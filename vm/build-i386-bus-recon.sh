#!/bin/sh
# Build drvEISABus (kernel server + PnPDump) and stage both Mach-Os.
# Usage: sh vm/build-i386-bus-recon.sh
#
# Gating is on artifact presence, not gnumake's exit code. A recursive
# pb_makefiles build can return nonzero for a step outside what we need.
# Keep this POSIX sh — Rhapsody's /bin/sh is a 1999 Bourne shell.

ROOT="${SRCROOT:-/build/source}"
SRC="$ROOT/src/drivers-i386/bus/drvEISABus"
PROJ="$SRC/EISABus.drvproj"
STAGE="$ROOT/out/i386/drvEISABus/EISABus.config"

if [ ! -d "$PROJ" ]; then
	echo "build-i386-bus-recon: missing $PROJ" >&2
	exit 1
fi

find "$SRC" -type f \( -name Makefile -o -name Makefile.preamble -o -name Makefile.postamble -o -name '*.make' \) -print |
while read f
do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

echo "======== build EISABus (drvEISABus) ========"
cd "$PROJ" || exit 1
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386
echo "make exit=$?"

RELOC=""
for f in `find "$SRC" -name EISABus_reloc -print`
do
	RELOC="$f"
	break
done
if [ -z "$RELOC" ] || [ ! -f "$RELOC" ]; then
	echo "FAILED: no EISABus_reloc" >&2
	find "$SRC" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2
	exit 1
fi

PNP=""
for f in `find "$SRC" -name PnPDump -print`
do
	case "$f" in
	*.m|*.h)
		;;
	*)
		PNP="$f"
		break
		;;
	esac
done
if [ -z "$PNP" ] || [ ! -f "$PNP" ]; then
	echo "FAILED: no PnPDump executable" >&2
	find "$SRC" -name 'PnPDump*' 2>/dev/null | head -40 >&2
	exit 1
fi

mkdir -p "$STAGE"
cp -p "$RELOC" "$STAGE/"
cp -p "$PNP" "$STAGE/"
for f in "$PROJ"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$STAGE/"
done

echo "=== bus-recon done fail=0 built: drvEISABus ==="
ls -l "$STAGE"
