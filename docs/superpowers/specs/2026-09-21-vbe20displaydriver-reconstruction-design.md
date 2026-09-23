# Binary reconstruction of drvVBE20DisplayDriver

Reconstruct `VBE20DisplayDriver_reloc`, the kernel half of the VESA 2.0 display
driver Apple shipped in OPENSTEP 4.2 User Patch 4, against that reference
binary. The driver has never existed in this tree; Rhapsody dropped it, along
with the two kernel functions it depends on.

This is the first of three specs covering the i386 VESA boot path. It runs
first because the driver's call sites are what pin down the kernel contract the
other two specs implement. The kernel work (`FBAllocateVBEConsole`,
`VBEModeInfo2IODisplayInfo`) and the booter work (the VBE mode list and three
defects in `boot-2`) are out of scope here and get their own specs.

The Configure.app inspector half is out of scope. See §1.3.

## Motivation

`src/boot-2/i386` carries a complete VBE implementation — `libsaio/vbe.c`,
`libsaio/vbe.h` (headed "vesa.h", Doug Mitchell, 30 Jul 1996) and the mode table
in `boot2/graphics.c`. It sets a linear framebuffer mode and records the result
in `kernBootStruct->video`.

Nothing on i386 reads it. `kernBootStruct->video` has exactly one consumer in
the tree and it is `bsd/dev/ppc/kmDevice.m`. The i386 boot console
(`bsd/dev/i386/BasicConsole.c`) programs VGA registers directly for 640x480x4
planar at `0xA0000` and ignores the framebuffer the booter set up.

The missing consumer is this driver, plus a kernel console allocator. Both are
in Patch 4. Reconstructing the driver first establishes what the kernel must
provide, so specs 2 and 3 implement against a known contract instead of a guess.

## 1. Scope

### 1.1 Target

Staged from `~/Downloads/OS42MachUserPatch4.tar` to the conventional reference
location, `C:\Users\raynorpat\Downloads\test\Drivers\i386\VBE20DisplayDriver.config\`.

| Property | Value |
| --- | --- |
| Mach-O type | MH_PRELOAD |
| File size | 37,984 bytes |
| SHA-256 | `9FBC2CAFBDD0124CC63B902161C86BBFEC0EF48D591DDA681A325FF7B68DADED` |
| `cpu_subtype` | 3 (`CPU_SUBTYPE_386`) |
| `__text` | 2,324 bytes, 15 partition entries (§4) |
| `__cstring` | 1,111 bytes, 38 strings |
| Symbols | 22 (5 defined, 17 undefined) |
| Relocations | 262, of which 169 in `__text` |

`BINRECON_REFERENCE` is that `_reloc` path. Reference binaries stay outside git
per `.gitignore` and `tools/binrecon/README.md`.

The extraction is not a plain `tar x`. The patch is a NeXT `.pkg` wrapping
`OS42MachUserPatch4.tar.Z`, and the inner archive uses a **225-byte name
field** instead of the standard 100, putting every other header field at +125
from its usual offset (size at 249, mtime at 261). GNU tar and Python
`tarfile` both reject it. Headers are still 512-byte aligned and data still
follows at +512, so a direct parser handles it in a few lines.

### 1.2 In scope

The thirteen hand-written functions of §4, `VBE20DisplayDriver.m` and its
header, the driver project wrapper, and the binrecon profile, ledger, source map
and divergences record.

`Default.table` (482 bytes, SHA-256 `02EF18A5…`) and `English.lproj/Localizable.strings`
are taken verbatim from the patch and are not reconstructed.

### 1.3 Out of scope

**The Configure.app inspector.** The patch ships a second binary beside the
`_reloc`, `VBE20DisplayDriver` (7,864 bytes, MH_OBJECT, SHA-256 `2033405F…`),
implementing `VBEInspector : IODisplayInspector` with a `DisplayInspector.nib`.
It is a GUI mode-picker that writes `"VBE Mode"` into the config table. It links
against AppKit and Foundation and needs nib handling — a toolchain path no video
driver in this tree has taken. The driver runs without it; the table can be
edited directly, as every drvVGA boot gate does. It is a candidate for a later
spec, not this one.

**The kernel functions and the booter.** Specs 2 and 3.

## 2. What the driver does

The partition establishes this rather than assuming it.

`enterLinearMode` and `revertToVGAMode` are 8 bytes each, and
`initDisplayInfo:fromVBEModeInfo:` is 20. Sizes that small leave room for a
`ret` and very little else, so the working hypothesis is that the first two are
empty overrides and the third is a pure forwarder to the kernel's
`VBEModeInfo2IODisplayInfo`. **Phase 1 confirms or refutes this from the
disassembly; nothing downstream may assume it beforehand.**

If it holds, the driver never sets a video mode. That is consistent with
`Default.table` declaring no I/O ports, no memory maps and no IRQ levels, with
the absence of any real-mode BIOS machinery (no `vidBIOS`, no `emu486`, unlike
drvVGA), and with the string `%s: Skipping framebuffer initialization (card not
in VBE mode).` The booter sets the mode; the driver inherits it, describes it to
DriverKit, and exports the mode list as driver parameters.

The single kernel dependency is `_VBEModeInfo2IODisplayInfo`, an undefined
external. The full undefined set is:

```
_IOLog  _VBEModeInfo2IODisplayInfo  _calloc  _objc_getOrigClass
_objc_msgSend  _objc_msgSendSuper  _page_mask  _sprintf
_strcat  _strcpy  _strncmp  _strncpy
.objc_class_name_{IODevice,IODisplay,IOFrameBufferDisplay,Object}
_VBE20DisplayDriver_instance
```

Everything but `_VBEModeInfo2IODisplayInfo` is already available to a Rhapsody
kernel driver.

## 3. The booter-to-driver contract

`parseVESAModes:size:` has the ObjC type encoding
`v16@8:12^{?=SSSSSCCCCCCCC^v}16I20` — it takes a pointer to a fourteen-field
record and an unsigned count. That is 22 bytes of data and **24 bytes with
padding**, which is the stride the disassembly confirms. It is **not** Apple's
256-byte `VBEModeInfoBlock` from `libsaio/vbe.h`; it is a distilled form.

The struct encoding gives five `unsigned short`, eight `unsigned char` and one
pointer — fourteen fields. The driver's own debug string names fourteen, in
order:

```
mode num, Attrib, BytesPerScanline, FrameBuffer, XRes, YRes, BitsPerPixel,
MemoryModel, RGB Mask Sizes (3), RGB Field Pos (3)
```

**The struct does not follow the print order** — an earlier draft of this spec
assumed it did and got two things wrong. Task 3 recovered the real layout from
the disassembly:

| Offset | Type | Field |
| --- | --- | --- |
| 0x00 | `unsigned short` | `modeNumber` |
| 0x02 | `unsigned short` | `modeAttributes` |
| 0x04 | `unsigned short` | `xResolution` |
| 0x06 | `unsigned short` | `yResolution` |
| 0x08 | `unsigned short` | `bytesPerScanline` |
| 0x0A | `unsigned char` | `bitsPerPixel` |
| 0x0B | `unsigned char` | `memoryModel` |
| 0x0C–0x11 | 6 × `unsigned char` | red mask/position, green mask/position, blue mask/position — **interleaved**, not grouped |
| 0x12–0x13 | — | padding, untouched by either side |
| 0x14 | pointer | `frameBuffer` |

`bytesPerScanline` is fifth, not third, and the colour bytes pair each mask
size with its field position rather than listing three sizes then three
positions.

**D1 is answered (Task 2), and the mapping is confirmed.**
`initFromDeviceDescription:` passes two *unrelocated* absolute literals,
`0x12858` and `0x12870`, while every other `push` in that function carries a
relocation into `__cstring`. `KERNSTRUCT_ADDR` is `0x11000`, so those are
`kernBootStruct + 0x1858` and `+ 0x1870` — 24 bytes apart, the record stride.
The mode array is a hard-coded `KERNBOOTSTRUCT` member that the booter fills,
and the reconstruction must emit plain integer constants carrying no symbol.

**This is the hinge for spec 3, and Task 4 measured the damage.** Those offsets
are into *OPENSTEP 4.2*'s `KERNBOOTSTRUCT`. Rhapsody's struct, measured on the
build guest with `offsetof` and `cc -arch i386 -S` against
`src/boot-2/i386/libsa/kernBootStruct.h` — not by hand; an earlier hand layout
in this spec was 12 bytes out — places:

| Field | Range |
| --- | --- |
| `_reserved[7500]` | 908 (`0x38C`) .. 8408 (`0x20D8`) |
| `boot_video` | 8408 .. 8432 |

Both `0x1858` (6232) and `0x1870` (6256) fall inside `_reserved`. Nothing under
`src/` writes them, and this booter's only video hand-off is
`kernBootStruct->video` at `boot2/graphics.c:204-208`.

**The operational consequence:** booted on Rhapsody today, the driver reads
`_reserved`, which `getKernBootStruct()` has `bzero`'d
(`src/boot-2/i386/libsa/bootstruct.c:84`) — so it reads deterministic zeros,
not garbage. `xResolution` is 0, the driver takes the "card not in VBE mode"
path and exports an empty mode list. That is the expected result of gate 3, and
it is now expected for *two* independent reasons: the booter never enters a VBE
mode, and even if it did it would not write where the driver reads.

One arithmetic coincidence worth flagging to spec 3: `0x1870 + 0x880` is 8432,
exactly the end of `boot_video`. So the array the reference declares overlaps
`video` in our layout. Whether `parseVESAModes:size:` would ever walk that far
is unknown.

**The kernel driver never reads its own config table.** Task 5 established
this: the reference contains no `VBE Mode` string, no `configTable`, and no
`valueForStringKey` — it has no config-table accessor at all. `VBEBooterMode`
and `VBEMode` are present, but as `getCharValues:` parameter names, not table
keys.

So `"VBE Mode" = "257"` in `Default.table` is not consumed by this driver. The
only remaining consumer is the **booter**, which loads Boot Drivers and their
tables and which `Default.table` marks this driver as (`"Boot Driver" = "Yes"`).
That closes the architecture: the Configure.app inspector writes the key, the
booter reads it and enters that VBE mode, the booter fills the mode array, and
the driver reads the array and describes the result to DriverKit. The driver is
a pure consumer at both ends.

Spec 3 therefore cannot simply adopt the 4.2 constants. It must either place
the array where the driver already reads — inside `_reserved`, which fixes that
offset as ABI — or add real members and accept that the reconstruction's
hard-coded addresses become a recorded divergence.

`boot_video` in `machdep/i386/kernBootStruct.h` has six `unsigned long` and no
room for an array of these, which is why spec 3 has to find or make the space.

## 4. Function partition

`__text` is 2,324 bytes and every byte is accounted for. Offsets are from the
relocated ObjC method lists; sizes are the differences between consecutive
entries.

| Offset | Size | Function |
| --- | --- | --- |
| 0 | 144 | `-[IOFrameBufferDisplay(UnnamedInitialization) initUnnamedFromDeviceDescription:]` |
| 144 | 548 | `-[VBE20DisplayDriver initFromDeviceDescription:]` |
| 692 | 292 | `-[VBE20DisplayDriver parseVESAModes:size:]` |
| 984 | 20 | `-[VBE20DisplayDriver initDisplayInfo:fromVBEModeInfo:]` |
| 1004 | 188 | `-[VBE20DisplayDriver modeStringForDisplayInfo:]` |
| 1192 | 48 | `-[VBE20DisplayDriver atoi:]` |
| 1240 | 676 | `-[VBE20DisplayDriver getCharValues:forParameter:count:]` |
| 1916 | 8 | `-[VBE20DisplayDriver enterLinearMode]` |
| 1924 | 8 | `-[VBE20DisplayDriver revertToVGAMode]` |
| 1932 | 244 | `-[VBE20DisplayDriver descriptionForDisplayInfo:]` |
| 2176 | 100 | `-[VBE20DisplayDriver descriptionForVBEMode:]` |
| 2276 | 12 | `-[VBE20DisplayDriver displayModeCount]` |
| 2288 | 12 | `-[VBE20DisplayDriver displayModes]` |
| 2300 | 12 | `+[VBE20DisplayDriverKernelServerInstance kernelServerInstance]` |
| 2312 | 12 | `+[VBE20DisplayDriverVersion driverKitVersionForVBE20DisplayDriver]` |

**Fifteen entries, thirteen of them hand-written.** The two build-generated ones
are emitted by the Kernel Server project type and are correctly absent from
source, as `docs/drivers/video-reconstruction.md` records for every driver in
the tree.

The entry at 2300 was resolved in Task 1, not the survey: it sits in a second
`__cls_meth` method list the survey parse did not read, and its body is
`push %ebp; mov %esp,%ebp; mov $0x0,%eax; mov %ebp,%esp; pop %ebp; ret` with an
external relocation on the immediate to `_VBE20DisplayDriver_instance` — the
shape `+kernelServerInstance` takes in every Kernel Server driver. That
correction also takes `displayModes` from 24 bytes to 12.

Classes and metaclasses, from `__OBJC,__class` and `__OBJC,__meta_class`:

| Class | Superclass | `instance_size` |
| --- | --- | --- |
| `VBE20DisplayDriver` | `IOFrameBufferDisplay` | 552 |
| `VBE20DisplayDriverVersion` | `IODevice` | 264 |
| `VBE20DisplayDriverKernelServerInstance` | `Object` | 4 |

plus one category, `IOFrameBufferDisplay(UnnamedInitialization)`.

Rhapsody's `driverkit-3` already declares `_displayModeCount`, `_displayModes`,
`enterLinearMode` and `revertToVGAMode` on `IOFrameBufferDisplay`, which is
exactly the set this driver overrides. `initUnnamedFromDeviceDescription:`
appears nowhere in `driverkit-3`, so the category adds a genuinely new method
and does not collide.

## 5. Source tree

Mirrors `drvCirrusLogicGD5434`, the most complete video reconstruction in the
tree. `VBE20DisplayDriver.m` is the single hand-written source, the name the
reference's `__OBJC,__module_info` carries.

```
src/drivers-i386/video/drvVBE20DisplayDriver/
├── Makefile
├── Makefile.postamble
├── VBE20DisplayDriver.drvproj/
│   ├── Default.table                      (verbatim from the patch)
│   ├── DriverInfo
│   ├── Makefile, Makefile.preamble, Makefile.postamble
│   ├── English.lproj/
│   │   ├── Localizable.strings            (verbatim from the patch)
│   │   └── Help/
│   └── VBE20DisplayDriver_reloc.lksproj/
│       ├── VBE20DisplayDriver.h
│       ├── VBE20DisplayDriver.m
│       ├── Load_Commands.sect
│       └── Makefile, Makefile.preamble, Makefile.postamble
└── reconstruction/
    ├── VBE20DisplayDriver_reloc/
    │   ├── ledger.json
    │   └── source-map.json
    └── divergences.md
```

The reference's build path names the subproject `VBE20DisplayDriver_reloc.tproj`
where Rhapsody Kernel Server projects use `.lksproj`. We follow the Rhapsody
convention and record the divergence.

The `Loaded Server` segment (`Server Name`, `Load Commands`, `Instance Var`,
`Server Version`) is produced from `Load_Commands.sect`, as in Cirrus.

## 6. Parity policy — resolved

> Phase 0 ran in Task 1 and settled this section. The original concern is kept
> below the result because the measurement it produced is evidence specs 2 and 3
> will want.

**Target: byte-parity throughout.** No function needs a function-parity
exemption.

The worry was that the reference is compiled against OPENSTEP 4.2's
`IOFrameBufferDisplay` while we compile against Rhapsody's, so a change in the
inherited ivar block would shift every inherited-ivar access. Two findings
retired it.

**The chain did not move.** `__OBJC,__instance_vars` in the reference is 0
bytes — `VBE20DisplayDriver` declares no ivars of its own — so its
`instance_size` of 552 measures 4.2's inherited chain exactly. Rhapsody's same
chain measures **552**, a delta of zero:

| Class | Bytes |
| --- | --- |
| `Object` | 4 |
| `IODevice` | 260 |
| `IODirectDevice` | 32 |
| `IODisplay` | 212 (of which `IODisplayInfo` is 136) |
| `IOFrameBufferDisplay` | 44 |
| **Total** | **552** |

The chain is `IOFrameBufferDisplay : IODisplay : IODirectDevice : IODevice :
Object`. Earlier drafts of this spec omitted `IODirectDevice` and summed 520;
that was a drafting error, not a measurement. Two independent checks in the
reference corroborate 552: `VBE20DisplayDriverVersion : IODevice` has
`instance_size` 264 = 4 + 260, and the category initialiser stores to
+0x210/+0x214/+0x218/+0x21c, which are `_currentDisplayMode`,
`_pendingDisplayMode`, `_displayModeCount` and `_displayModes` in the 552
layout.

**The driver reads no inherited ivars anyway.** `displayModes` and
`displayModeCount` do not return `_displayModes` and `_displayModeCount`, as
this spec previously asserted. They read two file statics in `__DATA,__data`
(8 bytes, exactly two 4-byte slots) that `parseVESAModes:size:` writes:

```
displayModeCount  55 89 e5  a1 04 20 00 00  89 ec 5d c3   mov __data+4,%eax
displayModes      55 89 e5  a1 00 20 00 00  89 ec 5d c3   mov __data+0,%eax
```

Both carry a local relocation into `__DATA,__data`. The reconstruction must
therefore declare them as file statics with explicit initialisers — an explicit
initialiser is what places a static in `__data` rather than `__bss` under this
compiler, the same finding `drvVGA` recorded for `IOVGADisplay.m`.

## 7. Discovery items

Answered from the disassembly. None are invented, and none may be assumed by
specs 2 or 3 until answered.

| | Item | Why it matters |
| --- | --- | --- |
| D1 | Where `parseVESAModes:size:` gets its mode array — config table, device description, or a `kernBootStruct` field Rhapsody lacks | Shapes specs 2 and 3 entirely |
| D2 | `VBEModeInfo2IODisplayInfo`'s exact signature | Spec 2 implements it; cross-check against the kernel's own copy at `0x0019ED8C` |
| D3 | What `VBEBooterMode` is — config key, parameter name, or both | Determines how the booter's choice reaches the driver |
| D4 | Whether the two 8-byte methods are genuinely empty | §2's architecture claim rests on it |
| D5 | Why the driver ships its own `atoi:` | Probably no libc `atoi` in the kernel driver environment; confirms the available runtime |

## 8. Verification gates

| Gate | Check |
| --- | --- |
| 0 | **Passed in Task 1.** Rhapsody's inherited chain measures 552 against the reference's 552; target fixed at byte-parity throughout (§6) |
| 1 | `VBE20DisplayDriver_reloc` compiles and links against `driverkit-3` on the Rhapsody build guest |
| 2 | binrecon ledger complete: every partition entry reviewed with a status and a reason, `reference_sha256` and `rebuilt_sha256` both real |
| 3 | **Passed 2026-09-22**, once spec 2 landed. Boots under QEMU per `docs/drivers/drvVGA-boot-gate.md`; record in `docs/kernel/i386-vbe-console.md` |

### Gate 3 was blocked on spec 2; it has now run and passed

**Result, 2026-09-22.** Spec 2 (`docs/superpowers/specs/2026-09-21-i386-vbe-kernel-support-design.md`)
added `_VBEModeInfo2IODisplayInfo` to the kernel. With that kernel, `sarld`
links this driver and the kernel's log shows all three lines below, as
`VBEDisplay0: ...`. The driver also printed `Driver loaded to export VBE mode
list.` and `No VBE modes found.` No other boot driver lost its registration —
a check that cannot by itself rule out a cascade, since this driver links
last in `Boot Drivers`; that an undefined-symbol failure would not cascade at
any position anyway is the inference noted below, not a measurement.
**[REFUTED — spec 3 G5 (docs/kernel/i386-vbe-console.md, G5): linked first
on a kernel without the symbol, the failure cascaded into all six other boot
drivers and the kernel panicked `Missing EISA kernel bus class`.]**
`Boot Drivers` alone was enough; `Active Drivers` did not need changing.

The same bundle on a pre-spec-2 kernel fails with the undefined symbol this
section predicted. The cascade and panic it also predicted were not seen, but
that run could not have seen them: the driver links last in `Boot Drivers`, so
nothing links after it, and `EISABus`, the driver whose loss the predicted
panic names, links before it. The booter shows `rld(): Undefined symbols:
_VBEModeInfo2IODisplayInfo`, and the kernel logs `configureDriver: driver
class 'VBE20DisplayDriver' was not loaded`. That it would not cascade at other
positions either is an inference, from
`src/cctools-2/ld/symbols.c:3523`/`ld.c:2059` and
`rld.c:402-405`/`1493`/`1674-1676`: an undefined-symbol failure is raised via
`error()`, which unloads only the one driver, not via `fatal()`→`cleanup()`,
which is what `docs/boot/sarld-driver-link-limit.md`'s cascade (a malloc
fatal) depends on.
**[REFUTED — spec 3 G5 (docs/kernel/i386-vbe-console.md, G5): the
conclusion, not the reading of `error()`. Linked first on a kernel without
the symbol, with the stock booter and `sarld`, the undefined-symbol error was
followed by EIDE's link failing with `rld(): virtual memory exhausted (malloc
failed)`, the malloc fatal named above. The latch refused the other five, and
the kernel panicked `Missing EISA kernel bus class`. The same order on a kernel with the
symbol lost nothing. The error itself returns through `rld.c:402-405` and
does not longjmp (`ld.c:2046-2064`), as read here; how the failed link leads
to the malloc fatal was not determined.]**

The `_VBE20DisplayDriver_instance` difference did not stop the load.

The booter that ran is Apple's stock v5.0.41.1, not `src/boot-2`. The
procedure, hashes and limits are in `docs/kernel/i386-vbe-console.md`.

The text below is the pre-run notice, kept as written — except that its
cascade-and-panic prediction is contradicted by the `rld.c` inference above,
not by the run. The run saw only the undefined-symbol failure and no panic,
in a position where neither a cascade nor that panic could show.
**[REFUTED — spec 3 G5 (docs/kernel/i386-vbe-console.md, G5): that
inference is refuted at the first position, where the cascade and the panic
were both measured. The prediction below held there.]**

`Default.table` marks this a Boot Driver, so the booter links it against the
kernel with `sarld`. `_VBEModeInfo2IODisplayInfo` is undefined in our `_reloc`,
nothing in `src/kernel-7` defines it, and no shipped Rhapsody kernel exports it
— so the link fails. Per `docs/boot/sarld-driver-link-limit.md` that failure
**cascades into every driver linked afterwards** and surfaces as
`panic: Missing EISA kernel bus class`, which names none of the cause.
**[VINDICATED at the first position — spec 3 G5
(docs/kernel/i386-vbe-console.md, G5): linked first on a kernel without the
symbol, the failed link was followed by EIDE's `rld(): virtual memory
exhausted (malloc failed)`, every later boot driver was refused, and the
kernel panicked `Missing EISA kernel bus class`. Linked last, it took down
nothing, since nothing links after it. The middle positions were not tried,
and whether this is the node limit that document describes was not
determined.]**

**Spec 2 alone unblocks the gate as described below.** Spec 3 is required only
for the deeper `%s: using VBE mode %d` path.

The procedure lives in the plan's Task 9, not here. Note in particular that
`rhap_inject.py` **cannot create the bundle**: it has only `set-key` and `put`,
both of which repoint an *existing* directory entry, and
`VBE20DisplayDriver.config` does not exist in `golden.img`. Use
`vm/install-driver.py`, which allocates the bundle and registers it in
`Boot Drivers`, matching this driver's `"Boot Driver" = "Yes"`. An earlier
revision of this section prescribed the `rhap_inject.py` route; it cannot work.

**What the gate will prove once unblocked.** The booter does not enter a VBE
mode — `"Graphics Mode"` is never set in any config table, so `setMode()` falls
through to text — and the 4.2 mode-array offsets land in `_reserved` regardless
(section 3). The driver will therefore take its
`%s: Skipping framebuffer initialization (card not in VBE mode).` path, proving
load, initialisation, mode-list export and registration as `VBEDisplay0`.

It does **not** prove a config-table read. Section 3 records that this driver
has no config-table accessor at all — no `configTable`, no `valueForStringKey`.
An earlier revision of this list claimed otherwise.

Gate 3 looks for these two `__cstring` entries reaching the console, plus the
DriverKit registration line:

```
%s: VESA video driver initialization.
%s: Skipping framebuffer initialization (card not in VBE mode).
Registering: VBEDisplay0
```

The `%s` is the driver's own `name`. Whether it prints as `VBEDisplay0` or
something else depends on where `setName:` falls relative to the two `IOLog`
calls, which phase 1 establishes; the gate matches on the fixed text, not on the
prefix.

## 9. Risks

~~**The inherited ivar-layout shift.**~~ Retired by Task 1: the chain measures
552 on both sides and the driver reads no inherited ivars at all. See §6.

**`initFromDeviceDescription:` at 548 bytes and
`getCharValues:forParameter:count:` at 676** are over half the driver between
them. Both are string-heavy — `getCharValues:` builds the mode descriptions the
inspector reads, from the `IO_*BitsPerPixel` / `IO_*ColorSpace` literals and
`sprintf`. String-building code is where compilers differ most in register
allocation, so these are where byte-parity is least likely and where the ledger
will need the most reasoning.

**D1 may not be answerable from this binary alone.** If `parseVESAModes:size:`
reads a `kernBootStruct` field, the field's offset will be visible but its
provenance will not. The 4.2 kernel's i386 slice
(SHA-256 `33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890`,
1,117,920 bytes, extracted from the fat `mach_kernel` at offset 835,584) and the
4.2 booter (`usr/standalone/i386/boot`, 44,848 bytes, SHA-256 `925D35B6…`) are
both available as cross-references, and spec 3 will need the booter anyway.

**The driver may not be loadable at all** under Rhapsody DriverKit if the
`Loaded Server` layout or the Kernel Server ABI moved between releases. Gate 1
catches a link failure; gate 3 catches a load failure. Neither is expected —
Cirrus and VGA both load, and they use the same machinery — but this is the
first 4.2-sourced driver in the tree.

## 10. Success criteria

1. Phase 0 has produced a written parity target and `divergences.md` records the
   ivar measurement either way.
2. `src/drivers-i386/video/drvVBE20DisplayDriver` builds a `_reloc` that links
   clean against `driverkit-3`.
3. `ledger.json` covers every `__text` partition entry with a reviewed status;
   no placeholder hashes.
4. D1 through D5 are answered in `divergences.md`, or explicitly recorded as
   unanswerable from this binary with the reason.
5. The driver loads under QEMU and logs the three lines of §8.
6. `src/drivers-i386/README` and `docs/drivers/video-reconstruction.md` carry
   the new driver with an accurate status line.
