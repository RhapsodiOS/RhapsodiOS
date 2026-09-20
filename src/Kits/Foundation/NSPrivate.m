/*	NSPrivate.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSZone.h>

/*  _NSAutoreleasedMallocMemory: scratch storage bump-allocated out of
    500-byte chunks (the reference's own -remainingCapacity, 0x42518bb4,
    hard-codes 0x1F4), each chunk autoreleased so its storage is reclaimed
    when the current autorelease pool drains.  Foundation-private, with no
    public header anywhere in the shipped tree -- hence this module has
    none either, and the class is declared here, the only place that
    needs it.  */

#define NSAutoreleasedMallocMemoryChunkSize 500

@interface _NSAutoreleasedMallocMemory : NSObject {
@private
    void	*mutableBytes;
    unsigned	length;
}
+ (void *)mallocMemoryWithCapacity:(unsigned)capacity;
- (id)initWithCapacity:(unsigned)capacity;
- (void *)mallocMemoryWithCapacity:(unsigned)capacity;
- (unsigned)remainingCapacity;
@end

/*	The chunk +mallocMemoryWithCapacity: is currently bump-allocating
	small requests out of, so consecutive small requests reuse the same
	chunk instead of allocating a fresh one every time.  The reference
	(0x4251ba24) keeps this in the calling thread's -threadDictionary,
	under the key "NSAutoreleaseMalloc" (recovered from the slice's
	__cstring_object at 0x42606734/0x42606738) -- NSThread.m and
	NSDictionary.m territory, neither reconstructed in this stage.
	Substituted here with a single process-global pointer for the same
	reason NSAutoreleasePool.m's own pool stack substitutes a
	process-global for the reference's per-thread pool storage --
	unthreaded, matching every test in this stage.  */
static _NSAutoreleasedMallocMemory *currentMallocMemoryChunk = nil;

@implementation _NSAutoreleasedMallocMemory

/*  Reconstructed from the reference's branch structure (0x4251ba24-
    0x4251bbd6): a request bigger than a chunk always gets its own
    dedicated, exactly sized chunk.  Otherwise, if the chunk currently
    cached above has enough room left, reuse it as-is; if a *fresh*
    chunk would end up with less headroom afterward than the cached one
    already has, the cached one is still worth keeping for later small
    requests, so this request instead gets its own dedicated chunk sized
    exactly to it; only when a fresh chunk would clearly do better does
    this replace the cache.  */
+ (void *)mallocMemoryWithCapacity:(unsigned)capacity {
    _NSAutoreleasedMallocMemory *chunk;
    unsigned remaining;

    if (capacity > NSAutoreleasedMallocMemoryChunkSize) {
        chunk = [[_NSAutoreleasedMallocMemory allocWithZone:NULL] initWithCapacity:capacity];
        chunk = [chunk autorelease];
        return [chunk mallocMemoryWithCapacity:capacity];
    }

    remaining = (currentMallocMemoryChunk != nil) ? [currentMallocMemoryChunk remainingCapacity] : 0;

    if (capacity <= remaining) {
        chunk = currentMallocMemoryChunk;
    } else if ((NSAutoreleasedMallocMemoryChunkSize - capacity) > remaining) {
        chunk = [[_NSAutoreleasedMallocMemory allocWithZone:NULL]
                    initWithCapacity:NSAutoreleasedMallocMemoryChunkSize];
        chunk = [chunk autorelease];
        currentMallocMemoryChunk = chunk;
    } else {
        chunk = [[_NSAutoreleasedMallocMemory allocWithZone:NULL] initWithCapacity:capacity];
        chunk = [chunk autorelease];
    }

    return [chunk mallocMemoryWithCapacity:capacity];
}

/*  [super init]'s own selector cell relocates to 0x41406990 -- outside
    this slice, in the same out-of-slice prebound-image range as
    NSObject.m's +new selectors (0x414067cc/0x41406990); the exact text
    is not recoverable, but a designated initializer calling its
    superclass's is the only structural candidate, and this is one of
    the two specific addresses NSObject.m's own +new already names.  */
- (id)initWithCapacity:(unsigned)capacity {
    self = [super init];
    mutableBytes = NSZoneMalloc(NULL, capacity);
    length = 0;
    return self;
}

/*  A bump allocator over this chunk's own storage: hands back the next
    `capacity` bytes and advances past them.  No bounds checking here --
    the class method above is what keeps a request within a chunk's
    remaining room.  */
- (void *)mallocMemoryWithCapacity:(unsigned)capacity {
    void *result = (char *)mutableBytes + length;

    length += capacity;
    return result;
}

/*  Headroom left in a full-size chunk.  The constant is the reference's
    own (-remainingCapacity at 0x42518bb4 hard-codes 0x1F4), and it has to
    be: the class carries exactly two ivars, mutableBytes and length, so
    there is nowhere to record a chunk's real size without changing
    instance_size away from the reference's 12 -- which the committed ABI
    baseline pins.  The answer is therefore only meaningful for a chunk
    allocated at the full size, which is why +mallocMemoryWithCapacity:
    above caches nothing else: the two dedicated-chunk branches size a
    chunk to one request and hand it straight back without ever consulting
    this.  The clamp keeps a chunk allocated smaller than the constant from
    turning that mismatch into an unsigned underflow, which would report
    near-4GB of headroom and let the unchecked bump allocator above walk
    off the end of the block.  */
- (unsigned)remainingCapacity {
    if (length >= NSAutoreleasedMallocMemoryChunkSize)
        return 0;
    return NSAutoreleasedMallocMemoryChunkSize - length;
}

- (void)dealloc {
    if (self == currentMallocMemoryChunk)
        currentMallocMemoryChunk = nil;
    NSZoneFree(NULL, mutableBytes);
    [super dealloc];
}

@end
