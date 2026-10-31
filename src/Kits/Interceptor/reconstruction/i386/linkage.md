# DR2 i386 linked support code

The DR2 i386 Interceptor image has `LC_LOAD_DYLIB` entries for AppKit,
Foundation, and System, but no `libDriver.A.dylib` entry. The primary PowerPC
image links `libDriver.A.dylib`; corresponding DriverKit names in its symbol
table resolve through linker-generated PIC import stubs.

The i386 bodies named `__IO*` and `__PM*` match the user MIG client routines
declared in `src/driverkit-3/libDriver/driverServer.defs`. The DriverKit
Makefile generates `driverServerUser.c` from those definitions. These routines
are linked support code rather than Interceptor-owned routines; the framework
build should resolve them through its selected libDriver implementation rather
than duplicate them in `InterceptorIPC.c`.

The i386 `_ev_lock`, `_spin`, `_ev_unlock`, and `_ev_try_lock` names map to the
shared event-lock assembly in `src/kernel-7/bsd/dev/i386/EventShmemLock.h`.
`_spin` is the retry label inside `_ev_lock`, not an independent operation.
These low-level synchronization helpers are also outside Interceptor's own
source files.

The remaining `dyld_stub_binding_helper` and `__dyld_func_lookup` entries are
dynamic-loader support routines. They are recorded in the function worklist as
runtime glue rather than missing framework implementation.
