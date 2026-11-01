# Foundation NSCharacterSet thread-lock fidelity (2026-10-04)

Reference: Foundation i386 IDA database `d12fe2f23883`.

IDA's `__NSToDoAtFirstThreadStart` (`0x425547f8`) initializes the global
`_NSCharacterSetLock` as an `NSLock`, after `_NSPortTableLock`. The target's
`+[NSConcreteMutableCharacterSet characterSetWithName:]`
(`0x42586c9c`) and `+[NSConcreteMutableCharacterSet
_readAndRetainFileNamed:makeCompact:]`
(`0x42586b2c`) acquire and release that lock only when it is nonnull. The
source had instead lazily created a static `NSRecursiveLock` at first use.

`NSCharacterSet.m` now defines the target-named global and uses nil-guarded
lock operations in both methods. `NSThread.m` initializes it in the existing
first-thread hook as an `NSLock`, matching the target's type and initialization
point. The target also keeps `namedCharacterSets` in an `NSMutableDictionary`,
allocating it with capacity 16, and performs `objectForKey:`/`setObject:forKey:`
under the same lock. The source's linked-list cache is now that dictionary.
Selector ownership is unchanged. Static selector and whitespace audits were
run; tests and builds were not run.
