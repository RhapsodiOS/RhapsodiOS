#!/bin/sh
set -e
IMG=/tmp/fat-images
mkdir -p "$IMG"
rm -f "$IMG/fat12.img" "$IMG/fat16.img" "$IMG/fat32.img"
newfs_msdos -C 1440k "$IMG/fat12.img"
newfs_msdos -C 32m "$IMG/fat16.img"
newfs_msdos -C 512m "$IMG/fat32.img"
fsck_msdos -n "$IMG/fat12.img"
fsck_msdos -n "$IMG/fat16.img"
fsck_msdos -n "$IMG/fat32.img"
echo OK
