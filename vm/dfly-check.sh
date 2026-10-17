#!/bin/sh
# DragonFly side: check a volume another system wrote, then mount it read-only.
set -e
VOL=/dev/ad0
H=/tmp/h

echo "== show"
hammer -f $VOL show > /tmp/show.txt
grep -E ' bad (nodes|elms|records)$' /tmp/show.txt && exit 1
echo "show: no damage"
echo "== checkmap"
hammer -f $VOL checkmap > /tmp/checkmap.txt
grep -E '^B[ZM]	| errors$' /tmp/checkmap.txt && exit 1
echo "checkmap: no damage"
echo "== mount ro"
mount_hammer -o ro $VOL $H
ls -la $H
umount $H
echo "CHECK_OK"
