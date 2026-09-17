# Evidence base for five PowerPC platform drivers

Measure how closely five in-tree PowerPC driver sources correspond to Apple's
shipped Rhapsody binaries — `drvPPCOHare`, `drvPPCPMU`, `PPCAwacs`,
`IOApplePCIBus` and `IODisplay` — and test whether the underscore selector
convention found in `drvPPCBurgundy` is project-wide.

This spec changes no driver source and no build wiring. It measures.

## Motivation

Three specs precede this one and establish the methodology it reuses unchanged:

- [2026-07-27-ppc-driver-evidence-base-design.md](2026-07-27-ppc-driver-evidence-base-design.md) — five drivers, `report.md`.
- [2026-07-27-ppc-network-driver-evidence-base-design.md](2026-07-27-ppc-network-driver-evidence-base-design.md) — four network drivers and a five-driver `IOEthernet` family, `report-network.md`.
- [2026-07-27-ppc-scsi-driver-evidence-base-design.md](2026-07-27-ppc-scsi-driver-evidence-base-design.md) — two SCSI drivers and a four-driver `IOSCSIController` family, `report-scsi.md`.

Eleven drivers are measured. This spec takes five of the remainder. `BPF` and
`PortServer` are excluded at the user's direction.

### Why these five, and not the other three candidates

Eight drivers remained after excluding `BPF` and `PortServer`. Three are
blocked, for reasons measured before this spec was written:

| Driver | ObjC methods in binary | Defined C functions | Disposition |
| --- | --- | --- | --- |
| `drvPPCOHare` | 3 | 3 | **this spec** |
| `IOApplePCIBus` | 26 | 5 | **this spec** |
| `IODisplay` | 25 | 10 | **this spec** |
| `PPCAwacs` | 40 | 17 | **this spec** |
| `drvPPCPMU` | 43 | 7 | **this spec** |
| `PPCSerialPort` | 18 | 63 | deferred — C-heavy |
| `IONDRVSupport` | 67 | 146 | deferred — C-heavy and scanner-blocked |
| `IOADBDevice` | 17 | 19 | **no source in the tree** |

Counts are defined symbols read from each `_reloc` with `read_macho`.

- **`PPCSerialPort` and `IONDRVSupport` are deferred behind the glue-stub
  naming work**, for the reason `Floppy` was: `--scope-to-objc` is mandatory
  (§3.3), so C functions fall outside the machine-checked map and are resolved
  by hand. At 5–17 apiece that is routine; at 63 and 146 it is a different job,
  and the tooling follow-on would obsolete the resulting tables.
- **`IONDRVSupport` is additionally blocked by a known scanner limitation.**
  `src/driverkit-3/libDriver/ppc/IOFramebuffer.m:753` writes
  `- (IOConsoleInfo *)allocateConsoleInfo;` followed by a `//` comment block
  before the body. The semicolon-before-body fix only inspects the next
  non-blank line, so this variant is still dropped. It is the first occurrence
  in any driver considered for measurement, and `IOFramebuffer` is one of
  `IONDRVSupport`'s classes. Three other sites in that directory
  (`IOMacRiscPCI.m:187`, `IONDRVFramebuffer.m:653`, `IOSmartDisplay.m:140`) are
  the handled variant and map correctly.
- **`IOADBDevice` has no source.** Its classes `ADBServer` and `IOADBDevice`
  are absent from the tree; only `IOADBBus` exists. Its companion `adbservd`
  has **0 Objective-C methods and 30 C functions**, so `--scope-to-objc` would
  map nothing at all. It belongs with `DEC21x4Ethernet` on the greenfield pile.

### The hypothesis this spec tests

`drvPPCBurgundy` — a RhapsodiOS reimplementation, not Apple source — was found
to have renamed **all 16** of its `PPCBurgundy(Private)` methods with an
underscore prefix relative to Apple's shipped selectors, so only 21 of 40
reference selectors matched by exact name. That was recorded as a
naming-convention decision with a real runtime consequence.

`PPCAwacs` is the second RhapsodiOS reimplementation in the tree. Its
`PPCSound.m` carries both `Copyright (c) 1999 Apple Computer, Inc.` and
`Copyright (c) 2025 RhapsodiOS Project`, and **17 of its 38 method definitions
are underscore-prefixed**. Both are `IOAudio` subclasses.

So this spec can answer a question no single measurement could: **is the
underscore convention project-wide, or was `drvPPCBurgundy` a one-off?** §4.6
tests it. A refutation is as valuable as a confirmation, and the spec commits
to reporting either.

## 1. Scope

### 1.1 Reference artifacts

Ten Mach-O files under `C:\Users\raynorpat\Downloads\test\Drivers\ppc`. Sizes
are recorded here; SHA-256 is captured by `binrecon validate` in the plan's
first task, since no value should be transcribed rather than measured.

| Artifact | Size |
| --- | --- |
| `drvPPCOHare.config/drvPPCOHare` | 8496 |
| `drvPPCOHare.config/drvPPCOHare_reloc` | 16568 |
| `IOApplePCIBus.config/IOApplePCIBus` | 8500 |
| `IOApplePCIBus.config/IOApplePCIBus_reloc` | 26668 |
| `IODisplay.config/IODisplay` | 8492 |
| `IODisplay.config/IODisplay_reloc` | 32640 |
| `PPCAwacs.config/PPCAwacs` | 8492 |
| `PPCAwacs.config/PPCAwacs_reloc` | 38540 |
| `drvPPCPMU.config/drvPPCPMU` | 8492 |
| `drvPPCPMU.config/drvPPCPMU_reloc` | 41488 |

Artifacts stay outside Git.

### 1.2 Sources under test

| Reference binary | Module classes | Source directory |
| --- | --- | --- |
| `drvPPCOHare` | `AppleOHare : IODirectDevice` | `src/kernel-7/bsd/dev/ppc/drvOHare` |
| `drvPPCPMU` | `ApplePMU : IODirectDevice <ADBservice, RTCservice, NVRAMservice, PowerService>` | `src/kernel-7/bsd/dev/ppc/drvPMU` |
| `PPCAwacs` | `PPCAwacs : IOAudio` | `src/drivers-ppc/sound/drvPPCAwacs/PPCAwacs.drvproj/PPCAwacs.lksproj` |
| `IOApplePCIBus` | `IOPCIBridge`, `IOGracklePCIBridge`, `IOMacRiscPCIBridge`, `IOMacRiscVCIBridge`, `IOPCIDevice`, `IODeviceTreeBus`, `IOTreeDevice` | `src/driverkit-3/libDriver/ppc` |
| `IODisplay` | `IOSmartDisplay`, `IOSmartADBDisplay`, `IOSmartDDCDisplay` | `src/driverkit-3/libDriver/ppc` |

> **`IOApplePCIBus` and `IODisplay` share one source directory**, which also
> serves the deferred `IONDRVSupport`. Each binary maps its own subset; the
> directory is passed whole to `--source-dir` and the map is scoped by what the
> binary actually contains. Expect a large "extra" set in each
> `selector_check.py` run — those are the sibling drivers' methods, not gaps,
> and §4.3 must say so.

`drvPPCOHare` is unusually small: the binary carries **two** real methods,
`+[AppleOHare probe:]` and `-[AppleOHare initFromDeviceDescription:]`, and
`ohare.m` appears to define only the first. If that holds, it is a
one-method driver with a one-method gap, and the smallest complete measurement
in the series.

`drvPMU` and `drvOHare` build into the kernel via `src/kernel-7/conf/files.ppc`
under `mk_hasdrivers`; `PPCAwacs` is a loadable-driver project; the two
`driverkit-3` binaries are framework code. All five shipped artifacts are
loadable kernel servers. That gap is recorded (§4.4) and deferred.

### 1.3 Out of scope

- **Repairing divergences.** Findings are recorded, not fixed.
- **`PPCSerialPort`, `IONDRVSupport`, `IOADBDevice`, `adbservd`, `Floppy`,
  `DEC21x4Ethernet`, `BPF`, `PortServer`** — see the motivation and §6.
- **Fixing the residual comment-block scanner case.** It blocks
  `IONDRVSupport`, not this spec's five, and belongs with the glue-stub work.
- **Loadable-bundle packaging**, **kernel build wiring**, **any PowerPC
  compile.** Nothing here is compile-verified.
- **Tool changes**, except under §3.5.

## 2. Design

### 2.1 Profiles

```
tools/binrecon/profiles/{ohare,pmu,awacs,applepcibus,iodisplay}-ppc.json
tools/binrecon/profiles/{ohare,pmu,awacs,applepcibus,iodisplay}-bundle-ppc.json
```

Same shape as the existing PowerPC profiles. `test_ppc_profile_inventory`
asserts the exact list; it names 29 today and must name 39. **The suite total
rises by 10**, because `test_ppc_profiles_are_reference_only_ida_runs` is
parametrized over the profile glob — 835 passed becomes 845. Expected, not a
regression.

### 2.2 Checked-in artifacts

```
src/drivers-ppc/reconstruction/
    report-platform.md
    OHare/{source-map.json,findings.md}
    PMU/{source-map.json,findings.md}
    Awacs/{source-map.json,findings.md}
    ApplePCIBus/{source-map.json,findings.md}
    IODisplay/{source-map.json,findings.md}
```

A fourth report file. Each is a finished artifact with its own acceptance run;
appending would blur what was verified when.

The two `driverkit-3` drivers are recorded here rather than under
`src/driverkit-3/libDriver/reconstruction/` — which already exists from the
i386 foundation work — so that all PowerPC measurement stays in one place, as
§2.2 of the first spec established. `report-platform.md` notes the
relationship.

## 3. Method

Unchanged from the three preceding specs.

### 3.1 Analyses

`binrecon analyze` per profile. Reference-only, so **exit 1 is expected and is
not a failure**. Pass condition: `"complete": true` plus a published
`analysis-reference-ida.json`.

### 3.2 Invariant checks

`ppc_invariant_check.py` against all ten. Two defects in this checker were
found and fixed during the SCSI spec — an `HA16`/`LO16` mis-pairing and a
missing `__OBJC,__cat_cls_meth` allowance — plus an `ori`-form under-report
introduced by the first of those fixes and caught in final review. **Expect 0
relocation violations.** The single item every driver reports is a symbol at
address `0x0` that is not a function start, a `boundary_disputed` candidate.

### 3.3 Source maps

`binrecon source-map --objc-methods --scope-to-objc` per driver.
`--scope-to-objc` is mandatory: IDA's PowerPC glue stubs carry no name and
`source-map-v1` requires every analyzed function to have one.

**Map validation must scope the reference analysis across all four map
categories** — `mapped`, `unmapped`, `duplicate_candidates`,
`boundary_disputed`.

### 3.4 The non-Objective-C remainder

Six buckets, as before. **Buckets 1 and 2 will be empty** for all five —
statically linked kernel servers, not `MH_EXECUTE` helpers. Bucket 5 is
populated by hand from bucket 6.

> **A name match is not a logic match.** The network spec found
> `GemEnetPrivate.m`'s `_mace_crc` had a source site under the right name but a
> different algorithm, producing different multicast hash indices on 5 of 5
> vectors. Where a bucket-6 entry is small and self-contained, confirm the
> logic.

### 3.5 Tool changes

Permitted only for a defect that **blocks publication** or **corrupts the
measurement**: a targeted change with a test, never a widening of what an
integrity check accepts without stated justification.

Pre-checks run before this spec was written: the two `kernel-7` source
directories and the `PPCAwacs` project carry **zero** semicolon-idiom methods
and **zero** `//`-on-signature lines. `src/driverkit-3/libDriver/ppc` carries
four semicolon sites, of which three are the handled variant; the fourth
(`IOFramebuffer.m:753`) belongs to the deferred `IONDRVSupport` and is not
reached by this spec's two drivers. **No tool work is anticipated.**

## 4. The report

`src/drivers-ppc/reconstruction/report-platform.md`, in six parts.

### 4.1 Correspondence

Per driver: total functions, mapped, unmapped, `duplicate_candidates`,
`boundary_disputed`, mapped and unmapped bytes. Every row reconciles against
IDA's total function count.

### 4.2 Class inventory

Binary versus source. `IOApplePCIBus` carries seven classes and `IODisplay`
three, both drawn from a shared directory — the report records how the classes
divide each binary and how the split was obtained. **IDA's export strips
Objective-C category tags; `read_macho` preserves them.**

### 4.3 Non-Objective-C remainder

Bucket tables and `selector_check.py` output per driver, with the explicit
statement that buckets 1 and 2 are empty and why. For the two `driverkit-3`
drivers, the large "extra" sets are the shared directory's sibling classes and
must be characterised as such, not as gaps.

### 4.4 Findings

Each with its reference evidence, including the packaging gap.

### 4.5 Decomposition proposal

Ranked by **actionable divergence with runtime consequence**, with "a
documented, evidenced cause is a result, not work" as the tie-breaker.

### 4.6 Two pairings

Thinner than the preceding family sections — two pairs, not four or five
drivers — and scoped accordingly.

**`IOAudio`: `PPCAwacs` against `drvPPCBurgundy`.** Both are RhapsodiOS
reimplementations of Apple audio drivers. Burgundy renamed all 16 of its
private selectors with an underscore prefix; Awacs has 17 underscore-prefixed
methods of its own. The report states, from measurement:

- how many of Awacs's reference selectors match by exact name, against
  Burgundy's 21 of 40
- whether Awacs's unmatched selectors correspond to Apple's under an
  underscore-stripping transformation, as Burgundy's did
- therefore whether the convention is project-wide or driver-local

**`IODirectDevice` + ADB/RTC: `ApplePMU` against `AppleCuda`.** Both provide
`ADBservice` and `RTCservice` on `IODirectDevice` — Cuda for desk machines, PMU
for PowerBooks. `AppleCuda` was measured in the first spec with **zero real
gaps**. The report states the selectors both implement, those unique to each,
and whether either lacks something the other has.

`drvPPCBurgundy` and `drvPPCCuda` are read from their committed source maps and
`findings.md`; **neither is re-measured**. Derive selector sets from each
`_reloc`'s symbol table via `read_macho`, not from source maps alone — a source
map cannot carry an address-`0x0` symbol.

**Bounded to the questions above.** Anything further is a recorded follow-on.

## 5. Acceptance

1. Ten `analyze` runs report `"complete": true` and publish
   `analysis-reference-ida.json`. Exit 1 throughout is expected.
2. `ppc_invariant_check.py` reports **0 relocation violations** across all ten.
   Symbol/function-start mismatches are enumerated, not required to be zero.
3. Five source maps exist and `load_source_map` accepts each against its
   reference analysis **restricted to the addresses that map covers across all
   four map categories**, and the repo root.
4. `duplicate_candidates` is **0, or every entry enumerated with the evidence
   establishing its cause**; `boundary_disputed` likewise.
5. Every function IDA found lands in exactly one of: mapped, or §3.4's six
   buckets. Per binary, mapped plus the buckets sums to IDA's **total**
   function count.
6. The binrecon suite is green at **845 passed, 4 skipped**, with
   `test_ppc_profile_inventory` covering 39 profiles. If the figure differs,
   record the discrepancy rather than substituting silently.
7. `report-platform.md` carries all six parts of §4, and §4.5 names each
   follow-on spec with its measured gap.
8. §4.6 answers both pairing questions from measurement, and states plainly
   whether the underscore convention is project-wide or driver-local.

These prove structural correspondence to Apple's binaries. **They do not prove
any driver builds or runs.**

### 5.1 Known risks

- **The shared `driverkit-3` directory** will produce large "extra" selector
  sets for both framework drivers. Mischaracterising those as gaps is the
  likeliest error; §4.3 requires them to be attributed to sibling classes.
- **`drvPPCOHare` may be too small to be interesting** — possibly one mapped
  method and one gap. That is a legitimate result, not a failed measurement.
- **§4.6 sprawl.** Bounded to its stated questions.

## 6. Follow-on work

- **Naming IDA's unnamed PowerPC glue stubs**, and **fixing the residual
  comment-block semicolon case**. Together these unblock `PPCSerialPort`,
  `IONDRVSupport` and `Floppy`, and retire the hand-built bucket tables
  everywhere. This is now the highest-value tooling item by a wide margin.
- **`PPCSerialPort`, `IONDRVSupport`, `Floppy`** — after that work.
- **`IOADBDevice` + `adbservd`, `DEC21x4Ethernet`** — greenfield; no in-tree
  source.
- **`BPF`, `PortServer`** — excluded from this series at the user's direction.
- **`IONDRV.config` cannot be measured by binrecon** — seven PEF (`Joy!peff`)
  Mac OS ROM video drivers, not Mach-O.
- **The duplicated scanner logic** across `source_map.py` and
  `selector_check.py`, and `read_selector`'s failure to strip `//` comments —
  the latter has eight occurrences in `src/kernel-7/bsd/dev/ppc`.
