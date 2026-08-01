#!/bin/sh
# Stage-1 dependency chain toward kernel-7 (chroot buildpackage).
# Log: /tmp/stage1-kernel.log  Pid: /tmp/stage1-kernel.pid
set -e
export PATH=/build/bin:/usr/bin:/bin:/usr/local/bin:/sbin:/usr/sbin

SRC="${1:-/build/src}"
REPO="${2:-/build/repo}"
# Keep dstdir == seeddir so new apks are visible to later makeroots.
BUILT="${3:-/build/repo}"
LOG=/tmp/stage1-kernel.log

mkdir -p "$REPO" "$BUILT"
# Do not wipe stage1-kernel.pid — starter owns it.
# Preserve log across restarts by rotating once.
if [ -f "$LOG" ]; then
  mv "$LOG" "$LOG.prev" 2>/dev/null || rm -f "$LOG"
fi

build_one() {
  pkg="$1"
  target="${2:-all}"
  echo "======== BUILD $pkg target=$target ========" >> "$LOG"
  date >> "$LOG"
  if [ "$target" = "all" ]; then
    rbuild buildpackage --dir "$pkg" "$REPO" "$BUILT" >> "$LOG" 2>&1
  else
    rbuild buildpackage --dir --target "$target" "$pkg" "$REPO" "$BUILT" >> "$LOG" 2>&1
  fi
  ec=$?
  echo "EXIT:$pkg:$target:$ec" >> "$LOG"
  if [ "$ec" -ne 0 ]; then
    echo "FAILED $pkg ($target) exit=$ec" >> "$LOG"
    return $ec
  fi
  echo "OK $pkg ($target)" >> "$LOG"
  return 0
}

# Seed empty self-hdrs stubs so first headers builds can resolve Build-Depends.
seed_stub() {
  name="$1"
  ver="$2"
  out="$REPO/${name}-${ver}.apk"
  if ls "$REPO"/${name}-*.apk >/dev/null 2>&1; then
    echo "stub skip (exists): $name" >> "$LOG"
    return 0
  fi
  stub=/tmp/stub-$$
  rm -rf "$stub"
  mkdir -p "$stub"
  # Minimal .PKGINFO; apk_extract uses gnutar xzf
  printf 'pkgname = %s\npkgver = %s\narch = ppc\n' "$name" "$ver" > "$stub/.PKGINFO"
  ( cd "$stub" && gnutar czf "$out" .PKGINFO )
  rm -rf "$stub"
  echo "stub seeded: $out" >> "$LOG"
}

{
  echo "stage1 start $(date)"
  echo "SRC=$SRC REPO=$REPO BUILT=$BUILT"

  if [ -x /tmp/_install-ln.sh ]; then /tmp/_install-ln.sh || true; fi
  if [ -x /tmp/_fix-crt1.sh ]; then /tmp/_fix-crt1.sh || true; fi

  cd "$SRC" || exit 1

  # Windows tar|ssh drops +x; perl and friends need Configure executable.
  find "$SRC" -type f \( -name Configure -o -name configure \) -exec chmod a+x {} \; 2>/dev/null || true

  # Promote apks from a prior /build/built dstdir into the seed repo.
  if [ -d /build/built ]; then
    for f in /build/built/*.apk; do
      [ -f "$f" ] || continue
      base=`basename "$f"`
      if [ ! -f "$REPO/$base" ]; then
        cp -p "$f" "$REPO/$base"
        echo "promoted $base -> $REPO"
      fi
    done
  fi

  # Order derived from Build-Depends of kernel + its transitive deps.
  build_one machkit-1 headers || exit 1
  build_one machkit-1 all || exit 1

  build_one yacc-1 all || exit 1
  build_one perl-1 all || exit 1
  build_one flex-1 all || exit 1
  build_one Commands/adv_cmds all || exit 1

  seed_stub driverkit-hdrs 0-stub
  build_one driverkit-3 headers || exit 1
  rm -f "$REPO"/driverkit-hdrs-0-stub.apk
  # Real hdrs apk replaces stub once produced; rebuild binary
  build_one driverkit-3 all || exit 1

  build_one driverTools-1 all || exit 1

  seed_stub kernload-hdrs 0-stub
  build_one kernload-1 headers || exit 1
  rm -f "$REPO"/kernload-hdrs-0-stub.apk
  build_one kernload-1 all || exit 1

  build_one drivers-ppc/bus/drvPExpert all || exit 1

  build_one objc-1 all || exit 1
  build_one gnudiff-1 all || exit 1

  build_one kernel-7 all || exit 1

  echo "stage1 COMPLETE $(date)"
} >> "$LOG" 2>&1

echo EXIT:$? >> "$LOG"
