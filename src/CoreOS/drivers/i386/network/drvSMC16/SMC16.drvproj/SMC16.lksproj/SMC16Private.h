/*
 * Copyright (c) 1992-1996 NeXT Software, Inc.
 *
 * Private declarations for SMC16 class.
 *
 * HISTORY
 *
 * 29 January 1993 
 *	Created.
 */

static BOOL
    checksumLAR(
	IOEISAPortAddress	base);

static BOOL
    checkBoardRev(
    	IOEISAPortAddress	base);

static void
    resetNIC(
    	IOEISAPortAddress	base);
	
static void
    startNIC(
	IOEISAPortAddress	base,
    	nic_rcon_reg_t		rcon_reg);

static SMC16_len_t
    setupRAM(
    	vm_offset_t		address,
	vm_size_t		size,
    	IOEISAPortAddress	base);

static void
    getStationAddress(
    	enet_addr_t		*ea,
	IOEISAPortAddress	base);

static void
    setStationAddress(
    	enet_addr_t		*ea,
	IOEISAPortAddress	base);

static void
    setIRQ(
    	int			irq,
	BOOL			enable,
	IOEISAPortAddress	base);

static void
    unmaskInterrupts(
    	IOEISAPortAddress	base);

static SMC16_off_t
    getCurrentBuffer(
    	IOEISAPortAddress	base);

static void
    startTransmit(
    	IOEISAPortAddress	base);

