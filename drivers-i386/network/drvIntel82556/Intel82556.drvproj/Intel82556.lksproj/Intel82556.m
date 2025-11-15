/*
 * Intel82556.m
 * Intel EtherExpress PRO/100 Network Driver - Main Implementation
 */

#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <driverkit/IOQueue.h>
#import <driverkit/IONetbufQueue.h>
#import <machkit/NXLock.h>
#import <kernserv/prototypes.h>

/* Utility function declarations */
static void __resetFunc(id driverInstance);
static netbuf_t _getNetBuffer(void *bufferPool);
static unsigned int _IOIsPhysicallyContiguous(unsigned int vaddr, int size);
static unsigned int _IOMallocNonCached(int requestedSize, int *allocPtr, int *allocSize);
static unsigned int _IOMallocPage(int requestedSize, int *allocPtr, int *allocSize);
static unsigned char _card_irq(unsigned short ioBase);
static void _recycleNetbuf(netbuf_t nb, void *arg1, int *bufferEntry);

@implementation Intel82556

/*
 * Probe method - Called during driver discovery
 * This is a stub that should be overridden by subclasses
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    IOLog("Intel82556: Base probe called - should be overridden by subclass\n");
    return NO;
}

/*
 * Initialize from device description
 * Reads configuration table and sets up data rate options
 *
 * Instance variables:
 *   +0x18C: TX queue (IONetbufQueue instance)
 *   +0x1F8: Speed flag (0 = 10Mbps, 1 = 100Mbps)
 *   +0x1FC: Cable check flag (1 = auto-detect speed)
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    id configTable;
    const char *dataRateStr;
    id txQueue;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Initialize cable check flag to 0 (no auto-detect) at offset 0x1FC */
    *(unsigned char *)(((char *)self) + 0x1FC) = 0;

    /* Initialize speed flag to 0 (10Mbps) at offset 0x1F8 */
    *(unsigned int *)(((char *)self) + 0x1F8) = 0;

    /* Get configuration table from device description */
    configTable = [deviceDescription configTable];

    /* Look for "Data Rate" key in config table */
    dataRateStr = [[configTable valueForStringKey:"Data Rate"] cString];

    if (dataRateStr != NULL) {
        /* Check for "Auto" or "AUTO" */
        if (strcmp(dataRateStr, "Auto") == 0 || strcmp(dataRateStr, "AUTO") == 0) {
            /* Enable auto-detect (cable check) */
            *(unsigned char *)(((char *)self) + 0x1FC) = 1;
        }
        /* Check for "10" (10Mbps) */
        else if (strcmp(dataRateStr, "10") == 0) {
            *(unsigned int *)(((char *)self) + 0x1F8) = 0;
        }
        /* Check for "100" (100Mbps) */
        else if (strcmp(dataRateStr, "100") == 0) {
            *(unsigned int *)(((char *)self) + 0x1F8) = 1;
        }

        /* Free the string */
        [configTable freeString:dataRateStr];
    }

    /* Create transmit queue (IONetbufQueue) with max count of 96 (0x60) */
    /* Store at offset 0x18C */
    txQueue = [[IONetbufQueue alloc] initWithMaxCount:0x60];
    *(id *)(((char *)self) + 0x18C) = txQueue;

    return self;
}

/*
 * Reset and enable hardware
 * Performs complete driver initialization and optionally enables interrupts
 *
 * param enable: If YES, enable interrupts and start operation
 * Returns: YES if successful, NO if initialization failed
 *
 * Instance variables:
 *   +0x195: Driver running flag
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    int result;

    /* Clear any pending timeout */
    [self clearTimeout];

    /* Perform hardware initialization */
    if (![self hwInit]) {
        return NO;
    }

    /* Perform software initialization */
    if (![self swInit]) {
        return NO;
    }

    /* If enable requested, set up interrupts */
    if (enable) {
        /* Enable all interrupts */
        result = [self enableAllInterrupts];
        if (result != 0) {
            /* Failed to enable interrupts */
            [self setRunning:NO];
            return NO;
        }

        /* Enable adapter-specific interrupts */
        [self enableAdapterInterrupts];
    }

    /* Set running state based on enable parameter */
    [self setRunning:enable];

    /* Set flag at offset 0x195 */
    *(unsigned char *)(((char *)self) + 0x195) = 1;

    return YES;
}

/*
 * Free driver resources
 *
 * Instance variables:
 *   +0x184: Some object (freed if present)
 *   +0x188: Netbuf pool (Intel82556Buf instance)
 *   +0x18C: TX queue object (freed if present)
 *   +0x195: Driver running flag
 *   +0x1A8: Allocated shared memory pointer
 *   +0x1AC: Allocated shared memory size
 *   +0x1E8: RFD list base
 */
- (void)free
{
    int rfdIndex;
    netbuf_t nb;

    /* If driver is running, shut it down */
    if (*(unsigned char *)(((char *)self) + 0x195) == 1) {
        [self clearTimeout];
        [self disableAllInterrupts];
        [self __waitScb];
        [self __waitCu:1000];
        [self __abortReceiveUnit];

        /* Clear running flag */
        *(unsigned char *)(((char *)self) + 0x195) = 0;
    }

    /* Free object at offset 0x184 if present */
    if (*(id *)(((char *)self) + 0x184) != nil) {
        [*(id *)(((char *)self) + 0x184) free];
    }

    /* Free object at offset 0x18C if present */
    if (*(id *)(((char *)self) + 0x18C) != nil) {
        [*(id *)(((char *)self) + 0x18C) free];
    }

    /* Free netbuf pool and all associated RFD netbufs */
    if (*(id *)(((char *)self) + 0x188) != nil) {
        /* Free all RFD netbufs (64 entries) */
        for (rfdIndex = 0; rfdIndex < 0x40; rfdIndex++) {
            nb = *(netbuf_t *)(*(int *)(((char *)self) + 0x1E8) + 0x44 + rfdIndex * 0x48);
            if (nb != NULL) {
                nb_free(nb);
            }
        }

        /* Free the netbuf pool object */
        [*(id *)(((char *)self) + 0x188) free];
    }

    /* Free shared memory pool */
    IOFree((void *)*(unsigned int *)(((char *)self) + 0x1A8),
           *(unsigned int *)(((char *)self) + 0x1AC));

    /* Call superclass free */
    [super free];
}

/*
 * Clear timeout counter
 */
- (void)clearTimeout
{
    IOLog("Intel82556: clearTimeout\n");
}

/*
 * Hardware initialization
 * Performs chip initialization with cable detection
 *
 * Instance variables:
 *   +0x1F8: Multicast promiscuous flag
 *   +0x1FC: Cable check flag (1 = check cable connection)
 */
- (BOOL)hwInit
{
    int dumpBuffer;
    unsigned int allocPtr;
    unsigned int allocSize;
    const char *driverName;
    BOOL result;

    /* Allocate temporary page for dump buffer */
    dumpBuffer = _IOMallocPage(__page_size, (int *)&allocPtr, (int *)&allocSize);
    if (dumpBuffer == 0) {
        driverName = [[self name] cString];
        IOLog("%s: hwInit: IOMallocPage failed\n", driverName);
        return NO;
    }

    /* Check if cable detection is enabled at offset 0x1FC */
    if (*(unsigned char *)(((char *)self) + 0x1FC) == 1) {
        /* First attempt with multicast promiscuous mode enabled */
        *(unsigned int *)(((char *)self) + 0x1F8) = 1;

        if (![self __hwInit]) {
            IOFree((void *)allocPtr, allocSize);
            return NO;
        }

        [self lockDBRT];
        IOSleep(500);

        if (![self dump:(void *)dumpBuffer]) {
            IOFree((void *)allocPtr, allocSize);
            return NO;
        }

        /* Check link status bit (bit 6) in dump buffer byte +1 */
        if ((*(unsigned char *)(dumpBuffer + 1) & 0x40) == 0) {
            /* Link not detected - try again without multicast promiscuous */
            *(unsigned int *)(((char *)self) + 0x1F8) = 0;

            if (![self __hwInit]) {
                IOFree((void *)allocPtr, allocSize);
                return NO;
            }

            [self lockDBRT];
            IOSleep(500);

            if (![self dump:(void *)dumpBuffer]) {
                IOFree((void *)allocPtr, allocSize);
                return NO;
            }

            /* Check link status again */
            if ((*(unsigned char *)(dumpBuffer + 1) & 0x40) == 0) {
                driverName = [[self name] cString];
                IOLog("%s: network cable is disconnected, please attach\n", driverName);
            }
        }
    } else {
        /* No cable detection - just initialize */
        if (![self __hwInit]) {
            IOFree((void *)allocPtr, allocSize);
            return NO;
        }

        [self lockDBRT];
        IOSleep(500);

        if (![self dump:(void *)dumpBuffer]) {
            IOFree((void *)allocPtr, allocSize);
            return NO;
        }

        /* Check link status */
        if ((*(unsigned char *)(dumpBuffer + 1) & 0x40) == 0) {
            driverName = [[self name] cString];
            IOLog("%s: network cable is disconnected, please attach\n", driverName);
        }

        IOSleep(200);
    }

    /* Free temporary dump buffer */
    IOFree((void *)allocPtr, allocSize);

    /* Set up individual address (MAC address) */
    if (![self iaSetup]) {
        return NO;
    }

    return YES;
}

/*
 * Software initialization
 * Initializes TCB/RFD lists and starts the receive unit
 * This must be called with the debugger lock held for thread safety
 */
- (BOOL)swInit
{
    BOOL result = NO;

    /* Reserve debugger lock for thread-safe initialization */
    [self reserveDebuggerLock];

    /* Initialize TCB list */
    if ([self __initTcbList]) {
        /* Initialize RFD list */
        if ([self __initRfdList]) {
            /* Start receive unit */
            if ([self __startReceiveUnit]) {
                result = YES;
            }
        }
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];

    return result;
}

/*
 * Cold initialization
 * Allocates all memory structures needed for driver operation
 *
 * Memory structure layout:
 *   +0x194: Multicast configured flag
 *   +0x198: Shared memory pool base
 *   +0x19C: Shared memory pool size
 *   +0x1A0: Shared memory pool current pointer
 *   +0x1A4: Shared memory pool remaining size
 *   +0x1A8: Allocated pointer (for deallocation)
 *   +0x1AC: Allocated size (for deallocation)
 *   +0x1B0: SCP (System Configuration Pointer) base
 *   +0x1B4: ISCP (Intermediate System Configuration Pointer) base
 *   +0x1B8: SCB (System Control Block) base
 *   +0x1BC: Self-test area (16-byte aligned)
 *   +0x1C0: Config block base
 *   +0x1C4: Config block physical address
 *   +0x1C8: TCB list base
 *   +0x1DC: Loopback TCB
 *   +0x1E0: Loopback buffer
 *   +0x1E4: Loopback buffer physical address
 *   +0x1E8: RFD list base
 *   +0x188: Netbuf pool (Intel82556Buf instance)
 */
- (BOOL)coldInit
{
    int sharedMemBase;
    unsigned int actualBufSize;
    const char *driverName;
    IOTask vmTask;
    int result;

    /* Clear IRQ latch and disable interrupts */
    [self clearIrqLatch];
    [self disableAdapterInterrupts];

    /* Clear multicast configured flag at offset 0x194 */
    *(unsigned char *)(((char *)self) + 0x194) = 0;

    /* Set shared memory pool size to one page at offset 0x19C */
    *(unsigned int *)(((char *)self) + 0x19C) = __page_size;

    /* Allocate page-aligned shared memory pool */
    sharedMemBase = _IOMallocNonCached(__page_size,
                                       (int *)(((char *)self) + 0x1A8),
                                       (int *)(((char *)self) + 0x1AC));

    /* Store shared memory base at offset 0x198 */
    *(int *)(((char *)self) + 0x198) = sharedMemBase;

    if (sharedMemBase == 0) {
        driverName = [[self name] cString];
        IOLog("%s: Can't allocate shared memory page\n", driverName);
        return NO;
    }

    /* Clear shared memory pool */
    bzero((void *)*(int *)(((char *)self) + 0x198),
          *(size_t *)(((char *)self) + 0x19C));

    /* Initialize shared memory pool pointers */
    *(unsigned int *)(((char *)self) + 0x1A0) = *(unsigned int *)(((char *)self) + 0x198);
    *(unsigned int *)(((char *)self) + 0x1A4) = *(unsigned int *)(((char *)self) + 0x19C);

    /* Allocate SCP (12 bytes) at offset 0x1B0 */
    *(unsigned int *)(((char *)self) + 0x1B0) = [self __memAlloc:0x0C];

    /* Allocate ISCP (8 bytes) at offset 0x1B4 */
    *(unsigned int *)(((char *)self) + 0x1B4) = [self __memAlloc:0x08];

    /* Allocate SCB (44 bytes) at offset 0x1B8 */
    *(unsigned int *)(((char *)self) + 0x1B8) = [self __memAlloc:0x2C];

    /* Allocate self-test area (24 bytes, 16-byte aligned) at offset 0x1BC */
    sharedMemBase = [self __memAlloc:0x18];
    *(int *)(((char *)self) + 0x1BC) = sharedMemBase;

    /* Ensure 16-byte alignment for self-test area */
    if ((*(unsigned char *)(((char *)self) + 0x1BC) & 0x0F) != 0) {
        *(unsigned int *)(((char *)self) + 0x1BC) =
            (sharedMemBase + 0x0F) & 0xFFFFFFF0;
    }

    /* Allocate config block (68 bytes) at offset 0x1C0 */
    *(unsigned int *)(((char *)self) + 0x1C0) = [self __memAlloc:0x44];

    /* Get physical address of config block and store at offset 0x1C4 */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask,
                                   (vm_address_t)*(unsigned int *)(((char *)self) + 0x1C0),
                                   (unsigned int *)(((char *)self) + 0x1C4));
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid command block address\n", driverName);
        return NO;
    }

    /* Allocate TCB list (16 * 68 = 1088 bytes = 0x440) at offset 0x1C8 */
    *(unsigned int *)(((char *)self) + 0x1C8) = [self __memAlloc:0x440];

    /* Allocate loopback TCB (68 bytes) at offset 0x1DC */
    sharedMemBase = [self __memAlloc:0x44];
    *(int *)(((char *)self) + 0x1DC) = sharedMemBase;

    /* Get physical address of loopback TCB and store at offset +0x1C */
    result = IOPhysicalFromVirtual(vmTask,
                                   (vm_address_t)sharedMemBase,
                                   (unsigned int *)(sharedMemBase + 0x1C));
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid TCB address\n", driverName);
        return NO;
    }

    /* Get physical address of loopback TCB's TBD at offset +0x20 and store at +0x2C */
    result = IOPhysicalFromVirtual(vmTask,
                                   (vm_address_t)(*(int *)(((char *)self) + 0x1DC) + 0x20),
                                   (unsigned int *)(*(int *)(((char *)self) + 0x1DC) + 0x2C));
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid TCB->_TBD address\n", driverName);
        return NO;
    }

    /* Allocate loopback buffer (1514 bytes = 0x5EA) at offset 0x1E0 */
    *(unsigned int *)(((char *)self) + 0x1E0) = [self __memAlloc:0x5EA];

    /* Get physical address of loopback buffer and store at offset 0x1E4 */
    result = IOPhysicalFromVirtual(vmTask,
                                   (vm_address_t)*(unsigned int *)(((char *)self) + 0x1E0),
                                   (unsigned int *)(((char *)self) + 0x1E4));
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid address\n", driverName);
        return NO;
    }

    /* Allocate RFD list (64 * 72 = 4608 bytes = 0x1200) at offset 0x1E8 */
    *(unsigned int *)(((char *)self) + 0x1E8) = [self __memAlloc:0x1200];

    /* Create netbuf pool at offset 0x188 */
    *(id *)(((char *)self) + 0x188) =
        [[Intel82556Buf alloc] initWithRequestedSize:0x5EE
                                          actualSize:&actualBufSize
                                               count:0x100];

    /* Verify buffer size is adequate (must be at least 1518 bytes = 0x5EE) */
    if (actualBufSize < 0x5EE) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to allocate memory buffers of adequate length\n", driverName);
        return NO;
    }

    /* Run self-test */
    if (![self __selfTest]) {
        return NO;
    }

    return YES;
}

/*
 * Configuration
 * Configures the 82556 chip with various control register settings
 *
 * The config block is 22 bytes (0x16) plus header (total 0x1C bytes)
 * Each byte controls specific chip behavior
 *
 * Instance variables:
 *   +0x190: Promiscuous mode flag (bit 0)
 *   +0x1B8: SCB base
 *   +0x1C0: Config block base
 *   +0x1C4: Config block physical address
 *   +0x1F8: Multicast promiscuous flag (bit 0)
 */
- (BOOL)config
{
    void *configBlock;
    unsigned char *configBytes;
    unsigned char promiscuousFlag;
    unsigned char multicastFlag;
    const char *driverName;
    int timeout;

    /* Get config block pointer */
    configBlock = *(void **)(((char *)self) + 0x1C0);

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return NO;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:100]) {
        return NO;
    }

    /* Clear config block (28 bytes = 0x1C) */
    bzero(configBlock, 0x1C);

    configBytes = (unsigned char *)configBlock;

    /* Byte +2: Command word (low byte) */
    configBytes[2] = (configBytes[2] & 0xF8) | 0x02;  /* Command = CONFIG (2) */

    /* Byte +3: Command word (high byte) */
    configBytes[3] |= 0x80;  /* Set suspend bit */

    /* Bytes +4-7: Link pointer (set to -1 = end of list) */
    *(unsigned int *)&configBytes[4] = 0xFFFFFFFF;

    /* Byte +8: Byte count and FIFO limit */
    configBytes[8] = (configBytes[8] & 0xC0) | 0x14;  /* 20 bytes to configure */

    /* Byte +9: FIFO limit and flags */
    configBytes[9] = (configBytes[9] & 0xF0) | 0x08;  /* TX FIFO limit = 8 */
    configBytes[9] |= 0xC0;  /* Set bits 6-7 */

    /* Byte +10: Adaptive IFS */
    configBytes[10] |= 0x20;  /* Enable adaptive IFS */

    /* Byte +11: Various flags */
    configBytes[11] = (configBytes[11] & 0xF8) | 0x06;  /* Preamble length = 6 */
    configBytes[11] |= 0x08;  /* Set bit 3 */

    /* Byte +12: Promiscuous mode flag */
    promiscuousFlag = *(unsigned char *)(((char *)self) + 0x1F8);
    configBytes[12] = (configBytes[12] & 0xFE) | (promiscuousFlag & 0x01);
    configBytes[12] |= 0x02;  /* Set bit 1 */

    /* Byte +13: Interframe spacing */
    configBytes[13] |= 0x80;  /* Set bit 7 */

    /* Byte +14: Various control flags */
    configBytes[14] = (configBytes[14] & 0xF8) | 0x06;  /* Lower 3 bits = 6 */
    configBytes[14] |= 0x08;  /* Set bit 3 */
    configBytes[14] = (configBytes[14] & 0xCF) | 0x20;  /* Bits 4-5 = 2 */

    /* Byte +16: Priority settings (0x60 = bits 5-6 set) */
    configBytes[16] = 0x60;
    *(unsigned int *)&configBytes[16] = (*(unsigned int *)&configBytes[16] & 0xFFF800FF) | 0x20000;

    /* Byte +18: Upper bits */
    configBytes[18] &= 0x0F;

    /* Byte +19: Multicast and various flags */
    multicastFlag = *(unsigned char *)(((char *)self) + 0x190);
    configBytes[19] = (configBytes[19] & 0xFE) | (multicastFlag & 0x01);
    configBytes[19] |= 0x08;  /* Set bit 3 */
    configBytes[19] |= 0x80;  /* Set bit 7 */

    /* Byte +21: Force full duplex */
    configBytes[21] = 0x40;

    /* Byte +22: Multiple control flags */
    configBytes[22] |= 0x01;  /* Set bit 0 */
    configBytes[22] |= 0x02;  /* Set bit 1 */
    configBytes[22] |= 0x04;  /* Set bit 2 */
    configBytes[22] |= 0x10;  /* Set bit 4 */
    configBytes[22] |= 0x20;  /* Set bit 5 */
    configBytes[22] |= 0x40;  /* Set bit 6 */
    configBytes[22] |= 0x80;  /* Set bit 7 */

    /* Byte +24: Multicast all */
    configBytes[24] |= 0x3F;  /* Set bits 0-5 */

    /* Byte +25: Control flags */
    configBytes[25] |= 0x01;  /* Set bit 0 */
    configBytes[25] = (configBytes[25] & 0xF9) | 0x04;  /* Bits 1-2 = 2 */

    /* Byte +26: Magic packet wakeup */
    configBytes[26] = 0x3A;

    /* Byte +27: Clear bit 0 */
    configBytes[27] &= 0xFE;

    /* Set config block physical address in SCB general pointer */
    *(unsigned int *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 4) =
        *(unsigned int *)(((char *)self) + 0x1C4);

    /* Clear SCB command word */
    *(unsigned short *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 2) = 0;

    /* Set CU command to START (1) */
    *(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) =
        (*(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) & 0xF8) | 0x01;

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for configuration to complete (check status bit 7 in config block byte +1) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);
        if ((configBytes[1] & 0x80) != 0) {
            break;
        }
    }

    if ((configBytes[1] & 0x80) != 0) {
        /* Configuration succeeded - return OK bit (bit 5 of status byte) */
        return (configBytes[1] >> 5) & 0x01;
    }

    driverName = [[self name] cString];
    IOLog("%s: configure command timed out\n", driverName);
    return NO;
}

/*
 * Individual Address (IA) Setup
 * Programs the MAC address into the 82556 chip
 *
 * Instance variables:
 *   +0x17C: Station address bytes 0-3 (first 4 bytes of MAC)
 *   +0x180: Station address bytes 4-5 (last 2 bytes of MAC)
 *   +0x1B8: SCB base
 *   +0x1C0: Config block (used as command block)
 *   +0x1C4: Config block physical address
 */
- (BOOL)iaSetup
{
    void *cmdBlock;
    unsigned char *cmdBytes;
    const char *driverName;
    int timeout;

    /* Get command block pointer */
    cmdBlock = *(void **)(((char *)self) + 0x1C0);

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return NO;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:100]) {
        return NO;
    }

    /* Clear command block (16 bytes for IA setup command) */
    bzero(cmdBlock, 0x10);

    cmdBytes = (unsigned char *)cmdBlock;

    /* Byte +2: Command word (low byte) */
    cmdBytes[2] = (cmdBytes[2] & 0xF8) | 0x01;  /* Command = IA_SETUP (1) */

    /* Byte +3: Command word (high byte) */
    cmdBytes[3] |= 0x80;  /* Set suspend bit */

    /* Bytes +4-7: Link pointer (set to -1 = end of list) */
    *(unsigned int *)&cmdBytes[4] = 0xFFFFFFFF;

    /* Bytes +8-11: First 4 bytes of MAC address from offset 0x17C */
    *(unsigned int *)&cmdBytes[8] = *(unsigned int *)(((char *)self) + 0x17C);

    /* Bytes +12-13: Last 2 bytes of MAC address from offset 0x180 */
    *(unsigned short *)&cmdBytes[12] = *(unsigned short *)(((char *)self) + 0x180);

    /* Set command block physical address in SCB general pointer */
    *(unsigned int *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 4) =
        *(unsigned int *)(((char *)self) + 0x1C4);

    /* Clear SCB command word */
    *(unsigned short *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 2) = 0;

    /* Set CU command to START (1) */
    *(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) =
        (*(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) & 0xF8) | 0x01;

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for IA setup to complete (check status bit 7 in command block byte +1) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);
        if ((cmdBytes[1] & 0x80) != 0) {
            break;
        }
    }

    if ((cmdBytes[1] & 0x80) != 0) {
        /* IA setup succeeded - return OK bit (bit 5 of status byte) */
        return (cmdBytes[1] >> 5) & 0x01;
    }

    driverName = [[self name] cString];
    IOLog("%s: IA-setup command timed out\n", driverName);
    return NO;
}

/*
 * Multicast Setup
 * Programs multicast addresses into the 82556 chip
 *
 * Instance variables:
 *   +0x193: Multicast setup complete flag
 *   +0x1B8: SCB base
 */
- (BOOL)mcSetup
{
    id mcQueue;
    void *cmdBlock;
    unsigned short *cmdWords;
    unsigned char *cmdBytes;
    unsigned int allocPtr;
    unsigned int allocSize;
    id queueEntry;
    id nextEntry;
    int mcCount;
    int offset;
    const char *driverName;
    IOTask vmTask;
    int timeout;
    int result;

    /* Get multicast queue from superclass */
    mcQueue = [super multicastQueue];

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return NO;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:100]) {
        return NO;
    }

    /* Allocate page for MC command block */
    cmdBlock = (void *)_IOMallocPage(__page_size, (int *)&allocPtr, (int *)&allocSize);
    if (cmdBlock == NULL) {
        driverName = [[self name] cString];
        IOLog("%s: mcSetup:IOMallocPage return NULL\n", driverName);
        return NO;
    }

    cmdWords = (unsigned short *)cmdBlock;
    cmdBytes = (unsigned char *)cmdBlock;

    /* Clear status and command */
    cmdWords[0] = 0;
    cmdWords[1] = 0;

    /* Byte +2: Command word (low byte) */
    cmdBytes[2] = (cmdBytes[2] & 0xF8) | 0x03;  /* Command = MC_SETUP (3) */

    /* Byte +3: Command word (high byte) */
    cmdBytes[3] |= 0x80;  /* Set suspend bit */

    /* Bytes +4-7: Link pointer (set to -1 = end of list) */
    cmdWords[2] = 0xFFFF;
    cmdWords[3] = 0xFFFF;

    /* Copy multicast addresses from queue starting at offset +10 (5 words) */
    mcCount = 0;
    offset = 10;  /* Offset in bytes for first MC address */

    /* Iterate through multicast queue */
    queueEntry = [mcQueue firstObject];
    nextEntry = [mcQueue nextObject];

    while (queueEntry != mcQueue) {
        /* Copy 6-byte Ethernet address (3 words) */
        *(unsigned int *)((char *)cmdBlock + offset) =
            *(unsigned int *)((char *)queueEntry + 0);  /* First 4 bytes */
        *(unsigned short *)((char *)cmdBlock + offset + 4) =
            *(unsigned short *)((char *)queueEntry + 4);  /* Last 2 bytes */

        mcCount++;
        offset += 6;

        /* Move to next entry */
        queueEntry = nextEntry;
        nextEntry = [mcQueue nextObject];
    }

    /* Set multicast address count at offset +8 (byte count = count * 6) */
    cmdWords[4] = (unsigned short)(mcCount * 6);

    /* Get physical address of command block */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask,
                                   (vm_address_t)cmdBlock,
                                   (unsigned int *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 4));
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid MC-setup command block address\n", driverName);
        IOFree((void *)allocPtr, allocSize);
        return NO;
    }

    /* Clear SCB command word */
    *(unsigned short *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 2) = 0;

    /* Set CU command to START (1) */
    *(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) =
        (*(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) & 0xF8) | 0x01;

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for MC setup to complete (check status bit 7 or aborted bit 12) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);
        if ((cmdBytes[1] & 0x80) != 0 || (cmdWords[0] & 0x1000) != 0) {
            break;
        }
    }

    if ((cmdBytes[1] & 0x80) != 0) {
        /* Free command block */
        IOFree((void *)allocPtr, allocSize);

        /* Set multicast setup complete flag at offset 0x193 */
        *(unsigned char *)(((char *)self) + 0x193) = 1;

        /* Return OK bit (bit 5 of status byte) */
        return (cmdBytes[1] >> 5) & 0x01;
    }

    driverName = [[self name] cString];
    IOLog("%s: MC-setup command timed out 0x%x\n", driverName, cmdWords[0]);
    IOFree((void *)allocPtr, allocSize);
    return NO;
}

/*
 * Enable promiscuous mode
 * Sets promiscuous flag and reconfigures the chip
 *
 * Instance variables:
 *   +0x190: Promiscuous mode flag (offset 400 decimal)
 */
- (BOOL)enablePromiscuousMode
{
    /* Check if already enabled */
    if (*(unsigned char *)(((char *)self) + 400) == 0) {
        /* Set promiscuous mode flag */
        *(unsigned char *)(((char *)self) + 400) = 1;
    }

    /* Reconfigure chip with new settings */
    return [self config];
}

/*
 * Disable promiscuous mode
 * Clears promiscuous flag and reconfigures the chip
 *
 * Instance variables:
 *   +0x190: Promiscuous mode flag (offset 400 decimal)
 */
- (void)disablePromiscuousMode
{
    /* Check if enabled */
    if (*(unsigned char *)(((char *)self) + 400) != 0) {
        /* Clear promiscuous mode flag */
        *(unsigned char *)(((char *)self) + 400) = 0;
    }

    /* Reconfigure chip with new settings */
    [self config];
}

/*
 * Enable multicast mode
 * Sets multicast flag
 *
 * Instance variables:
 *   +0x191: Multicast configured flag
 */
- (BOOL)enableMulticastMode
{
    /* Set multicast configured flag */
    *(unsigned char *)(((char *)self) + 0x191) = 1;

    return YES;
}

/*
 * Disable multicast mode
 * Clears multicast flag and updates hardware if needed
 *
 * Instance variables:
 *   +0x191: Multicast configured flag
 */
- (void)disableMulticastMode
{
    const char *driverName;

    /* If multicast is configured, disable it */
    if (*(unsigned char *)(((char *)self) + 0x191) != 0) {
        if (![self mcSetup]) {
            driverName = [[self name] cString];
            IOLog("%s: disable multicast mode failed\n", driverName);
        }
    }

    /* Clear multicast configured flag */
    *(unsigned char *)(((char *)self) + 0x191) = 0;
}

/*
 * Add multicast address
 * param addr: Ethernet address to add
 *
 * Sets multicast configured flag and calls mcSetup to update hardware
 * Offset 0x191 is the multicast configured flag
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    const char *driverName;

    /* Set multicast configured flag at offset 0x191 */
    *(unsigned char *)(((char *)self) + 0x191) = 1;

    /* Update multicast setup */
    if (![self mcSetup]) {
        driverName = [[self name] cString];
        IOLog("%s: add multicast address failed\n", driverName);
    }
}

/*
 * Remove multicast address
 * Removes a multicast address from the multicast list and reconfigures the adapter
 *
 * param addr: Pointer to Ethernet address to remove
 *
 * Note: The actual list removal is handled by the superclass.
 * This method just reconfigures the adapter with the updated list.
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;
    const char *driverName;

    /* Reconfigure multicast addresses */
    result = [self mcSetup];

    if (!result) {
        driverName = [[self name] cString];
        IOLog("%s: remove multicast address failed\n", driverName);
    }
}

/*
 * Interrupt occurred
 * Base class implementation - does nothing
 * Bus-specific variants (EISA/PCI) will override this method
 */
- (void)interruptOccurred
{
    /* Base class stub - bus variants will override */
}

/*
 * Timeout occurred
 * Called when a timeout occurs - checks if driver is running and triggers interrupt processing
 */
- (void)timeoutOccurred
{
    BOOL running;

    /* Check if driver is running */
    running = [self isRunning];

    if (running) {
        /* Trigger interrupt processing */
        [self interruptOccurred];
    }
}

/*
 * Enable adapter interrupts
 * Base class implementation - does nothing
 * Bus-specific variants (EISA/PCI) will override this method
 */
- (void)enableAdapterInterrupts
{
    /* Base class stub - bus variants will override */
}

/*
 * Disable adapter interrupts
 * Base class implementation - does nothing
 * Bus-specific variants (EISA/PCI) will override this method
 */
- (void)disableAdapterInterrupts
{
    /* Base class stub - bus variants will override */
}

/*
 * Clear IRQ latch
 * Base class implementation - does nothing
 * Bus-specific variants (EISA/PCI) will override this method
 */
- (void)clearIrqLatch
{
    /* Base class stub - bus variants will override */
}

/*
 * Acknowledge interrupts by writing status bits to SCB
 * param mask: Interrupt status mask to acknowledge
 * Returns: YES if successful, NO if failed
 *
 * The high byte of the status word contains interrupt flags that
 * are acknowledged by writing them back to the command register
 */
- (BOOL)acknowledgeInterrupts:(unsigned short)mask
{
    void *scbBase;
    unsigned char *scbCommand;
    unsigned char statusByte;
    unsigned char ackBits;
    const char *driverName;
    int timeout;

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return NO;
    }

    /* Get high byte of status (interrupt flags) */
    statusByte = (mask >> 8) & 0xF0;

    /* Only proceed if there are interrupt bits to acknowledge */
    if (statusByte == 0) {
        return NO;
    }

    /* Get SCB base pointer */
    scbBase = *(void **)(((char *)self) + 0x1B8);

    /* Clear SCB command word (offset +2) */
    *(unsigned short *)((char *)scbBase + 2) = 0;

    /* Get SCB command byte +3 (high byte of command word) */
    scbCommand = (unsigned char *)((char *)scbBase + 3);

    /* Write interrupt acknowledgment bits (preserve lower 4 bits, set upper 4) */
    *scbCommand = (*scbCommand & 0x0F) | statusByte;

    /* Send channel attention to execute acknowledge */
    [self sendChannelAttention];

    /* Wait for acknowledgment to complete (upper 4 bits clear) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1);  /* 1 microsecond delay */

        scbCommand = (unsigned char *)((char *)scbBase + 3);
        if ((*scbCommand & 0xF0) == 0) {
            /* Acknowledgment complete */
            return YES;
        }
    }

    /* Timeout - acknowledgment failed */
    driverName = [[self name] cString];
    IOLog("%s: acknowledge scb status 0x%x failed\n", driverName, mask);

    return NO;
}

/*
 * Transmit interrupt occurred
 * Handles transmit completion interrupts - processes completed TCBs
 *
 * Instance variables:
 *   +0x184: Network interface object
 *   +0x1CC: TX available list (free TCBs)
 *   +0x1D0: TX active list head (TCBs being transmitted)
 *   +0x1D4: TX active list tail
 *   +0x1D8: Last TCB in active list
 *
 * TCB structure:
 *   +0x00: Status byte (low)
 *   +0x01: Status byte (high) - bit 7 = complete, bit 5 = OK
 *   +0x03: Command byte (high) - bit 7 = suspend
 *   +0x18: Link to next free TCB
 *   +0x40: Associated netbuf pointer
 *
 * Returns: YES if successful, NO if error occurred
 */
- (BOOL)transmitInterruptOccurred
{
    unsigned char *activeTcb;
    unsigned char *currentTcb;
    unsigned char statusLow;
    unsigned char statusHigh;
    BOOL tcbComplete;
    BOOL tcbOk;
    netbuf_t packet;
    id networkInterface;
    int nextTcb;
    unsigned int collisions;
    const char *driverName;
    BOOL result;

    /* Get network interface */
    networkInterface = *(id *)(((char *)self) + 0x184);

    /* Get active TCB list head */
    activeTcb = *(unsigned char **)(((char *)self) + 0x1D0);

    /* Process all completed TCBs */
    while ((activeTcb != NULL) && ((char)activeTcb[1] < 0)) {  /* Check bit 7 of status high byte */
        /* Clear timeout since we got a response */
        [self clearTimeout];

        /* Get next TCB from link at offset +0x18 */
        nextTcb = *(int *)(activeTcb + 0x18);
        *(int *)(((char *)self) + 0x1D0) = nextTcb;

        /* If active list is now empty, check if there's a tail to restart */
        if ((nextTcb == 0) && (*(int *)(((char *)self) + 0x1D4) != 0)) {
            /* Set suspend bit in last TCB's command byte */
            unsigned char *lastTcb = *(unsigned char **)(((char *)self) + 0x1D8);
            lastTcb[3] |= 0x80;

            /* Move tail to active list */
            *(unsigned int *)(((char *)self) + 0x1D0) = *(unsigned int *)(((char *)self) + 0x1D4);
            *(unsigned int *)(((char *)self) + 0x1D4) = 0;

            /* Start transmit */
            result = [self __startTransmit];
            if (!result) {
                driverName = [[self name] cString];
                IOLog("%s: start transmit failed\n", driverName);
                [self __scheduleReset];
                return NO;
            }

            /* Set timeout for 500ms */
            [self setRelativeTimeout:500];
        }

        /* Get status bytes */
        statusLow = activeTcb[0];
        statusHigh = activeTcb[1];

        /* Check if transmission was OK (bit 5 of status high byte) */
        if ((statusHigh & 0x20) == 0) {
            /* Error - increment output errors */
            [networkInterface incrementOutputErrors];
        } else {
            /* Success - increment output packets */
            [networkInterface incrementOutputPackets];
        }

        /* Handle collision statistics */
        /* Bits 0-3 of status low byte contain collision count */
        collisions = statusLow & 0x0F;
        if (collisions != 0) {
            [networkInterface incrementCollisionsBy:collisions];
        }

        /* Check for excessive collisions (bit 5 of status low byte) */
        if ((statusLow & 0x20) != 0) {
            /* Excessive collisions (16) */
            [networkInterface incrementCollisionsBy:0x10];
        }

        /* Free associated netbuf if present */
        packet = *(netbuf_t *)(activeTcb + 0x40);
        if (packet != NULL) {
            nb_free(packet);

            /* Clear netbuf pointer (4 bytes at offset +0x40) */
            *(unsigned int *)(activeTcb + 0x40) = 0;
        }

        /* Return TCB to free list */
        /* Set link to current free list head */
        *(unsigned int *)(activeTcb + 0x18) = *(unsigned int *)(((char *)self) + 0x1CC);

        /* Set this TCB as new free list head */
        *(unsigned char **)(((char *)self) + 0x1CC) = activeTcb;

        /* Get next active TCB */
        activeTcb = *(unsigned char **)(((char *)self) + 0x1D0);
    }

    /* Service the transmit queue to send any pending packets */
    [self serviceTransmitQueue];

    return YES;
}

/*
 * Receive interrupt occurred
 * Handles receive interrupts by processing the RFD (Receive Frame Descriptor) queue
 *
 * Instance variables:
 *   +0x184: Network interface object
 *   +0x188: Netbuf pool (Intel82556Buf)
 *   +0x1E8: RFD base pointer
 *   +0x1EC: RFD physical address
 *   +0x1F0: RFD count (total number of RFDs)
 *   +0x1F4: Current RFD index
 *
 * Returns: YES (always successful)
 */
- (BOOL)receiveInterruptOccurred:(unsigned int)arg
{
    unsigned char *rfdBase;
    unsigned char *currentRfd;
    unsigned int rfdCount;
    unsigned int currentIndex;
    unsigned short status;
    unsigned short actualCount;
    BOOL frameComplete;
    BOOL frameOk;
    netbuf_t packet;
    void *packetData;
    id networkInterface;
    unsigned int rfdSize = 0x48;  /* RFD size is 72 bytes (0x48) */

    /* Get RFD base pointer */
    rfdBase = *(unsigned char **)(((char *)self) + 0x1E8);
    if (!rfdBase) {
        return;
    }

    /* Get current RFD index */
    currentIndex = *(unsigned int *)(((char *)self) + 0x1F4);

    /* Get total RFD count */
    rfdCount = *(unsigned int *)(((char *)self) + 0x1F0);

    /* Get network interface object */
    networkInterface = *(id *)(((char *)self) + 0x184);

    /* Process all completed RFDs */
    while (1) {
        /* Calculate current RFD address */
        currentRfd = rfdBase + (currentIndex * rfdSize);

        /* Read status word at offset +0 */
        status = *(unsigned short *)currentRfd;

        /* Check if frame is complete (bit 15 - 0x8000) */
        frameComplete = (status & 0x8000) != 0;

        if (!frameComplete) {
            /* No more completed frames */
            break;
        }

        /* Check if frame is OK (bit 13 - 0x2000) */
        frameOk = (status & 0x2000) != 0;

        /* Get actual count (at offset +2, lower 14 bits) */
        actualCount = *(unsigned short *)(currentRfd + 2) & 0x3FFF;

        if (frameOk && actualCount > 0) {
            /* Allocate new netbuf for this packet */
            packet = [self __recAllocateNetbuf];

            if (packet != NULL) {
                /* Get the data pointer from RFD at offset +0x10 (netbuf pointer) */
                void *oldNetbuf = *(void **)(currentRfd + 0x10);

                if (oldNetbuf != NULL) {
                    /* Set packet size */
                    nb_shrink_top((netbuf_t)oldNetbuf, actualCount);

                    /* Pass packet to network interface */
                    if (networkInterface != nil) {
                        [networkInterface performReceive:(netbuf_t)oldNetbuf];
                    } else {
                        /* No interface, free the packet */
                        nb_free((netbuf_t)oldNetbuf);
                    }
                }

                /* Install new netbuf in RFD */
                *(void **)(currentRfd + 0x10) = packet;

                /* Get data pointer from netbuf */
                packetData = nb_map(packet);

                /* Set RBD address at offset +0x14 (physical address of data buffer) */
                if (packetData) {
                    *(unsigned int *)(currentRfd + 0x14) =
                        IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)packetData);
                }
            } else {
                /* Failed to allocate new buffer, reuse old one */
                /* Just clear the complete bit and reuse */
            }
        } else {
            /* Frame had errors or zero length - just reuse the buffer */
        }

        /* Clear status word to mark RFD as ready for reuse */
        *(unsigned short *)currentRfd = 0;

        /* Clear count field */
        *(unsigned short *)(currentRfd + 2) = 0;

        /* Set size field at offset +8 (RBD size = 1518 bytes) */
        *(unsigned short *)(currentRfd + 8) = 0x8000 | 1518;  /* EOF bit (0x8000) | size */

        /* Move to next RFD */
        currentIndex++;
        if (currentIndex >= rfdCount) {
            currentIndex = 0;
        }

        /* Store updated index */
        *(unsigned int *)(((char *)self) + 0x1F4) = currentIndex;
    }

    return YES;
}

/*
 * Transmit packet - Main entry point for packet transmission
 * Handles queueing and direct transmission based on queue state
 *
 * param packet: Network buffer to transmit
 *
 * Instance variables:
 *   +0x18C: TX queue (IONetbufQueue)
 *   +0x1CC: TX available count (number of free TCBs)
 */
- (void)transmit:(netbuf_t)packet
{
    BOOL running;
    int queueCount;
    id txQueue;
    int txAvailable;

    /* Check if driver is running */
    running = [self isRunning];
    if (!running) {
        /* Not running, free the packet */
        nb_free(packet);
        return;
    }

    /* Service the transmit queue first */
    [self serviceTransmitQueue];

    /* Get TX queue */
    txQueue = *(id *)(((char *)self) + 0x18C);

    /* Get current queue count */
    queueCount = [txQueue count];

    /* Get TX available count */
    txAvailable = *(int *)(((char *)self) + 0x1CC);

    /* If queue is empty and we have available TCBs, transmit directly */
    if ((queueCount == 0) && (txAvailable != 0)) {
        [self __transmitPacket:packet];
    } else {
        /* Queue is not empty or no TCBs available, enqueue the packet */
        [txQueue enqueue:packet];
    }
}

/*
 * Get transmit queue size
 * Returns the maximum transmit queue size (96 packets)
 */
- (unsigned int)transmitQueueSize
{
    return 0x60;  /* 96 packets */
}

/*
 * Get transmit queue count
 * Returns the number of packets currently queued for transmission
 *
 * Instance variables:
 *   +0x18C: TX queue (IONetbufQueue)
 */
- (unsigned int)transmitQueueCount
{
    int count;
    id txQueue;

    /* Get TX queue */
    txQueue = *(id *)(((char *)self) + 0x18C);

    /* Get queue count */
    count = [txQueue count];

    return count;
}

/*
 * Send packet - Polled packet transmission
 * Sends a packet using the loopback TCB in polled mode (for debugger/boot)
 *
 * param data: Pointer to packet data
 * param len: Length of packet
 *
 * Instance variables:
 *   +0x1B8: SCB base pointer
 *   +0x1DC: Loopback TCB pointer
 *   +0x1E0: Loopback buffer pointer
 *   +0x1E4: Loopback buffer physical address
 *
 * TCB structure at +0x1DC:
 *   +0x00: Status word
 *   +0x02: Command word
 *   +0x04: Link pointer
 *   +0x08: TBD array address
 *   +0x0C: TCB byte count
 *   +0x1C: Physical address of this TCB
 *   +0x20: First TBD (embedded)
 *   +0x24: TBD link
 *   +0x28: TBD buffer address
 *   +0x2C: TBD array physical address
 */
- (unsigned int)sendPacket:(void *)data length:(unsigned int)len
{
    BOOL needAck = NO;
    unsigned char *scbBase;
    unsigned char *tcbBase;
    unsigned char *cmdByte;
    unsigned short *statusWord;
    unsigned short *sizeWord;
    int timeout;

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return 0;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:1000]) {
        return 0;
    }

    /* Get SCB base */
    scbBase = *(unsigned char **)(((char *)self) + 0x1B8);

    /* Check if CU is in idle or suspended state (bits 6 and 7 of status byte +1) */
    /* Status byte +1, shift right 4 gives us upper 4 bits, mask with 0x0A (bits 1 and 3) */
    if (((scbBase[1] >> 4) & 0x0A) != 0) {
        /* CU needs to be acknowledged first */

        /* Clear SCB command word */
        *(unsigned short *)(scbBase + 2) = 0;

        /* Set command byte to acknowledge status bits */
        scbBase[3] = (scbBase[3] & 0x0F) | (scbBase[1] & 0xA0);

        /* Send channel attention */
        [self sendChannelAttention];

        /* Wait for acknowledgment to complete */
        for (timeout = 0; timeout < 2000; timeout++) {
            IODelay(1);
            if ((scbBase[3] & 0xF0) == 0) {
                break;
            }
        }

        needAck = YES;
    }

    /* Get loopback TCB base */
    tcbBase = *(unsigned char **)(((char *)self) + 0x1DC);

    /* Clear TCB status */
    *(unsigned short *)tcbBase = 0;

    /* Set link pointer to -1 (end of list) */
    *(unsigned int *)(tcbBase + 4) = 0xFFFFFFFF;

    /* Clear command word */
    *(unsigned short *)(tcbBase + 2) = 0;

    /* Set command to TRANSMIT (4) */
    cmdByte = tcbBase + 2;
    *cmdByte = (*cmdByte & 0xF8);     /* Clear command bits */
    *cmdByte = (*cmdByte | 0x04);     /* Set TRANSMIT command */
    *cmdByte = (*cmdByte | 0x08);     /* Set bit 3 (Simplified mode) */

    /* Set suspend bit in command high byte */
    cmdByte = tcbBase + 3;
    *cmdByte = (*cmdByte | 0x80);

    /* Set TBD array address at offset +8 (use embedded TBD at +0x2C) */
    *(unsigned int *)(tcbBase + 8) = *(unsigned int *)(tcbBase + 0x2C);

    /* Clear TCB byte count at offset +0x0C */
    *(unsigned short *)(tcbBase + 0x0C) = 0;

    /* Clamp packet length to valid range */
    if (len > 0x5EA) {  /* Max 1514 bytes */
        len = 0x5EA;
    }
    if (len < 0x40) {  /* Min 64 bytes */
        len = 0x40;
    }

    /* Copy packet data to loopback buffer */
    bcopy(data, *(void **)(((char *)self) + 0x1E0), len);

    /* Set TBD buffer address at offset +0x28 */
    *(unsigned int *)(tcbBase + 0x28) = *(unsigned int *)(((char *)self) + 0x1E4);

    /* Setup first TBD at offset +0x20 */
    *(unsigned short *)(tcbBase + 0x20) = 0;

    /* Set size in TBD (preserve EOF bit 15, set size in lower 15 bits) */
    sizeWord = (unsigned short *)(tcbBase + 0x20);
    *sizeWord = (*sizeWord & 0x8000);  /* Preserve bit 15 */
    *sizeWord = (*sizeWord | (len & 0x7FFF));  /* Set size */

    /* Set EOF bit in TBD high byte */
    cmdByte = tcbBase + 0x21;
    *cmdByte = (*cmdByte | 0x80);

    /* Set TBD link to -1 at offset +0x24 */
    *(unsigned int *)(tcbBase + 0x24) = 0xFFFFFFFF;

    /* Issue CU START command */
    *(unsigned short *)(scbBase + 2) = 0;  /* Clear SCB command */
    scbBase[3] = (scbBase[3] & 0xF8) | 0x01;  /* CU START */

    /* Set general pointer to TCB physical address (at offset +0x1C in TCB) */
    *(unsigned int *)(scbBase + 4) = *(unsigned int *)(tcbBase + 0x1C);

    /* Send channel attention */
    [self sendChannelAttention];

    /* If we didn't already acknowledge, check if we need to now */
    if (!needAck) {
        if ([self __waitScb]) {
            if ([self __waitCu:1000]) {
                /* Check if CU needs acknowledgment */
                scbBase = *(unsigned char **)(((char *)self) + 0x1B8);
                if (((scbBase[1] >> 4) & 0x0A) != 0) {
                    /* Acknowledge */
                    scbBase[3] = (scbBase[3] & 0x0F) | (scbBase[1] & 0xA0);
                    [self sendChannelAttention];

                    /* Wait for acknowledgment */
                    for (timeout = 0; timeout < 2000; timeout++) {
                        IODelay(1);
                        if ((scbBase[3] & 0xF0) == 0) {
                            break;
                        }
                    }
                }
            }
        }
    }

    return len;
}

/*
 * Service transmit queue
 * Dequeues packets from the TX queue and transmits them while TCBs are available
 *
 * Instance variables:
 *   +0x18C: TX queue (IONetbufQueue)
 *   +0x1CC: TX available count (number of free TCBs)
 */
- (void)serviceTransmitQueue
{
    int txAvailable;
    netbuf_t packet;
    id txQueue;

    /* Get TX queue */
    txQueue = *(id *)(((char *)self) + 0x18C);

    /* Get TX available count */
    txAvailable = *(int *)(((char *)self) + 0x1CC);

    /* While we have available TCBs, dequeue and transmit packets */
    while (txAvailable != 0) {
        /* Dequeue a packet */
        packet = [txQueue dequeue];

        if (packet == NULL) {
            /* Queue is empty */
            break;
        }

        /* Transmit the packet */
        [self __transmitPacket:packet];

        /* Reload TX available count (may have been updated by __transmitPacket) */
        txAvailable = *(int *)(((char *)self) + 0x1CC);
    }
}

/*
 * Receive packet - Polled packet reception with timeout
 * Used primarily for debugger/boot scenarios
 *
 * param data: Buffer to receive packet data
 * param maxlen: Pointer to maximum length, updated with actual length received
 * param timeout: Timeout in milliseconds
 * Returns: Number of bytes received, 0 if timeout or error
 *
 * Instance variables:
 *   +0x1E8: RFD base pointer
 *   +0x1F0: RFD count (total number of RFDs)
 *   +0x1F4: Current RFD index
 */
- (unsigned int)receivePacket:(void *)data length:(unsigned int)maxlen timeout:(unsigned int)timeout
{
    unsigned char *rfdBase;
    unsigned char *currentRfd;
    unsigned int rfdCount;
    unsigned int currentIndex;
    unsigned short status;
    unsigned short actualCount;
    BOOL frameComplete;
    BOOL frameOk;
    unsigned int elapsed;
    unsigned int rfdSize = 0x48;  /* RFD size is 72 bytes (0x48) */
    void *packetData;
    unsigned int bytesToCopy;

    /* Get RFD base pointer */
    rfdBase = *(unsigned char **)(((char *)self) + 0x1E8);
    if (!rfdBase) {
        return 0;
    }

    /* Get current RFD index */
    currentIndex = *(unsigned int *)(((char *)self) + 0x1F4);

    /* Get total RFD count */
    rfdCount = *(unsigned int *)(((char *)self) + 0x1F0);

    /* Poll for packet with timeout */
    elapsed = 0;
    while (elapsed < timeout) {
        /* Calculate current RFD address */
        currentRfd = rfdBase + (currentIndex * rfdSize);

        /* Read status word at offset +0 */
        status = *(unsigned short *)currentRfd;

        /* Check if frame is complete (bit 15 - 0x8000) */
        frameComplete = (status & 0x8000) != 0;

        if (frameComplete) {
            /* Check if frame is OK (bit 13 - 0x2000) */
            frameOk = (status & 0x2000) != 0;

            /* Get actual count (at offset +2, lower 14 bits) */
            actualCount = *(unsigned short *)(currentRfd + 2) & 0x3FFF;

            if (frameOk && actualCount > 0) {
                /* Get the netbuf pointer from RFD at offset +0x10 */
                netbuf_t packet = *(netbuf_t *)(currentRfd + 0x10);

                if (packet != NULL) {
                    /* Get data pointer from netbuf */
                    packetData = nb_map(packet);

                    if (packetData != NULL) {
                        /* Copy packet data to user buffer */
                        bytesToCopy = actualCount;
                        if (bytesToCopy > maxlen) {
                            bytesToCopy = maxlen;
                        }

                        bcopy(packetData, data, bytesToCopy);

                        /* Clear status word to mark RFD as ready for reuse */
                        *(unsigned short *)currentRfd = 0;

                        /* Clear count field */
                        *(unsigned short *)(currentRfd + 2) = 0;

                        /* Set size field at offset +8 (RBD size = 1518 bytes) */
                        *(unsigned short *)(currentRfd + 8) = 0x8000 | 1518;  /* EOF bit | size */

                        /* Move to next RFD */
                        currentIndex++;
                        if (currentIndex >= rfdCount) {
                            currentIndex = 0;
                        }

                        /* Store updated index */
                        *(unsigned int *)(((char *)self) + 0x1F4) = currentIndex;

                        return bytesToCopy;
                    }
                }
            }

            /* Frame was bad or had errors - skip it */
            /* Clear status word */
            *(unsigned short *)currentRfd = 0;

            /* Clear count field */
            *(unsigned short *)(currentRfd + 2) = 0;

            /* Set size field */
            *(unsigned short *)(currentRfd + 8) = 0x8000 | 1518;

            /* Move to next RFD */
            currentIndex++;
            if (currentIndex >= rfdCount) {
                currentIndex = 0;
            }

            /* Store updated index */
            *(unsigned int *)(((char *)self) + 0x1F4) = currentIndex;
        }

        /* No packet yet, delay and continue */
        IODelay(1000);  /* 1ms delay */
        elapsed++;
    }

    /* Timeout - no packet received */
    return 0;
}

/*
 * Allocate network buffer
 * Allocates a 1518-byte buffer, ensures 4-byte alignment, and shrinks to 1514 bytes
 */
- (netbuf_t)allocateNetbuf
{
    netbuf_t nb;
    void *data;
    unsigned int addr;
    unsigned int size;
    unsigned int alignOffset;

    /* Allocate 1518-byte buffer (0x5EE) */
    nb = nb_alloc(0x5EE);
    if (nb == NULL) {
        return NULL;
    }

    /* Map buffer to get virtual address */
    data = nb_map(nb);
    addr = (unsigned int)data;

    /* Check if address is 4-byte aligned */
    if ((addr & 3) != 0) {
        /* Calculate offset needed to align to 4-byte boundary */
        alignOffset = ((addr + 3) & 0xFFFFFFFC) - addr;

        /* Shrink top by alignment offset to align the buffer */
        nb_shrink_top(nb, alignOffset);
    }

    /* Get current size */
    size = nb_size(nb);

    /* Shrink bottom to get exactly 1514 bytes (0x5EA) */
    nb_shrink_bot(nb, size - 0x5EA);

    return nb;
}

/*
 * Get power management
 * Returns: IO_R_UNSUPPORTED (0xFFFFFD39) - power management not supported
 */
- (IOReturn)getPowerManagement:(void *)powerManagement
{
    return 0xFFFFFD39;  /* IO_R_UNSUPPORTED */
}

/*
 * Get power state
 * Returns: IO_R_UNSUPPORTED (0xFFFFFD39) - power management not supported
 */
- (IOReturn)getPowerState:(void *)powerState
{
    return 0xFFFFFD39;  /* IO_R_UNSUPPORTED */
}

/*
 * Set power management
 * Returns: IO_R_UNSUPPORTED (0xFFFFFD39) - power management not supported
 */
- (IOReturn)setPowerManagement:(unsigned int)powerLevel
{
    return 0xFFFFFD39;  /* IO_R_UNSUPPORTED */
}

/*
 * Set power state
 * If state is 3 (power down), performs shutdown sequence
 *
 * param state: Power state to set (3 = power down)
 * Returns: IO_R_SUCCESS if state is 3, IO_R_UNSUPPORTED otherwise
 */
- (IOReturn)setPowerState:(unsigned int)state
{
    IOReturn result;

    if (state == 3) {
        /* Power down sequence */

        /* Abort receive unit */
        [self __abortReceiveUnit];

        /* Clear any pending timeout */
        [self clearTimeout];

        /* Disable adapter interrupts */
        [self disableAdapterInterrupts];

        /* Send selective reset port command (0, 0) */
        [self sendPortCommand:0 with:0];

        result = 0;  /* IO_R_SUCCESS */
    } else {
        /* State not supported */
        result = 0xFFFFFD39;  /* IO_R_UNSUPPORTED */
    }

    return result;
}

/*
 * Send channel attention
 * Base class implementation - does nothing
 * Bus-specific variants (EISA/PCI) will override this method
 */
- (void)sendChannelAttention
{
    /* Base class stub - bus variants will override */
    return;
}

/*
 * Send port command
 * Base class implementation - does nothing
 * Bus-specific variants (EISA/PCI) will override this method
 */
- (int)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg
{
    /* Base class stub - bus variants will override */
    return 0;
}

/*
 * Get Ethernet address
 * Base class implementation - does nothing
 * Bus-specific variants (EISA/PCI) will override this method to read MAC from EEPROM
 */
- (BOOL)getEthernetAddress
{
    /* Base class stub - bus variants will override */
    return YES;
}

/*
 * NOP command
 */
/*
 * NOP command
 * param timeout: If 0, simple NOP. If non-zero, NOP with interrupt test
 * Returns: YES if successful, NO if failed
 *
 * Instance variables:
 *   +0x1B8: SCB base
 *   +0x1C0: Config block (used as command block)
 *   +0x1C4: Config block physical address
 */
- (BOOL)nop:(unsigned int)timeout
{
    void *cmdBlock;
    unsigned char *cmdBytes;
    unsigned short *scbStatus;
    const char *driverName;
    int delay;
    BOOL checkInterrupt;

    /* Get command block pointer */
    cmdBlock = *(void **)(((char *)self) + 0x1C0);

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return NO;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:100]) {
        return NO;
    }

    /* Clear command block (8 bytes for NOP command) */
    bzero(cmdBlock, 8);

    cmdBytes = (unsigned char *)cmdBlock;

    /* Byte +2: Command word (low byte) */
    cmdBytes[2] = cmdBytes[2] & 0xF8;  /* Command = NOP (0) */

    /* Byte +3: Command word (high byte) */
    cmdBytes[3] |= 0x80;  /* Set suspend bit */

    /* Set/clear interrupt bit based on timeout parameter */
    if (timeout & 1) {
        cmdBytes[3] |= 0x20;  /* Set interrupt bit (bit 5) */
    } else {
        cmdBytes[3] &= 0xDF;  /* Clear interrupt bit */
    }

    /* Bytes +4-7: Link pointer (set to -1 = end of list) */
    *(unsigned int *)&cmdBytes[4] = 0xFFFFFFFF;

    /* Set command block physical address in SCB general pointer */
    *(unsigned int *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 4) =
        *(unsigned int *)(((char *)self) + 0x1C4);

    /* Clear SCB command word */
    *(unsigned short *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 2) = 0;

    /* Set CU command to START (1) */
    *(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) =
        (*(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) & 0xF8) | 0x01;

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for NOP to complete (check status bit 7) */
    for (delay = 0; delay < 2000; delay++) {
        IODelay(1000);
        if ((cmdBytes[1] & 0x80) != 0) {
            break;
        }
    }

    if ((cmdBytes[1] & 0x80) != 0) {
        /* NOP completed */
        if (timeout == 0) {
            return YES;
        }

        /* Check if interrupt was generated (bit 3 of SCB status high byte) */
        scbStatus = (unsigned short *)*(void **)(((char *)self) + 0x1B8);
        checkInterrupt = ((scbStatus[0] >> 4) & 0x08) == 0;

        if (checkInterrupt) {
            driverName = [[self name] cString];
            IOLog("%s: nop interrupt not set status 0x%x command 0x%x\n",
                  driverName, scbStatus[0], scbStatus[1]);
        }

        checkInterrupt = !checkInterrupt;

        /* Acknowledge interrupt if any status bits are set */
        if ((scbStatus[0] & 0xF000) != 0) {
            [self acknowledgeInterrupts:scbStatus[0]];
        }

        return checkInterrupt;
    }

    driverName = [[self name] cString];
    IOLog("%s: nop command failed\n", driverName);
    return NO;
}

/*
 * Dump statistics from the 82556 chip
 * param buffer: Pointer to buffer where statistics will be stored
 * Returns: YES if successful, NO if failed
 *
 * Instance variables:
 *   +0x1B8: SCB base
 *   +0x1C0: Config block (used as command block)
 *   +0x1C4: Config block physical address
 */
- (BOOL)dump:(void *)buffer
{
    void *cmdBlock;
    unsigned char *cmdBytes;
    unsigned int bufferPhysAddr;
    const char *driverName;
    IOTask vmTask;
    int timeout;
    int result;

    /* Get command block pointer */
    cmdBlock = *(void **)(((char *)self) + 0x1C0);

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return NO;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:100]) {
        return NO;
    }

    /* Clear command block (12 bytes for dump command) */
    bzero(cmdBlock, 0x0C);

    cmdBytes = (unsigned char *)cmdBlock;

    /* Byte +2: Command word (low byte) */
    cmdBytes[2] = (cmdBytes[2] & 0xF8) | 0x06;  /* Command = DUMP (6) */

    /* Byte +3: Command word (high byte) */
    cmdBytes[3] |= 0x80;  /* Set suspend bit */

    /* Bytes +4-7: Link pointer (set to -1 = end of list) */
    *(unsigned int *)&cmdBytes[4] = 0xFFFFFFFF;

    /* Get physical address of dump buffer and store at offset +8 */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask,
                                   (vm_address_t)buffer,
                                   (unsigned int *)&cmdBytes[8]);
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: invalid dump area pointer\n", driverName);
        return NO;
    }

    /* Set command block physical address in SCB general pointer */
    *(unsigned int *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 4) =
        *(unsigned int *)(((char *)self) + 0x1C4);

    /* Clear SCB command word */
    *(unsigned short *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 2) = 0;

    /* Set CU command to START (1) */
    *(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) =
        (*(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) & 0xF8) | 0x01;

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for dump to complete (check status bit 7 in command block byte +1) */
    for (timeout = 0; timeout < 4000; timeout++) {
        IODelay(1000);
        if ((cmdBytes[1] & 0x80) != 0) {
            break;
        }
    }

    if ((cmdBytes[1] & 0x80) != 0) {
        /* Dump succeeded */
        return YES;
    }

    driverName = [[self name] cString];
    IOLog("%s: dump command failed\n", driverName);
    return NO;
}

/*
 * Set throttle timers
 * Configures interrupt throttling timers in the 82556
 *
 * Instance variables:
 *   +0x1B8: SCB base pointer
 *
 * SCB structure:
 *   +0x00: Status word
 *   +0x02: Command word
 *   +0x03: Command byte (high byte of command word)
 *   +0x24: Interrupt delay timer (set to 2)
 *   +0x26: Bundle timer (set to 0x7D = 125)
 */
- (BOOL)setThrottleTimers
{
    void *scbBase;
    unsigned char *scbCmd;
    unsigned char *scbStatus;
    const char *driverName;
    int timeout;

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return NO;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:100]) {
        return NO;
    }

    /* Get SCB base */
    scbBase = *(void **)(((char *)self) + 0x1B8);

    /* Clear SCB command word at offset +2 */
    *(unsigned short *)((char *)scbBase + 2) = 0;

    /* Set CU command to 6 (Load CU Base / throttle timers) */
    scbCmd = (unsigned char *)((char *)scbBase + 3);
    *scbCmd = (*scbCmd & 0xF8) | 0x06;

    /* Set interrupt delay timer at offset +0x24 to 2 */
    *(unsigned short *)((char *)scbBase + 0x24) = 2;

    /* Set bundle timer at offset +0x26 to 0x7D (125) */
    *(unsigned short *)((char *)scbBase + 0x26) = 0x7D;

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for status bit 3 (0x08) to be set */
    scbStatus = (unsigned char *)scbBase;
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);  /* 1ms delay */

        if ((*scbStatus & 0x08) != 0) {
            /* Command completed successfully */
            return YES;
        }
    }

    /* Timeout - command failed */
    driverName = [[self name] cString];
    IOLog("%s: set throttle timers timed out\n", driverName);

    return NO;
}

/*
 * Lock DBRT
 * Base class implementation - does nothing
 * Bus-specific variants may override this method
 */
- (BOOL)lockDBRT
{
    /* Base class stub - bus variants may override */
    return YES;
}

/*
 * Initialize PLX chip
 * Base class implementation - does nothing
 * Bus-specific variants (EISA) may override this method for PLX bridge
 */
- (void)initPLXchip
{
    /* Base class stub - bus variants may override */
}

/*
 * Reset PLX chip
 * Base class implementation - does nothing
 * Bus-specific variants (EISA) may override this method for PLX bridge
 */
- (void)resetPLXchip
{
    /* Base class stub - bus variants may override */
    return;
}

@end

/* Private category implementation */
@implementation Intel82556(Intel82556Private)

/*
 * Private hardware initialization
 * Initializes the 82556 chip hardware - sets up SCP, ISCP, SCB structures
 * Returns: YES if successful, NO if failed
 */
- (BOOL)__hwInit
{
    void *scpBase;      /* System Control Block Pointer */
    void *iscpBase;     /* Intermediate System Control Block Pointer */
    void *scbBase;      /* System Control Block */
    unsigned char *scbCommand;
    unsigned int physAddr;
    int timeout;
    const char *driverName;
    IOTask vmTask;
    int result;

    /* Clear IRQ latch */
    [self clearIrqLatch];

    /* Disable adapter interrupts */
    [self disableAdapterInterrupts];

    /* Reset PLX chip */
    [self resetPLXchip];

    /* Sleep 150ms */
    IOSleep(150);

    /* Get Ethernet address from EEPROM */
    [self getEthernetAddress];

    /* Initialize PLX chip */
    [self initPLXchip];

    /* Issue port reset command (command 0, arg 0) */
    [self sendPortCommand:0 with:0];

    /* Sleep 250ms */
    IOSleep(250);

    /* Get pointers to control structures (offsets 0x1B0, 0x1B4, 0x1B8) */
    scpBase = *(void **)(((char *)self) + 0x1B0);
    iscpBase = *(void **)(((char *)self) + 0x1B4);
    scbBase = *(void **)(((char *)self) + 0x1B8);

    /* Initialize SCP (System Control Block Pointer) - 12 bytes */
    bzero(scpBase, 0x0C);

    /* Set SCP fields */
    scbCommand = (unsigned char *)scpBase + 2;
    *scbCommand |= 0x40;  /* Bus width */
    *scbCommand &= 0xF9;  /* Clear bits */
    *scbCommand |= 0x04;  /* Set bit 2 */
    *scbCommand |= 0x10;  /* Set bit 4 */

    /* Get physical address of SCB and store in SCP+8 */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask, (vm_address_t)((char *)scpBase + 8), &physAddr);
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid SCP address\n", driverName);
        return NO;
    }

    /* Initialize ISCP (Intermediate System Control Block Pointer) - 8 bytes */
    bzero(iscpBase, 0x08);

    /* Set ISCP busy flag */
    *(unsigned char *)iscpBase = 1;

    /* Get physical address of SCB and store in ISCP+4 */
    result = IOPhysicalFromVirtual(vmTask, (vm_address_t)((char *)iscpBase + 4), &physAddr);
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid SCB address\n", driverName);
        return NO;
    }

    /* Initialize SCB (System Control Block) - 44 bytes */
    bzero(scbBase, 0x2C);

    /* Get physical address of SCP */
    result = IOPhysicalFromVirtual(vmTask, (vm_address_t)scpBase, &physAddr);
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid ISCP address\n", driverName);
        return NO;
    }

    /* Send port command 2 (set SCP address) with physical address */
    [self sendPortCommand:2 with:physAddr];

    /* Sleep 150ms */
    IOSleep(150);

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for ISCP busy flag to clear (up to 2000ms) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);  /* 1ms delay */

        if (*(unsigned char *)iscpBase == 0) {
            /* Busy flag cleared */
            break;
        }
    }

    if (*(unsigned char *)iscpBase != 0) {
        /* Timeout */
        driverName = [[self name] cString];
        IOLog("%s: 82556 initialization timed out\n", driverName);
        return NO;
    }

    /* Acknowledge any pending interrupts */
    scbBase = *(void **)(((char *)self) + 0x1B8);
    if (![self acknowledgeInterrupts:*(unsigned short *)scbBase]) {
        return NO;
    }

    /* Sleep 150ms */
    IOSleep(150);

    /* Clear IRQ latch */
    [self clearIrqLatch];

    /* Sleep 150ms */
    IOSleep(150);

    /* Set throttle timers */
    if (![self setThrottleTimers]) {
        return NO;
    }

    /* Sleep 150ms */
    IOSleep(150);

    /* Configure the adapter */
    if (![self config]) {
        return NO;
    }

    /* Sleep 500ms */
    IOSleep(500);

    return YES;
}

/*
 * Self test - Run 82556 hardware self-test
 * Returns: YES if successful, NO if failed
 *
 * Self-test structure (at offset 0x1BC):
 *   +0x00: Signature (0xFFFFFFFF initially)
 *   +0x04: Results (0xFFFF = running)
 *   +0x06: Status
 *
 * Result bits (offset +4):
 *   Bit 3: ROM contents invalid
 *   Bit 2: Internal register failure
 *   Bit 4: Bus throttle timer failure
 *   Bit 5: Serial subsystem failure
 *
 * Status bits (offset +5):
 *   Bit 4: General failure
 */
- (BOOL)__selfTest
{
    void *selfTestArea;
    unsigned short *resultField;
    unsigned char *statusByte;
    unsigned int physAddr;
    const char *driverName;
    IOTask vmTask;
    int timeout;
    int result;

    /* Get self-test area pointer at offset 0x1BC */
    selfTestArea = *(void **)(((char *)self) + 0x1BC);

    /* Get physical address of self-test area */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask, (vm_address_t)selfTestArea, &physAddr);
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid self test area address\n", driverName);
        return NO;
    }

    /* Initialize self-test area */
    *(unsigned int *)selfTestArea = 0xFFFFFFFF;  /* Signature */
    *(unsigned short *)((char *)selfTestArea + 4) = 0xFFFF;  /* Results = running */
    *(unsigned short *)((char *)selfTestArea + 6) = 0;  /* Status */

    /* Send port command 1 (self-test) with physical address */
    [self sendPortCommand:1 with:physAddr];

    /* Wait for self-test to complete (up to 2000ms) */
    resultField = (unsigned short *)((char *)selfTestArea + 4);
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);  /* 1ms delay */

        if (*resultField != 0xFFFF) {
            /* Self-test completed */
            break;
        }
    }

    /* Check if timed out */
    if (*resultField == 0xFFFF) {
        driverName = [[self name] cString];
        IOLog("%s: Self test timed out\n", driverName);
        return NO;
    }

    /* Check if passed (result == 0) */
    if (*resultField == 0) {
        return YES;
    }

    /* Self-test failed - report specific errors */
    driverName = [[self name] cString];

    if ((*(unsigned char *)((char *)selfTestArea + 4) & 0x08) != 0) {
        IOLog("%s: Self test reports invalid ROM contents\n", driverName);
    }

    if ((*(unsigned char *)((char *)selfTestArea + 4) & 0x04) != 0) {
        IOLog("%s: Self test reports internal register failure\n", driverName);
    }

    if ((*(unsigned char *)((char *)selfTestArea + 4) & 0x10) != 0) {
        IOLog("%s: Self test reports bus throttle timer failure\n", driverName);
    }

    if ((*(unsigned char *)((char *)selfTestArea + 4) & 0x20) != 0) {
        IOLog("%s: Self test reports serial subsystem failure\n", driverName);
    }

    /* Check general failure bit in status byte */
    statusByte = (unsigned char *)((char *)selfTestArea + 5);
    if ((*statusByte & 0x10) == 0) {
        return NO;
    }

    IOLog("%s: Self test failed\n", driverName);
    return NO;
}

/*
 * Schedule reset - Abort receive, clear queues, schedule reset function
 * Uses IOScheduleFunc to schedule the reset callback
 *
 * Instance variables:
 *   +0x18C: Transmit queue object
 */
- (void)__scheduleReset
{
    id txQueue;
    netbuf_t packet;

    /* Abort receive unit */
    [self __abortReceiveUnit];

    /* Clear timeout */
    [self clearTimeout];

    /* Get transmit queue at offset 0x18C */
    txQueue = *(id *)(((char *)self) + 0x18C);

    /* Dequeue and free all pending packets */
    while (YES) {
        packet = (netbuf_t)[txQueue dequeue];
        if (packet == NULL) {
            break;
        }
        nb_free(packet);
    }

    /* Schedule reset function (0x164 = __resetFunc function pointer) */
    /* Parameters: function, argument, delay (1 = immediate) */
    IOScheduleFunc((IOThreadFunc)__resetFunc, self, 1);
}

/*
 * Wait for SCB command register to clear
 * Returns: YES if cleared, NO if timeout
 *
 * Waits up to 65535 microseconds for SCB command word to become 0
 */
- (BOOL)__waitScb
{
    void *scbBase;
    unsigned short *scbCommand;
    const char *driverName;
    int timeout;

    /* Get SCB base pointer */
    scbBase = *(void **)(((char *)self) + 0x1B8);

    /* SCB command word is at offset +2 */
    scbCommand = (unsigned short *)((char *)scbBase + 2);

    /* Wait for command word to clear */
    for (timeout = 0; timeout < 0xFFFF; timeout++) {
        if (*scbCommand == 0) {
            return YES;
        }
        IODelay(1);  /* 1 microsecond delay */
    }

    /* Timeout */
    driverName = [[self name] cString];
    IOLog("%s: timeout waiting for scb command to clear\n", driverName);

    return NO;
}

/*
 * Wait for command unit to become inactive
 * param timeout: Timeout in milliseconds
 * Returns: YES if inactive, NO if timeout
 *
 * Checks SCB status byte +1, bits 0-2 for CU state
 * State 2 = CU active, we wait until != 2
 */
- (BOOL)__waitCu:(unsigned int)timeout
{
    void *scbBase;
    unsigned char *scbStatus;
    const char *driverName;
    unsigned int delay;
    unsigned int maxDelay;

    /* Calculate max delay in microseconds (timeout * 1000) */
    maxDelay = (timeout * 0x7D) & 0x1FFFFFFF;  /* timeout * 125 microseconds */

    if (maxDelay == 0) {
        return YES;
    }

    /* Get SCB base pointer */
    scbBase = *(void **)(((char *)self) + 0x1B8);

    /* SCB status byte is at offset +1 */
    scbStatus = (unsigned char *)((char *)scbBase + 1);

    /* Wait for CU to become inactive (bits 0-2 != 2) */
    for (delay = 0; delay < timeout * 1000; delay++) {
        if ((*scbStatus & 0x07) != 2) {
            return YES;
        }
        IODelay(1);  /* 1 microsecond delay */
    }

    /* Timeout */
    driverName = [[self name] cString];
    IOLog("%s: timeout waiting for command unit to become inactive\n", driverName);

    return NO;
}

/*
 * Allocate memory from shared memory pool
 * param size: Size in bytes to allocate
 * Returns: Pointer to allocated memory
 *
 * Memory pool structure (instance variables):
 *   +0x198: Base pointer of shared memory
 *   +0x1A0: Current allocation pointer
 *   +0x1A4: Remaining free space
 */
- (void *)__memAlloc:(unsigned int)size
{
    void *allocatedPtr;
    unsigned int alignedPtr;

    /* Check if enough memory available */
    if (*(unsigned int *)(((char *)self) + 0x1A4) < size) {
        IOPanic("Intel82556: shared memory exhausted\n");
    }

    /* Get current allocation pointer */
    allocatedPtr = *(void **)(((char *)self) + 0x1A0);

    /* Advance allocation pointer */
    *(unsigned int *)(((char *)self) + 0x1A0) += size;

    /* Align to 4-byte boundary */
    if ((*(unsigned char *)(((char *)self) + 0x1A0) & 3) != 0) {
        alignedPtr = (*(unsigned int *)(((char *)self) + 0x1A0) + 3) & 0xFFFFFFFC;
        *(unsigned int *)(((char *)self) + 0x1A0) = alignedPtr;
    }

    /* Update remaining free space */
    *(int *)(((char *)self) + 0x1A4) =
        __page_size - (*(int *)(((char *)self) + 0x1A0) - *(int *)(((char *)self) + 0x198));

    return allocatedPtr;
}

/*
 * Initialize TCB (Transmit Command Block) list
 * Returns: YES if successful, NO if failed
 *
 * TCB structure (0x44 bytes each, 16 total = 0x440 bytes):
 *   +0x00-0x1B: TCB header
 *   +0x1C: Physical address of TCB (for DMA)
 *   +0x18: Link to next TCB
 *   +0x20-0x2F: TBD 0 (Transmit Buffer Descriptor)
 *   +0x30-0x3F: TBD 1
 *   +0x40: Netbuf pointer
 *
 * Instance variables:
 *   +0x1B8: SCB base pointer
 *   +0x1C8: TCB list base pointer
 *   +0x1CC: TCB head pointer
 *   +0x1D0-0x1D8: Queue management
 */
- (BOOL)__initTcbList
{
    unsigned char *scbStatus;
    void *tcbBase;
    int tcbIndex;
    int tcbOffset;
    int tbdIndex;
    int tbdOffset;
    netbuf_t existingNetbuf;
    unsigned int physAddr;
    const char *driverName;
    IOTask vmTask;
    int result;

    /* Get SCB status byte at offset +1 from SCB base */
    scbStatus = (unsigned char *)(*(unsigned int *)(((char *)self) + 0x1B8) + 1);

    /* Check if command unit is active (bit 1) */
    if ((*scbStatus & 0x02) != 0) {
        driverName = [[self name] cString];
        IOLog("%s: _initTcbList called while command unit active\n", driverName);
        [self __waitCu:100];
    }

    /* Get TCB list base pointer */
    tcbBase = *(void **)(((char *)self) + 0x1C8);

    /* Free any existing netbufs in TCB list (16 entries) */
    for (tcbIndex = 0; tcbIndex < 0x10; tcbIndex++) {
        tcbOffset = tcbIndex * 0x44;
        existingNetbuf = *(netbuf_t *)((char *)tcbBase + 0x40 + tcbOffset);

        if (existingNetbuf != NULL) {
            nb_free(existingNetbuf);
            *(netbuf_t *)((char *)tcbBase + 0x40 + tcbOffset) = NULL;
        }
    }

    /* Clear entire TCB area (16 * 0x44 = 0x440 bytes) */
    bzero(tcbBase, 0x440);

    /* Initialize each TCB and its TBDs */
    for (tcbIndex = 0; tcbIndex < 0x10; tcbIndex++) {
        tcbOffset = tcbIndex * 0x44;

        /* Get physical address for TCB (offset +0x1C stores phys addr) */
        vmTask = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(vmTask,
                                       (vm_address_t)((char *)tcbBase + tcbOffset),
                                       (unsigned int *)((char *)tcbBase + tcbOffset + 0x1C));
        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Invalid TCB address\n", driverName);
            return NO;
        }

        /* Get physical addresses for 2 TBDs per TCB */
        for (tbdIndex = 0; tbdIndex < 2; tbdIndex++) {
            tbdOffset = tcbOffset + 0x20 + (tbdIndex * 0x10);

            result = IOPhysicalFromVirtual(vmTask,
                                           (vm_address_t)((char *)tcbBase + tbdOffset),
                                           (unsigned int *)((char *)tcbBase + tbdOffset + 0x0C));
            if (result != 0) {
                driverName = [[self name] cString];
                IOLog("%s: Invalid TBD address\n", driverName);
                return NO;
            }
        }

        /* Set up linked list - last TCB (index 15) has NULL link */
        if (tcbIndex == 0x0F) {
            *(unsigned int *)((char *)tcbBase + 0x414) = 0;  /* Offset for last TCB's link field */
        } else {
            *(void **)((char *)tcbBase + 0x18 + tcbOffset) =
                (char *)tcbBase + tcbOffset + 0x44;  /* Link to next TCB */
        }
    }

    /* Initialize TCB queue management pointers */
    *(void **)(((char *)self) + 0x1CC) = tcbBase;  /* Head pointer */
    *(unsigned int *)(((char *)self) + 0x1D8) = 0;
    *(unsigned int *)(((char *)self) + 0x1D4) = 0;
    *(unsigned int *)(((char *)self) + 0x1D0) = 0;

    return YES;
}

/*
 * Initialize RFD (Receive Frame Descriptor) list
 * Returns: YES if successful, NO if failed
 *
 * RFD structure (0x48 bytes each, 64 total = 0x1200 bytes):
 *   +0x00: Status
 *   +0x02: Command
 *   +0x04: Link to next RFD (physical)
 *   +0x08: RBD pointer (physical)
 *   +0x20: Link to next RFD (virtual)
 *   +0x24: Physical address of this RFD
 *   +0x28: RBD structure start
 *   +0x2C: RBD buffer physical address
 *   +0x30: RBD buffer virtual address
 *   +0x34: RBD size
 *   +0x3C: Link to next RBD (virtual)
 *   +0x40: RBD physical address
 *   +0x44: Netbuf pointer
 *
 * Instance variables:
 *   +0x1B8: SCB base pointer
 *   +0x1E8: RFD list base pointer
 *   +0x1EC: RFD head pointer
 *   +0x1F0: RFD tail pointer
 */
- (BOOL)__initRfdList
{
    unsigned char *scbStatus;
    void *rfdBase;
    int rfdIndex;
    int rfdOffset;
    unsigned char *rfdCommand;
    unsigned short *rbdSize;
    netbuf_t existingNetbuf;
    netbuf_t newNetbuf;
    void *netbufData;
    unsigned int physAddr;
    const char *driverName;
    IOTask vmTask;
    int result;

    /* Get SCB status byte */
    scbStatus = *(unsigned char **)(((char *)self) + 0x1B8);

    /* Check if receive unit is ready (bits 4-7, shifted >> 4 & 0xC) */
    if (((*scbStatus >> 4) & 0x0C) != 0) {
        driverName = [[self name] cString];
        IOLog("%s: _initRfdList called while receive unit ready\n", driverName);
        [self __abortReceiveUnit];
    }

    /* Get RFD list base pointer */
    rfdBase = *(void **)(((char *)self) + 0x1E8);

    /* Free any existing netbufs in RFD list (64 entries) */
    for (rfdIndex = 0; rfdIndex < 0x40; rfdIndex++) {
        rfdOffset = rfdIndex * 0x48;
        existingNetbuf = *(netbuf_t *)((char *)rfdBase + 0x44 + rfdOffset);

        if (existingNetbuf != NULL) {
            nb_free(existingNetbuf);
            *(netbuf_t *)((char *)rfdBase + 0x44 + rfdOffset) = NULL;
        }
    }

    /* Clear entire RFD area (64 * 0x48 = 0x1200 bytes) */
    bzero(rfdBase, 0x1200);

    /* First loop: Set suspend bits and get physical addresses */
    vmTask = IOVmTaskSelf();

    for (rfdIndex = 0; rfdIndex < 0x40; rfdIndex++) {
        rfdOffset = rfdIndex * 0x48;

        /* Set suspend bit (bit 3) in command byte at offset +2 */
        rfdCommand = (unsigned char *)((char *)rfdBase + 2 + rfdOffset);
        *rfdCommand |= 0x08;

        /* Get physical address of RFD and store at offset +0x24 */
        result = IOPhysicalFromVirtual(vmTask,
                                       (vm_address_t)((char *)rfdBase + rfdOffset),
                                       (unsigned int *)((char *)rfdBase + rfdOffset + 0x24));
        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Invalid RFD address\n", driverName);
            return NO;
        }

        /* Get physical address of RBD and store at offset +0x40 */
        result = IOPhysicalFromVirtual(vmTask,
                                       (vm_address_t)((char *)rfdBase + rfdOffset + 0x28),
                                       (unsigned int *)((char *)rfdBase + rfdOffset + 0x40));
        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Invalid RBD address\n", driverName);
            return NO;
        }
    }

    /* Second loop: Set up linked list and allocate buffers */
    for (rfdIndex = 0; rfdIndex < 0x40; rfdIndex++) {
        rfdOffset = rfdIndex * 0x48;

        if (rfdIndex == 0x3F) {
            /* Last RFD - set EL bit (bit 7) in command at offset 0x11BB */
            rfdCommand = (unsigned char *)((char *)rfdBase + 0x11BB);
            *rfdCommand |= 0x80;

            /* Set link back to first RFD */
            *(void **)((char *)rfdBase + 0x11D8) = rfdBase;

            /* Set RFD size */
            *(unsigned short *)((char *)rfdBase + 0x11EE) = 1;

            /* Set RBD pointer */
            *(void **)((char *)rfdBase + 0x11F4) = (char *)rfdBase + 0x28;
        } else {
            /* Set virtual link to next RFD at offset +0x20 */
            *(void **)((char *)rfdBase + 0x20 + rfdOffset) =
                (char *)rfdBase + rfdOffset + 0x48;

            /* Set virtual link to next RBD at offset +0x3C */
            *(void **)((char *)rfdBase + 0x3C + rfdOffset) =
                (char *)rfdBase + rfdOffset + 0x48 + 0x28;
        }

        /* Copy physical address of next RFD to link field at offset +4 */
        *(unsigned int *)((char *)rfdBase + 4 + rfdOffset) =
            *(unsigned int *)((char *)((*(void **)((char *)rfdBase + 0x20 + rfdOffset)) + 0x24));

        /* Set RBD pointer at offset +8 */
        if (rfdIndex == 0) {
            *(unsigned int *)((char *)rfdBase + 8 + rfdOffset) =
                *(unsigned int *)((char *)rfdBase + 0x40);
        } else {
            *(unsigned int *)((char *)rfdBase + 8 + rfdOffset) = 0xFFFFFFFF;
        }

        /* Copy physical address of next RBD to link field at offset +0x2C */
        *(unsigned int *)((char *)rfdBase + 0x2C + rfdOffset) =
            *(unsigned int *)((char *)((*(void **)((char *)rfdBase + 0x3C + rfdOffset)) + 0x18));

        /* Set RBD size and flags at offset +0x34 */
        rbdSize = (unsigned short *)((char *)rfdBase + 0x34 + rfdOffset);
        *rbdSize &= 0xC000;  /* Clear size bits */
        *rbdSize |= 0x05EE;  /* Set size to 1518 bytes */

        /* Allocate netbuf for this RFD */
        newNetbuf = [self __recAllocateNetbuf];
        *(netbuf_t *)((char *)rfdBase + 0x44 + rfdOffset) = newNetbuf;

        if (newNetbuf == NULL) {
            driverName = [[self name] cString];
            IOLog("%s: receive buffer allocation failed\n", driverName);
        }

        /* Map netbuf and get physical address */
        netbufData = nb_map(newNetbuf);
        *(void **)((char *)rfdBase + 0x30 + rfdOffset) = netbufData;

        result = IOPhysicalFromVirtual(vmTask,
                                       (vm_address_t)netbufData,
                                       &physAddr);
        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Invalid RBD netbuf address\n", driverName);
            return NO;
        }
    }

    /* Set RFD head and tail pointers */
    *(void **)(((char *)self) + 0x1EC) = rfdBase;
    *(void **)(((char *)self) + 0x1F0) = (char *)rfdBase + 0x11B8;  /* Last RFD */

    return YES;
}

/*
 * Start transmit - Start the command unit with active TCB
 * Returns: YES if successful, NO if failed
 *
 * Instance variables:
 *   +0x1B8: SCB base pointer
 *   +0x1D0: Active TCB head pointer
 */
- (BOOL)__startTransmit
{
    unsigned char *scbCommand;
    void *activeTcbHead;
    unsigned int tcbPhysAddr;
    const char *driverName;

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        driverName = [[self name] cString];
        IOLog("%s: Cannot start transmit\n", driverName);
        return NO;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:100]) {
        driverName = [[self name] cString];
        IOLog("%s: Cannot start transmit\n", driverName);
        return NO;
    }

    /* Get active TCB head pointer at offset 0x1D0 */
    activeTcbHead = *(void **)(((char *)self) + 0x1D0);

    /* Validate active TCB head */
    if (activeTcbHead == NULL) {
        driverName = [[self name] cString];
        IOLog("%s: Attempt to start command unit with null activeTcbHead virtual or physical address\n",
              driverName);
        return NO;
    }

    /* Get physical address of TCB (stored at offset +0x1C) */
    tcbPhysAddr = *(unsigned int *)((char *)activeTcbHead + 0x1C);
    if (tcbPhysAddr == 0) {
        driverName = [[self name] cString];
        IOLog("%s: Attempt to start command unit with null activeTcbHead virtual or physical address\n",
              driverName);
        return NO;
    }

    /* Get SCB command register pointer */
    scbCommand = (unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 2);

    /* Clear command word */
    *(unsigned short *)scbCommand = 0;

    /* Set CU command to start (0x10 in CUC bits, which is byte +3) */
    *(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) =
        (*(unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 3) & 0xF8) | 0x01;

    /* Set TCB address in SCB general pointer (offset +4 from SCB) */
    *(unsigned int *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 4) = tcbPhysAddr;

    /* Send channel attention */
    [self sendChannelAttention];

    return YES;
}

/*
 * Transmit packet (internal)
 * Dequeues a TCB, sets up TBDs, and queues packet for transmission
 *
 * TCB structure (0x44 bytes):
 *   +0x00: Status word
 *   +0x02: Command word
 *   +0x04: Link to next TCB (physical)
 *   +0x08: TBD array pointer (physical)
 *   +0x0C: TCB count
 *   +0x0E: Transmit threshold
 *   +0x0F: TBD number
 *   +0x18: Link to next TCB (virtual)
 *   +0x1C: Physical address of this TCB
 *   +0x20: First TBD (0x10 bytes)
 *     +0x00: Buffer address (physical)
 *     +0x04: Size and end-of-list bit
 *     +0x08: Buffer address (virtual)
 *     +0x0C: TBD physical address
 *   +0x30: Second TBD (0x10 bytes)
 *   +0x40: Netbuf pointer
 *
 * Instance variables:
 *   +0x1C8: TCB list base
 *   +0x1CC: Free TCB head
 *   +0x1D0: Active TCB head
 *   +0x1D4: Free TCB count
 *   +0x1D8: Active TCB count
 */
- (void)__transmitPacket:(netbuf_t)packet
{
    void *freeTcbHead;
    void *nextFreeTcb;
    void *activeTcbHead;
    void *activeTcbTail;
    void *tcbBase;
    unsigned short *tcbCommand;
    unsigned short *tcbStatus;
    unsigned int *tbdPhysPtr;
    unsigned char *tcbThreshold;
    unsigned char *tcbCount;
    void *packetData;
    unsigned int packetSize;
    unsigned int physAddr;
    unsigned int isContiguous;
    unsigned int firstFragSize;
    unsigned int secondFragSize;
    void *firstFragAddr;
    void *secondFragAddr;
    unsigned short *tbdSize;
    unsigned int *tbdAddr;
    unsigned int freeTcbCount;
    unsigned int activeTcbCount;
    BOOL queueWasEmpty;
    const char *driverName;
    IOTask vmTask;
    int result;

    if (packet == NULL) {
        return;
    }

    /* Get free TCB head pointer at offset 0x1CC */
    freeTcbHead = *(void **)(((char *)self) + 0x1CC);

    /* Check if we have a free TCB */
    if (freeTcbHead == NULL) {
        driverName = [[self name] cString];
        IOLog("%s: No free TCBs available, dropping packet\n", driverName);
        nb_free(packet);
        return;
    }

    /* Get next free TCB (from virtual link at offset +0x18) */
    nextFreeTcb = *(void **)((char *)freeTcbHead + 0x18);

    /* Update free TCB head */
    *(void **)(((char *)self) + 0x1CC) = nextFreeTcb;

    /* Decrement free count at offset 0x1D4 */
    freeTcbCount = *(unsigned int *)(((char *)self) + 0x1D4);
    freeTcbCount--;
    *(unsigned int *)(((char *)self) + 0x1D4) = freeTcbCount;

    /* Map netbuf to get data pointer and size */
    packetData = nb_map(packet);
    packetSize = nb_size(packet);

    /* Check if packet buffer is physically contiguous */
    vmTask = IOVmTaskSelf();
    isContiguous = _IOIsPhysicallyContiguous((unsigned int)packetData, packetSize);

    /* Clear TCB status at offset +0x00 */
    tcbStatus = (unsigned short *)freeTcbHead;
    *tcbStatus = 0;

    /* Set TCB command at offset +0x02 */
    tcbCommand = (unsigned short *)((char *)freeTcbHead + 0x02);
    *tcbCommand = CB_CMD_TRANSMIT;  /* Command = 0x0004 (transmit) */
    *tcbCommand |= 0x8000;          /* Set suspend bit */
    *tcbCommand |= 0x4000;          /* Set interrupt bit */

    /* Clear virtual link at offset +0x18 */
    *(void **)((char *)freeTcbHead + 0x18) = NULL;

    /* Store netbuf pointer at offset +0x40 */
    *(netbuf_t *)((char *)freeTcbHead + 0x40) = packet;

    /* Set TCB byte count at offset +0x0C (always 0 for simplified mode) */
    tcbCount = (unsigned char *)((char *)freeTcbHead + 0x0C);
    *tcbCount = 0;

    /* Set transmit threshold at offset +0x0E (0xE0 = 224 bytes) */
    tcbThreshold = (unsigned char *)((char *)freeTcbHead + 0x0E);
    *tcbThreshold = 0xE0;

    if (isContiguous) {
        /* Packet is physically contiguous - use single TBD */

        /* Set TBD number at offset +0x0F (1 TBD) */
        *(unsigned char *)((char *)freeTcbHead + 0x0F) = 1;

        /* Get physical address of packet data */
        result = IOPhysicalFromVirtual(vmTask,
                                       (vm_address_t)packetData,
                                       &physAddr);
        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Cannot get physical address for packet\n", driverName);
            nb_free(packet);
            /* Return TCB to free list */
            *(void **)((char *)freeTcbHead + 0x18) = *(void **)(((char *)self) + 0x1CC);
            *(void **)(((char *)self) + 0x1CC) = freeTcbHead;
            *(unsigned int *)(((char *)self) + 0x1D4) = freeTcbCount + 1;
            return;
        }

        /* Set first TBD buffer address at offset +0x20 */
        tbdAddr = (unsigned int *)((char *)freeTcbHead + 0x20);
        *tbdAddr = physAddr;

        /* Set first TBD size at offset +0x24 with EOF bit */
        tbdSize = (unsigned short *)((char *)freeTcbHead + 0x24);
        *tbdSize = (unsigned short)(packetSize & 0x3FFF);  /* Size in lower 14 bits */
        *tbdSize |= 0x8000;  /* Set EOF (end-of-frame) bit */

        /* Store virtual address at offset +0x28 */
        *(void **)((char *)freeTcbHead + 0x28) = packetData;

        /* Set TBD array pointer at offset +0x08 to point to first TBD physical address */
        *(unsigned int *)((char *)freeTcbHead + 0x08) =
            *(unsigned int *)((char *)freeTcbHead + 0x20 + 0x0C);
    } else {
        /* Packet is not physically contiguous - use two TBDs */

        /* Set TBD number at offset +0x0F (2 TBDs) */
        *(unsigned char *)((char *)freeTcbHead + 0x0F) = 2;

        /* Calculate fragment sizes */
        /* First fragment: align to page boundary */
        firstFragSize = __page_size - ((unsigned int)packetData & __page_mask);
        if (firstFragSize > packetSize) {
            firstFragSize = packetSize;
        }
        secondFragSize = packetSize - firstFragSize;

        firstFragAddr = packetData;
        secondFragAddr = (void *)((unsigned char *)packetData + firstFragSize);

        /* Set up first TBD at offset +0x20 */
        result = IOPhysicalFromVirtual(vmTask,
                                       (vm_address_t)firstFragAddr,
                                       &physAddr);
        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Cannot get physical address for first fragment\n", driverName);
            nb_free(packet);
            *(void **)((char *)freeTcbHead + 0x18) = *(void **)(((char *)self) + 0x1CC);
            *(void **)(((char *)self) + 0x1CC) = freeTcbHead;
            *(unsigned int *)(((char *)self) + 0x1D4) = freeTcbCount + 1;
            return;
        }

        tbdAddr = (unsigned int *)((char *)freeTcbHead + 0x20);
        *tbdAddr = physAddr;

        tbdSize = (unsigned short *)((char *)freeTcbHead + 0x24);
        *tbdSize = (unsigned short)(firstFragSize & 0x3FFF);

        *(void **)((char *)freeTcbHead + 0x28) = firstFragAddr;

        /* Set up second TBD at offset +0x30 */
        result = IOPhysicalFromVirtual(vmTask,
                                       (vm_address_t)secondFragAddr,
                                       &physAddr);
        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Cannot get physical address for second fragment\n", driverName);
            nb_free(packet);
            *(void **)((char *)freeTcbHead + 0x18) = *(void **)(((char *)self) + 0x1CC);
            *(void **)(((char *)self) + 0x1CC) = freeTcbHead;
            *(unsigned int *)(((char *)self) + 0x1D4) = freeTcbCount + 1;
            return;
        }

        tbdAddr = (unsigned int *)((char *)freeTcbHead + 0x30);
        *tbdAddr = physAddr;

        tbdSize = (unsigned short *)((char *)freeTcbHead + 0x34);
        *tbdSize = (unsigned short)(secondFragSize & 0x3FFF);
        *tbdSize |= 0x8000;  /* Set EOF bit on last TBD */

        *(void **)((char *)freeTcbHead + 0x38) = secondFragAddr;

        /* Set TBD array pointer at offset +0x08 to point to first TBD physical address */
        *(unsigned int *)((char *)freeTcbHead + 0x08) =
            *(unsigned int *)((char *)freeTcbHead + 0x20 + 0x0C);
    }

    /* Add TCB to active queue */
    activeTcbHead = *(void **)(((char *)self) + 0x1D0);

    if (activeTcbHead == NULL) {
        /* Queue is empty - this becomes both head and tail */
        *(void **)(((char *)self) + 0x1D0) = freeTcbHead;
        queueWasEmpty = YES;
    } else {
        /* Queue not empty - find tail and link */
        void *currentTcb = activeTcbHead;
        void *nextTcb;

        /* Walk to end of active queue */
        while (1) {
            nextTcb = *(void **)((char *)currentTcb + 0x18);
            if (nextTcb == NULL) {
                break;
            }
            currentTcb = nextTcb;
        }

        /* Link previous tail to new TCB (both virtual and physical) */
        *(void **)((char *)currentTcb + 0x18) = freeTcbHead;
        *(unsigned int *)((char *)currentTcb + 0x04) =
            *(unsigned int *)((char *)freeTcbHead + 0x1C);

        /* Clear suspend bit on previous tail */
        tcbCommand = (unsigned short *)((char *)currentTcb + 0x02);
        *tcbCommand &= ~0x8000;

        queueWasEmpty = NO;
    }

    /* Increment active count at offset 0x1D8 */
    activeTcbCount = *(unsigned int *)(((char *)self) + 0x1D8);
    activeTcbCount++;
    *(unsigned int *)(((char *)self) + 0x1D8) = activeTcbCount;

    /* If queue was empty, start transmission */
    if (queueWasEmpty) {
        [self __startTransmit];
    }
}

/*
 * Start receive unit
 * Returns: YES if successful, NO if failed
 *
 * Instance variables:
 *   +0x1B8: SCB base pointer
 *   +0x1EC: RFD head pointer
 */
- (BOOL)__startReceiveUnit
{
    unsigned char *scbStatus;
    unsigned char *scbCommand;
    void *rfdHead;
    unsigned int rfdPhysAddr;
    unsigned int rbdPhysAddr;
    const char *driverName;
    int timeout;

    /* Get SCB status byte */
    scbStatus = *(unsigned char **)(((char *)self) + 0x1B8);

    /* Check if RU is already ready (status & 0xF0 == 0x40) */
    if ((*scbStatus & 0xF0) == 0x40) {
        driverName = [[self name] cString];
        IOLog("%s: receive unit is already ready\n", driverName);
        return YES;
    }

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return NO;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:100]) {
        return NO;
    }

    /* Get RFD head pointer */
    rfdHead = *(void **)(((char *)self) + 0x1EC);

    /* Validate RFD head and its physical addresses */
    if (rfdHead == NULL) {
        driverName = [[self name] cString];
        IOLog("%s: attempt to start receive unit with null virtual or physical RFD/RBD address\n",
              driverName);
        return NO;
    }

    /* Get physical address of RFD (stored at offset +0x24) */
    rfdPhysAddr = *(unsigned int *)((char *)rfdHead + 0x24);
    if (rfdPhysAddr == 0) {
        driverName = [[self name] cString];
        IOLog("%s: attempt to start receive unit with null virtual or physical RFD/RBD address\n",
              driverName);
        return NO;
    }

    /* Get physical address of RBD (stored at offset +0x40) */
    rbdPhysAddr = *(unsigned int *)((char *)rfdHead + 0x40);
    if (rbdPhysAddr == 0) {
        driverName = [[self name] cString];
        IOLog("%s: attempt to start receive unit with null virtual or physical RFD/RBD address\n",
              driverName);
        return NO;
    }

    /* Set RBD pointer in first RFD (offset +8) */
    *(unsigned int *)((char *)rfdHead + 8) = rbdPhysAddr;

    /* Set RFD address in SCB general pointer (offset +8 from SCB) */
    *(unsigned int *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 8) = rfdPhysAddr;

    /* Clear SCB command word */
    scbCommand = (unsigned char *)((char *)(*(void **)(((char *)self) + 0x1B8)) + 2);
    *(unsigned short *)scbCommand = 0;

    /* Set RU command to start (0x10 in RUC bits) while preserving CU command */
    *scbCommand = (*scbCommand & 0x8F) | 0x10;

    /* Send channel attention */
    [self sendChannelAttention];

    /* Wait for RU to become ready (up to 10000 microseconds) */
    scbStatus = *(unsigned char **)(((char *)self) + 0x1B8);
    for (timeout = 0; timeout < 10000; timeout++) {
        if ((*scbStatus & 0xF0) == 0x40) {
            /* RU is ready */
            break;
        }
        IODelay(1);  /* 1 microsecond delay */
    }

    /* Acknowledge any interrupts */
    [self acknowledgeInterrupts:*(unsigned short *)(*(void **)(((char *)self) + 0x1B8))];

    /* Sleep 50ms */
    IOSleep(50);

    /* Clear IRQ latch */
    [self clearIrqLatch];

    /* Return success if RU is ready */
    scbStatus = *(unsigned char **)(((char *)self) + 0x1B8);
    return ((*scbStatus & 0xF0) == 0x40);
}

/*
 * Abort receive unit
 * Returns: YES if successful, NO if failed or timed out
 */
- (BOOL)__abortReceiveUnit
{
    unsigned char *scbStatus;
    unsigned char *scbCommand;
    const char *driverName;
    int timeout;

    /* Get pointer to SCB status register (offset 0x1B8 contains SCB base pointer) */
    scbStatus = *(unsigned char **)(((char *)self) + 0x1B8);

    /* Check if RU is in suspended state (bits 4-7 == 0x40) */
    if ((*scbStatus & 0xF0) != 0x40) {
        /* RU not suspended, abort successful */
        return YES;
    }

    /* Wait for SCB to be ready */
    if (![self __waitScb]) {
        return NO;
    }

    /* Wait for CU to be ready */
    if (![self __waitCu:100]) {
        return NO;
    }

    /* Get pointer to SCB command register (SCB base + 2) */
    scbCommand = (unsigned char *)(*(unsigned int *)(((char *)self) + 0x1B8) + 2);

    /* Clear command word */
    *(unsigned short *)scbCommand = 0;

    /* Set RU command to abort (bits 0-3) while preserving CU command (bits 4-7) */
    *scbCommand = (*scbCommand & 0x8F) | 0x40;

    /* Send channel attention to execute command */
    [self sendChannelAttention];

    /* Wait up to 2000ms for RU to abort (status bits 4-7 == 0) */
    for (timeout = 0; timeout < 2000; timeout++) {
        IODelay(1000);  /* 1ms delay */

        scbStatus = *(unsigned char **)(((char *)self) + 0x1B8);
        if ((*scbStatus & 0xF0) == 0) {
            /* RU successfully aborted */
            return YES;
        }
    }

    /* Timeout */
    driverName = [[self name] cString];
    IOLog("%s: abort receive unit timed out\n", driverName);

    return NO;
}

/*
 * Allocate receive netbuf from buffer pool
 * Returns: Network buffer or NULL if pool doesn't exist
 *
 * Uses buffer pool at offset 0x188 (netbufPool instance variable)
 */
- (netbuf_t)__recAllocateNetbuf
{
    id bufferPool;
    netbuf_t netbuf;
    const char *driverName;

    /* Get buffer pool at offset 0x188 */
    bufferPool = *(id *)(((char *)self) + 0x188);

    if (bufferPool != nil) {
        /* Get buffer from pool */
        netbuf = (netbuf_t)[bufferPool getNetBuffer];
        return netbuf;
    }

    /* Buffer pool doesn't exist */
    driverName = [[self name] cString];
    IOLog("%s: allocateNetbuf called, but buffer pool doesn't exist\n", driverName);

    return NULL;
}

@end

/* External declarations */
extern unsigned int __page_size;
extern unsigned int __page_mask;

/* IRQ lookup tables */
static const unsigned char _plxirq[4] = { 0x05, 0x09, 0x0A, 0x0B };
static const unsigned char _fleairq[4] = { 0x03, 0x07, 0x0C, 0x0F };

/* Utility function implementations */

/*
 * Reset function - Attempts to reset the driver instance
 * param_1: Driver instance (id)
 */
static void __resetFunc(id driverInstance)
{
    BOOL result;
    const char *driverName;

    result = (BOOL)[driverInstance resetAndEnable:YES];
    if (result == NO) {
        driverName = [[driverInstance name] cString];
        IOLog("%s: Reset attempt unsuccessful\n", driverName);
    }
}

/*
 * Get network buffer from buffer pool
 * param_1: Pointer to buffer pool structure
 *
 * Buffer pool structure:
 *   +0x00: userData
 *   +0x04: magic1 (0xCAFE2BAD)
 *   +0x08: head pointer (free list)
 *   +0x0C: count (free buffers)
 *   +0x10: magic2 pointer
 *   +0x14: buffer size
 *   +0x24: lock object
 *
 * Buffer entry structure:
 *   +0x00: userData
 *   +0x04: magic1 (0xCAFE2BAD)
 *   +0x08: netbuf pointer
 *   +0x0C: next pointer
 *   +0x10: magic2 pointer (points to magic at end)
 *   +0x14: buffer data start
 */
static netbuf_t _getNetBuffer(void *bufferPool)
{
    int *pool = (int *)bufferPool;
    int *entry;
    netbuf_t nb;
    int *magic2Ptr;
    id lockObj;

    if (pool == NULL) {
        return NULL;
    }

    lockObj = (id)pool[0x24 / 4];  /* Get lock object at offset 0x24 */
    entry = (int *)pool[0x08 / 4]; /* Get head of free list at offset 0x08 */

    [lockObj lock];

    if (entry == NULL) {
        [lockObj unlock];
        return NULL;
    }

    /* Remove entry from free list */
    pool[0x08 / 4] = entry[0x0C / 4];  /* head = entry->next */
    pool[0x0C / 4]--;                   /* count-- */

    [lockObj unlock];

    /* Check buffer magic values for corruption */
    if (entry[0x04 / 4] != (int)0xCAFE2BAD) {
        IOPanic("getNetBuffer: buffer underrun");
    }

    magic2Ptr = (int *)entry[0x10 / 4];  /* Get pointer to end magic */
    if (*magic2Ptr != (int)0xCAFE2BAD) {
        IOPanic("getNetBuffer: buffer overrun");
    }

    /* Allocate netbuf wrapper around buffer data */
    nb = nb_alloc_wrapper(&entry[0x14 / 4],           /* buffer data */
                          pool[0x14 / 4],              /* buffer size */
                          (nb_func_t)_recycleNetbuf,   /* free function */
                          (void *)entry);              /* free arg */

    entry[0x08 / 4] = (int)nb;  /* Store netbuf pointer */

    if (nb == NULL) {
        /* Allocation failed, return entry to free list */
        [lockObj lock];
        entry[0x0C / 4] = pool[0x08 / 4];  /* entry->next = head */
        pool[0x08 / 4] = (int)entry;        /* head = entry */
        pool[0x0C / 4]++;                   /* count++ */
        [lockObj unlock];
    }

    return nb;
}

/*
 * Check if memory range is physically contiguous
 * param_1: Virtual address
 * param_2: Size in bytes
 * Returns: Last contiguous address, or 0 if not contiguous
 */
static unsigned int _IOIsPhysicallyContiguous(unsigned int vaddr, int size)
{
    unsigned int endAddr;
    unsigned int pageAddr;
    unsigned int physAddr1, physAddr2;
    int result;
    IOTask vmTask;

    /* Calculate end address */
    endAddr = (vaddr + size) - 1;

    /* Start at first page boundary after vaddr */
    pageAddr = (vaddr & ~__page_mask) + __page_size;

    while (pageAddr <= endAddr) {
        /* Get physical address at page boundary */
        vmTask = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(vmTask, pageAddr, &physAddr1);
        if (result != 0) {
            return 0;
        }

        /* Get physical address just before page boundary */
        result = IOPhysicalFromVirtual(vmTask, pageAddr - 1, &physAddr2);
        if (result != 0) {
            return 0;
        }

        /* Check if physical addresses are sequential */
        if (physAddr1 != physAddr2 + 1) {
            return pageAddr - 1;
        }

        /* Move to next page */
        pageAddr += __page_size;
    }

    return endAddr;
}

/*
 * Allocate non-cached memory
 * param_1: Requested size in bytes
 * param_2: Output - pointer to allocated memory (before alignment)
 * param_3: Output - actual allocated size
 * Returns: Page-aligned address
 */
static unsigned int _IOMallocNonCached(int requestedSize, int *allocPtr, int *allocSize)
{
    int totalSize;
    void *allocated;
    unsigned int alignedAddr;

    /* Round up to page boundary and add one page */
    totalSize = ((requestedSize + __page_mask) & ~__page_mask) + __page_size;
    *allocSize = totalSize;

    /* Allocate memory */
    allocated = IOMalloc(totalSize);
    *allocPtr = (int)allocated;

    if (allocated == NULL) {
        return 0;
    }

    /* Return page-aligned address */
    alignedAddr = ((unsigned int)allocated + __page_mask) & ~__page_mask;
    return alignedAddr;
}

/*
 * Allocate page-aligned memory
 * param_1: Requested size in bytes
 * param_2: Output - pointer to allocated memory (before alignment)
 * param_3: Output - actual allocated size (2x requested)
 * Returns: Page-aligned address
 */
static unsigned int _IOMallocPage(int requestedSize, int *allocPtr, int *allocSize)
{
    void *allocated;
    unsigned int alignedAddr;

    /* Allocate twice the requested size to ensure page alignment */
    *allocSize = requestedSize * 2;

    allocated = IOMalloc(requestedSize * 2);
    if (allocated == NULL) {
        return 0;
    }

    *allocPtr = (int)allocated;

    /* Return page-aligned address */
    alignedAddr = ((unsigned int)allocated + __page_mask) & ~__page_mask;
    return alignedAddr;
}

/*
 * Card IRQ - Determine IRQ number from hardware configuration
 * param_1: I/O base address (short)
 * Returns: IRQ number
 *
 * This function reads hardware configuration registers to determine
 * which IRQ the card is using. Different card types (PLX-based EISA
 * vs FLEA-based) use different lookup tables.
 */
static unsigned char _card_irq(unsigned short ioBase)
{
    unsigned char configByte;
    unsigned char irqIndex;

    /* Read configuration byte from offset 0x430 */
    configByte = inb(ioBase + 0x430);

    /* Check bit 7 to determine card type */
    if ((configByte & 0x80) == 0) {
        /* PLX-based card - read from offset 0xC88 */
        configByte = inb(ioBase + 0xC88);
        irqIndex = (configByte >> 1) & 0x03;
        return _plxirq[irqIndex];
    } else {
        /* FLEA-based card - use direct config byte */
        irqIndex = (configByte >> 1) & 0x03;
        return _fleairq[irqIndex];
    }
}

/*
 * Recycle network buffer - Called when netbuf is freed
 * This is the callback registered with nb_alloc_wrapper
 *
 * param_1: netbuf being freed (unused in this implementation)
 * param_2: Unused
 * param_3: Pointer to buffer entry structure
 *
 * Buffer pool structure (pointed to by *param_3):
 *   +0x00: userData
 *   +0x04: magic1 (0xCAFE2BAD)
 *   +0x05: shutdown flag (if non-zero, pool is being freed)
 *   +0x08: head pointer (free list)
 *   +0x0C: count (free buffers)
 *   +0x18: total count (total buffers allocated)
 *   +0x24: lock object
 *
 * Buffer entry structure (param_3):
 *   +0x00: buffer pool pointer
 *   +0x04: magic1 (0xCAFE2BAD)
 *   +0x0C: next pointer
 *   +0x10: magic2 pointer
 */
static void _recycleNetbuf(netbuf_t nb, void *arg1, int *bufferEntry)
{
    int *bufferPool;
    id lockObj;
    unsigned char shutdownFlag;
    int freeCount;
    int totalCount;

    /* Get pointer to buffer pool */
    bufferPool = (int *)*bufferEntry;

    /* Verify buffer magic values */
    if (bufferEntry[1] != (int)0xCAFE2BAD) {
        IOPanic("recycleNetbuf: buffer underrun");
    }

    if (*(int *)bufferEntry[4] != (int)0xCAFE2BAD) {
        IOPanic("recycleNetbuf: buffer overrun");
    }

    /* Get lock object */
    lockObj = (id)bufferPool[0x24 / 4];

    /* Check shutdown flag */
    shutdownFlag = *((unsigned char *)bufferPool + 5);

    [lockObj lock];

    if (shutdownFlag == 0) {
        /* Normal recycling - return buffer to free list */
        bufferEntry[3] = bufferPool[0x08 / 4];  /* entry->next = pool->head */
        bufferPool[0x08 / 4] = (int)bufferEntry; /* pool->head = entry */
        bufferPool[0x0C / 4]++;                  /* pool->count++ */

        [lockObj unlock];

        /* Check if all buffers are returned */
        freeCount = bufferPool[0x0C / 4];
        totalCount = bufferPool[0x18 / 4];

        if (freeCount == totalCount) {
            /* All buffers returned, free the pool */
            [(id)bufferPool free];
        }
    } else {
        /* Pool is shutting down - just increment count */
        bufferPool[0x0C / 4]++;  /* pool->count++ */

        [lockObj unlock];

        /* Check if all buffers are returned */
        freeCount = bufferPool[0x0C / 4];
        totalCount = bufferPool[0x18 / 4];

        if (freeCount == totalCount) {
            /* All buffers returned, free the pool */
            [(id)bufferPool free];
        }
    }
}

@end
