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
 * DEC21x4SRom.m
 *
 * Serial ROM access and parsing for the DEC 21x4x Ethernet driver: SROM
 * reading, dumping and patching, and the DC21X4 SROM format parsers
 * that fill in the adapter's media tables.
 *
 * HISTORY
 *
 * Reconstructed for RhapsodiOS from the DEC21x4 code linked into the
 * Mac OS X Server 1.2v3 (kernel 5.6) ppc mach_kernel.
 */

#import "DEC21x4.h"

/* 21040 Ethernet address ROM, also read through CSR9 */
#define DC21040_ROM_SIZE	32
#define DC21040_ROM_DNV		0x80000000	/* data not valid */
#define DC21040_ROM_TIMEOUT	50

/* SROM layout */
#define SROM_ADDRESS		20	/* station address */
#define SROM_FORMAT_VERSION	18
#define SROM_DEVICE_NUMBER	26	/* first controller info */
#define SROM_LEAF_OFFSET	27
#define SROM_DE500_ID		29	/* board name in old DE500-XA SROMs */
#define SROM_LEGACY_CRC		94	/* 21041-era checksum position */
#define SROM_CRC		126

/* Media block command word (21140 and extended type 4 blocks) */
#define SROM_CMD_MODE_MASK	0x0071	/* PS, TTM, PCS, SCR >> 18 */
#define SROM_CMD_MODE_SHIFT	18
#define SROM_CMD_POLARITY	0x0080
#define SROM_CMD_SENSE_SHIFT	1
#define SROM_CMD_SENSE_MASK	0x0007
#define SROM_CMD_DEFAULT	0x4000
#define SROM_CMD_NO_SENSE	0x8000

/* Media block header bits */
#define SROM_MEDIA_CODE_MASK	0x3f
#define SROM_MEDIA_EXTENDED	0x40	/* 21041: CSR13-15 follow */
#define SROM_BLOCK_EXTENDED	0x80	/* 21140: extended format block */
#define SROM_BLOCK_LENGTH_MASK	0x7f

#define SROM_NO_AUTOSENSE	0x8000	/* connection type word */

/*
 * Standard (little-endian, reflected) CRC-32 table, for the SROM
 * checksum.
 */
u_long CrcTable[256] = {
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba,
    0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
    0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988,
    0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
    0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de,
    0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec,
    0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
    0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
    0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
    0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940,
    0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116,
    0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
    0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924,
    0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
    0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a,
    0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818,
    0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
    0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e,
    0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
    0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c,
    0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2,
    0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
    0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
    0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
    0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086,
    0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4,
    0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
    0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a,
    0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
    0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8,
    0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe,
    0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
    0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc,
    0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
    0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252,
    0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60,
    0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
    0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
    0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
    0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04,
    0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a,
    0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
    0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38,
    0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
    0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e,
    0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c,
    0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
    0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2,
    0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
    0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0,
    0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6,
    0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
    0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
    0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d,
};

static u_short
swaps(u_short data)
{
    return (data << 8) | (data >> 8);
}

static u_long
swapl(u_long data)
{
    return (data >> 24) | ((data >> 8) & 0xff00) |
	((data << 8) & 0xff0000) | (data << 24);
}

@implementation DEC21x4(DEC21x4SRom)

- (void)dumpSROM:(unsigned char *)srom size:(unsigned int)size
{
    unsigned int i;

    IOLog("%s - SROM Dump:\n", [self name]);
    IOLog("         0    2    4    6    8    a    c    e");
    for (i = 0; i < size / 2; i++) {
	if ((i & 7) == 0)
	    IOLog("\n%04x: ", i * 2);
	IOLog("%04x ", swaps(((u_short *)srom)[i]));
    }
    IOLog("\n");
}

/*
 * Read the station address straight from the SROM at enetAddressOffset
 * (set by a patch table entry).
 */
- (void)_getStationAddress:(enet_addr_t *)ea
{
    int i;
    u_short data;

    for (i = 0; i < sizeof(*ea) / 2; i++) {
	data = swaps(sromReadWord(ioBase, i + enetAddressOffset / 2,
	    sromAddressBits));
	ea->ea_byte[2 * i] = data & 0xff;
	ea->ea_byte[2 * i + 1] = data >> 8;
    }
}

/*
 * Markers whose (possibly indirect) offset falls outside the SROM are
 * ignored.
 */
- (BOOL)matchSROM:(unsigned char *)srom
       forMarkers:(const dcSromMarker_t *)markers
{
    int i;
    unsigned int offset;

    for (i = 0; i < SROM_MARKER_COUNT; i++, markers++) {
	offset = markers->offset;
	if (markers->indirect)
	    offset += srom[markers->indirect];
	if (offset < SROM_SIZE && markers->value != srom[offset])
	    return NO;
    }
    return YES;
}

- (BOOL)patchSROM:(unsigned char *)srom withSize:(unsigned int)size
	   offset:(int *)offset verbose:(BOOL)verbose
{
    BOOL patched = NO;
    int i, j;
    const dcSromPatch_t *patch;

    if (size != SROM_SIZE)
	return NO;

    for (i = 0; i < patchTableCount; i++) {
	patch = &patchTable[i];
	if (Adapter->DeviceId == patch->deviceId &&
	    [self matchSROM:srom forMarkers:patch->markers]) {
	    if (verbose)
		IOLog("%s: %s detected, SROM patched.\n", [self name],
		    patch->name);
	    patched = YES;
	    *offset = patch->enetAddressOffset;
	    for (j = 0; j < SROM_SIZE / 2; j++)
		((u_short *)srom)[j] =
		    (patch->srom[j] >> 8) | (patch->srom[j] << 8);
	    break;
	}
    }
    return patched;
}

- (BOOL)parseSROM:(BOOL)logMedia
{
    BOOL result;
    unsigned char *srom;
    int i, phy;

    if (Adapter->DeviceId == DC21040_CFID) {
	IOLog("%s: Faking SROM data for 21040\n", getDriverName(Adapter));
	result = DC21040Parser(Adapter);
    } else {
	if (userSROMData) {
	    if (dumpSROM)
		[self dumpSROM:userSROMData size:SROM_SIZE];
	    result = DC21X4ParseSRom(Adapter, userSROMData);
	} else {
	    srom = IOMalloc(SROM_SIZE);
	    if (srom == NULL) {
		IOLog("%s: Unable to allocate memory for SROM\n", [self name]);
		return NO;
	    }
	    for (i = 0; i < SROM_SIZE / 2; i++) {
		((u_short *)srom)[i] =
		    sromReadWord(ioBase, i, sromAddressBits);
	    }
	    if (dumpSROM)
		[self dumpSROM:srom size:SROM_SIZE];
	    enetAddressOffset = -1;
	    if (patchSROM)
		[self patchSROM:srom withSize:SROM_SIZE
		    offset:&enetAddressOffset verbose:logMedia];
	    result = DC21X4ParseSRom(Adapter, srom);
	    IOFree(srom, SROM_SIZE);
	}
	if (enetAddressOffset != -1)
	    [self _getStationAddress:
		(enet_addr_t *)Adapter->PermanentAddress];
    }

    if (!result) {
	IOLog("%s: Error while parsing SROM\n", [self name]);
	return NO;
    }

    if (logMedia) {
	IOLog("%s: SROM format version: 0x%02x\n", getDriverName(Adapter),
	    Adapter->SromFormatVersion);
	for (i = 0; i < DC21X4_MEDIA_STRING_COUNT; i++) {
	    if ((Adapter->MediaCapable >> i) & 1)
		IOLog("%s: SROM Medium: %s\n", [self name], MediumString[i]);
	}
	if (Adapter->PhyMediaInSrom) {
	    for (phy = 0; phy < DC21X4_MAX_PHY; phy++) {
		if (!Adapter->PhyMediaInfo[phy].Present)
		    continue;
		for (i = 0; i < DC21X4_MEDIA_STRING_COUNT; i++) {
		    if (MediaBitTable[i] &
			Adapter->PhyMediaInfo[phy].MediaCapabilities)
			IOLog("%s: SROM PHY%d Medium: %s\n", [self name],
			    phy, MediumString[i]);
		}
	    }
	}
    }

    MediaCapableSaved = Adapter->MediaCapable;
    return YES;
}

@end

/*
 * The 21040 has no SROM, only a 32-byte Ethernet address ROM read
 * through CSR9; the media tables are fixed.
 */
BOOL
DC21040Parser(DC21X4_ADAPTER *Adapter)
{
    u_char addressRom[DC21040_ROM_SIZE];
    u_long data;
    unsigned int i;
    int timeout;

    Adapter->MediaCapable = (1 << DC21X4_MEDIA_10BASET) |
	(1 << DC21X4_MEDIA_10BASE2) | (1 << DC21X4_MEDIA_10BASE5);

    /* reset the ROM pointer */
    DC21X4_WRITE_CSR(Adapter, CSR9, 0);

    for (i = 0; i < DC21040_ROM_SIZE; i++) {
	timeout = DC21040_ROM_TIMEOUT;
	do {
	    IODelay(1000);
	    data = DC21X4_READ_CSR(Adapter, CSR9);
	    if (!(data & DC21040_ROM_DNV))
		break;
	} while (timeout-- > 0);
	/* XXX also fails when the data arrives on the very last poll */
	if (timeout <= 0)
	    return FALSE;
	addressRom[i] = data;
    }

    /*
     * XXX The 0x0095c000 test was written for a little-endian host
     * (Zynx OUI 00:c0:95 in bytes 0-2); on ppc it looks at bytes 1-3.
     */
    if (*(u_long *)&addressRom[0] == 0 && *(u_short *)&addressRom[4] == 0)
	Adapter->SromChecksumValid = FALSE;
    else if ((*(u_long *)&addressRom[0] & 0x00ffffff) == 0x0095c000)
	Adapter->SromChecksumValid = TRUE;
    else
	Adapter->SromChecksumValid = VerifyChecksum(addressRom);

    if (!Adapter->SromChecksumValid)
	return FALSE;

    bcopy(addressRom, Adapter->PermanentAddress, 6);

    Adapter->Media[DC21X4_MEDIA_10BASET].Csr13 = 0x8f01;
    Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 = 0xffff;
    Adapter->Media[DC21X4_MEDIA_10BASET].Csr15 = 0;
    Adapter->Media[DC21X4_MEDIA_10BASE2].Csr13 = 0xef09;
    Adapter->Media[DC21X4_MEDIA_10BASE2].Csr14 = 0x0705;
    Adapter->Media[DC21X4_MEDIA_10BASE2].Csr15 = 6;
    Adapter->Media[DC21X4_MEDIA_10BASE5].Csr13 = 0x8f09;
    Adapter->Media[DC21X4_MEDIA_10BASE5].Csr14 = 0x0705;
    Adapter->Media[DC21X4_MEDIA_10BASE5].Csr15 = 6;

    return TRUE;
}

u_long
CRC32(u_char *data, int len)
{
    u_long crc = 0xffffffff;

    while (len--)
	crc = CrcTable[(crc ^ *data++) & 0xff] ^ (crc >> 8);

    return ~crc;
}

/*
 * DEC address ROM checksum: an end-around-carry sum of the three
 * address words, doubled before each add, stored big-endian after the
 * address.
 */
BOOL
VerifyChecksum(u_char *data)
{
    u_long sum = 0;
    unsigned int i;
    u_char check[2];

    for (i = 0; i < 3; i++) {
	sum <<= 1;
	if (sum > 0xffff)
	    sum -= 0xffff;
	sum += (data[2 * i] << 8) + data[2 * i + 1];
	if (sum > 0xffff)
	    sum -= 0xffff;
    }
    if (sum > 0xfffe)
	sum = 0;

    check[0] = sum >> 8;
    check[1] = sum;
    return *(u_short *)check == *(u_short *)&data[6];
}

/*
 * Parse one extended format info leaf block (21140 version 3+, 21142,
 * 21143) and advance *block past it.
 */
void
DC21X4ParseExtendedBlock(DC21X4_ADAPTER *Adapter, u_char **block,
    u_short generalPurposeCtrl, u_char *mediaCode)
{
    u_char		*ptr = *block;
    u_char		*next;
    u_int		length, type, medium;
    int			phyNumber, i;
    DC21X4_PHY_MEDIA	*phy;
    DC21X4_MEDIA_TABLE	*media;

    length = *ptr++ & SROM_BLOCK_LENGTH_MASK;
    type = *ptr++;
    next = *block + 1 + length;

    switch (type) {

    case 0:		/* 21140 non-MII medium, compact format */
	DC21X4ParseFixedBlock(Adapter, &ptr, generalPurposeCtrl, mediaCode);
	break;

    case 1:		/* 21140 MII PHY */
    case 3:		/* 21142/21143 MII PHY */
	phyNumber = *ptr++;
	if (phyNumber >= DC21X4_MAX_PHY)
	    break;
	phy = &Adapter->PhyMediaInfo[phyNumber];
	phy->GeneralPurposeCtrl = generalPurposeCtrl;

	phy->GepSequenceLength = *ptr++;
	if (phy->GepSequenceLength > DC21X4_MAX_GEP_SEQUENCE)
	    break;
	if (type == 1) {
	    for (i = 0; i < phy->GepSequenceLength; i++)
		phy->GepSequence[i] = *ptr++;
	} else if (type == 3) {
	    /* a type 3 sequence starts with the GEP control word */
	    if (phy->GepSequenceLength) {
		phy->GeneralPurposeCtrl = swaps(*(u_short *)ptr);
		phy->GepSequenceLength--;
		ptr += 2;
	    }
	    for (i = 0; i < phy->GepSequenceLength; i++) {
		phy->GepSequence[i] = swaps(*(u_short *)ptr);
		ptr += 2;
	    }
	}

	phy->ResetSequenceLength = *ptr++;
	if (phy->ResetSequenceLength > DC21X4_MAX_GEP_SEQUENCE)
	    break;
	if (type == 1) {
	    for (i = 0; i < phy->ResetSequenceLength; i++)
		phy->ResetSequence[i] = *ptr++;
	} else if (type == 3) {
	    for (i = 0; i < phy->ResetSequenceLength; i++) {
		phy->ResetSequence[i] = swaps(*(u_short *)ptr);
		ptr += 2;
	    }
	}

	phy->MediaCapabilities = swaps(*(u_short *)ptr) & 0xf800;
	ptr += 2;
	phy->NwayAdvertisement = swaps(*(u_short *)ptr) & 0x03e0;
	ptr += 2;
	phy->FullDuplexBits = swaps(*(u_short *)ptr) & 0xf800;
	ptr += 2;
	phy->TxThresholdBits = swaps(*(u_short *)ptr) & 0xf800;
	ptr += 2;
	phy->Present = TRUE;
	Adapter->PhyMediaInSrom = TRUE;

	if (type == 3)
	    phy->Interrupt = *ptr++ << 29;

	/* sequence dumps, compiled out */
	for (i = 0; i < phy->GepSequenceLength; i++)
	    ;
	for (i = 0; i < phy->ResetSequenceLength; i++)
	    ;
	break;

    case 2:		/* 21142/21143 SIA medium */
	medium = *ptr & SROM_MEDIA_CODE_MASK;
	if (medium >= DC21X4_MEDIA_COUNT)
	    break;
	Adapter->MediaCapable |= 1 << medium;
	media = &Adapter->Media[medium];
	if (*ptr++ & SROM_MEDIA_EXTENDED) {
	    media->Csr13 = swaps(*(u_short *)ptr);
	    media->Csr14 = swaps(*(u_short *)(ptr + 2));
	    media->Csr15 = swaps(*(u_short *)(ptr + 4));
	    ptr += 6;
	}
	media->GeneralPurposeCtrl = swaps(*(u_short *)ptr);
	ptr += 2;
	media->GeneralPurposeData = swaps(*(u_short *)ptr);
	SRomLocalAdvertisement(Adapter, medium);
	*mediaCode = medium;
	break;

    case 4:		/* 21142/21143 SYM medium */
	medium = *ptr++ & SROM_MEDIA_CODE_MASK;
	if (medium >= DC21X4_MEDIA_COUNT)
	    break;
	Adapter->MediaCapable |= 1 << medium;
	media = &Adapter->Media[medium];
	media->GeneralPurposeCtrl = swaps(*(u_short *)ptr);
	media->GeneralPurposeData = swaps(*(u_short *)(ptr + 2));
	media->Mode = (swapl(*(u_long *)(ptr + 4)) & SROM_CMD_MODE_MASK)
	    << SROM_CMD_MODE_SHIFT;
	media->Polarity = (swapl(*(u_long *)(ptr + 4)) & SROM_CMD_POLARITY) ?
	    0xffffffff : 0;
	media->SenseMask = (swapl(*(u_long *)(ptr + 4)) & SROM_CMD_NO_SENSE) ?
	    0 : 1 << ((swapl(*(u_long *)(ptr + 4)) >> SROM_CMD_SENSE_SHIFT) &
		      SROM_CMD_SENSE_MASK);
	media->Mode |= (media->Mode & DC_CSR6_TTM) ?
	    Adapter->Threshold10Mbps : Adapter->Threshold100Mbps;
	if (media->SenseMask &&
	    medium != DC21X4_MEDIA_10BASET_FD &&
	    medium != DC21X4_MEDIA_100BASETX_FD &&
	    medium != DC21X4_MEDIA_100BASEFX_FD)
	    Adapter->MediaPrecedence[Adapter->MediaCount++] = medium;
	/* XXX tests the GEP words at ptr, not the command word at ptr + 4 */
	if (swapl(*(u_long *)ptr) & SROM_CMD_DEFAULT) {
	    Adapter->DefaultMediumFound = TRUE;
	    Adapter->DefaultMedium = medium;
	}
	SRomLocalAdvertisement(Adapter, medium);
	*mediaCode = medium;
	break;

    case 5:		/* PHY reset sequence */
	Adapter->GepSequenceLength = *ptr++;
	if (Adapter->GepSequenceLength > DC21X4_MAX_GEP_SEQUENCE)
	    break;
	for (i = 0; i < Adapter->GepSequenceLength; i++) {
	    Adapter->GepSequence[i] = swaps(*(u_short *)ptr);
	    ptr += 2;
	}
	/* sequence dump, compiled out */
	for (i = 0; i < Adapter->GepSequenceLength; i++)
	    ;
	break;
    }

    *block = next;
}

/*
 * Parse one 21140 compact (fixed format) media block: media code, GEP
 * data byte, command word.  Advances *block past it.
 */
void
DC21X4ParseFixedBlock(DC21X4_ADAPTER *Adapter, u_char **block,
    u_short generalPurposeCtrl, u_char *mediaCode)
{
    u_char		*ptr = *block;
    u_int		medium;
    DC21X4_MEDIA_TABLE	*media;

    medium = *ptr & SROM_MEDIA_CODE_MASK;
    if (medium >= DC21X4_MEDIA_COUNT) {
	ptr += 10;		/* XXX a compact block is 4 bytes */
    } else {
	Adapter->MediaCapable |= 1 << medium;
	media = &Adapter->Media[medium];
	media->GeneralPurposeCtrl = generalPurposeCtrl;
	media->GeneralPurposeData = *++ptr;
	ptr++;
	media->Mode = (swapl(*(u_long *)ptr) & SROM_CMD_MODE_MASK)
	    << SROM_CMD_MODE_SHIFT;
	media->Polarity = (swapl(*(u_long *)ptr) & SROM_CMD_POLARITY) ?
	    0xffffffff : 0;
	media->SenseMask = (swapl(*(u_long *)ptr) & SROM_CMD_NO_SENSE) ?
	    0 : 1 << ((swapl(*(u_long *)ptr) >> SROM_CMD_SENSE_SHIFT) &
		      SROM_CMD_SENSE_MASK);
	media->Mode |= (media->Mode & DC_CSR6_TTM) ?
	    Adapter->Threshold10Mbps : Adapter->Threshold100Mbps;
	if (media->SenseMask &&
	    medium != DC21X4_MEDIA_10BASET_FD &&
	    medium != DC21X4_MEDIA_100BASETX_FD &&
	    medium != DC21X4_MEDIA_100BASEFX_FD)
	    Adapter->MediaPrecedence[Adapter->MediaCount++] = medium;
	if (swapl(*(u_long *)ptr) & SROM_CMD_DEFAULT) {
	    Adapter->DefaultMediumFound = TRUE;
	    Adapter->DefaultMedium = medium;
	}
	SRomLocalAdvertisement(Adapter, medium);
	*mediaCode = medium;
	ptr += 2;
    }
    *block = ptr;
}

/*
 * Validate an SROM image, take the station address from it and build
 * the adapter's media tables from its info leaf.
 */
BOOL
DC21X4ParseSRom(DC21X4_ADAPTER *Adapter, u_char *srom)
{
    /* 21140 info leaf assumed for legacy (pre-version 1) SROMs */
    u_char	legacyLeaf[20] = {
	0x00, 0x08,			/* connection type: autosense */
	0x1f,				/* GEP control */
	0x04,				/* block count */
	0x00, 0x0b, 0x8e, 0x00,		/* 10BaseT */
	0x03, 0x1b, 0x6d, 0x00,		/* 100BaseTX */
	0x04, 0x03, 0x8e, 0x00,		/* 10BaseT full duplex */
	0x05, 0x1b, 0x6d, 0x00,		/* 100BaseTX full duplex */
    };
    char	de500Name[] = "DE500-XA";
    struct {
	u_char	DeviceNumber;
	u_short	LeafOffset;
    } controller;
    u_char	*leaf;
    u_char	*block;
    u_char	mediaCode;
    u_short	generalPurposeCtrl;
    int		blockCount = 0;
    int		i;
    BOOL	result = TRUE;

    if ((u_short)CRC32(srom, SROM_CRC) !=
	    swaps(*(u_short *)&srom[SROM_CRC]) &&
	(u_short)CRC32(srom, SROM_LEGACY_CRC) !=
	    swaps(*(u_short *)&srom[SROM_LEGACY_CRC])) {
	/*
	 * No valid SROM checksum.  A 21140 with an old style address
	 * ROM image gets the default leaf above.
	 */
	if (Adapter->DeviceId != DC21140_CFID ||
	    (*(u_long *)&srom[0] == 0 && *(u_short *)&srom[4] == 0) ||
	    !VerifyChecksum(srom)) {
	    IOLog("%s: Invalid SROM Checksum, aborting...\n",
		getDriverName(Adapter));
	    return FALSE;
	}
	IOLog("%s: Legacy SROM found...\n", getDriverName(Adapter));
	IOLog("%s: Network interface may not function correctly\n",
	    getDriverName(Adapter));
	bcopy(srom, Adapter->PermanentAddress, 6);
	srom[SROM_FORMAT_VERSION] = 0;
	leaf = legacyLeaf;
    }

    /* Toshiba (subsystem vendor 0x1179, id 0x0204) */
    if (swaps(*(u_short *)&srom[0]) == 0x1179 &&
	swaps(*(u_short *)&srom[2]) == 0x0204)
	Adapter->KeepSiaLinkInterrupts = TRUE;

    Adapter->SromFormatVersion = srom[SROM_FORMAT_VERSION];

    switch (srom[SROM_FORMAT_VERSION]) {
    case 0:
	/* XXX leaf is only set when the legacy path above was taken */
	break;
    case 1:
    case 3:
    case 4:
	controller.DeviceNumber = srom[SROM_DEVICE_NUMBER];
	/* XXX only the low byte of the leaf offset */
	controller.LeafOffset = srom[SROM_LEAF_OFFSET];
	if (*(u_long *)&srom[SROM_ADDRESS] == 0 &&
	    *(u_short *)&srom[SROM_ADDRESS + 4] == 0) {
	    IOLog("%s: NULL Network Address\n", getDriverName(Adapter));
	    return FALSE;
	}
	bcopy(&srom[SROM_ADDRESS], Adapter->PermanentAddress, 6);
	leaf = srom + controller.LeafOffset;
	break;
    default:
	IOLog("%s: Unsupported SROM format version (0x%02x)!\n",
	    getDriverName(Adapter), srom[SROM_FORMAT_VERSION]);
	return FALSE;
    }

    Adapter->MediaCapable = 0;

    switch (Adapter->DeviceId) {

    case DC21041_CFID:
	Adapter->Media[DC21X4_MEDIA_10BASET].Csr13 = 0xef01;
	Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 = 0xff3f;
	Adapter->Media[DC21X4_MEDIA_10BASET].Csr15 = 0x0008;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Csr13 = 0xef09;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Csr14 = 0x0705;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Csr15 = 0x0006;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Csr13 = 0xef09;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Csr14 = 0x0705;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Csr15 = 0x000e;

	swaps(*(u_short *)leaf);		/* connection type, unused */
	leaf += 2;
	blockCount = *leaf++;

	for (i = 0; i < blockCount; i++) {
	    block = leaf;
	    mediaCode = *block & SROM_MEDIA_CODE_MASK;
	    if (mediaCode >= DC21X4_MEDIA_COUNT) {
		/* XXX skips 16 or 4 bytes; the block is 7 or 1 */
		leaf = (*block & SROM_MEDIA_EXTENDED) ? block + 16 : block + 4;
		continue;
	    }
	    Adapter->MediaCapable |= 1 << mediaCode;
	    leaf = block + 1;
	    if (*block & SROM_MEDIA_EXTENDED) {
		Adapter->Media[mediaCode].Csr13 =
		    swaps(*(u_short *)(block + 1));
		Adapter->Media[mediaCode].Csr14 =
		    swaps(*(u_short *)(block + 3));
		Adapter->Media[mediaCode].Csr15 =
		    swaps(*(u_short *)(block + 5));
		leaf = block + 7;
	    }
	}
	break;

    case DC21140_CFID:
	if (srom[SROM_FORMAT_VERSION] <= 1 && Adapter->RevisionNumber == 0x11)
	    /* early DE500-XA SROMs: trust the board name, not the leaf */
	    Adapter->AutoSenseCapable =
		*(u_long *)&srom[SROM_DE500_ID] == *(u_long *)&de500Name[0] &&
		*(u_long *)&srom[SROM_DE500_ID + 4] == *(u_long *)&de500Name[4];
	else
	    Adapter->AutoSenseCapable =
		!(swaps(*(u_short *)leaf) & SROM_NO_AUTOSENSE);
	leaf += 2;
	generalPurposeCtrl = *leaf++ | 0x100;
	blockCount = *leaf++;

	for (i = 0; i < blockCount; i++) {
	    if (srom[SROM_FORMAT_VERSION] > 2 &&
		(*leaf & SROM_BLOCK_EXTENDED))
		DC21X4ParseExtendedBlock(Adapter, &leaf, generalPurposeCtrl,
		    &mediaCode);
	    else
		DC21X4ParseFixedBlock(Adapter, &leaf, generalPurposeCtrl,
		    &mediaCode);
	}
	if (!Adapter->DefaultMediumFound && Adapter->MediaCount > 0)
	    Adapter->DefaultMedium =
		Adapter->MediaPrecedence[Adapter->MediaCount - 1];
	break;

    case DC21142_CFID:
    case DC21143_CFID:
	if (srom[SROM_FORMAT_VERSION] <= 2)
	    return FALSE;

	Adapter->Media[DC21X4_MEDIA_10BASET].Csr13 = 0x0001;
	Adapter->Media[DC21X4_MEDIA_10BASET].Csr14 = 0x7f3f;
	Adapter->Media[DC21X4_MEDIA_10BASET].Csr15 = 0x0008;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Csr13 = 0x0009;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Csr14 = 0x0705;
	Adapter->Media[DC21X4_MEDIA_10BASE2].Csr15 = 0x0006;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Csr13 = 0x0009;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Csr14 = 0x0705;
	Adapter->Media[DC21X4_MEDIA_10BASE5].Csr15 = 0x000e;

	Adapter->AutoSenseCapable =
	    !(swaps(*(u_short *)leaf) & SROM_NO_AUTOSENSE);
	blockCount = leaf[2];
	leaf += 3;

	for (i = 0; i < blockCount; i++)
	    DC21X4ParseExtendedBlock(Adapter, &leaf, 0, &mediaCode);

	if (!Adapter->DefaultMediumFound && Adapter->MediaCount > 0)
	    Adapter->DefaultMedium =
		Adapter->MediaPrecedence[Adapter->MediaCount - 1];
	break;

    default:
	result = FALSE;
	break;
    }

    /* a single non-MII medium is used as is */
    if (blockCount == 1 && Adapter->MediaCapable &&
	!Adapter->PhyMediaInSrom) {
	Adapter->MediaType &= ~(DC21X4_MEDIA_AUTOSENSE | 0xff);
	Adapter->MediaType |= mediaCode;
    }

    /* no SIA medium: the port is MII/SYM */
    if (!(Adapter->MediaCapable & ((1 << DC21X4_MEDIA_10BASET) |
	    (1 << DC21X4_MEDIA_10BASE2) | (1 << DC21X4_MEDIA_10BASE5))))
	Adapter->OperationMode |= DC_CSR6_PS;

    return result;
}

/*
 * Accumulate the CSR14/CSR6 Nway advertisement bits and the link code
 * word ability bits for one medium.
 */
void
SRomLocalAdvertisement(DC21X4_ADAPTER *Adapter, u_char mediaCode)
{
    switch (mediaCode) {
    case DC21X4_MEDIA_10BASET:
	Adapter->MediaNwayAdvertisement |= 0x00000040;
	Adapter->NwayLocalAbility |= 0x00200000;
	break;
    case DC21X4_MEDIA_100BASETX:
	Adapter->MediaNwayAdvertisement |= 0x00810000;
	Adapter->NwayLocalAbility |= 0x00800000;
	break;
    case DC21X4_MEDIA_10BASET_FD:
	Adapter->MediaNwayAdvertisement |= 0x00000240;
	Adapter->NwayLocalAbility |= 0x00400000;
	break;
    case DC21X4_MEDIA_100BASETX_FD:
	Adapter->MediaNwayAdvertisement |= 0x00820200;
	Adapter->NwayLocalAbility |= 0x01000000;
	break;
    case DC21X4_MEDIA_100BASET4:
	Adapter->MediaNwayAdvertisement |= 0x00840000;
	Adapter->NwayLocalAbility |= 0x02000000;
	break;
    }
}
