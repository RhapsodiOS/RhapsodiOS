# PowerPC driver evidence base

Five in-tree PowerPC driver sources measured against Apple's shipped Rhapsody
binaries, per
[docs/superpowers/specs/2026-07-27-ppc-driver-evidence-base-design.md](../../../docs/superpowers/specs/2026-07-27-ppc-driver-evidence-base-design.md).

This report changes no driver source and no build wiring. It records what was
measured. Every number below comes from a command run against the published
analyses and the checked-in source maps; the per-driver `findings.md` beside
this file carries the evidence for each cause attributed here.

**What this does not establish.** No PowerPC toolchain exists in this
environment, so nothing here is compile-verified. These are structural
correspondences between our sources and Apple's binaries, not proof that any
of these drivers builds or runs.

Reference artifacts are the ten Mach-O files under
`C:\Users\raynorpat\Downloads\test\Drivers\ppc`, five bundle stubs and five
kernel-server `_reloc` images. All ten SHA-256 identities carried in the
published analyses match spec §1.1; see [Acceptance](#acceptance) item 1.

---

## 1. Correspondence

Summary table, re-derived from
`tools/binrecon/out/<profile>/published/analysis-reference-ida.json` and each
`source-map.json`:

```
driver      total  mapped  unmap  dup  disp     mapB   unmapB
Cuda          100      38      2    0     0     8116       36
53c96         424      88      3    0     0    39924       76
ATA           420     101     42    4     0    25220     7784
BMac          238      64      2    0     0    17320       36
Burgundy      111      21     18    0     0     1704     3368
```

`total` is IDA's total function count for the `_reloc` binary. `mapB`/`unmapB`
are mapped and unmapped bytes.

### Named / unnamed split

`--scope-to-objc` restricts each map to the binary's Objective-C methods, so
the named/unnamed split is what makes the rest of the binary countable:

```
driver      total  named  unnamed   objc  nonobjc
Cuda          100     40       60     40        0
BMac          238     76      162     66       10
Burgundy      111     49       62     39       10
ATA           420    166      254    147       19
53c96         424    108      316     91       17
```

`objc` is the in-scope set the source map operates on; `nonobjc` is the named C
functions the map deliberately does not claim, which §3 buckets by hand.
`unnamed` is bucket 3 throughout.

### Row reconciliation

Each row reconciles as `mapped + bucket1..6 = total`. The `unmapped` column
above is not a separate term: it distributes across bucket 4 (build-generated
accessors) and bucket 6.

| Driver | mapped | b1 | b2 | b3 | b4 | b5 | b6 | sum | total |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Cuda | 38 | 0 | 0 | 60 | 2 | 0 | 0 | 100 | 100 |
| BMac | 64 | 0 | 0 | 162 | 2 | 0 | 10 | 238 | 238 |
| Burgundy | 21 | 0 | 0 | 62 | 2 | 0 | 26 | 111 | 111 |
| ATA | 101 | 0 | 0 | 254 | 2 | 0 | 63 | 420 | 420 |
| 53c96 | 88 | 0 | 0 | 316 | 2 | 0 | 18 | 424 | 424 |

All five print `RECONCILES: yes`. Bucket 5 is 0 straight out of the bucketing
script by construction — entries move into it by hand, per §3.

### ATA: raw and rename-adjusted

`drvPPCATA` is the one driver whose raw numbers understate it, because the
binary links `IdeDisk` while our tree defines `ATADisk` (§2). The rename is
established, so both counts are reported:

| | raw (measured) | rename-adjusted (derived) |
| --- | --- | --- |
| mapped | 101 | 139 |
| unmapped | 42 | 4 |

**Raw is what the tooling measured**; rename-adjusted is derived by hand from
the 38/38 `IdeDisk`↔`ATADisk` selector correspondence established in
[ATA/findings.md](ATA/findings.md). The remaining 4 are 2 real `IdeController`
gaps (`setTransferRate:`, `calcIdeConfigWord:`) and the 2 build-generated
accessors. No other unmapped entry is affected by the rename.

---

## 2. Class inventory

Module-owned classes, derived from the `-[…]`/`+[…]` symbols in each `_reloc`
via `binrecon.macho.read_macho` (which, unlike IDA's export, preserves category
tags):

| Driver | Binary classes (methods) | Binary categories | Source `@implementation` blocks |
| --- | --- | --- | --- |
| Cuda | `AppleCuda` (39) | — | `AppleCuda` |
| BMac | `BMacEnet` (65) | `MII`, `Private` | `BMacEnet`, `BMacEnet(MII)`, `BMacEnet(Private)` |
| Burgundy | `PPCBurgundy` (38) | `Private` | `PPCBurgundy`, `PPCBurgundy(Private)` |
| ATA | `IdeController` (88), `IdeDisk` (38), `AtapiController` (20) | `ATAPI`, `Commands`, `Dma`, `Initialize`, `Internal` | `IdeController` + 4 categories, `AtapiController(Internal)`, **`ATADisk`, `ATADisk(Internal)`** |
| 53c96 | `Apple96_SCSI` (90) | `BusState`, `Curio`, `CurioPublic`, `Curio_DBDMA`, `Hardware`, `HardwarePrivate`, `InterruptService`, `Private` | `Apple96_SCSI` + the same 8 categories |

Every binary additionally carries `drv<Name>KernelServerInstance` and
`drv<Name>Version`, one method each — the build-generated pair that populates
bucket 4 in all five (§3).

Class and category structure corresponds one-for-one in four of the five. The
one difference is ATA's.

### `IdeDisk` is our `ATADisk` — rename established

The shipped `drvPPCATA_reloc` links `IdeDisk`; our tree defines
`ATADisk : IODisk` in `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADisk.m`. The
verdict is **RENAME ESTABLISHED**, on this evidence
([ATA/findings.md](ATA/findings.md)) — established by selector correspondence
and a size proxy, not by a literal byte-for-byte size match; see the size
clause below and "Not claimed":

- **38/38 selector correspondence.** Every `-[IdeDisk …]`/`+[IdeDisk …]`
  selector `selector_check.py` reports missing when scanning only
  `drvPPCATA` appears as an `-[ATADisk …]`/`+[ATADisk …]` "extra" when
  scanning only `drvATADisk`. 37 of the 38 are byte-identical selector
  strings, including the `(Internal)` category tag where present. The one
  exception, `logRwErr:block:status:readFlag:`, prints as
  `logRwErr://:status:readFlag:` on the `ATADisk` side — a parser artifact
  from a trailing `//` comment on the signature
  (`drvATADisk/ATADiskInternal.m:754`), not a real mismatch. See §5's tooling
  note.
- **Size correspondence, as a proxy.** The spec's size clause cannot be met
  literally: there is no `ATADisk`-linked binary to compare byte-for-byte
  against. Across the 37 name-matching pairs, binary byte-size and source
  line-count correlate strongly and monotonically (Pearson r ≈ 0.81, Spearman
  ρ ≈ 0.85), with no case where a large compiled function pairs with a trivial
  source stub. This is corroboration, not equality; it turns up no
  counter-evidence.
- **The tree still names the old class.** `drvATADisk/ATADiskKernel.m:90`
  cites `IdeDiskInternal.h`; `drvPPCATA/AtapiCnt.m:76`,
  `drvPPCATA/IdeCntCmds.h:100` and `drvPPCATA/IdeCntCmds.m:59` all name
  `IdeDisk` in comments.

---

## 3. Non-Objective-C remainder

`--scope-to-objc` puts every non-Objective-C function outside the map. Left
alone that would read as coverage the map does not have, so every function IDA
found that the map does not cover is placed in exactly one of spec §3.4's six
buckets.

### Buckets 1 and 2 are empty across all five

**Bucket 1 (crt/dyld startup routines): 0 in all five. Bucket 2
(`__picsymbol_stub` entries): 0 in all five.** This is not an omission. All
five `_reloc` images are statically linked kernel servers, not `MH_EXECUTE`
helpers: they carry no `start`/`__start`/`__call_mod_init_funcs`/
`__dyld_init_check`/`dyld_stub_binding_helper`/`__dyld_func_lookup`, and their
analyses carry no `__picsymbol_stub` section for the stub-range check to match
against. The section list for `cuda-ppc`, representative of all five, runs
`__text`, `__cstring`, `__const`, `__data`, `__bss`, `__common` and the
Objective-C metadata sections — no stub section.

The crt/dyld routines do exist, but in the *bundle stubs*: each of the five
bundle analyses contains exactly two functions, `dyld_stub_binding_helper`
(0xf04, 48 bytes) and `__dyld_func_lookup` (0xf34, 32 bytes), and no driver
code at all. No source map or bucket table was built for the stubs.

### Bucket 4 — build-generated classes

Two entries in every driver, identical in shape:

| Driver | Address | Symbol | Size |
| --- | --- | --- | --- |
| Cuda | 0x2428 / 0x243c | `+[drvPPCCudaKernelServerInstance kernelServerInstance]` / `+[drvPPCCudaVersion driverKitVersionFordrvPPCCuda]` | 20 / 16 |
| BMac | 0x5170 / 0x5184 | `+[drvPPCBMacKernelServerInstance …]` / `+[drvPPCBMacVersion …]` | 20 / 16 |
| Burgundy | 0x1f10 / 0x1f24 | `+[drvPPCBurgundyKernelServerInstance …]` / `+[drvPPCBurgundyVersion …]` | 20 / 16 |
| ATA | 0xa39c / 0xa3b0 | `+[drvPPCATAKernelServerInstance …]` / `+[drvPPCATAVersion …]` | 20 / 16 |
| 53c96 | 0xbf94 / 0xbfa8 | `+[drvPPC53c96KernelServerInstance …]` / `+[drvPPC53c96Version …]` | 20 / 16 |

These are DriverKit build-tooling output, not hand-written driver code. They
are the whole of Cuda's "unmapped" column.

### Buckets 3, 5 and 6 per driver

| Driver | b3 unnamed islands | b6 from script | → moved to b5 by hand | b6 residue |
| --- | --- | --- | --- | --- |
| Cuda | 60 | 0 | 0 | **0** |
| BMac | 162 | 10 | 9 | **1** (`__udivdi3`) |
| Burgundy | 62 | 26 | 26 | **0** |
| ATA | 254 | 63 | 60 | **3** (`setTransferRate:`, `calcIdeConfigWord:`, `__udivdi3`) |
| 53c96 | 316 | 18 | 15 | **3** (`maxTransfer`, `__divdi3`, `__udivdi3`) |

ATA's 60 moves are 18 C helpers, the 38 `IdeDisk` selectors and the 4 duplicate
candidates. Its two real `IdeController` gaps stay in bucket 6, where they
belong: `-[IdeController(Initialize) calcIdeConfigWord:]` has no source site
anywhere under `src/`, and the only `setTransferRate` definition in the tree is
the two-argument `-[IdeController setTransferRate:UseDMA:]` (`IdeCnt.m:493`,
declared `IdeCnt.h:230`), not the one-argument selector the binary carries at
0x6bc0.

Bucket-5 moves are recorded with file and line in each `findings.md`:
[Cuda](Cuda/findings.md) (none needed — `drvCuda/cuda.m` defines no C
functions at all), [BMac](BMac/findings.md) (9 C helpers in `BMacEnetHW.m`
and `BMacEnetPrivate.m`), [Burgundy](Burgundy/findings.md) (10 C helpers in
`BurgundySound.m` plus the 16 renamed methods, §4.3),
[ATA](ATA/findings.md) (18 C helpers across `IdeCntInit.m`,
`AtapiCntInternal.m` and the `drvATADisk` BSD devsw entry points, plus the 38
`IdeDisk` selectors and the 4 duplicate candidates),
[53c96](53c96/findings.md) (15 C helpers in `Apple96Hardware.m`,
`Apple96SCSIPrivate.m`, `Apple96Curio.m` and `Timestamp.c`).

`__udivdi3` (1616 bytes) and `__divdi3` (1736 bytes) are libgcc's 64-bit
division runtime helpers, emitted by the compiler with no driver-source
counterpart. `-[Apple96_SCSI maxTransfer]` is the one entry that genuinely
resists classification; see §4 finding 8.

### Merged `selector_check.py` output

Per driver, re-run for this report:

| Driver | ref selectors | our defs | renames | duplicates | missing | extra | exit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Cuda | 41 | 41 | 0 | 0 | 2 | 2 | 0 |
| BMac | 67 | 65 | 0 | 0 | 2 | 0 | 0 |
| Burgundy | 40 | 38 | 16 | 0 | 3 | 1 | 1 |
| ATA (`drvPPCATA`) | 148 | 124 | 0 | 1 | 43 | 17 | 1 |
| ATA (`drvATADisk`) | 148 | 40 | 0 | 0 | 148 | 38 | 0 |
| 53c96 | 92 | 126 | 0 | 0 | 3 | 37 | 0 |

`selector_check.py` takes one source directory, so ATA needs two runs against
the same binary. **Merged**, per [ATA/findings.md](ATA/findings.md):

- The `drvATADisk` run's 148 "missing" are all `IdeController`/
  `AtapiController` selectors defined in the *other* directory. Not gaps.
- The `drvATADisk` run's 38 "extra" `ATADisk` selectors are, one for one, the
  38 `IdeDisk` selectors the `drvPPCATA` run calls missing. That is the rename
  evidence in §2.
- 143 of the binary's 148 selectors therefore match by exact name across the
  two directories. Of the 5 remaining: 2 build-generated, 2 real gaps
  (`setTransferRate:`, `calcIdeConfigWord:`), and
  `-[IdeController(Dma) isDmaSupported:]`, which the source map *does* map
  (address 14820, `IdeCnt.m:480`) — it shows as missing only because
  `selector_check.py` compares category tags while `source_map.py` strips them.
- The single `duplicates` entry, `-[IdeController(Commands)
  _ideExecuteCmd:ToDrive:]` (`IdeCntCmds.m:714`), is a legitimate
  public-wrapper/private-implementation split, not redundant code.

Exact-name match rate per driver, from the table above (`ref − missing −
renames`):

| Driver | matched | of | rate |
| --- | --- | --- | --- |
| Cuda | 39 | 41 | 95.1% |
| BMac | 65 | 67 | 97.0% |
| ATA (merged) | 143 | 148 | 96.6% |
| 53c96 | 89 | 92 | 96.7% |
| Burgundy | **21** | 40 | **52.5%** |

Cuda's 95.1% is the *lowest* of the four Apple-sourced drivers and yet Cuda has
zero real gaps among the functions IDA reported: both misses are the
build-generated pair. (**Counting the address-0 correction below, Cuda has one
real gap, not zero** -- `+[AppleCuda probe:]`.) Match rate alone therefore does
not rank the work; §5 ranks by gaps that survive explanation.

### Symbol / function-start mismatches

`ppc_invariant_check.py` reports one per artifact, ten in ten. None is a
relocation-decode defect (see [Acceptance](#acceptance) item 2), and none
overlaps any function in any bucket table or source map, so none affects the
correspondence numbers -- but, per the correction below, that is because IDA
never had these functions to map, not because there is nothing there.

| Artifact | Symbol at 0x0 |
| --- | --- |
| `cuda-ppc` | `+[AppleCuda probe:]` |
| `bmac-ppc` | `+[BMacEnet probe:]` |
| `burgundy-ppc` | `+[PPCBurgundy probe:]` |
| `ata-ppc` | `-[IdeController(ATAPI) atapiWaitForNotBusy]` |
| `53c96-ppc` | `+[Apple96_SCSI probe:]` |
| all five bundles | `__mh_bundle_header` |

They are recorded as `boundary_disputed` candidates for the per-driver specs,
the same disposition `+[SCSIServer deviceStyle]` received. `__mh_bundle_header`
is the standard synthetic bundle-header symbol and is not a function at all --
in the bundle stubs `__text` starts at `0xf04`, so that symbol sits at the Mach
header, well before any code.

> **CORRECTION.** This section originally read: *"Address 0x0 is the Mach-O
> header/load-command region, not a code address in a relocatable object: these
> are symbol-table entries with placeholder addresses."* **That is withdrawn.** In
> a relocatable object `__TEXT,__text` begins at address 0, so address 0 is the
> *first instruction*. Reading the five `_reloc` binaries directly, `__text+0`
> holds `7c0802a6` (`mflr r0`) in every one of them, and each of the five symbols
> in the table above is the single defined `__TEXT,__text` symbol at that address.
> Every one names real code that IDA's *analysis* omits.
>
> The misreading came from `ppc_invariant_check.py`'s message, "symbol X at 0x0
> is not a function start", which says nothing about the bytes, compounded by
> `read_macho` reporting address `0` for *undefined* symbols (`_IOLog`,
> `_objc_msgSend`, ...) as well. The checker now distinguishes the two cases.
> Full account: [IOADBDevice/findings.md](IOADBDevice/findings.md), "The
> misreading".
>
> **Consequence for this report's counts: each of the five `_reloc` binaries has
> exactly one more real function than every table here reports** -- an *unmapped
> real function*, never written and never compared against source. Nothing was
> re-measured and no source map was regenerated for this correction; the mapped
> and unmapped counts are correct as stated, because IDA never had these
> functions to map. Only the gap totals move, by exactly one per driver. Each is
> flagged where it occurs below.

---

## 4. Findings

### 4.1 Cuda has one real gap: `+[AppleCuda probe:]`

Both unmapped entries are the build-generated accessors
(`+[drvPPCCudaKernelServerInstance kernelServerInstance]`,
`+[drvPPCCudaVersion driverKitVersionFordrvPPCCuda]`). Buckets 5 and 6 are both
0: `drvCuda/cuda.m` defines no C functions whatsoever — every function in the
file is an Objective-C method. Evidence: [Cuda/findings.md](Cuda/findings.md).

**This section was headed "Cuda has zero real gaps".** Per §3's correction,
`+[AppleCuda probe:]` is real code at `__text+0` that IDA's analysis omits, so it
appears in none of the buckets or lists above. `cuda.m:176` defines a `probe:`
of the same name, but nothing here has compared it against the bytes Apple
shipped. Cuda has **one** real, unwritten-against function, not zero.

`-[AppleCuda StartCudaTransmission:]` is not a gap. It is defined at
`cuda.m:1399` with a NeXT-era semicolon between signature and body, which the
scanner used to drop; see §5.

### 4.2 BMac has two real gaps: `__udivdi3` and `+[BMacEnet probe:]`

Nine of BMac's ten bucket-6 entries have a confirmed source site and move to
bucket 5. The tenth, `__udivdi3` (0x5194, 1616 bytes), matches nothing under
`src/kernel-7/bsd/dev/ppc/drvBMacEnet`. It is libgcc's 64-bit unsigned-division
runtime helper — compiler-generated, not driver source. An expected gap, not a
missing implementation. No caller could be identified: the reference analysis
carries no call-graph edges for this binary. Evidence:
[BMac/findings.md](BMac/findings.md).

The second gap is `+[BMacEnet probe:]` at `__text+0`, per §3's correction: real
code IDA's analysis omits, so it is in no bucket. `BMacEnet.m:45` defines a
`probe:` of the same name, unverified against Apple's bytes. This section
previously said BMac had one real gap.

### 4.3 Burgundy: a systematic private-selector rename

All 16 `PPCBurgundy(Private)` methods in our reimplementation carry an
underscore prefix the shipped selector does not: `-_resetBurgundy` against
`-resetBurgundy`, `-_startIO:` against `-startIO:`, and so on for all sixteen,
each with its source line in `BurgundySoundPrivate.m`. Objective-C dispatches
on the exact selector string, so a message send using Apple's selector name
would not resolve against this class as written.

Only **21 of the 40** reference selectors match by exact name — the lowest of
the five by a wide margin. The other 19: 16 renamed, 2 build-generated, and
`+[PPCBurgundy probe:]`, which is absent from source under any name and which,
per §3's correction, **does** have a real body in the binary at `__text+0` that
IDA's analysis omits. (This paragraph originally called it one of the "0x0
placeholder symbols" with no body and no observable runtime consequence; both
claims are withdrawn.) It is a real, unwritten function. The reimplementation
additionally adds one selector the reference
lacks, `-[PPCBurgundy updateSampleRate:]` (`BurgundySound.m:646`).

**Burgundy is the only one of the five whose source is a RhapsodiOS
reimplementation** rather than Apple's own; the other four are Apple sources
already sitting in `src/kernel-7/bsd/dev/ppc/`. That is why its gap differs in
*kind*, not merely in size. Evidence:
[Burgundy/findings.md](Burgundy/findings.md).

### 4.4 ATA: the `IdeDisk` rename is established

38/38 selector correspondence, 37 of 38 byte-identical. Detailed in §2. The
resulting counts are 101 mapped / 42 unmapped **measured**, 139 / 4 **derived**
after applying the rename. Evidence: [ATA/findings.md](ATA/findings.md).

Two of the surviving 4 are real absent bodies — compiled methods at real code
addresses with no source site. With 53c96's `maxTransfer` (§4.8) these were
recorded as the only three such cases across all five drivers; **per §3's
correction there are five**, the two added being `+[Apple96_SCSI probe:]` and
`+[PPCBurgundy probe:]` at their binaries' `__text+0`, each absent from source
under any name. The two here:

- `-[IdeController setTransferRate:]` (0x6bc0, 36 bytes) — our tree defines
  only the two-argument `-[IdeController setTransferRate:UseDMA:]`
  (`IdeCnt.m:493`, declared `IdeCnt.h:230`). The one-argument selector the
  binary carries has no source site.
- `-[IdeController(Initialize) calcIdeConfigWord:]` (0x54a8, 616 bytes) — no
  source site anywhere under `src/`, on any class. Not a category-tag artifact:
  `source_map.py` strips category tags before matching, confirmed against
  `source-map.json`, whose recorded `reference_names` for this selector carry
  no category.

The other 2 are the build-generated accessors.

### 4.5 ATA: a version divergence between our tree and Apple's shipped source

`getIdeDriveInfo:` and `getIdeIdentifyInfo:` are each defined twice for
`IdeController`: in `@implementation IdeController` (`IdeCnt.m:475` and `:469`)
and again in `@implementation IdeController(Initialize)` (`IdeCntInit.m:443`
and `:1101`). The bodies are near-textually identical, so size and instruction
count cannot distinguish them.

The Mach-O symbol table settles it. Read via `binrecon.macho.read_macho`:

```
20176 0x4ed0  -[IdeController(Initialize) getIdeDriveInfo:]
23280 0x5af0  -[IdeController(Initialize) getIdeIdentifyInfo:]
```

Both compiled selectors carry the `(Initialize)` tag, and GCC emits a category
name only when the method was compiled inside a category implementation block.
Category-overrides-primary-class is a *runtime load-time* behavior — it
replaces entries in a class's method list when the category loads. It cannot
suppress *symbol emission* at compile time: if Apple's `IdeCnt.m` had
contained these two bodies, the compiler would have emitted untagged
`-[IdeController …]` symbols for them regardless of whether a category
happened to load afterward.

The control proves this. `isMultiSectorAllowed:` (`IdeCnt.m:459`) and
`getMultiSectorValue:` (`IdeCnt.m:464`) sit in the same unguarded primary
`@implementation IdeController` block, immediately above the two disputed
bodies at `:469` and `:475` — the whole file is a single `@implementation`
running lines 56–926, no intervening `@end`. Both neighbours compile to
untagged symbols (`-[IdeController isMultiSectorAllowed:]` and
`-[IdeController getMultiSectorValue:]`). If `IdeCnt.m:469` and `:475` had
also been compiled, they would show the same untagged form. They don't —
only the `(Initialize)`-tagged symbols exist.

**Apple's Rhapsody-vintage `IdeCnt.m` did not contain these two bodies at
all; our tree does.** This is not dead code surviving in Apple's own driver —
it is a divergence between our tree's copy of `IdeCnt.m` and the source Apple
actually shipped, which contained only the `IdeCntInit.m:443` and `:1101`
category bodies. Evidence: [ATA/findings.md](ATA/findings.md).

This changes what the ATA follow-on spec must decide: not "delete dead code"
but "reconcile a divergence between our tree and Apple's shipped source" —
i.e. whether to remove the `IdeCnt.m` copies to match Apple's shipped tree,
or keep both bodies as an intentional local variant. The two entries remain
legitimate `duplicate_candidates` with an evidenced cause; only the stated
cause changes (§5 item 4 is unaffected).

The same two addresses read from IDA's export come back as
`-[IdeController getIdeDriveInfo:]` and `-[IdeController getIdeIdentifyInfo:]`,
with the category tag gone. See §5.

### 4.6 ATA: two selectors sit on the wrong class

`matchDevicePath:` and `getDevicePath:maxLength:useAlias:` exist in the binary
only as `-[IdeDisk …]` (0x8cc8 and 0x8bac). Our tree defines both **twice**:
on `IdeController` (`IdeCnt.m:85` and `IdeCnt.m:64`) and again on `ATADisk`
(`ATADisk.m:154` and `ATADisk.m:137`). Since `IdeDisk` is `ATADisk` renamed
(§2), the `ATADisk` copies are the ones Apple shipped; the `IdeController`
copies have no counterpart on that class in the reference. A class-placement
divergence, not a missing implementation. Evidence:
[ATA/findings.md](ATA/findings.md).

The same merge also finds 11 `IdeController` methods our tree defines that
Apple's binary does not contain on *any* class — `getControllerType`,
`numberOfDrives`, `configReadByte:value:`, `configWriteByte:value:`,
`setTransferRate:UseDMA:`, `atapiDmaAllowed:`, `setupDMA:client:length:fRead:`,
`setupDMAList:client:length:fRead:`, `calcIdeConfig:`,
`calcIdeTimingsCmd646X:`, `calcIdeTimingsDBDMA:`.

### 4.7 53c96: 37 "extra" selectors are all conditional compilation

Every one of the 37 source-tree methods with no binary counterpart is excluded
from this build by the preprocessor: 32 in `Apple96_SCSI(Curio)` and 4 in
`Apple96_SCSI(Curio_DBDMA)` sit inside `#if USE_CURIO_METHODS` blocks
(`Apple96Curio.m:180-459`, `Apple96CurioDBDMA.m:67-103`), and
`-[Apple96_SCSI(Private) killCurrentRequest]` sits inside `#if 0`
(`Apple96SCSIPrivate.m:528-550`).

The control that makes this conclusive: **unconditional methods in the same two
categories** — `curioInterruptPending`, `dbdmaTerminate` — *are* compiled in
and *do* appear in the binary's selector table. The exclusion tracks the
preprocessor guard, not the category. None of the 37 is a reconstruction gap.
Evidence: [53c96/findings.md](53c96/findings.md).

### 4.8 53c96: one open question, `-[Apple96_SCSI maxTransfer]`

Compiled into the binary at 0x260, 40 bytes, a real code address — but absent
from `src/` entirely. What was tried, per
[53c96/findings.md](53c96/findings.md): `grep -rn maxTransfer` across every
`.m`, `.h` and `.c` in the directory (every hit is a `scsiReq->maxTransfer`
struct-field access, never a method signature); a check of `Apple96SCSI.h`
alongside the neighbouring statistics accessors, which are all present; a check
for the NeXT-era semicolon-before-body pattern that recovered two other methods
in this same directory. No candidate line of any form exists.

`maxTransfer` is a real `IOSCSIController` virtual accessor that sibling
drivers in this tree do override, each with a short body of comparable size
(`drvPPCATA/AtapiCnt.m:451`, `drvAdaptecU2SCSI/AdaptecU2SCSI.m`), so a small
override in `Apple96_SCSI` is entirely plausible. **Recorded as an unresolved
gap with no cause assigned**: the override that produced this 40-byte method is
missing from this source tree. Per spec §5.1, an explicitly recorded
unbucketable function satisfies acceptance item 5; an unexamined one would not.

### 4.9 The packaging gap (spec §4.4)

Four of the five sources build **into the kernel**:
`src/kernel-7/conf/files.ppc:83-133` lists them as `optional mk_hasdrivers` —
`drvCuda/cuda.m` at line 83, the `drvApple96_SCSI` files from line 96, the
`drvPPCATA` files through line 133, plus `drvBMacEnet` and `drvATADisk`; 36 of
the 51 lines in that range carry `mk_hasdrivers`. Burgundy is the exception: it
lives in `src/drivers-ppc/sound/drvPPCBurgundy/` as a driver project.

The shipped artifacts are **loadable kernel servers**. Each `.config` bundle
carries its own `Default.table`, a `DriverInfo` (Cuda's does; Burgundy's
carries `English.lproj` instead) and a `_reloc` kernel-server image alongside
the bundle stub.

This is a real divergence in how the code is packaged and loaded, and this spec
does not close it. **Recorded and deferred** to the per-driver specs, per spec
§1.2. Nothing in §1–§3 depends on it: the measurement compares compiled
function bodies, which are the same either way.

### 4.10 Buckets 1 and 2 are empty across all five

Stated in full in §3 rather than omitted. Both are 0 in all five binaries
because these are statically linked kernel servers: no crt/dyld routines, no
`__picsymbol_stub` section. The crt/dyld routines live in the bundle stubs
instead, two per stub.

---

## 5. Decomposition proposal

Ranked by **measured gap, not binary size**. Cuda at 43 KB with one gap needs
far less work than Burgundy at 38 KB with a systematic rename.

> **CORRECTION.** Every per-driver count in this section is one function short,
> for the reason given in §3: each `_reloc` carries an unmapped real function at
> `__text+0` that IDA's analysis never listed. The additions are noted per entry
> below. The *ordering* does not change -- one unwritten method moves no driver
> past another -- but no entry here is a zero-gap result any more.

The ranking key is **actionable divergence with runtime consequence** — a
documented, evidenced cause does not by itself mean "no work": if the
divergence changes what actually runs (a renamed selector breaks
Objective-C's dynamic dispatch), it is real work no matter how well it is
explained. That is why Burgundy ranks #1 despite 0 residual bucket-6 entries
and every one of its 18 unmapped entries being documented and evidenced —
its 16 renames are exactly this kind of divergence. Once runtime consequence
is accounted for, the secondary tie-breaker is that an unmapped entry with a
documented, evidenced cause but no runtime consequence (a scanner limitation,
a libgcc helper) is a result, not work. Exact-name match rate is reported
alongside but does not drive the order: Cuda has the lowest rate of the four
Apple-sourced drivers (95.1%) and the least work of all five (one method).

### 1. `drvPPCBurgundy` — largest gap, and different in kind

- **Measured:** 21 mapped / 18 unmapped / 0 dup / 0 disputed; 1704 mapped
  bytes against 3368 unmapped. The only driver of the five whose unmapped
  bytes exceed its mapped bytes.
- **Exact-name match: 21 of 40 (52.5%)**, less than half that of any other.
- **Bucket 6 after hand resolution: 0.** All 26 script-reported entries
  resolve — 10 C helpers by exact name, 16 by rename.
- **Drift or different version?** Neither. This is a **reimplementation**, the
  only one of the five. The gap is a naming-convention decision (underscore
  prefix on every private selector), not divergence from a shared ancestor.
- **Bucket 6 plus the address-0 correction: 1** — `+[PPCBurgundy probe:]`.
- **The follow-on spec's job:** decide whether to adopt Apple's selector names
  or keep the underscore convention, and account for
  `-[PPCBurgundy updateSampleRate:]` (extra) and `+[PPCBurgundy probe:]`
  (absent from source, and — per §3's correction, which replaces this line's
  original "no real body" — carrying a real body at `__text+0` that must be
  written). Sixteen renames is mechanical work with a real
  runtime consequence, which makes it well suited to a spec of its own.

### 2. `drvPPCATA` + `drvATADisk` — widest finding set

- **Measured:** 101 mapped / 42 unmapped / 4 dup / 0 disputed. Rename-adjusted
  (derived): 139 / 4. 420 functions, the second largest.
- **Exact-name match: 143 of 148 (96.6%)** merged across both directories.
- **Bucket 6 after hand resolution: 3** — `setTransferRate:` and
  `calcIdeConfigWord:` (two real absent bodies) plus `__udivdi3` (libgcc).
  **Plus 1 from §3's correction: 4** — `-[IdeController(ATAPI)
  atapiWaitForNotBusy]` at `__text+0`, source at `AtapiCntCmds.m:47` but never
  compared against it.
- **Drift or different version?** Drift, plus a rename. The class rename
  (`IdeDisk`→`ATADisk`) is a Darwin-release rename, not a version difference;
  the 11 surplus `IdeController` methods look like our tree carrying a later or
  divergent controller feature set.
- **The follow-on spec's job:** two absent bodies (`setTransferRate:`,
  `calcIdeConfigWord:`); the class-placement fix for `matchDevicePath:` and
  `getDevicePath:maxLength:useAlias:`; a decision on the two dead
  primary-class bodies at `IdeCnt.m:469`/`:475`; and a decision on the 11
  surplus methods. Highest count of distinct, actionable findings of the five.

### 3. `drvPPC53c96` — one open question on the largest binary

- **Measured:** 88 mapped / 3 unmapped / 0 dup / 0 disputed. 424 functions,
  151 KB — the largest binary and the largest function count.
- **Exact-name match: 89 of 92 (96.7%)**.
- **Bucket 6 after hand resolution: 3** — `__divdi3`, `__udivdi3` (both
  libgcc), and `-[Apple96_SCSI maxTransfer]`. **Plus 1 from §3's correction: 4**
  — `+[Apple96_SCSI probe:]` at `__text+0`, absent from source under any name.
- **Drift or different version?** Drift, small. The 37 "extra" selectors are
  fully explained by `#if USE_CURIO_METHODS` and `#if 0`; they are not
  divergence.
- **The follow-on spec's job:** essentially one item — write
  `-[Apple96_SCSI maxTransfer]`. Sibling drivers give a template. Large binary,
  small gap; this is the cheapest of the top three despite being the biggest.

### 4. `drvPPCBMac` — one compiler-generated gap and one unmapped method

- **Measured:** 64 mapped / 2 unmapped / 0 dup / 0 disputed.
- **Exact-name match: 65 of 67 (97.0%)**, the highest of the five.
- **Bucket 6 after hand resolution: 1** (`__udivdi3`). **Plus 1 from §3's
  correction: 2** — `+[BMacEnet probe:]` at `__text+0`, source at
  `BMacEnet.m:45` but never compared against it. The heading previously read
  "one compiler-generated gap".
- **Drift or different version?** Neither observable. Zero divergence in the
  driver's own code.
- **The follow-on spec's job:** close to nothing on correspondence grounds
  beyond verifying `probe:`. Worth a spec only for packaging (§4.9) or for a
  compile attempt once a PowerPC toolchain exists.

### 5. `drvPPCCuda` — one unmapped method

- **Measured:** 38 mapped / 2 unmapped / 0 dup / 0 disputed, both unmapped
  build-generated.
- **Bucket 5 and bucket 6 both 0.** **Plus 1 from §3's correction: 1** —
  `+[AppleCuda probe:]` at `__text+0`, source at `cuda.m:176` but never
  compared against it. This entry previously read "no gap".
- **Drift or different version?** Neither. This source and this binary agree
  everywhere the measurement can see -- which, per §3, does not include
  `__text+0`.
- **The follow-on spec's job:** verify `probe:` against Apple's bytes; nothing
  else on correspondence grounds. Cuda remains the control that shows the
  method finds almost nothing when there is almost nothing to find.

### Tooling follow-on — name IDA's PowerPC glue stubs

Listed as its own candidate, per spec §6, and arguably the highest-leverage
item on this list.

`--scope-to-objc` is mandatory today because IDA's PowerPC linker glue stubs
carry no name and `source-map-v1` requires every analyzed function to have one.
The cost is visible in §1's `unnamed` column: **854 unnamed jump islands across
the five binaries** (60 + 162 + 62 + 254 + 316), 66% of all 1293 functions,
none of them machine-checked. It is also why §3's bucket tables had to be built
by hand at all.

These stubs resolve through the Mach-O external relocation table, which
`binrecon.macho.read_macho` already parses. Naming them would let `source-map`
run unscoped, put C functions into the machine-checked map, and retire the
hand-built bucket tables entirely. **This report's five bucket tables are the
natural test fixtures**: each has a known-correct answer for every address.

### Other tooling findings worth carrying forward

- **IDA's export strips Objective-C category tags; `read_macho` preserves
  them.** This is what settled §4.5 — `-[IdeController(Initialize)
  getIdeDriveInfo:]` from `read_macho` against a bare
  `-[IdeController getIdeDriveInfo:]` from the IDA export at the same address.
  Category questions must be asked of `read_macho`, never of the export. Same
  lesson-shape as the SCSITape spec's note that jump islands resolve through
  the Mach-O relocation table, which the IDA export also does not carry
  (`docs/superpowers/specs/2026-07-26-scsitape-ppc-reconstruction-design.md:146-148`).
  **This will matter for every future PowerPC spec.**
- **The scanner logic is duplicated across `source_map.py` and
  `selector_check.py`.** Both independently dropped method definitions written
  with a NeXT-era semicolon before the body
  (`- (void)StartCudaTransmission:(CudaRequest *)plugInMessage;` then `{`).
  One defect needed two fixes — `32a54ee0` in `source_map.py`, `d3bc365d` in
  `selector_check.py`, later refined by `16d2bd14` and `f040d6b2`. The
  duplication is the maintenance finding: `selector_check.source_methods` and
  `source_map.source_sites` carry parallel `found_semicolon`/`found_brace`
  scanners. `read_selector` is already shared between them (`81cdd736`); the
  line scanner is not.
- **`read_selector` strips `/* */` but not `//`.** `_COMMENT` in
  `source_map.py:41` is `re.compile(r"/\*.*?\*/")`. A trailing `//` comment on
  a wrapped signature is folded into the selector: fed the stitched
  declaration from `src/kernel-7/bsd/dev/ppc/IOADBBus.m:381-383`,
  `read_selector` returns `setState://::`. Does not affect these five drivers,
  but it did garble one ATA selector name in `selector_check.py` output
  (`logRwErr://:status:readFlag:`, §2), and it will bite any driver whose
  sources put a trailing `//` on a signature line.
- **`source_map.py` does not evaluate preprocessor conditionals**, so it
  records both branches of an `#ifdef`/`#else`. This produced two of ATA's four
  duplicate candidates (`allocAtapiBuf`, `freeAtapiBuf:` in
  `AtapiCntInternal.m`, whose `#else` branch is dead because `AtapiCnt.h:45`
  defines the macro unconditionally). Teaching it otherwise means emulating the
  preprocessor; not worth it for two entries, but worth knowing before reading
  any future duplicate list.
- **The brace-lookahead inspects only the immediately following non-blank
  line**, so a NeXT-idiom `- sig;` definition with an intervening comment
  block between the `;` and the `{` is still dropped as a bare declaration.
  13 such sites exist tree-wide, including files future PowerPC specs will
  measure — `src/kernel-7/bsd/dev/ppc/PPCKeyboard.m:616,671,706`,
  `src/kernel-7/bsd/dev/ppc/kmDevice.m:835`,
  `src/driverkit-3/libDriver/ppc/IOFramebuffer.m:753`. Zero occur in the five
  drivers measured here, so this report's measurements are uncorrupted by it.

---

## Acceptance

Spec §5, items 1–7. Items 3 and 4 use the amended wording. Every item below
was observed; nothing is claimed that was not run.

### Item 1 — ten analyses complete and published — **PASS**

`complete: true` in every `run-summary.json`, and
`published/analysis-reference-ida.json` present for all ten. Each analysis's
recorded input identity matches spec §1.1 exactly:

```
profile                complete  published sha256
cuda-ppc                   True       True 8CA26E3452246DE99BBD1731586B154B0B339DF3F4C2E65A50C000CC33EE1D1F  size=43328
cuda-bundle-ppc            True       True B82C4317C9DE095AC20C96FB69D902AE7C90DEAA6DB2443F50A7C3AAA5B1C07A  size=8496
53c96-ppc                  True       True D4E01B128C43F18EB1357FC62874A8B89471C77F2BE4C0D955BE18054700B251  size=151244
53c96-bundle-ppc           True       True 4DC866362B9394DD093FF967C2CA5BF25AC2813E64ECABC5BBDDF44719F69C1D  size=8496
ata-ppc                    True       True 734464DC6604C7430761D95E3FA2D51C3C5A9E38956FD847B15390CD3448F597  size=134952
ata-bundle-ppc             True       True 348D054DF4EA489937D1980128E0EC0F451FE0983BE21AB8D7C5D44858D19DD7  size=8492
bmac-ppc                   True       True F940BFBF0B67652409BF430F2A380D432B4BA59EAEE377A5FF218A0AE49DE616  size=77828
bmac-bundle-ppc            True       True 193D2E4FA1BF8DD70A48AB78F6335CC416864FE6504546C68774B21603C468C9  size=8496
burgundy-ppc               True       True D49E3479C9F0D2E7417A10ABAA3DC7D49562C1D4D2E1DCE77CAE467B96EB97CE  size=38652
burgundy-bundle-ppc        True       True D16D9B2355C96D6CEEBEA6346454BE438D5B5DB589F53BD8EDB457182304A1CE  size=8504
```

Exit 1 throughout was the expected outcome for reference-only profiles, per
spec §3.1, and is not a failure.

### Item 2 — 0 relocation violations across all ten — **PASS**

`ppc_invariant_check.py --binary … --analysis …` re-run against all ten. Every
run's `violations` count is 1, and in every case that 1 is the
symbol/function-start mismatch from `check_functions`, **not** a
relocation-decode violation from `check_document`. Actual relocation violations:
**0 in all ten**.

```
=== cuda-ppc ===       53 scattered/difference-form,  2 HI16/HA16-LO16 pairs,  949 fused
=== 53c96-ppc ===      85 scattered/difference-form,  4 HI16/HA16-LO16 pairs, 3751 fused
=== ata-ppc ===        26 scattered/difference-form,  5 HI16/HA16-LO16 pairs, 3418 fused
=== bmac-ppc ===       10 scattered/difference-form,  5 HI16/HA16-LO16 pairs, 1795 fused
=== burgundy-ppc ===    4 scattered/difference-form,  2 HI16/HA16-LO16 pairs,  623 fused
=== all five bundles === 0 scattered, 0 pairs, 0 fused
```

53c96's 85 scattered/difference-form relocations — the largest count of the
five, on the largest binary — all verified clean, which is the case spec §3.6
flagged as the likeliest to need a tool fix. It did not.

The ten mismatched symbols are enumerated in §3, not required to be zero.

### Item 3 — five maps load against a scoped reference analysis — **PASS**

Each map loaded via `load_source_map` against its reference analysis restricted
to the addresses that map covers (`mapped ∪ unmapped ∪ duplicate_candidates ∪
boundary_disputed`), with the repo root:

```
Cuda OK (100 functions -> 40 scoped)
53c96 OK (424 functions -> 91 scoped)
ATA OK (420 functions -> 147 scoped)
BMac OK (238 functions -> 66 scoped)
Burgundy OK (111 functions -> 39 scoped)
```

Scoping is required, not a weakening: `--scope-to-objc` maps do not claim the
unnamed jump islands and `load_source_map` enforces an *exact* partition, so
the unscoped analysis fails with `SemanticValidationError: source map partition
mismatch`. Over everything each map does claim, the check verifies the full
partition, names, sizes, source-line bounds and the analysis's SHA-256 identity.
Item 5 independently accounts for every function scoped out — 60 + 333 + 273 +
172 + 72 — so the pair together covers all 1293 functions.

Note ATA's 147: scoping must include `duplicate_candidates`, or the load fails
with `unexpected=[5204, 5496, 20176, 23280]` — exactly its four duplicates.

### Item 4 — duplicates and disputes enumerated — **PASS**

`duplicate_candidates` is **0 for Cuda, BMac, Burgundy and 53c96**.
`boundary_disputed` is **0 for all five**.

`drvPPCATA` carries **4**, each enumerated with its evidence in
[ATA/findings.md](ATA/findings.md) and summarised here:

| Address | Selector | Cause |
| --- | --- | --- |
| 5204 | `-[AtapiController allocAtapiBuf]` | Scanner limitation — `AtapiCntInternal.m:124` (`#ifdef`) and `:161` (`#else`); `AtapiCnt.h:45` defines the macro unconditionally, so only `:124` compiles |
| 5496 | `-[AtapiController freeAtapiBuf:]` | Same file, same cause: `:151` compiled, `:172` dead |
| 20176 | `-[IdeController getIdeDriveInfo:]` | Version divergence — `IdeCnt.m:475` (primary, our tree only) and `IdeCntInit.m:443` (`(Initialize)` category); binary carries the category tag, so Apple's shipped `IdeCnt.m` never contained the primary-class body (§4.5) |
| 23280 | `-[IdeController getIdeIdentifyInfo:]` | Same: `IdeCnt.m:469` (primary, our tree only) and `IdeCntInit.m:1101` (category); Apple's shipped source lacked this body too |

Per spec §5 item 4, a duplicate that is measured, explained and evidenced is a
result. All four are.

### Item 5 — every function in exactly one bucket, buckets sum to total — **PASS**

All five bucket tables re-derived for this report; all five print
`RECONCILES: yes`. Full table in §1; totals are 100, 238, 111, 420 and 424
against IDA's totals of 100, 238, 111, 420 and 424.

Seven bucket-6 entries carry an explicitly recorded disposition rather than a
source site: `__udivdi3` in BMac and ATA, `__divdi3` and `__udivdi3` in 53c96
(all libgcc, expected); `-[IdeController setTransferRate:]` and
`-[IdeController(Initialize) calcIdeConfigWord:]` in ATA (two real absent
bodies, §4.4); and `-[Apple96_SCSI maxTransfer]` (open question, §4.8). Per
spec §5.1 an explicitly recorded unbucketable function satisfies this item;
none is unexamined.

### Item 6 — binrecon suite green — **PASS**

```
$ PYTHONPATH=tools/binrecon python -m pytest tools/binrecon/tests -q
816 passed, 4 skipped in 53.11s
```

### Item 7 — report carries all five parts, §5 names each spec with its gap — **PASS**

Spec item 7 names these as §4.1–§4.5; this report promotes them to top-level
§1–§5 (so its own §4 is free for driver-specific findings). §1 Correspondence
maps to spec §4.1, §2 Class inventory to §4.2, §3 Non-Objective-C remainder
to §4.3, §4 Findings to §4.4, §5 Decomposition proposal to §4.5.

§1 Correspondence, §2 Class inventory, §3 Non-Objective-C remainder, §4
Findings, §5 Decomposition proposal. §5 names five per-driver follow-on specs
plus the tooling follow-on, each with its measured mapped/unmapped counts, its
bucket-6 residue, and a drift-versus-different-version assessment.

### Not claimed

- **No PowerPC compile.** `parity_check.py` and `import_check.py` need a
  rebuilt binary and remain unusable. Nothing here is compile-verified, and no
  claim is made that any of these five drivers builds or runs.
- **The `IdeDisk`/`ATADisk` size clause is met by proxy, not literally.** No
  `ATADisk`-linked binary exists to compare byte-for-byte; §2 states what was
  measured instead.
- **The packaging gap is recorded, not closed** (§4.9).
- **`-[Apple96_SCSI maxTransfer]` has no assigned cause** (§4.8).

---

## Addendum — `Floppy` (`drvPPCSwimFloppy`), reconstructed separately

Added after this report was written. `Floppy` is outside the five drivers
measured above; it was deferred to its own spec
([2026-07-28-floppy-reconstruction-design.md](../../../docs/superpowers/specs/2026-07-28-floppy-reconstruction-design.md))
and is recorded here so the series has one place that points at it.

Full evidence: [Floppy/findings.md](Floppy/findings.md). Artifacts:
`Floppy/source-map.json`, `Floppy/ledger.json`.

### It was previously recorded as having no in-tree source. That was wrong.

An earlier ad-hoc survey concluded this driver had **no in-tree source**. The
survey ran `find src -iname "*Floppy*" | head -1`, which returned
`src/driverkit-3/Examples/UnixDisk/FloppyDisk.m` — a 175-line DriverKit example
— and stopped there. The real tree,
`src/drivers-ppc/ide/drvPPCSwimFloppy/Floppy.drvproj/Floppy.lksproj`, holds
**11,475 lines across its eight source files** — **10,754** of them in the four
`.m` files — and was never seen. It is the largest driver source in this series.
(Both this report and the Floppy spec originally attributed all 11,475 to the
four `.m` files alone.)

Two things went wrong, and both are structural rather than incidental. `head -1`
discarded the rest of the match list before anything read it. And a name search
was accepted as a measurement: nothing cross-checked the result against the
binary's symbol table, which would have shown 203 `__TEXT,__text` symbols with
no plausible relationship to a 175-line example. This was the fifth ad-hoc
survey error in the series, and it is why the Floppy spec gates on
`symbol_name_check.py` rather than on a search. `Floppy` appears in the earlier
reports only as "not measured" or "deferred", so the false conclusion never
propagated into a published count — it merely postponed the work.

### Headline numbers

`Floppy_reloc`, SHA-256
`7CFD5E18A7CF4C5A8196BF7CC93113C6BE6AC90E770A03EDC58001C8D848BA8B`; `__text`
`0x0`–`0xc05c`, 49,244 bytes — about 2.5× `PPCSerialPort`, the largest binary
reconstructed in the series.

| | |
| --- | --- |
| defined `__TEXT,__text` symbols | 203 |
| build-generated class methods | 2 |
| hand-written Objective-C methods | 60 |
| hand-written C functions | 141 |
| IDA named functions (map universe) | 202 |

Source map, after the remap:

```
driver      total  mapped  unmap  dup  disp
Floppy        202     200      2    0     0
```

Buckets: `RECONCILES: yes`, counted 202 — bucket 4 holds the two
build-generated class methods (`+[FloppyKernelServerInstance
kernelServerInstance]`, `+[FloppyVersion driverKitVersionForFloppy]`) and
buckets 1, 2, 3, 5 and 6 are all 0. Ledger: 202 entries, 200 with a verified
source citation, 2 uncitable by construction.

The map covers **200 of the 201 hand-written functions**. The 201st is
`_fdrToIo` at `__text+0`: the bytes there are real code (`9421ffe0`,
`stwu r1,-32(r1)`) but IDA's function list has no entry at address 0, so the
symbol cannot enter the map. A **known exclusion, not a gap and not a phantom**.
Unlike every other driver in this series the address-0 function here is a plain
C function rather than a `+probe:` method, so `selector_check.py` cannot confirm
it; `symbol_name_check.py` reporting 0 missing is what does.

### What was corrected

| defect | scale | outcome |
| --- | --- | --- |
| C function names carried a spurious leading underscore | 136 of 141 | renamed; `symbol_name_check.py` 141 missing → 0 |
| Objective-C **selectors** carried a spurious leading underscore | 53 | renamed; `selector_check.py` 52 renames → 0 |
| C functions absent from the source | 5 | written from the disassembly, every branch accounted for |
| C functions defined twice (`static` beside `extern`) | 3 | `static` copies removed |

The selector defect was the more serious of the two naming faults: a leading
underscore on a C identifier is a symbol decoration, but `[self _timerEvent]`
and `[self timerEvent]` are different messages at runtime. It was found only by
the map, after the C rename had already been reviewed and accepted.

### What this does not establish

`selector_check.py` and the source map match **by name**. The 60 Objective-C
bodies came out of a decompiler and none has been compared against the
reference; only the five C functions written in Task 5 are derived from the
disassembly. Coverage is not correctness.

As with the five drivers above, **nothing was compiled** — there is no PowerPC
toolchain and no host C compiler here, and no `make` was run. That the renamed
symbols would now match Apple's follows from the Mach-O naming rule, not from a
build. Twelve open uncertainties and pre-existing C defects are recorded in
[Floppy/findings.md](Floppy/findings.md) §12.9, several of which must be settled
before the driver can build.

Two of them limit what the naming result above means, and are worth stating
here. The one-underscore Mach-O rule is **not** function-specific — none of the
binary's 306 symbols carries a double underscore, and `_FloppyState`,
`_FloppyIdMap`, `_busyflag` and five more are one-underscore `__DATA` symbols —
so the driver's **data** symbols still carry the same spurious underscore the
141 functions were corrected for, and `_IOExitThread` is imported under the
wrong spelling. `symbol_name_check.py` gates defined `__TEXT,__text` symbols
only, so its clean result cannot speak to either. Both are pre-existing and were
scheduled rather than fixed on this branch.

---

## Addendum — `IONDRVSupport`, measured separately

Added after this report was written. `IONDRVSupport` is outside the five drivers
measured above and outside the `Floppy` addendum; it was deferred to its own spec
([2026-07-28-iondrvsupport-measurement-design.md](../../../docs/superpowers/specs/2026-07-28-iondrvsupport-measurement-design.md))
and is recorded here so the series has one place that points at it.

Full evidence: [IONDRVSupport/findings.md](IONDRVSupport/findings.md).
Artifacts: `IONDRVSupport/source-map.json`, `IONDRVSupport/ledger.json`.

### Its source is not a driver project, and an earlier survey said it had none

`IONDRVSupport` is compiled from **`src/driverkit-3/libDriver/ppc/`**, the same
`driverkit-3` framework directory that builds `IOApplePCIBus` and `IODisplay`
(§3 and §4.5 above). There is no `IONDRVSupport.drvproj`. Its measurement
artifacts live here rather than under `src/driverkit-3/libDriver/reconstruction/`
so that all PowerPC measurement stays in one place.

**An earlier ad-hoc survey recorded this driver as having no in-tree source at
all** — the spec's §3.2 names it as one of six wrong answers that method
produced in this series. The claim never reached a published count: this driver
appears in the earlier reports only as "deferred", so the false conclusion
postponed the work rather than corrupting a number. It is recorded here because
the actual source is 5 files and 196 definitions, and because it is the same
class of error as the `find | head -1` mistake documented in the `Floppy`
addendum.

**This is the first driver in the series whose source shares a directory with
other binaries' sources.** That is what made a file-granularity scoping fix
necessary: `selector_check.py`, `symbol_name_check.py` and `binrecon source-map`
all returned **zero** for a file path instead of erroring, so a scoped gate would
have read green while measuring nothing. `source_files(path, suffixes,
recursive=True)` in `tools/binrecon/source_paths.py` now backs all four walkers,
plus a fifth `is_dir()` guard in `cli.py` that the first conversion missed.

### Headline numbers

`IONDRVSupport_reloc`, SHA-256
`C12688AE327660F69F16375E45E089673C9E0955FA6FFEDBB31F3B0C23CE85B1`; `__text`
`0x0`–`0x97c4`, 38,852 bytes.

| | |
| --- | --- |
| defined `__TEXT,__text` symbols | 192 |
| Objective-C selectors | 68 |
| C functions | 124 |
| IDA named functions (map universe) | 191 |
| scoped source files | 5 of the directory's 17 |

Scoped in: `IONDRVFramebuffer.m` (8 C + 58 selectors), `IONDRVLibraries.m` (61
C), `IONDRVInterface.m` (6 C), `IOPEFInternals.c` (26 C), `IOPEFLoader.c` (13 C).
The other twelve files contribute **zero** matching definitions between them.

Source map:

```
driver           total  mapped  unmap  dup  disp
IONDRVSupport      191     165     23    3     0
```

Buckets: `RECONCILES: yes`, counted 191 — bucket 4 holds the two build-generated
class methods and buckets 1, 2, 3 and 5 are all 0. Ledger: 191 entries, 165 with
a verified source citation, 26 uncitable by construction.

The map covers 165 of the 190 hand-written functions. The 191st symbol is
`-[IONDRVFramebuffer doControl:params:]` at `__text+0`: the bytes there are real
code (`7c0802a6`, `mflr r0`) but IDA's function list has no entry at address 0,
so the symbol cannot enter the map. A **known exclusion, not a gap and not a
phantom**. Unlike `Floppy`, this one *is* an Objective-C method, so
`selector_check.py` confirms it — it is absent from that checker's `missing` list.

### The spec's 45-function, 16,276-byte gap is one function

Spec §1.1 sized this driver's gap at "16,276 bytes across 45 C functions — 42% of
`__text`" in four clusters, and decomposed the reconstruction into four
sub-projects on that basis. The figure reproduces exactly from
`symbol_name_check.py`. It does not survive the map.

| the 45 | n | what they are |
| --- | ---: | --- |
| mapped, with a verified definition site | 32 | `symbol_name_check.py` false positives — two scanner defects, `IONDRVSupport/findings.md` §11 |
| defined but over-underscored | 12 | a **rename**, not bodies to write — §9 |
| **genuinely absent** | **1** | `_eLMGetPowerMgrVars`, 104 bytes at `0x5fd8` |

The PEF/PCode cluster — 25 functions and 12,060 bytes, the largest predicted gap
and the whole argument for splitting the work — **is already implemented**: all
39 PEF/PCode functions in `IOPEFInternals.c` and `IOPEFLoader.c` map, including
`_PEF_OpenContainer`, `_UnpackPartialSection`, `_Instantiate` and
`_SatisfyImports`. Zero are unmapped. **123 of the 124 C symbols have a
definition site.**

The outstanding work is therefore twelve renames, one class-hierarchy decision
(`IOATIMACH64NDRV`/`IOATIRAGE128NDRV` against the binary's flat `IOATINDRV`),
three duplicate-symbol removals (`_StdInt{Handler,Enabler,Disabler}`) and one
function to write — not four sub-projects.

### Both underscore cases occur in this one driver

This is the **sixth** appearance of the spurious-leading-underscore defect in the
series (after `e094b623`, `7ec48d4d`, `c365f6db` and the two scope refinements).
Twelve `static` functions in `IONDRVFramebuffer.m` carry one underscore too many
and emit symbols the binary never contained.

**And the rule inverts for a larger family in the same binary.** 59 symbols
begin `__e`; there the ABI's single prepended underscore means Apple's source
legitimately wrote `_eRegistryEntryIterate`, and 58 of the 59 map on that
spelling. Stripping a leading underscore from every C name — the reflex applied
in five earlier specs — would turn 58 correct mappings into 58 false "missing"
reports. A follow-on spec must keep the two straight.

### What this does not establish

**Nothing was compiled** — no PowerPC toolchain, no host C compiler, no `make`.
This measurement wrote no bodies and renamed nothing; `src/driverkit-3/` is
untouched.

The twelve over-underscored bodies and the eight `IOATIMACH64NDRV` bodies trace
by `git log -L` to commit `6f3d886c`, which is **prior in-repo reconstruction,
not recovered Apple source**. Their fidelity to the reference is unverified — no
disassembly comparison has been made at `0x21b8`–`0x38a8` or `0x2744`–`0x2c28` —
so "a body exists" must not be read as "a body is correct". That is the largest
open risk this measurement uncovered, and it is recorded in
[IONDRVSupport/findings.md](IONDRVSupport/findings.md) §16.
