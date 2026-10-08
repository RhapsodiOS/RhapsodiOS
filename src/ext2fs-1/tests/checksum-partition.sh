#!/bin/sh
# Test helper: checksum only the selected fixture's known 1024-byte blocks.
set -e
test "$#" = 3
device=$1
count=$2
output=$3
case "$count" in ''|*[!0-9]*) exit 2;; esac
test "$count" -gt 0
: > "$output.dd-status"
(
    # The consumer's success cannot hide a failed or partial raw-device read.
    set +e
    dd if="$device" bs=1024 count="$count" 2> "$output.dd-log"
    status=$?
    echo "$status" > "$output.dd-status"
    exit "$status"
) | cksum > "$output"
test "`cat "$output.dd-status"`" = 0
grep "^$count+0 records in$" "$output.dd-log" > /dev/null
grep "^$count+0 records out$" "$output.dd-log" > /dev/null
read crc bytes rest < "$output"
test "$bytes" = "`expr "$count" \* 1024`"
echo "PARTITION_CHECKSUM blocks=$count bytes=$bytes crc=$crc producer=0"
