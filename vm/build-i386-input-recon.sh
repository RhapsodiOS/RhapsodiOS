#!/bin/sh
# Build the i386 input drivers under reconstruction; stage reloc bundles.
# Userspace helpers (PreLoad/PostLoad) may fail on a PPC host — accept
# success when the loadable *_reloc exists.

export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
INPUT=/build/source/src/drivers-i386/input
mkdir -p "$OUT"

# Live System.framework on this guest lacks DriverKit private headers.
# Symlink from bootstrap-root when absent; never overwrite a live path.
BOOTFW=/build/bootstrap-root/System/Library/Frameworks/System.framework/Versions/B
LIVEFW=/System/Library/Frameworks/System.framework
if [ ! -e "$LIVEFW/PrivateHeaders" ]; then
	if [ ! -d "$BOOTFW/PrivateHeaders" ]; then
		echo "build-i386-input-recon: missing $BOOTFW/PrivateHeaders" >&2
		exit 1
	fi
	ln -s "$BOOTFW/PrivateHeaders" "$LIVEFW/PrivateHeaders" || exit 1
	echo "planted $LIVEFW/PrivateHeaders -> $BOOTFW/PrivateHeaders"
fi
if [ ! -e "$LIVEFW/Headers/objc/zone.h" ]; then
	if [ ! -f "$BOOTFW/Headers/objc/zone.h" ]; then
		echo "build-i386-input-recon: missing $BOOTFW/Headers/objc/zone.h" >&2
		exit 1
	fi
	mkdir -p "$LIVEFW/Headers/objc"
	ln -s "$BOOTFW/Headers/objc/zone.h" "$LIVEFW/Headers/objc/zone.h" || exit 1
	echo "planted $LIVEFW/Headers/objc/zone.h -> $BOOTFW/Headers/objc/zone.h"
fi

build_one() {
	name="$1"	# PS2Mouse / SerialPointingDevice / ...
	dir="$2"	# drvPS2Mouse / ...
	proj="$3"	# PS2Mouse.drvproj / ...
	# $4 (optional)	# lksproj to build before the drvproj, e.g. PCParallelPort.lksproj
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


	# drvPCParallel's drvproj lists PostLoad/PreLoad in TOOLS beside the
	# Kernel Server; those need i386 crt/libDriver this PPC guest lacks and
	# can die before the lksproj is reached. Build a named lksproj first so
	# the reloc gate still holds when the tools fail.
	lks="$4"
	if [ -n "$lks" ] && [ -d "$src/$proj/$lks" ]; then
		echo "======== build $name Kernel Server ($lks) ========"
		cd "$src/$proj/$lks" || return 1
		gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
		echo "lks make exit=$? for $name"
		cd "$src" || return 1
	fi

	gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
	ec=$?

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
# by directory name, e.g. `sh build-i386-input-recon.sh drvPS2Mouse`.
#
# This dispatches through `case` rather than a want()-returns-status helper.
# Rhapsody's 1999 Bourne /bin/sh applies `set -e` to *any* function that returns
# nonzero, including one called from an `if` condition, so a predicate function
# that answers "no" terminates the whole script. That is also why `set -e` is
# not used above: a driver that fails to build must not abort the loop, it must
# set fail=1 and let the remaining drivers run.
if [ $# -eq 0 ]; then
	TARGETS="drvPS2Mouse drvSerialPointingDevice drvPS2Keyboard drvPCParallel drvBusMouse drvISASerialPort"
else
	TARGETS="$*"
fi

fail=0
built=
for d in $TARGETS; do
	case "$d" in
	drvPS2Mouse)
		build_one PS2Mouse drvPS2Mouse PS2Mouse.drvproj || fail=1
		;;
	drvSerialPointingDevice)
		build_one SerialPointingDevice drvSerialPointingDevice SerialPointingDevice.drvproj || fail=1
		;;
	drvPS2Keyboard)
		build_one PS2Keyboard drvPS2Keyboard PS2Keyboard.drvproj || fail=1
		;;
	drvPCParallel)
		build_one ParallelPort drvPCParallel PCParallelPort.drvproj PCParallelPort.lksproj || fail=1
		;;
	drvBusMouse)
		build_one BusMouse drvBusMouse BusMouse.drvproj || fail=1
		;;
	drvISASerialPort)
		build_one ISASerialPort drvISASerialPort ISASerialPort.drvproj || fail=1
		;;
	*)
		echo "unknown driver: $d" >&2
		fail=1
		continue
		;;
	esac
	built="$built $d"
done

echo "======== summary ========"
for d in $built; do
	find "$OUT/$d" -type f 2>/dev/null | sort || true
done
for d in $built; do
	find "$OUT/$d" -name '*_reloc' -type f -exec file {} \; 2>&1 || true
done
echo "=== input-recon done fail=$fail built:$built ==="
exit $fail
