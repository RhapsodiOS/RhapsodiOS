#!/bin/sh
# Build and stage the reconstructed i386 ATI Mach64 kernel server.
# Expected guest layout: /build/source, /build/repo, /build/state.

set -eu

export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
SRC=/build/source/src/drivers-i386/video/drvATIMach64
PROJECT=$SRC/ATIMach64DisplayDriver.drvproj
LKS=$PROJECT/ATIMach64DisplayDriver.lksproj
REPO=/build/repo
STATE=/build/state
OUT=/build/out/drvATIMach64-rbuild
STAGE=/build/out/i386/drvATIMach64/ATIMach64DisplayDriver.config
PACKAGE_STAGE=/build/out/i386/drvATIMach64/packages
NAME=ATIMach64DisplayDriver

for path in "$SRC/Makefile" "$LKS/Makefile" "$REPO" "$STATE"; do
	if [ ! -e "$path" ]; then
		echo "build-i386-atimach64: missing $path" >&2
		exit 1
	fi
done

mkdir -p "$OUT" "$STAGE"
echo "======== rbuild buildpackage $NAME (i386) ========"
rbuild buildpackage --state "$STATE" --arch i386 --dir --target all \
	"$SRC" "$REPO" "$OUT"

RELOC=`find "$OUT" -name "${NAME}_reloc" -type f 2>/dev/null | head -1`
if [ -z "$RELOC" ] || [ ! -f "$RELOC" ]; then
	echo "build-i386-atimach64: no ${NAME}_reloc produced" >&2
	find "$OUT" -type f 2>/dev/null | head -40 >&2 || true
	exit 1
fi
PACKAGES=`find "$OUT" -name '*.apk' -type f 2>/dev/null`
if [ -z "$PACKAGES" ]; then
	echo "build-i386-atimach64: no package archive produced" >&2
	exit 1
fi

IDENTITY=`file "$RELOC"`
echo "$IDENTITY"
case "$IDENTITY" in
	*i386*) ;;
	*) echo "build-i386-atimach64: artifact is not identified as i386" >&2; exit 1 ;;
esac
cp -p "$RELOC" "$STAGE/"
BUNDLE=`find "$OUT" -name "$NAME" -type f 2>/dev/null | head -1`
if [ -n "$BUNDLE" ] && [ -f "$BUNDLE" ]; then
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
