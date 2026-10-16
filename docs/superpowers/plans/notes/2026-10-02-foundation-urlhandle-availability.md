# Foundation NSURLHandle target availability

Reference: Foundation i386 IDA database `6c2a913dc37a`.

The worktree's `NSURLHandle.m` is still a TODO skeleton, but this IDA target
has no named functions containing `NSURLHandle` and no indexed strings for
`NSURLHandle`, its HTTP property keys, or client callbacks. Related URL
support is present (`NSURL`, `NSAbsoluteURL`, and URL-based data/string
methods), but there is no `NSURLHandle` implementation body in this target to
decompile. This database therefore cannot ground an IDA-faithful
reconstruction of the class. Before implementing it, establish which binary
or source revision is the intended reference for this API.

## Current reconstruction-manifest check (2026-10-05)

The current Foundation ABI directory has no `NSURLHandle.json`, and the
`NSURL.json` manifest does not claim the adjacent resource-loading and
handle-delegation selectors that remain TODOs in `NSURL.m`. `NSURLHandle.m`
and `NSURLHandle.h` are listed in `PB.project`; the source-prelude list also
does not add the implementation as an extra `CLASSES` entry. This confirms
that the TODO API is not currently represented in the target ABI inventory.
Because the target IDA database likewise has no implementation bodies or
strings for it, these TODOs remain outside the evidence-supported
reconstruction scope until a matching reference revision is identified.

## Live IDA recheck (2026-10-05)

Rechecked the current `Foundation-i386` database (`703cb6287da7`) against the
remaining resource-loading selectors in `NSURL.m`: `resourceDataUsingCache:`,
`loadResourceDataNotifyingClient:usingCache:`, `propertyForKey:`,
`setResourceData:`, `setProperty:forKey:`, and `URLHandleUsingCache:`. The four
NSObject client callbacks in the same TODO block are also absent from IDA's
indexed strings. No public `NSURLHandle` symbol or resource-selector name was
found. The current `NSURL.json` still omits these methods and there is no
`NSURLHandle.json`. Together with the absent ABI entries, these checks leave no evidence of a
matching target implementation. Keep these methods outside the IDA-grounded
scope until a matching reference binary is identified.

## MOSXS PPC accessor reconstruction (2026-10-05)

A separate MOSXS PowerPC IDA database (`75ffa72daeee`) contains a live
`NSURLHandle` class with 20 instance selectors. This establishes target
evidence for the two accessors implemented in `NSURLHandle.m`:
`-[NSURLHandle status]` at `0x425b6898` has encoding `i4@4:8` and
returns the 32-bit `_status` ivar at offset 12;
`-[NSURLHandle availableResourceData]` at `0x425b65bc` has encoding
`@4@4:8` and returns nil when `_status` is
`NSURLHandleLoadFailed` (3), otherwise `_data` at offset 8. Both bodies
are guarded for PPC, and `reconstruction/abi-ppc/NSURLHandle.json`
records the class selectors, ivars, and 20-byte layout. The earlier
absence finding applies to the DR2 i386 database only.

## MOSXS PPC `failureReason` recheck (2026-10-05)

The live PPC IDA function at `0x425b68a8` sends `status` to `self`. If
the result is `NSURLHandleLoadFailed` (3), it returns the object pointer
stored at ivar offset 8 (`_data`) as an `NSString *`. Otherwise it calls
`NSLog` with `Handle %@ received message -failureReason when its status
was not NSURLHandleLoadFailed!` and returns nil. The attached DR2 i386
IDA database contains no `NSURLHandle` function or `failureReason`
selector. This is a PPC-only body; implementation remains subject to the
bounded design approval. This pass changed documentation only.

## MOSXS PPC load-flow decompilation (2026-10-05)

The load methods form a coordinated state machine, confirming that the
remaining TODOs should not be filled with isolated stubs.
`-[NSURLHandle resourceData]` (`0x425b65e0`) reads status first: state 1
returns available data, state 3 returns nil, and state 2 with no data
falls through to the foreground primitive. While state 2 remains after
data exists, it pumps the current run loop in the default mode with a
short deadline, then returns the available-data accessor result. For a
non-nil foreground result, `_data` is replaced and state 1 is set only if
`_data` was already non-nil; clients are notified whenever the load returns
data. For a nil result, the target failure string is built through the
bundle localization and string-formatting path. It replaces `_data` and
sets state 3 only when `_data` was already non-nil; clients are notified
even when that storage branch is skipped.
`-[NSURLHandle loadInForeground]` (`0x425b6c6c`) is an abstract
primitive and calls `_NSRequestConcreteImplementation`.
`backgroundLoadDidFailWithReason:` (`0x425b6d6c`) releases the current
`_data` and retains the reason before setting state 3, or sets state 0
when `_data` is nil; it then notifies every client.
`didLoadBytes:loadComplete:` (`0x425b6e4c`) snapshots non-null `_data`
through `dataWithData:`, releases the old value, stores the snapshot, and
sets state 1 when loading completes; completion with no accumulated data
sets state 0. Every call notifies clients that bytes are available, and
completed calls also
send the finish callback. These flows were read from live PPC IDA
pseudocode/disassembly; no source implementation changes were made.

## MOSXS PPC client and background-load control decompilation (2026-10-05)

`addClient:` (`0x425b6904`) lazily creates `_clients` as a mutable array
and adds the client; `removeClient:` (`0x425b6978`) removes the client
from that array. `loadInBackground` (`0x425b69b0`) logs and returns if
the handle is already in state 2; otherwise it performs the target
pre-start self call when the prior status is nonzero, calls the
subclass `beginLoadInBackground` primitive, sets state 2, then sends
the begin-loading callback to each client.
`cancelLoadInBackground` (`0x425b6a48`) acts only in state 2, invokes
the subclass end hook and the target cleanup/state call, then sends
the cancel callback to each client. The state call should be preserved
from the disassembly when implementing the cluster rather than inferred
from the selector name.
The base `beginLoadInBackground` (`0x425b6cc4`),
`endLoadInBackground` (`0x425b6d18`),
`propertyForKeyIfAvailable:` (`0x425b6b24`), and
`writeProperty:forKey:` (`0x425b6b7c`) all call
`_NSRequestConcreteImplementation`; their return values are nil or
false as appropriate. This extends the earlier load-flow evidence but
does not change source or approve an implementation design.

## MOSXS PPC registry, cache, and initializer decompilation (2026-10-05)

`+[NSURLHandle initialize]` (`0x425b61e0`) lazily creates its class
registry and registers `NSFileURLHandle` and `NSHTTPURLHandle`.
`registerURLHandleClass:` (`0x425b62a4`) inserts a subclass into that
registry. `URLHandleClassForURL:` (`0x425b6358`) scans the registered
classes in order and returns the first whose `canInitWithURL:` returns
true. The base `canInitWithURL:` is abstract and requests a concrete
implementation when sent to the base class.
`cachedHandleForURL:` (`0x425b63f8`) likewise traps when invoked on
the base class; on a concrete subclass it asks the registry for the
handler class and delegates the URL lookup to that class.
`initWithURL:cached:` (`0x425b64a0`) delegates initialization to
`super`, then initializes `_data` to a retained mutable-data object
when caching is enabled (otherwise nil), and clears `_clients` and
`_status`. `dealloc` (`0x425b6540`) releases and clears `_data` and
`_clients` before calling `super`. `flushCachedData`
(`0x425b6bd4`) cancels an active background load; otherwise it
releases the current data, replaces it with a new mutable buffer, and
resets status to zero. This establishes that registry/cache operations
are coupled to concrete handler classes and the load-state methods.
The analysis is PPC-only; no source implementation changes were made.

## MOSXS PPC file-URL handler decompilation (2026-10-05)

The PPC binary includes a concrete `NSFileURLHandle` implementation,
but the worktree has no source class for it.
`canInitWithURL:` (`0x425b416c`) obtains the URL path and delegates
the acceptance check to the target path/file helper.
`cachedHandleForURL:` (`0x425b41d8`) derives the path key, checks the
file-handler cache, and creates/registers a cached handler on a miss.
The initializer (`0x425b42ac`) delegates to the base initializer,
stores the URL path, and clears its file-handle ivar.
`loadInForeground` (`0x425b43dc`) opens the path for reading, reads
through end-of-file, closes the file handle, and returns the data.
`writeData:` (`0x425b4464`) writes the data atomically to the path and
flushes cached state on success. `propertyForKey:`
(`0x425b44c4`) lazily obtains file attributes, then returns the value
for the requested key. IDA strings confirm the concrete file APIs
used (`fileHandleForReadingAtPath:`, `readDataToEndOfFile`,
`closeFile`, `writeToFile:atomically:`, and
`fileAttributesAtPath:traverseLink:`). This is an additional new-source
class dependency for reconstructing the URL loading flow; no source
implementation changes were made.

## MOSXS PPC failure reason and cache flush reconstruction (2026-10-05)

Implemented the two confirmed base methods in `NSURLHandle.m`.
`failureReason` (`0x425b68a8`) returns `_data` only when `status` is
`NSURLHandleLoadFailed`; otherwise it logs the target diagnostic and
returns nil. `flushCachedData` (`0x425b6bd4`) cancels an in-progress
load. In other states, it replaces existing `_data` with a retained
empty `NSMutableData` and resets `_status` to not-loaded. Both source
bodies are guarded for PPC; the i386 branches remain unimplemented,
consistent with the absence of these methods in that target.

## MOSXS PPC HTTP URL-handler property and cancellation paths (2026-10-05)

`-[NSHTTPURLHandle propertyForKeyIfAvailable:]` (`0x425b529c`) reads
cached response headers and, when a redirect handle is present, uses
the target key-classification path to either return cached headers or
delegate the lookup. `writeProperty:forKey:` (`0x425b535c`) returns
false unconditionally. `endLoadInBackground` (`0x425b57ac`) delegates
to a redirect handle when present; otherwise it cancels the request for
the stored URL, closes the connection, and clears `_connection` when a
connection exists. These concrete handler methods depend on the missing
`NSHTTPURLHandle` source class.

The base methods are separate: `-[NSURLHandle
propertyForKeyIfAvailable:]` (`0x425b6b24`) and
`-[NSURLHandle writeProperty:forKey:]` (`0x425b6b7c`) call
`NSRequestConcreteImplementation` for `NSURLHandle`, then return nil
and false respectively.

## MOSXS PPC abstract property primitives implemented (2026-10-05)

Implemented `-[NSURLHandle propertyForKeyIfAvailable:]` (`0x425b6b24`)
and `-[NSURLHandle writeProperty:forKey:]` (`0x425b6b7c`) under PPC
guards. Both call `NSRequestConcreteImplementation(self, _cmd,
[NSURLHandle class])`, then return nil or false, matching the
decompiled base methods. The shared i386 implementation remains a
TODO, and the existing PPC ABI selector records were already present.

## MOSXS PPC HTTP request and redirect paths (2026-10-05)

`-[NSHTTPURLHandle propertyForKey:]` (`0x425b4fc8`) can issue a
synchronous request, return response data or a requested response
property, and create/delegate to a redirected handle for 300–399
responses. The path tracks cached headers and detects redirect loops.
`loadInForeground` (`0x425b5410`) delegates when already redirected;
otherwise it ensures a connection (using port 80 when absent), issues
the request, reads response data/status, and follows 300–399 redirects.
It returns nil for statuses above 399. `beginLoadInBackground`
(`0x425b5610`) similarly delegates to a redirect handle or creates a
connection/request and starts it with `self` as delegate; connection
creation failure is reported through the base background-failure path.
These request and redirect flows are interdependent and remain analysis
only; no HTTP concrete handler source exists in this worktree.

## MOSXS PPC background-load abstract hooks implemented (2026-10-05)

Implemented `-[NSURLHandle beginLoadInBackground]` (`0x425b6cc4`)
and `-[NSURLHandle endLoadInBackground]` (`0x425b6d18`) under PPC
guards. Each calls `NSRequestConcreteImplementation(self, _cmd,
[NSURLHandle class])`, matching the target body. The i386 branches
remain TODOs; both selector records were already present in the PPC
ABI manifest.

## MOSXS PPC remaining abstract primitive evidence (2026-10-05)

`-[NSURLHandle propertyForKey:]` (`0x425b6acc`) and
`-[NSURLHandle loadInForeground]` (`0x425b6c6c`) request a concrete
implementation for `NSURLHandle` and return nil. `-[NSURLHandle
writeData:]` (`0x425b6840`) makes the same request and returns false.
The corresponding selector encodings are already recorded in the PPC ABI
manifest. This records decompilation evidence only; source implementation
is pending approval.


## MOSXS PPC file-handler property and async-load paths (2026-10-05)

The remaining `NSFileURLHandle` methods show why this concrete class is a
separate reconstruction slice. `propertyForKeyIfAvailable:` (`0x425b4548`)
looks up the key in `_properties`. `writeProperty:forKey:` (`0x425b4580`)
serializes the property into a file attribute list, writes attributes for
`_path`, and replaces the cached properties dictionary when that cache exists
and the value changed. `beginLoadInBackground` (`0x425b46cc`) opens a file
handle, registers an asynchronous read completion with the run loop, and
reports a localized failure if opening fails. `endLoadInBackground`
(`0x425b47d8`) cancels the pending callback, closes the file handle, and clears
`_fh`. `flushCachedData` (`0x425b4840`) releases cached properties, clears the
ivar, and invokes the base flush. `_backgroundFileLoadCompleted:`
(`0x425b48b0`) extracts the completed read data, calls the base byte-completion
hook, closes the file handle, and clears `_fh`. The source tree has no
`NSFileURLHandle` class implementation; this trace remains analysis only.


## MOSXS PPC HTTP response callbacks (2026-10-05)

`redirectedHandleFromHeaders:` (`0x425b5828`) reads redirect-location
metadata, canonicalizes the resulting URL, and creates a redirected HTTP
handle, selecting cached or uncached creation according to the parent handle's
cache state. `receivedHeaders:forRequest:` (`0x425b5bb8`) branches on response
status: successful responses update cached headers, 300–399 responses create a
redirected handle and begin its load unless a loop is detected, and error or
out-of-range responses construct localized failure reasons. Failure paths close
and clear the connection. `receivedDataBlock:forRequest:finished:`
(`0x425b5950`) filters response blocks through the request/redirect state,
accumulates response or error-page bytes into cached header data, and refreshes
the cached header dictionary. `connectionFailedDuringRequest:`
(`0x425b5ec4`) localizes a connection error using the connection's failure
reason and sends it through `backgroundLoadDidFailWithReason:`.
`requestWasCancelled:` (`0x425b5f58`) is empty. These callbacks depend on
HTTP connection/request classes not present in the worktree; this is analysis
only.


## MOSXS PPC concrete handler initialization and teardown (2026-10-05)

`NSFileURLHandle` initialization (`0x425b42ac`) calls the base initializer,
stores a copied URL path, and initializes `_fh` to nil. Its deallocator
(`0x425b433c`) performs its class cache cleanup, releases `_path` and `_fh`,
and calls `super`. `NSHTTPURLHandle` initialization (`0x425b4d0c`) calls the
base initializer, canonicalizes and stores the URL, creates mutable response
headers only for cached handles, and clears `_connection` and
`_redirectedHandle`. Its deallocator (`0x425b4de4`) ends any background load,
releases `_url`, `_headers`, `_connection`, and `_redirectedHandle`, then calls
`super`. `+[NSHTTPURLHandle canonicalHTTPURLForURL:]` (`0x425b49d0`) rebuilds
a URL from its components, applying default HTTP port 80 and a default path
when absent. These lifecycle paths confirm both handlers own state beyond the
base class and need separate class implementations/ABI records.

## MOSXS PPC abstract base primitives (2026-10-05)

IDA confirms `-[NSURLHandle propertyForKey:]` (`0x425b6acc`),
`-[NSURLHandle writeData:]` (`0x425b6840`), and
`-[NSURLHandle loadInForeground]` (`0x425b6c6c`) call
`NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class])`, then return
nil, `NO`, and nil, respectively. The DR2 i386 Foundation function inventory
contains no `NSURLHandle` methods. The existing PPC ABI overlay records these
selectors and their encodings. The source now implements the PPC bodies and
keeps the i386 branches as TODOs.

## MOSXS PPC NSURLHandle base state-machine implementation (2026-10-05)

Implemented the remaining IDA-confirmed base flow in `NSURLHandle.m` under PPC
compiler guards: client registration/removal; background start and cancel;
foreground `resourceData`; background failure and byte-completion callbacks;
base initialization and teardown. Client callback paths snapshot `_clients`
before iterating where the target does so. The foreground wait pumps the
current run loop in `NSDefaultRunLoopMode` with IDA's 0.25-second deadline;
foreground failure uses the localized `Could not read from %@` message. The
cancel path calls `endLoadInBackground`, then `flushCachedData`, then sends the
cancel callback, matching the target call order. The PPC ownership map now
records the implemented selectors. i386 TODO branches and concrete file/HTTP
handlers remain outside this evidence-backed slice. No tests or builds were
run.

## PPC cancellation/flush call cycle recheck (2026-10-05)

A focused disassembly audit confirmed that `-[NSURLHandle cancelLoadInBackground]`
checks for state 2, calls `endLoadInBackground`, then calls
`flushCachedData`, then notifies clients. `flushCachedData` checks state 2 and
calls `cancelLoadInBackground`. The concrete file and HTTP `endLoadInBackground`
implementations (`0x425b47d8` and `0x425b57ac`) close/cancel their work and clear
handler ivars, but do not change the base `_status`. Thus the original PPC call
sequence forms a recursive cancellation/flush cycle for these handlers. The
reconstruction preserves the observed call sequence rather than adding an
unobserved status reset. This is an IDA-confirmed target defect and a runtime
risk in the reconstructed behavior; no tests or builds were run.

## MOSXS PPC abstract URL-handler predicate implemented (2026-10-05)

Implemented `+[NSURLHandle canInitWithURL:]` (`0x425b62e4`) as a PPC-only
abstract class method. IDA confirms it returns `NO` for `NSURLHandle` itself;
for a subclass that inherits the base implementation, it calls
`NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class])` before
returning `NO`. The existing i386 TODO remains because that target has no
matching `NSURLHandle` implementation. The PPC ABI selector record was already
present, and the selector now has an ownership entry. No tests or builds were
run.

## MOSXS PPC file-handler ABI and registry dependency recheck (2026-10-05)

Parsed the live Foundation `__OBJC` module records with the repository's
`binrecon.objc_abi` reader. The concrete class is defined in module
`NSFileURLHandle.m`, subclasses `NSURLHandle`, and has instance size 32 with
`_path` (`NSString *`) at offset 20, `_fh` (`NSFileHandle *`) at 24, and
`_properties` (`NSDictionary *`) at 28. The class record contains three class
selectors and eleven instance selectors. This confirms a separate PPC ABI
overlay and source-module registration are needed. At the time of this audit,
`NSURLHandle.m` still left `+registerURLHandleClass:`,
`+URLHandleClassForURL:`, and `+cachedHandleForURL:` as TODOs and has no
`+initialize`; implementing the file handler alone would leave its target
cache/registry path unreachable. No source behavior or ABI manifest was
changed.

## MOSXS PPC file-handler property and callback order recheck (2026-10-05)

Re-read the live bodies for `writeProperty:forKey:` (`0x425b4580`),
`beginLoadInBackground` (`0x425b46cc`), `endLoadInBackground`
(`0x425b47d8`), `flushCachedData` (`0x425b4840`), and
`_backgroundFileLoadCompleted:` (`0x425b48b0`). The property setter first
builds an attribute dictionary and writes it for `_path`; it then updates the
cached `_properties` copy only when the key's value differs. Background load
opens a file read handle, registers the handle notification with a run-loop
mode, and starts asynchronous reading; open failure reports a localized
reason through `backgroundLoadDidFailWithReason:`. End-load removes the
notification observer before closing and clearing `_fh`. Completion extracts
the notification's data item, removes the observer, calls
`didLoadBytes:loadComplete:` with completion set, then closes and clears the
file handle. Cache flush clears `_properties` before calling the base flush.
No source behavior or ABI manifest was changed.

## MOSXS PPC file-handler synchronous paths recheck (2026-10-05)

Live decompilation of `loadInForeground` (`0x425b43dc`), `writeData:`
(`0x425b4464`), `propertyForKey:` (`0x425b44c4`), and
`propertyForKeyIfAvailable:` (`0x425b4548`) fills out the file handler's
synchronous contract. Foreground read opens `_path`, returns nil if open fails,
otherwise reads to EOF, closes the handle, and returns the data. `writeData:`
uses `writeToFile:atomically:YES` and flushes the handle cache only on success.
`propertyForKey:` lazily copies file attributes from the default file manager
into `_properties`, then delegates to `propertyForKeyIfAvailable:`; the latter
is a direct dictionary lookup, including when `_properties` is nil. Together
with the cache/async paths above, this is a self-contained file handler over
existing Foundation APIs; the remaining integration dependency is the base
URL-handle registry. No source behavior or ABI manifest was changed.

## MOSXS PPC URL-handle registry recheck (2026-10-05)

Live decompilation confirms the missing class registry path. The base
`+[NSURLHandle initialize]` (`0x425b61e0`) first checks that its receiver is
exactly `NSURLHandle`; only then does it allocate and store the
registered-class array and register the built-in file and HTTP URL-handle
classes. This guard prevents subclass initialization from resetting the
shared registry.
`registerURLHandleClass:` (`0x425b62a4`) appends the class to that array.
`URLHandleClassForURL:` (`0x425b6358`) scans the array in registration order,
asks each class `canInitWithURL:`, and returns the first match or nil.
`cachedHandleForURL:` (`0x425b63f8`) is valid on `NSURLHandle` itself: it
selects the URL-specific class and calls that class's cache factory when a
handler is found, otherwise returning nil; a subclass using the inherited base
implementation triggers `NSRequestConcreteImplementation`. At the time of this
audit, the source still left registry initialization, registration, class
selection, and base cache selection as TODOs. This confirms that the
state-machine slice is implemented while the factory/registry path remains a
separate integration gap. No source changes, tests, or builds were made during
this registry audit.

## Registry source reconciliation (2026-10-07)

The preceding registry audit records the source state at the time of that
read. The current `NSURLHandle.m` now implements the recorded PPC path:
`+initialize` guards on the base class before registering the file and HTTP
handlers, `+registerURLHandleClass:` appends to the registry,
`+URLHandleClassForURL:` returns the first matching handler, and the base
`+cachedHandleForURL:` delegates to that handler or returns nil. The subclass
abstract-implementation path is preserved. i386 branches remain TODOs because
these selectors have no matching functions in the i386 IDA database. Source
and ABI state were reviewed statically; no tests or builds were run.


## PPC built-in HTTP handler path recheck (2026-10-07)

Compared the current `NSHTTPURLHandle.m` source with live PPC IDA for
`canonicalHTTPURLForURL:` (`0x425b49d0`), `cachedHandleForURL:`
(`0x425b4c44`), `inRedirectionLoop` (`0x425b4eb0`), `propertyForKey:`
(`0x425b4fc8`), `propertyForKeyIfAvailable:` (`0x425b529c`),
`loadInForeground` (`0x425b5410`), `beginLoadInBackground`
(`0x425b5610`), `redirectedHandleFromHeaders:` (`0x425b5828`),
`receivedDataBlock:forRequest:finished:` (`0x425b5950`),
`receivedHeaders:forRequest:` (`0x425b5bb8`), and
`connectionFailedDuringRequest:` (`0x425b5ec4`). The source preserves the
canonical host/port/path construction, redirect cache behavior, loop check,
HTTP status ranges, lowercase property lookup, error-page data accumulation,
background request wiring, and localized failures. `NSURLHandle -resourceData`
(`0x425b65e0`) also matches the source's cached-status checks, run-loop wait,
foreground load, state update, and client callbacks; its `data` local is assigned
from `loadInForeground` before use. No code change was indicated. Static
PPC IDA/source comparison only; no tests or builds were run.


## PPC built-in file handler path recheck (2026-10-07)

Compared the current `NSFileURLHandle.m` source with live PPC IDA for
`canInitWithURL:` (`0x425b416c`), `cachedHandleForURL:` (`0x425b41d8`),
`loadInForeground` (`0x425b43dc`), `writeData:` (`0x425b4464`),
`propertyForKey:` (`0x425b44c4`), `propertyForKeyIfAvailable:`
(`0x425b4548`), `writeProperty:forKey:` (`0x425b4580`),
`beginLoadInBackground` (`0x425b46cc`), `endLoadInBackground`
(`0x425b47d8`), `flushCachedData` (`0x425b4840`), and
`_backgroundFileLoadCompleted:` (`0x425b48b0`). The source follows the target's
file URL predicate, standardized-path cache key, foreground read/close order,
atomic write and conditional cache flush, lazy attribute cache, property update
order, background notification registration, open-failure callback, and
completion callback/close order. No code change was indicated. Static PPC
IDA/source comparison only; no tests or builds were run.

## PPC HTTP connection queue and dispatch recheck (2026-10-08)

Re-read PPC IDA for `sendRequestSynchronously:headers:` (`0x425b15e4`),
`enqueueRequest:forClient:` (`0x425b17f4`), `handlePortMessage:`
(`0x425b1f20`), and the background `processRequests:` method (`0x425b2300`).
The current source matches the synchronous condition assignment and run-loop
wait, request-identity lookup in the completed synchronous records, and
retained/autoreleased result handling. Enqueueing inserts synchronous jobs
after earlier synchronous jobs and appends asynchronous jobs; the first queued
work creates the receive port, installs its invalidation observer, registers
the port with the run loop, and detaches the worker. Port callbacks drain the
completed-message list and dispatch failure, data, header, and task-completion
messages. The worker drains requests in order, separately catches connect and
write failures, reports failure or fetches the response, closes the socket,
then signals task completion. No source mismatch was identified in this pass.
Static PPC IDA/source review only; no tests or builds were run.

## Current-tree implementation status recheck (2026-10-09)

The earlier statement that PPC `NSURLHandle` abstract-method implementation
was pending approval is historical and superseded. `NSURLHandle.m` now
implements the PPC `NSRequestConcreteImplementation` diagnostics and fallback
returns; `NSFileURLHandle.m`, `NSHTTPURLHandle.m`, and `NSHTTPConnection.m`
contain the approved built-in loading path. The current gap audit records the
paired source/IDA reviews. The i386 TODO branches remain because the DR2 i386
image has no corresponding URL-handle method bodies. Static source/audit
review only; no tests or builds were run.
