#!/bin/sh
# DragonFly side: check a volume another system wrote, then mount it read-only.
# Inputs: /tmp/in/walk.c (src/hammer-1/tests/hammer_walk.c).  Writes
# /tmp/x/TREE.WLK (the mounted tree) and /tmp/x/REC.WLK (what
# "hammer recover" rebuilds from the B-Tree alone) on the transfer disk.
set -e
VOL=/dev/ad0
H=/tmp/h
# The single-user shell's PATH has no /usr; cc also needs binutils' ld.
PATH=/sbin:/bin:/usr/sbin:/usr/bin
for d in /usr/libexec/binutils*/elf; do PATH=$PATH:$d; done
export PATH

cc -o /tmp/walk /tmp/in/walk.c
echo "== show"
hammer -f $VOL show > /tmp/show.txt
grep -E ' bad (nodes|elms|records)$' /tmp/show.txt && exit 1
echo "show: no damage"
echo "== checkmap"
hammer -f $VOL checkmap > /tmp/checkmap.txt
grep -E '^B[ZM]	| errors$| bad nodes$' /tmp/checkmap.txt && exit 1
echo "checkmap: no damage"
echo "== recover"
mkdir -p /tmp/rec
hammer -f $VOL recover /tmp/rec > /tmp/recover.txt 2>&1
grep -iE 'bad|error|corrupt' /tmp/recover.txt && exit 1
/tmp/walk /tmp/rec > /tmp/x/REC.WLK
echo "recover: no damaged records"
echo "== mount ro"
mount_hammer -o ro $VOL $H
/tmp/walk $H > /tmp/x/TREE.WLK
ls -la $H
umount $H
echo "CHECK_OK"
