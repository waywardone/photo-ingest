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

prereqs()
{
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
	);
	%Image::ExifTool::UserDefined = (
		'Image::ExifTool::Composite' => {
			CamName => {
				Require => 'Model',
				ValueConv => \$val[0]',
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
	-Artist=$artist"
	EOM
}

main()
{
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
}

while getopts "o:s:d:a:c:hn" options; do
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
