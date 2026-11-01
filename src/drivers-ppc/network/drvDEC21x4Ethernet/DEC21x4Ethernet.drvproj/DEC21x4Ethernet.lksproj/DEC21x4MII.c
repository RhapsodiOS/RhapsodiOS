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
 * DEC21x4MII.c
 *
 * MII PHY support for the DEC 21x4x driver: PHY discovery, the generic
 * MII entry points used by the media code, the per-PHY routines reached
 * through the MII_PHY_INFO function table, and bit-banged management
 * frames on CSR9.
 *
 * HISTORY
 *
 * Reconstructed for RhapsodiOS from the DEC21x4 code linked into the
 * Mac OS X Server 1.2v3 (kernel 5.6) ppc mach_kernel.
 */

#import <driverkit/generalFuncs.h>
#import "DEC21x4Adapter.h"

/* MII registers */
#define MII_CONTROL		0
#define MII_STATUS		1
#define MII_PHY_ID1		2
#define MII_PHY_ID2		3
#define MII_NWAY_ADVERTISE	4
#define MII_NWAY_PARTNER	5
#define MII_NWAY_EXPANSION	6

/* MII control register */
#define MII_CONTROL_RESET	0x8000
#define MII_CONTROL_SPEED_100	0x2000
#define MII_CONTROL_NWAY	0x1000
#define MII_CONTROL_POWER_DOWN	0x0800
#define MII_CONTROL_ISOLATE	0x0400
#define MII_CONTROL_RESTART_NWAY 0x0200
#define MII_CONTROL_FULL_DUPLEX	0x0100

/* Nway advertisement / link partner ability */
#define MII_NWAY_10BASET	0x0020
#define MII_NWAY_10BASET_FD	0x0040
#define MII_NWAY_100BASETX	0x0080
#define MII_NWAY_100BASETX_FD	0x0100
#define MII_NWAY_100BASET4	0x0200
#define MII_NWAY_MEDIA_MASK	0x03e0
#define MII_NWAY_SELECTOR_8023	0x0001

/* PHYs that need special handling, by MII registers 2:3 */
#define MII_PHY_ID_BROADCOM	0x03e00000
#define MII_PHY_ID_DP83840	0x20005c00	/* National DP83840 */
#define MII_PHY_ID_406210	0x00406210	/* revision in the low nibble */
#define MII_PHY_ID_REV_MASK	0xfffffff0

#define DP83840_PAR		25		/* PHY address register */
#define DP83840_PAR_SPEED_10	0x0040
#define BROADCOM_AUX_STATUS	16
#define BROADCOM_AUX_LINK	0x0100
#define BROADCOM_AUX_SPEED_100	0x0002
#define PHY_406210_REG30	30

/* Management frames on CSR9 */
#define MII_CLK			0x00010000
#define MII_DATA_OUT_SHIFT	14	/* frame bit 31 -> CSR9 MDO (bit 17) */
#define MII_DATA_OUT		0x00020000
#define MII_DATA_IN		0x00080000
#define MII_DATA_IN_SHIFT	19
#define MII_WRITE		0x00002000
#define MII_WRITE_TS		0x00042000
#define MII_READ		0x00044000
#define MII_READ_FRAME		0x60000000	/* start, read opcode */
#define MII_WRITE_FRAME		0x50020000	/* start, write opcode, turnaround */
#define MII_PHY_ADDR_SHIFT	23
#define MII_REG_ADDR_SHIFT	18
#define MII_PREAMBLE		0xffffffff

#define MEDIA_INDEX(_c)		((_c) & 0xff)
#define MEDIA_NWAY_AUTOSENSE	(DC21X4_MEDIA_AUTOSENSE | DC21X4_MEDIA_NWAY)

/*
 * Media codes with their flags, in SROM connection order.  Not
 * referenced.
 */
const u_long ConnectionType[] = {
    0x0900, 0x0001, 0x0000, 0x0204, 0x0400, 0x0002, 0x0800,
    0x0900, 0x0003, 0x0205, 0x0006, 0x0007, 0x0208
};

/* Bits forced to zero in every MII register read or written */
const u_short PhyRegsReservedBitsMasks[MII_PHY_REGS] = {
    0x007f, 0x07c0, 0x0000, 0x0000, 0x1c00, 0x1c00, 0xffe0, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000
};

/* MII control bits for each MII_ADMIN_ request */
const u_long AdminControlConversionTable[] = {
    MII_CONTROL_RESET,		/* MII_ADMIN_RESET */
    0,				/* MII_ADMIN_OPERATIONAL */
    MII_CONTROL_ISOLATE,	/* MII_ADMIN_ISOLATE */
    MII_CONTROL_POWER_DOWN,	/* MII_ADMIN_POWER_DOWN */
    0,				/* MII_ADMIN_FORCE_10 */
    MII_CONTROL_FULL_DUPLEX,	/* MII_ADMIN_FORCE_10_FD */
    0				/* MII_ADMIN_RESTORE */
};

/* MII status capability bit for each media string index */
const u_short MediaBitTable[DC21X4_MEDIA_STRING_COUNT] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    0x0800,	/* Mii10BaseT */
    0x1000,	/* Mii10BaseT_FD */
    0,		/* Mii10Base2 */
    0,		/* Mii10Base5 */
    0x2000,	/* Mii100BaseTX */
    0x4000,	/* Mii100BaseTX_FD */
    0x8000,	/* Mii100BaseT4 */
    0,		/* Mii100BaseFX */
    0		/* Mii100BaseFX_FD */
};

/* SROM media code -> MII media code (with the full duplex flag) */
const u_short ConvertMediaTypeToMiiType[DC21X4_MEDIA_COUNT] = {
    0x0009, 0x000b, 0x000c, 0x000d, 0x020a, 0x020e, 0x000f, 0x0010, 0x0211
};

/* Media index -> MII control speed/duplex bits */
const u_short MediaToCommandConversionTable[DC21X4_MEDIA_STRING_COUNT] = {
    0x0000, 0x0000, 0x0000, 0x2000, 0x0100, 0x2100, 0x2000, 0x2000, 0x2100,
    0x0000, 0x0100, 0x0000, 0x0000, 0x2000, 0x2100, 0x2000, 0x2000, 0x2100
};

/* Media index -> Nway advertisement bit */
const u_short MediaToNwayConversionTable[DC21X4_MEDIA_STRING_COUNT] = {
    0x0020, 0x0000, 0x0000, 0x0080, 0x0040, 0x0100, 0x0200, 0x0080, 0x0100,
    0x0020, 0x0040, 0x0000, 0x0000, 0x0080, 0x0100, 0x0200, 0x0080, 0x0100
};

/* Media index -> MII status capability bit */
const u_short MediaToStatusConversionTable[DC21X4_MEDIA_STRING_COUNT] = {
    0x0800, 0x0000, 0x0000, 0x2000, 0x1000, 0x4000, 0x8000, 0x2000, 0x4000,
    0x0800, 0x1000, 0x0000, 0x0000, 0x2000, 0x4000, 0x8000, 0x2000, 0x4000
};

char *MediumString[DC21X4_MEDIA_STRING_COUNT] = {
    "10BaseT",
    "10Base2",
    "10Base5",
    "100BaseTX",
    "10BaseT_FD",
    "100BaseTX_FD",
    "100BaseT4",
    "100BaseFX",
    "100BaseFX_FD",
    "Mii10BaseT",
    "Mii10BaseT_FD",
    "Mii10Base2",
    "Mii10Base5",
    "Mii100BaseTX",
    "Mii100BaseTX_FD",
    "Mii100BaseT4",
    "Mii100BaseFX",
    "Mii100BaseFX_FD"
};

/*
 * Generic MII entry points.  They act on the PHY selected by
 * Adapter->PhyNumber.
 */

BOOL
MiiGenInit(DC21X4_ADAPTER *Adapter)
{
    u_short capabilities;

    if (!FindAndInitMiiPhys(Adapter))
	return FALSE;

    Adapter->Phy[Adapter->PhyNumber]->PhyGetCapabilities(
	Adapter->Phy[Adapter->PhyNumber], &capabilities);
    Adapter->MiiCapabilities |= capabilities;
    Adapter->ActivePhy = Adapter->PhyNumber;
    return TRUE;
}

u_short
MiiGenGetCapabilities(DC21X4_ADAPTER *Adapter)
{
    return Adapter->MiiCapabilities;
}

BOOL
MiiGenCheckConnection(DC21X4_ADAPTER *Adapter, u_short connection)
{
    return CheckConnectionSupport(Adapter->Phy[Adapter->PhyNumber],
	connection);
}

BOOL
MiiGenSetConnection(DC21X4_ADAPTER *Adapter, u_long connection,
    u_short advertisement)
{
    MII_PHY_INFO *phy = Adapter->Phy[Adapter->PhyNumber];

    return phy->PhySetConnectionType(Adapter, phy, connection, advertisement);
}

BOOL
MiiGenGetConnectionStatus(DC21X4_ADAPTER *Adapter, u_short *status)
{
    MII_PHY_INFO *phy = Adapter->Phy[Adapter->PhyNumber];

    return phy->PhyGetConnectionStatus(Adapter, phy, status);
}

/*
 * The status lands in *connection first and is then overwritten by the
 * connection type.
 */
BOOL
MiiGenGetConnection(DC21X4_ADAPTER *Adapter, u_short *connection)
{
    MII_PHY_INFO *phy = Adapter->Phy[Adapter->PhyNumber];

    if (!phy->PhyGetConnectionStatus(Adapter, phy, connection)) {
	*connection = 0xffff;
	return FALSE;
    }
    phy = Adapter->Phy[Adapter->PhyNumber];
    return phy->PhyGetConnectionType(Adapter, phy, connection);
}

void
MiiGenAdminStatus(DC21X4_ADAPTER *Adapter, u_long *status)
{
    MII_PHY_INFO *phy = Adapter->Phy[Adapter->PhyNumber];

    phy->PhyAdminStatus(Adapter, phy, status);
}

BOOL
MiiGenAdminControl(DC21X4_ADAPTER *Adapter, u_short control)
{
    MII_PHY_INFO *phy = Adapter->Phy[Adapter->PhyNumber];

    phy->PhyAdminControl(Adapter, phy, control);

    switch (control) {
    case MII_ADMIN_RESET:
    case MII_ADMIN_OPERATIONAL:
    case MII_ADMIN_FORCE_10:
    case MII_ADMIN_FORCE_10_FD:
    case MII_ADMIN_RESTORE:
	Adapter->ActivePhy = Adapter->PhyNumber;
	break;
    case MII_ADMIN_ISOLATE:
    case MII_ADMIN_POWER_DOWN:
	Adapter->ActivePhy = 0xff;
	break;
    default:
	return FALSE;
    }
    return TRUE;
}

/*
 * Scan the 32 MII addresses for a PHY.  The first PHY found is reset,
 * which can move it, so the scan restarts once from address 0.
 */
BOOL
FindAndInitMiiPhys(DC21X4_ADAPTER *Adapter)
{
    int phyAddress = 0;
    BOOL firstScan = TRUE;

    if (Adapter->Phy[Adapter->PhyNumber] == NULL) {
	Adapter->Phy[Adapter->PhyNumber] =
	    (MII_PHY_INFO *)IOMalloc(DC21X4_MII_PHY_ALLOC_SIZE);
	if (Adapter->Phy[Adapter->PhyNumber] == NULL)
	    return FALSE;
    }

    InitPhyInfoEntries(Adapter->Phy[Adapter->PhyNumber]);

    while (phyAddress <= 31) {
	Adapter->Phy[Adapter->PhyNumber]->PhyAddress = phyAddress;
	if (MiiPhyInit(Adapter, Adapter->Phy[Adapter->PhyNumber])) {
	    Adapter->PhyCount++;
	    return TRUE;
	}
	if (Adapter->PhyResetDone && firstScan) {
	    firstScan = FALSE;
	    phyAddress = 0;
	} else
	    phyAddress++;
    }

    IOFree(Adapter->Phy[Adapter->PhyNumber], DC21X4_MII_PHY_ALLOC_SIZE);
    Adapter->Phy[Adapter->PhyNumber] = NULL;
    return FALSE;
}

void
MiiFreeResources(DC21X4_ADAPTER *Adapter)
{
    if (Adapter->Phy[Adapter->PhyNumber] != NULL) {
	IOFree(Adapter->Phy[Adapter->PhyNumber], DC21X4_MII_PHY_ALLOC_SIZE);
	Adapter->Phy[Adapter->PhyNumber] = NULL;
    }
}

/*
 * Per-PHY routines, reached through the MII_PHY_INFO function table.
 */

BOOL
MiiPhyInit(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy)
{
    if (!FindMiiPhyDevice(Adapter, Phy))
	return FALSE;

    if (!Adapter->PhyResetDone) {
	Adapter->PhyResetDone = TRUE;
	Phy->PhyAdminControl(Adapter, Phy, MII_ADMIN_RESET);
	if (!FindMiiPhyDevice(Adapter, Phy))
	    return FALSE;
    }

    Phy->PhyCapabilities = Phy->PhyRegs[MII_STATUS] &
	(MII_STATUS_MEDIA_MASK | MII_STATUS_NWAY_ABLE);
    /* the Broadcom PHY negotiates without saying so */
    if (Phy->PhyId == MII_PHY_ID_BROADCOM)
	Phy->PhyCapabilities |= MII_STATUS_NWAY_ABLE;

    Phy->PhyNwayGetLocalAbility(Adapter, Phy, &Phy->PhyMediaAdvertisement);
    Phy->PhyAdminControl(Adapter, Phy, MII_ADMIN_OPERATIONAL);
    Phy->Present = TRUE;
    Phy->PreviousConnectionStatus = 0xffff;
    return TRUE;
}

void
MiiPhyGetCapabilities(MII_PHY_INFO *Phy, u_short *capabilities)
{
    *capabilities = Phy->PhyCapabilities;
}

BOOL
MiiPhySetConnectionType(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
    u_short connection, u_short advertisement)
{
    if (!CheckConnectionSupport(Phy, connection))
	return FALSE;

    ConvertConnectionToControl(Phy, &connection);

    Phy->PhyRegs[MII_CONTROL] &= (MII_CONTROL_POWER_DOWN | MII_CONTROL_ISOLATE);
    Phy->PhyRegs[MII_CONTROL] |= connection;

    if (connection & MII_CONTROL_NWAY)
	Phy->PhyNwaySetLocalAbility(Adapter, Phy, advertisement);

    Phy->PhyWriteRegister(Adapter, Phy, MII_CONTROL, Phy->PhyRegs[MII_CONTROL]);
    Phy->PhyRegs[MII_CONTROL] &= ~MII_CONTROL_RESTART_NWAY;

    if (Phy->PhyId == MII_PHY_ID_BROADCOM)
	HandleBroadcomMediaChangeFrom10To100(Adapter, Phy);
    return TRUE;
}

BOOL
MiiPhyGetConnectionType(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
    u_short *connection)
{
    u_short localAbility;
    u_short partnerAbility;
    u_short par;
    int common;

    if (Phy->PhyId == MII_PHY_ID_BROADCOM) {
	if (!GetBroadcomPhyConnectionType(Adapter, Phy, connection)) {
	    *connection = 0xffff;
	    return FALSE;
	}
	HandleBroadcomMediaChangeFrom10To100(Adapter, Phy);
	return TRUE;
    }

    if (Phy->PhyRegs[MII_CONTROL] & MII_CONTROL_NWAY) {
	Phy->PhyNwayGetLocalAbility(Adapter, Phy, &localAbility);
	Phy->PhyNwayGetPartnerAbility(Adapter, Phy, &partnerAbility);
	common = localAbility & partnerAbility;
	if (common == 0) {
	    /* the DP83840 reports the parallel-detected speed in its PAR */
	    if (Phy->PhyId == MII_PHY_ID_DP83840 &&
		Phy->PhyReadRegister(Adapter, Phy, DP83840_PAR, &par)) {
		if (par & DP83840_PAR_SPEED_10)
		    common = localAbility & MII_NWAY_10BASET;
		else
		    common = localAbility & MII_NWAY_100BASETX;
	    }
	    if (common == 0)
		return FALSE;
	}
	return ConvertNwayToConnectionType(common, connection);
    }

    if (Phy->PhyRegs[MII_CONTROL] & MII_CONTROL_FULL_DUPLEX) {
	if (Phy->PhyRegs[MII_CONTROL] & MII_CONTROL_SPEED_100)
	    *connection = DC21X4_MEDIA_FULL_DUPLEX | 0x0e;	/* Mii100BaseTX_FD */
	else
	    *connection = DC21X4_MEDIA_FULL_DUPLEX | 0x0a;	/* Mii10BaseT_FD */
    } else if (Phy->PhyRegs[MII_CONTROL] & MII_CONTROL_SPEED_100) {
	if (Phy->PhyRegs[MII_STATUS] & MII_STATUS_100BASETX)
	    *connection = 0x0d;		/* Mii100BaseTX */
	else
	    *connection = 0x0f;		/* Mii100BaseT4 */
    } else
	*connection = 0x09;		/* Mii10BaseT */
    return TRUE;
}

BOOL
MiiPhyGetConnectionStatus(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
    u_short *status)
{
    u_short mode;
    u_short localAbility;
    u_short partnerAbility;
    u_long par;		/* read as a u_short; see the DP83840 test below */
    int common = 0;
    int link;

    if (!Phy->PhyReadRegister(Adapter, Phy, MII_CONTROL,
	    &Phy->PhyRegs[MII_CONTROL]) ||
	!Phy->PhyReadRegister(Adapter, Phy, MII_STATUS,
	    &Phy->PhyRegs[MII_STATUS]) ||
	Phy->PhyRegs[MII_STATUS] == 0) {
	*status = MII_CONN_READ_ERROR;
	Phy->PreviousConnectionStatus = MII_CONN_READ_ERROR;
	return FALSE;
    }

    if (Phy->PhyId == MII_PHY_ID_BROADCOM) {
	if (Phy->PhyRegs[MII_CONTROL] & MII_CONTROL_NWAY)
	    mode = MII_CONN_NWAY;
	else
	    mode = MII_CONN_FORCED;
    } else if (Phy->PhyRegs[MII_STATUS] & MII_STATUS_NWAY_ABLE) {
	if (Phy->PhyRegs[MII_CONTROL] & MII_CONTROL_NWAY) {
	    if (!(Phy->PhyRegs[MII_STATUS] & MII_STATUS_NWAY_DONE)) {
		*status = MII_CONN_NWAY_PENDING;
		Phy->PreviousConnectionStatus = MII_CONN_NWAY_PENDING;
		return FALSE;
	    }
	    mode = MII_CONN_NWAY;
	} else
	    mode = MII_CONN_FORCED;
    } else
	mode = 0;

    if (Phy->PhyId != MII_PHY_ID_BROADCOM && mode == MII_CONN_NWAY) {
	Phy->PhyNwayGetLocalAbility(Adapter, Phy, &localAbility);
	Phy->PhyNwayGetPartnerAbility(Adapter, Phy, &partnerAbility);
	if (Phy->PhyId == MII_PHY_ID_DP83840) {
	    /*
	     * par is a u_long filled through a u_short pointer, so the
	     * speed bit is tested in the half the read never wrote.
	     */
	    if (Phy->PhyReadRegister(Adapter, Phy, DP83840_PAR,
		    (u_short *)&par)) {
		if (par & DP83840_PAR_SPEED_10)
		    common = localAbility & MII_NWAY_10BASET;
		else
		    common = localAbility & MII_NWAY_100BASETX;
	    }
	} else
	    common = localAbility & partnerAbility;

	if (common == 0) {
	    *status = mode;
	    Phy->PreviousConnectionStatus = mode;
	    return FALSE;
	}
    }

    /*
     * The status register latches link failures, so a link already seen
     * up is reported from the copy just read; otherwise read it again.
     */
    if ((Phy->PhyRegs[MII_STATUS] & MII_STATUS_LINK) &&
	((u_char)Phy->PreviousConnectionStatus == MII_LINK_PASS ||
	 (u_char)Phy->PreviousConnectionStatus == MII_LINK_UP))
	link = MII_LINK_PASS;
    else {
	if (!Phy->PhyReadRegister(Adapter, Phy, MII_STATUS,
		&Phy->PhyRegs[MII_STATUS])) {
	    Phy->PreviousConnectionStatus = *status;
	    return FALSE;
	}
	link = (Phy->PhyRegs[MII_STATUS] & MII_STATUS_LINK) >> 1;
    }

    *status = mode | link;
    Phy->PreviousConnectionStatus = mode | link;
    return (link > 0);
}

void
MiiPhyAdminControl(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy, u_long control)
{
    u_long adminStatus = 0;
    int i = 0;

    switch (control) {
    case MII_ADMIN_FORCE_10:
    case MII_ADMIN_FORCE_10_FD:
	Phy->PreviousControl = Phy->PhyRegs[MII_CONTROL];
	Phy->PhyRegs[MII_CONTROL] &= ~(MII_CONTROL_SPEED_100 |
	    MII_CONTROL_NWAY | MII_CONTROL_FULL_DUPLEX);
	Adapter->PhyIsolated = TRUE;
	break;

    case MII_ADMIN_RESTORE:
	Phy->PhyRegs[MII_CONTROL] = Phy->PreviousControl;
	Adapter->PhyIsolated = FALSE;
	break;

    case MII_ADMIN_OPERATIONAL:
	if ((Phy->PhyId & MII_PHY_ID_REV_MASK) == MII_PHY_ID_406210)
	    Phy->PhyWriteRegister(Adapter, Phy, PHY_406210_REG30, 0);
	/* fall through */
    default:
	Phy->PhyRegs[MII_CONTROL] &= ~(MII_CONTROL_RESET |
	    MII_CONTROL_POWER_DOWN | MII_CONTROL_ISOLATE);
	break;
    }

    Phy->PhyWriteRegister(Adapter, Phy, MII_CONTROL,
	Phy->PhyRegs[MII_CONTROL] | AdminControlConversionTable[control]);

    if (control == MII_ADMIN_RESET) {
	while (i++ <= 9999) {
	    Phy->PhyAdminStatus(Adapter, Phy, &adminStatus);
	    if (adminStatus != MII_ADMIN_RESET)
		break;
	}
    }
}

void
MiiPhyAdminStatus(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy, u_long *status)
{
    u_short control = 0;
    short retries = 2;

    do {
	Phy->PhyReadRegister(Adapter, Phy, MII_CONTROL, &control);
	if (control != 0)
	    break;
    } while (retries--);

    switch (control) {
    case MII_CONTROL_RESET:
	*status = MII_ADMIN_RESET;
	break;
    case MII_CONTROL_ISOLATE:
	*status = MII_ADMIN_ISOLATE;
	break;
    case MII_CONTROL_POWER_DOWN:
	*status = MII_ADMIN_POWER_DOWN;
	break;
    default:
	*status = MII_ADMIN_OPERATIONAL;
	break;
    }
}

/*
 * Returns TRUE when the PHY drove the turnaround bit low.
 */
BOOL
MiiPhyReadRegister(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy, u_short reg,
    u_short *data)
{
    u_long csr9;
    BOOL ack;
    int i;

    WriteMii(Adapter, MII_PREAMBLE, 32);
    WriteMii(Adapter, MII_READ_FRAME | (Phy->PhyAddress << MII_PHY_ADDR_SHIFT) |
	(reg << MII_REG_ADDR_SHIFT), 14);
    MiiOutThreeState(Adapter);

    csr9 = DC21X4_READ_CSR(Adapter, CSR9);
    *data = 0;
    ack = (csr9 & MII_DATA_IN) == 0;

    for (i = 0; i < 16; i++) {
	DC21X4_WRITE_CSR(Adapter, CSR9, MII_READ);
	IODelay(1);
	DC21X4_WRITE_CSR(Adapter, CSR9, MII_READ | MII_CLK);
	IODelay(1);
	csr9 = DC21X4_READ_CSR(Adapter, CSR9);
	IODelay(1);
	*data = (*data << 1) | ((csr9 >> MII_DATA_IN_SHIFT) & 1);
    }

    MiiOutThreeState(Adapter);
    *data &= ~PhyRegsReservedBitsMasks[reg];
    return ack;
}

void
MiiPhyWriteRegister(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy, u_short reg,
    u_short data)
{
    data &= ~PhyRegsReservedBitsMasks[reg];

    WriteMii(Adapter, MII_PREAMBLE, 32);
    WriteMii(Adapter, MII_WRITE_FRAME | (Phy->PhyAddress << MII_PHY_ADDR_SHIFT) |
	(reg << MII_REG_ADDR_SHIFT) | data, 32);
    MiiOutThreeState(Adapter);
}

void
MiiPhyNwayGetLocalAbility(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
    u_short *ability)
{
    if (Phy->PhyId == MII_PHY_ID_BROADCOM)
	*ability = Phy->PhyCapabilities >> 6;
    else if (Phy->PhyReadRegister(Adapter, Phy, MII_NWAY_ADVERTISE,
		 &Phy->PhyRegs[MII_NWAY_ADVERTISE]))
	*ability = Phy->PhyRegs[MII_NWAY_ADVERTISE] & MII_NWAY_MEDIA_MASK;
    else
	*ability = 0;
}

void
MiiPhyNwaySetLocalAbility(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
    u_short ability)
{
    if (Phy->PhyId != MII_PHY_ID_BROADCOM) {
	Phy->PhyMediaAdvertisement = ability;
	Phy->PhyRegs[MII_NWAY_ADVERTISE] = ability | MII_NWAY_SELECTOR_8023;
	Phy->PhyWriteRegister(Adapter, Phy, MII_NWAY_ADVERTISE,
	    Phy->PhyRegs[MII_NWAY_ADVERTISE]);
    }
}

void
MiiPhyNwayGetPartnerAbility(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
    u_short *ability)
{
    if (Phy->PhyReadRegister(Adapter, Phy, MII_NWAY_PARTNER,
	    &Phy->PhyRegs[MII_NWAY_PARTNER])) {
	Phy->PhyRegs[MII_NWAY_PARTNER] &= MII_NWAY_MEDIA_MASK;
	*ability = Phy->PhyRegs[MII_NWAY_PARTNER];
    } else
	*ability = 0;
}

/*
 * Read the PHY's register file into Phy->PhyRegs.  Registers 0 and 1
 * must answer; the PHY id is taken only when registers 2 and 3 do.
 */
BOOL
FindMiiPhyDevice(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy)
{
    u_short reg;
    u_short data;

    for (reg = MII_CONTROL; reg <= MII_STATUS; reg++) {
	if (!Phy->PhyReadRegister(Adapter, Phy, reg, &data))
	    return FALSE;
	Phy->PhyRegs[reg] = data;
    }
    for (; reg <= MII_PHY_ID2; reg++) {
	if (!Phy->PhyReadRegister(Adapter, Phy, reg, &data))
	    break;
	Phy->PhyRegs[reg] = data;
    }
    if (reg > MII_PHY_ID2)
	Phy->PhyId = (Phy->PhyRegs[MII_PHY_ID1] << 16) |
	    Phy->PhyRegs[MII_PHY_ID2];

    for (reg = MII_NWAY_ADVERTISE; reg <= 31; reg++) {
	if (!Phy->PhyReadRegister(Adapter, Phy, reg, &data))
	    break;
	Phy->PhyRegs[reg] = data;
    }

    if (Phy->PhyId == MII_PHY_ID_BROADCOM || Phy->PhyId == MII_PHY_ID_DP83840) {
	if (reg <= 31)
	    return FALSE;
    } else {
	/*
	 * Both tests OR where an AND was meant, so they are always true:
	 * every other PHY must answer through register 6.
	 */
	if ((Phy->PhyRegs[MII_STATUS] | MII_STATUS_NWAY_ABLE) &&
	    reg <= MII_NWAY_PARTNER)
	    return FALSE;
	if ((Phy->PhyRegs[MII_NWAY_ADVERTISE] | 0x8000) &&
	    reg <= MII_NWAY_EXPANSION)
	    return FALSE;
    }
    return (Phy->PhyRegs[MII_STATUS] != 0);
}

/*
 * Clock out the top count bits of data, MSB first.
 */
void
WriteMii(DC21X4_ADAPTER *Adapter, u_long data, int count)
{
    u_long dataOut;

    for (; count > 0; count--, data <<= 1) {
	dataOut = (data >> MII_DATA_OUT_SHIFT) & MII_DATA_OUT;
	DC21X4_WRITE_CSR(Adapter, CSR9, dataOut | MII_WRITE);
	IODelay(1);
	DC21X4_WRITE_CSR(Adapter, CSR9, dataOut | MII_WRITE | MII_CLK);
	IODelay(1);
    }
}

void
MiiOutThreeState(DC21X4_ADAPTER *Adapter)
{
    DC21X4_WRITE_CSR(Adapter, CSR9, MII_WRITE_TS);
    IODelay(1);
    DC21X4_WRITE_CSR(Adapter, CSR9, MII_WRITE_TS | MII_CLK);
    IODelay(1);
}

void
InitPhyInfoEntries(MII_PHY_INFO *Phy)
{
    Phy->PhyInit = MiiPhyInit;
    Phy->PhyGetCapabilities = MiiPhyGetCapabilities;
    Phy->PhySetConnectionType = MiiPhySetConnectionType;
    Phy->PhyGetConnectionType = MiiPhyGetConnectionType;
    Phy->PhyGetConnectionStatus = MiiPhyGetConnectionStatus;
    Phy->PhyAdminControl = MiiPhyAdminControl;
    Phy->PhyAdminStatus = MiiPhyAdminStatus;
    Phy->PhyReadRegister = MiiPhyReadRegister;
    Phy->PhyWriteRegister = MiiPhyWriteRegister;
    Phy->PhyNwayGetLocalAbility = MiiPhyNwayGetLocalAbility;
    Phy->PhyNwaySetLocalAbility = MiiPhyNwaySetLocalAbility;
    Phy->PhyNwayGetPartnerAbility = MiiPhyNwayGetPartnerAbility;
}

/*
 * Media code -> MII control bits.  The Broadcom PHY is not told to
 * restart Nway.
 */
void
ConvertConnectionToControl(MII_PHY_INFO *Phy, u_short *connection)
{
    u_short media = *connection;

    *connection = MediaToCommandConversionTable[MEDIA_INDEX(media)];
    if (media & MEDIA_NWAY_AUTOSENSE) {
	if (Phy->PhyId != MII_PHY_ID_BROADCOM)
	    *connection |= MII_CONTROL_RESTART_NWAY;
	*connection |= MII_CONTROL_NWAY;
    }
}

void
ConvertMediaTypeToNwayLocalAbility(u_short mediaType, u_short *ability)
{
    *ability = MediaToNwayConversionTable[MEDIA_INDEX(mediaType)];
}

/*
 * Pick the best common Nway medium.
 */
BOOL
ConvertNwayToConnectionType(u_short nway, u_short *connection)
{
    if (nway & MII_NWAY_100BASETX_FD)
	*connection = MEDIA_NWAY_AUTOSENSE | DC21X4_MEDIA_FULL_DUPLEX | 0x0e;
    else if (nway & MII_NWAY_100BASET4)
	*connection = MEDIA_NWAY_AUTOSENSE | 0x0f;
    else if (nway & MII_NWAY_100BASETX)
	*connection = MEDIA_NWAY_AUTOSENSE | 0x0d;
    else if (nway & MII_NWAY_10BASET_FD)
	*connection = MEDIA_NWAY_AUTOSENSE | DC21X4_MEDIA_FULL_DUPLEX | 0x0a;
    else if (nway & MII_NWAY_10BASET)
	*connection = MEDIA_NWAY_AUTOSENSE | 0x09;
    else
	return FALSE;
    return TRUE;
}

BOOL
CheckConnectionSupport(MII_PHY_INFO *Phy, u_short connection)
{
    if (connection & MEDIA_NWAY_AUTOSENSE)
	return ((Phy->PhyCapabilities & MII_STATUS_NWAY_ABLE) != 0);
    return ((Phy->PhyCapabilities &
	MediaToStatusConversionTable[MEDIA_INDEX(connection)]) != 0);
}

/*
 * When the Broadcom PHY's link comes up at 100 Mb/s after running at
 * 10, reset it and rewrite its control register.
 */
void
HandleBroadcomMediaChangeFrom10To100(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy)
{
    u_short auxStatus;

    Phy->PhyReadRegister(Adapter, Phy, BROADCOM_AUX_STATUS, &auxStatus);

    if (auxStatus != Phy->PhyRegs[BROADCOM_AUX_STATUS] &&
	(auxStatus & (BROADCOM_AUX_LINK | BROADCOM_AUX_SPEED_100)) ==
	    (BROADCOM_AUX_LINK | BROADCOM_AUX_SPEED_100) &&
	!(Phy->PhyRegs[BROADCOM_AUX_STATUS] & BROADCOM_AUX_SPEED_100)) {
	Phy->PhyAdminControl(Adapter, Phy, MII_ADMIN_RESET);
	Phy->PhyWriteRegister(Adapter, Phy, MII_CONTROL,
	    Phy->PhyRegs[MII_CONTROL]);
    }
    Phy->PhyRegs[BROADCOM_AUX_STATUS] = auxStatus;
}

/*
 * The Broadcom PHY reports its speed in the auxiliary status register;
 * 100 Mb/s is reported as 100BaseT4.
 */
BOOL
GetBroadcomPhyConnectionType(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
    u_short *connection)
{
    u_short auxStatus;

    if (!Phy->PhyReadRegister(Adapter, Phy, BROADCOM_AUX_STATUS, &auxStatus) ||
	!(auxStatus & BROADCOM_AUX_LINK) ||
	!Phy->PhyReadRegister(Adapter, Phy, MII_CONTROL,
	    &Phy->PhyRegs[MII_CONTROL]))
	return FALSE;

    if (auxStatus & BROADCOM_AUX_SPEED_100)
	*connection = 0x0f;		/* Mii100BaseT4 */
    else if (Phy->PhyRegs[MII_CONTROL] & MII_CONTROL_FULL_DUPLEX)
	*connection = DC21X4_MEDIA_FULL_DUPLEX | 0x0a;	/* Mii10BaseT_FD */
    else
	*connection = 0x09;		/* Mii10BaseT */

    if (Phy->PhyRegs[MII_CONTROL] & MII_CONTROL_NWAY)
	*connection |= MEDIA_NWAY_AUTOSENSE;
    return TRUE;
}
