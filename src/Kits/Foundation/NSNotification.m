/*	NSNotification.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSNotification.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSString.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSZone.h>
#import <objc/objc-runtime.h>
#include <string.h>

extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern IMP _NSIMPForObjectAndSelector(id object, SEL aSelector);
extern NSLock *_NSGlobalRetainLock;
extern void _NSIncrementInternalRefCount(id object, unsigned *refCount,
                                         int mask, id lock);
extern BOOL _NSDecrementInternalRefCountWasZero(id object, unsigned *refCount,
                                                int mask, id lock);
extern unsigned _NSInternalRefCount(id object, unsigned refCount, int mask);

@interface NSConcreteNotification : NSNotification {
@public
    NSString *nameAndRefCount;
    id object;
    NSDictionary *userInfo;
}
- (id)initWithName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo;
@end

@interface NSNotification (NSNotificationPrivate)
- (id)initWithName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo;
@end

typedef struct {
    NSString *name;
    unsigned int nameHash;
    id object;
    id observer;
    SEL selector;
    IMP callback;
    unsigned int flags;
} NSNotificationObserver;

typedef struct {
    Class isa;
    id lock;
    void *registry;
    unsigned int registrySize;
    unsigned int registryCount;
    int *niltable;
    unsigned int niltableSize;
    unsigned int niltableCount;
    int *hashtable;
    unsigned int hashtableSize;
    unsigned int hashtableMask;
    unsigned int deletedCount;
    void *reserved1;
    void *reserved;
} NSNotificationCenterLayout;

typedef void (*NSNotificationCenterApplyCallback)(NSNotificationObserver *observer, void *context);

@interface NSNotificationCenter (NSNotificationCenterPrivate)
- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName
             object:(id)anObject flags:(unsigned int)flags;
- (void)postNotificationName:(NSString *)aName object:(id)anObject
                    userInfo:(NSDictionary *)aUserInfo flags:(unsigned int)flags;
- (void)applyCallBack:(NSNotificationCenterApplyCallback)callback context:(void *)context
                 name:(NSString *)aName object:(id)anObject literally:(BOOL)literally;
- (unsigned int)countObserversName:(NSString *)aName object:(id)anObject literally:(BOOL)literally;
- (unsigned int)suspensionBehaviorName:(NSString *)aName object:(id)anObject literally:(BOOL)literally;
- (BOOL)checkSuspensionBehavior:(unsigned int)behavior deliveryStatus:(unsigned int)status;
- (void)_bundleLoaded;
- (void)_taskNowMultiThreaded;
- (void)_taskNowSingleThreaded;
@end

NSLock *_NSNotificationCenterLock;
static NSNotificationCenter *NSNotificationCenterDefault;
static NSMutableDictionary *NSNotificationCenterDefaultsByClass;
#if defined(__ppc__) || defined(__POWERPC__)
static BOOL NSNotificationCenterSerializeRemoves = YES;
#endif

unsigned int
NSNotificationSuspensionBehaviorFromFlags(unsigned int flags)
{
    return flags & 7u;
}

int NSNotificationSuspensionBehaviorNoInterest(void)
{
    return 0;
}

unsigned int
NSHigherNotificationSuspensionBehavior(unsigned int left, unsigned int right)
{
    return (left > right) ? left : right;
}

static int
_addToTables(NSNotificationCenter *center, NSNotificationObserver *observer,
             int index)
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)center;
    int result = (int)observer;

    if (observer->name != nil) {
        unsigned int slot = layout->hashtableMask & observer->nameHash;

        while (layout->hashtable[slot] >= 0) {
            slot++;
            result = (int)(slot + 1);
            if (layout->hashtableSize <= slot + 1) {
                unsigned int oldSize = layout->hashtableSize;
                layout->hashtableSize += 10;
                layout->hashtable = (int *)NSZoneRealloc(0, layout->hashtable,
                                                          layout->hashtableSize * sizeof(int));
                while (oldSize < layout->hashtableSize)
                    layout->hashtable[oldSize++] = -1;
            }
        }
        layout->hashtable[slot] = index;
    } else {
        unsigned int oldSize;

        if (layout->niltableCount == 0 || layout->niltableSize <= layout->niltableCount + 1) {
            oldSize = layout->niltableSize;
            layout->niltableSize += 4;
            layout->niltable = (int *)NSZoneRealloc(0, layout->niltable,
                                                     layout->niltableSize * sizeof(int));
            while (oldSize < layout->niltableSize)
                layout->niltable[oldSize++] = -1;
        }
        result = (int)layout->niltable;
        layout->niltable[layout->niltableCount++] = index;
    }
    return result;
}

static void
_redoTables(NSNotificationCenter *center)
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)center;
    unsigned int size;
    unsigned int index;

    if (layout->registryCount == 0) {
        if (layout->niltable != nil) {
            NSZoneFree(0, layout->niltable);
            layout->niltable = nil;
        }
        layout->niltableCount = 0;
        layout->niltableSize = 0;
        if (layout->hashtable != nil) {
            NSZoneFree(0, layout->hashtable);
            layout->hashtable = nil;
        }
        layout->hashtableMask = 0;
        layout->hashtableSize = 0;
        layout->deletedCount = 0;
        return;
    }

#if defined(__ppc__) || defined(__POWERPC__)
    if (layout->niltable != nil) {
        NSZoneFree(0, layout->niltable);
        layout->niltable = nil;
    }
    layout->niltableSize = 0;
#endif
    layout->niltableCount = 0;
    layout->deletedCount = 0;
    size = 128;
    while (size < 4 * (layout->registryCount + 16))
        size *= 2;
    layout->hashtableMask = size - 1;
    layout->hashtableSize = size + 10;
    layout->hashtable = (int *)NSZoneRealloc(0, layout->hashtable,
                                              layout->hashtableSize * sizeof(int));
    for (index = 0; index < layout->hashtableSize; index++)
        layout->hashtable[index] = -1;
    for (index = 0; index < layout->registryCount; index++)
        _addToTables(center,
            &((NSNotificationObserver *)layout->registry)[index], index);
}

static int
_replaceInTables(NSNotificationCenter *center,
                 NSNotificationObserver *observer,
                 NSNotificationObserver *replacement)
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)center;
    NSNotificationObserver *registry = (NSNotificationObserver *)layout->registry;
    unsigned int index = (unsigned int)(observer - registry);
    unsigned int replacementIndex = replacement != NULL
        ? (unsigned int)(replacement - registry) : 0x40000000u;
    unsigned int slot = 0;
    int result = (int)index;

    if (replacement == NULL)
        layout->deletedCount++;
    if (observer->name != nil) {
        slot = layout->hashtableMask & observer->nameHash;
        result = (int)slot;
        while (layout->hashtable[slot] != -1) {
            if ((unsigned int)layout->hashtable[slot] == index) {
                layout->hashtable[slot] = (int)replacementIndex;
                return result;
            }
            slot++;
            result = (int)slot;
        }
    } else {
        for (slot = 0; slot < layout->niltableCount; slot++) {
            if ((unsigned int)layout->niltable[slot] == index) {
                layout->niltable[slot] = (int)replacementIndex;
                return (int)slot;
            }
        }
        if (layout->niltable != NULL)
            result = (int)slot;
    }
    return result;
}

static BOOL
NSNotificationCenterObserverMatches(NSNotificationObserver *entry,
                                   id observer, NSString *name, id object)
{
    return entry->observer == observer && (object == nil || entry->object == object) &&
        (name == nil || entry->name == name || [entry->name isEqualToString:name]);
}

static void
NSNotificationCenterCountCallback(NSNotificationObserver *observer, void *context)
{
    (void)observer;
    (*(unsigned int *)context)++;
}

static void
NSNotificationCenterSuspensionCallback(NSNotificationObserver *observer, void *context)
{
    unsigned int *behavior = (unsigned int *)context;
    *behavior = NSHigherNotificationSuspensionBehavior(
        NSNotificationSuspensionBehaviorFromFlags(observer->flags), *behavior);
}

typedef struct {
    NSNotificationObserver local[16];
    NSNotificationObserver *entries;
    unsigned int count;
    unsigned int capacity;
} NSNotificationCenterMatches;

#if defined(__ppc__) || defined(__POWERPC__)
typedef struct NSNotificationCenterPostInfo {
    struct NSNotificationCenterPostInfo *next;
    struct NSNotificationCenterPostInfo *previous;
    NSThread *thread;
    unsigned int count;
    NSNotificationObserver *observers;
} NSNotificationCenterPostInfo;

static void
NSNotificationCenterBeginPost(NSNotificationCenterLayout *layout,
                              NSNotificationCenterPostInfo *post,
                              NSNotificationCenterMatches *matches)
{
    NSNotificationCenterPostInfo **head =
        (NSNotificationCenterPostInfo **)&layout->reserved1;

    if (*head != NULL) {
        post->next = (*head)->next;
        post->previous = *head;
        (*head)->next->previous = post;
        (*head)->next = post;
    } else {
        *head = post;
        post->next = post;
        post->previous = post;
    }
    post->thread = _NSCurrentThread();
    post->count = matches->count;
    post->observers = matches->entries != NULL
        ? matches->entries : matches->local;
}

static BOOL
NSNotificationCenterIsPostingToObserver(NSNotificationCenterLayout *layout,
                                       id observer)
{
    NSNotificationCenterPostInfo *head =
        (NSNotificationCenterPostInfo *)layout->reserved1;
    NSThread *thread = _NSCurrentThread();
    NSNotificationCenterPostInfo *post;

    if (head == NULL)
        return NO;
    post = head;
    do {
        unsigned int index;

        if (post->thread == thread) {
            for (index = 0; index < post->count; index++) {
                if (post->observers[index].observer == observer)
                    post->observers[index].observer = nil;
            }
        } else {
            for (index = 0; index < post->count; index++) {
                if (post->observers[index].observer == observer)
                    return YES;
            }
        }
        post = post->next;
    } while (post != head);
    return NO;
}

static void
NSNotificationCenterWaitForObserver(NSNotificationCenterLayout *layout,
                                    id observer)
{
    while (NSNotificationCenterIsPostingToObserver(layout, observer))
        [(NSCondition *)layout->lock wait];
}

static void
NSNotificationCenterEndPost(NSNotificationCenterLayout *layout,
                            NSNotificationCenterPostInfo *post)
{
    NSNotificationCenterPostInfo **head =
        (NSNotificationCenterPostInfo **)&layout->reserved1;

    post->next->previous = post->previous;
    post->previous->next = post->next;
    *head = (post->next == post) ? NULL : post->next;
}
#endif

static void
NSNotificationCenterAppendMatch(NSNotificationCenterMatches *matches,
                                NSNotificationObserver *observer,
                                unsigned int maximumCount)
{
    if (matches->count == matches->capacity) {
        unsigned int newCapacity = maximumCount;
        NSNotificationObserver *newEntries = (NSNotificationObserver *)NSZoneMalloc(
            0, newCapacity * sizeof(NSNotificationObserver));
        memcpy(newEntries, matches->entries, matches->count * sizeof(NSNotificationObserver));
        if (matches->entries != matches->local)
            NSZoneFree(0, matches->entries);
        matches->entries = newEntries;
        matches->capacity = newCapacity;
    }
    matches->entries[matches->count++] = *observer;
}

static NSNotificationCenterMatches
NSNotificationCenterCollect(NSNotificationCenter *center, NSString *name, id object,
                            unsigned int deliveryStatus, BOOL canCheck)
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)center;
    NSNotificationCenterMatches matches;
    unsigned int index;

    matches.entries = matches.local;
    matches.count = 0;
    matches.capacity = 16;
    for (index = 0; index < layout->niltableCount; index++) {
        int registryIndex = layout->niltable[index];
        NSNotificationObserver *observer;
        BOOL deliver = YES;

        if (registryIndex < 0 || registryIndex == 0x40000000)
            continue;
        observer = &((NSNotificationObserver *)layout->registry)[registryIndex];
        if (canCheck)
            deliver = [center checkSuspensionBehavior:
                           NSNotificationSuspensionBehaviorFromFlags(observer->flags)
                                               deliveryStatus:deliveryStatus];
        if (!deliver || (observer->object != nil && observer->object != object))
            continue;
        NSNotificationCenterAppendMatch(&matches, observer,
                                        layout->registryCount);
    }

    if (name != nil && layout->hashtable != nil) {
        unsigned int nameHash = [name hash];
        unsigned int slot = layout->hashtableMask & nameHash;

        while (layout->hashtable[slot] >= 0) {
            int registryIndex = layout->hashtable[slot++];
            NSNotificationObserver *observer;
            BOOL deliver = YES;

            if (registryIndex == 0x40000000)
                continue;
            observer = &((NSNotificationObserver *)layout->registry)[registryIndex];
            if (canCheck)
                deliver = [center checkSuspensionBehavior:
                               NSNotificationSuspensionBehaviorFromFlags(observer->flags)
                                                   deliveryStatus:deliveryStatus];
            if (!deliver)
                continue;
            if (observer->nameHash != nameHash ||
                (observer->name != name && ![observer->name isEqualToString:name]) ||
                (observer->object != nil && observer->object != object))
                continue;
            NSNotificationCenterAppendMatch(&matches, observer,
                                            layout->registryCount);
        }
    }
    if (matches.entries == matches.local)
        matches.entries = nil;
    return matches;
}

static void
NSNotificationCenterDeliver(NSNotificationObserver *observers, unsigned int count,
                            NSNotification *notification, NSString *name,
                            id object, NSDictionary *userInfo,
                            BOOL releaseNotification,
                            NSNotificationCenterLayout *layout
#if defined(__ppc__) || defined(__POWERPC__)
                            , NSNotificationCenterPostInfo *post
#endif
                            )
{
    NSException *firstException = nil;
    unsigned int index;

    if (notification == nil)
        notification = [[NSNotification allocWithZone:0]
            initWithName:name object:object userInfo:userInfo];

    for (index = 0; index < count; index++) {
        NSNotificationObserver *observer = &observers[index];

        if (
#if defined(__ppc__) || defined(__POWERPC__)
            observer->observer != nil
#else
            YES
#endif
            ) {
            NS_DURING
                ((void (*)(id, SEL, id))observer->callback)(
                    observer->observer, observer->selector, notification);
            NS_HANDLER
                if (firstException == nil)
                    firstException = [localException retain];
            NS_ENDHANDLER
        }
    }
    if (releaseNotification)
        [notification release];
#if defined(__ppc__) || defined(__POWERPC__)
    if (NSNotificationCenterSerializeRemoves && post != NULL) {
        [(NSCondition *)layout->lock lock];
        NSNotificationCenterEndPost(layout, post);
        [(NSCondition *)layout->lock broadcast];
        [(NSCondition *)layout->lock unlock];
    }
#else
    (void)layout;
#endif
    if (firstException != nil)
        [[firstException autorelease] raise];
}

static NSString *
NSConcreteNotificationName(NSConcreteNotification *notification)
{
    return (NSString *)((unsigned int)notification->nameAndRefCount & ~3u);
}

@implementation NSNotification

+ (id)allocWithZone:(NSZone *)zone
{
    Class notificationClass = self;

    if (notificationClass == [NSNotification class])
        notificationClass = [NSConcreteNotification class];
    return NSAllocateObject(notificationClass, 0, zone);
}

+ (id)notificationWithName:(NSString *)aName object:(id)anObject
{
    return [[[self allocWithZone:0] initWithName:aName
                                            object:anObject
                                          userInfo:nil] autorelease];
}

+ (id)notificationWithName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo
{
    return [[[self allocWithZone:0] initWithName:aName
                                            object:anObject
                                          userInfo:aUserInfo] autorelease];
}

- (Class)classForCoder
{
    return [NSNotification class];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];
}

- (NSString *)description
{
    id notificationObject = [self object];
    NSDictionary *notificationUserInfo = [self userInfo];
    NSMutableString *result = [[[NSMutableString allocWithZone:0] initWithCapacity:256] autorelease];

    if (notificationObject != nil && notificationUserInfo != nil) {
        [result appendFormat:@"%@ %x {name = %@; object = %@; userInfo = %@}",
                             isa, self, [self name], notificationObject, notificationUserInfo];
    } else if (notificationObject != nil) {
        [result appendFormat:@"%@ %x {name = %@; object = %@}",
                             isa, self, [self name], notificationObject];
    } else if (notificationUserInfo != nil) {
        [result appendFormat:@"%@ %x {name = %@; userInfo = %@}",
                             isa, self, [self name], notificationUserInfo];
    } else {
        [result appendFormat:@"%@ %x {name = %@}", isa, self, [self name]];
    }
    return result;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[self name]];
    [aCoder encodeObject:[self object]];
    [aCoder encodeObject:[self userInfo]];
}

- (unsigned)hash
{
    return [[self name] hash];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    NSString *aName = [aDecoder decodeObject];
    id anObject = [aDecoder decodeObject];
    NSDictionary *aUserInfo = [aDecoder decodeObject];
    NSZone *zone = NSZoneFromPointer((void *)self);
    Class notificationClass = *(Class *)self;

    [self dealloc];
    self = [notificationClass allocWithZone:zone];
    return [(NSConcreteNotification *)self initWithName:aName object:anObject userInfo:aUserInfo];
}

- (id)init
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: should never be used", proem];
    return nil;
}

- (BOOL)isEqual:(id)anObject
{
    NSString *otherName;
    NSString *thisName;
    NSDictionary *otherUserInfo;
    NSDictionary *thisUserInfo;

    if (self == anObject)
        return YES;
    if (anObject == nil || ![anObject isKindOfClass:[NSNotification class]])
        return NO;
#if defined(__ppc__) || defined(__POWERPC__)
    thisName = [self name];
    otherName = [anObject name];
#else
    otherName = [anObject name];
    thisName = [self name];
#endif
    if (![thisName isEqualToString:otherName])
        return NO;
    if ([self object] != [anObject object])
        return NO;
#if defined(__ppc__) || defined(__POWERPC__)
    thisUserInfo = [self userInfo];
    otherUserInfo = [anObject userInfo];
#else
    otherUserInfo = [anObject userInfo];
    thisUserInfo = [self userInfo];
#endif
    return [thisUserInfo isEqualToDictionary:otherUserInfo];
}

- (NSString *)name
{
    NSRequestConcreteImplementation(self, _cmd, [NSNotification class]);
    return nil;
}

- (id)object
{
    NSRequestConcreteImplementation(self, _cmd, [NSNotification class]);
    return nil;
}

- (id)replacementObjectForPortCoder:(id)aPortCoder
{
    return self;
}

- (NSDictionary *)userInfo
{
    NSRequestConcreteImplementation(self, _cmd, [NSNotification class]);
    return nil;
}

@end

@implementation NSConcreteNotification

- (void)dealloc
{
    [NSConcreteNotificationName(self) release];
    nameAndRefCount = nil;
    if (object != nil)
        [object release];
    object = nil;
    if (userInfo != nil)
        [userInfo release];
    userInfo = nil;
    [super dealloc];
}

- (id)initWithName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo
{
    unsigned int refCount;

    if (aName == nil) {
        [super dealloc];
        return nil;
    }
    refCount = (unsigned int)nameAndRefCount & 3u;
    nameAndRefCount = (NSString *)((unsigned int)[aName copyWithZone:0] | refCount);
    if (anObject != nil)
        object = [anObject retain];
    if (aUserInfo != nil)
        userInfo = [aUserInfo retain];
    return self;
}

- (NSString *)name
{
    return NSConcreteNotificationName(self);
}

- (id)object
{
    return object;
}

- (NSDictionary *)userInfo
{
    return userInfo;
}

- (id)retain
{
    _NSIncrementInternalRefCount(self, (unsigned *)&nameAndRefCount, 3,
                                 _NSGlobalRetainLock);
    return self;
}

- (oneway void)release
{
    if (_NSDecrementInternalRefCountWasZero(self,
            (unsigned *)&nameAndRefCount, 3, _NSGlobalRetainLock))
        [self dealloc];
}

- (unsigned)retainCount
{
    return _NSInternalRefCount(self, (unsigned)nameAndRefCount, 3);
}

@end

@implementation NSNotificationCenter

+ (id)defaultCenter
{
    NSNotificationCenter *center;

    if (_NSNotificationCenterLock != nil)
        [_NSNotificationCenterLock lock];
    if (self == [NSNotificationCenter class]) {
        if (NSNotificationCenterDefault == nil) {
            NSNotificationCenterDefault = [[self allocWithZone:0] init];
            [NSNotificationCenterDefault addObserver:NSNotificationCenterDefault
                                             selector:@selector(_taskNowMultiThreaded)
                                                 name:NSWillBecomeMultiThreadedNotification object:nil];
            [NSNotificationCenterDefault addObserver:NSNotificationCenterDefault
                                             selector:@selector(_taskNowSingleThreaded)
                                                 name:NSDidBecomeSingleThreadedNotification object:nil];
        }
        center = NSNotificationCenterDefault;
    } else {
        if (NSNotificationCenterDefaultsByClass == nil)
            NSNotificationCenterDefaultsByClass = [[NSMutableDictionary allocWithZone:0]
                initWithCapacity:2];
        center = [NSNotificationCenterDefaultsByClass objectForKey:self];
        if (center == nil) {
            center = [[self allocWithZone:0] init];
            if (center != nil) {
                [NSNotificationCenterDefaultsByClass setObject:center forKey:self];
                [center release];
                center = [NSNotificationCenterDefaultsByClass objectForKey:self];
            }
        }
    }
    if (_NSNotificationCenterLock != nil)
        [_NSNotificationCenterLock unlock];
    return center;
}

#if defined(__ppc__) || defined(__POWERPC__)
+ (void)setNotificationCenterSerializeRemoves:(BOOL)flag
{
    NSNotificationCenterSerializeRemoves = flag;
}
#endif

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName object:(id)anObject
{
    [self addObserver:observer selector:aSelector name:aName object:anObject flags:0];
}

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName
             object:(id)anObject flags:(unsigned int)flags
{
    BOOL observesSuspension = [self respondsToSelector:
        @selector(changedSuspensionBehavior:name:object:)];
    unsigned int oldBehavior = 0;
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;
    NSNotificationObserver *entry;
    IMP callback;

    if (observer == nil)
        return;
    if (layout->lock != nil)
        [layout->lock lock];
    if (observesSuspension) {
        unsigned int requestedBehavior =
            NSNotificationSuspensionBehaviorFromFlags(flags);
        unsigned int newBehavior;

        oldBehavior = [self suspensionBehaviorName:aName object:anObject literally:YES];
        newBehavior = NSHigherNotificationSuspensionBehavior(requestedBehavior,
                                                              oldBehavior);
        if (newBehavior != oldBehavior)
            [self changedSuspensionBehavior:
                newBehavior
                                      name:aName object:anObject];
    }
    if (layout->registrySize == layout->registryCount) {
        layout->registrySize += 64;
        layout->registry = NSZoneRealloc(0, layout->registry,
            sizeof(NSNotificationObserver) * layout->registrySize);
    }
    entry = &((NSNotificationObserver *)layout->registry)[layout->registryCount];
    entry->name = [aName copyWithZone:0];
    entry->nameHash = (entry->name != nil) ? [entry->name hash] : 0;
    entry->object = anObject;
    entry->observer = observer;
    entry->selector = aSelector;
    callback = _NSIMPForObjectAndSelector(observer, aSelector);
    if (callback == (IMP)0)
        callback = (IMP)objc_msgSend;
    entry->callback = callback;
    entry->flags = flags;
    layout->registryCount++;

    if (layout->deletedCount <= 25 &&
        layout->hashtableMask >= 3 * (layout->deletedCount + layout->registryCount))
        _addToTables(self, entry, layout->registryCount - 1);
    else
        _redoTables(self);
    if (layout->lock != nil)
        [layout->lock unlock];
}

- (void)postNotification:(NSNotification *)notification
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;
    NSNotificationCenterMatches matches;
    id notificationObject;
    NSString *notificationName;
#if defined(__ppc__) || defined(__POWERPC__)
    NSNotificationCenterPostInfo post;
    NSNotificationCenterPostInfo *postPointer = NULL;
#endif

    if (notification == nil) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: notification cannot be nil", proem];
        return;
    }
    if (layout->registryCount == 0)
        return;
    if (layout->lock != nil)
        [layout->lock lock];
    notificationObject = [notification object];
    notificationName = [notification name];
    matches = NSNotificationCenterCollect(self, notificationName,
                                          notificationObject, 0, NO);
#if defined(__ppc__) || defined(__POWERPC__)
    if (matches.count != 0) {
        postPointer = &post;
        if (NSNotificationCenterSerializeRemoves)
            NSNotificationCenterBeginPost(layout, &post, &matches);
    }
#endif
    if (layout->lock != nil)
        [layout->lock unlock];
    NSNotificationCenterDeliver(matches.entries != nil ? matches.entries : matches.local,
                                 matches.count, notification, nil, nil, nil, NO, layout
#if defined(__ppc__) || defined(__POWERPC__)
                                 , postPointer
#endif
                                 );
    if (matches.entries != nil)
        NSZoneFree(0, matches.entries);
}

- (void)postNotificationName:(NSString *)aName object:(id)anObject
{
#if defined(__ppc__) || defined(__POWERPC__)
    [self postNotificationName:aName object:anObject userInfo:nil flags:0];
#else
    [self postNotificationName:aName object:anObject userInfo:nil];
#endif
}

- (void)postNotificationName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo
{
    [self postNotificationName:aName object:anObject userInfo:aUserInfo flags:0];
}

- (void)postNotificationName:(NSString *)aName object:(id)anObject
                    userInfo:(NSDictionary *)aUserInfo flags:(unsigned int)flags
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;
    NSNotificationCenterMatches matches;
    BOOL canCheckSuspensionBehavior =
        [self respondsToSelector:@selector(checkSuspensionBehavior:deliveryStatus:)];
#if defined(__ppc__) || defined(__POWERPC__)
    NSNotificationCenterPostInfo post;
    NSNotificationCenterPostInfo *postPointer = &post;
#endif

    if (aName == nil) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: name cannot be nil", proem];
        return;
    }
    if (layout->registryCount == 0)
        return;
    if (layout->lock != nil)
        [layout->lock lock];
    matches = NSNotificationCenterCollect(self, aName, anObject,
        flags & 7u, canCheckSuspensionBehavior);
#if defined(__ppc__) || defined(__POWERPC__)
    if (matches.count != 0 && NSNotificationCenterSerializeRemoves) {
        NSNotificationCenterBeginPost(layout, &post, &matches);
        postPointer = &post;
    }
#endif
    if (layout->lock != nil)
        [layout->lock unlock];
    if (matches.count == 0) {
        if (matches.entries != nil)
            NSZoneFree(0, matches.entries);
        return;
    }
    NSNotificationCenterDeliver(matches.entries != nil ? matches.entries : matches.local,
                                 matches.count, nil, aName, anObject, aUserInfo, YES, layout
#if defined(__ppc__) || defined(__POWERPC__)
                                 , postPointer
#endif
                                 );
    if (matches.entries != nil)
        NSZoneFree(0, matches.entries);
}

- (void)removeObserver:(id)observer
{
    [self removeObserver:observer name:nil object:nil];
}

- (void)removeObserver:(id)observer name:(NSString *)aName object:(id)anObject
{
    BOOL observesSuspension = [self respondsToSelector:
        @selector(changedSuspensionBehavior:name:object:)];
    unsigned int oldBehavior = 0;
    unsigned int index = 0;
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;
    NSNotificationObserver *registry;

    if (observer == nil || layout->registryCount == 0)
        return;
    if (layout->lock != nil)
        [layout->lock lock];
#if defined(__ppc__) || defined(__POWERPC__)
    if (NSNotificationCenterSerializeRemoves)
        NSNotificationCenterWaitForObserver(layout, observer);
#endif
    registry = (NSNotificationObserver *)layout->registry;
    while (index < layout->registryCount) {
        NSNotificationObserver *entry = &registry[index];

        if (!NSNotificationCenterObserverMatches(entry, observer, aName, anObject)) {
            index++;
            continue;
        }
        while (index < layout->registryCount) {
            unsigned int lastIndex = layout->registryCount - 1;
            NSNotificationObserver *last = &registry[lastIndex];

            if (!NSNotificationCenterObserverMatches(last, observer, aName, anObject))
                break;
            if (observesSuspension)
                oldBehavior = [self suspensionBehaviorName:aName object:anObject literally:YES];
            _replaceInTables(self, last, NULL);
            layout->registryCount--;
            if (observesSuspension) {
                unsigned int newBehavior =
                    [self suspensionBehaviorName:aName object:anObject literally:YES];
                if (newBehavior != oldBehavior) {
                    void (*changed)(id, SEL, unsigned int, id, id) =
                        (void (*)(id, SEL, unsigned int, id, id))[self
                            methodForSelector:@selector(changedSuspensionBehavior:name:object:)];
                    changed(self, @selector(changedSuspensionBehavior:name:object:),
                            newBehavior, aName, anObject);
                }
            }
        }
        if (index >= layout->registryCount)
            break;
        entry = &registry[index];
        if (observesSuspension)
            oldBehavior = [self suspensionBehaviorName:aName object:anObject literally:YES];
        _replaceInTables(self, entry, NULL);
        layout->registryCount--;
        if (index < layout->registryCount) {
            NSNotificationObserver *last = &registry[layout->registryCount];
            _replaceInTables(self, last, &registry[index]);
            registry[index] = *last;
        }
        if (observesSuspension) {
            unsigned int newBehavior =
                [self suspensionBehaviorName:aName object:anObject literally:YES];
            if (newBehavior != oldBehavior) {
                void (*changed)(id, SEL, unsigned int, id, id) =
                    (void (*)(id, SEL, unsigned int, id, id))[self
                        methodForSelector:@selector(changedSuspensionBehavior:name:object:)];
                changed(self, @selector(changedSuspensionBehavior:name:object:),
                        newBehavior, aName, anObject);
            }
        }
        index++;
    }
    if (layout->lock != nil)
        [layout->lock unlock];
}

- (void)applyCallBack:(NSNotificationCenterApplyCallback)callback context:(void *)context
                 name:(NSString *)aName object:(id)anObject literally:(BOOL)literally
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;
    NSNotificationObserver *registry = (NSNotificationObserver *)layout->registry;
    unsigned int nameHash;
    unsigned int slot;

    if (layout->registryCount == 0)
        return;
    nameHash = [aName hash];
    if (layout->niltableCount != 0 && (!literally || aName == nil)) {
        for (slot = 0; slot < layout->niltableCount; slot++) {
            int index = layout->niltable[slot];
            NSNotificationObserver *entry;

            if (index < 0 || index == 0x40000000)
                continue;
            entry = &registry[index];
            if (entry->object == nil || entry->object == anObject)
                callback(entry, context);
        }
    }
    slot = layout->hashtableMask & nameHash;
    while (layout->hashtable[slot] >= 0) {
        int index = layout->hashtable[slot++];
        NSNotificationObserver *entry;

        if (index == 0x40000000)
            continue;
        entry = &registry[index];
        if (literally ? entry->object != anObject :
            (entry->object != nil && entry->object != anObject))
            continue;
        if (literally) {
            if (entry->nameHash != nameHash ||
                (entry->name != aName &&
                 (aName == nil || ![aName isEqualToString:entry->name])))
                continue;
        } else if (aName != nil && (entry->nameHash != nameHash ||
                   (entry->name != aName && ![aName isEqualToString:entry->name]))) {
            continue;
        }
        callback(entry, context);
    }
}

- (unsigned int)countObserversName:(NSString *)aName object:(id)anObject literally:(BOOL)literally
{
    unsigned int count;

    if (((NSNotificationCenterLayout *)self)->lock != nil)
        [((NSNotificationCenterLayout *)self)->lock lock];
    count = 0;
    [self applyCallBack:NSNotificationCenterCountCallback context:&count
                   name:aName object:anObject literally:literally];
    if (((NSNotificationCenterLayout *)self)->lock != nil)
        [((NSNotificationCenterLayout *)self)->lock unlock];
    return count;
}

- (unsigned int)suspensionBehaviorName:(NSString *)aName object:(id)anObject literally:(BOOL)literally
{
    unsigned int behavior = 0;

    [self applyCallBack:NSNotificationCenterSuspensionCallback context:&behavior
                   name:aName object:anObject literally:literally];
    return behavior;
}

- (void)_bundleLoaded
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;
    NSNotificationObserver *registry = (NSNotificationObserver *)layout->registry;
    unsigned int index;

    if (layout->registryCount == 0)
        return;
    if (layout->lock != nil)
        [layout->lock lock];
    for (index = 0; index < layout->registryCount; index++) {
        IMP callback = _NSIMPForObjectAndSelector(registry[index].observer,
                                                   registry[index].selector);
        registry[index].callback = (callback != (IMP)0) ? callback : (IMP)objc_msgSend;
    }
    if (layout->lock != nil)
        [layout->lock unlock];
}

- (void)_taskNowMultiThreaded
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;

    if (layout->lock == nil)
#if defined(__ppc__) || defined(__POWERPC__)
        layout->lock = [[NSCondition allocWithZone:0] init];
#else
        layout->lock = [[NSLock allocWithZone:0] init];
#endif
}

- (void)_taskNowSingleThreaded
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;

    if (layout->lock != nil) {
        [layout->lock release];
        layout->lock = nil;
    }
}

- (id)init
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;

    layout->registry = nil;
    layout->registryCount = 0;
    layout->registrySize = 0;
    layout->niltable = nil;
    layout->niltableCount = 0;
    layout->niltableSize = 0;
    layout->hashtable = nil;
    layout->hashtableSize = 0;
    layout->hashtableMask = 0;
    layout->deletedCount = 0;
    if ([NSThread isMultiThreaded])
        [self _taskNowMultiThreaded];
    if (NSNotificationCenterDefault != nil) {
        [NSNotificationCenterDefault addObserver:self selector:@selector(_taskNowMultiThreaded)
                                             name:NSWillBecomeMultiThreadedNotification object:nil];
        [NSNotificationCenterDefault addObserver:self selector:@selector(_taskNowSingleThreaded)
                                             name:NSDidBecomeSingleThreadedNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;

    if (NSNotificationCenterDefault == self)
        return;
    if (NSNotificationCenterDefault != nil) {
        [NSNotificationCenterDefault removeObserver:self name:NSWillBecomeMultiThreadedNotification object:nil];
        [NSNotificationCenterDefault removeObserver:self name:NSDidBecomeSingleThreadedNotification object:nil];
    }
    if (layout->registry != nil)
        NSZoneFree(0, layout->registry);
    layout->registry = nil;
    if (layout->niltable != nil)
        NSZoneFree(0, layout->niltable);
    if (layout->hashtable != nil)
        NSZoneFree(0, layout->hashtable);
    [layout->lock release];
    [super dealloc];
}

- (NSString *)description
{
    NSNotificationCenterLayout *layout = (NSNotificationCenterLayout *)self;
    unsigned int count;
    unsigned int capacity;
    unsigned int size;
    unsigned int index;
    NSNotificationObserver *entries;
    NSMutableString *result;

    if (layout->lock != nil)
        [layout->lock lock];
    count = layout->registryCount;
    capacity = layout->registrySize;
    size = 28 * capacity;
    entries = (NSNotificationObserver *)NSZoneMalloc(0, count * sizeof(NSNotificationObserver));
    memmove(entries, layout->registry, count * sizeof(NSNotificationObserver));
    if (layout->lock != nil)
        [layout->lock unlock];

#if defined(__ppc__) || defined(__POWERPC__)
    result = [[[NSMutableString allocWithZone:0] initWithCapacity:160 * count] autorelease];
#else
    result = [[[NSMutableString allocWithZone:0] initWithCapacity:160 * capacity] autorelease];
#endif
    [result appendFormat:@"%@ %x {count = %u; max = %u; size = %u; table = (\n",
                        isa, self, count, capacity, size];
    for (index = 0; index < count; index++) {
        id object = entries[index].object;
        id observer = entries[index].observer;
        const char *objectClass = (object != nil)
            ? ((struct objc_object *)object)->isa->name : "nil";
        id observerClass = (observer != nil)
            ? ((struct objc_object *)observer)->isa : nil;
        const char *selectorName = (entries[index].selector != 0)
            ? sel_getName(entries[index].selector) : "nil";

        [result appendFormat:@"\t{name = %@; object = %s<%x>; observer = %@<%x>; SEL = %s;}\n",
                            entries[index].name, objectClass, object,
                            observerClass, observer, selectorName];
    }
    [result appendString:@")}"];
    if (entries != nil)
        NSZoneFree(0, entries);
    return result;
}

@end
