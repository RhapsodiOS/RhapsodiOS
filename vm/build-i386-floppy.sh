#!/bin/sh
# Build i386 drvPCFloppy; stage Floppy_reloc to /build/out/i386
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
SRC=/build/source/src/drivers-i386/ide/drvPCFloppy
name=Floppy
dir=drvPCFloppy
proj=Floppy.drvproj

mkdir -p "$OUT"
echo "======== build $name ($dir) ========"
cd "$SRC" || exit 1
find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
while read f; do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 clean >/tmp/${name}-clean.log 2>&1
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 >"/tmp/${name}.log" 2>&1
ec=$?
echo "make exit=$ec for $name"
echo "--- hard errors (first 80) ---"
grep -n 'undeclared\|illegal\|parse error\|void value\|conflicting\|too few\|too many\|structure has\|Error \|found `' "/tmp/${name}.log" | head -80
echo "--- log tail ---"
tail -40 "/tmp/${name}.log"

reloc=`find "$SRC" -name "${name}_reloc" -type f 2>/dev/null | head -1`
if [ -z "$reloc" ] || [ ! -f "$reloc" ]; then
	echo "FAILED: no ${name}_reloc" >&2
	find "$SRC" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2
	exit 1
fi
file "$reloc"
dst="$OUT/$dir/$name.config"
rm -rf "$dst"
mkdir -p "$dst"
cp -p "$reloc" "$dst/"
if [ -d "$SRC/$proj" ]; then
	for f in "$SRC/$proj"/*.table; do
		[ -f "$f" ] || continue
		cp -p "$f" "$dst/"
	done
	if [ -d "$SRC/$proj/English.lproj" ]; then
		cp -rp "$SRC/$proj/English.lproj" "$dst/"
	fi
fi
# Default.table may sit at drvproj root
if [ ! -f "$dst/Default.table" ] && [ -f "$SRC/$proj/Default.table" ]; then
	cp -p "$SRC/$proj/Default.table" "$dst/"
fi
cat > "$OUT/$dir/README.txt" <<EOF
i386 $name ($dir)
-----------------
${name}_reloc is the i386 loadable kernel server (kl_ld).
make exit status was: $ec
EOF
echo "staged $dst"
ls -la "$dst"
echo "=== floppy done ==="
exit 0
