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
