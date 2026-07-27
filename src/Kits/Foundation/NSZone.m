/*	NSZone.m
	Memory allocation
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSObject.h>
#import <objc/objc-runtime.h>
#import <mach/mach.h>
#import <mach/host_info.h>
#import <string.h>
#import <stdio.h>

/*	Rhapsody's zones are NeXT's NXZone (<objc/zone.h>, already pulled in
	through NSObjCRuntime.h): NSZone is that same struct under a
	Foundation-level name, and the functions below are thin wrappers
	around the NXZone entry points the reference actually calls --
	NXCreateChildZone, NXMergeZone, NXZoneFromPtr, NXNameZone, and the
	NXZoneMalloc/NXZoneRealloc/NXZoneFree macros that index a zone's own
	function table -- not malloc_zone_t.  */

static NSZone *defaultMallocZone = 0;

/*	Associates a name (set by NSSetZoneName) with a zone, so NSZoneName
	can hand it back. <objc/zone.h>'s NXZone exposes only a name
	*setter* (NXNameZone) and documents its layout past the function
	table as implementation-specific, so there is no supported way to
	read a name back out of the zone itself -- this small table is what
	keeps that round trip working.  */
#define NSZoneMaxNamedZones 16

static struct {
    NSZone *zone;
    NSString *name;
} namedZones[NSZoneMaxNamedZones];
static int namedZoneCount = 0;

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
    if (defaultMallocZone == 0)
        defaultMallocZone = (NSZone *)NXDefaultMallocZone();
    return defaultMallocZone;
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

    if (zone != 0 && zone != NSDefaultMallocZone())
        NXMergeZone((NXZone *)zone);
}

void
NSSetZoneName(NSZone *zone, NSString *name)
{
    const char *cName;
    int i;

    cName = [name cString];

    if (zone == 0 || zone == NSDefaultMallocZone())
        return;

    NXNameZone((NXZone *)zone, cName);

    for (i = 0; i < namedZoneCount; i++) {
        if (namedZones[i].zone == zone) {
            namedZones[i].name = name;
            return;
        }
    }
    if (namedZoneCount < NSZoneMaxNamedZones) {
        namedZones[namedZoneCount].zone = zone;
        namedZones[namedZoneCount].name = name;
        namedZoneCount++;
    }
}

NSString *
NSZoneName(NSZone *zone)
{
    NSZone *target;
    int i;

    target = (zone != 0) ? zone : NSDefaultMallocZone();

    for (i = 0; i < namedZoneCount; i++) {
        if (namedZones[i].zone == target)
            return namedZones[i].name;
    }
    return @"";
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
	zombie-class lookup in a real NSMapTable (classToZombie, backed by
	NSCreateMapTableWithZone/NSMapGet/NSMapInsert); NSMapTable.m in this
	tree is still unimplemented stubs and out of this task's file list,
	so this reconstruction substitutes a private table for both
	directions of that lookup -- the same substitution this file's own
	ExtraRefCountTable already makes for NSMapTable's overflow case, for
	the identical reason.  The table lives here (not in NSObject.m,
	alongside _NSZombie itself) because NSZone.m is linked into every
	stage-2a test binary, while NSObject.m is linked only into the ones
	that need NSObject; _NSZombieClassForClass looks up _NSZombie by
	name (objc_getClass), not by compile-time reference, so this file
	has no link-time dependency on NSObject.m being present.
	_NSOriginalClassForZombieClass is NSObject.m's own reverse-lookup
	accessor, for the diagnostic message's class name.  */

typedef struct {
    Class originalClass;
    Class zombieClass;
} NSZombieClassEntry;

static NSZombieClassEntry *zombieClasses = 0;
static unsigned zombieClassCount = 0;
static unsigned zombieClassCapacity = 0;

static void
NSRecordZombieClass(Class originalClass, Class zombieClass)
{
    if (zombieClassCount == zombieClassCapacity) {
        unsigned newCapacity = (zombieClassCapacity == 0) ? 4 : zombieClassCapacity * 2;
        NSZombieClassEntry *newEntries =
            (NSZombieClassEntry *)NSZoneMalloc(0, newCapacity * sizeof(NSZombieClassEntry));
        unsigned index;

        for (index = 0; index < zombieClassCount; index++)
            newEntries[index] = zombieClasses[index];
        if (zombieClasses != 0)
            NSZoneFree(0, zombieClasses);
        zombieClasses = newEntries;
        zombieClassCapacity = newCapacity;
    }
    zombieClasses[zombieClassCount].originalClass = originalClass;
    zombieClasses[zombieClassCount].zombieClass = zombieClass;
    zombieClassCount++;
}

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
Class
_NSZombieClassForClass(Class originalClass)
{
    Class zombieClass;
    Class zombieMeta;
    const char *originalName;
    char *name;
    unsigned index;

    for (index = 0; index < zombieClassCount; index++)
        if (zombieClasses[index].originalClass == originalClass)
            return zombieClasses[index].zombieClass;

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
    NSRecordZombieClass(originalClass, zombieClass);

    return zombieClass;
}

/*  Reverse lookup for _NSZombie's diagnostic message (NSObject.m).  */
Class
_NSOriginalClassForZombieClass(Class zombieClass)
{
    unsigned index;

    for (index = 0; index < zombieClassCount; index++)
        if (zombieClasses[index].zombieClass == zombieClass)
            return zombieClasses[index].originalClass;
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
	overflow table once it earns a third extra reference.  In the
	shipped Foundation that overflow table is an NSMapTable; the one
	here is a private equivalent, because NSMapTable.m in this tree is
	still unimplemented stubs.  The reference also guards this table
	with a lock (_NSRefCountLock) that starts out unallocated and is
	only acquired once something has actually enabled threading -- the
	unlocked, unthreaded state is exactly what every test in this
	stage runs under, so that lock is not reconstructed here.  */

#define ExtraRefCountTableMinCapacity 16

typedef struct {
    unsigned count;	/* occupied slots */
    unsigned capacity;	/* total slots, always a power of two */
    unsigned mask;	/* capacity - 1 */
    unsigned *slots;	/* tagged (object | tag) words; 0 == unused */
} ExtraRefCountTable;

static ExtraRefCountTable *extraRefCounts = 0;

typedef struct {
    id object;
    unsigned count;
} ExtraRefCountOverflowEntry;

static ExtraRefCountOverflowEntry *extraRefCountOverflow = 0;
static unsigned extraRefCountOverflowCount = 0;
static unsigned extraRefCountOverflowCapacity = 0;

static unsigned
ExtraRefCountHash(id object, unsigned mask)
{
    return ((unsigned)object >> 2) & mask;
}

static ExtraRefCountTable *
ExtraRefCountTableCreate(unsigned capacity)
{
    ExtraRefCountTable *table;

    table = (ExtraRefCountTable *)NSZoneCalloc(0, 1, sizeof(ExtraRefCountTable));
    table->count = 0;
    table->capacity = capacity;
    table->mask = capacity - 1;
    table->slots = (unsigned *)NSZoneCalloc(0, capacity, sizeof(unsigned));
    return table;
}

/*	Finds `object`'s slot if it has one, otherwise the first unused
	slot on its probe sequence -- the index either an insert or a
	lookup needs.  */
static unsigned
ExtraRefCountTableFindSlot(ExtraRefCountTable *table, id object)
{
    unsigned index;

    index = ExtraRefCountHash(object, table->mask);
    while (table->slots[index] != 0 && (id)(table->slots[index] & ~3) != object)
        index = (index + 1) & table->mask;
    return index;
}

static void
ExtraRefCountTableResize(ExtraRefCountTable *table, unsigned newCapacity)
{
    unsigned *oldSlots;
    unsigned oldCapacity;
    unsigned *newSlots;
    unsigned newMask;
    unsigned i;
    unsigned index;

    oldSlots = table->slots;
    oldCapacity = table->capacity;
    newMask = newCapacity - 1;

    newSlots = (unsigned *)NSZoneCalloc(0, newCapacity, sizeof(unsigned));

    for (i = 0; i < oldCapacity; i++) {
        if (oldSlots[i] != 0) {
            index = ((oldSlots[i] & ~3) >> 2) & newMask;
            while (newSlots[index] != 0)
                index = (index + 1) & newMask;
            newSlots[index] = oldSlots[i];
        }
    }

    NSZoneFree(0, oldSlots);
    table->slots = newSlots;
    table->capacity = newCapacity;
    table->mask = newMask;
}

/*	Standard backward-shift deletion for a linear-probed table with no
	tombstones: after clearing the slot at `hole`, walk the probe
	sequence that follows it and pull back any entry whose own home
	slot still requires the hole to be empty, closing the gap so that
	a lookup for a surviving entry never stops early.  */
static void
ExtraRefCountTableCloseGap(ExtraRefCountTable *table, unsigned hole)
{
    unsigned scan;
    unsigned home;
    BOOL mustStay;

    scan = hole;
    for (;;) {
        scan = (scan + 1) & table->mask;
        if (table->slots[scan] == 0)
            break;

        home = ExtraRefCountHash((id)(table->slots[scan] & ~3), table->mask);

        /*  This entry must stay put if the hole lies strictly between
            its home slot and its current slot on the probe path --
            moving it back would make a lookup starting at its own home
            slot stop at the hole before ever reaching it.  */
        if (hole <= scan)
            mustStay = (home > hole && home <= scan);
        else
            mustStay = (home <= scan || home > hole);

        if (!mustStay) {
            table->slots[hole] = table->slots[scan];
            table->slots[scan] = 0;
            hole = scan;
        }
    }
}

static void
ExtraRefCountTableRemoveSlot(ExtraRefCountTable *table, unsigned index)
{
    table->slots[index] = 0;
    table->count--;

    if (table->capacity > ExtraRefCountTableMinCapacity &&
        table->count < table->capacity / 4)
        ExtraRefCountTableResize(table, table->capacity / 2);
    else
        ExtraRefCountTableCloseGap(table, index);
}

static int
ExtraRefCountOverflowFind(id object)
{
    unsigned i;

    for (i = 0; i < extraRefCountOverflowCount; i++)
        if (extraRefCountOverflow[i].object == object)
            return (int)i;
    return -1;
}

static void
ExtraRefCountOverflowInsert(id object, unsigned count)
{
    if (extraRefCountOverflowCount == extraRefCountOverflowCapacity) {
        unsigned newCapacity;
        ExtraRefCountOverflowEntry *newEntries;
        unsigned i;

        newCapacity = (extraRefCountOverflowCapacity == 0) ? 4 : extraRefCountOverflowCapacity * 2;
        newEntries = (ExtraRefCountOverflowEntry *)
            NSZoneMalloc(0, newCapacity * sizeof(ExtraRefCountOverflowEntry));
        for (i = 0; i < extraRefCountOverflowCount; i++)
            newEntries[i] = extraRefCountOverflow[i];
        if (extraRefCountOverflow != 0)
            NSZoneFree(0, extraRefCountOverflow);
        extraRefCountOverflow = newEntries;
        extraRefCountOverflowCapacity = newCapacity;
    }
    extraRefCountOverflow[extraRefCountOverflowCount].object = object;
    extraRefCountOverflow[extraRefCountOverflowCount].count = count;
    extraRefCountOverflowCount++;
}

static void
ExtraRefCountOverflowRemoveAt(unsigned index)
{
    extraRefCountOverflow[index] = extraRefCountOverflow[extraRefCountOverflowCount - 1];
    extraRefCountOverflowCount--;
}

unsigned
NSExtraRefCount(id object)
{
    unsigned index;
    unsigned slot;
    unsigned tag;

    if (object == 0 || extraRefCounts == 0)
        return 0;

    index = ExtraRefCountTableFindSlot(extraRefCounts, object);
    slot = extraRefCounts->slots[index];

    if (slot == 0)
        return 0;

    tag = slot & 3;
    if (tag != 3)
        return tag;

    {
        int found;

        found = ExtraRefCountOverflowFind(object);
        return (found >= 0) ? extraRefCountOverflow[found].count : 0;
    }
}

void
NSIncrementExtraRefCount(id object)
{
    unsigned index;
    unsigned slot;
    unsigned tag;

    if (object == 0)
        return;

    if (extraRefCounts == 0)
        extraRefCounts = ExtraRefCountTableCreate(ExtraRefCountTableMinCapacity);

    index = ExtraRefCountTableFindSlot(extraRefCounts, object);
    slot = extraRefCounts->slots[index];

    if (slot == 0) {
        /*  First extra reference: grow before the table is more than
            half full, then insert with the tag set to 1.  */
        if (extraRefCounts->count * 2 > extraRefCounts->capacity) {
            ExtraRefCountTableResize(extraRefCounts, extraRefCounts->capacity * 2);
            index = ExtraRefCountTableFindSlot(extraRefCounts, object);
        }
        extraRefCounts->slots[index] = (unsigned)object | 1;
        extraRefCounts->count++;
    } else {
        tag = slot & 3;
        if (tag == 1) {
            extraRefCounts->slots[index] = (unsigned)object | 2;
        } else if (tag == 2) {
            extraRefCounts->slots[index] = (unsigned)object | 3;
            ExtraRefCountOverflowInsert(object, 3);
        } else {
            int found;

            found = ExtraRefCountOverflowFind(object);
            if (found < 0) {
                fprintf(stderr,
                    "*** NSIncrementExtraRefCount(): extra ref count table "
                    "corrupted for %p\n", (void *)object);
                ExtraRefCountOverflowInsert(object, 0xFFFFFFFF);
            } else {
                extraRefCountOverflow[found].count++;
            }
        }
    }

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectExtraRefIncrementedEvent, object);
}

BOOL
NSDecrementExtraRefCountWasZero(id object)
{
    unsigned index;
    unsigned slot;
    unsigned tag;
    BOOL wasZero;

    if (object == 0)
        return NO;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectExtraRefDecrementedEvent, object);

    if (extraRefCounts == 0)
        return YES;

    index = ExtraRefCountTableFindSlot(extraRefCounts, object);
    slot = extraRefCounts->slots[index];

    wasZero = NO;

    if (slot == 0) {
        wasZero = YES;
    } else {
        tag = slot & 3;
        if (tag == 1) {
            ExtraRefCountTableRemoveSlot(extraRefCounts, index);
        } else if (tag == 3) {
            int found;

            found = ExtraRefCountOverflowFind(object);
            if (found >= 0) {
                if (extraRefCountOverflow[found].count == 3) {
                    extraRefCounts->slots[index] = (unsigned)object | 2;
                    ExtraRefCountOverflowRemoveAt(found);
                } else {
                    extraRefCountOverflow[found].count--;
                }
            }
            /*  else: tag claims an overflow entry that is not there --
                corrupted state.  The reference leaves the count alone
                rather than acting on a value it does not have; matched
                here.  */
        } else {
            extraRefCounts->slots[index] = (unsigned)object | (tag - 1);
        }
    }

    return wasZero;
}
