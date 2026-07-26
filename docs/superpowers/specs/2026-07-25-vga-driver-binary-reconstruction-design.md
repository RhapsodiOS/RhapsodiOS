# Binary reconstruction of the VGA display driver

Reconstruct `VGA_reloc` and `VGA_psdrvr` against Apple's shipped i386 driver
binaries, using the `tools/binrecon` toolchain. Both of our sources are
inventions rather than reconstructions, so this is a rewrite effort: a report
pass that maps and decompiles every reference function, followed by a rewrite
pass per binary.

This continues
[2026-07-25-bus-driver-binary-reconstruction-design.md](2026-07-25-bus-driver-binary-reconstruction-design.md),
[2026-07-25-intel-bus-driver-binary-reconstruction-design.md](2026-07-25-intel-bus-driver-binary-reconstruction-design.md)
and
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md).
The reference-only profiles, the `binrecon source-map` subcommand, the
`load_source_map` semantic loader, the `reconstruction/` artifact layout, the
`ledger-v1` vocabulary, `tools/binrecon/parity_check.py`, and the
`vm/build-i386-*.sh` harness model are reused unchanged.

## Motivation

`src/drivers-i386/README` lists `vga` with no status at all — alone among the
eleven drivers in `video/`. Scoping read the reference symbol tables, `__cstring`
sections, config tables and localized resources before any analyzer run, and
found that neither of our two binaries shares a single string, symbol or class
name with the binary it is supposed to reproduce (§2.1, §2.2). The project also
cannot build a conforming `_reloc`, and has never built the PostScript driver at
all (§2.6).

Unlike the input-driver effort, this is not a parity-and-divergence exercise.
There is nothing to diff. Every hand-written function is written from the
reference disassembly.

## 1. Scope

### 1.1 Targets

Two binaries under `C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config`:

| Binary | Mach-O type | File size | `__text` | Functions | Hand-written |
| --- | --- | --- | --- | --- | --- |
| `VGA_reloc` | MH_PRELOAD | 71112 | 18048 | 36 | 34 |
| `VGA_psdrvr` | MH_BUNDLE | 26584 | 7057 | 22 | 19 |

53 hand-written functions over 52 distinct bodies — `_Start` is a zero-size alias
of `_VGAStart` in the psdrvr.

> **Corrected after the Task 7 analyzer run.** This table first said `VGA_reloc`
> held 30 functions. That count came from walking the `__TEXT,__text` symbol
> table and deriving each function's size from the gap to the next symbol, which
> is wrong wherever a function carries no symbol. Six `-[vidBIOS …]` methods do
> not appear in the symbol table at all and were hiding inside the 1168-byte gap
> the old table attributed to `+[VGAVersion driverKitVersionForVGA]`, whose real
> size is 12 bytes. IDA recovers them from `__OBJC,__inst_meth`. The sizes below
> are IDA's, not gap-derived.

`VGA_reloc`, in address order. Method names are as the symbol table gives them
where it names the function, and as IDA recovers them from the ObjC metadata for
the six `vidBIOS` methods it does not:

| Address | Size | Symbol |
| --- | --- | --- |
| 0 | 227 | `-[IOVGADisplay _registerWithED]` |
| 228 | 237 | `_SetET4000Brightness` |
| 468 | 103 | `_select_read_segment` |
| 572 | 102 | `_select_write_segment` |
| 676 | 110 | `_select_read_plane` |
| 788 | 127 | `_select_write_plane` |
| 916 | 407 | `_vga_read_bpp4planar_to_bpp2packed32` |
| 1324 | 428 | `_vga_write_bpp2packed32_to_bpp4planar` |
| 1752 | 816 | `_VGADisplayCursor` |
| 2568 | 660 | `_VGARemoveCursor` |
| 3228 | 100 | `-[IOVGADisplay hideCursor:]` |
| 3328 | 517 | `-[IOVGADisplay moveCursor:frame:token:]` |
| 3848 | 453 | `-[IOVGADisplay showCursor:frame:token:]` |
| 4304 | 47 | `-[IOVGADisplay generateNameAndUnit:]` |
| 4352 | 9 | `-[IOVGADisplay map]` |
| 4364 | 84 | `-[IOVGADisplay unmap]` |
| 4448 | 144 | `+[IOVGADisplay probe:]` |
| 4592 | 41 | `-[IOVGADisplay free]` |
| 4636 | 358 | `-[IOVGADisplay initFromDeviceDescription:]` |
| 4996 | 64 | `-[IOVGADisplay setBrightness:token:]` |
| 5060 | 437 | `-[IOVGADisplay getIntValues:forParameter:count:]` |
| 5500 | 295 | `-[IOVGADisplay setIntValues:forParameter:count:]` |
| 5796 | 29 | `-[IOVGADisplay allocateConsoleInfo]` |
| 5828 | 114 | `-[IOVGADisplay(VESAMode) enterSVGAMode:]` |
| 5944 | 166 | `-[IOVGADisplay(VESAMode) int10:]` |
| 6112 | 106 | `_find_parameter` |
| 6220 | 149 | `-[IOVGADisplay(VESAMode) didBootWithDefaultConfig]` |
| 6372 | 12 | `+[VGAKernelServerInstance kernelServerInstance]` |
| 6384 | 12 | `+[VGAVersion driverKitVersionForVGA]` |
| 6396 | 267 | `-[vidBIOS init]` |
| 6664 | 107 | `-[vidBIOS free]` |
| 6772 | 696 | `-[vidBIOS int10:outregs:iorange:ionum:smmport:]` |
| 7468 | 44 | `-[vidBIOS int10:outregs:iorange:ionum:]` |
| 7512 | 16 | `-[vidBIOS scratchSegment]` |
| 7528 | 22 | `-[vidBIOS realToVirtual::]` |
| 7552 | 8088 | `_emu486` |

IDA additionally carves 69 unnamed fragments totalling 1279 bytes out of the
range 7912 to 15758, which lies inside `_emu486`. They are its per-opcode
handlers, not functions, and they are excluded from the function partition
(§4.3). Thirty-four of the 69 return to a shared dispatch point at `0x1E20`; the
rest jump elsewhere, so the handler table is not uniform and its control flow has
to be read rather than assumed.
A further 2290 bytes from 15758 to the end of `__text` at 18048 are claimed by no
function at all and are presumably the emulator's dispatch tables.

`VGA_psdrvr`, in address order. Offsets are relative to the `__TEXT` segment
base, which the bundle prebinds at `0x70320000`; the `__text` section itself
begins at offset 7988, so the first three entries are the bundle header and glue
that precede it and their sizes are gap-derived rather than real function
extents:

| Offset | Size | Symbol |
| --- | --- | --- |
| 0 | 7988 | `__mh_bundle_header` (bundle glue) |
| 7988 | 20 | `dyld_stub_binding_helper` (bundle glue) |
| 8008 | 1344 | `__dyld_func_lookup` (bundle glue) |
| 9352 | 0 | `_Start` (alias of `_VGAStart`) |
| 9352 | 640 | `_VGAStart` |
| 9992 | 32 | `_VGASysHideCursor` |
| 10024 | 108 | `_VGASysShowCursor` |
| 10132 | 180 | `_VGACheckShield` |
| 10312 | 556 | `_VGASetCursor` |
| 10868 | 44 | `_VGAHideCursor` |
| 10912 | 44 | `_VGAShowCursor` |
| 10956 | 68 | `_VGAObscureCursor` |
| 11024 | 64 | `_VGARevealCursor` |
| 11088 | 80 | `_VGAShieldCursor` |
| 11168 | 1164 | `_VGAUnshieldCursor` |
| 12332 | 372 | `_set_colormap` |
| 12704 | 120 | `_get_addr_range` |
| 12824 | 120 | `_fill_64K_plane` |
| 12944 | 932 | `_vga_at_mode12_bpp2_to_bpp4` |
| 13876 | 404 | `_read_bpp4planar_to_bpp2packed` |
| 14280 | 364 | `_write_bpp2packed_to_bpp4planar` |
| 14644 | 401 | `_VGASetStdRegs` |

The offsets above are derived from the bundle's prebound `__TEXT` addresses,
which start at `0x70320000`. The source map records absolute addresses.

> **The sizes in this table are gap-derived and several are wrong**, in the same
> way §1.1's `VGA_reloc` table was before Task 7 corrected it. Sixteen `static`
> functions carry no symbol, so each one inflates the size attributed to whatever
> named symbol precedes it. `_VGAUnshieldCursor` is the worst case: 1164 bytes
> here against IDA's 73, having absorbed both cursor blitters. IDA also reports
> 17 PIC symbol stubs in `__TEXT,__picsymbol_stub` that no symbol names. The
> authoritative inventory is the committed source map, which after Task 9's
> correction holds 53 entries: 19 hand-written symbols over 18 bodies, 2 dyld
> glue routines, 17 PIC stubs and 16 unnamed statics. This table is left as it
> stood because it is what the symbol table alone shows, and the gap between the
> two is itself the point.

### 1.2 The `VGA` version bundle is out of scope

`VGA.config/VGA` is a third Mach-O file, 16672 bytes, MH_BUNDLE. Its `__text` is
34 bytes of `dyld_stub_binding_helper` and `__dyld_func_lookup`; its only content
is `_VGA_VERS_STRING` and `_VGA_VERS_NUM` in `__TEXT,__const`. It is what the
Driver project type emits, and the restructured build of §3.1 is expected to
produce an equivalent without anyone writing code. If it does not, that is a
build finding recorded in `divergences.md`, not a reconstruction target.

### 1.3 Config tables and localized resources are in scope

`Default.table`, `SVGABIOS.table`, `English.lproj/Localizable.strings` and
`English.lproj/SVGABIOS.strings` are checked-in source, not build output, and
§2.5 shows that a wrong separator character in a single value silently disables
SVGA mode selection. They are compared against Apple's copies.

`"Driver Version"` is emitted by Apple's build and stays out of the comparison.

### 1.4 Out of scope

`src/driverkit-3` and `src/kernel-7` are untouched, including
`IOVGADisplay.h`, `IOVGADisplayPrivate.h` and `IOVGAShared.h`, and the
`_VGAAllocateConsole` in `kernel-7/bsd/dev/i386/VGAConsole.c` that `VGA_reloc`
links against. If the reconstruction turns out to require a `driverkit` header
change, that is flagged in `divergences.md` and committed separately rather than
folded into a rewrite commit.

The other ten drivers in `src/drivers-i386/video` are untouched. Apple's Help
text is not reproduced (§4.2). Retrofitting `Unload_Commands.sect` onto the
previously reconstructed bus and input drivers is not part of this effort.

## 2. Findings that shaped this design

All of these come from reading the reference Mach-O symbol tables, `__cstring`
sections, `Loaded Server` sections, config tables and localized resources during
scoping, before any analyzer run.

### 2.1 `VGA_reloc` is a different driver from ours

Apple's binary defines four Objective-C classes — `IOVGADisplay` subclassing
`IODisplay`, a category `IOVGADisplay(VESAMode)`, `vidBIOS`, and the
build-generated `VGAKernelServerInstance` and `VGAVersion` — plus nine C
functions: read/write segment and plane select, bpp4-planar to bpp2-packed
conversion in both directions, a software cursor in `_VGADisplayCursor` and
`_VGARemoveCursor`, `_SetET4000Brightness`, `_find_parameter`, and `_emu486`.

Our `VGA_reloc.tproj` defines one class, `VGA`, subclassing
`IOFrameBufferDisplay`, across `VGA.m`, `VGAConfigTable.m`, `VGASetMode.m` and
`VGAModes.c` — about 330 lines. Most of its methods log a line and return
`self`; `initializeMode`, `enableLinearFrameBuffer` and `resetVGA` contain
comments where the register programming would go.

No string, symbol or class name is common to the two. The reference logs
`VGADisplay: Mode Selected: 640 x 480 @ 60 Hz (BW:2)`; ours logs
`%s: Selected mode: %s`. This is the same fully-disjoint-string-set signature the
Intel and input-driver specs found, at the scale of an entire driver.

### 2.2 `VGA_psdrvr` is a different program from ours

Apple's is the Window Server-side framebuffer driver. `_VGAStart` registers the
screen; `_VGASetCursor`, `_VGAShieldCursor`/`_VGAUnshieldCursor`,
`_VGAObscureCursor`/`_VGARevealCursor` and the `_VGASys*` pair implement the
cursor; `_set_colormap` and `_VGASetStdRegs` program the hardware;
`_vga_at_mode12_bpp2_to_bpp4`, `_read_bpp4planar_to_bpp2packed` and
`_write_bpp2packed_to_bpp4planar` convert between the Window Server's packed
format and VGA's planes. It imports `_NXRegisterScreen`,
`_LookupFrameBufferDevicePort`, `__IOMapEISADeviceMemory`,
`__IOMapEISADevicePorts`, `__IOGetIntValues`, `__IOSetIntValues`,
`__IOLookupByDeviceName`, `_ev_lock`/`_ev_unlock`, and the `__bm12`, `__bm18`,
`__bm34`, `__bm38` cursor blitters. Its seven `__DATA,__common` globals are
`_vga_width`, `_vga_height`, `_vga_rowbytes`, `_vga_bpl`, `_vgaBounds`,
`_vgaAddress` and `_vgaVirtualAddress`.

Our `VGAPSDriver.c` is a 127-line printing API: `VGAPSInit`, `VGAPSCleanup`,
`VGAPSBeginPage`, `VGAPSEndPage`, `VGAPSRenderImage`, `VGAPSSetColorSpace`,
`VGAPSSetGamma`, `VGAPSGetDisplayInfo`. It has no connection to the Window
Server, imports nothing, and its `Makefile.postamble` installs a `VGA.ppd` file
that does not exist in this repository and has no counterpart in Apple's
`VGA.config`.

### 2.3 The original NeXT headers are already in the tree

`src/driverkit-3/driverkit/` carries three headers written for exactly this
driver, all credited to Gary Crum, 28 September 1992:

- `IOVGADisplay.h` — the `IOVGADisplay : IODisplay` interface, with `map`,
  `unmap` and `setBrightness:token:`, matching three of the reference's methods
  by name and signature.
- `IOVGADisplayPrivate.h` — the ET4000 geometry and palette constants, the
  `colr_mode` variable that appears in the reference as the external
  `_colr_mode`, and the `vga_reg_out`/`vga_reg__in`/`vga_acr_out`/`vga_acr__in`
  macros. `_SetET4000Brightness` in the reference is named for these constants.
- `IOVGAShared.h` — `VGAShmem_t`, the `bm12`/`bm18`/`bm34`/`bm38` cursor
  structures matching the psdrvr's blitter imports, and every `IO_Framebuffer_*`
  parameter name that appears in both binaries' `__cstring`.

The reference was compiled against these headers. They are the single largest
asset in this effort and they are already checked in.

### 2.4 `vidBIOS` is the BIOS-call class, and it has six methods

`.objc_class_name_vidBIOS` is an `N_ABS` defined symbol, alongside
`.objc_class_name_IOVGADisplay`, `.objc_class_name_VGAKernelServerInstance` and
`.objc_class_name_VGAVersion`. `.objc_class_name_IODisplay`,
`.objc_class_name_IODevice`, `.objc_class_name_Object` and
`.objc_class_name_EventDriver` are undefined and resolved by the kernel loader.

An earlier draft of this section said no `vidBIOS` method appears in
`__TEXT,__text` and left the class's purpose as an open question. That was an
artifact of reading only the symbol table, which names none of them. IDA recovers
six from `__OBJC,__inst_meth`, listed in §1.1: `init`, `free`, two `int10:`
overloads, `scratchSegment` and `realToVirtual::`.

Their names settle what the class is for. `vidBIOS` owns the real-mode BIOS call:
`realToVirtual::` and `scratchSegment` manage the low-memory window the emulator
needs, and `int10:outregs:iorange:ionum:smmport:` is the call itself, with a
five-argument form and a four-argument convenience wrapper. `_emu486` is the
engine underneath it. `-[IOVGADisplay(VESAMode) int10:]` at 5944 is the display
driver's entry into that machinery, and `VGADisplay: vidBIOS failed` in
`__cstring` is what it logs when the call does not come back clean.

What remains for the report pass is narrower than before: the exact argument
types and the register block layout the two `int10:` methods pass and receive.

### 2.5 The config tables and localized resources diverge

`Default.table`, two errors:

| Key | Ours | Reference |
| --- | --- | --- |
| `"I/O Ports"` | `… 0x3d4-0x3d6 …` | `… 0x3d4-0x3dc …` |
| `"Display Mode"` | `… ColorSpace: BW.2` | `… ColorSpace: BW:2` |

`SVGABIOS.table`, the same two errors plus two missing keys:

```
"SVGA Mode" = "Yes";
"SVGA VESA BIOS Mode" = "0x6a";
```

The reference's `__cstring` contains `SVGA Mode`, `Yes` and
`SVGA VESA BIOS Mode` as literals, so `-[IOVGADisplay(VESAMode) enterSVGAMode:]`
reads both keys by name. Without them our SVGA table cannot select an SVGA mode
regardless of the rest of the driver. This is the same class of
one-key load blocker as `Intel824X0`'s `"Auto Detect_IDs"` typo and
`PS2Mouse`'s `"SkipDetection"`.

`English.lproj/Localizable.strings` is invented. Apple's is two lines:

```
"VGA" = "Default VGA";
"Long Name" = "Default VGA Adapter";
```

Ours declares `"VGADisplayDriver"` and a long English sentence as its own key.
We ship no `SVGABIOS.strings`; Apple's is the SVGA counterpart:

```
"VGA" = "Generic SVGA";
"Long Name" = "Generic SVGA Adapter";
```

We ship a `Display.modes`; **Apple's `VGA.config` contains no `Display.modes` at
all**. Ours is listed in the top-level `Makefile`'s `GLOBAL_RESOURCES`.

`Default.table` names `"Help File" = "VGA.rtfd"`. Apple ships
`English.lproj/Help/VGA.rtfd` and `English.lproj/Help/TableOfContents.rtf`; we
ship neither, and an `English.lproj/Info.rtf` that Apple does not.

### 2.6 The project cannot build a conforming `_reloc`, or the psdrvr at all

`src/drivers-i386/video/vga` is the only driver in `video/` still using the flat
legacy layout. Three problems:

1. The top-level `Makefile` uses `bundle.make` and lists
   `SUBPROJECTS = VGA_reloc.tproj` only. `VGA_psdrvr` is never built. Its
   `OTHER_RESOURCES = VGA_psdrvr/VGA.ppd` names a file that does not exist.
2. `VGA_reloc.tproj/Makefile` uses `tool.make` with no `PROJECT_TYPE`. The
   Kernel Server project type is what runs `kl_ld` and emits the `Loaded Server`
   sections; on `tool.make` none of them are produced.
3. Every other driver in `video/` uses `X.drvproj` on `driver.make` wrapping
   `X.lksproj` on `kernelserver.make`, with `MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles`.
   `vga` uses `/NextDeveloper/Makefiles/app` throughout.

### 2.7 `Load_Commands.sect` is one byte short, and there is no `Unload_Commands.sect`

The reference's five `Loaded Server` sections are:

| Section | Size | Content |
| --- | --- | --- |
| Server Name | 3 | `VGA` |
| Load Commands | 164 | the `WIRE` block below |
| Unload Commands | 67 | the termination block below |
| Instance Var | 12 | `VGA_instance` |
| Server Version | 1 | `2` |

Our `VGA_reloc.tproj/Load_Commands.sect` is 163 bytes and differs from Apple's
164 in exactly one byte: Apple's first line is `# ` with a trailing space, ours is
`#`. Everything after it is identical.

Apple's `Unload Commands`, which nothing in this repository produces:

```
# Termination

#CALL		stub_terminate		0
#CALL		stub_terminate		1


```

`Server Version` is `2` where our project declares `PROJECTVERSION = 1.0`. What
emits that section, and from which variable, is a Phase 0 build question.

### 2.8 binrecon rejects MH_BUNDLE

`binrecon/macho.py:131` accepts only `MH_OBJECT` and `MH_PRELOAD`, so
`read_macho` raises `MachOFormatError: unsupported Mach-O file type 8` on
`VGA_psdrvr`. That blocks `validate`, `analyze`, `source-map` and
`parity_check.py` for half of this effort.

Nothing else in `macho.py` needs changing. `LC_LOAD_DYLIB` and `LC_DYSYMTAB`
fall through to `unparsed_load_commands`, exactly as `LC_UNIXTHREAD`'s unknown
thread flavor already does for `VGA_reloc`, and the bundle's sections carry
`nreloc = 0`, so `_read_relocations` yields nothing.

### 2.9 The build-generated residue is the same as before

`+[VGAKernelServerInstance kernelServerInstance]` and
`+[VGAVersion driverKitVersionForVGA]` in `VGA_reloc`, and
`__mh_bundle_header`, `dyld_stub_binding_helper` and `__dyld_func_lookup` in
`VGA_psdrvr`, are emitted by the project type and the linker, not written by
hand. So are `_VGA_VERS_STRING`, `_VGA_VERS_NUM`, `_VGA_instance` and the
`_xxx.100`/`_xxx.103`/`_xxx.106` `__DATA,__bss` statics. They belong in the
source map's `unmapped` bucket with that reason class, per the drvPCIBus
precedent.

## 3. Artifact layout

### 3.1 Project restructure

`src/drivers-i386/video/vga` becomes `src/drivers-i386/video/drvVGA`, modelled on
`drvS3Generic`:

```
src/drivers-i386/video/drvVGA/
    Makefile  Makefile.preamble  Makefile.postamble
    VGA.drvproj/                    PROJECT_TYPE = Driver, driver.make
        Makefile  Makefile.preamble  Makefile.postamble  DriverInfo
        Default.table  SVGABIOS.table
        English.lproj/
            Localizable.strings  SVGABIOS.strings
            Help/VGA.rtfd
        VGA.lksproj/                PROJECT_TYPE = Kernel Server, kernelserver.make
            Makefile  Makefile.preamble  Makefile.postamble
            Load_Commands.sect  Unload_Commands.sect
            sources
        VGA_psdrvr.tproj/           bundle subproject
            Makefile  Makefile.preamble  Makefile.postamble
            sources
    reconstruction/
        VGA_reloc/{source-map.json, ledger.json}
        VGA_psdrvr/{source-map.json, ledger.json}
        divergences.md
```

`NAME = VGA` in the `.lksproj` yields `VGA_reloc`; `NAME = VGA` in the `.drvproj`
yields `VGA.config` containing a `VGA` version bundle. That is Apple's layout.
The `.drvproj` `Makefile` lists both subprojects in `TOOLS`, so `VGA_psdrvr` is
built and staged for the first time. `Display.modes` is deleted and dropped from
`GLOBAL_RESOURCES`. `src/drivers-i386/README` gains a `drvVGA` line in place of
`vga`.

Source file names inside `VGA.lksproj` are deliberately not fixed here. Apple's
translation-unit boundaries are recoverable from the `__DATA` and `__bss` static
ordering and the `_xxx.100`/`.103`/`.106` numbering, so file naming is decided in
the report pass and recorded in the source map rather than guessed now. The
existing four files carry across unchanged in Phase 0 so that the baseline build
is a build of today's code in tomorrow's structure.

### 3.2 Committed

The `reconstruction/` tree above; two reference-only profiles at
`tools/binrecon/profiles/{vga-reloc,vga-psdrvr}.json`, copied from
`pcmciabus.json` with `output_dir` set to `../out/vga-reloc` and
`../out/vga-psdrvr`; the MH_BUNDLE change to `tools/binrecon/binrecon/macho.py`
with its fixture and test; and `vm/build-i386-vga.sh`, modelled on
`vm/build-i386-input-recon.sh`.

`divergences.md` is one document covering both binaries, with a dedicated section
for the shared contract (§4.3).

### 3.3 Not committed

Reference binaries, rebuilt artifacts staged under `out/i386/`, and all analyzer
output under `tools/binrecon/out/`, which `.gitignore:17` already excludes. A
`VGA_reloc.i64` from an earlier IDA session already sits beside the reference;
the pipeline regenerates its own under the gitignored output directory and does
not read that one.

### 3.4 Reference paths

`BINRECON_REFERENCE` is per-shell-session:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr
```

## 4. The passes

### 4.1 Phase 0 — tooling and restructure

1. Add `MH_BUNDLE = 8` to the accepted file types in `read_macho`, with an
   MH_BUNDLE fixture in `tests/macho_fixture.py` and a case in `test_macho.py`.
2. Write the two profiles.
3. Restructure per §3.1, carrying the existing sources across unchanged.
4. Write `vm/build-i386-vga.sh`.
5. Build the untouched sources in the new structure as a baseline, so a later
   failure cannot be misattributed to the rewrite.

*Verify:* `pytest tools/binrecon/tests/test_macho.py` passes;
`binrecon validate --profile tools/binrecon/profiles/vga-reloc.json` and the
`vga-psdrvr` profile each print a reference identity with no rebuilt artifact;
`vm/build-i386-vga.sh` lands both a `VGA_reloc` and a `VGA_psdrvr` on disk.

If the baseline build fails, repairing that breakage is an explicit, separately
committed step before Phase 1. The driver has never been built in this tree, so
this is a real possibility rather than a formality.

### 4.2 Phase 1 — table and resource pass

The same carve-out from ledger discipline the prior specs made: every fix here
rests on a diff of our checked-in file against Apple's checked-in file, which is
stronger evidence than a decompilation. No analyzer run and no ledger entry is
required. The complete list, all from §2.5:

1. `Default.table`: `0x3d4-0x3d6` → `0x3d4-0x3dc`, `BW.2` → `BW:2`.
2. `SVGABIOS.table`: the same two, plus `"SVGA Mode" = "Yes"` and
   `"SVGA VESA BIOS Mode" = "0x6a"`.
3. `English.lproj/Localizable.strings` replaced with Apple's two entries.
4. `English.lproj/SVGABIOS.strings` added with Apple's two entries.
5. `Display.modes` deleted, and removed from `GLOBAL_RESOURCES`.
6. `Load_Commands.sect`: the missing trailing space on line 1 (§2.7).
7. `Unload_Commands.sect` added with the §2.7 content, to 67 bytes exactly.

`English.lproj/Help/VGA.rtfd` is authored as a stub so that
`"Help File" = "VGA.rtfd"` resolves, with a note in `divergences.md`. Reproducing
Apple's Help text is not reconstruction. `English.lproj/Info.rtf` is left alone
and recorded as a divergence.

Nothing else. Every other finding waits for the report pass.

*Verify:* `Default.table` and `SVGABIOS.table` each differ from the reference only
in `"Driver Version"`; both `.strings` files match byte for byte;
`Load_Commands.sect` is 164 bytes and `Unload_Commands.sect` is 67.

### 4.3 Phase 2 — report pass, both binaries

Per binary:

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/<name>.json`
   produces IDA 9.2, Ghidra 12.1 and angr 9.3.0 analyses plus
   `consensus-reference.json` under the gitignored `tools/binrecon/out/<name>/`.

2. **Map.** `binrecon source-map` anchored on IDA's named function partition,
   then hand-resolve the residue. Every reference function lands in exactly one
   bucket: `mapped`, `unmapped`, `boundary_disputed`, or `duplicate_candidates`.

   **A function is any IDA entry that is not contained within another one.** The
   Mach-O symbol table alone undercounts, because it names none of the six
   `vidBIOS` methods (§2.4). IDA's named entries alone also undercount, because a
   `static` C function carries no symbol and gets no name. What IDA's raw list
   overcounts is only the fragments its boundary heuristics carve *inside* an
   already-named function — `_emu486`'s per-opcode handlers. So the rule is
   containment, not naming: an unnamed entry lying wholly inside a named
   function's extent is one of its basic blocks and is excluded; an unnamed entry
   standing on its own is a `static` function and is included, under a
   synthesized `sub_<ADDRESS>` name because `source-map-v1` requires at least one.

   That yields **38 entries for `VGA_reloc`** — the 36 named plus two unnamed
   fragments of 81 and 37 bytes at 15640 and 15721, which sit past `_emu486`'s
   end — and **53 for `VGA_psdrvr`**: 37 named plus 16 unnamed statics.

   > **Corrected after Task 9.** An earlier draft of this rule said simply "a
   > function is an entry IDA names," which was drawn from `VGA_reloc`, where the
   > unnamed entries really are jump-table fragments. Applied to `VGA_psdrvr` it
   > excluded 2807 of that binary's 7057 `__text` bytes — 40% — including both
   > cursor blitters, at 603 and 481 bytes, and the eleven-entry driver vector
   > table `_VGAStart` installs. A rewrite built from that partition would have
   > produced a driver that draws no cursor. The excluded fragments under the
   > corrected rule are 1161 bytes inside `_emu486`, and they are recorded in
   > `divergences.md` as part of its structure rather than dropped silently.

   Because our source is disjoint from Apple's, each binary's report-pass map
   puts all of its hand-written symbols in `unmapped` — 28 for `VGA_reloc`, 19
   for `VGA_psdrvr` — with the reason class `no counterpart in our source` stated
   in `divergences.md`, alongside that binary's build-generated entries from §2.9
   under their own reason class. The rewrite pass
   regenerates the map and functions move to `mapped` as their source appears.
   `load_source_map` enforces the complete partition at every step, so nothing is
   silently dropped.

3. **Decompile.** Every reference function, batched by the translation units the
   `__DATA` static ordering implies.

4. **Report.** Write `divergences.md`: the reference decompilation and the
   design of its replacement, per function, plus a ledger entry per function.
   The `ledger-v1` vocabulary is `unexamined`, `signature-confirmed`,
   `control-flow-confirmed`, `assembly-matched`, `intentional-mismatch`. At the
   end of Phase 2 every hand-written function is `unexamined`, because none is
   written yet. `rebuilt_sha256` is `null` throughout, which `ledger-v1` permits.

**The shared-contract section.** `divergences.md` opens with a section settling
what both binaries must agree on, written from both sides' evidence before either
rewrite starts:

- the exact `VGAShmem_t` layout, which the kernel side validates — the reference
  logs `%s: shmem_size > sizeof (VGAShmem_t)(%d<>%d)`;
- the `IO_Framebuffer_*` get/set parameter protocol. An earlier draft of this
  section said it "appears in the `__cstring` of both binaries", which Task 9
  disproved: the bundle carries only `IO_Framebuffer_Register`,
  `IO_Framebuffer_SetDimensions`, `IOGetDisplayInfo` and `Set VGA VESA Mode`. It
  never sends `Map`, `Unmap`, `Dimensions` or `Unregister`, and maps the frame
  buffer itself through `_IOMapEISADeviceMemory`. The kernel side implements
  parameters the Window Server side does not use;
- the cursor state machine that `_VGADisplayCursor`/`_VGARemoveCursor` implement
  on the kernel side and `_VGAShieldCursor`/`_VGAUnshieldCursor` on the Window
  Server side.

Settling this once, from both sides, is the reason the report pass covers both
binaries before either is rewritten.

**Two questions the report pass must answer explicitly:** what `vidBIOS` is for,
given it has no method bodies (§2.4); and where Apple's translation-unit
boundaries fall, which fixes our source file names (§3.1).

**Done when** `load_source_map(path, reference_analysis=…, repo_root=…)` passes
for both binaries, every `unmapped` entry has a stated reason class in
`divergences.md`, and no function is without a ledger entry.

### 4.4 Phase 3 — rewrite

`VGA_psdrvr` first, then `VGA_reloc`. Each function is written from its
decompilation, and its ledger status advances to the level the new evidence
supports. Anything that cannot match — the build-generated glue of §2.9,
compiler-emitted statics, anything whose reference form depends on Apple's
toolchain — becomes `intentional-mismatch` with a reason and a reviewer, both of
which the ledger CLI requires.

The rewrite is approved as a unit, the way `drvBusMouse`'s was, so it is not
gated finding-by-finding. It stays inside `src/drivers-i386/video/drvVGA`; §1.4
governs everything outside.

`_emu486` gets its own commit or commits and its own section in `divergences.md`.
At 8088 bytes for its dispatch core, plus 69 handlers and roughly 2290 bytes of
tables, it is the largest single piece
of work in this effort.

### 4.5 Verification

Run at the end of each rewrite, against the rebuilt binaries.

**Gating:**

1. **Compiles.** `vm/build-i386-vga.sh` exits 0 and both `VGA_reloc` and
   `VGA_psdrvr` land on disk. Warnings are captured to a log and reviewed, but do
   not gate.

2. **Boots.** QEMU boot on a copy of the disk image, per CLAUDE.md §6, so a
   concurrent debugging session is unaffected. With `Default.table`, the boot log
   shows `VGADisplay: Mode Selected: 640 x 480 @ 60 Hz (BW:2)` and the console is
   usable. With `SVGABIOS.table`, it shows
   `VGADisplay: VESA mode selected: 0x6a`. That second run is the only end-to-end
   exercise `_emu486` gets: a mode set that reaches the video BIOS and returns is
   exactly what it exists to do.

**Reported, not gated.** Our builds are unstripped and carry extras; a reference
string or symbol our build lacks is a finding, an extra one of ours is not.

3. `parity_check.py` on `__TEXT,__cstring`, both binaries.
4. `parity_check.py` on `__TEXT,__text` symbol names, both binaries.
   `parity_check.py` compares names as a set. `_Start` and `_VGAStart` share an
   address in the psdrvr but are distinct names, so the set comparison is safe
   for both binaries here.
5. Section-size comparison against the reference, including the five
   `Loaded Server` sections of §2.7, which are small enough to match exactly.

## 5. Sequencing

**Phase 0 — tooling and restructure.** §4.1.

**Phase 1 — table and resource pass.** §4.2. Both tables, both `.strings` files,
both `.sect` files, at once.

**Phase 2 — report pass.** §4.3, both binaries, shared-contract section first.

**Phase 3a — rewrite `VGA_psdrvr`.** 19 symbols, 7057 bytes, no emulator. Proves
the MH_BUNDLE tooling and the restructured build on the smaller binary.

**Phase 3b — rewrite `VGA_reloc`.** 28 symbols, 18048 bytes, `_emu486` last.

## 6. Risks

**angr on MH_BUNDLE is unproven.** IDA and Ghidra load bundles without trouble;
CLE on a 1992-vintage 32-bit i386 bundle with prebound `__TEXT` addresses at
`0x70320000` is not established. If angr fails on `VGA_psdrvr`, its profile
disables angr and the psdrvr's consensus is built from two analyzers. The
`tools/binrecon/out/spd-noghidra` directory shows that precedent already exists.

**`_emu486` decompilation quality.** Partly resolved by the Task 7 analyzer run,
and in the encouraging direction. It is not one 10 KB straight-line function: it
is an 8088-byte dispatch core plus 69 per-opcode handlers averaging 19 bytes
each, every one of them returning to a shared dispatch point at `0x1E20`, with
roughly 2290 bytes of tables after it. That is a shape a reconstruction can
follow handler by handler rather than all at once.

What the run also showed is that the three analyzers agree on none of its
interior. IDA gives the core 8088 bytes; Ghidra gives 6931 and then fragments
along different boundaries; angr produced a phantom function overlapping the
core's opening bytes and had to be disabled for this binary to normalize at all.
So the risk has changed shape rather than disappeared: the danger is no longer
one indigestible function, it is that no analyzer's boundaries can be trusted
here and the handlers have to be read against the raw disassembly.

**The guest's display-driver build path.** Other `video/` drivers are marked
complete, so the toolchain is presumably sound, but `drvVGA` has never been built
in this tree. Phase 0's baseline build converts that assumption into a fact.

**Getting QEMU to select `IOVGADisplay`.** The gating boot test requires the
guest to be configured to use this driver rather than another display driver. If
that needs more than dropping the built `VGA.config` into place, it becomes a
Phase 0 item, since the verification of every later phase depends on it.
