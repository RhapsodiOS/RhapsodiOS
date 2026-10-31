/*	NSDistributedNotificationCenter.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDistributedNotificationCenter.h>
#import <Foundation/NSArchiver.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSZone.h>

#include <mach/mach.h>
#include <mach/message.h>
#include <mach/mach_error.h>
#include <servers/bootstrap.h>
#include <stdlib.h>
#include <string.h>

#if defined(__ppc__) || defined(__POWERPC__)
#define NSDNCCopyPayload memmove
#else
#define NSDNCCopyPayload memcpy
#endif

extern id _NSMethodExceptionProem(id object, SEL aSelector);
#if defined(__ppc__) || defined(__POWERPC__)
extern void _NSBasicStdErrLog(const char *format, ...);
#endif

NSString * const NSLocalNotificationCenterType = @"_NSLocalNotificationCenter";

static NSMutableDictionary *NSDistributedNotificationCenterRegistry;
static NSMutableSet *NSDistributedNotificationCenterUniquedStrings;
#if defined(__ppc__) || defined(__POWERPC__)
static volatile BOOL _NSDistributedNotificationCenterLogging;
#endif

@interface NSNotificationCenter (NSDistributedNotificationCenterPrivate)
- (void)addObserver:(id)observer selector:(SEL)selector name:(NSString *)name
             object:(id)object flags:(unsigned int)flags;
- (void)postNotificationName:(NSString *)name object:(id)object
                    userInfo:(NSDictionary *)userInfo flags:(unsigned int)flags;
@end

@interface NSDistributedNotificationCenter (NSDistributedNotificationCenterPrivate)
- (void)changedSuspensionBehavior:(NSNotificationSuspensionBehavior)behavior
                             name:(NSString *)name object:(NSString *)object;
- (void)_registerName:(NSString *)name object:(NSString *)object
 suspensionBehavior:(NSNotificationSuspensionBehavior)behavior;
- (void)_postNotificationToNetwork:(NSData *)data name:(NSString *)name
                            object:(NSString *)object deliverImmediately:(BOOL)deliverImmediately;
- (void)_handleNotificationFromNetwork:(NSData *)data name:(NSString *)name
                                 object:(NSString *)object deliveryStatus:(unsigned int)deliveryStatus;
@end

@interface NSConcreteMachDNC : NSDistributedNotificationCenter {
    int _localPort;
    int _serverPort;
    char _suspended;
}
- (void)sendMessageToServer:(msg_header_t *)message;
- (const char *)serverName;
- (void)handleMachMessage:(msg_header_t *)message;
- (void)lostServerPort:(NSNotification *)notification;
- (void)_suspend:(BOOL)suspend;
@end

@interface NSConcreteMachLocalDNC : NSConcreteMachDNC
@end

@interface _NSLocalNotificationCenter : NSDistributedNotificationCenter
@end

static size_t NSDNCAlign4(size_t length)
{
    return (length + 3) & ~(size_t)3;
}

static void NSDNCWriteType(unsigned char *address, unsigned char name,
                           unsigned char size, size_t count,
                           BOOL isInline, BOOL isLong, BOOL deallocate)
{
    msg_type_t *descriptor = (msg_type_t *)address;

    descriptor->msg_type_name = name;
    descriptor->msg_type_size = size;
    descriptor->msg_type_number = (unsigned)(count & 0x0fff);
    descriptor->msg_type_inline = isInline;
    descriptor->msg_type_longform = isLong;
    descriptor->msg_type_deallocate = deallocate;
}

static char *_NSBuildMessage(unsigned int kind, int flags, void *nameBytes,
                             size_t nameLength, void *objectBytes,
                             size_t objectLength, void *userInfoBytes,
                             size_t userInfoLength)
{
    size_t wireNameLength = nameBytes != NULL ? nameLength + 1 : 0;
    size_t wireObjectLength = objectBytes != NULL ? objectLength + 1 : 0;
    size_t alignedNameLength = NSDNCAlign4(wireNameLength);
    size_t alignedObjectLength = NSDNCAlign4(wireObjectLength);
    BOOL outOfLine = kind == 1 && userInfoBytes != NULL
        && vm_page_size <= userInfoLength;
    size_t messageSize = 32;
    unsigned char *bytes;
    unsigned char *nameType;
    unsigned char *objectType;

    if (kind <= 1) {
        messageSize = alignedNameLength + alignedObjectLength + 40;
        if (kind == 1)
            messageSize += outOfLine ? 16 : 12 + userInfoLength;
    }

#if defined(__ppc__) || defined(__POWERPC__)
    bytes = (unsigned char *)NSZoneMalloc(NULL, messageSize);
#else
    bytes = (unsigned char *)malloc(messageSize);
#endif
    ((msg_header_t *)bytes)->msg_simple = outOfLine ? 0 : 1;
    ((msg_header_t *)bytes)->msg_size = (msg_size_t)messageSize;
    ((msg_header_t *)bytes)->msg_type = 0;
    ((msg_header_t *)bytes)->msg_local_port = PORT_NULL;
    ((msg_header_t *)bytes)->msg_remote_port = PORT_NULL;
    ((msg_header_t *)bytes)->msg_id = (integer_t)kind;

    NSDNCWriteType(bytes + 24, 2, 32, 1, YES, NO, NO);
    ((int *)(bytes + 28))[0] = flags;
    if (kind == 2)
        return (char *)bytes;

    nameType = bytes + 32;
    NSDNCWriteType(nameType, 9, 8, wireNameLength, YES, NO, NO);
    if (nameLength != 0)
        NSDNCCopyPayload(nameType + 4, nameBytes, nameLength);

    objectType = nameType + 4 + alignedNameLength;
    NSDNCWriteType(objectType, 9, 8, wireObjectLength, YES, NO, NO);
    if (objectLength != 0)
        NSDNCCopyPayload(objectType + 4, objectBytes, objectLength);

    if (kind == 1) {
        unsigned char *userInfoType = objectType + 4 + alignedObjectLength;
        msg_type_long_t *longType = (msg_type_long_t *)userInfoType;

        longType->msg_type_header.msg_type_name = 0;
        longType->msg_type_header.msg_type_size = 0;
        longType->msg_type_header.msg_type_number = 0;
        longType->msg_type_header.msg_type_inline = outOfLine ? 0 : 1;
        longType->msg_type_header.msg_type_longform = 1;
        longType->msg_type_header.msg_type_deallocate = 0;
        longType->msg_type_long_name = 9;
        longType->msg_type_long_size = 8;
        longType->msg_type_long_number = (unsigned)userInfoLength;
        if (outOfLine)
            memcpy(userInfoType + 12, &userInfoBytes, sizeof(userInfoBytes));
        else if (userInfoLength != 0)
            NSDNCCopyPayload(userInfoType + 12, userInfoBytes, userInfoLength);
    }
    return (char *)bytes;
}

static char *NSBuildRegisterMessage(int flags, void *nameBytes, size_t nameLength,
                                    void *objectBytes, size_t objectLength)
{
    return _NSBuildMessage(0, flags, nameBytes, nameLength,
                           objectBytes, objectLength, NULL, 0);
}

char *NSBuildPostMessage(int flags, void *nameBytes, size_t nameLength,
                         void *objectBytes, size_t objectLength,
                         void *userInfoBytes, size_t userInfoLength)
{
    return _NSBuildMessage(1, flags, nameBytes, nameLength,
                           objectBytes, objectLength,
                           userInfoBytes, userInfoLength);
}

static char *NSBuildSuspendMessage(int flags)
{
    return _NSBuildMessage(2, flags, NULL, 0, NULL, 0, NULL, 0);
}

void *_NSParseMessage(msg_header_t *message, unsigned int kind,
                      unsigned *messageID, unsigned *flags,
                      void **nameBytes, unsigned *nameLength,
                      void **objectBytes, unsigned *objectLength,
                      void **userInfoBytes, unsigned *userInfoLength)
{
    unsigned char *bytes = (unsigned char *)message;
    msg_type_t *nameType;
    msg_type_t *objectType;
    msg_type_long_t *userInfoType;
    unsigned wireNameLength;
    unsigned wireObjectLength;
    unsigned char *result;

    *messageID = (unsigned)message->msg_remote_port;
    memcpy(flags, bytes + 28, sizeof(*flags));
    if (kind == 2)
        return messageID;

    nameType = (msg_type_t *)(bytes + 32);
    wireNameLength = nameType->msg_type_number & 0x0fff;
    *nameBytes = wireNameLength != 0 ? (unsigned char *)nameType + 4 : NULL;
    *nameLength = wireNameLength != 0 ? wireNameLength - 1 : 0;

    objectType = (msg_type_t *)((unsigned char *)nameType + 4
                                 + NSDNCAlign4(wireNameLength));
    wireObjectLength = objectType->msg_type_number & 0x0fff;
    *objectBytes = wireObjectLength != 0 ? (unsigned char *)objectType + 4 : NULL;
    *objectLength = wireObjectLength != 0 ? wireObjectLength - 1 : 0;

    result = (unsigned char *)objectType + 4 + NSDNCAlign4(wireObjectLength);
    if (kind != 0) {
        userInfoType = (msg_type_long_t *)((unsigned char *)objectType + 4
                                            + NSDNCAlign4(wireObjectLength));
        if (userInfoType->msg_type_header.msg_type_inline)
            *userInfoBytes = (unsigned char *)userInfoType + 12;
        else
            memcpy(userInfoBytes, (unsigned char *)userInfoType + 12,
                   sizeof(*userInfoBytes));
        *userInfoLength = userInfoType->msg_type_long_number;
        if (*userInfoLength == 0)
            *userInfoBytes = NULL;
    } else {
        *userInfoBytes = NULL;
        *userInfoLength = 0;
    }
    return result;
}

void *NSParsePostMessage(msg_header_t *message, unsigned *messageID,
                         unsigned *flags, void **nameBytes,
                         unsigned *nameLength, void **objectBytes,
                         unsigned *objectLength, void **userInfoBytes,
                         unsigned *userInfoLength)
{
    return _NSParseMessage(message, 1, messageID, flags, nameBytes,
                           nameLength, objectBytes, objectLength,
                           userInfoBytes, userInfoLength);
}

void *NSParseRegisterMessage(msg_header_t *message, unsigned *messageID,
                             unsigned *flags, void **nameBytes,
                             unsigned *nameLength, void **objectBytes,
                             unsigned *objectLength)
{
    return _NSParseMessage(message, 0, messageID, flags, nameBytes,
                           nameLength, objectBytes, objectLength, NULL, NULL);
}

void *NSParseSuspendMessage(msg_header_t *message, unsigned *messageID,
                            unsigned *flags)
{
    return _NSParseMessage(message, 2, messageID, flags, NULL, NULL,
                           NULL, NULL, NULL, NULL);
}

int NSFlagsFromNotificationSuspensionBehavior(int behavior)
{
    return behavior;
}

int NSFlagsFromNotificationDeliveryBehavior(int behavior)
{
    return behavior;
}

int NSFlagsFromNotificationDeliveryStatus(int status)
{
    return status;
}

int NSNotificationDeliveryBehaviorFromFlags(char behavior)
{
    return behavior & 7;
}

int NSNotificationDeliveryStatusFromFlags(char status)
{
    return status & 7;
}

int NSNotificationSuspendActionFromFlags(char suspend)
{
    return suspend & 1;
}

int NSFlagsFromNotificationSuspendAction(int suspend)
{
    return suspend;
}

@implementation _NSLocalNotificationCenter

- (id)init
{
    [super dealloc];
    return [[NSConcreteMachLocalDNC allocWithZone:NULL] init];
}

@end

@implementation NSConcreteMachDNC

- (id)init
{
    self = [super init];
    _localPort = 0;
    _serverPort = 0;
    return self;
}

- (void)sendMessageToServer:(msg_header_t *)message
{
    if (_localPort == 0) {
        NSPort *localPort = [[NSPort allocWithZone:[self zone]] init];

        _localPort = [localPort machPort];
        [localPort setDelegate:self];
        [[NSRunLoop currentRunLoop] addPort:localPort forMode:NSDefaultRunLoopMode];
    }

    if (_serverPort == 0) {
        kern_return_t error = bootstrap_look_up(bootstrap_port, [self serverName],
                                                (mach_port_t *)&_serverPort);

        if (error != KERN_SUCCESS) {
#if defined(__ppc__) || defined(__POWERPC__)
            if (_NSDistributedNotificationCenterLogging)
                _NSBasicStdErrLog(
                    "Can't connect to the distributed notification server: bootstrap_look_up returned %s.",
                    mach_error_string(error));
#else
            NSLog(@"Can't connect to the distributed notification server: bootstrap_look_up returned %s.",
                  mach_error_string(error));
#endif
            return;
        }
        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(lostServerPort:)
                   name:NSPortDidBecomeInvalidNotification
                 object:[[NSPort alloc] initWithMachPort:_serverPort]];
    }

    message->msg_local_port = (port_t)_localPort;
    message->msg_remote_port = (port_t)_serverPort;
    kern_return_t sendError = msg_send(message, SEND_TIMEOUT, 0);
    if (sendError != KERN_SUCCESS) {
#if defined(__ppc__) || defined(__POWERPC__)
        if (_NSDistributedNotificationCenterLogging)
            _NSBasicStdErrLog(
                "Can't send message to the distributed notification server: msg_send returned %s.",
                mach_error_string(sendError));
#else
        NSLog(@"Can't send message to the distributed notification server: msg_send returned %s.",
              mach_error_string(sendError));
#endif
    }
}

- (const char *)serverName
{
    NSRequestConcreteImplementation(self, _cmd, [self class]);
    return NULL;
}

- (void)handleMachMessage:(msg_header_t *)message
{
    unsigned messageID;
    unsigned flags;
    void *nameBytes;
    unsigned nameLength;
    void *objectBytes;
    unsigned objectLength;
    void *userInfoBytes;
    unsigned userInfoLength;
    NSData *nameData;
    NSData *objectData = nil;
    NSData *userInfoData = nil;
    NSString *name;
    NSString *object = nil;

    NSParsePostMessage(message, &messageID, &flags, &nameBytes, &nameLength,
                       &objectBytes, &objectLength,
                       &userInfoBytes, &userInfoLength);
    nameData = [[NSData allocWithZone:[self zone]]
        initWithBytes:nameBytes length:nameLength];
    if (objectBytes != NULL)
        objectData = [[NSData allocWithZone:[self zone]]
            initWithBytes:objectBytes length:objectLength];
    if (userInfoBytes != NULL)
        userInfoData = [[NSData allocWithZone:[self zone]]
            initWithBytes:userInfoBytes length:userInfoLength];

    name = [[NSString allocWithZone:[self zone]] initWithData:nameData encoding:4];
    object = [[NSString allocWithZone:[self zone]]
        initWithData:objectData encoding:4];
    [self _handleNotificationFromNetwork:userInfoData name:name object:object
                          deliveryStatus:NSNotificationDeliveryStatusFromFlags((char)flags)];
    [name release];
    [object release];
    [userInfoData release];
}

- (void)lostServerPort:(NSNotification *)notification
{
    NSNotificationCenter *center;
    id notificationObject;

    _serverPort = 0;
#if defined(__ppc__) || defined(__POWERPC__)
    center = [NSNotificationCenter defaultCenter];
    notificationObject = [notification object];
#else
    notificationObject = [notification object];
    center = [NSNotificationCenter defaultCenter];
#endif
    [center removeObserver:self name:NSPortDidBecomeInvalidNotification
                    object:notificationObject];
#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSDistributedNotificationCenterLogging)
        _NSBasicStdErrLog("Lost connection to notification server.");
#else
    NSLog(@"Lost connection to notification server.");
#endif
}

- (void)_suspend:(BOOL)suspend
{
    int flags = NSFlagsFromNotificationSuspendAction(suspend == NO);
    char *message = NSBuildSuspendMessage(flags);

    [self sendMessageToServer:(msg_header_t *)message];
#if defined(__ppc__) || defined(__POWERPC__)
    NSZoneFree(NULL, message);
#else
    free(message);
#endif
}

- (void)_registerName:(NSString *)name object:(NSString *)object
 suspensionBehavior:(NSNotificationSuspensionBehavior)behavior
{
    NSData *nameData = name != nil ? [name dataUsingEncoding:4] : nil;
    NSData *objectData = object != nil ? [object dataUsingEncoding:4] : nil;
    void *nameBytes;
    size_t nameLength;
    void *objectBytes;
    size_t objectLength;
    int flags;
    char *message;

#if defined(__ppc__) || defined(__POWERPC__)
    flags = NSFlagsFromNotificationSuspensionBehavior(behavior);
    nameBytes = (void *)[nameData bytes];
    nameLength = [nameData length];
    objectBytes = (void *)[objectData bytes];
    objectLength = [objectData length];
#else
    objectLength = [objectData length];
    objectBytes = (void *)[objectData bytes];
    nameLength = [nameData length];
    nameBytes = (void *)[nameData bytes];
    flags = NSFlagsFromNotificationSuspensionBehavior(behavior);
#endif

    message = NSBuildRegisterMessage(flags, nameBytes, nameLength,
                                     objectBytes, objectLength);

    [self sendMessageToServer:(msg_header_t *)message];
#if defined(__ppc__) || defined(__POWERPC__)
    NSZoneFree(NULL, message);
#else
    free(message);
#endif
}

- (void)_postNotificationToNetwork:(NSData *)userInfo name:(NSString *)name
                            object:(NSString *)object deliverImmediately:(BOOL)deliverImmediately
{
    NSData *nameData = [name dataUsingEncoding:4];
    NSData *objectData = object != nil ? [object dataUsingEncoding:4] : nil;
    void *nameBytes;
    size_t nameLength;
    void *objectBytes;
    size_t objectLength;
    void *userInfoBytes;
    size_t userInfoLength;
    int flags;
    char *message;

#if defined(__ppc__) || defined(__POWERPC__)
    flags = NSFlagsFromNotificationDeliveryBehavior(deliverImmediately == NO);
    nameLength = [nameData length];
    nameBytes = (void *)[nameData bytes];
    objectLength = [objectData length];
    objectBytes = (void *)[objectData bytes];
    userInfoLength = [userInfo length];
    userInfoBytes = (void *)[userInfo bytes];
#else
    userInfoLength = [userInfo length];
    userInfoBytes = (void *)[userInfo bytes];
    objectLength = [objectData length];
    objectBytes = (void *)[objectData bytes];
    nameLength = [nameData length];
    nameBytes = (void *)[nameData bytes];
    flags = NSFlagsFromNotificationDeliveryBehavior(deliverImmediately == NO);
#endif
    message = NSBuildPostMessage(flags, nameBytes, nameLength,
        objectBytes, objectLength, userInfoBytes, userInfoLength);

    [self sendMessageToServer:(msg_header_t *)message];
#if defined(__ppc__) || defined(__POWERPC__)
    NSZoneFree(NULL, message);
#else
    free(message);
#endif
}

- (void)setSuspended:(BOOL)suspended
{
    if (_suspended != suspended) {
        _suspended = suspended;
        [self _suspend:suspended];
    }
}

- (BOOL)suspended
{
    return _suspended;
}

@end

@implementation NSConcreteMachLocalDNC

- (const char *)serverName
{
    return "Apple DNC Server (Local Host)";
}

@end

static NSString *
UniqueString(NSString *string, BOOL copyIfNeeded)
{
    NSString *unique;

    if (string == nil)
        return nil;
    if (NSDistributedNotificationCenterUniquedStrings == nil)
        NSDistributedNotificationCenterUniquedStrings = [[NSMutableSet allocWithZone:0] init];
    unique = [NSDistributedNotificationCenterUniquedStrings member:string];
    if (unique != nil || !copyIfNeeded)
        return (unique != nil) ? unique : string;

    unique = [string copyWithZone:[NSDistributedNotificationCenterUniquedStrings zone]];
    [NSDistributedNotificationCenterUniquedStrings addObject:unique];
    [unique release];
    return unique;
}

static void
GarbageCollectUniquedStrings(void)
{
}

@implementation NSDistributedNotificationCenter

#if defined(__ppc__) || defined(__POWERPC__)
+ (void)enableLogging:(BOOL)enabled {
    _NSDistributedNotificationCenterLogging = enabled;
}
#endif

+ (NSDistributedNotificationCenter *)notificationCenterForType:(NSString *)notificationCenterType
{
    NSDistributedNotificationCenter *center;
    Class centerClass;

    if (NSDistributedNotificationCenterRegistry == nil)
        NSDistributedNotificationCenterRegistry = [[NSMutableDictionary allocWithZone:0]
            initWithCapacity:1];
    center = [NSDistributedNotificationCenterRegistry objectForKey:notificationCenterType];
    if (center != nil)
        return center;

    centerClass = NSClassFromString(notificationCenterType);
    if (centerClass == Nil)
        centerClass = self;
    center = [[centerClass allocWithZone:0] init];
    if (center != nil) {
        [NSDistributedNotificationCenterRegistry setObject:center forKey:notificationCenterType];
        [center release];
    }
    return center;
}

+ (id)defaultCenter
{
    return [self notificationCenterForType:NSLocalNotificationCenterType];
}

- (id)init
{
    if ([self class] == [NSDistributedNotificationCenter class]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSDistributedNotificationCenter is an abstract class. Only concrete subclasses may be instantiated."];
    }
    return [super init];
}

- (void)changedSuspensionBehavior:(NSNotificationSuspensionBehavior)behavior
                             name:(NSString *)name object:(NSString *)object
{
    [self _registerName:name object:object suspensionBehavior:behavior];
}

- (void)addObserver:(id)observer selector:(SEL)selector name:(NSString *)name
             object:(NSString *)object suspensionBehavior:(NSNotificationSuspensionBehavior)suspensionBehavior
{
    if (object != nil && ![object isKindOfClass:[NSString class]]) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: object in distributed notification must be a string", proem];
    }
    object = UniqueString(object, YES);
    [super addObserver:observer selector:selector name:name object:object
                 flags:(unsigned int)NSFlagsFromNotificationSuspensionBehavior(
                     suspensionBehavior)];
}

- (void)postNotificationName:(NSString *)name object:(NSString *)object
                    userInfo:(NSDictionary *)userInfo deliverImmediately:(BOOL)deliverImmediately
{
    NSMutableData *data;
    NSArchiver *archiver;

    if (name == nil)
        return;
    if (object != nil && ![object isKindOfClass:[NSString class]]) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: object in distributed notification must be a string", proem];
    }

    data = [[NSMutableData allocWithZone:[self zone]] init];
    archiver = [[NSArchiver allocWithZone:[self zone]]
        initForWritingWithMutableData:data];
    [archiver encodeObject:userInfo];
    [self _postNotificationToNetwork:data name:name object:object
                  deliverImmediately:deliverImmediately];
    [archiver release];
    [data release];
}

- (void)setSuspended:(BOOL)suspended
{
    NSRequestConcreteImplementation(self, _cmd, [self class]);
}

- (BOOL)suspended
{
    NSRequestConcreteImplementation(self, _cmd, [self class]);
    return NO;
}

- (void)addObserver:(id)aObserver selector:(SEL)aSelector name:(NSString *)aName
             object:(NSString *)anObject
{
    [self addObserver:aObserver selector:aSelector name:aName object:anObject
 suspensionBehavior:NSNotificationSuspensionBehaviorCoalesce];
}

- (void)postNotification:(NSNotification *)notification
{
    NSDictionary *userInfo = [notification userInfo];
    NSString *object = [notification object];
    NSString *name = [notification name];

    [self postNotificationName:name object:object userInfo:userInfo deliverImmediately:NO];
}

- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject
{
    [super postNotificationName:aName object:anObject];
}

- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject
                    userInfo:(NSDictionary *)aUserInfo
{
    [self postNotificationName:aName object:anObject userInfo:aUserInfo deliverImmediately:NO];
}

- (void)removeObserver:(id)observer name:(NSString *)name object:(NSString *)object
{
    if (object != nil && ![object isKindOfClass:[NSString class]]) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: object in distributed notification must be a string", proem];
    }
    object = UniqueString(object, NO);
    [super removeObserver:observer name:name object:object];
    GarbageCollectUniquedStrings();
}

- (void)_registerName:(NSString *)name object:(NSString *)object
 suspensionBehavior:(NSNotificationSuspensionBehavior)behavior
{
    NSRequestConcreteImplementation(self, _cmd, [self class]);
}

- (void)_postNotificationToNetwork:(NSData *)data name:(NSString *)name
                            object:(NSString *)object deliverImmediately:(BOOL)deliverImmediately
{
    NSRequestConcreteImplementation(self, _cmd, [self class]);
}

- (void)_handleNotificationFromNetwork:(NSData *)data name:(NSString *)name
                                 object:(NSString *)object deliveryStatus:(unsigned int)deliveryStatus
{
    NSUnarchiver *unarchiver = [[NSUnarchiver allocWithZone:0] initForReadingWithData:data];
    NSDictionary *userInfo = nil;
    BOOL didPost = NO;

    NS_DURING
        userInfo = [unarchiver decodeObject];
        NSString *uniqueObject = UniqueString(object, NO);
        [super postNotificationName:name object:uniqueObject userInfo:userInfo
                              flags:NSFlagsFromNotificationDeliveryStatus(
                                  (int)deliveryStatus)];
        didPost = YES;
    NS_HANDLER
        NSLog(@"Caught exception %@ posting notification %@", localException, name);
        [userInfo release];
    NS_ENDHANDLER
    if (didPost)
        [unarchiver release];
}

- (BOOL)checkSuspensionBehavior:(NSNotificationSuspensionBehavior)behavior
                 deliveryStatus:(unsigned int)deliveryStatus
{
    if (deliveryStatus == 1)
        return behavior == NSNotificationSuspensionBehaviorCoalesce ||
               behavior == NSNotificationSuspensionBehaviorHold;
    if (deliveryStatus != 0)
        return YES;
    return behavior == NSNotificationSuspensionBehaviorHold;
}

@end
