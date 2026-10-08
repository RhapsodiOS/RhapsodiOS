/* Intel EtherExpress PRO/100 PCI adapter support. */

#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/ioPorts.h>

@implementation IntelPRO100PCI

/* Reference: 0x3858. */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    unsigned char device, function, bus;
    unsigned char configSpace[0x100];
    unsigned long command;
    IORange portRange;
    int interrupt;
    IntelPRO100PCI *driver;
    IOPCIDeviceDescription *pciDescription = (IOPCIDeviceDescription *)deviceDescription;

    if ([pciDescription getPCIdevice:&device function:&function bus:&bus] != IO_R_SUCCESS) {
        IOLog("%s: unsupported PCI hardware.\n", [self name]);
        return NO;
    }
    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", [self name], device, function, bus);

    if ([self getPCIConfigSpace:(IOPCIConfigSpace *)configSpace
         withDeviceDescription:pciDescription] != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              [self name]);
        return NO;
    }
    if ([self getPCIConfigData:&command atRegister:4
         withDeviceDescription:pciDescription] != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              [self name]);
        return NO;
    }
    command |= 4;
    if ([self setPCIConfigData:command atRegister:4
         withDeviceDescription:pciDescription] != IO_R_SUCCESS) {
        IOLog("%s: Failed PCI configuration space access - aborting\n", [self name]);
        return NO;
    }

    portRange.start = *(unsigned int *)(configSpace + 0x14) & 0xfffffffcU;
    portRange.size = 0x40;
    if ([pciDescription setPortRangeList:&portRange num:1] != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve port range 0x%x-0x%x - Aborting\n",
              [self name], portRange.start, portRange.start + 0x3f);
        return NO;
    }

    interrupt = configSpace[0x3c];
    if ((unsigned int)interrupt - 2 > 13) {
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n", [self name], interrupt);
        return NO;
    }
    if ([pciDescription setInterruptList:&interrupt num:1] != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve IRQ %d - Aborting\n", [self name], interrupt);
        return NO;
    }

    driver = [self alloc];
    if (driver == nil) {
        IOLog("%s: Failed to alloc instance\n", [self name]);
        return NO;
    }
    driver->myAddress = *(enet_addr_t *)(configSpace + 0x40);
    return [driver initFromDeviceDescription:deviceDescription] != nil;
}

/* Reference: 0x3ae4. */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOPCIDeviceDescription *pciDescription = (IOPCIDeviceDescription *)deviceDescription;

    ioBase = [pciDescription portRangeList]->start;
    irq = [deviceDescription interrupt];
    promiscuousEnabled = NO;
    multicastEnabled = NO;
    allMulticastEnabled = NO;
    multicastConfigured = NO;
    fullDuplexMode = NO;

    if ([super initFromDeviceDescription:deviceDescription] == nil ||
        ![self coldInit] || ![self resetAndEnable:NO])
        return nil;

    IOLog("%s: Intel EtherExpress PRO/100 PCI port 0x%x irq %d at %sMbits/s\n",
          [self name], ioBase, irq, dataRate ? "100" : "10");
    networkInterface = [super attachToNetworkWithAddress:myAddress];
    return self;
}

/* Reference: 0x3c14. */
- (void)clearIrqLatch
{
    unsigned int value = inl(ioBase);

    outl(ioBase, value | 0x10);
}

/* Reference: 0x3c30. */
- (void)interruptOccurred
{
    unsigned short status = scb_p->status;

    [self acknowledgeInterrupts:status];
    if ((status & 0x5000) &&
        ![self receiveInterruptOccurred:(status >> 12) & 1])
        return;
    if ((status & 0xa000) && ![self transmitInterruptOccurred])
        return;

    [self clearIrqLatch];
    [self enableAllInterrupts];
}

/* Reference: 0x3cb8. */
- (void)sendPortCommand:(int)command with:(unsigned int)argument
{
    outl(ioBase + 0x24, (argument & 0xfffffff0U) | (command & 0x0f));
}

/* Reference: 0x3ce8. */
- (void)sendChannelAttention
{
    outl(ioBase + 0x20, 0);
}

/* Reference: 0x3d08. */
- (void)initPLXchip
{
    unsigned int value;

    value = inl(ioBase);
    outl(ioBase, (value & 0xfffffeffU) | 0x28);
    value = inl(ioBase + 4);
    outl(ioBase + 4, (value & 0xffffff00U) | 0xf1);
}

/* Reference: 0x3d58; dword I/O and delay verified from assembly. */
- (void)resetPLXchip
{
    unsigned int value;

    value = inl(ioBase + 0x10);
    outl(ioBase + 0x10, value | 0x1000);
    IOSleep(50);
    value = inl(ioBase + 0x10);
    outl(ioBase + 0x10, value & 0xffffefffU);
}

/* Reference: 0x3d9c; read/delay/write order verified from assembly. */
- (void)lockDBRT
{
    unsigned int value;

    value = inl(ioBase + 4);
    value = (value | 2) & 0xfffffffbU;
    IOSleep(10);
    outl(ioBase + 4, value);
    IOSleep(50);
    value = inl(ioBase + 4);
    IOSleep(10);
    value = (value & 0xfffffffdU) | 4;
    outl(ioBase + 4, value);
    IOSleep(10);
}

/* Reference: 0x3e28. */
- (void)enableAdapterInterrupts
{
    unsigned int value = inl(ioBase);

    outl(ioBase, (value | 0x100) & 0xffffffdfU);
}

/* Reference: 0x3e48. */
- (void)disableAdapterInterrupts
{
    unsigned int value = inl(ioBase);

    outl(ioBase, (value & 0xfffffeffU) | 0x20);
}

@end
