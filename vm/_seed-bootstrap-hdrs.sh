#!/bin/sh
# Seed host System.framework headers + tools that stage-0 native builds expect
# but this guest image lacks. Native bootstrap installs into per-package DSTROOT
# packages, not into the live /, so later compiles still look here.
#
# SRC defaults to /build/src (RemoteRoot/src).

SRC="${1:-/build/src}"
SYSFW=/System/Library/Frameworks/System.framework
VERHDR="$SYSFW/Versions/B/Headers"
VERPRIV="$SYSFW/Versions/B/PrivateHeaders"
SYSTEM_DYLIB="$SYSFW/Versions/B/System"

die() { echo "seed-bootstrap-hdrs: $*" >&2; exit 1; }

[ -d "$SRC/Libstreams-1" ] || die "missing $SRC/Libstreams-1"
[ -f "$SRC/kernel-7/bsd/dev/evio.h" ] || die "missing kernel bsd/dev/evio.h"
[ -f "$SRC/kernel-7/bsd/dev/ppc/evio.h" ] || die "missing kernel ppc/evio.h"
[ -f "$SRC/objc4-1/runtime/maptable.h" ] || die "missing objc4 maptable.h"
[ -d "$VERHDR" ] || die "missing $VERHDR"
[ -f "$SYSTEM_DYLIB" ] || die "missing $SYSTEM_DYLIB"

echo "=== seed PrivateHeaders/streams ==="
mkdir -p "$VERPRIV/streams"
cp -p "$SRC/Libstreams-1/streams.h" \
      "$SRC/Libstreams-1/streamsextra.h" \
      "$SRC/Libstreams-1/streamsimpl.h" \
      "$SRC/Libstreams-1/defs.h" \
      "$VERPRIV/streams/"
# Framework-top PrivateHeaders symlink (cctools -I path)
if [ ! -e "$SYSFW/PrivateHeaders" ]; then
  ln -s Versions/Current/PrivateHeaders "$SYSFW/PrivateHeaders"
fi

echo "=== seed Headers/bsd/dev/{,ppc/}evio.h ==="
mkdir -p "$VERHDR/bsd/dev/ppc"
cp -p "$SRC/kernel-7/bsd/dev/evio.h" "$VERHDR/bsd/dev/evio.h"
cp -p "$SRC/kernel-7/bsd/dev/ppc/evio.h" "$VERHDR/bsd/dev/ppc/evio.h"

echo "=== seed Headers/objc/maptable.h ==="
mkdir -p "$VERHDR/objc"
cp -p "$SRC/objc4-1/runtime/maptable.h" "$VERHDR/objc/maptable.h"

echo "=== seed Headers/mach-o/rld.h (from cctools) ==="
mkdir -p "$VERHDR/mach-o"
if [ -f "$SRC/cctools-2/include/mach-o/rld.h" ]; then
  cp -p "$SRC/cctools-2/include/mach-o/rld.h" "$VERHDR/mach-o/rld.h"
fi

echo "=== seed PrivateHeaders/driverkit/Event.defs (Libc drivers) ==="
mkdir -p "$VERPRIV/driverkit"
if [ -f "$SRC/driverkit-3/libDriver/Kernel/Event.defs" ]; then
  cp -p "$SRC/driverkit-3/libDriver/Kernel/Event.defs" "$VERPRIV/driverkit/Event.defs"
fi

# kernel-hdrs apk has some members without leading ./System/... so
# mach_debug_types.defs can be missing after extract; seed from source.
echo "=== seed PrivateHeaders/mach_debug (zprint / system_cmds) ==="
mkdir -p "$VERPRIV/mach_debug"
if [ -d "$SRC/kernel-7/mach_debug" ]; then
  for f in "$SRC/kernel-7/mach_debug"/*; do
    [ -f "$f" ] || continue
    b=`basename "$f"`
    if [ ! -f "$VERPRIV/mach_debug/$b" ]; then
      cp -p "$f" "$VERPRIV/mach_debug/$b"
    fi
  done
fi

# Framework-top Headers / PrivateHeaders symlinks (cpp-precomp searches both)
if [ ! -e "$SYSFW/Headers" ]; then
  ln -s Versions/Current/Headers "$SYSFW/Headers"
fi
if [ ! -e "$SYSFW/PrivateHeaders" ]; then
  ln -s Versions/Current/PrivateHeaders "$SYSFW/PrivateHeaders"
fi

# Native bootstrap does not chroot/makeroot, so install packaged hdrs/libs into
# the live root. kernel-hdrs provides PrivateHeaders (mach/syscall_sw.h, kern/*,
# vm/*, bsd/dev/kmreg_com.h) that Libc/Libkvm/system_cmds need.
REPO="${REPO:-/build/repo}"
extract_apk() {
  apk="$1"
  if [ -f "$apk" ]; then
    echo "=== extract $(basename "$apk") into / ==="
    # Ignore ownership/mtime noise under ./private/dev etc.
    (cd / && gnutar xzf "$apk") || true
  else
    echo "=== skip missing $apk ==="
  fi
}
# Unquoted globs so the shell expands them (quoted patterns stay literal).
found=
for apk in "$REPO"/kernel-hdrs-*.apk; do
  [ -f "$apk" ] || continue
  extract_apk "$apk"
  found=1
  break
done
[ -n "$found" ] || echo "=== no kernel-hdrs-*.apk in $REPO ==="

# Csu apk's crt1.o is built without a usable dyld merge and MUST NOT replace
# the host /lib/crt1.o (that removes LC_LOAD_DYLINKER from all new links).
# Only seed static crt0 into /usr/local/lib.
found=
for apk in "$REPO"/csu-*.apk; do
  [ -f "$apk" ] || continue
  case "$apk" in *-hdrs-*) continue ;; esac
  echo "=== extract crt0* from $(basename "$apk") (not crt1) ==="
  rm -rf /tmp/_csu_seed && mkdir -p /tmp/_csu_seed
  (cd /tmp/_csu_seed && gnutar xzf "$apk" './usr/local/lib/crt0.o' \
      './usr/local/lib/gcrt0.o' './usr/local/lib/pscrt0.o' 2>/dev/null) || true
  mkdir -p /usr/local/lib
  for f in crt0.o gcrt0.o pscrt0.o; do
    if [ -f "/tmp/_csu_seed/usr/local/lib/$f" ]; then
      cp -p "/tmp/_csu_seed/usr/local/lib/$f" "/usr/local/lib/$f"
    fi
  done
  found=1
  break
done
[ -n "$found" ] || echo "=== no csu-*.apk in $REPO ==="
# If host crt1 was already clobbered, rebuild via dyld stub (see _fix-crt1.sh).
if [ -x /tmp/_fix-crt1.sh ]; then
  # Detect missing LC_LOAD_DYLINKER in newly linked programs
  echo 'int main(){return 0;}' > /tmp/_crt1_probe.c
  if cc -arch ppc -o /tmp/_crt1_probe /tmp/_crt1_probe.c 2>/dev/null; then
    if ! otool -l /tmp/_crt1_probe 2>/dev/null | grep -q LC_LOAD_DYLINKER; then
      echo "=== host crt1.o broken; repairing ==="
      /tmp/_fix-crt1.sh || die "crt1 repair failed"
    fi
  fi
  rm -f /tmp/_crt1_probe /tmp/_crt1_probe.c
fi

found=
for apk in "$REPO"/libcompat-*.apk; do
  [ -f "$apk" ] || continue
  case "$apk" in *-hdrs-*) continue ;; esac
  extract_apk "$apk"
  found=1
  break
done
[ -n "$found" ] || echo "=== no libcompat-*.apk in $REPO ==="

# Ensure PrivateHeaders symlink after extract (Current may have been created)
if [ ! -e "$SYSFW/PrivateHeaders" ]; then
  ln -s Versions/Current/PrivateHeaders "$SYSFW/PrivateHeaders"
fi

echo "=== seed /usr/lib/libc.dylib (+ libkvm) -> System.framework ==="
mkdir -p /usr/lib
if [ ! -e /usr/lib/libc.dylib ]; then
  ln -sf "$SYSTEM_DYLIB" /usr/lib/libc.dylib
fi
# system_cmds/top links -lkvm; kvm is already in System.framework.
if [ ! -e /usr/lib/libkvm.dylib ]; then
  ln -sf "$SYSTEM_DYLIB" /usr/lib/libkvm.dylib
fi
# Do NOT seed libc_dynamic.dylib: cctools dyld treats it as invalid MH_DYLINKER input.
# Remove a bad symlink from earlier bootstrap attempts.
if [ -L /usr/lib/libc_dynamic.dylib ]; then
  rm -f /usr/lib/libc_dynamic.dylib
fi

echo "=== seed /usr/local/bin/bison (cc expects this path) ==="
mkdir -p /usr/local/bin
if [ ! -x /usr/local/bin/bison ]; then
  if [ -x /usr/bin/bison ]; then
    ln -sf /usr/bin/bison /usr/local/bin/bison
  else
    die "no /usr/bin/bison to link"
  fi
fi

echo "=== seed /usr/local/bin/relpath (kernel installhdrs) ==="
if [ ! -x /usr/local/bin/relpath ]; then
  RELSRC=""
  for cand in \
      "$SRC/bootstrap_cmds-1/relpath.tproj/relpath.c" \
      "$SRC/Commands/bootstrap_cmds/relpath.tproj/relpath.c"
  do
    if [ -f "$cand" ]; then RELSRC="$cand"; break; fi
  done
  [ -n "$RELSRC" ] || die "relpath.c not found under $SRC"
  cc -O -arch ppc -o /usr/local/bin/relpath "$RELSRC" || die "relpath compile failed"
  chmod a+x /usr/local/bin/relpath
fi

echo "=== seed /usr/local/bin/indr from last cctools DSTROOT if needed ==="
if [ ! -x /usr/local/bin/indr ]; then
  for cand in /private/tmp/roots/cctools-*.roots/cctools-*.dst/usr/local/bin/indr; do
    if [ -x "$cand" ]; then
      cp -p "$cand" /usr/local/bin/indr
      chmod a+x /usr/local/bin/indr
      break
    fi
  done
fi

echo "=== seed bootstrap_cmds tools from DSTROOT if present ==="
if [ -x /tmp/_install-bootstrap-tools.sh ]; then
  /tmp/_install-bootstrap-tools.sh || true
else
  for cand in /private/tmp/roots/bootstrap-cmds-*.roots/bootstrap-cmds-*.dst/usr/local/bin/config; do
    if [ -x "$cand" ]; then
      mkdir -p /usr/local/bin
      d=`dirname "$cand"`
      for t in config relpath decomment; do
        [ -x "$d/$t" ] && cp -p "$d/$t" /usr/local/bin/$t && chmod a+x /usr/local/bin/$t
      done
      break
    fi
  done
fi

echo "=== verify ==="
ls -la "$SYSFW/PrivateHeaders/streams/streams.h" \
       "$VERHDR/bsd/dev/evio.h" \
       "$VERHDR/bsd/dev/ppc/evio.h" \
       "$VERHDR/objc/maptable.h" \
       "$VERHDR/mach-o/rld.h" \
       "$VERPRIV/driverkit/Event.defs" \
       /usr/lib/libc.dylib \
       /usr/local/bin/bison \
       /usr/local/bin/relpath
ls -la "$SYSFW/PrivateHeaders/mach/syscall_sw.h" \
       "$SYSFW/PrivateHeaders/kern/queue.h" \
       "$SYSFW/PrivateHeaders/bsd/dev/kmreg_com.h" \
       /usr/local/lib/crt0.o \
       /usr/local/lib/libcompat.a 2>/dev/null \
  || echo "(kernel-hdrs/csu/libcompat not fully present yet)"
ls -la /usr/local/bin/indr 2>/dev/null || echo "(indr not yet present - ok until cctools builds)"
echo "seed-bootstrap-hdrs: ok"
