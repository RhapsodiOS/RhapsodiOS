#!/bin/sh
set -eu
HERE=`cd "$(dirname "$0")" && pwd`
LKS="$HERE/../../Intel82595NetworkDriver.drvproj/Intel82595NetworkDriver.lksproj"
TMP="${TMPDIR:-/tmp}/intel82595-tests-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' 0 1 2 15
${CC:-cc} -Wall -Werror -I"$LKS" "$HERE/ports.c" -o "$TMP/ports"
"$TMP/ports"
${CC:-cc} -Wall -I"$HERE/include" -I"$HERE" -I"$LKS" \
    "$HERE/driver.m" "$HERE/support.m" "$LKS/Intel82595.m" \
    "$LKS/Intel82595ISA.m" "$LKS/CogentEM525.m" "$LKS/CogentEM595.m" \
    "$LKS/IntelEEPro10.m" "$LKS/IntelEEPro10+.m" "$LKS/i82595eeprom.m" \
    -o "$TMP/driver"
"$TMP/driver"
