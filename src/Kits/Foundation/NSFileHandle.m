/*	NSFileHandle.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSFileHandle.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSZone.h>

#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/cthreads.h>
#include <mach/message.h>

NSString * const NSFileHandleOperationException = @"NSFileHandleOperationException";
NSString * const NSFileHandleReadCompletionNotification = @"NSFileHandleReadCompletionNotification";
NSString * const NSFileHandleReadToEndOfFileCompletionNotification = @"NSFileHandleReadToEndOfFileCompletionNotification";
NSString * const NSFileHandleConnectionAcceptedNotification = @"NSFileHandleConnectionAcceptedNotification";
NSString * const NSFileHandleDataAvailableNotification = @"NSFileHandleDataAvailableNotification";
NSString * const NSFileHandleNotificationDataItem = @"NSFileHandleNotificationDataItem";
NSString * const NSFileHandleNotificationFileHandleItem = @"NSFileHandleNotificationFileHandleItem";
NSString * const NSFileHandleNotificationMonitorModes = @"NSFileHandleNotificationMonitorModes";

@interface NSFileManager (NSFileHandlePrivate)
- (BOOL)getFileSystemRepresentation:(char *)buffer maxLength:(unsigned)length
                            withPath:(NSString *)path;
@end

@interface NSNotificationCenter (NSFileHandlePrivate)
- (unsigned int)countObserversName:(NSString *)name object:(id)object
                          literally:(BOOL)literally;
@end

typedef struct {
    struct mutex lock;
#if !defined(__ppc__) && !defined(__POWERPC__)
    int reserved;
#endif
    int references;
    int port;
    int error;
    int descriptor;
    void *nativeHandle;
    void *bytes;
    int length;
    int acceptedDescriptor;
} NSFileHandleHiddenData;

@interface NSConcreteFileHandle : NSFileHandle {
@public
    int _fd;
    void *_nativeHandle;
    void *_avars;
    unsigned short _flags;
    NSPort *_port;
    NSArray *_modes;
    NSFileHandleHiddenData *hiddenData;
    unsigned short _activity;
}
- (id)initWithPath:(NSString *)path flags:(int)flags createMode:(int)mode;
- (void)setModes:(NSArray *)modes;
- (void)setPort:(NSPort *)port;
- (NSPort *)port;
- (void)performFunction:(any_t (*)(any_t))function modes:(NSArray *)modes
               activity:(int)activity;
- (void)handleMachMessage:(void *)message;
@end

@interface NSNullFileHandle : NSFileHandle
@end

@interface NSConcretePipe : NSPipe {
@private
    NSFileHandle *_readHandle;
    NSFileHandle *_writeHandle;
}
@end

extern id _NSMethodExceptionProem(id object, SEL selector);
extern int _NSOpenFileDescriptor(char *path, int flags, int mode);
extern ssize_t _NSReadFromFileDescriptor(int descriptor, void *buffer, size_t length);
extern int _NSCloseFileDescriptor(int descriptor);
extern int sys_nerr;
extern char *sys_errlist[];

ssize_t _NSWriteToFileDescriptor(int descriptor, const void *buffer, size_t length) {
    return write(descriptor, buffer, length);
}

const char *_NSErrnoMessage(void) {
    if (cthread_errno() <= 0 || cthread_errno() >= sys_nerr)
        return "unknown error";
    return sys_errlist[cthread_errno()];
}

static void _NSFileHandleRaiseOperationException(id object, SEL selector) {
    id proem;
    const char *errnoMessage;

#if defined(__ppc__) || defined(__POWERPC__)
    proem = _NSMethodExceptionProem(object, selector);
    errnoMessage = _NSErrnoMessage();
#else
    errnoMessage = _NSErrnoMessage();
    proem = _NSMethodExceptionProem(object, selector);
#endif
    [NSException raise:NSFileHandleOperationException format:@"%@: %s",
        proem, errnoMessage];
}

static void _NSHiddenDataDeallocate(void *pointer) {
    NSFileHandleHiddenData *data = (NSFileHandleHiddenData *)pointer;

    if (data->bytes != NULL)
        NSZoneFree(NULL, data->bytes);
    if (data->acceptedDescriptor >= 0)
        close(data->acceptedDescriptor);
    NSZoneFree(NULL, data);
}

static int _NSHiddenDataReleaseDidDeallocate(NSFileHandleHiddenData *data) {
    int references;

#if defined(__ppc__) || defined(__POWERPC__)
    while (mutex_try_lock(&data->lock) == 0)
        cthread_yield();
    __asm__ volatile("isync" ::: "memory");
#else
    if (mutex_try_lock(&data->lock) == 0)
        mutex_wait_lock(&data->lock);
#endif
    references = --data->references;
#if defined(__ppc__) || defined(__POWERPC__)
    __asm__ volatile("sync" ::: "memory");
#endif
    data->lock = 0;
    if (references == 0)
        _NSHiddenDataDeallocate(data);
    return references == 0;
}

static int _NSHiddenDataReleaseAndSend(NSFileHandleHiddenData *data) {
    msg_header_t message;
    int released;

    bzero(&message, sizeof(message));
    message.msg_simple = TRUE;
    message.msg_size = sizeof(message);
    message.msg_remote_port = data->port;
    message.msg_local_port = MACH_PORT_NULL;
    message.msg_id = 0;
    released = _NSHiddenDataReleaseDidDeallocate(data);
    if (!released)
        return msg_send(&message, 5, 0);
    return released;
}

static NSFileHandleHiddenData *_NSHiddenDataAllocate(NSPort *port) {
    NSFileHandleHiddenData *data = (NSFileHandleHiddenData *)NSZoneMalloc(
        NULL, sizeof(NSFileHandleHiddenData));

    data->lock = 0;
    data->references = 2;
    data->port = [port machPort];
    data->error = 0;
    data->bytes = NULL;
    data->acceptedDescriptor = -1;
    return data;
}

static any_t NSFileHandleAcceptActivity(any_t argument) {
    NSFileHandleHiddenData *data = (NSFileHandleHiddenData *)argument;
    struct sockaddr address;
    socklen_t addressLength = sizeof(address);

    data->acceptedDescriptor = accept(data->descriptor, &address, &addressLength);
    if (data->acceptedDescriptor < 0)
        data->error = cthread_errno();
    _NSHiddenDataReleaseAndSend(data);
    return NULL;
}

static any_t NSFileHandleReadActivity(any_t argument) {
    NSFileHandleHiddenData *data = (NSFileHandleHiddenData *)argument;
    char buffer[4096];
    ssize_t length = _NSReadFromFileDescriptor(data->descriptor, buffer, sizeof(buffer));

    data->length = (int)length;
    if (length <= 0) {
        data->bytes = NULL;
        data->error = cthread_errno();
    } else {
        data->bytes = NSZoneMalloc(NULL, (unsigned)length);
        if (data->bytes != NULL)
            memmove(data->bytes, buffer, (unsigned)length);
    }
    _NSHiddenDataReleaseAndSend(data);
    return NULL;
}

static any_t NSFileHandleReadAllActivity(any_t argument) {
    NSFileHandleHiddenData *data = (NSFileHandleHiddenData *)argument;
    int length = 0;
    int capacity = 4096;
    ssize_t amount = 0;

    data->bytes = NSZoneMalloc(NULL, capacity);
    data->length = 0;
    while (1) {
        if (length == capacity) {
            capacity *= 2;
            data->bytes = NSZoneRealloc(NULL, data->bytes, 4 * length);
        }
#if defined(__ppc__) || defined(__POWERPC__)
        amount = _NSReadFromFileDescriptor(data->descriptor,
            (char *)data->bytes + length, capacity - length);
#else
        amount = read(data->descriptor, (char *)data->bytes + length,
                      capacity - length);
#endif
        if (amount <= 0)
            break;
        length += (int)amount;
    }
    if (amount < 0 && length == 0) {
        NSZoneFree(NULL, data->bytes);
        data->bytes = NULL;
        data->error = cthread_errno();
    }
    data->length = length;
    _NSHiddenDataReleaseAndSend(data);
    return NULL;
}

static any_t NSFileHandleWaitActivity(any_t argument) {
    NSFileHandleHiddenData *data = (NSFileHandleHiddenData *)argument;
    fd_set readSet;

    FD_ZERO(&readSet);
    FD_SET(data->descriptor, &readSet);
    if (select(data->descriptor + 1, &readSet, NULL, NULL, NULL) < 0)
        data->error = cthread_errno();
    _NSHiddenDataReleaseAndSend(data);
    return NULL;
}

static id __NSNullFileHandle;
static id __NSFileHandleStandardInput;
static id __NSFileHandleStandardOutput;
static id __NSFileHandleStandardError;

@implementation NSFileHandle

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSFileHandle class])
        return [NSConcreteFileHandle allocWithZone:zone];
    return [super allocWithZone:zone];
}

- (NSData *)availableData {
    return NSRequestConcreteImplementation(self, _cmd, [NSFileHandle class]);
}

- (NSData *)readDataToEndOfFile {
    return NSRequestConcreteImplementation(self, _cmd, [NSFileHandle class]);
}

- (NSData *)readDataOfLength:(unsigned int)length {
    (void)length;
    return NSRequestConcreteImplementation(self, _cmd, [NSFileHandle class]);
}

- (void)writeData:(NSData *)data {
    (void)data;
    NSRequestConcreteImplementation(self, _cmd, [NSFileHandle class]);
}

- (unsigned long long)offsetInFile {
    return (unsigned long long)NSRequestConcreteImplementation(self, _cmd,
        [NSFileHandle class]);
}

- (unsigned long long)seekToEndOfFile {
    return (unsigned long long)NSRequestConcreteImplementation(self, _cmd,
        [NSFileHandle class]);
}

- (void)seekToFileOffset:(unsigned long long)offset {
    (void)offset;
    NSRequestConcreteImplementation(self, _cmd, [NSFileHandle class]);
}

- (void)truncateFileAtOffset:(unsigned long long)offset {
    (void)offset;
    NSRequestConcreteImplementation(self, _cmd, [NSFileHandle class]);
}

- (void)synchronizeFile {
    NSRequestConcreteImplementation(self, _cmd, [NSFileHandle class]);
}

- (void)closeFile {
    NSRequestConcreteImplementation(self, _cmd, [NSFileHandle class]);
}

+ (id)fileHandleWithStandardInput {
    if (__NSFileHandleStandardInput == nil) {
        __NSFileHandleStandardInput = [[self allocWithZone:NULL]
            initWithFileDescriptor:0 closeOnDealloc:NO];
        if (__NSFileHandleStandardInput == nil)
            __NSFileHandleStandardInput = [self fileHandleWithNullDevice];
        else
            ((NSConcreteFileHandle *)__NSFileHandleStandardInput)->_flags |= 0x8000;
    }
    return __NSFileHandleStandardInput;
}

+ (id)fileHandleWithStandardOutput {
    if (__NSFileHandleStandardOutput == nil) {
        __NSFileHandleStandardOutput = [[self allocWithZone:NULL]
            initWithFileDescriptor:1 closeOnDealloc:NO];
        if (__NSFileHandleStandardOutput == nil)
            __NSFileHandleStandardOutput = [self fileHandleWithNullDevice];
        else
            ((NSConcreteFileHandle *)__NSFileHandleStandardOutput)->_flags |= 0x4000;
    }
    return __NSFileHandleStandardOutput;
}

+ (id)fileHandleWithStandardError {
    if (__NSFileHandleStandardError == nil) {
        __NSFileHandleStandardError = [[self allocWithZone:NULL]
            initWithFileDescriptor:2 closeOnDealloc:NO];
        if (__NSFileHandleStandardError == nil)
            __NSFileHandleStandardError = [self fileHandleWithNullDevice];
        else
            ((NSConcreteFileHandle *)__NSFileHandleStandardError)->_flags |= 0x2000;
    }
    return __NSFileHandleStandardError;
}

+ (id)fileHandleWithNullDevice {
    if (__NSNullFileHandle == nil)
        __NSNullFileHandle = [[NSNullFileHandle allocWithZone:NULL] init];
    return __NSNullFileHandle;
}

+ (id)fileHandleForReadingAtPath:(NSString *)path {
    NSConcreteFileHandle *handle = [[self allocWithZone:NULL]
        initWithPath:path flags:O_RDONLY createMode:0];
    return [handle autorelease];
}

+ (id)fileHandleForWritingAtPath:(NSString *)path {
    NSConcreteFileHandle *handle = [[self allocWithZone:NULL]
        initWithPath:path flags:O_WRONLY createMode:0];
    return [handle autorelease];
}

+ (id)fileHandleForUpdatingAtPath:(NSString *)path {
    NSConcreteFileHandle *handle = [[self allocWithZone:NULL]
        initWithPath:path flags:O_RDWR createMode:0];
    return [handle autorelease];
}

- (int)fileDescriptor {
    return (int)NSRequestConcreteImplementation(self, _cmd, [NSFileHandle class]);
}

@end

@implementation NSConcreteFileHandle

- (id)initWithFileDescriptor:(int)fd {
    return [self initWithFileDescriptor:fd closeOnDealloc:NO];
}

- (id)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)closeopt {
    _fd = fd;
    if (!closeopt)
        _flags |= 1;
    return self;
}

- (id)initWithPath:(NSString *)path flags:(int)flags createMode:(int)mode {
    char pathBuffer[4104];
    NSFileManager *manager = [NSFileManager defaultManager];
    int descriptor;

    if (![manager getFileSystemRepresentation:pathBuffer maxLength:1024
                                      withPath:path]) {
        [super dealloc];
        return nil;
    }
    descriptor = _NSOpenFileDescriptor(pathBuffer, flags, mode);
    if (descriptor < 0) {
        [super dealloc];
        return nil;
    }
    _fd = descriptor;
    return self;
}

- (NSData *)availableData {
    struct stat status;
    unsigned amount;
    NSMutableData *data;
    ssize_t length;

    if ((_flags & 8) != 0 || fstat(_fd, &status) < 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
    if (!S_ISREG(status.st_mode)) {
        amount = NSPageSize();
    } else {
        off_t offset = lseek(_fd, 0, SEEK_CUR);
        if (offset < 0)
            _NSFileHandleRaiseOperationException(self, _cmd);
        amount = status.st_size > offset ? (unsigned)(status.st_size - offset) : 0;
    }
    if (amount == 0)
        return [NSData data];
    data = [NSMutableData dataWithLength:amount];
    length = _NSReadFromFileDescriptor(_fd, [data mutableBytes], amount);
    if (length < 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
    if (length == 0)
        return [NSData data];
    return [NSData dataWithBytes:[data bytes] length:(unsigned)length];
}

- (NSData *)readDataToEndOfFile {
    return [self readDataOfLength:UINT_MAX];
}

- (NSData *)readDataOfLength:(unsigned int)requestedLength {
    struct stat status;
    NSMutableData *data;
    unsigned total = 0;
    unsigned remaining = requestedLength;
    unsigned amount;
    ssize_t length;

    if ((_flags & 8) != 0 || fstat(_fd, &status) < 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
    if (S_ISREG(status.st_mode)) {
        off_t offset = lseek(_fd, 0, SEEK_CUR);
        if (offset < 0)
            _NSFileHandleRaiseOperationException(self, _cmd);
        amount = status.st_size > offset ? (unsigned)(status.st_size - offset) : 0;
        if (requestedLength < amount)
            amount = requestedLength;
        if (amount == 0)
            return [NSData data];
        data = [NSMutableData dataWithLength:amount];
        length = _NSReadFromFileDescriptor(_fd, [data mutableBytes], amount);
        if (length < 0)
            _NSFileHandleRaiseOperationException(self, _cmd);
        if (length == 0)
            return [NSData data];
        return [NSData dataWithBytes:[data bytes] length:(unsigned)length];
    }
    amount = remaining > 4096 ? 4096 : remaining;
    data = [NSMutableData dataWithLength:amount];
    while (remaining != 0) {
        char *bytes = (char *)[data mutableBytes];
        length = _NSReadFromFileDescriptor(_fd, bytes + total, amount);
        if (length < 0)
            _NSFileHandleRaiseOperationException(self, _cmd);
        if (length == 0)
            break;
        total += (unsigned)length;
        remaining -= (unsigned)length;
        amount = remaining > 4096 ? 4096 : remaining;
        [data increaseLengthBy:amount];
    }
    return total == 0 ? [NSData data]
        : [NSData dataWithBytes:[data bytes] length:total];
}

- (void)writeData:(NSData *)data {
    const char *bytes;
    unsigned remaining;

    remaining = [data length];
    if (remaining == 0)
        return;
    if ((_flags & 8) != 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
    bytes = [data bytes];
    while (remaining != 0) {
        ssize_t length = _NSWriteToFileDescriptor(_fd, bytes, remaining);
        if (length < 0)
            _NSFileHandleRaiseOperationException(self, _cmd);
        bytes += length;
        remaining -= (unsigned)length;
    }
}

- (unsigned long long)offsetInFile {
    off_t offset;
    if ((_flags & 8) != 0 || (offset = lseek(_fd, 0, SEEK_CUR)) < 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
    return (unsigned long long)offset;
}

- (unsigned long long)seekToEndOfFile {
    off_t offset;
    if ((_flags & 8) != 0 || (offset = lseek(_fd, 0, SEEK_END)) < 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
    return (unsigned long long)offset;
}

- (void)seekToFileOffset:(unsigned long long)offset {
    if ((_flags & 8) != 0 || lseek(_fd, (off_t)offset, SEEK_SET) < 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
}

- (void)truncateFileAtOffset:(unsigned long long)offset {
    if ((_flags & 8) != 0 || lseek(_fd, (off_t)offset, SEEK_SET) < 0
        || ftruncate(_fd, (off_t)offset) < 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
}

- (void)synchronizeFile {
    if ((_flags & 8) != 0 || fsync(_fd) < 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
}

- (void)closeFile {
    if ((_flags & 8) == 0) {
        _NSCloseFileDescriptor(_fd);
        _flags |= 8;
    }
}

- (int)fileDescriptor {
    if ((_flags & 8) != 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
    return _fd;
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (void)setPort:(NSPort *)port {
    [_port release];
    _port = [port retain];
}

- (NSPort *)port {
    return _port;
}

- (void)setModes:(NSArray *)modes {
    NSRunLoop *runLoop;
    unsigned count;
    unsigned index;

    count = [_modes count];
    runLoop = [NSRunLoop currentRunLoop];
    for (index = 0; index < count; ++index)
        [runLoop removePort:_port forMode:[_modes objectAtIndex:index]];
    [_modes release];
    _modes = [modes copy];
    count = [_modes count];
    for (index = 0; index < count; ++index)
        [runLoop addPort:_port forMode:[_modes objectAtIndex:index]];
}

- (void)performFunction:(any_t (*)(any_t))function modes:(NSArray *)modes
               activity:(int)activity {
    static NSArray *defaultModes;
    cthread_t thread;

    if (modes == nil) {
        if (defaultModes == nil)
            defaultModes = [[NSArray allocWithZone:NULL]
                initWithObjects:NSDefaultRunLoopMode, nil];
        modes = defaultModes;
    }
    if (_port == nil) {
        _port = [NSPort port];
        [_port setDelegate:self];
    }
    if (_activity != 0 && activity != _activity)
        [NSException raise:NSInternalInconsistencyException
                    format:@"a different activity is already in progress"];
    _activity = activity;
    [self setModes:modes];
    if (hiddenData == NULL) {
        hiddenData = _NSHiddenDataAllocate(_port);
        hiddenData->descriptor = _fd;
        hiddenData->nativeHandle = _nativeHandle;
        thread = cthread_fork(function, (any_t)hiddenData);
        cthread_detach(thread);
    }
}

- (void)readInBackgroundAndNotifyForModes:(NSArray *)modes {
    [self performFunction:NSFileHandleReadActivity modes:modes activity:14];
}

- (void)readInBackgroundAndNotify {
    [self readInBackgroundAndNotifyForModes:nil];
}

- (void)readToEndOfFileInBackgroundAndNotifyForModes:(NSArray *)modes {
    [self performFunction:NSFileHandleReadAllActivity modes:modes activity:16];
}

- (void)readToEndOfFileInBackgroundAndNotify {
    [self readToEndOfFileInBackgroundAndNotifyForModes:nil];
}

- (void)acceptConnectionInBackgroundAndNotifyForModes:(NSArray *)modes {
    [self performFunction:NSFileHandleAcceptActivity modes:modes activity:12];
}

- (void)acceptConnectionInBackgroundAndNotify {
    [self acceptConnectionInBackgroundAndNotifyForModes:nil];
}

- (void)waitForDataInBackgroundAndNotifyForModes:(NSArray *)modes {
    [self performFunction:NSFileHandleWaitActivity modes:modes activity:20];
}

- (void)waitForDataInBackgroundAndNotify {
    [self waitForDataInBackgroundAndNotifyForModes:nil];
}

- (void)handleMachMessage:(void *)message {
    unsigned activity;
    BOOL isReadActivity;
    NSNotificationCenter *center;
    NSDictionary *userInfo;

    if (((unsigned *)message)[1] > 0x18)
        return;
    [self setModes:nil];
    activity = _activity;
    center = [NSNotificationCenter defaultCenter];
    if (activity == 12) {
        int descriptor = hiddenData->acceptedDescriptor;
        hiddenData->acceptedDescriptor = -1;
        _NSHiddenDataReleaseDidDeallocate(hiddenData);
        hiddenData = NULL;
        if ([center countObserversName:NSFileHandleConnectionAcceptedNotification
                                object:self literally:YES] != 0) {
            NSFileHandle *accepted = descriptor < 0 ? nil
                : [[NSFileHandle allocWithZone:NULL]
                    initWithFileDescriptor:descriptor];
#if defined(__ppc__) || defined(__POWERPC__)
            userInfo = accepted == nil ? [NSDictionary dictionary]
                : [NSDictionary dictionaryWithObject:accepted
                    forKey:NSFileHandleNotificationFileHandleItem];
#else
            userInfo = [NSDictionary dictionaryWithObjectsAndKeys:accepted,
                NSFileHandleNotificationFileHandleItem, nil];
#endif
            [center postNotificationName:NSFileHandleConnectionAcceptedNotification
                                  object:self userInfo:userInfo];
        }
    } else if (activity == 14 || activity == 16) {
        void *bytes = hiddenData->bytes;
        unsigned length = hiddenData->length;
        hiddenData->bytes = NULL;
        _NSHiddenDataReleaseDidDeallocate(hiddenData);
        hiddenData = NULL;
#if defined(__ppc__) || defined(__POWERPC__)
        isReadActivity = _activity == 14;
#else
        isReadActivity = activity == 14;
#endif
        if ([center countObserversName:isReadActivity
                ? NSFileHandleReadCompletionNotification
                : NSFileHandleReadToEndOfFileCompletionNotification
                                object:self literally:YES] != 0) {
#if defined(__ppc__) || defined(__POWERPC__)
            userInfo = bytes == NULL ? [NSDictionary dictionary]
                : [NSDictionary dictionaryWithObject:
                    [NSData dataWithBytes:bytes length:length]
                                          forKey:NSFileHandleNotificationDataItem];
#else
            userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                bytes == NULL ? nil : [NSData dataWithBytesNoCopy:bytes length:length],
                NSFileHandleNotificationDataItem, nil];
#endif
#if defined(__ppc__) || defined(__POWERPC__)
            isReadActivity = _activity == 14;
#else
            isReadActivity = activity == 14;
#endif
            [center postNotificationName:isReadActivity
                ? NSFileHandleReadCompletionNotification
                : NSFileHandleReadToEndOfFileCompletionNotification
                                object:self userInfo:userInfo];
        }
    } else if (activity == 20) {
        _NSHiddenDataReleaseDidDeallocate(hiddenData);
        hiddenData = NULL;
        if ([center countObserversName:NSFileHandleDataAvailableNotification
                                object:self literally:YES] != 0)
            [center postNotificationName:NSFileHandleDataAvailableNotification
                                  object:self userInfo:[NSDictionary dictionary]];
    } else {
        [NSException raise:NSInternalInconsistencyException
                    format:@"weird activity %u detected", activity];
    }
}

- (void)dealloc {
    if ((_flags & 0xE000) != 0)
        return;
    if ((_flags & 9) == 0 && _NSCloseFileDescriptor(_fd) != 0)
        _NSFileHandleRaiseOperationException(self, _cmd);
    if (hiddenData != NULL) {
        _NSHiddenDataReleaseDidDeallocate(hiddenData);
    }
    [self setModes:nil];
    [super dealloc];
}

@end

@implementation NSNullFileHandle

- (NSData *)availableData { return [NSData data]; }
- (NSData *)readDataToEndOfFile { return [NSData data]; }
- (NSData *)readDataOfLength:(unsigned)length { (void)length; return [NSData data]; }
- (void)writeData:(NSData *)data { (void)data; }
- (unsigned long long)offsetInFile { return 0; }
- (unsigned long long)seekToEndOfFile { return 0; }
- (void)seekToFileOffset:(unsigned long long)offset { (void)offset; }
- (void)truncateFileAtOffset:(unsigned long long)offset { (void)offset; }
- (void)synchronizeFile { }
- (void)closeFile { }
- (int)fileDescriptor { return -1; }

@end

@implementation NSPipe

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSPipe class])
        return [NSConcretePipe allocWithZone:zone];
    return [super allocWithZone:zone];
}

+ (id)pipe {
    return [[[NSPipe allocWithZone:NULL] init] autorelease];
}

- (NSFileHandle *)fileHandleForReading {
    return NSRequestConcreteImplementation(self, _cmd, [NSPipe class]);
}

- (NSFileHandle *)fileHandleForWriting {
    return NSRequestConcreteImplementation(self, _cmd, [NSPipe class]);
}

- (id)init {
    return [super init];
}

@end

@implementation NSConcretePipe

- (id)init {
    int descriptors[2];

    if (pipe(descriptors) < 0) {
        [super dealloc];
        return nil;
    }
    _readHandle = [[NSConcreteFileHandle allocWithZone:NULL]
        initWithFileDescriptor:descriptors[0] closeOnDealloc:YES];
    if (_readHandle == nil) {
        _NSCloseFileDescriptor(descriptors[0]);
        _NSCloseFileDescriptor(descriptors[1]);
        [super dealloc];
        return nil;
    }
    _writeHandle = [[NSConcreteFileHandle allocWithZone:NULL]
        initWithFileDescriptor:descriptors[1] closeOnDealloc:YES];
    if (_writeHandle == nil) {
        [_readHandle release];
        _NSCloseFileDescriptor(descriptors[1]);
        [super dealloc];
        return nil;
    }
    return self;
}

- (NSFileHandle *)fileHandleForReading { return _readHandle; }
- (NSFileHandle *)fileHandleForWriting { return _writeHandle; }

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (void)dealloc {
    [_writeHandle release];
    [_readHandle release];
    [super dealloc];
}

@end
