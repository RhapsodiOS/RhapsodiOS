/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * Driver class for SMC EtherCard Plus Elite16 Ultra adaptors.
 *
 * HISTORY
 *
 * Mar 1998
 *	Created from SMC16 driver.
 */

#define MACH_USER_API	1

#import <driverkit/generalFuncs.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/align.h>

#import "SMCElite16Ultra.h"
#import "SMCUltraIOInline.h"
#import "SMCUltraPrivate.h"

#import <kernserv/kern_server_types.h>
#import <kernserv/prototypes.h>

/* Forward declarations of hardware functions */
static void resetNIC(IOEISAPortAddress base);
static void setIRQ(int irq, BOOL enable, IOEISAPortAddress base);
static SMCUltra_len_t setupRAM(vm_offset_t membase, vm_size_t memsize, IOEISAPortAddress base);
static BOOL readEnetAddr(enet_addr_t *addr, IOEISAPortAddress base);

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
}


@implementation SMCElite16Ultra

/*
 * Private Instance Methods
 */

/*
 * _memAvail
 * Returns the amount of onboard memory not currently in use.
 * Never returns less than zero.
 */
- (SMCUltra_len_t)_memAvail
{
    int		available;

    available = (memtotal - memused);

    return ((SMCUltra_len_t) ((available < 0)? 0: available));
}

/*
 * _memRegion
 * Returns the next available NIC_PAGE_SIZE chunk of onboard memory.
 */
- (SMCUltra_off_t)_memRegion:(SMCUltra_len_t)length
{
    if ([self _memAvail] < length)
    	IOPanic("SMCUltra: onboard memory exhausted");

    return ((SMCUltra_off_t) (memused / NIC_PAGE_SIZE));
}

/*
 * _memAlloc
 * Allocates onboard memory in chunks of NIC_PAGE_SIZE
 */
- (SMCUltra_off_t)_memAlloc:(SMCUltra_len_t)length
{
    SMCUltra_off_t	region;

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
    SMCUltra_len_t		avail = [self _memAvail];

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
 * Initializes the instance variables that are not maintained by the hardware.
 */
- (void)_initializeSoftware
{
    nic_rcon_reg_t	rcon_reg;
    nic_tcon_reg_t	tcon_reg;
    nic_dcon_reg_t	dcon_reg;
    nic_cmd_reg_t	cmd_reg;

    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:128];

    [self _receiveInitialize];
    [self _transmitInitialize];

    put_tstart_reg(tstart, base);

    /*
     * Configure receive mode: Accept broadcasts, but not multicasts,
     * promiscuous, or monitor.
     */
    rcon_reg.sep = FALSE;
    rcon_reg.runts = FALSE;
    rcon_reg.broad = TRUE;
    rcon_reg.group = FALSE;
    rcon_reg.prom = FALSE;
    rcon_reg.mon = FALSE;

    rconsave = rcon_reg;

    /*
     * Configure transmit mode: Normal operation (no loopback)
     */
    tcon_reg.crcn = FALSE;
    tcon_reg.lb = NIC_XMT_LOOPB_NONE;

    (void)sel_reg_page(REG_PAGE2, base);
	put_rcon_reg(rcon_reg, base);
	put_tcon_reg(tcon_reg, base);
    (void)sel_reg_page(REG_PAGE0, base);

    /*
     * Configure data mode: 16-bit bus, burst DMA
     */
    dcon_reg.bus16 = TRUE;
    dcon_reg.bsize = NIC_DMA_BURST_8b;

    (void)sel_reg_page(REG_PAGE2, base);
	put_dcon_reg(dcon_reg, base);
    (void)sel_reg_page(REG_PAGE0, base);

    /*
     * Start the NIC
     */
    cmd_reg = get_cmd_reg(base);
    cmd_reg.stp = FALSE;
    cmd_reg.sta = TRUE;
    put_cmd_reg(cmd_reg, base);

    transmitActive = NO;
}

/*
 * _receivePacket
 * Called when a packet has been received
 */
- (void)_receivePacket
{
    SMCUltra_off_t	curr, bound, next;
    nic_recv_hdr_t	*hdr;
    netbuf_t		pkt;
    unsigned int	len;
    vm_offset_t		addr;
    unsigned char	*data;

    /*
     * Get current page pointer
     */
    (void)sel_reg_page(REG_PAGE1, base);
    curr = inb(base + SMCULTRA_NIC_OFF + NIC_CURR_REG_OFF);
    (void)sel_reg_page(REG_PAGE0, base);

    bound = rnext;

    while (bound != curr) {
        /*
         * Read packet header from ring buffer
         */
        addr = nic_page_addr(bound, membase);
        set_mode(SIXTEEN_BIT, addr, base);

        hdr = (nic_recv_hdr_t *)addr;
        next = hdr->next;
        len = hdr->len - 4;  /* Remove CRC */

        if (len > ETHERMAXPACKET || len < ETHERMINPACKET) {
            IOLog("SMCUltra: Bad packet length %d\n", len);
            break;
        }

        /*
         * Allocate netbuf and copy packet data
         */
        pkt = nb_alloc(len);
        if (pkt) {
            data = nb_map(pkt);
            bcopy(hdr->data, data, len);
            nb_shrink_top(pkt, len);

            /*
             * Pass packet up to network layer
             */
            [network handleInputPacket:pkt extra:0];
        }

        /*
         * Update boundary pointer
         */
        bound = next;
        put_bound_reg((bound == rstart) ? (rstop - 1) : (bound - 1), base);
    }

    rnext = curr;
    set_mode(EIGHT_BIT, 0, base);
}

/*
 * _transmitPacket
 * Transmit a packet
 */
- (void)_transmitPacket:(netbuf_t)pkt
{
    unsigned int	len;
    unsigned char	*data;
    vm_offset_t		addr;
    nic_cmd_reg_t	cmd_reg;

    transmitActive = YES;

    len = nb_size(pkt);
    data = nb_map(pkt);

    /* Pad short packets */
    if (len < ETHERMINPACKET)
        len = ETHERMINPACKET;

    /*
     * Copy packet to transmit buffer
     */
    addr = nic_page_addr(tstart, membase);
    set_mode(SIXTEEN_BIT, addr, base);
    bcopy(data, (void *)addr, nb_size(pkt));
    set_mode(EIGHT_BIT, 0, base);

    /*
     * Set transmit byte count
     */
    outb(base + SMCULTRA_NIC_OFF + NIC_TCNTL_REG_OFF, len & 0xFF);
    outb(base + SMCULTRA_NIC_OFF + NIC_TCNTH_REG_OFF, (len >> 8) & 0xFF);

    /*
     * Start transmission
     */
    cmd_reg = get_cmd_reg(base);
    cmd_reg.txp = TRUE;
    put_cmd_reg(cmd_reg, base);

    nb_free(pkt);
}

/*
 * _transmitCompleted
 * Called when a transmit completes
 */
- (void)_transmitCompleted
{
    netbuf_t	pkt;

    transmitActive = NO;

    /*
     * Check for queued packets
     */
    if ((pkt = [transmitQueue dequeue]) != NULL) {
        [self _transmitPacket:pkt];
    }
}

/*
 * _receiveOverwriteOccurred
 * Handle receive ring buffer overflow
 */
- (void)_receiveOverwriteOccurred
{
    nic_cmd_reg_t	cmd_reg;

    IOLog("SMCUltra: Receive overflow\n");

    /*
     * Stop the NIC
     */
    cmd_reg = get_cmd_reg(base);
    cmd_reg.stp = TRUE;
    cmd_reg.sta = FALSE;
    put_cmd_reg(cmd_reg, base);

    IODelay(2000);

    /*
     * Restart
     */
    cmd_reg.stp = FALSE;
    cmd_reg.sta = TRUE;
    put_cmd_reg(cmd_reg, base);
}

/*
 * _handleError
 * Handle various error conditions
 */
- (void)_handleError
{
    nic_istat_reg_t	istat;

    istat = get_istat_reg(base);

    if (istat.rxe)
        IOLog("SMCUltra: Receive error\n");
    if (istat.txe)
        IOLog("SMCUltra: Transmit error\n");

    /* Clear error status */
    put_istat_reg(istat, base);
}

/*
 * Public Methods
 */

/*
 * Probe for the adapter
 */
+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    IOEISAPortAddress	portBase;
    IORange		*portRanges;
    bic_msr_t		msr;
    unsigned char	boardID;

    /* Get I/O port base */
    if ([devDesc numPortRanges] < 1)
        return NO;

    portRanges = [devDesc portRangeList];
    portBase = portRanges[0].start;

    /* Try to access the card */
    msr = get_msr(portBase);

    /* Reset the NIC */
    msr.rst = 1;
    put_msr(msr, portBase);
    IODelay(2000);
    msr.rst = 0;
    put_msr(msr, portBase);
    IODelay(2000);

    /* Read board ID */
    boardID = inb(portBase + SMCULTRA_BIC_OFF + BIC_ID_OFF);
    if (SMCULTRA_REV(boardID) == 0 || SMCULTRA_REV(boardID) == 0x0F)
        return NO;

    IOLog("SMC Elite16 Ultra: Found adapter at 0x%x (ID=0x%x)\n", portBase, boardID);

    return YES;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IORange		*portRanges, *memRanges;
    enet_addr_t		addr;

    if ([super initFromDeviceDescription:devDesc] == nil)
        return nil;

    /* Get I/O port base */
    portRanges = [devDesc portRangeList];
    base = portRanges[0].start;

    /* Get interrupt */
    irq = [devDesc interrupt];

    /* Get memory range */
    if ([devDesc numMemoryRanges] > 0) {
        memRanges = [devDesc memoryRangeList];
        membase = memRanges[0].start;
        memsize = memRanges[0].size;
    } else {
        membase = 0xD0000;
        memsize = 0x4000;
    }

    /* Initialize hardware */
    [self _initializeHardware];

    /* Get ethernet address from card */
    if (!readEnetAddr(&addr, base)) {
        IOLog("SMCUltra: Failed to read ethernet address\n");
        return [self free];
    }

    /* Copy to our instance variable */
    bcopy(&addr, &myAddress, sizeof(enet_addr_t));

    /* Set our address */
    [self setEnetAddress:&addr];

    /* Initialize software structures */
    [self _initializeSoftware];

    /* Register with network */
    network = [self attachToNetworkWithAddress:&addr];
    if (network == nil) {
        IOLog("SMCUltra: Failed to attach to network\n");
        return [self free];
    }

    /* Enable interrupts */
    [self enableAllInterrupts];

    IOLog("SMCUltra: Initialized at 0x%x IRQ %d, Address %02x:%02x:%02x:%02x:%02x:%02x\n",
          base, irq,
          addr.ea_byte[0], addr.ea_byte[1], addr.ea_byte[2],
          addr.ea_byte[3], addr.ea_byte[4], addr.ea_byte[5]);

    return self;
}

/*
 * Free resources
 */
- free
{
    [self disableAllInterrupts];
    [self resetAndEnable:NO];

    if (transmitQueue)
        [transmitQueue free];

    return [super free];
}

/*
 * Enable interrupts
 */
- (IOReturn)enableAllInterrupts
{
    nic_imask_reg_t	imask_reg;

    /* Enable NIC interrupts */
    imask_reg.prxe = TRUE;
    imask_reg.ptxe = TRUE;
    imask_reg.rxee = TRUE;
    imask_reg.txee = TRUE;
    imask_reg.ovwe = TRUE;
    imask_reg.cnte = FALSE;

    (void)sel_reg_page(REG_PAGE0, base);
    outb(base + SMCULTRA_NIC_OFF + NIC_IMASK_REG_OFF, *(unsigned char *)&imask_reg);

    /* Enable IRQ */
    setIRQ(irq, YES, base);

    return IO_R_SUCCESS;
}

/*
 * Disable interrupts
 */
- (void)disableAllInterrupts
{
    nic_imask_reg_t	imask_reg;

    /* Disable all NIC interrupts */
    *(unsigned char *)&imask_reg = 0;

    (void)sel_reg_page(REG_PAGE0, base);
    outb(base + SMCULTRA_NIC_OFF + NIC_IMASK_REG_OFF, 0);

    /* Disable IRQ */
    setIRQ(irq, NO, base);
}

/*
 * Reset and enable/disable the card
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    nic_cmd_reg_t	cmd_reg;

    if (!enable) {
        cmd_reg = get_cmd_reg(base);
        cmd_reg.stp = TRUE;
        cmd_reg.sta = FALSE;
        put_cmd_reg(cmd_reg, base);
        [self setRunning:NO];
        return YES;
    }

    resetNIC(base);
    [self _initializeSoftware];

    /* Set receive mode */
    put_rcon_reg(rconsave, base);

    [self setRunning:YES];
    return YES;
}

/*
 * Handle timeouts
 */
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
 * Handle interrupts
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
	    [self _receivePacket];

	if (istat_reg.ptx)
	    [self _transmitCompleted];

	if (istat_reg.rxe || istat_reg.txe)
	    [self _handleError];

    } while (istat_reg.prx || istat_reg.ptx || istat_reg.rxe ||
             istat_reg.txe || istat_reg.ovw);
}

/*
 * Enable promiscuous mode
 */
- (BOOL)enablePromiscuousMode
{
    rconsave.prom = TRUE;
    put_rcon_reg(rconsave, base);
    return YES;
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    rconsave.prom = FALSE;
    put_rcon_reg(rconsave, base);
}

/*
 * Enable multicast mode
 */
- (BOOL)enableMulticastMode
{
    rconsave.group = TRUE;
    put_rcon_reg(rconsave, base);
    return YES;
}

/*
 * Disable multicast mode
 */
- (void)disableMulticastMode
{
    rconsave.group = FALSE;
    put_rcon_reg(rconsave, base);
}

/*
 * Transmit a packet
 */
- (void)transmit:(netbuf_t)pkt
{
    if (!pkt)
	return;

    if (transmitActive || ![self isRunning]) {
        /* Queue the packet */
        [transmitQueue enqueue:pkt];
    } else {
        /* Transmit immediately */
        [self _transmitPacket:pkt];
    }
}

@end

/*
 * Hardware utility functions
 */
static void
resetNIC(IOEISAPortAddress base)
{
    bic_msr_t		msr;
    nic_cmd_reg_t	cmd_reg;

    /* Hardware reset */
    msr = get_msr(base);
    msr.rst = TRUE;
    put_msr(msr, base);
    IODelay(2000);
    msr.rst = FALSE;
    put_msr(msr, base);
    IODelay(2000);

    /* Stop the NIC */
    cmd_reg = get_cmd_reg(base);
    cmd_reg.stp = TRUE;
    cmd_reg.sta = FALSE;
    put_cmd_reg(cmd_reg, base);

    IODelay(2000);
}

static void
setIRQ(int irq, BOOL enable, IOEISAPortAddress base)
{
    bic_icr_t	icr;
    bic_irr_t	irr;

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

static SMCUltra_len_t
setupRAM(vm_offset_t membase, vm_size_t memsize, IOEISAPortAddress base)
{
    bic_msr_t	msr;
    bic_icr_t	icr;
    union {
	struct {
	    unsigned int		:13,
			    madr	:6,
			    ladr	:5,
			    		:8;
	} bic_addr;
	unsigned int	address;
    } _mconv;

    /* Enable memory */
    msr = get_msr(base);
    msr.menb = TRUE;

    _mconv.address = membase;
    msr.madr = _mconv.bic_addr.madr;
    put_msr(msr, base);

    /* Configure for 16-bit mode if enabled */
    icr = get_icr(base);
    icr.bus16 = (sixteen_bit_mode ? TRUE : FALSE);
    icr.msz = FALSE;  /* 16K */
    put_icr(icr, base);

    return (SMCUltra_len_t)memsize;
}

static BOOL
readEnetAddr(enet_addr_t *addr, IOEISAPortAddress base)
{
    int		i;
    unsigned char	cksum = 0xFF;

    /* Read ethernet address from EEPROM */
    for (i = 0; i < NUM_EN_ADDR_BYTES; i++) {
        addr->ea_byte[i] = inb(base + SMCULTRA_BIC_OFF + BIC_LAR_OFF + i);
        cksum ^= addr->ea_byte[i];
    }

    /* Verify checksum */
    cksum ^= inb(base + SMCULTRA_BIC_OFF + BIC_LAR_CKSUM_OFF);

    if (cksum != 0x00) {
        IOLog("SMCUltra: Ethernet address checksum error\n");
        return NO;
    }

    return YES;
}
