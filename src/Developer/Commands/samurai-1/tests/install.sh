#!/bin/sh
# Native BSD install moves inputs unless explicitly told to copy them.
set -eu
here=`cd "\`dirname "$0"\`/.." && pwd`
work=${TMPDIR-/tmp}/samurai-install-$$
(umask 077 && mkdir "$work")
trap 'rm -rf "$work"' 0
trap 'exit 1' 1 2 3 15
cd "$here"
make=${MAKE-make}
for stage in first second; do
  "$make" install DSTROOT="$work/$stage"
  test -x samurai/samu
  test -f samurai/samu.1
  test -f samurai/LICENSE
  test -f PROVENANCE.md
  cmp samurai/samu "$work/$stage/usr/bin/samu"
  cmp samurai/samu.1 "$work/$stage/usr/share/man/man1/samu.1"
  cmp samurai/LICENSE "$work/$stage/usr/share/doc/samurai/LICENSE"
  cmp PROVENANCE.md "$work/$stage/usr/share/doc/samurai/PROVENANCE.md"
done
echo 'PASS: repeated staged installation preserves build inputs'
