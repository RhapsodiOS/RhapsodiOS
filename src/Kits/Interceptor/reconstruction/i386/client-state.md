# DR2 i386 client and intercepted-rectangle evidence

The DR2 i386 image confirms the shared notifier structure implemented in
`NSInterceptorClient.m`. `+[NSInterceptorClient initialize]` creates a lock,
a mutable dictionary from notification ports to clients, and a Mach port set.
`startHandlingThread` stores the client under its `NSPort` wrapper, adds the
receive port to the shared set, and starts one notifier thread under a lock
handshake.

The worker receives fixed 108-byte notification messages on the shared port
set, wraps the received local port with `+[NSPort portWithMachPort:]`, looks up
the owning client under the table lock, and dispatches through
`handleInterceptorMessage:withReply:`. It creates a fresh autorelease pool for
each receive and sends a 32-byte reply when the handler requests one. The
worker also observes `NSPortDidBecomeInvalidNotification` for the Window
Server port and publishes `NTWindowServerDeathNotification` through the
client callback.

The client initializes its context, condition lock, port lock, and rectangle
array only after context creation succeeds. `interceptorPort` allocates one
notification port per client, prefers thread special port 3, falls back to
task special port 3, and installs the notification and exception ports with
`_InterceptorSetNotifyPort`. Rectangle registration adds the object to the
client list before its RPC and removes it again on failure; removal reaches the
server first. `handlingThread` returns a per-client override when present, or
the shared notifier thread otherwise.

The context helpers are local code in the reference image. `getPSPort` first
looks up `WindowServer` through the task bootstrap port when both name
arguments are null. If that path fails, it resolves the historical
`NextStep(tm) Window Server` netname and sends the rendezvous RPC with package
ID `7196`. The PPC image confirms the same lookup order and message shape.

Static reconstruction is complete for the shared notifier and rendezvous
paths. Runtime behavior still needs execution on a compatible Rhapsody/DR2
host.
