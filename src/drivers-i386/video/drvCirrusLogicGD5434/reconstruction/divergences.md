# drvCirrusLogicGD5434 divergences

This document covers Apple's Cirrus Logic GD5434 display driver kernel server.

| Binary | Mach-O type | Size | SHA-256 |
| --- | --- | --- | --- |
| `CirrusLogicGD5434DisplayDriver_reloc` | MH_PRELOAD (type 5) | 41992 | `7DA038CCEA1CDE68B6CF2ACF4D12EE5056E7F0248ADD34D451FB96EA79C13D0D` |

Reference path, per shell session via `BINRECON_REFERENCE`:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\CirrusLogicGD5434DisplayDriver.config\CirrusLogicGD5434DisplayDriver_reloc
```

The Mach-O header carries `cpu_type = 7` (i386), `cpu_subtype = 3` (`CPU_SUBTYPE_386`),
`file_type = 5` (MH_PRELOAD), `flags = 0`. Four segments — `__TEXT` (0, 8192),
`__DATA` (8192, 8192), `__OBJC` (16384, 8192) and `Loaded Server` (24576, 8192).
`__TEXT,__text` is 4388 bytes at address 0.

**Every one of the 19 hand-written functions has now been examined against our
source, and 17 of the binary's 21 are byte-for-byte identical to the reference
under relocation masking** — see "Per-function findings" and "Build and parity"
below. That was not true when this report was first written, and the next three
paragraphs describe the pre-rewrite state; they are retained because the
`mapped`/`unmapped` history below is unreadable without them.

**At the report pass, no function had been examined against our source, because
our source implemented none of the reference's behaviour.** Our
`CirrusLogicGD5434DisplayDriver.lksproj` then implemented a class subclassing
`IOPCIDirectDevice`; Apple's implements `CirrusLogicGD5434DisplayDriver`, a
subclass of `IOFrameBufferDisplay`, plus the category
`CirrusLogicGD5434DisplayDriver(ProgramDAC)` and the two build-generated
classes. They shared no string and no ivar.

They were **not** wholly disjoint by name, and this document must not claim they
were. The invented class carried the same name as Apple's, so `binrecon
source-map` — which pairs `-[class selector]` symbols and looks at nothing else —
reported five of the 21 reference functions as `mapped`:

| Addr | Reference symbol | What our invented method actually does |
| --- | --- | --- |
| 0 | `initFromDeviceDescription:` | Hard-codes an 800×600×8 mode and three invented I/O port ranges, maps `0xa0000`/`0xc0000`/a guessed framebuffer aperture, then calls four invented setup methods; it never reads the PCI configuration space or a mode table. |
| 712 | `enterLinearMode` | Writes two guessed register values (CRTC `0x22`, "extended sequencer mode" `0x01`); the reference guards on `currentMode`, re-runs `setMode:` from `displayInfo`, clears the screen and reloads the gamma table. |
| 804 | `revertToVGAMode` | Writes the same two guessed registers back to `0x02`/`0x00`; the reference sets `currentMode = 2`, clears the screen, programs `_vgaMode` and calls `super`. |
| 3296 | `clearScreen` | `bzero` over an invented `framebuffer`/`framebufferSize` pair sized `width * height`; the reference zeroes the whole mapped aperture via the `vram` and `installedVRAMBytes` ivars, which our class does not have. |
| 3544 | `displayModes` | Two `IOLog` calls announcing a hard-coded mode list; the reference is a 16-byte accessor returning the `modeTable` ivar. |

That collision was **nominal only**. A shared selector name is not evidence of a
shared implementation, and the mapped count was therefore not the measure of
disjointness — the absence of any shared behaviour was, and that held for all 21
functions including those five. Every one had to be written from scratch, and
Tasks 3 and 4 wrote them. The per-function findings below record **the
reference's behaviour**; the diff against what we now build is in "Build and
parity".

## Evidence

### One analyzer, not three, and both reductions are recorded here

| Analyzer | Outcome |
| --- | --- |
| IDA 9.2 | **yes** — sole contributor to the consensus |
| Ghidra 12.1 | **disabled** — produces a valid document, but `binrecon` cannot normalize it |
| angr 9.3.0 | **disabled** — CFGFast misreads `__TEXT,__const` data as code |

Both analyzers are set to `"enabled": false` in
`tools/binrecon/profiles/cirruslogic-gd5434.json`. Neither reduction is a
judgement call about the binary; each has a reproducible error, quoted verbatim
below. The plan expected all three to run cleanly on this binary because it is
`cpu_subtype = 3` with no instruction emulator, unlike `VGA_reloc`. That
expectation held for IDA — no `-pmetapc` override was needed — but not for the
other two, for reasons unrelated to the emulator problem that stopped angr on
`VGA_reloc`.

#### angr — data in an executable section is disassembled as code

Verbatim, as `binrecon analyze` printed it to stderr:

```
binrecon: angr reference adapter failed: angr output is invalid: block at address 5148 is outside function at address 5172
```

The `binrecon: ` prefix is `cli.py`'s (`cli.py:80` and its siblings print
`f"binrecon: {error}"`); `run-summary.json`'s `diagnostic` field carries the bare
`str(error)` without it (`binrecon/runner.py:196`), so match on the text after
the prefix when looking for this message in a summary. The current
`run-summary.json` records the successful IDA-only run and its `diagnostic` is
`null`.

The failure is deterministic: the adapter was invoked twice more directly,
outside the runner, and produced the identical message both times.

Addresses 5148 and 5172 are **not code**. They lie inside `_gamma8`, the
256-byte gamma lookup table at `__TEXT,__const` 4976–5232, whose bytes at
5148 are

```
d1 d2 d2 d3 d3 d4 d5 d5 d6 d6 d7 d8 d8 d9 d9 da
```

— a monotonically rising ramp, which x86 happens to decode as a plausible
instruction stream (`d1 d2` is `rcl edx,1`). The cause is that this Mach-O puts
`__cstring` and `__const` inside the `__TEXT` segment, so `read_macho` reports
their permissions as `rx`; angr's CFGFast therefore treats the whole segment as
executable and recovers phantom functions in the middle of constant data. IDA
and Ghidra both read the same bytes correctly as data.

This is a different failure from `VGA_reloc`'s. There, angr misdisassembled six
bytes of genuine code inside `_emu486`. Here it disassembles a lookup table.
**Inference:** the same failure should be expected for any driver in this family
whose `__TEXT,__const` holds byte tables, and it is fixable in principle by
giving the profile an `analysis_scope` limited to `__text` — the mechanism exists
(`binrecon/profile.py:68`) and `kernel-driverkit.json` is the only profile in the
tree that uses it. That change was not made here: none of the 21 other driver
profiles declares a scope, so introducing one for this profile alone would be an
undiscussed deviation from the established shape. Recorded as a candidate for
separate infrastructure work.

#### Ghidra — `binrecon` cannot normalize its relocation operand metadata

Verbatim, as `binrecon analyze` printed it to stderr (same prefix convention as
above — `run-summary.json`'s `diagnostic` would hold the text without the
`binrecon: `):

```
binrecon: Ghidra relocation operand metadata is ambiguous
```

Note this is **not** an adapter failure — Ghidra ran to completion and wrote a
valid, schema-conforming 762 KB analysis document. That document went to the
dot-free scratch `output_dir` described below and was not retained, so the
instrumentation output quoted here is all that survives of it. The rejection
happens later,
in `normalize_analysis`, at `binrecon/normalize.py:432`. Instrumenting
`_ghidra_operand_owner` identifies the exact instruction:

```
FAIL at instruction addr 1152 bytes C7825C02000000200000 MOV dword ptr [EDX + 0x25c], 0x2000
  relocation {"addend": 0, "address": 1158, "kind": "i386-vanilla-32-absolute", "target": "__DATA,__data"} index 73 width 4 relative False
```

That instruction is inside `-[... determineConfiguration]`: it is
`self->modeTable = _GD5434_modeTable`, the store whose immediate `0x2000` is the
relocated address of `__DATA,__data`. Both operands carry a Ghidra reference —
operand 0 is a `WRITE` to `[EDX+0x25c]`, operand 1 is the relocated immediate —
so `owners` ends up with two entries, and the `READ`/`WRITE` tie-break at
`normalize.py:421-430` does not reduce it to one because the memory operand is
itself a semantic reference. `normalize_analysis` therefore aborts.

`mov [reg+disp], imm32` where the immediate is relocated is a common shape in
this driver — it is how every mode-table and default-mode ivar is initialized —
so this is not a one-off. It looks like a limitation of `binrecon`'s Ghidra
normalization rather than a defect in Ghidra or in the binary, and, like the
`VGA_psdrvr` relocation-kind gap recorded in `drvVGA/reconstruction/divergences.md`,
it is recorded here as a candidate for separate infrastructure work rather than
something this task fixes.

#### A separate, environment-only Ghidra failure that is not the reason for the disablement

The first run in this worktree failed earlier and differently, with

```
binrecon: ghidra reference adapter failed: Ghidra failed with exit code 1
```

whose underlying cause, from the adapter's own `.ghidra.log` — the retained
`tools/binrecon/out/cirruslogic-gd5434/binrecon-run-0iv2wn2a/analysis-reference-ghidra.json.ghidra.log`,
line 40, quoted with its leading timestamp and followed by the first four of its
stack frames (the rest elided) — is

```
2026-07-27 00:00:41 ERROR (HeadlessAnalyzer) Abort due to Headless analyzer error: Path element starting with '.' is not permitted java.lang.IllegalArgumentException: Path element starting with '.' is not permitted
	at ghidra.util.NamingUtilities.checkName(NamingUtilities.java:108)
	at ghidra.framework.protocol.ghidra.GhidraURL.checkValidProjectPath(GhidraURL.java:448)
	at ghidra.framework.protocol.ghidra.GhidraURL.checkLocalAbsolutePath(GhidraURL.java:429)
	at ghidra.framework.model.ProjectLocator.<init>(ProjectLocator.java:75)
	…
```

Ghidra 12.1 refuses to create a project whose path contains any dot-prefixed
element. `binrecon` puts the Ghidra workspace under the profile's `output_dir`,
and this work was done in a git worktree at
`D:\RhapsodiOS\.claude\worktrees\cirrus-thinkpad-recon`, so the path contains
`.claude`. **This is a property of the checkout location, not of the profile or
the binary** — the committed `output_dir` of `../out/cirruslogic-gd5434` is
correct and would work unchanged from the main checkout at `D:\RhapsodiOS`. It is
recorded only so that a future reader who sees this error knows it is not the
same problem as the normalization failure above, and it is repeated in the
plan's Global Constraints so that every later task inherits the diagnosis rather
than rediscovering it. Ghidra was re-run with
`output_dir` redirected to a dot-free path, which is how the normalization
failure — the location-independent one that actually justifies the disablement —
was reached and diagnosed.

### Why IDA alone is nevertheless trustworthy here

**The load-bearing corroboration is the Mach-O symbol table, and it is the only
one that can be re-checked from what is committed.**

`__TEXT,__text` carries 21 symbol-table entries. IDA recovers 21 functions.
**The two address sets are identical** — neither `set(IDA addresses) -
set(symtab addresses)` nor the reverse has a single member — and IDA's sizes are
consistent with the symbol table throughout: every function ends at or before
the next symbol's address, the differences being exactly the 14 padding gaps
tabulated below, 34 bytes in total. Re-derivable from
`published/analysis-reference-ida.json` and `binrecon.macho.read_macho` alone.

**The names are *not* quite identical, in three places.** The symbol table
spells the `ProgramDAC` methods with the category qualifier and IDA drops it:

| Address | Symbol table | IDA |
| --- | --- | --- |
| 3588 | `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setTransferTable:count:]` | `-[CirrusLogicGD5434DisplayDriver setTransferTable:count:]` |
| 3924 | `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setBrightness:token:]` | `-[CirrusLogicGD5434DisplayDriver setBrightness:token:]` |
| 4088 | `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setGammaTable]` | `-[CirrusLogicGD5434DisplayDriver setGammaTable]` |

The other 18 names match character for character. The three differences are a
display convention, not a disagreement about the binary — same addresses, same
extents — but the set equality is over addresses and extents, not over names.

There are no unnamed fragments, so the containment rule that had to be
introduced for `VGA_psdrvr` does not bite here; `filter_contained_fragments.py`
would be a no-op.

**Ghidra agreed too, but that agreement was not retained and cannot be
audited.** During the dot-free rerun Ghidra's document was observed to recover 19
of the 21 functions with addresses, byte sizes and instruction counts matching
IDA, and to miss 3588 (`-[... setTransferTable:count:]`) and 4364
(`+[...KernelServerInstance kernelServerInstance]`) — both immediately preceded
by three `0x00` padding bytes rather than by `nop`s. **That document was written
to a scratch directory outside the worktree and was not kept.** Nothing but the
failed run's `.ghidra.log` survives, so the comparison above is a recollection of
what was seen, not evidence a reader can check, and it should carry no weight in
accepting the single-analyzer consensus. It is recorded because it is what
happened, not because it can be verified.

So every claim below rests on IDA 9.2, the Mach-O symbol table, the `__OBJC`
metadata sections and the raw section bytes, all read directly — and, of those,
only the last three are independent of IDA.

### Function partition

`CirrusLogicGD5434DisplayDriver_reloc`, 21 entries. The committed
`source-map.json` alongside this document reads:

| Bucket | Count |
| --- | --- |
| mapped | 19 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

The 19 `mapped` are the 19 hand-written functions, split across
`CirrusLogicGD5434DisplayDriver.m` (15 entries, 0–3588) and `ProgramDAC.m` (4
entries, 3588–4364), each carrying the source path and line it was reconstructed
at. The 2 `unmapped` are the build-generated glue at 4364 and 4376
(`+[CirrusLogicGD5434DisplayDriverKernelServerInstance kernelServerInstance]`,
`+[CirrusLogicGD5434DisplayDriverVersion driverKitVersionForCirrusLogicGD5434DisplayDriver]`),
emitted by the Kernel Server project type and with no reconstructed source to
point at.

**At the report pass the same map read `mapped 5` / `unmapped 16`** — the five
nominal name collisions at 0, 712, 804, 3296 and 3544 tabulated at the top of
this document, none of which had a matching implementation, and 16 with reason
class `no counterpart in our source`. **Nothing was moved by hand**, in either
direction, at either pass: the five collisions were left in `mapped` rather than
suppressed by renaming our invented source, because the buckets should report
what the tool observed.

The source map's entry sizes total **4354**, not `__text`'s 4388. The 34-byte
shortfall is inter-function padding and **is not a finding**: IDA reports true
function extents, and the linker pads between functions to restore alignment. The
partition spans 0 to 4388 with no unclaimed region, which is the property that
matters, and it was confirmed directly — the first entry starts at 0, the last
ends at 4388, and every byte in between belongs either to an entry or to one of
these 14 gaps:

| Gap | Bytes | Content |
| --- | --- | --- |
| 553–556 | 3 | `90 90 90` |
| 710–712 | 2 | `90 90` |
| 801–804 | 3 | `90 90 90` |
| 890–892 | 2 | `90 90` |
| 1658–1660 | 2 | `90 90` |
| 1689–1692 | 3 | `90 90 90` |
| 2275–2276 | 1 | `90` |
| 3325–3328 | 3 | `90 90 90` |
| 3387–3388 | 1 | `90` |
| **3585–3588** | 3 | **`00 00 00`** |
| 3921–3924 | 3 | `90 90 90` |
| 4001–4004 | 3 | `90 90 90` |
| 4086–4088 | 2 | `90 90` |
| **4361–4364** | 3 | **`00 00 00`** |

**Correction to the plan's description of these gaps.** The plan calls all 14
`nop` padding. Twelve are; **two are zero bytes, not `nop`** — 3585–3588 and
4361–4364. Those two are exactly the boundaries between translation units
(`ProgramDAC.m` begins at 3588, `CirrusLogicGD5434DisplayDriver_instance.m`
begins at 4364). Padding emitted by the assembler *within* one object file's
`.text` is `nop`; padding inserted by the linker *between* object files is zero
fill. This is minor in itself, but it is independent corroboration of the module
boundaries that `__OBJC,__module_info` states, so it is recorded rather than
smoothed over.

### The `__TEXT,__cstring` section

Read from the binary, not transcribed. 571 bytes at 4388, 20 strings, all 20
referenced. Every string is listed here with the function that references it, so
that Tasks 3 and 4 can reproduce them exactly, including the punctuation and the
trailing newlines.

| Address | String | Referenced by |
| --- | --- | --- |
| 4388 | `%s: Selected mode not supported.\n` | `initFromDeviceDescription:`, `selectMode` |
| 4422 | `%s: Trying default mode.\n` | `initFromDeviceDescription:` |
| 4448 | `%s: Default mode not supported!\n` | `initFromDeviceDescription:` |
| 4481 | `%s: Unable to map frame buffer\n` | `initFromDeviceDescription:` |
| 4513 | `%s: Cirrus Logic CL-GD543X or CL-GD5446 not found\n` | `determineConfiguration` |
| 4564 | `Cirrus Logic GD5430` | `determineConfiguration` |
| 4584 | `Cirrus Logic GD5434` | `determineConfiguration` |
| 4604 | `Cirrus Logic GD5436` | `determineConfiguration` |
| 4624 | `Cirrus Logic GD5446` | `determineConfiguration` |
| 4644 | `Unknown device` | `determineConfiguration` |
| 4659 | `%s: %s detected (%d Bytes)\n` | `determineConfiguration` |
| 4687 | `Bus Type` | `determineConfiguration` |
| 4696 | `PCI` | `determineConfiguration` |
| 4700 | `%s: unsupported PCI hardware.` | `setPCIConfiguration` |
| 4730 | `%s: PCI Dev: %d Func: %d Bus: %d\n` | `setPCIConfiguration` |
| 4764 | `%s: Can't set memory range, using default.\n` | `setPCIConfiguration` |
| 4808 | `%s: Can't set to default range either!\n` | `setPCIConfiguration` |
| 4848 | `%s: Incorrect number of address ranges: %d.\n` | `setPCIConfiguration` |
| 4893 | `CirrusLogicGD5434DisplayDriver` | `name` |
| 4924 | ``%s: Invalid brightness level `%d'\n`` | `setBrightness:token:` |

Two details worth carrying into the rewrite verbatim: `%s: unsupported PCI
hardware.` has **no trailing newline** where every other log string does, and
the brightness message uses an asymmetric quote pair — backtick before, single
quote after.

The plan's hand-transcribed list has 20 entries and the binary has 20 strings, so
there is nothing to add. The table above is the binary's, and it is authoritative.

## Source-file partition

`__OBJC,__module_info` is 48 bytes — three 16-byte `objc_module` records
(`{version, size, char *name, struct objc_symtab *symtab}`). Read directly, the
three `name` pointers resolve in `__OBJC,__class_names` to:

| Module | `__text` range | symtab | Defines |
| --- | --- | --- | --- |
| `CirrusLogicGD5434DisplayDriver.m` | 0 – 3588 | 18588 | `@implementation CirrusLogicGD5434DisplayDriver` (1 class) |
| `ProgramDAC.m` | 3588 – 4364 | 18604 | `@implementation CirrusLogicGD5434DisplayDriver(ProgramDAC)` (1 category) |
| `CirrusLogicGD5434DisplayDriver_instance.m` | 4364 – 4388 | 18620 | `CirrusLogicGD5434DisplayDriverVersion` and `CirrusLogicGD5434DisplayDriverKernelServerInstance` (2 classes) |

`__OBJC,__symbols` is 52 bytes, which is exactly three 12-byte `objc_symtab`
headers plus four 4-byte `defs` pointers (`3*12 + 4*4 = 52`). Its raw bytes give
the split directly: the first symtab declares 1 class and 0 categories, the
second 0 classes and 1 category, the third 2 classes and 0 categories — four defs
in total, matching the three `__OBJC,__class` records plus the one
`__OBJC,__category` record with none left over.

`__OBJC,__category` is 20 bytes, one record: category name `ProgramDAC`, class
name `CirrusLogicGD5434DisplayDriver`, pointing at `__cat_inst_meth` (44 bytes =
8-byte header plus three 12-byte methods).

`__OBJC,__class` is 120 bytes, three 40-byte `struct objc_class` records:

| Class | Superclass | `instance_size` | ivars | methods |
| --- | --- | --- | --- | --- |
| `CirrusLogicGD5434DisplayDriver` | `IOFrameBufferDisplay` | 616 | 16 | 15 instance |
| `CirrusLogicGD5434DisplayDriverVersion` | `IODevice` | 264 | none | 1 class method |
| `CirrusLogicGD5434DisplayDriverKernelServerInstance` | `Object` | 4 | none | 1 class method |

The three boundaries are therefore stated outright by the binary's own metadata;
no inference from private-name numbering was needed. The zero-fill padding at
3585–3588 and 4361–4364 noted above corroborates them independently.

**`CirrusLogicGD5434DisplayDriver.lksproj`'s `sources` should name two
hand-written files:** `CirrusLogicGD5434DisplayDriver.m` and `ProgramDAC.m`. The
`CirrusLogicGD5434DisplayDriver_instance.m` unit is emitted by the Kernel Server
project type and must not be written by hand.

### The ivar layout

`__OBJC,__instance_vars` is 196 bytes — a 4-byte count of 16 followed by sixteen
12-byte records — and gives every name, type encoding and offset directly. The
first ivar sits at 552, so `IOFrameBufferDisplay`'s instance size is 552 and this
class adds 64 bytes to reach 616.

| Offset | Name | Encoding | Meaning |
| --- | --- | --- | --- |
| 552 (`0x228`) | `installedVRAMBytes` | `I` | detected VRAM, `0x40000 << (SR15 & 0x0F)` |
| 556 (`0x22C`) | `pciBus` | `I` | never read or written by any function in this binary |
| 560 (`0x230`) | `pciAddress` | `I` | never read or written by any function in this binary |
| 564 (`0x234`) | `busType` | `i` | 1 when the config table's `Bus Type` is `PCI`, else 0 |
| 568 (`0x238`) | `physicalAddress` | `I` | frame-buffer physical base |
| 572 (`0x23C`) | `vram` | `^v` | mapped frame-buffer virtual address |
| 576 (`0x240`) | `redTransferTable` | `*` | |
| 580 (`0x244`) | `greenTransferTable` | `*` | |
| 584 (`0x248`) | `blueTransferTable` | `*` | |
| 588 (`0x24C`) | `transferTableCount` | `i` | |
| 592 (`0x250`) | `brightnessLevel` | `i` | 0…64 |
| 596 (`0x254`) | `currentMode` | `i` | state: 0 initialized, 1 linear, 2 VGA |
| 600 (`0x258`) | `chipType` | `i` | 0 GD5430, 1 GD5434, 2 GD5436, 3 GD5446, 4 unknown |
| 604 (`0x25C`) | `modeTable` | `^{?}` | `IODisplayInfo *` |
| 608 (`0x260`) | `modeTableCount` | `i` | |
| 612 (`0x264`) | `defaultMode` | `i` | |

`pciBus` and `pciAddress` are declared but dead — `setPCIConfiguration` passes
the addresses of three *stack* bytes to `getPCIdevice:function:bus:` and never
copies them into the ivars. This is an observation, not an inference: no
instruction in `__text` references offset 556 or 560.

### The mode-programming struct

`setMode:`'s type encoding, read from `__OBJC,__meth_var_types`, is

```
v12@8:12r^{?=C[4C][25C][21C][9C]CCCCCCCCCC}16
```

so the argument is a **`const` pointer to a 70-byte struct** of
`unsigned char`: one scalar, then arrays of 4, 25, 21 and 9, then ten more
scalars — `1 + 4 + 25 + 21 + 9 + 10 = 70`. That is exactly the stride between
consecutive `_GD5434_mode_*` symbols in `__const` (5302 → 5372 → 5442 …), so the
encoding and the data agree. Mapping the fields onto what `setMode:` does with
them (see finding 8) gives:

| Offset | Field | Consumed as |
| --- | --- | --- |
| 0 | `misc` | Miscellaneous Output, port `0x3C2` |
| 1–4 | `seq[4]` | SR01–SR04 |
| 5–29 | `crtc[25]` | CR00–CR18 |
| 30–50 | `attr[21]` | AR00–AR14 |
| 51–59 | `gfx[9]` | GR00–GR08 |
| 60 | | SR07 |
| 61 | | SR0F, merged under mask `0x9F` |
| 62 | | SR0E — **and the flag that gates the SR0E/SR1E/SR07 extended path when zero** |
| 63 | | SR1E |
| 64 | | GR0B, merged under mask `0xC0` |
| 65 | | CR1A |
| 66 | | CR1B |
| 67 | | SR16 low nibble, used when SR0F bit 2 is set |
| 68 | | SR16 low nibble, used when SR0F bit 2 is clear |
| 69 | | Cirrus hidden DAC register, port `0x3C6` |

Two decoded instances, as evidence that the layout is right — `_vgaMode` is
recognisably a stock VGA register set and the GD5434 640×480×8 mode is
recognisably a packed-pixel one:

```
_vgaMode @ 5232
  misc = 67
  seq  = 00 03 00 03
  crtc = 5F 4F 50 82 55 81 BF 1F 00 4F 0D 0E 00 00 00 00 9C 8E 8F 28 1F 96 B9 A3 FF
  attr = 00 01 02 03 04 05 14 07 38 39 3A 3B 3C 3D 3E 3F 0C 00 0F 08 00
  gfx  = 00 00 00 00 00 10 0E 00 FF
  tail = 00 00 00 00 00 00 00 71 71 00

_GD5434_mode_640_8_60 @ 5302
  misc = E3
  seq  = 01 0F 00 0E
  crtc = 5F 4F 50 82 54 80 0B 3E 00 40 00 00 00 00 00 00 EA 8C DF 50 00 E7 04 E3 FF
  attr = 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 41 00 0F 00 00
  gfx  = 00 00 00 00 00 40 05 0F FF
  tail = 01 20 7E 33 00 00 22 01 01 00
```

`_vgaMode`'s offset-62 byte is `00`, so the extended SR0E/SR1E writes and the
`SR07 |= 0x10` step are both skipped when reverting to VGA — which is what makes
offset 62 a mode-kind flag as well as a data byte.

### The mode tables

`__DATA,__data` is 7072 bytes and holds exactly two arrays of `IODisplayInfo`,
whose size is 136 bytes (confirmed independently three ways: the
`displayModes` type encoding `^{?=iiiii^vii[64c]I^viiiiiiI[1I]}` sums to 136;
`src/driverkit-3/driverkit/displayDefs.h` as checked in gives the same layout;
and `selectMode` indexes the array with `i*17*8`).

| Symbol | Address | Entries | `defaultMode` | `modeTableCount` |
| --- | --- | --- | --- | --- |
| `_GD5434_modeTable` | 8192 | 24 | 4 | 24 |
| `_GD5446_modeTable` | 11456 | 28 | 8 | 28 |

Both tables are **mutable** — `determineConfiguration` writes `memorySize`,
`scanRate`, `screenWidth`, `screenHeight` and `modeUnavailableFlag` back into
whichever table it selected. They are in `__DATA` rather than `__TEXT,__const`
for exactly that reason, and the rewrite must not make them `const`.

**Read the column legend before transcribing either table.** The column headings
are not field names, one initialized field has no column at all, and one column
is not the value the field stores:

| Column | `IODisplayInfo` field | Offset | Note |
| --- | --- | --- | --- |
| W×H | `width` × `height` | 0, 4 | |
| — | **`totalWidth`** | **8** | **not a column; see below** |
| rowBytes | `rowBytes` | 12 | |
| Hz | **`refreshRate`** | 16 | plain integer, e.g. `60`, not a rate code |
| bpp | `bitsPerPixel` | 24 | **column is the human depth, stored value differs; see below** |
| colorSpace | `colorSpace` | 28 | |
| encoding | `pixelEncoding` | 32 | `char[64]`, NUL-padded to the full 64 bytes |
| `parameters` | `parameters` | 100 | address of the 70-byte register struct |

**`totalWidth` is nonzero in all 52 entries of both tables, and in every one of
them it equals `width`.** It is not a column because it would duplicate the W×H
column exactly, not because it ships zero — it does not appear in the all-zero
list below, and an implementer who emits only the columns would leave every
entry with `totalWidth == 0`, which is wrong in all 52. Set
`totalWidth = width` for every entry in both tables. Read directly out of
`__DATA,__data` at 8192 and 11456, 136-byte stride, offset 8 of each entry.

**The `bpp` column is the human bit depth; `bitsPerPixel` stores an
`IOBitsPerPixel` enumerator, which is a different number.** The mapping (from
`src/driverkit-3/driverkit/displayDefs.h`, and the only three values that occur
in either table) is

| `bpp` column | Stored `bitsPerPixel` | Enumerator |
| --- | --- | --- |
| 8 | **1** | `IO_8BitsPerPixel` |
| 15 | **3** | `IO_15BitsPerPixel` |
| 24 | **4** | `IO_24BitsPerPixel` |

Transcribe 1, 3 and 4 — never 8, 15 and 24.

`_GD5434_modeTable`, 24 entries. `colorSpace` 1 is `IO_OneIsWhiteColorSpace`,
2 is `IO_RGBColorSpace`; every 8-bit mode appears twice, once greyscale and once
pseudo-colour.

| # | W×H | rowBytes | Hz | bpp | colorSpace | encoding | `parameters` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 640×480 | 2560 | 60 | 24 | 2 | `--------RRRRRRRRGGGGGGGGBBBBBBBB` | `_GD5434_mode_640_24_60` |
| 1 | 640×480 | 2560 | 75 | 24 | 2 | `--------RRRRRRRRGGGGGGGGBBBBBBBB` | `_GD5434_mode_640_24_75` |
| 2 | 800×600 | 800 | 60 | 8 | 1 | `WWWWWWWW` | `_GD5434_mode_800_8_60` |
| 3 | 800×600 | 800 | 75 | 8 | 1 | `WWWWWWWW` | `_GD5434_mode_800_8_75` |
| 4 | 800×600 | 800 | 60 | 8 | 2 | `PPPPPPPP` | `_GD5434_mode_800_8_60` |
| 5 | 800×600 | 800 | 75 | 8 | 2 | `PPPPPPPP` | `_GD5434_mode_800_8_75` |
| 6 | 800×600 | 1600 | 60 | 15 | 2 | `-RRRRRGGGGGBBBBB` | `_GD5434_mode_800_15_60` |
| 7 | 800×600 | 1600 | 75 | 15 | 2 | `-RRRRRGGGGGBBBBB` | `_GD5434_mode_800_15_75` |
| 8 | 800×600 | 3200 | 60 | 24 | 2 | `--------RRRRRRRRGGGGGGGGBBBBBBBB` | `_GD5434_mode_800_24_60` |
| 9 | 1024×768 | 1024 | 60 | 8 | 1 | `WWWWWWWW` | `_GD5434_mode_1024_8_60` |
| 10 | 1024×768 | 1024 | 75 | 8 | 1 | `WWWWWWWW` | `_GD5434_mode_1024_8_75` |
| 11 | 1024×768 | 1024 | 60 | 8 | 2 | `PPPPPPPP` | `_GD5434_mode_1024_8_60` |
| 12 | 1024×768 | 1024 | 75 | 8 | 2 | `PPPPPPPP` | `_GD5434_mode_1024_8_75` |
| 13 | 1024×768 | 2048 | 60 | 15 | 2 | `-RRRRRGGGGGBBBBB` | `_GD5434_mode_1024_15_60` |
| 14 | 1024×768 | 2048 | 75 | 15 | 2 | `-RRRRRGGGGGBBBBB` | `_GD5434_mode_1024_15_75` |
| 15 | 1152×864 | 1152 | 60 | 8 | 1 | `WWWWWWWW` | `_GD5434_mode_1152_8_60` |
| 16 | 1152×864 | 1152 | 75 | 8 | 1 | `WWWWWWWW` | `_GD5434_mode_1152_8_75` |
| 17 | 1152×864 | 1152 | 60 | 8 | 2 | `PPPPPPPP` | `_GD5434_mode_1152_8_60` |
| 18 | 1152×864 | 1152 | 75 | 8 | 2 | `PPPPPPPP` | `_GD5434_mode_1152_8_75` |
| 19 | 1152×864 | 2304 | 60 | 15 | 2 | `-RRRRRGGGGGBBBBB` | `_GD5434_mode_1152_15_60` |
| 20 | 1280×1024 | 1280 | 60 | 8 | 1 | `WWWWWWWW` | `_GD5434_mode_1280_8_60` |
| 21 | 1280×1024 | 1280 | 70 | 8 | 1 | `WWWWWWWW` | `_GD5434_mode_1280_8_70` |
| 22 | 1280×1024 | 1280 | 60 | 8 | 2 | `PPPPPPPP` | `_GD5434_mode_1280_8_60` |
| 23 | 1280×1024 | 1280 | 70 | 8 | 2 | `PPPPPPPP` | `_GD5434_mode_1280_8_70` |

`_GD5446_modeTable`, 28 entries. It adds 640×480 at 8 and 15 bpp, adds
1152×864×15 at 75 Hz, and substitutes GD5446-specific register sets for the
15-bpp and the 1152/1280 modes while reusing the GD5434 register sets elsewhere.

The same column legend applies: **`totalWidth` equals `width` in all 28 entries
and is again not a column**, `Hz` is `refreshRate`, and the `bpp` column is the
human depth — store 1 for 8, 3 for 15. The `encoding` column is omitted here
because `pixelEncoding` follows the same rule as in the GD5434 table:
`WWWWWWWW` for `colorSpace` 1, `PPPPPPPP` for 8 bpp at `colorSpace` 2,
`-RRRRRGGGGGBBBBB` for 15 bpp.

| # | W×H | rowBytes | Hz | bpp | colorSpace | `parameters` |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 640×480 | 640 | 60 | 8 | 1 | `_GD5434_mode_640_8_60` |
| 1 | 640×480 | 640 | 75 | 8 | 1 | `_GD5434_mode_640_8_75` |
| 2 | 640×480 | 640 | 60 | 8 | 2 | `_GD5434_mode_640_8_60` |
| 3 | 640×480 | 640 | 75 | 8 | 2 | `_GD5434_mode_640_8_75` |
| 4 | 640×480 | 1280 | 60 | 15 | 2 | `_GD5446_mode_640_15_60` |
| 5 | 640×480 | 1280 | 75 | 15 | 2 | `_GD5446_mode_640_15_75` |
| 6 | 800×600 | 800 | 60 | 8 | 1 | `_GD5434_mode_800_8_60` |
| 7 | 800×600 | 800 | 75 | 8 | 1 | `_GD5434_mode_800_8_75` |
| 8 | 800×600 | 800 | 60 | 8 | 2 | `_GD5434_mode_800_8_60` |
| 9 | 800×600 | 800 | 75 | 8 | 2 | `_GD5434_mode_800_8_75` |
| 10 | 800×600 | 1600 | 60 | 15 | 2 | `_GD5446_mode_800_15_60` |
| 11 | 800×600 | 1600 | 75 | 15 | 2 | `_GD5446_mode_800_15_75` |
| 12 | 1024×768 | 1024 | 60 | 8 | 1 | `_GD5434_mode_1024_8_60` |
| 13 | 1024×768 | 1024 | 75 | 8 | 1 | `_GD5434_mode_1024_8_75` |
| 14 | 1024×768 | 1024 | 60 | 8 | 2 | `_GD5434_mode_1024_8_60` |
| 15 | 1024×768 | 1024 | 75 | 8 | 2 | `_GD5434_mode_1024_8_75` |
| 16 | 1024×768 | 2048 | 60 | 15 | 2 | `_GD5434_mode_1024_15_60` |
| 17 | 1024×768 | 2048 | 75 | 15 | 2 | `_GD5434_mode_1024_15_75` |
| 18 | 1152×864 | 1152 | 60 | 8 | 1 | `_GD5446_mode_1152_8_60` |
| 19 | 1152×864 | 1152 | 75 | 8 | 1 | `_GD5446_mode_1152_8_75` |
| 20 | 1152×864 | 1152 | 60 | 8 | 2 | `_GD5446_mode_1152_8_60` |
| 21 | 1152×864 | 1152 | 75 | 8 | 2 | `_GD5446_mode_1152_8_75` |
| 22 | 1152×864 | 2304 | 60 | 15 | 2 | `_GD5434_mode_1152_15_60` |
| 23 | 1152×864 | 2304 | 75 | 15 | 2 | `_GD5446_mode_1152_15_75` |
| 24 | 1280×1024 | 1280 | 60 | 8 | 1 | `_GD5446_mode_1280_8_60` |
| 25 | 1280×1024 | 1280 | 70 | 8 | 1 | `_GD5446_mode_1280_8_70` |
| 26 | 1280×1024 | 1280 | 60 | 8 | 2 | `_GD5446_mode_1280_8_60` |
| 27 | 1280×1024 | 1280 | 70 | 8 | 2 | `_GD5446_mode_1280_8_70` |

In both tables every entry ships with `frameBuffer`, `flags`, `memorySize`,
`scanRate`, `_reserved1`, `dotClockRate`, `screenWidth`, `screenHeight`,
`modeUnavailableFlag` and `_reserved[0]` all zero. They are filled in at runtime.
**`totalWidth` and `refreshRate` are not on that list** — both are initialized
and nonzero in all 52 entries, `totalWidth` to `width` and `refreshRate` to the
`Hz` column. Every one of these statements was checked field by field across
both tables against `__DATA,__data`.

**Two mode-parameter structs in `__const` are referenced by neither table:**
`_GD5434_mode_640_15_60` (5442) and `_GD5434_mode_640_15_75` (5512). The GD5446
table uses `_GD5446_mode_640_15_60`/`_75` for those geometries and the GD5434
table has no 640×480×15 entry at all. They are dead data — 140 bytes. **Inference:**
they are leftovers from a revision in which the GD5434 table carried 640×480×15
modes, kept because a file-scope `static const` array is emitted whether or not
anything references it. Tasks 3 and 4 should reproduce them if byte-level `__const`
parity is wanted, and may omit them otherwise; nothing reads them.

## Per-function findings

Addresses are decimal, as in the source map. All 21 entries, in address order.
`self` is `CirrusLogicGD5434DisplayDriver *` throughout, and ivar names are those
of the `__OBJC,__instance_vars` table above.

Three conventions apply to every finding and are stated once here rather than
repeated:

- **`outb`/`outw` come from `src/driverkit-3/driverkit/i386/ioPorts.h`.** Each is a
  `static __inline__` containing `static int xxx;` and an
  `outb %2,%1; lock; incl %0` asm body. That is why every `out` in this binary is
  followed by `lock inc ds:_xxx.NN`, and why the rewrite does not have to produce
  those increments by hand — they fall out of calling `outb()`/`outw()`. A word
  `out` to an index port writes the index in `AL` and the data in `AH`, so
  `outw(0x3C4, 0x4A0B)` sets sequencer register `0x0B` to `0x4A`.
- **No PCI configuration register is touched directly.** This driver reads and
  writes PCI config space only through `IODeviceDescription`'s
  `getPCIdevice:function:bus:`, `getPCIConfigSpace:` and `setPCIConfigSpace:`.
  There is no `0xCF8`/`0xCFC` access anywhere in `__text`.
- **The only imports are** `_IOFree`, `_IOLog`, `_IOMalloc`, `_bzero`,
  `_objc_msgSend` and `_objc_msgSendSuper`, plus the class references
  `.objc_class_name_IODevice`, `.objc_class_name_IOFrameBufferDisplay` and
  `.objc_class_name_Object`. Every other DriverKit facility is reached by message
  send.

---

### 1. `-[CirrusLogicGD5434DisplayDriver initFromDeviceDescription:]` — 0, 553 bytes

The driver's entry point and the only caller of most of the rest.

```c
- initFromDeviceDescription:deviceDescription
{
    if (![super initFromDeviceDescription:deviceDescription]) {
        [super free];
        return nil;                       /* returns [super free]'s value */
    }
    if (![self determineConfiguration])
        goto fail;                        /* determineConfiguration already logged */

    if (self->busType == 1)               /* PCI */
        if (![self setPCIConfiguration])
            goto fail;                    /* setPCIConfiguration already logged */

    mode = [self selectMode];
    if (mode >= 0 && ![self setPendingDisplayMode:mode]) {
        IOLog("%s: Selected mode not supported.\n", [self name]);
        mode = -1;
    }
    if (mode < 0) {
        IOLog("%s: Trying default mode.\n", [self name]);
        mode = self->defaultMode;
        if (![self setPendingDisplayMode:mode]) {
            IOLog("%s: Default mode not supported!\n", [self name]);
            goto fail;
        }
    }

    self->physicalAddress = [deviceDescription memoryRangeList][0].start;
    self->vram = [self mapFrameBufferAtPhysicalAddress:self->physicalAddress
                                                length:self->installedVRAMBytes];
    if (self->vram == 0) {
        IOLog("%s: Unable to map frame buffer\n", [self name]);
        goto fail;
    }

    self->blueTransferTable  = 0;
    self->greenTransferTable = 0;
    self->redTransferTable   = 0;
    self->transferTableCount = 0;
    self->brightnessLevel    = 64;                  /* EV_SCREEN_MAX_BRIGHTNESS */

    displayInfo = [self displayInfo];
    *displayInfo = self->modeTable[mode];           /* rep movsd, ecx = 34 */
    displayInfo->frameBuffer = self->vram;
    displayInfo->flags = (displayInfo->bitsPerPixel == IO_8BitsPerPixel)
                       ? IO_DISPLAY_HAS_TRANSFER_TABLE            /* 0x10 */
                       : IO_DISPLAY_NEEDS_SOFTWARE_GAMMA_CORRECTION; /* 0x02 */
    self->currentMode = 0;
    return self;

fail:
    [super free];
    return nil;
}
```

- **DriverKit calls:** `objc_msgSendSuper` to `initFromDeviceDescription:` and
  `free`; `objc_msgSend` to `determineConfiguration`, `setPCIConfiguration`,
  `selectMode`, `setPendingDisplayMode:` (twice), `name` (four times),
  `memoryRangeList`, `mapFrameBufferAtPhysicalAddress:length:` and `displayInfo`.
  `_IOLog` three call sites.
- **I/O ports:** none. **PCI config registers:** none directly.
- **Callers:** none in this binary; invoked by `IODevice`'s probe machinery.
  **Callees:** all of the above by message send; no direct call to any function
  in this binary.
- **`__const`/`__data` read:** none directly. It reads `self->modeTable`, which
  `determineConfiguration` has already pointed at `_GD5434_modeTable` or
  `_GD5446_modeTable`.
- The copy at 483–495 is `cld; rep movsd` with `ecx = 0x22` — 34 dwords, 136
  bytes, one whole `IODisplayInfo`. The index arithmetic is `mode*16 + mode`
  then `<< 3`, i.e. `mode * 136`.
- The "Default mode not supported!" path and the "Unable to map frame buffer"
  path share a single `call _IOLog` at 366 by tail-merging; that is a compiler
  artefact, not two call sites.
- **Inference:** the `goto fail` shape is inferred from three separate branches
  converging on the same `[super free]` at 371. The source may equally have
  written the `[super free]; return nil` out longhand in each arm; the emitted
  code cannot distinguish those.
- **Observation, not inference:** the failure return value is whatever
  `[super free]` returned, not a literal `nil` — `eax` is not zeroed after the
  super-send on any of these paths.

### 2. `-[CirrusLogicGD5434DisplayDriver selectMode]` — 556, 154 bytes

Builds a validity vector and hands it to `IOFrameBufferDisplay`.

```c
- (int)selectMode
{
    BOOL valid[self->modeTableCount];         /* alloca, rounded up to 4 bytes */

    for (i = 0; i < self->modeTableCount; i++)
        valid[i] = (self->installedVRAMBytes >=
                    self->modeTable[i].rowBytes * self->modeTable[i].height);

    mode = [self selectMode:self->modeTable
                     count:self->modeTableCount
                     valid:valid];
    if (mode < 0)
        IOLog("%s: Selected mode not supported.\n", [self name]);
    return mode;
}
```

- The stack array is a genuine variable-length array: `eax = modeTableCount + 3;
  al &= 0xFC; sub esp, eax`, then `esi = esp`. The rounding is to 4 bytes.
- `setnb` makes the comparison **unsigned** — `installedVRAMBytes` is `unsigned
  int`, and the product is treated the same way.
- **DriverKit calls:** `objc_msgSend` to `selectMode:count:valid:` (the
  three-argument `IOFrameBufferDisplay` variant, not the four-argument
  `modeString:` one) and to `name`; `_IOLog` once.
- **I/O ports:** none. **PCI:** none.
- **Callers:** `initFromDeviceDescription:`. **Callees:** none in this binary.
- **`__const`/`__data` read:** the mode table indirectly, through
  `self->modeTable`.
- Note this method logs `%s: Selected mode not supported.\n` **and** its caller
  logs the same string when `setPendingDisplayMode:` then refuses the mode, so
  the message can appear twice for one boot. That is the reference's behaviour;
  reproduce it.

### 3. `-[CirrusLogicGD5434DisplayDriver enterLinearMode]` — 712, 89 bytes

```c
- (void)enterLinearMode
{
    if (self->currentMode == 1)
        return;                                  /* already linear */
    self->currentMode = 1;
    [self setMode:[self displayInfo]->parameters];
    [self clearScreen];
    [self setGammaTable];
}
```

- `[eax+0x64]` is offset 100 of `IODisplayInfo`, the `void *parameters` field —
  which the mode tables point at the 70-byte register struct. So the mode
  programmed is the one belonging to the currently selected `IODisplayInfo`.
- **The order is load-bearing**: set the guard first, program registers, clear the
  frame buffer, then load the DAC. Clearing before the gamma load means the
  screen is blanked while the palette is still the old one.
- **DriverKit calls:** `objc_msgSend` to `displayInfo`, `setMode:`, `clearScreen`,
  `setGammaTable`. **I/O ports:** none directly. **PCI:** none.
- **Callers:** none in this binary; called by the window server through
  `IOFrameBufferDisplay`. **Callees:** `setMode:`, `clearScreen`, `setGammaTable`
  by message send.

### 4. `-[CirrusLogicGD5434DisplayDriver revertToVGAMode]` — 804, 86 bytes

```c
- (void)revertToVGAMode
{
    self->currentMode = 2;
    [self clearScreen];
    [self setMode:&_vgaMode];
    [super revertToVGAMode];
}
```

- Unlike `enterLinearMode` this has **no guard** — it runs unconditionally, even
  if `currentMode` is already 2.
- It clears the screen **before** programming registers, the opposite order to
  `enterLinearMode`. The `clearScreen` `bzero` therefore still runs against the
  linear-mode frame-buffer mapping, which is the only order that makes sense
  since the VGA mode does not have one.
- **`__const` read:** `_vgaMode` at 5232 — its only reference in the binary.
- **DriverKit calls:** `objc_msgSend` to `clearScreen` and `setMode:`;
  `objc_msgSendSuper` to `revertToVGAMode`.
- **I/O ports:** none directly, all via `setMode:`. **PCI:** none.
- **Callers:** none in this binary. **Callees:** `clearScreen`, `setMode:`, and
  `IOFrameBufferDisplay`'s `revertToVGAMode`.

### 5. `-[CirrusLogicGD5434DisplayDriver determineConfiguration]` — 892, 766 bytes

Chip detection, memory sizing, mode-table selection and per-mode validation. One
of the two functions carrying most of the risk in this reconstruction.

```c
- (BOOL)determineConfiguration
{
    /* 1. Presence test: unlock the Cirrus extensions and read the key back. */
    outw(0x3C4, 0xFA06);                 /* SR06 = 0xFA */
    if (inw(0x3C4) != 0x1206) {          /* AL = index 0x06, AH = data 0x12 */
        IOLog("%s: Cirrus Logic CL-GD543X or CL-GD5446 not found\n", [self name]);
        return NO;
    }

    /* 2. Chip identification: CR27, top six bits. */
    outb(0x3D4, 0x27);
    switch (inb(0x3D5) & 0xFC) {
    case 0xA0: self->chipType = 0; chipName = "Cirrus Logic GD5430"; break;
    case 0xA8: self->chipType = 1; chipName = "Cirrus Logic GD5434"; break;
    case 0xAC: self->chipType = 2; chipName = "Cirrus Logic GD5436"; break;
    case 0xB8: self->chipType = 3; chipName = "Cirrus Logic GD5446"; break;
    default:   self->chipType = 4; chipName = "Unknown device";      break;
    }

    /* 3. Mode table selection. */
    if (self->chipType <= 1) {                       /* GD5430, GD5434 */
        self->modeTable      = _GD5434_modeTable;
        self->modeTableCount = _GD5434_modeTableCount;   /* 24 */
        self->defaultMode    = _GD5434_defaultMode;      /* 4  */
    } else if (self->chipType <= 4) {                /* GD5436, GD5446 */
        self->modeTable      = _GD5446_modeTable;
        self->modeTableCount = _GD5446_modeTableCount;   /* 28 */
        self->defaultMode    = _GD5446_defaultMode;      /* 8  */
    }

    /* 4. Memory sizing: SR15 low nibble. */
    outb(0x3C4, 0x15);
    self->installedVRAMBytes = 0x40000 << (inb(0x3C5) & 0x0F);

    IOLog("%s: %s detected (%d Bytes)\n", [self name], chipName,
          self->installedVRAMBytes);

    /* 5. Bus type from the config table. */
    self->busType = (strncmp([[[self deviceDescription] configTable]
                                valueForStringKey:"Bus Type"], "PCI", 4) == 0);

    /* 6. Per-mode resource computation and validation. */
    for (i = 0; i < self->modeTableCount; i++) {
        IODisplayInfo *m = &self->modeTable[i];
        m->memorySize   = m->rowBytes * m->height;
        m->scanRate     = 0;
        m->screenWidth  = 0;
        m->screenHeight = 0;
        m->modeUnavailableFlag = 0;
        if (m->width > 1024 && self->installedVRAMBytes <= 0x1FFFFF)
            m->modeUnavailableFlag = IO_DISPLAY_MODE_OTHER_INVALID;      /* 16 */
        if (self->installedVRAMBytes < m->memorySize)
            m->modeUnavailableFlag = IO_DISPLAY_MODE_NEEDS_MORE_MEMORY;  /*  2 */
    }
    return YES;
}
```

**I/O ports touched, in order:** `0x3C4` word write (SR06 unlock), `0x3C4` word
read, `0x3D4` byte write / `0x3D5` byte read (CR27), `0x3C4` byte write /
`0x3C5` byte read (SR15). Nothing else.

**PCI config registers:** none. The bus type is a *string* read from the driver's
config table, not a PCI probe.

**Callers:** `initFromDeviceDescription:`. **Callees:** none in this binary; by
message send, `name` (twice), `deviceDescription`, `configTable`,
`valueForStringKey:`; `_IOLog` twice.

**`__const`/`__data` read:** `_GD5434_modeTableCount` (6708),
`_GD5434_defaultMode` (6704), `_GD5446_modeTableCount` (7348),
`_GD5446_defaultMode` (7344); the addresses of `_GD5434_modeTable` (8192) and
`_GD5446_modeTable` (11456); and the five chip-name strings plus `Bus Type` and
`PCI`. It **writes** five fields of every entry of whichever mode table it chose.

Points the rewrite must not smooth over:

- **The unknown-device case still gets the GD5446 table, and the guard against
  that is dead.** The dispatch is `cmp ecx,1 / ja` then `cmp ecx,4 / ja`, and the
  second `ja` jumps *past* the assignment block to the memory-sizing code,
  leaving `modeTable`, `modeTableCount` and `defaultMode` at whatever they
  already were. But `chipType` was just set to at most 4, and `ja 4` is false for
  4, so that escape is never taken — `chipType == 4` falls into the GD5446
  branch. The rewrite should reproduce the comparison as written
  (`> 1` then `> 4`) rather than "simplify" it to an `else`, because the two are
  observationally identical only as long as `chipType` stays within 0…4.
  **Inference:** the `<= 4` bound reads like defensive coding against a chipType
  enum that once had more members.
- **The two `modeUnavailableFlag` assignments are sequential, not exclusive.** A
  1280×1024 mode on a 1-MB card gets flag 16 from the first test and then flag 2
  from the second, and 2 is what survives. Do not turn this into `else if` and do
  not `|=` them.
- **`determineConfiguration` returns `YES` even when the chip is unknown.** Only
  the SR06 key check can make it return `NO`.
- **The `strncmp` is inlined** as `mov ecx,4; cld; repe cmpsb`, comparing four
  bytes — `"PCI"` plus its terminator — so a config value of `PCIX` does not
  match. The `test al,0` immediately before is the compiler's way of forcing
  `ZF = 1` before `repe`; it is not a meaningful test.
- **Inference:** `0x40000 << n` is 256 KB scaled by SR15's low nibble, giving
  1 MB at `n = 2` and 4 MB at `n = 4`. The shift is a plain `shl esi, cl` with no
  range clamp, so an SR15 low nibble above 13 would overflow `installedVRAMBytes`
  to 0. No hardware produces that; recorded for completeness only.

### 6. `-[CirrusLogicGD5434DisplayDriver isValidPCIAssignedBaseAddress:]` — 1660, 29 bytes

```c
- (BOOL)isValidPCIAssignedBaseAddress:(unsigned int)address
{
    return (address > 0x7FFFFF);
}
```

- Unsigned comparison (`ja`). Returns `YES` for any address at or above 8 MB,
  which rejects a base address the BIOS left inside the low 8 MB where main
  memory lives.
- **I/O ports:** none. **PCI:** none — despite the name, this inspects a value
  its caller already read.
- **Callers:** `setPCIConfiguration`. **Callees:** none.
- **`__const`/`__data`:** none.

### 7. `-[CirrusLogicGD5434DisplayDriver setPCIConfiguration]` — 1692, 583 bytes

```c
- (BOOL)setPCIConfiguration
{
    IOPCIConfigSpace config;               /* 256 bytes on the stack */
    IORange ranges[3];                     /* 24 bytes on the stack */
    unsigned char dev, func, bus;

    dd = [self deviceDescription];
    if ([dd getPCIdevice:&dev function:&func bus:&bus] != 0) {
        IOLog("%s: unsupported PCI hardware.", [self name]);
        return NO;
    }
    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", [self name], dev, func, bus);

    [self getPCIConfigSpace:&config];
    self->physicalAddress = config.BaseAddress[0];
    self->physicalAddress &= ~0x0F;                  /* and dl, 0xF0 */

    if ([self isValidPCIAssignedBaseAddress:self->physicalAddress]) {
        list = [dd memoryRangeList];
        n    = [dd numMemoryRanges];
        if (n != 3) {
            IOLog("%s: Incorrect number of address ranges: %d.\n", [self name], n);
            return NO;
        }
        for (i = 0; i < n; i++) ranges[i] = list[i];
        ranges[0].start = self->physicalAddress;
        if ([dd setMemoryRangeList:ranges num:3] == 0)
            return YES;                              /* IO_R_SUCCESS */

        IOLog("%s: Can't set memory range, using default.\n", [self name]);
        for (i = 0; i < n; i++) ranges[i] = list[i];   /* restore BIOS ranges */
        self->physicalAddress = ranges[0].start;
        if ([dd setMemoryRangeList:ranges num:3] == 0)
            return YES;
        IOLog("%s: Can't set to default range either!\n", [self name]);
        return NO;
    }

    /* Base address the BIOS assigned is unusable: fall back to the
     * device description's own first range and write it back to config space. */
    self->physicalAddress   = [dd memoryRangeList][0].start;
    config.BaseAddress[0]   = self->physicalAddress;
    [self setPCIConfigSpace:&config];
    return YES;
}
```

- The stack frame is `0x120` bytes: a 256-byte PCI config-space image at
  `var_118`, the three-entry `IORange` array at `var_18`, and the three
  device/function/bus bytes at `var_119`/`var_11A`/`var_11B`.
- **The config-space offset used is `var_108`, i.e. 16 bytes into the image** —
  PCI configuration register `0x10`, `BaseAddress[0]`, the frame-buffer BAR. That
  is the only PCI config register this driver reads or writes.
- The mask is applied to the low byte only (`and dl, 0F0h`), clearing the BAR's
  four type bits and leaving bits 4–31.
- **The retry path re-copies the ranges from `list` rather than patching the
  array it already has.** After `Can't set memory range, using default.` the
  loop at 2074–2098 reloads all `n` entries from `[dd memoryRangeList]`, which
  discards the `ranges[0].start = self->physicalAddress` the first attempt made,
  and then sets `self->physicalAddress` *from* `ranges[0].start` — i.e. the
  driver adopts the BIOS-assigned base it had been trying to replace. That is the
  intended meaning of "using default"; the ivar assignment at 2103 is what makes
  the fallback stick, and it must not be dropped as redundant.
- **Both DriverKit calls use the `IOReturn` convention: zero is success.**
  `test eax,eax; jz` jumps to `mov eax,1` at 2257 (return `YES`); a nonzero
  return falls through to the failure log. This matches
  `getPCIdevice:function:bus:` at 1769, which is also `jz` to the success path.
  Verified on both `setMemoryRangeList:num:` call sites, 2037 and 2137.
- **DriverKit calls:** `deviceDescription`, `getPCIdevice:function:bus:`, `name`
  (five times), `getPCIConfigSpace:`, `isValidPCIAssignedBaseAddress:`,
  `memoryRangeList` (twice), `numMemoryRanges`, `setMemoryRangeList:num:`
  (twice), `setPCIConfigSpace:`; `_IOLog` four call sites.
- **I/O ports:** none. **Callers:** `initFromDeviceDescription:`, only when
  `busType == 1`. **Callees:** `isValidPCIAssignedBaseAddress:` by message send.
- **`__const`/`__data` read:** the five log strings; no table.

### 8. `-[CirrusLogicGD5434DisplayDriver setMode:]` — 2276, 1020 bytes

The largest function and the one whose **write order is load-bearing**. It takes
the 70-byte register struct documented above and programs the VGA register files
plus the Cirrus extensions. It calls nothing and reads no `__const` or `__data`
symbol — every byte it writes comes from its argument or is an immediate.

**Ordered sequence, exactly as emitted.** `m` is the argument.

| # | Addr | Operation |
| --- | --- | --- |
| 1 | 2287 | `inb(0x3DA)` — reset the attribute controller flip-flop |
| 2 | 2293 | `outb(0x3C0, 0x00)` — attribute index 0, palette-address source clear: **video off** |
| 3 | 2308 | loop `i = 1…4`: `outw(0x3C4, (m->seq[i-1] << 8) \| i)` — SR01, SR02, SR03, SR04 |
| 4 | 2346 | `outw(0x3C4, 0x0300)` — SR00 = 0x03, end sequencer reset |
| 5 | 2360 | `outb(0x3C2, m->misc)` — Miscellaneous Output |
| 6 | 2377 | `outb(0x3D4, 0x11)`; `inb(0x3D5)`; `outb(0x3D5, value & 0x7F)` — clear CR11 bit 7, **unlocking CR00–CR07** |
| 7 | 2413 | loop `i = 0…24`: `outw(0x3D4, (m->crtc[i] << 8) \| i)` — CR00 … CR18 |
| 8 | 2450 | `inb(0x3DA)` — reset the flip-flop again |
| 9 | 2461 | loop `i = 0…20`: `outb(0x3C0, i)` then `outb(0x3C0, m->attr[i])` — AR00 … AR14 |
| 10 | 2499 | loop `i = 0…8`: `outw(0x3CE, (m->gfx[i] << 8) \| i)` — GR00 … GR08 |
| 11 | 2534 | `outw(0x3C4, 0x4A0B)` — SR0B = 0x4A |
| 12 | 2553 | `outw(0x3C4, 0x2B1B)` — SR1B = 0x2B |
| 13 | 2567 | `outw(0x3C4, 0x5B0C)` — SR0C = 0x5B |
| 14 | 2581 | `outw(0x3C4, 0x2F1C)` — SR1C = 0x2F |
| 15 | 2595 | `outw(0x3C4, 0x420D)` — SR0D = 0x42 |
| 16 | 2609 | `outw(0x3C4, 0x1F1D)` — SR1D = 0x1F |
| 17 | 2623 | `outw(0x3C4, (m[60] << 8) \| 0x07)` — SR07 |
| 18 | 2651 | `outb(0x3C4, 0x0F)`; `inb(0x3C5)`; `outb(0x3C5, (v & 0x9F) \| m[61])` — SR0F |
| 19 | 2685 | **if `m[62] != 0`**: `outw(0x3C4, (m[62] << 8) \| 0x0E)` — SR0E; then `outw(0x3C4, (m[63] << 8) \| 0x1E)` — SR1E |
| 20 | 2732 | `outb(0x3CE, 0x0B)`; `inb(0x3CF)`; `outb(0x3CF, (v & 0xC0) \| m[64])` — GR0B |
| 21 | 2771 | `outw(0x3D4, (m[65] << 8) \| 0x1A)` — CR1A |
| 22 | 2799 | `outw(0x3D4, (m[66] << 8) \| 0x1B)` — CR1B |
| 23 | 2822 | `outb(0x3C4, 0x0F)`; `inb(0x3C5)`; **test bit 2** |
| 24 | 2850 / 2884 | `outb(0x3C4, 0x16)`; `inb(0x3C5)`; `outb(0x3C5, (v & 0xF0) \| (sel & 0x0F))` where `sel` is `m[67]` if SR0F bit 2 was set, else `m[68]` — SR16 |
| 25 | 2933 | `outb(0x3C6, 0x00)` |
| 26 | 2948 | `inb(0x3C6)` **four times** |
| 27 | 2952 | `outb(0x3C6, m[69])` — the Cirrus **hidden DAC register** |
| 28 | 2965 | `outb(0x3C6, 0xFF)` — restore the PEL mask |
| 29 | 2975 | `outb(0x3C4, 0x17)`; `inb(0x3C5)`; `outb(0x3C5, v & 0xFB)` — SR17 bit 2 clear |
| 30 | 3011 | `outw(0x3CE, 0x000F)` — GR0F = 0 |
| 31 | 3030 | `outw(0x3D4, 0x001C)` — CR1C = 0 |
| 32 | 3049 | `outw(0x3D4, 0x001D)` — CR1D = 0 |
| 33 | 3063 | `outw(0x3C4, 0x0010)` — SR10 = 0 |
| 34 | 3082 | `outw(0x3C4, 0x0011)` — SR11 = 0 |
| 35 | 3096 | `outw(0x3C4, 0x0012)` — SR12 = 0 |
| 36 | 3110 | `outw(0x3C4, 0x0013)` — SR13 = 0 |
| 37 | 3124 | `outw(0x3CE, 0x0009)` — GR09 = 0 |
| 38 | 3143 | `outw(0x3CE, 0x000A)` — GR0A = 0 |
| 39 | 3157 | `outb(0x3CE, 0x0B)`; `inb(0x3CF)`; `outb(0x3CF, v & 0xFE)` — GR0B bit 0 clear |
| 40 | 3188 | **if `m[62] != 0`**: `outb(0x3C4, 0x07)`; `inb(0x3C5)`; `outb(0x3C5, v \| 0x10)` — SR07 bit 4 set |
| 41 | 3230 | `inb(0x3DA)`; `outb(0x3C0, 0x20)` — palette-address source set: **video on** |
| 42 | 3251 | `outb(0x3C4, 0x01)`; `inb(0x3C5)`; `outb(0x3C5, v & 0xDF)` — SR01 bit 5 clear: **screen unblanked** |

Notes the rewrite must honour:

- **Steps 2 and 41/42 bracket the whole sequence.** The attribute controller is
  put into "video off" before any register file is touched and restored last,
  with the sequencer's screen-off bit cleared after that. Reordering the ends
  produces visible garbage during a mode switch.
- **Step 6 must precede step 7.** CR00–CR07 are write-protected until CR11 bit 7
  is cleared, so writing the CRTC array first would silently drop the first eight
  registers.
- **Steps 11–16 are unconditional immediates**, not table data. They are the
  VCLK numerator/denominator pairs — SR0B/SR1B, SR0C/SR1C, SR0D/SR1D — programmed
  identically for every mode. **Inference:** these set up VCLK0–VCLK2 as a fixed
  set of standard frequencies; the per-mode clock choice is then made by
  `m->misc` bits 2–3 (step 5) and by the SR0E/SR1E pair in step 19. The naming is
  inferred from the Cirrus register map, not from anything in the binary.
- **`m[62]` is consulted twice**, at step 19 and again at step 40, and both are
  skipped when it is zero. `_vgaMode` has it zero and every accelerated mode has
  it non-zero, so it behaves as an "extended mode" flag as well as the SR0E value.
- **Step 26's four `inb(0x3C6)` are mandatory.** The Cirrus hidden DAC register
  is reached by reading the PEL mask register four times in a row and then
  writing it; a compiler is free to delete reads whose values are unused, which
  is exactly why they are `inb()` calls from `ioPorts.h` with `asm volatile`
  rather than plain dereferences. Do not let them be optimised away, and do not
  insert anything between them.
- **Step 25's `outb(0x3C6, 0)` before the four reads is unusual** — the canonical
  sequence is four reads then the write. It is recorded here as observed. **This
  is an observation; the reason is not recoverable from the binary.**
- Steps 30–38 zero the Cirrus BitBLT and cursor/overlay registers, and step 39
  disables the extended write mode. **Inference:** this is a reset of the
  acceleration engine, not part of the timing setup.

**I/O ports touched:** `0x3C0`, `0x3C2`, `0x3C4`, `0x3C5`, `0x3C6`, `0x3CE`,
`0x3CF`, `0x3D4`, `0x3D5`, `0x3DA`. **PCI config registers:** none.
**Callers:** `enterLinearMode` and `revertToVGAMode`, both by message send.
**Callees:** none. **`__const`/`__data` read:** none by symbol; its data all
arrives through the argument.

### 9. `-[CirrusLogicGD5434DisplayDriver clearScreen]` — 3296, 29 bytes

```c
- (void)clearScreen
{
    bzero(self->vram, self->installedVRAMBytes);
}
```

- Zeroes the **whole** mapped aperture, not just the visible frame.
- **DriverKit calls:** `_bzero` (a direct call, not a message send).
- **I/O ports:** none. **PCI:** none.
- **Callers:** `enterLinearMode`, `revertToVGAMode`. **Callees:** `_bzero`.
- **`__const`/`__data`:** none.

### 10. `-[CirrusLogicGD5434DisplayDriver name]` — 3328, 59 bytes

```c
- (const char *)name
{
    const char *n = [super name];
    if (n == NULL || *n == '\0')
        return "CirrusLogicGD5434DisplayDriver";
    return n;
}
```

- Both the NULL check and the empty-string check are present; the literal is
  loaded into `edx` *before* the test and overwritten only if the super's answer
  is usable.
- **`__const` read:** the string at 4893, which is its only reference.
- **DriverKit calls:** `objc_msgSendSuper` to `name`.
- **Callers:** `initFromDeviceDescription:`, `selectMode`,
  `determineConfiguration`, `setPCIConfiguration`, `setBrightness:token:` —
  every `IOLog` call site in the binary.
- **Callees:** none in this binary.

### 11. `-[CirrusLogicGD5434DisplayDriver setPendingDisplayMode:]` — 3388, 140 bytes

```c
- (BOOL)setPendingDisplayMode:(int)mode
{
    if (mode < 0 || mode >= self->modeTableCount)
        return NO;
    if (self->modeTable[mode].memorySize > self->installedVRAMBytes)
        return NO;
    if (self->modeTable[mode].width > 1024 &&
        self->installedVRAMBytes <= 0x1FFFFF)
        return NO;
    return [super setPendingDisplayMode:mode];
}
```

- The `memorySize` comparison is `ja`, i.e. **unsigned strictly-greater**, so a
  mode needing exactly the installed VRAM is accepted.
- The 1024/2 MB test duplicates `determineConfiguration`'s, deliberately: this
  method is reachable from outside without `determineConfiguration` having run
  again.
- `memorySize` is read from `+0x68` of the entry, which only has a meaningful
  value because `determineConfiguration` computed it. **Inference:** calling this
  before `determineConfiguration` would compare against 0 and pass everything.
- **DriverKit calls:** `objc_msgSendSuper` to `setPendingDisplayMode:`.
- **I/O ports:** none. **PCI:** none.
- **Callers:** `initFromDeviceDescription:`, twice. **Callees:** super only.
- **`__const`/`__data` read:** the selected mode table, indirectly.

### 12. `-[CirrusLogicGD5434DisplayDriver displayModeCount]` — 3528, 16 bytes

```c
- (unsigned int)displayModeCount { return self->modeTableCount; }
```

Pure accessor. No ports, no PCI, no calls, no `__const`/`__data` symbol.
**Callers:** none in this binary; `IOFrameBufferDisplay` calls it.

### 13. `-[CirrusLogicGD5434DisplayDriver displayModes]` — 3544, 16 bytes

```c
- (IODisplayInfo *)displayModes { return self->modeTable; }
```

Pure accessor, returning the mutable table itself rather than a copy. No ports,
no PCI, no calls. **Callers:** none in this binary.

### 14. `-[CirrusLogicGD5434DisplayDriver displayMemorySize]` — 3560, 16 bytes

```c
- (unsigned int)displayMemorySize { return self->installedVRAMBytes; }
```

Pure accessor. No ports, no PCI, no calls. **Callers:** none in this binary.

### 15. `-[CirrusLogicGD5434DisplayDriver ramdacSpeed]` — 3576, 9 bytes

```c
- (unsigned int)ramdacSpeed { return 0; }
```

- The smallest function in the binary, and the only one with no `sub esp` at all.
  It returns a constant zero, so the driver declares no RAMDAC speed limit and
  `IOFrameBufferDisplay` will never mark a mode `IO_DISPLAY_MODE_SLOW_RAMDAC` on
  its behalf.
- No ports, no PCI, no calls, no `__const`/`__data`. **Callers:** none in this
  binary.

### 16. `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setTransferTable:count:]` — 3588, 333 bytes

The source map and IDA both spell this
`-[CirrusLogicGD5434DisplayDriver setTransferTable:count:]`, without the category
qualifier; the Mach-O symbol table includes it. Same function, address 3588.

First function of `ProgramDAC.m`.

```c
- setTransferTable:(const unsigned int *)table count:(int)count
{
    if (self->redTransferTable == NULL || self->transferTableCount != count) {
        if (self->redTransferTable != NULL)
            IOFree(self->redTransferTable, self->transferTableCount * 3);
        self->transferTableCount = count;
        self->redTransferTable   = IOMalloc(count * 3);
        self->greenTransferTable = self->redTransferTable + count;
        self->blueTransferTable  = count + self->greenTransferTable;
    }

    switch ([self displayInfo]->colorSpace) {
    case IO_OneIsWhiteColorSpace:                  /* 1 */
        for (i = 0; i < count; i++) {
            unsigned char v = (unsigned char)table[i];   /* low byte */
            self->blueTransferTable[i]  = v;
            self->greenTransferTable[i] = v;
            self->redTransferTable[i]   = v;
        }
        break;
    case IO_RGBColorSpace:                         /* 2 */
        for (i = 0; i < count; i++) {
            self->redTransferTable[i]   = table[i] >> 24;
            self->greenTransferTable[i] = table[i] >> 16;
            self->blueTransferTable[i]  = table[i] >>  8;
        }
        break;
    default:
        IOFree(self->redTransferTable, count * 3);
        self->redTransferTable = NULL;
        break;
    }

    [self setGammaTable];
    return self;
}
```

- **One allocation of `3 * count` bytes serves all three tables**, carved into
  three consecutive runs. `IOFree` is therefore called with `3 * count`, never
  with `count`.
- The reallocation is skipped entirely when the count is unchanged and a table
  already exists — the guard is `redTransferTable == NULL || transferTableCount
  != count`, evaluated as two branches at 3600 and 3612.
- The dispatch reads `[eax+0x1C]`, offset 28 of `IODisplayInfo` — `colorSpace`,
  not `bitsPerPixel`. `setGammaTable` (finding 19) dispatches on `bitsPerPixel`
  instead. That asymmetry is real.
- **The default arm frees the table and sets `redTransferTable` to NULL but
  leaves `greenTransferTable`, `blueTransferTable` and `transferTableCount`
  stale**, pointing into freed memory. Nothing dereferences them afterwards
  because every reader gates on `redTransferTable != NULL`, so it is latent
  rather than live. Reproduce as written; it is Apple's.
- Packed RGBM is unpacked most-significant-byte-first: red from bits 31–24,
  green 23–16, blue 15–8, matching `displayDefs.h`'s comment that colour
  displays use the high three bytes.
- **DriverKit calls:** `_IOFree` (twice), `_IOMalloc`, `objc_msgSend` to
  `displayInfo` and `setGammaTable`.
- **I/O ports:** none directly. **PCI:** none.
- **Callers:** none in this binary; `IOFrameBufferDisplay` forwards
  `IODISPLAY_SET_TRANSFER_TABLE`. **Callees:** `setGammaTable` by message send.
- **`__const`/`__data`:** none.

### 17. `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setBrightness:token:]` — 3924, 77 bytes

Spelled `-[CirrusLogicGD5434DisplayDriver setBrightness:token:]` in the source map.

```c
- setBrightness:(int)level token:(int)token
{
    if ((unsigned)level > 64) {
        IOLog("%s: Invalid brightness level `%d'\n", [self name], level);
        return nil;
    }
    self->brightnessLevel = level;
    [self setGammaTable];
    return self;
}
```

- The bound is `ja 0x40` — **unsigned**, so a negative level is rejected by the
  same test. 64 is `EV_SCREEN_MAX_BRIGHTNESS`.
- **`token` is accepted and never used.** No instruction reads `arg_C`.
- Returns `nil` on rejection and `self` on success.
- **`__const` read:** the string at 4924.
- **DriverKit calls:** `objc_msgSend` to `name` and `setGammaTable`; `_IOLog`.
- **I/O ports:** none directly. **PCI:** none.
- **Callers:** none in this binary. **Callees:** `setGammaTable` by message send.

### 18. `_SetGammaValue` — 4004, 82 bytes

The only non-method function in the binary, and the only one called with a direct
`call` rather than a message send. `static` in `ProgramDAC.m` — it has a local
symbol-table entry and no external linkage.

```c
static void SetGammaValue(int red, int green, int blue, int brightness)
{
    outb(0x3C9, (red   * brightness) >> 8);
    outb(0x3C9, (green * brightness) >> 8);
    outb(0x3C9, (blue  * brightness) >> 8);
}
```

- Writes one RGB triple to the DAC data register. The DAC's write index is set
  once by the caller (`outb(0x3C8, 0)`) and auto-increments after every third
  write, so **these three writes must stay adjacent and in R, G, B order.**
- The scaling is a signed multiply (`imul`) followed by a **logical** right shift
  (`shr`), so a brightness of 64 yields a quarter-scale ramp — the DAC is 6-bit
  per channel on this part, and `(v * 64) >> 8` maps 0…255 onto 0…63 exactly.
  **Inference:** that is why 64 is both the default and the maximum brightness.
- Increments `_xxx.86` at 15276 — **ProgramDAC.m's** `outb` static, not the one
  `setMode:` uses. See the Static storage section.
- **I/O ports:** `0x3C9` only. **PCI:** none.
- **Callers:** `setGammaTable`, three call sites. **Callees:** none.
- **`__const`/`__data`:** none.

### 19. `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setGammaTable]` — 4088, 273 bytes

Spelled `-[CirrusLogicGD5434DisplayDriver setGammaTable]` in the source map.

```c
- setGammaTable
{
    IODisplayInfo *di = [self displayInfo];

    outb(0x3C8, 0);                              /* DAC write index = 0 */

    if (self->redTransferTable != NULL) {
        for (i = 0; i < self->transferTableCount; i++)
            for (j = 0; j < 256 / self->transferTableCount; j++)
                SetGammaValue(self->redTransferTable[i],
                              self->greenTransferTable[i],
                              self->blueTransferTable[i],
                              self->brightnessLevel);
    } else switch (di->bitsPerPixel) {
    case IO_8BitsPerPixel:                       /* 1 */
    case IO_24BitsPerPixel:                      /* 4 */
        for (i = 0; i <= 255; i++)
            SetGammaValue(_gamma8[i], _gamma8[i], _gamma8[i],
                          self->brightnessLevel);
        break;
    case IO_12BitsPerPixel:                      /* 2 */
    case IO_15BitsPerPixel:                      /* 3 */
        for (i = 0; i <= 15; i++)
            for (j = 0; j <= 15; j++)
                SetGammaValue(_gamma16[i], _gamma16[i], _gamma16[i],
                              self->brightnessLevel);
        break;
    default:                                     /* IO_2BitsPerPixel, IO_VGA */
        break;
    }
    return self;
}
```

- Every path writes exactly 256 DAC entries, or none. The 15/12-bit path writes
  each of the 16 `_gamma16` values sixteen times consecutively, so the DAC is
  filled with a 16-step ramp — correct for a mode where only the top bits of each
  channel index the palette.
- The transfer-table path expands a smaller client table the same way, repeating
  each entry `256 / transferTableCount` times. The division is **signed**
  (`cdq; idiv`) and is recomputed on every inner iteration.
- **`transferTableCount == 0` with a non-NULL `redTransferTable` would divide by
  zero.** The outer loop's `jbe` guard exits first when the count is zero, so the
  `idiv` is unreachable in that case. That is an observation about the emitted
  control flow, not an inference.
- The `bitsPerPixel` dispatch is a three-way compare chain — `> 3` then `>= 2`
  then `== 1`, with a separate `== 4` test on the high side — which is why 1 and
  4 share an arm and 2 and 3 share the other. `IO_2BitsPerPixel` (0) and `IO_VGA`
  (5) fall through and program nothing, leaving the DAC as `setMode:` left it.
- **`__const` read:** `_gamma8` (4976, 256 bytes) and `_gamma16` (4960, 16
  bytes). These are their only references. `_gamma16`'s bytes are
  `00 4A 66 7B 8C 9B A8 B4 C0 CA D4 DD E6 EF F7 FF` and `_gamma8` is a
  256-entry ramp beginning `00 0F 16 1B 1F 23 27 2A` and ending `FE FF`.
  **Inference:** both are gamma≈2.2 encoding ramps; the exponent was not derived.
- **DriverKit calls:** `objc_msgSend` to `displayInfo`.
- **I/O ports:** `0x3C8` directly, plus `0x3C9` through `_SetGammaValue`.
  **PCI:** none.
- **Callers:** `enterLinearMode`, `setTransferTable:count:`,
  `setBrightness:token:`. **Callees:** `_SetGammaValue`, by direct call, three
  sites.

### 20. `+[CirrusLogicGD5434DisplayDriverKernelServerInstance kernelServerInstance]` — 4364, 12 bytes

```c
+ kernelServerInstance { return &_CirrusLogicGD5434DisplayDriver_instance; }
```

- Build-generated by the Kernel Server project type; **must not be written by
  hand.** Returns the address of the 4-byte `__DATA,__common` symbol
  `_CirrusLogicGD5434DisplayDriver_instance` at 15288.
- No ports, no PCI, no calls. **Callers:** none in this binary — the kernel
  server loader sends it.

### 21. `+[CirrusLogicGD5434DisplayDriverVersion driverKitVersionForCirrusLogicGD5434DisplayDriver]` — 4376, 12 bytes

```c
+ (int)driverKitVersionForCirrusLogicGD5434DisplayDriver { return 500; }
```

- Build-generated. Returns the immediate `0x1F4` = 500, the DriverKit version the
  project declares.
- No ports, no PCI, no calls. **Callers:** none in this binary.

## Static storage

`__DATA,__bss` is 24 bytes at 15264 and holds **six** symbols, not three — the
symbol table carries `_xxx.86`, `_xxx.89` and `_xxx.92` **twice each**:

| Address | Symbol | Owning translation unit | Inline function | Referenced from |
| --- | --- | --- | --- | --- |
| 15264 | `_xxx.86` | `CirrusLogicGD5434DisplayDriver.m` | `outb()` | `determineConfiguration`, `setMode:` |
| 15268 | `_xxx.89` | `CirrusLogicGD5434DisplayDriver.m` | `outw()` | `determineConfiguration`, `setMode:` |
| 15272 | `_xxx.92` | `CirrusLogicGD5434DisplayDriver.m` | `outl()` | nothing |
| 15276 | `_xxx.86` | `ProgramDAC.m` | `outb()` | `_SetGammaValue`, `setGammaTable` |
| 15280 | `_xxx.89` | `ProgramDAC.m` | `outw()` | nothing |
| 15284 | `_xxx.92` | `ProgramDAC.m` | `outl()` | nothing |

These are the `static int xxx;` inside `outb()`, `outw()` and `outl()` in
`src/driverkit-3/driverkit/i386/ioPorts.h`, emitted once per translation unit
that includes the header. Two units include it, so there are two triples. IDA
disambiguates the second triple by suffixing its names — `_xxx_86_0` and so on —
which is a display artefact, not a difference in the binary.

The attribution is settled by the referencing instructions rather than by the
symbol order, and each is unambiguous:

- `setMode:` at 2301 emits `F0 FF 05 A0 3B 00 00`, i.e. `lock inc ds:0x3BA0` =
  **15264**, after `outb(0x3C0, 0)`; and at 2333 `lock inc ds:0x3BA4` = **15268**
  after `outw(0x3C4, …)`. So within the first unit, `.86` is `outb`'s and `.89`
  is `outw`'s.
- `_SetGammaValue` at 4032 emits `lock inc ds:0x3BAC` = **15276** after
  `outb(0x3C9, …)`. That address is in the second triple, and the instruction it
  follows is a byte `out`, so 15276 is `ProgramDAC.m`'s `outb` copy.

`_xxx.92` is never referenced from either unit and `ProgramDAC.m`'s `_xxx.89` is
never referenced either, because `outl()` is never called anywhere and `outw()`
is never called from `ProgramDAC.m` — that file's only port writes are the two
byte writes in `setGammaTable` and `_SetGammaValue`. gcc emits the statics
regardless, since the inline function bodies are instantiated per translation
unit.

**The suffix numbering corroborates the two-unit split.** gcc's private-name
counter rises monotonically within one compilation and restarts in the next, and
here the sequence is 86, 89, 92 followed by 86, 89, 92 — a restart, in exactly
the position `__OBJC,__module_info` puts the `ProgramDAC.m` boundary. The
identical numbers in both units follow from both units including the same header
at the same point relative to their own declarations. **This is corroboration of
a boundary already established by `__module_info`, not independent evidence.**

The remaining non-`__text` symbols:

| Symbol | Section | Address | Size | Role |
| --- | --- | --- | --- | --- |
| `_CirrusLogicGD5434DisplayDriver_instance` | `__DATA,__common` | 15288 | 4 | build-generated instance slot |
| `_gamma16` | `__TEXT,__const` | 4960 | 16 | 15/12-bpp gamma ramp |
| `_gamma8` | `__TEXT,__const` | 4976 | 256 | 8/24-bpp gamma ramp |
| `_vgaMode` | `__TEXT,__const` | 5232 | 70 | stock VGA register set |
| `_GD5434_mode_*` | `__TEXT,__const` | 5302–6702 | 20 × 70 | GD5434 register sets |
| `_GD5434_defaultMode` | `__TEXT,__const` | 6704 | 4 | 4 |
| `_GD5434_modeTableCount` | `__TEXT,__const` | 6708 | 4 | 24 |
| `_GD5446_mode_*` | `__TEXT,__const` | 6712–7342 | 9 × 70 | GD5446 register sets |
| `_GD5446_defaultMode` | `__TEXT,__const` | 7344 | 4 | 8 |
| `_GD5446_modeTableCount` | `__TEXT,__const` | 7348 | 4 | 28 |
| `_CirrusLogicGD5434DisplayDriver_VERS_STRING` | `__TEXT,__const` | 7352 | 160 | see below |
| `_CirrusLogicGD5434DisplayDriver_VERS_NUM` | `__TEXT,__const` | 7512 | 4 | 14641 |
| `_GD5434_modeTable` | `__DATA,__data` | 8192 | 3264 | 24 × `IODisplayInfo` |
| `_GD5446_modeTable` | `__DATA,__data` | 11456 | 3808 | 28 × `IODisplayInfo` |

`_CirrusLogicGD5434DisplayDriver_VERS_STRING` is

```
@(#)PROGRAM:CirrusLogicGD5434DisplayDriver  PROJECT:drvCirrusLogicGD5434-19  DEVELOPER:root  BUILT:Sat Mar 28 22:19:38 PST 1998
```

with a trailing newline. Both version symbols are build-generated and neither is
referenced by any function.

**Open question: the reference's `__TEXT,__const` is in the opposite object
order from every other section.** `kl_ld` is handed
`CirrusLogicGD5434DisplayDriver.o` before `ProgramDAC.o`, and in both the
reference and the rebuilt binary `__TEXT,__text`, `__TEXT,__cstring` and
`__DATA,__data` all follow that order. `__TEXT,__const` does not: in the
reference `_gamma16` and `_gamma8` — `ProgramDAC.m`'s constants — sit at 4960 and
4976, *ahead* of `_vgaMode` at 5232 and the whole `GD5434_mode_*` run, which come
from the main file. The rebuilt binary puts them where the link order says they
belong, `_vgaMode` first at 4348 and `_gamma16`/`_gamma8` last at 6468 and 6484.
No source-level change in either file reproduces the inversion — it is not a
matter of declaration order within a file, since each file's own constants stay
correctly ordered relative to each other on both sides — and its cause is not
recoverable from the binary. The practical consequence is that `__TEXT,__const`
addresses cannot be used as a parity criterion for this driver: every absolute
reference to a constant differs between the two binaries even where the
instruction stream is byte-identical, which is why the per-function comparison
below masks 32-bit relocation operands before comparing. Recorded as an open
question, not a defect.

The inversion is confined to `__TEXT,__const`; every other multi-unit section
keeps main-file-first order. `__TEXT,__text` runs 0–3588 for the main file, then
3588–4364 for `ProgramDAC.m` and 4364–4388 for
`CirrusLogicGD5434DisplayDriver_instance.m`; `__TEXT,__cstring` puts the main
file's nineteen strings at 4388–4923 ahead of `ProgramDAC.m`'s single string at
4924; `__DATA,__bss` puts the main file's `ioPorts.h` counter triple at
15264–15272 ahead of `ProgramDAC.m`'s at 15276–15284; and `__OBJC,__module_info`
names the units in that same order. The `__const` attributions themselves are
not in doubt, since all three symbols are local and each is reached only from
its own unit's text: `_gamma16` and `_gamma8` from 4278 and 4322 inside
`setGammaTable` (4088, `ProgramDAC.m`), `_vgaMode` from 838 inside
`revertToVGAMode` (804, main file). Because neither file's constants can be
reordered within that file to produce the observed interleaving, a rebuild
cannot reproduce the reference's `__const` layout by source reordering, and a
`__const` address-parity mismatch on these symbols must not be attributed to a
defect in `CirrusLogicGD5434DisplayDriver.m` or `ProgramDAC.m`.

## Build and parity

`vm/build-i386-video-recon.sh drvCirrusLogicGD5434`, run in the Rhapsody guest,
**succeeds on the first attempt with `make exit=0` and no compile errors**. This
was the first time any of these sources had been through a compiler; no source
change was needed to make them build. gcc emitted no warnings at all, including
none for the two deliberately dead mode structs `GD5434_mode_640_15_60` and
`GD5434_mode_640_15_75` — `-Wmost` as this compiler configures it does not imply
`-Wunused-variable` for file-scope statics, so their presence costs nothing.
`kl_ld` links `CirrusLogicGD5434DisplayDriver_reloc` as a `Mach-O preload
executable i386`.

`parity_check.py` against Apple's binary reports **0 missing strings and 0
missing `__TEXT,__text` symbols**. It reports 26 extras on our side, all of which
are debug artefacts of an unstripped guest build: the four source-file stabs, the
21 stab-typed duplicates of the real function symbols, and one empty name. No
reference method is misspelled and no reference function is unwritten.

The linkage check reports `linkage mismatches: []`. In particular `_SetGammaValue`
is `local` on both sides, so the `static` on it in `ProgramDAC.m` is correct, and
`_vgaMode`, `_GD5434_modeTable`, `_GD5446_modeTable` and the four
`defaultMode`/`modeTableCount` scalars are `external` on both sides.

Going past what `parity_check.py` can see, all 21 `__TEXT,__text` functions were
disassembled and compared against the reference individually. **17 of 21 are
byte-for-byte identical** once 32-bit relocation operands are masked — necessarily
masked, because of the `__TEXT,__const` inversion above. After replacing the
`"Bus Type"` `strncmp` with `strcmp` (see Task 1 result below), `__TEXT,__text`
is 4404 bytes against the reference's 4388, and the remaining 16-byte difference
is accounted for by three functions (`setMode:` 12 bytes smaller, `setPCIConfiguration`
28 bytes larger). `determineConfiguration` is now the same size as the reference
but still not byte-identical:

| Function | Ref | Rebuilt | Nature of the difference |
| --- | --- | --- | --- |
| `setMode:` | 1020 | 1008 | Identical branch structure and an identical port-I/O sequence of 67 `in`/`out` instructions. gcc strength-reduced the register loops to a walking pointer in the reference where our build uses indexed addressing. |
| `setPendingDisplayMode:` | 140 | 140 | Same size, same branches, same call target. The `memorySize` test is `cmp memorySize, installedVRAM / ja` in the reference and the operand-reversed `cmp installedVRAM, memorySize / jb` here — the same predicate — and one fewer callee-saved register is spilled. |
| `setPCIConfiguration` | 584 | 612 | The same 19 calls — 15 `_objc_msgSend` and 4 `_IOLog` — but reordered by block placement, not in the same order. The "Incorrect number of address ranges" error block is out of line at the end in the reference and inline here, which moves the `_IOLog` calls from reference positions 4, 11, 14, 16 to 4, 10, 13, 16 and pushes two `_objc_msgSend` calls one slot later (reference 10 and 13 against 11 and 14 here); the reference has 11 branch instructions to our 12. Also `IORange range[3]` is at `ebp-0x18` in the reference against `ebp-0x118` here, i.e. the two locals are assigned to the frame in the opposite order. |
| `determineConfiguration` | 768 | 768 | Same size after `strcmp`. Remaining DIFF is the two `chipType` `ja`/`jg` tests plus block placement. Not assembly-matched. |

**`determineConfiguration` still does not match byte for byte.** Before the
`strcmp` edit, two things differed. First, the reference expands the `"Bus Type"`
test inline as a `repe cmpsb` sequence while our build emitted `call
_strncmp`, so the ordered call-target lists differed by one entry — 7 calls in the
reference against 8 here. That call is gone: the source now uses `strcmp`, the
rebuilt extent has no `_strncmp` relocation, and the seven pc-relative call
targets are `_objc_msgSend`, `_IOLog`, `_objc_msgSend`, `_IOLog`, then three
`_objc_msgSend`. Second, the two `chipType` range tests are signed here
and unsigned in the reference: `cmp ecx, 1 / ja` and `cmp ecx, 4 / ja` at 1147
and 1184 in the reference against `cmp dword [esi+0x258], 1 / jg` and
`cmp dword [esi+0x258], 4 / jg` at 1135 and 1176 here. That is the whole of the
signedness divergence, and it is confined to those two branches. The extent
gap that remains is those `ja`/`jg` tests plus block placement.

The two other comparisons in this function that might look related are not
divergences of that kind. The `cmp dword [reg+0x228], 0x1fffff` guard is `ja` on
*both* sides — unsigned in the reference and unsigned here, identical. The
installed-VRAM-against-`memorySize` test is `cmp dword [edx+0x228], eax / jae` in
the reference and `cmp dword [ecx+edi+0x68], eax / jbe` here: `jbe` is the
unsigned below-or-equal branch, not a signed one, so both sides are unsigned and
the only difference is that the operands are reversed — the same pattern already
recorded for `setPendingDisplayMode:` above, and not a signedness question at
all. Counting all conditional branches, the reference has 14 and so do we.

Neither remaining difference changes behaviour: `chipType` only ever holds 0–4,
and both compare forms compute the same result.

### The `repe cmpsb` is gcc's `strcmp` builtin: the source said `strcmp`

**This supersedes the earlier note that the inline form "depends on compiler
flags that are not recoverable from the binary." It is recoverable, and it is
not a flag.** The construct is `strcmp`, not `strncmp`.

**Observation — the reference's sequence.** At `determineConfiguration` +459…+480
the reference reads

```
459  89C1        mov ecx, eax          ; the valueForStringKey: result
461  89CB        mov ebx, ecx
463  BF58120000  mov edi, 0x1258       ; -> "PCI"
468  B904000000  mov ecx, 4
473  89DE        mov esi, ebx
475  FC          cld
476  A800        test al, 0
478  F3A6        repe cmpsb
480  7512        jne …
```

The `cld` / `repz cmpsb` pair with the count in `ecx` and the two operands
forced into `esi`/`edi` is the i386 `cmpstrsi` expander. In gcc 2.x that
expander is reachable from three builtins — `memcmp`, `bcmp` and `strcmp` — and
**`strncmp` is not a builtin at all**, which is why our `strncmp` call survives
as a call.

**Observation — the count is `strlen(literal) + 1`, corpus-wide.** Scanning
every `_reloc` under `Drivers/i386` for `cmpsb` and correlating the `mov ecx,
imm` that feeds it against the string constant loaded into `esi`/`edi` gives,
among others:

| Driver | count | literal | `strlen + 1` |
| --- | --- | --- | --- |
| `ATIRageDisplayDriver` | 16 | `IODisplayDoBlit` | 16 |
| `ATIRageDisplayDriver` | 19 | `IOGetDisplaySynced` | 19 |
| `Adaptec2940SCSI` | 15 | `A2940_CmdQueue` | 15 |
| `Adaptec2940SCSI` | 11 | `A2940_Sync` | 11 |
| `DEC21X4XNetwork` | 21 | `DEC21X4X_GETLOCATION` | 21 |
| `Beep` | 10 | `Frequency` | 10 |
| `BusMouse` | 11 | `Resolution` | 11 |
| `CirrusLogicGD5434DisplayDriver` | 4 | `PCI` | 4 |

Eight different literals of six different lengths, and in every case the count
is exactly one more than the literal's length. A source-written length — which
is what `memcmp`, `bcmp` and `strncmp` all take — would not track `strlen + 1`
across unrelated drivers. **The compiler is computing the bound**, and
computing it as `c_strlen(constant) + 1` is precisely what gcc 2.x's
`BUILT_IN_STRCMP` case does before handing off to `cmpstrsi`. Our own `4` is
`sizeof("PCI")` by coincidence of that string's length; the corpus is what
distinguishes the two readings.

**Inference — the source construct.** Apple wrote

```c
    if (strcmp([[[self deviceDescription] configTable]
		valueForStringKey:"Bus Type"], "PCI") == 0)
	busType = 1;
    else
	busType = 0;
```

**Proposed change**, at `CirrusLogicGD5434DisplayDriver.m:1077-1078`, replacing
the `strncmp(…, "PCI", 4) == 0` test with

```c
    if (strcmp([[[self deviceDescription] configTable]
		valueForStringKey:"Bus Type"], "PCI") == 0)
```

`strcmp` needs no header: gcc 2.x predeclares the builtin, and the builtin is
what does the work. Behaviour is unchanged — both forms compare four bytes of a
NUL-terminated string against `"PCI"`, and both fault identically if
`valueForStringKey:` returns `NULL`.

**Prediction.** The call-target list drops from 8 entries to 7 and matches the
reference's, which is the whole of what holds this function at
`signature-confirmed`; `determineConfiguration` should then reach
`control-flow-confirmed`. **The extent gap will barely move**, and that is
expected: measuring both sides, the reference's inline sequence costs 21 bytes
(`mov ebx,ecx` 2, `mov edi,imm32` 5, `mov ecx,4` 5, `mov esi,ebx` 2, `cld` 1,
`test al,0` 2, `repe cmpsb` 2, `jne` 2) and our call costs 21 as well
(`push 4` 2, `push imm32` 5, `mov ecx,eax` 2, `push ecx` 1, `call` 5,
`mov ecx,eax` 2, `test ecx,ecx` 2, `jne` 2). The 56-byte extent difference
between the reference's 768 and our 712 is therefore **not** this; it lives in
the block placement and the two `ja`/`jg` tests already recorded above, and
closing it is a separate question. Confidence: **high** — the diagnosis rests on
a corpus-wide numeric regularity, not on a single reading.

**Task 1 result.** `strcmp` is in source at the `"Bus Type"` test
(`CirrusLogicGD5434DisplayDriver.m:1077`). The rebuilt `determineConfiguration`
extent no longer relocates `_strncmp`; the pc-relative call list is seven
entries and matches the reference's mix of `_objc_msgSend` and `_IOLog`. The
function is still `DIFF` under masked compare (768 vs 768): the remaining gap
is the `ja`/`jg` `chipType` tests plus block placement. It is **not**
assembly-matched. `failed_matched` stayed 0; the other three campaign functions
are unchanged `DIFF`. The 56-byte size gap closed even though the 21-byte
call-vs-inline estimate predicted it would not; the leftover mismatch is still
not a missing `_strncmp`.

Note also `test al, 0` at +476. It is a two-byte no-op emitted by the
`cmpstrqi_1` pattern between `cld` and the string op; it carries no meaning for
the source and should not be read as part of the comparison.

**The obvious fix for the two `jg` was tried and does not work.** The hypothesis
was that Apple declared `chipType` unsigned. The reference refutes it directly:
its `__OBJC,__instance_vars` encodes `chipType` (offset 600) as `'i'`, a signed
`int`, and all 16 of its ivar type encodings already match ours exactly.
Declaring the ivar `unsigned int` would emit `'I'` and break a section that is
currently identical, so the reference decides against the change and it was never
built.

A second, ABI-safe attempt was built on the guest: expressing the
`chipType <= 1` / `chipType <= 4` chain as a `switch` with `case 0: case 1:` and
`case 2: case 3: case 4:`. It got the comparison *form* right — gcc then loaded
`chipType` once into `ecx` and emitted `cmp ecx, 1` and `cmp ecx, 4` with the
same encodings and at nearly the same offsets as the reference — but it also
emitted a lower-bound `test ecx, ecx / jl` that the reference does not have,
taking the function from 14 conditional branches to 15 and moving it *away* from
the reference's block shape. The change was reverted; the restored build is
byte-identical to the pre-experiment build across all 21 functions. The `ja`
against `jg` divergence is therefore not reachable from the ivar's declared type
and not from a `switch`, and is left as it stands. Do not repeat either attempt.

Two further gaps, neither of them in the driver source:

- The build still prints `WARNING: no CirrusLogicGD5434DisplayDriver version bundle
  produced`. Apple's `.config` directory carries a 16728-byte
  `CirrusLogicGD5434DisplayDriver` alongside the reloc; our build produces only
  the reloc. That is Task 3 (Driver-project postamble).
- `_CirrusLogicGD5434DisplayDriver_VERS_STRING` and `_..._VERS_NUM` are still
  absent from the rebuilt nlist after Task 2. The 170-byte `__TEXT,__const`
  shortfall (2392 vs the reference's 2562) is still those two symbols plus
  padding.

**Task 2 result.** The Kernel Server `Makefile.postamble` is now exactly
`OTHER_GENERATED_OFILES += $(VERS_OFILE)`. Guest rebuild `make exit=0`.
`compare_cirrus.py` `failed_matched` stayed 0. The nlist is still `[]` for
`VERS`. `$(NAME)_vers.c` was not generated; the lksproj object directory has
`CirrusLogicGD5434DisplayDriver.o`, `ProgramDAC.o` and
`CirrusLogicGD5434DisplayDriver_instance.o` only.

`gnumake -p` on the guest shows `VERSIONING_SYSTEM = next-sgs` and
`OTHER_GENERATED_OFILES = $(INSTANCE_OBJFILE) $(VERS_OFILE)`, but no
`VERS_OFILE =` assignment. `/System/Developer/Makefiles/VersioningSystems`
contains `apple-generic.make` and `next-cvs.make` only — there is no
`next-sgs.make`, and `common.make`'s `-include` of that path is silent.
`$(VERS_OFILE)` therefore expands empty. `VERSIONING_SYSTEM` was not set
(Task 2 instruction). `driverTools` was not edited. Contents of the version
symbols, once they exist, may carry a 2026 timestamp; existence is what this
task was measuring.

Guest log excerpt (Task 2 rebuild):

```
/usr/bin/kl_ld -o /build/src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc -n CirrusLogicGD5434DisplayDriver  -i CirrusLogicGD5434DisplayDriver_instance -l Load_Commands.sect   -arch i386  /build/src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.build/objects-optimized/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/CirrusLogicGD5434DisplayDriver.o /build/src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.build/objects-optimized/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/ProgramDAC.o             /build/src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.build/objects-optimized/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/CirrusLogicGD5434DisplayDriver_instance.o
make exit=0 for CirrusLogicGD5434DisplayDriver
WARNING: no CirrusLogicGD5434DisplayDriver version bundle produced
staged /build/out/i386/drvCirrusLogicGD5434/CirrusLogicGD5434DisplayDriver.config
```

No `*_vers.o` on the `kl_ld` line. `parity_check.py` still cannot see this
gap: it scopes to `__TEXT,__cstring` and `__TEXT,__text`. Runtime impact is
low; neither symbol is referenced by any function in either binary.

### Ledger status distribution

| Status | Count |
| --- | --- |
| `assembly-matched` | 15 |
| `control-flow-confirmed` | 3 |
| `signature-confirmed` | 1 |
| `unexamined` | 2 |

The 15 at `assembly-matched` are the hand-written functions whose rebuilt
instruction stream was read against the reference and found byte-identical under
relocation masking; that is the strongest claim available and it is claimed only
where whole-body byte equality was actually demonstrated. `setMode:`,
`setPendingDisplayMode:` and `setPCIConfiguration` are held at
`control-flow-confirmed` because their block shape and call targets were compared
and agree, but their instruction streams do not match byte for byte.
`determineConfiguration` is still not `assembly-matched`: after `strcmp` the
call-target list matches (no `_strncmp`), but the instruction stream remains
`DIFF` on the `ja`/`jg` tests plus block placement. The two
`unexamined` entries are the build-generated glue at 4364 and 4376, which
`source-map.json` lists as unmapped: they have no reconstructed source to review,
and are left untouched even though both are byte-identical to the reference.

**The tool defect that used to drop `--reason` outside `intentional-mismatch`
is fixed.** `ledger.py:267-272` previously assigned `reason` only on the
`intentional-mismatch` branch, so every other transition dropped it silently
and the command still exited 0 with no warning — recorded identically on the
ThinkPad track. `transition()` now persists `reason` for every status, so the
19 reviewed entries here each carry their own machine-readable `reason` in
`ledger.json`, backfilled from this section via `binrecon ledger`. The two
`unexamined` glue entries are left with `reason: null`, since no reason was
ever recorded for them — nothing about them was reviewed. Every reviewed entry
also carries the reviewer and the source path and line the status was granted
against, and the ledger now records `rebuilt_sha256`, so the artifact the
`assembly-matched` claims were measured against is named rather than implied.

## What is not reconstructed

**The two generated glue functions at 4364 and 4376** —
`+[CirrusLogicGD5434DisplayDriverKernelServerInstance kernelServerInstance]` and
`+[CirrusLogicGD5434DisplayDriverVersion driverKitVersionForCirrusLogicGD5434DisplayDriver]`
— together with the `CirrusLogicGD5434DisplayDriver_instance.m` translation unit
that defines them and the `__DATA,__common` symbol
`_CirrusLogicGD5434DisplayDriver_instance` they hand out. These 24 bytes of
`__text` are emitted by the Kernel Server project type from the `.lksproj`'s
`NAME` and `DriverKitVersion`, exactly as `VGA_instance.m` is for `drvVGA`.
**They must not be written by hand.** If they are absent from the rebuilt binary,
the fault is in the project's `NAME`/`PROJECTVERSION`/`DriverKitVersion`
declarations or in the project type, not in the driver source. `_..._VERS_STRING`
and `_..._VERS_NUM` are likewise not hand-written source. Task 2 wired
`OTHER_GENERATED_OFILES += $(VERS_OFILE)` into the Kernel Server postamble;
`vers.c` was still not generated because `VERS_OFILE` is unset — see the Task 2
result under "Build and parity". Their *contents*
would carry our own build host and timestamp, not Apple's 1998 pair, so byte
parity on those 164 bytes is not achievable; their existence is.

Also not reconstructed, and deliberately so:

- **`_GD5434_mode_640_15_60` and `_GD5434_mode_640_15_75`** (5442 and 5512, 140
  bytes total) are referenced by neither mode table. Reproduce them only if
  byte-level `__const` parity is a goal.
- **`pciBus` and `pciAddress`** (ivars at 556 and 560) are declared in
  `__OBJC,__instance_vars` but never read or written. They must still be declared
  in the rewrite, in that order and at those offsets, or every later ivar shifts
  and `instance_size` stops being 616.

---

*Per-function findings above are the sole input to Tasks 3 and 4. Findings are
keyed by reference address so the rewrite can cite them.*
