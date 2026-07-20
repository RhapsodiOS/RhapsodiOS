#!/bin/sh
# Task 5: file:// install round-trip (mkapk + apk index + apk add --root).
# Runs on Darwin/RhapsodiOS once apk is built. On hosts without apk: exit 77 (skip).
set -e
if ! command -v dirname >/dev/null 2>&1; then
	dirname() { python -c "import os,sys; print(os.path.dirname(sys.argv[1]))" "$1"; }
fi
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
APK="${APK:-$ROOT/src/apk-tools/apk}"
# Directories can be -x; require a regular executable file
if [ ! -f "$APK" ] || [ ! -x "$APK" ]; then
	APK="${DSTROOT:-/tmp/rhapsody/dst}/sbin/apk"
fi
if [ ! -f "$APK" ] || [ ! -x "$APK" ]; then
	echo "SKIP: apk not found or not executable (set APK=/path/to/apk)" >&2
	exit 77
fi

WORK="$ROOT/ninja/tests/out/roundtrip"
rm -rf "$WORK"
mkdir -p "$WORK/repo" "$WORK/root" "$WORK/stage/usr/bin"
echo 'roundtrip' > "$WORK/stage/usr/bin/rt"
cat > "$WORK/PKGINFO" <<'EOF'
pkgname = roundtrip
pkgver = 1.0.0
pkgdesc = roundtrip fixture
url = http://rhapsody.local/rt
license = MIT
depend =
EOF
"$ROOT/ninja/mkapk.sh" "$WORK/PKGINFO" "$WORK/stage" "$WORK/repo/roundtrip-1.0.0.apk"

# pre11: apk index writes uncompressed index to stdout (no -o); repo file is APK_INDEX.gz
if command -v gzip >/dev/null 2>&1; then
	"$APK" index "$WORK/repo"/*.apk | gzip -n > "$WORK/repo/APK_INDEX.gz.tmp"
else
	"$APK" index "$WORK/repo"/*.apk > "$WORK/repo/APK_INDEX.tmp"
	python -c "import gzip,sys; gzip.open(sys.argv[2],'wb',mtime=0).write(open(sys.argv[1],'rb').read())" \
		"$WORK/repo/APK_INDEX.tmp" "$WORK/repo/APK_INDEX.gz.tmp"
	rm -f "$WORK/repo/APK_INDEX.tmp"
fi
mv "$WORK/repo/APK_INDEX.gz.tmp" "$WORK/repo/APK_INDEX.gz"

mkdir -p "$WORK/root/etc/apk"
echo "file://$WORK/repo" > "$WORK/root/etc/apk/repositories"

"$APK" --root "$WORK/root" add --initdb roundtrip
test -f "$WORK/root/usr/bin/rt"
grep -q roundtrip "$WORK/root/usr/bin/rt"
"$APK" --root "$WORK/root" info -e roundtrip
echo OK
