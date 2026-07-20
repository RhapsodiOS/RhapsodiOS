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

/* AttoScsiExecute.m - Atto SCSI Controller execution routines */

#import "AttoScsiController.h"

@implementation AttoScsiController(Execute)

/*-----------------------------------------------------------------------------*
 * This routine is used to shutdown the script engine in an orderly fashion.
 *
 * Normally the script engine automatically stops when an interrupt is generated.
 * However, in the case of timeouts we need to abort the script engine by setting
 * the ABRT bit in the ISTAT register.
 *
 * The function waits for the abort to complete or times out after 50ms.
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiAbortScript
{
    ns_time_t   currentTime;
    ns_time_t   endTime;

    /*
     * We set the ABRT bit in ISTAT and spin until the script engine acknowledges the
     * abort or we timeout.
     */
    AttoScsiWriteRegs( chipBaseAddr, ISTAT, ISTAT_SIZE, ABRT );

    IOGetTimestamp( &endTime );

    endTime += (kAbortScriptTimeoutMS * 1000 * 1000);

    do
    {
        IOGetTimestamp( &currentTime );

        istatReg = AttoScsiReadRegs( chipBaseAddr, ISTAT, ISTAT_SIZE );

        if ( istatReg & SIP )
        {
            // SCSI interrupt pending - read and clear SIST register
            AttoScsiReadRegs( chipBaseAddr, SIST, SIST_SIZE );
            continue;
        }

        if ( istatReg & DIP )
        {
            // DMA interrupt pending - clear ISTAT and read DSTAT
            AttoScsiWriteRegs( chipBaseAddr, ISTAT, ISTAT_SIZE, 0x00 );
            AttoScsiReadRegs( chipBaseAddr, DSTAT, DSTAT_SIZE );
            break;
        }
    }
    while ( currentTime < endTime );

    // Signal the script processor
    istatReg = SIGP;
    AttoScsiWriteRegs( chipBaseAddr, ISTAT, ISTAT_SIZE, SIGP );

    // If we timed out, reset the SCSI bus
    if ( currentTime >= endTime )
    {
        [self AttoScsiSCSIBusReset: NULL];
    }
}

/*-----------------------------------------------------------------------------*
 * Send an Abort or Bus Device Reset message to a target device.
 *
 * This routine sets up the AbortBdr mailbox with the appropriate SCSI message
 * (either Abort (0x06) or Abort Tag (0x0D)) and signals the script engine
 * to process it.
 *
 * The mailbox contains:
 *   - identify: 0xC0 | LUN (Identify message with disconnect allowed)
 *   - tag: Tag value (or 0 if untagged)
 *   - scsi_id: Target SCSI ID
 *   - message: Abort (0x06) for untagged or Abort Tag (0x0D) for tagged commands
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiAbortBdr:(SRB *)srb
{
    IOAbortBdrMailBox   abortMailBox;
    u_int8_t            messageCode;

    // Save the SRB pointer and set timeout
    abortSRB = srb;
    abortSRBTimeout = 0x0d;

    /*
     * Determine message code based on whether this is a tagged command.
     * If tag < MIN_SCSI_TAG (0x80), this is an untagged command, use Abort (0x06).
     * Otherwise, use Abort Tag (0x0D).
     */
    if ( srb->nexus.tag < MIN_SCSI_TAG )
    {
        messageCode = 0x06;     // Abort message
    }
    else
    {
        messageCode = 0x0d;     // Abort Tag message
    }

    /*
     * Build the abort mailbox:
     *   - identify: LUN with disconnect bit set (0xC0)
     *   - tag: Tag value (or 0 for untagged commands)
     *   - scsi_id: Target ID
     *   - message: Abort or Abort Tag message code
     */
    abortMailBox.identify = srb->lun | 0xC0;
    abortMailBox.tag = (srb->nexus.tag < MIN_SCSI_TAG) ? 0 : srb->nexus.tag;
    abortMailBox.scsi_id = srb->target;
    abortMailBox.message = messageCode;

    // Write the mailbox to the adapter's AbortBdr mailbox location
    adapter->abortBdrMailbox = *(u_int32_t *)&abortMailBox;

    // Signal the script engine to process the abort
    [self AttoScsiSignalScript: srb];
}

/*-----------------------------------------------------------------------------*
 * Timer interrupt handler - called periodically to handle timeout functions.
 *
 * This routine handles timeouts for:
 *   - Reset settle period
 *   - Abort operations
 *   - Individual SRB requests
 *
 * Called every 250ms via ns_timeout.
 *-----------------------------------------------------------------------------*/
- (void) timeoutOccurred
{
    Nexus       *nexus;
    SRB         *srb;
    u_int32_t   i;
    u_int32_t   mailboxNexusIndex = 0xffffffff;
    u_int32_t   currentNexusIndex;

    // Get the mailbox nexus index from the IOdone mailbox if it's valid
    if ( adapter->IOdone_mailbox != 0 )
    {
        mailboxNexusIndex = (u_int8_t)adapter->IOdone_mailbox;
    }

    // Get the current nexus index from the adapter
    currentNexusIndex = EndianSwap32(adapter->nexus_index);

    /*
     * If we are in a reset settle period, suspend all other timing.
     * When the reset settle period completes, return the SRB if the
     * client requested the bus reset. Also unlock the reset semaphore.
     */
    if ( resetQuiesceTimer )
    {
        if ( --resetQuiesceTimer )
        {
            goto timeoutOccurred_Exit;
        }

        if ( resetSRB )
        {
            [resetSRB->srbCmdLock unlockWith: ksrbCmdComplete];
            resetSRB = NULL;
        }
        [resetQuiesceSem unlock];
    }

    /*
     * Check whether an abort for the currently connected target timed out.
     * If it does, then it's likely that the target is hung on the bus.
     * In this case the only recourse is to issue a SCSI bus reset.
     */
    if ( abortCurrentSRB && abortCurrentSRBTimeout )
    {
        if ( !(--abortCurrentSRBTimeout) )
        {
            [self AttoScsiSCSIBusReset: NULL];
            goto timeoutOccurred_Exit;
        }
    }

    /*
     * Check whether a mailbox abort timed out.
     * If so, reset the SCSI bus.
     */
    if ( abortSRB && abortSRBTimeout )
    {
        if ( !(--abortSRBTimeout) )
        {
            [self AttoScsiSCSIBusReset: NULL];
            goto timeoutOccurred_Exit;
        }
    }

    /*
     * Scan the nexus pointer table looking for SRBs to timeout.
     * We check all 256 possible nexus entries.
     */
    for ( i = 0; i < MAX_SCSI_TAG; i++ )
    {
        nexus = adapter->nexusPtrsVirt[i];

        if ( nexus == (Nexus *) -1 )
        {
            continue;
        }

        // Get the SRB from the nexus (nexus is at offset 0x48 in SRB)
        srb = (SRB *)((u_int8_t *)nexus - offsetof(SRB, nexus));

        if ( srb->srbTimeout )
        {
            if ( --(srb->srbTimeout) == 0 )
            {
                // Timeout expired - handle based on which nexus this is

                if ( i == mailboxNexusIndex )
                {
                    // Clear the mailbox index in adapter
                    adapter->IOdone_mailbox = 0;
                }

                if ( i == currentNexusIndex )
                {
                    // This is the currently executing command - abort it
                    [self AttoScsiAbortScript];
                    srb->srbSCSIResult = SR_IOST_IOTO;
                    [self AttoScsiAbortCurrent: srb];
                    AttoScsiWriteRegs( chipBaseAddr, DSP, DSP_SIZE, scriptRestartAddr );
                }
                else
                {
                    // This command is not currently active - complete it with timeout
                    adapter->nexusPtrsVirt[i] = (Nexus *) -1;
                    adapter->nexusPtrsPhys[i] = (Nexus *) -1;
                    srb->srbSCSIResult = SR_IOST_IOTO;
                    srb->srbCmd = ksrbCmdProcessTimeout;
                    [srb->srbCmdLock unlockWith: ksrbCmdComplete];
                }
            }
        }
    }

timeoutOccurred_Exit:
    /*
     * Reschedule the next timer interval (250ms).
     */
    ns_timeout((func)AttoScsiTimerReq, (void *)self,
               (ns_time_t)kSCSITimerIntervalMS * 1000 * 1000,
               (int)CALLOUT_PRI_THREAD);
}

/*-----------------------------------------------------------------------------*
 * Clear the SCSI and DMA FIFOs.
 *
 * This routine flushes the DMA and SCSI FIFOs by:
 *   1. Checking and clearing CTEST5 DFS bit if set
 *   2. Setting CTEST3 CLF bit to clear DMA FIFO
 *   3. Setting DFIFO FLF bit to flush DMA FIFO
 *   4. Polling until all FIFO bits are clear
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiClearFifo
{
    u_int8_t    ctest5Val;
    u_int8_t    ctest3Val;
    u_int8_t    dfifoVal;
    u_int32_t   dfifoVal1, dfifoVal2, dfifoVal3;

    // Read CTEST5 and check DFS bit (0x40)
    ctest5Val = AttoScsiReadRegs( chipBaseAddr, CTEST5, CTEST5_SIZE );

    if ( ctest5Val & CTEST5_DFS )
    {
        // If DFS bit is set, write it back to clear
        AttoScsiWriteRegs( chipBaseAddr, CTEST5, CTEST5_SIZE, ctest5Val );
    }

    // Read CTEST3 and set CLF bit (0x04) to clear DMA FIFO
    ctest3Val = AttoScsiReadRegs( chipBaseAddr, CTEST3, CTEST3_SIZE );
    AttoScsiWriteRegs( chipBaseAddr, CTEST3, CTEST3_SIZE, ctest3Val | CTEST3_CLF );

    // Read DFIFO and set FLF bit (0x02) to flush FIFO
    dfifoVal = AttoScsiReadRegs( chipBaseAddr, DFIFO, DFIFO_SIZE );
    AttoScsiWriteRegs( chipBaseAddr, DFIFO, DFIFO_SIZE, dfifoVal | DFIFO_FLF );

    // Poll until FIFOs are clear
    do
    {
        do
        {
            dfifoVal1 = AttoScsiReadRegs( chipBaseAddr, CTEST3, CTEST3_SIZE );
            dfifoVal2 = AttoScsiReadRegs( chipBaseAddr, DFIFO, DFIFO_SIZE );
            dfifoVal3 = AttoScsiReadRegs( chipBaseAddr, DFIFO, DFIFO_SIZE );
        }
        while ( dfifoVal1 & CTEST3_CLF );
    }
    while ( (dfifoVal3 & DFIFO_FLF) || (dfifoVal2 & DFIFO_BO) );
}

/*-----------------------------------------------------------------------------*
 * Abort the currently executing SCSI command.
 *
 * This routine is called when a timeout occurs for the currently active
 * command. It sets up an abort message for the script to process.
 *
 * The routine:
 *   - Checks if an abort is already in progress
 *   - If not, sets up abort with message code (0x06 for untagged, 0x0D for tagged)
 *   - Writes message code to adapter communication area
 *   - Sets script restart address to abort handler (offset 0x7d8)
 *   - Clears FIFOs
 *   - If aborting a different SRB than already in progress, resets the bus
 *
 * Parameters:
 *   srb - SRB to abort, or (SRB *)-1 for general abort
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiAbortCurrent:(SRB *)srb
{
    u_int32_t   messageCode;

    if ( abortCurrentSRB == NULL )
    {
        // No abort currently in progress - start a new one
        abortCurrentSRB = srb;
        abortCurrentSRBTimeout = 0x0d;  // 13 * 250ms = 3.25 seconds

        // Determine message code: Abort (0x06) for untagged, AbortTag (0x0D) for tagged
        messageCode = 0x06;  // Default to Abort message

        if ( (srb != (SRB *)-1) && (srb->nexus.tag > 0x7f) )
        {
            // Tagged command (tag > MIN_SCSI_TAG threshold)
            messageCode = 0x0d;  // Abort Tag message
        }

        // Write message code to adapter (big-endian, in high byte)
        adapter->abortCurrentMessage = EndianSwap32( messageCode << 24 );

        // Set script restart address to abort handler entry point
        scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x7d8;

        // Clear FIFOs before restart
        [self AttoScsiClearFifo];
    }
    else if ( abortCurrentSRB != srb )
    {
        // Already aborting a different SRB - reset the bus
        [self AttoScsiSCSIBusReset: NULL];
    }
}

/*-----------------------------------------------------------------------------*
 * Perform a SCSI bus reset.
 *
 * This routine initiates a SCSI bus reset by setting the RST bit in the
 * SCNTL1 register. The reset is asserted for a brief period and then cleared.
 * After the reset, the bus reset processing routine is called to handle
 * cleanup and notify clients.
 *
 * If this reset was requested by a client (srb != NULL), save the SRB
 * so it can be completed after the reset quiesce period. If a reset is
 * already in progress, return the new SRB immediately with complete status.
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiSCSIBusReset:(SRB *)srb
{
    if ( srb != NULL )
    {
        // If a reset is already in progress, return this SRB immediately
        if ( resetSRB != NULL )
        {
            srb->srbRetryCount = 7;
            [srb->srbCmdLock unlockWith: ksrbCmdComplete];
            return;
        }
        // Save this SRB to be completed after reset quiesce period
        resetSRB = srb;
    }

    // Assert SCSI RST signal via SCNTL1 register
    AttoScsiWriteRegs( chipBaseAddr, SCNTL1, SCNTL1_SIZE, SCNTL1_RST );

    // Brief delay for reset assertion (25 microseconds)
    IODelay(25);

    // Clear SCSI RST signal
    AttoScsiWriteRegs( chipBaseAddr, SCNTL1, SCNTL1_SIZE, 0x00 );
}

/*-----------------------------------------------------------------------------*
 * Handle Wide Data Transfer Request (WDTR) negotiation.
 *
 * This routine processes WDTR messages from targets during negotiation.
 * It checks if the target supports wide transfers and configures the
 * controller accordingly.
 *
 * The routine:
 *   - Checks target capability flags (bit 0x40 = wide capable)
 *   - If not capable, sends message reject
 *   - Otherwise, configures wide transfer parameters
 *   - Updates SCNTL3 register and targetClocks
 *   - Sets target negotiation complete flag (bit 0x80)
 *   - Adjusts message pointers and sets script restart address
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiNegotiateWDTR:(SRB *)srb Nexus:(Nexus *)nexus
{
    u_int8_t    scntl3Value;
    u_int32_t   msgLength;
    u_int32_t   msgData;
    u_int32_t   consumedBytes;
    u_int32_t   targetID;

    // Check if target supports wide transfers (bit 0x40)
    if ( (srb->targetCapabilities & 0x40) == 0 )
    {
        // Target doesn't support wide - send message reject
        [self AttoScsiSendMsgReject: srb];
        return;
    }

    targetID = srb->target;

    // Determine SCNTL3 value based on adapter wide enable setting
    if ( adapter->wideDataXferEnabled == 1 )
    {
        // Enable wide transfers - set EWS bit (0x08)
        scntl3Value = nexus->targetParms[3] | SCNTL3_EWS;
    }
    else
    {
        // Disable wide transfers - clear EWS bit
        scntl3Value = nexus->targetParms[3] & ~SCNTL3_EWS;
    }

    // Update nexus target parameters
    nexus->targetParms[3] = scntl3Value;

    // Update target clocks array (SCNTL3 value stored at offset 3)
    adapter->targetClocks[targetID * 4 + 3] = scntl3Value;

    // Write to SCNTL3 register
    AttoScsiWriteRegs( chipBaseAddr, SCNTL3, SCNTL3_SIZE, scntl3Value );

    // Set negotiation complete flag (bit 0x80) in target flags
    targets[targetID].flags |= 0x80;

    // Get message length from nexus (with endian swap)
    msgLength = EndianSwap32( nexus->msgLength );

    // Calculate bytes consumed from transfer period
    consumedBytes = srb->transferPeriod - msgLength;

    if ( consumedBytes == 0 )
    {
        // Message fully consumed - restart at normal entry point (offset 0x428)
        scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x428;
    }
    else
    {
        // Message partially consumed - adjust pointers
        msgLength = consumedBytes;
        nexus->msgLength = EndianSwap32( msgLength );

        // Adjust message data pointer
        msgData = EndianSwap32( nexus->msgData );
        msgData += (srb->transferPeriod - consumedBytes);
        nexus->msgData = EndianSwap32( msgData );

        // Restart at message continuation entry point (offset 0x2d0)
        scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x2d0;
    }
}

/*-----------------------------------------------------------------------------*
 * Handle Synchronous Data Transfer Request (SDTR) negotiation.
 *
 * This routine processes SDTR messages from targets during negotiation.
 * It checks if the target supports synchronous transfers and configures
 * the controller accordingly.
 *
 * The routine:
 *   - Checks target capability flags (bit 0x80 = sync capable)
 *   - If not capable, sends message reject
 *   - Otherwise, gets period entry from lookup table
 *   - Configures SCNTL3 and SXFER registers with timing parameters
 *   - Updates targetClocks array
 *   - Sets target negotiation complete flag (bit 0x10)
 *   - Sets script restart address to offset 0x428
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiNegotiateSDTR:(SRB *)srb Nexus:(Nexus *)nexus
{
    PeriodEntry *periodEntry;
    u_int8_t    scntl3Value;
    u_int8_t    sxferValue;
    u_int32_t   targetID;

    // Check if target supports synchronous transfers (bit 0x80)
    if ( (srb->targetCapabilities & 0x80) == 0 )
    {
        // Target doesn't support synchronous - send message reject
        [self AttoScsiSendMsgReject: srb];
        return;
    }

    targetID = srb->target;

    // Get period entry based on adapter settings
    periodEntry = GetPeriodEntry( adapter->wideDataXferEnabled, chipClockRate );

    // Build SCNTL3 value by OR'ing current value with period entry bits
    scntl3Value = nexus->targetParms[3] | periodEntry->scntl3Bits;
    nexus->targetParms[3] = scntl3Value;

    // Build SXFER value by OR'ing adapter sync params with period entry bits
    sxferValue = periodEntry->sxferBits | adapter->syncXferParams;
    nexus->targetParms[1] = sxferValue;

    // Update target clocks array
    // SXFER stored at offset 1, SCNTL3 at offset 3 for each target (4 bytes per target)
    adapter->targetClocks[targetID * 4 + 1] = sxferValue;
    adapter->targetClocks[targetID * 4 + 3] = scntl3Value;

    // Write values to chip registers
    AttoScsiWriteRegs( chipBaseAddr, SCNTL3, SCNTL3_SIZE, scntl3Value );
    AttoScsiWriteRegs( chipBaseAddr, SXFER, SXFER_SIZE, sxferValue );

    // Set synchronous negotiation complete flag (bit 0x10) in target flags
    targets[targetID].flags |= 0x10;

    // Set script restart address to normal entry point (offset 0x428)
    scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x428;
}

/*-----------------------------------------------------------------------------*
 * Process "No Nexus" interrupt from script.
 *
 * This routine is called when the script engine encounters a situation where
 * no active nexus is available (no command in progress). It handles various
 * interrupt conditions including successful completion of abort/BDR operations
 * and error conditions.
 *
 * The routine checks:
 *   - SIST register for SCSI interrupt flags
 *   - DSTAT register for DMA interrupt flags
 *   - Script interrupt code from adapter
 *   - Status of abort operations (abortSRB, abortCurrentSRB)
 *
 * Based on these conditions, it either:
 *   - Completes abort/BDR operations
 *   - Clears abort state
 *   - Initiates new abort
 *   - Restarts script at appropriate entry point
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiProcessNoNexus
{
    u_int32_t   dspsValue;
    u_int32_t   scriptIntCode;
    u_int32_t   clearValue = 0;

    // Set default restart address to select phase entry point (offset 0x120)
    scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x120;

    // Read DSPS register (DMA Script Pointer Save) - contains script interrupt code
    dspsValue = AttoScsiReadRegs( chipBaseAddr, DSPS, DSPS_SIZE );

    // Get script interrupt code from adapter and endian swap
    scriptIntCode = EndianSwap32( adapter->scriptIntCode );

    // Check SIST register for SCSI phase mismatch/disconnect (bit 0x04)
    if ( (sistReg & 0x04) == 0 )
    {
        // No phase mismatch - check for gross error (bit 0x400)
        if ( (sistReg & 0x400) == 0 )
        {
            // No gross error - check DSTAT register flags
            if ( (dstatReg & 0x01) == 0 )
            {
                // Illegal instruction or script interrupt - check for single step (bit 0x04)
                if ( dstatReg & 0x04 )
                {
                    // Single step mode active
                    if ( dspsValue == 9 )
                    {
                        // Abort/BDR completed successfully
                        if ( abortSRB != NULL )
                        {
                            [abortSRB->srbCmdLock unlockWith: ksrbCmdComplete];
                            abortSRB = NULL;
                            adapter->abortBdrMailbox = 0;
                        }
                        goto processNoNexus_Restart;
                    }
                    else if ( dspsValue == 10 )
                    {
                        // Abort current completed
                        abortCurrentSRB = NULL;
                        goto processNoNexus_Restart;
                    }
                }
            }
            else
            {
                // Instruction fetch interrupt - read DSP register
                AttoScsiReadRegs( chipBaseAddr, DSP, DSP_SIZE );
            }

            // Unexpected condition - abort current operation
            [self AttoScsiAbortCurrent: (SRB *)-1];
            goto processNoNexus_Restart;
        }

        // Gross error (0x400) - check if it's abort/BDR related (code 0xb)
        if ( (scriptIntCode != 0xb) || (abortSRB == NULL) )
        {
            goto processNoNexus_Restart;
        }

        // Abort/BDR operation completed
        [abortSRB->srbCmdLock unlockWith: ksrbCmdComplete];
        abortSRB = NULL;
        adapter->abortBdrMailbox = 0;
        goto processNoNexus_Restart;
    }

    // Phase mismatch (bit 0x04) occurred
    if ( (scriptIntCode != 0xb) || (abortSRB == NULL) )
    {
        // Not abort-related - check for abort current completion (code 10)
        if ( scriptIntCode == 10 )
        {
            abortCurrentSRB = NULL;
        }
        goto processNoNexus_Restart;
    }

    // Abort/BDR with phase mismatch - operation completed
    [abortSRB->srbCmdLock unlockWith: ksrbCmdComplete];
    abortSRB = NULL;
    adapter->abortBdrMailbox = 0;

processNoNexus_Restart:
    // Restart script if restart address is set
    if ( scriptRestartAddr != 0 )
    {
        AttoScsiWriteRegs( chipBaseAddr, DSP, DSP_SIZE, scriptRestartAddr );
    }
}

/*-----------------------------------------------------------------------------*
 * Update the transfer offset for a SCSI data transfer.
 *
 * This routine calculates the current transfer offset by examining the
 * scatter-gather list and determining how much data has been transferred.
 *
 * The calculation depends on whether dataXferCalled is set:
 *   - If dataXferCalled == 0: Use savedDataPtr and walk SG list
 *   - If dataXferCalled != 0: Use currentDataPtr directly
 *
 * For savedDataPtr mode, it sums up completed SG entries and subtracts
 * the wide residual count to get the exact transfer offset.
 *
 * Parameters:
 *   srb - SRB containing transfer state and SG list
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiUpdateXferOffset:(SRB *)srb
{
    u_int32_t   offset;
    u_int32_t   sgIndex;
    u_int32_t   sgLength;
    u_int32_t   firstSGLength;
    u_int32_t   currentSGLength;

    // Check if data transfer has been called
    if ( srb->nexus.dataXferCalled == 0 )
    {
        // Use saved data pointer
        offset = srb->xferDonePhys;

        // Walk scatter-gather list if entries exist
        if ( srb->sgCount != 0 )
        {
            // Get first SG entry length (endian swap)
            firstSGLength = EndianSwap32( srb->sgList[srb->sgCount - 1].length );

            // Get current SG entry length (endian swap)
            currentSGLength = EndianSwap32( srb->sgList[0].length );

            // Add difference between first and current SG entry
            offset += (firstSGLength - currentSGLength);

            // Add up all intermediate SG entries (if sgCount > 2)
            if ( srb->sgCount > 2 )
            {
                for ( sgIndex = 1; sgIndex < (srb->sgCount - 1); sgIndex++ )
                {
                    sgLength = EndianSwap32( srb->sgList[sgIndex].length );
                    offset += sgLength;
                }
            }
        }
    }
    else
    {
        // Use current data pointer
        offset = srb->xferDoneVirt;
    }

    // Subtract wide residual count and store result
    srb->xferOffset = offset - srb->nexus.wideResidCount;
}

/*-----------------------------------------------------------------------------*
 * Check FIFO status and calculate FIFO counts.
 *
 * This routine examines the SCSI controller's FIFOs to determine how much
 * data is still in the FIFOs that hasn't been transferred yet. This is
 * critical for calculating accurate transfer counts.
 *
 * The routine:
 *   - Reads DMA Byte Counter (DBC) register
 *   - Checks DSTAT for DMA FIFO empty flag
 *   - Reads SCSI FIFO registers (SSTAT0, SCNTL2, SODL, SCID)
 *   - Calculates total FIFO count based on transfer phase and wide mode
 *   - Returns DBC + FIFO count
 *
 * Parameters:
 *   srb      - SRB for current transfer
 *   fifoCnt  - Pointer to receive FIFO count
 *
 * Returns:
 *   DMA byte counter + FIFO count (total remaining bytes)
 *-----------------------------------------------------------------------------*/
- (u_int32_t) AttoScsiCheckFifo:(SRB *)srb FifoCnt:(u_int32_t *)fifoCnt
{
    u_int32_t   dbc;
    u_int32_t   scriptIntCode;
    u_int32_t   sstat0;
    u_int32_t   scntl2;
    u_int32_t   sodl;
    u_int32_t   scid;
    u_int32_t   fifoCount = 0;
    u_int32_t   dmaFifoCount = 0;
    BOOL        isDataPhase;
    BOOL        isWideMode;

    // Get script interrupt code and check if this is a data phase (0 or 6)
    scriptIntCode = EndianSwap32( adapter->scriptIntCode );
    isDataPhase = (scriptIntCode == 0) || (scriptIntCode == 6);

    // Check if wide mode should be used (only for data in phase when script code < 2)
    isWideMode = (scriptIntCode < 2) && ((srb->nexus.targetParms[1] & 0x1f) != 0);

    // Read DMA Byte Counter (24-bit value)
    dbc = AttoScsiReadRegs( chipBaseAddr, DBC, DBC_SIZE );
    dbc = dbc & 0xffffff;

    // Check if DMA FIFO has data (DSTAT bit 0x80 == 0 means FIFO not empty)
    if ( (dstatReg & 0x80) == 0 )
    {
        // Read SCSI status and control registers
        sstat0 = AttoScsiReadRegs( chipBaseAddr, SSTAT0, SSTAT0_SIZE );
        scntl2 = AttoScsiReadRegs( chipBaseAddr, SCNTL2, SCNTL2_SIZE );

        if ( (scntl2 & 0x20) == 0 )
        {
            // Narrow SCSI - 7-bit FIFO count
            dmaFifoCount = (sstat0 - dbc) & 0x7f;
        }
        else
        {
            // Wide SCSI - 10-bit FIFO count (2 bits from scntl2, 8 from sstat0)
            dmaFifoCount = (((scntl2 & 0x03) << 8) | sstat0) - dbc;
            dmaFifoCount &= 0x3ff;
        }
    }

    // Read SCSI FIFO registers
    sodl = AttoScsiReadRegs( chipBaseAddr, SODL, SODL_SIZE ) & 0xff;
    scid = AttoScsiReadRegs( chipBaseAddr, SCID, SCID_SIZE ) & 0xff;

    // Calculate FIFO count based on phase and mode
    if ( isDataPhase )
    {
        // Data phase - add byte counts from SODL and SCID bits 5
        fifoCount = dmaFifoCount + ((sodl >> 5) & 1) + ((scid >> 5) & 1);

        if ( isWideMode )
        {
            // Wide mode - add bit 6 counts
            fifoCount += ((sodl >> 6) & 1);
            fifoCount += ((scid >> 6) & 1);
        }
    }
    else if ( isWideMode )
    {
        // Non-data phase with wide mode
        // Re-read SODL and combine with SCID bits
        sodl = AttoScsiReadRegs( chipBaseAddr, SODL, SODL_SIZE );
        fifoCount = dmaFifoCount + ((scid & 0x04) | ((sodl >> 4) & 0x0f));
    }
    else
    {
        // Non-data phase, narrow mode - use bit 7 counts
        fifoCount = dmaFifoCount + (sodl >> 7);
        fifoCount += (scid >> 7);
    }

    // Store FIFO count and return total
    *fifoCnt = fifoCount;
    return dbc + fifoCount;
}

/*-----------------------------------------------------------------------------*
 * Adjust data pointers after a save data pointer or disconnect.
 *
 * This routine is called when a SCSI save data pointer message is received
 * or when adjusting pointers after a phase mismatch. It calculates the
 * current position in the scatter-gather list and adjusts the nexus data
 * pointers accordingly.
 *
 * The routine:
 *   - Calls AttoScsiCheckFifo to get remaining byte count
 *   - Reads DSP to determine current SG list position
 *   - Calculates SG index from DSP relative to SRB physical address
 *   - If ATN (attention) is set, creates save data pointer script entry
 *   - Adjusts current SG entry length and address
 *   - Updates ppSGList pointer and continuation pointers
 *   - Clears dataXferCalled flag
 *
 * Parameters:
 *   srb   - SRB for current transfer
 *   nexus - Nexus structure containing data pointers
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiAdjustDataPtrs:(SRB *)srb Nexus:(Nexus *)nexus
{
    u_int32_t   dbcPlusFifo;
    u_int32_t   fifoCnt;
    u_int32_t   dsp;
    u_int32_t   sgIndex;
    u_int32_t   sgEntryCount;
    u_int32_t   scntl2;
    u_int32_t   sgPhysAddr;
    u_int32_t   sgLength;
    u_int32_t   sgAddr;
    u_int32_t   adjustedLength;
    u_int32_t   adjustedAddr;
    u_int32_t   tempValue;

    // Get DMA byte counter plus FIFO count
    dbcPlusFifo = [self AttoScsiCheckFifo: srb FifoCnt: &fifoCnt];

    // Read DSP register to see where script stopped
    dsp = AttoScsiReadRegs( chipBaseAddr, DSP, DSP_SIZE );

    // Calculate scatter-gather index from DSP
    // DSP points into the SG list at: srbPhysAddr + 0x8c + (sgIndex * 8)
    // So: sgIndex = (DSP - 0x8c - srbPhysAddr) / 8
    sgIndex = ((dsp - 0x8c) - srb->srbPhysAddr) >> 3;

    // Adjust to get entry from end (last entry is at sgCount-1)
    sgEntryCount = sgIndex - 1;

    // Check if index is valid (< 67 entries)
    if ( sgEntryCount < 0x43 )
    {
        // Check SCNTL2 for ATN (attention) bit
        scntl2 = AttoScsiReadRegs( chipBaseAddr, SCNTL2, SCNTL2_SIZE );

        if ( scntl2 & 0x01 )  // ATN bit set
        {
            // Create save data pointer script entry in adapter
            // Set length with ATN flag
            tempValue = srb->srbFlags | 1;
            adapter->saveDataLength = EndianSwap32( tempValue );

            // Set address to current SG entry
            adapter->saveDataAddr = ((SGEntry *)&nexus->targetParms[0])[sgEntryCount].physAddr;

            // Set command (0x880 = SCSI MOVE command)
            adapter->saveDataCmd = 0x880;

            // Set jump address to save data pointer handler
            tempValue = (u_int32_t)chipBaseAddrPhys + 0x270;
            adapter->saveDataJump = EndianSwap32( tempValue );

            // Decrement FIFO count by 1
            dbcPlusFifo -= 1;

            // Set script restart to save data pointer entry
            scriptRestartAddr = (u_int32_t)chipRamAddrVirt + 0x848;
        }

        // Get current SG entry (counting from end of list)
        sgLength = EndianSwap32( ((SGEntry *)&nexus->targetParms[0])[sgEntryCount].length );
        sgAddr = EndianSwap32( ((SGEntry *)&nexus->targetParms[0])[sgEntryCount].physAddr );

        // Adjust length: add FIFO count plus srbFlags
        adjustedLength = dbcPlusFifo | srb->srbFlags;
        ((SGEntry *)&nexus->targetParms[0])[0].length = EndianSwap32( adjustedLength );

        // Adjust address: add bytes already transferred
        adjustedAddr = sgAddr + (sgLength - dbcPlusFifo);
        ((SGEntry *)&nexus->targetParms[0])[0].physAddr = EndianSwap32( adjustedAddr );

        // If not the last entry, set up continuation
        if ( sgEntryCount != 0 )
        {
            // Calculate physical address of next SG entry
            sgPhysAddr = srb->srbPhysAddr + 0x8c + (sgEntryCount * 8);

            // Set indirect pointer: command + address
            ((u_int32_t *)&nexus->targetParms[0])[3] = 0x880;  // MOVE command
            tempValue = sgPhysAddr + 8;  // Point to next entry
            ((u_int32_t *)&nexus->targetParms[0])[4] = EndianSwap32( tempValue );

            // Store SG entry count (offset from nexus: 0x40 = sgCount in SRB)
            ((u_int32_t *)&nexus->targetParms[0])[0x40/4] = sgIndex;
        }

        // Update ppSGList to point to current SG entry physical address
        sgPhysAddr = srb->srbPhysAddr + 0x8c;
        nexus->ppSGList = EndianSwap32( sgPhysAddr );

        // Clear dataXferCalled flag
        nexus->dataXferCalled = 0;
    }
    else
    {
        // SG index out of range - abort
        [self AttoScsiAbortCurrent: srb];
    }
}

/*-----------------------------------------------------------------------------*
 * Issue a REQUEST SENSE command to retrieve extended error information.
 *
 * This routine is called when a SCSI command completes with CHECK CONDITION
 * status (0x02). It builds and issues an automatic REQUEST SENSE command to
 * get the sense data from the target.
 *
 * The routine:
 *   - Decrements adapter counter and saves mailbox index
 *   - Sets timeout to 13 * 250ms = 3.25 seconds
 *   - Sets srbState to 2 (request sense state)
 *   - Sets srbRetryCount to 2
 *   - Builds REQUEST SENSE CDB (opcode 0x03)
 *   - Clears target negotiation flags
 *   - Calls AttoScsiCalcMsgs and AttoScsiUpdateSGList
 *   - Sets up nexus pointers for sense data transfer
 *   - Schedules command and signals script
 *
 * Parameters:
 *   srb - SRB that received CHECK CONDITION status
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiIssueRequestSense:(SRB *)srb
{
    u_int8_t    mailboxIndex;
    u_int32_t   sgPhysAddr;
    u_int32_t   nexusPhysAddr;
    u_int32_t   targetID;

    // Get and decrement mailbox counter
    mailboxIndex = (u_int8_t)(EndianSwap32(adapter->counter) >> 24);
    adapter->counter = EndianSwap32((mailboxIndex - 1) << 24);

    // Set timeout to 13 * 250ms
    srb->srbTimeoutStart = 0x0d;

    // Set state to request sense
    srb->srbState = 2;

    // Set retry count
    srb->srbRetryCount = 2;

    // Clear CDB area (6 bytes for REQUEST SENSE)
    bzero(&srb->scsiCDB[0], 6);

    // Build REQUEST SENSE CDB
    srb->scsiCDB[0] = 0x03;  // REQUEST SENSE opcode

    // Add LUN to byte 1 (bits 5-7)
    srb->scsiCDB[0] |= ((srb->lun & 0x07) << 5);

    // Set allocation length (byte 4) from sense buffer length
    srb->scsiCDB[4] = srb->senseDataLength;

    // Set nexus msgData to 6 (for 6-byte CDB length indicator)
    srb->nexus.msgData = EndianSwap32(0x06000000);

    // Clear target negotiation flags (bits 0x90 = sync + wide negotiation)
    targetID = srb->transferOffset;
    targets[targetID].flags &= 0xffffff6f;

    // Clear target capability negotiation bits
    srb->targetCapabilities &= 0xfc;

    // Calculate messages for this command
    [self AttoScsiCalcMsgs: srb];

    // Clear saved data pointers
    srb->xferDoneVirt = 0;
    srb->xferDonePhys = 0;

    // Set VM task for I/O
    srb->srbVMTask = (void *)IOVmTaskSelf();

    // Set flags to 1 (standard transfer)
    srb->srbFlags = EndianSwap32(1);

    // Set continuation pointers
    srb->savedDataPtr1 = srb->senseDataBuffer;
    srb->savedDataPtr2 = srb->requestDataBuffer;

    // Calculate physical address of sense buffer + 0x9c offset
    sgPhysAddr = srb->srbPhysAddr + 0x9c;
    srb->nexus.currentDataPtr = EndianSwap32(sgPhysAddr);

    // Update scatter-gather list
    [self AttoScsiUpdateSGList: srb];

    // If this is a tagged command (tag > 0x7f), update nexus tables
    if ( srb->nexus.tag > 0x7f )
    {
        // Clear nexus pointers for this tag
        adapter->nexusPtrsVirt[adapter->IOdone_mailbox] = (Nexus *)-1;
        adapter->nexusPtrsPhys[adapter->IOdone_mailbox] = (Nexus *)-1;

        // Calculate new tag from target and LUN
        srb->nexus.tag = srb->target | (srb->lun << 3);

        // Set new nexus pointers
        adapter->nexusPtrsVirt[srb->nexus.tag] = &srb->nexus;

        nexusPhysAddr = srb->srbPhysAddr + 0x48;
        adapter->nexusPtrsPhys[srb->nexus.tag] = (Nexus *)EndianSwap32(nexusPhysAddr);
    }

    // Add to schedule mailbox
    nexusPhysAddr = srb->srbPhysAddr + 0x48;
    adapter->schedMailBox[mailboxIndex - 1] = EndianSwap32(nexusPhysAddr);

    // Signal script to process new command
    [self AttoScsiSignalScript: srb];

    // Clear IOdone mailbox
    adapter->IOdone_mailbox = 0;
}

/*-----------------------------------------------------------------------------*
 * Process SCSI status phase.
 *
 * This routine is called when a SCSI command completes and status is
 * received. It handles CHECK CONDITION by issuing REQUEST SENSE, and
 * handles other statuses appropriately.
 *
 * The routine:
 *   - Sets script restart to select phase (0x120)
 *   - Checks srbState - if 1 (normal command):
 *       - Saves status byte to scsiStatus
 *       - Calls AttoScsiUpdateXferOffset
 *       - If status is CHECK CONDITION (0x02):
 *           - If sense buffer exists, issues REQUEST SENSE and returns TRUE
 *           - Otherwise falls through to complete
 *       - Otherwise sets retry count to 3
 *   - If srbState != 1 and srbRetryCount == 0:
 *       - Returns FALSE (don't complete yet)
 *   - Otherwise sets retry count to 3
 *   - Returns FALSE
 *
 * Parameters:
 *   srb - SRB that received status
 *
 * Returns:
 *   TRUE if REQUEST SENSE was issued (caller should not complete SRB)
 *   FALSE if SRB should be completed normally
 *-----------------------------------------------------------------------------*/
- (BOOL) AttoScsiProcessStatus:(SRB *)srb
{
    // Set default restart address to select phase
    scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x120;

    // Check if this is a normal command completion (srbState == 1)
    if ( srb->srbState == 1 )
    {
        // Save SCSI status byte
        srb->scsiStatus = adapter->scsiStatusByte;

        // Update transfer offset
        [self AttoScsiUpdateXferOffset: srb];

        // Check for CHECK CONDITION status (0x02)
        if ( adapter->scsiStatusByte == 0x02 )
        {
            // Check if autosense buffer is available
            if ( srb->senseDataBuffer != NULL )
            {
                // Issue REQUEST SENSE command
                [self AttoScsiIssueRequestSense: srb];
                return TRUE;  // Don't complete SRB yet
            }
        }

        // Normal completion - set retry count to 3
        srb->srbRetryCount = 3;
        return FALSE;
    }

    // Check if this is a retry situation
    if ( srb->srbRetryCount != 0 )
    {
        // Set retry count to 3 for completion
        srb->srbRetryCount = 3;
    }
    else
    {
        // Still retrying - don't complete yet
        return FALSE;
    }

    return FALSE;
}

/*-----------------------------------------------------------------------------*
 * SCSI message templates for negotiation.
 *
 * These are copied into the message buffer and modified as needed.
 *-----------------------------------------------------------------------------*/
static const u_int8_t kWDTRMessage[4] = {
    MSG_EXTENDED,   // Extended message
    0x02,           // Message length (2 bytes follow)
    MSG_WDTR,       // Wide Data Transfer Request
    0x01            // Transfer width: 1 = 16-bit wide
};

static const u_int8_t kSDTRMessageNarrow[5] = {
    MSG_EXTENDED,   // Extended message
    0x03,           // Message length (3 bytes follow)
    MSG_SDTR,       // Synchronous Data Transfer Request
    0x00,           // Transfer period (filled in at runtime)
    0x00            // REQ/ACK offset (filled in at runtime)
};

static const u_int8_t kSDTRMessageWide[5] = {
    MSG_EXTENDED,   // Extended message
    0x03,           // Message length (3 bytes follow)
    MSG_SDTR,       // Synchronous Data Transfer Request
    0x00,           // Transfer period (filled in at runtime)
    0x00            // REQ/ACK offset (filled in at runtime)
};

/*-----------------------------------------------------------------------------*
 * Calculate SCSI messages for a command.
 *
 * This routine builds the SCSI message bytes needed for the request,
 * including IDENTIFY, SIMPLE QUEUE TAG, and negotiation messages.
 *
 * Messages are stored in scsiCDB[0xc] (offset 0x78 in SRB) and the
 * nexus.msgData field points to their physical address.
 *
 * Parameters:
 *   srb - Pointer to the SRB to calculate messages for
 *
 * Message sequence:
 *   1. IDENTIFY (0x80 or 0xC0 + LUN)
 *   2. SIMPLE QUEUE TAG + tag value (if tagged queuing)
 *   3. WDTR message (if wide negotiation needed)
 *   4. SDTR message (if sync negotiation needed)
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiCalcMsgs:(SRB *)srb
{
    u_int8_t        *msgBuffer;
    u_int8_t        msgCount;
    u_int8_t        identifyMsg;
    u_int8_t        targetCap;
    u_int8_t        targetID;
    u_int32_t       targetFlags;
    u_int32_t       msgPhysAddr;
    BOOL            useTaggedQueuing;
    BOOL            needWDTR;
    BOOL            needSDTR;
    BOOL            initiateSDTR;

    // Get target capabilities
    targetCap = srb->targetCapabilities;
    targetID = srb->target;
    targetFlags = targets[targetID].flags;

    // Message buffer starts at scsiCDB[0xc] (offset 0x78 in SRB)
    msgBuffer = &srb->scsiCDB[0xc];
    msgCount = 0;

    // Set msgData to physical address of message buffer
    msgPhysAddr = srb->srbPhysAddr + 0x78;
    srb->nexus.msgData = EndianSwap32( msgPhysAddr );

    // Build IDENTIFY message
    if ( targetCap & kTargetCapTagQueueEnabled )
    {
        // Tagged queuing enabled - use IDENTIFY with disconnect
        identifyMsg = MSG_IDENTIFY_DISCONNECT | srb->lun;
    }
    else
    {
        // Untagged - simple IDENTIFY
        identifyMsg = MSG_IDENTIFY | srb->lun;
    }
    msgBuffer[msgCount++] = identifyMsg;

    // Check if we should use tagged queuing
    useTaggedQueuing = NO;
    if ( (targetFlags & (kTargetCapTaggedQueuing | kTargetCapTagQueueEnabled)) ==
         (kTargetCapTaggedQueuing | kTargetCapTagQueueEnabled) )
    {
        // Target supports and has enabled tagged queuing
        // Check if SRB wants tagged queuing
        useTaggedQueuing = (targetCap & kTargetCapTaggedQueuing) ? YES : NO;
    }

    // Allocate tag if this is a normal I/O command
    if ( srb->srbState == 0x01 )
    {
        u_int8_t tag;

        // Allocate tag (tagged or untagged)
        [self AttoScsiAllocTag: srb CmdQueue: useTaggedQueuing];

        // Store tag in both nexus and SRB
        tag = srb->tag;
        srb->nexus.tag = tag;

        // If using tagged queuing, add SIMPLE QUEUE TAG message
        if ( useTaggedQueuing )
        {
            msgBuffer[msgCount++] = MSG_SIMPLE_QUEUE_TAG;
            msgBuffer[msgCount++] = tag;
        }
    }

    // Check if WDTR (Wide Data Transfer Request) is needed
    needWDTR = NO;
    if ( (targetFlags & kTargetCapWDTRSupport) == kTargetCapWDTRNeeded )
    {
        needWDTR = YES;

        // Mark that WDTR has been sent
        srb->targetCapabilities |= kNegotiationWDTRSent;

        // Copy WDTR message template
        bcopy( kWDTRMessage, &msgBuffer[msgCount], sizeof(kWDTRMessage) );
        msgCount += sizeof(kWDTRMessage);
    }

    // Check if SDTR (Synchronous Data Transfer Request) is needed
    needSDTR = NO;
    if ( (targetFlags & kTargetCapSDTRSupport) == kTargetCapSDTRSupport )
    {
        // Determine if we should initiate SDTR
        initiateSDTR = NO;

        if ( targetFlags & kTargetCapSDTRInitiator )
        {
            // Initiator flag is set - we initiate if capability bit is NOT set
            if ( !(targetCap & 0x04) )
            {
                initiateSDTR = YES;
            }
        }
        else
        {
            // Initiator flag is clear - we initiate if capability bit IS set
            if ( targetCap & 0x04 )
            {
                initiateSDTR = YES;
            }
        }

        if ( initiateSDTR )
        {
            const u_int8_t *sdtrTemplate;

            needSDTR = YES;

            // Mark that SDTR has been sent
            srb->targetCapabilities |= kNegotiationSDTRSent;

            // Select template based on wide transfer capability
            if ( targetCap & 0x04 )
            {
                sdtrTemplate = kSDTRMessageWide;
            }
            else
            {
                sdtrTemplate = kSDTRMessageNarrow;
            }

            // Copy SDTR message template
            bcopy( sdtrTemplate, &msgBuffer[msgCount], 5 );

            // Fill in negotiation parameters from controller
            msgBuffer[msgCount + 3] = sdtrPeriod;   // Transfer period
            msgBuffer[msgCount + 4] = sdtrOffset;   // REQ/ACK offset

            msgCount += 5;
        }
    }

    // Store total message count in nexus
    // If both WDTR and SDTR are sent, adjust count (WDTR takes precedence)
    if ( needSDTR && needWDTR )
    {
        msgCount -= 5;  // SDTR will be sent in separate phase
    }

    srb->nexus.msgLength = EndianSwap32( (u_int32_t)msgCount );

    // Store message count in transferPeriod field (temporary storage)
    srb->transferPeriod = msgCount;
}

/*-----------------------------------------------------------------------------*
 * Update scatter-gather list for a transfer.
 *
 * This routine updates the scatter-gather list pointers in the nexus
 * to prepare for a data transfer.
 *
 * Parameters:
 *   srb - SRB for transfer
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiUpdateSGList:(SRB *)srb
{
    // Implementation would update nexus SG list pointers
    // For now, this is a placeholder
}

/*-----------------------------------------------------------------------------*
 * Process I/O completion.
 *
 * This routine is called when a SCSI I/O operation completes successfully.
 * It performs final processing before completing the SRB.
 *
 * Parameters:
 *   (implicit) - Uses current interrupt state
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiProcessIODone
{
    // Implementation would perform final I/O completion processing
    // For now, this is a placeholder
}

/*-----------------------------------------------------------------------------*
 * Main interrupt processing routine.
 *
 * This is the primary interrupt handler called when the SCSI controller
 * generates an interrupt. It reads interrupt status registers and dispatches
 * to appropriate handlers based on the interrupt type.
 *
 * The routine handles:
 *   - SCSI bus reset (SIST bit 0x02)
 *   - No nexus situations (nexus index > 0xff or nexus == -1)
 *   - Parity errors (SIST bit 0x01)
 *   - SCSI gross errors (SIST bit 0x08)
 *   - Unexpected disconnect (SIST bit 0x04)
 *   - Phase mismatch (SIST bit 0x80)
 *   - Selection timeout (SIST bit 0x400)
 *   - Script interrupts (DSTAT bit 0x04)
 *   - Illegal instruction (DSTAT bit 0x01)
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiProcessInterrupt
{
    Nexus       *nexus;
    SRB         *srb;
    u_int32_t   nexusIndex;
    u_int32_t   scriptIntCode;
    u_int32_t   dspsValue;
    u_int32_t   fifoCnt;
    u_int32_t   msgLength;
    u_int32_t   msgData;

    // Read DSTAT register and store
    dstatReg = AttoScsiReadRegs( chipBaseAddr, DSTAT, DSTAT_SIZE );

    // Brief delay for register settling
    IODelay(5);

    // Read SIST register and store
    sistReg = AttoScsiReadRegs( chipBaseAddr, SIST, SIST_SIZE );

    // Get script interrupt code
    scriptIntCode = EndianSwap32( adapter->scriptIntCode );

    // Check for SCSI bus reset (SIST bit 0x02)
    if ( sistReg & 0x02 )
    {
        [self AttoScsiProcessSCSIBusReset];
        return;
    }

    // Get nexus index
    nexusIndex = EndianSwap32( adapter->nexus_index );

    // Check if no valid nexus (index > 255)
    if ( nexusIndex > 0xff )
    {
        [self AttoScsiProcessNoNexus];
        return;
    }

    // Get nexus from table
    nexus = adapter->nexusPtrsVirt[nexusIndex];

    // Check if nexus is invalid
    if ( nexus == (Nexus *)-1 )
    {
        [self AttoScsiProcessNoNexus];
        return;
    }

    // Calculate SRB from nexus (nexus is at offset 0x48 in SRB)
    srb = (SRB *)((u_int8_t *)nexus - 0x48);

    // Set default restart address
    scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x270;

    // Check SIST register for various error conditions
    if ( sistReg & 0x01 )
    {
        // Parity error
        srb->srbSCSIResult = 0x15;
        [self AttoScsiAbortCurrent: srb];
        goto processInterrupt_Restart;
    }

    if ( sistReg & 0x08 )
    {
        // SCSI gross error
        srb->srbSCSIResult = 6;
        [self AttoScsiAbortCurrent: srb];
        goto processInterrupt_Restart;
    }

    if ( sistReg & 0x04 )
    {
        // Unexpected disconnect
        if ( srb->srbSCSIResult == 0 )
        {
            srb->srbSCSIResult = 6;
        }

        // Clear nexus pointers
        adapter->nexusPtrsVirt[nexusIndex] = (Nexus *)-1;
        adapter->nexusPtrsPhys[nexusIndex] = (Nexus *)-1;

        // Check if this is abort current completion
        if ( scriptIntCode == 10 )
        {
            abortCurrentSRB = NULL;
        }

        // Complete the SRB
        [srb->srbCmdLock unlockWith: ksrbCmdComplete];

        // Set restart to select phase
        scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x120;
        goto processInterrupt_Restart;
    }

    if ( sistReg & 0x80 )
    {
        // Phase mismatch
        if ( scriptIntCode == 6 )
        {
            // Data in phase mismatch - check FIFO and adjust
            fifoCnt = [self AttoScsiCheckFifo: srb FifoCnt: &fifoCnt];

            // Store FIFO count in wideResidCount
            srb->nexus.wideResidCount = (u_int8_t)fifoCnt;

            // Adjust message length
            msgLength = EndianSwap32( nexus->msgLength );
            msgData = EndianSwap32( nexus->msgData );
            msgLength = (msgLength + msgData) - srb->nexus.wideResidCount;
            nexus->msgLength = EndianSwap32( msgLength );

            // Set message data to residual count
            nexus->msgData = EndianSwap32( srb->nexus.wideResidCount << 24 );

            // Abort current operation
            [self AttoScsiAbortCurrent: srb];
        }
        else if ( scriptIntCode < 2 )
        {
            // Data phase - adjust data pointers
            [self AttoScsiAdjustDataPtrs: srb Nexus: nexus];
        }
        else
        {
            // Other phase mismatch - abort
            srb->srbSCSIResult = 6;
            [self AttoScsiAbortCurrent: srb];
        }

        // Clear FIFOs
        [self AttoScsiClearFifo];
        goto processInterrupt_Restart;
    }

    if ( sistReg & 0x400 )
    {
        // Selection timeout
        srb->srbSCSIResult = 1;

        // Clear nexus pointers
        adapter->nexusPtrsVirt[nexusIndex] = (Nexus *)-1;
        adapter->nexusPtrsPhys[nexusIndex] = (Nexus *)-1;

        // Clear IOdone mailbox
        adapter->IOdone_mailbox = 0;

        // Complete the SRB
        [srb->srbCmdLock unlockWith: ksrbCmdComplete];

        // Set restart to select phase
        scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x120;
        goto processInterrupt_Restart;
    }

    // Check DSTAT register
    if ( dstatReg & 0x04 )
    {
        // Script interrupt - read DSPS register
        dspsValue = AttoScsiReadRegs( chipBaseAddr, DSPS, DSPS_SIZE );

        switch ( dspsValue )
        {
            case 0:
            case 2:
            case 3:
            case 0xc:
                // Various error conditions
                srb->srbSCSIResult = 0xc;
                [self AttoScsiAbortCurrent: srb];
                goto processInterrupt_Restart;

            case 1:
                // Status phase complete
                if ( [self AttoScsiProcessStatus: srb] )
                {
                    // REQUEST SENSE was issued - don't restart yet
                    goto processInterrupt_Restart;
                }
                // Call IODone processing
                [self AttoScsiProcessIODone];
                goto processInterrupt_Restart;

            case 10:
                // Abort current completed
                if ( srb->srbSCSIResult == 0 )
                {
                    srb->srbSCSIResult = 6;
                }

                // Clear nexus pointers
                adapter->nexusPtrsVirt[nexusIndex] = (Nexus *)-1;
                adapter->nexusPtrsPhys[nexusIndex] = (Nexus *)-1;

                // Clear abort state
                abortCurrentSRB = NULL;

                // Complete the SRB
                [srb->srbCmdLock unlockWith: ksrbCmdComplete];

                // Set restart to select phase
                scriptRestartAddr = (u_int32_t)chipBaseAddrPhys + 0x120;
                goto processInterrupt_Restart;

            case 0xd:
                // SDTR negotiation
                [self AttoScsiNegotiateSDTR: srb Nexus: nexus];
                goto processInterrupt_Restart;

            case 0xe:
                // WDTR negotiation
                [self AttoScsiNegotiateWDTR: srb Nexus: nexus];
                goto processInterrupt_Restart;

            case 0xf:
                // Update scatter-gather list
                [self AttoScsiUpdateSGList: srb];

                // Set restart to SG list continuation
                scriptRestartAddr = srb->xferDonePhys + 0x9c;
                goto processInterrupt_Restart;

            default:
                // Unknown script interrupt
                srb->srbSCSIResult = 0xe;
                [self AttoScsiAbortCurrent: srb];
                goto processInterrupt_Restart;
        }
    }

    if ( dstatReg & 0x01 )
    {
        // Illegal instruction / instruction fetch
        AttoScsiReadRegs( chipBaseAddr, DSP, DSP_SIZE );
        srb->srbSCSIResult = 0xe;
        [self AttoScsiAbortCurrent: srb];
        goto processInterrupt_Restart;
    }

processInterrupt_Restart:
    // Restart script if restart address is set
    if ( scriptRestartAddr != 0 )
    {
        AttoScsiWriteRegs( chipBaseAddr, DSP, DSP_SIZE, scriptRestartAddr );
    }
}

/*-----------------------------------------------------------------------------*
 * Send a Message Reject to the target.
 *
 * This routine is called when the controller needs to reject a message
 * from a target (e.g., unsupported negotiation request).
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiSendMsgReject:(SRB *)srb
{
    // Implementation for sending message reject
    // This would set up the script to send a MESSAGE REJECT (0x07) message
    // For now, this is a placeholder
}

/*-----------------------------------------------------------------------------*
 * Signal the script engine to check for new work.
 *
 * Writes the SIGP (Signal Process) bit to the ISTAT register to notify
 * the script engine that there's new work to process.
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiSignalScript:(SRB *)srb
{
    AttoScsiWriteRegs( chipBaseAddr, ISTAT, ISTAT_SIZE, SIGP );
}

/*-----------------------------------------------------------------------------*
 * Process a SCSI bus reset event.
 *
 * This routine is called when a SCSI bus reset is detected. It establishes
 * a settle period where new client requests are blocked and flushes all
 * currently executing SCSI requests back to the client with reset status.
 *
 * The routine handles:
 *   - Setting up reset quiesce timer
 *   - Completing any pending abort operations
 *   - Returning all active SRBs with reset error status
 *   - Clearing all mailboxes and script variables
 *   - Resetting target negotiation state
 *   - Restarting the script engine
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiProcessSCSIBusReset
{
    Nexus       *nexus;
    SRB         *srb;
    u_int32_t   i;

    if ( resetQuiesceTimer == 0 )
    {
        /*
         * Start a new reset quiesce period.
         * Save current sequence number and lock the reset semaphore.
         */
        resetSeqNum = srbSeqNum;
        [resetQuiesceSem lock];
        resetQuiesceTimer = 0x0d;  // 13 * 250ms = 3.25 seconds settle time
        abortCurrentSRB = NULL;

        /*
         * Complete any pending abort operation.
         */
        if ( abortSRB )
        {
            [abortSRB->srbCmdLock unlockWith: ksrbCmdComplete];
            abortSRB = NULL;
        }

        /*
         * Clear the script FIFOs.
         */
        [self AttoScsiClearFifo];

        /*
         * Return all active SRBs in the nexus table back to the client
         * with reset status.
         */
        for ( i = 0; i < MAX_SCSI_TAG; i++ )
        {
            nexus = adapter->nexusPtrsVirt[i];

            if ( nexus == (Nexus *) -1 )
            {
                continue;
            }

            // Get SRB from nexus
            srb = (SRB *)((u_int8_t *)nexus - offsetof(SRB, nexus));

            // Mark as reset error
            srb->srbSCSIResult = SR_IOST_RESET;

            // Clear nexus pointers
            adapter->nexusPtrsVirt[i] = (Nexus *) -1;
            adapter->nexusPtrsPhys[i] = (Nexus *) -1;

            // Complete the SRB
            [srb->srbCmdLock unlockWith: ksrbCmdComplete];
        }

        /*
         * Clear all schedule mailboxes.
         */
        for ( i = 0; i < MAX_SCSI_TAG; i++ )
        {
            adapter->schedMailBox[i] = 0;
        }

        /*
         * Clear script mailboxes and variables.
         */
        adapter->abortBdrMailbox = 0;
        adapter->IOdone_mailbox = 0;
        adapter->counter = 0;
        mailBoxIndex = 0;

        /*
         * Reset target negotiation state for all targets.
         * This clears synchronous/wide negotiation flags.
         */
        for ( i = 0; i < MAX_SCSI_TARGETS; i++ )
        {
            targets[i].flags &= 0xffffff6f;  // Clear negotiation bits
            adapter->targetClocks[i * 4 + 3] = 5;  // Reset SCNTL3 register value
            adapter->targetClocks[i * 4 + 1] = 0;  // Reset SXFER register value
        }

        /*
         * Restart the script at the select phase.
         * Offset 0x120 is the entry point for select phase in the script.
         */
        scriptRestartAddr = (u_int32_t)chipRamAddrPhys + 0x120;
        AttoScsiWriteRegs( chipBaseAddr, DSP, DSP_SIZE, scriptRestartAddr );
    }
    else
    {
        /*
         * Already in reset quiesce period - just extend the timer.
         */
        resetQuiesceTimer = 0x0d;
    }
}

/*-----------------------------------------------------------------------------*
 * Check for pending interrupts.
 *
 * Reads the ISTAT register to check for pending interrupts and stores
 * the value in istatReg for later processing.
 *
 * Returns:
 *   Non-zero if any interrupt bits are set (INTF, SIP, or DIP)
 *   Zero if no interrupts are pending
 *-----------------------------------------------------------------------------*/
- (int) checkForPendingInterrupt
{
    u_int32_t istatValue;

    // Read ISTAT register
    istatValue = AttoScsiReadRegs( chipBaseAddr, ISTAT, ISTAT_SIZE );

    // Store in instance variable
    istatReg = (u_int8_t)istatValue;

    // Return interrupt bits (INTF | SIP | DIP = 0x07)
    return (istatValue & 0x07);
}

/*-----------------------------------------------------------------------------*
 * Interrupt occurred handler.
 *
 * This is the primary interrupt dispatcher called when the SCSI controller
 * signals an interrupt. It checks the ISTAT register to determine the
 * interrupt type and dispatches to the appropriate handler.
 *
 * Interrupt types handled:
 *   - INTF (bit 2): Interrupt on the Fly - I/O completion
 *   - SIP/DIP (bits 0-1): SCSI/DMA interrupt - error or status change
 *-----------------------------------------------------------------------------*/
- (void) interruptOccurred
{
    // Check for Interrupt on the Fly (I/O completion)
    if ( istatReg & 0x04 )
    {
        // Clear INTF by writing any value to ISTAT
        AttoScsiWriteRegs( chipBaseAddr, ISTAT, ISTAT_SIZE, 0x00 );

        // Process I/O completion
        [self AttoScsiProcessIODone];
    }

    // Check for SCSI or DMA interrupt (SIP or DIP bits)
    if ( istatReg & 0x03 )
    {
        // Process the interrupt
        [self AttoScsiProcessInterrupt];
    }
}

/*-----------------------------------------------------------------------------*
 * Process I/O completion.
 *
 * Called when an I/O operation completes successfully (INTF interrupt).
 * This routine:
 *   - Retrieves the completed nexus from the IOdone mailbox
 *   - Updates transfer offset if this was a data transfer
 *   - Checks for INQUIRY command completion
 *   - Clears the nexus pointers
 *   - Completes the SRB back to the client
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiProcessIODone
{
    Nexus       *nexus;
    SRB         *srb;
    u_int8_t    mailboxIndex;

    // Get the mailbox index from the adapter
    mailboxIndex = adapter->IOdone_mailbox;

    // Get the nexus from the mailbox
    nexus = adapter->nexusPtrsVirt[mailboxIndex];

    // Calculate SRB address from nexus (nexus is at offset 0x48 in SRB)
    srb = (SRB *)((u_int8_t *)nexus - 0x48);

    // If this was a data transfer, update the transfer offset
    if ( srb->srbState == 0x01 )
    {
        [self AttoScsiUpdateXferOffset: srb];
    }

    // Clear the nexus pointers
    adapter->nexusPtrsVirt[mailboxIndex] = (Nexus *)-1;
    adapter->nexusPtrsPhys[mailboxIndex] = (Nexus *)-1;

    // Clear the IOdone mailbox
    adapter->IOdone_mailbox = 0;

    // Check if this was an INQUIRY command
    if ( srb->scsiCDB[0] == 0x12 )
    {
        [self AttoScsiCheckInquiryData: srb];
    }

    // Complete the SRB
    [srb->srbCmdLock unlockWith: ksrbCmdComplete];
}

/*-----------------------------------------------------------------------------*
 * Process command queue.
 *
 * This routine processes SRBs from the command queue. It handles different
 * command types:
 *   - ksrbCmdExecuteReq (1): Execute SCSI request
 *   - ksrbCmdResetSCSIBus (2): Reset SCSI bus
 *   - ksrbCmdAbortReq/ksrbCmdBusDevReset (3-4): Abort/BDR operations
 *
 * The routine:
 *   - Dequeues SRBs from the command queue
 *   - Checks for reset quiesce period and fails requests if active
 *   - Dispatches to appropriate handler based on command type
 *   - For execute requests, sets up nexus and schedules via script engine
 *-----------------------------------------------------------------------------*/
- (void) commandRequestOccurred
{
    SRB         *srb;
    SRB         *nextSRB;
    SRB         *queueHead;
    u_int8_t    cmd;
    u_int32_t   nexusPhysAddr;
    u_int8_t    targetID;
    u_int8_t    tag;

    queueHead = (SRB *)&commandQueue;

    while ( TRUE )
    {
        // Lock the command queue
        [queueLock lock];

        // Get the first SRB from the queue
        srb = commandQueue.next;

        // Check if queue is empty
        if ( srb == queueHead )
        {
            [queueLock unlock];
            return;
        }

        // Get next SRB
        nextSRB = srb->nextSRB;

        // Remove SRB from queue
        if ( nextSRB == queueHead )
        {
            // This was the last item
            commandQueue.prev = queueHead;
        }
        else
        {
            // Update next SRB's prev pointer
            nextSRB->prevSRB = queueHead;
        }

        // Advance queue head
        commandQueue.next = nextSRB;

        // Unlock the queue
        [queueLock unlock];

        // Check if we're in reset quiesce period
        if ( resetQuiesceTimer != 0 )
        {
            // Fail the request with reset error
            srb->srbRetryCount = 0x14;
            [srb->srbCmdLock unlockWith: ksrbCmdComplete];
            continue;
        }

        // Get the command type
        cmd = srb->srbCmd;

        // Dispatch based on command type
        if ( cmd == ksrbCmdExecuteReq )
        {
            // Execute SCSI request
            targetID = srb->target;

            // Copy target timing parameters to nexus
            srb->nexus.targetParms[3] =
                adapter->targetClocks[targetID * 4 + 3];
            srb->nexus.targetParms[1] =
                adapter->targetClocks[targetID * 4 + 1];

            // Get tag from nexus
            tag = srb->nexus.tag;

            // Set nexus pointers in the nexus table
            adapter->nexusPtrsVirt[tag] = &srb->nexus;

            // Calculate physical address of nexus
            nexusPhysAddr = srb->srbPhysAddr + 0x48;

            // Set physical nexus pointer (with endian swap)
            adapter->nexusPtrsPhys[tag] = (Nexus *)EndianSwap32( nexusPhysAddr );

            // Add to schedule mailbox
            nexusPhysAddr = srb->srbPhysAddr + 0x48;
            adapter->schedMailBox[mailBoxIndex] = EndianSwap32( nexusPhysAddr );
            mailBoxIndex++;

            // Signal the script to process this request
            [self AttoScsiSignalScript: srb];
        }
        else if ( cmd == ksrbCmdResetSCSIBus )
        {
            // Reset SCSI bus
            [self AttoScsiSCSIBusReset: srb];
        }
        else if ( cmd >= ksrbCmdAbortReq && cmd < ksrbCmdProcessTimeout )
        {
            // Abort or Bus Device Reset
            [self AttoScsiAbortBdr: srb];
        }
    }
}

/*-----------------------------------------------------------------------------*
 * Check INQUIRY data.
 *
 * This routine is called when an INQUIRY command completes. It can be used
 * to check the returned device information and update target capabilities.
 *
 * Parameters:
 *   srb - Pointer to the completed SRB
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiCheckInquiryData:(SRB *)srb
{
    // Placeholder for INQUIRY data checking
    // Would examine the INQUIRY response and update target flags
    // for wide, synchronous, and tagged queuing support
}

/*-----------------------------------------------------------------------------*
 * Update scatter-gather list.
 *
 * This routine is called when the script requests a scatter-gather list
 * update (usually when continuing a multi-segment transfer).
 *
 * Parameters:
 *   srb - Pointer to the SRB whose SG list needs updating
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiUpdateSGList:(SRB *)srb
{
    // Placeholder for SG list update
    // Would advance to next SG entry and update nexus data pointers
}

/*-----------------------------------------------------------------------------*
 * Timer callback function.
 *
 * This is the callback function registered with ns_timeout. It sends an
 * interrupt message to the controller's interrupt port to trigger timeout
 * processing. Called every 250ms to handle various timeout conditions.
 *
 * The message format uses the old Mach 2.x msg_header_t structure.
 *-----------------------------------------------------------------------------*/
IOThreadFunc AttoScsiTimerReq(AttoScsiController *device)
{
    msg_header_t msg;

    // Initialize message header
    bzero(&msg, sizeof(msg));
    msg.msg_simple = 0;
    msg.msg_size = sizeof(msg_header_t);
    msg.msg_type = 0;
    msg.msg_local_port = PORT_NULL;
    msg.msg_remote_port = device->interruptPortKern;
    msg.msg_id = 0x00232323;  // Timer interrupt message ID

    // Send message to interrupt port
    msg_send_from_kernel(&msg, MSG_OPTION_NONE, 0);

    return 0;
}

@end
