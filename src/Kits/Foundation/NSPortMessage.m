/*	NSPortMessage.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPortMessage.h>
#import <Foundation/NSData.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSZone.h>

#include <mach/message.h>
#include <string.h>

@interface NSMachPort : NSPort
@end

@interface NSData (NSPortMessageVMData)
- (id)initWithBytes:(const void *)bytes length:(unsigned)length
               copy:(BOOL)copy freeWhenDone:(BOOL)freeWhenDone
        bytesAreVM:(BOOL)bytesAreVM;
@end

typedef struct {
    void *data;
    char *cursor;
    char *limit;
    char *start;
    void *functions;
    void *callback;
    unsigned char flags;
    unsigned char isVMData;
} NSPortMessageStream;

typedef struct {
    Class isa;
    id refObject;
    NSPortMessageStream stream;
} NSPortMessageStreamData;

@interface NSPortMessage (NSMachMessageParsing)
+ (void)parseMachMessage:(void *)message localPort:(NSPort **)localPort
               remotePort:(NSPort **)remotePort msgid:(unsigned *)msgid
                   stream:(void *)stream
               components:(NSMutableArray **)components;
@end
@interface NSPortMessage (NSMachMessageSending)
+ (BOOL)sendBeforeTime:(NSTimeInterval)time streamData:(id)streamData
            components:(NSArray *)components to:(NSPort *)sendPort
                  from:(NSPort *)receivePort msgid:(unsigned)msgid
              reserved:(unsigned)reserved;
@end

extern void _NSIncrementInternalRefCount(id object, unsigned *refCount,
                                          int mask, id lock);
extern BOOL _NSDecrementInternalRefCountWasZero(id object, unsigned *refCount,
                                                 int mask, id lock);
extern unsigned _NSInternalRefCount(id object, unsigned refCount, int mask);
extern id _NSGlobalRetainLock;
#import "NSProcessInfoPrivate.h"
extern id _NSNewImmutableData(const void *bytes, unsigned length, NSZone *zone);

unsigned int __NSMsgSendCount;

@implementation NSPortMessage

+ (unsigned)reservedSpaceLength {
    return 36;
}

+ (BOOL)sendBeforeTime:(NSTimeInterval)time streamData:(id)streamData
            components:(NSArray *)components to:(NSPort *)sendPort
                  from:(NSPort *)receivePort msgid:(unsigned)messageID
              reserved:(unsigned)reserved {
    unsigned char storage[MSG_SIZE_MAX];
    msg_header_t *message;
    unsigned char *cursor;
    int remaining;
    unsigned count;
    unsigned index;
    int options = SEND_TIMEOUT | SEND_SWITCH;
    msg_timeout_t timeout = 0;
    long double delay;
    msg_return_t result;

    if (reserved != 0 && components == nil) {
        NSPortMessageStreamData *data = (NSPortMessageStreamData *)streamData;
        NSPortMessageStream *stream = &data->stream;
        unsigned streamLength = (unsigned)(stream->cursor - stream->start);

        if (streamLength <= 0x2000) {
            msg_type_long_t *type;

            message = (msg_header_t *)stream->start;
            message->msg_remote_port = (port_t)[sendPort machPort];
            message->msg_local_port = (port_t)[receivePort machPort];
            message->msg_simple = 1;
            message->msg_type = 0;
            message->msg_id = (int)messageID;
            type = (msg_type_long_t *)((unsigned char *)message +
                                        sizeof(msg_header_t));
            type->msg_type_header.msg_type_name = 0;
            type->msg_type_header.msg_type_size = 0;
            type->msg_type_header.msg_type_number = 0;
            type->msg_type_header.msg_type_inline = 1;
            type->msg_type_header.msg_type_longform = 1;
            type->msg_type_header.msg_type_deallocate = 0;
            type->msg_type_header.msg_type_unused = 0;
            type->msg_type_long_name = MSG_TYPE_BYTE;
            type->msg_type_long_size = 8;
            type->msg_type_long_number = streamLength - 36;
            message->msg_size = (streamLength + 3) & ~3U;
            goto send_message;
        }
    }

    message = (msg_header_t *)storage;
    cursor = storage + sizeof(msg_header_t);
    count = [components count];
    remaining = 8152 - 16 * (int)count;
    if (remaining < 0)
        [NSException raise:NSInvalidArgumentException
                    format:@"too much data for port message"];
    message->msg_simple = 1;
    message->msg_type = 0;
    message->msg_local_port = (port_t)[receivePort machPort];
    message->msg_remote_port = (port_t)[sendPort machPort];
    message->msg_id = (int)messageID;

    index = 0;
    do {
        id object = [components objectAtIndex:index];

        if (object == nil)
            object = streamData;
        if ([object respondsToSelector:@selector(bytes)]) {
            unsigned length = [object length];
            unsigned aligned = (length + 3) & ~3U;
            unsigned char *bytes = (unsigned char *)[object bytes];
            msg_type_long_t *type;

            if (index == 0 && reserved != 0) {
                length -= reserved;
                aligned -= reserved;
                bytes += reserved;
            }
            type = (msg_type_long_t *)cursor;
            type->msg_type_header.msg_type_name = 0;
            type->msg_type_header.msg_type_size = 0;
            type->msg_type_header.msg_type_number = 0;
            type->msg_type_header.msg_type_longform = 1;
            type->msg_type_header.msg_type_deallocate = 0;
            type->msg_type_header.msg_type_unused = 0;
            type->msg_type_long_name = MSG_TYPE_BYTE;
            type->msg_type_long_size = 8;
            type->msg_type_long_number = length;
            if (aligned <= (unsigned)remaining) {
                type->msg_type_header.msg_type_inline = 1;
                memmove(cursor + sizeof(*type), bytes, length);
                cursor += sizeof(*type) + aligned;
                remaining -= (int)aligned;
            } else {
                type->msg_type_header.msg_type_inline = 0;
                memcpy(cursor + sizeof(*type), &bytes, sizeof(bytes));
                cursor += sizeof(*type) + sizeof(bytes);
                message->msg_simple = 0;
            }
        } else if ([object respondsToSelector:@selector(machPort)]) {
            msg_type_t *type;
            unsigned port;

            if (remaining <= 7)
                break;
            message->msg_simple = 0;
            type = (msg_type_t *)cursor;
            type->msg_type_name = MSG_TYPE_PORT;
            type->msg_type_size = 32;
            type->msg_type_number = 1;
            type->msg_type_inline = 1;
            type->msg_type_longform = 0;
            type->msg_type_deallocate = 0;
            type->msg_type_unused = 0;
            port = (unsigned)[object machPort];
            memcpy(cursor + sizeof(*type), &port, sizeof(port));
            cursor += sizeof(*type) + sizeof(port);
        }
        ++index;
    } while (index < [components count]);
    message->msg_size = (unsigned)(cursor - storage);

send_message:
    delay = (long double)time - _NSCurrentTime();
    if (delay >= 0.0L) {
        if (delay > 4294967.295) {
            options = SEND_SWITCH;
        } else {
            long double milliseconds = delay * 1000.0L;

            if (milliseconds >= 2147483648.0L)
                timeout = (msg_timeout_t)
                    ((unsigned)((int)(milliseconds - 2147483648.0L))
                        ^ 0x80000000U);
            else
                timeout = (msg_timeout_t)(unsigned)(int)milliseconds;
        }
    }
    ++__NSMsgSendCount;
    result = msg_send(message, options, timeout);
    if (result == SEND_INVALID_PORT)
        [NSException raise:NSInvalidSendPortException
                    format:@"[NSPortMessage sendBeforeDate:] destination invalid"];
    if (result == SEND_TIMED_OUT)
        return NO;
    if (result != SEND_SUCCESS)
        [NSException raise:NSInvalidArgumentException
                    format:@"[NSPortMessage sendBeforeDate:] Cannot send (%s)",
                           mach_error_string(result)];
    return YES;
}

+ (void)parseMachMessage:(void *)buffer localPort:(NSPort **)localPortOut
               remotePort:(NSPort **)remotePortOut msgid:(unsigned *)msgidOut
                   stream:(void *)streamBuffer
               components:(NSMutableArray **)componentsOut {
    msg_header_t *message = (msg_header_t *)buffer;
    unsigned char *cursor = (unsigned char *)buffer + sizeof(msg_header_t);
    unsigned char *end = (unsigned char *)buffer + message->msg_size;
    NSMutableArray *objects = nil;
    NSPortMessageStream *stream = (NSPortMessageStream *)streamBuffer;

    *msgidOut = (unsigned)message->msg_id;
    *localPortOut = [NSMachPort newWithMachPort:(int)message->msg_local_port];
    *remotePortOut = [NSMachPort newWithMachPort:(int)message->msg_remote_port];
    if (stream != NULL)
        stream->isVMData = 0;

    while (cursor < end) {
        msg_type_t *shortType = (msg_type_t *)cursor;
        unsigned typeName;
        unsigned number;
        BOOL isInline;
        unsigned char *bytes;
        unsigned byteLength;

        if (shortType->msg_type_longform) {
            msg_type_long_t *longType = (msg_type_long_t *)cursor;
            typeName = longType->msg_type_long_name;
            number = longType->msg_type_long_number;
            isInline = longType->msg_type_header.msg_type_inline;
            cursor += sizeof(msg_type_long_t);
        } else {
            typeName = shortType->msg_type_name;
            number = shortType->msg_type_number;
            isInline = shortType->msg_type_inline;
            cursor += sizeof(msg_type_t);
        }

        if (typeName == MSG_TYPE_INTEGER_32) {
            byteLength = number * sizeof(unsigned);
            if (isInline) {
                bytes = cursor;
                cursor += (byteLength + 3) & ~3U;
            } else {
                bytes = *(unsigned char **)cursor;
                cursor += sizeof(bytes);
            }
            {
                NSData *data;

                if (isInline) {
                    data = _NSNewImmutableData(bytes, byteLength, NULL);
                } else {
                    data = [[NSData allocWithZone:NULL]
                        initWithBytes:bytes length:byteLength copy:NO
                        freeWhenDone:YES bytesAreVM:YES];
                }
                if (objects == nil)
                    objects = [[NSMutableArray allocWithZone:NULL] init];
                [objects addObject:data];
                [data release];
            }
        } else if (typeName == MSG_TYPE_PORT) {
            unsigned index;
            unsigned *ports;
            if (isInline) {
                ports = (unsigned *)cursor;
                cursor += number * sizeof(unsigned);
            } else {
                ports = *(unsigned **)cursor;
                cursor += sizeof(ports);
            }
            if (objects == nil)
                objects = [[NSMutableArray allocWithZone:NULL] init];
            for (index = 0; index < number; ++index) {
                NSPort *port = [NSMachPort newWithMachPort:(int)ports[index]];
                [objects addObject:port];
                [port release];
            }
        } else if (typeName == MSG_TYPE_CHAR || typeName == MSG_TYPE_BYTE) {
            byteLength = number;
            if (isInline) {
                bytes = cursor;
                if (stream != NULL) {
                    stream->start = (char *)NSZoneMalloc(NULL, byteLength);
                    stream->cursor = stream->start;
                    stream->limit = stream->start + byteLength;
                    memmove(stream->start, bytes, byteLength);
                    stream->cursor = stream->start;
                } else {
                    NSData *data = _NSNewImmutableData(bytes, byteLength, NULL);
                    if (objects == nil)
                        objects = [[NSMutableArray allocWithZone:NULL] init];
                    [objects addObject:data];
                    [data release];
                }
                cursor += (byteLength + 3) & ~3U;
            } else {
                bytes = *(unsigned char **)cursor;
                cursor += sizeof(bytes);
                if (stream != NULL) {
                    stream->start = (char *)bytes;
                    stream->cursor = stream->start;
                    stream->limit = stream->start + byteLength;
                    stream->isVMData = 1;
                } else {
                    NSData *data = [[NSData allocWithZone:NULL]
                        initWithBytes:bytes length:byteLength copy:NO
                        freeWhenDone:YES bytesAreVM:YES];
                    if (objects == nil)
                        objects = [[NSMutableArray allocWithZone:NULL] init];
                    [objects addObject:data];
                    [data release];
                }
            }
            stream = NULL;
        } else {
            [NSException raise:NSInternalInconsistencyException
                        format:@"unknown message data type: 0x%x", typeName];
        }
    }
    *componentsOut = objects;
}

- (id)initWithSendPort:(NSPort *)sendPort receivePort:(NSPort *)replyPort
            components:(NSArray *)newComponents {
    localPort = [replyPort retain];
    remotePort = [sendPort retain];
    components = [newComponents retain];
    return self;
}

- (id)initWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort
               components:(NSArray *)newComponents {
    return [self initWithSendPort:sendPort receivePort:receivePort
                        components:newComponents];
}

- (id)initWithMachMessage:(void *)buffer {
    [(Class)self->isa parseMachMessage:buffer localPort:&localPort
                            remotePort:&remotePort msgid:&msgid stream:NULL
                            components:&components];
    return self;
}

- (NSArray *)components { return components; }
- (NSPort *)receivePort { return localPort; }
- (NSPort *)sendPort { return remotePort; }
- (unsigned)msgid { return msgid; }
- (void)setMsgid:(unsigned)newMsgid { msgid = newMsgid; }

- (BOOL)sendBeforeDate:(NSDate *)date {
    return [(Class)self->isa sendBeforeTime:[date timeIntervalSinceReferenceDate]
                                 streamData:nil components:components to:remotePort
                                       from:localPort msgid:msgid reserved:0];
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [self retain];
}

- (id)retain {
    _NSIncrementInternalRefCount(self, &refCount, -1, _NSGlobalRetainLock);
    return self;
}

- (oneway void)release {
    if (_NSDecrementInternalRefCountWasZero(self, &refCount, -1,
                                             _NSGlobalRetainLock))
        [self dealloc];
}

- (unsigned)retainCount {
    return _NSInternalRefCount(self, refCount, -1);
}

- (void)dealloc {
    [remotePort release];
    [localPort release];
    [components release];
    [super dealloc];
}

@end
