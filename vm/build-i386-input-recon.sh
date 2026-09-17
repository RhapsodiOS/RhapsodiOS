#!/bin/sh
# Build one i386 input driver under reconstruction and stage its _reloc.
# Usage: sh vm/build-i386-input-recon.sh drvPS2Keyboard
#
# Gating is on artifact presence, not gnumake's exit code. A recursive
# pb_makefiles build can return nonzero for a step outside what we need.
# Keep this POSIX sh — Rhapsody's /bin/sh is a 1999 Bourne shell.

# Live System.framework on this guest lacks DriverKit private headers.
# Symlink from bootstrap-root when absent; never overwrite a live path.
BOOTFW=/build/bootstrap-root/System/Library/Frameworks/System.framework/Versions/B
LIVEFW=/System/Library/Frameworks/System.framework
if [ ! -e "$LIVEFW/PrivateHeaders" ]; then
	ln -s "$BOOTFW/PrivateHeaders" "$LIVEFW/PrivateHeaders"
	echo "planted $LIVEFW/PrivateHeaders -> $BOOTFW/PrivateHeaders"
fi
if [ ! -e "$LIVEFW/Headers/objc/zone.h" ]; then
	ln -s "$BOOTFW/Headers/objc/zone.h" "$LIVEFW/Headers/objc/zone.h"
	echo "planted $LIVEFW/Headers/objc/zone.h -> $BOOTFW/Headers/objc/zone.h"
fi

DRV="$1"
NAME=""
PROJ=""
case "$DRV" in
drvPS2Keyboard)
	NAME=PS2Keyboard
	PROJ=PS2Keyboard.drvproj
	;;
*)
	echo "usage: $0 drvPS2Keyboard" >&2
	exit 2
	;;
esac

ROOT="${SRCROOT:-/build/source}"
SRC="$ROOT/src/drivers-i386/input/$DRV"
OUT=/build/out/i386
STAGE="$OUT/$DRV/${NAME}.config"

if [ ! -d "$SRC" ]; then
	echo "build-i386-input-recon: missing $SRC" >&2
	exit 1
fi

find "$SRC" -type f \( -name Makefile -o -name Makefile.preamble -o -name Makefile.postamble -o -name '*.make' \) -print |
while read f
do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

LKS=`ls -d "$SRC"/*.drvproj/*.lksproj 2>/dev/null | head -1`
if [ -z "$LKS" ]; then
	echo "FAILED: no .lksproj under $SRC" >&2
	exit 1
fi

echo "======== build $NAME ($DRV) ========"
cd "$LKS" || exit 1
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386
echo "make exit=$?"

RELOC=`ls -1 ${NAME}_reloc 2>/dev/null | head -1`
if [ -z "$RELOC" ] || [ ! -f "$RELOC" ]; then
	echo "FAILED: no ${NAME}_reloc for $NAME" >&2
	find "$SRC" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2
	exit 1
fi

mkdir -p "$STAGE"
cp -p "$RELOC" "$STAGE/"
for f in "$SRC/$PROJ"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$STAGE/"
done

echo "=== input-recon done fail=0 built: $DRV ==="
ls -l "$STAGE"
