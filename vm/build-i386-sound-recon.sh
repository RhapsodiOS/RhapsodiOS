#!/bin/sh
# Build the i386 audio drivers under reconstruction; stage reloc bundles.
# Accept success when the loadable *_reloc exists.
#
# No `set -e`: Rhapsody's 1999 Bourne /bin/sh applies it to any function
# returning nonzero, so a driver that fails to build would abort the loop
# instead of setting fail=1 and letting the rest run.

export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
SOUND=/build/source/src/drivers-i386/sound
mkdir -p "$OUT"

FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

build_one() {
	name="$1"	# Beep / SoundBlaster8 / ...
	dir="$2"	# drvBeepSound / drvSB8Sound / ...
	proj="$3"	# Beep.drvproj / SoundBlaster8.drvproj / ...
	src="$SOUND/$dir"
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

	cat > "$OUT/$dir/README.txt" <<EOF
i386 $name ($dir)
-----------------
${name}_reloc is the i386 loadable kernel server (kl_ld).
make exit status was: $ec
EOF
	echo "staged $dst"
	ls -la "$dst"
	return 0
}

# With no arguments, build every driver. Otherwise build only those named,
# by directory name, e.g. `sh build-i386-sound-recon.sh drvBeepSound`.
#
# This dispatches through `case` rather than a want()-returns-status helper,
# for the same shell reason given above.
if [ $# -eq 0 ]; then
	TARGETS="drvBeepSound drvSB8Sound drvES1x88Sound drvSB16Sound"
else
	TARGETS="$*"
fi

fail=0
built=
for d in $TARGETS; do
	case "$d" in
	drvBeepSound)
		build_one Beep drvBeepSound Beep.drvproj || fail=1
		;;
	drvSB8Sound)
		build_one SoundBlaster8 drvSB8Sound SoundBlaster8.drvproj || fail=1
		;;
	drvES1x88Sound)
		build_one ES1x88AudioDriver drvES1x88Sound ES1x88AudioDriver.drvproj || fail=1
		;;
	drvSB16Sound)
		build_one SoundBlaster16 drvSB16Sound SoundBlaster16.drvproj || fail=1
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
echo "=== sound-recon done fail=$fail built:$built ==="
exit $fail
