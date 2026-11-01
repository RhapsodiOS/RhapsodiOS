# Foundation `NSPerformTimer` reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSPerformTimer.json`.

## ABI and source placement

The manifest records `NSPerformTimer` as an `NSTimer` subclass with a 32-byte
instance size. Its fields are `link`, `target`, `selector`, `argument`,
`order`, and `modes` at offsets 4 through 24; `firing`, `invalid`, and
`filler` occupy the 16-bit word at offset 28, and `refCount` occupies the
16-bit word at offset 30. The manifest has one factory and eleven instance
selectors.

All twelve methods were already implemented in `NSRunLoop.m`, but that file
declared the class as an `NSObject` subclass and exposed its state under
different ivar names. The ABI manifest assigns the class to `NSPerformTimer.m`
while `NSRunLoop.m` has its own class manifest. The implementation is now in
`NSPerformTimer.m`; the exact private class interface is shared with the run
loop through `NSPerformTimerPrivate.h`. The run loop continues to view the
performer as its linked-list record, whose pointer and state fields match the
class storage.

## IDA-confirmed behavior

- The factory removes the first available object from a four-entry cache under
  `NSPerformTimerCacheLock`, or allocates a fresh `NSPerformTimer`. Reused
  objects record an allocation event. It stores the target, selector,
  argument, order, clears `invalid`, copies the modes, and returns the object.
- `fire` returns when either `firing` or `invalid` is set. Otherwise it sets
  `firing`, invokes the target, catches and logs an exception, clears `firing`,
  and invalidates the performer.
- `invalidate` sets `invalid`, releases `modes`, and clears the ivar. `fireDate`
  returns `[NSDate date]`; `timeInterval` returns zero; `userInfo` returns nil;
  `isValid` checks `invalid`.
- The 16-bit reference count increments and decrements directly. Releasing at
  zero deallocates the performer; `retainCount` returns the stored count plus
  one.
- `dealloc` invalidates first, then stores the object in the first empty cache
  slot while holding the lock. Cached objects have target, selector, argument,
  order, modes, `firing`, filler bits, reference count, and `link` cleared;
  `invalid` remains set until the next factory call. If all four slots are
  occupied, it calls `NSObject` deallocation.
- `description` formats the target, selector, argument, and order.

Relevant IDA addresses: factory `0x425165d4`; `invalidate` `0x4250bc34`;
`release` `0x425123fc`; `fire` `0x425124f0`; `dealloc` `0x42516dc0`;
`description` `0x42581158`; `fireDate` `0x42581194`; `isValid` `0x425811b8`;
`retainCount` `0x425811cc`; `retain` `0x425811dc`; `timeInterval`
`0x425811ec`; `userInfo` `0x425811fc`.

Static selector and source-list audits are the verification available for this
increment; no build or runtime test has been run.
