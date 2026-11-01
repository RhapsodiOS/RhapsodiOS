#!/bin/sh
# DragonFly side: build the ref-dedup HAMMER reference volume on /dev/ad0:
# 32 identical 1 MiB files, deduplicated so their data records share blocks.
set -e
VOL=/dev/ad0
H=/tmp/h

newfs_hammer -f -L REFDEDUP $VOL
mount_hammer $VOL $H
head -c 1048576 /dev/urandom > /tmp/seed
i=0; while [ $i -lt 32 ]; do cp /tmp/seed $H/f$i; i=$((i+1)); done
sync; hammer synctid $H > /dev/null
hammer dedup $H
sync; hammer synctid $H > /dev/null
umount $H

echo "== show"
hammer -f $VOL show > /tmp/show.txt
grep -E ' bad (nodes|elms|records)$' /tmp/show.txt || echo "show: no damage"
echo "== checkmap"
hammer -f $VOL checkmap > /tmp/checkmap.txt
grep -E '^B[ZM]	| errors$' /tmp/checkmap.txt || echo "checkmap: no damage"

echo "REF_OK dedup"
