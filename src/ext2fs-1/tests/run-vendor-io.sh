#!/bin/sh
# Use the configured vendor source/objects from the selected native CPU build.
set -e
source=`cd "$1" && pwd`
objects=`cd "$2" && pwd`
work=$3
test -n "$work" && test ! -e "$work"
mkdir -p "$work"
work=`cd "$work" && pwd`
tests=`cd "$(dirname "$0")" && pwd`
test -s "$objects/MCONFIG"
test -s "$objects/lib/ext2fs/ext2_types.h"
test -s "$objects/lib/ext2fs/ext2_err.h"
cksum "$source/lib/ext2fs/unix_io.c" "$objects/MCONFIG" "$tests/vendor_io_test.c"
cat > "$work/Makefile" <<EOF
top_builddir=$objects
top_srcdir=$source
include $objects/MCONFIG
vendor_io_test: $tests/vendor_io_test.c
	\$(CC) \$(ALL_CFLAGS) -Wall -I$objects/lib/ext2fs -I$source/lib/ext2fs -DVENDOR_UNIX_IO='"$source/lib/ext2fs/unix_io.c"' $tests/vendor_io_test.c -o vendor_io_test
EOF
/bin/gnumake -C "$work" vendor_io_test
lipo -info "$work/vendor_io_test"
case "${4-run}" in
 build) ;;
 run) "$work/vendor_io_test" "$work/private-data" ;;
 *) exit 2 ;;
esac
