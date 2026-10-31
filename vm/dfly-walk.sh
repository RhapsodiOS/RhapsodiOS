#!/bin/sh
# DragonFly side: manifest of the HAMMER volume on /dev/ad0.
# Inputs: /tmp/in/walk.c (src/hammer-1/tests/hammer_walk.c).  Writes
# /tmp/x/TREE.WLK on the transfer disk.
# The mount is read-write with noatime: on a read-only mount DragonFly flags
# every inode HAMMER_INODE_RO and reports ctime as atime and mtime, which
# hides the stored times.  Run it on a throwaway copy of the volume.
set -e
VOL=/dev/ad0
H=/tmp/h
# The single-user shell's PATH has no /usr; cc also needs binutils' ld.
PATH=/sbin:/bin:/usr/sbin:/usr/bin
for d in /usr/libexec/binutils*/elf; do PATH=$PATH:$d; done
export PATH

cc -o /tmp/walk /tmp/in/walk.c
mount_hammer -o noatime $VOL $H
/tmp/walk $H > /tmp/x/TREE.WLK
umount $H
wc -l /tmp/x/TREE.WLK
echo "WALK_OK"
