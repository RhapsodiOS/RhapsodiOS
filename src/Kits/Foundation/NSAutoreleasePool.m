/*	NSAutoreleasePool.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#include <stdio.h>

/*  Foundation-private helper this file calls that is not declared by any
    header this project ships -- the same routine NSObject.m and NSProxy.m
    already declare locally for their own doesNotRecognizeSelector:
    messages.  */
extern id _NSMethodExceptionProem(id object, SEL aSelector);

/*  A pool's contents: the autoreleased objects recorded against it, kept
    here as a plain growable array of ids.  The reference keeps this in a
    per-thread structure (reached through _NSCurrentThread(), NSThread.m
    territory this stage does not reconstruct) segmented into fixed-size
    "pages" the pool machinery allocates as it grows (a private
    __NSAPAddPage) and indexed by nesting depth; none of that -- the
    paging, the per-thread storage, or the fixed-size-page layout -- is
    reconstructed here.  What is reconstructed is the externally
    observable contract established by the reference's own -release
    (0x4250d648, calls NSPopAutoreleasePool with this pool's _token) and
    -initWithCapacity: (0x4250d5cc, calls NSPushAutoreleasePool and
    stores its result in _token): an object handed to
    -autorelease/+addObject: is recorded against the innermost active
    pool and released exactly once when that pool (or an enclosing one)
    drains.  This substitutes a single, process-global stack of plain
    growable arrays for the reference's per-thread paged storage -- the
    same kind of substitution NSZone.m's ExtraRefCountTable already makes
    for NSMapTable, and for the identical reason (the real backing
    module is not yet reconstructed); made single-threaded for the same
    reason NSZone.m's own lock is skipped: every test in this stage runs
    unthreaded.  */

#define NSAutoreleasePoolFrameMinCapacity 16

typedef struct {
    id *objects;
    unsigned count;
    unsigned capacity;
} NSAutoreleasePoolFrame;

static NSAutoreleasePoolFrame **poolStack = 0;
static unsigned poolStackCount = 0;
static unsigned poolStackCapacity = 0;

/*	Class-side configuration and bookkeeping state.  Like the pool stack
	above, the reference keeps all of this in the same per-thread
	structure (_NSCurrentThread()'s lazily created "AP data", built by
	the out-of-scope __NSAPDataCreate); substituted here with plain
	process-global storage for the same reason.  */
static unsigned NSAutoreleasePoolCountHighWaterMark = 0;
static unsigned NSAutoreleasePoolCountHighWaterResolution = 0;
static BOOL NSAutoreleasePoolFreedObjectCheckEnabled = NO;
static BOOL NSAutoreleasePoolReleaseEnabled = NO;
static unsigned NSTotalAutoreleasedObjectsCount = 0;

static NSAutoreleasePoolFrame *
NSAutoreleasePoolFrameCreate(unsigned capacity)
{
    NSAutoreleasePoolFrame *frame;

    frame = (NSAutoreleasePoolFrame *)NSZoneMalloc(0, sizeof(NSAutoreleasePoolFrame));
    frame->count = 0;
    frame->capacity = (capacity > 0) ? capacity : NSAutoreleasePoolFrameMinCapacity;
    frame->objects = (id *)NSZoneMalloc(0, frame->capacity * sizeof(id));
    return frame;
}

static void
NSAutoreleasePoolFrameAppend(NSAutoreleasePoolFrame *frame, id anObject)
{
    if (frame->count == frame->capacity) {
        unsigned newCapacity = frame->capacity * 2;
        id *newObjects = (id *)NSZoneMalloc(0, newCapacity * sizeof(id));
        unsigned i;

        for (i = 0; i < frame->count; i++)
            newObjects[i] = frame->objects[i];
        NSZoneFree(0, frame->objects);
        frame->objects = newObjects;
        frame->capacity = newCapacity;
    }
    frame->objects[frame->count++] = anObject;
}

/*	Releases every object this frame recorded, in the reverse of the
	order it was recorded, then frees the frame itself.  */
static void
NSAutoreleasePoolFrameDrain(NSAutoreleasePoolFrame *frame)
{
    unsigned i;

    for (i = frame->count; i > 0; i--)
        [frame->objects[i - 1] release];
    NSZoneFree(0, frame->objects);
    NSZoneFree(0, frame);
}

/*	Pushes a new, empty pool frame and returns it -- the opaque token the
	reference's own NSPushAutoreleasePool returns and that
	-initWithCapacity: stores in _token.  `capacity` is the new frame's
	initial array size: the reference reads it the same way
	-initWithCapacity: itself does, the documented meaning of that
	method's argument (an initial-size hint, not a hard limit).  Not
	static: the reference exports this symbol (external, __TEXT,__text),
	the same cross-TU-entry-point category NSAutoreleaseObject's own
	comment below describes, even though only -initWithCapacity: in this
	file happens to call it.  No header declares it (see divergences.md)
	-- claimed by name in reconstruction/symbols.json instead.  */
void *
NSPushAutoreleasePool(unsigned capacity)
{
    NSAutoreleasePoolFrame *frame;

    frame = NSAutoreleasePoolFrameCreate(capacity);

    if (poolStackCount == poolStackCapacity) {
        unsigned newCapacity = (poolStackCapacity == 0) ? 8 : poolStackCapacity * 2;
        NSAutoreleasePoolFrame **newStack = (NSAutoreleasePoolFrame **)
            NSZoneMalloc(0, newCapacity * sizeof(NSAutoreleasePoolFrame *));
        unsigned i;

        for (i = 0; i < poolStackCount; i++)
            newStack[i] = poolStack[i];
        if (poolStack != 0)
            NSZoneFree(0, poolStack);
        poolStack = newStack;
        poolStackCapacity = newCapacity;
    }
    poolStack[poolStackCount++] = frame;

    return (void *)frame;
}

/*	Drains every pool from the innermost down to (and including) the one
	`token` identifies -- covering the case where an inner pool was
	created but never itself released before its enclosing pool is.  Not
	static: the reference exports this symbol (external, __TEXT,__text),
	the same cross-TU-entry-point category NSAutoreleaseObject's own
	comment below describes, even though only +releaseAllPools and
	-release (below) happen to call it from within this file.  No header
	declares it (see divergences.md) -- claimed by name in
	reconstruction/symbols.json instead.  */
void
NSPopAutoreleasePool(void *token)
{
    while (poolStackCount > 0) {
        NSAutoreleasePoolFrame *frame = poolStack[--poolStackCount];
        BOOL isTarget = ((void *)frame == token);

        NSAutoreleasePoolFrameDrain(frame);
        if (isTarget)
            break;
    }
}

/*	Records `anObject` against the innermost active pool.  If no pool is
	active, the reference's own _NSAutoreleaseObject is outside this
	stage's published analysis scope at this call, so its behaviour for
	that case is not confirmed; no test in this stage autoreleases
	without an active pool, so the object is simply not tracked here --
	documented, not exercised.

	Not static, same as NSPushAutoreleasePool/NSPopAutoreleasePool
	above: -[NSObject autorelease] and -[NSProxy autorelease] both call
	this symbol directly (extern declarations in NSObject.m/NSProxy.m),
	confirmed from each site's own disassembly (a real `call` to this
	exact exported name, not objc_msgSend) -- the same cross-file
	relationship the reference itself has, just not one this stage's ABI
	baseline captured, since no header declares it (see
	divergences.md).  */
void
NSAutoreleaseObject(id anObject)
{
    if (anObject == 0 || poolStackCount == 0)
        return;
    NSAutoreleasePoolFrameAppend(poolStack[poolStackCount - 1], anObject);
    NSTotalAutoreleasedObjectsCount++;
}

@implementation NSAutoreleasePool

/*  The reference (0x42512888) recycles up to four freed pool instances
    through the same per-thread AP data this file substitutes away above,
    rather than allocating fresh every time -- a pure allocation-
    performance optimisation: a recycled instance still has its ivars
    re-set by -init/-initWithCapacity:, so it is not observably different
    from a freshly allocated one.  Not reconstructed; every allocation
    here is fresh.  */
+ (id)allocWithZone:(NSZone *)zone {
    return NSAllocateObject(self, 0, zone);
}

+ (void)addObject:(id)anObject {
    NSAutoreleaseObject(anObject);
}

+ (BOOL)autoreleasePoolExists {
    return poolStackCount > 0;
}

+ (unsigned)autoreleasedObjectCount {
    unsigned total = 0;
    unsigned i;

    for (i = 0; i < poolStackCount; i++)
        total += poolStack[i]->count;
    return total;
}

+ (unsigned)topAutoreleasePoolCount {
    if (poolStackCount == 0)
        return 0;
    return poolStack[poolStackCount - 1]->count;
}

+ (void)enableFreedObjectCheck:(BOOL)flag {
    NSAutoreleasePoolFreedObjectCheckEnabled = flag;
}

+ (void)enableRelease:(BOOL)flag {
    NSAutoreleasePoolReleaseEnabled = flag;
}

+ (unsigned)poolCountHighWaterMark {
    return NSAutoreleasePoolCountHighWaterMark;
}

+ (void)setPoolCountHighWaterMark:(unsigned)mark {
    NSAutoreleasePoolCountHighWaterMark = mark;
}

+ (unsigned)poolCountHighWaterResolution {
    return NSAutoreleasePoolCountHighWaterResolution;
}

+ (void)setPoolCountHighWaterResolution:(unsigned)resolution {
    NSAutoreleasePoolCountHighWaterResolution = resolution;
}

+ (void)resetTotalAutoreleasedObjects {
    NSTotalAutoreleasedObjectsCount = 0;
}

+ (unsigned)totalAutoreleasedObjects {
    return NSTotalAutoreleasedObjectsCount;
}

/*  A best-effort diagnostic dump: the reference's own formatting routine
    (_NSPrintAutoreleasePools) is outside this stage's published analysis
    scope, so its exact text is not reconstructed -- only that this lists
    the active pools and how many objects each holds.  */
+ (void)showPools {
    unsigned i;

    fprintf(stderr, "%u autorelease pool(s) active\n", poolStackCount);
    for (i = 0; i < poolStackCount; i++)
        fprintf(stderr, "  pool %u: %u autoreleased object(s)\n", i, poolStack[i]->count);
}

+ (void)releaseAllPools {
    if (poolStackCount > 0)
        NSPopAutoreleasePool(poolStack[0]);
}

- (id)init {
    return [self initWithCapacity:0];
}

- (id)initWithCapacity:(unsigned)numSlots {
    _token = NSPushAutoreleasePool(numSlots);
    return self;
}

- (void)release {
    NSPopAutoreleasePool(_token);
}

/*  Calling -dealloc directly bypasses the bookkeeping -release performs
    (popping this pool, and any pools still nested inside it, off the
    stack).  Confirmed directly from the reference's disassembly
    (0x4257341c): this path does not call NSPopAutoreleasePool, or the
    superclass's -dealloc -- only the warning below.  */
- (void)dealloc {
    id proem = _NSMethodExceptionProem(self, _cmd);

    NSLog(@"%@: WARNING: Do not call this method directly.\n", proem);
}

- (unsigned)retainCount {
    return 1;
}

- (id)retain {
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                 format:@"%@: Cannot retain an autorelease pool", proem];
    return self;
}

- (id)autorelease {
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                 format:@"%@: Cannot autorelease an autorelease pool", proem];
    return self;
}

/*  Inserts `anObject` into *this* pool's own frame, whichever pool that
    is -- distinct from the class method above, which always targets the
    innermost active pool.  The reference (0x425732d8) does this by
    calling _NSAutoreleaseObject first (recording the object against the
    innermost pool and incrementing the global autoreleased-object
    counter), then re-homing it into this pool's slot by shifting every
    frame nested inside this one along a shared per-thread buffer
    (out-of-scope internals, see the block comment above).  Reconstructed
    here as calling NSAutoreleaseObject() first, for the same counter
    side effect, then moving the object from the innermost frame to this
    pool's own frame when the two differ -- preserving both the counter
    bump and the externally observable difference from +addObject:
    (which pool ends up holding the object) without the reference's
    buffer-sharing mechanics.  */
- (void)addObject:(id)anObject {
    NSAutoreleasePoolFrame *frame = (NSAutoreleasePoolFrame *)_token;
    NSAutoreleasePoolFrame *innermost;

    if (anObject == 0 || frame == 0)
        return;

    NSAutoreleaseObject(anObject);

    if (poolStackCount == 0)
        return;

    innermost = poolStack[poolStackCount - 1];
    if (innermost != frame) {
        innermost->count--;
        NSAutoreleasePoolFrameAppend(frame, anObject);
    }
}

@end
