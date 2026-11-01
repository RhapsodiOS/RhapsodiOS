/*	NSCompatibility.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCompatibility.h>
#import <Foundation/NSData.h>
#import <Foundation/NSArchiver.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <Foundation/obsoleteTimeZoneDetail.h>
#import <objc/HashTable.h>
#import <objc/List.h>
#import <objc/Object.h>
#import <objc/Protocol.h>
#import <objc/Storage.h>
#import <objc/StreamTable.h>
#import <string.h>

struct NSProtocolName {
    Class class_pointer;
    const char *protocol_name;
};

extern id _NSMethodExceptionProem(id object, SEL selector);
extern void NSAutoreleaseObject(id object);

static void
ObjectCompatibilityWarnOnce(unsigned index, id object, SEL selector)
{
    static unsigned char warned[64];

    if (!warned[index]) {
        warned[index] = 1;
        NSLog(@"%@: warning: Object compatibility method has been executed at least once.  Convert source code off it NOW!",
              _NSMethodExceptionProem(object, selector));
    }
}

/* These compatibility categories emit the warning on i386; PPC omits it. */
#if defined(__ppc__) || defined(__POWERPC__)
#define ObjectCompatibilityWarnOnceI386(index, object, selector) ((void)0)
#else
#define ObjectCompatibilityWarnOnceI386(index, object, selector) \
    ObjectCompatibilityWarnOnce(index, object, selector)
#endif

/* The Object category emits this warning on i386; PPC omits it. */
#if defined(__ppc__) || defined(__POWERPC__)
#define ObjectCategoryWarnOnce(index, object, selector) ((void)0)
#else
#define ObjectCategoryWarnOnce(index, object, selector) \
    ObjectCompatibilityWarnOnce(index, object, selector)
#endif

@implementation NSTimeZoneDetail
@end

@implementation Object (NSCompatibility)

+ (id)allocWithZone:(NSZone *)zone {
    if (zone == NULL)
        zone = NSDefaultMallocZone();
    ObjectCategoryWarnOnce(0, self, _cmd);
    return [self allocFromZone:(NXZone *)zone];
}

+ (id)autorelease {
    ObjectCategoryWarnOnce(1, self, _cmd);
    return self;
}

+ (IMP)instanceMethodForSelector:(SEL)selector {
    ObjectCategoryWarnOnce(2, self, _cmd);
    return [self instanceMethodFor:selector];
}

+ (BOOL)instancesRespondToSelector:(SEL)selector {
    ObjectCategoryWarnOnce(3, self, _cmd);
    return [self instancesRespondTo:selector];
}

+ (void)poseAsClass:(Class)aClass {
    ObjectCategoryWarnOnce(4, self, _cmd);
    [self poseAs:aClass];
}

+ (void)release {
    ObjectCategoryWarnOnce(5, self, _cmd);
}

+ (unsigned)retainCount {
    ObjectCategoryWarnOnce(6, self, _cmd);
    return (unsigned)-1;
}

+ (id)retain {
    ObjectCategoryWarnOnce(7, self, _cmd);
    return self;
}

- (id)autorelease {
    ObjectCategoryWarnOnce(8, self, _cmd);
    NSAutoreleaseObject(self);
    return self;
}

- (id)awakeAfterUsingCoder:(id)coder {
    id result;

    (void)coder;
    ObjectCategoryWarnOnce(9, self, _cmd);
    if ([self respondsToSelector:@selector(awake)])
        [self awake];
    if (![self respondsToSelector:@selector(finishUnarchiving)])
        return self;
    result = [self finishUnarchiving];
    return result == nil ? self : result;
}

- (Class)classForArchiver {
    ObjectCategoryWarnOnce(10, self, _cmd);
    return [self classForCoder];
}

- (Class)classForCoder {
    ObjectCategoryWarnOnce(11, self, _cmd);
    return isa;
}

- (BOOL)conformsToProtocol:(Protocol *)protocol {
    ObjectCategoryWarnOnce(12, self, _cmd);
    return [self conformsTo:protocol];
}

- (id)copyWithZone:(NSZone *)zone {
    ObjectCategoryWarnOnce(13, self, _cmd);
    if (zone == NULL)
        zone = NSDefaultMallocZone();
    return [self copyFromZone:(NXZone *)zone];
}

- (void)dealloc {
    ObjectCategoryWarnOnce(14, self, _cmd);
    [self free];
}

- (NSString *)description {
    ObjectCategoryWarnOnce(15, self, _cmd);
    return [NSString stringWithFormat:@"<%s: 0x%x>", isa->name, self];
}

- (void)doesNotRecognizeSelector:(SEL)selector {
    ObjectCategoryWarnOnce(16, self, _cmd);
    [self doesNotRecognize:selector];
}

- (void)encodeWithCoder:(id)coder {
    (void)coder;
    ObjectCategoryWarnOnce(17, self, _cmd);
}

- (id)initWithCoder:(id)coder {
    (void)coder;
    ObjectCategoryWarnOnce(18, self, _cmd);
    return self;
}

- (BOOL)isKindOfClass:(Class)aClass {
    ObjectCategoryWarnOnce(19, self, _cmd);
    return [self isKindOf:aClass];
}

- (BOOL)isMemberOfClass:(Class)aClass {
    ObjectCategoryWarnOnce(20, self, _cmd);
    return [self isMemberOf:aClass];
}

- (IMP)methodForSelector:(SEL)selector {
    ObjectCategoryWarnOnce(21, self, _cmd);
    return [self methodFor:selector];
}

- (id)perform:(SEL)selector withObject:(id)object {
    ObjectCategoryWarnOnce(22, self, _cmd);
    return [self perform:selector with:object];
}

- (id)perform:(SEL)selector withObject:(id)object1 withObject:(id)object2 {
    ObjectCategoryWarnOnce(23, self, _cmd);
    return [self perform:selector with:object1 with:object2];
}

- (id)performSelector:(SEL)selector withObject:(id)object {
    ObjectCategoryWarnOnce(24, self, _cmd);
    return [self perform:selector with:object];
}

- (id)performSelector:(SEL)selector withObject:(id)object1 withObject:(id)object2 {
    ObjectCategoryWarnOnce(25, self, _cmd);
    return [self perform:selector with:object1 with:object2];
}

- (void)release {
    ObjectCategoryWarnOnce(26, self, _cmd);
    if (NSDecrementExtraRefCountWasZero(self))
        [self dealloc];
}

- (id)replacementObjectForArchiver:(id)archiver {
    ObjectCategoryWarnOnce(27, self, _cmd);
    return [self replacementObjectForCoder:archiver];
}

- (id)replacementObjectForCoder:(id)coder {
    id result;

    (void)coder;
    ObjectCategoryWarnOnce(28, self, _cmd);
    if (![self respondsToSelector:@selector(startArchiving:)])
        return self;
    result = [self startArchiving:nil];
    return result == nil ? self : result;
}

- (BOOL)respondsToSelector:(SEL)selector {
    ObjectCategoryWarnOnce(29, self, _cmd);
    return [self respondsTo:selector];
}

- (unsigned)retainCount {
    ObjectCategoryWarnOnce(30, self, _cmd);
    return NSExtraRefCount(self) + 1;
}

- (id)retain {
    ObjectCategoryWarnOnce(31, self, _cmd);
    NSIncrementExtraRefCount(self);
    return self;
}

@end

#undef ObjectCategoryWarnOnce

typedef struct {
    id object;
    char *bytes;
    int length;
} NSCompatibilityPickle;

static unsigned
NSCompatibilityHashCapacity(unsigned count)
{
    unsigned capacity = 1;

#if !defined(__ppc__) && !defined(__POWERPC__)
    if (count > 0x7fffffffU)
        return 0;
#endif
    while (capacity < count)
        capacity = (capacity << 1) + 1;
    return capacity;
}

static void
NSCompatibilityNoRelease(void *value)
{
    (void)value;
}

static void
NSCompatibilityReleaseObject(void *value)
{
    [(id)value release];
}

static void
NSCompatibilityFreePickleAndReleaseObject(void *value)
{
    NSCompatibilityPickle *pickle = (NSCompatibilityPickle *)value;

    if (pickle == NULL)
        return;
    [pickle->object release];
    NSZoneFree(NSZoneFromPointer(pickle->bytes), pickle->bytes);
    NSZoneFree(NSZoneFromPointer(pickle), pickle);
}

static id
NSCompatibilityGetObject(NSCompatibilityPickle *pickle, NSZone *zone)
{
    NSData *data;
    NSUnarchiver *unarchiver;
    id object;

    if (pickle == NULL)
        return nil;
    if (pickle->object == nil) {
        data = [NSData dataWithBytes:pickle->bytes
                              length:(unsigned)pickle->length];
        if (data != nil) {
            unarchiver = [[NSUnarchiver allocWithZone:zone]
                initForReadingWithData:data];
            if (unarchiver != nil) {
                [unarchiver setObjectZone:zone];
                object = [[unarchiver decodeObject] retain];
                pickle->object = object;
                [unarchiver autorelease];
            }
        }
    }
    return pickle->object;
}

@implementation HashTable (NSCoderExtensions1)

- (id)autorelease
{
    ObjectCompatibilityWarnOnceI386(32, self, _cmd);
    NSAutoreleaseObject(self);
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    NXHashState state;
    const void *key;
    void *value;

    state = [self initState];
    ObjectCompatibilityWarnOnceI386(33, self, _cmd);
    [coder encodeValuesOfObjCTypes:"i%%", &count, &keyDesc, &valueDesc];
    while ([self nextState:&state key:&key value:&value]) {
        [coder encodeValueOfObjCType:keyDesc at:&key];
        [coder encodeValueOfObjCType:valueDesc at:&value];
    }
}

- (id)freeObjects
{
    ObjectCompatibilityWarnOnceI386(34, self, _cmd);
    [self freeKeys:(keyDesc[0] == '@' ? NSCompatibilityReleaseObject
                                       : NSCompatibilityNoRelease)
            values:(valueDesc[0] == '@' ? NSCompatibilityReleaseObject
                                         : NSCompatibilityNoRelease)];
    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    unsigned decodedCount;
    unsigned index;
    unsigned capacity;
    NSZone *zone;
    const void *key;
    void *value;

    ObjectCompatibilityWarnOnceI386(35, self, _cmd);
    if ([coder versionForClassName:@"HashTable"] != 0)
        [coder decodeValuesOfObjCTypes:"i%%", &decodedCount, &keyDesc, &valueDesc];
    else
        [coder decodeValuesOfObjCTypes:"i**", &decodedCount, &keyDesc, &valueDesc];
    if (keyDesc == NULL || valueDesc == NULL) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"%@: key or value description is NULL",
         _NSMethodExceptionProem(self, _cmd)];
    }
    count = 0;
    capacity = NSCompatibilityHashCapacity(decodedCount);
    _nbBuckets = capacity;
    zone = [self zone];
    _buckets = NSZoneMalloc(zone, 8 * capacity);
    memset(_buckets, 0, 8 * capacity);
    for (index = 0; index < decodedCount; index++) {
        [coder decodeValueOfObjCType:keyDesc at:&key];
        [coder decodeValueOfObjCType:valueDesc at:&value];
        [self insertKey:key value:value];
    }
    return self;
}

- (void)release
{
    ObjectCompatibilityWarnOnceI386(36, self, _cmd);
    if (NSDecrementExtraRefCountWasZero(self))
        [self dealloc];
}

- (unsigned)retainCount
{
    ObjectCompatibilityWarnOnceI386(37, self, _cmd);
    return NSExtraRefCount(self) + 1;
}

- (id)retain
{
    ObjectCompatibilityWarnOnceI386(38, self, _cmd);
    NSIncrementExtraRefCount(self);
    return self;
}

@end

@implementation List (NSCoderExtensions1)

- (id)autorelease
{
    ObjectCompatibilityWarnOnceI386(39, self, _cmd);
    NSAutoreleaseObject(self);
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    ObjectCompatibilityWarnOnceI386(40, self, _cmd);
    [coder encodeValuesOfObjCTypes:"i", &numElements];
    if (numElements != 0)
        [coder encodeArrayOfObjCType:"@" count:numElements at:dataPtr];
}

- (id)freeObjects
{
    id object;

    ObjectCompatibilityWarnOnceI386(41, self, _cmd);
    while ((object = [self removeLastObject]) != nil)
        [object release];
    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    unsigned legacyVersion;
    NSZone *zone = [self zone];

    ObjectCompatibilityWarnOnceI386(42, self, _cmd);
    if ([coder versionForClassName:@"List"] != 0) {
        [coder decodeValuesOfObjCTypes:"i", &numElements];
        maxElements = numElements;
        if (numElements != 0) {
            dataPtr = NSZoneMalloc(zone, 4 * numElements);
            [coder decodeArrayOfObjCType:"@" count:numElements at:dataPtr];
        }
    } else {
        legacyVersion = 0;
        [coder decodeValuesOfObjCTypes:"ii", &legacyVersion, &numElements];
        dataPtr = NSZoneMalloc(zone, 4 * numElements);
        maxElements = numElements;
        [coder decodeArrayOfObjCType:"@" count:numElements at:dataPtr];
    }
    return self;
}

- (void)makeObjectsPerform:(SEL)selector withObject:(id)object
{
    int index = (int)numElements;

    ObjectCompatibilityWarnOnceI386(43, self, _cmd);
    while (--index >= 0)
        [dataPtr[index] perform:selector withObject:object];
}

- (void)release
{
    ObjectCompatibilityWarnOnceI386(44, self, _cmd);
    if (NSDecrementExtraRefCountWasZero(self))
        [self free];
}

- (unsigned)retainCount
{
    ObjectCompatibilityWarnOnceI386(45, self, _cmd);
    return NSExtraRefCount(self) + 1;
}

- (id)retain
{
    ObjectCompatibilityWarnOnceI386(46, self, _cmd);
    NSIncrementExtraRefCount(self);
    return self;
}

@end

@implementation Storage (NSCoderExtensions1)

- (id)autorelease
{
    ObjectCompatibilityWarnOnceI386(47, self, _cmd);
    NSAutoreleaseObject(self);
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    ObjectCompatibilityWarnOnceI386(48, self, _cmd);
    [coder encodeValuesOfObjCTypes:"%ii", &description, &elementSize,
                                  &numElements];
    if (numElements != 0)
        [coder encodeArrayOfObjCType:description count:numElements at:dataPtr];
}

- (id)initWithCoder:(NSCoder *)coder
{
    unsigned legacyCapacity;
    unsigned byteCount;
    NSZone *zone = [self zone];

    ObjectCompatibilityWarnOnceI386(49, self, _cmd);
    if ([coder versionForClassName:@"Storage"] == 0) {
        [coder decodeValuesOfObjCTypes:"*iii", &description, &elementSize,
                                               &legacyCapacity, &numElements];
        maxElements = numElements;
        byteCount = elementSize * numElements;
        dataPtr = NSZoneMalloc(zone, byteCount);
        memset(dataPtr, 0, byteCount);
        [coder decodeArrayOfObjCType:description count:numElements at:dataPtr];
        return self;
    }
    [coder decodeValuesOfObjCTypes:"%ii", &description, &elementSize,
                                           &numElements];
    maxElements = numElements;
    if (numElements != 0) {
        byteCount = elementSize * numElements;
        dataPtr = NSZoneMalloc(zone, byteCount);
        memset(dataPtr, 0, byteCount);
        [coder decodeArrayOfObjCType:description count:numElements at:dataPtr];
    }
    return self;
}

- (void)release
{
    ObjectCompatibilityWarnOnceI386(50, self, _cmd);
    if (NSDecrementExtraRefCountWasZero(self))
        [self free];
}

- (unsigned)retainCount
{
    ObjectCompatibilityWarnOnceI386(51, self, _cmd);
    return NSExtraRefCount(self) + 1;
}

- (id)retain
{
    ObjectCompatibilityWarnOnceI386(52, self, _cmd);
    NSIncrementExtraRefCount(self);
    return self;
}

@end

@implementation StreamTable (NSCoderExtensions1)

- (void)encodeWithCoder:(NSCoder *)coder
{
    NXHashState state;
    const void *key;
    void *value;
    NSCompatibilityPickle *pickle;

    state = [self initState];
    ObjectCompatibilityWarnOnceI386(53, self, _cmd);
    [super encodeWithCoder:coder];
    while ([self nextState:&state key:&key value:&value]) {
        pickle = (NSCompatibilityPickle *)value;
        [coder encodeValueOfObjCType:keyDesc at:&key];
        [coder encodeValueOfObjCType:"i" at:&pickle->length];
        [coder encodeArrayOfObjCType:"c" count:(unsigned)pickle->length
                                  at:pickle->bytes];
    }
}

- (id)freeObjects
{
    ObjectCompatibilityWarnOnceI386(54, self, _cmd);
    [self freeKeys:(keyDesc[0] == '@' ? NSCompatibilityReleaseObject
                                       : NSCompatibilityNoRelease)
            values:NSCompatibilityFreePickleAndReleaseObject];
    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    StreamTable *table;
    unsigned remaining;
    NSZone *zone = [self zone];
    const void *key;
    int length;
    NSCompatibilityPickle *pickle;

    ObjectCompatibilityWarnOnceI386(55, self, _cmd);
    table = [super initWithCoder:coder];
    remaining = table->count;
    while (remaining-- != 0) {
        pickle = NSZoneMalloc(zone, sizeof(*pickle));
        [coder decodeValueOfObjCType:keyDesc at:&key];
        [coder decodeValueOfObjCType:"i" at:&length];
        pickle->bytes = NSZoneMalloc(zone, length);
        pickle->length = length;
        [coder decodeArrayOfObjCType:"c" count:length at:pickle->bytes];
        pickle->object = nil;
        [table insertKey:key value:pickle];
    }
    return table;
}

- (BOOL)nextStreamState:(NXHashState *)state
                    key:(const void **)key
                  value:(id *)value
{
    NSCompatibilityPickle *pickle;
    BOOL found;

    found = [self nextState:state key:key value:(void **)&pickle];
    ObjectCompatibilityWarnOnceI386(56, self, _cmd);
    *value = NSCompatibilityGetObject(pickle, [self zone]);
    return found;
}

- (id)valueForStreamKey:(const void *)key
{
    NSCompatibilityPickle *pickle =
        (NSCompatibilityPickle *)[self valueForKey:key];

    ObjectCompatibilityWarnOnceI386(57, self, _cmd);
    return NSCompatibilityGetObject(pickle, [self zone]);
}

@end

@implementation Object (NSConformsToProtocolNamed)

- (BOOL)_conformsToProtocolNamed:(const char *)protocolName {
    struct NSProtocolName protocol;
    protocol.protocol_name = protocolName;

    return [(id)isa conformsToProtocol:(Protocol *)&protocol];
}

@end

@implementation NSObject (NXCompatibilityFixes)

+ (BOOL)conformsTo:(Protocol *)protocol
{
    ObjectCompatibilityWarnOnceI386(58, self, _cmd);
    return [self conformsToProtocol:protocol];
}

+ (IMP)methodFor:(SEL)selector
{
    ObjectCompatibilityWarnOnceI386(59, self, _cmd);
    return [self methodForSelector:selector];
}

- (BOOL)conformsTo:(Protocol *)protocol
{
    ObjectCompatibilityWarnOnceI386(60, self, _cmd);
    return [self conformsToProtocol:protocol];
}

- (BOOL)isKindOf:(Class)aClass
{
    ObjectCompatibilityWarnOnceI386(61, self, _cmd);
    return [self isKindOfClass:aClass];
}

- (IMP)methodFor:(SEL)selector
{
    ObjectCompatibilityWarnOnceI386(62, self, _cmd);
    return [self methodForSelector:selector];
}

- (BOOL)respondsTo:(SEL)selector
{
    ObjectCompatibilityWarnOnceI386(63, self, _cmd);
    return [self respondsToSelector:selector];
}

@end

#undef ObjectCompatibilityWarnOnceI386

/*  On i386 the NXObject pair is a category on NSCoder in this module.
    The PPC target instead places the architecture-specific methods on the
    NSCoder class itself; those bodies are in NSCoder.m.  */
#if !defined(__ppc__) && !defined(__POWERPC__)
#import <Foundation/NSCoder.h>
#import <objc/typedstream.h>

extern id _NSNewImmutableData(const void *bytes, unsigned length,
                              NSZone *zone);

static unsigned char NSCoderEncodeNXObjectWarned;
static unsigned char NSCoderDecodeNXObjectWarned;

static void NSCoderWarnNXObjectCompatibility(id coder, SEL selector,
                                              unsigned char *warned)
{
    if (!*warned) {
        *warned = 1;
        NSLog(@"%@: warning: Object compatibility method has been executed at least once.  Convert source code off it NOW!",
              _NSMethodExceptionProem(coder, selector));
    }
}

@implementation NSCoder (NSTypedstreamCompatibility)

- (void)encodeNXObject:(id)object
{
    int length;
    char *buffer = NXWriteRootObjectToBuffer(object, &length);
    id data = _NSNewImmutableData(buffer, (unsigned)length, NULL);

    NSCoderWarnNXObjectCompatibility(self, _cmd,
                                     &NSCoderEncodeNXObjectWarned);
    [self encodeDataObject:data];
    [data release];
    NXFreeObjectBuffer(buffer, length);
}

- (id)decodeNXObject
{
    NSData *data = [self decodeDataObject];

    NSCoderWarnNXObjectCompatibility(self, _cmd,
                                     &NSCoderDecodeNXObjectWarned);
    return NXReadObjectFromBuffer((const char *)[data bytes],
                                  (int)[data length]);
}

@end
#endif
