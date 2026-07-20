#!/bin/sh
#
# buildproj.sh - build a single RhapsodiOS project via its existing
# Apple/NeXT make framework, staging into a shared DSTROOT.
#
# Invoked by build.ninja edges (see ninja/rhap-build.c generate):
#   - stage sources into a per-project SRCROOT (make installsrc)
#   - run `make installhdrs` or `make install` with the RC_* build flags
#   - for `install`: stage into a private pkgroot, merge into DSTROOT, then
#     build an .apk into APKREPO when apk/PKGINFO exists
#
# Arguments (all positional, passed by ninja):
#   1  proj      project directory, relative to srcroot (e.g. Commands/adv_cmds)
#   2  target    installhdrs | install
#   3  arch      universal | i386 | ppc
#   4  srcbase   per-project source roots base   (SRCROOT = srcbase/proj)
#   5  objroot   per-project object roots base   (OBJROOT = objroot/proj)
#   6  symroot   per-project symbol roots base   (SYMROOT = symroot/proj)
#   7  dstroot   shared install/staging tree      (DSTROOT, shared)
#   8  toolroot  staged toolchain prefix (MAKEFILEPATH / PATH)
#   9  rc_archs  e.g. "ppc i386" (informational; per-arch flags set below)
#  10  rc_os     RC_OS value (e.g. teflon)
#  11  stamp     stamp file to touch on success
#
# Environment:
#   SRCROOT_TREE   original source tree (default: src)
#   APKREPO        directory for .apk outputs (default: <parent of dstroot>/apk)
#   SKIP_APK=1     skip .apk generation after install

set -e

if [ $# -lt 11 ]; then
	echo "buildproj.sh: wrong number of arguments" >&2
	exit 2
fi

proj="$1"; target="$2"; arch="$3"
srcbase="$4"; objbase="$5"; symbase="$6"; dstroot="$7"
toolroot="$8"; rc_archs="$9"; rc_os="${10}"; stamp="${11}"

: "${SRCROOT_TREE:=src}"
: "${MAKE:=make}"

here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
srctree="${SRCROOT_TREE}"

srcdir="$srctree/$proj"
SRCROOT="$srcbase/$proj"
OBJROOT="$objbase/$proj"
SYMROOT="$symbase/$proj"
DSTROOT="$dstroot"
PKGROOT="$objbase/$proj/pkgroot"

if [ -z "${APKREPO:-}" ]; then
	APKREPO=$(CDPATH= cd -- "$(dirname "$dstroot")" && pwd)/apk
fi

if [ ! -d "$srcdir" ]; then
	echo "buildproj.sh: source directory not found: $srcdir" >&2
	exit 1
fi

mkdir -p "$SRCROOT" "$OBJROOT" "$SYMROOT" "$DSTROOT"
mkdir -p "$(dirname "$stamp")"

# ---------------------------------------------------------------------------
# Build environment
# ---------------------------------------------------------------------------
UNAME_SYSNAME=Rhapsody
export UNAME_SYSNAME

PATH="$toolroot/usr/bin:$toolroot/bin:$toolroot/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin"
export PATH

MAKEFILEPATH="$toolroot/System/Developer/Makefiles"
export MAKEFILEPATH

CFLAGS_NEXT="-Dunix -D__unix -D__unix__ \
-DNX_COMPILER_RELEASE_3_0=300 -DNX_COMPILER_RELEASE_3_1=310 \
-DNX_COMPILER_RELEASE_3_2=320 -DNX_COMPILER_RELEASE_3_3=330 \
-DNX_CURRENT_COMPILER_RELEASE=520 \
-DNS_TARGET=52 -DNS_TARGET_MAJOR=5 -DNS_TARGET_MINOR=2 \
-DNeXT -D__NeXT -D__NeXT__ -D_NEXT_SOURCE"

case "$arch" in
	i386)
		RC_CFLAGS="-arch i386 $CFLAGS_NEXT"
		RC_ARCHS="i386"; RC_i386="YES"; RC_ppc="" ;;
	ppc)
		RC_CFLAGS="-arch ppc $CFLAGS_NEXT"
		RC_ARCHS="ppc"; RC_i386=""; RC_ppc="YES" ;;
	*)
		RC_CFLAGS="-arch i386 -arch ppc $CFLAGS_NEXT"
		RC_ARCHS="i386 ppc"; RC_i386="YES"; RC_ppc="YES" ;;
esac

set -- \
	"MAKEFILEPATH=$MAKEFILEPATH" \
	"SUBLIBROOTS=/usr/local/lib/objs" \
	"RC_JASPER=YES" \
	"RC_ARCHS=$RC_ARCHS" \
	"RC_CFLAGS=$RC_CFLAGS" \
	"RC_hppa=" "RC_i386=$RC_i386" "RC_m68k=" "RC_ppc=$RC_ppc" "RC_sparc=" \
	"RC_KANJI=" "JAPANESE=" \
	"RC_OS=$rc_os" \
	"CURRENT_PROJECT_VERSION=1" \
	"RC_RELEASE=Rhapsody" \
	"NEXT_ROOT=" \
	"GnuNoInstallSource=YES" \
	"Install_Source="

echo "==> $proj: $target ($arch)"

# ---------------------------------------------------------------------------
# 1) Stage the sources (make installsrc) once, guarded by a marker.
# ---------------------------------------------------------------------------
if [ ! -f "$SRCROOT/.installsrc-stamp" ]; then
	echo "    installsrc -> $SRCROOT"
	( cd "$srcdir" && $MAKE "$@" \
		"SRCROOT=$SRCROOT" "OBJROOT=$OBJROOT" "SYMROOT=$SYMROOT" \
		"DSTROOT=$DSTROOT" installsrc )
	: > "$SRCROOT/.installsrc-stamp"
fi

# ---------------------------------------------------------------------------
# 2) Build the requested target in the staged source root.
# ---------------------------------------------------------------------------
if [ "$target" = "install" ]; then
	# Private install root so we know exactly which files this package owns,
	# then merge into the shared DSTROOT and build an .apk.
	rm -rf "$PKGROOT"
	mkdir -p "$PKGROOT"
	echo "    install -> $PKGROOT (private), then merge to $DSTROOT"
	( cd "$SRCROOT" && $MAKE "$@" \
		"SRCROOT=$SRCROOT" "OBJROOT=$OBJROOT" "SYMROOT=$SYMROOT" \
		"DSTROOT=$PKGROOT" install )
	# Merge package files into the shared tree (deps already live there).
	( cd "$PKGROOT" && tar cf - . ) | ( cd "$DSTROOT" && tar xf - )

	pkginfo="$srcdir/apk/PKGINFO"
	if [ "${SKIP_APK:-0}" != "1" ] && [ -f "$pkginfo" ]; then
		name=$(sed -n 's/^pkgname = //p' "$pkginfo" | head -1 | tr -d '\r')
		ver=$(sed -n 's/^pkgver = //p' "$pkginfo" | head -1 | tr -d '\r')
		if [ -n "$name" ] && [ -n "$ver" ]; then
			mkdir -p "$APKREPO"
			out="$APKREPO/${name}-${ver}.apk"
			RHAP="${RHAP_BUILD:-$here/rhap-build}"
			if [ ! -x "$RHAP" ]; then
				echo "    warning: rhap-build not found at $RHAP; skipping apk" >&2
			else
				echo "    mkapk -> $out"
				"$RHAP" mkapk "$pkginfo" "$PKGROOT" "$out"
			fi
		else
			echo "    warning: $pkginfo missing pkgname/pkgver; skipping apk" >&2
		fi
	fi
else
	( cd "$SRCROOT" && $MAKE "$@" \
		"SRCROOT=$SRCROOT" "OBJROOT=$OBJROOT" "SYMROOT=$SYMROOT" \
		"DSTROOT=$DSTROOT" "$target" )
fi

# ---------------------------------------------------------------------------
# 3) Mark success.
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$stamp")"
: > "$stamp"
echo "==> $proj: $target done"
