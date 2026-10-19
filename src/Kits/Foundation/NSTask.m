/*	NSTask.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSTask.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSPathUtilities.h>

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <mach/cthreads.h>
#include <mach/mach.h>
#include <mach/message.h>

NSString * const NSTaskDidTerminateNotification = @"NSTaskDidTerminateNotification";

NSString * const _NSTaskEnvironmentDictionary = @"_NSTaskEnvironmentDictionary";
NSString * const _NSTaskArgumentArray = @"_NSTaskArgumentArray";
NSString * const _NSTaskDirectoryPath = @"_NSTaskDirectoryPath";
NSString * const _NSTaskExecutablePath = @"_NSTaskExecutablePath";
NSString * const _NSTaskInputFileHandle = @"_NSTaskInputFileHandle";
NSString * const _NSTaskOutputFileHandle = @"_NSTaskOutputFileHandle";
NSString * const _NSTaskDiagnosticFileHandle = @"_NSTaskDiagnosticFileHandle";
NSString * const _NSTaskTerminationStatus = @"_NSTaskTerminationStatus";
NSString * const _NSTaskHasBeenLaunched = @"_NSTaskHasBeenLaunched";
NSString * const _NSTaskCreationFlags = @"_NSTaskCreationFlags";
NSString * const _NSTaskStartupInfo = @"_NSTaskStartupInfo";

@interface NSTask (NSTaskPrivate)
+ (id)launchedTaskWithDictionary:(NSDictionary *)dictionary;
+ (NSDictionary *)currentTaskDictionary;
- (void)launchWithDictionary:(NSDictionary *)dictionary;
@end

typedef struct {
    struct mutex lock;
#if !defined(__ppc__) && !defined(__POWERPC__)
    int reserved;
#endif
    int references;
    port_t port;
    pid_t pid;
    int status;
} NSTaskHiddenData;

@interface NSConcreteTask : NSTask {
@public
    NSMutableDictionary *_dictionary;
    char _hasExeced;
    char _isRunning;
    int _pid;
    int _terminationStatus;
    NSTaskHiddenData *hiddenTaskData;
    NSPort *port;
}
- (void)handleMachMessage:(void *)message;
- (int)_procid;
- (void)_requestNotification;
- (void)launchWithDictionary:(id)dictionary;
- (id)taskDictionary;
- (void)setTaskDictionary:(id)dictionary;
- (BOOL)taskExitedNormally;
- (void)terminateTask;
@end

extern id _NSMethodExceptionProem(id object, SEL selector);
extern char **_NSEnviron(void);
extern int _NSFileAccessibleForMode(NSString *path, int mode);
extern int _NSSetDirectory2(char *path);
extern int _NSOpenFileDescriptor(char *path, int flags, int mode);
extern int _NSCloseFileDescriptor(int descriptor);

static NSMutableDictionary *NSTaskDictionaryForAccess(NSConcreteTask *task) {
    if (task->_dictionary == nil)
        task->_dictionary = [[NSTask currentTaskDictionary] retain];
    return task->_dictionary;
}

static void NSTaskSetCopiedObject(NSConcreteTask *task, id object, id key) {
    id copy;

    if (task->_hasExeced)
        [NSException raise:NSInvalidArgumentException
                    format:@"task already launched"];
    NSMutableDictionary *dictionary = NSTaskDictionaryForAccess(task);
    copy = [object copyWithZone:NULL];
    [dictionary setObject:copy forKey:key];
    [copy release];
}

static void _NSHiddenTaskDataDeallocate(void *pointer) {
    NSZoneFree(NULL, pointer);
}

static int _NSHiddenTaskDataReleaseDidDeallocate(NSTaskHiddenData *data) {
    if (mutex_try_lock(&data->lock) == 0)
        mutex_wait_lock(&data->lock);
    --data->references;
    data->lock = 0;
    if (data->references != 0)
        return 0;
    _NSHiddenTaskDataDeallocate(data);
    return 1;
}

static int _NSHiddenTaskDataReleaseAndSend(NSTaskHiddenData *data) {
    msg_header_t message;
    int released;

    bzero(&message, sizeof(message));
    message.msg_simple = TRUE;
    message.msg_size = sizeof(message);
    message.msg_remote_port = data->port;
    message.msg_local_port = MACH_PORT_NULL;
    message.msg_id = 0;
    released = _NSHiddenTaskDataReleaseDidDeallocate(data);
    if (!released)
        return msg_send(&message, 5, 0);
    return released;
}

static any_t NSTaskWaitForTermination(any_t argument) {
    NSTaskHiddenData *data = (NSTaskHiddenData *)argument;
    int status;

    do {
        if (wait4(data->pid, &status, 2, NULL) >= 0) {
            data->status = status >> 8;
            _NSHiddenTaskDataReleaseAndSend(data);
            return NULL;
        }
    } while (cthread_errno() == EINTR);

    data->status = -1;
    _NSHiddenTaskDataReleaseAndSend(data);
    return NULL;
}

static NSTaskHiddenData *_NSHiddenTaskDataAllocate(NSPort *taskPort) {
    NSTaskHiddenData *data = NSZoneMalloc(NULL, sizeof(*data));

    data->lock = 0;
    data->references = 2;
    data->port = (port_t)[taskPort machPort];
    return data;
}

@implementation NSTask

+ (id)allocWithZone:(NSZone *)zone {
    Class taskClass = self;

    if (self == [NSTask class])
        taskClass = [NSConcreteTask class];
    return NSAllocateObject(taskClass, 0, zone);
}

+ (NSDictionary *)currentTaskDictionary {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSFileHandle fileHandleWithStandardInput], _NSTaskInputFileHandle,
        [NSFileHandle fileHandleWithStandardOutput], _NSTaskOutputFileHandle,
        [NSFileHandle fileHandleWithStandardError], _NSTaskDiagnosticFileHandle,
        [[NSFileManager defaultManager] currentDirectoryPath],
            _NSTaskDirectoryPath,
        nil];
}

+ (id)launchedTaskWithDictionary:(NSDictionary *)dictionary {
    NSTask *task = [[self allocWithZone:NULL] init];

    [task launchWithDictionary:dictionary];
    return task;
}

+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments {
    NSMutableDictionary *dictionary = (NSMutableDictionary *)[NSTask currentTaskDictionary];
    NSTask *task = [[self allocWithZone:NULL] init];

    [dictionary setObject:path forKey:_NSTaskExecutablePath];
    [dictionary setObject:arguments forKey:_NSTaskArgumentArray];
    [task launchWithDictionary:dictionary];
    return task;
}

+ (id)launchedTaskWithPath:(NSString *)path arguments:(NSArray *)arguments {
    return [self launchedTaskWithLaunchPath:path arguments:arguments];
}

#if !defined(__ppc__) && !defined(__POWERPC__)
+ (NSTask *)taskWithPath:(NSString *)path arguments:(NSArray *)arguments {
    unsigned argumentCount = [arguments count];
    char **argv = NSZoneMalloc(NULL, sizeof(char *) * (argumentCount + 2));
    NSFileManager *fileManager = [NSFileManager defaultManager];
    char *filePath = (char *)[fileManager fileSystemRepresentationWithPath:path];
    pid_t child;
    unsigned index;

    if (!_NSFileAccessibleForMode(path, X_OK))
        return nil;

    argv[0] = filePath;
    for (index = 0; index < argumentCount; ++index)
        argv[index + 1] = (char *)[[arguments objectAtIndex:index] cString];
    argv[argumentCount + 1] = NULL;

    child = fork();
    if (child < 0)
        return nil;
    if (child == 0) {
        pid_t grandchild = fork();
        int descriptor;
        int descriptorCount;

        if (grandchild < 0)
            exit(1);
        if (grandchild != 0)
            exit(0);

        descriptorCount = getdtablesize();
        setsid();
        for (descriptor = 0; descriptor < descriptorCount; ++descriptor)
            _NSCloseFileDescriptor(descriptor);

        descriptor = _NSOpenFileDescriptor("/dev/tty", O_NONBLOCK, 0);
        if (descriptor >= 0) {
            ioctl(descriptor, 0x20007471u, 0);
            _NSCloseFileDescriptor(descriptor);
        }
        _NSOpenFileDescriptor("/dev/null", O_RDONLY, 0);
        _NSOpenFileDescriptor("/dev/console", O_WRONLY, 0);
        dup2(1, 2);
        descriptor = _NSOpenFileDescriptor("/dev/tty", O_NONBLOCK, 0);
        if (descriptor >= 0) {
            ioctl(descriptor, 0x20007471u, 0);
            _NSCloseFileDescriptor(descriptor);
        }
        execv(filePath, argv);
        NSLog(@"Task create for path %@ failed.", path);
        exit(-1);
    }

    wait4(child, NULL, 0, NULL);
    return [[[NSObject allocWithZone:NULL] init] autorelease];
}
#endif

- (id)init {
    return [super init];
}

- (void)setLaunchPath:(NSString *)path {
    (void)path;
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (void)setArguments:(NSArray *)arguments {
    (void)arguments;
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (void)setEnvironment:(NSDictionary *)dict {
    (void)dict;
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (void)setCurrentDirectoryPath:(NSString *)path {
    (void)path;
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (void)setStandardInput:(id)input {
    (void)input;
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (void)setStandardOutput:(id)output {
    (void)output;
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (void)setStandardError:(id)error {
    (void)error;
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (NSString *)launchPath {
    return (NSString *)NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (NSArray *)arguments {
    return (NSArray *)NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (NSDictionary *)environment {
    return (NSDictionary *)NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (NSString *)currentDirectoryPath {
    return (NSString *)NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (id)standardInput {
    return NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (id)standardOutput {
    return NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (id)standardError {
    return NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (void)launch {
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (void)interrupt {
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (void)terminate {
    NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (BOOL)isRunning {
    return (BOOL)NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

- (int)terminationStatus {
    return (int)NSRequestConcreteImplementation(self, _cmd, [NSTask class]);
}

@end

@implementation NSConcreteTask

- (id)init {
    return [super init];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_dictionary release];
    if (hiddenTaskData != NULL)
        _NSHiddenTaskDataReleaseDidDeallocate(hiddenTaskData);
    if (port != nil) {
        [[NSRunLoop currentRunLoop] removePort:port forMode:NSDefaultRunLoopMode];
        [port setDelegate:nil];
        [port release];
    }
    [super dealloc];
}

- (void)setLaunchPath:(NSString *)path {
    NSTaskSetCopiedObject(self, path, _NSTaskExecutablePath);
}

- (void)setArguments:(NSArray *)arguments {
    NSTaskSetCopiedObject(self, arguments, _NSTaskArgumentArray);
}

- (void)setEnvironment:(NSDictionary *)dict {
    NSTaskSetCopiedObject(self, dict, _NSTaskEnvironmentDictionary);
}

- (void)setCurrentDirectoryPath:(NSString *)path {
    NSTaskSetCopiedObject(self, path, _NSTaskDirectoryPath);
}

- (void)setStandardInput:(id)input {
    if (_hasExeced)
        [NSException raise:NSInvalidArgumentException
                    format:@"task already launched"];
    [NSTaskDictionaryForAccess(self) setObject:input forKey:_NSTaskInputFileHandle];
}

- (void)setStandardOutput:(id)output {
    if (_hasExeced)
        [NSException raise:NSInvalidArgumentException
                    format:@"task already launched"];
    [NSTaskDictionaryForAccess(self) setObject:output forKey:_NSTaskOutputFileHandle];
}

- (void)setStandardError:(id)error {
    if (_hasExeced)
        [NSException raise:NSInvalidArgumentException
                    format:@"task already launched"];
    [NSTaskDictionaryForAccess(self) setObject:error forKey:_NSTaskDiagnosticFileHandle];
}

- (NSString *)launchPath {
    return [NSTaskDictionaryForAccess(self) objectForKey:_NSTaskExecutablePath];
}

- (NSArray *)arguments {
    return [NSTaskDictionaryForAccess(self) objectForKey:_NSTaskArgumentArray];
}

- (NSDictionary *)environment {
    return [NSTaskDictionaryForAccess(self) objectForKey:_NSTaskEnvironmentDictionary];
}

- (NSString *)currentDirectoryPath {
    return [NSTaskDictionaryForAccess(self) objectForKey:_NSTaskDirectoryPath];
}

- (id)standardInput {
    return [NSTaskDictionaryForAccess(self) objectForKey:_NSTaskInputFileHandle];
}

- (id)standardOutput {
    return [NSTaskDictionaryForAccess(self) objectForKey:_NSTaskOutputFileHandle];
}

- (id)standardError {
    return [NSTaskDictionaryForAccess(self) objectForKey:_NSTaskDiagnosticFileHandle];
}

- (id)taskDictionary {
    if (_dictionary == nil)
        _dictionary = [[NSTask currentTaskDictionary] retain];
    if (_hasExeced)
        return [[_dictionary mutableCopyWithZone:NULL] autorelease];
    return _dictionary;
}

- (void)setTaskDictionary:(NSDictionary *)dictionary {
    NSMutableDictionary *oldDictionary;

    if (_hasExeced)
        [NSException raise:NSInvalidArgumentException
                    format:@"task already launched"];
    oldDictionary = _dictionary;
    _dictionary = [dictionary mutableCopyWithZone:NULL];
    if (oldDictionary != nil)
        [oldDictionary release];
}

- (int)_procid {
#if defined(__ppc__) || defined(__POWERPC__)
    return [self processIdentifier];
#else
    return _pid;
#endif
}

#if defined(__ppc__) || defined(__POWERPC__)
- (unsigned int)processIdentifier {
    return _pid;
}
#endif

- (void)launch {
    [self launchWithDictionary:_dictionary];
}

- (void)launchWithDictionary:(NSDictionary *)dictionary {
    NSString *executable;
    NSArray *arguments;
    NSDictionary *environment;
    NSString *directory;
    char *filePath;
    char *directoryPath;
    char **argv;
    char **envp = NULL;
    unsigned argumentCount;
    unsigned index;
    BOOL ownsEnvironment = NO;
    int descriptors[3] = {0, 1, 2};
    int safeDescriptors[3];
    NSFileHandle *childInput = nil;
    NSFileHandle *childOutput = nil;
    NSFileHandle *childError = nil;
    id input;
    id output;
    id error;
    pid_t child;

    if (_hasExeced)
        [NSException raise:NSInvalidArgumentException format:@"task already launched"];
    if (dictionary == nil)
        [NSException raise:NSInvalidArgumentException format:@"need a dictionary"];

    if (_dictionary != dictionary) {
        NSMutableDictionary *copy = [dictionary mutableCopyWithZone:NULL];
        [_dictionary release];
        _dictionary = copy;
    }
    [_dictionary removeObjectForKey:_NSTaskTerminationStatus];
    [_dictionary removeObjectForKey:_NSTaskHasBeenLaunched];

    executable = [[_dictionary objectForKey:_NSTaskExecutablePath]
        stringByStandardizingPath];
    if (!_NSFileAccessibleForMode(executable, X_OK))
        [NSException raise:NSInvalidArgumentException format:@"launch path not accessible"];

    arguments = [_dictionary objectForKey:_NSTaskArgumentArray];
    filePath = (char *)[executable fileSystemRepresentation];
    argumentCount = [arguments count];
    argv = NSZoneMalloc(NULL, sizeof(char *) * (argumentCount + 2));
    argv[0] = filePath;
    for (index = 0; index < argumentCount; ++index)
        argv[index + 1] = (char *)[[arguments objectAtIndex:index] cString];
    argv[argumentCount + 1] = NULL;

    directory = [_dictionary objectForKey:_NSTaskDirectoryPath];
    directoryPath = (char *)[directory fileSystemRepresentation];
    environment = [_dictionary objectForKey:_NSTaskEnvironmentDictionary];
    if (environment != nil) {
        unsigned environmentCount = [environment count];
        if (environmentCount != 0) {
            NSEnumerator *enumerator = [environment keyEnumerator];
            id key;

            envp = NSZoneMalloc(NULL, sizeof(char *) * (environmentCount + 1));
            ownsEnvironment = YES;
            index = 0;
            while ((key = [enumerator nextObject]) != nil) {
                NSString *entry = [NSString stringWithFormat:@"%@=%@", key,
                    [environment objectForKey:key]];
                envp[index++] = (char *)[entry cString];
            }
            envp[index] = NULL;
        }
    } else {
        envp = _NSEnviron();
    }

    input = [_dictionary objectForKey:_NSTaskInputFileHandle];
    if (input != nil) {
        if ([input isKindOfClass:[NSPipe class]]) {
            childInput = [input fileHandleForReading];
            descriptors[0] = [childInput fileDescriptor];
        } else {
            descriptors[0] = [input fileDescriptor];
        }
    } else {
        descriptors[0] = -1;
    }

    output = [_dictionary objectForKey:_NSTaskOutputFileHandle];
    if (output != nil) {
        if ([output isKindOfClass:[NSPipe class]]) {
            childOutput = [output fileHandleForWriting];
            descriptors[1] = [childOutput fileDescriptor];
        } else {
            descriptors[1] = [output fileDescriptor];
        }
    } else {
        descriptors[1] = -1;
    }

    error = [_dictionary objectForKey:_NSTaskDiagnosticFileHandle];
    if (error != nil) {
        if ([error isKindOfClass:[NSPipe class]]) {
            childError = [error fileHandleForWriting];
            descriptors[2] = [childError fileDescriptor];
        } else {
            descriptors[2] = [error fileDescriptor];
        }
    } else {
        descriptors[2] = -1;
    }

    child = vfork();
    _pid = child;
    if (child >= 0) {
        if (child == 0) {
            int descriptorCount = getdtablesize();
            int descriptor;

            setsid();
            for (descriptor = 0; descriptor <= 2; ++descriptor) {
                if (descriptors[descriptor] == -1)
                    safeDescriptors[descriptor] = -1;
                else if (descriptors[descriptor] > 2)
                    safeDescriptors[descriptor] = descriptors[descriptor];
                else
                    safeDescriptors[descriptor] = dup(descriptors[descriptor]);
            }

            for (descriptor = 0; descriptor <= 2; ++descriptor) {
                if (safeDescriptors[descriptor] == descriptor) {
                    descriptors[descriptor] = descriptor;
                } else if (safeDescriptors[descriptor] == -1) {
                    _NSCloseFileDescriptor(descriptor);
                    descriptors[descriptor] = _NSOpenFileDescriptor("/dev/null", O_RDWR, 0);
                } else {
                    _NSCloseFileDescriptor(descriptor);
                    descriptors[descriptor] = dup(safeDescriptors[descriptor]);
                }
            }

            for (descriptor = 3; descriptor < descriptorCount; ++descriptor)
                _NSCloseFileDescriptor(descriptor);
            if (directoryPath != NULL)
                _NSSetDirectory2(directoryPath);
            execve(filePath, argv, envp);
            NSLog(@"Task create for path %@ failed.", executable);
            exit(-1);
        }

        _isRunning = 1;
        _hasExeced = 1;
        if (_dictionary == dictionary) {
            _dictionary = [dictionary mutableCopyWithZone:NULL];
            [dictionary release];
        }
        [_dictionary setObject:@"YES" forKey:_NSTaskHasBeenLaunched];
        [childInput closeFile];
        [childOutput closeFile];
        if (childError != nil && childError != childOutput)
            [childError closeFile];
        [self _requestNotification];
    } else {
        [NSException raise:NSInternalInconsistencyException format:@"couldn't fork"];
    }

    NSZoneFree(NULL, argv);
    if (ownsEnvironment)
        NSZoneFree(NULL, envp);
}

- (void)_requestNotification {
    cthread_t thread;

    port = [NSPort port];
    [port setDelegate:self];
    [[NSRunLoop currentRunLoop] addPort:port forMode:NSDefaultRunLoopMode];
    hiddenTaskData = _NSHiddenTaskDataAllocate(port);
    hiddenTaskData->pid = _pid;
    thread = cthread_fork(NSTaskWaitForTermination, (any_t)hiddenTaskData);
    cthread_detach(thread);
}

- (void)handleMachMessage:(void *)message {
    (void)message;
    _terminationStatus = hiddenTaskData->status;
    _NSHiddenTaskDataReleaseDidDeallocate(hiddenTaskData);
    hiddenTaskData = NULL;
    _isRunning = 0;
    [[NSRunLoop currentRunLoop] removePort:port forMode:NSDefaultRunLoopMode];
    [port setDelegate:nil];
    [port release];
    port = nil;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSTaskDidTerminateNotification object:self
                    userInfo:nil];
}

- (void)interrupt {
    if (!_hasExeced)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: task not launched", _NSMethodExceptionProem(self, _cmd)];
    if (_isRunning)
        kill(-_pid, SIGINT);
}

- (void)terminate {
    if (!_hasExeced)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: task not launched", _NSMethodExceptionProem(self, _cmd)];
    if (_isRunning)
        kill(-_pid, SIGTERM);
}

- (void)terminateTask {
    [self terminate];
}

- (BOOL)taskExitedNormally {
    if (!_hasExeced)
        [NSException raise:NSInvalidArgumentException format:@"task not launched"];
    if (_isRunning)
        [NSException raise:NSInvalidArgumentException format:@"task still running"];
    return YES;
}

- (BOOL)isRunning {
    return _hasExeced ? _isRunning : NO;
}

- (int)terminationStatus {
    if (!_hasExeced)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: task not launched", _NSMethodExceptionProem(self, _cmd)];
    if (_isRunning)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: task still running", _NSMethodExceptionProem(self, _cmd)];
    return _terminationStatus;
}

- (void)waitUntilExit {
    NSDate *limitDate;
    NSRunLoop *runLoop;

    while (_isRunning) {
        limitDate = [NSDate distantFuture];
        runLoop = [NSRunLoop currentRunLoop];
        [runLoop runMode:NSDefaultRunLoopMode beforeDate:limitDate];
    }
}

@end
