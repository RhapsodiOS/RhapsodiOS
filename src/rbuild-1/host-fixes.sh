#!/bin/sh
# Host-side fixes for stage-0 bootstrap on PPC Rhapsody.
set -e
export PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/build/tools/usr/local/bin

echo "=== 1. HFS-safe ln (shadow /bin/ln; Libc uses absolute /bin/ln) ==="
mkdir -p /build/bin
if [ ! -f /bin/ln.real ]; then
	cp -p /bin/ln /bin/ln.real
fi
cat > /build/bin/ln << 'ENDLN'
#!/bin/sh
# HFS-safe ln: on hard-link failure, fall back to cp -p for files.
# Directory targets use ln -s (cp -p cannot copy directories; Libsystem
# make_links does ln <dir> <name>).
REALLN=/bin/ln.real
[ -x "$REALLN" ] || REALLN=/bin/ln
for a in "$@"; do
	case "$a" in
	-s|-sf|-fs) exec "$REALLN" "$@" ;;
	esac
done
if "$REALLN" "$@" 2>/dev/null; then
	exit 0
fi
force=0
while [ $# -gt 0 ]; do
	case "$1" in
	-f) force=1; shift ;;
	-*) shift ;;
	*) break ;;
	esac
done
if [ $# -eq 2 ]; then
	src=$1; dst=$2
	[ "$force" = 1 ] && rm -rf "$dst"
	if [ -d "$src" ]; then
		exec "$REALLN" -s "$src" "$dst"
	fi
	exec cp -p "$src" "$dst"
fi
if [ $# -ge 2 ]; then
	n=$#
	eval "dest=\$$n"
	i=1
	while [ $i -lt $n ]; do
		eval "src=\$$i"
		base=`basename "$src"`
		[ "$force" = 1 ] && rm -rf "$dest/$base"
		if [ -d "$src" ]; then
			"$REALLN" -s "$src" "$dest/$base" || exit 1
		else
			cp -p "$src" "$dest/$base" || exit 1
		fi
		i=`expr $i + 1`
	done
	exit 0
fi
echo "ln: fallback failed" >&2
exit 1
ENDLN
chmod 755 /build/bin/ln
cp -p /build/bin/ln /bin/ln
chmod 755 /bin/ln
rm -f /big/hl_src /big/hl_dst
echo hi > /big/hl_src
/bin/ln -f /big/hl_src /big/hl_dst
cmp /big/hl_src /big/hl_dst
rm -f /big/hl_src /big/hl_dst
# Directory symlink fallback (Libsystem make_links)
rm -rf /big/hl_dir /big/hl_dirlink
mkdir -p /big/hl_dir
echo x > /big/hl_dir/f
/bin/ln /big/hl_dir /big/hl_dirlink
test -f /big/hl_dirlink/f && echo ln-dir-fallback OK
rm -rf /big/hl_dir /big/hl_dirlink
echo "ln-fallback OK"

echo "=== 1b. HFS-safe mv (shadow /bin/mv; build_gcc resets PATH) ==="
# Preserve real mv once. Nested gcc enquire uses bare `mv` after PATH=/bin:...
if [ ! -f /bin/mv.real ]; then
	cp -p /bin/mv /bin/mv.real
fi
cat > /build/bin/mv << 'ENDMV'
#!/bin/sh
# HFS-safe mv: rename-over-existing often fails with "Device busy".
REALMV=/bin/mv.real
[ -x "$REALMV" ] || REALMV=/bin/mv
if "$REALMV" "$@" 2>/dev/null; then
	exit 0
fi
force=0
args=
while [ $# -gt 0 ]; do
	case "$1" in
	-f) force=1; shift ;;
	-*) args="$args $1"; shift ;;
	*) break ;;
	esac
done
if [ $# -eq 2 ]; then
	src=$1; dst=$2
	rm -f "$dst"
	if cp -p "$src" "$dst"; then
		rm -f "$src"
		exit 0
	fi
	echo "mv: HFS fallback failed: $src -> $dst" >&2
	exit 1
fi
exec "$REALMV" $args "$@"
ENDMV
chmod 755 /build/bin/mv
# Also replace /bin/mv so absolute /bin/mv and PATH=/bin work
cp -p /build/bin/mv /bin/mv
chmod 755 /bin/mv
rm -f /big/mv_src /big/mv_dst
echo a > /big/mv_src
echo b > /big/mv_dst
/bin/mv /big/mv_src /big/mv_dst
test ! -f /big/mv_src && test -f /big/mv_dst && echo mv-fallback OK
rm -f /big/mv_src /big/mv_dst

echo "=== 2. decomment + makeinfo stubs ==="
# /usr/local/bin may have been a dangling symlink into /tmp/rhapsody
if [ -L /usr/local/bin ]; then rm -f /usr/local/bin; fi
mkdir -p /usr/local/bin /usr/local/lib
# Purge ALL broken /tmp/rhapsody tool symlinks (nmedit/strip/etc.)
for t in /usr/local/bin/*; do
	[ -L "$t" ] || continue
	tgt=`ls -l "$t" | sed 's/.*-> //'`
	case "$tgt" in
	/tmp/rhapsody/*) rm -f "$t"; echo "removed dangling $t" ;;
	esac
done
rm -f /usr/local/bin/decomment /usr/local/bin/makeinfo
/bin/ln -s /build/tools/usr/local/bin/decomment /usr/local/bin/decomment
cat > /usr/local/bin/makeinfo << 'EOF'
#!/bin/sh
# Stage-0 stub: write a minimal .info for each .texinfo/.texi argument.
for a in "$@"; do
	case "$a" in
	*.texinfo)
		b=`basename "$a" .texinfo`
		echo "makeinfo-stub: ${b}.info"
		echo "@setfilename ${b}.info" > "${b}.info"
		;;
	*.texi)
		b=`basename "$a" .texi`
		echo "makeinfo-stub: ${b}.info"
		echo "@setfilename ${b}.info" > "${b}.info"
		;;
	esac
done
exit 0
EOF
chmod 755 /usr/local/bin/makeinfo
cd /tmp
echo '@bye' > t.texinfo
/usr/local/bin/makeinfo t.texinfo
test -f t.info && echo makeinfo-stub OK
rm -f t.texinfo t.info

echo "=== 3. libcompat.a from Darwin deb ==="
rm -rf /tmp/libcompat-extract
mkdir -p /tmp/libcompat-extract
cd /tmp/libcompat-extract
ar x /build/repo/libcompat_12-1_universal-apple-rhapsody.deb
if [ -f data.tar.gz ]; then gnutar xzf data.tar.gz
elif [ -f data.tar ]; then gnutar xf data.tar
else ls -la; exit 1
fi
mkdir -p /usr/local/lib
cp -p usr/local/lib/libcompat.a /usr/local/lib/libcompat.a
ranlib /usr/local/lib/libcompat.a 2>/dev/null || true
ls -l /usr/local/lib/libcompat.a

echo "=== 4. streams headers for cctools ==="
mkdir -p /usr/include/streams \
	/System/Library/Frameworks/System.framework/Versions/B/Headers/streams
cp -p /build/source/src/Libstreams-1/streams.h /usr/include/streams/streams.h
cp -p /build/source/src/Libstreams-1/streams.h \
	/System/Library/Frameworks/System.framework/Versions/B/Headers/streams/streams.h
cp -p /build/source/src/Libstreams-1/streamsextra.h /usr/include/streams/ 2>/dev/null || true
cp -p /build/source/src/Libstreams-1/defs.h /usr/include/streams/ 2>/dev/null || true

echo "=== 5. evio.h into System.framework ==="
SYS=/System/Library/Frameworks/System.framework/Versions/B/Headers
mkdir -p "$SYS/bsd/dev/ppc" "$SYS/bsd/dev/machine" "$SYS/bsd/dev/i386"
K=/build/source/src/kernel-7/bsd/dev
cp -p "$K/ppc/evio.h" "$SYS/bsd/dev/ppc/evio.h"
cp -p "$K/machine/evio.h" "$SYS/bsd/dev/machine/evio.h"
cp -p "$K/i386/evio.h" "$SYS/bsd/dev/i386/evio.h" 2>/dev/null || true
cp -p "$K/evio.h" "$SYS/bsd/dev/evio.h" 2>/dev/null || true
ls -l "$SYS/bsd/dev/ppc/evio.h"

echo "=== 6. Seed System PrivateHeaders/driverkit ==="
# PrivateHeaders/* often dangling into /tmp/rhapsody; replace those we need.
SYS_DK=/System/Library/Frameworks/System.framework/Versions/B/Headers/driverkit
SYS_PRIV=/System/Library/Frameworks/System.framework/PrivateHeaders/driverkit
DK_SRC=/build/source/src/driverkit-3/driverkit
DK_DEFS=/build/source/src/driverkit-3/libDriver/Kernel
mkdir -p "$SYS_DK"
if [ -L "$SYS_PRIV" ] || [ ! -d "$SYS_PRIV" ]; then
	rm -f "$SYS_PRIV"
	mkdir -p "$SYS_PRIV"
fi
# Public-ish headers into Headers; full set + mig defs into PrivateHeaders
if [ -d "$DK_SRC" ]; then
	# Copy flat headers (not subdirs) into PrivateHeaders
	for f in "$DK_SRC"/*.h "$DK_SRC"/*.defs; do
		[ -f "$f" ] || continue
		cp -p "$f" "$SYS_PRIV/"
	done
	cp -p "$DK_SRC/Device_ddm.h" "$SYS_DK/Device_ddm.h" 2>/dev/null || true
	cp -p "$DK_SRC/IODeviceParams.h" "$SYS_DK/" 2>/dev/null || true
	cp -p "$DK_SRC/IOPower.h" "$SYS_DK/" 2>/dev/null || true
fi
if [ -f "$DK_DEFS/Event.defs" ]; then
	cp -p "$DK_DEFS/Event.defs" "$SYS_PRIV/Event.defs"
	echo "seeded Event.defs"
fi
# Replace kernel-7 dangling Device_ddm.h symlink with a real file
rm -f /build/source/src/kernel-7/driverkit/Device_ddm.h
mkdir -p /build/source/src/kernel-7/driverkit
if [ -f "$DK_SRC/Device_ddm.h" ]; then
	cp -p "$DK_SRC/Device_ddm.h" /build/source/src/kernel-7/driverkit/Device_ddm.h
fi
# Also place commonly missing kernel installhdrs inputs into kernel-7/driverkit
for h in IODeviceParams.h IOPower.h ddmPrivate.h volCheck.h Device_ddm.h; do
	if [ -f "$DK_SRC/$h" ] && [ ! -f /build/source/src/kernel-7/driverkit/$h ]; then
		cp -p "$DK_SRC/$h" /build/source/src/kernel-7/driverkit/$h
	elif [ -f "$DK_SRC/$h" ] && [ -L /build/source/src/kernel-7/driverkit/$h ]; then
		rm -f /build/source/src/kernel-7/driverkit/$h
		cp -p "$DK_SRC/$h" /build/source/src/kernel-7/driverkit/$h
	fi
done
ls -l "$SYS_PRIV/Event.defs" "$SYS_PRIV/Device_ddm.h" 2>/dev/null || true

echo "=== 7. Prefer prior indr.NEW if present ==="
rm -f /usr/local/bin/indr
found=`find /big/roots /private/tmp/roots -name 'indr.NEW' -type f 2>/dev/null | head -1`
if [ -n "$found" ]; then
	cp -p "$found" /usr/local/bin/indr
	chmod 755 /usr/local/bin/indr
	echo "indr from $found"
else
	echo "indr not found yet (will come from cctools build)"
fi

echo "=== 8. executable bits lost from Windows sync ==="
# pscp/Windows often strips +x from scripts; restore broadly for bootstrap trees
for d in /build/source/src/cc-1 /build/source/src/cctools-2 \
	/build/source/src/bootstrap_cmds-1 /build/source/src/Commands/bootstrap_cmds; do
	[ -d "$d" ] || continue
	find "$d" -type f \( \
		-name '*.sh' -o -name 'build_*' -o -name 'configure' \
		-o -name 'move-if-change' -o -name 'install-sh' \
		-o -name 'mkinstalldirs' -o -name 'config.sub' \
		-o -name 'config.guess' -o -name 'ylwrap' \
		-o -name 'missing' -o -name 'compile' \
	\) -exec chmod +x {} \; 2>/dev/null || true
done
# Anything under cc-1 that looks like a shell script (starts with #!)
if [ -d /build/source/src/cc-1 ]; then
	find /build/source/src/cc-1 -type f -print |
	while read f; do
		case "`sed -n '1p' \"$f\" 2>/dev/null`" in
		\#!*) chmod +x "$f" ;;
		esac
	done
fi
ls -l /build/source/src/cc-1/build_gcc /build/source/src/cc-1/cc/move-if-change 2>/dev/null || true

echo "=== 9. Purge dangling /tmp/rhapsody lib symlinks + seed libc ==="
for f in /usr/lib/libc_dynamic.dylib /usr/lib/libc_static.a \
	/usr/local/lib/libc_dynamic.dylib /lib/libc_static.a; do
	if [ -L "$f" ]; then
		tgt=`ls -l "$f" | sed 's/.*-> //'`
		case "$tgt" in
		/tmp/rhapsody/*) rm -f "$f"; echo "removed dangling $f" ;;
		esac
	fi
done
# Extract libc archives from Darwin deb so -lc / dyld can link
if [ ! -f /usr/lib/libc.a ] && [ -f /build/repo/libc_78.8-1_universal-apple-rhapsody.deb ]; then
	rm -rf /tmp/libc-extract
	mkdir -p /tmp/libc-extract
	(
		cd /tmp/libc-extract
		ar x /build/repo/libc_78.8-1_universal-apple-rhapsody.deb
		if [ -f data.tar.gz ]; then gnutar xzf data.tar.gz
		elif [ -f data.tar ]; then gnutar xf data.tar
		fi
		# Prefer static/dynamic archives wherever the deb put them
		for a in libc.a libc_static.a libc_dynamic.a libc.dylib libc_dynamic.dylib; do
			found=`find . -name "$a" -type f 2>/dev/null | head -1`
			if [ -n "$found" ]; then
				cp -p "$found" /usr/lib/"$a"
				echo "installed /usr/lib/$a from deb"
			fi
		done
	)
fi
# Alias for -lc if we only got libc_static
if [ ! -e /usr/lib/libc.a ] && [ -f /usr/lib/libc_static.a ]; then
	/bin/ln -s libc_static.a /usr/lib/libc.a
fi
if [ ! -e /usr/lib/libc.dylib ] && [ -f /usr/lib/libc_dynamic.dylib ]; then
	/bin/ln -s libc_dynamic.dylib /usr/lib/libc.dylib
fi
ls -l /usr/lib/libc.a /usr/lib/libc_static.a /usr/lib/libc_dynamic.a 2>/dev/null || true

echo "=== 10. Seed objc/maptable.h into System Headers ==="
# objc4 profile build includes <objc/maptable.h> from the live System tree
SYS_OBJC=/System/Library/Frameworks/System.framework/Versions/B/Headers/objc
mkdir -p "$SYS_OBJC"
if [ -f /build/source/src/objc4-1/runtime/maptable.h ]; then
	cp -p /build/source/src/objc4-1/runtime/maptable.h "$SYS_OBJC/maptable.h"
	echo "seeded $SYS_OBJC/maptable.h"
fi

echo "=== 11. Seed mach/syscall_sw.h + mach-o/rld.h + kmreg_com.h ==="
SYS_HDR=/System/Library/Frameworks/System.framework/Versions/B/Headers
K_MACH=/build/source/src/kernel-7/mach
mkdir -p "$SYS_HDR/mach/ppc" "$SYS_HDR/mach/i386" "$SYS_HDR/mach/machine" \
	/usr/include/mach/ppc /usr/include/mach/i386 /usr/include/mach/machine \
	"$SYS_HDR/mach-o" /usr/include/mach-o \
	"$SYS_HDR/bsd/dev" /usr/include/bsd/dev /usr/include/dev
for h in syscall_sw.h; do
	if [ -f "$K_MACH/$h" ]; then
		cp -p "$K_MACH/$h" "$SYS_HDR/mach/$h"
		cp -p "$K_MACH/$h" /usr/include/mach/$h
	fi
done
for arch in ppc i386 machine; do
	if [ -f "$K_MACH/$arch/syscall_sw.h" ]; then
		cp -p "$K_MACH/$arch/syscall_sw.h" "$SYS_HDR/mach/$arch/syscall_sw.h"
		cp -p "$K_MACH/$arch/syscall_sw.h" /usr/include/mach/$arch/syscall_sw.h
	fi
done
if [ -f /build/source/src/cctools-2/include/mach-o/rld.h ]; then
	cp -p /build/source/src/cctools-2/include/mach-o/rld.h "$SYS_HDR/mach-o/rld.h"
	cp -p /build/source/src/cctools-2/include/mach-o/rld.h /usr/include/mach-o/rld.h
	echo "seeded mach-o/rld.h"
fi
if [ -f /build/source/src/kernel-7/bsd/dev/kmreg_com.h ]; then
	cp -p /build/source/src/kernel-7/bsd/dev/kmreg_com.h "$SYS_HDR/bsd/dev/kmreg_com.h"
	cp -p /build/source/src/kernel-7/bsd/dev/kmreg_com.h /usr/include/bsd/dev/kmreg_com.h
	# fbalert includes <dev/kmreg_com.h>
	cp -p /build/source/src/kernel-7/bsd/dev/kmreg_com.h /usr/include/dev/kmreg_com.h
	echo "seeded kmreg_com.h"
fi
ls -l /usr/include/mach/syscall_sw.h /usr/include/mach-o/rld.h /usr/include/dev/kmreg_com.h 2>&1 | head

echo "=== 11b. Seed libm.a from Darwin deb (dangling /tmp/rhapsody link) ==="
for f in /usr/lib/libm.a /usr/local/lib/libm.a; do
	if [ -L "$f" ]; then
		tgt=`ls -l "$f" | sed 's/.*-> //'`
		case "$tgt" in
		/tmp/rhapsody/*) rm -f "$f"; echo "removed dangling $f" ;;
		esac
	fi
done
if [ ! -f /usr/lib/libm.a ] && [ -f /build/repo/libm_15-1_universal-apple-rhapsody.deb ]; then
	rm -rf /tmp/libm-extract
	mkdir -p /tmp/libm-extract
	(
		cd /tmp/libm-extract
		ar x /build/repo/libm_15-1_universal-apple-rhapsody.deb
		if [ -f data.tar.gz ]; then gnutar xzf data.tar.gz
		elif [ -f data.tar ]; then gnutar xf data.tar
		fi
		found=`find . -name 'libm.a' -type f 2>/dev/null | head -1`
		if [ -n "$found" ]; then
			cp -p "$found" /usr/lib/libm.a
			ranlib /usr/lib/libm.a 2>/dev/null || true
			mkdir -p /usr/local/lib
			cp -p /usr/lib/libm.a /usr/local/lib/libm.a
			echo "installed libm.a from deb"
		fi
	)
fi
ls -l /usr/lib/libm.a 2>&1 | head

echo "=== 11c. Seed machdep/*/features.h ==="
SYS_MD=/System/Library/Frameworks/System.framework/Versions/B/Headers/machdep
K_MD=/build/source/src/kernel-7/machdep
mkdir -p "$SYS_MD/machine" "$SYS_MD/ppc" "$SYS_MD/i386" \
	/usr/include/machdep/machine /usr/include/machdep/ppc /usr/include/machdep/i386
if [ -f "$K_MD/machine/features.h" ]; then
	cp -p "$K_MD/machine/features.h" "$SYS_MD/machine/features.h"
	cp -p "$K_MD/machine/features.h" /usr/include/machdep/machine/features.h
fi
# Arch-specific headers are often missing from this kernel drop; seed stubs.
for arch in ppc i386; do
	src="$K_MD/$arch/features.h"
	mkdir -p "$K_MD/$arch"
	if [ ! -f "$src" ]; then
		cat > "$src" << ENDFEAT
#ifndef _MACHDEP_${arch}_FEATURES_H_
#define _MACHDEP_${arch}_FEATURES_H_
#define KERNEL_FEATURES 1
#endif
ENDFEAT
	fi
	cp -p "$src" "$SYS_MD/$arch/features.h"
	cp -p "$src" /usr/include/machdep/$arch/features.h
done
echo "seeded features.h"
ls -l "$SYS_MD/machine/features.h" "$SYS_MD/ppc/features.h" /usr/include/machdep/ppc/features.h

echo "=== 11d. Patch migcom_untypd: use VERS_STRING stub (skip broken vers.ppc.o) ==="
for preamble in \
	/build/source/src/Commands/bootstrap_cmds/migcom_untypd.tproj/Makefile.preamble \
	/build/source/src/bootstrap_cmds-1/migcom_untypd.tproj/Makefile.preamble
do
	[ -f "$preamble" ] || continue
	sed -e 's/^VERS_OFILE.*/VERS_OFILE =/' \
	    -e 's/^OTHER_OFILES =.*/OTHER_OFILES = migcom_untypd_vers_stub.o/' \
	    -e 's/^OTHER_GENERATED_OFILES =.*/OTHER_GENERATED_OFILES =/' \
	    -e 's/^# OTHER_GENERATED_OFILES =.*/OTHER_GENERATED_OFILES =/' \
	    -e 's/^OTHER_SOURCEFILES =.*/OTHER_SOURCEFILES = migcom_untypd_vers_stub.c/' \
	    -e 's/^OTHER_GARBAGE =.*/OTHER_GARBAGE =/' \
		"$preamble" > /tmp/migcom_preamble && mv /tmp/migcom_preamble "$preamble"
	dir=`dirname "$preamble"`
	if [ ! -f "$dir/migcom_untypd_vers_stub.c" ]; then
		cat > "$dir/migcom_untypd_vers_stub.c" << 'ENDSTUB'
char migcom_untypd_VERS_STRING[] =
    "@(#)PROGRAM:migcom_untypd  PROJECT:bootstrap_cmds-13.2\n";
ENDSTUB
	fi
	echo "patched $preamble"
	grep -n 'VERS_OFILE\|OTHER_OFILES\|OTHER_GENERATED\|OTHER_SOURCEFILES\|stub' "$preamble" | head -10
done

echo "=== 11e. Ensure cctools otool links with -lm (_finite) ==="
# Single-file pscp sync drops nested paths; patch guest tree in place.
for omf in \
	/build/source/src/cctools-2/otool/Makefile \
	/build/source/cctools-2/otool/Makefile
do
	[ -f "$omf" ] || continue
	if grep -q -- '-lm -lc_static' "$omf"; then
		echo "otool Makefile already has -lm: $omf"
		continue
	fi
	sed -e 's/$(LIBSTUFF) -lc_static/$(LIBSTUFF) -lm -lc_static/' \
		"$omf" > /tmp/otool_mf && mv /tmp/otool_mf "$omf"
	echo "patched -lm into $omf"
	grep -n 'lc_static\|-lm' "$omf" | head -5
done

echo "=== 11f. Seed /usr/local/lib/objs for Libsystem make_links ==="
# Libsystem expects SUBLIBROOTS=/usr/local/lib/objs/<Proj>/dynamic_obj/ppc.
# Prefer freshly built .cobj trees; fall back to Darwin *-obj debs.
mkdir -p /usr/local/lib/objs
seed_objs_from_cobj() {
	src="$1"
	[ -d "$src" ] || return 0
	(cd "$src" && tar cf - usr/local/lib/objs) | (cd / && tar xf -)
	echo "seeded objs from $src"
}
for cobj in /big/roots/libc-*.roots/*.cobj \
	/big/roots/objc4-*.roots/*.cobj \
	/big/roots/cctools-*.roots/*.cobj; do
	[ -d "$cobj/usr/local/lib/objs" ] || continue
	seed_objs_from_cobj "$cobj"
done
seed_objs_from_deb() {
	deb="$1"
	[ -f "$deb" ] || return 0
	rm -rf /tmp/obj-extract
	mkdir -p /tmp/obj-extract
	(
		cd /tmp/obj-extract
		ar x "$deb"
		if [ -f data.tar.gz ]; then gnutar xzf data.tar.gz
		elif [ -f data.tar ]; then gnutar xf data.tar
		else exit 0
		fi
		if [ -d usr/local/lib/objs ]; then
			(cd . && tar cf - usr/local/lib/objs) | (cd / && tar xf -)
			echo "seeded objs from `basename "$deb"`"
		fi
	)
}
for deb in /build/repo/libc-obj_*.deb \
	/build/repo/objc4-obj_*.deb \
	/build/repo/cctools-obj_*.deb \
	/build/repo/libcurses-obj_*.deb \
	/build/repo/libedit-obj_*.deb \
	/build/repo/libinfo-obj_*.deb \
	/build/repo/libkvm-obj_*.deb \
	/build/repo/libm-obj_*.deb \
	/build/repo/libstreams-obj_*.deb; do
	seed_objs_from_deb "$deb"
done
# Show what Libsystem will look for (ppc subdir OR flat dynamic_obj)
for p in Libc Libcurses Libedit Libinfo Libkvm Libm Libstreams objc4 \
	cctools/libmacho cctools/ld cctools/libdyld; do
	if [ -d /usr/local/lib/objs/$p/dynamic_obj/ppc ] || \
	   [ -d /usr/local/lib/objs/$p/dynamic_obj ]; then
		echo "OK $p/dynamic_obj"
	else
		echo "MISSING $p/dynamic_obj"
		ls -la /usr/local/lib/objs/$p 2>&1 | head -5
	fi
done

echo "=== 11g. Seed libkvm.a for system_cmds top (-lkvm) ==="
# libkvm_*.deb payload is empty; build a static archive from harvested objs.
if [ ! -f /usr/lib/libkvm.a ]; then
	objs=
	for d in /usr/local/lib/objs/Libkvm/dynamic_obj/ppc \
		/usr/local/lib/objs/Libkvm/dynamic_obj; do
		[ -d "$d" ] || continue
		for o in "$d"/kvm.o "$d"/kvm_*.o; do
			[ -f "$o" ] || continue
			objs="$objs $o"
		done
		[ -n "$objs" ] && break
	done
	if [ -n "$objs" ]; then
		rm -f /usr/lib/libkvm.a
		ar rc /usr/lib/libkvm.a $objs
		ranlib /usr/lib/libkvm.a 2>/dev/null || true
		mkdir -p /usr/local/lib
		cp -p /usr/lib/libkvm.a /usr/local/lib/libkvm.a
		echo "built libkvm.a from objs:$objs"
	else
		echo "WARNING: no Libkvm objs to archive"
	fi
fi
ls -l /usr/lib/libkvm.a 2>&1 | head || true

echo "=== 11h. Patch Libsystem make_links ofileList path ==="
# Upstream uses relative dynamic_obj/NAME.ofileList but links live under NAME/.
for mf in /build/source/src/Libsystem-2/Makefile.postamble; do
	[ -f "$mf" ] || continue
	if grep -q 'name}/\$${obj_dir}_obj/\$$name.ofileList' "$mf" 2>/dev/null; then
		echo "already patched $mf"
		continue
	fi
	# Fix: $${obj_dir}_obj/$$name.ofileList -> $$name/$${obj_dir}_obj/$$name.ofileList
	sed -e 's|$(LN) $${obj_dir}_obj/$$name.ofileList|$(LN) $$name/$${obj_dir}_obj/$$name.ofileList|' \
		"$mf" > /tmp/libsys_post && mv /tmp/libsys_post "$mf"
	echo "patched $mf"
	grep -n 'ofileList' "$mf" | head -5
done

echo "=== 11i. Seed mach_debug headers+defs for system_cmds zprint ==="
SYS_HDR=/System/Library/Frameworks/System.framework/Versions/B/Headers
SYS_PRIV=/System/Library/Frameworks/System.framework/PrivateHeaders
K_MD=/build/source/src/kernel-7/mach_debug
# Stock System.framework often leaves broken /tmp/rhapsody symlinks here.
# [ -e ] is false for dangling links, so mkdir -p still fails with File exists.
for d in "$SYS_HDR/mach_debug" "$SYS_PRIV/mach_debug" /usr/include/mach_debug; do
	if [ -L "$d" ]; then
		rm -f "$d"
	elif [ -e "$d" ] && [ ! -d "$d" ]; then
		rm -f "$d"
	fi
	mkdir -p "$d"
done
if [ ! -f "$K_MD/mach_debug.h" ]; then
	cat > "$K_MD/mach_debug.h" << 'ENDMDH'
#ifndef _MACH_DEBUG_MACH_DEBUG_H_
#define _MACH_DEBUG_MACH_DEBUG_H_
#include <mach_debug/mach_debug_types.h>
#endif
ENDMDH
fi
for h in mach_debug.h mach_debug_types.h zone_info.h ipc_info.h hash_info.h host_machine_info.h; do
	[ -f "$K_MD/$h" ] || continue
	cp -p "$K_MD/$h" "$SYS_HDR/mach_debug/$h"
	cp -p "$K_MD/$h" /usr/include/mach_debug/$h
done
# zprint MIG rule wants PrivateHeaders/mach_debug/mach_debug.defs;
# mig also #includes <mach_debug/mach_debug_types.defs>.
for d in mach_debug.defs mach_debug_types.defs; do
	[ -f "$K_MD/$d" ] || continue
	cp -p "$K_MD/$d" "$SYS_PRIV/mach_debug/$d"
	cp -p "$K_MD/$d" "$SYS_HDR/mach_debug/$d"
	cp -p "$K_MD/$d" /usr/include/mach_debug/$d
done
ls -l "$SYS_PRIV/mach_debug/mach_debug.defs" /usr/include/mach_debug/mach_debug.h /usr/include/mach_debug/zone_info.h

mkdir -p /usr/local/bin
for tool in indr nmedit strip lipo libtool nm size strings segedit; do
	found=`find /big/roots/cctools-*.roots -name "${tool}.NEW" -type f 2>/dev/null | head -1`
	if [ -n "$found" ]; then
		rm -f /usr/local/bin/$tool
		cp -p "$found" /usr/local/bin/$tool
		chmod 755 /usr/local/bin/$tool
		echo "$tool from $found"
	fi
done

echo "=== verify ==="
ls -l /build/bin/ln /build/bin/mv /bin/mv /bin/mv.real /usr/local/bin/decomment /usr/local/bin/makeinfo /usr/local/lib/libcompat.a
ls -l /build/source/src/cc-1/build_gcc /build/source/src/cc-1/cc/move-if-change 2>/dev/null || true
head -12 /build/source/src/cc-1/build_gcc | tail -4
echo HOST_FIXES_DONE
