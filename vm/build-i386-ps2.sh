#!/bin/sh
# Build the i386 PS/2 keyboard and mouse drivers with rbuild.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
for d in drvPS2Keyboard drvPS2Mouse; do
	DST=/build/out/$d-rbuild
	rm -rf "$DST"; mkdir -p "$DST"
	echo "======== $d via rbuild (i386) start `date` ========"
	rbuild buildpackage --state /build/state --arch i386 --dir --target all \
	    /build/src/drivers-i386/input/$d /build/repo "$DST"
	echo "${d}_RC=$?"
	ls -l "$DST"/*.apk 2>/dev/null
done
echo "=== ps2 done `date` ==="
