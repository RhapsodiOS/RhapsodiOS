# drvPCIBus signature divergences against the DR2 reference

Scope: the Objective-C **interface** of `PCIKernBus`, `PCIKernBus(Private)` and
`PCIResourceDriver` as declared in `PCIBus.drvproj/PCIBus.lksproj/` — method
type encodings and ivar layout — compared against Apple's shipped driver.

Companion to `divergences.md` in this directory, which covers the *implementation*
of the same driver at function level (control flow, ivar initialisation, error
codes) and is backed by `ledger.json`, `source-map.json` and a clean build. The
two do not overlap: that pass examined function bodies, this one examines the
`__OBJC` metadata that declares them. Both cite the same reference binary and
the same SHA-256.

## Reference

| | |
| --- | --- |
| Binary | `Drivers/i386/PCIBus.config/PCIBus_reloc` |
| Format | Mach-O i386 preload executable, 41360 bytes |
| SHA-256 | `3efac8a41b87c5b4d77358c2892e38a1f0a0821d7edc18021182954b3c1a1451` |

Evidence was read directly out of the image: `__OBJC,__module_info` at `0x288c`
(four modules), each `objc_symtab` walked to its class defs, then each class's
`objc_ivar_list` and `objc_method_list` read for `ivar_name` / `ivar_type` /
`ivar_offset` and for `method_name` / `method_types`. The type strings quoted
below are the literal `__meth_var_types` and ivar-type bytes, not a
reconstruction of them.

**No build was performed and nothing here is compile-checked.** A build route
does exist — `vm/build-i386-bus-drivers.sh` builds this driver inside the
Rhapsody guest — but it was not exercised in this pass: no guest was running and
booting one was out of scope. Compiling these changes is the first thing the
next session with a live guest should do.

This document does not carry a `ledger.json` or `source-map.json`. Those require
a `binrecon` per-function analyzer pass (Ghidra/IDA/angr agreement) that was not
run here, and a stub ledger would misrepresent the confidence level.

Related: the kernel-side `PCIKernBus.h` interface was declared in commit
99a55c1b and reported in `src/driverkit-3/libDriver/reconstruction/divergences.md`.
That report covers only the 26 methods of the two public kernel headers; it is
where the first two findings below were first noticed, and it deliberately left
them unchanged pending this record. Both that commit and that report currently
live on the `qemu-debug-loop` branch, which is ahead of this one — the
cross-reference resolves once this branch merges forward.

## Findings

### 1. `-[PCIKernBus maxBusNum]` / `maxDevNum` returned `unsigned int` — **fixed**

| | |
| --- | --- |
| Reference | `i8@8:12` at `0x3a8` / `0x3b8`, so `- (int)` |
| Ours, before | `- (unsigned int)maxBusNum;` / `maxDevNum` |
| Backing ivars, reference | `i maxBusNum` at `+16`, `i maxDevNum` at `+20` |
| Backing ivars, ours before | `unsigned int _maxBusNum`, `unsigned int _maxDevNum` |

Brought to Apple's signature at `PCIKernBus.h:69-70` and `PCIKernBus.m:448,453`.
The two ivars were retyped to `int` in the same change: leaving them `unsigned
int` behind an `- (int)` accessor would have introduced an implicit conversion
that is not in the reference and would have left the record half-applied.

Checking the rest of the ivar block for the same `I`-for-`i` slip found two
more: `_pciVersionMajor` and `_pciVersionMinor` at `+36` / `+40` were `unsigned
int` against the reference's `i majorVersion` / `i minorVersion`. Both were
retyped to `int` at `PCIKernBus.h:51-52`. They are written once each as the
constants `2` and `1` (`PCIKernBus.m:90-91`) and read once in an `IOLog`
(`PCIKernBus.m:131`), so the change carries no risk.

This is ABI-identical — `int` and `unsigned int` both return in `eax` — so the
change is a type-checking one only. It is safe at every use: the values are PCI
bus and device numbers, set to `0`, `0x1f` (mechanism 1) or `0xf` (mechanism 2)
at `PCIKernBus.m:88-114`, and every comparison against them
(`PCIKernBus.m:135,136,244,272,273,321,346`, `PCIResourceDriver.m:145,155,259,269,389,396`)
is against a non-negative loop counter or a bounded config value.

### 2. `-[PCIKernBus testIDs:dev:fun:bus:]` took `unsigned int *` — **fixed**

| | |
| --- | --- |
| Reference | `c21@8:12r*16C20C24C28` at `0x3e4` |
| Decoded | `- (BOOL)testIDs:(const char *) dev:(unsigned char) fun:(unsigned char) bus:(unsigned char)` |
| Ours, before | `(unsigned int *)ids` plus three `unsigned int` |

Brought to Apple's signature at `PCIKernBus.h:94` and `PCIKernBus.m:364`.

Our own implementation was already the evidence that the declaration was wrong:
its first statement was `const char *idStr = (const char *)ids;`, casting the
parameter straight back to a byte string before parsing it with `strtoul`. All
three call sites had to cast a `char *` *up* to `(unsigned int *)` to satisfy
the declaration — `PCIKernBus.m:246,276` on `autoDetectIDs` (a `char *` from
`valueForStringKey:`) and `PCIResourceDriver.m:411` on `nameBuffer` (a
`char *`). The fix deletes all three casts and the one inside the body; nothing
else changed.

The sibling `EISAKernBus` already declares the analogous method Apple's way —
`- (BOOL)testIDs:(const char *)ids slot:(unsigned int)slot`
(`drvEISABus/.../EISAKernBus.h:63`) — so this driver was the outlier.

Narrowing `dev`/`fun`/`bus` to `unsigned char` is safe: each argument is a PCI
device (≤ `0x1f`), function (`< 8`) or bus number bounded by `_maxBusNum`, and
the neighbouring `getRegister:` / `setRegister:` in the same header already take
`unsigned char` for the same three values.

`r*` cannot distinguish `const char *` from `const unsigned char *` under this
compiler, which collapses any pointer-to-byte to `*`. `const char *` was chosen
because it is what the body's own local already was.

## Recorded, not changed

### Ivar names

The reference names `PCIKernBus`'s eleven ivars without our leading underscore,
and two of them differently:

| Offset | Type | Reference | Ours |
| --- | --- | --- | --- |
| +16 | `i` | `maxBusNum` | `_maxBusNum` |
| +20 | `i` | `maxDevNum` | `_maxDevNum` |
| +24 | `c` | `BIOS16Present` | `_bios16Present` |
| +25 | `c` | `configMethod1` | `_configMech1` |
| +26 | `c` | `configMethod2` | `_configMech2` |
| +27 | `c` | `specialCycle1` | `_specialCycle1` |
| +28 | `c` | `specialCycle2` | `_specialCycle2` |
| +29 | `c` | `BIOS32Present` | `_bios32Present` |
| +32 | `^v` | `BIOS32Entry` | `_reserved` |
| +36 | `i` | `majorVersion` | `_pciVersionMajor` |
| +40 | `i` | `minorVersion` | `_pciVersionMinor` |

Every offset and type now agrees, and `instance_size` matches at 44 on both
sides. Ivar names are not part of the ABI — they appear in `__OBJC` metadata but
nothing dispatches on them — and our `_`-prefixed `@private` convention is used
consistently across this driver and its siblings. Renaming eleven ivars to
recover metadata-only parity was judged not worth the diff; it is recorded here
so the difference is known rather than rediscovered.

One name is worth flagging beyond cosmetics: our `+32` is called `_reserved`,
but the reference calls it `BIOS32Entry` and types it `^v`. The slot is
therefore not spare — it holds the BIOS32 service-directory entry point. Our
`init` never populates it, so any future BIOS32 work should use this name and
not treat the field as free.

### Everything else agrees

The remaining declarations were checked against the metadata and match exactly:

- `PCIKernBus`: `init`, `free` (`@8@8:12`), `isPCIPresent` (`c8@8:12`),
  `allocateResourcesForDeviceDescription:` (`@12@8:12@16`),
  `configAddress:device:function:bus:` (`i24@8:12@16*20*24*28`),
  `getRegister:...` (`i28@8:12C16C20C24C28^L32`),
  `setRegister:...` (`i28@8:12C16C20C24C28L32`).
- `PCIKernBus(Private)`: `test_M1`, `test_M2` (`c8@8:12`) and
  `Method1:...` / `Method2:device:function:bus:data:write:`
  (`L29@8:12C16C20C24C28L32c36`).
- `PCIResourceDriver`: `+probe:` (`c12@8:12@16`),
  `initFromDeviceDescription:` (`@12@8:12@16`),
  `getCharValues:forParameter:count:` (`i20@8:12*16*20^I24`),
  `setCharValues:forParameter:count:` (`i20@8:12*16*20I24`);
  ivars `[512c] autoDetectIDs` at `+296` and `i autoDetectIDindex` at `+808`
  against our `_nameBuffer` / `_nameBufferLen` at the same offsets,
  `instance_size` 812 on both sides.

`+[PCIKernBus initialize]` (`@8@8:12`) and the `PCIBusVersion` /
`PCIBusKernelServerInstance` stubs are present in the reference and in our `.m`
files but are not declared in any header, which matches the reference.
