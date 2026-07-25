#!/bin/sh
# Build i386 drvPCIBus, drvEISABus, drvPCMCIABus; stage reloc bundles.
# Userspace helpers (PostLoad/PnPDump) often fail on a PPC host — accept
# success when the loadable *_reloc exists.
set -e
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
BUS=/build/source/src/drivers-i386/bus
mkdir -p "$OUT"

# Ensure framework PrivateHeaders symlink (from prior kernel build session).
FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

build_one() {
	name="$1"	# PCIBus / EISABus / PCMCIABus
	dir="$2"	# drvPCIBus / ...
	proj="$3"	# PCIBus.drvproj / ...
	src="$BUS/$dir"
	if [ ! -f "$src/Makefile" ]; then
		echo "MISSING $src/Makefile" >&2
		return 1
	fi
	echo "======== build $name ($dir) ========"
	cd "$src"
	# Strip CR from makefiles
	find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
	while read f; do
		tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
	done

	# Best-effort build; ignore overall make status if reloc lands.
	set +e
	gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
	ec=$?
	set -e
	echo "make exit=$ec for $name"

	reloc=
	# Prefer freshly built .config next to project
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
	# Tables / strings from drvproj
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

	cat > "$OUT/$dir/README.txt" <<EOF
i386 $name ($dir)
-----------------
${name}_reloc is the i386 loadable kernel server (kl_ld).
Userspace helpers (PostLoad / PnPDump) may be absent: they need i386
crt/libDriver which this PPC guest does not provide.
make exit status was: $ec
EOF
	echo "staged $dst"
	ls -la "$dst"
	return 0
}

# With no arguments, build every driver. Otherwise build only those named,
# by directory name, e.g. `sh build-i386-bus-drivers.sh Intel824X0PCI`.
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
# Under set -e, use `|| fail=1` so a failed driver does not abort the script.
if want drvPCIBus "$@"; then
	build_one PCIBus drvPCIBus PCIBus.drvproj || fail=1
	built="$built drvPCIBus"
fi
if want drvEISABus "$@"; then
	build_one EISABus drvEISABus EISABus.drvproj || fail=1
	built="$built drvEISABus"
fi
if want drvPCMCIABus "$@"; then
	build_one PCMCIABus drvPCMCIABus PCMCIABus.drvproj || fail=1
	built="$built drvPCMCIABus"
fi
if want Intel824X0PCI "$@"; then
	build_one Intel824X0 Intel824X0PCI Intel824X0.drvproj || fail=1
	built="$built Intel824X0PCI"
fi
if want Intel82365PCMCIA "$@"; then
	build_one PCIC Intel82365PCMCIA PCIC.drvproj || fail=1
	built="$built Intel82365PCMCIA"
fi

echo "======== summary ========"
for d in $built; do
	find "$OUT/$d" -type f 2>/dev/null | sort || true
done
for d in $built; do
	find "$OUT/$d" -name '*_reloc' -type f -exec file {} \; 2>&1 || true
done
echo "=== bus-drivers done fail=$fail built:$built ==="
exit $fail
