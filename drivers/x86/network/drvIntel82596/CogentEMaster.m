/*
 * CogentEMaster.m
 * Cogent EM Master Ethernet Adapter Driver for Intel 82596
 */

#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEISADeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/i386/ioPorts.h>
#import <objc/objc-runtime.h>
#import <bsd/string.h>

/* Forward declaration of Intel82596 base class */
@interface Intel82596 : IOEthernetDriver
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)clearIrqLatch;
- (void)sendChannelAttention;
- (void)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg;
- (void)setIOBase:(unsigned int)base;
- (BOOL)resetAndEnable:(BOOL)enable;
- (BOOL)coldInit;
- (const char *)name;
@end

/* Base IRQ lookup tables */
static unsigned char irq932[4] = {5, 9, 10, 11};    /* EM932 series */
static unsigned char irq9X5[4] = {5, 12, 10, 11};   /* 9X5 series */

/* IRQ table pointers for different board types (indexed by slot ID & 7) */
static const unsigned char *irqTable[] = {
    irq9X5,     /* Type 0 - unknown */
    irq932,     /* Type 1 - EM932 EISA */
    irq9X5,     /* Type 2 - EM935 EISA XL */
    irq932,     /* Type 3 - EM932 EISA */
    irq932,     /* Type 4 - EM932 EISA TP */
    irq9X5,     /* Type 5 - EM945 EISA FDE */
    irq9X5,     /* Type 6 - unknown */
    irq9X5      /* Type 7 - unknown */
};

/* Board name table (indexed by slot ID & 7) */
static const char *boardTable[] = {
    "unknown",          /* Type 0 */
    "EM932 EISA",       /* Type 1 */
    "EM935 EISA XL",    /* Type 2 */
    "EM932 EISA",       /* Type 3 */
    "EM932 EISA TP",    /* Type 4 */
    "EM945 EISA FDE",   /* Type 5 */
    "unknown",          /* Type 6 */
    "unknown"           /* Type 7 */
};

/* Synchronization counter */
static volatile unsigned int _clearIrqCount = 0;
static volatile unsigned int _sendCACount = 0;
static volatile unsigned int _sendPortCmdCount = 0;

@interface CogentEMaster : Intel82596
{
    /* Instance variables with specific offsets to match object layout */
    unsigned short ioBase;              /* Offset 0x174 */
    unsigned short reserved1;
    unsigned int irqLevel;              /* Offset 0x178 */
    unsigned char romAddress[6];        /* Offset 0x17c */
    unsigned short reserved2;
    /* More fields follow in the actual object structure */
}

/* Probe and initialization */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/* Hardware control methods - override Intel82596 base methods */
- (void)clearIrqLatch;
- (void)sendChannelAttention;
- (void)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg;

@end

@implementation CogentEMaster

/*
 * Probe for CogentEMaster hardware
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
        IOLog("CogentEMaster: couldn't get slot number\n");
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
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOReturn result;
    unsigned char slotID[4];
    unsigned char boardType;
    unsigned char regValue;
    int i;
    id netif;
    id txQueue;
    BOOL isSpecialBoard = NO;

    /* Get EISA slot ID */
    result = [deviceDescription getEISASlotID:slotID];
    if (result != IO_R_SUCCESS) {
        IOLog("CogentEMaster: couldn't get slot ID\n");
        [self free];
        return nil;
    }

    /* Determine board type from slot ID (lower 3 bits) */
    boardType = slotID[0] & 7;

    /* Read IRQ configuration from hardware */
    regValue = inb(ioBase + 0xc88);

    /* Look up IRQ using board type and register value */
    irqLevel = irqTable[boardType][(regValue >> 1) & 3];

    /* Set interrupt list in device description */
    result = [deviceDescription setInterruptList:&irqLevel num:1];
    if (result != IO_R_SUCCESS) {
        IOLog("CogentEMaster: Unable to reserve IRQ %d - Aborting\n", irqLevel);
        [self free];
        return nil;
    }

    /* Read MAC address from EEPROM/ROM (ports 0xc90-0xc95) */
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

    /* Check for special board configuration (Flash32 with EEPROM) */
    /* Offset 0x1fc in object structure - this is beyond our declared ivars */
    *((char *)self + 0x1fc) = 0;
    if (boardType == 5) {
        regValue = inb(ioBase + 0xc89);
        if (regValue & 8) {
            *((char *)self + 0x1fc) = 1;
            isSpecialBoard = YES;
        }
    }

    /* Log board information */
    IOLog("Cogent %s at slot %d IRQ %d %s\n",
          boardTable[boardType],
          (ioBase >> 12),
          irqLevel,
          isSpecialBoard ? "with EEPROM" : "");

    /* Reset and enable the adapter */
    if (![self resetAndEnable:NO]) {
        [self free];
        return nil;
    }

    /* Initialize statistics counters (offsets 0x194-0x197) */
    *((char *)self + 0x194) = 0;
    *((char *)self + 0x195) = 0;
    *((char *)self + 0x196) = 0;
    *((char *)self + 0x197) = 0;

    /* Create transmit queue with max count of 80 (0x50) */
    txQueue = [[objc_getClass("Queue") alloc] initWithMaxCount:0x50];
    if (txQueue == nil) {
        [self free];
        return nil;
    }
    *((id *)self + 100) = txQueue;  /* Offset 400 bytes / sizeof(id) = 100 */

    /* Attach to network with MAC address */
    netif = [super attachToNetworkWithAddress:romAddress];
    *((id *)self + 0x188/sizeof(id)) = netif;

    return self;
}

/*
 * Clear interrupt latch
 * Cogent EMaster boards require special handling to clear the IRQ latch
 */
- (void)clearIrqLatch
{
    unsigned short port;
    unsigned char regValue;

    /* Read from control register at offset 0xc88 */
    port = ioBase + 0xc88;
    regValue = inb(port);

    /* Clear bit 4 (mask with 0xef) and write back */
    outb(port, regValue & 0xef);

    /* Increment counter (atomic operation) */
    _clearIrqCount++;
}

/*
 * Send channel attention to 82596
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

@end
