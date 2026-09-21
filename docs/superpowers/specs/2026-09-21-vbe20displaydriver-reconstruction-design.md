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
| `__text` | 2,324 bytes, 14–15 partition entries (§4) |
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
`v16@8:12^{?=SSSSSCCCCCCCC^v}16I20` — it takes a pointer to a 22-byte packed
record and an unsigned count. That record is **not** Apple's 256-byte
`VBEModeInfoBlock` from `libsaio/vbe.h`; it is a distilled form.

The struct encoding gives five `unsigned short`, eight `unsigned char` and one
pointer — fourteen fields. The driver's own debug string names fourteen, in
order:

```
mode num, Attrib, BytesPerScanline, FrameBuffer, XRes, YRes, BitsPerPixel,
MemoryModel, RGB Mask Sizes (3), RGB Field Pos (3)
```

Aligning the two by type gives:

| Type | Fields |
| --- | --- |
| 5 × `unsigned short` | mode number, ModeAttributes, BytesPerScanline, XResolution, YResolution |
| 8 × `unsigned char` | BitsPerPixel, MemoryModel, R/G/B mask sizes, R/G/B field positions |
| 1 × pointer | framebuffer physical address |

This mapping is an inference from two independent sources that agree on the
field count. Phase 1 confirms it against the disassembly before it is written
down as fact anywhere else.

`boot_video` in `machdep/i386/kernBootStruct.h` has six `unsigned long` and no
room for an array of these. Where the array comes from is discovery item D1.

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
| 2288 | 24 | `-[VBE20DisplayDriver displayModes]` |
| 2312 | 12 | `+[VBE20DisplayDriver driverKitVersionForVBE20DisplayDriver]` |

Thirteen functions are hand-written. `driverKitVersionForVBE20DisplayDriver` is
emitted by the Kernel Server project type and is correctly absent from source,
as `docs/drivers/video-reconstruction.md` records for every driver in the tree.
`+[VBE20DisplayDriverKernelServerInstance kernelServerInstance]` is the second
build-generated symbol; it lives in a second `__cls_meth` method list that the
survey parse did not resolve, so the committed partition may carry fifteen
entries rather than fourteen. Phase 1 settles the count.

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

## 6. Parity policy

The reference was compiled against OPENSTEP 4.2's `IOFrameBufferDisplay`. We
compile against Rhapsody's. If the inherited ivar block changed size between the
two releases, every ivar access in the reconstruction shifts by a constant and
byte-parity fails across the whole driver from one root cause — not because the
source is wrong.

Every other reconstruction in this tree targets a same-release reference, so
this risk is new and is resolved by measurement before a target is chosen.

**Phase 0** computes Rhapsody's `IODisplay` + `IOFrameBufferDisplay` instance
size and compares it against the 552 the reference implies.

- **If they agree**, the spec targets byte-parity throughout, tracked in
  `ledger.json` exactly as Cirrus and ThinkPad are.
- **If they differ**, `divergences.md` records the delta and its cause once, up
  front. Functions that touch no ivars still target byte-parity; the rest target
  function-parity, and each such ledger entry cites the shared root cause rather
  than repeating it.

Phase 0 is cheap — it reads two headers and one number out of the reference —
and it is a gate: no reconstruction work starts until the target is fixed.

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
| 0 | Rhapsody `IOFrameBufferDisplay` instance size measured against the reference's 552; parity target fixed in writing |
| 1 | `VBE20DisplayDriver_reloc` compiles and links against `driverkit-3` on the Rhapsody build guest |
| 2 | binrecon ledger complete: every partition entry reviewed with a status and a reason, `reference_sha256` and `rebuilt_sha256` both real |
| 3 | Boots under QEMU per `docs/drivers/drvVGA-boot-gate.md` |

Gate 3 follows the established procedure: `graft-kernel.py`, then
`rhap_inject.py set-key` for `Active Drivers`, then `put` for the driver, then
hash-verify the injected copy in the image before booting. The bus retest's PCIC
near-miss showed a refused injection still yields a plausible-looking boot of
somebody else's driver, so the hash check is not optional.

**Gate 3's reachable depth is limited until spec 3 lands.** The booter does not
currently enter a VBE mode — `"Graphics Mode"` is never set in any config table,
so `setMode()` falls through to text. The driver will therefore take its
`%s: Skipping framebuffer initialization (card not in VBE mode).` path. That
still proves load, initialisation, config-table read, mode-list export and
registration as `VBEDisplay0`, and it is the honest gate for this spec. The
`%s: using VBE mode %d` path becomes reachable only after spec 3, and is gated
there.

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

**The ivar-layout shift** is the main one, and §6 handles it by measuring first.

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
