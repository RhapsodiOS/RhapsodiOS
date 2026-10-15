#!/bin/sh
set -eu
config=$1
outdir=$2
manifest=$3
rm -f "$outdir/validated"
commands=$outdir/commands.check.$$
messages=$outdir/messages.check.$$
trap 'rm -f "$commands" "$messages"' 0
"${SAMU-samu}" -f "$manifest" -t commands "$outdir/mach_kernel" > "$commands"
if awk -v config="${config}_I386" -v outdir="$outdir" -v srcdir="`pwd`" \
    -f ninja/check-config.awk "$outdir/Makefile" "$commands" > "$messages"; then
    cat "$messages"
else
    cat "$messages" >&2
    exit 1
fi
date > "$outdir/validated"
