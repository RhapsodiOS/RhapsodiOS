#!/bin/sh
# Run the reconstructed BusLogic FlashPoint tests with an i386 guest compiler.
set -eu

ROOT=${SRCROOT:-.}
TESTS="$ROOT/src/drivers-i386/scsi/drvBusLogicFP/reconstruction/tests"
DRIVER="$ROOT/src/drivers-i386/scsi/drvBusLogicFP/BusLogicFP.drvproj/BusLogicFP.lksproj"
CC=${CC:-cc}
CFLAGS=${CFLAGS:-}
OUT=${BLFP_TEST_OUT:-$ROOT/.blfp-test-out}
CASE=${1:-all}

mkdir -p "$OUT"
MACROS=`printf '\n' | $CC $CFLAGS -dM -E -`
echo "$MACROS" | grep '__i386__' >/dev/null || {
    echo "verify.sh: compiler target is not i386" >&2
    exit 2
}

run_layout()
{
    echo "layout: SCCB 260 bytes, 17 SG entries, manager/card/target offsets"
    $CC $CFLAGS -std=c99 -ffreestanding -I"$TESTS/include" -fsyntax-only "$TESTS/layout.c"
    echo "layout: 43 ABI assertions passed"
}

run_queues()
{
    echo "queues: queue links, disconnect/flush, residual, port/wait trace, manager init, page boundaries"
    $CC $CFLAGS -std=c99 -DBLFP_TEST_IO -DBLFP_TEST_STUB_SCAM_INIT -I"$TESTS/include" \
        "$TESTS/queues.c" "$TESTS/io_mock.c" "$DRIVER/FlashPoint.c" \
        -o "$OUT/queues"
    "$OUT/queues"
    echo "queues: trace scenario groups passed"
}

case "$CASE" in
    layout) run_layout ;;
    queues) run_queues ;;
    all) run_layout; run_queues ;;
    *) echo "usage: $0 layout|queues|all" >&2; exit 2 ;;
esac
