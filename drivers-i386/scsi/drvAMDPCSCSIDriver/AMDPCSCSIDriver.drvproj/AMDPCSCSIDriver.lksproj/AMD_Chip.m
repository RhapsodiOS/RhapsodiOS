/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_Chip.m - chip (53C974/79C974) specific methods for AMD SCSI driver
 *
 * HISTORY
 * 21 Oct 94    Doug Mitchell at NeXT
 *      Created. 
 */

#import "AMD_Chip.h"
#import "AMD_ChipPrivate.h"
#import "AMD_Private.h"
#import "AMD_x86.h"
#import "AMD_Regs.h"
#import "AMD_Types.h"
#import "AMD_ddm.h"
#import "bringup.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>

IONamedValue scsiMsgValues[] = {
	{MSG_CMDCMPLT,		"Command Complete"	},
	{MSG_EXTENDED,		"Extended Message"	},
	{MSG_SAVEPTRS,		"Save Pointers"		},
	{MSG_RESTOREPTRS,	"Restore Pointers"	},
	{MSG_DISCONNECT,	"Disconnect"		},
	{MSG_IDETERR,		"Initiator Det Error"	},
	{MSG_ABORT,		"Abort"			},
	{MSG_MSGREJECT,		"Message Reject"	},
	{MSG_NOP,		"Nop"			},
	{MSG_MSGPARERR,		"Message parity Error"	},
	{0,			NULL			}
};

#ifdef	DDM_DEBUG
IONamedValue scsiPhaseValues[] = {
	{PHASE_DATAOUT,		"data_out"		},
	{PHASE_DATAIN,		"data_in"		},
	{PHASE_COMMAND,		"command"		},
	{PHASE_STATUS,		"status"		},
	{PHASE_MSGOUT,		"message_out"		},
	{PHASE_MSGIN,		"message_in"		},
	{0,			NULL			}
};

#endif	DDM_DEBUG

#ifdef	DEBUG
/*
 * For IOFindNameForValue() and ddm's.
 */
IONamedValue scStateValues[] = { 
	{SCS_UNINITIALIZED,	"SCS_UNINITIALIZED"	},
        {SCS_DISCONNECTED,	"SCS_DISCONNECTED"	},
        {SCS_SELECTING,		"SCS_SELECTING"		},
        {SCS_INITIATOR,		"SCS_INITIATOR" 	},
        {SCS_COMPLETING,	"SCS_COMPLETING"	},
        {SCS_DMAING,		"SCS_DMAING"		},	
        {SCS_ACCEPTINGMSG,	"SCS_ACCEPTINGMSG"	},
        {SCS_SENDINGMSG,	"SCS_SENDINGMSG"	},	
        {SCS_GETTINGMSG,	"SCS_GETTINGMSG"	},	
	{SCS_SENDINGCMD,	"SCS_SENDINGCMD"	},
	{0, 			NULL			},
};
#endif	DEBUG

@implementation AMD_SCSI(Chip)

/*
 * One-time-only init and probe. Returns YES if a functioning chip is 
 * found, else returns NO. -hwReset must be called subsequent to this 
 * to enable operation of the chip.
 */
- (BOOL)probeChip
{
	int target;
	
	/*
	 * Init sync mode to async, until we negotiate.
	 */
	for(target=0; target<SCSI_NTARGETS; target++) {
		perTarget[target].syncXferOffset = 0;
	}
	return YES;
}

/*
 * Reusable 53C974 init function. This includes a SCSI reset.
 * Handling of ioComplete of active and disconnected commands must be done
 * elsewhere. Returns non-zero on error. 
 */
- (int)hwReset : (const char *)reason
{
	int 		target;
	unsigned char 	reg;
	
	/*
	 * First of all, reset interrupts, the SCSI block, and the DMA engine.
	 */
	[self disableAllInterrupts];
	WRITE_REG(scsiCmd, SCMD_RESET_DEVICE);
	WRITE_REG(scsiCmd, SCMD_NOP);
	[self dmaIdle];
	
	/*
	 * Clear possible pending interrupt.
	 */
	READ_REG(intrStatus);
	
	/*
	 * Init state variables.
	 */
	reselPending  = 0;
	scState       = SCS_DISCONNECTED;
	activeCmd     = NULL;
	currMsgInCnt  = 0;
	currMsgOutCnt = 0;
	msgOutState   = MOS_NONE;
	SDTR_State    = SNS_NONE;
	
	/*
	 * Sync negotiation is needed after a reset.
	 */
	for(target=0; target<SCSI_NTARGETS; target++) {
		perTarget[target].syncNegotNeeded = 1;
	}
	
	/*
	 * Control1....
	 */
	reg = CR1_RESET_INTR_DIS | CR1_PERR_ENABLE | AMD_SCSI_ID;
	if(extendTiming) {
		/*
		 * Per instance table. This slows down transfers on the
		 * bus.
		 */
		reg |= CR1_EXTEND_TIMING;
	}
	WRITE_REG(control1, reg);
	ddm_init("control1 = 0x%x\n", reg, 2,3,4,5);
	hostId = AMD_SCSI_ID;
	
	/*
	 * Clock factor and select timeout.
	 */
	ASSERT(scsiClockRate != 0);
	if(scsiClockRate < 10) {
		IOLog("AMD53C974: Clock %d MHZ too low; using 10 MHz\n",
			 scsiClockRate);
		scsiClockRate = 10;
	}
	if(scsiClockRate > 40) {
		IOLog("AMD53C974: Clock %d MHZ too high; using 40 MHz\n",
			 scsiClockRate);
		scsiClockRate = 40;
	}
	reg = AMD_CLOCK_FACTOR(scsiClockRate) & 0x7;
	WRITE_REG(clockFactor, reg);
	ddm_init("clockFactor %d\n", reg, 2,3,4,5);
	reg = amdSelectTimeout(AMD_SELECT_TO, scsiClockRate);
	WRITE_REG(scsiTimeout, reg);
	ddm_init("select timeout reg 0x%x\n", reg, 2,3,4,5);
	
	/*
	 * control2 - enable extended features - mainly, 24-bit transfer count.
	 */
	WRITE_REG(control2, CR2_ENABLE_FEAT);
	
	/*
	 * control3
	 */
	reg = 0;
	if(fastModeEnable) {
		reg |= CR3_FAST_SCSI;
	}
	if(scsiClockRate > 25) {
		reg |= CR3_FAST_CLOCK;
	}
	ddm_init("control3 = 0x%x\n", reg, 2,3,4,5);
	WRITE_REG(control3, reg);
	
	/*
	 * control4 - glitch eater, active negation. Let's not 
	 * worry about these whizzy features just yet.
	 */
	WRITE_REG(control4, 0);
	
	/*
	 * Go to async xfer mode for now. Sync gets enabled on a per-target 
	 * basis in -targetContext.
	 */
	WRITE_REG(syncOffset, 0);
	
	/*
	 * Reset SCSI bus, wait, clear possible interrupt.
	 */
	WRITE_REG(scsiCmd, SCMD_RESET_SCSI);
	if(reason) {
		IOLog("AMD53C974: Resetting SCSI bus (%s)\n", reason);
	}
	else {
		IOLog("AMD53C974: Resetting SCSI bus\n");
	}
	IOSleep(AMD_SCSI_RESET_DELAY);
	READ_REG(intrStatus);

	ddm_init("hwReset: enabling interrupts\n", 1,2,3,4,5);
	[self enableAllInterrupts];
	
	ddm_init("hwReset: DONE\n", 1,2,3,4,5);
	return 0;	
}

/*
 * reset SCSI bus.
 */
- (void)scsiReset
{
	WRITE_REG(scsiCmd, SCMD_RESET_SCSI);
	READ_REG(intrStatus);
}

/*
 * Prepare for power down. 
 *  -- reset SCSI bus to get targets back to known state
 *  -- reset chip 
 */
- (void) powerDown
{
	WRITE_REG(scsiCmd, SCMD_RESET_SCSI);
	IODelay(100);				// SCSI spec says 25 us
	READ_REG(intrStatus);			// clear SCSI reset interrupt
	WRITE_REG(scsiCmd, SCMD_RESET_DEVICE);
	IODelay(50);				// chip settle delay
	WRITE_REG(scsiCmd, SCMD_NOP);		// re-enable chip for BIOS
}

/*
 * Start a SCSI transaction for the specified command. ActiveCmd must be 
 * NULL. A return of HWS_REJECT indicates that caller may try again
 * with another command; HWS_BUSY indicates a condition other than
 * (activeCmd != NULL) which prevents the processing of the command.
 */
- (hwStartReturn)hwStart : (commandBuf *)cmdBuf
{	
	unsigned char	cdb_ctrl;
	IOSCSIRequest	*scsiReq = cmdBuf->scsiReq;
	cdb_t		*cdbp = &scsiReq->cdb;
	unsigned char	identify_msg = 0;
	unsigned char	*cp;
	unsigned char	okToDisc;
	unsigned char	okToQueue;
	perTargetData	*perTargetPtr;
	int		i;
	BOOL		cmdQueueDisableFlag = NO;
	unsigned char	selectCmd;
	
	ddm_chip("hwStart cmdBuf = 0x%x opcode %s\n", cmdBuf, 
		IOFindNameForValue(cdbp->cdb_opcode, IOSCSIOpcodeStrings),
			3,4,5);
	ASSERT(activeCmd == NULL);
	
	/*
	 * Currently, the only reason we return HWS_BUSY is if we have
	 * a reselect pending.
	 */
	if(reselPending) {
		queue_enter(&pendingQ, cmdBuf, commandBuf *, link);
		return HWS_BUSY;
	}
	ASSERT(scState == SCS_DISCONNECTED);
		
	/*
	 * Initialize driver return values and state machine.
	 */
	cmdBuf->currentByteCount = cmdBuf->savedByteCount = 
		scsiReq->maxTransfer;
	scsiReq->bytesTransferred = 0;
	cmdBuf->savedPtr = cmdBuf->currentPtr = (vm_offset_t)cmdBuf->buffer;
	scsiReq->driverStatus = SR_IOST_INVALID;
	scsiReq->totalTime  = 0ULL;
	scsiReq->latentTime = 0ULL;
	
	/*
	 * Figure out what kind of cdb we've been given and grab the ctrl byte.
	 */
	switch (SCSI_OPGROUP(cdbp->cdb_opcode)) {
	    case OPGROUP_0:
		cmdBuf->cdbLength = sizeof(cdb_6_t);
		cdb_ctrl  = cdbp->cdb_c6.c6_ctrl;
		break;
	    case OPGROUP_1:
	    case OPGROUP_2:
		cmdBuf->cdbLength = sizeof(cdb_10_t);
		cdb_ctrl  = cdbp->cdb_c10.c10_ctrl;
		break;
	    case OPGROUP_5:
		cmdBuf->cdbLength = sizeof(cdb_12_t);
		cdb_ctrl  = cdbp->cdb_c12.c12_ctrl;
		break;
            case OPGROUP_6:
		cmdBuf->cdbLength = (scsiReq->cdbLength ? 
			 scsiReq->cdbLength : sizeof (struct cdb_6));
		cdb_ctrl = 0;
		break;
	    case OPGROUP_7:
		cmdBuf->cdbLength = (scsiReq->cdbLength ? 
			 scsiReq->cdbLength : sizeof (struct cdb_10));
		cdb_ctrl = 0;
		break;
	    default:
		goto abortReq;
	}
	ddm_chip("cdbLength = %d\n", cmdBuf->cdbLength, 2,3,4,5);
	
	/*
	 * Do a little command snooping.
	 */
	perTargetPtr = &perTarget[scsiReq->target];
	switch(cdbp->cdb_opcode) {
	    case C6OP_INQUIRY:
		/*
		 * The first command SCSIDisk sends us is an Inquiry command.
		 * This never gets retried, so avoid a possible 
		 * reject of a command queue tag. Avoid this hack if
		 * there are any other commands outstanding for this
		 * target/lun.
		 */
		if(activeArray[scsiReq->target][scsiReq->lun] == 0) {
			cmdQueueDisableFlag = YES;
		}
		break;
		
	    case C6OP_REQSENSE:
	    	/*
		 * Always force sync renegotiation on this one to 
		 * catch independent target power cycles.
		 */
		if(SYNC_RENEGOT_ON_REQ_SENSE) {
			perTargetPtr->syncNegotNeeded = 1;
		}
		break;
	}
		
	/*
	 * Avoid command queueing if if we're going to do sync
	 * negotiation.
	 * FIXME - this might be illegal - what if we're doing a request 
	 * sense in response to a legitimate error, and there are 
	 * tagged commands pending?
	 */
	if(perTargetPtr->syncNegotNeeded &&
	   !perTargetPtr->syncDisable &&
	   syncModeEnable) {
	   	cmdQueueDisableFlag = YES;
		SDTR_State = SNS_HOST_INIT_NEEDED;
		ddm_chip("hwStart: entering SNS_HOST_INIT_NEEDED state\n", 
			1,2,3,4,5);
	}
	else {
		SDTR_State = SNS_NONE;
	}
	
	/*
	 * Determine from myriad sources whether or not it's OK to 
	 * disconnect and to use command queueing. 
	 */
	okToQueue = cmdQueueEnable &&			// global per driver
	    	    !scsiReq->cmdQueueDisable && 	// per I/O
	    	    !perTargetPtr->cmdQueueDisable &&  	// per target
		    !cmdQueueDisableFlag;		// inquiry hack
	okToDisc  = ([self numReserved] > 		// > 1 target on bus
			(1 + SCSI_NLUNS)) || 
		    okToQueue;				// hope to do cmd q'ing
	#if	FORCE_DISCONNECTS
	okToDisc = 1;
	#else	FORCE_DISCONNECTS
	if(!scsiReq->disconnect) {
		/*
		 * This overrides everything...
		 */
		okToQueue = okToDisc = 0;
	}
	#endif	FORCE_DISCONNECTS
	cmdBuf->discEnable = okToDisc;
	if(okToQueue) {
		/*
		 * Avoid using tag QUEUE_TAG_NONTAGGED...
		 */
		cmdBuf->queueTag = nextQueueTag;
		if(++nextQueueTag == QUEUE_TAG_NONTAGGED) {
			nextQueueTag++;
		}
	}
	else {
		cmdBuf->queueTag = QUEUE_TAG_NONTAGGED;
	}
	
	/*
	 * Make sure nothing unreasonable has been asked of us. 
	 */
	if((cdb_ctrl & CTRL_LINKFLAG) != CTRL_NOLINK) {
		ddm_err("Linked CDB (Unimplemented)\n",
			1,2,3,4,5);
		goto abortReq;
	}

	/*
	 * OK, this command is hot.
	 */
	[self activateCommand:cmdBuf];
	
	scState = SCS_SELECTING;
	msgOutState = MOS_NONE;
	bzero(currMsgIn, AMD_MSG_SIZE);
	bzero(currMsgOut, AMD_MSG_SIZE);
	currMsgInCnt = 0;
	currMsgOutCnt = 0;
	
	/*
	 * Load per-target context.
	 */
	[self targetContext:scsiReq->target];

	/*
	 * set target bus id
	 * punch message(s), optional cdb into fifo
	 * write appropriate select command
	 */
	ddm_chip("hwStart: opcode 0x%x targ %d lun %d maxTransfer 0x%x\n", 
	     cdbp->cdb_opcode, scsiReq->target, scsiReq->lun, 
	     scsiReq->maxTransfer, 5);
	WRITE_REG(scsiCmd, SCMD_CLEAR_FIFO);
	WRITE_REG(scsiDestID, scsiReq->target);
	identify_msg = MSG_IDENTIFYMASK | (scsiReq->lun & MSG_ID_LUNMASK);
	if(okToDisc) {
		identify_msg |= MSG_ID_DISCONN;
	}

	WRITE_REG(scsiFifo, identify_msg);
	
	/*
	 * Note this logic assumes that queue tag and SDTR messages are
	 * mutually exclusive...
	 */
	if(SDTR_State == SNS_HOST_INIT_NEEDED) {
		selectCmd = SCMD_SELECT_ATN_STOP;
	}
	else {
		if(okToQueue) {
			WRITE_REG(scsiFifo, MSG_SIMPLE_QUEUE_TAG);
			WRITE_REG(scsiFifo, cmdBuf->queueTag);
			
			/*
			 * Save these in currMsgOut[] in case 
			 * the target rejects this message.
			 */
			currMsgOut[0] = MSG_SIMPLE_QUEUE_TAG;
			currMsgOut[1] = cmdBuf->queueTag;
			currMsgOutCnt = 2;
		}
		cp = (u_char *)cdbp;
		for(i=0; i<cmdBuf->cdbLength; i++) {
			WRITE_REG(scsiFifo, *cp++);
		}
		if(okToQueue) {
			selectCmd = SCMD_SELECT_ATN_3;
		}
		else {
			selectCmd = SCMD_SELECT_ATN;
		}
	}
	WRITE_REG(scsiCmd, selectCmd);
	IOGetTimestamp(&cmdBuf->startTime);
	return HWS_OK;
	
abortReq:
	scsiReq->driverStatus = SR_IOST_CMDREJ;
	[self ioComplete:cmdBuf];
	return HWS_REJECT;
}

/*
 * SCSI device interrupt handler.
 */
- (void)hwInterrupt
{
	ddm_chip("hwInterrupt: activeCmd 0x%x\n", activeCmd, 2,3,4,5);
	
	switch([self scsiInterruptPending]) {
	    case SINT_NONE:
		/*
		 * Must be another device....
		 */
		[self enableAllInterrupts];
		return;
	    case SINT_DEVICE:
	    case SINT_DMA:
	    	break;
	    default:
	    	/* 
		 * What do we do now, batman?
		 */
		[self hwAbort:SR_IOST_HW reason:"Bad Interrupt Received"];
		return;
	}
	
goAgain:
	/*
	 * Save interrupt state.
	 */
	saveStatus     = READ_REG(scsiStat);
	saveSeqStep    = READ_REG(internState);
	saveIntrStatus = READ_REG(intrStatus);
		
	ddm_chip("   status 0x%x intstatus 0x%x scState %s\n", 
		saveStatus, saveIntrStatus, 
		IOFindNameForValue(scState, scStateValues), 4,5);
	if((saveStatus & SS_ILLEGALOP) || (saveIntrStatus & IS_ILLEGALCMD)) {
	   
	 	/*
		 * Software screwup. Start over from scratch.
		 */
		IOLog("AMD53C974: hardware command reject\n");
		[self hwAbort:SR_IOST_INT reason:"Hardware Command Reject"];
		return;
	}

	/*
	 * OK, grind thru the state machine.
	 */
	switch(scState) {
           case SCS_DISCONNECTED:
	   	[self fsmDisconnected];
		break;
           case SCS_SELECTING:
	   	[self fsmSelecting];
		break;
           case SCS_INITIATOR:
	   	[self fsmInitiator];
		break;
           case SCS_COMPLETING:
	   	[self fsmCompleting];
		break;
           case SCS_DMAING:
	   	[self fsmDMAing];
		break;
           case SCS_ACCEPTINGMSG:
	   	[self fsmAcceptingMsg];
		break;
           case SCS_SENDINGMSG:
	   	[self fsmSendingMsg];
		break;
           case SCS_GETTINGMSG:
	   	[self fsmGettingMsg];
		break;
	   case SCS_SENDINGCMD:
	   	[self fsmSendingCmd];
		break;
	   default:
	   	IOPanic("AMD53C974: Bad scState");
	} /* switch scState */
	
	if ((scState != SCS_DISCONNECTED) &&
	    (saveIntrStatus & IS_DISCONNECT)) {
		/*
		 * the target just up and went away. This is a catch-all
		 * trap for any unexpected disconnect.
		 */
		ddm_err("hwInterrupt: target disconnected\n", 1,2,3,4,5);
		scState = SCS_DISCONNECTED;
		if(activeCmd != NULL) {
			activeCmd->scsiReq->driverStatus = SR_IOST_TABT;
			[self ioComplete:activeCmd];
			activeCmd = NULL;
		}
	}
	
	/*
	 * Handle a SCSI Phase change if necessary.
	 */
	if (scState == SCS_INITIATOR)
		[self fsmPhaseChange];
#ifdef	DEBUG
	else {
		ddm_chip("hwInterrupt #2: scState %s\n", 
			IOFindNameForValue(scState, scStateValues),
			2,3,4,5);
	}
#endif	DEBUG

	/*
	 * If we're off the bus, enable reselection at chip level.
	 */
	if (scState == SCS_DISCONNECTED) {
		ddm_chip("hwInterrupt: enabling reselection\n", 1,2,3,4,5);
		WRITE_REG(scsiCmd, SCMD_ENABLE_SELECT);
	}
	
	
	/*
	 * If another SCSI interrupt is pending, go for it again (avoiding 
	 * an unnecessary enableInterrupt and msg_receive()).
	 */
	switch([self scsiInterruptPending]) {
	    case SINT_DEVICE:
	    	#if	INTR_LATENCY_TEST
		ddm_chip("hwInterrupt: INTR TRUE; EXITING FOR MEASUREMENT\n",
			1,2,3,4,5);
		break;
		#else	INTR_LATENCY_TEST
	    	ddm_chip("hwInterrupt: going again without enabling "
			"interrupt\n", 1,2,3,4,5);
	    	goto goAgain;
		#endif	INTR_LATENCY_TEST
	    default:
	    	break;
	}

	[self enableAllInterrupts];
	
	/*
	 * One more thing - if we're still disconnected, enable processing
	 * of new commands. 
	 */
	if(scState == SCS_DISCONNECTED)
		[self busFree];
	ddm_chip("hwInterrupt: DONE; scState %s\n", 
		IOFindNameForValue(scState, scStateValues), 2,3,4,5);
}


- (void)logRegs
{
#if	DEBUG
	unsigned char 	cs, cis;
	unsigned char 	fifoDepth;
	unsigned	scsiXfrCnt;
	unsigned	value;
	
	IOLog("*** saveStatus 0x%x saveIntrStatus 0x%x\n", 
		saveStatus, saveIntrStatus);
	IOLog("*** scState = %s  scsiCmd = 0x%x\n", 
		IOFindNameForValue(scState, scStateValues),
		READ_REG(scsiCmd));
		
	cs = READ_REG(scsiStat);
	cis = READ_REG(intrStatus);
	IOLog("*** current status 0x%x current intrStatus 0x%x\n", cs, cis);
	
	IOLog("*** syncOffset %d  syncPeriod 0x%x\n", 
		syncOffsetShadow, syncPeriodShadow);
	
	fifoDepth = READ_REG(currFifoState) & FS_FIFO_LEVEL_MASK;
	scsiXfrCnt = READ_REG(currXfrCntLow);
	value = READ_REG(currXfrCntMid);
	scsiXfrCnt += (value << 8);
	value = READ_REG(currXfrCntHi);
	scsiXfrCnt += (value << 16);
	IOLog("*** fifoDepth %d  scsiXfrCnt 0x%x\n", fifoDepth, scsiXfrCnt);
#endif	DEBUG
}


@end	/* AMD_SCSI(Chip) */

/* end of AMD_Chip.m */

