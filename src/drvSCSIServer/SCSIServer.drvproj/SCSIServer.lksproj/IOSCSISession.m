/*
 * IOSCSISession.m
 * SCSI session implementation for SCSIServer driver
 */

#import "IOSCSISession.h"
#import "IOTask.h"
#import <objc/objc-runtime.h>
#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <mach/mach.h>

/* Global SCSI session structures */
static void *_scsiSessionList = NULL;      /* Head of session list (circular linked list) */
static void *_scsiSessionListTail = NULL;  /* Tail of session list */
static id _scsiSessionListLock = NULL;     /* Lock protecting the session list */
static int _sSessionIndex = 0;             /* Global session index counter */

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
 * or via initServerWithTask:sendPort:.
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
 * initForDevice:result:, but only through initServerWithTask:sendPort:.
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
 * offset +0: next pointer (circular list)
 * offset +4: prev pointer (circular list)
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
            IOTaskPortDeallocate(notify_port);
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

    return nil;
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
 * initServerWithTask:sendPort: - Initialize server with Mach task and send port
 * task: Mach task port
 * sendPort: Pointer to send port (output parameter)
 * Returns: self on success, calls free and returns that result on failure
 *
 * Sets up the Mach messaging infrastructure for SCSI communication.
 *
 * Session structure (at offset +4, size 0x1c bytes):
 * offset +0: next pointer (circular list)
 * offset +4: prev pointer (circular list)
 * offset +8: (unused/reserved)
 * offset +c: notify port (from IOTaskPortAllocateName)
 * offset +10: death port (from IORequestNotifyForClientTask)
 * offset +14: session object ID (from objc_msgSend with selector 0xa70)
 * offset +18: session index (_sSessionIndex)
 */
- (int)initServerWithTask:(mach_port_t)task sendPort:(mach_port_t *)sendPort
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

@end



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
             * in initServerWithTask:sendPort:
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
            next[1] = (int)prev;           /* next->prev = prev */
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

