#Requires -Version 5.0
param (
    [Parameter(Mandatory = $True, HelpMessage = "Directory that contains the source images.")]
    [ValidateNotNullOrEmpty()]
    [string] $srcdir,
    [Parameter(Mandatory = $True, HelpMessage = "Artist name to be used for copyright notices.")]
    [ValidateNotNullOrEmpty()]
    [string] $artist,
    [Parameter(HelpMessage = "Optional: Destination directory.")]
    [string] $destdir,
    [Parameter(HelpMessage = "Optional: md/m - Group by month-day or month. Default: md")]
    [string] $groupby,
    [Parameter(HelpMessage = "Optional: Camera name or nickname. Used as a suffix in destdir.")]
    [string] $device,
    [Parameter(HelpMessage = "Optional: Time offset in hours to fall back.")]
    [string] $fallBackTime,
    [Parameter(HelpMessage = "Optional: Time offset in hours to spring ahead.")]
    [string] $springForwardTime,
    [switch] $skipCopyright,
    [switch] $skipRotate,
    [string] $keywords
)

function sanityCheck
{
    ForEach ($UTIL in $UTILS.KEYS)
    {
        if (!( Test-Path $UTILDIR\$UTIL))
        {
            Write-Error "$UTILDIR\$UTIL not found - $( $UTILS.$UTIL )" -ErrorAction Stop
        }
    }

    if (!( Test-Path -path $srcdir))
    {
        Write-Error "$srcdir doesn't exist. Provide a valid directory with source images." -ErrorAction Stop
    }

    if (!( Test-Path $PSScriptRoot\cameraModels.psd1))
    {
        Write-Error "$PSScriptRoot\cameraModels.psd1 doesn't exist." -ErrorAction Stop
    }
}

function genCustomTagConfig
{
    $CAMS = Import-PowerShellDataFile $PSScriptRoot\cameraModels.psd1
    Add-Content $CUSTOMTAGS "%Image::ExifTool::UserDefined = ("
    Add-Content $CUSTOMTAGS "`t'Image::ExifTool::Composite' => {"
    Add-Content $CUSTOMTAGS "`t`tCamName => {"
    Add-Content $CUSTOMTAGS "`t`t`tRequire => 'Model',"
    Add-Content $CUSTOMTAGS "`t`t`tValueConv => '`$val[0]',"
    Add-Content $CUSTOMTAGS "`t`t`t# replace model with nickname"
    Add-Content $CUSTOMTAGS "`t`t`tPrintConv => {"

    ForEach ($CAM in $CAMS.KEYS)
    {
        # Add something like: "`t`t`t`t'COOLPIX L3' => 'L3',"
        Add-Content $CUSTOMTAGS "`t`t`t`t'$CAM' => '$( $CAMS.$CAM )',"
    }

    Add-Content $CUSTOMTAGS "`t`t`t},"
    Add-Content $CUSTOMTAGS "`t`t},"
    Add-Content $CUSTOMTAGS "`t},"
    Add-Content $CUSTOMTAGS ");"
    Add-Content $CUSTOMTAGS "%Image::ExifTool::UserDefined::Options = ("
    # QuickTime Date/Times are in UTC - http://u88.n24.queensu.ca/exiftool/forum/index.php?topic=7992.0
    Add-Content $CUSTOMTAGS "`t'QuickTimeUTC' => 1,"
    Add-Content $CUSTOMTAGS ");"
    Add-Content $CUSTOMTAGS "1; #end"
}

function genCopyrightConfig
{
    Add-Content $COPYRIGHT "-r" # recursive
    Add-Content $COPYRIGHT "-P" # preserve date/time stamp
    Add-Content $COPYRIGHT "-overwrite_original"
    Add-Content $COPYRIGHT "-progress"
    Add-Content $COPYRIGHT "-d" # date format
    Add-Content $COPYRIGHT "%Y" # year
    Add-Content $COPYRIGHT "-Copyright<Copyright `$createdate, $artist. All rights reserved."
    Add-Content $COPYRIGHT "-CopyrightNotice<Copyright `$createdate, $artist. All rights reserved."
    Add-Content $COPYRIGHT "-Rights<Copyright `$createdate, $artist. All rights reserved."
    Add-Content $COPYRIGHT "-Artist=$artist"
    # To prevent duplication when adding new items
    if (!([string]::IsNullOrEmpty($keywords)))
    {
        Add-Content $COPYRIGHT "-keywords-=$keywords -keywords+=$keywords"
    }
}

function adjustTime
{
    if ($fallBackTime -and $springForwardTime)
    {
        Write-Host "WARNING: Both backward and forward time adjustments requested. Time will be adjusted backward and then forward." `
    -Foregroundcolor Yellow -Backgroundcolor Black
    }
    if ($fallBackTime)
    {
        Write-Host "Time adjust: -$fallBackTime in  " $srcdir -Foregroundcolor Yellow -Backgroundcolor Black
        &$UTILDIR\exiftool.exe -m -stay_open 1 -f -progress -overwrite_original -ext jpg -ext cr2 -r -P "-AllDates-=$fallBackTime" $srcdir
    }

    if ($springForwardTime)
    {
        Write-Host "Time adjust: +$springForwardTime in  " $srcdir -Foregroundcolor Yellow -Backgroundcolor Black
        &$UTILDIR\exiftool.exe -m -stay_open 1 -f -progress -overwrite_original -ext jpg -ext cr2 -r -P "-AllDates+=$springForwardTime" $srcdir
    }
}

function renameFiles
{
    Write-Host "Renaming and copying photos from " $srcdir " to " $destdir

    # Default to grouping by month-day: Example - 2019/1030/xxx
    $destinationTemplate = "$destdir/%Y/%m%d/%Y%m%d-%H%M%S-%%f-%%.3nc-"

    if ( $groupby.Equals("m") )
    {
        # Optionally group by month: Example - 2019/10 - October/xxx
        Write-Host "Image grouping: Y/m - B/Ymd-HMS-f-i" -Foregroundcolor Yellow -Backgroundcolor Black
        $destinationTemplate = "$destdir/%Y/`"%m - %B`"/%Y%m%d-%H%M%S-%%f-%%.3nc-"
    }
    else
    {
        Write-Host "Default image grouping: Y/md/Ymd-HMS-f-i" -Foregroundcolor Green -Backgroundcolor Black
    }

    # If a date/time tag specified by -filename doesn't exist, then the option is ignored,
    # and the last one of these with a valid date/time tag will override earlier ones.
    # http://u88.n24.queensu.ca/exiftool/forum/index.php?topic=7992.0

    Write-Host "Processing images in " $srcdir

    &$UTILDIR\exiftool.exe -config $CUSTOMTAGS -stay_open 1 -f -progress -ext jpg -ext cr2 -r -P `
  -o $destdir/%e-files/%f/ -d $destinationTemplate "-filename<`${FileModifyDate}`${CamName}.%le" `
  "-filename<`${GPSDateTime}`${CamName}.%le" "-filename<`${MediaCreateDate}`${CamName}.%le" `
  "-filename<`${DateTimeOriginal}`${CamName}.%le" "-filename<`${CreateDate}`${CamName}.%le" $srcdir

    Write-Host "Processing videos "

    &$UTILDIR\exiftool.exe -config $CUSTOMTAGS -stay_open 1 -f -progress -ext mov -ext mp4 -r -P `
  -o $destdir/%e-files/%f/ -d $destinationTemplate "-filename<`${FileModifyDate}`${CamName}.%le" `
  "-filename<`${GPSDateTime}`${CamName}.%le" "-filename<`${MediaCreateDate}`${CamName}.%le" `
  "-filename<`${DateTimeOriginal}`${CamName}.%le" "-filename<`${CreateDate}`${CamName}.%le" $srcdir

    Remove-Item $CUSTOMTAGS
}

function addCopyright
{
    if ($skipCopyright)
    {
        Write-Host "Skipping copyright update" -Foregroundcolor Yellow -Backgroundcolor Black
        return
    }

    Write-Host "Updating copyright information for photos in " $destdir
    &$UTILDIR\exiftool.exe -m -@ $COPYRIGHT $destdir
    Remove-Item $COPYRIGHT
}

function autoRotateImages
{
    if ($skipRotate)
    {
        Write-Host "Skipping auto-rotate" -Foregroundcolor Yellow -Backgroundcolor Black
        return
    }
    if (!( Test-Path -path $destdir))
    {
        Write-Error "Skipping auto-rotate of images - destination directory not found!" -ErrorAction Stop
    }
    Write-Host "Rotating files in " $destdir " using EXIF orientation info"
    &$UTILDIR\jhead.exe -ft -autorot $destdir\**\*.jpg
}


$script:startTime = get-date

$TODAY = get-date -f yyyyMMdd
$NOW = get-date -f yyyyMMdd-HHmmss
$CURRUSER = [Environment]::UserName
$DESKTOP = "C:\Users\$CURRUSER\Desktop"
$UTILDIR = "C:\Users\$CURRUSER\Dropbox\Utils"
$UTILS = @{
    'exiftool.exe' = 'http://www.sno.phy.queensu.ca/~phil/exiftool/';
    'jhead.exe' = 'http://www.sentex.net/~mwandel/jhead/';
    'jpegtran.exe' = 'http://jpegclub.org/jpegtran/';
}

if ( [string]::IsNullOrEmpty($destdir))
{
    $destdir = "$DESKTOP\PhotosTODO-$TODAY"
}
else
{
    $destdir = "$destdir\PhotosTODO-$TODAY"
}

if (!([string]::IsNullOrEmpty($device)))
{
    $destdir = "$destdir-$device"
}


$COPYRIGHT = "$destdir\exiftool-copyright-$NOW.txt"
$CUSTOMTAGS = "$destdir\exiftool-customtags-$NOW.txt"

if (( Test-Path -path $destdir\PhotosTODO-$TODAY))
{
    $destdir = "$destdir\PhotosTODO-$NOW"
}

if (!(Test-Path -Path $destdir))
{
    New-Item -Force -ItemType directory -Path $destdir
}

sanityCheck
genCustomTagConfig
genCopyrightConfig
adjustTime
renameFiles
addCopyright
autoRotateImages
$elapsedTime = $( get-date ) - $script:StartTime
$elapsedTime = [string]::format("{0} days {1} hours {2} mins {3}.{4} secs",  `
   $elapsedTime.Days, $elapsedTime.Hours, $elapsedTime.Minutes, $elapsedTime.Seconds, $elapsedTime.Milliseconds)
Write-Host "Elapsed time: $elapsedTime"
