# Foundation freed-object query analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and the current
Foundation/runtime sources under `src/Kits/Foundation` and `src/objc-1`.

## IDA behavior

`NSIsFreedObject` at `0x4256ee44` first rejects null or unreadable addresses.
It reads the object's `isa`, lazily caches the runtime's freed-object class by
allocating and deallocating an `Object`, and caches the `NSZombie` class. It
returns true when the object's `isa` is the freed-object class or when walking
the superclass chain from its `isa` encounters the cached zombie class.

The local helper `_isReadableAddr` at `0x4257225c` checks a four-byte range
through `vm_region`. It rejects addresses whose page number is zero, requires
the queried address to lie within the returned region, and checks that the
requested range ends within that region. IDA's condition also tests bit 0 of
the returned region information.

## Source relationship

`NSDebug.h` already declares `NSIsFreedObject`, but no Foundation source file
currently defines it. `src/objc-1/objc-class.m` exposes the freed-object class
through `_objc_getFreedObjectClass`; `src/objc-1/Object.m` assigns that class
before disposing an object. `NSObject.m` defines the `_NSZombie` root class,
and `NSZone.m` records the generated per-class zombie subclasses. `NSZone.m`
also implements `NSLogPageSize`, which `_isReadableAddr` uses as a shift count.

No source changes were made for this analysis. The eventual source owner and
whether Foundation should reproduce IDA's allocate/deallocate cache sequence
or use the runtime's existing `_objc_getFreedObjectClass` entry point remain
to be resolved before implementation.

## Implementation (2026-10-04)

`NSDebug.m` now defines the public `NSIsFreedObject` entry point and a local
readability check. Its nine-argument `vm_region` call follows the target's
`task_self_`, page-number guard, readable-protection bit, and region-boundary
checks. After confirming the object pointer is readable, the function compares
its `isa` with the runtime freed-object class and walks `super_class` for the
`_NSZombie` class.

The target lazily discovers the freed-object class by allocating and
_deallocating an `Object`, then reading its `isa`; the reconstruction uses
`_objc_getFreedObjectClass()` instead, which returns that same runtime class
without reading the deallocated allocation. `_NSZombie` is obtained through
`objc_lookUpClass`. The function is recorded in `NSDebug.json` and the symbol
ownership map. Static source/manifest checks and `git diff --check` passed; the
symbol audit reports 144 unclaimed exports. No tests or builds were run.
