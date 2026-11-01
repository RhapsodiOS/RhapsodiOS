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
 * DEC21x4KDB.m
 *
 * Polled transmit and receive for the kernel debugger, and the SROM
 * patch table for boards with broken SROMs.
 *
 * HISTORY
 *
 * Reconstructed for RhapsodiOS from the DEC21x4 code linked into the
 * Mac OS X Server 1.2v3 (kernel 5.6) ppc mach_kernel.
 */

#import "DEC21x4.h"

@implementation DEC21x4(DEC21x4KDB)

- (void)receivePacket:(void *)pkt length:(unsigned int *)pkt_len
	      timeout:(unsigned int)timeout
{
    dcDescriptor_t	*desc;
    int			timeLeft;

    *pkt_len = 0;
    timeLeft = timeout * 1000;

    if (!ready) {
	IOLog("receivePacket: driver not ready\n");
	return;
    }

    for (;;) {
	desc = &rxRing[rxDoneIndex];
	if (desc->status.rx.own) {
	    if (timeLeft <= 0)
		return;
	    IODelay(50);
	    timeLeft -= 50;
	    continue;
	}

	/* Take the first good, complete frame; recycle anything else. */
	if (!(desc->status.data & Adapter->RxErrorMask) &&
	    desc->status.rx.fs && desc->status.rx.ls &&
	    (desc->status.rx.fl_lo | (desc->status.rx.fl_hi << 8)) >=
		MIN_FRAME_SIZE)
	    break;

	desc->status.rx.own = 1;
	eieio();
	if (++rxDoneIndex == rxRingSize)
	    rxDoneIndex = 0;
    }

    desc = &rxRing[rxDoneIndex];
    *pkt_len = (desc->status.rx.fl_lo | (desc->status.rx.fl_hi << 8)) - 4;
    fast_bcopy(mtod(rxMbuf[rxDoneIndex], char *), pkt, *pkt_len);

    desc->status.data = 0;
    eieio();
    desc->status.rx.own = 1;
    eieio();
    if (++rxDoneIndex == rxRingSize)
	rxDoneIndex = 0;
}

/*
 * Reap completed transmit descriptors.  Freed mbufs go on kdbQueue,
 * since they cannot be freed from inside the debugger.
 */
static void
kdb_intr_tx(DEC21x4 *self)
{
    dcDriverStats_t	*stats = &self->drvstat;
    dcDescriptor_t	*desc;
    struct mbuf		**mp;
    dcDescStatus_t	status;

    while (self->txNumFree < self->txRingSize) {
	desc = &self->txRing[self->txDoneIndex];
	mp = &self->txMbuf[self->txDoneIndex];
	status = desc->status;

	if (status.tx.own)
	    return;

	if (desc->control.bits.set) {
	    /* setup frame, no mbuf */
	    if (++self->txDoneIndex == self->txRingSize)
		self->txDoneIndex = 0;
	}
	else {
	    if (desc->control.bits.ls) {
		if (status.data & self->Adapter->TxErrorMask) {
		    dc_increment_out_errors(self, 1);
		    tx_err_record(&desc->status, stats);
		}
		else {
		    dc_increment_out_packets(self, 1);
		    stats->tx_f++;
		}
		if (status.tx.de)
		    stats->tx_de++;
		if (status.tx.ec)
		    dc_increment_collisions(self, 16);
		else if (status.tx.cc)
		    dc_increment_collisions(self, status.tx.cc);
		if (status.tx.lc && !status.tx.uf)
		    dc_increment_collisions(self, 1);
	    }
	    if (*mp) {
		IF_ENQUEUE(&self->kdbQueue, *mp);
		*mp = NULL;
	    }
	    if (++self->txDoneIndex == self->txRingSize)
		self->txDoneIndex = 0;
	}
	self->txNumFree++;
    }
}

- (void)sendPacket:(void *)pkt length:(unsigned int)pkt_len
{
    dcDescriptor_t	*desc;
    unsigned int	offset = 0;
    int			i;

    if (!ready && !Adapter->TestPacketMode) {
	IOLog("sendPacket: driver not ready\n");
	return;
    }
    if (pkt == NULL || pkt_len == 0) {
	IOLog("sendPacket: null packet\n");
	return;
    }

    kdb_intr_tx(self);
    if (txNumFree == 0) {
	IOLog("sendPacket: no free descriptors\n");
	return;
    }

    desc = &txRing[txPutIndex];
    if (txMbuf[txPutIndex]) {
	IOLog("sendPacket: recycled mbuf not NULL\n");
	IF_ENQUEUE(&kdbQueue, txMbuf[txPutIndex]);
	txMbuf[txPutIndex] = NULL;
    }

    KDB_txBuf->m_next = NULL;
    KDB_txBuf->m_data = (caddr_t)pkt;
    KDB_txBuf->m_len = pkt_len;
    KDB_txBuf->m_pkthdr.len = pkt_len;

    desc->control.data = 0;
    desc->status.data = 0;
    eieio();
    if (txPutIndex == txRingSize - 1)
	desc->control.bits.ter = 1;
    eieio();

    if (!IOUpdateTxDescriptorFromMbuf(self, &KDB_txBuf, &offset, desc)) {
	IOLog("sendPacket: IOUpdateTxDescriptorFromMbuf() error\n");
	return;
    }

    desc->control.bits.fs = 1;
    desc->control.bits.ls = 1;
    desc->control.bits.ic = 0;
    if (Adapter->TestPacketMode)
	desc->control.bits.ac = 1;
    eieio();
    desc->status.tx.own = 1;
    eieio();

    if (++txPutIndex == txRingSize)
	txPutIndex = 0;
    txNumFree--;

    /* Transmit poll demand; any value will do. */
    *(volatile unsigned int *)(ioBase + DC_CSR(CSR1)) = 1;
    eieio();

    for (i = 0; i < 10000; i++) {
	if (!desc->status.tx.own)
	    break;
	IODelay(500);
    }
    Adapter->TestPacketPollCount = 10000 - i;
    Adapter->TestPacketStatus = desc->status.data;

    if (desc->status.tx.own && !Adapter->TestPacketMode)
	IOLog("sendPacket: polling timed out\n");
    if (Adapter->TestPacketMode)
	Adapter->TestPacketMode = FALSE;
}

@end

/*
 * SROM images for boards whose own SROMs are wrong, matched by PCI id
 * and marker bytes.  The image holds SROM word values; -patchSROM:...
 * stores them back in SROM byte order.
 */
const dcSromPatch_t patchTable[] = {
    {
	"Zynx 21140", DC21140_CFID, 20,
	{
	    { 0x14, 0x00, 0x00 },	/* address OUI 00:c0:95 */
	    { 0x15, 0x00, 0xc0 },
	    { 0x16, 0x00, 0x95 },
	    { 0x1c, 0x00, 0x00 },	/* leaf offset high byte */
	    { 0x02, 0x1b, 0x03 },	/* leaf: GEP control 0x03 */
	    { 0x03, 0x1b, 0x02 },	/* leaf: 2 media blocks */
	    { 0x80, 0x00, 0x06 },	/* out of range: unused */
	    { 0x80, 0x00, 0x07 },
	},
	{
	    0xffff, 0xffff, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x00ff, 0x0103, 0xbbaa, 0xddcc, 0xffee, 0x1e00, 0x0000, 0x0800,
	    0x0100, 0x018c, 0x0000, 0x0000, 0xe078, 0x0001, 0x0050, 0x0018,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0xd2fc,
	},
    },
    {
	"Apple 100BaseTX", DC21140_CFID, 20,
	{
	    { 0x14, 0x00, 0x00 },	/* address OUI 00:05:02 */
	    { 0x15, 0x00, 0x05 },
	    { 0x16, 0x00, 0x02 },
	    { 0x1b, 0x00, 0x00 },	/* leaf offset 0 */
	    { 0x1c, 0x00, 0x00 },
	    { 0x80, 0x00, 0x05 },	/* out of range: unused */
	    { 0x80, 0x00, 0x06 },
	    { 0x80, 0x00, 0x07 },
	},
	{
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0101, 0xbbaa, 0xddcc, 0xffee, 0x1e00, 0x0000, 0x0800,
	    0x021f, 0x1b03, 0x406d, 0x1b05, 0x406d, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x46ba,
	},
    },
    {
	"Asante 21140", DC21140_CFID, 0,
	{
	    { 0x00, 0x00, 0x00 },	/* address OUI 00:00:94 at 0 */
	    { 0x01, 0x00, 0x00 },
	    { 0x02, 0x00, 0x94 },
	    { 0x10, 0x00, 0x00 },	/* and again at 16 */
	    { 0x11, 0x00, 0x00 },
	    { 0x12, 0x00, 0x94 },
	    { 0x80, 0x00, 0x06 },	/* out of range: unused */
	    { 0x80, 0x00, 0x07 },
	},
	{
	    0xffff, 0xffff, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x00ff, 0x0103, 0xbbaa, 0xddcc, 0xffee, 0x1e00, 0x0000, 0x0800,
	    0x01ff, 0x018c, 0x0000, 0xff02, 0x0000, 0xe078, 0x0001, 0x0050,
	    0x0018, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x5216,
	},
    },
};

const int patchTableCount = sizeof(patchTable) / sizeof(patchTable[0]);
