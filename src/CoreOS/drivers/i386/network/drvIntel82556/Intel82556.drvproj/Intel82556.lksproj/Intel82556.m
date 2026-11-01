/* Intel EtherExpress PRO/100 shared engine.
 * Reconstructed from Intel82556NetworkDriver_reloc (i386).
 * Reference addresses identify the reviewed functions; see reconstruction/.
 */
#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IOEthernetPrivate.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/IOConfigTable.h>
#import <mach/mach.h>
#import <string.h>

/* Byte accesses preserve the reference's hardware bitfield access widths. */
#define BYTE(p,n) (((volatile unsigned char *)(p))[n])
#define WORD(p,n) (*(volatile unsigned short *)((unsigned char *)(p)+(n)))
#define DWORD(p,n) (*(volatile unsigned int *)((unsigned char *)(p)+(n)))
extern unsigned int page_size, page_mask;

/* 0x0000: returns the last virtually contiguous byte with adjacent physical pages. */
unsigned int IOIsPhysicallyContiguous(unsigned int address, int size)
{
    unsigned int end = address + size - 1;
    unsigned int next = (address & ~page_mask) + page_size;
    unsigned int before, after;
    while (next <= end) {
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), next, &after) != 0 ||
            IOPhysicalFromVirtual(IOVmTaskSelf(), next - 1, &before) != 0)
            return 0;
        if (after != before + 1)
            return next - 1;
        next += page_size;
    }
    return end;
}

/* 0x008c */
void *IOMallocPage(int size, void **allocation, unsigned int *allocationSize)
{
    void *memory;
    *allocationSize = 2 * size;
    memory = IOMalloc(2 * size);
    if (!memory) return 0;
    *allocation = memory;
    return (void *)(((unsigned int)memory + page_mask) & ~page_mask);
}

/* 0x00cc: the original name does not imply a cache-policy change. */
void *IOMallocNonCached(int size, void **allocation, int *allocationSize)
{
    *allocationSize = ((size + page_mask) & ~page_mask) + page_size;
    *allocation = IOMalloc(*allocationSize);
    if (!*allocation) return 0;
    return (void *)(((unsigned int)*allocation + page_mask) & ~page_mask);
}

/* 0x0164 */
static void _resetFunc(id driver)
{
    if (![driver resetAndEnable:YES])
        IOLog("%s: Reset attempt unsuccessful\n", [driver name]);
}

@implementation Intel82556

/* 0x011c */
- (netbuf_t)_recAllocateNetbuf
{
    if (bufferPool) return [bufferPool getNetBuffer];
    IOLog("%s: allocateNetbuf called, but buffer pool doesn't exist\n", [self name]);
    return 0;
}

/* 0x01a0 */
- (BOOL)_waitCu:(unsigned int)timeout
{
    unsigned int elapsed;
    for (elapsed = 0; elapsed < 1000 * timeout; elapsed++) {
        if ((BYTE(scb_p, 1) & 7) != 2) return YES;
        IODelay(1);
    }
    IOLog("%s: timeout waiting for command unit to become inactive\n", [self name]);
    return NO;
}

/* 0x0218 */
- (BOOL)_waitScb
{
    int i;
    for (i = 0; i < 65535; i++) {
        if (scb_p->command == 0) return YES;
        IODelay(1);
    }
    IOLog("%s: timeout waiting for scb command to clear\n", [self name]);
    return NO;
}

/* 0x0274 */
- (BOOL)_abortReceiveUnit
{
    int i;
    if ((BYTE(scb_p, 0) & 0xf0) != 0x40) return YES;
    if (![self _waitScb] || ![self _waitCu:100]) return NO;
    scb_p->command = 0;
    BYTE(scb_p, 2) = (BYTE(scb_p, 2) & 0x8f) | 0x40;
    [self sendChannelAttention];
    for (i = 0; i < 2000; i++) {
        IODelay(1000);
        if ((BYTE(scb_p, 0) & 0xf0) == 0) break;
    }
    if (i != 2000) return YES;
    IOLog("%s: abort receive unit timed out\n", [self name]);
    return NO;
}

/* 0x0344 */
- (void)_scheduleReset
{
    netbuf_t packet;
    [self _abortReceiveUnit];
    [self clearTimeout];
    while ((packet = [transmitQueue dequeue]) != 0) nb_free(packet);
    IOScheduleFunc((IOThreadFunc)_resetFunc, self, 1);
}

/* 0x03a4 */
- (BOOL)_initRfdList
{
    int i;
    I556RFD *rfd;
    if (((BYTE(scb_p, 0) >> 4) & 0x0c) != 0) {
        IOLog("%s: _initRfdList called while receive unit ready\n", [self name]);
        [self _abortReceiveUnit];
    }
    for (i = 0; i < 64; i++) {
        if (rfdList_p[i].netbuf) {
            nb_free(rfdList_p[i].netbuf);
            rfdList_p[i].netbuf = 0;
        }
    }
    bzero(rfdList_p, 64 * sizeof(I556RFD));
    for (i = 0; i < 64; i++) {
        rfd = &rfdList_p[i];
        BYTE(rfd, 2) |= 8;
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)rfd, &rfd->physical)) {
            IOLog("%s: Invalid RFD address\n", [self name]);
            return NO;
        }
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)&rfd->rbd, &rfd->rbd.physical)) {
            IOLog("%s: Invalid RBD address\n", [self name]);
            return NO;
        }
    }
    for (i = 0; i < 64; i++) {
        rfd = &rfdList_p[i];
        if (i == 63) {
            BYTE(rfd, 3) |= 0x80;
            rfd->next = rfdList_p;
            rfd->rbd.end = 1;
            rfd->rbd.next = &rfdList_p[0].rbd;
        } else {
            rfd->next = &rfdList_p[i + 1];
            rfd->rbd.next = &rfdList_p[i + 1].rbd;
        }
        rfd->link = rfd->next->physical;
        rfd->rbdAddress = i ? ~0U : rfd->rbd.physical;
        rfd->rbd.link = rfd->rbd.next->physical;
        rfd->rbd.size &= 0xc000;
        rfd->rbd.size |= 1518;
        rfd->netbuf = [self _recAllocateNetbuf];
        if (!rfd->netbuf)
            IOLog("%s: receive buffer allocation failed\n", [self name]);
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)nb_map(rfd->netbuf), (unsigned int *)&rfd->rbd.buffer)) {
            IOLog("%s: Invalid RBD netbuf address\n", [self name]);
            return NO;
        }
    }
    headRfd = rfdList_p;
    tailRfd = &rfdList_p[63];
    return YES;
}

/* 0x0670 */
- (BOOL)_initTcbList
{
    int i, j;
    I556TCB *tcb;
    if (BYTE(scb_p, 1) & 2) {
        IOLog("%s: _initTcbList called while command unit active\n", [self name]);
        [self _waitCu:100];
    }
    for (i = 0; i < 16; i++) {
        if (tcbList_p[i].netbuf) {
            nb_free(tcbList_p[i].netbuf);
            tcbList_p[i].netbuf = 0;
        }
    }
    bzero(tcbList_p, 16 * sizeof(I556TCB));
    for (i = 0; i < 16; i++) {
        tcb = &tcbList_p[i];
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)tcb, &tcb->physical)) {
            IOLog("%s: Invalid TCB address\n", [self name]);
            return NO;
        }
        for (j = 0; j < 2; j++) {
            if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)&tcb->tbd[j], &tcb->tbd[j].physical)) {
                IOLog("%s: Invalid TBD address\n", [self name]);
                return NO;
            }
        }
        tcb->next = i == 15 ? 0 : &tcbList_p[i + 1];
    }
    headFreeTcb = tcbList_p;
    pendingTcbTail = 0;
    pendingTcbHead = 0;
    activeTcbHead = 0;
    return YES;
}

/* 0x0820: allocation arena uses the native Rhapsody page size. */
- (void *)_memAlloc:(unsigned int)size
{
    void *result;
    if (sharedMemAvail < size) IOPanic("Intel82556: shared memory exhausted\n");
    result = sharedMemAllocPtr;
    sharedMemAllocPtr = (char *)sharedMemAllocPtr + size;
    if ((unsigned int)sharedMemAllocPtr & 3)
        sharedMemAllocPtr = (void *)(((unsigned int)sharedMemAllocPtr + 3) & ~3U);
    sharedMemAvail = page_size - ((char *)sharedMemAllocPtr - (char *)sharedMemPtr);
    return result;
}

/* 0x0888 */
- (BOOL)_selfTest
{
    unsigned int physical;
    int i;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)selfTest_p, &physical)) {
        IOLog("%s: Invalid self test area address\n", [self name]);
        return NO;
    }
    DWORD(selfTest_p, 0) = ~0U;
    WORD(selfTest_p, 4) = 0xffff;
    WORD(selfTest_p, 6) = 0;
    [self sendPortCommand:1 with:physical];
    for (i = 0; i < 2000; i++) {
        IODelay(1000);
        if (WORD(selfTest_p, 4) != 0xffff) break;
    }
    if (WORD(selfTest_p, 4) == 0xffff) {
        IOLog("%s: Self test timed out\n", [self name]);
        return NO;
    }
    if (WORD(selfTest_p, 4) == 0) return YES;
    if (BYTE(selfTest_p, 4) & 8) IOLog("%s: Self test reports invalid ROM contents\n", [self name]);
    if (BYTE(selfTest_p, 4) & 4) IOLog("%s: Self test reports internal register failure\n", [self name]);
    if (BYTE(selfTest_p, 4) & 0x10) IOLog("%s: Self test reports bus throttle timer failure\n", [self name]);
    if (BYTE(selfTest_p, 4) & 0x20) IOLog("%s: Self test reports serial subsystem failure\n", [self name]);
    if (BYTE(selfTest_p, 5) & 0x10) IOLog("%s: Self test failed\n", [self name]);
    return NO;
}

/* 0x0a3c */
- (BOOL)_startTransmit
{
    if (![self _waitScb] || ![self _waitCu:100]) {
        IOLog("%s: Cannot start transmit\n", [self name]);
        return NO;
    }
    if (!activeTcbHead || !activeTcbHead->physical) {
        IOLog("%s: Attempt to start command unit with null activeTcbHead virtual or physical address\n", [self name]);
        return NO;
    }
    scb_p->command = 0;
    BYTE(scb_p, 3) = (BYTE(scb_p, 3) & 0xf8) | 1;
    scb_p->commandList = activeTcbHead->physical;
    [self sendChannelAttention];
    return YES;
}

/* 0x0b00 */
- (BOOL)_startReceiveUnit
{
    int i;
    if ((BYTE(scb_p, 0) & 0xf0) == 0x40) {
        IOLog("%s: receive unit is already ready\n", [self name]);
        return YES;
    }
    if (![self _waitScb] || ![self _waitCu:100]) return NO;
    if (!headRfd || !headRfd->physical || !headRfd->rbd.physical) {
        IOLog("%s: attempt to start receive unit with null virtual or physical RFD/RBD address\n", [self name]);
        return NO;
    }
    headRfd->rbdAddress = headRfd->rbd.physical;
    scb_p->receiveFrameArea = headRfd->physical;
    scb_p->command = 0;
    BYTE(scb_p, 2) = (BYTE(scb_p, 2) & 0x8f) | 0x10;
    [self sendChannelAttention];
    for (i = 0; i < 10000; i++) {
        if ((BYTE(scb_p, 0) & 0xf0) == 0x40) break;
        IODelay(1);
    }
    [self acknowledgeInterrupts:scb_p->status];
    IOSleep(50);
    [self clearIrqLatch];
    return (BYTE(scb_p, 0) & 0xf0) == 0x40;
}

/* 0x0c58 */
- (void)_transmitPacket:(netbuf_t)packet
{
    I556TCB *tcb = headFreeTcb;
    I556TBD *tbd;
    unsigned int data, end;
    int length, firstLength;
    headFreeTcb = tcb->next;
    tcb->status = 0;
    tcb->command = 0;
    BYTE(tcb, 2) &= 0xf8;
    BYTE(tcb, 2) |= 4;
    BYTE(tcb, 3) |= 0x20;
    BYTE(tcb, 2) |= 8;
    tcb->link = ~0U;
    tcb->next = 0;
    tcb->threshold = 0xe0;
    tbd = &tcb->tbd[0];
    tcb->tbdAddress = tbd->physical;
    tcb->count = 0;
    tcb->tbdCount = 0;
    tcb->netbuf = packet;
    data = (unsigned int)nb_map(packet);
    length = nb_size(packet);
    end = IOIsPhysicallyContiguous(data, length);
    if (!end) {
        IOLog("%s: IOIsPhysicallyContiguous returned NULL\n", [self name]);
        goto failed;
    }
    firstLength = end - data + 1;
    if (length > firstLength) {
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), data, (unsigned int *)&tbd->buffer)) {
            IOLog("%s: Invalid address for outgoing packet (before piece)\n", [self name]);
            goto failed;
        }
        tbd->reserved = 0;
        tbd->count &= 0x8000;
        tbd->count |= firstLength & 0x7fff;
        BYTE(tbd, 1) &= 0x7f;
        tbd->link = tcb->tbd[1].physical;
        tbd = &tcb->tbd[1];
        length -= firstLength;
        data += firstLength;
    }
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), data, (unsigned int *)&tbd->buffer)) {
        IOLog("%s: Invalid address for outgoing packet\n", [self name]);
        goto failed;
    }
    [self performLoopback:packet];
    tbd->reserved = 0;
    tbd->count &= 0x8000;
    tbd->count |= length & 0x7fff;
    BYTE(tbd, 1) |= 0x80;
    tbd->link = ~0U;
    if (activeTcbHead) {
        if (pendingTcbHead) {
            pendingTcbTail->next = tcb;
            pendingTcbTail->link = tcb->physical;
        } else pendingTcbHead = tcb;
        pendingTcbTail = tcb;
    } else {
        BYTE(tcb, 3) |= 0x80;
        activeTcbHead = tcb;
        if ([self _startTransmit]) [self setRelativeTimeout:500];
        else {
            IOLog("%s: failed to start transmission\n", [self name]);
            [self _scheduleReset];
        }
    }
    return;
failed:
    /* The reference drops this descriptor until the next list reset. */
    nb_free(packet);
    tcb->netbuf = 0;
}

/* 0x0e9c */
- (void)serviceTransmitQueue
{
    netbuf_t packet;
    while (headFreeTcb) {
        packet = [transmitQueue dequeue];
        if (!packet) break;
        [self _transmitPacket:packet];
    }
}

/* 0x0ee8 */
- (BOOL)acknowledgeInterrupts:(unsigned short)status
{
    int i;
    if ([self _waitScb] && (status & 0xf000)) {
        scb_p->command = 0;
        BYTE(scb_p, 3) = ((status >> 8) & 0xf0) | (BYTE(scb_p, 3) & 0x0f);
        [self sendChannelAttention];
        for (i = 0; i < 2000; i++) {
            IODelay(1);
            if (!(BYTE(scb_p, 3) & 0xf0)) break;
        }
        if (!(BYTE(scb_p, 3) & 0xf0)) return YES;
        IOLog("%s: acknowledge scb status 0x%x failed\n", [self name], status);
    }
    return NO;
}

/* 0x0fb8 */
- free
{
    int i;
    if (resetAndEnabled == YES) {
        [self clearTimeout];
        [self disableAllInterrupts];
        [self _waitScb];
        [self _waitCu:1000];
        [self _abortReceiveUnit];
        resetAndEnabled = NO;
    }
    if (networkInterface) [networkInterface free];
    if (transmitQueue) [transmitQueue free];
    if (bufferPool) {
        for (i = 0; i < 64; i++)
            if (rfdList_p[i].netbuf) nb_free(rfdList_p[i].netbuf);
        [bufferPool free];
    }
    IOFree(sharedMem_actualPtr, sharedMem_actualSize);
    return [super free];
}

/* 0x10dc: checked against assembly; Hex-Rays cannot reconstruct its stack. */
- (BOOL)_hwInit
{
    unsigned int physical;
    int i;
    [self clearIrqLatch];
    [self disableAdapterInterrupts];
    [self resetPLXchip];
    IOSleep(150);
    [self getEthernetAddress];
    [self initPLXchip];
    [self sendPortCommand:0 with:0];
    IOSleep(250);
    bzero(scp_p, 12);
    BYTE(scp_p, 2) |= 0x40;
    BYTE(scp_p, 2) &= 0xf9;    BYTE(scp_p, 2) |= 4;
    BYTE(scp_p, 2) |= 0x10;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)iscp_p, (unsigned int *)&scp_p->iscpAddress)) {
        IOLog("%s: Invalid ISCP address\n", [self name]);
        return NO;
    }
    bzero(iscp_p, 8);
    iscp_p->busy = 1;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)scb_p, (unsigned int *)&iscp_p->scbAddress)) {
        IOLog("%s: Invalid SCB address\n", [self name]);
        return NO;
    }
    bzero(scb_p, 44);
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)scp_p, &physical)) {
        IOLog("%s: Invalid SCP address\n", [self name]);
        return NO;
    }
    [self sendPortCommand:2 with:physical];
    IOSleep(150);
    [self sendChannelAttention];
    for (i = 0; i < 2000; i++) {
        IODelay(1000);
        if (!iscp_p->busy) break;
    }
    if (iscp_p->busy) {
        IOLog("%s: 82556 initialization timed out\n", [self name]);
        return NO;
    }
    if (![self acknowledgeInterrupts:scb_p->status]) return NO;
    IOSleep(150);
    [self clearIrqLatch];
    IOSleep(150);
    if (![self setThrottleTimers]) return NO;
    IOSleep(150);
    if (![self config]) return NO;
    IOSleep(500);
    return YES;
}

/* 0x1368 */
- (BOOL)hwInit
{
    void *allocation;
    unsigned int allocationSize;
    I556Dump *dumpArea = IOMallocPage(page_size, &allocation, &allocationSize);
    if (!dumpArea) {
        IOLog("%s: hwInit: IOMallocPage failed\n", [self name]);
        return NO;
    }
    if (autoSpeedDetect == YES) {
        dataRate = 1;
        if (![self _hwInit]) return NO;
        [self lockDBRT];
        IOSleep(500);
        if (![self dump:dumpArea]) return NO;
        if (!(BYTE(dumpArea, 1) & 0x40)) {
            dataRate = 0;
            if (![self _hwInit]) return NO;
            [self lockDBRT];
            IOSleep(500);
            if (![self dump:dumpArea]) return NO;
            if (!(BYTE(dumpArea, 1) & 0x40))
                IOLog("%s: network cable is disconnected, please attach\n", [self name]);
        }
    } else {
        if (![self _hwInit]) return NO;
        [self lockDBRT];
        IOSleep(500);
        if (![self dump:dumpArea]) return NO;
        if (!(BYTE(dumpArea, 1) & 0x40))
            IOLog("%s: network cable is disconnected, please attach\n", [self name]);
        IOSleep(200);
    }
    /* Early failures above retain the original allocation ownership behavior. */
    IOFree(allocation, allocationSize);
    return [self iaSetup] ? YES : NO;
}

/* 0x1538 */
- (netbuf_t)allocateNetbuf
{
    netbuf_t packet = nb_alloc(1518);
    unsigned int data;
    if (packet) {
        data = (unsigned int)nb_map(packet);
        if (data & 3) nb_shrink_top(packet, ((data + 3) & ~3U) - data);
        nb_shrink_bot(packet, nb_size(packet) - 1514);
    }
    return packet;
}

/* 0x158c */
- initFromDeviceDescription:(IODeviceDescription *)description
{
    id table;
    const char *rate;
    if (![super initFromDeviceDescription:description]) return nil;
    autoSpeedDetect = NO;
    dataRate = 0;
    table = [description configTable];
    rate = [table valueForStringKey:"Data Rate"];
    if (rate) {
        if (!strcmp(rate, "Auto") || !strcmp(rate, "AUTO")) autoSpeedDetect = YES;
        else if (!strcmp(rate, "10")) dataRate = 0;
        else if (!strcmp(rate, "100")) dataRate = 1;
        [table freeString:rate];
    }
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:96];
    return self;
}

/* 0x16c0 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    [self clearTimeout];
    if (![self hwInit] || ![self swInit]) return NO;
    if (enable) {
        if ([self enableAllInterrupts] != 0) {
            [self setRunning:NO];
            return NO;
        }
        [self enableAdapterInterrupts];
    }
    [self setRunning:enable];
    resetAndEnabled = YES;
    return YES;
}

/* 0x176c: intentionally empty base hook; implemented by both bus subclasses. */
- (void)clearIrqLatch {}

/* 0x1774 */
- (BOOL)swInit
{
    BOOL result = NO;
    [self reserveDebuggerLock];
    if ([self _initTcbList] && [self _initRfdList])
        result = [self _startReceiveUnit] != NO;
    [self releaseDebuggerLock];
    return result;
}

/* 0x17e8: Rhapsody's page_size is 8192, sufficient for this 7436-byte arena. */
- (BOOL)coldInit
{
    unsigned int actualSize;
    [self clearIrqLatch];
    [self disableAdapterInterrupts];
    sourceAddressInsertion = NO;
    sharedMemSize = page_size;
    sharedMemPtr = IOMallocNonCached(page_size, &sharedMem_actualPtr, (int *)&sharedMem_actualSize);
    if (!sharedMemPtr) {
        IOLog("%s: Can't allocate shared memory page\n", [self name]);
        return NO;
    }
    bzero(sharedMemPtr, sharedMemSize);
    sharedMemAllocPtr = sharedMemPtr;
    sharedMemAvail = sharedMemSize;
    scp_p = [self _memAlloc:12];
    iscp_p = [self _memAlloc:8];
    scb_p = [self _memAlloc:44];
    selfTest_p = [self _memAlloc:24];
    if ((unsigned int)selfTest_p & 15)
        selfTest_p = (I556SelfTest *)(((unsigned int)selfTest_p + 15) & ~15U);
    cbl_p = [self _memAlloc:68];
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)cbl_p, &cbl_paddr)) {
        IOLog("%s: Invalid command block address\n", [self name]);
        return NO;
    }
    tcbList_p = [self _memAlloc:1088];
    KDB_tcb_p = [self _memAlloc:68];
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)KDB_tcb_p, &KDB_tcb_p->physical)) {
        IOLog("%s: Invalid TCB address\n", [self name]);
        return NO;
    }
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)&KDB_tcb_p->tbd[0], &KDB_tcb_p->tbd[0].physical)) {
        IOLog("%s: Invalid TCB->_TBD address\n", [self name]);
        return NO;
    }
    KDB_buf_p = [self _memAlloc:1514];
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)KDB_buf_p, &KDB_buf_paddr)) {
        IOLog("%s: Invalid address\n", [self name]);
        return NO;
    }
    rfdList_p = [self _memAlloc:4608];
    bufferPool = [[Intel82556Buf alloc] initWithRequestedSize:1518 actualSize:&actualSize count:256];
    if ((int)actualSize <= 1517) {
        IOLog("%s: Unable to allocate memory buffers of adequate length\n", [self name]);
        return NO;
    }
    return [self _selfTest] ? YES : NO;
}

/* 0x1ac8 */
- (BOOL)receiveInterruptOccurred:(BOOL)restart
{
    I556RFD *rfd;
    netbuf_t packet, replacement;
    unsigned int length;
    [self reserveDebuggerLock];
    rfd = headRfd;
    while (rfd && (BYTE(rfd, 1) & 0x80)) {
        if (!(BYTE(&rfd->rbd, 1) & 0x80)) {
            IOLog("%s: oversize frame size %d\n", [self name], rfd->rbd.status & 0x3fff);
            [self _scheduleReset];
            return NO;
        }
        headRfd = headRfd->next;
        if (BYTE(rfd, 1) & 0x20) {
            packet = rfd->netbuf;
            length = rfd->rbd.status & 0x3fff;
            [self releaseDebuggerLock];
            if (length > 63 &&
                (promiscuousEnabled == YES || multicastConfigured == NO ||
                 !(BYTE(rfd, 0) & 2) ||
                 ![super isUnwantedMulticastPacket:(ether_header_t *)nb_map(packet)])) {
                replacement = [self _recAllocateNetbuf];
                if (replacement) {
                    nb_shrink_bot(packet, nb_size(packet) + 4 - length);
                    [networkInterface handleInputPacket:packet extra:0];
                    rfd->netbuf = replacement;
                    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)nb_map(replacement), (unsigned int *)&rfd->rbd.buffer))
                        IOPanic("Intel82556: Invalid net buffer address");
                } else {
                    replacement = [super allocateNetbuf];
                    if (replacement) {
                        bcopy(nb_map(packet), nb_map(replacement), length - 4);
                        nb_shrink_bot(replacement, nb_size(replacement) + 4 - length);
                        [networkInterface handleInputPacket:replacement extra:0];
                    }
                }
            }
            [self reserveDebuggerLock];
        } else [networkInterface incrementInputErrors];
        rfd->status = 0;
        rfd->command = 0;
        BYTE(rfd, 2) |= 8;
        BYTE(rfd, 3) |= 0x80;
        rfd->rbdAddress = ~0U;
        rfd->count = 0;
        rfd->size = 0;
        rfd->rbd.status = 0;
        rfd->rbd.size = 1518;
        rfd->rbd.end = 1;
        tailRfd->rbd.end = 0;
        BYTE(tailRfd, 3) &= 0x7f;
        tailRfd = tailRfd->next;
        rfd = headRfd;
    }
    if (restart || (BYTE(scb_p, 0) & 0xf0) != 0x40) {
        [self _abortReceiveUnit];
        [self _initRfdList];
        [self _startReceiveUnit];
    }
    [self releaseDebuggerLock];
    return YES;
}

/* 0x1db0 */
- (BOOL)transmitInterruptOccurred
{
    I556TCB *tcb;
    while (activeTcbHead && (BYTE(activeTcbHead, 1) & 0x80)) {
        tcb = activeTcbHead;
        [self clearTimeout];
        activeTcbHead = activeTcbHead->next;
        if (!activeTcbHead && pendingTcbHead) {
            BYTE(pendingTcbTail, 3) |= 0x80;
            activeTcbHead = pendingTcbHead;
            pendingTcbHead = 0;
            if (![self _startTransmit]) {
                IOLog("%s: start transmit failed\n", [self name]);
                [self _scheduleReset];
                return NO;
            }
            [self setRelativeTimeout:500];
        }
        if (BYTE(tcb, 1) & 0x20) [networkInterface incrementOutputPackets];
        else [networkInterface incrementOutputErrors];
        if (BYTE(tcb, 0) & 15) [networkInterface incrementCollisionsBy:BYTE(tcb, 0) & 15];
        if (BYTE(tcb, 0) & 0x20) [networkInterface incrementCollisionsBy:16];
        if (tcb->netbuf) {
            nb_free(tcb->netbuf);
            tcb->netbuf = 0;
        }
        tcb->next = headFreeTcb;
        headFreeTcb = tcb;
    }
    [self serviceTransmitQueue];
    return YES;
}

/* 0x1f34 */
- (BOOL)setThrottleTimers
{
    int i;
    if (![self _waitScb] || ![self _waitCu:100]) return NO;
    scb_p->command = 0;
    BYTE(scb_p, 3) = (BYTE(scb_p, 3) & 0xf8) | 6;
    scb_p->throttleOn = 2;
    scb_p->throttleOff = 125;
    [self sendChannelAttention];
    for (i = 0; i < 2000; i++) {
        IODelay(1000);
        if (BYTE(scb_p, 0) & 8) break;
    }
    if (BYTE(scb_p, 0) & 8) return YES;
    IOLog("%s: set throttle timers timed out\n", [self name]);
    return NO;
}

/* 0x2010 */
- (BOOL)nop:(BOOL)interrupt
{
    int i;
    BOOL result = YES;
    I556Command *command = cbl_p;
    if (![self _waitScb] || ![self _waitCu:100]) return NO;
    bzero(command, 8);
    BYTE(command, 2) &= 0xf8;
    BYTE(command, 3) |= 0x80;
    BYTE(command, 3) = ((interrupt & 1) << 5) | (BYTE(command, 3) & 0xdf);
    DWORD(command, 4) = ~0U;
    scb_p->commandList = cbl_paddr;
    scb_p->command = 0;
    BYTE(scb_p, 3) = (BYTE(scb_p, 3) & 0xf8) | 1;
    [self sendChannelAttention];
    for (i = 0; i < 2000; i++) {
        IODelay(1000);
        if (BYTE(command, 1) & 0x80) break;
    }
    if (!(BYTE(command, 1) & 0x80)) {
        IOLog("%s: nop command failed\n", [self name]);
        return NO;
    }
    if (interrupt) {
        if (!(BYTE(scb_p, 1) & 0x80)) {
            IOLog("%s: nop interrupt not set status 0x%x command 0x%x\n", [self name], scb_p->status, scb_p->command);
            result = NO;
        }
        if (BYTE(scb_p, 1) & 0xf0) [self acknowledgeInterrupts:scb_p->status];
    }
    return result;
}

/* 0x218c */
- (BOOL)dump:(I556Dump *)area
{
    int i;
    I556Command *command = cbl_p;
    if (![self _waitScb] || ![self _waitCu:100]) return NO;
    bzero(command, 12);
    BYTE(command, 2) &= 0xf8;    BYTE(command, 2) |= 6;
    BYTE(command, 3) |= 0x80;
    DWORD(command, 4) = ~0U;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)area, (unsigned int *)((char *)command + 8))) {
        IOLog("%s: invalid dump area pointer\n", [self name]);
        return NO;
    }
    scb_p->commandList = cbl_paddr;
    scb_p->command = 0;
    BYTE(scb_p, 3) = (BYTE(scb_p, 3) & 0xf8) | 1;
    [self sendChannelAttention];
    for (i = 0; i < 4000; i++) {
        IODelay(1000);
        if (BYTE(command, 1) & 0x80) break;
    }
    if (BYTE(command, 1) & 0x80) return YES;
    IOLog("%s: dump command failed\n", [self name]);
    return NO;
}

/* 0x22ac */
- (BOOL)config
{
    int i;
    I556Command *command = cbl_p;
    if (![self _waitScb] || ![self _waitCu:100]) return NO;
    bzero(command, 28);
    BYTE(command, 2) &= 0xf8;    BYTE(command, 2) |= 2;
    BYTE(command, 3) |= 0x80;
    DWORD(command, 4) = ~0U;
    BYTE(command, 8) &= 0xc0;    BYTE(command, 8) |= 0x14;
    BYTE(command, 9) &= 0xf0;    BYTE(command, 9) |= 8;
    BYTE(command, 9) |= 0xc0;
    BYTE(command, 10) |= 0x20;
    BYTE(command, 11) &= 0xf8;    BYTE(command, 11) |= 6;
    BYTE(command, 11) |= 8;
    BYTE(command, 12) &= 0xfe;    BYTE(command, 12) |= (dataRate & 1);
    BYTE(command, 12) |= 2;
    BYTE(command, 13) |= 0x80;
    BYTE(command, 14) &= 0xf8;    BYTE(command, 14) |= 6;
    BYTE(command, 14) |= 8;
    BYTE(command, 14) &= 0xcf;    BYTE(command, 14) |= 0x20;
    BYTE(command, 16) = 96;
    DWORD(command, 16) &= 0xfff800ffU;
    DWORD(command, 16) |= 0x20000;
    BYTE(command, 18) &= 0x0f;
    BYTE(command, 19) &= 0xfe;    BYTE(command, 19) |= (promiscuousEnabled & 1);
    BYTE(command, 19) |= 8;
    BYTE(command, 19) |= 0x80;
    BYTE(command, 21) = 64;
    BYTE(command, 22) |= 1;
    BYTE(command, 22) |= 2;
    BYTE(command, 22) |= 4;
    BYTE(command, 22) |= 0x10;
    BYTE(command, 22) |= 0x20;
    BYTE(command, 22) |= 0x40;
    BYTE(command, 22) |= 0x80;
    BYTE(command, 24) |= 0x3f;
    BYTE(command, 25) |= 1;
    BYTE(command, 25) &= 0xf9;    BYTE(command, 25) |= 4;
    BYTE(command, 26) = 58;
    BYTE(command, 27) &= 0xfe;
    scb_p->commandList = cbl_paddr;
    scb_p->command = 0;
    BYTE(scb_p, 3) = (BYTE(scb_p, 3) & 0xf8) | 1;
    [self sendChannelAttention];
    for (i = 0; i < 2000; i++) {
        IODelay(1000);
        if (BYTE(command, 1) & 0x80) break;
    }
    if (BYTE(command, 1) & 0x80) return (BYTE(command, 1) & 0x20) != 0;
    IOLog("%s: configure command timed out\n", [self name]);
    return NO;
}

/* 0x2450 */
- (BOOL)iaSetup
{
    int i;
    I556Command *command = cbl_p;
    if (![self _waitScb] || ![self _waitCu:100]) return NO;
    bzero(command, 16);
    BYTE(command, 2) &= 0xf8;    BYTE(command, 2) |= 1;
    BYTE(command, 3) |= 0x80;
    DWORD(command, 4) = ~0U;
    *(enet_addr_t *)((char *)command + 8) = myAddress;
    scb_p->commandList = cbl_paddr;
    scb_p->command = 0;
    BYTE(scb_p, 3) = (BYTE(scb_p, 3) & 0xf8) | 1;
    [self sendChannelAttention];
    for (i = 0; i < 2000; i++) {
        IODelay(1000);
        if (BYTE(command, 1) & 0x80) break;
    }
    if (BYTE(command, 1) & 0x80) return (BYTE(command, 1) & 0x20) != 0;
    IOLog("%s: IA-setup command timed out\n", [self name]);
    return NO;
}

/* 0x2554 */
- (BOOL)mcSetup
{
    queue_head_t *queue = [super multicastQueue];
    enetMulti_t *entry;
    unsigned char *command;
    void *allocation;
    unsigned int allocationSize, count;
    int i;
    BOOL result;
    if (![self _waitScb] || ![self _waitCu:100]) return NO;
    command = IOMallocPage(page_size, &allocation, &allocationSize);
    if (!command) {
        IOLog("%s: mcSetup:IOMallocPage return NULL\n", [self name]);
        return NO;
    }
    WORD(command, 0) = 0;
    WORD(command, 2) = 0;
    BYTE(command, 2) &= 0xf8;    BYTE(command, 2) |= 3;
    BYTE(command, 3) |= 0x80;
    DWORD(command, 4) = ~0U;
    count = 0;
    /* DriverKit queues point to the containing enetMulti_t, not its link field. */
    for (entry = (enetMulti_t *)queue->next; entry != (enetMulti_t *)queue;
         entry = (enetMulti_t *)entry->link.next) {
        *(enet_addr_t *)(command + 10 + 6 * count) = entry->address;
        count++;
    }
    WORD(command, 8) = 6 * count;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)command, (unsigned int *)&scb_p->commandList)) {
        IOLog("%s: Invalid MC-setup command block address\n", [self name]);
    } else {
        scb_p->command = 0;
        BYTE(scb_p, 3) = (BYTE(scb_p, 3) & 0xf8) | 1;
        [self sendChannelAttention];
        for (i = 0; i < 2000; i++) {
            IODelay(1000);
            if (BYTE(command, 1) & 0x80) break;
            if (BYTE(command, 1) & 0x10) break;
        }
        if (BYTE(command, 1) & 0x80) {
            result = (BYTE(command, 1) & 0x20) != 0;
            IOFree(allocation, allocationSize);
            multicastConfigured = YES;
            return result;
        }
        IOLog("%s: MC-setup command timed out 0x%x\n", [self name], WORD(command, 0));
    }
    IOFree(allocation, allocationSize);
    return NO;
}

/* 0x274c: the reference uses subclass interrupt dispatch. */
- (void)interruptOccurred {}

/* 0x2754 */
- (void)transmit:(netbuf_t)packet
{
    if ([self isRunning]) {
        [self serviceTransmitQueue];
        if ([transmitQueue count] == 0 && headFreeTcb) [self _transmitPacket:packet];
        else [transmitQueue enqueue:packet];
    } else nb_free(packet);
}

/* 0x27d4 */
- (void)timeoutOccurred
{
    if ([self isRunning]) [self interruptOccurred];
}

/* 0x2804 */
- (BOOL)enablePromiscuousMode
{
    if (!promiscuousEnabled) promiscuousEnabled = YES;
    return [self config];
}

/* 0x2830 */
- (void)disablePromiscuousMode
{
    if (promiscuousEnabled) promiscuousEnabled = NO;
    [self config];
}

/* 0x2858 */
- (BOOL)enableMulticastMode
{
    multicastEnabled = YES;
    return YES;
}

/* 0x2870 */
- (void)disableMulticastMode
{
    if (multicastEnabled && ![self mcSetup])
        IOLog("%s: disable multicast mode failed\n", [self name]);
    multicastEnabled = NO;
}

/* 0x28bc */
- (void)addMulticastAddress:(enet_addr_t *)address
{
    multicastEnabled = YES;
    if (![self mcSetup]) IOLog("%s: add multicast address failed\n", [self name]);
}

/* 0x2900 */
- (void)removeMulticastAddress:(enet_addr_t *)address
{
    if (![self mcSetup]) IOLog("%s: remove multicast address failed\n", [self name]);
}

/* 0x293c: debugger receive, reconstructed from assembly. Length includes CRC. */
- (void)receivePacket:(void *)packet length:(unsigned int *)length timeout:(unsigned int)timeout
{
    int remaining = timeout * 1000;
    int i;
    I556RFD *rfd;
    *length = 0;
    while (!(BYTE(headRfd, 1) & 0x80)) {
        if (remaining <= 0) {
            if ((BYTE(scb_p, 0) & 0xf0) != 0x40) goto restart;
            return;
        }
        IODelay(50);
        remaining -= 50;
    }
    if (BYTE(scb_p, 1) & 0x40) {
        if (![self _waitScb] || ![self _waitCu:1000]) return;
        scb_p->command = 0;
        BYTE(scb_p, 3) = (BYTE(scb_p, 3) & 0x0f) | 0x40;
        [self sendChannelAttention];
        for (i = 0; i < 2000; i++) {
            IODelay(1);
            if (!(BYTE(scb_p, 3) & 0xf0)) break;
        }
    }
    if (!(BYTE(&headRfd->rbd, 1) & 0x80)) {
restart:
        [self _abortReceiveUnit];
        [self _initRfdList];
        [self _startReceiveUnit];
        return;
    }
    rfd = headRfd;
    if (!(BYTE(rfd, 1) & 0x20)) return;
    *length = rfd->rbd.status & 0x3fff;
    bcopy(nb_map(rfd->netbuf), packet, *length);
    rfd->status = 0;
    BYTE(rfd, 3) |= 0x80;
    rfd->rbdAddress = ~0U;
    rfd->count = 0;
    rfd->size = 0;
    rfd->rbd.status = 0;
    rfd->rbd.size &= 0xc000;
    rfd->rbd.size |= 1518;
    rfd->rbd.end = 1;
    tailRfd->rbd.end = 0;
    BYTE(tailRfd, 3) &= 0x7f;
    tailRfd = tailRfd->next;
    headRfd = headRfd->next;
}

/* 0x2b48 */
- (void)sendPacket:(void *)packet length:(unsigned int)length
{
    BOOL pending = NO;
    int i;
    if (![self _waitScb] || ![self _waitCu:1000]) return;
    if (BYTE(scb_p, 1) & 0xa0) {
        scb_p->command = 0;
        BYTE(scb_p, 3) = (BYTE(scb_p, 1) & 0xa0) | (BYTE(scb_p, 3) & 0x0f);
        [self sendChannelAttention];
        for (i = 0; i < 2000; i++) {
            IODelay(1);
            if (!(BYTE(scb_p, 3) & 0xf0)) break;
        }
        pending = YES;
    }
    KDB_tcb_p->status = 0;
    KDB_tcb_p->link = ~0U;
    KDB_tcb_p->command = 0;
    BYTE(KDB_tcb_p, 2) &= 0xf8;    BYTE(KDB_tcb_p, 2) |= 4;
    BYTE(KDB_tcb_p, 2) |= 8;
    BYTE(KDB_tcb_p, 3) |= 0x80;
    KDB_tcb_p->tbdAddress = KDB_tcb_p->tbd[0].physical;
    KDB_tcb_p->count = 0;
    if (length > 1514) length = 1514;
    if (length < 64) length = 64;
    bcopy(packet, KDB_buf_p, length);
    KDB_tcb_p->tbd[0].buffer = KDB_buf_paddr;
    KDB_tcb_p->tbd[0].count = 0;
    KDB_tcb_p->tbd[0].count &= 0x8000;
    KDB_tcb_p->tbd[0].count |= length & 0x7fff;
    BYTE(&KDB_tcb_p->tbd[0], 1) |= 0x80;
    KDB_tcb_p->tbd[0].link = ~0U;
    scb_p->command = 0;
    BYTE(scb_p, 3) = (BYTE(scb_p, 3) & 0xf8) | 1;
    scb_p->commandList = KDB_tcb_p->physical;
    [self sendChannelAttention];
    if (!pending && [self _waitScb] && [self _waitCu:1000] && (BYTE(scb_p, 1) & 0xa0)) {
        BYTE(scb_p, 3) = (BYTE(scb_p, 1) & 0xa0) | (BYTE(scb_p, 3) & 0x0f);
        [self sendChannelAttention];
        for (i = 0; i < 2000; i++) {
            IODelay(1);
            if (!(BYTE(scb_p, 3) & 0xf0)) break;
        }
    }
}

/* 0x2d94 */
- (int)transmitQueueSize { return 96; }
/* 0x2da0 */
- (int)transmitQueueCount { return [transmitQueue count]; }

/* These empty hooks are present in the original base class. */
/* 0x2dc0 */
- (void)sendPortCommand:(int)command with:(unsigned int)argument {}
/* 0x2dc8 */
- (void)sendChannelAttention {}
/* 0x2dd0 */
- (void)getEthernetAddress {}
/* 0x2dd8 */
- (void)resetPLXchip {}
/* 0x2de0 */
- (void)initPLXchip {}
/* 0x2de8 */
- (void)lockDBRT {}
/* 0x2df0 */
- (void)enableAdapterInterrupts {}
/* 0x2df8 */
- (void)disableAdapterInterrupts {}

/* 0x2e00 */
- (IOReturn)getPowerState:(PMPowerState *)state { return -711; }
/* 0x2e0c */
- (IOReturn)setPowerState:(PMPowerState)state
{
    if (state != 3) return -711;
    [self _abortReceiveUnit];
    [self clearTimeout];
    [self disableAdapterInterrupts];
    [self sendPortCommand:0 with:0];
    return 0;
}
/* 0x2e64 */
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state { return -711; }
/* 0x2e70 */
- (IOReturn)setPowerManagement:(PMPowerManagementState)state { return -711; }
@end
