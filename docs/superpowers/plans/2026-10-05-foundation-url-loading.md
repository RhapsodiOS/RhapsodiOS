# PPC Foundation URL Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct the MOSXS PPC Foundation URL loading path so `NSURL` can select and use the target's built-in file and HTTP handlers.

**Architecture:** Add the target's private HTTP request, socket, connection, file-handler, and HTTP-handler classes as focused modules. Complete the base `NSURLHandle` registry/cache path and connect the new modules through the target APIs, then reconcile PPC ABI and project metadata.

**Tech Stack:** Objective-C Foundation sources, legacy Project Builder metadata, PPC Objective-C ABI JSON, IDA decompilation notes.

**Spec:** `docs/superpowers/specs/2026-10-05-foundation-url-loading-design.md`

## Global Constraints

- This is a PPC-only reconstruction. Preserve current i386 fallback branches and shared ABI surface.
- Match PPC class sizes, ivar offsets, selectors, and encodings extracted from the reference image.
- Preserve observed target control flow, including the base background-cancel/flush recursion; do not silently add a status reset.
- Use existing Foundation collection, string, data, port, run-loop, file, and locking APIs where IDA shows those calls; do not add a separate networking abstraction.
- Do not alter unrelated source or metadata already modified in the worktree.
- Runtime tests/builds are outside this reconstruction's current verification scope. Verify source against IDA bodies, validate ABI/metadata JSON, and run `git diff --check` only.

## Review Focus

- **Unsupported URL scheme or no matching handler:** verify ordered class selection returns the first accepting handler and nil if none accepts.
- **File open failure or a missing file:** compare the localized failure path and no-data state against `NSFileURLHandle` IDA bodies.
- **Redirect loops and HTTP error statuses:** compare redirect creation, loop detection, localized failure, and connection cleanup against `NSHTTPURLHandle` IDA bodies.
- **Partial headers, chunk framing, and bytes after a response boundary:** verify `NSHTTPConnection` header/body parsing and `NSHTTPSocket` surplus-byte handling match the target.
- **Cancellation while a background load is active:** verify the target call sequence, including its recursive cancel/flush behavior, remains intact.

---

### Task 1: Add the HTTP request model and serializer

**Files:**
- Create: `src/Kits/Foundation/NSHTTPRequest.h`
- Create: `src/Kits/Foundation/NSHTTPRequest.m`
- Create: `src/Kits/Foundation/reconstruction/abi-ppc/NSHTTPRequest.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
- Reference: `docs/superpowers/plans/notes/2026-10-02-foundation-urlhandle-availability.md`
- Reference: `docs/superpowers/plans/notes/2026-10-05-foundation-url-loading-abi-inventory.md`

**Interfaces:**
- Consumes: `NSURL`, `NSMutableDictionary`, `NSMutableArray`, `NSData`, `NSString`, and the existing URL component/string conversion APIs used by the target.
- Produces: target `NSHTTPRequest` selectors `initWithMethod:URL:`, `dealloc`, `addHeader:value:`, `setData:`, `serializedRequest`, `requestMethod`, `URL`, `_client`, `_setClient:`, `fetchesURL:`, `_condition`, and `_setCondition:` with encodings from the PPC Objective-C module record.

- [x] **Step 1: Add the private request class declaration** with target instance size 32 and ivars `_req`, `_url`, `_headers`, `_headerOrder`, `_data`, `_client`, and `_condition` at offsets 4, 8, 12, 16, 20, 24, and 28, respectively.
- [x] **Step 2: Implement target ownership, request matching, and ordered-header behavior**: copy method and URL; append a header key to order only on its first insertion; replace duplicate values in the dictionary; retain/release body and client as the target does; make `fetchesURL:` match only `GET` requests whose URL equals the supplied URL.
- [x] **Step 3: Implement request serialization** with the target path fallback, request-line syntax, insertion-ordered headers, header terminator, optional body, and target string-to-byte conversion.
- [x] **Step 4: Add the PPC ABI record and selector ownership entries** from the target module metadata; preserve the inventory's finding that this module defines no additional C symbols.
- [x] **Step 5: Compare each request method with its IDA body and validate `NSHTTPRequest.json`** using `python -m json.tool src/Kits/Foundation/reconstruction/abi-ppc/NSHTTPRequest.json > $null`.

### Task 2: Add the HTTP socket transport

**Files:**
- Create: `src/Kits/Foundation/NSHTTPSocket.h`
- Create: `src/Kits/Foundation/NSHTTPSocket.m`
- Create: `src/Kits/Foundation/reconstruction/abi-ppc/NSHTTPSocket.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
- Reference: the target socket decompilation in `docs/superpowers/plans/notes/2026-10-02-foundation-urlhandle-availability.md` and ABI record in `docs/superpowers/plans/notes/2026-10-05-foundation-url-loading-abi-inventory.md`.

**Interfaces:**
- Consumes: existing BSD socket APIs and Foundation `NSData`, as called by the target.
- Produces: `NSHTTPSocket` with target instance size 12, `_socket` at offset 4, and `_surplusBytes` at offset 8; selectors `initWithSocket:`, `+descriptorWithStreamSocket`, `dealloc`, `connectToHost:withPort:`, `readAvailableData:`, `writeData:`, and `returnSurplusBytes:`.

- [x] **Step 1: Implement `NSHTTPSocket` descriptor ownership**: create an IPv4 stream socket, resolve/connect the target host and port, close on deallocation, and preserve the target localized resolution/connect failures.
- [x] **Step 2: Implement socket writes and reads**: loop until all request bytes are sent and raise on `send <= 0`; for reads, use 4096 when the requested length is zero, return nil on EOF, return empty data on target errno 35, and raise the target error otherwise; return and clear saved surplus before receiving more, and append newly returned surplus after existing bytes.
- [x] **Step 3: Add the PPC ABI record and selector ownership entries**; preserve the inventory's finding that this module defines no additional C symbols.
- [x] **Step 4: Compare every socket method with IDA, validate `NSHTTPSocket.json`, and run `git diff --check`** for this task's changes.

### Task 3: Add the HTTP connection and request queue

**Files:**
- Create: `src/Kits/Foundation/NSHTTPConnection.h`
- Create: `src/Kits/Foundation/NSHTTPConnection.m`
- Create: `src/Kits/Foundation/reconstruction/abi-ppc/NSHTTPConnection.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
- Reference: Tasks 1–2, the connection/category decompilation in `docs/superpowers/plans/notes/2026-10-02-foundation-urlhandle-availability.md`, and `docs/superpowers/plans/notes/2026-10-05-foundation-url-loading-abi-inventory.md`.

**Interfaces:**
- Consumes: Task 1's `NSHTTPRequest` selectors, Task 2's `NSHTTPSocket` selectors, and existing `NSHost`, `NSLock`, `NSConditionLock`, `NSRunLoop`, `NSPort`, `NSPortMessage`, and `NSThread` APIs.
- Produces: `NSHTTPConnection` with target instance size 44 and its ten ivars at offsets 4 through 40. Implement target selectors `+initialize`, `+cachedConnectionForHost:port:`, `+connectionForHost:port:`, `initWithHost:port:`, `host`, `remotePortNumber`, `sendRequestSynchronously:headers:`, `enqueueRequest:forClient:`, `cancelRequest:`, `cancelFetchOfURL:`, `receivedHeaders:forRequest:`, `receivedDataBlock:forRequest:finished:`, `connectionFailedDuringRequest:`, `requestWasCancelled:`, `handlePortMessage:`, `portBecameInvalid:`, and `_nextSynchCondition`. Implement category selectors `processRequests:`, `_findCRLF:length:`, `fetchHeadersForRequest:connectionDied:`, `enrichedHeadersFromHeaders:andStatus:`, `numberDataBytesForRequest:withHeaders:`, `fetchResponseForRequest:`, `signalMessage:`, `signalTaskCompletion`, `signalConnectionFailureForRequest:`, `signalDataBlock:forRequest:finished:`, and `signalHeaders:complete:forRequest:`.

- [x] **Step 1: Implement the host/port connection cache and request state**: use the target lock, initialize the ten ivars and collection/condition objects, place synchronous jobs before asynchronous jobs, allocate an unused condition by checking all target queues, and pump `NSDefaultRunLoopMode` until the synchronous response record is ready.
- [x] **Step 2: Implement port delivery and cancellation**: reproduce client-message kinds 0–5, linked-list enqueue/drain, dispatch outside the lock, sync completion signaling, queued-request removal, cancellation callbacks, connection failure callbacks, and port invalidation recovery.
- [x] **Step 3: Implement response parsing and background processing**: reproduce worker setup/teardown, request serialization and socket lifecycle, CRLF/header parsing, continuation lines and surplus handoff, content-length/transfer handling, HEAD/status body rules, response normalization, 512-byte-bounded partial reads, connection-death handling, and final data-block completion.
- [x] **Step 4: Add the PPC class/category ABI record and selector ownership entries**; preserve the inventory's finding that this module defines no additional C symbols.
- [x] **Step 5: Compare every connection and category method with IDA, validate `NSHTTPConnection.json`, and run `git diff --check`** for this task's changes.

### Task 4: Implement the file URL handler and base registry

**Files:**
- Create: `src/Kits/Foundation/NSFileURLHandle.h`
- Create: `src/Kits/Foundation/NSFileURLHandle.m`
- Create: `src/Kits/Foundation/reconstruction/abi-ppc/NSFileURLHandle.json`
- Modify: `src/Kits/Foundation/NSURLHandle.m`
- Modify: `src/Kits/Foundation/reconstruction/abi-ppc/NSURLHandle.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
  - Reference: `docs/superpowers/plans/notes/2026-10-02-foundation-urlhandle-availability.md` and `docs/superpowers/plans/notes/2026-10-05-foundation-url-loading-abi-inventory.md`

**Interfaces:**
- Consumes: existing `NSURLHandle` state hooks, `NSURL` path access, `NSFileHandle`, `NSFileManager`, and mutable collections. Use forward declarations for the file and HTTP concrete handler classes in the base registry.
- Produces: `NSFileURLHandle` with target instance size 32, `_path` at offset 20, `_fh` at 24, and `_properties` at 28; class selectors `+initialize`, `+canInitWithURL:`, `+cachedHandleForURL:`; instance selectors `initWithURL:cached:`, `dealloc`, `loadInForeground`, `writeData:`, `propertyForKey:`, `propertyForKeyIfAvailable:`, `writeProperty:forKey:`, `beginLoadInBackground`, `endLoadInBackground`, `flushCachedData`, and `_backgroundFileLoadCompleted:`. Complete base selectors `+initialize`, `+registerURLHandleClass:`, `+URLHandleClassForURL:`, and `+cachedHandleForURL:`.

- [x] **Step 1: Implement the file-handler predicate, cache factory, initializer, and deallocator** using path acceptance, path-keyed reuse, the target per-class cache, and target ownership.
- [x] **Step 2: Implement synchronous file operations**: read through EOF and close; write atomically and flush only on success; lazily load file attributes and update attributes/cache using the target APIs.
- [x] **Step 3: Implement file background loading** with the target `NSFileHandle` read notification and run-loop registration, localized open failure, cancellation cleanup, and completion callback order.
- [x] **Step 4: Complete `NSURLHandle` registry integration**: initialize the array only for `NSURLHandle`, register file then HTTP, append registrations, scan in order, and dispatch base `cachedHandleForURL:` to the selected handler class. Do not add registry locking.
- [x] **Step 5: Add the file-handler PPC ABI record and update base/file selector ownership**; keep the shared/i386 ABI manifest unchanged.
- [x] **Step 6: Compare each implemented file/base method with IDA, validate both ABI JSON files, and run `git diff --check`** for this task's changes.

### Task 5: Implement the HTTP URL handler

**Files:**
- Create: `src/Kits/Foundation/NSHTTPURLHandle.h`
- Create: `src/Kits/Foundation/NSHTTPURLHandle.m`
- Create: `src/Kits/Foundation/reconstruction/abi-ppc/NSHTTPURLHandle.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
  - Reference: Tasks 1–3, `docs/superpowers/plans/notes/2026-10-02-foundation-urlhandle-availability.md`, and `docs/superpowers/plans/notes/2026-10-05-foundation-url-loading-abi-inventory.md`.

**Interfaces:**
- Consumes: `NSURLHandle` base hooks, Task 1 request methods, Task 3 connection methods/callback protocol, and Task 4 registry.
- Produces: `NSHTTPURLHandle` with target instance size 36 and `_url`, `_headers`, `_connection`, and `_redirectedHandle` at offsets 20, 24, 28, and 32; class selectors `+initialize`, `+canonicalHTTPURLForURL:`, `+canInitWithURL:`, `+cachedHandleForURL:`; instance selectors `initWithURL:cached:`, `dealloc`, `writeData:`, `_URL`, `_redirectedHandle`, `inRedirectionLoop`, `propertyForKey:`, `propertyForKeyIfAvailable:`, `writeProperty:forKey:`, `flushCachedData`, `loadInForeground`, `beginLoadInBackground`, `endLoadInBackground`, `redirectedHandleFromHeaders:`, `receivedDataBlock:forRequest:finished:`, `receivedHeaders:forRequest:`, `connectionFailedDuringRequest:`, `requestWasCancelled:`, `URLHandle:resourceDataDidBecomeAvailable:`, `URLHandleResourceDidBeginLoading:`, `URLHandleResourceDidFinishLoading:`, `URLHandleResourceDidCancelLoading:`, `URLHandle:resourceDidFailLoadingWithReason:`, and `didLoadBytes:loadComplete:`.

- [x] **Step 1: Implement canonical URL construction and cache lifecycle** with target HTTP port/path defaults, canonical URL cache keys, cached-only mutable response headers, and target init/dealloc cleanup.
- [x] **Step 2: Implement synchronous/background requests and cancellation** using `NSHTTPRequest` and `NSHTTPConnection`; preserve cache choice, connection lifecycle, request conditions, and base state callbacks from IDA.
- [x] **Step 3: Implement response properties and error-page data** with target 200–299 success, 300–399 redirect, 400–599 error, and out-of-range status routing; preserve cached-header behavior, status/reason normalization, 599 fallback, localized errors, and error-page data.
- [x] **Step 4: Implement redirects and connection callbacks** with `Location` then `location` lookup, target URL canonicalization, cached/uncached redirected-handle creation, loop detection and localized reason, redirected loading, data filtering, terminal callbacks, and connection cleanup. Preserve the confirmed callback details: begin-loading is a no-op; finish reports a nil final block; cancel notifies current clients; failure calls the base failure hook; uncached redirects are released on finish, cancel, and failure before the redirect reference is cleared.
- [x] **Step 5: Add the PPC ABI record and selector ownership entries**; preserve the inventory's finding that this module defines no additional C symbols and keep shared/i386 ABI unchanged.
- [x] **Step 6: Compare every HTTP-handler selector with IDA, validate the ABI JSON, and run `git diff --check`** for this task's changes.

### Task 6: Register and reconcile the complete PPC URL-loading path

**Files:**
- Modify: `src/Kits/Foundation/PB.project`
- Modify: `src/Kits/Foundation/Makefile.preamble`
- Modify: `src/Kits/Foundation/reconstruction/abi-ppc/NSURL.json` only if target metadata requires a correction
- Modify: `src/Kits/Foundation/reconstruction/abi-ppc/NSURLHandle.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
  - Review: `src/Kits/Foundation/reconstruction/symbols.json` (the new modules have no target-confirmed C symbols)
- Modify: `src/Kits/Foundation/reconstruction/divergences.md`
  - Reference: `docs/superpowers/plans/notes/2026-10-05-foundation-url-loading-abi-inventory.md`

**Interfaces:**
- Consumes: all five new classes and completed `NSURLHandle` registry from Tasks 1–5.
- Produces: project/source registration for every new module; complete PPC ABI, ownership, symbol, and architecture-divergence records; a source path from `NSURL` to both built-in handlers.

- [x] **Step 1: Register all five `.m` files in `PB.project` and `Makefile.preamble`** and all five headers in the Project Builder header table; leave generated `Makefile` edits to Project Builder regeneration.
- [x] **Step 2: Reconcile metadata against the PPC Objective-C and symbol tables**: confirm every class/category size, ivar, selector, encoding, and ownership source; confirm the reference modules add no module-level C symbols; do not add PPC records to shared/i386 ABI files.
- [x] **Step 3: Record the PPC-only class availability and any remaining evidence-backed divergence** in `divergences.md`, including the documented cancellation/flush recursion.
- [x] **Step 4: Validate every changed JSON file with `python -m json.tool <path> > $null`, compare the complete five-class path and registry with IDA, and run `git diff --check`**. Do not run tests or builds in this plan.

### File-handler property write recheck (2026-10-06)

The PPC `-[NSFileURLHandle writeProperty:forKey:]` body always sends
`setObject:forKey:` to the temporary attributes dictionary and, when the
cached properties differ, to its mutable copy. The source had a nil-specific
`removeObjectForKey:` branch in both places. Those branches are removed so a
nil value follows the target's dictionary call behavior. The cached-property
replacement order matches IDA. The temporary attributes payload and its
creation order were corrected in the follow-up below. Static source checks
only; no tests or builds were run.

### File attribute write payload correction (2026-10-07)

Rechecking `-[NSFileURLHandle writeProperty:forKey:]`'s call arguments showed
the disk write uses an `NSDictionary` initialized with only the requested
value/key pair, created before obtaining `NSFileManager`'s default manager.
The source had copied all cached attributes into a mutable dictionary and
written that full set. `NSFileURLHandle.m` now uses the one-entry dictionary
and target call order; cached-property mutation remains conditional on the
existing cached value differing by identity. No tests or builds were run.

### Synchronous redirect cache recheck (2026-10-06)

The PPC selector slots in `loadInForeground` and `propertyForKey:` resolve to
`release`, not `flushCachedData`. For uncached redirects, both methods release
the redirected handle and clear `_redirectedHandle` after retrieving the
redirected result; neither flushes the handle. Their redirection-loop paths
return nil without calling `backgroundLoadDidFailWithReason:`. The source now
follows those calls and cleanup paths. Static source checks only; no tests or
builds were run.

### Redirected handler class dispatch (2026-10-06)

PPC IDA for `-[NSHTTPURLHandle redirectedHandleFromHeaders:]` obtains the
receiver's class, uses it for canonicalization and cached-handle lookup, and
allocates/initializes an uncached redirected handler through that same class.
The source's concrete `NSHTTPURLHandle` class references are replaced with
`[self class]` dispatch. No tests or builds were run.

### Redirected cancel and failure callback cleanup (2026-10-06)

PPC IDA for `-[NSHTTPURLHandle URLHandle:resourceDidFailLoadingWithReason:]`
sends `backgroundLoadDidFailWithReason:` to the current handle. If the handle
is uncached (`_headers == nil`), it then sends `release` to
`_redirectedHandle` and clears the ivar; it does not forward the failure
callback. `URLHandleResourceDidCancelLoading:` likewise notifies the current
handle's clients, then releases and clears the redirected handle instead of
forwarding cancellation. The source now matches both cleanup paths. No tests
or builds were run.

### URL fetch cancellation ownership (2026-10-06)

PPC IDA for `-[NSHTTPConnection cancelFetchOfURL:]` retains the matching
queued request only through the `_newJobs` array while the lock is held, then
unlocks and calls `cancelRequest:` without an extra retain/release pair. The
source now matches that call sequence.

### HTTP connection failure reasons (2026-10-06)

PPC IDA strings and call arguments confirm that a failed connection creation
uses the localized `Could not connect to host %@` key with the URL host, while
an established connection failure uses `Lost connection to host %@` with the
connection description. Both lookups use the `URL` table. The two source paths
now use those distinct keys and arguments. No tests or builds were run.

### Background connection guard (2026-10-06)

PPC IDA for `-[NSHTTPURLHandle beginLoadInBackground]` forwards to an existing
redirected handle, otherwise it enters connection setup and request enqueueing
only when `_connection` is nil. If a connection already exists, the target
returns without creating another request. The source now has that early return.
No tests or builds were run.

### HTTP URL canonicalization recheck (2026-10-06)

PPC IDA for `+[NSHTTPURLHandle canonicalHTTPURLForURL:]` first obtains the
absolute URL, lowercases its host, defaults a missing port to the number 80,
and uses `_relativeURLPath` with `/` only when that path is nil. It parses the
absolute string's path and fragment ranges, appends the raw suffix after the
path while excluding a nonempty fragment, and creates the canonical `http`
URL. The source now follows those operations through
`_NSParseStringToGenericURLComponents`. No tests or builds were run.

### Redirect loop tracking collection (2026-10-06)

PPC IDA for `-[NSHTTPURLHandle inRedirectionLoop]` starts a retained ordered
collection with the receiver URL's `absoluteURL`, walks redirected handles,
checks each absolute URL with `indexOfObject:` against `NSNotFound`, and adds
new entries. It releases the collection on both return paths. The source's
autoreleased `NSMutableSet` and `containsObject:` traversal is replaced with
that array flow. No tests or builds were run.

### Unknown HTTP status diagnostic recheck (2026-10-06)

PPC `-[NSHTTPURLHandle receivedHeaders:forRequest:]` logs
`Received unknown HTTP server response %@: %@` with the URL and status reason
before creating and reporting the localized unknown-status failure. The exact
log literal is present in the PPC string table at `0x42622940`. The source now
emits that diagnostic in the target order. Static source checks only; no tests
or builds were run.

The same PPC branch sends `-_setCondition:` with `0` to the request after the
failure callback; the selector is confirmed in the target string table at
`0x4264964c`. `receivedHeaders:forRequest:` now signals that completion in the
same order. Static source checks only; no tests or builds were run.

### Response data state check (2026-10-06)

PPC `-[NSHTTPURLHandle receivedDataBlock:forRequest:finished:]` sends
`-status` to the URL handle and forwards bytes through `didLoadBytes:` only
when the result is `2`. The base `NSURLHandle` sets `2` for
`NSURLHandleLoadInProgress` immediately after `beginLoadInBackground` returns.
The source instead inferred this branch from the HTTP status code and a special
uncached case. It now follows the handle-state check; the error-page path
remains for non-progress states with cached headers. Static source checks only;
no tests or builds were run.

### Partial error-page data key and completion (2026-10-06)

PPC `receivedDataBlock:forRequest:finished:` stores unfinished error bodies
under `_NSErrorPageInProgress` (constant string at `0x42622870`). When the
body finishes, it copies the accumulated bytes to
`NSHTTPPropertyErrorPageDataKey` and removes the progress key. A one-block
finished body is stored directly under the public error-page key. The source
now follows these keys, append behavior, and completion transition. Static
source checks only; no tests or builds were run.

### Foreground response-header caching (2026-10-06)

PPC IDA for `-[NSHTTPURLHandle loadInForeground]` at `0x425b5410` reads the
response status, handles redirects and errors, and returns the response data
for successful statuses. It does not merge the response headers into the
cached `_headers` dictionary. The source's extra merge is removed. No tests or
builds were run.

### HTTP redirect cache selectors (2026-10-06)

PPC IDA confirms `flushCachedData` releases `_redirectedHandle` before clearing
it. Its selector is `release`, not `flushCachedData`. In
`propertyForKeyIfAvailable:`, the redirect special case compares against
`NSHTTPPropertyRedirectionHeadersKey` with `isEqualToString:` and returns the
local headers only when the dictionary is nonempty; other keys forward to the
redirected handle. `NSHTTPURLHandle.m` now follows those paths. No tests or
builds were run.

### Synchronous HTTP header record ownership (2026-10-06)

PPC IDA for `-[NSHTTPConnection receivedHeaders:forRequest:]` at `0x425B1B80`
creates a record with `alloc` / `initWithObjectsAndKeys:`, adds it to
`_synchCompletedJobs` while `_lock` is held, unlocks `_lock`, then releases the
local record ownership. It does not signal `_synchLock` in this method. The
source now follows that allocation, collection-retain, and release sequence.
Static source checks only; no tests or builds were run.

### HTTP data callback condition ordering (2026-10-06)

PPC IDA for `-[NSHTTPConnection receivedDataBlock:forRequest:finished:]` at
`0x425B1C64` acquires `_lock` before reading the request condition and checks
that the data object is nonnil before reading its length. The source previously
read the condition before locking and sent `length` to nil. It now matches the
target ordering and guard. Static source checks only; no tests or builds were
run.

### HTTP port invalidation dispatch (2026-10-06)

PPC IDA for `-[NSHTTPConnection portBecameInvalid:]` at `0x425B21BC` replaces
the invalid port, restores its delegate and run-loop registration, unlocks
`_lock`, then invokes `handlePortMessage:` with nil. The source previously
called `enqueueRequest:forClient:` with a nil request. It now dispatches through
the target selector. Static source checks only; no tests or builds were run.

### HTTP socket host-name encoding selector (2026-10-06)

PPC IDA for `-[NSHTTPSocket connectToHost:withPort:]` at `0x425B37A0` sends
`cString` to the host name before calling `gethostbyname`. The source used
`UTF8String`; it now uses the selector present in the target body. Static
source checks only; no tests or builds were run.

### File URL path normalization recheck (2026-10-07)

PPC IDA for `+[NSFileURLHandle cachedHandleForURL:]` keys the registry by
`[[[url absoluteURL] path] stringByStandardizingPath]`. The initializer stores
`[[url standardizedURL] path]` with retain ownership. Source previously used
`[url path]` for both, which mishandled relative bases and left cache keys
unstandardized. `NSFileURLHandle.m` now follows the two target call sequences.
No tests or builds were run.

### File URL handle deallocation observer cleanup (2026-10-07)

PPC IDA for `-[NSFileURLHandle dealloc]` sends `defaultCenter` to
`NSNotificationCenter`, then `removeObserver:` with `self`. It does not remove
the handle from `fileURLHandleCache`. The source now follows that observer
cleanup sequence before releasing `_path` and `_fh`.

### HTTP redirect-property comparison selector (2026-10-07)

PPC IDA for `-[NSHTTPURLHandle propertyForKey:]` resolves the special
`NSHTTPPropertyRedirectionHeadersKey` comparison to `isEqualToString:`. The
source used `isEqual:`; it now sends the target selector. No tests or builds
were run.

### Redirect finish callback ownership recheck (2026-10-07)

PPC IDA for `-[NSHTTPURLHandle URLHandleResourceDidFinishLoading:]`
(`0x425b5fac`) calls `release` on `_redirectedHandle` when `_headers` is nil,
then clears the ivar. Source previously called `flushCachedData` and cleared
the ivar without releasing its retain. The callback now follows the target
ownership sequence. No tests or builds were run.

### URL handle client callback and dispatch recheck (2026-10-08)

Re-decompiled PPC `-[NSURL loadResourceDataNotifyingClient:usingCache:]`
(`0x425aef38`) and the five URL-handle client callbacks
(`0x425af418`–`0x425af7b0`) against the current `NSURL.m`. The status 0–3
branches, optional client-selector checks, `_clients` map creation and
insertion, partial-data forwarding, per-handle client snapshot, callback
order, map removal, handle detachment, and empty-map free match the target.
`URLHandleResourceDidBeginLoading:` is a no-op on both sides. No source change
was needed. Static paired IDA/source review only; no tests or builds were run.

