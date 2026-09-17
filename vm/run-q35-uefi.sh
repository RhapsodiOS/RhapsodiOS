#!/bin/sh
# Boot a hybrid UEFI image under QEMU with IA32 OVMF.  The source image is
# only copied; every writable disk lives in vm/work.  COM1 is recorded in
# vm/logs/uefi-serial.log.

set -eu

script_path=$0
case "$script_path" in
    */*) script_dir_part=${script_path%/*} ;;
    *) script_dir_part=. ;;
esac
script_dir=`CDPATH= cd "$script_dir_part" && pwd -P`
repo_root=`CDPATH= cd "$script_dir/.." && pwd -P`
work_root=$repo_root/vm/work
logs_dir=$repo_root/vm/logs
firmware_dir=${UEFI_FIRMWARE_DIR:-$repo_root/vm/firmware}
serial_log=$logs_dir/uefi-serial.log
qemu=${UEFI_QEMU:-qemu-system-i386}
code_fd=$firmware_dir/OVMF32_CODE.fd
vars_fd=$firmware_dir/OVMF32_VARS.fd

die()
{
    echo "run-q35-uefi: $*" >&2
    exit 1
}

usage()
{
    echo "usage: $0 SOURCE_HYBRID_IMAGE vm/work/IMAGE" >&2
    exit 2
}

[ $# -eq 2 ] || usage
src_image=$1
dst_image=$2

[ -f "$src_image" ] || die "no such image: $src_image"
[ -f "$code_fd" ] || die "missing firmware: $code_fd"
[ -f "$vars_fd" ] || die "missing firmware: $vars_fd"

case "$dst_image" in
    "$work_root"/*) ;;
    *) die "destination must be under $work_root" ;;
esac

mkdir -p "$work_root" "$logs_dir"
cp "$src_image" "$dst_image"
vars_copy=$work_root/OVMF32_VARS.fd
cp "$vars_fd" "$vars_copy"

exec "$qemu" \
    -machine q35 \
    -m 256 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$code_fd" \
    -drive if=pflash,format=raw,unit=1,file="$vars_copy" \
    -drive id=disk0,file="$dst_image",format=raw,if=none \
    -device ich9-ahci,id=ahci \
    -device ide-hd,drive=disk0,bus=ahci.0 \
    -serial "file:$serial_log" \
    -display none \
    -vga std
