# IONDRVSupport — measurement findings

Reference binary: `Drivers/ppc/IONDRVSupport.config/IONDRVSupport_reloc`
SHA-256 `C12688AE327660F69F16375E45E089673C9E0955FA6FFEDBB31F3B0C23CE85B1`
Source under map: `src/driverkit-3/libDriver/ppc/` — **five files**, see section 4.

Spec: [docs/superpowers/specs/2026-07-28-iondrvsupport-measurement-design.md](../../../../docs/superpowers/specs/2026-07-28-iondrvsupport-measurement-design.md).

**Nothing here was compiled.** There is no PowerPC toolchain and no host C
compiler in this environment, and no `make` was run. Every number below comes
from the Mach-O symbol table, IDA's function list, and the checkers under
`tools/binrecon`.

**This measurement wrote no function bodies and renamed nothing.** No file under
`src/driverkit-3/` or `src/kernel-7/` was modified. Where this document says a
symbol "would match" after a rename, that follows from the Mach-O naming rule —
the compiler prepends exactly one underscore to a C identifier — not from a
build.

**The spec's headline gap figure does not survive measurement.** Section 1.1 of
the spec sized the work at "16,276 bytes across 45 C functions — 42% of
`__text`", split across four largely independent clusters, and decomposed the
reconstruction into four follow-on sub-projects on that basis. That figure
reproduces exactly (section 11) — and **32 of the 45 are false positives from
two regex defects in `symbol_name_check.py`**, 12 more are existing bodies
misspelled by one underscore, and **one** is a genuinely absent function.
Section 17 states what the follow-on work actually is.

---

## 1. The reference analysis

`tools/binrecon/out/iondrvsupport-ppc/published/analysis-reference-ida.json`:

```
functions: 461
unnamed  : 270
lowest   : 0x50
sha256   : C12688AE327660F69F16375E45E089673C9E0955FA6FFEDBB31F3B0C23CE85B1
```

`filter_named_functions.py` produced
`tools/binrecon/out/iondrvsupport-ppc/analysis-named.json`:

```
functions: 191
unnamed  : 0
lowest   : 0x60
sha256   : C12688AE327660F69F16375E45E089673C9E0955FA6FFEDBB31F3B0C23CE85B1
```

461 − 270 = **191 named functions**, and `input.sha256` is byte-identical
across the two documents, so the filtered analysis still binds to the same
binary. `lowest` rose `0x50` → `0x60` because the entry at `0x50` was one of the
unnamed jump islands.

The 270 unnamed entries are the PowerPC jump islands the linker emits between a
`bl` site and its target. They carry no symbol and no source and are excluded
before mapping. They total 4,320 bytes, all of them 16 bytes apiece.

## 2. The symbol partition

`__TEXT,__text` is 38,852 bytes and holds **192 defined symbols over 192
symbol-table entries** — 192 distinct names, so there is no aliasing in `__text`.

IDA's view of the section carries 196 entries; the four extra (`def_6D44`,
`def_7B4C`, `def_7FE4`, `def_8680`) are IDA-synthesized placeholders for
anonymous locals, not defined symbols, and do not appear in the Mach-O symbol
table at all.

| group | count |
| --- | ---: |
| Objective-C selectors | 68 |
| C functions | 124 |
| **total defined `__TEXT,__text` symbols** | **192** |

192 defined symbols against 191 named analysis functions. The difference is
exactly one symbol, `-[IONDRVFramebuffer doControl:params:]` at `__text+0` —
section 12.

### 2.1 Classes in the binary

| class | selectors in `__text` |
| --- | ---: |
| `IONDRVFramebuffer` | 24 |
| `IONDRVFramebuffer(ProgramDAC)` | 5 |
| `IOOFFramebuffer` | 11 |
| `IOIX3DNDRV` | 9 |
| `IOATINDRV` | 9 |
| `IOIXMNDRV` | 8 |
| `IONDRVSupportKernelServerInstance` (build-generated) | 1 |
| `IONDRVSupportVersion` (build-generated) | 1 |
| **total** | **68** |

The binary has **no `IOATIMACH64NDRV` and no `IOATIRAGE128NDRV`** — it carries a
single flat `IOATINDRV`. Our tree does not. Section 15.

## 3. How sizes in this document are derived

Two size columns appear throughout, and they mean different things:

- **Extent** is IDA's measured function size, carried in `analysis-named.json`
  and in `source-map.json`. It is the body only.
- **Next-symbol delta** is `next_symbol.address − this_symbol.address`, computed
  over the 192 `__TEXT,__text` symbols sorted by address, with the last one
  running to the end of the section. **It is not a measured extent**: it includes
  any trailing jump island the linker placed between one function and the next.

The two differ by exactly the islands. `_m64WaitForIdle` has an extent of 60 and
a delta of 76; the 16-byte remainder is the unnamed island at `0x21f4`.

The deltas partition `__text` exactly — they sum to 38,852 — which is what makes
them useful for sizing a cluster. Extents do not: 34,452 (named) + 4,320
(islands) + 80 (the address-0 body IDA omits) = 38,852.

**The spec's byte figures are next-symbol deltas.** Its "ATI Mach64 5 / 1,420",
"IXMicro 7 / 1,948" and "Name Registry 8 / 848" reproduce to the byte as delta
sums (sections 8 and 11), which is how the derivation was identified.

## 4. The source-scoping problem

**This is the first driver in the series whose source shares a directory with
other binaries' sources.** `src/driverkit-3/libDriver/ppc/` holds 17 `.m` and
`.c` files and builds at least four separate binaries — `IOApplePCIBus`,
`IODisplay`, `IONDRVSupport`, plus framework code that ships in none of them.
There is no `IONDRVSupport.drvproj` and no directory that belongs to this binary
alone.

### 4.1 How the file list was derived

Not by a name search, and not from the spec's table. The binary's
`__TEXT,__text` symbol names were read with `binrecon.macho.read_macho`, and
`binrecon.source_map.source_sites` — the same definition-site scanner the source
map itself uses — was run over **every** `.m` *and* `.c` file in the directory,
one file at a time. Each file's definition keys were intersected with the
binary's `__text` names.

Two choices distinguish this from the spec's derivation, and both matter:

1. **Objective-C methods are matched on the full symbol-table spelling**
   `-[Class(Category) selector]`, never on the bare selector. Matching bare
   selectors across classes is what manufactures "coincidental matches".
2. **`.c` files were scanned as well as `.m` files.** The spec's §3 speaks only
   of "eleven `.m` files". `source_sites` scans `{".m", ".c"}`; a `.m`-only
   derivation cannot see a contributing `.c` file, and two of them contribute 39
   definitions.

### 4.2 Every file in the directory

| File | C defs matching `__text` | Selectors matching `__text` | Total defs in file | Scoped |
| --- | ---: | ---: | ---: | :---: |
| **`IONDRVFramebuffer.m`** | **8** | **58** | 90 | **in** |
| **`IONDRVLibraries.m`** | **61** | 0 | 61 | **in** |
| **`IONDRVInterface.m`** | **6** | 0 | 6 | **in** |
| **`IOPEFInternals.c`** | **26** | 0 | 26 | **in** |
| **`IOPEFLoader.c`** | **13** | 0 | 13 | **in** |
| `IODBDMA.m` | 0 | 0 | 8 | out |
| `IODeviceTreeBus.m` | 0 | 0 | 20 | out |
| `IOFramebuffer.m` | 0 | 0 | 71 | out |
| `IOMacRiscPCI.m` | 0 | 0 | 18 | out |
| `IOPCIDevice.m` | 0 | 0 | 9 | out |
| `IOPPCDeviceDescription.m` | 0 | 0 | 1 | out |
| `IOPPCDirectDevice.m` | 0 | 0 | 2 | out |
| `IOPropertyTable.m` | 0 | 0 | 17 | out |
| `IOSmartDisplay.m` | 0 | 0 | 24 | out |
| `IOTreeDevice.m` | 0 | 0 | 37 | out |
| `disk_label.c` | 0 | 0 | 14 | out |
| `memcpy.c` | 0 | 0 | 1 | out |

**Five files in, twelve out.** The scoped five hold 196 definitions and cover
169 of the binary's 192 `__text` names; the other twelve contribute **zero**
matches between them.

### 4.3 Where this disagrees with the spec

| | Spec §3 | Measured |
| --- | --- | --- |
| Contributing files | 3 | **5** |
| `IONDRVLibraries.m` C defs | 54 | **61** |
| `IONDRVFramebuffer.m` C defs | 8 | 8 |
| `IONDRVFramebuffer.m` selectors | 48 | **58** |
| `IONDRVInterface.m` C defs | 5 | **6** |
| `IOPEFInternals.c` | not considered | **26 C defs** |
| `IOPEFLoader.c` | not considered | **13 C defs** |
| Files with coincidental selector matches | 8, `IOFramebuffer.m` largest at 11 | **0 files, 0 matches** |

Three substantive corrections:

1. **Two `.c` files contribute 39 definitions.** `IOPEFInternals.c` (the PEF
   container reader — `_PEF_OpenContainer`, `_PEF_RelocateSection`,
   `_UnpackFullSection`) and `IOPEFLoader.c` (`_PCodeOpen`, `_PCodeFindMain`,
   `_SatisfyImports`) are the PEF/CFM machinery that loads the Mac OS NDRV
   itself. Excluding them would have left 39 real functions unmapped and
   attributed to absent source.
2. **The eight "coincidental selector matches" do not exist.** `IOFramebuffer.m`
   defines `-[IOFramebuffer open]`; the binary contains `-[IONDRVFramebuffer open]`.
   Those are different symbols and the full-name match rejects the pairing. The
   spec's 11 for `IOFramebuffer.m` is an artifact of comparing bare selectors
   across a superclass boundary. There is no superclass-collision problem here.
3. **The `.m` counts are higher than the spec's** (61/58/6 against 54/48/5),
   because the spec discounted the matches it read as collisions.

### 4.4 Cross-check against the map's own `source_path` values

The spec (§3.2) requires the derived list be cross-checked against the map once
it exists. The map's 165 mapped entries cite exactly five distinct
`source_path` values, and they are exactly the five scoped files:

| `source_path` | mapped C | mapped selectors | mapped extent bytes |
| --- | ---: | ---: | ---: |
| `…/IONDRVFramebuffer.m` | 5 | 57 | 9,892 |
| `…/IONDRVLibraries.m` | 58 | 0 | 6,196 |
| `…/IONDRVInterface.m` | 6 | 0 | 1,372 |
| `…/IOPEFInternals.c` | 26 | 0 | 9,864 |
| `…/IOPEFLoader.c` | 13 | 0 | 2,948 |
| **total** | **108** | **57** | **30,272** |

The residuals reconcile: `IONDRVFramebuffer.m`'s 8 C definitions are 5 mapped
plus the 3 `_StdInt*` duplicates; its 58 selectors are 57 mapped plus
`doControl:params:`, which has no analysis row. `IONDRVLibraries.m`'s 61 are 58
mapped plus the same 3 duplicates.

### 4.5 The tooling this required

`selector_check.py`, `symbol_name_check.py` and `binrecon source-map` all walked
a directory and **returned zero for a file path instead of erroring** — a
scoped gate would have read green while measuring nothing. Task 1 introduced
`source_files(path, suffixes, recursive=True)` in `tools/binrecon/source_paths.py`
and converted all four walkers, preserving each site's recursion semantics.
Task 3 found a fifth guard the conversion had not reached: `cli.py` gated
`--source-dir` on `is_dir()` before `source_sites` was ever called, so the CLI
still rejected a file. That redundant guard was removed; `source_files()` already
raises for a missing path and for a wrong-suffix file.

## 5. Four-category coverage

Built with `--objc-methods` and **without** `--scope-to-objc`, over the five
scoped files. Scoping to Objective-C would have covered 68 of 192 symbols and
reported itself complete; 124 of the 192 are C.

```
mapped:                165
unmapped:               23
duplicate_candidates:    3
boundary_disputed:       0
TOTAL:                 191
```

165 + 23 + 3 + 0 = **191**, the whole named-function set. Every analysis function
lands in exactly one bucket.

Judged on `mapped ∪ unmapped` alone the total would read 188 and the three
`_StdInt*` entries would vanish silently — which is why coverage is judged across
all four categories.

By language:

| category | Objective-C | C |
| --- | ---: | ---: |
| `mapped` | 57 | 108 |
| `unmapped` | 10 | 13 |
| `duplicate_candidates` | 0 | 3 |
| `boundary_disputed` | 0 | 0 |

By class:

| class | mapped | unmapped |
| --- | ---: | ---: |
| `IONDRVFramebuffer` (incl. `(ProgramDAC)`) | 28 | 0 |
| `IOOFFramebuffer` | 11 | 0 |
| `IOIX3DNDRV` | 9 | 0 |
| `IOIXMNDRV` | 8 | 0 |
| `IOATINDRV` | 1 | 8 |
| `IONDRVSupportKernelServerInstance` | 0 | 1 |
| `IONDRVSupportVersion` | 0 | 1 |

`-[IOATINDRV getStartupMode:depth:]` at `0x2018` is the one `IOATINDRV` method
that maps: our tree keeps it on the base class (`IONDRVFramebuffer.m:1137`,
`@implementation IOATINDRV` at line 1135) while the other eight moved to the
subclass. Section 15.

### 5.1 A note on how the map matched the `(ProgramDAC)` category

IDA names the five category methods without their category
(`-[IONDRVFramebuffer setTheTable]`), while the Mach-O symbol table spells them
`-[IONDRVFramebuffer(ProgramDAC) setTheTable]`. `build_source_map` looks up
`set(analysis_names) | set(symbol_table_names_at_that_address)`, so the
category-qualified symbol-table spelling is what matched the source. The map's
`reference_names` field shows IDA's spelling, which is why the category does not
appear there. The five are correctly mapped.

## 6. Buckets

```
$ bucket_functions.py analysis-named.json source-map.json
total functions: 191
  mapped: 165
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 0
  4-build-generated-class: 2
  5-fn-with-source-site: 0
  6-fn-no-source-site: 24
counted: 191
RECONCILES: yes
exit 0
```

Buckets 1 and 2 are empty, as always for a `_reloc` kernel server: it is
relocatable object output with no crt startup and no PIC symbol stubs. Bucket 3
is empty because the 270 unnamed islands were filtered out before mapping rather
than carried in.

Bucket 4 holds exactly the two build-generated class methods,
`+[IONDRVSupportKernelServerInstance kernelServerInstance]` (`0x97a0`, 20 bytes)
and `+[IONDRVSupportVersion driverKitVersionForIONDRVSupport]` (`0x97b4`, 16
bytes). Both are emitted by the Kernel Server build machinery, have no
hand-written source, and are correctly outside the 190 hand-written functions.

Bucket 4's 2 + bucket 6's 24 = 26 = 23 `unmapped` + 3 `duplicate_candidates`,
which closes the partition against section 5.

## 7. Bucket 6 is not the gap count

**Twenty-three of bucket 6's 24 entries have a body in our tree.** The bucketer
labels anything outside `mapped` as "no source site"; that label is accurate for
exactly one entry.

| Sub-group | n | What it actually is |
| --- | --: | --- |
| `_StdInt{Handler,Enabler,Disabler}` | 3 | duplicate definitions, `IONDRVFramebuffer.m:602-612` **and** `IONDRVLibraries.m:809-819` — section 13 |
| `-[IOATINDRV …]` | 8 | class-split naming divergence; bodies live under `IOATIMACH64NDRV` — section 15 |
| `_m64*`, `_ix*`, `_ix3d*` | 12 | **over-underscored existing definitions — a rename question, not a body to write** — section 9 |
| `__eLMGetPowerMgrVars` | 1 | **the only genuine absent-source gap** — section 10 |
| **total** | **24** | of which **1** is a true absent-source gap |

### 7.1 Coverage of the 124 C symbols: 123 of 124

Derived over all 124 C names in `__TEXT,__text` against the union of the five
scoped files' definition sites:

```
exact-spelling definition site  : 111
over-underscored definition site:  12
no definition site at all       :   1  ->  __eLMGetPowerMgrVars
TOTAL with a definition site    : 123 of 124
```

An earlier draft of the Task 3 report recorded this as **111 of 124**, counting
only exact-spelling matches, and concluded that the 13 residual names had no
definition anywhere in `src/`. Twelve of the thirteen do. The corrected figure is
**123 of 124**.

Of the 68 selectors, 58 have a definition site; the 10 without are the 8
`IOATINDRV` methods (present under another class) and the 2 build-generated
class methods (which no hand-written source can define).

## 8. The complete accounting table

This is the deliverable. Every symbol the map does not place, with its address,
both size measures, and its disposition. **`source-map.json` and `ledger.json`
are correct as generated and were not regenerated** — the map is right to report
these addresses unmapped, because `_m64WaitForIdle` in the binary and
`__m64WaitForIdle` from our source are genuinely different symbols. What was
wrong in the first Task 3 draft was the conclusion drawn about *why*.

### 8.1 ATI Mach64 2-D engine — 5 functions, all present, all misspelled

| Address | Symbol | Extent (B) | Delta (B) | Definition site in our tree, as spelled |
| --- | --- | ---: | ---: | --- |
| `0x21b8` | `_m64WaitForIdle` | 60 | 76 | `__m64WaitForIdle` `IONDRVFramebuffer.m:1227` |
| `0x2204` | `_m64WaitForFIFO` | 92 | 108 | `__m64WaitForFIFO` `IONDRVFramebuffer.m:1245` |
| `0x2270` | `_m64Init` | 488 | 568 | `__m64Init` `IONDRVFramebuffer.m:1270` |
| `0x24a8` | `_m64DoBlit` | 380 | 412 | `__m64DoBlit` `IONDRVFramebuffer.m:1368` |
| `0x2644` | `_m64DoFill` | 224 | 256 | `__m64DoFill` `IONDRVFramebuffer.m:1341` |
| | **5** | **1,244** | **1,420** | |

1,420 delta bytes is exactly the spec's "ATI Mach64 acceleration 5 / 1,420".
Note that address order and source order disagree: the binary emits `DoBlit`
before `DoFill`, our source defines `DoFill` first.

### 8.2 IXMicro 2-D engine — 3 functions, all present, all misspelled

| Address | Symbol | Extent (B) | Delta (B) | Definition site in our tree, as spelled |
| --- | --- | ---: | ---: | --- |
| `0x2c38` | `_ixDoBlit` | 496 | 528 | `__ixDoBlit` `IONDRVFramebuffer.m:1674` |
| `0x2e48` | `_ixDoFill` | 432 | 464 | `__ixDoFill` `IONDRVFramebuffer.m:1637` |
| `0x3018` | `_ixIdleEngine` | 60 | 76 | `__ixIdleEngine` `IONDRVFramebuffer.m:1628` |
| | **3** | **988** | **1,068** | |

### 8.3 IXMicro 3-D engine — 4 functions, all present, all misspelled

| Address | Symbol | Extent (B) | Delta (B) | Definition site in our tree, as spelled |
| --- | --- | ---: | ---: | --- |
| `0x3598` | `_ix3dDoBlit` | 412 | 444 | `__ix3dDoBlit` `IONDRVFramebuffer.m:1897` |
| `0x3754` | `_ix3dDoFill` | 232 | 264 | `__ix3dDoFill` `IONDRVFramebuffer.m:1879` |
| `0x385c` | `_ix3dIdleEngine` | 60 | 76 | `__ix3dIdleEngine` `IONDRVFramebuffer.m:1870` |
| `0x38a8` | `_ix3dInterruptHandler` | 64 | 96 | `__ix3dInterruptHandler` `IONDRVFramebuffer.m:1959` |
| | **4** | **768** | **880** | |

8.2 + 8.3 = 7 functions and **1,948** delta bytes, exactly the spec's "IXMicro
acceleration 7 / 1,948".

### 8.4 `IOATINDRV` methods — 8, all present under another class

| Address | Symbol | Extent (B) | Delta (B) | Body in our tree |
| --- | --- | ---: | ---: | --- |
| `0x2744` | `-[IOATINDRV initEngine]` | 80 | 112 | `-[IOATIMACH64NDRV initEngine]` |
| `0x27b4` | `-[IOATINDRV setDisplayMode:depth:page:]` | 108 | 140 | `-[IOATIMACH64NDRV setDisplayMode:depth:page:]` |
| `0x2840` | `-[IOATINDRV open]` | 108 | 140 | `-[IOATIMACH64NDRV open]` |
| `0x28cc` | `-[IOATINDRV setIntValues:forParameter:count:]` | 308 | 388 | `-[IOATIMACH64NDRV setIntValues:forParameter:count:]` |
| `0x2a50` | `-[IOATINDRV showCursor:frame:token:]` | 136 | 168 | `-[IOATIMACH64NDRV showCursor:frame:token:]` |
| `0x2af8` | `-[IOATINDRV moveCursor:frame:token:]` | 136 | 168 | `-[IOATIMACH64NDRV moveCursor:frame:token:]` |
| `0x2ba0` | `-[IOATINDRV hideCursor:]` | 104 | 136 | `-[IOATIMACH64NDRV hideCursor:]` |
| `0x2c28` | `-[IOATINDRV tempFlags]` | 16 | 16 | `-[IOATIMACH64NDRV tempFlags]` |
| | **8** | **996** | **1,268** | |

`@implementation IOATIMACH64NDRV` is at `IONDRVFramebuffer.m:1415`, its methods
at 1495, 1511, 1526, 1537 and following. Section 15.

### 8.5 Duplicate definitions — 3

| Address | Symbol | Extent (B) | Delta (B) | Candidates |
| --- | --- | ---: | ---: | --- |
| `0x5e9c` | `_StdIntHandler` | 16 | 16 | `IONDRVFramebuffer.m:602`, `IONDRVLibraries.m:809` |
| `0x5eac` | `_StdIntEnabler` | 12 | 12 | `IONDRVFramebuffer.m:606`, `IONDRVLibraries.m:813` |
| `0x5eb8` | `_StdIntDisabler` | 16 | 16 | `IONDRVFramebuffer.m:610`, `IONDRVLibraries.m:817` |
| | **3** | **44** | **44** | |

### 8.6 The one genuine gap — 1

| Address | Symbol | Extent (B) | Delta (B) | Definition site |
| --- | --- | ---: | ---: | --- |
| `0x5fd8` | `__eLMGetPowerMgrVars` | 104 | 136 | **none, anywhere in `src/`** |
| | **1** | **104** | **136** | |

### 8.7 Build-generated — 2

| Address | Symbol | Extent (B) | Delta (B) |
| --- | --- | ---: | ---: |
| `0x97a0` | `+[IONDRVSupportKernelServerInstance kernelServerInstance]` | 20 | 20 |
| `0x97b4` | `+[IONDRVSupportVersion driverKitVersionForIONDRVSupport]` | 16 | 16 |
| | **2** | **36** | **36** |

### 8.8 The whole of `__text`, accounted for

| group | symbols | delta bytes | % of `__text` |
| --- | ---: | ---: | ---: |
| mapped to a scoped source file | 165 | 33,904 | 87.26% |
| `-[IONDRVFramebuffer doControl:params:]`, mapped by definition site, outside the analysis | 1 | 96 | 0.25% |
| present but over-underscored (8.1–8.3) | 12 | 3,368 | 8.67% |
| present under another class (8.4) | 8 | 1,268 | 3.26% |
| defined twice (8.5) | 3 | 44 | 0.11% |
| build-generated (8.7) | 2 | 36 | 0.09% |
| **genuinely absent (8.6)** | **1** | **136** | **0.35%** |
| **total** | **192** | **38,852** | **100%** |

The delta column sums to 38,852 exactly, and the symbol column to 192. That is
the check: the deltas partition the section, so a table of them that does not
close is wrong.

## 9. The over-underscore defect — twelve renames, the sixth appearance

The twelve functions of 8.1–8.3 are **defined** in `IONDRVFramebuffer.m`, the
file already in scope, each carrying one spurious leading underscore:

```c
static void _m64WaitForIdle(volatile UInt32 *base)      // line 1227
```

The Mach-O ABI prepends exactly one underscore, so these bodies emit
`__m64WaitForIdle` — a symbol this binary has never contained. Apple's spelling
was `m64WaitForIdle`.

### 9.1 The rule proved inside this binary's own mapped set

`static` linkage does not exempt a symbol from the one-underscore rule. Four
statics in `IOPEFInternals.c`, all in the *mapped* bucket of the map this
measurement produced, demonstrate it:

| binary symbol | address | source | source spelling |
| --- | --- | --- | --- |
| `_GetNameLength` | `0x6154` | `IOPEFInternals.c:209` | `static ByteCount GetNameLength(…)` |
| `_FindRelocationInfo` | `0x6188` | `IOPEFInternals.c:230` | `static LoaderRelExpHeader * FindRelocationInfo(…)` |
| `_UnpackFullSection` | `0x7ab0` | `IOPEFInternals.c:1324` | `static OSStatus UnpackFullSection(…)` |
| `_PartialBlockMove` | `0x7e98` | `IOPEFInternals.c:1544` | `static void PartialBlockMove(…)` |

Source `Foo` → binary `_Foo`, exactly one underscore, `static` or not.

### 9.2 The underscore-offset probe

Rather than trusting a list, the probe was re-run independently for this report:
for each of the 26 `unmapped` + `duplicate_candidates` reference names, test
whether the scoped files define that name carrying one or two extra leading
underscores, using `binrecon.source_map.source_sites` (whose keys are already in
binary form, since it applies the Mach-O prepend itself).

```
probe over 26 entries (23 unmapped + 3 duplicate)
underscore-offset hits: 12
```

**Exactly the twelve of 8.1–8.3 and nothing else.** `__eLMGetPowerMgrVars` does
not hit — that would require a source `___eLMGetPowerMgrVars`, which does not
exist — confirming it as the sole genuine gap. The 8 `IOATINDRV` methods and the
3 `_StdInt*` do not hit either, consistent with their being a class split and a
duplicate pair respectively.

### 9.3 This is a rename, not twelve bodies

The twelve bodies exist and are substantial — 60 to 496 bytes of reference code
apiece. Closing them is a **naming** correction: dropping one leading underscore
from twelve `static` declarations and from their call sites (`_m64DoFill` calls
`_m64WaitForFIFO` at `IONDRVFramebuffer.m:1344`, and there are others). A spec
that budgets this as "write 12 missing functions" would be sizing work already
done.

### 9.4 Sixth appearance in this series

The spurious-leading-underscore defect has been found and corrected five times
before here — `e094b623` (Floppy selectors), `7ec48d4d` (Floppy data globals),
`c365f6db` (drvSCSIServer data globals), with `25a99615` and
`0d4399e2`/`3882b2e8` refining the rule's scope — and the first draft of the
Task 3 report asserted its absence in this driver. **This is the sixth
appearance.** Any future measurement in this series should run the
underscore-offset probe before concluding that a symbol has absent source. It is
cheap and it has been load-bearing six times running.

**Nothing was renamed here.** This measurement does not touch
`src/driverkit-3/`. The rename belongs to a later spec, which must not disturb
the `_e*` shims of section 10 — those are correct as written and stripping them
would break 58 working mappings.

## 10. The Registry exception — the rule inverts for the `_e*` shims

Separately from section 9, a family of symbols in this binary carries a **double**
underscore, and there the ABI means the source spelling is legitimately
single-underscored.

`__TEXT,__text` holds **59** symbols beginning `__e`. Fifty-eight map cleanly
against a source name written with one leading underscore; one does not exist in
the tree at all.

```c
OSStatus
_eRegistryEntryIterateCreate( RegEntryIter * cookie)
```

The eight the spec §4 named:

| Binary symbol | Source spelling | Map result |
| --- | --- | --- |
| `__eRegistryEntryIterate` | `_eRegistryEntryIterate` | mapped, `IONDRVLibraries.m:473` |
| `__eRegistryEntryIterateCreate` | `_eRegistryEntryIterateCreate` | mapped, `IONDRVLibraries.m:460` |
| `__eRegistryEntryIterateDispose` | `_eRegistryEntryIterateDispose` | mapped, `IONDRVLibraries.m:467` |
| `__eRegistryCStrEntryToName` | `_eRegistryCStrEntryToName` | mapped, `IONDRVLibraries.m:492` |
| `__eRegistryCStrEntryCreate` | `_eRegistryCStrEntryCreate` | mapped, `IONDRVLibraries.m:507` |
| `__eGetInterruptFunctions` | `_eGetInterruptFunctions` | mapped, `IONDRVLibraries.m:827` |
| `__eInstallInterruptFunctions` | `_eInstallInterruptFunctions` | mapped, `IONDRVLibraries.m:847` |
| `__eLMGetPowerMgrVars` | *(absent from the tree)* | **unmapped — the one gap** |

**Correction to the dispatch that commissioned this report.** It states "57 of
the 58 `__e*` symbols map correctly on that spelling". The measured figures are
**59 `__e*` symbols, 58 mapped, 1 unmapped**. The other 51 are the
`__eExpMgr*`, `__eRegistryProperty*`, `__eAbsolute*` and similar Mac OS shims
in the same file, and they map on the same one-underscore source spelling.

**So this driver contains both underscore cases at once, and they point in
opposite directions.** The twelve of section 9 have one underscore too many in
our source and must lose one. The fifty-nine of this section have exactly the
right number and must keep it. Stripping a leading underscore from every C name
— the reflex applied in five earlier specs — would turn 58 correct mappings into
58 false "missing" reports.

### 10.1 Should the checker learn to distinguish the two cases?

`symbol_name_check.py` reports all eight of the table above as missing, from
every scoped file, including `IONDRVLibraries.m` where seven of them are
defined. **The spec predicted this and attributed it to the underscore rule.
That attribution is wrong** — the checker's underscore handling is correct here.
`missing_definitions` strips exactly one underscore from the binary symbol
(`__eFoo` → looks for a source `_eFoo`), which is precisely right. The false
report has a different cause, in section 11.

**The question, recorded and not answered in code as the spec directs:** the
checker cannot presently tell "the source name legitimately starts with `_`"
from "the source name is over-underscored", because it only ever tries
`symbol[1:]`. Both cases occur in this one driver. A follow-on spec must decide
whether `symbol_name_check.py` should try `symbol[2:]` as a second candidate and
report a hit there as a *rename* rather than a *gap* — which is effectively what
`source_map`'s `source_sites` does, and why the map got all 59 right. That change
would also have caught the defect of section 9 automatically on all six of its
appearances. **No change was made here.**

## 11. `symbol_name_check.py` produces 32 false "missing" reports on this driver

This is the finding that dissolves the spec's decomposition, and it is separate
from both underscore cases.

Run once over the union of the five scoped files — `--source-dir` is
`action="append"`, so a single invocation takes them all — the checker reports:

```
hand-written C symbols: 124
missing definitions   : 45
```

**45 functions. Their next-symbol deltas sum to 16,276 bytes.** That is exactly
the spec §1.1 headline, "16,276 bytes across 45 C functions — 42% of `__text`",
reproduced to the byte. It is where the four-sub-project decomposition came from.

**32 of the 45 are in the map's `mapped` bucket**, with a verified definition
site. Only 13 are genuinely unmapped: the 12 over-underscored of section 9, and
`__eLMGetPowerMgrVars`.

Two independent defects in the checker's scanner produce the 32. `source_sites`,
which the source map uses, has neither, which is why the map and the checker
disagree and why **the map is the authoritative document**.

### 11.1 `_DEFINITION` eats the first character of a column-0 name — 18 cases

```python
_DEFINITION = re.compile(r"^(?:static\s+)?[A-Za-z_][\w \t\*]*?([A-Za-z_]\w*)\s*\(")
```

The leading `[A-Za-z_]` is mandatory: it is meant to consume the first character
of the return type. When the return type sits on the *previous* line — a common
style in this source — the name itself starts at column 0 and the pattern eats
its first character instead:

| source line | captured |
| --- | --- |
| `_eRegistryEntryIterateCreate( RegEntryIter * cookie)` | `eRegistryEntryIterateCreate` |
| `PCodeOpen( LogicalAddress container, …)` | `CodeOpen` |
| `Instantiate( InstanceVars * inst )` | `nstantiate` |
| `NDRVForDevice( IOTreeDevice * ioDevice )` | `DRVForDevice` |

The defect is not underscore-specific — `PEF_OpenContainer` at column 0 would
capture `EF_OpenContainer`. It affects `_NDRVForDevice`, **seven** of the eight
`_e*` functions in the section 10 table (all but `__eLMGetPowerMgrVars`, which
has no definition to misparse), and **ten** of `IOPEFLoader.c`'s thirteen —
1 + 7 + 10 = 18.

### 11.2 The `{` lookahead is only four lines — 14 cases

```python
if "{" in "".join(lines[index:index + 4]):
```

`IOPEFInternals.c` declares its entry points with one parameter per line:

```c
OSStatus    PEF_OpenContainer   ( LogicalAddress            mappedAddress,
                                  LogicalAddress            runningAddress,
                                  …
                                  CFContHandlerProcsPtr *   handlerProcs )
{
```

The opening brace is ten lines below the name, so the four-line window never
sees it and the definition is discarded.

The 14 counted here are the cases where this is the *only* defect, and every one
of them is in `IOPEFInternals.c`. The lookahead also compounds with 11.1 on four
of the `_e*` shims — `_eRegistryEntryIterate`, `_eRegistryCStrEntryToName`,
`_eGetInterruptFunctions`, `_eInstallInterruptFunctions` — which are counted in
11.1. 18 with the regex defect + 14 with only the lookahead defect = **32**, and
the four overlap into the 18.

### 11.3 What that means for the spec

The PEF/PCode cluster — the spec's largest predicted gap at 25 functions and
12,060 bytes, and the entire justification for splitting the reconstruction into
four sub-projects — **is already implemented.** All 39 PEF/PCode functions across
`IOPEFInternals.c` and `IOPEFLoader.c` are mapped, 12,812 extent bytes /
13,900 delta bytes, including every function the spec named by hand:

| spec named it as a gap | address | extent | source |
| --- | --- | ---: | --- |
| `_PEF_OpenContainer` | `0x62a4` | 1,692 | `IOPEFInternals.c:282` |
| `_UnpackPartialSection` | `0x7f20` | 1,092 | `IOPEFInternals.c:1571` |
| `_Instantiate` | `0x8f98` | 860 | `IOPEFLoader.c:317` |
| `_SatisfyImports` | `0x93fc` | 756 | `IOPEFLoader.c:486` |

Zero PEF/PCode functions are unmapped.

### 11.4 The scanner defects are latent elsewhere in the series, not yet realised

A prior review of this series asserted that the scanner defects of 11.1 and
11.2 had already degraded the published gate for `Floppy`, citing
`Geometry.m:171` and "4 missing". That is wrong. `Geometry.m` belongs to
`src/drivers-i386/ide/drvPCFloppy` — the **i386** floppy driver, which no task
in this series has measured or gated. The PPC driver reconstructed and gated
in this series is `src/drivers-ppc/ide/drvPPCSwimFloppy`, and its gate reports
**141 hand-written C symbols, 0 missing** (`report.md`). `report.md`'s
`Floppy` claims are accurate and need no correction.

The defects themselves are real, but **latent, not yet realised**: no driver
measured in this series contains a column-0 name-first definition, so no
published gate result is affected by them. `drvPCFloppy` (i386) does contain
one — `fdGetSectSizeInfo`, `Geometry.m:171` — and would be affected if that
driver is ever gated.

## 12. `-[IONDRVFramebuffer doControl:params:]` at `__text+0` — a known exclusion

`ppc_invariant_check.py`:

```
symbol -[IONDRVFramebuffer doControl:params:] at 0x0 has no function start in the
analysis, but code is present: the bytes there are a function prologue, so the
analysis omits a real function
167 scattered/difference-form relocations (target section verified, field is a
difference, not an address)
27 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
2227 fused relocations, 1 violations
exit 1
```

The first four words at `__TEXT,__text + 0`, read raw from the file at offset
2424:

```
7c0802a6  90010008  9421ff90  38000000
mflr r0   stw r0,8(r1)  stwu r1,-112(r1)  li r0,0
```

A textbook PowerPC non-leaf prologue. The bytes are **real code**.

The finding means only that **IDA's function list has no entry at address 0** —
which is why `analysis-named.json` describes 191 functions where the symbol table
names 192, and why the source map totals 191. The checker itself says so in
words: "code is present". This is a **known exclusion, not a gap and not a
phantom.** The opposite reading was recorded across five earlier specs in this
series and retracted in 22 places; it is not reopened here.

Its source **is** in scope. `source_sites` finds
`-[IONDRVFramebuffer doControl:params:]` at `IONDRVFramebuffer.m:59`, and
`selector_check.py` does not list it as missing — the confirmation the spec §5
asked for, which Floppy could not have because its address-0 function was a plain
C function. It simply has no analysis row to attach to, so it can never enter a
map. **Account for it as a 192nd symbol outside the map, not as an unmapped one
and not as a gap.**

The three relocation invariants are clean: 167 scattered/difference-form
relocations verified, 27 HI16/HA16-LO16 pairs reconstructed and in agreement,
2,227 fused relocations with no violation among them. Address 0 is the single
violation, and `exit 1` is that violation alone.

## 13. `duplicate_candidates` — every entry explained

All three carry the reason `symbol name resolves to multiple definitions`.
`_StdIntHandler`, `_StdIntEnabler` and `_StdIntDisabler` each have two source
definitions: `IONDRVFramebuffer.m:602-612` and `IONDRVLibraries.m:809-819`.

Both copies are byte-identical, non-`static`, external definitions. **Two
external definitions of one symbol in a single link is a duplicate-symbol
error**, and the binary carries exactly one copy of each, so one of the two
copies is a stray in our tree. The binary offers no evidence for which:
`IONDRVLibraries.m` holds all 59 `_e*` shims and its `_eGetInterruptFunctions`
(`:827`) references these three, which is weak circumstantial support for the
`IONDRVLibraries.m` copy being the original — but it is circumstantial, and this
measurement does not decide it. **Neither copy was removed.**

## 14. `boundary_disputed` — empty, and why

Zero entries. Two reasons, both structural:

- IDA is the only analyzer that supports PowerPC, so there is no second opinion
  that could disagree about a function extent.
- `_overlapping_addresses` found no named function whose `[address, address + size)`
  range runs into another's, so no symbol was mistaken for an interior label.

## 15. The class-hierarchy divergence — `selector_check.py`'s 12 extras

### 15.1 Before and after scoping

| Invocation | our definitions | renames | duplicates | missing | extra |
| --- | ---: | ---: | ---: | ---: | ---: |
| `src/driverkit-3/libDriver/ppc` (unscoped) | 241 | 0 | 0 | 10 | **183** |
| `…/IONDRVFramebuffer.m` | 70 | 0 | 0 | 10 | **12** |
| `…/IONDRVLibraries.m` | 0 | 0 | 0 | 68 | 0 |
| `…/IONDRVInterface.m` | 0 | 0 | 0 | 68 | 0 |
| **combined** | **70** | **0** | **0** | **10** | **12** |

`selector_check.py` takes exactly one `SOURCE_DIR` argument, so it was run once
per scoped `.m` file. The two `.c` files are not applicable: `source_methods`
calls `source_files(path, {".m"})`, which raises for a `.c` path by design.

**Extra falls 183 → 12.** The 171 removed were cross-binary contamination from
the other twelve files in the shared directory, which is what the scoping fix
was for. `renames` is 0 and `duplicates` is 0 in every run.

### 15.2 The 12 that remain, and why no scoping can remove them

**(a) A class split — 9 of the 12.** `IONDRVFramebuffer.h` declares
`IOATINDRV : IONDRVFramebuffer` with two subclasses, `IOATIMACH64NDRV : IOATINDRV`
and `IOATIRAGE128NDRV : IOATINDRV`. The shipped binary has neither subclass; it
has a single flat `IOATINDRV` carrying all nine methods. The 8 `IOATIMACH64NDRV`
extras are exactly, name for name, the 8 `IOATINDRV` missing entries of 8.4:

| binary (`missing`) | our tree (`extra`) |
| --- | --- |
| `-[IOATINDRV hideCursor:]` | `-[IOATIMACH64NDRV hideCursor:]` |
| `-[IOATINDRV initEngine]` | `-[IOATIMACH64NDRV initEngine]` |
| `-[IOATINDRV moveCursor:frame:token:]` | `-[IOATIMACH64NDRV moveCursor:frame:token:]` |
| `-[IOATINDRV open]` | `-[IOATIMACH64NDRV open]` |
| `-[IOATINDRV setDisplayMode:depth:page:]` | `-[IOATIMACH64NDRV setDisplayMode:depth:page:]` |
| `-[IOATINDRV setIntValues:forParameter:count:]` | `-[IOATIMACH64NDRV setIntValues:forParameter:count:]` |
| `-[IOATINDRV showCursor:frame:token:]` | `-[IOATIMACH64NDRV showCursor:frame:token:]` |
| `-[IOATINDRV tempFlags]` | `-[IOATIMACH64NDRV tempFlags]` |

The 9th, `-[IOATIRAGE128NDRV moveCursor:frame:token:]`, is new code with no
reference counterpart at all.

The base/Mach64 split is Apple's own, not ours: Darwin 0.3's
`IONDRVFramebuffer.h` already declares `@interface IOATIMACH64NDRV:IOATINDRV`
(empty, `19ffee9a`). `IOATIRAGE128NDRV` is not Apple's — it first appears in
`6f3d886c`, an in-repo commit. And nothing was "factored": Apple's `.m`
implements only `IOATINDRV`, with a single method
(`getStartupMode:depth:`), and has no `@implementation IOATIMACH64NDRV` at
all. The eight `IOATIMACH64NDRV` bodies were never in Apple's source under any
class; `6f3d886c` wrote them (section 16). The one method our tree still keeps
on the base class, `-[IOATINDRV getStartupMode:depth:]`, maps cleanly at
`0x2018`.

**(b) Three methods with no symbol-table counterpart.**
`-[IONDRVFramebuffer getInterruptFunctionsTV:refCon:handler:enabler:disabler:]`,
`-[IONDRVFramebuffer setInterruptFunctionsTV:refCon:handler:enabler:disabler:]`
and `-[IONDRVFramebuffer(ProgramDAC) interruptOccurred]` exist in our
`IONDRVFramebuffer.m` with no symbol-table counterpart in the shipped image.

Both categories are our-source-only definitions inside `IONDRVFramebuffer.m`, a
file unambiguously in scope. **No file-level scoping can change the count.** This
is a divergence to record, not a scoping failure to fix; renaming a class to
close a checker count is exactly what this measurement forbids.

## 16. Provenance — the 20 recovered bodies are unverified reconstruction

`git log -L` attributes **all twelve** bodies of section 9, and the **eight**
`IOATIMACH64NDRV` method bodies of 8.4, to a single commit:

```
6f3d886c  driverkit: Add hardware blit and fill code for Mach64, Rage 128,
          and IMS video cards for PPC
```

That is **prior in-repo reconstruction work, not recovered Apple source.**

Whether these twenty bodies are faithful to the reference binary is
**unverified**. No task in this series has disassembled the reference at these
addresses and compared. A follow-on spec must not treat them as settled: *a body
exists* is not *a body is correct*. Establishing fidelity requires disassembly
comparison against `IONDRVSupport_reloc` at `0x21b8`–`0x38a8` (the twelve, 3,368
delta bytes) and `0x2744`–`0x2c28` (the eight, 1,268 delta bytes). That work
remains outstanding, and it is the largest genuine risk this measurement
uncovered.

## 17. What the follow-on work actually is

The spec proposed four sub-projects behind this measurement — PEF/PCode, IXMicro,
ATI Mach64, Name Registry — sized at 45 functions and 16,276 bytes. **That
decomposition no longer has a subject.** The PEF/PCode cluster, which was 25 of
the 45 functions and 12,060 of the 16,276 bytes and carried the whole argument
for splitting, is already implemented and mapped (section 11.3).

What is genuinely outstanding, in the order a spec should take it:

1. **Twelve renames.** Drop one leading underscore from twelve `static`
   declarations in `IONDRVFramebuffer.m` (lines 1227, 1245, 1270, 1341, 1368,
   1628, 1637, 1674, 1870, 1879, 1897, 1959) and from every call site among
   them. Verified by those twelve addresses moving from `unmapped` to `mapped`
   in a regenerated `source-map.json`.
2. **One class-hierarchy decision.** Either collapse `IOATIMACH64NDRV` back into
   `IOATINDRV` to match the shipped binary, or record the split as a deliberate
   forward divergence and adjust the gate. The eight bodies exist either way;
   `-[IOATIRAGE128NDRV moveCursor:frame:token:]` and the three
   newer-than-the-binary `IONDRVFramebuffer` methods have no reference
   counterpart and must survive whatever is decided.
3. **Three duplicate removals.** Delete one copy each of `_StdIntHandler`,
   `_StdIntEnabler`, `_StdIntDisabler`. As written the tree cannot link.
4. **One function to write.** `_eLMGetPowerMgrVars`, 104 bytes at `0x5fd8`, from
   the disassembly. It is the only absent body in the driver.

Two further pieces of work, not gap-filling but prerequisites for trusting any
gate here:

5. **Verify the twenty bodies from `6f3d886c` against the disassembly**
   (section 16). Until that is done, "mapped" at those addresses means "a name
   matches", not "the code is right".
6. **Decide the `symbol_name_check.py` question** (sections 10.1 and 11). Two
   scanner defects make it report 32 present functions as missing on this
   driver, and it cannot distinguish a legitimate leading underscore from a
   spurious one. Until that is settled it is not usable as a gate on this source.

That is one small rename pass, one design decision, three deletions and one
function — not four sub-projects.

## 18. The ledger

```
$ seed_ledger.py source-map.json IONDRVSupport_reloc ledger.json
191 entries
exit 0
```

Schema `ledger-v1`. `reference_sha256` is
`C12688AE327660F69F16375E45E089673C9E0955FA6FFEDBB31F3B0C23CE85B1`, identical to
the source map's and to the analysis's `input.sha256`. `rebuilt_sha256` is
`null` — nothing has been rebuilt, and nothing can be, since there is no
compiler here. All 191 entries are `status: "unexamined"`.

Every citation was verified programmatically against the map:

```
map addresses: 191   ledger addresses: 191
in map not in ledger: []
in ledger not in map: []
entries carrying a source_path: 165
agree with mapped: 165   mismatched: 0   non-mapped entries: 26
```

**165 entries cite a source location and all 165 agree exactly** with the map's
`source_path` and `source_line`. The other 26 — the 23 `unmapped` plus the 3
`duplicate_candidates` — correctly carry no citation at all rather than a guessed
one. Address sets are identical in both directions.

## 19. Acceptance

Against the spec's eleven items.

| # | Item | Result | Evidence |
| --: | --- | --- | --- |
| 1 | Two profiles created, `test_ppc_profile_inventory` updated, suite green | **pass** | `iondrvsupport-ppc.json` and `iondrvsupport-bundle-ppc.json`, sorted between `iodisplay-ppc.json` and `mace-bundle-ppc.json`; suite 894 passed / 4 skipped |
| 2 | `source_definitions()` and `selector_check.py` accept a file path, with tests; the silent-zero case unreachable | **pass** | `source_files(path, suffixes, recursive=True)` in `tools/binrecon/source_paths.py`, all four walkers converted plus a fifth CLI guard removed in Task 3; nonexistent path raises, wrong-suffix *file* raises, empty *directory* still returns `[]`; 7 new tests. `source_definitions` on a file returns 57 where it returned 0 |
| 3 | Scoped file list re-derived independently and cross-checked against the map's `source_path` values | **pass** | Section 4. Five files, not three; re-derived a second time here from the symbol table, and the map cites exactly those five |
| 4 | Source map built over the scoped files, every `unmapped`, `duplicate_candidates` and `boundary_disputed` entry explained | **pass** | Sections 5, 8, 13, 14. 23 + 3 + 0, each with a disposition |
| 5 | `extra` falls from 183 to the irreducible remainder, every entry enumerated with its disposition (**as amended**) | **pass against the amended text** | Section 15. 183 → 12; 8 `IOATIMACH64NDRV` + 1 `IOATIRAGE128NDRV` + 3 newer-than-binary, each named. **Fails against the original "0 extra"**, which the spec now records as unachievable: those classes live in `IONDRVFramebuffer.m`, so no file-level scoping can change the count |
| 6 | `doControl:params:` recorded as a known exclusion, confirmed present by `selector_check.py` | **pass** | Section 12. Prologue read raw (`7c0802a6 90010008 9421ff90`); definition site `IONDRVFramebuffer.m:59`; absent from `selector_check.py`'s `missing` list |
| 7 | `RECONCILES: yes`, the two build-generated class methods accounted for | **pass** | Section 6. `counted: 191`, bucket 4 = 2 |
| 8 | Ledger seeded against the final map, every citation verified | **pass** | Section 18. 191 entries, 165 citations, 0 mismatches |
| 9 | The four clusters of §1.1 enumerated with each function's address and size | **pass, but the premise is void** | Section 8 enumerates every non-mapped symbol with address, extent and delta. Three of the spec's four clusters reproduce exactly by delta (1,420 / 1,948 / 848) and are shown to be present-but-misnamed rather than absent; the fourth, PEF/PCode, is mapped in full (section 11.3). There is no four-cluster gap left to write specs from — section 17 |
| 10 | The Registry `__e*` exception recorded, with a note on whether the checker must distinguish the two underscore cases | **pass** | Section 10. Exception recorded, count corrected to 59/58/1, and 10.1 records the question without answering it in code — including the finding that the checker's underscore handling is *not* what causes the false report |
| 11 | The binrecon suite stays green | **pass** | `894 passed, 4 skipped` |

Ten of eleven pass as written. Item 5 passes against the amended text and fails
against the original. Item 9's deliverable is complete but establishes that its
own premise was wrong.

## 20. What this does not establish

- **Nothing was compiled.** No PowerPC toolchain, no host C compiler, no `make`.
  Every correspondence here is structural — a name in the symbol table against a
  definition site in the source. That the twelve renamed symbols *would* match
  Apple's follows from the Mach-O one-underscore rule, not from a build.
- **Coverage is not correctness.** 165 mapped addresses means 165 names match.
  Not one function body in this driver has been compared against the reference
  disassembly, and section 16 records twenty bodies whose provenance makes that
  comparison necessary rather than optional.
- **This measurement wrote no bodies and renamed nothing.** `src/driverkit-3/`
  and `src/kernel-7/` are untouched. `source-map.json` and `ledger.json` are as
  generated and were not regenerated for this document.
- **Data symbols were not measured.** `symbol_name_check.py --check-data` is
  outside this scope, so the `__DATA` underscore question that Floppy raised is
  open for this driver too.
- **Ivars were not read from `__OBJC,__instance_vars`.** The spec §2.1 asks for
  that during the reconstruction work; the class inventory in section 2.1 comes
  from `__text` selector names and the symbol table, which is what the mapping
  needed.
