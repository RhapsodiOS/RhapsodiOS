/*	NSZone.m
	Memory allocation
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDebug.h>
#import <mach/mach.h>
#import <mach/host_info.h>
#import <string.h>

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
