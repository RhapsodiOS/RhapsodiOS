#!/bin/sh
# Run from the directory containing mount_ext2fs and ext2_io.
set -e
case "$1" in
discovery)
    test "$#" = 2
    label="$2"
    ./discovery-native ext2fs 1 "$label"
    ./discovery-media save /dev/rhd1a saved-super
    ./discovery-media dirty /dev/rhd1a saved-super
    /bin/sh ./checksum-partition.sh /dev/rhd1a 16384 before-crc
    ./discovery-native ext2fs 0 "$label"
    /bin/sh ./checksum-partition.sh /dev/rhd1a 16384 after-crc
    cmp before-crc after-crc
    ./discovery-media unsupported /dev/rhd1a saved-super
    /bin/sh ./checksum-partition.sh /dev/rhd1a 16384 before-crc
    ./discovery-native none skip "$label"
    /bin/sh ./checksum-partition.sh /dev/rhd1a 16384 after-crc
    cmp before-crc after-crc
    ./discovery-media malformed /dev/rhd1a saved-super
    /bin/sh ./checksum-partition.sh /dev/rhd1a 16384 before-crc
    ./discovery-native none skip "$label"
    /bin/sh ./checksum-partition.sh /dev/rhd1a 16384 after-crc
    cmp before-crc after-crc
    ./discovery-media restore /dev/rhd1a saved-super
    mv /usr/filesystems/ext2fs.fs/ext2fs.util /usr/filesystems/ext2fs.fs/ext2fs.util.saved
    ./discovery-native none skip "$label"
    mv /usr/filesystems/ext2fs.fs/ext2fs.util.saved /usr/filesystems/ext2fs.fs/ext2fs.util
    ./discovery-native ext2fs 1 "$label"
    echo "EXT2_OK discovery"
    ;;
persistence-write-suite)
    test "$#" = 2
    ./mount_ext2fs /dev/hd1a "$2"
    ./ext2_io persistence-write "$2"
    ./ext2_io busy "$2"
    umount "$2"
    echo "EXT2_OK persistence-write-suite"
    ;;
task5-covering-suite)
    sh "$0" write-fsync-suite "$2"
    sh "$0" fresh-control-suite "$2"
    echo "EXT2_OK task5-covering-suite"
    ;;
recovery-write)
    test "$#" = 2
    ./mount_ext2fs /dev/hd1a "$2"
    ./ext2_io persistence-write "$2"
    echo "EXT2_OK recovery-write"
    ;;
dirty-refusal)
    test "$#" = 2
    ./ext2_io dirty-refusal "$2" /dev/hd1a
    ;;

ioerror-suite|ioerror-transition-suite|ioerror-allocation-suite|ioerror-read-suite)
    test "$#" = 2
    test -b /dev/hd1f || mknod /dev/hd1f b 3 13
    mkdir /mnt/control
    ./mount_ext2fs -o ro /dev/hd1f /mnt/control
    result=0
    items="admission:a short-inode:a first-push:a metadata:b truncate:c allocation:d clean:e"
    if test "$1" = ioerror-transition-suite; then items="close:a rewrite:b remount-clean:c remount-rewrite:d"; fi
    if test "$1" = ioerror-allocation-suite; then items="truncate-bitmap:a allocation-bitmap:b first-errno:c"; fi
    if test "$1" = ioerror-read-suite; then items="read-indirect-error:a read-indirect-short:b read-tail-error:c read-tail-short:d"; fi
    for item in $items; do
        scenario="${item%:*}"
        part="${item#*:}"
        case "$part" in a) minor=8;; b) minor=9;; c) minor=10;; d) minor=11;; e) minor=12;; esac
        device="/dev/hd1$part"
        point="/mnt/e-$part"
        test -b "$device" || mknod "$device" b 3 "$minor"
        test -d "$point" || mkdir "$point"
        set +e
        ./ext2_io ioerror "$scenario" "$device" "$point" /mnt/control/faultctl
        one=$?
        set -e
        echo "FAULT_STATUS $scenario $one"
        if test "$one" != 0; then result=1; fi
    done
    umount /mnt/control
    test "$result" = 0
    echo "EXT2_OK $1"
    ;;
ioerror-*)
    case "$1" in
    ioerror-first-push) scenario=first-push;;
    ioerror-short-inode) scenario=short-inode;;
    ioerror-admission) scenario=admission;;
    ioerror-metadata) scenario=metadata;;
    ioerror-truncate) scenario=truncate;;
    ioerror-allocation) scenario=allocation;;
    ioerror-clean) scenario=clean;;
    ioerror-close) scenario=close;;
    ioerror-rewrite) scenario=rewrite;;
    ioerror-remount-clean) scenario=remount-clean;;
    ioerror-remount-rewrite) scenario=remount-rewrite;;
    esac
    test "$#" = 2
    test -b /dev/hd1f || mknod /dev/hd1f b 3 13
    mkdir /mnt/control
    ./mount_ext2fs -o ro /dev/hd1f /mnt/control
    ./ext2_io ioerror "$scenario" /dev/hd1a "$2" /mnt/control/faultctl
    umount /mnt/control
    rmdir /mnt/control
    echo "EXT2_OK $1"
    ;;

remount|busy|persistence-write|persistence-read)
    test "$#" = 2
    ./mount_ext2fs /dev/hd1a "$2"
    result=0
    if test "$1" = remount; then
        ./ext2_io remount-busy "$2" || result=1
        ./ext2_io remount-cycle-null "$2" || result=1
        ./ext2_io remount-cycle-device "$2" /dev/hd1a || result=1
    else
        ./ext2_io "$1" "$2" || result=1
    fi
    umount "$2"
    test "$result" = 0
    echo "EXT2_OK $1"
    ;;

rejected-inode-suite)
    test "$#" = 2
    set +e
    ./ext2_io rejected-inode /dev/hd1a "$2"
    ordinary=$?
    test -b /dev/hd1b || mknod /dev/hd1b b 3 9
    ./ext2_io rejected-root /dev/hd1b "$2"
    root=$?
    set -e
    test "$ordinary" = 0 && test "$root" = 0
    echo "EXT2_OK rejected-inode-suite"
    ;;
fresh-control-suite)
    test "$#" = 2
    ./mount_ext2fs /dev/hd1a "$2"
    set +e
    ./ext2_io mmap-fresh-control "$2"
    result=$?
    set -e
    umount "$2"
    test "$result" = 0
    echo "EXT2_OK fresh-control-suite"
    ;;
fresh-mmap-suite)
    test "$#" = 2
    ./mount_ext2fs /dev/hd1a "$2"
    ./ext2_io mmap-fresh "$2"
    umount "$2"
    ./mount_ext2fs -o ro /dev/hd1a "$2"
    ./ext2_io verify-fresh "$2"
    umount "$2"
    echo "EXT2_OK fresh-mmap-suite"
    ;;
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
    if test "$suite" = write-fsync-suite; then scenarios="mutation limits mmap-fresh mmap-size mmap-fsync mmap-limits permissions special"; fi
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
        if test "$suite" = write-fsync-suite; then ./ext2_io verify-fresh "$point"; fi
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
            sh "$0" mmap-readonly "$device" "$point"
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
readonly|mapping|directory|mmap-readonly|malformed)
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
