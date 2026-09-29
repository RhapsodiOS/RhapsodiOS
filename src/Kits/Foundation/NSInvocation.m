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
#import <objc/objc-runtime.h>
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

/*	The reference's -init is a 52-byte guard: it logs a fault and
	returns nil -- an NSInvocation is built through
	+invocationWithMethodSignature: or the coder path, never bare
	alloc/init.  Written exactly as measured (xor eax,eax before the
	return).  */
- (id)init
{
    [NSException raise:NSInternalInconsistencyException
                format:@"*** NSInvocation: use +invocationWithMethodSignature:"];
    return nil;
}

/*	The reference's -invalidate sets the isInvalid bit (bit 1 of the
	flags byte at +0x1c -- cross-confirming the header's bitfield
	order) and, when the return value is a retained object, releases
	it.  Written to those measured effects.  */
- (void)invalidate
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;

    instance->isInvalid = 1;
    if (instance->retainedRet &&
        instance->returnValue.type == NSObjCObjectType) {
        [instance->returnValue.value.objectValue release];
        instance->retainedRet = 0;
    }
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

/*
	NSCoding.  NSInvocation.h already declares conformance, so these
	are header-declared surface even though the reference's own
	encode/decode pair goes through more machinery (its decoder side
	builds the frame through _setArgFrame:, which is what keeps the
	decoded frame's ownership straight).
	*/

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    unsigned frameLength = [instance->signature frameLength];
    SEL selectorValue = [self selector];
    id targetValue = [self target];

    [aCoder encodeObject:instance->signature];
    [aCoder encodeValueOfObjCType:":" at:&selectorValue];
    [aCoder encodeObject:targetValue];
    [aCoder encodeArrayOfObjCType:"c" count:frameLength
                               at:instance->argumentFrame];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    NSInvocationInstance *instance;
    unsigned frameLength;
    void *frame;
    SEL selectorValue;
    id targetValue;

    self = [super init];
    instance = (NSInvocationInstance *)self;

    instance->signature = [[aDecoder decodeObject] retain];
    [aDecoder decodeValueOfObjCType:":" at:&selectorValue];
    targetValue = [aDecoder decodeObject];
    frameLength = [instance->signature frameLength];
    frame = NSZoneMalloc(0, frameLength);
    [aDecoder decodeArrayOfObjCType:"c" count:frameLength at:frame];
    [self _setArgFrame:frame];
    ((SEL *)frame)[1] = selectorValue;
    ((id *)frame)[0] = targetValue;
    instance->signatureValid = 1;
    instance->refCount = 1;
    return self;
}

- (void)encodeReturnValueWithCoder:(NSCoder *)aCoder
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSObjCValue value = [self _returnValue];

    [aCoder encodeValueOfObjCType:"i" at:&value.type];
    [aCoder encodeValueOfObjCType:
        [instance->signature methodReturnType] at:&value.value];
}

- (void)decodeReturnValueWithCoder:(NSCoder *)aCoder
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSObjCValue value;

    [aCoder decodeValueOfObjCType:"i" at:&value.type];
    [aCoder decodeValueOfObjCType:
        [instance->signature methodReturnType] at:&value.value];
    [self setReturnValue:&value.value];
}

/*	Undeclared; the reference's logging toggle is not a no-op -- its
	40-byte body increments a global counter when the flag is YES and
	decrements it when NO (a logging DEPTH, the same shape as
	NSException's +_enableLogging: from stage 2b).  Written exactly as
	measured; the counter's consumers live with NSPortCoder (stage 8).
	*/
static int __NSInvocationLoggingDepth;

+ (void)_enableLogging:(BOOL)flag
{
    if (flag)
        __NSInvocationLoggingDepth++;
    else
        __NSInvocationLoggingDepth--;
}

/*
	The coder-based construction path NSPortCoder (stage 8) uses to
	rebuild an NSInvocation on the receiving side of a distributed
	call.  The reference's real call graph, decoded:

	+_preInitWithCoder:... decodes signature, wire-signature validity,
	target, selector and arg count from the coder into OUT parameters
	(the method-list encoding is all pointers: ^@ ^c ^@ ^@ ^: ^I) and
	validates, raising through the fault path on a mismatch;

	+newInvocationWithCoder: drives it, allocates the instance with
	class_createInstance(self, frameLength) -- the argument frame is
	carved from the allocation's tail -- and hands the lot to

	-_postInitWithCoder:..., which stores the signature, sets the
	signatureValid bit (bit 2 of the flags byte at +0x1c, matching the
	header's bitfield order), and mallocs struct-return storage when
	the wire type says the return is compound.

	This stage has no NSPortCoder, so the wire FORMAT exercised here
	is this file's own -encodeWithCoder: stream through TestCoder; the
	reference's 1008-byte DO wire encoder and its exact preInit decode
	sequence arrive with stage 8.  The observable contract -- a decoded
	invocation with the right target, selector and arguments -- is what
	these tests pin, and what the reference's own path also delivers.
	*/
+ (id)_preInitWithCoder:(NSCoder *)aCoder signature:(NSMethodSignature **)sigOut
                  valid:(BOOL *)validOut wireSignature:(char **)wireOut
                 target:(id *)targetOut selector:(SEL *)selOut
               argCount:(unsigned *)countOut
{
    /*  The reference's preInit decodes the DO wire format its own
        1008-byte encoder produces (stage 8); this stage's wire is the
        -encodeWithCoder: stream above, so the decode order mirrors
        THAT -- signature object, selector, target -- with the arg
        count derived from the signature rather than a wire field.
        Validity is the reference's compare: the decoded signature
        must not be nil.  */
    *sigOut = [aCoder decodeObject];
    [aCoder decodeValueOfObjCType:":" at:selOut];
    [aCoder decodeValueOfObjCType:"@" at:targetOut];
    if (*sigOut != nil)
        *countOut = (unsigned)[*sigOut numberOfArguments];
    else
        *countOut = 0;
    *wireOut = NULL;
    *validOut = (*sigOut != nil);
    if (!*validOut)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: decoded a nil signature",
                            _NSMethodExceptionProem(self, _cmd)];
    return self;
}

- (id)_postInitWithCoder:(NSCoder *)aCoder signature:(NSMethodSignature *)aSignature
                   valid:(BOOL)valid wireSignature:(char *)wireSignature
                  target:(id)aTarget selector:(SEL)aSelector
                argCount:(unsigned)argCount
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;

    instance->signature = [aSignature retain];
    instance->signatureValid = valid ? 1 : 0;
    if (instance->argumentFrame == NULL) {
        unsigned frameLength = [aSignature frameLength];
        void *frame = NSZoneMalloc(0, frameLength);

        memset(frame, 0, frameLength);
        [self _setArgFrame:frame];
        instance->argumentFrame = frame;
    }
    ((id *)instance->argumentFrame)[0] = aTarget;
    ((SEL *)instance->argumentFrame)[1] = aSelector;
    return self;
}

+ (id)newInvocationWithCoder:(NSCoder *)aCoder
{
    NSMethodSignature *sig;
    BOOL valid;
    char *wire;
    id target;
    SEL selector;
    unsigned argCount;

    [self _preInitWithCoder:aCoder signature:&sig valid:&valid
              wireSignature:&wire target:&target selector:&selector
                   argCount:&argCount];

    return [[[self allocWithZone:NULL]
        _postInitWithCoder:aCoder signature:sig valid:valid
             wireSignature:wire target:target selector:selector
                  argCount:argCount] autorelease];
}

- (id)replacementObjectForPortCoder:(NSCoder *)aCoder
{
    return self;
}

/*
	Dispatch.  The reference's -invoke is the 1888-byte dispatcher and
	-invokeWithTarget: is its 60-byte front door (store the substitute
	receiver into frame slot 0, dispatch, done -- the stored target is
	not an ivar here because frame slots 0 and 4 ARE self and _cmd).
	The register-class switch is the plan's confirmed hypothesis: the
	reference's jump table over return types ends in indirect calls
	through objc_msgSendv cast to each return flavour, because this
	runtime declares no _stret variant.
	*/

- (void)invoke
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    const char *returnType;
    unsigned frameLength;
    id receiver;
    SEL op;

    if (instance->argumentFrame == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: argument frame is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }
    if (!instance->signatureValid) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: signature is invalid",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }

    receiver = ((id *)instance->argumentFrame)[0];
    op = ((SEL *)instance->argumentFrame)[1];
    if (receiver == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: target is nil",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }
    if (op == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: selector is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }

    frameLength = [instance->signature frameLength];
    returnType = [instance->signature methodReturnType];

    if (*returnType == 'v') {
        objc_msgSendv(receiver, op, frameLength, instance->argumentFrame);
        instance->returnValue.type = NSObjCVoidType;
        return;
    }

    if (*returnType == 'f' || *returnType == 'd') {
        /*  The FPU returns through ST(0): the caller's read width is
            all that differs, so call through a double-returning cast
            and store the return type's own size.  */
        double value;

        value = ((double (*)(id, SEL, unsigned, void *))objc_msgSendv)
            (receiver, op, frameLength, instance->argumentFrame);
        memcpy(&instance->returnValue.value, &value,
               (*returnType == 'd') ? sizeof(double) : sizeof(float));
        instance->returnValue.type =
            (enum _NSObjCValueType)*returnType;
        return;
    }

    if (*returnType == 'q' || *returnType == 'Q') {
        /*  EDX:EAX -- read the pair through a long-long cast.  */
        long long value;

        value = ((long long (*)(id, SEL, unsigned, void *))objc_msgSendv)
            (receiver, op, frameLength, instance->argumentFrame);
        memcpy(&instance->returnValue.value, &value, sizeof(long long));
        instance->returnValue.type =
            (enum _NSObjCValueType)*returnType;
        return;
    }

    if ((*returnType == '{' || *returnType == '(') &&
        ![instance->signature _isReturnStructInRegisters]) {
        /*  Compound return through the hidden pointer: this ABI puts
            the destination address at the frame's START, before self
            and _cmd.  Build frameLength + 4 bytes with the storage
            prepended and let objc_msgSendv pass the whole frame
            through; the callee stores through slot 0 and returns it.  */
        unsigned size = 0;
        char *shifted;
        unsigned result;
        NSObjCValue captured;

        NSGetSizeAndAlignment(returnType, &size, NULL);
        captured.value.structLocation = NSZoneMalloc(0, size);
        captured.type = (enum _NSObjCValueType)*returnType;
        shifted = (char *)NSZoneMalloc(0, frameLength + 4);
        memcpy(shifted + 4, instance->argumentFrame, frameLength);
        memcpy(shifted, &captured.value.structLocation, sizeof(void *));
        result = (unsigned)objc_msgSendv(receiver, op, frameLength + 4,
                                         shifted);
        NSZoneFree(0, shifted);
        instance->returnValue = captured;
        return;
    }

    /*  Everything else -- id, Class, SEL, pointer, char, short, int,
        long, and structs of 1/2/4/8 bytes the ABI returns in
        registers -- is read through the widest cast and copied by
        the return type's own size.  */
    {
        unsigned long long value;
        unsigned size = 0;

        value = ((unsigned long long (*)(id, SEL, unsigned, void *))
                 objc_msgSendv)(receiver, op, frameLength,
                                instance->argumentFrame);
        NSGetSizeAndAlignment(returnType, &size, NULL);
        if (size > sizeof(value))
            size = sizeof(value);
        memcpy(&instance->returnValue.value, &value, size);
        instance->returnValue.type =
            (enum _NSObjCValueType)*returnType;
    }
}

- (void)invokeWithTarget:(id)aTarget
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;

    if (aTarget == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: target is nil",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }

    /*  The reference's 60-byte body is exactly these two sends: store
        the substitute receiver into frame slot 0 and dispatch.  The
        substitute REMAINS the invocation's target afterwards -- there
        is no restore in the reference and none here, matching the
        documented NeXT behaviour that -invokeWithTarget: changes the
        receiver's target.  */
    [self setArgument:&aTarget atIndex:0];
    [self invoke];
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
