/*
 * Copyright (c) 1999-2000 Apple Computer, Inc.
 *
 * Driver class for PacketEngines Gigabit Ethernet (Yellowfin/Hamachi) adapters.
 * PowerPC specific implementation.
 *
 * HISTORY
 *
 * 7 Oct 2025
 *	Created for RhapsodiOS Project.
 */

#import <driverkit/IOEthernet.h>
#import <driverkit/ppc/IOPPCDeviceDescription.h>
#import "PPCGNicHdw.h"

/* Chip types */
typedef enum {
    CHIP_TYPE_YELLOWFIN = 0,
    CHIP_TYPE_HAMACHI = 1
} PPCGNicChipType;

@interface PPCGNic:IOEthernet
{
    IOPPCDeviceDescription *deviceDescription;
    vm_offset_t		ioBase;		/* I/O base address 		     */
    vm_offset_t		memBase;	/* Memory mapped base address	     */
    int			irq;		/* Interrupt line		     */
    enet_addr_t		myAddress;	/* Local ethernet address	     */
    IONetwork		*network;	/* Handle to kernel network object   */

    PPCGNicChipType	chipType;	/* Yellowfin or Hamachi		     */
    unsigned int	chipRevision;	/* Chip revision number		     */

    id			transmitQueue;	/* Queue for outgoing packets 	     */
    BOOL		transmitActive;	/* Transmit in progress 	     */

    /* DMA descriptor rings */
    vm_offset_t		rxRingPhys;	/* Physical address of RX ring	     */
    vm_offset_t		txRingPhys;	/* Physical address of TX ring	     */
    void		*rxRing;	/* Virtual address of RX ring	     */
    void		*txRing;	/* Virtual address of TX ring	     */

    unsigned int	rxHead;		/* Current RX descriptor index	     */
    unsigned int	txHead;		/* Current TX descriptor index	     */
    unsigned int	txTail;		/* TX completion index		     */

    /* Ring sizes */
    unsigned int	rxRingSize;	/* Number of RX descriptors	     */
    unsigned int	txRingSize;	/* Number of TX descriptors	     */

    /* Buffer tracking */
    void		**rxBuffers;	/* Array of RX buffer pointers	     */
    void		**txBuffers;	/* Array of TX buffer pointers	     */
    netbuf_t		*txNetbufs;	/* Array of TX netbuf pointers	     */

    /* Statistics */
    unsigned int	rxPackets;
    unsigned int	txPackets;
    unsigned int	rxErrors;
    unsigned int	txErrors;

    /* PHY/MII management */
    unsigned int	phyAddr;	/* PHY address			     */
    BOOL		fullDuplex;	/* Full duplex mode		     */
    BOOL		gigabitMode;	/* Gigabit mode enabled		     */

    /* Driver state */
    BOOL		isOpen;
    BOOL		promiscuousMode;
    BOOL		multicastMode;
}

+ (BOOL)probe:(IODeviceDescription *)devDesc;

- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- free;

- (IOReturn)enableAllInterrupts;
- (void)disableAllInterrupts;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)timeoutOccurred;
- (void)interruptOccurred;

- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;

- (void)transmit:(netbuf_t)pkt;

/* Private methods */
- (BOOL)_initHardware;
- (void)_resetHardware;
- (BOOL)_setupRings;
- (void)_freeRings;
- (void)_initPHY;
- (void)_updateLinkStatus;
- (void)_handleReceive;
- (void)_handleTransmit;
- (void)_doTransmit:(netbuf_t)pkt;
- (unsigned int)_readMII:(unsigned int)reg;
- (void)_writeMII:(unsigned int)reg value:(unsigned int)val;

@end
