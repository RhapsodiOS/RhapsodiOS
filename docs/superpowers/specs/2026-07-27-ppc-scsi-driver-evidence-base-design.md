# Evidence base for the PowerPC SCSI drivers

Measure how closely two in-tree PowerPC SCSI driver sources correspond to
Apple's shipped Rhapsody binaries — `drvPPCMesh` and `drvPPCSym8xx` — and
complete the `IOSCSIController` family comparison the earlier specs made
possible.

This spec changes no driver source and no build wiring. It measures.

## Motivation

Two specs precede this one and establish the methodology it reuses unchanged:

- [2026-07-27-ppc-driver-evidence-base-design.md](2026-07-27-ppc-driver-evidence-base-design.md)
  measured five drivers; report at `src/drivers-ppc/reconstruction/report.md`.
- [2026-07-27-ppc-network-driver-evidence-base-design.md](2026-07-27-ppc-network-driver-evidence-base-design.md)
  measured four network drivers and added a five-driver `IOEthernet` family
  comparison; report at `src/drivers-ppc/reconstruction/report-network.md`.

The remaining PowerPC drivers are being taken by subsystem. Storage is next,
and it splits cleanly in two.

### Why this spec takes two drivers, not three

Storage has three shipped drivers. `drvPPCMesh` and `drvPPCSym8xx` have the
same shape as everything measured so far. `Floppy` does not:

| Driver | ObjC methods in binary | Defined C functions in binary |
| --- | --- | --- |
| `drvPPCMesh` | 72 | 15 |
| `drvPPCSym8xx` | 46 | 15 |
| `Floppy` | 62 | **183** |
| `drvPPCMace` (measured, for scale) | 49 | 17 |

Counts are defined symbols read from each `_reloc` with
`binrecon.macho.read_macho`.

`--scope-to-objc` is mandatory on PowerPC (§3.3), so C functions fall outside
the machine-checked map and are resolved by hand. At 15 apiece that is a
handful of lookups; at 183 it is a different job entirely — roughly thirty
times the per-driver hand-resolution of the network batch, producing a bucket
table that the tooling follow-on would immediately obsolete.

**`Floppy` is therefore deferred to its own spec, after the glue-stub naming
work.** `--scope-to-objc` is only required because IDA's *unnamed* linker glue
stubs violate `source-map-v1`'s name requirement; `Floppy`'s 183 C functions
are named. Once the stubs are named, they map automatically. Doing `Floppy`
first would be the most expensive possible ordering.

### What these two complete

Four `IOSCSIController` subclasses will then be measured:

| Class | Driver | Measured by |
| --- | --- | --- |
| `Apple96_SCSI` | `drvPPC53c96` | five-driver spec |
| `AtapiController` | `drvPPCATA` | five-driver spec |
| `AppleMesh_SCSI` | `drvPPCMesh` | this spec |
| `Sym8xxController` | `drvPPCSym8xx` | this spec |

Superclasses confirmed from source: `Apple96_SCSI : IOSCSIController <IOPower>`,
`AtapiController : IOSCSIController`, `AppleMesh_SCSI : IOSCSIController
< IOPower >`, `Sym8xxController : IOSCSIController`.

That enables the same cross-driver comparison the network spec produced for
`IOEthernet` (§4.6), which surfaced a functional defect no single-driver
measurement could have found.

## 1. Scope

### 1.1 Reference artifacts

Four Mach-O files under `C:\Users\raynorpat\Downloads\test\Drivers\ppc`. Sizes
are recorded here; SHA-256 is captured by `binrecon validate` in the plan's
first task, since no value should be transcribed rather than measured.

| Artifact | Size |
| --- | --- |
| `drvPPCMesh.config/drvPPCMesh` | 8496 |
| `drvPPCMesh.config/drvPPCMesh_reloc` | 66712 |
| `drvPPCSym8xx.config/drvPPCSym8xx` | 8500 |
| `drvPPCSym8xx.config/drvPPCSym8xx_reloc` | 59128 |

Artifacts stay outside Git.

### 1.2 Sources under test

| Reference binary | Module classes | Source directory |
| --- | --- | --- |
| `drvPPCMesh` | `AppleMesh_SCSI` and its `Hardware`, `HardwarePrivate`, `MeshInterrupt`, `Mesh` and `Private` categories | `src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI` |
| `drvPPCSym8xx` | `Sym8xxController` and its `Client`, `Execute` and `Init` categories | `src/kernel-7/bsd/dev/ppc/drvSymbios8xx` |

Both are Apple's own sources and both build into the kernel via
`src/kernel-7/conf/files.ppc` under `mk_hasdrivers`, while the shipped
artifacts are loadable kernel servers. That gap is recorded (§4.4) and
deferred.

> **`drvAppleMesh_SCSI` writes its category headers with spaces inside the
> parentheses** — `@implementation AppleMesh_SCSI( Hardware )`. Both scanners
> tolerate this: `source_map.py`'s `_IMPLEMENTATION` and `selector_check.py`'s
> equivalent both use `\(\s*(\w+)\s*\)`. No tool change is needed, but a reader
> comparing category names across drivers should expect the spacing.

### 1.3 Out of scope

- **Repairing divergences.** Findings are recorded, not fixed.
- **`Floppy`**, for the reason in the motivation.
- **The glue-stub naming work** that would let maps cover C functions. It is
  the prerequisite for `Floppy`, not part of this spec.
- **Loadable-bundle packaging.** Recorded as a finding, deferred.
- **Kernel build wiring.** `conf/files.ppc` is read, never edited.
- **Any PowerPC compile.** There is no PowerPC toolchain here. **Nothing in
  this spec is compile-verified**; `parity_check.py` and `import_check.py`
  remain unusable.
- **Tool changes**, except under §3.5.

## 2. Design

### 2.1 Profiles

```
tools/binrecon/profiles/{mesh,sym8xx}-ppc.json
tools/binrecon/profiles/{mesh,sym8xx}-bundle-ppc.json
```

Same shape as the existing PowerPC profiles: `"architecture": "ppc"`,
`"endianness": "big"`, IDA enabled at 900 seconds, Ghidra and angr disabled
— both reject a PowerPC profile before starting a subprocess — `output_dir`
at `../out/<name>-ppc`, reference `${BINRECON_REFERENCE}`, no rebuilt artifact.

`tools/binrecon/tests/test_profile.py::test_ppc_profile_inventory` asserts the
exact PowerPC profile list. It names 25 today and must name 29. **The suite
total will rise by 4**, because
`test_ppc_profiles_are_reference_only_ida_runs` is parametrized over the
profile glob — 826 passed becomes 830. That is expected, not a regression.

### 2.2 Checked-in artifacts

```
src/drivers-ppc/reconstruction/
    report-scsi.md
    Mesh/{source-map.json,findings.md}
    Sym8xx/{source-map.json,findings.md}
```

A third report file, alongside `report.md` and `report-network.md`. Each is a
finished artifact with its own acceptance run against a specific set of
binaries; appending would blur what was verified when. `report-scsi.md`
cross-references the other two for `Apple96_SCSI` and `AtapiController`.

No ledgers are seeded.

## 3. Method

Five phases, identical to the two preceding specs.

### 3.1 Analyses

`binrecon analyze` once per profile. Reference-only, so **exit 1 is the
expected outcome and is not a failure**. The pass condition is
`"complete": true` plus a published `analysis-reference-ida.json`.

### 3.2 Invariant checks

`ppc_invariant_check.py` against all four. Symbols whose address IDA did not
recognise as a function start are enumerated as `boundary_disputed`
candidates, not failures. Every driver measured so far has had exactly one —
a method at address `0x0` with a source site but no analysis function entry.

### 3.3 Source maps

`binrecon source-map --objc-methods --scope-to-objc` per driver.
`--scope-to-objc` is mandatory: IDA's PowerPC glue stubs carry no name and
`source-map-v1` requires every analyzed function to have one.

**Map validation must scope the reference analysis to the addresses the map
covers, across all four map categories** — `mapped`, `unmapped`,
`duplicate_candidates`, `boundary_disputed`. Omitting `duplicate_candidates`
is what broke the first spec's ATA measurement.

### 3.4 The non-Objective-C remainder

Every function IDA found that the scoped map did not cover goes in exactly one
bucket: crt/dyld routines, `__picsymbol_stub` entries, unnamed jump islands,
build-generated classes, a function matched to a source site, or a function
with no source site. **Buckets 1 and 2 will be empty** for both — statically
linked kernel servers, not `MH_EXECUTE` helpers. State it with the reason.

Bucket 5 is populated by hand from bucket 6. Each driver has roughly 15 C
functions, comparable to the network batch.

> **A name match is not a logic match.** The network spec found
> `GemEnetPrivate.m`'s `_mace_crc` had a source site under the right name but a
> different algorithm, producing different multicast hash indices on 5 of 5
> test vectors. Where a bucket-6 entry is small and self-contained, confirm the
> logic, not just the name.

### 3.5 Tool changes

Permitted only for a defect that **blocks publication** or **corrupts the
measurement**, following the first spec's §3.6 and commit `12a64a6c`: a
targeted change with a test, never a widening of what an integrity check
accepts.

Both known scanner limitations were checked against both source directories
before this spec was written and **neither occurs**: zero methods use the
semicolon-before-body idiom, and zero signature lines carry a `//` comment. No
tool work is anticipated.

## 4. The report

`src/drivers-ppc/reconstruction/report-scsi.md`, in six parts.

### 4.1 Correspondence

Per driver: total functions, mapped, unmapped, `duplicate_candidates`,
`boundary_disputed`, mapped and unmapped bytes. Every row reconciles against
IDA's total function count.

### 4.2 Class inventory

Binary versus source. Both drivers put most of their methods in categories —
`AppleMesh_SCSI` has five, `Sym8xxController` three — so the report records how
the categories divide each binary, as the network report did for
`drvPPCDec21040`'s three classes.

### 4.3 Non-Objective-C remainder

Bucket tables and `selector_check.py` output per driver, including the
explicit statement that buckets 1 and 2 are empty and why.

### 4.4 Findings

Each with the reference evidence establishing it, including the packaging gap.

### 4.5 Decomposition proposal

Ranked by **actionable divergence with runtime consequence**, with "a
documented, evidenced cause is a result, not work" as the tie-breaker — the
criterion the two preceding reports settled on.

### 4.6 The `IOSCSIController` family comparison

With `Apple96_SCSI` and `AtapiController` already measured, four
`IOSCSIController` subclasses are available. The report establishes:

- the selector set every one of the four implements — the de facto
  `IOSCSIController` contract as Apple shipped it
- selectors implemented by some but not all, and by which
- per-driver selectors, indicating hardware-specific behaviour
- whether any driver is missing a selector the other three share

`Apple96_SCSI` and `AtapiController` are read from their committed source maps
and `findings.md`; **neither is re-measured**. `AtapiController`'s selectors are
extracted from `drvPPCATA`'s map by filtering to that class, since that binary
carries three.

Derive selector sets from each `_reloc`'s symbol table via `read_macho`, not
from the source maps alone. The network spec established why: a source map
cannot carry an address-`0x0` symbol, so the two derivations differ. Report the
symbol-table derivation and disclose any disagreement.

**Bounded to those four questions.** Anything further is a recorded follow-on,
not chased.

## 5. Acceptance

Done when all of the following hold, with output shown:

1. Four `analyze` runs report `"complete": true` and publish
   `analysis-reference-ida.json`. Exit 1 throughout is expected.
2. `ppc_invariant_check.py` reports **0 relocation violations** across all
   four. Symbol/function-start mismatches are enumerated, not required to be
   zero.
3. Two source maps exist and `load_source_map` accepts each against its
   reference analysis **restricted to the addresses that map covers across all
   four map categories**, and the repo root.
4. `duplicate_candidates` is **0, or every entry enumerated with the evidence
   establishing its cause**; `boundary_disputed` likewise.
5. Every function IDA found lands in exactly one of: mapped, or §3.4's six
   buckets. Per binary, mapped plus the buckets sums to IDA's **total**
   function count.
6. The binrecon suite is green at **830 passed, 4 skipped**, with
   `test_ppc_profile_inventory` covering 29 profiles.
7. `report-scsi.md` carries all six parts of §4, and §4.5 names each follow-on
   spec with its measured gap.
8. §4.6 covers all four `IOSCSIController` drivers and states, for each of the
   two measured here, whether it is missing any selector the other three share.

These prove structural correspondence to Apple's binaries. **They do not prove
any driver builds or runs.**

### 5.1 Known risk

`drvAppleMesh_SCSI` has 71 method definitions across six categories, the most
category-fragmented driver measured so far. Attributing a method to the right
category matters for §4.2, and IDA's export strips category tags — `read_macho`
must be used for that, as the first spec's `IdeController` question established.
The likeliest overrun is §4.6 sprawl; it is bounded to its four questions.

## 6. Follow-on work

- **Naming IDA's unnamed PowerPC glue stubs**, so `--scope-to-objc` becomes
  unnecessary and C functions enter the machine-checked map. This is now the
  highest-value tooling item: it is the prerequisite for `Floppy` and it
  retires the hand-built bucket tables for every remaining driver.
- **`Floppy`**, after that work.
- **The remaining eleven drivers**: platform (`drvPPCOHare`, `drvPPCPMU`,
  `IOADBDevice`, `IOApplePCIBus`), framework (`IODisplay`, `IONDRVSupport` —
  both `driverkit-3`, extending the existing `libDriver/reconstruction`),
  sound and serial (`PPCAwacs`, `PPCSerialPort`), and the userspace-adjacent
  pair (`BPF`, `PortServer`).
- **`DEC21x4Ethernet`**, which has no in-tree source at all.
- **`IONDRV.config` cannot be measured by binrecon** — seven PEF (`Joy!peff`)
  Mac OS ROM video drivers, not Mach-O.
- **The duplicated scanner logic** across `source_map.py` and
  `selector_check.py`, `read_selector`'s failure to strip `//` comments, and
  the residual semicolon-with-intervening-comment case (13 sites tree-wide,
  none in any driver measured so far).
