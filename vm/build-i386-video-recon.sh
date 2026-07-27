#!/bin/sh
# Build the i386 video drivers under reconstruction; stage config bundles.
#
# drvCirrusLogicGD5434 must link: its _reloc is the deliverable.
# drvIBMThinkPad760EDDisplay's gate is only that the three in-scope objects
# compile. It does produce a _reloc — kl_ld is a relocatable link, so the
# drvVGA-owned .objc_class_name_vidBIOS and _emu486 stay undefined rather
# than failing the link — and that _reloc is staged alongside the Cirrus one
# so parity_check.py has something to read, but it cannot load until drvVGA
# supplies those symbols, so its absence does not fail the build.
#
# Gating is on artifact presence, not on gnumake's exit code, and that is
# deliberate. run_make records gnumake's status in MAKE_EC and each arm echoes
# it as "make exit=", but no arm fails on it: a recursive pb_makefiles build
# can return nonzero for a step outside what these gates cover, and a build
# that produced every artifact we asked for has met the gate regardless. Read
# the echoed "make exit=" and the log for anything else. Keep this POSIX sh -
# Rhapsody's /bin/sh is a 1999 Bourne shell with no "local" and no bashisms.

export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
VIDEO=/build/source/src/drivers-i386/video
mkdir -p "$OUT"

FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

run_make() {
	src="$1"
	if [ ! -f "$src/Makefile" ]; then
		echo "MISSING $src/Makefile" >&2
		MAKE_EC=127
		return 1
	fi
	cd "$src"
	find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
	while read f; do
		tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
	done
	gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
	MAKE_EC=$?
	return 0
}

build_reloc() {
	name="$1"	# CirrusLogicGD5434DisplayDriver
	dir="$2"	# drvCirrusLogicGD5434
	proj="$3"	# CirrusLogicGD5434.drvproj
	src="$VIDEO/$dir"
	echo "======== build $name ($dir) ========"
	run_make "$src" || return 1
	ec=$MAKE_EC
	echo "make exit=$ec for $name"

	reloc=`find "$src" -name "${name}_reloc" -type f 2>/dev/null | head -1`
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
	bundle=`find "$src" -name "$name" -type f 2>/dev/null | head -1`
	if [ -n "$bundle" ]; then
		cp -p "$bundle" "$dst/"
		echo "staged version bundle $name"
	else
		echo "WARNING: no $name version bundle produced" >&2
	fi
	for f in "$src/$proj"/*.table "$src/$proj"/*.modes; do
		[ -f "$f" ] || continue
		cp -p "$f" "$dst/"
	done
	if [ -d "$src/$proj/English.lproj" ]; then
		cp -rp "$src/$proj/English.lproj" "$dst/"
	fi
	echo "staged $dst"
	ls -la "$dst"
	return 0
}

build_objects() {
	name="$1"	# IBMThinkPad760EDDisplayDriver
	dir="$2"	# drvIBMThinkPad760EDDisplay
	shift 2		# remaining args are the required object basenames
	src="$VIDEO/$dir"
	echo "======== build $name ($dir), objects only ========"
	run_make "$src" || return 1
	ec=$MAKE_EC
	echo "make exit=$ec for $name (objects, not a loadable driver)"

	miss=0
	for o in $*; do
		# pb_makefiles leaves the arch-less name as a symlink to the
		# per-arch object, so -type f would miss it.
		found=`find "$src" -name "$o" \( -type f -o -type l \) 2>/dev/null | head -1`
		if [ -z "$found" ]; then
			echo "FAILED: $o was not compiled" >&2
			miss=1
		else
			echo "compiled $found"
		fi
	done
	if [ $miss -ne 0 ]; then
		return 1
	fi

	# kl_ld does a relocatable link, so a _reloc IS produced even with
	# drvVGA's symbols undefined. Report and stage it the way build_reloc
	# does, so parity_check.py has something to read and the summary has
	# something to list. Its presence is reported, never required: the
	# objects above are the gate.
	reloc=`find "$src" -name "${name}_reloc" \( -type f -o -type l \) 2>/dev/null | head -1`
	if [ -n "$reloc" ]; then
		echo "relocatable link produced $reloc"
		file "$reloc"
		dst="$OUT/$dir/$name.config"
		rm -rf "$dst"
		mkdir -p "$dst"
		cp -p "$reloc" "$dst/"
		echo "staged $dst"
		ls -la "$dst"
	else
		echo "NOTE: no ${name}_reloc this time; objects still gate the build."
	fi

	echo "NOTE: $name leaves .objc_class_name_vidBIOS and _emu486 undefined;"
	echo "NOTE: it cannot load until drvVGA supplies vidBIOS.m and emu486."
	return 0
}

if [ $# -eq 0 ]; then
	TARGETS="drvCirrusLogicGD5434 drvIBMThinkPad760EDDisplay"
else
	TARGETS="$*"
fi

fail=0
built=
for d in $TARGETS; do
	case "$d" in
	drvCirrusLogicGD5434)
		build_reloc CirrusLogicGD5434DisplayDriver drvCirrusLogicGD5434 CirrusLogicGD5434.drvproj || fail=1
		;;
	drvIBMThinkPad760EDDisplay)
		build_objects IBMThinkPad760EDDisplayDriver drvIBMThinkPad760EDDisplay \
			IBMThinkPad760ED.o TransferTable.o smapi.o || fail=1
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
echo "=== video-recon done fail=$fail built:$built ==="
exit $fail
