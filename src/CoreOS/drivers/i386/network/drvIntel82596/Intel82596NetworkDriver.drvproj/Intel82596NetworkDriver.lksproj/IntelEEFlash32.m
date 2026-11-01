/*
 * IntelEEFlash32.m
 * Intel EtherExpress Flash32 Ethernet Adapter Driver for Intel 82596
 */

#import "IntelEEFlash32.h"
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEISADeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/i386/ioPorts.h>
#import <objc/objc-runtime.h>
#import <mach/mach_interface.h>
#import <bsd/string.h>

/* 82596 board IRQ selection tables recovered from the reference. */
static unsigned char plxirq[4] = {5, 9, 10, 11};
static unsigned char fleairq[4] = {3, 7, 12, 15};
static const char *connector_text[] = {"BNC", "n/a", "AUI", "TPE"};
static const char *test_data_159 = "IntelEtherExpressFlash32 AutoConnectorDetect";

static int card_irq(unsigned int ioBase)
{
    unsigned char value;
    value=inb(ioBase+1072);
    if ((signed char)value < 0) {
        value=inb(ioBase+1072);
        return fleairq[(value>>1)&3];
    }
    value=inb(ioBase+3208);
    return plxirq[(value>>1)&3];
}

static int get_connector_type(short ioBase)
{
    return inb(ioBase+3209)&3;
}

static unsigned char set_connector_type(short ioBase, char type)
{
    unsigned char value=inb(ioBase+3209);
    value=(value&0xfc)|(type&3);
    outb(ioBase+3209,value);
    return value;
}

@implementation IntelEEFlash32

/*
 * Probe for Intel EtherExpress Flash32 hardware
 */
+ (char)probe:(IODeviceDescription *)deviceDescription
{
    id instance=[self alloc];
    unsigned int slot;
    if (instance==nil) return 0;
    if ([deviceDescription getEISASlotNumber:&slot]==IO_R_SUCCESS) {
        [instance setIOBase:(unsigned short)(slot<<12)];
        return [instance initFromDeviceDescription:deviceDescription]!=nil;
    }
    IOLog("EEFlash32: couldn't get slot number\n");
    [instance free]; return 0;
}

/*
 * Initialize from device description
 * Complete initialization for Intel EtherExpress Flash32 adapter
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    unsigned char value;
    unsigned int eepromData;
    int i;
    IONetbufQueue *queue;
    if ([deviceDescription getEISASlotID:&eepromData]!=IO_R_SUCCESS) {
        IOLog("EEFlash32: failed to retrieve eisa id\n");
        [self free]; return nil;
    }
    irq=card_irq(ioBase);
    if ([deviceDescription setInterruptList:&irq num:1]!=IO_R_SUCCESS) {
        IOLog("EEFlash32: failed to add irq");
        [self free]; return nil;
    }
    for(i=0;i<6;++i) myAddress.ether_addr_octet[i]=inb(ioBase+3216+i);
    self=[super initFromDeviceDescription:deviceDescription];
    if (self==nil || ![self coldInit]) goto fail;
    if (![self checksum_OK:eepromData]) {
        IOLog("EEFLash32: invalid checksum\n"); goto fail;
    }
    value=inb(ioBase+1072);
    if ((value&8)==0) { outb(ioBase+1072,value|8); IOLog("interrupts NOT latched - now latched\n"); }
    value=inb(ioBase+3208);
    if (value&8) { outb(ioBase+3208,value&0xf7); IOLog("Set plx latched to non-latched\n"); }
    fullDuplexMode=0;
    if (![self resetAndEnable:0]) goto fail;
    promiscuousEnabled=0; multicastEnabled=0; allMulticastEnabled=0; multicastConfigured=0;
    queue=[[IONetbufQueue alloc] initWithMaxCount:0x50];
    xmtQueue=queue;
    value=inb(ioBase+1040);
    if (((value^8)&8)!=0) {
        [self doAutoConnectorDetect];
        if (![self resetAndEnable:0]) goto fail;
    }
    IOLog("Intel EtherExpress Flash32 in slot %d irq %d using %s connector\n",ioBase>>12,irq,connector_text[get_connector_type(ioBase)]);
    networkInterface=[super attachToNetworkWithAddress:myAddress];
    return self;
fail:
    [self free]; return nil;
}

/*
 * Clear interrupt latch
 * Flash32 boards require clearing latches at two ports
 */
- (void)clearIrqLatch
{
    unsigned char value;
    value=inb(ioBase+1072); outb(ioBase+1072,value&0xef);
    value=inb(ioBase+3208); outb(ioBase+3208,value&0xef);
}

/*
 * Send channel attention to 82596
 * Triggers channel attention by writing to base I/O port
 */
- (void)sendChannelAttention
{
    outb(ioBase,0);
}

/*
 * Send port command to 82596
 * Sends PORT command with argument to the controller
 */
- (void)sendPortCommand:(int)cmd with:(unsigned int)arg
{
    outl(ioBase+8,(arg&0xf0)|(cmd&0x0f));
}

/*
 * Handle interrupt
 * Flash32-specific interrupt handling with port 0x430 manipulation
 */
- (void)interruptOccurred
{
    unsigned short status=*(unsigned short *)scb->bytes;
    unsigned char value;
    value=inb(ioBase+1072); outb(ioBase+1072,value|0x20);
    [self acknowledgeInterrupts:status];
    if (((status&0x5000)==0 || [self processRecInterrupt]) &&
        (activeTcbHead==NULL || (*(unsigned short *)activeTcbHead&0x8000)==0 ||
         [self processXmtInterrupt])) {
        [self clearIrqLatch];
        value=inb(ioBase+1072); outb(ioBase+1072,value&0xdf);
    }
}

/*
 * Verify EEPROM checksum
 * Checksum validation for EEPROM data
 */
- (char)checksum_OK:(unsigned int)eepromData
{
    unsigned char low=inb(ioBase+3223);
    unsigned char high=inb(ioBase+3222);
    short checksum=(short)((high<<8)|low);
    int sum=0, i;
    for(i=0;i<6;++i) sum+=inb(ioBase+3216+i);
    sum+=checksum;
    sum+=(eepromData>>24)&0xff;
    sum+=(eepromData>>16)&0xff;
    sum+=(eepromData>>8)&0xff;
    sum+=eepromData&0xff;
    return sum==0;
}

/*
 * Auto-detect connector type
 * Tests each connector type to find one with link
 */
- (void)doAutoConnectorDetect
{
    unsigned short *command;
    unsigned int i;
    sourceAddressInsertion=1;
    if (![self config]) {
        IOLog("EEFlash32: connector test: configure failed");
        return;
    }
    command=(unsigned short *)IOMalloc(page_size);
    bzero(command,0x5f4);
    command[1]=0x8004;
    *(unsigned int *)(command+2)=0xffffffffU;
    *(unsigned int *)(command+4)=0xffffffffU;
    command[6]=0x8036;
    *(enet_addr_t *)(command+8)=myAddress;
    command[11]=0x4444;
    bcopy(test_data_159,(char *)(command+12),strlen((char *)test_data_159));
    if (IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)command,(unsigned int *)(scb->bytes+4))!=IO_R_SUCCESS) {
        IOLog("%s: Invalid auto-connect transmit command block address\n",[self name]);
        IOFree(command,page_size); return;
    }
    set_connector_type(ioBase,3);
    IODelay(500000);
    *(unsigned short *)(scb->bytes+2)=0x0100;
    outb(ioBase,0);
    for(i=0;i<2000;++i) { IODelay(1000); if(command[0]&0x8000) break; }
    if ((command[0]&0xa000)==0 || (command[0]&0x0fa0)!=0) {
        set_connector_type(ioBase,0);
        IODelay(500000);
        *(unsigned short *)(scb->bytes+2)=0x0100;
        outb(ioBase,0);
        for(i=0;i<2000;++i) { IODelay(1000); if(command[0]&0x8000) break; }
        if ((command[0]&0xa000)==0 || (command[0]&0x0fa0)!=0)
            set_connector_type(ioBase,2);
    }
    [self clearIrqLatch];
    IOFree(command,page_size);
    sourceAddressInsertion=0;
}

@end
