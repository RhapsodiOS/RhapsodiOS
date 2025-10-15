# BeepDriver - PC Speaker Sound Driver for RhapsodiOS

## Overview

This is a simple sound driver for the PC speaker (also known as the system speaker or internal speaker) on x86 systems. The driver provides basic sound output functionality using the Intel 8254 Programmable Interval Timer (PIT) Channel 2.

## Hardware

### PC Speaker Architecture

The PC speaker is controlled by two hardware components:

1. **Intel 8254 PIT (Programmable Interval Timer)**
   - Channel 2 is dedicated to speaker control
   - Base clock: 1.193182 MHz
   - Divisor programming for frequency generation
   - Mode 3 (Square Wave Generator) for audio output

2. **8255 PPI Port B (Programmable Peripheral Interface)**
   - Controls speaker gate and data signals
   - Both bits must be set to enable speaker
   - Port 0x61 on x86 systems

### Hardware Capabilities

- **Frequency Range**: 20 Hz - 20 kHz (audible range)
- **Waveform**: Square wave only (limited by PIT Mode 3)
- **Volume**: Fixed (no volume control on PC speaker)
- **Polyphony**: Monophonic (one tone at a time)

### Hardware Limitations

- **No Volume Control**: Speaker is always at full volume when enabled
- **Square Wave Only**: No waveform shaping
- **No Mixing**: Cannot play multiple frequencies simultaneously
- **Limited Quality**: Good for alerts and simple tones

## Features

- Simple tone generation with configurable frequency and duration
- Default beep functionality
- Continuous tone control (start/stop)
- Thread-safe operation with locking
- Enable/disable control
- Configurable defaults

## Technical Details

### 8254 PIT Programming

The driver programs the PIT using the following sequence:

1. **Select Counter 2**: Write control word to port 0x43
   - Bits 7-6: 10 (Counter 2)
   - Bits 5-4: 11 (Access mode: lo/hi byte)
   - Bits 3-1: 011 (Mode 3: Square wave)
   - Bit 0: 0 (Binary mode)

2. **Write Divisor**: Calculate divisor from frequency
   ```
   Divisor = 1193182 / frequency
   ```
   - Write low byte to port 0x42
   - Write high byte to port 0x42

3. **Enable Speaker**: Set bits 0 and 1 in port 0x61
   - Bit 0: Timer 2 gate enable
   - Bit 1: Speaker data enable

### Frequency Calculation

```
PIT Clock = 1,193,182 Hz
Divisor = PIT Clock / Desired Frequency
Output Frequency = PIT Clock / Divisor

Example for 800 Hz:
Divisor = 1193182 / 800 = 1491
Actual Frequency = 1193182 / 1491 = 800.12 Hz
```

### Supported Frequency Range

- **Minimum**: 20 Hz
- **Maximum**: 20,000 Hz
- **Optimal**: 100-10,000 Hz (most audible range)

## Architecture

### File Structure

```
drvBeepSound/
├── BeepDriver.h            - Driver interface definition
├── BeepDriver.m            - Driver implementation
├── BeepTypes.h             - Type definitions
├── PCSpeakerRegs.h         - Hardware register definitions
├── Beep.table              - Configuration table
├── Makefile                - Build configuration
└── README.md               - This file
```

### Class Hierarchy

```
NSObject
  └── IODevice
      └── IODirectDevice
          └── BeepDriver
```

## Usage

### Simple Beep

```objective-c
BeepDriver *beep = [BeepDriver probe:deviceDescription];

// Play default beep (800 Hz, 250ms)
[beep beep];
```

### Custom Tone

```objective-c
// Play custom frequency and duration
[beep playTone:1000 duration:500];  // 1000 Hz for 500ms
```

### Continuous Tone

```objective-c
// Start a continuous tone
[beep startTone:440];  // 440 Hz (A4)

// ... do other work ...

// Stop the tone
[beep stopTone];
```

### Configuration

```objective-c
// Set default frequency and duration
[beep setDefaults:800 duration:250];

// Enable/disable sound output
[beep setEnabled:NO];   // Disable all sound
[beep setEnabled:YES];  // Re-enable

// Check if enabled
if ([beep isEnabled]) {
    [beep beep];
}

// Get configuration
SoundConfig config;
[beep getConfiguration:&config];
```

## Building

```bash
cd drvBeepSound
make
```

The build will produce `BeepDriver.config`.

## Installation

```bash
make install
```

The driver will be installed to `/System/Library/Drivers/BeepDriver.config`.

## API Reference

### Sound Output Methods

- `- (IOReturn) playTone:(UInt32)frequency duration:(UInt32)duration` - Play a tone at specified frequency and duration
- `- (IOReturn) beep` - Play default beep (800 Hz, 250ms)
- `- (IOReturn) startTone:(UInt32)frequency` - Start continuous tone
- `- (IOReturn) stopTone` - Stop current tone

### Configuration Methods

- `- (IOReturn) setEnabled:(BOOL)enabled` - Enable/disable sound output
- `- (BOOL) isEnabled` - Check if sound is enabled
- `- (IOReturn) setDefaults:(UInt32)frequency duration:(UInt32)duration` - Set defaults
- `- (IOReturn) getConfiguration:(SoundConfig *)config` - Get current configuration

## Performance

### Timing Characteristics

- **Frequency Accuracy**: ±1 Hz typical
- **Duration Accuracy**: ±1 ms (limited by IOSleep resolution)
- **Response Time**: < 1 ms to start/stop tone
- **CPU Usage**: Minimal (blocking sleep during tone)

### Resource Usage

- **I/O Ports Used**: 0x42 (PIT Counter 2), 0x43 (PIT Control), 0x61 (PPI Port B)
- **Memory**: < 1 KB for driver instance
- **No DMA**: All control via direct I/O port access
- **No Interrupts**: Timing via IOSleep

## Troubleshooting

### No Sound

1. **Check if enabled**: Verify `[beep isEnabled]` returns YES
2. **Verify hardware**: Ensure PC speaker is installed
3. **Check BIOS**: Some systems allow disabling PC speaker in BIOS

### Wrong Frequency

1. **Validate range**: Ensure frequency is 20-20000 Hz
2. **Hardware variation**: Some speakers have limited frequency response

### Distorted Sound

1. **Frequency too high**: Try lower frequencies (< 5000 Hz)
2. **Frequency too low**: Try higher frequencies (> 100 Hz)
3. **Square wave**: All tones are square waves (inherently buzzy)

## Limitations

### Hardware Limitations

- **No Volume Control**: Speaker volume is fixed by hardware
- **Monophonic**: Only one tone at a time
- **Square Wave Only**: No waveform variety
- **Limited Bandwidth**: Poor frequency response outside 500-2000 Hz

### Software Limitations

- **Blocking I/O**: Tones block the calling thread (synchronous)
- **No Asynchronous Playback**: All operations are synchronous
- **Fixed Sample Rate**: Determined by PIT clock (1.193182 MHz)

### System Limitations

- **Missing Hardware**: Some modern systems lack PC speaker
- **BIOS Disable**: PC speaker may be disabled in BIOS
- **Virtualization**: May not work in virtual machines

## Historical Context

The PC speaker has been a standard component since the original IBM PC (1981). While largely replaced by sound cards in the 1990s, it persists for:

- **Firmware Access**: Works before OS loads (BIOS/UEFI can use it)
- **No Dependencies**: Requires no drivers, always available
- **Reliability**: Simple hardware, almost never fails
- **Debugging**: Audio feedback when screen is not working

## Technical References

### Intel 8254 PIT

- **Datasheet**: Intel 82C54 Programmable Interval Timer
- **Clock**: 1.193182 MHz
- **Resolution**: 16-bit counter (divisor 1-65535)

### I/O Port Assignments

| Port | Name | Direction | Purpose |
|------|------|-----------|---------|
| 0x42 | Counter 2 | R/W | PC speaker frequency control |
| 0x43 | Control | W | PIT control register |
| 0x61 | PPI Port B | R/W | Speaker enable/disable |

## Compatibility

### Supported Systems

- **x86 PC Compatible**: Any system with 8254 PIT and PC speaker
- **Physical Hardware**: Best on real hardware with physical speaker
- **Virtual Machines**: May work if VM emulates PC speaker

## Credits

- **Author**: RhapsodiOS Project
- **Hardware**: Intel 8254 Programmable Interval Timer
- **Architecture**: x86 PC Compatible

## License

This driver is released under the Apple Public Source License Version 1.1.
