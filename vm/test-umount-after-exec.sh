#!/bin/sh
# Guest regression test: a UFS file system must unmount after programs
# have been run from it, however many times.
#
# Before the kernel fix in kern/mach_loader.c, get_macho_vnode() leaked a
# mapfs map_count on dyld once the file already had a pager, so the second
# `chroot T /usr/bin/true` left T permanently "Device busy".
#
# Run on the guest as root:  sh test-umount-after-exec.sh [disk]
#   disk   spare, unlabelled raw disk, e.g. rhd1h (default).  It is
#          INITIALISED (disk -i) and its contents are destroyed.
# Exit status 0 = pass.

DISK=${1:-rhd1h}
PART=`echo $DISK | sed 's/^r//; s/.$/a/'`	# rhd1h -> hd1a
T=/mnt/umount-exec-test

fail() { echo "FAIL: $*"; exit 1; }

disk -i -N -l umounttest /dev/$DISK > /dev/null 2>&1 || fail "disk -i /dev/$DISK"
mkdir -p $T

mount /dev/$PART $T || fail "mount /dev/$PART"
mkdir -p $T/usr/bin $T/usr/lib $T/System/Library/Frameworks
cp /usr/bin/true $T/usr/bin/true
cp /usr/lib/dyld $T/usr/lib/dyld
cp -R /System/Library/Frameworks/System.framework \
	$T/System/Library/Frameworks/System.framework
sync
umount $T || fail "umount after populating"

for runs in 1 2 3; do
	mount /dev/$PART $T || fail "mount (runs=$runs)"
	n=0
	while [ $n -lt $runs ]; do
		chroot $T /usr/bin/true || fail "chroot exec (runs=$runs)"
		n=`expr $n + 1`
	done
	umount $T || fail "umount busy after $runs chroot exec(s)"
done

rmdir $T
echo PASS
