#!/bin/sh
# DragonFly side: build the ref-main HAMMER reference volume on /dev/ad0.
# Run by dfly_guest.py; vm/dfly-walk.sh makes its manifest afterwards.
set -e
VOL=/dev/ad0
H=/tmp/h
sync_tid() { sync; hammer synctid $H > /dev/null; }

newfs_hammer -f -L REFMAIN $VOL
mount_hammer $VOL $H
cd $H

# Directories: empty, one entry, 100 entries, 20,000 entries.
mkdir empty0 one1 hundred big
: > one1/only
i=0; while [ $i -lt 100 ]; do : > hundred/h$i; i=$((i+1)); done
i=0; while [ $i -lt 20000 ]; do : > big/e$i; i=$((i+1)); done

# Names of length 1 and 255.
: > a
n=""; i=0; while [ $i -lt 255 ]; do n="${n}x"; i=$((i+1)); done
: > $n

# Files across the size boundaries (16 KiB buffers, 1 MiB large-data mark).
: > size0
for s in 1 16383 16385 1048577 67108864; do
	head -c $s /dev/urandom > size$s
done

# 512 MiB sparse file with data at 0, 256 MiB and its last byte.
dd if=/dev/urandom of=sparse bs=4096 count=1 2>/dev/null
dd if=/dev/urandom of=sparse bs=4096 count=1 seek=65536 conv=notrunc 2>/dev/null
dd if=/dev/urandom of=sparse bs=1 count=1 seek=536870911 conv=notrunc 2>/dev/null

# Symlinks stored in the inode (24 bytes) and in a record (200 bytes).
ln -s abcdefghijklmnopqrstuvwx sl24
t=""; i=0; while [ $i -lt 20 ]; do t="${t}0123456789"; i=$((i+1)); done
ln -s $t sl200

# Three names for one file.
echo linked > hl1
ln hl1 hl2
ln hl1 hl3

# Ownership, modes and out-of-range timestamps.
echo owned > owned
chown 1234:5678 owned
: > m0; chmod 0 m0
: > m4755; chmod 4755 m4755
mkdir d1777; chmod 1777 d1777
: > m644; chmod 644 m644
# Read these back through a read-write mount: a read-only one reports ctime.
TZ=UTC touch -t 197001010000 old
TZ=UTC touch -t 210001010000 future

# History: a file rewritten three times and one created then deleted.
echo v1 > rewrite; sync_tid
echo v2 > rewrite; sync_tid
echo v3 > rewrite; sync_tid
echo gone > deleted; sync_tid
rm deleted; sync_tid

cd /
umount $H

echo "== show"
hammer -f $VOL show > /tmp/show.txt
grep -E ' bad (nodes|elms|records)$' /tmp/show.txt || echo "show: no damage"
echo "== checkmap"
hammer -f $VOL checkmap > /tmp/checkmap.txt
grep -E '^B[ZM]	| errors$' /tmp/checkmap.txt || echo "checkmap: no damage"

echo "REF_OK main"
