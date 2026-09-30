/*
	NSMethodSignature.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.

	Stage 2c Task 1: the implementation is the reference's constructor
	and accessors, decoded from the i386 image and written to the
	bytes -- each method's comment says what was measured and where.
*/

#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSString.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSException.h>
#import <Foundation/NSZone.h>
#import <objc/objc-class.h>
#import <objc/objc-runtime.h>
#include <stdio.h>
#include <string.h>

/*
	The private argument-cache entry.  The reference's is 20 bytes on
	i386 -- {?=ii*^{_arginfo}i} in -_argumentInfoAtIndex:'s own
	encoding: the running offset, the argument's size, its type
	pointer, then two fields the constructor never writes (its
	walker's alignment output goes to a stack temporary that is never
	stored back).  */
typedef struct {
    unsigned	offset;
    unsigned	size;
    const char	*type;
    unsigned	unused0;
    unsigned	unused1;
} NSMethodSignatureArgInfo;

/*	The by-value shape -_argumentInfoAtIndex: delivers (the reference's
	{?=ii*^{_arginfo}i} return encoding).  The exact shape is what makes
	this toolchain's cc1obj emit that encoding byte-for-byte (probed on
	the guest, Gate 1 stage 2c): an ANONYMOUS typedef'd struct with
	int-sized fields and a tag-only pointer field -- `struct _arginfo`
	is forward-declared here and defined NOWHERE, so the pointer
	encodes as ^{_arginfo}.  NSInvocation.m and the test suite carry
	identical file-local copies; no shared header declares the type.  */
struct _arginfo;

typedef struct {
    int		offset;
    int		size;
    const char	*type;
    struct _arginfo *unused0;
    int		unused1;
} NSMethodSignatureArgumentInfo;

/*
	Mirror of the header's ivar layout, which is the ABI-visible part:
	isa plus the seven declared ivars is the reference's own 32-byte
	instance_size.  All field access in this file goes through this
	struct rather than through Objective-C ivar references, so the
	file's helper functions need no special compilation context.  */
typedef struct {
    Class		isa;
    const char		*_types;
    int			_nargs;
    unsigned		_sizeofParams;
    unsigned		_returnValueLength;
    void		*_parmInfoP;
    int			*_fixup;
    void		*_reserved;
} NSMethodSignatureInstance;

#define NSMethodSignatureInstanceSize	32
#define NSMethodSignatureEntrySize	20

/*
	The class-global signature cache.  The reference keeps a lock-
	protected sorted table (__NSMethodSignatureTable beside
	__NSMethodSignatureTableLock in its symbols; entries are added
	with NSZoneMalloc under the lock and looked up with
	__NSFastBSearchInt), so identical type strings share one signature
	object.  The reconstruction keeps the same table shape with a
	linear walk; the reference's lock is a mach mutex with a spin
	limit (its _mutex_spin_limit import) whose declaring headers this
	guest does not carry, so the lock word here is a plain test-and-
	set spin -- correct for this stage's single-threaded tests, and
	recorded in divergences.md as a substitution.  */
static NSMethodSignature **__NSMethodSignatureTable;
static unsigned __NSMethodSignatureTableCount;
static unsigned __NSMethodSignatureTableCapacity;
static volatile unsigned __NSMethodSignatureTableLock;

static void
_NSMethodSignatureLockAcquire(void)
{
    while (__NSMethodSignatureTableLock != 0)
        ;
    __NSMethodSignatureTableLock = 1;
}

static void
_NSMethodSignatureLockRelease(void)
{
    __NSMethodSignatureTableLock = 0;
}

/*	NSObjCRuntime.m exports this beside the public walker; no header
	declares it, so this file carries the declaration.  */
extern const char *
_NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep,
                       unsigned int *alignp);

/*	The cache's comparison key.  */
static const char *
_NSMethodSignatureTypesOf(NSMethodSignature *signature)
{
    return ((NSMethodSignatureInstance *)signature)->_types;
}

/*
	The builder: everything here is the reference constructor's own
	sequence.  Count the arguments by walking the encoding; allocate
	instance + entry table + types copy as ONE NSZoneMalloc block (the
	reference's class_createInstanceFromZone(self, 20*nargs +
	strlen(types) + 1, NULL), the class's instance_size coming first
	in its block too); derive the return length from the shared
	walker; then fill the table with running round4 offsets.
	_sizeofParams is that accumulated sum -- `mov dword ptr
	[ecx + 0xc], 0` before the fill loop at 0x42520f00 and
	`add eax, 3 / and al, 0xfc` at 0x42520f3b -- NOT the leading
	digits of the encoding string, which nothing in the reference
	reads back as an offset.  */
static NSMethodSignature *
_NSMethodSignatureNew(Class self, const char *types, unsigned typesLength)
{
    NSMethodSignatureInstance *instance;
    NSMethodSignatureArgInfo *entries;
    char *typesCopy;
    unsigned argCount = 0;
    unsigned scan = 0;
    unsigned offset = 0;
    unsigned i;

    /*  The return type first: the reference derives _returnValueLength
        from it and starts the argument list after it and its digit
        run -- the argument count and the fill loop share that scan
        position, so the count covers self, _cmd and the declared
        arguments, never the return type.  */
    scan = _NSGetSizeAndAlignment(types, NULL, NULL) - types;
    while (types[scan] >= '0' && types[scan] <= '9')
        scan++;

    i = scan;
    while (types[i] != '\0') {
        i += _NSGetSizeAndAlignment(types + i, NULL, NULL) - (types + i);
        while (types[i] >= '0' && types[i] <= '9')
            i++;
        argCount++;
    }

    instance = (NSMethodSignatureInstance *)NSZoneMalloc(0,
        NSMethodSignatureInstanceSize +
        argCount * NSMethodSignatureEntrySize + typesLength + 1);

    entries = (NSMethodSignatureArgInfo *)
        ((char *)instance + NSMethodSignatureInstanceSize);
    typesCopy = (char *)entries + argCount * NSMethodSignatureEntrySize;
    memcpy(typesCopy, types, typesLength + 1);

    /*	NSZoneMalloc runs no constructor: zero the instance region so
        the fields the reference never writes (_fixup, _reserved, and
        _sizeofParams until the fill loop) start at zero, then set
        isa.  */
    memset(instance, 0, NSMethodSignatureInstanceSize);
    instance->isa = self;

    _NSGetSizeAndAlignment(typesCopy, &instance->_returnValueLength, NULL);
    instance->_parmInfoP = entries;
    instance->_types = typesCopy;
    instance->_nargs = (int)argCount;

    for (i = 0; i < argCount; i++) {
        unsigned size = 0;
        unsigned consumed;

        consumed = _NSGetSizeAndAlignment(typesCopy + scan, &size, NULL) -
                   (typesCopy + scan);
        entries[i].offset = offset;
        entries[i].size = size;
        entries[i].type = typesCopy + scan;
        entries[i].unused0 = 0;
        entries[i].unused1 = 0;
        scan += consumed;
        while (typesCopy[scan] >= '0' && typesCopy[scan] <= '9')
            scan++;
        offset += (size + 3) & ~3u;
        instance->_sizeofParams += (size + 3) & ~3u;
    }

    return (NSMethodSignature *)instance;
}

@implementation NSMethodSignature

/*
	Returns the signature for `types`, building it on first sight and
	returning the shared cached instance thereafter.  Because every
	call with the same string returns the same object, -retain is an
	immortal no-op -- the reference's own three (return self / empty /
	return -1) are reproduced verbatim below.  */
+ (id)signatureWithObjCTypes:(const char *)types
{
    NSMethodSignature *signature;
    unsigned typesLength;
    unsigned i;

    if (types == NULL)
        return nil;

    typesLength = strlen(types);

    _NSMethodSignatureLockAcquire();
    for (i = 0; i < __NSMethodSignatureTableCount; i++) {
        if (strcmp(_NSMethodSignatureTypesOf(__NSMethodSignatureTable[i]),
                   types) == 0) {
            _NSMethodSignatureLockRelease();
            return __NSMethodSignatureTable[i];
        }
    }

    signature = _NSMethodSignatureNew(self, types, typesLength);

    if (__NSMethodSignatureTableCount == __NSMethodSignatureTableCapacity) {
        unsigned newCapacity = (__NSMethodSignatureTableCapacity == 0)
            ? 16 : __NSMethodSignatureTableCapacity * 2;
        NSMethodSignature **newTable = (NSMethodSignature **)
            NSZoneRealloc(0, __NSMethodSignatureTable,
                          newCapacity * sizeof(NSMethodSignature *));
        if (newTable == NULL) {
            _NSMethodSignatureLockRelease();
            return signature;
        }
        __NSMethodSignatureTable = newTable;
        __NSMethodSignatureTableCapacity = newCapacity;
    }
    __NSMethodSignatureTable[__NSMethodSignatureTableCount++] = signature;
    _NSMethodSignatureLockRelease();

    return signature;
}

- (unsigned)numberOfArguments
{
    return (unsigned)((NSMethodSignatureInstance *)self)->_nargs;
}

/*
	Returns the span NSGetSizeAndAlignment consumes for this argument's
	type token -- the reference slices at call time (its accessor
	walks the stored pointer with the same walker and copies the
	consumed span), so the digit annotations that follow each token
	are never part of the result.  Each call returns a fresh copy, as
	the reference's own per-call copy does; the header's `const char *`
	return makes this a use-and-discard accessor, not a borrowed
	pointer.  */
- (const char *)getArgumentTypeAtIndex:(unsigned)index
{
    NSMethodSignatureArgInfo *entries =
        (NSMethodSignatureArgInfo *)
        ((NSMethodSignatureInstance *)self)->_parmInfoP;
    const char *type;
    const char *end;
    char *copy;
    unsigned length;

    if ((int)index >= ((NSMethodSignatureInstance *)self)->_nargs) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%s %s: index out of bounds",
                            ((struct objc_object *)self)->isa->name,
                            sel_getName(_cmd)];
    }

    type = entries[index].type;
    end = _NSGetSizeAndAlignment(type, NULL, NULL);
    length = (unsigned)(end - type);

    copy = (char *)NSZoneMalloc(0, length + 1);
    memcpy(copy, type, length);
    copy[length] = '\0';
    return copy;
}

- (unsigned)frameLength
{
    return ((NSMethodSignatureInstance *)self)->_sizeofParams;
}

/*
	The reference's -isOneway is one byte test: cmp byte ptr [eax],
	0x56 at 0x42521415 -- the 'V' oneway qualifier on the return
	type.  */
- (BOOL)isOneway
{
    return (((NSMethodSignatureInstance *)self)->_types[0] == 'V')
        ? YES : NO;
}

/*
	Returns the span the walker consumes for the return type -- for
	"Vv12@8:12@16" that is "Vv": the qualifier is skipped within the
	one walker step and stays inside the consumed span.  */
- (const char *)methodReturnType
{
    const char *types = ((NSMethodSignatureInstance *)self)->_types;
    const char *end = _NSGetSizeAndAlignment(types, NULL, NULL);
    unsigned length = (unsigned)(end - types);
    char *copy;

    copy = (char *)NSZoneMalloc(0, length + 1);
    memcpy(copy, types, length);
    copy[length] = '\0';
    return copy;
}

- (unsigned)methodReturnLength
{
    return ((NSMethodSignatureInstance *)self)->_returnValueLength;
}

/*
	Whether this signature's return value comes back in registers or
	through a hidden pointer.  From the reference's disassembly
	(56 bytes at 0x42574520): non-struct returns answer NO; struct or
	union returns answer YES only when the return size is 1, 2, 4 or
	8 bytes.  Larger structs take the hidden pointer.  */
- (BOOL)_isReturnStructInRegisters
{
    NSMethodSignatureInstance *instance = (NSMethodSignatureInstance *)self;

    if (instance->_types[0] != '{' && instance->_types[0] != '(')
        return NO;
    return (instance->_returnValueLength == 1 ||
            instance->_returnValueLength == 2 ||
            instance->_returnValueLength == 4 ||
            instance->_returnValueLength == 8) ? YES : NO;
}

/*
	Undeclared; NSInvocation.m (Task 6) marshals arguments through
	this cache.  The reference's method-list encoding is
	{?=ii*^{_arginfo}i}12@8:12I16 -- a STRUCT RETURN: the i386
	caller passes the destination buffer in a hidden register, and
	the body copies the 20-byte entry out to it (the register-return
	convention this compiler cannot declare with a bare pointer
	return).  Declared here with the struct as the return type so the
	compiled encoding matches the reference byte-for-byte (Gate 1,
	stage 2c); callers receive the entry by value exactly as the
	reference delivers it.  */
- (NSMethodSignatureArgumentInfo)_argumentInfoAtIndex:(unsigned)index
{
    NSMethodSignatureArgInfo *entries =
        (NSMethodSignatureArgInfo *)
        ((NSMethodSignatureInstance *)self)->_parmInfoP;
    NSMethodSignatureArgumentInfo out;

    if ((int)index >= ((NSMethodSignatureInstance *)self)->_nargs) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%s %s: index out of bounds",
                            ((struct objc_object *)self)->isa->name,
                            sel_getName(_cmd)];
    }

    out.offset = (int)entries[index].offset;
    out.size = (int)entries[index].size;
    out.type = entries[index].type;
    out.unused0 = 0;
    out.unused1 = 0;
    return out;
}

/*
	Confirmed from the reference's disassembly of all three: -retain is
	`return self` untouched, -release an empty body, -retainCount
	`return -1`.  NSMethodSignature objects are immortal because the
	class caches every signature it builds -- identical type strings
	return the same shared object, so there is no per-instance
	counting (and no NSIncrementExtraRefCount side table either).
	These three are written exactly as the reference has them.  */
- (id)retain
{
    return self;
}

- (void)release
{
}

- (unsigned)retainCount
{
    return (unsigned)-1;
}

/*
	NSString is still the stage's TODO skeleton; this goes through the
	same +stringWithCString:length: entry the stage 2a/2b classes use
	(carried by link_stubs.m until stage 3), unexercised by this
	stage's tests, exactly like NSObject's -description.  */
- (NSString *)description
{
    char buffer[64];

    sprintf(buffer, "<%s: 0x%x>",
            ((struct objc_object *)self)->isa->name, (unsigned)self);
    return [NSString stringWithCString:buffer length:strlen(buffer)];
}

- (NSString *)debugDescription
{
    return [self description];
}

@end
