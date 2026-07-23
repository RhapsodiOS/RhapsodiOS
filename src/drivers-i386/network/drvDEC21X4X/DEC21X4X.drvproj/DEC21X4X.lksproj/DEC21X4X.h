/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * DEC21X4X.h
 * Header file for DEC 21x4x Ethernet driver
 */

#ifndef _DEC21X4X_H
#define _DEC21X4X_H

#import <driverkit/IOEthernetController.h>
#import <driverkit/IONetbuf.h>
#import <objc/objc.h>

// Forward declarations
typedef int BOOL;
#ifndef YES
#define YES 1
#endif
#ifndef NO
#define NO 0
#endif

// Table size constants
#define MEDIUM_STRING_COUNT        18
#define MEDIA_BIT_TABLE_COUNT      18
#define CONNECTOR_TABLE_COUNT      12
#define CONNECTOR_MEDIA_MAP_COUNT  12
#define MEDIA_TO_MII_TYPE_COUNT    9
#define PHY_REGS_COUNT             32

// Media type indices
#define MEDIA_10BASET              0
#define MEDIA_10BASE2              1
#define MEDIA_10BASE5              2
#define MEDIA_100BASETX            3
#define MEDIA_10BASET_FD           4
#define MEDIA_100BASETX_FD         5
#define MEDIA_100BASET4            6
#define MEDIA_100BASEFX            7
#define MEDIA_100BASEFX_FD         8
#define MEDIA_MII_10BASET          9
#define MEDIA_MII_10BASET_FD       10
#define MEDIA_MII_10BASE2          11
#define MEDIA_MII_10BASE5          12
#define MEDIA_MII_100BASETX        13
#define MEDIA_MII_100BASETX_FD     14
#define MEDIA_MII_100BASET4        15
#define MEDIA_MII_100BASEFX        16
#define MEDIA_MII_100BASEFX_FD     17

// Connector type indices
#define CONNECTOR_AUTOSENSE        0
#define CONNECTOR_AUTOSENSE_NO_NWAY 1
#define CONNECTOR_TP               2
#define CONNECTOR_TP_FD            3
#define CONNECTOR_10BASE2          4
#define CONNECTOR_10BASE5          5
#define CONNECTOR_100BASETX        6
#define CONNECTOR_100BASETX_FD     7
#define CONNECTOR_100BASET4        8
#define CONNECTOR_100BASEFX        9
#define CONNECTOR_100BASEFX_FD     10
#define CONNECTOR_MII              11

// Chip revision IDs
#define CHIP_REV_DC21040           0x21011
#define CHIP_REV_DC21142           0x191011
#define CHIP_REV_DC21143           0xff1011

// CSR (Control Status Register) offsets
#define CSR0_BUS_MODE              0x00
#define CSR1_TX_POLL_DEMAND        0x08
#define CSR2_RX_POLL_DEMAND        0x10
#define CSR3_RX_LIST_BASE          0x18
#define CSR4_TX_LIST_BASE          0x20
#define CSR5_STATUS                0x28
#define CSR6_OPMODE                0x30
#define CSR7_INTERRUPT_ENABLE      0x38
#define CSR8_MISSED_FRAMES         0x40
#define CSR9_SROM_MII              0x48
#define CSR11_TIMER                0x58
#define CSR12_SIA_STATUS           0x60
#define CSR13_SIA_CONNECTIVITY     0x68
#define CSR14_SIA_TX_RX            0x70
#define CSR15_SIA_GENERAL          0x78

// DEC21142 class interface
@interface DEC21142 : IOEthernetController
{
    // Instance variables will be defined here
}

// Initialization methods
- (BOOL)_initAdapter;
- (BOOL)_parseSROM;
- (BOOL)_resetAndInitAdapter;
- free;

// Interrupt handling
- (void)interruptOccurred;

@end

// Utility function declarations (defined in DEC21X4XUtil.c)
extern void DC21X4DisableInterrupt(void *adapter);
extern void DC21X4EnableInterrupt(void *adapter);
extern void DC21X4StopAutoSenseTimer(void *adapter);
extern void DC21X4StopAdapter(void *adapter);
extern void DC21X4WriteGepRegister(void *adapter, unsigned short value);
extern BOOL DC21X4PhyInit(void *adapter);
extern void DC21X4EnableNway(void *adapter);
extern void DC21X4DisableNway(void *adapter);
extern BOOL DC21X4SetPhyConnection(void *adapter);
extern void DC21X4StopReceiverAndTransmitter(void *adapter);
extern void DC21X4InitializeMediaRegisters(void *adapter, int reset);
extern void DC21X4StartAdapter(void *adapter);
extern BOOL DC21X4MediaDetect(void *adapter);
extern BOOL DC21X4MiiAutoDetect(void *adapter);
extern void DC21X4StartAutoSenseTimer(void *adapter, int timeout);
extern void DC21X4DynamicAutoSense(void *timerArg, int adapter);
extern int DC21X4AutoSense(unsigned int adapter);
extern BOOL DC2114Sense100BaseTxLink(int adapter);
extern void DC2104InitializeSiaRegisters(int adapter, unsigned int resetValue);
extern BOOL DC21040Parser(int adapter);
extern BOOL DC21X4ParseSRom(void *adapter, void *sromData);
extern unsigned int CRC32(unsigned char *data, int length);
extern const char *getDriverName(void *adapter);

// Interrupt handler functions
extern void HandleGepInterrupt(void *adapter);
extern void HandleLinkFailInterrupt(void *adapter, unsigned int *status);
extern void HandleLinkPassInterrupt(void *adapter, unsigned int *status);
extern void HandleLinkChangeInterrupt(void *adapter);

// MII/PHY functions (defined in DEC21X4XMII.c)
extern BOOL MiiPhyInit(void *adapter);
extern BOOL MiiPhyReset(void *adapter, int phyIndex);
extern BOOL MiiReadRegister(void *adapter, unsigned char phyAddress,
                            unsigned char regAddress, unsigned short *data);
extern BOOL MiiWriteRegister(void *adapter, unsigned char phyAddress,
                             unsigned char regAddress, unsigned short data);
extern BOOL MiiWaitForAutoNegotiation(void *adapter, int phyIndex);
extern void MiiSetCapabilities(void *adapter, int phyIndex, unsigned short capabilities);
extern void ConvertNwayToConnectionType(unsigned short nwayResult, unsigned short *connectionType);
extern void ConvertMediaTypeToNwayLocalAbility(unsigned char mediaType, unsigned short *nwayAbility);
extern void ConvertConnectionToControl(int phyStructure, unsigned short *connectionType);
extern unsigned short CheckConnectionSupport(int phyStructure, unsigned short connectionType);

// Lookup tables (defined in DEC21X4XUtil.c)
extern const char *MediumString[];
extern const unsigned short MediaBitTable[];
extern const unsigned char ConvertMediaTypeToMiiType[];
extern const char *connectorTable[];
extern const unsigned int connectorMediaMap[];

// Global variables
extern BOOL mediaSupported;

#endif /* _DEC21X4X_H */
