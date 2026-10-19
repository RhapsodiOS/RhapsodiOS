#!/bin/sh
set -eu
source_root=$(cd "$(dirname "$0")/../../../.." && pwd)
relative_driver=drivers-ppc/sound/drvPPCScreamer
driver="$source_root/$relative_driver"
shared=drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj
test_root=$(mktemp -d /tmp/screamer-package.XXXXXX)
cp -R "$driver" "$test_root/direct"
if cc -I"$test_root/direct/PPCScreamer.drvproj/PPCScreamer.lksproj" -c \
    "$test_root/direct/PPCScreamer.drvproj/PPCScreamer.lksproj/ScreamerRuntime.c" \
    -o "$test_root/direct.o" >"$test_root/direct.log" 2>&1; then
    echo 'Direct copy unexpectedly contains canonical helper inputs' >&2;exit 1
fi
for name in PPCDBDMAAudio.c PPCDBDMAAudio.h TASTime.c TASTime.h; do
    cksum "$source_root/$shared/$name"
done >"$test_root/before"
sh "$driver/package-source.sh" "$source_root" "$test_root/package"
for name in PPCDBDMAAudio.c PPCDBDMAAudio.h TASTime.c TASTime.h; do
    cmp "$source_root/$shared/$name" "$test_root/package/$shared/$name"
    cksum "$source_root/$shared/$name"
done >"$test_root/after"
cmp "$test_root/before" "$test_root/after"
mkdir "$test_root/package/$relative_driver/PPCScreamer.config"
echo stale >"$test_root/package/$relative_driver/PPCScreamer.config/marker"
sh "$driver/package-source.sh" "$test_root/package" "$test_root/repackage"
test ! -d "$test_root/repackage/$relative_driver/PPCScreamer.config"
test -f "$test_root/package/$relative_driver/PPCScreamer.config/marker"
if sh "$driver/package-source.sh" "$source_root" "$test_root/package" >"$test_root/repeat.log" 2>&1; then
    echo 'Nonempty output accepted' >&2;exit 1
fi
echo "Screamer source staging passed: $test_root/package"
