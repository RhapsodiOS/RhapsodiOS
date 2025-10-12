/*
 * Copyright (c) 1999-2000 Apple Computer, Inc.
 *
 * Driver for PacketEngines Gigabit Ethernet (Yellowfin/Hamachi) adapters.
 * PowerPC specific implementation.
 *
 * Based on Linux drivers by Donald Becker and others.
 *
 * HISTORY
 *
 * 7 Oct 2025
 *	Created for RhapsodiOS Project.
 */

#define MACH_USER_API	1

#import <driverkit/generalFuncs.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/align.h>
#import <kernserv/kern_server_types.h>
#import <kernserv/prototypes.h>
#import <machkit/NXLock.h>

#import "PPCGNic.h"

/* Debug logging */
#ifdef DEBUG
#define DLOG(fmt, args...)	IOLog("PPCGNic: " fmt, ## args)
#else
#define DLOG(fmt, args...)
#endif

/* Register access macros */
#define READ_REG(offset)	(*(volatile unsigned int *)((ioBase) + (offset)))
#define WRITE_REG(offset, val)	(*(volatile unsigned int *)((ioBase) + (offset)) = (val))

@implementation PPCGNic

/*
 * probe - Check if this is our device
 */
+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    unsigned int vendor, device;

    if ([devDesc numPortRanges] < 1)
	return NO;

    /* Get PCI vendor and device IDs */
    vendor = [devDesc getPCIConfigData:0x00] & 0xFFFF;
    device = ([devDesc getPCIConfigData:0x00] >> 16) & 0xFFFF;

    /* Check for Packet Engines Yellowfin */
    if (vendor == PCI_VENDOR_PACKET_ENGINES && device == PCI_DEVICE_YELLOWFIN) {
	IOLog("PPCGNic: Found Packet Engines Yellowfin Gigabit Ethernet\n");
	return YES;
    }

    /* Check for Packet Engines Hamachi */
    if (vendor == PCI_VENDOR_PACKET_ENGINES && device == PCI_DEVICE_HAMACHI) {
	IOLog("PPCGNic: Found Packet Engines Hamachi Gigabit Ethernet\n");
	return YES;
    }

    /* Check for Symbios (rebadged) Yellowfin */
    if (vendor == PCI_VENDOR_SYMBIOS && device == PCI_DEVICE_YELLOWFIN) {
	IOLog("PPCGNic: Found Symbios Logic Yellowfin Gigabit Ethernet\n");
	return YES;
    }

    return NO;
}

/*
 * initFromDeviceDescription - Initialize the driver instance
 */
- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    unsigned int vendor, device;
    IORange *portRange;
    int i;

    [super initFromDeviceDescription:devDesc];

    deviceDescription = devDesc;

    /* Get vendor and device IDs to determine chip type */
    vendor = [devDesc getPCIConfigData:0x00] & 0xFFFF;
    device = ([devDesc getPCIConfigData:0x00] >> 16) & 0xFFFF;

    if (device == PCI_DEVICE_YELLOWFIN) {
	chipType = CHIP_TYPE_YELLOWFIN;
	IOLog("PPCGNic: Initializing Yellowfin adapter\n");
    } else if (device == PCI_DEVICE_HAMACHI) {
	chipType = CHIP_TYPE_HAMACHI;
	IOLog("PPCGNic: Initializing Hamachi adapter\n");
    } else {
	IOLog("PPCGNic: Unknown device ID 0x%x\n", device);
	[self free];
	return nil;
    }

    /* Get chip revision */
    chipRevision = [devDesc getPCIConfigData:0x08] & 0xFF;
    DLOG("Chip revision: 0x%x\n", chipRevision);

    /* Get I/O base address */
    portRange = [devDesc portRangeList];
    ioBase = portRange[0].start;
    DLOG("I/O base: 0x%lx\n", ioBase);

    /* Get IRQ */
    irq = [devDesc interrupt];
    DLOG("IRQ: %d\n", irq);

    /* Initialize ring sizes */
    rxRingSize = RX_RING_SIZE;
    txRingSize = TX_RING_SIZE;

    /* Initialize state */
    isOpen = NO;
    promiscuousMode = NO;
    multicastMode = NO;
    transmitActive = NO;
    fullDuplex = NO;
    gigabitMode = NO;

    /* Clear statistics */
    rxPackets = txPackets = 0;
    rxErrors = txErrors = 0;

    /* Create transmit queue */
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:TX_RING_SIZE];
    if (transmitQueue == nil) {
	IOLog("PPCGNic: Failed to allocate transmit queue\n");
	[self free];
	return nil;
    }

    /* Initialize hardware */
    if (![self _initHardware]) {
	IOLog("PPCGNic: Hardware initialization failed\n");
	[self free];
	return nil;
    }

    /* Read MAC address from hardware */
    if (chipType == CHIP_TYPE_YELLOWFIN) {
	/* Yellowfin stores MAC in config space */
	unsigned int mac_low = [devDesc getPCIConfigData:0x10];
	unsigned int mac_high = [devDesc getPCIConfigData:0x14];

	myAddress.ea_byte[0] = mac_low & 0xFF;
	myAddress.ea_byte[1] = (mac_low >> 8) & 0xFF;
	myAddress.ea_byte[2] = (mac_low >> 16) & 0xFF;
	myAddress.ea_byte[3] = (mac_low >> 24) & 0xFF;
	myAddress.ea_byte[4] = mac_high & 0xFF;
	myAddress.ea_byte[5] = (mac_high >> 8) & 0xFF;
    } else {
	/* Hamachi stores MAC in station address registers */
	unsigned int addr0 = READ_REG(HAM_StationAddr0);
	unsigned int addr1 = READ_REG(HAM_StationAddr1);

	myAddress.ea_byte[0] = addr0 & 0xFF;
	myAddress.ea_byte[1] = (addr0 >> 8) & 0xFF;
	myAddress.ea_byte[2] = (addr0 >> 16) & 0xFF;
	myAddress.ea_byte[3] = (addr0 >> 24) & 0xFF;
	myAddress.ea_byte[4] = addr1 & 0xFF;
	myAddress.ea_byte[5] = (addr1 >> 8) & 0xFF;
    }

    IOLog("PPCGNic: MAC Address: %02x:%02x:%02x:%02x:%02x:%02x\n",
	myAddress.ea_byte[0], myAddress.ea_byte[1], myAddress.ea_byte[2],
	myAddress.ea_byte[3], myAddress.ea_byte[4], myAddress.ea_byte[5]);

    /* Register with network subsystem */
    if (![self attachToNetworkWithAddress:myAddress]) {
	IOLog("PPCGNic: Failed to attach to network\n");
	[self free];
	return nil;
    }

    IOLog("PPCGNic: Driver initialized successfully\n");
    return self;
}

/*
 * free - Clean up and release resources
 */
- free
{
    if (isOpen)
	[self resetAndEnable:NO];

    [self _freeRings];

    if (transmitQueue)
	[transmitQueue free];

    return [super free];
}

/*
 * _initHardware - Initialize the hardware
 */
- (BOOL)_initHardware
{
    /* Reset the chip */
    [self _resetHardware];

    /* Setup descriptor rings */
    if (![self _setupRings]) {
	IOLog("PPCGNic: Failed to setup descriptor rings\n");
	return NO;
    }

    /* Initialize PHY */
    [self _initPHY];

    return YES;
}

/*
 * _resetHardware - Perform hardware reset
 */
- (void)_resetHardware
{
    int i;

    DLOG("Resetting hardware\n");

    if (chipType == CHIP_TYPE_YELLOWFIN) {
	/* Reset Yellowfin chip */
	WRITE_REG(YF_ChipConfig, CFG_RESET);

	/* Wait for reset to complete */
	for (i = 0; i < 1000; i++) {
	    IODelay(10);
	    if (!(READ_REG(YF_ChipConfig) & CFG_RESET))
		break;
	}

	if (i >= 1000)
	    IOLog("PPCGNic: Reset timeout\n");

	/* Enable MII interface */
	WRITE_REG(YF_ChipConfig, CFG_MII_ENABLE);

    } else {
	/* Reset Hamachi chip */
	WRITE_REG(HAM_PCIDeviceConfig, 0x00000001);
	IODelay(1000);
	WRITE_REG(HAM_PCIDeviceConfig, 0x00000000);
	IODelay(1000);
    }

    DLOG("Reset complete\n");
}

/*
 * _setupRings - Allocate and initialize descriptor rings
 */
- (BOOL)_setupRings
{
    unsigned int ringSize;
    int i;

    DLOG("Setting up descriptor rings\n");

    /* Allocate RX ring */
    if (chipType == CHIP_TYPE_YELLOWFIN) {
	ringSize = rxRingSize * sizeof(yellowfin_desc_t);
    } else {
	ringSize = rxRingSize * sizeof(hamachi_desc_t);
    }

    rxRing = IOMalloc(ringSize);
    if (!rxRing) {
	IOLog("PPCGNic: Failed to allocate RX ring\n");
	return NO;
    }
    bzero(rxRing, ringSize);
    rxRingPhys = (vm_offset_t)kvtophys((vm_offset_t)rxRing);

    /* Allocate TX ring */
    if (chipType == CHIP_TYPE_YELLOWFIN) {
	ringSize = txRingSize * sizeof(yellowfin_desc_t);
    } else {
	ringSize = txRingSize * sizeof(hamachi_desc_t);
    }

    txRing = IOMalloc(ringSize);
    if (!txRing) {
	IOLog("PPCGNic: Failed to allocate TX ring\n");
	IOFree(rxRing, rxRingSize * sizeof(yellowfin_desc_t));
	return NO;
    }
    bzero(txRing, ringSize);
    txRingPhys = (vm_offset_t)kvtophys((vm_offset_t)txRing);

    /* Allocate buffer tracking arrays */
    rxBuffers = (void **)IOMalloc(rxRingSize * sizeof(void *));
    txBuffers = (void **)IOMalloc(txRingSize * sizeof(void *));
    txNetbufs = (netbuf_t *)IOMalloc(txRingSize * sizeof(netbuf_t));

    if (!rxBuffers || !txBuffers || !txNetbufs) {
	IOLog("PPCGNic: Failed to allocate buffer tracking arrays\n");
	[self _freeRings];
	return NO;
    }

    bzero(rxBuffers, rxRingSize * sizeof(void *));
    bzero(txBuffers, txRingSize * sizeof(void *));
    bzero(txNetbufs, txRingSize * sizeof(netbuf_t));

    /* Allocate and setup RX buffers */
    for (i = 0; i < rxRingSize; i++) {
	rxBuffers[i] = IOMalloc(PKT_BUF_SZ);
	if (!rxBuffers[i]) {
	    IOLog("PPCGNic: Failed to allocate RX buffer %d\n", i);
	    [self _freeRings];
	    return NO;
	}

	/* Setup RX descriptor */
	if (chipType == CHIP_TYPE_YELLOWFIN) {
	    yellowfin_desc_t *desc = (yellowfin_desc_t *)rxRing + i;
	    desc->addr = (unsigned int)kvtophys((vm_offset_t)rxBuffers[i]);
	    desc->request_cnt = PKT_BUF_SZ | DESC_OWN;
	    desc->branch_addr = 0;
	    desc->result_status = 0;
	} else {
	    hamachi_desc_t *desc = (hamachi_desc_t *)rxRing + i;
	    desc->addr = (unsigned int)kvtophys((vm_offset_t)rxBuffers[i]);
	    desc->status_n_length = PKT_BUF_SZ | DESC_OWN;
	    desc->reserved1 = 0;
	    desc->reserved2 = 0;
	}
    }

    /* Initialize ring pointers */
    rxHead = 0;
    txHead = 0;
    txTail = 0;

    /* Configure hardware with ring addresses */
    if (chipType == CHIP_TYPE_YELLOWFIN) {
	WRITE_REG(YF_RxDescQPtr, rxRingPhys);
	WRITE_REG(YF_RxDescQLen, rxRingSize);
	WRITE_REG(YF_TxDescQPtr, txRingPhys);
	WRITE_REG(YF_TxDescQLen, txRingSize);
    } else {
	WRITE_REG(HAM_RxPtr, rxRingPhys);
	WRITE_REG(HAM_TxPtr, txRingPhys);
    }

    DLOG("Descriptor rings configured\n");
    return YES;
}

/*
 * _freeRings - Free descriptor rings
 */
- (void)_freeRings
{
    int i;

    /* Free RX buffers */
    if (rxBuffers) {
	for (i = 0; i < rxRingSize; i++) {
	    if (rxBuffers[i]) {
		IOFree(rxBuffers[i], PKT_BUF_SZ);
		rxBuffers[i] = NULL;
	    }
	}
	IOFree(rxBuffers, rxRingSize * sizeof(void *));
	rxBuffers = NULL;
    }

    /* Free TX buffers and netbufs */
    if (txBuffers) {
	for (i = 0; i < txRingSize; i++) {
	    if (txBuffers[i]) {
		IOFree(txBuffers[i], PKT_BUF_SZ);
		txBuffers[i] = NULL;
	    }
	}
	IOFree(txBuffers, txRingSize * sizeof(void *));
	txBuffers = NULL;
    }

    if (txNetbufs) {
	for (i = 0; i < txRingSize; i++) {
	    if (txNetbufs[i]) {
		nb_free(txNetbufs[i]);
		txNetbufs[i] = NULL;
	    }
	}
	IOFree(txNetbufs, txRingSize * sizeof(netbuf_t));
	txNetbufs = NULL;
    }

    if (rxRing) {
	if (chipType == CHIP_TYPE_YELLOWFIN) {
	    IOFree(rxRing, rxRingSize * sizeof(yellowfin_desc_t));
	} else {
	    IOFree(rxRing, rxRingSize * sizeof(hamachi_desc_t));
	}
	rxRing = NULL;
    }

    if (txRing) {
	if (chipType == CHIP_TYPE_YELLOWFIN) {
	    IOFree(txRing, txRingSize * sizeof(yellowfin_desc_t));
	} else {
	    IOFree(txRing, txRingSize * sizeof(hamachi_desc_t));
	}
	txRing = NULL;
    }
}

/*
 * _initPHY - Initialize the PHY/MII interface
 */
- (void)_initPHY
{
    unsigned int bmcr, bmsr;

    DLOG("Initializing PHY\n");

    /* Assume PHY address 0 */
    phyAddr = 0;

    /* Read PHY status */
    bmsr = [self _readMII:MII_BMSR];
    DLOG("PHY BMSR: 0x%x\n", bmsr);

    /* Reset PHY */
    [self _writeMII:MII_BMCR value:BMCR_RESET];
    IODelay(1000);

    /* Enable auto-negotiation */
    bmcr = BMCR_ANENABLE | BMCR_ANRESTART;
    [self _writeMII:MII_BMCR value:bmcr];

    /* Wait for auto-negotiation to complete */
    IOSleep(2000);

    [self _updateLinkStatus];
}

/*
 * _updateLinkStatus - Check and update link status
 */
- (void)_updateLinkStatus
{
    unsigned int bmsr, bmcr;

    bmsr = [self _readMII:MII_BMSR];
    bmcr = [self _readMII:MII_BMCR];

    if (bmsr & BMSR_LSTATUS) {
	DLOG("Link is UP\n");

	/* Check duplex mode */
	fullDuplex = (bmcr & BMCR_FULLDPLX) ? YES : NO;

	/* Check if gigabit mode */
	gigabitMode = (bmcr & BMCR_SPEED1000) ? YES : NO;

	DLOG("Mode: %s, %s\n",
	    gigabitMode ? "1000Mbps" : (bmcr & BMCR_SPEED100) ? "100Mbps" : "10Mbps",
	    fullDuplex ? "Full Duplex" : "Half Duplex");
    } else {
	DLOG("Link is DOWN\n");
    }
}

/*
 * _readMII - Read from MII register
 */
- (unsigned int)_readMII:(unsigned int)reg
{
    unsigned int cmd, data;
    int i;

    if (chipType == CHIP_TYPE_YELLOWFIN) {
	/* Yellowfin MII access */
	/* Build command: PHY address, register, read operation */
	cmd = ((phyAddr & 0x1F) << 8) | ((reg & 0x1F) << 0) | MII_START;

	/* Write command */
	WRITE_REG(YF_MIICmd, cmd);

	/* Wait for completion */
	for (i = 0; i < 1000; i++) {
	    IODelay(10);
	    if (!(READ_REG(YF_MIIStatus) & MII_BUSY))
		break;
	}

	if (i >= 1000) {
	    DLOG("MII read timeout\n");
	    return 0xFFFF;
	}

	/* Read data */
	data = READ_REG(YF_MIIData) & 0xFFFF;
	return data;

    } else {
	/* Hamachi MII access - through auto-negotiation registers */
	/* Hamachi has integrated PHY, use AN registers for basic control */
	if (reg == MII_BMCR) {
	    return READ_REG(HAM_ANControl) & 0xFFFF;
	} else if (reg == MII_BMSR) {
	    return READ_REG(HAM_ANStatus) & 0xFFFF;
	} else {
	    /* Not all registers accessible on Hamachi */
	    return 0;
	}
    }
}

/*
 * _writeMII - Write to MII register
 */
- (void)_writeMII:(unsigned int)reg value:(unsigned int)val
{
    unsigned int cmd;
    int i;

    if (chipType == CHIP_TYPE_YELLOWFIN) {
	/* Yellowfin MII access */
	/* Write data first */
	WRITE_REG(YF_MIIData, val & 0xFFFF);

	/* Build command: PHY address, register, write operation */
	cmd = ((phyAddr & 0x1F) << 8) | ((reg & 0x1F) << 0) |
	      MII_START | MII_WRITE_CMD;

	/* Write command */
	WRITE_REG(YF_MIICmd, cmd);

	/* Wait for completion */
	for (i = 0; i < 1000; i++) {
	    IODelay(10);
	    if (!(READ_REG(YF_MIIStatus) & MII_BUSY))
		break;
	}

	if (i >= 1000)
	    DLOG("MII write timeout\n");

    } else {
	/* Hamachi MII access - through auto-negotiation registers */
	if (reg == MII_BMCR) {
	    WRITE_REG(HAM_ANControl, val & 0xFFFF);
	} else if (reg == MII_BMSR) {
	    /* Status register is read-only */
	}
}

/*
 * resetAndEnable - Reset and optionally enable the adapter
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    DLOG("resetAndEnable: %d\n", enable);

    if (enable) {
	/* Enable receiver and transmitter */
	if (chipType == CHIP_TYPE_YELLOWFIN) {
	    WRITE_REG(YF_RxConfig, RX_ENABLE | RX_ACCEPT_BROADCAST | RX_STRIP_CRC);
	    WRITE_REG(YF_TxConfig, TX_ENABLE | TX_AUTO_PAD | TX_ADD_CRC);
	} else {
	    WRITE_REG(HAM_RxCmd, RX_ENABLE);
	    WRITE_REG(HAM_TxCmd, TX_ENABLE);
	}

	isOpen = YES;
    } else {
	/* Disable receiver and transmitter */
	if (chipType == CHIP_TYPE_YELLOWFIN) {
	    WRITE_REG(YF_RxConfig, 0);
	    WRITE_REG(YF_TxConfig, 0);
	} else {
	    WRITE_REG(HAM_RxCmd, 0);
	    WRITE_REG(HAM_TxCmd, 0);
	}

	isOpen = NO;
    }

    return YES;
}

/*
 * enableAllInterrupts - Enable interrupts
 */
- (IOReturn)enableAllInterrupts
{
    unsigned int intr_mask;

    DLOG("Enabling interrupts\n");

    /* Enable common interrupts */
    intr_mask = INTR_RX_DONE | INTR_TX_DONE | INTR_LINK_CHANGE |
		INTR_ABNORMAL_SUMMARY | INTR_NORMAL_SUMMARY;

    if (chipType == CHIP_TYPE_YELLOWFIN) {
	WRITE_REG(YF_IntrEnb, intr_mask);
    } else {
	WRITE_REG(HAM_IntrEnb, intr_mask);
    }

    return IO_R_SUCCESS;
}

/*
 * disableAllInterrupts - Disable interrupts
 */
- (void)disableAllInterrupts
{
    DLOG("Disabling interrupts\n");

    if (chipType == CHIP_TYPE_YELLOWFIN) {
	WRITE_REG(YF_IntrEnb, 0);
    } else {
	WRITE_REG(HAM_IntrEnb, 0);
    }
}

/*
 * interruptOccurred - Handle interrupt
 */
- (void)interruptOccurred
{
    unsigned int status;

    /* Read interrupt status */
    if (chipType == CHIP_TYPE_YELLOWFIN) {
	status = READ_REG(YF_IntrStatus);
	WRITE_REG(YF_IntrClear, status);
    } else {
	status = READ_REG(HAM_IntrStatus);
	WRITE_REG(HAM_IntrStatus, status);
    }

    /* Handle receive */
    if (status & INTR_RX_DONE) {
	[self _handleReceive];
    }

    /* Handle transmit complete */
    if (status & INTR_TX_DONE) {
	[self _handleTransmit];
    }

    /* Handle link change */
    if (status & INTR_LINK_CHANGE) {
	DLOG("Link change interrupt\n");
	[self _updateLinkStatus];
    }

    /* Handle errors */
    if (status & INTR_ABNORMAL_SUMMARY) {
	DLOG("Abnormal interrupt: 0x%x\n", status);
	rxErrors++;
    }
}

/*
 * _handleReceive - Process received packets
 */
- (void)_handleReceive
{
    unsigned int status, length;
    netbuf_t pkt;
    void *newBuf;
    int limit = rxRingSize; /* Process at most one full ring */

    while (limit-- > 0) {
	/* Check current RX descriptor */
	if (chipType == CHIP_TYPE_YELLOWFIN) {
	    yellowfin_desc_t *desc = (yellowfin_desc_t *)rxRing + rxHead;

	    /* Check if owned by hardware */
	    if (desc->request_cnt & DESC_OWN)
		break;

	    status = desc->result_status;
	    length = status & 0xFFFF;

	    /* Check for errors */
	    if (!(status & RX_STATUS_OK) || length > MAX_FRAME_SIZE) {
		DLOG("RX error: status=0x%x, length=%d\n", status, length);
		rxErrors++;

		/* Re-own the descriptor */
		desc->result_status = 0;
		desc->request_cnt = PKT_BUF_SZ | DESC_OWN;
		rxHead = (rxHead + 1) % rxRingSize;
		continue;
	    }

	    /* Allocate new buffer for this slot */
	    newBuf = IOMalloc(PKT_BUF_SZ);
	    if (!newBuf) {
		IOLog("PPCGNic: Failed to allocate RX buffer\n");
		/* Re-own descriptor and continue */
		desc->result_status = 0;
		desc->request_cnt = PKT_BUF_SZ | DESC_OWN;
		rxHead = (rxHead + 1) % rxRingSize;
		continue;
	    }

	    /* Allocate netbuf and copy data */
	    pkt = nb_alloc(length);
	    if (pkt) {
		nb_write(pkt, 0, length, rxBuffers[rxHead]);
		nb_shrink_bot(pkt, length);

		/* Pass to network stack */
		[network handleInputPacket:pkt extra:0];
		rxPackets++;
	    } else {
		IOLog("PPCGNic: Failed to allocate netbuf\n");
		rxErrors++;
		IOFree(newBuf, PKT_BUF_SZ);
		/* Re-own descriptor and continue */
		desc->result_status = 0;
		desc->request_cnt = PKT_BUF_SZ | DESC_OWN;
		rxHead = (rxHead + 1) % rxRingSize;
		continue;
	    }

	    /* Install new buffer in descriptor */
	    IOFree(rxBuffers[rxHead], PKT_BUF_SZ);
	    rxBuffers[rxHead] = newBuf;
	    desc->addr = (unsigned int)kvtophys((vm_offset_t)newBuf);
	    desc->result_status = 0;
	    desc->request_cnt = PKT_BUF_SZ | DESC_OWN;

	} else {
	    /* Hamachi */
	    hamachi_desc_t *desc = (hamachi_desc_t *)rxRing + rxHead;

	    /* Check if owned by hardware */
	    if (desc->status_n_length & DESC_OWN)
		break;

	    status = desc->status_n_length;
	    length = status & 0xFFFF;

	    /* Check for errors */
	    if (!(status & RX_STATUS_OK) || length > MAX_FRAME_SIZE) {
		DLOG("RX error: status=0x%x, length=%d\n", status, length);
		rxErrors++;

		/* Re-own the descriptor */
		desc->status_n_length = PKT_BUF_SZ | DESC_OWN;
		rxHead = (rxHead + 1) % rxRingSize;
		continue;
	    }

	    /* Allocate new buffer for this slot */
	    newBuf = IOMalloc(PKT_BUF_SZ);
	    if (!newBuf) {
		IOLog("PPCGNic: Failed to allocate RX buffer\n");
		desc->status_n_length = PKT_BUF_SZ | DESC_OWN;
		rxHead = (rxHead + 1) % rxRingSize;
		continue;
	    }

	    /* Allocate netbuf and copy data */
	    pkt = nb_alloc(length);
	    if (pkt) {
		nb_write(pkt, 0, length, rxBuffers[rxHead]);
		nb_shrink_bot(pkt, length);

		/* Pass to network stack */
		[network handleInputPacket:pkt extra:0];
		rxPackets++;
	    } else {
		IOLog("PPCGNic: Failed to allocate netbuf\n");
		rxErrors++;
		IOFree(newBuf, PKT_BUF_SZ);
		desc->status_n_length = PKT_BUF_SZ | DESC_OWN;
		rxHead = (rxHead + 1) % rxRingSize;
		continue;
	    }

	    /* Install new buffer in descriptor */
	    IOFree(rxBuffers[rxHead], PKT_BUF_SZ);
	    rxBuffers[rxHead] = newBuf;
	    desc->addr = (unsigned int)kvtophys((vm_offset_t)newBuf);
	    desc->status_n_length = PKT_BUF_SZ | DESC_OWN;
	}

	/* Move to next descriptor */
	rxHead = (rxHead + 1) % rxRingSize;
    }
}

/*
 * _handleTransmit - Process transmit completions
 */
- (void)_handleTransmit
{
    unsigned int status;
    int cleaned = 0;

    /* Process completed transmissions */
    while (txTail != txHead) {
	if (chipType == CHIP_TYPE_YELLOWFIN) {
	    yellowfin_desc_t *desc = (yellowfin_desc_t *)txRing + txTail;

	    /* Check if still owned by hardware */
	    if (desc->request_cnt & DESC_OWN)
		break;

	    status = desc->result_status;

	    /* Check for errors */
	    if (!(status & TX_STATUS_OK)) {
		DLOG("TX error: status=0x%x\n", status);
		txErrors++;
	    } else {
		txPackets++;
	    }

	    /* Free the netbuf */
	    if (txNetbufs[txTail]) {
		nb_free(txNetbufs[txTail]);
		txNetbufs[txTail] = NULL;
	    }

	    /* Clear descriptor */
	    desc->request_cnt = 0;
	    desc->result_status = 0;

	} else {
	    /* Hamachi */
	    hamachi_desc_t *desc = (hamachi_desc_t *)txRing + txTail;

	    /* Check if still owned by hardware */
	    if (desc->status_n_length & DESC_OWN)
		break;

	    status = desc->status_n_length;

	    /* Check for errors */
	    if (!(status & TX_STATUS_OK)) {
		DLOG("TX error: status=0x%x\n", status);
		txErrors++;
	    } else {
		txPackets++;
	    }

	    /* Free the netbuf */
	    if (txNetbufs[txTail]) {
		nb_free(txNetbufs[txTail]);
		txNetbufs[txTail] = NULL;
	    }

	    /* Clear descriptor */
	    desc->status_n_length = 0;
	}

	/* Move to next descriptor */
	txTail = (txTail + 1) % txRingSize;
	cleaned++;
    }

    /* If we cleaned any descriptors, check if we can send more */
    if (cleaned > 0) {
	netbuf_t pkt;

	/* Try to dequeue and send packets from transmit queue */
	while ((pkt = [transmitQueue dequeue]) != NULL) {
	    /* Check if ring is full */
	    if (((txHead + 1) % txRingSize) == txTail) {
		/* Ring full, re-queue packet and stop */
		[transmitQueue enqueuePriority:pkt];
		break;
	    }

	    /* Send the packet */
	    [self _doTransmit:pkt];
	}

	/* Update transmit active status */
	if (txHead == txTail) {
	    transmitActive = NO;
	}
    }
}

/*
 * _doTransmit - Actually send a packet (internal helper)
 */
- (void)_doTransmit:(netbuf_t)pkt
{
    unsigned int length;
    void *data;

    /* Get packet length and data */
    length = nb_size(pkt);
    if (length > MAX_FRAME_SIZE) {
	IOLog("PPCGNic: Packet too large (%d bytes)\n", length);
	nb_free(pkt);
	txErrors++;
	return;
    }

    /* Allocate buffer if needed */
    if (!txBuffers[txHead]) {
	txBuffers[txHead] = IOMalloc(PKT_BUF_SZ);
	if (!txBuffers[txHead]) {
	    IOLog("PPCGNic: Failed to allocate TX buffer\n");
	    nb_free(pkt);
	    txErrors++;
	    return;
	}
    }

    /* Copy packet data to TX buffer */
    nb_read(pkt, 0, length, txBuffers[txHead]);

    /* Save netbuf for later freeing */
    txNetbufs[txHead] = pkt;

    /* Setup descriptor */
    if (chipType == CHIP_TYPE_YELLOWFIN) {
	yellowfin_desc_t *desc = (yellowfin_desc_t *)txRing + txHead;

	desc->addr = (unsigned int)kvtophys((vm_offset_t)txBuffers[txHead]);
	desc->branch_addr = 0;
	desc->result_status = 0;
	/* Set length, end-of-packet, interrupt, and own bits */
	desc->request_cnt = length | DESC_END_PACKET | DESC_INTR | DESC_OWN;

	/* Notify hardware */
	WRITE_REG(YF_TxDescQIdx, (txHead + 1) % txRingSize);

    } else {
	/* Hamachi */
	hamachi_desc_t *desc = (hamachi_desc_t *)txRing + txHead;

	desc->addr = (unsigned int)kvtophys((vm_offset_t)txBuffers[txHead]);
	desc->reserved1 = 0;
	desc->reserved2 = 0;
	/* Set length, end-of-packet, interrupt, and own bits */
	desc->status_n_length = length | DESC_END_PACKET | DESC_INTR | DESC_OWN;

	/* Notify hardware */
	WRITE_REG(HAM_TxCmd, 0x00000001); /* Start TX */
    }

    /* Move to next descriptor */
    txHead = (txHead + 1) % txRingSize;
}

/*
 * transmit - Transmit a packet
 */
- (void)transmit:(netbuf_t)pkt
{
    if (!isOpen) {
	nb_free(pkt);
	return;
    }

    /* Check if ring is full */
    if (((txHead + 1) % txRingSize) == txTail) {
	/* Ring full, queue the packet */
	if ([transmitQueue count] >= TX_RING_SIZE) {
	    /* Queue is also full, drop the packet */
	    IOLog("PPCGNic: TX ring and queue full, dropping packet\n");
	    nb_free(pkt);
	    txErrors++;
	    return;
	}
	[transmitQueue enqueue:pkt];
	return;
    }

    /* Send immediately if ring has space */
    [self _doTransmit:pkt];
    transmitActive = YES;
}

/*
 * timeoutOccurred - Handle timeout
 */
- (void)timeoutOccurred
{
    DLOG("Timeout occurred\n");
    [self _updateLinkStatus];
}

/*
 * enablePromiscuousMode - Enable promiscuous mode
 */
- (BOOL)enablePromiscuousMode
{
    DLOG("Enabling promiscuous mode\n");
    promiscuousMode = YES;

    if (chipType == CHIP_TYPE_YELLOWFIN) {
	unsigned int rxconfig = READ_REG(YF_RxConfig);
	rxconfig |= RX_ACCEPT_ALL_PHYS;
	WRITE_REG(YF_RxConfig, rxconfig);
    } else {
	unsigned int rxcmd = READ_REG(HAM_RxCmd);
	rxcmd |= RX_ACCEPT_ALL_PHYS;
	WRITE_REG(HAM_RxCmd, rxcmd);
    }

    return YES;
}

/*
 * disablePromiscuousMode - Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    DLOG("Disabling promiscuous mode\n");
    promiscuousMode = NO;

    if (chipType == CHIP_TYPE_YELLOWFIN) {
	unsigned int rxconfig = READ_REG(YF_RxConfig);
	rxconfig &= ~RX_ACCEPT_ALL_PHYS;
	WRITE_REG(YF_RxConfig, rxconfig);
    } else {
	unsigned int rxcmd = READ_REG(HAM_RxCmd);
	rxcmd &= ~RX_ACCEPT_ALL_PHYS;
	WRITE_REG(HAM_RxCmd, rxcmd);
    }
}

/*
 * enableMulticastMode - Enable multicast mode
 */
- (BOOL)enableMulticastMode
{
    DLOG("Enabling multicast mode\n");
    multicastMode = YES;

    if (chipType == CHIP_TYPE_YELLOWFIN) {
	unsigned int rxconfig = READ_REG(YF_RxConfig);
	rxconfig |= RX_ACCEPT_MULTICAST;
	WRITE_REG(YF_RxConfig, rxconfig);
    } else {
	unsigned int rxcmd = READ_REG(HAM_RxCmd);
	rxcmd |= RX_ACCEPT_MULTICAST;
	WRITE_REG(HAM_RxCmd, rxcmd);
    }

    return YES;
}

/*
 * disableMulticastMode - Disable multicast mode
 */
- (void)disableMulticastMode
{
    DLOG("Disabling multicast mode\n");
    multicastMode = NO;

    if (chipType == CHIP_TYPE_YELLOWFIN) {
	unsigned int rxconfig = READ_REG(YF_RxConfig);
	rxconfig &= ~RX_ACCEPT_MULTICAST;
	WRITE_REG(YF_RxConfig, rxconfig);
    } else {
	unsigned int rxcmd = READ_REG(HAM_RxCmd);
	rxcmd &= ~RX_ACCEPT_MULTICAST;
	WRITE_REG(HAM_RxCmd, rxcmd);
    }
}

@end
