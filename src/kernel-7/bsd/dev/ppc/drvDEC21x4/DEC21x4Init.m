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
 * DEC21x4Init.m
 *
 * Adapter reset and initialization for the DEC 21x4x Ethernet driver.
 *
 * HISTORY
 *
 * Reconstructed for RhapsodiOS from the DEC21x4 code linked into the
 * Mac OS X Server 1.2v3 (kernel 5.6) ppc mach_kernel.
 */

#import "DEC21x4.h"

/*
 * Little-endian TDES0/RDES0 bits that count as errors (see the
 * Adapter->TxErrorMask/RxErrorMask comments in DEC21x4Adapter.h).
 * Tx: UF, EC, LC, NC, LO, TO.  The 21040's early revisions report
 * loss of carrier spuriously, so LO is dropped for them.
 * Rx: TL, CS, RW, CE, bit 0, RF, DE.
 */
#define TX_ERROR_MASK_DEFAULT	0x024f0000
#define TX_ERROR_LO		0x00080000
#define TX_ERROR_NC_LO		0x000c0000	/* no carrier check in full duplex */
#define RX_ERROR_MASK		0xd3480000

@implementation DEC21x4(DEC21x4Init)

- (BOOL)resetAndEnable:(BOOL)enable
{
    int			i;
    unsigned int	interruptMask;

    [self clearTimeout];
    [self disableAdapterInterrupts];

    for (i = 0; i < DC21X4_CSR_COUNT; i++)
	Adapter->CsrOffset[i] = DC_CSR(i);

    if (Adapter->TimerState != DC21X4_TIMER_IDLE)
	DC21X4StopAutoSenseTimer(Adapter);

    Adapter->InterruptMask = DC_INT_LC | DC_INT_NIS | DC_INT_AIS |
	DC_INT_SE | DC_INT_LNF | DC_INT_GTE | DC_INT_RU | DC_INT_RI |
	DC_INT_UNF | DC_INT_LNP | DC_INT_TJT | DC_INT_TI;
    Adapter->InterruptDispatchMask = Adapter->InterruptMask &
	~(DC_INT_LC | DC_INT_NIS | DC_INT_AIS);

    switch (Adapter->DeviceId) {
    case DC21143_CFID:
	Adapter->InterruptDispatchMask |= DC_INT_LC;
	/* fall through */
    case DC21142_CFID:
	Adapter->InterruptMask |= DC_INT_GPI;
	break;
    }

    DC21X4StopAdapter(Adapter);

    Adapter->ForceNway = TRUE;
    Adapter->UseMediaTypeForPhy = TRUE;
    Adapter->InitInProgress = TRUE;
    Adapter->TxErrorMaskDefault = TX_ERROR_MASK_DEFAULT;
    Adapter->RxErrorMask = RX_ERROR_MASK;
    Adapter->Threshold10Mbps = txThresh10;
    Adapter->Threshold100Mbps = txThresh100;

    if (Adapter->DeviceId == DC21040_CFID) {
	switch (Adapter->RevisionNumber) {
	case 0x00:
	case 0x20:
	case 0x22:
	    Adapter->TxErrorMaskDefault &= ~TX_ERROR_LO;
	    Adapter->Threshold10Mbps = 0x4000;
	    break;
	}
    }

    if (![self parseSROM:logMediaTypes])
	goto failed;
    logMediaTypes = NO;

    if (!enable) {
	[self setRunning:NO];
	return YES;
    }

    if (![self _initRxRing] || ![self _initTxRing])
	goto failed;

    if (![self verifyMediaSupport:Adapter->MediaType]) {
	IOLog("%s: Unsupported medium. Using default: %s\n", [self name],
	    MediumString[(u_char)Adapter->DefaultMedium]);
	Adapter->MediaType = Adapter->DefaultMedium;
    }

    /* No link interrupts until the adapter is up. */
    interruptMask = Adapter->InterruptMask;
    Adapter->InterruptMask = interruptMask &
	~(DC_INT_LC | DC_INT_LNF | DC_INT_LNP);

    if ([self _initAdapter]) {
	Adapter->InterruptMask = interruptMask;
	[self enableAdapterInterrupts];
	[self setRunning:YES];
	return YES;
    }
    IOLog("%s: initAdapter failed\n", [self name]);

failed:
    [self setRunning:NO];
    return NO;
}

- (BOOL)_initRegisters
{
    unsigned char	burstLength;
    unsigned int	csr0 = 0;
    unsigned int	physAddr;

    DC21X4StopAdapter(Adapter);

    switch (Adapter->DeviceId) {
    case DC21040_CFID:
	break;
    case DC21140_CFID:
	DC21X4_WRITE_CSR(Adapter, CSR6,
	    Adapter->OperationMode & ~(DC_CSR6_ST | DC_CSR6_SR));
	DC21X4StopAdapter(Adapter);
	break;
    }

    burstLength = maxBurstLen;
    if ((Adapter->DeviceId == DC21040_CFID ||
	 Adapter->DeviceId == DC21041_CFID) && burstLength > 16)
	burstLength = 16;

    if (burstLength == 0) {
	switch (Adapter->DeviceId) {
	case DC21140_CFID:
	    if ((Adapter->RevisionNumber & 0xf0) == 0x10)
		burstLength = 16;
	    break;
	case DC21040_CFID:
	case DC21041_CFID:
	    burstLength = 16;
	    break;
	}
    }

    csr0 |= DC_CSR0_WIE | DC_CSR0_RLE | DC_CSR0_RME | DC_CSR0_CAL_8 |
	((burstLength << DC_CSR0_PBL_SHIFT) & DC_CSR0_PBL_MASK);
    DC21X4_WRITE_CSR(Adapter, CSR0, csr0);
    eieio();

    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)rxRing,
	    &physAddr) != IO_R_SUCCESS) {
	IOLog("%s: Invalid memory address\n", [self name]);
	return NO;
    }
    DC21X4_WRITE_CSR(Adapter, CSR3, physAddr);
    eieio();

    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)txRing,
	    &physAddr) != IO_R_SUCCESS) {
	IOLog("%s: Invalid memory address\n", [self name]);
	return NO;
    }
    DC21X4_WRITE_CSR(Adapter, CSR4, physAddr);
    eieio();

    if (Adapter->DeviceId == DC21040_CFID) {
	DC21X4_WRITE_CSR(Adapter, CSR10, 0);
	eieio();
    }

    return YES;
}

- (BOOL)_initAdapter
{
    int			i;
    unsigned int	csr6 = 0;
    unsigned int	mode;
    BOOL		miiFound;
    BOOL		startTimer = YES;

    if (Adapter->GepSequenceLength) {
	for (i = 0; i < Adapter->GepSequenceLength; i++) {
	    IODelay(5);
	    DC21X4WriteGepRegister(Adapter, Adapter->GepSequence[i]);
	}
    }

    if (![self _initRegisters])
	return NO;

    if (Adapter->PhyMediaInSrom) {
	Adapter->PhyResetDone = FALSE;
	Adapter->PhyPresent = DC21X4PhyInit(Adapter);
	if (!Adapter->KeepSiaLinkInterrupts && Adapter->PhyPresent &&
	    (Adapter->DeviceId == DC21142_CFID ||
	     Adapter->DeviceId == DC21143_CFID)) {
	    Adapter->InterruptMask &= ~(DC_INT_LC | DC_INT_LNF | DC_INT_LNP);
	    Adapter->InterruptDispatchMask &=
		~(DC_INT_LC | DC_INT_LNF | DC_INT_LNP);
	}
    }

    if (captureEffect)
	csr6 = DC_CSR6_SC | DC_CSR6_CAE;

    switch (Adapter->DeviceId) {

    case DC21040_CFID:
	Adapter->LinkSpeed = 100000;
	csr6 |= Adapter->Threshold10Mbps;
	Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= csr6;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Mode |= csr6;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Mode |= csr6;

	if (Adapter->MediaType ==
	    (DC21X4_MEDIA_FULL_DUPLEX | DC21X4_MEDIA_10BASET_FD)) {
	    Adapter->MediaType = DC21X4_MEDIA_FULL_DUPLEX | DC21X4_MEDIA_10BASET;
	    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 = 0xfffd;
	    Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= DC_CSR6_FD;
	    Adapter->FullDuplex = TRUE;
	}
	else if (Adapter->MediaType & DC21X4_MEDIA_NO_LINK_TEST)
	    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 = 0xcfff;

	Adapter->SelectedMedium = (u_char)Adapter->MediaType;
	Adapter->MediaCapable &= 1 << Adapter->SelectedMedium;
	break;

    case DC21041_CFID:
	Adapter->LinkSpeed = 100000;
	csr6 |= Adapter->Threshold10Mbps;
	Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= csr6;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Mode |= csr6;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Mode |= csr6;

	if (Adapter->MediaType ==
	    (DC21X4_MEDIA_FULL_DUPLEX | DC21X4_MEDIA_10BASET_FD))
	    Adapter->MediaType = DC21X4_MEDIA_FULL_DUPLEX | DC21X4_MEDIA_10BASET;

	if (Adapter->MediaType & DC21X4_MEDIA_NWAY)
	    DC21X4EnableNway(Adapter);

	if (Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE) {
	    Adapter->Media[DC21X4_MEDIA_10BASE2].Csr14 |= 0xf038;
	    Adapter->Media[DC21X4_MEDIA_10BASE5].Csr14 |= 0xf038;
	    Adapter->SelectedMedium =
		(Adapter->MediaCapable & (1 << DC21X4_MEDIA_10BASE2)) ?
		DC21X4_MEDIA_10BASE2 : DC21X4_MEDIA_10BASE5;
	}
	else {
	    Adapter->SelectedMedium = Adapter->MediaType & 0xff;
	    Adapter->MediaCapable &= 1 << Adapter->SelectedMedium;
	}

	if (Adapter->MediaType & DC21X4_MEDIA_FULL_DUPLEX) {
	    Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= DC_CSR6_FD;
	    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 = 0x7f3d;
	    Adapter->FullDuplex = TRUE;
	}
	else if (Adapter->MediaType & DC21X4_MEDIA_NO_LINK_TEST)
	    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 = 0x4f3f;
	break;

    case DC21140_CFID:
	csr6 |= DC_CSR6_MBO;
	mode = csr6 | DC_CSR6_TTM | Adapter->Threshold10Mbps;
	Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_10BASET_FD].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_100BASETX].Mode |= csr6;
	Adapter->Media[DC21X4_MEDIA_100BASETX_FD].Mode |= csr6;
	Adapter->Media[DC21X4_MEDIA_100BASET4].Mode |= csr6;
	Adapter->Media[DC21X4_MEDIA_100BASEFX].Mode |= csr6;
	Adapter->Media[DC21X4_MEDIA_100BASEFX_FD].Mode |= csr6;

	Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= DC_CSR6_SCR;
	Adapter->Media[DC21X4_MEDIA_10BASET_FD].Mode |= DC_CSR6_SCR;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Mode |= DC_CSR6_SCR;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Mode |= DC_CSR6_SCR;
	Adapter->Media[DC21X4_MEDIA_100BASETX].Mode |= DC_CSR6_MBO | DC_CSR6_HBD;
	Adapter->Media[DC21X4_MEDIA_100BASETX_FD].Mode |= DC_CSR6_MBO | DC_CSR6_HBD;
	Adapter->Media[DC21X4_MEDIA_100BASEFX].Mode |= DC_CSR6_MBO | DC_CSR6_HBD;
	Adapter->Media[DC21X4_MEDIA_100BASEFX_FD].Mode |= DC_CSR6_MBO | DC_CSR6_HBD;

	if (Adapter->MediaType & DC21X4_MEDIA_FULL_DUPLEX) {
	    Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= DC_CSR6_FD;
	    Adapter->Media[DC21X4_MEDIA_10BASET_FD].Mode |= DC_CSR6_FD;
	    Adapter->Media[DC21X4_MEDIA_100BASETX_FD].Mode |= DC_CSR6_FD;
	    Adapter->Media[DC21X4_MEDIA_100BASEFX_FD].Mode |= DC_CSR6_FD;
	    Adapter->FullDuplex = TRUE;
	}

	if (Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE)
	    Adapter->LinkSpeed = 100000;
	else {
	    Adapter->SelectedMedium = Adapter->MediaType & 0xff;
	    Adapter->MediaCapable &= 1 << Adapter->SelectedMedium;
	    Adapter->LinkSpeed =
		(Adapter->Media[Adapter->SelectedMedium].Mode & DC_CSR6_SCR) ?
		100000 : 1000000;
	}
	break;

    case DC21142_CFID:
    case DC21143_CFID:
	csr6 |= DC_CSR6_MBO;
	mode = csr6 | DC_CSR6_TTM | Adapter->Threshold10Mbps;
	Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Mode |= mode;

	mode = csr6 & ~DC_CSR6_TTM;
	if (!Adapter->PhyPresent)
	    mode |= DC_CSR6_PCS;
	mode |= Adapter->Threshold100Mbps | DC_CSR6_HBD;
	Adapter->Media[DC21X4_MEDIA_100BASETX].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_100BASETX_FD].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_100BASET4].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_100BASEFX].Mode |= mode;
	Adapter->Media[DC21X4_MEDIA_100BASEFX_FD].Mode |= mode;

	if (Adapter->MediaType ==
	    (DC21X4_MEDIA_FULL_DUPLEX | DC21X4_MEDIA_10BASET_FD))
	    Adapter->MediaType = DC21X4_MEDIA_FULL_DUPLEX | DC21X4_MEDIA_10BASET;

	if ((Adapter->MediaType & DC21X4_MEDIA_NWAY) &&
	    (!Adapter->PhyPresent || !Adapter->PhyNwayCapable))
	    DC21X4EnableNway(Adapter);

	if (Adapter->MediaType & DC21X4_MEDIA_AUTOSENSE) {
	    Adapter->Media[DC21X4_MEDIA_10BASE2].Csr14 |= 0xf038;
	    Adapter->Media[DC21X4_MEDIA_10BASE5].Csr14 |= 0xf038;
	    if (Adapter->MediaCapable & (1 << DC21X4_MEDIA_10BASE2))
		Adapter->SelectedMedium = DC21X4_MEDIA_10BASE2;
	    else if (Adapter->MediaCapable & (1 << DC21X4_MEDIA_10BASE5))
		Adapter->SelectedMedium = DC21X4_MEDIA_10BASE5;
	    else
		Adapter->SelectedMedium = (u_char)Adapter->MediaType;
	    Adapter->LinkSpeed = 100000;
	}
	else {
	    Adapter->SelectedMedium = Adapter->MediaType & 0xff;
	    Adapter->MediaCapable &= 1 << Adapter->SelectedMedium;
	    switch (Adapter->SelectedMedium) {
	    case DC21X4_MEDIA_100BASETX:
	    case DC21X4_MEDIA_100BASETX_FD:
	    case DC21X4_MEDIA_100BASET4:
	    case DC21X4_MEDIA_100BASEFX:
	    case DC21X4_MEDIA_100BASEFX_FD:
		Adapter->LinkSpeed = 1000000;
		break;
	    default:
		Adapter->LinkSpeed = 100000;
		break;
	    }
	}

	if (Adapter->MediaType & DC21X4_MEDIA_FULL_DUPLEX) {
	    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 = 0x7f3d;
	    Adapter->Media[DC21X4_MEDIA_10BASET].Mode |= DC_CSR6_FD;
	    Adapter->Media[DC21X4_MEDIA_100BASETX_FD].Mode |= DC_CSR6_FD;
	    Adapter->Media[DC21X4_MEDIA_100BASEFX_FD].Mode |= DC_CSR6_FD;
	    Adapter->FullDuplex = TRUE;
	}
	else if (Adapter->MediaType & DC21X4_MEDIA_NO_LINK_TEST)
	    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 = 0x4f3f;
	break;

    default:
	IOLog("Unknown adapter - initializeAdapter failed\n");
	break;
    }

    if (Adapter->PhyPresent) {
	if (Adapter->Phy100Sia10 &&
	    (Adapter->MiiMediaType & DC21X4_MEDIA_AUTOSENSE)) {
	    Adapter->MiiMediaType &= 0xff00;
	    Adapter->MiiMediaType |= DC21X4_MII_MEDIA_AUTOSENSE;
	    Adapter->SelectedMedium = DC21X4_MEDIA_10BASET;
	}
	Adapter->PhyPresent = DC21X4SetPhyConnection(Adapter);
    }
    if (!Adapter->PhyPresent && !Adapter->MediaCapable)
	IOLog("Warning: unsupported media\n");

    Adapter->OperationMode |= Adapter->Media[Adapter->SelectedMedium].Mode;

    Adapter->TxErrorMask = Adapter->TxErrorMaskDefault;
    if (Adapter->FullDuplex)
	Adapter->TxErrorMask &= ~TX_ERROR_NC_LO;

    [self _startTransmit];
    if (![self _setAddressFiltering:YES])
	return NO;

    if (Adapter->NwayProtocol == 3 || !Adapter->PhyPresent) {
	DC21X4StopReceiverAndTransmitter(Adapter);
	DC21X4_WRITE_CSR(Adapter, CSR6,
	    Adapter->OperationMode & ~(DC_CSR6_ST | DC_CSR6_SR));
	IODelay(1000);
	DC21X4InitializeMediaRegisters(Adapter, FALSE);
    }

    Adapter->NwayOnFirstLinkPass = TRUE;
    DC21X4StartAdapter(Adapter);

    if (Adapter->NwayProtocol != 3) {
	if (Adapter->PhyPresent)
	    miiFound = DC21X4MiiAutoDetect(Adapter);
	if (!Adapter->PhyPresent || (!miiFound && Adapter->MediaCapable)) {
	    if (!Adapter->Phy100Sia10 ||
		(Adapter->MediaCapable & ((1 << DC21X4_MEDIA_10BASE2) |
					  (1 << DC21X4_MEDIA_10BASE5))))
		startTimer = DC21X4MediaDetect(Adapter);
	}
	if (startTimer && Adapter->TimerState == DC21X4_TIMER_IDLE)
	    DC21X4StartAutoSenseTimer(Adapter, 6000);
    }

    Adapter->InitInProgress = FALSE;
    return YES;
}

- (BOOL)verifyMediaSupport:(unsigned int)mediaType
{
    unsigned int	medium = mediaType & 0xff;
    int			phy, bit;

    if ((mediaType & DC21X4_MEDIA_AUTOSENSE) ||
	(MediaCapableSaved & (1 << medium)))
	return YES;

    if (Adapter->PhyMediaInSrom) {
	for (phy = 0; phy < DC21X4_MAX_PHY; phy++) {
	    if (!Adapter->PhyMediaInfo[phy].Present)
		continue;
	    for (bit = 0; bit < DC21X4_MEDIA_STRING_COUNT; bit++) {
		if ((MediaBitTable[bit] &
		     Adapter->PhyMediaInfo[phy].MediaCapabilities) &&
		    bit == (u_char)ConvertMediaTypeToMiiType[medium])
		    return YES;
	    }
	}
    }
    return NO;
}

@end
