/*	NSInvocation.m
	An Objective C message object
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.

	Stage 2c Task 5: construction and bookkeeping.  Marshaling is
	Task 6, coding Task 7, -invoke Task 8.
*/

#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <objc/objc-class.h>
#include <stdio.h>
#include <string.h>

/*	NSException.m exports this beside the public raise path; no header
	declares it, so this file carries the declaration.  */
extern id _NSMethodExceptionProem(id object, SEL aSelector);

/*	The argument-cache entry NSMethodSignature.m hands back through
	-_argumentInfoAtIndex: -- the reference's 20-byte i386 layout,
	{?=ii*^{_arginfo}i}: the frame offset, the size, the type pointer,
	and two fields the constructor never writes.  */
typedef struct {
    unsigned	offset;
    unsigned	size;
    const char	*type;
    unsigned	unused0;
    unsigned	unused1;
} NSInvocationArgInfo;

/*	NSMethodSignature.m exposes its per-argument cache through this
	undeclared accessor; Task 1 measured the reference's own layout
	(entry +8 holds the type pointer) and this accessor is the
	reconstruction's cross-module stand-in for what the reference does
	by reaching into the signature's cache directly (index*20 off its
	_parmInfoP, rep movsd x5).  */
@interface NSMethodSignature (NSInvocationSupport)
- (void *)_argumentInfoAtIndex:(unsigned)index;
@end

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
/*	Undeclared; hands back the whole tagged return-value struct rather
	than copying just its bytes the way -getReturnValue: does.  Task
	7's -encodeReturnValueWithCoder: uses this to know which union
	member to encode.  */
- (NSObjCValue)_returnValue
{
    return ((NSInvocationInstance *)self)->returnValue;
}

/*	Neither NSInvocation.h nor NSMethodSignature.h documents a
	nullability contract for the four pointer arguments below; an
	unchecked memcpy on a NULL pointer is undefined behaviour, not a
	failure a caller can catch, so all four raise on NULL (Review
	Focus item 1).  Bounds match the reference's own check: -1
	through nargs-1 for getArgument:, 0 through nargs-1 for
	setArgument:, where -1 names the return value.  */

- (void)getArgument:(void *)argumentLocation atIndex:(int)index
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSInvocationArgInfo *info;
    unsigned size;

    if (instance->argumentFrame == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: argument frame is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }
    if (argumentLocation == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: argumentLocation is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }
    /*  The reference's own pair of comparisons: -1 <= index AND
        index < nargs (its jl/jg around cmp [edx+8], ecx).  Both sides
        compared as signed -- the usual int/unsigned promotion would
        wrap the -1 index to UINT_MAX and reject the return value.  */
    if (index < -1 ||
        index >= (int)[instance->signature numberOfArguments]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: index (%d) out of bounds",
                            _NSMethodExceptionProem(self, _cmd), index];
        return;
    }

    if (index == -1) {
        /*  The return value.  The reference switches on the return
            type; the observable effect is a copy of exactly the
            return type's own bytes -- scalars straight out of the
            union, compound types through the structLocation pointer
            -setReturnValue: recorded.  */
        NSGetSizeAndAlignment(
            [instance->signature methodReturnType], &size, NULL);
        if (instance->returnValue.type == NSObjCStructType ||
            instance->returnValue.type == NSObjCUnionType) {
            if (instance->returnValue.value.structLocation == NULL)
                return;
            memcpy(argumentLocation,
                   instance->returnValue.value.structLocation, size);
        } else {
            memcpy(argumentLocation, &instance->returnValue.value, size);
        }
        return;
    }

    info = (NSInvocationArgInfo *)
        [instance->signature _argumentInfoAtIndex:(unsigned)index];
    memcpy(argumentLocation,
           (char *)instance->argumentFrame + info->offset, info->size);
}

- (void)setArgument:(void *)argumentLocation atIndex:(int)index
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSInvocationArgInfo *info;

    if (instance->argumentFrame == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: argument frame is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }
    if (argumentLocation == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: argumentLocation is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }
    if (index < 0 ||
        (unsigned)index >= (unsigned)
            [instance->signature numberOfArguments]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: index (%d) out of bounds",
                            _NSMethodExceptionProem(self, _cmd), index];
        return;
    }

    info = (NSInvocationArgInfo *)
        [instance->signature _argumentInfoAtIndex:(unsigned)index];
    memcpy((char *)instance->argumentFrame + info->offset,
           argumentLocation, info->size);
}

- (void)getReturnValue:(void *)retLoc
{
    if (retLoc == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: retLoc is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }
    /*  The reference's 36-byte body is literally this tail-call: the
        -1 index of getArgument:atIndex: names the return value.  */
    [self getArgument:retLoc atIndex:-1];
}

- (void)setReturnValue:(void *)retLoc
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    const char *returnType;
    unsigned size = 0;

    if (retLoc == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: retLoc is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }

    returnType = [instance->signature methodReturnType];
    NSGetSizeAndAlignment(returnType, &size, NULL);
    instance->returnValue.type = (enum _NSObjCValueType)returnType[0];
    if (*returnType == '{' || *returnType == '(') {
        /*  Compound returns do not fit the 8-byte union: the
            reference mallocs storage and records the pointer, the
            way -invoke (Task 8) later fills it through the hidden
            return slot.  */
        void *storage = NSZoneMalloc(0, size);

        memcpy(storage, retLoc, size);
        instance->returnValue.value.structLocation = storage;
    } else {
        memcpy(&instance->returnValue.value, retLoc, size);
    }
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
