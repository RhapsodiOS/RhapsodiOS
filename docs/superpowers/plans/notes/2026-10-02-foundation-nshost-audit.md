# Foundation NSHost audit

Reference: Foundation i386 IDA database `6c2a913dc37a`.

## Cache synchronization

`+[NSHost _hostWithHostEntry:name:]` (`0x425513c8`) locks
`_NSHostTableLock` around the host-cache lookup and again around cache creation
and insertion, when that lock exists. `+[NSHost flushHostCache]`
(`0x42577334`) also locks around release and reset of the cache. The current
`NSHost.m` now guards the lookup, cache creation and insertion, and flush paths
with `_NSHostTableLock`, when the lock exists. Cache enable flag access itself
is unlocked in the target.

The lock lifecycle is owned by `NSThread`: `__NSToDoAtFirstThreadStart`
(`0x425547f8`) creates `_NSHostTableLock` when it is nil, and
`__NSToDoAtLastThreadExit` (`0x42571898`) releases and clears it. The current
`NSThread.m` startup hook now creates the lock and its ABI inventory includes
the exported data symbol. The last-thread cleanup hook remains absent from the
current source and ABI inventory; the target cleanup body also owns many other
locks, so it is left as a separate lifecycle reconstruction task.

## Name collection

`-[NSHost _initWithHostEntry:name:]` (`0x4254ea70`) starts `names` with the
requested name, then adds the canonical name only when it differs from the
requested name. For each alias, it performs the same comparison against the
requested name only; it does not deduplicate against the canonical name or
earlier aliases. The source now follows those comparisons and constructs the
canonical name and aliases with `stringWithCString:length:`, as the target does.

## Other checked methods

The checked `currentHost`, `hostWithName:`, `hostWithAddress:`,
`_hostWithHostEntry:`, first-name/address accessors, address-based equality,
description, and deallocation follow the target paths. The target copies each
`h_addr_list` entry into an `in_addr` using the hostent's `h_length`, then
formats it with `inet_ntoa` and passes its measured C-string length to
`stringWithCString:length:`. The source now uses `memmove` with that exact
length, with no additional size filter, and constructs the address string with
the observed bounded initializer.

Relevant target addresses: `currentHost` `0x425470e8`; name lookup
`0x42577400`; address lookup `0x425773a4`; `_hostWithHostEntry:`
`0x425772d4`; cache path `0x425513c8`; `_initWithHostEntry:name:`
`0x4254ea70`; equality `0x4257fd78`.

## Public lookup recheck (2026-10-04)

Re-decompiled `currentHost`, `hostWithName:`, `hostWithAddress:`, and
`isEqualToHost:` at their addresses above. The source matches the 257-byte
`gethostname` call, hostname lookup and loopback fallback, `inet_addr` /
`gethostbyaddr` path, and address-intersection equality check. The source-side
write to `hostname[259]` was removed because the target has no such write. No
other source discrepancy was found in these methods.

## Thread-lock teardown recheck (2026-10-06)

The earlier lifecycle note is superseded: `NSThread.m` now releases and clears
`_NSHostTableLock` in `_NSToDoAtLastThreadExit`. Both the i386 target at
`0x42571898` and PPC target at `0x4257fdfc` release this lock in the last-thread
hook after the host-cache methods initialize and use it. The source matches
that lifecycle; no further NSHost source change was needed.

## Address equality call order (2026-10-07)

DR2 i386 `-[NSHost isEqualToHost:]` at `0x4257fd78` and MOSXS PPC at
`0x42594ee0` both fetch `[aHost addresses]` once and read the count of
`self->addresses` once before iterating. Each iteration obtains the local
address by index and checks membership in the cached other-host array.
`NSHost.m` now matches that call order instead of repeating the accessor and
count messages inside the loop.

## Description selector and message count (2026-10-07)

DR2 i386 `-[NSHost description]` at `0x4257fd0c` reads its first format
argument's selector from `0x42608c58`; the first word is `0x414066d4`, also
used by `-[NSTimeZone timeZoneName]`. MOSXS PPC `-[NSHost description]` at
`0x42594e58` reads selector `sel_name` from `0x4262d284`, confirmed by the PPC
System database. That identifies the corresponding i386 selector as `name` by
cross-target and call-site comparison. Both methods send exactly three
messages to `self` before formatting, corresponding to `name`, `names`, and
`addresses`; compiler argument-evaluation order accounts for the
target-specific order. The source had two extra discarded calls to `addresses`
and `names`. Removed those calls; the single format expression retains the
target's three selector sends and `"Host %@ (%@ %@)"` format.

## Cache controls and accessors recheck (2026-10-07)

Paired IDA review confirms `flushHostCache` locks the optional host-table lock,
releases and clears the cache, then unlocks; cache-enabled getter/setter access
the flag without locking. `name` and `address` return element zero of their
arrays, while `names` and `addresses` return the stored arrays. `NSHost.m`
matches both i386 (`0x42577334`, `0x42577440`, `0x42577454`, `0x42546914`,
`0x4257fc7c`, `0x4257fca0`, `0x4257fe14`) and PPC (`0x425899d4`, `0x42589b2c`,
`0x42589b64`, `0x4253eeb4`, `0x42594d9c`, `0x42594dd8`, `0x42594f98`). No
source correction was indicated.
