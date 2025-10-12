#!/bin/bash

##
# mkbootfloppy.sh - Create a bootable RhapsodiOS boot floppy
#
# This script creates a bootable 1.44MB floppy disk image or writes directly
# to a floppy device for booting RhapsodiOS on x86 systems. The boot floppy
# contains the boot loader (boot1f + boot2) and can be used to boot from
# floppy when the hard disk boot loader is not available or for installation.
#
# Usage: ./mkbootfloppy.sh [options]
#
# Options:
#   -o OUTPUT    Output file (floppy image) (default: boot.img)
#   -d DEVICE    Write directly to floppy device (e.g., /dev/fd0, /dev/rdisk2)
#   -s SRCROOT   Source root directory (default: .)
#   -b           Build boot loader first
#   -v           Verbose output
#   -h           Show this help
#
# Requirements:
#   - Built boot loader: boot1f and boot in boot-2/i386
#   - For image: dd (standard Unix tool)
#   - For formatting: newfs_ufs or mkfs.ufs (UFS filesystem tools)
#
# Examples:
#   # Create a floppy image file
#   ./mkbootfloppy.sh -o boot.img
#
#   # Build boot loader and write to floppy device
#   ./mkbootfloppy.sh -b -d /dev/fd0
#
#   # Create image with verbose output
#   ./mkbootfloppy.sh -v -o rhapsodi-boot.img
##

set -e  # Exit on error

# Default values
OUTPUT_IMAGE="boot.img"
DEVICE=""
SRCROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_FIRST=0
VERBOSE=0

# Floppy specifications (1.44MB high-density floppy)
FLOPPY_SIZE=1440  # sectors (1440 KB = 1.44 MB)
SECTOR_SIZE=512
TOTAL_SIZE=$((FLOPPY_SIZE * 1024))  # bytes
BOOT1F_SIZE=512    # boot1f is exactly 512 bytes (one sector)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print functions
info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

verbose() {
    [ "$VERBOSE" -eq 1 ] && echo "[DEBUG] $*"
}

usage() {
    sed -n '3,30p' "$0" | sed 's/^# \?//'
    exit 1
}

# Parse command line arguments
while getopts "o:d:s:bvh" opt; do
    case $opt in
        o) OUTPUT_IMAGE="$OPTARG" ;;
        d) DEVICE="$OPTARG" ;;
        s) SRCROOT="$OPTARG" ;;
        b) BUILD_FIRST=1 ;;
        v) VERBOSE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Determine output target
if [ -n "$DEVICE" ]; then
    OUTPUT_TARGET="$DEVICE"
    OUTPUT_TYPE="device"
else
    OUTPUT_TARGET="$OUTPUT_IMAGE"
    OUTPUT_TYPE="image"
fi

# Check for required tools
check_requirements() {
    info "Checking requirements..."

    if ! command -v dd >/dev/null 2>&1; then
        error "dd not found"
    fi

    verbose "System: $(uname -s)"
}

# Build boot loader
build_bootloader() {
    if [ "$BUILD_FIRST" -eq 1 ]; then
        info "Building boot loader..."
        cd "${SRCROOT}/boot-2/i386"

        if [ -f Makefile ]; then
            make || error "Boot loader build failed"
            info "Boot loader built successfully"
        else
            error "No Makefile found in boot-2/i386"
        fi

        cd "${SRCROOT}"
    fi
}

# Verify boot files exist
verify_boot_files() {
    info "Verifying boot files..."

    local BOOT_DIR="${SRCROOT}/boot-2/i386"

    # Check for boot1f (floppy boot sector)
    if [ ! -f "${BOOT_DIR}/boot1/boot1f" ]; then
        error "boot1f not found at ${BOOT_DIR}/boot1/boot1f - run with -b to build"
    fi

    # Verify boot1f is exactly 512 bytes
    local boot1f_size
    if [ "$(uname -s)" = "Darwin" ]; then
        boot1f_size=$(stat -f%z "${BOOT_DIR}/boot1/boot1f")
    else
        boot1f_size=$(stat -c%s "${BOOT_DIR}/boot1/boot1f")
    fi

    if [ "$boot1f_size" -ne 512 ]; then
        error "boot1f size is $boot1f_size bytes (expected 512 bytes)"
    fi

    verbose "boot1f verified: 512 bytes"

    # Check for boot2
    if [ ! -f "${BOOT_DIR}/boot2/boot" ]; then
        error "boot2 (boot) not found at ${BOOT_DIR}/boot2/boot - run with -b to build"
    fi

    verbose "boot2 found: ${BOOT_DIR}/boot2/boot"
}

# Create floppy image or prepare device
create_floppy_base() {
    info "Creating $OUTPUT_TYPE: $OUTPUT_TARGET"

    if [ "$OUTPUT_TYPE" = "image" ]; then
        # Create blank 1.44MB floppy image
        dd if=/dev/zero of="$OUTPUT_TARGET" bs=$SECTOR_SIZE count=$FLOPPY_SIZE status=none
        verbose "Created blank floppy image: $FLOPPY_SIZE sectors"
    else
        # Verify device exists and is writable
        if [ ! -w "$DEVICE" ]; then
            error "Device $DEVICE is not writable (try running as root/sudo)"
        fi
        warn "Writing to device $DEVICE - ALL DATA WILL BE DESTROYED!"
        read -p "Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            error "Aborted by user"
        fi
    fi
}

# Write boot sector (boot1f) to first sector
write_boot_sector() {
    info "Writing boot sector (boot1f)..."

    local BOOT1F="${SRCROOT}/boot-2/i386/boot1/boot1f"

    # Write boot1f to the first sector (sector 0)
    dd if="$BOOT1F" of="$OUTPUT_TARGET" bs=$SECTOR_SIZE count=1 conv=notrunc status=none

    verbose "Boot sector written to sector 0"
}

# Write boot loader (boot2) starting at sector 1
write_boot_loader() {
    info "Writing boot loader (boot2)..."

    local BOOT2="${SRCROOT}/boot-2/i386/boot2/boot"

    # Get boot2 size
    local boot2_size
    if [ "$(uname -s)" = "Darwin" ]; then
        boot2_size=$(stat -f%z "$BOOT2")
    else
        boot2_size=$(stat -c%s "$BOOT2")
    fi

    verbose "boot2 size: $boot2_size bytes"

    # Calculate sectors needed for boot2 (round up)
    local boot2_sectors=$(( (boot2_size + SECTOR_SIZE - 1) / SECTOR_SIZE ))
    verbose "boot2 sectors: $boot2_sectors"

    # Check if boot2 fits in the boot cylinder
    # According to README, first cylinder is reserved for boot
    # For 1.44MB floppy: 18 sectors/track, 2 heads = 36 sectors/cylinder
    # We have sectors 1-35 available (sector 0 is boot1f)
    local max_boot_sectors=35

    if [ "$boot2_sectors" -gt "$max_boot_sectors" ]; then
        error "boot2 is too large ($boot2_sectors sectors, max $max_boot_sectors)"
    fi

    # Write boot2 starting at sector 1 (skip boot1f in sector 0)
    dd if="$BOOT2" of="$OUTPUT_TARGET" bs=$SECTOR_SIZE seek=1 conv=notrunc status=none

    info "Boot loader written: $boot2_sectors sectors starting at sector 1"
}

# Create minimal filesystem for boot files (optional - for data area)
create_filesystem() {
    info "Setting up boot data area..."

    # For a minimal boot floppy, we don't need a full filesystem
    # The boot loader is in the boot cylinder (sectors 0-35)
    # The rest can remain empty or contain minimal boot configuration

    # We could potentially add:
    # - /etc/boot.defaults
    # - Language files
    # - Boot bitmaps
    # But for a minimal boot floppy, just the boot loader is sufficient

    verbose "Boot floppy prepared with boot loader only"
}

# Generate checksum and info
generate_info() {
    info "=== Boot Floppy Creation Summary ==="
    echo ""

    if [ "$OUTPUT_TYPE" = "image" ]; then
        echo "Output Image:    $OUTPUT_TARGET"

        if [ -f "$OUTPUT_TARGET" ]; then
            local size=$(du -h "$OUTPUT_TARGET" | cut -f1)
            echo "Size:            $size (1.44 MB)"

            if command -v md5sum >/dev/null 2>&1; then
                echo "MD5:             $(md5sum "$OUTPUT_TARGET" | cut -d' ' -f1)"
            elif command -v md5 >/dev/null 2>&1; then
                echo "MD5:             $(md5 -q "$OUTPUT_TARGET")"
            fi
        fi
    else
        echo "Output Device:   $DEVICE"
        echo "Status:          Written successfully"
    fi

    echo ""
    echo "Boot Files:"
    echo "  boot1f (sector 0):     512 bytes"

    local boot2_size
    if [ "$(uname -s)" = "Darwin" ]; then
        boot2_size=$(stat -f%z "${SRCROOT}/boot-2/i386/boot2/boot")
    else
        boot2_size=$(stat -c%s "${SRCROOT}/boot-2/i386/boot2/boot")
    fi
    echo "  boot2  (sector 1+):    $boot2_size bytes"

    echo ""
    info "=== Next Steps ==="

    if [ "$OUTPUT_TYPE" = "image" ]; then
        echo "1. Test in VM: qemu-system-i386 -fda $OUTPUT_TARGET"
        echo "2. Write to floppy: dd if=$OUTPUT_TARGET of=/dev/fd0 bs=512"
        echo "3. Or on macOS: sudo dd if=$OUTPUT_TARGET of=/dev/rdiskN bs=512"
        echo "   (Find diskN with: diskutil list)"
    else
        echo "1. Insert floppy into target system and boot"
        echo "2. Follow RhapsodiOS installation prompts"
    fi

    echo ""
}

# Main execution
main() {
    info "RhapsodiOS Boot Floppy Creator"
    echo ""

    check_requirements
    build_bootloader
    verify_boot_files
    create_floppy_base
    write_boot_sector
    write_boot_loader
    create_filesystem
    generate_info

    info "Boot floppy created successfully!"
}

# Run main function
main
