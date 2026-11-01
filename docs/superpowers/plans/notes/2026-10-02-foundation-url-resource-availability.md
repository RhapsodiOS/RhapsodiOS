# Foundation NSURL resource loading target availability

Reference: Foundation i386 IDA database `6c2a913dc37a`.

The worktree's `NSURL.m` still has TODO bodies for
`resourceDataUsingCache:`, `loadResourceDataNotifyingClient:usingCache:`,
`propertyForKey:`, `setResourceData:`, `setProperty:forKey:`, and
`URLHandleUsingCache:`. The IDA function-name index has no `NSURLHandle`
functions and no functions for these `NSURL` selectors; the indexed strings
also contain none of the selector names. The extracted NSURL ABI record does
not list these methods. This target does include URL construction, component
accessors, path conversion, and URL-based NSData/NSString methods, so its
absence is limited to the resource-handle API checked here.

As with `NSURLHandle`, these TODO bodies are not recoverable from this target's
IDA database. Reconstruction needs the binary or source revision that contains
the resource loading implementation; implementing them from API expectations
would not be IDA-grounded.

## Secondary Foundation binary check

Also inspected the separate DR2 Foundation binary at
`C:\Users\raynorpat\Downloads\test\DR2\Frameworks\Foundation.framework\Versions\C\Foundation`
in IDA instance `3aa234610366`. Its URL-related function index likewise has no
`NSURLHandle`, URL resource-loading, or URL cache methods, and the strings
contain no resource-handle selectors. It does include the same basic NSURL
construction/component API and an `NSAbsoluteURL` subclass. This second binary
therefore does not provide a grounded implementation for the missing resource
methods.

The containing DR2 tree was also checked for `CFNetwork.framework`,
`WebFoundation.framework`, and `URLFoundation.framework`; none is present.
There is no URL networking framework in this supplied DR2 reference set to
cross-check these APIs against.

## Exact project binary cross-check

The project's `Foundation-i386` reference was also checked in IDA instance
`d12fe2f23883`. Exact Objective-C function lookups for all six `NSURL`
resource/cache TODO selectors returned no function. The four `NSObject` URL
delegate TODO selectors also have no function in that database. The project's
`reconstruction/abi/NSURL.json` omits the six resource/cache selectors, and
the extracted `NSAbsoluteURL` ABI contains no URL delegate methods. These
source TODOs therefore remain outside the selector surface of the exact target;
the earlier availability finding is confirmed against the binary used by the
project's ABI extraction.

## MOSXS PPC resource API recheck (2026-10-05)

The separate MOSXS PPC IDA database contains the URL resource methods absent
from the DR2 i386 reference. `-[NSURL resourceDataUsingCache:]`
(`0x425aeef8`) asks `URLHandleUsingCache:` for a handle and returns its
`resourceData`. `propertyForKey:` (`0x425af284`), `setResourceData:`
(`0x425af2d0`), and `setProperty:forKey:` (`0x425af320`) forward through a
handle. `propertyForKey:` requests an uncached handle; both setters pass YES
to `URLHandleUsingCache:`. `URLHandleUsingCache:`
(`0x425af378`) asks the registered URL handler class for the URL; it uses the
class cache when requested or initializes an uncached handle otherwise. The
five synchronous wrappers now match these PPC call paths in `NSURL.m`; their
i386 source branches remain TODOs because the shared i386 target omits them.

`loadResourceDataNotifyingClient:usingCache:` (`0x425aef38`) coordinates
callbacks with handle status. It reports immediate failure when no handle can
be obtained, delivers available data/finish callbacks for a completed handle,
retains the client-to-handle association and starts background loading for an
in-progress handle, and delivers the failure callback for a failed handle.
The method lazily creates its client map. These source TODOs are therefore
PPC-supported, but the asynchronous path is coupled to the NSURL client map,
NSURLHandle state machine, and concrete URL handlers; no source changes were
made from this analysis.

The status branches use the existing enum values: not-loaded (0) creates the
client map, associates the client with the handle, registers the URL as a
handle client, and starts background loading; succeeded (1) conditionally
sends available data and a finish callback; in-progress (2) conditionally
sends currently available data, records the association, and registers the
URL without starting a second load; failed (3) conditionally sends the
handle's failure reason. When no handle exists, the failure callback receives
the localized `Don't know how to load URL %@` reason. The terminal URL
callbacks notify only clients mapped to the completing handle, remove those
associations, unregister the URL from that handle, and free `_clients` when
the map becomes empty. The begin-loading callback is empty.

## PPC async URL reconstruction

The PPC-only asynchronous entry point and the five `NSURLHandleClient`
callbacks have been implemented in `NSURL.m`. The client map uses the object
key and value callbacks with initial capacity 10 and the URL's zone. The
terminal callback helper snapshots map keys before invoking clients and
removing associations. The i386 TODO branch and shared i386 ABI record remain
unchanged; `reconstruction/abi-ppc/NSURL.json` now records the six async
selectors.


## MOSXS PPC URL-handle client callbacks (2026-10-05)

IDA identifies the PPC callbacks on `NSURL` itself. The begin-loading callback
at `0x425af4c8` is an empty body. `URLHandle:resourceDataDidBecomeAvailable:`
(`0x425af418`) walks the `_clients` map and forwards available data to clients
whose associated handle matches. Finish (`0x425af4d4`), cancel
(`0x425af644`), and failure (`0x425af7b0`) callbacks find clients associated
with the completing handle, issue the corresponding client callback, remove
their map entries, and detach the URL from the handle; they release the map
when it becomes empty. The failure path also constructs a localized failure
reason before notifying clients. These callbacks coordinate with
`loadResourceDataNotifyingClient:usingCache:` and `NSURLHandle` client
registration. The four default `NSObject` URL delegate methods in source are
not these target callbacks; they have no matching function in this PPC lookup.


## URL resource ABI boundary

The checked-in shared `NSURL.json` ABI record contains none of the resource,
property, setter, handle-selection, or handle-callback methods (the only
matching selector text is `resourceSpecifier`). The source header does declare
the URL-loading category and `NSURL` conforms to `NSURLHandleClient`, but its
implementation has only the resource methods and default `NSObject` delegate
methods as TODOs; it lacks the five PPC `NSURL` handle-callback bodies found by
IDA. The PPC handler list also includes separate `NSFileURLHandle` and
`NSHTTPURLHandle` classes absent from this source tree. Therefore a complete
PPC resource-loading reconstruction needs architecture-specific ABI coverage
and coordinated client-map/handler source, while the existing i386 ABI should
remain grounded in its separate target absence.
