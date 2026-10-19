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
	# Until the root vnode exists (Task 6) the mount stops just after
	# admission; the host checks the console for the admission message.
	./hammer_io mounterr $DEV "$2" 1 $EOPNOTSUPP
	;;
*)
	echo "unknown case $1"
	exit 2
	;;
esac
echo "HAMMER_OK $1"
