<#

Use> ps change_filetimes.ps1 "FilePath" <"TimeString">

Used to change the times that are set on a Image or Video file.  If a time is not provided on the command line use the last write time from the file 

This was created so that all our family movies can be viewed and played in Amazon Photos

Requires: Exiftool to encode metadata to new file
#>

param([string]$fileName, [string]$time)

if (-not($fileName)) {
Throw "You must supply a value for the file"
}



# if you don't set the time get it from the file
if (-not($time)) {
    $time = (Get-Item $fileName).LastWriteTime.ToString("yyyy:MM:dd HH:mm:ss");
}

write-output "$fileName"
write-output "$time"
    
&"C:\ProgramData\chocolatey\bin\exiftool.exe" -overwrite_original -FileCreateDate="$time" -FileModifyDate="$time" -quicktime:CreateDate="$time" -quicktime:ModifyDate="$time" -quicktime:mediacreatedate="$time" -quicktime:mediamodifydate="$time" "$fileName"


