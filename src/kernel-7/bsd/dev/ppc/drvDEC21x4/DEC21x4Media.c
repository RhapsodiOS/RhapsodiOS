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
 * DEC21x4Media.c
 *
 * Media selection for the DEC 21x4x driver: SIA and general purpose
 * port programming, link interrupt handling, MII PHY connection
 * management, media detection, the autosense timer state machine and
 * Nway (TP autonegotiation) control.
 *
 * HISTORY
 *
 * Reconstructed for RhapsodiOS from the DEC21x4 code linked into the
 * Mac OS X Server 1.2v3 (kernel 5.6) ppc mach_kernel.
 */

#import <driverkit/generalFuncs.h>
#import <kernserv/ns_timer.h>
#import "DEC21x4Adapter.h"

#define MEDIA_BIT(_m)		(1 << (_m))

/* CSR12 (21041/21142/21143) link code word bits from the partner */
#define DC_CSR12_LP_10BASET	0x00200000
#define DC_CSR12_LP_10BASET_FD	0x00400000
#define DC_CSR12_LP_100BASETX	0x00800000
#define DC_CSR12_LP_100BASETX_FD 0x01000000
#define DC_CSR12_LP_100BASET4	0x02000000
#define DC_CSR12_LP_SELECTOR	0x001f0000
#define DC_CSR12_LP_8023	0x00010000
#define DC_CSR12_ANS_RESTART	0x00001000
#define DC_CSR12_ANS_ACK_DETECT	0x00003000
#define DC_CSR12_ANS_ACK_COMPLETE 0x00004000
#define DC_CSR12_SRA		0x00000100	/* AUI/BNC receive activity */
#define DC_CSR12_SELECTED_AUI	0x00000200

#define NWAY_POLL_COUNT		40

static __inline__ BOOL
is2114x(DC21X4_ADAPTER *Adapter)
{
    return (Adapter->DeviceId == DC21142_CFID ||
	    Adapter->DeviceId == DC21143_CFID);
}

void
scheduleFunc(void (*function)(), void *arg, int msecs)
{
    ns_timeout((func)function, arg, (ns_time_t)msecs * 1000000,
	CALLOUT_PRI_THREAD);
}

void
unscheduleFunc(void (*function)(), void *arg)
{
    ns_untimeout((func)function, arg);
}

/*
 * The 21142/21143 general purpose port lives in CSR15<31:16>; keep the
 * SIA bits in the low half.
 */
void
DC21X4WriteGepRegister(DC21X4_ADAPTER *Adapter, u_long data)
{
    if (is2114x(Adapter)) {
	IODelay(100);
	Adapter->Csr15Shadow = (data << 16) | (u_short)Adapter->Csr15Shadow;
	stwbrx(Adapter->Csr15Shadow,
	    Adapter->PortOffset + (u_short)Adapter->CsrOffset[CSR15]);
    } else {
	stwbrx(data,
	    Adapter->PortOffset + (u_short)Adapter->CsrOffset[CSR12]);
    }
    eieio();
}

void
DC21X4InitializeGepRegisters(DC21X4_ADAPTER *Adapter, BOOL phy)
{
    DC21X4_PHY_MEDIA *phyMedia;
    int i;

    if (phy) {
	DC21X4WriteGepRegister(Adapter,
	    Adapter->PhyMediaInfo[Adapter->PhyNumber].GeneralPurposeCtrl);
	for (i = 0;
	     i < Adapter->PhyMediaInfo[Adapter->PhyNumber].GepSequenceLength;
	     i++) {
	    phyMedia = &Adapter->PhyMediaInfo[Adapter->PhyNumber];
	    DC21X4WriteGepRegister(Adapter, phyMedia->GepSequence[i]);
	}
    } else {
	DC21X4WriteGepRegister(Adapter,
	    Adapter->Media[Adapter->SelectedMedium].GeneralPurposeCtrl);
	DC21X4WriteGepRegister(Adapter,
	    Adapter->Media[Adapter->SelectedMedium].GeneralPurposeData);
    }
}

void
DC21X4InitializeMediaRegisters(DC21X4_ADAPTER *Adapter, BOOL phy)
{
    switch (Adapter->DeviceId) {
    case DC21040_CFID:
    case DC21041_CFID:
	DC2104InitializeSiaRegisters(Adapter);
	break;
    case DC21140_CFID:
	DC21X4InitializeGepRegisters(Adapter, phy);
	break;
    case DC21142_CFID:
    case DC21143_CFID:
	DC21X4InitializeGepRegisters(Adapter, phy);
	DC2104InitializeSiaRegisters(Adapter);
	break;
    }
}

void
DC2104InitializeSiaRegisters(DC21X4_ADAPTER *Adapter)
{
    DC21X4_MEDIA_TABLE *media;
    u_int i;

    DC21X4_WRITE_CSR(Adapter, CSR13, 0);
    for (i = 0; i < 2; i++)
	IODelay(5000);

    if (is2114x(Adapter)) {
	Adapter->Csr15Shadow = (Adapter->Csr15Shadow & 0xffff0000) |
	    (u_short)Adapter->Media[Adapter->SelectedMedium].Csr15;
	stwbrx(Adapter->Csr15Shadow,
	    Adapter->PortOffset + (u_short)Adapter->CsrOffset[CSR15]);
    } else {
	stwbrx(Adapter->Media[Adapter->SelectedMedium].Csr15,
	    Adapter->PortOffset + (u_short)Adapter->CsrOffset[CSR15]);
    }
    eieio();

    media = &Adapter->Media[Adapter->SelectedMedium];
    DC21X4_WRITE_CSR(Adapter, CSR14, media->Csr14);
    DC21X4_WRITE_CSR(Adapter, CSR13, media->Csr13);
}

void
DC21X4StartAdapter(DC21X4_ADAPTER *Adapter)
{
    Adapter->OperationMode |= DC_CSR6_ST | DC_CSR6_SR;

    if (Adapter->DeviceId == DC21040_CFID && Adapter->RevisionNumber == 0) {
	/* first pass 21040: reset the SIA around the start */
	DC21X4_WRITE_CSR(Adapter, CSR13, 0);
	IODelay(1000);
	DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
	DC21X4_WRITE_CSR(Adapter, CSR13,
	    Adapter->Media[Adapter->SelectedMedium].Csr13);
    } else {
	DC21X4_WRITE_CSR(Adapter, CSR6,
	    Adapter->OperationMode & ~(DC_CSR6_ST | DC_CSR6_SR));
	IODelay(1000);
	DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
    }
    eieio();
    IODelay(2000);
}

void
DC21X4StopAdapter(DC21X4_ADAPTER *Adapter)
{
    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_FAIL);
    DC21X4_WRITE_CSR(Adapter, CSR0, DC_CSR0_SWR);
    IODelay(2000);
}

void
DC21X4StopReceiverAndTransmitter(DC21X4_ADAPTER *Adapter)
{
    u_long csr5;
    int i;

    DC21X4_WRITE_CSR(Adapter, CSR6,
	Adapter->OperationMode & ~(DC_CSR6_ST | DC_CSR6_SR));

    /* the read result is not used: this is a fixed 100 ms wait */
    for (i = 0; i < 50; i++) {
	csr5 = DC21X4_READ_CSR(Adapter, CSR5);
	IODelay(2000);
    }
}

/*
 * A PHY was plugged in or removed (GEP interrupt, 21142/21143).
 */
void
HandleGepInterrupt(DC21X4_ADAPTER *Adapter)
{
    u_long csr15;

    csr15 = DC21X4_READ_CSR(Adapter, CSR15);
    if (!(csr15 & Adapter->PhyMediaInfo[Adapter->PhyNumber].Interrupt) ||
	!Adapter->PhyMediaInSrom)
	return;

    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_FAIL);
    Adapter->PhyPresent = DC21X4PhyInit(Adapter);
    if (!Adapter->PhyPresent)
	return;

    if (Adapter->Phy100Sia10 &&
	(Adapter->MiiMediaType & DC21X4_MEDIA_AUTOSENSE)) {
	Adapter->MiiMediaType =
	    (Adapter->MiiMediaType & 0xff00) | DC21X4_MII_MEDIA_AUTOSENSE;
	Adapter->SelectedMedium = DC21X4_MEDIA_10BASET;
    }
    DC21X4SetPhyConnection(Adapter);
    if (Adapter->PhyNwayCapable && (Adapter->MediaType & DC21X4_MEDIA_NWAY))
	DC21X4DisableNway(Adapter);
    DC21X4StartAutoSenseTimer(Adapter, 100);
}

void
HandleLinkFailInterrupt(DC21X4_ADAPTER *Adapter, u_long *status)
{
    u_long nway;
    u_long csr12;

    if (Adapter->SelectedMedium != DC21X4_MEDIA_10BASET)
	return;

    if (Adapter->PhyPresent)
	DC21X4SetPhyControl(Adapter, MII_ADMIN_RESTORE);

    switch (Adapter->DeviceId) {
    case DC21040_CFID:
	DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_FAIL);
	*status &= ~(DC_INT_LC | DC_INT_LNP);
	DC21X4StartAutoSenseTimer(Adapter, 3000);
	return;
    case DC21142_CFID:
    case DC21143_CFID:
	Adapter->TpLinkPassPending = FALSE;
	break;
    case DC21041_CFID:
	break;
    default:
	return;
    }

    nway = Adapter->NwayProtocol;
    switch (nway) {
    case 1:
	DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_FAIL);
	*status &= ~(DC_INT_LC | DC_INT_LNP);
	if (!Adapter->NwayInProgress && Adapter->NwayEnabled)
	    SwitchMediumToTpNway(Adapter);
	return;

    case 2:
	DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_FAIL);
	*status &= ~(DC_INT_LC | DC_INT_LNP);
	if (!(Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE) &&
	    !Adapter->NwayEnabled)
	    return;
	if (Adapter->TimerState != DC21X4_TIMER_IDLE)
	    DC21X4StopAutoSenseTimer(Adapter);
	Adapter->TimerState = DC21X4_TIMER_NWAY_LINK_FAIL;
	DC21X4StartTimer(Adapter, 5000);
	return;

    case 3:
	csr12 = DC21X4_READ_CSR(Adapter, CSR12) & DC_CSR12_ANS_MASK;
	if ((Adapter->MediaType & DC21X4_MEDIA_NWAY) &&
	    csr12 != DC_CSR12_ANS_RESTART)
	    return;
	break;
    }

    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_FAIL);
    *status &= ~(DC_INT_LC | DC_INT_LNP);
    if (Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE) {
	DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_NONE);
    } else if (Adapter->MediaType & DC21X4_MEDIA_NWAY) {
	if (Adapter->TimerState != DC21X4_TIMER_IDLE)
	    DC21X4StopAutoSenseTimer(Adapter);
	Adapter->TimerState = DC21X4_TIMER_NWAY_LINK_FAIL;
	DC21X4StartTimer(Adapter, 5000);
    }
}

void
HandleLinkPassInterrupt(DC21X4_ADAPTER *Adapter, u_long *status)
{
    u_long csr12;
    u_long medium;
    u_long timerState;

    *status &= ~DC_INT_LC;

    switch (Adapter->DeviceId) {
    case DC21041_CFID:
    case DC21142_CFID:
    case DC21143_CFID:
	break;
    default:
	DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	return;
    }

    switch (Adapter->NwayProtocol) {
    case 1:
	if (Adapter->TimerState != DC21X4_TIMER_TP_NWAY) {
	    if (Adapter->SelectedMedium != DC21X4_MEDIA_10BASET ||
		Adapter->NwayOnFirstLinkPass)
		SwitchMediumToTpNway(Adapter);
	    else
		DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	    Adapter->NwayOnFirstLinkPass = FALSE;
	}
	return;

    case 2:
	if (Adapter->NwayEnabled) {
	    if (Adapter->TimerState != DC21X4_TIMER_IDLE)
		DC21X4StopAutoSenseTimer(Adapter);
	    Adapter->TimerState = DC21X4_TIMER_NWAY_LINK_PASS;
	    DC21X4StartTimer(Adapter, 1000);
	    return;
	}
	break;

    case 3:
	if (!Adapter->NwayEnabled) {
	    if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASET)
		return;
	    DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_10BASET);
	    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	    return;
	}
	if (Adapter->TimerState != DC21X4_TIMER_IDLE)
	    DC21X4StopAutoSenseTimer(Adapter);

	/* pick the best medium both ends can do */
	csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	medium = Adapter->SelectedMedium;
	timerState = DC21X4_TIMER_IDLE;
	if (csr12 & DC_CSR12_LPN) {
	    csr12 &= Adapter->NwayLocalAbility;
	    if (csr12 & DC_CSR12_LP_100BASET4) {
		medium = DC21X4_MEDIA_100BASET4;
		timerState = DC21X4_TIMER_NWAY_100_CHECK;
	    } else if (csr12 & DC_CSR12_LP_100BASETX_FD) {
		medium = DC21X4_MEDIA_100BASETX_FD;
		timerState = DC21X4_TIMER_NWAY_100_CHECK;
	    } else if (csr12 & DC_CSR12_LP_100BASETX) {
		medium = DC21X4_MEDIA_100BASETX;
		timerState = DC21X4_TIMER_NWAY_100_CHECK;
	    } else if (!(csr12 & (DC_CSR12_LP_10BASET |
				  DC_CSR12_LP_10BASET_FD))) {
		medium = DC21X4_MEDIA_NONE;
	    } else if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASET) {
		timerState = DC21X4_TIMER_NWAY_10_CHECK;
	    } else {
		medium = DC21X4_MEDIA_10BASET;
		timerState = DC21X4_TIMER_NWAY_LINK_FAIL;
	    }
	} else if (!(csr12 & DC_CSR12_LS100)) {
	    medium = DC21X4_MEDIA_100BASETX;
	} else if (medium == DC21X4_MEDIA_10BASET) {
	    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	} else {
	    medium = DC21X4_MEDIA_10BASET;
	    timerState = DC21X4_TIMER_NWAY_LINK_FAIL;
	}

	if (timerState != DC21X4_TIMER_IDLE) {
	    Adapter->TimerState = timerState;
	    DC21X4StartTimer(Adapter,
		(timerState == DC21X4_TIMER_NWAY_LINK_FAIL) ? 5000 : 1000);
	}
	if (medium != Adapter->SelectedMedium)
	    DC21X4SwitchMedia(Adapter, medium);
	return;
    }

    if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASET) {
	if (Adapter->PhyPresent)
	    Adapter->TpLinkPassPending = TRUE;
	else
	    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
    } else if (Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE) {
	if (Adapter->TimerState != DC21X4_TIMER_IDLE && !Adapter->PhyPresent)
	    DC21X4StopAutoSenseTimer(Adapter);
	DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_10BASET);
    }
}

/*
 * 21143 link changed interrupt.
 */
void
HandleLinkChangeInterrupt(DC21X4_ADAPTER *Adapter)
{
    u_long linkFail100;

    linkFail100 = DC21X4_READ_CSR(Adapter, CSR12) & DC_CSR12_LS100;

    if (Adapter->NwayProtocol == 3) {
	Adapter->TpLinkPassPending = FALSE;
	if (Adapter->TimerState != DC21X4_TIMER_NWAY_10_CHECK &&
	    Adapter->TimerState != DC21X4_TIMER_NWAY_100_CHECK &&
	    linkFail100) {
	    if (Adapter->TimerState != DC21X4_TIMER_IDLE)
		DC21X4StopAutoSenseTimer(Adapter);
	    DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_NONE);
	}
    } else if (Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE) {
	if (linkFail100)
	    DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_NONE);
	else if (Adapter->SelectedMedium != DC21X4_MEDIA_100BASETX)
	    DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_100BASETX);
	else
	    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
    } else {
	DC21X4IndicateMediaStatus(Adapter, linkFail100 == 0);
    }
}

void
SwitchMediumToTpNway(DC21X4_ADAPTER *Adapter)
{
    if (Adapter->TimerState != DC21X4_TIMER_IDLE)
	DC21X4StopAutoSenseTimer(Adapter);
    DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_TP_NWAY);
    Adapter->NwayRetryCount = 0;
    Adapter->NwayPollCount = NWAY_POLL_COUNT;
    Adapter->TimerState = DC21X4_TIMER_TP_NWAY;
    DC21X4StartTimer(Adapter, 100);
}

void
DC21X4EnableInterrupt(DC21X4_ADAPTER *Adapter)
{
    DC21X4_WRITE_CSR(Adapter, CSR7, Adapter->InterruptMask);
}

void
DC21X4DisableInterrupt(DC21X4_ADAPTER *Adapter)
{
    DC21X4_WRITE_CSR(Adapter, CSR7, 0);
}

BOOL
DC21X4PhyInit(DC21X4_ADAPTER *Adapter)
{
    DC21X4_PHY_MEDIA *phyMedia;
    BOOL found;
    BOOL connected = FALSE;
    u_short capabilities;
    int i, j;

    if (!Adapter->PhyMediaInSrom)
	return FALSE;

    Adapter->PhyIsolated = FALSE;

    /* reset sequence (always for the current PHY entry) */
    for (i = 0; i < DC21X4_MAX_PHY; i++) {
	phyMedia = &Adapter->PhyMediaInfo[Adapter->PhyNumber];
	if (phyMedia->ResetSequenceLength) {
	    DC21X4WriteGepRegister(Adapter, phyMedia->GeneralPurposeCtrl);
	    for (j = 0;
		 j < Adapter->PhyMediaInfo[Adapter->PhyNumber].ResetSequenceLength;
		 j++) {
		IODelay(10);
		DC21X4WriteGepRegister(Adapter,
		    Adapter->PhyMediaInfo[Adapter->PhyNumber].ResetSequence[j]);
	    }
	}
    }

    Adapter->PhyNumber = 0;
    found = MiiGenInit(Adapter);
    if (found) {
	capabilities = MiiGenGetCapabilities(Adapter);

	if (Adapter->UseMediaTypeForPhy)
	    Adapter->MiiMediaType =
		ConvertMediaTypeToMiiType[(u_char)Adapter->MediaType] |
		(Adapter->MediaType & 0xff00);
	else
	    Adapter->MiiMediaType = DC21X4_MII_MEDIA_AUTOSENSE;

	Adapter->PhyNwayCapable =
	    (Adapter->MiiMediaType & DC21X4_MEDIA_NWAY) ?
	    ((capabilities & MII_STATUS_NWAY_ABLE) != 0) : FALSE;

	if (is2114x(Adapter))
	    Adapter->Phy100Sia10 = (capabilities & 0xf800) == 0x7800 &&
		(Adapter->PhyMediaInfo[Adapter->PhyNumber].MediaCapabilities &
		 0xf800) == 0x6000;

	for (i = 0; i < DC21X4_MAX_PHY; i++) {
	    phyMedia = &Adapter->PhyMediaInfo[i];
	    phyMedia->MediaCapabilities &= capabilities;
	    if (phyMedia->MediaCapabilities & 0x0800) {	/* 10BaseT */
		Adapter->MediaNwayAdvertisement |= 0x00000040;
		Adapter->NwayLocalAbility |= DC_CSR12_LP_10BASET;
	    }
	    if (phyMedia->MediaCapabilities & 0x1000) {	/* 10BaseT FD */
		Adapter->MediaNwayAdvertisement |= 0x00000240;
		Adapter->NwayLocalAbility |= DC_CSR12_LP_10BASET_FD;
	    }
	    if (phyMedia->MediaCapabilities & 0x2000) {	/* 100BaseTX */
		Adapter->MediaNwayAdvertisement |= 0x00010000;
		Adapter->NwayLocalAbility |= DC_CSR12_LP_100BASETX;
	    }
	    if (phyMedia->MediaCapabilities & 0x4000) {	/* 100BaseTX FD */
		Adapter->MediaNwayAdvertisement |= 0x00020200;
		Adapter->NwayLocalAbility |= DC_CSR12_LP_100BASETX_FD;
	    }
	    if (phyMedia->MediaCapabilities & 0x8000) {	/* 100BaseT4 */
		Adapter->MediaNwayAdvertisement |= 0x00040000;
		Adapter->NwayLocalAbility |= DC_CSR12_LP_100BASET4;
	    }
	    phyMedia->MediaCapabilities |= capabilities & MII_STATUS_NWAY_ABLE;
	    Adapter->Phy[i]->PhyCapabilities = phyMedia->MediaCapabilities;
	}
    }

    if (found) {
	connected = MiiGenCheckConnection(Adapter,
	    (u_short)Adapter->MiiMediaType);
	if (!connected)
	    DC21X4SetPhyControl(Adapter, MII_ADMIN_FORCE_10);
    }

    return (found && connected);
}

BOOL
DC21X4SetPhyConnection(DC21X4_ADAPTER *Adapter)
{
    SetMacConnection(Adapter);
    return MiiGenSetConnection(Adapter, Adapter->MiiMediaType,
	Adapter->PhyMediaInfo[Adapter->PhyNumber].NwayAdvertisement);
}

/*
 * Set up CSR6 for the medium the PHY is running.
 */
void
SetMacConnection(DC21X4_ADAPTER *Adapter)
{
    u_long mode;

    if (MediaBitTable[(u_char)Adapter->MiiMediaType] == 0)
	return;

    if (Adapter->Phy100Sia10 &&
	!(MediaBitTable[(u_char)Adapter->MiiMediaType] & 0x6000))
	mode = (Adapter->OperationMode | DC_CSR6_HBD) & ~DC_CSR6_PS;
    else
	mode = Adapter->OperationMode | DC_CSR6_PS | DC_CSR6_HBD;

    if ((Adapter->PhyMediaInfo[Adapter->PhyNumber].MediaCapabilities &
	 MediaBitTable[(u_char)Adapter->MiiMediaType]) ||
	Adapter->Phy100Sia10) {
	if (MediaBitTable[(u_char)Adapter->MiiMediaType] & 0x5000)
	    mode |= DC_CSR6_FD;
	else
	    mode &= ~DC_CSR6_FD;

	if (MediaBitTable[(u_char)Adapter->MiiMediaType] & 0x1800)
	    mode = (mode & ~Adapter->Threshold100Mbps) | DC_CSR6_TTM |
		Adapter->Threshold10Mbps;
	else
	    mode = (mode & ~(Adapter->Threshold10Mbps | DC_CSR6_TTM)) |
		Adapter->Threshold100Mbps;
    }

    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_FAIL);

    if ((mode & (DC_CSR6_TTM | DC_CSR6_FD | DC_CSR6_SF)) !=
	(Adapter->OperationMode & (DC_CSR6_TTM | DC_CSR6_FD | DC_CSR6_SF)))
	DC21X4StopReceiverAndTransmitter(Adapter);

    if (is2114x(Adapter))
	DC2104InitializeSiaRegisters(Adapter);

    Adapter->OperationMode = mode;
    DC21X4_WRITE_CSR(Adapter, CSR6, mode);
    IODelay(5);
    DC21X4InitializeGepRegisters(Adapter, TRUE);
}

BOOL
DC21X4MiiAutoDetect(DC21X4_ADAPTER *Adapter)
{
    BOOL connected;
    u_short status;
    u_short connection;
    int timeout;

    connected = MiiGenGetConnectionStatus(Adapter, &status);
    DC21X4IndicateMediaStatus(Adapter,
	connected ? DC21X4_MII_LINK_PASS : DC21X4_LINK_FAIL);

    timeout = 3500;
    while (!connected && timeout--) {
	IODelay(1000);
	connected = MiiGenGetConnectionStatus(Adapter, &status);
    }

    if (Adapter->MiiMediaType & DC21X4_MEDIA_AUTOSENSE) {
	connected = MiiGenGetConnection(Adapter, &connection);
	if (connected &&
	    Adapter->MiiMediaType != (connection | DC21X4_MEDIA_AUTOSENSE)) {
	    Adapter->MiiMediaType = connection | DC21X4_MEDIA_AUTOSENSE;
	    SetMacConnection(Adapter);
	}
    }

    DC21X4IndicateMediaStatus(Adapter,
	connected ? DC21X4_MII_LINK_PASS : DC21X4_LINK_FAIL);

    if (!connected && Adapter->MediaCapable &&
	(Adapter->MiiMediaType & DC21X4_MEDIA_AUTOSENSE) &&
	(!Adapter->Phy100Sia10 ||
	 (Adapter->MediaCapable & (MEDIA_BIT(DC21X4_MEDIA_10BASE2) |
				   MEDIA_BIT(DC21X4_MEDIA_10BASE5)))))
	SelectNonMiiPort(Adapter);

    return connected;
}

BOOL
DC21X4MiiAutoSense(DC21X4_ADAPTER *Adapter)
{
    BOOL connected;
    BOOL selectNonMii = FALSE;
    u_short status;
    u_short connection;

    connected = MiiGenGetConnectionStatus(Adapter, &status);

    if ((Adapter->MiiMediaType & DC21X4_MEDIA_AUTOSENSE) && connected &&
	(u_char)status == MII_LINK_UP) {
	connected = MiiGenGetConnection(Adapter, &connection);
	/*
	 * MiiMediaType carries the autosense flag and connection does
	 * not, so the first test is always true.
	 */
	if (connected && (Adapter->MiiMediaType != connection ||
			  Adapter->LinkStatus != DC21X4_MII_LINK_PASS)) {
	    Adapter->MiiMediaType = connection | DC21X4_MEDIA_AUTOSENSE;
	    SetMacConnection(Adapter);
	}
    }

    if (connected || Adapter->LinkStatus != DC21X4_LINK_PASS)
	DC21X4IndicateMediaStatus(Adapter,
	    connected ? DC21X4_MII_LINK_PASS : DC21X4_LINK_FAIL);

    if (connected || !Adapter->MediaCapable ||
	!(Adapter->MiiMediaType & DC21X4_MEDIA_AUTOSENSE))
	return connected;

    if ((u_char)status == (u_char)MII_CONN_READ_ERROR) {
	/* the PHY went away */
	Adapter->PhyPresent = FALSE;
	if (Adapter->MediaType & DC21X4_MEDIA_NWAY) {
	    DC21X4EnableNway(Adapter);
	    selectNonMii = TRUE;
	}
    } else if (Adapter->OperationMode & DC_CSR6_PS) {
	selectNonMii = TRUE;
    }

    if (selectNonMii) {
	if ((Adapter->MediaCapable & (MEDIA_BIT(DC21X4_MEDIA_10BASE2) |
				      MEDIA_BIT(DC21X4_MEDIA_10BASE5))) ||
	    !Adapter->Phy100Sia10) {
	    SelectNonMiiPort(Adapter);
	} else if ((u_char)Adapter->MiiMediaType != DC21X4_MII_MEDIA_AUTOSENSE) {
	    Adapter->MiiMediaType =
		(Adapter->MiiMediaType & 0xff00) | DC21X4_MII_MEDIA_AUTOSENSE;
	    Adapter->SelectedMedium = DC21X4_MEDIA_10BASET;
	    SetMacConnection(Adapter);
	}
    }

    return connected;
}

void
SelectNonMiiPort(DC21X4_ADAPTER *Adapter)
{
    u_long mode;

    mode = (Adapter->OperationMode & ~DC_CSR6_MEDIA_MASK) |
	Adapter->Media[Adapter->SelectedMedium].Mode;
    if ((mode & (DC_CSR6_TTM | DC_CSR6_FD | DC_CSR6_SF)) !=
	(Adapter->OperationMode & (DC_CSR6_TTM | DC_CSR6_FD | DC_CSR6_SF)))
	DC21X4StopReceiverAndTransmitter(Adapter);

    Adapter->OperationMode = mode;
    DC21X4_WRITE_CSR(Adapter, CSR6, mode);
    DC21X4InitializeMediaRegisters(Adapter, FALSE);

    if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASE2 ||
	Adapter->SelectedMedium == DC21X4_MEDIA_10BASE5)
	DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
}

void
DC21X4SetPhyControl(DC21X4_ADAPTER *Adapter, u_short control)
{
    MiiGenAdminControl(Adapter, control);
}

/*
 * Find a medium with link at initialization time.
 */
BOOL
DC21X4MediaDetect(DC21X4_ADAPTER *Adapter)
{
    DC21X4_MEDIA_TABLE *media;
    BOOL linkPass = FALSE;
    BOOL txSensed = FALSE;
    u_long csr12;
    u_long medium;
    u_char *packet;
    int i, j, index;

    switch (Adapter->DeviceId) {
    case DC21040_CFID:
	if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASET) {
	    for (;;) {
		csr12 = DC21X4_READ_CSR(Adapter, CSR12);
		if (!(csr12 & DC_CSR12_LS10))
		    break;		/* TP link is up */
		if (!(csr12 & DC_CSR12_LS100) &&
		    (csr12 & (DC_CSR12_LS100 | DC_CSR12_LS10)) == DC_CSR12_LS10)
		    continue;

		if (!(Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE)) {
		    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_FAIL);
		    return FALSE;
		}

		/* try BNC: send ourselves a frame and see if it goes out */
		Adapter->SelectedMedium = DC21X4_MEDIA_10BASE2;
		DC2104InitializeSiaRegisters(Adapter);
		for (i = 0;
		     i < ((int)Adapter->MediaSenseDelay < 30 ?
			  30 : (int)Adapter->MediaSenseDelay);
		     i++)
		    for (j = 0; j < 10; j++)
			IODelay(1000);

		packet = (u_char *)IOMalloc(64);
		if (packet) {
		    bzero(packet, 64);
		    bcopy(Adapter->PermanentAddress, packet, 6);
		    bcopy(Adapter->PermanentAddress, packet + 6, 6);
		    Adapter->TestPacketMode = TRUE;
		    sendPacket(Adapter, packet, 64);
		    IOFree(packet, 64);
		} else {
		    Adapter->TestPacketPollCount = 0;
		}

		if ((Adapter->TestPacketStatus & 0x8000) ||
		    (int)Adapter->TestPacketPollCount <= 0) {
		    /* no luck, fall back to AUI */
		    Adapter->SelectedMedium = DC21X4_MEDIA_10BASE5;
		    DC2104InitializeSiaRegisters(Adapter);
		    DC21X4StartAdapter(Adapter);
		}
		break;
	    }
	}
	DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	return FALSE;

    case DC21140_CFID:
	if (Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE) {
	    IOLog("MediaCount = %d\n", Adapter->MediaCount);
	    for (i = 0; i < Adapter->MediaCount; i++)
		IOLog("%d - %d\n", i, Adapter->MediaPrecedence[i]);

	    DC21X4_WRITE_CSR(Adapter, CSR12,
		Adapter->Media[Adapter->MediaPrecedence[0]].GeneralPurposeCtrl);

	    for (index = Adapter->MediaCount; index > 0; index--) {
		medium = Adapter->MediaPrecedence[index - 1];
		if ((medium == DC21X4_MEDIA_100BASETX ||
		     medium == DC21X4_MEDIA_10BASET) && !txSensed) {
		    linkPass = DC2114Sense100BaseTxLink(Adapter);
		    txSensed = TRUE;
		    if (linkPass)
			break;
		    continue;
		}

		media = &Adapter->Media[medium];
		DC21X4_WRITE_CSR(Adapter, CSR6,
		    (Adapter->OperationMode & ~DC_CSR6_MEDIA_MASK) |
		    media->Mode);
		DC21X4_WRITE_CSR(Adapter, CSR12, media->GeneralPurposeData);
		for (i = 0; i < 200; i++)
		    IODelay(1000);
		csr12 = DC21X4_READ_CSR(Adapter, CSR12);
		linkPass = ((csr12 ^ Adapter->Media[medium].Polarity) &
		    Adapter->Media[medium].SenseMask) != 0;
		if (linkPass) {
		    Adapter->SelectedMedium = medium;
		    Adapter->OperationMode &= ~DC_CSR6_MEDIA_MASK;
		    Adapter->OperationMode |= Adapter->Media[medium].Mode;
		    break;
		}
	    }

	    DC21X4IndicateMediaStatus(Adapter,
		linkPass ? DC21X4_LINK_PASS : DC21X4_LINK_FAIL);

	    if (!linkPass) {
		Adapter->SelectedMedium = Adapter->DefaultMedium;
		Adapter->OperationMode &= ~DC_CSR6_MEDIA_MASK;
		Adapter->OperationMode |=
		    Adapter->Media[Adapter->SelectedMedium].Mode;
		DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
		DC21X4_WRITE_CSR(Adapter, CSR12,
		    Adapter->Media[Adapter->SelectedMedium].GeneralPurposeData);
	    }
	} else {
	    media = &Adapter->Media[Adapter->SelectedMedium];
	    if (!media->SenseMask) {
		if (!Adapter->PhyPresent)
		    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
		return Adapter->PhyPresent;
	    }
	    csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	    DC21X4IndicateMediaStatus(Adapter,
		((csr12 ^ Adapter->Media[Adapter->SelectedMedium].Polarity) &
		 Adapter->Media[Adapter->SelectedMedium].SenseMask) != 0);
	}
	if (!Adapter->AutoSenseCapable)
	    Adapter->MediaType &= ~DC21X4_MEDIA_AUTOSENSE;
	return TRUE;

    case DC21041_CFID:
    case DC21142_CFID:
    case DC21143_CFID:
	if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASE2 ||
	    Adapter->SelectedMedium == DC21X4_MEDIA_10BASE5)
	    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	if (!(Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE))
	    return Adapter->PhyPresent;
	return TRUE;
    }

    return FALSE;
}

/*
 * 21140: look for 100BaseTX link (with and without the scrambler on
 * later revisions), then for 10BaseT link, timing both with the
 * general purpose timer.
 */
BOOL
DC2114Sense100BaseTxLink(DC21X4_ADAPTER *Adapter)
{
    BOOL linkPass = FALSE;
    BOOL scrambler;
    BOOL scramblerFirst;
    u_long mode100;
    u_long csr12;
    int factor;
    int retries;
    int pass;
    int timeout;
    int polls;
    int ticks;
    int firstTick;
    int i;

    DC21X4_WRITE_CSR(Adapter, CSR7, Adapter->InterruptMask & ~DC_INT_GTE);

    mode100 = ((Adapter->OperationMode & ~DC_CSR6_MEDIA_MASK) |
	Adapter->Media[DC21X4_MEDIA_100BASETX].Mode) & ~DC_CSR6_SCR;
    factor = 12;
    if (Adapter->Media[DC21X4_MEDIA_10BASET].Mode & DC_CSR6_PS)
	factor = 3;
    retries = 3;
    scramblerFirst = (Adapter->RevisionNumber != 0x11);

    do {
	scrambler = scramblerFirst;
	pass = 1;
	do {
	    timeout = scrambler ? 2 : 400;
	    polls = 3 * timeout;

	    if (Adapter->MediaCapable & MEDIA_BIT(DC21X4_MEDIA_100BASETX)) {
		DC21X4_WRITE_CSR(Adapter, CSR6,
		    scrambler ? (mode100 | DC_CSR6_SCR) : mode100);
		DC21X4_WRITE_CSR(Adapter, CSR12,
		    Adapter->Media[DC21X4_MEDIA_100BASETX].GeneralPurposeData);
		firstTick = 0;
		ticks = 0;
		DC21X4_WRITE_CSR(Adapter, CSR11, 0x0001001e);
		while (ticks < polls + 1 && !linkPass) {
		    if (DC21X4_READ_CSR(Adapter, CSR5) & DC_INT_GTE) {
			DC21X4_WRITE_CSR(Adapter, CSR5, DC_INT_GTE);
			ticks++;
		    }
		    csr12 = DC21X4_READ_CSR(Adapter, CSR12);
		    if ((csr12 ^
			 Adapter->Media[DC21X4_MEDIA_100BASETX].Polarity) &
			Adapter->Media[DC21X4_MEDIA_100BASETX].SenseMask) {
			if (firstTick == 0)
			    firstTick = ticks + 1;
			else
			    linkPass = (ticks - firstTick >= timeout);
		    } else {
			firstTick = 0;
		    }
		}
		DC21X4_WRITE_CSR(Adapter, CSR11, 0);
		DC21X4_WRITE_CSR(Adapter, CSR5, DC_INT_GTE);

		if (linkPass) {
		    Adapter->SelectedMedium = DC21X4_MEDIA_100BASETX;
		    Adapter->OperationMode &= ~DC_CSR6_MEDIA_MASK;
		    Adapter->OperationMode |=
			Adapter->Media[DC21X4_MEDIA_100BASETX].Mode;
		    if (!scrambler)
			DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
		    break;
		}
	    }

	    if (Adapter->MediaCapable & MEDIA_BIT(DC21X4_MEDIA_10BASET)) {
		DC21X4_WRITE_CSR(Adapter, CSR6,
		    (Adapter->OperationMode & ~DC_CSR6_MEDIA_MASK) |
		    Adapter->Media[DC21X4_MEDIA_10BASET].Mode);
		DC21X4_WRITE_CSR(Adapter, CSR12,
		    Adapter->Media[DC21X4_MEDIA_10BASET].GeneralPurposeData);
		DC21X4_WRITE_CSR(Adapter, CSR11, (polls / 2) * factor);
		while (!linkPass) {
		    /* link must show on two reads in a row */
		    linkPass = TRUE;
		    for (i = 0; i < 2; i++) {
			csr12 = DC21X4_READ_CSR(Adapter, CSR12);
			linkPass = linkPass &&
			    ((csr12 ^
			      Adapter->Media[DC21X4_MEDIA_10BASET].Polarity) &
			     Adapter->Media[DC21X4_MEDIA_10BASET].SenseMask) != 0;
		    }
		    if (DC21X4_READ_CSR(Adapter, CSR5) & DC_INT_GTE)
			break;
		}
	    }

	    if (linkPass) {
		DC21X4_WRITE_CSR(Adapter, CSR11, 0);
		DC21X4_WRITE_CSR(Adapter, CSR5, DC_INT_GTE);
		if (pass) {
		    /* a 10BaseT link on the first pass does not count */
		    linkPass = FALSE;
		} else {
		    Adapter->SelectedMedium = DC21X4_MEDIA_10BASET;
		    Adapter->OperationMode &= ~DC_CSR6_MEDIA_MASK;
		    Adapter->OperationMode |=
			Adapter->Media[DC21X4_MEDIA_10BASET].Mode;
		}
	    } else if (pass) {
		if (!scrambler) {
		    retries = 0;
		    break;
		}
		scrambler = FALSE;
		pass = 2;
	    }
	} while (pass-- && !linkPass);
    } while (retries-- && !linkPass);

    DC21X4_WRITE_CSR(Adapter, CSR5, DC_INT_GTE);
    DC21X4_WRITE_CSR(Adapter, CSR7, Adapter->InterruptMask);
    return linkPass;
}

/*
 * Autosense timer expiry (mediaTimeoutOccurred, under the debugger lock
 * at splnet).
 */
void
DC21X4DynamicAutoSense(void *systemSpecific1, DC21X4_ADAPTER *Adapter,
    void *systemSpecific2, void *systemSpecific3)
{
    BOOL miiLink = FALSE;
    BOOL restart = TRUE;

    if (Adapter->PhyPresent && Adapter->NwayProtocol != 3 &&
	!Adapter->PhyIsolated)
	miiLink = DC21X4MiiAutoSense(Adapter);

    if (Adapter->TpLinkPassPending) {
	Adapter->TpLinkPassPending = FALSE;
	if (!miiLink) {
	    /* TP link up on the SIA: take the PHY off the wire */
	    DC21X4SetPhyControl(Adapter,
		(Adapter->OperationMode & DC_CSR6_FD) ?
		MII_ADMIN_FORCE_10_FD : MII_ADMIN_FORCE_10);
	    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	}
    }

    if (!miiLink && Adapter->MediaCapable)
	restart = DC21X4AutoSense(Adapter);

    if (restart)
	DC21X4StartAutoSenseTimer(Adapter, Adapter->PhyPresent ? 7000 : 3000);
}

/*
 * Returns TRUE if the autosense timer should be restarted.
 */
BOOL
DC21X4AutoSense(DC21X4_ADAPTER *Adapter)
{
    DC21X4_MEDIA_TABLE *media;
    u_long csr12 = 0;
    u_long medium;
    BOOL fullDuplex;
    BOOL switchMedium;
    int index;

    switch (Adapter->DeviceId) {
    case DC21040_CFID:
	if (Adapter->LinkStatus != DC21X4_LINK_FAIL)
	    return FALSE;
	csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	if (csr12 & DC_CSR12_LS10)
	    return TRUE;
	DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	return FALSE;

    case DC21140_CFID:
	media = &Adapter->Media[Adapter->SelectedMedium];
	if (!media->SenseMask)
	    goto linkPass;
	if (!(Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE) &&
	    Adapter->PhyPresent)
	    return TRUE;

	csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	DC21X4IndicateMediaStatus(Adapter,
	    ((csr12 ^ Adapter->Media[Adapter->SelectedMedium].Polarity) &
	     Adapter->Media[Adapter->SelectedMedium].SenseMask) != 0);

	if (Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE) {
	    for (index = Adapter->MediaCount; index > 0; index--) {
		medium = Adapter->MediaPrecedence[index - 1];
		if (Adapter->LinkStatus == DC21X4_LINK_FAIL) {
		    DC21X4SwitchMedia(Adapter, medium);
		    csr12 = DC21X4_READ_CSR(Adapter, CSR12);
		}
		if ((csr12 ^ Adapter->Media[medium].Polarity) &
		    Adapter->Media[medium].SenseMask)
		    break;
	    }
	    if (index > 0) {
		switchMedium = (Adapter->SelectedMedium != medium);
	    } else {
		medium = Adapter->DefaultMedium;
		switchMedium = Adapter->DefaultMediumFound &&
		    Adapter->SelectedMedium != medium;
	    }
	    if (switchMedium) {
		DC21X4SwitchMedia(Adapter, medium);
		csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	    }
	}
	return TRUE;

    case DC21041_CFID:
    case DC21142_CFID:
    case DC21143_CFID:
	break;

    default:
	return TRUE;
    }

    /* 21041, 21142, 21143 */
    if (!(Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE))
	return Adapter->PhyPresent;

    if (Adapter->SkipAutoSense) {
	Adapter->SkipAutoSense = FALSE;
	return FALSE;
    }

    switch (Adapter->TimerState) {
    case DC21X4_TIMER_IDLE:
	return FALSE;

    case DC21X4_TIMER_AUTOSENSE:
	if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASET)
	    return TRUE;
	goto checkNonTp;

    case DC21X4_TIMER_NWAY_LINK_FAIL:
	Adapter->TimerState = DC21X4_TIMER_IDLE;
	if (Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE)
	    DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_NONE);
	return FALSE;

    case DC21X4_TIMER_NWAY_LINK_PASS:
	Adapter->TimerState = DC21X4_TIMER_IDLE;
	csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	if ((csr12 & (DC_CSR12_ANS_MASK | DC_CSR12_LS10)) ==
	    DC_CSR12_ANS_COMPLETE) {
	    if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASET)
		goto linkPass;
	    Adapter->TimerState = DC21X4_TIMER_NWAY_LINK_FAIL;
	    DC21X4StartTimer(Adapter, 5000);
	    DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_10BASET);
	    return FALSE;
	}
	if (Adapter->SelectedMedium != DC21X4_MEDIA_10BASET)
	    goto checkNonTp;
	if (!(Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE))
	    return FALSE;
	DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_NONE);
	return FALSE;

    case DC21X4_TIMER_NWAY_10_CHECK:
	Adapter->TimerState = DC21X4_TIMER_IDLE;
	csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	if ((csr12 & (DC_CSR12_ANS_MASK | DC_CSR12_LS10)) ==
	    DC_CSR12_ANS_COMPLETE)
	    goto linkPass;
	if (!(Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE))
	    return Adapter->PhyPresent;
	DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_NONE);
	return FALSE;

    case DC21X4_TIMER_NWAY_100_CHECK:
	Adapter->TimerState = DC21X4_TIMER_IDLE;
	csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	if (!(csr12 & DC_CSR12_LS100))
	    goto linkPass;
	if (!(Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE))
	    return Adapter->PhyPresent;
	DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_NONE);
	return FALSE;

    case DC21X4_TIMER_TP_NWAY:
	if (Adapter->NwayPollCount-- == 0) {
	    medium = DC21X4_MEDIA_NONE;
	    fullDuplex = FALSE;
	} else {
	    csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	    switch (csr12 & DC_CSR12_ANS_MASK) {
	    case DC_CSR12_ANS_ACK_DETECT:
	    case DC_CSR12_ANS_ACK_COMPLETE:
		Adapter->NwayLinkPartner = csr12;
		DC21X4StartTimer(Adapter, 100);
		return FALSE;
	    case DC_CSR12_ANS_COMPLETE:
		break;
	    default:
		DC21X4StartTimer(Adapter, 100);
		return FALSE;
	    }

	    if (!(csr12 & DC_CSR12_LPN)) {
		/* partner does not negotiate */
		if (++Adapter->NwayRetryCount <= 1) {
		    Adapter->TimerState = DC21X4_TIMER_TP_NWAY_RETRY;
		    DC21X4StartTimer(Adapter, 500);
		    return FALSE;
		}
		medium = DC21X4_MEDIA_10BASET;
		fullDuplex = FALSE;
	    } else if (Adapter->NwayLinkPartner == 0) {
		Adapter->NwayPollCount = NWAY_POLL_COUNT;
		DC21X4_WRITE_CSR(Adapter, CSR12, DC_CSR12_ANS_RESTART);
		Adapter->TimerState = DC21X4_TIMER_TP_NWAY;
		DC21X4StartTimer(Adapter, 100);
		return FALSE;
	    } else if ((Adapter->NwayLinkPartner & DC_CSR12_LP_SELECTOR) !=
		       DC_CSR12_LP_8023) {
		medium = DC21X4_MEDIA_NONE;
		fullDuplex = FALSE;
	    } else if (Adapter->NwayLinkPartner & DC_CSR12_LP_10BASET_FD) {
		medium = DC21X4_MEDIA_10BASET;
		fullDuplex = TRUE;
	    } else if (Adapter->NwayLinkPartner & DC_CSR12_LP_10BASET) {
		medium = DC21X4_MEDIA_10BASET;
		fullDuplex = FALSE;
	    } else {
		medium = DC21X4_MEDIA_NONE;
		fullDuplex = FALSE;
	    }
	}

	Adapter->TimerState = DC21X4_TIMER_IDLE;
	Adapter->NwayLinkPartner = 0;
	DC21X4StopReceiverAndTransmitter(Adapter);
	if (fullDuplex)
	    Adapter->OperationMode |= DC_CSR6_FD;
	else
	    Adapter->OperationMode &= ~DC_CSR6_FD;
	Adapter->NwayInProgress = FALSE;

	if (medium == DC21X4_MEDIA_NONE) {
	    DC21X4SwitchMedia(Adapter, DC21X4_MEDIA_NONE);
	    DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
	    return FALSE;
	}

	/* 10BaseT, Nway done: reprogram the SIA without autonegotiation */
	DC21X4_WRITE_CSR(Adapter, CSR13, 0);
	IODelay(10000);
	DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
	Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 =
	    fullDuplex ? 0x7f3d : 0x7f3f;
	if (is2114x(Adapter)) {
	    Adapter->Csr15Shadow = (Adapter->Csr15Shadow & 0xffff0000) |
		(u_short)Adapter->Media[Adapter->SelectedMedium].Csr15;
	    stwbrx(Adapter->Csr15Shadow,
		Adapter->PortOffset + (u_short)Adapter->CsrOffset[CSR15]);
	} else {
	    stwbrx(Adapter->Media[Adapter->SelectedMedium].Csr15,
		Adapter->PortOffset + (u_short)Adapter->CsrOffset[CSR15]);
	}
	eieio();
	DC21X4_WRITE_CSR(Adapter, CSR14,
	    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14);
	DC21X4_WRITE_CSR(Adapter, CSR13,
	    Adapter->Media[DC21X4_MEDIA_10BASET].Csr13);
	DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	return FALSE;

    case DC21X4_TIMER_TP_NWAY_RETRY:
	Adapter->NwayPollCount = NWAY_POLL_COUNT;
	Adapter->NwayLinkPartner = 0;
	DC21X4_WRITE_CSR(Adapter, CSR12, DC_CSR12_ANS_RESTART);
	Adapter->TimerState = DC21X4_TIMER_TP_NWAY;
	DC21X4StartTimer(Adapter, 100);
	return FALSE;

    default:
	return TRUE;
    }

checkNonTp:
    /* BNC and AUI both fitted: alternate while there is no activity */
    if ((Adapter->MediaCapable & (MEDIA_BIT(DC21X4_MEDIA_10BASE2) |
				  MEDIA_BIT(DC21X4_MEDIA_10BASE5))) ==
	(MEDIA_BIT(DC21X4_MEDIA_10BASE2) | MEDIA_BIT(DC21X4_MEDIA_10BASE5))) {
	csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	if (!(csr12 & DC_CSR12_SRA) ||
	    Adapter->MediaErrorCount[0] > 3 ||
	    Adapter->MediaErrorCount[1] > 3) {
	    Adapter->SelectedMedium =
		(Adapter->SelectedMedium == DC21X4_MEDIA_10BASE2) ?
		DC21X4_MEDIA_10BASE5 : DC21X4_MEDIA_10BASE2;
	    DC21X4_WRITE_CSR(Adapter, CSR15,
		Adapter->Media[Adapter->SelectedMedium].Csr15);
	    Adapter->MediaErrorCount[0] = 0;
	    Adapter->MediaErrorCount[1] = 0;
	}
	DC21X4_WRITE_CSR(Adapter, CSR12, DC_CSR12_SRA);
    }
    return TRUE;

linkPass:
    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
    return Adapter->PhyPresent;
}

void
DC21X4SwitchMedia(DC21X4_ADAPTER *Adapter, u_long medium)
{
    DC21X4_MEDIA_TABLE *media;
    BOOL startTimer = FALSE;
    BOOL programGep = FALSE;
    u_long fullDuplex = 0;
    u_long miiMedia;
    u_long csr12;
    u_int i;

    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_FAIL);

    /* only 10BaseT fitted: nothing to switch to */
    if (medium == DC21X4_MEDIA_NONE &&
	(Adapter->MediaCapable & (MEDIA_BIT(DC21X4_MEDIA_10BASET) |
				  MEDIA_BIT(DC21X4_MEDIA_10BASE2) |
				  MEDIA_BIT(DC21X4_MEDIA_10BASE5))) ==
	MEDIA_BIT(DC21X4_MEDIA_10BASET))
	medium = DC21X4_MEDIA_10BASET;

    switch (Adapter->DeviceId) {
    case DC21140_CFID:
	media = &Adapter->Media[medium];
	Adapter->OperationMode &= ~DC_CSR6_MEDIA_MASK;
	Adapter->SelectedMedium = medium;
	Adapter->OperationMode |= media->Mode;
	DC21X4_WRITE_CSR(Adapter, CSR12, media->GeneralPurposeData);
	DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
	for (i = 0; i < 200; i++)
	    IODelay(1000);
	csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	DC21X4IndicateMediaStatus(Adapter,
	    ((csr12 ^ Adapter->Media[Adapter->SelectedMedium].Polarity) &
	     Adapter->Media[Adapter->SelectedMedium].SenseMask) != 0);
	return;

    case DC21143_CFID:
	if (Adapter->PhyPresent) {
	    miiMedia = ConvertMediaTypeToMiiType[(u_char)medium] |
		(medium & 0xff00);
	    if (MiiGenCheckConnection(Adapter, miiMedia)) {
		Adapter->SelectedMedium = medium;
		Adapter->MiiMediaType = miiMedia;
		DC21X4SetPhyConnection(Adapter);
		DC21X4StartAutoSenseTimer(Adapter, 7000);
		return;
	    }
	}
	programGep = TRUE;
	break;

    case DC21041_CFID:
    case DC21142_CFID:
	break;

    default:
	return;
    }

    /* 21041, 21142, 21143 */
    switch (medium) {
    case DC21X4_MEDIA_10BASET_FD:
	fullDuplex = DC_CSR6_FD;
	/* fall through */
    case DC21X4_MEDIA_10BASET:
	if (programGep) {
	    DC21X4StopReceiverAndTransmitter(Adapter);
	    media = &Adapter->Media[medium];
	    Adapter->OperationMode &= ~DC_CSR6_MEDIA_MASK;
	    Adapter->OperationMode |= media->Mode | fullDuplex;
	    DC21X4WriteGepRegister(Adapter, media->GeneralPurposeCtrl);
	    DC21X4WriteGepRegister(Adapter, media->GeneralPurposeData);
	    DC21X4_WRITE_CSR(Adapter, CSR6,
		Adapter->OperationMode & ~(DC_CSR6_ST | DC_CSR6_SR));
	    IODelay(1000);
	}
	Adapter->SelectedMedium = medium;
	DC2104InitializeSiaRegisters(Adapter);
	if (programGep)
	    DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
	return;

    case DC21X4_MEDIA_100BASETX_FD:
	fullDuplex = DC_CSR6_FD;
	medium = (u_char)medium;
	/* fall through */
    case DC21X4_MEDIA_100BASETX:
    case DC21X4_MEDIA_100BASET4:
	if (programGep) {
	    DC21X4StopReceiverAndTransmitter(Adapter);
	    media = &Adapter->Media[medium];
	    Adapter->OperationMode &= ~DC_CSR6_MEDIA_MASK;
	    Adapter->OperationMode |= media->Mode | fullDuplex;
	    DC21X4WriteGepRegister(Adapter, media->GeneralPurposeCtrl);
	    DC21X4WriteGepRegister(Adapter, media->GeneralPurposeData);
	    DC21X4_WRITE_CSR(Adapter, CSR13, 0);
	    for (i = 0; i < 10; i++)
		IODelay(1000);
	    media = &Adapter->Media[medium];
	    DC21X4_WRITE_CSR(Adapter, CSR14, media->Csr14);
	    Adapter->Csr15Shadow = (Adapter->Csr15Shadow & 0xffff0000) |
		(u_short)media->Csr15;
	    DC21X4_WRITE_CSR(Adapter, CSR15, Adapter->Csr15Shadow);
	    DC21X4_WRITE_CSR(Adapter, CSR6,
		Adapter->OperationMode & ~(DC_CSR6_ST | DC_CSR6_SR));
	    IODelay(1000);
	    DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
	}
	Adapter->SelectedMedium = medium;
	if (Adapter->TimerState != DC21X4_TIMER_NWAY_100_CHECK)
	    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);
	return;

    case DC21X4_MEDIA_10BASE2:
	startTimer = Adapter->MediaCapable & MEDIA_BIT(DC21X4_MEDIA_10BASE5);
	break;

    case DC21X4_MEDIA_10BASE5:
	startTimer = Adapter->MediaCapable & MEDIA_BIT(DC21X4_MEDIA_10BASE2);
	break;

    case DC21X4_MEDIA_NONE:
	/* next non-TP medium */
	switch (Adapter->MediaCapable & (MEDIA_BIT(DC21X4_MEDIA_10BASE2) |
					 MEDIA_BIT(DC21X4_MEDIA_10BASE5))) {
	case MEDIA_BIT(DC21X4_MEDIA_10BASE5):
	    medium = DC21X4_MEDIA_10BASE5;
	    break;
	case MEDIA_BIT(DC21X4_MEDIA_10BASE2) | MEDIA_BIT(DC21X4_MEDIA_10BASE5):
	    csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	    medium = (csr12 & DC_CSR12_SELECTED_AUI) ?
		DC21X4_MEDIA_10BASE5 : DC21X4_MEDIA_10BASE2;
	    startTimer = TRUE;
	    break;
	case MEDIA_BIT(DC21X4_MEDIA_10BASE2):
	    medium = DC21X4_MEDIA_10BASE2;
	    break;
	default:
	    if (Adapter->PhyPresent)
		DC21X4StartAutoSenseTimer(Adapter, 7000);
	    return;
	}
	break;

    case DC21X4_MEDIA_TP_NWAY:
	medium = DC21X4_MEDIA_10BASET;
	Adapter->SelectedMedium = medium;
	Adapter->NwayInProgress = TRUE;
	DC21X4StopReceiverAndTransmitter(Adapter);
	Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 |= 0xc0;
	DC2104InitializeSiaRegisters(Adapter);
	Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 &= ~0xc0;
	Adapter->OperationMode |= DC_CSR6_FD;
	DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
	return;
    }

    /* BNC/AUI (and anything else) */
    if (programGep) {
	media = &Adapter->Media[medium];
	Adapter->OperationMode &= ~DC_CSR6_MEDIA_MASK;
	Adapter->OperationMode |= media->Mode;
	DC21X4WriteGepRegister(Adapter, media->GeneralPurposeCtrl);
	DC21X4WriteGepRegister(Adapter, media->GeneralPurposeData);
	DC21X4_WRITE_CSR(Adapter, CSR6, Adapter->OperationMode);
    }
    Adapter->SelectedMedium = medium;
    DC2104InitializeSiaRegisters(Adapter);
    DC21X4IndicateMediaStatus(Adapter, DC21X4_LINK_PASS);

    if (startTimer || Adapter->PhyPresent) {
	Adapter->MediaErrorCount[0] = 0;
	Adapter->MediaErrorCount[1] = 0;
	DC21X4StartAutoSenseTimer(Adapter,
	    Adapter->PhyPresent ? 7000 : 3000);
    }
}

void
DC21X4StartAutoSenseTimer(DC21X4_ADAPTER *Adapter, u_long msecs)
{
    Adapter->TimerState = DC21X4_TIMER_AUTOSENSE;
    scheduleFunc(mediaTimeoutOccurred, Adapter, msecs);
}

void
DC21X4StartTimer(DC21X4_ADAPTER *Adapter, u_long msecs)
{
    scheduleFunc(mediaTimeoutOccurred, Adapter, msecs);
}

void
DC21X4StopAutoSenseTimer(DC21X4_ADAPTER *Adapter)
{
    Adapter->TimerState = DC21X4_TIMER_IDLE;
    unscheduleFunc(mediaTimeoutOccurred, Adapter);
    Adapter->SkipAutoSense = FALSE;
}

void
DC21X4EnableNway(DC21X4_ADAPTER *Adapter)
{
    u_long csr14Bits;
    u_long modeBits;
    u_long pcsBits;

    switch (Adapter->DeviceId) {
    case DC21041_CFID:
	if (Adapter->RevisionNumber >= 0x10 &&
	    Adapter->RevisionNumber <= 0x11) {
	    Adapter->NwayEnabled = FALSE;
	    Adapter->NwayProtocol = 0;
	    return;
	}
	if (Adapter->RevisionNumber == 0x20) {
	    if (Adapter->ForceNway) {
		Adapter->NwayEnabled = TRUE;
		Adapter->NwayProtocol = 1;
	    } else {
		Adapter->NwayEnabled = FALSE;
		Adapter->NwayProtocol = 0;
	    }
	    return;
	}
	break;

    case DC21142_CFID:
	if (Adapter->RevisionNumber >= 0x10 &&
	    Adapter->RevisionNumber <= 0x11) {
	    if (Adapter->ForceNway) {
		Adapter->NwayEnabled = TRUE;
		Adapter->NwayProtocol = 1;
	    } else {
		Adapter->NwayEnabled = FALSE;
		Adapter->NwayProtocol = 0;
	    }
	    return;
	}
	break;

    case DC21143_CFID:
	Adapter->NwayEnabled = TRUE;
	if (!(Adapter->MediaCapable & MEDIA_BIT(DC21X4_MEDIA_10BASET))) {
	    Adapter->NwayProtocol = 0;
	    return;
	}
	Adapter->NwayProtocol = 3;
	csr14Bits = (Adapter->MediaNwayAdvertisement & 0xff7ffdff) | 0x80;
	Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 |= csr14Bits;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Csr14 |= csr14Bits;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Csr14 |= csr14Bits;
	modeBits = Adapter->MediaNwayAdvertisement &
	    (DC_CSR6_PCS | DC_CSR6_FD);
	Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= modeBits;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Mode |= modeBits;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Mode |= modeBits;
	Adapter->Media[DC21X4_MEDIA_100BASETX_FD].Mode |= modeBits;
	pcsBits = Adapter->MediaNwayAdvertisement & DC_CSR6_PCS;
	Adapter->MediaType &= ~0xff;
	Adapter->Media[DC21X4_MEDIA_100BASETX].Mode |= pcsBits;
	Adapter->Media[DC21X4_MEDIA_100BASET4].Mode |= pcsBits;
	return;

    default:
	return;
    }

    /* 21041 and 21142 with autonegotiation in the SIA */
    Adapter->NwayEnabled = TRUE;
    Adapter->NwayProtocol = 2;
    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 |= 0xc0;
    Adapter->Media[DC21X4_MEDIA_10BASE2].Csr14 |= 0xc0;
    Adapter->Media[DC21X4_MEDIA_10BASE5].Csr14 |= 0xc0;
    Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= DC_CSR6_FD;
    Adapter->Media[DC21X4_MEDIA_10BASE2].Mode |= DC_CSR6_FD;
    Adapter->Media[DC21X4_MEDIA_10BASE5].Mode |= DC_CSR6_FD;
}

void
DC21X4DisableNway(DC21X4_ADAPTER *Adapter)
{
    u_long csr14Bits;

    Adapter->NwayEnabled = FALSE;
    Adapter->NwayProtocol = 0;

    switch (Adapter->DeviceId) {
    case DC21041_CFID:
    case DC21142_CFID:
	csr14Bits = 0xc0;
	break;
    case DC21143_CFID:
	csr14Bits = 0x80;
	break;
    default:
	return;
    }

    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 &= ~csr14Bits;
    Adapter->Media[DC21X4_MEDIA_10BASE2].Csr14 &= ~csr14Bits;
    Adapter->Media[DC21X4_MEDIA_10BASE5].Csr14 &= ~csr14Bits;
    Adapter->Media[DC21X4_MEDIA_10BASET].Mode &= ~DC_CSR6_FD;
    Adapter->Media[DC21X4_MEDIA_10BASE2].Mode &= ~DC_CSR6_FD;
    Adapter->Media[DC21X4_MEDIA_10BASE5].Mode &= ~DC_CSR6_FD;
}

void
DC21X4IndicateMediaStatus(DC21X4_ADAPTER *Adapter, u_long status)
{
    u_long csr12;

    Adapter->LinkStatus = status;
    if (status == Adapter->PreviousLinkStatus)
	return;

    switch (status) {
    case DC21X4_LINK_FAIL:
	if (!Adapter->PhyPresent || Adapter->KeepSiaLinkInterrupts) {
	    /* wait for link pass */
	    Adapter->InterruptMask &= ~DC_INT_LNF;
	    Adapter->InterruptMask |= DC_INT_LNP;
	    Adapter->InterruptDispatchMask &= ~DC_INT_LNF;
	    Adapter->InterruptDispatchMask |= DC_INT_LNP;
	    if (Adapter->DeviceId == DC21143_CFID) {
		Adapter->InterruptMask |= DC_INT_LC;
		Adapter->InterruptDispatchMask |= DC_INT_LC;
	    }
	}
	IOLog("%s: Link FAIL\n", getDriverName(Adapter));
	break;

    case DC21X4_LINK_PASS:
	if (Adapter->SelectedMedium == DC21X4_MEDIA_100BASETX ||
	    (Adapter->SelectedMedium >= DC21X4_MEDIA_100BASETX_FD &&
	     Adapter->SelectedMedium <= DC21X4_MEDIA_100BASEFX_FD)) {
	    if (Adapter->DeviceId == DC21143_CFID) {
		Adapter->InterruptMask &= ~(DC_INT_LNF | DC_INT_LNP);
		Adapter->InterruptDispatchMask &= ~(DC_INT_LNF | DC_INT_LNP);
		Adapter->InterruptMask |= DC_INT_LC;
		Adapter->InterruptDispatchMask |= DC_INT_LC;
	    }
	    Adapter->LinkSpeed = 1000000;
	} else {
	    /* 10 Mb/s: watch for link fail */
	    Adapter->LinkSpeed = 100000;
	    Adapter->InterruptMask &= ~DC_INT_LC;
	    Adapter->InterruptDispatchMask &= ~DC_INT_LC;
	    Adapter->InterruptMask |= DC_INT_LNF;
	    Adapter->InterruptDispatchMask |= DC_INT_LNF;
	}

	if (Adapter->NwayEnabled) {
	    csr12 = DC21X4_READ_CSR(Adapter, CSR12);
	    if (Adapter->DeviceId == DC21143_CFID) {
		Adapter->FullDuplex = (csr12 & (DC_CSR12_LP_100BASETX_FD |
						DC_CSR12_LP_10BASET_FD)) != 0;
		if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASET_FD ||
		    Adapter->SelectedMedium == DC21X4_MEDIA_100BASETX_FD)
		    Adapter->FullDuplex = TRUE;
	    } else {
		Adapter->FullDuplex = (csr12 & DC_CSR12_LP_10BASET_FD) != 0;
		if (Adapter->SelectedMedium == DC21X4_MEDIA_10BASET &&
		    (Adapter->OperationMode & DC_CSR6_FD))
		    Adapter->FullDuplex = TRUE;
	    }
	} else {
	    Adapter->FullDuplex =
		(Adapter->MediaType & DC21X4_MEDIA_FULL_DUPLEX) != 0;
	}

	IOLog("%s: %s%s Link PASS\n", getDriverName(Adapter),
	    MediumString[Adapter->SelectedMedium],
	    Adapter->FullDuplex ? " Full_Duplex" : "");
	break;

    case DC21X4_MII_LINK_PASS:
	Adapter->LinkSpeed = 100000;
	Adapter->FullDuplex = FALSE;
	switch ((u_char)Adapter->MiiMediaType) {
	case 10:		/* Mii10BaseT_FD */
	    Adapter->FullDuplex = TRUE;
	    break;
	case 14:		/* Mii100BaseTX_FD */
	case 17:		/* Mii100BaseFX_FD */
	    Adapter->FullDuplex = TRUE;
	    /* fall through */
	case 13:		/* Mii100BaseTX */
	case 15:		/* Mii100BaseT4 */
	case 16:		/* Mii100BaseFX */
	    Adapter->LinkSpeed = 1000000;
	    break;
	}
	IOLog("%s: %s%s MiiLink PASS\n", getDriverName(Adapter),
	    MediumString[(u_char)Adapter->MiiMediaType],
	    Adapter->FullDuplex ? " Full_Duplex" : "");
	break;
    }

    if (!Adapter->PhyPresent || Adapter->KeepSiaLinkInterrupts)
	DC21X4_WRITE_CSR(Adapter, CSR7, Adapter->InterruptMask);

    /* no carrier/heartbeat errors in full duplex */
    if (Adapter->FullDuplex)
	Adapter->TxErrorMask &= ~0x000c0000;
    else
	Adapter->TxErrorMask = Adapter->TxErrorMaskDefault;

    Adapter->PreviousLinkStatus = status;
}
