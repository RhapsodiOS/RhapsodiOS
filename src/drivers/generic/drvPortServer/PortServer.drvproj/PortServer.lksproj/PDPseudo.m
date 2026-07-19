/*
 * PDPseudo.m
 * Pseudo serial device for PortServer driver
 */

#import "PDPseudo.h"
#import <objc/objc-runtime.h>

/* Global flag to track if pseudo device has been loaded */
static char _PseudoDeviceLoaded = '\0';

@implementation PDPseudo

/*
 * deviceStyle - Return device style
 * Returns: 2 (device style constant)
 *
 * Class method that returns the style/type of this device.
 */
+ (int)deviceStyle
{
    return 2;
}

/*
 * probe: - Probe for pseudo device
 * deviceDescription: Device description to probe
 * Returns: 1 if probe successful, 0 otherwise
 *
 * Attempts to allocate and initialize a PDPseudo device.
 * Returns 1 if initialization succeeds (device present), 0 otherwise.
 */
+ (char)probe:(id)deviceDescription
{
    id pseudoDevice;
    int initResult;

    /* Allocate and initialize PDPseudo with device description */
    pseudoDevice = objc_msgSend(objc_getClass("PDPseudo"),
                                @selector(alloc));
    pseudoDevice = objc_msgSend(pseudoDevice,
                                @selector(initFromDeviceDescription:),
                                deviceDescription);

    /* Check if initialization succeeded */
    initResult = objc_msgSend(pseudoDevice);

    if (initResult == 0) {
        return 0;  /* Probe failed */
    }

    return 1;  /* Probe succeeded */
}

/*
 * initFromDeviceDescription: - Initialize pseudo device from device description
 * deviceDescription: Device description structure
 * Returns: initialized object or nil on failure
 *
 * Only initializes once (singleton pattern using _PseudoDeviceLoaded flag)
 * Sets device name and kind, then registers the device
 */
- initFromDeviceDescription:(void *)deviceDescription
{
    id result;
    struct objc_super super_struct;

    /* Check if pseudo device has already been loaded */
    if (_PseudoDeviceLoaded == '\0') {
        /* Mark as loaded */
        _PseudoDeviceLoaded = '\x01';

        /* Set device name to "PDPseudo" */
        [self setName:"PDPseudo"];

        /* Set device kind to "Server Device" */
        [self setDeviceKind:"Server Device"];

        /* Call [super initFromDeviceDescription:] using objc_msgSendSuper */
        super_struct.receiver = self;
        super_struct.class = objc_getClass("IODevice");
        result = objc_msgSendSuper(&super_struct,
                                   @selector(initFromDeviceDescription:),
                                   deviceDescription);

        if (result != nil) {
            /* Registration successful - register the device */
            [self registerDevice];
            return result;
        }
    }

    /* Already loaded or initialization failed - free self and return nil */
    result = [self free];
    return result;
}

/*
 * acquire: - Acquire pseudo device
 * param: Acquisition parameter
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices cannot be acquired - always returns error
 */
- (int)acquire:(int)param
{
    /* Pseudo devices cannot be acquired */
    return 0xfffffd42;  /* -702 decimal */
}

/*
 * release - Release pseudo device
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices cannot be released - always returns error
 */
- (void)release
{
    /* Operation not supported - no-op */
    /* Note: Decompiled shows return 0xfffffd42 but signature is void */
}


/*
 * getState - Get current device state
 * Returns: Current state value (always 0)
 *
 * PDPseudo devices have no state - always returns 0
 */
- (unsigned int)getState
{
    /* Pseudo devices have no state */
    return 0;
}


/*
 * setState:mask: - Set device state with mask
 * state: New state value
 * mask: Bits to modify
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support state setting
 */
- (void)setState:(unsigned int)state mask:(unsigned int)mask
{
    /* Operation not supported - no-op */
    /* Note: Decompiled shows return 0xfffffd42 but signature is void */
}


/*
 * watchState:mask: - Watch for state changes
 * state: Pointer to receive state (output parameter)
 * mask: State bits to watch
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support state watching
 */
- (void)watchState:(unsigned int *)state mask:(unsigned int)mask
{
    /* Operation not supported - no-op */
    /* Note: Decompiled shows return 0xfffffd42 but signature is void */
}


/*
 * nextEvent - Get next pending event
 * Returns: 0 (no events)
 *
 * PDPseudo devices have no events - always returns 0
 */
- (unsigned int)nextEvent
{
    /* No events available */
    return 0;
}


/*
 * executeEvent:data: - Execute immediate event
 * event: Event code
 * data: Event data
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support event execution
 */
- (void)executeEvent:(unsigned int)event data:(unsigned int)data
{
    /* Operation not supported - no-op */
    /* Note: Decompiled shows return 0xfffffd42 but signature is void */
}


/*
 * requestEvent:data: - Request event data
 * event: Event code
 * data: Pointer to receive data (output parameter)
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support event requests
 */
- (void)requestEvent:(unsigned int)event data:(unsigned int *)data
{
    /* Operation not supported - no-op */
    /* Note: Decompiled shows return 0xfffffd42 but signature is void */
}

}

/*
 * enqueueEvent:data:sleep: - Enqueue event with data
 * event: Event code
 * data: Event data
 * sleep: Whether to sleep if queue is full
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support event queueing
 */
- (int)enqueueEvent:(unsigned int)event data:(unsigned int)data sleep:(int)sleep
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
}


/*
 * dequeueEvent:data:sleep: - Dequeue event with data
 * event: Pointer to receive event code (output parameter)
 * data: Pointer to receive event data (output parameter)
 * sleep: Whether to sleep if queue is empty
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support event queueing
 */
- (int)dequeueEvent:(unsigned int *)event data:(unsigned int *)data sleep:(int)sleep
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
}


/*
 * enqueueData:bufferSize:transferCount:sleep: - Enqueue data for transmission
 * buffer: Data buffer
 * bufferSize: Size of data to enqueue
 * transferCount: Pointer to receive actual bytes transferred (output parameter)
 * sleep: Whether to sleep if buffer is full
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support data transfer
 */
- (int)enqueueData:(void *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
             sleep:(int)sleep
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
}


/*
 * dequeueData:bufferSize:transferCount:minCount: - Dequeue received data
 * buffer: Buffer to receive data
 * bufferSize: Maximum buffer size
 * transferCount: Pointer to receive actual bytes transferred (output parameter)
 * minCount: Minimum bytes required before returning
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support data transfer
 */
- (int)dequeueData:(void *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
          minCount:(unsigned int)minCount
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
}


@end
