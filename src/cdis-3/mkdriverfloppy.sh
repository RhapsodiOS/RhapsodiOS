#!/bin/bash

##
# mkdriverfloppy.sh - Create a RhapsodiOS driver floppy
#
# This script creates a 1.44MB driver floppy disk image or writes directly
# to a floppy device. The driver floppy contains kernel extensions (.driver
# or .bundle files) that can be loaded during boot for additional hardware
# support not included in the base system.
#
# The RhapsodiOS boot loader can prompt for driver disks and will scan
# /usr/Drivers/ for loadable kernel extensions.
#
# Usage: ./mkdriverfloppy.sh [options]
#
# Options:
#   -o OUTPUT    Output file (floppy image) (default: drivers.img)
#   -d DEVICE    Write directly to floppy device (e.g., /dev/fd0, /dev/rdisk2)
#   -i INPUT     Input directory containing drivers (default: ./drivers)
#   -l LABEL     Volume label (default: RhapsodiDrivers)
#   -t TYPE      Filesystem type: ufs, msdos, hfs (default: ufs)
#   -v           Verbose output
#   -h           Show this help
#
# Requirements:
#   - Driver files (.driver, .bundle, or directories containing driver bundles)
#   - For UFS: newfs_ufs or mkfs.ufs
#   - For DOS: mkfs.msdos or newfs_msdos (most compatible)
#   - For HFS: hformat (from hfsutils) or newfs_hfs
#   - hdiutil (macOS) or mount/losetup (Linux) for mounting images
#
# Examples:
#   # Create driver floppy from drivers directory
#   ./mkdriverfloppy.sh -i ./my_drivers -o drivers.img
#
#   # Create DOS filesystem driver floppy (most compatible)
#   ./mkdriverfloppy.sh -t msdos -i ./drivers -o drivers-dos.img
#
#   # Write directly to floppy device
#   ./mkdriverfloppy.sh -i ./drivers -d /dev/fd0
##

set -e  # Exit on error

# Default values
OUTPUT_IMAGE="drivers.img"
DEVICE=""
DRIVERS_DIR="./drivers"
FS_TYPE="ufs"
VOLUME_LABEL="RhapsodiDrivers"
VERBOSE=0

# Floppy specifications (1.44MB high-density floppy)
FLOPPY_SIZE=1440  # sectors (1440 KB = 1.44 MB)
SECTOR_SIZE=512
TOTAL_SIZE=$((FLOPPY_SIZE * 1024))  # bytes

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
    sed -n '3,36p' "$0" | sed 's/^# \?//'
    exit 1
}

# Parse command line arguments
while getopts "o:d:i:l:t:vh" opt; do
    case $opt in
        o) OUTPUT_IMAGE="$OPTARG" ;;
        d) DEVICE="$OPTARG" ;;
        i) DRIVERS_DIR="$OPTARG" ;;
        l) VOLUME_LABEL="$OPTARG" ;;
        t) FS_TYPE="$OPTARG" ;;
        v) VERBOSE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate filesystem type
case "$FS_TYPE" in
    ufs|msdos|hfs) ;;
    *) error "Invalid filesystem type: $FS_TYPE (must be ufs, msdos, or hfs)" ;;
esac

# Determine output target
if [ -n "$DEVICE" ]; then
    OUTPUT_TARGET="$DEVICE"
    OUTPUT_TYPE="device"
else
    OUTPUT_TARGET="$OUTPUT_IMAGE"
    OUTPUT_TYPE="image"
fi

# Temporary mount point
TEMP_MOUNT=$(mktemp -d /tmp/rhapsodi-driver-floppy.XXXXXX)

# Cleanup function
cleanup() {
    if [ -d "$TEMP_MOUNT" ]; then
        # Try to unmount if mounted
        if mount | grep -q "$TEMP_MOUNT"; then
            if [ "$(uname -s)" = "Darwin" ]; then
                hdiutil detach "$TEMP_MOUNT" 2>/dev/null || true
            else
                umount "$TEMP_MOUNT" 2>/dev/null || true
            fi
        fi
        rmdir "$TEMP_MOUNT" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Check for required tools
check_requirements() {
    info "Checking requirements..."

    if ! command -v dd >/dev/null 2>&1; then
        error "dd not found"
    fi

    # Check for filesystem tools
    case "$FS_TYPE" in
        ufs)
            if ! command -v newfs_ufs >/dev/null 2>&1 && ! command -v mkfs.ufs >/dev/null 2>&1; then
                error "UFS filesystem tools not found (newfs_ufs or mkfs.ufs required)"
            fi
            ;;
        msdos)
            if ! command -v mkfs.msdos >/dev/null 2>&1 && ! command -v newfs_msdos >/dev/null 2>&1; then
                error "DOS filesystem tools not found (mkfs.msdos or newfs_msdos required)"
            fi
            ;;
        hfs)
            if ! command -v hformat >/dev/null 2>&1 && ! command -v newfs_hfs >/dev/null 2>&1; then
                error "HFS filesystem tools not found (hformat or newfs_hfs required)"
            fi
            ;;
    esac

    verbose "System: $(uname -s)"
    verbose "Filesystem: $FS_TYPE"
}

# Verify driver directory exists and contains drivers
verify_drivers() {
    info "Verifying driver files..."

    if [ ! -d "$DRIVERS_DIR" ]; then
        error "Driver directory not found: $DRIVERS_DIR"
    fi

    # Count driver files
    local driver_count=0
    if [ -d "$DRIVERS_DIR" ]; then
        driver_count=$(find "$DRIVERS_DIR" -type f \( -name "*.driver" -o -name "*.bundle" \) 2>/dev/null | wc -l)
        driver_count=$((driver_count + $(find "$DRIVERS_DIR" -type d \( -name "*.driver" -o -name "*.bundle" \) 2>/dev/null | wc -l)))
    fi

    if [ "$driver_count" -eq 0 ]; then
        warn "No driver files found in $DRIVERS_DIR"
        warn "Looking for .driver or .bundle files/directories"
        warn ""
        warn "Creating empty driver floppy (can be populated manually later)"
    else
        info "Found $driver_count driver(s) in $DRIVERS_DIR"
    fi

    verbose "Driver directory: $DRIVERS_DIR"
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

# Create filesystem on floppy
create_filesystem() {
    info "Creating $FS_TYPE filesystem..."

    case "$FS_TYPE" in
        ufs)
            if command -v newfs_ufs >/dev/null 2>&1; then
                newfs_ufs -L "$VOLUME_LABEL" "$OUTPUT_TARGET" >/dev/null 2>&1
            elif command -v mkfs.ufs >/dev/null 2>&1; then
                mkfs.ufs -L "$VOLUME_LABEL" "$OUTPUT_TARGET" >/dev/null 2>&1
            else
                error "No UFS formatting tool available"
            fi
            ;;
        msdos)
            if command -v mkfs.msdos >/dev/null 2>&1; then
                mkfs.msdos -n "$VOLUME_LABEL" "$OUTPUT_TARGET" >/dev/null 2>&1
            elif command -v newfs_msdos >/dev/null 2>&1; then
                newfs_msdos -L "$VOLUME_LABEL" "$OUTPUT_TARGET" >/dev/null 2>&1
            else
                error "No DOS formatting tool available"
            fi
            ;;
        hfs)
            if command -v newfs_hfs >/dev/null 2>&1; then
                newfs_hfs -v "$VOLUME_LABEL" "$OUTPUT_TARGET" >/dev/null 2>&1
            elif command -v hformat >/dev/null 2>&1; then
                hformat -l "$VOLUME_LABEL" "$OUTPUT_TARGET" >/dev/null 2>&1
            else
                error "No HFS formatting tool available"
            fi
            ;;
    esac

    info "Filesystem created successfully"
}

# Mount the floppy image
mount_floppy() {
    info "Mounting floppy image..."

    if [ "$(uname -s)" = "Darwin" ]; then
        # macOS: use hdiutil
        hdiutil attach "$OUTPUT_TARGET" -mountpoint "$TEMP_MOUNT" >/dev/null 2>&1
    else
        # Linux: use mount with loop device
        if [ "$OUTPUT_TYPE" = "image" ]; then
            mount -o loop "$OUTPUT_TARGET" "$TEMP_MOUNT" 2>/dev/null || \
                error "Failed to mount image (may need root/sudo)"
        else
            mount "$DEVICE" "$TEMP_MOUNT" 2>/dev/null || \
                error "Failed to mount device (may need root/sudo)"
        fi
    fi

    verbose "Mounted at: $TEMP_MOUNT"
}

# Copy drivers to floppy
copy_drivers() {
    info "Copying drivers to floppy..."

    # Create standard driver directory structure
    # RhapsodiOS boot loader looks in /usr/Drivers/
    mkdir -p "$TEMP_MOUNT/usr/Drivers"
    verbose "Created /usr/Drivers directory"

    # Copy driver files if any exist
    local copied=0
    if [ -d "$DRIVERS_DIR" ]; then
        # Copy .driver and .bundle files/directories
        for driver in "$DRIVERS_DIR"/*.driver "$DRIVERS_DIR"/*.bundle; do
            if [ -e "$driver" ]; then
                cp -R "$driver" "$TEMP_MOUNT/usr/Drivers/"
                local name=$(basename "$driver")
                verbose "Copied: $name"
                copied=$((copied + 1))
            fi
        done

        # Also copy any subdirectories that might contain drivers
        for subdir in "$DRIVERS_DIR"/*/; do
            if [ -d "$subdir" ]; then
                local dirname=$(basename "$subdir")
                # Skip if it's a .driver or .bundle (already copied above)
                if [[ ! "$dirname" =~ \.(driver|bundle)$ ]]; then
                    cp -R "$subdir" "$TEMP_MOUNT/usr/Drivers/"
                    verbose "Copied directory: $dirname"
                    copied=$((copied + 1))
                fi
            fi
        done
    fi

    if [ "$copied" -eq 0 ]; then
        warn "No drivers copied (empty driver directory)"
        echo "Driver floppy template created." > "$TEMP_MOUNT/usr/Drivers/README.txt"
        echo "Add driver bundles (.driver or .bundle) to this directory." >> "$TEMP_MOUNT/usr/Drivers/README.txt"
    else
        info "Copied $copied driver(s)"
    fi

    # Create a driver list file for the boot loader
    if [ -d "$TEMP_MOUNT/usr/Drivers" ]; then
        find "$TEMP_MOUNT/usr/Drivers" -type d \( -name "*.driver" -o -name "*.bundle" \) > "$TEMP_MOUNT/usr/Drivers/.drivers.list" 2>/dev/null || true
    fi
}

# Unmount the floppy
unmount_floppy() {
    info "Unmounting floppy..."

    if [ "$(uname -s)" = "Darwin" ]; then
        hdiutil detach "$TEMP_MOUNT" >/dev/null 2>&1
    else
        umount "$TEMP_MOUNT" 2>/dev/null
    fi

    verbose "Unmounted successfully"
}

# Generate summary
generate_info() {
    info "=== Driver Floppy Creation Summary ==="
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

    echo "Filesystem:      $FS_TYPE"
    echo "Volume Label:    $VOLUME_LABEL"

    # Count drivers on the floppy
    if [ "$OUTPUT_TYPE" = "image" ] && [ "$(uname -s)" = "Darwin" ]; then
        # Try to mount and count (macOS)
        local mount_point=$(mktemp -d /tmp/count-drivers.XXXXXX)
        if hdiutil attach "$OUTPUT_TARGET" -mountpoint "$mount_point" >/dev/null 2>&1; then
            local driver_count=$(find "$mount_point/usr/Drivers" -type d \( -name "*.driver" -o -name "*.bundle" \) 2>/dev/null | wc -l | tr -d ' ')
            echo "Drivers:         $driver_count"
            hdiutil detach "$mount_point" >/dev/null 2>&1
            rmdir "$mount_point"
        fi
    fi

    echo ""
    info "=== Next Steps ==="
    echo "1. During RhapsodiOS boot, the boot loader will prompt for driver disk"
    echo "2. Insert this driver floppy when prompted"
    echo "3. The boot loader will scan /usr/Drivers/ and load needed drivers"
    echo ""

    if [ "$OUTPUT_TYPE" = "image" ]; then
        echo "Write to floppy with:"
        echo "  Linux: dd if=$OUTPUT_TARGET of=/dev/fd0 bs=512"
        echo "  macOS: sudo dd if=$OUTPUT_TARGET of=/dev/rdiskN bs=512"
        echo "         (Find diskN with: diskutil list)"
    fi

    echo ""
}

# Main execution
main() {
    info "RhapsodiOS Driver Floppy Creator"
    echo ""

    check_requirements
    verify_drivers
    create_floppy_base
    create_filesystem
    mount_floppy
    copy_drivers
    unmount_floppy
    generate_info

    info "Driver floppy created successfully!"
}

# Run main function
main
