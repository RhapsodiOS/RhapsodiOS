# BusMouse - ISA Bus Mouse Driver for RhapsodiOS

## Overview

This is a driver for ISA bus mice on x86 systems. The driver supports Microsoft InPort mice, Logitech bus mice, and ATI XL mice - all of which use dedicated ISA cards with proprietary interfaces (as opposed to serial or PS/2 mice).

## Hardware Support

The driver supports three major bus mouse types:

### Microsoft InPort Mouse
- **Introduced**: 1986
- **Interface**: InPort chip with register-based access
- **Standard Addresses**: 0x23C (primary), 0x238 (secondary)
- **IRQ**: 5 (typical)
- **Resolution**: High precision
- **Buttons**: 2 or 3 buttons
- **Sample Rates**: 30, 50, 100, 200 Hz

### Logitech Bus Mouse
- **Interface**: Logitech proprietary bus interface
- **Standard Addresses**: 0x23C (primary), 0x238 (secondary)
- **IRQ**: 5 (typical)
- **Resolution**: Standard
- **Buttons**: 3 buttons
- **Sample Rates**: Up to 100 Hz

### ATI XL Mouse
- **Compatibility**: InPort-compatible
- **Standard Addresses**: 0x23C
- **IRQ**: 5 (typical)
- **Buttons**: 2 or 3 buttons
- **Notes**: Bundled with ATI graphics cards

## Features

### Core Features
- Auto-detection of mouse type (InPort, Logitech, ATI)
- Support for 2 and 3-button mice
- Configurable sample rates (30-200 Hz)
- Interrupt-driven operation (IRQ 5)
- Mouse acceleration with configurable threshold
- Event queue with buffering (64 events)

### Movement Tracking
- Relative movement (delta X/Y)
- Absolute position tracking
- Sign-extended 8-bit movement values
- Acceleration support for enhanced control

### Button Handling
- Left, right, and middle button support
- Button click counting
- Real-time button state tracking

### Event Management
- Queued event delivery
- Peek/get event operations
- Event flushing
- Timestamp tracking

## Technical Details

### Architecture

The driver consists of four main components:

1. **BusMouseDriver.h** - Driver interface definition
2. **BusMouseDriver.m** - Driver implementation with hardware support
3. **BusMouseRegs.h** - Hardware register definitions for all mouse types
4. **BusMouseTypes.h** - Type definitions and constants

### Hardware Interfaces

#### Microsoft InPort Mouse

The InPort interface uses an address/data register pair:

```
Base + 0: Address Register (write-only)
Base + 1: Data Register (read/write)
Base + 2: Identification Register (read-only)
Base + 3: Test Register
```

Internal registers (accessed via address/data):
- Register 0: Status (buttons and flags)
- Register 1: X movement delta
- Register 2: Y movement delta
- Register 7: Mode (sample rate, IRQ enable)

#### Logitech Bus Mouse

The Logitech interface uses direct register access:

```
Base + 0: Data Register
Base + 1: Signature Register
Base + 2: Control Register
Base + 3: Configuration Register
```

Movement data is read in nibbles (high and low 4 bits separately).

### Standard Port Addresses

| Mouse Type | Primary Address | Secondary Address | IRQ |
|-----------|----------------|-------------------|-----|
| InPort | 0x23C | 0x238 | 5 |
| Logitech | 0x23C | 0x238 | 5 |
| ATI XL | 0x23C | 0x238 | 5 |

### Detection Algorithm

The driver uses a multi-step detection process:

1. **InPort Detection**: Read signature registers (0x12, 0x34)
2. **Identification Check**: Verify ID byte (0xDE)
3. **Logitech Detection**: Check signature register (0xA5)
4. **Fallback**: Attempt InPort-compatible operation for ATI mice

## Usage

### Opening and Configuring the Mouse

```objective-c
BusMouseDriver *mouse = [BusMouseDriver probe:deviceDescription];
[mouse openMouse];

// Set sample rate to 100 Hz
[mouse setSampleRate:100];

// Set acceleration
[mouse setAcceleration:2 threshold:4];
```

### Reading Events

```objective-c
BusMouseEvent event;
IOReturn result;

while ([mouse hasEvent]) {
    result = [mouse getEvent:&event];
    if (result == IO_R_SUCCESS) {
        printf("Delta X: %d, Delta Y: %d\n",
               event.deltaX, event.deltaY);
        printf("Buttons: L=%d R=%d M=%d\n",
               event.buttons.left,
               event.buttons.right,
               event.buttons.middle);
    }
}
```

### Checking Position

```objective-c
BusMousePosition pos;
[mouse getPosition:&pos];

printf("Position: (%d, %d)\n", pos.x, pos.y);
```

### Polling Mode (without interrupts)

```objective-c
int deltaX, deltaY;
BusMouseButtons buttons;

[mouse readMovement:&deltaX deltaY:&deltaY buttons:&buttons];
```

## Building

```bash
cd drvBusMouse
make
```

The build will produce `BusMouse.config` which can be installed in `/System/Library/Drivers/`.

## Installation

```bash
make install
```

The driver will be installed to `/System/Library/Drivers/BusMouse.config`.

## Configuration

The driver configuration is stored in `BusMouse.table`. Each mouse type has separate configuration entries:

```
"InPort_Primary" = {
    "Port"       = "0x23C";
    "IRQ"        = "5";
    "Probe"      = "YES";
    "Type"       = "InPort";
};
```

## Compatibility

### Supported Hardware

- **Microsoft InPort Mouse** (all revisions)
- **Microsoft InPort Mouse Bus Card**
- **Logitech Bus Mouse** (Series 7, 9, and compatible)
- **Logitech MouseMan Bus**
- **ATI XL Mouse** (bundled with ATI VGA Wonder cards)
- **Generic InPort-compatible bus mice**

### Not Supported

- Serial mice (use serial port driver)
- PS/2 mice (use PS/2 controller driver)
- USB mice (use USB HID driver)

## Sample Rates

The driver supports multiple sample rates for InPort mice:

| Rate | Value | Notes |
|------|-------|-------|
| 30 Hz | RATE_30HZ | Low CPU usage |
| 50 Hz | RATE_50HZ | Balanced |
| 100 Hz | RATE_100HZ | Recommended |
| 200 Hz | RATE_200HZ | High precision |

Logitech mice typically operate at a fixed rate around 100 Hz.

## Acceleration

The driver supports mouse acceleration:

- **Acceleration Factor**: 1-10x multiplier
- **Threshold**: Minimum delta before acceleration applies
- **Default**: 2x acceleration with threshold of 4 pixels

Example:
```objective-c
// 3x acceleration when movement > 5 pixels
[mouse setAcceleration:3 threshold:5];
```

## Known Limitations

- **No Hot-Plug**: Bus mice require system restart for detection
- **Fixed IRQ**: Most systems hard-wire bus mouse to IRQ 5
- **Resolution**: Limited by hardware (typically 200-400 DPI)
- **Port Conflicts**: Only one bus mouse can be active at a time
- **ISA Only**: Requires ISA bus slot (not compatible with PCI-only systems)

## Troubleshooting

### Mouse Not Detected

1. Verify ISA card is properly seated
2. Check I/O port address (use system BIOS or documentation)
3. Ensure no port conflicts with other devices
4. Try both primary (0x23C) and secondary (0x238) addresses

### Erratic Movement

1. Clean mouse ball and rollers
2. Reduce acceleration factor
3. Lower sample rate
4. Check for IRQ conflicts

### Buttons Not Working

1. Verify mouse has 3-button support if using middle button
2. Check cable connection to ISA card
3. Test with known-good mouse

## Historical Context

Bus mice were popular in the late 1980s and early 1990s before PS/2 and serial mice became standard:

- **1984**: Logitech introduces first bus mouse
- **1986**: Microsoft releases InPort mouse
- **Late 1980s**: Bus mice common on IBM PC compatibles
- **Early 1990s**: PS/2 mice begin replacing bus mice
- **Mid 1990s**: Bus mice become legacy hardware

Bus mice required a dedicated ISA expansion card, which had several disadvantages:
- Consumed a valuable expansion slot
- Required manual configuration (I/O address, IRQ)
- More expensive than serial alternatives

However, they offered advantages:
- Lower CPU overhead than serial mice
- No serial port required
- Better precision than early serial mice
- Interrupt-driven operation

## References

- Microsoft InPort Mouse technical reference
- Logitech Bus Mouse programming guide
- ISA bus architecture specifications
- ATI graphics card documentation

## Credits

- **Author**: RhapsodiOS Project
- **Based on**: Microsoft InPort and Logitech bus mouse specifications
- **Architecture**: x86 ISA bus

## License

This driver is released under the Apple Public Source License Version 1.1.

## Version History

### 1.0 (2025)
- Initial implementation for RhapsodiOS x86
- Support for Microsoft InPort mouse
- Support for Logitech bus mouse
- Support for ATI XL mouse
- Auto-detection of mouse type
- Configurable sample rates
- Interrupt-driven event handling
- Mouse acceleration support
- Event queue with 64-entry buffer
- Statistics tracking
