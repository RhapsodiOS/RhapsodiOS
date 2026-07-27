# Binary reconstruction of the Cirrus Logic GD5434 and IBM ThinkPad 760ED display drivers

Reconstruct `CirrusLogicGD5434DisplayDriver_reloc` and
`IBMThinkPad760EDDisplayDriver_reloc` against Apple's shipped i386 driver
binaries, using the `tools/binrecon` toolchain. Both of our sources are
inventions rather than reconstructions, so each driver gets a report pass that
maps and decompiles every reference function, followed by a rewrite pass and a
guest build.

This continues
[2026-07-25-vga-driver-binary-reconstruction-design.md](2026-07-25-vga-driver-binary-reconstruction-design.md),
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md)
and
[2026-07-26-isaserialport-binary-reconstruction-design.md](2026-07-26-isaserialport-binary-reconstruction-design.md).
The reference-only profiles, the `binrecon source-map` subcommand, the
`load_source_map` semantic loader, the `reconstruction/` artifact layout, the
`ledger-v1` vocabulary, `tools/binrecon/parity_check.py`, and the
`vm/build-i386-*.sh` harness model are reused unchanged.

## Motivation

`src/drivers-i386/README` lists `drvCirrusLogicGD5434` and
`drvIBMThinkPad760EDDisplay` with no status at all — the only two i386 video
drivers other than `drvVGA` in that condition, and `drvVGA`'s status at least
says "reconstruction in progress".

Scoping read the reference symbol tables, `__OBJC` metadata, `__cstring`
sections and config resources before any analyzer run. Neither of our sources
shares a class, a method or a string with the binary it is supposed to
reproduce (§2.1). Both projects are also misconfigured to a degree that would
prevent them ever producing Apple's binary (§2.3), and both are missing most of
Apple's config resources (§2.4).

As with the VGA effort, this is not a parity-and-divergence exercise. There is
nothing to diff. Every function is written from the reference disassembly.

## 1. Scope

### 1.1 Targets

Two `_reloc` kernel servers under
`C:\Users\raynorpat\Downloads\test\Drivers\i386`:

| Binary | Mach-O type | File size | `__text` | Functions | Reconstructed here |
| --- | --- | --- | --- | --- | --- |
| `CirrusLogicGD5434DisplayDriver_reloc` | MH_PRELOAD | 41992 | 4388 | 21 | 4388 bytes, 19 hand-written |
| `IBMThinkPad760EDDisplayDriver_reloc` | MH_PRELOAD | 73168 | 18204 | 38 | 6528 bytes, 29 hand-written |

The remaining two functions in each binary are the build-generated glue of
`_instance.m`, described in the VGA spec's §2.8.

> **Corrected after Task 7.** The ThinkPad's function count is **40**, not 38.
> The two extra entries are unnamed routines at 15796 and 15877, past the end of
> IDA's extent for `_emu486` and deep inside the deferred region; `VGA_reloc`'s
> map has the same pair 156 bytes lower. The 29 hand-written and the two
> `_instance.m` glue functions are unaffected, so the remainder is nine deferred
> entries, not seven. See the ThinkPad `divergences.md`, "Function partition".

`CirrusLogicGD5434DisplayDriver_reloc` carries `cpu_subtype = 3`;
`IBMThinkPad760EDDisplayDriver_reloc` carries `cpu_subtype = 4`
(`CPU_SUBTYPE_486`), the same value that forced IDA to `-pmetapc` for
`VGA_reloc` (§5).

SHA-256:

```
7da038ccea1cde68b6cf2acf4d12ee5056e7f0248add34d451fb96ea79c13d0d  CirrusLogicGD5434DisplayDriver_reloc
47539e03c441bbfd6724eb6778d85bfacd0961b78a8dfa33d56321c938eb5aec  IBMThinkPad760EDDisplayDriver_reloc
```

Reference paths, per shell session via `BINRECON_REFERENCE`:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\CirrusLogicGD5434DisplayDriver.config\CirrusLogicGD5434DisplayDriver_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\IBMThinkPad760EDDisplayDriver.config\IBMThinkPad760EDDisplayDriver_reloc
```

Both binaries retain a full symbol table, so address-to-name resolution is
exact rather than gap-derived — with the six `vidBIOS` methods the sole
exception, which `__OBJC,__inst_meth` recovers (§1.4).

### 1.2 The `.config` bundle executables are out of scope

Each `.config` also contains a non-`_reloc` MH_BUNDLE executable:

| Bundle | File size | `__text` | Contents |
| --- | --- | --- | --- |
| `CirrusLogicGD5434DisplayDriver` | 16728 | 34 | dyld glue only |
| `IBMThinkPad760EDDisplayDriver` | 16724 | 34 | dyld glue only |

Their entire `__text` is `dyld_stub_binding_helper` (20 bytes) and
`__dyld_func_lookup` (14 bytes). The only other content is
`_<Name>_VERS_STRING` and `_<Name>_VERS_NUM` in `__TEXT,__const`, 4 bytes of
`__DATA,__data` and 8 of `__DATA,__dyld`.

These are what `driver.make` emits for a driver bundle's main executable from
the generated version file. There is no source to reconstruct, and no
subproject to add — `drvS3Generic`, which the README marks complete, has no
such subproject either and Apple's `S3GenericDisplayDriver` bundle is the same
16712-byte stub. This is unlike `drvVGA`, whose `VGA_psdrvr` is a real Window
Server framebuffer driver with 22 functions.

Verification of these bundles is limited to their existence after the guest
build.

> **Corrected after Task 5 — criterion unmet and open.** No version bundle was
> produced for either driver. `vm/build-i386-video-recon.sh` prints
> `WARNING: no CirrusLogicGD5434DisplayDriver version bundle produced`, and the
> ThinkPad's `kl_ld` object list has no `_vers.o` either. Correspondingly
> `_..._VERS_STRING` and `_..._VERS_NUM` are absent from both rebuilt
> `__TEXT,__const` sections. This is an open build-configuration gap, not a
> waived requirement; see §4.3 step 7 and both `divergences.md` files.

### 1.3 Other drivers are out of scope

The four Number9 drivers, both Weitek drivers, and
`MatroxMGA2064WDisplayDriver` are excluded by instruction. No other driver,
and no part of `src/kernel-7`, is touched.

### 1.4 `vidBIOS.m` and `_emu486` are deferred to drvVGA

`IBMThinkPad760EDDisplayDriver_reloc` carries its own copy of the `vidBIOS`
class and the `_emu486` real-mode emulator — 11652 of its 18204 `__text`
bytes:

| Address | Size | Symbol |
| --- | --- | --- |
| 6552 | 268 | `-[vidBIOS init]` |
| 6820 | 108 | `-[vidBIOS free]` |
| 6928 | 696 | `-[vidBIOS int10:outregs:iorange:ionum:smmport:]` |
| 7624 | 44 | `-[vidBIOS int10:outregs:iorange:ionum:]` |
| 7668 | 16 | `-[vidBIOS scratchSegment]` |
| 7684 | 24 | `-[vidBIOS realToVirtual::]` |
| 7708 | 10496 | `_emu486` |

`VGA_reloc` has the same six `vidBIOS` methods spanning 6396 to 7551 — 1156
bytes, exactly the extent 6552 to 7708 occupies here — and the same `_emu486`.
Two independently linked binaries carrying byte-identical method extents for
the same six selectors is strong evidence of a single shared source file,
compiled into each driver rather than dynamically linked from the other.

[2026-07-25-vga-driver-binary-reconstruction-design.md](2026-07-25-vga-driver-binary-reconstruction-design.md)
already owns the reconstruction of both, and
`drvVGA/reconstruction/divergences.md` already contains the `vidBIOS`
interface, its three instance variables, and seven independent observations
that `_emu486` is hand-written assembly. Reconstructing them a second time here
would duplicate that effort and pre-empt a decision belonging to that spec.

This effort therefore:

- excludes the range 6552–18204 from the ThinkPad rewrite;
- leaves those seven entries in `unmapped` in the ThinkPad source map, with the
  deferral stated in `divergences.md` rather than left to be inferred;
- lists `vidBIOS.m` and the emulator's assembly file in the ThinkPad's
  `lksproj` Makefile from the start, so that adding the sources is the only
  remaining step;
- records the 1156-byte extent match so that the drvVGA effort can use this
  binary as an independent second copy to cross-validate its reconstruction
  against.

> **Corrected after Task 8.** The third bullet was not done, deliberately.
> Neither `vidBIOS.m` nor the emulator's assembly file is listed in the
> ThinkPad's `lksproj` Makefile, and neither should be added to `CLASSES` when
> drvVGA lands them: in the reference `vidBIOS.o` links **last**, after the
> generated `IBMThinkPad760EDDisplayDriver_instance.o`, and a `CLASSES` entry
> would place it immediately after `TransferTable.o` and break the `__text`
> order. See the ThinkPad `divergences.md`, "What has to happen before this
> driver links into something loadable".

The consequence for verification is stated in §4.3.

### 1.5 Config tables and localized resources are in scope

Apple's `.table`, `.modes` and `English.lproj` files are checked-in source, not
build output, and are restored verbatim as commit `5c654c53` did for
drvPCFloppy. `"Driver Version"` is emitted by Apple's build and stays out of
any comparison.

## 2. Evidence

### 2.1 Neither driver's source has any relationship to its reference

**Cirrus.** The reference implements
`CirrusLogicGD5434DisplayDriver : IOFrameBufferDisplay` with a `(ProgramDAC)`
category. Our `CirrusLogicGD5434.lksproj` implements
`CirrusLogicGD5434DisplayDriver : IOPCIDirectDevice` with 30 invented methods —
`writeCRTC:value:`, `drawPixel:y:color:`, `fillRect:y:width:height:color:`,
`copyRect:srcY:destX:destY:width:height:` — of which not one appears in the
reference. The reference's `determineConfiguration`, `setPCIConfiguration`,
`setPendingDisplayMode:`, `setMode:`, `displayModeCount`, `displayModes`,
`displayMemorySize`, `ramdacSpeed` and the whole `ProgramDAC` category are
absent from ours. 604 lines of source, zero shared symbols.

**ThinkPad.** The reference implements
`IBMThinkPad760EDDisplayDriver : IOFrameBufferDisplay` with a
`(TransferTable)` category. Ours declares the same superclass but 17 invented
methods — `mapMemoryRanges`, `initHardware`, `resetHardware`,
`setDisplayMode:height:depth:`, `getBrightness:` — of which none appears in the
reference. 366 lines, zero shared symbols.

Both source maps will therefore place every reference function in `unmapped`
under the "no counterpart in our source" reason class, exactly as `VGA_reloc`'s
did.

> **Corrected after Tasks 3 and 7.** Not so. Both invented classes carry the
> *same class name* as Apple's, and `binrecon source-map` pairs on
> `-[class selector]` alone, so it reported five nominal collisions on the
> Cirrus baseline (0, 712, 804, 3296, 3544) and four on the ThinkPad (56, 1184,
> 1812, 4344). Every one was a name match over a completely different body.
> Both `divergences.md` files tabulate them. The claim about *shared behaviour*
> stands; the claim about the bucket counts does not.

### 2.2 The reference's source-file partition is recorded in the binaries

`__OBJC,__module_info` names each translation unit, and each module's symbol
table gives the classes and categories it defines:

**Cirrus** — 3 modules:

| Module | Defines |
| --- | --- |
| `CirrusLogicGD5434DisplayDriver.m` | class `CirrusLogicGD5434DisplayDriver : IOFrameBufferDisplay` |
| `ProgramDAC.m` | category `CirrusLogicGD5434DisplayDriver(ProgramDAC)` |
| `CirrusLogicGD5434DisplayDriver_instance.m` | classes `…Version : IODevice`, `…KernelServerInstance : Object` |

**ThinkPad** — 4 modules:

| Module | Defines |
| --- | --- |
| `IBMThinkPad760ED.m` | class `IBMThinkPad760EDDisplayDriver : IOFrameBufferDisplay` |
| `TransferTable.m` | category `IBMThinkPad760EDDisplayDriver(TransferTable)` |
| `IBMThinkPad760EDDisplayDriver_instance.m` | classes `…Version : IODevice`, `…KernelServerInstance : Object` |
| `vidBIOS.m` | class `vidBIOS : Object` |

The `_instance.m` modules are build-generated, as established in the VGA
spec's §2.8. Two hand-written `.m` files for Cirrus, two for the ThinkPad
within this effort's scope, plus one assembly file for the ThinkPad (§2.6).

Assembly files contribute no `__OBJC,__module_info` entry, which is why
`_smapi_asm` and `_emu486` appear in neither list.

### 2.3 Both projects are misconfigured

`drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434.lksproj`
sets `NAME = CirrusLogicGD5434`, which links `CirrusLogicGD5434_reloc`. Apple's
binary, the `.config` directory, `Default.table`'s `"Driver Name"` and
`"Server Name"` keys all say `CirrusLogicGD5434DisplayDriver`. The subproject
directory and its `NAME` both have to change.

The ThinkPad's `NAME` is already correct.

Neither `lksproj` Makefile lists any source file; both have only
`OTHERSRCS`. The `.m` files are present in the directory but not in the build.

### 2.4 Both bundles are missing most of Apple's resources

**Cirrus.** Apple ships six `.table` files and six `.modes` files — one pair
each for `Default`, `TwoMeg`, `PCIOneMB`, `PCITwoMB`, `GD5446_PCIOneMB` and
`GD5446_PCITwoMB`, with `Display.modes` completing the `.modes` set in place of
a `Default.modes` — six `.strings` files, and two help bundles
`CL_GD5434.rtfd` and `CL_GD5446.rtfd` under `English.lproj/Help` alongside a
`TableOfContents.rtf`. We ship one `Default.table` and one
`Localizable.strings`.

Our `Default.table` is also a hand-made approximation with wrong syntax. Apple:

```
"Memory Maps" = "0x04000000-0x04ffffff 0xa0000-0xbffff 0xc0000-0xcffff";
"VGA Memory Maps" = "0xa0000-0xbffff 0xc0000-0xcffff";
"I/O Ports" = "0x3b0-0x3df 0x102-0x102 0x46e8-0x46e8";
"Display Mode" = "Height:600 Width:800 Refresh:60Hz ColorSpace:RGB:256/8";
"Help File" = "CL_GD5434.rtfd";
```

Ours has a different memory-map base, a nonexistent `"VGA Vendor"` key in place
of `"VGA Memory Maps"`, narrower I/O port ranges, underscores where Apple uses
colons in the `"Display Mode"` value, and a `"Help File"` naming an `.rtf` that
does not exist.

**ThinkPad.** Apple ships `Default.table`, `ThinkPad760.{table,modes}`,
`Display.modes`, `Localizable.strings`, `ThinkPad760.strings`, and two help
bundles `ThinkPad560.rtfd` and `ThinkPad760.rtfd`. We ship `Default.table` and
`Localizable.strings`.

### 2.5 What each driver actually is

**Cirrus** drives CL-GD5430/5434/5436/5446 parts over PCI. Its `__cstring`
section names all four and reports `"%s: %s detected (%d Bytes)"`;
`"%s: Cirrus Logic CL-GD543X or CL-GD5446 not found"` is the probe failure.
`__TEXT,__const` holds 24 named mode records — `_GD5434_mode_640_8_60`
through `_GD5434_mode_1280_8_70` and a parallel `_GD5446_` set —
`_GD5434_defaultMode`, `_GD5446_defaultMode`, a `_modeTableCount` for each,
`_gamma8`, `_gamma16` and `_vgaMode`. `__DATA,__data` holds the two runtime
mode tables `_GD5434_modeTable` and `_GD5446_modeTable`, selected by
`determineConfiguration` according to detected chip and memory size.

**ThinkPad** does not drive an IBM part. `Default.table` sets
`"Auto Detect IDs" = "0x96601023"` — Trident Microsystems TGUI9660 — and its
strings say `"Trident Cyber938x not detected - trying anyway"`,
`"Chip ID=0x%02x, Revision=0x%02x"` and `"TVGA BIOS SetMode failure (%04x)"`,
with a `"Vesa BIOS SetMode failure (%04x)"` fallback. `Default.table`'s
`"Title"` is `"IBM ThinkPad 560"` while `ThinkPad760.table`'s is
`"IBM ThinkPad 760E/760ED"`, so one binary serves both machines through
different config tables.

Panel and system access goes through IBM's SMAPI BIOS: the strings report
`"SMAPI revision %01x.%02x"`, `"System management BIOS revision %01x.%02x"`,
`"Slave controller revision %01x.%02x"`, CPU vendor/family/model/stepping and
internal and external clock, and classify the panel as
`"Monochrome STN"`, `"Monochrome TFT"`, `"Color STN"` or `"Color TFT"`.
`"%s: Unable to call SMAPI at port 0x%04x"` is the failure path, and
`"%s: Unable to set refresh rate using SMAPI"` shows refresh control runs
through it too. `__DATA,__data` holds a single `_ThinkPad760EDModeTable`.

### 2.6 `_smapi_asm` is the only assembly file in scope

`_smapi_asm` occupies 6440–6528, 88 bytes. Three observations make it a
separate hand-written assembly translation unit rather than part of
`IBMThinkPad760ED.m`:

- it sits *after* `TransferTable.m`'s range (5708–6440) in link order, so it
  cannot belong to the module that ends at 5708;
- it contributes no `__OBJC,__module_info` entry, which every `.m` in the
  binary does;
- its symbol binding is `external`, as `_emu486`'s is, where every
  compiler-emitted C helper in both drivers — `_SetGammaValue`, `_set555Mode` —
  is `local`.

Its role, issuing the SMAPI trap with a register block, fits. The analysis pass
in §4.1 confirms this against the disassembly before the rewrite commits to a
`.s` file.

### 2.7 Both binaries contain gcc static-local symbols

`__DATA,__bss` holds `_xxx.NN` symbols, gcc's naming for function-scope
statics: `_xxx.86`, `_xxx.89`, `_xxx.92` in the Cirrus driver (24 bytes), and
those three plus `_xxx.8`, `_xxx.11`, `_xxx.14` in the ThinkPad (36 bytes).
Attributing each to its owning function is part of the decompilation pass,
not an assumption to carry into it. `__DATA,__common` in each holds the
4-byte `_<Name>_instance` pointer from the generated `_instance.m`.

### 2.8 Function partitions

**Cirrus**, in address order. `CirrusLogicGD5434DisplayDriver.m` runs 0–3588,
`ProgramDAC.m` 3588–4364, `CirrusLogicGD5434DisplayDriver_instance.m`
4364–4388.

| Address | Size | Symbol |
| --- | --- | --- |
| 0 | 556 | `-[CirrusLogicGD5434DisplayDriver initFromDeviceDescription:]` |
| 556 | 156 | `-[CirrusLogicGD5434DisplayDriver selectMode]` |
| 712 | 92 | `-[CirrusLogicGD5434DisplayDriver enterLinearMode]` |
| 804 | 88 | `-[CirrusLogicGD5434DisplayDriver revertToVGAMode]` |
| 892 | 768 | `-[CirrusLogicGD5434DisplayDriver determineConfiguration]` |
| 1660 | 32 | `-[CirrusLogicGD5434DisplayDriver isValidPCIAssignedBaseAddress:]` |
| 1692 | 584 | `-[CirrusLogicGD5434DisplayDriver setPCIConfiguration]` |
| 2276 | 1020 | `-[CirrusLogicGD5434DisplayDriver setMode:]` |
| 3296 | 32 | `-[CirrusLogicGD5434DisplayDriver clearScreen]` |
| 3328 | 60 | `-[CirrusLogicGD5434DisplayDriver name]` |
| 3388 | 140 | `-[CirrusLogicGD5434DisplayDriver setPendingDisplayMode:]` |
| 3528 | 16 | `-[CirrusLogicGD5434DisplayDriver displayModeCount]` |
| 3544 | 16 | `-[CirrusLogicGD5434DisplayDriver displayModes]` |
| 3560 | 16 | `-[CirrusLogicGD5434DisplayDriver displayMemorySize]` |
| 3576 | 12 | `-[CirrusLogicGD5434DisplayDriver ramdacSpeed]` |
| 3588 | 336 | `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setTransferTable:count:]` |
| 3924 | 80 | `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setBrightness:token:]` |
| 4004 | 84 | `_SetGammaValue` |
| 4088 | 276 | `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setGammaTable]` |
| 4364 | 12 | `+[CirrusLogicGD5434DisplayDriverKernelServerInstance kernelServerInstance]` |
| 4376 | 12 | `+[CirrusLogicGD5434DisplayDriverVersion driverKitVersionForCirrusLogicGD5434DisplayDriver]` |

**ThinkPad**, in address order, to the end of this effort's scope.
`IBMThinkPad760ED.m` runs 0–5708, `TransferTable.m` 5708–6440, the assembly
file 6440–6528, and `IBMThinkPad760EDDisplayDriver_instance.m` 6528–6552.
Everything from 6552 is deferred per §1.4.

| Address | Size | Symbol |
| --- | --- | --- |
| 0 | 56 | `_set555Mode` |
| 56 | 780 | `-[IBMThinkPad760EDDisplayDriver initFromDeviceDescription:]` |
| 836 | 128 | `-[IBMThinkPad760EDDisplayDriver updateModeTable]` |
| 964 | 116 | `-[IBMThinkPad760EDDisplayDriver selectMode]` |
| 1080 | 104 | `-[IBMThinkPad760EDDisplayDriver defaultMode]` |
| 1184 | 628 | `-[IBMThinkPad760EDDisplayDriver enterLinearMode]` |
| 1812 | 216 | `-[IBMThinkPad760EDDisplayDriver revertToVGAMode]` |
| 2028 | 168 | `-[IBMThinkPad760EDDisplayDriver getModeInfo:]` |
| 2196 | 396 | `-[IBMThinkPad760EDDisplayDriver determineConfiguration:]` |
| 2592 | 32 | `-[IBMThinkPad760EDDisplayDriver isValidPCIAssignedBaseAddress:]` |
| 2624 | 676 | `-[IBMThinkPad760EDDisplayDriver setPCIConfiguration]` |
| 3300 | 544 | `-[IBMThinkPad760EDDisplayDriver setPendingDisplayMode:]` |
| 3844 | 84 | `-[IBMThinkPad760EDDisplayDriver getDisplayDeviceState]` |
| 3928 | 80 | `-[IBMThinkPad760EDDisplayDriver setDisplayDeviceState:]` |
| 4008 | 168 | `-[IBMThinkPad760EDDisplayDriver unlockRegisters]` |
| 4176 | 168 | `-[IBMThinkPad760EDDisplayDriver lockRegisters]` |
| 4344 | 92 | `-[IBMThinkPad760EDDisplayDriver free]` |
| 4436 | 12 | `-[IBMThinkPad760EDDisplayDriver displayModeCount]` |
| 4448 | 12 | `-[IBMThinkPad760EDDisplayDriver displayModes]` |
| 4460 | 16 | `-[IBMThinkPad760EDDisplayDriver displayMemorySize]` |
| 4476 | 12 | `-[IBMThinkPad760EDDisplayDriver ramdacSpeed]` |
| 4488 | 72 | `-[IBMThinkPad760EDDisplayDriver readCMOS:]` |
| 4560 | 1088 | `-[IBMThinkPad760EDDisplayDriver reportSystemConfiguration]` |
| 5648 | 60 | `-[IBMThinkPad760EDDisplayDriver name]` |
| 5708 | 336 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) setTransferTable:count:]` |
| 6044 | 80 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) setBrightness:token:]` |
| 6124 | 84 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) SetGammaValueRed:Green:Blue:Level:]` |
| 6208 | 232 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) setGammaTable]` |
| 6440 | 88 | `_smapi_asm` |
| 6528 | 12 | `+[IBMThinkPad760EDDisplayDriverKernelServerInstance kernelServerInstance]` |
| 6540 | 12 | `+[IBMThinkPad760EDDisplayDriverVersion driverKitVersionForIBMThinkPad760EDDisplayDriver]` |

The two drivers share a shape: both subclass `IOFrameBufferDisplay`, both carry
`isValidPCIAssignedBaseAddress:` (32 bytes in each), `setPCIConfiguration`,
`setPendingDisplayMode:`, the same four mode accessors, `name`, and a
transfer-table category whose `setTransferTable:count:` is 336 bytes and
`setBrightness:token:` 80 bytes in both. Where the decompilations agree, the
divergence documents say so; where they differ, each says how.

## 3. Artifacts

### 3.1 binrecon profiles

Two reference-only profiles, copied from `profiles/vga-reloc.json` with the
name and `output_dir` changed:

| Profile | `output_dir` |
| --- | --- |
| `tools/binrecon/profiles/cirruslogic-gd5434.json` | `../out/cirruslogic-gd5434` |
| `tools/binrecon/profiles/thinkpad760ed.json` | `../out/thinkpad760ed` |

Architecture `i386`, little-endian, acceptance `normalized-functions`. All
three analyzers start enabled. Disabling one is permitted only with the reason
recorded in that driver's `divergences.md`, as `vga-reloc.json` does for angr.

### 3.2 Reconstruction directories

```
src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/
    divergences.md
    CirrusLogicGD5434DisplayDriver_reloc/
        source-map.json
        ledger.json

src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/
    divergences.md
    IBMThinkPad760EDDisplayDriver_reloc/
        source-map.json
        ledger.json
```

Each `source-map.json` partitions the whole `__text` range: every reference
function lands in `mapped`, `unmapped`, `boundary_disputed` or
`duplicate_candidates`. Each `ledger.json` carries one `ledger-v1` entry per
function recording analyzer agreement and reason class.

### 3.3 Source tree

**Cirrus.** Rename `CirrusLogicGD5434.lksproj` to
`CirrusLogicGD5434DisplayDriver.lksproj`, set `NAME` to match, and update
`TOOLS` in the `.drvproj` Makefile. Replace the invented
`CirrusLogicGD5434DisplayDriver.{h,m}` with:

```
CirrusLogicGD5434DisplayDriver.h
CirrusLogicGD5434DisplayDriver.m     module 1, __text 0–3588
ProgramDAC.m                         module 2, __text 3588–4364
```

**ThinkPad.** Replace the invented `IBMThinkPad760EDDisplayDriver.{h,m}` with:

```
IBMThinkPad760ED.h
IBMThinkPad760ED.m                   module 1, __text 0–5708
TransferTable.m                      module 2, __text 5708–6440
smapi.s                              __text 6440–6528
```

`vidBIOS.m` and the emulator's assembly file are listed in the `lksproj`
Makefile but not written here (§1.4). Header names are ours to choose —
Apple's `__OBJC` metadata records `.m` files only — and follow the convention
of naming the header after the class's implementation file.

Both `lksproj` Makefiles gain `MFILES`, `CFILES` and `SFILES` entries; today
they list no sources at all.

> **Corrected after Task 8 — this line was a Critical defect. Do not act on
> it.** **`SFILES` is not a pb_makefiles variable at all.** Nothing in
> `src/pb_makefiles-1` or `src/driverTools-1` defines or consumes it, so
> assembly listed under `SFILES` is silently never assembled and never linked.
> The working pair, as `src/awk-1/Makefile:17,24` uses it and as the stock
> `Makefile.postamble` template documents it, is `OTHERLINKED = smapi.s` with
> `OTHERLINKEDOFILES = smapi.o`; `common.make:242` folds `OTHERLINKEDOFILES`
> into `LOCAL_OFILES` and `common.make:240` folds `OTHERLINKED` into
> `SRCFILES`. `MFILES` and `CFILES` are real variables but
> neither Makefile uses them: both list their Objective-C sources in `CLASSES`
> (`CLASSES = CirrusLogicGD5434DisplayDriver.m ProgramDAC.m` and
> `CLASSES = IBMThinkPad760ED.m TransferTable.m`), whose ordering within
> `LOCAL_OFILES` is what reproduces the reference's `__text` layout.

### 3.4 Resources

Copy Apple's `.table`, `.modes` and `English.lproj` contents verbatim into each
`.drvproj`, and extend `GLOBAL_RESOURCES` and `LOCAL_RESOURCES` to match. This
replaces our approximated `Default.table` in both projects.

### 3.5 Build script

`vm/build-i386-video-recon.sh`, modelled on `vm/build-i386-vga.sh`: strip CRs
from the makefiles, run `gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386` in each
`.drvproj`, and report per-driver results.

### 3.6 README

`src/drivers-i386/README` gains a status for both drivers.

## 4. Phases

Two independent tracks, A (Cirrus) and B (ThinkPad). Neither blocks the other.
Within each track the steps are ordered.

### 4.1 Analysis

1. Write the profile. Verify with `binrecon validate`.
   → verify: both artifact paths resolve and the printed SHA-256 matches §1.1.
2. `binrecon analyze --profile … --ledger …/ledger.json`.
   → verify: exit 0, or a recorded analyzer disablement with the reason written
   into `divergences.md` and a rerun at exit 0.
3. `binrecon source-map` against the current (invented) sources.
   → verify: the map partitions the full `__text` range and every reference
   function is in `unmapped`.

   > **Corrected after Tasks 3 and 7.** The second half of this criterion is
   > unmeetable and was dropped — see the correction to §2.1. Because the
   > invented classes share Apple's class names, the baseline maps read
   > `mapped 5` / `unmapped 16` (Cirrus) and `mapped 4` / `unmapped 36`
   > (ThinkPad), all nominal selector-name collisions. The criterion that
   > actually held is the first half: the map partitions the full `__text`
   > range with no unclaimed region.
4. Decompile every function in the track's scope and write
   `divergences.md`: behaviour, hardware registers and DriverKit calls touched,
   call-graph position, and every inference marked as an inference.
   → verify: the document has one finding per function in §2.8, and the
   `_xxx.NN` statics of §2.7 are each attributed to a function.

### 4.2 Rewrite

5. Fix the project configuration and resources (§3.3, §3.4).
   → verify: `NAME` and `TOOLS` name `CirrusLogicGD5434DisplayDriver`; each
   `.drvproj` contains every `.table`, `.modes` and `English.lproj` file the
   reference bundle has, byte-identical apart from `"Driver Version"`.
6. Write the sources, smallest translation unit first — `ProgramDAC.m` before
   `CirrusLogicGD5434DisplayDriver.m`, `TransferTable.m` and `smapi.s` before
   `IBMThinkPad760ED.m`. Match Apple's symbol names exactly: method names,
   file-static C helpers `_SetGammaValue` and `_set555Mode`, and the `__const`
   and `__data` table symbols named in §2.5.
   → verify: regenerated `source-map.json` moves every in-scope function from
   `unmapped` to `mapped`; the ledger advances each entry.

### 4.3 Build and parity

7. Add `vm/build-i386-video-recon.sh` and run both tracks on the Rhapsody
   guest.
   → verify, track A: `CirrusLogicGD5434DisplayDriver_reloc` and
   `CirrusLogicGD5434DisplayDriver` both exist.
   → verify, track B: `IBMThinkPad760ED.o`, `TransferTable.o` and `smapi.o`
   all compile.

   > **Corrected after Task 5 — track A's criterion is UNMET and OPEN.** The
   > `_reloc` exists; the `CirrusLogicGD5434DisplayDriver` version bundle does
   > **not**. `vm/build-i386-video-recon.sh` prints `WARNING: no
   > CirrusLogicGD5434DisplayDriver version bundle produced`, and nothing was
   > staged. The same gap recurs on track B — its `kl_ld` object list contains
   > no `_vers.o`. Half of this criterion therefore fails, and the branch merges
   > with it failing rather than met: the missing `_..._VERS_STRING` /
   > `_..._VERS_NUM` pair is unreferenced by any function in either binary, so
   > the runtime impact is nil, but the build-configuration cause is not
   > diagnosed. See §1.2, `src/drivers-i386/README`, and the "Build and parity"
   > and "Build status" sections of the two `divergences.md` files.

   > **Corrected after Task 10.** This step originally predicted the link
   > would **fail** with unresolved `.objc_class_name_vidBIOS` and `_emu486`
   > until drvVGA supplies them, and that no ThinkPad `_reloc` would be
   > produced. All of that was wrong. `kl_ld` performs a *relocatable* link
   > (`ld -r`), which leaves unresolved symbols undefined rather than erroring
   > — so `IBMThinkPad760EDDisplayDriver_reloc` **is produced** with
   > `make exit=0`. `.objc_class_name_vidBIOS` is indeed among the undefined
   > symbols, but `_emu486` is not: it is referenced only from the deferred
   > `vidBIOS.m`, so it never appears as an unresolved symbol of this build at
   > all. See `divergences.md`'s "Build status" section for the full account.
8. Run `tools/binrecon/parity_check.py` against the reference `_reloc` for
   track A.
   → verify: every reference `__TEXT,__cstring` string and every reference
   `__TEXT,__text` symbol is present in our build. Extras on our side are
   reported, not failures — our guest builds are unstripped.

> **Corrected after Task 10.** Track B was expected to have no
> `parity_check.py` step because it would produce no linked binary. It does
> produce one — see the correction to step 7 above — so `parity_check.py`
> runs against it too, and reports one missing symbol (`_emu486`) and eight
> missing strings (the deferred `vidBIOS.m` strings), with nothing extra
> beyond unstripped-build artifacts.

### 4.4 Out of scope for verification

No boot test and no QEMU run. QEMU models neither a CL-GD5434 nor a TGUI9660,
so a boot would exercise nothing but the probe failure path. No binrecon
`compare` of a rebuilt artifact against the reference: acceptance is the
source map, the ledger, and `parity_check.py`.

## 5. Risks

**The ThinkPad track ends without a *loadable* binary.** This is by design
(§1.4): `vidBIOS.m` and `_emu486` remain deferred to drvVGA, so the rebuilt
`_reloc` has no `vidBIOS` class and cannot load.

> **Corrected after Task 10.** This paragraph originally said the ThinkPad
> track produces no linked binary at all, so its 29 reconstructed functions
> would be verified by compilation and source map only, with a symbol- and
> string-level parity check unavailable until drvVGA lands. That was wrong on
> both counts: `kl_ld`'s relocatable link **does** produce a `_reloc`, and
> `parity_check.py` **does** run against it now, reporting only `_emu486`
> missing among symbols and the eight deferred `vidBIOS.m` strings missing.
> What that check cannot yet do is confirm byte-level parity — 12 of the 29
> in-scope function extents still differ from the reference — and it cannot
> exercise the deferred region at all. Full parity, including `vidBIOS.m` and
> `_emu486`, is still gated on drvVGA landing them.

**`reportSystemConfiguration` is 1088 bytes**, the largest single function in
either driver, and consists largely of SMAPI calls and `IOLog` formatting whose
exact call sequence has to be read from the disassembly rather than inferred
from the format strings.

**`setMode:` is 1020 bytes** in the Cirrus driver and programs the CRTC,
sequencer, graphics and attribute register files plus Cirrus extensions. Its
register-write order matters and cannot be reordered for readability.

**Analyzer disagreement, ThinkPad.** `VGA_reloc` needed angr disabled and IDA
forced to `-pmetapc`, the latter because its `cpu_subtype = 4` makes IDA's
loader auto-select the legacy `80486p` processor module.
`IBMThinkPad760EDDisplayDriver_reloc` has the same `cpu_subtype = 4` and the
same `_emu486`, so expect both problems to recur: the `-pmetapc` force
(already committed as `8d8cfd20`) applies, and angr is likely to need the same
disablement for the same reason. §4.1 step 2 covers this, and the reason must
be recorded rather than assumed from this paragraph.

`CirrusLogicGD5434DisplayDriver_reloc` has `cpu_subtype = 3` and no emulator,
so all three analyzers are expected to run cleanly on it.
