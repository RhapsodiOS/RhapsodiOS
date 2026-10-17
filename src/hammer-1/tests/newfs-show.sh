#!/bin/sh
# newfs-show.sh IMAGE: format a 2 GB regular file with our newfs_hammer and
# inspect it offline with our hammer show/checkmap.  BIN selects the tools.
BIN=${BIN:-.}
IMG=$1
fail() { echo "FAIL: $*"; exit 1; }
test -n "$IMG" || fail "usage: newfs-show.sh IMAGE"
rm -f $IMG
# Rhapsody has no /dev/zero; make a sparse 2047 MiB file (below 2^31).
perl -e 'open(F, ">$ARGV[0]") or die; truncate(F, 2047 * 1048576) or die' $IMG ||
	fail "create image"

$BIN/newfs_hammer -L T -f $IMG > newfs.out 2>&1 || { cat newfs.out; fail "newfs_hammer"; }
$BIN/hammer -f $IMG show > show.out 2>&1 || { tail -20 show.out; fail "hammer show"; }
$BIN/hammer -f $IMG checkmap > checkmap.out 2>&1 || { tail -20 checkmap.out; fail "hammer checkmap"; }

if grep -E ' bad (nodes|elms|records)$' show.out; then fail "show reports damage"; fi
if grep -E '^B[ZM]	| errors$| bad (nodes|layer1|layer2)$' checkmap.out; then fail "checkmap reports damage"; fi
grep -q 'NODE' show.out || fail "show printed no B-Tree nodes"
echo "HAMMER_OK newfs-show"
