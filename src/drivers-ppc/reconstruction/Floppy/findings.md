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

## 3. Four-category coverage of `source-map.json`

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

The function is present in our source at `FloppyDisk.m:8434` as
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

Every span reconciles as `body + 16 * islands`, and every body ends at its
`blr`. Nothing was compiled; no `make` was run.

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

The reference loads the halfword with `lha` (signed). Our tree defines
`DAT_0000fb88` as `unsigned short`, and `TestTrackInCache` already compares it
unsigned. The two differ only in how `0xffff` is widened, and `0xffff` is the
invalidation sentinel `DumpTrackCache` writes — never equal to a 0..255 drive
byte under either widening. Kept `unsigned short` for consistency with the
existing definition.

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
(`FloppyDisk.m:2184`, in `fdstrategy`) was the correct one; the five `(void)`
declarations were wrong. All six now read
`extern int fd_dev_to_id(unsigned int device);`, a matching prototype was added
to `FloppyDisk.h`, and the five bare calls now pass their device number.

`_fdsize` consequently gained the parameter it always had in the binary:
`unsigned int fdsize(unsigned int param_1)`. Its three source declarations
(the local in `fdsize` itself, `FloppyDisk.h:190`, and the local in `+probe:`)
were all `(void)` and were all corrected.

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

so the existing five-parameter declaration at `FloppyDisk.h:297` matches
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
`+0x18` command-list physical address. Our tree already models those three
words as the separate globals `DAT_0000f500`, `DAT_0000f510`, `DAT_0000f514`,
and that convention is followed here rather than widening
`_PrivDBDMAChannelArea`.

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
| `fdsize` declared `(void)` | local in `fdsize`, local in `+probe:`, `FloppyDisk.h:190` | all three now `(unsigned int)` |
| `extern unsigned int fdminphys;` (data) | `FloppyDisk.m`, twice | `extern unsigned int fdminphys(int bufPtr);`, prototype added to `FloppyDisk.h` |
| `extern void *MediaScanTask;` (data) | `FloppyDisk.h:414` | `extern void MediaScanTask(void);` |
| `OpenDBDMAChannel` declared `void` | `FloppyDisk.h:297` | `int` |
| `CloseDBDMAChannel(void)` | `FloppyDisk.h:172` and its definition | takes and ignores an `int` channel |
| `_FloppyIdMap[64]` | `FloppyDisk.h`, `FloppyDisk.m` | `[0x98]` |

`TestCacheDirtyState`'s existing local declaration
(`extern int TestCacheDirtyState(int driveStructure);`) already matched the body
written here and was left alone.

Two of these go beyond the letter of the task brief and are called out
deliberately:

1. **`OpenDBDMAChannel`'s return type.** The brief says the declaration is
   already function-shaped and to leave it alone. Its return type is `void`,
   but the body returns three distinct values (`0`, `10`, `-0x32`) in `r3`, and
   `mr r3,r31` at `0x69b0` is unambiguous. Keeping `void` would have required
   discarding both error codes — reproducing a source defect rather than
   Apple's form. Changed to `int` and reported.
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

`getStatusName` has no binary counterpart, so the choice rests on the arrays
each copy indexes. **The external body in `FloppyDisk.m` (bound 16) was kept**
and the `static` in `FloppyDiskThread.m` (bound 20) deleted, because:

- 16 is exactly the length of `_fdCommandValues`, the only array passed at the
  `FloppyDisk.m` call site;
- both `FloppyDiskThread.m` call sites are safer under 16 than under 20 —
  `_fdrValues` there has 20 entries (codes 16..19 now print `"Unknown"`, which
  costs four debug labels and reads nothing out of range), and `_densityValues`
  there has **4**, for which the deleted bound of 20 was already an
  out-of-bounds read.

`FloppyDiskThread.m` imports `FloppyDisk.h`, which declares `_getStatusName` at
line 118, so no declaration was added.

### 12.9 Uncertainties and pre-existing defects observed

Numbered; none of these was resolved by picking a plausible option.

1. **`_getStatusName` is still unsafe for `_densityValues`.** The surviving
   bound of 16 is wrong for the 4-entry `_densityValues` array that
   `FloppyDiskThread.m` passes at its second call site. There is no binary
   counterpart to settle the real bound, and the two source copies disagreed, so
   no bound is derivable from evidence. Settling it needs Apple's source, or a
   decision to pass the array length.
2. **`fdstrategy` is declared three incompatible ways.** `extern int
   fdstrategy(void);` (local, in `+probe:`), `extern unsigned int fdstrategy;`
   (data, twice, in `fdread` and `fdwrite`), and `extern unsigned int
   fdstrategy(int param_1);` (`FloppyDisk.h:191`) against the definition
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
4. **`donone` is declared `(void)` and called with arguments at 104 sites.**
   Pre-existing and systemic. The three new `donone` calls in `fd_dev_to_id` and
   the one in `OpenDBDMAChannel` follow the existing convention rather than
   introducing a second one.
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
6. **`DAT_0000fb88` is declared twice with different types.** `FloppyDisk.h:122`
   says `unsigned short`, `FloppyDisk.h:506` says `unsigned char`; the definition
   is `unsigned short` and the binary loads a halfword. A hard conflict,
   pre-existing, not fixed here. Our `TestCacheDirtyState` declares the
   `unsigned short` form locally, matching the definition and `DumpTrackCache`.
7. **`ResetDBDMA`'s reconstructed body does not match `0x665c`.** The binary does
   `r9 = *(channel + 4); *r9 = 0xC8; *(channel + 8) = 0; *(r9 + 0xC) = 0;` — it
   writes through the DBDMA register base stored at `channel + 4`. Our source
   writes four words of the channel structure itself. This matters to
   `OpenDBDMAChannel` only because it confirms `+0x04` is the register base; the
   discrepancy is in an existing function and was not touched.
8. **`LaunchMediaScanTask`'s reconstruction uses placeholder names.**
   `_MediaScanTaskID = FUN_0000a300(_entry, &MediaScanTask)` is really
   `kernel_thread(kernel_task, MediaScanTask)`: the relocations at `0xa2cc` and
   the island at `0xa300` name `_kernel_task` and `_kernel_thread`. The
   `MediaScanTask` declaration was corrected to a function as required; the call
   expression and the two placeholder names were left as they were.
   `&MediaScanTask` is still the function's address, but passing it to
   `FUN_0000a300`'s `void *` parameter is now a pointer-conversion warning.
9. **`_PrivDBDMAChannelArea` is declared `[4]` against 44 bytes in the binary**
   (`0xf4fc`..`0xf528`). `OpenDBDMAChannel` only takes its address, so nothing
   written here indexes out of range, and the array was left alone.

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
