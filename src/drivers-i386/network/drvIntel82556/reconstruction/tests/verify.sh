#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
driver_dir=$(dirname -- "$(dirname -- "$test_dir")")
lks_dir="$driver_dir/Intel82556.drvproj/Intel82556.lksproj"
CC=${CC:-cc}
CFLAGS=${CFLAGS:--Wall -Werror -traditional-cpp}
CPPFLAGS=${CPPFLAGS:-}
tmp=${TMPDIR:-/tmp}/drvintel82556-tests-$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' 0 1 2 15
$CC $CFLAGS -Di386 -DKERNEL -DNXSpinLock=I556TestSpinLock \
    -I"$test_dir/include" -I"$lks_dir" -I"$test_dir" $CPPFLAGS \
    -o "$tmp/pool" "$test_dir/pool.m" "$test_dir/test_support.m" \
    "$lks_dir/Intel82556Buf.m"
"$tmp/pool"
$CC $CFLAGS -Di386 -DKERNEL -I"$test_dir/include" -I"$lks_dir" $CPPFLAGS \
    -o "$tmp/layout" "$test_dir/layout.m"
"$tmp/layout"
