/*
 * IntelEEFlash32.m
 * Intel EtherExpress Flash32 Ethernet Adapter Driver for Intel 82596
 */

#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEISADeviceDescription.h>
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
- (void)setIOBase:(unsigned int)base;
@end

@interface IntelEEFlash32 : Intel82596
{
    unsigned int ioBase;
    unsigned int irqLevel;
    unsigned int flashRomBase;
    unsigned int connectorType;
    BOOL autoDetectEnabled;
    unsigned char romAddress[6];
}

/* Probe and initialization */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/* Hardware control methods - override Intel82596 base methods */
- (void)clearIrqLatch;
- (void)sendChannelAttention;
- (void)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg;
- (void)interruptOccurred;

/* Flash32 specific methods */
- (BOOL)checksum_OK:(unsigned char *)data;
- (void)doAutoConnectorDetect;

@end

/* Synchronization counters */
static volatile unsigned int _clearIrqCount = 0;
static volatile unsigned int _sendCACount = 0;
static volatile unsigned int _sendPortCmdCount = 0;

/* Connector type names for logging */
static const char *_connector_text[] = {
    "BNC",      /* Type 0 */
    "n/a",      /* Type 1 */
    "AUI",      /* Type 2 */
    "TPE"       /* Type 3 */
};

/* External C functions */
extern unsigned char _card_irq(unsigned short ioBase);
extern unsigned char _get_connector_type(unsigned short ioBase);
extern unsigned char _set_connector_type(unsigned short ioBase, unsigned char type);

@implementation IntelEEFlash32

/*
 * Probe for Intel EtherExpress Flash32 hardware
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id instance;
    unsigned int slotNumber;
    IOReturn result;

    /* Allocate an instance */
    instance = [self alloc];
    if (instance == nil) {
        return NO;
    }

    /* Get EISA slot number */
    result = [deviceDescription getEISASlotNumber:&slotNumber];
    if (result != IO_R_SUCCESS) {
        IOLog("EEFlash32: couldn't get slot number\n");
        [instance free];
        return NO;
    }

    /* Set IO base address based on slot number */
    [instance setIOBase:((slotNumber & 0xf) << 12)];

    /* Initialize from device description */
    instance = [instance initFromDeviceDescription:deviceDescription];

    return (instance != nil);
}

/*
 * Initialize from device description
 * Complete initialization for Intel EtherExpress Flash32 adapter
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOReturn result;
    unsigned char slotID[4];
    unsigned char regValue;
    unsigned int eepromData;
    int i;
    id transmitQueue;
    id netif;

    /* Get EISA slot ID */
    result = [deviceDescription getEISASlotID:slotID];
    if (result != IO_R_SUCCESS) {
        IOLog("EEFlash32: failed to retrieve eisa id\n");
        [self free];
        return nil;
    }

    /* Read IRQ from hardware using external function */
    irqLevel = _card_irq(ioBase);

    /* Set interrupt list in device description */
    result = [deviceDescription setInterruptList:&irqLevel num:1];
    if (result != IO_R_SUCCESS) {
        IOLog("EEFlash32: failed to add irq\n");
        [self free];
        return nil;
    }

    /* Read MAC address from EEPROM (ports 0xc90-0xc95) */
    for (i = 0; i < 6; i++) {
        romAddress[i] = inb(ioBase + 0xc90 + i);
    }

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

    /* Read EEPROM data for checksum verification */
    eepromData = 0;  /* Read from EEPROM - exact location TBD */

    /* Verify EEPROM checksum */
    if (![self checksum_OK:eepromData]) {
        IOLog("EEFLash32: invalid checksum\n");
        [self free];
        return nil;
    }

    /* Check interrupt latch configuration at port 0x430 */
    regValue = inb(ioBase + 0x430);
    if ((regValue & 8) == 0) {
        /* Interrupts not latched - enable latching */
        outb(ioBase + 0x430, regValue | 8);
        _clearIrqCount++;
        IOLog("interrupts NOT latched - now latched\n");
    }

    /* Check PLX latch configuration at port 0xc88 */
    regValue = inb(ioBase + 0xc88);
    if (regValue & 8) {
        /* PLX is latched - set to non-latched */
        outb(ioBase + 0xc88, regValue & 0xf7);
        _clearIrqCount++;
        IOLog("Set plx latched to non-latched\n");
    }

    /* Initialize flag at offset 0x1fc */
    *((unsigned char *)self + 0x1fc) = 0;

    /* Reset and enable the adapter */
    if (![self resetAndEnable:NO]) {
        [self free];
        return nil;
    }

    /* Initialize statistics counters (offsets 0x194-0x197) */
    *((unsigned char *)self + 0x194) = 0;
    *((unsigned char *)self + 0x195) = 0;
    *((unsigned char *)self + 0x196) = 0;
    *((unsigned char *)self + 0x197) = 0;

    /* Create transmit queue with max count of 80 (0x50) */
    transmitQueue = [[objc_getClass("IONetbufQueue") alloc] initWithMaxCount:0x50];
    if (transmitQueue == nil) {
        [self free];
        return nil;
    }
    *((id *)self + 100) = transmitQueue;  /* Offset 400 bytes / sizeof(id) = 100 */

    /* Check if auto-connector detect is needed (port 0x410 bit 3) */
    regValue = inb(ioBase + 0x410);
    if ((regValue ^ 8) & 8) {
        /* Bit 3 is not set - perform auto-detect */
        [self doAutoConnectorDetect];

        /* Reset and enable again after auto-detect */
        if (![self resetAndEnable:NO]) {
            [self free];
            return nil;
        }
    }

    /* Log adapter information */
    connectorType = _get_connector_type(ioBase);
    IOLog("Intel EtherExpress Flash32 in slot %d irq %d using %s connector\n",
          (ioBase >> 12),
          irqLevel,
          _connector_text[connectorType]);

    /* Attach to network with MAC address */
    netif = [super attachToNetworkWithAddress:romAddress];
    *((id *)self + (0x188 / sizeof(id))) = netif;

    return self;
}

/*
 * Clear interrupt latch
 * Flash32 boards require clearing latches at two ports
 */
- (void)clearIrqLatch
{
    unsigned short port;
    unsigned char regValue;

    /* Clear bit 4 at port 0x430 */
    port = ioBase + 0x430;
    regValue = inb(port);
    outb(port, regValue & 0xef);

    /* Clear bit 4 at port 0xc88 (PLX bridge) */
    port = ioBase + 0xc88;
    regValue = inb(port);
    outb(port, regValue & 0xef);

    /* Increment counter (atomic operation) */
    _clearIrqCount += 2;
}

/*
 * Send channel attention to 82596
 * Triggers channel attention by writing to base I/O port
 */
- (void)sendChannelAttention
{
    /* Write 0 to base I/O port to trigger channel attention */
    outb(ioBase, 0);

    /* Increment counter (atomic operation) */
    _sendCACount++;
}

/*
 * Send port command to 82596
 * Sends PORT command with argument to the controller
 */
- (void)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg
{
    unsigned short port;
    unsigned char value;

    /* Port command is sent to base + 8 */
    port = ioBase + 8;

    /* Combine argument (upper bits) with command (lower 4 bits) */
    value = (arg & 0xfffffff0) | (cmd & 0xf);

    /* Write port command */
    outb(port, value);

    /* Increment counter (atomic operation) */
    _sendPortCmdCount++;
}

/*
 * Handle interrupt
 * Flash32-specific interrupt handling with port 0x430 manipulation
 */
- (void)interruptOccurred
{
    unsigned short scbStatus;
    unsigned short port;
    unsigned char regValue;

    /* Read SCB status word */
    scbStatus = *(unsigned short *)(*((unsigned int *)self + (0x1bc / sizeof(unsigned int))));

    /* Set bit 5 at port 0x430 before interrupt processing */
    port = ioBase + 0x430;
    regValue = inb(port);
    outb(port, regValue | 0x20);
    _clearIrqCount++;

    /* Acknowledge interrupts */
    [self acknowledgeInterrupts:scbStatus];

    /* Process receive interrupt if FR (bit 14) or RNR (bit 12) set */
    if ((scbStatus & 0x5000) != 0) {
        if (![self processRecInterrupt]) {
            /* Clear bit 5 at port 0x430 before returning */
            [self clearIrqLatch];
            port = ioBase + 0x430;
            regValue = inb(port);
            outb(port, regValue & 0xdf);
            _clearIrqCount++;
            return;
        }
    }

    /* Process transmit interrupt if TCB completed */
    if ((*((void **)self + (0x1cc / sizeof(void *)))) != NULL) {
        if (*(short *)(*((void **)self + (0x1cc / sizeof(void *)))) < 0) {  /* Command complete bit */
            if (![self processXmtInterrupt]) {
                /* Clear bit 5 at port 0x430 before returning */
                [self clearIrqLatch];
                port = ioBase + 0x430;
                regValue = inb(port);
                outb(port, regValue & 0xdf);
                _clearIrqCount++;
                return;
            }
        }
    }

    /* Clear IRQ latch */
    [self clearIrqLatch];

    /* Clear bit 5 at port 0x430 after interrupt processing */
    port = ioBase + 0x430;
    regValue = inb(port);
    outb(port, regValue & 0xdf);
    _clearIrqCount++;
}

/*
 * Verify EEPROM checksum
 * Checksum validation for EEPROM data
 */
- (BOOL)checksum_OK:(unsigned int)eepromData
{
    unsigned char byte1, byte2;
    unsigned char macByte;
    int i;
    int sum;

    /* Read checksum bytes from EEPROM */
    byte1 = inb(ioBase + 0xc97);
    byte2 = inb(ioBase + 0xc96);

    /* Sum all MAC address bytes (ports 0xc90-0xc95) */
    sum = 0;
    for (i = 0; i < 6; i++) {
        macByte = inb(ioBase + 0xc90 + i);
        sum += macByte;
    }

    /* Combine checksum bytes and add to sum */
    sum += (byte2 | (byte1 << 8));

    /* Add all bytes from eepromData parameter */
    sum += (eepromData & 0xff);
    sum += ((eepromData >> 8) & 0xff);
    sum += ((eepromData >> 16) & 0xff);
    sum += (eepromData >> 24);

    /* Checksum is valid if sum equals zero */
    return (sum == 0);
}

/*
 * Auto-detect connector type
 * Tests each connector type to find one with link
 */
- (void)doAutoConnectorDetect
{
    unsigned short *testTCB;
    const char *testString = "IntelEtherExpressFlash32 AutoConnectorDetect";
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
        IOLog("EEFlash32: connector test: configure failed\n");
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

    /* Test connector type 3 (TPE - Twisted Pair Ethernet) */
    _set_connector_type(ioBase, 3);
    IODelay(500000);  /* 500ms delay */

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
        linkDetected = YES;  /* TPE has link */
    }

    if (!linkDetected) {
        /* Test connector type 0 (BNC) */
        testTCB[0] = 0;  /* Reset status */
        _set_connector_type(ioBase, 0);
        IODelay(500000);  /* 500ms delay */

        /* Issue transmit command */
        *(unsigned short *)(*((unsigned int *)self + (0x1bc / sizeof(unsigned int))) + 2) = 0x100;  /* CU_START */
        [self sendChannelAttention];

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
            /* Default to connector type 2 (AUI) */
            _set_connector_type(ioBase, 2);
        }
    }

    /* Clear interrupt latch */
    [self clearIrqLatch];

    /* Free test TCB */
    IOFree(testTCB, __page_size);

    /* Clear auto-detect flag */
    *((unsigned char *)self + 0x198) = 0;
}

@end
