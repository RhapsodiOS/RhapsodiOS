# PowerPC SCSI driver evidence base

Two in-tree PowerPC SCSI driver sources measured against Apple's shipped
Rhapsody binaries, per
[docs/superpowers/specs/2026-07-27-ppc-scsi-driver-evidence-base-design.md](../../../docs/superpowers/specs/2026-07-27-ppc-scsi-driver-evidence-base-design.md).

This report changes no driver source and no build wiring. It records what was
measured. Every number below comes from a command run for this report against
the published analyses, the checked-in source maps and the reference binaries;
the per-driver `findings.md` beside this file carries the evidence for each
cause attributed here.

It is a **third** report rather than an extension of [report.md](report.md)
(five drivers: `drvPPCCuda`, `drvPPC53c96`, `drvPPCATA`, `drvPPCBMac`,
`drvPPCBurgundy`) or [report-network.md](report-network.md) (four network
drivers plus the `IOEthernet` family). Each was measured against a different set
of binaries with its own acceptance run. §6 cross-references `report.md` for
`Apple96_SCSI` and `AtapiController`, which are **not re-measured here**.

`Floppy`, the third shipped PowerPC storage driver, is deferred to its own spec
— 183 defined C functions against these two drivers' 15 apiece, which
`--scope-to-objc` would push entirely into hand resolution (spec, motivation).

**What this does not establish.** No PowerPC toolchain exists in this
environment, so nothing here is compile-verified. These are structural
correspondences between our sources and Apple's binaries, not proof that either
driver builds or runs.

Reference artifacts are the four Mach-O files under
`C:\Users\raynorpat\Downloads\test\Drivers\ppc`, two bundle stubs and two
kernel-server `_reloc` images. All four SHA-256 identities and sizes carried in
the published analyses match spec §1.1; see [Acceptance](#acceptance) item 1.

---

## 1. Correspondence

Summary table, re-derived from
`tools/binrecon/out/<profile>/published/analysis-reference-ida.json` and each
`source-map.json`:

```
driver      total  mapped  unmap  dup  disp     mapB   unmapB
Mesh          173      66      6    0     0    16060      904
Sym8xx        146      44      2    0     0    13624       36
```

`total` is IDA's total function count for the `_reloc` binary. `mapB`/`unmapB`
are mapped and unmapped bytes.

The two drivers separate on the `unmapped` column, and that is the whole of the
correspondence story. **Sym8xx's 2 unmapped are both build-generated accessors**
(20 + 16 = 36 bytes, the same tool-emitted pair every driver measured across all
three specs carries). **Mesh's 6 are those same 2 plus 4 genuine Objective-C
gaps** (868 bytes), characterised individually in §4.2.

### Named / unnamed split

`--scope-to-objc` restricts each map to the binary's Objective-C methods, so the
named/unnamed split is what makes the rest of the binary countable:

```
driver      total  named  unnamed   objc  nonobjc
Mesh          173     77       96     72        5
Sym8xx        146     50       96     46        4
```

`objc` is the in-scope set the source map operates on (`mapped + unmapped`);
`nonobjc` is the named C functions the map deliberately does not claim, which §3
buckets by hand. `unnamed` is bucket 3, and it is **96 in both** — the same
count, in two binaries of different size with different method inventories.

### Row reconciliation

Each row reconciles as `mapped + bucket1..6 = total`. The `unmapped` column is
not a separate term: in Sym8xx it lands entirely in bucket 4, and in Mesh its
build-generated 2 land in bucket 4 while its 4 real gaps land in bucket 6.

| Driver | mapped | b1 | b2 | b3 | b4 | b5 | b6 | sum | total |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Mesh | 66 | 0 | 0 | 96 | 2 | 0 | 9 | 173 | 173 |
| Sym8xx | 44 | 0 | 0 | 96 | 2 | 0 | 4 | 146 | 146 |

Both print `RECONCILES: yes`. Bucket 5 is 0 straight out of the bucketing script
by construction — entries move into it by hand, per §3.

### One symbol per binary sits at address 0x0

Each `_reloc` carries exactly one `__TEXT,__text` symbol at address `0x0` that
IDA does not treat as a function start, so it can appear in neither `mapped` nor
`unmapped`:

| Driver | Symbol at 0x0 | Source site | Kind |
| --- | --- | --- | --- |
| Mesh | `_AllocateEventLog` | `MESH_DBDMA.m:298` | plain C function |
| Sym8xx | `-[Sym8xxController(Execute) commandRequestOccurred]` | `Sym8xxExecute.m:44` | Objective-C method |

Address 0x0 is the Mach-O header/load-command region, not a code address in a
relocatable object: these are symbol-table entries with placeholder addresses,
the same disposition the two previous reports recorded for their nine binaries.
Neither overlaps any function in any bucket table or source map, so neither
affects the correspondence numbers.

**Mesh's is the first that is a plain C function rather than an Objective-C
method**, which is why Mesh — unlike every driver in the network batch — has no
off-by-one between its source method count and its mapped count from this cause.
Sym8xx's is the reason its `read_macho` selector count (47) exceeds its
`mapped + unmapped` (46) by one. Evidence: [Mesh/findings.md](Mesh/findings.md)
and [Sym8xx/findings.md](Sym8xx/findings.md), each "Invariant check".

---

## 2. Class inventory

Module-owned classes, derived for this report from the `-[...]`/`+[...]` symbols
in each `_reloc` via `binrecon.macho.read_macho`, which — unlike IDA's export —
preserves category tags:

| Driver | Binary class (methods) | Binary categories | Source `@implementation` blocks |
| --- | --- | --- | --- |
| Mesh | `AppleMesh_SCSI` (70) | `Hardware`, `HardwarePrivate`, `MeshInterrupt`, `Mesh`, `Private` | `AppleMesh_SCSI` + the same 5 categories, all six in `MESH_DBDMA.m` |
| Sym8xx | `Sym8xxController` (45) | `Client`, `Execute`, `Init` | `Sym8xxController` + the same 3 categories, across 4 `.m` files |

Both binaries additionally carry `drv<Name>KernelServerInstance` and
`drv<Name>Version`, one method each — the build-generated pair that populates
bucket 4 in both (§3), bringing the symbol totals to 72 and 47.

**Class and category structure corresponds one-for-one in both.** Neither shows
anything resembling `report.md`'s `IdeDisk`/`ATADisk` rename, and
`selector_check.py` reports **0 renames and 0 duplicates** for both (§3).

Superclasses, confirmed from source: `AppleMesh_SCSI : IOSCSIController
< IOPower >` (`MESH_DBDMA.h:668`) and `Sym8xxController : IOSCSIController`
(`Sym8xxController.h:51`).

### Category attribution required `read_macho`, not the source map

The map-derived per-category split returns **everything under `(primary)`** for
both drivers — `{'(primary)': 66}` for Mesh and `{'(primary)': 44}` for Sym8xx.
That is IDA's export stripping Objective-C category tags: it flattens
`-[Class(Category) selector]` to `-[Class selector]`, so the reference names the
source map carries have no category to group by. This is spec §5.1's known risk,
and it is why the real split below was read from each binary's own symbol table
with `binrecon.macho.read_macho` instead.

### How Mesh's six categories divide its binary

72 Objective-C symbols, split by `read_macho` as
`{'(primary)': 22, 'Hardware': 3, 'HardwarePrivate': 6, 'MeshInterrupt': 13,
'Mesh': 10, 'Private': 18}`. Joining each mapped address back to that symbol
table gives:

| Category | Mapped | Unmapped | Binary total | Source defs |
| --- | --- | --- | --- | --- |
| `(primary)` (`AppleMesh_SCSI`) | 20 | 0 | 20 | 22 |
| `Hardware` | 2 | 1 (`ResetHardware:reason:`) | 3 | 3 |
| `HardwarePrivate` | 6 | 0 | 6 | 7 |
| `MeshInterrupt` | 13 | 0 | 13 | 13 |
| `Mesh` | 8 | 2 (`ResetMESH:reason:`, `IssueAbort`) | 10 | 11 |
| `Private` | 17 | 1 (`killActiveCommandAndResetBus:reason:`) | 18 | 17 |
| **`AppleMesh_SCSI` subtotal** | **66** | **4** | **70** | **73** |
| build-generated (`drvPPCMeshKernelServerInstance`, `drvPPCMeshVersion`) | 0 | 2 | 2 | 0 |
| **Total** | **66** | **6** | **72** | **73** |

`MeshInterrupt` is the only category with a perfect 1:1 match at 13/13/13. This
is the most category-fragmented driver measured across all three specs, and
every other category carries at least one unmapped or extra selector.

### How Sym8xx's three categories divide its binary

47 Objective-C symbols, split as `{'Execute': 22, 'Init': 8, 'Client': 15,
'(primary)': 2}`:

| Category | Mapped | Unmapped | At 0x0 | Binary total | Source defs |
| --- | --- | --- | --- | --- | --- |
| `Client` | 15 | 0 | 0 | 15 | 15 |
| `Execute` | 21 | 0 | 1 (`commandRequestOccurred`) | 22 | 22 |
| `Init` | 8 | 0 | 0 | 8 | 8 |
| **`Sym8xxController` subtotal** | **44** | **0** | **1** | **45** | **45** |
| build-generated | 0 | 2 | 0 | 2 | 0 |
| **Total** | **44** | **2** | **1** | **47** | **45** |

**All three of Sym8xx's categories match their source block counts exactly**
(15/15, 22/22, 8/8), and its `@implementation Sym8xxController` primary block in
`Sym8xxMisc.m:29` is empty — `@implementation`/`@end` with no methods.

That is not an accident of counting: **`drvPPCSym8xx_reloc`'s
`__OBJC,__inst_meth` section is size 0**, measured directly for this report
alongside `__cat_inst_meth` (552), `__cls_meth` (40) and `__cat_cls_meth` (20).
Every instance method in this driver lives in a category. Mesh, by contrast,
carries `__inst_meth` at 236 bytes. Evidence:
[Sym8xx/findings.md](Sym8xx/findings.md), "Categories".

---

## 3. Non-Objective-C remainder

`--scope-to-objc` puts every non-Objective-C function outside the map. Left
alone that would read as coverage the map does not have, so every function IDA
found that the map does not cover is placed in exactly one of spec §3.4's six
buckets.

### Buckets 1 and 2 are empty in both

**Bucket 1 (crt/dyld startup routines): 0 in both. Bucket 2
(`__picsymbol_stub` entries): 0 in both.** This is not an omission. Both
`_reloc` images are **statically linked kernel servers, not `MH_EXECUTE`
helpers**: they carry no `start`/`__start`/`__call_mod_init_funcs`/
`__dyld_init_check`/`dyld_stub_binding_helper`/`__dyld_func_lookup`, and their
analyses carry **no `__picsymbol_stub` section** for the stub-range check to
match against. The section lists re-derived for this report confirm it directly
— `__text`, `__cstring`, `__const`, `__data`/`__bss` where present, `__common`,
the Objective-C metadata sections, `__symbols` and the DriverKit `Server Name`/
`Server Version` pseudo-sections, with no stub section in either.

The crt/dyld routines do exist, but in the *bundle stubs*: both bundle analyses
contain exactly two functions, `dyld_stub_binding_helper` (0xf04, 48 bytes) and
`__dyld_func_lookup` (0xf34, 32 bytes), and no driver code at all. No source map
or bucket table was built for the stubs. This matches all nine binaries in the
two previous reports; it is a property of the artifact shape, not of any driver.

### Bucket 4 — build-generated classes

Two entries in both, identical in shape:

| Driver | Address | Symbol | Size |
| --- | --- | --- | --- |
| Mesh | 0x4cec / 0x4d00 | `+[drvPPCMeshKernelServerInstance kernelServerInstance]` / `+[drvPPCMeshVersion driverKitVersionFordrvPPCMesh]` | 20 / 16 |
| Sym8xx | 0x3ebc / 0x3ed0 | `+[drvPPCSym8xxKernelServerInstance kernelServerInstance]` / `+[drvPPCSym8xxVersion driverKitVersionFordrvPPCSym8xx]` | 20 / 16 |

These are DriverKit build-tooling output, not hand-written driver code.

### Buckets 3, 5 and 6 per driver

| Driver | b3 unnamed islands | b6 from script | to b5 by hand | b6 residue |
| --- | --- | --- | --- | --- |
| Mesh | 96 | 9 | 5 | **4** |
| Sym8xx | 96 | 4 | 4 | **0** |

**Sym8xx has no bucket-6 residue at all** — every one of its four bucket-6
entries has an exact-name source definition and moves to bucket 5. Not even a
libgcc helper is left over; unlike GNic, Gem, Mace, BMac and ATA it carries no
`__udivdi3`.

Bucket-5 moves are recorded with file and line in each `findings.md`:

- [Sym8xx](Sym8xx/findings.md): `_Sym8xxGrowSRBPool` (`Sym8xxClient.m:798`),
  `_Sym8xxTimerReq` (`Sym8xxClient.m:853`), `_Sym8xxReadRegs`
  (`Sym8xxMisc.m:36`), `_Sym8xxWriteRegs` (`Sym8xxMisc.m:57`) — all four
  non-static free functions declared in `Sym8xxController.h`, each confirmed by
  basic-block structure against the source, not by name alone.
  `_Sym8xxGrowSRBPool` is a C trampoline that *calls* the identically named
  Objective-C method `-[Sym8xxController(Client) Sym8xxGrowSRBPool]` (mapped at
  0x3b14); the two coexist deliberately, with a source comment saying why.
- [Mesh](Mesh/findings.md): `_EvLog` (`MESH_DBDMA.m:317`), `_Pause` (`:350`),
  `_serviceTimeoutInterrupt` (`:406`), `_getConfigParam` (`:1465`),
  `_GetSCSICommandLength` (`:1482`) — likewise confirmed by basic-block
  structure.

**Mesh's 4-entry bucket-6 residue is entirely Objective-C**, which no previous
driver's has been: `ResetHardware:reason:` (0x1164, 76 bytes),
`ResetMESH:reason:` (0x3348, 348), `IssueAbort` (0x3b4c, 352) and
`killActiveCommandAndResetBus:reason:` (0x480c, 92). None qualifies for bucket 5
because none has a source site with the *same selector* — only arity- or
name-mismatched siblings. §4.2 characterises each.

**Both structural confirmations are basic-block-shape only, not
instruction-level.** No decompiler was available in this session and the
reference analysis JSON carries CFG shape rather than disassembly text, so
neither driver got the byte-level treatment `report-network.md` §4.3 gave Gem's
`_mace_crc`. That bound is stated again in §5.

### Merged `selector_check.py` output

Per driver, re-run for this report against the `_reloc` binary and the source
directory named in spec §1.2:

| Driver | ref selectors | our defs | renames | duplicates | missing | extra | exit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Mesh | 72 | 73 | 0 | 0 | 6 | 7 | 0 |
| Sym8xx | 47 | 45 | 0 | 0 | 2 | **0** | 0 |

**Zero renames and zero duplicates in both.** Sym8xx's `missing` two are the
build-generated pair and its `extra` is empty — every one of its 45 source
selectors has an exact-selector match in the binary. Mesh's 6 missing are that
same pair plus its 4 real gaps, and its 7 extra are the source-side siblings
(§4.2).

Exact-name match rate (`ref - missing - renames`, over `ref`):

| Driver | matched | of | rate |
| --- | --- | --- | --- |
| Mesh | 66 | 72 | 91.7% |
| Sym8xx | 45 | 47 | 95.7% |

As the two previous reports established, match rate does not by itself rank the
work. Here it happens to agree with §5's ordering, but the reason Mesh ranks
first is the character of its 6 misses, not their count.

### Symbol / function-start mismatches

`ppc_invariant_check.py` reports one per artifact, four in four. None is a
relocation-decode defect (see [Acceptance](#acceptance) item 2), and none
overlaps any function in any bucket table or source map, so none affects the
correspondence numbers. The two `_reloc` symbols are tabulated in §1; both
bundle stubs report `__mh_bundle_header`, the standard synthetic bundle-header
symbol, which is not a function at all.

---

## 4. Findings

### 4.1 Sym8xx is the cleanest driver measured across all three specs

**44 mapped, 2 unmapped and both build-generated, 0 duplicate candidates, 0
boundary-disputed** — and a `selector_check.py` run with **0 renames, 0
duplicates, 0 extras, and a `missing` list containing nothing but the two
build-generated accessors** (§3). Its bucket table prints `RECONCILES: yes` with
a **bucket-6 residue of 0** after hand resolution, and all three of its
categories match their source block counts exactly (§2).

No driver in [report.md](report.md) or [report-network.md](report-network.md)
reaches that. The network batch's four came closest — 2 unmapped and 0/0 dup and
disputed apiece — but GNic, Gem and Mace each left a bucket-6 entry (`__udivdi3`,
and in Gem's case a genuine driver-code absence as well), while Dec21040, the one
that left none, carried two `extra` selectors. **Sym8xx is the only driver
measured with an empty bucket-6 residue and an empty `extra` list at the same
time.** Evidence:
[Sym8xx/findings.md](Sym8xx/findings.md), "Correspondence", "Buckets",
"Selector check".

The one asterisk is `-[Sym8xxController(Execute) commandRequestOccurred]` at
address `0x0` (§1), which `selector_check.py` matches by name — hence `extra 0`
— while the source map cannot place it by address. It is the same address-0x0
artifact all eleven `_reloc` binaries measured across the three specs show, not
a gap.

### 4.2 Mesh has four genuine Objective-C gaps, and none has a same-selector source site

Four selectors in `drvPPCMesh_reloc` have no source implementation under that
exact selector. Each has a *related* source method, and in every case the
relation is an arity or name mismatch rather than a match:

| Binary selector (size) | Closest source site | Relation |
| --- | --- | --- |
| `-[AppleMesh_SCSI(Hardware) ResetHardware:reason:]` (76) | `ResetHardware:` (`MESH_DBDMA.m:1208`) | one keyword vs two; no `reason:` variant in source |
| `-[AppleMesh_SCSI(Mesh) ResetMESH:reason:]` (348) | `ResetMESH:` (`:3392`) | same pattern |
| `-[AppleMesh_SCSI(Mesh) IssueAbort]` (352) | `AbortActiveCommand` (`:3739`), `AbortDisconnectedCommand` (`:3788`) | binary has one combined selector; source has two differently *named* methods |
| `-[AppleMesh_SCSI(Private) killActiveCommandAndResetBus:reason:]` (92) | `killActiveCommand:` (`:4429`), `threadResetBus:` (`:3998`) | both source siblings are **separately mapped**, at 0x4879 and 0x3fe4; the binary carries an additional combined wrapper source never implements |

This is why Mesh's bucket 6 keeps four Objective-C entries where every previous
driver's held only C functions: the bucket taxonomy asks whether a source site
exists *for the same function*, and here none does. Evidence:
[Mesh/findings.md](Mesh/findings.md), "Buckets" (Group B), "Unmapped detail" and
"Selector check".

**The runtime consequence is bounded, and the bound was measured.** Grepping
`src/` for each of the four selectors outside `drvAppleMesh_SCSI` returns
**nothing**: all four are referenced only from within `MESH_DBDMA.m` itself. Our
source is internally consistent — it calls `ResetHardware:` where Apple's binary
calls `ResetHardware:reason:` — so no external caller would hit an unrecognised
selector. This is a **version or refactoring divergence between our tree and the
source Apple shipped, not a broken call path**, and it is characterised, not
fixed (spec §1.3).

The combined wrapper is not a phantom. `killActiveCommandAndResetBus:reason:` is
declared at `drvApple96_SCSI/Apple96SCSIPrivate.h:151`, defined at
`Apple96SCSIPrivate.m:854` and called twice from `Apple96BusState.m` — so the
selector is real in Apple's own PowerPC SCSI family, and §6 confirms
`Apple96_SCSI`'s binary carries it too. Only `drvAppleMesh_SCSI` lacks it.

Mesh's three remaining `extra` selectors have no missing counterpart at all:
`getIntValues:forParameter:count:` and `setIntValues:forParameter:count:` (no
`IntValues`-shaped selector exists anywhere in the binary) and
`-[AppleMesh_SCSI(HardwarePrivate) StartBucket]`. These are source-only.

### 4.3 One open question: `isCmdTimedOut`, likely inlined

`MESH_DBDMA.m:426` defines `static BOOL isCmdTimedOut(...)`, called twice at
`:730` and `:753`, and **no symbol of that name appears anywhere in the
173-function reference analysis**. It is 14 lines and file-local, so compiler
inlining at both call sites is the likeliest explanation, and an inlined static
leaves no symbol for bucket 6 to list. **Recorded as an open question, not
asserted**: no decompiler was available to confirm inlining at either call site.
Evidence: [Mesh/findings.md](Mesh/findings.md), "Buckets".

### 4.4 Category attribution required `read_macho`

IDA's exported analysis strips Objective-C category tags, so the source-map-
derived per-category split returns everything under `(primary)` for both drivers
— `{'(primary)': 66}` and `{'(primary)': 44}`. The real splits (§2) were read
from each binary's own symbol table via `binrecon.macho.read_macho`, joining on
address rather than name: Mesh `(primary)` 22, `Hardware` 3, `HardwarePrivate`
6, `MeshInterrupt` 13, `Mesh` 10, `Private` 18; Sym8xx `Execute` 22, `Init` 8,
`Client` 15, `(primary)` 2.

Spec §5.1 named this as the likeliest way to get §4.2 wrong, and it was: with 6
and 3 categories these are the two most category-fragmented drivers measured,
and Sym8xx's `__OBJC,__inst_meth` section is **size 0** — every instance method
in a category. Any category claim made from the IDA export alone would have been
uniformly wrong. Evidence: [Mesh/findings.md](Mesh/findings.md) and
[Sym8xx/findings.md](Sym8xx/findings.md), each "Categories".

### 4.5 Two checker defects were found and fixed during this spec

Both were **false positives against acceptance item 2**, and in both cases the
relocation *decode* was always correct — only the checking was wrong. Neither
fix widened what the check accepts.

**HA16/LO16 paired by address rather than by address computation**
(`151282da`). `ppc_invariant_check.py` paired each scattered `HA16`/`HI16` with
the nearest same-target `LO16` by address alone. **Mesh is the first driver
measured to trip it**, and both sites were decoded by hand rather than taken at
face value:

- `0x120`: `addis r9,r0,0` (addend 8) was paired with `0x124: lwz r11,r11,0x600c`
  (addend 12) — but that instruction's **base register is r11**, not the `r9`
  the `addis` wrote, so it can never have been the real partner. The true
  partner is `0x128: lwz r9,r9,0x6008`, base `r9`, addend 8.
- `0x2b2c`: `addis r9,r0,0` (addend 24) was paired with
  `0x2b28: addi r25,r9,0x6016` (addend 22) — which **precedes** the `addis` and
  belongs to the previous computation. The true partner is
  `0x2b30: addi r26,r9,0x6018`, addend 24.

The checker now prefers the `LO16` whose base register matches the register the
`HA16`/`HI16` wrote, and a following `LO16` over a preceding one. Two regression
tests. Mesh went **3 → 1** violations.

**`__OBJC,__cat_cls_meth` missing from the method-list allowance** (`da51d92d`).
The allow-list for `__OBJC` pointers legitimately targeting `__TEXT,__text`
carried three of Objective-C's four method-list sections. **Sym8xx is the first
driver measured with a class method declared in a category** —
`+[Sym8xxController(Init) probe:]` (`Sym8xxInit.m:113`), which the raw
relocation at `0x6010` points to — so its IMP pointer was reported as a
violation. That arrangement is standard for IOKit drivers, since `probe:` must
run before any instance exists. One regression test, RED confirmed first.
Sym8xx went **2 → 1**.

After both fixes, **all four artifacts report exactly one item, and in every
case that item is the address-`0x0` symbol/function-start anomaly** — a
`boundary_disputed` pattern, not a relocation violation. **Actual relocation
violations: 0 across all four.** Evidence: [Mesh/findings.md](Mesh/findings.md)
and [Sym8xx/findings.md](Sym8xx/findings.md), each "Invariant check", and
[Acceptance](#acceptance) item 2.

The three tests added by these two commits are why the suite total is 833 rather
than the 830 spec §5 item 6 predicted ([Acceptance](#acceptance) item 6).

### 4.6 The packaging gap

**Both** sources build into the kernel. Re-read from
`src/kernel-7/conf/files.ppc` for this report:

```
107:bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m		optional mk_hasdrivers
135:bsd/dev/ppc/drvSymbios8xx/Sym8xxInit.m 			optional mk_hasdrivers
136:bsd/dev/ppc/drvSymbios8xx/Sym8xxClient.m 		optional mk_hasdrivers
137:bsd/dev/ppc/drvSymbios8xx/Sym8xxExecute.m 		optional mk_hasdrivers
138:bsd/dev/ppc/drvSymbios8xx/Sym8xxMisc.m 			optional mk_hasdrivers
```

i.e. compiled into the kernel binary whenever `mk_hasdrivers` is set, not built
as standalone targets. **Both shipped artifacts are loadable kernel servers** —
each a `<name>.config` bundle carrying a bundle stub plus a `_reloc`
kernel-server image (§1.1, and the four identities in
[Acceptance](#acceptance) item 1).

So both drivers are wired to build one way and shipped another. This is the same
divergence [report-network.md](report-network.md) §4.6 recorded for
`drvMaceEnet` and `drvDECchip21040`, and this spec does not close it either:
**recorded and deferred** to the per-driver specs, per spec §1.3. Nothing in
§1–§3 depends on it, because the measurement compares compiled function bodies,
which are the same either way. Evidence: [Mesh/findings.md](Mesh/findings.md)
and [Sym8xx/findings.md](Sym8xx/findings.md), each opening section.

### 4.7 Buckets 1 and 2 are empty across both

Stated in full in §3 rather than omitted. Both are 0 in both binaries because
these are **statically linked kernel servers, not `MH_EXECUTE` helpers**: no
crt/dyld startup routines, and no `__picsymbol_stub` section for the stub-range
check to match against. The crt/dyld routines live in the bundle stubs instead,
two per stub. This matches all nine binaries in the two previous reports.

---

## 5. Decomposition proposal

Ranked by **actionable divergence with runtime consequence** — the criterion the
two previous reports settled on. The tie-breaker is that an unmapped or bucket-6
entry with a documented, evidenced cause and no runtime consequence (a
build-generated accessor, a libgcc helper, a preprocessor exclusion) is **a
result, not work**.

Only two drivers are ranked here, and they separate cleanly: one has four
characterised divergences, the other has none.

### 1. `drvPPCMesh` — four evidenced Objective-C divergences

- **Measured:** 66 mapped / 6 unmapped / 0 dup / 0 disputed; 16060 mapped bytes
  against 904 unmapped. 173 functions.
- **Exact-name match: 66 of 72 (91.7%)**, the lower of the two.
- **Bucket 6 after hand resolution: 4** — all four Objective-C, all four
  characterised in §4.2, none a libgcc helper or a preprocessor exclusion.
- **Drift or different version?** A **different version**. The pattern is
  consistent across all four: the source Apple shipped had a `reason:` argument
  on its reset entry points (`ResetHardware:reason:`, `ResetMESH:reason:`) and
  two combined wrappers (`IssueAbort`,
  `killActiveCommandAndResetBus:reason:`) that our tree either drops or splits.
  `killActiveCommandAndResetBus:reason:` exists in `drvApple96_SCSI`'s in-tree
  source and in `Apple96_SCSI`'s binary (§4.2, §6), so the selector is real
  family API that our `drvAppleMesh_SCSI` either predates or postdates.
- **The follow-on spec's job:** decide, per selector, whether to adopt Apple's
  shipped shape or keep ours. The change is not mechanical — `IssueAbort` and
  `killActiveCommandAndResetBus:reason:` are *combinations* of methods our tree
  keeps separate, so adopting them means merging call paths, and
  `drvApple96_SCSI` is the working in-tree template for the latter. Also
  packaging (§4.6, `files.ppc:107`), and a decision on the three source-only
  selectors (`getIntValues:forParameter:count:`,
  `setIntValues:forParameter:count:`, `StartBucket`) — keep or delete. Its
  measured gap is **4 Objective-C selectors present in Apple's binary and absent
  from our source under that exact selector**.
- **What is a result, not work:** the 2 build-generated accessors, the 5 C
  helpers resolved to bucket 5, and the `_AllocateEventLog` symbol at 0x0.
  `isCmdTimedOut` (§4.3) is an open question carried forward, not a task.

It ranks first because it is the only driver here with any divergence at all —
**not** because a runtime break was demonstrated. §4.2 measured the opposite:
all four selectors are internally referenced only, so nothing calls a selector
our source does not implement. Compare [report-network.md](report-network.md)
§4.3, where Gem's CRC divergence changed the hash bucket actually programmed on
5 of 5 vectors. **No finding in this batch reaches that bar.**

### 2. `drvPPCSym8xx` — nothing on correspondence grounds

- **Measured:** 44 mapped / 2 unmapped / 0 dup / 0 disputed; 13624 mapped bytes
  against 36 unmapped. 146 functions.
- **Exact-name match: 45 of 47 (95.7%)**.
- **Bucket 6 after hand resolution: 0** — nothing left over, not even
  `__udivdi3`.
- **Drift or different version?** Neither observable. 0 renames, 0 duplicates,
  0 extras; all three categories match their source block counts exactly.
- **The follow-on spec's job:** packaging only (§4.6, `files.ppc:135-138`).
  Nothing on correspondence grounds. Its measured gap is **0 selectors** — the
  only driver measured across all three specs whose `selector_check.py` reports
  both an empty `extra` list and a `missing` list containing nothing but
  tool-emitted accessors. Worth a spec of its own only for a compile attempt
  once a PowerPC toolchain exists.
- **What is a result, not work:** the 2 build-generated accessors, the 4 C
  helpers resolved to bucket 5, the `commandRequestOccurred` symbol at 0x0, and
  the absence of `free` (§6, question 4) — `IOSCSIController` implements it at
  `src/driverkit-3/libDriver/Kernel/IOSCSIController.m:128`, so a subclass need
  not override it, and our source does not define it either.

### The limit of this ranking

**Nothing in this method systematically checks method bodies for behavioural
equivalence** — the source maps match names, addresses and sizes, and this
batch's bucket-5 confirmations are basic-block-shape only (§3), weaker than the
byte-level disassembly [report-network.md](report-network.md) §4.3 and §4.4
used. Sym8xx's clean correspondence bounds its *structure*, not its behaviour,
and Mesh's 66 mapped bodies were never compared instruction-for-instruction
against source. A per-driver spec for either should assume body-level divergence
is possible until a compile-and-compare exists.

### Recorded follow-on questions, not chased

Per spec §5.1 and §6 these are recorded and left alone:

- `isCmdTimedOut` (§4.3) — inlining is the likely explanation, unconfirmed.
- Why `AtapiController` implements only 20 selectors against the family's other
  three at 45–90 (§6). Its thinness is Apple's design; the shape of that design
  is not chased here.
- The three near-collisions between Mesh's and 53c96's selector names that
  differ only in arity (§6, question 3).
- Whether `Sym8xxController`'s empty primary `@implementation` and size-0
  `__inst_meth` (§2) reflect a deliberate convention or an artifact of how the
  driver was split across four files. The binary cannot distinguish these.
- **`Floppy`**, deferred to its own spec after the glue-stub naming work, and
  the naming work itself — still the highest-value tooling item, and the reason
  both bucket tables above are hand-resolved (spec §6).

---

## 6. The `IOSCSIController` family

With `Apple96_SCSI` and `AtapiController` from the five-driver spec, **four
`IOSCSIController` subclasses are now measured**. `drvPPC53c96` and `drvPPCATA`
are read from their committed source maps and [report.md](report.md); **neither
is re-measured**. `drvPPCATA` carries three classes, so it is filtered to
`AtapiController`.

Selector sets are the selector part of each binary's `-[Class selector]` /
`+[Class selector]` symbols. Two derivations were run: independently from the
four `_reloc` symbol tables via `read_macho`, and from the four committed source
maps. **The symbol-table derivation is the one reported below**, since it is the
complete picture of what Apple shipped; the disagreement is disclosed after
question 4.

```
Mesh     70 class symbols, 70 distinct selectors
Sym8xx   45 class symbols, 45 distinct selectors
53c96    90 class symbols, 90 distinct selectors
ATA      20 class symbols, 20 distinct selectors
```

Symbol count equals distinct-selector count in all four — unlike
[report-network.md](report-network.md)'s Dec21040, no class here carries a
duplicated selector. Mesh's 70 and Sym8xx's 45 reconcile against §2's tables;
53c96's 90 and ATA's 20 match [report.md](report.md)'s class inventory exactly.

> **This family is lopsided by design, and that is Apple's design, not a
> reconstruction gap.** `AtapiController` is a much thinner class than the other
> three — it drives ATAPI devices through the IDE controller rather than a full
> SCSI HBA, and in `drvPPCATA_reloc` it sits alongside `IdeController` (88
> methods) and `IdeDisk` (38), which carry the bulk of that driver's logic.
> **Both sides of every comparison below are Apple's own shipped binaries**, so
> a selector "missing" from `AtapiController` means Apple's `AtapiController`
> genuinely does not implement it, not that our source lost it. This follows
> [report-network.md](report-network.md) §6's handling of `drvPPCDec21040`'s 11.
> **The reconstruction signal is in question 4's result for Mesh and Sym8xx**,
> the two drivers actually measured here.

**This section is bounded to spec §4.6's four questions.** Anything beyond them
is a recorded follow-on question (§5), not chased.

### Question 1 — the selector set all four implement

**4 selectors** — the de facto `IOSCSIController` contract as Apple actually
shipped it on PowerPC:

```
executeRequest:buffer:client:
getDMAAlignment:
probe:
resetSCSIBus
```

That is a much smaller universal core than `IOEthernet`'s 30 across five
drivers, and `AtapiController`'s 20-selector ceiling is why: no selector can be
universal unless `AtapiController` has it. **The comparison is bounded above by
the thinnest member.** Note also that none of the four is the build-generated
`kernelServerInstance` — that accessor sits on `drv<Name>KernelServerInstance`,
a separate class, and so is correctly excluded by the class filter here, unlike
[report-network.md](report-network.md) §6 where it appeared in the universal
set.

### Question 2 — implemented by some but not all

**31 selectors**: 5 in three drivers, 26 in two.

| In | Selector | Drivers |
| --- | --- | --- |
| 3 | `commandRequestOccurred` | Mesh, Sym8xx, 53c96 |
| 3 | `executeRequest:ioMemoryDescriptor:` | Mesh, Sym8xx, 53c96 |
| 3 | `interruptOccurred` | Mesh, Sym8xx, 53c96 |
| 3 | `timeoutOccurred` | Mesh, Sym8xx, 53c96 |
| 3 | `free` | Mesh, 53c96, ATA |
| 2 | `maxTransfer` | 53c96, ATA |
| 2 | `abortAllCommands:`, `activateCommand:`, `commandCanBeStarted:`, `disconnect`, `executeCmdBuf:`, `getPowerManagement:`, `getPowerState:`, `hardwareStart:`, `interruptOccurredAt:`, `killActiveCommand:`, `killActiveCommandAndResetBus:reason:`, `killQueue:finalStatus:`, `logTimestamp:`, `maxQueueLength`, `numQueueSamples`, `otherOccurred:`, `pushbackCurrentRequest:`, `pushbackFullTargetQueue:`, `receiveMsg`, `selectNextRequest`, `setPowerManagement:`, `setPowerState:`, `sumQueueLengths`, `threadExecuteRequest:`, `threadResetBus:` | Mesh, 53c96 |

The dominant pattern is a **25-selector block shared by Mesh and 53c96 alone** —
the two `IOPower`-conforming HBA drivers (§2; `Apple96_SCSI : IOSCSIController
<IOPower>` per spec §1.2). It covers power management (`get`/`setPowerState:`,
`get`/`setPowerManagement:`), queue accounting (`maxQueueLength`,
`numQueueSamples`, `sumQueueLengths`, `logTimestamp:`), and the abort/reset
paths. `Sym8xxController` implements none of it, consistent with its declaration
carrying no `<IOPower>` protocol.

**`killActiveCommandAndResetBus:reason:` sits in this band**, on Mesh and 53c96.
That is the direct binary confirmation for §4.2: the selector Mesh's source
lacks is one Apple shipped on two of its four SCSI controllers, and
`drvApple96_SCSI`'s in-tree source implements it (`Apple96SCSIPrivate.m:854`).

The four in-3 selectors shared by Mesh, Sym8xx and 53c96 and absent from ATA —
`commandRequestOccurred`, `executeRequest:ioMemoryDescriptor:`,
`interruptOccurred`, `timeoutOccurred` — are question 4's answer for ATA.

### Question 3 — per-driver selectors, indicating hardware-specific behaviour

142 of the union's 177 selectors are implemented by exactly one driver — **80%**,
against `IOEthernet`'s 39 of 91 (43%). This family is far more
hardware-divergent than the Ethernet one.

```
Mesh: 36      AllocHdwAndChanMem:, ClearCPResults, DoHBASelfTest,
              DoHardwareInterrupt, DoInterruptStageArb, DoInterruptStageCmdO,
              DoInterruptStageGood, DoInterruptStageMsgO, DoInterruptStageSelA,
              DoInterruptStageXfer, DoInterruptStageXferAutosense,
              DoMessageInPhase, GetHBARegsAndClear:,
              HandleReselectionInterrupt, InitAutosenseCCL, InitCP,
              InitializeHardware:, IssueAbort, ProcessInterrupt, ProcessMSGI,
              ResetHardware:reason:, ResetMESH:reason:, RunDBDMA:stageLabel:,
              SetIntMask:, SetSeqReg:, SetupMsgO, UpdateCP:,
              UpdateCurrentIndex, WaitForMesh:, WaitForReq, deactivateCmd:,
              getReselectionTargetID, ioComplete:, killCurrentRequest,
              reselectNexus:lun:queueTag:, resetStatistics

Sym8xx: 37    35 Sym8xx-prefixed methods (Sym8xxAbortBdr: through
              Sym8xxUpdateXferOffset:), plus initFromDeviceDescription: and
              numberOfTargets

53c96: 55     30 fsm/curio/hardware-prefixed methods, plus busFree,
              clearChannelCommandResults, dbdmaTerminate, deactivateCmd,
              disableMode:, getIntValues:forParameter:count:,
              getReselectionTargetID:, initializeChannelProgram,
              initializePerTargetData, ioComplete:finalStatus:,
              logChannelCommandArea:, logCommand:logMemory:reason:,
              logIOMemoryDescriptor:, logMemory:length:reason:,
              logRegisters:reason:, powerDown, putMessageOutByte:setATN:,
              renegotiateSyncMode:, reselectNexusWithTag:,
              reselectNexusWithoutTag, resetStats,
              setIntValues:forParameter:count:

ATA: 14       allocAtapiBuf, atapiCmdDispatch:, atapiIoComplete:, deviceStyle,
              emulateSCSICmd:buffer:, enqueueAtapiBuf:, freeAtapiBuf:,
              initResources:, maptoAtapiCmd:buffer:,
              property_IODeviceClass:length:, property_IODeviceType:length:,
              requiredProtocols, scsiCmdLen:, unlockIoQLock
```

Each set is a naming convention as much as a capability set: Mesh's
`Do*`/`Init*`/`Process*` MESH sequencer stages, Sym8xx's uniform `Sym8xx` prefix
on 35 of its 37, and 53c96's `fsm*` state machine over its `curio*` chip layer.
The three carve the same job — bus phase sequencing, message handling,
reselection — three different ways, which is a large part of why the universal
set is only 4. **`AtapiController`'s 14 are the clearest statement of what it
is**: `emulateSCSICmd:buffer:`, `maptoAtapiCmd:buffer:` and `scsiCmdLen:` are an
ATAPI *translation* layer, not HBA control. It emulates SCSI over ATAPI rather
than driving a SCSI bus.

Three selectors near-collide across drivers without matching:
`getReselectionTargetID` (Mesh) versus `getReselectionTargetID:` (53c96),
`deactivateCmd:` (Mesh) versus `deactivateCmd` (53c96), and `ioComplete:` (Mesh)
versus `ioComplete:finalStatus:` (53c96) — the same arity-mismatch pattern §4.2
found *within* Mesh, here appearing *between* Apple's own drivers. Recorded as a
follow-on question (§5), not chased.

### Question 4 — is any driver missing a selector the other three share?

From the `_reloc` symbol tables:

```
Mesh: 0
Sym8xx: 1
      free
53c96: 0
ATA: 4
      commandRequestOccurred
      executeRequest:ioMemoryDescriptor:
      interruptOccurred
      timeoutOccurred
```

**Mesh, the more divergent of the two measured here, is missing nothing.** Its
four gaps (§4.2) are gaps between our *source* and Apple's binary; against the
family its binary is complete, and `killActiveCommandAndResetBus:reason:` — one
of those four — is a selector Mesh's binary *has*, and only Sym8xx and ATA lack.

**Sym8xx's one is `free`, and it is not a reconstruction gap.**
`IOSCSIController` implements `- free` at
`src/driverkit-3/libDriver/Kernel/IOSCSIController.m:128`, so a subclass that
adds no owned resources requiring teardown need not override it. Our source
agrees with the binary exactly: grepping `drvSymbios8xx` for a `free` method
definition returns nothing, and `selector_check.py` reports `extra (0)` (§3).
**Both sides match; neither implements `free`.** This is Apple's design in
`Sym8xxController`, reproduced identically in our tree.

**ATA's four are Apple's own factoring**, per the note above. All four are
event-callback entry points — `interruptOccurred`, `timeoutOccurred`,
`commandRequestOccurred` and `executeRequest:ioMemoryDescriptor:` — which the
three full HBA drivers implement and `AtapiController` does not, because in
`drvPPCATA` the interrupt and timeout paths belong to `IdeController` (88
methods), the class that actually owns the hardware; `AtapiController` is
dispatched *by* it. This is class factoring inside one driver, not an absence.
Cross-reference: [report.md](report.md) §2 and §4.6.

**On the source side, neither measured driver's source is missing any
family-shared selector.** `selector_check.py`'s `missing` list is exactly the two
build-generated accessors for Sym8xx, and for Mesh those two plus four selectors
that are not family-shared: `ResetHardware:reason:`, `ResetMESH:reason:` and
`IssueAbort` are Mesh-only (question 3), and
`killActiveCommandAndResetBus:reason:` is shared with 53c96 only, whose own
source implements it.

Union across the four: **177 selectors**, distributed 4 / 5 / 26 / 142 across
in-4 / in-3 / in-2 / in-1.

### Disclosure: where the two derivations disagree

The source-map derivation gives Mesh 70, Sym8xx 44, 53c96 89 and ATA 20 — the
same union of 177, and **the same answer for both drivers measured here**:

```
source-map Q4:  Mesh 0    Sym8xx 1 (free)    53c96 1 (probe:)    ATA 3
```

The two disagreements are both the address-`0x0` artifact of §1, which a source
map cannot carry:

- **Sym8xx 45 → 44**, losing `commandRequestOccurred`. Because that selector is
  in the in-3 band (absent from ATA), dropping it removes it from ATA's gap
  list, which is why ATA reads 3 rather than 4.
- **53c96 90 → 89**, losing `probe:` — the address-0x0 symbol in `53c96-ppc` is
  `+[Apple96_SCSI probe:]` ([report.md](report.md) §3). That drops `probe:` from
  the universal set (4 → 3) and produces a **spurious** 1-selector gap for
  53c96, which the symbol-table derivation correctly reports as 0.

Mesh shows no disagreement at all, because its address-0x0 symbol is the plain C
function `_AllocateEventLog`, not an Objective-C method (§1). **Both derivations
give Mesh 0 and Sym8xx 1, so the result for the two drivers measured here is
derivation-independent.** Checking both is what distinguishes the artifact from a
real gap, exactly as [report-network.md](report-network.md) §6 established.

---

## Acceptance

Spec §5, items 1–8. Every item below was observed in output run for this report;
nothing is claimed that was not run.

### Item 1 — four analyses complete and published — **PASS**

`complete: true` in every `run-summary.json`, and
`published/analysis-reference-ida.json` present for all four. Each analysis's
recorded input identity matches spec §1.1's sizes exactly:

```
profile              complete  published sha256                                                            size
mesh-ppc                 True       True 3B7251FBD0B83A14655E011B5033A4582DE88CCAC6B600FB3F940BDFF7127173  size=66712
mesh-bundle-ppc          True       True 681289A4691DD6D092D9CE4F98CF3D96690EC0AD8C850D54E587469A430E7B4F  size=8496
sym8xx-ppc               True       True 45092B9D7C33E4B9688C215D1806F1B1808670A61A2B6C376660B608B5746514  size=59128
sym8xx-bundle-ppc        True       True 6459396AF147D3BE11510553034744BB22BAFA647C12F1B3A97CEBA751E917A3  size=8500
```

Exit 1 throughout was the expected outcome for reference-only profiles, per spec
§3.1, and is not a failure.

### Item 2 — 0 relocation violations across all four — **PASS**

`ppc_invariant_check.py --binary ... --analysis ...` re-run against all four for
this report:

```
=== mesh-ppc ===
symbol _AllocateEventLog at 0x0 is not a function start
137 scattered/difference-form relocations (target section verified, field is a difference, not an address)
45 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1559 fused relocations, 1 violations
=== mesh-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered, 0 pairs, 0 fused relocations, 1 violations
=== sym8xx-ppc ===
symbol -[Sym8xxController(Execute) commandRequestOccurred] at 0x0 is not a function start
16 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1129 fused relocations, 1 violations
=== sym8xx-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered, 0 pairs, 0 fused relocations, 1 violations
```

Every run's `violations` count is 1, and in every case that 1 is the
symbol/function-start mismatch from `check_functions`, **not** a
relocation-decode violation from `check_document`. **Actual relocation
violations: 0 in all four.** The four mismatched symbols are enumerated in §1
(the two `_reloc` symbols at 0x0) and §3 (`__mh_bundle_header` in both stubs).
They are not required to be zero.

**This item required two checker fixes to reach, and both were false positives**
— `151282da` (register-aware HA16/LO16 pairing; Mesh 3 → 1) and `da51d92d`
(`__cat_cls_meth` in the method-list allowance; Sym8xx 2 → 1). In both cases the
relocation decode was always correct; both original findings were decoded by
hand before the tool was touched, and neither fix widened what the check
accepts. Full detail in §4.5.

### Item 3 — two maps load against a scoped reference analysis — **PASS**

Each map loaded via `load_source_map` against its reference analysis restricted
to the addresses that map covers across **all four map categories** (`mapped`
union `unmapped` union `duplicate_candidates` union `boundary_disputed`), with
the repo root:

```
Mesh OK (173 functions -> 72 scoped)
Sym8xx OK (146 functions -> 46 scoped)
```

72 = 66 mapped + 6 unmapped; 46 = 44 + 2. Scoping is required, not a weakening:
`--scope-to-objc` maps do not claim the unnamed jump islands and
`load_source_map` enforces an *exact* partition, so an unscoped analysis fails.
Over everything each map does claim, the check verifies the full partition,
names, sizes, source-line bounds and the analysis's SHA-256 identity. Item 5
independently accounts for every function scoped out — 101 + 100 — so the pair
together covers all 319 functions (118 scoped in, 201 out).

### Item 4 — duplicates and disputes enumerated — **PASS**

`duplicate_candidates` is **0 for both**. `boundary_disputed` is **0 for both**.
Nothing to enumerate; the counts are in §1's summary table, and each
`findings.md` records them independently.

The one symbol per binary at address 0x0 (§1) is recorded as a
`boundary_disputed` *candidate* by `ppc_invariant_check.py`, not by the source
map, which is why the map's own count is 0. Each is enumerated with its source
site in §1 and in the relevant `findings.md`.

### Item 5 — every function in exactly one bucket, buckets sum to total — **PASS**

Both bucket tables re-derived for this report; both print `RECONCILES: yes`.
Counted totals are 173 and 146 against IDA's totals of 173 and 146. Full table
in §1.

Four bucket-6 entries carry an explicitly recorded disposition rather than a
source site — all four in Mesh, all four Objective-C, each characterised
individually in §4.2. **Sym8xx has none.** No entry in either driver is
unexamined.

### Item 6 — binrecon suite green — **PASS**, at 833 rather than the spec's 830

```
$ PYTHONPATH=tools/binrecon python -m pytest tools/binrecon/tests -q
833 passed, 4 skipped in 44.45s
```

**Spec §5 item 6 says 830 passed, 4 skipped, and that figure is stale.** It was
written before the two checker defects of §4.5 were found. Their fixes added
three regression tests — two in `151282da`
(`test_ha16_pairs_with_matching_register_not_nearest_lo16`,
`test_second_ha16_not_paired_with_preceding_lo16`) and one in `da51d92d`
(`test_objc_category_class_method_list_pointing_into_text_is_not_reported`) — so
830 + 3 = 833. The discrepancy against the spec is recorded here rather than
substituted silently; the observed figure is **833 passed, 4 skipped**.

`test_ppc_profile_inventory` passes and names **29** profiles, as spec §2.1
requires (`tools/binrecon/tests/test_profile.py:360-377`).

The one test known to be flaky,
`test_compare.py::test_mutation_during_later_section_reads_is_rejected`,
**passed on this run**; no retry was needed. It is unrelated to this work and
tracked separately.

### Item 7 — report carries all six parts, §5 names each spec with its gap — **PASS**

§1 Correspondence (spec §4.1), §2 Class inventory (§4.2), §3 Non-Objective-C
remainder (§4.3), §4 Findings (§4.4), §5 Decomposition proposal (§4.5), §6 The
`IOSCSIController` family (§4.6). §5 names two per-driver follow-on specs, each
with its measured mapped/unmapped counts, its bucket-6 residue after hand
resolution, a drift-versus-different-version assessment and its measured gap —
`drvPPCMesh` **4 Objective-C selectors**, `drvPPCSym8xx` **0**.

§3 states explicitly that buckets 1 and 2 are empty in both, with the reason
(statically linked kernel servers, no `__picsymbol_stub` section), and §4.7
restates it. §4.6 records the packaging gap: both sources build into the kernel
via `src/kernel-7/conf/files.ppc` under `mk_hasdrivers` (lines 107 and 135-138)
while both shipped artifacts are loadable kernel servers.

### Item 8 — family comparison covers all four, answers the missing-selector question — **PASS**

§6 covers `AppleMesh_SCSI`, `Sym8xxController`, `Apple96_SCSI` and
`AtapiController`, and answers spec §4.6's four questions in order. For the
missing-selector question it states, for each of the two measured here: **Mesh
0** and **Sym8xx 1** (`free`, with the cause established — `IOSCSIController`
implements it and our source agrees with the binary). `Apple96_SCSI` **0** and
`AtapiController` **4** are carried without re-measurement, with
`AtapiController`'s thinness characterised as Apple's own class factoring rather
than a reconstruction gap. Both derivations were run and the disagreement
disclosed. The section is bounded to the four questions, per spec §5.1.

### Not claimed

- **No PowerPC compile.** `parity_check.py` and `import_check.py` need a rebuilt
  binary and remain unusable. Nothing here is compile-verified, and no claim is
  made that either driver builds or runs.
- **No behavioural equivalence for mapped bodies.** The source maps match names,
  addresses and sizes, and this batch's bucket-5 confirmations are
  basic-block-shape only — no decompiler was available, so nothing here matches
  the byte-level check [report-network.md](report-network.md) §4.3 applied to
  Gem. §5's closing note states what that bounds.
- **No demonstrated runtime consequence.** Mesh's four divergences (§4.2) are
  referenced only from within `MESH_DBDMA.m`, so none breaks a call path. This
  batch has no equivalent of Gem's CRC finding.
- **`isCmdTimedOut` inlining is not confirmed** (§4.3), only judged likely.
- **The packaging gap is recorded, not closed** (§4.6).
- **`drvPPC53c96` and `drvPPCATA` were not re-measured** — §6 reads their
  selector sets from their `_reloc` symbol tables and their committed source
  maps, and cross-references [report.md](report.md) for everything else.
- **`Floppy` is not measured**, per spec §1.3.
