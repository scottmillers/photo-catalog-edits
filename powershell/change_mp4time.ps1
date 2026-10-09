<#

Use> ps change_mp4time.ps1 "Path"

Used to recursively traverse through a directory looking for mp4 file and when found sets multiple dates on the files

This was created so that all our family movies can be viewed and played in Amazon Photos

Requires: Exiftool to encode metadata to new file
#>

param([string]$path)

if (-not($path)) {
Throw "You must supply a value for the path"
}


Get-ChildItem -Path $path\* -Include *.mp4 -Recurse -Force | 
foreach-object { 
    
  
    $time = $_.LastWriteTime.ToString("yyyy:MM:dd HH:mm:ss");
    
    
    write-output "$_"
    write-output "$time"
    
    &"C:\ProgramData\chocolatey\bin\exiftool.exe" -overwrite_original -FileCreateDate="$time" -FileModifyDate="$time" -quicktime:CreateDate="$time" -quicktime:ModifyDate="$time" -quicktime:mediacreatedate="$time" -quicktime:mediamodifydate="$time" "$_"
}