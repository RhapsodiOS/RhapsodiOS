#!/bin/sh
# Disposable selected partition only. Run beside ext2_io/checksum-partition.sh.
# This tests actual tools and driver I/O; provider tests cannot replace it.
test "$#" = 5 || exit 2
raw="$1"; block="$2"; token="$3"; point="$4"; blocks1024="$5"
failures=0
run_status() {
    case_name="$1"; expected="$2"; shift 2
    "$@"
    actual=$?
    echo "SECTOR_STATUS $case_name expected=$expected actual=$actual"
    test "$actual" = "$expected" || failures=`expr "$failures" + 1`
    return "$actual"
}
for device in "$raw" "$block"; do
    run_status "format:$device" 0 /sbin/newfs_ext2fs -b 1024 -L Task9Sector "$device"
    run_status "wrapper-check:$device" 0 /sbin/fsck_ext2fs -n -f "$device"
    run_status "raw-checker:$device" 0 /sbin/e2fsck -f -n "$device"
done
run_status bounded-read 0 /bin/sh ./checksum-partition.sh "$raw" "$blocks1024" sector-crc
run_status probe 255 /usr/filesystems/ext2fs.fs/ext2fs.util -p "$token" fixed writable
run_status mount 0 /sbin/mount_ext2fs "$block" "$point"
if test "$?" = 0; then
    run_status persistence-write 0 ./ext2_io persistence-write "$point"
    run_status unmount 0 /sbin/umount "$point"
    run_status remount-readonly 0 /sbin/mount_ext2fs -o ro "$block" "$point"
    if test "$?" = 0; then
        run_status persistence-read 0 ./ext2_io persistence-read "$point"
        run_status unmount-readonly 0 /sbin/umount "$point"
    fi
fi
echo "SECTOR_FAILURES $failures"
test "$failures" = 0
