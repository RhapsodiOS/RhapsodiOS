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
 * Copyright (c) 2025 by RhapsodiOS Project, All rights reserved.
 *
 * Hardware-specific functions for the Sun GEM Gigabit Ethernet Controller
 *
 * HISTORY
 *
 */

#import "GemEnetPrivate.h"

@implementation GemEnet(Private)

/*
 * Register Access
 */

- (u_int32_t)readRegister:(unsigned int)offset
{
    volatile u_int32_t *reg = (volatile u_int32_t *)((char *)ioBaseGem + offset);
    eieio();
    return *reg;
}

- (void)writeRegister:(unsigned int)offset value:(u_int32_t)value
{
    volatile u_int32_t *reg = (volatile u_int32_t *)((char *)ioBaseGem + offset);
    *reg = value;
    eieio();
}

/*
 * Chip Initialization
 */

- (BOOL)initChip
{
    u_int32_t val;
    int i;

    GEM_TRACE("Initializing GEM chip\n");

    /* Global software reset */
    [self writeRegister:GREG_SWRST value:(GREG_SWRST_TXRST | GREG_SWRST_RXRST | GREG_SWRST_RSTOUT)];
    IODelay(20);

    /* Wait for reset to complete */
    for (i = 0; i < 100; i++)
    {
        val = [self readRegister:GREG_SWRST];
        if ((val & (GREG_SWRST_TXRST | GREG_SWRST_RXRST)) == 0)
            break;
        IODelay(10);
    }

    if (i >= 100)
    {
        GEM_ERROR("Chip reset timeout\n");
        return NO;
    }

    /* Configure cache line size */
    val = (32 << GREG_SWRST_CACHE_SHIFT);
    [self writeRegister:GREG_SWRST value:val];

    /* Configure DMA */
    val = GREG_CFG_IBURST;
    val |= (0x1F << 1);  /* TX DMA limit */
    val |= (0x1F << 6);  /* RX DMA limit */
    [self writeRegister:GREG_CFG value:val];

    /* Disable all interrupts initially */
    [self writeRegister:GREG_IMASK value:0xFFFFFFFF];

    /* Configure MAC */
    [self writeRegister:MAC_STIME value:0x40];       /* Slot time */
    [self writeRegister:MAC_PASIZE value:0x07];      /* Preamble */
    [self writeRegister:MAC_JAMSIZE value:0x04];     /* JAM size */
    [self writeRegister:MAC_ATTLIM value:0x10];      /* Attempt limit */
    [self writeRegister:MAC_MCTYPE value:0x8808];    /* MAC control type */

    /* Configure XIF */
    val = MAC_XIFCFG_TXOE | MAC_XIFCFG_GMII;
    if (isFullDuplex)
        val |= MAC_XIFCFG_FLED;
    [self writeRegister:MAC_XIFCFG value:val];

    /* Setup MAC address */
    [self writeRegister:MAC_ADDR0 value:((myAddress.ea_byte[4] << 8) | myAddress.ea_byte[5])];
    [self writeRegister:MAC_ADDR1 value:((myAddress.ea_byte[2] << 8) | myAddress.ea_byte[3])];
    [self writeRegister:MAC_ADDR2 value:((myAddress.ea_byte[0] << 8) | myAddress.ea_byte[1])];

    /* Enable address filtering */
    val = [self readRegister:MAC_RXCFG];
    val |= MAC_RXCFG_AENABLE;
    [self writeRegister:MAC_RXCFG value:val];

    /* Clear hash table */
    for (i = 0; i < 16; i++)
    {
        [self writeRegister:(MAC_HASH0 + (i * 4)) value:0];
        hashTableMask[i] = 0;
    }

    for (i = 0; i < 256; i++)
        hashTableUseCount[i] = 0;

    GEM_TRACE("Chip initialized\n");
    return YES;
}

- (BOOL)initRings
{
    int i;
    gem_dma_desc_t *txd, *rxd;

    GEM_TRACE("Initializing descriptor rings\n");

    /* Initialize TX ring */
    txDescHead = 0;
    txDescTail = 0;

    for (i = 0; i < TX_RING_LENGTH; i++)
    {
        txd = &txDescriptors[i];
        txd->flags = 0;
        txd->buffer = 0;
        txNetbuf[i] = NULL;
    }

    /* Initialize RX ring */
    rxDescHead = 0;
    rxDescTail = 0;

    for (i = 0; i < RX_RING_LENGTH; i++)
    {
        rxd = &rxDescriptors[i];
        rxd->flags = GEM_RXDESC_OWN | RX_BUF_SIZE;
        rxd->buffer = rxBuffersPhys + (i * RX_BUF_SIZE);
        rxNetbuf[i] = NULL;
    }

    /* Program descriptor base addresses */
    [self writeRegister:TXDMA_DBLOW value:txDescriptorsPhys];
    [self writeRegister:TXDMA_DBHI value:0];
    [self writeRegister:RXDMA_DBLOW value:rxDescriptorsPhys];
    [self writeRegister:RXDMA_DBHI value:0];

    /* Configure TX DMA */
    [self writeRegister:TXDMA_CFG value:(TXDMA_CFG_RINGSZ_256 | (0x7FF << 10))]; /* FTHRESH */

    /* Configure RX DMA */
    [self writeRegister:RXDMA_CFG value:(RXDMA_CFG_RINGSZ_256 | (2 << 10) | RXDMA_CFG_CKSUM)];

    /* Set RX blanking */
    [self writeRegister:RXDMA_BLANK value:((16 << 9) | 128)]; /* 16 packets or 128 time units */

    /* Initialize RX kick register */
    [self writeRegister:RXDMA_KICK value:(RX_RING_LENGTH - 4)];

    GEM_TRACE("Rings initialized\n");
    return YES;
}

- (void)freeRings
{
    int i;

    /* Free any allocated TX netbufs */
    for (i = 0; i < TX_RING_LENGTH; i++)
    {
        if (txNetbuf[i])
        {
            nb_free(txNetbuf[i]);
            txNetbuf[i] = NULL;
        }
    }

    /* Free any allocated RX netbufs */
    for (i = 0; i < RX_RING_LENGTH; i++)
    {
        if (rxNetbuf[i])
        {
            nb_free(rxNetbuf[i]);
            rxNetbuf[i] = NULL;
        }
    }
}

- (BOOL)allocateMemory
{
    unsigned int size;

    GEM_TRACE("Allocating memory\n");

    /* Allocate TX descriptors (aligned to 2KB) */
    size = TX_RING_LENGTH * sizeof(gem_dma_desc_t);
    txDescriptors = (gem_dma_desc_t *)IOMallocAligned(size, GEM_TX_DESC_ALIGN);
    if (!txDescriptors)
    {
        GEM_ERROR("Failed to allocate TX descriptors\n");
        return NO;
    }
    txDescriptorsPhys = (unsigned int)kvtophys((vm_offset_t)txDescriptors);

    /* Allocate RX descriptors (aligned to 2KB) */
    size = RX_RING_LENGTH * sizeof(gem_dma_desc_t);
    rxDescriptors = (gem_dma_desc_t *)IOMallocAligned(size, GEM_RX_DESC_ALIGN);
    if (!rxDescriptors)
    {
        GEM_ERROR("Failed to allocate RX descriptors\n");
        [self freeMemory];
        return NO;
    }
    rxDescriptorsPhys = (unsigned int)kvtophys((vm_offset_t)rxDescriptors);

    /* Allocate TX buffers */
    size = TX_RING_LENGTH * TX_BUF_SIZE;
    txBuffers = (unsigned char *)IOMallocAligned(size, GEM_TX_BUF_ALIGN);
    if (!txBuffers)
    {
        GEM_ERROR("Failed to allocate TX buffers\n");
        [self freeMemory];
        return NO;
    }
    txBuffersPhys = (unsigned int)kvtophys((vm_offset_t)txBuffers);

    /* Allocate RX buffers */
    size = RX_RING_LENGTH * RX_BUF_SIZE;
    rxBuffers = (unsigned char *)IOMallocAligned(size, GEM_RX_BUF_ALIGN);
    if (!rxBuffers)
    {
        GEM_ERROR("Failed to allocate RX buffers\n");
        [self freeMemory];
        return NO;
    }
    rxBuffersPhys = (unsigned int)kvtophys((vm_offset_t)rxBuffers);

    GEM_LOG("Memory allocated: TX desc=0x%08x RX desc=0x%08x TX buf=0x%08x RX buf=0x%08x\n",
            txDescriptorsPhys, rxDescriptorsPhys, txBuffersPhys, rxBuffersPhys);

    return YES;
}

- (void)freeMemory
{
    if (txDescriptors)
    {
        IOFree(txDescriptors, TX_RING_LENGTH * sizeof(gem_dma_desc_t));
        txDescriptors = NULL;
    }

    if (rxDescriptors)
    {
        IOFree(rxDescriptors, RX_RING_LENGTH * sizeof(gem_dma_desc_t));
        rxDescriptors = NULL;
    }

    if (txBuffers)
    {
        IOFree(txBuffers, TX_RING_LENGTH * TX_BUF_SIZE);
        txBuffers = NULL;
    }

    if (rxBuffers)
    {
        IOFree(rxBuffers, RX_RING_LENGTH * RX_BUF_SIZE);
        rxBuffers = NULL;
    }
}

/*
 * PHY Management
 */

- (BOOL)phyProbe
{
    u_int16_t phyId1, phyId2;
    int phy;

    GEM_TRACE("Probing for PHY\n");

    /* Try to find PHY */
    for (phy = 0; phy < 32; phy++)
    {
        phyId1 = [self mifReadPHY:phy reg:PHY_ID1];
        phyId2 = [self mifReadPHY:phy reg:PHY_ID2];

        if (phyId1 != 0xFFFF && phyId1 != 0x0000)
        {
            phyId = phy;
            GEM_LOG("Found PHY at address %d: ID1=0x%04x ID2=0x%04x\n", phy, phyId1, phyId2);

            /* Identify PHY type */
            if ((phyId1 == 0x0040) && ((phyId2 & 0xFFF0) == 0x6210))
                phyType = PHY_TYPE_BCM5400;
            else if ((phyId1 == 0x0040) && ((phyId2 & 0xFFF0) == 0x6250))
                phyType = PHY_TYPE_BCM5401;
            else if ((phyId1 == 0x0040) && ((phyId2 & 0xFFF0) == 0x6070))
                phyType = PHY_TYPE_BCM5411;
            else if ((phyId1 == 0x0040) && ((phyId2 & 0xFFF0) == 0x61E0))
                phyType = PHY_TYPE_BCM5421;
            else
                phyType = PHY_TYPE_MII;

            return YES;
        }
    }

    GEM_ERROR("No PHY found\n");
    return NO;
}

- (BOOL)phyInit
{
    GEM_TRACE("Initializing PHY\n");

    /* Probe for PHY */
    if (![self phyProbe])
        return NO;

    /* Reset PHY */
    if (![self phyReset])
        return NO;

    /* Setup auto-negotiation or forced mode */
    if (gigabitCapable)
    {
        if (![self phySetupAutoNeg])
            return NO;
    }
    else
    {
        if (![self phySetupForcedMode])
            return NO;
    }

    return YES;
}

- (BOOL)phyReset
{
    u_int16_t val;
    int i;

    GEM_TRACE("Resetting PHY\n");

    /* Issue PHY reset */
    [self phyWrite:PHY_CONTROL value:PHY_CTRL_RESET];

    /* Wait for reset to complete */
    for (i = 0; i < 100; i++)
    {
        IODelay(GEM_PHY_RESET_DELAY);
        val = [self phyRead:PHY_CONTROL];
        if (!(val & PHY_CTRL_RESET))
            break;
    }

    if (i >= 100)
    {
        GEM_ERROR("PHY reset timeout\n");
        return NO;
    }

    IODelay(GEM_PHY_STABLE_DELAY);
    return YES;
}

- (u_int16_t)phyRead:(u_int8_t)reg
{
    return [self mifReadPHY:phyId reg:reg];
}

- (void)phyWrite:(u_int8_t)reg value:(u_int16_t)val
{
    [self mifWritePHY:phyId reg:reg value:val];
}

- (void)phyCheckLink
{
    u_int16_t status, auxStatus;
    u_int8_t oldState = linkState;

    /* Read PHY status */
    status = [self phyRead:PHY_STATUS];

    if (status & PHY_STAT_LINK_UP)
    {
        /* Link is up, determine speed */
        if (phyType == PHY_TYPE_BCM5400 || phyType == PHY_TYPE_BCM5401 ||
            phyType == PHY_TYPE_BCM5411 || phyType == PHY_TYPE_BCM5421)
        {
            auxStatus = [self phyRead:BCM5400_AUX_STATUS];
            switch ((auxStatus & BCM5400_AUXSTAT_LINKMODE_MASK) >> BCM5400_AUXSTAT_LINKMODE_SHIFT)
            {
                case 1: linkState = LINK_STATE_UP_10MB; break;
                case 2: linkState = LINK_STATE_UP_100MB; break;
                case 3: linkState = LINK_STATE_UP_1000MB; break;
                default: linkState = LINK_STATE_UNKNOWN; break;
            }
        }
        else
        {
            /* Generic MII - assume 100Mbps */
            linkState = LINK_STATE_UP_100MB;
        }
    }
    else
    {
        linkState = LINK_STATE_DOWN;
    }

    /* Report link state changes */
    if (linkState != oldState)
    {
        GEM_LOG("Link state changed: %s\n", [self linkStateString]);
    }

    phyStatusPrev = status;
}

- (BOOL)phySetupForcedMode
{
    u_int16_t val;

    GEM_TRACE("Setting up forced 100Mbps mode\n");

    val = PHY_CTRL_SPEED_SEL | PHY_CTRL_DUPLEX;
    [self phyWrite:PHY_CONTROL value:val];

    isFullDuplex = YES;
    return YES;
}

- (BOOL)phySetupAutoNeg
{
    u_int16_t val;

    GEM_TRACE("Setting up auto-negotiation\n");

    /* Advertise all capabilities */
    val = PHY_AN_ADV_100BTXFD | PHY_AN_ADV_100BTXHD |
          PHY_AN_ADV_10BTFD | PHY_AN_ADV_10BTHD |
          PHY_AN_ADV_PAUSE | 0x0001;  /* 802.3 */
    [self phyWrite:PHY_AUTONEG_ADV value:val];

    /* Advertise gigabit if capable */
    if (gigabitCapable)
    {
        val = PHY_1000BT_CTL_ADV_FD | PHY_1000BT_CTL_ADV_HD;
        [self phyWrite:PHY_1000BT_CONTROL value:val];
    }

    /* Enable and restart auto-negotiation */
    val = PHY_CTRL_AUTONEG_EN | PHY_CTRL_RESTART_AN | PHY_CTRL_DUPLEX;
    [self phyWrite:PHY_CONTROL value:val];

    return YES;
}

/*
 * MIF (Management Interface)
 */

- (u_int16_t)mifReadPHY:(u_int8_t)phy reg:(u_int8_t)reg
{
    u_int32_t frame;
    int i;

    /* Build read frame */
    frame = MIF_FRAME_ST;
    frame |= MIF_FRAME_OP_READ;
    frame |= (phy << 23) & MIF_FRAME_PHYAD;
    frame |= (reg << 18) & MIF_FRAME_REGAD;
    frame |= MIF_FRAME_TAMSB;

    [self writeRegister:MIF_FRAME value:frame];

    /* Wait for completion */
    for (i = 0; i < 100; i++)
    {
        IODelay(10);
        frame = [self readRegister:MIF_FRAME];
        if ((frame & MIF_FRAME_TALSB) == 0)
            break;
    }

    return (u_int16_t)(frame & MIF_FRAME_DATA);
}

- (void)mifWritePHY:(u_int8_t)phy reg:(u_int8_t)reg value:(u_int16_t)val
{
    u_int32_t frame;
    int i;

    /* Build write frame */
    frame = MIF_FRAME_ST;
    frame |= MIF_FRAME_OP_WRITE;
    frame |= (phy << 23) & MIF_FRAME_PHYAD;
    frame |= (reg << 18) & MIF_FRAME_REGAD;
    frame |= MIF_FRAME_TAMSB;
    frame |= val & MIF_FRAME_DATA;

    [self writeRegister:MIF_FRAME value:frame];

    /* Wait for completion */
    for (i = 0; i < 100; i++)
    {
        IODelay(10);
        frame = [self readRegister:MIF_FRAME];
        if ((frame & MIF_FRAME_TALSB) == 0)
            break;
    }
}

- (void)mifPollStart
{
    u_int32_t cfg;

    /* Enable MII management polling */
    cfg = [self readRegister:MIF_CFG];
    cfg |= MIF_CFG_POLL;
    [self writeRegister:MIF_CFG value:cfg];
}

- (void)mifPollStop
{
    u_int32_t cfg;

    /* Disable MII management polling */
    cfg = [self readRegister:MIF_CFG];
    cfg &= ~MIF_CFG_POLL;
    [self writeRegister:MIF_CFG value:cfg];

    /* Wait for any pending operations to complete */
    IODelay(20);
}

/*
 * TX/RX Operations
 */

- (void)txReset
{
    [self writeRegister:MAC_TXRST value:1];
    IODelay(10);
}

- (void)rxReset
{
    [self writeRegister:MAC_RXRST value:1];
    IODelay(10);
}

- (void)txEnable
{
    u_int32_t val;

    val = [self readRegister:TXDMA_CFG];
    val |= TXDMA_CFG_ENABLE;
    [self writeRegister:TXDMA_CFG value:val];

    val = [self readRegister:MAC_TXCFG];
    val |= MAC_TXCFG_ENAB;
    [self writeRegister:MAC_TXCFG value:val];
}

- (void)rxEnable
{
    u_int32_t val;

    val = [self readRegister:RXDMA_CFG];
    val |= RXDMA_CFG_ENABLE;
    [self writeRegister:RXDMA_CFG value:val];

    val = [self readRegister:MAC_RXCFG];
    val |= MAC_RXCFG_ENAB;
    [self writeRegister:MAC_RXCFG value:val];
}

- (void)txDisable
{
    u_int32_t val;

    val = [self readRegister:MAC_TXCFG];
    val &= ~MAC_TXCFG_ENAB;
    [self writeRegister:MAC_TXCFG value:val];

    val = [self readRegister:TXDMA_CFG];
    val &= ~TXDMA_CFG_ENABLE;
    [self writeRegister:TXDMA_CFG value:val];
}

- (void)rxDisable
{
    u_int32_t val;

    val = [self readRegister:MAC_RXCFG];
    val &= ~MAC_RXCFG_ENAB;
    [self writeRegister:MAC_RXCFG value:val];

    val = [self readRegister:RXDMA_CFG];
    val &= ~RXDMA_CFG_ENABLE;
    [self writeRegister:RXDMA_CFG value:val];
}

- (BOOL)txQueuePacket:(netbuf_t)pkt
{
    gem_dma_desc_t *txd;
    unsigned int entry, len;
    unsigned char *buf;

    entry = txDescTail;
    txd = &txDescriptors[entry];

    /* Check if descriptor is available */
    if (txd->flags & GEM_TXDESC_OWN)
        return NO;

    /* Get packet data */
    len = nb_size(pkt);
    if (len > TX_BUF_SIZE)
        len = TX_BUF_SIZE;

    buf = txBuffers + (entry * TX_BUF_SIZE);
    bcopy(nb_map(pkt), buf, len);

    /* Setup descriptor */
    txd->buffer = txBuffersPhys + (entry * TX_BUF_SIZE);
    txd->flags = GEM_TXDESC_SOP | GEM_TXDESC_EOP | len;
    eieio();
    txd->flags |= GEM_TXDESC_OWN;

    /* Save netbuf */
    txNetbuf[entry] = pkt;

    /* Advance tail */
    txDescTail = (entry + 1) & TX_RING_WRAP;

    /* Kick TX DMA */
    [self writeRegister:TXDMA_KICK value:txDescTail];

    txPackets++;
    return YES;
}

- (void)txComplete
{
    gem_dma_desc_t *txd;
    unsigned int entry;

    while (txDescHead != txDescTail)
    {
        entry = txDescHead;
        txd = &txDescriptors[entry];

        /* Check if hardware still owns this descriptor */
        if (txd->flags & GEM_TXDESC_OWN)
            break;

        /* Free the netbuf */
        if (txNetbuf[entry])
        {
            nb_free(txNetbuf[entry]);
            txNetbuf[entry] = NULL;
        }

        /* Advance head */
        txDescHead = (entry + 1) & TX_RING_WRAP;
    }
}

- (void)rxProcess
{
    gem_dma_desc_t *rxd;
    unsigned int entry, len;
    netbuf_t pkt;
    unsigned char *buf;

    while (1)
    {
        entry = rxDescHead;
        rxd = &rxDescriptors[entry];

        /* Check if hardware still owns this descriptor */
        if (rxd->flags & GEM_RXDESC_OWN)
            break;

        /* Get packet length */
        len = rxd->flags & GEM_RXDESC_BUFSIZE;

        /* Check for errors */
        if (rxd->flags & GEM_RXDESC_BAD)
        {
            rxErrors++;
        }
        else if (len > 0)
        {
            /* Allocate netbuf */
            pkt = nb_alloc(len);
            if (pkt)
            {
                buf = rxBuffers + (entry * RX_BUF_SIZE);

                /* Copy packet data */
                bcopy(buf, nb_map(pkt), len);

                /* Hand packet to network stack */
                [networkInterface handleInputPacket:pkt extra:0];
                rxPackets++;
            }
        }

        /* Return descriptor to hardware */
        rxd->buffer = rxBuffersPhys + (entry * RX_BUF_SIZE);
        eieio();
        rxd->flags = GEM_RXDESC_OWN | RX_BUF_SIZE;
        eieio();

        /* Advance head */
        rxDescHead = (entry + 1) & RX_RING_WRAP;
    }

    /* Update hardware RX tail pointer */
    if (rxDescHead != entry)
        [self writeRegister:RXDMA_KICK value:rxDescHead];
}

- (BOOL)rxRefill
{
    gem_dma_desc_t *rxd;
    unsigned int entry, count = 0;

    /* Refill any empty RX descriptors */
    while (count < RX_RING_LENGTH)
    {
        entry = rxDescTail;
        rxd = &rxDescriptors[entry];

        /* Check if descriptor already owned by hardware */
        if (rxd->flags & GEM_RXDESC_OWN)
            break;

        /* Setup descriptor with buffer */
        rxd->buffer = rxBuffersPhys + (entry * RX_BUF_SIZE);
        eieio();
        rxd->flags = GEM_RXDESC_OWN | RX_BUF_SIZE;
        eieio();

        /* Advance tail */
        rxDescTail = (entry + 1) & RX_RING_WRAP;
        count++;
    }

    if (count > 0)
    {
        /* Kick RX DMA to process new descriptors */
        [self writeRegister:RXDMA_KICK value:rxDescTail];
        GEM_TRACE("Refilled %d RX descriptors\n", count);
    }

    return YES;
}

/*
 * Multicast/Promiscuous
 */

- (void)setMulticastFilter
{
    u_int32_t rxcfg;
    int i;

    rxcfg = [self readRegister:MAC_RXCFG];

    if (multicastEnabled || isPromiscuous)
    {
        /* Enable hash filtering for multicast */
        rxcfg |= MAC_RXCFG_HENABLE;

        /* In promiscuous mode, set all hash bits */
        if (isPromiscuous)
        {
            for (i = 0; i < 16; i++)
            {
                hashTableMask[i] = 0xFFFF;
                [self writeRegister:(MAC_HASH0 + (i * 4)) value:0xFFFF];
            }
        }
        else
        {
            /* Write current hash table to hardware */
            for (i = 0; i < 16; i++)
                [self writeRegister:(MAC_HASH0 + (i * 4)) value:hashTableMask[i]];
        }
    }
    else
    {
        /* Disable hash filtering */
        rxcfg &= ~MAC_RXCFG_HENABLE;

        /* Clear hash table */
        for (i = 0; i < 16; i++)
        {
            hashTableMask[i] = 0;
            [self writeRegister:(MAC_HASH0 + (i * 4)) value:0];
        }
    }

    [self writeRegister:MAC_RXCFG value:rxcfg];
}

- (u_int16_t)hashCRC:(enet_addr_t *)addr
{
    static const u_int32_t crc_table[256] = {
        0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA,
        0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
        0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988,
        0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
        0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE,
        0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
        0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC,
        0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
        0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172,
        0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
        0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940,
        0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
        0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116,
        0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
        0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924,
        0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
        0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A,
        0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
        0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818,
        0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
        0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E,
        0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
        0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C,
        0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
        0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2,
        0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
        0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0,
        0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
        0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086,
        0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
        0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4,
        0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
        0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A,
        0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
        0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8,
        0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
        0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE,
        0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
        0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC,
        0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
        0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252,
        0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
        0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60,
        0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
        0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
        0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
        0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04,
        0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
        0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A,
        0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
        0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38,
        0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
        0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E,
        0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
        0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C,
        0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
        0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2,
        0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
        0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0,
        0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
        0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6,
        0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
        0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94,
        0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
    };

    u_int32_t crc = 0xFFFFFFFF;
    int i;

    /* Calculate CRC32 over the 6 bytes of MAC address */
    for (i = 0; i < 6; i++)
        crc = (crc >> 8) ^ crc_table[(crc ^ addr->ea_byte[i]) & 0xFF];

    /* Use top 8 bits of CRC as hash index */
    return (u_int16_t)((crc >> 24) & 0xFF);
}

/*
 * Interrupt Handling
 */

- (void)handleAbnormalInterrupt:(u_int32_t)status
{
    GEM_LOG("Abnormal interrupt: 0x%08x\n", status);

    if (status & GREG_STAT_PCIERR)
        GEM_ERROR("PCI error\n");

    if (status & GREG_STAT_TXMAC)
        GEM_ERROR("TX MAC error\n");

    if (status & GREG_STAT_RXMAC)
        GEM_ERROR("RX MAC error\n");

    if (status & GREG_STAT_RXNOBUF)
        [self rxRefill];
}

/*
 * Timer
 */

- (void)startWatchdogTimer
{
    [self scheduleTimeout];
}

- (void)stopWatchdogTimer
{
    [self clearTimeout];
}

/*
 * Utility Functions
 */

- (void)getStationAddress:(enet_addr_t *)addr
{
    u_int32_t mac0, mac1, mac2;

    /* Read MAC address from hardware registers */
    /* The MAC address is stored in three 16-bit registers */
    mac0 = [self readRegister:MAC_ADDR0];
    mac1 = [self readRegister:MAC_ADDR1];
    mac2 = [self readRegister:MAC_ADDR2];

    /* Extract bytes from registers (network byte order) */
    addr->ea_byte[5] = (mac0 >> 0) & 0xFF;
    addr->ea_byte[4] = (mac0 >> 8) & 0xFF;
    addr->ea_byte[3] = (mac1 >> 0) & 0xFF;
    addr->ea_byte[2] = (mac1 >> 8) & 0xFF;
    addr->ea_byte[1] = (mac2 >> 0) & 0xFF;
    addr->ea_byte[0] = (mac2 >> 8) & 0xFF;

    /* Check if MAC address is valid (not all zeros or all FFs) */
    if ((addr->ea_byte[0] == 0x00 && addr->ea_byte[1] == 0x00 &&
         addr->ea_byte[2] == 0x00 && addr->ea_byte[3] == 0x00 &&
         addr->ea_byte[4] == 0x00 && addr->ea_byte[5] == 0x00) ||
        (addr->ea_byte[0] == 0xFF && addr->ea_byte[1] == 0xFF &&
         addr->ea_byte[2] == 0xFF && addr->ea_byte[3] == 0xFF &&
         addr->ea_byte[4] == 0xFF && addr->ea_byte[5] == 0xFF))
    {
        /* Invalid MAC address, try reading from OpenFirmware */
        GEM_LOG("Invalid MAC in registers, trying OpenFirmware\n");

        /* Use a default Apple-like MAC address as fallback */
        addr->ea_byte[0] = 0x00;
        addr->ea_byte[1] = 0x0D;
        addr->ea_byte[2] = 0x93;
        addr->ea_byte[3] = 0x00;
        addr->ea_byte[4] = 0x00;
        addr->ea_byte[5] = 0x01;
    }
}

- (void)dumpRegisters
{
    GEM_LOG("=== GEM Register Dump ===\n");
    GEM_LOG("GREG_CFG     = 0x%08x\n", [self readRegister:GREG_CFG]);
    GEM_LOG("GREG_STAT    = 0x%08x\n", [self readRegister:GREG_STAT]);
    GEM_LOG("GREG_IMASK   = 0x%08x\n", [self readRegister:GREG_IMASK]);
    GEM_LOG("TXDMA_CFG    = 0x%08x\n", [self readRegister:TXDMA_CFG]);
    GEM_LOG("RXDMA_CFG    = 0x%08x\n", [self readRegister:RXDMA_CFG]);
    GEM_LOG("MAC_TXCFG    = 0x%08x\n", [self readRegister:MAC_TXCFG]);
    GEM_LOG("MAC_RXCFG    = 0x%08x\n", [self readRegister:MAC_RXCFG]);
    GEM_LOG("MAC_XIFCFG   = 0x%08x\n", [self readRegister:MAC_XIFCFG]);
}

- (void)dumpDescriptors
{
    int i;
    gem_dma_desc_t *txd, *rxd;

    GEM_LOG("=== TX Descriptors (head=%d tail=%d) ===\n", txDescHead, txDescTail);
    for (i = 0; i < 4; i++)
    {
        txd = &txDescriptors[i];
        GEM_LOG("[%d] flags=0x%016llx buffer=0x%08x\n", i, txd->flags, txd->buffer);
    }

    GEM_LOG("=== RX Descriptors (head=%d tail=%d) ===\n", rxDescHead, rxDescTail);
    for (i = 0; i < 4; i++)
    {
        rxd = &rxDescriptors[i];
        GEM_LOG("[%d] flags=0x%016llx buffer=0x%08x\n", i, rxd->flags, rxd->buffer);
    }
}

- (const char *)linkStateString
{
    switch (linkState)
    {
        case LINK_STATE_DOWN:       return "Down";
        case LINK_STATE_UP_10MB:    return "Up 10Mbps";
        case LINK_STATE_UP_100MB:   return "Up 100Mbps";
        case LINK_STATE_UP_1000MB:  return "Up 1000Mbps (Gigabit)";
        default:                    return "Unknown";
    }
}

@end
