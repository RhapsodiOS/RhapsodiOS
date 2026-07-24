#!/bin/sh
# Host-side fixes for stage-0 bootstrap on PPC Rhapsody.
set -e
export PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/build/tools/usr/local/bin

echo "=== 1. /build/bin/ln (HFS hardlink -> cp fallback) ==="
mkdir -p /build/bin
cat > /build/bin/ln << 'ENDLN'
#!/bin/sh
# HFS-safe ln: on hard-link failure, fall back to cp -p for the common cases.
for a in "$@"; do
	case "$a" in
	-s|-sf|-fs) exec /bin/ln "$@" ;;
	esac
done
if /bin/ln "$@" 2>/dev/null; then
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
	[ "$force" = 1 ] && rm -f "$dst"
	exec cp -p "$src" "$dst"
fi
if [ $# -ge 2 ]; then
	n=$#
	eval "dest=\$$n"
	i=1
	while [ $i -lt $n ]; do
		eval "src=\$$i"
		base=`basename "$src"`
		[ "$force" = 1 ] && rm -f "$dest/$base"
		cp -p "$src" "$dest/$base" || exit 1
		i=`expr $i + 1`
	done
	exit 0
fi
echo "ln: fallback failed" >&2
exit 1
ENDLN
chmod 755 /build/bin/ln
rm -f /big/hl_src /big/hl_dst
echo hi > /big/hl_src
/build/bin/ln -f /big/hl_src /big/hl_dst
cmp /big/hl_src /big/hl_dst
rm -f /big/hl_src /big/hl_dst
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

echo "=== 12. Prefer prior cctools *.NEW tools if present ==="
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
