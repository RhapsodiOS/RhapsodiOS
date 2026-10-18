#!/bin/sh
# Stage canonical sibling inputs for builders which copy one project at a time.
set -eu
if test "$#" != 2; then echo 'usage: package-source.sh SOURCE_ROOT EMPTY_OUTPUT_DIR' >&2;exit 1;fi
source_root=$(cd "$1" && pwd)
driver=drivers-ppc/sound/drvPPCScreamer
shared=drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj
test -f "$source_root/$driver/apk/pkginfo"
for name in PPCDBDMAAudio.c PPCDBDMAAudio.h TASTime.c TASTime.h; do test -f "$source_root/$shared/$name";done
mkdir -p "$2"
output=$(cd "$2" && pwd)
case "$output/" in "$source_root/"*) echo 'Output must be outside the source tree' >&2;exit 1;;esac
if test -n "$(ls -A "$output")"; then echo 'Output must be empty' >&2;exit 1;fi
mkdir -p "$output/$driver" "$output/$shared" "$output/apk"
tar -cf "$output/.driver.tar" --exclude='*.build' --exclude='*.config' --exclude='*.exe' --exclude='*.o' --exclude='*.a' \
    --exclude='screamer_identity_test' --exclude='screamer_core_test' \
    --exclude='screamer_codec_test' --exclude='screamer_runtime_test' \
    --exclude='screamer_profile_test' --exclude='screamer_pcm_test' \
    --exclude='screamer_adapter_test' -C "$source_root/$driver" .
(cd "$output/$driver" && tar -xf "$output/.driver.tar")
rm -f "$output/.driver.tar"
for name in PPCDBDMAAudio.c PPCDBDMAAudio.h TASTime.c TASTime.h; do
    cp "$source_root/$shared/$name" "$output/$shared/$name"
done
cp "$source_root/$driver/apk/pkginfo" "$output/apk/pkginfo"
cat >"$output/Makefile" <<'MAKEFILE'
SCREAMER_ROOT := $(shell pwd)
SCREAMER_DRIVER = drivers-ppc/sound/drvPPCScreamer
.PHONY: all installhdrs install clean
all installhdrs install clean:
	$(MAKE) -C $(SCREAMER_DRIVER) SRCROOT="$(SCREAMER_ROOT)/$(SCREAMER_DRIVER)" $@
MAKEFILE
