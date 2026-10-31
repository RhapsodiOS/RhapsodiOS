#import "IntelPRO10PCI.h"
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/ioPorts.h>
#import <mach/mach_interface.h>
#import <bsd/string.h>

extern unsigned int page_size;

static const char *connectorNames[] = {"AUTO", "BNC", "AUI", "RJ-45"};
static const char test_data_119[] = "Intel EtherExpress PRO/10 AutoConnectorDetect";

@implementation IntelPRO10PCI

+ (char)probe:(IODeviceDescription *)deviceDescription
{
    unsigned char device, function, bus;
    unsigned char configSpace[0x100];
    unsigned int command;
    IORange portRange;
    int interrupt;
    id instance;

    if ([deviceDescription getPCIDeviceFunction:&device
                                      function:&function
                                            bus:&bus] != IO_R_SUCCESS) {
        IOLog("%s: unsupported PCI hardware.\n", [self name]);
        return 0;
    }
    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", [self name], device, function, bus);

    if ([self getPCIConfigSpace:configSpace withDeviceDescription:deviceDescription] != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              [self name]);
        return 0;
    }
    if ([self getPCIConfigData:&command atRegister:4 withDeviceDescription:deviceDescription] != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              [self name]);
        return 0;
    }
    command |= 4;
    if ([self setPCIConfigData:command atRegister:4 withDeviceDescription:deviceDescription] != IO_R_SUCCESS) {
        IOLog("%s: Failed PCI configuration space access - aborting\n", [self name]);
        return 0;
    }

    portRange.start = *(unsigned int *)(configSpace + 0x14) & 0xfffffffcU;
    portRange.size = 64;
    if ([deviceDescription setPortRangeList:&portRange num:1] != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve port range 0x%x-0x%x - Aborting\n",
              [self name], portRange.start, portRange.start + 63);
        return 0;
    }

    interrupt = configSpace[0x3c];
    if ((unsigned int)interrupt - 2 > 13) {
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n", [self name], interrupt);
        return 0;
    }
    if ([deviceDescription setInterruptList:&interrupt num:1] != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve IRQ %d - Aborting\n", [self name], interrupt);
        return 0;
    }

    instance = [self alloc];
    if (instance == nil) {
        IOLog("%s: Failed to alloc instance\n", [self name]);
        return 0;
    }
    bcopy(configSpace + 0x60, &((IntelPRO10PCI *)instance)->myAddress, sizeof(enet_addr_t));
    ((IntelPRO10PCI *)instance)->RJ45Only = configSpace[0x67] == 2;
    return [instance initFromDeviceDescription:deviceDescription] != nil;
}

- (void)_setConnectorType:(int)type
{
    unsigned int value;

    connector = type;
    value = inl(ioBase + 4);
    if (type == 2)
        value = (value & 0xfffffffcU) | 2;
    else if (type == 1)
        value &= 0xfffffffcU;
    else
        value |= 3;
    outl(ioBase + 4, value);
}

- (void)doAutoConnectorDetect
{
    short *command;
    int i;

    sourceAddressInsertion = 1;
    if (![self config]) {
        IOLog("%s: connector test: configure failed", [self name]);
        return;
    }

    command = (short *)IOMalloc(page_size);
    bzero(command, 0x5f4);
    command[1] = (short)0x8004;
    *(unsigned int *)(command + 2) = 0xffffffffU;
    *(unsigned int *)(command + 4) = 0xffffffffU;
    command[6] = (short)0x8036;
    bcopy(&myAddress, command + 8, sizeof(myAddress));
    command[11] = 0x4444;
    bcopy(test_data_119, command + 12, strlen(test_data_119));

    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)command,
                              (unsigned int *)((char *)scb + 4)) != IO_R_SUCCESS) {
        IOLog("%s: Invalid auto-connect transmit command block address\n", [self name]);
        IOFree(command, page_size);
        return;
    }

    [self _setConnectorType:2];
    IOSleep(500);
    *(unsigned short *)((char *)scb + 2) = 0x100;
    [self sendChannelAttention];
    for (i = 0; i < 2000; ++i) {
        IODelay(1000);
        if (command[0] < 0)
            break;
    }
    if ((command[0] & 0xa000) == 0 || (command[0] & 0x0fa0) != 0) {
        [self _setConnectorType:1];
        IOSleep(500);
        *(unsigned short *)((char *)scb + 2) = 0x100;
        outl(ioBase + 32, 0);
        for (i = 0; i < 2000; ++i) {
            IODelay(1000);
            if (command[0] < 0)
                break;
        }
        if ((command[0] & 0xa000) == 0 || (command[0] & 0x0fa0) != 0)
            [self _setConnectorType:3];
    }

    [self clearIrqLatch];
    IOFree(command, page_size);
    sourceAddressInsertion = 0;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    id configTable;
    const char *configuredConnector;
    int index;

    ioBase = *(unsigned short *)[deviceDescription portRangeList];
    irq = [deviceDescription interrupt];
    if (RJ45Only) {
        connector = 3;
    } else {
        configTable = [deviceDescription configTable];
        configuredConnector = [configTable valueForString:"Connector"];
        connector = 0;
        if (configuredConnector != 0) {
            for (index = 0; index < 4; ++index) {
                if (strcmp(connectorNames[index], configuredConnector) == 0) {
                    connector = index;
                    break;
                }
            }
            [configTable freeString:configuredConnector];
        }
    }

    promiscuousEnabled = 0;
    multicastEnabled = 0;
    allMulticastEnabled = 0;
    multicastConfigured = 0;
    fullDuplexMode = 0;
    [self resetPLXchip];
    IOSleep(100);
    [self initPLXchip];
    IOSleep(50);
    self = [super initFromDeviceDescription:deviceDescription];
    if (self == nil || ![self coldInit] || ![self resetAndEnable:0])
        return nil;

    autoDetectedPort = 0;
    if (connector != 0) {
        [self _setConnectorType:connector];
    } else {
        autoDetectedPort = 1;
        [self doAutoConnectorDetect];
        if (![self resetAndEnable:0])
            return nil;
    }

    if (RJ45Only) {
        IOLog("%s: Intel EtherExpress PRO/10 PCI (RJ-45) port 0x%x irq %d\n",
              [self name], ioBase, irq);
    } else {
        IOLog("%s: Intel EtherExpress PRO/10 PCI port 0x%x irq %d %s %s\n",
              [self name], ioBase, irq, autoDetectedPort ? "auto-detected" : "using",
              connectorNames[connector]);
    }
    networkInterface = [super attachToNetworkWithAddress:myAddress];
    return self;
}

- (void)interruptOccurred
{
    unsigned short status = *(unsigned short *)scb;

    [self acknowledgeInterrupts:status];
    if (((status & 0x5000) == 0 || [self processRecInterrupt]) &&
        (activeTcbHead == nil || *(short *)activeTcbHead >= 0 || [self processXmtInterrupt])) {
        [self clearIrqLatch];
        [super enableAllInterrupts];
    }
}

- (void)clearIrqLatch
{
    unsigned int value = inl(ioBase);
    outl(ioBase, value | 0x10);
}

- (void)initPLXchip
{
    unsigned int value = inl(ioBase);
    value = (value & 0xfffffe00U) | ((value & 0xffU) | 0x28);
    outl(ioBase, value);
    value = inl(ioBase + 4);
    outl(ioBase + 4, (value & 0xffffff00U) | 0xf0);
}

- (void)resetPLXchip
{
    unsigned int value = inl(ioBase + 16);
    outl(ioBase + 16, value | 0x1000);
    IOSleep(50);
    value = inl(ioBase + 16);
    outl(ioBase + 16, value & 0xffffefffU);
}

- (void)sendPortCommand:(int)command with:(unsigned int)value
{
    outl(ioBase + 36, (value & 0xf0) | (command & 0xf));
}

- (void)sendChannelAttention
{
    outl(ioBase + 32, 0);
}

- (void)_enableAdapterInterrupts
{
    unsigned int value = inl(ioBase);
    value = (value | 0x100U) & ~0x20U;
    outl(ioBase, value);
}

- (void)_disableAdapterInterrupts
{
    unsigned int value = inl(ioBase);
    value = (value & ~0x100U) | 0x20U;
    outl(ioBase, value);
}

- (char)resetAndEnable:(char)enable
{
    sourceAddressInsertion = 0;
    [self clearTimeout];
    [self _disableAdapterInterrupts];
    [self disableAllInterrupts];
    if (![self hwInit] || ![self swInit])
        return 0;
    if (enable) {
        if ([self enableAllInterrupts] != 0) {
            [self setRunning:NO];
            return 0;
        }
        [self _enableAdapterInterrupts];
    }
    [self setRunning:enable];
    resetAndEnabled = 1;
    return 1;
}

@end
