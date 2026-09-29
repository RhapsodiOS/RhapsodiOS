# DR2 i386 intercepted-rectangle state

DR2 i386 initializes the condition lock at state zero, then calls `lockRect`
before registering the rectangle with the client. This leaves a newly
constructed rectangle locked while its initial Window Server registration is
in progress. The PPC reference does not make that constructor call, so the
source keeps it under the i386 build guard.

Both binaries implement `unlockRect` by clearing `isLocked` and releasing the
condition lock with state zero. Notification handling separately releases the
lock using `moveInProgress`, preserving state one across move and buffering
callbacks until their matching completion notification.

The geometry and state accessors return their corresponding stored fields;
`removeFromWindowServer` delegates to the owning client, and `dealloc` repeats
that removal before releasing the temporary bitmap, condition lock, and cached
screen shape. `_handleMsg:withReply:` follows the PPC notification dispatch
and reply contract, including visibility updates and move/buffering lock
state. Runtime execution remains pending a compatible host.
