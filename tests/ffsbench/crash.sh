#!/bin/sh
# ffsbench crash run.  usage: sh crash.sh REPO TARGET
# The replay part of run.sh only; the host kills the guest during it.
REPO=$1
T=$2
B=/tmp/ffsbench
cc -O -o $B/wakeprobe $B/wakeprobe.c || exit 1
echo PROBE-BUILT
$B/wakeprobe &
mkdir $T/root $T/tmp
echo REPLAY-START
n=0
while read root apk; do
	n=`expr $n + 1`
	s=$T/tmp/validate.$n
	mkdir $s
	gzip -dc $REPO/apks/$apk | (cd $s && pax -r -pe)
	rm -rf $s
	s=$T/tmp/extract.$n
	mkdir -p $s $T/root/$root
	gzip -dc $REPO/apks/$apk | (cd $s && pax -r -pe)
	(cd $s && pax -rw -pe . $T/root/$root)
	rm -rf $s
done < $REPO/replay.list
echo REPLAY-END
