#!/bin/sh
# Task 11: file conflict (same path) and corrupt/tampered .apk rejection.
# Runs on Darwin/RhapsodiOS once apk is built. On hosts without apk: exit 77 (skip).
set -e
if ! command -v dirname >/dev/null 2>&1; then
	dirname() { python -c "import os,sys; print(os.path.dirname(sys.argv[1]))" "$1"; }
fi
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
APK="${APK:-$ROOT/src/apk-tools/apk}"
if [ ! -f "$APK" ] || [ ! -x "$APK" ]; then
	APK="${DSTROOT:-/tmp/rhapsody/dst}/sbin/apk"
fi
if [ ! -f "$APK" ] || [ ! -x "$APK" ]; then
	echo "SKIP: apk not found or not executable (set APK=/path/to/apk)" >&2
	exit 77
fi

RHAP="${RHAP_BUILD:-$ROOT/ninja/rhap-build}"
if [ ! -x "$RHAP" ]; then
	echo "SKIP: rhap-build not built" >&2
	exit 77
fi

if command -v python3 >/dev/null 2>&1; then
	PYTHON=python3
elif command -v python >/dev/null 2>&1; then
	PYTHON=python
else
	PYTHON=
fi

WORK="$ROOT/ninja/tests/out/conflict"
rm -rf "$WORK"
mkdir -p "$WORK/repo" "$WORK/root" \
	"$WORK/a/stage/usr/bin" "$WORK/b/stage/usr/bin" "$WORK/good/stage/usr/bin"

echo 'from-a' > "$WORK/a/stage/usr/bin/clash"
echo 'from-b' > "$WORK/b/stage/usr/bin/clash"
echo 'goodpkg' > "$WORK/good/stage/usr/bin/good"

cat > "$WORK/a/PKGINFO" <<'EOF'
pkgname = conflict-a
pkgver = 1.0.0
pkgdesc = conflict package A
url = http://rhapsody.local/conflict-a
license = MIT
depend =
EOF
cat > "$WORK/b/PKGINFO" <<'EOF'
pkgname = conflict-b
pkgver = 1.0.0
pkgdesc = conflict package B
url = http://rhapsody.local/conflict-b
license = MIT
depend =
EOF
cat > "$WORK/good/PKGINFO" <<'EOF'
pkgname = goodpkg
pkgver = 1.0.0
pkgdesc = integrity victim
url = http://rhapsody.local/goodpkg
license = MIT
depend =
EOF

"$RHAP" mkapk "$WORK/a/PKGINFO" "$WORK/a/stage" "$WORK/repo/conflict-a-1.0.0.apk"
"$RHAP" mkapk "$WORK/b/PKGINFO" "$WORK/b/stage" "$WORK/repo/conflict-b-1.0.0.apk"
"$RHAP" mkapk "$WORK/good/PKGINFO" "$WORK/good/stage" "$WORK/repo/goodpkg-1.0.0.apk"

if command -v gzip >/dev/null 2>&1; then
	"$APK" index "$WORK/repo"/*.apk | gzip -n > "$WORK/repo/APK_INDEX.gz.tmp"
else
	"$APK" index "$WORK/repo"/*.apk > "$WORK/repo/APK_INDEX.tmp"
	$PYTHON -c "import gzip,sys; gzip.open(sys.argv[2],'wb',mtime=0).write(open(sys.argv[1],'rb').read())" \
		"$WORK/repo/APK_INDEX.tmp" "$WORK/repo/APK_INDEX.gz.tmp"
	rm -f "$WORK/repo/APK_INDEX.tmp"
fi
mv "$WORK/repo/APK_INDEX.gz.tmp" "$WORK/repo/APK_INDEX.gz"

mkdir -p "$WORK/root/etc/apk"
echo "file://$WORK/repo" > "$WORK/root/etc/apk/repositories"

"$APK" --root "$WORK/root" add --initdb conflict-a
test -f "$WORK/root/usr/bin/clash"
grep -q from-a "$WORK/root/usr/bin/clash"

if "$APK" --root "$WORK/root" add conflict-b; then
	echo "FAIL: expected file conflict to abort" >&2
	exit 1
fi
grep -q from-a "$WORK/root/usr/bin/clash"

# Tamper a byte in goodpkg after indexing; add must reject (checksum / integrity)
if [ -n "$PYTHON" ]; then
	$PYTHON -c "
import sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
# Flip a payload byte past the gzip header so the archive is still openable
# but the package checksum no longer matches the index.
i = min(64, len(d) - 1)
if i < 0:
    sys.exit('empty apk')
d[i] ^= 0xFF
open(p, 'wb').write(d)
" "$WORK/repo/goodpkg-1.0.0.apk"
else
	# dd fallback: overwrite one byte at offset 64
	printf '\xff' | dd of="$WORK/repo/goodpkg-1.0.0.apk" bs=1 seek=64 conv=notrunc 2>/dev/null
fi

if "$APK" --root "$WORK/root" add goodpkg; then
	echo "FAIL: expected tampered package to be rejected" >&2
	exit 1
fi
if [ -e "$WORK/root/usr/bin/good" ]; then
	echo "FAIL: tampered package left installed files" >&2
	exit 1
fi

echo OK
