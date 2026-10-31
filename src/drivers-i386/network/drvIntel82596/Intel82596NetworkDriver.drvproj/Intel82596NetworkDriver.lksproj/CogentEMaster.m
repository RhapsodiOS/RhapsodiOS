/*
 * CogentEMaster.m
 * Cogent EM Master Ethernet Adapter Driver for Intel 82596
 */

#import "CogentEMaster.h"
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEISADeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/i386/ioPorts.h>
#import <objc/objc-runtime.h>
#import <bsd/string.h>

/* Forward declaration of Intel82596 base class */
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


@implementation CogentEMaster

/*
 * Probe for CogentEMaster hardware
 */
+ (char)probe:(IODeviceDescription *)deviceDescription
{
    id instance=[self alloc];
    unsigned int slot;
    if (instance == nil) return 0;
    if ([deviceDescription getEISASlotNumber:&slot] == IO_R_SUCCESS) {
        [instance setIOBase:(unsigned short)(slot << 12)];
        return [instance initFromDeviceDescription:deviceDescription] != nil;
    }
    IOLog("CogentEMaster: couldn't get slot number\n");
    [instance free];
    return 0;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    unsigned char slotID[4], regValue;
    unsigned int boardType;
    int i;
    IONetbufQueue *queue;
    if ([deviceDescription getEISASlotID:slotID] != IO_R_SUCCESS) {
        IOLog("CogentEMaster: failed to retrieve eisa id\n");
        [self free]; return nil;
    }
    boardType=slotID[0]&7;
    regValue=inb(ioBase+0xc88);
    irq=irqTable[boardType][(regValue>>1)&3];
    if ([deviceDescription setInterruptList:&irq num:1] != IO_R_SUCCESS) {
        IOLog("CogentEMaster: failed to add irq\n");
        [self free]; return nil;
    }
    for(i=0;i<6;++i) myAddress.ether_addr_octet[i]=inb(ioBase+0xc90+i);
    self=[super initFromDeviceDescription:deviceDescription];
    if (self==nil || ![self coldInit]) goto fail;
    fullDuplexMode=0;
    if (boardType==5 && (inb(ioBase+0xc89)&8)) fullDuplexMode=1;
    IOLog("Cogent eMASTER+ %s in slot %d irq %d %s\n",boardTable[boardType],ioBase>>12,irq,fullDuplexMode ? "full duplex" : "");
    if (![self resetAndEnable:0]) goto fail;
    promiscuousEnabled=0; multicastEnabled=0; allMulticastEnabled=0; multicastConfigured=0;
    queue=[[IONetbufQueue alloc] initWithMaxCount:0x50];
    xmtQueue=queue;
    networkInterface=[super attachToNetworkWithAddress:myAddress];
    return self;
fail:
    [self free];
    return nil;
}

/*
 * Clear interrupt latch
 * Cogent EMaster boards require special handling to clear the IRQ latch
 */
- (void)clearIrqLatch
{
    unsigned short port=ioBase+3208;
    unsigned char value=inb(port);
    outb(port,value&0xef);
}

/*
 * Send channel attention to 82596
 */
- (void)sendChannelAttention
{
    outb(ioBase,0);
}

/*
 * Send port command to 82596
 */
- (void)sendPortCommand:(int)cmd with:(unsigned int)arg
{
    unsigned int value=(arg&0xf0)|(cmd&0x0f);
    outl(ioBase+8,value);
}

@end
