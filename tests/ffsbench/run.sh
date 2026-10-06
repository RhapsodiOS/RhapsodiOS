#!/bin/sh
# ffsbench throughput run.  usage: sh run.sh REPO TARGET
#   REPO   read-only workload volume: apks/, replay.list, slow.c
#   TARGET the filesystem under test, freshly newfs'd
# Replays rbuild's build-root population (src/rbuild-1/apk.c: extract each
# apk into a stage, copy the stage into the root, remove the stage), then
# removes the root, then runs slow.c.  wakeprobe runs throughout.
REPO=$1
T=$2
B=/tmp/ffsbench
cc -O -o $B/wakeprobe $B/wakeprobe.c || exit 1
cc -O -o $B/slow $REPO/slow.c || exit 1
echo PROBE-BUILT
$B/wakeprobe &
wp=$!
mkdir $T/root $T/tmp
echo REPLAY-START
t0=`$B/wakeprobe -t`
n=0
for apk in `cat $REPO/replay.list`; do
	n=`expr $n + 1`
	s=$T/tmp/stage.$n
	mkdir $s
	gzip -dc $REPO/apks/$apk | (cd $s && pax -r -pe)
	(cd $s && pax -rw -pe . $T/root)
	rm -rf $s
done
t1=`$B/wakeprobe -t`
echo REPLAY-END `expr $t1 - $t0`
rm -rf $T/root
t2=`$B/wakeprobe -t`
echo RM-END `expr $t2 - $t1`
$B/slow $T/s 64 > $B/slow.out
echo SLOW1 `grep Transferred $B/slow.out | sed -n 1p | sed 's/.*(\(.*\)Mb\/s).*/\1/'`
echo SLOW2 `grep Transferred $B/slow.out | sed -n 3p | sed 's/.*(\(.*\)Mb\/s).*/\1/'`
kill $wp
echo RUN-END
