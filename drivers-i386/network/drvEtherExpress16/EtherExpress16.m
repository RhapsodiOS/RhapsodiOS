/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * EtherExpress16.m - Intel EtherExpress 16 Ethernet Driver Implementation
 */

#import "EtherExpress16.h"
#import "EtherExpress16KernelServerInstance.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <machkit/NXLock.h>
#import <string.h>

/* I/O Port Offsets */
#define EE16_STATUS_REG     0x00
#define EE16_COMMAND_REG    0x00
#define EE16_WRITE_PTR      0x02
#define EE16_READ_PTR       0x04
#define EE16_DATA_REG       0x08
#define EE16_IRQ_REG        0x0C

/* Command Register Bits */
#define CMD_RESET           0x8000
#define CMD_IRQ_ACK         0x4000
#define CMD_RX_ENABLE       0x0001
#define CMD_TX_ENABLE       0x0002

/* Status Register Bits */
#define STAT_RX_INT         0x0001
#define STAT_TX_INT         0x0002
#define STAT_BUSY           0x8000

@implementation EtherExpress16

+ (BOOL)probe:(IOPCIDevice *)devDesc
{
    unsigned short ioBase;
    const char *ioPortStr;

    if ([devDesc getStringPropertyList:&ioPortStr forKey:"I/O Ports"] != IO_R_SUCCESS) {
        return NO;
    }

    /* Parse I/O port address */
    if (sscanf(ioPortStr, "0x%hx", &ioBase) != 1) {
        return NO;
    }

    /* Perform basic hardware detection */
    outw(ioBase + EE16_COMMAND_REG, CMD_RESET);
    IOSleep(10);

    unsigned short status = inw(ioBase + EE16_STATUS_REG);
    if (status == 0xFFFF) {
        return NO;  /* No card present */
    }

    return YES;
}

- initFromDeviceDescription:(IOPCIDevice *)devDesc
{
    const char *ioPortStr;
    unsigned int *irqList;
    unsigned int irqCount;

    [super initFromDeviceDescription:devDesc];

    /* Get I/O port base */
    if ([devDesc getStringPropertyList:&ioPortStr forKey:"I/O Ports"] != IO_R_SUCCESS) {
        [self free];
        return nil;
    }
    sscanf(ioPortStr, "0x%hx", &ioBase);

    /* Get IRQ */
    if ([devDesc getIntValues:&irqList forProperty:"IRQ Levels" count:&irqCount] != IO_R_SUCCESS || irqCount == 0) {
        [self free];
        return nil;
    }
    irq = irqList[0];

    /* Reset and initialize chip */
    if (![self resetChip]) {
        [self free];
        return nil;
    }

    if (![self initChip]) {
        [self free];
        return nil;
    }

    /* Create kernel server instance */
    kernelServerInstance = [[EtherExpress16KernelServerInstance alloc] init:self];
    if (!kernelServerInstance) {
        [self free];
        return nil;
    }

    /* Register interrupt handler */
    [self registerInterrupt:irq];

    return self;
}

- free
{
    if (kernelServerInstance) {
        [kernelServerInstance free];
        kernelServerInstance = nil;
    }

    [self disableAllInterrupts];

    return [super free];
}

- (BOOL)resetChip
{
    /* Issue reset command */
    outw(ioBase + EE16_COMMAND_REG, CMD_RESET);
    IOSleep(10);

    /* Wait for reset to complete */
    int timeout = 1000;
    while (timeout-- > 0) {
        unsigned short status = inw(ioBase + EE16_STATUS_REG);
        if (!(status & STAT_BUSY)) {
            break;
        }
        IOSleep(1);
    }

    if (timeout <= 0) {
        IOLog("EtherExpress16: Reset timeout\n");
        return NO;
    }

    return YES;
}

- (BOOL)initChip
{
    int i;

    /* Read MAC address from EEPROM/hardware */
    for (i = 0; i < 6; i++) {
        myAddress[i] = inb(ioBase + i);
    }

    IOLog("EtherExpress16: MAC address %02x:%02x:%02x:%02x:%02x:%02x\n",
          myAddress[0], myAddress[1], myAddress[2],
          myAddress[3], myAddress[4], myAddress[5]);

    /* Configure IRQ */
    unsigned char irqMask = 0;
    switch (irq) {
        case 3:  irqMask = 0x01; break;
        case 4:  irqMask = 0x02; break;
        case 5:  irqMask = 0x04; break;
        case 9:  irqMask = 0x08; break;
        case 10: irqMask = 0x10; break;
        case 11: irqMask = 0x20; break;
        default:
            IOLog("EtherExpress16: Invalid IRQ %d\n", irq);
            return NO;
    }
    outb(ioBase + EE16_IRQ_REG, irqMask);

    return YES;
}

- (void)resetEtherChip:(id)arg_88_xxx_93_xxx_96_xxx_99
{
    [self resetChip];
    [self initChip];
}

- (int)getIntValues:(unsigned int **)paramPtr count:(unsigned int *)count
           forParameter:(IOParameterName)parameterName
{
    /* Delegate to superclass or handle specific parameters */
    return [super getIntValues:paramPtr count:count forParameter:parameterName];
}

- (IOReturn)getHandler:(IOEthernetHandler *)handler
                 level:(unsigned int *)level
              argument:(void **)arg
           forInterrupt:(unsigned int)irqNum
{
    *handler = (IOEthernetHandler)[self methodFor:@selector(interruptOccurred)];
    *level = IPLDEVICE;
    *arg = self;
    return IO_R_SUCCESS;
}

- (void)interruptOccurred
{
    unsigned short status = inw(ioBase + EE16_STATUS_REG);

    /* Acknowledge interrupt */
    outw(ioBase + EE16_COMMAND_REG, CMD_IRQ_ACK);

    /* Handle receive interrupt */
    if (status & STAT_RX_INT) {
        [self receivePacket];
    }

    /* Handle transmit interrupt */
    if (status & STAT_TX_INT) {
        /* Notify network stack that transmit completed */
        [self transmitInterruptOccurred];
    }
}

- (void)timeoutOccurred
{
    /* Handle timeout events */
    IOLog("EtherExpress16: Timeout occurred\n");
}

- (BOOL)enableAllInterrupts
{
    /* Enable RX and TX */
    outw(ioBase + EE16_COMMAND_REG, CMD_RX_ENABLE | CMD_TX_ENABLE);
    return YES;
}

- (BOOL)disableAllInterrupts
{
    /* Disable interrupts */
    outw(ioBase + EE16_COMMAND_REG, 0);
    return YES;
}

- (void)sendPacket:(void *)pkt length:(unsigned int)len
{
    int i;
    unsigned char *data = (unsigned char *)pkt;

    /* Wait for transmitter to be ready */
    int timeout = 1000;
    while (timeout-- > 0) {
        unsigned short status = inw(ioBase + EE16_STATUS_REG);
        if (!(status & STAT_BUSY)) {
            break;
        }
        IOSleep(1);
    }

    if (timeout <= 0) {
        IOLog("EtherExpress16: TX timeout\n");
        return;
    }

    /* Set write pointer */
    outw(ioBase + EE16_WRITE_PTR, 0);

    /* Write packet length */
    outw(ioBase + EE16_DATA_REG, len);

    /* Write packet data */
    for (i = 0; i < len; i += 2) {
        unsigned short word;
        if (i + 1 < len) {
            word = data[i] | (data[i + 1] << 8);
        } else {
            word = data[i];
        }
        outw(ioBase + EE16_DATA_REG, word);
    }

    /* Trigger transmission */
    outw(ioBase + EE16_COMMAND_REG, CMD_TX_ENABLE);
}

- (void)receivePacket
{
    unsigned short len;
    unsigned char buffer[2048];
    int i;

    /* Set read pointer */
    outw(ioBase + EE16_READ_PTR, 0);

    /* Read packet length */
    len = inw(ioBase + EE16_DATA_REG);

    if (len > sizeof(buffer)) {
        IOLog("EtherExpress16: Packet too large: %d\n", len);
        return;
    }

    /* Read packet data */
    for (i = 0; i < len; i += 2) {
        unsigned short word = inw(ioBase + EE16_DATA_REG);
        buffer[i] = word & 0xFF;
        if (i + 1 < len) {
            buffer[i + 1] = (word >> 8) & 0xFF;
        }
    }

    /* Pass packet to network stack */
    [self receiveFrame:buffer length:len];
}

- (IOReturn)getEtherAddress:(enet_addr_t *)ea
{
    memcpy(ea->ea_byte, myAddress, 6);
    return IO_R_SUCCESS;
}

- (void)setRunningState:(BOOL)state
{
    if (state) {
        [self enableAllInterrupts];
    } else {
        [self disableAllInterrupts];
    }
}

- (BOOL)isRunning
{
    unsigned short status = inw(ioBase + EE16_STATUS_REG);
    return (status & (CMD_RX_ENABLE | CMD_TX_ENABLE)) != 0;
}

@end
