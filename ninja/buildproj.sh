#!/bin/sh
#
# buildproj.sh - build a single RhapsodiOS project via its existing
# Apple/NeXT make framework, staging into a shared DSTROOT.
#
# Invoked by build.ninja edges (see ninja/genninja.c). This replaces the
# per-project work that Dpkg::Package::Builder::build used to do
# (buildtools-2/lib/Builder.pm), minus the chroot and .deb packaging:
#   - stage sources into a per-project SRCROOT (make installsrc)
#   - run `make installhdrs` or `make install` with the RC_* build flags
#   - install everything into one shared DSTROOT
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

set -e

if [ $# -lt 11 ]; then
	echo "buildproj.sh: wrong number of arguments" >&2
	exit 2
fi

proj="$1"; target="$2"; arch="$3"
srcbase="$4"; objbase="$5"; symbase="$6"; dstroot="$7"
toolroot="$8"; rc_archs="$9"; rc_os="${10}"; stamp="${11}"

: "${SRCROOT_TREE:=.}"   # where the original source tree lives (repo root)
: "${MAKE:=make}"

# The repo root: ninja passes proj relative to $srcroot, which ninja knows as
# its own working directory. We derive the source tree from SRCROOT_TREE (set
# by the caller/ninja file) or default to the current directory.
srctree="${SRCROOT_TREE}"

srcdir="$srctree/$proj"        # original sources
SRCROOT="$srcbase/$proj"       # staged sources (build happens here)
OBJROOT="$objbase/$proj"
SYMROOT="$symbase/$proj"
DSTROOT="$dstroot"             # shared

if [ ! -d "$srcdir" ]; then
	echo "buildproj.sh: source directory not found: $srcdir" >&2
	exit 1
fi

mkdir -p "$SRCROOT" "$OBJROOT" "$SYMROOT" "$DSTROOT"
mkdir -p "$(dirname "$stamp")"

# ---------------------------------------------------------------------------
# Build environment (ported from Builder.pm build()).
# ---------------------------------------------------------------------------
UNAME_SYSNAME=Rhapsody
export UNAME_SYSNAME

# Prefer the freshly-staged toolchain, then fall back to the host base tools.
PATH="$toolroot/usr/bin:$toolroot/bin:$toolroot/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin"
export PATH

# The Apple make framework locates its makefiles via MAKEFILEPATH.
# CoreOSMakefiles installs into $DSTROOT/System/Developer/Makefiles/CoreOS
# (see CoreOSMakefiles-1/Makefile); pb_makefiles/project_makefiles install
# alongside. Point MAKEFILEPATH at the staged toolchain.
MAKEFILEPATH="$toolroot/System/Developer/Makefiles"
export MAKEFILEPATH

# ---------------------------------------------------------------------------
# RC_* compiler flags (ported from @cflags / buildflags() in Builder.pm).
# ---------------------------------------------------------------------------
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

# The full set of make variables Builder.pm passed on every invocation.
# Kept as positional parameters ("$@") so that values containing spaces
# (notably RC_CFLAGS) survive as single arguments to make. A subshell
# ( ... ) inherits these positional parameters.
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
( cd "$SRCROOT" && $MAKE "$@" \
	"SRCROOT=$SRCROOT" "OBJROOT=$OBJROOT" "SYMROOT=$SYMROOT" \
	"DSTROOT=$DSTROOT" "$target" )

# ---------------------------------------------------------------------------
# 3) Mark success.
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$stamp")"
: > "$stamp"
echo "==> $proj: $target done"
