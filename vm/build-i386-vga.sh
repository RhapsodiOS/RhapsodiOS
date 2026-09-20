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

# VGA_psdrvr is an MH_BUNDLE, so its lazy stubs need dyld_stub_binding_helper
# out of bundle1.o.  This host only has a ppc /lib/bundle1.o, which ld skips
# with a warning when -arch i386 is in force, and the link then fails on an
# external relocation in __TEXT,__picsymbol_stub.  Assemble Apple's own
# Csu-1/bundle1.s for i386 and hand the result to the link.  If it cannot be
# built the variable stays empty and the host's own bundle1.o is used.
BUNDLE1=$OUT/bundle1-i386.o
CSU=/build/source/src/Csu-1/bundle1.s
if [ -f "$CSU" ] && cc -arch i386 -c -o "$BUNDLE1" "$CSU"; then
	echo "assembled $BUNDLE1 for the psdrvr bundle link"
else
	echo "WARNING: no i386 bundle1.o; the psdrvr link may fail"
	BUNDLE1=
fi

# emu486.s in VGA.lksproj is hand-written i386 assembly, and this
# pb_makefiles vintage has no variable that carries a .s source into the
# kernelserver link (common.make's LOCAL_OFILES never references an
# SFILES-like variable). Assemble it explicitly and hand the object to the
# link through EMU486_I386, which Makefile.preamble feeds to OPTIONAL_LDFLAGS.
EMU486=$OUT/emu486-i386.o
EMU486_S=$SRC/VGA.drvproj/VGA.lksproj/emu486.s
if [ -f "$EMU486_S" ] && cc -arch i386 -c -o "$EMU486" "$EMU486_S"; then
	echo "assembled $EMU486 for the VGA_reloc link"
else
	echo "WARNING: emu486.s did not assemble; VGA_reloc will be missing _emu486"
	EMU486=
fi

echo "======== build VGA (drvVGA) ========"
cd "$SRC"
find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
while read f; do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 BUNDLE1_I386="$BUNDLE1" EMU486_I386="$EMU486" 2>&1
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
