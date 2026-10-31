/*	NSSet.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSSet.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSZone.h>
#import <objc/objc-runtime.h>

#include <stdarg.h>
#include <string.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>
#endif

@interface NSConcreteSet : NSSet {
@public
    void *table;
    unsigned _retainCount;
}
@end

@interface NSConcreteMutableSet : NSMutableSet {
@public
    void *table;
    unsigned _retainCount;
}
@end

@interface _NSSetEnumerator : NSEnumerator {
    NSSet *_target;
    void *_table;
    unsigned _slot;
    char _countedSet;
}
- (id)initWithSet:(NSSet *)aSet;
@end

@interface NSSet (NSSetPrivate)
- (unsigned)countForObject:(id)object;
@end

NSConcreteSet *__NSEmptySet;
extern Class __NSSetClass;
extern Class __NSConcreteSetClass;
extern Class __NSMutableSetClass;
extern Class __NSConcreteMutableSetClass;
extern Class __NSCountedSetClass;

extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern NSLock *_NSGlobalRetainLock;
extern void _NSIncrementInternalRefCount(id object, unsigned *refCount,
                                         int mask, id lock);
extern BOOL _NSDecrementInternalRefCountWasZero(id object,
                                                 unsigned *refCount,
                                                 int mask, id lock);
extern unsigned _NSInternalRefCount(id object, unsigned refCount, int mask);

typedef struct NSSimpleDictionary NSSimpleDictionary;
typedef struct NSSimpleSet NSSimpleSet;

typedef struct {
    unsigned hashAndState;
    void *key;
    void *value;
} NSSimpleDictionaryBucket;

typedef struct {
    unsigned hashAndState;
    void *value;
} NSSimpleSetBucket;

typedef BOOL (*NSSimpleHashingEqual)(void *, const void *, const void *);

typedef struct {
    void *isa;
    void *table;
} NSCountedSetLayout;

extern NSSimpleDictionary *NSCreateSimpleDictionary(
    unsigned capacity, NSSimpleHashingEqual keysEqual, NSZone *zone);
extern void NSFreeSimpleDictionary(NSSimpleDictionary *table);
extern unsigned NSSimpleDictionaryCount(NSSimpleDictionary *table);
extern unsigned NSSimpleDictionaryNumBuckets(NSSimpleDictionary *table);
extern NSSimpleDictionaryBucket *NSSimpleDictionaryGetBucket(
    NSSimpleDictionary *table, unsigned index);
extern NSSimpleDictionaryBucket *NSSimpleDictionaryLookup(
    NSSimpleDictionary *table, void *key, unsigned hash, void *context);
extern int NSSimpleDictionaryInsert(
    NSSimpleDictionary **tablePointer, void **keyPointer, unsigned hash,
    void **valuePointer, void *context, BOOL replaceValue);
extern int NSSimpleDictionaryDelete(
    NSSimpleDictionary **tablePointer, void **keyPointer, unsigned hash,
    void **valuePointer, void *context);
extern int NSSimpleDictionaryIncrementValue(
    NSSimpleDictionary **tablePointer, void **keyPointer, unsigned hash,
    void *context);
extern int NSSimpleDictionaryDecrementValue(
    NSSimpleDictionary **tablePointer, void **keyPointer, unsigned hash,
    void *context);
extern unsigned NSResetSimpleDictionary(
    NSSimpleDictionary *table,
    int (*releaseEntry)(void *, void *, void *), void *context);
extern NSSimpleSet *NSCreateSimpleSet(
    unsigned capacity, NSSimpleHashingEqual valuesEqual, NSZone *zone);
extern NSSimpleSet *NSCopySimpleSet(NSSimpleSet *source, NSZone *zone);
extern void NSFreeSimpleSet(NSSimpleSet *table);
extern unsigned NSSimpleSetCount(NSSimpleSet *table);
extern unsigned NSSimpleSetNumBuckets(NSSimpleSet *table);
extern NSSimpleSetBucket *NSSimpleSetGetBucket(NSSimpleSet *table,
                                                unsigned index);
extern NSSimpleSetBucket *NSSimpleSetLookup(NSSimpleSet *table, void *value,
                                             unsigned hash, void *context);
extern int NSSimpleSetInsert(NSSimpleSet **tablePointer, void **valuePointer,
                             unsigned hash, void *context, BOOL replaceValue);
extern int NSSimpleSetDelete(NSSimpleSet **tablePointer, void **valuePointer,
                             unsigned hash, void *context);
extern int *NSResetSimpleSet(NSSimpleSet *table,
                             int (*releaseValue)(void *, void *), void *context);
static BOOL _NSSetAreObjectsEqual(void *context, const void *left,
                                  const void *right) {
    (void)context;
    return [(id)left isEqual:(id)right];
}

static int _NSSetDictRelease(void *context, void *key, void *value) {
    (void)context;
    (void)value;
    return (int)(long)objc_msgSend((id)key, @selector(release));
}

static int _NSSetSetRelease(void *context, void *value) {
    (void)context;
    return (int)(long)objc_msgSend((id)value, @selector(release));
}

static void NSSetRetainAllValues(NSSimpleSet *table) {
    unsigned index = NSSimpleSetNumBuckets(table);

    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(table, --index);
        if (bucket != NULL)
            bucket->value = [(id)bucket->value retain];
    }
}

static NSArray *NSSetAllSimpleSetObjects(NSSimpleSet *table,
                                         BOOL sharedWhenEmpty) {
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned count = NSSimpleSetCount(table);
    unsigned index;
    unsigned objectIndex = 0;
    NSArray *array;

    if (count == 0 && sharedWhenEmpty)
        return [NSArray array];
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    index = NSSimpleSetNumBuckets(table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(table, --index);
        if (bucket != NULL)
            objects[objectIndex++] = bucket->value;
    }
    array = [[NSArray allocWithZone:NULL] initWithObjects:objects
                                                     count:count];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return [array autorelease];
}

#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSSetRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSSetLockConcreteRetainCount(void)
{
    if (!_NSIsMultiThreaded)
        return NO;
    for (;;) {
        unsigned oldValue;
        unsigned acquired;
        unsigned one = 1;

        __asm__ volatile(
            "1: lwarx %0,0,%2\n\t"
            "cmpwi %0,0\n\t"
            "bne- 2f\n\t"
            "stwcx. %3,0,%2\n\t"
            "bne- 1b\n\t"
            "isync\n\t"
            "li %1,1\n\t"
            "b 3f\n"
            "2: li %1,0\n"
            "3:"
            : "=&r" (oldValue), "=&r" (acquired)
            : "r" (&__NSSetRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
}

static void NSSetUnlockConcreteRetainCount(BOOL locked)
{
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSSetRetainLock = 0;
    }
}

static void NSSetIncrementConcreteRetainCount(id object, unsigned *count)
{
    BOOL locked = NSSetLockConcreteRetainCount();

    if (*count != 0xffffffffU)
        ++*count;
    NSSetUnlockConcreteRetainCount(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, object);
}

static BOOL NSSetDecrementConcreteRetainCount(id object, unsigned *count)
{
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, object);
    locked = NSSetLockConcreteRetainCount();
    if (*count != 0) {
        if (*count != 0xffffffffU)
            --*count;
    } else {
        shouldDeallocate = YES;
    }
    NSSetUnlockConcreteRetainCount(locked);
    return shouldDeallocate;
}
#else
static void NSSetIncrementConcreteRetainCount(id object, unsigned *count)
{
    _NSIncrementInternalRefCount(object, count, -1, _NSGlobalRetainLock);
}

static BOOL NSSetDecrementConcreteRetainCount(id object, unsigned *count)
{
    return _NSDecrementInternalRefCountWasZero(
        object, count, -1, _NSGlobalRetainLock);
}
#endif

static void NSSetCheckSize(id object, SEL selector, unsigned count,
                           const char *sizeName) {
    if (count > 0x0fffffffU) {
        id proem = _NSMethodExceptionProem(object, selector);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: absurd %s: %d", proem, sizeName, count];
    }
}

static void NSSetRaiseInsertNilException(id object, SEL selector) {
    id proem = _NSMethodExceptionProem(object, selector);
    [NSException raise:NSInvalidArgumentException
                format:@"%@: attempt to insert nil", proem];
}

static void NSSetRaiseRemoveNilException(id object, SEL selector) {
    id proem = _NSMethodExceptionProem(object, selector);
    [NSException raise:NSInvalidArgumentException
                format:@"%@: attempt to remove nil", proem];
}

@implementation NSSet

- (unsigned)count {
    NSRequestConcreteImplementation(self, _cmd, __NSSetClass);
    return 0;
}

- (id)member:(id)object {
    NSRequestConcreteImplementation(self, _cmd, __NSSetClass);
    return nil;
}

- (NSEnumerator *)objectEnumerator {
    NSRequestConcreteImplementation(self, _cmd, __NSSetClass);
    return nil;
}

- (NSArray *)allObjects {
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned count = [self count];
    unsigned objectIndex = 0;
    NSArray *array;
    NSEnumerator *enumerator;
    id object;

    if (count == 0)
        return [NSArray array];
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    enumerator = [self objectEnumerator];
    while ((object = [enumerator nextObject]) != nil)
        objects[objectIndex++] = object;
    array = [[[NSArray allocWithZone:NULL] initWithObjects:objects
                                                     count:count] autorelease];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return array;
}

- (id)anyObject {
    if ([self count] == 0)
        return nil;
    return [[self objectEnumerator] nextObject];
}

- (BOOL)containsObject:(id)object {
    return object != nil && [self member:object] != nil;
}

- (unsigned)countForObject:(id)object {
    return [self member:object] != nil;
}

- (BOOL)intersectsSet:(NSSet *)otherSet {
    NSEnumerator *enumerator;
    id object;

    if (otherSet == nil || [otherSet count] == 0 || [self count] == 0)
        return NO;
    enumerator = [self objectEnumerator];
    while ((object = [enumerator nextObject]) != nil) {
        if ([otherSet member:object] != nil)
            return YES;
    }
    return NO;
}

- (BOOL)isEqualToSet:(NSSet *)otherSet {
#if defined(__ppc__) || defined(__POWERPC__)
    NSEnumerator *enumerator;
    id object;
    id otherMember;
    id selfMember;
    unsigned count;

    count = [self count];
    if (otherSet == nil || count != [otherSet count])
        return NO;
    if (count == 0)
        return YES;
    enumerator = [self objectEnumerator];
    while ((object = [enumerator nextObject]) != nil) {
        otherMember = [otherSet member:object];
        selfMember = [self member:object];
        if (otherMember != selfMember)
            return NO;
    }
    return YES;
#else
    NSEnumerator *enumerator;
    id object;
    unsigned count;
    unsigned otherObjectCount;
    unsigned selfObjectCount;

    count = [self count];
    if (otherSet == nil || count != [otherSet count])
        return NO;
    if (count == 0)
        return YES;
    enumerator = [self objectEnumerator];
    while ((object = [enumerator nextObject]) != nil) {
        otherObjectCount = [otherSet countForObject:object];
        selfObjectCount = [self countForObject:object];
        if (otherObjectCount != selfObjectCount)
            return NO;
    }
    return YES;
#endif
}

- (BOOL)isSubsetOfSet:(NSSet *)otherSet {
    NSEnumerator *enumerator;
    id object;
    unsigned count;
    unsigned otherObjectCount;
    unsigned selfObjectCount;

    count = [self count];
    if (otherSet == nil || count > [otherSet count])
        return NO;
    if (count == 0)
        return YES;
    enumerator = [self objectEnumerator];
    while ((object = [enumerator nextObject]) != nil) {
        otherObjectCount = [otherSet countForObject:object];
        selfObjectCount = [self countForObject:object];
        if (otherObjectCount < selfObjectCount)
            return NO;
    }
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass:[NSSet class]])
        return NO;
    return [self isEqualToSet:object];
}

- (Class)classForCoder {
    return __NSSetClass;
}

- (id)copyWithZone:(NSZone *)zone {
    id copy = NSAllocateObject(__NSConcreteSetClass, 0, zone);
    return [copy initWithSet:self copyItems:YES];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    id copy = NSAllocateObject(__NSConcreteMutableSetClass, 0, zone);
    return [copy initWithSet:self copyItems:NO];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    unsigned count = [self count];

    [coder encodeValueOfObjCType:"I" at:&count];
    if (count != 0) {
        NSEnumerator *enumerator = [self objectEnumerator];
        id object;

        while ((object = [enumerator nextObject]) != nil)
            [coder encodeBycopyObject:object];
    }
}

- (id)initWithCoder:(NSCoder *)coder {
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned count;
    unsigned index;
    id result;

    [coder decodeValueOfObjCType:"I" at:&count];
    if (count == 0)
        return [self initWithObjects:NULL count:0];
    NSSetCheckSize(self, _cmd, count, "count");
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    for (index = 0; index < count; index++)
        [coder decodeValueOfObjCType:"@" at:&objects[index]];
    result = [self initWithObjects:objects count:count];
    for (index = 0; index < count; index++)
        [objects[index] release];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return result;
}

- (unsigned)hash {
    return [self count];
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    if (![coder isByref])
        return self;
    return [NSDistantObject proxyWithLocal:self connection:[coder connection]];
}

- (void)makeObjectsPerformSelector:(SEL)selector {
    NSEnumerator *enumerator;
    id object;

    if ([self count] != 0) {
        enumerator = [self objectEnumerator];
        while ((object = [enumerator nextObject]) != nil)
            [object performSelector:selector];
    }
}

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument {
    NSEnumerator *enumerator;
    id object;

    if ([self count] != 0) {
        enumerator = [self objectEnumerator];
        while ((object = [enumerator nextObject]) != nil)
            [object performSelector:selector withObject:argument];
    }
}

- (void)makeObjectsPerform:(SEL)selector {
    [self makeObjectsPerformSelector:selector];
}

- (void)makeObjectsPerform:(SEL)selector withObject:(id)argument {
    [self makeObjectsPerformSelector:selector withObject:argument];
}

- (NSArray *)members:(NSArray *)objects notFoundMarker:(id)marker {
    id stackObjects[128];
    id *members = stackObjects;
    unsigned count = [objects count];
    unsigned index;
    NSArray *result;

    if (count == 0)
        return [NSArray array];
    if (count > 128)
        members = NSZoneMalloc(NULL, count * sizeof(id));
    for (index = 0; index < count; index++) {
        id member = [self member:[objects objectAtIndex:index]];
        members[index] = member != nil ? member : marker;
    }
    result = [[[NSArray allocWithZone:NULL]
        initWithObjects:members count:count] autorelease];
    if (members != stackObjects)
        NSZoneFree(NULL, members);
    return result;
}

- (NSString *)description {
    return [self descriptionWithLocale:nil];
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    NSMutableString *result;
    NSEnumerator *enumerator;
    id object;
    unsigned count = [self count];
    BOOL first = YES;
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned descriptionIndex;
#endif

    if (count == 0)
        return [NSString stringWithFormat:@"<%s: 0x%x> ()",
                  self->isa->name, (unsigned)self];

    result = [[[NSMutableString allocWithZone:NULL]
        initWithCapacity:count << 6] autorelease];
    [result appendFormat:@"<%s: 0x%x> (",
        self->isa->name, (unsigned)self];
    enumerator = [self objectEnumerator];

    while ((object = [enumerator nextObject]) != nil) {
        NSString *description;

        if (!first)
#if defined(__ppc__) || defined(__POWERPC__)
            [result replaceCharactersInRange:NSMakeRange([result length], 0)
                                   withString:@", "];
#else
            [result replaceCharactersInRange:NSMakeRange([result length], 0) withString:@", "];
#endif
        if ([object respondsToSelector:@selector(descriptionWithLocale:)]) {
#if defined(__ppc__) || defined(__POWERPC__)
            descriptionIndex = [result length];
#endif
            description = [object descriptionWithLocale:locale];
        } else {
#if defined(__ppc__) || defined(__POWERPC__)
            descriptionIndex = [result length];
#endif
            description = [object description];
        }
#if defined(__ppc__) || defined(__POWERPC__)
        [result replaceCharactersInRange:NSMakeRange(descriptionIndex, 0)
                               withString:description];
#else
        [result replaceCharactersInRange:NSMakeRange([result length], 0) withString:description];
#endif
        first = NO;
    }
#if defined(__ppc__) || defined(__POWERPC__)
    [result replaceCharactersInRange:NSMakeRange([result length], 0)
                           withString:@")"];
#else
    [result replaceCharactersInRange:NSMakeRange([result length], 0) withString:@")"];
#endif
    return result;
}

+ (id)allocWithZone:(NSZone *)zone {
    Class setClass = self;

    if (self == __NSSetClass)
        setClass = __NSConcreteSetClass;
    return NSAllocateObject(setClass, 0, zone);
}

+ (id)set {
    if (self == __NSSetClass) {
        if (__NSEmptySet == nil)
            __NSEmptySet = NSAllocateObject(__NSConcreteSetClass, 0, NULL);
        return __NSEmptySet;
    }
    return [[[self allocWithZone:NULL] initWithObjects:NULL count:0] autorelease];
}

+ (id)setWithArray:(NSArray *)array {
    return [[[self allocWithZone:NULL] initWithArray:array] autorelease];
}

+ (id)setWithObject:(id)object {
    return [[[self allocWithZone:NULL] initWithObjects:&object count:1]
        autorelease];
}

+ (id)setWithObjects:(id)firstObject, ... {
    id stackObjects[128];
    id *objects = NULL;
    unsigned count = 0;
    unsigned index;
    id set;
    va_list arguments;

    if (firstObject != nil) {
        count = 1;
        va_start(arguments, firstObject);
        while (va_arg(arguments, id) != nil)
            count++;
        va_end(arguments);

        if (count > 128)
            objects = NSZoneMalloc(NULL, count * sizeof(id));
        else
            objects = stackObjects;
        objects[0] = firstObject;

        va_start(arguments, firstObject);
        for (index = 1; index < count; index++)
            objects[index] = va_arg(arguments, id);
        va_end(arguments);
    }

    set = [[self allocWithZone:NULL] initWithObjects:objects count:count];
    set = [set autorelease];
    if (objects != NULL && objects != stackObjects)
        NSZoneFree(NULL, objects);
    return set;
}

- (id)initWithArray:(NSArray *)array {
    unsigned count = [array count];
    id stackObjects[128];
    id *objects;
    unsigned index;

    if (count == 0)
        return [self initWithObjects:NULL count:0];
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    else
        objects = stackObjects;
    if ([array isProxy]) {
        for (index = 0; index < count; index++)
            objects[index] = [array objectAtIndex:index];
    } else {
        [array getObjects:objects range:NSMakeRange(0, count)];
    }
    self = [self initWithObjects:objects count:count];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return self;
}

- (id)initWithObjects:(id *)objects count:(unsigned)count {
    (void)objects;
    (void)count;
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithObjects:(id)firstObject, ... {
    id stackObjects[128];
    id *objects = NULL;
    unsigned count = 0;
    unsigned index;
    va_list arguments;

    if (firstObject != nil) {
        count = 1;
        va_start(arguments, firstObject);
        while (va_arg(arguments, id) != nil)
            count++;
        va_end(arguments);

        if (count > 128)
            objects = NSZoneMalloc(NULL, count * sizeof(id));
        else
            objects = stackObjects;
        objects[0] = firstObject;

        va_start(arguments, firstObject);
        for (index = 1; index < count; index++)
            objects[index] = va_arg(arguments, id);
        va_end(arguments);
    }

    self = [self initWithObjects:objects count:count];
    if (objects != NULL && objects != stackObjects)
        NSZoneFree(NULL, objects);
    return self;
}

- (id)initWithSet:(NSSet *)set {
    return [self initWithSet:set copyItems:NO];
}

- (id)initWithSet:(NSSet *)set copyItems:(BOOL)copyItems {
    unsigned count = [set count];
    id stackObjects[128];
    id *objects = stackObjects;
    NSEnumerator *enumerator;
    NSZone *zone;
    unsigned index;
    id object;

    if (count == 0)
        return [self initWithObjects:NULL count:0];
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    zone = copyItems ? NSZoneFromPointer(self) : NULL;
    enumerator = [set objectEnumerator];
    index = 0;
    while ((object = [enumerator nextObject]) != nil)
        objects[index++] = copyItems ? [object copyWithZone:zone] : object;
    self = [self initWithObjects:objects count:count];
    if (copyItems)
        for (index = 0; index < count; index++)
            [objects[index] release];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return self;
}

+ (id)setWithSet:(NSSet *)set {
    return [[[self allocWithZone:NULL] initWithSet:set] autorelease];
}

+ (id)setWithObjects:(id *)objects count:(unsigned)count {
    return [[[self allocWithZone:NULL] initWithObjects:objects count:count]
        autorelease];
}

@end

@implementation NSConcreteSet

- (id)init {
    return [self initWithObjects:NULL count:0];
}

- (id)initWithObjects:(id *)objects count:(unsigned)count {
    unsigned index;

    if (count == 0) {
        if (__NSEmptySet == nil)
            __NSEmptySet = NSAllocateObject(__NSConcreteSetClass, 0, NULL);
        NSDeallocateObject(self);
        return [__NSEmptySet retain];
    }
    NSSetCheckSize(self, _cmd, count, "count");
    table = NSCreateSimpleSet(count, _NSSetAreObjectsEqual,
                              NSZoneFromPointer(self));
    for (index = 0; index < count; index++) {
        void *object = objects[index];

        if (objects[index] == nil)
            NSSetRaiseInsertNilException(self, _cmd);
        if (NSSimpleSetInsert((NSSimpleSet **)&table, &object,
                              [(id)object hash], NULL, NO))
            [(id)object retain];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    unsigned count = table != NULL ? NSSimpleSetCount((NSSimpleSet *)table) : 0;

    [coder encodeValueOfObjCType:"I" at:&count];
    if (count != 0) {
        unsigned bucketIndex = NSSimpleSetNumBuckets((NSSimpleSet *)table);

        while (bucketIndex != 0) {
            NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
                (NSSimpleSet *)table, --bucketIndex);
            if (bucket != NULL)
                [coder encodeBycopyObject:bucket->value];
        }
    }
}

- (unsigned)count {
    return table != NULL ? NSSimpleSetCount((NSSimpleSet *)table) : 0;
}

- (id)member:(id)object {
    NSSimpleSetBucket *bucket;

    if (table == NULL || object == nil)
        return nil;
    bucket = NSSimpleSetLookup((NSSimpleSet *)table, object,
                               [object hash], NULL);
    return bucket != NULL ? bucket->value : nil;
}

- (BOOL)containsObject:(id)object {
    if (object == nil || table == NULL)
        return NO;
    return NSSimpleSetLookup((NSSimpleSet *)table, object,
                             [object hash], NULL) != NULL;
}

- (NSEnumerator *)objectEnumerator {
    NSZone *zone;
    Class enumeratorClass;

#if defined(__ppc__) || defined(__POWERPC__)
    enumeratorClass = [_NSSetEnumerator class];
    zone = NSZoneFromPointer(self);
#else
    zone = NSZoneFromPointer(self);
    enumeratorClass = [_NSSetEnumerator class];
#endif
    return [[NSAllocateObject(enumeratorClass, 0, zone) initWithSet:self]
        autorelease];
}

- (NSArray *)allObjects {
    return table != NULL ? NSSetAllSimpleSetObjects((NSSimpleSet *)table, NO)
                         : [NSArray array];
}

- (id)anyObject {
    NSSimpleSet *set = (NSSimpleSet *)table;
    unsigned bucketIndex;

    if (set == NULL)
        return nil;
    bucketIndex = NSSimpleSetNumBuckets(set);
    while (bucketIndex != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(set, --bucketIndex);
        if (bucket != NULL)
            return bucket->value;
    }
    return nil;
}

- (unsigned)countForObject:(id)object {
    if (object == nil || table == NULL)
        return 0;
    return NSSimpleSetLookup((NSSimpleSet *)table, object,
                             [object hash], NULL) != NULL;
}

- (BOOL)intersectsSet:(NSSet *)otherSet {
    unsigned index;

    if (otherSet == nil || table == NULL || [otherSet count] == 0)
        return NO;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL && [otherSet member:bucket->value] != nil)
            return YES;
    }
    return NO;
}

- (BOOL)isEqualToSet:(NSSet *)otherSet {
    unsigned count = table != NULL ? NSSimpleSetCount((NSSimpleSet *)table) : 0;
    unsigned index;

    if (otherSet == nil || count != [otherSet count])
        return NO;
    if (count == 0)
        return YES;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL && [otherSet member:bucket->value] == nil)
            return NO;
    }
    return YES;
}

- (BOOL)isSubsetOfSet:(NSSet *)otherSet {
    unsigned count = table != NULL ? NSSimpleSetCount((NSSimpleSet *)table) : 0;
    unsigned index;

    if (otherSet == nil || [otherSet count] < count)
        return NO;
    if (count == 0)
        return YES;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL && [otherSet member:bucket->value] == nil)
            return NO;
    }
    return YES;
}

- (void)makeObjectsPerformSelector:(SEL)selector {
    unsigned index;

    if (table == NULL)
        return;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL)
            [(id)bucket->value performSelector:selector];
    }
}

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument {
    unsigned index;

    if (table == NULL)
        return;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL)
            [(id)bucket->value performSelector:selector withObject:argument];
    }
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (id)retain {
    NSSetIncrementConcreteRetainCount(self, &((NSConcreteSet *)self)->_retainCount);
    return self;
}

- (oneway void)release {
    if (NSSetDecrementConcreteRetainCount(
            self, &((NSConcreteSet *)self)->_retainCount))
        [self dealloc];
}

- (unsigned)retainCount {
#if defined(__ppc__) || defined(__POWERPC__)
    return ((NSConcreteSet *)self)->_retainCount + 1;
#else
    return _NSInternalRefCount(self,
        ((NSConcreteSet *)self)->_retainCount, -1);
#endif
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    if (table == NULL)
        return [[NSMutableSet allocWithZone:NULL] initWithCapacity:0];
    NSConcreteMutableSet *copy = NSAllocateObject(
        __NSConcreteMutableSetClass, 0, zone);
    copy->table = NSCopySimpleSet((NSSimpleSet *)table, zone);
    NSSetRetainAllValues((NSSimpleSet *)copy->table);
    return copy;
}

- (void)dealloc {
    if (table != NULL) {
        NSSimpleSet *simpleSet = table;
        if (NSSimpleSetCount(simpleSet) != 0)
            NSResetSimpleSet(simpleSet, _NSSetSetRelease, NULL);
        NSFreeSimpleSet(simpleSet);
    }
    [super dealloc];
}

@end

@implementation _NSSetEnumerator

- (id)initWithSet:(NSSet *)aSet {
    _slot = 0;
    _countedSet = [aSet isKindOfClass:[NSCountedSet class]];
    if (_countedSet) {
        _table = ((NSCountedSetLayout *)aSet)->table;
        if (_table != NULL)
            _slot = NSSimpleDictionaryNumBuckets(
                (NSSimpleDictionary *)_table);
    } else {
        _table = ((NSConcreteSet *)aSet)->table;
        if (_table != NULL)
            _slot = NSSimpleSetNumBuckets((NSSimpleSet *)_table);
    }
    if (_slot != 0)
        _target = [aSet retain];
    return self;
}

- (id)nextObject {
    if (_target == nil)
        return nil;
    while (_slot != 0) {
        if (_countedSet) {
            NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
                (NSSimpleDictionary *)_table, _slot - 1);
            --_slot;
            if (bucket != NULL)
                return bucket->key;
        } else {
            NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
                (NSSimpleSet *)_table, _slot - 1);
            --_slot;
            if (bucket != NULL)
                return bucket->value;
        }
    }
    [_target release];
    _target = nil;
    return nil;
}

- (void)dealloc {
    [_target release];
    [super dealloc];
}

@end

@implementation NSMutableSet

- (void)addObject:(id)object {
    NSRequestConcreteImplementation(self, _cmd, __NSMutableSetClass);
}

- (void)removeObject:(id)object {
    NSRequestConcreteImplementation(self, _cmd, __NSMutableSetClass);
}

- (void)addObjectsFromArray:(NSArray *)array {
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned count = [array count];

    if (count == 0)
        return;
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    if ([array isProxy]) {
        unsigned index;

        for (index = 0; index < count; index++)
            objects[index] = [array objectAtIndex:index];
    } else {
        [array getObjects:objects range:NSMakeRange(0, count)];
    }
    while (count > 0)
        [self addObject:objects[--count]];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
}

- (void)intersectSet:(NSSet *)otherSet {
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned objectCount = 0;
    unsigned capacity = 128;
    NSEnumerator *enumerator;
    id object;

    if (otherSet == self)
        return;
    if (otherSet == nil || [otherSet count] == 0) {
        [self removeAllObjects];
        return;
    }
    enumerator = [self objectEnumerator];
    while ((object = [enumerator nextObject]) != nil) {
        unsigned otherCount = [otherSet countForObject:object];
        unsigned ownCount = [self countForObject:object];

        if (otherCount < ownCount) {
            unsigned additional = ownCount - otherCount;
            unsigned required = objectCount + additional;

            if (required >= capacity) {
                unsigned newCapacity = objects == stackObjects ? 512 : capacity;

                while (newCapacity < required)
                    newCapacity *= 2;
                if (objects == stackObjects) {
                    id *newObjects = NSZoneMalloc(NULL,
                        newCapacity * sizeof(id));
                    memmove(newObjects, stackObjects,
                            objectCount * sizeof(id));
                    objects = newObjects;
                } else {
                    objects = NSZoneRealloc(NULL, objects,
                        newCapacity * sizeof(id));
                }
                capacity = newCapacity;
            }
            while (additional-- > 0)
                objects[objectCount++] = object;
        }
    }
    while (objectCount > 0)
        [self removeObject:objects[--objectCount]];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
}

- (void)minusSet:(NSSet *)otherSet {
    NSEnumerator *enumerator;
    id object;

    if (otherSet == nil || [otherSet count] == 0)
        return;
    if (otherSet == self) {
        [self removeAllObjects];
        return;
    }
    enumerator = [otherSet objectEnumerator];
    while ((object = [enumerator nextObject]) != nil) {
        unsigned count = [otherSet countForObject:object];

        while (count > 0) {
            [self removeObject:object];
            count--;
        }
    }
}

- (void)removeAllObjects {
    unsigned count = [self count];
    id stackObjects[128];
    id *objects = stackObjects;
    NSArray *allObjectsArray;

    if (count == 0)
        return;
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    allObjectsArray = [self allObjects];
    if ([allObjectsArray isProxy]) {
        unsigned index;

        for (index = 0; index < count; index++)
            objects[index] = [allObjectsArray objectAtIndex:index];
    } else {
        [allObjectsArray getObjects:objects range:NSMakeRange(0, count)];
    }
    while (count > 0)
        [self removeObject:objects[--count]];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
}

- (void)unionSet:(NSSet *)otherSet {
    NSEnumerator *enumerator;
    id object;

    if (otherSet == nil || otherSet == self || [otherSet count] == 0)
        return;
    enumerator = [otherSet objectEnumerator];
    while ((object = [enumerator nextObject]) != nil) {
        unsigned count = [otherSet countForObject:object];

        while (count > 0) {
            [self addObject:object];
            count--;
        }
    }
}

- (void)setSet:(NSSet *)otherSet {
    if (otherSet != nil && otherSet != self) {
        NSEnumerator *enumerator;
        id object;

        [self removeAllObjects];
        if ([otherSet count] != 0) {
            enumerator = [otherSet objectEnumerator];
            while ((object = [enumerator nextObject]) != nil) {
                unsigned count = [otherSet countForObject:object];

                while (count > 0) {
                    [self addObject:object];
                    count--;
                }
            }
        }
    }
}

+ (id)allocWithZone:(NSZone *)zone {
    Class setClass = self;

    if (self == __NSMutableSetClass)
        setClass = __NSConcreteMutableSetClass;
    return NSAllocateObject(setClass, 0, zone);
}

+ (id)setWithCapacity:(unsigned)capacity {
    return [[[self allocWithZone:NULL] initWithCapacity:capacity] autorelease];
}

- (id)initWithCapacity:(unsigned)capacity {
    (void)capacity;
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return nil;
}

- (Class)classForCoder {
    return __NSMutableSetClass;
}

- (id)initWithObjects:(id *)objects count:(unsigned)count {
    unsigned index;

    NSSetCheckSize(self, _cmd, count, "count");
    self = [self initWithCapacity:count];
    for (index = 0; index < count; index++)
        [self addObject:objects[index]];
    return self;
}

- (id)initWithCoder:(NSCoder *)coder {
    unsigned count;
    unsigned index;

    [coder decodeValueOfObjCType:"I" at:&count];
    NSSetCheckSize(self, _cmd, count, "count");
    self = [self initWithCapacity:count];
    for (index = 0; index < count; index++) {
        id object = nil;

        [coder decodeValueOfObjCType:"@" at:&object];
        if (object == nil)
            NSSetRaiseInsertNilException(self, _cmd);
        [self addObject:object];
        [object release];
    }
    return self;
}

@end

@implementation NSConcreteMutableSet

- (id)init {
    return [self initWithCapacity:0];
}

- (unsigned)count {
    return NSSimpleSetCount((NSSimpleSet *)table);
}

- (id)member:(id)object {
    NSSimpleSetBucket *bucket;

    if (object == nil)
        return nil;
    bucket = NSSimpleSetLookup((NSSimpleSet *)table, object,
                               [object hash], NULL);
    return bucket != NULL ? bucket->value : nil;
}

- (NSEnumerator *)objectEnumerator {
    return [[[_NSSetEnumerator allocWithZone:[self zone]]
        initWithSet:self] autorelease];
}

- (NSArray *)allObjects {
    return NSSetAllSimpleSetObjects((NSSimpleSet *)table, YES);
}

- (id)anyObject {
    NSSimpleSet *set = (NSSimpleSet *)table;
    unsigned bucketIndex;

    if (NSSimpleSetCount(set) == 0)
        return nil;
    bucketIndex = NSSimpleSetNumBuckets(set);
    while (bucketIndex != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(set, --bucketIndex);
        if (bucket != NULL)
            return bucket->value;
    }
    return nil;
}

- (unsigned)countForObject:(id)object {
    if (object == nil)
        return 0;
    return NSSimpleSetLookup((NSSimpleSet *)table, object,
                             [object hash], NULL) != NULL;
}

- (void)addObjectsFromArray:(NSArray *)array {
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned count = [array count];

    if (count == 0)
        return;
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    if ([array isProxy]) {
        unsigned index;

        for (index = 0; index < count; index++)
            objects[index] = [array objectAtIndex:index];
    } else {
        [array getObjects:objects range:NSMakeRange(0, count)];
    }
    while (count > 0) {
        void *object = objects[--count];

        if (NSSimpleSetInsert((NSSimpleSet **)&table, &object,
                              [(id)object hash], NULL, NO))
            [(id)object retain];
    }
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
}

- (void)encodeWithCoder:(NSCoder *)coder {
    unsigned count = NSSimpleSetCount((NSSimpleSet *)table);

    [coder encodeValueOfObjCType:"I" at:&count];
    if (count != 0) {
        unsigned bucketIndex = NSSimpleSetNumBuckets((NSSimpleSet *)table);

        while (bucketIndex != 0) {
            NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
                (NSSimpleSet *)table, --bucketIndex);
            if (bucket != NULL)
                [coder encodeBycopyObject:bucket->value];
        }
    }
}

- (id)initWithCoder:(NSCoder *)coder {
    unsigned count;
    unsigned index;

    [coder decodeValueOfObjCType:"I" at:&count];
    NSSetCheckSize(self, _cmd, count, "count");
    self = [self initWithCapacity:count];
    for (index = 0; index < count; index++) {
        void *object = NULL;
        void *key;

        [coder decodeValueOfObjCType:"@" at:&object];
        if (object == NULL)
            NSSetRaiseInsertNilException(self, _cmd);
        key = object;
        if (!NSSimpleSetInsert((NSSimpleSet **)&table, &key,
                              [(id)object hash], NULL, NO))
            [(id)object release];
    }
    return self;
}

- (BOOL)intersectsSet:(NSSet *)otherSet {
    unsigned index;

    if (otherSet == nil || NSSimpleSetCount((NSSimpleSet *)table) == 0 ||
        [otherSet count] == 0)
        return NO;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL && [otherSet member:bucket->value] != nil)
            return YES;
    }
    return NO;
}

- (BOOL)isEqualToSet:(NSSet *)otherSet {
    unsigned count = NSSimpleSetCount((NSSimpleSet *)table);
    unsigned index;

    if (otherSet == nil || count != [otherSet count])
        return NO;
    if (count == 0)
        return YES;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL && [otherSet member:bucket->value] == nil)
            return NO;
    }
    return YES;
}

- (BOOL)isSubsetOfSet:(NSSet *)otherSet {
    unsigned count = NSSimpleSetCount((NSSimpleSet *)table);
    unsigned index;

    if (otherSet == nil || [otherSet count] < count)
        return NO;
    if (count == 0)
        return YES;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL && [otherSet member:bucket->value] == nil)
            return NO;
    }
    return YES;
}

- (void)intersectSet:(NSSet *)otherSet {
    unsigned index;

    if (otherSet == self)
        return;
    if (otherSet == nil || [otherSet count] == 0) {
        NSResetSimpleSet((NSSimpleSet *)table, _NSSetSetRelease, NULL);
        return;
    }
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL && [otherSet member:bucket->value] == nil) {
            void *object = bucket->value;
            unsigned hash = [object hash];

            if (NSSimpleSetDelete((NSSimpleSet **)&table, &object,
                                  hash, NULL))
                [(id)object release];
        }
    }
}

- (void)makeObjectsPerformSelector:(SEL)selector {
    unsigned index;

    if (NSSimpleSetCount((NSSimpleSet *)table) == 0)
        return;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL)
            [(id)bucket->value performSelector:selector];
    }
}

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument {
    unsigned index;

    if (NSSimpleSetCount((NSSimpleSet *)table) == 0)
        return;
    index = NSSimpleSetNumBuckets((NSSimpleSet *)table);
    while (index != 0) {
        NSSimpleSetBucket *bucket = NSSimpleSetGetBucket(
            (NSSimpleSet *)table, --index);
        if (bucket != NULL)
            [(id)bucket->value performSelector:selector withObject:argument];
    }
}

- (id)copyWithZone:(NSZone *)zone {
    if (NSSimpleSetCount((NSSimpleSet *)table) != 0) {
        NSConcreteSet *copy = NSAllocateObject(__NSConcreteSetClass, 0, zone);
        copy->table = NSCopySimpleSet((NSSimpleSet *)table, zone);
        NSSetRetainAllValues((NSSimpleSet *)copy->table);
        return copy;
    } else {
        return [[NSSet allocWithZone:NULL] init];
    }
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSConcreteMutableSet *copy = NSAllocateObject(
        __NSConcreteMutableSetClass, 0, zone);
    copy->table = NSCopySimpleSet((NSSimpleSet *)table, zone);
    NSSetRetainAllValues((NSSimpleSet *)copy->table);
    return copy;
}

- (id)retain {
    NSSetIncrementConcreteRetainCount(self, &_retainCount);
    return self;
}

- (oneway void)release {
    if (NSSetDecrementConcreteRetainCount(self, &_retainCount))
        [self dealloc];
}

- (unsigned)retainCount {
#if defined(__ppc__) || defined(__POWERPC__)
    return _retainCount + 1;
#else
    return _NSInternalRefCount(self, _retainCount, -1);
#endif
}

- (id)initWithCapacity:(unsigned)capacity {
    NSSetCheckSize(self, _cmd, capacity, "capacity");
    table = NSCreateSimpleSet(capacity, _NSSetAreObjectsEqual,
                              NSZoneFromPointer(self));
    return self;
}

- (id)initWithObjects:(id *)objects count:(unsigned)count {
    unsigned index;

    NSSetCheckSize(self, _cmd, count, "count");
    self = [self initWithCapacity:count];
    for (index = 0; index < count; index++) {
        void *object = objects[index];

        if (objects[index] == nil)
            NSSetRaiseInsertNilException(self, _cmd);
        if (NSSimpleSetInsert((NSSimpleSet **)&table, &object,
                              [(id)object hash], NULL, NO))
            [(id)object retain];
    }
    return self;
}

- (void)addObject:(id)object {
    void *value = object;

    if (object == nil)
        NSSetRaiseInsertNilException(self, _cmd);
    if (NSSimpleSetInsert((NSSimpleSet **)&table, &value,
                          [object hash], NULL, NO))
        [(id)value retain];
}

- (void)removeObject:(id)object {
    void *value = object;

    if (object == nil)
        NSSetRaiseRemoveNilException(self, _cmd);
    if (NSSimpleSetCount((NSSimpleSet *)table) != 0 &&
        NSSimpleSetDelete((NSSimpleSet **)&table, &value,
                          [object hash], NULL))
        [(id)value release];
}

- (void)removeAllObjects {
    NSResetSimpleSet((NSSimpleSet *)table, _NSSetSetRelease, NULL);
}

- (void)dealloc {
    if (table != NULL) {
        NSSimpleSet *simpleSet = table;
        if (NSSimpleSetCount(simpleSet) != 0)
            NSResetSimpleSet(simpleSet, _NSSetSetRelease, NULL);
        NSFreeSimpleSet(simpleSet);
    }
    [super dealloc];
}

@end

@implementation NSCountedSet

- (id)retain
{
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked = NSSetLockConcreteRetainCount();
    unsigned count = (unsigned)(unsigned long)_reserved;

    if (count != 0xffffffffU)
        _reserved = (void *)(unsigned long)(count + 1);
    NSSetUnlockConcreteRetainCount(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
#else
    _NSIncrementInternalRefCount(self, (unsigned *)&_reserved, -1,
                                 _NSGlobalRetainLock);
#endif
    return self;
}

- (oneway void)release
{
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL shouldDeallocate = NO;
    BOOL locked;
    unsigned count;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSSetLockConcreteRetainCount();
    count = (unsigned)(unsigned long)_reserved;
    if (count != 0) {
        if (count != 0xffffffffU)
            _reserved = (void *)(unsigned long)(count - 1);
    } else {
        shouldDeallocate = YES;
    }
    NSSetUnlockConcreteRetainCount(locked);
    if (shouldDeallocate)
        [self dealloc];
#else
    if (_NSDecrementInternalRefCountWasZero(
            self, (unsigned *)&_reserved, -1, _NSGlobalRetainLock))
        [self dealloc];
#endif
}

- (unsigned)retainCount
{
#if defined(__ppc__) || defined(__POWERPC__)
    return (unsigned)(unsigned long)_reserved + 1;
#else
    return _NSInternalRefCount(self, (unsigned)(unsigned long)_reserved, -1);
#endif
}

- (void)makeObjectsPerformSelector:(SEL)selector {
    NSSimpleDictionary *table = (NSSimpleDictionary *)_table;
    unsigned bucketIndex;

    if (NSSimpleDictionaryCount(table) != 0) {
        bucketIndex = NSSimpleDictionaryNumBuckets(table);
        while (bucketIndex != 0) {
            NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
                table, --bucketIndex);
            if (bucket != NULL)
                [(id)bucket->key performSelector:selector];
        }
    }
}

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument {
    NSSimpleDictionary *table = (NSSimpleDictionary *)_table;
    unsigned bucketIndex;

    if (NSSimpleDictionaryCount(table) != 0) {
        bucketIndex = NSSimpleDictionaryNumBuckets(table);
        while (bucketIndex != 0) {
            NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
                table, --bucketIndex);
            if (bucket != NULL)
                [(id)bucket->key performSelector:selector
                                      withObject:argument];
        }
    }
}

- (id)init {
    return [self initWithCapacity:0];
}

- (id)initWithCapacity:(unsigned)numItems {
    NSSetCheckSize(self, _cmd, numItems, "capacity");
    _table = NSCreateSimpleDictionary(numItems, _NSSetAreObjectsEqual,
                                      NSZoneFromPointer(self));
    return self;
}

- (id)initWithArray:(NSArray *)array {
    return [super initWithArray:array];
}

- (id)initWithSet:(NSSet *)set {
    return [super initWithSet:set];
}

- (id)initWithSet:(NSSet *)set copyItems:(BOOL)copyItems {
    unsigned capacity = [set count];
    NSEnumerator *enumerator;
    id object;

    self = [self initWithCapacity:capacity];
    if (capacity == 0)
        return self;

    enumerator = [set objectEnumerator];
    while ((object = [enumerator nextObject]) != nil) {
        unsigned count = [set countForObject:object];
        void *key = copyItems ? [object copyWithZone:[self zone]]
                              : [object retain];
        void *value = (void *)(unsigned long)count;

        if (NSSimpleDictionaryInsert((NSSimpleDictionary **)&_table, &key,
                                     [(id)key hash], &value, NULL, NO))
            [(id)key retain];
    }
    return self;
}

- (id)initWithObjects:(id *)objects count:(unsigned)count {
    unsigned index;

    NSSetCheckSize(self, _cmd, count, "count");
    self = [self initWithCapacity:count];
    for (index = 0; index < count; index++) {
        void *object = objects[index];

        if (object == NULL)
            NSSetRaiseInsertNilException(self, _cmd);
        if (NSSimpleDictionaryIncrementValue(
                (NSSimpleDictionary **)&_table, &object,
                [(id)object hash], NULL))
            [(id)object retain];
    }
    return self;
}

- (unsigned)count {
    return NSSimpleDictionaryCount((NSSimpleDictionary *)_table);
}

- (unsigned)countForObject:(id)object {
    NSSimpleDictionaryBucket *bucket;

    if (object == nil)
        return 0;
    bucket = NSSimpleDictionaryLookup((NSSimpleDictionary *)_table, object,
                                      [object hash], NULL);
    return bucket != NULL ? (unsigned)(unsigned long)bucket->value : 0;
}

- (id)member:(id)object {
    NSSimpleDictionaryBucket *bucket;

    if (object == nil)
        return nil;
    bucket = NSSimpleDictionaryLookup((NSSimpleDictionary *)_table, object,
                                      [object hash], NULL);
    return bucket != NULL ? bucket->key : nil;
}

- (NSEnumerator *)objectEnumerator {
    return [[[_NSSetEnumerator allocWithZone:NSZoneFromPointer(self)]
        initWithSet:self] autorelease];
}

- (NSArray *)allObjects {
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned count = [self count];
    unsigned capacity = 128;
    unsigned bucketIndex;
    unsigned objectIndex = 0;
    NSArray *array;

    if (count == 0)
        return [NSArray array];
    if (count > capacity)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    bucketIndex = NSSimpleDictionaryNumBuckets((NSSimpleDictionary *)_table);
    while (bucketIndex != 0) {
        NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
            (NSSimpleDictionary *)_table, --bucketIndex);
        if (bucket != NULL)
            objects[objectIndex++] = bucket->key;
    }
    array = [[NSArray allocWithZone:NULL] initWithObjects:objects
                                                     count:count];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return [array autorelease];
}

- (id)anyObject {
    NSSimpleDictionary *table = (NSSimpleDictionary *)_table;
    unsigned bucketIndex;

    if (NSSimpleDictionaryCount(table) == 0)
        return nil;
    bucketIndex = NSSimpleDictionaryNumBuckets(table);
    while (bucketIndex != 0) {
        NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
            table, --bucketIndex);
        if (bucket != NULL)
            return bucket->key;
    }
    return nil;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    NSSimpleDictionary *table = (NSSimpleDictionary *)
        ((NSCountedSetLayout *)self)->table;
    NSMutableString *result;
    unsigned count = NSSimpleDictionaryCount(table);
    unsigned bucketIndex;
    NSSimpleDictionaryBucket *bucket;
    BOOL first = YES;

    if (count == 0)
        return [NSString stringWithFormat:@"<%s: 0x%x> ()",
                  self->isa->name, (unsigned)self];

    result = [[[NSMutableString allocWithZone:NULL]
        initWithCapacity:count << 6] autorelease];
    [result appendFormat:@"<%s: 0x%x> (",
        self->isa->name, (unsigned)self];
    bucketIndex = NSSimpleDictionaryNumBuckets(table);

    while (bucketIndex != 0) {
        NSString *description;
        id object;
        unsigned descriptionIndex;

        bucket = NSSimpleDictionaryGetBucket(table, --bucketIndex);
        if (bucket == NULL)
            continue;
        object = bucket->key;
        if (!first)
            [result replaceCharactersInRange:NSMakeRange([result length], 0)
                                   withString:@", "];
        if ([object respondsToSelector:@selector(descriptionWithLocale:)]) {
#if defined(__ppc__) || defined(__POWERPC__)
            descriptionIndex = [result length];
#endif
            description = [object descriptionWithLocale:locale];
#if !defined(__ppc__) && !defined(__POWERPC__)
            descriptionIndex = [result length];
#endif
        } else {
#if defined(__ppc__) || defined(__POWERPC__)
            descriptionIndex = [result length];
#endif
            description = [object description];
#if !defined(__ppc__) && !defined(__POWERPC__)
            descriptionIndex = [result length];
#endif
        }
        [result replaceCharactersInRange:NSMakeRange(descriptionIndex, 0)
                               withString:description];
        [result appendFormat:@" [%d]", (int)(unsigned long)bucket->value];
        first = NO;
    }
    [result replaceCharactersInRange:NSMakeRange([result length], 0)
                           withString:@")"];
    return result;
}

- (BOOL)intersectsSet:(NSSet *)otherSet {
    NSSimpleDictionary *table = (NSSimpleDictionary *)_table;
    unsigned bucketIndex;

    if (otherSet == nil || NSSimpleDictionaryCount(table) == 0 ||
        [otherSet count] == 0)
        return NO;
    bucketIndex = NSSimpleDictionaryNumBuckets(table);
    while (bucketIndex != 0) {
        NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
            table, --bucketIndex);
        if (bucket != NULL && [otherSet member:bucket->key] != nil)
            return YES;
    }
    return NO;
}

- (BOOL)isEqualToSet:(NSSet *)otherSet {
    NSSimpleDictionary *table = (NSSimpleDictionary *)_table;
    unsigned count = NSSimpleDictionaryCount(table);
    unsigned bucketIndex;

    if (otherSet == nil || count != [otherSet count])
        return NO;
    if (count != 0) {
        bucketIndex = NSSimpleDictionaryNumBuckets(table);
        while (bucketIndex != 0) {
            NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
                table, --bucketIndex);
            if (bucket != NULL && (unsigned)(unsigned long)bucket->value !=
                [otherSet countForObject:bucket->key])
                return NO;
        }
    }
    return YES;
}

- (BOOL)isSubsetOfSet:(NSSet *)otherSet {
    NSSimpleDictionary *table = (NSSimpleDictionary *)_table;
    unsigned count = NSSimpleDictionaryCount(table);
    unsigned bucketIndex;

    if (otherSet == nil || count > [otherSet count])
        return NO;
    if (count != 0) {
        bucketIndex = NSSimpleDictionaryNumBuckets(table);
        while (bucketIndex != 0) {
            NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
                table, --bucketIndex);
            if (bucket != NULL &&
                (unsigned)(unsigned long)bucket->value >
                    [otherSet countForObject:bucket->key])
                return NO;
        }
    }
    return YES;
}

- (void)intersectSet:(NSSet *)otherSet {
    NSSimpleDictionary *table = (NSSimpleDictionary *)_table;
    unsigned bucketIndex;

    if (otherSet == self)
        return;
    if (otherSet == nil || [otherSet count] == 0) {
        NSResetSimpleDictionary(table, _NSSetDictRelease, NULL);
        return;
    }
    bucketIndex = NSSimpleDictionaryNumBuckets(table);
    while (bucketIndex != 0) {
        NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
            table, --bucketIndex);
        id object;
        unsigned otherCount;
        unsigned ownCount;

        if (bucket == NULL)
            continue;
        object = bucket->key;
        ownCount = (unsigned)(unsigned long)bucket->value;
        otherCount = [otherSet countForObject:object];
        if (otherCount < ownCount) {
            bucket->value = (void *)(unsigned long)otherCount;
            if (otherCount == 0) {
                void *key = object;
                void *value = NULL;
                unsigned hash = [object hash];

                [object release];
                NSSimpleDictionaryDelete((NSSimpleDictionary **)&_table,
                    &key, hash, &value, NULL);
                table = (NSSimpleDictionary *)_table;
            }
        }
    }
}

- (void)removeAllObjects {
    NSResetSimpleDictionary((NSSimpleDictionary *)_table,
                            _NSSetDictRelease, NULL);
}

- (Class)classForCoder {
    return __NSCountedSetClass;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    unsigned count = NSSimpleDictionaryCount((NSSimpleDictionary *)_table);

    [coder encodeValueOfObjCType:"I" at:&count];
    if (count != 0) {
        unsigned bucketIndex = NSSimpleDictionaryNumBuckets(
            (NSSimpleDictionary *)_table);

        while (bucketIndex != 0) {
            NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryGetBucket(
                (NSSimpleDictionary *)_table, --bucketIndex);

            if (bucket != NULL) {
                unsigned objectCount = (unsigned)(unsigned long)bucket->value;

                [coder encodeBycopyObject:bucket->key];
                [coder encodeValueOfObjCType:"I" at:&objectCount];
            }
        }
    }
}

- (id)initWithCoder:(NSCoder *)coder {
    unsigned version = [coder versionForClassName:@"NSCountedSet"];
    unsigned count;
    unsigned index;

    if (version > 1) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSGenericException
                    format:@"%@: NSCountedSet cannot decode class version %u",
                           proem, version];
        return self;
    }

    [coder decodeValueOfObjCType:"I" at:&count];
    NSSetCheckSize(self, _cmd, count, "count");
    self = [self initWithCapacity:count];
    for (index = 0; index < count; index++) {
        void *object = nil;
        void *key;
        unsigned decodedCount;

        [coder decodeValueOfObjCType:"@" at:&object];
        [coder decodeValueOfObjCType:"I" at:&decodedCount];
        (void)decodedCount;
        key = object;
        if (!NSSimpleDictionaryIncrementValue(
                (NSSimpleDictionary **)&_table, &key,
                [(id)object hash], NULL))
            [(id)object release];
    }
    return self;
}

- (void)addObject:(id)object {
    void *key;

    if (object == nil)
        NSSetRaiseInsertNilException(self, _cmd);
    key = object;
    if (NSSimpleDictionaryIncrementValue((NSSimpleDictionary **)&_table,
                                         &key, [object hash], NULL))
        [(id)key retain];
}

- (void)removeObject:(id)object {
    void *key;

    if (object == nil)
        NSSetRaiseRemoveNilException(self, _cmd);
    if (NSSimpleDictionaryCount((NSSimpleDictionary *)_table) == 0)
        return;
    key = object;
    if (NSSimpleDictionaryDecrementValue((NSSimpleDictionary **)&_table,
                                         &key, [object hash], NULL))
        [(id)key release];
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [[(Class)self->isa allocWithZone:NULL]
        initWithSet:self copyItems:YES];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    (void)zone;
    return [[(Class)self->isa allocWithZone:NULL]
        initWithSet:self copyItems:NO];
}

- (void)dealloc {
    if (_table != NULL) {
        NSSimpleDictionary *table = (NSSimpleDictionary *)_table;

        if (NSSimpleDictionaryCount(table) != 0)
            NSResetSimpleDictionary(table, _NSSetDictRelease, NULL);
        NSFreeSimpleDictionary(table);
    }
    [super dealloc];
}

@end
