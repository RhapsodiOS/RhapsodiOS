/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_ChipPrivate.m - methods used only by AMD_Chip module.
 *
 * HISTORY
 * 2 Nov 94    Doug Mitchell at NeXT
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


@implementation AMD_SCSI(ChipPrivate)

/*
 * Determine if SCSI interrupt is pending.
 */
- (sintPending_t)scsiInterruptPending
{
	unsigned char sstat;
	
	sstat = READ_REG(scsiStat);
	if (sstat & SS_INTERRUPT) {
		return SINT_DEVICE;
	}
	else {
		return SINT_NONE;
	}
}

/*
 * Methods invoked upon interrupt. One per legal scState. All assume that 
 * status and interrupt status have been captured in saveStatus and 
 * saveIntrStatus.
 */
 
/*
 * Disconnected - only legal event here is reselection.
 */
- (void)fsmDisconnected
{
	ddm_chip("fsmDisconnected\n", 1,2,3,4,5);
	ASSERT(activeCmd == NULL);
	if(saveIntrStatus & IS_RESELECTED) {
		/*
		 * We've been reselected. 
		 */
				
		unsigned char	selectByte;
		unsigned 	fifoDepth;
		unsigned char	msg;
	
		/* 
		 * Make sure there's a selection byte and an 
		 * identify message in the fifo.
		 */
		fifoDepth = READ_REG(currFifoState) & FS_FIFO_LEVEL_MASK;
		ddm_chip("reselect: fifoDepth %d\n", fifoDepth, 2,3,4,5);
		if(fifoDepth != 2) {
			ddm_err("reselection, fifoDepth %d\n", fifoDepth, 
				2,3,4,5);
			IOLog("AMD53C974: Bad FIFO count (%d) on Reselect\n",
				fifoDepth);
			[self hwAbort:SR_IOST_HW 
				reason:NULL];
			return;
			
		}
		
		/* 
		 * make sure target set his bit.
		 */
		if ((selectByte = READ_REG(scsiFifo) &~ (1 << hostId)) == 0) {
			ddm_err("fsmDisconnected: reselection failed"
				" - no target bit\n", 1,2,3,4,5);
			[self hwAbort:SR_IOST_BV 
				reason:"No target bit on Reselect"];
			return;
		}
		
		/* 
		 * figure out target from bit that's on.
		 */
		for (reselTarget = 0; 
		     (selectByte & 1) == 0; 
		     reselTarget++, selectByte>>=1) {
			continue;
		}
		
		/* 
		 * first message byte must be identify.
		 */
		msg = READ_REG(scsiFifo);
		if (saveStatus & SS_PARITYERROR) {
			ddm_err("fsmDisconnected: reselected parity error\n",
				1,2,3,4,5);
			[self hwAbort:SR_IOST_PARITY 
				reason:"Parity error on Reselect"];
			return;
		}
		if ((msg & MSG_IDENTIFYMASK) == 0) {
			ddm_err("fsmDisconnected: reselection failed - "
				"bad msg byte (0x%x)\n", msg, 2,3,4,5);
			[self hwAbort:SR_IOST_BV 
				reason:"Bad ID Message on Reselect"];
			return;
		}
		reselLun = msg & MSG_ID_LUNMASK;
		currMsgInCnt = 0;
		
		/*
		 * At this point, the chip is waiting for us to validate 
		 * the identify message. If cmd queueing is enabled
		 * for this target, the target is waiting to send a queue 
		 * tag message, so we have to tell the chip to 
		 * drop ACK before we proceed with the reselection. (There
		 * may be other msg bytes coming in, like a bogus 
		 * "save ptr" from a Syquest drive...)
		 *
		 * In case of sync mode, we need to load target context right
		 * now, before dropping ACK, because the target might go
		 * straight to a data in or data out as soon as ACK drops.
		 */
		[self targetContext:reselTarget];
		scState = SCS_ACCEPTINGMSG;
		reselPending = 1;
		WRITE_REG(scsiCmd, SCMD_CLEAR_FIFO);
		WRITE_REG(scsiCmd, SCMD_MSG_ACCEPTED);
		ddm_chip("reselPending: target %d lun %d\n",
			reselTarget, reselLun, 3,4,5);
		 
	} else if(saveIntrStatus & IS_SCSIRESET) {
		/*
		 * TBD - for now ignore, we get one of these by resetting the
		 * chip. If an I/O is pending, it'll probably time out.
		 * Maybe we want to return SR_IOST_RESET on the pending 
		 * command...
		 */
		ddm_chip("fsmDisconnected: ignoring reset interrupt\n",
			1,2,3,4,5);
	} else {
		/* 
		 * I'm confused.... 
		 */
		[self hwAbort:SR_IOST_BV 
			reason:"bad interrupt while disconnected"];
	}
}


/*
 * One of three things can happen here - the selection could succeed (though
 * with possible imcomplete message out), it could time out, or we can be 
 * reselected.
 */
#define CATCH_SELECT_TO		0

- (void)fsmSelecting
{
	unsigned char fifoDepth;
	unsigned char phase;
	IOSCSIRequest *scsiReq = activeCmd->scsiReq;
	
	ddm_chip("fsmSelecting\n", 1,2,3,4,5);
	ASSERT(activeCmd != NULL);
	if (saveIntrStatus & IS_DISCONNECT) {
		/*
		 * selection timed-out. Abort this request.
		 */
		#if	CATCH_SELECT_TO
		/* DEBUG ONLY */
		if(scsiReq->cdb.cdb_opcode != C6OP_INQUIRY) {
			IOLog("Unexpected Select Timeout\n");
		}
		#endif	CATCH_SELECT_TO
		ddm_chip("***SELECTION TIMEOUT for target %d\n",
			activeCmd->scsiReq->target, 2,3,4,5);
		WRITE_REG(scsiCmd, SCMD_CLEAR_FIFO);
		scState = SCS_DISCONNECTED;
		scsiReq->driverStatus = SR_IOST_SELTO;
		[self ioComplete:activeCmd];
		activeCmd = NULL;
	}
	else if(saveIntrStatus == (IS_SUCCESSFUL_OP|IS_SERVICE_REQ)) {

		ddm_chip("selection seqstep=%d\n", 
			saveSeqStep & INS_STATE_MASK, 2,3,4,5);
		
		switch (saveSeqStep & INS_STATE_MASK) {
		    case 0:	
		    	/*
			 * No message phase. If we really wanted one,
			 * this could be significant...
			 */
			if(activeCmd->queueTag != QUEUE_TAG_NONTAGGED) {
				/*
				 * This target can't do command queueing.
				 */
				[self disableMode:AM_CmdQueue];
			}	
			if(SDTR_State == SNS_HOST_INIT_NEEDED) {
				/*
				 * We were trying to do an SDTR.
				 */
				[self disableMode:AM_Sync];
				SDTR_State = SNS_NONE;
			}
			
			/*
			 * OK, let's try to continue following phase
			 * changes.
			 */
			scState = SCS_INITIATOR;
			break;
			
		    case 3:	/* didn't complete cmd phase, parity? */
		    case 4:	/* everything worked */
		    case 1:	/* everything worked, SCMD_SELECT_ATN_STOP
		    		 * case */
		    
		        /* 
			 * We're connected. Start following the target's phase
			 * changes.
			 *
			 * If we're trying to do sync negotiation,
			 * this is the place to do it. In that case, we
			 * sent a SCMD_SELECT_ATN_STOP command, and
			 * ATN is now asserted (and we're hopefully in
			 * msg out phase). We want to send 5 bytes. 
			 * Drop them into currMsgOut[] and prime the  
			 * msgOutState machine.
			 */
			if(SDTR_State == SNS_HOST_INIT_NEEDED) {
				[self createSDTR:currMsgOut inboundMsg:NULL];
				currMsgOutCnt = MSG_SDTR_LENGTH;
				msgOutState = MOS_WAITING;
			}
			scState = SCS_INITIATOR;
			break;
			
		    case 2:	
			/*
			 * Either no command phase, or imcomplete message
			 * transfer.
			 */
			fifoDepth = READ_REG(currFifoState) & 
				FS_FIFO_LEVEL_MASK;
			phase = saveStatus & SS_PHASEMASK;
			ddm_chip("INCOMPLETE SELECT; fifoDepth %d phase %s\n",
				fifoDepth, 
				IOFindNameForValue(phase, scsiPhaseValues),
				3,4,5);
			if(activeCmd->queueTag != QUEUE_TAG_NONTAGGED) {
				/*
				 * This target can't do command queueing.
				 */
				[self disableMode:AM_CmdQueue];
			}	
			
			/*
			 * Spec says ATN is asserted if all message bytes
			 * were not sent.
			 */
			if(fifoDepth > activeCmd->cdbLength) {
				WRITE_REG(scsiCmd, SCMD_CLR_ATN);
			}
			
			/*
			 * OK, let's try to continue following phase
			 * changes.
			 */
			scState = SCS_INITIATOR;
			break;

		    default:
			[self hwAbort:SR_IOST_HW 
				reason:"Selection sequence Error"];
			break;
		}
	}
	else if(saveIntrStatus & IS_RESELECTED) {
		/*
		 * We got reselected while trying to do a selection. 
		 * Enqueue this cmdBuf on the HEAD of pendingQ, then deal
		 * with the reselect. 
		 * Tricky case, we have to "deactivate" this command
		 * since this hwStart attempt failed.  
		 */
		queue_enter_first(&pendingQ, activeCmd, commandBuf *, link);
		[self deactivateCmd:activeCmd];
		ddm_chip("reselect while trying to select target %d\n",
			activeCmd->scsiReq->target, 2,3,4,5);
		activeCmd = NULL;
		scState = SCS_DISCONNECTED;
		
		/*
		 * Go deal with reselect.
		 */
		[self fsmDisconnected];
	}
	else {
		ddm_err("fsmSelecting: Bogus select/reselect interrupt\n", 
			1,2,3,4,5);
		[self hwAbort:SR_IOST_HW 
			reason: "Bogus select/reselect interrupt"];
		return;
	}
	return;
}

/*
 * This one is illegal.
 */
- (void)fsmInitiator
{
	ddm_chip("fsmInitiator\n", 1,2,3,4,5);
	[self hwAbort:SR_IOST_HW reason:"Interrupt as Initiator"];
}

/*
 * We just did a SCMD_INIT_CMD_CMPLT command, hopefully all that's left is
 * to drop ACK. Command Complete message is handled in fscAcceptingMsg.
 */
- (void)fsmCompleting
{		
	ddm_chip("fsmCompleting\n", 1,2,3,4,5);
	ASSERT(activeCmd != NULL);
	if(saveIntrStatus & IS_DISCONNECT) {
		ddm_err("unexpected completing disconnect\n",
			1,2,3,4,5);
		return;
	}
	if(saveIntrStatus & IS_SUCCESSFUL_OP) {
		/*
		 * Got both status and msg in fifo; Ack is still true.
		 */
		if((READ_REG(currFifoState) & FS_FIFO_LEVEL_MASK) != 2) {
			/*
			 * This is pretty bogus - we expect a status and 
			 * msg in the fifo. 
		   	 */
			[self hwAbort:SR_IOST_HW reason:"InitComplete fifo"
				" level"];
			return;
		}
		activeCmd->scsiReq->scsiStatus = READ_REG(scsiFifo);
		currMsgInCnt = 1;
		currMsgIn[0] = READ_REG(scsiFifo);
		ddm_chip("fsmCompleting: status 0x%x msg 0x%x\n",
			activeCmd->scsiReq->scsiStatus, 
			currMsgIn[0], 3,4,5);
		if (saveStatus & SS_PARITYERROR) {
			ddm_err("fsmCompleting: parity error on msg in\n",
				1,2,3,4,5);
			[self hwAbort:SR_IOST_PARITY 
				reason:"Parity error on message in"];
			return;
		}
		scState = SCS_ACCEPTINGMSG;
		WRITE_REG(scsiCmd, SCMD_MSG_ACCEPTED);
		return;
	} else {
		/*
		 * Must have just got a status byte only. This is kind of
		 * weird, but let's try to handle it.
		 */
		ddm_err("fsmCompleting: status only on complete\n", 
			1,2,3,4,5);
		if((READ_REG(currFifoState) & FS_FIFO_LEVEL_MASK) != 1) {
			[self hwAbort:SR_IOST_HW 
				reason:"Bad Fifo level on Cmd Complete"];
			return;
		}
		activeCmd->scsiReq->scsiStatus = READ_REG(scsiFifo);
		if(saveStatus & SS_PARITYERROR) {
			ddm_err("fsmCompleting: parity error on status\n",
				1,2,3,4,5);
			[self hwAbort:SR_IOST_PARITY 
				reason:"Parity Error on Cmd Complete"];
			return;
		}
		
		/*
		 * Back to watching phase changes. Why the target isn't in 
		 * message in we have yet to find out.
		 */
		scState = SCS_INITIATOR;
	}
}

/*
 * DMA Complete.
 */
- (void)fsmDMAing
{
	u_int bytesMoved;
	
	ddm_chip("fsmDMAing\n", 1,2,3,4,5);
	ASSERT(activeCmd != NULL);
	
	bytesMoved = [self dmaTerminate];
	if(bytesMoved > activeCmd->currentByteCount) {
		ddm_err("fsmDMAing: DMA transfer count exceeeded\n",
			1,2,3,4,5);
		ddm_err("  expected %d, moved %d\n", 
			activeCmd->currentByteCount, bytesMoved, 3,4,5);
		bytesMoved = activeCmd->currentByteCount;
	}
	((char *)activeCmd->currentPtr) += bytesMoved;
	activeCmd->currentByteCount     -= bytesMoved; 
	if(saveStatus & SS_PARITYERROR) {
		ddm_err("fsmDMAing: SCSI Data Parity Error\n", 1,2,3,4,5);
		[self hwAbort:SR_IOST_PARITY reason:"SCSI Data Parity Error"];
		return;
	}
	/*
	 * Back to watching phase changes.
         */
	scState = SCS_INITIATOR;
}

/*
 * Just completed the SCMD_TRANSFER_INFO operation for message in. ACK is
 * still true. Stash the current message byte in currMsgIn[] and proceed to
 * fsmAcceptingMsg after a SCMD_MSG_ACCEPTED.
 */
- (void)fsmGettingMsg
{
	BOOL	setAtn = NO;
	
	ASSERT((activeCmd != NULL) || reselPending);
	if(saveIntrStatus & IS_DISCONNECT) {
		ddm_chip("fsmGettingMsg: message In Disconnect\n", 1,2,3,4,5);
		/*
		 * This error is handled on return...
		 */
		return;
	}
	if((READ_REG(currFifoState) & FS_FIFO_LEVEL_MASK) != 1) {
		ddm_chip("Message In fifo error\n", 1,2,3,4,5);
		[self hwAbort:SR_IOST_HW reason:"Message In fifo error"];
		return;
	}

	currMsgIn[currMsgInCnt++] = READ_REG(scsiFifo);
	if(currMsgInCnt > AMD_MSG_SIZE) {
		[self hwAbort:SR_IOST_BV 
			reason:"Too Many Message bytes received"];
	}
	if(saveStatus & SS_PARITYERROR) {
		ddm_err("fsmGettingMsg: parity error on Message In\n", 
			1,2,3,4,5);
		[self hwAbort:SR_IOST_PARITY 
			reason:"parity error on Message In"];
		return;
	}
	ddm_chip("fsmGettingMsg: currMsgIn[%d] = 0x%x (%s)\n", currMsgInCnt-1,
		currMsgIn[currMsgInCnt-1],
		IOFindNameForValue(currMsgIn[currMsgInCnt-1], 
			scsiMsgValues),	4,5);
			
	/*
	 * Handle special cases. 
	 */
	 
	/*
	 * 1. If this is the last byte of an unsolicited sync negotiation, 
	 *    we have to assert ATN right now. The message is actually
	 *    fully parsed, and a response SDTR message created, in
	 *    fsmAcceptingMsg.
	 *
	 *    This parsing is pretty crude; if we come up with other special 
	 *    cases, we might rewrite this or come up with some state variables
	 *    to help us.
	 */
	if((currMsgInCnt >= MSG_SDTR_LENGTH) && (SDTR_State == SNS_NONE)) {
	
		int start = currMsgInCnt - MSG_SDTR_LENGTH;
		
		if((currMsgIn[start] == MSG_EXTENDED) &&
		   (currMsgIn[start+1] == (MSG_SDTR_LENGTH - 2)) &&
		   (currMsgIn[start+2] == MSG_SDTR)) {
		   	ddm_chip("UNSOLICITED SDTR IN; setting ATN\n",
				 1,2,3,4,5);
			WRITE_REG(scsiCmd, SCMD_SET_ATN);
			setAtn = YES;
			SDTR_State = SNS_TARGET_INIT;
		}
	}

	/*
	 * 2. If this was a message reject, it's possible that an extended
	 *    message out was prematurely aborted, with ATN still true.
	 *    Clear it so we don't do another (needless) message out.
	 *    Avoid this, of course, if we set ATN in this method for 
	 *    any reason.
	 */
	if((currMsgIn[currMsgInCnt - 1] == MSG_MSGREJECT) && 
	   (currMsgOutCnt > 1) &&
	   !setAtn) {
		ddm_chip("fsmGettingMsg: Message Reject; clearing ATN\n",
			1,2,3,4,5);
		WRITE_REG(scsiCmd, SCMD_CLR_ATN);
	}
	
	/*
	 * No need to clear FIFO; its depth was one on entry, and we read
	 * the byte. Note that clearing FIFO after the SCS_ACCEPTINGMSG
	 * might disturb possible sync data in transfer.
	 */
	WRITE_REG(scsiCmd, SCMD_MSG_ACCEPTED);
	scState = SCS_ACCEPTINGMSG;

}

/*
 * Just finished a message in; Ack is false. If phase is still
 * message in, we're in the midst of an extended message or additional
 * message bytes on reselect. Otherwise, message in is complete;
 * process currMsgIn[].
 */
- (void)fsmAcceptingMsg
{
	unsigned char 	phase = saveStatus & SS_PHASEMASK;
	unsigned 	index=0;
	perTargetData	*perTargetPtr;
	
	ddm_chip("fsmAcceptingMsg: phase %s\n", 
		IOFindNameForValue(phase, scsiPhaseValues), 2,3,4,5);
	if((phase == PHASE_MSGIN) && !(saveIntrStatus & IS_DISCONNECT)) {
	
		/*
		 * More message bytes to follow.
		 * We have to qualify with !IS_DISCONNECT to cover the 
		 * case of some targets (like the Exabyte tape drive)
		 * which bogusly keep CD, IO, and MSG asserted after
		 * they drop BSY upon command complete.
		 */
		WRITE_REG(scsiCmd, SCMD_CLEAR_FIFO);
		WRITE_REG(scsiCmd, SCMD_TRANSFER_INFO);
		scState = SCS_GETTINGMSG; 
		return;
	}
	
	/*
	 * Message in complete. Handle message(s) in currMsgIn[].
	 */
	if(reselPending) {
	
		/*
		 * Only interesting message here is queue tag.
		 */
		unsigned char tag = QUEUE_TAG_NONTAGGED;
		
		ASSERT(activeCmd == NULL);
		if(currMsgIn[index] == MSG_SIMPLE_QUEUE_TAG) {
			if(currMsgInCnt < 2) {
			    [self hwAbort: SR_IOST_BV
				reason:"Queue tag message, no tag"];
			    return;
			}
			tag = currMsgIn[++index];
			index++;
		}
		
		if([self reselect:reselTarget 
		        	lun:reselLun 
				queueTag:tag] == YES) {
			/*
			 * Found a disconnected commandBuf to reconnect.
			 *
			 * IDENTIFY msg implies restore ptrs.
			 */
			reselPending = 0;
			ASSERT(activeCmd != NULL);
			activeCmd->currentPtr = activeCmd->savedPtr;
			activeCmd->currentByteCount =  
				activeCmd->savedByteCount;
			scState = SCS_INITIATOR;
			
			/* 
			 * continue to handle possible additional messages
			 */
		}
		else {
			IOLog("AMD53C974: Illegal reselect (target %d lun "
				"%d tag %d)\n", reselTarget, reselLun, tag);
			[self hwAbort: SR_IOST_BV 
				reason:NULL];
			return;
		}
	}	/* reselect pending */
	
	/*
	 * Handle all other messages.
	 */
	ASSERT(activeCmd != NULL);
	perTargetPtr = &perTarget[activeCmd->scsiReq->target];
	
	for(; index<currMsgInCnt; index++) {
	    switch(currMsgIn[index]) {
		case MSG_CMDCMPLT:
		    /*
		     * Bus really should be free; we came here from 
		     * fsmCompleting.
		     */
		    if(!(saveIntrStatus & IS_DISCONNECT)) {
			    ddm_err("fsmAcceptingMsg: Command Complete"
				    " but no Disconnect\n", 1,2,3,4,5);
			    [self hwAbort:SR_IOST_BV 
				    reason:"No Disconnect On Command"
					    " Complete"];
			    return;
		    }
		    
		    /*
		     * TA DA!
		     */
		    scState = SCS_DISCONNECTED;
		    activeCmd->scsiReq->driverStatus = SR_IOST_GOOD;
		    [self ioComplete:activeCmd];
		    activeCmd = NULL;
		    return;
		
		case MSG_DISCONNECT:
		    if(!activeCmd->discEnable) {
			   /*
			    * This could be handled in fsmGettingMsg, 
			    * where we could handle it gracefully by 
			    * doing a MSGREJ, but this is such a bogus 
			    * error that we'll just reset the
			    * offender.
			    */
			    ddm_chip("***Illegal Disconnect attempt\n",
				    1,2,3,4,5);
			    IOLog("AMD53C974: Illegal disconnect attempt"
				    " on target %d\n",
				    activeCmd->scsiReq->target);
			    [self hwAbort:SR_IOST_BV
				    reason:NULL];
			    return;
		    }
		    
		    /*
		     * Special tricky case here. Some targets fail to do
		     * a restore pointers before disconnect if all 
		     * requested data has been transferred. Do an 
		     * implied save ptrs if that's the case.
		     */
		    if(activeCmd->currentByteCount == 0) {
			    activeCmd->savedPtr = activeCmd->currentPtr;
			    activeCmd->savedByteCount = 
				    activeCmd->currentByteCount;
		    }
		    scState = SCS_DISCONNECTED;
		    [self disconnect];
		    return;

		case MSG_SAVEPTRS:
		    activeCmd->savedPtr = activeCmd->currentPtr;
		    activeCmd->savedByteCount = 
			    activeCmd->currentByteCount;
		    break;
		    
		case MSG_RESTOREPTRS:
		    activeCmd->currentPtr = activeCmd->savedPtr;
		    activeCmd->currentByteCount = 
			    activeCmd->savedByteCount;
		    break;
			    
		case MSG_MSGREJECT:
		    /*
		     * look at last message sent; may have to 
		     * disable sync or cmd queue mode for this target.
		     * This assumes that we don't send SDTR and queue tag
		     * in the same message.
		     */
		    ddm_chip("fsmAcceptingMsg: MESSAGE REJECT RECEIVED "
			    "from target %d\n", 
			    activeCmd->scsiReq->target, 2,3,4,5);
		    if(currMsgOutCnt == 0) {
			    /*
			     * Huh? We haven't sent a message recently...
			     */
			    [self hwAbort:SR_IOST_BV
				    reason:"Unexpected Message Reject"];
			    return;
		    }
		    switch(currMsgOut[0]) {
			case MSG_SIMPLE_QUEUE_TAG:	
			    [self disableMode:AM_CmdQueue];
			    break;
			case MSG_EXTENDED:
			    /*
			     * Only one we ever send is sync negotiation..
			     */
			    if(currMsgOut[2] == MSG_SDTR) {
			        [self disableMode:AM_Sync];
				SDTR_State = SNS_NONE;
				break;
			    }
			    else {
				[self hwAbort:SR_IOST_INT
				    reason:"Currupted Message Buffer"];
				return;
			    }
			default:
			    IOLog("AMD53C974: %s Message Rejected\n",
				    IOFindNameForValue(currMsgOut[0], 
				    scsiMsgValues));
			    /* oh well... */
			    break;
		    }
		    
		    /*
		     * In any case, we're definitely thru with the 
		     * outbound message buffer.
		     */
		    currMsgOutCnt = 0;
		    break;
		    
		case MSG_LNKCMDCMPLT:
		case MSG_LNKCMDCMPLTFLAG:
		    /*
		     * This should never happen, because hwStart trashes
		     * commands with the LINK bit on.
		     */
		    [self hwAbort:SR_IOST_BV reason:"Linked command"];
		    return;
		    
		case MSG_EXTENDED:
		    /*
		     * The only valid one is sync negotiation....
		     */
		    switch(currMsgIn[index+2]) {
			case MSG_SDTR:
			    if(currMsgIn[index+1] != (MSG_SDTR_LENGTH-2)) {
				[self hwAbort:SR_IOST_BV 
				    reason:"Bad Extended Msg Length"];
				return;
			    }
			    switch(SDTR_State) {
			        case SNS_HOST_INIT:
				    /* 
				     * Just completed SDTR that we initiated.
				     */
				    if([self parseSDTR:&currMsgIn[index]] 
				    		== NO) {
					[self hwAbort:SR_IOST_HW 
					    reason:"Bad SDTR Parameters"];
					return;
				    }
				   
				   /*
				    * Successful SDTR. 
				    */
				    ddm_chip("host-init SDTR COMPLETE\n", 
					1,2,3,4,5);
				    SDTR_State = SNS_NONE;
				    break;
				
				case SNS_TARGET_INIT:
				    /*
				     * Target-initiated negotiation. This
				     * was detected in fsmGettingMsg, where
				     * we set ATN true.
				     * Cons up a response and prime the message 
				     * out state machine to send it.
				     */
				    [self createSDTR : currMsgOut
					    inboundMsg : &currMsgIn[index]];
				    currMsgOutCnt = MSG_SDTR_LENGTH;
				    msgOutState = MOS_WAITING;
				    
				    /*
				     * We have to load target context before 
				     * we send the msg out in case of 
				     * impending data in...
			 	     */
				    if([self parseSDTR:currMsgOut] == NO) {
					    IOPanic("AMD53C974: SDTR "
					    	"Problem\n");
				    }

				    break;
				   
				default:
				    IOPanic("AMD53C974: Bad SDTR_State");
			    }
			    
			    /*
			     * Skip over the rest of this message; index
			     * should point to the last byte of this message.
			     */
			    index += (MSG_SDTR_LENGTH - 1);
			    break;
    
			default:
			    IOLog("AMD53C974: Unexpected Extended Message "
				    "(0x%x) Received\n",
				    currMsgIn[index+2]);
			    [self hwAbort:SR_IOST_BV reason:NULL];
			    return;
		    }	
		    break;
		    		
		default:
		    /*
		     * all others are unacceptable. 
		     */
		    IOLog("AMD53C974: Illegal message (0x%x)\n", 
			    currMsgIn[index]);
		    [self messageOut:MSG_MSGREJECT];
	    } 
	} /* for index */
	
	/*
	 * Default case for 'break' from above switch - back to following 
	 * phase changes.
	 */
	scState = SCS_INITIATOR;
}

/*
 * Just completed the SCMD_TRANSFER_INFO operation for message out. 
 */
- (void)fsmSendingMsg
{
	ddm_chip("fsmSendingMsg\n", 1,2,3,4,5);
	ASSERT(activeCmd != NULL);
	scState = SCS_INITIATOR;
	if(SDTR_State == SNS_TARGET_INIT) {
		/*
		 * If the message we just sent was a SDTR, we've just 
		 * completed a target-initiated SDTR sequence. 
		 * Note this assumes that an outbound SDTR in this 
		 * situation is the only message in currMsgOut[].
		 * This will have to change if we send a queue tag and
		 * SDTR in the sqame message.
		 */
		if((currMsgOutCnt == MSG_SDTR_LENGTH) &&
		   (currMsgOut[0] == MSG_EXTENDED) &&
		   (currMsgOut[1] == (MSG_SDTR_LENGTH - 2)) &&
		   (currMsgOut[2] == MSG_SDTR)) {
			
		 	ddm_chip("fsmSendingMsg: target-init SDTR complete\n",
				1,2,3,4,5);
			/*
			 * Note that we loaded target context before we 
			 * sent the msg out in case of impending data in...
			 */
			SDTR_State = SNS_NONE;
		}
	}
}


/*
 * Just completed the SCMD_TRANSFER_INFO operation for command.
 */
- (void)fsmSendingCmd
{
	ddm_chip("fsmSendingCmd\n", 1,2,3,4,5);
	ASSERT(activeCmd != NULL);
	scState = SCS_INITIATOR;
}

/*
 * Follow SCSI Phase change. Called while SCS_INITIATOR. 
 */
- (void)fsmPhaseChange
{
	int 		phase;
	char 		*cp;
	cdb_t 		*cdbp;
	int 		i;
	sc_status_t 	rtn;
	
	ddm_chip("fsmPhaseChange\n", 1,2,3,4,5);
	ASSERT(activeCmd != NULL);

	/*
	 * Advance msg out state machine -- SCSI spec says if
	 * we do a msg out phase and then see another phase
	 * we can assume msg was transmitted without error.
	 * However, if we're in msg in, we may have a message reject
	 * coming in, so we'll keep currMsgOut[] valid in that case.
	 *
	 * FIXME - one case which this would not cover is the queue tag
	 * message saved in currMsgOut[] during selection. We don't 
	 * go to MOS_SAWMSGOUT in that case. problem?
	 */
	phase = saveStatus & SS_PHASEMASK;
	if ((phase != PHASE_MSGOUT) &&
	    (phase != PHASE_MSGIN) &&
	    (msgOutState == MOS_SAWMSGOUT)) {
		msgOutState = MOS_NONE;
		currMsgOutCnt = 0;
	}

	/*
	 * If we just sent a host-initiated SDTR and the target went 
	 * to something other than phase in, we assume that the negotiation
	 * failed. This is in violation of the spec, but the Sony CDROM 
	 * does this.
	 */
	if((SDTR_State == SNS_HOST_INIT) && (phase != PHASE_MSGIN)) {
		ddm_chip("IMPLIED SNS_HOST_INIT Reject\n", 1,2,3,4,5);
   	        [self disableMode:AM_Sync];
		SDTR_State = SNS_NONE;
	}
	
	/* 
	 * make sure we start off with a clean slate.
	 *
	 * NO - this can disturb possible sync data in! We'll need to cover
	 * this in individual cases elsewhere...
	 */
	/* WRITE_REG(scsiCmd, SCMD_CLEAR_FIFO); */
	ddm_chip("fsmPhaseChange:  phase = %s\n", 
		IOFindNameForValue(phase, scsiPhaseValues), 2,3,4,5);

	switch (phase) {

	    case PHASE_COMMAND:
	    	/*
		 * The normal case here is after a host-initiated SDTR
		 * sequence. 
		 */
		ddm_chip("fsmPhaseChange: command phase\n", 1,2,3,4,5);
		WRITE_REG(scsiCmd, SCMD_CLEAR_FIFO);
		cdbp = &activeCmd->scsiReq->cdb;
		cp = (char *)cdbp;
		for(i=0; i<activeCmd->cdbLength; i++) {
			WRITE_REG(scsiFifo, *cp++);
		}

#if	0
		/*
		 * This causes extra bytes to sit around in the fifo
		 * if we go straight to data phase after this, and
		 * we can't clear the fifo at that time in case
		 * we're in sync data in...
		 */
		/*
		 * fill fifo to avoid spurious command phase for target
		 * chips that try to get max command length
		 */
		for (i = 12 - activeCmd->cdbLength; i > 0; i--)
			WRITE_REG(scsiFifo, 0);
#endif	0
		WRITE_REG(scsiCmd, SCMD_TRANSFER_INFO);
		scState = SCS_SENDINGCMD;
		break;

	    case PHASE_DATAOUT:	/* To Target from Initiator (write) */
		if(activeCmd->scsiReq->read) {
			[self hwAbort:SR_IOST_BV reason:"bad i/o direction"];
			break;
		}
		if(rtn = [self dmaStart]) {
			[self hwAbort:rtn 
				reason: IOFindNameForValue(rtn, 
					IOScStatusStrings)];
			break;
		}
		break;
		
	    case PHASE_DATAIN:	/* From Target to Initiator (read) */
		if(!activeCmd->scsiReq->read) {
			[self hwAbort:SR_IOST_BV reason:"bad i/o direction"];
			break;
		}
		if(rtn = [self dmaStart]) {
			[self hwAbort:rtn 
				reason: IOFindNameForValue(rtn, 
					IOScStatusStrings)];
			break;
		}
		break;
	
	    case PHASE_STATUS:	/* Status from Target to Initiator */
		/*
		 * fsmCompleting will collect the STATUS byte
		 * (and hopefully a MSG) from the fifo when this
		 * completes.
		 */
		scState = SCS_COMPLETING;
		currMsgInCnt = 0;
		WRITE_REG(scsiCmd, SCMD_CLEAR_FIFO);
		WRITE_REG(scsiCmd, SCMD_INIT_CMD_CMPLT);
		break;
		
	    case PHASE_MSGIN:	/* Message from Target to Initiator */
		scState = SCS_GETTINGMSG;
		currMsgInCnt = 0;
		WRITE_REG(scsiCmd, SCMD_CLEAR_FIFO);
		WRITE_REG(scsiCmd, SCMD_TRANSFER_INFO);
		break;
		
	    case PHASE_MSGOUT:	/* Message from Initiator to Target */
	        WRITE_REG(scsiCmd, SCMD_CLEAR_FIFO);
		if(msgOutState == MOS_WAITING) {
			int i;
			
			ASSERT(currMsgOutCnt != 0);
			for(i=0; i<currMsgOutCnt; i++) {
				ddm_chip("msg out: writing 0x%x\n",
					currMsgOut[i], 2,3,4,5);
				WRITE_REG(scsiFifo, currMsgOut[i]);
			}
			msgOutState = MOS_SAWMSGOUT;
			if(SDTR_State == SNS_HOST_INIT_NEEDED) {
				/*
				 * sending SDTR message after select.
				 */
				ASSERT(currMsgOut[0] == MSG_EXTENDED);
				ASSERT(currMsgOut[2] == MSG_SDTR);
				ASSERT(currMsgOutCnt == MSG_SDTR_LENGTH);
				ddm_chip("going to SNS_HOST_INIT\n",
					1,2,3,4,5);
				SDTR_State = SNS_HOST_INIT;
			}
		} else {
			/*
			 * Target went to msg out and we don't have
			 * anything to send!  Just give it a nop.
			 */
			ddm_chip("msg out: sending MSG_NOP\n", 1,2,3,4,5);
			WRITE_REG(scsiFifo, MSG_NOP);
		}

		scState = SCS_SENDINGMSG;
		/* 
		 * ATN is automatically cleared when transfer info completes.
		 */
		WRITE_REG(scsiCmd, SCMD_TRANSFER_INFO);
		break;
		
	    default:
	    	[self hwAbort:SR_IOST_HW reason:"Bad SCSI phase"];
		break;
	}
}

/*
 * Set up to send single-byte message. 
 */ 
- (void) messageOut : (u_char)msg
{
	ddm_chip("messageOut (0x%x)\n", msg, 2,3,4,5);
	currMsgOut[0] = msg;
	currMsgOutCnt = 1;
	msgOutState = MOS_WAITING;
	WRITE_REG(scsiCmd, SCMD_SET_ATN);
}


/*
 * Load syncPeriod, syncOffset for activeCmd per perTarget values.
 */
- (void)targetContext : (unsigned) target
{
	perTargetData *perTargetPtr;
	
	perTargetPtr = &perTarget[target];
	if(!syncModeEnable || 
	   perTargetPtr->syncDisable ||
	   (perTargetPtr->syncXferOffset == 0)) {
		/*
		 * Easy case, async.
		 */
		WRITE_REG(syncOffset, 0);
		ddm_chip("targetContext(%d): ASYNC\n", target, 2,3,4,5);
		#ifdef	DEBUG
		syncOffsetShadow = 0;
		#endif	DEBUG
	}
	else {
		unsigned char periodReg;
		unsigned char offsetReg;
		
		periodReg = nsPeriodToSyncPeriodReg(
			perTargetPtr->syncXferPeriod,
			fastModeEnable, scsiClockRate);
		WRITE_REG(syncPeriod, periodReg);
		
		/*
		 * FIXME - might eventually want to use non-default
		 * values for RAD and RAA...
		 */
		offsetReg = (perTargetPtr->syncXferOffset |
			SOR_RAD_DEFAULT | SOR_RAA_DEFAULT);
		WRITE_REG(syncOffset, offsetReg);
		ddm_chip("targetContext(%d): period 0x%x offset %d\n",
			target, periodReg, offsetReg, 4,5);
		#ifdef	DEBUG
		syncOffsetShadow = offsetReg;
		syncPeriodShadow = periodReg;
		#endif	DEBUG
	}
}

/*
 * Parse and validate 5-byte SDTR message. If valid, save in perTarget 
 * and in hardware. Returns YES if valid, else NO.
 * 
 * Specified message buffer could be from either currMsgIn[] or 
 * currMsgOut[].
 */
- (BOOL)parseSDTR    : (unsigned char *)sdtrMessage
{
	unsigned nsPeriod;
	unsigned char fastClock;
	unsigned minPeriod;
	perTargetData *perTargetPtr;
	
	ASSERT(activeCmd != NULL);
	perTargetPtr = &perTarget[activeCmd->scsiReq->target];
	
	if(sdtrMessage[0] != MSG_EXTENDED) {
		goto Bad;
	}
	if(sdtrMessage[1] != (MSG_SDTR_LENGTH - 2)) {
		goto Bad;
	}
	if(sdtrMessage[2] != MSG_SDTR) {
		goto Bad;
	}
	
	/*
	 * period
	 */
	nsPeriod = SDTR_TO_NS_PERIOD(sdtrMessage[3]);
	fastClock = READ_REG(control3) & CR3_FAST_CLOCK;
	if(fastClock && fastModeEnable) {
		minPeriod = MIN_PERIOD_FASTCLK_FASTSCSI;
	}
	else {
		minPeriod = MIN_PERIOD_NORM;
	}
	if(nsPeriod < minPeriod) {
		goto Bad;
	}
	perTargetPtr->syncXferPeriod = nsPeriod;
	
	/*
	 * Offset
	 */
	if(sdtrMessage[4] > AMD_MAX_SYNC_OFFSET) {
		goto Bad;
	}
	perTargetPtr->syncXferOffset = sdtrMessage[4];
	
	/*
	 * Success.
	 */
	perTargetPtr->syncDisable = 0;
	perTargetPtr->syncNegotNeeded = 0;
	[self targetContext:activeCmd->scsiReq->target];
	
	ddm_chip("parseSDTR SUCCESS: %02x %02x %02x %02x %02x\n",
		sdtrMessage[0], sdtrMessage[1], sdtrMessage[2], 
		sdtrMessage[3], sdtrMessage[4]);
	ddm_chip("   period %d offset %d\n", perTargetPtr->syncXferPeriod,
		perTargetPtr->syncXferOffset, 3,4,5);
	return YES;
	
Bad:
	ddm_chip("parseSDTR FAIL: 02%x %02x %02x %02x %02x\n",
		sdtrMessage[0], sdtrMessage[1], sdtrMessage[2], 
		sdtrMessage[3], sdtrMessage[4]);
	return NO;
}

/*
 * Cons up a SDTR message appropriate for both our hardware and a possible
 * target-generated SDTR message. If inboundMsg is NULL, we just use
 * the parameters we want.
 */
- (void)createSDTR		: (unsigned char *)outboundMsg	// required
		     inboundMsg : (unsigned char *)inboundMsg
{
	unsigned 	desiredNsPeriod;
	unsigned 	inboundNsPeriod;
	unsigned 	offset = AMD_MAX_SYNC_OFFSET;
	unsigned char 	fastClock;
	
	outboundMsg[0] = MSG_EXTENDED;
	outboundMsg[1] = MSG_SDTR_LENGTH - 2;
	outboundMsg[2] = MSG_SDTR;
	
	/*
	 * period
	 */
	fastClock = READ_REG(control3) & CR3_FAST_CLOCK;
	if(fastClock && fastModeEnable) {
		desiredNsPeriod = MIN_PERIOD_FASTCLK_FASTSCSI;
	}
	else {
		desiredNsPeriod = MIN_PERIOD_NORM;
	}
	if(inboundMsg) {
		inboundNsPeriod = SDTR_TO_NS_PERIOD(inboundMsg[3]);
	}
	else {
		inboundNsPeriod = desiredNsPeriod;
	}
	if(inboundNsPeriod > desiredNsPeriod) {
		/*
		 * Target is slower than us
		 */
		desiredNsPeriod = inboundNsPeriod;
	}
	outboundMsg[3] = NS_PERIOD_TO_SDTR(desiredNsPeriod);
	
	/*
	 * Offset
	 */
	if(inboundMsg) {
		offset = inboundMsg[4];
		if(offset > AMD_MAX_SYNC_OFFSET) {
			/* 
			 * target's buffer smaller than ours
			 */
			offset = AMD_MAX_SYNC_OFFSET;
		}
	}
	if(!syncModeEnable) {
		/*
		 * Forget all of this. We won't do sync mode. 
		 */
		offset = 0;
	}
	outboundMsg[4] = offset;
	
	ddm_chip("createSDTR: %02x %02x %02x %02x %02x\n",
		outboundMsg[0], outboundMsg[1], outboundMsg[2], 
		outboundMsg[3], outboundMsg[4]);
	ddm_chip("   period %d   offset %d\n", desiredNsPeriod, offset, 3,4,5);
}

/*
 * Disable specified mode for activeCmd's target. If mode is currently 
 * enabled, we'll log a message to the console.
 */
- (void)disableMode : (AMD_Mode)mode
{
	int target;
	perTargetData *perTargetPtr;
	const char *modeStr = NULL;
	
	ASSERT(activeCmd != NULL);
	target = activeCmd->scsiReq->target;
	perTargetPtr = &perTarget[target];
	switch(mode) {
	    case AM_Sync:
	    	if(perTargetPtr->syncDisable == 0) {
			perTargetPtr->syncDisable = 1;
			modeStr = "Synchronous Transfer Mode";
		}
		[self targetContext:activeCmd->scsiReq->target];
		break;
	    case AM_CmdQueue:
	        if(perTargetPtr->cmdQueueDisable == 0) {
			perTargetPtr->cmdQueueDisable = 1;
			modeStr = "Command Queueing";
		}
		break;
	}
	ddm_chip("DISABLING %s for target %d\n", modeStr, target, 3,4,5);
	if(modeStr) {
		IOLog("AMD53C974: DISABLING %s for target %d\n", 
			modeStr, target);
	}
}

@end	/* AMD_SCSI(ChipPrivate) */
