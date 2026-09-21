#!/bin/sh
# Build the parallel port, bus mouse and serial pointing device drivers.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
for d in drvPCParallel drvBusMouse drvSerialPointingDevice; do
	DST=/build/out/$d-rbuild
	rm -rf "$DST"; mkdir -p "$DST"
	echo "======== $d via rbuild (i386) ========"
	rbuild buildpackage --state /build/state --arch i386 --dir --target all \
	    /build/src/drivers-i386/input/$d /build/repo "$DST" > /tmp/_$d.log 2>&1
	echo "${d}_RC=$?"
	ls -l "$DST"/*.apk 2>/dev/null || echo "  NO APK"
	grep -iE "Error [0-9]|multiple definitions|does not exist|No such file" /tmp/_$d.log | head -4
done
echo "=== input3 done `date` ==="
