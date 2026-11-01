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
 * DEC21x4Private.m
 *
 * Descriptor rings, mbuf transmit/receive, interrupt handling and
 * address filtering for the DEC 21x4x Ethernet driver.
 *
 * HISTORY
 *
 * Reconstructed for RhapsodiOS from the DEC21x4 code linked into the
 * Mac OS X Server 1.2v3 (kernel 5.6) ppc mach_kernel.
 */

#import "DEC21x4.h"

#import <mach/vm_param.h>
#import <kern/thread_call.h>
#import <kernserv/queue.h>
#import <bsd/net/if.h>

@implementation DEC21x4(Private)

/*
 * Debugging aids; nothing calls them.
 */
static void
dc_print_desc(dcDescriptor_t *desc)
{
    IOLog("DESC: ");
    IOLog("%x (%x) ", DC_SWAP_LONG(desc->status.data), desc->status.data);
    IOLog("%x (%x: %x %x) ", DC_SWAP_LONG(desc->control.data),
	desc->control.data,
	desc->control.bits.bs1_lo | (desc->control.bits.bs1_hi << 8),
	desc->control.bits.bs2_lo | (desc->control.bits.bs2_hi << 5));
    IOLog("%x (%x) ", DC_SWAP_LONG(desc->buffer1), desc->buffer1);
    IOLog("%x (%x) ", DC_SWAP_LONG(desc->buffer2), desc->buffer2);
    IOLog("\n");
}

static void
dc_print_mbuf(struct mbuf *m)
{
    for (; m; m = m->m_next) {
	IOLog("mbuf: %08x\n", m);
	IOLog("next: %08x\n", m->m_next);
	IOLog("len : %d\n", m->m_len);
	IOLog("data: %08x\n", m->m_data);
	IOLog("flag: %08x\n\n", m->m_flags);
    }
}

typedef struct {
    unsigned int	phys;
    int			len;
} dcPhysRange_t;

/*
 * Physical range(s) of a virtual buffer: one, or two if it crosses a
 * page boundary (second->len is 0 otherwise).
 */
static __inline__ BOOL
getPhysicalRanges(vm_task_t task, vm_address_t vaddr, int len,
    dcPhysRange_t *first, dcPhysRange_t *second)
{
    vm_address_t	pageBreak;

    if (len <= 0 ||
	IOPhysicalFromVirtual(task, vaddr, &first->phys) != IO_R_SUCCESS)
	return NO;

    if ((vaddr & ~page_mask) == ((vaddr + len - 1) & ~page_mask)) {
	first->len = len;
	second->len = 0;
	return YES;
    }

    pageBreak = round_page(vaddr);
    first->len = pageBreak - vaddr;
    len -= first->len;
    if (IOPhysicalFromVirtual(task, pageBreak, &second->phys) != IO_R_SUCCESS)
	return NO;
    second->len = len;
    return YES;
}

/*
 * Global, and also expanded inline into -transmitMbuf: below; the
 * kernel debugger's -sendPacket:length: calls the out-of-line copy.
 *
 * Point a transmit descriptor at the data of *mp starting at *offset.
 * If that data crosses a page it fills both buffers.  Otherwise buffer 2
 * takes (the first page of) the next non-empty mbuf, *mp advances to it
 * and *offset says how much of it was used.
 */
__inline__ BOOL
IOUpdateTxDescriptorFromMbuf(DEC21x4 *self, struct mbuf **mp,
    unsigned int *offset, dcDescriptor_t *desc)
{
    struct mbuf		*m = *mp;
    dcDriverStats_t	*stats = &self->drvstat;
    dcPhysRange_t	range[3];

    range[0].phys = 0;
    range[1].phys = 0;

    if (!getPhysicalRanges(self->driver_task,
	    mtod(m, vm_address_t) + *offset, m->m_len - *offset,
	    &range[0], &range[1]))
	return NO;

    if (range[1].len) {
	DC_SET_BUFFER_SIZES(desc, range[0].len, range[1].len);
	desc->buffer1 = DC_SWAP_LONG(range[0].phys);
	desc->buffer2 = DC_SWAP_LONG(range[1].phys);
	eieio();
	*offset = 0;
	stats->tx_page_crossed++;
	return YES;
    }

    range[2].len = 0;
    for (m = m->m_next; m; m = m->m_next) {
	if (m->m_len == 0)
	    continue;
	if (!getPhysicalRanges(self->driver_task, mtod(m, vm_address_t),
		m->m_len, &range[2], &range[1]))
	    return NO;
	break;
    }

    DC_SET_BUFFER_SIZES(desc, range[0].len, range[2].len);
    desc->buffer1 = DC_SWAP_LONG(range[0].phys);
    desc->buffer2 = DC_SWAP_LONG(range[2].phys);
    eieio();

    if (range[1].len) {
	*offset = range[2].len;
	stats->tx_page_crossed++;
    }
    else
	*offset = 0;
    *mp = m;
    return YES;
}

/*
 * Take the first packet off the driver's transmit queue.
 */
static __inline__ struct mbuf *
dequeueMbuf(DEC21x4 *self)
{
    struct mbuf	*m;

    if (self->Qcount == 0)
	return NULL;

    m = self->Qhead;
    self->Qhead = m->m_nextpkt;
    m->m_nextpkt = NULL;
    if (--self->Qcount == 0)
	self->Qtail = self->Qhead = NULL;
    return m;
}

/*
 * Point a receive descriptor at a cluster mbuf, longword aligning its
 * data and splitting the buffer at a page boundary if needed.
 */
static __inline__ BOOL
IOUpdateRxDescriptorFromMbuf(DEC21x4 *self, struct mbuf *m,
    dcDescriptor_t *desc)
{
    vm_address_t	vaddr, pageBreak;
    unsigned int	paddr1, paddr2;
    int			len1;

    vaddr = mtod(m, vm_address_t);
    if (vaddr & 3) {
	vaddr = vaddr + 4 - (vaddr & 3);
	m->m_data = (caddr_t)vaddr;
	self->drvstat.rx_alignment++;
    }

    if (IOPhysicalFromVirtual(self->driver_task, vaddr, &paddr1) !=
	IO_R_SUCCESS)
	return NO;
    desc->buffer1 = DC_SWAP_LONG(paddr1);

    if ((vaddr & ~page_mask) ==
	((vaddr + RX_BUFFER_SIZE - 1) & ~page_mask)) {
	DC_SET_BUFFER_SIZES(desc, RX_BUFFER_SIZE, 0);
    }
    else {
	pageBreak = round_page(vaddr);
	self->drvstat.rx_page_crossed++;
	if (IOPhysicalFromVirtual(self->driver_task, pageBreak, &paddr2) !=
	    IO_R_SUCCESS)
	    return NO;
	len1 = pageBreak - vaddr;
	DC_SET_BUFFER_SIZES(desc, len1, RX_BUFFER_SIZE - len1);
	desc->buffer2 = DC_SWAP_LONG(paddr2);
    }
    eieio();
    return YES;
}

/*
 * Copy an mbuf chain into a single new mbuf (with a cluster if it
 * does not fit in a header mbuf).
 */
static __inline__ struct mbuf *
coalesceMbuf(struct mbuf *m)
{
    struct mbuf	*n;

    MGETHDR(n, M_DONTWAIT, MT_DATA);
    if (n == NULL)
	return NULL;

    if (m->m_pkthdr.len > MHLEN) {
	MCLGET(n, M_DONTWAIT);
	if ((n->m_flags & M_EXT) == 0) {
	    m_free(n);
	    return NULL;
	}
    }
    m_copydata(m, 0, m->m_pkthdr.len, mtod(n, caddr_t));
    n->m_len = n->m_pkthdr.len = m->m_pkthdr.len;
    return n;
}

/*
 * Allocate memory that starts on a page boundary and spans no more
 * pages than it has to.
 */
static void *
IOMallocPage(unsigned int request_size, void **actual_ptr,
    unsigned int *actual_size)
{
    void	*mem_ptr;

    *actual_size = round_page(request_size) + page_size;
    mem_ptr = IOMalloc(*actual_size);
    if (mem_ptr == NULL)
	return NULL;
    *actual_ptr = mem_ptr;
    return (void *)round_page(mem_ptr);
}


- (void)enableAdapterInterrupts
{
    int		s;

    (*_kdbLock)(self, @selector(reserveDebuggerLock));
    s = splnet();

    writeCsr(ioBase, DC_CSR(CSR7), 0);
    writeCsr(ioBase, DC_CSR(CSR5), readCsr(ioBase, DC_CSR(CSR5)));
    Adapter->InterruptStatusMask = 0xffffffff;
    writeCsr(ioBase, DC_CSR(CSR7), Adapter->InterruptMask);
    ready = YES;

    splx(s);
    (*_kdbUnlock)(self, @selector(releaseDebuggerLock));
}

- (void)disableAdapterInterrupts
{
    int		s;

    (*_kdbLock)(self, @selector(reserveDebuggerLock));
    s = splnet();

    writeCsr(ioBase, DC_CSR(CSR7), 0);
    writeCsr(ioBase, DC_CSR(CSR5), readCsr(ioBase, DC_CSR(CSR5)));
    ready = NO;

    splx(s);
    (*_kdbUnlock)(self, @selector(releaseDebuggerLock));
}

- (BOOL)_allocateDescMemory:(dcDescMemory_t *)descMem size:(unsigned int)size
{
    if (size == 0 || size > page_size) {
	IOLog("%s: page limit exceeded for descriptor memory\n", [self name]);
	return NO;
    }

    descMem->size = size;
    descMem->ptr = IOMallocPage(size, &descMem->ptrReal, &descMem->sizeReal);
    if (descMem->ptr == NULL) {
	IOLog("%s: can't allocate %d bytes of memory\n", [self name],
	    descMem->size);
	return NO;
    }
    return YES;
}

- (void)_freeDescMemory:(dcDescMemory_t *)descMem
{
    if (descMem->ptr) {
	IOFree(descMem->ptrReal, descMem->sizeReal);
	descMem->ptr = NULL;
    }
}

- (BOOL)_allocateMemory
{
    int		i;

    if (![self _allocateDescMemory:&txDescMem
	    size:txRingSize * sizeof(dcDescriptor_t)])
	return NO;
    txRing = (dcDescriptor_t *)txDescMem.ptr;
    for (i = 0; i < txRingSize; i++) {
	bzero(&txRing[i], sizeof(dcDescriptor_t));
	txMbuf[i] = NULL;
    }

    /* The setup frame buffer follows the receive ring. */
    if (![self _allocateDescMemory:&rxDescMem
	    size:rxRingSize * sizeof(dcDescriptor_t) + SETUP_FRAME_SIZE])
	return NO;
    rxRing = (dcDescriptor_t *)rxDescMem.ptr;
    for (i = 0; i < rxRingSize; i++) {
	bzero(&rxRing[i], sizeof(dcDescriptor_t));
	rxMbuf[i] = NULL;
    }

    setupBuffer = (dcSetupBuffer_t *)&rxRing[rxRingSize];
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)setupBuffer,
	    &setupBufferPhysical) != IO_R_SUCCESS) {
	IOLog("%s: IOPhysicalFromVirtual failed\n", [self name]);
	return NO;
    }

    eieio();
    return YES;
}

- (BOOL)_initTxRing
{
    struct mbuf		*m;
    unsigned int	i;

    while ((m = dequeueMbuf(self)) != NULL)
	m_freem(m);

    for (i = 0; i < txRingSize; i++) {
	bzero(&txRing[i], sizeof(dcDescriptor_t));
	eieio();
	txRing[i].status.tx.own = 0;
	eieio();
	if (txMbuf[i]) {
	    m_freem(txMbuf[i]);
	    txMbuf[i] = NULL;
	}
    }
    txRing[txRingSize - 1].control.data |= DC_TDES1_TER;
    eieio();

    txPutIndex = 0;
    txDoneIndex = 0;
    txIntCount = 0;
    txNumFree = txRingSize;
    return YES;
}

- (BOOL)_initRxRing
{
    int		i;

    for (i = 0; i < rxRingSize; i++) {
	bzero(&rxRing[i], sizeof(dcDescriptor_t));
	eieio();
	rxRing[i].status.rx.own = 0;
	eieio();

	if (rxMbuf[i] == NULL) {
	    MGETHDR(rxMbuf[i], M_DONTWAIT, MT_DATA);
	    if (rxMbuf[i] == NULL)
		IOPanic("_initRxRing: MGETHDR failed");
	    MCLGET(rxMbuf[i], M_DONTWAIT);
	    if ((rxMbuf[i]->m_flags & M_EXT) == 0)
		IOPanic("_initRxRing: MCLGET failed");
	}

	if (!IOUpdateRxDescriptorFromMbuf(self, rxMbuf[i], &rxRing[i]))
	    IOPanic("_initRxRing: IOUpdateRxDescriptorFromMbuf failed");

	rxRing[i].status.rx.own = 1;
	eieio();
    }
    rxRing[rxRingSize - 1].control.data |= DC_TDES1_TER;
    eieio();

    rxDoneIndex = 0;
    return YES;
}

- (void)_startTransmit
{
    Adapter->OperationMode |= DC_CSR6_ST;
    writeCsr(ioBase, DC_CSR(CSR6), Adapter->OperationMode);
    IODelay(2000);
}

- (void)_startReceive
{
    Adapter->OperationMode |= DC_CSR6_SR;
    writeCsr(ioBase, DC_CSR(CSR6), Adapter->OperationMode);
    IODelay(2000);
}

void
dc_increment_out_errors(DEC21x4 *self, int count)
{
    self->ifp->if_oerrors += count;
}

void
dc_increment_in_errors(DEC21x4 *self, int count)
{
    self->ifp->if_ierrors += count;
}

void
dc_increment_collisions(DEC21x4 *self, int count)
{
    self->ifp->if_collisions += count;
    self->drvstat.tx_col += count;
}

void
dc_increment_out_packets(DEC21x4 *self, int count)
{
    self->ifp->if_opackets += count;
}

- (void)transmit:(netbuf_t)pkt
{
    struct mbuf	*m = (struct mbuf *)pkt;
    struct mbuf	*n;
    int		result;

    if (!ready) {
	if (m)
	    m_freem(m);
	return;
    }

    /* Reclaim finished descriptors if the ring is short. */
    if (m && (txNumFree <= 1 || Qcount)) {
	disableFlush = YES;
	dc_intr_tx(self);
	disableFlush = NO;
	drvstat.tx_low_water++;
    }

    /* Drain the queue first. */
    while (Qcount && txNumFree > 1) {
	result = (int)(*_transmitMbufFunc)(self, @selector(transmitMbuf:),
	    Qhead);
	if (result == TRANSMIT_QUEUE)
	    break;
	n = dequeueMbuf(self);
	if (result == TRANSMIT_DROP)
	    m_freem(n);
    }

    if (m == NULL)
	return;

    result = TRANSMIT_QUEUE;
    if (Qcount == 0 && txNumFree > 1) {
	result = (int)(*_transmitMbufFunc)(self, @selector(transmitMbuf:), m);
	if (result == TRANSMIT_OK)
	    return;
    }

    if (result != TRANSMIT_QUEUE) {
	m_freem(m);
	return;
    }

    if (Qcount < maxQueueSize) {
	if (Qcount++ == 0)
	    Qtail = Qhead = m;
	else {
	    Qtail->m_nextpkt = m;
	    Qtail = m;
	}
	while (Qtail->m_nextpkt) {
	    Qtail = Qtail->m_nextpkt;
	    Qcount++;
	}
    }
    else {
	m_freem(m);
	drvstat.tx_queue_full++;
    }

    if (Qcount > drvstat.tx_fifo_max)
	drvstat.tx_fifo_max = Qcount;
}

/*
 * Put an mbuf chain on the transmit ring.  A chain that needs more
 * descriptors than are free, while the ring is mostly busy, is copied
 * into a single mbuf; TRANSMIT_DROP then tells the caller to free the
 * original chain.
 */
- (int)transmitMbuf:(struct mbuf *)m
{
    unsigned int	savedIntCount = txIntCount;
    unsigned int	putIndex = txPutIndex;
    dcDescriptor_t	*desc = NULL;
    struct mbuf		*cur;
    struct mbuf		*n;
    unsigned int	offset;
    unsigned int	count = 0;
    unsigned int	control = 0;
    unsigned int	status;
    unsigned int	index;
    int			result = TRANSMIT_OK;

    (*_kdbLock)(self, @selector(reserveDebuggerLock));

    if (txNumFree == 0) {
	result = TRANSMIT_QUEUE;
	goto rollback;
    }

restart:
    for (cur = m; cur; cur = cur->m_next) {
	offset = 0;
	if (cur->m_len == 0)
	    continue;

	do {
	    if (count + 1 > txNumFree) {
		if (count <= txRingSize - txIntThreshold) {
		    result = TRANSMIT_QUEUE;
		    goto rollback;
		}

		n = coalesceMbuf(m);
		result = TRANSMIT_DROP;
		drvstat.tx_coalesced++;
		if (n == NULL) {
		    drvstat.tx_coalesce_err++;
		    goto rollback;
		}
		m = n;

		/* Give back the descriptors taken so far and start over. */
		index = txPutIndex;
		while (count--) {
		    txRing[index].status.tx.own = 0;
		    eieio();
		    if (++index == txRingSize)
			index = 0;
		}
		count = 0;
		savedIntCount = txIntCount;
		putIndex = txPutIndex;
		goto restart;
	    }

	    /* The first descriptor is handed to the chip last, below. */
	    desc = &txRing[putIndex];
	    control = (putIndex == txRingSize - 1) ? DC_TDES1_TER : 0;
	    status = 0;
	    if (count == 0)
		control |= DC_TDES1_FS;
	    else
		status = DC_DESC_OWN;
	    desc->control.data = control;
	    desc->status.data = status;
	    eieio();

	    putIndex++;
	    txIntCount++;
	    if (putIndex == txRingSize)
		putIndex = 0;
	    count++;

	    if (!IOUpdateTxDescriptorFromMbuf(self, &cur, &offset, desc)) {
		result = TRANSMIT_DROP;
		IOLog("%s: IOUpdateTxDescriptorFromMbuf() error\n",
		    [self name]);
		goto rollback;
	    }
	} while (offset);

	if (cur == NULL)
	    break;
    }

    if (count == 0) {
	result = TRANSMIT_DROP;
	IOLog("%s: zero-length mbuf chain\n", [self name]);
	goto rollback;
    }

    txMbuf[txPutIndex] = m;

    control |= DC_TDES1_LS;
    if (txIntCount >= txIntThreshold) {
	txIntCount = 0;
	control |= DC_TDES1_IC;
    }
    desc->control.data |= control;
    eieio();

    txRing[txPutIndex].status.tx.own = 1;
    eieio();

    txPutIndex = putIndex;
    txNumFree -= count;

    /* transmit poll demand; any value will do, so it is not swapped */
    *(u_long *)(ioBase + DC_CSR(CSR1)) = 1;
    eieio();

    (*_kdbUnlock)(self, @selector(releaseDebuggerLock));
    return result;

rollback:
    index = txPutIndex;
    while (count--) {
	txRing[index].status.tx.own = 0;
	eieio();
	if (++index == txRingSize)
	    index = 0;
    }
    drvstat.tx_rollback++;
    txIntCount = savedIntCount;

    (*_kdbUnlock)(self, @selector(releaseDebuggerLock));
    return result;
}

static void
rx_err_record(dcDescStatus_t *status, dcDriverStats_t *stats)
{
    if (status->rx.ls) {
	if (status->rx.rf && !status->rx.zer)
	    stats->rx_rf++;
	if (status->rx.tl)
	    stats->rx_tl++;
	if (status->rx.cs)
	    stats->rx_cs++;
	if (status->rx.rw)
	    stats->rx_rj++;
	if (status->rx.db && !status->rx.cs && !status->rx.rf)
	    stats->rx_db++;
	if (status->rx.ce)
	    stats->rx_ce++;
	if (status->rx.de)
	    stats->rx_de++;
    }
    if (status->rx.re)
	stats->rx_re++;
}

void
tx_err_record(dcDescStatus_t *status, dcDriverStats_t *stats)
{
    if (status->tx.lo)
	stats->tx_lo++;
    if (status->tx.nc)
	stats->tx_nc++;
    if (status->tx.lc && !status->tx.uf)
	stats->tx_lc++;
    if (status->tx.ec)
	stats->tx_ec++;
    if (status->tx.uf)
	stats->tx_uf++;
    if (status->tx.to)
	stats->tx_to++;
}

/*
 * Receive thread: runs from thread_call_func(), with RI masked by
 * dc_intr() until the ring has been emptied.
 */
static void
dc_intr_rx(DEC21x4 *self)
{
    dcDescriptor_t	*desc;
    struct mbuf		*m, *rxm;
    unsigned int	len;
    int			s;

    (*self->_kdbLock)(self, @selector(reserveDebuggerLock));

    desc = &self->rxRing[self->rxDoneIndex];
    while (!desc->status.rx.own) {
	/* acknowledge RI; the test and the value are not swapped */
	s = splnet();
	if (*(u_long *)(self->ioBase + DC_CSR(CSR5)) & DC_RAW_INT_RI) {
	    *(u_long *)(self->ioBase + DC_CSR(CSR5)) = DC_RAW_INT_RI;
	    eieio();
	}
	splx(s);

	len = (desc->status.rx.fl_lo | (desc->status.rx.fl_hi << 8)) - 4;

	if ((desc->status.data & self->Adapter->RxErrorMask) ||
	    !desc->status.rx.fs || !desc->status.rx.ls ||
	    len < MIN_FRAME_SIZE) {
	    self->ifp->if_ierrors++;
	    rx_err_record(&desc->status, &self->drvstat);
	    desc->status.rx.own = 1;
	    eieio();
	    if (++self->rxDoneIndex == self->rxRingSize)
		self->rxDoneIndex = 0;
	    desc = &self->rxRing[self->rxDoneIndex];
	    continue;
	}

	m = NULL;
	rxm = self->rxMbuf[self->rxDoneIndex];

	if (!self->isPromiscuous && self->filterMode != FILTER_PERFECT &&
	    desc->status.rx.mf &&
	    [self isUnwantedMulticastPacket:mtod(rxm, ether_header_t *)])
	    goto next;

	MGETHDR(m, M_DONTWAIT, MT_DATA);
	if (m == NULL) {
	    self->drvstat.rx_MGETHDR_failed++;
	    goto next;
	}

	if (len < MHLEN - 2) {
	    /* Small frame: copy it out and keep the cluster on the ring. */
	    self->drvstat.rx_short_frame++;
	    m->m_pkthdr.len = m->m_len = len;
	    m->m_data += 2;
	    fast_bcopy(mtod(rxm, void *), mtod(m, void *), len);
	    goto next;
	}

	/* Large frame: pass the cluster up and put a new one on the ring. */
	self->drvstat.rx_long_frame++;
	MCLGET(m, M_DONTWAIT);
	if ((m->m_flags & M_EXT) == 0) {
	    self->drvstat.rx_MCLGET_failed++;
	    m_free(m);
	    m = NULL;
	    goto next;
	}

	self->rxMbuf[self->rxDoneIndex] = m;
	if (!IOUpdateRxDescriptorFromMbuf(self, m, desc))
	    IOPanic("dc_intr_rx: IOUpdateRxDescriptorFromMbuf() error\n");

	m = rxm;
	m->m_pkthdr.len = m->m_len = len;

next:
	desc->status.rx.own = 1;
	eieio();
	if (++self->rxDoneIndex == self->rxRingSize)
	    self->rxDoneIndex = 0;
	desc = &self->rxRing[self->rxDoneIndex];

	if (m) {
	    (*self->_inputPacketFunc)(self, @selector(inputPacket:extra:),
		m, 0);
	    self->drvstat.rx_f++;
	}
    }

    s = splnet();
    self->Adapter->InterruptStatusMask |= DC_INT_RI;
    self->Adapter->InterruptMask |= DC_INT_RI;
    self->Adapter->InterruptDispatchMask |= DC_INT_RI;
    writeCsr(self->ioBase, DC_CSR(CSR7), self->Adapter->InterruptMask);
    splx(s);

    (*self->_kdbUnlock)(self, @selector(releaseDebuggerLock));
}

/*
 * Reclaim finished transmit descriptors.
 */
void
dc_intr_tx(DEC21x4 *self)
{
    dcDescriptor_t	*desc;
    dcDescStatus_t	status;
    struct mbuf		**mp;
    struct mbuf		*m;

    (*self->_kdbLock)(self, @selector(reserveDebuggerLock));

    while (self->txNumFree < self->txRingSize) {
	desc = &self->txRing[self->txDoneIndex];
	status = desc->status;
	mp = &self->txMbuf[self->txDoneIndex];

	if (status.data & DC_DESC_OWN)
	    break;

	if (desc->control.data & DC_TDES1_SET) {
	    /* setup frame: no mbuf, no statistics */
	    if (++self->txDoneIndex == self->txRingSize)
		self->txDoneIndex = 0;
	    self->txNumFree++;
	    continue;
	}

	if (desc->control.data & DC_TDES1_LS) {
	    if (status.data & self->Adapter->TxErrorMask) {
		self->ifp->if_oerrors++;
		tx_err_record(&desc->status, &self->drvstat);
	    }
	    else {
		self->ifp->if_opackets++;
		self->drvstat.tx_f++;
	    }

	    if (status.tx.de)
		self->drvstat.tx_de++;

	    if (status.tx.ec) {
		self->ifp->if_collisions += 16;
		self->drvstat.tx_col += 16;
	    }
	    else if (status.tx.cc) {
		self->ifp->if_collisions += status.tx.cc;
		self->drvstat.tx_col += status.tx.cc;
	    }

	    if (status.tx.lc && !status.tx.uf) {
		self->ifp->if_collisions++;
		self->drvstat.tx_col++;
	    }
	}

	if (*mp) {
	    m_freem(*mp);
	    *mp = NULL;
	}
	if (++self->txDoneIndex == self->txRingSize)
	    self->txDoneIndex = 0;
	self->txNumFree++;
    }

    /* Packets sent by the kernel debugger are freed here. */
    while (self->kdbQueue.ifq_len) {
	IF_DEQUEUE(&self->kdbQueue, m);
	if (m)
	    m_freem(m);
    }

    (*self->_kdbUnlock)(self, @selector(releaseDebuggerLock));

    if (!self->disableFlush && self->Qcount)
	(*self->_transmitFunc)(self, @selector(transmit:), NULL);
}

static void
dc_intr_tx_jabber(DEC21x4 *self)
{
    unsigned int	txRingPhysical;
    int			s;

    IOLog("%s: transmit jabber timeout\n", [self name]);

    (*self->_kdbLock)(self, @selector(reserveDebuggerLock));
    s = splnet();

    [self _initTxRing];
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)self->txRing,
	    &txRingPhysical) != IO_R_SUCCESS)
	IOPanic("tx_jabber: IOPhysicalFromVirtual() error\n");
    stwbrx(txRingPhysical, self->ioBase + DC_CSR(CSR4));
    [self _startTransmit];

    splx(s);
    (*self->_kdbUnlock)(self, @selector(releaseDebuggerLock));
}

/*
 * Interrupt handler for every adapter on this irq.  Receive, transmit
 * and jabber work is passed to threads.
 */
void
dc_intr(int irq, void *ssp, void *arg)
{
    DEC21x4		*driver;
    dcDriverStats_t	*stats;
    u_long		status;
    int			count = inst;
    int			i;

    /* Mask all of them first. */
    for (i = 0; i < count; i++) {
	driver = (DEC21x4 *)irq_table[i].driver;
	if (driver->ready && irq_table[i].irq == irq) {
	    *(u_long *)(driver->ioBase + DC_CSR(CSR7)) = 0;
	    eieio();
	}
    }

    for (i = 0; i < count; i++) {
	driver = (DEC21x4 *)irq_table[i].driver;
	if (!driver->ready || irq_table[i].irq != irq)
	    continue;

	stats = &driver->drvstat;
	for (;;) {
	    status = readCsr(driver->ioBase, DC_CSR(CSR5)) &
		driver->Adapter->InterruptStatusMask;
	    if ((status & DC_INT_ALL) == 0)
		break;
	    writeCsr(driver->ioBase, DC_CSR(CSR5), status);

	    status &= driver->Adapter->InterruptDispatchMask;
	    if (status == 0)
		break;

	    if (status & DC_INT_LINK) {
		stats->link_events++;
		if (status & DC_INT_GPI)
		    HandleGepInterrupt(driver->Adapter);

		if (driver->Adapter->TimerState != DC21X4_TIMER_NWAY_10_CHECK &&
		    driver->Adapter->TimerState != DC21X4_TIMER_NWAY_100_CHECK) {
		    if (status & DC_INT_LNF) {
			HandleLinkFailInterrupt(driver->Adapter, &status);
			driver->_linkChangeInterruptCount = 0;
		    }
		    if (status & DC_INT_LNP) {
			HandleLinkPassInterrupt(driver->Adapter, &status);
			driver->_linkChangeInterruptCount = 0;
		    }
		    if (status & DC_INT_LC) {
			HandleLinkChangeInterrupt(driver->Adapter);
			if (driver->_linkChangeInterruptCount++ > 20) {
			    driver->Adapter->InterruptMask &= ~DC_INT_LC;
			    driver->Adapter->InterruptDispatchMask &= ~DC_INT_LC;
			    IOLog("DEC21x4: LinkChange interrupts disabled\n");
			}
		    }
		}
	    }

	    if (status & (DC_INT_RI | DC_INT_RU)) {
		driver->Adapter->InterruptMask &= ~DC_INT_RI;
		thread_call_func((thread_call_func_t)dc_intr_rx,
		    (thread_call_spec_t)driver, TRUE);
		driver->Adapter->InterruptStatusMask &= ~DC_INT_RI;
		driver->Adapter->InterruptDispatchMask &= ~DC_INT_RI;
		stats->rx_int++;
	    }

	    if (status & (DC_INT_TI | DC_INT_UNF)) {
		thread_call_func((thread_call_func_t)dc_intr_tx,
		    (thread_call_spec_t)driver, TRUE);
		if (status & DC_INT_UNF) {
		    /* transmit poll demand */
		    *(u_long *)(driver->ioBase + DC_CSR(CSR1)) = 1;
		    eieio();
		}
		stats->tx_int++;
	    }

	    if (status & DC_INT_TJT) {
		thread_call_func((thread_call_func_t)dc_intr_tx_jabber,
		    (thread_call_spec_t)driver, TRUE);
		stats->tx_to_int++;
	    }

	    if (status & DC_INT_SE) {
		IOLog("DEC21x4: System Error!\n");
		DC21X4StopAdapter(driver->Adapter);
	    }
	}
    }

    /* Unmask. */
    for (i = 0; i < count; i++) {
	driver = (DEC21x4 *)irq_table[i].driver;
	if (driver->ready && irq_table[i].irq == irq)
	    writeCsr(driver->ioBase, DC_CSR(CSR7),
		driver->Adapter->InterruptMask);
    }
}

/*
 * Queue a setup frame from setupBuffer.  A no-op descriptor goes in
 * front of it.
 */
- (BOOL)_loadSetupFilter:(BOOL)pollForCompletion filterMode:(int)mode
{
    dcDescriptor_t	*desc;
    int			time;

    if (txNumFree <= 1)
	return NO;

    desc = &txRing[txPutIndex];
    desc->control.data = 0;
    eieio();
    DC_SET_BUFFER_SIZES(desc, 0, 0);
    if (txPutIndex == txRingSize - 1)
	desc->control.data |= DC_TDES1_TER;
    eieio();
    desc->status.data = DC_DESC_OWN;
    eieio();
    if (++txPutIndex == txRingSize)
	txPutIndex = 0;
    desc = &txRing[txPutIndex];
    txNumFree--;
    eieio();

    desc->control.data = DC_TDES1_SET;
    if (mode == FILTER_HASH)
	desc->control.data = DC_TDES1_SET | DC_TDES1_FT0;
    if (!pollForCompletion)
	desc->control.data |= DC_TDES1_IC;
    if (txPutIndex == txRingSize - 1)
	desc->control.data |= DC_TDES1_TER;
    DC_SET_BUFFER_SIZES(desc, SETUP_FRAME_SIZE, 0);
    desc->buffer2 = 0;
    desc->buffer1 = DC_SWAP_LONG(setupBufferPhysical);
    desc->status.data = DC_DESC_OWN;
    eieio();
    if (++txPutIndex == txRingSize)
	txPutIndex = 0;
    txNumFree--;

    writeCsr(ioBase, DC_CSR(CSR1), 1);	/* transmit poll demand */

    if (pollForCompletion) {
	for (time = 10000; time > 0; time -= 10) {
	    IODelay(10);
	    if ((desc->status.data & DC_DESC_OWN) == 0)
		break;
	}
	if (time <= 0)
	    IOLog("%s: setup frame timeout\n", [self name]);
    }
    return YES;
}

/*
 * Perfect filtering holds the station, broadcast and 14 multicast
 * addresses; beyond that, switch to hash filtering.
 */
- (BOOL)_setAddressFiltering:(BOOL)pollForCompletion
{
    int		mode = FILTER_PERFECT;

    if (multicastEnabled) {
	queue_head_t	*multiQueue = [super multicastQueue];
	enetMulti_t	*multiAddr;
	unsigned int	q_count = 0;

	queue_iterate(multiQueue, multiAddr, enetMulti_t *, link)
	    q_count++;
	if (q_count > SETUP_ADDRESS_COUNT - 2)
	    mode = FILTER_HASH;
    }

    if (mode != FILTER_PERFECT)
	[self _setupHashFiltering];
    else
	[self _setupPerfectFiltering];

    if (![self _loadSetupFilter:pollForCompletion filterMode:mode])
	return NO;

    if (filterMode != mode)
	IOLog("%s: filter switched to %s filtering\n", [self name],
	    mode != FILTER_PERFECT ? "hash" : "perfect");
    filterMode = mode;
    return YES;
}

- (void)_setupPerfectFiltering
{
    int			i;
    unsigned short	*address;
    unsigned int	q_count;

    /*
     * Station address in the first entry.  The upper 2 bytes of each
     * longword are don't cares.
     */
    address = (unsigned short *)Adapter->PermanentAddress;
    for (i = 0; i < 3; i++)
	setupBuffer->address[0][i] = *address++ << 16;

    /* Broadcast in the second. */
    for (i = 0; i < 3; i++)
	setupBuffer->address[1][i] = 0xffffffff;
    eieio();

    q_count = 2;

    if (multicastEnabled) {
	enetMulti_t	*multiAddr;
	queue_head_t	*multiQueue = [super multicastQueue];
	union {
	    unsigned char	bytes[4];
	    unsigned long	word;
	} typeConvert;

	if (!queue_empty(multiQueue)) {
	    queue_iterate(multiQueue, multiAddr, enetMulti_t *, link) {
		if (q_count >= SETUP_ADDRESS_COUNT) {
		    IOLog("%s: %d multicast address limit exceeded\n",
			[self name], SETUP_ADDRESS_COUNT - 2);
		    break;
		}
		for (i = 0; i < 3; i++) {
		    typeConvert.bytes[0] = multiAddr->address.ea_byte[i * 2];
		    typeConvert.bytes[1] =
			multiAddr->address.ea_byte[i * 2 + 1];
		    setupBuffer->address[q_count][i] = typeConvert.word;
		}
		q_count++;
	    }
	}
    }

    /* Station address again in the unused entries. */
    for (; q_count < SETUP_ADDRESS_COUNT; q_count++)
	fast_bcopy(setupBuffer->address[0], setupBuffer->address[q_count],
	    3 * sizeof(u_long));
    eieio();
}

/*
 * 9-bit hash filter index: the top 9 bits of the little-endian CRC-32
 * of the address, bit reversed.
 */
static unsigned int
dc_hash_index(unsigned char *addr)
{
    unsigned long	crc = 0xffffffff;
    unsigned char	byte;
    unsigned int	index;
    int			i, bit, carry;

    for (i = 0; i < 6; i++) {
	byte = addr[i];
	for (bit = 0; bit < 8; bit++) {
	    carry = (crc >> 31) ^ (byte & 1);
	    crc <<= 1;
	    if (carry)
		crc = (crc ^ 0x04c11db6) | 1;
	    byte >>= 1;
	}
    }

    index = 0;
    for (bit = 0; bit < 9; bit++)
	index |= ((crc >> (23 + bit)) & 1) << (8 - bit);
    return index;
}

- (void)_initHashFilter
{
    bzero(setupBuffer, SETUP_FRAME_SIZE);
}

- (void)_updateHashFilter:(enet_addr_t *)addr
{
    /* Bit within the longword for each of the 16 bits of a table word. */
    char		bitMap[16] = {
	24, 25, 26, 27, 28, 29, 30, 31,
	16, 17, 18, 19, 20, 21, 22, 23,
    };
    unsigned int	index, word;

    index = dc_hash_index(addr->ea_byte);
    if (index > 511) {
	IOLog("%s: Invalid hash filter index (%d)\n", [self name], index);
	return;
    }

    word = index >> 4;
    setupBuffer->address[word / 3][word % 3] |= 1 << bitMap[index & 0xf];
}

/*
 * Hash filtering: the 512-bit table in the first 32 longwords, the
 * station address perfect-filtered in entry 13.
 */
- (void)_setupHashFiltering
{
    enet_addr_t		broadcast = { { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff } };
    unsigned short	*address = (unsigned short *)Adapter->PermanentAddress;
    int			i;

    [self _initHashFilter];

    if (multicastEnabled) {
	enetMulti_t	*multiAddr;
	queue_head_t	*multiQueue = [super multicastQueue];

	queue_iterate(multiQueue, multiAddr, enetMulti_t *, link)
	    [self _updateHashFilter:&multiAddr->address];
    }
    [self _updateHashFilter:&broadcast];

    for (i = 0; i < 3; i++)
	setupBuffer->address[13][i] = *address++ << 16;
    eieio();
}

@end
