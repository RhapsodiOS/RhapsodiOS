/*
 * Copyright (c) 1998 3Com Corporation. All rights reserved.
 *
 * EtherLink XL 3C90X Ethernet Driver
 */

#import "EtherLinkXL.h"
#import "EtherLinkXLMII.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <machkit/NXLock.h>

@implementation EtherLinkXL

+ (BOOL)probe:(IOPCIDevice *)device
{
    unsigned int vendorID, deviceID;

    vendorID = [device configReadLong:PCI_VENDOR_ID];
    deviceID = (vendorID >> 16) & 0xFFFF;
    vendorID &= 0xFFFF;

    if (vendorID != 0x10B7) {
        return NO;
    }

    /* Check for supported device IDs */
    switch (deviceID) {
        case 0x9000:  /* 3C900 */
        case 0x9001:  /* 3C900B */
        case 0x9050:  /* 3C905 */
        case 0x9051:  /* 3C905B */
        case 0x90B1:  /* 3C90xB */
            return YES;
        default:
            return NO;
    }
}

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    IOPCIDevice *device;
    unsigned int baseAddr;

    [super initFromDeviceDescription:deviceDescription];

    device = (IOPCIDevice *)[deviceDescription device];
    pciDevice = device;

    /* Get I/O base address */
    baseAddr = [device configReadLong:PCI_BASE_ADDRESS_0];
    ioBasePhys = baseAddr & ~0xF;

    /* Map I/O space */
    if ([device mapIORange:ioBasePhys to:&ioBase findSpace:YES cache:IO_CACHE_OFF] != IO_R_SUCCESS) {
        [self free];
        return nil;
    }

    /* Initialize state */
    isFullDuplex = NO;
    isRunning = NO;
    transmitEnabled = NO;
    receiveEnabled = NO;

    /* Reset and initialize hardware */
    if (![self resetAndEnable:NO]) {
        [self free];
        return nil;
    }

    /* Get ethernet address */
    [self selectWindow:WINDOW_2];
    ethernetAddress[0] = [self readRegister:0x00] & 0xFF;
    ethernetAddress[1] = [self readRegister:0x01] & 0xFF;
    ethernetAddress[2] = [self readRegister:0x02] & 0xFF;
    ethernetAddress[3] = [self readRegister:0x03] & 0xFF;
    ethernetAddress[4] = [self readRegister:0x04] & 0xFF;
    ethernetAddress[5] = [self readRegister:0x05] & 0xFF;

    /* Initialize MII interface */
    miiDevice = [[EtherLinkXLMII alloc] initWithController:self];

    /* Enable interrupts */
    [device enableAllInterrupts];

    return self;
}

- free
{
    if (miiDevice) {
        [miiDevice free];
        miiDevice = nil;
    }

    if (ioBase && pciDevice) {
        [pciDevice unmapIORange:ioBase];
        ioBase = NULL;
    }

    return [super free];
}

- (BOOL)resetAndEnable:(BOOL)enable
{
    int i;

    /* Issue global reset */
    [self writeRegister:ELINK_COMMAND value:(CMD_GLOBAL_RESET << 11)];

    /* Wait for reset to complete */
    for (i = 0; i < 1000; i++) {
        IODelay(10);
        if (!([self readRegister:ELINK_STATUS] & 0x1000))
            break;
    }

    if (i >= 1000) {
        IOLog("EtherLinkXL: Reset timeout\n");
        return NO;
    }

    if (enable) {
        [self enableAdapter];
    }

    return YES;
}

- (void)enableAdapter
{
    [self selectWindow:WINDOW_0];

    /* Enable transmitter */
    [self writeRegister:ELINK_COMMAND value:(CMD_TX_ENABLE << 11)];
    transmitEnabled = YES;

    /* Enable receiver */
    [self writeRegister:ELINK_COMMAND value:(CMD_RX_ENABLE << 11)];
    receiveEnabled = YES;

    /* Enable interrupts */
    [self writeRegister:ELINK_COMMAND value:((CMD_SET_INTR_ENABLE << 11) | 0x07FF)];
    [self writeRegister:ELINK_COMMAND value:((CMD_ACK_INTR << 11) | 0x07FF)];

    isRunning = YES;
}

- (void)disableAdapter
{
    /* Disable receiver */
    [self writeRegister:ELINK_COMMAND value:(CMD_RX_DISABLE << 11)];
    receiveEnabled = NO;

    /* Disable transmitter */
    [self writeRegister:ELINK_COMMAND value:(CMD_TX_DISABLE << 11)];
    transmitEnabled = NO;

    /* Disable interrupts */
    [self writeRegister:ELINK_COMMAND value:((CMD_SET_INTR_ENABLE << 11) | 0)];

    isRunning = NO;
}

- (void)setRunning:(BOOL)running
{
    if (running) {
        [self enableAdapter];
    } else {
        [self disableAdapter];
    }
}

- (unsigned int)readRegister:(unsigned int)offset
{
    return inw((unsigned int)ioBase + offset);
}

- (void)writeRegister:(unsigned int)offset value:(unsigned int)value
{
    outw((unsigned int)ioBase + offset, value);
}

- (void)selectWindow:(int)window
{
    [self writeRegister:ELINK_WINDOW value:window];
}

- (void)transmitPacket:(netbuf_t)packet
{
    unsigned int length;
    unsigned char *data;

    if (!transmitEnabled) {
        return;
    }

    length = nb_size(packet);
    data = nb_map(packet);

    /* Wait for transmitter ready */
    while ([self readRegister:ELINK_TX_STATUS] & 0x80) {
        IODelay(10);
    }

    /* Write packet length */
    [self writeRegister:0x00 value:length];

    /* Write packet data */
    outsw((unsigned int)ioBase + 0x00, data, (length + 1) / 2);

    txPackets++;
}

- (void)receivePacket
{
    unsigned int status;
    unsigned int length;
    netbuf_t packet;
    unsigned char *data;

    if (!receiveEnabled) {
        return;
    }

    status = [self readRegister:0x00];
    length = status & 0x1FFF;

    if (length < 14 || length > 1518) {
        rxErrors++;
        return;
    }

    packet = [self allocateNetbuf];
    if (!packet) {
        rxErrors++;
        return;
    }

    nb_grow_top(packet, length);
    data = nb_map(packet);

    /* Read packet data */
    insw((unsigned int)ioBase + 0x00, data, (length + 1) / 2);

    [self receiveNetbuf:packet];
    rxPackets++;
}

- (void)handleInterrupt
{
    unsigned int status;

    status = [self readRegister:ELINK_INT_STATUS];

    /* Acknowledge interrupt */
    [self writeRegister:ELINK_COMMAND value:((CMD_ACK_INTR << 11) | (status & 0x07FF))];

    if (status & INT_RX_COMPLETE) {
        [self receivePacket];
    }

    if (status & INT_TX_COMPLETE) {
        /* Handle transmit completion */
        [self readRegister:ELINK_TX_STATUS];
    }

    if (status & INT_UPDATE_STATS) {
        [self updateStatistics];
    }

    if (status & INT_LINK_EVENT) {
        /* Handle link status change */
    }

    interruptOccurred++;
}

- (void)setEthernetAddress:(unsigned char *)addr
{
    int i;

    [self selectWindow:WINDOW_2];

    for (i = 0; i < 6; i++) {
        ethernetAddress[i] = addr[i];
        [self writeRegister:i value:addr[i]];
    }
}

- (void)getEthernetAddress:(unsigned char *)addr
{
    int i;

    for (i = 0; i < 6; i++) {
        addr[i] = ethernetAddress[i];
    }
}

- (void)setFullDuplex:(BOOL)fullDuplex
{
    isFullDuplex = fullDuplex;

    /* Configure full duplex mode in hardware */
    [self selectWindow:WINDOW_3];

    if (fullDuplex) {
        unsigned int value = [self readRegister:0x00];
        [self writeRegister:0x00 value:(value | 0x20)];
    } else {
        unsigned int value = [self readRegister:0x00];
        [self writeRegister:0x00 value:(value & ~0x20)];
    }
}

- (void)setMediaType:(unsigned int)media
{
    mediaType = media;

    [self selectWindow:WINDOW_4];
    [self writeRegister:0x08 value:media];
}

- (void)updateStatistics
{
    [self selectWindow:WINDOW_6];

    /* Read and clear statistics */
    [self readRegister:0x00];  /* Carrier sense lost */
    [self readRegister:0x01];  /* SQE errors */
    [self readRegister:0x02];  /* Multiple collisions */
    [self readRegister:0x03];  /* Single collisions */
    [self readRegister:0x04];  /* Late collisions */
    [self readRegister:0x05];  /* Receive overruns */
    [self readRegister:0x06];  /* Good frames transmitted */
    [self readRegister:0x07];  /* Good frames received */
    [self readRegister:0x08];  /* Transmit deferrals */
    [self readRegister:0x0A];  /* Bytes received */
    [self readRegister:0x0C];  /* Bytes transmitted */
}

- (unsigned int)getTxPackets
{
    return txPackets;
}

- (unsigned int)getRxPackets
{
    return rxPackets;
}

- (unsigned int)miiReadBit
{
    unsigned int value;

    [self selectWindow:WINDOW_4];
    value = [self readRegister:0x08];

    return (value & 0x4000) ? 1 : 0;
}

- (void)miiWriteBit:(unsigned int)bit
{
    unsigned int value;

    [self selectWindow:WINDOW_4];
    value = [self readRegister:0x08];

    if (bit) {
        value |= 0x0800;
    } else {
        value &= ~0x0800;
    }

    [self writeRegister:0x08 value:value];
}

- (void)miiInit
{
    [self selectWindow:WINDOW_4];

    /* Initialize MII management interface */
    [self writeRegister:0x08 value:0x0000];
}

- (void)setPowerState:(unsigned int)state
{
    powerState = state;

    /* Implement power state transitions */
    switch (state) {
        case 0:  /* D0 - Full power */
            [self enableAdapter];
            break;
        case 1:  /* D1 - Low power */
        case 2:  /* D2 - Lower power */
        case 3:  /* D3 - Off */
            [self disableAdapter];
            break;
    }
}

- (unsigned int)getPowerState
{
    return powerState;
}

@end
