/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * BusLogic FlashPoint SCSI Driver
 */

#import "BusLogicFPSCSI.h"
#import "FlashPoint.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <mach/mach_interface.h>
#import <kernserv/queue.h>
#import <kern/lock.h>

#define PCI_VENDOR_BUSLOGIC     0x104B
#define PCI_DEVICE_FLASHPOINT   0x8130

/* Thread messages */
#define MSG_COMMAND         1
#define MSG_INTERRUPT       2
#define MSG_SHUTDOWN        3

@implementation BusLogicFPSCSI

/*
 * Probe for BusLogic FlashPoint adapter
 */
+ (BOOL)probe:(IOPCIDevice *)deviceDescription
{
    unsigned int vendor, device;

    if ([deviceDescription getPCIConfigData:&vendor
                                   atRegister:PCI_VENDOR_ID
                                   withSize:sizeof(vendor)] != IO_R_SUCCESS)
        return NO;

    if ([deviceDescription getPCIConfigData:&device
                                   atRegister:PCI_DEVICE_ID
                                   withSize:sizeof(device)] != IO_R_SUCCESS)
        return NO;

    if (vendor == PCI_VENDOR_BUSLOGIC && device == PCI_DEVICE_FLASHPOINT) {
        IOLog("BusLogicFPSCSI: Found FlashPoint adapter\n");
        return YES;
    }

    return NO;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IOPCIDevice *)deviceDescription
{
    struct sccb_mgr_info cardInfo;
    unsigned int baseAddr;
    unsigned int irqLevel;

    [super initFromDeviceDescription:deviceDescription];

    _pciDevice = deviceDescription;
    _initialized = NO;
    _threadRunning = NO;
    _controllerThread = nil;

    /* Initialize queue */
    queue_init(&_pendingQueue);
    simple_lock_init(&_queueLock);

    /* Get base I/O address */
    if ([_pciDevice getPCIConfigData:&baseAddr
                           atRegister:PCI_BASE_ADDRESS_0
                           withSize:sizeof(baseAddr)] != IO_R_SUCCESS) {
        IOLog("BusLogicFPSCSI: Failed to get base address\n");
        [self free];
        return nil;
    }

    _baseAddress = baseAddr & ~0x3;  /* Mask off type bits */

    /* Get IRQ level */
    if ([_pciDevice getPCIConfigData:&irqLevel
                           atRegister:PCI_INTERRUPT_LINE
                           withSize:sizeof(unsigned char)] != IO_R_SUCCESS) {
        IOLog("BusLogicFPSCSI: Failed to get IRQ\n");
        [self free];
        return nil;
    }

    _irq = irqLevel;

    /* Set up card info structure for FlashPoint probe */
    bzero(&cardInfo, sizeof(cardInfo));
    cardInfo.si_baseaddr = _baseAddress;
    cardInfo.si_id = 7;  /* Default SCSI ID */
    cardInfo.si_intvect = _irq;
    cardInfo.si_bustype = BUSTYPE_PCI;

    /* Probe the adapter */
    _cardHandle = FlashPoint_ProbeHostAdapter(&cardInfo);
    if (_cardHandle == NULL) {
        IOLog("BusLogicFPSCSI: FlashPoint probe failed\n");
        [self free];
        return nil;
    }

    /* Save adapter parameters */
    _scsiId = cardInfo.si_id;
    _maxTargets = 16;  /* FlashPoint supports 16 targets */
    _maxLun = 32;      /* and 32 LUNs */

    /* Request I/O port range */
    if ([self reservePortRange:_baseAddress size:256] != IO_R_SUCCESS) {
        IOLog("BusLogicFPSCSI: Failed to reserve I/O ports\n");
        [self free];
        return nil;
    }

    /* Enable interrupts */
    if ([self enableInterrupt:_irq] != IO_R_SUCCESS) {
        IOLog("BusLogicFPSCSI: Failed to enable interrupt\n");
        [self free];
        return nil;
    }

    /* Reset and initialize hardware */
    if (![self initializeHardware]) {
        IOLog("BusLogicFPSCSI: Hardware initialization failed\n");
        [self free];
        return nil;
    }

    /* Start controller thread */
    if (![self startControllerThread]) {
        IOLog("BusLogicFPSCSI: Failed to start controller thread\n");
        [self free];
        return nil;
    }

    _initialized = YES;

    IOLog("BusLogicFPSCSI: Initialized at 0x%x IRQ %d\n", _baseAddress, _irq);

    return self;
}

/*
 * Reset the controller
 */
- (BOOL)reset
{
    return [self resetHardware];
}

/*
 * Free resources
 */
- (void)free
{
    /* Stop controller thread */
    if (_threadRunning) {
        [self stopControllerThread];
    }

    if (_cardHandle) {
        FlashPoint_ReleaseHostAdapter(_cardHandle);
        _cardHandle = NULL;
    }

    if (_baseAddress) {
        [self releasePortRange:_baseAddress size:256];
    }

    if (_irq) {
        [self disableInterrupt:_irq];
    }

    [super free];
}

/*
 * Execute a SCSI request
 */
- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiRequest
                       buffer:(void *)buffer
                       client:(vm_task_t)client
{
    struct sccb *sccb;
    unsigned char target, lun;

    if (!_initialized)
        return SR_IOST_INVALID;

    target = [scsiRequest target];
    lun = [scsiRequest lun];

    if (target >= _maxTargets || lun >= _maxLun)
        return SR_IOST_BADST;

    /* Allocate SCCB */
    sccb = (struct sccb *)IOMalloc(sizeof(struct sccb));
    if (!sccb)
        return SR_IOST_MEMALL;

    /* Build SCCB from request */
    [self createSCCB:sccb forRequest:scsiRequest buffer:buffer client:client];

    /* Queue the command for execution by the controller thread */
    [self queueCommand:sccb];

    return SR_IOST_GOOD;
}

/*
 * Create SCCB from SCSI request
 */
- (void)createSCCB:(void *)sccbPtr
        forRequest:(IOSCSIRequest *)request
            buffer:(void *)buffer
            client:(vm_task_t)client
{
    struct sccb *sccb = (struct sccb *)sccbPtr;
    unsigned char *cdb;
    unsigned int cdbLen;
    unsigned int dataLen;

    bzero(sccb, sizeof(struct sccb));

    /* Get CDB */
    cdb = [request cdb:&cdbLen];
    if (cdbLen > 12)
        cdbLen = 12;

    bcopy(cdb, sccb->Cdb, cdbLen);
    sccb->CdbLength = cdbLen;

    /* Target and LUN */
    sccb->TargID = [request target];
    sccb->Lun = [request lun];

    /* Data transfer */
    dataLen = [request maxTransfer];
    sccb->DataLength = dataLen;
    sccb->DataPointer = buffer;

    /* Direction */
    if ([request isRead])
        sccb->OperationCode = 0x00;  /* SCSI Initiator Command */
    else
        sccb->OperationCode = 0x00;  /* SCSI Initiator Command */

    /* Timeout */
    sccb->ControlByte = 0x00;

    /* Request sense */
    sccb->RequestSenseLength = [request senseBufSize];
    sccb->SensePointer = (u32)[request senseBuffer];

    /* I/O port */
    sccb->SccbIOPort = _baseAddress;

    /* Callback - we'll use context to store the request */
    sccb->Reserved2 = (u32)request;

    /* Set callback function pointer */
    sccb->SccbCallback = (CALL_BK_FN)[self methodFor:@selector(scsiCallback:)];
}

/*
 * Reset hardware
 */
- (BOOL)resetHardware
{
    unsigned long result;

    if (!_cardHandle)
        return NO;

    result = FlashPoint_HardwareResetHostAdapter(_cardHandle);

    return (result == 0);
}

/*
 * Initialize hardware
 */
- (BOOL)initializeHardware
{
    return [self resetHardware];
}

/*
 * Handle interrupt
 */
- (void)interruptOccurred
{
    if (!_cardHandle)
        return;

    while (FlashPoint_InterruptPending(_cardHandle)) {
        FlashPoint_HandleInterrupt(_cardHandle);
    }
}

/*
 * Handle timeout
 */
- (void)timeoutOccurred
{
    IOLog("BusLogicFPSCSI: Timeout occurred\n");
}

/*
 * Reset SCSI bus
 */
- (BOOL)resetSCSIBus
{
    return [self resetHardware];
}

/*
 * SCSI command completion callback
 */
- (void)scsiComplete:(void *)sccbPtr
{
    struct sccb *sccb = (struct sccb *)sccbPtr;
    IOSCSIRequest *request;

    if (!sccb)
        return;

    /* Retrieve the request from the SCCB */
    request = (IOSCSIRequest *)sccb->Reserved2;
    if (!request) {
        IOFree(sccb, sizeof(struct sccb));
        return;
    }

    /* Update request status based on SCCB status */
    switch (sccb->HostStatus) {
        case SCCB_COMPLETE:
            [request setStatus:SR_IOST_GOOD];
            break;
        case SCCB_SELECTION_TIMEOUT:
            [request setStatus:SR_IOST_SELTO];
            break;
        case SCCB_DATA_OVER_RUN:
        case SCCB_DATA_UNDER_RUN:
            [request setStatus:SR_IOST_IOTO];
            break;
        default:
            [request setStatus:SR_IOST_HW];
            break;
    }

    /* Set bytes transferred */
    [request setBytesTransferred:sccb->Sccb_XferCnt];

    /* Complete the request */
    [request commandComplete];

    /* Free SCCB */
    IOFree(sccb, sizeof(struct sccb));
}

/*
 * SCSI callback from FlashPoint manager
 */
- (void)scsiCallback:(void *)sccbPtr
{
    [self scsiComplete:sccbPtr];
}

/*
 * Thread completion
 */
- threadComplete:(void *)sccbPtr reason:(int)reason
{
    struct sccb *sccb = (struct sccb *)sccbPtr;

    if (reason != 0) {
        /* Error occurred */
        if (sccb) {
            sccb->HostStatus = SCCB_ERROR;
        }
    }

    [self scsiComplete:sccbPtr];
    return self;
}

/*
 * Command completion
 */
- cmdComplete:(void *)sccbPtr
{
    [self scsiComplete:sccbPtr];
    return self;
}

/*
 * Delete/cleanup
 */
- delete
{
    return [self free];
}

/*
 * Cancel command
 */
- cmdCancel:(void *)sccbPtr
{
    struct sccb *sccb = (struct sccb *)sccbPtr;

    if (!_cardHandle || !sccb)
        return self;

    /* Abort the command */
    FlashPoint_AbortCCB(_cardHandle, sccb);

    return self;
}

/*
 * Create SCCB structures
 */
- createSCCBs
{
    /* This would allocate a pool of SCCBs if needed */
    /* For now, we allocate them on demand in executeRequest */
    return self;
}

/*
 * Reset hardware with extended parameters
 * This appears to be an internal method with mangled name
 */
- resetHardware_xxx_8_xxx_11_xxx_14_xxx_8_xxx_11_xxx_14_first_time_2
{
    [self resetHardware];
    return self;
}

/*
 * Controller thread - handles command execution and interrupts
 */
- (void)controllerThread:(void *)arg
{
    msg_header_t msg;
    kern_return_t kr;

    IOLog("BusLogicFPSCSI: Controller thread started\n");

    while (_threadRunning) {
        /* Wait for message */
        msg.msg_size = sizeof(msg);
        msg.msg_local_port = _commandPort;

        kr = msg_receive(&msg, MSG_OPTION_NONE, 0);
        if (kr != KERN_SUCCESS) {
            if (_threadRunning) {
                IOLog("BusLogicFPSCSI: msg_receive failed: %d\n", kr);
            }
            break;
        }

        /* Process message */
        switch (msg.msg_id) {
            case MSG_COMMAND: {
                /* Process pending commands */
                struct sccb *sccb;
                while ((sccb = [self dequeueCommand]) != NULL) {
                    FlashPoint_StartCCB(_cardHandle, sccb);
                }
                break;
            }

            case MSG_INTERRUPT:
                /* Handle interrupt */
                [self interruptOccurred];
                break;

            case MSG_SHUTDOWN:
                /* Thread shutdown requested */
                _threadRunning = NO;
                break;

            default:
                IOLog("BusLogicFPSCSI: Unknown message %d\n", msg.msg_id);
                break;
        }
    }

    IOLog("BusLogicFPSCSI: Controller thread exiting\n");
    thread_terminate(thread_self());
}

/*
 * Start controller thread
 */
- (BOOL)startControllerThread
{
    kern_return_t kr;

    /* Allocate command port */
    kr = port_allocate(task_self(), &_commandPort);
    if (kr != KERN_SUCCESS) {
        IOLog("BusLogicFPSCSI: Failed to allocate command port\n");
        return NO;
    }

    /* Start thread */
    _threadRunning = YES;
    kr = IOForkThread((IOThreadFunc)[self methodFor:@selector(controllerThread:)], self);
    if (kr != IO_R_SUCCESS) {
        IOLog("BusLogicFPSCSI: Failed to fork controller thread\n");
        port_deallocate(task_self(), _commandPort);
        _threadRunning = NO;
        return NO;
    }

    return YES;
}

/*
 * Stop controller thread
 */
- (void)stopControllerThread
{
    msg_header_t msg;
    kern_return_t kr;

    if (!_threadRunning)
        return;

    /* Send shutdown message */
    msg.msg_simple = TRUE;
    msg.msg_size = sizeof(msg);
    msg.msg_type = MSG_TYPE_NORMAL;
    msg.msg_local_port = PORT_NULL;
    msg.msg_remote_port = _commandPort;
    msg.msg_id = MSG_SHUTDOWN;

    kr = msg_send(&msg, MSG_OPTION_NONE, 0);
    if (kr != KERN_SUCCESS) {
        IOLog("BusLogicFPSCSI: Failed to send shutdown message\n");
    }

    /* Wait a bit for thread to exit */
    IOSleep(100);

    /* Deallocate port */
    port_deallocate(task_self(), _commandPort);
    _commandPort = PORT_NULL;
}

/*
 * Queue a command for execution
 */
- (void)queueCommand:(void *)sccbPtr
{
    struct sccb *sccb = (struct sccb *)sccbPtr;
    msg_header_t msg;
    kern_return_t kr;

    /* Add to queue */
    simple_lock(&_queueLock);
    queue_enter(&_pendingQueue, sccb, struct sccb *, Sccb_forwardlink);
    simple_unlock(&_queueLock);

    /* Notify thread */
    msg.msg_simple = TRUE;
    msg.msg_size = sizeof(msg);
    msg.msg_type = MSG_TYPE_NORMAL;
    msg.msg_local_port = PORT_NULL;
    msg.msg_remote_port = _commandPort;
    msg.msg_id = MSG_COMMAND;

    kr = msg_send(&msg, SEND_TIMEOUT, 100);
    if (kr != KERN_SUCCESS) {
        IOLog("BusLogicFPSCSI: Failed to send command message: %d\n", kr);
    }
}

/*
 * Dequeue a command
 */
- (void *)dequeueCommand
{
    struct sccb *sccb = NULL;

    simple_lock(&_queueLock);
    if (!queue_empty(&_pendingQueue)) {
        queue_remove_first(&_pendingQueue, sccb, struct sccb *, Sccb_forwardlink);
    }
    simple_unlock(&_queueLock);

    return sccb;
}

@end
