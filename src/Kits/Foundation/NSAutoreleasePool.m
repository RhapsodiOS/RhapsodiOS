/*	NSAutoreleasePool.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSThread.h>
#import <objc/objc-runtime.h>
#include <stddef.h>
#include <string.h>

extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern void _NSBasicStdErrLog(const char *format, ...);
extern BOOL NSKeepAllocationStatistics;
extern void NSRecordAllocationEvent(int eventType, ...);
extern unsigned NSAutoreleasePoolCount(void);
extern unsigned NSTopAutoreleasePoolCount(void);
extern unsigned NSAutoreleasePoolCountForObject(id anObject);
extern unsigned NSPushAutoreleasePool(void);
extern void NSPopAutoreleasePool(unsigned token);
extern void NSAutoreleaseObject(id anObject);

typedef struct NSAutoreleasePoolPage {
	struct NSAutoreleasePoolPage *next;
	struct NSAutoreleasePoolPage *previous;
	unsigned count;
} NSAutoreleasePoolPage;

typedef struct {
	unsigned pageCount;
	NSAutoreleasePoolPage *page;
	id pool;
} NSAutoreleasePoolCursor;

typedef struct {
	NSAutoreleasePoolPage *pageHead;
	unsigned objectCount;
	unsigned highWaterMark;
	unsigned highWaterResolution;
	unsigned char releaseEnabled;
	unsigned char freedObjectCheckEnabled;
	unsigned char handlingReleaseException;
	unsigned char routesToSubclass;
	NSAutoreleasePoolPage *freePageHead;
	id recycledPools[4];
	unsigned poolCapacity;
	unsigned poolDepth;
	NSAutoreleasePoolCursor records[1];
} NSAutoreleasePoolData;

typedef char NSAutoreleasePoolPageHeaderIs12Bytes[
	(sizeof(NSAutoreleasePoolPage) == 12) ? 1 : -1];
typedef char NSAutoreleasePoolCursorIs12Bytes[
	(sizeof(NSAutoreleasePoolCursor) == 12) ? 1 : -1];
typedef char NSAutoreleasePoolRecordsStartAt48[
	(offsetof(NSAutoreleasePoolData, records) == 48) ? 1 : -1];

static unsigned NSAutoreleasePoolPageSize;
static unsigned NSAutoreleasePoolDefaultHighWaterMark;
static unsigned NSAutoreleasePoolDefaultHighWaterResolution;
static BOOL NSAutoreleasePoolDefaultReleaseEnabled = YES;
static BOOL NSAutoreleasePoolDefaultFreedObjectCheckEnabled;
static unsigned NSTotalAutoreleasedObjectsCount;
static Class NSAutoreleasePoolClass;

static NSAutoreleasePoolCursor *
NSAutoreleasePoolRecords(NSAutoreleasePoolData *data)
{
	return (NSAutoreleasePoolCursor *)((char *)data + 48);
}

static NSAutoreleasePoolCursor *
NSAutoreleasePoolRecord(NSAutoreleasePoolData *data, unsigned index)
{
	return NSAutoreleasePoolRecords(data) + index;
}

static id *
NSAutoreleasePoolPageObjects(NSAutoreleasePoolPage *page)
{
	return (id *)((char *)page + 12);
}

/* NSThread's target-visible autoreleasePool ivar is at byte offset 24. */
static NSAutoreleasePoolData *
NSAutoreleasePoolDataForThread(NSThread *thread, BOOL create)
{
	NSAutoreleasePoolData **slot =
		(NSAutoreleasePoolData **)((char *)thread + 24);
	NSAutoreleasePoolData *data = *slot;

	if (data == 0 && create) {
		data = (NSAutoreleasePoolData *)NSZoneMalloc(0, 144);
		memset(data, 0, 144);
		data->highWaterMark = NSAutoreleasePoolDefaultHighWaterMark;
		data->highWaterResolution = NSAutoreleasePoolDefaultHighWaterResolution;
		data->releaseEnabled = NSAutoreleasePoolDefaultReleaseEnabled;
		data->freedObjectCheckEnabled =
			NSAutoreleasePoolDefaultFreedObjectCheckEnabled;
		data->poolCapacity = 8;
	}
	if (data != 0 && NSAutoreleasePoolPageSize == 0)
		NSAutoreleasePoolPageSize = NSPageSize();
	if (data != 0 && *slot == 0)
		*slot = data;
	return data;
}

static NSAutoreleasePoolData *
NSAutoreleasePoolGrowRecords(NSThread *thread, NSAutoreleasePoolData *data)
{
	unsigned oldCapacity = data->poolCapacity;
	unsigned newCapacity = oldCapacity * 2;
	unsigned oldSize = 48 + 12 * oldCapacity;
	unsigned newSize = 48 + 12 * newCapacity;
	NSAutoreleasePoolData **slot =
		(NSAutoreleasePoolData **)((char *)thread + 24);

	data->poolCapacity = newCapacity;
	data = (NSAutoreleasePoolData *)NSZoneRealloc(0, data, newSize);
	memset((char *)data + oldSize, 0, newSize - oldSize);
	*slot = data;
	return data;
}

static NSAutoreleasePoolPage *
NSAutoreleasePoolAddPage(NSAutoreleasePoolData *data)
{
	NSAutoreleasePoolPage *page;

	if (data->freePageHead != 0) {
		page = data->freePageHead;
		data->freePageHead = page->previous;
		if (data->freePageHead != 0)
			data->freePageHead->next = 0;
	} else {
		page = (NSAutoreleasePoolPage *)
			NSAllocateMemoryPages(NSAutoreleasePoolPageSize);
	}

	page->next = 0;
	page->previous = data->pageHead;
	page->count = 0;
	if (data->pageHead != 0)
		data->pageHead->next = page;
	data->pageHead = page;
	return page;
}

static unsigned
NSAutoreleasePoolRangeCount(NSAutoreleasePoolCursor start,
		NSAutoreleasePoolPage *endPage, unsigned endCount)
{
	NSAutoreleasePoolPage *page = start.page;
	unsigned count = 0;

	if (page == 0 || endPage == 0)
		return 0;
	for (;;) {
		unsigned first = page == start.page ? start.pageCount : 0;
		unsigned last = page == endPage ? endCount : page->count;

		if (last > first)
			count += last - first;
		if (page == endPage || page->next == 0)
			break;
		page = page->next;
	}
	return count;
}

unsigned
NSAutoreleasePoolCount(void)
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), NO);

	return data == 0 ? 0 : data->objectCount;
}

unsigned
NSTopAutoreleasePoolCount(void)
{
	NSThread *thread = _NSCurrentThread();
	NSAutoreleasePoolData *data = NSAutoreleasePoolDataForThread(thread, NO);
	NSAutoreleasePoolCursor *record;

	if (data == 0 || data->poolDepth == 0 || data->pageHead == 0)
		return 0;
	record = NSAutoreleasePoolRecord(data, data->poolDepth - 1);
	return NSAutoreleasePoolRangeCount(*record, data->pageHead,
		data->pageHead->count);
}

unsigned
NSAutoreleasePoolCountForObject(id anObject)
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), NO);
	NSAutoreleasePoolPage *page;
	unsigned count = 0;

	if (data == 0)
		return 0;
	for (page = data->pageHead; page != 0; page = page->previous) {
		unsigned index;

		for (index = 0; index < page->count; index++)
			if (NSAutoreleasePoolPageObjects(page)[index] == anObject)
				count++;
	}
	return count;
}

static BOOL
NSAutoreleaseObjectHasBeenFreed(id anObject)
{
	static Class freedObjectClass;

	if (freedObjectClass == Nil) {
		Object *probe = [(id)objc_lookUpClass("Object") allocWithZone:NULL];

		[probe free];
		freedObjectClass = *(Class *)probe;
	}
	return anObject != nil && *(Class *)anObject == freedObjectClass;
}

int
_NSAutoreleaseFreedObject(id anObject)
{
	_NSBasicStdErrLog(
		"*** _NSAutoreleaseFreedObject(): release of previously deallocated object (0x%x) ignored\n",
		(unsigned)anObject);
	return 0;
}

void
_NSAutoreleaseNoPool(id anObject)
{
	Class objectClass = *(Class *)anObject;

	NSLog(@"*** _NSAutoreleaseNoPool(): Object 0x%x of class %s autoreleased with no pool in place - just leaking\n",
		(unsigned)anObject, objectClass->name);
}

int
_NSAutoreleaseHighWaterLog(unsigned count)
{
	_NSBasicStdErrLog(
		"*** _NSAutoreleaseHighWaterLog(): %d objects in top autorelease pool\n",
		(int)count);
	return 0;
}

static void
NSAutoreleasePoolPrintRange(NSAutoreleasePoolCursor start,
		NSAutoreleasePoolPage *endPage, unsigned endCount)
{
	NSAutoreleasePoolPage *page = endPage;

	if (start.page == 0 || endPage == 0)
		return;
	for (;;) {
		unsigned first = page == start.page ? start.pageCount : 0;
		unsigned last = page == endPage ? endCount : page->count;
		unsigned index;

		for (index = last; index > first; index--) {
			id object = NSAutoreleasePoolPageObjects(page)[index - 1];
			Class objectClass = *(Class *)object;

			_NSBasicStdErrLog("\t0x%x (%s)\n", (unsigned)object,
				objectClass->name);
		}
		if (page == start.page)
			break;
		page = page->previous;
		if (page == 0)
			break;
	}
}

int
NSPrintAutoreleasePools(void)
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), NO);
	NSAutoreleasePoolCursor *records;
	NSAutoreleasePoolPage *endPage;
	unsigned endCount;
	unsigned index;

	if (data == 0 || data->poolDepth == 0 || data->pageHead == 0) {
		_NSBasicStdErrLog("No autorelease pools.\n");
		return 0;
	}
	records = NSAutoreleasePoolRecords(data);
	endPage = data->pageHead;
	endCount = endPage->count;
	for (index = data->poolDepth; index > 0; index--) {
		NSAutoreleasePoolCursor start = records[index - 1];
		unsigned count = NSAutoreleasePoolRangeCount(start, endPage, endCount);

		_NSBasicStdErrLog(
			"Pool (level = %d): %d objects ====================\n",
			(int)(data->poolDepth - index), (int)count);
		NSAutoreleasePoolPrintRange(start, endPage, endCount);
		endPage = start.page;
		endCount = start.pageCount;
	}
	return 0;
}

unsigned
NSPushAutoreleasePool(void)
{
	NSThread *thread = _NSCurrentThread();
	NSAutoreleasePoolData *data = NSAutoreleasePoolDataForThread(thread, YES);
	NSAutoreleasePoolCursor *record;
	unsigned token;

	if (data->poolDepth >= data->poolCapacity)
		data = NSAutoreleasePoolGrowRecords(thread, data);
	if (data->pageHead == 0)
		NSAutoreleasePoolAddPage(data);
	token = data->poolDepth;
	record = NSAutoreleasePoolRecord(data, token);
	record->pageCount = data->pageHead->count;
	record->page = data->pageHead;
	record->pool = 0;
	data->routesToSubclass = 0;
	data->poolDepth = token + 1;
	return token;
}

void
NSAutoreleaseObject(id anObject)
{
	NSThread *thread;
	NSAutoreleasePoolData *data;
	NSAutoreleasePoolPage *page;
	unsigned capacity;
	unsigned count;

	if (anObject == nil)
		return;
	thread = _NSCurrentThread();
	data = NSAutoreleasePoolDataForThread(thread, NO);
	if (data == 0 || data->poolDepth == 0) {
		if (NSKeepAllocationStatistics)
			NSRecordAllocationEvent(3, anObject);
		_NSAutoreleaseNoPool(anObject);
		return;
	}
	if (data->routesToSubclass) {
		NSAutoreleasePoolCursor *record =
			NSAutoreleasePoolRecord(data, data->poolDepth - 1);
		[(id)record->pool addObject:anObject];
		return;
	}
	if (NSKeepAllocationStatistics)
		NSRecordAllocationEvent(3, anObject);
	capacity = (NSAutoreleasePoolPageSize - 12) / sizeof(id);
	page = data->pageHead;
	if (page->count >= capacity) {
		NSAutoreleasePoolAddPage(data);
		page = data->pageHead;
	}
	NSAutoreleasePoolPageObjects(page)[page->count++] = anObject;
	data->objectCount++;
	NSTotalAutoreleasedObjectsCount++;
	count = data->objectCount;
	if (data->highWaterMark != 0 && count >= data->highWaterMark) {
		if (data->highWaterResolution != 0) {
			if ((count - data->highWaterMark) % data->highWaterResolution != 0)
				return;
		} else if (count != data->highWaterMark) {
			return;
		}
		_NSAutoreleaseHighWaterLog(count);
	}
}

void
NSPopAutoreleasePool(unsigned token)
{
	NSThread *thread = _NSCurrentThread();
	NSAutoreleasePoolData *data = NSAutoreleasePoolDataForThread(thread, NO);
	NSAutoreleasePoolCursor *records;
	NSAutoreleasePoolCursor target;
	unsigned index;
	BOOL checkFreedObjects;
	BOOL releaseObjects;

	if (data == 0 || data->pageHead == 0 || data->poolDepth <= token)
		return;
	records = NSAutoreleasePoolRecords(data);
	target = records[token];
	checkFreedObjects = data->freedObjectCheckEnabled;
	releaseObjects = data->releaseEnabled;
	if (NSKeepAllocationStatistics)
		NSRecordAllocationEvent(8);
	for (;;) {
		unsigned released = 0;
		BOOL caughtException = NO;
		NSAutoreleasePoolPage *page;

		NS_DURING
			page = data->pageHead;
			while (page != 0) {
				unsigned lower = page == target.page ? target.pageCount : 0;

				while (page->count > lower) {
					id object = NSAutoreleasePoolPageObjects(page)[--page->count];

					if (checkFreedObjects &&
						NSAutoreleaseObjectHasBeenFreed(object))
						_NSAutoreleaseFreedObject(object);
					else if (releaseObjects)
						[object release];
					released++;
				}
				if (page == target.page)
					break;
				page = page->previous;
			}
		NS_HANDLER
			caughtException = YES;
			if (data->handlingReleaseException) {
				_NSBasicStdErrLog("*** -[NSAutoreleasePool dealloc]: Exception ignored while releasing an object in an autorelease pool\n");
			} else {
				data->handlingReleaseException = 1;
#if defined(__ppc__) || defined(__POWERPC__)
				NSLog(@"*** -[NSAutoreleasePool dealloc]: Exception %@ ignored while releasing an object in an autorelease pool: %@\n",
					[localException name], localException);
#else
				NSLog(@"*** -[NSAutoreleasePool dealloc]: Exception %@ ignored while releasing an object in an autorelease pool\n",
					[localException name]);
#endif
				data->handlingReleaseException = 0;
			}
		NS_ENDHANDLER

		data = NSAutoreleasePoolDataForThread(thread, NO);
		if (caughtException)
			break;
		data->objectCount -= released;
		if (released == 0)
			break;
	}

	data = NSAutoreleasePoolDataForThread(thread, NO);
	records = NSAutoreleasePoolRecords(data);
	for (index = token; index < data->poolCapacity; index++) {
		NSAutoreleasePoolCursor *record = &records[index];
		id pool = record->pool;
		BOOL recycled = NO;
		unsigned slot;

		if (pool != nil && *(Class *)pool == NSAutoreleasePoolClass) {
			for (slot = 0; slot < 4; slot++) {
				if (data->recycledPools[slot] == nil) {
					data->recycledPools[slot] = pool;
					recycled = YES;
					break;
				}
			}
		}
		if (pool != nil && !recycled) {
			NSDeallocateObject(pool);
		}
		if (recycled && NSKeepAllocationStatistics)
			NSRecordAllocationEvent(1, pool);
		record->pageCount = 0;
		record->page = 0;
		record->pool = 0;
	}
	if (NSKeepAllocationStatistics)
		NSRecordAllocationEvent(9);
	data->poolDepth = token;
	data->routesToSubclass = 0;
	if (token != 0) {
		id parentPool = records[token - 1].pool;

		if (parentPool != nil && [parentPool class] != NSAutoreleasePoolClass)
			data->routesToSubclass = 1;
	}
	while (data->pageHead != 0 && data->pageHead->count == 0 &&
		data->pageHead->previous != 0) {
		NSAutoreleasePoolPage *page = data->pageHead;
		NSAutoreleasePoolPage *previous = page->previous;

		previous->next = 0;
		data->pageHead = previous;
		page->next = 0;
		page->previous = data->freePageHead;
		data->freePageHead = page;
		memset((char *)page + 12, 0, NSAutoreleasePoolPageSize - 12);
	}
}

@implementation NSAutoreleasePool

+ (id)allocWithZone:(NSZone *)zone
{
	Class class = (Class)self;
	NSThread *thread;
	NSAutoreleasePoolData *data;
	unsigned slot;

	if (NSAutoreleasePoolClass == Nil)
		NSAutoreleasePoolClass = [NSAutoreleasePool class];
	if (class != NSAutoreleasePoolClass)
		return NSAllocateObject(class, 0, zone);
	thread = _NSCurrentThread();
	data = NSAutoreleasePoolDataForThread(thread, YES);
	for (slot = 0; slot < 4; slot++) {
		id pool = data->recycledPools[slot];

		if (pool != nil) {
			data->recycledPools[slot] = nil;
			if (NSKeepAllocationStatistics)
				NSRecordAllocationEvent(0, pool, 0);
			return pool;
		}
	}
	return NSAllocateObject(class, 0, 0);
}

+ (void)addObject:(id)anObject
{
	NSAutoreleaseObject(anObject);
}

+ (BOOL)autoreleasePoolExists
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), NO);

	return data != 0 && data->poolDepth != 0;
}

+ (unsigned)autoreleasedObjectCount
{
	return NSAutoreleasePoolCount();
}

+ (unsigned)topAutoreleasePoolCount
{
	return NSTopAutoreleasePoolCount();
}

+ (void)enableFreedObjectCheck:(BOOL)flag
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), YES);
	if (data->freedObjectCheckEnabled != flag)
		data->freedObjectCheckEnabled = flag;
}

+ (void)enableRelease:(BOOL)flag
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), YES);
	if (data->releaseEnabled != flag)
		data->releaseEnabled = flag;
}

+ (unsigned)poolCountHighWaterMark
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), NO);

	return data == 0 ? 0 : data->highWaterMark;
}

+ (void)setPoolCountHighWaterMark:(unsigned)mark
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), YES);
	data->highWaterMark = mark;
}

+ (unsigned)poolCountHighWaterResolution
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), NO);

	return data == 0 ? 0 : data->highWaterResolution;
}

+ (void)setPoolCountHighWaterResolution:(unsigned)resolution
{
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), YES);
	data->highWaterResolution = resolution;
}

+ (void)resetTotalAutoreleasedObjects
{
	NSTotalAutoreleasedObjectsCount = 0;
}

+ (unsigned)totalAutoreleasedObjects
{
	return NSTotalAutoreleasedObjectsCount;
}

+ (void)showPools
{
	NSPrintAutoreleasePools();
}

+ (void)releaseAllPools
{
	NSThread *thread = _NSCurrentThread();
	NSAutoreleasePoolData **slot =
		(NSAutoreleasePoolData **)((char *)thread + 24);
	NSAutoreleasePoolData *data = *slot;
	NSAutoreleasePoolPage *page;
	unsigned index;

	if (data == 0)
		return;
	NSPopAutoreleasePool(0);
	*slot = 0;
	while ((page = data->pageHead) != 0) {
		data->pageHead = page->previous;
		NSDeallocateMemoryPages(page, NSAutoreleasePoolPageSize);
	}
	while ((page = data->freePageHead) != 0) {
		data->freePageHead = page->previous;
		NSDeallocateMemoryPages(page, NSAutoreleasePoolPageSize);
	}
	for (index = 0; index < 4; index++)
		if (data->recycledPools[index] != nil)
			(*_dealloc)((Object *)data->recycledPools[index]);
	NSZoneFree(0, data);
}

- (id)init
{
	return [self initWithCapacity:0];
}

- (id)initWithCapacity:(unsigned)numSlots
{
	unsigned token = NSPushAutoreleasePool();
	NSAutoreleasePoolData *data =
		NSAutoreleasePoolDataForThread(_NSCurrentThread(), NO);
	NSAutoreleasePoolCursor *record = NSAutoreleasePoolRecord(data, token);

	_token = (void *)token;
	record->pool = self;
	if (NSAutoreleasePoolClass == Nil)
		NSAutoreleasePoolClass = [NSAutoreleasePool class];
	data->routesToSubclass = *(Class *)self != NSAutoreleasePoolClass;
	(void)numSlots;
	return self;
}

- (void)release
{
	NSPopAutoreleasePool((unsigned)_token);
}

- (void)dealloc
{
	id proem = _NSMethodExceptionProem(self, _cmd);

	NSLog(@"%@: WARNING: Do not call this method directly.\n", proem);
}

- (unsigned)retainCount
{
	return 1;
}

- (id)retain
{
	id proem = _NSMethodExceptionProem(self, _cmd);

	[NSException raise:NSInvalidArgumentException
			 format:@"%@: Cannot retain an autorelease pool", proem];
	return self;
}

- (id)autorelease
{
	id proem = _NSMethodExceptionProem(self, _cmd);

	[NSException raise:NSInvalidArgumentException
			 format:@"%@: Cannot autorelease an autorelease pool", proem];
	return self;
}

- (void)addObject:(id)anObject
{
	NSThread *thread;
	NSAutoreleasePoolData *data;
	unsigned token = (unsigned)_token;
	unsigned depth;
	id *insert;

	if (anObject == nil)
		return;
	NSAutoreleaseObject(anObject);
	thread = _NSCurrentThread();
	data = NSAutoreleasePoolDataForThread(thread, NO);
	if (data == 0 || data->poolDepth == 0)
		return;
	depth = data->poolDepth;
	if (token == depth - 1)
		return;
	insert = NSAutoreleasePoolPageObjects(data->pageHead) +
		data->pageHead->count;
	while (token < depth - 1) {
		NSAutoreleasePoolCursor *record;
		NSAutoreleasePoolPage *page;
		id *source;

		--depth;
		record = NSAutoreleasePoolRecord(data, depth);
		page = record->page;
		source = NSAutoreleasePoolPageObjects(page) + record->pageCount++;
		if (record->pageCount >=
			(NSAutoreleasePoolPageSize - 12) / sizeof(id)) {
			if (page->next == 0)
				NSAutoreleasePoolAddPage(data);
			record->page = page->next;
			record->pageCount = 0;
		}
		*insert = *source;
		insert = source;
	}
	*insert = anObject;
}

@end
