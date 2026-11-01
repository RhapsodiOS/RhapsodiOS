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
#import <Foundation/NSLock.h>
#import <Foundation/NSMapTable.h>
#import <objc/objc-class.h>
#import <objc/objc-runtime.h>
#include <string.h>

extern NSString *_NSIndentSpace(unsigned level);
extern id _NSMethodExceptionProem(id object, SEL aSelector);

struct _arginfo;

/*
	The private argument-cache entry.  The reference's is 20 bytes on
	i386; PPC also uses the last two fields for nested aggregate
	argument records.  */
typedef struct {
    unsigned	offset;
    unsigned	size;
    const char	*type;
	struct _arginfo *unused0;
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

#define NSMethodSignatureEntrySize	20

/*  The reference's C-string keyed signature map and its shared lock.  */
NSMapTable *_NSMethodSignatureTable;
NSLock *_NSMethodSignatureTableLock;

/*	NSObjCRuntime.m exports this beside the public walker; no header
	declares it, so this file carries the declaration.  */
extern const char *
_NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep,
                       unsigned int *alignp);
extern void *_NSUniqueCString(void *pointer);

static unsigned
_NSMethodSignatureHashString(NSMapTable *table, const void *key)
{
    const char *cursor = (const char *)key;
    unsigned length = (unsigned)strlen((const char *)key);
    unsigned remaining = length;
    unsigned hash = 51815;

    (void)table;
    while (remaining != 0) {
        unsigned character = (unsigned short)(signed char)*cursor++;

        hash += (character << (character & 7)) + (hash << 8);
        if (character == '{') {
            while (remaining != 0) {
                unsigned next = *cursor++;

                remaining--;
                if (next == '=')
                    break;
            }
        }
        remaining--;
    }
    return hash;
}

static BOOL
_NSMethodSignatureStructurallyEqual(const char *first, const char *second)
{
    while (*first != '\0' && *second != '\0') {
        if (*first == *second) {
            first++;
            second++;
        } else if (*first == '?') {
            first++;
            while (*second != '\0' && *second != '=')
                second++;
        } else if (*second == '?') {
            second++;
            while (*first != '\0' && *first != '=')
                first++;
        } else {
            return NO;
        }
    }
    return *first == '\0' && *second == '\0';
}

static BOOL
_NSMethodSignatureEqualString(NSMapTable *table, const void *first,
                              const void *second)
{
    (void)table;
    return first == second || _NSMethodSignatureStructurallyEqual(
        (const char *)first, (const char *)second);
}

static unsigned
_NSMethodSignatureScrunchTypes(const char *typePtr, char *destination)
{
    unsigned argumentCount = 0;
    const char *next;

    for (;;) {
        unsigned length;

        next = _NSGetSizeAndAlignment(typePtr, NULL, NULL);
        length = (unsigned)(next - typePtr);
        memmove(destination, typePtr, length);
        destination += length;
        if (*next == '\0')
            break;
        do {
            if (((unsigned char)(*next - '0') > 9) && *next != '-')
                break;
            next++;
        } while (*next != '\0');
        if (*next == '\0')
            break;
        typePtr = next;
        argumentCount++;
    }
    *destination = '\0';
    return argumentCount;
}

/*  Allocate the class instance and inline its entries and normalized
    type encoding, as +signatureWithObjCTypes: does in the reference.  */
static NSMethodSignature *
_NSMethodSignatureNew(Class self, const char *types, unsigned typesLength,
                     unsigned argCount, const char **argumentTypes)
{
    NSMethodSignatureInstance *instance;
    NSMethodSignatureArgInfo *entries;
    char *typesCopy;
    instance = (NSMethodSignatureInstance *)NSAllocateObject(self,
        argCount * NSMethodSignatureEntrySize + typesLength, NULL);

    entries = (NSMethodSignatureArgInfo *)
        ((char *)instance + self->instance_size);
    typesCopy = (char *)entries + argCount * NSMethodSignatureEntrySize;
    memmove(typesCopy, types, typesLength);
    instance->_parmInfoP = entries;
    instance->_types = typesCopy;
    instance->_nargs = (int)argCount;
    *argumentTypes = _NSGetSizeAndAlignment(typesCopy,
        &instance->_returnValueLength, NULL);
    return (NSMethodSignature *)instance;
}

/*  Populate argument records after the reference publishes the new
    signature in its cache.  */
static void
_NSMethodSignatureComplete(NSMethodSignature *signature, const char *type)
{
    NSMethodSignatureInstance *instance = (NSMethodSignatureInstance *)signature;
    NSMethodSignatureArgInfo *entries =
        (NSMethodSignatureArgInfo *)instance->_parmInfoP;
    unsigned i;

    instance->_sizeofParams = 0;
    for (i = 0; i < (unsigned)instance->_nargs; i++) {
        entries[i].type = type;
        type = _NSGetSizeAndAlignment(type, &entries[i].size, NULL);
        entries[i].offset = instance->_sizeofParams;
        instance->_sizeofParams += (entries[i].size + 3) & ~3u;
    }
}

#if defined(__ppc__) || defined(__POWERPC__)
static const char *
_NSMethodSignatureSkipQualifiers(const char *type)
{
    while (*type == 'N' || *type == 'O' || *type == 'R' || *type == 'V' ||
           *type == 'n' || *type == 'o' || *type == 'r')
        type++;
    return type;
}

static unsigned
_NSMethodSignatureAlign(unsigned offset, unsigned alignment)
{
    return (offset + alignment - 1) & ~(alignment - 1);
}

static unsigned
_NSMethodSignatureComputePPCOffset(NSMethodSignatureArgInfo *info,
                                   unsigned offset, int *gpr, int *fpr,
                                   BOOL nested)
{
    const char *type = _NSMethodSignatureSkipQualifiers(info->type);

    if (!nested && (*type == 'f' || *type == 'd')) {
        if (*fpr > 13) {
            info->offset = offset;
            return _NSMethodSignatureAlign(offset + info->size, 4);
        }
        info->offset = 8u * (unsigned)(*fpr - 1);
        (*fpr)++;
        info->size = 8;
        if (*gpr > 10) {
            offset = _NSMethodSignatureAlign(offset + info->size, 4);
            if (*type == 'd')
                offset = _NSMethodSignatureAlign(offset + info->size, 4);
        } else {
            (*gpr)++;
            if (*type == 'd') {
                if (*gpr > 10)
                    return _NSMethodSignatureAlign(offset + info->size, 4);
                (*gpr)++;
            }
        }
        return offset;
    }

    if (*type == '{') {
        const char *cursor = info->type;
        const char *field;
        unsigned alignment = 1;
        unsigned count = 0;
        unsigned index;
        NSMethodSignatureArgInfo *children;

        _NSGetSizeAndAlignment(info->type, &info->size, &alignment);
        while (*cursor != '=' && *cursor != '\0') {
            if (*cursor == '}' || *cursor == ')')
                [NSException raise:NSInvalidArgumentException
                            format:@"malformed struct encoding %s", info->type];
            cursor++;
        }
        if (*cursor != '=')
            [NSException raise:NSInvalidArgumentException
                        format:@"malformed struct encoding %s", info->type];
        field = cursor + 1;
        cursor = field;
        while (*cursor != '}') {
            if (*cursor == '\0' || *cursor == ')')
                [NSException raise:NSInvalidArgumentException
                            format:@"unterminated struct encoding %s", info->type];
            count++;
            cursor = _NSGetSizeAndAlignment(cursor, NULL, NULL);
        }

        children = (NSMethodSignatureArgInfo *)NSZoneMalloc(
            NULL, count * sizeof(NSMethodSignatureArgInfo));
        memset(children, 0, count * sizeof(NSMethodSignatureArgInfo));
        info->unused0 = (struct _arginfo *)children;
        info->unused1 = count;
        offset = _NSMethodSignatureAlign(offset - 1 + alignment, alignment);
        cursor = field;
        for (index = 0; index < count; index++) {
            children[index].type = cursor;
            cursor = _NSGetSizeAndAlignment(cursor, &children[index].size,
                                            NULL);
            if (children[index].size == 0)
                [NSException raise:NSInvalidArgumentException
                            format:@"zero-size struct field %s",
                                   children[index].type];
            offset = _NSMethodSignatureComputePPCOffset(
                &children[index], offset, gpr, fpr, YES);
        }
        info->offset = children[0].offset;
        return _NSMethodSignatureAlign(offset, 4);
    }

    if (*gpr > 10) {
        info->offset = offset;
        if (info->size == 1)
            info->offset += 3;
        else if (info->size == 2)
            info->offset += 2;
    } else {
        info->offset = 4u * (unsigned)(*gpr - 3) + 128;
        if (info->size == 1)
            info->offset += 3;
        else if (info->size == 2)
            info->offset += 2;
        (*gpr)++;
    }
    return _NSMethodSignatureAlign(offset + info->size, 4);
}

static void
_NSMethodSignatureCompletePPC(NSMethodSignature *signature,
                               const char *type)
{
    NSMethodSignatureInstance *instance = (NSMethodSignatureInstance *)signature;
    NSMethodSignatureArgInfo *entries =
        (NSMethodSignatureArgInfo *)instance->_parmInfoP;
    int gpr = (instance->_types[0] == '{') ? 4 : 3;
    int fpr = 1;
    unsigned offset = 160;
    unsigned index;

    instance->_sizeofParams = offset;
    for (index = 0; index < (unsigned)instance->_nargs; index++) {
        entries[index].type = type;
        type = _NSGetSizeAndAlignment(type, &entries[index].size, NULL);
        entries[index].unused0 = NULL;
        entries[index].unused1 = 0;
        offset = _NSMethodSignatureComputePPCOffset(
            &entries[index], offset, &gpr, &fpr, NO);
    }
    instance->_sizeofParams = offset;
}
#endif

/*  Both public type-string accessors intern a stack copy in the shared
    unique-C-string table.  */
static const char *
_NSMethodSignatureUniqueTypeString(const char *type)
{
    const char *end = _NSGetSizeAndAlignment(type, NULL, NULL);
    unsigned length = (unsigned)(end - type);
    char *scratch;

#if defined(__ppc__) || defined(__POWERPC__)
    char *storage = __builtin_alloca(length + 15);

    scratch = (char *)(((unsigned long)storage + 15UL) & ~15UL);
#else
    scratch = __builtin_alloca(length + 4);
#endif
    memmove(scratch, type, length);
    scratch[length] = '\0';
    return (const char *)_NSUniqueCString(scratch);
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
    unsigned argumentCount;
    char stackTypes[512];
    char *normalizedTypes = stackTypes;
    const char *argumentTypes;

    typesLength = (unsigned)strlen(types) + 1;
    if (typesLength == 1)
        return nil;
    if (typesLength > sizeof(stackTypes) - 1)
        normalizedTypes = (char *)NSZoneMalloc(NULL, typesLength);
    argumentCount = _NSMethodSignatureScrunchTypes(types, normalizedTypes);

    if (_NSMethodSignatureTableLock != nil)
        [_NSMethodSignatureTableLock lock];
    signature = _NSMethodSignatureTable != NULL
        ? (NSMethodSignature *)NSMapGet(_NSMethodSignatureTable,
                                        normalizedTypes) : nil;
    if (_NSMethodSignatureTableLock != nil)
        [_NSMethodSignatureTableLock unlock];

    if (signature == nil) {
        NSMapTableKeyCallBacks keyCallbacks = {
            _NSMethodSignatureHashString,
            _NSMethodSignatureEqualString,
            NULL, NULL, NULL, NULL
        };

        signature = _NSMethodSignatureNew(self, normalizedTypes,
                                           typesLength, argumentCount,
                                           &argumentTypes);
        if (_NSMethodSignatureTableLock != nil)
            [_NSMethodSignatureTableLock lock];
        if (_NSMethodSignatureTable == NULL)
            _NSMethodSignatureTable = NSCreateMapTableWithZone(
                keyCallbacks, NSObjectMapValueCallBacks, 0x28, NULL);
        NSMapInsert(_NSMethodSignatureTable,
            ((NSMethodSignatureInstance *)signature)->_types, signature);
        if (_NSMethodSignatureTableLock != nil)
            [_NSMethodSignatureTableLock unlock];
#if defined(__ppc__) || defined(__POWERPC__)
        _NSMethodSignatureCompletePPC(signature, argumentTypes);
#else
        _NSMethodSignatureComplete(signature, argumentTypes);
#endif
    }
    if (normalizedTypes != stackTypes)
        NSZoneFree(NULL, normalizedTypes);
    return signature;
}

- (unsigned)numberOfArguments
{
    return (unsigned)((NSMethodSignatureInstance *)self)->_nargs;
}

/*  Returns the interned copy of the type token consumed by
    NSGetSizeAndAlignment, excluding following frame-offset digits.  */
- (const char *)getArgumentTypeAtIndex:(unsigned)index
{
    NSMethodSignatureInstance *instance = (NSMethodSignatureInstance *)self;
    NSMethodSignatureArgInfo *entries;
    const char *type;
    if (index >= (unsigned)instance->_nargs) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: index out of bounds",
                            _NSMethodExceptionProem(self, _cmd)];
    }

    entries = (NSMethodSignatureArgInfo *)instance->_parmInfoP;
    type = entries[index].type;
    return _NSMethodSignatureUniqueTypeString(type);
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

    return _NSMethodSignatureUniqueTypeString(types);
}

- (unsigned)methodReturnLength
{
    return ((NSMethodSignatureInstance *)self)->_returnValueLength;
}

/*
	The i386 method reports small struct returns in registers; unions and
	all other return types report NO.  The PPC implementation always
	reports NO.  */
- (BOOL)_isReturnStructInRegisters
{
#if defined(__ppc__) || defined(__POWERPC__)
    return NO;
#else
    NSMethodSignatureInstance *instance = (NSMethodSignatureInstance *)self;

    if (instance->_types[0] != '{')
        return NO;
    return (instance->_returnValueLength == 1 ||
            instance->_returnValueLength == 2 ||
            instance->_returnValueLength == 4 ||
            instance->_returnValueLength == 8) ? YES : NO;
#endif
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
    NSMethodSignatureInstance *instance = (NSMethodSignatureInstance *)self;
    NSMethodSignatureArgInfo *entries;
    NSMethodSignatureArgumentInfo out;

    if (index >= (unsigned)instance->_nargs) {
        [NSException raise:NSInvalidArgumentException
                    format:@"index out of bounds"];
    }

    entries = (NSMethodSignatureArgInfo *)instance->_parmInfoP;
    out.offset = (int)entries[index].offset;
    out.size = (int)entries[index].size;
    out.type = entries[index].type;
    out.unused0 = entries[index].unused0;
    out.unused1 = (int)entries[index].unused1;
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

static NSString *NSMethodSignatureStringFromArgInfo(
    NSMethodSignatureArgInfo *info, unsigned indent, unsigned index)
{
    NSMutableString *result = [NSMutableString string];
    unsigned childIndex;

    [result appendFormat:
        @"%@{%d : type(%s) size(%d) offset(%d)}\n",
        _NSIndentSpace(indent), (int)index, info->type,
        (int)info->size, (int)info->offset];
    for (childIndex = 0; childIndex < info->unused1; childIndex++) {
        NSMethodSignatureArgInfo *children =
            (NSMethodSignatureArgInfo *)info->unused0;
        NSString *child;
        NSString *indentation;

#if defined(__ppc__) || defined(__POWERPC__)
        indentation = _NSIndentSpace(indent + 1);
        child = NSMethodSignatureStringFromArgInfo(
            &children[childIndex], indent + 1, childIndex);
#else
        child = NSMethodSignatureStringFromArgInfo(
            &children[childIndex], indent + 1, childIndex);
        indentation = _NSIndentSpace(indent + 1);
#endif
        [result appendFormat:@"%@%@", indentation, child];
    }
    return result;
}

/*  The target prints the cached type and frame metadata directly.  */
- (NSString *)description
{
    NSMethodSignatureInstance *instance = (NSMethodSignatureInstance *)self;

    return [NSString stringWithFormat:
        @"NSMethodSignature: types=%s nargs=%d sizeOfParams=%d returnValueLength=%d; ",
        instance->_types, instance->_nargs, instance->_sizeofParams,
        instance->_returnValueLength];
}

- (NSString *)debugDescription
{
    NSMethodSignatureInstance *instance = (NSMethodSignatureInstance *)self;
    NSMethodSignatureArgInfo *entries =
        (NSMethodSignatureArgInfo *)instance->_parmInfoP;
    const char *returnType = [self methodReturnType];
#if defined(__ppc__) || defined(__POWERPC__)
    NSMutableString *result = [NSMutableString stringWithFormat:
        @"NSMethodSignature <0x%x> types(%s) nargs(%d) frameSize(%d) retType(%s) retSize(%d)\n",
        (unsigned)self, instance->_types, instance->_nargs,
        instance->_sizeofParams, returnType, instance->_returnValueLength];
#else
    NSMutableString *result = [NSMutableString stringWithFormat:
        @"NSMethodSignature <0x%x> types(%s) nargs(%d) frameSize(%d) retType(%s) retSize(%d)\n",
        (unsigned)self, instance->_types, instance->_nargs,
        instance->_sizeofParams, returnType];
#endif
    unsigned index;

    for (index = 0; index < (unsigned)instance->_nargs; index++)
        [result appendString:
            NSMethodSignatureStringFromArgInfo(&entries[index], 0, index)];
    return result;
}

@end
