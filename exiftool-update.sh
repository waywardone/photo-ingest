#!/bin/bash

main() {
    # Exit if not root - can't copy to /usr/local/bin otherwise
    if [[ $(id -u) -ne 0 ]] ; then echo "Run as sudo/root." ; exit 1 ; fi

    local CURRVER=$(curl -sL https://exiftool.org/ver.txt)
    local WORKDIR="/tmp"
    cd $WORKDIR
    curl -L https://github.com/exiftool/exiftool/archive/${CURRVER}.tar.gz | tar -xz
    # Update WSL copy
    cd exiftool-${CURRVER}
    perl Makefile.PL
    make test && make install

    cd $WORKDIR
    rm -rf exiftool-${CURRVER}
}

main "$@"
