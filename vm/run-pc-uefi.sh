#!/bin/sh
# Boot the two-disk UEFI layout under QEMU with IA32 OVMF, on an i440FX/PIIX3
# machine instead of q35/ICH9-AHCI: disk 0 is the Rhapsody filesystem image
# (attached whole, so boot-2's read_label() sees part_offset == 0), disk 1 is
# an ESP-only disk holding the UEFI loader that OVMF boots from.  The
# Rhapsody source image is only copied; every writable disk lives in
# vm/work.  COM1 is recorded in vm/logs/uefi-serial.log (OVMF firmware and
# the loader); COM2, the Rhapsody kernel's console, is recorded in
# vm/logs/uefi-kernel.log.
#
# This is a copy of run-q35-uefi.sh with the disk controller swapped from
# q35's ich9-ahci to i440FX's built-in PIIX3 IDE (ide.0/ide.1) -- an
# experiment to see whether the kernel mounts root when its disk sits on a
# controller the EIDE boot driver actually has a driver for (see
# .superpowers/sdd/task-8-ide-report.md).

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
kernel_log=$logs_dir/uefi-kernel.log
# Homebrew's qemu formula does not build on this host: it compiles every
# target, and the ARM board files fail under clang 15.  An i386-only source
# build lives in ~/opt/qemu-i386.  Prefer it, fall back to PATH.
qemu=${UEFI_QEMU:-}
if [ -z "$qemu" ]; then
    if [ -x "$HOME/opt/qemu-i386/bin/qemu-system-i386" ]; then
        qemu=$HOME/opt/qemu-i386/bin/qemu-system-i386
    else
        qemu=qemu-system-i386
    fi
fi
code_fd=$firmware_dir/OVMF32_CODE.fd
vars_fd=$firmware_dir/OVMF32_VARS.fd

die()
{
    echo "run-pc-uefi: $*" >&2
    exit 1
}

usage()
{
    echo "usage: $0 SOURCE_RHAPSODY_IMAGE ESP_IMAGE vm/work/IMAGE" >&2
    exit 2
}

[ $# -eq 3 ] || usage
src_image=$1
esp_image=$2
dst_image=$3

[ -f "$src_image" ] || die "no such image: $src_image"
[ -f "$esp_image" ] || die "no such image: $esp_image"
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

# QEMU's default i386 CPU model lacks paging/NX support this OVMF DEBUG
# build asserts on during DXE startup (before BDS even runs); Nehalem has
# what it needs. (Task 3 finding.)
#
# disable_s3 tells the platform that S3 (suspend-to-RAM) is unavailable,
# which suppresses OVMF's low ACPI NVS S3 save-state reservation --
# otherwise that reservation caps the contiguous span the kernel can be
# given at ~7MB.  On i440FX the ACPI/PM function lives in the PIIX4 PM
# device rather than ICH9-LPC; PIIX4_PM.disable_s3 is its equivalent.
exec "$qemu" \
    -machine pc \
    -cpu Nehalem \
    -m 256 \
    -global PIIX4_PM.disable_s3=1 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$code_fd" \
    -drive if=pflash,format=raw,unit=1,file="$vars_copy" \
    -drive id=disk0,file="$dst_image",format=raw,if=none \
    -drive id=disk1,file="$esp_image",format=raw,if=none \
    -device ide-hd,drive=disk0,bus=ide.0,unit=0 \
    -device ide-hd,drive=disk1,bus=ide.1,unit=0 \
    -serial "file:$serial_log" \
    -serial "file:$kernel_log" \
    -display none \
    -vga cirrus \
    -qmp "tcp:127.0.0.1:${UEFI_QMP_PORT:-4446},server=on,wait=off"
