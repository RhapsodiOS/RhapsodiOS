#!/bin/sh
# Build the four generic (non arch-specific) drivers with rbuild.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
for p in generic/network/drvBPF generic/serial/drvPortServer generic/scsi/drvSCSIServer generic/scsi/drvSCSITape; do
	d=${p##*/}
	DST=/build/out/$d-rbuild
	rm -rf "$DST"; mkdir -p "$DST"
	echo "======== $d via rbuild ========"
	rbuild buildpackage --state /build/state --dir --target all \
	    /build/src/CoreOS/drivers/$p /build/repo "$DST" > /tmp/_$d.log 2>&1
	echo "${d}_RC=$?"
	ls -l "$DST"/*.apk 2>/dev/null || echo "  NO APK"
	grep -iE "Error [0-9]|multiple definitions|does not exist|No such file|Must set" /tmp/_$d.log | head -4
done
echo "=== generic done `date` ==="
