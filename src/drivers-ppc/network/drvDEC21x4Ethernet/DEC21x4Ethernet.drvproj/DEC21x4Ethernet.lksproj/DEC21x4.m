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
 * DEC21x4.m
 *
 * Public methods of the DEC 21x4x mbuf-based Ethernet driver: probe,
 * initialization from the config table, multicast/promiscuous control,
 * statistics export and power management, plus the C glue the media
 * code calls back into.
 *
 * HISTORY
 *
 * Reconstructed for RhapsodiOS from the DEC21x4 code linked into the
 * Mac OS X Server 1.2v3 (kernel 5.6) ppc mach_kernel.
 */

#import "DEC21x4.h"

#import <string.h>
#import <bsd/sys/systm.h>		/* bcopy, sprintf, strtoul, strchr */
#import <machdep/ppc/interrupts.h>	/* pmac_register_int, SPLNET */
#import <mach/vm_param.h>		/* page_size */

/*
 * GET_DEBUGINFO snapshot, returned by -getCharValues:forParameter:count:.
 */
typedef struct {
    unsigned int	ioBase;
    unsigned short	irq;
    enet_addr_t		address;
    char		multicastEnabled;
    char		ready;
    unsigned int	txPutIndex;
    unsigned int	txDoneIndex;
    unsigned int	txNumFree;
    unsigned int	Qcount;
    unsigned int	rxDoneIndex;
} dcDebugInfo_t;

/*
 * Transmit threshold choices ("TX Threshold" 0-4): CSR6 TR bits for each
 * speed and the byte counts they stand for.
 */
typedef struct {
    u_long	csr6_10;
    u_long	csr6_100;
    char	*name10;
    char	*name100;
} dcTxThreshold_t;

int irq_size = 0;
int inst = 0;

static dcTxThreshold_t Treshold_Map[] = {
    { 0x00000000, 0x00000000, "72",  "128"  },
    { 0x00004000, 0x00004000, "96",  "256"  },
    { 0x00008000, 0x00008000, "128", "512"  },
    { 0x0000c000, 0x0000c000, "160", "1024" },
    { DC_CSR6_SF, DC_CSR6_SF, "SF",  "SF"   },
};

int		irq_regs[8];		/* interrupts already registered */
dcIrqEntry_t	irq_table[DEC21X4_MAX_INSTANCES];

static __inline__ unsigned int
_atoi(const char *s)
{
    char *cptr;
    unsigned int val;

    cptr = (char *)s;
    while (*cptr && ((*cptr == ' ') || (*cptr == '\t') || (*cptr == '\n')))
	cptr++;

    val = 0;
    if (*cptr == '\0')
	return 0;

    while ((*cptr != ' ') && (*cptr != '\t') && (*cptr != '\n')) {
	if ((*cptr >= '0') && (*cptr <= '9'))
	    val = val * 10 + (*cptr - '0');
	++cptr;
	if (*cptr == '\0')
	    break;
    }

    return val;
}

static BOOL
irq_registered(int irq)
{
    int i;

    for (i = 0; i < irq_size; i++)
	if (irq_regs[i] == irq)
	    return YES;
    return NO;
}

@implementation DEC21x4

/*
 * Glue for the media code, which knows only the adapter structure.
 * Defined inside the implementation for access to the driver's ivars.
 */
void
mediaTimeoutOccurred(DC21X4_ADAPTER *Adapter)
{
    DEC21x4 *driver = (DEC21x4 *)Adapter->Driver;
    int s;

    driver->_kdbLock(driver, @selector(reserveDebuggerLock));
    s = splnet();
    DC21X4DynamicAutoSense(NULL, Adapter, NULL, NULL);
    splx(s);
    driver->_kdbUnlock(driver, @selector(releaseDebuggerLock));
}

void
sendPacket(DC21X4_ADAPTER *Adapter, void *pkt, unsigned int len)
{
    [(DEC21x4 *)Adapter->Driver sendPacket:pkt length:len];
}

const char *
getDriverName(DC21X4_ADAPTER *Adapter)
{
    return [(DEC21x4 *)Adapter->Driver name];
}

+ (BOOL)probe:(IOPCIDevice *)devDesc
{
    UInt32	deviceId, classRev, command, cfdd;
    id		dev;

    if (inst == DEC21X4_MAX_INSTANCES) {
	IOLog("DEC21X4: Too many devices probed, max=%d\n",
	    DEC21X4_MAX_INSTANCES);
	return NO;
    }

    if ([devDesc numInterrupts] != 1) {
	IOLog("%s: Incorrect number of interrupts -> %d\n",
	    [self name], [devDesc numInterrupts]);
	return NO;
    }

    if ([devDesc configReadLong:0x00 value:&deviceId]) {
	IOLog("%s: Failed PCI configuration space access - aborting",
	    [self name]);
	return NO;
    }
    if ([devDesc configReadLong:0x08 value:&classRev]) {
	IOLog("%s: Failed PCI configuration space access - aborting",
	    [self name]);
	return NO;
    }

    /*
     * Command register: memory space, bus master, memory write and
     * invalidate, parity error response; no I/O space.
     */
    if ([devDesc configReadLong:0x04 value:&command]) {
	IOLog("%s: Failed PCI configuration space access - aborting",
	    [self name]);
	return NO;
    }
    command = (command & ~0x01) | 0x56;
    if ([devDesc configWriteLong:0x04 value:command]) {
	IOLog("%s: Failed PCI configuration space access - aborting\n",
	    [self name]);
	return NO;
    }

    /* CFDD: wake the chip from sleep/snooze mode */
    if ([devDesc configReadLong:0x40 value:&cfdd]) {
	IOLog("Invalid PCI configuration or failed configuration space "
	    "access - aborting\n");
	return NO;
    }
    cfdd &= 0x3fffffff;
    if ([devDesc configWriteLong:0x40 value:cfdd]) {
	IOLog("Failed PCI configuration space access - aborting\n");
	return NO;
    }
    IOSleep(20);

    dev = [self alloc];
    if (dev == nil) {
	IOLog("%s: Failed to alloc instance\n", [self name]);
	return NO;
    }

    return [dev initFromDeviceDescription:devDesc] != nil;
}

- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IOPCIDevice		*deviceDescription = (IOPCIDevice *)devDesc;
    id			configTable;
    UInt32		deviceId, classRev;
    IORange		*range;
    unsigned int	memStart, memSize;
    vm_address_t	virtAddr;
    const char		*chipName;
    const char		*params;
    const char		*sromParams;
    char		sromKey[12];
    unsigned short	sromWord;
    unsigned int	threshold;
    int			sromLine, sromCount;
    BOOL		sromFound;
    int			connector, i;
    enet_addr_t		myAddress;

    configTable = [deviceDescription configTable];

    if ([super initFromDeviceDescription:devDesc] == nil)
	return nil;

    ready = NO;
    isPromiscuous = NO;
    multicastEnabled = NO;
    filterMode = FILTER_PERFECT;
    bzero(&drvstat, sizeof(drvstat));
    driver_task = IOVmTaskSelf();
    disableFlush = NO;
    captureEffect = NO;
    logMediaTypes = YES;
    bzero(&kdbQueue, sizeof(kdbQueue));

    Adapter = (DC21X4_ADAPTER *)IOMalloc(sizeof(DC21X4_ADAPTER));
    if (Adapter == NULL) {
	IOLog("%s: Adapter structure memory allocation failed\n",
	    [self name]);
	return [self free];
    }
    bzero(Adapter, sizeof(DC21X4_ADAPTER));
    Adapter->Driver = self;
    Adapter->TimerState = DC21X4_TIMER_IDLE;

    if ([deviceDescription configReadLong:0x00 value:&deviceId]) {
	IOLog("%s: Failed PCI configuration space access - aborting\n",
	    [self name]);
	return [self free];
    }
    Adapter->DeviceId = deviceId;

    if ([deviceDescription configReadLong:0x08 value:&classRev]) {
	IOLog("%s: Failed PCI configuration space access - aborting\n",
	    [self name]);
	return [self free];
    }
    Adapter->RevisionNumber = classRev & 0xff;

    /* the CSRs are in the last memory range */
    range = [deviceDescription memoryRangeList];
    range += [deviceDescription numMemoryRanges];
    memStart = range[-1].start;
    memSize = range[-1].size;
    if ([self mapMemoryRange:[deviceDescription numMemoryRanges] - 1
			  to:&virtAddr findSpace:YES cache:IO_CacheOff]) {
	IOLog("%s: mapMemoryRange failed for 0x%x..0x%x\n",
	    [self name], memStart, memSize);
	return [self free];
    }
    ioBase = virtAddr + (memStart & (page_size - 1));
    Adapter->PortOffset = ioBase;

    irq = [deviceDescription interrupt];

    /* The 21143 shares the 21142's device id; tell them apart by revision. */
    if (Adapter->DeviceId == DC21142_CFID
	    && (Adapter->RevisionNumber & 0xf0) != 0x10)
	Adapter->DeviceId = DC21143_CFID;

    switch (Adapter->DeviceId) {
	case DC21040_CFID:
	    chipName = "DECchip 21040";
	    break;
	case DC21041_CFID:
	    chipName = "DECchip 21041";
	    break;
	case DC21140_CFID:
	    chipName = "DECchip 21140";
	    break;
	case DC21142_CFID:
	    chipName = "DECchip 21142";
	    break;
	case DC21143_CFID:
	    chipName = "DECchip 21143";
	    break;
	default:
	    IOLog("%s: Unknown device. DeviceID:0x%08x Rev:0x%02x\n",
		[self name], Adapter->DeviceId, Adapter->RevisionNumber);
	    return [self free];
    }
    IOLog("%s: %s (Rev:0x%02x) at mem 0x%x irq %d\n", [self name],
	chipName, Adapter->RevisionNumber, memStart, irq);

    /* Address bits needed depends upon SROM size. */
    sromAddressBits = 6;
    params = [configTable valueForStringKey:"SROM Address Bits"];
    if (params) {
	if (strcmp(params, "8") == 0)
	    sromAddressBits = 8;
	[configTable freeString:params];
    }

    threshold = 2;
    params = [configTable valueForStringKey:"TX Threshold"];
    if (params) {
	threshold = _atoi(params);
	[configTable freeString:params];
    }
    if (threshold > 4)
	threshold = 4;
    txThresh10 = Treshold_Map[threshold].csr6_10;
    txThresh100 = Treshold_Map[threshold].csr6_100;
    IOLog("%s: Transmit thresholds: %s/%s\n", [self name],
	Treshold_Map[threshold].name100, Treshold_Map[threshold].name10);

    maxBurstLen = 0;
    params = [configTable valueForStringKey:"Max Burst Length"];
    if (params) {
	maxBurstLen = _atoi(params);
	[configTable freeString:params];
    }
    switch (maxBurstLen) {
	case 1: case 2: case 4: case 8: case 16: case 32:
	    break;
	default:
	    maxBurstLen = 0;
	    break;
    }
    if (maxBurstLen)
	IOLog("%s: Max burst length = %d bytes\n", [self name],
	    maxBurstLen * 4);
    else
	IOLog("%s: Max burst length = unlimited\n", [self name]);

    params = [configTable valueForStringKey:"Capture Effect"];
    if (params) {
	if (*params == 'y' || *params == 'Y') {
	    IOLog("%s: Capture-effect enabled\n", [self name]);
	    captureEffect = YES;
	}
	[configTable freeString:params];
    }

    maxQueueSize = TX_RING_MAX;
    params = [configTable valueForStringKey:"TX Queue Size"];
    if (params) {
	maxQueueSize = _atoi(params);
	if (maxQueueSize < 10)
	    maxQueueSize = 10;
	[configTable freeString:params];
    }

    txRingSize = 128;
    rxRingSize = 32;
    txIntThreshold = 32;
    params = [configTable valueForStringKey:"TX Ring Size"];
    if (params) {
	txRingSize = _atoi(params);
	[configTable freeString:params];
    }
    if (txRingSize < 8)
	txRingSize = 8;
    if (txRingSize > page_size / sizeof(dcDescriptor_t))
	txRingSize = page_size / sizeof(dcDescriptor_t);
    if (txRingSize > TX_RING_MAX)
	txRingSize = TX_RING_MAX;

    params = [configTable valueForStringKey:"TX Interrupt Threshold"];
    if (params) {
	txIntThreshold = _atoi(params);
	[configTable freeString:params];
    }
    if (txIntThreshold > txRingSize / 2)
	txIntThreshold = txRingSize / 2;
    if (txIntThreshold == 0)
	txIntThreshold = 1;

    /* the receive ring shares its page with the setup frame */
    params = [configTable valueForStringKey:"RX Ring Size"];
    if (params) {
	rxRingSize = _atoi(params);
	[configTable freeString:params];
    }
    if (rxRingSize < 8)
	rxRingSize = 8;
    if (rxRingSize > (page_size - SETUP_FRAME_SIZE) / sizeof(dcDescriptor_t))
	rxRingSize = (page_size - SETUP_FRAME_SIZE) / sizeof(dcDescriptor_t);
    if (rxRingSize > RX_RING_MAX)
	rxRingSize = RX_RING_MAX;

    IOLog("%s: TX ring = %d(%d), queue = %d, RCV ring = %d\n", [self name],
	txRingSize, txIntThreshold, maxQueueSize, rxRingSize);

    Adapter->MediaType = DC21X4_MEDIA_AUTOSENSE | DC21X4_MEDIA_NWAY;

    dumpSROM = NO;
    params = [configTable valueForStringKey:"Dump SROM"];
    if (params) {
	if (*params == 'y' || *params == 'Y')
	    dumpSROM = YES;
	[configTable freeString:params];
    }

    patchSROM = YES;
    params = [configTable valueForStringKey:"Patch SROM"];
    if (params) {
	if (*params == 'n' || *params == 'N')
	    patchSROM = NO;
	[configTable freeString:params];
    }

    /*
     * A user SROM image: keys SROM0, SROM1, ... each holding
     * space-separated hex words, 64 words in all.
     */
    sprintf(sromKey, "SROM%d", 0);
    sromLine = 0;
    sromCount = 0;
    sromFound = NO;
    params = sromParams = [configTable valueForStringKey:sromKey];
    if (params) {
	userSROMData = (char *)IOMalloc(SROM_SIZE);
	if (userSROMData) {
	    do {
		sromWord = strtoul(params, NULL, 16);
		((unsigned short *)userSROMData)[sromCount] =
		    (sromWord << 8) | (sromWord >> 8);
		params = strchr(params, ' ');
		sromCount++;
		if (params) {
		    params++;
		} else {
		    [configTable freeString:sromParams];
		    sromLine++;
		    sprintf(sromKey, "SROM%d", sromLine);
		    params = sromParams =
			[configTable valueForStringKey:sromKey];
		    if (params == NULL) {
			if (sromCount == SROM_SIZE / 2) {
			    sromFound = YES;
			    IOLog("%s: Found user supplied SROM image\n",
				[self name]);
			}
			break;
		    }
		}
	    } while (sromCount < SROM_SIZE / 2);
	}
    }
    if (sromParams)
	[configTable freeString:sromParams];
    if (!sromFound && userSROMData) {
	IOFree(userSROMData, SROM_SIZE);
	userSROMData = NULL;
    }

    enetAddressOffset = -1;
    if (userSROMData) {
	params = [configTable valueForStringKey:"Address Offset"];
	if (params) {
	    enetAddressOffset = _atoi(params);
	    [configTable freeString:params];
	    if (enetAddressOffset > SROM_SIZE - sizeof(enet_addr_t)
		    || enetAddressOffset < 0)
		enetAddressOffset = 20;		/* DEC standard location */
	}
    }

    connector = 0;
    params = [configTable valueForStringKey:"Network Connection"];
    if (params) {
	for (i = 0; i < CONNECTOR_COUNT; i++) {
	    if (strcmp(params, connectorTable[i].name) == 0) {
		connector = i;
		break;
	    }
	}
	[configTable freeString:params];
    }
    Adapter->MediaType = connectorTable[connector].mediaType;
    IOLog("%s: Selected medium: %s\n", [self name],
	connectorTable[connector].name);

    if ([self _allocateMemory] == NO) {
	[self free];
	return nil;
    }

    Qhead = Qtail = NULL;
    Qcount = 0;

    MGETHDR(KDB_txBuf, M_DONTWAIT, MT_DATA);
    if (KDB_txBuf == NULL) {
	IOLog("%s: Couldn't allocate KDB mbuf\n", [self name]);
	return [self free];
    }

    _inputPacketFunc = [self methodFor:@selector(inputPacket:extra:)];
    _transmitFunc = [self methodFor:@selector(transmit:)];
    _transmitMbufFunc = [self methodFor:@selector(transmitMbuf:)];
    _kdbLock = [self methodFor:@selector(reserveDebuggerLock)];
    _kdbUnlock = [self methodFor:@selector(releaseDebuggerLock)];

    /* One handler per interrupt; dc_intr finds the drivers in irq_table. */
    if (!irq_registered(pmac_int_to_number(irq))) {
	irq_regs[irq_size++] = pmac_int_to_number(irq);
	pmac_register_int(pmac_int_to_number(irq), SPLNET, dc_intr, self);
    }

    /* the 21140 gets an extra reset first */
    if (Adapter->DeviceId == DC21140_CFID && ![self resetAndEnable:NO]) {
	IOLog("Ethernet Device Initialization failed\n");
	return [self free];
    }

    if (![self resetAndEnable:NO]) {
	IOLog("%s: Device initialization failed\n", [self name]);
	return [self free];
    }

    bcopy(Adapter->PermanentAddress, &myAddress, sizeof(myAddress));
    networkInterface = [super attachToNetworkWithAddress:myAddress];
    ifp = [networkInterface getIONetworkIfnet];
    ifp->if_eflags |= IFEF_DVR_REENTRY_OK;

    irq_table[inst].irq = pmac_int_to_number(irq);
    irq_table[inst].driver = self;
    {
	int s = splnet();
	inst++;
	splx(s);
    }

    if ([self resetAndEnable:YES])
	return self;

    IOLog("%s: Device initialization failed\n", [self name]);
    return [self free];
}

- free
{
    struct mbuf	*m;
    int		i;

    if (networkInterface)
	[networkInterface free];

    for (i = 0; i < rxRingSize; i++)
	if (rxMbuf[i])
	    m_freem(rxMbuf[i]);

    for (i = 0; i < txRingSize; i++)
	if (txMbuf[i])
	    m_freem(txMbuf[i]);

    if (KDB_txBuf)
	m_freem(KDB_txBuf);

    /* drain the transmit queue */
    while (1) {
	if (Qcount) {
	    m = Qhead;
	    Qhead = m->m_nextpkt;
	    m->m_nextpkt = NULL;
	    if (--Qcount == 0)
		Qhead = Qtail = NULL;
	} else
	    m = NULL;
	if (m == NULL)
	    break;
	m_freem(m);
    }

    while (kdbQueue.ifq_len) {
	IF_DEQUEUE(&kdbQueue, m);
	if (m)
	    m_freem(m);
    }

    [self _freeDescMemory:&txDescMem];
    [self _freeDescMemory:&rxDescMem];

    if (userSROMData)
	IOFree(userSROMData, SROM_SIZE);

    return [super free];
}

- (BOOL)enablePromiscuousMode
{
    int s = splnet();

    DC21X4_WRITE_CSR(Adapter, CSR6,
	DC21X4_READ_CSR(Adapter, CSR6) | DC_CSR6_PR);
    isPromiscuous = YES;
    splx(s);

    return YES;
}

- (void)disablePromiscuousMode
{
    int s = splnet();

    DC21X4_WRITE_CSR(Adapter, CSR6,
	DC21X4_READ_CSR(Adapter, CSR6) & ~DC_CSR6_PR);
    isPromiscuous = NO;
    splx(s);
}

- (BOOL)enableMulticastMode
{
    multicastEnabled = YES;
    return YES;
}

- (void)disableMulticastMode
{
    int s;

    if (multicastEnabled) {
	_kdbLock(self, @selector(reserveDebuggerLock));
	s = splnet();
	if (![self _setAddressFiltering:NO])
	    IOLog("%s: disable multicast mode failed\n", [self name]);
	splx(s);
	_kdbUnlock(self, @selector(releaseDebuggerLock));
    }
    multicastEnabled = NO;
}

- (void)addMulticastAddress:(enet_addr_t *)addr
{
    int s;

    _kdbLock(self, @selector(reserveDebuggerLock));
    multicastEnabled = YES;
    s = splnet();
    if (![self _setAddressFiltering:NO])
	IOLog("%s: add multicast address failed\n", [self name]);
    splx(s);
    _kdbUnlock(self, @selector(releaseDebuggerLock));
}

- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    int s;

    _kdbLock(self, @selector(reserveDebuggerLock));
    s = splnet();
    if (![self _setAddressFiltering:NO])
	IOLog("%s: remove multicast address failed\n", [self name]);
    splx(s);
    _kdbUnlock(self, @selector(releaseDebuggerLock));
}

/*
 * Private parameters for diagnostic tools.
 */
- (IOReturn)getCharValues:(unsigned char *)parameterArray
	     forParameter:(IOParameterName)parameterName
		    count:(unsigned int *)count
{
    const char		*name;
    unsigned int	maxCount;
    unsigned int	csr8;
    unsigned int	i;
    int			s;
    u_long		csrs[DC21X4_CSR_COUNT];
    dcDebugInfo_t	info;

    if (strcmp(parameterName, "GET_NAME_DEC21x4") == 0) {
	name = [self name];
	maxCount = *count;
	if (maxCount >= strlen(name) + 1) {
	    strcpy((char *)parameterArray, name);
	    parameterArray[maxCount - 1] = '\0';
	    return IO_R_SUCCESS;
	}
    }

    if ((strcmp(parameterName, "GET_STATS") == 0
	    || strcmp(parameterName, "GET_STATS_CLR") == 0)
	    && *count >= sizeof(drvstat)) {
	s = splnet();

	/* CSR8: missed frames <15:0>, FIFO overflows <28:17> */
	csr8 = readCsr(ioBase, DC_CSR(CSR8));
	drvstat.rx_csr8_missed += csr8 & 0xffff;
	if (Adapter->DeviceId == DC21040_CFID
		|| Adapter->DeviceId == DC21041_CFID
		|| (Adapter->DeviceId == DC21140_CFID
		    && (Adapter->RevisionNumber & 0xf0) != 0x20))
	    drvstat.rx_csr8_overflow = 0;
	else
	    drvstat.rx_csr8_overflow += (csr8 >> 17) & 0x1fff;

	drvstat.link_speed = Adapter->LinkSpeed;
	drvstat.link_duplex = Adapter->FullDuplex;
	drvstat.link_status = Adapter->LinkStatus;

	for (i = 0; i < sizeof(drvstat); i++)
	    parameterArray[i] = ((unsigned char *)&drvstat)[i];
	*count = i;

	if (strcmp(parameterName, "GET_STATS_CLR") == 0)
	    bzero(&drvstat, sizeof(drvstat));

	splx(s);
	return IO_R_SUCCESS;
    }

    if (strcmp(parameterName, "GET_CSR") == 0 && *count >= sizeof(csrs)) {
	s = splnet();
	for (i = 0; i < DC21X4_CSR_COUNT; i++)
	    csrs[i] = readCsr(ioBase, DC_CSR(i));
	splx(s);

	for (i = 0; i < sizeof(csrs); i++)
	    parameterArray[i] = ((unsigned char *)csrs)[i];
	*count = i;
	return IO_R_SUCCESS;
    }

    if (strcmp(parameterName, "GET_DEBUGINFO") == 0
	    && *count >= sizeof(info)) {
	s = splnet();
	info.ioBase = ioBase;
	info.irq = irq;
	bcopy(Adapter->PermanentAddress, &info.address, sizeof(info.address));
	info.multicastEnabled = multicastEnabled;
	info.ready = ready;
	info.txPutIndex = txPutIndex;
	info.txDoneIndex = txDoneIndex;
	info.txNumFree = txNumFree;
	info.Qcount = Qcount;
	info.rxDoneIndex = rxDoneIndex;
	splx(s);

	for (i = 0; i < sizeof(info); i++)
	    parameterArray[i] = ((unsigned char *)&info)[i];
	*count = i;
	return IO_R_SUCCESS;
    }

    if (strcmp(parameterName, "GET_SROM") == 0 && *count >= SROM_SIZE) {
	s = splnet();
	_kdbLock(self, @selector(reserveDebuggerLock));
	for (i = 0; i < SROM_SIZE / 2; i++) {
	    ((unsigned short *)parameterArray)[i] =
		sromReadWord(ioBase, i, sromAddressBits);
	}
	_kdbUnlock(self, @selector(releaseDebuggerLock));
	splx(s);
	*count = SROM_SIZE;
	return IO_R_SUCCESS;
    }

    return [super getCharValues:parameterArray
		   forParameter:parameterName
			  count:count];
}

/*
 * Power management.  The only request honored is "off", which stops the
 * chip.
 */
- (IOReturn)getPowerState:(PMPowerState *)state_p
{
    return IO_R_UNSUPPORTED;
}

- (IOReturn)setPowerState:(PMPowerState)state
{
    if (state == PM_OFF) {
	[self resetAndEnable:NO];
	return IO_R_SUCCESS;
    }
    return IO_R_UNSUPPORTED;
}

- (IOReturn)getPowerManagement:(PMPowerManagementState *)state_p
{
    return IO_R_UNSUPPORTED;
}

- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
    return IO_R_UNSUPPORTED;
}

- (void)mbufsPlease
{
}

@end
