/*
 * Copyright (c) 1993-1996 NeXT Software, Inc.
 *
 * Driver class for SMC EtherCard Plus Elite16 adaptors.
 *
 * HISTORY
 *
 * 18 Apr 1995
 *	Enabled 16-bit mode. Some changes.
 *
 * 19 Apr 1993 
 *	Added multicast & promiscuous mode support.
 *
 * 26 Jan 1993
 *	Created.
 */

#define MACH_USER_API	1

#import <driverkit/generalFuncs.h>
#import <driverkit/IONetbufQueue.h>

#import "SMC16.h"
#import "SMC16IOInline.h"
#import "SMC16Private.h"


#import <kernserv/kern_server_types.h>
#import <kernserv/prototypes.h>

#define SIXTEEN_BIT_ENABLE	"Sixteen Bit Mode"

static BOOL sixteen_bit_mode = YES;

#define EIGHT_BIT		0
#define SIXTEEN_BIT		1

/*
 * This routine can set the m16en bit so it must be called with all
 * interrupts turned off. 
 */
static __inline__
void 
set_mode(
	unsigned int mode, 
	vm_offset_t addr, 
	IOEISAPortAddress base
	)
{
    bic_laar_t	laar;
    union {
	struct {
	    unsigned int		:13,
			    madr	:6,
			    ladr	:5,
			    		:8;
	} bic_addr;
	unsigned int	address;
    } _mconv;
    
    /*
     * All this is needed only when we are using the 16K buffer. 
     */
    if (sixteen_bit_mode == NO)
	return;

    if (mode == SIXTEEN_BIT)	{
	asm("cli");
	laar.m16en = 1;
    } else {
	laar.m16en = 0;
	asm("sti");
    }

    laar.zws16 = TRUE;
    laar.l16en = TRUE;

    _mconv.address = addr;
    laar.ladr = _mconv.bic_addr.ladr;

    put_laar(laar, base);

#ifdef undef 
    IOLog("laar:  %x %x %x %x\n", 
	    laar.m16en, laar.l16en, laar.zws16, laar.ladr);
#endif undef
}


@implementation SMC16

/*
 * Private Instance Methods
 */

/*
 * _memAvail
 * Returns the amount of onboard memory not currently in use.
 * Never returns less than zero.
 */
- (SMC16_len_t)_memAvail
{
    int		available;
    
    available = (memtotal - memused);
    
    return ((SMC16_len_t) ((available < 0)? 0: available));
}

/*
 * _memRegion
 * Returns the next available NIC_PAGE_SIZE chunk of onboard memory.
 */
- (SMC16_off_t)_memRegion:(SMC16_len_t)length
{
    if ([self _memAvail] < length)
    	IOPanic("SMC16: onboard memory exhausted");
	
    return ((SMC16_off_t) (memused / NIC_PAGE_SIZE));
}

/*
 * _memAlloc
 * Allocates onboard memory in chunks of NIC_PAGE_SIZE 
 */
- (SMC16_off_t)_memAlloc:(SMC16_len_t)length
{
    SMC16_off_t	region;
    
    /*
     * Round up to the next multiple of NIC_PAGE_SIZE
     */
    length = ((length + NIC_PAGE_SIZE - 1) & ~(NIC_PAGE_SIZE - 1));
    
    region = [self _memRegion:length];
    
    memused += length;
    
    return (region);
}

/*
 * _initializeHardware
 * Resets the SMC adaptor.  Disables interrupts, resets the NIC, and
 * configures the onboard memory.
 */
- (void)_initializeHardware
{    
    setIRQ(irq, YES, base);
    
    resetNIC(base);
    
    memtotal = setupRAM(membase, memsize, base);
    memused = 0;
}

/*
 * _receiveInitialize
 * Prepares the card for receive operations.  Allocates as many NIC_PAGE_SIZE
 * buffers from the available onboard memory.
 */
- (void)_receiveInitialize
{
    SMC16_len_t		avail = [self _memAvail];
    
    rstart = [self _memAlloc:avail];
    rstop = rstart + (avail / NIC_PAGE_SIZE);

    /*
     * Setup the receive ring
     */	
    put_rstart_reg(rstart, base); put_rstop_reg(rstop, base);
    
    /*
     * Reset the boundary buffer pointer
     */	
    put_bound_reg(rstart, base);
    
    rnext = rstart + 1;
    
    /*
     * Reset the current buffer pointer    
     */	
    (void)sel_reg_page(REG_PAGE1, base);
	put_curr_reg(rnext, base);
    (void)sel_reg_page(REG_PAGE0, base);
}

/*
 * _transmitInitialize
 * Prepares for transmit operations.  We use 1 transmit buffer of maximum
 * size.
 */
- (void)_transmitInitialize
{
    tstart = [self _memAlloc:ETHERMAXPACKET];
}

/*
 * _initializeSoftware
 * Prepare the adaptor for network operations and start them.
 */
- (void)_initializeSoftware
{
    setStationAddress(&myAddress, base);
    
    [self _transmitInitialize]; 
    [self _receiveInitialize];
        
    startNIC(base, rconsave);
}

/*
 * _receiveInterruptOccurred
 * This method handles the process of moving received frames from 
 * onboard adaptor memory to netbufs and handing them up to the network
 * object.
 */
- (void)_receiveInterruptOccurred
{
    nic_recv_hdr_t	*rhdr, rhdr_copy;
    netbuf_t		pkt;
    int			pkt_len, pre_wrap_len;
    void 		*pkt_data = NULL;

#ifdef DEBUG

    /*
     * Change this to 1 to be inundated with messages.
     */
    boolean_t	SMC16_recvTrace = 0;

#endif DEBUG

    
    /*
     * Grab buffers until we point to the next available one.
     */
    while (rnext != getCurrentBuffer(base)) {

	/*
	 * Point to the receive header in this buffer.
	 */
	rhdr = (nic_recv_hdr_t *)nic_page_addr(rnext,membase);

	/* 
	 * Access receive header from onboard RAM.
	 */
	set_mode(SIXTEEN_BIT, membase, base);
	rhdr_copy = *rhdr;
	set_mode(EIGHT_BIT, membase, base);

#ifdef DEBUG
	if (SMC16_recvTrace) {
	    IOLog("[rstat %02x next %02x len %03x rnext "
	    	"%02x bound %02x curr %02x]\n",
	    	*(unsigned char *)&rhdr_copy.rstat, 
		rhdr_copy.next, rhdr_copy.len, rnext, 
		get_bound_reg(base), getCurrentBuffer(base));
	}
#endif DEBUG
	
	
	/*
	 * Display a somewhat cryptic message if the prx bit is set.
	 */
	if (!rhdr_copy.rstat.prx) {
	    IOLog("rhdr1 rstat %02x next %02x len %x\n", 
	    	*(unsigned char *)&(rhdr_copy.rstat), rhdr_copy.next, 
		rhdr_copy.len);
	    [network incrementInputErrors];
	    rnext = rhdr_copy.next; 
	    
	    if ((rnext - 1) >= rstart)
		put_bound_reg(rnext - 1, base);
	    else
		put_bound_reg(rstop - 1, base);
	    continue;
	    continue;
	}
	
	/*
	 * Display a slightly different, equally cryptic message 
	 * if the pointer to the next buffer in this header is outside
	 * the range configured buffers.  If this is the case, force a
	 * reset by invoking -timeoutOccurred.
	 */
	if (rhdr_copy.next >= rstop || rhdr_copy.next < rstart) {
	    IOLog("rhdr2 rstat %02x next %02x len %x\n", 
	    	*(unsigned char *)&(rhdr_copy.rstat), 
		rhdr_copy.next, rhdr_copy.len);
	    [network incrementInputErrors];
	    [self timeoutOccurred]; 
	    return;
	}

	/*
	 * Get the overall packet length and the length between
	 * the start of the packet and the end of onboard memory.
	 * Any packet data beyond that will wrap back to the start
	 * of onboard memory.
	 */
	pkt_len = rhdr_copy.len - ETHERCRC;
	pre_wrap_len =	nic_page_addr(rstop,membase) -
			nic_page_addr(rnext,membase) -
			sizeof(rhdr_copy);

	/*
	 * If the packet length looks reasonable, allocate a net buffer
	 * for it and establish a pointer to the data in that net buffer.
	 */
	if (pkt_len >= (ETHERMINPACKET - ETHERCRC) && 
		pkt_len <= ETHERMAXPACKET) {
	    pkt = nb_alloc(pkt_len);
	    if (pkt)
	    	pkt_data = nb_map(pkt);
	}
	else {
	    [network incrementInputErrors];
	    pkt = 0;
	}
	    
	set_mode(SIXTEEN_BIT, membase, base);

	/*
	 * If none of the packet wraps around the ring, just
	 * copy it into the netbuf.
	 */
	if (pkt_len <= pre_wrap_len) {
	    if (pkt)
		IOCopyMemory(
			(void *)nic_page_addr(rnext,membase) + sizeof (*rhdr),
			pkt_data,
			pkt_len,
			sizeof(short));
	/*
	 * Otherwise, copy up to the end of memory, then copy the remaining
	 * portion from the start of memory.
	 */
	}
	else {
	    if (pkt) {
		IOCopyMemory(
			(void *)nic_page_addr(rnext,membase) + sizeof (*rhdr),
			pkt_data,
			pre_wrap_len,
			sizeof(short));
		IOCopyMemory(
			(void *)nic_page_addr(rstart,membase),
			pkt_data + pre_wrap_len,
			pkt_len - pre_wrap_len,
			sizeof(short));
	    }
	}
	
	rnext = rhdr->next;		// on to next buffer

	bzero((void *)rhdr, sizeof(nic_recv_hdr_t));

	set_mode(EIGHT_BIT, membase, base);
	
	/*
	 * Update the bounds register.
	 */
	if ((rnext - 1) >= rstart)
	    put_bound_reg(rnext - 1, base);
	else
	    put_bound_reg(rstop - 1, base);

	/*
	 * We only pass packets upward if they pass thru multicast filter.
	 */
	if(pkt) {
  	    if(rconsave.prom == 0 && [super 
		    isUnwantedMulticastPacket:(ether_header_t *)nb_map(pkt)]) {
		nb_free(pkt);
	    } 
	    else {
		
	    	[network handleInputPacket:pkt extra:0];

	    } 
	}
    }

}

/*
 * _receiveOverwriteOccurred
 * Called when the adaptor tells us that we haven't fetched frames from
 * onboard memory fast enough, so it's overwritten an old frame with a new
 * one.  Oh well...
 */
- (void)_receiveOverwriteOccurred
{
#ifdef DEBUG
    IOLog("overwrite bound %02x curr %02x rnext %02x\n", get_bound_reg(base), getCurrentBuffer(base), rnext);
    [network incrementInputErrors];
#endif DEBUG
}

/*
 * _transmitInterruptOccurred
 * Called when the adaptor indicated a transmit operation is complete.  Check
 * tstat register and increment the appropriate counters.  Clear the
 * timeout we set when we initiated the transmit and clear the transmitActive
 * flag.  Finally, if there are any outgoing packets in the queue, send the
 * next one.
 */
- (void)_transmitInterruptOccurred
{
    nic_tstat_reg_t	tstat_reg;
    netbuf_t		pkt;

    if (transmitActive) {
    	tstat_reg = get_tstat_reg(base);
	
	/*
	 * Always check transmit status (if available) here.  On a
	 * transmit error, increment statistics and reset the
	 * adaptor if necessary (not for SMC).  NEVER TRY TO 
	 * RETRANSMIT A PACKET.  Leave this up to higher level
	 * software, which should insure reliability when
	 * it's needed.
	 */
	if (tstat_reg.ptx)
	    [network incrementOutputPackets];
	else
	    [network incrementOutputErrors];
	    
	if (tstat_reg.abort || tstat_reg.twc)
	    [network incrementCollisions];
	
	[self clearTimeout];    
	transmitActive = NO;
	
	if (pkt = [transmitQueue dequeue])
	    [self transmit:pkt];
    }
}

/*
 * Public Factory Methods
 */
 
+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    SMC16		*dev = [self alloc];
    IOEISADeviceDescription
    		*deviceDescription = (IOEISADeviceDescription *)devDesc;
    IORange		*io;

    if (dev == nil)
    	return NO;
	
    /* 
     * Valid configuration?
     */
    if (	[deviceDescription numPortRanges] < 1
	    ||
	    	[deviceDescription numMemoryRanges] < 1
	    ||
    		[deviceDescription numInterrupts] < 1) {
    	[dev free]; 
	return NO;
    }
    
    /*
     * Make sure we're configured for 16K (even though we can only use 8)
     */
    io = [deviceDescription memoryRangeList];
    if (io->size < 16*1024) {
    	[dev free]; 
	return NO;
    }
    
    /*
     * More configuration validation
     */
    io = [deviceDescription portRangeList];
    if (io->size < 16) {
	[dev free]; 
	return NO;
    }

    /* 
     * Configuration checks out so let's actually probe for hardware.
     */
    if (!checksumLAR(io->start)) {
    	IOLog("SMC16: Adaptor not present or invalid EEROM checksum.\n");
	[dev free]; 
	return NO;
    }
    
    if (!checkBoardRev(io->start)) {
    	IOLog("SMC16: Unsupported board revision.\n");
	[dev free]; 
	return NO;
    }
    
    return [dev initFromDeviceDescription:devDesc] != nil;
}

/*
 * Public Instance Methods
 */

- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IOEISADeviceDescription
		    *deviceDescription = (IOEISADeviceDescription *)devDesc;
    IORange		*io;
    const char		*params;

    if ([super initFromDeviceDescription:devDesc] == nil) 
    	return nil;
	
    /* 
     * Initialize ivars
     */
    irq = [deviceDescription interrupt];
    
    io = [deviceDescription portRangeList];
    base = io->start;
    
    io = [deviceDescription memoryRangeList];
    membase = io->start;	
    memsize = io->size;

    /*
     * The default mode is 16-bit and uses 16K RAM. 
     */
    sixteen_bit_mode = YES;
    params = [[deviceDescription configTable] 
		valueForStringKey:SIXTEEN_BIT_ENABLE];

    if ((params) && (strcmp(params, "NO") == 0))
	sixteen_bit_mode = NO;
    
    /*
     * Broadcasts should be enabled
     */
    rconsave.broad = 1;

    /*
     * Reset the adaptor, but don't enable yet.  We'll receive 
     * -resetAndEnable:YES as a side effect of calling
     * -attachToNetworkWithAddress:
     */
    [self resetAndEnable:NO];	
    
    IOLog("SMC16 at port %x irq %d\n", base, irq);
    IOLog("SMC16 using %d bytes of memory at 0x%x\n", memtotal, membase);
	    
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:32];
    
    network = [super attachToNetworkWithAddress:myAddress];
    return self;		
}

- free
{
    [transmitQueue free];
    
    return [super free];
}

- (IOReturn)enableAllInterrupts
{
    unmaskInterrupts(base);

    setIRQ(irq, YES, base);
    
    return [super enableAllInterrupts];
}

- (void)disableAllInterrupts
{
    setIRQ(irq, NO, base);
    
    [super disableAllInterrupts];
}

- (BOOL)resetAndEnable:(BOOL)enable
{
    [self disableAllInterrupts];
   
    transmitActive = NO;
    
    [self _initializeHardware];
    
    getStationAddress(&myAddress, base);
    
    [self _initializeSoftware];
    
    if (enable && [self enableAllInterrupts] != IO_R_SUCCESS) {
	[self setRunning:NO];
    	return NO;
    }
	
    [self setRunning:enable];
    return YES;
}

- (void)timeoutOccurred
{
    netbuf_t	pkt = NULL;
    
    if ([self isRunning]) {
    	if ([self resetAndEnable:YES]) {

	    if (pkt = [transmitQueue dequeue])
		[self transmit:pkt];
	}
    }
    /*
     * Value of [self isRunning] may have been modified by
     * resetAndEnable:
     */
    if (![self isRunning]) {	
	/*
	 * Free any packets in the queue since we're not running.
	 */
    	if ([transmitQueue count]) {
	    transmitActive = NO;
	    while (pkt = [transmitQueue dequeue])
		nb_free(pkt);
	}
    }
}

/* 
 * Called by our IOThread when it receives a message signifying
 * an interrupt.  We check the istat register and vector off
 * to the appropriate handler routines.
 */
- (void)interruptOccurred
{
    nic_istat_reg_t	istat_reg;
    
    do	{
	istat_reg = get_istat_reg(base);
	put_istat_reg(istat_reg, base);
	
	if (istat_reg.ovw)
	    [self _receiveOverwriteOccurred];
	
	if (istat_reg.prx)
	    [self _receiveInterruptOccurred];
		    
	if (istat_reg.ptx || istat_reg.txe)
	    [self _transmitInterruptOccurred];
	    
    } while (istat_reg.ovw || istat_reg.prx || istat_reg.ptx || istat_reg.txe);
}

 
/*
 * Enable promiscuous mode (invoked by superclass).
 */
- (BOOL)enablePromiscuousMode
{
    int 	old_page = sel_reg_page(REG_PAGE0, base);

    rconsave.prom = 1;
    put_rcon_reg(rconsave, base);
    sel_reg_page(old_page, base);

    return YES;
}

/*
 * Disable promiscuous mode (invoked by superclass).
 */
- (void)disablePromiscuousMode
{
   int 	old_page = sel_reg_page(REG_PAGE0, base);

    rconsave.prom = 0;
    put_rcon_reg(rconsave, base);
    sel_reg_page(old_page, base);

}


- (BOOL)enableMulticastMode
{
    int 	old_page = sel_reg_page(REG_PAGE0, base);

    rconsave.group = 1;
    put_rcon_reg(rconsave, base);
    sel_reg_page(old_page, base);

    return YES;
}

- (void)disableMulticastMode
{
    int 	old_page = sel_reg_page(REG_PAGE0, base);

    rconsave.group = 0;
    put_rcon_reg(rconsave, base);
    sel_reg_page(old_page, base);

}

- (void)transmit:(netbuf_t)pkt
{
    int			pkt_len;

    /*
     * If we're already transmitting, just queue up the packet.
     */
    if (transmitActive)
    	[transmitQueue enqueue:pkt];
    else {
 	
	/*
	 * We execute a softare loopback since this adaptor doesn't
	 * deal with this in hardware.
	 */
	[self performLoopback:pkt];	 
    	
	/*
	 * Copy the packet into our transmit buffer, then free it.
	 */
	pkt_len = nb_size(pkt);
	set_mode(SIXTEEN_BIT, membase, base);
	IOCopyMemory(
		nb_map(pkt),
		(void *)nic_page_addr(tstart,membase),
		pkt_len,
		sizeof(short));

	set_mode(EIGHT_BIT, membase, base);
	
	/*
	 * Once the packet is copied out to the adaptor's onboard RAM,
	 * always free the packet.  DON'T SAVE A REFERENCE FOR 
	 * RETRANSMISSION PURPOSES.  Retransmission should be handled
	 * at the higher levels.  
	 */
	nb_free(pkt);
	
	/*
	 * Setup up and initiate the transmit operation
	 */
	put_tcnt_reg(pkt_len, base);
	put_tstart_reg(tstart, base);
	startTransmit(base);
	
	/*
	 * Start a timer whose expiration will call -timeoutOccurred, then
	 * set the transmitActive flag so we don't step on this operation.
	 */
	[self setRelativeTimeout:3000];
	transmitActive = YES;
    }
}


@end

/*
 * Private Functions
 */

static BOOL
checksumLAR(
    IOEISAPortAddress	base
)
{
    IOEISAPortAddress	offset;
    unsigned char	sum = 0;
    
    for (offset = BIC_LAR_OFF; offset <= BIC_LAR_CKSUM_OFF; offset++)
    	sum += inb(base + SMC16_BIC_OFF + offset);
	
    return (sum == 0xff);
}

static void
getStationAddress(
    enet_addr_t		*ea,
    IOEISAPortAddress	base
)
{
    int			i;
    unsigned char	*enaddr = (unsigned char *)ea;
    
    for (i = 0; i < sizeof (*ea); i++)
    	*(enaddr + i) = inb(base + SMC16_BIC_OFF + BIC_LAR_OFF + i);
}

static void
setStationAddress(
    enet_addr_t		*ea,
    IOEISAPortAddress	base
)
{
    int			i, old_page;
    unsigned char	*enaddr = (unsigned char *)ea;
    
    old_page = sel_reg_page(REG_PAGE1, base);
    
    for (i = 0; i < sizeof (*ea); i++)
    	outb(base + SMC16_NIC_OFF + NIC_STA_REG_OFF + i, *(enaddr + i));
	
    (void)sel_reg_page(old_page, base);
}

static BOOL
checkBoardRev(
    IOEISAPortAddress	base
)
{
    unsigned int	bid;
    
    bid = get_bid(base);
    
    if (SMC16_REV(bid) < 2)
    	return NO;
	
    return YES;
}

static void
resetNIC(
    IOEISAPortAddress	base
)
{
    bic_msr_t		msr = { 0 };
    nic_istat_reg_t	istat_reg;

    /*
     * Perform HW Reset of NIC	
     */	
    msr.rst = 1;	put_msr(msr, base);
    IODelay(500);
    msr.rst = 0;	put_msr(msr, base);

    /*
     * Wait for NIC to enter stopped state	
     */	
    do {
	istat_reg = get_istat_reg(base);
    } while (istat_reg.rst == 0);
}

static SMC16_len_t
setupRAM(
    vm_offset_t		addr,
    vm_size_t		size,
    IOEISAPortAddress	base
)
{
    SMC16_len_t		total;
    SMC16_off_t		block_addr;
    bic_laar_t		laar;
    bic_msr_t		msr;
    bic_icr_t		icr;

    union {
	struct {
	    unsigned int		:13,
			    madr	:6,
			    ladr	:5,
			    		:8;
	} bic_addr;
	struct {
	   unsigned int			:16,
	   		    block	:8,
			    		:8;
	} nic_addr;
	unsigned int	address;
    } _mconv;


    if (sixteen_bit_mode == YES)	{
    	icr = get_icr(base);
    	total = (icr.msz ? 16 : 64) * 1024;

    	if (total > 16 * 1024)	{
	    total = 16 * 1024;
        }
    	total = 16 * 1024;		// always set to this value
    } else {
    	total = 8 * 1024;
    }
	
    if (total > size)
	total = size;

#ifdef DEBUG
    IOLog("SMC16: using %d bytes of onboard memory\n",total);
#endif DEBUG

    _mconv.address = addr;

    laar = get_laar(base);
    if (sixteen_bit_mode == YES)	{
    	laar.zws16 = TRUE;
    	laar.l16en = TRUE;
    }
    
    laar.ladr = _mconv.bic_addr.ladr;
    put_laar(laar, base);
    
    msr = get_msr(base);
    msr.madr = _mconv.bic_addr.madr;
    msr.menb = TRUE;
    put_msr(msr, base);
 
    block_addr = _mconv.nic_addr.block;
    put_block_reg(block_addr, base);

    return (total);
}
	
static void
startNIC(
    IOEISAPortAddress	base,
    nic_rcon_reg_t	rcon_reg
)
{
    nic_cmd_reg_t	cmd_reg = { 0 };
    nic_enh_reg_t	enh_reg = { 0 };
    nic_dcon_reg_t	dcon_reg = { 0 };
    nic_tcon_reg_t	tcon_reg = { 0 };
    nic_istat_reg_t	istat_reg;

    enh_reg.slot = NIC_SLOT_512_BIT;
    enh_reg.wait = 0;
    put_enh_reg(enh_reg, base);

    dcon_reg.bsize = NIC_DMA_BURST_8b;
    if (sixteen_bit_mode)	{
    	dcon_reg.bus16 = TRUE;
    }
    put_dcon_reg(dcon_reg, base);
    
    put_tcon_reg(tcon_reg, base);
    
    istat_reg = get_istat_reg(base);
    put_istat_reg(istat_reg, base);
    
    cmd_reg.sta = 1;
    put_cmd_reg(cmd_reg, base);
    
    put_rcon_reg(rcon_reg, base);
}

static void
unmaskInterrupts(
    IOEISAPortAddress	base
)
{
    nic_imask_reg_t	imask_reg = { 0 };

    /*
     * Receive conditions
     */	
    imask_reg.prxe = imask_reg.rxee = imask_reg.ovwe = TRUE;
    
    /*
     * Transmit conditions
     */	
    imask_reg.ptxe = imask_reg.txee = TRUE;
    
    put_imask_reg(imask_reg, base);
}

static SMC16_off_t
getCurrentBuffer(
    IOEISAPortAddress	base
)
{
    SMC16_off_t		curr;
    int			old_page;
    
    old_page = sel_reg_page(REG_PAGE1, base);
    curr = get_curr_reg(base);
    if (old_page != REG_PAGE1)
    	sel_reg_page(old_page, base);
    
    return (curr);
}

static void
startTransmit(
    IOEISAPortAddress	base
)
{
    nic_cmd_reg_t	cmd_reg = { 0 };
    
    cmd_reg.txp = 1;
    cmd_reg.sta = 1;
    put_cmd_reg(cmd_reg, base);
}

static void
setIRQ(
    int			irq,
    BOOL		enable,
    IOEISAPortAddress	base
)
{
    bic_irr_t		irr;
    bic_icr_t		icr;
    static char		_irx_map[16] = {	-1,
						-1,
						-1,
						BIC_IRX_3,
						BIC_IRX_4,
						BIC_IRX_5,
						-1,
						BIC_IRX_7,
						-1,
						BIC_IRX_9,
						BIC_IRX_10,
						BIC_IRX_11,
						-1,
						-1,
						-1,
						BIC_IRX_15 };
    static char		_ir2_map[16] = {	-1,
						-1,
						-1,
						ICR_IR2_3,
						ICR_IR2_4,
						ICR_IR2_5,
						-1,
						ICR_IR2_7,
						-1,
						ICR_IR2_9,
						ICR_IR2_10,
						ICR_IR2_11,
						-1,
						-1,
						-1,
						ICR_IR2_15 };

    irr = get_irr(base);
    irr.irx = _irx_map[irq]; 
    irr.ien = FALSE;
    put_irr(irr, base);

    icr = get_icr(base);
    icr.ir2 = _ir2_map[irq];
    put_icr(icr, base);
    
    irr.ien = enable;
    put_irr(irr, base);	
}

