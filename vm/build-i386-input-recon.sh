#!/bin/sh
# Build one i386 input driver under reconstruction and stage its artifacts.
# Usage: sh vm/build-i386-input-recon.sh drvPCParallel
#
# Gating is on ParallelPort_reloc presence, not gnumake's exit code.
# Keep this POSIX sh — Rhapsody's /bin/sh is a 1999 Bourne shell.

DRV="$1"
NAME=""
PROJ=""
case "$DRV" in
drvPCParallel)
	NAME=ParallelPort
	PROJ=PCParallelPort.drvproj
	;;
*)
	echo "usage: $0 drvPCParallel" >&2
	exit 2
	;;
esac

ROOT="${SRCROOT:-/build/source}"
SRC="$ROOT/src/drivers-i386/input/$DRV"
STAGE="$ROOT/out/i386/$DRV/${NAME}.config"

if [ ! -d "$SRC" ]; then
	echo "build-i386-input-recon: missing $SRC" >&2
	exit 1
fi

find "$SRC" -type f \( -name Makefile -o -name Makefile.preamble -o -name Makefile.postamble -o -name '*.make' \) -print |
while read f
do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

DRVPROJ="$SRC/$PROJ"
if [ ! -d "$DRVPROJ" ]; then
	echo "FAILED: no $PROJ under $SRC" >&2
	exit 1
fi

echo "======== build $NAME ($DRV) ========"
cd "$DRVPROJ" || exit 1
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386
echo "make exit=$?"

RELOC=`find "$SRC" -name "${NAME}_reloc" -type f 2>/dev/null | head -1`
if [ -z "$RELOC" ] || [ ! -f "$RELOC" ]; then
	echo "FAILED: no ${NAME}_reloc for $NAME" >&2
	find "$SRC" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2
	exit 1
fi

mkdir -p "$STAGE"
cp -p "$RELOC" "$STAGE/"
for f in "$DRVPROJ"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$STAGE/"
done
for tool in InstallPPDev RemovePPDev; do
	t=`find "$SRC" -name "$tool" -type f 2>/dev/null | head -1`
	if [ -n "$t" ] && [ -f "$t" ]; then
		cp -p "$t" "$STAGE/"
		echo "staged $tool"
	else
		echo "WARNING: no $tool for $NAME"
	fi
done

echo "=== input-recon done fail=0 built: $DRV ==="
ls -l "$STAGE"
