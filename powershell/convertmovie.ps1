<#

Use> ps convertmovie.ps1 "Path"

Used to recursively traverse through a directory looking for movie files and when found converts them to MPEG4 format and adds metadata

This was created so that all our family movies can be viewed and played in Amazon Photos

Requires: HandBrake to convert to movie encoding
Requires: Exiftool to encode metadata to new file
#>
param([string]$path)

if (-not($path)) {
Throw "You must supply a value for the path"
}


Get-ChildItem -Path $path\* -Include *.mts, *.MOV, *.avi, *.wmv -Recurse -Force | 
foreach-object { 
    $newfile = $_.Path + $_.DirectoryName + "\" + $_.BaseName + "-convert.mp4"; 
    $time = $_.LastWriteTime.ToString("yyyy:MM:dd HH:mm:ss");
    write-output "$_"
    &"C:\Program Files\HandBrake\HandBrakeCLI.exe" -i "$_" -o "$newfile" --preset "Fast 1080p30" 
    
    &"C:\Program Files\exiftool-10.40\exiftool.exe" -overwrite_original -FileCreateDate="$time" -FileModifyDate="$time" -quicktime:CreateDate="$time" -quicktime:ModifyDate="$time" -quicktime:mediacreatedate="$time" -quicktime:mediamodifydate="$time" "$newfile"
}