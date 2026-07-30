#import "AHCIPort.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/kernelDriver.h>
#import <mach/mach_interface.h>
#import <string.h>

extern unsigned int vm_page_size;

static int AHCIPortMMIOValid(AHCIMMIOContext *context, AHCIU32 offset)
{
    return context != 0 && context->base != 0 &&
           context->length >= sizeof(AHCIU32) && (offset & 3U) == 0 &&
           offset <= context->length - sizeof(AHCIU32);
}

static AHCIU32 AHCIPortMMIORead(void *context, AHCIU32 offset)
{
    AHCIMMIOContext *mapped;

    mapped = (AHCIMMIOContext *)context;
    if (!AHCIPortMMIOValid(mapped, offset))
        return 0xffffffffU;
    return *(volatile AHCIU32 *)(mapped->base + offset);
}

static void AHCIPortMMIOWrite(void *context, AHCIU32 offset,
                              AHCIU32 value)
{
    AHCIMMIOContext *mapped;

    mapped = (AHCIMMIOContext *)context;
    if (!AHCIPortMMIOValid(mapped, offset))
        return;
    *(volatile AHCIU32 *)(mapped->base + offset) = value;
}

static void AHCIPortMMIOBarrier(void *context)
{
    volatile AHCIU32 readback;

    readback = AHCIPortMMIORead(context, AHCI_REG_GHC);
    (void)readback;
}

static void AHCIPortDelayMilliseconds(void *context,
                                      unsigned int milliseconds)
{
    (void)context;
    IOSleep(milliseconds);
}

static int AHCIPortTranslateAddress(void *context,
                                    unsigned long virtualAddress,
                                    AHCIU32 *physicalAddress)
{
    vm_offset_t physical;

    (void)context;
    if (physicalAddress == 0 ||
        IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)virtualAddress,
                              &physical) != IO_R_SUCCESS)
        return 0;
    *physicalAddress = (AHCIU32)physical;
    return (vm_offset_t)*physicalAddress == physical;
}

static void AHCIPortFillOps(AHCIPortOps *ops, AHCIMMIOContext *context)
{
    ops->context = context;
    ops->read = AHCIPortMMIORead;
    ops->write = AHCIPortMMIOWrite;
    ops->delay = AHCIPortDelayMilliseconds;
    ops->barrier = AHCIPortMMIOBarrier;
}

@implementation AHCIPort

- initWithMMIO:(AHCIMMIOContext *)context
           port:(unsigned int)number
   capabilities:(AHCIU32)capabilities
{
    AHCIPortOps ops;
    AHCIPortResult result;
    AHCICommandHeader *commandList;

    self = [super init];
    if (self == nil)
        return nil;
    if (context == 0 || number >= 32U || vm_page_size < 1024U ||
        (vm_page_size & (vm_page_size - 1U)) != 0) {
        [self free];
        return nil;
    }
    mmio = context;
    portNumber = number;
    rawArenaBytes = AHCI_PORT_ARENA_USABLE_BYTES + vm_page_size - 1U;
    rawArena = IOMallocLow(rawArenaBytes);
    if (rawArena == 0) {
        [self free];
        return nil;
    }
    result = AHCIPortPrepareArena((unsigned long)rawArena, rawArenaBytes,
                                  vm_page_size, AHCIPortTranslateAddress, 0,
                                  &arena);
    if (result != AHCI_PORT_SUCCESS) {
        [self free];
        return nil;
    }
    bzero((void *)arena.virtualBase, arena.usableBytes);
    commandList = (AHCICommandHeader *)
                  (arena.virtualBase + arena.commandListOffset);
    commandList[0].ctba = arena.physicalBase + arena.commandTableOffset;
    commandList[0].ctbau = 0;

    AHCIPortFillOps(&ops, mmio);
    hardwareTouched = YES;
    result = AHCIPortInitializeHardware(&ops, portNumber, capabilities,
                                        &arena, &deviceKind);
    if (result != AHCI_PORT_SUCCESS) {
        [self free];
        return nil;
    }
    return self;
}

- free
{
    AHCIPortOps ops;
    AHCIPortResult stopResult;

    stopResult = AHCI_PORT_SUCCESS;
    if (hardwareTouched && mmio != 0 && mmio->base != 0) {
        AHCIPortFillOps(&ops, mmio);
        stopResult = AHCIPortStopHardware(&ops, portNumber);
        hardwareTouched = NO;
    }
    if (AHCIPortArenaMayRelease(stopResult) && rawArena != 0) {
        IOFreeLow(rawArena, rawArenaBytes);
        rawArena = 0;
        rawArenaBytes = 0;
    } else if (rawArena != 0) {
        IOLog("AHCI: port %u engine did not stop; preserving DMA arena\n",
              portNumber);
    }
    mmio = 0;
    return [super free];
}

- (unsigned int)portNumber
{
    return portNumber;
}

- (AHCIDeviceKind)deviceKind
{
    return deviceKind;
}

- (void)handleInterrupt
{
    AHCIU32 base;
    AHCIU32 status;
    AHCIU32 error;

    if (mmio == 0 || mmio->base == 0)
        return;
    base = AHCI_PORT_BASE(portNumber);
    status = AHCIPortMMIORead(mmio, base + AHCI_PX_IS);
    if ((status & AHCI_PORT_INITIAL_IE_MASK) == 0)
        return;
    error = AHCIPortMMIORead(mmio, base + AHCI_PX_SERR);
    AHCIPortMMIOWrite(mmio, base + AHCI_PX_IS,
                      status & AHCI_PORT_INITIAL_IE_MASK);
    if (error != 0)
        AHCIPortMMIOWrite(mmio, base + AHCI_PX_SERR, error);
    AHCIPortMMIOBarrier(mmio);
}

@end
