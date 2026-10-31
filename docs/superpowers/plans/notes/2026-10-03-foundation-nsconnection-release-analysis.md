# Foundation `NSConnection` released-proxy analysis

Reference: project Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSConnection.json`, and
`src/Kits/Foundation/NSConnection.m`.

## Missing release-handling methods

The ABI lists four NSConnection instance methods that have no definitions in
the current source: `_cleanupAndAuthenticate:sequence:conversation:invocation:raise:`,
`getReleasedProxies:length:`, `handleReleasedProxies:length:`, and
`decodeReleasedProxies:`. IDA confirms these bodies:

- `getReleasedProxies:length:` at `0x42528b08` returns the result of sending
  `decodeBytesWithReturnedLength:` to its coder, passing through the caller's
  length pointer.
- `handleReleasedProxies:length:` at `0x42528a38` returns immediately for a
  null byte pointer or zero length. Otherwise it decodes successive 4-byte
  values from the byte stream in pairs, treats the pair as a local proxy name
  and release count, gets the local proxy by name, and sends it
  `_releaseWireCount:` with that count. Logging, when enabled, prints the two
  values. The target does not add a separate alignment or divisibility check
  before decoding each pair.
- `decodeReleasedProxies:` at `0x425296ac` obtains the released-proxy bytes
  and returned length through the first helper, then passes both to the
  second helper.
- `_cleanupAndAuthenticate:sequence:conversation:invocation:raise:` at
  `0x4254ff94` decodes one object value, decodes the released-proxy byte
  stream, then authenticates when the connection's authentication flag is
  set. On success it processes the releases and releases the supplied
  invocation, returning `YES`. On authentication failure it optionally sends
  an exception result when `raise` is true, releases the invocation, and
  returns `NO`.

The failure reply uses exception name `NSFailedAuthenticationException` and
reason `*** Received message without authentication` (constant-string objects
at `0x42605d14` and `0x42605edc`). Optional release logging uses
`piggybacked [0x%x _releaseWireCount:%u]` (`0x42605ed0`).

The selectors and encodings are recorded in `NSConnection.json`. Source
already has the nearby `_releaseWireCount:` and `getLocal:` operations that
these routines call. This is a connected protocol-cleanup gap: a source
reconstruction should keep byte decoding, authentication, release counts,
invocation ownership, and the optional exception reply in this order.

`-[NSConnection description]` at `0x425679d8` is also absent under that exact
class owner. The reference returns a short formatted representation while the
connection's active flag is clear; when active, it builds a mutable
description containing endpoint, retain-count, proxy-count, and object-list
information. The indirect format constants resolve to these exact literals:

- inactive: `connection 0x%x is invalid`
- active prefix: `(**NSConnection receivePort %@ sendPort %@ refCount %d\n`
- remote proxy count: `%d remote ids\n`
- local proxy count: `\n%d local ids\n`
- active suffix: `\n**)\n`

The active path gets `remoteObjects` and `localObjects`, and appends the
respective counts from `remoteProxies` and `localProxies`. The disassembly
resolves the object-list sequence: it obtains each array's `description`,
gets the mutable string's current `length`, then sends
`replaceCharactersInRange:withString:` with a zero-length range at that offset
and the object-list description. The same range-insertion sequence appends
the final suffix. `-[NSConnection description]` is now implemented with those
operations and the exact reference formats. The active branch returns the
initialized mutable string directly, preserving the reference's ownership
behavior. No tests or builds were run.

## Queued-request helper selector audit follow-up (2026-10-03)

The Foundation i386 selector audit reports `-[NSConnection _hasRequestDelegate]`
as a source extra, not a binary selector. The current source defines it as a
wrapper around the `doRequest` bit and calls it from
`NSConnectionHandleQueuedRequest`. IDA's `_NSHandleDORequest` at `0x4256a560`
reads the connection flag byte at offset 16 directly, invokes the delegate
when that bit is set, and otherwise dispatches the invocation. Thus the source
preserves the decision but adds a selector absent from the target ABI. The
same selector audit reports `-[NSConnection description]` as a binary method
was missing in source. It is now defined, and the current selector audit no
longer lists it as missing. The full Foundation audit still reports unrelated
gaps. No tests or builds were run.

## Queued-request selector parity correction (2026-10-04)

IDA rechecked `__NSHandleDORequest` at `0x4256a560`: it reads the cached
request-delegate bit directly from the `NSConnection` flag word at byte offset
16, then invokes the delegate when set. On a caught delegate exception, the
reference logs `Error occured in delegate connection:handleRequest:\n` and
continues into normal invocation dispatch. The source's `_hasRequestDelegate`
method only returned that same bit and was absent from the target selector
table. It has been removed; the C request handler now reads `doRequest`
through a local layout matching the leading ivars and flag order in
`NSConnection.h`. The source now logs the same exception message before
continuing into dispatch. Delegate invocation, exception scope, dispatch
fallback, conversation cleanup, and reply handling otherwise match the
reference. The selector audit now reports this helper as removed from source
extras. No tests or builds were run.

The same selector audit also identified `-[NSThread existingWorkQueue]` as a
source-only helper. IDA's `+[NSConnection doQueuedWork]` at `0x42518c60`
loads the thread's queue pointer directly from offset 28 while holding the
work-queue lock, then messages that pointer. The source now reads `doQueue`
through a local `NSThread` layout matching the ivar prefix in `NSThread.h`;
the extra getter declaration and implementation were removed. This preserves
the target's nil-queue behavior without allocating a queue during inspection.
After both source-only selectors were removed, the full selector audit reports
3,253 reference selectors, zero missing, renamed, or duplicate selectors, and
62 source extras. The C-symbol source audit reports 249 of 249 reference
symbols defined. No tests or builds were run.

## Released-proxy source verification (2026-10-03)

The four methods from the released-proxy design are now defined in
`NSConnection.m` at lines 577-629. The source declarations match the ABI
manifest's Objective-C encodings at the type level: `char *`/`*`,
`unsigned *`/`^I`, `unsigned`/`I`, and `BOOL`/`c`. The current whole-module
selector audit reports no rename or duplicate and lists none of these four
selectors as missing or extra. `git diff --check` is clean for the runtime
source and this note. No tests or builds were run; compiled-object ABI
verification remains unavailable under the project's no-build constraint.

## Released-proxy integer encoding correction (2026-10-03)

A direct recheck of `-[NSConnection handleReleasedProxies:length:]` at
`0x42528a38` found that each pair is not two fixed-width 4-byte values. The
method calls `_decodeFastInt` (`0x42517540`) twice with a decoded width of four
bytes. Its stream cursor advances by a signed one-byte length prefix followed
by the encoded payload bytes; negative lengths sign-extend with `0xff`.

The matching sender path, `-[NSConnection releaseName:count:]` at `0x42567fe4`,
calls `serializeDataAt:ofObjCType:"I"` for both the proxy name and count.
`-[NSMutableData serializeDataAt:ofObjCType:context:]` (`0x42575e94`) routes
the `I` values through `_encodeFastInt` (`0x42513fa8`), which writes the same
signed-length format after removing redundant high-order zero or `0xff` bytes.
The current source had paired fixed-width `memcpy` reads with `serializeInt:`
writes; both sides have now been corrected to use the IDA-confirmed compact
encoding. The decoder raises `NSRangeException` with reason
`more significant bytes than room to hold them` when a negative prefix exceeds
the four-byte width. Source also rejects oversized positive prefixes before
copying; the binary decoder does not bound that malformed case and would write
past its output value.

No tests or builds were run.

## Sender call-path fidelity follow-up (2026-10-03)

The typed Objective-C serialization methods are now implemented in the current
`NSSerialization.m`. `-[NSConnection releaseName:count:]` now calls
`serializeDataAt:ofObjCType:"I" context:nil` for both fields, following the
IDA call path instead of duplicating `_encodeFastInt` in `NSConnection.m`.
The local fast-integer encoder was removed; the released-proxy decoder remains
local because IDA decodes directly from the raw byte buffer. Static selector
and whitespace checks only; no tests or builds were run.

## Released-proxy PPC cross-architecture verification (2026-10-05)

The PPC target confirms the compact integer path. In `-[NSConnection handleReleasedProxies:length:]` at `0x42521fd0`, the callback table is loaded through `_NSFastFuncList_ptr` (`0x42626d78`). Its function list begins at `0x426263ac`; the entry at offset `0x14` is `0x42510b70`, the PPC `_decodeFastInt`. The handler calls that entry twice with a four-byte destination, so both proxy name and release count use the same signed-length-prefixed compact decoding as i386.

The PPC sender `-[NSConnection releaseName:count:]` at `0x4256185c` sends the typed serialization selector twice, once for the proxy name and once for the count, using the same type-string argument. PPC `_encodeFastInt` at `0x4250d0e8` performs the corresponding signed-width reduction and prefix write. This confirms the previously corrected source path across both architectures; no source change was needed. Static IDA verification only; no tests or builds were run.
