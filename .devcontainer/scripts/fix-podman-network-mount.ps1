<#
.SYNOPSIS
    Fixes Podman/WSL2 so Dev Containers can bind-mount a Windows-mapped network
    drive (e.g. the Z: mount used in devcontainer.json).

.DESCRIPTION
    Podman Desktop on Windows runs containers inside a WSL2 VM
    ("podman-machine-default"). That VM only auto-mounts *local* fixed drives
    under /mnt/<letter> - mapped network drives (like Z: pointing at a NAS
    share) are not mounted automatically, which causes dev container startup
    to fail with:

        Error: statfs /mnt/z: no such file or directory

    Additionally, Podman's API service runs inside its own private mount
    namespace (created at machine boot), so a mount made from a plain
    `wsl -d podman-machine-default` shell is invisible to containers even
    after manually mounting the share.

    This script fixes both problems by creating a systemd .mount unit for the
    network share, plus a systemd override that makes podman.service depend
    on it, directly inside the podman machine's own systemd instance. This
    way the share is always (re-)mounted, in the right namespace, before
    Podman starts - including after a full "podman machine stop/start" or a
    Windows reboot.

    Safe to re-run; all steps are idempotent.

.PARAMETER DriveLetter
    The Windows drive letter mapped to a network share that is bind-mounted
    in .devcontainer/devcontainer.json (default: Z).

.PARAMETER UncPath
    The UNC path backing the drive letter, e.g. \\server\share. If omitted,
    it is auto-detected from the current mapping of -DriveLetter.

.PARAMETER MachineName
    The podman machine (WSL distro) name (default: podman-machine-default).

.EXAMPLE
    .\fix-podman-network-mount.ps1

.EXAMPLE
    .\fix-podman-network-mount.ps1 -DriveLetter Z -UncPath '\\MillersNAS\PlexMedia\Photos'

.NOTES
    Run this once after first setting up Podman on a new machine, and again
    any time the podman machine is recreated (e.g. "podman machine rm" then
    "podman machine init").
#>
[CmdletBinding()]
param(
    [string]$DriveLetter = 'Z',
    [string]$UncPath,
    [string]$MachineName = 'podman-machine-default'
)

$ErrorActionPreference = 'Stop'

$letter = $DriveLetter.TrimEnd(':').ToLower()
$mountPoint = "/mnt/$letter"
$unitName = "mnt-$letter.mount"

if (-not $UncPath) {
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($DriveLetter.TrimEnd(':')):'" |
        Where-Object { $_.DriveType -eq 4 -and $_.ProviderName }
    if (-not $disk) {
        throw "${DriveLetter}: is not a currently-connected mapped network drive. Pass -UncPath '\\server\share' explicitly."
    }
    $UncPath = $disk.ProviderName
}
$uncForLinux = $UncPath.Replace('\', '/')

Write-Host "Machine     : $MachineName"
Write-Host "Drive       : ${DriveLetter}: -> $UncPath"
Write-Host "Mount point : $mountPoint (systemd unit: $unitName)"

# Make sure the podman machine is running.
$machineInfo = podman machine list --format '{{.Name}}\t{{.Running}}' 2>$null
$isRunning = $machineInfo -split "`n" | Where-Object { $_ -match "^$([regex]::Escape($MachineName))\s+true$" }
if (-not $isRunning) {
    Write-Host "Starting podman machine '$MachineName'..."
    podman machine start $MachineName
}

function Invoke-Wsl {
    param([Parameter(Mandatory)][string[]]$CmdArgs)
    & wsl -d $MachineName -u root -- @CmdArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed inside $($MachineName): $($CmdArgs -join ' ')"
    }
}

function Write-WslFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Content))
    Invoke-Wsl -CmdArgs @('sh', '-c', "echo $b64 | base64 -d > $Path")
}

$mountUnit = @"
[Unit]
Description=Mount $UncPath (drvfs) for Dev Containers

[Mount]
What=$uncForLinux
Where=$mountPoint
Type=drvfs
Options=noauto

[Install]
WantedBy=multi-user.target
"@

$overrideConf = @"
[Unit]
Requires=$unitName
After=$unitName
"@

Write-Host "Writing systemd units inside the podman machine..."
Invoke-Wsl -CmdArgs @('mkdir', '-p', '/etc/systemd/system/podman.service.d')
Write-WslFile -Path "/etc/systemd/system/$unitName" -Content $mountUnit
Write-WslFile -Path "/etc/systemd/system/podman.service.d/mnt-$letter.conf" -Content $overrideConf

# podman.service runs inside its own nested systemd/mount namespace, created
# when the podman machine boots, which is separate from the namespace a plain
# `wsl -d <machine> --` shell attaches to. We must run systemctl *inside that
# namespace* (via nsenter on a process living there), or the new mount/unit
# won't be visible to containers.
Write-Host "Locating the podman machine's inner systemd instance..."
# Trigger podman's API once so its systemd instance is guaranteed to be fully up.
podman --connection $MachineName info *> $null

$innerPid = (Invoke-Wsl -CmdArgs @('sh', '-c', 'pgrep -f ''^/lib/systemd/systemd$'' | head -n1') 2>$null)
if ($innerPid -is [array]) { $innerPid = $innerPid[0] }
$innerPid = "$innerPid".Trim()
if (-not $innerPid) {
    throw "Could not find the podman machine's inner systemd process. Is '$MachineName' fully booted?"
}
Write-Host "Inner systemd PID: $innerPid"

Invoke-Wsl -CmdArgs @('nsenter', '-t', $innerPid, '-a', '--', 'systemctl', 'daemon-reload')
Invoke-Wsl -CmdArgs @('nsenter', '-t', $innerPid, '-a', '--', 'systemctl', 'enable', '--now', $unitName)
Invoke-Wsl -CmdArgs @('nsenter', '-t', $innerPid, '-a', '--', 'systemctl', 'restart', 'podman.service')

Write-Host "Verifying the mount is visible to containers..."
$verify = podman run --rm --cgroups=disabled --mount "type=bind,source=${DriveLetter}:\,target=/verify-mount,consistency=cached" alpine:latest sh -c "ls -A /verify-mount | wc -l" 2>&1
Write-Host "Entries visible in container: $verify"
if ($verify -match '^\s*0\s*$') {
    Write-Warning "The mount point appears empty inside containers. Double-check that $UncPath is reachable and the share allows access."
}
else {
    Write-Host "Success! Dev Containers can now bind-mount ${DriveLetter}: via Podman." -ForegroundColor Green
}
