/*	NSPortNameServer.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPortNameServer.h>
#import <Foundation/NSException.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSNumberFormatter.h>
#import <Foundation/NSDateFormatter.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDate.h>
#import <mach/mach_init.h>
#import <servers/netname.h>

@interface NSMachPort : NSPort
+ (void)resetAllPorts;
@end

@interface NSMachNMServer : NSPortNameServer {
    NSPort *_nameServerPort;
}
+ (id)default;
- (id)initWithPort:(NSPort *)port;
- (NSPort *)portForName:(NSString *)name onHost:(NSString *)host;
- (BOOL)registerPort:(NSPort *)port forName:(NSString *)name;
- (BOOL)registerPort:(NSPort *)port forName:(NSString *)name
           signature:(NSPort *)signature;
- (void)removePortForName:(NSString *)name signature:(NSPort *)signature;
@end

static NSMachNMServer *NSMachNMServerDefault;
NSPort *__NSMachNMServerPort;
static NSPort *NSMachNMServerSignature;

Class __NSArrayClass;
Class __NSConcreteArrayClass;
Class __NSMutableArrayClass;
Class __NSConcreteMutableArrayClass;
Class __NSDictionaryClass;
Class __NSConcreteDictionaryClass;
Class __NSMutableDictionaryClass;
Class __NSConcreteMutableDictionaryClass;
Class __NSSetClass;
Class __NSConcreteSetClass;
Class __NSMutableSetClass;
Class __NSConcreteMutableSetClass;
Class __NSCountedSetClass;
Class __NSStringArrayClass;
Class __NSDataClass;
Class __NSConcreteDataClass;
Class __NSMutableDataClass;
Class __NSConcreteMutableDataClass;
Class __NSStringClass;
Class __NSDistantObjectClass;
Class __NSInvocationClass;
Class __NSStreamDataClass;
Class __NSNotificationClass;
Class __NSConcreteNotificationClass;
Class __NSInlineCStringClass;
Class __NSConstantStringClass;
Class __NSNotificationCenterClass;
Class __NSProtocolCheckerClass;
Class __NSConcreteProtocolCheckerClass;
Class __NSPathStore2Class;
Class __NSMachPortClass;
Class __NSDateClass;
Class __NSDistantDateClass;
Class __NSConcreteDateClass;
Class __NSSimpleCStringClass;
Class __NSSimpleStringClass;
Class __NSInlineUnicodeStringClass;
Class __NSValueClass;
Class __NSConcreteValueClass;
Class __NSNumberClass;
Class __NSTimeZoneClass;
Class __NSConcreteTimeZoneClass;
Class __NSURLFormatterClass;
Class __NSPlaceholderStringClass;
Class __NSCStringClass;
Class __NSUnicodeStringClass;
Class __NSConcreteMutableStringClass;
Class __NSMutableStringClass;
Class __NSObjectClass;
Class __NSCStringWithGapClass;
Class __NSUnicodeStringWithGapClass;
Class __NSPortClass;
Class __NSDecimalNumberClass;
extern id __NSEmptyArray;
extern id __NSEmptyDictionary;
extern id __NSEmptySet;
extern id __NSEmptyStringArray;
extern NSDate *__NSDistantFutureDate;
extern NSDate *__NSDistantPastDate;

NSPort *_NSToDoAtProcessStart(void) {
    if (__NSArrayClass == nil)
        __NSArrayClass = objc_getClass("NSArray");
    if (__NSConcreteArrayClass == nil)
        __NSConcreteArrayClass = objc_getClass("NSConcreteArray");
    if (__NSMutableArrayClass == nil)
        __NSMutableArrayClass = objc_getClass("NSMutableArray");
    if (__NSConcreteMutableArrayClass == nil)
        __NSConcreteMutableArrayClass = objc_getClass("NSConcreteMutableArray");
    if (__NSDictionaryClass == nil)
        __NSDictionaryClass = objc_getClass("NSDictionary");
    if (__NSConcreteDictionaryClass == nil)
        __NSConcreteDictionaryClass = objc_getClass("NSConcreteDictionary");
    if (__NSMutableDictionaryClass == nil)
        __NSMutableDictionaryClass = objc_getClass("NSMutableDictionary");
    if (__NSConcreteMutableDictionaryClass == nil)
        __NSConcreteMutableDictionaryClass = objc_getClass("NSConcreteMutableDictionary");
    if (__NSSetClass == nil)
        __NSSetClass = objc_getClass("NSSet");
    if (__NSConcreteSetClass == nil)
        __NSConcreteSetClass = objc_getClass("NSConcreteSet");
    if (__NSMutableSetClass == nil)
        __NSMutableSetClass = objc_getClass("NSMutableSet");
    if (__NSConcreteMutableSetClass == nil)
        __NSConcreteMutableSetClass = objc_getClass("NSConcreteMutableSet");
    if (__NSCountedSetClass == nil)
        __NSCountedSetClass = objc_getClass("NSCountedSet");
    if (__NSStringArrayClass == nil)
        __NSStringArrayClass = objc_getClass("NSStringArray");
    if (__NSDataClass == nil)
        __NSDataClass = objc_getClass("NSData");
    if (__NSConcreteDataClass == nil)
        __NSConcreteDataClass = objc_getClass("NSConcreteData");
    if (__NSMutableDataClass == nil)
        __NSMutableDataClass = objc_getClass("NSMutableData");
    if (__NSConcreteMutableDataClass == nil)
        __NSConcreteMutableDataClass = objc_getClass("NSConcreteMutableData");
    if (__NSStringClass == nil)
        __NSStringClass = objc_getClass("NSString");
    if (__NSDistantObjectClass == nil)
        __NSDistantObjectClass = objc_getClass("NSDistantObject");
    if (__NSInvocationClass == nil)
        __NSInvocationClass = objc_getClass("NSInvocation");
    if (__NSStreamDataClass == nil)
        __NSStreamDataClass = objc_getClass("NSStreamData");
    if (__NSNotificationClass == nil)
        __NSNotificationClass = objc_getClass("NSNotification");
    if (__NSConcreteNotificationClass == nil)
        __NSConcreteNotificationClass = objc_getClass("NSConcreteNotification");
    if (__NSInlineCStringClass == nil)
        __NSInlineCStringClass = objc_getClass("NSInlineCString");
    if (__NSConstantStringClass == nil)
        __NSConstantStringClass = objc_getClass("NSConstantString");
    if (__NSNotificationCenterClass == nil)
        __NSNotificationCenterClass = objc_getClass("NSNotificationCenter");
    if (__NSProtocolCheckerClass == nil)
        __NSProtocolCheckerClass = objc_getClass("NSProtocolChecker");
    if (__NSConcreteProtocolCheckerClass == nil)
        __NSConcreteProtocolCheckerClass = objc_getClass("NSConcreteProtocolChecker");
    if (__NSPathStore2Class == nil)
        __NSPathStore2Class = objc_getClass("NSPathStore2");
    if (__NSMachPortClass == nil)
        __NSMachPortClass = objc_getClass("NSMachPort");
    if (__NSDateClass == nil)
        __NSDateClass = objc_getClass("NSDate");
    if (__NSDistantDateClass == nil)
        __NSDistantDateClass = objc_getClass("NSDistantDate");
    if (__NSConcreteDateClass == nil)
        __NSConcreteDateClass = objc_getClass("NSConcreteDate");
    if (__NSSimpleCStringClass == nil)
        __NSSimpleCStringClass = objc_getClass("NSSimpleCString");
    if (__NSSimpleStringClass == nil)
        __NSSimpleStringClass = objc_getClass("NSSimpleString");
    if (__NSInlineUnicodeStringClass == nil)
        __NSInlineUnicodeStringClass = objc_getClass("NSInlineUnicodeString");
    if (__NSValueClass == nil)
        __NSValueClass = objc_getClass("NSValue");
    if (__NSConcreteValueClass == nil)
        __NSConcreteValueClass = objc_getClass("NSConcreteValue");
    if (__NSNumberClass == nil)
        __NSNumberClass = objc_getClass("NSNumber");
    if (__NSTimeZoneClass == nil)
        __NSTimeZoneClass = objc_getClass("NSTimeZone");
    if (__NSConcreteTimeZoneClass == nil)
        __NSConcreteTimeZoneClass = objc_getClass("NSConcreteTimeZone");
    if (__NSURLFormatterClass == nil)
        __NSURLFormatterClass = objc_getClass("NSURLFormatter");
    if (__NSPlaceholderStringClass == nil)
        __NSPlaceholderStringClass = objc_getClass("NSPlaceholderString");
    if (__NSCStringClass == nil)
        __NSCStringClass = objc_getClass("NSCString");
    if (__NSUnicodeStringClass == nil)
        __NSUnicodeStringClass = objc_getClass("NSUnicodeString");
    if (__NSConcreteMutableStringClass == nil)
        __NSConcreteMutableStringClass = objc_getClass("NSConcreteMutableString");
    if (__NSMutableStringClass == nil)
        __NSMutableStringClass = objc_getClass("NSMutableString");
    if (__NSObjectClass == nil)
        __NSObjectClass = objc_getClass("NSObject");
    if (__NSCStringWithGapClass == nil)
        __NSCStringWithGapClass = objc_getClass("NSCStringWithGap");
    if (__NSUnicodeStringWithGapClass == nil)
        __NSUnicodeStringWithGapClass = objc_getClass("NSUnicodeStringWithGap");
    if (__NSPortClass == nil)
        __NSPortClass = objc_getClass("NSPort");
    if (__NSDecimalNumberClass == nil)
        __NSDecimalNumberClass = objc_getClass("NSDecimalNumber");
    [NSString setVersion:1];
    [NSMutableString setVersion:1];
    [NSCountedSet setVersion:1];
#if defined(__i386__)
    [NSTimeZone setVersion:1];
#elif defined(__ppc__) || defined(__POWERPC__)
    [NSValue setVersion:1];
#endif
    [NSNumberFormatter setVersion:4];
    [NSDateFormatter setVersion:41];
    if (__NSEmptyArray == nil)
        __NSEmptyArray = NSAllocateObject(__NSConcreteArrayClass, 0, NULL);
    if (__NSEmptyDictionary == nil)
        __NSEmptyDictionary = NSAllocateObject(__NSConcreteDictionaryClass, 0, NULL);
    if (__NSEmptySet == nil)
        __NSEmptySet = NSAllocateObject(__NSConcreteSetClass, 0, NULL);
    if (__NSEmptyStringArray == nil)
        __NSEmptyStringArray = NSAllocateObject(__NSStringArrayClass, 0, NULL);
    if (__NSDistantFutureDate == nil) {
        __NSDistantFutureDate = NSAllocateObject(__NSDistantDateClass, 0, NULL);
        __NSDistantFutureDate = [__NSDistantFutureDate
            initWithTimeIntervalSinceReferenceDate:63113990400.0];
    }
    if (__NSDistantPastDate == nil) {
        __NSDistantPastDate = NSAllocateObject(__NSDistantDateClass, 0, NULL);
        __NSDistantPastDate = [__NSDistantPastDate
            initWithTimeIntervalSinceReferenceDate:-63113817600.0];
    }
    [NSMachPort resetAllPorts];
    __NSMachNMServerPort = [[NSPort allocWithZone:NULL]
        initWithMachPort:name_server_port];
    return __NSMachNMServerPort;
}

@implementation NSPortNameServer

+ (id)defaultPortNameServer {
    return [NSMachNMServer default];
}

- (NSPort *)portForName:(NSString *)name {
    (void)name;
    return NSRequestConcreteImplementation(self, _cmd, [NSPortNameServer class]);
}

- (NSPort *)portForName:(NSString *)name host:(NSString *)host {
    return [self portForName:name onHost:host];
}

- (BOOL)registerPort:(NSPort *)port name:(NSString *)netName {
    return [self registerPort:port forName:netName];
}

- (void)removePortForName:(NSString *)name {
    (void)name;
    NSRequestConcreteImplementation(self, _cmd, [NSPortNameServer class]);
}

- (NSPort *)portForName:(NSString *)name onHost:(NSString *)host {
    (void)name;
    (void)host;
    return NSRequestConcreteImplementation(self, _cmd, [NSPortNameServer class]);
}

- (BOOL)registerPort:(NSPort *)port forName:(NSString *)netName {
    (void)port;
    (void)netName;
    return (BOOL)NSRequestConcreteImplementation(self, _cmd,
        [NSPortNameServer class]);
}

@end

@implementation NSMachNMServer

+ (id)default {
    if (NSMachNMServerDefault == nil)
        NSMachNMServerDefault = [[self allocWithZone:NULL] init];
    return NSMachNMServerDefault;
}

- (id)init {
    return [self initWithPort:__NSMachNMServerPort];
}

- (id)initWithPort:(NSPort *)port {
    _nameServerPort = [port retain];
    return self;
}

- (NSPort *)portForName:(NSString *)name onHost:(NSString *)host {
    const char *hostName = [host cString];
    const char *portName = [name cString];
    port_t port;

    if (hostName == NULL)
        hostName = "";
    if (portName == NULL)
        portName = "";
    if (netname_look_up((port_t)[_nameServerPort machPort], (char *)hostName,
                        (char *)portName, &port) != 0)
        return nil;
    return [NSPort portWithMachPort:port];
}

- (NSPort *)portForName:(NSString *)name {
    return [self portForName:name onHost:nil];
}

- (BOOL)registerPort:(NSPort *)port forName:(NSString *)name {
    if (NSMachNMServerSignature == nil)
        NSMachNMServerSignature = [[NSPort allocWithZone:NULL] init];
    return [self registerPort:port forName:name
                   signature:NSMachNMServerSignature];
}

- (BOOL)registerPort:(NSPort *)port forName:(NSString *)name
           signature:(NSPort *)signature {
    const char *portName;
    port_t portID;
    port_t signaturePort;
    port_t serverPort;

    if (![port respondsToSelector:@selector(machPort)])
        [NSException raise:NSInvalidArgumentException
                    format:@"object does not provide machPort"];
    portName = [name cString];
    if (portName == NULL)
        portName = "";
#if defined(__i386__)
    portID = (port_t)[port machPort];
    signaturePort = (port_t)[signature machPort];
    serverPort = (port_t)[_nameServerPort machPort];
#elif defined(__ppc__) || defined(__POWERPC__)
    serverPort = (port_t)[_nameServerPort machPort];
    signaturePort = (port_t)[signature machPort];
    portID = (port_t)[port machPort];
#else
    portID = (port_t)[port machPort];
    signaturePort = (port_t)[signature machPort];
    serverPort = (port_t)[_nameServerPort machPort];
#endif
    return netname_check_in(serverPort, (char *)portName, signaturePort,
                            portID) == 0;
}

- (void)removePortForName:(NSString *)name {
    [self removePortForName:name signature:NSMachNMServerSignature];
}

- (void)removePortForName:(NSString *)name signature:(NSPort *)signature {
    const char *portName = [name cString];
    port_t serverPort;
    port_t signaturePort;

    if (portName == NULL)
        portName = "";
#if defined(__i386__)
    signaturePort = (port_t)[signature machPort];
    serverPort = (port_t)[_nameServerPort machPort];
#elif defined(__ppc__) || defined(__POWERPC__)
    serverPort = (port_t)[_nameServerPort machPort];
    signaturePort = (port_t)[signature machPort];
#else
    serverPort = (port_t)[_nameServerPort machPort];
    signaturePort = (port_t)[signature machPort];
#endif
    netname_check_out(serverPort, (char *)portName, signaturePort);
}

- (unsigned)count {
    return 0;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[(Class)self->isa allocWithZone:zone] init];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [[(Class)self->isa allocWithZone:zone] init];
}

- (void)dealloc {
    [_nameServerPort release];
    [super dealloc];
}

@end
