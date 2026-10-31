#!/bin/sh
set -eu

group=${1:-all}
case "$group" in
	layouts|firmware|him|config|optima|integration|all) ;;
	*) printf '{"group":"%s","ok":false,"error":"unknown group"}\n' "$group"; exit 2 ;;
esac

test_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$test_dir/../../../../../../.." && pwd)
cc=${CC:-cc}
temporary=${TMPDIR:-/tmp}
binary="$temporary/adaptec2940-checks-$$"
trap 'rm -f "$binary"' EXIT HUP INT TERM

source_hash=${A2940_BUILD_HASH:-}
if [ -z "$source_hash" ] && [ -d "$repo_root/.git" ]; then
	source_hash=$(git -C "$repo_root" rev-parse HEAD)
fi
if [ -z "$source_hash" ]; then
	source_hash=unknown
fi
"$cc" ${CFLAGS:-} -DKERNEL -x objective-c -arch i386 \
	-I"$repo_root/src/driverkit-3" \
	-I"$repo_root/src/kernel-7" \
	-I"$repo_root/src" \
	-DA2940_BUILD_HASH=\"$source_hash\" \
	-o "$binary" "$test_dir/adaptec2940-checks.c"

"$binary" "$group"
