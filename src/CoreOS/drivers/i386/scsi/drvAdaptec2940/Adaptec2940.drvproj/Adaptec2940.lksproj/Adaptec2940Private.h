/* Copyright (c) 1999 Apple Computer, Inc. */

#ifndef _ADAPTEC2940PRIVATE_H
#define _ADAPTEC2940PRIVATE_H

#include "Adaptec2940Types.h"

#define AIC_QUEUE_SIZE 16
#define AIC_NUM_SCBS 16
#define AIC_RESET_TIMEOUT_MS 5000
#define AIC_CMD_TIMEOUT_MS 30000

#ifdef __OBJC__

#import "Adaptec2940.h"

@interface Adaptec2940(Private)
- (char)checkScbAlign:(Adaptec2940SCB *)scb;
- (Adaptec2940SCB *)allocScb;
- (void)freeScb:(Adaptec2940SCB *)scb;
- (void)createScbs:(unsigned int)base size:(unsigned int)size;
- (void)threadExecuteRequest:(Adaptec2940RequestMessage *)message;
- (void)threadResetBus:(Adaptec2940RequestMessage *)message
              channel:(unsigned int)channel
               reason:(const char *)reason;
- (void)commandCompleted:(Adaptec2940SCB *)scb;
- (void)scbComplete:(Adaptec2940SCB *)scb;
- (IOReturn)startIOThread;
- (IOReturn)enableAllInterrupts;
- (id)deviceDescription;
- (port_t)interruptPort;
@end

@interface Adaptec2940(IOThread)
- (void)interruptOccurred;
- (void)interruptOccurredAt:(int)localNum;
- (void)otherOccurred:(int)event;
- (void)receiveMsg;
- (void)timeoutOccurred;
- (void)commandRequestOccurred;
@end

#endif /* __OBJC__ */

#endif /* _ADAPTEC2940PRIVATE_H */
