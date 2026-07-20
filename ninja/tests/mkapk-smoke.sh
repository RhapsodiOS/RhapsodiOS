#!/bin/sh
set -e
# Portable helpers for limited environments (e.g. Windows BuildTools msys)
if ! command -v dirname >/dev/null 2>&1; then
	dirname() { python -c "import os,sys; print(os.path.dirname(sys.argv[1]))" "$1"; }
fi
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
FIX="$ROOT/ninja/tests/fixtures/mkapk-smoke"
OUT="$ROOT/ninja/tests/out"
rm -rf "$OUT"
mkdir -p "$FIX/root/usr/bin" "$OUT"
echo 'hello' > "$FIX/root/usr/bin/hello"
cat > "$FIX/PKGINFO" <<'EOF'
pkgname = hello
pkgver = 1.0.0
pkgdesc = smoke test package
url = http://rhapsody.local/hello
license = MIT
depend =
EOF
"$ROOT/ninja/mkapk.sh" "$FIX/PKGINFO" "$FIX/root" "$OUT/hello-1.0.0.apk"
# Must be gzip
if command -v od >/dev/null 2>&1; then
	dd if="$OUT/hello-1.0.0.apk" bs=2 count=1 2>/dev/null | od -An -tx1 | grep -q '1f 8b' || \
	  dd if="$OUT/hello-1.0.0.apk" bs=2 count=1 2>/dev/null | od -An -tx1 | grep -qi '1f8b'
elif command -v xxd >/dev/null 2>&1; then
	xxd -l 2 "$OUT/hello-1.0.0.apk" | grep -qi '1f 8b'
else
	python -c "import sys; d=open(sys.argv[1],'rb').read(2); sys.exit(0 if d==b'\x1f\x8b' else 1)" "$OUT/hello-1.0.0.apk"
fi
# Must contain .PKGINFO as first-class member
if command -v gzip >/dev/null 2>&1 && command -v grep >/dev/null 2>&1; then
	gzip -dc "$OUT/hello-1.0.0.apk" | tar tf - | grep -q '^\.PKGINFO$'
elif command -v grep >/dev/null 2>&1; then
	tar tzf "$OUT/hello-1.0.0.apk" | grep -q '^\.PKGINFO$'
else
	python -c "import sys,subprocess; out=subprocess.check_output(['tar','tzf',sys.argv[1]],text=True); sys.exit(0 if any(l.strip()=='.PKGINFO' for l in out.splitlines()) else 1)" "$OUT/hello-1.0.0.apk"
fi
echo OK
