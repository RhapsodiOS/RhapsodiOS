#!/bin/sh
# Rebuild APK_INDEX.gz for a directory of .apk files (apk-tools 2.0_pre11).
# Usage: index-apk-repo.sh <repo-dir>
set -e
REPO=${1:?usage: index-apk-repo.sh <repo-dir>}
APK="${APK:-apk}"

if [ ! -d "$REPO" ]; then
	echo "index-apk-repo.sh: not a directory: $REPO" >&2
	exit 1
fi

# No packages yet (e.g. empty world) — nothing to index.
set -- "$REPO"/*.apk
if [ ! -f "$1" ]; then
	echo "index-apk-repo.sh: no .apk files in $REPO (skip)"
	exit 0
fi

INDEX_NEW="$REPO/APK_INDEX.gz.new"
INDEX="$REPO/APK_INDEX.gz"

if ! command -v "$APK" >/dev/null 2>&1 && [ ! -x "$APK" ]; then
	# Prefer apk just built into DSTROOT if TOOLROOT/DSTROOT set
	if [ -n "${DSTROOT:-}" ] && [ -x "$DSTROOT/sbin/apk" ]; then
		APK="$DSTROOT/sbin/apk"
	elif [ -n "${TOOLROOT:-}" ] && [ -x "$TOOLROOT/sbin/apk" ]; then
		APK="$TOOLROOT/sbin/apk"
	fi
fi

if ! command -v "$APK" >/dev/null 2>&1 && [ ! -x "$APK" ]; then
	echo "index-apk-repo.sh: apk not found; wrote packages but no index" >&2
	echo "  set APK=/path/to/apk and re-run: $0 $REPO" >&2
	exit 0
fi

echo "index-apk-repo.sh: indexing $* -> $INDEX"
"$APK" index "$@" | gzip -n > "$INDEX_NEW"
mv "$INDEX_NEW" "$INDEX"
echo "index-apk-repo.sh: done"
