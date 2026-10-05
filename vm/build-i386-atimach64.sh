#!/bin/sh
# Build and stage the reconstructed i386 ATI Mach64 kernel server.
# Expected guest layout: /build/source, /build/repo, /build/state.

set -eu

export PATH=/build/tools/bin:/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
SRC=/build/source/src/drivers-i386/video/drvATIMach64
PROJECT=$SRC/ATIMach64DisplayDriver.drvproj
LKS=$PROJECT/ATIMach64DisplayDriver.lksproj
REPO=/build/repo
STATE=/build/state
OUT=/build/out/drvATIMach64-rbuild
RUN_OUT=$OUT/runs/v39-2026-10-05
BUILDIT_DIR=$RUN_OUT/buildroots
LOG=$RUN_OUT/build.log
STAGE=/build/out/i386/drvATIMach64/ATIMach64DisplayDriver.config
PACKAGE_STAGE=/build/out/i386/drvATIMach64/packages/v39-2026-10-05
NAME=ATIMach64DisplayDriver

for path in "$SRC/Makefile" "$LKS/Makefile" "$REPO" "$STATE"; do
	if [ ! -e "$path" ]; then
		echo "build-i386-atimach64: missing $path" >&2
		exit 1
	fi
done

mkdir -p "$OUT" "$RUN_OUT" "$BUILDIT_DIR" "$STAGE"
exec 3>&1
exec >"$LOG" 2>&1
# Keep rbuild mutable roots in this task-owned output tree instead of the
# guest-wide /private/tmp/roots default.
export BUILDIT_DIR
# rbuild quarantines an older bad APK before writing a replacement. Clear
# that generated quarantine from this target's private output area first.
find "$RUN_OUT" -name '*.apk.invalid' -type f -exec rm -f {} \;
echo "======== focused native and i386 compile checks ========"
gnumake -C "$LKS/tests" check-abi check-data check-bios-segments \
	check-dac check-mapping check-lifecycle check-init-mapping
echo "======== rbuild buildpackage $NAME (i386) ========"
rbuild buildpackage --state "$STATE" --arch i386 \
	--toolchain /build/source/src/rbuild-1/toolchains/gcc-darwin-i386.conf \
	--dir --target all \
	"$SRC" "$REPO" "$RUN_OUT"

PACKAGES=`find "$RUN_OUT" -name '*.apk' -type f 2>/dev/null`
if [ -z "$PACKAGES" ]; then
	echo "build-i386-atimach64: no package archive produced" >&2
	exit 1
fi
PACKAGE=`find "$RUN_OUT" -name '*.apk' -type f 2>/dev/null | head -1`
RELOC="$RUN_OUT/${NAME}_reloc"
gzip -dc "$PACKAGE" | tar xOf - "./private/Drivers/i386/${NAME}.config/${NAME}_reloc" > "$RELOC"
if [ ! -s "$RELOC" ]; then
	echo "build-i386-atimach64: no ${NAME}_reloc in package archive" >&2
	exit 1
fi

IDENTITY=`file "$RELOC"`
echo "$IDENTITY"
case "$IDENTITY" in
	*i386*) ;;
	*) echo "build-i386-atimach64: artifact is not identified as i386" >&2; exit 1 ;;
esac
cp -p "$RELOC" "$STAGE/"
BUNDLE="$RUN_OUT/$NAME"
gzip -dc "$PACKAGE" | tar xOf - "./private/Drivers/i386/${NAME}.config/$NAME" > "$BUNDLE"
if [ -s "$BUNDLE" ]; then
	cp -p "$BUNDLE" "$STAGE/"
fi
for resource in "$PROJECT"/*.table "$PROJECT"/*.modes; do
	[ -f "$resource" ] || continue
	cp -p "$resource" "$STAGE/"
done
if [ -d "$PROJECT/English.lproj" ]; then
	cp -rp "$PROJECT/English.lproj" "$STAGE/"
fi
cp -p "$PROJECT/DriverInfo" "$STAGE/"
mkdir -p "$PACKAGE_STAGE"
for package in $PACKAGES; do
	cp -p "$package" "$PACKAGE_STAGE/"
done
echo "staged $STAGE/${NAME}_reloc"
echo "staged package archives under $PACKAGE_STAGE"
ls -la "$STAGE"
echo "build log: $LOG"
exec 1>&3
cat "$LOG"
