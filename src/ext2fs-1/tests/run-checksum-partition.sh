#!/bin/sh
# Real bounded reads plus two controls that a successful consumer cannot hide.
set -e
helper=$1
work=$2
test -f "$helper" && test ! -e "$work"
helper=`cd "\`dirname "$helper"\`" && pwd`/`basename "$helper"`
mkdir -p "$work"
work=`cd "$work" && pwd`
real_dd=/bin/dd
test -x "$real_dd" || real_dd=/usr/bin/dd
test -x "$real_dd"
"$real_dd" if=/dev/zero of="$work/full" bs=1024 count=16384 2> "$work/create.dd-log"
"$real_dd" if=/dev/zero of="$work/short" bs=1024 count=1 2> "$work/create-short.dd-log"
failures=0
if /bin/sh "$helper" "$work/full" 16384 "$work/full.crc"; then
    echo CHECKSUM_PARTITION_PASS real_full_16MiB
else
    echo CHECKSUM_PARTITION_FAIL real_full_16MiB
    failures=`expr "$failures" + 1`
fi
mkdir "$work/error-bin"
cat > "$work/error-bin/dd" <<EOF
#!/bin/sh
"$real_dd" "\$@"
status=\$?
test "\$status" = 0 || exit "\$status"
exit 7
EOF
chmod 755 "$work/error-bin/dd"
set +e
PATH="$work/error-bin:$PATH" /bin/sh "$helper" "$work/full" 16384 "$work/error.crc"
error_status=$?
/bin/sh "$helper" "$work/short" 16384 "$work/short.crc"
short_status=$?
set -e
if test "$error_status" != 0; then
    echo "CHECKSUM_PARTITION_PASS full_data_producer_exit7 helper=$error_status"
else
    echo CHECKSUM_PARTITION_FAIL hidden_producer_exit7
    failures=`expr "$failures" + 1`
fi
if test "$short_status" != 0; then
    echo "CHECKSUM_PARTITION_PASS short_data_producer_exit0 helper=$short_status"
else
    echo CHECKSUM_PARTITION_FAIL accepted_short_data
    failures=`expr "$failures" + 1`
fi
echo "CHECKSUM_PARTITION cases=3 failures=$failures"
test "$failures" = 0
