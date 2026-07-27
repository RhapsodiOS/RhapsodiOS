# drvIBMThinkPad760EDDisplay divergences

This document covers Apple's IBM ThinkPad 760ED display driver kernel server.

| Binary | Mach-O type | Size | SHA-256 |
| --- | --- | --- | --- |
| `IBMThinkPad760EDDisplayDriver_reloc` | MH_PRELOAD (type 5) | 73168 | `47539E03C441BBFD6724EB6778D85BFACD0961B78A8DFA33D56321C938EB5AEC` |

Reference path, per shell session via `BINRECON_REFERENCE`:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\IBMThinkPad760EDDisplayDriver.config\IBMThinkPad760EDDisplayDriver_reloc
```

The Mach-O header carries `cpu_type = 7` (i386), `cpu_subtype = 4`
(`CPU_SUBTYPE_486`), `file_type = 5` (MH_PRELOAD), `ncmds = 6`, `flags = 0`.
`__TEXT,__text` is 18204 bytes at address 0. The sections, read with
`binrecon.macho.read_macho`:

| Section | Address | Size |
| --- | --- | --- |
| `__TEXT,__text` | 0 | 18204 |
| `__TEXT,__cstring` | 18204 | 1416 |
| `__TEXT,__const` | 19620 | 602 |
| `__DATA,__data` | 24576 | 1996 |
| `__DATA,__bss` | 26572 | 36 |
| `__DATA,__common` | 26608 | 4 |
| `Loaded Server,Server Name` | 40960 | 29 |
| `Loaded Server,Load Commands` | 40989 | 164 |
| `Loaded Server,Instance Var` | 41153 | 38 |
| `Loaded Server,Server Version` | 41191 | 1 |

plus the `__OBJC` metadata sections listed in "Source-file partition" below.
`Server Name` is `IBMThinkPad760EDDisplayDriver`, `Instance Var` is
`IBMThinkPad760EDDisplayDriver_instance`, `Server Version` is the single byte
`2`, and `Load Commands` is the 164-byte `WIRE` directive already restored by
Task 6.

**No function was examined against our source, because our source implements
none of the reference's behaviour.** Our
`IBMThinkPad760EDDisplayDriver.lksproj` implements a 366-line invented class
with `mapMemoryRanges`, `initHardware`, `resetHardware`,
`setDisplayMode:height:depth:` and `+probe:`; Apple's implements
`IBMThinkPad760EDDisplayDriver : IOFrameBufferDisplay` with the category
`IBMThinkPad760EDDisplayDriver(TransferTable)`, the class `vidBIOS`, the two
build-generated `_instance.m` classes, the file-static C helper `_set555Mode`
and the hand-written assembly routine `_smapi_asm`. They share no string, no
ivar and no hardware access.

They are **not** wholly disjoint by name, and this document must not claim they
are. The invented class carries the same name as Apple's, so `binrecon
source-map` — which pairs `-[class selector]` symbols and looks at nothing else —
reports four of the 40 reference entries as `mapped`:

| Addr | Reference symbol | What our invented method actually does |
| --- | --- | --- |
| 56 | `initFromDeviceDescription:` | Parses `memoryRangeList`/`portRangeList` with an invented `stringToRange:ranges:`, hard-codes an 800×600×16 `IODisplayInfo`, then calls the invented `mapMemoryRanges` and `initHardware`; it never touches SMAPI, CMOS, the Trident sequencer or PCI configuration space. |
| 1184 | `enterLinearMode` | Returns `IO_R_NOT_READY` unless an invented `isInitialized` flag is set, then sets `isEnabled = YES` and logs; the reference programs the panel through SMAPI, sets the mode through the video BIOS, unlocks CR21, clears the aperture, loads the DAC and forks the 5-5-5 refresh thread. |
| 1812 | `revertToVGAMode` | Calls the invented `resetHardware` (an empty `IOLog`) and clears `isEnabled`; the reference stops and joins the 5-5-5 thread, restores the panel through SMAPI, sets BIOS mode 3 and calls `super`. |
| 4344 | `free` | `IOFree`s two invented `IORange` arrays after an invented `unmapMemoryRanges`; the reference frees the single 3·count transfer-table allocation and calls `super`. |

The prediction in the task brief — that exactly 56, 1184, 1812 and 4344 would
collide, and that `selectMode:`, `setBrightness:` and `+probe:` would not —
holds exactly. The collision is **nominal only**. A shared selector name is not
evidence of a shared implementation, and the mapped count is therefore not the
measure of disjointness. This document records **the reference's behaviour**,
not a function-by-function diff. There is nothing to diff until Tasks 8 and 9
write the replacements.

## Evidence

### One analyzer, not three, and both reductions are recorded here

| Analyzer | Outcome |
| --- | --- |
| IDA 9.2 | **yes** — sole contributor to the consensus |
| Ghidra 12.1 | **disabled** — produces a valid document, but `binrecon` cannot normalize it |
| angr 9.3.0 | **disabled** — CFGFast misreads `__TEXT,__const` data as code |

Both are set to `"enabled": false` in
`tools/binrecon/profiles/thinkpad760ed.json`. Neither reduction is a judgement
call; each has a reproducible error, quoted verbatim below. This is the same
pair of reductions the sibling `drvCirrusLogicGD5434` effort had to make, for
the same two underlying reasons — and, in angr's case, on byte-identical data.

**IDA needed no intervention beyond what is already committed.** The spec's §5
predicted a processor-module problem because this binary is `cpu_subtype = 4`
(`CPU_SUBTYPE_486`), which makes IDA's loader auto-select the legacy `80486p`
module. `binrecon/binrecon/adapters/ida.py:317` passes `-pmetapc`
unconditionally — the force added by commit `8d8cfd20` for `VGA_reloc` — so the
override was already in effect and IDA completed with no assertion. No profile
change was needed for IDA.

#### angr — data in an executable section is disassembled as code

Verbatim, as `binrecon analyze` printed it to stderr:

```
binrecon: angr reference adapter failed: angr output is invalid: block at address 19792 is outside function at address 19816
```

The `binrecon: ` prefix is `cli.py`'s; `run-summary.json`'s `diagnostic` field
carries the bare `str(error)` without it (`binrecon/runner.py:196`), so match on
the text after the prefix when looking for this message in a summary.

The failure is deterministic: `export_with_angr` was invoked twice more
directly, outside the runner, and produced the identical message both times.

Addresses 19792 and 19816 are **not code**. They lie inside `_gamma8`, the
256-byte gamma lookup table at `__TEXT,__const` 19620–19876, whose bytes at
19792 are

```
d1 d2 d2 d3 d3 d4 d5 d5 d6 d6 d7 d8 d8 d9 d9 da
```

**Those are the same sixteen bytes, in the same role, that stopped angr on
`CirrusLogicGD5434DisplayDriver_reloc` at 5148.** The two drivers' `_gamma8`
tables are byte-identical — SHA-256
`9AD66F002D8D4DD5D032FB764C9E54403E8F5BB0B6C66D102920A134117AC33D` over both
256-byte spans — so this is literally the same failure on the same data, not
merely the same failure mode. The cause is that this Mach-O puts `__cstring` and
`__const` inside the `__TEXT` segment, so `read_macho` reports their permissions
as `rx`; angr's CFGFast therefore treats the whole segment as executable and
recovers phantom functions in the middle of constant data. IDA reads the same
bytes correctly as data.

**Correction to the plan's expectation.** The spec's §5 and this task's brief
both predicted angr would fail *inside `_emu486`*, as it did on `VGA_reloc`. It
does not get that far: it fails on the gamma table in `__const`, 1912 bytes past
the end of `__text`. The emulator may well also defeat it, but that is not what
was observed and must not be recorded as if it were.

As on the sibling driver, this is fixable in principle by giving the profile an
`analysis_scope` limited to `__text` (`binrecon/profile.py:68`), and, as there,
that change was not made: no other driver profile in the tree declares a scope.
Recorded as a candidate for separate infrastructure work.

#### Ghidra — `binrecon` cannot normalize its relocation operand metadata

Verbatim, as `binrecon analyze` printed it to stderr:

```
binrecon: Ghidra relocation operand metadata is ambiguous
```

This is **not** an adapter failure — Ghidra ran to completion and wrote a valid,
schema-conforming 3.4 MB analysis document with 44 functions. The rejection
happens later, in `normalize_analysis`, at `binrecon/normalize.py:431`.
Re-running `normalize_analysis` over the retained document with
`_ghidra_operand_owner` instrumented identifies the exact instruction:

```
FAIL at instruction addr 4451 bytes B800600000 MOV EAX, 0x6000
  relocation {"addend": 0, "address": 4452, "kind": "i386-vanilla-32-absolute", "target": "__DATA,__data"} index 230 width 4 relative False
```

That instruction is the whole body of `-[... displayModes]`: it is
`return _ThinkPad760EDModeTable;`, whose immediate `0x6000` is the relocated
address of `__DATA,__data`. Both operands carry a Ghidra reference — operand 0
is a `WRITE` to `EAX`, operand 1 is the relocated immediate — so `owners` ends
up with two entries, and the `READ`/`WRITE` tie-break at `normalize.py:421-430`
does not reduce it to one. `normalize_analysis` therefore aborts.

The sibling driver aborted at the same place on the same shape of instruction
(`mov [reg+disp], imm32` there, `mov reg, imm32` here), which makes this a
limitation of `binrecon`'s Ghidra normalization rather than a defect in Ghidra
or in either binary. Recorded as a candidate for separate infrastructure work
rather than something this task fixes.

#### A separate, environment-only Ghidra failure that is not the reason for the disablement

The first run in this worktree failed earlier and differently, with

```
binrecon: ghidra reference adapter failed: Ghidra failed with exit code 1
```

whose underlying cause, from the adapter's own `.ghidra.log` — reproduced
deliberately by pointing `export_with_ghidra`'s destination back inside the
worktree — is, quoted with its leading timestamp and the first four of its stack
frames (the rest elided):

```
2026-07-27 03:47:41 ERROR (HeadlessAnalyzer) Abort due to Headless analyzer error: Path element starting with '.' is not permitted java.lang.IllegalArgumentException: Path element starting with '.' is not permitted
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
the binary** — the committed `output_dir` of `../out/thinkpad760ed` is correct
and would work unchanged from the main checkout at `D:\RhapsodiOS`. It is
recorded only so a future reader who sees this error knows it is not the same
problem as the normalization failure above. Ghidra was re-run with `output_dir`
redirected to a dot-free scratch path, which is how the normalization failure —
the location-independent one that actually justifies the disablement — was
reached and diagnosed.

#### `rebuilt_sha256` in the committed ledger is a placeholder, not a rebuild

Task 6 gave `thinkpad760ed.json` a `rebuilt` artifact so that Tasks 8 and 9 can
run `binrecon compare`. `profile.py` resolves that artifact eagerly, so **every**
`binrecon` subcommand — `validate` included — fails outright unless
`BINRECON_REBUILT` names a file that exists, and pointing it at the reference's
own path makes `compare` abort with `binrecon: artifacts alias each other`
(`compare.py:146`). No rebuilt driver exists yet, so this run was made with
`BINRECON_REBUILT` pointing at **a copy of the reference binary at a scratch
path**. The consequences, which a reader of the committed artifacts must not
misread:

- `ledger.json`'s top-level `rebuilt_sha256` is
  `47539E03…B5AEC`. **That is the reference's own hash — the field names the
  reference binary, not a rebuild. No rebuilt artifact exists.** The field is
  not self-describing and the ledger was deliberately left unrestructured, so
  this paragraph is the only thing that says so: read `rebuilt_sha256` in the
  committed `ledger.json` as "whatever `BINRECON_REBUILT` happened to point at",
  which on this run was a copy of the reference.
- `run-summary.json` (not committed; `tools/binrecon/out/` is never committed)
  reports `acceptance.passed = true`. That is the reference compared against a
  byte-identical copy of itself and carries no information.
- Every one of `ledger.json`'s 40 entries carries `status: "unexamined"`,
  `reason: null` and `reviewer: null`, which is what the runner generates and is
  the honest state after a report pass: nothing has been rebuilt and nothing has
  been reviewed against a rebuild. Its `analyzer_agreement` is
  `{"analyzers": ["IDA"], "status": "agreed", "generated": true}` throughout,
  reflecting the single-analyzer consensus.
- Each entry also lists a `comparison` artifact,
  `published/comparison-ida.json`. That comparison is the reference against its
  own copy and should be disregarded.

The ledger's 40 addresses are exactly the source map's 40, verified directly.

**Tasks 8 and 9 must re-run the ledger against a real rebuilt binary before any
entry advances beyond `unexamined`.** Re-run `analyze` with `BINRECON_REBUILT`
pointing at the real `out/i386/…/IBMThinkPad760EDDisplayDriver_reloc`, let
`rebuilt_sha256`, the comparison artifacts and every entry be rewritten from
that, and only then review entries. Advancing any entry off `unexamined` while
`rebuilt_sha256` still equals the reference's hash would record a review of the
reference against itself.

### Why IDA alone is nevertheless trustworthy here

**The load-bearing corroboration is the Mach-O symbol table.**

`__TEXT,__text` carries 32 symbol-table entries, 31 of them below 6552. IDA
recovers every one of those 31 addresses; `set(symtab addresses below 6552) -
set(IDA addresses)` is empty. IDA's sizes are consistent with the symbol table
throughout: every function ends at or before the next symbol's address, the
differences being exactly the 21 in-scope padding gaps tabulated below, 45 bytes
in total. Re-derivable from `published/analysis-reference-ida.json` and
`binrecon.macho.read_macho` alone.

**The names are not quite identical, in four places.** The symbol table spells
the `TransferTable` methods with the category qualifier and IDA drops it:

| Address | Symbol table | IDA |
| --- | --- | --- |
| 5708 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) setTransferTable:count:]` | `-[IBMThinkPad760EDDisplayDriver setTransferTable:count:]` |
| 6044 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) setBrightness:token:]` | `-[IBMThinkPad760EDDisplayDriver setBrightness:token:]` |
| 6124 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) SetGammaValueRed:Green:Blue:Level:]` | `-[IBMThinkPad760EDDisplayDriver SetGammaValueRed:Green:Blue:Level:]` |
| 6208 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) setGammaTable]` | `-[IBMThinkPad760EDDisplayDriver setGammaTable]` |

The other 27 in-scope names match character for character. The four differences
are a display convention, not a disagreement about the binary — same addresses,
same extents.

**A second, independent partition check comes from the `__OBJC` method lists.**
`__inst_meth` is 364 bytes — two `objc_method_list`s, 23 methods for
`IBMThinkPad760EDDisplayDriver` and 6 for `vidBIOS`; `__cat_inst_meth` is 56
bytes, the 4 `TransferTable` methods; and `__cls_meth` is 40 bytes, which is
**two single-method lists, not one** — `+kernelServerInstance` at 6528 and
`+driverKitVersionForIBMThinkPad760EDDisplayDriver` at 6540, one class method
from each generated `_instance.m` class. All 23 + 6 + 4 + 2 carry an `imp`
pointer, and every one of those 35 addresses is in IDA's set with the same value
the symbol table gives (or, for the six `vidBIOS` methods, with no symbol-table
entry at all). That is what makes `--objc-methods` mandatory: without it the six
`vidBIOS` implementations at 6552, 6820, 6928, 7624, 7668 and 7684 have no name
from any source.

**Ghidra agreed too, but that agreement cannot be audited.** During the dot-free
rerun Ghidra's document was observed to recover 29 of the 31 in-scope
symbol-table addresses with byte sizes matching IDA's in all 29, and to miss
exactly two:

| Address | Symbol | Preceded by |
| --- | --- | --- |
| 5708 | `-[... (TransferTable) setTransferTable:count:]` | one `00` byte |
| 6528 | `+[...KernelServerInstance kernelServerInstance]` | two `00` bytes |

Both are the functions preceded by zero-fill rather than `nop` padding — the
same two-function blind spot Ghidra had on the sibling driver, and for the same
reason. So the only in-scope disagreement observed between the two analyzers was
which functions Ghidra declines to start, never where one ends. **But that
document was written to a scratch directory outside the worktree and is not
committed**, so a reader cannot re-check any of the above without re-running
Ghidra. It is recorded because it is what happened, not because it can be
verified, and **it should carry no weight in accepting the single-analyzer
consensus.** The corroboration that does carry weight is the Mach-O symbol-table
check above, which is re-derivable from what is committed and stands on its own.

So every claim below rests on IDA 9.2, the Mach-O symbol table, the `__OBJC`
metadata sections and the raw section bytes, all read directly.

### Function partition

`IBMThinkPad760EDDisplayDriver_reloc`, **40 entries**:

| Bucket | Count |
| --- | --- |
| mapped | 4 |
| unmapped | 36 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

The four `mapped` are the nominal name collisions at 56, 1184, 1812 and 4344
tabulated at the top of this document; none of them has a matching
implementation. Reason class for all 36 `unmapped`: `no counterpart in our
source`. **Nothing was moved by hand**, in either direction, and our invented
source was not renamed to suppress the collisions — the buckets report what the
tool observed.

**Correction to the plan's count: the partition has 40 entries, not 38.** IDA's
raw document has 107 functions; `tools/binrecon/filter_contained_fragments.py`
reduces that to 40 by dropping the 67 entries wholly contained inside another
entry's extent, which are `_emu486`'s per-opcode fragments. The filter is
required — `binrecon source-map` refuses the raw document with

```
binrecon: analysis function at address 8068 has no names; source-map-v1 requires at least one and the semantic validator requires an exact match against the analysis
```

— and the filtered document was written to a scratch path, exactly as
`drvVGA`'s two maps were (commit `5cd7b6de`); it is not a committed artifact.

The two entries the spec's §1.4 table does not list are

| Address | Size | IDA name |
| --- | --- | --- |
| 15796 | 81 | `sub_00003DB4` |
| 15877 | 37 | `sub_00003E05` |

standalone unnamed routines past the end of IDA's extent for `_emu486` (which
IDA ends at 15796, not at 18204 as the symbol-table gap implies). `VGA_reloc`'s
map has the same two entries at 15640 and 15721 — **exactly 156 bytes lower,
which is the same 156-byte offset by which this binary's `vidBIOS` block starts
later than `VGA_reloc`'s** (6552 versus 6396). They are the same two routines in
both binaries. They are deep inside the deferred region and this effort does not
touch them; they are recorded so the count of 40 is not mistaken for an error.

The remaining 2290 bytes, 15914–18204, are claimed by no entry. They are
`_emu486`'s jump tables and data — `off_422C`, `off_432C`, `off_442C` and the
rest of the pointer tables the deferred region relocates against. Also deferred.

### Padding between in-scope functions

The source map's in-scope entry sizes total 6507 against `__text`'s first 6552
bytes. The 45-byte shortfall is inter-function padding and **is not a finding**:
IDA reports true function extents and the linker pads between them. The
partition spans 0 to 6552 with no unclaimed region — the first entry starts at
0, the last in-scope entry ends at 6552, and every byte in between belongs
either to an entry or to one of these 21 gaps:

| Gap | Bytes | Content | Follows |
| --- | --- | --- | --- |
| 54–56 | 2 | `90 90` | `_set555Mode` |
| 833–836 | 3 | `90 90 90` | `initFromDeviceDescription:` |
| 1079–1080 | 1 | `90` | `selectMode` |
| 1182–1184 | 2 | `90 90` | `defaultMode` |
| 1810–1812 | 2 | `90 90` | `enterLinearMode` |
| 2027–2028 | 1 | `90` | `revertToVGAMode` |
| 2591–2592 | 1 | `90` | `determineConfiguration:` |
| 2621–2624 | 3 | `90 90 90` | `isValidPCIAssignedBaseAddress:` |
| 3298–3300 | 2 | `90 90` | `setPCIConfiguration` |
| 3925–3928 | 3 | `90 90 90` | `getDisplayDeviceState` |
| 4174–4176 | 2 | `90 90` | `unlockRegisters` |
| 4342–4344 | 2 | `90 90` | `lockRegisters` |
| 4433–4436 | 3 | `90 90 90` | `free` |
| 4485–4488 | 3 | `90 90 90` | `ramdacSpeed` |
| 4559–4560 | 1 | `90` | `readCMOS:` |
| **5707–5708** | 1 | **`00`** | `name` |
| 6041–6044 | 3 | `90 90 90` | `(TransferTable) setTransferTable:count:` |
| 6121–6124 | 3 | `90 90 90` | `(TransferTable) setBrightness:token:` |
| 6206–6208 | 2 | `90 90` | `(TransferTable) SetGammaValueRed:…` |
| **6437–6440** | 3 | **`00 00 00`** | `(TransferTable) setGammaTable` |
| **6526–6528** | 2 | **`00 00`** | `_smapi_asm` |

**Three of the 21 are zero bytes, not `nop`**, and each of the three is exactly
a boundary between translation units: `TransferTable.m` begins at 5708, the
assembly file begins at 6440, and
`IBMThinkPad760EDDisplayDriver_instance.m` begins at 6528. Padding emitted by
the assembler *within* one object file's `.text` is `nop`; padding inserted by
the linker *between* object files is zero fill. This is independent
corroboration of the module boundaries `__OBJC,__module_info` states, and it is
also the fourth piece of evidence that `_smapi_asm` is its own translation unit
(see "The `_smapi_asm` linkage" below).

There is one further gap inside `_smapi_asm` itself, at 6513–6516, but it is
**`90 90 90` — `nop`, not zero-fill** (see finding 29): it is the slack after a
two-byte `jmp` to the epilogue, intra-function, and by the rule above it is
therefore not a module boundary.

### How `IOLog` is counted: gcc tail-merged three arms

**Throughout this document `IOLog` is counted as logical invocations — one per
`IOLog(...)` a rewrite would write in the source — not as `call _IOLog`
instructions.** The two differ, because gcc tail-merged three error arms: the
arm pushes its own format string (and its own `[self name]` result) and then
`jmp`s to another arm's `call _IOLog` rather than emitting one of its own.

| Function | Arm's last push | `jmp` address | String pushed | Jumps to `call _IOLog` at |
| --- | --- | --- | --- | --- |
| `initFromDeviceDescription:` | 344 | 349 | `%s: vidBIOS alloc failure` | 711 |
| `enterLinearMode` | 1531 | 1536 | `%s: TVGA BIOS SetMode failure (%04x)\n` | 1635 |
| `setPCIConfiguration` | 2719 | 2724 | `%s: Error: Unsupported PCI hardware\n` | 3132 |

So those three have **5, 3 and 4 logical `IOLog`s against 4, 2 and 3 `call
_IOLog` instructions**. The other three in-scope users have no merged arm and
both counts agree: `determineConfiguration:` 4, `reportSystemConfiguration` 13,
`(TransferTable) setBrightness:token:` 1. In-scope totals: **30 logical
`IOLog`s, 27 `call _IOLog` instructions.** Where a summary below still gives a
raw instruction count it says so explicitly.

**A rewrite that emits one call per `IOLog` will not match the reference
byte-for-byte at those three sites.** Tail merging is something the compiler
does, not something the source expresses; if gcc does not find the same merge,
the divergence is at 344, 1531 and 2719 and nowhere else, and it is expected.

### The `__TEXT,__cstring` section

Read from the binary, not transcribed: 1416 bytes at 18204, **49 strings, all 49
referenced**. Every string is listed with the function that references it, taken
from the disassembly's relocations rather than from the wording — the brief is
right that `"%s: vidBIOS alloc failure"` is emitted by the *driver* and not by
`vidBIOS.m`, and the disassembly confirms it: its only reference is from
`-[... initFromDeviceDescription:]` at 344.

| Address | String | Referenced by |
| --- | --- | --- |
| 18204 | `%s: vidBIOS alloc failure` | `initFromDeviceDescription:` |
| 18230 | `%s: Unable to call SMAPI at port 0x%04x\n` | `initFromDeviceDescription:` |
| 18271 | `%s: Cannot use requested display mode. ` | `initFromDeviceDescription:` |
| 18311 | `Trying default mode.\n` | `initFromDeviceDescription:` |
| 18333 | `%s: Error: Unable to map frame buffer\n` | `initFromDeviceDescription:` |
| 18372 | `%s: Unable to set refresh rate using SMAPI\n` | `enterLinearMode` |
| 18416 | `%s: TVGA BIOS SetMode failure (%04x)\n` | `enterLinearMode` |
| 18454 | `%s: Vesa BIOS SetMode failure (%04x)\n` | `enterLinearMode` |
| 18492 | `%s: Trident Cyber938x not detected - trying anyway\n` | `determineConfiguration:` |
| 18544 | `%s: Chip ID=0x%02x, Revision=0x%02x\n` | `determineConfiguration:` |
| 18581 | `%s: Detected Trident Cyber938x (rev 0x%02x)\n` | `determineConfiguration:` |
| 18626 | `%s: Found %d MB DRAM\n` | `determineConfiguration:` |
| 18648 | `%s: Error: Unsupported PCI hardware\n` | `setPCIConfiguration` |
| 18685 | `%s: Error: Can't set memory range, using default.\n` | `setPCIConfiguration` |
| 18736 | `%s: Error: Can't set to default range either!\n` | `setPCIConfiguration` |
| 18783 | `%s: Error: Incorrect number of address ranges: %d.\n` | `setPCIConfiguration` |
| 18835 | `%s: System ID = 0x%04x\n` | `reportSystemConfiguration` |
| 18859 | `%s: System BIOS revision %01x.%02x\n` | `reportSystemConfiguration` |
| 18895 | `%s: System management BIOS revision %01x.%02x\n` | `reportSystemConfiguration` |
| 18942 | `%s: SMAPI revision %01x.%02x\n` | `reportSystemConfiguration` |
| 18972 | `%s: Video BIOS revision %01x.%02x\n` | `reportSystemConfiguration` |
| 19007 | `%s: Slave controller revision %01x.%02x\n` | `reportSystemConfiguration` |
| 19048 | `Intel` | `reportSystemConfiguration` |
| 19054 | `AMD` | `reportSystemConfiguration` |
| 19058 | `Unknown` | `reportSystemConfiguration` (three call sites) |
| 19066 | `%s: %s CPU Family %d, Model %d, Stepping %d\n` | `reportSystemConfiguration` |
| 19111 | `%s: CPU clock (Int/Ext) = ` | `reportSystemConfiguration` |
| 19138 | `%d` | `reportSystemConfiguration` |
| 19141 | `?` | `reportSystemConfiguration` |
| 19143 | `/%d MHz\n` | `reportSystemConfiguration` |
| 19152 | `/? MHz\n` | `reportSystemConfiguration` |
| 19160 | `Monochrome STN` | `reportSystemConfiguration` |
| 19175 | `Monochrome TFT` | `reportSystemConfiguration` |
| 19190 | `Color STN` | `reportSystemConfiguration` |
| 19200 | `Color TFT` | `reportSystemConfiguration` |
| 19210 | `640x480` | `reportSystemConfiguration` |
| 19218 | `800x600` | `reportSystemConfiguration` |
| 19226 | `1024x768` | `reportSystemConfiguration` |
| 19235 | `%s: %s LCD (%s)\n` | `reportSystemConfiguration` |
| 19252 | `Display0` | `name` |
| 19261 | ``%s: Invalid brightness level `%d'\n`` | `(TransferTable) setBrightness:token:` |
| 19296 | `%s: can't allocate low memory region\n` | **deferred** — `-[vidBIOS init]` |
| 19334 | `%s: failed to wire down low memory region\n` | **deferred** — `-[vidBIOS init]` |
| 19377 | `%s: can't allocate memory region in the lower 1MB\n` | **deferred** — `-[vidBIOS init]` |
| 19428 | `%s: can't map lower 1MB\n` | **deferred** — `-[vidBIOS init]` |
| 19453 | `%s: emu486 error %08x before %04x:%04x\n` | **deferred** — `-[vidBIOS int10:outregs:iorange:ionum:smmport:]` |
| 19493 | `%s: eax=%08x ebx=%08x ecx=%08x edx=%08x\n` | **deferred** — same |
| 19534 | `%s: esi=%08x edi=%08x ebp=%08x esp=%08x\n` | **deferred** — same |
| 19575 | `%s: ds=%04x es=%04x fs=%04x gs=%04x ss=%04x\n` | **deferred** — same |

**Eight of the 49 strings, 19296–19620, belong to the deferred region** and must
not be written into `IBMThinkPad760ED.m` or `TransferTable.m`. They are
`vidBIOS.m`'s, and `drvVGA/reconstruction/divergences.md` already treats the
last four as the evidence fixing the `emu486` register-block layout.

Details worth carrying into the rewrite verbatim:

- `%s: vidBIOS alloc failure` has **no trailing newline**, and neither does
  `%s: Cannot use requested display mode. ` — the latter deliberately, because
  `Trying default mode.\n` is logged immediately after it as a *separate*
  `IOLog` with no `%s` prefix, so the two concatenate into one line.
- `%s: CPU clock (Int/Ext) = ` likewise has no newline; it is the first of a
  three-`IOLog` sequence that builds one line.
- The brightness message uses an asymmetric quote pair — backtick before, single
  quote after.
- Four of the six error strings in `setPCIConfiguration`/`initFromDeviceDescription:`
  are spelled `%s: Error: …`; the Cirrus driver's equivalents are not. Do not
  normalize either driver's wording to the other's.

### `__TEXT,__const`

602 bytes at 19620, fully accounted for:

| Symbol | Address | Size | Content |
| --- | --- | --- | --- |
| `_gamma8` | 19620 | 256 | the 8-bit gamma ramp, `00 0f 16 1b 1f 23 27 2a …` — byte-identical to the Cirrus driver's |
| `_mode_640_8_60` … `_mode_1280_8_75` | 19876 | 168 | 14 twelve-byte mode-parameter records (below) |
| `_defaultMode` | 20044 | 4 | `0` |
| `_modeTableCount` | 20048 | 4 | `14` |
| `_IBMThinkPad760EDDisplayDriver_VERS_STRING` | 20052 | 160 | `@(#)PROGRAM:IBMThinkPad760EDDisplayDriver  PROJECT:drvIBMThinkPad760EDDisplay-7  DEVELOPER:root  BUILT:Sat Mar 28 21:52:34 PST 1998\n` |
| `_IBMThinkPad760EDDisplayDriver_VERS_NUM` | 20212 | 10 | `"7"` |

The two `VERS_` symbols are emitted by Apple's build from the generated version
file and must not be written by hand.

## Deferred to drvVGA

**`__text` 6552 through 18204 — 11652 bytes, seven entries — is out of scope for
this effort** and is documented here rather than decompiled, per the spec's
§1.4:

| Address | Size | Symbol |
| --- | --- | --- |
| 6552 | 268 | `-[vidBIOS init]` |
| 6820 | 108 | `-[vidBIOS free]` |
| 6928 | 696 | `-[vidBIOS int10:outregs:iorange:ionum:smmport:]` |
| 7624 | 44 | `-[vidBIOS int10:outregs:iorange:ionum:]` |
| 7668 | 16 | `-[vidBIOS scratchSegment]` |
| 7684 | 24 | `-[vidBIOS realToVirtual::]` |
| 7708 | 10496 | `_emu486` |

(Only `_emu486`'s size is a symbol-table gap. **The six `vidBIOS` methods have
no symbol-table entry at all** — `__TEXT,__text`'s symtab jumps straight from
6540 to 7708 — so their sizes are gaps between consecutive `__OBJC` `imp`
addresses, and between the last of them and `_emu486`. The same is true in
`VGA_reloc`. IDA gives `_emu486` an extent of 8088 bytes ending at 15796, with
the two standalone fragments and 2290 bytes of jump tables making up the rest of
the gap; see "Function partition" above.)

**Extents in this document are half-open, `[start, end)`, so `end - start` is
the size.** `vidBIOS.m`'s six methods span **6552 to 7708 here — 1156 bytes** —
and `VGA_reloc`'s same six selectors span **6396 to 7552 — also 1156 bytes**,
with every individual method size matching (268, 108, 696, 44, 16, 24 in both).
Two
independently linked binaries carrying byte-identical method extents for the
same six selectors is strong evidence of a single shared source file compiled
into each driver, and it makes the two copies **cross-validating**: whoever
reconstructs `vidBIOS.m` for
[2026-07-25-vga-driver-binary-reconstruction-design.md](../../../../../docs/superpowers/specs/2026-07-25-vga-driver-binary-reconstruction-design.md)
can check the result against both. The `_emu486` bodies likewise correspond.

`drvVGA/reconstruction/divergences.md` already owns the `vidBIOS` interface, its
three instance variables, the sixteen-slot `emu486` register block and seven
independent observations that `_emu486` is hand-written assembly. This driver's
copy of the `vidBIOS` class metadata agrees with it exactly: `vidBIOS : Object`,
`instance_size` 16, three ivars `biosStackVirtual` (`^v`, +4),
`biosStackPhysical` (`I`, +8) and `lowMem` (`I`, +12), and the same six method
type encodings.

`vidBIOS.m` and the emulator's assembly file are to be **listed** in the
`lksproj` Makefile from the start (spec §1.4) but not written here; the link is
expected to fail on `.objc_class_name_vidBIOS` and `_emu486` until drvVGA
supplies them.

## Source-file partition

`__OBJC,__module_info` is 64 bytes — four 16-byte `objc_module` records
(`{version, size, char *name, struct objc_symtab *symtab}`). Read directly, the
four `name` pointers resolve in `__OBJC,__class_names` to:

| Module | `__text` range | symtab | Defines |
| --- | --- | --- | --- |
| `IBMThinkPad760ED.m` | 0 – 5708 | 36068 | `@implementation IBMThinkPad760EDDisplayDriver` (1 class) |
| `TransferTable.m` | 5708 – 6440 | 36084 | `@implementation IBMThinkPad760EDDisplayDriver(TransferTable)` (1 category) |
| `IBMThinkPad760EDDisplayDriver_instance.m` | 6528 – 6552 | 36100 | `IBMThinkPad760EDDisplayDriverVersion` and `IBMThinkPad760EDDisplayDriverKernelServerInstance` (2 classes) |
| `vidBIOS.m` | 6552 – 7708 | 36120 | `@implementation vidBIOS` (1 class) |

The two assembly translation units — `_smapi_asm` at 6440–6528 and `_emu486` at
7708–18204 — contribute no module record, which is why the ranges above are not
contiguous.

`__OBJC,__symbols` is 68 bytes, which is exactly four 12-byte `objc_symtab`
headers plus five 4-byte `defs` pointers (`4*12 + 5*4 = 68`). Its raw bytes give
the split directly: the first symtab declares 1 class and 0 categories with
`defs = [32980]`, the second 0 classes and 1 category with `defs = [35712]`, the
third 2 classes with `defs = [33020, 33060]`, the fourth 1 class with
`defs = [33100]` — five defs in total, matching the four 40-byte
`__OBJC,__class` records at 32980/33020/33060/33100 plus the one 20-byte
`__OBJC,__category` record at 35712 with none left over.

`__OBJC,__class` decoded:

| Address | Class | Superclass | `instance_size` | ivars | methods |
| --- | --- | --- | --- | --- | --- |
| 32980 | `IBMThinkPad760EDDisplayDriver` | `IOFrameBufferDisplay` | 648 | 19 | 23 instance |
| 33020 | `IBMThinkPad760EDDisplayDriverVersion` | `IODevice` | 264 | none | 1 class method |
| 33060 | `IBMThinkPad760EDDisplayDriverKernelServerInstance` | `Object` | 4 | none | 1 class method |
| 33100 | `vidBIOS` | `Object` | 16 | 3 | 6 instance |

The category record names `TransferTable` on class
`IBMThinkPad760EDDisplayDriver`, pointing at `__cat_inst_meth` (56 bytes = an
8-byte header plus four 12-byte methods) and at no class methods.

**`IBMThinkPad760EDDisplayDriver.lksproj`'s `sources` should name three
hand-written files in scope** — `IBMThinkPad760ED.m`, `TransferTable.m` and
`smapi.s` — plus the deferred `vidBIOS.m` and the emulator's `.s`. The
`IBMThinkPad760EDDisplayDriver_instance.m` unit is emitted by the Kernel Server
project type and must not be written by hand.

### The ivar layout

`__OBJC,__instance_vars` is 272 bytes — a 4-byte count of 19 followed by
nineteen 12-byte records — and gives every name, type encoding and offset
directly. The first ivar sits at 552, so `IOFrameBufferDisplay`'s instance size
is 552 and this class adds 96 bytes to reach 648.

| Offset | Hex | Name | Encoding | Meaning |
| --- | --- | --- | --- | --- |
| 552 | `0x228` | `modeIndex` | `i` | index into `_ThinkPad760EDModeTable` |
| 556 | `0x22C` | `currentState` | `i` | 0 = initialized/VGA, 1 = linear |
| 560 | `0x230` | `crtOnlyDisplay` | `c` | set by `setPendingDisplayMode:` when the mode exceeds the panel |
| 564 | `0x234` | `LCDWidth` | `i` | panel-size **index**, 0 = 640×480, 1 = 800×600, 2 = 1024×768 — not a pixel count |
| 568 | `0x238` | `viewportSize` | `S` | SMAPI 0x100C/0x100D parameter; initialized to `0x0204` |
| 572 | `0x23C` | `displayMemorySize` | `I` | detected DRAM in bytes |
| 576 | `0x240` | `physicalAddress` | `I` | frame-buffer physical base |
| 580 | `0x244` | `virtualAddress` | `^v` | mapped frame-buffer virtual address |
| 584 | `0x248` | `transferTableCount` | `i` | |
| 588 | `0x24C` | `brightnessLevel` | `i` | 0…64, initialized to 64 |
| 592 | `0x250` | `redTransferTable` | `*` | head of one `3*count` allocation |
| 596 | `0x254` | `greenTransferTable` | `*` | `red + count` |
| 600 | `0x258` | `blueTransferTable` | `*` | `green + count` |
| 604 | `0x25C` | `reg` | `{smapiReg="ax"(?)"bx"(?)"cx"(?)"dx"(?)"si"(?)"di"(?)}` | 24 bytes, the `_smapi_asm` register block |
| 628 | `0x274` | `smapiPort` | `S` | assembled from CMOS 0x7E/0x7F |
| 632 | `0x278` | `bios` | `@"vidBIOS"` | |
| 636 | `0x27C` | `BiosType` | `i` | 1 when a Trident Cyber938x was positively identified |
| 640 | `0x280` | `mode555_thread` | `^v` | `IOForkThread` handle, or 0 |
| 644 | `0x284` | `mode555_thread_enable` | `c` | 1 = run, 0 = stop requested, 2 = stopped |

**`struct smapiReg` is six 4-byte members, not six 2-byte members.** The
encoding gives each member as `(?)` — an anonymous union — and the ivar spans
604…628, 24 bytes for six members. Every access in `__text` is a 16-bit
operand-size access at offsets 0, 4, 8, 0x0C, 0x10, 0x14 from the base, and
`reportSystemConfiguration` additionally reads the individual high bytes at +1,
+5, +9, +0x0D, +0x11 and +0x15. **Inference:** the source declares

```c
struct smapiReg {
    union { unsigned int e; unsigned short x; struct { unsigned char l, h; } b; } ax, bx, cx, dx, si, di;
};
```

or something isomorphic. The 4-byte stride, the 16-bit accesses and the
low/high byte accesses are observations; the union spelling that produces them
is not.

Every ivar is used. `crtOnlyDisplay` is written by `setPendingDisplayMode:` and
read by `enterLinearMode`; `viewportSize` is written by
`reportSystemConfiguration` and read by `setPendingDisplayMode:`; there is no
dead ivar in this class, unlike the Cirrus driver's `pciBus`/`pciAddress`.

### The mode-parameter struct

The 14 records in `__TEXT,__const` are 12 bytes each (19876 → 20044). Their
fields are fixed by how `defaultMode`, `enterLinearMode` and
`setPendingDisplayMode:` read them:

| Offset | Access | Meaning |
| --- | --- | --- |
| 0 | `movzx …, byte [p]` | panel-size index + 1: 1 = 640×480, 2 = 800×600, 3 = 1024×768, 4 = 1280×1024 |
| 1 | `movzx …, byte [p+1]` | refresh index: 0 = 60 Hz, 2 = 75 Hz |
| 2–3 | never read | always `00 00` |
| 4 | `mov …, [p+4]` | VESA mode number |
| 8 | `mov …, [p+8]` | Trident TVGA mode number |

**Inference:** the source declares
`struct { unsigned char panelSize, refresh; unsigned int vesaMode, tvgaMode; }`,
whose natural gcc padding gives exactly 12 bytes with `vesaMode` at 4. The
offsets and widths are observations; the two-byte hole being padding rather
than a declared `short` is the inference. It is never read or written, so a
declared `unsigned short pad` would be observationally identical.

The 14 records, read from the binary:

| Symbol | Address | panelSize | refresh | VESA | TVGA |
| --- | --- | --- | --- | --- | --- |
| `_mode_640_8_60` | 19876 | 1 | 0 | `0x101` | `0x5D` |
| `_mode_640_8_75` | 19888 | 1 | 2 | `0x101` | `0x5D` |
| `_mode_640_15_60` | 19900 | 1 | 0 | `0x110` | `0x74` |
| `_mode_640_15_75` | 19912 | 1 | 2 | `0x110` | `0x74` |
| `_mode_800_8_60` | 19924 | 2 | 0 | `0x103` | `0x5E` |
| `_mode_800_8_75` | 19936 | 2 | 2 | `0x103` | `0x5E` |
| `_mode_800_15_60` | 19948 | 2 | 0 | `0x113` | `0x76` |
| `_mode_800_15_75` | 19960 | 2 | 2 | `0x113` | `0x76` |
| `_mode_1024_8_60` | 19972 | 3 | 0 | `0x105` | `0x62` |
| `_mode_1024_8_75` | 19984 | 3 | 2 | `0x105` | `0x62` |
| `_mode_1024_15_60` | 19996 | 3 | 0 | `0x116` | `0x78` |
| `_mode_1024_15_75` | 20008 | 3 | 2 | `0x116` | `0x78` |
| `_mode_1280_8_60` | 20020 | 4 | 0 | `0x107` | `0x64` |
| `_mode_1280_8_75` | 20032 | 4 | 2 | `0x107` | `0x64` |

The VESA numbers are the standard VBE mode numbers for the corresponding
geometry and depth, and the TVGA numbers are Trident's own; both are only ever
handed to the video BIOS, never decoded by the driver. **All 14 records are
referenced** — one per mode-table entry, with none dead, unlike the Cirrus
driver's two orphaned register structs.

### The mode table

`__DATA,__data` is 1996 bytes and begins with `_ThinkPad760EDModeTable`, an
array of **14 `IODisplayInfo`** (136 bytes each, 1904 bytes, 24576–26480).
`_modeTableCount` is 14 and `_defaultMode` is 0, both in `__const`.

**The remaining 92 bytes, 26480–26572, are not part of the mode table.** They
are all zero at load and are relocated against only by the deferred region:
IDA names them `dword_6770` … `dword_67C8` plus two byte-granular references at
26566 and 26567, and every reference to them comes from inside `_emu486`. They
are the emulator's file-scope state. Nothing in scope reads or writes them, and
a rewrite of `IBMThinkPad760ED.m` must not try to account for them.

The table, read directly. `bitsPerPixel` stores an `IOBitsPerPixel` enumerator,
not a human depth — 1 is `IO_8BitsPerPixel` and 3 is `IO_15BitsPerPixel`
(`src/driverkit-3/driverkit/displayDefs.h`); transcribe 1 and 3, never 8 and 15.
`colorSpace` is 2 (`IO_RGBColorSpace`) in **all 14** entries — this driver ships
no greyscale modes, unlike the Cirrus driver. `totalWidth` equals `width` in all
14 and is initialized, so it is listed as its own column here.

| # | Address | width×height | totalWidth | rowBytes | refreshRate | bitsPerPixel | pixelEncoding | parameters |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 24576 | 640×480 | 640 | 640 | 60 | 1 | `PPPPPPPP` | `_mode_640_8_60` |
| 1 | 24712 | 640×480 | 640 | 640 | 75 | 1 | `PPPPPPPP` | `_mode_640_8_75` |
| 2 | 24848 | 640×480 | 640 | 1280 | 60 | 3 | `-RRRRRGGGGGBBBBB` | `_mode_640_15_60` |
| 3 | 24984 | 640×480 | 640 | 1280 | 75 | 3 | `-RRRRRGGGGGBBBBB` | `_mode_640_15_75` |
| 4 | 25120 | 800×600 | 800 | 800 | 60 | 1 | `PPPPPPPP` | `_mode_800_8_60` |
| 5 | 25256 | 800×600 | 800 | 800 | 75 | 1 | `PPPPPPPP` | `_mode_800_8_75` |
| 6 | 25392 | 800×600 | 800 | 1600 | 60 | 3 | `-RRRRRGGGGGBBBBB` | `_mode_800_15_60` |
| 7 | 25528 | 800×600 | 800 | 1600 | 75 | 3 | `-RRRRRGGGGGBBBBB` | `_mode_800_15_75` |
| 8 | 25664 | 1024×768 | 1024 | 1024 | 60 | 1 | `PPPPPPPP` | `_mode_1024_8_60` |
| 9 | 25800 | 1024×768 | 1024 | 1024 | 75 | 1 | `PPPPPPPP` | `_mode_1024_8_75` |
| 10 | 25936 | 1024×768 | 1024 | 2048 | 60 | 3 | `-RRRRRGGGGGBBBBB` | `_mode_1024_15_60` |
| 11 | 26072 | 1024×768 | 1024 | 2048 | 75 | 3 | `-RRRRRGGGGGBBBBB` | `_mode_1024_15_75` |
| 12 | 26208 | 1280×1024 | 1280 | 1280 | 60 | 1 | `PPPPPPPP` | `_mode_1280_8_60` |
| 13 | 26344 | 1280×1024 | 1280 | 1280 | 75 | 1 | `PPPPPPPP` | `_mode_1280_8_75` |

`pixelEncoding` is a `char[64]`, NUL-padded to the full 64 bytes. Every entry
ships with `frameBuffer`, `flags`, `memorySize`, `scanRate`, `_reserved1`,
`dotClockRate`, `screenWidth`, `screenHeight`, `modeUnavailableFlag` and
`_reserved[0]` **all zero**; `updateModeTable`, `initFromDeviceDescription:` and
`setPendingDisplayMode:` fill them in at runtime. The table is therefore
**mutable** and must not be declared `const`.

## Per-function findings

Addresses are decimal, as in the source map. **All 31 entries below 6552, in
address order.** Twenty-nine of them are hand-written; findings 30 and 31 are
the two build-generated `_instance.m` methods, included so the coverage check
finds every name and so the rewrite knows not to write them. Sizes given are
IDA's true extents; the symbol-table gap is larger by the padding tabulated
above.

`self` is `IBMThinkPad760EDDisplayDriver *` throughout, and ivar names are those
of the `__OBJC,__instance_vars` table above.

Four conventions apply to every finding and are stated once here rather than
repeated:

- **`inb`/`outb`/`outw` come from `src/driverkit-3/driverkit/i386/ioPorts.h`.**
  `outb`, `outw` and `outl` are each a `static __inline__` containing
  `static int xxx;` and an `outX %2,%1; lock; incl %0` asm body. That is why
  every `out` in this binary is followed by `lock inc ds:_xxx.NN`, and why the
  rewrite does not have to produce those increments by hand — they fall out of
  calling `outb()`/`outw()`. `inb`/`inw` have no counter. A word `out` to an
  index port writes the index in `AL` and the data in `AH`, so
  `outw(0x3C4, 0x2021)` sets register `0x21` to `0x20`.
- **No PCI configuration register is touched directly.** All PCI access goes
  through `IODeviceDescription`/`IOPCIDevice` messages —
  `getPCIdevice:function:bus:`, `getPCIConfigData:atRegister:withDeviceDescription:`,
  `setPCIConfigData:atRegister:withDeviceDescription:`, `getPCIConfigSpace:` and
  `setPCIConfigSpace:`. There is no `0xCF8`/`0xCFC` access anywhere in `__text`.
  The only PCI *register number* named in the code is **4**, the Command/Status
  register; base address register 0 is reached as offset 16 of the fetched
  256-byte config-space image.
- **Every SMAPI call has the same shape:** the caller fills `self->reg.ax` with
  `0x5380`, `self->reg.dx` with `self->smapiPort`, `self->reg.bx` with the
  function code and `self->reg.cx` with the parameter, then calls
  `_smapi_asm(&self->reg)`. **`reg.si` and `reg.di` are never initialized by any
  caller** — they carry whatever the previous call left in them. Callers that
  check for failure test `self->reg.ax`'s high byte (`AH`) against zero. All
  writes are 16-bit.
- **`self->bios` is a `vidBIOS *` and every video-BIOS call goes through it.**
  The register block passed to `int10:outregs:iorange:ionum:smmport:` is the
  sixteen-`unsigned int` `emu486` block documented in
  `drvVGA/reconstruction/divergences.md`: index 0 `eax`, 1 `ecx`, 2 `edx`,
  3 `ebx`, 4 `esp`, 5 `ebp`, 6 `esi`, 7 `edi`, 8 `eip`, 9 `eflags`, 10 `es`,
  11 `cs`, 12 `ss`, 13 `ds`, 14 `fs`, 15 `gs`. Every in-scope caller passes the
  same 64-byte stack block as both `inregs` and `outregs`, `iorange = 0`,
  `ionum = 0` and `smmport = self->smapiPort`.

---

### 1. `_set555Mode` — 0, 54 bytes

A file-static C function used only as an `IOForkThread` body. It never returns.

```c
static void set555Mode(volatile char *enable)
{
    for (;;) {
        if (*enable == 1) {
            (void)inb(0x3C6); (void)inb(0x3C6);
            (void)inb(0x3C6); (void)inb(0x3C6);
            outb(0x3C6, 0x10);
        } else {
            *enable = 2;
        }
        IOSleep(500);
    }
}
```

- **I/O ports:** `0x3C6` — four reads then one write, the standard VGA
  hidden-DAC-command unlock sequence; `0x10` is the Trident value selecting
  5-5-5 direct colour. **PCI:** none. **CMOS/SMAPI:** none.
- **DriverKit calls:** `_IOSleep` once. No message send.
- **Callers:** none directly; its *address* is taken by `enterLinearMode` and
  handed to `_IOForkThread`. **Callees:** `_IOSleep`.
- **`__const`/`__data` read:** none. It increments `_xxx.86`
  (`IBMThinkPad760ED.m`'s `outb` counter) once per write.
- The argument is `&self->mode555_thread_enable`, so the thread and
  `revertToVGAMode` communicate through that single byte: 1 means "keep
  reasserting the 5-5-5 DAC setting", anything else means "stop", and the thread
  answers by writing 2.
- **Observation, not inference:** the loop has no exit. The thread lives for the
  life of the driver; `revertToVGAMode` parks it rather than terminating it, and
  `enterLinearMode` reuses it rather than forking a second one.
- **Inference:** the 500 ms poll exists because the ThinkPad's SMM code
  reprograms the hidden DAC register behind the driver's back when the panel
  state changes. Nothing in the binary states this; it is the only reading that
  explains a periodic rewrite of a register nobody else in the driver touches.

### 2. `-[IBMThinkPad760EDDisplayDriver initFromDeviceDescription:]` — 56, 777 bytes

The driver's entry point and the only caller of most of the rest.

```c
- initFromDeviceDescription:deviceDescription
{
    self->blueTransferTable   = 0;
    self->greenTransferTable  = 0;
    self->redTransferTable    = 0;
    self->transferTableCount  = 0;
    self->brightnessLevel     = 64;              /* EV_SCREEN_MAX_BRIGHTNESS */
    self->modeIndex           = 0;
    self->physicalAddress     = 0;
    self->displayMemorySize   = 0;
    self->virtualAddress      = 0;
    self->currentState        = 0;
    self->BiosType            = 0;
    self->crtOnlyDisplay      = 0;
    self->mode555_thread      = 0;
    self->LCDWidth            = 0;
    self->viewportSize        = 0x0204;

    if (![self determineConfiguration:deviceDescription])   goto fail;
    if (![super initFromDeviceDescription:deviceDescription]) goto fail;

    self->bios = [[vidBIOS alloc] init];
    if (self->bios == nil) {
        IOLog("%s: vidBIOS alloc failure", [self name]);
        goto fail;
    }
    if (![self setPCIConfiguration]) goto fail;

    self->smapiPort = ([self readCMOS:0x7F] << 8) | [self readCMOS:0x7E];

    self->reg.ax.x = 0x5380;
    self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0;
    self->reg.cx.x = 0;
    smapi_asm(&self->reg);
    if (self->reg.ax.b.h != 0) {
        IOLog("%s: Unable to call SMAPI at port 0x%04x\n", [self name], self->smapiPort);
        goto fail;
    }

    [self reportSystemConfiguration];

    self->modeIndex = [self selectMode];
    if (![self setPendingDisplayMode:self->modeIndex]) {
        IOLog("%s: Cannot use requested display mode. ", [self name]);
        IOLog("Trying default mode.\n");
        self->modeIndex = [self defaultMode];
    }

    self->physicalAddress = [deviceDescription memoryRangeList][0].start;
    self->virtualAddress  = [self mapFrameBufferAtPhysicalAddress:self->physicalAddress
                                                           length:self->displayMemorySize];
    if (self->virtualAddress == 0) {
        IOLog("%s: Error: Unable to map frame buffer\n", [self name]);
        goto fail;
    }

    displayInfo = [self displayInfo];
    *displayInfo = _ThinkPad760EDModeTable[self->modeIndex];   /* rep movsd, ecx = 34 */
    displayInfo->frameBuffer = self->virtualAddress;
    if (displayInfo->bitsPerPixel == IO_8BitsPerPixel)
        displayInfo->flags |= IO_DISPLAY_HAS_TRANSFER_TABLE;               /* 0x10 */
    else
        displayInfo->flags |= IO_DISPLAY_NEEDS_SOFTWARE_GAMMA_CORRECTION;  /* 0x02 */

    [self updateModeTable];
    return self;

fail:
    return [self free];
}
```

- **DriverKit calls:** `objc_msgSendSuper` to `initFromDeviceDescription:`;
  `objc_msgSend` to `determineConfiguration:`, `alloc` and `init` on the
  `vidBIOS` class reference, `setPCIConfiguration`, `readCMOS:` twice,
  `reportSystemConfiguration`, `selectMode`, `setPendingDisplayMode:`,
  `defaultMode`, `memoryRangeList`, `mapFrameBufferAtPhysicalAddress:length:`,
  `displayInfo`, `updateModeTable`, `free`, and `name` four times. Direct call to
  `_smapi_asm` and five `IOLog`s — at 512, 595, 605, 706 and the tail-merged arm
  at 344, which is only four `call _IOLog` instructions (see "How `IOLog` is
  counted" above). Four of the five take `[self name]`; the `"Trying default
  mode…"` one at 605 has no `%s`.
- **I/O ports:** none directly. **PCI:** none directly. **CMOS:** 0x7E and 0x7F,
  through `readCMOS:`. **SMAPI:** one call, function `BX = 0x0000`.
- **Callers:** none in this binary; invoked by `IODevice`'s probe machinery.
  **Callees:** everything above, plus `_smapi_asm` directly.
- **`__const`/`__data` read:** `_ThinkPad760EDModeTable` (24576), through the
  `mode*136` index arithmetic; the class reference `.objc_class_name_vidBIOS`;
  and five `__cstring` entries.
- **`determineConfiguration:` runs before `[super initFromDeviceDescription:]`.**
  That is unusual and load-bearing: the Trident detection and the DRAM sizing
  have to happen before `IOFrameBufferDisplay` looks at the device description.
  Do not reorder them.
- **The failure return is `[self free]`, not `[super free]` and not a literal
  `nil`.** `eax` is not zeroed on any failure path; whatever `-free` returns is
  what the method returns. Every one of the five failure arms converges on the
  single `objc_msgSend(self, @selector(free))` at 716.
- **After falling back to `[self defaultMode]` the driver does *not* re-call
  `setPendingDisplayMode:`.** The default mode is installed by copying its
  `IODisplayInfo` and nothing else, so the panel and the video BIOS are never
  programmed for it during `init`. That is the reference's behaviour; reproduce
  it.
- **The two log strings on the fallback path are two separate `IOLog` calls**
  producing one line, the first with a `%s` prefix and no newline and the second
  with neither prefix nor `%s`.
- The copy at 764–779 is `cld; rep movsd` with `ecx = 0x22` — 34 dwords, 136
  bytes, one whole `IODisplayInfo`. The index arithmetic is `mode*16 + mode`
  then `<< 3`, i.e. `mode * 136`.
- **The flags are `|=`, not `=`** (`or byte ptr [edx+0x60], 0x10`). Since the
  table ships `flags == 0` this is observationally the same as assignment on the
  first pass, but the emitted code is an or and the rewrite should match it.
- **Inference:** the `goto fail` shape is inferred from five branches converging
  on one `[self free]`. The source may equally have written `return [self free];`
  out longhand in each arm.

### 3. `-[IBMThinkPad760EDDisplayDriver updateModeTable]` — 836, 128 bytes

```c
- (void)updateModeTable
{
    for (i = 0; i < _modeTableCount; i++) {
        IODisplayInfo *m = &_ThinkPad760EDModeTable[i];
        m->memorySize = m->rowBytes * m->height;
        m->scanRate = 0;
        m->screenWidth = 0;
        m->screenHeight = 0;
        m->modeUnavailableFlag = 0;
        if (self->displayMemorySize < m->memorySize)
            m->modeUnavailableFlag = IO_DISPLAY_MODE_NEEDS_MORE_MEMORY;   /* 2 */
    }
}
```

- **I/O ports:** none. **PCI/CMOS/SMAPI:** none. **DriverKit calls:** none — no
  message send, no import.
- **Callers:** `initFromDeviceDescription:`, as the last thing it does.
  **Callees:** none.
- **`__const`/`__data`:** reads `_modeTableCount` (20048) on every iteration —
  the compiler reloads it rather than caching it — and **writes** five fields of
  every entry of `_ThinkPad760EDModeTable`.
- The comparison at 926 is `cmp [esi+23Ch], eax` / `jnb`, i.e. **unsigned**:
  `displayMemorySize` is `unsigned int`.
- **Unlike the Cirrus driver's `determineConfiguration`, there is no
  width-based invalidation.** No mode is marked unavailable for being wider than
  1024; only the memory test applies. Do not import the Cirrus rule.
- `memorySize` is `rowBytes * height`, not `rowBytes * totalWidth` or anything
  else; the `imul` at 878 is `[ecx+edx+0Ch] * [ecx+edx+4]`.

### 4. `-[IBMThinkPad760EDDisplayDriver selectMode]` — 964, 115 bytes

```c
- (int)selectMode
{
    char valid[_modeTableCount];        /* alloca, rounded up to 4 bytes */

    for (i = 0; i < _modeTableCount; i++)
        valid[i] = (self->displayMemorySize >=
                    _ThinkPad760EDModeTable[i].rowBytes *
                    _ThinkPad760EDModeTable[i].height);

    return [self selectMode:_ThinkPad760EDModeTable
                      count:_modeTableCount
                      valid:valid];
}
```

- The stack array is a genuine variable-length array: `eax = _modeTableCount + 3;
  al &= 0xFC; sub esp, eax`, then `ecx = esp`. The rounding is to 4 bytes.
- `setnb` makes the comparison **unsigned**.
- **This method does not log.** Its Cirrus counterpart logs
  `"Selected mode not supported."` here; this one leaves all reporting to
  `initFromDeviceDescription:`.
- **DriverKit calls:** `objc_msgSend` to `selectMode:count:valid:` — the
  three-argument `IOFrameBufferDisplay` variant. Nothing else.
- **I/O ports / PCI / CMOS / SMAPI:** none.
- **Callers:** `initFromDeviceDescription:`. **Callees:** none in this binary.
- **`__const`/`__data` read:** `_modeTableCount` (three separate loads) and the
  address of `_ThinkPad760EDModeTable`.

### 5. `-[IBMThinkPad760EDDisplayDriver defaultMode]` — 1080, 102 bytes

```c
- (int)defaultMode
{
    int best = _defaultMode;            /* 0 */

    for (i = 0; i < _modeTableCount; i++) {
        IODisplayInfo *m = &_ThinkPad760EDModeTable[i];
        if (self->displayMemorySize < m->rowBytes * m->height)  continue;
        if (self->LCDWidth != ((unsigned char *)m->parameters)[0] - 1) continue;
        best = i;
    }
    return best;
}
```

- **The loop keeps overwriting `best`, so the *last* matching entry wins** — the
  highest-numbered mode that both fits in memory and matches the panel. There is
  no early exit.
- `LCDWidth` is compared against `parameters->panelSize - 1`, which is what
  fixes `LCDWidth` as a 0-based panel index rather than a pixel width; SMAPI
  hands it over 0-based in `reportSystemConfiguration` and the mode records
  store it 1-based.
- **I/O ports / PCI / CMOS / SMAPI:** none. **DriverKit calls:** none.
- **Callers:** `initFromDeviceDescription:`. **Callees:** none.
- **`__const`/`__data` read:** `_defaultMode` (20044), `_modeTableCount` (twice),
  `_ThinkPad760EDModeTable`, and each entry's `parameters` pointer.

### 6. `-[IBMThinkPad760EDDisplayDriver enterLinearMode]` — 1184, 626 bytes

One of the two functions carrying most of the risk in this reconstruction.

```c
- (void)enterLinearMode
{
    const thinkpadMode_t *p = [self displayInfo]->parameters;
    unsigned int regs[16];

    if (self->currentState == 1) return;             /* already linear */
    self->currentState = 1;

    /* 1. Tell SMM which panel geometry is coming. */
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x100B; self->reg.cx.x = p->panelSize;
    smapi_asm(&self->reg);                            /* result not checked */

    /* 2. Set the refresh rate. */
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x1009; self->reg.cx.x = (p->panelSize << 8) | p->refresh;
    smapi_asm(&self->reg);
    if (self->reg.ax.b.h != 0)
        IOLog("%s: Unable to set refresh rate using SMAPI\n", [self name]);

    /* 3. Set the mode, Trident BIOS first, VESA BIOS as fallback. */
    if (self->BiosType == 1) {
        bzero(regs, 64);
        regs[0] = 0x1200;                             /* eax */
        regs[3] = (p->tvgaMode << 8) | 0x14;          /* ebx: BH = mode, BL = 0x14 */
        regs[1] = [self displayInfo]->refreshRate;    /* ecx */
        [self->bios int10:regs outregs:regs iorange:0 ionum:0 smmport:self->smapiPort];
        if ((regs[0] >> 8) & 0xFF)
            IOLog("%s: TVGA BIOS SetMode failure (%04x)\n", [self name], regs[0] & 0xFFFF);
    } else {
        bzero(regs, 64);
        regs[0] = 0x4F02;                             /* eax: VBE set mode */
        regs[3] = p->vesaMode;                        /* ebx */
        [self->bios int10:regs outregs:regs iorange:0 ionum:0 smmport:self->smapiPort];
        if ((regs[0] & 0xFFFF) != 0x004F)
            IOLog("%s: Vesa BIOS SetMode failure (%04x)\n", [self name], regs[0] & 0xFFFF);
    }

    /* 4. Enable linear addressing. */
    [self unlockRegisters];
    outw(0x3D4, 0x2021);                              /* CR21 = 0x20 */
    [self lockRegisters];

    /* 5. Clear the aperture and load the DAC. */
    bzero(self->virtualAddress, self->displayMemorySize);
    [self setGammaTable];

    /* 6. Start the 5-5-5 keeper thread if this is a 15bpp mode on the panel. */
    if ([self displayInfo]->bitsPerPixel == IO_15BitsPerPixel &&
        self->crtOnlyDisplay == 0) {
        self->mode555_thread_enable = 1;
        if (self->mode555_thread == 0) {
            self->mode555_thread = IOForkThread(set555Mode,
                                                &self->mode555_thread_enable);
            IOSetThreadPriority(self->mode555_thread, 0);
        }
    }
}
```

- **`parameters` is loaded before the `currentState` guard**, at 1210, and the
  guard is tested at 1216. That is a compiler scheduling artefact of a source
  that reads `[self displayInfo]->parameters` into a local before the `if`; it
  means the `displayInfo` message is sent even on the early-return path.
- **The two `IOLog` failure messages differ in their success test.** The Trident
  path fails when `AH != 0`; the VESA path fails when `AX != 0x004F`. Both print
  the full 16-bit `AX`.
- **`regs[1]` is loaded from a *second* `[self displayInfo]` send**, not from the
  one at the top of the method. Two `displayInfo` sends in the Trident path,
  three in the method overall.
- **I/O ports:** `0x3D4` word write only (`CR21 = 0x20`), between
  `unlockRegisters` and `lockRegisters`. Everything else is BIOS or SMM.
- **SMAPI functions:** `BX = 0x100B` (panel geometry, unchecked) and
  `BX = 0x1009` (refresh rate, checked).
- **DriverKit calls:** `objc_msgSend` to `displayInfo` (×3), `name` (×3),
  `int10:outregs:iorange:ionum:smmport:`, `unlockRegisters`, `lockRegisters`,
  `setGammaTable`; direct calls to `_smapi_asm` (×2), `_bzero` (×3), `IOLog`
  (×3 — at 1384, 1630 and the tail-merged arm at 1531, so only two
  `call _IOLog` instructions), `_IOForkThread`, `_IOSetThreadPriority`.
- **Callers:** none in this binary; called by the window server through
  `IOFrameBufferDisplay`. **Callees:** as above, plus `_set555Mode` by address.
- **`__const`/`__data` read:** the mode-parameter record through
  `displayInfo->parameters`; the address of `_set555Mode`; `_xxx.89` is
  incremented by the single `outw`.
- **The order is load-bearing:** panel geometry, then refresh, then mode set,
  then CR21, then clear, then gamma, then the thread. Clearing before the gamma
  load means the screen is blank while the palette is still the old one.
- **`IOSetThreadPriority` is inside the `mode555_thread == 0` guard**, so it runs
  only on the first fork. A second `enterLinearMode` sets the enable byte and
  leaves the existing thread's priority alone.
- **Inference:** `BL = 0x14` in the Trident call is a Trident-specific
  `INT 10h AH=12h` subfunction taking the mode in `BH` and the refresh rate in
  `CX`. The register placement is observed; the naming is not, and no Trident
  documentation is quoted here.

### 7. `-[IBMThinkPad760EDDisplayDriver revertToVGAMode]` — 1812, 215 bytes

```c
- (void)revertToVGAMode
{
    unsigned int regs[16];

    self->currentState = 0;

    if (self->mode555_thread != 0) {
        self->mode555_thread_enable = 0;
        for (i = 0; i <= 2999; i++) {
            if (self->mode555_thread_enable == 2) break;
            IOSleep(1);
        }
    }

    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x100B; self->reg.cx.x = 1;
    smapi_asm(&self->reg);                       /* result not checked */

    bzero(regs, 64);
    regs[0] = 3;                                 /* INT 10h AX=0003: 80x25 text */
    [self->bios int10:regs outregs:regs iorange:0 ionum:0 smmport:self->smapiPort];

    [super revertToVGAMode];
}
```

- **There is no `currentState` guard** — the method runs unconditionally, even
  if `currentState` is already 0.
- **The thread is parked, not killed.** `mode555_thread` is left non-zero, so a
  later `enterLinearMode` reuses it. The handshake is: write 0, then poll for the
  thread to write 2, at most 3000 times with a 1 ms sleep between polls — about
  three seconds worst case. The test happens *before* the first sleep, so a
  thread that has already stopped costs nothing.
- **SMAPI function `BX = 0x100B` with `CX = 1`** — the same function
  `enterLinearMode` uses to announce the panel geometry, here with the 640×480
  index, restoring the panel to its VGA geometry. Result unchecked.
- **I/O ports:** none directly. **PCI/CMOS:** none.
- **DriverKit calls:** `objc_msgSend` to `int10:outregs:iorange:ionum:smmport:`;
  `objc_msgSendSuper` to `revertToVGAMode`; direct `_smapi_asm`, `_bzero`,
  `_IOSleep`.
- **Callers:** none in this binary. **Callees:** as above.
- **`__const`/`__data`:** none.
- **Observation:** the stack register block is 64 bytes but the frame reserves
  0x48; `var_40` is the block and `var_48` is the two-word `objc_super` struct
  for the super-send.

### 8. `-[IBMThinkPad760EDDisplayDriver getModeInfo:]` — 2028, 168 bytes

```c
- (BOOL)getModeInfo:(unsigned int)mode
{
    unsigned int regs[16];
    unsigned int seg;
    unsigned char *buf;

    bzero(regs, 64);
    regs[0] = 0x4F01;                        /* eax: VBE Get Mode Info */
    regs[1] = mode;                          /* ecx */
    seg = [self->bios scratchSegment];
    regs[10] = seg;                          /* es */
    regs[7]  = 0;                            /* edi */
    buf = [self->bios realToVirtual:seg :0];
    bzero(buf, 256);
    [self->bios int10:regs outregs:regs iorange:0 ionum:0 smmport:self->smapiPort];
    return ((regs[0] & 0xFFFF) == 0x004F) && (buf[0] & 1);
}
```

- `buf[0] & 1` is bit 0 of the VBE `ModeAttributes` word — "mode supported in
  hardware". Only that bit is examined; the other 255 bytes of the returned
  block are ignored.
- **This is the only in-scope function that uses `scratchSegment` and
  `realToVirtual::`.** Both are deferred `vidBIOS` methods, so this method cannot
  be exercised until drvVGA lands them.
- **I/O ports / PCI / CMOS / SMAPI:** none. `smapiPort` is passed to the BIOS
  call as `smmport` but no SMAPI trap is issued here.
- **DriverKit calls:** `objc_msgSend` to `scratchSegment`, `realToVirtual::` and
  `int10:outregs:iorange:ionum:smmport:`; direct `_bzero` twice.
- **Callers:** `setPendingDisplayMode:`, which passes
  `parameters->vesaMode`. **Callees:** as above.
- **`__const`/`__data`:** none.
- **Observation:** the `es` slot is written at index 10 and `edi` at index 7,
  which is what independently confirms this driver uses the same `emu486`
  register-block layout that `drvVGA/reconstruction/divergences.md` derived from
  `VGA_reloc`. `regs[1] = mode` at index 1 confirms `ecx`, since VBE 0x4F01 takes
  the mode in `CX`.

### 9. `-[IBMThinkPad760EDDisplayDriver determineConfiguration:]` — 2196, 395 bytes

Trident detection and DRAM sizing.

```c
- (BOOL)determineConfiguration:deviceDescription      /* argument unused */
{
    unsigned char sr08, sr09, sr0b;

    outb(0x3C4, 0x08); sr08 = inb(0x3C5);
    outb(0x3C4, 0x09); sr09 = inb(0x3C5);
    outb(0x3C4, 0x0B); sr0b = inb(0x3C5);        /* the read switches to new mode */

    if ((signed char)sr08 >= 0) {
        outw(0x3C4, (sr0b << 8) | 0x0B);          /* SR0B = old value */
        outw(0x3D4, 0x042A);                      /* CR2A = 0x04 */
        if (sr0b != 0xD3) {
            IOLog("%s: Trident Cyber938x not detected - trying anyway\n", [self name]);
            IOLog("%s: Chip ID=0x%02x, Revision=0x%02x\n", [self name], sr0b, sr09);
            self->displayMemorySize = 0x100000;
            goto report;
        }
    }

    IOLog("%s: Detected Trident Cyber938x (rev 0x%02x)\n", [self name], sr09);
    self->BiosType = 1;

    outb(0x3D4, 0x1F);
    switch (inb(0x3D5) & 7) {
    case 5:  self->displayMemorySize = 0x400000; break;   /* 4 MB */
    case 7:  self->displayMemorySize = 0x200000; break;   /* 2 MB */
    default: self->displayMemorySize = 0x100000; break;   /* 1 MB */
    }

report:
    IOLog("%s: Found %d MB DRAM\n", [self name], self->displayMemorySize >> 20);
    return YES;
}
```

**I/O ports touched, in order:** `0x3C4`/`0x3C5` byte pairs for SR08, SR09 and
SR0B; then, on the "old mode" path only, a word write to `0x3C4` restoring SR0B
and a word write to `0x3D4` setting CR2A to 0x04; then, on the detected path, a
byte write to `0x3D4` and a byte read from `0x3D5` for CR1F. **PCI / CMOS /
SMAPI:** none.

**Callers:** `initFromDeviceDescription:`, before `super`. **Callees:** none in
this binary; `name` four times by message send, `_IOLog` four call sites.

**`__const`/`__data`:** none read. Increments `_xxx.86` four times and `_xxx.89`
twice.

Points the rewrite must not smooth over:

- **The `deviceDescription` argument is never used.** No instruction reads
  `[ebp+arg_8]`. The selector takes it, and the caller passes it, but the body
  ignores it. Keep the signature; do not invent a use.
- **`determineConfiguration:` can only return `YES`.** There is a single `mov
  eax, 1` before the epilogue and no other return path — unlike its Cirrus
  namesake, which returns `NO` when the chip key check fails. The
  "not detected" branch logs and carries on with 1 MB. Its caller nonetheless
  tests the result.
- **The `SR08` sign test selects between two detection protocols.** Bit 7 of
  SR08 set means the chip is already in "new mode", so the SR0B restore and the
  CR2A write are skipped and detection is taken as successful without ever
  comparing the chip ID. Bit 7 clear means "old mode": SR0B is written back,
  CR2A is set, and only then is `sr0b == 0xD3` used as the identity test. **A
  chip that reports SR08 bit 7 set is therefore never checked against 0xD3 and
  always takes the `BiosType = 1` path.**
- **The DRAM decode is not monotonic**: CR1F low three bits of 5 give 4 MB and 7
  gives 2 MB, with everything else — 0, 1, 2, 3, 4 and 6 — giving 1 MB. The
  emitted dispatch is `cmp 5 / je`, `jle` to the 1 MB arm, `cmp 7 / je`, fall
  through to the 1 MB arm; reproduce the values, not a tidied-up table.
- **`%d MB` is `displayMemorySize >> 20`**, a plain shift with no rounding.
- At 2366–2372 the chip ID is masked to a byte and stored to a stack slot that is
  never read again — a dead store, a compiler artefact of the value also being
  pushed as an argument. Do not try to reproduce it.
- **Inference:** `0xD3` is the Trident Cyber938x chip identifier and CR1F's low
  nibble is its memory-size field. Neither is stated by the binary; the log
  strings name the part and the values are consistent with that reading.

### 10. `-[IBMThinkPad760EDDisplayDriver isValidPCIAssignedBaseAddress:]` — 2592, 29 bytes

```c
- (BOOL)isValidPCIAssignedBaseAddress:(void *)address
{
    return ((unsigned int)address > 0x7FFFFF);
}
```

- Unsigned comparison (`ja`). Returns `YES` for any address at or above 8 MB,
  rejecting a base address the BIOS left inside the low 8 MB where main memory
  lives. **Byte-for-byte the same test as the Cirrus driver's method of the same
  name**, which is 29 bytes there too.
- The type encoding declares the argument `^v`, a `void *`, though it is only
  ever compared as an integer.
- **I/O ports / PCI / CMOS / SMAPI:** none — despite the name, this inspects a
  value its caller already read.
- **Callers:** `setPCIConfiguration`. **Callees:** none.
- **`__const`/`__data`:** none.

### 11. `-[IBMThinkPad760EDDisplayDriver setPCIConfiguration]` — 2624, 674 bytes

```c
- (BOOL)setPCIConfiguration
{
    unsigned char        config[256];   /* IOPCIConfigSpace */
    IORange              local[3];
    unsigned char        dev, func, bus;
    unsigned int         command;
    IODeviceDescription *dd = [self deviceDescription];
    IORange             *ranges;
    int                  n;

    if ([dd getPCIdevice:&dev function:&func bus:&bus] != 0) {
        IOLog("%s: Error: Unsupported PCI hardware\n", [self name]);
        return NO;
    }

    [[self class] getPCIConfigData:&command atRegister:4 withDeviceDescription:dd];
    [[self class] setPCIConfigData:(command & ~3) atRegister:4 withDeviceDescription:dd];

    [self getPCIConfigSpace:config];
    self->physicalAddress = *(unsigned int *)(config + 16);       /* BAR0 */
    self->physicalAddress &= ~0x0Fu;

    if ([self isValidPCIAssignedBaseAddress:(void *)self->physicalAddress]) {
        ranges = [dd memoryRangeList];
        n      = [dd numMemoryRanges];
        if (n != 3) {
            IOLog("%s: Error: Incorrect number of address ranges: %d.\n", [self name], n);
            return NO;
        }
        for (i = 0; i < n; i++) local[i] = ranges[i];
        local[0].start = self->physicalAddress;
        if ([dd setMemoryRangeList:local num:3] != 0) {
            IOLog("%s: Error: Can't set memory range, using default.\n", [self name]);
            for (i = 0; i < n; i++) local[i] = ranges[i];
            self->physicalAddress = local[0].start;
            if ([dd setMemoryRangeList:local num:3] != 0) {
                IOLog("%s: Error: Can't set to default range either!\n", [self name]);
                return NO;
            }
        }
    } else {
        self->physicalAddress = [dd memoryRangeList][0].start;
        *(unsigned int *)(config + 16) = self->physicalAddress;
        [self setPCIConfigSpace:config];
    }

    [[self class] setPCIConfigData:(command | 3) atRegister:4 withDeviceDescription:dd];
    return YES;
}
```

- **PCI registers:** only register **4**, the Command/Status register, read once
  and written twice — cleared of bits 0 and 1 (I/O space and memory space
  decode) around the reconfiguration, then restored with both bits **set**,
  regardless of what they were. The second write uses the *original* value read
  at the top, not a re-read. Base address register 0 is reached as bytes 16–19 of
  the 256-byte config-space image, never by register number.
- **`getPCIConfigData:` and `setPCIConfigData:` are sent to `[self class]`**, not
  to `self` and not to the device description — `objc_msgSend(self, @selector(class))`
  first, then `objc_msgSend(result, …)`. `getPCIConfigSpace:` and
  `setPCIConfigSpace:` are sent to `self`.
- **The success convention is inverted between the two families.**
  `getPCIdevice:function:bus:` and `setMemoryRangeList:num:` return **0 on
  success**; the code branches to the error arm when the result is non-zero.
- **`dev`, `func` and `bus` are write-only.** Three stack bytes are passed by
  address and never read again — the same dead pattern as the Cirrus driver,
  except that this driver does not even log them.
- **The retry copies the ranges a second time from `[dd memoryRangeList]`,** and
  the second copy takes `physicalAddress` *from* `local[0].start` rather than
  writing it. So the fallback abandons the PCI-assigned base and adopts the
  config table's.
- **The invalid-base arm falls through to the common tail**, so `command | 3` is
  written on both the valid and the invalid path; only the two `Can't set …`
  arms and the `Unsupported PCI hardware` arm return `NO`, and all three of those
  leave the Command register with bits 0 and 1 **clear**.
- **I/O ports / CMOS / SMAPI:** none.
- **DriverKit calls:** `objc_msgSend` to `deviceDescription`, `class` (×3),
  `getPCIdevice:function:bus:`, `getPCIConfigData:atRegister:withDeviceDescription:`,
  `setPCIConfigData:atRegister:withDeviceDescription:` (×2), `getPCIConfigSpace:`,
  `setPCIConfigSpace:`, `isValidPCIAssignedBaseAddress:`, `memoryRangeList` (×2),
  `numMemoryRanges`, `setMemoryRangeList:num:` (×2), `name` (×4); four `IOLog`s
  — at 3031, 3127, 3162 and the tail-merged arm at 2719, so only three
  `call _IOLog` instructions.
- **Callers:** `initFromDeviceDescription:`. **Callees:**
  `isValidPCIAssignedBaseAddress:` by message send.
- **`__const`/`__data` read:** four `__cstring` entries. `physicalAddress` is
  written three times on the valid path (raw BAR, masked BAR, and possibly the
  fallback) and twice on the invalid path.
- **Observation:** the frame is 0x124 bytes because `config` alone is 256; the
  three `IORange` land at `ebp-0x18` and the config image at `ebp-0x118`.

### 12. `-[IBMThinkPad760EDDisplayDriver setPendingDisplayMode:]` — 3300, 544 bytes

The mode-validation gate, and the other function carrying most of the risk.

```c
- (BOOL)setPendingDisplayMode:(int)mode
{
    const thinkpadMode_t *p = _ThinkPad760EDModeTable[mode].parameters;
    unsigned int savedState = 0;
    char         crtOnly    = 0;

    if (mode < 0)                                                return NO;
    if (mode >= _modeTableCount)                                 return NO;
    if (_ThinkPad760EDModeTable[mode].modeUnavailableFlag != 0)  return NO;

    if (self->LCDWidth < (unsigned)(p->panelSize - 1)) {
        crtOnly = 1;
        self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
        self->reg.bx.x = 0x0002; self->reg.cx.x = 0x0200;
        smapi_asm(&self->reg);
        if (self->reg.cx.b.h == 0) return NO;       /* no external display attached */
    }

    if (crtOnly) {
        savedState = [self getDisplayDeviceState];
        if (savedState != 2)
            [self setDisplayDeviceState:2];         /* CRT only */
    }

    if (![self getModeInfo:p->vesaMode]) {
        if (crtOnly) [self setDisplayDeviceState:savedState];
        return NO;
    }

    self->crtOnlyDisplay = crtOnly;

    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x100D;
    self->reg.cx.x = crtOnly ? 0x0101 : self->viewportSize;
    smapi_asm(&self->reg);

    self->reg.cx.x = p->panelSize;
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x100B;
    smapi_asm(&self->reg);

    _ThinkPad760EDModeTable[mode].frameBuffer = self->virtualAddress;

    if (![super setPendingDisplayMode:mode]) return NO;
    self->modeIndex = mode;
    return YES;
}
```

- **`parameters` is fetched before the range checks**, at 3322, indexing
  `_ThinkPad760EDModeTable` with an unvalidated `mode`. That is an out-of-bounds
  read for a negative or oversized argument, but the value is unused on those
  paths. It is a compiler scheduling artefact of a source that declares and
  initializes the local first; reproduce the source shape, not the hazard.
- **The panel-fit test is `LCDWidth < panelSize - 1`, unsigned (`jnb`).** If the
  requested mode is wider than the built-in panel, the driver needs an external
  monitor, so it asks SMAPI function `BX = 0x0002` with `CX = 0x0200` and
  requires `CH != 0`.
- **`getDisplayDeviceState`'s value 2 means "CRT only".** The saved state is
  restored only on the `getModeInfo:` failure path, and only when `crtOnly` was
  set. On success the state stays as set.
- **SMAPI function `BX = 0x100D` takes `CX = 0x0101` in CRT-only mode and
  `CX = self->viewportSize` otherwise.** `viewportSize` is whatever
  `reportSystemConfiguration` read back from function `0x100C`, or `0x0204` if
  that call failed.
- **Neither `0x100D` nor the following `0x100B` call is error-checked.**
- **The `0x100B` call reuses `reg` without resetting `bx` first** — `cx` is
  written, then `ax`, `dx` and `bx`. The emitted order is `cx`, `ax`, `dx`, `bx`;
  the effect is the same but the store order is visible in the disassembly.
- **`frameBuffer` is written into the *table*, not into `[self displayInfo]`.**
  The store at 3779 targets `_ThinkPad760EDModeTable[mode] + 20`.
- **`modeIndex` is set only after `super` accepts**, so a rejected mode leaves
  the ivar alone. Note that `initFromDeviceDescription:` also assigns `modeIndex`
  directly, before calling this method.
- **I/O ports:** none. **PCI/CMOS:** none. **SMAPI functions:** `0x0002`
  (conditionally), `0x100D`, `0x100B`.
- **DriverKit calls:** `objc_msgSend` to `getDisplayDeviceState`,
  `setDisplayDeviceState:` (×2) and `getModeInfo:`; `objc_msgSendSuper` to
  `setPendingDisplayMode:`; direct `_smapi_asm` (×3). **No `IOLog` at all** —
  every rejection is silent, which is why `initFromDeviceDescription:` has to log
  on its behalf.
- **Callers:** `initFromDeviceDescription:`, and the window server through
  `IOFrameBufferDisplay`. **Callees:** `getDisplayDeviceState`,
  `setDisplayDeviceState:`, `getModeInfo:`, `_smapi_asm`.
- **`__const`/`__data`:** reads `_modeTableCount` and three fields of
  `_ThinkPad760EDModeTable[mode]` (`parameters`, `modeUnavailableFlag`,
  and writes `frameBuffer`).
- **Inference:** SMAPI `BX = 0x0002` with `CX = 0x0200` is a display-device
  query whose `CH` reports attached devices. Only the "`CH` must be non-zero"
  behaviour is observed; the function's name and its full return semantics are
  not in the binary.

### 13. `-[IBMThinkPad760EDDisplayDriver getDisplayDeviceState]` — 3844, 81 bytes

```c
- (unsigned int)getDisplayDeviceState
{
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x1000; self->reg.cx.x = 0;
    smapi_asm(&self->reg);
    return (self->reg.cx.x >> 8) & 3;
}
```

- **The result is not error-checked** — `AH` is never tested, so a failed SMAPI
  call returns whatever `CH` happened to hold.
- The two surviving bits are the LCD and CRT enables; the caller compares against
  the literal 2.
- **SMAPI function:** `BX = 0x1000`. **I/O ports / PCI / CMOS:** none.
- **DriverKit calls:** none — direct `_smapi_asm` only.
- **Callers:** `setPendingDisplayMode:`. **Callees:** `_smapi_asm`.
- **`__const`/`__data`:** none.

### 14. `-[IBMThinkPad760EDDisplayDriver setDisplayDeviceState:]` — 3928, 80 bytes

```c
- (void)setDisplayDeviceState:(unsigned int)state
{
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x1001;
    self->reg.cx.x = (((state & 3) | 0x80) << 8);
    smapi_asm(&self->reg);
}
```

- The emitted sequence is `ax = state; ax &= 3; ax <<= 8; … ah |= 0x80`, so
  `CH = 0x80 | (state & 3)` and `CL = 0`. The 0x80 bit is a "commit" flag.
- **No error check.** The method returns `void` per its type encoding
  `v12@8:12I16`.
- **SMAPI function:** `BX = 0x1001`. **I/O ports / PCI / CMOS:** none.
- **DriverKit calls:** none — direct `_smapi_asm` only.
- **Callers:** `setPendingDisplayMode:`, twice. **Callees:** `_smapi_asm`.
- **`__const`/`__data`:** none.

### 15. `-[IBMThinkPad760EDDisplayDriver unlockRegisters]` — 4008, 166 bytes

```c
- (void)unlockRegisters
{
    outb(0x3C4, 0x08);
    if ((signed char)inb(0x3C5) >= 0) {         /* old mode */
        outb(0x3C4, 0x0B); (void)inb(0x3C5);    /* switch to new mode */
        outb(0x3C4, 0x0E); outb(0x3C5, inb(0x3C5) | 0x80);
        outw(0x3C4, 0x000B);                    /* SR0B = 0: back to old mode */
    } else {                                    /* already new mode */
        outb(0x3C4, 0x0E); outb(0x3C5, inb(0x3C5) | 0x80);
    }
}
```

- **I/O ports:** `0x3C4`/`0x3C5` only. SR08 bit 7 selects the protocol, exactly
  as in `determineConfiguration:`; SR0E bit 7 is the protection bit being set.
- **PCI / CMOS / SMAPI:** none. **DriverKit calls:** none, no message send, no
  import.
- **Callers:** `enterLinearMode`. **Callees:** none.
- **`__const`/`__data`:** increments `_xxx.86` four times on the old-mode path
  (three on the new-mode path) and `_xxx.89` once on the old-mode path.
- **The `outw(0x3C4, 0x000B)` writes SR0B := 0**, not SR0B := its previous value.
  `determineConfiguration:` restores the read-back value; this method writes
  zero. That asymmetry is in the binary.
- The `mov ebx, 3C5h; mov edx, 3C5h` pair at 4075/4080 is a register-allocation
  artefact of the `inb`/`outb` inline asm operands, not two different ports.

### 16. `-[IBMThinkPad760EDDisplayDriver lockRegisters]` — 4176, 166 bytes

Byte-for-byte `unlockRegisters` with one instruction changed: `and cl, 0x7F`
where the other has `or cl, 0x80`. Same two protocols, same port sequence, same
`outw(0x3C4, 0x000B)` on the old-mode path, same counter increments, same size.

- **Callers:** `enterLinearMode`. **Callees:** none.
- The rewrite should keep them as two separate methods rather than factoring out
  a shared helper with a mask argument: the reference emits two independent
  166-byte bodies.

### 17. `-[IBMThinkPad760EDDisplayDriver free]` — 4344, 89 bytes

```c
- free
{
    if (self->redTransferTable != 0) {
        IOFree(self->redTransferTable, self->transferTableCount * 3);
        self->redTransferTable = 0;
    }
    return [super free];
}
```

- **One allocation, not three.** `red`, `green` and `blue` are three pointers
  into one `3 * transferTableCount` block whose head is `red`, so only `red` is
  freed and only `red` is nulled. `green` and `blue` are left dangling; nothing
  reads them afterwards.
- The size is computed as `lea eax, [eax+eax*2]`.
- **DriverKit calls:** `_IOFree`; `objc_msgSendSuper` to `free`.
- **I/O ports / PCI / CMOS / SMAPI:** none.
- **Callers:** `initFromDeviceDescription:` on every failure path. **Callees:**
  `IOFrameBufferDisplay`'s `free`.
- **`__const`/`__data`:** none.
- **Observation:** `free` does *not* free `self->bios`, does not stop the 5-5-5
  thread and does not unmap the frame buffer. Whatever cleanup those need is left
  to `super`, or does not happen.

### 18. `-[IBMThinkPad760EDDisplayDriver displayModeCount]` — 4436, 12 bytes

```c
- (unsigned int)displayModeCount { return _modeTableCount; }
```

- Reads `_modeTableCount` (20048) directly, not an ivar. **Callers:** none in
  this binary; `IOFrameBufferDisplay`. **Callees:** none. No ports, no PCI, no
  SMAPI, no DriverKit call.

### 19. `-[IBMThinkPad760EDDisplayDriver displayModes]` — 4448, 12 bytes

```c
- (IODisplayInfo *)displayModes { return _ThinkPad760EDModeTable; }
```

- Returns the address of `_ThinkPad760EDModeTable` (24576) as an immediate. This
  is the instruction Ghidra's normalization chokes on. **Callers:** none in this
  binary. **Callees:** none.

### 20. `-[IBMThinkPad760EDDisplayDriver displayMemorySize]` — 4460, 16 bytes

```c
- (unsigned int)displayMemorySize { return self->displayMemorySize; }
```

- Plain ivar accessor for offset 572. **Callers:** none in this binary.

### 21. `-[IBMThinkPad760EDDisplayDriver ramdacSpeed]` — 4476, 9 bytes

```c
- (unsigned int)ramdacSpeed { return 0; }
```

- `xor eax, eax` and nothing else. The Cirrus driver's `ramdacSpeed` is also a
  constant. **Callers:** none in this binary.

### 22. `-[IBMThinkPad760EDDisplayDriver readCMOS:]` — 4488, 71 bytes

```c
- (unsigned short)readCMOS:(unsigned char)index
{
    unsigned char value;

    asm volatile("cli");
    outb(0x70, index | 0x80);
    value = inb(0x71);
    outb(0x70, 0x0F);
    (void)inb(0x71);
    asm volatile("sti");
    return value;
}
```

- **I/O ports:** `0x70` (CMOS index) and `0x71` (CMOS data), two writes and two
  reads. **PCI / SMAPI:** none.
- **`cli` and `sti` are emitted inline**, bare, with no surrounding save of the
  interrupt flag. They cannot come from `outb()`; the source has its own inline
  asm or macro for them. **Inference:** the pair brackets the whole index/data
  transaction so no other CMOS user can interleave.
- **The `| 0x80` on the index disables NMI** while the access is in flight — the
  conventional meaning of bit 7 of port 0x70.
- **The trailing `outb(0x70, 0x0F)` and discarded read** reset the index register
  to the shutdown-status byte, the conventional "leave it somewhere harmless"
  idiom. The read result is discarded; only the first read is returned.
- The return type is `unsigned short` (`S9@8:12C16`) but only a byte is ever
  produced; the caller shifts one result left by 8 and ors in the other.
- **DriverKit calls:** none. **Callers:** `initFromDeviceDescription:`, twice,
  with 0x7E and 0x7F. **Callees:** none.
- **`__const`/`__data`:** increments `_xxx.86` twice.

### 23. `-[IBMThinkPad760EDDisplayDriver reportSystemConfiguration]` — 4560, 1088 bytes

The largest function in either driver. It is six SMAPI queries in sequence, each
guarding its own `IOLog`s, plus two ivar side effects. **The call sequence below
was read from the disassembly, not inferred from the format strings**, and the
argument order in each `IOLog` was taken from the push order.

```c
- (void)reportSystemConfiguration
{
    /* 1. BX = 0x0000 — system identity */
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x0000; self->reg.cx.x = 0;
    smapi_asm(&self->reg);
    if (self->reg.ax.b.h == 0) {
        IOLog("%s: System ID = 0x%04x\n", [self name], self->reg.bx.x);
        IOLog("%s: System BIOS revision %01x.%02x\n", [self name],
              self->reg.dx.b.h + 1, self->reg.dx.b.l);
        if (self->reg.si.x != 0xFFFF)
            IOLog("%s: System management BIOS revision %01x.%02x\n", [self name],
                  self->reg.si.b.h, self->reg.si.b.l);
        IOLog("%s: SMAPI revision %01x.%02x\n", [self name],
              self->reg.di.b.h, self->reg.di.b.l);
    }

    /* 2. BX = 0x0008 — video BIOS revision */
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x0008; self->reg.cx.x = 0;
    smapi_asm(&self->reg);
    if (self->reg.ax.b.h == 0)
        IOLog("%s: Video BIOS revision %01x.%02x\n", [self name],
              self->reg.bx.b.h, self->reg.bx.b.l);

    /* 3. BX = 0x0006 — slave controller revision */
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x0006; self->reg.cx.x = 0;
    smapi_asm(&self->reg);
    if (self->reg.ax.b.h == 0 && self->reg.cx.x != 0xFFFF)
        IOLog("%s: Slave controller revision %01x.%02x\n", [self name],
              self->reg.cx.b.h, self->reg.cx.b.l);

    /* 4. BX = 0x0001 — CPU identity and clocks */
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x0001; self->reg.cx.x = 0;
    smapi_asm(&self->reg);
    if (self->reg.ax.b.h == 0) {
        switch (self->reg.bx.b.l) {
        case 1:  vendor = "Intel";   break;
        case 2:  vendor = "AMD";     break;
        default: vendor = "Unknown"; break;
        }
        IOLog("%s: %s CPU Family %d, Model %d, Stepping %d\n", [self name], vendor,
              self->reg.cx.b.h, self->reg.cx.b.l >> 4, self->reg.cx.b.l & 0x0F);
        IOLog("%s: CPU clock (Int/Ext) = ", [self name]);
        if (self->reg.dx.b.l != 0xFF) IOLog("%d", self->reg.dx.b.l);
        else                          IOLog("?");
        if (self->reg.dx.b.h != 0xFF) IOLog("/%d MHz\n", self->reg.dx.b.h);
        else                          IOLog("/? MHz\n");
    }

    /* 5. BX = 0x0002, CX = 0x0100 — panel identity */
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x0002; self->reg.cx.x = 0x0100;
    smapi_asm(&self->reg);
    if (self->reg.ax.b.h == 0) {
        switch (self->reg.bx.b.h) {
        case 0:  type = "Monochrome STN"; break;
        case 1:  type = "Monochrome TFT"; break;
        case 2:  type = "Color STN";      break;
        case 3:  type = "Color TFT";      break;
        default: type = "Unknown";        break;
        }
        self->LCDWidth = self->reg.bx.b.l;
        switch (self->reg.bx.b.l) {
        case 0:  size = "640x480";  break;
        case 1:  size = "800x600";  break;
        case 2:  size = "1024x768"; break;
        default: size = "Unknown";  break;
        }
        IOLog("%s: %s LCD (%s)\n", [self name], type, size);
    }

    /* 6. BX = 0x100C — current viewport setting */
    self->reg.ax.x = 0x5380; self->reg.dx.x = self->smapiPort;
    self->reg.bx.x = 0x100C; self->reg.cx.x = 0;
    smapi_asm(&self->reg);
    if (self->reg.ax.b.h == 0)
        self->viewportSize = self->reg.cx.x;
}
```

Things a reader of the format strings alone would get wrong, all read from the
instruction stream:

- **The "System BIOS revision" major has `+ 1` added to it** (`inc eax` at 4686)
  and the other four `%01x.%02x` pairs do not. Only that one.
- **The "SMAPI revision" line is *not* inside the `SI != 0xFFFF` guard.** The
  `jz` at 4727 targets the SMAPI-revision block, so a system that reports
  `SI == 0xFFFF` skips the management-BIOS line and still prints the SMAPI line.
- **`SI` and `DI` are read but never written by any caller.** Query 1 is the only
  one whose results include them, and they are whatever the SMAPI call left
  there.
- **The slave-controller line has two guards, `AH == 0` *and* `CX != 0xFFFF`**;
  the video-BIOS line has one; the management-BIOS line has only the `0xFFFF`
  test (its `AH` guard is query 1's).
- **The CPU-clock line is built from three or four separate `IOLog` calls** —
  a prefix with no newline, then either `%d` or `?`, then either `/%d MHz\n` or
  `/? MHz\n`. The `0xFF` sentinel is tested separately for each half.
- **Family, model and stepping come from one byte pair:** family is `CH`, model
  is `CL >> 4`, stepping is `CL & 0x0F`.
- **Query 5's panel type is `BH` and the panel size index is `BL`,** and
  `LCDWidth` is assigned `BL` — the raw 0-based index — between the two switches.
  This is the only place `LCDWidth` is ever written, which is what makes
  `defaultMode`'s and `setPendingDisplayMode:`'s `panelSize - 1` arithmetic
  correct.
- **Query 5 uses `CX = 0x0100`; `setPendingDisplayMode:`'s query of the same
  function 0x0002 uses `CX = 0x0200`.** Same function code, different subfunction
  in `CH`.
- **`Unknown` at 19058 serves three switches** — CPU vendor, panel type and panel
  size — from one string constant.
- **The method returns `void` and never fails.** Every query is independent; a
  failing query skips only its own output.

Summary of the interfaces this function touches: **SMAPI functions `0x0000`,
`0x0008`, `0x0006`, `0x0001`, `0x0002` and `0x100C`**, six `_smapi_asm` calls;
**no I/O port, no PCI register, no CMOS access**; `objc_msgSend` to `name`
nine times; `_IOLog` at thirteen call sites (no arm is tail-merged here, so
thirteen `call _IOLog` instructions too); nineteen `__cstring` references.
**Callers:** `initFromDeviceDescription:`. **Callees:** `_smapi_asm`.
**`__const`/`__data`:** none; it writes `self->LCDWidth` and
`self->viewportSize`.

### 24. `-[IBMThinkPad760EDDisplayDriver name]` — 5648, 59 bytes

```c
- (const char *)name
{
    const char *n = [super name];
    return (n != 0 && *n != 0) ? n : "Display0";
}
```

- Two tests, null and empty. **`__const`/`__data` read:** `"Display0"` at 19252.
- **DriverKit calls:** `objc_msgSendSuper` to `name`.
- **Callers:** almost every other method, as the `%s` argument of every `IOLog`.
  **Callees:** `IODevice`'s `name`.
- The type encoding is `r*8@8:12` — a `const char *`.

### 25. `-[IBMThinkPad760EDDisplayDriver(TransferTable) setTransferTable:count:]` — 5708, 333 bytes

`TransferTable.m` begins here.

```c
- setTransferTable:(const unsigned int *)table count:(int)count
{
    if (self->redTransferTable == 0 || self->transferTableCount != count) {
        if (self->redTransferTable != 0)
            IOFree(self->redTransferTable, self->transferTableCount * 3);
        self->transferTableCount  = count;
        self->redTransferTable    = IOMalloc(count * 3);
        self->greenTransferTable  = self->redTransferTable + count;
        self->blueTransferTable   = self->greenTransferTable + count;
    }

    switch ([self displayInfo]->colorSpace) {
    case IO_OneIsWhiteColorSpace:                       /* 1 */
        for (i = 0; i < count; i++) {
            unsigned char v = ((const unsigned char *)table)[i * 4];
            self->blueTransferTable[i]  = v;
            self->greenTransferTable[i] = v;
            self->redTransferTable[i]   = v;
        }
        break;
    case IO_RGBColorSpace:                              /* 2 */
        for (i = 0; i < count; i++) {
            self->redTransferTable[i]   = table[i] >> 24;
            self->greenTransferTable[i] = table[i] >> 16;
            self->blueTransferTable[i]  = table[i] >> 8;
        }
        break;
    default:
        IOFree(self->redTransferTable, count * 3);
        self->redTransferTable = 0;
        break;
    }

    [self setGammaTable];
    return self;
}
```

- **One `IOMalloc` of `3 * count` bytes serves all three tables**, laid out
  red, green, blue. That is why `free` releases only `red`.
- **The reallocation is skipped when the pointer is live and the count is
  unchanged**, which is the common repaint case.
- The emitted code tests `redTransferTable != 0` **twice** (5720 and 5740); the
  second test can never fail. It is a compiler artefact of a source with two
  separate `if (self->redTransferTable)` statements, and it is not a finding.
- **The greyscale case takes the *low* byte of each entry** (`mov al, [ecx+esi*4]`,
  i.e. `table[i] & 0xFF`) while the RGB case takes bits 31–24, 23–16 and 15–8.
  The low byte is unused by the RGB case and the top three bytes are unused by
  the greyscale case. Reproduce both as written.
- **Both loops use signed comparisons against `count`.**
- **The default arm frees the table it may have just allocated** and leaves
  `red` null, `green` and `blue` dangling, and `transferTableCount` set — so a
  subsequent call with the same count still reallocates, because the `red == 0`
  test fires.
- **DriverKit calls:** `_IOFree` (×2), `_IOMalloc`; `objc_msgSend` to
  `displayInfo` and `setGammaTable`.
- **333 bytes here and 333 bytes in the Cirrus driver's `(ProgramDAC)`
  category.** The two bodies are the same routine; where this one differs, the
  difference is in `IODisplayInfo` field offsets, not in structure.
- **I/O ports / PCI / CMOS / SMAPI:** none.
- **Callers:** none in this binary; the window server through
  `IOFrameBufferDisplay`. **Callees:** `setGammaTable` by message send.
- **`__const`/`__data`:** none.

### 26. `-[IBMThinkPad760EDDisplayDriver(TransferTable) setBrightness:token:]` — 6044, 77 bytes

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

- The comparison is **unsigned** (`ja`), so a negative level is rejected by the
  same test. 64 is accepted.
- **`token` is never read.** It is part of the `IOFrameBufferDisplay` protocol.
- Returns `self` on success and literal `nil` on rejection.
- **DriverKit calls:** `objc_msgSend` to `name` and `setGammaTable`; `_IOLog`.
- **I/O ports / PCI / CMOS / SMAPI:** none.
- **Callers:** none in this binary. **Callees:** `setGammaTable`.
- **`__const`/`__data`:** the brightness message at 19261.
- This is 77 bytes here and 77 bytes in the Cirrus driver's `(ProgramDAC)`
  category, with the same 64-level clamp and the same backtick/quote message —
  the two categories were plainly written from one another.

### 27. `-[IBMThinkPad760EDDisplayDriver(TransferTable) SetGammaValueRed:Green:Blue:Level:]` — 6124, 82 bytes

```c
- (void)SetGammaValueRed:(unsigned int)r Green:(unsigned int)g
                    Blue:(unsigned int)b Level:(int)level
{
    outb(0x3C9, (r * level) >> 8);
    outb(0x3C9, (g * level) >> 8);
    outb(0x3C9, (b * level) >> 8);
}
```

- **I/O ports:** three byte writes to `0x3C9`, the VGA DAC data port. The write
  index was set by the caller. **PCI / CMOS / SMAPI:** none.
- **The multiply is a plain `imul` and the scale is `>> 8`,** so a level of 64
  gives a quarter-intensity ramp and a level of 255 is very nearly unity. There
  is no rounding and no clamp.
- The third `outb` reuses `edx`, already holding 0x3C9, so only two of the three
  `mov edx, 3C9h` appear.
- **The Cirrus driver's equivalent is the file-static C function
  `_SetGammaValue`; here it is a real Objective-C method** with a capitalized
  selector, called by message send 256 times per gamma load. That is a genuine
  structural difference between the two categories, not a naming choice: it is in
  `__OBJC,__cat_inst_meth` with encoding `v24@8:12IIIi`. Both are **82 bytes**,
  and the Cirrus one writes the same three `outb`s to the same DAC data port, so
  the difference really is only C function versus Objective-C method.
- **DriverKit calls:** none. **Callers:** `setGammaTable`, from both of its
  loops. **Callees:** none.
- **`__const`/`__data`:** increments `_xxx.8` at 26584 — `TransferTable.m`'s
  `outb` counter — three times.

### 28. `-[IBMThinkPad760EDDisplayDriver(TransferTable) setGammaTable]` — 6208, 229 bytes

```c
- setGammaTable
{
    IODisplayInfo *info = [self displayInfo];

    outb(0x3C8, 0);                              /* DAC write index := 0 */

    if (self->redTransferTable != 0) {
        for (i = 0; i < self->transferTableCount; i++)
            for (j = 0; j < 256 / self->transferTableCount; j++)
                [self SetGammaValueRed:self->redTransferTable[i]
                                 Green:self->greenTransferTable[i]
                                  Blue:self->blueTransferTable[i]
                                 Level:self->brightnessLevel];
    } else if (info->bitsPerPixel == IO_8BitsPerPixel ||
               info->bitsPerPixel == IO_24BitsPerPixel) {
        for (i = 0; i <= 255; i++)
            [self SetGammaValueRed:_gamma8[i] Green:_gamma8[i]
                              Blue:_gamma8[i] Level:self->brightnessLevel];
    }
    return self;
}
```

- **I/O ports:** one byte write to `0x3C8` (DAC write index), then 768 writes to
  `0x3C9` through `SetGammaValueRed:…`. **PCI / CMOS / SMAPI:** none.
- **The replication factor `256 / transferTableCount` is recomputed with an
  `idiv` on every inner iteration** (6336–6347). It is a signed divide of the
  literal 256. The outer loop's bound uses **unsigned** comparisons (`jbe`/`ja`)
  against `transferTableCount` while the divide is signed — an asymmetry that is
  in the emitted code.
- **The fallback ramp applies to `bitsPerPixel` 1 and 4 only** — `IO_8BitsPerPixel`
  and `IO_24BitsPerPixel`. A 15bpp mode with no transfer table loads nothing.
- **`_gamma8[i]` is used for all three channels.**
- **DriverKit calls:** `objc_msgSend` to `displayInfo` and to
  `SetGammaValueRed:Green:Blue:Level:`.
- **Callers:** `enterLinearMode`, `setTransferTable:count:`,
  `setBrightness:token:`. **Callees:** `SetGammaValueRed:Green:Blue:Level:`.
- **`__const`/`__data` read:** `_gamma8` (19620); increments `_xxx.8` once for
  the index write.
- **Observation:** `[self displayInfo]` is sent unconditionally, before the
  `redTransferTable` test, even though the result is only used in the else arm.

### 29. `_smapi_asm` — 6440, 86 bytes

**Hand-written i386 assembly, and the only assembly translation unit in this
effort's scope.** Its own file, `smapi.s` by convention, occupying `__text`
6440–6528.

```
_smapi_asm:
        push    ebp
        mov     ebp, esp
        push    edi
        push    esi
        push    ebx
        mov     eax, [ebp+8]          ; struct smapiReg *r
        mov     bx,  [eax]            ; r->ax.x
        push    bx                    ; stash it, bx is needed for r->bx
        mov     bx,  [eax+4]          ; r->bx.x
        mov     cx,  [eax+8]          ; r->cx.x
        mov     dx,  [eax+0Ch]        ; r->dx.x  == the SMAPI port
        mov     si,  [eax+10h]        ; r->si.x
        mov     di,  [eax+14h]        ; r->di.x
        pop     ax                    ; ax = r->ax.x
        out     dx,  al               ; --- the trap ---
        out     4Fh, al               ; --- second trap port ---
        push    ax
        mov     eax, [ebp+8]          ; reload, eax was clobbered
        mov     [eax+4],  bx
        mov     [eax+8],  cx
        mov     [eax+0Ch], dx
        mov     [eax+10h], si
        mov     [eax+14h], di
        mov     ebx, eax
        pop     ax
        mov     [ebx], ax
        jmp     .epilogue             ; 6511, two bytes, lands at 6516
        ; 6513-6516: 90 90 90
.epilogue:
        lea     esp, [ebp-0Ch]
        pop     ebx
        pop     esi
        pop     edi
        mov     esp, ebp
        pop     ebp
        ret
```

**The register contract, which a later task must reproduce exactly:**

| Direction | Registers | Source / destination |
| --- | --- | --- |
| in | `AX BX CX DX SI DI` | `r->ax.x … r->di.x`, 16-bit loads from offsets 0, 4, 8, 0x0C, 0x10, 0x14 |
| trap | `out dx, al` then `out 0x4F, al` | `DX` is the SMAPI port; `AL` is `0x80` for every caller in this driver, since every caller sets `AX = 0x5380` |
| out | `BX CX DX SI DI` then `AX` | written back to the same six offsets, 16-bit stores |
| clobbers | `EAX EBX ECX EDX ESI EDI` | `EBX`, `ESI`, `EDI` are saved and restored by the prologue/epilogue |
| returns | nothing | callers read results out of the struct, never out of `eax` |

- **The write-back order matters**: `BX`, `CX`, `DX`, `SI`, `DI` first, then
  `AX` last, because `AX` is spilled across the pointer reload.
- **`out 0x4F, al` is a second, fixed port** issued immediately after the
  port-in-`DX` write, with the same `AL`. **Inference:** the pair is the
  ThinkPad SMM entry handshake — one write to the model-specific SMAPI port and
  one to the fixed one. The binary states only that both writes happen, in that
  order, with the same value.
- **Neither `out` is followed by `lock incl`.** That is a fifth linkage
  observation to set beside the spec's §2.6 three, and the strongest one: every
  `out` emitted from C in this binary carries the `ioPorts.h` counter increment
  and these two do not, so this code was not compiled from C.
- The other four linkage observations, restated with what this pass confirms:
  it sits *after* `TransferTable.m`'s range so it cannot belong to
  `IBMThinkPad760ED.m`; it contributes no `__OBJC,__module_info` record; its
  symbol binding is `external` where every compiler-emitted file-static helper
  in this binary (`_set555Mode`) is `local`; and it is separated from its
  neighbours on both sides by **zero-fill** padding (6437–6440 and 6526–6528),
  which the linker only emits between object files.
- **It nonetheless uses a standard `push ebp / mov ebp, esp` frame and reads its
  argument at `[ebp+8]`,** unlike `_emu486`, which has no frame pointer. So the
  frame-pointer argument in `drvVGA`'s `_emu486` case does not apply here, and
  this routine was written to be callable from C exactly like a compiled
  function.
- The three-byte `90 90 90` at 6513–6516, jumped over by the two-byte `jmp` at
  6511, is intra-function alignment before the epilogue.
- **`binrecon source-map` cannot map 6440, and that is a scanner limitation.**
  `binrecon/source_map.py` globs `*.m` and `*.c` in each `--source-dir`, so it
  never opens `smapi.s` and knows nothing of `.s` definitions; 6440 stays in
  `unmapped` even with the file written and named exactly as the binary names
  it. The symbol must not be renamed to satisfy the tool.
- **Callers:** `initFromDeviceDescription:`, `enterLinearMode` (×2),
  `revertToVGAMode`, `setPendingDisplayMode:` (×3), `getDisplayDeviceState`,
  `setDisplayDeviceState:`, `reportSystemConfiguration` (×6) — fifteen call
  sites, all passing `&self->reg`. **Callees:** none.
- **SMAPI functions requested by those callers**, all with `AX = 0x5380`:

| `BX` | `CX` | Requested by | Checked? |
| --- | --- | --- | --- |
| `0x0000` | 0 | `initFromDeviceDescription:`, `reportSystemConfiguration` | yes, `AH` |
| `0x0001` | 0 | `reportSystemConfiguration` | yes, `AH` |
| `0x0002` | `0x0100` | `reportSystemConfiguration` | yes, `AH` |
| `0x0002` | `0x0200` | `setPendingDisplayMode:` | yes, `CH != 0` |
| `0x0006` | 0 | `reportSystemConfiguration` | yes, `AH` and `CX != 0xFFFF` |
| `0x0008` | 0 | `reportSystemConfiguration` | yes, `AH` |
| `0x1000` | 0 | `getDisplayDeviceState` | no |
| `0x1001` | `(state&3\|0x80)<<8` | `setDisplayDeviceState:` | no |
| `0x1009` | `(panel<<8)\|refresh` | `enterLinearMode` | yes, `AH` |
| `0x100B` | panel index | `enterLinearMode`, `revertToVGAMode`, `setPendingDisplayMode:` | no |
| `0x100C` | 0 | `reportSystemConfiguration` | yes, `AH` |
| `0x100D` | viewport or `0x0101` | `setPendingDisplayMode:` | no |

### 30. `+[IBMThinkPad760EDDisplayDriverKernelServerInstance kernelServerInstance]` — 6528, 12 bytes

**Build-generated.** `IBMThinkPad760EDDisplayDriver_instance.m` begins here.

```c
+ (id *)kernelServerInstance { return &IBMThinkPad760EDDisplayDriver_instance; }
```

- Returns the address of the 4-byte `__DATA,__common` symbol
  `_IBMThinkPad760EDDisplayDriver_instance` (26608) as an immediate.
- Emitted by the Kernel Server project type from
  `Loaded Server,Instance Var`. **Must not be written by hand.**

### 31. `+[IBMThinkPad760EDDisplayDriverVersion driverKitVersionForIBMThinkPad760EDDisplayDriver]` — 6540, 12 bytes

**Build-generated.**

```c
+ (int)driverKitVersionForIBMThinkPad760EDDisplayDriver { return 500; }
```

- `mov eax, 0x1F4`. 500 is the DriverKit version, unrelated to
  `_IBMThinkPad760EDDisplayDriver_VERS_NUM`, which is the string `"7"`.
- **Must not be written by hand.**

## Static storage

`__DATA,__bss` is 36 bytes and holds **nine** symbols under **six distinct
names** — the brief's "six `_xxx.NN` statics" counts names, not symbols. They
are gcc's per-file numbering for the `static int xxx;` inside each of
`ioPorts.h`'s `outb`, `outw` and `outl` inlines, emitted once per translation
unit that includes the header, in link order:

| Address | Symbol | Inline | Owning translation unit | Referenced? |
| --- | --- | --- | --- | --- |
| 26572 | `_xxx.86` | `outb` | `IBMThinkPad760ED.m` | yes — `_set555Mode`, `determineConfiguration:`, `unlockRegisters`, `lockRegisters`, `readCMOS:` |
| 26576 | `_xxx.89` | `outw` | `IBMThinkPad760ED.m` | yes — `determineConfiguration:`, `enterLinearMode`, `unlockRegisters`, `lockRegisters` |
| 26580 | `_xxx.92` | `outl` | `IBMThinkPad760ED.m` | **no** — the driver issues no 32-bit `out` |
| 26584 | `_xxx.8` | `outb` | `TransferTable.m` | yes — `SetGammaValueRed:Green:Blue:Level:`, `setGammaTable` |
| 26588 | `_xxx.11` | `outw` | `TransferTable.m` | **no** |
| 26592 | `_xxx.14` | `outl` | `TransferTable.m` | **no** |
| 26596 | `_xxx.8` | `outb` | **deferred** — `vidBIOS.m` | **no** |
| 26600 | `_xxx.11` | `outw` | **deferred** — `vidBIOS.m` | **no** |
| 26604 | `_xxx.14` | `outl` | **deferred** — `vidBIOS.m` | **no** |

**Six of the nine belong to in-scope translation units and three to the
deferred region.** Attribution of the first three and of 26584 is an
**observation** — every `lock incl` instruction in `__text` names one of
`_xxx.86`, `_xxx.89` or `_xxx.8` at 26584, and each of those instructions sits
inside a function whose module is known. Attribution of the last five is an
**inference** from two facts: gcc emits all three counters for any file that
includes `ioPorts.h`, so they come in groups of three; and `__bss` is laid out
in link order, which for `__text` is `IBMThinkPad760ED.m`, `TransferTable.m`,
then `vidBIOS.m`. The numbering corroborates it — the large first file gets
counters 86/89/92 while the two small ones both restart at 8/11/14 — but nothing
in the binary states it outright.

The sibling driver is consistent with this reading: its `__DATA,__bss` is 24
bytes holding **six** symbols, `_xxx.86`/`.89`/`.92` twice over, one group for
each of its two hand-written `.m` files. (The spec's §2.7 describes both drivers'
`__bss` by distinct name and so undercounts the symbols in each; the byte counts
it gives, 24 and 36, are right.)

`__DATA,__common` holds the single 4-byte
`_IBMThinkPad760EDDisplayDriver_instance` at 26608, from the generated
`_instance.m`, returned by finding 30.

**The 92 zero bytes at the tail of `__DATA,__data`, 26480–26572, are separate
from all of this** and belong to `_emu486`; see "The mode table" above.

## Undefined imports

Seventeen undefined symbols, split by which region references them:

**Referenced only by in-scope code (4):**

| Symbol | Used by |
| --- | --- |
| `_IOForkThread` | `enterLinearMode` |
| `_IOSetThreadPriority` | `enterLinearMode` |
| `_IOSleep` | `_set555Mode`, `revertToVGAMode` |
| `_bzero` | `enterLinearMode` (×3), `revertToVGAMode`, `getModeInfo:` (×2) |

**Referenced by both regions (5):**

| Symbol | In-scope users | Deferred users |
| --- | --- | --- |
| `_IOFree` | `free`, `setTransferTable:count:` (×2) | `-[vidBIOS free]` |
| `_IOLog` | six methods — `initFromDeviceDescription:` (56), `enterLinearMode` (1184), `determineConfiguration:` (2196), `setPCIConfiguration` (2624), `reportSystemConfiguration` (4560), `(TransferTable) setBrightness:token:` (6044) | `-[vidBIOS init]`, `-[vidBIOS int10:…smmport:]` |
| `_IOMalloc` | `setTransferTable:count:` | `-[vidBIOS init]` |
| `_objc_msgSend` | almost every method | `vidBIOS` methods |
| `_objc_msgSendSuper` | `initFromDeviceDescription:`, `revertToVGAMode`, `free`, `name`, `setPendingDisplayMode:` | `-[vidBIOS free]` |

**Referenced only by the deferred region (8):**

`_IOFreeLow`, `_IOMallocLow`, `_IOMapPhysicalIntoIOTask`,
`_IOPhysicalFromVirtual`, `_IOUnmapPhysicalFromIOTask`, `_IOVmTaskSelf`,
`_memset`, `_page_size` — all six of the first from `-[vidBIOS init]` and
`-[vidBIOS free]`, and `_memset` and `_page_size` from `-[vidBIOS init]` and
`-[vidBIOS int10:…smmport:]`.

Separately, **eight** `.objc_`-prefixed symbols are Objective-C class and
category references rather than function imports. Three name classes the kernel
supplies: `.objc_class_name_IODevice`, `.objc_class_name_IOFrameBufferDisplay`
and `.objc_class_name_Object`. One, **`.objc_class_name_vidBIOS`, is defined by
this binary's own deferred `vidBIOS.m`**, and together with `_emu486` it is what
will leave the ThinkPad link unresolved until drvVGA supplies both (spec §4.3).
The remaining four — easy to miscount as more imports — are simply **this
binary's own class and category names**:
`.objc_class_name_IBMThinkPad760EDDisplayDriver`,
`.objc_class_name_IBMThinkPad760EDDisplayDriverKernelServerInstance`,
`.objc_class_name_IBMThinkPad760EDDisplayDriverVersion` and
`.objc_category_name_IBMThinkPad760EDDisplayDriver_TransferTable`.

**Consequence for Tasks 8 and 9:** the four in-scope-only imports plus the five
shared ones — nine symbols — are the entire non-Objective-C runtime surface the
rewrite has to satisfy. The eight deferred-only imports must **not** appear in
`IBMThinkPad760ED.m`, `TransferTable.m` or `smapi.s`; if they do, something has
been written that belongs to `vidBIOS.m`.

## The driver is a Trident, and one binary serves two machines

**Despite its name, this driver does not drive an IBM part.** Apple's
`Default.table` sets

```
"Auto Detect IDs" = "0x96601023";
```

— vendor 0x1023, Trident Microsystems, device 0x9660, the TGUI9660 — and the
driver's own strings say `Trident Cyber938x`, `TVGA BIOS SetMode failure` and
`Chip ID=0x%02x`. The IBM-specific part of the driver is the *panel and system*
access, which goes through IBM's SMAPI BIOS (findings 23 and 29) and the CMOS
bytes 0x7E/0x7F that give the SMAPI port; the *graphics* part is Trident
sequencer and CRTC programming plus the Trident and VESA video BIOS.

**`Default.table` and `ThinkPad760.table` differ in exactly two lines**, verified
by `diff` over the restored resources:

| Key | `Default.table` | `ThinkPad760.table` |
| --- | --- | --- |
| `"Title"` | `IBM ThinkPad 560` | `IBM ThinkPad 760E/760ED` |
| `"Help File"` | `ThinkPad560.rtfd` | `ThinkPad760.rtfd` |

Every other key — `"Driver Name"`, `"Server Name"`, `"Bus Type" = "PCI"`,
`"Auto Detect IDs"`, `"Memory Maps" = "0x08000000-0x081fffff 0xa0000-0xbffff
0xc0000-0xcffff"`, `"VGA Memory Maps"`, `"I/O Ports" = "0x03b0-0x03df
0x0102-0x0102 0x43c6-0x43c9"`, `"Display Mode" = "Height:600 Width:800
Refresh:60Hz ColorSpace:RGB:555/16"` — is identical. **One binary serves the
ThinkPad 560 and the 760E/760ED**, distinguished only by which table the
installer picks, and the driver itself never reads either key.

The two `.modes` files, by contrast, are **not** the same: `Display.modes` lists
10 modes and `ThinkPad760.modes` lists 14, the extra four being 1024×768×15 at
both refresh rates and 1280×1024×8 at both. The 14 in `ThinkPad760.modes`
correspond one-for-one with `_ThinkPad760EDModeTable`; `Display.modes` is the
560's smaller panel repertoire. That difference is a resource difference only —
the mode table in the binary is the same 14 entries either way, and
`updateModeTable` and `defaultMode` are what narrow it at runtime.

The `"I/O Ports"` range `0x43c6-0x43c9` is worth noting against finding 27:
the DAC ports the driver actually writes are `0x3C6`, `0x3C8` and `0x3C9`, and
`0x43c6-0x43c9` is the same window relocated by 0x4000 — the alias the config
table reserves so the DAC can be reached while VGA I/O is disabled. This
document records the ports the code uses; the table's aliasing is not something
the code is aware of.
