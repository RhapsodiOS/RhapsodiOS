/*
 * PDPseudo.m
 * Pseudo serial device for PortServer driver
 */

#import "PDPseudo.h"

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

    /* Allocate and initialize PDPseudo with device description */
    pseudoDevice = [[PDPseudo alloc] initFromDeviceDescription:deviceDescription];

    if (pseudoDevice == nil) {
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
- initFromDeviceDescription:(id)deviceDescription
{
    id result;

    /* Check if pseudo device has already been loaded */
    if (_PseudoDeviceLoaded == '\0') {
        /* Mark as loaded */
        _PseudoDeviceLoaded = '\x01';

        /* Set device name to "PDPseudo" */
        [self setName:"PDPseudo"];

        /* Set device kind to "Server Device" */
        [self setDeviceKind:"Server Device"];

        result = [super initFromDeviceDescription:deviceDescription];

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
 * sleep: Whether to sleep if the port is busy
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices cannot be acquired - always returns error
 */
- (int)acquire:(BOOL)sleep
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
- (int)release
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
}


/*
 * setState:mask: - Set device state with mask
 * state: New state value
 * mask: Bits to modify
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support state setting
 */
- (int)setState:(unsigned long)state mask:(unsigned long)mask
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
}


/*
 * getState - Get current device state
 * Returns: Current state value (always 0)
 *
 * PDPseudo devices have no state - always returns 0
 */
- (unsigned long)getState
{
    /* Pseudo devices have no state */
    return 0;
}


/*
 * watchState:mask: - Watch for state changes
 * state: Pointer to receive state (output parameter)
 * mask: State bits to watch
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support state watching
 */
- (int)watchState:(unsigned long *)state mask:(unsigned long)mask
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
}


/*
 * nextEvent - Get next pending event
 * Returns: 0 (no events)
 *
 * PDPseudo devices have no events - always returns 0
 */
- (unsigned long)nextEvent
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
- (int)executeEvent:(unsigned long)event data:(unsigned long)data
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
}


/*
 * requestEvent:data: - Request event data
 * event: Event code
 * data: Pointer to receive data (output parameter)
 * Returns: 0xfffffd42 (-702 decimal) - operation not supported
 *
 * PDPseudo devices do not support event requests
 */
- (int)requestEvent:(unsigned long)event data:(unsigned long *)data
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
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
- (int)enqueueEvent:(unsigned long)event data:(unsigned long)data sleep:(BOOL)sleep
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
- (int)dequeueEvent:(unsigned long *)event data:(unsigned long *)data sleep:(BOOL)sleep
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
- (int)enqueueData:(char *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
             sleep:(BOOL)sleep
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
- (int)dequeueData:(char *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
          minCount:(unsigned int)minCount
{
    /* Operation not supported */
    return 0xfffffd42;  /* -702 decimal */
}


@end
