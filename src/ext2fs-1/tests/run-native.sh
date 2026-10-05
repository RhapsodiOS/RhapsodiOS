#!/bin/sh
# Run from the directory containing mount_ext2fs and ext2_io.
set -e
case "$1" in
tiny)
    test "$#" = 2
    test -b /dev/hd1b || mknod /dev/hd1b b 3 9
    test -b /dev/hd1c || mknod /dev/hd1c b 3 10
    test -b /dev/hd1d || mknod /dev/hd1d b 3 11
    ./ext2_io tiny "$2"
    ;;
readonly)
    test "$#" = 3
    i=0
    while test "$i" -lt 2; do
        ./mount_ext2fs -o ro "$2" "$3"
        if ./ext2_io readonly "$3"; then
            umount "$3"
        else
            status=$?
            umount "$3" || :
            exit "$status"
        fi
        i=`expr "$i" + 1`
    done
    ;;
capacity512|capacity1024)
    test "$#" = 3
    sector=`echo "$1" | sed 's/capacity//'`
    for spec in 'rhd1a 8' 'rhd1b 9' 'rhd1c 10' 'rhd1g 14' 'rhd1h 15'; do
        set -- "$@" $spec
        test -c "/dev/$4" || mknod "/dev/$4" c 15 "$5"
        set -- "$1" "$2" "$3"
    done
    ./partition_info /dev/hd1a /dev/rhd1a /dev/rhd1h /dev/rhd1g /dev/rhd1b /dev/rhd1c "$sector" "$2" 512 "$3"
    echo "EXT2_OK $1"
    ;;
*) echo "usage: run-native.sh readonly DEVICE MOUNT_POINT | tiny MOUNT_POINT | capacity512|capacity1024 PARTITION_BLOCKS DRIVE_SECTORS" >&2; exit 2 ;;
esac
