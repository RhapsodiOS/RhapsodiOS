#!/bin/sh
# DragonFly side: the reference tree for case big-dir, midway (20,000
# files made, every other one removed).  Run once against a throwaway copy
# of the blank volume.  Inputs: /tmp/in/walk.c and /tmp/in/scaleops.c
# (src/hammer-1/tests/{hammer_walk,scale_ops}.c).  Writes /tmp/x/BIGDIR.WLK,
# the hammer_walk -n manifest after a remount.
set -e
VOL=/dev/ad0
H=/tmp/h
PATH=/sbin:/bin:/usr/sbin:/usr/bin
for d in /usr/libexec/binutils*/elf; do PATH=$PATH:$d; done
export PATH

cc -o /tmp/walk /tmp/in/walk.c
cc -o /tmp/scaleops /tmp/in/scaleops.c
mount_hammer -o noatime $VOL $H
/tmp/scaleops dir-fill $H
umount $H
mount_hammer -o noatime $VOL $H
/tmp/scaleops dir-half $H
/tmp/walk -n $H > /tmp/x/BIGDIR.WLK
umount $H
wc -l /tmp/x/BIGDIR.WLK
echo "BIGDIR_OK"
