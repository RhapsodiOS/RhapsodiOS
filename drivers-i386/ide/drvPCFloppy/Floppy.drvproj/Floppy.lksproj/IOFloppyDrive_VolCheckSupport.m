/*
 * IOFloppyDrive_VolCheckSupport.m
 * Volume check support method implementations for IOFloppyDrive
 */

#import "IOFloppyDrive_VolCheckSupport.h"
#import "FloppyController.h"
#import <driverkit/generalFuncs.h>

@implementation IOFloppyDrive(VolCheckSupport)

- (IOReturn)registerVolCheck:(id)check
{
    if (check == nil) {
        IOLog("IOFloppyDrive(VolCheck): NULL volume check object\n");
        return IO_R_INVALID_ARG;
    }

    [_lock lock];

    if (_volCheck != nil) {
        IOLog("IOFloppyDrive(VolCheck): Volume check already registered, replacing\n");
        [_volCheck release];
    }

    _volCheck = [check retain];

    [_lock unlock];

    IOLog("IOFloppyDrive(VolCheck): Registered volume check %p\n", check);
    return IO_R_SUCCESS;
}

- (IOReturn)diskBecameReady
{
    IODiskReadyState previousState;
    BOOL notify = NO;

    IOLog("IOFloppyDrive(VolCheck): Disk became ready on unit %d\n", _unit);

    [_lock lock];

    previousState = [self lastReadyState];

    // Update ready state using IODisk method
    [self setLastReadyState:IO_Ready];
    _diskChanged = NO;

    // Check if state actually changed
    if (previousState != IO_Ready) {
        notify = YES;
        IOLog("IOFloppyDrive(VolCheck): State changed from %d to Ready\n", previousState);
    }

    [_lock unlock];

    // Notify volume checker if registered and state changed
    if (notify && _volCheck != nil) {
        if ([_volCheck respondsToSelector:@selector(diskBecameReady:)]) {
            [_volCheck performSelector:@selector(diskBecameReady:) withObject:self];
            IOLog("IOFloppyDrive(VolCheck): Notified volume checker of ready state\n");
        }
    }

    return IO_R_SUCCESS;
}

- (IOReturn)updateReadyState
{
    IODiskReadyState newState;
    IODiskReadyState previousState;
    BOOL hasMedia;
    BOOL notify = NO;

    [_lock lock];

    previousState = [self lastReadyState];

    [_lock unlock];

    // Check media presence via controller
    if (_controller != nil) {
        unsigned char status = 0;
        IOReturn result = [_controller doSenseInterrupt:_unit status:&status];

        if (result == IO_R_SUCCESS) {
            // Check if media is present (bit 5 of status register)
            hasMedia = ((status & 0x20) == 0);  // Bit 5 clear = media present
        } else {
            // If sense fails, assume no media
            hasMedia = NO;
            IOLog("IOFloppyDrive(VolCheck): Sense interrupt failed, assuming no media\n");
        }
    } else {
        // No controller, can't determine state
        hasMedia = NO;
        IOLog("IOFloppyDrive(VolCheck): No controller, assuming no media\n");
    }

    // Determine new ready state
    if (hasMedia) {
        newState = IO_Ready;
    } else {
        newState = IO_NotReady;
    }

    [_lock lock];

    // Update state using IODisk method
    [self setLastReadyState:newState];

    // Check if state changed
    if (newState != previousState) {
        notify = YES;
        IOLog("IOFloppyDrive(VolCheck): Ready state changed from %d to %d\n",
              previousState, newState);

        // If transitioning from Ready to NotReady, mark disk as changed
        if (previousState == IO_Ready && newState == IO_NotReady) {
            _diskChanged = YES;
            IOLog("IOFloppyDrive(VolCheck): Disk was removed\n");
        }
        // If transitioning from NotReady to Ready, clear disk changed flag
        else if (previousState == IO_NotReady && newState == IO_Ready) {
            _diskChanged = NO;
            IOLog("IOFloppyDrive(VolCheck): New disk inserted\n");
        }
    }

    [_lock unlock];

    // Notify volume checker if state changed
    if (notify && _volCheck != nil) {
        if (newState == IO_Ready) {
            if ([_volCheck respondsToSelector:@selector(diskBecameReady:)]) {
                [_volCheck performSelector:@selector(diskBecameReady:) withObject:self];
            }
        } else {
            if ([_volCheck respondsToSelector:@selector(diskBecameUnready:)]) {
                [_volCheck performSelector:@selector(diskBecameUnready:) withObject:self];
            }
        }
    }

    IOLog("IOFloppyDrive(VolCheck): Ready state = %d (ready:%d changed:%d)\n",
          newState, ([self lastReadyState] == IO_Ready), _diskChanged);

    return newState;
}

- (IOReturn)needsHandlePolling
{
    BOOL needsPolling;

    [_lock lock];

    // Floppy drives need polling if:
    // 1. They don't support disk change interrupts, OR
    // 2. We need to periodically check for disk changes

    // For PC floppies, we typically need to poll the disk change line
    needsPolling = YES;

    [_lock unlock];

    IOLog("IOFloppyDrive(VolCheck): Needs polling = %d\n", needsPolling);

    return needsPolling ? IO_R_SUCCESS : IO_R_UNSUPPORTED;
}

- (IOReturn)updateEjectState:(id)state
{
    BOOL isEjecting;

    if (state == nil) {
        IOLog("IOFloppyDrive(VolCheck): NULL eject state object\n");
        return IO_R_INVALID_ARG;
    }

    [_lock lock];

    // Check if we're in the process of ejecting
    isEjecting = ([self lastReadyState] != IO_Ready) && _diskChanged;

    // Update the state object (assuming it responds to setEjecting:)
    if ([state respondsToSelector:@selector(setEjecting:)]) {
        [state performSelector:@selector(setEjecting:) withObject:(id)(isEjecting ? (void *)1 : (void *)0)];
        IOLog("IOFloppyDrive(VolCheck): Updated eject state to %d\n", isEjecting);
    } else if ([state respondsToSelector:@selector(setObject:forKey:)]) {
        // Try dictionary-style setting
        [state performSelector:@selector(setObject:forKey:)
                    withObject:(isEjecting ? @"YES" : @"NO")
                    withObject:@"isEjecting"];
        IOLog("IOFloppyDrive(VolCheck): Updated eject state dictionary\n");
    } else {
        IOLog("IOFloppyDrive(VolCheck): State object doesn't respond to known setters\n");
    }

    [_lock unlock];

    IOLog("IOFloppyDrive(VolCheck): Eject state = %d (ready:%d changed:%d)\n",
          isEjecting, ([self lastReadyState] == IO_Ready), _diskChanged);

    return IO_R_SUCCESS;
}

@end
