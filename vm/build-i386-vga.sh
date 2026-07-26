#!/bin/sh
# Build the VGA display driver under reconstruction; stage VGA.config.
# Accept the run when both VGA_reloc and VGA_psdrvr exist, even if a
# packaging rule later in the makefile exits nonzero.

export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
SRC=/build/source/src/drivers-i386/video/drvVGA
PROJ=$SRC/VGA.drvproj
mkdir -p "$OUT"

FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

if [ ! -f "$SRC/Makefile" ]; then
	echo "MISSING $SRC/Makefile" >&2
	exit 1
fi

echo "======== build VGA (drvVGA) ========"
cd "$SRC"
find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
while read f; do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
ec=$?
echo "make exit=$ec for VGA"

reloc=`find "$SRC" -name VGA_reloc -type f 2>/dev/null | head -1`
psdrvr=`find "$SRC" -name VGA_psdrvr -type f 2>/dev/null | head -1`

fail=0
if [ -z "$reloc" ] || [ ! -f "$reloc" ]; then
	echo "FAILED: no VGA_reloc" >&2
	fail=1
fi
if [ -z "$psdrvr" ] || [ ! -f "$psdrvr" ]; then
	echo "FAILED: no VGA_psdrvr" >&2
	fail=1
fi
if [ $fail -ne 0 ]; then
	find "$SRC" \( -name '*reloc*' -o -name '*psdrvr*' -o -name '*.config' \) 2>/dev/null | head -40 >&2 || true
	echo "=== vga done fail=1 ==="
	exit 1
fi

file "$reloc"
file "$psdrvr"

dst="$OUT/drvVGA/VGA.config"
rm -rf "$dst"
mkdir -p "$dst"
cp -p "$reloc" "$dst/"
cp -p "$psdrvr" "$dst/"
for f in "$PROJ"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$dst/"
done
if [ -f "$PROJ/DriverInfo" ]; then
	cp -p "$PROJ/DriverInfo" "$dst/"
fi
if [ -d "$PROJ/English.lproj" ]; then
	cp -rp "$PROJ/English.lproj" "$dst/"
fi
vgabundle=`find "$SRC" -name VGA -type f 2>/dev/null | head -1`
if [ -n "$vgabundle" ] && [ -f "$vgabundle" ]; then
	cp -p "$vgabundle" "$dst/"
	echo "staged version bundle VGA"
fi

cat > "$OUT/drvVGA/README.txt" <<EOF
i386 VGA (drvVGA)
-----------------
VGA_reloc is the i386 loadable kernel server (kl_ld).
VGA_psdrvr is the user-space Window Server bundle.
make exit status was: $ec
EOF

echo "staged $dst"
ls -la "$dst"
echo "=== vga done fail=0 ==="
exit 0
