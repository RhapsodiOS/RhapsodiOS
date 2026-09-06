# Floppy (drvPPCSwimFloppy) — reconstruction findings

Reference binary: `Drivers/ppc/Floppy.config/Floppy_reloc`
SHA-256 `7CFD5E18A7CF4C5A8196BF7CC93113C6BE6AC90E770A03EDC58001C8D848BA8B`
Source under map: `src/drivers-ppc/ide/drvPPCSwimFloppy/Floppy.drvproj/Floppy.lksproj`

**Nothing here was compiled.** No PowerPC toolchain and no host C compiler are
present in this environment. No `make` was run. Every claim below rests on the
Mach-O symbol table, IDA's function list, and the checkers in `tools/binrecon`.
Where this document says a renamed symbol "will match" Apple's, that follows
from the Mach-O naming rule — the compiler prepends exactly one underscore to a
C identifier — and from `symbol_name_check.py`, not from a build.

---

## 1. The reference analysis

`tools/binrecon/out/floppy-ppc/published/analysis-reference-ida.json`:

```
functions: 708
unnamed  : 506
lowest   : 0x8c
```

708 - 506 = **202 named functions**. `filter_named_functions.py` produced
`tools/binrecon/out/floppy-ppc/analysis-named.json` with exactly those 202;
re-running the shape snippet against it gives `functions: 202`, `unnamed: 0`,
`lowest: 0x8c`, and `input.sha256` is byte-identical to the published analysis,
so the filtered document still binds to the same binary.

The 506 unnamed entries are the PowerPC jump islands the linker emits between
`bl` sites and their targets. They carry no symbol and no source, and are
excluded before mapping.

## 2. The symbol partition

The binary defines **203** `__TEXT,__text` symbols:

| group | count |
| --- | --- |
| build-generated Objective-C class methods (`FloppyVersion`, `FloppyKernelServerInstance`) | 2 |
| hand-written Objective-C methods | 60 |
| hand-written C functions | 141 |
| **total** | **203** |

203 defined symbols against 202 named functions. The difference is exactly one
symbol: `_fdrToIo` — see section 5.

## 3. Four-category coverage of `source-map.json` (Task 3 snapshot)

> **Sections 3, 4, 6, 7, 8, 10 and 11 record the Task 3 measurement**, taken before
> Task 4's selector rename and before Task 5 wrote the five absent bodies and
> deleted the three duplicate statics. Their counts, and the source line numbers
> they cite, describe the tree as it stood at commit `53da4375`. They are kept as
> the record of what was found, not as a description of the tree today.
> **Section 14 supersedes them** with the Task 6 remap.

Built with `--objc-methods` and **without** `--scope-to-objc`. Scoping to
Objective-C would have covered 60 of the 201 hand-written functions and reported
itself complete; 141 of the 201 are C, so the full-scope route is the only
honest one.

| category | count |
| --- | --- |
| `mapped` | 141 |
| `unmapped` | 59 |
| `duplicate_candidates` | 2 |
| `boundary_disputed` | 0 |
| **total** | **202** |

141 + 59 + 2 + 0 = 202, the whole named-function set. Coverage is judged across
all four categories, not `mapped` union `unmapped`.

By language:

| category | Objective-C | C |
| --- | --- | --- |
| `mapped` | 8 | 133 |
| `unmapped` | 54 | 5 |
| `duplicate_candidates` | 0 | 2 |
| `boundary_disputed` | 0 | 0 |

`boundary_disputed` is empty: only IDA supports PowerPC, so no analyzer can
disagree about a function extent, and no named function's `[address, address +
size)` range overlaps another's, so no symbol is an interior label.

## 4. Buckets

`bucket_functions.py tools/binrecon/out/floppy-ppc/analysis-named.json
src/drivers-ppc/reconstruction/Floppy/source-map.json`:

```
total functions: 202
  mapped: 141
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 0
  4-build-generated-class: 2
  5-fn-with-source-site: 0
  6-fn-no-source-site: 59
counted: 202
RECONCILES: yes
```

Buckets 1 and 2 are empty as always for a `_reloc` kernel server: it is
relocatable object output with no crt startup and no PIC symbol stubs. Bucket 3
is empty because the 506 unnamed islands were filtered out in Step 1 rather than
carried into the map.

Bucket 4 holds exactly the two build-generated class methods,
`+[FloppyKernelServerInstance kernelServerInstance]` (0xc038) and
`+[FloppyVersion driverKitVersionForFloppy]` (0xc04c). These are emitted by the
driver build machinery, have no hand-written source, and are correctly outside
the 201.

**Bucket 6 is not the gap count.** Its 59 entries are the map's 57
non-build-generated `unmapped` plus the 2 `duplicate_candidates`, and they break
down as:

| bucket 6 contents | count | section |
| --- | --- | --- |
| Objective-C methods whose source selector carries a spurious leading underscore | 52 | 6 |
| C functions with no source definition at all (real gaps) | 5 | 8 |
| C functions with two source definitions | 2 | 7 |
| **total** | **59** | |

## 5. `_fdrToIo` — a known exclusion, not a gap and not a phantom

`ppc_invariant_check.py` reports one violation:

```
symbol _fdrToIo at 0x0 has no function start in the analysis, but code is
present: the bytes there are a function prologue, so the analysis omits a
real function
214 scattered/difference-form relocations (target section verified, field is a difference, not an address)
71 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
3932 fused relocations, 1 violations
```

The first four words at `__TEXT,__text + 0` are

```
9421ffe0 28830017 41850078 3d200001
```

`9421ffe0` is `stwu r1,-32(r1)` — a standard PowerPC prologue. The bytes are
**real code**. The finding means only that IDA's function list has no entry
starting at address 0; it is **not** evidence that the body is absent. The
checker itself says so: "code is present".

`_fdrToIo` therefore never enters the source map (confirmed: the name appears in
none of the four categories), and the map covers 200 of the 201 hand-written
functions by construction, plus the 2 build-generated ones, for 202 entries.

The function is present in our source at `FloppyDisk.m:8679` as
`unsigned int fdrToIo(unsigned int fdrCode)`, and `symbol_name_check.py` lists
it as *not* missing — that checker works from definition sites, so it can
confirm what IDA's function list cannot. Unlike every earlier driver in this
series the address-0 function here is a plain C function rather than a `+probe:`
method, so `selector_check.py` has nothing to say about it.

Record: **known exclusion. Code present. Not a gap, not a phantom.**

The other three invariant lines are clean — 214 scattered/difference-form
relocations all land in a verified target section, and all 71 HI16/HA16-LO16
pairs reconstruct to agreeing values, which is what rules out a byte-order or
HA16 sign-extension misread of this big-endian image.

## 6. The 52 Objective-C selectors

> **Task 3 snapshot — superseded by 12.7 and 14.7.** This section is written in
> the present tense about a tree that no longer exists: Task 4 renamed 52 of
> these selectors and Task 5 the 53rd, so none of them fails to map today.
> It is kept as the record of what was found.

All 52 hand-written Objective-C methods in bucket 6 fail to map for **one
reason**: the selector in our source carries a leading underscore that Apple's
binary does not have.

```
source                                    binary
-[FloppyDisk _abortRequest]           ->  -[FloppyDisk abortRequest]
-[FloppyDisk(Internal) _timerEvent]   ->  -[FloppyDisk(Internal) timerEvent]
-[FloppyDisk(Thread) _fdRwCommon:]    ->  -[FloppyDisk(Thread) fdRwCommon:]
```

`selector_check.py` confirms it independently:

```
reference selectors: 62
our definitions:     60

renames (52):
    ... 21 in @implementation FloppyDisk           (FloppyDisk.m)
    ... 21 in @implementation FloppyDisk(Internal) (FloppyDiskInt.m)
    ... 10 in @implementation FloppyDisk(Thread)   (FloppyDiskThread.m)

duplicates (0):

missing (2):
    +[FloppyKernelServerInstance kernelServerInstance]
    +[FloppyVersion driverKitVersionForFloppy]

extra (0):
```

The two "missing" are the build-generated class methods of bucket 4, which have
no hand-written source by definition. There are no duplicates and no extras.

This is the same defect class as the 141 C functions of section 9, in the other
half of the language. Task 2's C rename derived its name list by excluding `-[`
and `+[` symbols, so the selectors were never examined. Fixing them is not this
task's work; the map records them.

The 8 Objective-C methods that *do* map are the 8 whose source selectors were
already written without the underscore: `+[FloppyController probe:]`,
`+[FloppyDisk probe:]`, `+[FloppyDisk requiredProtocols]`,
`+[FloppyDisk deviceStyle]`, and the four `read`/`write` `At:...` methods.

### The IDA category collapse is real, and is *not* the cause

IDA's function list does collapse category names: an entry the symbol table
carries as `-[FloppyDisk(Internal) timerEvent]` appears in the analysis as
`-[FloppyDisk timerEvent]`. There are **31** such collapses — 21 in `(Internal)`
and 10 in `(Thread)` — and they are count-neutral: no function is lost,
duplicated, or renamed onto another real symbol.

They are also **not** why those 31 are unmapped. `build_source_map` takes the
union of the analysis names and the Mach-O symbol-table names at each address,
and the symbol table retains the category:

```
symbol table:  -[FloppyDisk(Internal) timerEvent]
IDA analysis:  -[FloppyDisk timerEvent]
our source:    -[FloppyDisk(Internal) _timerEvent]
```

The category form is available to the matcher and would have matched a correctly
named source method. Reinserting the underscore into the symbol-table name
resolves all 31 category methods to a source site, and all 21 main-class ones
too — 52 of 52. The collapse is a cosmetic property of the analysis to be aware
of when reading bucket 6's listing (every entry there prints as
`-[FloppyDisk ...]`), nothing more.

## 7. `duplicate_candidates` — two functions defined twice

```
0x4c2c  _GetBusyFlag    (120 bytes)
          FloppyDisk.m:3608      (extern)
          FloppyDiskInt.m:125    (static)
0x5d90  _ResetBusyFlag   (96 bytes)
          FloppyDisk.m:6447      (extern)
          FloppyDiskInt.m:130    (static)
```

The map cannot pick a site, so it records both with the reason "symbol name
resolves to multiple definitions" rather than guessing.

The `static` definitions at `FloppyDiskInt.m:125`/`:130` follow the file-scope
`extern` prototypes in `FloppyDisk.h:217`/`:427` within the same translation
unit — C99 6.2.2p7 undefined behaviour, which GCC diagnoses. Nothing was
compiled here, so the period toolchain's exact behaviour is untested. Which
body the calls at `FloppyDiskInt.m:248`/`:267` bind to is precisely what the
conflict leaves undefined.

Apple's binary carries **one** symbol for each, and `static` functions do get
symbol-table entries in `_reloc` output, so the conflict must be resolved one
way or another before this builds. Removing the redundant `static` copies, and
verifying against the disassembly that the surviving body is the one matching
Apple's rather than assuming the external one is right, is Task 4's work. They
are enumerated here with evidence, not fixed.

`getStatusName` is likewise defined twice — `FloppyDisk.m:136` (extern) and
`FloppyDiskThread.m:94` (static) — but it **cannot** appear in
`duplicate_candidates`, because there is no `_getStatusName` symbol in the
binary at all. It is one of the six source-only helpers in section 8.

## 8. Source-only additions and the five real gaps

### Six source-only debug helpers

Defined in our source, absent from Apple's binary. The source identifiers
already carry a leading underscore, so their Mach-O symbols are the
double-underscore forms below, and it is those double-underscore symbols that
are absent from the binary:

```
__getStatusName    FloppyDisk.m:136        (also FloppyDiskThread.m:94, static)
__getDensityName   FloppyDisk.m:146
__getIoctlName     FloppyDisk.m:158
__getCommandName   FloppyDiskInt.m:147
__getResultName    FloppyDiskInt.m:156
__getOpName        FloppyDiskThread.m:86
```

They map codes to strings for debug printing — roughly 100 lines Apple's driver
did not carry. Per the design decision they **stay**, and they are not renamed,
because there is no binary symbol for them to match. They are the reason our
source has 142 distinct C definition names against the binary's 141: 136 shared,
6 source-only.

### Five real gaps

Functions the binary defines with no source definition anywhere:

```
0x5b84  _fdminphys            40 bytes
0x5bac  _fd_dev_to_id        200 bytes
0x68a8  _OpenDBDMAChannel    300 bytes
0x9444  _TestCacheDirtyState  72 bytes
0xa284  _MediaScanTask        28 bytes
```

Writing them is Task 4's work; none was written here. Note for that task: three
are currently declared with data-shaped `extern`s — `extern unsigned int
fdminphys;` at `FloppyDisk.m:2087` and `extern void *MediaScanTask;` at
`FloppyDisk.h:414`, the latter then taken as `&MediaScanTask` for a thread entry
point at `FloppyDisk.m:5297` — which will have to be reconciled with real
function definitions.

## 9. The C rename fixed 136 functions at once

`symbol_name_check.py` establishes presence by definition site, never by
occurrence count. Both runs below were executed for this task against the same
reference binary; the "before" run used the source tree as of the parent commit
`ad5fa6ca`, extracted with `git show`.

**Before** (source at `ad5fa6ca`):

```
hand-written C symbols: 141
missing definitions   : 141
  _fdrToIo
  _GetCurrentState
  _fdTimer
  ... (all 141 listed)
  _HALFormatTrack
```

**After** (source at `53da4375`, the rename commit):

```
hand-written C symbols: 141
missing definitions   : 5
  _fdminphys
  _fd_dev_to_id
  _OpenDBDMAChannel
  _TestCacheDirtyState
  _MediaScanTask
```

141 -> 5. One transformation — dropping the spurious leading underscore from
each hand-written C function name — moved **136** functions from missing to
present. The 5 that remain are the section 8 gaps, which no rename could have
fixed because they have no body in our tree.

## 10. Ledger

`seed_ledger.py source-map.json <reference> ledger.json` produced **202
entries**, one per named function, bound to the same `reference_sha256` as the
map.

Verified programmatically against the map:

- the ledger's 202 addresses are exactly the union of all four map categories;
- every entry's `names` and `size` equal the map's `reference_names` and `size`;
- all 141 `mapped` entries carry `source_path`/`source_line` identical to the
  map's, and each cited line is in range and textually contains the symbol's
  name;
- the 61 entries drawn from `unmapped` and `duplicate_candidates` carry no
  source citation at all — the seeder does not invent one for a gap, and does
  not pick a winner for a duplicate;
- every entry's `status` is `unexamined`, and every `analyzer_agreement.status`
  is `agreed` with the reason "IDA is the only analyzer that supports PowerPC".

## 11. Summary of what is left

| item | count | owner |
| --- | --- | --- |
| Objective-C selectors to rename | 52 | not yet scheduled — see section 6 |
| C functions to write | 5 | Task 4 |
| redundant `static` duplicates to delete | 2 (+1 for `getStatusName`) | Task 4 |
| source-only debug helpers | 6 | kept by design |
| `_fdrToIo` | 1 | known exclusion, code present |

---

## 12. Task 5 — the five absent functions

Written from the disassembly of `Floppy_reloc`. Every `bl` was resolved through
the **island's** HI16/LO16 relocation pair in `read_macho`'s table, not through
IDA's operand text: IDA's external names in this image are wrong (it prints
`_fdrToIo@ha` for every undefined-symbol HA16 it cannot attribute). The
relocation table gives `_page_size`, `_kernel_map`, `_kernel_task`,
`_kmem_alloc_wired`, `_kvtophys` and `_kernel_thread` at those sites.

| function | address | body | islands | span |
| --- | --- | --- | --- | --- |
| `fdminphys` | `0x5b84` | 40 | 0 | 40 |
| `MediaScanTask` | `0xa284` | 28 | 2 (32) | 60 |
| `TestCacheDirtyState` | `0x9444` | 72 | 1 (16) | 88 |
| `fd_dev_to_id` | `0x5bac` | 200 | 1 (16) | 216 |
| `OpenDBDMAChannel` | `0x68a8` | 300 | 5 (80) | 380 |

Every span reconciles as `body + 16 * islands`. Four of the five bodies end at
a `blr`; `MediaScanTask` has none — it ends at `0xa29c b 0xa290`, the back-edge
of its infinite loop, as 12.2 describes. Nothing was compiled; no `make` was
run.

### 12.1 `fdminphys` (`0x5b84`)

Ten instructions, straight-line with one forward branch.

```
stwu r1,-32(r1)          frame
lis/lwz r9,_page_size    r9 = page_size          (reloc: _page_size, HA16+LO16)
lwz r0,0x30(r3)          r0 = bp->b_bcount
cmplw cr1,r0,r9          unsigned compare
ble cr1,0x5ba0           b_bcount <= page_size -> skip the store
stw r9,0x30(r3)          b_bcount = page_size
lwz r3,0x30(r3)          return b_bcount
addi r1,r1,0x20 / blr
```

The only branch is the `ble`, and both arms fall into the same `lwz r3`. The
i386 `drvPCFloppy` sibling is `return bp->b_bcount;` with **no** clamp; the
PowerPC driver clamps. The hint was checked and rejected — the body here is
derived from this binary.

### 12.2 `MediaScanTask` (`0xa284`)

```
mflr/stw/stwu            prologue; lr is saved and never restored
0xa290: bl -> 0x7178     _ScanForDisketteChange   (island 0xa2b0)
        li r3,0x1F4      500
        bl -> 0x6bf8     _FloppyTimedSleep        (island 0xa2a0)
        b 0xa290         unconditional back-edge
```

Both branches are covered: the `bl` pair and the `b` back to `0xa290`. There is
no exit path — no `blr`, and the saved `lr` is never reloaded. It is a thread
body, and `_LaunchMediaScanTask` (`0xa2c0`) confirms it: that function loads
`_kernel_task`, takes `&MediaScanTask`, calls `_kernel_thread`, and stores the
result in `_MediaScanTaskID`. Written as `for (;;) { ... }`.

### 12.3 `TestCacheDirtyState` (`0x9444`)

```
lis/addi r9,_SonyVariables+0x650   scattered HA16/LO16 -> __DATA,__common+0x72c
lha r9,0(r9)                       cached drive number (DAT_0000fb88)
lbz r0,0x46(r3)                    this drive's number
cmpw cr1,r9,r0
bne cr1,0x9478                     different drive -> r3 = 0
addi r3,r3,0xA4 ; li r4,0x10
bl -> 0x6f74                       _TestBitArray (island 0x948c)
b 0x947c
0x9478: li r3,0                    the else arm
0x947c: epilogue, return r3
```

Both arms of the single `bne` are accounted for. `0xa4`/`0x10` are the same
dirty-bit-array base and length that `DumpTrackCache` already passes to
`ResetBitArray` (`FloppyDisk.m`), and `0x46` is the same cached-drive field
`TestTrackInCache` already reads, so no bare constant was invented.

**`intentional-mismatch` 2.** `0x9458` loads the cached drive number with
`lha` — a **signed** halfword load. Our tree defines `DAT_0000fb88` as
`unsigned short`, and `TestTrackInCache` (`FloppyDisk.m:7967`) already compares
it unsigned, so the body written here does too. The two widenings differ only
at `0xffff`, the invalidation sentinel `DumpTrackCache` writes, which equals no
0..255 drive byte signed *or* unsigned; the comparison's result is therefore
the same for every value the field can hold. Kept `unsigned short` for
consistency with the definition and with `TestTrackInCache`. The divergence is
recorded in the function's own comment, the same way 12.5's is.

### 12.4 `fd_dev_to_id` (`0x5bac`) — arity

**Settled: one argument, `int fd_dev_to_id(unsigned int dev)`.**

The evidence is on both sides of the call.

*Callee.* The first three instructions after the prologue read `r3` before
anything writes it:

```
extrwi r0,r3,5,24    r0 = (dev >> 3) & 0x1f     unit
clrlwi r11,r3,29     r11 = dev & 7              slot
...
extrwi r4,r3,8,16    r4 = (dev >> 8) & 0xff     major
```

`r3` is live on entry, so it is a parameter. No other argument register is read.

*Callers.* All six `bl` sites reach `0x5bac` through an island, and every one of
them establishes `r3` first:

```
_Fdopen+0x28      mr r29,r3 ; mr r27,r4 ; bl      -> r3 = dev (param 1)
_Fdclose+0x1c     mr r30,r3 ; bl                  -> r3 = dev (param 1)
_fdread+0x28      mr r27,r3 ; mr r28,r4 ; bl      -> r3 = dev (param 1)
_fdwrite+0x24     mr r29,r3 ; mr r28,r4 ; bl      -> r3 = dev (param 1)
_fdstrategy+0x2c  lwz r3,0x38(r31) ; bl           -> r3 = bp->b_dev
_fdsize+0xc       (r3 untouched) ; bl             -> r3 = dev (param 1)
```

The one source declaration that already carried an argument
(now `FloppyDisk.m:2286`, in `fdstrategy`) was the correct one; the five `(void)`
declarations were wrong. All six now read
`extern int fd_dev_to_id(unsigned int device);`, a matching prototype was added
to `FloppyDisk.h`, and the five bare calls now pass their device number.

`_fdsize` consequently gained the parameter it always had in the binary. It has
exactly **two** declarations plus the definition, not three: the block-scope
declaration in `+probe:` (`FloppyDisk.m:260`), the file-scope one in
`FloppyDisk.h:192`, and the definition at `FloppyDisk.m:2241`. An earlier draft
of this section counted "the local in `fdsize` itself" as a third declaration;
no such local exists — that is the definition. All three sites were `(void)`
and all three were given the parameter.

Their **return types** disagreed after that change: `FloppyDisk.m:260` read
`int`, the other two `unsigned int`. The binary settles it. `_fdsize`
(`0x5af8`) has two arms:

```
0x5b04 bl -> 0x5bac   _fd_dev_to_id
0x5b08 or. r3,r3,r3 / beq 0x5b20
  0x5b10 lis r4,1 ; lwz r4,0x294(r4)     __OBJC,__message_refs+0x9c
  0x5b18 bl -> _objc_msgSend             ("blockSize"), result kept in r3
  0x5b1c b 0x5b44
0x5b20 lis/addi r3,"fdsize: bad unit\n"  (__TEXT,__cstring+0x1a50)
  li r4..r8,1..5 ; bl -> 0x6f18 _donone
0x5b40 li r3,-1                          the bad-unit return value
0x5b44 epilogue
```

`li r3,-1` is a signed sentinel, so the settled type is **`int`**. All three
sites now read `int fdsize(unsigned int)`, and the local that carried
`0xffffffff` was retyped `int` and now carries `-1`, which is the same word.
The `psize:` argument at `FloppyDisk.m:306` casts to `void *` and is unaffected.

*Body.* Every branch:

```
cmpwi cr1,r0,0xF / ble          unit <= 15 -> keep it
  addic r0,r0,-0x10             else unit -= 16
  addi  r11,r11,8                    slot += 8
cmpwi cr1,r0,1 / ble            unit <= 1 -> continue
  lis/addi r3,"fd_dev_to_id:ret nil\n"   (__TEXT,__cstring+0x1a64 = 0xdc80)
  bl -> 0x6f18  _donone         (island 0x5c74, shared by all three calls)
  li r3,0 ; b epilogue
3 x cror 0,0,0                  alignment no-ops, no source content
mulli r0,r0,0x4C ; add r31,r0,&_FloppyIdMap      entry = map + unit*0x4c
cmpwi cr1,r11,1 / bne -> 0x5c54
  extrwi r4,r3,8,16 ; lwz r9,_fd_block_major ; cmpw / bne -> 0x5c3c
    lis/addi r3,"fd_dev_to_id:fdblockmaj=%d\n"   (0xdc98); bl _donone
      (r4 still holds the major - it is argument 2)
    li r3,0 ; b epilogue
  0x5c3c: lis/addi r3,"fd_dev_to_id:retlive=0x%x\n" (0xdcb4)
    lwz r4,0(r31) ; bl _donone ; lwz r3,0(r31) ; b epilogue
0x5c54: slwi r9,r11,2 ; add r9,r9,r31 ; lwz r3,4(r9)
```

Four branches, all covered. The `0x4c` stride is the one `fd_init_idmap`
already walks (`puVar3 = puVar3 + 0x4c`), and the `0x98` it clears is exactly
two such entries, which also settles the `_FloppyIdMap` array bound — see 12.6.

Note the shape: slot 1 returns word 0 of the entry, not word 2 as the general
`slot*4 + 4` formula would give. That is a deliberate special case in the
binary (the "retlive" path), reproduced as written.

### 12.5 `OpenDBDMAChannel` (`0x68a8`)

Five parameters. The callee reads only `r3`, `r4`, `r5`, but the caller
`_HALReset+0xec` sets `r3`..`r7`:

```
lwz  r3,_GRCFloppyDMARegs
addi r4,&_GRCFloppyDMAChannel
li   r5,1
addi r6,&_ccCommandsLogicalAddr
addi r7,&_ccCommandsPhysicalAddr
bl -> 0x68a8
```

so the existing five-parameter declaration at `FloppyDisk.h:299` matches
Apple's; the last two arguments are simply ignored by the body. Only the return
type was corrected — see 12.6.

Instruction account:

```
prologue saves r28-r31
mr r28,r3 ; mr r29,r4 ; li r31,0                dmaBase, channelPtr, result = 0
lis/addi r9,&_PrivDBDMAChannelArea
stw r9,0(r29)                                   *channelPtr = &area
mr r30,r9
mr. r5,r5 / bne -> 0x68f0                       branch 1
  li r3,-0x32 ; b 0x69b4                        return -50, bypassing "mr r3,r31"
0x68f0: slwi r5,r5,4 ; addi r5,r5,-1
        lwz r9,_page_size ; add r5,r5,r9
        neg r9,r9 ; and r5,r5,r9                round up to a page
        lwz r3,_kernel_map ; addi r4,r30,0x14
        bl -> _kmem_alloc_wired  (island 0x6a14)   result in r3 ignored
lwz r0,0x14(r30) ; cmpwi / bne -> 0x6938        branch 2
  lis/addi r3,"dbdmasupport.c:Unable to create DBDMA CCLs memory\n" (0xdd80)
  bl -> _donone (island 0x6a04) ; li r31,0xA
0x6938: lwz r3,0x14(r30) ; bl -> _kvtophys (island 0x69f4) ; stw r3,0x18(r30)
        lwz r11,0x14(r30) ; lwz r9,_page_size ; li r10,0
        srwi. r0,r9,4 / beq -> 0x6990           branch 3 (loop-rotation guard)
        li r7,0x70 ; li r9,0 ; lis r8,_page_size@ha
  0x6968: stw r7,0(r11) ; stw r9,4(r11) ; stw r9,0xC(r11) ; stw r9,8(r11)
          addi r11,r11,0x10 ; addi r10,r10,1
          lwz r0,_page_size(r8) ; srwi r0,r0,4
          cmplw cr1,r10,r0 / blt -> 0x6968      branch 4 (back-edge)
0x6990: cmpwi cr1,r31,0 / beq -> 0x69a4         branch 5
  lwz r3,0(r29) ; bl -> _CloseDBDMAChannel (island 0x69e4) ; b 0x69b0
0x69a4: stw r28,4(r30) ; lwz r3,0(r29) ; bl -> _ResetDBDMA (island 0x69d4)
0x69b0: mr r3,r31
0x69b4: epilogue
```

Five branches, all covered. The reload of `page_size` inside the loop is what a
`for (i = 0; i < page_size >> 4; i++)` over a non-`const` extern compiles to
when the body stores through a pointer, so the loop is written in that form;
`r9 = page_size` at `0x6948` is dead after the guard and `li r9,0` at `0x6960`
reuses the register.

Channel-area layout, confirmed against `PrepDBDMA` which already reads the same
offsets: `+0x04` DBDMA register base, `+0x14` command-list logical address,
`+0x18` command-list physical address.

**The area's bound, and the connection defect.** An earlier draft of this
section followed the tree's existing convention and wrote those three words as
the separate globals `DAT_0000f500`, `DAT_0000f510` and `DAT_0000f514` rather
than widening `_PrivDBDMAChannelArea`. Both halves of that decision were wrong,
and both are corrected here.

*The bound.* `_PrivDBDMAChannelArea` was declared `unsigned char [4]`. The true
size is derivable exactly as `_FloppyIdMap`'s was, from the symbol span: the
symbol is at `0xf4fc`, the next symbol `_GRCFloppyDMARegs` is at `0xf528`, and
the sorted symbol table has nothing in between, so the object is
**`0x2c` = 44 bytes**. Both declarations were widened to `[0x2c]`.

This was not cosmetic. Before this task nothing in the tree ever assigned
`_GRCFloppyDMAChannel` — `FloppyDisk.m` initialises it to `0` and every other
reference is a read — so no DBDMA function was reachable with a live channel.
`OpenDBDMAChannel` stores `&_PrivDBDMAChannelArea` into `*channelPtr`, and
`channelPtr` is `&_GRCFloppyDMAChannel`, so writing this function is what made
`ResetDBDMA`, `ResetDMAChannel`, `PrepDBDMA`, `SetDBDMAPhysicalAddress`,
`StartDBDMA` and `StopDBDMA` live. `ResetDBDMA`'s body writes offsets `0x0`,
`0x4`, `0x8` and `0xc`; `PrepDBDMA` reads `+0x18` and dereferences `+0x04`;
`SetDBDMAPhysicalAddress` dereferences `+0x04` and `+0x14`. Against a 4-byte
declaration every one of those is out of bounds. Against `[0x2c]` — the
binary's own size, and the largest offset any of them touches is `0x18` — none
of them is.

*The connection.* Modelling `+0x04`, `+0x14` and `+0x18` as standalone globals
made the two halves of this function fail to meet. `ResetDBDMA` reads the
register base from `channel + 4` (`0x6660 lwz r9,4(r3)`), so a store to a
separate object named `DAT_0000f500` is not the word the callee reads, however
the addresses happen to line up in the image. `OpenDBDMAChannel` would have
armed the channel and then reset it through an uninitialised register pointer.
The three offsets are now written as fields of the widened area, mirroring the
binary's own `r30` addressing (`addi r4,r30,0x14`, `stw r3,0x18(r30)`,
`stw r28,4(r30)`) and matching the byte-offset style `PrepDBDMA`,
`StartDBDMA`, `StopDBDMA` and `SetDBDMAPhysicalAddress` already use. No
resolved address, branch or store changed; only the spelling did.

**The connection is made, but for one consumer it is undone again.** Naming one
object rather than three is necessary and it holds. It is not sufficient:
`ResetDBDMA`'s body in our tree diverges from `0x665c` and its
`FloppyDisk.m:6690` write **zeroes** `area + 4` — the very register base
`OpenDBDMAChannel` stores there eight lines earlier, and the word `PrepDBDMA`,
`SetDBDMAPhysicalAddress`, `StartDBDMA` and `StopDBDMA` all dereference. So on
the path this function creates, the register base survives exactly until the
`ResetDBDMA` call at the end of it. `ResetDBDMA` is an existing function outside
this task's edit set and was not touched; the defect is recorded in full as
uncertainty 7.

The three `DAT_0000f5xx` declarations and definitions were removed with that
change. They had no callers left, they correspond to no symbol in the reference
(the symbol table has nothing between `0xf4fc` and `0xf528`), and keeping them
alongside `_PrivDBDMAChannelArea[0x2c]` would have left two spellings of one
object — the hazard uncertainty 5 describes.

`0x70` in word 0 of each 16-byte slot is a DBDMA STOP: the registers are
little-endian, so the big-endian word `0x00000070` reads back as `0x70000000`,
whose top nibble (the `cmd` field) is 7 = STOP.

The allocation is `round_page(param3 * 0x10)` but the fill runs
`page_size / 0x10` slots, so a request larger than one page leaves the rest
uninitialised. That is always within the allocation, never past it, so it is
reproduced as written; the only caller passes `param3 = 1`.

**`intentional-mismatch` 1.** The shipped body runs `kvtophys` and the STOP fill
**unconditionally**: there is no branch between the `li r31,0xA` at `0x6934` and
the loop, so a `kmem_alloc_wired` failure makes it call `kvtophys(0)` and then
write `page_size` bytes starting at virtual address 0. Our body guards the
`kvtophys` and the fill with the `else` of the null test and is otherwise
identical, including the `iVar3 = 10` result and the `CloseDBDMAChannel` arm.
The divergence is recorded in the function's own comment.

### 12.6 Declaration defects settled

| defect | site(s) | resolution |
| --- | --- | --- |
| `fd_dev_to_id` declared `(void)` | 5 sites in `FloppyDisk.m` | all six now `(unsigned int device)`; prototype added to `FloppyDisk.h` |
| `fdsize` declared `(void)` | local in `+probe:` (`FloppyDisk.m:260`), `FloppyDisk.h:192`, the definition (`FloppyDisk.m:2241`) | all three now `int fdsize(unsigned int)` |
| `extern unsigned int fdminphys;` (data) | `FloppyDisk.m`, twice | `extern unsigned int fdminphys(int bufPtr);`, prototype added to `FloppyDisk.h` |
| `extern void *MediaScanTask;` (data) | `FloppyDisk.h:416` | `extern void MediaScanTask(void);` |
| `OpenDBDMAChannel` declared `void` | `FloppyDisk.h:299` | `int` |
| `CloseDBDMAChannel(void)` | `FloppyDisk.h:172` and its definition | takes and ignores an `int` channel |
| `_FloppyIdMap[64]` | `FloppyDisk.h`, `FloppyDisk.m` | `[0x98]` |
| `_PrivDBDMAChannelArea[4]` | `FloppyDisk.h`, `FloppyDisk.m` | `[0x2c]`; see 12.5 |
| `fdsize` returns `unsigned int` | `FloppyDisk.h:192`, `FloppyDisk.m:2241` | `int` — `_fdsize` returns `-1`; see 12.4 |

`TestCacheDirtyState`'s existing local declaration
(`extern int TestCacheDirtyState(int driveStructure);`) already matched the body
written here and was left alone.

Two of these go beyond the letter of the task brief and are called out
deliberately:

1. **`OpenDBDMAChannel`'s return type.** The brief said the declaration is
   "already function-shaped" — i.e. that it is not an instance of the
   data-declared-as-function defect the brief was about. It did not say to
   leave the declaration alone, and an earlier draft of this section
   overstated it that way. There was no contradiction to resolve: the return
   type is `void`, the body returns three distinct values (`0`, `10`,
   `-0x32`) in `r3`, and `mr r3,r31` at `0x69b0` is unambiguous. Keeping
   `void` would have discarded both error codes. Changed to `int`.
2. **`CloseDBDMAChannel`'s parameter.** `0x6998` loads `r3` from `*channelPtr`
   immediately before the `bl`, so the shipped call passes an argument, but our
   declaration was `(void)` — a constraint violation at the new call site. The
   callee's body (`stwu`/`addi`/`blr`) ignores `r3`, so an ignored `int`
   parameter reproduces both sides exactly.

The `_FloppyIdMap` bound was already provably wrong before this task
(`fd_init_idmap` writes `+0x44`/`+0x48` of entry 1, offset 0x94, and clears
`0x98` bytes), and `fd_dev_to_id` indexes as far as offset 0x8c, so the array
was widened to the `0x98` the binary's symbol span shows (`0xf460`..`0xf4f8`).

### 12.7 The 53rd selector

`_fcCmdXfr:driveInfo:` was renamed to `fcCmdXfr:driveInfo:` at both sites in
`FloppyDiskInt.m` (the `FloppyController` forward declaration and the send in
`fdSendCmd`). Verified independently against the image: the
`__OBJC,__meth_var_names` blob contains `fcCmdXfr:driveInfo:` bare, it is one of
the 99 entries of `__OBJC,__message_refs`, and **none** of those 99 begins with
an underscore. `selector_check.py` now reports 0 renames, 0 duplicates,
0 extras, and the 2 build-generated methods missing.

### 12.8 The three duplicate definitions

All three `static` copies were deleted and the external definitions kept.

`GetBusyFlag` (`0x4c2c`, 120 bytes) and `ResetBusyFlag` (`0x5d90`, 96 bytes)
were checked against the disassembly rather than assumed. The external bodies in
`FloppyDisk.m` are the structural match:

- `_GetBusyFlag` spins on `_busyflag == 1` calling `_timeout(0, &_busyflag, 1)`
  and `_sleep(&_busyflag, 0x16)`, then retries `_SetBusyFlag` (`0x5cfc`) until
  it succeeds — the `do { while (busyflag == 1) {...} } while (!SetBusyFlag())`
  shape the external body already has.
- `_ResetBusyFlag` spins on `_test_and_set(0, slock)`, stores `0` to
  `_busyflag`, then `sync` and releases the lock — the lock/clear/release shape
  the external body already has.

The `static` copies in `FloppyDiskInt.m` were one-line stubs (`_BusyFlag = YES;`
and `_BusyFlag = NO;`) that match nothing in the binary. `FloppyDiskInt.m`
imports `FloppyDisk.h`, which already declares both, so no declaration was
added. The now-orphaned `static BOOL _BusyFlag` was removed with them;
`static int _DataSource` stays, it is still used at two sites.

`getStatusName` has no binary counterpart, so **no true bound is derivable**
and the choice rests only on which of the two is less unsafe across the three
call sites. **The external body in `FloppyDisk.m` (bound 16) was kept** and the
`static` in `FloppyDiskThread.m` (bound 20) deleted, because 16 is strictly
safer than 20 at all three:

- `FloppyDisk.m:754` passes `_fdCommandValues`;
- `FloppyDiskThread.m:536` passes `_fdrValues`, which has 20 entries — codes
  16..19 now print `"Unknown"`, which costs four debug labels and reads nothing
  out of range;
- `FloppyDiskThread.m:603` passes `_densityValues`, which has **4** entries,
  for which the deleted bound of 20 was already an out-of-bounds read and 16
  still is.

An earlier draft justified 16 as "exactly the length of `_fdCommandValues`".
The binary contradicts that. `_fdCommandValues` is at `0xf2a8` and the next
symbol `_fcOpcodeValues` at `0xf2e0` — `0x38` = 56 bytes = **seven** eight-byte
entries. That is the `LookupEntry _fdCommandValues[]` at `FloppyDisk.m:8619`,
not the 16-element `const char *_fdCommandValues[]` at `FloppyDisk.m:77` the
draft was counting. So bound 16 over-reads `_fdCommandValues` too, not only
`_densityValues`: 16 four-byte reads span 64 bytes against the symbol's 56.
The decision stands — it is still the safer of the two available bounds — but
it is a safety choice, not a derived one, and the source comment on
`_getStatusName` now says so.

**Pre-existing defect exposed while checking this, recorded and not fixed.**
`_fdCommandValues` is **defined twice, with incompatible types, in one
translation unit**: `const char *_fdCommandValues[]` (16 entries) at
`FloppyDisk.m:77` and `LookupEntry _fdCommandValues[]` (7 entries) at
`FloppyDisk.m:8619`, with a third, block-scope `extern const char
*_fdCommandValues[];` at `FloppyDisk.m:751` selecting the first spelling for
the call site. Both definitions predate Task 5 (they are at lines 77 and 8374
of the parent commit). This is a fourth duplicate definition, distinct from the
three the task brief listed and from the two `duplicate_candidates` of
section 7; the binary has one `_fdCommandValues`, the `LookupEntry` table.
Settling it means deciding which table Apple's `FloppyDisk.m` really held and
renaming the other, which needs evidence this task did not have.

`FloppyDiskThread.m` imports `FloppyDisk.h`, which declares `_getStatusName` at
line 118, so no declaration was added.

### 12.9 Uncertainties and pre-existing defects observed

Numbered; none of these was resolved by picking a plausible option.

1. **`_getStatusName`'s bound of 16 still over-reads two of its three
   arrays.** It is wrong for the 4-entry `_densityValues` that
   `FloppyDiskThread.m:603` passes, and — see 12.8 — also for
   `_fdCommandValues`, whose symbol in the reference spans 56 bytes, not the
   64 that 16 pointer-sized reads cover. `_getStatusName` has no binary
   counterpart, so no true bound is derivable; 16 was kept only because it is
   strictly safer than the 20 of the deleted duplicate. Settling it needs
   Apple's source, or a decision to pass the array length.
2. **`fdstrategy` is declared three incompatible ways.** `extern int
   fdstrategy(void);` (local, in `+probe:`), `extern unsigned int fdstrategy;`
   (data, twice, in `fdread` and `fdwrite`), and `extern unsigned int
   fdstrategy(int param_1);` (`FloppyDisk.h:193`) against the definition
   `unsigned int fdstrategy(int param_1)`. This is the same defect class as
   `fdminphys`'s data declaration, at a symbol the task brief did not list. Not
   fixed here; recorded for scheduling.
3. **The `physio` call sites still pass function designators into `unsigned int`
   parameters.** `FUN_00004aa8`/`FUN_00004bec` (physio) are locally declared
   with `unsigned int strategy` and `unsigned int minphys`. Converting
   `fdminphys`'s declaration from data to function turns what was an integer
   argument into a function pointer, which GCC diagnoses as a warning, not an
   error. Fixing it properly means typing those two local prototypes with
   function-pointer parameters, which also depends on uncertainty 2.
4. **`donone` is declared `(void)` and called with arguments at 103 sites —
   settled in Task 6.** Task 5 gave `fd_dev_to_id` and `OpenDBDMAChannel` a
   block-scope `extern void donone(const char *format, ...);`
   (`FloppyDisk.m:1475`, `:5810`), the pattern the tree already uses at
   `FloppyDisk.m:1592` for `FUN_00004940`. Unlike `FUN_00004940`, which has no
   other declaration in the translation unit, `donone` also had a file-scope
   `extern void donone(void);` (`FloppyDisk.h:179`) and a `(void)` definition
   (`FloppyDisk.m:1320`), both visible in the same translation unit. Two
   declarations of one function with incompatible types is C99 6.2.7p2
   undefined behaviour, and because the new ones are at block scope the
   standard does not itself require a diagnostic. Task 5's write-up went one
   step further and said the conflict is "not necessarily diagnosed". That part
   was a claim about compiler behaviour made with no compiler available, and it
   is wrong in practice: GCC rejects an incompatible redeclaration outright —
   `error: conflicting types for 'donone'` — whether the redeclaration is at
   file or block scope. So the two prototypes did not narrow the defect; they
   substituted one hard error for four.

   Task 6 takes the two-line completion Task 5 described and scoped out:
   `FloppyDisk.h:179` is now `extern void donone(const char *format, ...);` and
   the definition at `FloppyDisk.m:1320` is now
   `void donone(const char *format, ...)`. That makes all four declarations and
   the definition compatible, and makes every one of the 103 pre-existing
   argument-passing call sites well-formed rather than ill-formed. None of the
   103 call sites was edited; no call in the tree passes zero arguments (checked
   — there is no `donone()`), so the variadic form leaves every one of them
   valid. The two block-scope prototypes Task 5 added are now exact
   redeclarations of the file-scope one and were left in place. Nothing was
   compiled, so this is a reading of the standard and of documented GCC
   behaviour, not an observed diagnostic.

   **The figure 104 was an occurrence count, not a call count.** `FloppyDisk.m`
   at `f31c0693` contains 104 occurrences of the token `donone`, but one of them
   is the definition at `FloppyDisk.m:1310` — so there are **103** calls. Commit
   `f492103e`'s subject line ("…to match its 104 call sites") carries the same
   mistake and cannot be amended now that it is published history.
5. **Data symbols still carry the spurious leading underscore.** Task 2
   corrected the 136 C *function* names and Task 4 the selectors, but globals are
   untouched: our `_FloppyIdMap` would emit `__FloppyIdMap` against the binary's
   `_FloppyIdMap`, and likewise `_fd_block_major`, `_PrivDBDMAChannelArea`,
   `_GRCFloppyDMAChannel` and the rest. `symbol_name_check.py` measures
   functions only, so this is invisible to the gate. New references written here
   use the existing tree names, because introducing the correct name alongside
   the wrong one would create two spellings of one object. External *kernel*
   symbols are a separate case and were written correctly (`page_size`,
   `kernel_map`, `kmem_alloc_wired`, `kvtophys`), matching how the tree already
   writes `IOMalloc`/`IOLog`.

   **The rule is not function-specific, and this is now measured rather than
   inferred.** Of the reference's **306** symbols, **zero** carry a double
   underscore. Eight of the names the spec listed among the "157 that must not
   move" are real **one-underscore data symbols** in the binary:

   ```
   _FloppyState           __DATA,__data     0xf454
   _Floppy_dev            __DATA,__data     0xf448
   _busyflag              __DATA,__data     0xf444
   _ReadDataPresent       __DATA,__data     0xf458
   _FloppyIdMap           __DATA,__common   0xf460
   _slock                 __DATA,__common   0xf45c
   _PrivDBDMAChannelArea  __DATA,__common   0xf4fc
   _GRCFloppyDMAChannel   __DATA,__common   0xf52c
   ```

   Apple's source therefore spelled those globals **bare**, exactly as it spelled
   the 141 C functions bare. Ours defines them underscored
   (`FloppyDisk.m:922 unsigned int _FloppyState = 0;`,
   `:179 _busyflag`, `:8536 _PrivDBDMAChannelArea`), which emits `__FloppyState`
   and matches nothing. `symbol_name_check.py:46` selects only symbols whose
   `section == "__TEXT,__text"`, so the gate is structurally unable to see this
   and stays green over it. Corroboration from the import side: the binary has
   **48** undefined `_`-prefixed imports; **21** of them are already referenced
   bare and correct in our source, and exactly one is not — see uncertainty 11.

   **Consequence for the next driver.** The design spec's §3.1 and acceptance
   item 3, and the plan's Task 2 Step 3, originally framed "none of the 157
   `_`-prefixed globals was renamed" as a settled correctness result. It is not:
   those 157 were left alone because correcting data symbols was **out of scope
   for the C rename**, not because their spelling is right. All three passages
   were reworded so the defect is scheduled rather than deliberately preserved.
6. **`DAT_0000fb88` is declared twice with different types.** `FloppyDisk.h:123`
   says `unsigned short`, `FloppyDisk.h:508` says `unsigned char`; the definition
   is `unsigned short` and the binary loads a halfword. A hard conflict,
   pre-existing, not fixed here. Our `TestCacheDirtyState` declares the
   `unsigned short` form locally, matching the definition and `DumpTrackCache`.
7. **`ResetDBDMA`'s reconstructed body does not match `0x665c`, and one of its
   writes erases the register base.** The binary is nine instructions:

   ```
   0x665c  9421ffe0  stwu r1,-32(r1)
   0x6660  81230004  lwz  r9,4(r3)      r9 = *(channel + 4)   -- READ, as a pointer
   0x6664  380000c8  li   r0,0xC8
   0x6668  90090000  stw  r0,0(r9)      *r9 = 0xC8
   0x666c  38000000  li   r0,0
   0x6670  90030008  stw  r0,8(r3)      *(channel + 8) = 0
   0x6674  9009000c  stw  r0,0xC(r9)    *(r9 + 0xC) = 0
   0x6678  38210020  addi r1,r1,32
   0x667c  4e800020  blr
   ```

   It **reads** `channel + 4` as the DBDMA register base and writes through it.
   Our source (`FloppyDisk.m:6680`) instead writes four words of the channel
   structure itself, and `FloppyDisk.m:6690` is
   `*(unsigned int *)(param_1 + 4) = 0;` — it **zeroes the register base**.

   This is worse than a spelling difference, and worse than an earlier draft of
   this entry said. That draft concluded only that our writes "still land in the
   channel area"; it did not say that one of them destroys the word every other
   DBDMA consumer dereferences. `PrepDBDMA` (`FloppyDisk.m:6141`),
   `SetDBDMAPhysicalAddress` (`:6995`), `StartDBDMA` (`:7347`) and `StopDBDMA`
   (`:7446`) all dereference `channel + 4` as a pointer, correctly. So the
   sequence `OpenDBDMAChannel` now creates is: store `dmaBase` at `area + 4`,
   call `ResetDBDMA`, which sets that word to `0`; a later `PrepDBDMA` then
   writes through address `0 + 0xc`.

   **12.5's claim that the two halves now connect is therefore only half
   realised.** Widening `_PrivDBDMAChannelArea` and writing the offsets as fields
   of it did make `OpenDBDMAChannel`'s store and the consumers' reads name the
   same object — that part stands. But for this one consumer the connection is
   immediately broken again by `ResetDBDMA`'s divergent body. Fixing
   `ResetDBDMA` is outside this task's edit set; it is a pre-existing defect in
   an existing function, recorded here for scheduling. Before this branch it was
   latent — `_GRCFloppyDMAChannel` was never assigned, so `ResetDBDMA` was
   unreachable with a live channel — and writing `OpenDBDMAChannel` is what
   armed it.
8. **`LaunchMediaScanTask`'s reconstruction uses placeholder names.**
   `_MediaScanTaskID = FUN_0000a300(_entry, &MediaScanTask)` is really
   `kernel_thread(kernel_task, MediaScanTask)`: the relocations at `0xa2cc` and
   the island at `0xa300` name `_kernel_task` and `_kernel_thread`. The
   `MediaScanTask` declaration was corrected to a function as required; the call
   expression and the two placeholder names were left as they were.
   `&MediaScanTask` is still the function's address, but passing it to
   `FUN_0000a300`'s `void *` parameter is now a pointer-conversion warning.
9. **`_PrivDBDMAChannelArea`'s bound — resolved, not an uncertainty.** An
   earlier draft left the array at `[4]` and reasoned that "`OpenDBDMAChannel`
   only takes its address, so nothing written here indexes out of range." That
   is factually wrong. `OpenDBDMAChannel` stores that address into
   `*channelPtr` and then, eight lines later, hands the same value to
   `ResetDBDMA`, whose body writes offsets `0x0`, `0x4`, `0x8` and `0xc` — 12
   bytes past a 4-byte object — and the same store made `PrepDBDMA`,
   `SetDBDMAPhysicalAddress`, `StartDBDMA`, `StopDBDMA` and `ResetDMAChannel`
   reachable for the first time, reading `+0x18` and dereferencing `+0x04` and
   `+0x14`. Writing this function is what armed the out-of-bounds access. The
   bound is derivable exactly as `_FloppyIdMap`'s was — `0xf4fc` to the next
   symbol `_GRCFloppyDMARegs` at `0xf528`, nothing in between, `0x2c` bytes —
   and both declarations now say `[0x2c]`. See 12.5, which also covers the
   `DAT_0000f5xx` offsets that were preventing the two halves of
   `OpenDBDMAChannel` from connecting.
10. **Eight file-scope symbols are declared twice with incompatible types in one
    header. Recorded, not fixed.** An earlier draft of this entry presented
    `_GRCFloppyDMAChannel` as the only same-scope type conflict in
    `FloppyDisk.h`. There are **seven more of identical shape** in that same
    header — two file-scope `extern` declarations of one name with incompatible
    types, C99 6.7p4, a constraint violation a conforming implementation must
    diagnose:

    ```
    _myDriveStatus         :138  unsigned int *   :554  unsigned int
    _trackBuffer           :139  unsigned int     :547  void *
    _lastSectorsPerTrack   :141  char             :516  unsigned char
    _track_offset          :142  int              :513  unsigned int
    _driveOSEventIDptr     :305  unsigned int *   :504  void *
    _lastErrorsPending     :312  unsigned char    :505  unsigned int
    _FloppySWIMIIIRegs     :335  int              :515  void *
    _GRCFloppyDMAChannel   :337  void *           :562  unsigned int
    ```

    (`char` and `unsigned char` are distinct types in C, so
    `_lastSectorsPerTrack` is a conflict like the rest.) All eight are
    pre-existing — none was introduced by this branch — and all eight are
    outside its permitted edit set. Settling each one means deciding what the
    object actually is, which needs evidence this task did not have; they are
    left for scheduling as a group rather than one at a time.

    The `_GRCFloppyDMAChannel` case in detail. `FloppyDisk.h:337` says
    `extern void *_GRCFloppyDMAChannel;` and `FloppyDisk.h:562` says
    `extern unsigned int _GRCFloppyDMAChannel;`. Both are at file scope in the
    same header, so unlike uncertainty 4 this one *is* a same-scope
    redeclaration with an incompatible type — C99 6.7p4, a constraint
    violation a conforming implementation must diagnose. The definition
    (`FloppyDisk.m:8540`) is `unsigned int`, agreeing with `:562`.

    This is the object `OpenDBDMAChannel` writes through: `HALReset` passes
    `&_GRCFloppyDMAChannel` as `channelPtr` (`FloppyDisk.m:4820`), and the
    function stores `&_PrivDBDMAChannelArea` into it — see 12.5. So the symbol
    Task 5 made live for the first time is the one carrying the conflict. Both
    spellings are pre-existing: they predate Task 5, which added no declaration
    of this symbol. Settling it means deciding whether the channel handle is a
    pointer or a word — the binary stores an address into it, which argues for
    `void *`, but every existing use in the tree passes it by value to
    `ResetDBDMA` and friends as `unsigned int`. Changing it touches eight call
    sites, which is outside this task's permitted edit set, and it is left for
    scheduling.
11. **`_IOExitThread` is the one misspelled kernel import, and it is an
    undefined symbol at link.** `FloppyDiskThread.m:111` declares
    `extern void _IOExitThread(void);` and `FloppyDiskThread.m:237` calls
    `_IOExitThread();`. The binary imports `_IOExitThread` — undefined, address
    0, no section — so under the Mach-O rule (uncertainty 5) the source name must
    be `IOExitThread`. As written, our source emits a reference to
    `__IOExitThread`, which nothing defines.

    It is the **only** one of the reference's 48 undefined `_`-prefixed imports
    that is misspelled. Twenty-one of the 48 are already referenced bare and
    correct in our source (`IOMalloc`, `IOFree`, `bcopy`, `sleep`, `timeout`,
    `page_size`, `kernel_map`, `kmem_alloc_wired`, `kvtophys` among them); the
    remaining 26 have no reference in the source under either spelling. So this
    is a single-token defect, not a class of them.

    `symbol_name_check.py` cannot see it: it gates *defined* `__TEXT,__text`
    symbols (`:46`), and `_IOExitThread` is neither defined nor in `__text`.
    Both sites are outside this task's edit set; recorded for scheduling, and it
    should be fixed alongside uncertainty 5's data symbols, which have the same
    cause.
12. **Seven `static` data objects have the exact shape Task 5 deleted three
    `static` functions for.** Task 5's three deletions (12.8) rested on C99
    6.2.2p7: a `static` definition that follows a file-scope `extern`
    declaration of the same name in the same translation unit. Seven data
    objects in the same two files have that shape and were left in place:

    ```
    FloppyDiskInt.m:117    static int _DataSource            FloppyDisk.h:95   extern void *
    FloppyDiskInt.m:128    static const char *_fdCommandValues[]  FloppyDisk.h:578  extern LookupEntry []
    FloppyDiskInt.m:134    static const char *_fdrValues[]        FloppyDisk.h:576  extern LookupEntry []
    FloppyDiskThread.m:36  static const char *_fdOpValues[]       FloppyDisk.h:577  extern LookupEntry []
    FloppyDiskThread.m:45  static const char *_fdrValues[]        FloppyDisk.h:576  extern LookupEntry []
    FloppyDiskThread.m:53  static const char *_densityValues[]    FloppyDisk.h:113  extern DensityEntry []
    FloppyDiskThread.m:58  static int _fdDensityInfo[]            FloppyDisk.h:624  extern DensityInfoEntry []
    ```

    `FloppyDiskInt.m:7` and `FloppyDiskThread.m:7` both `#import "FloppyDisk.h"`,
    so every one of these is **two** defects at once: a 6.2.2p7 linkage conflict
    like the three functions, and a 6.7p4 incompatible-type conflict like
    uncertainty 10's eight.

    **Keeping them may well be right.** Five of the seven exist only to feed the
    retained source-only debug helpers of section 8 — `_fdCommandValues` and
    `_fdrValues` are read by `_getCommandName`/`_getResultName`
    (`FloppyDiskInt.m:141`, `:150`), `_fdOpValues` by `_getOpName`
    (`FloppyDiskThread.m:88`), and `FloppyDiskThread.m`'s `_fdrValues` and
    `_densityValues` are the arrays passed to `_getStatusName` at `:536` and
    `:603`. Those helpers have no counterpart in Apple's binary, so there is no
    reference evidence for what the file-scope objects should be. The other two
    are not debug-only: `_DataSource` is assigned at `FloppyDiskInt.m:246`/`:248`
    and `_fdDensityInfo` is read at `FloppyDiskThread.m:615`. But neither the
    decision to keep them nor
    the defect itself was documented before now, and Task 5 gave the identical
    shape the opposite treatment a few lines away in the same file — the
    `static` `GetBusyFlag`/`ResetBusyFlag` it deleted stood at
    `FloppyDiskInt.m:125`/`:130`, immediately below `_DataSource` at `:117`.
    Recorded so the asymmetry is deliberate rather than accidental; settling it
    is out of scope here.

## 13. Gate results after Task 5

```
symbol_name_check.py --binary <ref> --source-dir <lks>
  hand-written C symbols: 141
  missing definitions   : 0
  exit 0

selector_check.py <ref> <lks>
  reference selectors: 62
  our definitions:     60
  renames (0):  duplicates (0):  extra (0):
  missing (2):  +[FloppyKernelServerInstance kernelServerInstance]
                +[FloppyVersion driverKitVersionForFloppy]
  exit 0

pytest tools/binrecon/tests -q
  866 passed, 4 skipped
```

The two "missing" selectors are the build-generated class methods of bucket 4.

Section 11's table is now settled: 5 C functions written, 3 `static` duplicates
deleted, the 53rd selector renamed. The map, ledger, profiles and checkers were
not touched — Task 6 regenerates those.

---

## 14. Task 6 — the remap, and the state of the reconstruction

This section supersedes sections 3, 4, 7, 8, 10 and 11, which record the Task 3
measurement taken before the selector rename and the five bodies.

### 14.1 The analysis is unchanged

`filter_named_functions.py` was re-run against
`tools/binrecon/out/floppy-ppc/published/analysis-reference-ida.json` and
produced the same `analysis-named.json`:

```
functions: 202
unnamed  : 0
lowest   : 0x8c
sha256   : 7CFD5E18A7CF4C5A8196BF7CC93113C6BE6AC90E770A03EDC58001C8D848BA8B
```

Same binary, same 202 named functions, `lowest` still `0x8c`. Nothing in Tasks 4
and 5 touched the reference side; only the source moved.

### 14.2 Four-category coverage after the remap

`binrecon source-map --objc-methods` (no `--scope-to-objc`), the same invocation
as Task 3 Step 2:

| category | Task 3 | **Task 6** |
| --- | --- | --- |
| `mapped` | 141 | **200** |
| `unmapped` | 59 | **2** |
| `duplicate_candidates` | 2 | **0** |
| `boundary_disputed` | 0 | **0** |
| **total** | **202** | **202** |

200 + 2 + 0 + 0 = 202, the whole named-function set. The movement is +59 mapped,
and it decomposes exactly:

| what moved | count | fixed by |
| --- | --- | --- |
| Objective-C selectors carrying a spurious leading underscore | 52 | Task 4 |
| C functions with no source definition (the five gaps) | 5 | Task 5 |
| C functions with two source definitions (`GetBusyFlag`, `ResetBusyFlag`) | 2 | Task 5 |
| **total** | **59** | |

52 + 5 = 57 came out of Task 3's `unmapped` (59, of which 2 were and remain the
build-generated methods), and 2 came out of `duplicate_candidates`.
`duplicate_candidates` is now **0**: there is nothing left to enumerate.

The 2 that stay `unmapped` are the build-generated class methods:

```
0xc038  +[FloppyKernelServerInstance kernelServerInstance]   20 bytes
0xc04c  +[FloppyVersion driverKitVersionForFloppy]           16 bytes
```

They are emitted by the driver build machinery, have no hand-written source by
definition, and are correctly outside the 201.

### 14.3 Coverage against the 201 hand-written functions

202 named functions = 200 hand-written + 2 build-generated. The binary defines
**203** `__TEXT,__text` symbols; the 203rd is `_fdrToIo`, which has no entry in
IDA's function list (the list's lowest address is `0x8c`) and therefore cannot
appear in any of the map's four categories.

So the map covers **200 of the 201 hand-written functions**, and the 201st is
`_fdrToIo` — a known exclusion by construction, **not a gap and not a phantom**.
Section 5 carries the byte evidence that the code at `__text+0` is real.

`selector_check.py` cannot confirm `_fdrToIo`: unlike every prior driver in this
series, the address-0 function here is a plain C function, not a `+probe:`
method. The confirmation comes from `symbol_name_check.py`, which works from
definition sites:

```
$ symbol_name_check.py --binary <ref> --source-dir <lks>
hand-written C symbols: 141
missing definitions   : 0
exit 0
```

**0 missing** means every one of the 141 hand-written C symbols, `_fdrToIo`
included, has a definition site. Independently: `fdrToIo` is defined at
`FloppyDisk.m:8679` as `unsigned int fdrToIo(unsigned int fdrCode)` and declared
at `FloppyDisk.h:582`.

### 14.4 Buckets

```
$ bucket_functions.py analysis-named.json source-map.json
total functions: 202
  mapped: 200
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 0
  4-build-generated-class: 2
      0xc038  +[FloppyKernelServerInstance kernelServerInstance]  (20 bytes)
      0xc04c  +[FloppyVersion driverKitVersionForFloppy]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 0
counted: 202
RECONCILES: yes
```

Bucket 6 is now empty — Task 3's 59 entries are gone, for the reasons tabulated
in 14.2. Buckets 1 and 2 are empty as always for a `_reloc` kernel server
(relocatable object output, no crt startup, no PIC symbol stubs); bucket 3 is
empty because the 506 unnamed jump islands were filtered out before mapping.
Bucket 4 holds exactly the two build-generated class methods. 200 + 2 = 202.

### 14.5 PowerPC invariant check — unchanged

```
$ ppc_invariant_check.py --binary <ref> --analysis analysis-named.json
symbol _fdrToIo at 0x0 has no function start in the analysis, but code is
present: the bytes there are a function prologue, so the analysis omits a
real function
214 scattered/difference-form relocations (target section verified, field is a difference, not an address)
71 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
3932 fused relocations, 1 violations
exit 1
```

Byte-identical to Task 3's result, as it must be — the checker reads the binary
and the analysis, neither of which changed. The single violation is the
`_fdrToIo` line, and it reports **code present**. Exit 1 reflects that one
violation; it is the known exclusion, not a regression.

### 14.6 The ledger was regenerated

`seed_ledger.py source-map.json <ref> ledger.json` was re-run against the **new**
map and produced **202 entries**.

This step is not optional. On the `PPCSerialPort` branch the ledger was left
unregenerated after a remap and all 64 of its citations pointed at lines that had
moved. Verified programmatically here, against the map and against the source:

- the ledger's 202 addresses are **exactly** the union of the map's four
  categories — set equality, not merely equal counts;
- every entry's `names` and `size` equal the map's `reference_names` and `size`;
- all **200** `mapped` entries carry a `source_path`/`source_line` identical to
  the map's — **0 mismatches**;
- all 200 cited lines are in range, and each one **textually names its own
  symbol**: a C entry's line matches `\bname\s*\(`, a method entry's line begins
  with `+`/`-` and contains the first selector keyword. **0 failures**;
- the 2 entries drawn from `unmapped` carry no source citation at all — the
  seeder invents nothing for a build-generated method.

Task 3's ledger had 141 citations and 61 uncitable entries; this one has 200
and 2.

### 14.7 Objective-C surface

```
$ selector_check.py <ref> <lks>
reference selectors: 62
our definitions:     60
renames (0):
duplicates (0):
missing (2):
    +[FloppyKernelServerInstance kernelServerInstance]
    +[FloppyVersion driverKitVersionForFloppy]
extra (0):
exit 0
```

The two missing are the build-generated class methods. 0 renames, 0 duplicates,
0 extras.

**What this proves, and what it does not.** `selector_check.py` compares the
binary's method symbols with our `@implementation` definitions **by name**. It
proves that every hand-written selector Apple shipped exists in our source under
Apple's exact spelling, and that we define no selector Apple did not ship. It
proves nothing whatever about the 60 bodies behind those names. Those bodies came
out of a decompiler — their parameters are still called `param_1`, `param_2` —
and not one has been compared instruction-by-instruction against the reference.
**Coverage is not correctness.** The same caveat applies to the map's
`mapped: 200`: a mapping is a name-to-definition-site correspondence, not a
behavioural equivalence. The only bodies in this driver derived from the
disassembly are the five of section 12.

### 14.8 Suite

```
$ PYTHONPATH=tools/binrecon pytest tools/binrecon/tests -q
866 passed, 4 skipped
```

Baseline 864 plus the 2 parametrised profile cases Task 1 added. No task in this
plan added or removed a test.

### 14.9 Carried-forward items settled here

1. **Nine stale line citations** left in this document by Task 5's own fix wave
   were corrected, each verified against the current file before it was written:
   `FloppyDisk.m` `8595`→`8619` (2 places — `8595` is now `_fdOpValues`, a
   different symbol), `744`→`751`, `747`→`754`, `253`→`260` (3 places),
   `2231`→`2241` (3 places), `1313`→`1320` (2 places), `1584`→`1592`, and
   `7943`→`7967` (`7943` is now inside `TestCacheDirtyState`). A tenth was found
   while checking them: section 5 cited `FloppyDisk.m:8434` for `fdrToIo`, which
   is now a padding word in a table; the definition is at `8679`. Fourteen
   occurrences in all.

   Checking those turned up **seven more** stale citations in section 12 that
   the carried-forward list did not name, all corrected the same way:
   `FloppyDisk.m` `2184`→`2286` (`fdstrategy`'s `fd_dev_to_id` declaration) and
   `299`→`306` (the `psize:` argument); `FloppyDisk.h` `297`→`299`
   (`OpenDBDMAChannel`, 2 places), `414`→`416` (`MediaScanTask`), `191`→`193`
   (`fdstrategy`), `122`→`123` and `506`→`508` (`DAT_0000fb88`). Every citation
   in sections 12 and 14 was then re-extracted mechanically and resolved against
   the current files; all of them now land on a line that names the symbol they
   claim, with two deliberate exceptions that are labelled as historical in the
   text — `FloppyDisk.m:8434` (the stale `fdrToIo` citation being described just
   above) and `FloppyDiskInt.m:118` (where `static BOOL _BusyFlag` stood at
   commit `f31c0693`, before Task 5 deleted it).

   Line citations inside sections 3, 4, 6, 7, 8, 10 and 11 were **not** rewritten.
   Those sections describe a tree that no longer exists — they cite `static`
   definitions Task 5 deleted — so renumbering them would have made them look
   current while their content stayed historical. They carry a snapshot banner
   instead.

2. **The `donone` conflict was completed**, not left as a residual. See
   uncertainty 4 in 12.9 for the account, and for the correction to Task 5's
   "not necessarily diagnosed" claim.

3. **`_GRCFloppyDMAChannel`'s incompatible double declaration** is recorded as
   uncertainty 10 in 12.9 and deliberately not fixed.

### 14.10 Acceptance — the spec's eleven items

**Standing constraint on every line below: nothing was compiled.** There is no
PowerPC toolchain and no host C compiler in this environment, and no `make` was
run. Every claim here is a claim of **correspondence to the binary** — its symbol
table, IDA's function list, its relocations and its disassembly — never a claim
of buildability. Where this document says the renamed symbols "would now match"
Apple's, that is an argument from the Mach-O naming rule (the compiler prepends
exactly one underscore to a file-scope C identifier), reinforced by
`symbol_name_check.py`. It is not an observation of a build.

| # | item | verdict | evidence |
| --- | --- | --- | --- |
| 1 | Two profiles created, `test_ppc_profile_inventory` updated, suite green | **pass** | Task 1, commit `ad5fa6ca`; suite 866/4 in 14.8 |
| 2 | All 136 misnamed C functions renamed, every call site updated, driven by the binary's exact name list, word-bounded | **pass** | Task 2, commit `53da4375`: 997 insertions / 997 deletions across 4 files, one per token; the gate went 141 missing → 5 (section 9). The reviewer re-derived the whole rename from the parent commit plus the binary's own symbol list and got byte-identical files |
| 3 | No identifier outside those 136 renamed — none of the 157 `_`-prefixed globals, types or selectors | **pass** | Same commit: insertions equal deletions and every changed token is one of the 141 names. Spot-checked again here — `_FloppyState`, `_FdBuffer`, `_Floppy_dev`, `_FloppySWIMIIIRegs`, `_FloppyIdMap`, `_fd_block_major`, `_PrivDBDMAChannelArea`, `_busyflag` all still present and still underscored. One of the 157, `static BOOL _BusyFlag` (`FloppyDiskInt.m:118` at `f31c0693`), no longer exists — it was **deleted**, not renamed, in Task 5 as the orphaned state of the two `static` duplicates (12.8). Deletion is outside what this item forbids, but it is recorded rather than glossed |
| 4 | `symbol_name_check.py` reports 141 symbols, 0 missing, exit 0 | **pass** | 14.3, run in this task |
| 5 | All 52 misnamed selectors renamed; `selector_check.py` 0 renames, 0 duplicates, 2 missing (both build-generated), 0 extra | **pass** | 14.7, run in this task. Task 4 renamed 52, Task 5 the 53rd (`fcCmdXfr:driveInfo:`, 12.7) |
| 6 | The map covers 200 of the 201 hand-written functions; the 201st is `_fdrToIo`, a known exclusion | **pass** | 14.2 and 14.3: `mapped` 200, and the only hand-written function outside the map's universe is `_fdrToIo` |
| 7 | `duplicate_candidates` is 0, or every entry enumerated with evidence | **pass** | 14.2: **0**. Nothing to enumerate |
| 8 | `RECONCILES: yes`, with the two build-generated class methods accounted for | **pass** | 14.4: `RECONCILES: yes`, counted 202, bucket 4 holds exactly those two, by address |
| 9 | All five bodies written, each with an instruction-by-instruction account covering every branch | **pass** | Sections 12.1–12.5. Definitions present at `FloppyDisk.m` `2072` (`fdminphys`), `1467` (`fd_dev_to_id`), `5797` (`OpenDBDMAChannel`), `7930` (`TestCacheDirtyState`), `5526` (`MediaScanTask`). Every span reconciles as `body + 16 × islands`. Two bodies deliberately diverge from the reference and each says so in its own source comment, described in 12.3 and 12.5. These are prose records, **not** ledger statuses: no ledger entry carries an `intentional-mismatch` status, and all 202 are `status: unexamined` |
| 10 | All three redundant `static` copies removed; the six source-only helpers retained and recorded | **pass** | 12.8. Verified again here: no `static` `GetBusyFlag`, `ResetBusyFlag` or `_getStatusName` remains anywhere in the source dir, and all six helpers are still defined (`_getStatusName`/`_getDensityName`/`_getIoctlName` in `FloppyDisk.m`, `_getCommandName`/`_getResultName` in `FloppyDiskInt.m`, `_getOpName` in `FloppyDiskThread.m`) and recorded in section 8 |
| 11 | The binrecon suite stays green | **pass** | 14.8: 866 passed, 4 skipped |

**Eleven of eleven pass.** Two qualifications travel with that result and are not
defects in it:

- Item 5 certifies **names**, not behaviour (14.7). The 60 Objective-C bodies
  remain unverified against the reference.
- Item 3's `_BusyFlag` deletion is a real change to one of the 157, made in
  Task 5 for a documented reason. It is a removal, not a rename, so the item
  holds as written — but the item's spirit is "nothing outside the 136 moved",
  and one thing outside the 136 did go away.
- Item 3 says the C rename touched none of the 157 `_`-prefixed identifiers.
  That is true and it is what the item asks, but it is a **scoping** result, not
  a correctness one: uncertainty 5 shows the binary spells those globals bare,
  so leaving them underscored is a defect deferred, not a defect avoided. The
  spec and plan were reworded so the next driver schedules it rather than
  preserving it deliberately.

**Twelve** open uncertainties and pre-existing defects remain recorded in 12.9.
None was closed by guessing, and none blocks acceptance; several — the
`_fdCommandValues` double definition, the `fdstrategy` triple declaration, the
**eight** incompatible double declarations in `FloppyDisk.h`, `ResetDBDMA`'s
divergent body erasing the DBDMA register base, the misspelled `_IOExitThread`
import, and the data symbols that still carry the spurious underscore — will
have to be scheduled before this driver can be built.
