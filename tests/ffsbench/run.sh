#!/bin/sh
# ffsbench throughput run.  usage: sh run.sh REPO TARGET
#   REPO   read-only workload volume: apks/, replay.list, slow.c
#   TARGET the filesystem under test, freshly newfs'd
# Replays the four build roots `rbuild kernel` populates.  replay.list holds
# "<root> <apk>" lines.  As in src/rbuild-1 (builder.c find_arch_package,
# apk.c use_artifact), each apk is extracted into a stage once to validate it,
# then again to install it: the stage is copied into the root and removed.
# Then the roots are removed and slow.c runs.  wakeprobe runs throughout.
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
