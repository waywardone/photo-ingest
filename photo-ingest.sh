#!/bin/bash

usage()
{
    printf "Usage: $0 [-h]\n"
    printf "\t-a <artist>\tname to use in copyright notices.\n"
    printf "\t-c <comment>\toptional - suffix for destdir.\n"
    printf "\t-d <destdir>\toptional - specify a destination directory. Defaults to PhotosTODO-YYYYmmdd.\n"
    printf "\t-g grouping\toptional - 'm' or 'md'. Defaults to 'md'.\n"
    printf "\t-h\t\tprint this help screen.\n"
    printf "\t-s <srcdir>\tspecify source directory with images/videos.\n"
    printf "\t-t <h>\t\toffset picture dates by <h> hours (int or float). +h to jump forward and -h to fall back.\n"
    exit 1;
}

checkos()
{
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        return
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Mac OSX
        { echo >&2 "OS $OSTYPE not supported. Aborting."; exit 1; }
    elif [[ "$OSTYPE" == "cygwin" ]]; then
        # POSIX compatibility layer and Linux environment emulation for Windows
        { echo >&2 "OS $OSTYPE not supported. Aborting."; exit 1; }
    elif [[ "$OSTYPE" == "msys" ]]; then
        # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
        { echo >&2 "OS $OSTYPE not supported. Aborting."; exit 1; }
    elif [[ "$OSTYPE" == "win32" ]]; then
        # I'm not sure this can happen.
        { echo >&2 "OS $OSTYPE not supported. Aborting."; exit 1; }
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        # ...
        { echo >&2 "OS $OSTYPE not supported. Aborting."; exit 1; }
    else
        # Unknown.
        { echo >&2 "Unhandled OS $OSTYPE not supported. Aborting."; exit 1; }
    fi
}

prereqs()
{
    checkos
    REQUIREMENTS="exiftool jhead jpegtran"
    for r in $REQUIREMENTS
    do
        # Ref: https://stackoverflow.com/questions/592620
        hash $r 2>/dev/null || { echo >&2 "$r is not installed. Aborting."; exit 1; }
    done

    # Check mandatory arguments
    [[ ! -z $srcdir ]] || { echo >&2 "srcdir not specified. Aborting."; usage; }
    [[ ! -z $artist ]] || { echo >&2 "Copyright name not specified. Aborting."; usage; }

    # Check source directory
    [[ -d $srcdir ]] || { echo >&2 "$srcdir doesn't exist. Aborting."; exit 1; }
}

genCustomTags()
{
    # The heredoc uses tabs for indents
    # http://tldp.org/LDP/abs/html/here-docs.html
    # https://stackoverflow.com/questions/9104706
    cat > $customtags <<EOM
	%Image::ExifTool::UserDefined::Options = (
		# QuickTime Date/Times are in UTC
		# http://u88.n24.queensu.ca/exiftool/forum/index.php?topic=7992.0
		'QuickTimeUTC' => 1,
		# Needed for some MOV files
		# https://sno.phy.queensu.ca/~phil/exiftool/ExifTool.html#ExtractEmbedded
		'ExtractEmbedded' => 1,
	);
	%Image::ExifTool::UserDefined = (
		'Image::ExifTool::Composite' => {
			CamName => {
				Require => 'Model',
				ValueConv => '\$val[0]',
				# replace model with nickname
				PrintConv => {
EOM
    # https://stackoverflow.com/questions/4990575
    while IFS="=" read -r key value; do
        case "$key" in
            '#'*);; # Skip comments
            *)
                printf "\t\t\t\t\t%s\n" "$key => $value," >> $customtags
        esac
    done < photo-ingest-deviceData.props

    cat >> $customtags <<EOM
				},
			},
		},
	);
	1; #end
EOM
    # Remove first tab introduced as a result of indentation in heredocs above
    sed -i 's/\t//1' $customtags
}

genCopyrightConfig()
{
    # The heredoc *must* use tabs for all indents including the delimiter
    # http://tldp.org/LDP/abs/html/here-docs.html
    # https://stackoverflow.com/questions/9104706
    cat > $copyrightcfg <<-EOM
	-r
	-P
	-overwrite_original
	-progress
	-d
	%Y
	-Copyright<Copyright \$createdate, $artist. All rights reserved.
	-CopyrightNotice<Copyright \$createdate, $artist. All rights reserved.
	-Rights<Copyright \$createdate, $artist. All rights reserved.
	-Artist=$artist
	EOM
}

adjustTime()
{
    if [[ -z $timeoffset ]]; then
        return
    fi

    case "$timeoffset" in
        '+'*)
            # Jump forward by $timeoffset
            printf "Moving forward by ${timeoffset#*+} hours in $srcdir\n"
            exiftool -m -stay_open 1 -f -progress -overwrite_original -ext jpg -ext cr2 -r -P "-AllDates+=${timeoffset#*+}" $srcdir
            ;;
        '-'*)
            # Fall back by $timeoffset
            printf "Falling back by ${timeoffset#*-} hours in $srcdir\n"
            exiftool -m -stay_open 1 -f -progress -overwrite_original -ext jpg -ext cr2 -r -P "-AllDates-=${timeoffset#*-}" $srcdir
            ;;
        *)
            { echo >&2 "Unsupported time offset $timeoffset. Aborting."; exit 1; }
    esac

}

renameFiles()
{
    printf "Renaming and copying photos from $srcdir to $destdir\n"

    case "$groupby" in
        m|M)
            # Group by month: Example - 2019/10 - October/xxx
            destGroup="$destdir/%Y/\"%m - %B\"/%Y%m%d-%H%M%S-%%f-%%.3nc-"
            printf "Grouping by month: Y/m -B/Ymd-HMS-f-i\n"
        ;;
        *)
            destGroup="$destdir/%Y/%m%d/%Y%m%d-%H%M%S-%%f-%%.3nc-"
            # Default to grouping by month-day: Example - 2019/1030/xxx
            printf "Grouping by month-day: Y/md/Ymd-HMS-f-i\n"
        ;;
    esac


    # If a date/time tag specified by -filename doesn't exist, then the option is ignored,
    # and the last one of these with a valid date/time tag will override earlier ones.
    # http://u88.n24.queensu.ca/exiftool/forum/index.php?topic=7992.0
    exiftool -config $customtags -stay_open 1 -f -progress -r -P \
        -ext jpg -ext cr2 -ext mov -ext mp4 \
        -o $destdir/%e-files/%f/ -d $destGroup "-filename<\${FileModifyDate}\${CamName}.%le" \
        "-filename<\${GPSDateTime}\${CamName}.%le" "-filename<\${MediaCreateDate}\${CamName}.%le" \
        "-filename<\${DateTimeOriginal}\${CamName}.%le" "-filename<\${CreateDate}\${CamName}.%le" \
        $srcdir

    rm -f $customtags
}

addCopyright()
{
    printf "Updating copyright information in $destdir\n"
    exiftool -m -@ $copyrightcfg $destdir
    rm -f $copyrightcfg
}

autoRotate()
{
    printf "Rotating files in $destdir using EXIF orientation info\n"
    shopt -s globstar
    jhead -ft -autorot $destdir/**/*.jpg
}

main()
{
    SECONDS=0
    prereqs
    today=$(date +%Y%m%d)
    now=$(date +%Y%m%d-%H%M%S)
    desktop="/home/${USER}/Desktop"

    [[ -z $destdir ]] && destdir="${desktop}/PhotosTODO-${today}"
    [[ ! -z $comment ]] && destdir="${destdir}-${comment}"

    copyrightcfg="${destdir}/exiftool-copyright-$now.txt"
    customtags="${destdir}/exiftool-customtags-$now.txt"

    mkdir -p $destdir

    genCopyrightConfig
    genCustomTags
    adjustTime
    renameFiles
    addCopyright
    autoRotate
    # https://unix.stackexchange.com/questions/27013/displaying-seconds-as-days-hours-mins-seconds
    eval "echo $(date -ud "@$SECONDS" +'Time elapsed: $((%s/3600/24)) days %H hours %M mins %S secs')"
}

while getopts "a:c:d:g:hs:t:" options; do
    case $options in
        a) artist=$OPTARG;;
        c) comment=$OPTARG;;
        d) destdir=$OPTARG;;
        g) groupby=$OPTARG;;
        h) usage;;
        s) srcdir=$OPTARG;;
        t) timeoffset=$OPTARG;;
        \?) usage;;
        *) usage;;
    esac
done
shift $((OPTIND-1))

main
