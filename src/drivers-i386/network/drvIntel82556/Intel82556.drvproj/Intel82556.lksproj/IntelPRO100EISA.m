/* Intel EtherExpress PRO/100 EISA adapter support. */

#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/i386/ioPorts.h>

static const unsigned char plxirq[] = { 5, 9, 10, 11 };
static const unsigned char fleairq[] = { 3, 7, 12, 15 };

/* Reference: 0x3278, _card_irq. */
static int card_irq(unsigned int base)
{
    unsigned char value;

    value = inb(base + 0x430);
    if (value & 0x80) {
        value = inb(base + 0x430);
        return fleairq[(value >> 1) & 3];
    }
    value = inb(base + 0xc88);
    return plxirq[(value >> 1) & 3];
}

@implementation IntelPRO100EISA

/* Reference: 0x32c8. */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    IntelPRO100EISA *driver;
    unsigned int slot;
    unsigned long slotID;
    IOEISADeviceDescription *eisaDescription = (IOEISADeviceDescription *)deviceDescription;

    driver = [self alloc];
    if (driver == nil)
        return NO;

    if ([eisaDescription getEISASlotNumber:&slot] != IO_R_SUCCESS) {
        IOLog("IntelPRO100EISA: couldn't get slot number\n");
        [driver free];
        return NO;
    }
    if ([eisaDescription getEISASlotID:&slotID] != IO_R_SUCCESS) {
        IOLog("IntelPRO100EISA: failed to retrieve eisa id\n");
        [driver free];
        return NO;
    }
    driver->ioBase = slot << 12;
    return [driver initFromDeviceDescription:deviceDescription] != nil;
}

/* Reference: 0x3378. */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    irq = card_irq(ioBase);
    if ([deviceDescription setInterruptList:&irq num:1] != IO_R_SUCCESS) {
        IOLog("IntelPRO100EISA: failed to add irq");
        [self free];
        return nil;
    }

    promiscuousEnabled = NO;
    multicastEnabled = NO;
    allMulticastEnabled = NO;
    multicastConfigured = NO;
    fullDuplexMode = NO;

    if ([super initFromDeviceDescription:deviceDescription] == nil ||
        ![self coldInit] || ![self resetAndEnable:NO])
        return nil;

    IOLog("%s: Intel EtherExpress PRO/100 slot %d irq %d at %sMbits/s\n",
          [self name], ioBase >> 12, irq, dataRate ? "100" : "10");
    networkInterface = [super attachToNetworkWithAddress:myAddress];
    return self;
}

/* Reference: 0x34cc. */
- (void)clearIrqLatch
{
    unsigned short port;
    unsigned char value;

    port = ioBase + 0x430;
    value = inb(port);
    outb(port, value | 0x10);
    port = ioBase + 0xc88;
    value = inb(port);
    outb(port, value & 0xef);
}

/* Reference: 0x3524. */
- (void)interruptOccurred
{
    unsigned short port, status;
    unsigned char value;

    port = ioBase + 0x430;
    value = inb(port);
    outb(port, value | 0x20);

    status = scb_p->status;
    [self acknowledgeInterrupts:status];
    if ((status & 0x5000) &&
        ![self receiveInterruptOccurred:(status >> 12) & 1])
        return;
    if ((status & 0xa000) && ![self transmitInterruptOccurred])
        return;

    [self clearIrqLatch];
    port = ioBase + 0x430;
    value = inb(port);
    outb(port, value & 0xdf);
}

/* Reference: 0x35ec. */
- (void)sendPortCommand:(int)command with:(unsigned int)argument
{
    outl(ioBase + 8, (argument & 0xfffffff0U) | (command & 0x0f));
}

/* Reference: 0x361c. */
- (void)sendChannelAttention
{
    outb(ioBase, 0);
}

/* Reference: 0x3638. */
- (void)initPLXchip
{
    unsigned char value;

    value = inb(ioBase + 0xc88);
    if (value & 0x08)
        value &= 0xf7;
    if (!(value & 0x40))
        value |= 0x40;
    if (!(value & 0x80))
        value |= 0x80;
    if (value & 0x20)
        value &= 0xdf;
    outb(ioBase + 0xc88, value);

    value = inb(ioBase + 0xc89);
    if (!(value & 1))
        value |= 1;
    value |= 4;
    value &= 0xf7;
    if (value & 0x10)
        value &= 0xef;
    outb(ioBase + 0xc89, value);

    value = inb(ioBase + 0xc8a);
    if (value & 2)
        outb(ioBase + 0xc8a, value);

    value = inb(ioBase + 0xc8f);
    if (!(value & 0x80))
        value |= 0x80;
    outb(ioBase + 0xc8f, value & 0xbb);
}

/* Reference: 0x36f0; byte I/O and delay verified from assembly. */
- (void)resetPLXchip
{
    unsigned char value;

    value = inb(ioBase + 0xc8f);
    outb(ioBase + 0xc8f, value | 2);
    IOSleep(50);
    value = inb(ioBase + 0xc8f);
    outb(ioBase + 0xc8f, value & 0xfd);
}

/* Reference: 0x3734; read/delay/write order verified from assembly. */
- (void)lockDBRT
{
    unsigned char value;

    value = inb(ioBase + 0xc89);
    value = (value | 2) & 0xfb;
    IOSleep(10);
    outb(ioBase + 0xc89, value);
    IOSleep(50);
    value = inb(ioBase + 0xc89);
    IOSleep(10);
    value = (value & 0xfd) | 4;
    outb(ioBase + 0xc89, value);
    IOSleep(10);
}

/* Reference: 0x37d0. */
- (void)enableAdapterInterrupts
{
    unsigned short port = ioBase + 0x430;
    unsigned char value = inb(port);

    outb(port, value & 0xdf);
}

/* Reference: 0x37f8. */
- (void)disableAdapterInterrupts
{
    unsigned short port = ioBase + 0x430;
    unsigned char value = inb(port);

    outb(port, value | 0x20);
}

/* Reference: 0x3824. */
- (void)getEthernetAddress
{
    int i;

    for (i = 0; i < 6; i++)
        myAddress.ether_addr_octet[i] = inb(ioBase + 0xc90 + i);
}

@end
