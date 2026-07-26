/*
 * IOPortSession.m
 */

#import "IOPortSession.h"
#import "AppleIOPSSafeCondLock.h"
#import <objc/objc-runtime.h>
#import <machkit/NXLock.h>
#import <kern/assert.h>
#import <string.h>			/* memset */
#import <driverkit/generalFuncs.h>	/* IOMalloc, IOFree */
#import <driverkit/kernelDriver.h>	/* IOGetObjectForDeviceName */

/* Global port list structures.  _portListLock is declared first: the
 * reference has it at 33160 and _portList at 33164, i.e. this order.
 */
static id _portListLock;            /* Lock protecting the port list */
static struct {
    void *next;
    void *prev;
} _portList;                        /* Circular list head (next, prev) */

/* Port list entry structure (0x20 bytes)
 * offset +0: next pointer
 * offset +4: prev pointer
 * offset +8: AppleIOPSSafeCondLock object
 * offset +c: NXConditionLock object
 * offset +10: device object pointer
 * offset +14-+1c: unknown fields
 * offset +1d: flag (checked in condition)
 * offset +1e: reference count
 */

@implementation IOPortSession

/*
 * initialize - Class initialization method
 * Called once when the class is first used
 * Initializes the circular linked list for port tracking and creates the list lock
 */
+ (id)initialize
{
    /* Initialize circular linked list pointers
     * Both words of the head point at the head itself, i.e. an empty list
     */
    _portList.prev = &_portList;
    _portList.next = &_portList;

    /* Create NXLock for protecting the port list */
    _portListLock = [[NXLock alloc] init];

    return self;
}

/*
 * init - Initialize basic port session
 *
 * The shipped driver really does send -free to super here; the selector is
 * __message_refs' "free" entry, so -init returns Object's -free result rather
 * than self. That is Apple's apparent copy-paste bug, not ours, and it is
 * inert because nothing in the driver sends bare -init to an IOPortSession
 * (ttyiops.m and IOPortSessionKern.m both use initForDevice:result:).
 * Reproduced as shipped.
 */
- init
{
    return [super free];
}

/*
 * initForDevice:result: - Initialize port session for specific device
 * device: Device name string
 * result: Pointer to result code (output parameter)
 * Returns: initialized session, or [self free]'s result on failure
 *
 * Creates a session state block at _priv with cached device method IMPs.
 * The block is 0x34 bytes containing the device object and the cached IMPs.
 */
- initForDevice:(char *)device result:(int *)result
{
    char conforms;
    int error;
    void **method_cache;
    id device_obj;
    IMP method_imp;

    device_obj = NULL;

    /* Call [super init] */
    [super init];

    /* Get the device object for the given device name */
    error = IOGetObjectForDeviceName(device, &device_obj);
    *result = error;

    if (error == 0) {
        /* Check if device conforms to the required protocol */
        conforms = objc_msgSend(device_obj, @selector(conformsTo:), @protocol(PortDevices));

        if (conforms != 0) {
            /* Allocate session state block (0x34 bytes = 52 bytes = 13 pointers) */
            method_cache = (void **)IOMalloc(0x34);
            memset(method_cache, 0, 0x34);

            /* Store device object at offset +0 */
            method_cache[0] = device_obj;

            /* Store error code at offset +8 */
            *(int *)((char *)method_cache + 8) = 0xfffffd33;  /* -717 */

            /* Clear port entry pointer at offset +4 */
            method_cache[1] = NULL;

            /* Cache method implementations for performance */
            /* offset +c: setState:mask: */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:), @selector(setState:mask:));
            method_cache[3] = (void *)method_imp;

            /* offset +10: getState */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:), @selector(getState));
            method_cache[4] = (void *)method_imp;

            /* offset +14: watchState:mask: */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:), @selector(watchState:mask:));
            method_cache[5] = (void *)method_imp;

            /* offset +18: nextEvent */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:), @selector(nextEvent));
            method_cache[6] = (void *)method_imp;

            /* offset +1c: executeEvent:data: */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:), @selector(executeEvent:data:));
            method_cache[7] = (void *)method_imp;

            /* offset +20: requestEvent:data: */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:), @selector(requestEvent:data:));
            method_cache[8] = (void *)method_imp;

            /* offset +24: enqueueEvent:data:sleep: */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:), @selector(enqueueEvent:data:sleep:));
            method_cache[9] = (void *)method_imp;

            /* offset +28: dequeueEvent:data:sleep: */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:), @selector(dequeueEvent:data:sleep:));
            method_cache[10] = (void *)method_imp;

            /* offset +2c: enqueueData:bufferSize:transferCount:sleep: */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:),
                                     @selector(enqueueData:bufferSize:transferCount:sleep:));
            method_cache[11] = (void *)method_imp;

            /* offset +30: dequeueData:bufferSize:transferCount:minCount: */
            method_imp = objc_msgSend(device_obj, @selector(methodFor:),
                                     @selector(dequeueData:bufferSize:transferCount:minCount:));
            method_cache[12] = (void *)method_imp;

            /* Store the session state block */
            _priv = method_cache;

            return self;
        }

        /* Device doesn't conform to protocol */
        *result = 0xfffffd3e;  /* -706 */
    }

    /* Initialization failed - free self and return what -free returns */
    return [self free];
}

/*
 * free - Free port session and release resources
 *
 * Calls release first, then frees the session state block if allocated
 */
- free
{
    /* Call release to clean up port acquisition */
    [self release];

    /* Free the session state block if it exists */
    if (_priv != NULL) {
        IOFree(_priv, 0x34);
        _priv = NULL;
    }

    return [super free];
}

/*
 * name - Get port name
 * Returns: Port name string or NULL if not initialized
 *
 * Forwards call to device object
 */
- (const char *)name
{
    const char *port_name;

    /* Check if the session state block is not initialized */
    if (_priv == NULL) {
        return NULL;
    }

    /* Call name method on device object at _priv+0 */
    port_name = (const char *)objc_msgSend(*(id *)_priv, @selector(name));

    return port_name;
}

/*
 * locked - Check if port is locked
 * Returns: YES if locked (initialized and no error), NO otherwise
 *
 * Checks if the session state block exists and its error code is 0
 */
- (BOOL)locked
{
    /* Check if the session state block is initialized */
    if (_priv != NULL) {
        /* Check if error code at _priv+8 is 0 */
        if (*(int *)((char *)_priv + 8) == 0) {
            return YES;  /* Locked/acquired */
        }
    }

    return NO;  /* Not locked */
}

/*
 * acquireAudit: - Acquire port for callout/audit (type 1)
 * sleep: Whether to sleep if port is busy
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if not initialized)
 *
 * Wrapper that calls acquirePort:sleep: with type 1 (callout)
 */
- (int)acquireAudit:(BOOL)sleep
{
    int result;

    /* Check if the session state block is initialized */
    if (_priv != NULL) {
        /* Call private acquirePort:sleep: with type 1 */
        result = [self acquirePort:1 sleep:sleep];
        return result;
    }

    /* Not initialized - return error */
    return 0xfffffd3e;  /* -706 decimal */
}

/*
 * acquire: - Acquire port for dialin (type 2)
 * sleep: Whether to sleep if port is busy
 * Returns: Result code (0 on success, 0xfffffd3e/-706 if not initialized)
 *
 * Wrapper that calls acquirePort:sleep: with type 2 (dialin)
 */
- (int)acquire:(BOOL)sleep
{
    int result;

    /* Check if the session state block is initialized */
    if (_priv != NULL) {
        /* Call private acquirePort:sleep: with type 2 */
        result = [self acquirePort:2 sleep:sleep];
        return result;
    }

    /* Not initialized - return error */
    return 0xfffffd3e;  /* -706 decimal */
}

/*
 * release - Release port session
 * Returns: 0 on success, 0xfffffd3e/-706 if not initialized
 *
 * Calls requestType:sleep: with type 0 to release, then calls releasePort
 */
- (int)release
{
    /* Check if the session state block is not initialized */
    if (_priv == NULL) {
        return 0xfffffd3e;  /* -706 decimal */
    }

    /* Check if port entry exists at _priv+4 */
    if (*(void **)((char *)_priv + 4) != NULL) {
        /* Request type 0 (release) with no sleep */
        [self requestType:0 sleep:0];

        /* Release the port */
        [self releasePort];
    }

    return 0;
}

/*
 * setState:mask: - Set port state with mask
 * state: New state value
 * mask: Bits to modify
 * Returns: The device's result, or the session error code
 *
 * Uses cached IMP at method_cache[3] (offset +0xc) for performance
 * Checks error code at _priv+8 before calling
 */
- (int)setState:(unsigned long)state mask:(unsigned long)mask
{
    void **method_cache;
    int error_code;
    typedef int (*SetStateIMP)(id, SEL, unsigned long, unsigned long);
    SetStateIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Check error code at _priv+8 */
    error_code = *(int *)((char *)method_cache + 8);

    if (error_code == 0) {
        /* No error - call cached IMP at method_cache[3] (offset +0xc) */
        cached_imp = (SetStateIMP)method_cache[3];

        /* Call cached method on device object (method_cache[0]) */
        return cached_imp(method_cache[0], @selector(setState:mask:), state, mask);
    }

    /* Return the error code recorded in the session state block */
    return error_code;
}

/*
 * getState - Get current port state
 * Returns: Current state value
 *
 * Uses cached IMP at method_cache[4] (offset +0x10) for performance
 */
- (unsigned long)getState
{
    unsigned long state;
    void **method_cache;
    typedef unsigned long (*GetStateIMP)(id, SEL);
    GetStateIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Call cached IMP at method_cache[4] (offset +0x10) */
    cached_imp = (GetStateIMP)method_cache[4];

    /* Call cached method on device object (method_cache[0]) */
    state = cached_imp(method_cache[0], @selector(getState));

    return state;
}

/*
 * watchState:mask: - Watch for state changes
 * state: Pointer to receive state (output parameter)
 * mask: State bits to watch
 * Returns: The device's result, or the session error code
 *
 * Uses cached IMP at method_cache[5] (offset +0x14) for performance
 * Checks error code at _priv+8 before and after call
 */
- (int)watchState:(unsigned long *)state mask:(unsigned long)mask
{
    int result;
    void **method_cache;
    int error_code;
    typedef int (*WatchStateIMP)(id, SEL, unsigned long *, unsigned long);
    WatchStateIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Check error code at _priv+8 */
    error_code = *(int *)((char *)method_cache + 8);

    if (error_code == 0) {
        /* No error - call cached IMP at method_cache[5] (offset +0x14) */
        cached_imp = (WatchStateIMP)method_cache[5];

        /* Call cached method on device object (method_cache[0]) */
        result = cached_imp(method_cache[0], @selector(watchState:mask:), state, mask);

        /* Check if error code is still 0 after call */
        if (*(int *)((char *)method_cache + 8) == 0) {
            return result;
        }

        /* Error occurred during call - fall through to return it */
        method_cache = (void **)_priv;
    }

    /* Return the error code recorded in the session state block */
    return *(int *)((char *)method_cache + 8);
}

/*
 * nextEvent - Get next pending event
 * Returns: Next event code
 *
 * Uses cached IMP at method_cache[6] (offset +0x18) for performance
 * Returns 0 if error code is set
 */
- (unsigned long)nextEvent
{
    void **method_cache;
    int error_code;
    unsigned long event;
    typedef unsigned long (*NextEventIMP)(id, SEL);
    NextEventIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Check error code at _priv+8 */
    error_code = *(int *)((char *)method_cache + 8);

    if (error_code == 0) {
        /* No error - call cached IMP at method_cache[6] (offset +0x18) */
        cached_imp = (NextEventIMP)method_cache[6];

        /* Call cached method on device object (method_cache[0]) */
        event = cached_imp(method_cache[0], @selector(nextEvent));

        return event;
    }

    /* Error - return 0 */
    return 0;
}

/*
 * executeEvent:data: - Execute immediate event
 * event: Event code
 * data: Event data
 * Returns: The device's result, or the session error code
 *
 * Uses cached IMP at method_cache[7] (offset +0x1c) for performance
 * Checks error code at _priv+8 before calling
 */
- (int)executeEvent:(unsigned long)event data:(unsigned long)data
{
    void **method_cache;
    int error_code;
    typedef int (*ExecuteEventIMP)(id, SEL, unsigned long, unsigned long);
    ExecuteEventIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Check error code at _priv+8 */
    error_code = *(int *)((char *)method_cache + 8);

    if (error_code == 0) {
        /* No error - call cached IMP at method_cache[7] (offset +0x1c) */
        cached_imp = (ExecuteEventIMP)method_cache[7];

        /* Call cached method on device object (method_cache[0]) */
        return cached_imp(method_cache[0], @selector(executeEvent:data:), event, data);
    }

    /* Return the error code recorded in the session state block */
    return error_code;
}

/*
 * requestEvent:data: - Request event data
 * event: Event code
 * data: Pointer to receive data (output parameter)
 * Returns: The device's result, or the session error code
 *
 * Uses cached IMP at method_cache[8] (offset +0x20) for performance
 * Checks error code at _priv+8 before calling
 */
- (int)requestEvent:(unsigned long)event data:(unsigned long *)data
{
    void **method_cache;
    int error_code;
    typedef int (*RequestEventIMP)(id, SEL, unsigned long, unsigned long *);
    RequestEventIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Check error code at _priv+8 */
    error_code = *(int *)((char *)method_cache + 8);

    if (error_code == 0) {
        /* No error - call cached IMP at method_cache[8] (offset +0x20) */
        cached_imp = (RequestEventIMP)method_cache[8];

        /* Call cached method on device object (method_cache[0]) */
        return cached_imp(method_cache[0], @selector(requestEvent:data:), event, data);
    }

    /* Return the error code recorded in the session state block */
    return error_code;
}

/*
 * enqueueEvent:data:sleep: - Enqueue event with data
 * event: Event code
 * data: Event data
 * sleep: Whether to sleep if queue is full
 * Returns: Result code (0 on success)
 *
 * Uses cached IMP at method_cache[9] (offset +0x24) for performance
 * Checks error code at _priv+8 before and after call
 */
- (int)enqueueEvent:(unsigned long)event data:(unsigned long)data sleep:(BOOL)sleep
{
    int result;
    void **method_cache;
    int error_code;
    typedef int (*EnqueueEventIMP)(id, SEL, unsigned long, unsigned long, int);
    EnqueueEventIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Check error code at _priv+8 */
    error_code = *(int *)((char *)method_cache + 8);

    if (error_code == 0) {
        /* No error - call cached IMP at method_cache[9] (offset +0x24) */
        cached_imp = (EnqueueEventIMP)method_cache[9];

        /* Call cached method on device object (method_cache[0]) */
        result = cached_imp(method_cache[0],
                           @selector(enqueueEvent:data:sleep:),
                           event, data, sleep);

        /* Check if error code changed after call */
        if (*(int *)((char *)method_cache + 8) != 0) {
            result = *(int *)((char *)method_cache + 8);
        }
    } else {
        /* Return error code from _priv+8 */
        result = error_code;
    }

    return result;
}

/*
 * dequeueEvent:data:sleep: - Dequeue event with data
 * event: Pointer to receive event code (output parameter)
 * data: Pointer to receive event data (output parameter)
 * sleep: Whether to sleep if queue is empty
 * Returns: Result code (0 on success)
 *
 * Uses cached IMP at method_cache[10] (offset +0x28) for performance
 * Checks error code at _priv+8 before and after call
 */
- (int)dequeueEvent:(unsigned long *)event data:(unsigned long *)data sleep:(BOOL)sleep
{
    int result;
    void **method_cache;
    int error_code;
    typedef int (*DequeueEventIMP)(id, SEL, unsigned long *, unsigned long *, int);
    DequeueEventIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Check error code at _priv+8 */
    error_code = *(int *)((char *)method_cache + 8);

    if (error_code == 0) {
        /* No error - call cached IMP at method_cache[10] (offset +0x28) */
        cached_imp = (DequeueEventIMP)method_cache[10];

        /* Call cached method on device object (method_cache[0]) */
        result = cached_imp(method_cache[0],
                           @selector(dequeueEvent:data:sleep:),
                           event, data, sleep);

        /* Check if error code changed after call */
        if (*(int *)((char *)method_cache + 8) != 0) {
            result = *(int *)((char *)method_cache + 8);
        }
    } else {
        /* Return error code from _priv+8 */
        result = error_code;
    }

    return result;
}

/*
 * enqueueData:bufferSize:transferCount:sleep: - Enqueue data for transmission
 * buffer: Data buffer
 * bufferSize: Size of data to enqueue
 * transferCount: Pointer to receive actual bytes transferred (output parameter)
 * sleep: Whether to sleep if buffer is full
 * Returns: Result code (0 on success)
 *
 * Uses cached IMP at method_cache[11] (offset +0x2c) for performance
 * Checks error code at _priv+8 before and after call
 */
- (int)enqueueData:(char *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
             sleep:(BOOL)sleep
{
    int result;
    void **method_cache;
    int error_code;
    typedef int (*EnqueueDataIMP)(id, SEL, char *, unsigned int, unsigned int *, int);
    EnqueueDataIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Check error code at _priv+8 */
    error_code = *(int *)((char *)method_cache + 8);

    if (error_code == 0) {
        /* No error - call cached IMP at method_cache[11] (offset +0x2c) */
        cached_imp = (EnqueueDataIMP)method_cache[11];

        /* Call cached method on device object (method_cache[0]) */
        result = cached_imp(method_cache[0],
                           @selector(enqueueData:bufferSize:transferCount:sleep:),
                           buffer, bufferSize, transferCount, sleep);

        /* Check if error code changed after call */
        if (*(int *)((char *)method_cache + 8) != 0) {
            result = *(int *)((char *)method_cache + 8);
        }
    } else {
        /* Return error code from _priv+8 */
        result = error_code;
    }

    return result;
}

/*
 * dequeueData:bufferSize:transferCount:minCount: - Dequeue received data
 * buffer: Buffer to receive data
 * bufferSize: Maximum buffer size
 * transferCount: Pointer to receive actual bytes transferred (output parameter)
 * minCount: Minimum bytes required before returning
 * Returns: Result code (0 on success)
 *
 * Uses cached IMP at method_cache[12] (offset +0x30) for performance
 * Checks error code at _priv+8 before and after call
 */
- (int)dequeueData:(char *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
          minCount:(unsigned int)minCount
{
    int result;
    void **method_cache;
    int error_code;
    typedef int (*DequeueDataIMP)(id, SEL, char *, unsigned int, unsigned int *, unsigned int);
    DequeueDataIMP cached_imp;

    /* Get the session state block */
    method_cache = (void **)_priv;

    /* Check error code at _priv+8 */
    error_code = *(int *)((char *)method_cache + 8);

    if (error_code == 0) {
        /* No error - call cached IMP at method_cache[12] (offset +0x30) */
        cached_imp = (DequeueDataIMP)method_cache[12];

        /* Call cached method on device object (method_cache[0]) */
        result = cached_imp(method_cache[0],
                           @selector(dequeueData:bufferSize:transferCount:minCount:),
                           buffer, bufferSize, transferCount, minCount);

        /* Check if error code is still 0 after call */
        if (*(int *)((char *)method_cache + 8) == 0) {
            return result;
        }

        /* Error occurred during call - fall through to return error */
        method_cache = (void **)_priv;
    }

    /* Return error code from _priv+8 */
    return *(int *)((char *)method_cache + 8);
}


@end

@implementation IOPortSession (Private)

/*
 * acquirePort:sleep: - Acquire port with type and sleep option
 * type: Port type to acquire
 * sleep: Whether to sleep if port is busy
 * Returns: Result code (0 on success)
 *
 * Complex method that:
 * 1. Manages a global list of acquired ports
 * 2. Creates port list entries with locks for new acquisitions
 * 3. Increments reference count for already-acquired ports
 */
- (int)acquirePort:(int)type sleep:(BOOL)sleep
{
    BOOL already_in_list;
    void **port_entry;
    int result;
    void **new_entry;
    id safe_cond_lock;
    id nx_cond_lock;
    int error_code;

    /* Check if port entry already exists at _priv+4 */
    if (*(int *)((char *)_priv + 4) != 0) {
        already_in_list = NO;

        /* Special condition check: if type==1 and flag at offset +1d is set */
        if ((type == 1) && (*(char *)(*(int *)((char *)_priv + 4) + 0x1d) != '\0')) {
            already_in_list = YES;
        }
        goto LAB_acquire_request_type;
    }

    /* Lock the global port list */
    objc_msgSend(_portListLock, @selector(lock));

    /* Check if port list is empty (circular list: head points to itself) */
    if (_portList.next == (void *)&_portList) {
LAB_create_new_entry:
        already_in_list = NO;

        /* Try to acquire the device */
        result = objc_msgSend(*(id *)_priv, @selector(acquire:), 0);
        if (result != 0) {
            /* Acquisition failed */
            objc_msgSend(_portListLock, @selector(unlock));
            return result;
        }

        /* Allocate new port list entry (0x20 bytes) */
        new_entry = (void **)IOMalloc(0x20);
        memset(new_entry, 0, 0x20);

        /* Create AppleIOPSSafeCondLock object at offset +8 */
        safe_cond_lock = [[AppleIOPSSafeCondLock alloc] init];
        new_entry[2] = safe_cond_lock;

        /* Create NXConditionLock object at offset +c, initialized with value 1 */
        nx_cond_lock = [[NXConditionLock alloc] initWith:1];
        new_entry[3] = nx_cond_lock;

        /* Store device object pointer at offset +10 */
        new_entry[4] = *(void **)_priv;

        /* Copy byte from offset +1c to offset +1d */
        *(char *)((int)new_entry + 0x1d) = *(char *)((int)new_entry + 0x1c);

        /* Clear fields at offset +14 and +18 */
        new_entry[6] = NULL;
        new_entry[5] = NULL;

        /* Set reference count at offset +1e to 1 */
        *(char *)((int)new_entry + 0x1e) = 1;

        /* Insert into circular linked list */
        if (_portList.next == (void *)&_portList) {
            /* List is empty - create first entry */
            _portList.next = new_entry;
            _portList.prev = new_entry;
            new_entry[0] = &_portList;  /* next = head */
            new_entry[1] = &_portList;  /* prev = head */
        } else {
            /* Insert at tail */
            new_entry[1] = _portList.prev;       /* prev = old tail */
            new_entry[0] = &_portList;           /* next = head */
            *(void **)_portList.prev = new_entry;  /* old_tail->next = new */
            _portList.prev = new_entry;          /* tail = new */
        }

        port_entry = new_entry;
    } else {
        /* Search for existing entry with matching device */
        port_entry = (void **)_portList.next;

        do {
            /* Check if device matches at offset +10 */
            if (port_entry[4] == *(void **)_priv) {
                /* Found matching entry - increment reference count at offset +1e */
                *(char *)((int)port_entry + 0x1e) = *(char *)((int)port_entry + 0x1e) + 1;
                break;
            }

            /* Move to next entry */
            port_entry = (void **)*port_entry;
        } while (port_entry != (void **)&_portList);

        /* If we circled back to head, entry not found - create new one */
        if (port_entry == (void **)&_portList) {
            goto LAB_create_new_entry;
        }

        already_in_list = YES;
    }

    /* Unlock the global port list */
    objc_msgSend(_portListLock, @selector(unlock));

    /* Store port entry pointer at _priv+4 */
    *(void **)((char *)_priv + 4) = port_entry;

LAB_acquire_request_type:
    /* Request the port type */
    error_code = objc_msgSend(self, @selector(requestType:sleep:), type, (int)sleep);

    /* Store error code at _priv+8 */
    *(int *)((char *)_priv + 8) = error_code;

    if (*(int *)((char *)_priv + 8) == 0) {
        /* Success */
        if (already_in_list) {
            /* Release and re-acquire the lock at offset +10 */
            objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0x10),
                        @selector(release));
            objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0x10),
                        @selector(acquire:), 0);
        }
    } else {
        /* Failure - release the port */
        objc_msgSend(self, @selector(releasePort));
    }

    return *(int *)((char *)_priv + 8);
}

/*
 * releasePort - Release acquired port
 *
 * Decrements reference count and removes from global port list if count reaches 0
 * Frees all associated resources when last reference is released
 */
- (void)releasePort
{
    char *ref_count_ptr;
    void **port_entry;
    void **next_entry;
    void **prev_entry;
    void **list_ptr;

    /* Lock the global port list */
    objc_msgSend(_portListLock, @selector(lock));

    /* Check if the session at offset +14 matches self */
    if (*(id *)(*(int *)((char *)_priv + 4) + 0x14) == self) {
        /* Execute event 5 with data 0 on the device */
        objc_msgSend(*(id *)_priv, @selector(executeEvent:data:), 5, 0);
    }

    /* Get pointer to reference count at offset +1e */
    ref_count_ptr = (char *)(*(int *)((char *)_priv + 4) + 0x1e);

    /* Decrement reference count */
    *ref_count_ptr = *ref_count_ptr - 1;

    /* Check if reference count reached 0 */
    if (*ref_count_ptr == 0) {
        /* Last reference - remove from list and free resources */
        port_entry = *(void **)((char *)_priv + 4);

        /* Get next and prev pointers from circular list */
        next_entry = (void **)*port_entry;      /* offset +0 */
        prev_entry = (void **)port_entry[1];    /* offset +4 */

        /* Update prev->next pointer */
        list_ptr = (void **)&_portList;
        if (next_entry != (void **)&_portList) {
            list_ptr = next_entry;
        }
        list_ptr[1] = prev_entry;  /* prev->next = prev_entry */

        /* Update next->prev pointer */
        list_ptr = (void **)&_portList;
        if (prev_entry != (void **)&_portList) {
            list_ptr = prev_entry;
        }
        *list_ptr = next_entry;  /* next->prev = next_entry */

        /* Free the AppleIOPSSafeCondLock at offset +8 */
        objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 8),
                    @selector(free));

        /* Free the NXConditionLock at offset +c */
        objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0xc),
                    @selector(free));

        /* Release the object at offset +10 */
        objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0x10),
                    @selector(release));

        /* Free the port entry structure (0x20 bytes) */
        IOFree(*(void **)((char *)_priv + 4), 0x20);
    }

    /* Unlock the global port list */
    objc_msgSend(_portListLock, @selector(unlock));

    /* Clear the port entry pointer at _priv+4 */
    *(int *)((char *)_priv + 4) = 0;

    /* Set error code at _priv+8 */
    *(int *)((char *)_priv + 8) = 0xfffffd33;  /* -717 decimal */
}

/*
 * getType:sleep: - Take ownership of the port at the given type
 * type: Port type
 * sleep: Whether to sleep if operation would block
 * Returns: Result code (0 on success)
 *
 * Complex locking protocol:
 * 1. Increments flag at offset +1c or +1d based on type parameter
 * 2. Waits on AppleIOPSSafeCondLock for the requested type
 * 3. Locks NXConditionLock, checks condition, unlocks appropriately
 * 4. Stores type and session pointer in port entry
 */
- (int)getType:(int)type sleep:(BOOL)sleep
{
    int result;
    char *flag_ptr;
    int lock_result;
    int condition_value;

    result = 0;

    /* Check if sleep parameter is 0 - if so, return error */
    if (sleep == 0) {
        result = 0xfffffd34;  /* -716 decimal */
    } else {
        /* Determine which flag to increment based on type parameter */
        if (type == 1) {
            /* Type 1: use flag at offset +1c */
            flag_ptr = (char *)(*(int *)((char *)_priv + 4) + 0x1c);
        } else {
            /* Other types: use flag at offset +1d */
            flag_ptr = (char *)(*(int *)((char *)_priv + 4) + 0x1d);
        }

        /* Increment the flag */
        *flag_ptr = *flag_ptr + 1;

        /* Wait on AppleIOPSSafeCondLock at offset +8 for the requested type
         * lockWhen: will block until condition equals the requested type
         */
        lock_result = objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 8),
                                   @selector(lockWhen:), type);

        if (lock_result != 0) {
            /* Lock acquisition failed */
            result = 0xfffffd41;  /* -703 decimal */
        }

        /* Lock the NXConditionLock at offset +c */
        objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0xc),
                    @selector(lock));

        /* Get the condition value from NXConditionLock */
        condition_value = objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0xc),
                                       @selector(condition));

        if (condition_value == 0) {
            /* Condition is 0 - unlock with new condition value 1 */
            objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0xc),
                        @selector(unlockWith:), 1);
        } else {
            /* Condition is not 0 - just unlock */
            objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0xc),
                        @selector(unlock));
        }

        /* Decrement the flag */
        *flag_ptr = *flag_ptr - 1;

        /* If successful, store the type and session pointer */
        if (result == 0) {
            /* Store type at offset +18 */
            *(int *)(*(int *)((char *)_priv + 4) + 0x18) = type;

            /* Store session pointer (self) at offset +14 */
            *(id *)(*(int *)((char *)_priv + 4) + 0x14) = self;
        }
    }

    return result;
}

/*
 * requestType:sleep: - Request port type change
 * type: Requested port type (0=none, 1=callout, 2=dialin)
 * sleep: Whether to sleep if operation would block
 * Returns: Result code (0 on success)
 *
 * Complex state machine for managing port type transitions
 */
- (int)requestType:(int)type sleep:(BOOL)sleep
{
    int result;
    int current_type;
    unsigned int unlock_value;

    if (type != 0) {
        /* Non-zero type requested */

        /* Check if session at offset +14 does NOT match self */
        if (*(id *)(*(int *)((char *)_priv + 4) + 0x14) != self) {
            /* Port is owned by another session */
            current_type = *(int *)(*(int *)((char *)_priv + 4) + 0x18);

            if (current_type == 1) {
                /* Current type is 1 (callout) */
                if (type != 1) {
                    if (type != 2) {
                        return 0xfffffd3e;  /* -706: invalid type */
                    }
                    /* Type 1 -> 2 transition: release old session's port */
                    objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0x14),
                                @selector(releasePort));

                    /* Update type to 2 */
                    *(int *)(*(int *)((char *)_priv + 4) + 0x18) = 2;

                    /* Update session pointer and return success */
                    goto LAB_update_session;
                }
                /* Type 1 -> 1: call getType:sleep: */
                goto LAB_call_gettype;

            } else if (current_type == 0) {
                /* Current type is 0 (none) - acquire lock */
                result = objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 8),
                                     @selector(lock));
                if (result != 0) {
                    return 0xfffffd41;  /* -703: lock failed */
                }

                /* Update type and session */
                *(int *)(*(int *)((char *)_priv + 4) + 0x18) = type;
LAB_update_session:
                *(id *)(*(int *)((char *)_priv + 4) + 0x14) = self;
                return 0;

            } else if (current_type == 2) {
                /* Current type is 2 (dialin) */
                if (type > 2) {
                    return 0xfffffd3e;  /* -706: invalid type */
                }
                if (type == 0) {
                    return 0xfffffd3e;  /* -706: invalid type */
                }
                /* Type 2 -> 1 or 2 -> 2: call getType:sleep: */
                goto LAB_call_gettype;
            } else {
                /* Unknown current type */
                return 0xfffffd3e;  /* -706: invalid type */
            }

        } else {
            /* Port is owned by this session */

            if (type == 1) {
                /* Requesting type 1 */
                if (*(char *)(*(int *)((char *)_priv + 4) + 0x1d) != 0) {
                    /* Flag at +1d is set - recursive request */
                    objc_msgSend(self, @selector(requestType:sleep:), 0, 0);
                    /* Fall through to call getType:sleep: */
                    goto LAB_call_gettype;
                }
            } else if (type != 2) {
                /* Invalid type */
                return 0xfffffd3e;  /* -706 */
            }

            /* Update type directly (session already owns port) */
            *(int *)(*(int *)((char *)_priv + 4) + 0x18) = type;
            return 0;
        }

LAB_call_gettype:
        /* Call getType:sleep: to acquire the requested type */
        result = objc_msgSend(self, @selector(getType:sleep:), type, (int)sleep);
        return result;

    } else {
        /* Type 0 requested - release port */

        /* Clear type and session at offsets +18 and +14 */
        *(int *)(*(int *)((char *)_priv + 4) + 0x18) = 0;
        *(id *)(*(int *)((char *)_priv + 4) + 0x14) = NULL;

        /* Determine unlock value based on flags */
        if (*(char *)(*(int *)((char *)_priv + 4) + 0x1d) == 0) {
            /* Flag at +1d is 0 */
            unlock_value = (unsigned int)(*(char *)(*(int *)((char *)_priv + 4) + 0x1c) != 0);
            if (unlock_value == 0) {
                goto LAB_unlock_safe_cond;
            }
        } else {
            /* Flag at +1d is non-zero */
            unlock_value = 2;
        }

        /* Lock and unlock the NXConditionLock with value 0 */
        objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0xc),
                    @selector(lock));
        objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0xc),
                    @selector(unlockWith:), 0);

LAB_unlock_safe_cond:
        /* Unlock the AppleIOPSSafeCondLock with the calculated value */
        objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 8),
                    @selector(unlockWith:), unlock_value);

        if (unlock_value != 0) {
            /* Wait for lock to become available at condition 1 */
            objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0xc),
                        @selector(lockWhen:), 1);
            objc_msgSend(*(id *)(*(int *)((char *)_priv + 4) + 0xc),
                        @selector(unlock));
        }

        return 0;
    }
}

@end
