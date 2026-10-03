#!/bin/sh
set -eu

case_name=${1:-all}
case "$case_name" in
    layout|pool|packets|control|adapters|all) ;;
    *) echo "usage: $0 layout|pool|packets|control|adapters|all" >&2; exit 2 ;;
esac

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
recon_dir=$(dirname -- "$test_dir")
driver_dir=$(dirname -- "$recon_dir")
lks_dir="$driver_dir/Intel82596NetworkDriver.drvproj/Intel82596NetworkDriver.lksproj"
repo_root=$(CDPATH= cd -- "$driver_dir/../../../../.." && pwd)
CC=${CC:-cc}
CFLAGS=${CFLAGS:--ansi -pedantic -Wall -Werror -traditional-cpp}
tmp=${TMPDIR:-/tmp}/drvintel82596-tests-$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

run_layout() {
    $CC $CFLAGS -I"$lks_dir" -o "$tmp/layout" "$test_dir/layout.c"
    "$tmp/layout"
}

run_pool() {
    $CC $CFLAGS -DKERNEL -DNXSpinLock=I596TestSpinLock -I"$lks_dir" -I"$test_dir" \
        -o "$tmp/pool" "$test_dir/pool.m" "$test_dir/test_support.m" \
        "$lks_dir/Intel82596Buf.m"
    "$tmp/pool"
}

case "$case_name" in
    layout) run_layout ;;
    pool) run_pool ;;
    packets) echo "packets: pending task 3" >&2; exit 2 ;;
    control) echo "control: pending task 3" >&2; exit 2 ;;
    adapters) echo "adapters: pending tasks 4-5" >&2; exit 2 ;;
    all) run_layout; run_pool ;;
esac
