#!/bin/sh
# Test and build drvIntelE100 for i386. Runs on the build guest through
#   powershell -NoProfile -File vm\guest-remote.ps1 -Run vm\build-i386-e100.sh
# after vm\sync-src.ps1 -Path drivers-i386/network/drvIntelE100.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
SRC=/build/src/drivers-i386/network/drvIntelE100
DST=/build/out/drvIntelE100-rbuild

echo "======== drvIntelE100 tests `date` ========"
( cd $SRC/tests && gnumake clean check ) || { echo "TESTS_RC=1"; exit 1; }
echo "TESTS_RC=0"

if [ ! -f $SRC/apk/pkginfo ]; then
    echo "no apk/pkginfo yet - tests only"
    exit 0
fi

rm -rf "$DST"; mkdir -p "$DST"
echo "======== drvIntelE100 via rbuild (i386) `date` ========"
rbuild buildpackage --state /build/state --arch i386 --dir --target all \
    $SRC /build/repo "$DST" > "$DST.log" 2>&1
rc=$?
echo "BUILD_RC=$rc"
echo "--- compiler diagnostics from the driver's own sources ---"
grep -n "IntelE100\.m\|E100Hw\.c\|E100Logic\.c" "$DST.log" | grep -i "warning\|error"
[ $rc -ne 0 ] && tail -40 "$DST.log"
ls -l "$DST"/*.apk
# A fixed name for guest-remote.ps1 -Fetch, whatever version rbuild stamps
for f in "$DST"/*.apk; do cp "$f" /build/out/intele100.apk; done
exit $rc
