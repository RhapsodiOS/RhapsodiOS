/*	NSPortCoder.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPortCoder.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSData.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSException.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSPortMessage.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>

#include <string.h>

extern void _NSGenericFree(void *ptr);

extern unsigned _NSWalkData(int operation, BOOL walkPointers, void *context,
                            void *value, const char *type);

typedef struct {
    void *data;
    char *cursor;
    char *limit;
    char *start;
    void *functions;
    void *callback;
    unsigned char flags;
    unsigned char isVMData;
} NSPortCoderStream;

typedef char *(*NSPortCoderWriteByteFunction)(NSPortCoderStream *, unsigned char);
#if defined(__ppc__) || defined(__POWERPC__)
typedef char *(*NSPortCoderWriteFastIntFunction)(NSPortCoderStream *,
                                                  const void *, unsigned);
#else
typedef int (*NSPortCoderWriteFastIntFunction)(NSPortCoderStream *,
                                               const void *, unsigned);
#endif
typedef void *(*NSPortCoderWriteCStringFunction)(NSPortCoderStream *, const char *);
typedef void *(*NSPortCoderWriteDataFunction)(NSPortCoderStream *,
                                               const void *, unsigned);

typedef struct {
    NSPortCoderWriteByteFunction writeByte;
    NSPortCoderWriteFastIntFunction writeFastInt;
    NSPortCoderWriteCStringFunction writeCString;
    NSPortCoderWriteDataFunction writeData;
} NSPortCoderStreamFunctions;

typedef struct {
    Class isa;
    Class superClass;
    const char *name;
    int version;
    unsigned info;
} NSPortCoderClassLayout;

static void NSPortCoderEnsureCapacity(NSPortCoderStream *stream, unsigned extra) {
    unsigned used = (unsigned)(stream->cursor - stream->start);
    unsigned capacity = (unsigned)(stream->limit - stream->start);
    unsigned required = used + extra;

    if (required >= capacity) {
        unsigned newCapacity = required * 2;
        char *bytes = (char *)NSZoneRealloc(NSZoneFromPointer(stream->start),
                                             stream->start, newCapacity);
        stream->start = bytes;
        stream->cursor = bytes + used;
        stream->limit = bytes + newCapacity;
    }
}

static void NSPortCoderRaiseTruncatedStream(void) {
    [NSException raise:NSInvalidArgumentException
                format:@"NSPortCoder received a truncated stream"];
}

static char *NSPortCoderEncodeFastByte(NSPortCoderStream *stream,
                                       unsigned char value) {
    char *destination;
#if defined(__ppc__) || defined(__POWERPC__)
    int grew = (unsigned)(stream->cursor - stream->start) + 1
        >= (unsigned)(stream->limit - stream->start);
#endif

    NSPortCoderEnsureCapacity(stream, 1);
    destination = stream->cursor;
    *stream->cursor++ = value;
#if defined(__ppc__) || defined(__POWERPC__)
    return grew ? destination : (char *)stream;
#else
    return destination;
#endif
}

static unsigned char NSPortCoderReadMarker(NSPortCoderStream *stream) {
    if (stream->cursor > stream->limit)
        NSPortCoderRaiseTruncatedStream();
    return (unsigned char)*stream->cursor++;
}

static void *NSPortCoderEncodeFastData(NSPortCoderStream *stream,
                                       const void *bytes, unsigned length) {
    void *destination;

    NSPortCoderEnsureCapacity(stream, length);
    destination = stream->cursor;
    if (length != 0)
        destination = memmove(stream->cursor, bytes, length);
    stream->cursor += length;
    return destination;
}

static void NSPortCoderReadBytes(NSPortCoderStream *stream, void *bytes,
                                 unsigned length) {
    if ((unsigned)(stream->limit - stream->cursor) < length)
        NSPortCoderRaiseTruncatedStream();
    if (length != 0)
        memmove(bytes, stream->cursor, length);
    stream->cursor += length;
}

#if defined(__ppc__) || defined(__POWERPC__)
static char *NSPortCoderEncodeFastInt(NSPortCoderStream *stream, const void *value,
                                      unsigned size) {
    char *result = (char *)stream;
    int grew = (unsigned)(stream->cursor - stream->start) + size
        >= (unsigned)(stream->limit - stream->start);
#else
static int NSPortCoderEncodeFastInt(NSPortCoderStream *stream, const void *value,
                                    unsigned size) {
#endif
    const unsigned char *source = (const unsigned char *)value;
    unsigned length = size;
    unsigned char marker;

    NSPortCoderEnsureCapacity(stream, size);
#if defined(__ppc__) || defined(__POWERPC__)
    {
        unsigned i;
        for (i = 0; i < size; ++i)
            stream->cursor[1 + i] = source[size - i - 1];
        if (source[0] == 0) {
            while (length > 0 && source[size - length] == 0)
                --length;
            marker = (unsigned char)length;
        } else if (source[0] == 0xff) {
            length = size - 1;
            while (length > 1 && (unsigned char)stream->cursor[length] == 0xff)
                --length;
            marker = (unsigned char)(-(int)length);
        } else {
            marker = (unsigned char)length;
        }
    }
#else
    memmove(stream->cursor + 1, source, size);
    if (source[size - 1] == 0) {
        while (length > 0 && source[length - 1] == 0)
            --length;
        marker = (unsigned char)length;
    } else if (source[size - 1] == 0xff) {
        while (length > 1 && source[length - 1] == 0xff)
            --length;
        marker = (unsigned char)(-(int)length);
    } else {
        marker = (unsigned char)length;
    }
#endif
    *stream->cursor = marker;
    stream->cursor += length + 1;
#if defined(__ppc__) || defined(__POWERPC__)
    return grew ? stream->cursor - (length + 1) : result;
#else
    return (int)(length + 1);
#endif
}

static void *NSPortCoderEncodeFastCString(NSPortCoderStream *stream,
                                           const char *string) {
    unsigned length = string != NULL ? (unsigned)strlen(string) + 1 : 0;
    void *result;

    result = ((NSPortCoderStreamFunctions *)stream->functions)->writeByte(
        stream, string != NULL);
    if (string != NULL) {
        ((NSPortCoderStreamFunctions *)stream->functions)->writeFastInt(
            stream, &length, sizeof(length));
        return ((NSPortCoderStreamFunctions *)stream->functions)->writeData(
            stream, string, length);
    }
    return result;
}

NSPortCoderStreamFunctions _NSFastFuncList = {
    NSPortCoderEncodeFastByte,
    NSPortCoderEncodeFastInt,
    NSPortCoderEncodeFastCString,
    NSPortCoderEncodeFastData
};

static void NSPortCoderWriteMarker(NSPortCoderStream *stream, unsigned char value) {
    ((NSPortCoderStreamFunctions *)stream->functions)->writeByte(stream, value);
}

static void NSPortCoderWriteBytes(NSPortCoderStream *stream, const void *bytes,
                                  unsigned length) {
    ((NSPortCoderStreamFunctions *)stream->functions)->writeData(stream, bytes,
                                                                 length);
}

static void NSPortCoderWriteFastInt(NSPortCoderStream *stream, const void *value,
                                    unsigned size) {
    ((NSPortCoderStreamFunctions *)stream->functions)->writeFastInt(stream, value,
                                                                    size);
}

static void NSPortCoderReadFastInt(NSPortCoderStream *stream, void *value,
                                   unsigned size) {
    signed char marker;
    unsigned length;
    unsigned char fill;
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned i;
#endif

    if ((unsigned)(stream->limit - stream->cursor) < 1)
        NSPortCoderRaiseTruncatedStream();
    marker = (signed char)NSPortCoderReadMarker(stream);
    length = marker < 0 ? (unsigned)(-marker) : (unsigned)marker;
    fill = marker < 0 ? 0xff : 0;

    if (length > size
        || (unsigned)(stream->limit - stream->cursor) < length)
        NSPortCoderRaiseTruncatedStream();
    memset(value, fill, size);
#if defined(__ppc__) || defined(__POWERPC__)
    for (i = 0; i < length; ++i) {
        unsigned char byte;
        NSPortCoderReadBytes(stream, &byte, 1);
        ((unsigned char *)value)[size - i - 1] = byte;
    }
#else
    NSPortCoderReadBytes(stream, value, length);
#endif
}

static void NSPortCoderWriteCString(NSPortCoderStream *stream, const char *string) {
    ((NSPortCoderStreamFunctions *)stream->functions)->writeCString(stream,
                                                                    string);
}

static const char *NSPortCoderReadCString(NSPortCoderStream *stream) {
    unsigned length;
    const char *string;

    if (NSPortCoderReadMarker(stream) == 0)
        return NULL;
    NSPortCoderReadFastInt(stream, &length, sizeof(length));
    if (length == 0 || (unsigned)(stream->limit - stream->cursor) < length)
        NSPortCoderRaiseTruncatedStream();
    string = stream->cursor;
    stream->cursor += length;
    return string;
}

static const void *NSPortCoderReadData(NSPortCoderStream *stream, unsigned length) {
    const void *bytes;

    if ((unsigned)(stream->limit - stream->cursor) < length)
        NSPortCoderRaiseTruncatedStream();
    bytes = stream->cursor;
    stream->cursor += length;
    return bytes;
}

static void NSPortCoderReadFastIntCallback(NSPortCoderStream *stream,
                                            void *value, unsigned size) {
    NSPortCoderReadFastInt(stream, value, size);
}

@interface NSStreamData : NSMutableData {
    id refObject;
    NSPortCoderStream stream;
}
- (unsigned)length;
- (const void *)bytes;
- (void *)mutableBytes;
@end

@interface NSConcretePortCoder : NSPortCoder {
    NSConnection *connection;
    struct {
        Class isa;
        id refObject;
        NSPortCoderStream stream;
    } streamData;
    NSMutableArray *components;
    NSMutableArray *importedObjects;
    unsigned componentIndex;
    unsigned msgid;
    char isBycopy;
    char isByref;
    char isValid;
    char unused;
}
+ (NSDate *)limitDateForMode:(NSString *)mode;
- (id)initWithConnection:(NSConnection *)connection components:(NSArray *)components
                   msgid:(unsigned)msgid;
- (id)initWithConnection:(NSConnection *)connection msgid:(unsigned)msgid;
- (id)initWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort
               components:(NSArray *)components;
- (id)initWithMachMessage:(void *)message;
+ (void)handleMachMessage:(void *)message;
+ (id)portCoderWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort
                    components:(NSArray *)components;
- (void)invalidate;
- (void)encodeBytes:(const void *)bytes length:(unsigned)length;
- (void *)decodeBytesWithReturnedLength:(unsigned *)length;
- (void)encodeDataObject:(NSData *)data;
- (NSData *)decodeDataObject;
- (void)encodeValueOfObjCType:(const char *)type at:(const void *)address;
- (void)decodeValueOfObjCType:(const char *)type at:(void *)address;
- (void)encodeObject:(id)object isBycopy:(BOOL)bycopy isByref:(BOOL)byref;
- (id)decodeRetainedObject;
- (void)importObject:(id)object;
- (void)sendBeforeTime:(NSTimeInterval)time;
- (void)decryptWithDelegate:(id)delegate;
- (void)encryptWithDelegate:(id)delegate;
- (void)authenticateWithDelegate:(id)delegate;
- (BOOL)verifyWithDelegate:(id)delegate;
@end

@interface NSConnection (NSPortCoderClassInfo)
- (void)addClassNamed:(const char *)name version:(int)version;
- (unsigned)versionForClassNamed:(NSString *)className;
+ (void)doQueuedWork;
@end

@interface NSPort (NSConcretePortCoderTransport)
- (BOOL)sendBeforeTime:(NSTimeInterval)time streamData:(id)data
            components:(NSArray *)components from:(NSPort *)receivePort
                 msgid:(unsigned)msgid;
@end

@interface NSDistantObject (NSPortCoderDecoding)
+ (id)newDistantObjectWithCoder:(NSPortCoder *)coder;
@end

@interface NSObject (NSPortCoderAuthentication)
- (void)decryptComponents:(NSArray *)components;
- (void)encryptComponents:(NSArray *)components;
- (NSData *)authenticationDataForComponents:(NSArray *)components;
- (BOOL)authenticateComponents:(NSArray *)components withData:(NSData *)data;
@end

@interface NSInvocation (NSPortCoderDecoding)
+ (id)newInvocationWithCoder:(NSCoder *)coder;
@end

@interface NSPortMessage (NSConcretePortCoderParsing)
+ (void)parseMachMessage:(void *)message localPort:(NSPort **)localPort
               remotePort:(NSPort **)remotePort msgid:(unsigned *)msgid
                   stream:(void *)stream components:(NSMutableArray **)components;
@end

static NSDate *NSPortCoderDistantFuture;
NSLock *_NSPortCoderCacheLock;
static id NSPortCoderCache;
static id NSPortCoderCache1;
static id NSPortCoderCache2;
static id NSPortCoderCache3;
static int NSPortCoderLoggingEnabled;

@implementation NSPortCoder

- (BOOL)isBycopy {
    return (BOOL)NSRequestConcreteImplementation(self, _cmd, [NSPortCoder class]);
}

- (BOOL)isByref {
    return (BOOL)NSRequestConcreteImplementation(self, _cmd, [NSPortCoder class]);
}

- (NSConnection *)connection {
    return (NSConnection *)NSRequestConcreteImplementation(self, _cmd,
        [NSPortCoder class]);
}

- (void)encodePortObject:(NSPort *)aport {
    (void)aport;
    NSRequestConcreteImplementation(self, _cmd, [NSPortCoder class]);
}

- (NSPort *)decodePortObject {
    return (NSPort *)NSRequestConcreteImplementation(self, _cmd,
        [NSPortCoder class]);
}

+ portCoderWithReceivePort:(NSPort *)rcvPort sendPort:(NSPort *)sndPort components:(NSArray *)comps {
    return [NSConcretePortCoder portCoderWithReceivePort:rcvPort
        sendPort:sndPort components:comps];
}

- (void)dispatch {
    NSRequestConcreteImplementation(self, _cmd, [NSPortCoder class]);
}

@end

@implementation NSStreamData

- (unsigned)length {
    return (unsigned)(stream.cursor - stream.start);
}

- (const void *)bytes {
    return stream.start;
}

- (void *)mutableBytes {
    return stream.start;
}

- (id)retain {
    [refObject retain];
    return self;
}

- (oneway void)release {
    [refObject release];
}

- (unsigned)retainCount {
    return [refObject retainCount];
}

- (void)dealloc {
    [NSException raise:NSInternalInconsistencyException
                format:@"NSStreamData can't dealloc"];
}

@end

@implementation NSConcretePortCoder

+ (void)_enableLogging:(BOOL)flag {
    if (flag)
        ++NSPortCoderLoggingEnabled;
    else
        --NSPortCoderLoggingEnabled;
}

#if defined(__ppc__) || defined(__POWERPC__)
- (id)debugDescription {
    NSConcretePortCoder *coder = self;
#else
+ (id)debugDescription {
    NSConcretePortCoder *coder = (NSConcretePortCoder *)self;
#endif

    return [NSString stringWithFormat:
        @"conn: %@; comps: %@; imported: %@; compIdx = %d; msgid = 0x%x; bycopy = %d; byref = %d; isvalid = %d;\n",
        coder->connection, coder->components, coder->importedObjects,
        coder->componentIndex, coder->msgid, coder->isBycopy,
        coder->isByref, coder->isValid];
}

+ (id)allocWithZone:(NSZone *)zone {
    id coder = nil;

    (void)zone;
    if (_NSPortCoderCacheLock != nil)
        [_NSPortCoderCacheLock lock];
    if (NSPortCoderCache != nil) {
        coder = NSPortCoderCache;
        NSPortCoderCache = nil;
    } else if (NSPortCoderCache1 != nil) {
        coder = NSPortCoderCache1;
        NSPortCoderCache1 = nil;
    } else if (NSPortCoderCache2 != nil) {
        coder = NSPortCoderCache2;
        NSPortCoderCache2 = nil;
    } else if (NSPortCoderCache3 != nil) {
        coder = NSPortCoderCache3;
        NSPortCoderCache3 = nil;
    }
    if (_NSPortCoderCacheLock != nil)
        [_NSPortCoderCacheLock unlock];
    if (coder == nil)
        return NSAllocateObject(self, 0, NULL);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectAllocatedEvent, coder, 0);
    return coder;
}

+ (NSDate *)limitDateForMode:(NSString *)mode {
    (void)mode;
    if (NSPortCoderDistantFuture == nil)
        NSPortCoderDistantFuture = [NSDate distantFuture];
    [NSConnection doQueuedWork];
    return NSPortCoderDistantFuture;
}

+ (void)handleMachMessage:(void *)message {
    NSConcretePortCoder *coder = [[self allocWithZone:NULL]
        initWithMachMessage:message];

    if (coder != nil) {
        [coder dispatch];
        [coder release];
    }
}

+ (id)portCoderWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort
                    components:(NSArray *)objects {
    NSMutableArray *mutableComponents = [objects mutableCopyWithZone:NULL];
    NSConcretePortCoder *coder = [[self allocWithZone:NULL]
        initWithReceivePort:receivePort sendPort:sendPort
                 components:mutableComponents];

    [mutableComponents release];
    return [coder autorelease];
}

- (id)initWithConnection:(NSConnection *)newConnection components:(NSArray *)newComponents
                   msgid:(unsigned)newMsgid {
    if (newConnection == nil) {
        [super dealloc];
        return nil;
    }
    isValid = YES;
    connection = [newConnection retain];
    if (components != nil)
        [components addObjectsFromArray:newComponents];
    else
        components = [newComponents retain];
    componentIndex = 1;
    msgid = newMsgid;
    isBycopy = NO;
    isByref = NO;
    streamData.isa = [NSStreamData class];
    streamData.stream.data = NULL;
    streamData.stream.functions = &_NSFastFuncList;
    streamData.stream.flags = 1;
    streamData.stream.callback = self;
    return self;
}

- (id)initWithConnection:(NSConnection *)newConnection msgid:(unsigned)newMsgid {
    NSPort *sendPort;
    unsigned reservedSpaceLength;
    unsigned capacity;
    char *buffer;

    self = [self initWithConnection:newConnection components:nil msgid:newMsgid];
    sendPort = [newConnection sendPort];
    reservedSpaceLength = [sendPort reservedSpaceLength];
    capacity = reservedSpaceLength + 98;
    buffer = (char *)NSZoneMalloc(NULL, capacity);
    streamData.refObject = self;
    streamData.stream.start = buffer;
    streamData.stream.cursor = buffer + reservedSpaceLength;
    streamData.stream.limit = buffer + capacity;
    streamData.stream.isVMData = 0;
    return self;
}

- (id)initWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort
               components:(NSArray *)newComponents {
    NSConnection *newConnection = [NSConnection
        connectionWithReceivePort:receivePort sendPort:sendPort];

    self = [self initWithConnection:newConnection components:newComponents msgid:0];
    NSStreamData *input = [newComponents objectAtIndex:0];
    streamData.refObject = input;
    streamData.stream.start = (char *)[input bytes];
    streamData.stream.cursor = streamData.stream.start;
    streamData.stream.limit = streamData.stream.start + [input length];
    streamData.stream.isVMData = 0;
    return self;
}

- (id)initWithMachMessage:(void *)message {
    NSPort *receivePort;
    NSPort *sendPort;
    NSMutableArray *incomingComponents = nil;
    unsigned incomingMsgid;
    NSConnection *newConnection;

    [NSPortMessage parseMachMessage:message localPort:&receivePort
                         remotePort:&sendPort msgid:&incomingMsgid
                             stream:&streamData.stream
                         components:&incomingComponents];
    if (NSPortCoderLoggingEnabled != 0)
        NSLog(@"initWithMachMessage on port %d, %d components",
              [receivePort machPort], [incomingComponents count]);
    newConnection = [NSConnection connectionWithReceivePort:receivePort
                                                  sendPort:sendPort];
    self = [self initWithConnection:newConnection components:incomingComponents
                               msgid:incomingMsgid];
#if defined(__ppc__) || defined(__POWERPC__)
    [incomingComponents release];
#endif
    streamData.refObject = self;
    if (components != nil)
        [components insertObject:&streamData atIndex:0];
    [receivePort release];
    [sendPort release];
    return self;
}

- (void)dispatch {
    NS_DURING
        [connection handlePortCoder:self];
    NS_HANDLER
        if (NSPortCoderLoggingEnabled != 0)
            NSLog(@"[NSPortCoder] exception ignored:'%@'", localException);
        [self invalidate];
    NS_ENDHANDLER
}

- (void)decryptWithDelegate:(id)delegate {
    char *cursor = streamData.stream.cursor;

    streamData.stream.cursor = streamData.stream.limit;
    [delegate decryptComponents:[self components]];
    streamData.stream.cursor = cursor;
}

- (void)encryptWithDelegate:(id)delegate {
    unsigned reserved = [[connection sendPort] reservedSpaceLength];

    streamData.stream.start += reserved;
    [delegate encryptComponents:[self components]];
    streamData.stream.start -= reserved;
}

- (void)authenticateWithDelegate:(id)delegate {
    unsigned reserved = [[connection sendPort] reservedSpaceLength];
    NSData *authenticationData;

    streamData.stream.start += reserved;
    authenticationData = [delegate authenticationDataForComponents:[self components]];
    streamData.stream.start -= reserved;
    if (authenticationData == nil)
        [NSException raise:NSInvalidArgumentException
                    format:@"NSPortCoder delegate did not provide authentication data"];
    [components addObject:authenticationData];
}

- (BOOL)verifyWithDelegate:(id)delegate {
    id authenticationData;
    NSArray *authenticatedComponents;

    if (componentIndex >= [components count])
        return NO;
    authenticationData = [components objectAtIndex:componentIndex];
    authenticatedComponents = [components subarrayWithRange:
        NSMakeRange(0, componentIndex)];
    ++componentIndex;
    return [delegate authenticateComponents:authenticatedComponents
                                    withData:authenticationData];
}

- (BOOL)isBycopy { return isBycopy; }
- (BOOL)isByref { return isByref; }
- (NSConnection *)connection { return connection; }

- (void)encodePortObject:(NSPort *)port {
    [[self components] addObject:port];
}

- (NSPort *)decodePortObject {
    return [components objectAtIndex:componentIndex++];
}

- (NSArray *)components {
    if (components == nil)
        components = [[NSMutableArray allocWithZone:NULL] init];
    if ([components count] == 0)
        [components addObject:&streamData];
    return components;
}
- (NSArray *)importedObjects { return importedObjects; }

- (void)encodeBytes:(const void *)bytes length:(unsigned)length {
    NSPortCoderWriteFastInt(&streamData.stream, &length, sizeof(length));
    NSPortCoderWriteBytes(&streamData.stream, bytes, length);
}

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)address {
    _NSWalkData(1, YES, &streamData.stream, (void *)address, type);
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)address {
    _NSWalkData(0, YES, &streamData.stream, address, type);
}

- (void)encodeObject:(id)object isBycopy:(BOOL)bycopy isByref:(BOOL)byref {
    char oldBycopy = isBycopy;
    char oldByref = isByref;
    id replacement;

    if (NSPortCoderLoggingEnabled != 0) {
        const char *className = object != nil
            ? ((Class)object)->isa->name : "<nil>";
        NSLog(@"encodeObject: %x (%s) isBycopy:(%d) isByref:(%d)\n",
              (unsigned)object, className, bycopy, byref);
    }
    isBycopy = bycopy;
    isByref = byref;
    replacement = [object replacementObjectForPortCoder:self];
    if (replacement == nil) {
        NSPortCoderWriteMarker(&streamData.stream, 0);
    } else {
        Class objectClass = *(Class *)replacement;
        NSPortCoderClassLayout *isaLayout = (NSPortCoderClassLayout *)objectClass;

        if ((isaLayout->info & 2) != 0) {
            NSPortCoderWriteMarker(&streamData.stream, 3);
            NSPortCoderWriteCString(&streamData.stream, isaLayout->name);
        } else {
            Class coderClass = [replacement classForPortCoder];
            NSPortCoderClassLayout *layout = (NSPortCoderClassLayout *)coderClass;
            Class superclass;
            BOOL wroteVersion = NO;

            if (coderClass == Nil)
                [NSException raise:NSInvalidArgumentException
                            format:@"classForPortCoder returned nil"];
            NSPortCoderWriteMarker(&streamData.stream, 1);
            NSPortCoderWriteCString(&streamData.stream, layout->name);
            if (layout->version != 0) {
                NSPortCoderWriteMarker(&streamData.stream, 1);
                NSPortCoderWriteFastInt(&streamData.stream, &layout->version,
                                        sizeof(layout->version));
                wroteVersion = YES;
            }
            for (superclass = layout->superClass; superclass != Nil;
                 superclass = ((NSPortCoderClassLayout *)superclass)->superClass) {
                NSPortCoderClassLayout *superLayout =
                    (NSPortCoderClassLayout *)superclass;

                if (superLayout->version != 0) {
                    if (!wroteVersion) {
                        NSPortCoderWriteMarker(&streamData.stream, 1);
                        NSPortCoderWriteFastInt(&streamData.stream,
                            &layout->version, sizeof(layout->version));
                        wroteVersion = YES;
                    }
                    NSPortCoderWriteMarker(&streamData.stream, 1);
                    NSPortCoderWriteCString(&streamData.stream,
                                            superLayout->name);
                    NSPortCoderWriteFastInt(&streamData.stream,
                        &superLayout->version, sizeof(superLayout->version));
                }
            }
            NSPortCoderWriteMarker(&streamData.stream, 0);
            [replacement encodeWithCoder:self];
            NSPortCoderWriteMarker(&streamData.stream, 1);
        }
    }
    isBycopy = oldBycopy;
    isByref = oldByref;
}

- (id)decodeRetainedObject {
    unsigned char marker = NSPortCoderReadMarker(&streamData.stream);
    const char *className;
    NSString *name;
    Class objectClass;
    id object;

    if (marker == 0) {
        if (NSPortCoderLoggingEnabled != 0)
            NSLog(@"deserializeObjectAt: nil object received\n");
        return nil;
    }
    className = NSPortCoderReadCString(&streamData.stream);
    name = [NSString stringWithCString:className];
    objectClass = NSClassFromString(name);
    if (objectClass == Nil)
        [NSException raise:NSInvalidArgumentException
                    format:@"NSPortCoder cannot decode class %s", className];
    if ((marker & 2) != 0)
        return (id)objectClass;

    if (NSPortCoderReadMarker(&streamData.stream) != 0) {
        int version;
        NSPortCoderReadFastInt(&streamData.stream, &version, sizeof(version));
        [connection addClassNamed:className version:version];
        while (NSPortCoderReadMarker(&streamData.stream) != 0) {
            const char *superName = NSPortCoderReadCString(&streamData.stream);
            NSPortCoderReadFastInt(&streamData.stream, &version, sizeof(version));
            [connection addClassNamed:superName version:version];
        }
    }
    if (objectClass == [NSDistantObject class]) {
        object = [NSDistantObject newDistantObjectWithCoder:self];
    } else if (objectClass == [NSInvocation class]) {
        object = [NSInvocation newInvocationWithCoder:self];
    } else if (objectClass == [NSData class]) {
        object = [[self decodeDataObject] retain];
    } else {
        object = [[objectClass allocWithZone:[self objectZone]] initWithCoder:self];
        object = [object awakeAfterUsingCoder:self];
    }
    if (NSPortCoderReadMarker(&streamData.stream) == 0)
        [NSException raise:NSInvalidArgumentException
                    format:@"NSPortCoder object terminator is missing"];
    if (NSPortCoderLoggingEnabled != 0) {
        const char *className = object != nil
            ? ((Class)object)->isa->name : "<nil>";
        NSLog(@"decodeObject: %x [%s] ", (unsigned)object, className);
    }
    return object;
}

- (void)importObject:(id)object {
    if (importedObjects == nil)
        importedObjects = [[NSMutableArray allocWithZone:NULL] initWithCapacity:16];
    [importedObjects addObject:object];
}

- (void)sendBeforeTime:(NSTimeInterval)time {
    NSPort *sendPort = [connection sendPort];
    BOOL usesStreamSender = [sendPort respondsToSelector:
        @selector(sendBeforeTime:streamData:components:from:msgid:)];
    BOOL sent;

#if defined(__ppc__) || defined(__POWERPC__)
    if (NSPortCoderLoggingEnabled != 0) {
        int port = [sendPort machPort];
        unsigned count = [components count];

        NSLog(@"msg_sending on %d, %d components\n", port, count);
    }
#else
    if (NSPortCoderLoggingEnabled != 0) {
        unsigned count = [components count];
        int port = [sendPort machPort];

        NSLog(@"msg_sending on %d, %d components\n", port, count);
    }
#endif
    if (usesStreamSender) {
        NSArray *streamComponents = components;
        NSPort *receivePort;

#if !defined(__ppc__) && !defined(__POWERPC__)
        receivePort = [connection receivePort];
#endif
        if (streamComponents != nil && [streamComponents count] == 0)
            streamComponents = nil;
#if defined(__ppc__) || defined(__POWERPC__)
        receivePort = [connection receivePort];
#endif
        sent = [sendPort sendBeforeTime:time streamData:&streamData
                             components:streamComponents from:receivePort
                                  msgid:msgid];
        if (!sent) {
            [connection release];
            connection = nil;
            [NSException raise:NSInvalidArgumentException
                        format:@"NSPortCoder could not send the message before its deadline"];
        }
    } else {
        NSArray *outgoingComponents = [self components];
        NSPort *receivePort;
        NSDate *limitDate;
        unsigned reserved;

#if defined(__ppc__) || defined(__POWERPC__)
        limitDate = [NSDate dateWithTimeIntervalSinceReferenceDate:time];
        receivePort = [connection receivePort];
        reserved = [sendPort reservedSpaceLength];
#else
        reserved = [sendPort reservedSpaceLength];
        receivePort = [connection receivePort];
        limitDate = [NSDate dateWithTimeIntervalSinceReferenceDate:time];
#endif
        sent = [sendPort sendBeforeDate:limitDate
                             components:(NSMutableArray *)outgoingComponents
                                   from:receivePort
                               reserved:reserved];
        if (!sent)
            [NSException raise:NSInvalidArgumentException
                        format:@"NSPortCoder could not send the message before its deadline"];
    }
    [connection release];
    connection = nil;
}

- (void *)decodeBytesWithReturnedLength:(unsigned *)length {
    NSPortCoderReadFastInt(&streamData.stream, length, sizeof(*length));
    return *length != 0
        ? (void *)NSPortCoderReadData(&streamData.stream, *length) : NULL;
}

- (void)encodeDataObject:(NSData *)data {
    unsigned length = [data length];
    BOOL asComponent = length >= NSPageSize();

    NSPortCoderWriteMarker(&streamData.stream, asComponent);
    if (asComponent) {
        [[self components] addObject:data];
    } else {
        NSPortCoderWriteFastInt(&streamData.stream, &length, sizeof(length));
        NSPortCoderWriteBytes(&streamData.stream, [data bytes], length);
    }
}

- (NSData *)decodeDataObject {
    unsigned length;
    const void *bytes;

    if (NSPortCoderReadMarker(&streamData.stream) != 0)
        return [components objectAtIndex:componentIndex++];
    NSPortCoderReadFastInt(&streamData.stream, &length, sizeof(length));
    bytes = NSPortCoderReadData(&streamData.stream, length);
    if (((unsigned)bytes & 3) == 0) {
        unsigned offset = (unsigned)((const char *)bytes - streamData.stream.start);
        return [(NSStreamData *)&streamData
            subdataWithRange:NSMakeRange(offset, length)];
    }
    return [NSData dataWithBytes:bytes length:length];
}

- (void)invalidate {
    if (isValid) {
        isValid = NO;
        [components removeAllObjects];
        [importedObjects removeAllObjects];
        [connection release];
        connection = nil;
    }
}

- (void)dealloc {
    BOOL deallocated = NO;

    if (isValid)
        [self invalidate];
    if (streamData.refObject == self) {
        if (streamData.stream.isVMData)
            NSDeallocateMemoryPages(streamData.stream.start,
                (unsigned)(streamData.stream.limit - streamData.stream.start));
        else
            _NSGenericFree(streamData.stream.start);
    }
    if (_NSPortCoderCacheLock != nil)
        [_NSPortCoderCacheLock lock];
    if (NSPortCoderCache == nil)
        NSPortCoderCache = self;
    else if (NSPortCoderCache1 == nil)
        NSPortCoderCache1 = self;
    else if (NSPortCoderCache2 == nil)
        NSPortCoderCache2 = self;
    else if (NSPortCoderCache3 == nil)
        NSPortCoderCache3 = self;
    else {
        if (_NSPortCoderCacheLock != nil)
            [_NSPortCoderCacheLock unlock];
        [components release];
        [importedObjects release];
        [super dealloc];
        deallocated = YES;
    }
    if (_NSPortCoderCacheLock != nil)
        [_NSPortCoderCacheLock unlock];
    if (!deallocated && NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectDeallocatedEvent, self);
}

- (void)encodeBycopyObject:(id)object {
    [self encodeObject:object isBycopy:YES isByref:NO];
}

- (void)encodeByrefObject:(id)object {
    [self encodeObject:object isBycopy:NO isByref:YES];
}

- (void)sendBeforeDate:(NSDate *)date {
    [self sendBeforeTime:[date timeIntervalSinceReferenceDate]];
}

- (unsigned)versionForClassName:(NSString *)className {
    return (unsigned)[connection versionForClassNamed:className];
}

@end

@implementation NSObject (NSDistributedObjects)

+ (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    return self;
}

- (Class)classForPortCoder {
    return [self classForCoder];
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    id object = [self replacementObjectForCoder:coder];

    if (object == nil)
        return nil;
    return [NSDistantObject proxyWithLocal:object connection:[coder connection]];
}

@end
