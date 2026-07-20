#!/bin/sh
# Usage: mkapk.sh <PKGINFO> <staging-root> <out.apk>
set -e
PKGINFO=$1
ROOT=$2
OUT=$3
if [ ! -f "$PKGINFO" ] || [ ! -d "$ROOT" ] || [ -z "$OUT" ]; then
	echo "usage: $0 <PKGINFO> <staging-root> <out.apk>" >&2
	exit 2
fi
if command -v mktemp >/dev/null 2>&1; then
	TMP=$(mktemp -d)
else
	TMP="${TMPDIR:-/tmp}/mkapk.$$"
	mkdir -p "$TMP"
fi
trap 'rm -rf "$TMP"' EXIT
cp "$PKGINFO" "$TMP/.PKGINFO"
( cd "$ROOT" && tar cf - . ) | ( cd "$TMP" && tar xf - )
(
	cd "$TMP"
	OTHERS=
	for f in $(ls -A); do
		case "$f" in
		.PKGINFO) ;;
		*) OTHERS="$OTHERS $f" ;;
		esac
	done
	if command -v gzip >/dev/null 2>&1; then
		tar cf - .PKGINFO $OTHERS | gzip -n > "$OUT"
	else
		# Windows bsdtar / environments without standalone gzip
		tar czf "$OUT" .PKGINFO $OTHERS
	fi
)
