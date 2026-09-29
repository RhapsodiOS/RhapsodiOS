# PowerPC client and intercepted-rectangle evidence

The PPC reference's Objective-C bodies establish these ownership and dispatch
orders. `NSInterceptedRect.m` now implements construction, geometry/state
accessors, condition-lock behavior, notification dispatch, and reply framing.
`NSInterceptorClient.m` implements initialization, notification-port setup,
rectangle registration, lookup, teardown, and a receive loop. Cross-client
notifier ownership and runtime behavior remain to be compared. The flush
notification's selector-probe behavior is documented below.

`NSInterceptorClient` creates a 12-byte Mach context, a condition lock, a
regular lock, and its intercepted-rectangle collection. Class initialization
also creates the shared client table and allocates the notification port set.
`interceptorPort`
holds the port lock while allocating the notification receive port, tries
thread special port 3, falls back to task special port 3, then sends the
notification and exception ports through `_InterceptorSetNotifyPort`. On RPC
failure it deallocates the new receive port and returns zero; on success it
stores that port in the context and creates an `NSPort` wrapper.

`_addInterceptedRect:returnedScreenRect:returnedFlags:` adds the rectangle to
the collection while holding the list lock before issuing `_InterceptorAddRect`.
On failure it removes the rectangle under the same lock and logs the status.
On success it converts the returned four integer screen bounds to floats and
returns the server's flags. `_removeInterceptedRect:` calls the server first
and removes the object only on success.

`startHandlingThread` stores the client in a shared dictionary keyed by its
`NSPort` wrapper, adds the Mach port to the shared port set, then starts one
notifier thread. The worker registers for invalidation of the Window Server
port, receives fixed 108-byte `InterceptorNotification` messages from the
port set, and looks up the client using the received local port. It holds the
shared table lock while dispatching, then sends a 32-byte reply when requested.
The worker rotates autorelease pools for successive messages, and startup uses
a lock handshake so only one notifier thread is created.

The selected DR2 i386 image uses the same shared port-set and client-table
design. Its global names differ, but port registration, message dispatch,
thread startup, and reply sizing match the PPC behavior.

`InterceptorContext.c` implements the local rendezvous helpers. It first looks
up `WindowServer` through the task bootstrap port when both names are null,
then falls back to the historical netname service name. The rendezvous RPC
sends a 32-byte message with package ID `7196` and returns the context port.
Unknown message IDs and missing rectangle IDs are logged.

Notification types map in order to these target selectors:
`areaDidReveal:inRect:`, `areaWillObscure:inRect:`, `areaIsInvalid:`,
`areaWillMove:by:`, `areaDidMove:by:`, `areaWasOrderedIn:`,
`areaWasOrderedOut:`, `areaWillFlush:inRect:theBits:`,
`areaChangedScreen:from:to:`, `areaWindowFreed:`,
`areaWillChangeBuffering:fromType:`, and
`areaDidChangeBuffering:toType:`. `DID_MOVE` changes the stored screen origin
and offsets the cached screen shape. Move and buffering messages update the
move-in-progress state around their callbacks.

During teardown, the client holds the port lock, removes the notification port
from its receive set, removes its Window Server death observer, releases the
`NSPort` wrapper, deallocates and clears the notification port, then releases
the rectangle array and both locks before destroying the Mach context. The
notifier is shared and created only once by `startHandlingThread`.

Runtime ordering and callback arguments still need comparison against the
reference in a compatible guest before these findings can count as behavioral
parity.

For `INTERCEPT_FLUSH`, the PPC jump-table case and the DR2 i386 switch both
check whether the target responds to `areaWillFlush:inRect:theBits:`. Neither
binary invokes that selector or sets a nonzero reply code on this path. The
source and rectangle regression case preserve this observed behavior; they do
not invent the missing bits delivery.

For `INTERCEPT_WILL_OBSCURE`, both implementations clear the totally-visible
state only after the target reports support for and receives the obscure
callback. The source keeps that state update inside the selector guard.

`currentClipList:count:` and `compositeBits:withOp:` both raise
`NSInvalidArgumentException` with `*** Method not implemented: <selector>` on
PowerPC and DR2 i386. The source retains these binary-observed failure
contracts instead of returning a placeholder value.
