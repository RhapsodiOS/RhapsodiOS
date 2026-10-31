#ifndef TERMINAL_FILER_OBJC_H
#define TERMINAL_FILER_OBJC_H

#import <Foundation/NSFileHandle.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSTimer.h>

#include "Filer.h"

@interface Filer : NSObject
{
    NSFileHandle *fileHandle;
    NSTimer *output;
    TerminalChunk *outbuff;
    id target;
    unsigned char Peekc;
}

- (id)init;
- (void)close;
- (void)setTarget:(id)value;
- (id)target;
- (void)setFd:(int)fd;
- (int)fd;
- (void)handleFileActivity:(NSNotification *)notification;
- (void)handleOutput:(id)sender;
- (void)output:(const char *)bytes len:(unsigned int)length;
- (void)output:(const char *)string;
- (void)outputChar:(unsigned char)value;

@end

#endif
