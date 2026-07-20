# RhapsodiOS Installation CD Creation

## Overview

The `mkinstallcd.sh` script creates a bootable ISO image for installing RhapsodiOS on x86 and PowerPC systems. It packages the boot loader, installer tools, base system tarball, and optional packages into an El Torito bootable CD image.

## Requirements

### Software Dependencies

1. **ISO Creation Tool** (one of):
   - `mkisofs` (from cdrtools)
   - `genisoimage` (alternative implementation)

   Install on macOS:
   ```bash
   brew install cdrtools
   ```

   Install on Linux:
   ```bash
   # Debian/Ubuntu
   sudo apt-get install genisoimage

   # RHEL/CentOS
   sudo yum install genisoimage
   ```

2. **Optional Tools**:
   - `isohybrid` (from syslinux) - for USB bootable hybrid images
   - `tar`/`gnutar` - for verifying base system tarball

### Build Requirements

Before creating the ISO, you need to build:

1. **Boot Loader** (boot-2/i386):
   ```bash
   cd boot-2/i386
   make DSTROOT=/tmp/rhapsodi_build install_i386
   ```

   This builds:
   - `boot0` - Master Boot Record (512 bytes)
   - `boot1` - Stage 1 boot loader (512 bytes)
   - `boot2` (boot) - Stage 2 boot loader (~45KB)

2. **Installer Tools** (cdis-3):
   ```bash
   cd cdis-3
   make DSTROOT=/tmp/rhapsodi_build install
   ```

   This builds installer utilities:
   - `getpath`, `findroot`, `checkflop`, `pickdisk`
   - `gc`, `slamloaderbits`, `sgmove`, `popconsole`, `ditto`

3. **Base System Tarball**:
   You need to create `image.tar.gz` containing the complete RhapsodiOS base system:
   ```bash
   # Example: create from a working installation
   cd /path/to/rhapsodios/root
   tar -czf image.tar.gz \
       System/ \
       Library/ \
       usr/ \
       bin/ \
       sbin/ \
       etc/ \
       var/ \
       private/ \
       dev/
   ```

## Usage

### Basic Usage

Create an ISO with default settings:

```bash
./mkinstallcd.sh -i /path/to/image.tar.gz
```

This creates `rhapsodios-install.iso` in the current directory.

### Full Options

```bash
./mkinstallcd.sh [options]

Options:
  -o OUTPUT    Output ISO file (default: rhapsodios-install.iso)
  -s SRCROOT   Source root directory (default: current directory)
  -d DSTROOT   Destination root for staging (default: ./iso_staging)
  -i IMAGE     Base system image tarball (REQUIRED)
  -p PKGDIR    Additional packages directory (optional)
  -b           Build boot loader and installer tools first
  -c           Clean staging directory before starting
  -v           Verbose output
  -h           Show this help
```

### Example: Complete Build

Build everything from scratch and create ISO:

```bash
./mkinstallcd.sh \
    -b \
    -c \
    -v \
    -i /path/to/image.tar.gz \
    -p /path/to/packages \
    -o rhapsodios-dr2-install.iso
```

This will:
1. Clean any existing staging directory (`-c`)
2. Build boot loader and installer tools (`-b`)
3. Copy base system image (`-i`)
4. Include additional packages (`-p`)
5. Show verbose output (`-v`)
6. Create output ISO (`-o`)

## ISO Structure

The generated ISO has the following structure:

```
/
├── usr/
│   └── standalone/
│       └── i386/
│           ├── boot0                    # MBR boot code
│           ├── boot1                    # Stage 1 loader (El Torito boot image)
│           ├── boot                     # Stage 2 loader (boot2)
│           ├── English.lproj/           # Localized strings
│           ├── French.lproj/
│           └── *.bitmap                 # Boot splash screens
├── System/
│   └── Installation/
│       ├── CDIS/
│       │   ├── rc.cdrom                 # Main installer script (symlink)
│       │   ├── rc.cdrom.PPC             # PowerPC-specific code
│       │   ├── rc.cdrom.x86             # x86-specific code
│       │   ├── English.lproj/           # Installer UI strings
│       │   ├── fixdisk                  # Disk preparation script
│       │   ├── ditto                    # File copying utility
│       │   ├── getpath, findroot, etc.  # Installer utilities
│       │   └── install_tools/
│       │       ├── installer.sh         # Package installer
│       │       └── package              # Package manager
│       ├── Data/
│       │   └── image.tar.gz             # Base system tarball
│       └── Packages/
│           └── *.pkg                    # Optional packages
└── private/
    └── etc/
        ├── rc.cdrom                     # Main installer script
        ├── rc.cdrom.PPC
        └── rc.cdrom.x86
```

## Boot Process

1. **BIOS Stage**: BIOS loads El Torito boot image (`boot1`, 512 bytes)
2. **Stage 1**: `boot1` loads `boot` (boot2) from CD
3. **Stage 2**: `boot2` displays boot menu, loads kernel
4. **Kernel Boot**: Kernel detects CD-ROM installation
5. **Installer Launch**: `/etc/rc.boot` detects `/System/Installation` and launches `/etc/rc.cdrom`
6. **Installation**: Perl-based `rc.cdrom` handles:
   - Language selection
   - Disk partitioning
   - Base system extraction from `image.tar.gz`
   - System configuration
   - Optional package installation

## Testing the ISO

### QEMU

```bash
# x86 test
qemu-system-i386 \
    -cdrom rhapsodios-install.iso \
    -boot d \
    -m 512 \
    -hda disk.img

# Create disk image first
qemu-img create -f qcow2 disk.img 2G
```

### VirtualBox

1. Create new VM (Other/Other Unix)
2. Attach ISO to CD-ROM drive
3. Set boot order to CD-ROM first
4. Start VM

### VMware Fusion/Workstation

1. Create new VM (Other)
2. Mount ISO as CD-ROM
3. Power on

### Physical Media

#### Burn to CD-R

Using `cdrecord` (Linux/macOS):
```bash
# Find your CD writer
cdrecord -scanbus

# Burn ISO
cdrecord -v dev=/dev/cdrom speed=4 rhapsodios-install.iso
```

Using macOS Disk Utility:
1. Open Disk Utility
2. File → Open Disk Image → Select ISO
3. Right-click mounted image → Burn to Disc

#### Create Bootable USB

```bash
# Linux
sudo dd if=rhapsodios-install.iso of=/dev/sdX bs=4M status=progress
sync

# macOS
diskutil list
diskutil unmountDisk /dev/diskX
sudo dd if=rhapsodios-install.iso of=/dev/rdiskX bs=4m
diskutil eject /dev/diskX
```

**Note**: USB booting requires hybrid ISO support (created with `isohybrid`).

## Troubleshooting

### ISO Creation Fails

**Error**: "mkisofs: command not found"
- **Solution**: Install cdrtools or genisoimage (see Requirements)

**Error**: "Boot image not found"
- **Solution**: Build boot loader first with `-b` option or manually build in boot-2/i386

**Error**: "Invalid tarball"
- **Solution**: Verify your base system tarball is valid:
  ```bash
  tar -tzf image.tar.gz | head
  ```

### Boot Fails

**Symptom**: "Boot Error" or system hangs at boot
- **Cause**: boot1 not properly configured as El Torito boot image
- **Solution**: Verify boot1 is exactly 512 bytes:
  ```bash
  ls -l boot-2/i386/boot1/boot1
  # Should show: -rwxr-xr-x ... 512 ... boot1
  ```

**Symptom**: Boots but cannot find installer
- **Cause**: Missing or incorrect `/etc/rc.cdrom` script
- **Solution**: Verify rc.cdrom is executable and present in staging directory

**Symptom**: Installer starts but cannot extract base system
- **Cause**: Missing or corrupted `image.tar.gz`
- **Solution**: Check `/System/Installation/Data/image.tar.gz` exists in ISO

### Installation Fails

**Error**: "Cannot find installation target"
- **Cause**: No suitable disk found or disk needs partitioning
- **Solution**: Check disk is properly connected and not in use

**Error**: "tar extraction failed"
- **Cause**: Corrupted base system tarball or insufficient disk space
- **Solution**: Verify tarball integrity and target disk has enough space (minimum 2GB)

## Advanced Customization

### Custom Boot Splash

Replace boot bitmaps in `boot-2/i386/util/*.bitmap` with custom 8-bit images.

### Pre-configured Installation

Modify `cdis-3/rc.cdrom` to set default values:
```perl
# Skip language selection
$info{'language'} = 'English';

# Auto-partition (dangerous!)
$info{'interactive'} = 0;
```

### Additional Packages

Place `.pkg` directories in packages directory:
```bash
mkdir -p packages
cp -R MyApp.pkg packages/
./mkinstallcd.sh -p packages -i image.tar.gz
```

Packages will be available in the installer under "Custom Installation".

### Hybrid Boot (BIOS + UEFI)

For modern systems with UEFI support (future enhancement):
```bash
# After creating ISO
isohybrid --uefi rhapsodios-install.iso
```

**Note**: RhapsodiOS boot loader currently only supports BIOS booting.

## File Size Considerations

Typical sizes:
- Boot loader: ~50 KB
- Installer tools: ~2-5 MB
- Base system: 200-800 MB (depends on included components)
- Total ISO: 250-850 MB

CD-ROM capacity:
- CD-R: 650-700 MB
- Mini CD-R: 180-210 MB

For systems too large for CD, consider:
1. Splitting into multiple CDs (base + additional packages)
2. Using DVD-ROM (4.7 GB)
3. Network installation from CD boot + network packages

## Implementation Notes

### El Torito Bootable CD

The ISO uses El Torito "no emulation" mode:
- Boot image: `boot1` (512 bytes)
- Boot catalog: Hidden file created by mkisofs
- Load size: 4 sectors (2048 bytes)
- Boot info table: Injected by mkisofs for boot2 to locate itself

### Boot Sequence

```
BIOS → El Torito → boot1 (512b) → boot2 (~45KB) → kernel → installer
```

### Platform Detection

The installer (`rc.cdrom`) automatically detects:
- Architecture (x86 vs PowerPC)
- Available disks
- CD-ROM mount point
- Language preference

Platform-specific code is in:
- `rc.cdrom.x86` - x86 partitioning, boot loader installation
- `rc.cdrom.PPC` - PowerPC Open Firmware, partition maps

## References

- El Torito Bootable CD-ROM Specification
- mkisofs/genisoimage documentation
- RhapsodiOS boot-2 documentation
- cdis-3/rc.cdrom source code

## Support

For issues with:
- Boot loader: Check boot-2/i386/README
- Installer: Check cdis-3/rc.cdrom comments
- ISO creation: Run with `-v` for verbose output

## License

This script is part of RhapsodiOS and follows the project's licensing terms (see APPLE_LICENSE).
