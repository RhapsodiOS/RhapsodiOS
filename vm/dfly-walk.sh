#!/bin/sh
# DragonFly side: manifest of the HAMMER volume on /dev/ad0, read-only.
# Inputs: /tmp/in/walk.c (src/hammer-1/tests/hammer_walk.c).  Writes
# /tmp/x/TREE.WLK on the transfer disk.
set -e
VOL=/dev/ad0
H=/tmp/h
# The single-user shell's PATH has no /usr; cc also needs binutils' ld.
PATH=/sbin:/bin:/usr/sbin:/usr/bin
for d in /usr/libexec/binutils*/elf; do PATH=$PATH:$d; done
export PATH

cc -o /tmp/walk /tmp/in/walk.c
mount_hammer -o ro $VOL $H
/tmp/walk $H > /tmp/x/TREE.WLK
umount $H
wc -l /tmp/x/TREE.WLK
echo "WALK_OK"
