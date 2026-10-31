#!/bin/sh
# Run from vm/guest-remote.ps1 after syncing this driver's source directory.
set -u

PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

SRC=/build/codex-drvintel82596/src/drivers-i386/network/drvIntel82596
DST=/build/out/drvIntel82596-rbuild
STATE=/build/state
TOOLCHAIN=/tmp/drvintel82596-gcc-darwin-i386.conf
LOG=/build/out/drvIntel82596-rbuild.log
DRIVERTOOLS_DST=/build/out/drivertools-i386
DRIVERTOOLS_LOG=/build/out/drivertools-i386.log

mkdir -p "$DST" "$STATE" || exit 1
rm -f "$DST"/Intel82596NetworkDriver_reloc "$DST"/drvintel82596.apk

echo "======== drvIntel82596 focused tests $(date) ========"
(
    cd "$SRC/reconstruction/tests" || exit 1
    sh ./verify.sh all
) || exit $?

sed 's|^path=.*|path=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin|' \
    /build/src/rbuild-1/toolchains/gcc-darwin-i386.conf > "$TOOLCHAIN" || exit 1

echo "======== drivertools dependency via rbuild (i386) $(date) ========"
mkdir -p "$DRIVERTOOLS_DST" || exit 1
rbuild buildpackage --state "$STATE" --toolchain "$TOOLCHAIN" --arch i386 --dir --target all \
    /build/src/driverTools-1 /build/repo "$DRIVERTOOLS_DST" > "$DRIVERTOOLS_LOG" 2>&1
rc=$?
echo "DRIVERTOOLS_BUILD_RC=$rc"
if [ "$rc" -ne 0 ]; then
    tail -60 "$DRIVERTOOLS_LOG"
    exit "$rc"
fi
drivertools=$(find "$DRIVERTOOLS_DST" -type f -name 'drivertools-*-i386.apk' -print | head -1)
if [ -z "$drivertools" ]; then
    echo "DRIVERTOOLS_BUILD_RC=1: expected i386 APK was not produced"
    find "$DRIVERTOOLS_DST" -maxdepth 4 -type f -print
    exit 1
fi
cp "$drivertools" /build/repo/ || exit 1

echo "======== drvIntel82596 via rbuild (i386) $(date) ========"
rbuild buildpackage --state "$STATE" --toolchain "$TOOLCHAIN" --arch i386 --dir --target all \
    "$SRC" /build/repo "$DST" > "$LOG" 2>&1
rc=$?
echo "BUILD_RC=$rc"
if [ "$rc" -ne 0 ]; then
    tail -60 "$LOG"
    exit "$rc"
fi

reloc=$(find "$DST" -type f -name Intel82596NetworkDriver_reloc -print | head -1)
apk=$(find "$DST" -type f -name '*.apk' -print | head -1)
if [ -z "$reloc" ] || [ -z "$apk" ]; then
    echo "BUILD_RC=1: expected reloc and package were not produced"
    find "$DST" -maxdepth 5 -type f -print
    exit 1
fi
[ "$reloc" = "$DST/Intel82596NetworkDriver_reloc" ] || cp "$reloc" "$DST/Intel82596NetworkDriver_reloc" || exit 1
[ "$apk" = "$DST/drvintel82596.apk" ] || cp "$apk" "$DST/drvintel82596.apk" || exit 1
echo "RELOC_PATH=$DST/Intel82596NetworkDriver_reloc"
echo "PACKAGE_PATH=$DST/drvintel82596.apk"
cksum "$DST/Intel82596NetworkDriver_reloc" "$DST/drvintel82596.apk"
exit 0
