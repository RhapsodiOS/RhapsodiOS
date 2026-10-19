# NSProcessInfo Singleton and Unique String Recheck

Reference: Foundation i386 IDA database `6c2a913dc37a`.

## Singleton

`+[NSProcessInfo processInfo]` at `0x42535d84` checks the static cache,
allocates `NSProcessInfo` in the default zone when the cache is null, sends
`init`, stores the result, and returns the cache. The source follows this
sequence. The cache at `0x426025a0` is initialized to null.

## Globally unique string

`-[NSProcessInfo globallyUniqueString]` at `0x42581558` gates both lock and
unlock of `_NSUniqueStringCounterLock` on `_NSTempFileCounterLock` being
non-null, increments the static counter, and rebuilds the prototype when the
counter wraps to a non-positive value. The data at `0x426025a4` initializes
the counter to `-1`; the prototype pointer at `0x426025a8` initializes to
null. The source has the same lock gate, wrapping behavior, prototype release,
and reset to counter `1`.

On prototype rebuild, the target obtains the current time, host name, process
name length, and process ID; converts negative time to positive; and formats
`host_pid_seconds_processNameLength_`, using an empty host string if the host
name is null. The source follows this ordering and uses the same format shape.
The returned string appends the decimal counter to that prototype.

## Result

No source correction was indicated by the singleton and unique-string
comparison. The supporting process-information paths were compared in the
follow-up section below.

## Process path, name, environment, and arguments

The IDA bodies checked for this pass are `_NSGetEnvironmentVariable` at
`0x42528214`, `_NSGetDirectory2` at `0x4254135c`,
`_NSSearchForNameInPath` at `0x42585314`, `_NSProcessPath` at `0x425472d0`,
`_NSProcessName` at `0x4253ffb4`, `-[NSProcessInfo processName]` at
`0x42540398`, `-[NSProcessInfo arguments]` at `0x4254dc3c`, and
`-[NSProcessInfo environment]` at `0x42533bc0`.

The source follows the same normal path resolution order: `NSProcessPath`
environment override, `argv[0]` search through `PATH` when it has no slash,
current-directory qualification when a relative PATH hit exists, then
current-directory qualification of `argv[0]`, with the original argument as
the final fallback. The executable-name helper caches the path basename.
`processName` wraps it in an NSString. `arguments` standardizes the executable
path as element zero, appends remaining argv strings, and caches the array.
`environment` builds a dictionary from `environ`, skips entries without `=`,
and caches an immutable copy. These paths match the target under normal
initialized argv and paths that fit the target's 1026-byte local buffer.

A fresh disassembly pass over `-[NSProcessInfo environment]` at `0x42533bc0`
confirms the delimiter behavior: the key ends at the first `=`, entries with
no `=` are skipped, and the value span begins after `=` and may have length
zero. The current source also retains empty values and permits an empty key.

`NSProcessInfo.m` now follows the target's direct `argv[0]` access and
unbounded appends into its 1026-byte path buffer. This preserves the target's
behavior when argv is malformed or a path exceeds that buffer, including the
same unchecked failure modes. Its shared path-copy helper also performs the
target's unconditional copy after allocation. The setters, host-name lookup,
user identity forwarding, platform map, operating-system value/name, and
deallocator also match the IDA bodies checked here.

The target's `_NSSearchForNameInPath` (`0x42585314`) scans PATH by temporarily
writing NUL over each colon in the environment string returned by
`_NSGetEnvironmentVariable`, then restores the colon before returning or
moving to the next component. `NSProcessInfo.m` now follows this split, lookup,
restore, and free sequence. This also preserves the target's brief in-place
mutation of the environment string during lookup. The null-argv and local
buffer-length differences described above remain unchanged.

## PowerPC cross-architecture recheck (2026-10-05)

Rechecked the same approved slice in the live MOSXS PowerPC Foundation database. `+[NSProcessInfo processInfo]` at `0x42527b18` has the same null-cache, default-zone allocation, initialization, cache-store, and return sequence as the i386 body above. `-[NSProcessInfo globallyUniqueString]` at `0x425623a8` likewise gates lock/unlock on `_NSTempFileCounterLock`, increments and resets the counter identically, rebuilds the prototype on nonpositive wrap, normalizes negative current time, and appends the decimal counter.

The PPC prototype construction calls host name, process name and its length, `_NSProcessID()`, and `_NSCurrentTime()`; it formats the same `host_pid_seconds_processNameLength_` shape, with an empty host fallback. The current `NSProcessInfo.m` implementation has those same inputs and ordering. The i386 pseudocode renders `_NSProcessID` as if two arguments were passed, while PPC renders it as a zero-argument call; this is a decompiler/call-site signature discrepancy only, since both target paths obtain the process identifier and the source helper wraps `getpid()` with no parameters. No source or ABI correction is indicated by this cross-architecture recheck.

## Globally unique string call-order correction (2026-10-07)

A raw-instruction recheck showed that the prototype's argument evaluation
order differs between targets, which the former nested Objective-C arguments
left to the compiler. i386 at `0x42581558` obtains the process name and its
length, calls `_NSProcessID()`, and only then allocates the prototype string.
PPC at `0x425623a8` allocates the prototype string first, calls
`_NSProcessID()`, then obtains the process name and its length. The code now
spells out these target-specific sequences before the shared
`initWithFormat:` call. The format inputs and lock/counter behavior are
unchanged. Static source review only; no build or tests were run.

## Argument string ownership (2026-10-07)

Rechecked `-[NSProcessInfo arguments]` in both target databases. The i386 body at
`0x4254dc3c` stores each `initWithCString:length:` result directly and releases
the temporary strings after `initWithObjects:count:`. The PPC body at
`0x42539884` sends `retain` to each initialized argument string before storing
it, then sends `release` during the same cleanup loop. PPC selector references
resolve through the method's TOC-relative selector slots to `paRetain` at
`0x4262cfe8` and `paRelease` at `0x4262cfe4`. `NSProcessInfo.m` now preserves
this PPC-only retain while leaving the i386 sequence unchanged.

The executable-path element uses different string factories as well. i386
calls `+[NSString stringWithCString:length:]` before
`-stringByStandardizingPath`; PPC allocates in the default zone and calls
`-initWithCString:length:` before standardizing. `NSProcessInfo.m` now preserves
that target split.

## Host-name accessor cross-target path (2026-10-07)

DR2 i386 `-[NSProcessInfo hostName]` at `0x4254dbf4` lazily stores
`[[NSHost currentHost] name]`. MOSXS PPC at `0x425419c4` lazily calls
`NSHostName()` and sends `retain` to the result before storing it. The
TOC-relative selector slot resolves to `paRetain` (`0x4262cfe8`, whose selector
string is `retain` at `0x426401c4`). The PPC setter's selector slot resolves to
`paAutorelease` (`0x4262cf98`), confirming that setter already matches the
i386 autorelease/copy sequence. `NSProcessInfo.m` now preserves these target
ownership differences.


## Accessor and platform dictionary parity (2026-10-07)

Paired IDA review confirms `userFullName`, `userHomeDirectory`, and `userName`
forward directly to `NSFullUserName`, `NSHomeDirectory`, and `NSUserName`
(i386 `0x4258174c`–`0x42581764`; PPC `0x42596f94`–`0x42596fd4`). Both
`operatingSystem` methods return 5 (i386 `0x42538de0`, PPC `0x425367c8`),
and `operatingSystemName` dispatches to the matching system-name constants.
`platformOSDictionary` lazily creates the same five-entry dictionary in both
images (i386 `0x4253e898`, PPC `0x4253731c`). Hex-Rays omitted i386's
variadic key/value stack arguments in pseudocode; the instruction stream shows
the complete entries and nil terminators, matching the current source. No code
change was indicated. Static paired IDA/source review only; no tests or builds
were run.
