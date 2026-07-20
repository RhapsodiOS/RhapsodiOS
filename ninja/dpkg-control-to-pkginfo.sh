#!/bin/sh
# Usage: dpkg-control-to-pkginfo.sh path/to/dpkg/control > apk/PKGINFO
set -e
CTL=$1
[ -f "$CTL" ] || { echo "usage: $0 path/to/dpkg/control" >&2; exit 2; }

# Extract a simple single-line field (first occurrence). Strips CR.
field() {
  key=$1
  sed -n "s/^${key}:[[:space:]]*//p" "$CTL" | head -1 | tr -d '\r'
}

pkgname=$(field Package)
pkgver=$(field Version)
url=$(field URL)
# Some controls use Homepage instead of URL
if [ -z "$url" ]; then
  url=$(field Homepage)
fi
arch=$(field Architecture)

# Description: first line only (synopsis). Continuation lines start with space/tab.
pkgdesc=$(sed -n 's/^Description:[[:space:]]*//p' "$CTL" | head -1 | tr -d '\r')

# Build-Depends: drop "(version)" constraints, map commas to spaces, collapse whitespace
builddepend=$(field Build-Depends \
  | sed 's/([^)]*)//g' \
  | tr ',' ' ' \
  | tr -s '[:space:]' ' ' \
  | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Depends (runtime), if present
depend=$(field Depends \
  | sed 's/([^)]*)//g' \
  | tr ',' ' ' \
  | tr -s '[:space:]' ' ' \
  | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$pkgname" ] || [ -z "$pkgver" ]; then
  echo "error: Package and Version are required in $CTL" >&2
  exit 1
fi

# license unknown when not present in dpkg control
license=unknown

printf 'pkgname = %s\n' "$pkgname"
printf 'pkgver = %s\n' "$pkgver"
printf 'pkgdesc = %s\n' "$pkgdesc"
printf 'url = %s\n' "$url"
printf 'license = %s\n' "$license"
printf 'builddepend = %s\n' "$builddepend"
printf 'depend = %s\n' "$depend"
if [ -n "$arch" ]; then
  printf 'arch = %s\n' "$arch"
fi
