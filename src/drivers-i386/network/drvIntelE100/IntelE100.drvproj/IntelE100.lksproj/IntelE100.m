/*
 * IntelE100.m - Intel 8255x (e100) 10/100 ethernet driver for RhapsodiOS
 * i386.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * An IOEthernet subclass. The kernel matches "Auto Detect IDs" in the
 * config tables against the PCI bus, calls +probe:, and the instance
 * attaches to the network stack as enN.
 *
 * The specification is Intel's 8255x Open Source Software Developer Manual
 * ("SDM"). FreeBSD's if_fxp supplied what the SDM leaves out - the ICH
 * device IDs, the EEPROM map and the errata - and each such choice is
 * cited where it is made. NOTICE records what was and was not consulted.
 *
 * How the hardware is driven:
 *
 *   - CSRs through the I/O BAR; SCB command and status a byte at a time.
 *   - Linear addressing (CU and RU base 0): every pointer is physical.
 *   - Configure, individual-address and multicast setup run polled from
 *     one command block while the CU is idle, inside -resetAndEnable:. A
 *     change to the receive filter re-runs -resetAndEnable: rather than
 *     slipping a command into the live transmit ring, as FreeBSD does.
 *   - Transmit: 16 flexible TxCBs in a static circle, each with one TBD
 *     pointing at its own inline data (see -_queueFrame:). The CU is
 *     started once on a NOP with S set and never goes idle again; each
 *     frame sets S on its own TxCB, clears it on the previous one and
 *     issues CU Resume (SDM 8.2).
 *   - Receive: 32 simplified RFDs in a circle with EL on the tail only. EL
 *     moves forward as RFDs are recycled, and RNR restarts the RU.
 *
 * Strict C89 + NeXT Objective-C (cc 2.7.2.1), kernel context. There is no
 * locking: the kernel is not preemptive, so -transmit:, the interrupt
 * handler and the watchdog never run at the same time - the guarantee
 * Pro1000 relies on too. Stores to DMA memory are ordered before the SCB
 * write that hands them to the chip because every SCB access is a call
 * into E100Hw.c, which the compiler cannot see through, and the i386
 * keeps stores in order.
 */

#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IONetwork.h>
#import <driverkit/IONetbufQueue.h>
#import <net/etherdefs.h>
#import <net/netbuf.h>

#import "E100Regs.h"
#import "E100Logic.h"
#import "E100Hw.h"
#import "E100Port.h"

#define E100_VENDOR     0x8086
#define PAGE_BYTES      4096

#define NTX             16      /* transmit slots                        */
#define NRX             32      /* receive frame descriptors             */
#define SLOT_BYTES      1544    /* one TxCB and its TBD, or one RFD      */
#define TX_TBD_OFFSET   1536    /* the TBD, after the 1530-byte TxCB     */
#define TX_CB_SF        0x0008  /* TxCB command: flexible mode           */
#define TX_TBD_EL       0x00010000UL    /* TBD dword 1: last TBD         */
#define CB_BYTES        256     /* configure, IA or multicast setup      */
#define STATS_BYTES     (E100_STATS_DWORDS * 4)

#define TICK_MS         2000    /* watchdog period                       */
#define STATS_EVERY     5       /* ticks between statistics dumps        */
#define TX_STALL_TICKS  2       /* no transmit progress for 4 s          */
#define RX_IDLE_TICKS   8       /* 16 s: if_fxp resets after 15 s idle   */
#define TX_QUEUE_MAX    32
#define CB_WAIT_LOOPS   25000   /* x 2 us = 50 ms for a polled command   */
#define LOUD_RESETS     3       /* transmit resets before the log shouts */

/* True at 1, 10, 100, ... so a repeating condition logs on a log scale. */
static BOOL
logMilestone(unsigned long n)
{
    unsigned long m;

    for (m = 1UL; m != 0UL && m <= n; m *= 10UL) {
        if (m == n)
            return YES;
    }
    return NO;
}

static void
zeroBytes(vm_address_t p, int n)
{
    unsigned char *b = (unsigned char *)p;

    while (n-- > 0)
        *b++ = 0;
}

static BOOL
sameAddress(enet_addr_t *a, enet_addr_t *b)
{
    int i;

    for (i = 0; i < 6; i++) {
        if (a->ether_addr_octet[i] != b->ether_addr_octet[i])
            return NO;
    }
    return YES;
}

/*
 * DMA memory the chip can reach: physically contiguous, with a known
 * physical address. IOMalloc promises neither, so take twice the size and
 * use whichever half lies inside one page - for any size up to half a
 * page, one of them does. Pro1000 uses the same idiom (NeXT's own, from
 * AMDPCSCSIDriver). Returns the usable address, or 0; the caller frees
 * *allocOut with freeDmaBlock.
 */
static vm_address_t
allocDmaBlock(int size, vm_address_t *allocOut, unsigned long *physOut)
{
    vm_address_t    alloc, use;
    unsigned int    phys, physEnd;

    *allocOut = 0;
    *physOut = 0;
    alloc = (vm_address_t)IOMalloc(size * 2);
    if (alloc == 0) {
        IOLog("IntelE100: IOMalloc(%d) failed\n", size * 2);
        return 0;
    }
    *allocOut = alloc;

    use = alloc;
    if ((use & ~(PAGE_BYTES - 1)) != ((use + size - 1) & ~(PAGE_BYTES - 1)))
        use = alloc + size;

    if ((use & 3) != 0
        || IOPhysicalFromVirtual(IOVmTaskSelf(), use, &phys) != IO_R_SUCCESS
        || IOPhysicalFromVirtual(IOVmTaskSelf(), use + size - 1, &physEnd)
           != IO_R_SUCCESS
        || physEnd != phys + size - 1) {
        IOLog("IntelE100: no aligned, physically contiguous %d bytes\n", size);
        return 0;
    }
    zeroBytes(use, size);
    *physOut = (unsigned long)phys;
    return use;
}

static void
freeDmaBlock(vm_address_t *alloc, int size)
{
    if (*alloc != 0) {
        IOFree((void *)*alloc, size * 2);
        *alloc = 0;
    }
}

@interface IntelE100 : IOEthernet
{
    unsigned short      ioBase;
    const E100Chip     *chip;
    int                 revision;       /* see e100EffectiveRevision   */
    unsigned int        quirks;
    int                 irqCount;
    enet_addr_t         myAddress;
    IONetwork          *network;
    id                  transmitQueue;
    BOOL                irqSeen;

    int                 phyAddr;        /* -1: no MII                  */
    unsigned short      phyId1, phyId2;
    BOOL                linkUp;

    vm_address_t        txAlloc[NTX], txSlot[NTX];
    unsigned long       txPhys[NTX];
    int                 txHead;         /* next slot to fill           */
    int                 txTail;         /* oldest slot not completed   */
    int                 txCount;        /* frames from txTail to txHead */
    int                 txLast;         /* the slot holding S          */
    unsigned int        txThreshold;

    vm_address_t        rxAlloc[NRX], rxSlot[NRX];
    unsigned long       rxPhys[NRX];
    int                 rxHead;         /* next RFD to look at         */
    int                 rxTail;         /* the RFD holding EL          */

    vm_address_t        cbAlloc, cbBlock;
    unsigned long       cbPhys;
    vm_address_t        statsAlloc, statsBlock;
    unsigned long       statsPhys;
    BOOL                dumpPending;

    unsigned int        ticks;
    int                 txStallTicks;
    int                 rxIdleTicks;

    unsigned long       txDropped, txResets, rxBadFrames, rxNoNetbufs;
    unsigned long       rxRestarts, rxLockupResets, scbTimeouts, statsMissed;

    enet_addr_t         mcast[E100_MAX_MCAST];
    int                 mcastCount;
    int                 mcastExtra;     /* addresses beyond the list   */
    BOOL                mcastMode;
    BOOL                promiscMode;
}
+ (BOOL)probe:(IODeviceDescription *)devDesc;
- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- (void)_findPhy:(unsigned short)phyWord;
- (BOOL)_allocateDma;
- (BOOL)_initChip;
- (BOOL)_runCommand:(unsigned short)command name:(const char *)name;
- (BOOL)_startTransmitRing;
- (BOOL)_startReceiveRing;
- (BOOL)_queueFrame:(netbuf_t)pkt;
- (void)_startTransmit;
- (void)_reapTransmit;
- (void)_drainTransmitQueue;
- (void)_flushTransmitQueue;
- (void)_serviceReceive:(BOOL)rnr;
- (void)_checkLink;
- (void)_harvestStatistics;
- (BOOL)_allMulticast;
- (void)_filtersChanged;
@end

@implementation IntelE100

+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    IntelE100 *dev = [self alloc];

    if (dev == nil)
        return NO;
    return [dev initFromDeviceDescription:devDesc] != nil;
}

- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IOPCIConfigSpace    config;
    unsigned long       command;
    unsigned short      ee[E100_EEPROM_WORDS_KEPT];
    unsigned short      sum, word;
    unsigned char       mac[6];
    int                 eeBits, words, i;

    if ([super initFromDeviceDescription:devDesc] == nil)
        return nil;

    if ([IODirectDevice getPCIConfigSpace:&config
                    withDeviceDescription:devDesc] != IO_R_SUCCESS) {
        IOLog("IntelE100: cannot read PCI configuration space\n");
        [self free];
        return nil;
    }
    if (config.VendorID != E100_VENDOR) {
        IOLog("IntelE100: vendor %04x is not Intel\n",
              (unsigned int)config.VendorID);
        [self free];
        return nil;
    }
    chip = e100ChipLookup(config.DeviceID, (unsigned char)config.RevisionID);
    if (chip == 0) {
        IOLog("IntelE100: device %04x is not an 8255x this driver knows\n",
              (unsigned int)config.DeviceID);
        [self free];
        return nil;
    }

    /*
     * The CSRs are decoded through the I/O BAR as well as the memory BAR,
     * and port I/O needs no mapping. Scan for it rather than assume BAR1.
     */
    ioBase = 0;
    for (i = 0; i < 6; i++) {
        unsigned long bar = config.BaseAddress[i];

        if ((bar & 1UL) && (bar & 0xFFFFFFFCUL) != 0UL
            && (bar & 0xFFFFFFFCUL) <= 0xFFFFUL) {
            ioBase = (unsigned short)(bar & 0xFFFCUL);
            break;
        }
    }
    if (ioBase == 0) {
        IOLog("IntelE100: %s has no I/O BAR assigned\n", chip->name);
        [self free];
        return nil;
    }

    /* I/O decoding and bus mastering. The status half of the dword goes
     * back as zero, which leaves its write-one-to-clear bits alone. */
    if ([IODirectDevice getPCIConfigData:&command atRegister:0x04
                   withDeviceDescription:devDesc] == IO_R_SUCCESS
        && (command & 0x0005UL) != 0x0005UL) {
        [IODirectDevice setPCIConfigData:((command & 0xFFFFUL) | 0x0005UL)
                              atRegister:0x04 withDeviceDescription:devDesc];
        IOLog("IntelE100: turned on I/O decoding and bus mastering"
              " (command was %04x)\n", (unsigned int)(command & 0xFFFFUL));
    }

    /* A warm boot leaves the chip as the last driver left it (SDM 8.1.1).
     * Both PORT commands clear the SCB M bit, so mask again at once. */
    e100PortCommand(ioBase, E100_PORT_SELECTIVE_RESET);
    e100PortCommand(ioBase, E100_PORT_SOFTWARE_RESET);
    E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);

    eeBits = e100EepromAddressBits(ioBase);
    if (eeBits < 6 || eeBits > 8) {
        IOLog("IntelE100: EEPROM did not answer (address width %d)\n", eeBits);
        [self free];
        return nil;
    }
    words = 1 << eeBits;
    sum = 0;
    for (i = 0; i < words; i++) {
        word = e100EepromRead(ioBase, eeBits, i);
        sum = (unsigned short)(sum + word);
        if (i < E100_EEPROM_WORDS_KEPT)
            ee[i] = word;
    }
    e100MacFromEeprom(ee, mac);
    if (!e100MacValid(mac)) {
        IOLog("IntelE100: EEPROM holds %02x:%02x:%02x:%02x:%02x:%02x,"
              " which is not a station address\n",
              mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        [self free];
        return nil;
    }
    for (i = 0; i < 6; i++)
        myAddress.ether_addr_octet[i] = mac[i];

    revision = e100EffectiveRevision(chip, (unsigned char)config.RevisionID, ee);
    quirks = e100Quirks(chip, revision, ee);
    irqCount = [devDesc numInterrupts];

    /* "0 irq" is the signature of a missing "IRQ Levels" key in the
     * instance table (drvIntel1000's README-Instance0.md). */
    IOLog("IntelE100: %s [8086:%04x rev %02x] %s generation, I/O 0x%04x,"
          " config IRQ %d, %d irq\n",
          chip->name, (unsigned int)config.DeviceID,
          (unsigned int)config.RevisionID, e100GenerationName(revision),
          (unsigned int)ioBase, (int)config.InterruptLine, irqCount);
    IOLog("IntelE100: MAC %02x:%02x:%02x:%02x:%02x:%02x, EEPROM %d words,"
          " checksum %s\n",
          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], words,
          (sum == E100_EEPROM_SUM) ? "OK" : "BAD - continuing");
    if (quirks & E100_Q_RXBUG)
        IOLog("IntelE100: EEPROM word 3 does not mark the receive lockup"
              " fixed - watching for it\n");
    if (quirks & E100_Q_CU_RESUME)
        IOLog("IntelE100: EEPROM enables Dynamic Standby (82801BA erratum 30)"
              " - a CU NOP precedes every resume; the EEPROM is left alone\n");
    if (revision >= E100_REV_82550)
        IOLog("IntelE100: %s runs in simplified mode here, which no reference"
              " driver exercises on this part\n", chip->name);

    [self _findPhy:ee[E100_EEPROM_PHY]];

    if (![self _allocateDma]) {
        [self free];
        return nil;
    }
    txThreshold = E100_TX_THRESHOLD_START;
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:TX_QUEUE_MAX];
    network = [super attachToNetworkWithAddress:myAddress];
    return self;
}

/*
 * The MII address from EEPROM word 6 first (SDM 7.1), then every other
 * address, taking the first whose PHYID1 is neither 0 nor all ones.
 */
- (void)_findPhy:(unsigned short)phyWord
{
    int want = phyWord & E100_PHY_ADDR_MASK;
    int i, addr, id1;

    phyAddr = -1;
    if (quirks & E100_Q_SERIAL) {
        IOLog("IntelE100: 82503 serial interface - no MII PHY\n");
        return;
    }
    for (i = -1; i < 32; i++) {
        addr = (i < 0) ? want : i;
        if (i == want)
            continue;
        id1 = e100MdiRead(ioBase, addr, MII_PHYID1);
        if (id1 > 0 && id1 != 0xFFFF) {
            phyAddr = addr;
            phyId1 = (unsigned short)id1;
            phyId2 = (unsigned short)(e100MdiRead(ioBase, addr, MII_PHYID2)
                                      & 0xFFFF);
            IOLog("IntelE100: PHY at MII address %d%s, ID %04x:%04x\n",
                  addr, (i < 0) ? "" : " (found by scanning; the EEPROM"
                  " names another)", (unsigned int)phyId1,
                  (unsigned int)phyId2);
            /* Autonegotiate once, here. Restarting it on every
             * -resetAndEnable: would drop the link at each filter change. */
            (void)e100MdiWrite(ioBase, addr, MII_BMCR,
                               BMCR_AUTONEG | BMCR_RESTART_AUTONEG);
            return;
        }
    }
    IOLog("IntelE100: no MII PHY answered - link will be reported as up\n");
}

- (BOOL)_allocateDma
{
    int i;

    for (i = 0; i < NTX; i++) {
        txSlot[i] = allocDmaBlock(SLOT_BYTES, &txAlloc[i], &txPhys[i]);
        if (txSlot[i] == 0)
            return NO;
    }
    for (i = 0; i < NRX; i++) {
        rxSlot[i] = allocDmaBlock(SLOT_BYTES, &rxAlloc[i], &rxPhys[i]);
        if (rxSlot[i] == 0)
            return NO;
    }
    cbBlock = allocDmaBlock(CB_BYTES, &cbAlloc, &cbPhys);
    statsBlock = allocDmaBlock(STATS_BYTES, &statsAlloc, &statsPhys);
    return (cbBlock != 0 && statsBlock != 0) ? YES : NO;
}

- free
{
    int i;

    if (ioBase != 0) {
        /* Stop every DMA engine before the memory it targets goes away. */
        e100PortCommand(ioBase, E100_PORT_SELECTIVE_RESET);
        E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);
    }
    if (transmitQueue != nil) {
        [self _flushTransmitQueue];
        [transmitQueue free];
        transmitQueue = nil;
    }
    for (i = 0; i < NTX; i++)
        freeDmaBlock(&txAlloc[i], SLOT_BYTES);
    for (i = 0; i < NRX; i++)
        freeDmaBlock(&rxAlloc[i], SLOT_BYTES);
    freeDmaBlock(&cbAlloc, CB_BYTES);
    freeDmaBlock(&statsAlloc, STATS_BYTES);
    return [super free];
}

/*
 * Called by the network stack, so it must not sleep: every wait below is a
 * bounded IODelay loop (Pro1000 hung the machine with an IOSleep here).
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    [self disableAllInterrupts];
    [self clearTimeout];
    [self setRunning:NO];

    /* Selective reset stops the CU and RU; the software reset returns the
     * rest to power-on state (the pair FreeBSD issues). Both clear the
     * SCB M bit, so mask again straight away. */
    e100PortCommand(ioBase, E100_PORT_SELECTIVE_RESET);
    e100PortCommand(ioBase, E100_PORT_SOFTWARE_RESET);
    E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);

    if (!enable) {
        [self _flushTransmitQueue];
        return YES;
    }
    if (![self _initChip]) {
        IOLog("IntelE100: %s did not come up after reset\n", chip->name);
        return NO;
    }

    /* Starting the transmit ring raised CNA; nothing from before the reset
     * can be pending, so acknowledge everything. */
    E100_OUTB(ioBase + E100_SCB_STATACK, 0xFF);

    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
        IOLog("IntelE100: enableAllInterrupts failed\n");
        return NO;
    }
    [self setRunning:YES];
    [self setRelativeTimeout:TICK_MS];

    IOLog("IntelE100: %s enabled, %d irq, tx threshold %u bytes,"
          " %d multicast%s%s\n", chip->name, irqCount, txThreshold * 8,
          mcastCount, promiscMode ? ", promiscuous" : "",
          [self _allMulticast] ? ", all multicast" : "");
    [self _drainTransmitQueue];
    return YES;
}

- (BOOL)_initChip
{
    E100ConfigCB   *config = (E100ConfigCB *)cbBlock;
    E100IaCB       *ia = (E100IaCB *)cbBlock;
    unsigned char   list[E100_MAX_MCAST * 6];
    int             i, j;

    if (!e100ScbCommandPtr(ioBase, E100_CUC_LOAD_BASE, 0UL)
        || !e100ScbCommandPtr(ioBase, E100_RUC_LOAD_BASE, 0UL)) {
        IOLog("IntelE100: SCB did not accept the base address loads\n");
        return NO;
    }

    zeroBytes(statsBlock, STATS_BYTES);
    dumpPending = NO;
    if (!e100ScbCommandPtr(ioBase, E100_CUC_DUMP_ADDR, statsPhys)) {
        IOLog("IntelE100: SCB did not accept the statistics address\n");
        return NO;
    }

    e100BuildConfig(config->bytes, revision, quirks, promiscMode,
                    [self _allMulticast]);
    if (![self _runCommand:E100_CB_CONFIGURE name:"configure"])
        return NO;

    for (i = 0; i < 6; i++)
        ia->addr[i] = myAddress.ether_addr_octet[i];
    if (![self _runCommand:E100_CB_IAS name:"individual address setup"])
        return NO;

    for (i = 0; i < mcastCount; i++) {
        for (j = 0; j < 6; j++)
            list[i * 6 + j] = mcast[i].ether_addr_octet[j];
    }
    e100FillMcast((E100McastCB *)cbBlock, list, mcastCount);
    if (![self _runCommand:E100_CB_MCAS name:"multicast setup"])
        return NO;

    if (![self _startTransmitRing] || ![self _startReceiveRing])
        return NO;

    txStallTicks = 0;
    rxIdleTicks = 0;
    return YES;
}

/* One polled action command, with the CU idle (SDM 6.4.2). */
- (BOOL)_runCommand:(unsigned short)command name:(const char *)name
{
    E100CBHeader *hdr = (E100CBHeader *)cbBlock;

    if (!e100WaitCuIdle(ioBase)) {
        IOLog("IntelE100: CU not idle before %s (SCB status 0x%02x)\n", name,
              (unsigned int)E100_INB(ioBase + E100_SCB_STATUS));
        return NO;
    }
    hdr->status = 0;
    hdr->command = (unsigned short)(command | E100_CB_EL);
    hdr->link = E100_NO_LINK;
    if (!e100ScbCommandPtr(ioBase, E100_CUC_START, cbPhys)) {
        IOLog("IntelE100: SCB did not accept CU Start for %s\n", name);
        return NO;
    }
    if (!e100WaitCB(&hdr->status, CB_WAIT_LOOPS)) {
        IOLog("IntelE100: %s did not complete (CB status 0x%04x)\n", name,
              (unsigned int)hdr->status);
        return NO;
    }
    if (!(hdr->status & E100_CB_OK)) {
        IOLog("IntelE100: %s failed (CB status 0x%04x)\n", name,
              (unsigned int)hdr->status);
        return NO;
    }
    return YES;
}

- (BOOL)_startTransmitRing
{
    E100TxCB   *first;
    int         i;

    for (i = 0; i < NTX; i++) {
        E100TxCB *cb = (E100TxCB *)txSlot[i];

        cb->hdr.status = E100_CB_C | E100_CB_OK;
        cb->hdr.command = E100_CB_NOP;
        cb->hdr.link = txPhys[(i + 1) % NTX];
    }

    /* Park the CU on a NOP with S set. From here on it only ever
     * suspends, and every frame is a CU Resume (FreeBSD's fxp_init_body
     * does the same). */
    first = (E100TxCB *)txSlot[0];
    first->hdr.status = 0;
    first->hdr.command = E100_CB_NOP | E100_CB_S;
    txLast = 0;
    txHead = 1;
    txTail = 1;
    txCount = 0;

    if (!e100WaitCuIdle(ioBase)
        || !e100ScbCommandPtr(ioBase, E100_CUC_START, txPhys[0])
        || !e100WaitCB(&first->hdr.status, CB_WAIT_LOOPS)) {
        IOLog("IntelE100: transmit ring did not start (CB status 0x%04x)\n",
              (unsigned int)first->hdr.status);
        return NO;
    }
    return YES;
}

- (BOOL)_startReceiveRing
{
    int i;

    for (i = 0; i < NRX; i++) {
        E100Rfd *rfd = (E100Rfd *)rxSlot[i];

        rfd->status = 0;
        rfd->command = (i == NRX - 1) ? E100_RFD_EL : 0;
        rfd->link = rxPhys[(i + 1) % NRX];
        rfd->rbdPointer = E100_NO_LINK;
        rfd->actualCount = 0;
        rfd->size = E100_RFD_BUF;
    }
    rxHead = 0;
    rxTail = NRX - 1;
    if (!e100ScbCommandPtr(ioBase, E100_RUC_START, rxPhys[0])) {
        IOLog("IntelE100: SCB did not accept RU Start\n");
        return NO;
    }
    return YES;
}

- (IOReturn)enableAllInterrupts
{
    E100_OUTB(ioBase + E100_SCB_INTR, 0);
    return [super enableAllInterrupts];
}

- (void)disableAllInterrupts
{
    if (ioBase != 0)
        E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);
    [super disableAllInterrupts];
}

- (void)interruptOccurred
{
    unsigned char   stat;
    int             pass;

    for (pass = 0; pass < 16; pass++) {
        stat = E100_INB(ioBase + E100_SCB_STATACK);
        if (stat == 0x00 || stat == 0xFF)
            break;              /* not ours (shared line), or card gone */
        E100_OUTB(ioBase + E100_SCB_STATACK, stat);

        if (!irqSeen) {
            irqSeen = YES;
            IOLog("IntelE100: interrupts flowing, first STAT/ACK 0x%02x\n",
                  (unsigned int)stat);
        }
        if (stat & (E100_STAT_FR | E100_STAT_RNR))
            [self _serviceReceive:(stat & E100_STAT_RNR) ? YES : NO];
        if (stat & (E100_STAT_CX | E100_STAT_CNA)) {
            [self _reapTransmit];
            [self _drainTransmitQueue];
        }
    }

    /* Re-enable at the framework level as well as in the chip: Pro1000
     * measured that the IRQ stays stranded without the disable/enable
     * pair. */
    if ([self isRunning]) {
        [self disableAllInterrupts];
        [self enableAllInterrupts];
    }
}

- (void)transmit:(netbuf_t)pkt
{
    if (![self isRunning]) {
        nb_free(pkt);
        return;
    }
    [self _reapTransmit];

    if ([transmitQueue count] > 0 || txCount >= NTX - 1) {
        /* IONetbufQueue frees a netbuf "without notice" once it is full
         * (its header says so), so count it here. */
        if ([transmitQueue count] >= [transmitQueue maxCount]) {
            txDropped++;
            if (network != nil)
                [network incrementOutputErrors];
            if (logMilestone(txDropped))
                IOLog("IntelE100: transmit queue full, %u frames dropped\n",
                      (unsigned int)txDropped);
        }
        [transmitQueue enqueue:pkt];
        [self _drainTransmitQueue];
        return;
    }
    if ([self _queueFrame:pkt])
        [self _startTransmit];
}

- (BOOL)_queueFrame:(netbuf_t)pkt
{
    E100TxCB       *cb = (E100TxCB *)txSlot[txHead];
    E100TxCB       *prev = (E100TxCB *)txSlot[txLast];
    unsigned long  *tbd = (unsigned long *)(txSlot[txHead] + TX_TBD_OFFSET);
    unsigned int    length = nb_size(pkt);

    if (length > E100_MAX_FRAME) {
        txDropped++;
        if (network != nil)
            [network incrementOutputErrors];
        nb_free(pkt);
        return NO;
    }
    [self performLoopback:pkt];
    IOCopyMemory(nb_map(pkt), (void *)cb->data, length, 1);
    nb_free(pkt);

    /* Flexible mode with one TBD pointing back at the inline data, as
     * FreeBSD's fxp_encap transmits. The QEMU build the tests run on sends
     * simplified-mode TxCBs as zero-length frames, while flexible mode
     * works on it, upstream QEMU and every 8255x (SDM 6.4.2.5). */
    tbd[0] = txPhys[txHead] + (unsigned long)(cb->data - (unsigned char *)cb);
    tbd[1] = (unsigned long)length | TX_TBD_EL;
    cb->hdr.status = 0;
    cb->tbdArray = txPhys[txHead] + TX_TBD_OFFSET;
    cb->byteCount = 0;
    cb->threshold = (unsigned char)txThreshold;
    cb->tbdNumber = 1;
    cb->hdr.command = E100_CB_XMIT | TX_CB_SF | E100_CB_S;

    /* S on the new CB first, then off the previous one (SDM 8.2), so the
     * CU can never run past the end of what is ready. */
    prev->hdr.command = (unsigned short)(prev->hdr.command & ~E100_CB_S);

    txLast = txHead;
    txHead = (txHead + 1) % NTX;
    txCount++;
    if (network != nil)
        [network incrementOutputPackets];
    return YES;
}

- (void)_startTransmit
{
    if (!e100CuResume(ioBase, (quirks & E100_Q_CU_RESUME) != 0)) {
        scbTimeouts++;
        if (logMilestone(scbTimeouts))
            IOLog("IntelE100: SCB did not accept CU Resume (%u times) - the"
                  " watchdog will reset\n", (unsigned int)scbTimeouts);
    }
}

- (void)_reapTransmit
{
    while (txCount > 0
           && (((E100TxCB *)txSlot[txTail])->hdr.status & E100_CB_C)) {
        txTail = (txTail + 1) % NTX;
        txCount--;
        txStallTicks = 0;
    }
}

- (void)_drainTransmitQueue
{
    netbuf_t    pkt;
    BOOL        queued = NO;

    if (![self isRunning])
        return;
    while (txCount < NTX - 1 && [transmitQueue count] > 0) {
        pkt = [transmitQueue dequeue];
        if (pkt != NULL && [self _queueFrame:pkt])
            queued = YES;
    }
    if (queued)
        [self _startTransmit];
}

- (void)_flushTransmitQueue
{
    while (transmitQueue != nil && [transmitQueue count] > 0)
        nb_free([transmitQueue dequeue]);
}

- (void)_serviceReceive:(BOOL)rnr
{
    int budget = NRX;

    while (budget-- > 0) {
        E100Rfd        *rfd = (E100Rfd *)rxSlot[rxHead];
        unsigned short  status = rfd->status;
        unsigned int    length;
        netbuf_t        pkt = NULL;

        if (!(status & E100_RFD_C))
            break;
        length = rfd->actualCount & E100_RFD_COUNT_MASK;

        /* C with OK is the whole frame in a simplified RFD; EOF is not
         * required, because QEMU writes the count without EOF or F. */
        if (!(status & E100_RFD_OK) || (status & E100_RFD_ERRORS)
            || length < 14 || length > E100_RFD_BUF) {
            rxBadFrames++;
            /* Bad frames only reach an RFD in promiscuous mode (configure
             * byte 6 bit 7), and the statistics dump counts them already. */
            if (network != nil && !promiscMode)
                [network incrementInputErrors];
            if (logMilestone(rxBadFrames))
                IOLog("IntelE100: bad receive, status 0x%04x count 0x%04x,"
                      " %u so far\n", (unsigned int)status,
                      (unsigned int)rfd->actualCount,
                      (unsigned int)rxBadFrames);
        } else {
            pkt = nb_alloc(length);
            if (pkt == NULL) {
                rxNoNetbufs++;
                if (network != nil)
                    [network incrementInputErrors];
                if (logMilestone(rxNoNetbufs))
                    IOLog("IntelE100: no netbuf for a %u byte frame,"
                          " %u dropped so far\n", length,
                          (unsigned int)rxNoNetbufs);
            } else {
                IOCopyMemory((void *)rfd->data, nb_map(pkt), length, 1);
            }
        }

        /* Recycle: this RFD becomes the end of the list, and only then
         * does the old end stop holding the RU back. */
        rfd->status = 0;
        rfd->actualCount = 0;
        rfd->command = E100_RFD_EL;
        ((E100Rfd *)rxSlot[rxTail])->command = 0;
        rxTail = rxHead;
        rxHead = (rxHead + 1) % NRX;
        rxIdleTicks = 0;

        if (pkt != NULL) {
            if ([super isUnwantedMulticastPacket:
                           (ether_header_t *)nb_map(pkt)]) {
                nb_free(pkt);
            } else {
                [network incrementInputPackets];
                [network handleInputPacket:pkt extra:0];
            }
        }
    }

    /* RU Resume is illegal from no resources (SDM Table 53): start again
     * at the first free RFD. */
    if (rnr) {
        rxRestarts++;
        if (!e100ScbCommandPtr(ioBase, E100_RUC_START, rxPhys[rxHead]))
            IOLog("IntelE100: SCB did not accept RU Start\n");
        if (logMilestone(rxRestarts))
            IOLog("IntelE100: receive ring ran out, RU restarted"
                  " (%u so far)\n", (unsigned int)rxRestarts);
    }
}

- (void)timeoutOccurred
{
    if (![self isRunning])
        return;
    ticks++;
    [self _checkLink];
    [self _reapTransmit];
    [self _drainTransmitQueue];

    if (txCount > 0 && linkUp) {
        if (++txStallTicks >= TX_STALL_TICKS) {
            txResets++;
            IOLog("IntelE100: transmit stalled %d s with %d frames"
                  " outstanding - resetting (%u)%s\n",
                  TX_STALL_TICKS * TICK_MS / 1000, txCount,
                  (unsigned int)txResets, (txResets >= LOUD_RESETS)
                  ? " - repeatedly; check the IRQ Levels key" : "");
            [self resetAndEnable:YES];
            return;
        }
    } else {
        txStallTicks = 0;
    }

    /* 82557 receive lockup (FreeBSD if_fxp.c, fxp_tick): nothing received
     * for more than 15 s on a part whose EEPROM does not mark the fix, so
     * reinitialise - if_fxp's comment says multicast, its code does this. */
    if ((quirks & E100_Q_RXBUG) && ++rxIdleTicks >= RX_IDLE_TICKS) {
        rxLockupResets++;
        if (logMilestone(rxLockupResets))
            IOLog("IntelE100: nothing received for %d s on an 82557 without"
                  " the receive fix - reinitialising (%u)\n",
                  RX_IDLE_TICKS * TICK_MS / 1000,
                  (unsigned int)rxLockupResets);
        [self resetAndEnable:YES];
        return;
    }

    if (ticks % STATS_EVERY == 0)
        [self _harvestStatistics];
    [self setRelativeTimeout:TICK_MS];
}

- (void)_checkLink
{
    E100Link    link;
    int         bmsr, intel = -1;

    if (phyAddr < 0) {
        if (!linkUp) {
            linkUp = YES;
            IOLog("IntelE100: no MII PHY - reporting link up\n");
        }
        return;
    }
    (void)e100MdiRead(ioBase, phyAddr, MII_BMSR);   /* link latches low */
    bmsr = e100MdiRead(ioBase, phyAddr, MII_BMSR);
    if (bmsr < 0 || ((bmsr & BMSR_LINK) != 0) == linkUp)
        return;

    if (phyId1 == INTEL_PHYID1)
        intel = e100MdiRead(ioBase, phyAddr, MII_INTEL_STATUS);
    e100DecodeLink(bmsr, e100MdiRead(ioBase, phyAddr, MII_ANAR),
                   e100MdiRead(ioBase, phyAddr, MII_ANLPAR), intel, &link);
    linkUp = link.up ? YES : NO;
    if (!link.up)
        IOLog("IntelE100: link down\n");
    else if (!link.known)
        IOLog("IntelE100: link up, speed and duplex unknown\n");
    else
        IOLog("IntelE100: link up, %s, %s duplex\n",
              link.speed100 ? "100Mb/s" : "10Mb/s",
              link.fullDuplex ? "full" : "half");
}

/*
 * Read the previous Dump and Reset, then issue the next. The dump happens
 * when it is issued, so what is read here covers the interval up to the
 * previous harvest.
 */
- (void)_harvestStatistics
{
    volatile unsigned long *s = (volatile unsigned long *)statsBlock;
    unsigned long           txErrors, rxErrors, collisions;
    unsigned int            threshold;
    int                     i;

    if (dumpPending) {
        if (!e100StatsComplete(s)) {
            statsMissed++;
            if (logMilestone(statsMissed))
                IOLog("IntelE100: statistics dump did not complete"
                      " (%u times)\n", (unsigned int)statsMissed);
        } else {
            collisions = s[E100_STAT_TX_TOTALCOL];
            txErrors = s[E100_STAT_TX_MAXCOL] + s[E100_STAT_TX_LATECOL]
                     + s[E100_STAT_TX_UNDERRUN] + s[E100_STAT_TX_LOSTCRS];
            rxErrors = s[E100_STAT_RX_CRC] + s[E100_STAT_RX_ALIGN]
                     + s[E100_STAT_RX_RESOURCE] + s[E100_STAT_RX_OVERRUN]
                     + s[E100_STAT_RX_SHORT];
            if (network != nil) {
                if (collisions != 0UL)
                    [network incrementCollisionsBy:(unsigned)collisions];
                if (txErrors != 0UL)
                    [network incrementOutputErrorsBy:(unsigned)txErrors];
                if (rxErrors != 0UL)
                    [network incrementInputErrorsBy:(unsigned)rxErrors];
            }
            threshold = e100NextThreshold(txThreshold,
                                          s[E100_STAT_TX_UNDERRUN]);
            if (threshold != txThreshold) {
                IOLog("IntelE100: %u transmit underruns - threshold now"
                      " %u bytes\n", (unsigned int)s[E100_STAT_TX_UNDERRUN],
                      threshold * 8);
                txThreshold = threshold;
            }
            if (s[E100_STAT_TX_GOOD] != 0UL || s[E100_STAT_RX_GOOD] != 0UL
                || txErrors != 0UL || rxErrors != 0UL)
                IOLog("IntelE100: stats: tx %u rx %u, errors tx %u rx %u,"
                      " collisions %u\n",
                      (unsigned int)s[E100_STAT_TX_GOOD],
                      (unsigned int)s[E100_STAT_RX_GOOD],
                      (unsigned int)txErrors, (unsigned int)rxErrors,
                      (unsigned int)collisions);
        }
    }
    for (i = 0; i < E100_STATS_DWORDS; i++)
        s[i] = 0UL;
    dumpPending = e100ScbCommand(ioBase, E100_CUC_DUMP_RESET) ? YES : NO;
}

/* Pro1000's rule: multicast wanted but no list means accept all of it. */
- (BOOL)_allMulticast
{
    return (mcastExtra > 0 || (mcastMode && mcastCount == 0)) ? YES : NO;
}

/* A filter change re-runs the whole bring-up (FreeBSD's approach), which
 * keeps configure and multicast setup out of the live transmit ring. */
- (void)_filtersChanged
{
    if ([self isRunning])
        [self resetAndEnable:YES];
}

- (BOOL)enablePromiscuousMode
{
    promiscMode = YES;
    [self _filtersChanged];
    return YES;
}

- (void)disablePromiscuousMode
{
    promiscMode = NO;
    [self _filtersChanged];
}

- (BOOL)enableMulticastMode
{
    mcastMode = YES;
    [self _filtersChanged];
    return YES;
}

- (void)disableMulticastMode
{
    mcastMode = NO;
    [self _filtersChanged];
}

- (void)addMulticastAddress:(enet_addr_t *)address
{
    int i;

    for (i = 0; i < mcastCount; i++) {
        if (sameAddress(&mcast[i], address))
            return;
    }
    if (mcastCount < E100_MAX_MCAST) {
        mcast[mcastCount++] = *address;
    } else {
        /* No room: accept all multicast until the extras are removed. */
        if (mcastExtra++ == 0)
            IOLog("IntelE100: more than %d multicast addresses - accepting"
                  " all multicast\n", E100_MAX_MCAST);
    }
    [self _filtersChanged];
}

- (void)removeMulticastAddress:(enet_addr_t *)address
{
    int i, j;

    for (i = 0; i < mcastCount; i++) {
        if (sameAddress(&mcast[i], address)) {
            for (j = i; j < mcastCount - 1; j++)
                mcast[j] = mcast[j + 1];
            mcastCount--;
            [self _filtersChanged];
            return;
        }
    }
    /* Not in the list, so it was one of the extras. */
    if (mcastExtra > 0) {
        mcastExtra--;
        [self _filtersChanged];
    }
}

@end
