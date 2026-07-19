/*
 * IOSCSISession.m
 * SCSI session implementation for SCSIServer driver
 */

#import "IOSCSISession.h"
#import <objc/objc-runtime.h>
#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <mach/mach.h>

/* Global SCSI session structures */
static void *_scsiSessionList = NULL;      /* Head of session list (circular linked list) */
static void *_scsiSessionListTail = NULL;  /* Tail of session list */
static id _scsiSessionListLock = NULL;     /* Lock protecting the session list */
static int _sSessionIndex = 0;             /* Global session index counter */

/* External kernel functions and global variables */
extern int IORequestNotifyForClientTask(mach_port_t task, mach_port_t notifyPort, mach_port_t *deathPort);

/* Global entry structure pointer
 * The '_entry' global contains pointers to kernel functions and data:
 * offset +0x18: Task port for memory operations
 * offset +0xa4: Mach port management functions
 */
extern struct {
    char pad1[0x18];
    mach_port_t task_port;     /* offset +0x18 */
    char pad2[0x8c];
    void *port_funcs;          /* offset +0xa4 */
} *_entry;

/* Page size global - used for address alignment */
extern unsigned int _page_size;

/* Function pointer for session cleanup callback
 * This is loaded from a global variable and called indirectly
 */
typedef void (*session_cleanup_callback_t)(void);
extern session_cleanup_callback_t _scsiSessionCleanupCallback;

/* Helper functions for managing SCSI reservations
 * These are C functions that manage the reservation list
 */
extern void addReservation(id session, int target_high, int target_low, int lun_high, int lun_low);
extern void blastAllReservations(id session);

@implementation IOSCSISession

/*
 * controllerNameList - Get list of available SCSI controller names
 * Returns: NULL (always)
 *
 * NOTE: The decompiled code shows this always returns NULL.
 * This suggests that controller enumeration is not implemented,
 * or controllers are discovered through a different mechanism
 * (possibly via device probing or registration callbacks).
 */
+ (id)controllerNameList
{
    /* Always return NULL */
    return NULL;
}

/*
 * init - Initialize basic SCSI session
 * Returns: result of [self free]
 *
 * NOTE: This is unusual - the init method immediately frees the object!
 * This suggests that IOSCSISession objects should NOT be created via
 * a simple alloc/init pattern, but rather through initForDevice:result:
 * or via _initServerWithTask:sendPort:.
 */
- init
{
    id result;

    /* Call [self free] and return the result
     * This prevents simple alloc/init usage
     */
    result = [self free];
    return result;
}

/*
 * initForDevice:result: - Initialize SCSI session for specific device
 * device: Device name string (const char *)
 * result: Pointer to result code (output parameter)
 * Returns: result of [self free]
 *
 * NOTE: Like init, this method immediately frees the object!
 * This suggests that IOSCSISession should NOT be initialized via
 * initForDevice:result:, but only through _initServerWithTask:sendPort:.
 * The server-based initialization is the only supported path.
 */
- initForDevice:(const char *)device result:(int *)result
{
    id free_result;

    /* Call [self free] and return the result
     * This prevents initForDevice:result: from being used
     */
    free_result = [self free];
    return free_result;
}

/*
 * free - Free SCSI session and release resources
 *
 * Cleans up session structure, releases Mach ports, and calls parent free.
 * If session object ID exists, calls an unknown cleanup function.
 *
 * Session structure (at offset +4, size 0x1c bytes):
 * offset +0: prev pointer (circular list)
 * offset +4: next pointer (circular list)
 * offset +8: object pointer (for releaseAllUnitsForOwner:)
 * offset +c: notify port
 * offset +10: death port
 * offset +14: session object ID
 * offset +18: session index
 */
- free
{
    int session_object_id;
    int object_at_8;
    int death_port;
    int notify_port;
    struct objc_super super_struct;

    session_object_id = 0;

    /* Check if session structure exists at offset +4 */
    if (*(int *)((char *)self + 4) != 0) {
        /* Get object at offset +8 in session structure */
        object_at_8 = *(int *)(*(int *)((char *)self + 4) + 8);

        /* If object exists, call releaseAllUnitsForOwner: on it */
        if (object_at_8 != 0) {
            objc_msgSend((id)object_at_8,
                        @selector(releaseAllUnitsForOwner:),
                        self);
        }

        /* Get session object ID from offset +14 */
        session_object_id = *(int *)(*(int *)((char *)self + 4) + 0x14);

        /* Release death port notification at offset +10 */
        death_port = *(int *)(*(int *)((char *)self + 4) + 0x10);
        if (death_port != 0) {
            IOReleaseNotifyForFunc(death_port, self);
            *(int *)(*(int *)((char *)self + 4) + 0x10) = 0;
        }

        /* Deallocate task port at offset +c */
        notify_port = *(int *)(*(int *)((char *)self + 4) + 0xc);
        if (notify_port != 0) {
            IOTaskPortDeallocate();
            *(int *)(*(int *)((char *)self + 4) + 0xc) = 0;
        }

        /* Free the session structure (0x1c bytes) */
        IOFree(*(void **)((char *)self + 4), 0x1c);
        *(int *)((char *)self + 4) = 0;
    }

    /* Call [super free] using objc_msgSendSuper */
    super_struct.receiver = self;
    super_struct.class = objc_getClass("Object");
    objc_msgSendSuper(&super_struct, @selector(free));

    /* If session object ID exists, call cleanup callback
     * This is FUN_000007bc() in the decompiled code, which loads
     * a function pointer from a global variable and calls it indirectly.
     *
     * PowerPC assembly:
     *   lis   r12, 0x0        ; Load high 16 bits of address into r12
     *   ori   r12, r12, 0x0   ; OR with low 16 bits (address of callback)
     *   mtspr CTR, r12        ; Move r12 to Count Register
     *   bctr                  ; Branch to address in CTR
     *
     * This pattern is an indirect function call through a function pointer
     * stored in a global variable. The callback likely handles session-specific
     * cleanup like releasing session object IDs or updating global session state.
     */
    if (session_object_id != 0) {
        if (_scsiSessionCleanupCallback != NULL) {
            _scsiSessionCleanupCallback();
        }
    }

    return self;
}

/*
 * name - Get SCSI device name
 * Returns: NULL (always)
 *
 * NOTE: The decompiled code shows this always returns NULL.
 * This makes sense since IOSCSISession objects are session objects,
 * not device objects. They don't have names in the traditional sense.
 */
- (const char *)name
{
    /* Always return NULL */
    return NULL;
}

@end


/* ========================================================================
 * Private Category Implementation
 * ======================================================================== */

@implementation IOSCSISession (Private)

/*
 * _initServerWithTask:sendPort: - Initialize server with Mach task and send port
 * task: Mach task port
 * sendPort: Pointer to send port (output parameter)
 * Returns: self on success, calls free and returns that result on failure
 *
 * Sets up the Mach messaging infrastructure for SCSI communication.
 *
 * Session structure (at offset +4, size 0x1c bytes):
 * offset +0: prev pointer (circular list)
 * offset +4: next pointer (circular list)
 * offset +8: (unused/reserved)
 * offset +c: notify port (from IOTaskPortAllocateName)
 * offset +10: death port (from IORequestNotifyForClientTask)
 * offset +14: session object ID (from objc_msgSend with selector 0xa70)
 * offset +18: session index (_sSessionIndex)
 */
- (int)_initServerWithTask:(mach_port_t)task sendPort:(mach_port_t *)sendPort
{
    int result;
    void **session_struct;
    mach_port_t notify_port;
    id session_object_id;
    struct objc_super super_struct;

    /* Call [super init] */
    super_struct.receiver = self;
    super_struct.class = objc_getClass("Object");
    objc_msgSendSuper(&super_struct, @selector(init));

    /* Initialize sendPort to 0 */
    *sendPort = 0;

    /* Allocate session structure (0x1c = 28 bytes) */
    session_struct = (void **)IOMalloc(0x1c);
    if (session_struct == NULL) {
        /* Allocation failed - free self and return */
        return (int)[self free];
    }

    /* Zero out the session structure */
    memset(session_struct, 0, 0x1c);

    /* Store session structure pointer at offset +4 in self */
    *(void ***)((char *)self + 4) = session_struct;

    /* Initialize circular linked list pointers
     * Both prev (offset +4) and next (offset +0) point to self initially
     */
    session_struct[1] = session_struct;  /* prev = self */
    session_struct[0] = session_struct;  /* next = self */

    /* Allocate a Mach port name for this task */
    result = IOTaskPortAllocateName(self);
    if (result != 0) {
        /* Port allocation failed - free self and return */
        return (int)[self free];
    }

    /* Store notify port (self) at offset +c */
    *(id *)((char *)session_struct + 0xc) = self;

    /* Register for client task death notification
     * This sets up the death port at offset +10
     */
    result = IORequestNotifyForClientTask(task,
                                         *(mach_port_t *)((char *)session_struct + 0xc),
                                         (mach_port_t *)((char *)session_struct + 0x10));
    if (result != 0) {
        /* Notification registration failed - free self and return */
        return (int)[self free];
    }

    /* Get session object ID using selector 0xa70
     * This appears to be a method that returns an object identifier
     */
    session_object_id = objc_msgSend(self, (SEL)0xa70);
    *(id *)((char *)session_struct + 0x14) = session_object_id;

    if (*(id *)((char *)session_struct + 0x14) == NULL) {
        /* Failed to get session object ID - free self and return */
        return (int)[self free];
    }

    /* Assign and increment global session index */
    *(int *)((char *)session_struct + 0x18) = _sSessionIndex;
    _sSessionIndex++;

    /* Set sendPort output parameter to self */
    *sendPort = (mach_port_t)self;

    return (int)self;
}

/*
 * _reserveTarget:lun: - Reserve a SCSI target and LUN for this session
 * target: SCSI target ID (0-15)
 * lun: SCSI logical unit number (0-7)
 * Returns: 0 on success, error code on failure
 *
 * This method:
 * 1. Gets the controller object from session structure offset +8
 * 2. Calls reserveTarget:lun:forOwner: on the controller
 * 3. If successful, adds the reservation to this session's reservation list
 *
 * The decompiled code shows sign-extension of the target and lun values
 * (iVar3 >> 0x1f, iVar2 >> 0x1f) which produces the high 32 bits for
 * passing unsigned chars as 64-bit values on PowerPC.
 */
- (int)_reserveTarget:(unsigned char)target lun:(unsigned char)lun
{
    int result;
    id controller;
    int target_val;
    int lun_val;

    /* Convert unsigned char to int */
    target_val = (int)target;
    lun_val = (int)lun;

    /* Get controller object from session structure at offset +8
     * This is the SCSI controller that owns this target/LUN
     */
    controller = *(id *)(*(int *)((char *)self + 4) + 8);

    /* Call reserveTarget:lun:forOwner: on the controller
     * This reserves the target/LUN pair for exclusive use by this session
     */
    result = objc_msgSend(controller,
                         @selector(reserveTarget:lun:forOwner:),
                         target_val,
                         lun_val,
                         self);

    /* If reservation succeeded, add it to this session's reservation list */
    if (result == 0) {
        /* The sign extension (>> 0x1f) extracts the sign bit, which is 0
         * for positive values. This is used to pass 64-bit values on PowerPC.
         * For unsigned chars, this will always be 0.
         */
        addReservation(self,
                      target_val >> 0x1f,  /* High 32 bits of target (always 0) */
                      target_val,           /* Low 32 bits of target */
                      lun_val >> 0x1f,      /* High 32 bits of LUN (always 0) */
                      lun_val);             /* Low 32 bits of LUN */
    }

    return result;
}

@end


/* ========================================================================
 * MIG Server Dispatch Function
 * ======================================================================== */

/* Forward declaration of MIG handler dispatch table (defined below) */
typedef int (*mig_handler_func_t)(int *request, int *reply);
static const mig_handler_func_t _IOSCSISessionMig_handlers[18];

/*
 * IOSCSISessionMig_server - MIG server dispatch function
 * request: Pointer to incoming MIG request message
 * reply: Pointer to outgoing MIG reply message
 * Returns: 1 if message was handled, 0 if not recognized
 *
 * This is the main dispatch function for Mach messages sent to SCSI sessions.
 * It routes incoming messages to the appropriate handler functions based on
 * the message ID.
 *
 * The decompiled code shows this behavior:
 * 1. Set up reply message header with standard MIG fields
 * 2. Check if message ID is in valid range (0x1092 - 0x10a3, 18 messages)
 * 3. Look up handler in dispatch table at offset (msg_id * 4 + -0xaa4)
 * 4. If handler exists, call it and return 1
 * 5. Otherwise return 0 with MIG_BAD_ID error in reply
 *
 * MIG Message IDs: 0x1092 - 0x10a3 (4242 - 4259 decimal, 18 messages total)
 *
 * Message structure offsets:
 * request+0x08: sender port
 * request+0x10: message flags
 * request+0x14: message ID
 *
 * reply+0x03: flags (set to 1)
 * reply+0x04: size (0x20 = 32 bytes)
 * reply+0x08: sender port (copied from request)
 * reply+0x0c: 0
 * reply+0x10: flags (copied from request)
 * reply+0x14: message ID (request ID + 100)
 * reply+0x18: 0x2200018 (NDR record or type descriptor)
 * reply+0x1c: return code (default 0xfffffed1 = MIG_BAD_ID = -303)
 */
int IOSCSISessionMig_server(int *request, int *reply)
{
    int msg_id;
    int handler_offset;
    mig_handler_func_t handler;
    int result;

    /* Set up reply message header
     * The decompiled code shows these exact assignments:
     * *(undefined *)(param_2 + 3) = 1;
     * *(undefined4 *)(param_2 + 4) = 0x20;
     * etc.
     */
    *((unsigned char *)reply + 3) = 1;              /* reply+0x03: flags = 1 */
    reply[1] = 0x20;                                 /* reply+0x04: size = 32 bytes */
    reply[2] = request[2];                           /* reply+0x08: sender port from request+0x08 */
    reply[3] = 0;                                    /* reply+0x0c: 0 */
    reply[4] = request[4];                           /* reply+0x10: flags from request+0x10 */
    reply[5] = request[5] + 100;                     /* reply+0x14: msg ID + 100 */
    reply[6] = 0x2200018;                            /* reply+0x18: NDR/type constant */
    reply[7] = 0xfffffed1;                           /* reply+0x1c: MIG_BAD_ID (-303) */

    /* Get message ID from request
     * *(int *)(param_1 + 0x14)
     */
    msg_id = request[5];                             /* request+0x14: message ID */

    /* Check if message ID is in valid range
     * Decompiled: (*(int *)(param_1 + 0x14) - 0x1092U < 0x12)
     * This checks if: 0x1092 <= msg_id <= 0x10a3 (18 messages)
     */
    if ((unsigned int)(msg_id - 0x1092) < 0x12) {
        /* Calculate handler table index
         * Index = msg_id - 0x1092 (base message ID)
         * This converts message ID to array index (0-17)
         */
        handler_offset = msg_id - 0x1092;

        /* Get handler function pointer from dispatch table
         * The dispatch table _IOSCSISessionMig_handlers is indexed by
         * the message ID offset from the base (0x1092)
         */
        handler = _IOSCSISessionMig_handlers[handler_offset];

        /* Check if handler exists (not NULL)
         * All handlers in the table should be valid, but check anyway
         */
        if (handler != NULL) {
            /* Call the handler function
             * The handler unmarshals parameters, calls the implementation,
             * and marshals the results into the reply message
             */
            (*handler)(request, reply);

            /* Return 1 to indicate message was handled
             * Decompiled: uVar1 = 1;
             */
            result = 1;
        }
        else {
            /* Handler is NULL - message not handled
             * Reply already has MIG_BAD_ID error set
             */
            result = 0;
        }
    }
    else {
        /* Message ID out of range - not handled
         * Decompiled: else { uVar1 = 0; }
         * Reply already has MIG_BAD_ID error set
         */
        result = 0;
    }

    return result;
}


/* ========================================================================
 * MIG Handler Functions
 * ======================================================================== */

/*
 * MIG message format:
 * - MIG messages use a standard header followed by typed parameters
 * - Request messages contain input parameters
 * - Reply messages contain output parameters and return codes
 *
 * Standard MIG message offsets:
 * - request+0x00: message header
 * - request+0x14: message ID
 * - request+0x18+: typed parameters (each parameter has type descriptor + data)
 *
 * - reply+0x00: message header
 * - reply+0x14: reply message ID (request ID + 100)
 * - reply+0x18: NDR record (0x2200018)
 * - reply+0x1c: return code (kern_return_t)
 * - reply+0x20+: typed output parameters
 */

/*
 * MIG Handler: Reserve SCSI-3 Target (Message ID 0x1092 / 4242)
 *
 * Reserves a SCSI-3 target/LUN for exclusive access.
 *
 * Request format:
 *   +0x18: session port (implied in server context)
 *   +0x1c: target high 32 bits
 *   +0x20: target low 32 bits
 *   +0x24: LUN high 32 bits
 *   +0x28: LUN low 32 bits
 *
 * Reply format:
 *   +0x1c: return code (0 on success)
 */
int _IOSCSISession_reserveSCSI3Target_handler(int *request, int *reply)
{
    id session;
    unsigned int target[2];
    unsigned int lun[2];
    int result;

    /* Extract session from message context (typically stored in a per-message context) */
    session = (id)request[3];  /* Adjust based on actual message format */

    /* Extract target (64-bit) */
    target[0] = request[7];   /* High 32 bits */
    target[1] = request[8];   /* Low 32 bits */

    /* Extract LUN (64-bit) */
    lun[0] = request[9];      /* High 32 bits */
    lun[1] = request[10];     /* Low 32 bits */

    /* Call implementation */
    result = IOSCSISession_reserveSCSI3Target(session, target, lun);

    /* Set return code in reply */
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Release SCSI-3 Target (Message ID 0x1093 / 4243)
 */
int _IOSCSISession_releaseSCSI3Target_handler(int *request, int *reply)
{
    id session;
    unsigned int target[2];
    unsigned int lun[2];
    int result;

    session = (id)request[3];
    target[0] = request[7];
    target[1] = request[8];
    lun[0] = request[9];
    lun[1] = request[10];

    result = IOSCSISession_releaseSCSI3Target(session, target, lun);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Reserve Target (Legacy) (Message ID 0x1094 / 4244)
 */
int _IOSCSISession_reserveTarget_handler(int *request, int *reply)
{
    id session;
    unsigned char target;
    unsigned char lun;
    int result;

    session = (id)request[3];
    target = (unsigned char)request[7];
    lun = (unsigned char)request[8];

    result = IOSCSISession_reserveTarget(session, target, lun);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Release Target (Legacy) (Message ID 0x1095 / 4245)
 */
int _IOSCSISession_releaseTarget_handler(int *request, int *reply)
{
    id session;
    unsigned char target;
    unsigned char lun;
    int result;

    session = (id)request[3];
    target = (unsigned char)request[7];
    lun = (unsigned char)request[8];

    result = IOSCSISession_releaseTarget(session, target, lun);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Execute SCSI-3 Request (Message ID 0x1096 / 4246)
 */
int _IOSCSISession_executeSCSI3Request_handler(int *request, int *reply)
{
    id session;
    void *scsi_request;
    mach_port_t client;
    int buffer_size;
    int result;

    session = (id)request[3];
    scsi_request = (void *)&request[7];  /* Inline SCSI request structure */
    client = request[40];  /* Client port */
    buffer_size = request[41];

    result = IOSCSISession_executeSCSI3Request(session, scsi_request, client,
                                               buffer_size, &result);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Execute SCSI-3 Request with Scatter-Gather (Message ID 0x1097 / 4247)
 */
int _IOSCSISession_executeSCSI3RequestScatter_handler(int *request, int *reply)
{
    id session;
    void *scsi_request;
    mach_port_t client;
    void *io_ranges;
    unsigned int range_count;
    int result;

    session = (id)request[3];
    scsi_request = (void *)&request[7];
    client = request[40];
    io_ranges = (void *)&request[42];
    range_count = request[41];

    result = IOSCSISession_executeSCSI3RequestScatter(session, scsi_request, client,
                                                      io_ranges, range_count, &result);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Execute SCSI-3 Request with OOL Scatter-Gather (Message ID 0x1098 / 4248)
 */
int _IOSCSISession_executeSCSI3RequestOOLScatter_handler(int *request, int *reply)
{
    id session;
    void *scsi_request;
    mach_port_t client;
    void *ool_data;
    int ool_size;
    int result;

    session = (id)request[3];
    scsi_request = (void *)&request[7];
    client = request[40];
    ool_data = (void *)request[42];
    ool_size = request[43];

    result = IOSCSISession_executeSCSI3RequestOOLScatter(session, scsi_request, client,
                                                         ool_data, ool_size, &result);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Execute Request (Legacy) (Message ID 0x1099 / 4249)
 */
int _IOSCSISession_executeRequest_handler(int *request, int *reply)
{
    id session;
    void *scsi_request;
    mach_port_t client;
    int buffer_size;
    int result;

    session = (id)request[3];
    scsi_request = (void *)&request[7];
    client = request[40];
    buffer_size = request[41];

    result = IOSCSISession_executeRequest(session, scsi_request, client,
                                          buffer_size, &result);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Execute Request with Scatter-Gather (Legacy) (Message ID 0x109A / 4250)
 */
int _IOSCSISession_executeRequestScatter_handler(int *request, int *reply)
{
    id session;
    void *scsi_request;
    mach_port_t client;
    void *io_ranges;
    unsigned int range_count;
    int result;

    session = (id)request[3];
    scsi_request = (void *)&request[7];
    client = request[40];
    io_ranges = (void *)&request[42];
    range_count = request[41];

    result = IOSCSISession_executeRequestScatter(session, scsi_request, client,
                                                 io_ranges, range_count, &result);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Execute Request with OOL Scatter-Gather (Legacy) (Message ID 0x109B / 4251)
 */
int _IOSCSISession_executeRequestOOLScatter_handler(int *request, int *reply)
{
    id session;
    void *scsi_request;
    mach_port_t client;
    void *ool_data;
    int ool_size;
    int result;

    session = (id)request[3];
    scsi_request = (void *)&request[7];
    client = request[40];
    ool_data = (void *)request[42];
    ool_size = request[43];

    result = IOSCSISession_executeRequestOOLScatter(session, scsi_request, client,
                                                    ool_data, ool_size, &result);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Reset SCSI Bus (Message ID 0x109C / 4252)
 */
int _IOSCSISession_resetSCSIBus_handler(int *request, int *reply)
{
    id session;
    unsigned int result;

    session = (id)request[3];

    IOSCSISession_resetSCSIBus(session, &result);
    reply[7] = 0;
    reply[8] = result;

    return 0;
}

/*
 * MIG Handler: Get Number of Targets (Message ID 0x109D / 4253)
 */
int _IOSCSISession_numberOfTargets_handler(int *request, int *reply)
{
    id session;
    unsigned int num_targets;

    session = (id)request[3];

    IOSCSISession_numberOfTargets(session, &num_targets);
    reply[7] = 0;
    reply[8] = num_targets;

    return 0;
}

/*
 * MIG Handler: Get DMA Alignment (Message ID 0x109E / 4254)
 */
int _IOSCSISession_getDMAAlignment_handler(int *request, int *reply)
{
    id session;
    unsigned int alignment;

    session = (id)request[3];

    IOSCSISession_getDMAAlignment(session, &alignment);
    reply[7] = 0;
    reply[8] = alignment;

    return 0;
}

/*
 * MIG Handler: Get Max Transfer Size (Message ID 0x109F / 4255)
 */
int _IOSCSISession_maxTransfer_handler(int *request, int *reply)
{
    id session;
    unsigned int max_transfer;

    session = (id)request[3];

    IOSCSISession_maxTransfer(session, &max_transfer);
    reply[7] = 0;
    reply[8] = max_transfer;

    return 0;
}

/*
 * MIG Handler: Release All Units (Message ID 0x10A0 / 4256)
 */
int _IOSCSISession_releaseAllUnits_handler(int *request, int *reply)
{
    id session;
    int result;

    session = (id)request[3];

    result = IOSCSISession_releaseAllUnits(session);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Free Session (Message ID 0x10A1 / 4257)
 */
int _IOSCSISession_free_handler(int *request, int *reply)
{
    id session;
    int result;

    session = (id)request[3];

    result = IOSCSISession_free(session);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Initialize for Device (Message ID 0x10A2 / 4258)
 */
int _IOSCSISession_initForDevice_handler(int *request, int *reply)
{
    id session;
    const char *device_name;
    int result;

    session = (id)request[3];
    device_name = (const char *)&request[7];

    result = IOSCSISession_initForDevice(session, device_name);
    reply[7] = result;

    return 0;
}

/*
 * MIG Handler: Return from SCSI Status (Message ID 0x10A3 / 4259)
 */
int _IOSCSISession_returnFromScStatus_handler(int *request, int *reply)
{
    id session;
    unsigned int sc_status;

    session = (id)request[3];
    sc_status = request[7];

    IOSCSISession_returnFromScStatus(session, sc_status);
    reply[7] = 0;

    return 0;
}

/* ========================================================================
 * MIG Handler Table
 * ======================================================================== */

/*
 * MIG Handler Dispatch Table
 *
 * This table maps message IDs (0x1092 - 0x10a3) to handler functions.
 * The IOSCSISessionMig_server function uses this table to dispatch
 * incoming MIG messages to the appropriate handler.
 *
 * Message ID calculation:
 *   handler_offset = msg_id * 4 + (-0xaa4)
 *
 * The table is accessed as: *(handler_table_base + msg_id * 4 - 0xaa4)
 *
 * For proper linkage, this table needs to be at the correct offset in memory.
 * In the binary, the calculation (-0xaa4 + msg_id * 4) resolves to addresses
 * in the dispatch table section.
 *
 * NOTE: In the actual binary, this table is embedded at a specific location
 * such that the formula (msg_id * 4 + (-0xaa4)) correctly indexes into it.
 * For a complete recreation, you would need to use linker scripts or
 * compiler-specific directives to place this at the correct address.
 */
static const mig_handler_func_t _IOSCSISessionMig_handlers[18] = {
    _IOSCSISession_reserveSCSI3Target_handler,           /* 0x1092 / 4242 */
    _IOSCSISession_releaseSCSI3Target_handler,           /* 0x1093 / 4243 */
    _IOSCSISession_reserveTarget_handler,                /* 0x1094 / 4244 */
    _IOSCSISession_releaseTarget_handler,                /* 0x1095 / 4245 */
    _IOSCSISession_executeSCSI3Request_handler,          /* 0x1096 / 4246 */
    _IOSCSISession_executeSCSI3RequestScatter_handler,   /* 0x1097 / 4247 */
    _IOSCSISession_executeSCSI3RequestOOLScatter_handler,/* 0x1098 / 4248 */
    _IOSCSISession_executeRequest_handler,               /* 0x1099 / 4249 */
    _IOSCSISession_executeRequestScatter_handler,        /* 0x109A / 4250 */
    _IOSCSISession_executeRequestOOLScatter_handler,     /* 0x109B / 4251 */
    _IOSCSISession_resetSCSIBus_handler,                 /* 0x109C / 4252 */
    _IOSCSISession_numberOfTargets_handler,              /* 0x109D / 4253 */
    _IOSCSISession_getDMAAlignment_handler,              /* 0x109E / 4254 */
    _IOSCSISession_maxTransfer_handler,                  /* 0x109F / 4255 */
    _IOSCSISession_releaseAllUnits_handler,              /* 0x10A0 / 4256 */
    _IOSCSISession_free_handler,                         /* 0x10A1 / 4257 */
    _IOSCSISession_initForDevice_handler,                /* 0x10A2 / 4258 */
    _IOSCSISession_returnFromScStatus_handler            /* 0x10A3 / 4259 */
};


/* ========================================================================
 * C Function Wrappers
 * ======================================================================== */

/*
 * IOSCSISession_reserveTarget - Reserve a legacy target/LUN for a session
 * session: IOSCSISession object
 * target: SCSI target ID (8-bit value)
 * lun: SCSI logical unit number (8-bit value)
 * Returns: 0 on success, error code on failure
 *
 * Legacy version of target reservation using 8-bit target and LUN values.
 * The function:
 * 1. Sign-extends the 8-bit values to create 64-bit target/LUN pairs
 * 2. Calls the controller's reserveTarget:lun:forOwner: method
 * 3. If successful, adds the reservation to the session's list
 *
 * Sign extension: The high 32 bits are created using arithmetic right shift (>> 0x1f)
 * - For values 0-127: high bits = 0x00000000 (positive)
 * - For values 128-255: high bits = 0xFFFFFFFF (negative when treated as signed char)
 */
int IOSCSISession_reserveTarget(id session, unsigned char target, unsigned char lun)
{
    id controller;
    int target_int;
    int lun_int;
    int target_high;
    int lun_high;
    int result;

    /* Convert unsigned char to signed int (sign-extended) */
    target_int = (int)(char)target;
    lun_int = (int)(char)lun;

    /* Create high 32 bits via arithmetic right shift by 31 bits
     * This replicates the sign bit across all 32 bits:
     * - Positive values (0-127): 0 >> 31 = 0x00000000
     * - Negative values (128-255 when cast to signed char): -1 >> 31 = 0xFFFFFFFF
     */
    target_high = target_int >> 0x1f;
    lun_high = lun_int >> 0x1f;

    /* Get controller from session structure at offset +8
     * Decompiled: *(undefined4 *)(*(int *)(param_1 + 4) + 8)
     * session+4 points to an instance variable structure, offset +8 has controller
     */
    controller = *(id *)((*(int *)((char *)session + 4)) + 8);

    /* Call reserveTarget:lun:forOwner: on controller (legacy selector)
     * Decompiled: FUN_00000dc8(controller, s_reserveTarget:lun:forOwner:_00005bd4,
     *                           iVar3, iVar2, param_1)
     * Only passes the low 32 bits of target/LUN to the controller
     */
    result = (int)objc_msgSend(controller,
                               @selector(reserveTarget:lun:forOwner:),
                               target_int,
                               lun_int,
                               session);

    /* If reservation was successful, add it to our list using full 64-bit values
     * Decompiled: if (iVar1 == 0) { _addReservation(...) }
     */
    if (result == 0) {
        addReservation(session, target_high, target_int, lun_high, lun_int);
    }

    /* Return controller's result code */
    return result;
}

/*
 * IOSCSISession_releaseAllUnits - Release all SCSI units reserved by a session
 * session: IOSCSISession object
 * Returns: 0 (always)
 *
 * This function:
 * 1. Calls releaseAllUnitsForOwner: on the controller to release all reserved units
 * 2. Clears the session's reservation list via blastAllReservations
 */
int IOSCSISession_releaseAllUnits(id session)
{
    id controller;

    /* Get controller object from session structure at offset +8 */
    controller = *(id *)(*(int *)((char *)session + 4) + 8);

    /* Call releaseAllUnitsForOwner: on the controller
     * This releases all target/LUN pairs reserved by this session
     */
    objc_msgSend(controller,
                @selector(releaseAllUnitsForOwner:),
                session);

    /* Clear all reservations from the session's internal list */
    blastAllReservations(session);

    return 0;
}

/*
 * IOSCSISession_free - Free a SCSI session
 * session: IOSCSISession object
 * Returns: 0 (always)
 *
 * This is a C wrapper that calls the Objective-C [session free] method.
 */
int IOSCSISession_free(id session)
{
    /* Call the Objective-C free method */
    objc_msgSend(session, @selector(free));

    return 0;
}

/*
 * IOSCSISession_initForDevice - Initialize SCSI session for a device
 * session: IOSCSISession object
 * deviceName: Name of the SCSI device
 * Returns: 0 on success, error code on failure
 *
 * This function:
 * 1. Gets the device object for the given device name
 * 2. Checks if device conforms to SCSIDevices protocol
 * 3. Stores the device object in session structure at offset +8
 *
 * Note: This is different from the Objective-C initForDevice:result: method
 * which always calls free. This C function provides actual initialization.
 */
int IOSCSISession_initForDevice(id session, const char *deviceName)
{
    int result;
    id device_obj;
    char conforms;

    device_obj = NULL;

    /* Get the device object for the given device name */
    result = IOGetObjectForDeviceName((char *)deviceName, &device_obj);

    if (result == 0) {
        /* Check if device conforms to IOSCSIControllerExported protocol */
        conforms = objc_msgSend(device_obj,
                               @selector(conformsTo:),
                               @protocol(IOSCSIControllerExported));

        if (conforms == 0) {
            /* Device doesn't conform to protocol */
            result = -0x2c2;  /* -706 decimal (0xfffffd3e) */
        }
        else {
            /* Store device object in session structure at offset +8
             * This is the same location where the controller object is stored
             * in _initServerWithTask:sendPort:
             */
            *(id *)(*(int *)((char *)session + 4) + 8) = device_obj;
        }
    }

    return result;
}

/*
 * IOSCSISession_getDMAAlignment - Get DMA alignment requirements
 * session: IOSCSISession object
 * alignment: Pointer to receive alignment value (output parameter)
 * Returns: 0 (always)
 *
 * Queries the SCSI controller/device for DMA alignment requirements.
 * This is important for ensuring DMA buffers are properly aligned.
 */
int IOSCSISession_getDMAAlignment(id session, unsigned int *alignment)
{
    id controller;

    /* Get controller/device object from session structure at offset +8 */
    controller = *(id *)(*(int *)((char *)session + 4) + 8);

    /* Call getDMAAlignment: on the controller/device */
    objc_msgSend(controller,
                @selector(getDMAAlignment:),
                alignment);

    return 0;
}

/*
 * IOSCSISession_maxTransfer - Get maximum transfer size
 * session: IOSCSISession object
 * maxTransfer: Pointer to receive max transfer size (output parameter)
 * Returns: 0 (always)
 *
 * Queries the SCSI controller/device for maximum transfer size.
 * This determines the largest single SCSI I/O operation that can be performed.
 */
int IOSCSISession_maxTransfer(id session, unsigned int *maxTransfer)
{
    id controller;
    unsigned int max;

    /* Get controller/device object from session structure at offset +8 */
    controller = *(id *)(*(int *)((char *)session + 4) + 8);

    /* Call maxTransfer on the controller/device and get result */
    max = objc_msgSend(controller, @selector(maxTransfer));

    /* Store result in output parameter */
    *maxTransfer = max;

    return 0;
}


/* ========================================================================
 * Reservation Management Functions
 * ======================================================================== */

/*
 * Reservation structure (0x18 = 24 bytes):
 * offset +0: next pointer (circular list)
 * offset +4: prev pointer (circular list)
 * offset +8: target (high 32 bits)
 * offset +c: target (low 32 bits)
 * offset +10: lun (high 32 bits)
 * offset +14: lun (low 32 bits)
 *
 * The reservation list is stored at session structure offset +4,
 * which is a circular doubly-linked list.
 */

/*
 * addReservation - Add a target/LUN reservation to a session
 * session: IOSCSISession object
 * target_high: High 32 bits of target ID (usually 0)
 * target_low: Low 32 bits of target ID
 * lun_high: High 32 bits of LUN (usually 0)
 * lun_low: Low 32 bits of LUN
 *
 * This function adds a reservation to the session's circular doubly-linked list.
 * Before adding, it checks if the reservation already exists using findReservation().
 * If the reservation doesn't exist, it allocates a new 0x18-byte entry and inserts
 * it at the end of the list (before the list head).
 *
 * The list structure uses the session structure at offset +4 as the list head.
 * The prev pointer at offset +4 in the session structure points to the last entry.
 */
void addReservation(id session, int target_high, int target_low,
                   int lun_high, int lun_low)
{
    char already_exists;
    int *new_entry;
    void **session_struct;
    void **last_entry;

    /* Check if this reservation already exists */
    already_exists = findReservation(session, target_high, target_low, lun_high, lun_low);

    if (already_exists == 0) {
        /* Reservation doesn't exist - create a new one */

        /* Allocate new reservation entry (0x18 = 24 bytes) */
        new_entry = (int *)IOMalloc(0x18);

        /* Initialize the reservation entry:
         * offset +0: next pointer (will be set below)
         * offset +4: prev pointer (will be set below)
         * offset +8: target_high
         * offset +c: target_low
         * offset +10: lun_high
         * offset +14: lun_low
         */
        new_entry[2] = target_high;
        new_entry[3] = target_low;
        new_entry[4] = lun_high;
        new_entry[5] = lun_low;

        /* Get session structure pointer at offset +4 */
        session_struct = *(void ***)((char *)session + 4);

        /* Get pointer to last entry in list
         * session_struct + 4 points to session structure offset +4,
         * which is the prev pointer of the list head
         * This points to the last entry in the circular list
         */
        last_entry = (void **)session_struct[1];  /* session_struct->prev */

        /* Insert new entry at end of list (before list head):
         * 1. last_entry->next = new_entry
         * 2. new_entry->prev = last_entry
         * 3. new_entry->next = session_struct (list head)
         * 4. session_struct->prev = new_entry
         */

        /* Step 1: Make last entry point to new entry */
        *last_entry = new_entry;

        /* Step 2: new_entry->prev = last_entry */
        new_entry[1] = (int)last_entry;

        /* Step 3: new_entry->next = session_struct (list head) */
        new_entry[0] = (int)session_struct;

        /* Step 4: session_struct->prev = new_entry */
        session_struct[1] = new_entry;
    }

    /* If reservation already exists, do nothing (idempotent) */
}

/*
 * blastAllReservations - Remove all reservations from a session
 * session: IOSCSISession object
 *
 * This function walks the circular linked list and frees all reservation
 * entries. The session structure at offset +4 serves as the list head.
 */
void blastAllReservations(id session)
{
    void **list_head;
    void **current;
    void **next;
    void **prev;

    /* Get pointer to list head at session+4
     * The list head is stored at *(session+4), which points to the
     * session structure that contains the list pointers
     */
    list_head = *(void ***)((char *)session + 4);

    /* While list is not empty (head->next != head) */
    while (*(void **)list_head != list_head) {
        /* Get first reservation entry */
        current = *(void ***)list_head;

        /* Get next entry from current->next */
        next = (void **)*current;

        /* Update prev pointer:
         * If next == list_head, make it circular (next->prev = next)
         * Otherwise, next->prev = list_head
         */
        if (next == list_head) {
            next[1] = next;  /* next->prev = next */
        }
        else {
            next[1] = list_head;  /* next->prev = list_head */
        }

        /* Update list_head->next to skip current entry */
        *list_head = next;

        /* Free the reservation entry (0x18 = 24 bytes) */
        IOFree(current, 0x18);
    }
}

/*
 * removeReservation - Remove a specific reservation from a session
 * session: IOSCSISession object
 * target_high: High 32 bits of target ID (usually 0)
 * target_low: Low 32 bits of target ID
 * lun_high: High 32 bits of LUN (usually 0)
 * lun_low: Low 32 bits of LUN
 *
 * Searches the reservation list for a matching target/LUN pair and removes it.
 */
void removeReservation(id session, int target_high, int target_low,
                      int lun_high, int lun_low)
{
    void **list_head;
    int *current;
    int *next;
    int *prev;

    /* Get pointer to list head */
    list_head = *(void ***)((char *)session + 4);

    /* Get first reservation entry */
    current = (int *)*(void **)list_head;

    /* If list is empty, return */
    if (list_head == (void **)current) {
        return;
    }

    /* Walk the circular list */
    do {
        /* Check if this entry matches the target/LUN:
         * current[2] == target_high  (offset +8)
         * current[3] == target_low   (offset +c)
         * current[4] == lun_high     (offset +10)
         * current[5] == lun_low      (offset +14)
         */
        if ((current[2] == target_high) &&
            (current[3] == target_low) &&
            (current[4] == lun_high) &&
            (current[5] == lun_low)) {

            /* Found matching entry - remove it from list */

            /* Get next and prev pointers */
            next = (int *)current[0];  /* current->next */
            prev = (int *)current[1];  /* current->prev */

            /* Unlink from list: prev->next = next, next->prev = prev */
            *(int **)(next + 4) = prev;   /* next->prev = prev */
            *prev = (int)next;             /* prev->next = next */

            /* Free the reservation entry (0x18 = 24 bytes) */
            IOFree(current, 0x18);

            return;
        }

        /* Move to next entry */
        current = (int *)*current;

    } while ((void **)current != list_head);
}

/*
 * findReservation - Find a specific reservation in a session
 * session: IOSCSISession object
 * target_high: High 32 bits of target ID (usually 0)
 * target_low: Low 32 bits of target ID
 * lun_high: High 32 bits of LUN (usually 0)
 * lun_low: Low 32 bits of LUN
 * Returns: 1 if found, 0 if not found
 *
 * Searches the reservation list for a matching target/LUN pair.
 */
int findReservation(id session, int target_high, int target_low,
                   int lun_high, int lun_low)
{
    void **list_head;
    int *current;

    /* Get pointer to list head */
    list_head = *(void ***)((char *)session + 4);

    /* Get first reservation entry */
    current = (int *)*(void **)list_head;

    /* If list is empty, return not found */
    if (list_head == (void **)current) {
        return 0;
    }

    /* Walk the circular list */
    do {
        /* Check if this entry matches the target/LUN */
        if ((current[2] == target_high) &&
            (current[3] == target_low) &&
            (current[4] == lun_high) &&
            (current[5] == lun_low)) {

            /* Found matching entry */
            return 1;
        }

        /* Move to next entry */
        current = (int *)*current;

    } while ((void **)current != list_head);

    /* Not found */
    return 0;
}


/* ========================================================================
 * Client Reference Counting
 * ======================================================================== */

/*
 * Client reference tracking structure
 *
 * Located at address 0x4008 in the binary
 * Valid range: 0x4008 - 0x4087 (128 bytes = 32 ints)
 * Boundary at 0x4088 is marked as _notifyThread
 *
 * This is an array of reference counts, where each entry is a single int
 * representing the reference count for that client slot. The IOReferenceClientTask
 * function searches this array for empty slots (value == 0) and allocates them
 * as needed.
 *
 * Structure:
 * - Array of 32 integers (128 bytes total)
 * - Each entry is a reference count (not a struct)
 * - Empty slots have value 0
 * - Allocated slots have reference count >= 1
 */
static int _clientReferences[32] = {0};  /* Client reference array at 0x4008-0x4087 */

/*
 * Notify thread identifier or boundary marker
 *
 * Located at address 0x4088 in the binary, immediately after _clientReferences
 * This serves as a boundary marker for the client references array in
 * IOReferenceClientTask, which searches until it reaches &_notifyThread.
 *
 * Cross-references show this is used by IORequestNotifyForClientTask,
 * suggesting it may be a thread identifier for notification handling.
 */
static int _notifyThread = 0;  /* Notify thread or boundary marker at 0x4088 */

/* ========================================================================
 * Client Task Notification Management
 * ======================================================================== */

/*
 * Global notification client tracking
 * Maximum 32 (0x20) notification clients can be registered
 *
 * Structure:
 * - notifClients[64]: Array of 32 client entries (2 ints each = 8 bytes)
 *   Entry structure:
 *   offset +0: death port (mach_port_t)
 *   offset +4: reference count
 * - DAT_00004098[64]: Parallel array storing session objects (id)
 * - notifClientCnt: Current number of registered clients
 */
static int notifClients[64];      /* 32 entries * 2 ints = 64 ints */
static id notifClientObjects[32]; /* Parallel array for session objects */
static int notifClientCnt = 0;    /* Current client count */

/*
 * IOReleaseNotifyForFunc - Release notification registration
 * deathPort: Death notification port to release
 * session: IOSCSISession object associated with the notification
 *
 * This function:
 * 1. Searches the notification client array for matching port/session
 * 2. Dereferences the client task
 * 3. Clears the entry (8 bytes)
 * 4. Decrements the client count
 */
void IOReleaseNotifyForFunc(mach_port_t deathPort, id session)
{
    int i;
    int *client_entry;

    /* Iterate through all possible notification slots (0-31) */
    for (i = 0; i < 0x20; i++) {
        /* Get pointer to client entry (2 ints = 8 bytes per entry)
         * Entry layout:
         *   notifClients[i*2+0]: death port
         *   notifClients[i*2+1]: reference count
         */
        client_entry = &notifClients[i * 2];

        /* Check if this entry matches the death port and session */
        if ((client_entry[0] == (int)deathPort) &&
            (notifClientObjects[i] == session)) {

            /* Dereference the client task (decrements reference count) */
            IODereferenceClientTask(&notifClients[i * 2]);

            /* Clear the entry (8 bytes = 2 ints) */
            memset(client_entry, 0, 8);

            /* Decrement global client count */
            notifClientCnt--;
        }
    }
}

/*
 * IODereferenceClientTask - Decrement reference count for a client task
 * clientEntry: Pointer to client entry (death port at offset +0, refcount at offset +4)
 * Returns: 0 on success, result of cleanup function if refcount reaches 0, 4 on error
 *
 * This function:
 * 1. Validates the client entry pointer is in valid range
 * 2. Decrements the reference count
 * 3. If refcount reaches 0, calls cleanup function
 */
int IODereferenceClientTask(int *clientEntry)
{
    int refcount;
    int result;

    /* Validate pointer is within notifClients array
     * Range check: &notifClients[1] <= clientEntry <= &notifClients[33]
     * (Actually checking the reference count field, which is at offset +4)
     *
     * The decompiled code checks:
     * (&UNK_00004007 < param_1 && param_1 <= &UNK_00004087)
     * This appears to check if pointer is within the notifClients array
     */
    if ((clientEntry < &notifClients[0]) ||
        (clientEntry > &notifClients[64])) {
        return 4;  /* Invalid pointer */
    }

    /* Get reference count from offset +4 (second int in entry) */
    refcount = clientEntry[1];

    /* Check if reference count is positive */
    if (refcount <= 0) {
        return 4;  /* Invalid refcount */
    }

    /* Decrement reference count */
    clientEntry[1] = refcount - 1;

    /* If refcount reached 0, call cleanup function */
    if (clientEntry[1] == 0) {
        /* Call function from entry table at offset 0xa4
         * This appears to be a Mach port cleanup function
         * FUN_00001c88(*(undefined4 *)(_entry + 0xa4))
         *
         * This likely calls mach_port_deallocate() or similar
         */
        result = 0;  /* Placeholder - actual cleanup would happen here */
    }
    else {
        result = 0;  /* Success, refcount still > 0 */
    }

    return result;
}

/*
 * IOReferenceClientTask - Reference a client task and increment reference count
 * param_1: Pointer to pointer to client entry (input/output parameter)
 * Returns: 0 on success, 6 if no slots available, error code from kernel function on failure
 *
 * This function manages client task references in a more complex way than just
 * incrementing a counter. It:
 * 1. Checks if *param_1 already points to a valid entry in the reference table
 * 2. If not, searches for an empty slot in the client reference table
 * 3. Calls a kernel function to set up the reference
 * 4. Updates *param_1 to point to the found/allocated entry
 * 5. Increments the reference count in the entry
 *
 * The decompiled code shows this behavior:
 * - If *param_1 is already in valid range (0x4008-0x4087), just increment
 * - Otherwise, search _clientReferences array for an empty slot (where *slot == 0)
 * - Call kernel function FUN_00001be4() to set up the reference
 * - Update *param_1 to point to the allocated slot
 * - Increment the reference count
 *
 * Client reference table range:
 * - Start: &_clientReferences (0x4008)
 * - End: &_notifyThread (appears to be end of client reference array)
 * - Valid range for existing references: 0x4008-0x4087
 */
int IOReferenceClientTask(int **param_1)
{
    int result;
    int *current_entry;
    int *search_ptr;

    /* Get the entry pointer from param_1
     * piVar2 = *param_1
     */
    current_entry = *param_1;

    /* Check if current_entry is already in valid range
     * Decompiled: if (piVar2 <= &UNK_00004007 || &UNK_00004087 < piVar2)
     * Valid range is &_clientReferences[0] to &_clientReferences[31]
     * (0x4008 - 0x4087)
     */
    if ((current_entry < &_clientReferences[0]) || (current_entry > &_clientReferences[31])) {
        /* Entry not in valid range - need to find or allocate a slot */

        /* Start search at beginning of client references table
         * piVar2 = &_clientReferences
         */
        search_ptr = _clientReferences;

        /* Search for an empty slot (where *slot == 0)
         * Decompiled:
         * do {
         *   if (*piVar2 == 0) break;
         *   piVar2 = piVar2 + 1;
         * } while (piVar2 < &_notifyThread);
         */
        while (search_ptr < &_notifyThread) {
            if (*search_ptr == 0) {
                /* Found empty slot */
                break;
            }
            search_ptr = search_ptr + 1;
        }

        /* Check if we found a valid slot
         * Decompiled: if (&UNK_00004087 < piVar2)
         * This checks if search went past the last valid slot
         */
        if (search_ptr > &_clientReferences[31]) {
            /* No empty slots available */
            return 6;  /* Error code 6: no slots */
        }

        /* Call kernel function to set up the reference
         * Decompiled: iVar1 = FUN_00001be4(*(undefined4 *)(_entry + 0xa4),*param_1,piVar2)
         *
         * This appears to be a kernel function that:
         * - Takes the port functions pointer from _entry+0xa4
         * - Takes the original *param_1 value (client identifier?)
         * - Takes the allocated slot pointer
         * - Returns 0 on success, error code on failure
         */
        result = 0;  /* TODO: Call actual kernel function */
        /* result = FUN_00001be4(_entry->port_funcs, *param_1, search_ptr); */

        /* Update *param_1 to point to the allocated slot
         * Decompiled: *param_1 = piVar2
         */
        *param_1 = search_ptr;

        /* Check if kernel function failed
         * Decompiled: if (iVar1 != 0) { return iVar1; }
         */
        if (result != 0) {
            return result;
        }

        /* Update current_entry to point to the new slot */
        current_entry = search_ptr;
    }

    /* Increment reference count in the entry
     * Decompiled: *piVar2 = *piVar2 + 1
     *
     * Note: This increments the value at the entry, which is the reference count.
     * The entry structure appears to be just the reference count itself,
     * not a struct with multiple fields like notifClients.
     */
    *current_entry = *current_entry + 1;

    return 0;  /* Success */
}

/* ========================================================================
 * Memory Wiring Functions
 * ======================================================================== */

/*
 * IOTaskWireMemory - Wire memory in task's address space for DMA
 * address: Virtual address to wire
 * length: Length of memory region in bytes
 *
 * "Wiring" memory locks it into physical RAM and prevents it from being
 * paged out. This is required for DMA operations as the hardware needs
 * stable physical addresses.
 */
void IOTaskWireMemory(unsigned int address, int length)
{
    unsigned int start_addr;
    unsigned int end_addr;
    mach_port_t task_port;

    /* Get task port from global entry structure */
    task_port = _entry->task_port;

    /* Align start address to page boundary (round down) */
    start_addr = address & ~(_page_size - 1);

    /* Calculate end address aligned to page boundary (round up) */
    end_addr = (address + length + (_page_size - 1)) & ~(_page_size - 1);

    /* TODO: Call kernel vm_wire() function
     * FUN_00001a8c(task_port, start_addr, end_addr, 0)
     */
}

/*
 * IOTaskUnwireMemory - Unwire previously wired memory
 * address: Virtual address to unwire
 * length: Length of memory region in bytes
 */
void IOTaskUnwireMemory(unsigned int address, int length)
{
    unsigned int start_addr;
    unsigned int end_addr;
    mach_port_t task_port;

    /* Get task port from global entry structure */
    task_port = _entry->task_port;

    /* Align start address to page boundary (round down) */
    start_addr = address & ~(_page_size - 1);

    /* Calculate end address aligned to page boundary (round up) */
    end_addr = (address + length + (_page_size - 1)) & ~(_page_size - 1);

    /* TODO: Call kernel vm_unwire() function
     * FUN_00001aec(task_port, start_addr, end_addr, 1)
     */
}

/* ========================================================================
 * Port Management Functions
 * ======================================================================== */

/*
 * IOTaskPortDeallocate - Deallocate a Mach port
 * port: Mach port to deallocate
 */
void IOTaskPortDeallocate(mach_port_t port)
{
    void *port_funcs;

    /* Get port management functions from global entry structure */
    port_funcs = _entry->port_funcs;

    /* TODO: Call mach_port_deallocate()
     * FUN_00001a2c(port_funcs, port)
     */
}

/*
 * IOTaskPortAllocateName - Allocate and assign a name to a Mach port
 * name: Port name to assign
 */
void IOTaskPortAllocateName(mach_port_t name)
{
    int result;
    mach_port_t allocated_port;
    void *port_funcs;

    /* Get port management functions from global entry structure */
    port_funcs = _entry->port_funcs;

    /* TODO: Allocate port
     * result = FUN_000019ac(port_funcs, &allocated_port)
     */
    result = 0;

    if (result == 0) {
        /* TODO: Insert send right with name
         * FUN_0000199c(port_funcs, allocated_port, name)
         */
    }
}

/* ========================================================================
 * SCSI Controller Functions
 * ======================================================================== */

/*
 * IOSCSISession_returnFromScStatus - Convert SCSI status to IOReturn
 * session: IOSCSISession object
 * scStatus: SCSI status code
 */
void IOSCSISession_returnFromScStatus(id session, unsigned int scStatus)
{
    id controller;

    /* Get controller from session structure at offset +8 */
    controller = *(id *)((*(int *)((char *)session + 4)) + 8);

    /* TODO: Call returnFromScStatus: on controller
     * FUN_00001890(controller, @selector(returnFromScStatus:), scStatus)
     */
}

/*
 * IOSCSISession_resetSCSIBus - Reset the SCSI bus
 * session: IOSCSISession object
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 */
int IOSCSISession_resetSCSIBus(id session, unsigned int *result)
{
    id controller;
    unsigned int reset_result;

    /* Get controller from session structure at offset +8 */
    controller = *(id *)((*(int *)((char *)session + 4)) + 8);

    /* TODO: Call resetSCSIBus on controller
     * reset_result = FUN_0000184c(controller, @selector(resetSCSIBus))
     */
    reset_result = 0;

    /* Store result */
    *result = reset_result;

    return 0;
}

/*
 * IOSCSISession_executeSCSI3Request - Execute a SCSI-3 request
 * session: IOSCSISession object
 * request: Pointer to SCSI request structure
 * client: Client task port
 * bufferSize: Size of data buffer
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * This is the main entry point for SCSI-3 command execution.
 * It handles two paths:
 * 1. Simple transfer: No buffer or request has embedded buffer
 *    - Checks if target/LUN is reserved
 *    - Executes directly on controller
 * 2. Scatter-gather transfer: External buffer provided
 *    - Creates temporary I/O range on stack
 *    - Calls scatter-gather execution
 *
 * Request structure offsets:
 * offset +0: target ID (high 32 bits)
 * offset +4: target ID (low 32 bits)
 * offset +8: LUN (high 32 bits)
 * offset +12: LUN (low 32 bits)
 * offset +36 (0x24): Buffer address/pointer
 */
int IOSCSISession_executeSCSI3Request(id session, void *request,
                                     mach_port_t client, int bufferSize,
                                     int *result)
{
    id controller;
    char is_reserved;
    int exec_result;
    int *req_ints;

    /* Stack-allocated I/O range for scatter-gather
     * local_18: buffer size
     * local_14: buffer address
     */
    struct {
        int size;
        void *address;
    } ioRange;

    req_ints = (int *)request;

    /* Check if this is a simple transfer (no external buffer) */
    if ((bufferSize == 0) || (req_ints[9] == 0)) {  /* req_ints[9] = offset +0x24 */
        /* Simple transfer path - verify target is reserved first */

        /* Check if target/LUN is reserved by this session
         * Uses target/LUN from request offsets +0, +4, +8, +12
         */
        is_reserved = findReservation(session,
                                      req_ints[0],  /* target high */
                                      req_ints[1],  /* target low */
                                      req_ints[2],  /* LUN high */
                                      req_ints[3]); /* LUN low */

        if (is_reserved == 0) {
            /* Target/LUN not reserved - access denied */
            *result = 7;  /* Error code 7: not reserved */
        }
        else {
            /* Target is reserved - execute the request
             * Call executeSCSI3Request:buffer:client: with NULL buffer
             */
            controller = *(id *)((*(int *)((char *)session + 4)) + 8);

            /* TODO: exec_result = objc_msgSend(controller,
             *          @selector(executeSCSI3Request:buffer:client:),
             *          request, NULL, NULL);
             */
            exec_result = 0;
            *result = exec_result;
        }

        return 0;
    }
    else {
        /* Scatter-gather path - external buffer provided */

        /* Build I/O range on stack
         * local_14 = buffer address (from request offset +0x24)
         * local_18 = buffer size
         */
        ioRange.address = (void *)req_ints[9];
        ioRange.size = bufferSize;

        /* Execute using scatter-gather with single range
         * Pass 8 as rangeCount (1 range << 3 = 8)
         */
        return IOSCSISession_executeSCSI3RequestScatter(session, request, client,
                                                       &ioRange, 8, result);
    }
}

/*
 * IOSCSISession_executeSCSI3RequestScatter - Execute SCSI-3 request with scatter-gather
 * session: IOSCSISession object
 * request: Pointer to SCSI request structure
 * client: Client task port
 * ioRanges: Pointer to array of I/O ranges for scatter-gather
 * rangeCount: Number of ranges encoded in upper bits (actual count = rangeCount >> 3)
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * This function handles two cases:
 * 1. Simple transfer (rangeCount == 0 or request->bufferSize == 0):
 *    - Executes SCSI request with NULL buffer directly
 * 2. Scatter-gather transfer (rangeCount > 0 and bufferSize > 0):
 *    - Creates IOMemoryDescriptor for the scatter-gather list
 *    - Wires the memory for DMA
 *    - Executes SCSI request with the memory descriptor
 *    - Unwires and releases the memory descriptor
 *
 * Request structure offsets:
 * offset +0x20: Direction flags (for wireMemory)
 * offset +0x24: Buffer size
 * offset +0x30: Status/result code (set on error)
 */
int IOSCSISession_executeSCSI3RequestScatter(id session, void *request,
                                             mach_port_t client, void *ioRanges,
                                             unsigned int rangeCount, int *result)
{
    id controller;
    id ioMemDesc;
    int exec_result;
    int wire_result;
    int actualRangeCount;
    int bufferSize;
    unsigned char direction;

    /* Get controller from session structure at offset +8 */
    controller = *(id *)((*(int *)((char *)session + 4)) + 8);

    /* Get buffer size from request at offset +0x24 */
    bufferSize = *(int *)((char *)request + 0x24);

    /* Check if this is a simple transfer (no scatter-gather) */
    if ((rangeCount == 0) || (bufferSize == 0)) {
        /* Simple case: execute with NULL buffer
         * Call executeSCSI3Request:buffer:client: on controller
         */
        /* TODO: exec_result = objc_msgSend(controller,
         *                    @selector(executeSCSI3Request:buffer:client:),
         *                    request, NULL, NULL);
         */
        exec_result = 0;
        *result = exec_result;
    }
    else {
        /* Scatter-gather case: create IOMemoryDescriptor */

        /* Calculate actual range count: rangeCount >> 3
         * The count is encoded in the upper bits
         */
        actualRangeCount = rangeCount >> 3;

        /* Allocate IOMemoryDescriptor */
        /* TODO: ioMemDesc = [[IOMemoryDescriptor alloc]
         *                    initWithIORange:ioRanges
         *                    count:actualRangeCount
         *                    byReference:YES];
         */
        ioMemDesc = NULL;

        if (ioMemDesc == NULL) {
            /* Allocation/initialization failed */
            *result = 8;  /* Error code 8 */
            *(int *)((char *)request + 0x30) = 8;  /* Set status in request */
        }
        else {
            /* Set the client task for the memory descriptor */
            /* TODO: objc_msgSend(ioMemDesc, @selector(setClient:), client); */

            /* Wire the memory for DMA
             * Direction is at request offset +0x20
             */
            direction = *(unsigned char *)((char *)request + 0x20);
            /* TODO: wire_result = objc_msgSend(ioMemDesc,
             *                      @selector(wireMemory:), direction);
             */
            wire_result = 0;

            *result = wire_result;
            *(int *)((char *)request + 0x30) = wire_result;

            if (*result != 0) {
                /* Wiring failed - release the descriptor */
                /* TODO: objc_msgSend(ioMemDesc, @selector(release)); */
            }
        }

        /* If we successfully created and wired the descriptor */
        if (ioMemDesc != NULL) {
            /* Execute SCSI request with the memory descriptor
             * Call executeSCSI3Request:ioMemoryDescriptor: on controller
             */
            /* TODO: exec_result = objc_msgSend(controller,
             *          @selector(executeSCSI3Request:ioMemoryDescriptor:),
             *          request, ioMemDesc);
             */
            exec_result = 0;
            *result = exec_result;

            /* Unwire the memory */
            /* TODO: objc_msgSend(ioMemDesc, @selector(unwireMemory)); */

            /* Release the memory descriptor */
            /* TODO: objc_msgSend(ioMemDesc, @selector(release)); */
        }
    }

    return 0;
}

/*
 * IOSCSISession_executeSCSI3RequestOOLScatter - Execute SCSI-3 with out-of-line data
 * session: IOSCSISession object
 * request: Pointer to SCSI request structure
 * client: Client task port
 * oolData: Out-of-line data buffer pointer
 * oolDataSize: Size of out-of-line data buffer in bytes
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * Out-of-line (OOL) data is memory that was sent via Mach IPC and needs
 * special handling:
 * 1. Wire the OOL memory for DMA access
 * 2. Execute the SCSI request using scatter-gather
 * 3. Unwire the OOL memory
 * 4. Deallocate the OOL memory (via vm_deallocate)
 *
 * This is typically used for large data transfers where the data was
 * passed out-of-line in a Mach message rather than inline.
 */
int IOSCSISession_executeSCSI3RequestOOLScatter(id session, void *request,
                                                mach_port_t client, void *oolData,
                                                int oolDataSize, int *result)
{
    int wire_result;

    /* Initialize result to success */
    *result = 0;

    /* If there's OOL data to process, wire it first */
    if (oolDataSize != 0) {
        /* Wire the out-of-line memory for DMA
         * This locks the pages into physical RAM
         */
        wire_result = IOTaskWireMemory((unsigned int)oolData, oolDataSize);

        if (wire_result != 0) {
            /* Wiring failed */
            *result = 8;  /* Error code 8 */
            *(int *)((char *)request + 0x30) = 8;  /* Set status in request */
        }
    }

    /* If wiring succeeded (or no OOL data), execute the SCSI request */
    if (*result == 0) {
        /* Execute the SCSI request with scatter-gather
         * The oolData/oolDataSize are passed as the ioRanges/rangeCount
         * parameters to the scatter-gather function
         */
        IOSCSISession_executeSCSI3RequestScatter(session, request, client,
                                                 oolData, oolDataSize, result);

        /* If we wired the memory, unwire it now that we're done */
        if (oolDataSize != 0) {
            IOTaskUnwireMemory((unsigned int)oolData, oolDataSize);
        }
    }

    /* Deallocate the out-of-line memory
     * FUN_00001640(oolData, oolDataSize) is likely vm_deallocate()
     * This releases the memory that was sent via Mach IPC
     */
    /* TODO: Call vm_deallocate(mach_task_self(), (vm_address_t)oolData, oolDataSize) */

    return 0;
}

/* ========================================================================
 * Legacy SCSI Request Functions (Pre-SCSI-3 Format)
 * ======================================================================== */

/*
 * IOSCSISession_executeRequest - Execute a legacy SCSI request
 * session: IOSCSISession object
 * request: Pointer to legacy SCSI request structure
 * client: Client task port
 * bufferSize: Size of data buffer
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * This is the legacy entry point for pre-SCSI-3 command execution.
 * It handles two paths similar to the SCSI-3 version but with different
 * request structure offsets:
 *
 * Legacy request structure offsets:
 * offset +0: target ID (high 32 bits)
 * offset +4: target ID (low 32 bits)
 * offset +8: LUN (high 32 bits)
 * offset +12: LUN (low 32 bits)
 * offset +20 (0x14): Buffer address/pointer (not +0x24 like SCSI-3)
 *
 * 1. Simple transfer: No buffer or request has embedded buffer
 *    - Checks if target/LUN is reserved
 *    - Executes directly on controller using executeRequest:buffer:client:
 * 2. Scatter-gather transfer: External buffer provided
 *    - Creates temporary I/O range on stack
 *    - Calls scatter-gather execution
 */
int IOSCSISession_executeRequest(id session, void *request,
                                 mach_port_t client, int bufferSize,
                                 int *result)
{
    id controller;
    char is_reserved;
    int exec_result;
    int *req_ints;

    /* Stack-allocated I/O range for scatter-gather */
    struct {
        int size;
        void *address;
    } ioRange;

    req_ints = (int *)request;

    /* Check if this is a simple transfer (no external buffer)
     * Legacy request has buffer pointer at offset +0x14 (req_ints[5])
     */
    if ((bufferSize == 0) || (req_ints[5] == 0)) {
        /* Simple transfer path - verify target is reserved first */

        /* Check if target/LUN is reserved by this session
         * Note: Legacy format uses bytes directly (param_2[0], param_2[1])
         * which map to the first two bytes of the request structure
         */
        is_reserved = findReservation(session,
                                      0,                                    /* target high = 0 */
                                      ((unsigned char *)request)[0],        /* target low from byte 0 */
                                      0,                                    /* LUN high = 0 */
                                      ((unsigned char *)request)[1]);       /* LUN low from byte 1 */

        if (is_reserved == 0) {
            /* Target/LUN not reserved - access denied */
            *result = 7;  /* Error code 7: not reserved */
        }
        else {
            /* Target is reserved - execute the request
             * Call executeRequest:buffer:client: with NULL buffer
             * Note: Uses executeRequest: not executeSCSI3Request:
             */
            controller = *(id *)((*(int *)((char *)session + 4)) + 8);

            /* TODO: exec_result = objc_msgSend(controller,
             *          @selector(executeRequest:buffer:client:),
             *          request, NULL, NULL);
             */
            exec_result = 0;
            *result = exec_result;
        }

        return 0;
    }
    else {
        /* Scatter-gather path - external buffer provided */

        /* Build I/O range on stack
         * Buffer address from request offset +0x14 (req_ints[5])
         */
        ioRange.address = (void *)req_ints[5];
        ioRange.size = bufferSize;

        /* Execute using scatter-gather with single range
         * Pass 8 as rangeCount (1 range << 3 = 8)
         */
        return IOSCSISession_executeRequestScatter(session, request, client,
                                                  &ioRange, 8, result);
    }
}

/*
 * IOSCSISession_executeRequestScatter - Execute legacy SCSI request with scatter-gather
 * session: IOSCSISession object
 * request: Pointer to legacy SCSI request structure
 * client: Client task port
 * ioRanges: Pointer to array of I/O ranges for scatter-gather
 * rangeCount: Number of ranges encoded in upper bits (actual count = rangeCount >> 3)
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * Legacy version of SCSI-3 scatter-gather execution. Main differences:
 * - Uses executeRequest:buffer:client: selector instead of executeSCSI3Request:buffer:client:
 * - Uses executeRequest:ioMemoryDescriptor: instead of executeSCSI3Request:ioMemoryDescriptor:
 * - Different request structure offsets:
 *   - Direction at offset +0x10 (not +0x20)
 *   - Buffer size at offset +0x14 (not +0x24)
 *   - Status at offset +0x20 (not +0x30)
 *
 * This function handles two cases:
 * 1. Simple transfer (rangeCount == 0 or request->bufferSize == 0):
 *    - Executes SCSI request with NULL buffer directly
 * 2. Scatter-gather transfer (rangeCount > 0 and bufferSize > 0):
 *    - Creates IOMemoryDescriptor for the scatter-gather list
 *    - Wires the memory for DMA
 *    - Executes SCSI request with the memory descriptor
 *    - Unwires and releases the memory descriptor
 */
int IOSCSISession_executeRequestScatter(id session, void *request,
                                        mach_port_t client, void *ioRanges,
                                        unsigned int rangeCount, int *result)
{
    id controller;
    id ioMemDesc;
    int exec_result;
    int wire_result;
    int actualRangeCount;
    int bufferSize;
    unsigned char direction;

    /* Get controller from session structure at offset +8 */
    controller = *(id *)((*(int *)((char *)session + 4)) + 8);

    /* Get buffer size from request at offset +0x14 (legacy offset) */
    bufferSize = *(int *)((char *)request + 0x14);

    /* Check if this is a simple transfer (no scatter-gather) */
    if ((rangeCount == 0) || (bufferSize == 0)) {
        /* Simple case: execute with NULL buffer
         * Call executeRequest:buffer:client: on controller (legacy selector)
         */
        /* TODO: exec_result = objc_msgSend(controller,
         *                    @selector(executeRequest:buffer:client:),
         *                    request, NULL, NULL);
         */
        exec_result = 0;
        *result = exec_result;
    }
    else {
        /* Scatter-gather case: create IOMemoryDescriptor */

        /* Calculate actual range count: rangeCount >> 3
         * The count is encoded in the upper bits
         */
        actualRangeCount = rangeCount >> 3;

        /* Allocate IOMemoryDescriptor */
        /* TODO: ioMemDesc = [[IOMemoryDescriptor alloc]
         *                    initWithIORange:ioRanges
         *                    count:actualRangeCount
         *                    byReference:YES];
         */
        ioMemDesc = NULL;

        if (ioMemDesc == NULL) {
            /* Allocation/initialization failed */
            *result = 8;  /* Error code 8 */
            *(int *)((char *)request + 0x20) = 8;  /* Set status in request (legacy offset) */
        }
        else {
            /* Set the client task for the memory descriptor */
            /* TODO: objc_msgSend(ioMemDesc, @selector(setClient:), client); */

            /* Wire the memory for DMA
             * Direction is at request offset +0x10 (legacy offset, not +0x20)
             */
            direction = *(unsigned char *)((char *)request + 0x10);
            /* TODO: wire_result = objc_msgSend(ioMemDesc,
             *                      @selector(wireMemory:), direction);
             */
            wire_result = 0;

            *result = wire_result;
            *(int *)((char *)request + 0x20) = wire_result;  /* Legacy status offset */

            if (*result != 0) {
                /* Wiring failed - release the descriptor */
                /* TODO: objc_msgSend(ioMemDesc, @selector(release)); */
            }
        }

        /* If we successfully created and wired the descriptor */
        if (ioMemDesc != NULL) {
            /* Execute SCSI request with the memory descriptor
             * Call executeRequest:ioMemoryDescriptor: on controller (legacy selector)
             */
            /* TODO: exec_result = objc_msgSend(controller,
             *          @selector(executeRequest:ioMemoryDescriptor:),
             *          request, ioMemDesc);
             */
            exec_result = 0;
            *result = exec_result;

            /* Unwire the memory */
            /* TODO: objc_msgSend(ioMemDesc, @selector(unwireMemory)); */

            /* Release the memory descriptor */
            /* TODO: objc_msgSend(ioMemDesc, @selector(release)); */
        }
    }

    return 0;
}

/*
 * IOSCSISession_executeRequestOOLScatter - Execute legacy SCSI request with out-of-line data
 * session: IOSCSISession object
 * request: Pointer to legacy SCSI request structure
 * client: Client task port
 * oolData: Out-of-line data buffer pointer
 * oolDataSize: Size of out-of-line data buffer in bytes
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * Legacy version of out-of-line (OOL) data execution. Same basic flow as SCSI-3
 * version but uses legacy request format and calls legacy scatter-gather function.
 *
 * Out-of-line data handling:
 * 1. Wire the OOL memory for DMA access
 * 2. Execute the SCSI request using scatter-gather (legacy version)
 * 3. Unwire the OOL memory
 * 4. Deallocate the OOL memory (via vm_deallocate)
 *
 * This is used for large data transfers where the data was passed out-of-line
 * in a Mach message rather than inline. Status stored at offset +0x20 (not +0x30).
 */
int IOSCSISession_executeRequestOOLScatter(id session, void *request,
                                           mach_port_t client, void *oolData,
                                           int oolDataSize, int *result)
{
    int wire_result;

    /* Initialize result to success */
    *result = 0;

    /* If there's OOL data to process, wire it first */
    if (oolDataSize != 0) {
        /* Wire the out-of-line memory for DMA
         * This locks the pages into physical RAM
         */
        wire_result = IOTaskWireMemory((unsigned int)oolData, oolDataSize);

        if (wire_result != 0) {
            /* Wiring failed */
            *result = 8;  /* Error code 8 */
            *(int *)((char *)request + 0x20) = 8;  /* Set status in request (legacy offset) */
        }
    }

    /* If wiring succeeded (or no OOL data), execute the SCSI request */
    if (*result == 0) {
        /* Execute the SCSI request with scatter-gather (legacy version)
         * The oolData/oolDataSize are passed as the ioRanges/rangeCount
         * parameters to the scatter-gather function
         */
        IOSCSISession_executeRequestScatter(session, request, client,
                                           oolData, oolDataSize, result);

        /* If we wired the memory, unwire it now that we're done */
        if (oolDataSize != 0) {
            IOTaskUnwireMemory((unsigned int)oolData, oolDataSize);
        }
    }

    /* Deallocate the out-of-line memory
     * This releases the memory that was sent via Mach IPC
     */
    /* TODO: Call vm_deallocate(mach_task_self(), (vm_address_t)oolData, oolDataSize) */

    return 0;
}

/* ========================================================================
 * SCSI Controller Query and Management Functions
 * ======================================================================== */

/*
 * IOSCSISession_numberOfTargets - Get number of SCSI targets
 * session: IOSCSISession object
 * numTargets: Pointer to receive number of targets (output parameter)
 * Returns: 0 (always)
 *
 * Queries the SCSI controller for the maximum number of targets it supports.
 * This is typically 8 for narrow SCSI, 16 for wide SCSI.
 */
int IOSCSISession_numberOfTargets(id session, unsigned int *numTargets)
{
    id controller;
    unsigned int target_count;

    /* Get controller from session structure at offset +8 */
    controller = *(id *)((*(int *)((char *)session + 4)) + 8);

    /* TODO: Call numberOfTargets on controller
     * target_count = FUN_000010b0(controller, @selector(numberOfTargets))
     */
    target_count = 0;

    /* Store result */
    *numTargets = target_count;

    return 0;
}

/*
 * IOSCSISession_releaseSCSI3Target - Release a SCSI-3 target/LUN reservation
 * session: IOSCSISession object
 * target: Pointer to 64-bit SCSI target ID (array of 2 x 32-bit values)
 * lun: Pointer to 64-bit SCSI LUN (array of 2 x 32-bit values)
 * Returns: 0 (always)
 *
 * Releases a previously reserved SCSI-3 target and LUN combination.
 * The function:
 * 1. Checks if the target/LUN is actually reserved by this session
 * 2. If found, calls the controller's releaseSCSI3Target:lun:forOwner: method
 * 3. Removes the reservation from the session's reservation list
 *
 * Target and LUN are 64-bit values split into high/low 32-bit parts:
 * - target[0] = high 32 bits
 * - target[1] = low 32 bits
 * - lun[0] = high 32 bits
 * - lun[1] = low 32 bits
 *
 * This matches the SCSI-3 specification which allows 64-bit addressing.
 */
int IOSCSISession_releaseSCSI3Target(id session, unsigned int *target, unsigned int *lun)
{
    id controller;
    unsigned int target_high;
    unsigned int target_low;
    unsigned int lun_high;
    unsigned int lun_low;
    char is_reserved;

    /* Extract 64-bit target ID components */
    target_high = target[0];
    target_low = target[1];

    /* Extract 64-bit LUN components */
    lun_high = lun[0];
    lun_low = lun[1];

    /* Check if this target/LUN is actually reserved by this session */
    is_reserved = findReservation(session, target_high, target_low, lun_high, lun_low);

    if (is_reserved != 0) {
        /* Target/LUN is reserved - release it */

        /* Get controller from session structure at offset +8 */
        controller = *(id *)((*(int *)((char *)session + 4)) + 8);

        /* Call releaseSCSI3Target:lun:forOwner: on controller
         * This notifies the controller that we're releasing our reservation
         */
        /* TODO: FUN_0000104c(controller,
         *          @selector(releaseSCSI3Target:lun:forOwner:),
         *          target_high, target_low, lun_high, lun_low, session);
         */

        /* Remove the reservation from our list */
        removeReservation(session, target_high, target_low, lun_high, lun_low);
    }

    /* Always return 0 (success), even if target wasn't reserved
     * This is idempotent - releasing an unreserved target is not an error
     */
    return 0;
}

/*
 * IOSCSISession_reserveSCSI3Target - Reserve a SCSI-3 target/LUN
 * session: IOSCSISession object
 * target: Pointer to 64-bit SCSI target ID (array of 2 x 32-bit values)
 * lun: Pointer to 64-bit SCSI LUN (array of 2 x 32-bit values)
 * Returns: 0 on success, error code on failure
 *
 * Attempts to reserve a SCSI-3 target and LUN for exclusive access by this session.
 * The function:
 * 1. Calls the controller's reserveSCSI3Target:lun:forOwner: method
 * 2. If successful (returns 0), adds the reservation to the session's list
 * 3. Returns the controller's result code
 *
 * Target and LUN are 64-bit values split into high/low 32-bit parts:
 * - target[0] = high 32 bits
 * - target[1] = low 32 bits
 * - lun[0] = high 32 bits
 * - lun[1] = low 32 bits
 *
 * If the reservation fails (controller returns non-zero), the reservation is NOT
 * added to the session's list, preventing inconsistent state.
 */
int IOSCSISession_reserveSCSI3Target(id session, unsigned int *target, unsigned int *lun)
{
    id controller;
    unsigned int target_high;
    unsigned int target_low;
    unsigned int lun_high;
    unsigned int lun_low;
    int result;

    /* Extract 64-bit target ID components */
    target_high = target[0];
    target_low = target[1];

    /* Extract 64-bit LUN components */
    lun_high = lun[0];
    lun_low = lun[1];

    /* Get controller from session structure at offset +8 */
    controller = *(id *)((*(int *)((char *)session + 4)) + 8);

    /* Call reserveSCSI3Target:lun:forOwner: on controller
     * This asks the controller to reserve the target/LUN for this session
     */
    /* TODO: result = FUN_00000f80(controller,
     *          @selector(reserveSCSI3Target:lun:forOwner:),
     *          target_high, target_low, lun_high, lun_low, session);
     */
    result = 0;

    /* If reservation was successful, add it to our list */
    if (result == 0) {
        addReservation(session, target_high, target_low, lun_high, lun_low);
    }

    /* Return controller's result code */
    return result;
}

/*
 * IOSCSISession_releaseTarget - Release a legacy target/LUN reservation
 * session: IOSCSISession object
 * target: SCSI target ID (8-bit value)
 * lun: SCSI logical unit number (8-bit value)
 * Returns: 0 (always)
 *
 * Legacy version of target release using 8-bit target and LUN values.
 * The function:
 * 1. Sign-extends the 8-bit values to create 64-bit target/LUN pairs
 * 2. Checks if the target/LUN is reserved
 * 3. If found, calls the controller's releaseTarget:lun:forOwner: method
 * 4. Removes the reservation from the session's list
 *
 * Sign extension: The high 32 bits are created using arithmetic right shift (>> 0x1f)
 * - For values 0-127: high bits = 0x00000000 (positive)
 * - For values 128-255: high bits = 0xFFFFFFFF (negative when treated as signed char)
 *
 * Example:
 * - target=5 (char) -> iVar3=5 (int) -> high=0, low=5
 * - target=200 (char) -> iVar3=-56 (int, signed) -> high=0xFFFFFFFF, low=-56
 */
int IOSCSISession_releaseTarget(id session, unsigned char target, unsigned char lun)
{
    id controller;
    int target_int;
    int lun_int;
    int target_high;
    int lun_high;
    char is_reserved;

    /* Convert unsigned char to signed int (sign-extended) */
    target_int = (int)(char)target;
    lun_int = (int)(char)lun;

    /* Create high 32 bits via arithmetic right shift by 31 bits
     * This replicates the sign bit across all 32 bits:
     * - Positive values (0-127): 0 >> 31 = 0x00000000
     * - Negative values (128-255 when cast to signed char): -1 >> 31 = 0xFFFFFFFF
     */
    target_high = target_int >> 0x1f;
    lun_high = lun_int >> 0x1f;

    /* Check if this target/LUN is reserved by this session */
    is_reserved = findReservation(session, target_high, target_int, lun_high, lun_int);

    if (is_reserved != 0) {
        /* Target/LUN is reserved - release it */

        /* Get controller from session structure at offset +8 */
        controller = *(id *)((*(int *)((char *)session + 4)) + 8);

        /* Call releaseTarget:lun:forOwner: on controller (legacy selector)
         * Only passes the low 32 bits of target/LUN to the controller
         */
        /* TODO: FUN_00000eb4(controller,
         *          @selector(releaseTarget:lun:forOwner:),
         *          target_int, lun_int, session);
         */

        /* Remove the reservation from our list using full 64-bit values */
        removeReservation(session, target_high, target_int, lun_high, lun_int);
    }

    /* Always return 0 (success) */
    return 0;
}

