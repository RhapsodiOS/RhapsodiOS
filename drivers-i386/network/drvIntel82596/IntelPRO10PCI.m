/*
 * IntelPRO10PCI.m
 * Intel PRO/10 PCI Ethernet Adapter Driver for Intel 82596
 * Uses PLX PCI-to-local bus bridge
 */

#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/i386/ioPorts.h>
#import <objc/objc-runtime.h>
#import <mach/mach_interface.h>
#import <bsd/string.h>

/* VM page size variable - from kernel */
extern unsigned int __page_size;

/* Forward declaration of Intel82596 base class */
@interface Intel82596 : IOEthernetDriver
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)clearIrqLatch;
- (void)sendChannelAttention;
- (void)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg;
- (void)interruptOccurred;
- (BOOL)resetAndEnable:(BOOL)enable;
- (const char *)name;
@end

/* PCI configuration space structure offsets */
#define PCI_CONFIG_BASE_ADDRESS_1   0x14  /* Base Address Register 1 */
#define PCI_CONFIG_INTERRUPT_LINE   0x3C  /* Interrupt Line */
#define PCI_CONFIG_COMMAND          0x04  /* Command register */
#define PCI_CONFIG_SUBSYSTEM_VENDOR 0x2C  /* Subsystem Vendor ID */
#define PCI_CONFIG_SUBSYSTEM_ID     0x2E  /* Subsystem ID */
#define PCI_CONFIG_REVISION_ID      0x08  /* Revision ID */

#define PCI_COMMAND_IO_ENABLE       0x01  /* Enable I/O space */
#define PCI_COMMAND_MEM_ENABLE      0x02  /* Enable memory space */
#define PCI_COMMAND_MASTER_ENABLE   0x04  /* Enable bus mastering */

@interface IntelPRO10PCI : Intel82596
{
    unsigned int ioBase;
    unsigned int irqLevel;
    unsigned int pciMemBase;
    unsigned int plxBase;
    unsigned int connectorType;
    BOOL autoDetectEnabled;
    BOOL plxInitialized;
    unsigned char romAddress[6];

    /* PCI configuration info - at specific offsets */
    unsigned int subsystemVendorId;    /* Offset 0x17c */
    unsigned short subsystemId;        /* Offset 0x180 */
    BOOL hasEEPROM;                    /* Offset 0x204 */
}

/* Probe and initialization */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/* Hardware control methods - override Intel82596 base methods */
- (void)clearIrqLatch;
- (void)sendChannelAttention;
- (void)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg;
- (void)interruptOccurred;
- (BOOL)resetAndEnable:(BOOL)enable;

/* PLX chip management */
- (void)initPLXchip;
- (void)resetPLXchip;

/* Connector management */
- (void)doAutoConnectorDetect;
- (void)_setConnectorType:(unsigned int)type;

/* Interrupt control */
- (void)_enableAdapterInterrupts;
- (void)_disableAdapterInterrupts;

@end

@implementation IntelPRO10PCI

/*
 * Probe for Intel PRO/10 PCI hardware
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    IOReturn result;
    unsigned char pciDevice, pciFunction, pciBus;
    unsigned char configSpace[256];
    unsigned int commandReg;
    unsigned int baseAddress1;
    unsigned char interruptLine;
    unsigned int subsystemVendor;
    unsigned short subsystemId;
    unsigned char revisionId;
    IORange portRange;
    unsigned int irqLevel;
    id instance;
    const char *driverName;

    /* Get PCI device, function, and bus numbers */
    result = [deviceDescription getPCIdevice:&pciDevice
                                   function:&pciFunction
                                        bus:&pciBus];
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: unsupported PCI hardware.\n", driverName);
        return NO;
    }

    driverName = [self name];
    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", driverName,
          pciDevice, pciFunction, pciBus);

    /* Read PCI configuration space */
    result = [self getPCIConfigSpace:configSpace
                withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              driverName);
        return NO;
    }

    /* Read command register */
    result = [self getPCIConfigData:&commandReg
                         atRegister:PCI_CONFIG_COMMAND
               withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              driverName);
        return NO;
    }

    /* Enable I/O space and bus mastering */
    commandReg |= PCI_COMMAND_MASTER_ENABLE;
    result = [self setPCIConfigData:commandReg
                         atRegister:PCI_CONFIG_COMMAND
               withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Failed PCI configuration space access - aborting\n", driverName);
        return NO;
    }

    /* Get base address register 1 (I/O ports) from config space */
    baseAddress1 = *(unsigned int *)(configSpace + PCI_CONFIG_BASE_ADDRESS_1);
    portRange.start = baseAddress1 & 0xfffffffc;
    portRange.size = 0x40;

    /* Reserve port range */
    result = [deviceDescription setPortRangeList:&portRange num:1];
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Unable to reserve port range 0x%x-0x%x - Aborting\n",
              driverName, portRange.start, portRange.start + 0x3f);
        return NO;
    }

    /* Get interrupt line */
    interruptLine = configSpace[PCI_CONFIG_INTERRUPT_LINE];
    irqLevel = interruptLine;

    /* Validate IRQ level (must be 2-15) */
    if (irqLevel < 2 || irqLevel > 15) {
        driverName = [self name];
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n",
              driverName, irqLevel);
        return NO;
    }

    /* Reserve interrupt */
    result = [deviceDescription setInterruptList:&irqLevel num:1];
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Unable to reserve IRQ %d - Aborting\n", driverName, irqLevel);
        return NO;
    }

    /* Allocate driver instance */
    instance = [self alloc];
    if (instance == nil) {
        driverName = [self name];
        IOLog("%s: Failed to alloc instance\n", driverName);
        return NO;
    }

    /* Store PCI configuration data in instance variables */
    /* These are at specific offsets in the object structure */
    subsystemVendor = *(unsigned int *)(configSpace + PCI_CONFIG_SUBSYSTEM_VENDOR);
    subsystemId = *(unsigned short *)(configSpace + PCI_CONFIG_SUBSYSTEM_ID);
    revisionId = configSpace[PCI_CONFIG_REVISION_ID];

    ((IntelPRO10PCI *)instance)->subsystemVendorId = subsystemVendor;
    ((IntelPRO10PCI *)instance)->subsystemId = subsystemId;
    ((IntelPRO10PCI *)instance)->hasEEPROM = (revisionId == 0x02);

    /* Initialize from device description */
    instance = [instance initFromDeviceDescription:deviceDescription];

    return (instance != nil);
}

/*
 * Initialize from device description
 * Complete initialization for Intel PRO/10 PCI adapter
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IORange *portRange;
    const char *connectorNames[] = {"AUTO", "BNC", "AUI", "RJ-45"};
    const char *connectorString;
    id propertyTable;
    int i;
    id netif;

    /* Get I/O port range from device description */
    portRange = (IORange *)[deviceDescription portRangeList];
    ioBase = portRange->start;

    /* Get interrupt level from device description */
    irqLevel = [deviceDescription interrupt];

    /* Determine connector type based on hasEEPROM flag */
    if (!hasEEPROM) {
        /* Get property table from device description */
        propertyTable = [deviceDescription propertyTable];

        /* Look up "Connector" property */
        connectorString = [propertyTable valueForStringKey:"Connector"];

        /* Default to AUTO (0) */
        connectorType = 0;

        if (connectorString != NULL) {
            /* Parse connector type string */
            for (i = 0; i < 4; i++) {
                if (strcmp(connectorNames[i], connectorString) == 0) {
                    connectorType = i;
                    break;
                }
            }
            /* Free the string */
            [propertyTable freeString:connectorString];
        }
    } else {
        /* Adapter has EEPROM - force RJ-45 */
        connectorType = 3;
    }

    /* Initialize statistics counters (offsets 0x194-0x197) */
    *((unsigned char *)self + 0x194) = 0;
    *((unsigned char *)self + 0x195) = 0;
    *((unsigned char *)self + 0x196) = 0;
    *((unsigned char *)self + 0x197) = 0;

    /* Initialize flag at offset 0x1fc */
    *((unsigned char *)self + 0x1fc) = 0;

    /* Reset PLX chip */
    [self resetPLXchip];
    IOSleep(100);  /* 100ms delay */

    /* Initialize PLX chip */
    [self initPLXchip];
    IOSleep(50);   /* 50ms delay */

    /* Call superclass initialization */
    self = [super initFromDeviceDescription:deviceDescription];
    if (self == nil) {
        return nil;
    }

    /* Perform cold initialization */
    if (![self coldInit]) {
        [self free];
        return nil;
    }

    /* Reset and enable the adapter */
    if (![self resetAndEnable:NO]) {
        [self free];
        return nil;
    }

    /* Initialize auto-detect flag */
    autoDetectEnabled = NO;

    /* Handle connector configuration */
    if (connectorType == 0) {
        /* AUTO connector - perform auto-detection */
        autoDetectEnabled = YES;
        [self doAutoConnectorDetect];

        /* Reset and enable again after auto-detect */
        if (![self resetAndEnable:NO]) {
            [self free];
            return nil;
        }
    } else {
        /* Set specified connector type */
        [self _setConnectorType:connectorType];
    }

    /* Log adapter information */
    if (!hasEEPROM) {
        /* Log with connector type and auto-detect status */
        IOLog("%s: Intel EtherExpress PRO/10 PCI port 0x%x irq %d %s %s\n",
              [self name],
              ioBase,
              irqLevel,
              autoDetectEnabled ? "autodetected" : "configured",
              connectorNames[connectorType]);
    } else {
        /* Log for EEPROM version (always RJ-45) */
        IOLog("%s: Intel EtherExpress PRO/10 PCI (RJ-45) port 0x%x irq %d\n",
              [self name],
              ioBase,
              irqLevel);
    }

    /* Attach to network with MAC address */
    netif = [super attachToNetworkWithAddress:romAddress];
    *((id *)self + (0x188 / sizeof(id))) = netif;

    return self;
}

/*
 * Clear interrupt latch
 * PRO/10 PCI clears interrupt by setting bit 4 at base I/O port
 */
- (void)clearIrqLatch
{
    unsigned int regValue;

    /* Read control register from base I/O port */
    regValue = inb(ioBase);

    /* Set bit 4 to clear interrupt latch */
    outb(ioBase, regValue | 0x10);

    /* Increment counter (atomic operation) */
    _interrupt_control_count++;
}

/*
 * Send channel attention to 82596
 * Triggers via writing to port offset 0x20
 */
- (void)sendChannelAttention
{
    /* Write 0 to ioBase + 0x20 to trigger channel attention */
    outb(ioBase + 0x20, 0);

    /* Increment counter (atomic operation) */
    _interrupt_control_count++;
}

/*
 * Send port command to 82596
 * Sends PORT command with argument via PLX bridge
 */
- (void)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg
{
    unsigned short port;
    unsigned char value;

    /* Port command is sent to ioBase + 0x24 */
    port = ioBase + 0x24;

    /* Combine argument (upper bits) with command (lower 4 bits) */
    value = (arg & 0xfffffff0) | (cmd & 0xf);

    /* Write port command */
    outb(port, value);

    /* Increment counter (atomic operation) */
    _interrupt_control_count++;
}

/*
 * Handle interrupt
 * PRO/10 PCI interrupt handler with superclass enableAllInterrupts call
 */
- (void)interruptOccurred
{
    unsigned short scbStatus;

    /* Read SCB status word */
    scbStatus = *(unsigned short *)(*((unsigned int *)self + (0x1bc / sizeof(unsigned int))));

    /* Acknowledge interrupts */
    [self acknowledgeInterrupts:scbStatus];

    /* Process receive interrupt if FR (bit 14) or RNR (bit 12) set */
    if ((scbStatus & 0x5000) != 0) {
        if (![self processRecInterrupt]) {
            return;
        }
    }

    /* Process transmit interrupt if TCB completed */
    if ((*((void **)self + (0x1cc / sizeof(void *)))) != NULL) {
        if (*(short *)(*((void **)self + (0x1cc / sizeof(void *)))) < 0) {  /* Command complete bit */
            if (![self processXmtInterrupt]) {
                return;
            }
        }
    }

    /* Clear IRQ latch */
    [self clearIrqLatch];

    /* Enable all interrupts via superclass method */
    [super enableAllInterrupts];
}

/*
 * Reset and enable the adapter
 * PRO/10 PCI-specific reset sequence with PLX interrupt control
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    /* Clear auto-detect flag at offset 0x198 */
    *((unsigned char *)self + 0x198) = 0;

    /* Clear any pending timeout */
    [self clearTimeout];

    /* Disable adapter interrupts via PLX bridge */
    [self _disableAdapterInterrupts];

    /* Disable all 82596 interrupts */
    [self disableAllInterrupts];

    /* Perform hardware initialization */
    if (![self hwInit]) {
        return NO;
    }

    /* Perform software initialization */
    if (![self swInit]) {
        return NO;
    }

    /* If enable flag is set, enable interrupts */
    if (enable) {
        /* Enable all 82596 interrupts */
        if ([self enableAllInterrupts] != 0) {
            /* enableAllInterrupts failed, set running to NO */
            [self setRunning:NO];
            return NO;
        }

        /* Enable adapter interrupts via PLX bridge */
        [self _enableAdapterInterrupts];
    }

    /* Set running state */
    [self setRunning:enable];

    /* Set flag at offset 0x199 */
    *((unsigned char *)self + 0x199) = 1;

    return YES;
}

/*
 * Initialize PLX PCI-to-local bus bridge chip
 * Configures PLX chip for proper operation
 */
- (void)initPLXchip
{
    unsigned int regValue;
    unsigned short port;

    /* Configure base control register */
    regValue = inb(ioBase);
    /* Clear bit 8, set bits 5 and 3 */
    outb(ioBase, (regValue & 0xfffffeff) | 0x28);

    /* Configure control register at ioBase + 4 */
    port = ioBase + 4;
    regValue = inb(port);
    /* Set low byte to 0xf0 */
    outb(port, 0xf0);

    /* Increment counter (atomic operation) */
    _interrupt_control_count += 2;

    /* Mark PLX as initialized */
    plxInitialized = YES;
}

/*
 * Reset PLX chip
 * Resets PLX bridge by toggling bit 12 at port offset 0x10
 */
- (void)resetPLXchip
{
    unsigned int regValue;
    unsigned short port;

    /* Set bit 12 to enter reset */
    port = ioBase + 0x10;
    regValue = inb(port);
    outb(port, regValue | 0x1000);
    _interrupt_control_count++;

    /* Wait 50ms for reset to take effect */
    IOSleep(50);

    /* Clear bit 12 to exit reset */
    port = ioBase + 0x10;
    regValue = inb(port);
    outb(port, regValue & 0xffffefff);
    _interrupt_control_count++;

    /* Mark PLX as not initialized */
    plxInitialized = NO;
}

/*
 * Auto-detect connector type
 * Tests AUI, BNC, then defaults to RJ-45
 */
- (void)doAutoConnectorDetect
{
    unsigned short *testTCB;
    const char *testString = "Intel EtherExpress PRO/10 AutoConnectorDetect";
    int stringLen;
    IOReturn result;
    vm_task_t task;
    unsigned int physAddr;
    int i;
    BOOL linkDetected;

    /* Set auto-detect flag at offset 0x198 */
    *((unsigned char *)self + 0x198) = 1;

    /* Configure the adapter */
    if (![self config]) {
        IOLog("%s: connector test: configure failed\n", [self name]);
        *((unsigned char *)self + 0x198) = 0;
        return;
    }

    /* Allocate page-sized buffer for test TCB */
    testTCB = (unsigned short *)IOMalloc(__page_size);
    if (testTCB == NULL) {
        *((unsigned char *)self + 0x198) = 0;
        return;
    }

    /* Zero the buffer (0x5f4 bytes) */
    bzero(testTCB, 0x5f4);

    /* Initialize test TCB structure */
    testTCB[1] = 0x8004;  /* Command: Transmit with interrupt */
    testTCB[2] = 0xffff;  /* TBD pointer (none) */
    testTCB[3] = 0xffff;
    testTCB[4] = 0xffff;  /* Destination MAC (broadcast) */
    testTCB[5] = 0xffff;
    testTCB[6] = 0x8036;  /* Source MAC first word + count */

    /* Copy source MAC address from romAddress */
    *(unsigned int *)(&testTCB[8]) = *(unsigned int *)romAddress;
    testTCB[10] = *(unsigned short *)(&romAddress[4]);

    /* Set packet length */
    testTCB[0xb] = 0x4444;

    /* Copy test string */
    stringLen = strlen(testString);
    bcopy(testString, &testTCB[0xc], stringLen);

    /* Get physical address of command word for 82596 */
    task = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(task, (unsigned int)&testTCB[1], &physAddr);

    if (result != IO_R_SUCCESS) {
        IOLog("%s: Invalid auto-connect transmit command block address\n", [self name]);
        IOFree(testTCB, __page_size);
        *((unsigned char *)self + 0x198) = 0;
        return;
    }

    /* Test connector type 2 (AUI) */
    [self _setConnectorType:2];
    IOSleep(500);  /* 500ms delay */

    /* Issue transmit command */
    *(unsigned short *)(*((unsigned int *)self + (0x1bc / sizeof(unsigned int))) + 2) = 0x100;  /* CU_START */
    [self sendChannelAttention];

    /* Wait for completion (up to 2 seconds) */
    linkDetected = NO;
    for (i = 0; i < 2000; i++) {
        IODelay(1000);  /* 1ms delay */
        if (testTCB[0] & 0x8000) {  /* Command complete */
            break;
        }
    }

    /* Check if command completed successfully */
    if (((testTCB[0] & 0xa000) != 0) && ((testTCB[0] & 0x4000) == 0)) {
        linkDetected = YES;  /* AUI has link */
    }

    if (!linkDetected) {
        /* Test connector type 1 (BNC) */
        testTCB[0] = 0;  /* Reset status */
        [self _setConnectorType:1];
        IOSleep(500);  /* 500ms delay */

        /* Issue transmit command */
        *(unsigned short *)(*((unsigned int *)self + (0x1bc / sizeof(unsigned int))) + 2) = 0x100;  /* CU_START */

        /* Trigger channel attention via alternate port (ioBase + 0x20) */
        outb(ioBase + 0x20, 0);
        _interrupt_control_count++;

        /* Wait for completion (up to 2 seconds) */
        for (i = 0; i < 2000; i++) {
            IODelay(1000);  /* 1ms delay */
            if (testTCB[0] & 0x8000) {  /* Command complete */
                break;
            }
        }

        /* Check if command completed successfully */
        if (((testTCB[0] & 0xa000) != 0) && ((testTCB[0] & 0x4000) == 0)) {
            linkDetected = YES;  /* BNC has link */
        }

        if (!linkDetected) {
            /* Default to connector type 3 (RJ-45) */
            [self _setConnectorType:3];
        }
    }

    /* Clear interrupt latch */
    [self clearIrqLatch];

    /* Free test TCB */
    IOFree(testTCB, __page_size);

    /* Clear auto-detect flag */
    *((unsigned char *)self + 0x198) = 0;
}

/*
 * Set connector type (private method)
 * Configures hardware for selected connector (BNC, AUI, or RJ-45)
 */
- (void)_setConnectorType:(unsigned int)type
{
    unsigned int regValue;

    /* Store connector type */
    connectorType = type;

    /* Read control register at ioBase + 4 */
    regValue = inb(ioBase + 4);

    /* Configure connector type bits (0-1) based on type */
    if (type == 2) {
        /* Type 2 (AUI): Clear bit 0, set bit 1 */
        regValue = (regValue & 0xfffffffe) | 2;
    } else if (type == 1) {
        /* Type 1 (BNC): Clear bits 0-1 */
        regValue = regValue & 0xfffffffc;
    } else {
        /* Type 3 (RJ-45) or other: Set bits 0-1 */
        regValue = regValue | 3;
    }

    /* Write back to control register */
    outb(ioBase + 4, regValue);

    /* Increment counter (atomic operation) */
    _interrupt_control_count++;
}

/*
 * Enable adapter interrupts (private method)
 * Enables interrupts via PLX bridge control register
 */
- (void)_enableAdapterInterrupts
{
    unsigned int regValue;

    /* Read current control register value */
    regValue = inb(ioBase);

    /* Clear bit 5 and set bit 8 to enable interrupts */
    regValue = (regValue & 0xffffffdf) | 0x100;

    /* Write back to control register */
    outb(ioBase, regValue);

    /* Increment counter (atomic operation) */
    _interrupt_control_count++;
}

/*
 * Disable adapter interrupts (private method)
 * Disables interrupts via PLX bridge control register
 */
- (void)_disableAdapterInterrupts
{
    unsigned int regValue;

    /* Read current control register value */
    regValue = inb(ioBase);

    /* Clear bit 8 and set bit 5 to disable interrupts */
    regValue = (regValue & 0xfffffeff) | 0x20;

    /* Write back to control register */
    outb(ioBase, regValue);

    /* Increment counter (atomic operation) */
    _interrupt_control_count++;
}

@end

/*
 * C function implementations for hardware access
 */

/* IRQ lookup tables for different adapter types */
static unsigned char plxirq[4] = {5, 9, 10, 11};     /* PLX-based adapters */
static unsigned char fleairq[4] = {3, 7, 12, 15};    /* Flash32 adapters */

/* Synchronization counters */
static volatile unsigned int _connector_change_count = 0;
static volatile unsigned int _interrupt_control_count = 0;

/*
 * Get card IRQ from hardware registers
 * Reads IRQ configuration from adapter registers
 */
unsigned char _card_irq(unsigned short ioBase)
{
    unsigned char regValue;
    unsigned char irqIndex;

    /* Read control register at offset 0x430 */
    regValue = inb(ioBase + 0x430);

    /* Check bit 7 to determine adapter type */
    if ((regValue & 0x80) == 0) {
        /* PLX-based adapter - read from offset 0xc88 */
        regValue = inb(ioBase + 0xc88);
        irqIndex = (regValue >> 1) & 0x3;
        return plxirq[irqIndex];
    } else {
        /* Flash32 adapter - read from offset 0x430 */
        regValue = inb(ioBase + 0x430);
        irqIndex = (regValue >> 1) & 0x3;
        return fleairq[irqIndex];
    }
}

/*
 * Get connector type from hardware
 * Returns connector type bits (0-3)
 */
unsigned char _get_connector_type(unsigned short ioBase)
{
    unsigned char regValue;

    /* Read connector configuration register */
    regValue = inb(ioBase + 0xc89);

    /* Return only the connector type bits (bits 0-1) */
    return regValue & 0x3;
}

/*
 * Set connector type in hardware
 * Writes connector type to hardware register
 */
unsigned char _set_connector_type(unsigned short ioBase, unsigned char connectorType)
{
    unsigned char regValue;

    /* Read current register value */
    regValue = inb(ioBase + 0xc89);

    /* Modify only the connector type bits (0-1) */
    regValue = (connectorType & 0x3) | (regValue & 0xfc);

    /* Write back to hardware */
    outb(ioBase + 0xc89, regValue);

    /* Increment change counter (with synchronization) */
    /* Note: Original code had LOCK/UNLOCK, but we'll use atomic increment */
    _connector_change_count++;

    return regValue;
}
