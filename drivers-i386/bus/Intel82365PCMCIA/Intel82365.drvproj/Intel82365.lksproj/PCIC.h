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
 * Intel 82365 PCMCIA Controller Driver
 */

#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/PCMCIA.h>
#import <driverkit/i386/PCMCIAKernBus.h>

/* Forward declarations */
@class PCMCIAKernBus;

@interface PCIC : IODevice
{
    unsigned int basePort;
    unsigned int numSockets;
    unsigned int irqLevel;
    id pcmciaBus;              /* PCMCIAKernBus instance */
    BOOL *cardPresent;         /* Array tracking card presence per socket */
    id lock;                   /* NXLock for thread safety */
}

/* Instance methods */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/* Power management */
- (IOReturn)setPowerState:(unsigned int)socket state:(unsigned int)state;
- (IOReturn)getPowerState:(unsigned int)socket state:(unsigned int *)state;

/* Window management */
- (IOReturn)setMemoryWindow:(unsigned int)window
                     socket:(unsigned int)socket
                       base:(unsigned int)base
                       size:(unsigned int)size
                     offset:(unsigned int)offset
                      flags:(unsigned int)flags;

- (IOReturn)setIOWindow:(unsigned int)window
                 socket:(unsigned int)socket
                   base:(unsigned int)base
                   size:(unsigned int)size
                  flags:(unsigned int)flags;

/* Socket management */
- (IOReturn)getSocketStatus:(unsigned int)socket status:(unsigned int *)status;
- (IOReturn)resetSocket:(unsigned int)socket;
- (IOReturn)enableSocket:(unsigned int)socket;
- (IOReturn)disableSocket:(unsigned int)socket;

/* Interrupt handling */
- (void)interruptOccurred;
- (void)cardStatusChangeHandler:(unsigned int)socket;
- (IOReturn)enableCardStatusChangeInterrupts:(unsigned int)socket;
- (IOReturn)disableCardStatusChangeInterrupts:(unsigned int)socket;

/* Voltage detection and configuration */
- (IOReturn)detectCardVoltage:(unsigned int)socket voltage:(unsigned int *)voltage;
- (IOReturn)setCardVoltage:(unsigned int)socket voltage:(unsigned int)voltage;
- (BOOL)supportsVoltage:(unsigned int)socket voltage:(unsigned int)voltage;

/* Timing configuration */
- (IOReturn)setCommandTiming:(unsigned int)socket setup:(unsigned int)setup hold:(unsigned int)hold;
- (IOReturn)setMemoryTiming:(unsigned int)socket speed:(unsigned int)speed;

/* Card information */
- (IOReturn)getCardType:(unsigned int)socket type:(unsigned int *)type;
- (const char *)getCardTypeString:(unsigned int)type;

/* Advanced socket control */
- (IOReturn)forceCardEject:(unsigned int)socket;
- (IOReturn)lockCard:(unsigned int)socket;
- (IOReturn)unlockCard:(unsigned int)socket;

/* Internal methods */
- (unsigned char)readRegister:(unsigned int)socket offset:(unsigned int)offset;
- (void)writeRegister:(unsigned int)socket offset:(unsigned int)offset value:(unsigned char)value;
- (IOReturn)waitForReady:(unsigned int)socket timeout:(unsigned int)timeout;
- (void)dumpRegisters:(unsigned int)socket;

@end

/* PCIC Register offsets */
#define PCIC_ID_REVISION        0x00
#define PCIC_STATUS             0x01
#define PCIC_POWER              0x02
#define PCIC_INT_GEN_CTRL       0x03
#define PCIC_CARD_STATUS        0x04
#define PCIC_CARD_STATUS_CHG    0x05
#define PCIC_IO_WINDOW_0        0x06
#define PCIC_IO_WINDOW_0_START_LSB  0x06
#define PCIC_IO_WINDOW_0_START_MSB  0x07
#define PCIC_IO_WINDOW_0_END_LSB    0x08
#define PCIC_IO_WINDOW_0_END_MSB    0x09
#define PCIC_IO_WINDOW_1        0x0E
#define PCIC_IO_WINDOW_1_START_LSB  0x0C
#define PCIC_IO_WINDOW_1_START_MSB  0x0D
#define PCIC_IO_WINDOW_1_END_LSB    0x0E
#define PCIC_IO_WINDOW_1_END_MSB    0x0F
#define PCIC_MEM_WINDOW_0       0x10
#define PCIC_MEM_WINDOW_1       0x18
#define PCIC_MEM_WINDOW_2       0x20
#define PCIC_MEM_WINDOW_3       0x28
#define PCIC_MEM_WINDOW_4       0x30
#define PCIC_IO_CONTROL         0x07
#define PCIC_IO_WINDOW_CTRL     0x07
#define PCIC_CARD_DETECT        0x16
#define PCIC_TIMING_0           0x3A
#define PCIC_TIMING_1           0x3B
#define PCIC_MISC_CTRL_1        0x16
#define PCIC_MISC_CTRL_2        0x1E
#define PCIC_GLOBAL_CONTROL     0x1E

/* PCIC Status register bits */
#define PCIC_STATUS_CD1         0x01
#define PCIC_STATUS_CD2         0x02
#define PCIC_STATUS_READY       0x20
#define PCIC_STATUS_POWER       0x40
#define PCIC_STATUS_BUSY        0x80

/* PCIC Power control bits */
#define PCIC_POWER_VCC_5V       0x10
#define PCIC_POWER_VCC_3V       0x18
#define PCIC_POWER_VPP1_5V      0x01
#define PCIC_POWER_VPP1_12V     0x02
#define PCIC_POWER_VPP2_5V      0x04
#define PCIC_POWER_VPP2_12V     0x08
#define PCIC_POWER_OUTPUT_ENA   0x80

/* PCIC Interrupt and General Control */
#define PCIC_IGCTRL_IRQ_MASK    0x0F
#define PCIC_IGCTRL_INTR_ENA    0x10
#define PCIC_IGCTRL_CARD_RESET  0x40
#define PCIC_IGCTRL_RING_IND    0x80

/* PCIC Card Status Change */
#define PCIC_CSC_CD             0x08
#define PCIC_CSC_READY          0x04
#define PCIC_CSC_BATTWARN       0x02
#define PCIC_CSC_BATTDEAD       0x01

/* PCMCIA Power State Flags */
#define PCMCIA_VCC_5V           0x01
#define PCMCIA_VCC_3V           0x02
#define PCMCIA_VPP1_5V          0x04
#define PCMCIA_VPP1_12V         0x08
#define PCMCIA_VPP2_5V          0x10
#define PCMCIA_VPP2_12V         0x20

/* Card voltage detection flags */
#define PCMCIA_VS1              0x01    /* Voltage Sense 1 */
#define PCMCIA_VS2              0x02    /* Voltage Sense 2 */

/* Card types based on voltage sense pins */
#define PCMCIA_CARD_TYPE_5V     0       /* 5V card (VS1=1, VS2=1) */
#define PCMCIA_CARD_TYPE_3V     1       /* 3.3V card (VS1=0, VS2=1) */
#define PCMCIA_CARD_TYPE_XV     2       /* X.V card (VS1=1, VS2=0) */
#define PCMCIA_CARD_TYPE_YV     3       /* Y.V card (VS1=0, VS2=0) */

/* Card Status Change Enable register bits */
#define PCIC_CSCEN_CD           0x08    /* Card Detect enable */
#define PCIC_CSCEN_READY        0x04    /* Ready enable */
#define PCIC_CSCEN_BATTWARN     0x02    /* Battery warning enable */
#define PCIC_CSCEN_BATTDEAD     0x01    /* Battery dead enable */

/* I/O Control register bits */
#define PCIC_IOCTRL_16BIT       0x01    /* 16-bit I/O */
#define PCIC_IOCTRL_IOCS16      0x02    /* IOCS16 source */
#define PCIC_IOCTRL_0WS         0x04    /* Zero wait state */
#define PCIC_IOCTRL_WS          0x08    /* Wait state */

/* Timing register bits */
#define PCIC_TIMING_COMMAND_SLOW    0x00
#define PCIC_TIMING_COMMAND_MEDIUM  0x01
#define PCIC_TIMING_COMMAND_FAST    0x02
#define PCIC_TIMING_MEMORY_SLOW     0x00
#define PCIC_TIMING_MEMORY_MEDIUM   0x10
#define PCIC_TIMING_MEMORY_FAST     0x20

/* Misc Control register bits */
#define PCIC_MISC1_VCC_33       0x80    /* 3.3V VCC */
#define PCIC_MISC1_5V_DETECT    0x01    /* 5V card detect */
#define PCIC_MISC1_INPACK       0x80    /* INPACK enable */

/* Ready timeout in milliseconds */
#define PCIC_READY_TIMEOUT      1000
