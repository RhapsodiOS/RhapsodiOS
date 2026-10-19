/*	NSPrivate.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSValue.h>
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

/*	The chunk +mallocMemoryWithCapacity: reuses for small requests is
	stored in the current thread's -threadDictionary under
	"NSAutoreleaseMalloc".  Both reference targets use this per-thread
	cache (PPC 0x42525c40; i386 0x4251ba24), wrapping the chunk in an
	NSValue nonretained-object value.  NSThread.m, NSDictionary.m, and
	NSValue.m now provide the supporting APIs used by that path.  */
@implementation _NSAutoreleasedMallocMemory

/*  Reconstructed from the PPC and i386 reference branches: requests
    larger than 500 bytes get exact-size chunks without consulting the
    cache. Smaller requests reuse a cached chunk with enough room, or
    replace it with a full chunk only when that leaves more headroom. */
+ (void *)mallocMemoryWithCapacity:(unsigned)capacity {
    _NSAutoreleasedMallocMemory *chunk;
    NSMutableDictionary *threadDictionary;
    NSValue *cachedChunkValue;
    unsigned remaining;

    if (capacity > NSAutoreleasedMallocMemoryChunkSize) {
        chunk = [[_NSAutoreleasedMallocMemory allocWithZone:NULL] initWithCapacity:capacity];
        chunk = [chunk autorelease];
        return [chunk mallocMemoryWithCapacity:capacity];
    }

    threadDictionary = [_NSCurrentThread() threadDictionary];
    cachedChunkValue = [threadDictionary objectForKey:@"NSAutoreleaseMalloc"];
    chunk = [cachedChunkValue nonretainedObjectValue];
    remaining = (chunk != nil) ? [chunk remainingCapacity] : 0;

    if (capacity > remaining) {
        if ((NSAutoreleasedMallocMemoryChunkSize - capacity) > remaining) {
            chunk = [[_NSAutoreleasedMallocMemory allocWithZone:NULL]
                        initWithCapacity:NSAutoreleasedMallocMemoryChunkSize];
            chunk = [chunk autorelease];
            [threadDictionary setObject:
                [NSValue valueWithNonretainedObject:chunk]
                forKey:@"NSAutoreleaseMalloc"];
        } else {
            chunk = [[_NSAutoreleasedMallocMemory allocWithZone:NULL]
                        initWithCapacity:capacity];
            chunk = [chunk autorelease];
        }
    }

    return [chunk mallocMemoryWithCapacity:capacity];
}

/*  Both reference targets send init to super but discard its result,
    then initialize this object's storage and return the original self.  */
- (id)initWithCapacity:(unsigned)capacity {
    [super init];
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

/*  The targets return unsigned 500 - length without a capacity check.
    The cache asks for this value only on a cached full-size chunk. */
- (unsigned)remainingCapacity {
    return NSAutoreleasedMallocMemoryChunkSize - length;
}

- (void)dealloc {
    NSMutableDictionary *threadDictionary = [_NSCurrentThread() threadDictionary];
    NSValue *cachedChunkValue =
        [threadDictionary objectForKey:@"NSAutoreleaseMalloc"];

    if ([cachedChunkValue nonretainedObjectValue] == self)
        [threadDictionary removeObjectForKey:@"NSAutoreleaseMalloc"];
    NSZoneFree(NULL, mutableBytes);
    [super dealloc];
}

@end
