/*
 * Copyright (c) 1998 3Com Corporation. All rights reserved.
 *
 * EtherLink XL MII (Media Independent Interface) Support
 */

#import "EtherLinkXLMII.h"
#import "EtherLinkXL.h"
#import <driverkit/generalFuncs.h>

@implementation EtherLinkXLMII

- initWithController:(EtherLinkXL *)ctrl
{
    [super init];

    controller = ctrl;
    phyAddress = 0;
    linkUp = NO;
    fullDuplex = NO;
    linkSpeed = 0;

    /* Initialize MII interface */
    [controller miiInit];

    /* Find and initialize PHY */
    if (![self findPHY]) {
        IOLog("EtherLinkXLMII: No PHY found\n");
        [self free];
        return nil;
    }

    /* Reset PHY */
    [self resetPHY];

    /* Start auto-negotiation */
    [self autoNegotiate];

    return self;
}

- free
{
    controller = nil;
    return [super free];
}

- (unsigned int)readRegister:(unsigned int)reg
{
    unsigned int value = 0;
    int i;

    /* Send preamble (32 ones) */
    for (i = 0; i < 32; i++) {
        [controller miiWriteBit:1];
    }

    /* Send start of frame (01) */
    [controller miiWriteBit:0];
    [controller miiWriteBit:1];

    /* Send read opcode (10) */
    [controller miiWriteBit:1];
    [controller miiWriteBit:0];

    /* Send PHY address (5 bits) */
    for (i = 4; i >= 0; i--) {
        [controller miiWriteBit:(phyAddress >> i) & 1];
    }

    /* Send register address (5 bits) */
    for (i = 4; i >= 0; i--) {
        [controller miiWriteBit:(reg >> i) & 1];
    }

    /* Turnaround (2 bits) */
    [controller miiWriteBit:0];
    [controller miiWriteBit:0];

    /* Read data (16 bits) */
    for (i = 15; i >= 0; i--) {
        value |= ([controller miiReadBit] << i);
    }

    return value;
}

- (void)writeRegister:(unsigned int)reg value:(unsigned int)value
{
    int i;

    /* Send preamble (32 ones) */
    for (i = 0; i < 32; i++) {
        [controller miiWriteBit:1];
    }

    /* Send start of frame (01) */
    [controller miiWriteBit:0];
    [controller miiWriteBit:1];

    /* Send write opcode (01) */
    [controller miiWriteBit:0];
    [controller miiWriteBit:1];

    /* Send PHY address (5 bits) */
    for (i = 4; i >= 0; i--) {
        [controller miiWriteBit:(phyAddress >> i) & 1];
    }

    /* Send register address (5 bits) */
    for (i = 4; i >= 0; i--) {
        [controller miiWriteBit:(reg >> i) & 1];
    }

    /* Turnaround (10) */
    [controller miiWriteBit:1];
    [controller miiWriteBit:0];

    /* Write data (16 bits) */
    for (i = 15; i >= 0; i--) {
        [controller miiWriteBit:(value >> i) & 1];
    }
}

- (BOOL)findPHY
{
    int addr;
    unsigned int id1, id2;

    /* Search for PHY on all addresses */
    for (addr = 0; addr < 32; addr++) {
        phyAddress = addr;

        id1 = [self readRegister:MII_PHY_ID1];
        id2 = [self readRegister:MII_PHY_ID2];

        if (id1 != 0xFFFF && id1 != 0x0000) {
            phyID = (id1 << 16) | id2;
            IOLog("EtherLinkXLMII: Found PHY at address %d, ID 0x%08x\n", addr, phyID);
            return YES;
        }
    }

    return NO;
}

- (void)resetPHY
{
    int i;

    /* Issue PHY reset */
    [self writeRegister:MII_CONTROL value:MII_CTRL_RESET];

    /* Wait for reset to complete */
    for (i = 0; i < 1000; i++) {
        IODelay(10);
        if (!([self readRegister:MII_CONTROL] & MII_CTRL_RESET)) {
            break;
        }
    }

    if (i >= 1000) {
        IOLog("EtherLinkXLMII: PHY reset timeout\n");
    }
}

- (void)autoNegotiate
{
    unsigned int advertise;
    int i;

    /* Read current capabilities */
    phyStatus = [self readRegister:MII_STATUS];

    /* Configure advertise register */
    advertise = MII_ADV_SELECTOR;

    if (phyStatus & MII_STAT_100_FULL) {
        advertise |= MII_ADV_100_FULL;
    }
    if (phyStatus & MII_STAT_100_HALF) {
        advertise |= MII_ADV_100_HALF;
    }
    if (phyStatus & MII_STAT_10_FULL) {
        advertise |= MII_ADV_10_FULL;
    }
    if (phyStatus & MII_STAT_10_HALF) {
        advertise |= MII_ADV_10_HALF;
    }

    [self writeRegister:MII_ADVERTISE value:advertise];

    /* Enable and restart auto-negotiation */
    [self writeRegister:MII_CONTROL value:(MII_CTRL_AUTO_ENABLE | MII_CTRL_AUTO_RESTART)];

    /* Wait for auto-negotiation to complete */
    for (i = 0; i < 3000; i++) {
        IODelay(10);
        phyStatus = [self readRegister:MII_STATUS];
        if (phyStatus & MII_STAT_AUTO_DONE) {
            break;
        }
    }

    /* Check link status */
    [self checkLinkStatus];
}

- (void)checkLinkStatus
{
    unsigned int linkPartner;

    phyStatus = [self readRegister:MII_STATUS];
    linkUp = (phyStatus & MII_STAT_LINK_UP) ? YES : NO;

    if (!linkUp) {
        IOLog("EtherLinkXLMII: Link down\n");
        return;
    }

    /* Get link partner capabilities */
    linkPartner = [self readRegister:MII_LINK_PARTNER];
    phyAdvertise = [self readRegister:MII_ADVERTISE];

    /* Determine link speed and duplex */
    if ((phyAdvertise & MII_ADV_100_FULL) && (linkPartner & MII_ADV_100_FULL)) {
        linkSpeed = 100;
        fullDuplex = YES;
    } else if ((phyAdvertise & MII_ADV_100_HALF) && (linkPartner & MII_ADV_100_HALF)) {
        linkSpeed = 100;
        fullDuplex = NO;
    } else if ((phyAdvertise & MII_ADV_10_FULL) && (linkPartner & MII_ADV_10_FULL)) {
        linkSpeed = 10;
        fullDuplex = YES;
    } else if ((phyAdvertise & MII_ADV_10_HALF) && (linkPartner & MII_ADV_10_HALF)) {
        linkSpeed = 10;
        fullDuplex = NO;
    } else {
        linkSpeed = 10;
        fullDuplex = NO;
    }

    IOLog("EtherLinkXLMII: Link up, %d Mbps %s duplex\n",
          linkSpeed, fullDuplex ? "full" : "half");

    /* Configure controller */
    [controller setFullDuplex:fullDuplex];
}

- (void)setSpeed:(unsigned int)speed
{
    unsigned int control;

    control = [self readRegister:MII_CONTROL];
    control &= ~MII_CTRL_SPEED_100;

    if (speed == 100) {
        control |= MII_CTRL_SPEED_100;
    }

    [self writeRegister:MII_CONTROL value:control];
    linkSpeed = speed;
}

- (void)setDuplex:(BOOL)duplex
{
    unsigned int control;

    control = [self readRegister:MII_CONTROL];
    control &= ~MII_CTRL_DUPLEX;

    if (duplex) {
        control |= MII_CTRL_DUPLEX;
    }

    [self writeRegister:MII_CONTROL value:control];
    fullDuplex = duplex;

    /* Configure controller */
    [controller setFullDuplex:duplex];
}

- (void)setAutoNegotiate:(BOOL)enable
{
    if (enable) {
        [self autoNegotiate];
    } else {
        unsigned int control;

        control = [self readRegister:MII_CONTROL];
        control &= ~MII_CTRL_AUTO_ENABLE;
        [self writeRegister:MII_CONTROL value:control];
    }
}

- (BOOL)isLinkUp
{
    return linkUp;
}

- (BOOL)isFullDuplex
{
    return fullDuplex;
}

- (unsigned int)getLinkSpeed
{
    return linkSpeed;
}

@end
