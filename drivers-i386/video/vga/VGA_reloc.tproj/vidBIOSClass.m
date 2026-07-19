/*
 * vidBIOSClass.m
 * Video BIOS Emulator Class Implementation
 *
 * Provides x86 real mode BIOS emulation for VESA video calls
 */

#import "vidBIOS.h"
#import "IOVGADisplay.h"
#import <driverkit/generalFuncs.h>
#import <mach/mach_interface.h>
#import <string.h>

// External page size variable
extern unsigned int __page_size;

// External _emu486 function from vidBIOS.m
extern unsigned int _emu486(unsigned char *base_ptr, unsigned int *in_regs,
                           unsigned int *out_regs, unsigned int page_table,
                           unsigned int io_bitmap, unsigned int smm_port);

@implementation vidBIOS

/*
 * init
 * Initializes the BIOS emulator by allocating low memory and mapping lower 1MB
 */
- init
{
    int result;
    unsigned int virtAddr;
    const char *name;

    // Allocate one page of low memory (< 1MB physical)
    lowMemRegion = (void *)IOMallocLow(__page_size);
    if (lowMemRegion == NULL) {
        name = [self name];
        IOLog("%s: can't allocate low memory region\n", name);
        return [self free];
    }

    // Get the virtual-to-physical mapping
    result = IOVmTaskSelf((unsigned int)lowMemRegion, &virtAddr);
    result = IOPhysicalFromVirtual(result);

    if (result != 0) {
        name = [self name];
        IOLog("%s: failed to wire down low memory region\n", name);
        physAddr = 0;
        return [self free];
    }

    // Verify the physical address is in lower 1MB
    if ((virtAddr & 0xFFF00000) != 0) {
        name = [self name];
        IOLog("%s: can't allocate memory region in the lower 1MB\n", name);
        return [self free];
    }

    physAddr = virtAddr;

    // Map the entire lower 1MB into our virtual address space
    result = IOMapPhysicalIntoIOTask(0, 0x100000, (unsigned int *)&mappedLowMem);
    if (result != 0) {
        name = [self name];
        IOLog("%s: can't map lower 1MB\n", name);
        mappedLowMem = NULL;
        return [self free];
    }

    // Initialize successfully
    return [super init];
}

/*
 * free
 * Cleanup allocated resources
 */
- free
{
    // Free low memory region if allocated
    if (lowMemRegion != NULL) {
        IOFreeLow((unsigned int)lowMemRegion, __page_size);
        lowMemRegion = NULL;
    }

    // Unmap lower 1MB if mapped
    if (mappedLowMem != NULL) {
        IOUnmapPhysicalFromIOTask((unsigned int)mappedLowMem, 0x100000);
        mappedLowMem = NULL;
    }

    return [super free];
}

/*
 * realToVirtual::
 * Converts real mode segment:offset address to virtual address
 */
- (void *)realToVirtual:(unsigned int)segment :(unsigned int)offset
{
    return (void *)(segment * 0x10 + (unsigned int)mappedLowMem + offset);
}

/*
 * scratchSegment
 * Returns the segment address of the scratch memory region
 */
- (unsigned int)scratchSegment
{
    return physAddr >> 4;
}

/*
 * int10:outregs:iorange:ionum:
 * Execute INT 10h BIOS call with default SMM port
 */
- (int)int10:(const x86_registers_t *)inregs
     outregs:(x86_registers_t *)outregs
     iorange:(const IORange *)ranges
       ionum:(int)numRanges
{
    return [self int10:inregs
               outregs:outregs
               iorange:ranges
                 ionum:numRanges
               smmport:0x10000];
}

/*
 * int10:outregs:iorange:ionum:smmport:
 * Execute INT 10h BIOS call with specified SMM port
 *
 * This is the main BIOS emulation entry point. It sets up the environment
 * for _emu486 and executes the BIOS code.
 */
- (int)int10:(const x86_registers_t *)inregs
     outregs:(x86_registers_t *)outregs
     iorange:(const IORange *)ranges
       ionum:(int)numRanges
     smmport:(unsigned int)smmPort
{
    unsigned char pageTable[256];
    void *ioBitmap;
    int result;
    unsigned int i, port;
    unsigned int regs[16];
    unsigned int savedPort0, savedPort1;
    unsigned int scratchSeg, scratchSP;
    const char *name;
    unsigned int pageNum;

    // Initialize page table - all pages invalid by default
    memset(pageTable, 0, 0x100);

    // Page 0 is always valid (BIOS data area, interrupt vectors)
    pageTable[0] = 1;

    // Pages 0xA0-0xFF are valid (video memory and BIOS ROM)
    for (i = 0xA0; i < 0x100; i++) {
        pageTable[i] = 1;
    }

    // Mark scratch memory page as valid
    for (pageNum = physAddr >> 12;
         pageNum < (physAddr + __page_size) >> 12;
         pageNum++) {
        pageTable[pageNum] = 1;
    }

    // Allocate I/O permission bitmap (8KB for 64K ports)
    ioBitmap = IOMalloc(0x2000);

    if (ranges == NULL) {
        // No ranges specified - deny all I/O ports
        memset(ioBitmap, 0xFF, 0x2000);
    } else {
        // Start with all ports denied
        memset(ioBitmap, 0, 0x2000);

        // Mark allowed port ranges
        for (i = numRanges - 1; i != (unsigned int)-1; i--) {
            unsigned int startPort = ranges[i].start;
            unsigned int endPort = startPort + ranges[i].size;

            for (port = startPort; port < endPort; port++) {
                if (port < 0x10000) {
                    unsigned int byteOffset = port >> 3;
                    unsigned int bitOffset = port & 7;
                    ((unsigned char *)ioBitmap)[byteOffset] |= (1 << bitOffset);
                }
            }
        }
    }

    // Copy input registers to emulator format
    for (i = 0; i < 16; i++) {
        regs[i] = ((unsigned int *)inregs)[i];
    }

    // Read saved values at top of scratch stack
    savedPort0 = *(unsigned int *)(mappedLowMem + physAddr + __page_size - 4);
    savedPort1 = *(unsigned int *)(mappedLowMem + physAddr + __page_size - 8);

    // Set up stack in scratch segment
    scratchSeg = physAddr >> 4;
    scratchSP = __page_size - 8;

    // Zero out stack area
    *(unsigned int *)((unsigned int)mappedLowMem + physAddr + __page_size - 4) = 0;
    *(unsigned int *)((unsigned int)mappedLowMem + physAddr + __page_size - 8) = 0;

    // Execute BIOS code via emulator
    result = _emu486((unsigned char *)mappedLowMem, regs, (unsigned int *)outregs,
                     (unsigned int)pageTable, (unsigned int)ioBitmap, smmPort);

    // Check for errors
    if (result != 0) {
        name = [self name];
        IOLog("%s: emu486 error %08x before %04x:%04x\n",
              name, result, outregs->cs, outregs->eip);
        IOLog("%s: eax=%08x ebx=%08x ecx=%08x edx=%08x\n",
              name, outregs->eax, outregs->ebx, outregs->ecx, outregs->edx);
        IOLog("%s: esi=%08x edi=%08x ebp=%08x esp=%08x\n",
              name, outregs->esi, outregs->edi, outregs->ebp, outregs->esp);
        IOLog("%s: ds=%04x es=%04x fs=%04x gs=%04x ss=%04x\n",
              name, outregs->ds, outregs->es, outregs->fs, outregs->gs, outregs->ss);
    }

    // Free I/O bitmap
    IOFree(ioBitmap, 0x2000);

    return result;
}

@end
