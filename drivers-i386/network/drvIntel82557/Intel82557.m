/*
 * Intel82557.m
 * Intel EtherExpress PRO/100 Network Driver - Main Implementation
 */

#import "Intel82557NetworkDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <driverkit/IOQueue.h>
#import <driverkit/IONetbufQueue.h>
#import <machkit/NXLock.h>
#import <kernserv/prototypes.h>

/* Forward declarations for utility functions */
static void __resetFunc(id driverInstance);
static netbuf_t _getNetBuffer(void *bufferPool);
static unsigned int _IOIsPhysicallyContiguous(unsigned int vaddr, int size);
static unsigned int _IOMallocNonCached(int requestedSize, int *allocPtr, int *allocSize);
static unsigned int _IOMallocPage(int requestedSize, int *allocPtr, int *allocSize);
static void _intHandler(void);
static void *_QDequeue(void *queue);
static void _recycleNetbuf(netbuf_t nb, void *arg1, int *bufferEntry);

/* External function declarations */
extern int nb_alloc_wrapper(void *buffer, unsigned int size, void (*recycleFunc)(netbuf_t, void *, int *), void *arg);
extern unsigned int _page_size;
extern unsigned int _page_mask;
extern int IOVmTaskSelf(unsigned int vaddr, int *physPage);
extern int IOPhysicalFromVirtual(int vmTask);
extern void IOSendInterrupt(void *param1, void *param2, int msgType);
extern void IOEnableInterrupt(void *param1);
extern int nb_size(netbuf_t nb);
extern void nb_shrink_bot(netbuf_t nb, int amount);
extern void *nb_map(netbuf_t nb);
extern void *IOMalloc(int size);
extern void nb_free(netbuf_t nb);
extern void bzero(void *s, int n);
extern int spldevice(void);
extern void splx(int level);
extern void IOSleep(int milliseconds);
extern void IOScheduleFunc(void (*func)(void), void *arg, int param);

@implementation Intel82557

/*
 * Probe method - Called during driver discovery
 * Detects Intel 82557 PCI devices and initializes driver instance
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    int result;
    const char *driverName;
    unsigned char pciDev, pciFunc, pciBus;
    unsigned char pciConfigSpace[256];
    unsigned int commandReg;
    unsigned int memoryRange[2];
    unsigned int irqLevel;
    unsigned char irqByte;
    id driverInstance;

    /* Get PCI device location */
    result = [deviceDescription getPCIdevice:&pciDev function:&pciFunc bus:&pciBus];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: unsupported PCI hardware.\n", driverName);
        return NO;
    }

    driverName = [[self name] cString];
    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", driverName, pciDev, pciFunc, pciBus);

    /* Get PCI configuration space */
    result = [self getPCIConfigSpace:pciConfigSpace withDeviceDescription:deviceDescription];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              driverName);
        return NO;
    }

    /* Read PCI command register (offset 4) and enable bus mastering */
    result = [self getPCIConfigData:&commandReg atRegister:4 withDeviceDescription:deviceDescription];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              driverName);
        return NO;
    }

    /* Enable bus mastering (bit 2) */
    commandReg |= 0x04;
    result = [self setPCIConfigData:commandReg atRegister:4 withDeviceDescription:deviceDescription];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Failed PCI configuration space access - aborting\n", driverName);
        return NO;
    }

    /* Set up memory range from PCI BAR0 */
    /* Extract base address from config space offset 0x10 and clear lower bits */
    memoryRange[0] = *(unsigned int *)(pciConfigSpace + 0x10) & 0xFFFFFFF7;
    memoryRange[1] = 0x20;  /* 32 bytes */

    result = [deviceDescription setMemoryRangeList:memoryRange num:1];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to reserve memory range 0x%x-0x%x - Aborting\n",
              driverName, memoryRange[0], memoryRange[0] + 0x1F);
        return NO;
    }

    /* Get IRQ from PCI config space offset 0x3C */
    irqByte = pciConfigSpace[0x3C];
    irqLevel = (unsigned int)irqByte;

    /* Validate IRQ (must be in range 2-15) */
    if ((irqLevel - 2) > 0x0D) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n", driverName, irqLevel);
        return NO;
    }

    result = [deviceDescription setInterruptList:&irqLevel num:1];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to reserve IRQ %d - Aborting\n", driverName, irqLevel);
        return NO;
    }

    /* Allocate and initialize driver instance */
    driverInstance = [self alloc];
    if (driverInstance == nil) {
        driverName = [[self name] cString];
        IOLog("%s: Failed to alloc instance\n", driverName);
        return NO;
    }

    driverInstance = [driverInstance initFromDeviceDescription:deviceDescription];
    if (driverInstance == nil) {
        return NO;
    }

    return YES;
}

/*
 * Initialize from device description
 * Main initialization method called during driver loading
 *
 * Driver instance structure:
 *   +0x17C: Station MAC address (6 bytes)
 *   +0x184: Network interface object
 *   +0x190: Promiscuous mode flag
 *   +0x191: Multicast mode flag
 *   +0x194: Initialized flag
 *   +0x196: Interrupts enabled flag
 *   +0x198: Transmit in progress flag
 *   +0x19C: Interrupt counter (for periodic interrupt generation)
 *   +0x1A1: Debug flag
 *   +0x1AC: Device I/O port base
 *   +0x1B0: EEPROM object
 *   +0x1BC: SCB base address
 *
 * Initialization sequence:
 *   1. Call superclass initialization
 *   2. Clear all driver state flags
 *   3. Get device I/O port from device description
 *   4. Initialize EEPROM interface and read MAC address
 *   5. Attach to network stack
 *
 * Returns: self if successful, nil on error
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOPCIDevice *devicePort;
    id eepromObj;
    unsigned char *eepromContents;
    id networkInterface;
    unsigned char *eepromCtrlReg;

    IOLog("Intel82557: initFromDeviceDescription\n");

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Initialize all driver state flags to zero */
    *(unsigned char *)(((char *)self) + 0x190) = 0;  /* Promiscuous mode */
    *(unsigned char *)(((char *)self) + 0x191) = 0;  /* Multicast mode */
    *(unsigned char *)(((char *)self) + 0x194) = 0;  /* Initialized flag */
    *(unsigned char *)(((char *)self) + 0x196) = 0;  /* Interrupts enabled */
    *(unsigned char *)(((char *)self) + 0x198) = 0;  /* Transmit in progress */
    *(unsigned char *)(((char *)self) + 0x19C) = 0;  /* Interrupt counter */
    *(unsigned char *)(((char *)self) + 0x1A1) = 0;  /* Debug flag */
    *(unsigned int *)(((char *)self) + 0x1BC) = 0;   /* SCB base address */

    /* Get device I/O port from device description */
    devicePort = [deviceDescription devicePort];
    *(id *)(((char *)self) + 0x1AC) = devicePort;

    /* Initialize EEPROM interface
     * The EEPROM control register is at offset 0x0E from I/O base
     */
    eepromCtrlReg = (unsigned char *)devicePort + 0x0E;
    eepromObj = [[i82557eeprom alloc] initWithAddress:eepromCtrlReg];
    *(id *)(((char *)self) + 0x1B0) = eepromObj;

    if (eepromObj == nil) {
        IOLog("Intel82557: i82557eeprom init failed in initFromDeviceDescription\n");
        [self free];
        return nil;
    }

    /* Read MAC address from EEPROM contents (first 6 bytes) */
    eepromContents = [eepromObj getContents];
    memmove((void *)(((char *)self) + 0x17C), eepromContents, 6);

    /* Log the MAC address */
    IOLog("Intel82557: Read MAC %02x:%02x:%02x:%02x:%02x:%02x\n",
          *(unsigned char *)(((char *)self) + 0x17C),
          *(unsigned char *)(((char *)self) + 0x17D),
          *(unsigned char *)(((char *)self) + 0x17E),
          *(unsigned char *)(((char *)self) + 0x17F),
          *(unsigned char *)(((char *)self) + 0x180),
          *(unsigned char *)(((char *)self) + 0x181));

    /* Attach to network stack with our MAC address */
    networkInterface = [self attachToNetworkWithAddress:
        (enet_addr_t *)(((char *)self) + 0x17C)];
    *(id *)(((char *)self) + 0x184) = networkInterface;

    if (networkInterface == nil) {
        IOLog("Intel82557: Failed to attach to network in initFromDeviceDescription\n");
        [self free];
        return nil;
    }

    return self;
}

/*
 * Free driver instance
 * Releases all allocated resources including memory, queues, and buffers
 *
 * Driver instance structure:
 *   +0x184: Network interface object
 *   +0x188: Netbuf pool object
 *   +0x18C: TX queue object
 *   +0x194: Initialized flag
 *   +0x1B4: Shared memory allocated pointer
 *   +0x1B8: Shared memory allocated size
 *   +0x1FC: RFD list base pointer
 *
 * RFD structure:
 *   +0x44: Netbuf pointer (offset from RFD base)
 *   0x48: Size of each RFD entry
 *   32 RFDs total (0x20)
 */
- (void)free
{
    int i;
    netbuf_t nb;
    unsigned char *rfdBase;

    /* If initialized, disable interrupts and clear flag */
    if (*(unsigned char *)(((char *)self) + 0x194) == 1) {
        [self disableAdapterInterrupts];
        *(unsigned char *)(((char *)self) + 0x194) = 0;
    }

    /* Free network interface object */
    if (*(id *)(((char *)self) + 0x184) != nil) {
        [*(id *)(((char *)self) + 0x184) free];
    }

    /* Free TX queue object */
    if (*(id *)(((char *)self) + 0x18C) != nil) {
        [*(id *)(((char *)self) + 0x18C) free];
    }

    /* Free netbuf pool and all netbufs in RFD list */
    if (*(id *)(((char *)self) + 0x188) != nil) {
        /* Free all netbufs attached to RFDs (32 RFDs, each 0x48 bytes) */
        rfdBase = *(unsigned char **)(((char *)self) + 0x1FC);

        for (i = 0; i < 0x20; i++) {  /* 0x20 = 32 RFDs */
            /* Each RFD is 0x48 bytes, netbuf pointer at offset +0x44 */
            nb = *(netbuf_t *)(rfdBase + 0x44 + (i * 0x48));

            if (nb != NULL) {
                nb_free(nb);
            }
        }

        /* Free the netbuf pool object */
        [*(id *)(((char *)self) + 0x188) free];
    }

    /* Free shared DMA memory */
    IOFree(*(void **)(((char *)self) + 0x1B4),
           *(unsigned int *)(((char *)self) + 0x1B8));

    /* Call superclass free */
    [super free];
}

/*
 * Reset and enable hardware
 * Performs a complete hardware reset and optionally enables the adapter
 *
 * Driver instance structure:
 *   +0x194: Initialized flag
 *   +0x195: Reset scheduled flag
 *   +0x197: Packets received flag
 *   +0x198: Transmit in progress flag
 *   +0x19C: Interrupt counter
 *   +0x218: Free queue structure base
 *
 * Parameters:
 *   enable - YES to enable adapter and interrupts, NO to just reset
 *
 * Operation:
 *   1. Clear any pending timeouts
 *   2. Disable adapter interrupts
 *   3. Reset driver state flags
 *   4. Refill free queue with buffers
 *   5. Perform hardware initialization (hwInit)
 *   6. If enable is YES:
 *      - Enable all interrupts via enableAllInterrupts
 *      - If that succeeds, also enable adapter interrupts and statistics dump
 *      - Set timeout for periodic operations
 *   7. Update running state and initialized flag
 *
 * Returns: YES if successful, NO on failure
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    BOOL result;
    int enableResult;

    /* Clear any pending timeouts */
    [self clearTimeout];

    /* Disable adapter interrupts during reset */
    [self disableAdapterInterrupts];

    /* Reset driver state flags */
    *(unsigned char *)(((char *)self) + 0x197) = 1;  /* Packets received */
    *(unsigned char *)(((char *)self) + 0x198) = 0;  /* Transmit in progress */
    *(unsigned int *)(((char *)self) + 0x19C) = 0;   /* Interrupt counter */
    *(unsigned char *)(((char *)self) + 0x195) = 0;  /* Reset scheduled */

    /* Refill free queue with buffers */
    [self QFill:(void *)(((char *)self) + 0x218)];

    /* Perform hardware initialization */
    result = [self hwInit];

    if (!result) {
        return NO;
    }

    /* If enable requested, set up interrupts and statistics */
    if (enable) {
        /* Enable all interrupts (system level) */
        enableResult = [self enableAllInterrupts];

        if (enableResult != 0) {
            /* Failed to enable interrupts - mark as not running */
            [self setRunning:NO];
            return NO;
        }

        /* Enable adapter interrupts */
        [self enableAdapterInterrupts];

        /* Start statistics collection */
        [self __dumpStatistics];

        /* Set periodic timeout (4000 milliseconds) */
        [self setRelativeTimeout:4000];
    }

    /* Update running state */
    [self setRunning:enable];

    /* Mark as initialized */
    *(unsigned char *)(((char *)self) + 0x194) = 1;

    return YES;
}

/*
 * Cold initialization - Full chip reset
 * Allocates and initializes all memory structures needed by the driver
 *
 * Driver instance structure:
 *   +0x17C: MAC address (6 bytes)
 *   +0x188: Netbuf pool object
 *   +0x1A4: Shared memory base
 *   +0x1A8: Shared memory size
 *   +0x1AC: Shared memory current pointer
 *   +0x1B0: Shared memory free bytes
 *   +0x1B4: Shared memory allocated pointer
 *   +0x1B8: Shared memory allocated size
 *   +0x1C0: Self-test command block pointer
 *   +0x1C4: Self-test command block physical address
 *   +0x1C8: Statistics buffer pointer
 *   +0x1CC: Statistics buffer physical address
 *   +0x1D0: EEPROM object
 *   +0x1E8: TCB base pointer
 *   +0x1F0: Single TCB for config commands
 *   +0x1F4: Configuration data buffer pointer
 *   +0x1F8: Configuration data physical address
 *   +0x1FC: RFD list base pointer
 *   +0x208-0x214: Receive queue (head, tail, count, max)
 *   +0x218-0x224: Free netbuf queue (head, tail, count, max)
 *
 * Allocated structures:
 *   - Shared memory page for DMA operations
 *   - Self-test command block (0x44 bytes)
 *   - TCB array (0x2C0 bytes for 16 TCBs)
 *   - Single TCB for configuration (0x2C bytes)
 *   - Configuration data buffer (0x5EA bytes)
 *   - Statistics buffer (0x44 bytes)
 *   - RFD list (0x900 bytes for 32 RFDs)
 *   - Netbuf pool (160 buffers of 0x5EE bytes each)
 *
 * Returns: YES on success, NO on failure
 */
- (BOOL)coldInit
{
    unsigned int sharedMemSize;
    unsigned int sharedMemBase;
    void *cmdBlock;
    vm_task_t vmTask;
    int result;
    unsigned int actualBufSize;
    id netbufPool;
    const char *driverName;
    unsigned int *eepromContents;

    /* Disable interrupts during initialization */
    [self disableAdapterInterrupts];

    /* Set shared memory size to one page */
    sharedMemSize = _page_size;
    *(unsigned int *)(((char *)self) + 0x1A8) = sharedMemSize;

    /* Allocate shared memory page for DMA operations */
    sharedMemBase = _IOMallocNonCached(sharedMemSize,
                                        ((char *)self) + 0x1B4,
                                        ((char *)self) + 0x1B8);
    *(unsigned int *)(((char *)self) + 0x1A4) = sharedMemBase;

    if (sharedMemBase == 0) {
        driverName = [[self name] cString];
        IOLog("%s: Can't allocate shared memory page\n", driverName);
        return NO;
    }

    /* Zero shared memory */
    bzero((void *)sharedMemBase, sharedMemSize);

    /* Initialize shared memory allocator */
    *(unsigned int *)(((char *)self) + 0x1AC) = sharedMemBase;  /* Current pointer */
    *(unsigned int *)(((char *)self) + 0x1B0) = sharedMemSize;  /* Free bytes */

    /* Allocate self-test command block (0x44 = 68 bytes) */
    cmdBlock = [self __memAlloc:0x44];
    *(void **)(((char *)self) + 0x1C0) = cmdBlock;

    /* Get physical address for self-test command block */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask, (vm_address_t)cmdBlock,
                                     (unsigned int *)(((char *)self) + 0x1C4));

    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid command block address\n", driverName);
        return NO;
    }

    /* Allocate TCB array (0x2C0 = 704 bytes for 16 TCBs of 44 bytes each) */
    cmdBlock = [self __memAlloc:0x2C0];
    *(void **)(((char *)self) + 0x1E8) = cmdBlock;

    /* Allocate single TCB for configuration commands (0x2C = 44 bytes) */
    cmdBlock = [self __memAlloc:0x2C];
    *(void **)(((char *)self) + 0x1F0) = cmdBlock;

    /* Get physical address for TCB */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask, (vm_address_t)cmdBlock + 0x14,
                                     (unsigned int *)((char *)cmdBlock + 0x14));

    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid TCB address\n", driverName);
        return NO;
    }

    /* Get physical address for TCB's TBD */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask, (vm_address_t)cmdBlock + 0x18,
                                     (unsigned int *)((char *)cmdBlock + 0x08));

    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid TCB->_TBD address\n", driverName);
        return NO;
    }

    /* Allocate configuration data buffer (0x5EA = 1514 bytes) */
    cmdBlock = [self __memAlloc:0x5EA];
    *(void **)(((char *)self) + 0x1F4) = cmdBlock;

    /* Get physical address for configuration data */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask, (vm_address_t)cmdBlock,
                                     (unsigned int *)(((char *)self) + 0x1F8));

    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid address\n", driverName);
        return NO;
    }

    /* Allocate statistics buffer (0x44 = 68 bytes) */
    cmdBlock = [self __memAlloc:0x44];
    *(void **)(((char *)self) + 0x1C8) = cmdBlock;

    /* Get physical address for statistics buffer */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask, (vm_address_t)cmdBlock,
                                     (unsigned int *)(((char *)self) + 0x1CC));

    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid errorCounters address\n", driverName);
        return NO;
    }

    /* Allocate RFD list (0x900 = 2304 bytes for 32 RFDs of 72 bytes each) */
    cmdBlock = [self __memAlloc:0x900];
    *(void **)(((char *)self) + 0x1FC) = cmdBlock;

    /* Allocate netbuf pool (160 buffers of 0x5EE bytes each) */
    netbufPool = [[Intel82557Buf alloc] initWithRequestedSize:0x5EE
                                                    actualSize:&actualBufSize
                                                         count:0xA0];  /* 160 buffers */

    *(id *)(((char *)self) + 0x188) = netbufPool;

    /* Check if actual buffer size is adequate (must be at least 0x5EE - 1 = 0x5ED) */
    if (actualBufSize < 0x5EE) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to allocate memory buffers of adequate length\n", driverName);
        return NO;
    }

    /* Initialize free netbuf queue */
    *(unsigned int *)(((char *)self) + 0x218) = 0;  /* Head */
    *(unsigned int *)(((char *)self) + 0x21C) = 0;  /* Tail */
    *(unsigned int *)(((char *)self) + 0x220) = 0;  /* Count */
    *(unsigned int *)(((char *)self) + 0x224) = 0xA0;  /* Max = 160 */

    /* Initialize receive queue */
    *(unsigned int *)(((char *)self) + 0x208) = 0;  /* Head */
    *(unsigned int *)(((char *)self) + 0x20C) = 0;  /* Tail */
    *(unsigned int *)(((char *)self) + 0x210) = 0;  /* Count */
    *(unsigned int *)(((char *)self) + 0x214) = 0xA0;  /* Max = 160 */

    /* Run self-test */
    if (![self __selfTest]) {
        return NO;
    }

    /* Get EEPROM contents and copy MAC address */
    eepromContents = (unsigned int *)[[*(id *)(((char *)self) + 0x1D0)] getContents];

    /* Copy first 4 bytes of MAC address */
    *(unsigned int *)(((char *)self) + 0x17C) = eepromContents[0];

    /* Copy last 2 bytes of MAC address */
    *(unsigned short *)(((char *)self) + 0x180) = ((unsigned short *)eepromContents)[2];

    return YES;
}

/*
 * Hardware initialization
 * Performs complete hardware initialization sequence
 *
 * Driver instance structure:
 *   +0x1BC: SCB base address
 *   +0x1C8: Statistics buffer pointer
 *   +0x1CC: Statistics buffer physical address
 *   +0x1EC: CU state
 *
 * SCB Register Offsets:
 *   +0x00: Status word
 *   +0x01: Status high byte
 *   +0x02: Command byte
 *   +0x04: General pointer
 *
 * Initialization sequence:
 *   1. Disable interrupts and reset chip
 *   2. Load CU base (0x60)
 *   3. Load RU base (0x06)
 *   4. Load dump counters address (0x40)
 *   5. Acknowledge pending interrupts
 *   6. Detect and configure PHY
 *   7. Configure adapter
 *   8. Setup individual address (MAC)
 *   9. Initialize TCB queue
 *   10. Initialize RFD list
 *   11. Start receive unit
 *
 * Returns: YES on success, NO on failure
 */
- (BOOL)hwInit
{
    unsigned char *scbBase;
    volatile unsigned char *commandReg;
    volatile unsigned char *statusHighByte;
    unsigned short statusWord;
    unsigned char statusHigh;
    int timeout;
    int spl;
    const char *driverName;
    BOOL result;

    /* Disable interrupts */
    [self disableAdapterInterrupts];

    /* Reset the chip */
    [self __resetChip];

    /* Disable interrupts again after reset */
    [self disableAdapterInterrupts];

    scbBase = *(unsigned char **)(((char *)self) + 0x1BC);
    commandReg = scbBase + 2;

    /* Wait for SCB command register to clear (CU initialization) */
    timeout = 10000;
    while (*commandReg != 0 && timeout > 0) {
        IODelay(1);
        timeout--;
    }

    if (*commandReg != 0) {
        driverName = [[self name] cString];
        IOLog("%s: hwInit: CU _waitSCBCommandClear failed\n", driverName);
        return NO;
    }

    /* Load CU base address (command 0x60) */
    *(unsigned int *)(scbBase + 4) = 0;  /* Set general pointer to 0 */
    scbBase[2] = (scbBase[2] & 0x8F) | 0x60;  /* CU_LOAD_BASE */
    *(unsigned int *)(((char *)self) + 0x1EC) = (scbBase[2] >> 4) & 7;

    /* Wait for command clear (RU initialization) */
    timeout = 10000;
    while (*commandReg != 0 && timeout > 0) {
        IODelay(1);
        timeout--;
    }

    if (*commandReg != 0) {
        driverName = [[self name] cString];
        IOLog("%s: hwInit: RU _waitSCBCommandClear failed\n", driverName);
        return NO;
    }

    /* Load RU base address (command 0x06) */
    *(unsigned int *)(scbBase + 4) = 0;  /* Set general pointer to 0 */
    scbBase[2] = (scbBase[2] & 0xF8) | 0x06;  /* RU_LOAD_BASE */

    /* Wait for command clear (before load dump counters) */
    timeout = 10000;
    while (*commandReg != 0 && timeout > 0) {
        IODelay(1);
        timeout--;
    }

    if (*commandReg != 0) {
        driverName = [[self name] cString];
        IOLog("%s: hwInit: before LOAD_DUMP_COUNTERS_ADDRESS: _waitSCBCommandClear failed\n",
              driverName);
        return NO;
    }

    /* Clear statistics completion flag */
    *(unsigned int *)(*(int *)(((char *)self) + 0x1C8) + 0x40) = 0;

    /* Load dump counters address (command 0x40) */
    *(unsigned int *)(scbBase + 4) = *(unsigned int *)(((char *)self) + 0x1CC);
    scbBase[2] = (scbBase[2] & 0x8F) | 0x40;  /* CU_DUMP_STATS */

    /* Wait for command clear (before interrupt ACK) */
    timeout = 10000;
    while (*commandReg != 0 && timeout > 0) {
        IODelay(1);
        timeout--;
    }

    if (*commandReg != 0) {
        driverName = [[self name] cString];
        IOLog("%s: hwInit: before intrACK _waitSCBCommandClear failed\n", driverName);
        return NO;
    }

    /* Acknowledge any pending interrupts */
    spl = spldevice();

    statusWord = *(unsigned short *)scbBase;
    statusHigh = (unsigned char)(statusWord >> 8);

    if (statusHigh != 0) {
        statusHighByte = scbBase + 1;
        *statusHighByte = statusHigh;
    }

    splx(spl);

    /* Detect and configure PHY */
    [self __phyDetect];

    /* Configure adapter */
    result = [self config];
    if (!result) {
        return NO;
    }

    /* Wait 500ms for PHY to stabilize */
    IOSleep(500);

    /* Setup individual address (MAC address) */
    result = [self iaSetup];
    if (!result) {
        return NO;
    }

    /* Initialize TCB queue */
    result = [self __initTcbQ];
    if (!result) {
        return NO;
    }

    /* Initialize RFD list */
    result = [self __initRfdList];
    if (!result) {
        return NO;
    }

    /* Start receive unit */
    result = [self __startReceive];
    if (!result) {
        return NO;
    }

    /* Acknowledge any pending interrupts again */
    spl = spldevice();

    statusWord = *(unsigned short *)scbBase;
    statusHigh = (unsigned char)(statusWord >> 8);

    if (statusHigh != 0) {
        statusHighByte = scbBase + 1;
        *statusHighByte = statusHigh;
    }

    splx(spl);

    return YES;
}

/*
 * Configure chip parameters
 * Sets up and sends a configuration command block to the adapter
 *
 * Driver instance structure:
 *   +0x1A0: PHY address
 *   +0x1C0: Command block pointer
 *   +0x1C4: Command block physical address
 *   +0x228: Speed detection mode flag
 *   +0x229: Full duplex flag
 *
 * Configuration command block structure (32 bytes at +0x08):
 *   Byte 0: Byte count (0x16 = 22 bytes)
 *   Byte 1: FIFO limits
 *   Byte 2-31: Various configuration parameters
 *
 * Returns: Result of polled command execution
 */
- (BOOL)config
{
    void *cmdBlock;
    unsigned char *configBytes;
    BOOL result;

    /* Get command block pointer */
    cmdBlock = *(void **)(((char *)self) + 0x1C0);

    /* Zero the configuration area (32 bytes) */
    bzero(cmdBlock, 0x20);

    /* Point to configuration data area (starts at byte 8 of command block) */
    configBytes = (unsigned char *)cmdBlock + 8;

    /* Set command: configure (0x02) */
    ((unsigned char *)cmdBlock)[2] &= 0xF8;
    ((unsigned char *)cmdBlock)[2] |= 0x02;

    /* Set EL bit (end of list) */
    ((unsigned char *)cmdBlock)[3] |= 0x80;

    /* Set link pointer to 0xFFFFFFFF (no next command) */
    *(unsigned int *)((unsigned char *)cmdBlock + 4) = 0xFFFFFFFF;

    /* Byte 0: Byte count = 0x16 (22 bytes of configuration) */
    configBytes[0] &= 0xC0;
    configBytes[0] |= 0x16;

    /* Byte 1: FIFO limits (RX=8, TX=0) */
    configBytes[1] &= 0xF0;
    configBytes[1] |= 0x08;
    configBytes[1] &= 0x0F;
    configBytes[1] |= 0x80;

    /* Byte 5: DMA maximum byte count */
    configBytes[0x0D - 8] |= 0x80;

    /* Byte 6: Late SCB update, TNO interrupt */
    configBytes[0x0E - 8] |= 0x02;
    configBytes[0x0E - 8] |= 0x30;

    /* Byte 7: Discard short frames, underrun retry */
    configBytes[0x0F - 8] |= 0x01;
    configBytes[0x0F - 8] &= 0xF9;
    configBytes[0x0F - 8] |= 0x02;

    /* Byte 8: MII mode (if not 82503 serial interface) */
    if (*(char *)(((char *)self) + 0x1A0) != 0x20) {
        configBytes[0x10 - 8] |= 0x01;
    }

    /* Byte 10: Preamble length, no address insertion */
    configBytes[0x12 - 8] |= 0x06;
    configBytes[0x12 - 8] |= 0x08;
    configBytes[0x12 - 8] &= 0xCF;
    configBytes[0x12 - 8] |= 0x20;

    /* Byte 12: Interframe spacing */
    configBytes[0x14 - 8] &= 0x0F;
    configBytes[0x14 - 8] |= 0x60;

    /* Byte 14: CRC in memory, collision filtering */
    configBytes[0x16 - 8] |= 0x02;
    configBytes[0x16 - 8] |= 0xF0;

    /* Byte 15: Promiscuous mode, broadcast disable */
    configBytes[0x17 - 8] |= 0x08;
    configBytes[0x17 - 8] |= 0x40;

    /* Copy MII mode bit to byte 15 bit 7 (inverted) */
    configBytes[0x17 - 8] &= 0x7F;
    configBytes[0x17 - 8] |= (~(configBytes[0x10 - 8] & 1)) << 7;

    /* Byte 17: Priority */
    configBytes[0x19 - 8] |= 0x40;

    /* Byte 18: Padding, stripping */
    configBytes[0x1A - 8] |= 0x01;
    configBytes[0x1A - 8] |= 0x02;
    configBytes[0x1A - 8] |= 0xF0;

    /* Byte 19: Full duplex mode (if speed detect mode or PHY 0 with full duplex) */
    if ((*(char *)(((char *)self) + 0x228) == 1) ||
        ((*(char *)(((char *)self) + 0x1A0) == 0) && (*(char *)(((char *)self) + 0x229) == 1))) {
        configBytes[0x1B - 8] |= 0x40;
    }

    /* Byte 19: Force full duplex */
    configBytes[0x1B - 8] |= 0x80;

    /* Byte 20: Multi-IA */
    configBytes[0x1C - 8] |= 0x3F;

    /* Byte 21: Multicast all */
    configBytes[0x1D - 8] |= 0x01;
    configBytes[0x1D - 8] |= 0x04;

    /* Send configuration command */
    result = [self __polledCommand:cmdBlock
                       WithAddress:*(unsigned int *)(((char *)self) + 0x1C4)];

    return result;
}

/*
 * Individual Address Setup
 * Programs the station MAC address into the adapter
 *
 * Driver instance structure:
 *   +0x17C: Station MAC address (6 bytes: 4 bytes + 2 bytes split)
 *   +0x1C0: Command block pointer
 *   +0x1C4: Command block physical address
 *
 * IA Setup command block structure (16 bytes):
 *   +0x00: Status (2 bytes)
 *   +0x02: Command (2 bytes)
 *   +0x04: Link pointer (4 bytes)
 *   +0x08: MAC address (6 bytes)
 *   +0x0E: Padding (2 bytes)
 *
 * Returns: YES if successful, NO otherwise
 */
- (BOOL)iaSetup
{
    void *cmdBlock;
    unsigned char *macAddr;
    unsigned int physAddr;
    BOOL result;

    /* Get command block pointer */
    cmdBlock = *(void **)(((char *)self) + 0x1C0);

    /* Zero the command block (16 bytes) */
    bzero(cmdBlock, 0x10);

    /* Set command: Individual Address Setup (0x01) */
    ((unsigned char *)cmdBlock)[2] &= 0xF8;  /* Clear low 3 bits */
    ((unsigned char *)cmdBlock)[2] |= 0x01;  /* CB_CMD_IA_SETUP */

    /* Set I bit (interrupt on completion, bit 7 of byte 3) */
    ((unsigned char *)cmdBlock)[3] |= 0x80;

    /* Set link pointer to 0xFFFFFFFF (end of list) */
    *(unsigned int *)((unsigned char *)cmdBlock + 4) = 0xFFFFFFFF;

    /* Copy MAC address to command block at offset 8 */
    /* MAC address is stored as 4 bytes at +0x17C and 2 bytes at +0x180 */
    *(unsigned int *)((unsigned char *)cmdBlock + 8) =
        *(unsigned int *)(((char *)self) + 0x17C);
    *(unsigned short *)((unsigned char *)cmdBlock + 0x0C) =
        *(unsigned short *)(((char *)self) + 0x180);

    /* Get physical address of command block */
    physAddr = *(unsigned int *)(((char *)self) + 0x1C4);

    /* Execute command using polled mode */
    result = [self __polledCommand:cmdBlock WithAddress:physAddr];

    if (!result) {
        IOLog("Intel82557: iaSetup failed\n");
    }

    return result;
}

/*
 * Multicast Setup
 * Configures the adapter's multicast address filter
 *
 * Driver instance structure:
 *   +0x193: Multicast enabled flag
 *
 * MC-Setup command block structure:
 *   +0x00: Status (2 bytes)
 *   +0x02: Command (2 bytes) - opcode 3, I bit
 *   +0x04: Link pointer (4 bytes) - 0xFFFFFFFF
 *   +0x08: MC count (2 bytes) - number of bytes (addresses * 6)
 *   +0x0A: MC addresses (6 bytes each)
 *
 * Multicast queue entry structure (from superclass):
 *   +0x00: MAC address low 4 bytes
 *   +0x04: MAC address high 2 bytes
 *   +0x08: Next pointer (offset +2 in 32-bit words)
 *
 * Returns: YES if OK bit is set, NO otherwise
 */
- (BOOL)mcSetup
{
    void **multicastQueue;
    unsigned short *cmdBlock;
    void **queueEntry;
    void **nextEntry;
    int addressCount;
    unsigned int physAddr;
    BOOL result;
    unsigned char statusByte;
    char *driverName;

    /* Get multicast queue from superclass */
    multicastQueue = (void **)[super multicastQueue];

    /* Allocate a page for the MC-setup command block */
    cmdBlock = (unsigned short *)IOMallocPage(_page_size);

    if (cmdBlock == NULL) {
        driverName = (char *)[self name];
        IOLog("%s: mcSetup: IOMallocPage return NULL\n", driverName);
        return NO;
    }

    /* Zero the command block header */
    cmdBlock[0] = 0;  /* Status */
    cmdBlock[1] = 0;  /* Command */

    /* Set command: MC-Setup (0x03) */
    ((unsigned char *)&cmdBlock[1])[0] &= 0xF8;  /* Clear low 3 bits */
    ((unsigned char *)&cmdBlock[1])[0] |= 0x03;  /* CB_CMD_MC_SETUP */

    /* Set I bit (interrupt on completion, bit 7 of byte 3) */
    ((unsigned char *)&cmdBlock[1])[1] |= 0x80;

    /* Set link pointer to 0xFFFFFFFF (end of list) */
    cmdBlock[2] = 0xFFFF;
    cmdBlock[3] = 0xFFFF;

    /* Walk multicast queue and copy addresses */
    addressCount = 0;

    /* Check if queue has entries (circular list check) */
    if ((void *)*multicastQueue != (void *)multicastQueue) {
        /* Iterate through circular linked list */
        for (queueEntry = (void **)*multicastQueue;
             queueEntry != multicastQueue;
             queueEntry = (void **)queueEntry[2]) {
            /* Copy MAC address (4 bytes at offset 0, 2 bytes at offset 4) */
            *(unsigned int *)&cmdBlock[addressCount * 3 + 5] =
                *(unsigned int *)queueEntry;
            cmdBlock[addressCount * 3 + 7] =
                *(unsigned short *)((unsigned char *)queueEntry + 4);

            addressCount++;
        }
    }

    /* Set MC count field (number of bytes = addresses * 6) */
    cmdBlock[4] = (unsigned short)(addressCount * 6);

    /* Get physical address of command block */
    physAddr = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)cmdBlock);

    if (physAddr == 0) {
        driverName = (char *)[self name];
        IOLog("%s: Invalid MC-setup command block address\n", driverName);
        IOFree(cmdBlock, _page_size);
        return NO;
    }

    /* Execute MC-setup command */
    result = [self __polledCommand:cmdBlock WithAddress:physAddr];

    if (result) {
        /* Get status byte (byte 3 of status word) */
        statusByte = ((unsigned char *)&cmdBlock[1])[1];

        /* Free command block */
        IOFree(cmdBlock, _page_size);

        /* Set multicast enabled flag */
        *(unsigned char *)(((char *)self) + 0x193) = 1;

        /* Return OK bit (bit 5 of status byte) */
        return (statusByte >> 5) & 1;
    }

    /* Command failed */
    driverName = (char *)[self name];
    IOLog("%s: MC-setup command failed 0x%x\n", driverName, cmdBlock[0]);

    IOFree(cmdBlock, _page_size);
    return NO;
}

/*
 * No Operation command
 * Sends a NOP command to test the command unit
 *
 * Driver instance structure:
 *   +0x1C0: Command block pointer
 *   +0x1C4: Command block physical address
 *
 * NOP command block structure (8 bytes):
 *   +0x00: Status (2 bytes)
 *   +0x02: Command (2 bytes) - opcode 0, I bit set, S bit clear
 *   +0x04: Link pointer (4 bytes) - 0xFFFFFFFF
 *
 * Returns: Result of polled command execution
 */
- (BOOL)nop
{
    void *cmdBlock;
    unsigned int physAddr;
    BOOL result;

    /* Get command block pointer */
    cmdBlock = *(void **)(((char *)self) + 0x1C0);

    /* Zero the command block (8 bytes) */
    bzero(cmdBlock, 8);

    /* Set command: NOP (0x00) - clear low 3 bits */
    ((unsigned char *)cmdBlock)[2] &= 0xF8;

    /* Set I bit (interrupt on completion, bit 7 of byte 3) */
    ((unsigned char *)cmdBlock)[3] |= 0x80;

    /* Clear S bit (suspend on completion, bit 5 of byte 3) */
    ((unsigned char *)cmdBlock)[3] &= 0xDF;  /* AND with ~0x20 */

    /* Set link pointer to 0xFFFFFFFF (end of list) */
    *(unsigned int *)((unsigned char *)cmdBlock + 4) = 0xFFFFFFFF;

    /* Get physical address of command block */
    physAddr = *(unsigned int *)(((char *)self) + 0x1C4);

    /* Execute NOP command using polled mode */
    result = [self __polledCommand:cmdBlock WithAddress:physAddr];

    return result;
}

/*
 * Enable promiscuous mode
 * Enables promiscuous mode and reconfigures the adapter
 *
 * Driver instance structure:
 *   +0x190: Promiscuous mode flag (offset 400 decimal)
 *
 * This method:
 *   1. Disables adapter interrupts
 *   2. Sets promiscuous mode flag if not already set
 *   3. Calls config to reconfigure the adapter
 *   4. Re-enables adapter interrupts
 *
 * Returns: Result from config method
 */
- (BOOL)enablePromiscuousMode
{
    BOOL result;

    /* Disable interrupts during reconfiguration */
    [self disableAdapterInterrupts];

    /* Set promiscuous mode flag if not already set */
    if (*(unsigned char *)(((char *)self) + 400) == 0) {
        *(unsigned char *)(((char *)self) + 400) = 1;
    }

    /* Reconfigure adapter */
    result = [self config];

    /* Re-enable interrupts */
    [self enableAdapterInterrupts];

    return result;
}

/*
 * Disable promiscuous mode
 * Disables promiscuous mode and reconfigures the adapter
 *
 * Driver instance structure:
 *   +0x190: Promiscuous mode flag (offset 400 decimal)
 *
 * This method:
 *   1. Disables adapter interrupts
 *   2. Clears promiscuous mode flag if set
 *   3. Calls config to reconfigure the adapter
 *   4. Re-enables adapter interrupts
 */
- (void)disablePromiscuousMode
{
    /* Disable interrupts during reconfiguration */
    [self disableAdapterInterrupts];

    /* Clear promiscuous mode flag if set */
    if (*(unsigned char *)(((char *)self) + 400) != 0) {
        *(unsigned char *)(((char *)self) + 400) = 0;
    }

    /* Reconfigure adapter */
    [self config];

    /* Re-enable interrupts */
    [self enableAdapterInterrupts];
}

/*
 * Enable multicast mode
 * Enables multicast packet reception by setting the multicast mode flag
 *
 * Driver instance structure:
 *   +0x191: Multicast mode flag
 *
 * Returns: YES (always succeeds)
 */
- (BOOL)enableMulticastMode
{
    /* Set multicast mode flag */
    *(unsigned char *)(((char *)self) + 0x191) = 1;

    return YES;
}

/*
 * Disable multicast mode
 * Disables multicast reception and reconfigures the adapter
 *
 * Driver instance structure:
 *   +0x191: Multicast mode flag
 *
 * This method:
 *   1. Disables adapter interrupts
 *   2. Calls mcSetup to reconfigure if multicast was enabled
 *   3. Clears multicast mode flag
 *   4. Re-enables adapter interrupts
 */
- (void)disableMulticastMode
{
    BOOL result;
    const char *driverName;

    /* Disable interrupts during reconfiguration */
    [self disableAdapterInterrupts];

    /* If multicast mode is currently enabled, reconfigure */
    if (*(unsigned char *)(((char *)self) + 0x191) != 0) {
        result = [self mcSetup];

        if (!result) {
            driverName = [[self name] cString];
            IOLog("%s: disable multicast mode failed\n", driverName);
        }
    }

    /* Clear multicast mode flag */
    *(unsigned char *)(((char *)self) + 0x191) = 0;

    /* Re-enable interrupts */
    [self enableAdapterInterrupts];
}

/*
 * Add multicast address
 * Adds a multicast address to the filter and reconfigures the adapter
 *
 * Driver instance structure:
 *   +0x191: Multicast mode flag
 *
 * This method:
 *   1. Sets multicast mode flag
 *   2. Disables adapter interrupts
 *   3. Calls mcSetup to configure multicast addresses
 *   4. Re-enables adapter interrupts
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;
    const char *driverName;

    /* Set multicast mode flag */
    *(unsigned char *)(((char *)self) + 0x191) = 1;

    /* Disable interrupts during reconfiguration */
    [self disableAdapterInterrupts];

    /* Setup multicast address list */
    result = [self mcSetup];

    if (!result) {
        driverName = [[self name] cString];
        IOLog("%s: add multicast address failed\n", driverName);
    }

    /* Re-enable interrupts */
    [self enableAdapterInterrupts];
}

/*
 * Remove multicast address
 * Removes a multicast address from the filter and updates the hardware
 *
 * The actual removal from the multicast list is handled by the superclass.
 * This method disables interrupts, reconfigures the hardware filter via
 * mcSetup, and re-enables interrupts.
 *
 * Parameters:
 *   addr - Pointer to multicast MAC address to remove
 *
 * Note: The superclass maintains the multicast queue, and mcSetup reads
 * that queue to program the hardware filter.
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;
    char *driverName;

    /* Disable interrupts while updating multicast filter */
    [self disableAdapterInterrupts];

    /* Reconfigure multicast filter (reads from superclass queue) */
    result = [self mcSetup];

    if (!result) {
        driverName = (char *)[self name];
        IOLog("%s: remove multicast address failed\n", driverName);
    }

    /* Re-enable interrupts */
    [self enableAdapterInterrupts];
}

/*
 * Enable adapter interrupts
 * Clears the interrupt mask bit in the SCB to enable hardware interrupts
 *
 * Driver instance structure:
 *   +0x196: Interrupts enabled flag
 *   +0x1BC: SCB base address
 *
 * SCB Register Offsets:
 *   +0x03: Interrupt control register
 *
 * Uses spldevice()/splx() for thread-safe interrupt level manipulation
 */
- (void)enableAdapterInterrupts
{
    int spl;
    unsigned char *scbBase;

    /* Raise interrupt priority level */
    spl = spldevice();

    /* Set interrupts enabled flag */
    *(unsigned char *)(((char *)self) + 0x196) = 1;

    /* Clear interrupt mask bit in SCB */
    scbBase = *(unsigned char **)(((char *)self) + 0x1BC);
    scbBase[3] = 0;  /* Clear M bit (unmask interrupts) */

    /* Restore interrupt priority level */
    splx(spl);
}

/*
 * Disable adapter interrupts
 * Sets the interrupt mask bit in the SCB to disable hardware interrupts
 *
 * Driver instance structure:
 *   +0x196: Interrupts enabled flag
 *   +0x1BC: SCB base address
 *
 * SCB Register Offsets:
 *   +0x03: Interrupt control register
 *
 * Uses spldevice()/splx() for thread-safe interrupt level manipulation
 */
- (void)disableAdapterInterrupts
{
    int spl;
    unsigned char *scbBase;

    /* Raise interrupt priority level */
    spl = spldevice();

    /* Clear interrupts enabled flag */
    *(unsigned char *)(((char *)self) + 0x196) = 0;

    /* Set interrupt mask bit in SCB */
    scbBase = *(unsigned char **)(((char *)self) + 0x1BC);
    scbBase[3] = 1;  /* Set M bit (mask interrupts) */

    /* Restore interrupt priority level */
    splx(spl);
}

/*
 * Interrupt handler
 * Main interrupt service routine for receive and transmit events
 *
 * Driver instance structure:
 *   +0x184: Network interface object
 *   +0x190: Promiscuous mode flag
 *   +0x193: Multicast enabled flag
 *   +0x195: Reset scheduled flag
 *   +0x197: Packets received flag
 *   +0x208: Receive queue head pointer
 *   +0x20C: Receive queue tail pointer
 *   +0x210: Receive queue count
 *   +0x218: Free queue structure base (for QFill)
 *
 * Receive queue entry structure:
 *   +0x00: Next pointer (for linked list)
 *
 * Operation:
 *   1. Check if reset is scheduled (+0x195)
 *   2. If so, call __scheduleReset and clear flag
 *   3. Otherwise:
 *      - Dequeue all received packets from receive queue
 *      - For each packet, either pass to network stack or free if unwanted multicast
 *      - Refill receive queue with fresh buffers
 *      - Free completed transmit buffers
 *      - Service transmit queue
 */
- (void)interruptOccurred
{
    unsigned int spl;
    netbuf_t packet;
    int packetsReceived;
    int *queueCount;
    void *queueTail;
    void *queueHead;
    unsigned char *mappedData;
    BOOL isUnwanted;

    /* Check if reset is scheduled */
    if (*(unsigned char *)(((char *)self) + 0x195) != 0) {
        /* Schedule reset and clear flag */
        [self __scheduleReset];
        *(unsigned char *)(((char *)self) + 0x195) = 0;
        return;
    }

    /* Process received packets */
    spl = spldevice();
    packetsReceived = 0;

    while (1) {
        /* Dequeue packet from receive queue */
        if (*(int *)(((char *)self) + 0x210) == 0) {
            /* Queue is empty */
            packet = NULL;
        } else {
            /* Get head of queue */
            packet = *(netbuf_t *)(((char *)self) + 0x208);

            /* Update head to next packet */
            *(netbuf_t *)(((char *)self) + 0x208) = *(netbuf_t *)packet;

            /* Decrement count */
            queueCount = (int *)(((char *)self) + 0x210);
            (*queueCount)--;

            /* If queue is now empty, clear tail and head */
            if (*queueCount == 0) {
                *(void **)(((char *)self) + 0x20C) = NULL;
                *(void **)(((char *)self) + 0x208) = NULL;
            }

            /* Clear next pointer in dequeued packet */
            *(netbuf_t *)packet = NULL;
        }

        /* Break if no more packets */
        if (packet == NULL) {
            break;
        }

        splx(spl);
        packetsReceived++;

        /* Check if we should pass packet to network stack */
        if ((*(unsigned char *)(((char *)self) + 0x190) == 0x01) ||
            (*(unsigned char *)(((char *)self) + 0x193) == 0)) {
            /* Promiscuous mode enabled or multicast not enabled */
            /* Pass packet to network interface */
            [*(id *)(((char *)self) + 0x184) handleInputPacket:packet extra:0];
        } else {
            /* Check if this is an unwanted multicast packet */
            mappedData = nb_map(packet);
            isUnwanted = [super isUnwantedMulticastPacket:mappedData];

            if (!isUnwanted) {
                /* Wanted packet - pass to network interface */
                [*(id *)(((char *)self) + 0x184) handleInputPacket:packet extra:0];
            } else {
                /* Unwanted multicast - free it */
                nb_free(packet);
            }
        }

        spl = spldevice();
    }

    splx(spl);

    /* Set flag if we received packets */
    if (packetsReceived > 0) {
        *(unsigned char *)(((char *)self) + 0x197) = 1;
    }

    /* Refill receive queue with fresh buffers */
    [self QFill:(void *)(((char *)self) + 0x218)];

    /* Free completed transmit buffers */
    [self freeCompletedTransmits];

    /* Service transmit queue */
    [self serviceTransmitQueue];
}

/*
 * Timeout handler
 * Periodic timeout handler for maintenance and statistics collection
 *
 * Driver instance structure:
 *   +0x197: Packets received flag
 *   +0x198: Transmit in progress flag
 *
 * Operation:
 *   1. Check if driver is running
 *   2. If no packets received and transmit in progress, reconfigure multicast
 *   3. Reset flags
 *   4. Process any pending interrupts
 *   5. Update statistics
 *   6. Set next timeout for 4 seconds
 */
- (void)timeoutOccurred
{
    BOOL isRunning;

    /* Check if driver is running */
    isRunning = [self isRunning];

    if (!isRunning) {
        return;
    }

    /* Check if we need to reconfigure multicast
     * If no packets received (+0x197 == 0) and transmit in progress (+0x198 == 1),
     * the multicast filter may need updating
     */
    if ((*(unsigned char *)(((char *)self) + 0x197) == 0) &&
        (*(unsigned char *)(((char *)self) + 0x198) == 1)) {
        /* Reconfigure multicast filter */
        [self disableAdapterInterrupts];
        [self mcSetup];
        [self enableAdapterInterrupts];
    }

    /* Reset flags for next timeout period */
    *(unsigned char *)(((char *)self) + 0x198) = 0;  /* Transmit in progress */
    *(unsigned char *)(((char *)self) + 0x197) = 0;  /* Packets received */

    /* Process any pending interrupts */
    [self interruptOccurred];

    /* Update statistics */
    [self __updateStatistics];

    /* Set next timeout for 4 seconds (4000 milliseconds) */
    [self setRelativeTimeout:4000];
}

/*
 * Get interrupt handler
 */
- (void)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)level
          argument:(void **)argument
      forInterrupt:(unsigned int)interrupt
{
    IOLog("Intel82557: getHandler\n");

    // TODO: Return interrupt handler function pointer
}

/*
 * Transmit packet
 * Main transmit entry point called by network stack
 *
 * Driver instance structure:
 *   +0x18C: TX queue object
 *   +0x196: Interrupts enabled flag
 *   +0x1E4: Free TCB count
 *
 * Operation:
 *   1. Check if driver is running and interrupts enabled
 *   2. If not, free packet and return
 *   3. Free completed transmits
 *   4. Service transmit queue
 *   5. If queue is empty and TCBs available, transmit immediately
 *   6. Otherwise enqueue packet for later transmission
 */
- (void)transmit:(netbuf_t)packet
{
    BOOL isRunning;
    int queueCount;
    int freeTcbCount;

    /* Check if driver is running */
    isRunning = [self isRunning];

    /* If not running or interrupts disabled, drop packet */
    if (!isRunning || (*(unsigned char *)(((char *)self) + 0x196) == 0)) {
        nb_free(packet);
        return;
    }

    /* Free any completed transmit buffers */
    [self freeCompletedTransmits];

    /* Service the transmit queue (send queued packets) */
    [self serviceTransmitQueue];

    /* Get current queue count */
    queueCount = [*(id *)(((char *)self) + 0x18C) count];

    /* Get number of free TCBs */
    freeTcbCount = *(int *)(((char *)self) + 0x1E4);

    /* If queue is empty and we have free TCBs, transmit immediately */
    if ((queueCount == 0) && (freeTcbCount != 0)) {
        [self __transmitPacket:packet];
    } else {
        /* Queue is not empty or no free TCBs - enqueue packet */
        [*(id *)(((char *)self) + 0x18C) enqueue:packet];
    }
}

/*
 * Send packet
 * Polled transmit method for kernel debugging (KDB mode)
 *
 * Driver instance structure:
 *   +0x1F0: Polled transmit TCB pointer
 *   +0x1F4: Polled transmit buffer pointer (offset 500 decimal)
 *   +0x1F8: Polled transmit buffer physical address
 *
 * TCB structure for polled transmit:
 *   +0x00: Status (2 bytes)
 *   +0x02: Command (2 bytes) - opcode 4 (transmit), S bit, I bit
 *   +0x04: Link pointer (4 bytes) - 0xFFFFFFFF
 *   +0x0C: TBD number (2 bytes)
 *   +0x0E: Transmit threshold (1 byte)
 *   +0x0F: TBD count (1 byte)
 *   +0x14: TCB physical address (for __polledCommand)
 *   +0x18: TBD array address (4 bytes)
 *   +0x1C: TBD size (2 bytes) - bits 13:0 = size
 *
 * Parameters:
 *   data - Pointer to packet data to transmit
 *   len - Length of packet in bytes
 *
 * Returns: Number of bytes transmitted (len, clamped to valid range)
 *
 * Note: This is a synchronous, polled transmit used during kernel debugging
 * when interrupts may not be available.
 */
- (unsigned int)sendPacket:(void *)data length:(unsigned int)len
{
    void *tcb;
    void *txBuffer;
    unsigned int physAddr;
    unsigned short *tbdSize;
    unsigned char *cmdBytes;

    /* Get polled transmit TCB pointer */
    tcb = *(void **)(((char *)self) + 0x1F0);

    /* Clear status */
    *(unsigned short *)tcb = 0;

    /* Set link pointer to 0xFFFFFFFF (end of list) */
    *(unsigned int *)((unsigned char *)tcb + 4) = 0xFFFFFFFF;

    /* Set transmit threshold (0xE0 = entire frame in FIFO before transmit) */
    ((unsigned char *)tcb)[0x0E] = 0xE0;

    /* Clear command word */
    *(unsigned short *)((unsigned char *)tcb + 2) = 0;

    /* Set command: Transmit (0x04) */
    cmdBytes = (unsigned char *)tcb + 2;
    cmdBytes[0] &= 0xF8;  /* Clear low 3 bits */
    cmdBytes[0] |= 0x04;  /* CB_CMD_TRANSMIT */

    /* Set S bit (suspend on completion, bit 3) */
    cmdBytes[0] |= 0x08;

    /* Set I bit (interrupt on completion, bit 7 of byte 3) */
    cmdBytes[1] |= 0x80;

    /* Clear TBD number */
    *(unsigned short *)((unsigned char *)tcb + 0x0C) = 0;

    /* Set TBD count to 1 (one transmit buffer descriptor) */
    ((unsigned char *)tcb)[0x0F] = 1;

    /* Clamp length to valid Ethernet frame size */
    if (len > 0x5EA) {
        len = 0x5EA;  /* Max 1514 bytes */
    }
    if (len < 0x40) {
        len = 0x40;   /* Min 64 bytes */
    }

    /* Copy packet data to transmit buffer */
    txBuffer = *(void **)(((char *)self) + 0x1F4);
    bcopy(data, txBuffer, len);

    /* Set TBD array address (points to physical address of buffer) */
    *(unsigned int *)((unsigned char *)tcb + 0x18) =
        *(unsigned int *)(((char *)self) + 0x1F8);

    /* Clear TBD size field and set packet length */
    tbdSize = (unsigned short *)((unsigned char *)tcb + 0x1C);
    *tbdSize = 0;
    *tbdSize = (*tbdSize & 0xC000) | ((unsigned short)len & 0x3FFF);

    /* Get physical address of TCB for polled command */
    physAddr = *(unsigned int *)((unsigned char *)tcb + 0x14);

    /* Execute transmit command in polled mode */
    [self __polledCommand:tcb WithAddress:physAddr];

    return len;
}

/*
 * Receive packet
 * Polled receive method for kernel debugging (KDB mode)
 *
 * Driver instance structure:
 *   +0x1BC: SCB base address
 *   +0x200: Current RFD pointer
 *   +0x204: Last RFD pointer
 *
 * RFD structure:
 *   +0x00: Status (2 bytes) - C bit (bit 7 of byte 1), OK bit (bit 5 of byte 1)
 *   +0x03: Control (1 byte) - EL bit (bit 7)
 *   +0x08: Link pointer (4 bytes)
 *   +0x0C: Count (2 bytes)
 *   +0x0E: Size (2 bytes)
 *   +0x20: Next RFD physical address (4 bytes)
 *   +0x28: Actual count (2 bytes) - EOF bit (bit 15), F bit (bit 14), size (bits 13:0)
 *   +0x29: Actual count high byte - EOF bit (bit 7)
 *   +0x34: Buffer size (2 bytes) - bits 13:0
 *   +0x36: Actual size (2 bytes)
 *
 * SCB status register (at SCB base):
 *   Byte 0: Status low
 *   Byte 1: Status high - RNR bit (bit 4)
 *
 * Returns: Number of bytes received, 0 on timeout or error
 */
- (unsigned int)receivePacket:(void *)data length:(unsigned int)maxlen timeout:(unsigned int)timeout
{
    void *currentRfd;
    void *lastRfd;
    unsigned char *scbBase;
    unsigned short scbStatus;
    unsigned char statusHigh;
    unsigned short actualCount;
    unsigned int packetLength;
    void *packetData;
    unsigned char *rfdBytes;
    unsigned short *rfdWords;
    int timeoutMicroseconds;
    unsigned char ruState;
    char *driverName;

    /* Initialize return length to 0 */
    maxlen = 0;

    /* Convert timeout from seconds to microseconds (timeout * 1000000) */
    /* Note: The decompiled code shows * 1000, which seems to be milliseconds */
    timeoutMicroseconds = timeout * 1000;

    while (1) {
        /* Get current RFD pointer */
        currentRfd = *(void **)(((char *)self) + 0x200);

        /* Check if C bit is set (command complete, bit 7 of byte 1) */
        if (((unsigned char *)currentRfd)[1] < 0) {
            /* Packet received - get SCB base to check/acknowledge interrupts */
            scbBase = *(unsigned char **)(((char *)self) + 0x1BC);
            scbStatus = *(unsigned short *)scbBase;
            statusHigh = (unsigned char)(scbStatus >> 8);

            /* Acknowledge interrupts if any are pending */
            if (statusHigh != 0) {
                scbBase[1] = statusHigh;
            }

            /* Check if EOF bit is set (bit 7 of byte 0x29) */
            if (((unsigned char *)currentRfd)[0x29] < 0) {
                /* Check if OK bit is set (bit 5 of byte 1) */
                if ((((unsigned char *)currentRfd)[1] & 0x20) != 0) {
                    /* Get actual count (bits 13:0 of word at +0x28) */
                    actualCount = *(unsigned short *)((unsigned char *)currentRfd + 0x28);
                    packetLength = actualCount & 0x3FFF;
                    maxlen = packetLength;

                    /* Map packet data and copy to user buffer */
                    packetData = nb_map(*(netbuf_t *)((unsigned char *)currentRfd + 0x44));
                    bcopy(packetData, data, packetLength);

                    /* Reset RFD for reuse */
                    *(unsigned short *)currentRfd = 0;  /* Clear status */

                    /* Set EL bit (bit 7 of byte 3) */
                    ((unsigned char *)currentRfd)[3] |= 0x80;

                    /* Set link to 0xFFFFFFFF */
                    *(unsigned int *)((unsigned char *)currentRfd + 8) = 0xFFFFFFFF;

                    /* Clear count fields */
                    *(unsigned short *)((unsigned char *)currentRfd + 0x0C) = 0;
                    *(unsigned short *)((unsigned char *)currentRfd + 0x0E) = 0;
                    *(unsigned short *)((unsigned char *)currentRfd + 0x28) = 0;

                    /* Reset buffer size (0x5EE = 1518 bytes) */
                    rfdWords = (unsigned short *)((unsigned char *)currentRfd + 0x34);
                    *rfdWords = (*rfdWords & 0xC000) | 0x5EE;

                    /* Set actual size to 1 */
                    *(unsigned short *)((unsigned char *)currentRfd + 0x36) = 1;

                    /* Move to next RFD */
                    *(void **)(((char *)self) + 0x200) =
                        *(void **)((unsigned char *)currentRfd + 0x20);

                    /* Clear EL bit on previous last RFD */
                    lastRfd = *(void **)(((char *)self) + 0x204);
                    *(unsigned short *)((unsigned char *)lastRfd + 0x36) = 0;
                    ((unsigned char *)lastRfd)[3] &= 0x7F;

                    /* Update last RFD pointer */
                    *(void **)(((char *)self) + 0x204) =
                        *(void **)((unsigned char *)lastRfd + 0x20);
                }

                /* Check if RU is not ready (RNR - bit 4 of status high byte) */
                if ((scbStatus >> 8) & 0x10) {
                    /* RU not ready - need to restart receive */
                    driverName = (char *)[self name];
                    IOLog("%s: KDB: restarting receive\n", driverName);

                    [self __abortReceive];
                    [self __initRfdList];
                    [self __startReceive];
                }

                return maxlen;
            } else {
                /* More than 1 RBD per RFD - error condition */
                driverName = (char *)[self name];
                IOLog("%s: KDB: more than 1 rbd per rfd\n", driverName);

                [self __abortReceive];
                [self __initRfdList];
                [self __startReceive];

                return maxlen;
            }
        }

        /* No packet yet - check timeout */
        if (timeoutMicroseconds < 1) {
            /* Timeout expired - check RU state */
            scbBase = *(unsigned char **)(((char *)self) + 0x1BC);
            ruState = *scbBase & 0x3C;  /* Bits 5:2 = RU state */

            /* If RU is ready (state 0x10), just return */
            if (ruState == 0x10) {
                return 0;
            }

            /* RU not ready - restart receive unit */
            driverName = (char *)[self name];
            IOLog("%s: KDB: RU timeout, restarting\n", driverName);

            [self __abortReceive];
            [self __initRfdList];
            [self __startReceive];

            return 0;
        }

        /* Wait 50 microseconds before polling again */
        IODelay(50);
        timeoutMicroseconds -= 50;
    }
}

/*
 * Service transmit queue
 * Dequeues packets from the TX queue and transmits them
 *
 * Driver instance structure:
 *   +0x18C: TX queue object
 *   +0x1E4: Free TCB count
 *
 * Operation:
 *   While there are free TCBs and packets in the queue:
 *   - Dequeue packet from TX queue
 *   - Transmit packet via __transmitPacket:
 *   - Check for more free TCBs and continue
 */
- (void)serviceTransmitQueue
{
    netbuf_t packet;
    int freeTcbCount;

    /* Get number of free TCBs */
    freeTcbCount = *(int *)(((char *)self) + 0x1E4);

    /* While we have free TCBs available */
    while (freeTcbCount > 0) {
        /* Dequeue packet from TX queue */
        packet = [*(id *)(((char *)self) + 0x18C) dequeue];

        if (packet == NULL) {
            /* Queue is empty */
            break;
        }

        /* Transmit the packet */
        [self __transmitPacket:packet];

        /* Refresh free TCB count for next iteration */
        freeTcbCount = *(int *)(((char *)self) + 0x1E4);
    }
}

/*
 * Free completed transmits
 * Scans the TCB queue and frees netbufs for completed transmissions
 *
 * Driver instance structure:
 *   +0x1D4: Total TCB count (max TCBs)
 *   +0x1D8: Oldest TCB pointer (head of completion queue)
 *   +0x1E4: Free TCB count
 *
 * TCB structure:
 *   +0x01: Status byte (bit 7 = C flag - command complete)
 *   +0x10: Link pointer (next TCB)
 *   +0x28: Netbuf pointer
 *
 * This method walks the TCB completion queue, freeing netbufs for
 * TCBs that have the C (complete) bit set, until it reaches an
 * incomplete TCB or the queue is empty.
 */
- (void)freeCompletedTransmits
{
    int tcbAddr;
    netbuf_t nb;

    /* Process completed TCBs while free count < total count and C bit is set */
    while ((*(int *)(((char *)self) + 0x1E4) < *(int *)(((char *)self) + 0x1D4))) {
        tcbAddr = *(int *)(((char *)self) + 0x1D8);

        /* Check if C bit (bit 7 of status byte at +0x01) is set */
        if (((unsigned char *)tcbAddr)[1] < 0x80) {
            break;  /* Not completed yet */
        }

        /* Clear C bit (bit 7) in status byte */
        ((unsigned char *)tcbAddr)[1] &= 0x7F;

        /* Get netbuf pointer from TCB at offset +0x28 */
        nb = *(netbuf_t *)(tcbAddr + 0x28);

        if (nb != NULL) {
            /* Free the netbuf */
            nb_free(nb);

            /* Clear netbuf pointer in TCB */
            *(netbuf_t *)(tcbAddr + 0x28) = NULL;
        }

        /* Move to next TCB (link pointer at +0x10) */
        *(int *)(((char *)self) + 0x1D8) = *(int *)(tcbAddr + 0x10);

        /* Increment free count */
        *(int *)(((char *)self) + 0x1E4) = *(int *)(((char *)self) + 0x1E4) + 1;
    }
}

/*
 * Allocate network buffer
 * Allocates a network buffer with proper size and alignment for DMA
 *
 * This method:
 *   1. Allocates buffer of size 0x5EE (1518 bytes - max Ethernet frame)
 *   2. Aligns buffer to 4-byte boundary
 *   3. Shrinks buffer from bottom to final size of 0x5EA (1514 bytes)
 *
 * Returns: Allocated netbuf or NULL on failure
 */
- (netbuf_t)allocateNetbuf
{
    netbuf_t nb;
    unsigned int virtAddr;
    unsigned int alignedAddr;
    int currentSize;

    /* Allocate buffer of 0x5EE bytes (1518 bytes) */
    nb = nb_alloc(0x5EE);

    if (nb != NULL) {
        /* Get virtual address of buffer */
        virtAddr = (unsigned int)nb_map(nb);

        /* Check if buffer is aligned to 4-byte boundary */
        if ((virtAddr & 3) != 0) {
            /* Calculate aligned address */
            alignedAddr = (virtAddr + 3) & 0xFFFFFFFC;

            /* Shrink from top to align buffer */
            nb_shrink_top(nb, alignedAddr - virtAddr);
        }

        /* Get current buffer size */
        currentSize = nb_size(nb);

        /* Shrink from bottom to final size of 0x5EA (1514 bytes) */
        nb_shrink_bot(nb, currentSize - 0x5EA);
    }

    return nb;
}

/*
 * Queue fill operation
 * Fills the specified queue with buffers from the netbuf pool
 *
 * Driver instance structure:
 *   +0x188: Netbuf pool object
 *
 * Queue structure:
 *   +0x00: Head pointer (first buffer in queue)
 *   +0x04: Tail pointer (last buffer in queue)
 *   +0x08: Current count (number of buffers in queue)
 *   +0x0C: Max count (maximum buffers for queue)
 *
 * Buffer entry structure:
 *   +0x00: Next pointer (for linked list)
 *
 * Operation:
 *   1. While current count < max count:
 *      - Get buffer from netbuf pool
 *      - Convert to physical address for validation
 *      - Enqueue buffer into queue (with thread safety)
 *   2. If enqueue fails, log error
 */
- (void)QFill:(void *)queue
{
    netbuf_t buffer;
    void *mappedAddr;
    unsigned int physAddr;
    unsigned int spl;
    unsigned int currentCount;
    unsigned int maxCount;
    BOOL enqueued;
    char *driverName;

    /* Queue structure pointers */
    netbuf_t *queueHead;
    netbuf_t *queueTail;
    unsigned int *queueCount;
    unsigned int *queueMaxCount;

    queueHead = (netbuf_t *)queue;
    queueTail = (netbuf_t *)((unsigned char *)queue + 4);
    queueCount = (unsigned int *)((unsigned char *)queue + 8);
    queueMaxCount = (unsigned int *)((unsigned char *)queue + 12);

    /* Fill queue until it reaches max count */
    while (1) {
        /* Check if queue is full */
        if (*queueMaxCount <= *queueCount) {
            return;
        }

        /* Get buffer from netbuf pool */
        buffer = [*(id *)(((char *)self) + 0x188) getNetBuffer];

        if (buffer == NULL) {
            /* No buffers available */
            return;
        }

        /* Map buffer and get physical address for validation */
        mappedAddr = nb_map(buffer);
        physAddr = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)mappedAddr);

        if (physAddr != 0) {
            /* Physical address conversion failed */
            driverName = (char *)[self name];
            IOLog("%s: QFill invalid netbuf address\n", driverName);
            return;
        }

        /* Enter critical section */
        spl = spldevice();

        /* Attempt to enqueue buffer */
        if (*queueCount < *queueMaxCount) {
            currentCount = *queueCount;
            (*queueCount)++;

            if (currentCount == 0) {
                /* Queue was empty - set both head and tail */
                *queueHead = buffer;
                *queueTail = buffer;
            } else {
                /* Queue has entries - link from tail and update tail */
                *(*queueTail) = buffer;
                *queueTail = buffer;
            }

            /* Clear next pointer in buffer */
            *(netbuf_t *)buffer = NULL;

            enqueued = YES;
        } else {
            enqueued = NO;
        }

        /* Exit critical section */
        splx(spl);

        /* If enqueue failed, break and log error */
        if (!enqueued) {
            driverName = (char *)[self name];
            IOLog("%s: QFill: failed to enqueue %d\n", driverName, *queueCount);
            return;
        }
    }
}

/*
 * Get transmit queue size
 * Returns the maximum size of the transmit queue
 *
 * Returns: 80 (0x50) - maximum number of packets that can be queued
 */
- (unsigned int)transmitQueueSize
{
    /* Fixed queue size of 80 packets */
    return 0x50;
}

/*
 * Get transmit queue count
 * Returns the current number of packets in the transmit queue
 *
 * Driver instance structure:
 *   +0x18C: TX queue object
 *
 * Returns: Current number of packets queued for transmission
 */
- (unsigned int)transmitQueueCount
{
    int count;

    /* Get current queue count from TX queue object */
    count = [*(id *)(((char *)self) + 0x18C) count];

    return count;
}

/*
 * Send port command
 * Writes a PORT command to the adapter's PORT register
 *
 * Driver instance structure:
 *   +0x1BC: SCB base address
 *
 * SCB PORT register:
 *   Offset +0x08 from SCB base
 *
 * PORT command format (32-bit):
 *   Bits 31:4 - Command-specific data (must be 16-byte aligned)
 *   Bits 3:0  - Command opcode
 *
 * PORT commands:
 *   0 = Software reset
 *   1 = Self-test
 *   2 = Selective reset
 *   3 = Dump wake-up parameters
 *
 * Parameters:
 *   cmd - Command opcode (low 4 bits)
 *   arg - Command argument (must be 16-byte aligned, low 4 bits ignored)
 *
 * Returns: 0 (void function in original code)
 */
- (int)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg
{
    unsigned char *scbBase;
    unsigned int portValue;

    /* Get SCB base address */
    scbBase = *(unsigned char **)(((char *)self) + 0x1BC);

    /* Combine argument (aligned to 16 bytes) and command (low 4 bits) */
    portValue = (arg & 0xFFFFFFF0) | (cmd & 0x0F);

    /* Write to PORT register at offset +0x08 */
    *(unsigned int *)(scbBase + 8) = portValue;

    return 0;
}

/*
 * Get interrupt handler information
 * Returns the interrupt handler function, priority level, and argument
 *
 * This method is called by the IODirectDevice framework to obtain
 * the interrupt handler that should be called when hardware interrupts occur.
 *
 * Parameters:
 *   handler: Output - pointer to interrupt handler function (_intHandler)
 *   level: Output - interrupt priority level (3)
 *   arg: Output - argument to pass to handler (self)
 *   irq: Input - interrupt number (unused)
 *
 * Returns: YES (always succeeds)
 */
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)level
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)irq
{
    /* Set handler to _intHandler utility function */
    *handler = (IOInterruptHandler)_intHandler;

    /* Set interrupt priority level to 3 */
    *level = 3;

    /* Pass driver instance as argument */
    *arg = (unsigned int)self;

    return YES;
}

/*
 * Get power management settings
 */
- (IOReturn)getPowerManagement:(void *)powerManagement
{
    /* Power management not supported - return unsupported error */
    return 0xFFFFFD39;  /* IO_R_UNSUPPORTED */
}

/*
 * Get power state
 */
- (IOReturn)getPowerState:(void *)powerState
{
    /* Power management not supported - return unsupported error */
    return 0xFFFFFD39;  /* IO_R_UNSUPPORTED */
}

/*
 * Set power management
 * Power management is not supported by this driver
 *
 * Parameters:
 *   powerLevel - Requested power management level (ignored)
 *
 * Returns: IO_R_UNSUPPORTED (0xFFFFFD39)
 */
- (IOReturn)setPowerManagement:(unsigned int)powerLevel
{
    /* Power management not supported */
    return IO_R_UNSUPPORTED;
}

/*
 * Set power state
 * Sets the adapter's power state (only state 3 supported for power down)
 *
 * Driver instance structure:
 *   +0x1A0: PHY address
 *
 * Power states:
 *   3 = Power down (supported)
 *   Other states = Unsupported
 *
 * Parameters:
 *   powerState - Desired power state
 *
 * Returns: IO_R_SUCCESS (0) if state 3, IO_R_UNSUPPORTED otherwise
 */
- (IOReturn)setPowerState:(unsigned int)powerState
{
    unsigned char phyAddr;

    if (powerState == 3) {
        /* Power state 3 - power down the adapter */

        /* Clear any pending timeouts */
        [self clearTimeout];

        /* Disable adapter interrupts */
        [self disableAdapterInterrupts];

        /* Reset the chip */
        [self __resetChip];

        /* Disable interrupts again after reset */
        [self disableAdapterInterrupts];

        /* Power down PHY via MDI write
         * PHY address at +0x1A0
         * Register 0 (control register)
         * Data 0x9200 = Power down + Auto-negotiation enable + restart AN
         */
        phyAddr = *(unsigned char *)(((char *)self) + 0x1A0);
        [self __mdiWritePHY:phyAddr Register:0 Data:0x9200];

        return IO_R_SUCCESS;
    }

    /* Other power states not supported */
    return IO_R_UNSUPPORTED;
}

/*
 * Private: Abort receive operation
 * Stops the receive unit by sending RU_ABORT command
 *
 * Driver instance structure offsets:
 *   +0x1BC: SCB base address pointer
 *
 * SCB structure offsets:
 *   +0x00: Status register
 *   +0x02: Command register
 *
 * Returns: YES if successful, NO if timeout
 */
- (BOOL)__abortReceive
{
    char *cmdRegPtr;
    int timeout;
    const char *driverName;

    /* Get pointer to SCB command register (+0x02) */
    cmdRegPtr = (char *)(*(int *)((char *)self + 0x1BC) + 0x02);

    /* Wait for command register to clear (max 10000 us) */
    timeout = 0;
    do {
        if (*cmdRegPtr == 0) {
            break;
        }
        IODelay(1);
        timeout++;
    } while (timeout < 10000);

    if (*cmdRegPtr != 0) {
        /* Timeout waiting for SCB command clear */
        driverName = [[self name] cString];
        IOLog("%s: _abortReceive: _waitSCBCommandClear failed\n", driverName);
        return NO;
    }

    /* Send RU_ABORT command (0x04) - clear lower 3 bits and set bit 2 */
    *(unsigned char *)(*(int *)((char *)self + 0x1BC) + 0x02) =
        (*(unsigned char *)(*(int *)((char *)self + 0x1BC) + 0x02) & 0xF8) | 0x04;

    /* Wait for RU state to become idle (bits 2-5 of status should be 0) */
    timeout = 0;
    do {
        if ((*(unsigned char *)*(int *)((char *)self + 0x1BC) & 0x3C) == 0) {
            break;
        }
        IODelay(1);
        timeout++;
    } while (timeout < 10000);

    return ((*(unsigned char *)*(int *)((char *)self + 0x1BC) & 0x3C) == 0);
}

/*
 * Private: Dump statistics
 * Triggers the hardware to dump statistics and waits for completion
 *
 * Driver instance structure offsets:
 *   +0x1BC: SCB base address pointer
 *   +0x1EC: CU state storage
 *
 * Returns: YES if successful, NO if timeout
 */
- (BOOL)__dumpStatistics
{
    int splLevel;
    char *cmdRegPtr;
    int timeout;
    const char *driverName;
    int scbBase;
    BOOL success;

    /* Raise interrupt priority level */
    splLevel = spldevice();

    /* Get pointer to SCB command register (+0x02) */
    cmdRegPtr = (char *)(*(int *)((char *)self + 0x1BC) + 0x02);

    /* Wait for command register to clear (max 10000 us) */
    timeout = 0;
    do {
        if (*cmdRegPtr == 0) {
            break;
        }
        splx(splLevel);
        IODelay(1);
        splLevel = spldevice();
        timeout++;
    } while (timeout < 10000);

    if (*cmdRegPtr != 0) {
        /* Timeout waiting for SCB command clear */
        splx(splLevel);
        driverName = [[self name] cString];
        IOLog("%s: _dumpStatistics: _waitSCBCommandClear failed\n", driverName);
        return NO;
    }

    /* Get SCB base and issue CU dump statistics command */
    scbBase = *(int *)((char *)self + 0x1BC);

    /* Set CU command bits (0x70 = dump statistics and reset) */
    *(unsigned char *)(scbBase + 0x02) =
        *(unsigned char *)(scbBase + 0x02) | 0x70;

    /* Save CU state (bits 4-6 of command register) */
    *(unsigned int *)((char *)self + 0x1EC) =
        (*(unsigned char *)(scbBase + 0x02) >> 4) & 0x07;

    /* Restore interrupt priority level */
    splx(splLevel);

    return YES;
}

/*
 * Private: Get model ID
 * Reads PHY model and revision from MII registers 2 and 3
 *
 * Driver instance structure offsets:
 *   +0x1A0: PHY address
 *
 * Returns: 32-bit value with model ID in upper 16 bits and revision in lower 16 bits
 */
- (unsigned int)__getModelId
{
    unsigned short reg2Data;
    unsigned short reg3Data;
    unsigned int modelId;

    /* Read MII register 2 (PHY identifier 1) */
    [self __mdiReadPHY:*(unsigned char *)((char *)self + 0x1A0)
              Register:2
                  Data:&reg3Data];

    /* Read MII register 3 (PHY identifier 2) */
    [self __mdiReadPHY:*(unsigned char *)((char *)self + 0x1A0)
              Register:3
                  Data:&reg2Data];

    /* Combine into 32-bit model ID:
     * Upper 16 bits: reg3Data (shifted left 16)
     * Lower 16 bits: combined reg2Data and reg3Data
     */
    modelId = (((unsigned int)reg2Data << 16) << 16) |
              (((unsigned int)reg2Data << 16) | reg3Data);

    return modelId;
}

/*
 * Private: Initialize RFD (Receive Frame Descriptor) list
 * Allocates and initializes 32 Receive Frame Descriptors in a circular list
 *
 * Driver instance structure offsets:
 *   +0x1FC: RFD list base address
 *   +0x200: Current RFD pointer
 *   +0x204: Previous RFD pointer
 *   +0x218: Free netbuf queue head
 *   +0x21C: Free netbuf queue tail
 *   +0x220: Free netbuf queue count
 *
 * RFD structure (0x48 bytes each):
 *   +0x00: Status
 *   +0x02: Command
 *   +0x04: Link address
 *   +0x08: RBD address
 *   +0x20: Next RFD pointer
 *   +0x24: Physical address
 *   +0x28: RBD area start
 *   +0x2C: RBD buffer address
 *   +0x30: RBD buffer physical address
 *   +0x34: RBD size
 *   +0x3C: Next RBD pointer
 *   +0x40: RBD physical address
 *   +0x44: Netbuf pointer
 *
 * Returns: YES if successful, NO if error
 */
- (BOOL)__initRfdList
{
    int i;
    int offset;
    int rfdBase;
    int rfdAddr;
    unsigned char *cmdPtr;
    const char *driverName;
    int vmTask;
    int result;
    netbuf_t *netbufPtr;
    netbuf_t nb;
    int *countPtr;
    unsigned short *sizePtr;

    /* Free any existing netbufs from RFD list */
    for (i = 0; i < 0x20; i++) {
        offset = i * 0x48;
        rfdBase = *(int *)((char *)self + 0x1FC);

        if (*(netbuf_t *)(rfdBase + 0x44 + offset) != NULL) {
            nb_free(*(netbuf_t *)(rfdBase + 0x44 + offset));
            *(netbuf_t *)(rfdBase + 0x44 + offset) = NULL;
        }
    }

    /* Zero the entire RFD list area (32 * 0x48 = 0x900 bytes) */
    bzero(*(void **)((char *)self + 0x1FC), 0x900);

    /* Initialize each RFD and validate addresses */
    for (i = 0; i < 0x20; i++) {
        offset = i * 0x48;

        /* Set Suspend and Flexible mode bits in command field */
        cmdPtr = (unsigned char *)(*(int *)((char *)self + 0x1FC) + 0x02 + offset);
        *cmdPtr |= 0x08;  /* Set SF (Suspend/Flexible) bit */

        /* Validate RFD physical address */
        rfdAddr = offset + *(int *)((char *)self + 0x1FC);
        vmTask = IOVmTaskSelf(rfdAddr, rfdAddr + 0x24);
        result = IOPhysicalFromVirtual(vmTask);

        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Invalid RFD address\n", driverName);
            return NO;
        }

        /* Validate RBD physical address */
        rfdAddr = offset + *(int *)((char *)self + 0x1FC);
        vmTask = IOVmTaskSelf(rfdAddr + 0x28, rfdAddr + 0x40);
        result = IOPhysicalFromVirtual(vmTask);

        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Invalid RBD address\n", driverName);
            return NO;
        }
    }

    /* Link RFDs into circular list and initialize fields */
    for (i = 0; i < 0x20; i++) {
        offset = i * 0x48;
        rfdBase = *(int *)((char *)self + 0x1FC);

        if (i == 0x1F) {
            /* Last RFD - set EL bit and point back to first */
            cmdPtr = (unsigned char *)(rfdBase + 0x8BB);  /* +0x8BB = 31*0x48 + 3 */
            *cmdPtr |= 0x80;  /* Set EL (End of List) bit */

            /* Point back to first RFD */
            *(int *)(rfdBase + 0x8D8) = rfdBase;  /* Link address */
            *(unsigned short *)(rfdBase + 0x8EE) = 1;  /* Count = 1 */
            *(int *)(rfdBase + 0x8F4) = rfdBase + 0x28;  /* RBD address */
        } else {
            /* Point to next RFD */
            *(int *)(rfdBase + 0x20 + offset) = rfdBase + offset + 0x48;
            *(int *)(rfdBase + 0x3C + offset) = rfdBase + offset + 0x48 + 0x28;
        }

        /* Set link address to physical address of next RFD */
        *(int *)(rfdBase + 0x04 + offset) =
            *(int *)(*(int *)(rfdBase + 0x20 + offset) + 0x24);

        /* Set RBD address */
        if (i == 0) {
            /* First RFD gets RBD address from offset 0x40 */
            *(int *)(rfdBase + 0x08 + offset) = *(int *)(rfdBase + 0x40);
        } else {
            /* Other RFDs get 0xFFFFFFFF (no RBD initially) */
            *(int *)(rfdBase + 0x08 + offset) = 0xFFFFFFFF;
        }

        /* Set RBD buffer address */
        *(int *)(rfdBase + 0x2C + offset) =
            *(int *)(*(int *)(rfdBase + 0x3C + offset) + 0x18);

        /* Set RBD size (clear upper bits, set size to 0x5EE = 1518 bytes) */
        sizePtr = (unsigned short *)(rfdBase + 0x34 + offset);
        *sizePtr = (*sizePtr & 0xC000) | 0x5EE;

        /* Allocate netbuf from free queue */
        if (*(int *)((char *)self + 0x220) == 0) {
            netbufPtr = NULL;
        } else {
            netbufPtr = *(netbuf_t **)((char *)self + 0x218);
            *(netbuf_t **)((char *)self + 0x218) = *netbufPtr;
            countPtr = (int *)((char *)self + 0x220);
            (*countPtr)--;
            if (*countPtr == 0) {
                *(int *)((char *)self + 0x21C) = 0;
                *(int *)((char *)self + 0x218) = 0;
            }
            *netbufPtr = NULL;
        }

        if (netbufPtr == NULL) {
            driverName = [[self name] cString];
            IOLog("%s: receive buffer allocation failed\n", driverName);
        }

        /* Store netbuf pointer in RFD */
        *(netbuf_t **)(rfdBase + 0x44 + offset) = netbufPtr;

        /* Map netbuf and store physical address */
        netbufPtr = (netbuf_t *)nb_map((netbuf_t)netbufPtr);
        *(void **)(rfdBase + 0x30 + offset) = *netbufPtr;
    }

    /* Set current and previous RFD pointers */
    *(int *)((char *)self + 0x200) = *(int *)((char *)self + 0x1FC);
    *(int *)((char *)self + 0x204) = *(int *)((char *)self + 0x1FC) + 0x8B8;  /* Last RFD */

    return YES;
}

/*
 * Private: Initialize TCB (Transmit Command Block) queue
 * Allocates and initializes 16 Transmit Command Blocks in a circular list
 *
 * Driver instance structure offsets:
 *   +0x1D4: TCB count (16)
 *   +0x1D8: TCB head pointer
 *   +0x1DC: TCB tail pointer
 *   +0x1E0: TCB current pointer
 *   +0x1E4: TCB free count
 *   +0x1E8: TCB list base address
 *
 * TCB structure (0x2C = 44 bytes each):
 *   +0x00: Status
 *   +0x02: Command
 *   +0x04: Link address (physical)
 *   +0x08: TBD array address
 *   +0x10: Next TCB pointer
 *   +0x14: Physical address
 *   +0x18: TBD area start
 *   +0x28: Netbuf pointer
 *
 * Returns: YES if successful, NO if error
 */
- (BOOL)__initTcbQ
{
    int i;
    int offset;
    int tcbBase;
    int tcbAddr;
    int vmTask;
    int result;

    /* Set TCB count to 16 */
    *(int *)((char *)self + 0x1D4) = 0x10;

    /* Set free count to 16 */
    *(int *)((char *)self + 0x1E4) = 0x10;

    /* Initialize all pointers to base address */
    tcbBase = *(int *)((char *)self + 0x1E8);
    *(int *)((char *)self + 0x1E0) = tcbBase;  /* Current */
    *(int *)((char *)self + 0x1DC) = tcbBase;  /* Tail */
    *(int *)((char *)self + 0x1D8) = tcbBase;  /* Head */

    /* Free any existing netbufs from TCB list */
    for (i = 0; i < *(int *)((char *)self + 0x1D4); i++) {
        offset = i * 0x2C;
        if (*(netbuf_t *)(*(int *)((char *)self + 0x1E8) + 0x28 + offset) != NULL) {
            nb_free(*(netbuf_t *)(*(int *)((char *)self + 0x1E8) + 0x28 + offset));
            *(netbuf_t *)(*(int *)((char *)self + 0x1E8) + 0x28 + offset) = NULL;
        }
    }

    /* Zero the entire TCB list area (16 * 0x2C bytes) */
    bzero(*(void **)((char *)self + 0x1E8),
          *(int *)((char *)self + 0x1D4) * 0x2C);

    /* Validate physical addresses for each TCB */
    for (i = 0; i < *(int *)((char *)self + 0x1D4); i++) {
        /* Validate TCB physical address */
        tcbAddr = i * 0x2C + *(int *)((char *)self + 0x1E8);
        vmTask = IOVmTaskSelf(tcbAddr, tcbAddr + 0x14);
        result = IOPhysicalFromVirtual(vmTask);

        if (result != 0) {
            IOLog("i82557(tcbQ): Invalid TCB address\n");
            return NO;
        }

        /* Validate TBD physical address */
        tcbAddr = i * 0x2C + *(int *)((char *)self + 0x1E8);
        vmTask = IOVmTaskSelf(tcbAddr + 0x18, tcbAddr + 0x08);
        result = IOPhysicalFromVirtual(vmTask);

        if (result != 0) {
            IOLog("i82557(tcbQ): Invalid TBD address\n");
            return NO;
        }

        /* Link TCBs in circular list */
        if (i == *(int *)((char *)self + 0x1D4) - 1) {
            /* Last TCB points back to first */
            *(int *)(*(int *)((char *)self + 0x1E8) + 0x10 + i * 0x2C) =
                *(int *)((char *)self + 0x1E8);
        } else {
            /* Point to next TCB */
            *(int *)(*(int *)((char *)self + 0x1E8) + 0x10 + i * 0x2C) =
                i * 0x2C + 0x2C + *(int *)((char *)self + 0x1E8);
        }
    }

    /* Set link addresses to physical addresses of next TCB */
    for (i = 0; i < *(int *)((char *)self + 0x1D4); i++) {
        *(int *)(*(int *)((char *)self + 0x1E8) + 0x04 + i * 0x2C) =
            *(int *)(*(int *)(*(int *)((char *)self + 0x1E8) + 0x10 + i * 0x2C) + 0x14);
    }

    return YES;
}

/*
 * Private: MDI Read PHY register
 * Reads a 16-bit register from the PHY via the MDI interface
 *
 * Driver instance structure offsets:
 *   +0x1BC: SCB base address pointer
 *
 * SCB MDI Control Register (+0x10):
 *   Bits 31-28: Opcode (1 = write, 2 = read)
 *   Bits 27-23: PHY address (5 bits)
 *   Bits 20-16: Register address (5 bits)
 *   Bits 15-0:  Data
 *   Bit 28: Ready (1 when operation complete)
 *
 * Returns: 0 on success, -1 on timeout
 */
- (int)__mdiReadPHY:(int)phyAddr Register:(int)regAddr Data:(unsigned short *)data
{
    unsigned int mdiCmd;
    int timeout;
    const char *driverName;

    /* Build MDI command register value */
    bzero(&mdiCmd, 4);

    /* Clear PHY address field (bits 27-23) */
    mdiCmd &= 0xFC1FFFFF;

    /* Set PHY address (bits 27-23) */
    mdiCmd |= ((phyAddr & 0x1F) << 21);

    /* Clear register address field (bits 20-16) */
    mdiCmd &= 0xFFE0FFFF;

    /* Set register address (bits 20-16) */
    mdiCmd |= ((regAddr & 0x1F) << 16);

    /* Clear opcode field (bits 31-28) and set to READ (0x02) */
    mdiCmd &= 0xF3FFFFFF;
    mdiCmd |= 0x08000000;  /* Read opcode (2 << 26) */

    /* Write command to MDI control register */
    *(unsigned int *)(*(int *)((char *)self + 0x1BC) + 0x10) = mdiCmd;

    /* Wait a bit for command to start */
    IODelay(20);

    /* Wait for Ready bit (bit 28) to be set (max 10ms) */
    timeout = 0;
    do {
        if ((*(unsigned char *)(*(int *)((char *)self + 0x1BC) + 0x13) & 0x10) != 0) {
            /* Ready bit is set - read data */
            *data = *(unsigned short *)(*(int *)((char *)self + 0x1BC) + 0x10);
            return 0;
        }
        IODelay(20);
        timeout++;
    } while (timeout < 10000);

    /* Timeout */
    driverName = [[self name] cString];
    IOLog("%s: _mdiReadPHYRegisterSuccess timeout\n", driverName);
    return -1;
}

/*
 * Private: MDI Write PHY register
 * Writes a 16-bit value to a PHY register via the MDI interface
 *
 * Driver instance structure offsets:
 *   +0x1BC: SCB base address pointer
 *
 * SCB MDI Control Register (+0x10):
 *   Bits 31-28: Opcode (1 = write, 2 = read)
 *   Bits 27-23: PHY address (5 bits)
 *   Bits 20-16: Register address (5 bits)
 *   Bits 15-0:  Data
 *   Bit 28: Ready (1 when operation complete)
 *
 * Returns: 0 on success, -1 on timeout
 */
- (int)__mdiWritePHY:(int)phyAddr Register:(int)regAddr Data:(unsigned short)data
{
    unsigned int mdiCmd;
    int timeout;
    const char *driverName;

    /* Build MDI command register value */
    bzero(&mdiCmd, 4);

    /* Set PHY address (bits 27-23) */
    mdiCmd &= 0xFC1FFFFF;  /* Clear PHY field first */
    mdiCmd |= ((phyAddr & 0x1F) << 21);

    /* Set register address (bits 20-16) */
    mdiCmd &= 0xFFE0FFFF;  /* Clear register field first */
    mdiCmd |= ((regAddr & 0x1F) << 16);

    /* Set data (bits 15-0) */
    mdiCmd = (mdiCmd & 0xFFFF0000) | data;

    /* Set opcode to WRITE (0x01) - bits 27-26 */
    mdiCmd = (mdiCmd & 0xF3FFFFFF) | 0x04000000;  /* Write opcode (1 << 26) */

    /* Write command to MDI control register */
    *(unsigned int *)(*(int *)((char *)self + 0x1BC) + 0x10) = mdiCmd;

    /* Wait a bit for command to start */
    IODelay(20);

    /* Wait for Ready bit (bit 28) to be set (max 10ms) */
    timeout = 0;
    do {
        if ((*(unsigned char *)(*(int *)((char *)self + 0x1BC) + 0x13) & 0x10) != 0) {
            /* Ready bit is set - operation complete */
            return 0;
        }
        IODelay(20);
        timeout++;
    } while (timeout < 10000);

    /* Timeout */
    driverName = [[self name] cString];
    IOLog("%s: _mdiWritePHYRegisterData timeout\n", driverName);
    return -1;
}

/*
 * Private: Allocate memory
 * Allocates memory from the shared DMA memory pool
 *
 * Driver instance structure offsets:
 *   +0x1A4: Shared memory base address
 *   +0x1AC: Current allocation pointer
 *   +0x1B0: Remaining free space
 *
 * The memory is allocated from a pre-allocated shared memory region
 * and automatically aligned to 4-byte boundaries.
 *
 * Returns: Pointer to allocated memory, or panics if exhausted
 */
- (void *)__memAlloc:(unsigned int)size
{
    void *allocPtr;

    /* Check if requested size exceeds available space */
    if (*(unsigned int *)((char *)self + 0x1B0) < size) {
        IOPanic("Intel82557: shared memory exhausted\n");
    }

    /* Get current allocation pointer */
    allocPtr = *(void **)((char *)self + 0x1AC);

    /* Advance allocation pointer */
    *(int *)((char *)self + 0x1AC) =
        *(int *)((char *)self + 0x1AC) + size;

    /* Align to 4-byte boundary if necessary */
    if ((*(unsigned char *)((char *)self + 0x1AC) & 0x03) != 0) {
        *(unsigned int *)((char *)self + 0x1AC) =
            (*(int *)((char *)self + 0x1AC) + 3) & 0xFFFFFFFC;
    }

    /* Update remaining free space */
    *(int *)((char *)self + 0x1B0) =
        _page_size - (*(int *)((char *)self + 0x1AC) -
                      *(int *)((char *)self + 0x1A4));

    return allocPtr;
}

/*
 * Private: Detect PHY
 * Detects and initializes the PHY (Physical Layer) chip
 *
 * Driver instance structure offsets:
 *   +0x1A0: PHY address
 *   +0x1A1: Debug flag
 *   +0x1BC: SCB base address
 *   +0x22C: PHY type/flags
 *
 * Returns: 1 on success, 0 on failure
 */
- (int)__phyDetect
{
    char *cmdRegPtr;
    int timeout;
    const char *driverName;
    unsigned short reg0Data, reg1Data;
    BOOL phy1Found = NO;
    int i;

    /* Wait for SCB command register to clear */
    cmdRegPtr = (char *)(*(int *)((char *)self + 0x1BC) + 0x02);
    timeout = 0;
    do {
        if (*cmdRegPtr == 0) {
            break;
        }
        IODelay(1);
        timeout++;
    } while (timeout < 10000);

    if (*cmdRegPtr != 0) {
        driverName = [[self name] cString];
        IOLog("%s: phyDetect: _waitSCBCommandClear failed\n", driverName);
        return 0;
    }

    /* Check for special 82503 serial interface case */
    if (*(unsigned char *)((char *)self + 0x1A0) == 0x20) {
        if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
            driverName = [[self name] cString];
            IOLog("%s: overriding to use Intel 82503", driverName);
        }
        *(int *)((char *)self + 0x22C) = 0;
        return 1;
    }

    /* Check if PHY address is invalid (0 or > 31) - auto-detect mode */
    if ((*(unsigned char *)((char *)self + 0x1A0) == 0) ||
        (*(unsigned char *)((char *)self + 0x1A0) > 0x1F)) {
        goto detect_phy0;
    }

    /* Try to detect PHY 1 at specified address */
    if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
        driverName = [[self name] cString];
        IOLog("%s: looking for Phy 1 at address %d\n",
              driverName, *(unsigned char *)((char *)self + 0x1A0));
    }

    /* Read PHY registers 0 and 1 at specified address */
    [self __mdiReadPHY:*(unsigned char *)((char *)self + 0x1A0)
              Register:0
                  Data:&reg0Data];
    [self __mdiReadPHY:*(unsigned char *)((char *)self + 0x1A0)
              Register:1
                  Data:&reg1Data];

    /* Check if PHY exists (registers not 0xFFFF or all zeros) */
    if ((reg0Data == 0xFFFF) || ((reg1Data == 0) && (reg0Data == 0))) {
        if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
            driverName = [[self name] cString];
            IOLog("%s: Phy 1 at address %d does not exist\n",
                  driverName, *(unsigned char *)((char *)self + 0x1A0));
        }
        goto detect_phy0;
    }

    if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
        driverName = [[self name] cString];
        IOLog("%s: Phy 1 at address %d exists\n",
              driverName, *(unsigned char *)((char *)self + 0x1A0));
    }

    phy1Found = YES;

    /* Check if link is up (bit 2 of register 1) */
    if ((reg1Data & 0x04) == 0) {
        goto detect_phy0;
    }

    if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
        driverName = [[self name] cString];
        IOLog("%s: found Phy 1 at address %d with link\n",
              driverName, *(unsigned char *)((char *)self + 0x1A0));
    }
    goto setup_phy;

detect_phy0:
    /* Try to detect PHY at address 0 */
    [self __mdiReadPHY:0 Register:0 Data:&reg0Data];
    [self __mdiReadPHY:0 Register:1 Data:&reg1Data];

    /* Check if PHY exists at address 0 */
    if ((reg0Data == 0xFFFF) || ((reg1Data == 0) && (reg0Data == 0))) {
        if (*(unsigned char *)((char *)self + 0x1A0) == 0) {
            driverName = [[self name] cString];
            IOLog("%s: phy0 not detected\n", driverName);
            return 0;
        }

        /* No PHY at address 0 */
        if (!phy1Found) {
            /* No PHY 1 either - default to 82503 */
            if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
                driverName = [[self name] cString];
                IOLog("%s: no Phy at address 0, defaulting to 82503\n", driverName);
            }
            *(unsigned char *)((char *)self + 0x1A0) = 0x20;
            return 1;
        }

        /* PHY 1 exists but no link - use it anyway */
        if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
            driverName = [[self name] cString];
            IOLog("%s: no Phy at address 0, using Phy 1 without link\n", driverName);
        }
        goto setup_phy;
    }

    /* PHY 0 found - perform auto-negotiation if PHY 1 was also found */
    if (phy1Found) {
        /* Isolate PHY 1 */
        reg0Data = 0x400;
        [self __mdiWritePHY:*(unsigned char *)((char *)self + 0x1A0)
                   Register:0
                       Data:0x400];
        IOSleep(1);
    }

    if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
        driverName = [[self name] cString];
        IOLog("%s: starting auto-negotiation on Phy 1", driverName);
    }

    /* Reset PHY */
    reg0Data = 0x1000;
    [self __mdiWritePHY:0 Register:0 Data:0x1000];
    IOSleep(1);

    /* Enable and restart auto-negotiation */
    reg0Data |= 0x200;  /* 0x1200 */
    [self __mdiWritePHY:0 Register:0 Data:reg0Data];

    /* Wait for auto-negotiation to complete (bit 5 of register 1) */
    for (i = 0; i < 0x23; i++) {
        [self __mdiReadPHY:0 Register:1 Data:&reg1Data];
        if ((reg1Data & 0x20) != 0) {
            break;
        }
        IOSleep(100);
    }

    /* Check link status */
    [self __mdiReadPHY:0 Register:1 Data:&reg1Data];

    if (((reg1Data & 0x04) == 0) && phy1Found) {
        /* No link on PHY 0, use PHY 1 without link */
        if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
            driverName = [[self name] cString];
            IOLog("%s: using Phy 1 without link\n", driverName);
        }

        /* Isolate PHY 0 */
        reg0Data = 0x400;
        [self __mdiWritePHY:0 Register:0 Data:0x400];
        IOSleep(1);

        /* Reset PHY 1 */
        reg0Data = 0x1000;
        [self __mdiWritePHY:*(unsigned char *)((char *)self + 0x1A0)
                   Register:0
                       Data:0x1000];
        IOSleep(1);

        /* Enable and restart auto-negotiation on PHY 1 */
        reg0Data |= 0x200;  /* 0x1200 */
        [self __mdiWritePHY:*(unsigned char *)((char *)self + 0x1A0)
                   Register:0
                       Data:reg0Data];
        goto setup_phy;
    }

    /* Use PHY 0 */
    if (*(unsigned char *)((char *)self + 0x1A1) == 1) {
        driverName = [[self name] cString];
        IOLog("%s: using Phy 0 at address 0\n", driverName);
    }
    *(unsigned char *)((char *)self + 0x1A0) = 0;

setup_phy:
    /* Call PHY setup */
    [self __setupPhy];
    return 1;
}

/*
 * Private: Polled command execution
 * Executes a command block in polled mode (waiting for completion)
 *
 * Driver instance structure offsets:
 *   +0x1BC: SCB base address
 *   +0x1EC: CU state storage
 *
 * Command block structure:
 *   +0x01: Status (bit 7 = complete, bit 5 = OK)
 *   +0x02: Command opcode (bits 0-2)
 *
 * Returns: 1 if OK bit set, 0 otherwise
 */
- (int)__polledCommand:(void *)cmd WithAddress:(unsigned int)addr
{
    char *cmdRegPtr;
    unsigned char *scbStatusPtr;
    int timeout;
    const char *driverName;
    int scbBase;
    const char *cmdNames[] = {"nop", "iasetup", "configure", "mcsetup", "transmit"};
    const char *cmdName;

    /* Wait for SCB command register to clear */
    cmdRegPtr = (char *)(*(int *)((char *)self + 0x1BC) + 0x02);
    timeout = 0;
    do {
        if (*cmdRegPtr == 0) {
            break;
        }
        IODelay(1);
        timeout++;
    } while (timeout < 10000);

    if (*cmdRegPtr != 0) {
        /* Timeout waiting for command clear */
        driverName = [[self name] cString];
        cmdName = cmdNames[*(unsigned char *)((char *)cmd + 0x02) & 0x07];
        IOLog("%s: _polledCommand:(%s): _waitSCBCommandClear failed\n",
              driverName, cmdName);
        return 0;
    }

    /* Wait for CU to become non-active (bits 6-7 of status != 0x80) */
    scbStatusPtr = *(unsigned char **)((char *)self + 0x1BC);
    timeout = 0;
    do {
        if ((*scbStatusPtr & 0xC0) != 0x80) {
            break;
        }
        IODelay(1);
        timeout++;
    } while (timeout < 10000);

    if ((*scbStatusPtr & 0xC0) == 0x80) {
        /* Timeout waiting for CU non-active */
        driverName = [[self name] cString];
        cmdName = cmdNames[*(unsigned char *)((char *)cmd + 0x02) & 0x07];
        IOLog("%s: _polledCommand:(%s): _waitCUNonActive failed\n",
              driverName, cmdName);
        return 0;
    }

    /* Set general pointer to command address */
    *(unsigned int *)(*(int *)((char *)self + 0x1BC) + 0x04) = addr;

    /* Issue CU START command (0x10) */
    scbBase = *(int *)((char *)self + 0x1BC);
    *(unsigned char *)(scbBase + 0x02) =
        (*(unsigned char *)(scbBase + 0x02) & 0x8F) | 0x10;

    /* Save CU state (bits 4-6 of command register) */
    *(unsigned int *)((char *)self + 0x1EC) =
        (*(unsigned char *)(scbBase + 0x02) >> 4) & 0x07;

    /* Wait for command to complete (bit 7 of status byte in command block) */
    timeout = 0;
    do {
        if (*(char *)((char *)cmd + 0x01) < 0) {  /* Bit 7 set = complete */
            break;
        }
        IODelay(1);
        timeout++;
    } while (timeout < 10000);

    /* Return OK bit (bit 5 of status byte) */
    return (*(unsigned char *)((char *)cmd + 0x01) >> 5) & 0x01;
}

/*
 * Private: Reset chip
 */
- (void)__resetChip
{
    IOLog("Intel82557: __resetChip\n");

    // TODO: Perform chip reset
}

/*
 * Private: Schedule reset
 */
- (void)__scheduleReset
{
    IOLog("Intel82557: __scheduleReset\n");

    // TODO: Schedule deferred reset
}

/*
 * Private: Self test
 */
- (BOOL)__selfTest
{
    IOLog("Intel82557: __selfTest\n");

    // TODO: Execute hardware self-test

    return NO;
}

/*
 * Private: Setup PHY
 */
- (void)__setupPhy
{
    IOLog("Intel82557: __setupPhy\n");

    // TODO: Configure PHY for link operation
}

/*
 * Private: Start receive unit
 * Starts the receive unit and waits for it to become ready
 *
 * Driver instance structure:
 *   +0x1BC: SCB base address
 *   +0x200: Current RFD pointer
 *
 * RFD structure:
 *   +0x24: Physical address for DMA
 *
 * SCB Register Offsets:
 *   +0x00: Status byte
 *   +0x02: Command byte
 *   +0x04: General pointer (32-bit)
 *
 * RU Status (bits 2-5 of status byte):
 *   0x00: Idle
 *   0x04: Suspended
 *   0x08: No resources
 *   0x10: Ready (successfully started)
 *
 * Returns: YES on success, NO on failure
 */
- (BOOL)__startReceive
{
    unsigned char *scbBase;
    volatile unsigned char *commandReg;
    volatile unsigned char *statusReg;
    volatile unsigned int *generalPtrReg;
    unsigned int rfdPhysAddr;
    int timeout;
    const char *driverName;

    scbBase = *(unsigned char **)(((char *)self) + 0x1BC);
    statusReg = scbBase;
    commandReg = scbBase + 2;
    generalPtrReg = (unsigned int *)(scbBase + 4);

    /* Wait for SCB command register to clear (10ms timeout) */
    timeout = 10000;
    while (*commandReg != 0 && timeout > 0) {
        IODelay(1);
        timeout--;
    }

    if (*commandReg == 0) {
        /* Get physical address of first RFD from current RFD pointer */
        rfdPhysAddr = *(unsigned int *)(*(int *)(((char *)self) + 0x200) + 0x24);

        /* Set general pointer to RFD physical address */
        *generalPtrReg = rfdPhysAddr;

        /* Issue RU START command (0x01) */
        *commandReg = (*commandReg & 0xF8) | 0x01;

        /* Wait for RU to reach ready state (bits 2-5 = 0x10) */
        timeout = 10000;
        while ((*statusReg & 0x3C) != 0x10 && timeout > 0) {
            IODelay(1);
            timeout--;
        }

        /* Check if RU is ready */
        if ((*statusReg & 0x3C) == 0x10) {
            return YES;
        }
    } else {
        driverName = [[self name] cString];
        IOLog("%s: _startReceive: _waitSCBCommandClear failed\n", driverName);
    }

    return NO;
}

/*
 * Private: Transmit packet (internal)
 * Prepares and submits a packet for transmission
 *
 * Driver instance structure:
 *   +0x184: Network interface
 *   +0x198: Transmit in progress flag
 *   +0x19C: Interrupt counter (generate interrupt every 8th packet)
 *   +0x1BC: SCB base address
 *   +0x1DC: Last TCB pointer
 *   +0x1E0: Current TCB pointer
 *   +0x1E4: Free TCB count
 *   +0x1EC: CU state
 *
 * TCB structure:
 *   +0x00: Status word
 *   +0x02: Command word
 *   +0x03: Command byte (high byte of command word)
 *   +0x0C: TBD count
 *   +0x0E: Transmit threshold
 *   +0x0F: Number of TBDs
 *   +0x10: Link address (next TCB)
 *   +0x14: TBD array pointer
 *   +0x18: First TBD
 *   +0x1C: TBD physical address
 *   +0x20: Second TBD
 *   +0x24: Second TBD physical address
 *   +0x28: Netbuf pointer (stored for later freeing)
 *
 * TBD structure:
 *   +0x00: Size (bits 0-13) and control bits
 *   +0x04: Physical address
 */
- (void)__transmitPacket:(netbuf_t)packet
{
    unsigned char *scbBase;
    unsigned short *currentTcb;
    unsigned char *lastTcb;
    id networkInterface;
    unsigned int *tbd;
    unsigned int virtAddr;
    unsigned int physAddr;
    unsigned int packetSize;
    unsigned int contiguousSize;
    unsigned int firstFragSize;
    int spl;
    int timeout;
    const char *driverName;
    vm_task_t vmTask;
    int result;

    /* Set transmit in progress flag */
    *(unsigned char *)(((char *)self) + 0x198) = 1;

    /* Perform loopback if enabled (for testing) */
    [self performLoopback:packet];

    /* Increment output packet counter */
    networkInterface = *(id *)(((char *)self) + 0x184);
    [networkInterface incrementOutputPackets];

    /* Get current TCB pointer */
    currentTcb = *(unsigned short **)(((char *)self) + 0x1E0);

    /* Initialize TCB fields */
    currentTcb[0] = 0;  /* Status word */
    currentTcb[1] = 0;  /* Command word */

    /* Clear command bits 0-2 */
    ((unsigned char *)currentTcb)[2] &= 0xF8;

    /* Set command: transmit (0x04) */
    ((unsigned char *)currentTcb)[2] |= 0x04;

    /* Set suspend bit (0x40) */
    ((unsigned char *)currentTcb)[3] |= 0x40;

    /* Handle interrupt generation (every 8th packet) */
    *(int *)(((char *)self) + 0x19C) = *(int *)(((char *)self) + 0x19C) + 1;

    if (*(int *)(((char *)self) + 0x19C) == 8) {
        /* Generate interrupt on this packet */
        ((unsigned char *)currentTcb)[3] |= 0x20;
        *(int *)(((char *)self) + 0x19C) = 0;
        *(unsigned char *)(((char *)self) + 0x198) = 1;
    } else {
        /* Don't generate interrupt */
        ((unsigned char *)currentTcb)[3] &= 0xDF;
    }

    /* Set CNA interrupt bit (0x08) */
    ((unsigned char *)currentTcb)[2] |= 0x08;

    /* Clear EL bit (0x80) */
    ((unsigned char *)currentTcb)[3] &= 0x7F;

    /* Set transmit threshold to 0xE0 (224 bytes) */
    ((unsigned char *)currentTcb)[0x0E] = 0xE0;

    /* Clear EOF flag */
    currentTcb[6] = 0;

    /* Point to TBD array (starts at TCB + 0x18) */
    tbd = (unsigned int *)(currentTcb + 0x0C);

    /* Set number of TBDs */
    ((unsigned char *)currentTcb)[0x0F] = 1;

    /* Store netbuf pointer for later freeing */
    *(netbuf_t *)(currentTcb + 0x14) = packet;

    /* Get virtual address of packet data */
    virtAddr = (unsigned int)nb_map(packet);

    /* Get packet size */
    packetSize = nb_size(packet);

    /* Check if packet is physically contiguous */
    contiguousSize = _IOIsPhysicallyContiguous(virtAddr, packetSize);

    if (contiguousSize == 0) {
        driverName = [[self name] cString];
        IOLog("%s: IOIsPhysicallyContiguous returned NULL\n", driverName);
        goto transmitError;
    }

    /* Calculate size of contiguous region */
    contiguousSize = (contiguousSize - virtAddr) + 1;

    /* If not fully contiguous, need to split into multiple TBDs */
    if (contiguousSize < packetSize) {
        /* Get physical address of first fragment */
        vmTask = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(vmTask, virtAddr, &physAddr);

        if (result != 0) {
            driverName = [[self name] cString];
            IOLog("%s: Invalid address for outgoing packet (before piece)\n", driverName);
            goto transmitError;
        }

        /* Set first TBD size (bits 0-13) */
        currentTcb[0x0E] = contiguousSize & 0x3FFF;

        /* Update for second fragment */
        packetSize -= contiguousSize;
        virtAddr += contiguousSize;

        /* Increment TBD count */
        ((unsigned char *)currentTcb)[0x0F]++;

        /* Point to second TBD */
        tbd = (unsigned int *)(currentTcb + 0x10);
    }

    /* Set size of (last) TBD */
    ((unsigned short *)tbd)[2] = packetSize & 0x3FFF;

    /* Get physical address for DMA */
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask, virtAddr, &physAddr);

    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid address for outgoing packet\n", driverName);
        goto transmitError;
    }

    /* Update TCB queue */
    *(int *)(((char *)self) + 0x1E4) = *(int *)(((char *)self) + 0x1E4) - 1;
    *(unsigned short **)(((char *)self) + 0x1E0) =
        *(unsigned short **)(*(int *)(((char *)self) + 0x1E0) + 0x10);

    /* Clear suspend bit on previous TCB */
    if (*(unsigned short **)(((char *)self) + 0x1DC) != currentTcb) {
        lastTcb = *(unsigned char **)(((char *)self) + 0x1DC);
        lastTcb[3] &= 0xBF;
    }

    /* Update last TCB pointer */
    *(unsigned short **)(((char *)self) + 0x1DC) = currentTcb;

    /* Disable interrupts for critical section */
    spl = spldevice();

    scbBase = *(unsigned char **)(((char *)self) + 0x1BC);

    /* Check CU state */
    if ((scbBase[0] & 0xC0) == 0) {
        /* CU is idle - issue CU START */
        volatile unsigned char *commandReg = scbBase + 2;

        /* Wait for SCB command register to clear */
        timeout = 10000;
        while (*commandReg != 0 && timeout > 0) {
            splx(spl);
            IODelay(1);
            spl = spldevice();
            timeout--;
        }

        if (*commandReg != 0) {
            splx(spl);
            driverName = [[self name] cString];
            IOLog("%s: _transmitPacket: _waitSCBCommandClearSPL failed\n", driverName);
            return;
        }

        /* Set general pointer to TCB physical address */
        *(unsigned int *)(scbBase + 4) = *(unsigned int *)(currentTcb + 10);

        /* Issue CU START command (0x10) */
        scbBase[2] = (scbBase[2] & 0x8F) | 0x10;

        /* Update CU state */
        *(unsigned int *)(((char *)self) + 0x1EC) = (scbBase[2] >> 4) & 7;
    } else {
        /* CU is active */
        if (*(int *)(((char *)self) + 0x1EC) != 2) {
            /* CU is not in RESUME state - wait for command clear */
            volatile unsigned char *commandReg = scbBase + 2;

            timeout = 10000;
            while (*commandReg != 0 && timeout > 0) {
                splx(spl);
                IODelay(1);
                spl = spldevice();
                timeout--;
            }

            if (*commandReg != 0) {
                splx(spl);
                driverName = [[self name] cString];
                IOLog("%s: _transmitPacket: _waitSCBCommandClear failed\n", driverName);
                return;
            }
        }

        /* Issue CU RESUME command (0x20) */
        scbBase[2] = (scbBase[2] & 0x8F) | 0x20;

        /* Update CU state */
        *(unsigned int *)(((char *)self) + 0x1EC) = (scbBase[2] >> 4) & 7;
    }

    splx(spl);
    return;

transmitError:
    /* Free packet on error */
    nb_free(packet);

    /* Clear netbuf pointer in TCB */
    *(netbuf_t *)(currentTcb + 0x14) = NULL;
}

/*
 * Private: Update statistics
 * Reads statistics from hardware and updates network interface counters
 *
 * Driver instance structure:
 *   +0x184: Network interface
 *   +0x1A1: Debug flag
 *   +0x1C8: Statistics buffer pointer
 *
 * Statistics buffer structure (all 32-bit integers):
 *   +0x00: TX good frames
 *   +0x04: TX maxcol errors
 *   +0x08: TX late collision errors
 *   +0x0C: TX underrun errors
 *   +0x10: TX lost carrier sense errors
 *   +0x14: TX deferred
 *   +0x18: TX single collisions
 *   +0x1C: TX multiple collisions
 *   +0x20: TX total collisions
 *   +0x24: RX good frames
 *   +0x28: RX CRC errors
 *   +0x2C: RX alignment errors
 *   +0x30: RX resource errors
 *   +0x34: RX overrun errors
 *   +0x38: RX collision detect errors
 *   +0x3C: RX short frame errors
 *   +0x40: Completion flag (non-zero = valid)
 */
- (void)__updateStatistics
{
    int *statsBuffer;
    id networkInterface;
    BOOL debugMode;
    int outputErrors;
    int inputErrors;
    int collisions;

    /* Get statistics buffer pointer */
    statsBuffer = *(int **)(((char *)self) + 0x1C8);

    /* Check if statistics are valid (completion flag at +0x40) */
    if (statsBuffer[0x10] == 0) {
        return;
    }

    debugMode = *(unsigned char *)(((char *)self) + 0x1A1);

    /* Log individual statistics in debug mode */
    if (debugMode) {
        if (statsBuffer[0] != 0) {
            IOLog("tx_good_frames %ld\n", statsBuffer[0]);
        }
        if (statsBuffer[1] != 0) {
            IOLog("tx_maxcol_errors %ld\n", statsBuffer[1]);
        }
        if (statsBuffer[2] != 0) {
            IOLog("tx_late_collision_errors %ld\n", statsBuffer[2]);
        }
        if (statsBuffer[3] != 0) {
            IOLog("tx_underrun_errors %ld\n", statsBuffer[3]);
        }
        if (statsBuffer[4] != 0) {
            IOLog("tx_lost_carrier_sense_errors %ld\n", statsBuffer[4]);
        }
        if (statsBuffer[5] != 0) {
            IOLog("tx_deferred %ld\n", statsBuffer[5]);
        }
        if (statsBuffer[6] != 0) {
            IOLog("tx_single_collisions %ld\n", statsBuffer[6]);
        }
        if (statsBuffer[7] != 0) {
            IOLog("tx_multiple_collisions %ld\n", statsBuffer[7]);
        }
        if (statsBuffer[8] != 0) {
            IOLog("tx_total_collisions %ld\n", statsBuffer[8]);
        }
        if (statsBuffer[9] != 0) {
            IOLog("rx_good_frames %ld\n", statsBuffer[9]);
        }
        if (statsBuffer[10] != 0) {
            IOLog("rx_crc_errors %ld\n", statsBuffer[10]);
        }
        if (statsBuffer[0x0B] != 0) {
            IOLog("rx_alignment_errors %ld\n", statsBuffer[0x0B]);
        }
        if (statsBuffer[0x0C] != 0) {
            IOLog("rx_resource_errors %ld\n", statsBuffer[0x0C]);
        }
        if (statsBuffer[0x0D] != 0) {
            IOLog("rx_overrun_errors %ld\n", statsBuffer[0x0D]);
        }
        if (statsBuffer[0x0E] != 0) {
            IOLog("rx_collision_detect_errors %ld\n", statsBuffer[0x0E]);
        }
        if (statsBuffer[0x0F] != 0) {
            IOLog("rx_short_frame_errors %ld\n", statsBuffer[0x0F]);
        }
    }

    networkInterface = *(id *)(((char *)self) + 0x184);

    /* Calculate total output errors */
    outputErrors = statsBuffer[2] +   /* late collision */
                   statsBuffer[1] +   /* maxcol */
                   statsBuffer[3] +   /* underrun */
                   statsBuffer[4];    /* lost carrier */

    [networkInterface incrementOutputErrorsBy:outputErrors];

    /* Calculate total input errors */
    inputErrors = statsBuffer[10] +    /* CRC */
                  statsBuffer[0x0B] +  /* alignment */
                  statsBuffer[0x0C] +  /* resource */
                  statsBuffer[0x0D] +  /* overrun */
                  statsBuffer[0x0E] +  /* collision detect */
                  statsBuffer[0x0F];   /* short frame */

    [networkInterface incrementInputErrorsBy:inputErrors];

    /* Update collision count */
    collisions = statsBuffer[8];  /* total collisions */
    [networkInterface incrementCollisionsBy:collisions];

    /* Clear completion flag */
    statsBuffer[0x10] = 0;

    /* Request statistics dump to refresh buffer */
    [self __dumpStatistics];
}

/*
 * Private: Execute command in polled mode
 * Sends a command to the CU and waits for completion by polling
 *
 * Driver instance structure:
 *   +0x1BC: SCB base address
 *   +0x1EC: CU state
 *
 * SCB Register Offsets:
 *   +0x00: Status word
 *   +0x02: Command word
 *   +0x04: General pointer (32-bit)
 *
 * Command block structure:
 *   +0x00: Status word (bit 7 = complete, bit 5 = OK)
 *   +0x02: Command word
 *
 * Returns: OK bit (1 if command succeeded, 0 if failed)
 */
- (int)__polledCommand:(void *)cmd WithAddress:(unsigned int)addr
{
    unsigned char *scbBase;
    volatile unsigned short *statusReg;
    volatile unsigned short *commandReg;
    volatile unsigned int *generalPtrReg;
    volatile unsigned short *cmdStatus;
    unsigned short statusWord;
    unsigned short commandWord;
    int timeout;
    int result;
    const char *commandNames[] = {"nop", "iasetup", "configure", "mcsetup", "transmit"};
    const char *cmdName;
    unsigned int cmdOpcode;

    scbBase = *(unsigned char **)(((char *)self) + 0x1BC);
    statusReg = (unsigned short *)scbBase;
    commandReg = (unsigned short *)(scbBase + 0x02);
    generalPtrReg = (unsigned int *)(scbBase + 0x04);

    /* Wait for SCB command register to clear (10ms timeout) */
    timeout = 10000;
    while (*commandReg != 0 && timeout > 0) {
        IODelay(1);
        timeout--;
    }

    if (timeout == 0) {
        IOLog("Intel82557: __polledCommand: SCB command register timeout\n");
        return 0;
    }

    /* Wait for CU to become non-active (bits 6-7 of status != 0x80) */
    timeout = 10000;
    statusWord = *statusReg;
    while ((statusWord & 0xC0) == 0x80 && timeout > 0) {
        IODelay(1);
        statusWord = *statusReg;
        timeout--;
    }

    if (timeout == 0) {
        IOLog("Intel82557: __polledCommand: CU active timeout\n");
        return 0;
    }

    /* Set general pointer to command address */
    *generalPtrReg = addr;

    /* Issue CU START command (0x10) */
    *commandReg = 0x10;

    /* Save CU state */
    *(unsigned int *)(((char *)self) + 0x1EC) = 0x80;

    /* Poll command block status until complete (bit 7 = 1) */
    cmdStatus = (unsigned short *)cmd;
    timeout = 10000;
    while ((*cmdStatus & 0x8000) == 0 && timeout > 0) {
        IODelay(1);
        timeout--;
    }

    if (timeout == 0) {
        /* Get command name for error message */
        commandWord = ((unsigned short *)cmd)[1];
        cmdOpcode = commandWord & 0x07;
        if (cmdOpcode < 5) {
            cmdName = commandNames[cmdOpcode];
        } else {
            cmdName = "unknown";
        }

        IOLog("Intel82557: __polledCommand: command '%s' timeout\n", cmdName);
        return 0;
    }

    /* Extract OK bit (bit 5 of status word) */
    result = (*cmdStatus & 0x2000) ? 1 : 0;

    return result;
}

/*
 * Private: Reset chip
 * Performs a complete chip reset via PORT command interface
 *
 * Driver instance structure:
 *   +0x1BC: SCB base address
 *
 * SCB Register Offsets:
 *   +0x08: PORT register (32-bit)
 *
 * Reset sequence:
 *   1. Software reset (PORT command 2)
 *   2. Wait for general pointer to clear (100ms timeout)
 *   3. Selective reset (PORT command 0)
 *   4. Wait 1ms for reset to complete
 */
- (void)__resetChip
{
    unsigned char *scbBase;
    volatile unsigned int *generalPtrReg;
    int timeout;
    int i;

    /* Send software reset command (PORT command 2, arg 0) */
    [self sendPortCommand:2 with:0];

    /* Wait for general pointer at SCB +0x04 to become 0 */
    /* Sleep 1ms in loop up to 100 times (100ms total timeout) */
    scbBase = *(unsigned char **)(((char *)self) + 0x1BC);
    generalPtrReg = (unsigned int *)(scbBase + 0x04);

    timeout = 100;
    for (i = 0; i < timeout; i++) {
        IOSleep(1);
        if (*generalPtrReg == 0) {
            break;
        }
    }

    if (i >= timeout) {
        IOLog("Intel82557: __resetChip: general pointer clear timeout\n");
    }

    /* Send selective reset command (PORT command 0, arg 0) */
    [self sendPortCommand:0 with:0];

    /* Wait 1ms for reset to complete */
    IOSleep(1);
}

/*
 * Private: Schedule reset
 * Defers adapter reset to a safe context by scheduling a function call
 *
 * Driver instance structure:
 *   +0x18C: TX queue (IONetbufQueue)
 *
 * Reset sequence:
 *   1. Log reset message
 *   2. Disable adapter interrupts (twice for safety)
 *   3. Reset chip hardware
 *   4. Clear any pending timeouts
 *   5. Dequeue and free all pending TX packets
 *   6. Schedule reset function via IOScheduleFunc
 *
 * The reset function address 0x8c0 corresponds to __resetFunc
 * which will call resetAndEnable:YES to complete the reset
 */
- (void)__scheduleReset
{
    void *txQueue;
    netbuf_t packet;

    IOLog("Intel82557: resetting adapter\n");

    /* Disable adapter interrupts (twice for safety) */
    [self disableAdapterInterrupts];
    [self disableAdapterInterrupts];

    /* Reset the chip */
    [self __resetChip];

    /* Clear any pending timeouts */
    [self clearTimeout];

    /* Dequeue and free all packets from TX queue */
    txQueue = (void *)(((char *)self) + 0x18C);

    while (1) {
        packet = (netbuf_t)_QDequeue(txQueue);
        if (packet == NULL) {
            break;
        }

        /* Free the packet */
        nb_free(packet);
    }

    /* Schedule reset function (address 0x8c0 = __resetFunc) */
    /* This will call resetAndEnable:YES in a safe context */
    IOScheduleFunc((IOThreadFunc)__resetFunc, self, 1);
}

/*
 * Private: Self-test
 * Executes the adapter's built-in self-test diagnostic
 *
 * Driver instance structure:
 *   +0x1C0: Self-test results buffer pointer (8 bytes)
 *   +0x1C4: Self-test results physical address
 *
 * Self-test results structure (pointed to by +0x1C0):
 *   +0x00: Signature word (0 = timeout, non-zero = completed)
 *   +0x04: Results word (0 = pass, non-zero = failure)
 *     Bit 3 (0x08): Invalid ROM contents
 *     Bit 2 (0x04): Internal register failure
 *     Bit 5 (0x20): Serial subsystem failure
 *   +0x05: General failure flag (bit 4 = 0x10)
 *
 * Returns: 1 on success, 0 on failure
 */
- (BOOL)__selfTest
{
    int *selfTestResults;
    unsigned int physAddr;
    const char *driverName;

    /* Get self-test results buffer pointer */
    selfTestResults = *(int **)(((char *)self) + 0x1C0);

    /* Initialize results buffer */
    selfTestResults[0] = 0;      /* Signature */
    selfTestResults[1] = -1;     /* Results */

    /* Get physical address of results buffer */
    physAddr = *(unsigned int *)(((char *)self) + 0x1C4);

    /* Send PORT command 1 (self-test) with physical address */
    [self sendPortCommand:1 with:physAddr];

    /* Wait 20ms for self-test to complete */
    IOSleep(20);

    /* Check if self-test completed (signature != 0) */
    if (selfTestResults[0] == 0) {
        driverName = [[self name] cString];
        IOLog("%s: Self test timed out\n", driverName);
        return NO;
    }

    /* Check if self-test passed (results == 0) */
    if (selfTestResults[1] == 0) {
        return YES;
    }

    /* Self-test failed - report specific errors */
    driverName = [[self name] cString];

    /* Check for ROM failure (bit 3) */
    if ((((unsigned char *)selfTestResults)[4] & 0x08) != 0) {
        IOLog("%s: Self test reports invalid ROM contents\n", driverName);
    }

    /* Check for register failure (bit 2) */
    if ((((unsigned char *)selfTestResults)[4] & 0x04) != 0) {
        IOLog("%s: Self test reports internal register failure\n", driverName);
    }

    /* Check for serial subsystem failure (bit 5) */
    if ((((unsigned char *)selfTestResults)[4] & 0x20) != 0) {
        IOLog("%s: Self test reports serial subsystem failure\n", driverName);
    }

    /* Check general failure flag at byte offset +5, bit 4 */
    if ((((unsigned char *)selfTestResults)[5] & 0x10) == 0) {
        return NO;
    }

    IOLog("%s: Self test failed\n", driverName);
    return NO;
}

/*
 * Private: Setup PHY
 * Configures PHY for appropriate speed and duplex mode
 *
 * Driver instance structure:
 *   +0x1A0: PHY address
 *   +0x1A1: Debug flag
 *   +0x228: Speed detection mode flag
 *   +0x229: Full duplex flag (0=half, 1=full)
 *   +0x22A: User forced settings flag
 *   +0x22C: Speed (0=10Mbps, 1=100Mbps)
 *   +0x230: 100Mbps capability flag
 *
 * PHY Register Map:
 *   0: Control register
 *   1: Status register (read twice to get current status)
 *   4: Auto-negotiation advertisement
 *   5: Auto-negotiation link partner ability
 *   6: Auto-negotiation expansion
 *
 * This function:
 *   1. Reads PHY capabilities
 *   2. Handles user-forced speed/duplex settings
 *   3. Performs auto-negotiation
 *   4. Sets appropriate speed and duplex mode
 *   5. Handles chip-specific quirks (NSC83840, Intel 82553)
 *
 * Returns: YES on success
 */
- (BOOL)__setupPhy
{
    unsigned short controlReg;
    unsigned short statusReg;  /* Status register (reg 1) - read as 16-bit */
    unsigned char statusReg1;  /* Low byte of status register */
    unsigned char statusReg2;  /* High byte of status register */
    unsigned short advReg, lpAbilityReg, expansionReg;
    unsigned short nscReg, intelReg;
    unsigned short negotiatedAbility;
    unsigned int modelId;
    unsigned char phyAddr;
    BOOL debugMode;
    BOOL userForced;
    BOOL speedDetectMode;
    BOOL fullDuplex;
    unsigned int speed;
    const char *driverName;
    BOOL canFullDuplex;
    BOOL can100Mbps;
    BOOL can10Mbps;

    phyAddr = *(unsigned char *)(((char *)self) + 0x1A0);
    debugMode = *(unsigned char *)(((char *)self) + 0x1A1);
    userForced = *(unsigned char *)(((char *)self) + 0x22A);
    speedDetectMode = *(unsigned char *)(((char *)self) + 0x228);
    fullDuplex = *(unsigned char *)(((char *)self) + 0x229);
    speed = *(unsigned int *)(((char *)self) + 0x22C);

    /* Read PHY control register (register 0) */
    [self __mdiReadPHY:phyAddr Register:0 Data:&controlReg];

    /* Read PHY status register (register 1) twice to get current status */
    [self __mdiReadPHY:phyAddr Register:1 Data:&statusReg];
    [self __mdiReadPHY:phyAddr Register:1 Data:&statusReg];

    /* Split status register into low and high bytes */
    statusReg1 = statusReg & 0xFF;        /* Low byte */
    statusReg2 = (statusReg >> 8) & 0xFF; /* High byte */

    /* Get PHY model ID */
    modelId = [self __getModelId];

    if (debugMode) {
        driverName = [[self name] cString];
        IOLog("%s: PHY model id is 0x%lx\n", driverName, modelId);
    }

    /* Mask off middle 16 bits for model comparison */
    modelId = modelId & 0xFFF0FFFF;

    /* If not user-forced mode, detect capabilities and configure */
    if (!userForced) {
        /* Determine if PHY supports full duplex */
        canFullDuplex = YES;
        if (speedDetectMode) {
            if (speed == 0) {
                /* 10Mbps - check bit 4 of status byte 2 */
                canFullDuplex = (statusReg2 & 0x10) ? YES : NO;
            } else {
                /* 100Mbps - check bit 6 of status byte 2 */
                canFullDuplex = (statusReg2 & 0x40) ? YES : NO;
            }
        }

        /* Check 100Mbps capability (bits 5-7 of status byte 2) */
        can100Mbps = ((speed != 1) || ((statusReg2 & 0xE0) != 0));

        /* Check 10Mbps capability (bits 3-4 of status byte 2) */
        can10Mbps = ((speed == 1) || ((statusReg2 & 0x18) != 0));

        /* Handle full duplex capability */
        if (!canFullDuplex) {
            if (debugMode) {
                driverName = [[self name] cString];
                IOLog("%s: adapter does not do full duplex at %s Mbit/s\n",
                      driverName, (speed == 0) ? "10" : "100");
            }
        } else if (can100Mbps && can10Mbps) {
            /* Both speeds supported, user forcing specific mode */
            /* Clear bits 12-13 (speed select) */
            controlReg &= 0xCFFF;

            /* Set speed bit (bit 13: 1=100Mbps, 0=10Mbps) */
            if (speed == 1) {
                controlReg |= 0x2000;
            }

            /* Clear bit 8 (duplex mode) then set if full duplex */
            controlReg &= 0xFEFF;
            if (fullDuplex) {
                controlReg |= 0x0100;
            }

            /* Write control register */
            [self __mdiWritePHY:phyAddr Register:0 Data:controlReg];

            if (debugMode) {
                driverName = [[self name] cString];
                IOLog("%s: user forced %s Mbit/s%s mode\n",
                      driverName,
                      (speed == 0) ? "10" : "100",
                      fullDuplex ? " full duplex" : "");
            }

            IOSleep(100);
            goto setupPhyComplete;
        }

        /* Check if adapter supports requested speed */
        if (!can100Mbps && debugMode) {
            driverName = [[self name] cString];
            IOLog("%s: adapter is not capable of 100 Mbits\n", driverName);
        }

        if (!can10Mbps && debugMode) {
            driverName = [[self name] cString];
            IOLog("%s: adapter is not capable of 10 Mbits\n", driverName);
        }

        /* Debug output of PHY capabilities */
        if (debugMode) {
            if (statusReg2 & 0x80) {
                IOLog("PHY: T4 capable\n");
            }
            if (statusReg2 & 0x40) {
                IOLog("PHY: 100Base-TX full duplex capable\n");
            }
            if (statusReg2 & 0x20) {
                IOLog("PHY: 100Base-TX half duplex capable\n");
            }
            if (statusReg2 & 0x10) {
                IOLog("PHY: 10Base-T full duplex capable\n");
            }
            if (statusReg2 & 0x08) {
                IOLog("PHY: 10Base-T half duplex capable\n");
            }
            if (statusReg1 & 0x01) {
                IOLog("PHY: has extended capability registers\n");
            }
            if (statusReg1 & 0x02) {
                IOLog("PHY: jabberDetect set\n");
            }
            if (statusReg1 & 0x08) {
                IOLog("PHY: auto negotiation capable\n");
            }
            IOLog("PHY: link is %s\n", (statusReg1 & 0x04) ? "UP" : "DOWN");
        }

        /* Log that adapter doesn't support requested configuration */
        driverName = [[self name] cString];
        IOLog("%s: adapter doesn't support%s%s%s, using detected values\n",
              driverName,
              (!can100Mbps) ? " 100 Mbit/s" : "",
              (!can10Mbps) ? " 10 Mbit/s" : "",
              (!canFullDuplex) ? " full duplex" : "");

        /* Mark as user-forced and use defaults */
        *(unsigned char *)(((char *)self) + 0x22A) = 1;
        *(unsigned char *)(((char *)self) + 0x229) = 0;  /* Half duplex */
        *(unsigned char *)(((char *)self) + 0x228) = 0;
    }

setupPhyComplete:
    /* Handle NSC83840 chip-specific setup */
    if (modelId == 0x5C002000) {
        if (debugMode) {
            driverName = [[self name] cString];
            IOLog("%s: setting NSC83840-specific registers\n", driverName);
        }

        /* Read register 0x17 and set bits 10 and 5 (0x420) */
        [self __mdiReadPHY:phyAddr Register:0x17 Data:&nscReg];
        nscReg |= 0x420;
        [self __mdiWritePHY:phyAddr Register:0x17 Data:nscReg];
    }

    /* Auto-detect speed and duplex if user forced mode */
    if (userForced) {
        /* Read status register twice */
        [self __mdiReadPHY:phyAddr Register:1 Data:&statusReg];
        [self __mdiReadPHY:phyAddr Register:1 Data:&statusReg];
        statusReg1 = statusReg & 0xFF;

        /* Check if link is up (bit 2) */
        if ((statusReg1 & 0x04) == 0) {
            if (debugMode) {
                driverName = [[self name] cString];
                IOLog("%s: data rate was not auto-detected\n", driverName);
            }
            *(unsigned int *)(((char *)self) + 0x22C) = 0;   /* Default to 10Mbps */
            *(unsigned char *)(((char *)self) + 0x229) = 0;  /* Half duplex */
        }
        /* Intel 82553 or similar - use chip-specific register */
        else if ((modelId == 0x3E0) || (modelId == 0x35002A8)) {
            if (debugMode) {
                driverName = [[self name] cString];
                IOLog("%s: using Intel82553 register to determine speed\n", driverName);
            }

            /* Read register 0x10 */
            [self __mdiReadPHY:phyAddr Register:0x10 Data:&intelReg];

            /* Bit 1 = speed (1=100Mbps, 0=10Mbps) */
            speed = (intelReg >> 1) & 1;
            *(unsigned int *)(((char *)self) + 0x22C) = speed;

            if (speed == 1) {
                *(unsigned char *)(((char *)self) + 0x230) = 1;
            }

            /* Bit 0 = duplex (1=full, 0=half) */
            *(unsigned char *)(((char *)self) + 0x229) = intelReg & 1;
        }
        /* Other PHYs - use auto-negotiation registers */
        else {
            /* Read status register */
            [self __mdiReadPHY:phyAddr Register:1 Data:&statusReg];
            statusReg1 = statusReg & 0xFF;

            /* Read auto-negotiation expansion register (register 6) */
            [self __mdiReadPHY:phyAddr Register:6 Data:&expansionReg];

            /* Check if auto-negotiation completed (status bit 5) and
               link partner has ability (expansion bit 0) */
            if (((statusReg1 & 0x20) == 0) || ((expansionReg & 1) == 0)) {
                /* No auto-negotiation, default to 10Mbps */
                *(unsigned int *)(((char *)self) + 0x22C) = 0;

                /* Special case for NSC83840 - check register 0x19 */
                if (modelId == 0x5C002000) {
                    [self __mdiReadPHY:phyAddr Register:0x19 Data:&nscReg];
                    /* Bit 6 inverted: 0=100Mbps, 1=10Mbps */
                    *(unsigned int *)(((char *)self) + 0x22C) = (~(nscReg >> 6)) & 1;
                }
            } else {
                /* Auto-negotiation successful */
                /* Read link partner ability (register 5) */
                [self __mdiReadPHY:phyAddr Register:5 Data:&lpAbilityReg];

                /* Read our advertisement (register 4) */
                [self __mdiReadPHY:phyAddr Register:4 Data:&advReg];

                /* AND them together to get negotiated abilities */
                negotiatedAbility = lpAbilityReg & advReg;

                /* Defaults */
                *(unsigned char *)(((char *)self) + 0x230) = 0;
                *(unsigned int *)(((char *)self) + 0x22C) = 1;      /* 100Mbps */
                *(unsigned char *)(((char *)self) + 0x229) = 0;     /* Half duplex */

                /* Priority order: 100-FD, 100-HD, 10-FD, 10-HD */
                if (negotiatedAbility & 0x100) {
                    /* 100Base-TX full duplex (bit 8) */
                    *(unsigned char *)(((char *)self) + 0x229) = 1;
                } else if (negotiatedAbility & 0x200) {
                    /* 100Base-T4 (bit 9) */
                    *(unsigned char *)(((char *)self) + 0x230) = 1;
                } else if (negotiatedAbility & 0x80) {
                    /* 100Base-TX half duplex (bit 7) */
                    /* Already set to 100Mbps half duplex */
                } else if (negotiatedAbility & 0x40) {
                    /* 10Base-T full duplex (bit 6) */
                    *(unsigned char *)(((char *)self) + 0x229) = 1;
                    *(unsigned int *)(((char *)self) + 0x22C) = 0;
                } else {
                    /* 10Base-T half duplex */
                    *(unsigned int *)(((char *)self) + 0x22C) = 0;
                }

                if (debugMode) {
                    driverName = [[self name] cString];
                    IOLog("%s: got dataRate from auto-negotiate register (NWAY)\n", driverName);
                }
            }
        }
    }

    return YES;
}

@end

/*
 * Utility function implementations
 */

/*
 * Reset function callback
 * Called to reset the driver instance
 */
static void __resetFunc(id driverInstance)
{
    BOOL result;
    const char *driverName;

    result = (BOOL)[driverInstance resetAndEnable:YES];
    if (!result) {
        driverName = [[driverInstance name] cString];
        IOLog("%s: Reset attempt unsuccessful\n", driverName);
    }
}

/*
 * Get network buffer from pool
 *
 * Buffer pool structure:
 *   +0x08: Head pointer (free list)
 *   +0x0C: Free count
 *   +0x14: Buffer size
 *   +0x24: Lock object
 *
 * Buffer entry structure:
 *   +0x00: Pointer to pool
 *   +0x04: Magic value 1 (0xCAFE2BAD)
 *   +0x08: User data (netbuf_t)
 *   +0x0C: Next pointer
 *   +0x10: Pointer to magic value 2
 *   +0x14: Buffer data start
 */
static netbuf_t _getNetBuffer(void *bufferPool)
{
    int bufferEntry;
    id lockObj;
    netbuf_t nb;
    int nbResult;

    if (bufferPool == NULL) {
        return NULL;
    }

    bufferEntry = *(int *)((char *)bufferPool + 0x08);
    lockObj = *(id *)((char *)bufferPool + 0x24);

    /* Lock the buffer pool */
    [lockObj lock];

    if (bufferEntry == 0) {
        /* No free buffers */
        [lockObj unlock];
        return NULL;
    }

    /* Remove buffer from free list */
    *(int *)((char *)bufferPool + 0x08) = *(int *)(bufferEntry + 0x0C);

    /* Decrement free count */
    *(int *)((char *)bufferPool + 0x0C) = *(int *)((char *)bufferPool + 0x0C) - 1;

    /* Unlock the buffer pool */
    [lockObj unlock];

    /* Check buffer integrity - magic value 1 at offset +4 */
    if (*(int *)(bufferEntry + 0x04) != 0xCAFE2BAD) {
        IOPanic("getNetBuffer: buffer underrun");
    }

    /* Check buffer integrity - magic value 2 at end */
    if (**(int **)(bufferEntry + 0x10) != 0xCAFE2BAD) {
        IOPanic("getNetBuffer: buffer overrun");
    }

    /* Allocate netbuf wrapper around buffer */
    nbResult = nb_alloc_wrapper((void *)(bufferEntry + 0x14),
                                *(unsigned int *)((char *)bufferPool + 0x14),
                                _recycleNetbuf,
                                (void *)bufferEntry);

    /* Store netbuf_t in buffer entry */
    *(int *)(bufferEntry + 0x08) = nbResult;

    if (nbResult == 0) {
        /* Allocation failed - return buffer to pool */
        [lockObj lock];
        *(int *)(bufferEntry + 0x0C) = *(int *)((char *)bufferPool + 0x08);
        *(int *)((char *)bufferPool + 0x08) = bufferEntry;
        *(int *)((char *)bufferPool + 0x0C) = *(int *)((char *)bufferPool + 0x0C) + 1;
        [lockObj unlock];
        return NULL;
    }

    /* Return the netbuf */
    nb = (netbuf_t)*(int *)(bufferEntry + 0x08);
    return nb;
}

/*
 * Check if memory region is physically contiguous
 * Returns the end address up to which memory is contiguous, or 0 if not contiguous
 */
static unsigned int _IOIsPhysicallyContiguous(unsigned int vaddr, int size)
{
    int vmTask;
    int result;
    unsigned int endAddr;
    unsigned int nextPageAddr;
    int physPage1, physPage2;

    /* Calculate end address */
    endAddr = (vaddr + size) - 1;

    /* Start at first page boundary after vaddr */
    nextPageAddr = (vaddr & ~_page_mask) + _page_size;

    /* Walk through pages checking physical continuity */
    while (endAddr >= nextPageAddr) {
        /* Get VM task for current page */
        vmTask = IOVmTaskSelf(nextPageAddr, &physPage1);
        result = IOPhysicalFromVirtual(vmTask);
        if (result != 0) {
            return 0;
        }

        /* Get VM task for previous byte */
        vmTask = IOVmTaskSelf(nextPageAddr - 1, &physPage2);
        result = IOPhysicalFromVirtual(vmTask);
        if (result != 0) {
            return 0;
        }

        /* Check if physical pages are consecutive */
        if (physPage1 != physPage2 + 1) {
            /* Not contiguous - return address just before break */
            return nextPageAddr - 1;
        }

        /* Move to next page */
        nextPageAddr += _page_size;
    }

    /* All pages are contiguous */
    return endAddr;
}

/*
 * Allocate non-cached memory
 * Allocates memory aligned to page boundaries for DMA operations
 *
 * Returns: Page-aligned virtual address, or 0 if allocation fails
 * allocPtr: Set to actual allocated address
 * allocSize: Set to actual allocated size
 */
static unsigned int _IOMallocNonCached(int requestedSize, int *allocPtr, int *allocSize)
{
    int alignedSize;
    int allocated;
    unsigned int alignedAddr;

    /* Calculate size aligned to page boundary plus one extra page */
    alignedSize = ((requestedSize + _page_mask) & ~_page_mask) + _page_size;
    *allocSize = alignedSize;

    /* Allocate memory */
    allocated = (int)IOMalloc(alignedSize);
    *allocPtr = allocated;

    if (allocated == 0) {
        return 0;
    }

    /* Return page-aligned address within allocated region */
    alignedAddr = (allocated + _page_mask) & ~_page_mask;
    return alignedAddr;
}

/*
 * Allocate page-aligned memory
 * Allocates double the requested size to ensure page alignment
 *
 * Returns: Page-aligned virtual address, or 0 if allocation fails
 * allocPtr: Set to actual allocated address
 * allocSize: Set to actual allocated size (2 * requestedSize)
 */
static unsigned int _IOMallocPage(int requestedSize, int *allocPtr, int *allocSize)
{
    int allocated;
    unsigned int alignedAddr;

    /* Allocate double the requested size */
    *allocSize = requestedSize * 2;
    allocated = (int)IOMalloc(requestedSize * 2);

    if (allocated == 0) {
        return 0;
    }

    *allocPtr = allocated;

    /* Return page-aligned address within allocated region */
    alignedAddr = (allocated + _page_mask) & ~_page_mask;
    return alignedAddr;
}

/*
 * Interrupt handler function
 *
 * Driver instance structure offsets used:
 *   +0x195: Schedule flag
 *   +0x196: Driver enabled flag
 *   +0x1BC: SCB status register pointer
 *   +0x200: Current RFD pointer
 *   +0x204: Previous RFD pointer
 *   +0x208: Receive queue head
 *   +0x20C: Receive queue tail
 *   +0x210: Receive queue count
 *   +0x214: Receive queue max size
 *   +0x218: Free netbuf queue head
 *   +0x21C: Free netbuf queue tail
 *   +0x220: Free netbuf queue count
 */
static void _intHandler(void *param1, void *param2, int driverInstance)
{
    unsigned char *statusRegPtr;
    unsigned short *currentRfd;
    unsigned short *prevRfd;
    netbuf_t *freeNetbufPtr;
    netbuf_t nb;
    netbuf_t packetNb;
    unsigned char statusByte;
    unsigned short frameSize;
    BOOL needInterrupt;
    BOOL receiveProcessed;
    int loopCount;
    int nbSize;
    int *countPtr;

    /* Check if driver is enabled */
    if (*(char *)(driverInstance + 0x196) != 1) {
        IOEnableInterrupt(param1);
        return;
    }

    needInterrupt = NO;

    /* Get status register pointer */
    statusRegPtr = *(unsigned char **)(driverInstance + 0x1BC);

    /* Read and acknowledge status byte (high byte of status register) */
    statusByte = statusRegPtr[1];
    if (statusByte != 0) {
        statusRegPtr[1] = statusByte;
    }

    /* Process interrupts (max 10 iterations to prevent lockup) */
    for (loopCount = 0; statusByte != 0 && loopCount < 10; loopCount++) {

        /* Handle receive interrupts (FR=0x40, RNR=0x10) */
        if ((statusByte & 0x50) != 0) {
            receiveProcessed = NO;

            /* Process all completed receive frames */
            currentRfd = *(unsigned short **)(driverInstance + 0x200);
            while (((unsigned char *)currentRfd)[1] & 0x80) { /* Check Complete bit */

                /* Check if this is a multi-RBD frame (not supported) */
                if (((unsigned char *)currentRfd)[0x29] >= 0) {
                    IOLog("Intel82557: more than 1 rbd, frame size %d\n",
                          currentRfd[0x14] & 0x3FFF);
                    receiveProcessed = NO;
                    goto done_receive;
                }

                /* Check if frame is OK and size is valid */
                if ((((unsigned char *)currentRfd)[1] & 0x20) && /* OK bit */
                    ((frameSize = currentRfd[0x14] & 0x3FFF) > 0x3B)) { /* Size > 59 bytes */

                    /* Get a free netbuf from the free queue */
                    if (*(int *)(driverInstance + 0x220) == 0) {
                        freeNetbufPtr = NULL;
                    } else {
                        freeNetbufPtr = *(netbuf_t **)(driverInstance + 0x218);
                        *(void **)(driverInstance + 0x218) = *freeNetbufPtr;
                        countPtr = (int *)(driverInstance + 0x220);
                        (*countPtr)--;
                        if (*countPtr == 0) {
                            *(int *)(driverInstance + 0x21C) = 0;
                            *(int *)(driverInstance + 0x218) = 0;
                        }
                        *freeNetbufPtr = NULL;
                    }

                    if (freeNetbufPtr != NULL) {
                        /* Get the netbuf from the RFD */
                        packetNb = *(netbuf_t *)&currentRfd[0x22];

                        /* Trim netbuf to actual packet size */
                        nbSize = nb_size(packetNb);
                        nb_shrink_bot(packetNb, nbSize - frameSize);

                        /* Try to enqueue packet to receive queue */
                        if (*(unsigned int *)(driverInstance + 0x210) <
                            *(unsigned int *)(driverInstance + 0x214)) {

                            countPtr = (int *)(driverInstance + 0x210);
                            if ((*countPtr)++ == 0) {
                                /* First packet in queue */
                                *(netbuf_t **)(driverInstance + 0x20C) = packetNb;
                                *(netbuf_t **)(driverInstance + 0x208) = packetNb;
                            } else {
                                /* Add to tail of queue */
                                **(netbuf_t ***)(driverInstance + 0x20C) = packetNb;
                                *(netbuf_t **)(driverInstance + 0x20C) = packetNb;
                            }
                            *packetNb = NULL;
                            receiveProcessed = YES;
                        } else {
                            receiveProcessed = NO;
                        }

                        if (receiveProcessed) {
                            /* Install the replacement netbuf in RFD */
                            *(netbuf_t **)&currentRfd[0x22] = (netbuf_t)freeNetbufPtr;
                            freeNetbufPtr = (netbuf_t *)nb_map((netbuf_t)freeNetbufPtr);
                            *(void **)&currentRfd[0x18] = *freeNetbufPtr;
                        } else {
                            IOLog("Intel82557: can't enqueue packet %d\n",
                                  *(int *)(driverInstance + 0x210));
                        }
                    }
                }

                /* Reset RFD for reuse */
                currentRfd[0] = 0;
                currentRfd[1] = 0;
                ((unsigned char *)currentRfd)[2] |= 0x08;  /* Set SF bit */
                ((unsigned char *)currentRfd)[3] |= 0x80;  /* Set EL bit */
                *(unsigned int *)&currentRfd[4] = 0xFFFFFFFF;
                currentRfd[6] = 0;
                currentRfd[7] = 0;
                currentRfd[0x14] = 0;
                currentRfd[0x1A] = 0x5EE;  /* Size */
                currentRfd[0x1B] = 1;

                /* Clear EL bit in previous RFD */
                prevRfd = *(unsigned short **)(driverInstance + 0x204);
                prevRfd[0x1B] = 0;
                ((unsigned char *)prevRfd)[3] &= 0x7F;

                /* Move to next RFD */
                *(unsigned short **)(driverInstance + 0x204) = currentRfd;
                *(void **)(driverInstance + 0x200) =
                    *(void **)(*(int *)(driverInstance + 0x200) + 0x20);
                currentRfd = *(unsigned short **)(driverInstance + 0x200);
            }

            receiveProcessed = YES;

done_receive:
            /* If no packets processed or RU not ready, schedule reset */
            if (!receiveProcessed || (statusByte & 0x10)) {
                *(unsigned char *)(driverInstance + 0x195) = 1;
            }

            needInterrupt = YES;
        }

        /* Handle transmit/command interrupts (CX=0x80, CNA=0x20) */
        if ((statusByte & 0xA0) != 0) {
            needInterrupt = YES;
        }

        /* Read status again for next iteration */
        statusByte = statusRegPtr[1];
        if (statusByte != 0) {
            statusRegPtr[1] = statusByte;
        }
    }

    /* Send interrupt notification if needed */
    if (needInterrupt || *(char *)(driverInstance + 0x195) == 1) {
        IOSendInterrupt(param1, param2, 0x232325);
    }

    /* Re-enable hardware interrupts */
    IOEnableInterrupt(param1);
}

/*
 * Dequeue operation
 * Removes and returns the first element from a queue
 *
 * Queue structure:
 *   +0x00: Head pointer (first element)
 *   +0x04: Tail pointer (last element)
 *   +0x08: Count (number of elements)
 *
 * Element structure:
 *   +0x00: Next pointer
 *
 * Returns: Pointer to dequeued element, or NULL if queue is empty
 */
static void *_QDequeue(void *queue)
{
    int *countPtr;
    void **headPtr;
    void *element;

    if (queue == NULL) {
        return NULL;
    }

    headPtr = (void **)queue;
    countPtr = (int *)((char *)queue + 0x08);

    /* Check if queue is empty */
    if (*countPtr == 0) {
        return NULL;
    }

    /* Remove first element */
    element = *headPtr;
    *headPtr = *(void **)element;  /* head = element->next */

    /* Decrement count */
    (*countPtr)--;

    /* If queue is now empty, clear tail pointer too */
    if (*countPtr == 0) {
        *(void **)((char *)queue + 0x04) = NULL;  /* tail = NULL */
        *headPtr = NULL;                           /* head = NULL */
    }

    /* Clear next pointer in dequeued element */
    *(void **)element = NULL;

    return element;
}

/*
 * Recycle network buffer
 * Returns a netbuf to the buffer pool when it's no longer in use
 *
 * Buffer pool structure:
 *   +0x00: Pool header
 *   +0x05: Shutdown flag
 *   +0x08: Head pointer (free list)
 *   +0x0C: Free count
 *   +0x18: Total count
 *   +0x24: Lock object
 *
 * Buffer entry structure:
 *   +0x00: Pointer to pool
 *   +0x04: Magic value 1 (0xCAFE2BAD)
 *   +0x08: User data (netbuf_t)
 *   +0x0C: Next pointer
 *   +0x10: Pointer to magic value 2
 */
static void _recycleNetbuf(netbuf_t nb, void *arg1, int *bufferEntry)
{
    int poolAddr;
    id lockObj;

    /* Get pool address from buffer entry */
    poolAddr = *bufferEntry;

    /* Verify buffer integrity - check magic value 1 */
    if (bufferEntry[1] != (int)0xCAFE2BAD) {
        IOPanic("recycleNetbuf: buffer underrun");
    }

    /* Verify buffer integrity - check magic value 2 at end */
    if (*(int *)bufferEntry[4] != (int)0xCAFE2BAD) {
        IOPanic("recycleNetbuf: buffer overrun");
    }

    /* Check if pool is shutting down */
    if (*(char *)(poolAddr + 0x05) == 0) {
        /* Normal operation - return buffer to free list */
        lockObj = *(id *)(poolAddr + 0x24);
        [lockObj lock];

        /* Add buffer to head of free list */
        bufferEntry[3] = *(int *)(poolAddr + 0x08);
        *(int **)(poolAddr + 0x08) = bufferEntry;

        /* Increment free count */
        *(int *)(poolAddr + 0x0C) = *(int *)(poolAddr + 0x0C) + 1;

        [lockObj unlock];
    } else {
        /* Pool is shutting down */
        lockObj = *(id *)(poolAddr + 0x24);
        [lockObj lock];

        /* Increment free count */
        *(int *)(poolAddr + 0x0C) = *(int *)(poolAddr + 0x0C) + 1;

        [lockObj unlock];

        /* If all buffers are now free, free the pool */
        if (*(int *)(poolAddr + 0x18) == *(int *)(poolAddr + 0x0C)) {
            [(id)poolAddr free];
        }
    }
}
