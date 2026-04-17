#!/bin/bash

set -euo pipefail

ALL_STEPS="time,rename,copyright,rotate"

usage()
{
    cat <<-EOM
    Usage: $0 [-h]
        -a <artist>   name to use in copyright notices.
        -c <comment>  optional - suffix for destdir.
        -d <destdir>  optional - specify a destination directory. Defaults to PhotosTODO-YYYYmmdd.
        -g grouping   optional - 'm' or 'md'. Defaults to 'md'.
        -h            print this help screen.
        -n            dry run - show resolved configuration and steps, then exit.
        -s <srcdir>   specify source directory with images/videos.
        -S <steps>    optional - comma-separated list of steps to run.
                      Valid steps: time,rename,copyright,rotate
                      Default: all ($ALL_STEPS)
        -t <h>        offset picture dates by <h> hours (int or float). +h to jump forward and -h to fall back.
	EOM
    exit 1
}

logD()
{
    printf '%s%s%s\n' "$(tput setaf 4)" "${1:-}" "$(tput sgr0)" >&2
}

logE()
{
    printf '%s%s%s\n' "$(tput setaf 1)" "${1:-}" "$(tput sgr0)" >&2
}

logI()
{
    printf '%s%s%s\n' "$(tput setaf 2)" "${1:-}" "$(tput sgr0)" >&2
}

logW()
{
    printf '%s%s%s\n' "$(tput setaf 3)" "${1:-}" "$(tput sgr0)" >&2
}

run_step() { [[ ",$steps," == *",$1,"* ]]; }

validate_steps()
{
    local valid="time rename copyright rotate"
    IFS=',' read -ra requested <<< "$steps"
    for s in "${requested[@]}"; do
        local found=false
        for v in $valid; do
            [[ "$s" == "$v" ]] && found=true && break
        done
        if ! $found; then
            logE "Invalid step '$s'. Valid steps: $valid"
            exit 1
        fi
    done
}

checkos()
{
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        logE "OS $OSTYPE not supported. Only linux-gnu is supported. Aborting."
        exit 1
    fi
}

prereqs()
{
    checkos

    # Always required
    [[ -n $srcdir ]] || { logE "srcdir not specified. Aborting."; usage; }
    [[ -d $srcdir ]] || { logE "$srcdir doesn't exist. Aborting."; exit 1; }

    # exiftool is needed for time, rename, copyright, and rotate steps
    if run_step time || run_step rename || run_step copyright || run_step rotate; then
        command -v exiftool >/dev/null 2>&1 || { logE "exiftool is not installed. Aborting."; exit 1; }
    fi

    # jpegtran is needed for rotate
    if run_step rotate; then
        command -v jpegtran >/dev/null 2>&1 || { logE "jpegtran is not installed. Aborting."; exit 1; }
    fi

    # artist is only needed for copyright
    if run_step copyright; then
        [[ -n $artist ]] || { logE "Copyright name not specified. Aborting."; usage; }
    fi

    # deviceData.props is only needed for rename
    if run_step rename; then
        [[ -f "photo-ingest-deviceData.props" ]] || { logE "photo-ingest-deviceData.props not found. Aborting."; exit 1; }
    fi
}

genCustomTags()
{
    # The heredoc uses tabs for indents
    # http://tldp.org/LDP/abs/html/here-docs.html
    # https://stackoverflow.com/questions/9104706
    cat > "$customtags" <<-EOM
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
                printf "\t\t\t\t\t%s\n" "$key => $value," >> "$customtags"
        esac
    done < photo-ingest-deviceData.props

    cat >> "$customtags" <<EOM
				},
			},
		},
	);
	1; #end
EOM
}

genCopyrightConfig()
{
    # The heredoc *must* use tabs for all indents including the delimiter
    # http://tldp.org/LDP/abs/html/here-docs.html
    # https://stackoverflow.com/questions/9104706
    cat > "$copyrightcfg" <<-EOM
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
    [[ -z $timeoffset ]] && return

    local sign="${timeoffset:0:1}"
    local hours="${timeoffset:1}"
    [[ "$sign" == "+" || "$sign" == "-" ]] || { logE "Unsupported time offset $timeoffset. Aborting."; exit 1; }
    logI "Adjusting time by ${timeoffset} hours in $srcdir"
    exiftool -m -f -progress -overwrite_original -ext jpg -ext cr2 -r -P "-AllDates${sign}=${hours}" "$srcdir"
}

renameFiles()
{
    logI "Renaming and copying photos from $srcdir to $destdir"

    case "$groupby" in
        m|M)
            # Group by month: Example - 2019/10 - October/xxx
            destGroup="$destdir/%Y/\"%m - %B\"/%Y%m%d-%H%M%S-%%f-%%.3nc-"
            logD "Grouping by month: Y/m -B/Ymd-HMS-f-i"
        ;;
        md|MD)
            destGroup="$destdir/%Y/%m%d/%Y%m%d-%H%M%S-%%f-%%.3nc-"
            # Default to grouping by month-day: Example - 2019/1030/xxx
            logD "Grouping by month-day: Y/md/Ymd-HMS-f-i"
        ;;
        *)
            logE "Invalid groupby value: $groupby. Use 'm' or 'md'."
            exit 1
        ;;
    esac


    # If a date/time tag specified by -filename doesn't exist, then the option is ignored,
    # and the last one of these with a valid date/time tag will override earlier ones.
    # http://u88.n24.queensu.ca/exiftool/forum/index.php?topic=7992.0
    exiftool -config "$customtags" -f -progress -r -P \
        -ext jpg -ext cr2 -ext mov -ext mp4 \
        -o "$destdir"/%e-files/%f/ -d "$destGroup" "-filename<\${FileModifyDate}\${CamName}.%le" \
        "-filename<\${GPSDateTime}\${CamName}.%le" "-filename<\${MediaCreateDate}\${CamName}.%le" \
        "-filename<\${DateTimeOriginal}\${CamName}.%le" "-filename<\${CreateDate}\${CamName}.%le" \
        "$srcdir"
}

addCopyright()
{
    logI "Updating copyright information in $workdir"
    exiftool -q -q -m -@ "$copyrightcfg" "$workdir"
}

autoRotate()
{
    logI "Rotating files in $workdir using EXIF orientation info"
    shopt -s globstar nullglob nocaseglob
    local files=("$workdir"/**/*.jpg)
    shopt -u nocaseglob
    if (( ${#files[@]} == 0 )); then
        logW "No JPEG files found in $workdir"
        return
    fi

    local total=${#files[@]}
    local current=0
    local rotated=0
    local skipped=0
    logI "Found $total JPEG file(s) to check for rotation"

    local progress_interval=$(( total / 20 ))
    (( progress_interval < 10 )) && progress_interval=10

    for f in "${files[@]}"; do
        current=$((current + 1))
        if (( current % progress_interval == 0 )); then
            logD "  [$current/$total] Processing..."
        fi

        # Read orientation; skip if already normal or unset
        local orient
        orient=$(exiftool -n -s3 -Orientation "$f" 2>/dev/null) || continue
        if [[ -z "$orient" || "$orient" == "1" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        local transform="" orient_label=""
        case "$orient" in
            2) transform="-flip horizontal";  orient_label="Mirror horizontal";;
            3) transform="-rotate 180";       orient_label="Rotate 180";;
            4) transform="-flip vertical";    orient_label="Mirror vertical";;
            5) transform="-transpose";        orient_label="Mirror horizontal and rotate 270 CW";;
            6) transform="-rotate 90";        orient_label="Rotate 90 CW";;
            7) transform="-transverse";       orient_label="Mirror horizontal and rotate 90 CW";;
            8) transform="-rotate 270";       orient_label="Rotate 270 CW";;
            *) logW "Unknown orientation $orient for '$f'"; continue;;
        esac

        # jpegtran writes to a temp file; create it alongside the
        # original so it's always on the same filesystem.
        local tmpfile
        tmpfile=$(mktemp "${f}.XXXXXX") || { logW "Nonfatal: mktemp failed for '$f'"; continue; }
        # unquoted vars in jpegtran invocation is intentional
        # $transform can be `-flip horizontal`, etc. These are two separate
        # arguments that jpegtran expects as separate words.
        # shellcheck disable=SC2086
        if jpegtran -copy all -trim $transform -outfile "$tmpfile" "$f"; then
            touch -r "$f" "$tmpfile"
            mv -f "$tmpfile" "$f"
            # Clear orientation tag and set file timestamp from EXIF
            exiftool -q -q -m -P -overwrite_original \
                '-Orientation=Horizontal (normal)' \
                '-FileModifyDate<DateTimeOriginal' \
                "$f" || logW "Nonfatal: exiftool post-rotate failed on '$f'"
            rotated=$((rotated + 1))
            logD "  [$current/$total] Rotated ($orient_label): ${f##*/}"
        else
            logW "Nonfatal: jpegtran failed on '$f'"
            rm -f "$tmpfile"
        fi
    done
    logI "Rotation complete: $rotated rotated, $skipped already normal, $((total - rotated - skipped)) skipped/failed"
}

dryRun()
{
    if run_step rename; then
        workdir="$destdir"
    else
        workdir="$srcdir"
    fi

    local destdir_display="$destdir"
    run_step rename || destdir_display="(not used - rename step skipped)"

    local offset_display="${timeoffset:-(none)}"
    local groupby_display="$groupby"
    case "$groupby" in
        m|M)  groupby_display="$groupby (Y/m - B/Ymd-HMS-f-i)";;
        md|MD) groupby_display="$groupby (Y/md/Ymd-HMS-f-i)";;
    esac

    cat >&2 <<-EOM
	[dry-run] photo-ingest configuration:
	  artist:       $artist
	  srcdir:       $srcdir
	  destdir:      $destdir_display
	  groupby:      $groupby_display
	  timeoffset:   $offset_display
	  steps:        $steps
	  workdir:      $workdir
	EOM

    logD "[dry-run] step plan:"
    local i=0
    for step_name in time rename copyright rotate; do
        i=$((i + 1))
        if run_step "$step_name"; then
            case "$step_name" in
                time)
                    if [[ -n "$timeoffset" ]]; then
                        logI "  $i. adjustTime      -> exiftool AllDates${timeoffset} on $srcdir"
                    else
                        logW "  $i. adjustTime      -> no offset specified, will be a no-op"
                    fi
                    ;;
                rename)    logI "  $i. renameFiles     -> copy from $srcdir to $destdir";;
                copyright) logI "  $i. addCopyright    -> apply to $workdir";;
                rotate)    logI "  $i. autoRotate      -> exiftool+jpegtran on $workdir";;
            esac
        else
            logW "  $i. $(printf '%-14s' "$step_name") -> SKIP"
        fi
    done

    logI "[dry-run] no changes made. Remove -n to execute."
}

main()
{
    SECONDS=0
    validate_steps
    prereqs
    today=$(date +%Y%m%d)
    desktop="${HOME}/Desktop"

    [[ -z $destdir ]] && destdir="${desktop}/PhotosTODO-${today}"
    [[ -n $comment ]] && destdir="${destdir}-${comment}"

    # Determine working directory for post-rename steps (copyright, rotate).
    # When rename is active, these operate on the destination.
    # When rename is skipped, they operate on the source in-place.
    if run_step rename; then
        workdir="$destdir"
    else
        workdir="$srcdir"
    fi

    if $dryrun; then
        dryRun
        exit 0
    fi

    customtags=$(mktemp /tmp/exiftool-customtags-XXXXXX)
    copyrightcfg=$(mktemp /tmp/exiftool-copyright-XXXXXX)
    trap 'rm -f "$customtags" "$copyrightcfg"' EXIT

    genCopyrightConfig
    genCustomTags

    if run_step time; then
        adjustTime
    else
        logW "Skipping time adjustment"
    fi

    if run_step rename; then
        mkdir -p "$destdir"
        renameFiles
    else
        logW "Skipping file rename"
    fi

    if run_step copyright; then
        addCopyright
    else
        logW "Skipping copyright update"
    fi

    if run_step rotate; then
        autoRotate
    else
        logW "Skipping auto-rotate"
    fi

    local h=$((SECONDS / 3600))
    local m=$(( (SECONDS % 3600) / 60 ))
    local s=$((SECONDS % 60))
    logI "Time elapsed: ${h}h ${m}m ${s}s"
}
artist=""
comment=""
destdir=""
dryrun=false
groupby="md"
srcdir=""
steps="$ALL_STEPS"
timeoffset=""
while getopts "a:c:d:g:hns:S:t:" options; do
    case $options in
        a) artist=$OPTARG;;
        c) comment=$OPTARG;;
        d) destdir=$OPTARG;;
        g) groupby=$OPTARG;;
        h) usage;;
        n) dryrun=true;;
        s) srcdir=$OPTARG;;
        S) steps=$OPTARG;;
        t) timeoffset=$OPTARG;;
        \?) usage;;
        *) usage;;
    esac
done
shift $((OPTIND-1))

main
