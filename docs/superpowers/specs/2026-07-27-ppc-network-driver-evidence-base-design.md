# Evidence base for the PowerPC network drivers

Measure how closely four in-tree PowerPC network driver sources correspond to
Apple's shipped Rhapsody binaries — `drvPPCGNic`, `drvPPCGem`, `drvPPCMace` and
`drvPPCDec21040` — and extend the evidence base that later per-driver
reconstruction specs build on.

This spec changes no driver source and no build wiring. It measures.

## Motivation

[2026-07-27-ppc-driver-evidence-base-design.md](2026-07-27-ppc-driver-evidence-base-design.md)
measured five PowerPC drivers — `drvPPCCuda`, `drvPPC53c96`, `drvPPCATA`,
`drvPPCBMac` and `drvPPCBurgundy` — and established the methodology this spec
reuses unchanged. Its report is at
`src/drivers-ppc/reconstruction/report.md`.

Eighteen shipped PowerPC drivers remain unmeasured, about 1.07 MB of
`_reloc` against the 446 KB that spec covered. Attempting all eighteen at once
would repeat the mistake the whole approach exists to avoid: `SCSIServer`
asserted a bar it could not meet and ended with 31 open ledger entries. So the
remainder is decomposed by subsystem, and this spec takes the network group.

### Why network first

The four are the most uniform group in the set, which makes them cheap to
measure and unusually informative to compare. Every one is an `IOEthernet`
subclass, and their method counts cluster tightly:

| Driver | ObjC method definitions | Static C functions |
| --- | --- | --- |
| `GNicEnet` | 46 | 1 |
| `GemEnet` | 47 | 2 |
| `MaceEnet` | 46 | 3 |
| `DECchip2104x` family | 47 | 4 |

`drvPPCBMac` — already measured, 64 mapped and 2 unmapped with one real gap —
is a fifth `IOEthernet` subclass. Measuring these four completes the family and
enables a comparison no single-driver measurement can produce (§4.6).

## 1. Scope

### 1.1 Reference artifacts

Eight Mach-O files under
`C:\Users\raynorpat\Downloads\test\Drivers\ppc`, each driver contributing a
bundle stub and a kernel-server `_reloc`. Sizes are recorded here; SHA-256 is
captured by `binrecon validate` in the plan's first task and written into each
driver's `findings.md`, since no value in this spec should be transcribed
rather than measured.

| Artifact | Size |
| --- | --- |
| `drvPPCGNic.config/drvPPCGNic` | 8496 |
| `drvPPCGNic.config/drvPPCGNic_reloc` | 48432 |
| `drvPPCGem.config/drvPPCGem` | 8492 |
| `drvPPCGem.config/drvPPCGem_reloc` | 58072 |
| `drvPPCMace.config/drvPPCMace` | 8496 |
| `drvPPCMace.config/drvPPCMace_reloc` | 60744 |
| `drvPPCDec21040.config/drvPPCDec21040` | 8504 |
| `drvPPCDec21040.config/drvPPCDec21040_reloc` | 51872 |

Artifacts stay outside Git.

### 1.2 Sources under test

Class names were read from each binary's `.objc_class_name_*` symbols. Every
module-owned class corresponds to an in-tree source:

| Reference binary | Module classes | Source directory |
| --- | --- | --- |
| `drvPPCGNic` | `GNicEnet` | `src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj` |
| `drvPPCGem` | `GemEnet` | `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj` |
| `drvPPCMace` | `MaceEnet` | `src/kernel-7/bsd/dev/ppc/drvMaceEnet` |
| `drvPPCDec21040` | `DECchip21040`, `DECchip21041`, `DECchip2104x` | `src/kernel-7/bsd/dev/ppc/drvDECchip21040` |

> **`drvPPCDec21040` has a PowerPC source, despite appearances.**
> `src/drivers-i386/network/drvDECchip21040` also defines `DECchip2104x`, and a
> first search found it before the PowerPC copy. Comparing a PowerPC binary
> against i386 sources would have been meaningless. The PowerPC directory
> `src/kernel-7/bsd/dev/ppc/drvDECchip21040` defines all three of the binary's
> classes, and it is the one under test. The i386 tree is not touched.

### 1.3 Out of scope

- **Repairing divergences.** Findings are recorded, not fixed.
- **Writing absent function bodies.**
- **`DEC21x4Ethernet.config`.** Its class `DEC21x4` has no source anywhere in
  the tree, so it is archaeology rather than measurement, and at 124 KB it is
  larger than any driver here. It needs its own spec.
- **Loadable-bundle packaging.** Two of the four sources build into the kernel
  via `conf/files.ppc`; the shipped artifacts are loadable kernel servers.
  Recorded as a finding, deferred.
- **Kernel build wiring.** `conf/files.ppc` is read, never edited.
- **Any PowerPC compile.** There is no PowerPC toolchain here. **Nothing in
  this spec is compile-verified**, and `parity_check.py` and `import_check.py`
  remain unusable.
- **Tool changes**, except under §3.5.

## 2. Design

### 2.1 Profiles

Eight profiles on the existing convention:

```
tools/binrecon/profiles/{gnic,gem,mace,dec21040}-ppc.json
tools/binrecon/profiles/{gnic,gem,mace,dec21040}-bundle-ppc.json
```

Each takes the shape of the existing PowerPC profiles: `"architecture": "ppc"`,
`"endianness": "big"`, IDA enabled at a 900-second timeout, Ghidra and angr
disabled — both reject a PowerPC profile before starting a subprocess — and
`output_dir` at `../out/<name>-ppc`. Reference path is `${BINRECON_REFERENCE}`;
there is no rebuilt artifact.

`tools/binrecon/tests/test_profile.py::test_ppc_profile_inventory` asserts the
exact list of PowerPC profiles. It currently names 17 and must be updated to
25. That test failing on a new profile is the test working as designed.

### 2.2 Checked-in artifacts

```
src/drivers-ppc/reconstruction/
    report-network.md
    GNic/{source-map.json,findings.md}
    Gem/{source-map.json,findings.md}
    Mace/{source-map.json,findings.md}
    Dec21040/{source-map.json,findings.md}
```

The shared `reconstruction/` home already holds the previous spec's
`report.md` and five driver directories. This spec adds four directories and a
**second report** rather than extending the first: `report.md` is a finished
artifact with its own acceptance run recorded against a specific set of
binaries, and appending to it would blur what was verified when.
`report-network.md` cross-references it for `drvPPCBMac`.

No ledgers are seeded, for the reason the previous spec gives: a ledger's value
is the reviewed status of its entries, and this spec reviews none.

## 3. Method

Five phases, identical to the previous spec's except where noted.

### 3.1 Analyses

`binrecon analyze` once per profile. These are reference-only profiles with no
rebuilt artifact, so **exit 1 is the expected outcome and is not a failure**.
The pass condition is `"complete": true` plus a published
`analysis-reference-ida.json`.

### 3.2 Invariant checks

`ppc_invariant_check.py --binary … --analysis …` against all eight. Symbols
whose address IDA did not recognise as a function start are enumerated as
`boundary_disputed` candidates, not failures.

### 3.3 Source maps

`binrecon source-map --objc-methods --scope-to-objc` per driver.
`--scope-to-objc` is mandatory on PowerPC: IDA's linker glue stubs carry no
name and `source-map-v1` requires every analyzed function to have one.

**Map validation must scope the reference analysis to the addresses the map
covers, across all four map categories** — `mapped`, `unmapped`,
`duplicate_candidates`, `boundary_disputed`. `load_source_map` enforces an
exact partition; omitting any category fails with `unexpected`, and omitting
`duplicate_candidates` specifically is what broke the previous spec's ATA
measurement.

### 3.4 The non-Objective-C remainder

Every function IDA found that the scoped map did not cover — named or not —
goes in exactly one bucket:

1. crt/dyld startup routines
2. `__picsymbol_stub` entries
3. unnamed jump islands
4. build-generated classes (`drv<Name>KernelServerInstance`, `drv<Name>Version`)
5. a function matched to a source site, with file and line
6. a function with no source site — the gap

**Buckets 1 and 2 will be empty for all four**, because `_reloc` files are
statically linked kernel servers rather than `MH_EXECUTE` helpers: no crt/dyld
routines, no `__picsymbol_stub` section. The report states this with the
reason rather than omitting the buckets.

Bucket 5 is populated by hand from bucket 6. `selector_check.py` runs per
driver; a nonzero exit or a reported missing selector is a finding to record.

### 3.5 Tool changes

Permitted only for a defect that **blocks an artifact from publishing** or
**corrupts the measurement**, following the previous spec's §3.6 and the
precedent of commit `12a64a6c`: a targeted change with a test, never a
widening of what an integrity check accepts.

Two known scanner limitations were checked against all four source
directories before this spec was written, and **neither occurs**:

- a method definition written with a semicolon before the body where a comment
  block intervenes (13 sites exist tree-wide; **0 here**)
- a `//` line comment on a signature line, which `read_selector` does not
  strip (**0 here**)

So no tool work is anticipated. If a defect appears anyway, this clause
governs.

## 4. The report

`src/drivers-ppc/reconstruction/report-network.md`, in six parts.

### 4.1 Correspondence

Per driver: total functions, mapped, unmapped, `duplicate_candidates`,
`boundary_disputed`, mapped bytes, unmapped bytes. Every row reconciles against
IDA's total function count.

### 4.2 Class inventory

Binary versus source per driver. `drvPPCDec21040` carries three classes where
the others carry one; the report records how the three divide the binary.

### 4.3 Non-Objective-C remainder

The bucket tables and merged `selector_check.py` output per driver, including
the explicit statement that buckets 1 and 2 are empty and why.

### 4.4 Findings

Each with the reference evidence establishing it, including the packaging gap:
`drvMaceEnet` and `drvDECchip21040` build into the kernel via
`src/kernel-7/conf/files.ppc` under `mk_hasdrivers`, while `drvPPCGNic` and
`drvPPCGem` are already loadable-driver projects under `src/drivers-ppc`. The
shipped artifacts are loadable kernel servers in all four cases. Recorded and
deferred.

### 4.5 Decomposition proposal

The per-driver specs to follow, ranked by **actionable divergence with runtime
consequence** — the criterion the previous spec's report settled on. An
unmapped entry with a documented, evidenced cause is a result, not work, and
serves as the tie-breaker rather than the primary key.

### 4.6 The `IOEthernet` family comparison

The section that justifies measuring these four together. With `drvPPCBMac`
from the previous spec, five `IOEthernet` subclasses are now measured. The
report establishes:

- the selector set every one of the five implements — the de facto
  `IOEthernet` contract as Apple actually shipped it
- selectors implemented by some but not all, and by which
- per-driver selectors, which indicate hardware-specific behaviour
- whether any driver is missing a selector the other four share, which is a
  stronger signal of a real gap than that driver's own unmapped count

This is evidence no single-driver measurement can produce. It is derived from
the five source maps and `selector_check.py` outputs, so it costs almost
nothing once §4.1–§4.3 exist. `drvPPCBMac`'s data is read from
`src/drivers-ppc/reconstruction/BMac/findings.md` and its committed source
map; that driver is not re-measured.

## 5. Acceptance

Done when all of the following hold, with output shown:

1. Eight `analyze` runs report `"complete": true` and publish
   `analysis-reference-ida.json`. Exit 1 throughout is expected.
2. `ppc_invariant_check.py` reports **0 relocation violations** across all
   eight. Symbol/function-start mismatches are enumerated, not required to be
   zero.
3. Four source maps exist and `load_source_map` accepts each against its
   reference analysis **restricted to the addresses that map covers across all
   four map categories**, and the repo root.
4. `duplicate_candidates` is **0, or every entry is enumerated with the
   evidence establishing its cause**; `boundary_disputed` likewise. A nonzero
   count is a finding, not a failure.
5. Every function IDA found in every binary lands in exactly one of: mapped, or
   §3.4's six buckets. Per binary, mapped plus the six buckets sums to IDA's
   **total** function count.
6. The binrecon suite is green, including the updated
   `test_ppc_profile_inventory`.
7. `report-network.md` carries all six parts of §4, and §4.5 names each
   follow-on spec with its measured gap.
8. §4.6's family comparison covers all five `IOEthernet` drivers and states,
   for each of the four measured here, whether it is missing any selector the
   other four share.

These prove structural correspondence to Apple's binaries. **They do not prove
any driver builds or runs**, and this spec does not claim otherwise.

### 5.1 Known risk

The four are uniform and the pre-checks are clean, so the likeliest overrun is
§4.6 rather than any single measurement: a family comparison across five
drivers can expand indefinitely. It is bounded to the four bullets in §4.6.
Anything beyond those is recorded as a follow-on question, not chased.

## 6. Follow-on work

- **The remaining fourteen drivers**, by subsystem: storage (`drvPPCMesh`,
  `drvPPCSym8xx`, `Floppy`), platform (`drvPPCOHare`, `drvPPCPMU`,
  `IOADBDevice`, `IOApplePCIBus`), framework (`IODisplay`, `IONDRVSupport` —
  both `driverkit-3`, extending the existing `libDriver/reconstruction`),
  sound and serial (`PPCAwacs`, `PPCSerialPort`), and the userspace-adjacent
  pair (`BPF`, `PortServer`, both of which already carry i386 reconstruction
  directories).
- **`DEC21x4Ethernet`**, which has no in-tree source at all.
- **`IONDRV.config` cannot be measured by binrecon.** Its seven `*_ndrv` files
  are PEF (`Joy!peff`), Mac OS ROM video drivers, not Mach-O. Reading them
  would need a PEF loader; `src/driverkit-3/libDriver/ppc/IOPEFLoader.c`
  suggests the tree already understands the format.
- **Naming IDA's unnamed PowerPC glue stubs**, which would let source maps
  cover C functions and retire the hand-built bucket tables.
- **The duplicated scanner logic** across `source_map.py` and
  `selector_check.py`, and `read_selector`'s failure to strip `//` comments.
