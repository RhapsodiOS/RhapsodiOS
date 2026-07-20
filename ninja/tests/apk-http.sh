#!/bin/sh
# Task 10: HTTP repo delivery (same tree as file:// via python http.server).
# Runs on Darwin/RhapsodiOS once apk is built. On hosts without apk: exit 77 (skip).
# Pre11 fetch uses wget for http:// URLs.
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

if command -v python3 >/dev/null 2>&1; then
	PYTHON=python3
elif command -v python >/dev/null 2>&1; then
	PYTHON=python
else
	echo "FAIL: python3/python required for HTTP test" >&2
	exit 1
fi

WORK="$ROOT/ninja/tests/out/http"
rm -rf "$WORK"
mkdir -p "$WORK/repo" "$WORK/root/etc/apk" "$WORK/stage/usr/bin"
echo 'roundtrip' > "$WORK/stage/usr/bin/rt"
cat > "$WORK/PKGINFO" <<'EOF'
pkgname = roundtrip
pkgver = 1.0.0
pkgdesc = http fixture
url = http://rhapsody.local/rt
license = MIT
depend =
EOF
"$ROOT/ninja/mkapk.sh" "$WORK/PKGINFO" "$WORK/stage" "$WORK/repo/roundtrip-1.0.0.apk"

if command -v gzip >/dev/null 2>&1; then
	"$APK" index "$WORK/repo"/*.apk | gzip -n > "$WORK/repo/APK_INDEX.gz.tmp"
else
	"$APK" index "$WORK/repo"/*.apk > "$WORK/repo/APK_INDEX.tmp"
	$PYTHON -c "import gzip,sys; gzip.open(sys.argv[2],'wb',mtime=0).write(open(sys.argv[1],'rb').read())" \
		"$WORK/repo/APK_INDEX.tmp" "$WORK/repo/APK_INDEX.gz.tmp"
	rm -f "$WORK/repo/APK_INDEX.tmp"
fi
mv "$WORK/repo/APK_INDEX.gz.tmp" "$WORK/repo/APK_INDEX.gz"

PORT=$($PYTHON -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
(
	cd "$WORK/repo"
	exec $PYTHON -m http.server "$PORT" 2>/dev/null || exec $PYTHON -m SimpleHTTPServer "$PORT"
) &
PID=$!
trap 'kill $PID 2>/dev/null; wait $PID 2>/dev/null; true' EXIT

i=0
while [ "$i" -lt 50 ]; do
	if $PYTHON -c "import socket; s=socket.socket(); s.settimeout(0.2); s.connect(('127.0.0.1',int('$PORT'))); s.close()" 2>/dev/null; then
		break
	fi
	i=$((i + 1))
	sleep 0.1 2>/dev/null || sleep 1
done

echo "http://127.0.0.1:${PORT}/" > "$WORK/root/etc/apk/repositories"

# init empty DB, then update (fetch APK_INDEX.gz) and add
"$APK" --root "$WORK/root" add --initdb
"$APK" --root "$WORK/root" update
"$APK" --root "$WORK/root" add roundtrip
test -f "$WORK/root/usr/bin/rt"
grep -q roundtrip "$WORK/root/usr/bin/rt"

echo OK
