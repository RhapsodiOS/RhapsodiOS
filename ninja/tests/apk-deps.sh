#!/bin/sh
# Task 9: A→B→C dependency resolution and unmet-dep abort.
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

FIX="$ROOT/ninja/tests/fixtures/deps"
WORK="$ROOT/ninja/tests/out/deps"
rm -rf "$WORK"
mkdir -p "$WORK/repo" "$WORK/root"

# Ensure fixture payload files exist (idempotent for clean checkouts)
mkdir -p "$FIX/depa/root/usr/share/deps" "$FIX/depb/root/usr/share/deps" "$FIX/depc/root/usr/share/deps"
echo depa > "$FIX/depa/root/usr/share/deps/a"
echo depb > "$FIX/depb/root/usr/share/deps/b"
echo depc > "$FIX/depc/root/usr/share/deps/c"

"$RHAP" mkapk "$FIX/depc/PKGINFO" "$FIX/depc/root" "$WORK/repo/depc-1.0.0.apk"
"$RHAP" mkapk "$FIX/depb/PKGINFO" "$FIX/depb/root" "$WORK/repo/depb-1.0.0.apk"
"$RHAP" mkapk "$FIX/depa/PKGINFO" "$FIX/depa/root" "$WORK/repo/depa-1.0.0.apk"

# unmet-dep package (built into same repo, not indexed until after happy path — keep in repo)
mkdir -p "$WORK/nosuch/stage/usr/share/deps"
echo nosuch > "$WORK/nosuch/stage/usr/share/deps/bad"
cat > "$WORK/nosuch/PKGINFO" <<'EOF'
pkgname = neednosuch
pkgver = 1.0.0
pkgdesc = depends on missing package
url = http://rhapsody.local/neednosuch
license = MIT
depend = nosuch
EOF
"$RHAP" mkapk "$WORK/nosuch/PKGINFO" "$WORK/nosuch/stage" "$WORK/repo/neednosuch-1.0.0.apk"

# pre11: index → stdout; APK_INDEX.gz (includes neednosuch)
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

"$APK" --root "$WORK/root" add --initdb depa
test -f "$WORK/root/usr/share/deps/a"
test -f "$WORK/root/usr/share/deps/b"
test -f "$WORK/root/usr/share/deps/c"
grep -q depa "$WORK/root/usr/share/deps/a"
grep -q depb "$WORK/root/usr/share/deps/b"
grep -q depc "$WORK/root/usr/share/deps/c"

# unmet dependency must fail with no partial install of neednosuch
if "$APK" --root "$WORK/root" add neednosuch; then
	echo "FAIL: expected unmet dependency to abort" >&2
	exit 1
fi
if [ -e "$WORK/root/usr/share/deps/bad" ]; then
	echo "FAIL: partial install of neednosuch" >&2
	exit 1
fi

echo OK
