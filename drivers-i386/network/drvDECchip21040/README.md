# DECchip 21040 Network Driver

## Overview
This driver supports the DEC 21040 and 21041 Ethernet controllers. These are 10Mbps-only chips that use SIA (Serial Interface Adapter) for media control rather than MII.

## Files Created
- ✅ `Default.table` - Driver configuration
- ✅ `DECchip2104x.h` - Base class header with Private category

## Complete File Structure

```
drvDECchip21040/
├── Default.table               # Driver configuration
├── DECchip2104x.h             # Base class interface + Private category
├── DECchip2104x.m             # Base class implementation
├── DECchip21040.h             # 21040-specific subclass
├── DECchip21040.m             # 21040 implementation
├── DECchip21041.h             # 21041-specific subclass
├── DECchip21041.m             # 21041 implementation
├── DECchip2104xKernelServerInstance.h
├── DECchip2104xKernelServerInstance.m
├── Makefile
├── Makefile.preamble
└── Makefile.postamble
```

## Architecture

### Class Hierarchy
```
IOEthernetDriver
  └── DECchip2104x (Base class)
      ├── DECchip21040 (21040-specific)
      └── DECchip21041 (21041-specific)

DECchip2104x(Private) - Category for internal implementation

DECchip2104xKernelServerInstance - Kernel server integration
```

### Private Category Pattern
Based on binary exports, this driver uses Objective-C categories to separate public interface from private implementation:

**Public methods** (DECchip2104x interface):
- User-facing API
- Driver initialization
- Network operations

**Private methods** (DECchip2104x(Private) category):
- `_allocMemory`, `_freeMemory`
- `_initChip`, `_resetChip`
- `_startTransmit`, `_startReceive`
- `_transmitInterruptOccurred`, `_receiveInterruptOccurred`
- `_loadSetupFilter`
- Low-level chip operations

## Key Differences from 21X4X Driver

### 1. **No MII Support**
   - Uses SIA (CSR12-15) for media control
   - No PHY management
   - No auto-negotiation

### 2. **10Mbps Only**
   - Supports 10BaseT, 10Base2, 10Base5
   - No 100Mbps capability

### 3. **Simpler Media Selection**
   - Direct SIA register programming
   - Manual interface selection

### 4. **Separate 21040/21041 Classes**
   - 21040: Original chip
   - 21041: Improved version with better media detection

## CSR Register Map (21040/21041)

```
CSR0  - Bus Mode
CSR1  - Transmit Poll Demand
CSR2  - Receive Poll Demand
CSR3  - Receive List Base Address
CSR4  - Transmit List Base Address
CSR5  - Status
CSR6  - Network Access (Operation Mode)
CSR7  - Interrupt Enable
CSR8  - Missed Frames Counter
CSR9  - Ethernet Address (ROM)
CSR10 - Reserved
CSR11 - General Purpose Timer
CSR12 - SIA Status
CSR13 - SIA Connectivity
CSR14 - SIA Transmit and Receive
CSR15 - SIA General
```

## SIA Configuration

### 10BaseT Configuration
```c
CSR13 = 0x00000001;  // SIA Connectivity
CSR14 = 0x0000007F;  // SIA TX/RX
CSR15 = 0x00000008;  // SIA General
```

### 10Base2 (BNC) Configuration
```c
CSR13 = 0x00000009;
CSR14 = 0x00000705;
CSR15 = 0x00000006;
```

### 10Base5 (AUI) Configuration
```c
CSR13 = 0x00000009;
CSR14 = 0x00000705;
CSR15 = 0x00000006;
```

## Implementation Notes

### Memory Management
- Uses kernel `IOMalloc`/`IOFree` for buffers
- Descriptor rings for TX/RX
- Setup frame for address filtering

### Descriptor Format
Same as 21X4X:
- 4 32-bit words per descriptor
- Ring buffer architecture
- DMA ownership bit

### Interrupt Handling
- CSR5 status register
- TX complete, RX complete
- Error conditions
- Link status changes

## Device IDs

- **21040**: PCI ID 0x00021011
- **21041**: PCI ID 0x00141011

## Build Instructions

```bash
cd drvDECchip21040
make
```

## Testing

1. Load driver: `/usr/etc/kextload /usr/Devices/DECchip21040.config`
2. Check dmesg for initialization messages
3. Configure network interface
4. Test connectivity

## Known Limitations

1. **10Mbps only** - No 100Mbps support
2. **Manual media selection** - No auto-sensing on 21040
3. **SIA-based** - Different from modern MII-based chips
4. **Legacy hardware** - Primarily for compatibility

## Future Enhancements

- [ ] Complete all implementation files
- [ ] Add comprehensive error handling
- [ ] Implement full media auto-detection for 21041
- [ ] Add performance tuning
- [ ] Create unit tests

## References

- DEC 21040 Hardware Reference Manual
- DEC 21041 Datasheet
- Tulip Driver Documentation (Linux)
- RhapsodiOS Driver Kit Documentation
