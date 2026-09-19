#!/bin/sh
# EXPERIMENT ONLY -- not a committed-behavior runner. Copy of run-q35-uefi.sh
# with the -device ich9-ahci controller removed, so the two disks attach to
# q35's BUILT-IN ICH9 SATA controller (buses ide.0 / ide.1) instead of a
# second, separately-added ich9-ahci device at a different PCI slot. This
# exists to test whether DriverKit's AHCI probe was binding to the wrong
# (empty) controller when both were present. See
# .superpowers/sdd/ahci-builtin-controller-report.md for the result.
#
# Boot the two-disk UEFI layout under QEMU with IA32 OVMF: disk 0 is the
# Rhapsody filesystem image (attached whole, so boot-2's read_label() sees
# part_offset == 0), disk 1 is an ESP-only disk holding the UEFI loader that
# OVMF boots from.  The Rhapsody source image is only copied; every writable
# disk lives in vm/work.  COM1 is recorded in vm/logs/uefi-serial.log (OVMF
# firmware and the loader); COM2, the Rhapsody kernel's console, is recorded
# in vm/logs/uefi-kernel.log.

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
    echo "run-q35-uefi-builtin: $*" >&2
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
# disable_s3 tells OVMF that S3 (suspend-to-RAM) is unavailable, which
# suppresses its low ACPI NVS S3 save-state reservation -- otherwise that
# reservation caps the contiguous span the kernel can be given at ~7MB.
#
# No -device ich9-ahci here: q35 already has a built-in ICH9 SATA controller
# at PCI 0:31.2 with buses ide.0 through ide.5. Attaching disks to ide.0 /
# ide.1 puts both disks on that single controller instead of adding a second
# one.
exec "$qemu" \
    -machine q35 \
    -cpu Nehalem \
    -m 256 \
    -global ICH9-LPC.disable_s3=1 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$code_fd" \
    -drive if=pflash,format=raw,unit=1,file="$vars_copy" \
    -drive id=disk0,file="$dst_image",format=raw,if=none \
    -drive id=disk1,file="$esp_image",format=raw,if=none \
    -device ide-hd,drive=disk0,bus=ide.0 \
    -device ide-hd,drive=disk1,bus=ide.1 \
    -serial "file:$serial_log" \
    -serial "file:$kernel_log" \
    -display none \
    -vga cirrus \
    -qmp "tcp:127.0.0.1:${UEFI_QMP_PORT:-4446},server=on,wait=off"
