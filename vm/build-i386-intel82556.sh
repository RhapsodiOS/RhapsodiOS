#!/bin/sh
# Native i386 verification in an isolated guest source/output tree.
# Sync the driver to $ROOT/source first; do not run against /build/src.
set -eu
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
ROOT=${INTEL82556_BUILD_ROOT:-/build/codex-drvintel82556}
SRC=$ROOT/source
DST=$ROOT/dst-$$
FW=${INTEL82556_FRAMEWORK:-/build/bootstrap-root/System/Library/Frameworks/System.framework/Versions/B}
case "$ROOT" in /build/codex-drvintel82556|/build/codex-drvintel82556-*) ;; *) echo "Refusing non-isolated build root: $ROOT" >&2; exit 1;; esac
mkdir -p "$ROOT/products" "$ROOT/obj" "$DST"
cc -v
sysctl hw.pagesize
cd "$SRC"
# Native DriverKit kernel headers live in the bootstrap framework on this image.
includes="-I$FW/PrivateHeaders -I$FW/PrivateHeaders/ansi -I$FW/PrivateHeaders/bsd -I$FW/Headers"
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 \
    MAKEFILEPATH=/System/Developer/Makefiles \
    OBJROOT="$ROOT/obj" SYMROOT="$ROOT/products" DSTROOT="$DST" \
    "OTHER_CFLAGS=$includes" all
reloc="$ROOT/products/Intel82556NetworkDriver.config/Intel82556NetworkDriver_reloc"
test -s "$reloc"
file "$reloc"
cksum "$reloc"
echo "RELOC_PATH=$reloc"
cd "$SRC/reconstruction/tests"
CFLAGS="-Wall -Werror -traditional-cpp"
CPPFLAGS="$includes"
export CFLAGS CPPFLAGS
sh ./verify.sh
sh ./verify-core.sh
sh ./verify-adapters.sh

# The guest's original driver.make expects a userspace inspector executable;
# this source-only bundle intentionally contains only the kernel module.
cd "$SRC"
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 \
    MAKEFILEPATH=/System/Developer/Makefiles \
    OBJROOT="$ROOT/obj" SYMROOT="$ROOT/products" DSTROOT="$DST" \
    "OTHER_CFLAGS=$includes" STRIPPED_PRODUCTS= install
installed="$DST/private/Drivers/i386/Intel82556NetworkDriver.config"
test -s "$installed/Intel82556NetworkDriver_reloc"
(cd "$DST" && pax -w -x ustar private) > "$ROOT/Intel82556NetworkDriver-install.tar"
gzip -c "$ROOT/Intel82556NetworkDriver-install.tar" > "$ROOT/Intel82556NetworkDriver-install.tar.gz"
echo "INSTALL_ARCHIVE=$ROOT/Intel82556NetworkDriver-install.tar.gz"
