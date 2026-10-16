# Foundation `__NSUniqueCString` analysis

Reference: Foundation i386 IDA database `d12fe2f23883`.

## IDA behavior

IDA decompiles `__NSUniqueCString` at `0x42538dec` as a C-string interning
helper. A null pointer returns null immediately. Otherwise it locks
`_NSUniqueCStringLock` when that global is non-null, lazily creates a global
`NSHashTable` with capacity 27 and the C-string hash, equality, and description
callbacks, and looks up the input by contents. A miss allocates
`strlen(input) + 1` bytes in the default zone, copies the terminating NUL,
inserts the copy, and returns the interned pointer. A hit returns the pointer
already stored in the table. The helper unlocks before returning whenever the
lock was present.

The hash table has no retain or release callbacks. The helper does not free
interned strings or destroy the table in its own body.

## Callers and source state

IDA identifies three call sites in `__NSWalkData` at `0x4251db30` and one in
`__encodeClass` at `0x425345dc`. The latter interns the class-name C string
before passing it to `_encodeOrReuseCString`.

The current `NSArchiver.m` class path obtains `[archiveName cString]` and
passes it directly to `_encodeOrReuseCString`. Its per-archiver string table
already uses content-based C-string callbacks. No source definition or caller
for `__NSWalkData` is present under `src/Kits/Foundation`.

## Lock lifecycle gap

IDA's `_NSToDoAtFirstThreadStart` at `0x425547f8` creates an `NSLock` for
`_NSUniqueCStringLock` when it is null. `_NSToDoAtLastThreadExit` at
`0x42571898` calls `+[NSRunLoop _taskNowSingleThreaded]`, then releases and
clears the framework's shared lock globals, including `_NSUniqueCStringLock`.
It also frees four low-level lock allocations (`__NSDebugRecordLock`,
`__NSAllocatorLock`, `__NSRefCountLock`, and `__NSSequenceLock`). The current
`NSThread.m` defines first-thread initialization but no corresponding
last-thread teardown function; `-[NSThread _exit]` exits an individual thread
and does not establish that it is the last one. A teardown implementation
cannot safely be reduced to releasing only `_NSUniqueCStringLock`, because
that would omit the other shared locks and the single-threaded run-loop
transition.

No source implementation change was made as part of this analysis.
