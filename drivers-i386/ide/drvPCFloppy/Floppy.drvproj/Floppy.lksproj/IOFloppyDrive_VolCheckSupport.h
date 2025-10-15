/*
 * IOFloppyDrive_VolCheckSupport.h
 * Volume check support methods for IOFloppyDrive
 */

#import "IOFloppyDrive.h"

/*
 * VolCheckSupport category for IOFloppyDrive
 * Provides volume check and validation support
 */
@interface IOFloppyDrive(VolCheckSupport)

// Volume check methods
- (IOReturn)registerVolCheck:(id)check;
- (IOReturn)diskBecameReady;
- (IOReturn)updateReadyState;
- (IOReturn)needsHandlePolling;
- (IOReturn)updateEjectState:(id)state;

@end
