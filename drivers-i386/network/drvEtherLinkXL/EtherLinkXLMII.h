/*
 * Copyright (c) 1998 3Com Corporation. All rights reserved.
 *
 * EtherLink XL MII (Media Independent Interface) Support
 */

#import <objc/Object.h>

@class EtherLinkXL;

@interface EtherLinkXLMII : Object
{
    EtherLinkXL *controller;

    /* MII state */
    unsigned int phyAddress;
    unsigned int phyID;
    unsigned int phyStatus;
    unsigned int phyControl;
    unsigned int phyAdvertise;
    unsigned int phyLinkPartner;

    /* Link status */
    BOOL linkUp;
    BOOL fullDuplex;
    unsigned int linkSpeed;  /* 10 or 100 Mbps */
}

/* Initialization */
- initWithController:(EtherLinkXL *)ctrl;
- free;

/* MII register access */
- (unsigned int)readRegister:(unsigned int)reg;
- (void)writeRegister:(unsigned int)reg value:(unsigned int)value;

/* PHY operations */
- (BOOL)findPHY;
- (void)resetPHY;
- (void)autoNegotiate;
- (void)checkLinkStatus;

/* Configuration */
- (void)setSpeed:(unsigned int)speed;
- (void)setDuplex:(BOOL)duplex;
- (void)setAutoNegotiate:(BOOL)enable;

/* Status */
- (BOOL)isLinkUp;
- (BOOL)isFullDuplex;
- (unsigned int)getLinkSpeed;

@end

/* MII register definitions */
#define MII_CONTROL             0x00
#define MII_STATUS              0x01
#define MII_PHY_ID1             0x02
#define MII_PHY_ID2             0x03
#define MII_ADVERTISE           0x04
#define MII_LINK_PARTNER        0x05
#define MII_EXPANSION           0x06

/* MII control register bits */
#define MII_CTRL_RESET          0x8000
#define MII_CTRL_LOOPBACK       0x4000
#define MII_CTRL_SPEED_100      0x2000
#define MII_CTRL_AUTO_ENABLE    0x1000
#define MII_CTRL_POWER_DOWN     0x0800
#define MII_CTRL_ISOLATE        0x0400
#define MII_CTRL_AUTO_RESTART   0x0200
#define MII_CTRL_DUPLEX         0x0100
#define MII_CTRL_COL_TEST       0x0080

/* MII status register bits */
#define MII_STAT_100_T4         0x8000
#define MII_STAT_100_FULL       0x4000
#define MII_STAT_100_HALF       0x2000
#define MII_STAT_10_FULL        0x1000
#define MII_STAT_10_HALF        0x0800
#define MII_STAT_AUTO_DONE      0x0020
#define MII_STAT_REMOTE_FAULT   0x0010
#define MII_STAT_AUTO_CAP       0x0008
#define MII_STAT_LINK_UP        0x0004
#define MII_STAT_JABBER         0x0002
#define MII_STAT_EXTENDED       0x0001

/* MII advertise register bits */
#define MII_ADV_100_FULL        0x0100
#define MII_ADV_100_HALF        0x0080
#define MII_ADV_10_FULL         0x0040
#define MII_ADV_10_HALF         0x0020
#define MII_ADV_SELECTOR        0x001F
