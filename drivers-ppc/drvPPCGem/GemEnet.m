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
 * Implementation for the Sun GEM Gigabit Ethernet Controller
 *
 * HISTORY
 *
 */

#import "GemEnetPrivate.h"

@implementation GemEnet

/*
 * Public Factory Methods
 */

+ (BOOL)probe:(IOPCIDevice *)devDesc
{
    GemEnet *gemInstance;

    gemInstance = [self alloc];
    return [gemInstance initFromDeviceDescription:devDesc] != nil;
}

/*
 * Public Instance Methods
 */

- initFromDeviceDescription:(IOPCIDevice *)devDesc
{
    IORange *ioRange;
    unsigned int vendorID, deviceID;

    if ([super initFromDeviceDescription:devDesc] == nil)
    {
        GEM_ERROR("initFromDeviceDescription: super init failed\n");
        return nil;
    }

    /* Get PCI vendor and device IDs */
    vendorID = [devDesc configReadLong:kIOPCIConfigVendorID] & 0xFFFF;
    deviceID = ([devDesc configReadLong:kIOPCIConfigVendorID] >> 16) & 0xFFFF;

    GEM_LOG("Found device: vendor=0x%04x device=0x%04x\n", vendorID, deviceID);

    /* Verify this is a supported device */
    gigabitCapable = YES;
    if (vendorID == GEM_VENDOR_APPLE)
    {
        switch (deviceID)
        {
            case GEM_DEVICE_APPLE_GMAC:
            case GEM_DEVICE_APPLE_GMAC2:
            case GEM_DEVICE_APPLE_GMAC3:
            case GEM_DEVICE_APPLE_K2:
            case GEM_DEVICE_APPLE_SHASTA:
            case GEM_DEVICE_APPLE_INTREPID2:
                GEM_LOG("Apple GMAC variant detected\n");
                break;
            default:
                GEM_ERROR("Unknown Apple device ID: 0x%04x\n", deviceID);
                return nil;
        }
    }
    else if (vendorID == GEM_VENDOR_SUN)
    {
        if (deviceID == GEM_DEVICE_SUN_GEM)
        {
            GEM_LOG("Sun GEM detected\n");
        }
        else if (deviceID == GEM_DEVICE_SUN_ERI)
        {
            GEM_LOG("Sun ERI detected (10/100 only)\n");
            gigabitCapable = NO;
        }
        else
        {
            GEM_ERROR("Unknown Sun device ID: 0x%04x\n", deviceID);
            return nil;
        }
    }
    else
    {
        GEM_ERROR("Unknown vendor ID: 0x%04x\n", vendorID);
        return nil;
    }

    /* Map the GEM register space */
    if ([devDesc numMemoryRanges] < 1)
    {
        GEM_ERROR("No memory ranges available\n");
        return nil;
    }

    ioRange = [devDesc memoryRangeList];
    ioBaseGem = (IOPPCAddress)ioRange[0].start;

    if (!ioBaseGem)
    {
        GEM_ERROR("Failed to map GEM registers\n");
        return nil;
    }

    GEM_LOG("GEM registers mapped at 0x%08x\n", (unsigned int)ioBaseGem);

    /* Initialize chip ID and revision */
    chipId = deviceID;
    chipRevision = [devDesc configReadLong:kIOPCIConfigRevisionID] & 0xFF;

    /* Initialize PHY variables */
    phyType = PHY_TYPE_UNKNOWN;
    phyId = 0;
    phyStatusPrev = 0;
    linkState = LINK_STATE_UNKNOWN;

    /* Initialize ring indices */
    txDescHead = 0;
    txDescTail = 0;
    rxDescHead = 0;
    rxDescTail = 0;

    /* Initialize statistics */
    txInterrupts = 0;
    rxInterrupts = 0;
    errorInterrupts = 0;
    txPackets = 0;
    rxPackets = 0;
    txErrors = 0;
    rxErrors = 0;

    /* Allocate memory for descriptors and buffers */
    if (![self allocateMemory])
    {
        GEM_ERROR("Failed to allocate memory\n");
        [self free];
        return nil;
    }

    /* Reset and initialize the chip */
    if (![self resetAndEnable:NO])
    {
        GEM_ERROR("Failed to reset chip\n");
        [self free];
        return nil;
    }

    /* Read MAC address from hardware */
    [self getStationAddress:&myAddress];
    GEM_LOG("MAC Address: %02x:%02x:%02x:%02x:%02x:%02x\n",
            myAddress.ea_byte[0], myAddress.ea_byte[1], myAddress.ea_byte[2],
            myAddress.ea_byte[3], myAddress.ea_byte[4], myAddress.ea_byte[5]);

    /* Initialize and enable the chip */
    if (![self resetAndEnable:YES])
    {
        GEM_ERROR("Failed to enable chip\n");
        [self free];
        return nil;
    }

    isPromiscuous = NO;
    multicastEnabled = NO;

    /* Attach to network stack */
    networkInterface = [super attachToNetworkWithAddress:myAddress];
    if (!networkInterface)
    {
        GEM_ERROR("Failed to attach to network\n");
        [self free];
        return nil;
    }

    /* Mark interface as reentrant */
    [networkInterface getIONetworkIfnet]->if_eflags |= IFEF_DVR_REENTRY_OK;

    GEM_LOG("GemEnet driver initialized successfully\n");
    return self;
}

- free
{
    int i;

    [self clearTimeout];

    [self resetAndEnable:NO];

    if (networkInterface)
        [networkInterface free];

    for (i = 0; i < RX_RING_LENGTH; i++)
        if (rxNetbuf[i])
            nb_free(rxNetbuf[i]);

    for (i = 0; i < TX_RING_LENGTH; i++)
        if (txNetbuf[i])
            nb_free(txNetbuf[i]);

    [self freeMemory];

    return [super free];
}

- (void)transmit:(netbuf_t)pkt
{
    [self reserveDebuggerLock];

    /* Queue the packet for transmission */
    if (![self txQueuePacket:pkt])
    {
        /* Ring is full, drop the packet */
        nb_free(pkt);
        txErrors++;
    }

    [self releaseDebuggerLock];
}

- (void)serviceTransmitQueue
{
    /* Process completed transmissions */
    [self txComplete];

    /* Start watchdog timer */
    [self startWatchdogTimer];
}

- (BOOL)resetAndEnable:(BOOL)enable
{
    if (enable)
    {
        GEM_TRACE("Enabling GEM\n");

        /* Initialize chip */
        if (![self initChip])
        {
            GEM_ERROR("Chip initialization failed\n");
            return NO;
        }

        /* Initialize descriptor rings */
        if (![self initRings])
        {
            GEM_ERROR("Ring initialization failed\n");
            return NO;
        }

        /* Initialize PHY */
        if (![self phyInit])
        {
            GEM_ERROR("PHY initialization failed\n");
            return NO;
        }

        /* Enable TX and RX */
        [self txEnable];
        [self rxEnable];

        /* Enable interrupts */
        [self enableAllInterrupts];

        /* Start link monitoring */
        [self scheduleTimeout];

        resetAndEnabled = YES;
    }
    else
    {
        GEM_TRACE("Disabling GEM\n");

        [self clearTimeout];
        [self disableAllInterrupts];

        /* Disable TX and RX */
        [self txDisable];
        [self rxDisable];

        /* Reset the chip */
        [self txReset];
        [self rxReset];
        [self writeRegister:GREG_SWRST value:(GREG_SWRST_TXRST | GREG_SWRST_RXRST)];
        IODelay(20);

        resetAndEnabled = NO;
    }

    return YES;
}

- (void)interruptOccurredAt:(int)irqNum
{
    u_int32_t status;

    [self reserveDebuggerLock];

    /* Read interrupt status */
    status = [self readRegister:GREG_STAT];

    /* Acknowledge interrupts */
    [self writeRegister:GREG_IACK value:status];

    GEM_TRACE("IRQ: status=0x%08x\n", status);

    /* Handle abnormal interrupts */
    if (status & GREG_STAT_ABNORMAL)
    {
        errorInterrupts++;
        [self handleAbnormalInterrupt:status];
    }

    /* Handle RX interrupts */
    if (status & GREG_STAT_RXDONE)
    {
        rxInterrupts++;
        [self rxProcess];
    }

    /* Handle TX interrupts */
    if (status & (GREG_STAT_TXDONE | GREG_STAT_TXALL))
    {
        txInterrupts++;
        [self txComplete];
        [self serviceTransmitQueue];
    }

    /* Re-enable interrupts */
    [self enableAllInterrupts];

    [self releaseDebuggerLock];
}

- (void)timeoutOccurred
{
    /* Check PHY link status */
    [self phyCheckLink];

    /* Reschedule timer */
    [self scheduleTimeout];
}

- (BOOL)enableMulticastMode
{
    multicastEnabled = YES;
    [self setMulticastFilter];
    return YES;
}

- (void)disableMulticastMode
{
    multicastEnabled = NO;
    [self setMulticastFilter];
}

- (BOOL)enablePromiscuousMode
{
    u_int32_t rxcfg;

    isPromiscuous = YES;

    rxcfg = [self readRegister:MAC_RXCFG];
    rxcfg |= MAC_RXCFG_PROM;
    [self writeRegister:MAC_RXCFG value:rxcfg];

    return YES;
}

- (void)disablePromiscuousMode
{
    u_int32_t rxcfg;

    isPromiscuous = NO;

    rxcfg = [self readRegister:MAC_RXCFG];
    rxcfg &= ~MAC_RXCFG_PROM;
    [self writeRegister:MAC_RXCFG value:rxcfg];
}

/*
 * Kernel Debugger Support
 */

- (void)sendPacket:(void *)pkt length:(unsigned int)pkt_len
{
    gem_dma_desc_t *txd;
    unsigned int entry;
    unsigned char *buf;
    u_int32_t timeout;

    /* Polled send for kernel debugger */
    if (!resetAndEnabled || pkt_len == 0 || pkt_len > TX_BUF_SIZE)
        return;

    /* Use the first TX descriptor for debugger packets */
    entry = 0;
    txd = &txDescriptors[entry];

    /* Wait for descriptor to be free (with timeout) */
    timeout = 1000000;
    while ((txd->flags & GEM_TXDESC_OWN) && timeout--)
        IODelay(1);

    if (txd->flags & GEM_TXDESC_OWN)
    {
        GEM_ERROR("Debugger TX timeout\n");
        return;
    }

    /* Copy packet to TX buffer */
    buf = txBuffers + (entry * TX_BUF_SIZE);
    bcopy(pkt, buf, pkt_len);

    /* Setup descriptor */
    txd->buffer = txBuffersPhys + (entry * TX_BUF_SIZE);
    eieio();
    txd->flags = GEM_TXDESC_OWN | GEM_TXDESC_SOP | GEM_TXDESC_EOP |
                 (pkt_len & GEM_TXDESC_BUFSIZE);
    eieio();

    /* Kick TX DMA */
    [self writeRegister:TXDMA_KICK value:1];

    /* Wait for transmission to complete */
    timeout = 1000000;
    while ((txd->flags & GEM_TXDESC_OWN) && timeout--)
        IODelay(1);

    GEM_TRACE("Debugger sent: %d bytes\n", pkt_len);
}

- (void)receivePacket:(void *)pkt length:(unsigned int *)pkt_len timeout:(unsigned int)timeout
{
    gem_dma_desc_t *rxd;
    unsigned int entry, len;
    unsigned char *buf;
    u_int32_t delay_count;

    /* Polled receive for kernel debugger */
    *pkt_len = 0;

    if (!resetAndEnabled)
        return;

    /* Check the current RX descriptor */
    entry = rxDescHead;
    rxd = &rxDescriptors[entry];

    /* Wait for a packet (with timeout) */
    delay_count = timeout * 1000;
    while ((rxd->flags & GEM_RXDESC_OWN) && delay_count--)
        IODelay(1);

    /* No packet received */
    if (rxd->flags & GEM_RXDESC_OWN)
        return;

    /* Check for errors */
    if (rxd->flags & GEM_RXDESC_BAD)
    {
        /* Reset descriptor and return */
        rxd->flags = GEM_RXDESC_OWN | RX_BUF_SIZE;
        eieio();
        return;
    }

    /* Get packet length */
    len = rxd->flags & GEM_RXDESC_BUFSIZE;

    if (len > 0 && len <= RX_BUF_SIZE)
    {
        /* Copy packet data */
        buf = rxBuffers + (entry * RX_BUF_SIZE);
        bcopy(buf, pkt, len);
        *pkt_len = len;
    }

    /* Return descriptor to hardware */
    rxd->buffer = rxBuffersPhys + (entry * RX_BUF_SIZE);
    eieio();
    rxd->flags = GEM_RXDESC_OWN | RX_BUF_SIZE;
    eieio();

    /* Advance head */
    rxDescHead = (entry + 1) & RX_RING_WRAP;

    /* Kick RX DMA */
    [self writeRegister:RXDMA_KICK value:rxDescHead];

    GEM_TRACE("Debugger received: %d bytes\n", *pkt_len);
}

/*
 * Power Management
 */

- (IOReturn)getPowerState:(PMPowerState *)state_p
{
    *state_p = resetAndEnabled ? PM_ON : PM_OFF;
    return IO_R_SUCCESS;
}

- (IOReturn)setPowerState:(PMPowerState)state
{
    if (state == PM_ON)
    {
        return [self resetAndEnable:YES] ? IO_R_SUCCESS : IO_R_ERROR;
    }
    else
    {
        return [self resetAndEnable:NO] ? IO_R_SUCCESS : IO_R_ERROR;
    }
}

- (IOReturn)getPowerManagement:(PMPowerManagementState *)state_p
{
    *state_p = PM_AUTO;
    return IO_R_SUCCESS;
}

- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
    return IO_R_SUCCESS;
}

@end
