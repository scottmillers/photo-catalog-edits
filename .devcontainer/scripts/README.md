# Dev container host setup scripts

## fix-podman-network-mount.ps1

Run this on the **Windows host** (not inside the container) if the dev
container fails to start with an error like:

```
Error: statfs /mnt/z: no such file or directory
```

This happens because `devcontainer.json` bind-mounts a Windows-mapped network
drive (`Z:\`, pointing at a NAS share) into the container. Podman Desktop on
Windows runs containers inside a WSL2 VM (`podman-machine-default`), and that
VM only auto-mounts local fixed drives (`C:`, etc.) — not mapped network
drives — so the bind mount fails.

The script fixes this by configuring the podman machine to automatically
mount the network share (via a systemd unit) before Podman's API service
starts, so the mount is in place every time the machine boots.

### Usage

```powershell
.\.devcontainer\scripts\fix-podman-network-mount.ps1
```

By default this targets drive `Z:` and machine `podman-machine-default`
(matching `devcontainer.json`). Override if needed:

```powershell
.\.devcontainer\scripts\fix-podman-network-mount.ps1 -DriveLetter Z -UncPath '\\MillersNAS\PlexMedia\Photos'
```

### When to run it

- The first time you set up this dev container on a new machine.
- Any time the podman machine is recreated (`podman machine rm` followed by
  `podman machine init`).
- If the network-drive mount ever stops working after a Windows/Podman
  update.

The script is safe to re-run; all steps are idempotent.
