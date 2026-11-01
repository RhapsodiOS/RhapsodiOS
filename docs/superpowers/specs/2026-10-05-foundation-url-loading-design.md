# PPC Foundation URL Loading Design

## Goal

Reconstruct the MOSXS PowerPC Foundation URL-loading path so `NSURL` can select
and use the same built-in file and HTTP handlers as the reference framework.
The work covers the base `NSURLHandle` registry and cache factory, both
concrete handlers, and the HTTP request/connection/socket classes they use.

## Scope and target boundary

This is a PPC-only reconstruction. The DR2 i386 Foundation image has no
`NSURLHandle`, `NSFileURLHandle`, `NSHTTPURLHandle`, `NSHTTPRequest`,
`NSHTTPConnection`, or `NSHTTPSocket` implementation inventory. Preserve its
current i386 fallback branches and shared ABI surface; record the MOSXS PPC
classes in per-module `reconstruction/abi-ppc` manifests.

Implement only behavior supported by the MOSXS PPC Objective-C metadata and
IDA bodies. Preserve observed target control flow, including the base
background-cancel/flush recursion documented in the URL-handle evidence note;
do not silently add a status reset to make that path safer.

## Components and interfaces

### `NSURLHandle` registry and integration

`+[NSURLHandle initialize]` initializes the registered-class array only when
the receiver is exactly `NSURLHandle`, then registers `NSFileURLHandle` and
`NSHTTPURLHandle` in that order. `registerURLHandleClass:` appends to this
array. `URLHandleClassForURL:` asks classes in registration order whether they
accept the URL and returns the first match. Base `cachedHandleForURL:` selects
that class and delegates to its cache factory; a subclass inheriting the base
factory requests a concrete implementation. Do not add synchronization to the
class registry unless IDA confirms that the registry path takes a lock; the
target method bodies shown so far only establish array insertion and ordered
scanning.

The existing PPC state machine in `NSURLHandle.m` remains the common owner of
load status, client registration, data accumulation, callback delivery,
foreground waiting, failure state, and abstract subclass hooks. New handler
classes use those methods rather than duplicating the base state.

### `NSFileURLHandle`

Add the PPC class in its own source/header module with target instance size 32:
`_path` at offset 20, `_fh` at 24, and `_properties` at 28. Its URL predicate
uses the target path/file check; cache lookup is keyed by path and creates and
registers a handler on a miss. The handler implements path initialization and
teardown, synchronous read/write, file-attribute lookup and mutation, and
run-loop-driven background reading through `NSFileHandle` notifications.
Opening failures use the target localized reason. Background completion
forwards received bytes to the base callback before closing the read handle.

### `NSHTTPRequest`

Add the PPC request object as a separate private module with target instance
size 32 and ivars `_req`, `_url`, `_headers`, `_headerOrder`, `_data`,
`_client`, and `_condition` at offsets 4 through 28. It owns method and URL
copies, preserves header insertion order while replacing duplicate values,
retains request data and client state, and serializes the request line, ordered
headers, terminating CRLF, and optional body using the target URL path and
string/byte conversion behavior. Its private condition and client accessors
must match the connection queue's use.

### `NSHTTPSocket` and `NSHTTPConnection`

Add `NSHTTPSocket` with target instance size 12 (`_socket` at offset 4 and
`_surplusBytes` at offset 8). It owns the stream-socket descriptor, connects to
host/port, writes request bytes, reads available bytes with a timeout, and
preserves bytes beyond a parsed response boundary for the next request.

Add `NSHTTPConnection` with target instance size 44 and the ten target ivars
from its PPC ABI record. It caches connections by host and port, queues
requests, supports synchronous response waits using its condition state,
cancels queued/current requests, and delivers response headers, data blocks,
completion, cancellation, and failure to request clients. Its background
thread processes queued jobs over `NSHTTPSocket`; existing `NSPortMessage` and
Foundation port APIs are reused where the target uses them.

### `NSHTTPURLHandle`

Add `NSHTTPURLHandle` with target instance size 36 (`_url`, `_headers`,
`_connection`, `_redirectedHandle` at offsets 20, 24, 28, and 32). Its cache
factory keys by canonical URL. Canonicalization applies the target defaults
for port 80 and for an absent path. The handler implements synchronous and background
requests, status/property access, error-page data, response-header callbacks,
redirect creation and loop detection, cancellation, and forwarding of data and
completion/failure callbacks through the common `NSURLHandle` state machine.
Preserve the target distinctions between uncached and cached response headers
and its localized error reasons.

`NSURL` continues to use the existing PPC forwarding and client-callback
methods in `NSURL.m`; the registry makes its existing `URLHandleUsingCache:`
path resolve built-in handlers.

## Delivery sequence

The implementation is staged by dependency while preserving one final
full-path result:

1. Implement `NSHTTPRequest` serialization, ownership, and ABI metadata.
2. Implement `NSHTTPSocket` and `NSHTTPConnection`, including their request
   queue and synchronous/asynchronous response paths.
3. Implement `NSFileURLHandle`, `NSHTTPURLHandle`, and the base registry/cache
   factory; register both built-in classes and connect `NSURL` to them.
4. Reconcile PPC ABI, ownership, symbol, project-file, and divergence records
   for every added class/module.

The stages may be represented by separate commits later, but no stage may
replace an absent target component with a stub or leave HTTP unregistered in
the final result.

## Constraints and verification

- Match PPC Objective-C class sizes, ivar offsets, selectors, and encodings
  extracted from the reference image.
- Preserve i386 unimplemented branches and do not add PPC-only class records to shared/i386 ABI
  manifests.
- Use existing Foundation collection, string, data, port, run-loop, file, and
  locking APIs when IDA shows those calls; do not add a separate networking
  abstraction.
- Do not alter unrelated source or metadata already modified in the worktree.
- Validate generated ABI JSON and reconstruction metadata, compare every
  reconstructed method against its IDA body, and run `git diff --check`.
  Runtime tests/builds are outside this design's current verification scope.

## Evidence

The PPC class records and method encodings are extracted from the target
Foundation image by `tools/binrecon/binrecon/objc_abi.py`. Current method-level
decompilation notes are in
`docs/superpowers/plans/notes/2026-10-02-foundation-urlhandle-availability.md`.
The key source integration points are `src/Kits/Foundation/NSURL.m`,
`NSURLHandle.m`, `NSThread.m`, `PB.project`, and `Makefile`.
