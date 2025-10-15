# ParallelPort - Standard PC Parallel Port Driver for RhapsodiOS

## Overview

This is a driver for standard PC parallel ports (LPT1-LPT3) on x86 systems. The driver supports multiple operating modes including SPP (Standard Parallel Port), PS/2 bidirectional, EPP (Enhanced Parallel Port), and ECP (Extended Capabilities Port).

## Hardware Support

The driver supports:
- **LPT1**: Base address 0x378, IRQ 7 (default)
- **LPT2**: Base address 0x278, IRQ 5
- **LPT3**: Base address 0x3BC, IRQ 7

### Port Modes

- **SPP (Standard Parallel Port)**: Classic Centronics-compatible mode, output only
- **PS/2 Bidirectional**: Bidirectional data transfer using standard pins
- **EPP (Enhanced Parallel Port)**: High-speed bidirectional mode with address/data strobes
- **ECP (Extended Capabilities Port)**: Advanced mode with FIFO buffer and DMA support

## Features

### Core Features
- Auto-detection of port capabilities (SPP/PS/2/EPP/ECP)
- Support for all three standard parallel ports
- Bidirectional data transfer
- Hardware status monitoring (BUSY, ACK, PAPER OUT, SELECT, ERROR)
- Control signal management (STROBE, AUTO FEED, INIT, SELECT)
- Configurable timeout values
- Interrupt support (IRQ-driven operation)

### Data Transfer
- Single-byte read/write operations
- Block read/write operations
- EPP address/data transfers
- ECP FIFO-based transfers (framework in place)

### Status and Statistics
- Real-time port status monitoring
- Transfer statistics (bytes sent/received, errors)
- Error counting (timeout, FIFO overrun, etc.)

## Technical Details

### Architecture

The driver consists of four main components:

1. **ParallelPortDriver.h** - Driver interface definition
2. **ParallelPortDriver.m** - Driver implementation
3. **ParallelPortRegs.h** - Hardware register definitions
4. **ParallelPortTypes.h** - Type definitions and constants

### Register Interface

The parallel port uses a simple I/O port interface:

```
Base + 0: Data Register (8-bit bidirectional)
Base + 1: Status Register (read-only)
Base + 2: Control Register (read/write)
Base + 3: EPP Address Register (EPP mode)
Base + 4: EPP Data Register (EPP mode)
Base + 0x400: ECP registers (if supported)
```

### Standard Port Addresses

| Port | Base Address | IRQ | Notes |
|------|-------------|-----|-------|
| LPT1 | 0x378 | 7 | Most common |
| LPT2 | 0x278 | 5 | Secondary port |
| LPT3 | 0x3BC | 7 | Legacy (MDA era) |

### Pin Assignments

#### Data Lines (Pins 2-9)
- D0-D7: 8-bit bidirectional data

#### Status Lines
- BUSY (Pin 11): Printer busy (inverted)
- ACK (Pin 10): Acknowledge
- PAPER OUT (Pin 12): Out of paper
- SELECT (Pin 13): Printer selected
- ERROR (Pin 15): Error condition (inverted)

#### Control Lines
- STROBE (Pin 1): Data strobe (inverted)
- AUTO FEED (Pin 14): Auto line feed (inverted)
- INIT (Pin 16): Initialize printer (inverted)
- SELECT IN (Pin 17): Select printer

## Usage

### Opening and Configuring a Port

```objective-c
ParallelPortDriver *port = [ParallelPortDriver probe:deviceDescription];
[port openPort];

// Set mode
ParallelPortMode mode = PP_MODE_SPP;
[port setMode:mode];

// Set timeout
[port setTimeout:1000000]; // 1 second
```

### Writing Data

```objective-c
UInt8 data[] = "Hello, printer!\n";
UInt32 bytesWritten;
IOReturn result;

result = [port writeBytes:data
                   length:strlen(data)
             bytesWritten:&bytesWritten];
```

### Reading Status

```objective-c
ParallelPortStatus status;
[port getStatus:&status];

if (status.online && !status.busy) {
    // Port is ready
}

if (status.paperOut) {
    // Out of paper
}
```

### EPP Mode Transfers

```objective-c
// Switch to EPP mode
[port setMode:PP_MODE_EPP];

// Write address
[port eppWriteAddress:0x10];

// Write data
UInt8 data[256];
[port eppWriteData:data length:256];
```

## Building

```bash
cd drvParallelPort
make
```

The build will produce `ParallelPort.config` which can be installed in `/System/Library/Drivers/`.

## Installation

```bash
make install
```

The driver will be installed to `/System/Library/Drivers/ParallelPort.config`.

## Command Line Tools

The driver package includes two command line utilities for managing parallel port devices:

### InstallPPDev

Installs and configures a parallel port device.

**Usage:**
```bash
InstallPPDev -port <portname> [-base <address>] [-irq <number>] [-mode <mode>] [-verbose]
```

**Options:**
- `-port <name>`: Port name (LPT1, LPT2, or LPT3) [required]
- `-base <address>`: Base I/O address (hex or decimal)
- `-irq <number>`: IRQ number
- `-mode <mode>`: Operating mode (SPP, PS2, EPP, ECP)
- `-verbose, -v`: Verbose output
- `-help, -h`: Show help

**Examples:**
```bash
# Install LPT1 with default settings (0x378, IRQ 7, SPP mode)
InstallPPDev -port LPT1

# Install LPT2 with custom settings
InstallPPDev -port LPT2 -base 0x278 -irq 5

# Install LPT1 in EPP mode with verbose output
InstallPPDev -port LPT1 -mode EPP -verbose
```

### RemovePPDev

Removes a parallel port device configuration.

**Usage:**
```bash
RemovePPDev -port <portname> [-force] [-verbose]
```

**Options:**
- `-port <name>`: Port name (LPT1, LPT2, or LPT3) [required]
- `-force, -f`: Force removal without confirmation
- `-verbose, -v`: Verbose output
- `-help, -h`: Show help

**Examples:**
```bash
# Remove LPT1 (will prompt for confirmation)
RemovePPDev -port LPT1

# Remove LPT2 without confirmation
RemovePPDev -port LPT2 -force

# Remove LPT1 with verbose output
RemovePPDev -port LPT1 -verbose
```

## Configuration

The driver configuration is stored in `ParallelPort.table`. You can customize:
- Port addresses
- IRQ numbers
- Probe settings for each port

Example configuration:
```
"LPT1" = {
    "Port"       = "0x378";
    "IRQ"        = "7";
    "Probe"      = "YES";
};
```

## Compatibility

### Supported Devices
- Standard PC parallel ports (25-pin DB25 connector)
- Centronics-compatible printers
- Parallel port scanners
- Parallel port Zip drives
- PLIP (Parallel Line Internet Protocol) adapters
- Parallel port dongles

### Operating Modes
- **SPP**: Universal, works with all parallel ports
- **PS/2**: Requires bidirectional support (most post-1990 hardware)
- **EPP**: Requires EPP-capable port and device
- **ECP**: Requires ECP-capable port and device

## Known Limitations

- **ECP Mode**: FIFO and DMA operations are stubbed (framework in place)
- **IEEE 1284**: Full IEEE 1284 negotiation is not implemented
- **DMA Transfers**: Not yet implemented for ECP mode
- **Interrupt Handler**: Basic implementation, does not handle data transfer
- **Device ID**: IEEE 1284 device ID retrieval not implemented

## Future Enhancements

Planned improvements include:
1. Full IEEE 1284 negotiation and termination
2. Complete ECP FIFO implementation with DMA
3. Enhanced interrupt-driven data transfer
4. Device ID retrieval and parsing
5. Power management support
6. PnP parallel port detection

## Hardware Timing

The driver respects standard parallel port timing requirements:
- **Strobe Width**: 1 µs minimum
- **Data Setup**: 500 ns
- **Data Hold**: 500 ns
- **ACK Width**: 5 µs typical
- **Busy Wait**: 1 µs between polls

### Transfer Rates

| Mode | Maximum Speed | Notes |
|------|--------------|-------|
| SPP | 150 KB/s | Standard unidirectional |
| PS/2 | 150 KB/s | Bidirectional |
| EPP | 2 MB/s | Enhanced transfers |
| ECP | 2 MB/s | With FIFO/DMA |

## Debugging

Enable debug output by setting:
```c
#define PP_DEBUG        1
#define PP_TRACE        1
```

This will log:
- Port detection and initialization
- Register reads/writes
- Transfer operations
- Error conditions

## References

- IEEE 1284-1994: Standard Signaling Method for a Bidirectional Parallel Peripheral Interface
- Intel 8255 PPI (Programmable Peripheral Interface) documentation
- PC Architecture references (ISA bus parallel port)
- Centronics parallel interface specification

## Credits

- **Author**: RhapsodiOS Project
- **Based on**: Standard PC parallel port architecture
- **Architecture**: x86 ISA bus

## License

This driver is released under the Apple Public Source License Version 1.1.

## Version History

### 1.0 (2025)
- Initial implementation for RhapsodiOS x86
- SPP mode support with full status/control
- PS/2 bidirectional support
- EPP mode framework (address/data operations)
- ECP mode detection and framework
- Port capability detection
- Statistics and error tracking
