/*
 * vidBIOS.h
 * Video BIOS Emulator Class
 *
 * Provides x86 real mode BIOS emulation for VESA video calls
 */

#import <objc/Object.h>
#import <driverkit/return.h>

// Structure for x86 registers (INT 10h call interface)
typedef struct {
    unsigned int eax;      // 0x00
    unsigned int ecx;      // 0x04
    unsigned int edx;      // 0x08
    unsigned int ebx;      // 0x0C
    unsigned int esp;      // 0x10
    unsigned int ebp;      // 0x14
    unsigned int esi;      // 0x18
    unsigned int edi;      // 0x1C
    unsigned int eip;      // 0x20
    unsigned int eflags;   // 0x24
    unsigned int es;       // 0x28
    unsigned int cs;       // 0x2C
    unsigned int ss;       // 0x30
    unsigned int ds;       // 0x34
    unsigned int fs;       // 0x38
    unsigned int gs;       // 0x3C
} x86_registers_t;

// IORange structure (should match driverkit definition)
typedef struct {
    unsigned int start;    // Starting address/port
    unsigned int size;     // Size of range
} IORange;

@interface vidBIOS : Object
{
    void *lowMemRegion;        // @ offset +4: Low memory allocation (< 1MB)
    unsigned int physAddr;     // @ offset +8: Physical address of low memory
    void *mappedLowMem;        // @ offset +12: Mapped lower 1MB virtual address
}

// Initialization and cleanup
- init;
- free;

// Address translation
- (void *)realToVirtual:(unsigned int)segment :(unsigned int)offset;
- (unsigned int)scratchSegment;

// BIOS INT 10h emulation
- (int)int10:(const x86_registers_t *)inregs
     outregs:(x86_registers_t *)outregs
     iorange:(const IORange *)ranges
       ionum:(int)numRanges;

- (int)int10:(const x86_registers_t *)inregs
     outregs:(x86_registers_t *)outregs
     iorange:(const IORange *)ranges
       ionum:(int)numRanges
     smmport:(unsigned int)smmPort;

@end
