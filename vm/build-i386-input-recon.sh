#!/bin/sh
# Build the i386 input drivers under reconstruction; stage reloc bundles.
# Userspace helpers (PreLoad/PostLoad) may fail on a PPC host — accept
# success when the loadable *_reloc exists.
set -e
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
INPUT=/build/source/src/drivers-i386/input
mkdir -p "$OUT"

FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

build_one() {
	name="$1"	# PS2Mouse / SerialPointingDevice / ...
	dir="$2"	# drvPS2Mouse / ...
	proj="$3"	# PS2Mouse.drvproj / ...
	src="$INPUT/$dir"
	if [ ! -f "$src/Makefile" ]; then
		echo "MISSING $src/Makefile" >&2
		return 1
	fi
	echo "======== build $name ($dir) ========"
	cd "$src"
	find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
	while read f; do
		tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
	done

	set +e
	gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
	ec=$?
	set -e
	echo "make exit=$ec for $name"

	reloc=
	for cand in \
		"$src/$name.config/${name}_reloc" \
		"$src/$proj/$name.config/${name}_reloc" \
		"$src/${name}.config/${name}_reloc"
	do
		if [ -f "$cand" ]; then
			reloc=$cand
			break
		fi
	done
	if [ -z "$reloc" ]; then
		reloc=`find "$src" -name "${name}_reloc" -type f 2>/dev/null | head -1`
	fi
	if [ -z "$reloc" ] || [ ! -f "$reloc" ]; then
		echo "FAILED: no ${name}_reloc for $name" >&2
		find "$src" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2 || true
		return 1
	fi
	file "$reloc"

	dst="$OUT/$dir/$name.config"
	rm -rf "$dst"
	mkdir -p "$dst"
	cp -p "$reloc" "$dst/"
	if [ -d "$src/$proj" ]; then
		for f in "$src/$proj"/*.table; do
			[ -f "$f" ] || continue
			cp -p "$f" "$dst/"
		done
		if [ -f "$src/$proj/DriverInfo" ]; then
			cp -p "$src/$proj/DriverInfo" "$dst/"
		fi
		if [ -d "$src/$proj/English.lproj" ]; then
			cp -rp "$src/$proj/English.lproj" "$dst/"
		fi
	fi
	if [ ! -f "$dst/Default.table" ] && [ -f "$src/$proj/Default.table" ]; then
		cp -p "$src/$proj/Default.table" "$dst/"
	fi

	# drvPCParallel also builds two user-space tools named in Default.table
	# as "Pre-Load" and "Post-Load"; stage them beside the reloc if present.
	for tool in InstallPPDev RemovePPDev; do
		t=`find "$src" -name "$tool" -type f 2>/dev/null | head -1`
		if [ -n "$t" ]; then
			cp -p "$t" "$dst/"
			echo "staged tool $tool"
		fi
	done

	cat > "$OUT/$dir/README.txt" <<EOF
i386 $name ($dir)
-----------------
${name}_reloc is the i386 loadable kernel server (kl_ld).
Userspace helpers (PreLoad / PostLoad) may be absent: they need i386
crt/libDriver which this PPC guest does not provide.
make exit status was: $ec
EOF
	echo "staged $dst"
	ls -la "$dst"
	return 0
}

# With no arguments, build every driver. Otherwise build only those named,
# by directory name, e.g. `sh build-i386-input-drivers.sh drvPS2Mouse`.
want() {
	[ $# -eq 1 ] && return 0
	target=$1
	shift
	for arg in "$@"; do
		[ "$arg" = "$target" ] && return 0
	done
	return 1
}

fail=0
built=
if want drvPS2Mouse "$@"; then
	build_one PS2Mouse drvPS2Mouse PS2Mouse.drvproj || fail=1
	built="$built drvPS2Mouse"
fi
if want drvSerialPointingDevice "$@"; then
	build_one SerialPointingDevice drvSerialPointingDevice SerialPointingDevice.drvproj || fail=1
	built="$built drvSerialPointingDevice"
fi
if want drvPS2Keyboard "$@"; then
	build_one PS2Keyboard drvPS2Keyboard PS2Keyboard.drvproj || fail=1
	built="$built drvPS2Keyboard"
fi
if want drvPCParallel "$@"; then
	build_one ParallelPort drvPCParallel PCParallelPort.drvproj || fail=1
	built="$built drvPCParallel"
fi
if want drvBusMouse "$@"; then
	build_one BusMouse drvBusMouse BusMouse.drvproj || fail=1
	built="$built drvBusMouse"
fi

echo "======== summary ========"
for d in $built; do
	find "$OUT/$d" -type f 2>/dev/null | sort || true
done
for d in $built; do
	find "$OUT/$d" -name '*_reloc' -type f -exec file {} \; 2>&1 || true
done
echo "=== input-recon done fail=$fail built:$built ==="
exit $fail
