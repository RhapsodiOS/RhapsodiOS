#!/bin/sh
# Run after syncing drivers-i386/network/drvIntel82595 to the build guest.
set -eu
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
SRC=${SRC:-/build/src/drivers-i386/network/drvIntel82595}
DST=${DST:-/build/out/drvIntel82595-rbuild}
sh "$SRC/reconstruction/tests/verify.sh"
mkdir -p "$DST"
rbuild buildpackage --state /build/state --arch i386 --dir --target all \
    "$SRC" /build/repo "$DST" > "$DST.log" 2>&1 || {
    tail -60 "$DST.log"
    exit 1
}
ls -l "$DST"/*.apk
