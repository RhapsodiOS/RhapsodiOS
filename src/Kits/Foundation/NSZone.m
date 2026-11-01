/*	NSZone.m
	Memory allocation
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSMapTable.h>
#import <objc/objc-runtime.h>
#import <mach/mach.h>
#import <mach/host_info.h>
#import <mach/cthreads.h>
#import <string.h>
#import <stdio.h>

extern NSString *__NSEmptyString;
extern int _NSsnprintf(char *buffer, size_t size, char *format, ...);

#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSExternRefCountLock;
extern int _NSIsMultiThreaded;

static void NSExternRefCountLockAcquire(void)
{
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
            : "r" (&__NSExternRefCountLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return;
        cthread_yield();
    }
}

static void NSExternRefCountLockRelease(void)
{
    __asm__ volatile("sync" ::: "memory");
    __NSExternRefCountLock = 0;
}
#else
extern mutex_t __NSRefCountLock;
#endif

static BOOL NSLockExtraRefCountTable(void)
{
#if defined(__ppc__) || defined(__POWERPC__)
    if (!_NSIsMultiThreaded)
        return NO;
    NSExternRefCountLockAcquire();
    return YES;
#else
    if (__NSRefCountLock == 0)
        return NO;
    if (mutex_try_lock(__NSRefCountLock) == 0)
        mutex_wait_lock(__NSRefCountLock);
    return YES;
#endif
}

static void NSUnlockExtraRefCountTable(BOOL locked)
{
    if (!locked)
        return;
#if defined(__ppc__) || defined(__POWERPC__)
    NSExternRefCountLockRelease();
#else
    *(unsigned *)__NSRefCountLock = 0;
#endif
}

/*	Rhapsody's zones are NeXT's NXZone (<objc/zone.h>, already pulled in
	through NSObjCRuntime.h): NSZone is that same struct under a
	Foundation-level name, and the functions below are thin wrappers
	around the NXZone entry points the reference actually calls --
	NXCreateChildZone, NXMergeZone, NXZoneFromPtr, NXNameZone, and the
	NXZoneMalloc/NXZoneRealloc/NXZoneFree macros that index a zone's own
	function table -- not malloc_zone_t.  */

__private_extern__ NSZone *__NSDefaultMallocZone;

/*	The 32-bit zone_t layout in malloc.c embeds NXZone, then its free-array
	metadata, granularity, parent zone, and name pointer at byte offset 36.
	Both target NSZoneName implementations read this private field directly.  */
typedef struct {
    NXZone functions;
    void *freeArray;
    int freeCount;
    int freeMaximum;
    int granularity;
    NSZone *parentZone;
    char *name;
} NSZoneNameLayout;

/*	log2 of a power-of-two value, for NSLogPageSize.  */
static int
Log2(unsigned value)
{
    int result;

    result = 0;
    while (value > 1) {
        value >>= 1;
        result++;
    }
    return result;
}

/*	Zone creation and identity		*/

NSZone *
NSDefaultMallocZone(void)
{
    return __NSDefaultMallocZone;
}

NSZone *
NSCreateZone(unsigned startSize, unsigned granularity, BOOL canFree)
{
    NSZone *zone;

    if (startSize == 0)
        startSize = NSPageSize();
    if (granularity == 0)
        granularity = NSPageSize();

    zone = (NSZone *)NXCreateChildZone((NXZone *)NSDefaultMallocZone(),
                                        startSize, granularity, canFree);

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSZoneCreatedEvent, zone, startSize, granularity, canFree);

    return zone;
}

void
NSRecycleZone(NSZone *zone)
{
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSZoneRecycledEvent, zone, 0, 0, 0);

    if (zone != 0 && zone != NSDefaultMallocZone()) {
        NXMergeZone((NXZone *)zone);
    }
}

void
NSSetZoneName(NSZone *zone, NSString *name)
{
    const char *cName = [name lossyCString];

    if (zone == 0 || zone == NSDefaultMallocZone())
        return;

    NXNameZone((NXZone *)zone, cName);
}

NSString *
NSZoneName(NSZone *zone)
{
    NSZoneNameLayout *target =
        (NSZoneNameLayout *)((zone != 0) ? zone : NSDefaultMallocZone());

    if (target->name != 0)
        return [NSString stringWithCString:target->name];
    return __NSEmptyString;
}

NSZone *
NSZoneFromPointer(void *ptr)
{
    return (NSZone *)NXZoneFromPtr(ptr);
}

/*	Allocation within a zone		*/

void *
NSZoneMalloc(NSZone *zone, unsigned size)
{
    void *ptr;

    if (zone == 0)
        zone = NSDefaultMallocZone();

    ptr = NXZoneMalloc((NXZone *)zone, size);

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSZoneMallocEvent, ptr, zone, size, 0);

    return ptr;
}

/*	The reference does not call the public NXZoneCalloc() (which the
	header documents as "calls NXZoneMalloc and then bzero") -- it
	mallocs and clears the memory itself, matched here.  */
void *
NSZoneCalloc(NSZone *zone, unsigned numElems, unsigned byteSize)
{
    void *ptr;
    unsigned size;

    if (zone == 0)
        zone = NSDefaultMallocZone();

    size = numElems * byteSize;
    ptr = NXZoneMalloc((NXZone *)zone, size);
    if (ptr != 0)
        memset(ptr, 0, size);

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSZoneCallocEvent, ptr, zone, size, 0);

    return ptr;
}

void *
NSZoneRealloc(NSZone *zone, void *ptr, unsigned size)
{
    void *newPtr;

    if (zone == 0)
        zone = NSDefaultMallocZone();

    newPtr = NXZoneRealloc((NXZone *)zone, ptr, size);

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSZoneReallocEvent, ptr, zone, size, newPtr);

    return newPtr;
}

void
NSZoneFree(NSZone *zone, void *ptr)
{
    if (zone == 0)
        zone = NSDefaultMallocZone();

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSZoneFreeEvent, ptr, 0, 0, 0);

    NXZoneFree((NXZone *)zone, ptr);
}

void
_NSGenericFree(void *ptr)
{
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSZoneFreeEvent, ptr, 0, 0, 0);
    free(ptr);
}

/*	Pages		*/

unsigned
NSPageSize(void)
{
    return vm_page_size;
}

unsigned
NSLogPageSize(void)
{
    static int cachedLogPageSize = 0;

    if (cachedLogPageSize == 0)
        cachedLogPageSize = Log2(vm_page_size);
    return cachedLogPageSize;
}

unsigned
NSRoundUpToMultipleOfPageSize(unsigned bytes)
{
    return (bytes + vm_page_size - 1) & ~(vm_page_size - 1);
}

unsigned
NSRoundDownToMultipleOfPageSize(unsigned bytes)
{
    return bytes & ~(vm_page_size - 1);
}

void *
NSAllocateMemoryPages(unsigned bytes)
{
    vm_address_t address;
    kern_return_t result;

    result = vm_allocate(task_self(), &address, bytes, 1);
    if (result != KERN_SUCCESS)
        [NSException raise:NSInvalidArgumentException
                     format:@"*** NSAllocateMemoryPages(%d) failed", bytes];

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSVMAllocateEvent, (void *)address, bytes);

    return (void *)address;
}

void
NSDeallocateMemoryPages(void *ptr, unsigned bytes)
{
    kern_return_t result;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSVMDeallocateEvent, ptr, bytes);

    result = vm_deallocate(task_self(), (vm_address_t)ptr, bytes);
    if (result != KERN_SUCCESS)
        [NSException raise:NSInvalidArgumentException
                     format:@"*** NSDeallocateMemoryPages(0x%x, %d) failed", ptr, bytes];
}

void
NSCopyMemoryPages(const void *source, void *dest, unsigned bytes)
{
    kern_return_t result;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSVMCopyEvent, source, bytes, dest);

    result = vm_copy(task_self(), (vm_address_t)source, bytes, (vm_address_t)dest);
    if (result != KERN_SUCCESS)
        [NSException raise:NSInvalidArgumentException
                     format:@"*** NSCopyMemoryPages(0x%x, 0x%x, %d) failed", source, dest, bytes];
}

unsigned
NSRealMemoryAvailable(void)
{
    static unsigned cachedRealMemory = 0;
    host_basic_info_data_t info;
    unsigned count;

    if (cachedRealMemory == 0) {
        count = HOST_BASIC_INFO_COUNT;
        if (host_info(host_self(), HOST_BASIC_INFO, (host_info_t)&info, &count) == KERN_SUCCESS)
            cachedRealMemory = info.memory_size;
    }
    return cachedRealMemory;
}

/*	Object allocation, copying and deallocation		*/

/*	The reference allocates, copies and disposes of objects through
	the same swappable runtime hooks the Objective-C runtime itself
	uses for +alloc/+copy/-dealloc (objc-1/objc-globaldata.m's
	_zoneAlloc, _zoneCopy and _dealloc, declared in
	<objc/objc-runtime.h>) rather than anything Foundation-specific --
	so a class that overrides its own allocation still goes through
	the zone the caller asked for.  */

id
NSAllocateObject(Class aClass, unsigned extraBytes, NSZone *zone)
{
    id newObject;

    if (zone == 0)
        zone = NSDefaultMallocZone();

    newObject = (*_zoneAlloc)(aClass, extraBytes, (NXZone *)zone);

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectAllocatedEvent, newObject, extraBytes);

    return newObject;
}

/*	NSZombieEnabled and NSDeallocateZombies (both read directly as
	globals, matching NSKeepAllocationStatistics above -- the
	environment-variable bootstrap that sets them from the process's
	environment is NSDebug.h territory this stage doesn't reconstruct)
	retarget a deallocated object's isa to a synthesized zombie class
	instead of freeing it, so a message sent to it afterward is caught
	and logged instead of touching memory that may have been reused.

	The reference (_NSDeallocateObject, disassembled directly since it
	is within this stage's analysis scope) keeps the original-class ->
	zombie-class lookup in an NSMapTable (classToZombie, backed by
	NSCreateMapTableWithZone/NSMapGet/NSMapInsert).  The lookup lives here
	(not in NSObject.m, alongside _NSZombie itself) because NSZone.m is
	linked into every
	stage-2a test binary, while NSObject.m is linked only into the ones
	that need NSObject; _NSZombieClassForClass looks up _NSZombie by
	name (objc_getClass), not by compile-time reference, so this file
	has no link-time dependency on NSObject.m being present.  NSObject.m's
	zombie diagnostic also needs the original class.  Its
	NSZombieOriginalClassForClass helper walks this table in reverse,
	matching the reference's _findOriginalClass helper.  */

static NSMapTable *classToZombie;

/*  Finds (or synthesizes and caches) the zombie class standing in for
    originalClass.  The reference builds the pair by memmove()-cloning
    _NSZombie's own class and metaclass structs (each sizeof(struct
    objc_class), matching this project's objc-class.h layout exactly) --
    giving the clone the same method lists as _NSZombie itself -- then
    gives the metaclass clone its own empty method cache (a fresh, zeroed
    sizeof(struct objc_cache) block; sharing _NSZombie's own cache would
    let a lookup on one pollute the other), sets a new
    "NSZombie_<originalClass>" name shared by both, and registers the
    result with objc_addClass.  */
static Class
_NSZombieClassForClass(Class originalClass)
{
    Class zombieClass;
    Class zombieMeta;
    const char *originalName;
    char *name;

    zombieClass = classToZombie != 0
        ? (Class)NSMapGet(classToZombie, originalClass) : Nil;
    if (zombieClass != Nil)
        return zombieClass;

    zombieClass = (Class)NSZoneMalloc(0, sizeof(struct objc_class));
    memmove(zombieClass, objc_getClass("_NSZombie"), sizeof(struct objc_class));

    zombieMeta = (Class)NSZoneMalloc(0, sizeof(struct objc_class));
    memmove(zombieMeta, zombieClass->isa, sizeof(struct objc_class));
    zombieMeta->cache = (struct objc_cache *)NSZoneMalloc(0, sizeof(struct objc_cache));
    memset(zombieMeta->cache, 0, sizeof(struct objc_cache));
    zombieClass->isa = zombieMeta;

    originalName = originalClass->name;
    name = (char *)NSZoneMalloc(0, strlen("NSZombie_") + strlen(originalName) + 1);
    strcpy(name, "NSZombie_");
    strcat(name, originalName);
    zombieMeta->name = name;
    zombieClass->name = name;

    objc_addClass(zombieClass);
    if (classToZombie == 0) {
        NSMapTableValueCallBacks valueCallBacks;

        memset(&valueCallBacks, 0, sizeof(valueCallBacks));
        classToZombie = NSCreateMapTableWithZone(
            NSNonOwnedPointerMapKeyCallBacks, valueCallBacks, 1, 0);
    }
    NSMapInsert(classToZombie, originalClass, zombieClass);

    return zombieClass;
}

__private_extern__ Class
NSZombieOriginalClassForClass(Class zombieClass)
{
    NSMapEnumerator enumerator;
    void *key;
    void *value;

    enumerator = NSEnumerateMapTable(classToZombie);
    while (NSNextMapEnumeratorPair(&enumerator, &key, &value)) {
        if (value == zombieClass)
            return (Class)key;
    }
    return Nil;
}

void
NSDeallocateObject(id object)
{
    if (object == 0)
        return;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectDeallocatedEvent, object);

    if (NSZombieEnabled) {
        Class zombieClass = _NSZombieClassForClass(object->isa);

        if (NSDeallocateZombies)
            (*_dealloc)((Object *)object);
        else
            object->isa = zombieClass;
        return;
    }

    (*_dealloc)((Object *)object);
}

id
NSCopyObject(id object, unsigned extraBytes, NSZone *zone)
{
    id newObject;

    if (object == 0)
        return 0;

    if (zone == 0)
        zone = NSDefaultMallocZone();

    newObject = (*_zoneCopy)((Object *)object, extraBytes, (NXZone *)zone);

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectCopiedEvent, object, extraBytes, newObject);

    return newObject;
}

BOOL
NSShouldRetainWithZone(id anObject, NSZone *requestedZone)
{
    if (requestedZone == 0 || requestedZone == NSDefaultMallocZone())
        return YES;
    return (NSZoneFromPointer(anObject) == requestedZone);
}

/*	Extra reference counts		*/

/*	An object's own reference is implicit and is never counted here --
	a freshly allocated object has an *extra* reference count of 0.
	The reference keeps that count in a side table outside the object
	rather than in the object itself, keyed by identity.  Because a
	heap object is always word-aligned, the low two bits of a table
	entry (always zero on a bare pointer) are free to carry a tag:

		0			slot unused
		object | 1		one extra reference
		object | 2		two extra references
		object | 3		three or more -- the real count is
					in the overflow table below, keyed
					by object

	so the overwhelmingly common case (0, 1 or 2 extra references)
	never needs a second lookup, and an object is only promoted to the
	overflow table once it earns a third extra reference.  The shipped
	Foundation uses an NSMapTable for overflow counts, as this source now
	does.  The compact table starts at 256 entries and uses the reference's
	growth, shrink, and cluster-rehash rules.  The
	three exported accessors synchronize the tables when threading is
	enabled: PPC uses __NSExternRefCountLock as a spin word, while i386
	uses the mutex pointer __NSRefCountLock allocated by NSThread.  The
	debug printer remains outside the lock, matching the reference.  */

#define ExtraRefCountTableMinCapacity 256

typedef struct {
    unsigned count;
    unsigned capacity;
    unsigned mask;
    unsigned *slots;
} ExtraRefCountTable;

static ExtraRefCountTable *fewCounter = 0;
static NSMapTable *manyCounter = 0;

static unsigned
ExtraRefCountHash(id object, unsigned mask)
{
    return ((unsigned)object >> 2) & mask;
}

static ExtraRefCountTable *
ExtraRefCountTableCreate(void)
{
    ExtraRefCountTable *table;

    table = (ExtraRefCountTable *)NSZoneMalloc(0, sizeof(ExtraRefCountTable));
    table->count = 0;
    table->capacity = ExtraRefCountTableMinCapacity;
    table->mask = ExtraRefCountTableMinCapacity - 1;
    table->slots = (unsigned *)NSZoneMalloc(
        0, ExtraRefCountTableMinCapacity * sizeof(unsigned));
    memset(table->slots, 0,
           ExtraRefCountTableMinCapacity * sizeof(unsigned));
    return table;
}

/* Finds the existing slot for object, or the first empty slot on its probe
   sequence. The low two bits hold the extra-reference count tag. */
static unsigned
ExtraRefCountTableFindSlot(ExtraRefCountTable *table, id object)
{
    unsigned index = ExtraRefCountHash(object, table->mask);

    while (table->slots[index] != 0 &&
           (id)(table->slots[index] >> 2 << 2) != object)
        index = (index + 1) & table->mask;
    return index;
}

/* Resize and rehash the compact table. Return NO when a shrink request reaches
   the reference's 256-slot floor. */
static BOOL
ExtraRefCountTableResize(ExtraRefCountTable *table, BOOL grow)
{
    unsigned *oldSlots = table->slots;
    unsigned oldCapacity = table->capacity;
    unsigned index, rehashed = 0;

    if (grow) {
        table->capacity = oldCapacity * 2;
        table->mask = (table->mask * 2) | 1;
    } else {
        if (oldCapacity <= ExtraRefCountTableMinCapacity)
            return NO;
        table->capacity = oldCapacity / 2;
        table->mask >>= 1;
    }

    table->slots = (unsigned *)NSZoneMalloc(
        0, table->capacity * sizeof(unsigned));
    memset(table->slots, 0, table->capacity * sizeof(unsigned));
    for (index = 0; index < oldCapacity; index++) {
        unsigned value = oldSlots[index];
        if (value != 0) {
            unsigned destination = ExtraRefCountHash(
                (id)(value & ~3U), table->mask);
            while (table->slots[destination] != 0 &&
                   (table->slots[destination] >> 2) != (value >> 2))
                destination = (destination + 1) & table->mask;
            table->slots[destination] = value;
            rehashed++;
        }
    }
    if (rehashed != table->count)
        [NSException raise:NSInternalInconsistencyException
                    format:@"Extra reference count table is inconsistent"];
    NSZoneFree(0, oldSlots);
    return YES;
}

/* Reinsert the cluster following a removed slot so lookups cannot stop at the
   newly empty slot. */
static void
ExtraRefCountTableRehash(ExtraRefCountTable *table, unsigned removed)
{
    unsigned index = (removed + 1) & table->mask;

    while (table->slots[index] != 0) {
        unsigned value = table->slots[index];
        unsigned destination;

        table->slots[index] = 0;
        destination = ExtraRefCountTableFindSlot(
            table, (id)(value & ~3U));
        table->slots[destination] = value;
        index = (index + 1) & table->mask;
    }
}

static void
ExtraRefCountTableRemoveSlot(ExtraRefCountTable *table, unsigned index)
{
    table->slots[index] = 0;
    table->count--;
    if (table->count >= table->capacity / 4 ||
        !ExtraRefCountTableResize(table, NO))
        ExtraRefCountTableRehash(table, index);
}

unsigned
NSExtraRefCount(id object)
{
    unsigned index, slot, result;
    BOOL locked;

    if (object == 0 || fewCounter == 0)
        return 0;

    locked = NSLockExtraRefCountTable();
    index = ExtraRefCountTableFindSlot(fewCounter, object);
    slot = fewCounter->slots[index];
    if (slot == 0) {
        result = 0;
    } else if ((slot & 3) == 3) {
        result = (unsigned)(unsigned long)NSMapGet(
            manyCounter, (const void *)((unsigned long)object + 1));
    } else {
        result = slot & 3;
    }
    NSUnlockExtraRefCountTable(locked);
    return result;
}

void
NSIncrementExtraRefCount(id object)
{
    unsigned index, slot;
    BOOL locked;

    if (object == 0)
        return;

    if (fewCounter == 0) {
        fewCounter = ExtraRefCountTableCreate();
        manyCounter = NSCreateMapTableWithZone(
            NSNonOwnedPointerMapKeyCallBacks, NSIntMapValueCallBacks, 42, 0);
    }

    locked = NSLockExtraRefCountTable();
    index = ExtraRefCountTableFindSlot(fewCounter, object);
    slot = fewCounter->slots[index];
    if (slot != 0) {
        switch (slot & 3) {
        case 1:
            fewCounter->slots[index] = (unsigned)object | 2;
            break;
        case 2:
            fewCounter->slots[index] = (unsigned)object | 3;
            NSMapInsertKnownAbsent(
                manyCounter, (const void *)((unsigned long)object + 1),
                (const void *)3);
            break;
        default: {
            const void *key = (const void *)((unsigned long)object + 1);
            unsigned count = (unsigned)(unsigned long)NSMapGet(manyCounter,
                                                                key);
            if (count == UINT_MAX) {
                NSLog(@"*** Reference count overflow for '%@': probably implies a leak!",
                      object);
            } else {
                count++;
            }
            NSMapInsert(manyCounter, key, (const void *)(unsigned long)count);
            break;
        }
        }
    } else {
        if (fewCounter->capacity < 2 * fewCounter->count) {
            ExtraRefCountTableResize(fewCounter, YES);
            index = ExtraRefCountTableFindSlot(fewCounter, object);
        }
        fewCounter->slots[index] = (unsigned)object | 1;
        fewCounter->count++;
    }

    NSUnlockExtraRefCountTable(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectExtraRefIncrementedEvent, object);
}

BOOL
NSDecrementExtraRefCountWasZero(id object)
{
    unsigned index, slot;
    BOOL wasZero = NO;
    BOOL locked;

    if (object == 0)
        return NO;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectExtraRefDecrementedEvent, object);
    if (fewCounter == 0)
        return YES;

    locked = NSLockExtraRefCountTable();
    index = ExtraRefCountTableFindSlot(fewCounter, object);
    slot = fewCounter->slots[index];
    if (slot == 0) {
        wasZero = YES;
    } else {
        switch (slot & 3) {
        case 1:
            ExtraRefCountTableRemoveSlot(fewCounter, index);
            break;
        case 3: {
            const void *key = (const void *)((unsigned long)object + 1);
            void *count = NSMapGet(manyCounter, key);
            if (count == (void *)3) {
                fewCounter->slots[index] = (unsigned)object | 2;
                NSMapRemove(manyCounter, key);
            } else if (count != (void *)-1) {
                NSMapInsert(manyCounter, key,
                            (const void *)((unsigned long)count - 1));
            }
            break;
        }
        default:
            fewCounter->slots[index]--;
            break;
        }
    }
    NSUnlockExtraRefCountTable(locked);
    return wasZero;
}

void
_NSIncrementInternalRefCount(id object, unsigned *refCount, int mask, id lock)
{
    if (lock != 0)
        [lock lock];
    if ((*refCount & mask) == mask)
        NSIncrementExtraRefCount(object);
    else
        ++*refCount;
    if (lock != 0)
        [lock unlock];
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, object);
}

BOOL
_NSDecrementInternalRefCountWasZero(id object, unsigned *refCount, int mask, id lock)
{
    BOOL wasZero = NO;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, object);
    if (lock != 0)
        [lock lock];
    if ((*refCount & mask) != 0) {
        if ((*refCount & mask) != mask || NSDecrementExtraRefCountWasZero(object))
            --*refCount;
    } else {
        wasZero = YES;
    }
    if (lock != 0)
        [lock unlock];
    return wasZero;
}

unsigned
_NSInternalRefCount(id object, unsigned refCount, int mask)
{
    if ((refCount & mask) == mask)
        return NSExtraRefCount(object) + mask + 1;
    return (refCount & mask) + 1;
}

void
_NSPrintExtraRefCount(void)
{
    char *buffer;
    char *cursor;
    unsigned capacity, index;
    NSMapEnumerator enumerator;
    void *key;
    void *value;

    if (fewCounter == 0)
        return;

    capacity = fewCounter->count + NSCountMapTable(manyCounter);
    buffer = (char *)NSZoneMalloc(0, capacity << 8);
    cursor = buffer;
    buffer[0] = '\0';

    for (index = fewCounter->capacity; index != 0; ) {
        unsigned slot = fewCounter->slots[--index];
        id object;
        Class objectClass;
        int length;

        if (slot == 0)
            continue;
        object = (id)(slot & ~3U);
        objectClass = *(Class *)object;
        length = _NSsnprintf(cursor, 255,
                          "Object 0x%x of class %s: extra RefCount = %d\n",
                          (unsigned)object, objectClass->name, slot & 3);
        if (length < 0)
            continue;
        cursor += strlen(cursor);
    }

    enumerator = NSEnumerateMapTable(manyCounter);
    while (NSNextMapEnumeratorPair(&enumerator, &key, &value)) {
        id object = (id)((unsigned long)key - 1);
        Class objectClass = *(Class *)object;
        int length = _NSsnprintf(cursor, 255,
                              "Object 0x%x of class %s: extra RefCount = %d\n",
                              (unsigned)object, objectClass->name,
                              (unsigned long)value);

        if (length >= 0)
            cursor += strlen(cursor);
    }

    NSLog(@"Extra ref count statistics:\n%s", buffer);
    NSZoneFree(0, buffer);
}
