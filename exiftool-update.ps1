#Requires -RunAsAdministrator

$CURRUSER = [Environment]::UserName
$DROPBOX = "C:\Users\$CURRUSER\Dropbox\Utils"
$GEOSETTER = "C:\Program Files (x86)\GeoSetter\tools"

$CURRVER = Invoke-WebRequest -Uri https://exiftool.org/ver.txt | Select-Object -Expand Content

Invoke-WebRequest -Uri https://exiftool.org/exiftool-${CURRVER}.zip -OutFile exiftool-${CURRVER}.zip
Expand-Archive -Force exiftool-${CURRVER}.zip -DestinationPath "${DROPBOX}\"

If (Test-Path "${DROPBOX}\exiftool.exe") { Remove-Item -Force "${DROPBOX}\exiftool.exe" }
Move-Item -Path "${DROPBOX}\exiftool(-k).exe" -Destination "${DROPBOX}\exiftool.exe"

If (Test-Path "${GEOSETTER}\exiftool.exe") { Remove-Item -Force "${GEOSETTER}\exiftool.exe" }
Copy-Item -Force -Path "${DROPBOX}\exiftool.exe" -Destination "${GEOSETTER}\"

Remove-Item -Force exiftool-${CURRVER}.zip

