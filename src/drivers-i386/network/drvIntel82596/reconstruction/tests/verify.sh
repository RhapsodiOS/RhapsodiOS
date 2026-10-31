#!/bin/sh
set -eu

case_name=${1:-all}
case "$case_name" in
    layout|pool|all) ;;
    *) echo "usage: $0 layout|pool|all" >&2; exit 2 ;;
esac

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
recon_dir=$(dirname -- "$test_dir")
driver_dir=$(dirname -- "$recon_dir")
lks_dir="$driver_dir/Intel82596NetworkDriver.drvproj/Intel82596NetworkDriver.lksproj"
CC=${CC:-cc}
CFLAGS=${CFLAGS:--Wall -Werror -traditional-cpp}
tmp=${TMPDIR:-/tmp}/drvintel82596-tests-$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' 0 1 2 15

run_layout() {
    $CC $CFLAGS -I"$lks_dir" -o "$tmp/layout" "$test_dir/layout.c"
    "$tmp/layout"
}

run_pool() {
    $CC $CFLAGS -Di386 -DKERNEL -DNXSpinLock=I596TestSpinLock \
        -I"$test_dir/include" -I"$lks_dir" -I"$test_dir" \
        -o "$tmp/pool" "$test_dir/pool.m" "$test_dir/test_support.m" \
        "$lks_dir/Intel82596Buf.m"
    "$tmp/pool"
}

case "$case_name" in
    layout) run_layout ;;
    pool) run_pool ;;
    all) run_layout; run_pool ;;
esac
