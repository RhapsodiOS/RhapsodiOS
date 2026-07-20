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
INDEX_NEW="$REPO/APKINDEX.tar.gz.new"
INDEX="$REPO/APKINDEX.tar.gz"
if command -v "$APK" >/dev/null 2>&1 || [ -x "$APK" ]; then
  "$APK" index -o "$INDEX_NEW" "$REPO"/*.apk
  mv "$INDEX_NEW" "$INDEX"
else
  echo "warning: apk not found; packages written but APKINDEX not generated" >&2
  echo "  set APK=/path/to/apk and re-run, or: apk index -o $INDEX $REPO/*.apk" >&2
fi
