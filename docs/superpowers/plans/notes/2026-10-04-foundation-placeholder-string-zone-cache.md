# Foundation `NSPlaceholderString` zone cache reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and the current
`NSString.m` / `NSThread.m` sources.

`__NSPlaceholderStringFromZone` at `0x42503c08` locks with
`_NSPlaceholderStringLock` when that lock exists, reuses a cached placeholder
when its `zoneForString` matches, otherwise scans the retained placeholder
array from last to first. The array is allocated in the default zone with
capacity 8. A missing zone entry is an `NSPlaceholderString` allocated in the
default zone, initialized with the requested zone at ivar offset 4, added to
the array, and released locally. The selected object becomes the cache, the
lock is released when present, and the borrowed placeholder is returned.

`__NSToDoAtFirstThreadStart` at `0x42554f31` initializes
`_NSPlaceholderStringLock` as an `NSLock` if it is nil. The source now defines
that global beside the placeholder implementation and initializes it in the
existing first-thread startup hook. The constructor obtains its class through
`[NSPlaceholderString class]`; the binary's separate class cache is populated
by process startup.

Static source and manifest checks only; no tests or builds were run.
