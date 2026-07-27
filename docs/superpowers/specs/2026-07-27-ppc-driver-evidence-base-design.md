# Evidence base for five PowerPC drivers

Measure how closely five in-tree PowerPC driver sources correspond to Apple's
shipped Rhapsody binaries — `drvPPCCuda`, `drvPPC53c96`, `drvPPCATA`,
`drvPPCBMac` and `drvPPCBurgundy` — and publish the evidence base that later
per-driver reconstruction specs will build on.

This spec changes no driver source and no build wiring. It measures.

## Motivation

The PowerPC binrecon work so far runs one spec per driver family:
[2026-07-26-binrecon-ppc-support-design.md](2026-07-26-binrecon-ppc-support-design.md)
taught binrecon to read big-endian PowerPC Mach-O and drive IDA against it,
then
[2026-07-26-scsiserver-ppc-reconstruction-design.md](2026-07-26-scsiserver-ppc-reconstruction-design.md)
and
[2026-07-26-scsitape-ppc-reconstruction-design.md](2026-07-26-scsitape-ppc-reconstruction-design.md)
reconstructed `SCSIServer` and `SCSITape`.

Both of those started from a measured gap. `SCSIServer` mapped 41 of 68 named
functions and carried 51 findings; `SCSITape` mapped 44 of 50 and needed four
absent bodies. Knowing that number up front is what let each spec state
achievable acceptance instead of an aspirational one — and `SCSIServer`'s
review found the harder lesson, asserting a bar it could not meet and ending
with 31 open ledger entries.

For these five drivers no such number exists. Their sources have never been
compared against Apple's binaries at all. Doing five reconstructions blind
would repeat `SCSIServer`'s mistake five times. This spec produces the numbers
first, cheaply, and ends with a decomposition proposal ranked by measured gap.

### The sources are already here

The four drivers absent from `src/drivers-ppc` are not absent from the tree.
They are Apple's own sources under `src/kernel-7/bsd/dev/ppc/`, wired into
`src/kernel-7/conf/files.ppc:83-133` under `mk_hasdrivers`. Their Objective-C
class inventories match the shipped binaries:

| Reference binary | Module classes in binary | Source directory |
| --- | --- | --- |
| `drvPPCCuda` | `AppleCuda` | `bsd/dev/ppc/drvCuda` |
| `drvPPC53c96` | `Apple96_SCSI` | `bsd/dev/ppc/drvApple96_SCSI` |
| `drvPPCATA` | `IdeController`, `AtapiController`, `IdeDisk` | `bsd/dev/ppc/drvPPCATA` + `bsd/dev/ppc/drvATADisk` |
| `drvPPCBMac` | `BMacEnet` | `bsd/dev/ppc/drvBMacEnet` |
| `drvPPCBurgundy` | `PPCBurgundy` | `src/drivers-ppc/sound/drvPPCBurgundy/PPCBurgundy.drvproj/PPCBurgundy.lksproj` |

Class names were read from each binary's `.objc_class_name_*` symbols. Every
module-owned class corresponds, with one exception recorded in §4.2.

Method counts corroborate the correspondence:

| Driver | ObjC method definitions in source | Static C functions | Distinct method-name strings in binary |
| --- | --- | --- | --- |
| `drvCuda` | 39 | 0 | ~41 |
| `drvApple96_SCSI` | 124 | 9 | ~92 |
| `drvPPCATA` + `drvATADisk` | 153 | 7 | ~148 |
| `drvBMacEnet` | 63 | 3 | ~67 |
| `drvPPCBurgundy` | 38 | 0 | ~40 |

The binary column is a regular-expression count of distinct `-[…]`/`+[…]`
strings, so it is indicative rather than exact — establishing that these are
the same drivers, not the precise gap. Producing the precise gap is this
spec's job.

## 1. Scope

### 1.1 Reference artifacts

Ten Mach-O files under
`C:\Users\raynorpat\Downloads\test\Drivers\ppc`, each driver contributing a
bundle stub and a kernel-server `_reloc`:

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCCuda.config/drvPPCCuda` | 8496 | `B82C4317C9DE095AC20C96FB69D902AE7C90DEAA6DB2443F50A7C3AAA5B1C07A` |
| `drvPPCCuda.config/drvPPCCuda_reloc` | 43328 | `8CA26E3452246DE99BBD1731586B154B0B339DF3F4C2E65A50C000CC33EE1D1F` |
| `drvPPC53c96.config/drvPPC53c96` | 8496 | `4DC866362B9394DD093FF967C2CA5BF25AC2813E64ECABC5BBDDF44719F69C1D` |
| `drvPPC53c96.config/drvPPC53c96_reloc` | 151244 | `D4E01B128C43F18EB1357FC62874A8B89471C77F2BE4C0D955BE18054700B251` |
| `drvPPCATA.config/drvPPCATA` | 8492 | `348D054DF4EA489937D1980128E0EC0F451FE0983BE21AB8D7C5D44858D19DD7` |
| `drvPPCATA.config/drvPPCATA_reloc` | 134952 | `734464DC6604C7430761D95E3FA2D51C3C5A9E38956FD847B15390CD3448F597` |
| `drvPPCBMac.config/drvPPCBMac` | 8496 | `193D2E4FA1BF8DD70A48AB78F6335CC416864FE6504546C68774B21603C468C9` |
| `drvPPCBMac.config/drvPPCBMac_reloc` | 77828 | `F940BFBF0B67652409BF430F2A380D432B4BA59EAEE377A5FF218A0AE49DE616` |
| `drvPPCBurgundy.config/drvPPCBurgundy` | 8504 | `D16D9B2355C96D6CEEBEA6346454BE438D5B5DB589F53BD8EDB457182304A1CE` |
| `drvPPCBurgundy.config/drvPPCBurgundy_reloc` | 38652 | `D49E3479C9F0D2E7417A10ABAA3DC7D49562C1D4D2E1DCE77CAE467B96EB97CE` |

Artifacts stay outside Git. Any later regeneration must reproduce these
hashes, or the measurement describes different bytes than this spec does.

### 1.2 Out of scope

- **Repairing divergences.** Findings are recorded, not fixed.
- **Writing absent function bodies.**
- **Loadable-bundle packaging.** The four kernel-resident drivers build into
  the kernel; the shipped artifacts are loadable kernel servers. The gap is
  recorded as a finding (§4.4) and deferred to the per-driver specs.
- **Kernel build wiring.** `conf/files.ppc` is read, never edited.
- **Any PowerPC compile.** There is no PowerPC toolchain in this environment;
  `vm/` holds only `build-i386-*.sh`. **Nothing in this spec is
  compile-verified**, and `parity_check.py` and `import_check.py` — both of
  which need a rebuilt binary — remain unusable.
- **Naming IDA's unnamed PowerPC glue stubs.** The tooling change that would
  let source maps cover C functions is written up as a follow-on (§6), not
  attempted here.

One narrow exception to "no tool changes": see §3.6.

## 2. Design

### 2.1 Profiles

Ten profiles on the existing naming convention:

```
tools/binrecon/profiles/{cuda,53c96,ata,bmac,burgundy}-ppc.json
tools/binrecon/profiles/{cuda,53c96,ata,bmac,burgundy}-bundle-ppc.json
```

Each takes the shape of `scsitape-ppc.json`: `"architecture": "ppc"`,
`"endianness": "big"`, IDA enabled at a 900-second timeout, Ghidra and angr
disabled — both reject a PowerPC profile before starting a subprocess — and
`output_dir` pointing at `../out/<name>-ppc`. Reference path is
`${BINRECON_REFERENCE}`; there is no rebuilt artifact.

Analyzer output lands under `tools/binrecon/out/`, which `.gitignore:25`
already excludes. Generated evidence stays out of Git, as with every prior
profile.

### 2.2 Checked-in artifacts

```
src/drivers-ppc/reconstruction/
    report.md
    Cuda/source-map.json
    53c96/source-map.json
    ATA/source-map.json
    BMac/source-map.json
    Burgundy/source-map.json
```

This is one shared home rather than the one-`reconstruction`-per-project
layout that `src/drvSCSITape` and `src/drvBPF` use. Two reasons: four of the
five sources live in `src/kernel-7`, and putting driver-reconstruction
artifacts inside the kernel tree misplaces them; and `report.md` covers all
five drivers at once, so a per-project layout would either duplicate it or
assign it arbitrarily to one driver.

A source map's `source_path` is repo-relative — verified against
`src/drvSCSITape/reconstruction/SCSITape/source-map.json` — so entries
pointing into `src/kernel-7/bsd/dev/ppc/…` resolve correctly from a
`drivers-ppc` home given the repo root.

No ledgers are seeded. A ledger's value is the reviewed status of its
entries, and this spec reviews none; seeding `drvPPC53c96` alone would commit
several hundred `unexamined` entries carrying no information. Each per-driver
spec seeds its own from its source map with `tools/binrecon/seed_ledger.py`,
as §3.3 of the SCSITape spec requires.

`.gitignore:30` already covers `**/reconstruction/**/*.lock`, so the shared
home needs no new rule.

## 3. Method

### 3.1 Phase 1 — analyses

Run `binrecon analyze` once per profile with `BINRECON_REFERENCE` set to that
artifact's absolute path.

These are reference-only profiles: with no rebuilt artifact,
`normalized-functions` acceptance can never pass, so **exit 1 is the expected
outcome and is not a failure**. The pass condition is `"complete": true` in
the run summary plus a published `analysis-reference-ida.json`, exactly the
bar the seven existing PowerPC profiles are held to.

Runs are sequential — binrecon holds cross-process locks and invokes analyzers
one at a time. Ten runs against binaries up to 151 KB should be budgeted at an
hour or more of wall clock.

### 3.2 Phase 2 — invariant checks

`ppc_invariant_check.py --binary … --analysis …` against all ten, confirming
the relocation decode holds: HI16/HA16 halves agreeing with their LO16
partners, and scattered/difference forms reconstructing inside a real section.

The check also reports symbols whose address IDA did not recognize as a
function start. Those are enumerated as `boundary_disputed` candidates for
later specs — the same disposition `+[SCSIServer deviceStyle]` and
`+[SCSITape deviceStyle]` received. They are not relocation-decoder defects
and do not fail this phase.

### 3.3 Phase 3 — source maps

Per driver, against its `_reloc` analysis:

```
binrecon source-map --objc-methods --scope-to-objc \
  --reference-analysis <published analysis> --binary <_reloc> \
  --source-dir <source dir> --repo-root . --output <source-map.json>
```

`--scope-to-objc` is mandatory on PowerPC. Without it the run fails: IDA's
PowerPC linker glue stubs for external calls carry no name, and
`source-map-v1` requires every analyzed function to have one. This is the
same failure the SCSIServer spec hit.

`--source-dir` is repeatable, so `drvPPCATA` passes both `bsd/dev/ppc/drvPPCATA`
and `bsd/dev/ppc/drvATADisk` in one invocation. All five source directories
are flat, and the scanner does not recurse, so every file is reached.

### 3.4 Phase 4 — the non-Objective-C remainder

`--scope-to-objc` puts every non-Objective-C function outside the map. Left
alone, that reads as coverage the map does not have. So for each binary, every
function IDA found that the scoped map did not cover — named or not — is
placed in exactly one bucket:

1. **crt/dyld startup routines** — `start`, `__start`,
   `__call_mod_init_funcs`, `__dyld_init_check`, `dyld_stub_binding_helper`,
   `__dyld_func_lookup`.
2. **`__picsymbol_stub` entries** — verified arithmetically against the stub
   section size as an exact multiple of 36, and matched one-for-one to their
   imported names.
3. **Unnamed jump islands** — `lis`/`mr`/`mtctr`/`bctr` branch glue, excluded
   from maps by `filter_named_functions.py` because they carry no name.
4. **Build-generated classes** — `drv<Name>KernelServerInstance` and
   `drv<Name>Version`, emitted by the Kernel Server build. Both appear in
   every one of the five binaries' class inventories.
5. **A C function matched to a source site** — recorded with file and line.
6. **A C function with no source site** — the finding.

Buckets 1–4 are explained-and-expected; 5 is measured correspondence; 6 is the
gap. Bucket 6 is what the per-driver specs will have to write.

`selector_check.py REFERENCE_BINARY SOURCE_DIR` runs per driver. It takes a
single source directory, so `drvPPCATA` needs two runs whose results are
merged in the report.

### 3.5 Phase 5 — report

§4 specifies the contents.

### 3.6 One tool change permitted

`scsitape-ppc` did not publish on its first attempt: IDA's PowerPC loader hit
a `PPC_RELOC_SECTDIFF` switch table in `__TEXT,__const`, and the exporter's
fixup-integrity check rejected the 32-bit wrap of that scattered
section-difference fixup as corruption rather than a legitimate negative
displacement. Commit `12a64a6c` fixed it, and a later pass replaced the
masking arithmetic with an explicit sign-extend-then-range-check.

`drvPPC53c96` and `drvPPCATA` are roughly three times the size of
`SCSITape_reloc` and correspondingly likelier to contain switch tables. **A
defect that blocks an artifact from publishing is in scope to fix**, because
otherwise the measurement cannot complete. Any such fix follows `12a64a6c`'s
precedent: a targeted change with a test, never a widening of what the
integrity check accepts. Tool changes for any other reason are out of scope.

## 4. The report

`src/drivers-ppc/reconstruction/report.md`, in five parts.

### 4.1 Correspondence

Per driver: named functions, mapped, unmapped, mapped bytes, unmapped bytes.
Every row must reconcile against IDA's named-function count for that binary.

### 4.2 Class inventory

Binary versus source, per driver, including this already-found difference:
the shipped `drvPPCATA` links a class `IdeDisk`, while the tree defines
`ATADisk : IODisk` in `bsd/dev/ppc/drvATADisk`. The source itself still refers
to the old name — `drvATADisk/ATADiskKernel.m:90` cites `IdeDiskInternal.h`,
and `drvPPCATA/AtapiCnt.m:76`, `IdeCntCmds.h:100` and `IdeCntCmds.m:59` all
name `IdeDisk` in comments. That is strong evidence of a rename between the
Rhapsody build and the Darwin release rather than two distinct classes.

The analysis settles it, but not automatically. `source-map` matches by name,
so every `-[IdeDisk …]` in the binary will report unmapped against a source
that defines `-[ATADisk …]`, and `drvPPCATA`'s map will look far worse than
the driver actually is. **Expect this and account for it**: the report
compares the two selector sets by hand, and a rename is established when
`IdeDisk`'s selectors and `ATADisk`'s coincide and their sizes correspond. If
they do, `drvPPCATA`'s correspondence table carries both the raw count and the
rename-adjusted count, with the difference attributed to this finding.

### 4.3 Non-Objective-C remainder

The Phase 4 bucket tables, plus merged `selector_check.py` output per driver.

### 4.4 Findings

Each with the reference evidence that establishes it. The packaging gap is
recorded here: four of the five sources build into the kernel via
`conf/files.ppc:83-133` under `mk_hasdrivers`, while the shipped artifacts are
loadable kernel servers with their own `Default.table`, `DriverInfo` and
`_reloc`. This spec does not close that gap.

### 4.5 Decomposition proposal

The per-driver specs to follow, ranked by **measured gap rather than binary
size** — `SCSITape` is 91 KB across four binaries and needed four function
bodies, while `SCSIServer` is 51 KB in one and needed far more. Each entry
states its mapped/unmapped counts, its bucket-6 C functions, and whether its
findings look like drift or like a different driver version.

The tooling follow-on (§6) is listed here as its own candidate.

## 5. Acceptance

Done when all of the following hold, with output shown:

1. Ten `analyze` runs report `"complete": true` and publish
   `analysis-reference-ida.json`. Exit 1 throughout is expected; it is the
   documented outcome for a reference-only profile.
2. `ppc_invariant_check.py` reports **0 relocation violations** across all ten
   artifacts. Symbol/function-start mismatches are enumerated in §4.3, not
   required to be zero.
3. Five source maps exist, and `load_source_map` accepts each against its
   reference analysis and the repo root — re-verifying the exact function
   partition, names, full function sizes, source-line bounds, boundary
   overlaps, and the analysis's SHA-256 identity against §1.1.
4. **0 `duplicate_candidates`** across all five maps. `boundary_disputed`
   entries are enumerated with cause; a nonzero count is a finding, not a
   failure.
5. Every function IDA found in every binary lands in exactly one of: mapped,
   or Phase 4's six buckets. Per binary, mapped plus the six buckets sums to
   IDA's total function count — total, not named, because bucket 3 is
   precisely the unnamed islands. This is the check that makes the C-function
   gap countable rather than invisible, and it is the strictest item here.
6. The binrecon suite is green
   (`pytest tools/binrecon/tests -q`, with `PYTHONPATH=tools/binrecon`).
7. `report.md` carries all five parts of §4, and §4.5 names each follow-on
   spec with its measured gap.

These prove structural correspondence between our sources and Apple's
binaries. **They do not prove that any of these drivers builds or runs**, and
this spec does not claim otherwise.

### 5.1 Known risk to item 5

`drvPPC53c96` has several hundred functions. A long tail of oddities that
resist bucketing is the likeliest way this spec overruns. If an item cannot be
bucketed, it is recorded in §4.4 as an open question with what was tried —
the SCSITape spec's lesson was that stating the achievable condition beats
asserting the strong one and missing it. Item 5 stands; an explicitly recorded
unbucketable function satisfies it, an unexamined one does not.

## 6. Follow-on work

- **Name IDA's PowerPC glue stubs**, so `source-map` runs without
  `--scope-to-objc` and C functions enter the machine-checked map instead of
  §4.3's hand-built tables. The README notes these stubs resolve through the
  Mach-O external relocation table, which `binrecon.macho.read_macho` already
  parses. This spec's bucket tables are the natural test fixtures.
- **Per-driver reconstruction specs**, ranked by §4.5.
- **A PowerPC build.** The tree carries the pieces — `src/cctools-2`
  (`as/ppc.c`, `as/ppc-opcode.h`, `ld/ppc_reloc.c`) and GCC's `rs6000`
  configuration in `src/cc-1`. Standing one up would make `parity_check.py`
  and `import_check.py` usable and let every deferred PowerPC body be
  compile-verified.
- **Loadable-bundle packaging** for the four kernel-resident drivers (§4.4).
