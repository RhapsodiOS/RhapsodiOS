/*
 * Intel82596.m
 * Intel 82596 Ethernet Controller Base Driver
 */

#import "Intel82596Private.h"
#import "Intel82596Buf.h"
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IODirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/i386/ioPorts.h>
#import <objc/Object.h>
#import <objc/objc-runtime.h>
#import <mach/mach_interface.h>
#import <bsd/string.h>

/* Network buffer API - from netbuf framework */
extern void nb_free(netbuf_t netbuf);
extern void *nb_map(netbuf_t netbuf);
extern unsigned int nb_size(netbuf_t netbuf);
#define _nb_free nb_free
#define _nb_map nb_map
#define _nb_size nb_size

/* Network scheduler timeout function */
typedef id (*I596TimeoutFunc)(id);
extern void ns_timeout(I596TimeoutFunc function, id target, int arg1, int arg2, int flags);
#define _ns_timeout ns_timeout

/* Private methods category */
@implementation Intel82596

/*
 * Initialize from device description
 */
/*
 * Free driver instance
 * Performs complete cleanup of all allocated resources
 */
- free
{
    unsigned int i;
    struct objc_super superInfo;

    if (resetAndEnabled == 1) {
        [self clearTimeout];
        [self disableAllInterrupts];
        [self _waitScb];
        [self _waitCu:1000];
        [self _abortReceiveUnit];
        resetAndEnabled = 0;
    }
    if (networkInterface != nil)
        [networkInterface free];
    if (xmtQueue != nil)
        [xmtQueue free];
    if (bufferPool != nil) {
        for (i = 0; i < 16; ++i) {
            netbuf_t packet = *(netbuf_t *)((char *)rfdList + i * 64 + 56);
            if (packet != NULL)
                nb_free(packet);
        }
        [bufferPool free];
    }
    IOFree(sharedMem_actualPtr, sharedMem_actualSize);
    superInfo.receiver = self;
    superInfo.super_class = [Intel82596 superclass];
    return objc_msgSendSuper(&superInfo, @selector(free));
}

/*
 * Reset and enable/disable the adapter
 * Performs complete hardware reset and optionally enables interrupts
 */
- (char)resetAndEnable:(char)enable
{
    sourceAddressInsertion = 0;
    [self clearTimeout];
    [self disableAllInterrupts];
    if (![self hwInit] || ![self swInit])
        return NO;
    if (enable && [self enableAllInterrupts] != 0) {
        [self setRunning:NO];
            return NO;
    }
    [self setRunning:enable];
    resetAndEnabled = 1;
    return YES;
}

/*
 * Cold initialization
 * Allocates shared memory for all 82596 structures and initializes the chip
 */
- (char)coldInit
{
    unsigned int actualSize, poolSize = 0;
    void *actualPtr = NULL;
    sharedMemSize = page_size;
    sharedMemPtr = IOMallocNonCached(page_size, &actualPtr, &actualSize);
    sharedMem_actualPtr = actualPtr; sharedMem_actualSize = actualSize;
    if (sharedMemPtr == NULL) { IOLog("eMASTER+: Can't allocate shared memory page\n"); return 0; }
    bzero(sharedMemPtr, sharedMemSize);
    sharedMemAllocPtr = sharedMemPtr; sharedMemAvail = sharedMemSize;
    scp = (I596SCP *)[self _memAlloc:28];
    if (((unsigned int)scp & 15) != 0) scp = (I596SCP *)(((unsigned int)scp + 15) & ~15U);
    iscp = (I596ISCP *)[self _memAlloc:8]; scb = (I596SCB *)[self _memAlloc:40];
    selfTestArea = [self _memAlloc:24];
    if (((unsigned int)selfTestArea & 15) != 0) selfTestArea = (void *)(((unsigned int)selfTestArea + 15) & ~15U);
    tcbList = (I596TCB *)[self _memAlloc:864]; kdbTcb = (I596TCB *)[self _memAlloc:108];
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)kdbTcb, (unsigned int *)((char *)kdbTcb + 28)) != IO_R_SUCCESS) {
        IOLog("%s: Invalid TCB address\n", [self name]); return 0;
    }
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)((char *)kdbTcb + 32), (unsigned int *)((char *)kdbTcb + 44)) != IO_R_SUCCESS) {
        IOLog("%s: Invalid TCB->TBD address\n", [self name]); return 0;
    }
    rfdList = (I596RFD *)[self _memAlloc:1024]; kdbPacketBuffer = [self _memAlloc:1514];
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)kdbPacketBuffer, &kdbPacketPhysical) != IO_R_SUCCESS) {
        IOLog("%s: Invalid address\n", [self name]); return 0;
    }
    bufferPool = [[Intel82596Buf alloc] initWithRequestedSize:1514 actualSize:&poolSize count:32];
    if (poolSize > 1513) return 1;
    IOLog("%s: Unable to allocate memory buffers of adequate length\n", [self name]);
    return 0;
}

/*
 * Hardware initialization
 * Performs complete hardware initialization sequence
 */
- (char)hwInit
{
    /* Reset and self-test the chip */
    if (![self _resetAndSelfTest]) {
        return NO;
    }

    /* Initialize 82596 chip structures */
    if (![self _init596]) {
        return NO;
    }

    /* Clear interrupt latch (hardware-specific) */
    [self clearIrqLatch];

    /* Set throttle timers */
    if (![self setThrottleTimers]) {
        return NO;
    }

    /* Configure the chip */
    if (![self config]) {
        return NO;
    }

    /* Setup individual address (MAC address) */
    if (![self iaSetup]) {
        return NO;
    }

    /* Setup multicast addresses */
    if (![self mcSetup]) {
        return NO;
    }

    return YES;
}

/*
 * Software initialization
 * Initializes transmit and receive structures and starts receive unit
 */
- (char)swInit
{
    BOOL returnValue = NO;

    /* Reserve debugger lock */
    [self reserveDebuggerLock];

    /* Initialize TCB list */
    if (![self _initTcbList]) {
        [self releaseDebuggerLock];
        return NO;
    }

    /* Initialize RFD list */
    if (![self _initRfdList]) {
        [self releaseDebuggerLock];
        return NO;
    }

    /* Start receive unit */
    if ([self _startReceiveUnit]) {
        returnValue = YES;
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];

    return returnValue;
}

/*
 * Configure the 82596
 * Sends a 14-byte configuration command to set chip parameters
 */
- (char)config
{
    struct { unsigned short status, command; unsigned int link; unsigned char cfg[14]; } command;
    unsigned int i;
    if (![self _waitScb] || ![self _waitCu:100]) return 0;
    bzero(&command, sizeof(command));
    command.command = 0xc002; command.link = 0xffffffffU;
    command.cfg[0]=14; command.cfg[1]=0xca; command.cfg[2]=0; command.cfg[3]=sourceAddressInsertion ? 0x26 : 0x2e;
    command.cfg[4]=0; command.cfg[5]=0x60; command.cfg[6]=0; command.cfg[7]=0xf2;
    command.cfg[8]=promiscuousEnabled != 0; command.cfg[9]=0;
    command.cfg[10]=0x40; command.cfg[11]=allMulticastEnabled ? 0xdd : 0xfd;
    command.cfg[12]=fullDuplexMode == 1 ? 0x40 : 0; command.cfg[13]=0x3f;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)&command, (unsigned int *)((char *)scb + 4)) != IO_R_SUCCESS) {
        IOLog("%s: Invalid configure command block address\n", [self name]); return 0;
    }
    *(unsigned short *)(scb->bytes + 2)=0x0100;
    [self sendChannelAttention];
    for (i=0; i<2000; ++i) { IODelay(1000); if (command.status & 0x8000) break; }
    [self clearIrqLatch];
    if (i != 2000) return (command.status & 0x2000) != 0;
    IOLog("%s: configure command timed out\n", [self name]); return 0;
}

/*
 * Individual Address setup
 * Sends IA Setup command to configure the chip's MAC address
 */
- (char)iaSetup
{
    struct { unsigned short status, command; unsigned int link; enet_addr_t address; } command;
    unsigned int i;
    if (![self _waitScb] || ![self _waitCu:100]) return 0;
    bzero(&command, sizeof(command)); command.command=0xc001; command.link=0xffffffffU; command.address=myAddress;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)&command, (unsigned int *)((char *)scb + 4)) != IO_R_SUCCESS) {
        IOLog("%s: Invalid IA-setup command block address\n", [self name]); return 0;
    }
    *(unsigned short *)(scb->bytes+2)=0x0100; [self sendChannelAttention];
    for(i=0;i<2000;++i) { IODelay(1000); if(command.status & 0x8000) break; }
    [self clearIrqLatch];
    if(i==2000) { IOLog("%s: IA-setup command timed out\n", [self name]); return 0; }
    return (command.status & 0x2000) != 0;
}

/*
 * Multicast setup
 * Sends MC Setup command to configure multicast address filtering
 */
- (char)mcSetup
{
    void *actualAddress;
    unsigned int actualSize, count=0, i;
    unsigned short status;
    id queue;
    void *entry;
    unsigned char *command;
    char succeeded=1;
    multicastConfigured=0;
    if (!multicastEnabled) return 1;
    queue=[super multicastQueue];
    if (![self _waitScb] || ![self _waitCu:100]) return 0;
    if (*(void **)queue == queue) return 1;
    command=(unsigned char *)IOMallocPage(page_size,&actualAddress,&actualSize);
    *(unsigned short *)command=0;
    *(unsigned short *)(command+2)=0xc003;
    *(unsigned int *)(command+4)=0xffffffffU;
    entry=*(void **)queue;
    while(entry!=queue) {
        unsigned char *dst=command+10+count*6;
        *(unsigned int *)dst=*(unsigned int *)entry;
        *(unsigned short *)(dst+4)=*((unsigned short *)entry+2);
        ++count;
        entry=*((void **)entry+2);
    }
    *(unsigned short *)(command+8)=(unsigned short)(count*6);
    if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)command,(unsigned int *)(scb->bytes+4))!=IO_R_SUCCESS) {
        IOLog("%s: Invalid MC-setup command block address\n",[self name]);
        IOFree(actualAddress,actualSize); return 0;
    }
    *(unsigned short *)(scb->bytes+2)=0x0100; [self sendChannelAttention];
    for(i=0;i<2000;++i) { IODelay(1000); if(*(unsigned short *)command & 0x8000) break; }
    if(i==2000) { IOLog("%s: MC-setup command timed out\n",[self name]); succeeded=0; }
    else { status=*(unsigned short *)command; succeeded=(status&0x2000)!=0; [self clearIrqLatch]; multicastConfigured=1; }
    IOFree(actualAddress,actualSize);
    return succeeded;
}

/*
 * Interrupt handler
 * Called when hardware interrupt occurs
 */
- (void)interruptOccurred
{
    unsigned short status=*(unsigned short *)scb->bytes;
    [self acknowledgeInterrupts:status];
    [self clearIrqLatch];
    if (((status & 0x5000)==0 || [self processRecInterrupt]) &&
        activeTcbHead != NULL && (*(unsigned short *)activeTcbHead & 0x8000))
        [self processXmtInterrupt];
}

/*
 * Timeout handler
 * Called when a timeout expires - checks if running and triggers interrupt processing
 */
- (void)timeoutOccurred
{
    if ([self isRunning]) [self interruptOccurred];
}

/*
 * Acknowledge interrupts
 * Writes acknowledgment bits to SCB command field and waits for them to clear
 */
- (char)acknowledgeInterrupts:(unsigned short)intStatus
{
    unsigned int i;
    if ((intStatus & 0xf000) == 0) return 0;
    if (*(unsigned short *)(scb->bytes+2) == 0 || [self _waitScb]) {
        *(unsigned short *)(scb->bytes+2)=intStatus & 0xf000;
        [self sendChannelAttention];
        for(i=0;i<2000;++i) {
            IODelay(1);
            if ((scb->bytes[3] & 0xf0)==0) break;
        }
    }
    return 1;
}

/*
 * Disable all interrupts
 */
/*
 * Reserve debugger lock
 */
/*
 * Release debugger lock
 */
/*
 * Allocate network buffer
 */
/*
 * Transmit a packet
 * Main entry point for network stack to send packets
 */
- (void)transmit:(netbuf_t)packet
{
    if ([self isRunning]) {
        [self serviceTransmitQueue];
        if ([xmtQueue count] == 0 && headFreeTcb != NULL)
            [self _transmitPacket:packet];
        else
            [xmtQueue enqueue:packet];
    } else {
        nb_free(packet);
    }
}

/*
 * Send packet (synchronous)
 * Used for debugger and special cases - sends packet directly
 */
- (void)sendPacket:(void *)pkt length:(unsigned int)len
{
    unsigned int length=len, i;
    char acked=0;
    if (![self _waitScb] || ![self _waitCu:1000]) return;
    if (*(unsigned short *)scb->bytes & 0xa000) {
        *(unsigned short *)(scb->bytes+2)=*(unsigned short *)scb->bytes & 0xa000;
        [self sendChannelAttention];
        for(i=0;i<2000;++i) { IODelay(1); if((scb->bytes[3]&0xf0)==0) break; }
        acked=1;
    }
    *(unsigned short *)kdbTcb=0;
    *(unsigned int *)((char *)kdbTcb+4)=0xffffffffU;
    *(unsigned short *)((char *)kdbTcb+2)=0xa00c;
    *(unsigned int *)((char *)kdbTcb+24)=0;
    *(unsigned int *)((char *)kdbTcb+8)=*(unsigned int *)((char *)kdbTcb+44);
    *(unsigned short *)((char *)kdbTcb+12)=0;
    *(unsigned short *)((char *)kdbTcb+14)=0;
    if(length>1514) length=1514;
    if(length<64) length=64;
    bcopy(pkt,kdbPacketBuffer,length);
    *(unsigned int *)((char *)kdbTcb+40)=kdbPacketPhysical;
    *(unsigned short *)((char *)kdbTcb+32)=(unsigned short)(length|0x8000);
    *(unsigned short *)((char *)kdbTcb+34)=0;
    *(unsigned int *)((char *)kdbTcb+36)=0xffffffffU;
    bzero((char *)kdbTcb+16,8);
    *(unsigned short *)(scb->bytes+2)=0x0100;
    *(unsigned int *)(scb->bytes+4)=*(unsigned int *)((char *)kdbTcb+28);
    [self sendChannelAttention];
    if(!acked && [self _waitScb] && [self _waitCu:1000] && (*(unsigned short *)scb->bytes&0xa000)) {
        *(unsigned short *)(scb->bytes+2)=*(unsigned short *)scb->bytes&0xa000;
        [self sendChannelAttention];
        for(i=0;i<2000;++i) { IODelay(1); if((scb->bytes[3]&0xf0)==0) break; }
    }
}

/*
 * Receive packet (synchronous polling)
 * Used for debugger and special cases - waits for packet to arrive
 */
- (void)receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout
{
    int remaining=1000*(int)timeout;
    unsigned int i, length;
    I596RFD *rfd=headRfd;
    *len=0;
    while (*(short *)rfd >= 0) {
        if (remaining <= 0) {
            if ((*(unsigned short *)scb->bytes & 0x00f0)==0x0040) return;
            goto recover;
        }
        IODelay(50); remaining-=50;
    }
    if (*(unsigned short *)scb->bytes & 0x4000) {
        if (![self _waitScb] || ![self _waitCu:1000]) return;
        *(unsigned short *)(scb->bytes+2)=0x4000;
        [self sendChannelAttention];
        for(i=0;i<2000;++i) {
            IODelay(1);
            if ((scb->bytes[3]&0xf0)==0) break;
        }
    }
    if (*(short *)((char *)rfd+40) >= 0) {
        [self _abortReceiveUnit];
        goto recover;
    }
    if (*(unsigned short *)rfd & 0x2000) {
        netbuf_t packet=*(netbuf_t *)((char *)rfd+56);
        length=*(unsigned short *)((char *)rfd+40)&0x3fff;
        *len=length;
        bcopy(nb_map(packet),pkt,length);
        *(unsigned int *)((char *)rfd+4)=*(unsigned int *)((char *)*(I596RFD **)((char *)rfd+32)+36);
        if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)nb_map(packet),(unsigned int *)((char *)rfd+48))!=IO_R_SUCCESS)
            IOPanic("Invalid net buffer address");
        *(unsigned short *)rfd=0;
        *(unsigned short *)((char *)rfd+2)=0x8008;
        *(unsigned int *)((char *)rfd+8)=0xffffffffU;
        *(unsigned short *)((char *)rfd+14)=0;
        *(unsigned short *)((char *)rfd+12)=0;
        *(unsigned short *)((char *)rfd+40)=0;
        *(unsigned short *)((char *)rfd+42)=0;
        *(unsigned short *)((char *)rfd+54)=0;
        *(unsigned short *)((char *)rfd+52)=0x85ea;
        *(unsigned short *)((char *)*(I596RFD **)((char *)tailRfd+32)+52)&=~0x8000;
        *(unsigned short *)((char *)tailRfd+2)&=~0x8000;
        tailRfd=*(I596RFD **)((char *)tailRfd+32);
        headRfd=*(I596RFD **)((char *)rfd+32);
    }
    return;
recover:
    [self _initRfdList];
    [self _startReceiveUnit];
}

/*
 * Service transmit queue
 * Dequeues and transmits pending packets
 */
- (void)serviceTransmitQueue
{
    netbuf_t packet;
    while (headFreeTcb != NULL) {
        packet = [xmtQueue dequeue];
        if (packet == NULL) break;
        [self _transmitPacket:packet];
    }
}

/*
 * Process receive interrupt
 * Handles received packets from the RFD list
 */
- (char)processRecInterrupt
{
    I596RFD *rfd;
    [self reserveDebuggerLock];
    rfd=headRfd;
    while (rfd != NULL && (*(short *)rfd < 0)) {
        unsigned short status=*(unsigned short *)rfd;
        if (*(short *)((char *)rfd+40) >= 0) {
            IOLog("%s: Oversize frame in RFD %ld\n",[self name],0L);
            [networkInterface incrementInputErrors];
            [self _abortReceiveUnit]; [self _initRfdList];
            if (![self _startReceiveUnit]) {
                [self _scheduleReset]; [self releaseDebuggerLock]; return 0;
            }
            [self releaseDebuggerLock]; return 0;
        }
        headRfd=*(I596RFD **)((char *)rfd+32);
        if (status & 0x2000) {
            netbuf_t packet=*(netbuf_t *)((char *)rfd+56);
            unsigned int length=*(unsigned short *)((char *)rfd+40) & 0x3fff;
            [self releaseDebuggerLock];
            if (length > 0x3b &&
                (promiscuousEnabled==1 || multicastConfigured==0 || (status&2)==0 ||
                 ![super isUnwantedMulticastPacket:nb_map(packet)])) {
                netbuf_t replacement=[self _recAllocateNetbuf];
                if (replacement != NULL) {
                    unsigned int size=nb_size(packet);
                    if (length<size) nb_shrink_bot(packet,size-length);
                    [networkInterface handleInputPacket:packet extra:0];
                    *(netbuf_t *)((char *)rfd+56)=replacement;
                    if (IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)nb_map(replacement),(unsigned int *)((char *)rfd+48))!=IO_R_SUCCESS)
                        IOPanic("Invalid net buffer address");
                } else {
                    netbuf_t copy=[self allocateNetbuf];
                    if (copy != NULL) {
                        void *to=nb_map(copy), *from=nb_map(packet);
                        bcopy(from,to,length);
                        nb_shrink_bot(copy,nb_size(copy)-length);
                        [networkInterface handleInputPacket:copy extra:0];
                    }
                }
            }
            [self reserveDebuggerLock];
        } else {
            [networkInterface incrementInputErrors];
        }
        *(unsigned int *)((char *)rfd+4)=*(unsigned int *)((char *)*(I596RFD **)((char *)rfd+32)+36);
        *(unsigned short *)rfd=0;
        *(unsigned short *)((char *)rfd+2)=0x8008;
        *(unsigned int *)((char *)rfd+8)=0xffffffffU;
        *(unsigned short *)((char *)rfd+12)=0;
        *(unsigned short *)((char *)rfd+14)=0;
        *(unsigned short *)((char *)rfd+40)=0;
        *(unsigned short *)((char *)rfd+42)=0;
        *(unsigned short *)((char *)rfd+54)=0;
        *(unsigned short *)((char *)rfd+52)=0x85ea;
        *(unsigned short *)((char *)*(I596RFD **)((char *)tailRfd+32)+52) &= ~0x8000;
        *(unsigned short *)((char *)tailRfd+2) &= ~0x8000;
        tailRfd=*(I596RFD **)((char *)tailRfd+32);
        rfd=headRfd;
    }
    {
        unsigned short status=*(unsigned short *)scb->bytes;
        if ((status&0x00f0)==0x0040) {
            [self releaseDebuggerLock]; return 1;
        }
        if ((status&0x00f0)==0x00c0) [self _abortReceiveUnit];
        [self _initRfdList];
        if ([self _startReceiveUnit]) { [self releaseDebuggerLock]; return 1; }
        [self _scheduleReset];
        return 0;
    }
}

/*
 * Process transmit interrupt
 * Handles completed transmit command blocks
 */
- (char)processXmtInterrupt
{
    while (activeTcbHead != NULL && (*(unsigned short *)activeTcbHead & 0x8000)) {
        I596TCB *done=activeTcbHead;
        unsigned short status=*(unsigned short *)done;
        I596TCB *next=*(I596TCB **)((char *)done+24);
        netbuf_t packet;
        unsigned int i, collisions=0;
        [self clearTimeout];
        activeTcbHead=next;
        if (next==NULL && pendingTcbHead!=NULL) {
            *(unsigned short *)((char *)pendingTcbTail+2)|=0x8000;
            activeTcbHead=pendingTcbHead;
            pendingTcbHead=NULL;
            if (![self _startCommandUnit]) goto reset;
            [self setRelativeTimeout:500];
        }
        if (*(unsigned short *)((char *)done+4)==0x4000) {
            IOLog("%s: erratum 15 in tcb link addr!\n",[self name]);
            __asm__ volatile("int $3");
        }
        if (status&0x2000) [networkInterface incrementOutputPackets];
        else [networkInterface incrementOutputErrors];
        collisions=status&0x000f;
        for(i=0;i<collisions;++i) [networkInterface incrementCollisions];
        if (status&0x20) for(i=0;i<16;++i) [networkInterface incrementCollisions];
        if (status&0x800) [networkInterface incrementCollisions];
        packet=*(netbuf_t *)((char *)done+104);
        if (packet!=NULL) { nb_free(packet); *(netbuf_t *)((char *)done+104)=NULL; }
        *(I596TCB **)((char *)done+24)=headFreeTcb;
        headFreeTcb=done;
        if (status&0x600) goto reset;
    }
    [self serviceTransmitQueue];
    return 1;
reset:
    [self _scheduleReset];
    return 0;
}

/*
 * Enable promiscuous mode
 * Sets promiscuous mode flag and reconfigures chip
 */
- (char)enablePromiscuousMode
{
    if (promiscuousEnabled == 0) promiscuousEnabled=1;
    return [self config];
}

/*
 * Disable promiscuous mode
 * Clears promiscuous mode flag and reconfigures chip
 */
- (void)disablePromiscuousMode
{
    if (promiscuousEnabled != 0) promiscuousEnabled=0;
    [self config];
}

/*
 * Enable multicast mode
 * Sets multicast mode flag
 */
- (char)enableMulticastMode
{
    multicastEnabled=1;
    return 1;
}

/*
 * Disable multicast mode
 * Clears multicast mode flag and reconfigures chip if it was previously enabled
 */
- (void)disableMulticastMode
{
    char wasEnabled=multicastEnabled;
    multicastEnabled=0;
    if (wasEnabled && ![self mcSetup]) IOLog("%s: disable multicast mode failed\n",[self name]);
}

/*
 * Add multicast address
 * Sets multicast mode flag and calls mcSetup to configure the chip
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    multicastEnabled=1;
    if (![self mcSetup]) IOLog("%s: add multicast address failed\n",[self name]);
}

/*
 * Remove multicast address
 * Reconfigures multicast filtering after address is removed from queue
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    if (![self mcSetup]) IOLog("%s: remove multicast address failed\n",[self name]);
}

/*
 * Clear interrupt latch - subclass override
 * Base implementation is empty - hardware-specific subclasses must override
 */
- (void)clearIrqLatch
{
    /* The shared 82596 implementation has no board-specific latch. */
}

/*
 * Send channel attention - subclass override
 * Base implementation is empty - hardware-specific subclasses must override
 */
- (void)sendChannelAttention
{
    /* Subclasses perform the board-specific channel-attention write. */
}

/*
 * Send port command - subclass override
 * Base implementation is empty - hardware-specific subclasses must override
 */
- (void)sendPortCommand:(int)cmd with:(unsigned int)arg
{
    /* Subclasses provide the 82596 port-command register access. */
}

/*
 * Set I/O base address
 * Stores base address at offset 0x174
 */
- (void)setIOBase:(unsigned short)base
{
    ioBase = (unsigned short)base;
}

/*
 * Set throttle timers
 * Configures bus throttle timers to prevent DMA overruns
 */
- (char)setThrottleTimers
{
    unsigned int i;
    unsigned short status;
    if (![self _waitScb] || ![self _waitCu:100]) return 0;
    status=*(unsigned short *)scb->bytes;
    *(unsigned short *)scb->bytes=(status & 0xff00) | (status & 0x00f7);
    *(unsigned short *)(scb->bytes+36)=2;
    *(unsigned short *)(scb->bytes+38)=125;
    *(unsigned short *)(scb->bytes+2)=0x0600;
    [self sendChannelAttention];
    for(i=0;i<2000;++i) {
        IODelay(1000);
        if ((*(unsigned short *)scb->bytes & 8)!=0) return 1;
    }
    IOLog("%s: set throttle timers timed out\n",[self name]); return 0;
}

/*
 * Clear timeout
 */
/*
 * Set relative timeout
 */
/*
 * Enable all interrupts
 */
/*
 * Set running state
 */
/*
 * Check if driver is running
 */
/*
 * Get power management state
 * Power management not supported on this driver
 */
- (int)getPowerManagement:(int *)state
{
    return -711;
}

/*
 * Set power management state
 * Power management not supported on this driver
 */
- (int)setPowerManagement:(int)state
{
    return -711;
}

/*
 * Get power state
 * Power management not supported on this driver
 */
- (int)getPowerState:(int *)state
{
    return -711;
}

/*
 * Set power state
 * Handles sleep/wake power state transitions
 */
- (int)setPowerState:(int)state
{
    if (state != 3) return -711;
    [self _abortReceiveUnit]; [self clearTimeout]; [self sendPortCommand:0 with:0];
    return 0;
}

@end

/*
 * Private methods implementation
 */
@implementation Intel82596(Private)

/*
 * Initialize 82596 chip
 */
- (char)_init596
{
    unsigned int physical, i;
    bzero(scp, sizeof(*scp));
    *(unsigned short *)(scp->bytes + 2) = 0x0054;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)iscp, (unsigned int *)((char *)scp + 8)) != IO_R_SUCCESS) goto bad_iscp;
    bzero(iscp, sizeof(*iscp));
    iscp->bytes[0] = 1;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)scb, (unsigned int *)((char *)iscp + 4)) != IO_R_SUCCESS) goto bad_scb;
    bzero(scb, sizeof(*scb));
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)scp, &physical) != IO_R_SUCCESS) goto bad_scp;
    [self sendPortCommand:2 with:physical];
    IODelay(1000);
    [self sendChannelAttention];
    for (i = 0; i < 2000; ++i) {
        IODelay(1000);
        if (iscp->bytes[0] == 0) return 1;
    }
    IOLog("%s: 82596 initialization timed out\n", [self name]);
    return 0;
bad_iscp: IOLog("%s: Invalid ISCP address\n", [self name]); return 0;
bad_scb: IOLog("%s: Invalid SCB address\n", [self name]); return 0;
bad_scp: IOLog("%s: Invalid SCP address\n", [self name]); return 0;
}

/*
 * Reset and self-test the 82596 chip
 */
- (char)_resetAndSelfTest
{
    unsigned int physical, i, result;
    [self sendPortCommand:0 with:0];
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)selfTestArea, &physical) != IO_R_SUCCESS) {
        IOLog("%s: Invalid self test area address\n", [self name]); return 0;
    }
    *(unsigned int *)selfTestArea = 0xffffffffU;
    *((unsigned int *)selfTestArea + 1) = 0xffffffffU;
    [self sendPortCommand:1 with:physical];
    for (i = 0; i < 2000; ++i) { IODelay(1000); if (*(unsigned int *)selfTestArea != 0xffffffffU) break; }
    if (i == 2000) { IOLog("%s: Self test timed out\n", [self name]); return 0; }
    if (*((unsigned short *)selfTestArea + 2) != 0) {
        unsigned char errors = *((unsigned char *)selfTestArea + 4);
        if (errors & 4) IOLog("%s: Self test reports invalid ROM contents\n", [self name]);
        if (errors & 8) IOLog("%s: Self test reports internal register failure\n", [self name]);
        if (errors & 0x10) IOLog("%s: Self test reports bus throttle timer failure\n", [self name]);
        if (errors & 0x20) IOLog("%s: Self test reports serial subsystem failure\n", [self name]);
        if (*((unsigned char *)selfTestArea + 5) & 0x10) IOLog("%s: Self test failed\n", [self name]);
        return 0;
    }
    result = *(unsigned int *)selfTestArea;
    if (result == 1402235955U) chipRev = 0;
    else if (result == (unsigned int)-588996411) chipRev = 1;
    else if (result == 839460270U) chipRev = 2;
    else { IOLog("%s: Unknown chip revision\n", [self name]); chipRev = 0; }
    return 1;
}

/*
 * Schedule reset - cleanup transmit queue and schedule timeout
 */
- (void)_scheduleReset
{
    netbuf_t packet;
    [self _abortReceiveUnit];
    [self clearTimeout];
    while ((packet=[xmtQueue dequeue]) != NULL) nb_free(packet);
    ns_timeout(_resetFunc,self,0,0,4);
}

/*
 * Wait for SCB command register to clear
 * Polls up to 65535 times for SCB command field to become 0
 */
- (char)_waitScb
{
    unsigned int i;
    for (i = 0; i < 65535U; ++i) {
        if (scb->bytes[2] == 0 && scb->bytes[3] == 0)
            return 1;
    }
    IOLog("%s: timeout waiting for scb command to clear\n", [self name]);
    [self _scheduleReset];
    return 0;
}

/*
 * Wait for command unit to become inactive
 * timeout - timeout in milliseconds
 */
- (char)_waitCu:(unsigned int)timeout
{
    unsigned int i, limit = timeout * 1000U;
    for (i = 0; i < limit; ++i) {
        unsigned short status = *(unsigned short *)scb->bytes;
        if ((status & 0x0700) != 0x0200)
            return 1;
        IODelay(1);
    }
    IOLog("%s: timeout waiting for command unit to become inactive\n", [self name]);
    [self _scheduleReset];
    return 0;
}

/*
 * Start command unit
 */
- (char)_startCommandUnit
{
    unsigned short status;
    if (![self _waitScb]) {
        IOLog("%s: Cannot start command unit - SCB not clear\n", [self name]);
        return 0;
    }
    status = *(unsigned short *)scb->bytes;
    if ((status & 0x0700) == 0x0200 && ![self _waitCu:100]) {
        IOLog("%s: Cannot start command unit - still active\n", [self name]);
        return 0;
    }
    if (activeTcbHead == NULL || *(unsigned int *)((char *)activeTcbHead + 28) == 0) {
        IOLog("%s: Attempt to start command unit with null activeTcbHead virtual or physical address\n", [self name]);
        return 0;
    }
    *(unsigned short *)activeTcbHead |= 0x4000;
    *(unsigned short *)(scb->bytes + 2) = 0x0100;
    *(unsigned int *)(scb->bytes + 4) = *(unsigned int *)((char *)activeTcbHead + 28);
    [self sendChannelAttention];
    return 1;
}

/*
 * Start receive unit
 */
- (char)_startReceiveUnit
{
    unsigned int i;
    unsigned short status = *(unsigned short *)scb->bytes;
    if ((status & 0x00f0) == 0x0040)
        return 1;
    if (![self _waitScb] || ![self _waitCu:100])
        return 0;
    if (headRfd != NULL && *(unsigned int *)((char *)headRfd + 36) != 0 &&
        *(unsigned int *)((char *)headRfd + 60) != 0) {
        *(unsigned int *)((char *)headRfd + 8) = *(unsigned int *)((char *)headRfd + 60);
        *(unsigned int *)(scb->bytes + 8) = *(unsigned int *)((char *)headRfd + 36);
        *(unsigned short *)(scb->bytes + 2) = 0x0010;
        [self sendChannelAttention];
        for (i = 0; i < 10000; ++i) {
            if ((*(unsigned short *)scb->bytes & 0x00f0) == 0x0040)
                return 1;
            IODelay(1);
        }
        return 0;
    }
    IOLog("%s: attempt to start receive unit with null virtual or physical RFD/RBD address\n", [self name]);
    return 0;
}

/*
 * Abort receive unit
 */
- (char)_abortReceiveUnit
{
    unsigned int i;
    if ((*(unsigned short *)scb->bytes & 0x00f0) != 0x0040)
        return 1;
    if (![self _waitScb] || ![self _waitCu:100])
        return 0;
    *(unsigned short *)(scb->bytes + 2) = 0x0040;
    [self sendChannelAttention];
    for (i = 0; i < 2000; ++i) {
        IODelay(1000);
        if ((*(unsigned short *)scb->bytes & 0x00f0) == 0)
            return 1;
    }
    IOLog("%s: abort receive unit timed out\n", [self name]);
    return 0;
}

/*
 * Allocate memory for 82596 structures from shared memory pool
 * Aligns allocation to 4-byte boundary
 */
- (void *)_memAlloc:(unsigned int)size
{
    unsigned int rounded = (size + 3U) & ~3U;
    void *result;

    if (sharedMemAvail < rounded)
        IOPanic("Intel82596: shared memory exhausted\n");
    result = sharedMemAllocPtr;
    sharedMemAllocPtr = (char *)sharedMemAllocPtr + rounded;
    return result;
}

/*
 * Initialize RFD list (Receive Frame Descriptor list)
 */
- (char)_initRfdList
{
    unsigned int i;
    if ((*(unsigned short *)scb->bytes & 0x00c0) != 0) {
        IOLog("%s: _initRfdList called while receive unit ready\n", [self name]);
        [self _abortReceiveUnit];
    }
    for (i = 0; i < 16; ++i) {
        netbuf_t old = *(netbuf_t *)((char *)rfdList + i * 64 + 56);
        if (old != NULL) { nb_free(old); *(netbuf_t *)((char *)rfdList + i * 64 + 56) = NULL; }
    }
    bzero(rfdList, 0x400);
    for (i = 0; i < 16; ++i) {
        char *rfd = (char *)rfdList + i * 64;
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)rfd, (unsigned int *)(rfd + 36)) != IO_R_SUCCESS) {
            IOLog("%s: Invalid RFD address\n", [self name]); return 0;
        }
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)(rfd + 40), (unsigned int *)(rfd + 60)) != IO_R_SUCCESS) {
            IOLog("%s: Invalid RBD address\n", [self name]); return 0;
        }
    }
    for (i = 0; i < 16; ++i) {
        char *rfd = (char *)rfdList + i * 64;
        char *next = i == 15 ? (char *)rfdList : rfd + 64;
        netbuf_t packet;
        *(unsigned char *)(rfd + 2) |= 8;
        *(unsigned int *)(rfd + 32) = (unsigned int)next;
        *(unsigned int *)(rfd + 4) = *(unsigned int *)(next + 36);
        *(unsigned int *)(rfd + 8) = i == 0 ? *(unsigned int *)((char *)rfdList + 15 * 64 + 60) : 0xffffffffU;
        *(unsigned int *)(rfd + 44) = *(unsigned int *)(next + 60);
        packet = [self _recAllocateNetbuf];
        *(netbuf_t *)(rfd + 56) = packet;
        if (packet == NULL) IOLog("%s: receive buffer allocation failed\n", [self name]);
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)nb_map(packet), (unsigned int *)(rfd + 48)) != IO_R_SUCCESS) {
            IOLog("%s: Invalid RBD netbuf address\n", [self name]); return 0;
        }
        *(unsigned short *)(rfd + 52) = 1514;
        if (i == 15) *(unsigned short *)(rfd + 52) |= 0x8000;
    }
    *(unsigned short *)((char *)rfdList + 898) |= 0x8000;
    tailRfd = (I596RFD *)((char *)rfdList + 896);
    headRfd = rfdList;
    return 1;
}

/*
 * Initialize TCB list (Transmit Command Block list)
 */
- (char)_initTcbList
{
    unsigned int i, j;
    if ((*(unsigned short *)scb->bytes & 0x0200) != 0) {
        IOLog("%s: _initTcbList called while command unit active\n", [self name]);
        [self _waitCu:100];
    }
    for (i = 0; i < 8; ++i) {
        netbuf_t old = *(netbuf_t *)((char *)tcbList + i * 108 + 104);
        if (old != NULL) { nb_free(old); *(netbuf_t *)((char *)tcbList + i * 108 + 104) = NULL; }
    }
    bzero(tcbList, 0x360);
    for (i = 0; i < 8; ++i) {
        char *tcb = (char *)tcbList + i * 108;
        if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)tcb, (unsigned int *)(tcb + 28)) != IO_R_SUCCESS) {
            IOLog("%s: Invalid TCB address\n", [self name]); return 0;
        }
        for (j = 0; j < 3; ++j) {
            if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)(tcb + 32 + j * 24), (unsigned int *)(tcb + 44 + j * 24)) != IO_R_SUCCESS) {
                IOLog("%s: Invalid TBD address\n", [self name]); return 0;
            }
            if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)(tcb + 52 + j * 24), (unsigned int *)(tcb + 48 + j * 24)) != IO_R_SUCCESS) {
                IOLog("%s: Invalid TBD align address\n", [self name]); return 0;
            }
        }
        *(unsigned int *)(tcb + 24) = i == 7 ? 0 : (unsigned int)(tcb + 108);
    }
    headFreeTcb = tcbList;
    pendingTcbTail = NULL; pendingTcbHead = NULL; activeTcbHead = NULL;
    return 1;
}

/*
 * Transmit a packet using TCB/TBD structures
 */
- (void)_transmitPacket:(netbuf_t)packet
{
    I596TCB *tcb=headFreeTcb;
    char *tbd;
    unsigned int data, size, first, contiguous;
    int misalign, i;
    headFreeTcb=*(I596TCB **)((char *)tcb+24);
    *(unsigned short *)tcb=0;
    *(unsigned int *)((char *)tcb+4)=0xffffffffU;
    *(unsigned short *)((char *)tcb+2)=8204;
    *(unsigned int *)((char *)tcb+24)=0;
    *(unsigned int *)((char *)tcb+8)=*(unsigned int *)((char *)tcb+44);
    *(unsigned short *)((char *)tcb+12)=0;
    *(unsigned short *)((char *)tcb+14)=0;
    *(netbuf_t *)((char *)tcb+104)=packet;
    data=(unsigned int)nb_map(packet);
    size=nb_size(packet);
    tbd=(char *)tcb+32;
    misalign=data&3;
    if (misalign != 0) {
        first=4U-misalign;
        *(unsigned int *)((char *)tcb+40)=*(unsigned int *)((char *)tcb+48);
        *(unsigned short *)((char *)tcb+32)=(unsigned short)first;
        for(i=0;i<(int)first;++i) *((char *)tcb+52+i)=*(char *)(data++);
        *(unsigned int *)((char *)tcb+36)=*(unsigned int *)((char *)tcb+68);
        tbd=(char *)tcb+56;
        size-=first;
    }
    contiguous=IOIsPhysicallyContiguous(data,size);
    if (contiguous==0) {
        IOLog("%s: IOIsPhysicallyContiguous returned 0\n",[self name]);
        nb_free(packet); *(netbuf_t *)((char *)tcb+104)=NULL; return;
    }
    first=contiguous-data+1;
    if (first<size) {
        if (IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)data,(unsigned int *)(tbd+8))!=IO_R_SUCCESS) {
            IOLog("%s: Invalid address for outgoing packet (before piece)\n",[self name]);
            nb_free(packet); *(netbuf_t *)((char *)tcb+104)=NULL; return;
        }
        *(unsigned short *)tbd=(unsigned short)first;
        *(unsigned int *)(tbd+4)=*(unsigned int *)(tbd+36);
        tbd+=24; size-=first; data+=first;
    }
    if (IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)data,(unsigned int *)(tbd+8))!=IO_R_SUCCESS) {
        IOLog("%s: Invalid address for outgoing packet\n",[self name]);
        nb_free(packet); *(netbuf_t *)((char *)tcb+104)=NULL; return;
    }
    *(unsigned short *)tbd=(unsigned short)size|0x8000;
    *(unsigned int *)(tbd+4)=0xffffffffU;
    if (activeTcbHead != NULL) {
        if (pendingTcbHead != NULL) {
            *(unsigned int *)((char *)pendingTcbTail+24)=(unsigned int)tcb;
            *(unsigned int *)((char *)pendingTcbTail+4)=*(unsigned int *)((char *)tcb+28);
        } else pendingTcbHead=tcb;
        pendingTcbTail=tcb;
    } else {
        *(unsigned short *)((char *)tcb+2)|=0x8000;
        activeTcbHead=tcb;
        if ([self _startCommandUnit]) [self setRelativeTimeout:500];
        else [self _scheduleReset];
    }
}

/*
 * Allocate network buffer from buffer pool for receive operations
 */
- (netbuf_t)_recAllocateNetbuf
{
    if (bufferPool != nil)
        return [bufferPool getNetBuffer];
    IOLog("%s: allocateNetbuf called, but buffer pool doesn't exist\n", [self name]);
    return NULL;
}

@end

/*
 * C callback implementation
 */

/*
 * Reset function - called to reset a driver instance
 */
id _resetFunc(id driver)
{
    id result=[driver resetAndEnable:1];
    if ((char)result == 0) {
        IOLog("%s: Reset attempt unsuccessful\n",[driver name]);
        return nil;
    }
    return result;
}
