/*
 * FloppyController_Arch.m
 * Architecture-specific implementation for FloppyController
 */

#import "FloppyController_Arch.h"
#import <driverkit/i386/ioPorts.h>
#import <driverkit/generalFuncs.h>
#import <architecture/i386/pio.h>

// DMA Controller registers (8237)
#define DMA_MODE_REG        0x0B    // Mode register
#define DMA_MASK_REG        0x0A    // Mask register
#define DMA_CLEAR_FF_REG    0x0C    // Clear flip-flop register
#define DMA_ADDR_2          0x04    // Channel 2 address register
#define DMA_COUNT_2         0x05    // Channel 2 count register
#define DMA_PAGE_2          0x81    // Channel 2 page register
#define DMA_STATUS_REG      0x08    // Status register

// FDC I/O port offsets (relative to base)
#define FDC_DOR     0  // Digital Output Register
#define FDC_MSR     4  // Main Status Register
#define FDC_DATA    5  // Data Register
#define FDC_DIR     7  // Digital Input Register
#define FDC_CCR     7  // Configuration Control Register (write)

// DOR (Digital Output Register) bits
#define DOR_MOTD    0x80  // Motor D enable
#define DOR_MOTC    0x40  // Motor C enable
#define DOR_MOTB    0x20  // Motor B enable
#define DOR_MOTA    0x10  // Motor A enable
#define DOR_DMA     0x08  // DMA enable
#define DOR_RESET   0x04  // FDC reset (active low)
#define DOR_DSEL1   0x02  // Drive select bit 1
#define DOR_DSEL0   0x01  // Drive select bit 0

// MSR (Main Status Register) bits
#define MSR_RQM     0x80  // Request for Master (ready for command/data)
#define MSR_DIO     0x40  // Data Input/Output (1=read, 0=write)
#define MSR_NONDMA  0x20  // Non-DMA mode
#define MSR_BUSY    0x10  // Command in progress
#define MSR_DRV3BSY 0x08  // Drive 3 busy
#define MSR_DRV2BSY 0x04  // Drive 2 busy
#define MSR_DRV1BSY 0x02  // Drive 1 busy
#define MSR_DRV0BSY 0x01  // Drive 0 busy

@implementation FloppyController(Arch)

- (void)outb:(unsigned int)port value:(unsigned char)value
{
    // Wrapper for architecture-specific port I/O
    outb(port, value);
}

- (unsigned char)inb:(unsigned int)port
{
    // Wrapper for architecture-specific port I/O
    return inb(port);
}

- (IOReturn)setupDMAChannel:(unsigned int)channel
                     address:(vm_address_t)addr
                      length:(unsigned int)length
                       write:(BOOL)isWrite
{
    unsigned int dmaAddr;
    unsigned int dmaCount;
    unsigned int dmaMode;

    // Only support channel 2 (floppy DMA channel)
    if (channel != 2) {
        IOLog("FloppyController_Arch: Invalid DMA channel %d (must be 2)\n", channel);
        return IO_R_INVALID_ARG;
    }

    // Verify buffer is within DMA-able range (first 16MB for ISA DMA)
    if (addr >= 0x1000000) {
        IOLog("FloppyController_Arch: DMA buffer at 0x%08x above 16MB boundary\n",
              (unsigned int)addr);
        return IO_R_INVALID_ARG;
    }

    // Verify transfer doesn't cross 64KB boundary (ISA DMA limitation)
    dmaAddr = (unsigned int)addr;
    if ((dmaAddr & 0xFFFF0000) != ((dmaAddr + length - 1) & 0xFFFF0000)) {
        IOLog("FloppyController_Arch: DMA transfer crosses 64KB boundary\n");
        return IO_R_INVALID_ARG;
    }

    // Setup DMA mode register
    // Bits: 7-6 = mode (01=write, 10=read, 00=verify)
    //       5-4 = 00 (single mode, no auto-init)
    //       3   = 0 (address increment)
    //       2   = 0 (demand mode)
    //       1-0 = 10 (channel 2)
    if (isWrite) {
        dmaMode = 0x4A;  // 01001010b: Write mode (read from memory)
    } else {
        dmaMode = 0x46;  // 01000110b: Read mode (write to memory)
    }

    // Mask DMA channel 2 (disable it during programming)
    outb(DMA_MASK_REG, 0x06);  // Set mask bit for channel 2

    // Clear byte pointer flip-flop
    outb(DMA_CLEAR_FF_REG, 0x00);

    // Set DMA address (16-bit, low byte first, then high byte)
    outb(DMA_ADDR_2, dmaAddr & 0xFF);
    outb(DMA_ADDR_2, (dmaAddr >> 8) & 0xFF);

    // Set DMA page register (bits 16-23 of address)
    outb(DMA_PAGE_2, (dmaAddr >> 16) & 0xFF);

    // Set DMA count (16-bit, length - 1, low byte first, then high byte)
    dmaCount = length - 1;
    outb(DMA_COUNT_2, dmaCount & 0xFF);
    outb(DMA_COUNT_2, (dmaCount >> 8) & 0xFF);

    // Set DMA mode
    outb(DMA_MODE_REG, dmaMode);

    // Unmask DMA channel 2 (enable it)
    outb(DMA_MASK_REG, 0x02);  // Clear mask bit for channel 2

    return IO_R_SUCCESS;
}

- (void)enableInterrupts
{
    unsigned char dor;
    unsigned int ioBase;

    // Get I/O port base from controller instance variable
    ioBase = ((FloppyController *)self)->_ioPortBase;

    // Read current DOR value
    dor = inb(ioBase + FDC_DOR);

    // Set DMA enable bit to allow FDC to trigger interrupts
    // This enables the controller to signal IRQ 6 to the PIC
    dor |= DOR_DMA;

    // Write back DOR with interrupts enabled
    outb(ioBase + FDC_DOR, dor);

    // Note: IRQ 6 on the PIC (Programmable Interrupt Controller) must also be
    // unmasked, but this is handled by the IODirectDevice interrupt registration
    // mechanism during initialization via getHandler:level:argument:forInterrupt:
}

- (void)disableInterrupts
{
    unsigned char dor;
    unsigned int ioBase;

    // Get I/O port base from controller instance variable
    ioBase = ((FloppyController *)self)->_ioPortBase;

    // Read current DOR value
    dor = inb(ioBase + FDC_DOR);

    // Clear DMA enable bit to disable FDC interrupts
    // This prevents the controller from signaling IRQ 6
    dor &= ~DOR_DMA;

    // Write back DOR with interrupts disabled
    outb(ioBase + FDC_DOR, dor);
}

@end
