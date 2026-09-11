#!/bin/sh
# Build one i386 SCSI driver on the Rhapsody guest and stage its _reloc.
# Usage: sh vm/build-i386-scsi.sh drvAdaptec6X60

set -e

DRV="$1"
if [ -z "$DRV" ]; then
    echo "usage: $0 drvAdaptec6X60" >&2
    exit 2
fi

ROOT="${SRCROOT:-/build/source}"
SRC="$ROOT/src/drivers-i386/scsi/$DRV"
STAGE="$ROOT/out/i386/$DRV"
DST="/tmp/${DRV}-dst"

if [ ! -d "$SRC" ]; then
    echo "build-i386-scsi: missing $SRC" >&2
    exit 1
fi

# Strip CR so gnumake does not treat it as part of a target name.
find "$SRC" -type f \( -name Makefile -o -name Makefile.preamble -o -name Makefile.postamble -o -name '*.make' \) -print | while read f
do
    tr -d '\r' < "$f" > "$f.nocr" && mv "$f.nocr" "$f"
done

LKS=`ls -d "$SRC"/*.drvproj/*.lksproj 2>/dev/null | head -1`
if [ -z "$LKS" ]; then
    echo "build-i386-scsi: no .lksproj under $SRC" >&2
    exit 1
fi

cd "$LKS"
gnumake clean || true
gnumake

RELOC=`ls -1 *_reloc 2>/dev/null | head -1`
if [ -z "$RELOC" ]; then
    echo "FAILED: no _reloc in $LKS" >&2
    exit 1
fi

rm -rf "$DST"
mkdir -p "$DST" "$STAGE"
# install if the project supports it; otherwise copy the reloc
if gnumake DSTROOT="$DST" install; then
    find "$DST" -name '*_reloc' -exec cp {} "$STAGE/" \;
else
    cp "$RELOC" "$STAGE/"
fi

echo "=== scsi-recon done fail=0 built: $DRV reloc=$RELOC ==="
ls -l "$STAGE"
