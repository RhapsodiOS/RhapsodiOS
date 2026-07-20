#!/bin/sh
# Usage: publish-apk-repo.sh <repo-dir> <pkginfo> <stage-root> [<pkginfo> <stage-root> ...]
# For each pair, runs ninja/mkapk.sh into repo-dir, then indexes with apk if available.
set -e
SCRIPT_ROOT="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO=$1
shift
if [ -z "$REPO" ] || [ $# -lt 2 ]; then
  echo "usage: $0 <repo-dir> <pkginfo> <stage-root> [...]" >&2
  exit 2
fi
mkdir -p "$REPO"
while [ $# -ge 2 ]; do
  PKGINFO=$1
  STAGE=$2
  shift 2
  # derive name-ver from PKGINFO
  name=$(sed -n 's/^pkgname = //p' "$PKGINFO" | head -1 | tr -d '\r')
  ver=$(sed -n 's/^pkgver = //p' "$PKGINFO" | head -1 | tr -d '\r')
  out="$REPO/${name}-${ver}.apk"
  "$SCRIPT_ROOT/mkapk.sh" "$PKGINFO" "$STAGE" "$out"
done
APK="${APK:-apk}"
# apk-tools 2.0_pre11: `apk index` writes uncompressed index to stdout; repo file is APK_INDEX.gz
INDEX_NEW="$REPO/APK_INDEX.gz.new"
INDEX="$REPO/APK_INDEX.gz"
if command -v "$APK" >/dev/null 2>&1 || [ -x "$APK" ]; then
  "$APK" index "$REPO"/*.apk | gzip -n > "$INDEX_NEW"
  mv "$INDEX_NEW" "$INDEX"
else
  echo "warning: apk not found; packages written but APK_INDEX.gz not generated" >&2
  echo "  set APK=/path/to/apk and re-run, or: apk index $REPO/*.apk | gzip -n > $INDEX" >&2
fi
