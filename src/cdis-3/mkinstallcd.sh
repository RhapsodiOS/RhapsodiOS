#!/bin/bash

##
# mkinstallcd.sh - Create a bootable RhapsodiOS installation CD-ROM
#
# This script creates a bootable ISO image for installing RhapsodiOS on
# x86 and PowerPC systems. It packages the boot loader, installer tools,
# base system tarball, and optional packages into a bootable CD image.
#
# Usage: ./mkinstallcd.sh [options]
#
# Options:
#   -o OUTPUT    Output ISO file (default: rhapsodios-install.iso)
#   -s SRCROOT   Source root directory (default: .)
#   -d DSTROOT   Destination root for installed files (default: ./iso_staging)
#   -i IMAGE     Base system image tarball (default: auto-detect or prompt)
#   -p PKGDIR    Additional packages directory (optional)
#   -b           Build boot loader and installer tools first
#   -c           Clean staging directory before starting
#   -v           Verbose output
#   -h           Show this help
#
# Requirements:
#   - mkisofs or genisoimage (for creating ISO image)
#   - Built boot loader (boot0, boot1, boot2) in boot-2/i386
#   - Built installer tools in cdis-3
#   - Base system tarball (image.tar.gz)
#
# Example:
#   ./mkinstallcd.sh -b -o rhapsodi-dr2.iso -i /path/to/base-system.tar.gz
##

set -e  # Exit on error

# Default values
OUTPUT_ISO="rhapsodios-install.iso"
SRCROOT="$(cd "$(dirname "$0")" && pwd)"
STAGING_DIR="${SRCROOT}/iso_staging"
IMAGE_TARBALL=""
PACKAGES_DIR=""
BUILD_FIRST=0
CLEAN_STAGING=0
VERBOSE=0

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
    sed -n '3,28p' "$0" | sed 's/^# \?//'
    exit 1
}

# Parse command line arguments
while getopts "o:s:d:i:p:bcvh" opt; do
    case $opt in
        o) OUTPUT_ISO="$OPTARG" ;;
        s) SRCROOT="$OPTARG" ;;
        d) STAGING_DIR="$OPTARG" ;;
        i) IMAGE_TARBALL="$OPTARG" ;;
        p) PACKAGES_DIR="$OPTARG" ;;
        b) BUILD_FIRST=1 ;;
        c) CLEAN_STAGING=1 ;;
        v) VERBOSE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check for required tools
check_requirements() {
    info "Checking requirements..."

    if command -v mkisofs >/dev/null 2>&1; then
        MKISO_CMD="mkisofs"
    elif command -v genisoimage >/dev/null 2>&1; then
        MKISO_CMD="genisoimage"
    else
        error "Neither mkisofs nor genisoimage found. Please install cdrtools or genisoimage."
    fi
    verbose "Using ISO creation tool: $MKISO_CMD"

    # Check for gnutar
    if ! command -v gnutar >/dev/null 2>&1 && ! command -v tar >/dev/null 2>&1; then
        error "tar/gnutar not found"
    fi
}

# Build boot loader and installer tools
build_components() {
    if [ "$BUILD_FIRST" -eq 1 ]; then
        info "Building boot loader..."
        cd "${SRCROOT}/boot-2/i386"
        if [ -f Makefile ]; then
            make DSTROOT="${STAGING_DIR}" install_i386 || warn "Boot loader build failed, using existing files"
        else
            warn "No Makefile found in boot-2/i386, skipping build"
        fi

        info "Building installer tools..."
        cd "${SRCROOT}/cdis-3"
        if [ -f Makefile ]; then
            make DSTROOT="${STAGING_DIR}" install || warn "Installer tools build failed, using existing files"
        else
            warn "No Makefile found in cdis-3, skipping build"
        fi

        cd "${SRCROOT}"
    fi
}

# Create staging directory structure
create_staging_structure() {
    info "Creating staging directory structure..."

    if [ "$CLEAN_STAGING" -eq 1 ] && [ -d "$STAGING_DIR" ]; then
        warn "Cleaning existing staging directory: $STAGING_DIR"
        rm -rf "$STAGING_DIR"
    fi

    # Create required directories
    mkdir -p "${STAGING_DIR}/System/Installation/CDIS"
    mkdir -p "${STAGING_DIR}/System/Installation/Data"
    mkdir -p "${STAGING_DIR}/System/Installation/Packages"
    mkdir -p "${STAGING_DIR}/usr/standalone/i386"
    mkdir -p "${STAGING_DIR}/private/etc"

    verbose "Created directory structure in $STAGING_DIR"
}

# Copy boot loader files
copy_bootloader() {
    info "Copying boot loader files..."

    local BOOT_SOURCE="${SRCROOT}/boot-2/i386"
    local BOOT_DEST="${STAGING_DIR}/usr/standalone/i386"

    # Check for built boot files
    if [ -f "${BOOT_SOURCE}/boot0/boot0" ]; then
        cp "${BOOT_SOURCE}/boot0/boot0" "${BOOT_DEST}/"
        verbose "Copied boot0"
    else
        warn "boot0 not found at ${BOOT_SOURCE}/boot0/boot0"
    fi

    if [ -f "${BOOT_SOURCE}/boot1/boot1" ]; then
        cp "${BOOT_SOURCE}/boot1/boot1" "${BOOT_DEST}/"
        cp "${BOOT_SOURCE}/boot1/boot1f" "${BOOT_DEST}/" 2>/dev/null || true
        verbose "Copied boot1"
    else
        warn "boot1 not found at ${BOOT_SOURCE}/boot1/boot1"
    fi

    if [ -f "${BOOT_SOURCE}/boot2/boot" ]; then
        cp "${BOOT_SOURCE}/boot2/boot" "${BOOT_DEST}/"
        verbose "Copied boot2 (boot)"
    else
        warn "boot2 not found at ${BOOT_SOURCE}/boot2/boot"
    fi

    # Copy language files and bitmaps if present
    if [ -d "${BOOT_SOURCE}/strings" ]; then
        cp -R "${BOOT_SOURCE}/strings/"*.lproj "${BOOT_DEST}/" 2>/dev/null || true
        verbose "Copied language files"
    fi

    if [ -d "${BOOT_SOURCE}/util" ]; then
        cp "${BOOT_SOURCE}/util/"*.bitmap "${BOOT_DEST}/" 2>/dev/null || true
        verbose "Copied boot bitmaps"
    fi
}

# Copy installer tools
copy_installer() {
    info "Copying installer tools..."

    local CDIS_SOURCE="${SRCROOT}/cdis-3"
    local CDIS_DEST="${STAGING_DIR}/System/Installation/CDIS"

    # Copy main installer script
    if [ -f "${CDIS_SOURCE}/rc.cdrom" ]; then
        cp "${CDIS_SOURCE}/rc.cdrom" "${STAGING_DIR}/private/etc/"
        chmod +x "${STAGING_DIR}/private/etc/rc.cdrom"
        verbose "Copied rc.cdrom"
    else
        error "rc.cdrom not found at ${CDIS_SOURCE}/rc.cdrom"
    fi

    # Copy platform-specific scripts
    [ -f "${CDIS_SOURCE}/rc.cdrom.PPC" ] && cp "${CDIS_SOURCE}/rc.cdrom.PPC" "${STAGING_DIR}/private/etc/"
    [ -f "${CDIS_SOURCE}/rc.cdrom.x86" ] && cp "${CDIS_SOURCE}/rc.cdrom.x86" "${STAGING_DIR}/private/etc/"

    # Copy language resources
    for lang in English French German Italian Spanish Swedish; do
        if [ -d "${CDIS_SOURCE}/${lang}.lproj" ]; then
            mkdir -p "${CDIS_DEST}/${lang}.lproj"
            cp -R "${CDIS_SOURCE}/${lang}.lproj/"* "${CDIS_DEST}/${lang}.lproj/"
            verbose "Copied ${lang} resources"
        fi
    done

    # Copy installer tools
    cp "${CDIS_SOURCE}/fixdisk" "${CDIS_DEST}/" 2>/dev/null || true
    cp "${CDIS_SOURCE}/"*.pl "${CDIS_DEST}/" 2>/dev/null || true

    # Copy built installer binaries (if present)
    for tool in getpath findroot checkflop pickdisk gc slamloaderbits sgmove popconsole ditto; do
        local tool_path="${CDIS_SOURCE}/${tool}.tproj/${tool}"
        if [ -f "$tool_path" ]; then
            cp "$tool_path" "${CDIS_DEST}/"
            chmod +x "${CDIS_DEST}/${tool}"
            verbose "Copied tool: $tool"
        else
            warn "Tool not found: $tool (${tool_path})"
        fi
    done

    # Copy install_tools directory
    if [ -d "${CDIS_SOURCE}/install_tools" ]; then
        cp -R "${CDIS_SOURCE}/install_tools" "${CDIS_DEST}/"
        verbose "Copied install_tools directory"
    fi
}

# Copy or prompt for base system image
copy_base_image() {
    info "Setting up base system image..."

    local IMAGE_DEST="${STAGING_DIR}/System/Installation/Data/image.tar.gz"

    if [ -n "$IMAGE_TARBALL" ]; then
        if [ -f "$IMAGE_TARBALL" ]; then
            info "Copying base system image: $IMAGE_TARBALL"
            cp "$IMAGE_TARBALL" "$IMAGE_DEST"

            # Verify it's a valid tarball
            if ! gnutar -tzf "$IMAGE_DEST" >/dev/null 2>&1 && ! tar -tzf "$IMAGE_DEST" >/dev/null 2>&1; then
                error "Invalid tarball: $IMAGE_DEST"
            fi

            local size=$(du -h "$IMAGE_DEST" | cut -f1)
            info "Base system image size: $size"
        else
            error "Image tarball not found: $IMAGE_TARBALL"
        fi
    else
        warn "No base system image specified."
        warn "The installer expects a tarball at: /System/Installation/Data/image.tar.gz"
        warn "This tarball should contain the complete RhapsodiOS base system."
        warn ""
        warn "You can specify it with: -i /path/to/image.tar.gz"
        warn ""
        warn "Creating placeholder file..."

        # Create a small placeholder
        echo "PLACEHOLDER - Replace with actual base system tarball" > "${IMAGE_DEST}.placeholder"
        warn "Created: ${IMAGE_DEST}.placeholder"
        warn "CD will not be functional without a real base system image!"
    fi
}

# Copy optional packages
copy_packages() {
    if [ -n "$PACKAGES_DIR" ] && [ -d "$PACKAGES_DIR" ]; then
        info "Copying optional packages from: $PACKAGES_DIR"
        cp -R "$PACKAGES_DIR/"*.pkg "${STAGING_DIR}/System/Installation/Packages/" 2>/dev/null || true

        local pkg_count=$(find "${STAGING_DIR}/System/Installation/Packages/" -name "*.pkg" -type d | wc -l)
        info "Copied $pkg_count package(s)"
    else
        verbose "No packages directory specified or found"
    fi
}

# Create El Torito boot catalog and bootable ISO
create_bootable_iso() {
    info "Creating bootable ISO image: $OUTPUT_ISO"

    # The boot image needs to be boot1 (512 bytes, floppy emulation)
    local BOOT_IMAGE="${STAGING_DIR}/usr/standalone/i386/boot1"

    if [ ! -f "$BOOT_IMAGE" ]; then
        error "Boot image not found: $BOOT_IMAGE"
    fi

    # Verify boot image size (should be 512 bytes for boot1)
    local boot_size=$(stat -f%z "$BOOT_IMAGE" 2>/dev/null || stat -c%s "$BOOT_IMAGE" 2>/dev/null)
    if [ "$boot_size" -ne 512 ]; then
        warn "Boot image size is $boot_size bytes (expected 512 bytes)"
    fi

    # Create the ISO with El Torito boot support
    info "Running $MKISO_CMD..."

    $MKISO_CMD \
        -o "$OUTPUT_ISO" \
        -V "RhapsodiOS Install" \
        -b "usr/standalone/i386/boot1" \
        -c "boot.catalog" \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -r -J -l \
        -hide boot.catalog \
        "$STAGING_DIR" || error "ISO creation failed"

    if [ -f "$OUTPUT_ISO" ]; then
        local iso_size=$(du -h "$OUTPUT_ISO" | cut -f1)
        info "Successfully created ISO: $OUTPUT_ISO ($iso_size)"
    else
        error "ISO creation failed - file not created"
    fi
}

# Create hybrid MBR for USB boot support (optional enhancement)
make_hybrid() {
    if command -v isohybrid >/dev/null 2>&1; then
        info "Making ISO hybrid (USB bootable)..."
        isohybrid "$OUTPUT_ISO" && info "ISO is now USB bootable" || warn "isohybrid failed"
    else
        verbose "isohybrid not found, skipping hybrid creation"
    fi
}

# Generate a summary report
generate_report() {
    info "=== Installation CD Creation Summary ==="
    echo ""
    echo "Output ISO:      $OUTPUT_ISO"
    echo "Staging Dir:     $STAGING_DIR"
    echo ""

    if [ -f "${STAGING_DIR}/System/Installation/Data/image.tar.gz" ]; then
        echo "Base System:     $(du -h "${STAGING_DIR}/System/Installation/Data/image.tar.gz" | cut -f1)"
    else
        echo "Base System:     NOT PRESENT (placeholder only)"
    fi

    local pkg_count=$(find "${STAGING_DIR}/System/Installation/Packages/" -name "*.pkg" -type d 2>/dev/null | wc -l)
    echo "Packages:        $pkg_count"

    echo ""
    echo "Boot files:"
    [ -f "${STAGING_DIR}/usr/standalone/i386/boot0" ] && echo "  ✓ boot0" || echo "  ✗ boot0"
    [ -f "${STAGING_DIR}/usr/standalone/i386/boot1" ] && echo "  ✓ boot1" || echo "  ✗ boot1"
    [ -f "${STAGING_DIR}/usr/standalone/i386/boot" ] && echo "  ✓ boot2" || echo "  ✗ boot2"

    echo ""
    echo "Installer:"
    [ -f "${STAGING_DIR}/private/etc/rc.cdrom" ] && echo "  ✓ rc.cdrom" || echo "  ✗ rc.cdrom"

    local tool_count=$(find "${STAGING_DIR}/System/Installation/CDIS/" -type f -perm +111 2>/dev/null | wc -l)
    echo "  Tools: $tool_count"

    echo ""
    if [ -f "$OUTPUT_ISO" ]; then
        echo "ISO Size:        $(du -h "$OUTPUT_ISO" | cut -f1)"
        echo "ISO MD5:         $(md5 -q "$OUTPUT_ISO" 2>/dev/null || md5sum "$OUTPUT_ISO" 2>/dev/null | cut -d' ' -f1)"
    fi

    echo ""
    info "=== Next Steps ==="
    echo "1. Test the ISO in a VM (QEMU, VirtualBox, VMware)"
    echo "2. Burn to CD-R with: cdrecord -v dev=/dev/cdrom $OUTPUT_ISO"
    echo "3. Or write to USB: dd if=$OUTPUT_ISO of=/dev/sdX bs=4M"
    echo ""
}

# Main execution
main() {
    info "RhapsodiOS Installation CD Creator"
    echo ""

    check_requirements
    build_components
    create_staging_structure
    copy_bootloader
    copy_installer
    copy_base_image
    copy_packages
    create_bootable_iso
    make_hybrid
    generate_report

    info "Done!"
}

# Run main function
main
