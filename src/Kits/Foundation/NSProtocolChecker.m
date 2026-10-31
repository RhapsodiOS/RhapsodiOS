/*	NSProtocolChecker.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSProtocolChecker.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSPortCoder.h>
#import <objc/Protocol.h>
#import <objc/objc-runtime.h>

struct NSProtocolName {
    Class class_pointer;
    const char *protocol_name;
};

@interface Protocol (NSProtocolCheckerIntrospection)
- (struct objc_method_description *)instanceMethodDescriptionForSelector:(SEL)selector;
- (BOOL)conformsToProtocol:(Protocol *)protocol;
@end

extern id _NSRequestConcreteObject(id object, const char *selectorName);

@protocol NSProtocolCheckerForwardingMethods <NSCoding, NSCopying>
- (BOOL)_conformsToProtocolNamed:(const char *)name;
- (BOOL)respondsToSelector:(SEL)selector;
- (struct objc_method_description *)methodDescriptionForSelector:(SEL)selector;
- (void)forwardInvocation:(NSInvocation *)invocation;
@end

@interface NSConcreteProtocolChecker : NSProtocolChecker {
    NSObject *_target;
    Protocol *_protocol;
}
@end

static void _NSProtocolCheckerRaiseUnknownSelectorException(
    NSProtocolChecker *checker, SEL selector)
{
    (void)checker;
    [NSException raise:NSInvalidArgumentException
                format:@"*** NSProtocolChecker: target protocol does not recognize selector:%s",
                       sel_getName(selector)];
}

@implementation NSProtocolChecker

+ (id)allocWithZone:(NSZone *)zone {
    Class checkerClass = self;

    if (self == [NSProtocolChecker class])
        checkerClass = [NSConcreteProtocolChecker class];
    return NSAllocateObject(checkerClass, 0, zone);
}

- (Protocol *)protocol {
    return (Protocol *)NSRequestConcreteImplementation(self, _cmd,
                                                        [NSProtocolChecker class]);
}

- (NSObject *)target {
    return (NSObject *)NSRequestConcreteImplementation(self, _cmd,
                                                        [NSProtocolChecker class]);
}

+ (id)protocolCheckerWithTarget:(NSObject *)anObject protocol:(Protocol *)aProtocol {
    id checker = [[self allocWithZone:NULL] initWithTarget:anObject protocol:aProtocol];
    return [checker autorelease];
}

- (id)initWithTarget:(NSObject *)anObject protocol:(Protocol *)aProtocol {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    struct objc_method_description *description;

    description = [self methodDescriptionForSelector:selector];
    if (description != NULL)
        return [NSMethodSignature signatureWithObjCTypes:description->types];
    return nil;
}

- (struct objc_method_description *)methodDescriptionForSelector:(SEL)selector {
    struct objc_method_description *description;

    description = [@protocol(NSProtocolCheckerForwardingMethods)
        instanceMethodDescriptionForSelector:selector];
    if (description == NULL)
        description = [[self protocol] instanceMethodDescriptionForSelector:selector];
    return description;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    SEL selector = [invocation selector];
    struct objc_method_description *description;

    description = [[self protocol] instanceMethodDescriptionForSelector:selector];
    if (description == NULL)
        _NSProtocolCheckerRaiseUnknownSelectorException(self, selector);
    [invocation invokeWithTarget:[self target]];
}

- (BOOL)_conformsToProtocolNamed:(const char *)name {
    struct NSProtocolName protocol;
    protocol.protocol_name = name;
    return [[self protocol] conformsToProtocol:(Protocol *)&protocol];
}

- (id)awakeAfterUsingCoder:(id)coder {
    return self;
}

- (void)doesNotRecognizeSelector:(SEL)selector {
    _NSProtocolCheckerRaiseUnknownSelectorException(self, selector);
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    return [NSDistantObject proxyWithLocal:self connection:[coder connection]];
}

- (BOOL)respondsToSelector:(SEL)selector {
    return [[self protocol] instanceMethodDescriptionForSelector:selector] != NULL;
}

@end

@implementation NSConcreteProtocolChecker

- (NSObject *)target {
    return _target;
}

- (Protocol *)protocol {
    return _protocol;
}

- (id)initWithTarget:(NSObject *)anObject protocol:(Protocol *)aProtocol {
    _target = [anObject retain];
    _protocol = aProtocol;
    return self;
}

- (void)dealloc {
    [_target release];
    [super dealloc];
}

@end
