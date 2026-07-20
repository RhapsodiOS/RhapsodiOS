#!/bin/sh
# Mass-migrate */dpkg/control → */apk/PKGINFO, then remove dpkg/control.
# Prefer the Python migrator on Windows; this wrapper calls it when available.
# Usage: ninja/migrate-dpkg-to-apk.sh [srcroot]
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SRCROOT="${1:-$ROOT/src}"
if command -v python3 >/dev/null 2>&1; then
	exec python3 "$ROOT/ninja/migrate-dpkg-to-apk.py" "$SRCROOT"
elif command -v python >/dev/null 2>&1; then
	exec python "$ROOT/ninja/migrate-dpkg-to-apk.py" "$SRCROOT"
fi
CONV="$ROOT/ninja/dpkg-control-to-pkginfo.sh"
converted=0
skipped=0
failed=0

for ctl in $(find "$SRCROOT" -type f -path '*/dpkg/control' 2>/dev/null); do
	proj=$(dirname "$(dirname "$ctl")")
	apkdir="$proj/apk"
	pkginfo="$apkdir/PKGINFO"
	if [ -f "$pkginfo" ]; then
		echo "skip (PKGINFO exists): $proj"
		skipped=$((skipped + 1))
		rm -f "$ctl"
		rmdir "$(dirname "$ctl")" 2>/dev/null || true
		continue
	fi
	mkdir -p "$apkdir"
	if ! "$CONV" "$ctl" > "$pkginfo"; then
		echo "FAIL: $ctl" >&2
		rm -f "$pkginfo"
		failed=$((failed + 1))
		continue
	fi
	if ! grep -q '^pkgname = ' "$pkginfo"; then
		echo "FAIL (empty pkgname): $ctl" >&2
		rm -f "$pkginfo"
		failed=$((failed + 1))
		continue
	fi
	rm -f "$ctl"
	rmdir "$(dirname "$ctl")" 2>/dev/null || true
	echo "ok: $proj"
	converted=$((converted + 1))
done

echo "---"
echo "converted=$converted skipped=$skipped failed=$failed"
left=$(find "$SRCROOT" -type f -path '*/dpkg/control' 2>/dev/null | wc -l | tr -d ' ')
echo "remaining_dpkg_control=$left"
if [ "$failed" -ne 0 ] || [ "$left" -ne 0 ]; then
	exit 1
fi
