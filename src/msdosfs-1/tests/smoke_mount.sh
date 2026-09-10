#!/bin/sh
# Task 8: kernel R/W + VFAT verification on a FAT image/device in the guest.
# Depends on Task 3 kernel plus mount_msdos, newfs_msdos, fsck_msdos installed.
#
# Usage: smoke_mount.sh [/dev/<device>]
#   DEV defaults to /dev/FIXME when no argument is given.
#
# Step 1: attach or present a FAT image to the guest (vn/md, secondary disk, or
# dd onto a spare slice). Pass the resulting block device as $1.
set -e

DEV=${1:-/dev/FIXME}
MNT=/mnt/fat
BAD=/tmp/bad.img

if [ "$DEV" = /dev/FIXME ]; then
	echo "smoke_mount: set DEV to a FAT block device (e.g. sh $0 /dev/vn0)" >&2
	exit 1
fi

mkdir -p "$MNT"

# --- Step 2: mount read-only, then read/write with VFAT long names ---
mount -t msdos -o rdonly "$DEV" "$MNT"
ls -la "$MNT"
umount "$MNT"

mount -t msdos "$DEV" "$MNT"
echo hello > "$MNT/SHORT.TXT"
mkdir "$MNT/subdir"
echo world > "$MNT/subdir/Long File Name.txt"
ls -la "$MNT" "$MNT/subdir"
umount "$MNT"

mount -t msdos "$DEV" "$MNT"
test "$(cat "$MNT/SHORT.TXT")" = hello
test "$(cat "$MNT/subdir/Long File Name.txt")" = world
umount "$MNT"

fsck_msdos -n "$DEV"

# --- Step 3: negative checks ---
dd if=/dev/zero of="$BAD" bs=512 count=40
if mount -t msdos "$BAD" "$MNT" 2>/dev/null; then
	echo "smoke_mount: mount of garbage image should have failed" >&2
	umount "$MNT" 2>/dev/null || true
	exit 1
fi

mount -t msdos -o rdonly "$DEV" "$MNT"
if echo no > "$MNT/x" 2>/tmp/ro.err; then
	echo "smoke_mount: write on rdonly mount should have failed" >&2
	umount "$MNT"
	exit 1
fi
umount "$MNT"

echo OK
