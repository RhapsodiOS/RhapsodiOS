#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
driver_dir=$(dirname -- "$(dirname -- "$test_dir")")
lks_dir="$driver_dir/Intel82556.drvproj/Intel82556.lksproj"
CC=${CC:-cc}
CFLAGS=${CFLAGS:--Wall -Werror -traditional-cpp}
CPPFLAGS=${CPPFLAGS:-}
tmp=${TMPDIR:-/tmp}/drvintel82556-adapters-$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' 0 1 2 15
for bus in EISA PCI; do
    expected=9
    test "$bus" != EISA || expected=10
    awk -v expected="$expected" -v bus="$bus" '
    BEGIN { preamble=1; take=0; count=0 }
    { sub(/\015$/, "") }
    /^@implementation/ { preamble=0; print; next }
    preamble { print; next }
    /^[+-]/ {
        take=($0 ~ /\)clearIrqLatch$/ || $0 ~ /\)interruptOccurred$/ ||
              $0 ~ /\)sendPortCommand:/ || $0 ~ /\)sendChannelAttention$/ ||
              $0 ~ /\)initPLXchip$/ || $0 ~ /\)resetPLXchip$/ ||
              $0 ~ /\)lockDBRT$/ || $0 ~ /\)enableAdapterInterrupts$/ ||
              $0 ~ /\)disableAdapterInterrupts$/ || $0 ~ /\)getEthernetAddress$/)
        if (take) count++
    }
    take { print }
    /^}/ { take=0 }
    END {
        print "@end"
        if (bus == "EISA") print "int TestCardIRQ(unsigned int base) { return card_irq(base); }"
        if (count != expected) {
            print "adapter selector count mismatch: " count " vs " expected > "/dev/stderr"
            exit 3
        }
    }' "$lks_dir/IntelPRO100$bus.m" > "$tmp/$bus.m"
done
# The actual production method bodies run against an isolated port/sleep trace.
$CC $CFLAGS -w -Di386 -DKERNEL -I"$test_dir/adapter-include" \
    -I"$test_dir/include" -I"$lks_dir" $CPPFLAGS \
    -o "$tmp/adapters" "$test_dir/adapter.m" "$tmp/EISA.m" "$tmp/PCI.m"
"$tmp/adapters"
