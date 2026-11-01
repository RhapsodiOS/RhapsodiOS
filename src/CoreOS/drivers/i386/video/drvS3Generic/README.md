# S3 Generic Display Driver

A unified display driver for S3 graphics accelerators supporting both S3 Trio and Virge chipsets, along with the legacy S3 805 and 928 chipsets.

## Supported Hardware

### S3 Trio Series
- **S3 Trio32** - Entry-level 2D accelerator
- **S3 Trio64** - Enhanced version with improved performance

### S3 Virge Series
- **S3 Virge** - 2D/3D accelerator with basic 3D support
- **S3 VirgeDX** - Enhanced Virge with improved features
- **S3 VirgeGX** - High-end variant

### Legacy S3 Chipsets
- **S3 86C805** - Legacy 2D accelerator
- **S3 86C928** - Legacy 2D accelerator with enhanced features

## Features

- **Automatic chipset detection** - Detects and configures based on installed S3 chipset
- **Multiple resolution support** - Common resolutions from 640x480 to 1280x1024
- **Color depth options** - 8-bit, 15-bit, and 24-bit color modes (chipset dependent)
- **Multiple refresh rates** - 60Hz, 70Hz, and 72Hz options (mode dependent)
- **Optimized for each chipset** - Chipset-specific register configurations
- **Linear framebuffer mode** - For efficient graphics operations

## Supported Resolutions

### S3 Trio Chipsets
- 640 x 480 @ 8bpp, 60Hz
- 800 x 600 @ 8bpp, 60Hz, 72Hz
- 800 x 600 @ 15bpp, 60Hz
- 1024 x 768 @ 8bpp, 60Hz, 70Hz, 72Hz
- 1024 x 768 @ 15bpp, 60Hz (Trio64)

### S3 Virge Chipsets
- 640 x 480 @ 8bpp, 60Hz
- 800 x 600 @ 8bpp, 60Hz, 72Hz
- 800 x 600 @ 15bpp, 60Hz
- 800 x 600 @ 24bpp, 60Hz
- 1024 x 768 @ 8bpp, 60Hz, 70Hz, 72Hz
- 1024 x 768 @ 15bpp, 60Hz
- 1280 x 1024 @ 8bpp, 60Hz

## Memory Requirements

Mode selection is automatic based on available video memory:
- **512KB** - Limited to basic 640x480 modes
- **1MB** - Supports up to 1024x768 @ 8bpp
- **2MB** - Supports higher color depths (15bpp at 1024x768)
- **3-4MB** - Supports 24bpp modes on Virge chipsets

## Configuration

The driver supports configuration through the config table:

### Performance Options
- `WritePostingEnabled` - Enable/disable write posting (default: YES for most chipsets)
- `ReadAheadCacheEnabled` - Enable/disable read-ahead cache (default: YES for most chipsets)
- `DisplayCacheMode` - Cache mode: "Off", "WriteThrough", or "CopyBack"

### Custom Mode Parameters (Advanced)
You can override register values for specific modes:
- `[Mode Name] CRTC Registers` - CRTC register overrides
- `[Mode Name] XCRTC Registers` - Extended CRTC register overrides
- `[Mode Name] Mode Control Register` - Mode control overrides
- `[Mode Name] MiscOutput Register` - Miscellaneous output overrides
- `[Mode Name] Advanced Function Control Register` - Advanced function control overrides

## Building

```bash
cd S3GenericDisplayDriver
make
```

## Installation

The driver will be installed as a kernel driver bundle. Installation location depends on your RhapsodiOS configuration.

## Architecture

### Key Components

1. **S3Generic.m** - Main driver implementation
2. **S3GenericSetMode.m** - Mode detection and initialization
3. **S3GenericProgramDAC.m** - DAC programming for different color modes
4. **S3GenericConfigTable.m** - Configuration table handling
5. **S3_Trio_Modes.c** - Mode tables for Trio chipsets
6. **S3_Virge_Modes.c** - Mode tables for Virge chipsets
7. **S3_805_Modes.c** - Mode tables for 805 chipset
8. **S3_928_Modes.c** - Mode tables for 928 chipset

### Chipset Detection

The driver uses register 0x30 (Chip ID) to identify the S3 chipset:
- 0xA0 = S3 805
- 0x90 = S3 928
- 0xB0 = S3 Trio32
- 0xE0 = S3 Trio64
- 0x50 = S3 Virge
- 0x60 = S3 VirgeDX
- 0x70 = S3 VirgeGX

## Differences from Original S3 Driver

1. **Unified codebase** - Single driver supporting multiple chipset families
2. **Extended chipset support** - Added Trio and Virge families
3. **More display modes** - Additional resolutions and color depths
4. **Better mode compatibility** - Trio64 can use Trio32 modes, etc.
5. **Improved default settings** - Better performance defaults for newer chipsets

## Known Limitations

- 3D acceleration features of Virge chipsets are not utilized
- Some exotic resolutions may require custom configuration
- Hardware cursor support depends on DAC type
- ISA bus configurations may have reduced performance

## Credits

Based on the original S3 display driver by:
- Peter Graffagnino (1/31/93)
- Derek B Clegg (5/21/93)
- James C. Lee (AT&T 20C505 DAC support)

Modified to support S3 Trio and Virge chipsets for RhapsodiOS.

## License

Copyright (c) 1993-1996 by NeXT Software, Inc. as an unpublished work.
All rights reserved.
