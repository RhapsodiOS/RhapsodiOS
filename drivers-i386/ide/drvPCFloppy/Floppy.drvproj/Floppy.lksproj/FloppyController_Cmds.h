/*
 * FloppyController_Cmds.h
 * FDC command methods for FloppyController
 */

#import "FloppyController.h"

/*
 * FDC Commands category for FloppyController
 * Contains low-level FDC command operations
 */
@interface FloppyController(Cmds)

// Basic FDC command operations
- (IOReturn)fdcSendCommand:(unsigned char *)cmd length:(unsigned int)len;
- (IOReturn)fdcGetResult:(unsigned char *)result length:(unsigned int)len;
- (IOReturn)fdcSendByte:(unsigned char)byte;
- (IOReturn)fdcGetByte:(unsigned char *)byte;

// FDC status operations
- (IOReturn)fdcWaitReady;
- (IOReturn)fdcCheckStatus;
- (unsigned char)fdcReadStatus;

// Specific FDC commands
- (IOReturn)fdcSpecify;
- (IOReturn)fdcConfigure;
- (IOReturn)fdcVersion:(unsigned char *)version;
- (IOReturn)fdcLock;
- (IOReturn)fdcUnlock;

@end
