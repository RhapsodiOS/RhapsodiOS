# Foundation PPC URL Loading ABI Inventory

Reference image: `C:\Users\raynorpat\Downloads\test\Frameworks\Foundation.framework\Versions\C\Foundation`

Architecture: PPC, big-endian. Image size: 1,811,940 bytes. SHA-256:
`332B3C8C0AE0A6E40A4B93110EE16748FCD94AA0119D63F16EDE878598C681B4`.

The records below were extracted from the image's `__OBJC` metadata with
`binrecon.objc_abi.read_modules_from_sections`, using the PPC symbol table to
resolve selectors whose prebound selector pointers lie outside the image.
Selectors use the exact Objective-C encoding strings stored in the target.

## `NSHTTPRequest.m`

Class `NSHTTPRequest`, superclass `NSObject`, instance size 32:

| Ivar | Type | Offset |
| --- | --- | ---: |
| `_req` | `NSString *` | 4 |
| `_url` | `NSURL *` | 8 |
| `_headers` | `NSMutableDictionary *` | 12 |
| `_headerOrder` | `NSMutableArray *` | 16 |
| `_data` | `NSData *` | 20 |
| `_client` | `id` | 24 |
| `_condition` | `int` | 28 |

| Selector | Encoding |
| --- | --- |
| `initWithMethod:URL:` | `@12@4:8@12@16` |
| `dealloc` | `v4@4:8` |
| `addHeader:value:` | `v12@4:8@12@16` |
| `setData:` | `v8@4:8@12` |
| `serializedRequest` | `@4@4:8` |
| `requestMethod` | `@4@4:8` |
| `URL` | `@4@4:8` |
| `_client` | `@4@4:8` |
| `_setClient:` | `v8@4:8@12` |
| `fetchesURL:` | `c8@4:8@12` |
| `_condition` | `i4@4:8` |
| `_setCondition:` | `v8@4:8i12` |

## `NSHTTPSocket.m`

Class `NSHTTPSocket`, superclass `NSObject`, instance size 12:

| Ivar | Type | Offset |
| --- | --- | ---: |
| `_socket` | `unsigned int` | 4 |
| `_surplusBytes` | `NSData *` | 8 |

| Selector | Encoding |
| --- | --- |
| `initWithSocket:` | `@8@4:8I12` |
| `dealloc` | `v4@4:8` |
| `connectToHost:withPort:` | `v12@4:8@12I16` |
| `readAvailableData:` | `@8@4:8I12` |
| `writeData:` | `v8@4:8@12` |
| `returnSurplusBytes:` | `v8@4:8@12` |
| `+descriptorWithStreamSocket` | `@4@4:8` |

`descriptorWithStreamSocket` at `0x425b36c4` creates an IPv4 stream socket,
initializes the receiver with its descriptor, and autoreleases the socket
wrapper. `connectToHost:withPort:` at `0x425b37a0` resolves the host name with
`gethostbyname`, builds an IPv4 `sockaddr`, and connects using the supplied
port. Resolution and connection failures raise `NSGenericException`
with the localized target messages `Can't determine IP address of host: %@.`
and `Can't connect to host %@ using port %d`. Read/write failures other than
the read-side errno 35 case raise `NSFileHandleOperationException` with the
target `recv: %s` or `send: %s` format and `_NSErrnoMessage()` text.

## `NSHTTPConnection.m`

Class `NSHTTPConnection`, superclass `NSObject`, instance size 44:

| Ivar | Type | Offset |
| --- | --- | ---: |
| `_port` | `NSPort *` | 4 |
| `_host` | `NSHost *` | 8 |
| `_remotePort` | `unsigned int` | 12 |
| `_lock` | `NSLock *` | 16 |
| `_newJobs` | `NSMutableArray *` | 20 |
| `_completedJobs` | `void *` | 24 |
| `_currentSynchCondition` | `int` | 28 |
| `_synchCompletedJobs` | `NSMutableArray *` | 32 |
| `_synchLock` | `NSConditionLock *` | 36 |
| `_socket` | `NSHTTPSocket *` | 40 |

Class methods:

| Selector | Encoding |
| --- | --- |
| `initialize` | `v4@4:8` |
| `cachedConnectionForHost:port:` | `@12@4:8@12I16` |
| `connectionForHost:port:` | `@12@4:8@12I16` |

Instance methods:

| Selector | Encoding |
| --- | --- |
| `initWithHost:port:` | `@12@4:8@12I16` |
| `host` | `@4@4:8` |
| `remotePortNumber` | `I4@4:8` |
| `sendRequestSynchronously:headers:` | `@12@4:8@12^@16` |
| `enqueueRequest:forClient:` | `v12@4:8@12@16` |
| `cancelRequest:` | `v8@4:8@12` |
| `cancelFetchOfURL:` | `v8@4:8@12` |
| `receivedHeaders:forRequest:` | `v12@4:8@12@16` |
| `receivedDataBlock:forRequest:finished:` | `v13@4:8@12@16c20` |
| `connectionFailedDuringRequest:` | `v8@4:8@12` |
| `requestWasCancelled:` | `v8@4:8@12` |
| `handlePortMessage:` | `v8@4:8@12` |
| `portBecameInvalid:` | `v8@4:8@12` |
| `_nextSynchCondition` | `i4@4:8` |

Category `NSHTTPConnectionBackgroundThread` on `NSHTTPConnection`:

| Selector | Encoding |
| --- | --- |
| `processRequests:` | `v8@4:8@12` |
| `_findCRLF:length:` | `*12@4:8*12I16` |
| `fetchHeadersForRequest:connectionDied:` | `@12@4:8@12^c16` |
| `enrichedHeadersFromHeaders:andStatus:` | `@12@4:8@12@16` |
| `numberDataBytesForRequest:withHeaders:` | `I12@4:8@12@16` |
| `fetchResponseForRequest:` | `v8@4:8@12` |
| `signalMessage:` | `v8@4:8^{?=I@@^{_NSHTTPConnectionClientMessage}}12` |
| `signalTaskCompletion` | `v4@4:8` |
| `signalConnectionFailureForRequest:` | `v8@4:8@12` |
| `signalDataBlock:forRequest:finished:` | `v13@4:8@12@16c20` |
| `signalHeaders:complete:forRequest:` | `v16@4:8@12c16@20` |

## `NSFileURLHandle.m`

Class `NSFileURLHandle`, superclass `NSURLHandle`, instance size 32:

| Ivar | Type | Offset |
| --- | --- | ---: |
| `_path` | `NSString *` | 20 |
| `_fh` | `NSFileHandle *` | 24 |
| `_properties` | `NSDictionary *` | 28 |

| Selector | Encoding |
| --- | --- |
| `+initialize` | `v4@4:8` |
| `+canInitWithURL:` | `c8@4:8@12` |
| `+cachedHandleForURL:` | `@8@4:8@12` |
| `initWithURL:cached:` | `@9@4:8@12c16` |
| `dealloc` | `v4@4:8` |
| `loadInForeground` | `@4@4:8` |
| `writeData:` | `c8@4:8@12` |
| `propertyForKey:` | `@8@4:8@12` |
| `propertyForKeyIfAvailable:` | `@8@4:8@12` |
| `writeProperty:forKey:` | `c12@4:8@12@16` |
| `beginLoadInBackground` | `v4@4:8` |
| `endLoadInBackground` | `v4@4:8` |
| `flushCachedData` | `v4@4:8` |
| `_backgroundFileLoadCompleted:` | `v8@4:8@12` |

## File URL Handler Cache and Loading

`+[NSFileURLHandle initialize]` at `0x425b4118` initializes the per-class
cache. `canInitWithURL:` at `0x425b416c` requires a URL scheme and compares
it to `file` with the target case-insensitive string option. The cached
factory at `0x425b41d8` uses the URL path as its cache key; on a miss it
creates a cached handle, inserts it under that path, and starts background
loading. `initWithURL:cached:` calls the base initializer, stores a copy of
the URL path, and initializes `_fh` to nil. `dealloc` removes the receiver
from `NSNotificationCenter`, releases `_path` and `_fh`, then calls the base
deallocator.

`loadInForeground` at `0x425b43dc` asks `NSFileHandle` for a read handle at
`_path`, returns nil if opening fails, otherwise reads to EOF, closes the
handle, and returns the data. `writeData:` at `0x425b4464` writes atomically
to `_path`; only a successful write calls `flushCachedData`.

`propertyForKey:` at `0x425b44c4` lazily loads file attributes when
`_properties` is nil, stores a copied dictionary, then reads through
`propertyForKeyIfAvailable:`. The latter simply queries `_properties`.
`writeProperty:forKey:` at `0x425b4580` copies current properties into a
mutable dictionary, applies the requested key/value, asks `NSFileManager` to
change the file attributes at `_path`, and releases the temporary dictionary.
If cached properties exist and the target value differs, it updates the
cached immutable copy too; the method returns the file-manager success flag.

`beginLoadInBackground` at `0x425b46cc` opens `_fh` for reading if none is
open, registers `_backgroundFileLoadCompleted:` for the target file-handle
read-completion notification, and requests a background read. Open failure
uses the Foundation bundle's localized file-open reason and reports it through
`backgroundLoadDidFailWithReason:`. `endLoadInBackground` at `0x425b47d8`
removes this observer, closes `_fh`, and clears the ivar. `flushCachedData`
at `0x425b4840` releases and clears cached attributes before calling the base
flush. `_backgroundFileLoadCompleted:` at `0x425b48b0` extracts the data from
the completion notification, removes the notification observer, calls
`didLoadBytes:loadComplete:` with completion true, then closes and clears
`_fh`.

## `NSHTTPURLHandle.m`

Class `NSHTTPURLHandle`, superclass `NSURLHandle`, instance size 36:

| Ivar | Type | Offset |
| --- | --- | ---: |
| `_url` | `NSURL *` | 20 |
| `_headers` | `NSDictionary *` | 24 |
| `_connection` | `NSHTTPConnection *` | 28 |
| `_redirectedHandle` | `NSHTTPURLHandle *` | 32 |

Class methods:

| Selector | Encoding |
| --- | --- |
| `initialize` | `v4@4:8` |
| `canonicalHTTPURLForURL:` | `@8@4:8@12` |
| `canInitWithURL:` | `c8@4:8@12` |
| `cachedHandleForURL:` | `@8@4:8@12` |

Instance methods:

| Selector | Encoding |
| --- | --- |
| `initWithURL:cached:` | `@9@4:8@12c16` |
| `dealloc` | `v4@4:8` |
| `writeData:` | `c8@4:8@12` |
| `_URL` | `@4@4:8` |
| `_redirectedHandle` | `@4@4:8` |
| `inRedirectionLoop` | `c4@4:8` |
| `propertyForKey:` | `@8@4:8@12` |
| `propertyForKeyIfAvailable:` | `@8@4:8@12` |
| `writeProperty:forKey:` | `c12@4:8@12@16` |
| `flushCachedData` | `v4@4:8` |
| `loadInForeground` | `@4@4:8` |
| `beginLoadInBackground` | `v4@4:8` |
| `endLoadInBackground` | `v4@4:8` |
| `redirectedHandleFromHeaders:` | `@8@4:8@12` |
| `receivedDataBlock:forRequest:finished:` | `v13@4:8@12@16c20` |
| `receivedHeaders:forRequest:` | `v12@4:8@12@16` |
| `connectionFailedDuringRequest:` | `v8@4:8@12` |
| `requestWasCancelled:` | `v8@4:8@12` |
| `URLHandle:resourceDataDidBecomeAvailable:` | `v12@4:8@12@16` |
| `URLHandleResourceDidBeginLoading:` | `v8@4:8@12` |
| `URLHandleResourceDidFinishLoading:` | `v8@4:8@12` |
| `URLHandleResourceDidCancelLoading:` | `v8@4:8@12` |
| `URLHandle:resourceDidFailLoadingWithReason:` | `v12@4:8@12@16` |
| `didLoadBytes:loadComplete:` | `v9@4:8@12c16` |

These five modules define Objective-C classes/categories but no additional
module-level C text or data symbols in the reference image. The current shared
i386 ABI inventory does not contain these classes; add only PPC overlay
records when implementing them.

## HTTP Handler Cache, Properties, and Lifecycle

`+[NSHTTPURLHandle initialize]` at `0x425b495c` creates the class cache only
when initialization is running for `NSHTTPURLHandle` itself. The cache key in
`cachedHandleForURL:` is the canonicalized URL. That factory returns an
existing cached handle when present; otherwise it creates a cached handle and
stores it under the canonical key. `initWithURL:cached:` invokes the base
initializer, stores a copy of the canonicalized URL, initializes the
connection and redirect ivars to nil, and creates a mutable headers dictionary
only for cached handles. `dealloc` ends background loading, releases the URL,
headers, connection, and redirected handle, then calls the base deallocator.

`+[NSHTTPURLHandle canInitWithURL:]` at `0x425b4bdc` requires a URL scheme and
compares it against `http` using the target case-insensitive string comparison.
`+[NSHTTPURLHandle canonicalHTTPURLForURL:]` at `0x425b49d0` returns nil when
the input has no absolute string. Otherwise it normalizes the URL components,
defaults a missing port to 80, uses target fallbacks for absent host/path
components, strips a fragment from the path source, and returns the target URL
object for the rebuilt string. The observed format strings are
`http://%@:%@%@` and `http://%@:%@%@%@`; preserve which path/suffix branch
selects each format as shown in the IDA body.

`writeData:` at `0x425b4e80` and `writeProperty:forKey:` at `0x425b535c` are
stubs that return false. `propertyForKeyIfAvailable:` at `0x425b529c` reads
from `_headers` when there is no redirect, and otherwise routes ordinary
properties to the redirected handle while retaining the local status/header
dictionary path for the target status property. `propertyForKey:` at
`0x425b4fc8` triggers foreground loading when the requested property is not
already available, then follows the target response-status and redirect path;
the precise status routing is recorded above. `flushCachedData` at
`0x425b536c` calls the base flush, clears cached response headers when present,
flushes the redirected handle, and clears `_redirectedHandle`.

`endLoadInBackground` at `0x425b57ac` delegates to the redirected handle when
one exists. Otherwise, if `_connection` exists, it asks the connection to
cancel the fetch for `_url`, releases the connection, and clears the ivar.
`requestWasCancelled:` at `0x425b5f58` is an empty method. `writeData:` and
`writeProperty:forKey:` therefore remain unsupported by the HTTP handler.

The retain/release ownership is balanced at the URL-handler boundary:
`loadInForeground` (`0x425b5410`) and `beginLoadInBackground`
(`0x425b5610`) both send `retain` to the result of
`+[NSHTTPConnection connectionForHost:port:]` before storing `_connection`.
`endLoadInBackground` releases that retained reference after canceling the
URL fetch. This matters because `connectionForHost:port:` can return a cached
connection or an autoreleased newly created connection. The current
`NSHTTPURLHandle.m` assignments and teardown match this flow.

## Request serialization and response body length

`-[NSHTTPRequest serializedRequest]` at `0x425b3e04` obtains the URL's absolute
string and calls `_NSParseStringToGenericURLComponents` to obtain its path. If
the parser reports no path, the method uses `/`; the PPC constant string at
`0x4262c924` points to the one-byte string at `0x42620188`. The method formats
the request line with the format `"%@ %@ HTTP/1.0\r\n"`, iterates
`_headerOrder`, looks up each value in `_headers`, appends the header lines in
that order, and appends the header/body separator. It encodes the serialized
string with `NSISOLatin1StringEncoding` and lossy conversion enabled. With nil
`_data`, it returns those serialized bytes; with non-nil `_data`, it creates
mutable data from them, appends the body bytes, and returns the combined data.
Initialization copies the
method and URL, creates empty mutable headers/order collections, and sets
`_data` to nil and `_condition` to -1. `addHeader:value:` inserts the key into
`_headerOrder` only when the dictionary has no value for it, then sets the
dictionary value. `setData:` retains its argument before releasing the
previous data. `_setClient:` likewise retains the new client before releasing
the old one. `fetchesURL:` returns true only when the request method matches
the target comparison string and the supplied URL equals `_url`.

The comparison string in `fetchesURL:` is `GET`: the PPC body at
`0x425b407c` forms the address of the `NSConstantString` object at
`0x4262c954`, whose character pointer is `0x42622854` and length is 3. The
method then returns false for any other request method; for `GET`, it returns
the result of comparing the supplied URL with `_url`. This predicate is used
by URL-based cancellation, not by the response body-length calculation.

`-[NSHTTPConnection numberDataBytesForRequest:withHeaders:]` at `0x425b2ff0`
returns zero for `HEAD`, all status codes from 100 through 199, and statuses
204 and 304. For other responses it parses the `Content-Length` header when
present (the target lookup key is lowercase `content-length`); if that header
is absent, it returns `0x7fffffff` as the unknown-size
sentinel.

`-[NSHTTPConnection fetchHeadersForRequest:connectionDied:]` at `0x425b261c`
reads in 512-byte chunks under the target exception-handler path. It scans the
accumulated bytes for CRLF-delimited lines, recognizes the header/body
separator, handles continuation lines, and parses the status line and header
fields. Bytes after the boundary are returned to `NSHTTPSocket` as surplus for
the response-body reader. A malformed status line returns the unconsumed
buffer to the socket as surplus, sets the connection-died out parameter to
false, releases the temporary collections, and returns nil. A malformed
header field without a colon is logged and skipped; parsing continues.

### HTTP header folding and value trimming (2026-10-06)

The PPC body appends a continuation line to its previous header value exactly
as received, including its leading whitespace. It does not insert a normalized
space or remove the first continuation character. A header value is formed
from the text after the colon and has all leading members of the cached
`whitespaceAndNewlineCharacterSet` removed; an all-whitespace value becomes an
empty string. Header lines are created with `initWithCString:length:`, using
the default C-string encoding. `NSHTTPConnection.m` now follows those rules,
skips logged colonless fields, and returns the remaining buffer to the socket
when the first status line is malformed. Static checks only; no tests or builds
were run.

## Socket read/write and response delivery

`-[NSHTTPSocket readAvailableData:]` at `0x425b38e0` first autoreleases the
stored `_surplusBytes` object and clears the ivar. If there is no surplus and
the requested length is zero, it requests 4096 bytes. It calls `recv` once: zero
bytes frees the temporary buffer and returns nil; a negative result with
`errno == 35` returns the target empty `NSData`; any other negative result
raises using the target errno message. A positive result becomes an `NSData`
with the received length and frees the temporary allocation. It does not wait
for the requested size to be filled.

`-[NSHTTPSocket writeData:]` at `0x425b3a14` advances through the data's byte
buffer until its remaining length reaches zero. `send` returning zero or less
raises the target errno-based error. `returnSurplusBytes:` at `0x425b3acc`
retains the first returned object; when surplus already exists, it creates a
mutable data object from the old surplus, appends the newly returned bytes,
copies that into `_surplusBytes`, and releases the temporaries.

The current `NSHTTPSocket.m` source was rechecked against these PPC bodies on
2026-10-07. Its one-call `recv`, 4096-byte zero-length default, errno-35 empty
data result, partial-send loop, and surplus-byte ownership match IDA. No source
change, tests, or builds were made in this recheck.

`-[NSHTTPConnection fetchResponseForRequest:]` at `0x425b30ec` gets parsed
headers and the expected body-byte count. A response marked as connection-died
signals either request failure or task completion according to whether headers
exist and whether the parsed size is zero. Otherwise, it forwards headers,
reads body chunks no larger than 512 bytes (or the remaining known size),
reduces the remaining count without underflow, and forwards received data
blocks. Once the socket returns nil or the known body length reaches zero, it
sends the target final data-block callback with completion set.

## Connection queue, worker, and client delivery

`-[NSHTTPConnection enqueueRequest:forClient:]` at `0x425b17f4` assigns the
request's client before taking the queue lock. When the client is the
connection itself (the synchronous path), it inserts the request before the
first queued request whose client is not the connection; other requests append
to the end. It unlocks before lazily creating the reply port, assigning the
connection as delegate, registering the port with the run-loop path, and
starting the request worker.

`-[NSHTTPConnection processRequests:]` at `0x425b2300` repeatedly locks the
queue, removes the first request, and unlocks before doing network work. For
each request it replaces the worker autorelease pool, creates an
`NSHTTPSocket`, connects to `_host` and `_remotePort`, serializes and writes
the request, then fetches the response. The connect and write stages each have
their own target exception-handler frame; an exception signals request
failure, while a successful write proceeds to response parsing. The socket is
closed and cleared after either result. Once the queue is empty, the worker
signals task completion and drains its autorelease pool.

`-[NSHTTPConnection handlePortMessage:]` at `0x425b1f20` drains a linked list
of pending client messages. It removes each list head while holding `_lock`,
then unlocks before dispatching the message to its client. Unknown message
kinds take the target log-and-free path. This keeps client callbacks outside
the connection lock.

## Synchronous response records and signaling

`-[NSHTTPConnection sendRequestSynchronously:headers:]` at `0x425b15e4`
allocates a condition with `_nextSynchCondition`, stores it on the request, and
enqueues the request with the connection as its client. It repeatedly tries to
acquire `_synchLock` for that condition. Between failed attempts it runs the
current run loop in `NSDefaultRunLoopMode` with the target short-date deadline. Once
the lock reaches that condition, the caller resets it to `-1`, searches
`_synchCompletedJobs` for the record associated with this request, removes the
record under `_lock`, and returns its body data while writing its response
headers through the out parameter. Missing records produce nil headers/data.

`_nextSynchCondition` at `0x425b0fb0` increments `_currentSynchCondition`.
When incrementing would make it negative, it wraps the counter and searches
candidate values against the synchronous requests in `_newJobs`, `_completedJobs`,
and `_synchCompletedJobs`, returning the first unused condition. If no value is
available, it logs the target diagnostic and follows the target decrement path.

`receivedHeaders:forRequest:` at `0x425b1b80` creates a synchronous completion
record from the parsed headers and request, appends it to
`_synchCompletedJobs` under `_lock`, then signals the record's condition.
`receivedDataBlock:forRequest:finished:` at `0x425b1c64` ignores requests
whose condition was reset to `-1`; otherwise it appends non-nil bytes to the
matching record under `_lock`. A finished block performs the target
`NSConditionLock` transition so the synchronous waiter can acquire its
condition and read the completed record.

Rechecked the current `NSHTTPConnection.m` implementation against the live
PPC bodies on 2026-10-07. Condition allocation/wrap scanning, run-loop wait,
completion-record lookup/removal, and queued synchronous-request priority
match the decompiled control flow. The retained record and autoreleased return
values preserve the target's values across removal from the array. No source
change, tests, or builds were made in this recheck.

Also rechecked `cancelRequest:` (`0x425b19c8`), `cancelFetchOfURL:`
(`0x425b1aa8`), and `portBecameInvalid:` (`0x425b21bc`). The source retains the
request client before clearing the request's client slot, removes queued work
under `_lock`, calls cancellation after unlocking, and replaces/re-registers
the invalid port while locked before draining pending messages. These paths
match the PPC control flow; no source change, tests, or builds were made.

The completion records are mutable dictionaries keyed by the target strings
`NSHTTPRequestKey`, `NSHTTPHeadersKey`, and `NSHTTPDataKey` (at `0x426226a8`,
`0x426226bc`, and `0x426226d0`). The request's `_condition` remains on the
request object; `_nextSynchCondition` follows that request through queued jobs,
pending client messages, and completion records.

The client-message signaling helpers assign kind 0 to connection failure,
1/2 to unfinished/finished data blocks, 3 to task completion, and 4/5 to
incomplete/complete headers. `signalMessage:` appends each allocated message
to `_completedJobs` under `_lock`, then sends a wakeup through `_port` after
releasing the lock; a failed send logs the target diagnostic.

## HTTP status routing and redirects

`-[NSHTTPURLHandle receivedHeaders:forRequest:]` at `0x425b5bb8` routes the
normalized status code as follows: values 200–299 update `_headers` when this
handle is cached; 300–399 construct a redirected handle, attach the current
handle as its client, and start its background load unless a redirection loop
is detected; values 400–599 build a localized failure reason and call
`backgroundLoadDidFailWithReason:`. Codes below 200 or above 599 take the
target unknown/out-of-range failure path. All terminal/error branches release
and clear the active connection.

`-[NSHTTPURLHandle redirectedHandleFromHeaders:]` at `0x425b5828` checks the
`Location` header first, then lowercase `location`. It resolves the resulting
URL relative to the current URL and canonicalizes it. If the current handle
has cached headers, the redirect uses a cached handle; otherwise it creates
an uncached handle. The loop path uses the target localized
`Detected a redirection loop while attempting to load URL %@` reason.

`-[NSHTTPConnection enrichedHeadersFromHeaders:andStatus:]` at `0x425b2cd8`
copies parsed headers to a mutable dictionary and adds the target HTTP status
code and status-reason properties. It derives a reason from the parsed status
line when available and uses the target localized status-reason fallback
otherwise. If the status cannot be parsed, it inserts status 599 and the
target localized unknown-status reason before returning the enriched copy.
`-[NSHTTPURLHandle connectionFailedDuringRequest:]` at `0x425b5ec4`
localizes a connection failure with the connection's reason and passes that
reason through `backgroundLoadDidFailWithReason:`.

### HTTP response enrichment allocation and number factory (2026-10-06)

The PPC decompilation of `-[NSHTTPConnection
enrichedHeadersFromHeaders:andStatus:]` at `0x425b2cd8` initializes its mutable
result with `NSMutableDictionary`'s `initWithDictionary:` and creates parsed
status values with `NSNumber`'s `numberWithInt:`. `NSHTTPConnection.m` now uses
those exact construction paths. The literal operands resolve to a single-space
separator, `Bad header received from server` as the localized reason key, and
`URL` as the localization table. The property-key slots resolve in order to
`NSHTTPPropertyServerHTTPVersionKey`, `NSHTTPPropertyStatusReasonKey`, and
`NSHTTPPropertyStatusCodeKey`.

The target stores the status-line suffix beginning at the first space under the
server-version key, then searches for the next space in the remaining range
with option `2` (`NSLiteralSearch`). When it finds one, it parses the
intervening text with `intValue` and uses the trailing text as the reason. If
no later space exists, a three-
character suffix with value greater than 99 is stored as the status code and
the method returns immediately without setting a reason. Other malformed
lines receive status 599 and the localized reason. `NSHTTPConnection.m` now
matches these branches. Static source checks only; no tests or builds were run.

## HTTP Handle Request and Data Callbacks

`-[NSHTTPURLHandle loadInForeground]` at `0x425b5410` first delegates to
`_redirectedHandle` when present. Otherwise it lazily obtains a connection for
the URL host and port (default 80), builds a GET request, and invokes
`sendRequestSynchronously:headers:`. A 300–399 result creates a redirected
handle and checks the redirect chain for a loop. It follows the redirected
handle's `resourceData`; when the current handle is uncached (`_headers ==
nil`), it flushes that handle and clears `_redirectedHandle` after obtaining
the result. A status above 399 returns nil for the base handler's failure
handling. The request is released after the synchronous send.

`-[NSHTTPURLHandle beginLoadInBackground]` at `0x425b5610` also delegates to
an existing redirected handle. It lazily obtains a connection using the URL
host and port (default 80), builds a GET request, enqueues it with the current
handle as client, then releases the request. If no connection is available,
it builds a localized failure reason from the URL and calls
`backgroundLoadDidFailWithReason:`.

`-[NSHTTPURLHandle receivedDataBlock:forRequest:finished:]` at `0x425b5950`
first calls `_shouldAcceptResponseDataBlock:forRequest:`. The accepted result
value 2 forwards bytes and the completion flag through `didLoadBytes:loadComplete:`.
Otherwise, only a cached handle with `_headers` stores the error-page body
under the target error-page data key: existing data is appended, while a
missing value is added to a mutable copy; the updated dictionary replaces
`_headers` as an immutable copy when complete.

`-[NSHTTPURLHandle URLHandle:resourceDataDidBecomeAvailable:]` at
`0x425b5f64` forwards bytes as an incomplete load. The begin/finish/cancel
base-client callbacks are confirmed in their target bodies: begin-loading at
`0x425b5fa0` is empty; finish-loading at `0x425b5fac` reports a nil final data
block through `didLoadBytes:loadComplete:` and, when uncached, flushes and
clears `_redirectedHandle`; cancel-loading at `0x425b600c` notifies the current
base clients and, when uncached, forwards cancellation to the redirected
handle before clearing it; failure at `0x425b607c` calls
`backgroundLoadDidFailWithReason:` and, when uncached, forwards the failure to
the redirected handle before clearing it. `-[NSHTTPURLHandle didLoadBytes:loadComplete:]`
at `0x425b60d8` normally forwards to the base implementation. When both
response headers and a redirected handle exist, it first forwards the bytes
through the current handle's base clients; on completion it calls the base
implementation with nil bytes and completion set, marking the parent complete
without duplicating the redirected payload.

`-[NSHTTPURLHandle inRedirectionLoop]` at `0x425b4eb0` creates a visited-URL
set, inserts the current URL, then walks `_redirectedHandle` links and tests
each URL for equality/duplication. A duplicate reports a loop; exhausting the
chain reports no loop. The localized loop reason is documented in the status
routing section above.

### HTTP worker request ownership (2026-10-06)

PPC IDA `-[NSHTTPConnection processRequests:]` at `0x425b2300` confirms the
worker retains the dequeued request before removing it from `_newJobs`. The
retained request is used through connection and response handling, and the
target does not release that local retain before the next queue iteration or
return. The source previously released it after each request; that release is
removed to match the target. The socket factory returns an autoreleased socket;
the worker retains it when storing `_socket`, releases that retain after the
request, then clears the ivar. No tests or builds were run.

### HTTP signal-message locking and port-message ownership (2026-10-06)

PPC IDA `-[NSHTTPConnection signalMessage:]` at `0x425b3360` confirms the
completed-message queue append and `NSPortMessage` allocation/initialization
occur while `_lock` is held; the lock is released before computing the send
deadline and sending. Source now uses that lock ordering. The target sends the
allocated message without a release, so the source release was removed to
preserve target ownership behavior. Its selectors resolve to `alloc`,
`initWithSendPort:receivePort:components:`, and `sendBeforeDate:`. Static
source review only; no tests or builds were run.

### HTTP response-length and status enrichment source recheck (2026-10-07)

Re-decompiled `-[NSHTTPConnection numberDataBytesForRequest:withHeaders:]`
(`0x425b2ff0`) and `-[NSHTTPConnection enrichedHeadersFromHeaders:andStatus:]`
(`0x425b2cd8`) against the current source. The source preserves the target's
zero-body cases (`HEAD`, 1xx, 204, and 304), lowercase `content-length`
lookup, and `0x7fffffff` unknown-length sentinel. Status enrichment keeps the
version suffix, parses a status/reason when a second space is present, accepts
a three-character status without a reason, and supplies status 599 plus the
localized malformed-header reason on parse failure. No source mismatch was
found in these two paths; no source changes, tests, or builds were made.

### HTTP property lookup and redirect source recheck (2026-10-07)

Compared `-[NSHTTPURLHandle propertyForKey:]` (`0x425b4fc8`),
`propertyForKeyIfAvailable:` (`0x425b529c`), and `flushCachedData`
(`0x425b536c`) with the current implementation. The source matches IDA's
lazy synchronous GET, lowercase property lookup, 300–399 redirect handling,
cached-header replacement, `NSHTTPPropertyRedirectionHeadersKey` return,
redirect-loop early return, and uncached redirected-handle release. The
available-property method forwards through redirects except for the redirect
headers key, and flush resets headers and releases the redirected handle after
the base flush. No mismatch was found in these paths; no source changes, tests,
or builds were made.

### Request-line empty-path fidelity correction (2026-10-07)

Rechecked `-[NSHTTPRequest serializedRequest]` at `0x425b3e04` and its call to
`_NSParseStringToGenericURLComponents` at `0x425af9b4`. The target tests only
the path range's location against `NSNotFound` before choosing `/`; it does
not test the range length. The target parser writes the path as `(start,
length)`, including a zero-length path at the end of an authority URL. The
source's extra `pathRange.length == 0` fallback therefore changed the target's
empty request-target into `/`. `NSHTTPRequest.m` now falls back only when the
location is `NSNotFound`, matching the PPC branch. This refines the earlier
request-serialization note above. Static source and IDA review only; no tests
or builds were run.

### Request initialization, headers, and ownership source recheck (2026-10-07)

Compared the current `NSHTTPRequest.m` bodies with PPC IDA:
`initWithMethod:URL:` (`0x425b3ba0`), `dealloc` (`0x425b3c80`),
`addHeader:value:` (`0x425b3d30`), `setData:` (`0x425b3da8`), `_setClient:`
(`0x425b4028`), and `fetchesURL:` (`0x425b407c`). Initialization copies the
method and URL, creates the mutable header collections, and initializes nil
data and condition -1. Header order records a key only before its first value;
data and client setters retain before releasing their old values. Teardown
releases the six owned ivars before `super dealloc`. `fetchesURL:` accepts GET
requests whose URL compares equal. No mismatch was found; no source changes,
tests, or builds were made in this recheck.

### HTTP response callback and port dispatch source recheck (2026-10-07)

Compared `-[NSHTTPConnection receivedHeaders:forRequest:]` (`0x425b1b80`),
`receivedDataBlock:forRequest:finished:` (`0x425b1c64`),
`requestWasCancelled:` (`0x425b1e0c`), and `handlePortMessage:`
(`0x425b1f20`) against the current implementation. Synchronous response
records are appended under `_lock`; nonempty body chunks are appended to the
matching request record only while its condition is active; a finished chunk
signals the condition lock first with -1 and then with the request's condition.
Cancellation removes the matching synchronous record and releases waiters.
Port dispatch detaches each completed message under `_lock`, invokes callbacks
outside the lock, and recycles the message afterward. The current source follows
these target paths; no mismatch or source change resulted. No tests or builds
were run.

