#!/bin/sh
# Build the i386 EIDE driver; stage EIDE.config.
# idemodes.tproj is a user-space helper and may fail on a PPC host - accept
# the run when EIDE_reloc exists.
# Do not use set -e: NeXT /bin/sh treats a nonzero return from a function as
# fatal even inside an `if`.
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
SRC=/build/source/src/drivers-i386/ide/drvEIDE
PROJ=$SRC/EIDE.drvproj
mkdir -p "$OUT"

FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

if [ ! -f "$SRC/Makefile" ]; then
	echo "MISSING $SRC/Makefile" >&2
	exit 1
fi

echo "======== build EIDE (drvEIDE) ========"
cd "$SRC"
find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
while read f; do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
ec=$?
echo "make exit=$ec for EIDE"

reloc=`find "$SRC" -name EIDE_reloc -type f 2>/dev/null | head -1`
if [ -z "$reloc" ] || [ ! -f "$reloc" ]; then
	echo "FAILED: no EIDE_reloc" >&2
	find "$SRC" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -20 >&2
	echo "=== eide done fail=1 ==="
	exit 1
fi
file "$reloc"

dst="$OUT/drvEIDE/EIDE.config"
rm -rf "$dst"
mkdir -p "$dst"
cp -p "$reloc" "$dst/"
for f in "$PROJ"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$dst/"
done
if [ -d "$PROJ/English.lproj" ]; then
	cp -rp "$PROJ/English.lproj" "$dst/"
fi

echo "staged $dst"
ls -la "$dst"
echo "=== eide done fail=0 ==="
exit 0
