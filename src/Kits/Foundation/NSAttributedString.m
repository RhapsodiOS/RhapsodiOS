/*	NSAttributedString.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSAttributedString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>
#import "NSStringRetainLock.h"
#include <limits.h>
#include <string.h>

extern NSString *__NSEmptyString;

typedef struct {
    unsigned length;
    id object;
} NSRLEArrayRun;

typedef struct {
    unsigned refCount;
    unsigned length;
    unsigned runCount;
    unsigned capacity;
    unsigned blockIndex;
    unsigned blockLength;
    NSRLEArrayRun runs[1];
} NSRLEArrayStorage;

typedef struct {
    unsigned hash;
    id key;
    id object;
} NSSimpleAttributeDictionaryElement;

@interface NSSimpleAttributeDictionary : NSDictionary {
@public
    unsigned numElements;
    unsigned refCount;
    NSSimpleAttributeDictionaryElement elements[1];
}
+ (id)emptyAttributeDictionary;
+ (id)newWithDictionary:(NSDictionary *)dictionary;
- (id)newWithKey:(id)key object:(id)object;
- (unsigned)slotForKey:(id)key;
@end

@interface NSSimpleAttributeDictionaryEnumerator : NSEnumerator {
@private
    NSSimpleAttributeDictionary *dictionary;
    unsigned nextElement;
}
- (id)initWithAttributeDictionary:(NSSimpleAttributeDictionary *)dictionary;
@end

@interface NSRLEArray : NSObject {
@protected
    NSRLEArrayStorage *theList;
}
- (id)initWithRefCountedRunArray:(NSRLEArrayStorage *)runArray;
- (id)objectAtIndex:(unsigned)index effectiveRange:(NSRangePointer)range;
- (id)objectAtIndex:(unsigned)index effectiveRange:(NSRangePointer)range
          runIndex:(unsigned *)runIndex;
- (id)objectAtRunIndex:(unsigned)runIndex length:(unsigned *)length;
- (unsigned)count;
- (id)mutableCopyWithZone:(NSZone *)zone;
- (void)_makeNewListFrom:(NSRLEArrayStorage *)runArray;
@end

@interface NSMutableRLEArray : NSRLEArray
- (void)insertObject:(id)object range:(NSRange)range;
- (void)replaceObjectsInRange:(NSRange)range withObject:(id)object
                       length:(unsigned)length;
- (void)deleteObjectsInRange:(NSRange)range;
- (void)_setBlockCapacity:(unsigned)capacity;
@end

@interface NSMutableAttributedString (NSWeakAttributeAddition)
- (void)addAttributesWeakly:(NSDictionary *)attributes range:(NSRange)range;
@end

static Class NSAttributedStringAttributeDictionaryClass(void);
static id NSAttributedStringEmptyAttributeDictionary(void);
static Class _NSAttributeDictionaryClass(void);
static int _NSReadMutableAttributedStringWithCoder(
    NSCoder *coder, NSMutableAttributedString *attributedString);

static unsigned NSRLEArrayBlockForLocation(NSRLEArrayStorage *storage,
                                          unsigned location,
                                          NSRangePointer range) {
    unsigned blockIndex;
    unsigned blockLocation;

    if (location <= storage->blockLength / 2) {
        blockIndex = 0;
        blockLocation = 0;
    } else {
        blockIndex = storage->blockIndex;
        blockLocation = storage->blockLength;
    }
    if (blockLocation > location) {
        do {
            blockIndex--;
            blockLocation -= storage->runs[blockIndex].length;
        } while (blockIndex != 0 && blockLocation > location);
    } else {
        while (blockLocation + storage->runs[blockIndex].length <= location) {
            blockLocation += storage->runs[blockIndex].length;
            blockIndex++;
        }
    }
    storage->blockLength = blockLocation;
    storage->blockIndex = blockIndex;
    if (range != NULL)
        *range = NSMakeRange(blockLocation, storage->runs[blockIndex].length);
    return blockIndex;
}

static Class NSAttributedStringConfiguredAttributeDictionaryClass;

static Class NSAttributedStringAttributeDictionaryClass(void) {
    if (NSAttributedStringConfiguredAttributeDictionaryClass == Nil) {
        NSAttributedStringConfiguredAttributeDictionaryClass =
            objc_lookUpClass("NSAttributeDictionary");
        if (NSAttributedStringConfiguredAttributeDictionaryClass == Nil)
            NSAttributedStringConfiguredAttributeDictionaryClass =
                [NSSimpleAttributeDictionary class];
    }
    return NSAttributedStringConfiguredAttributeDictionaryClass;
}

static Class _NSAttributeDictionaryClass(void) {
    return NSAttributedStringAttributeDictionaryClass();
}

static id NSAttributedStringEmptyAttributeDictionary(void) {
    Class dictionaryClass = NSAttributedStringAttributeDictionaryClass();
    return [(NSSimpleAttributeDictionary *)dictionaryClass
        emptyAttributeDictionary];
}

static int _NSReadMutableAttributedStringWithCoder(
        NSCoder *coder, NSMutableAttributedString *attributedString) {
    id dictionariesOnStack[20];
    id *dictionaries = dictionariesOnStack;
    unsigned capacity = 20;
    NSString *string = [coder decodeObject];
    unsigned stringLength = [string length];
    unsigned location = 0;

    [attributedString replaceCharactersInRange:NSMakeRange(0, 0)
                                    withString:string];
    if (stringLength == 0)
        return 1;
    memset(dictionariesOnStack, 0, sizeof(dictionariesOnStack));
    while (location < stringLength) {
        int dictionaryIndex;
        unsigned runLength;

        [coder decodeValuesOfObjCTypes:"iI", &dictionaryIndex, &runLength];
        if ((unsigned)dictionaryIndex >= capacity) {
            unsigned newCapacity = capacity * 2;
            id *newDictionaries;

            if ((unsigned)dictionaryIndex >= newCapacity)
                newCapacity = (unsigned)dictionaryIndex + 1;
            if (dictionaries == dictionariesOnStack)
                newDictionaries = NSZoneMalloc(NULL,
                    newCapacity * sizeof(id));
            else
                newDictionaries = NSZoneRealloc(NULL, dictionaries,
                    newCapacity * sizeof(id));
            memset(newDictionaries + capacity, 0,
                   (newCapacity - capacity) * sizeof(id));
            dictionaries = newDictionaries;
            capacity = newCapacity;
        }
        if (dictionaries[dictionaryIndex] == nil)
            dictionaries[dictionaryIndex] = [coder decodeObject];
        [attributedString setAttributes:dictionaries[dictionaryIndex]
                                  range:NSMakeRange(location, runLength)];
        location += runLength;
    }
    if (dictionaries != dictionariesOnStack)
        NSZoneFree(NULL, dictionaries);
    return 1;
}

@implementation NSSimpleAttributeDictionary

+ (id)emptyAttributeDictionary {
    static NSSimpleAttributeDictionary *emptyDictionary;

    if (emptyDictionary == nil) {
        emptyDictionary = (NSSimpleAttributeDictionary *)
            NSAllocateObject(self, 0, NULL);
        emptyDictionary->numElements = 0;
    }
    return emptyDictionary;
}

+ (id)newWithDictionary:(NSDictionary *)dictionary {
    unsigned count = [dictionary count];
    NSSimpleAttributeDictionary *result;
    NSEnumerator *keys;
    id key;

    if (dictionary != nil && [dictionary isKindOfClass:self])
        return [dictionary retain];
    if (count == 0)
        return [[self emptyAttributeDictionary] retain];
    result = (NSSimpleAttributeDictionary *)NSAllocateObject(self,
        (unsigned)(sizeof(NSSimpleAttributeDictionaryElement) * (count - 1)),
        NULL);
    result->numElements = count;
    keys = [dictionary keyEnumerator];
    while ((key = [keys nextObject]) != nil) {
        unsigned hash = [key hash];
        unsigned slot = hash % count;

        while (result->elements[slot].key != nil) {
            if (++slot == count)
                slot = 0;
        }
        result->elements[slot].hash = hash;
        result->elements[slot].key = [key copyWithZone:NULL];
        result->elements[slot].object = [[dictionary objectForKey:key] retain];
    }
    return result;
}

- (unsigned)count {
    return numElements;
}

- (id)objectForKey:(id)key {
    unsigned slot = [self slotForKey:key];

    return slot == 0x7fffffff ? nil : elements[slot].object;
}

- (NSEnumerator *)keyEnumerator {
    NSSimpleAttributeDictionaryEnumerator *enumerator =
        [[NSSimpleAttributeDictionaryEnumerator allocWithZone:NULL]
            initWithAttributeDictionary:self];
    return [enumerator autorelease];
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    id objects[40];
    id keys[40];
    unsigned index;

    if (numElements > 40)
        return [super mutableCopyWithZone:zone];
    for (index = 0; index < numElements; index++) {
        objects[index] = elements[index].object;
        keys[index] = elements[index].key;
    }
    return [[NSMutableDictionary allocWithZone:zone]
        initWithObjects:objects forKeys:keys count:numElements];
}

- (id)newWithKey:(id)key object:(id)object {
    unsigned slot = [self slotForKey:key];
    unsigned newCount = numElements + (slot == 0x7fffffff);
    NSSimpleAttributeDictionary *result;
    unsigned index;

    if (slot != 0x7fffffff
        && (elements[slot].object == object
            || [elements[slot].object isEqual:object]))
        return [self retain];
    result = (NSSimpleAttributeDictionary *)NSAllocateObject(
        [NSSimpleAttributeDictionary class],
        (unsigned)(sizeof(NSSimpleAttributeDictionaryElement) * (newCount - 1)),
        NULL);
    result->numElements = newCount;
    if (slot == 0x7fffffff) {
        for (index = 0; index < newCount; index++) {
            id sourceKey = index == numElements ? key : elements[index].key;
            id sourceObject = index == numElements ? object : elements[index].object;
            unsigned hash = index == numElements ? [key hash] : elements[index].hash;
            unsigned target = hash % newCount;

            while (result->elements[target].key != nil) {
                if (++target == newCount)
                    target = 0;
            }
            result->elements[target].hash = hash;
            result->elements[target].key = [sourceKey copyWithZone:NULL];
            result->elements[target].object = [sourceObject retain];
        }
    } else {
        for (index = 0; index < numElements; index++) {
            result->elements[index].hash = elements[index].hash;
            result->elements[index].key = [elements[index].key copyWithZone:NULL];
            result->elements[index].object = [elements[index].object retain];
        }
        result->elements[slot].hash = [key hash];
        result->elements[slot].key = [key copyWithZone:NULL];
        result->elements[slot].object = [object retain];
    }
    return result;
}

- (unsigned)slotForKey:(id)key {
    unsigned index;
    unsigned hash;
    unsigned first;

    for (index = 0; index < numElements; index++) {
        if (elements[index].key == key)
            return index;
    }
    if (numElements == 0)
        return 0x7fffffff;
    hash = [key hash];
    index = hash % numElements;
    first = index;
    while (elements[index].hash != hash
        || ![elements[index].key isEqual:key]) {
        if (++index == numElements)
            index = 0;
        if (index == first)
            return 0x7fffffff;
    }
    return index;
}

- (void)dealloc {
    unsigned index;

    for (index = 0; index < numElements; index++) {
        [elements[index].key release];
        [elements[index].object release];
    }
    [super dealloc];
}

- (id)retain {
    BOOL locked = NSStringRetainLockAcquire();

#if defined(__ppc__) || defined(__POWERPC__)
    if (refCount != UINT_MAX)
#endif
        refCount++;
    NSStringRetainLockRelease(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSStringRetainLockAcquire();
    if (refCount != 0) {
        refCount--;
        NSStringRetainLockRelease(locked);
        return;
    }
    NSStringRetainLockRelease(locked);
    [self dealloc];
}

- (unsigned)retainCount {
    return refCount + 1;
}

@end

@implementation NSSimpleAttributeDictionaryEnumerator

- (id)initWithAttributeDictionary:(NSSimpleAttributeDictionary *)aDictionary {
    self = [super init];
    if (self != nil) {
        dictionary = [aDictionary retain];
        nextElement = 0;
    }
    return self;
}

- (id)nextObject {
    if (nextElement == dictionary->numElements)
        return nil;
    return dictionary->elements[nextElement++].key;
}

- (void)dealloc {
    [dictionary release];
    [super dealloc];
}

@end

@implementation NSRLEArray

- (id)init {
    return [self initWithRefCountedRunArray:NULL];
}

- (id)initWithRefCountedRunArray:(NSRLEArrayStorage *)runArray {
    [super init];
    if (runArray != NULL) {
        theList = runArray;
        theList->refCount++;
    } else {
        [self _makeNewListFrom:NULL];
    }
    return self;
}

- (void)dealloc {
    NSRLEArrayStorage *storage = theList;
    unsigned index;

    if (storage->refCount > 1) {
        storage->refCount--;
    } else {
        index = 0;
        if (storage->runCount != 0) {
            do {
                [storage->runs[index++].object release];
                storage = theList;
            } while (index < storage->runCount);
        }
        NSZoneFree(NSZoneFromPointer(theList), theList);
    }
    [super dealloc];
}

- (unsigned)count {
    return theList->length;
}

- (NSString *)description {
    NSMutableString *result = [NSMutableString stringWithCapacity:100];
    unsigned index;

    [result appendFormat:@"Length %d (%d blocks, %d used, block %d is at %d)\n",
        theList->length, theList->capacity, theList->runCount,
        theList->blockIndex, theList->blockLength];
    for (index = 0; index < theList->runCount; index++) {
        NSRLEArrayRun *run = &theList->runs[index];

        [result appendFormat:@" %d %x %@\n", run->length,
            (unsigned)run->object, run->object];
    }
    return result;
}

- (id)objectAtRunIndex:(unsigned)runIndex length:(unsigned *)length {
    if (runIndex >= theList->runCount)
        return nil;
    if (length != NULL)
        *length = theList->runs[runIndex].length;
    return theList->runs[runIndex].object;
}

- (id)objectAtIndex:(unsigned)index effectiveRange:(NSRangePointer)range {
    return [self objectAtIndex:index effectiveRange:range runIndex:NULL];
}

- (id)objectAtIndex:(unsigned)index effectiveRange:(NSRangePointer)range
          runIndex:(unsigned *)runIndex {
    unsigned current;

    if (index >= theList->length) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd object:self file:@"NSAttributedString.m"
            lineNumber:903
            description:@"Access invalid attribute location %d (length %d)",
                        index, theList->length];
    }
    current = NSRLEArrayBlockForLocation(theList, index, range);
    if (runIndex != NULL)
        *runIndex = current;
    return theList->runs[current].object;
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [[NSMutableRLEArray allocWithZone:zone]
        initWithRefCountedRunArray:theList];
}

- (void)_makeNewListFrom:(NSRLEArrayStorage *)runArray {
    unsigned capacity = runArray == NULL ? 2 : runArray->runCount;
    NSRLEArrayStorage *copy = (NSRLEArrayStorage *)NSZoneMalloc(
        [self zone], 6 * sizeof(unsigned) + capacity * sizeof(NSRLEArrayRun));
    unsigned index;

    theList = copy;
    copy->capacity = capacity;
    if (runArray != NULL) {
        for (index = 0; index < runArray->runCount; index++) {
            copy->runs[index].length = runArray->runs[index].length;
            copy->runs[index].object = [runArray->runs[index].object retain];
        }
        runArray->refCount--;
        copy->runCount = runArray->runCount;
        copy->blockIndex = runArray->blockIndex;
        copy->blockLength = runArray->blockLength;
        copy->length = runArray->length;
    } else {
        copy->blockLength = 0;
        copy->blockIndex = 0;
        copy->runCount = 0;
        copy->length = 0;
    }
    copy->refCount = 1;
}

@end

@implementation NSMutableRLEArray

- (void)_setBlockCapacity:(unsigned)requestedCapacity {
    unsigned capacity = requestedCapacity == 0 ? 1 : requestedCapacity;

    if (theList->capacity < capacity || theList->capacity / 2 > capacity) {
        unsigned roundedCapacity = 4 * ((capacity + 3) / 3);
        theList = (NSRLEArrayStorage *)NSZoneRealloc(
            [self zone], theList,
            6 * sizeof(unsigned) + roundedCapacity * sizeof(NSRLEArrayRun));

        theList->capacity = roundedCapacity;
    }
}

- (void)replaceObjectsInRange:(NSRange)range withObject:(id)object
                       length:(unsigned)length {
    NSRange blockRange;
    unsigned blockIndex;
    unsigned firstAfterRange;
    unsigned lastRangeBlock;
    unsigned firstBlockLength;
    unsigned removedLength;

    if (range.location + range.length > theList->length) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd object:self file:@"NSAttributedString.m"
            lineNumber:1008
            description:@"Delete invalid attribute range %@ (length %d)",
                        range, theList->length];
    }
    if (range.length == 0)
        return;
    if (length == 0)
        object = nil;
    if (theList->refCount > 1)
        [self _makeNewListFrom:theList];

    blockIndex = NSRLEArrayBlockForLocation(theList, range.location,
                                             &blockRange);
    theList->length -= range.length;
    firstBlockLength = blockRange.length -
                       (range.location - blockRange.location);
    if (firstBlockLength > range.length)
        firstBlockLength = range.length;
    theList->runs[blockIndex].length -= firstBlockLength;
    if (theList->runs[blockIndex].length == 0)
        [theList->runs[blockIndex].object release];

    removedLength = range.length - firstBlockLength;
    firstAfterRange = blockIndex;
    if (theList->runs[blockIndex].length != 0)
        firstAfterRange++;
    while (removedLength != 0) {
        unsigned runLength;

        blockIndex++;
        runLength = removedLength;
        if (theList->runs[blockIndex].length < runLength)
            runLength = theList->runs[blockIndex].length;
        theList->runs[blockIndex].length -= runLength;
        if (theList->runs[blockIndex].length == 0)
            [theList->runs[blockIndex].object release];
        removedLength -= runLength;
    }
    lastRangeBlock = blockIndex;
    if (theList->runs[blockIndex].length != 0 && blockIndex != 0)
        lastRangeBlock--;

    if (firstAfterRange <= lastRangeBlock) {
        if (firstAfterRange != 0
            && theList->blockIndex == firstAfterRange) {
            theList->blockLength -=
                theList->runs[firstAfterRange].length;
            theList->blockIndex--;
        }

        if (object != nil) {
            if (firstAfterRange != 0
                && theList->runs[firstAfterRange - 1].object == object) {
                theList->runs[firstAfterRange - 1].length += length;
                theList->length += length;
                object = nil;
            } else if (lastRangeBlock + 1 < theList->runCount
                       && theList->runs[lastRangeBlock + 1].object == object) {
                theList->runs[lastRangeBlock + 1].length += length;
                theList->length += length;
                object = nil;
            }

            if (object != nil && firstAfterRange < theList->runCount) {
                theList->runs[firstAfterRange].object = [object retain];
                theList->runs[firstAfterRange].length = length;
                theList->length += length;
                firstAfterRange++;
                object = nil;
            }
        }

        if (firstAfterRange != 0
            && lastRangeBlock + 1 < theList->runCount
            && theList->runs[lastRangeBlock + 1].object ==
               theList->runs[firstAfterRange - 1].object) {
            lastRangeBlock++;
            theList->runs[firstAfterRange - 1].length +=
                theList->runs[lastRangeBlock].length;
            [theList->runs[lastRangeBlock].object release];
        }

        if (firstAfterRange <= lastRangeBlock) {
            unsigned sourceIndex = lastRangeBlock + 1;
            unsigned destinationIndex = firstAfterRange;
#if defined(__ppc__) || defined(__POWERPC__)
            unsigned moveCount = theList->runCount - sourceIndex;
#else
            /*  i386 copies the extra slot at the old runCount index. */
            unsigned moveCount = theList->runCount - lastRangeBlock;
#endif

            if (moveCount != 0)
                memmove(&theList->runs[destinationIndex],
                        &theList->runs[sourceIndex],
                        moveCount * sizeof(NSRLEArrayRun));
            theList->runCount -= sourceIndex - destinationIndex;
            [self _setBlockCapacity:theList->runCount];
        }
    }
    if (object != nil)
        [self insertObject:object range:NSMakeRange(range.location, length)];
}

- (void)insertObject:(id)object range:(NSRange)range {
    if (range.location > theList->length) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd object:self file:@"NSAttributedString.m"
            lineNumber:951
            description:@"Insert at invalid attribute location %d (length %d)",
                        range.location, theList->length];
    }
    if (range.length == 0)
        return;
    if (theList->refCount > 1)
        [self _makeNewListFrom:theList];

    if (range.location == theList->length) {
        if (theList->runCount != 0
            && theList->runs[theList->runCount - 1].object == object) {
            theList->runs[theList->runCount - 1].length += range.length;
            if (theList->runCount <= theList->blockIndex)
                theList->blockLength += range.length;
        } else {
            [self _setBlockCapacity:theList->runCount + 1];
            theList->runs[theList->runCount].length = range.length;
            theList->runs[theList->runCount].object = [object retain];
            theList->runCount++;
        }
        theList->length += range.length;
        return;
    }
    {
        NSRange blockRange;
        unsigned block = NSRLEArrayBlockForLocation(theList, range.location,
                                                     &blockRange);
        NSRLEArrayRun current = theList->runs[block];

        if (current.object == object) {
            theList->runs[block].length += range.length;
        } else if (blockRange.location == range.location && block != 0
                   && theList->runs[block - 1].object == object) {
            theList->runs[block - 1].length += range.length;
            if (theList->blockIndex >= block)
                theList->blockLength += range.length;
        } else if (blockRange.location == range.location) {
            unsigned move;

            [self _setBlockCapacity:theList->runCount + 1];
            for (move = theList->runCount; move > block; move--)
                theList->runs[move] = theList->runs[move - 1];
            theList->runs[block].length = range.length;
            theList->runs[block].object = [object retain];
            theList->runCount++;
        } else {
            unsigned rightLength = blockRange.length
                - (range.location - blockRange.location);
            unsigned move;

            [self _setBlockCapacity:theList->runCount + 2];
            for (move = theList->runCount + 1; move > block + 1; move--)
                theList->runs[move] = theList->runs[move - 2];
            theList->runs[block].length = range.location - blockRange.location;
            theList->runs[block + 1].length = range.length;
            theList->runs[block + 1].object = [object retain];
            theList->runs[block + 2].length = rightLength;
            theList->runs[block + 2].object = [current.object retain];
            theList->runCount += 2;
        }
    }
    theList->length += range.length;
}

- (void)deleteObjectsInRange:(NSRange)range {
    [self replaceObjectsInRange:range withObject:nil length:0];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[NSRLEArray allocWithZone:zone]
        initWithRefCountedRunArray:theList];
}

@end

@interface NSConcreteAttributedString : NSAttributedString {
@private
    NSString *string;
    NSRLEArray *attributes;
}
- (id)initWithString:(NSString *)aString;
- (id)initWithString:(NSString *)aString attributes:(NSDictionary *)attributes;
- (id)initWithAttributedString:(NSAttributedString *)attributedString;
- (NSRLEArray *)_runArrayHoldingAttributes;
@end

id emptyAttributedString(void) {
    static id emptyString = nil;

    if (emptyString == nil)
        emptyString = [[NSConcreteAttributedString allocWithZone:NULL] init];
    return emptyString;
}

@interface NSConcreteMutableAttributedString : NSMutableAttributedString {
@private
    NSMutableString *mutableString;
    NSMutableRLEArray *mutableAttributes;
}
- (id)initWithAttributedString:(NSAttributedString *)attributedString;
- (id)initWithString:(NSString *)aString;
- (id)initWithString:(NSString *)aString attributes:(NSDictionary *)attributes;
- (void)edited:(unsigned)mask range:(NSRange)range changeInLength:(int)change;
- (NSMutableRLEArray *)_runArrayHoldingAttributes;
@end

@interface NSMutableStringProxyForMutableAttributedString : NSMutableString {
@private
    NSMutableAttributedString *mutableAttributedString;
}
- (id)initWithMutableAttributedString:(NSMutableAttributedString *)attributedString;
@end

static NSDictionary *NSAttributedStringCopyAttributes(NSDictionary *attributes,
                                                       NSZone *zone) {
    Class dictionaryClass = NSAttributedStringAttributeDictionaryClass();

    (void)zone;
    return [(NSSimpleAttributeDictionary *)dictionaryClass
        newWithDictionary:attributes];
}

static void NSAttributedStringCopyRuns(NSAttributedString *source,
                                       NSMutableRLEArray *runs,
                                       unsigned length) {
    unsigned location = 0;

    while (location < length) {
        Class dictionaryClass;
        NSRange effectiveRange;
        NSDictionary *sourceAttributes;
        unsigned runLength;
        NSDictionary *attributes;

#if defined(__ppc__) || defined(__POWERPC__)
        dictionaryClass = NSAttributedStringAttributeDictionaryClass();
#endif
        sourceAttributes = [source attributesAtIndex:location
            effectiveRange:&effectiveRange];
#if !defined(__ppc__) && !defined(__POWERPC__)
        dictionaryClass = NSAttributedStringAttributeDictionaryClass();
#endif
        attributes = [(NSSimpleAttributeDictionary *)dictionaryClass
            newWithDictionary:sourceAttributes];
        if (effectiveRange.location < location)
            effectiveRange.length -= location - effectiveRange.location;
        runLength = effectiveRange.length;
        if (runLength > length - location)
            runLength = length - location;
        [runs insertObject:attributes range:NSMakeRange(location, runLength)];
        [attributes release];
        location += runLength;
    }
}

@implementation NSConcreteAttributedString

- (id)init {
    return [self initWithString:__NSEmptyString];
}

- (id)initWithString:(NSString *)aString {
    self = [super init];
    if (self != nil) {
        string = [aString copyWithZone:[self zone]];
        attributes = nil;
    }
    return self;
}

- (id)initWithString:(NSString *)aString attributes:(NSDictionary *)anAttributes {
    NSZone *zone;
    NSMutableRLEArray *runArray;
    NSDictionary *attributesCopy;
    unsigned length;

    self = [self initWithString:aString];
    if (self != nil && anAttributes != nil) {
        zone = [self zone];
        runArray = [[NSMutableRLEArray allocWithZone:zone] init];
        attributesCopy = NSAttributedStringCopyAttributes(anAttributes, zone);
        length = [string length];
        [runArray insertObject:attributesCopy range:NSMakeRange(0, length)];
        [attributesCopy release];
        attributes = runArray;
    }
    return self;
}

- (id)initWithAttributedString:(NSAttributedString *)attributedString {
    self = [self initWithString:[attributedString string]];
    if (self == nil)
        return nil;
    if ([attributedString respondsToSelector:
            @selector(_runArrayHoldingAttributes)]) {
        NSRLEArray *sourceRuns = [attributedString
            performSelector:@selector(_runArrayHoldingAttributes)];
        if (sourceRuns != nil)
            attributes = [sourceRuns copyWithZone:[self zone]];
    }
    if (attributes == nil) {
        unsigned length = [string length];
        attributes = [[NSMutableRLEArray allocWithZone:[self zone]] init];
        NSAttributedStringCopyRuns(attributedString, (NSMutableRLEArray *)attributes,
                                   length);
    }
    return self;
}

- (NSString *)string {
    return string;
}

- (unsigned)length {
    return [string length];
}

- (NSDictionary *)attributesAtIndex:(unsigned)location
                      effectiveRange:(NSRangePointer)range {
    if (attributes != nil)
        return [attributes objectAtIndex:location effectiveRange:range];
    if (range != NULL)
        *range = NSMakeRange(0, [string length]);
    return NSAttributedStringEmptyAttributeDictionary();
}

- (id)attribute:(NSString *)attributeName atIndex:(unsigned)location
  effectiveRange:(NSRangePointer)range {
    if (attributes != nil) {
        NSDictionary *currentAttributes = [attributes
            objectAtIndex:location effectiveRange:range];
        return [currentAttributes objectForKey:attributeName];
    }
    if (range != NULL)
        *range = NSMakeRange(0, [string length]);
    return nil;
}

- (NSRLEArray *)_runArrayHoldingAttributes {
    return attributes;
}

- (void)dealloc {
    [string release];
    [attributes release];
    [super dealloc];
}

@end

@implementation NSConcreteMutableAttributedString

- (id)init {
    return [self initWithAttributedString:nil];
}

- (id)initWithAttributedString:(NSAttributedString *)attributedString {
    NSZone *zone;

    self = [super init];
    if (self == nil)
        return nil;
    zone = [self zone];
    mutableAttributes = nil;
    if (attributedString != nil) {
        if ([attributedString respondsToSelector:
                @selector(_runArrayHoldingAttributes)]) {
            NSRLEArray *sourceRuns = [attributedString
                performSelector:@selector(_runArrayHoldingAttributes)];
            if (sourceRuns != nil) {
                mutableAttributes = [sourceRuns mutableCopyWithZone:zone];
            }
        }
        if (mutableAttributes == nil) {
            NSString *sourceString = [attributedString string];
            mutableAttributes = [[NSMutableRLEArray allocWithZone:zone] init];
            NSAttributedStringCopyRuns(attributedString, mutableAttributes,
                [sourceString length]);
        }
        mutableString = [[attributedString string] mutableCopyWithZone:zone];
    } else {
        mutableAttributes = [[NSMutableRLEArray allocWithZone:zone] init];
        mutableString = [[NSMutableString allocWithZone:zone] init];
    }
    return self;
}

- (id)initWithString:(NSString *)aString {
    self = [self initWithAttributedString:nil];
    if (self != nil)
        [self replaceCharactersInRange:NSMakeRange(0, 0) withString:aString];
    return self;
}

- (id)initWithString:(NSString *)aString attributes:(NSDictionary *)attributes {
    NSDictionary *attributesCopy;
    unsigned length;

    self = [self initWithString:aString];
    if (self != nil) {
        attributesCopy = NSAttributedStringCopyAttributes(attributes,
                                                          [self zone]);
        length = [mutableString length];
        [mutableAttributes insertObject:attributesCopy
                                 range:NSMakeRange(0, length)];
        [attributesCopy release];
    }
    return self;
}

- (NSString *)string {
    return mutableString;
}

- (unsigned)length {
    return [mutableString length];
}

- (NSDictionary *)attributesAtIndex:(unsigned)location
                      effectiveRange:(NSRangePointer)range {
    return [mutableAttributes objectAtIndex:location effectiveRange:range];
}

- (id)attribute:(NSString *)attributeName atIndex:(unsigned)location
  effectiveRange:(NSRangePointer)range {
    NSDictionary *currentAttributes = [mutableAttributes
        objectAtIndex:location effectiveRange:range];
    return [currentAttributes objectForKey:attributeName];
}

- (id)attribute:(NSString *)attributeName atIndex:(unsigned)location
  longestEffectiveRange:(NSRangePointer)range inRange:(NSRange)rangeLimit {
    extern IMP _NSIMPForObjectAndSelector(id object, SEL aSelector);
    NSRange currentRange;
    unsigned currentRun;
    id (*runLookup)(id, SEL, unsigned, unsigned *);
    BOOL (*equality)(id, SEL, id);
    NSDictionary *currentAttributes = [mutableAttributes
        objectAtIndex:location effectiveRange:&currentRange
             runIndex:&currentRun];
    id value = [currentAttributes objectForKey:attributeName];

    if (range != NULL) {
        unsigned start = currentRange.location;
        unsigned end = NSMaxRange(currentRange);
        unsigned limitEnd = NSMaxRange(rangeLimit);
        unsigned nextRun = currentRun;

        runLookup = (id (*)(id, SEL, unsigned, unsigned *))
            _NSIMPForObjectAndSelector(mutableAttributes,
                @selector(objectAtRunIndex:length:));
        equality = value == nil ? NULL
            : (BOOL (*)(id, SEL, id))_NSIMPForObjectAndSelector(
                value, @selector(isEqual:));
        while (end < limitEnd) {
            unsigned runLength;
            NSDictionary *nextAttributes = runLookup(mutableAttributes,
                @selector(objectAtRunIndex:length:), ++nextRun, &runLength);
            id nextValue;

            if (nextAttributes == nil)
                break;
            nextValue = [nextAttributes objectForKey:attributeName];
            if (value != nextValue &&
                (value == nil || !equality(value, @selector(isEqual:),
                                           nextValue)))
                break;
            end += runLength;
        }

        while (rangeLimit.location < start) {
            unsigned runLength;
            NSDictionary *previousAttributes = runLookup(mutableAttributes,
                @selector(objectAtRunIndex:length:), --currentRun, &runLength);
            id previousValue = [previousAttributes objectForKey:attributeName];

            if (value != previousValue &&
                (value == nil || !equality(value, @selector(isEqual:),
                                           previousValue)))
                break;
            start -= runLength;
        }
        *range = NSIntersectionRange(rangeLimit, NSMakeRange(start, end - start));
    }
    return value;
}

- (NSMutableRLEArray *)_runArrayHoldingAttributes {
    return mutableAttributes;
}

- (void)setAttributes:(NSDictionary *)newAttributes range:(NSRange)range {
    if (range.length != 0) {
        NSDictionary *attributesCopy = NSAttributedStringCopyAttributes(
            newAttributes, [self zone]);
        [mutableAttributes replaceObjectsInRange:range
            withObject:attributesCopy length:range.length];
        [attributesCopy release];
        [self edited:1 range:range changeInLength:0];
    }
}

- (void)addAttribute:(NSString *)name value:(id)value range:(NSRange)range {
    unsigned location = range.location;
    unsigned remaining = range.length;

    if (remaining != 0) {
        do {
            NSRange effectiveRange;
            NSSimpleAttributeDictionary *attributes = (NSSimpleAttributeDictionary *)
                [mutableAttributes objectAtIndex:location
                                  effectiveRange:&effectiveRange];
            effectiveRange = NSIntersectionRange(effectiveRange,
                NSMakeRange(location, remaining));
            id updatedAttributes = [attributes newWithKey:name object:value];

            if (updatedAttributes != attributes)
                [mutableAttributes replaceObjectsInRange:effectiveRange
                    withObject:updatedAttributes length:effectiveRange.length];
            [updatedAttributes release];
            remaining -= effectiveRange.length;
            location += effectiveRange.length;
        } while (remaining != 0);
        [self edited:1 range:range changeInLength:0];
    }
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)newString {
    unsigned newLength = [newString length];
    NSDictionary *inheritedAttributes = nil;

    if (newLength != 0) {
        unsigned attributeIndex = range.location;
        if (range.length == 0 && attributeIndex != 0)
            attributeIndex--;
        else if (range.length == 0 && [mutableString length] == 0)
            inheritedAttributes = NSAttributedStringEmptyAttributeDictionary();
        if (inheritedAttributes == nil)
            inheritedAttributes = [mutableAttributes objectAtIndex:attributeIndex
                effectiveRange:NULL];
        [inheritedAttributes retain];
    }
    if (range.length != 0)
        [mutableAttributes replaceObjectsInRange:range
            withObject:inheritedAttributes length:newLength];
    else if (newLength != 0)
        [mutableAttributes insertObject:inheritedAttributes
            range:NSMakeRange(range.location, newLength)];
    [inheritedAttributes release];
    [mutableString replaceCharactersInRange:range withString:newString];
    [self edited:2 range:range changeInLength:(int)newLength - (int)range.length];
}

- (void)replaceCharactersInRange:(NSRange)range
            withAttributedString:(NSAttributedString *)attributedString {
    NSString *replacementString = [attributedString string];
    unsigned replacementLength = [replacementString length];

    if (replacementLength != 0) {
        unsigned sourceLocation = 0;

        while (sourceLocation < replacementLength) {
            NSRange sourceRange;
            NSDictionary *sourceAttributes;
            NSSimpleAttributeDictionary *copiedAttributes;
#if defined(__ppc__) || defined(__POWERPC__)
            Class dictionaryClass = _NSAttributeDictionaryClass();
#endif

            sourceAttributes = [attributedString
                attributesAtIndex:sourceLocation effectiveRange:&sourceRange];
#if defined(__ppc__) || defined(__POWERPC__)
            copiedAttributes = (NSSimpleAttributeDictionary *)
                [(NSSimpleAttributeDictionary *)dictionaryClass
                    newWithDictionary:sourceAttributes];
#else
            copiedAttributes = (NSSimpleAttributeDictionary *)
                [(NSSimpleAttributeDictionary *)_NSAttributeDictionaryClass()
                    newWithDictionary:sourceAttributes];
#endif

            [mutableAttributes insertObject:copiedAttributes
                range:NSMakeRange(range.location + sourceRange.location,
                                  sourceRange.length)];
            [copiedAttributes release];
            sourceLocation += sourceRange.length;
        }
    }
    if (range.length != 0)
        [mutableAttributes deleteObjectsInRange:NSMakeRange(
            range.location + replacementLength, range.length)];
    [mutableString replaceCharactersInRange:range withString:replacementString];
    [self edited:3 range:range
        changeInLength:(int)replacementLength - (int)range.length];
}

- (Class)classForCoder {
    return [NSMutableAttributedString class];
}

- (id)initWithCoder:(NSCoder *)coder {
    [self init];
    if (!_NSReadMutableAttributedStringWithCoder(coder, self)) {
        [self dealloc];
        return nil;
    }
    return self;
}

- (void)edited:(unsigned)mask range:(NSRange)range changeInLength:(int)change {
}

- (void)dealloc {
    [mutableString release];
    [mutableAttributes release];
    [super dealloc];
}

@end

@implementation NSMutableStringProxyForMutableAttributedString

- (unichar)characterAtIndex:(unsigned)index {
    return [[mutableAttributedString string] characterAtIndex:index];
}

- (void)dealloc {
    [mutableAttributedString release];
    [super dealloc];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    [[mutableAttributedString string] getCharacters:buffer range:range];
}

- (id)initWithMutableAttributedString:(NSMutableAttributedString *)attributedString {
    self = [super init];
    if (self != nil)
        mutableAttributedString = [attributedString retain];
    return self;
}

- (unsigned)length {
    return [[mutableAttributedString string] length];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string {
    [mutableAttributedString replaceCharactersInRange:range withString:string];
}

@end

@implementation NSAttributedString

+ (id)allocWithZone:(NSZone *)zone {
    Class stringClass = self == [NSAttributedString class]
        ? [NSConcreteAttributedString class] : self;

    return NSAllocateObject(stringClass, 0, zone);
}

+ (void)_setAttributedDictionaryClass:(Class)dictionaryClass {
    NSAttributedStringConfiguredAttributeDictionaryClass = dictionaryClass;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[NSAttributedString allocWithZone:zone]
        initWithAttributedString:self];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [[NSMutableAttributedString allocWithZone:zone]
        initWithAttributedString:self];
}

- (NSString *)string {
    NSRequestConcreteImplementation(self, _cmd, [NSAttributedString class]);
    return nil;
}

- (NSDictionary *)attributesAtIndex:(unsigned)location effectiveRange:(NSRangePointer)range {
    NSRequestConcreteImplementation(self, _cmd, [NSAttributedString class]);
    return nil;
}

- (unsigned)length {
    return [[self string] length];
}

- (id)attribute:(NSString *)attrName atIndex:(unsigned int)location effectiveRange:(NSRangePointer)range {
    NSDictionary *attributes = [self attributesAtIndex:location effectiveRange:range];
    return [attributes objectForKey:attrName];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range {
    unsigned location = range.location;
    unsigned end = range.location + range.length;
    NSString *string = [self string];
    unsigned stringLength = [string length];
    NSMutableAttributedString *substring;

    if (end > stringLength) {
        Class stringClass = [self class];
        [NSException raise:NSRangeException format:@"[%s %s]: Out of bounds",
                          stringClass->name, sel_getName(_cmd)];
    }
    if (range.length == stringLength)
        return [[self copyWithZone:NULL] autorelease];

    string = [string substringWithRange:range];
    substring = [[NSMutableAttributedString allocWithZone:NULL]
        initWithString:string];
    substring = [substring autorelease];
    while (location < end) {
        NSRange effectiveRange;
        NSDictionary *attributes = [self attributesAtIndex:location
            effectiveRange:&effectiveRange];

        if (effectiveRange.location != location)
            effectiveRange.length -= location - effectiveRange.location;
        if (end < location + effectiveRange.length)
            effectiveRange.length = end - location;
        [substring addAttributes:attributes
            range:NSMakeRange(location - range.location,
                              effectiveRange.length)];
        location += effectiveRange.length;
    }
    return substring;
}

- (NSDictionary *)attributesAtIndex:(unsigned)location longestEffectiveRange:(NSRangePointer)range inRange:(NSRange)rangeLimit {
    NSDictionary *attributes = [self attributesAtIndex:location effectiveRange:range];
    if (range != NULL) {
        NSRange effectiveRange = *range;
        unsigned end;
        while (1) {
            end = NSMaxRange(effectiveRange);
            if (end >= NSMaxRange(rangeLimit))
                break;
            NSDictionary *nextAttributes = [self attributesAtIndex:end effectiveRange:&effectiveRange];
            if (![nextAttributes isEqualToDictionary:attributes])
                break;
        }

        effectiveRange = *range;
        unsigned start = effectiveRange.location;
        while (start > rangeLimit.location) {
            NSDictionary *previousAttributes = [self attributesAtIndex:start - 1 effectiveRange:&effectiveRange];
            if (![previousAttributes isEqualToDictionary:attributes])
                break;
            start = effectiveRange.location;
        }

        NSRange longestRange = NSMakeRange(start, end - start);
        *range = NSIntersectionRange(rangeLimit, longestRange);
    }
    return attributes;
}

- (id)attribute:(NSString *)attrName atIndex:(unsigned int)location longestEffectiveRange:(NSRangePointer)range inRange:(NSRange)rangeLimit {
    id value = [self attribute:attrName atIndex:location effectiveRange:range];
    if (range != NULL) {
        NSRange effectiveRange = *range;
        unsigned end;
        while (1) {
            end = NSMaxRange(effectiveRange);
            if (end >= NSMaxRange(rangeLimit))
                break;
            id nextValue = [self attribute:attrName atIndex:end effectiveRange:&effectiveRange];
            if (nextValue != value && ![nextValue isEqual:value])
                break;
        }

        effectiveRange = *range;
        unsigned start = effectiveRange.location;
        while (start > rangeLimit.location) {
            id previousValue = [self attribute:attrName atIndex:start - 1 effectiveRange:&effectiveRange];
            if (previousValue != value && ![previousValue isEqual:value])
                break;
            start = effectiveRange.location;
        }

        NSRange longestRange = NSMakeRange(start, end - start);
        *range = NSIntersectionRange(rangeLimit, longestRange);
    }
    return value;
}

- (BOOL)isEqualToAttributedString:(NSAttributedString *)other {
    if (![[self string] isEqualToString:[other string]])
        return NO;

    unsigned length = [self length];
    unsigned location = 0;
    NSRange selfRange = NSMakeRange(0, 0);
    NSRange otherRange = NSMakeRange(0, 0);
    NSDictionary *selfAttributes = nil;
    NSDictionary *otherAttributes = nil;

    while (location < length) {
        if (location >= NSMaxRange(selfRange))
            selfAttributes = [self attributesAtIndex:location effectiveRange:&selfRange];
        if (location >= NSMaxRange(otherRange))
            otherAttributes = [other attributesAtIndex:location effectiveRange:&otherRange];
        if (![selfAttributes isEqualToDictionary:otherAttributes])
            return NO;

        unsigned selfEnd = NSMaxRange(selfRange);
        unsigned otherEnd = NSMaxRange(otherRange);
        location = selfEnd < otherEnd ? selfEnd : otherEnd;
    }
    return YES;
}

- (Class)classForCoder {
    return [NSAttributedString class];
}

- (id)replacementObjectForPortCoder:(id)coder {
    (void)coder;
    return self;
}

- (unsigned)hash {
    return [[self string] hash];
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[NSAttributedString class]]
        && [self isEqualToAttributedString:object];
}

- (NSString *)description {
    unsigned length = [self length];
    unsigned location = 0;
    NSMutableString *result = [NSMutableString stringWithCapacity:2 * length];

    while (location < length) {
        NSRange range;
        NSDictionary *attributes = [self attributesAtIndex:location
            effectiveRange:&range];
        NSString *substring = [[self string] substringWithRange:range];

        [result replaceCharactersInRange:NSMakeRange([result length], 0)
                              withString:substring];
        [result replaceCharactersInRange:NSMakeRange([result length], 0)
                              withString:[attributes description]];
        location += range.length;
    }
    return result;
}

- (NSAttributedString *)attributedStringByWeaklyAddingAttributes:
        (NSDictionary *)attributes {
    NSMutableAttributedString *mutableCopy = [self mutableCopyWithZone:NULL];
    id result;

    [mutableCopy addAttributesWeakly:attributes
                              range:NSMakeRange(0, [self length])];
    result = [mutableCopy copyWithZone:NULL];
    [mutableCopy release];
    return [result autorelease];
}

- (id)initWithCoder:(NSCoder *)coder {
    NSMutableAttributedString *decoded =
        [[NSMutableAttributedString allocWithZone:NULL] init];

    if (_NSReadMutableAttributedStringWithCoder(coder, decoded))
        self = [self initWithAttributedString:decoded];
    else {
        [self dealloc];
        self = nil;
    }
    [decoded release];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    unsigned length = [self length];
    NSString *string = [self string];

    [coder encodeObject:string];
    if (length != 0) {
        NSMapTableValueCallBacks valueCallbacks = { NULL, NULL, NULL };
        NSMapTable *dictionaryIDs = NSCreateMapTable(
            NSNonRetainedObjectMapKeyCallBacks, valueCallbacks, 8);
        unsigned location = 0;
        int nextDictionaryID = 1;

        while (location < length) {
            NSRange range;
            NSDictionary *attributes = [self
                attributesAtIndex:location
                longestEffectiveRange:&range
                inRange:NSMakeRange(location, length - location)];
            void *storedID = NSMapGet(dictionaryIDs, attributes);
            int dictionaryID;
            unsigned runLength = range.length;

            if (storedID != NULL) {
                dictionaryID = (int)(unsigned long)storedID;
            } else {
                dictionaryID = nextDictionaryID++;
                NSMapInsertKnownAbsent(dictionaryIDs, attributes,
                    (const void *)(unsigned long)dictionaryID);
            }
            [coder encodeValuesOfObjCTypes:"iI", &dictionaryID, &runLength];
            if (storedID == NULL)
                [coder encodeObject:attributes];
            location += runLength;
        }
        NSFreeMapTable(dictionaryIDs);
    }
}

@end

@implementation NSMutableAttributedString

+ (id)allocWithZone:(NSZone *)zone {
    Class stringClass = self == [NSMutableAttributedString class]
        ? [NSConcreteMutableAttributedString class] : self;

    return NSAllocateObject(stringClass, 0, zone);
}

- (void)addAttributesWeakly:(NSDictionary *)attributes range:(NSRange)range {
    unsigned location = range.location;
    unsigned remaining = range.length;

    if (remaining == 0)
        return;
    [self beginEditing];
    while (remaining != 0) {
        NSRange effectiveRange;
        NSRange intersection;
        NSDictionary *existing = [self attributesAtIndex:location
            effectiveRange:&effectiveRange];
        NSMutableDictionary *combined = [attributes mutableCopyWithZone:NULL];

        intersection = NSIntersectionRange(NSMakeRange(location, remaining),
                                           effectiveRange);
        intersection.location = location;
        if (intersection.length > remaining)
            intersection.length = remaining;
        [combined addEntriesFromDictionary:existing];
        [self setAttributes:combined range:intersection];
        [combined release];
        remaining -= intersection.length;
        location += intersection.length;
    }
    [self endEditing];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    NSRequestConcreteImplementation(self, _cmd, [NSMutableAttributedString class]);
}

- (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range {
    NSRequestConcreteImplementation(self, _cmd, [NSMutableAttributedString class]);
}

- (NSMutableString *)mutableString {
    NSMutableStringProxyForMutableAttributedString *proxy =
        [[NSMutableStringProxyForMutableAttributedString allocWithZone:NULL]
            initWithMutableAttributedString:self];
    return [proxy autorelease];
}

- (void)addAttribute:(NSString *)name value:(id)value range:(NSRange)range {
    unsigned location = range.location;
    unsigned length = range.length;
    if (length != 0) {
        [self beginEditing];
        do {
            NSRange effectiveRange;
            NSDictionary *attributes = [self attributesAtIndex:location effectiveRange:&effectiveRange];
            NSMutableDictionary *updatedAttributes =
                [attributes mutableCopyWithZone:NULL];
            NSRange affectedRange = NSIntersectionRange(NSMakeRange(location, length), effectiveRange);
            [updatedAttributes setObject:value forKey:name];
            [self setAttributes:updatedAttributes range:affectedRange];
            [updatedAttributes release];
            length -= affectedRange.length;
            location += affectedRange.length;
        } while (length != 0);
        [self endEditing];
    }
}

- (void)addAttributes:(NSDictionary *)attrs range:(NSRange)range {
    unsigned location = range.location;
    unsigned length = range.length;
    if (length != 0) {
        [self beginEditing];
        while (length != 0) {
            NSRange effectiveRange;
            NSDictionary *attributes = [self attributesAtIndex:location effectiveRange:&effectiveRange];
            NSMutableDictionary *updatedAttributes =
                [attributes mutableCopyWithZone:NULL];
            NSRange affectedRange = NSIntersectionRange(NSMakeRange(location, length), effectiveRange);
            [updatedAttributes addEntriesFromDictionary:attrs];
            [self setAttributes:updatedAttributes range:affectedRange];
            [updatedAttributes release];
            length -= affectedRange.length;
            location += affectedRange.length;
        }
        [self endEditing];
    }
}

- (void)removeAttribute:(NSString *)name range:(NSRange)range {
    unsigned location = range.location;
    unsigned length = range.length;
    if (length != 0) {
        [self beginEditing];
        do {
            NSRange effectiveRange;
            NSDictionary *attributes = [self attributesAtIndex:location effectiveRange:&effectiveRange];
            NSMutableDictionary *updatedAttributes =
                [attributes mutableCopyWithZone:NULL];
            NSRange affectedRange = NSIntersectionRange(NSMakeRange(location, length), effectiveRange);
            [updatedAttributes removeObjectForKey:name];
            [self setAttributes:updatedAttributes range:affectedRange];
            [updatedAttributes release];
            length -= affectedRange.length;
            location += affectedRange.length;
        } while (length != 0);
        [self endEditing];
    }
}

- (void)replaceCharactersInRange:(NSRange)range withAttributedString:(NSAttributedString *)attrString {
    NSString *string = [attrString string];
    unsigned length = [string length];
    unsigned location = 0;
    NSRange sourceRange = NSMakeRange(0, 0);

    [self beginEditing];
    [self replaceCharactersInRange:range withString:string];
    while (location < length) {
        NSDictionary *attributes = [attrString attributesAtIndex:location effectiveRange:&sourceRange];
        [self setAttributes:attributes
                      range:NSMakeRange(range.location + sourceRange.location, sourceRange.length)];
        location = NSMaxRange(sourceRange);
    }
    [self endEditing];
}

- (void)insertAttributedString:(NSAttributedString *)attrString atIndex:(unsigned)loc {
    [self replaceCharactersInRange:NSMakeRange(loc, 0) withAttributedString:attrString];
}

- (void)appendAttributedString:(NSAttributedString *)attrString {
    [self replaceCharactersInRange:NSMakeRange([[self string] length], 0) withAttributedString:attrString];
}

- (void)deleteCharactersInRange:(NSRange)range {
    [self replaceCharactersInRange:range
             withAttributedString:emptyAttributedString()];
}

- (void)setAttributedString:(NSAttributedString *)attrString {
    NSString *string = [self string];

    [self replaceCharactersInRange:NSMakeRange(0, [string length])
              withAttributedString:attrString];
}

- (void)beginEditing {
}

- (void)endEditing {
}

@end
