# Foundation `NSConcretePortCoder` selector reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSPortCoder.json`, and current
`NSPortCoder.m` / `NSThread.m`.

## Confirmed selectors

IDA confirms these previously missing `NSConcretePortCoder` methods:

- `+[NSConcretePortCoder _enableLogging:]` at `0x42566cc0` increments or
  decrements the coder logging counter.
- `+[NSConcretePortCoder allocWithZone:]` at `0x42524b44` takes a coder from
  the main cache slot and then three overflow slots under
  `_NSPortCoderCacheLock`; on a miss it allocates the class with zero extra
  bytes in the default zone. A reused coder records an allocation event.
- `-[NSConcretePortCoder encodeBycopyObject:]` at `0x42545d08` forwards to
  `encodeObject:isBycopy:isByref:` with flags `YES, NO`.
- `-[NSConcretePortCoder encodeByrefObject:]` at `0x42567430` forwards with
  flags `NO, YES`.
- `-[NSConcretePortCoder sendBeforeDate:]` at `0x425675c0` converts the date
  to reference-time seconds and calls `sendBeforeTime:`.
- `-[NSConcretePortCoder versionForClassName:]` at `0x4252d85c` forwards to
  the connection's `versionForClassNamed:`.

The coder's existing `dealloc` at `0x4252176c` completes the bounded cache
lifecycle. It invalidates and releases the connection, frees owned stream
storage, then caches the coder if one of four slots is free. When all slots are
occupied it releases both component arrays and deallocates normally. It records
a deallocation event only when the coder is retained in the cache. The cache
lock is created in `_NSToDoAtFirstThreadStart` at `0x425547f8`.

The `_enableLogging:` counter is read at the coder's object encode/decode,
Mach-message initialization, and send sites. The source now emits the IDA
confirmed messages there, including the nil-object and decoded-object reports.

## `debugDescription` class/instance mismatch

`+[NSConcretePortCoder debugDescription]` at `0x42566ce8` is class-side in both
the Mach-O symbol and Objective-C method metadata. The method record is the
sixth entry in the class-method list at `0x4260d788`; its type encoding is
`@8@8:12`, and its implementation pointer is `0x42566ce8`.

A disassembly recheck confirms the method directly loads from its first
argument (`self`): a pointer at offset 4, pointers at offsets 44, 48, 52, and
56, and signed bytes at offsets 60, 61, and 62. It passes those values to
`NSString stringWithFormat:` with the format:

`conn: %@; comps: %@; imported: %@; compIdx = %d; msgid = 0x%x; bycopy = %d; byref = %d; isvalid = %d;\n`

Those offsets exactly match the `NSConcretePortCoder` instance ivars
`connection`, `components`, `importedObjects`, `componentIndex`, `msgid`,
`isBycopy`, `isByref`, and `isValid` in the ABI ivar manifest. The evidence
therefore establishes an actual target-side receiver/layout mismatch: the
class method reads instance-shaped fields from the class object passed as
`self`. This is not a decompiler-only type inference. The source preserves the
reads by viewing the class receiver through the coder's instance layout, so
calls on the class object retain the target's potentially invalid metadata
reads.

## Class-record cross-check (2026-10-04)

The class method list pointer at `0x4260d788` is stored at offset 28 of the
`NSConcretePortCoder` class record at `0x4260bc8c`; the record's name pointer
at offset 8 resolves to the `NSConcretePortCoder` name string, and its instance
size field is 40 bytes. The method's first pointer load at `self+4` therefore
reads the class record's superclass field. Later loads at `self+44` and
`self+48` extend beyond the class record into adjacent Objective-C metadata;
the raw image contains pointers to the `NSMutableData` and `NSStreamData` name
strings at those positions. This confirms that the class-side call does not
address an allocated coder instance. Runtime relocation/interpretation of those
raw metadata values is not established by the static IDA database.

## Current implementation status

The six confirmed methods above and the bounded coder cache lifecycle are
implemented. `+[NSConcretePortCoder debugDescription]` is now implemented with
the format string and raw field reads confirmed by disassembly. The global
selector audit and whitespace check were rerun after this change. No tests or
builds were run.