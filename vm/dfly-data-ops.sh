#!/bin/sh
# DragonFly side: the reference tree for case data-ops.  Run once against a
# throwaway copy of the blank volume.  Inputs: /tmp/in/walk.c
# (src/hammer-1/tests/hammer_walk.c) and /tmp/in/dataops.c
# (src/hammer-1/tests/data_ops.c).  Writes /tmp/x/DATAOPS.WLK, the
# hammer_walk manifest (with content CRCs) after a remount.
set -e
VOL=/dev/ad0
H=/tmp/h
PATH=/sbin:/bin:/usr/sbin:/usr/bin
for d in /usr/libexec/binutils*/elf; do PATH=$PATH:$d; done
export PATH

cc -o /tmp/walk /tmp/in/walk.c
cc -o /tmp/dataops /tmp/in/dataops.c
mount_hammer -o noatime $VOL $H
/tmp/dataops write $H
/tmp/dataops verify $H
umount $H
mount_hammer -o noatime $VOL $H
/tmp/dataops verify $H
/tmp/walk $H > /tmp/x/DATAOPS.WLK
umount $H
wc -l /tmp/x/DATAOPS.WLK
echo "DATAOPS_OK"
