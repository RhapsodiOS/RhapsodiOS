# Reconstructing IOADBDevice

Write the bodies of Apple's shipped `IOADBDevice` driver — fifteen Objective-C
methods and six C functions, about 5.5 KB — into the stub project the packaging
spec created.

**Nothing in this spec is compile-verified.** There is no PowerPC toolchain.

## Motivation

Five measurement specs and two reconstruction specs covered the sixteen
PowerPC drivers whose sources are in the tree. Two shipped drivers have **no
in-tree source at all**: `IOADBDevice` and `DEC21x4Ethernet`. The packaging
spec gave both stub projects with the real class hierarchy and the real
selector lists, and empty bodies.

This spec fills `IOADBDevice`'s in, and is deliberately a **calibration
exercise**: it is the smaller of the two by an order of magnitude, and
finishing it establishes what a full greenfield reconstruction actually costs
before anyone commits to `DEC21x4Ethernet`.

### The scale, measured

| Binary | `__text` | ObjC methods | C functions |
| --- | --- | --- | --- |
| **`IOADBDevice`** | **5,524 B** | 17 symbols / 15 with bodies | 6 |
| `adbservd` | 1,488 B | 0 | 30 |
| `DEC21x4Ethernet` | 55,604 B | 40 | 116 |
| `drvstat` | 2,868 B | 0 | 35 |

Everything written across the two preceding reconstruction specs totals about
**1,850 bytes**. `IOADBDevice` alone is three times that; the full greenfield
set is thirty-five times it. That is why this spec takes one driver.

### Why this is less greenfield than it looked

The decisive discovery, made before this spec was written:
`src/kernel-7/bsd/dev/ppc/IOADBBus.h` **already declares this driver's
contract.** Its header comment records `1997-12-19 Brent Schorsch (schorsch)
created IOADBDevice.h`, and the file carries:

- `@protocol ADBprotocol`, with `GetTable:length:` and the device-info accessor
- `typedef unsigned long int IOADBDeviceState`
- `IOADBDeviceInfo`, and `kIOADBDeviceAvailable = 0x00000001`
- signatures for `setState`, `getState:`, `watchState`

`IOADBBusProt.h` carries the protocol separately, and `adb.h:127` declares
`extern struct adb_device adb_devices[ADB_DEVICE_COUNT]` — one of the binary's
undefined externals.

So the **types, the protocol and most signatures are already in the tree**.
That is a much stronger starting position than the IODisplay reconstruction
had, and it is what makes this driver a sensible first greenfield target.

## 1. Scope

### 1.1 The functions

Reference: `IOADBDevice.config/IOADBDevice_reloc`, 34180 bytes, `__text`
5524 B at 0.

**`IOADBDevice` class — 9 with bodies:**

| Method | Address | Size |
| --- | --- | --- |
| `initForDevice:result:` | `0x00e4` | 696 |
| `free` | `0x039c` | 232 |
| `getADBInfo:` | `0x0484` | 68 |
| `flushADBDevice` | `0x04c8` | 76 |
| `readADBDeviceRegister:buffer:length:` | `0x0514` | 92 |
| `writeADBDeviceRegister:buffer:length:` | `0x0570` | 92 |
| `setState:mask:` | `0x05cc` | 16 |
| `getState` | `0x05dc` | 16 |
| `watchState:mask:` | `0x05ec` | 16 |

**`ADBServer` class — 6:**

| Method | Address | Size |
| --- | --- | --- |
| `+serverMajor:` | `0x07d0` | 292 |
| `+deviceStyle` | `0x08f4` | 16 |
| `+requiredProtocols` | `0x0904` | 20 |
| `+probe:` | `0x0918` | 552 |
| `initFromDeviceDescription:` | `0x0b40` | 300 |
| `getIntValues:forParameter:count:` | `0x0c6c` | 280 |

**C functions — 6:**

| Function | Address | Size |
| --- | --- | --- |
| `_initalize` | `0x05fc` | 468 |
| `_adbServeropen` | `0x0d84` | 272 |
| `_adbServerclose` | `0x0e94` | 268 |
| `_adbServerioctlDispatch` | `0x0fa0` | 236 |
| `_adbServerIoctl` | `0x108c` | 492 |
| `_ioadbDeviceIoctl` | `0x1278` | 760 |

> `_initalize` is misspelled in Apple's binary. **Reproduce the misspelling** —
> the symbol name is the evidence, and correcting it would break the
> correspondence this whole effort measures.

### 1.2 What has no body

- The two build-generated classes, `IOADBDeviceKernelServerInstance` and
  `IOADBDeviceVersion`, which the Kernel Server build emits.

**CORRECTION.** This section originally listed `+[IOADBDevice GetTable:length:]`
here, on the grounds that it "resolves to address `0`, with no function entry"
and is therefore "a selector present in the metadata with no code". That was a
misreading of `ppc_invariant_check.py`'s output, repeated from four earlier
specs. Address `0` is `__text`'s first address, not a null one; the bytes there
are `7c0802a6` (`mflr r0`) and 208 more, and it is IDA's function list that
omits the function, not Apple's binary that omits the code. The method is
written. See `src/drivers-ppc/reconstruction/IOADBDevice/findings.md`, "The
misreading".

### 1.3 What the externals reveal

`_IOSetUNIXError`, `_NXZoneCalloc`, `_adb_devices`, `_bzero`, `_enodev`,
`_kprintf`, `_objc_msgSend`, `_objc_msgSendSuper`, `_panic`, `_printf`,
`_sprintf`, `_strcmp`, `_strlen`, `_strtol`.

`_enodev` and `_IOSetUNIXError` alongside `open`/`close`/`ioctl`-shaped C
functions say this driver exposes a **UNIX character-device interface**;
`+serverMajor:` and `_adbServerioctlDispatch` corroborate it. That framing
should guide the reading, but every claim still comes from the disassembly.

### 1.4 Out of scope

- **`adbservd`** (1,488 B, pure C, 30 functions). It is a separate userspace
  binary with no Objective-C at all, so `--scope-to-objc` maps nothing for it
  and no mechanical check applies. Its own spec.
- **`DEC21x4Ethernet` and `drvstat`.** Sequenced after this calibration.
- **Any build or claim of buildability.**
- **Modifying `IOADBBus.m`, `adb.m`, or anything else in
  `src/kernel-7/bsd/dev/ppc/`.** Those headers are read, never edited.

## 2. Design

All code goes into the existing stub project at
`src/drivers-ppc/input/drvIOADBDevice/IOADBDevice.drvproj/IOADBDevice.lksproj/`
— `IOADBDevice.{h,m}` and `ADBServer.{h,m}`. The stubs already carry the
correct class declarations and the full selector lists with empty bodies; this
spec replaces the bodies and adds the ivars, types and C functions the code
needs.

**Every stub file currently declares itself a stub.** As bodies land, those
declarations must be replaced with an accurate account — a file that still says
"every method body is empty" when they are not is worse than no note at all.

### 2.1 Reuse the tree's existing declarations

`IOADBDeviceState`, `IOADBDeviceInfo`, `kIOADBDeviceAvailable` and the
`ADBprotocol` protocol already exist in `IOADBBus.h` / `IOADBBusProt.h`.
**Include them rather than redeclaring them.** A duplicate `typedef` that
drifts from the original is exactly the failure the packaging spec's divergence
check exists to catch elsewhere.

Where a type is needed that the tree does not have, it is derived from the
binary's Objective-C metadata and recorded as derived.

### 2.2 The class layout, read from the binary — and a stub correction

Read from `__OBJC,__class` and `__OBJC,__instance_vars` before this spec was
written:

```
class IOADBDevice : Object     instance_size = 8 (0x8)
    +0x0004  ^v                       _priv
class ADBServer  : IODevice    instance_size = 268 (0x10c)
    +0x0108  {ioadb_state="ioadb"@}   state
```

Two things follow.

**The stub declares `IOADBDevice : IODevice`; the binary says `: Object`.**
`IOADBDevice.h:33` must be corrected. The packaging spec inferred the
superclass from the binary's linked-class list — where `IODevice` appears —
but `Object` is linked too, and the class table is what settles it. This is
the same class of error the IODisplay reconstruction found in reverse, and it
is why §3.2 requires reading the class table rather than inferring.

**`IOADBDevice` is a lightweight wrapper**: one `void *_priv` at `+0x4`, total
size 8 bytes. `ADBServer` carries a single `state` ivar at `+0x108`, a struct
`ioadb_state` whose one encoded field `ioadb` has type `@`. The struct's real
field names beyond `ioadb` are not in the encoding and are derived from usage,
per §3.4.

### 2.3 Ivars come from the binary

`__OBJC,__instance_vars` carries the real ivar names, types and offsets for
both classes. Those are the authority — not a guess from usage, and not our
stub's current (empty) ivar block. The IODisplay spec was blocked precisely
because a class's shipped layout disagreed with our source's; here there is no
prior source to disagree with, so the binary simply defines it.

## 3. Method

### 3.1 One function at a time, from its own disassembly

Each function is transcribed from its own listing, not from a paraphrase and
not from a sibling that looks similar.

### 3.2 The disciplines that have each caught a real defect

Carried forward from the IODisplay and fill-gaps specs, where each of these
found something:

- **Settle every method signature from `__OBJC,__meth_var_types`**, not by
  inferring from instructions.
- **Resolve every `bl` to an unnamed `sub_XXXX` through `read_macho`'s
  relocation table.** They are jump islands; IDA's export omits the target.
- **Read ivar names, types and offsets from `__OBJC,__instance_vars`.**
- **Trace every bare constant to a named constant in this tree** before writing
  it as one. This has succeeded three times running.
- **Account for every instruction and every branch in writing.** That account
  is as much the deliverable as the code.

### 3.3 Uncertainty is recorded, not guessed

A confident guess is a defect; a recorded uncertainty is a result. For a
greenfield driver there is no surrounding source to constrain a wrong reading,
so this matters more here than anywhere previous.

### 3.4 Local names are invented, and said to be

Argument names, local variable names and internal struct field names are not in
the binary. They are invented, and the deliverable says so plainly rather than
implying they were recovered.

## 4. Acceptance

1. All fifteen methods and six C functions have bodies, or are recorded as not
   writable with the evidence.
2. For each, a written account maps **every instruction** to the source
   producing it, including every branch.
3. Every constant is a named constant found in this tree, or a literal with a
   comment recording that no name was found.
4. Ivars for both classes match `__OBJC,__instance_vars` in name, type and
   order; `IOADBBus.h`'s existing types are included rather than redeclared;
   and **`IOADBDevice`'s superclass is corrected to `Object`** per §2.2.
5. `_initalize` keeps Apple's misspelling.
6. A `binrecon` profile exists for this binary, an analysis is published, and a
   source map is generated. **All fifteen methods IDA has functions for map**,
   leaving only the two build-generated accessors unmapped. `GetTable:length:`
   is written but appears in no map category, because IDA records no function
   at `__text+0` for the map to place. The map reconciles. **If a method does not map, its selector is wrong** — a real
   defect, not a tooling artifact.
7. No stub file still describes itself as a stub with empty bodies.
8. `tools/ppc_package_check.py` reports no divergences and the binrecon suite
   is green at **845 passed, 4 skipped**, plus whatever the new profile adds to
   the inventory test.
9. Every uncertainty and every invented name is listed in the deliverable.

**Not claimed:** that any of this compiles, links, loads, or is behaviourally
correct. Item 6 proves the *selectors* match Apple's binary. It does not prove
the *bodies* do, and no check available here can. For a driver with no prior
source, that gap is wider than in any preceding spec.

### 4.1 The calibration question

This spec exists partly to answer one thing: **what does a full greenfield
driver reconstruction actually cost, and how much of it survives review?** The
deliverable records the answer — functions written, defects caught in review,
uncertainties left standing — so the decision about `DEC21x4Ethernet`'s 55 KB
can be made from evidence rather than optimism.

## 5. Follow-on work

- **`adbservd`**, this driver's userspace companion.
- **`DEC21x4Ethernet` and `drvstat`**, informed by §4.1's answer.
- **A PowerPC toolchain.** Every reconstruction spec has ended with this, and
  each one strengthens the case: it is the only thing that would turn "not
  claimed" into "verified".
- **`drvPPCATA`'s two functions**, blocked on its conflicting `ata_extern.h`
  revisions.
- **`findADBDisplayInfoForType:`**, blocked on IODisplay's hierarchy
  divergence.
