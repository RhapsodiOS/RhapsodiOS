# RhapsodiOS Floppy Creation Scripts

This directory contains scripts for creating bootable boot floppies and driver floppies for RhapsodiOS installation and troubleshooting.

## Scripts

### mkbootfloppy.sh
Creates a bootable 1.44MB boot floppy containing the RhapsodiOS boot loader (boot1f + boot2). This floppy can be used to boot a RhapsodiOS system when the hard disk boot loader is not available, or for initial installation.

### mkdriverfloppy.sh
Creates a driver floppy containing kernel extensions (.driver or .bundle files) that can be loaded during boot for additional hardware support not included in the base system.

## Requirements

### Boot Floppy Requirements
- Built boot loader components:
  - `boot-2/i386/boot1/boot1f` (512-byte floppy boot sector)
  - `boot-2/i386/boot2/boot` (second-stage boot loader)
- Standard Unix tools: `dd`, `stat`
- Optional: `md5sum` or `md5` for checksums

### Driver Floppy Requirements
- Driver files (.driver, .bundle, or directories containing driver bundles)
- Filesystem tools (at least one):
  - **UFS**: `newfs_ufs` or `mkfs.ufs` (native RhapsodiOS filesystem)
  - **DOS/FAT**: `mkfs.msdos` or `newfs_msdos` (most compatible)
  - **HFS**: `hformat` (from hfsutils) or `newfs_hfs` (for macOS compatibility)
- Mounting tools:
  - macOS: `hdiutil` (built-in)
  - Linux: `mount` with loop device support (usually built-in)

## Usage Examples

### Creating a Boot Floppy

1. **Build the boot loader first**:
```bash
cd boot-2/i386
make
cd ../..
```

2. **Create a boot floppy image**:
```bash
./mkbootfloppy.sh -o boot.img
```

3. **Build and create in one step**:
```bash
./mkbootfloppy.sh -b -o rhapsodi-boot.img
```

4. **Write directly to a floppy device** (requires root/sudo):
```bash
# Linux
sudo ./mkbootfloppy.sh -d /dev/fd0

# macOS (find device with: diskutil list)
sudo ./mkbootfloppy.sh -d /dev/rdisk2
```

5. **Create with verbose output**:
```bash
./mkbootfloppy.sh -v -o boot.img
```

### Creating a Driver Floppy

1. **Prepare a directory with drivers**:
```bash
mkdir -p drivers
# Copy your .driver or .bundle files to the drivers directory
cp path/to/MyDriver.driver drivers/
```

2. **Create a driver floppy image with UFS filesystem** (native):
```bash
./mkdriverfloppy.sh -i drivers -o drivers.img
```

3. **Create a driver floppy with DOS filesystem** (most compatible):
```bash
./mkdriverfloppy.sh -t msdos -i drivers -o drivers-dos.img
```

4. **Create with custom volume label**:
```bash
./mkdriverfloppy.sh -l "MyDrivers" -i drivers -o drivers.img
```

5. **Write directly to a floppy device**:
```bash
# Linux
sudo ./mkdriverfloppy.sh -i drivers -d /dev/fd0

# macOS
sudo ./mkdriverfloppy.sh -i drivers -d /dev/rdisk2
```

## Testing in Virtual Machines

### QEMU
```bash
# Test boot floppy
qemu-system-i386 -fda boot.img

# Test with both boot and driver floppy
qemu-system-i386 -fda boot.img -fdb drivers.img

# Test boot floppy with hard disk
qemu-system-i386 -fda boot.img -hda rhapsodi.img
```

### VirtualBox
1. Create or open a VM
2. Go to Settings → Storage
3. Add a floppy controller
4. Attach the floppy image (.img file)
5. Set boot order to start with floppy

### VMware
1. Edit VM settings
2. Add a floppy drive
3. Select "Use floppy image file"
4. Browse to your .img file

## Writing to Physical Floppies

### Linux
```bash
# Write boot floppy
sudo dd if=boot.img of=/dev/fd0 bs=512 status=progress

# Write driver floppy
sudo dd if=drivers.img of=/dev/fd0 bs=512 status=progress
```

### macOS
```bash
# Find the floppy device
diskutil list

# Unmount (but don't eject)
diskutil unmountDisk /dev/diskN

# Write the image
sudo dd if=boot.img of=/dev/rdiskN bs=512

# Eject when done
diskutil eject /dev/diskN
```

### Windows (via WSL or Cygwin)
```bash
# From WSL/Cygwin (may require admin privileges)
dd if=boot.img of=/dev/fd0 bs=512
```

## Boot Process with Floppies

### Standard Boot Sequence

1. **Boot from floppy**: Insert boot floppy and power on
2. **Boot loader starts**: boot1f loads boot2 from the floppy
3. **Driver prompt** (optional): If configured, boot loader prompts for driver disk
4. **Insert driver floppy**: Replace boot floppy with driver floppy when prompted
5. **Drivers load**: Boot loader scans `/usr/Drivers/` and loads needed drivers
6. **Kernel boots**: System continues booting from hard disk

### Configuring Driver Disk Prompts

The boot loader checks for these keys in `/etc/boot.defaults` or system configuration:

- `"Prompt For Driver Disk"` - Set to "Yes" to enable prompting
- `"Driver Disk Prompts"` - Number of times to prompt (default: 1)
- `"Ask For Drivers"` - Alternative key for driver prompting

## Filesystem Recommendations

### Boot Floppy
- **No filesystem needed**: Boot floppy contains only the boot loader in the boot cylinder (sectors 0-35)
- The rest of the floppy is unused

### Driver Floppy
- **UFS** (recommended): Native RhapsodiOS filesystem, best compatibility
- **DOS/FAT** (most compatible): Works across platforms, easier to create/modify on other systems
- **HFS** (macOS only): For creating drivers on macOS, but limited RhapsodiOS support

## Directory Structure

### Boot Floppy Layout
```
Sector 0:       boot1f (512 bytes) - First-stage boot loader
Sectors 1-35:   boot2 (boot) - Second-stage boot loader
Sectors 36+:    Unused (reserved for configuration/data)
```

### Driver Floppy Layout
```
/
└── usr/
    └── Drivers/
        ├── Driver1.driver/
        ├── Driver2.bundle/
        └── .drivers.list (auto-generated)
```

## Troubleshooting

### Boot Floppy Issues

**Problem**: "boot1f not found"
- **Solution**: Build the boot loader first with `cd boot-2/i386 && make`

**Problem**: "boot1f size is not 512 bytes"
- **Solution**: Rebuild boot1f - it must be exactly one sector (512 bytes)

**Problem**: Boot floppy doesn't boot
- **Solution**: 
  - Verify BIOS boot order (floppy first)
  - Test in a VM first
  - Try recreating the floppy
  - Check for bad floppy media

### Driver Floppy Issues

**Problem**: "No drivers found"
- **Solution**: Boot loader looks in `/usr/Drivers/` - ensure drivers are in this directory

**Problem**: Drivers not loading
- **Solution**:
  - Check driver file extensions (.driver or .bundle)
  - Verify filesystem is readable (UFS or FAT recommended)
  - Check driver compatibility with your RhapsodiOS version

**Problem**: "Filesystem tools not found"
- **Solution**: Install required packages:
  - Debian/Ubuntu: `sudo apt-get install ufsutils mtools hfsutils`
  - macOS: Tools are built-in for UFS and HFS
  - For DOS filesystem: `brew install mtools` (macOS) or use built-in tools

## Advanced Usage

### Creating a Multi-Boot Setup

You can combine both boot and driver content on a single bootable floppy by modifying the boot floppy script to add a filesystem in the data area (sectors 36+) and copying drivers there.

### Extracting Files from Driver Floppy

**Linux**:
```bash
mkdir mount_point
sudo mount -o loop drivers.img mount_point
# Copy files
sudo umount mount_point
```

**macOS**:
```bash
hdiutil attach drivers.img
# Access files at /Volumes/RhapsodiDrivers
hdiutil detach /Volumes/RhapsodiDrivers
```

### Adding Drivers to Existing Floppy

```bash
# Mount the floppy image
sudo mount -o loop drivers.img /mnt/floppy

# Copy additional drivers
sudo cp NewDriver.driver /mnt/floppy/usr/Drivers/

# Unmount
sudo umount /mnt/floppy
```

## References

- Boot loader documentation: `boot-2/i386/doc/README`
- Boot loader source: `boot-2/i386/boot1/` and `boot-2/i386/boot2/`
- Driver loading code: `boot-2/i386/libsaio/drivers.c`
- Installation CD script: `mkinstallcd.sh`

## See Also

- `mkinstallcd.sh` - Create bootable installation CD-ROM
- `README.mkinstallcd.md` - Installation CD documentation

## License

These scripts are part of RhapsodiOS and follow the same license terms as the rest of the project.
