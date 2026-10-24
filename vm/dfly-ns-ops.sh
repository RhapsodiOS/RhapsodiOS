#!/bin/sh
# DragonFly side: the reference tree for case ns-ops.  Run once against a
# throwaway copy of the blank volume.  Inputs: /tmp/in/walk.c
# (src/hammer-1/tests/hammer_walk.c) and /tmp/in/nsops.c
# (src/hammer-1/tests/ns_ops.c).  Writes /tmp/x/NSOPS.WLK, the
# hammer_walk -n manifest after a remount.
set -e
VOL=/dev/ad0
H=/tmp/h
PATH=/sbin:/bin:/usr/sbin:/usr/bin
for d in /usr/libexec/binutils*/elf; do PATH=$PATH:$d; done
export PATH

cc -o /tmp/walk /tmp/in/walk.c
cc -o /tmp/nsops /tmp/in/nsops.c
mount_hammer -o noatime $VOL $H
/tmp/nsops $H
umount $H
mount_hammer -o noatime $VOL $H
/tmp/walk -n $H > /tmp/x/NSOPS.WLK
umount $H
wc -l /tmp/x/NSOPS.WLK
echo "NSOPS_OK"
