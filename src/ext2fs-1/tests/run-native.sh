#!/bin/sh
# Run from the directory containing mount_ext2fs and ext2_io.
set -e
case "$1" in
mutation|limits|mmap|mmap-size|mmap-fsync|mmap-limits|permissions|special)
    test "$#" = 3
    ./mount_ext2fs "$2" "$3"
    ./ext2_io "$1" "$3"
    umount "$3"
    ;;
append-control-suite)
    test "$#" = 2
    mkdir /mnt/ufs-control
    ./ext2_io ufs-append-control /mnt/ufs-control
    rmdir /mnt/ufs-control
    ./mount_ext2fs /dev/hd1a "$2"
    ./ext2_io mmap-limits "$2"
    umount "$2"
    echo "EXT2_OK append-control-suite"
    ;;
mmap-diagnostic-suite)
    test "$#" = 2
    mkdir /mnt/ufs-control
    set +e
    ./ext2_io mmap-size /mnt/ufs-control
    echo "FFS_CONTROL_STATUS $?"
    set -e
    rmdir /mnt/ufs-control
    ./mount_ext2fs /dev/hd1a "$2"
    set +e
    ./ext2_io mmap-size "$2"
    echo "EXT2_DIAGNOSTIC_STATUS $?"
    set -e
    umount "$2"
    echo "EXT2_OK mmap-diagnostic-suite"
    ;;
remount-red-suite)
    test "$#" = 2
    for route in remount-null remount-device; do
        ./mount_ext2fs /dev/hd1a "$2"
        if test "$route" = remount-device; then
            if ./ext2_io "$route" "$2" /dev/hd1a; then exit 1; fi
        else
            if ./ext2_io "$route" "$2"; then exit 1; fi
        fi
        echo "EXPECTED_RED $route"
        umount "$2"
    done
    echo "EXT2_OK remount-red-suite"
    ;;
write-red-suite)
    test "$#" = 2
    ./mount_ext2fs -o ro /dev/hd1a "$2"
    for scenario in mutation limits mmap permissions special; do
        if ./ext2_io "$scenario" "$2"; then exit 1; else echo "EXPECTED_RED $scenario"; fi
    done
    umount "$2"
    echo "EXT2_OK write-red-suite"
    ;;
write-suite|write-fsync-suite|write-core-suite)
    test "$#" = 2
    point="$2"
    suite="$1"
    scenarios="mutation limits mmap-size mmap permissions special"
    verify=verify-writes
    if test "$suite" = write-fsync-suite; then scenarios="mutation limits mmap-size mmap-fsync mmap-limits permissions special"; fi
    if test "$suite" = write-core-suite; then scenarios="mutation limits permissions special"; verify=verify-core; fi
    n=0
    for part in a b c d e f; do
        minor=`expr 8 + "$n"`
        device="/dev/hd1$part"
        test -b "$device" || mknod "$device" b 3 "$minor"
        echo "write partition $part"
        ./mount_ext2fs "$device" "$point"
        for scenario in $scenarios; do
            ./ext2_io "$scenario" "$point"
        done
        ./ext2_io remount-null "$point"
        ./ext2_io remount-device "$point" "$device"
        umount "$point"
        ./mount_ext2fs -o ro "$device" "$point"
        ./ext2_io "$verify" "$point"
        umount "$point"
        n=`expr "$n" + 1`
    done
    echo "EXT2_OK $suite"
    ;;
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
*) echo "usage: run-native.sh mutation|limits|mmap-fsync|mmap-size|permissions|special DEVICE MOUNT_POINT | write-fsync-suite MOUNT_POINT | readonly|mapping|directory DEVICE MOUNT_POINT | malformed DEVICE MOUNT_POINT directory|indirect | read-suite|malformed-suite|truncated-suite MOUNT_POINT | tiny MOUNT_POINT | capacity512|capacity1024 PARTITION_BLOCKS DRIVE_SECTORS" >&2; exit 2 ;;
esac
