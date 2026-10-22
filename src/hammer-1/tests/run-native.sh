#!/bin/sh
# run-native.sh CASE POINT: HAMMER kernel cases on a Rhapsody guest.
# Run from the directory holding hammer_io; the data volume is /dev/hd1a.
# Every case prints "HAMMER_OK <case>" only after all its checks pass.
set -e
DEV=/dev/hd1a
EINVAL=22
EROFS=30
EOPNOTSUPP=45
case "$1" in
refuse-badsig|refuse-badcrc)
	./hammer_io mounterr $DEV "$2" 1 $EINVAL
	;;
refuse-v6|refuse-twovol|refuse-needs-recovery)
	./hammer_io mounterr $DEV "$2" 1 $EOPNOTSUPP
	;;
refuse-rw)
	./hammer_io mounterr $DEV "$2" 0 $EROFS
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
