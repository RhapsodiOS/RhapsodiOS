#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
driver_dir=$(dirname -- "$(dirname -- "$test_dir")")
lks_dir="$driver_dir/Intel82556.drvproj/Intel82556.lksproj"
source=${1:-$lks_dir/Intel82556.m}
CC=${CC:-cc}
CFLAGS=${CFLAGS:--Wall -Werror -traditional-cpp}
CPPFLAGS=${CPPFLAGS:-}
tmp=${TMPDIR:-/tmp}/drvintel82556-core-$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' 0 1 2 15
# Copy the production preamble and eight method bodies without translation.
# Refuse obsolete selector spellings before attempting to compile a baseline.
awk '
BEGIN { preamble=1; count=0; take=0 }
{ sub(/\015$/, "") }
/^@implementation Intel82556$/ { preamble=0; print; next }
preamble { print; next }
/^-/ {
    take=($0 ~ /\)_waitCu:/ || $0 ~ /\)_waitScb$/ ||
          $0 ~ /\)_initRfdList$/ || $0 ~ /\)_initTcbList$/ ||
          $0 ~ /\)acknowledgeInterrupts:/ || $0 ~ /\)config$/ ||
          $0 ~ /\)sendPacket:/ || $0 ~ /\)receivePacket:/)
    if (take) count++
}
take { print }
/^}/ { take=0 }
END {
    print "@end"
    if (count != 8) {
        print "core selector contract: expected 8 reference methods, found " count > "/dev/stderr"
        exit 3
    }
}' "$source" > "$tmp/engine.m"
# These objects intentionally implement only the selected methods and service
# stubs; suppress incomplete-class warnings only in this isolated test build.
$CC $CFLAGS -w -Di386 -DKERNEL -I"$test_dir/include" -I"$lks_dir" $CPPFLAGS \
    -o "$tmp/core" "$test_dir/core.m" "$tmp/engine.m"
"$tmp/core"
