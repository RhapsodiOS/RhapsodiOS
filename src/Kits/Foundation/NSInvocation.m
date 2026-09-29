/*	NSInvocation.m
	An Objective C message object
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.

	Stage 2c Task 5: construction and bookkeeping.  Marshaling is
	Task 6, coding Task 7, -invoke Task 8.
*/

#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <objc/objc-class.h>
#include <stdio.h>
#include <string.h>

/*
	Mirror of the header's declared ivar layout -- the ABI-visible part
	(retainedArgs/isInvalid/signatureValid/retainedRet/externalArgFrame
	pack one word with `unused`, refCount takes the second).  All field
	access goes through this struct so the file needs no special
	compilation context.  */
typedef struct {
    Class		isa;
    NSObjCValue		returnValue;
    void		*argumentFrame;
    NSMethodSignature	*signature;
    NSMutableArray	*container;
    unsigned 		retainedArgs:1;
    unsigned		isInvalid:1;
    unsigned		signatureValid:1;
    unsigned		retainedRet:1;
    unsigned		externalArgFrame:1;
    unsigned		unused:3;
    unsigned		refCount:24;
    void		*reserved;
} NSInvocationInstance;

@implementation NSInvocation

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig
{
    return [[[self allocWithZone:NULL] initWithMethodSignature:sig]
        autorelease];
}

/*	Not declared by NSInvocation.h, but the only structural candidate
	for +invocationWithMethodSignature:'s own body -- the reference
	shows exactly this two-step alloc/init handoff, the same shape
	+[NSException exceptionWithName:reason:userInfo:] and
	+[NSAutoreleasePool alloc] both already use.  */
- (id)initWithMethodSignature:(NSMethodSignature *)sig
{
    NSInvocationInstance *instance;

    self = [super init];
    instance = (NSInvocationInstance *)self;

    instance->signature = [sig retain];
    instance->argumentFrame =
        NSZoneMalloc(0, [sig frameLength]);
    instance->container = nil;
    instance->retainedArgs = 0;
    instance->isInvalid = 0;
    instance->signatureValid = 1;
    instance->retainedRet = 0;
    instance->externalArgFrame = 0;
    instance->refCount = 1;
    instance->reserved = 0;
    return self;
}

- (void)dealloc
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;

    [instance->signature release];
    if (!instance->externalArgFrame && instance->argumentFrame != NULL)
        NSZoneFree(0, instance->argumentFrame);
    if (instance->container != nil)
        [instance->container release];
    if (instance->retainedRet &&
        instance->returnValue.type == NSObjCObjectType)
        [instance->returnValue.value.objectValue release];
    [super dealloc];
}

/*	The header declares no selector/target ivars because the frame
	itself is the storage: argument frame slots 0 and 4 ARE self and
	_cmd -- the same layout -invoke (Task 8) hands to objc_msgSendv.
	setTarget:/setSelector: write those slots; target/selector read
	them.  The reference's accessors do the same, which is why
	setTarget: before setSelector: leaves slot 4 (a garbage-zero id
	until set) unused by anything else.  */
- (SEL)selector
{
    void *frame = ((NSInvocationInstance *)self)->argumentFrame;

    return (frame == NULL) ? (SEL)0 : ((SEL *)frame)[1];
}

- (void)setSelector:(SEL)aSelector
{
    void *frame = ((NSInvocationInstance *)self)->argumentFrame;

    if (frame != NULL)
        ((SEL *)frame)[1] = aSelector;
}

- (id)target
{
    void *frame = ((NSInvocationInstance *)self)->argumentFrame;

    return (frame == NULL) ? nil : ((id *)frame)[0];
}

- (void)setTarget:(id)aTarget
{
    void *frame = ((NSInvocationInstance *)self)->argumentFrame;

    if (frame != NULL)
        ((id *)frame)[0] = aTarget;
}

- (NSMethodSignature *)methodSignature
{
    return ((NSInvocationInstance *)self)->signature;
}

/*	Whether the arguments already stored in argumentFrame are retained
	object references -- set once, by -retainArguments, and never
	cleared.  Real retaining of each object argument found in the
	frame is Task 6's job (it needs the signature's per-argument type
	info to know which slots hold an id at all); this task only
	tracks the flag and the ivar it is named after.  */
- (void)retainArguments
{
    ((NSInvocationInstance *)self)->retainedArgs = 1;
}

- (BOOL)argumentsRetained
{
    return ((NSInvocationInstance *)self)->retainedArgs ? YES : NO;
}

/*	Undeclared; NSInvocation's own -invoke (Task 8) checks this
	before dispatching, matching the ivar's own name.  Set once at
	construction and left alone thereafter -- nothing in this stage's
	own reconstructed surface ever invalidates a signature after the
	fact.  */
- (BOOL)_signatureValid
{
    return ((NSInvocationInstance *)self)->signatureValid ? YES : NO;
}

/*	Undeclared; replaces argumentFrame with a caller-supplied frame
	the invocation does not own, marking it external so -dealloc does
	not free it.  The sole caller in this stage's own analysis scope
	is +newInvocationWithCoder: (Task 7), which decodes a frame's
	bytes into memory it allocates itself and hands the pointer over
	rather than having the invocation allocate a second copy.  */
- (void)_setArgFrame:(void *)frame
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;

    if (!instance->externalArgFrame && instance->argumentFrame != NULL)
        NSZoneFree(0, instance->argumentFrame);
    instance->argumentFrame = frame;
    instance->externalArgFrame = 1;
}

/*	NSInvocation carries its own 24-bit count (the header's refCount
	bitfield) rather than NSObject's side table -- confirmed from the
	header's declared layout; the plan's tests pin the behaviour.  */
- (id)retain
{
    ((NSInvocationInstance *)self)->refCount++;
    return self;
}

- (void)release
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;

    if (--instance->refCount == 0)
        [self dealloc];
}

- (unsigned)retainCount
{
    return ((NSInvocationInstance *)self)->refCount;
}

/*	NSString is still the stage's TODO skeleton; this goes through the
	same +stringWithCString:length: entry the other classes use
	(carried by link_stubs.m until stage 3), unexercised by this
	stage's tests.  */
- (NSString *)description
{
    char buffer[64];

    sprintf(buffer, "<%s: 0x%x>",
            ((struct objc_object *)self)->isa->name, (unsigned)self);
    return [NSString stringWithCString:buffer length:strlen(buffer)];
}

@end
