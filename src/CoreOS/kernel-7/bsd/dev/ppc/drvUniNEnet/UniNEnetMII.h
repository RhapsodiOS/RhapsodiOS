/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER@
 */

/*
 * Copyright (c) 1998-1999 by Apple Computer, Inc., All rights reserved.
 *
 * MII/PHY support methods for UniN Ethernet.
 *
 * HISTORY
 *
 */

/* MII registers */
#define MII_CONTROL             0
#define MII_STATUS              1
#define MII_ID0                 2
#define MII_ID1                 3
#define MII_ADVERTISEMENT       4

@interface UniNEnet(MII)
- (BOOL)miiReadWord:(unsigned short *)dataPtr reg:(unsigned short)reg phy:(unsigned char)phy;
- (BOOL)miiWriteWord:(unsigned short)data reg:(unsigned short)reg phy:(unsigned char)phy;
- (BOOL)miiResetPHY:(unsigned char)phy;
- (BOOL)miiWaitForLink:(unsigned char)phy;
- (BOOL)miiWaitForAutoNegotiation:(unsigned char)phy;
- (void)miiRestartAutoNegotiation:(unsigned char)phy;
- (BOOL)miiFindPHY:(unsigned char *)phy;
- (BOOL)miiInitializePHY:(unsigned char)phy;
@end
