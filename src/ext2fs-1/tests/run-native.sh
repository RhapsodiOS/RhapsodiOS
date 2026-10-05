#!/bin/sh
# Run from the directory containing mount_ext2fs and ext2_io.
set -e
case "$1" in
read-suite|malformed-suite|truncated-suite)
    test "$#" = 2
    suite="$1"
    point="$2"
    n=0
    for part in a b c d e f g; do
        if test "$part" = g && test "$suite" != malformed-suite; then break; fi
        minor=`expr 8 + "$n"`
        device="/dev/hd1$part"
        test -b "$device" || mknod "$device" b 3 "$minor"
        echo "suite partition $part"
        case "$suite" in
        read-suite)
            sh "$0" readonly "$device" "$point"
            sh "$0" mapping "$device" "$point"
            sh "$0" directory "$device" "$point"
            ;;
        malformed-suite)
            kind=directory
            if test "$n" -ge 5; then kind=indirect; fi
            sh "$0" malformed "$device" "$point" "$kind"
            ;;
        truncated-suite) ./ext2_io truncated "$device" "$point" ;;
        esac
        n=`expr "$n" + 1`
    done
    echo "EXT2_OK $suite"
    ;;
tiny)
    test "$#" = 2
    test -b /dev/hd1b || mknod /dev/hd1b b 3 9
    test -b /dev/hd1c || mknod /dev/hd1c b 3 10
    test -b /dev/hd1d || mknod /dev/hd1d b 3 11
    ./ext2_io tiny "$2"
    ;;
readonly|mapping|directory|malformed)
    scenario="$1"
    if test "$scenario" = malformed; then test "$#" = 4; else test "$#" = 3; fi
    i=0
    while test "$i" -lt 2; do
        ./mount_ext2fs -o ro "$2" "$3"
        if ./ext2_io "$scenario" "$3" ${4+"$4"}; then
            # realpath in the stock helper traverses corrupt dot entries.
            if test "$scenario" = malformed; then ./ext2_io unmount "$3"; else umount "$3"; fi
        else
            status=$?
            if test "$scenario" = malformed; then ./ext2_io unmount "$3" || :; else umount "$3" || :; fi
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
*) echo "usage: run-native.sh readonly|mapping|directory DEVICE MOUNT_POINT | malformed DEVICE MOUNT_POINT directory|indirect | read-suite|malformed-suite|truncated-suite MOUNT_POINT | tiny MOUNT_POINT | capacity512|capacity1024 PARTITION_BLOCKS DRIVE_SECTORS" >&2; exit 2 ;;
esac
