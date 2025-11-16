/*
 * Intel82596.m
 * Intel 82596 Ethernet Controller Base Driver
 */

#import <driverkit/IOEthernetDriver.h>
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
extern void nb_free(void *netbuf);
extern void *nb_map(void *netbuf, unsigned int *physAddr);
extern unsigned int nb_size(void *netbuf);
#define _nb_free nb_free
#define _nb_map nb_map
#define _nb_size nb_size

/* Network scheduler timeout function */
extern void ns_timeout(unsigned int msec, id target, int arg1, int arg2, int flags);
#define _ns_timeout ns_timeout

@interface Intel82596 : IOEthernetDriver
{
    /* Basic configuration */
    unsigned int ioBase;
    unsigned int irqLevel;
    unsigned int memBase;

    /* 82596 control structures - at specific offsets */
    void *scp;                  /* Offset 0x1b4: System Configuration Pointer */
    void *iscp;                 /* Offset 0x1b8: Intermediate SCP */
    void *scbBase;              /* Offset 0x1bc: System Control Block */
    void *cmdList;              /* Offset 0x1c0: Command list */
    void *tcbList;              /* Offset 0x1c4: Transmit Command Block list */
    void *tcbHead;              /* Offset 0x1c8: Head of TCB list */
    void *tcbTail;              /* Offset 0x1cc: Tail of TCB list */
    void *tcbFree;              /* Offset 0x1d0: Free TCB list */
    void *tcbReserved;          /* Offset 0x1d4: Reserved */

    /* Receive structures */
    void *rbd;                  /* Offset 0x1d8: Receive Buffer Descriptor */
    void *rbdReserved[2];       /* Reserved */
    void *rfdList;              /* Offset 0x1e4: Receive Frame Descriptor list */
    void *rfdHead;              /* Offset 0x1e8: Head of RFD list */
    void *rfdTail;              /* Offset 0x1ec: Tail of RFD list */

    /* Chip information */
    unsigned int chipRevision;  /* Offset 0x184: Chip revision ID */
    id bufferPool;              /* Offset 0x18c: Network buffer pool */

    /* Shared memory management */
    void *sharedMemPtr;         /* Offset 0x1a4: Current shared memory pointer */
    unsigned int sharedMemRemaining; /* Offset 0x1a8: Remaining shared memory */

    /* Mode and state */
    BOOL promiscuousMode;
    BOOL multicastMode;
    unsigned int multicastCount;
    id netif;
    id transmitQueue;
    unsigned char romAddress[6];
}

/* Initialization and control methods */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;
- (BOOL)resetAndEnable:(BOOL)enable;
- (BOOL)coldInit;
- (BOOL)hwInit;
- (BOOL)swInit;
- (BOOL)config;
- (BOOL)iaSetup;
- (BOOL)mcSetup;

/* Interrupt handling */
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)acknowledgeInterrupts:(unsigned int)intStatus;
- (void)disableAllInterrupts;

/* Transmit/receive operations */
- (void)transmit:(netbuf_t)packet;
- (void)sendPacket:(void *)pkt length:(unsigned int)len;
- (void)receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout;
- (void)serviceTransmitQueue;
- (BOOL)processRecInterrupt;
- (void)processXmtInterrupt;

/* Debugger lock */
- (void)reserveDebuggerLock;
- (void)releaseDebuggerLock;

/* Network buffer allocation */
- (void *)allocateNetbuf;

/* Mode control */
- (void)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (void)enableMulticastMode;
- (void)disableMulticastMode;
- (void)addMulticastAddress:(enet_addr_t *)addr;
- (void)removeMulticastAddress:(enet_addr_t *)addr;

/* Hardware interface - subclasses override these */
- (void)clearIrqLatch;
- (void)sendChannelAttention;
- (void)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg;
- (void)setIOBase:(unsigned int)base;

/* Throttle control */
- (BOOL)setThrottleTimers;

/* Timeout management */
- (void)clearTimeout;
- (void)setRelativeTimeout:(unsigned int)msec;

/* Interrupt control */
- (IOReturn)enableAllInterrupts;
- (void)setRunning:(BOOL)running;
- (BOOL)isRunning;

/* Power management */
- (IOReturn)getPowerManagement:(IOPMPowerManagementState *)state;
- (IOReturn)setPowerManagement:(IOPMPowerManagementState)state;
- (IOReturn)getPowerState:(IOPMPowerState *)state;
- (IOReturn)setPowerState:(IOPMPowerState)state;

@end

/* Private methods category */
@interface Intel82596(Private)
- (BOOL)_init596;
- (BOOL)_resetAndSelfTest;
- (void)_scheduleReset;
- (BOOL)_waitScb;
- (BOOL)_waitCu:(unsigned int)timeout;
- (BOOL)_startCommandUnit;
- (BOOL)_startReceiveUnit;
- (BOOL)_abortReceiveUnit;
- (void *)_memAlloc:(unsigned int)size;
- (BOOL)_initRfdList;
- (BOOL)_initTcbList;
- (BOOL)_transmitPacket:(netbuf_t)packet;
- (BOOL)_recAllocateNetbuf;
@end

@implementation Intel82596

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOLog("Intel82596: initFromDeviceDescription - stub\n");
    return nil;
}

/*
 * Free driver instance
 * Performs complete cleanup of all allocated resources
 */
- free
{
    int i;
    void *netbuf;

    /* If driver is enabled (offset 0x199), shut it down cleanly */
    if (*((char *)self + 0x199) == 1) {
        /* Clear any pending timeout */
        [self clearTimeout];

        /* Disable all interrupts */
        [self disableAllInterrupts];

        /* Wait for SCB to be ready */
        [self _waitScb];

        /* Wait for command unit (up to 1000ms) */
        [self _waitCu:1000];

        /* Abort receive unit */
        [self _abortReceiveUnit];

        /* Mark driver as disabled */
        *((char *)self + 0x199) = 0;
    }

    /* Free network interface object (offset 0x188) */
    if (*((id *)self + 0x188/sizeof(id)) != nil) {
        [*((id *)self + 0x188/sizeof(id)) free];
    }

    /* Free transmit queue (offset 400 decimal = 0x190) */
    if (*((id *)self + 400/sizeof(id)) != nil) {
        [*((id *)self + 400/sizeof(id)) free];
    }

    /* Free buffer pool and associated netbufs */
    if (bufferPool != nil) {
        /* Free all netbufs in RFD list (16 RFDs) */
        for (i = 0; i < 0x10; i++) {
            /* Each RFD is 0x40 bytes, netbuf pointer at offset 0x38 */
            netbuf = *(void **)((char *)rfdList + (i * 0x40) + 0x38);
            if (netbuf != NULL) {
                _nb_free(netbuf);
            }
        }

        /* Free buffer pool object */
        [bufferPool free];
    }

    /* Free shared memory allocated in coldInit */
    if (*((void **)self + 0x1ac/sizeof(void *)) != NULL) {
        IOFree(*((void **)self + 0x1ac/sizeof(void *)),
               *((unsigned int *)self + 0x1b0/sizeof(unsigned int)));
    }

    /* Call superclass free */
    return [super free];
}

/*
 * Reset and enable/disable the adapter
 * Performs complete hardware reset and optionally enables interrupts
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    IOReturn result;

    /* Clear reset flag (offset 0x198) */
    *((char *)self + 0x198) = 0;

    /* Clear any pending timeout */
    [self clearTimeout];

    /* Disable all interrupts */
    [self disableAllInterrupts];

    /* Perform hardware initialization */
    if (![self hwInit]) {
        return NO;
    }

    /* Perform software initialization */
    if (![self swInit]) {
        return NO;
    }

    /* Enable interrupts if requested */
    if (enable) {
        result = [self enableAllInterrupts];
        if (result != IO_R_SUCCESS) {
            /* Failed to enable interrupts */
            [self setRunning:NO];
            return NO;
        }
    }

    /* Set running state */
    [self setRunning:enable];

    /* Set enabled flag (offset 0x199) */
    *((char *)self + 0x199) = 1;

    return YES;
}

/*
 * Cold initialization
 * Allocates shared memory for all 82596 structures and initializes the chip
 */
- (BOOL)coldInit
{
    extern unsigned int _IOMallocPage(unsigned int size, void **actualAddr, unsigned int *actualSize);
    extern id objc_getClass(const char *name);

    unsigned int pageAlignedAddr;
    void *actualMemAddr;
    unsigned int actualMemSize;
    unsigned int alignedSize;
    id Intel82596BufClass;
    const char *driverName;

    /* Allocate page-aligned memory (4KB = 0x1000 bytes) */
    pageAlignedAddr = _IOMallocPage(0x1000, &actualMemAddr, &actualMemSize);
    if (pageAlignedAddr == 0) {
        driverName = [self name];
        IOLog("%s: Failed to allocate shared memory\n", driverName);
        return NO;
    }

    /* Store actual allocation info at specific offsets */
    *((void **)self + 0x1ac/sizeof(void *)) = actualMemAddr;      /* Offset 0x1ac */
    *((unsigned int *)self + 0x1b0/sizeof(unsigned int)) = actualMemSize;  /* Offset 0x1b0 */

    /* Setup shared memory management */
    sharedMemPtr = (void *)pageAlignedAddr;
    sharedMemRemaining = 0x1000;

    /* Zero out shared memory */
    bzero(sharedMemPtr, 0x1000);

    /* Allocate 82596 control structures from shared memory */
    scp = [self _memAlloc:0xc];          /* SCP: 12 bytes */
    iscp = [self _memAlloc:0x8];         /* ISCP: 8 bytes */
    scbBase = [self _memAlloc:0x28];     /* SCB: 40 bytes */
    cmdList = [self _memAlloc:0x28];     /* Command list: 40 bytes */
    tcbList = [self _memAlloc:0x360];    /* TCB list: 8 * 108 = 864 bytes */
    rfdList = [self _memAlloc:0x400];    /* RFD list: 16 * 64 = 1024 bytes */

    /* Create buffer pool - 32 buffers of 1514 bytes each */
    Intel82596BufClass = objc_getClass("Intel82596Buf");
    if (Intel82596BufClass == nil) {
        driverName = [self name];
        IOLog("%s: Intel82596Buf class not found\n", driverName);
        return NO;
    }

    bufferPool = [[Intel82596BufClass alloc] initWithRequestedSize:0x5ea
                                                         actualSize:&alignedSize
                                                              count:0x20];
    if (bufferPool == nil) {
        driverName = [self name];
        IOLog("%s: Failed to create buffer pool\n", driverName);
        return NO;
    }

    /* Initialize RFD and TCB lists */
    if (![self _initRfdList]) {
        driverName = [self name];
        IOLog("%s: Failed to initialize RFD list\n", driverName);
        return NO;
    }

    if (![self _initTcbList]) {
        driverName = [self name];
        IOLog("%s: Failed to initialize TCB list\n", driverName);
        return NO;
    }

    /* Initialize 82596 chip */
    if (![self _init596]) {
        driverName = [self name];
        IOLog("%s: Failed to initialize 82596 chip\n", driverName);
        return NO;
    }

    return YES;
}

/*
 * Hardware initialization
 * Performs complete hardware initialization sequence
 */
- (BOOL)hwInit
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
- (BOOL)swInit
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
- (BOOL)config
{
    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short *cmd;
    unsigned char *configBytes;
    IOReturn result;
    vm_task_t task;
    const char *driverName;
    int timeout;

    /* Get command block from cmdList */
    cmd = (unsigned short *)cmdList;

    /* Wait for SCB to be ready */
    if (![self _waitScb]) {
        return NO;
    }

    /* Wait for command unit */
    if (![self _waitCu:100]) {
        return NO;
    }

    /* Setup configuration command */
    cmd[0] = 0;                    /* Status */
    cmd[1] = 0x8002;               /* Command: configure + EL (end of list) */
    *((unsigned int *)(cmd + 2)) = 0xffffffff;  /* Link address (end) */

    /* Get physical address of command block */
    task = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(task, (unsigned int)cmd, (unsigned int *)(cmd + 0x0e));
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid config command address\n", driverName);
        return NO;
    }

    /* Setup 14 configuration bytes */
    configBytes = (unsigned char *)(cmd + 4);  /* Config bytes start at offset 8 */

    configBytes[0] = 0x0e;   /* Byte count: 14 bytes */
    configBytes[1] = 0x48;   /* FIFO limit: 8, byte mode */
    configBytes[2] = 0x00;   /* Save bad frames: no */
    configBytes[3] = 0x00;   /* Address length: 6 bytes */
    configBytes[4] = 0x00;   /* Transmit: normal, no loopback */
    configBytes[5] = 0x60;   /* Linear priority: 6, backoff: 0 */
    configBytes[6] = 0x00;   /* Inter-frame spacing */
    configBytes[7] = 0xf2;   /* Slot time low */
    configBytes[8] = 0x00;   /* Slot time high, retry: 15 */
    configBytes[9] = 0x00;   /* Promiscuous: off, broadcast: on */
    configBytes[10] = 0x40;  /* Manchester/NRZ encoding */
    configBytes[11] = 0x00;  /* Linear priority mode */
    configBytes[12] = 0x00;  /* Inter-frame spacing */
    configBytes[13] = 0x00;  /* Reserved */

    /* Adjust config based on promiscuous mode (offset 0x204) */
    if (*((char *)self + 0x204) != 0) {
        configBytes[9] |= 0x01;  /* Enable promiscuous mode */
    }

    /* Issue CU START command with config command address */
    scb[1] = 0x100;  /* CUC_START */
    *((unsigned int *)(scb + 2)) = *((unsigned int *)(cmd + 0x0e));

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for command to complete (up to 2 seconds) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);
        if ((cmd[0] & 0x8000) != 0) {
            /* Command completed */
            if ((cmd[0] & 0x2000) != 0) {
                /* Configuration failed */
                driverName = [self name];
                IOLog("%s: config command failed\n", driverName);
                return NO;
            }
            return YES;
        }
    }

    /* Timeout */
    driverName = [self name];
    IOLog("%s: config command timed out\n", driverName);
    return NO;
}

/*
 * Individual Address setup
 * Sends IA Setup command to configure the chip's MAC address
 */
- (BOOL)iaSetup
{
    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short cmdBlock[8];  /* IA Setup command block */
    IOReturn result;
    vm_task_t task;
    const char *driverName;
    int timeout;

    /* Wait for SCB to be ready */
    if (![self _waitScb]) {
        return NO;
    }

    /* Wait for command unit */
    if (![self _waitCu:100]) {
        return NO;
    }

    /* Setup IA Setup command block */
    cmdBlock[0] = 0;                    /* Status */
    cmdBlock[1] = 0xc001;               /* Command: IA Setup + EL + Suspend */
    cmdBlock[2] = 0xffff;               /* Link address (end of list) */
    cmdBlock[3] = 0xffff;

    /* Copy MAC address from romAddress (offset 0x17c) */
    *((unsigned int *)(cmdBlock + 4)) = *((unsigned int *)self + 0x17c/sizeof(unsigned int));
    *((unsigned short *)(cmdBlock + 6)) = *((unsigned short *)self + 0x180/sizeof(unsigned short));

    /* Get physical address of command block */
    task = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(task, (unsigned int)cmdBlock,
                                   (unsigned int *)(scb + 2));
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid IA-setup command block address\n", driverName);
        return NO;
    }

    /* Issue CU START command */
    scb[1] = 0x100;  /* CUC_START */

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for command to complete (up to 2 seconds) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);
        if ((cmdBlock[0] & 0x8000) != 0) {
            /* Command completed */
            break;
        }
    }

    /* Clear interrupt latch */
    [self clearIrqLatch];

    if (timeout >= 2000) {
        /* Timeout */
        driverName = [self name];
        IOLog("%s: IA-setup command timed out\n", driverName);
        return NO;
    }

    /* Check status bit 13 (OK bit) */
    return ((cmdBlock[0] >> 13) & 1) ? YES : NO;
}

/*
 * Multicast setup
 * Sends MC Setup command to configure multicast address filtering
 */
- (BOOL)mcSetup
{
    extern unsigned int _IOMallocPage(unsigned int size, void **actualAddr, unsigned int *actualSize);
    extern unsigned int __page_size;

    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short *cmdBlock;
    void *actualMemAddr;
    unsigned int actualMemSize;
    IOReturn result;
    vm_task_t task;
    const char *driverName;
    int timeout;
    BOOL returnValue = YES;
    id mcQueue;
    void *mcEntry;
    void *nextEntry;
    int mcCount;
    unsigned short status;

    /* Clear multicast setup flag (offset 0x197) */
    *((char *)self + 0x197) = 0;

    /* Check if multicast mode is enabled (offset 0x195) */
    if (*((char *)self + 0x195) == 0) {
        return YES;  /* Multicast disabled, nothing to do */
    }

    /* Get multicast queue from superclass */
    mcQueue = [super multicastQueue];

    /* Wait for SCB to be ready */
    if (![self _waitScb]) {
        return NO;
    }

    /* Wait for command unit */
    if (![self _waitCu:100]) {
        return NO;
    }

    /* Check if multicast queue is empty */
    if (*((void **)mcQueue) == mcQueue) {
        /* Empty queue, nothing to setup */
        return YES;
    }

    /* Allocate page-aligned memory for MC Setup command */
    cmdBlock = (unsigned short *)_IOMallocPage(__page_size, &actualMemAddr, &actualMemSize);

    /* Setup MC Setup command block */
    cmdBlock[0] = 0;                    /* Status */
    cmdBlock[1] = 0xc003;               /* Command: MC Setup + EL + Suspend */
    cmdBlock[2] = 0xffff;               /* Link address (end of list) */
    cmdBlock[3] = 0xffff;

    /* Copy multicast addresses from queue */
    mcCount = 0;
    mcEntry = *((void **)mcQueue);  /* First entry */

    while (mcEntry != mcQueue) {
        /* Copy 6-byte MAC address (offset 0 in entry structure) */
        *((unsigned int *)(cmdBlock + (mcCount * 3) + 5)) = *((unsigned int *)mcEntry);
        *((unsigned short *)(cmdBlock + (mcCount * 3) + 7)) = *((unsigned short *)mcEntry + 2);

        mcCount++;
        mcEntry = *((void **)mcEntry + 2);  /* Next entry (offset 8) */
    }

    /* Set MC address count (in bytes) */
    cmdBlock[4] = (unsigned short)(mcCount * 6);

    /* Get physical address of command block */
    task = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(task, (unsigned int)cmdBlock,
                                   (unsigned int *)(scb + 2));
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid MC-setup command block address\n", driverName);
        IOFree(actualMemAddr, actualMemSize);
        return NO;
    }

    /* Issue CU START command */
    scb[1] = 0x100;  /* CUC_START */

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for command to complete (up to 2 seconds) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);
        if ((cmdBlock[0] & 0x8000) != 0) {
            /* Command completed */
            break;
        }
    }

    if (timeout >= 2000) {
        /* Timeout */
        driverName = [self name];
        IOLog("%s: MC-setup command timed out\n", driverName);
        returnValue = NO;
    } else {
        /* Save status for return value */
        status = cmdBlock[0];

        /* Clear interrupt latch */
        [self clearIrqLatch];

        /* Set multicast setup complete flag (offset 0x197) */
        *((char *)self + 0x197) = 1;

        /* Check status bit 13 (OK bit) */
        returnValue = ((status >> 13) & 1) ? YES : NO;
    }

    /* Free allocated memory */
    IOFree(actualMemAddr, actualMemSize);

    return returnValue;
}

/*
 * Interrupt handler
 * Called when hardware interrupt occurs
 */
- (void)interruptOccurred
{
    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short scbStatus;

    /* Read SCB status word */
    scbStatus = scb[0];

    /* Acknowledge interrupts */
    [self acknowledgeInterrupts:scbStatus];

    /* Clear hardware interrupt latch */
    [self clearIrqLatch];

    /* Check for receive interrupt (RNR or FR bits: 0x5000) */
    if ((scbStatus & 0x5000) != 0) {
        if (![self processRecInterrupt]) {
            /* Receive processing failed */
            return;
        }
    }

    /* Check for transmit complete (tcbTail has completed flag) */
    if ((tcbTail != NULL) && (*((short *)tcbTail) & 0x8000)) {
        [self processXmtInterrupt];
    }
}

/*
 * Timeout handler
 * Called when a timeout expires - checks if running and triggers interrupt processing
 */
- (void)timeoutOccurred
{
    /* Only process timeout if driver is running */
    if ([self isRunning]) {
        /* Trigger interrupt processing to handle timeout condition */
        [self interruptOccurred];
    }
}

/*
 * Acknowledge interrupts
 * Writes acknowledgment bits to SCB command field and waits for them to clear
 */
- (void)acknowledgeInterrupts:(unsigned int)intStatus
{
    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short ackBits;
    int timeout;
    const char *driverName;

    /* Wait for SCB command to be ready */
    if (![self _waitScb]) {
        return;
    }

    /* Extract acknowledgment bits (bits 12-15) and shift to command position */
    ackBits = (intStatus >> 8) & 0xf0;

    /* Write acknowledgment bits to SCB command field */
    scb[1] = ackBits;

    /* Send channel attention to process acknowledgment */
    [self sendChannelAttention];

    /* Wait for acknowledgment to complete (up to 65535 iterations) */
    for (timeout = 0; timeout < 0xffff; timeout++) {
        if ((scb[0] & 0xf000) == 0) {
            /* Acknowledgment cleared */
            return;
        }
    }

    /* Timeout - log error and schedule reset */
    driverName = [self name];
    IOLog("%s: acknowledgeInterrupts timeout\n", driverName);
    [self _scheduleReset];
}

/*
 * Disable all interrupts
 */
- (void)disableAllInterrupts
{
    IOLog("Intel82596: disableAllInterrupts - stub\n");
}

/*
 * Reserve debugger lock
 */
- (void)reserveDebuggerLock
{
    /* Stub - would acquire lock for debugger access */
}

/*
 * Release debugger lock
 */
- (void)releaseDebuggerLock
{
    /* Stub - would release lock for debugger access */
}

/*
 * Allocate network buffer
 */
- (void *)allocateNetbuf
{
    IOLog("Intel82596: allocateNetbuf - stub\n");
    return NULL;
}

/*
 * Transmit a packet
 * Main entry point for network stack to send packets
 */
- (void)transmit:(netbuf_t)packet
{
    int queueCount;

    /* Check if driver is running */
    if (![self isRunning]) {
        /* Driver not running, discard packet */
        _nb_free(packet);
        return;
    }

    /* Service any pending transmits from queue */
    [self serviceTransmitQueue];

    /* Check if transmit queue is empty and we have free TCBs */
    queueCount = [transmitQueue count];

    if ((queueCount == 0) && (tcbHead != NULL)) {
        /* Queue empty and TCBs available - transmit directly */
        [self _transmitPacket:packet];
    } else {
        /* Queue has packets or no free TCBs - enqueue for later */
        [transmitQueue enqueue:packet];
    }
}

/*
 * Send packet (synchronous)
 * Used for debugger and special cases - sends packet directly
 */
- (void)sendPacket:(void *)pkt length:(unsigned int)len
{
    extern void _bcopy(void *src, void *dst, unsigned int len);
    extern void _bzero(void *dst, unsigned int len);

    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short *tbd;
    BOOL needsAck = NO;
    int timeout;

    /* Wait for SCB to be ready */
    if (![self _waitScb]) {
        return;
    }

    /* Wait for command unit (up to 1 second) */
    if (![self _waitCu:1000]) {
        return;
    }

    /* Check if interrupts need acknowledgment (CNA or CX bits: 0xa000) */
    if ((scb[0] & 0xa000) != 0) {
        /* Acknowledge interrupts */
        scb[1] = scb[0] & 0xa000;
        [self sendChannelAttention];

        /* Wait for acknowledgment to complete */
        for (timeout = 0; timeout < 2000; timeout++) {
            IODelay(1);
            if (((scb[0] >> 8) & 0xf0) == 0) {
                break;
            }
        }

        needsAck = YES;
    }

    /* Get RBD pointer (offset 0x1d8) */
    tbd = *(unsigned short **)((char *)self + 0x1d8);

    /* Setup transmit command block (simplified on-chip TCB) */
    tbd[0] = 0;                    /* Status */
    tbd[1] = 0xa00c;               /* Command: transmit + EL + suspend + interrupt */
    *((unsigned int *)(tbd + 2)) = 0xffffffff;  /* Link address (end) */
    *((unsigned int *)(tbd + 0x18/2)) = 0;      /* Reserved */

    /* Setup TBD pointer */
    *((unsigned int *)(tbd + 4)) = *((unsigned int *)tbd + 0x2c/sizeof(unsigned int));

    tbd[6] = 0;  /* Tx count */
    tbd[7] = 0;

    /* Validate and adjust packet length */
    if (len > 0x5ea) {
        len = 0x5ea;  /* Max Ethernet frame size */
    }
    if (len < 0x40) {
        len = 0x40;   /* Min Ethernet frame size (64 bytes) */
    }

    /* Copy packet data to on-chip buffer (offset 0x1dc) */
    _bcopy(pkt, *(void **)((char *)self + 0x1dc), len);

    /* Setup TBD */
    *((unsigned int *)(tbd + 0x28/2)) = *((unsigned int *)self + 0x1e0/sizeof(unsigned int));
    tbd[0x20/2] = (unsigned short)len | 0x8000;  /* Count with EOF */
    tbd[0x22/2] = 0;
    *((unsigned int *)(tbd + 0x24/2)) = 0xffffffff;  /* Next TBD (end) */

    /* Zero out 8 bytes at offset 0x10 */
    _bzero((void *)(tbd + 0x10/2), 8);

    /* Issue CU START command */
    scb[1] = 0x100;  /* CUC_START */
    *((unsigned int *)(scb + 2)) = *((unsigned int *)tbd + 0x1c/sizeof(unsigned int));

    /* Send channel attention */
    [self sendChannelAttention];

    /* If we didn't ack before, check again after command completes */
    if (!needsAck) {
        if (![self _waitScb]) {
            return;
        }

        if (![self _waitCu:1000]) {
            return;
        }

        /* Check if interrupts need acknowledgment */
        if ((scb[0] & 0xa000) != 0) {
            /* Acknowledge interrupts */
            scb[1] = scb[0] & 0xa000;
            [self sendChannelAttention];

            /* Wait for acknowledgment to complete */
            for (timeout = 0; timeout < 2000; timeout++) {
                IODelay(1);
                if (((scb[0] >> 8) & 0xf0) == 0) {
                    return;
                }
            }
        }
    }
}

/*
 * Receive packet (synchronous polling)
 * Used for debugger and special cases - waits for packet to arrive
 */
- (void)receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout
{
    extern void _bcopy(void *src, void *dst, unsigned int len);

    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short *rfd;
    unsigned short frameLength;
    void *netbuf;
    void *packetData;
    int timeRemaining;
    IOReturn result;
    vm_task_t task;

    /* Initialize output length to 0 */
    *len = 0;

    /* Convert timeout from milliseconds to microseconds */
    timeRemaining = timeout * 1000;

    /* Wait for RFD to complete, polling with delays */
    while ((*((short *)rfdHead) & 0x8000) == 0) {  /* Not complete */
        /* Check if timeout expired */
        if (timeRemaining <= 0) {
            /* Check if RU is ready/suspended */
            if ((scb[0] & 0xf0) == 0x40) {
                /* RU is ready, just no packet yet */
                return;
            }
            /* RU not ready, fall through to restart logic */
            goto restart_ru;
        }

        /* Delay 50 microseconds (0x32) */
        IODelay(50);
        timeRemaining -= 50;
    }

    /* Check for RNR (Receive Not Ready) interrupt (bit 14 = 0x4000) */
    if ((scb[0] & 0x4000) != 0) {
        /* Acknowledge RNR interrupt */
        if (![self _waitScb]) {
            return;
        }

        if (![self _waitCu:100]) {
            return;
        }

        /* Write acknowledge command */
        scb[1] = 0x4000;  /* Acknowledge RNR */
        [self sendChannelAttention];

        /* Wait for acknowledgment to complete */
        for (int i = 0; i < 2000; i++) {
            IODelay(1000);
            if (((scb[0] >> 8) & 0xf0) == 0) {
                break;
            }
        }
    }

    /* Get RFD pointer */
    rfd = (unsigned short *)rfdHead;

    /* Check if RBD has data (bit 15 of count at offset 0x28) */
    if ((rfd[0x28/2] & 0x8000) == 0) {
        /* No data in RBD, need to restart RU */
        goto restart_ru;
    }

    /* Check status bit 13 (OK bit at 0x2000) */
    if ((rfd[0] & 0x2000) != 0) {
        /* Frame received successfully */

        /* Get frame length (bits 0-13 of count field at offset 0x14) */
        frameLength = rfd[0x14] & 0x3fff;
        *len = frameLength;

        /* Get netbuf pointer from RFD (offset 0x38) */
        netbuf = *(void **)((char *)rfd + 0x38);

        /* Map netbuf to get data pointer */
        packetData = _nb_map(netbuf, NULL);

        /* Copy packet data to output buffer */
        _bcopy(packetData, pkt, frameLength);

        /* Reset RFD for reuse */
        /* Update link physical address (offset 0x04) */
        *(unsigned int *)((char *)rfd + 0x04) =
            *(unsigned int *)(*(void **)((char *)rfd + 0x20) + 0x24);

        /* Remap netbuf and update physical address */
        packetData = _nb_map(netbuf, (unsigned int *)((char *)rfd + 0x30));
        task = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(task, (unsigned int)packetData,
                                      (unsigned int *)((char *)rfd + 0x30));
        if (result != IO_R_SUCCESS) {
            IOPanic("Invalid net buffer address");
        }

        /* Reset status and command fields */
        rfd[0] = 0;                    /* Status */
        rfd[1] = 0x8008;               /* Command: suspend + EL */
        rfd[4] = 0xffff;               /* RBD offset (unused) */
        rfd[5] = 0xffff;
        rfd[6] = 0;                    /* Actual count */
        rfd[7] = 0;
        rfd[0x28/2] = 0;               /* RBD count */
        rfd[0x2a/2] = 0;
        rfd[0x36/2] = 0;
        rfd[0x34/2] = 0x85ea;          /* Size field: 0x8000 | 0x5ea */

        /* Clear end-of-list marker from next RFD's size field */
        *((unsigned short *)((char *)rfdTail + 0x20) + 0x34/2) &= 0x7fff;

        /* Clear end-of-list marker from current rfdTail */
        *((unsigned short *)rfdTail + 1) &= 0x7fff;

        /* Update rfdTail and rfdHead */
        rfdTail = *(void **)((char *)rfdTail + 0x20);
        rfdHead = *(void **)((char *)rfdHead + 0x20);

        return;
    }

restart_ru:
    /* RU needs to be restarted */
    [self _abortReceiveUnit];
    [self _initRfdList];
    [self _startReceiveUnit];
}

/*
 * Service transmit queue
 * Dequeues and transmits pending packets
 */
- (void)serviceTransmitQueue
{
    void *packet;

    /* Continue while there are free TCBs and queued packets */
    while (tcbHead != NULL) {
        /* Try to dequeue a packet from transmit queue */
        packet = [transmitQueue dequeue];

        if (packet == NULL) {
            /* No more packets to transmit */
            break;
        }

        /* Transmit the packet */
        [self _transmitPacket:packet];
    }
}

/*
 * Process receive interrupt
 * Handles received packets from the RFD list
 */
- (BOOL)processRecInterrupt
{
    extern void _nb_free(void *netbuf);
    extern void *_nb_map(void *netbuf, unsigned int *physAddr);
    extern unsigned int _nb_size(void *netbuf);
    extern void _nb_shrink_bot(void *netbuf, unsigned int amount);
    extern void _bcopy(void *src, void *dst, unsigned int len);

    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short *rfd;
    unsigned short rfdStatus;
    unsigned short frameLength;
    void *netbuf;
    void *newNetbuf;
    void *packetData;
    void *newPacketData;
    unsigned int packetSize;
    const char *driverName;
    IOReturn result;
    vm_task_t task;
    BOOL isUnwanted;

    /* Reserve debugger lock */
    [self reserveDebuggerLock];

    /* Process all completed RFDs */
    rfd = (unsigned short *)rfdHead;

    while ((rfd != NULL) && (*rfd & 0x8000)) {  /* Status bit 15: complete */
        /* Check for oversize frame (bit 15 of count field at offset 0x14) */
        if ((rfd[0x14] & 0x8000) == 0) {
            /* Frame is not oversize - normal processing */

            /* Update rfdHead to next RFD (offset 0x20) */
            rfdHead = *(void **)((char *)rfd + 0x20);

            /* Check status bit 13 (OK bit at 0x2000) */
            if ((*rfd & 0x2000) == 0) {
                /* Frame received with errors */
                [netif incrementInputErrors];
            } else {
                /* Frame received successfully */

                /* Get netbuf pointer from RFD (offset 0x38) */
                netbuf = *(void **)((char *)rfd + 0x38);

                /* Get frame length (bits 0-13 of count field) */
                frameLength = rfd[0x14] & 0x3fff;

                /* Release debugger lock during processing */
                [self releaseDebuggerLock];

                /* Check minimum packet size (60 bytes = 0x3c) */
                if (frameLength >= 0x3c) {
                    /* Check for unwanted multicast packets */
                    isUnwanted = NO;

                    if ((*((char *)self + 0x194) != 1) &&    /* Not promiscuous */
                        (*((char *)self + 0x197) != 0) &&     /* MC setup complete */
                        ((*rfd & 2) != 0)) {                  /* Multicast frame */

                        packetData = _nb_map(netbuf, NULL);
                        isUnwanted = [super isUnwantedMulticastPacket:packetData];
                    }

                    if (!isUnwanted) {
                        /* Try to allocate replacement netbuf */
                        newNetbuf = [self _recAllocateNetbuf];

                        if (newNetbuf == NULL) {
                            /* No buffer available, allocate from general pool */
                            newNetbuf = [self allocateNetbuf];

                            if (newNetbuf != NULL) {
                                /* Copy packet data to new buffer */
                                newPacketData = _nb_map(newNetbuf, NULL);
                                packetData = _nb_map(netbuf, NULL);
                                _bcopy(packetData, newPacketData, frameLength);

                                /* Shrink buffer to actual packet size */
                                packetSize = _nb_size(newNetbuf);
                                _nb_shrink_bot(newNetbuf, packetSize - frameLength);

                                /* Handle packet */
                                [netif handleInputPacket:newNetbuf extra:0];
                            }
                        } else {
                            /* Replacement buffer allocated successfully */

                            /* Shrink original buffer to actual packet size */
                            packetSize = _nb_size(netbuf);
                            if (frameLength < packetSize) {
                                _nb_shrink_bot(netbuf, packetSize - frameLength);
                            }

                            /* Handle packet */
                            [netif handleInputPacket:netbuf extra:0];

                            /* Install replacement buffer in RFD */
                            *(void **)((char *)rfd + 0x38) = newNetbuf;

                            /* Map new netbuf and get physical address */
                            packetData = _nb_map(newNetbuf, (unsigned int *)((char *)rfd + 0x30));
                            task = IOVmTaskSelf();
                            result = IOPhysicalFromVirtual(task, (unsigned int)packetData,
                                                          (unsigned int *)((char *)rfd + 0x30));
                            if (result != IO_R_SUCCESS) {
                                IOPanic("Invalid net buffer address");
                            }
                        }
                    }
                }

                /* Re-acquire debugger lock */
                [self reserveDebuggerLock];
            }

            /* Reset RFD for reuse */
            /* Update link physical address (offset 0x04) */
            *(unsigned int *)((char *)rfd + 0x04) =
                *(unsigned int *)(*(void **)((char *)rfd + 0x20) + 0x24);

            /* Reset status and command fields */
            rfd[0] = 0;                    /* Status */
            rfd[1] = 0x8008;               /* Command: suspend + EL */
            rfd[4] = 0xffff;               /* RBD offset (unused) */
            rfd[5] = 0xffff;
            rfd[6] = 0;                    /* Actual count */
            rfd[7] = 0;
            rfd[0x14] = 0;                 /* RBD count */
            rfd[0x15] = 0;
            rfd[0x1a] = 0x85ea;            /* Size field: 0x8000 | 0x5ea */
            rfd[0x1b] = 0;

            /* Clear end-of-list marker from next RFD's size field */
            *((unsigned short *)((char *)rfdTail + 0x20) + 0x34) &= 0x7fff;

            /* Clear end-of-list marker from current rfdTail */
            *((unsigned short *)rfdTail + 1) &= 0x7fff;

            /* Update rfdTail */
            rfdTail = *(void **)((char *)rfdTail + 0x20);

        } else {
            /* Oversize frame detected */
            driverName = [self name];
            IOLog("%s: Oversize frame in RFD %ld\n", driverName, 0L);

            [netif incrementInputErrors];

            /* Abort and restart receive unit */
            [self _abortReceiveUnit];
            [self _initRfdList];

            if (![self _startReceiveUnit]) {
                [self _scheduleReset];
                [self releaseDebuggerLock];
                return NO;
            }

            [self releaseDebuggerLock];
            return YES;
        }

        /* Get next RFD */
        rfd = (unsigned short *)rfdHead;
    }

    /* Check RU status and restart if needed */
    if ((scb[0] & 0xf0) != 0x40) {  /* Not ready/suspended */
        /* Check if RU is out of resources (0xc0) */
        if ((scb[0] & 0xf0) == 0xc0) {
            [self _abortReceiveUnit];
        }

        /* Reinitialize and restart RU */
        [self _initRfdList];

        if (![self _startReceiveUnit]) {
            [self _scheduleReset];
            [self releaseDebuggerLock];
            return NO;
        }
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];

    return YES;
}

/*
 * Process transmit interrupt
 * Handles completed transmit command blocks
 */
- (BOOL)processXmtInterrupt
{
    unsigned short *tcb;
    void *nextTcb;
    unsigned short tcbStatus;
    int collisionCount;
    const char *driverName;

    /* Process all completed TCBs */
    while (YES) {
        /* Check if tcbTail is NULL or not completed */
        if ((tcbTail == NULL) || ((*((short *)tcbTail) & 0x8000) == 0)) {
            /* No more completed TCBs, service transmit queue */
            [self serviceTransmitQueue];
            return YES;
        }

        /* Get TCB pointer */
        tcb = (unsigned short *)tcbTail;

        /* Clear any pending timeout */
        [self clearTimeout];

        /* Get next TCB in chain (offset 0x18) */
        nextTcb = *(void **)((char *)tcb + 0x18);
        tcbTail = nextTcb;

        /* Check if we've processed all active TCBs and have pending ones */
        if ((nextTcb == NULL) && (tcbFree != NULL)) {
            /* Set end-of-list bit in last pending TCB (tcbReserved) */
            *((unsigned short *)tcbReserved + 1) |= 0x8000;

            /* Move pending queue to active */
            tcbTail = tcbFree;
            tcbFree = NULL;

            /* Start command unit with new queue */
            if (![self _startCommandUnit]) {
                return NO;
            }

            /* Set timeout for transmission (500ms) */
            [self setRelativeTimeout:500];
        }

        /* Check for erratum 15 (link address = 0x4000) */
        if (tcb[2] == 0x4000) {
            driverName = [self name];
            IOLog("%s: erratum 15 in tcb link addr!\n", driverName);
            /* This is a serious hardware bug, trigger debugger */
            asm("int $3");
            return NO;
        }

        /* Check status bit 13 (OK bit at 0x2000) */
        tcbStatus = tcb[0];
        if ((tcbStatus & 0x2000) == 0) {
            /* Transmission failed */
            [netif incrementOutputErrors];
        } else {
            /* Transmission successful */
            [netif incrementOutputPackets];
        }

        /* Count collisions from status bits 0-3 */
        collisionCount = tcbStatus & 0xf;
        if (collisionCount != 0) {
            for (int i = 0; i < collisionCount; i++) {
                [netif incrementCollisions];
            }
        }

        /* Check for max collisions (bit 5 = 0x20) */
        if ((tcbStatus & 0x20) != 0) {
            /* Maximum collisions (16) */
            for (int i = 0; i < 0x10; i++) {
                [netif incrementCollisions];
            }
        }

        /* Check for heartbeat (bit 11 = 0x800) */
        if ((tcbStatus & 0x800) != 0) {
            /* SQE test signal (heartbeat) */
            [netif incrementCollisions];
        }

        /* Free network buffer if present (offset 0x68) */
        if (*(void **)((char *)tcb + 0x68) != NULL) {
            _nb_free(*(void **)((char *)tcb + 0x68));
            *(void **)((char *)tcb + 0x68) = NULL;
        }

        /* Add TCB back to free list (tcbHead) */
        *(void **)((char *)tcb + 0x18) = tcbHead;  /* Link to current head */
        tcbHead = tcb;

        /* Check for DMA underrun (bits 9-10 = 0x600) */
        if ((tcbStatus & 0x600) != 0) {
            /* DMA underrun or other serious error, schedule reset */
            [self _scheduleReset];
            return NO;
        }
    }

    /* Unreachable */
    return YES;
}

/*
 * Enable promiscuous mode
 * Sets promiscuous mode flag and reconfigures chip
 */
- (BOOL)enablePromiscuousMode
{
    /* Set promiscuous mode flag if not already set (offset 0x194) */
    if (*((char *)self + 0x194) == 0) {
        *((char *)self + 0x194) = 1;
    }

    /* Reconfigure chip with updated promiscuous mode setting */
    return [self config];
}

/*
 * Disable promiscuous mode
 * Clears promiscuous mode flag and reconfigures chip
 */
- (void)disablePromiscuousMode
{
    /* Clear promiscuous mode flag if set (offset 0x194) */
    if (*((char *)self + 0x194) != 0) {
        *((char *)self + 0x194) = 0;
    }

    /* Reconfigure chip with updated promiscuous mode setting */
    [self config];
}

/*
 * Enable multicast mode
 * Sets multicast mode flag
 */
- (BOOL)enableMulticastMode
{
    /* Set multicast mode flag (offset 0x195) */
    *((char *)self + 0x195) = 1;

    return YES;
}

/*
 * Disable multicast mode
 * Clears multicast mode flag and reconfigures chip if it was previously enabled
 */
- (void)disableMulticastMode
{
    char wasEnabled;
    BOOL result;
    const char *driverName;

    /* Get current multicast mode state (offset 0x195) */
    wasEnabled = *((char *)self + 0x195);

    /* Clear multicast mode flag */
    *((char *)self + 0x195) = 0;

    /* If multicast was enabled, reconfigure the chip */
    if (wasEnabled != 0) {
        result = [self mcSetup];
        if (!result) {
            driverName = [self name];
            IOLog("%s: disable multicast mode failed\n", driverName);
        }
    }
}

/*
 * Add multicast address
 * Sets multicast mode flag and calls mcSetup to configure the chip
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    /* Set multicast mode flag (at offset 0x205) */
    *((char *)self + 0x205) = 1;

    /* Call multicast setup to reconfigure chip */
    [self mcSetup];
}

/*
 * Remove multicast address
 * Reconfigures multicast filtering after address is removed from queue
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;
    const char *driverName;

    /* Call mcSetup to reconfigure with updated multicast list */
    result = [self mcSetup];

    if (!result) {
        driverName = [self name];
        IOLog("%s: remove multicast address failed\n", driverName);
    }
}

/*
 * Clear interrupt latch - subclass override
 * Base implementation is empty - hardware-specific subclasses must override
 */
- (void)clearIrqLatch
{
    /* Empty base implementation - subclasses override for hardware-specific IRQ clearing */
}

/*
 * Send channel attention - subclass override
 * Base implementation is empty - hardware-specific subclasses must override
 */
- (void)sendChannelAttention
{
    /* Empty base implementation - subclasses override for hardware-specific CA signaling */
}

/*
 * Send port command - subclass override
 * Base implementation is empty - hardware-specific subclasses must override
 */
- (void)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg
{
    /* Empty base implementation - subclasses override for hardware-specific PORT commands */
}

/*
 * Set I/O base address
 * Stores base address at offset 0x174
 */
- (void)setIOBase:(unsigned int)base
{
    /* Set IO base address (offset 0x174) */
    *((unsigned short *)self + 0x174/sizeof(unsigned short)) = (unsigned short)base;
}

/*
 * Set throttle timers
 * Configures bus throttle timers to prevent DMA overruns
 */
- (BOOL)setThrottleTimers
{
    unsigned short *scb = (unsigned short *)scbBase;
    const char *driverName;
    int timeout;

    /* Wait for SCB to be ready */
    if (![self _waitScb]) {
        return NO;
    }

    /* Wait for command unit */
    if (![self _waitCu:100]) {
        return NO;
    }

    /* Clear bit 3 in SCB status (bit 0x0008) */
    scb[0] &= 0xfff7;

    /* Set throttle timer values in SCB */
    scb[0x24/2] = 2;      /* On-time: 2 bus cycles */
    scb[0x26/2] = 0x7d;   /* Off-time: 125 bus cycles */

    /* Issue Load Dump Area command (0x600) */
    scb[1] = 0x600;

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for command to complete (up to 2 seconds) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);
        if ((scb[0] & 0x0008) != 0) {
            /* Command completed successfully */
            return YES;
        }
    }

    /* Timeout */
    driverName = [self name];
    IOLog("%s: set throttle timers timed out\n", driverName);
    return NO;
}

/*
 * Clear timeout
 */
- (void)clearTimeout
{
    IOLog("Intel82596: clearTimeout - stub\n");
}

/*
 * Set relative timeout
 */
- (void)setRelativeTimeout:(unsigned int)msec
{
    IOLog("Intel82596: setRelativeTimeout:%d - stub\n", msec);
}

/*
 * Enable all interrupts
 */
- (IOReturn)enableAllInterrupts
{
    IOLog("Intel82596: enableAllInterrupts - stub\n");
    return IO_R_SUCCESS;
}

/*
 * Set running state
 */
- (void)setRunning:(BOOL)running
{
    IOLog("Intel82596: setRunning:%d - stub\n", running);
}

/*
 * Check if driver is running
 */
- (BOOL)isRunning
{
    IOLog("Intel82596: isRunning - stub\n");
    return NO;
}

/*
 * Get power management state
 * Power management not supported on this driver
 */
- (IOReturn)getPowerManagement:(IOPMPowerManagementState *)state
{
    return IO_R_UNSUPPORTED;
}

/*
 * Set power management state
 * Power management not supported on this driver
 */
- (IOReturn)setPowerManagement:(IOPMPowerManagementState)state
{
    return IO_R_UNSUPPORTED;
}

/*
 * Get power state
 * Power management not supported on this driver
 */
- (IOReturn)getPowerState:(IOPMPowerState *)state
{
    return IO_R_UNSUPPORTED;
}

/*
 * Set power state
 * Handles sleep/wake power state transitions
 */
- (IOReturn)setPowerState:(IOPMPowerState)state
{
    /* Check if entering sleep state (state 3) */
    if (state == 3) {
        /* Prepare for sleep */

        /* Abort receive unit */
        [self _abortReceiveUnit];

        /* Clear any pending timeout */
        [self clearTimeout];

        /* Send PORT RESET command (0, 0) */
        [self sendPortCommand:0 with:0];

        return IO_R_SUCCESS;
    }

    /* All other power states not supported */
    return IO_R_UNSUPPORTED;
}

@end

/*
 * Private methods implementation
 */
@implementation Intel82596(Private)

/*
 * Initialize 82596 chip
 */
- (BOOL)_init596
{
    IOReturn result;
    vm_task_t task;
    unsigned int scpPhysAddr;
    const char *driverName;
    int timeout;

    /* Zero out SCP (12 bytes) */
    bzero(scp, 0xc);

    /* Set SCP offset field (word at offset 2) */
    *((unsigned short *)scp + 1) = 0x54;

    /* Get physical address of ISCP base (at scp + 8) */
    task = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(task, (unsigned int)iscp, (unsigned int *)((char *)scp + 8));
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid ISCP address\n", driverName);
        return NO;
    }

    /* Zero out ISCP (8 bytes) */
    bzero(iscp, 8);

    /* Set ISCP busy flag */
    *((unsigned char *)iscp) = 1;

    /* Get physical address of SCB and store in ISCP (at iscp + 4) */
    task = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(task, (unsigned int)scbBase, (unsigned int *)((char *)iscp + 4));
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid SCB address\n", driverName);
        return NO;
    }

    /* Zero out SCB (40 bytes / 0x28) */
    bzero(scbBase, 0x28);

    /* Get physical address of SCP */
    task = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(task, (unsigned int)scp, &scpPhysAddr);
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid SCP address\n", driverName);
        return NO;
    }

    /* Send PORT command (command 2) with SCP address */
    [self sendPortCommand:2 with:scpPhysAddr];

    /* Delay for chip initialization */
    IODelay(1000);

    /* Send channel attention to start initialization */
    [self sendChannelAttention];

    /* Wait for ISCP busy flag to clear (up to 2 seconds) */
    timeout = 0;
    while (timeout < 2000) {
        IODelay(1000);
        if (*((unsigned char *)iscp) == 0) {
            /* Initialization successful */
            return YES;
        }
        timeout++;
    }

    /* Timeout */
    driverName = [self name];
    IOLog("%s: 82596 initialization timed out\n", driverName);
    return NO;
}

/*
 * Reset and self-test the 82596 chip
 */
- (BOOL)_resetAndSelfTest
{
    IOReturn result;
    vm_task_t task;
    unsigned int selfTestPhysAddr;
    const char *driverName;
    int timeout;
    unsigned int *selfTestArea;
    unsigned int signature;
    unsigned short errorFlags;

    /* Send PORT RESET command (command 0, address 0) */
    [self sendPortCommand:0 with:0];

    /* Get physical address of self-test area (cmdList) */
    task = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(task, (unsigned int)cmdList, &selfTestPhysAddr);
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid self test area address\n", driverName);
        return NO;
    }

    /* Setup self-test area */
    selfTestArea = (unsigned int *)cmdList;
    selfTestArea[0] = 0xffffffff;  /* Signature - will be overwritten by chip */
    selfTestArea[1] = 0xffffffff;  /* Results - will be overwritten by chip */

    /* Send PORT SELF-TEST command (command 1) with self-test area address */
    [self sendPortCommand:1 with:selfTestPhysAddr];

    /* Wait for self-test to complete (up to 2 seconds) */
    timeout = 0;
    while (timeout < 2000) {
        IODelay(1000);
        if (selfTestArea[0] != 0xffffffff) {
            /* Self-test completed */
            break;
        }
        timeout++;
    }

    if (timeout >= 2000) {
        driverName = [self name];
        IOLog("%s: Self test timed out\n", driverName);
        return NO;
    }

    /* Check results */
    errorFlags = (unsigned short)selfTestArea[1];

    if (errorFlags == 0) {
        /* Self-test passed - check chip signature */
        signature = selfTestArea[0];

        switch (signature) {
            case 0x53946c33:
                /* 82596CA stepping */
                chipRevision = 0;
                return YES;

            case 0xdce4a0c5:
                /* 82596DX stepping */
                chipRevision = 1;
                return YES;

            case 0x320925ae:
                /* 82596SX stepping */
                chipRevision = 2;
                return YES;

            default:
                driverName = [self name];
                IOLog("%s: Unknown chip revision\n", driverName);
                chipRevision = 0;
                return YES;  /* Continue anyway */
        }
    }

    /* Self-test failed - report errors */
    driverName = [self name];

    if (errorFlags & 0x04) {
        IOLog("%s: Self test reports invalid ROM contents\n", driverName);
    }
    if (errorFlags & 0x08) {
        IOLog("%s: Self test reports internal register failure\n", driverName);
    }
    if (errorFlags & 0x10) {
        IOLog("%s: Self test reports bus throttle timer failure\n", driverName);
    }
    if (errorFlags & 0x20) {
        IOLog("%s: Self test reports serial subsystem failure\n", driverName);
    }
    if (((unsigned char *)&selfTestArea[1])[1] & 0x10) {
        IOLog("%s: Self test failed\n", driverName);
    }

    return NO;
}

/*
 * Schedule reset - cleanup transmit queue and schedule timeout
 */
- (void)_scheduleReset
{
    void *packet;

    /* Abort receive unit */
    [self _abortReceiveUnit];

    /* Clear any pending timeout */
    [self clearTimeout];

    /* Drain transmit queue and free all packets */
    while (YES) {
        packet = [transmitQueue dequeue];
        if (packet == NULL) {
            break;
        }
        _nb_free(packet);
    }

    /* Schedule timeout for reset - 1184ms (0x4a0), flags = 4 */
    _ns_timeout(0x4a0, self, 0, 0, 4);
}

/*
 * Wait for SCB command register to clear
 * Polls up to 65535 times for SCB command field to become 0
 */
- (BOOL)_waitScb
{
    unsigned short *scb = (unsigned short *)scbBase;
    int timeout;
    const char *driverName;

    /* Poll SCB command field (offset 2) for it to clear */
    for (timeout = 0; timeout < 0xffff; timeout++) {
        if (scb[1] == 0) {
            /* SCB command cleared */
            return YES;
        }
    }

    /* Timeout - schedule reset */
    driverName = [self name];
    IOLog("%s: timeout waiting for scb command to clear\n", driverName);
    [self _scheduleReset];
    return NO;
}

/*
 * Wait for command unit to become inactive
 * timeout - timeout in milliseconds
 */
- (BOOL)_waitCu:(unsigned int)timeout
{
    unsigned short *scb = (unsigned short *)scbBase;
    unsigned int elapsed;
    unsigned int maxIterations;
    const char *driverName;

    /* Calculate max iterations (timeout * 1000 microseconds, delay 1us each) */
    maxIterations = timeout * 1000;

    /* Check if timeout is valid */
    if ((maxIterations & 0x1fffffff) == 0) {
        /* Invalid timeout */
        return NO;
    }

    /* Poll for CU status to not be active (0x200) */
    for (elapsed = 0; elapsed < maxIterations; elapsed++) {
        if ((scb[0] & 0x700) != 0x200) {
            /* Command unit is not active */
            return YES;
        }
        IODelay(1);
    }

    /* Timeout - schedule reset */
    driverName = [self name];
    IOLog("%s: timeout waiting for command unit to become inactive\n", driverName);
    [self _scheduleReset];
    return NO;
}

/*
 * Start command unit
 */
- (BOOL)_startCommandUnit
{
    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short scbStatus;
    const char *driverName;
    unsigned short *tcbFlags;
    unsigned int *tcbPhysAddr;

    /* Wait for SCB to be ready */
    if (![self _waitScb]) {
        driverName = [self name];
        IOLog("%s: Cannot start command unit - SCB not clear\n", driverName);
        return NO;
    }

    /* Check if command unit is active (status bit 0x200) */
    scbStatus = scb[0] & 0x700;
    if (scbStatus == 0x200) {
        /* CU is active, wait for it to complete */
        if (![self _waitCu:100]) {
            driverName = [self name];
            IOLog("%s: Cannot start command unit - still active\n", driverName);
            return NO;
        }
    }

    /* Check if we have a command to execute */
    if (tcbTail == NULL) {
        driverName = [self name];
        IOLog("%s: Attempt to start command unit with null activeTcbHead virtual"
              "or physical address\n", driverName);
        return NO;
    }

    /* Get physical address of TCB */
    tcbPhysAddr = (unsigned int *)((char *)tcbTail + 0x1c);
    if (*tcbPhysAddr == 0) {
        driverName = [self name];
        IOLog("%s: Attempt to start command unit with null activeTcbHead virtual"
              "or physical address\n", driverName);
        return NO;
    }

    /* Set suspend bit in TCB command field */
    tcbFlags = (unsigned short *)tcbTail;
    *tcbFlags |= 0x4000;

    /* Issue CU START command */
    scb[1] = 0x100;  /* CUC_START */
    *((unsigned int *)(scb + 2)) = *tcbPhysAddr;

    /* Send channel attention to start command unit */
    [self sendChannelAttention];

    return YES;
}

/*
 * Start receive unit
 */
- (BOOL)_startReceiveUnit
{
    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short ruStatus;
    const char *driverName;
    int timeout;
    char *rfdHead_p;
    unsigned int *rfdPhysAddr;
    unsigned int *rbdPhysAddr;

    /* Check if RU is already suspended (status 0x40) */
    ruStatus = scb[0] & 0xf0;
    if (ruStatus == 0x40) {
        /* Already in correct state */
        return YES;
    }

    /* Wait for SCB to be ready */
    if (![self _waitScb]) {
        return NO;
    }

    /* Wait for command unit */
    if (![self _waitCu:100]) {
        return NO;
    }

    /* Validate RFD head pointer */
    if (rfdHead == NULL) {
        driverName = [self name];
        IOLog("%s: attempt to start receive unit with null virtual or physical RFD/RBD address\n",
              driverName);
        return NO;
    }

    rfdHead_p = (char *)rfdHead;

    /* Validate RFD physical address (at offset 0x24) */
    rfdPhysAddr = (unsigned int *)(rfdHead_p + 0x24);
    if (*rfdPhysAddr == 0) {
        driverName = [self name];
        IOLog("%s: attempt to start receive unit with null virtual or physical RFD/RBD address\n",
              driverName);
        return NO;
    }

    /* Validate RBD physical address (at offset 0x3c) */
    rbdPhysAddr = (unsigned int *)(rfdHead_p + 0x3c);
    if (*rbdPhysAddr == 0) {
        driverName = [self name];
        IOLog("%s: attempt to start receive unit with null virtual or physical RFD/RBD address\n",
              driverName);
        return NO;
    }

    /* Setup RFD to point to RBD (store RBD phys addr at RFD offset 0x08) */
    *(unsigned int *)(rfdHead_p + 0x08) = *rbdPhysAddr;

    /* Setup SCB with RFD address (at SCB offset 0x08) */
    *((unsigned int *)scb + 2) = *rfdPhysAddr;

    /* Issue RU START command */
    scb[1] = 0x10;  /* RUC_START */

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for RU to become ready (up to 10000 microseconds) */
    for (timeout = 0; timeout < 10000; timeout++) {
        ruStatus = scb[0] & 0xf0;
        if (ruStatus == 0x40) {
            /* RU ready/suspended */
            return YES;
        }
        IODelay(1);
    }

    /* Timeout or error */
    return NO;
}

/*
 * Abort receive unit
 */
- (BOOL)_abortReceiveUnit
{
    unsigned short *scb = (unsigned short *)scbBase;
    unsigned short scbStatus;
    int timeout;
    const char *driverName;

    /* Check if RU is suspended (status bits 6-7 = 0x40) */
    scbStatus = scb[0] & 0xf0;
    if (scbStatus != 0x40) {
        /* RU not suspended, can proceed */
        return YES;
    }

    /* Wait for SCB to be ready */
    if (![self _waitScb]) {
        return NO;
    }

    /* Wait for command unit */
    if (![self _waitCu:100]) {
        return NO;
    }

    /* Issue RU abort command */
    scb[1] = 0x40;  /* RUC_ABORT */
    [self sendChannelAttention];

    /* Wait for command to complete (up to 2 seconds) */
    timeout = 0;
    while (timeout < 2000) {
        IODelay(1000);
        scbStatus = scb[0] & 0xf0;
        if (scbStatus == 0) {
            /* RU aborted successfully */
            return YES;
        }
        timeout++;
    }

    /* Timeout */
    driverName = [self name];
    IOLog("%s: abort receive unit timed out\n", driverName);
    return NO;
}

/*
 * Allocate memory for 82596 structures from shared memory pool
 * Aligns allocation to 4-byte boundary
 */
- (void *)_memAlloc:(unsigned int)size
{
    unsigned int alignedSize;
    void *allocatedMem;

    /* Round up to 4-byte boundary (align to 4 bytes) */
    alignedSize = (size + 3) & 0xfffffffc;

    /* Check if enough memory remains */
    if (sharedMemRemaining < alignedSize) {
        IOPanic("Intel82596: shared memory exhausted\n");
    }

    /* Return current pointer and advance it */
    allocatedMem = sharedMemPtr;
    sharedMemPtr = (char *)sharedMemPtr + alignedSize;
    sharedMemRemaining -= alignedSize;

    return allocatedMem;
}

/*
 * Initialize RFD list (Receive Frame Descriptor list)
 */
- (BOOL)_initRfdList
{
    unsigned short *scb = (unsigned short *)scbBase;
    const char *driverName;
    IOReturn result;
    vm_task_t task;
    int i;
    char *rfd;
    void *netbuf;
    void *netbufData;
    unsigned short *rfdFlags;

    /* Check if receive unit is ready */
    if ((scb[0] & 0xc0) != 0) {
        driverName = [self name];
        IOLog("%s: _initRfdList called while receive unit ready\n", driverName);
        [self _abortReceiveUnit];
    }

    /* Free any existing netbufs in the RFD list */
    for (i = 0; i < 0x10; i++) {  /* 16 RFDs */
        rfd = (char *)rfdList + (i * 0x40);
        netbuf = *(void **)(rfd + 0x38);
        if (netbuf != NULL) {
            _nb_free(netbuf);
            *(void **)(rfd + 0x38) = NULL;
        }
    }

    /* Zero out RFD list (16 * 64 = 1024 bytes) */
    bzero(rfdList, 0x400);

    /* Validate and setup each RFD */
    for (i = 0; i < 0x10; i++) {
        rfd = (char *)rfdList + (i * 0x40);

        /* Validate RFD address (rfd + 0x24) */
        task = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(task, (unsigned int)rfd, (unsigned int *)(rfd + 0x24));
        if (result != IO_R_SUCCESS) {
            driverName = [self name];
            IOLog("%s: Invalid RFD address\n", driverName);
            return NO;
        }

        /* Validate RBD address (rfd + 0x28, store at rfd + 0x3c) */
        task = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(task, (unsigned int)(rfd + 0x28), (unsigned int *)(rfd + 0x3c));
        if (result != IO_R_SUCCESS) {
            driverName = [self name];
            IOLog("%s: Invalid RBD address\n", driverName);
            return NO;
        }
    }

    /* Setup RFD linked list */
    for (i = 0; i < 0x10; i++) {
        rfd = (char *)rfdList + (i * 0x40);

        /* Set suspend bit in control field (offset 0x02) */
        rfdFlags = (unsigned short *)(rfd + 0x02);
        *rfdFlags |= 0x08;

        /* Setup link pointers */
        if (i == 0x0f) {
            /* Last entry points back to first */
            *(void **)(rfd + 0x20) = rfdList;
            rfdFlags = (unsigned short *)(rfd + 0x02);
            *rfdFlags |= 0x8000;  /* End of list marker */
        } else {
            /* Point to next entry */
            *(void **)(rfd + 0x20) = (char *)rfdList + ((i + 1) * 0x40);
        }

        /* Store physical address of link in command link field (offset 0x04) */
        *(unsigned int *)(rfd + 0x04) = *(unsigned int *)(*(void **)(rfd + 0x20) + 0x24);

        /* Setup RBD pointer */
        if (i == 0) {
            /* First entry - point to last RBD */
            *(unsigned int *)(rfd + 0x08) = *((unsigned int *)rfdList + (0x0f * 0x10) + 0x0f);
        } else {
            /* No RBD */
            *(unsigned int *)(rfd + 0x08) = 0xffffffff;
        }

        /* Store RBD buffer address (offset 0x2c) */
        *(unsigned int *)(rfd + 0x2c) = *(unsigned int *)(*(void **)(rfd + 0x20) + 0x3c);

        /* Allocate network buffer */
        netbuf = (void *)[self _recAllocateNetbuf];
        *(void **)(rfd + 0x38) = netbuf;
        if (netbuf == NULL) {
            driverName = [self name];
            IOLog("%s: receive buffer allocation failed\n", driverName);
        }

        /* Map netbuf and get physical address */
        netbufData = _nb_map(netbuf, (unsigned int *)(rfd + 0x30));
        task = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(task, (unsigned int)netbufData, (unsigned int *)(rfd + 0x30));
        if (result != IO_R_SUCCESS) {
            driverName = [self name];
            IOLog("%s: Invalid RBD netbuf address\n", driverName);
            return NO;
        }

        /* Set buffer size (1514 bytes = 0x5ea) */
        *(unsigned short *)(rfd + 0x34) = 0x5ea;

        /* Mark last RBD with end-of-list */
        if (i == 0x0f) {
            rfdFlags = (unsigned short *)(rfd + 0x34);
            *rfdFlags |= 0x8000;
        }
    }

    /* Mark second-to-last RFD with end marker */
    rfdFlags = (unsigned short *)((char *)rfdList + (0x0e * 0x40) + 0x02);
    *rfdFlags |= 0x8000;

    /* Setup head and tail pointers */
    rfdTail = (char *)rfdList + (0x0e * 0x40);
    rfdHead = rfdList;

    return YES;
}

/*
 * Initialize TCB list (Transmit Command Block list)
 */
- (BOOL)_initTcbList
{
    unsigned short *scb = (unsigned short *)scbBase;
    const char *driverName;
    IOReturn result;
    vm_task_t task;
    int i, j;
    char *tcb, *tbd;
    void *netbuf;

    /* Check if command unit is active */
    if ((scb[0] & 0x200) != 0) {
        driverName = [self name];
        IOLog("%s: _initTcbList called while command unit active\n", driverName);
        [self _waitCu:100];
    }

    /* Free any existing netbufs in the TCB list */
    for (i = 0; i < 8; i++) {  /* 8 TCBs */
        tcb = (char *)tcbList + (i * 0x6c);
        netbuf = *(void **)(tcb + 0x68);
        if (netbuf != NULL) {
            _nb_free(netbuf);
            *(void **)(tcb + 0x68) = NULL;
        }
    }

    /* Zero out TCB list (8 * 108 = 864 bytes / 0x360) */
    bzero(tcbList, 0x360);

    /* Validate and setup each TCB */
    for (i = 0; i < 8; i++) {
        tcb = (char *)tcbList + (i * 0x6c);

        /* Validate TCB address (store at tcb + 0x1c) */
        task = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(task, (unsigned int)tcb, (unsigned int *)(tcb + 0x1c));
        if (result != IO_R_SUCCESS) {
            driverName = [self name];
            IOLog("%s: Invalid TCB address\n", driverName);
            return NO;
        }

        /* Validate each TBD (3 TBDs per TCB) */
        for (j = 0; j < 3; j++) {
            tbd = tcb + 0x20 + (j * 0x18);  /* TBDs start at offset 0x20 */

            /* Validate TBD address (store at tbd + 0xc) */
            task = IOVmTaskSelf();
            result = IOPhysicalFromVirtual(task, (unsigned int)tbd, (unsigned int *)(tbd + 0xc));
            if (result != IO_R_SUCCESS) {
                driverName = [self name];
                IOLog("%s: Invalid TBD address\n", driverName);
                return NO;
            }

            /* Validate TBD align address (tbd + 0x14, store at tbd + 0x10) */
            task = IOVmTaskSelf();
            result = IOPhysicalFromVirtual(task, (unsigned int)(tbd + 0x14), (unsigned int *)(tbd + 0x10));
            if (result != IO_R_SUCCESS) {
                driverName = [self name];
                IOLog("%s: Invalid TBD align address\n", driverName);
                return NO;
            }
        }

        /* Setup link pointers */
        if (i == 7) {
            /* Last entry - no next link */
            *(unsigned int *)(tcb + 0x18) = 0;
        } else {
            /* Point to next TCB */
            *(void **)(tcb + 0x18) = (char *)tcbList + ((i + 1) * 0x6c);
        }
    }

    /* Setup TCB list pointers */
    tcbHead = tcbList;
    tcbTail = NULL;
    tcbFree = NULL;
    tcbReserved = NULL;

    return YES;
}

/*
 * Transmit a packet using TCB/TBD structures
 */
- (BOOL)_transmitPacket:(netbuf_t)packet
{
    unsigned short *tcb;
    unsigned short *tbd;
    unsigned char *packetData;
    int packetSize;
    int alignBytes;
    int i;
    int contiguousSize;
    IOReturn result;
    vm_task_t task;
    const char *driverName;
    unsigned short tbdCount;
    unsigned short *initialTbd;

    /* Get next free TCB from head */
    tcb = (unsigned short *)tcbHead;
    tcbHead = *(void **)((char *)tcb + 0x18);  /* tcb->link */

    /* Initialize TCB */
    tcb[0] = 0;  /* Status/command */
    *((unsigned int *)(tcb + 2)) = 0xffffffff;  /* Link address (end of list) */
    tcb[1] = 0x200c;  /* Command: transmit + suspend + interrupt */
    *((unsigned int *)(tcb + 0xc)) = 0;  /* TBD link */

    /* Setup TBD pointer - first TBD at offset 0x20 from TCB start */
    tbd = tcb + 0x10;  /* offset 0x20 in bytes = 0x10 in shorts */
    initialTbd = tbd;

    /* Store TBD physical address in TCB (at offset 0x08) */
    *((unsigned int *)(tcb + 4)) = *((unsigned int *)tcb + 0x16/sizeof(unsigned int));

    tcb[6] = 0;  /* Tx count */
    tcb[7] = 0;  /* Reserved */

    /* Store netbuf pointer in TCB (at offset 0x68) */
    *(netbuf_t *)((char *)tcb + 0x68) = packet;

    /* Map netbuf to get data pointer */
    packetData = (unsigned char *)_nb_map(packet);
    packetSize = _nb_size(packet);

    /* Check if packet data is aligned to 4-byte boundary */
    if (((unsigned int)packetData & 3) != 0) {
        /* Unaligned - copy alignment bytes to TCB's alignment buffer */
        alignBytes = 4 - ((unsigned int)packetData & 3);

        /* Setup alignment TBD (at offset 0x28 from tbd) */
        *((unsigned int *)(tbd + 0x14/sizeof(unsigned short))) =
            *((unsigned int *)(tbd + 0x18/sizeof(unsigned short)));  /* Physical address */
        tbd[0x10] = (unsigned short)alignBytes;  /* Count */

        /* Copy alignment bytes */
        for (i = 0; i < alignBytes; i++) {
            *((unsigned char *)tbd + 0x14 + i) = packetData[i];
        }

        /* Move to next TBD */
        *((unsigned int *)(tbd + 0x12/sizeof(unsigned short))) =
            *((unsigned int *)(tbd + 0x22/sizeof(unsigned short)));  /* Link */
        tbd = tbd + 0x1c/sizeof(unsigned short);  /* Advance to next TBD */

        /* Adjust packet pointer and size */
        packetData += alignBytes;
        packetSize -= alignBytes;
    }

    /* Check physical contiguity */
    contiguousSize = _IOIsPhysicallyContiguous((unsigned int)packetData, packetSize);
    if (contiguousSize == 0) {
        driverName = [self name];
        IOLog("%s: IOIsPhysicallyContiguous returned 0\n", driverName);
        _nb_free(packet);
        *(netbuf_t *)((char *)tcb + 0x68) = NULL;
        return NO;
    }

    /* Calculate actual contiguous length */
    contiguousSize = (contiguousSize - (int)packetData) + 1;

    /* If packet is not fully contiguous, split into two TBDs */
    if (contiguousSize < packetSize) {
        /* First piece - get physical address */
        task = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(task, (unsigned int)packetData,
                                       (unsigned int *)(tbd + 4));
        if (result != IO_R_SUCCESS) {
            driverName = [self name];
            IOLog("%s: Invalid address for outgoing packet (before piece)\n", driverName);
            _nb_free(packet);
            *(netbuf_t *)((char *)tcb + 0x68) = NULL;
            return NO;
        }

        tbd[0] = (unsigned short)contiguousSize;  /* Count */
        *((unsigned int *)(tbd + 2)) = *((unsigned int *)(tbd + 0x12));  /* Link to next TBD */

        /* Advance to next TBD */
        tbd = tbd + 0xc;  /* 0x18 bytes / 2 */

        /* Update for second piece */
        packetData += contiguousSize;
        packetSize -= contiguousSize;
    }

    /* Last piece - get physical address */
    task = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(task, (unsigned int)packetData,
                                   (unsigned int *)(tbd + 4));
    if (result != IO_R_SUCCESS) {
        driverName = [self name];
        IOLog("%s: Invalid address for outgoing packet\n", driverName);
        _nb_free(packet);
        *(netbuf_t *)((char *)tcb + 0x68) = NULL;
        return NO;
    }

    /* Set last TBD with end-of-list marker */
    tbd[0] = (unsigned short)packetSize | 0x8000;  /* Count with EOF */
    tbd[2] = 0xffff;  /* Link = end */
    tbd[3] = 0xffff;

    /* Add TCB to transmit queue */
    if (tcbTail != NULL) {
        /* Queue has entries - add to end */
        if (tcbFree == NULL) {
            tcbFree = tcb;
        } else {
            /* Link to end of queue */
            *(void **)((char *)tcbReserved + 0x18) = tcb;
            *((unsigned int *)tcbReserved + 1) = *((unsigned int *)tcb + 0xe/sizeof(unsigned int));
        }
        tcbReserved = tcb;
    } else {
        /* Queue empty - this is first entry */
        tcb[1] |= 0x8000;  /* Set EL (end of list) bit */
        tcbTail = tcb;

        /* Start command unit */
        if (![self _startCommandUnit]) {
            [self _scheduleReset];
            return NO;
        }

        /* Set timeout for transmission (500ms) */
        [self setRelativeTimeout:500];
    }

    return YES;
}

/*
 * Allocate network buffer from buffer pool for receive operations
 */
- (void *)_recAllocateNetbuf
{
    void *netbuf;
    const char *driverName;

    /* Check if buffer pool exists */
    if (bufferPool == nil) {
        driverName = [self name];
        IOLog("%s: allocateNetbuf called, but buffer pool doesn't exist\n", driverName);
        return NULL;
    }

    /* Get buffer from pool */
    netbuf = [bufferPool getNetBuffer];
    return netbuf;
}

@end

/*
 * C function stubs
 */

/*
 * Reset function - called to reset a driver instance
 */
void __resetFunc(id driver)
{
    BOOL result;
    const char *driverName;

    result = [driver resetAndEnable:YES];
    if (!result) {
        driverName = [driver name];
        IOLog("%s: Reset attempt unsuccessful\n", driverName);
    }
}
