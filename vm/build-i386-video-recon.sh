#!/bin/sh
# Build the i386 video drivers under reconstruction; stage config bundles.
#
# drvCirrusLogicGD5434 must link: its _reloc is the deliverable.
# drvIBMThinkPad760EDDisplay precompiles vidBIOS.m and assembles emu486.s,
# exports them through OPTIONAL_LDFLAGS so they follow the instance object,
# emits VERS_OFILE, and stages its _reloc. .objc_class_name_vidBIOS must not
# remain undefined, _emu486 must be defined, and the version symbols must
# be present; those gates fail the ThinkPad arm only.
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

# Compile vidBIOS.m and assemble emu486.s in the lksproj, then export
# absolute paths so Makefile.preamble's OPTIONAL_LDFLAGS reaches kl_ld.
# Same -Wno-format / kernelserver flags as IBMThinkPad760ED.m; as -arch
# i386 matches smapi.s. No local; Rhapsody /bin/sh is 1999 Bourne.
prebuild_thinkpad_extras() {
	lks="$VIDEO/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj"
	if [ ! -f "$lks/vidBIOS.m" ] || [ ! -f "$lks/emu486.s" ]; then
		echo "FAILED: vidBIOS.m or emu486.s missing under $lks" >&2
		return 1
	fi
	cd "$lks" || return 1
	echo "cc vidBIOS.m -> vidBIOS.i386.o"
	/usr/bin/cc -arch i386 -O -Wmost -Wno-format -g -fno-common -I. -pipe \
		-static -DKERNEL -D_KERNEL -DMACH_USER_API \
		-DKERNEL_SERVER_INSTANCE=IBMThinkPad760EDDisplayDriver_instance \
		-F/System/Library/PrivateFrameworks \
		-F/System/Library/PrivateFrameworks \
		-ObjC -c vidBIOS.m -o vidBIOS.i386.o
	if [ $? -ne 0 ]; then
		echo "FAILED: cc vidBIOS.m" >&2
		return 1
	fi
	echo "as emu486.s -> emu486.i386.o"
	/usr/bin/as -arch i386 -o emu486.i386.o emu486.s
	if [ $? -ne 0 ]; then
		echo "FAILED: as emu486.s" >&2
		return 1
	fi
	if [ ! -f vidBIOS.i386.o ] || [ ! -f emu486.i386.o ]; then
		echo "FAILED: extras missing after compile/assemble" >&2
		return 1
	fi
	VIDBIOS_I386=`pwd`/vidBIOS.i386.o
	EMU486_I386=`pwd`/emu486.i386.o
	export VIDBIOS_I386
	export EMU486_I386
	echo "export VIDBIOS_I386=$VIDBIOS_I386"
	echo "export EMU486_I386=$EMU486_I386"
	return 0
}

check_thinkpad_reloc() {
	reloc="$1"
	if /usr/bin/nm -u "$reloc" | grep objc_class_name_vidBIOS >/dev/null; then
		echo "FAILED: .objc_class_name_vidBIOS still undefined in $reloc" >&2
		return 1
	fi
	if /usr/bin/nm -u "$reloc" | grep '_emu486' >/dev/null; then
		echo "FAILED: _emu486 still undefined in $reloc" >&2
		return 1
	fi
	if /usr/bin/nm "$reloc" | grep '_emu486' >/dev/null; then
		echo "defined _emu486"
	else
		echo "FAILED: _emu486 missing from $reloc" >&2
		return 1
	fi
	vers_miss=0
	if /usr/bin/nm "$reloc" | grep IBMThinkPad760EDDisplayDriver_VERS_STRING >/dev/null; then
		echo "found _IBMThinkPad760EDDisplayDriver_VERS_STRING"
	else
		echo "WARNING: _IBMThinkPad760EDDisplayDriver_VERS_STRING missing from $reloc" >&2
		vers_miss=1
	fi
	if /usr/bin/nm "$reloc" | grep IBMThinkPad760EDDisplayDriver_VERS_NUM >/dev/null; then
		echo "found _IBMThinkPad760EDDisplayDriver_VERS_NUM"
	else
		echo "WARNING: _IBMThinkPad760EDDisplayDriver_VERS_NUM missing from $reloc" >&2
		vers_miss=1
	fi
	if [ $vers_miss -ne 0 ]; then
		echo "FAILED: version symbols missing from $reloc" >&2
		return 1
	fi
	return 0
}

build_objects() {
	name="$1"	# IBMThinkPad760EDDisplayDriver
	dir="$2"	# drvIBMThinkPad760EDDisplay
	shift 2		# remaining args are the required object basenames
	src="$VIDEO/$dir"
	echo "======== build $name ($dir) ========"
	run_make "$src" || return 1
	ec=$MAKE_EC
	echo "make exit=$ec for $name"

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

	reloc=`find "$src" -name "${name}_reloc" \( -type f -o -type l \) 2>/dev/null | head -1`
	if [ -z "$reloc" ]; then
		echo "FAILED: no ${name}_reloc for $name" >&2
		return 1
	fi
	echo "relocatable link produced $reloc"
	file "$reloc"
	dst="$OUT/$dir/$name.config"
	rm -rf "$dst"
	mkdir -p "$dst"
	cp -p "$reloc" "$dst/"
	echo "staged $dst"
	ls -la "$dst"
	check_thinkpad_reloc "$reloc" || return 1
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
		if prebuild_thinkpad_extras; then
			build_objects IBMThinkPad760EDDisplayDriver drvIBMThinkPad760EDDisplay \
				IBMThinkPad760ED.o TransferTable.o smapi.o || fail=1
		else
			fail=1
		fi
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
