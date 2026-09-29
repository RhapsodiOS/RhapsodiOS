# PowerPC client and intercepted-rectangle evidence

The PPC reference's Objective-C bodies establish these ownership and dispatch
orders. `NSInterceptedRect.m` now implements construction, geometry/state
accessors, condition-lock behavior, notification dispatch, and reply framing.
`NSInterceptorClient.m` implements initialization, notification-port setup,
rectangle registration, lookup, teardown, and a receive loop. Cross-client
notifier ownership and runtime behavior remain to be compared. The reference's
flush-bit delivery path remains an explicit TODO.

`NSInterceptorClient` creates a 12-byte Mach context, a condition lock, a
regular lock, and its intercepted-rectangle collection. `interceptorPort`
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

The notification worker receives a fixed 108-byte `InterceptorNotification`
on the context notification port. It rotates autorelease pools for successive
messages, checks notification ID `1234`, finds the matching rectangle by
`uniqueID` under the list lock, releases the list lock, then calls
`_handleMsg:withReply:`. The rectangle handler holds its condition lock while
updating visibility and move state, and builds an `InterceptorReply` with ID
`4321`, the input sequence number, and a 40-byte reply layout. The client sends
the reply when requested.
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
