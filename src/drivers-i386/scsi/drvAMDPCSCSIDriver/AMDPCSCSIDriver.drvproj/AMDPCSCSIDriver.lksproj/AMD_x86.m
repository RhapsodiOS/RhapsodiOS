/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_x86.m - architecture-specific methods for AMD SCSI driver
 *
 * HISTORY
 * 21 Oct 94    Doug Mitchell at NeXT
 *      Created. 
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <kernserv/prototypes.h>
#import <mach/kern_return.h>
#import "AMD_x86.h"
#import "pciconf.h"
#import "AMD_Regs.h"
#import "AMD_Chip.h"
#import "bringup.h"
#import "AMD_ddm.h"
#import "configKeys.h"
#import <mach/mach_interface.h>

#define TEST_DEBUG	0	/* low level I/O test before registerDevice */
#define TEST_IPL_BUG	0	/* test IPL bug */

#if	TEST_DEBUG
static void testDebug(id driver);
#endif	TEST_DEBUG

#if	TEST_IPL_BUG
static void testIplBug();
#endif	TEST_IPL_BUG

#ifdef	DEBUG
AMD_SCSI *amd_g;
#endif	DEBUG

static int _atoi(const char *ip)
{
	unsigned rtn = 0;
	
	while(*ip) {
		if((*ip < '0') || (*ip > '9')) {
			return rtn;	
		}
		rtn *= 10;
		rtn += (*ip - '0');
		ip++;
	}
	return rtn;
}

/*
 * Get I/O port range and IRQ from PCI config space. Set appropriate
 * values in deviceDescription. Returns base address in *baseAddr.
 * Returns YES if successful, else NO.
 */
static BOOL parseConfigSpace(
	id deviceDescription,
	const char *title,
	unsigned regSize,		// in bytes
	IOEISAPortAddress *baseAddr)	// RETURNED
{
	IOPCIConfigSpace	configSpace;
	IORange 		portRange;
	unsigned		*basePtr = 0;
	int			irq;
	int			i;
	BOOL			foundBase = NO;
	IOReturn		irtn;
	
	/*
	 * First get our configSpace register set.
	 */
	bzero(&configSpace, sizeof(IOPCIConfigSpace));
	if(irtn = [IODirectDevice getPCIConfigSpace:&configSpace
			withDeviceDescription:deviceDescription]) {
		IOLog("%s: Can\'t get configSpace (%s); ABORTING\n", 
			title, [IODirectDevice stringFromReturn:irtn]);
		    return NO;
	}
	basePtr = configSpace.BaseAddress;
	irq     = configSpace.InterruptLine;
	if((basePtr[0] == 0) || (irq == 0)) {
		IOLog("%s: Bogus config info (IRQ %d, Base 0x%x)\n",
			title, irq, (unsigned)basePtr);
		    return NO;
	}
	
	/*
	 * Scan all 6 base address registers, make sure there is exactly one
	 * I/O address.
	 */
	for(i=0; i<PCI_NUM_BASE_ADDRESS; i++) {
	    if(basePtr[i] & PCI_BASE_IO_BIT) {
		if(foundBase) {
		    IOLog("%s: Multiple I/O Port Bases Found\n", title);
		    return NO;
		}
		foundBase = YES;
		portRange.start = PCI_BASE_IO(basePtr[i]);
	    }
	}
	if(!foundBase) {
	    	IOLog("%s: No I/O Port Base Found\n", title);
		return NO;
	}
	portRange.size = regSize;
	*baseAddr = portRange.start;
	ddm_init("irq %d base 0x%x\n", irq, *baseAddr, 3,4,5);
	
	/*
	 * OK, retweeze our device description. 
	 */
	irtn = [deviceDescription setInterruptList:&irq num:1];
	if(irtn) {
		IOLog("%s: Can\'t set interruptList to IRQ %d (%s)\n", 
			title, irq, [IODirectDevice stringFromReturn:irtn]);
		return NO;
	}
	irtn = [deviceDescription setPortRangeList:&portRange num:1];
	if(irtn) {
		IOLog("%s: Can\'t set portRangeList to port 0x%x (%s)\n", 
			title, portRange.start, 
			[IODirectDevice stringFromReturn:irtn]);
		return NO;
	}
	return YES;
}

/*
 * Obtain a YES/NO type parameter from the config table.
 */
static int getConfigParam(
	id	configTable,
	const char *paramName)
{
	const char *value;
	int rtn = 0;		// default if not present in table
	
	value = [configTable valueForStringKey:paramName];
	if(value) {
		if(strcmp(value, "YES") == 0) {
			rtn = 1;
		}
		[configTable freeString:value];
	}
	return rtn;
}

@implementation AMD_SCSI(Architecture)

- archInit : deviceDescription
{
	id			configTable;
	const char		*value = NULL;
	kern_return_t		krtn;
	vm_offset_t		startPage, endPage;
	unsigned		ival;
	IOReturn		irtn;
	unsigned char 		lun;
	
#if	TEST_IPL_BUG
	testIplBug();
#endif	TEST_IPL_BUG

	ddm_init("AMD archInit\n", 
		1,2,3,4,5);
	scState = SCS_UNINITIALIZED;
		
	/*
	 * Obtain I/O port base, busType dependent.
	 */
	levelIRQ = NO;
	configTable = [deviceDescription configTable];
	value = [configTable valueForStringKey:"Bus Type"];
	if(value == NULL) {
		IOLog("AMD53C974: No Bus Type in config Table\n");
		goto abort;
	}
	if(strcmp(value, "PCI") == 0) {
		busType = BT_PCI;
		if(parseConfigSpace(deviceDescription,
				"AMD53C974",
				AMD_PCI_REGISTER_SPACE,
				&ioBase) == NO) {
			[configTable freeString:value];
			goto abort;
		}
		ioBase += AMD_PCI_REGISTER_OFFSET;
		if(irtn = [deviceDescription getPCIdevice : &deviceNumber
					    function : &functionNumber
						bus : &busNumber]) {
			IOLog("AMD53C974: Can't find device using "
				"getPCIdevice (%s)\n",
				[self stringFromReturn:irtn]);
			goto abort;
		}
		levelIRQ = YES;
		IOLog("AMD53C974: found at bus %d device %d function %d "
			"irq %d\n",
			busNumber, deviceNumber, functionNumber,
			[deviceDescription interrupt]);
	}
	else {
		IOLog("AMD53C974: Bad Bus Type (%s) in config table\n",
			value);
		[configTable freeString:value];
		goto abort;
	}	
	[configTable freeString:value];
	
	if (![self probeChip]) {
		IOLog("AMD53C974 Host Adaptor Not found at Port 0x%x\n",
			ioBase);
		goto abort;
	}
	
	#if	DEBUG
	amd_g = self;
	#endif	DEBUG
	
	if ([super initFromDeviceDescription:deviceDescription] == nil) {
		goto abort;
	}
	ioThreadRunning = 1;
	
	/*
	 * Initialize local variables. Note that activeArray and 
	 * perTarget arrays are zeroed by objc runtime.
	 */
	queue_init(&disconnectQ);
	queue_init(&commandQ);
	queue_init(&pendingQ);
	commandLock = [[NXLock alloc] init];
	activeCmd = NULL;
	[self resetStats];
 	nextQueueTag = QUEUE_TAG_NONTAGGED + 1;
	
	/*
	 * Allocate some physically contiguous memory for the Memory 
	 * Descriptor List.
	 */
	mdlFree = IOMalloc(MDL_SIZE * 2 * sizeof(vm_address_t));
	startPage = trunc_page(mdlFree);
	endPage = trunc_page(((vm_offset_t)&mdlFree[MDL_SIZE]) - 1);
	if(startPage != endPage) {
		mdl = mdlFree + MDL_SIZE;
	}
	else {
		mdl = mdlFree;
	}
	ddm_init("&mdl[0] = 0x%x &mdl[%d] = 0x%x\n", mdl, MDL_SIZE - 1,
		&mdl[MDL_SIZE - 1], 4,5);
	irtn = IOPhysicalFromVirtual(IOVmTaskSelf(),
			(vm_offset_t)mdl,
			&mdlPhys);
	if(irtn) {
		IOLog("AMD53C974: can't get physical address of MDL\n");
		goto abort;
	}
	
	/*
	 * get tagged command queueing, sync mode, fast mode enables from
	 * configTable.
	 */
	cmdQueueEnable = getConfigParam(configTable, CMD_QUEUE_ENABLE);
	syncModeEnable = getConfigParam(configTable, SYNC_ENABLE);
	fastModeEnable = getConfigParam(configTable, FAST_ENABLE);
	extendTiming   = getConfigParam(configTable, EXTENDED_TIMING);

	/*
	 * Get clock rate, in MHz.
	 */
	scsiClockRate = AMD_DEFAULT_CLOCK;
	value = [configTable valueForStringKey:SCSI_CLOCK_RATE];
	if(value) {
		ival = _atoi(value);
		if(ival) {
			scsiClockRate = ival;
			ddm_init("SCSI Clock Rate = %d MHz\n", 
				ival, 2,3,4,5);
		}
		[configTable freeString:value];
	}
	
	autoSenseEnable = AUTO_SENSE_ENABLE;	// from bringup.h
		
	/*
	 * Get internal version of interruptPort; set the port queue 
	 * length to the maximum size. 
	 */
	interruptPortKern = IOConvertPort([self interruptPort],
		IO_KernelIOTask,
		IO_Kernel);		
	krtn = port_set_backlog(task_self(), [self interruptPort], 
		PORT_BACKLOG_MAX);
	if(krtn) {
		IOLog("%s: error %d on port_set_backlog()\n",
			[self name], krtn);
		/* Oh well... */
	}
	
	/*
	 * Initialize the chip and reset the bus.
	 */
	if([self hwReset:NULL]) {
		goto abort;
	}
	
	/*
	 * Reserve our devices. hostId is init'd at chip level in hwReset.
	 */
	for(lun=0; lun<SCSI_NLUNS; lun++) {
		[self reserveTarget:hostId 
			lun:lun
			forOwner:self];
	}
	
	/*
	 * OK, we're ready to roll.
	 */
	
	#if 	TEST_DEBUG
	
	/*
	 * Before we call registerDevice and bring all kinds of uncontrolled
	 * I/O...
	 */
	testDebug(self);
	#endif	TEST_DEBUG

	[self registerDevice];

	return self;

abort:
	return [self free];
}

/*
 * Ensure DMA machine is in idle quiescent state.
 */
- (void)dmaIdle
{
	unsigned cmd = DC_CMD_IDLE | DC_MDL;
	
	/*
	 * MDL and dir bits need to be the same as they will for a 
	 * (potentially) upcoming DMA command.
	 */
	if(activeCmd) {
		if(activeCmd->scsiReq->read) {
			cmd |= DC_DIR_READ;
		}
		else {
			cmd |= DC_DIR_WRITE;
		}
	}
	/* else direction is don't care */
	
	/*
	 * FIXME - should we do a DMA blast here?
	 */
	WRITE_REGL(dmaCommand, cmd);
	#if	WRITE_DMA_COMMAND_TWICE
	WRITE_REGL(dmaCommand, cmd);
	#endif	WRITE_DMA_COMMAND_TWICE
}

#if	DDM_DEBUG
static unsigned char *ddmPhys;
#endif	DDM_DEBUG

/*
 * Start DMA transfer at activeCmd->currentPtr for activeCmd->currentByteCount.
 * Note: this method is not strictly architecture-dependent and 
 * chip-independent. I think it's best to do all of this work in one place,
 * and an AMD chip for a different bus will definitely have a lot of changes
 * here. 
 */
- (sc_status_t)dmaStart
{
	unsigned 	byteCount = activeCmd->currentByteCount;
	unsigned char 	cvalue;
	unsigned 	pages;
	vm_offset_t 	virtAddr;
	unsigned 	physAddr;
	unsigned 	page;
	unsigned 	offset;
	IOReturn	irtn;
	unsigned 	cmd;
	
	ddm_thr("dmaStart\n", 1,2,3,4,5);
	ASSERT(activeCmd != NULL);
	[self dmaIdle];
	
	/*
	 * Set up SCSI block transfer count registers.
	 */
	cvalue = byteCount & 0xff;
	WRITE_REG(startXfrCntLow, cvalue);
	cvalue = (byteCount >> 8) & 0xff;
	WRITE_REG(startXfrCntMid, cvalue);
	cvalue = (byteCount >> 16) & 0xff;
	WRITE_REG(startXfrCntHi, cvalue);
	
	/*
	 * Set up a memory descriptor list.
	 */
	virtAddr = (vm_offset_t)activeCmd->currentPtr;
	pages = (AMD_ROUND_PAGE(virtAddr + byteCount) - 
	         AMD_TRUNC_PAGE(virtAddr)) / AMD_DMA_PAGE_SIZE;
	if(pages > MDL_SIZE) {
		IOLog("%s: DMA Transfer Count Exceeded (%d)\n",
			[self name], byteCount);
		return SR_IOST_MEMALL;
	}
	for(page=0; page<pages; page++) {
		if(page == 0) {
			/*
			 * Special case, this one is allowed a page offset.
			 */
			offset = virtAddr & AMD_DMA_PAGE_MASK;
			WRITE_REGL(dmaStartAddrs, offset);
			ddm_dma("    page 0 offset 0x%x\n", offset, 2,3,4,5);
			virtAddr = virtAddr & ~AMD_DMA_PAGE_MASK;
		}
		irtn = IOPhysicalFromVirtual(activeCmd->client,
			virtAddr,
			&physAddr);
		if(irtn) {
			IOLog("%s: Can't get physical address (%s)\n", 
				[self name], [self stringFromReturn:irtn]);
			return SR_IOST_MEMF;
		}
		ddm_dma("    mdl[%d] = 0x%x\n", page, mdl[page], 3,4,5);
		mdl[page] = physAddr;
		virtAddr += AMD_DMA_PAGE_SIZE;
		#if	DDM_DEBUG
		if(page == 0) {
			ddmPhys = (unsigned char *)(physAddr + offset);
		}
		#endif	DDM_DEBUG
	}
	
	/*
	 * Load byte count and address of MDL into DMA engine, and go.
	 */
	ddm_dma("    dmaStartCount = 0x%x\n", byteCount, 2,3,4,5);
	WRITE_REGL(dmaStartCount, byteCount);
	WRITE_REGL(dmaStartMdlAddrs, mdlPhys);
	if(activeCmd->scsiReq->read) {
		cmd = DC_CMD_START | DC_MDL | DC_DIR_READ;
	}
	else {
		cmd = DC_CMD_START | DC_MDL | DC_DIR_WRITE;
	}
	WRITE_REGL(dmaCommand, cmd);
	#if	WRITE_DMA_COMMAND_TWICE
	WRITE_REGL(dmaCommand, cmd);
	#endif	WRITE_DMA_COMMAND_TWICE
	WRITE_REG(scsiCmd, SCMD_TRANSFER_INFO | SCMD_ENABLEDMA);
	scState = SCS_DMAING;
	return SR_IOST_GOOD;
}

/*
 * Terminate a DMA, including FIFO flush if necessary. Returns number of 
 * bytes transferred.
 */
- (unsigned)dmaTerminate
{
	unsigned char 	fifoDepth = 0;
	unsigned 	cmd;
	int 		tries;
	unsigned	status;
	unsigned	bytesXfrd;
	unsigned	scsiXfrCnt;
	unsigned	value;
	
	ASSERT(activeCmd != NULL);
	
	/*
	 * Get resid count from SCSI block.
	 */
	scsiXfrCnt = READ_REG(currXfrCntLow);
	value = READ_REG(currXfrCntMid);
	scsiXfrCnt += (value << 8);
	value = READ_REG(currXfrCntHi);
	scsiXfrCnt += (value << 16);
	
	fifoDepth = READ_REG(currFifoState) & FS_FIFO_LEVEL_MASK;
	if((activeCmd->scsiReq->read) && (scsiXfrCnt != 0)) {
		/*
		 * Make sure SCSI fifo is empty. The manual says we 
		 * might have to wait a while.
		 */
		if(fifoDepth) {
			IODelay(1000);
			fifoDepth = READ_REG(currFifoState) & 
				FS_FIFO_LEVEL_MASK;
			switch(fifoDepth) {
			    case 0:
			    	ddm_dma("dmaTerminate: fifo cleared\n",
					1,2,3,4,5);
			    	break;		// normal, OK
			    case 1:
			    	IOLog("%s: Odd Byte Disconnect on target %d\n",
					[self name], 
					activeCmd->scsiReq->target);
				break;
			    default:
			    	IOLog("%s: SCSI FIFO hung\n", [self name]);
				break;
			
			   	/*
				 * I'm not sure what to do about these
				 * errors...
				 */
			}
		}
		if(activeCmd->scsiReq->read) {
			cmd = DC_CMD_BLAST | DC_MDL | DC_DIR_READ;
		}
		else {
			cmd = DC_CMD_BLAST | DC_MDL | DC_DIR_WRITE;
		}
		ddm_dma("   ...sending DMA blast\n", 1,2,3,4,5);
		WRITE_REGL(dmaCommand, cmd);
		#if	WRITE_DMA_COMMAND_TWICE
		WRITE_REGL(dmaCommand, cmd);
		#endif	WRITE_DMA_COMMAND_TWICE
		
		/*
		 * Unfortunately, we have to poll for this one. No interrupt.
		 * FIXME - documentation is unclear on this. 6.7.6, the 
		 * description of dmaStatus, says DS_BLAST_COMPLETE is only 
		 * complete for "SCSI Disconnect and Reselect Operation".
		 * That doesn't make a whole lot of sense to me...
		 */
		for(tries=0; tries<500; tries++) {
			status = READ_REGL(dmaStatus);
			if(status & DS_BLAST_COMPLETE) {
				break;
			}
			IODelay(100);
		}
		
		ddm_dma("DMA blast : tries = %d fifoDepth = %d\n", 
			tries, fifoDepth, 3,4,5);
	}
	
	/*
	 * Obtain number of bytes transferred. 
	 */
	bytesXfrd = activeCmd->currentByteCount - 
		(scsiXfrCnt + fifoDepth);
	ddm_chip("dmaTerminate: currentByteCount 0x%x, bytesXfrd 0x%x\n",
		activeCmd->currentByteCount, bytesXfrd, 3,4,5);
#if	0
	{
	unsigned char *vp = activeCmd->buffer;
	
	ddm_init("ddmPhys = %02x %02x %02x %02x %02x\n",
		ddmPhys[0], ddmPhys[1], ddmPhys[2], ddmPhys[3], ddmPhys[4]);
	ddm_init("          %02x %02x %02x %02x %02x\n",
	    	ddmPhys[5], ddmPhys[6], ddmPhys[7], ddmPhys[8], ddmPhys[9]);
	ddm_init("virt    = %02x %02x %02x %02x %02x\n",
		vp[0], vp[1], vp[2], vp[3], vp[4]);
	ddm_init("          %02x %02x %02x %02x %02x\n",
	    	vp[5], vp[6], vp[7], vp[8], vp[9]);
	}
#endif	0
	[self dmaIdle];
	return bytesXfrd;
}

@end

#if	TEST_DEBUG

/*
 * Do some simple I/O before IODisk starts probing us.
 */
int	loopTest = 0;
int	target = 0;

#define DO_INIT_SLEEP	0
#define DO_TUR		1
#define DO_READ		1
#define TEST_READ_SIZE	1	// in sectors
#define DO_TEST_ALIGN	0
#define TEST_DISCONNECT	1

static void testDebug(id driver)
{
	IOSCSIRequest	scsiReq;
	sc_status_t	srtn;
	unsigned char	*rbuf;
	int		block = 100000;
	
	ddm_init("testDebug\n", 1,2,3,4,5);
	if(DO_INIT_SLEEP) {
		IOLog("Sleeping for 10 seconds for DDM view\n");
		IOSleep(10000);
	}
	if(DO_READ) {
		if(DO_TEST_ALIGN) {
			rbuf = IOMallocLow(TEST_READ_SIZE * 512);
			if(rbuf == NULL) {
				IOLog("IOMallocLow returned NULL!\n");
				rbuf = IOMalloc(TEST_READ_SIZE * 512);
			}
		}
		else {
			rbuf = IOMalloc(TEST_READ_SIZE * 512);
		}
	}
	do {
		if(DO_TUR) {
			bzero(&scsiReq, sizeof(IOSCSIRequest));
			scsiReq.target = target;
			scsiReq.cmdQueueDisable = 1;
		
			/* 
			 * cdb = all zeroes = test unit ready 
			 */
			scsiReq.timeoutLength = 4;
			srtn = [driver executeRequest:&scsiReq
				buffer:NULL
				client:(vm_task_t)0];
			IOLog("testDebug: TUR result = %s\n",
				IOFindNameForValue(scsiReq.driverStatus, 
					IOScStatusStrings));
		}
		
		if(DO_READ) {
			cdb_6_t *cdbp = &scsiReq.cdb.cdb_c6;
			unsigned i;

			bzero(&scsiReq, sizeof(IOSCSIRequest));
			scsiReq.target = target;
			scsiReq.cmdQueueDisable = 1;
			scsiReq.disconnect = TEST_DISCONNECT;
			for(i=0; i<(TEST_READ_SIZE * 512); i++) {
				rbuf[i] = i;
			}
			cdbp->c6_opcode = 8;
			cdbp->c6_len = TEST_READ_SIZE;
			cdbp->c6_lba0 = block;
			/*
			 * Force a disconnect eventually 
			 */
			if(block == 0) {
				block = 100000;	
			}
			else {
				block = 0;
			}
			scsiReq.maxTransfer = TEST_READ_SIZE * 512;
			scsiReq.read = YES;
			scsiReq.timeoutLength = 10;
			srtn = [driver executeRequest:&scsiReq
				buffer:rbuf
				client:IOVmTaskSelf()];
			if(scsiReq.driverStatus == 0) {
				ddm_init("rbuf = %02x %02x %02x %02x %02x\n",
				   rbuf[0],rbuf[1],rbuf[2],rbuf[3],rbuf[4]);
				ddm_init("       %02x %02x %02x %02x %02x\n",
				   rbuf[5],rbuf[6],rbuf[7],rbuf[8],rbuf[9]);
			}
			IOLog("testDebug: Read result = %s\n",
				IOFindNameForValue(scsiReq.driverStatus, 
					IOScStatusStrings));
		}
		IOSleep(5000);
	} while(loopTest);
	
}

#endif	TEST_DEBUG

#if	TEST_IPL_BUG

#define IPL_TEST_LOOPS	1000000		// # of loops
#define IPL_TEST_TIME	0		// us delay per loop

static void testIplBug() {
	int loopNum;
	ns_time_t curTime, lastTime;
	unsigned usTime;
	
	IOGetTimestamp(&lastTime);
	for(loopNum=0; loopNum<IPL_TEST_LOOPS; loopNum++) {
		if(IPL_TEST_TIME) {
			IODelay(IPL_TEST_TIME);
		}
		IOGetTimestamp(&curTime);
		usTime = (unsigned)((curTime - lastTime) / 1000ULL);
		if(usTime > 1000) {
			ddm_intr("usTime %d loopNum %d curTime 0x%x lastTime "
				"0x%x\n",
				usTime, loopNum,
				(unsigned)(curTime & 0xffffffffULL),
				(unsigned)(lastTime & 0xffffffffULL), 5);
		}
		lastTime = curTime;
		
	}
	ddm_intr("testIplBug complete; IPL_TEST_TIME %d\n", IPL_TEST_TIME,
		2,3,4,5);
		
	/*
	 * Calibrate the IODelay call...
	 *
	for(loopNum=0; loopNum<500; loopNum++) {
		IODelay(IPL_TEST_TIME);
		ddm_intr("IODelay(%d) calibration\n", IPL_TEST_TIME, 2,3,4,5);
	}
	*/
}

#endif	TEST_IPL_BUG
