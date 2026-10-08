#import "FilerObjC.h"

#import <AppKit/NSApplication.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSString.h>

#include <stdlib.h>
#include <string.h>

@implementation Filer

- (id)init
{
    [super init];

    fileHandle = nil;
    output = nil;
    outbuff = filerBufferCreateInZone([self zone]);
    target = nil;
    return self;
}

- (void)close
{
    if (fileHandle != nil) {
        [fileHandle closeFile];
        [[NSNotificationCenter defaultCenter] removeObserver:self
            name:NSFileHandleDataAvailableNotification object:fileHandle];
        [fileHandle release];
        fileHandle = nil;
    }

    filerBufferClear(outbuff);
    if (output != nil) {
        [output invalidate];
        [output release];
    }
}

- (void)dealloc
{
    [self close];
    free(outbuff);
    [super dealloc];
}

- (void)setTarget:(id)value
{
    target = value;
}

- (id)target
{
    return target;
}

- (void)setFd:(int)fd
{
    if (fd < 0)
        return;

    if (fileHandle != nil) {
        [fileHandle closeFile];
        [[NSNotificationCenter defaultCenter] removeObserver:self
            name:NSFileHandleDataAvailableNotification object:fileHandle];
        [fileHandle release];
    }

    fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:fd];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(handleFileActivity:)
        name:NSFileHandleDataAvailableNotification object:fileHandle];
    [fileHandle readInBackgroundAndNotify];
}

- (int)fd
{
    return (int)[fileHandle fileDescriptor];
}

- (void)handleFileActivity:(NSNotification *)notification
{
    NSFileHandle *handle = [notification object];
    NSDictionary *info = [notification userInfo];
    NSData *data = [info objectForKey:NSFileHandleNotificationDataItem];

    if (data != nil) {
        [target outputdata:(const char *)[data bytes] len:(unsigned int)[data length]];
        [handle readInBackgroundAndNotify];
    }
}

- (void)handleOutput:(id)sender
{
    int result;
    unsigned int i;

    (void)sender;

    for (i = 0; i < outbuff->count; ++i) {
        if (outbuff->elements[i] == '\n') {
            [target scheduleUpdate];
            break;
        }
    }

    result = tryOutput(outbuff, [self fd]);
    if (result != 0)
        [target endOfFileOn:self];

    if (outbuff->count != 0) {
        if (output == nil) {
            /* IDA's PPC literal at 0x346c8 is the 0.1-second retry interval. */
            output = [[NSTimer timerWithTimeInterval:0.1 target:self
                selector:@selector(handleOutput:) userInfo:self repeats:YES] retain];
            [[NSRunLoop currentRunLoop] addTimer:output forMode:NSDefaultRunLoopMode];
            [[NSRunLoop currentRunLoop] addTimer:output forMode:NSEventTrackingRunLoopMode];
            [[NSRunLoop currentRunLoop] addTimer:output forMode:NSModalPanelRunLoopMode];
        }
    } else if (output != nil) {
        [output invalidate];
        [output release];
        output = nil;
    }
}

- (void)output:(const char *)bytes len:(unsigned int)length
{
    outbuff = filerBufferAppend(outbuff, bytes, length);
    [self handleOutput:nil];
}

- (void)output:(const char *)string
{
    [self output:string len:(unsigned int)strlen(string)];
}

- (void)outputChar:(unsigned char)value
{
    [self output:(const char *)&value len:1];
}

@end
