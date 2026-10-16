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
#import <Foundation/NSData.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <objc/objc-class.h>
/*  struct objc_method_description is defined here, not in objc-class.h.  */
#import <objc/Protocol.h>
#import <objc/objc-runtime.h>
#include <string.h>

/*	NSException.m exports this beside the public raise path; no header
	declares it, so this file carries the declaration.  */
extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern unsigned _NSParseAndRelease(const char *type, void *value);
extern unsigned _NSParseAndRetain(const char *type, void *value);
extern unsigned _NSParseAndAutorelease(const char *type, void *value);
extern void _NSIncrementInternalRefCount(id object, unsigned *refCount,
                                         int mask, id lock);
extern BOOL _NSDecrementInternalRefCountWasZero(id object,
                                                unsigned *refCount,
                                                int mask, id lock);
extern unsigned _NSInternalRefCount(id object, unsigned refCount, int mask);
#if !defined(__ppc__) && !defined(__POWERPC__)
extern void *_structure_addr(void);
#endif
static int __NSInvocationLoggingDepth;

/*	NSMethodSignature.m exposes its per-argument cache through this
	undeclared accessor; Task 1 measured the reference's own layout
	(entry +8 holds the type pointer) and this accessor is the
	reconstruction's cross-module stand-in for what the reference does
	by reaching into the signature's cache directly (index*20 off its
	_parmInfoP, rep movsd x5).  */
/*	The by-value entry shape, identical to NSMethodSignature.m's own
	anonymous typedef (no shared header declares it; the tag-only
	`struct _arginfo` pointer field is what makes the compiled encoding
	read ^{_arginfo} like the reference's).  */
struct _arginfo;

typedef struct {
    int		offset;
    int		size;
    const char	*type;
    struct _arginfo *unused0;
    int		unused1;
} NSMethodSignatureArgumentInfo;
@interface NSMethodSignature (NSInvocationSupport)
- (BOOL)_isReturnStructInRegisters;
@end

@interface NSObject (NSInvocationForwarding)
- (BOOL)willForwardSelector:(SEL)selector;
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

/*	NSMethodSignature's private layout; _types is at +4 and _fixup at +24
	on both target ABIs.  */
typedef struct {
    Class isa;
    const char *types;
    int numberOfArguments;
    unsigned parameterSize;
    unsigned returnValueLength;
    NSMethodSignatureArgumentInfo *argumentInfo;
    int *fixup;
    void *reserved;
} NSInvocationMethodSignatureLayout;

/*	The target sets externalArgFrame only when argumentFrame is a separate
	zone allocation that dealloc must free.  A factory-installed tail frame
	belongs to the invocation allocation and leaves this bit clear.  */
static void NSInvocationEstablishArgumentFrame(NSInvocation *invocation)
{
    NSInvocationInstance *instance = (NSInvocationInstance *)invocation;
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    unsigned frameLength = signature->parameterSize;

    instance->argumentFrame = NSZoneMalloc([invocation zone], frameLength);
    memset(instance->argumentFrame, 0, frameLength);
    instance->externalArgFrame = 1;
}

static void NSInvocationCallWithStructReturn(void *returnLocation,
                                             id receiver,
                                             SEL selector,
                                             unsigned dispatchSize,
                                             void *argumentFrame)
{
    /*  The targets use the platform's hidden-result register, then pass
        objc_msgSendv's ordinary four arguments in their normal positions.  */
#if defined(__ppc__) || defined(__POWERPC__)
    register void *resultRegister __asm__("r3") = returnLocation;
    register id receiverRegister __asm__("r4") = receiver;
    register SEL selectorRegister __asm__("r5") = selector;
    register unsigned lengthRegister __asm__("r6") = dispatchSize;
    register void *frameRegister __asm__("r7") = argumentFrame;
    register unsigned long sendRegister __asm__("r12") =
        (unsigned long)objc_msgSendv;

    __asm__ volatile("mtctr %5\n\tbctrl"
        : "+r"(resultRegister), "+r"(receiverRegister),
          "+r"(selectorRegister), "+r"(lengthRegister),
          "+r"(frameRegister), "+r"(sendRegister)
        :
        : "r0", "r8", "r9", "r10", "r11", "ctr", "lr", "xer",
          "cr0", "cr1", "cr5", "memory", "f0", "f1", "f2", "f3",
          "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11",
          "f12", "f13");
#else
    register void *resultRegister __asm__("ebx") = returnLocation;
    register void *frameRegister __asm__("eax") = argumentFrame;
    register unsigned lengthRegister __asm__("ecx") = dispatchSize;
    register SEL selectorRegister __asm__("edx") = selector;
    register id receiverRegister __asm__("esi") = receiver;
    register unsigned long sendRegister __asm__("edi") =
        (unsigned long)objc_msgSendv;

    __asm__ volatile("pushl %%eax\n\t"
                     "pushl %%ecx\n\t"
                     "pushl %%edx\n\t"
                     "pushl %%esi\n\t"
                     "call *%%edi\n\t"
                     "addl $16, %%esp"
        : "+b"(resultRegister), "+a"(frameRegister),
          "+c"(lengthRegister), "+d"(selectorRegister),
          "+S"(receiverRegister), "+D"(sendRegister)
        :
        : "memory", "cc");
#endif
}

static void NSInvocationInitializeReturnValue(NSInvocationInstance *instance)
{
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    const char *returnType = signature->types;

    if (*returnType == 'r')
        returnType++;
    switch (*returnType) {
        case '#':
        case '@':
        case 'O':
        case 'R':
            instance->returnValue.type = NSObjCObjectType;
            break;
        case '$':
        case 'C':
        case 'c':
            instance->returnValue.type = NSObjCCharType;
            break;
        case '%':
        case '*':
            instance->returnValue.type = NSObjCStringType;
            break;
        case ':':
            instance->returnValue.type = NSObjCSelectorType;
            break;
        case 'I':
        case 'L':
        case 'i':
        case 'l':
            instance->returnValue.type = NSObjCLongType;
            break;
        case 'Q':
        case 'q':
            instance->returnValue.type = NSObjCLonglongType;
            break;
        case 'S':
        case 's':
            instance->returnValue.type = NSObjCShortType;
            break;
        case 'V':
        case 'v':
            instance->returnValue.type = NSObjCVoidType;
            break;
        case '^':
            instance->returnValue.type = NSObjCPointerType;
            break;
        case 'd':
            instance->returnValue.type = NSObjCDoubleType;
            break;
        case 'f':
            instance->returnValue.type = NSObjCFloatType;
            break;
        case '{':
            instance->returnValue.type = NSObjCStructType;
            instance->returnValue.value.structLocation =
                NSZoneMalloc(NULL, signature->returnValueLength);
            memset(instance->returnValue.value.structLocation, 0,
                   signature->returnValueLength);
            break;
        default:
            [NSException raise:NSInternalInconsistencyException
                        format:@"*** unknown return type encoding '%c'",
                               *returnType];
            break;
    }
}

static const char *NSInvocationSkipQualifiers(const char *type)
{
    while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' ||
           *type == 'O' || *type == 'R' || *type == 'V')
        type++;
    return type;
}

#if defined(__ppc__) || defined(__POWERPC__)
static void NSInvocationReleasePointers(
    NSMethodSignatureArgumentInfo *info, void *frame)
{
    const char *type = NSInvocationSkipQualifiers(info->type);
    void *value = (char *)frame + info->offset;

    if (*type == '@') {
        id object = *(id *)value;

        [object release];
    } else if (*type == '*') {
        void *string = *(void **)value;

        if (string != NULL)
            NSZoneFree(NSZoneFromPointer(string), string);
    } else if (info->unused0 != NULL) {
        NSMethodSignatureArgumentInfo *children =
            (NSMethodSignatureArgumentInfo *)info->unused0;
        int index;

        for (index = 0; index < info->unused1; index++)
            NSInvocationReleasePointers(&children[index], frame);
    }
}

static void NSInvocationRetainPointers(
    NSMethodSignatureArgumentInfo *info, void *frame)
{
    const char *type = NSInvocationSkipQualifiers(info->type);
    void *value = (char *)frame + info->offset;

    if (*type == '@') {
        id object = *(id *)value;

        [object retain];
    } else if (*type == '*') {
        const char *string = *(const char **)value;

        if (string != NULL) {
            unsigned length = (unsigned)strlen(string) + 1;
            char *copy = NSZoneMalloc(NULL, length);

            memmove(copy, string, length);
            *(char **)value = copy;
        }
    } else if (info->unused0 != NULL) {
        NSMethodSignatureArgumentInfo *children =
            (NSMethodSignatureArgumentInfo *)info->unused0;
        int index;

        for (index = 0; index < info->unused1; index++)
            NSInvocationRetainPointers(&children[index], frame);
    }
}

static void NSInvocationScatterStruct(
    void **source, NSMethodSignatureArgumentInfo *info, void *frame)
{
    if (info->unused0 != NULL) {
        NSMethodSignatureArgumentInfo *children =
            (NSMethodSignatureArgumentInfo *)info->unused0;
        int index;

        for (index = 0; index < info->unused1; index++)
            NSInvocationScatterStruct(source, &children[index], frame);
    } else {
        memmove((char *)frame + info->offset, *source, info->size);
        *source = (char *)*source + info->size;
    }
}

static void NSInvocationGatherStruct(
    void **destination, NSMethodSignatureArgumentInfo *info, void *frame)
{
    if (info->unused0 != NULL) {
        NSMethodSignatureArgumentInfo *children =
            (NSMethodSignatureArgumentInfo *)info->unused0;
        int index;

        for (index = 0; index < info->unused1; index++)
            NSInvocationGatherStruct(destination, &children[index], frame);
    } else {
        memmove(*destination, (char *)frame + info->offset, info->size);
        *destination = (char *)*destination + info->size;
    }
}
#endif

/*  PPC's coder path walks the signature's nested argument records after
    decoding a pointer pointee, autoreleasing object slots in that value.  */
#if defined(__ppc__) || defined(__POWERPC__)
static void NSInvocationAutoreleasePointers(
    NSMethodSignatureArgumentInfo *info, void *frame)
{
    const char *type = NSInvocationSkipQualifiers(info->type);

    if (*type == '@') {
        id *object = (id *)((char *)frame + info->offset);
        [*object autorelease];
    } else if (*type != '*' && info->unused0 != NULL && info->unused1 > 0) {
        NSMethodSignatureArgumentInfo *children =
            (NSMethodSignatureArgumentInfo *)info->unused0;
        int index;

        for (index = 0; index < info->unused1; index++)
            NSInvocationAutoreleasePointers(&children[index], frame);
    }
}
#endif

@interface NSInvocation (NSInvocationCoderSupport)
+ (void)_preInitWithCoder:(NSCoder *)coder
                 signature:(NSMethodSignature **)signature
                     valid:(BOOL *)valid
              wireSignature:(NSMethodSignature **)wireSignature
                    target:(id *)target selector:(SEL *)selector
                  argCount:(unsigned *)argCount;
- (id)_postInitWithCoder:(NSCoder *)coder
               signature:(NSMethodSignature *)signature
                   valid:(BOOL)valid
            wireSignature:(NSMethodSignature *)wireSignature
                  target:(id)target selector:(SEL)selector
                argCount:(unsigned)argCount;
@end

@implementation NSInvocation

+ (void)_enableLogging:(char)enabled
{
    if (enabled)
        __NSInvocationLoggingDepth++;
    else
        __NSInvocationLoggingDepth--;
}

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig
{
#if defined(__ppc__) || defined(__POWERPC__)
    return [[self newInvocationWithMethodSignature:sig] autorelease];
#else
    unsigned parameterSize =
        ((NSInvocationMethodSignatureLayout *)sig)->parameterSize;
    id invocation = NSAllocateObject(self, parameterSize, NULL);

    if (invocation != nil) {
        NSInvocationInstance *instance = (NSInvocationInstance *)invocation;

        instance->argumentFrame = (char *)invocation +
            instance->isa->instance_size;
    }
    return [[invocation initWithMethodSignature:sig] autorelease];
#endif
}

#if defined(__ppc__) || defined(__POWERPC__)
+ (NSInvocation *)newInvocationWithMethodSignature:(NSMethodSignature *)sig
{
    unsigned parameterSize =
        ((NSInvocationMethodSignatureLayout *)sig)->parameterSize;
    id invocation = NSAllocateObject(self, parameterSize, NULL);

    if (invocation != nil) {
        NSInvocationInstance *instance = (NSInvocationInstance *)invocation;

        instance->argumentFrame = (char *)invocation +
            instance->isa->instance_size;
    }
    return [invocation initWithMethodSignature:sig];
}
#endif

/*	Not declared by NSInvocation.h, but the only structural candidate
	for +invocationWithMethodSignature:'s own body -- the reference
	shows exactly this two-step alloc/init handoff, the same shape
	+[NSException exceptionWithName:reason:userInfo:] and
	+[NSAutoreleasePool alloc] both already use.  */
- (id)initWithMethodSignature:(NSMethodSignature *)sig
{
    NSInvocationInstance *instance;

    if (sig == nil) {
        [super dealloc];
        return nil;
    }
    instance = (NSInvocationInstance *)self;

    instance->signature = [sig retain];
    if (instance->argumentFrame == NULL)
        NSInvocationEstablishArgumentFrame(self);
    NSInvocationInitializeReturnValue(instance);
    return self;
}

- (void)dealloc
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;

    [self invalidate];
    if (instance->container != nil)
        [instance->container release];
    if (instance->externalArgFrame)
        NSZoneFree(NULL, instance->argumentFrame);
    [instance->signature release];
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
    SEL selector;

    [self getArgument:&selector atIndex:1];
    return selector;
}

- (void)setSelector:(SEL)aSelector
{
    [self setArgument:&aSelector atIndex:1];
}

- (id)target
{
    id target;

    [self getArgument:&target atIndex:0];
    return target;
}

- (void)setTarget:(id)aTarget
{
    [self setArgument:&aTarget atIndex:0];
}

- (NSMethodSignature *)methodSignature
{
    return ((NSInvocationInstance *)self)->signature;
}

/*	Retain the target and object-bearing arguments already in the frame.
	The signature's nested argument records describe object and C-string
	slots inside aggregate arguments.  */
- (void)retainArguments
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    unsigned count;
    unsigned index;
    id target;

    if (instance->retainedArgs)
        return;
    instance->retainedArgs = 1;
    count = (unsigned)
        ((NSInvocationMethodSignatureLayout *)instance->signature)
            ->numberOfArguments;
    target = [self target];
    [target retain];
    for (index = 2; index < count; index++) {
        NSMethodSignatureArgumentInfo info =
            ((NSInvocationMethodSignatureLayout *)instance->signature)
                ->argumentInfo[index];
#if defined(__ppc__) || defined(__POWERPC__)
        NSInvocationRetainPointers(&info, instance->argumentFrame);
#else
        _NSParseAndRetain(info.type,
                          (char *)instance->argumentFrame + info.offset);
#endif
    }
}

- (BOOL)argumentsRetained
{
    return ((NSInvocationInstance *)self)->retainedArgs ? YES : NO;
}

/*	Undeclared validity bit set by the coder path. The paired -invoke
	bodies do not inspect it; keep the accessor for the source's private
	compatibility surface without adding a dispatch guard.  */
- (BOOL)_signatureValid
{
    return ((NSInvocationInstance *)self)->signatureValid ? YES : NO;
}

/*	Undeclared; copies a caller-supplied frame into the invocation's
	existing storage.  The caller retains ownership of its input frame.  */
- (void)_setArgFrame:(void *)frame
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;

#if defined(__ppc__) || defined(__POWERPC__)
    memmove(instance->argumentFrame, frame,
            ((NSInvocationMethodSignatureLayout *)instance->signature)
                ->parameterSize);
#else
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    unsigned index;

    for (index = 0; index < (unsigned)signature->numberOfArguments; index++) {
        NSMethodSignatureArgumentInfo info =
            signature->argumentInfo[index];
        int offset = (signature->fixup != NULL) ? signature->fixup[index] : 0;
        void *argument = (char *)frame + info.offset;

        if (offset != 0)
            argument = *(void **)((char *)frame + offset);
        [self setArgument:argument atIndex:(int)index];
    }
#endif
}

/*	Bare initialization deallocates the receiver and returns nil;
	NSInvocation instances are created through
	+invocationWithMethodSignature: or the coder path.  */
- (id)init
{
    [super dealloc];
    return nil;
}

/*	The reference's -invalidate sets isInvalid, releases retained object
	returns, frees typed pointer, C-string, and compound return storage, then
	releases retained arguments. i386 also parses typed pointers and structs
	for object cleanup; PPC frees their return storage directly.	*/
- (void)invalidate
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    const char *returnType;

    if (instance->isInvalid)
        return;
    instance->isInvalid = 1;
    if (instance->returnValue.type == NSObjCObjectType) {
        if (instance->retainedRet)
            [instance->returnValue.value.objectValue release];
        instance->retainedRet = 0;
    }
    if (instance->returnValue.type == NSObjCPointerType &&
        instance->returnValue.value.pointerValue != NULL) {
        returnType = NSInvocationSkipQualifiers(
            ((NSInvocationMethodSignatureLayout *)instance->signature)->types)
            + 1;
        if (*returnType != 'v') {
#if !defined(__ppc__) && !defined(__POWERPC__)
            _NSParseAndRelease(returnType,
                               instance->returnValue.value.pointerValue);
#endif
            NSZoneFree(NULL, instance->returnValue.value.pointerValue);
            instance->returnValue.value.pointerValue = NULL;
        }
    }
    if (instance->returnValue.type == NSObjCStructType) {
#if !defined(__ppc__) && !defined(__POWERPC__)
        _NSParseAndRelease(
            ((NSInvocationMethodSignatureLayout *)instance->signature)->types,
            instance->returnValue.value.structLocation);
#endif
        NSZoneFree(NULL, instance->returnValue.value.structLocation);
        instance->returnValue.value.structLocation = NULL;
    }
    if (instance->returnValue.type == NSObjCStringType &&
        instance->returnValue.value.cStringLocation != NULL) {
        NSZoneFree(NULL, instance->returnValue.value.cStringLocation);
        instance->returnValue.value.cStringLocation = NULL;
    }
    if (instance->retainedArgs) {
        unsigned index = (unsigned)
            ((NSInvocationMethodSignatureLayout *)instance->signature)
                ->numberOfArguments;

        while (index > 0) {
            NSMethodSignatureArgumentInfo info =
                ((NSInvocationMethodSignatureLayout *)instance->signature)
                    ->argumentInfo[--index];
#if defined(__ppc__) || defined(__POWERPC__)
            NSInvocationReleasePointers(&info, instance->argumentFrame);
#else
            _NSParseAndRelease(info.type,
                               (char *)instance->argumentFrame + info.offset);
#endif
        }
    }
}

/*	NSInvocation carries its own 24-bit count (the header's refCount
	bitfield) rather than NSObject's side table -- confirmed from the
	header's declared layout; the plan's tests pin the behaviour.  */
- (id)retain
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    unsigned refCount = instance->refCount;

    _NSIncrementInternalRefCount(self, &refCount, 0xFFFFFF, NULL);
    instance->refCount = refCount;
    return self;
}

- (void)release
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    unsigned refCount = instance->refCount;

    if (_NSDecrementInternalRefCountWasZero(self, &refCount, 0xFFFFFF,
                                            NULL))
        [self dealloc];
    else
        instance->refCount = refCount;
}

- (unsigned)retainCount
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;

    return _NSInternalRefCount(self, instance->refCount, 0xFFFFFF);
}

/*	Undeclared; hands back the whole tagged return-value struct rather
	than copying just its bytes the way -getReturnValue: does.  Task
	7's -encodeReturnValueWithCoder: uses this to know which union
	member to encode.  */
- (NSObjCValue)_returnValue
{
    return ((NSInvocationInstance *)self)->returnValue;
}

/*	The target checks argumentLocation for NULL in setArgument: only.
	getArgument: and setReturnValue: use the pointer without a NULL guard;
	getReturnValue: forwards it to getArgument:.  Bounds match the
	reference's own check: -1 through nargs-1 for getArgument: and
	setArgument:, where -1 names the return value.  */

- (void)getArgument:(void *)argumentLocation atIndex:(int)index
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    NSMethodSignatureArgumentInfo info;
    unsigned size;

    if (instance->argumentFrame == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: argument frame is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }
    /*  The reference's own pair of comparisons: -1 <= index AND
        index < nargs (its jl/jg around cmp [edx+8], ecx).  Both sides
        compared as signed -- the usual int/unsigned promotion would
        wrap the -1 index to UINT_MAX and reject the return value.  */
    if (index < -1 || index >= signature->numberOfArguments) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: index (%d) out of bounds",
                            _NSMethodExceptionProem(self, _cmd), index];
        return;
    }

    if (index == -1) {
        const void *source;

        switch (instance->returnValue.type) {
        case NSObjCCharType:
            source = &instance->returnValue.value.charValue;
            size = sizeof(instance->returnValue.value.charValue);
            break;
        case NSObjCShortType:
            source = &instance->returnValue.value.shortValue;
            size = sizeof(instance->returnValue.value.shortValue);
            break;
        case NSObjCLongType:
            source = &instance->returnValue.value.longValue;
            size = sizeof(instance->returnValue.value.longValue);
            break;
        case NSObjCLonglongType:
            source = &instance->returnValue.value.longlongValue;
            size = sizeof(instance->returnValue.value.longlongValue);
            break;
        case NSObjCFloatType:
            source = &instance->returnValue.value.floatValue;
            size = sizeof(instance->returnValue.value.floatValue);
            break;
        case NSObjCDoubleType:
            source = &instance->returnValue.value.doubleValue;
            size = sizeof(instance->returnValue.value.doubleValue);
            break;
        case NSObjCSelectorType:
            source = &instance->returnValue.value.selectorValue;
            size = sizeof(instance->returnValue.value.selectorValue);
            break;
        case NSObjCObjectType:
            source = &instance->returnValue.value.objectValue;
            size = sizeof(instance->returnValue.value.objectValue);
            break;
        case NSObjCPointerType:
            source = &instance->returnValue.value.pointerValue;
            size = sizeof(instance->returnValue.value.pointerValue);
            break;
        case NSObjCStringType:
            source = &instance->returnValue.value.cStringLocation;
            size = sizeof(instance->returnValue.value.cStringLocation);
            break;
        case NSObjCStructType:
            source = instance->returnValue.value.structLocation;
            size = signature->returnValueLength;
            break;
        default:
            [NSException raise:NSInternalInconsistencyException
                        format:@"*** unknown return type %u",
                               (unsigned)instance->returnValue.type];
            return;
        }
        memmove(argumentLocation, source, size);
        return;
    }

    info = signature->argumentInfo[index];
#if defined(__ppc__) || defined(__POWERPC__)
    if (*NSInvocationSkipQualifiers(info.type) == '{') {
        void *destination = argumentLocation;

        NSInvocationGatherStruct(&destination, &info, instance->argumentFrame);
    } else if (*NSInvocationSkipQualifiers(info.type) == 'f' &&
               info.size == 8) {
        *(float *)argumentLocation =
            *(double *)((char *)instance->argumentFrame + info.offset);
    } else {
        memmove(argumentLocation,
                (char *)instance->argumentFrame + info.offset, info.size);
    }
#else
    memmove(argumentLocation,
            (char *)instance->argumentFrame + info.offset, info.size);
#endif
}

- (void)setArgument:(void *)argumentLocation atIndex:(int)index
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    NSMethodSignatureArgumentInfo info;

    if (instance->argumentFrame == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: argument frame is NULL",
                            _NSMethodExceptionProem(self, _cmd)];
        return;
    }
    if (argumentLocation == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"setArgument not supplied with pointer to location"];
        return;
    }
    if (index < -1 || index >= signature->numberOfArguments) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: index (%d) out of bounds",
                            _NSMethodExceptionProem(self, _cmd), index];
        return;
    }

    if (index == -1) {
        [self setReturnValue:argumentLocation];
        return;
    }

    info = signature->argumentInfo[index];
#if defined(__ppc__) || defined(__POWERPC__)
    if (instance->retainedArgs)
        NSInvocationReleasePointers(&info, instance->argumentFrame);
    if (*NSInvocationSkipQualifiers(info.type) == '{') {
        void *source = argumentLocation;

        NSInvocationScatterStruct(&source, &info, instance->argumentFrame);
    } else if (*NSInvocationSkipQualifiers(info.type) == 'f' &&
               info.size == 8) {
        *(double *)((char *)instance->argumentFrame + info.offset) =
            *(float *)argumentLocation;
    } else {
        memmove((char *)instance->argumentFrame + info.offset,
                argumentLocation, info.size);
    }
    if (__NSInvocationLoggingDepth != 0)
        NSLog(@"Invocation %x setArgument:(%x) atIndex:%d to frame offset %x",
              self, *(unsigned *)argumentLocation, index, info.offset);
    if (instance->retainedArgs)
        NSInvocationRetainPointers(&info, instance->argumentFrame);
#else
    if (instance->retainedArgs)
        _NSParseAndRelease(info.type,
                           (char *)instance->argumentFrame + info.offset);
    memmove((char *)instance->argumentFrame + info.offset,
            argumentLocation, info.size);
    if (instance->retainedArgs)
        _NSParseAndRetain(info.type,
                          (char *)instance->argumentFrame + info.offset);
#endif
}

- (void)getReturnValue:(void *)retLoc
{
    /* Both target bodies forward to getArgument:atIndex: with index -1,
       which identifies the return value. */
    [self getArgument:retLoc atIndex:-1];
}

- (void)setReturnValue:(void *)retLoc
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    unsigned size = signature->returnValueLength;
    const char *returnType = NSInvocationSkipQualifiers(signature->types);
    void *storage;

    if (instance->returnValue.type == NSObjCObjectType) {
        id value = *(id *)retLoc;

        if (instance->retainedRet)
            [instance->returnValue.value.objectValue release];
        instance->returnValue.value.objectValue = value;
        [value retain];
        instance->retainedRet = 1;
        return;
    }

    switch (instance->returnValue.type) {
    case NSObjCCharType:
        size = sizeof(instance->returnValue.value.charValue);
        break;
    case NSObjCShortType:
        size = sizeof(instance->returnValue.value.shortValue);
        break;
    case NSObjCLongType:
        size = sizeof(instance->returnValue.value.longValue);
        break;
    case NSObjCLonglongType:
        size = sizeof(instance->returnValue.value.longlongValue);
        break;
    case NSObjCFloatType:
        size = sizeof(instance->returnValue.value.floatValue);
        break;
    case NSObjCDoubleType:
        size = sizeof(instance->returnValue.value.doubleValue);
        break;
    case NSObjCSelectorType:
        size = sizeof(instance->returnValue.value.selectorValue);
        break;
    case NSObjCStringType: {
        const char *value = *(const char **)retLoc;
        char *copy = NULL;

        if (instance->returnValue.value.cStringLocation != NULL)
            NSZoneFree(NULL, instance->returnValue.value.cStringLocation);
        if (value != NULL) {
            size = (unsigned)strlen(value) + 1;
            copy = NSZoneMalloc(NULL, size);
            memmove(copy, value, size);
        }
        instance->returnValue.value.cStringLocation = copy;
        return;
    }
    case NSObjCPointerType:
        returnType++;
        if (*returnType == 'v') {
            instance->returnValue.value.pointerValue = *(void **)retLoc;
            return;
        }
        storage = instance->returnValue.value.pointerValue;
        if (*(void **)retLoc == NULL) {
            if (storage != NULL)
                NSZoneFree(NULL, storage);
            instance->returnValue.value.pointerValue = NULL;
            return;
        }
        NSGetSizeAndAlignment(returnType, &size, NULL);
        if (storage == NULL)
            storage = NSZoneMalloc(NULL, size);
        memmove(storage, *(void **)retLoc, size);
        instance->returnValue.value.pointerValue = storage;
        return;
    case NSObjCStructType:
        storage = instance->returnValue.value.structLocation;
        if (storage == NULL)
            storage = NSZoneMalloc(NULL, size);
        memmove(storage, retLoc, size);
        instance->returnValue.value.structLocation = storage;
        return;
    default:
        [NSException raise:NSInternalInconsistencyException
                    format:@"*** unknown return type %u",
                           (unsigned)instance->returnValue.type];
        return;
    }

    if (size != 0)
        memmove(&instance->returnValue.value, retLoc, size);
}

static void NSInvocationEncodeArgumentRecords(
    NSInvocation *invocation, NSInvocationInstance *instance, NSCoder *coder,
    SEL selector, BOOL validateOffsets)
{
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    BOOL logArgumentEncoding = (selector == @selector(encodeWithCoder:));
    unsigned index;

#if defined(__ppc__) || defined(__POWERPC__)
    (void)validateOffsets;
#endif
    for (index = 2; index < (unsigned)signature->numberOfArguments; index++) {
        NSMethodSignatureArgumentInfo info =
            signature->argumentInfo[index];
        void *argument;
        if (logArgumentEncoding && __NSInvocationLoggingDepth != 0)
            NSLog(@"encodeWithCoder: type=%s\n", info.type);
#if !defined(__ppc__) && !defined(__POWERPC__)
        if (validateOffsets && info.offset == 0)
            [NSException raise:NSInternalInconsistencyException
                        format:@"%s cannot extract %d argument for type desc %s\n",
                               sel_getName(selector), index, info.type];
#endif
#if defined(__ppc__) || defined(__POWERPC__)
        char *scratch = __builtin_alloca(info.size + 15);
        argument = (void *)(((unsigned long)scratch + 15UL) & ~15UL);
        [invocation getArgument:argument atIndex:(int)index];
        if (logArgumentEncoding && __NSInvocationLoggingDepth != 0)
            NSLog(@"encoding argument type=%s", info.type);
#else
        argument = (char *)instance->argumentFrame + info.offset;
#endif
        if (*NSInvocationSkipQualifiers(info.type) == '^') {
            void *pointee = *(void **)argument;
            char isNull = (pointee == NULL);

            [coder encodeValueOfObjCType:"c" at:&isNull];
            if (logArgumentEncoding && __NSInvocationLoggingDepth != 0)
                NSLog(@"encoding pointer argument type=%s (isNull=%d)",
                      info.type, isNull);
            if (!isNull)
                [coder encodeValueOfObjCType:
                    NSInvocationSkipQualifiers(info.type) + 1 at:pointee];
#if defined(__ppc__) || defined(__POWERPC__)
            if (!isNull && logArgumentEncoding &&
                __NSInvocationLoggingDepth != 0)
                NSLog(@"encoded value pointed to with type %s",
                      NSInvocationSkipQualifiers(info.type) + 1);
#endif
        } else {
            [coder encodeValueOfObjCType:info.type at:argument];
        }
    }
}

static void NSInvocationDecodeArgumentRecords(
    NSInvocation *invocation, NSInvocationInstance *instance, NSCoder *coder,
    NSMethodSignature *signature, unsigned argCount, BOOL logArguments)
{
    unsigned index;

    for (index = 2; index < argCount; index++) {
        NSMethodSignatureArgumentInfo info =
            ((NSInvocationMethodSignatureLayout *)signature)
                ->argumentInfo[index];
        const char *type = NSInvocationSkipQualifiers(info.type);
        void *argument;
        void *pointee = NULL;

        if (*type == '^') {
            char isNull = 1;
            unsigned size;

            [coder decodeValueOfObjCType:"c" at:&isNull];
#if defined(__ppc__) || defined(__POWERPC__)
            if (logArguments && __NSInvocationLoggingDepth != 0)
                NSLog(@"decoded pointer argument type=%s (isNull=%d)",
                      info.type, isNull);
#endif
            if (!isNull) {
                NSMutableData *data;

                NSGetSizeAndAlignment(type + 1, &size, NULL);
#if !defined(__ppc__) && !defined(__POWERPC__)
                if (size == 0)
                    [NSException raise:NSInternalInconsistencyException
                                format:@"bad size for type %s\n", type + 1];
#endif
                data = [[NSMutableData allocWithZone:NULL]
                    initWithLength:size];
                if (instance->container == nil)
                    instance->container = [[NSMutableArray allocWithZone:NULL]
                        init];
                [instance->container addObject:data];
                [data release];
                pointee = [data mutableBytes];
#if !defined(__ppc__) && !defined(__POWERPC__)
                *(void **)((char *)instance->argumentFrame + info.offset) =
                    pointee;
#endif
                [coder decodeValueOfObjCType:type + 1 at:pointee];
#if defined(__ppc__) || defined(__POWERPC__)
                if (logArguments && __NSInvocationLoggingDepth != 0)
                    NSLog(@"decoded value pointed to with type %s to address 0x%x",
                          type + 1, pointee);
#endif
#if defined(__ppc__) || defined(__POWERPC__)
                NSInvocationAutoreleasePointers(&info,
                                                instance->argumentFrame);
#else
                _NSParseAndAutorelease(type + 1, pointee);
#endif
            }
#if defined(__ppc__) || defined(__POWERPC__)
            argument = &pointee;
#endif
        } else {
#if defined(__ppc__) || defined(__POWERPC__)
            char *storage = __builtin_alloca(info.size + 15);
            argument = (void *)(((unsigned long)storage + 15UL) & ~15UL);
#else
            argument = (char *)instance->argumentFrame + info.offset;
#endif
            [coder decodeValueOfObjCType:info.type at:argument];
        }

#if defined(__ppc__) || defined(__POWERPC__)
        instance->retainedArgs = 0;
        [invocation setArgument:argument atIndex:(int)index];
        instance->retainedArgs = 1;
#endif
        if (logArguments && __NSInvocationLoggingDepth != 0) {
#if defined(__ppc__) || defined(__POWERPC__)
            NSLog(@"[NSInvocation initWithCoder: decoded argument type=%s]",
                  info.type);
#else
            NSLog(@"[NSInvocation initWithCoder: decoded argument type=%s",
                  info.type);
#endif
        }
#if defined(__ppc__) || defined(__POWERPC__)
        if (logArguments && __NSInvocationLoggingDepth != 0 &&
            *info.type == ':')
            NSLog(@"the argument is selector '%s'", *(char **)argument);
#endif
    }
}

/*  Distributed-object coding uses a target/signature header followed by
    typed argument records.  The local coder stream from the earlier frame
    reconstruction is not the format used by NSPortCoder.  */

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    unsigned argCount = (unsigned)signature->numberOfArguments;
    SEL selectorValue = [self selector];
    id targetValue = [self target];
    const char *wireTypes = signature->types;

    if (__NSInvocationLoggingDepth != 0)
        NSLog(@"encodeWithCoder:onto: type=%s nargs %d\n",
              wireTypes, argCount);
    [aCoder encodeValueOfObjCType:"@" at:&targetValue];
    [aCoder encodeValueOfObjCType:"I" at:&argCount];
    [aCoder encodeValueOfObjCType:":" at:&selectorValue];
    [aCoder encodeValueOfObjCType:"*" at:&wireTypes];
    [aCoder encodeValueOfObjCType:"i" at:&instance->returnValue.type];
    NSInvocationEncodeArgumentRecords(self, instance, aCoder, _cmd, YES);
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSMethodSignature *signature;
    NSMethodSignature *wireSignature;
    BOOL valid;
    id target;
    SEL selector;
    unsigned argCount;

    [instance->isa _preInitWithCoder:aDecoder signature:&signature
                                valid:&valid wireSignature:&wireSignature
                               target:&target selector:&selector
                             argCount:&argCount];
    return [self _postInitWithCoder:aDecoder signature:signature valid:valid
                      wireSignature:wireSignature target:target
                           selector:selector argCount:argCount];
}

- (void)encodeReturnValueWithCoder:(NSCoder *)aCoder
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    const char *returnType;
    void *returnValue;

    if (instance->returnValue.type != NSObjCVoidType) {
        returnType =
            ((NSInvocationMethodSignatureLayout *)instance->signature)->types;
        returnValue = instance->returnValue.type == NSObjCStructType
            ? instance->returnValue.value.structLocation
            : &instance->returnValue.value;
        [aCoder encodeValueOfObjCType:returnType at:returnValue];
    }
    NSInvocationEncodeArgumentRecords(self, instance, aCoder, _cmd, NO);
}

- (void)decodeReturnValueWithCoder:(NSCoder *)aCoder
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    const char *returnType;
    void *returnValue;

    if (__NSInvocationLoggingDepth != 0)
        NSLog(@"decodeMethodRet type '%c' location %x",
              instance->returnValue.type,
              *(unsigned *)&instance->returnValue.value);
    if (instance->returnValue.type != NSObjCVoidType) {
        returnType = signature->types;
        returnValue = instance->returnValue.type == NSObjCStructType
            ? instance->returnValue.value.structLocation
            : &instance->returnValue.value;
        [aCoder decodeValueOfObjCType:returnType at:returnValue];
    }
    NSInvocationDecodeArgumentRecords(self, instance, aCoder,
                                      instance->signature,
                                      (unsigned)signature->numberOfArguments,
                                      NO);
    if (__NSInvocationLoggingDepth != 0)
        NSLog(@"decodeReturn type '%c' value %x",
              instance->returnValue.type,
              *(unsigned *)&instance->returnValue.value);
}

/*  NSPortCoder's factory path uses these helpers for the distributed-object
    wire protocol.  The decoded wire signature remains separate from the
    selected invocation signature because it supplies the argument records. */
+ (void)_preInitWithCoder:(NSCoder *)aCoder signature:(NSMethodSignature **)sigOut
                   valid:(BOOL *)validOut
            wireSignature:(NSMethodSignature **)wireOut
                  target:(id *)targetOut selector:(SEL *)selOut
                argCount:(unsigned *)countOut
{
    const char *types;
    NSMethodSignature *targetSignature;
    NSMethodSignature *decodedSignature;

    [aCoder decodeValueOfObjCType:"@" at:targetOut];
    [aCoder decodeValueOfObjCType:"I" at:countOut];
    [aCoder decodeValueOfObjCType:":" at:selOut];
    [aCoder decodeValueOfObjCType:"*" at:&types];

    decodedSignature = [NSMethodSignature signatureWithObjCTypes:types];
    targetSignature = [[*targetOut methodSignatureForSelector:*selOut] retain];
    *wireOut = decodedSignature;
    if (targetSignature != nil && targetSignature == decodedSignature) {
        *sigOut = targetSignature;
        *validOut = YES;
    } else {
        if (*targetOut != nil && targetSignature != nil) {
#if defined(__ppc__) || defined(__POWERPC__)
            NSLog(@"%s incompatible method params: got %@ want %@\n",
                  sel_getName(_cmd), decodedSignature);
#else
            NSLog(@"%s incompatible method params: got %@ want %@\n",
                  sel_getName(_cmd), decodedSignature, targetSignature);
#endif
        }
        [targetSignature release];
        *sigOut = [decodedSignature retain];
        *validOut = NO;
    }
    NSZoneFree(NSZoneFromPointer((void *)types), (void *)types);
}

- (id)_postInitWithCoder:(NSCoder *)aCoder signature:(NSMethodSignature *)aSignature
                   valid:(BOOL)valid
            wireSignature:(NSMethodSignature *)wireSignature
                  target:(id)aTarget selector:(SEL)aSelector
                argCount:(unsigned)argCount
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSInvocationMethodSignatureLayout *wireSignatureLayout =
        (NSInvocationMethodSignatureLayout *)wireSignature;

    if (__NSInvocationLoggingDepth != 0)
        NSLog(@"NSInvocation initWithCoder: the selector is '%s'\n",
              (char *)aSelector);
    instance->signature = aSignature;
    instance->signatureValid = valid ? 1 : 0;
    [aCoder decodeValueOfObjCType:"i" at:&instance->returnValue.type];
    if (instance->returnValue.type == NSObjCStructType) {
        unsigned size;

        NSGetSizeAndAlignment(wireSignatureLayout->types, &size, NULL);

        instance->returnValue.value.structLocation = NSZoneMalloc(NULL, size);
        memset(instance->returnValue.value.structLocation, 0, size);
    }
    if (instance->argumentFrame == NULL)
        NSInvocationEstablishArgumentFrame(self);
    [self setArgument:&aSelector atIndex:1];
    [self setArgument:&aTarget atIndex:0];
    instance->retainedArgs = 1;
    instance->retainedRet = 0;
    NSInvocationDecodeArgumentRecords(self, instance, aCoder,
                                      wireSignature, argCount, YES);
    return self;
}

+ (id)newInvocationWithCoder:(NSCoder *)aCoder
{
    NSMethodSignature *sig;
    BOOL valid;
    NSMethodSignature *wire;
    id target;
    SEL selector;
    unsigned argCount;
    id invocation;
    NSInvocationInstance *instance;

    [self _preInitWithCoder:aCoder signature:&sig valid:&valid
              wireSignature:&wire target:&target selector:&selector
                   argCount:&argCount];

    invocation = NSAllocateObject(self,
        ((NSInvocationMethodSignatureLayout *)sig)->parameterSize, NULL);
    if (invocation != nil) {
        instance = (NSInvocationInstance *)invocation;
        instance->argumentFrame = (char *)invocation +
            instance->isa->instance_size;
    }
    return [invocation _postInitWithCoder:aCoder signature:sig valid:valid
                            wireSignature:wire target:target selector:selector
                                 argCount:argCount];
}

- (id)replacementObjectForPortCoder:(NSCoder *)aCoder
{
    return self;
}

/*	The target keeps message dispatch inside an exception-handler frame and
	uses these helpers for its return-type switch so every case reaches the
	common ownership and handler cleanup below.	*/
static void NSInvocationDispatchMessage(NSInvocationInstance *instance,
                                        id receiver,
                                        SEL selector,
                                        unsigned dispatchSize,
                                        const char *returnType)
{
    enum _NSObjCValueType returnKind = instance->returnValue.type;

    if (returnKind == NSObjCVoidType) {
        objc_msgSendv(receiver, selector, dispatchSize,
                      instance->argumentFrame);
        return;
    }

    if (returnKind == NSObjCCharType) {
        unsigned char value =
            ((unsigned char (*)(id, SEL, unsigned, void *))objc_msgSendv)
            (receiver, selector, dispatchSize, instance->argumentFrame);

        memcpy(&instance->returnValue.value, &value, sizeof(value));
        return;
    }

    if (returnKind == NSObjCShortType) {
        unsigned short value =
            ((unsigned short (*)(id, SEL, unsigned, void *))objc_msgSendv)
            (receiver, selector, dispatchSize, instance->argumentFrame);

        memcpy(&instance->returnValue.value, &value, sizeof(value));
        return;
    }

    if (returnKind == NSObjCFloatType) {
        float value =
            ((float (*)(id, SEL, unsigned, void *))objc_msgSendv)
            (receiver, selector, dispatchSize, instance->argumentFrame);

        memcpy(&instance->returnValue.value, &value, sizeof(value));
        return;
    }

    if (returnKind == NSObjCDoubleType) {
        double value =
            ((double (*)(id, SEL, unsigned, void *))objc_msgSendv)
            (receiver, selector, dispatchSize, instance->argumentFrame);

        memcpy(&instance->returnValue.value, &value, sizeof(value));
        return;
    }

    if (returnKind == NSObjCLonglongType) {
        long long value =
            ((long long (*)(id, SEL, unsigned, void *))objc_msgSendv)
            (receiver, selector, dispatchSize, instance->argumentFrame);

        memcpy(&instance->returnValue.value, &value, sizeof(value));
        return;
    }

    if (returnKind == NSObjCStructType || returnKind == NSObjCUnionType) {
        unsigned size = 0;
        void *structure = instance->returnValue.value.structLocation;
        NSInvocationMethodSignatureLayout *signature =
            (NSInvocationMethodSignatureLayout *)instance->signature;

        NSGetSizeAndAlignment(returnType, &size, NULL);
#if !defined(__ppc__) && !defined(__POWERPC__)
        if (signature->types[0] == '{' &&
            (signature->returnValueLength == 1 ||
             signature->returnValueLength == 2 ||
             signature->returnValueLength == 4 ||
             signature->returnValueLength == 8)) {
            if (size == 8) {
                long long value =
                    ((long long (*)(id, SEL, unsigned, void *))objc_msgSendv)
                    (receiver, selector, dispatchSize,
                     instance->argumentFrame);
                memcpy(structure, &value, sizeof(value));
            } else {
                unsigned long value =
                    ((unsigned long (*)(id, SEL, unsigned, void *))objc_msgSendv)
                    (receiver, selector, dispatchSize,
                     instance->argumentFrame);
                memcpy(structure, &value, sizeof(value));
            }
        } else {
            NSInvocationCallWithStructReturn(structure, receiver, selector,
                dispatchSize, instance->argumentFrame);
        }
#else
        NSInvocationCallWithStructReturn(structure, receiver, selector,
            dispatchSize, instance->argumentFrame);
#endif
        return;
    }

    /*  Everything else -- id, Class, SEL, pointer, int, and long -- is
        read through the widest cast and copied by the return type's
        own size.  */
    {
        unsigned long long value =
            ((unsigned long long (*)(id, SEL, unsigned, void *))
             objc_msgSendv)(receiver, selector, dispatchSize,
                            instance->argumentFrame);
        unsigned size = 0;

        NSGetSizeAndAlignment(returnType, &size, NULL);
        if (size > sizeof(value))
            size = sizeof(value);
        memcpy(&instance->returnValue.value, &value, size);
    }
}

#if !defined(__ppc__) && !defined(__POWERPC__)
static void NSInvocationRetainReturnedValue(
    NSInvocation *invocation, id receiver, SEL selector)
{
    NSInvocationInstance *instance = (NSInvocationInstance *)invocation;
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    const char *returnType = signature->types;
    BOOL retainValue = YES;

    if (instance->returnValue.type == NSObjCVoidType)
        return;

    if (instance->returnValue.type == NSObjCObjectType &&
        (selector == @selector(performSelector:) ||
         selector == @selector(performSelector:withObject:) ||
         selector == @selector(performSelector:withObject:withObject:))) {
        SEL invokedSelector;
        NSMethodSignature *invokedSignature;

        invokedSelector = NULL;
        [invocation getArgument:&invokedSelector atIndex:2];
        invokedSignature = [receiver methodSignatureForSelector:
            invokedSelector];
        if (invokedSignature != nil) {
            returnType = ((NSInvocationMethodSignatureLayout *)
                invokedSignature)->types;
            if (*returnType == 'v' || *returnType == 'V')
                retainValue = NO;
        }
    }

    if (retainValue) {
        _NSParseAndRetain(returnType, &instance->returnValue.value);
        instance->retainedRet = 1;
    }
}
#endif

- (void)invoke
{
    NSInvocationInstance *instance = (NSInvocationInstance *)self;
    NSInvocationMethodSignatureLayout *signature =
        (NSInvocationMethodSignatureLayout *)instance->signature;
    const char *returnType;
    unsigned dispatchSize = signature->parameterSize;
    unsigned index;
    id receiver;
    SEL op;

    [self getArgument:&op atIndex:1];
    [self getArgument:&receiver atIndex:0];

    if ([receiver isProxy] && [receiver willForwardSelector:op]) {
        [receiver forwardInvocation:self];
        return;
    }

#if defined(__ppc__) || defined(__POWERPC__)
    dispatchSize -= 128;
#endif
    for (index = 2; index < (unsigned)signature->numberOfArguments; index++) {
        int fixupOffset = signature->fixup != NULL
            ? signature->fixup[index] : 0;

        if (fixupOffset != 0) {
            NSMethodSignatureArgumentInfo info =
                signature->argumentInfo[index];

            dispatchSize -= info.size;
            *(void **)((char *)instance->argumentFrame + fixupOffset) =
                (char *)instance->argumentFrame + info.offset;
        }
    }

    returnType = NSInvocationSkipQualifiers(signature->types);
    NS_DURING {
#if !defined(__ppc__) && !defined(__POWERPC__)
        if (instance->returnValue.type != NSObjCVoidType)
            _NSParseAndRelease(signature->types,
                               &instance->returnValue.value);
#endif
        NSInvocationDispatchMessage(instance, receiver, op, dispatchSize,
                                    returnType);
#if !defined(__ppc__) && !defined(__POWERPC__)
        NSInvocationRetainReturnedValue(self, receiver, op);
#endif
    } NS_HANDLER {
        [localException raise];
    } NS_ENDHANDLER
    if (__NSInvocationLoggingDepth != 0)
        NSLog(@"invokeWithTarget: return type '%c' value %x",
              instance->returnValue.type,
              *(unsigned *)&instance->returnValue.value);
}

- (void)invokeWithTarget:(id)aTarget
{
    /*  The reference's 60-byte body is exactly these two sends: store
        the substitute receiver into frame slot 0 and dispatch.  The
        substitute REMAINS the invocation's target afterwards -- there
        is no restore in the reference and none here, matching the
        documented NeXT behaviour that -invokeWithTarget: changes the
        receiver's target.  */
    [self setArgument:&aTarget atIndex:0];
    [self invoke];
}

/*  The i386 implementation omits the third format argument present on PPC.  */
- (NSString *)description
{
    SEL selector = [self selector];
#if defined(__ppc__) || defined(__POWERPC__)
    NSMethodSignature *signature =
        ((NSInvocationInstance *)self)->signature;

    return [NSString stringWithFormat:
        @"<NSInvocation[0x%x] selector: %s signature: %@>",
        self, selector, signature];
#else
    return [NSString stringWithFormat:
        @"<NSInvocation[0x%x] selector: %s signature: %@>",
        self, selector];
#endif
}

@end

/*
	NSInvocationBuilder.  No header declares this class anywhere in
	the tree; NSProxy.m's own comment on -isKindOfClass:/
	-isMemberOfClass:/-conformsToProtocol:/-respondsToSelector:
	already names it and the shape it is used in.  The reference's
	own -forward:: (type @16@8:12:16^:20, distinct from the two
	packages' forwarding -forward:: below) is a packaging step: build
	the one-shot signature/invocation pair for whatever selector was
	sent, never dispatch it.  Claimed by name in symbols.json.
	*/
/*  The builder is a ROOT class in the reference (class record super
    field = 0, explicit isa ivar at +0, 16 bytes), so it declares its
    own isa here; subclassing Object instead is fatal on the guest's
    cc1obj (duplicate-member 'isa' error path segfaults).  */
@interface NSInvocationBuilder
{
    Class	isa;
    Class	targetClass;
    id		target;
    void	*reserved;
}
+ (id)builderForClass:(Class)aClass;
+ (id)builderForObject:(id)anObject;
- (id)forward:(SEL)aSelector :(SEL *)argFrame;
@end

@interface NSInvocation (NSInvocationBuilderPrivate)
- (id)initWithMethodSignature:(NSMethodSignature *)signature;
- (void)_setArgFrame:(void *)argFrame;
@end

@implementation NSInvocationBuilder

+ (void)initialize
{
}

+ (id)builderForClass:(Class)aClass
{
    NSInvocationBuilder *builder = [NSInvocation allocWithZone:NULL];

    /*  The reference allocates NSInvocation-sized storage, then installs
        NSInvocationBuilder as its temporary class until -forward:: turns
        this same object back into an NSInvocation.  */
    builder->isa = (Class)self;
    builder->targetClass = aClass;
    return builder;
}

+ (id)builderForObject:(id)anObject
{
    NSInvocationBuilder *builder = [self builderForClass:anObject->isa];

    builder->target = anObject;
    return builder;
}

/*  The reference allocates NSInvocation-sized storage and changes its isa
    to NSInvocationBuilder. Its -forward:: then turns that same object into
    an NSInvocation, installs the original argument frame and target, and
    autoreleases it. The method-list encoding is @16@8:12:16^:20 because
    argFrame is declared SEL *. */
- (id)forward:(SEL)aSelector :(SEL *)argFrame
{
    struct objc_method_description *description;
    NSMethodSignature *signature;
    NSInvocation *invocation;
    id originalTarget = target;
    SEL forwardedSelector = NULL;

    description = [targetClass instanceMethodDescriptionForSelector:aSelector];
    if (description == NULL)
        [NSException raise:NSInternalInconsistencyException
                    format:@"target does not implement method"];

    targetClass = Nil;
    target = nil;
    signature = [NSMethodSignature signatureWithObjCTypes:description->types];
    isa = [NSInvocation class];
    invocation = (NSInvocation *)self;
    [invocation initWithMethodSignature:signature];
    [invocation _setArgFrame:argFrame];
    [invocation getArgument:&forwardedSelector atIndex:1];
    if (forwardedSelector == NULL) {
        NSData *frame = [NSData dataWithBytes:argFrame
                                       length:((NSInvocationMethodSignatureLayout *)signature)
                                                   ->parameterSize + 20];
        [NSException raise:NSInternalInconsistencyException
                    format:@"*** -forward:: no selector in argument frame for '%s' (%@)",
                           (char *)aSelector, frame];
    }
    [invocation setArgument:&originalTarget atIndex:0];
    [invocation autorelease];
    return invocation;
}

@end

/*
	The real forwarding trampoline.  Confirmed from the reference's
	category body: build the signature (nil ->
	-doesNotRecognizeSelector:), build the invocation, _setArgFrame:
	the runtime's raw frame -- whose slots 0 and 1 STILL hold self and
	_cmd from the original send, which is exactly why no setTarget:
	send appears -- then -invoke, and return the value.  This category
	replaces NSObject.m's own raising -forward:: at method-table load,
	which is how a subclass's -forwardInvocation: override is reached
	at all; NSObject.m's stage 2a body becomes functionally dead from
	this file's link onward (the gate test in Task 10 pins that).
	*/
@implementation NSObject (NSForwardInvocation)

/*  The category's method-list encoding is q16@8:12:16^v20. The
    forwarding trampoline dispatches the tagged -_returnValue through
    the return lane of the original message: integer and pointer values
    use integer registers, floating values use the target FP return
    register, and aggregates use the target's register or hidden-buffer
    convention. Keep the recovered q encoding unchanged.  */
- (long long)forward:(SEL)aSelector :(marg_list)argFrame
{
    id signature = [self methodSignatureForSelector:aSelector];
    id invocation;
    NSObjCValue value;
#if !defined(__ppc__) && !defined(__POWERPC__)
    void *structReturnLocation = _structure_addr();
#endif

    /*  The target returns the tagged invocation result using the original
        message's ABI lane.  Its selector encoding remains q16@8:12:16^v20;
        the forwarding runtime consumes the result according to the message
        being forwarded.  */
    if (signature == nil)
        [self doesNotRecognizeSelector:aSelector];

    invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation _setArgFrame:argFrame];
    [self forwardInvocation:invocation];

    value = [invocation _returnValue];
    switch (value.type) {
    case NSObjCVoidType:
        return 0;
    case NSObjCCharType:
        return (long long)value.value.charValue;
    case NSObjCShortType:
        return (long long)value.value.shortValue;
    case NSObjCLongType:
        return (long long)value.value.longValue;
    case NSObjCLonglongType:
        return value.value.longlongValue;
    case NSObjCFloatType:
#if defined(__ppc__) || defined(__POWERPC__)
        __asm__ volatile("lfs 1,0(%0)"
                         : : "r"(&value.value.floatValue) : "f1");
#else
        __asm__ volatile("flds %0"
                         : : "m"(value.value.floatValue) : "st");
#endif
        return 0;
    case NSObjCDoubleType:
#if defined(__ppc__) || defined(__POWERPC__)
        __asm__ volatile("lfd 1,0(%0)"
                         : : "r"(&value.value.doubleValue) : "f1");
#else
        __asm__ volatile("fldl %0"
                         : : "m"(value.value.doubleValue) : "st");
#endif
        return 0;
    case NSObjCStructType: {
        void *structure = value.value.structLocation;
        unsigned length =
            ((NSInvocationMethodSignatureLayout *)signature)->returnValueLength;

        if ([signature _isReturnStructInRegisters]) {
            long long result = 0;

            memmove(&result, structure, sizeof(result));
            return result;
        }
#if defined(__ppc__) || defined(__POWERPC__)
        {
            void *destination = *(void **)((char *)argFrame + 128);

            memmove(destination, structure, length);
            return value.value.longlongValue;
        }
#else
        memmove(structReturnLocation, structure, length);
        return (long long)structReturnLocation;
#endif
    }
    case NSObjCObjectType:
    case NSObjCSelectorType:
    case NSObjCStringType:
    case NSObjCPointerType:
        return value.value.longlongValue;
    case NSObjCNoType:
    default:
        [NSException raise:NSInternalInconsistencyException
                    format:@"*** unknown return type %u",
                           (unsigned)value.type];
        return 0;
    }
}

@end

@implementation NSObject (NSIDispatchProxy)

/*	Distributed Objects infrastructure (stage 8) asks this to tell an
	ordinary object apart from one of its own dispatch-proxy classes.
	No NSObject instance is ever one, so the answer here is always NO;
	a stage-8 subclass overrides it.  */
- (BOOL)isNSIDispatchProxy
{
    return NO;
}

@end
