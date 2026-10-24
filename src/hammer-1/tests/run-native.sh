#!/bin/sh
# run-native.sh CASE POINT: HAMMER kernel cases on a Rhapsody guest.
# Run from the directory holding hammer_io; the data volume is /dev/hd1a.
# Every case prints "HAMMER_OK <case>" only after all its checks pass.
set -e
DEV=/dev/hd1a
EIO=5
EINVAL=22
EROFS=30
EOPNOTSUPP=45

# A volume this kernel wrote must look undamaged to the hammer tool.
checkvol() {
	./hammer -f /dev/rhd1a show > /tmp/show.txt 2>&1
	if grep -E ' bad (nodes|elms|records)$' /tmp/show.txt; then
		echo "show: damage"; exit 1
	fi
	./hammer -f /dev/rhd1a checkmap > /tmp/checkmap.txt 2>&1
	if grep -E "^B[ZM]	| errors$| bad nodes$" /tmp/checkmap.txt; then
		echo "checkmap: damage"; exit 1
	fi
	echo "show and checkmap: no damage"
}

case "$1" in
refuse-badsig|refuse-badcrc)
	./hammer_io mounterr $DEV "$2" 1 $EINVAL
	;;
refuse-v6|refuse-twovol|refuse-needs-recovery)
	./hammer_io mounterr $DEV "$2" 1 $EOPNOTSUPP
	;;
rw-empty)
	./hammer_io mount-rw $DEV "$2"
	sync
	./hammer_io unmount "$2"
	checkvol
	;;
ns-ops)
	# Namespace workload; the host diffs the walk with DragonFly's.
	./hammer_io mount-rw $DEV "$2"
	./ns_ops "$2"
	./hammer_io unmount "$2"
	./hammer_io mount $DEV "$2"
	./hammer_walk -n "$2" > /tmp/walk.txt
	gzip -9 < /tmp/walk.txt > walk.gz
	./hammer_io unmount "$2"
	checkvol
	;;
data-ops)
	# File data workload, checked before and after a remount; the host
	# diffs the walk (with content CRCs) with DragonFly's.
	./hammer_io mount-rw $DEV "$2"
	./data_ops write "$2"
	./data_ops verify "$2"
	./hammer_io unmount "$2"
	./hammer_io mount $DEV "$2"
	./data_ops verify-remount "$2"
	./hammer_walk "$2" > /tmp/walk.txt
	gzip -9 < /tmp/walk.txt > walk.gz
	./hammer_io unmount "$2"
	checkvol
	;;
unlinked)
	./hammer_io mount-rw $DEV "$2"
	./data_ops unlinked "$2"
	./hammer_io unmount "$2"
	checkvol
	;;
fsync-crash)
	# No unmount: the host quits the guest with the volume mounted.
	./hammer_io mount-rw $DEV "$2"
	./data_ops durable "$2"
	;;
fsync-check)
	# The volume fsync-crash left; mounting it needs no recovery.
	./hammer_io mount $DEV "$2"
	./data_ops durable-check "$2"
	./hammer_io unmount "$2"
	checkvol
	;;
big-dir)
	# 20,000 entries, half removed (the host diffs this walk with
	# DragonFly's), then all; remounts between stages.
	./hammer_io mount-rw $DEV "$2"
	./scale_ops dir-fill "$2"
	./hammer_io unmount "$2"
	./hammer_io mount $DEV "$2"
	./scale_ops dir-half "$2"
	./hammer_walk -n "$2" > /tmp/walk.txt
	gzip -9 < /tmp/walk.txt > walk.gz
	./hammer_io unmount "$2"
	./hammer_io mount-rw $DEV "$2"
	./scale_ops dir-empty "$2"
	./hammer_io unmount "$2"
	./hammer_io mount $DEV "$2"
	./scale_ops gone "$2"
	./hammer_io unmount "$2"
	checkvol
	;;
big-file)
	./hammer_io mount-rw $DEV "$2"
	./scale_ops file-write "$2"
	./hammer_io unmount "$2"
	./hammer_io mount $DEV "$2"
	./scale_ops file-check "$2"
	./hammer_io unmount "$2"
	./hammer_io mount-rw $DEV "$2"
	./scale_ops file-delete "$2"
	./hammer_io unmount "$2"
	./hammer_io mount $DEV "$2"
	./scale_ops gone "$2"
	./hammer_io unmount "$2"
	checkvol
	;;
churn)
	./hammer_io mount-rw $DEV "$2"
	./scale_ops churn "$2"
	./hammer_io unmount "$2"
	./hammer_io mount $DEV "$2"
	./scale_ops churn-check "$2"
	./hammer_io unmount "$2"
	checkvol
	;;
refuse-rw-recovery)
	./hammer_io mounterr $DEV "$2" 0 $EOPNOTSUPP
	;;
refuse-rw-pfs)
	./hammer_io mounterr $DEV "$2" 0 $EOPNOTSUPP
	./hammer_io mount $DEV "$2"
	./hammer_io unmount "$2"
	;;
admit)
	./hammer_io mount $DEV "$2"
	./hammer_io unmount "$2"
	;;
namespace)
	# Metadata manifest for the host to diff against the DragonFly one.
	./hammer_io mount $DEV "$2"
	./hammer_walk -n "$2" > /tmp/walk.txt
	gzip -9 < /tmp/walk.txt > walk.gz
	./hammer_io unmount "$2"
	;;
readdir-small)
	./hammer_io mount $DEV "$2"
	./hammer_io readdir-small "$2/big" 20002
	./hammer_io unmount "$2"
	;;
times)
	./hammer_io mount $DEV "$2"
	./hammer_io times "$2"
	./hammer_io unmount "$2"
	;;
erofs)
	./hammer_io mount $DEV "$2"
	./hammer_io erofs "$2"
	./hammer_io unmount "$2"
	;;
data|dedup)
	# Full manifest with content CRCs for the host to diff.
	./hammer_io mount $DEV "$2"
	./hammer_walk "$2" > /tmp/walk.txt
	gzip -9 < /tmp/walk.txt > walk.gz
	./hammer_io unmount "$2"
	;;
cycle)
	# Mount lifecycle: leaks are reported at each last unmount.
	i=0
	while [ $i -lt 100 ]; do
		./hammer_io mount $DEV "$2"
		./hammer_walk -n "$2" > /dev/null
		./hammer_io unmount "$2"
		i=`expr $i + 1`
	done
	echo "$i mount/walk/unmount cycles"
	;;
holes)
	./hammer_io mount $DEV "$2"
	./hammer_io holes "$2/sparse"
	./hammer_io unmount "$2"
	;;
mmap)
	./hammer_io mount $DEV "$2"
	./hammer_io mmap "$2/size16385"
	./hammer_io unmount "$2"
	;;
crafted-data)
	./hammer_io mount $DEV "$2"
	./hammer_io readeio "$2/size1048577"
	./hammer_io readok "$2/size16385"
	./hammer_io unmount "$2"
	;;
negread)
	./hammer_io mount $DEV "$2"
	./hammer_io negread "$2/size16385"
	./hammer_io unmount "$2"
	;;
crafted-count)
	# The bad leaf also holds the root inode, so the mount itself fails.
	./hammer_io mounterr $DEV "$2" 1 $EIO
	;;
crafted-len|crafted-off)
	./hammer_io mount $DEV "$2"
	./hammer_io readdir-eio "$2"
	./hammer_io readok "$2/size16385"
	./hammer_io unmount "$2"
	;;
crafted-dotdot)
	./hammer_io mount $DEV "$2"
	./hammer_io dotdot "$2/d1777"
	./hammer_io unmount "$2"
	;;
crafted-dirhash)
	./hammer_io mount $DEV "$2"
	./hammer_io lookupeio "$2/a"
	./hammer_io unmount "$2"
	;;
crafted-name)
	./hammer_io mount $DEV "$2"
	./hammer_io readdir-eio "$2"
	./hammer_io unmount "$2"
	;;
*)
	echo "unknown case $1"
	exit 2
	;;
esac
echo "HAMMER_OK $1"
