#!/bin/sh
# Translate the GNU tar invocations rbuild uses into Rhapsody pax.
# GNU tar 1.12 ignores POSIX ustar prefix fields, so pax-created APKs
# lose names longer than 100 bytes on extract.
#
# Supported:
#   pax-gnutar.sh -tf -
#   pax-gnutar.sh -C ROOT -xf -
#   pax-gnutar.sh -C ROOT -cf - MEMBER...

dir=
op=
files=

while [ $# -gt 0 ]; do
    case "$1" in
        -C)
            shift
            if [ $# -lt 1 ]; then
                echo "pax-gnutar: -C requires a directory" >&2
                exit 2
            fi
            dir=$1
            ;;
        -tf)
            op=list
            ;;
        -xf)
            op=extract
            ;;
        -cf)
            op=create
            ;;
        -)
            ;;
        *)
            files="$files $1"
            ;;
    esac
    shift
done

case "$op" in
    list)
        exec /bin/pax
        ;;
    extract)
        if [ -z "$dir" ]; then
            echo "pax-gnutar: extract requires -C" >&2
            exit 2
        fi
        cd "$dir" || exit 1
        exec /bin/pax -r
        ;;
    create)
        if [ -z "$dir" ]; then
            echo "pax-gnutar: create requires -C" >&2
            exit 2
        fi
        if [ -z "$files" ]; then
            echo "pax-gnutar: create requires a member" >&2
            exit 2
        fi
        cd "$dir" || exit 1
        set -- $files
        exec /bin/pax -w -x ustar "$@"
        ;;
    *)
        echo "pax-gnutar: need -tf, -xf, or -cf" >&2
        exit 2
        ;;
esac
