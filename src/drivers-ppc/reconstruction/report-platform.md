# PowerPC platform driver evidence base

Five in-tree PowerPC platform driver sources measured against Apple's shipped
Rhapsody binaries, per
[docs/superpowers/specs/2026-07-27-ppc-platform-driver-evidence-base-design.md](../../../docs/superpowers/specs/2026-07-27-ppc-platform-driver-evidence-base-design.md).

This report changes no driver source and no build wiring. It records what was
measured. Every number below comes from a command run for this report against
the published analyses, the checked-in source maps and the reference binaries;
the per-driver `findings.md` beside this file carries the evidence for each
cause attributed here.

It is a **fourth** report rather than an extension of [report.md](report.md)
(five drivers: `drvPPCCuda`, `drvPPC53c96`, `drvPPCATA`, `drvPPCBMac`,
`drvPPCBurgundy`), [report-network.md](report-network.md) (four network drivers
plus the `IOEthernet` family) or [report-scsi.md](report-scsi.md) (two SCSI
drivers plus the `IOSCSIController` family). Each was measured against a
different set of binaries with its own acceptance run. Section 6
cross-references [report.md](report.md) for `drvPPCBurgundy` and `drvPPCCuda`,
which are **not re-measured here**.

Sixteen drivers are now measured across the four reports.

**Two of this batch's five are `driverkit-3` framework code, not driver
projects.** `IOApplePCIBus` and `IODisplay` are both compiled from
`src/driverkit-3/libDriver/ppc`, a directory shared with the deferred
`IONDRVSupport`. Their measurement artifacts live here rather than under
`src/driverkit-3/libDriver/reconstruction/` so that all PowerPC measurement
stays in one place (spec 2.2). **The large "extra" selector sets those two
produce are sibling classes from that shared directory, not gaps** -- sections 3
and 4.5 state this with the per-class attribution, and it is the single likeliest
misreading of this report.

**What this does not establish.** No PowerPC toolchain exists in this
environment, so nothing here is compile-verified. These are structural
correspondences between our sources and Apple's binaries, not proof that any
driver builds or runs.

Reference artifacts are the ten Mach-O files under
`C:\Users\raynorpat\Downloads\test\Drivers\ppc`, five bundle stubs and five
kernel-server `_reloc` images. All ten sizes carried in the published analyses
match spec 1.1's table exactly, and each analysis's recorded SHA-256 identity is
tabulated in [Acceptance](#acceptance) item 1.

---

## 1. Correspondence

Summary table, re-derived for this report from
`tools/binrecon/out/<profile>/published/analysis-reference-ida.json` and each
`source-map.json`:

```
driver         total  mapped  unmap  dup  disp     mapB   unmapB
OHare              7       1      2    0     0      332       36
PMU               89      41      2    0     0     8168       36
Awacs            118      22     18    0     0     1812     3128
ApplePCIBus       52      24      2    0     0     3152       36
IODisplay         64      18      7    0     0     3420      636
```

`total` is IDA's total function count for the `_reloc` binary. `mapB`/`unmapB`
are mapped and unmapped bytes. **`duplicate_candidates` and `boundary_disputed`
are 0 for all five.**

The `unmapped` column separates the batch into three shapes:

- **OHare, PMU and ApplePCIBus each have exactly 2 unmapped, and in each case
  both are the build-generated accessors** (20 + 16 = 36 bytes, the same pair
  every driver measured across all four specs carries). Their real gap count on
  this axis is **zero**.
- **Awacs has 18**, of which **16 are underscore renames**, not missing code
  (4.1, 6.1), and 2 are the build-generated pair.
- **IODisplay has 7** -- the build-generated 2 plus **5 genuine gaps** (4.3). It
  is the only driver in this batch with any.

### Named / unnamed split

`--scope-to-objc` restricts each map to the binary's Objective-C methods, so the
named/unnamed split is what makes the rest of the binary countable:

```
driver         total  named  unnamed   objc  nonobjc
OHare              7      3        4      3        0
PMU               89     45       44     43        2
Awacs            118     51       67     40       11
ApplePCIBus       52     27       25     27        0
IODisplay         64     27       37     25        2
```

`objc` is the Objective-C-named function set; `nonobjc` is the named C functions
the map deliberately does not claim, which section 3 buckets by hand. `unnamed`
is bucket 3.

For four of the five, `objc` equals `mapped + unmapped` exactly. **`ApplePCIBus`
is the exception**: its `objc` is 27 against a `mapped + unmapped` of 26,
because `-[IOPCIBridge registerLoudly]` sits at address `0x0` and the
`--scope-to-objc` builder classifies it into none of the map's four categories
(4.6). `bucket_functions.py` recovers it into bucket 6.

### Row reconciliation

Each row reconciles as `mapped + bucket1..6 = total`. The `unmapped` column is
not a separate term: in OHare, PMU and ApplePCIBus it lands entirely in bucket
4; in Awacs its 16 renames land in bucket 6 and its build-generated 2 in bucket
4; in IODisplay its 5 real gaps land in bucket 6 and its 2 in bucket 4.

| Driver | mapped | b1 | b2 | b3 | b4 | b5 | b6 | sum | total |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OHare | 1 | 0 | 0 | 4 | 2 | 0 | 0 | 7 | 7 |
| PMU | 41 | 0 | 0 | 44 | 2 | 0 | 2 | 89 | 89 |
| Awacs | 22 | 0 | 0 | 67 | 2 | 0 | 27 | 118 | 118 |
| ApplePCIBus | 24 | 0 | 0 | 25 | 2 | 0 | 1 | 52 | 52 |
| IODisplay | 18 | 0 | 0 | 37 | 2 | 0 | 7 | 64 | 64 |

**All five print `RECONCILES: yes`.** Bucket 5 is 0 straight out of the
bucketing script by construction -- entries move into it by hand, per section 3.

### One symbol per `_reloc` sits at address 0x0

Each `_reloc` carries exactly one `__TEXT,__text` Objective-C symbol at address
`0x0`:

| Driver | Symbol at 0x0 | In IDA's function list? | Source site |
| --- | --- | --- | --- |
| OHare | `+[AppleOHare probe:]` | no | `ohare.m:35` |
| PMU | `+[ApplePMU probe:]` | no | `pmu.m:62` |
| Awacs | `+[PPCAwacs probe:]` | no | `PPCSound.m:227` |
| ApplePCIBus | `-[IOPCIBridge registerLoudly]` | **yes** (12 bytes) | none on `IOPCIBridge`; logic match on `IOMacRiscPCIBridge`, `IOMacRiscPCI.m:207` |
| IODisplay | `-[IOSmartDisplay registerLoudly]` | no | none, under any name |

> **CORRECTION.** This section originally continued: *"Address 0x0 is the Mach-O
> header/load-command region, not a code address in a relocatable object, so in
> four of five cases these are symbol-table entries with placeholder addresses"*,
> and called `ApplePCIBus` "the exception and a genuine anomaly". **All of that
> is withdrawn.** In a relocatable object `__TEXT,__text` begins at address 0, so
> address 0 is the *first instruction*, not a placeholder. Every one of these five
> symbols names real code: reading the reference binaries directly, `__text+0` is
> `7c0802a6` (`mflr r0`) in `drvPPCOHare_reloc`, `drvPPCBurgundy_reloc`,
> `drvPPCSym8xx_reloc`, `drvPPCMesh_reloc` and `drvPPC53c96_reloc`, and
> `9421ffe0` (`stwu r1,-32(r1)`, a leaf prologue) in `IODisplay_reloc`. The
> "Real IDA function?" column has been renamed to say what it actually measured:
> whether IDA's *analysis* lists a function there. `ApplePCIBus` is not the
> exception -- it is the one case where IDA happened to record the function.
>
> The misreading came from `ppc_invariant_check.py`'s message, "symbol X at 0x0
> is not a function start", which says nothing about the bytes, compounded by
> `read_macho` reporting address `0` for *undefined* symbols as well. The checker
> now distinguishes the two cases. Full account:
> [IOADBDevice/findings.md](IOADBDevice/findings.md), "The misreading".

None of the five overlaps any function in any bucket table or source map, so
none affects the correspondence numbers -- but that is because IDA never had
these functions to map, not because there is nothing there. Each is an
**unmapped real function**.

---

## 2. Class inventory

Module-owned classes, derived for this report from the `-[...]`/`+[...]` symbols
in each `_reloc` via `binrecon.macho.read_macho`, which -- unlike IDA's export --
preserves category tags:

| Driver | Binary classes (methods) | Source `@implementation` blocks |
| --- | --- | --- |
| OHare | `AppleOHare` (2) | `AppleOHare` -- `ohare.m:33` |
| PMU | `ApplePMU` (42) | `ApplePMU` -- `pmu.m:54` |
| Awacs | `PPCAwacs` (23) + `PPCAwacs(Private)` (16) | `PPCAwacs` -- `PPCSound.m:222`; `PPCAwacs (Private)` -- `PPCSoundPrivate.m:14` |
| ApplePCIBus | `IOPCIBridge` (9), `IOPCIDevice` (8), `IOMacRiscPCIBridge` (4), `IOGracklePCIBridge` (3), `IOMacRiscVCIBridge` (1) | all five in `IOMacRiscPCI.m` / `IOPCIDevice.m` |
| IODisplay | `IOSmartADBDisplay` (14), `IOSmartDisplay` (8), `IOSmartDDCDisplay` (2) | all three in `IOSmartDisplay.m` |

Each binary additionally carries `<Name>KernelServerInstance` and
`<Name>Version`, one method each -- the build-generated pair that populates
bucket 4 in all five (section 3), bringing the symbol totals to 4, 44, 41, 27
and 26.

**Only Awacs uses a category**, and it is the one this report's central finding
turns on. OHare and PMU are single-class, single-`@implementation` drivers. The
two `driverkit-3` binaries have no categories among their own classes at all.

### Two corrections to spec 1.2's class list

**`IOApplePCIBus` compiles five classes, not seven.** Spec 1.2 lists
`IODeviceTreeBus` and `IOTreeDevice` among its classes. Empirically neither is
in the binary: `IOApplePCIBus_reloc`'s symbol table carries
`.objc_class_name_IODeviceTreeBus` and `.objc_class_name_IOTreeDevice` only as
`binding: external, address: 0, section: None` -- *undefined* symbols this object
references but does not define. Not one compiled method of either class exists
in the `_reloc` or the bundle. Their 48 source selectors (17 + 31) are
absent from every shipped ppc driver binary in the reference tree, the
deferred `IONDRVSupport` included (section 3). Evidence:
[ApplePCIBus/findings.md](ApplePCIBus/findings.md), "Note on `IODeviceTreeBus`
and `IOTreeDevice` specifically".

**`IODisplay`'s three classes are confirmed as listed.**

### How the shared directory divides between the two binaries

`src/driverkit-3/libDriver/ppc` holds 24 `@implementation` blocks across 10
`.m` files, of which the two binaries measured here compile eight classes
between them. The split was obtained by joining each source map's mapped and
unmapped addresses back to the `_reloc` symbol table read by `read_macho`, then
grouping by class.

**`IOApplePCIBus`** -- 27 Objective-C symbols:

| Class | Mapped | Unmapped | At 0x0 | Binary total | Source defs |
| --- | --- | --- | --- | --- | --- |
| `IOPCIBridge` | 8 | 0 | 1 (`registerLoudly`) | 9 | 9 |
| `IOPCIDevice` | 8 | 0 | 0 | 8 | 9 |
| `IOMacRiscPCIBridge` | 4 | 0 | 0 | 4 | 5 |
| `IOGracklePCIBridge` | 3 | 0 | 0 | 3 | 3 |
| `IOMacRiscVCIBridge` | 1 | 0 | 0 | 1 | 1 |
| **subtotal** | **24** | **0** | **1** | **25** | **27** |
| build-generated | 0 | 2 | 0 | 2 | 0 |
| **Total** | **24** | **2** | **1** | **27** | **27** |

`IOPCIBridge`'s 9 and 9 are a coincidence of count, not of content: the binary's
ninth is `registerLoudly` at 0x0, the source's ninth is `match:key:location:`
(4.6). The two extra source defs are `-[IOPCIDevice getResources]` and
`-[IOPCIBridge match:key:location:]`; `IOMacRiscPCIBridge`'s fifth source def is
its own `registerLoudly`.

**`IODisplay`** -- 26 Objective-C symbols:

| Class | Mapped | Unmapped | At 0x0 | Binary total | Source defs |
| --- | --- | --- | --- | --- | --- |
| `IOSmartADBDisplay` | 10 | 4 | 0 | 14 | 10 |
| `IOSmartDisplay` | 6 | 1 | 1 (`registerLoudly`) | 8 | 6 |
| `IOSmartDDCDisplay` | 2 | 0 | 0 | 2 | 2 |
| **subtotal** | **18** | **5** | **1** | **24** | **18** |
| build-generated | 0 | 2 | 0 | 2 | 0 |
| **Total** | **18** | **7** | **1** | **26** | **18** |

**This is the only driver in the batch whose binary carries more of its own
methods than its source defines** -- 24 against 18. The 6-method shortfall is
exactly 4.3's finding: 4 on `IOSmartADBDisplay`, 2 on `IOSmartDisplay`.

Source-side per-class counts were read from `selector_check.py`'s own extra
lists (each binary's run reports the other's classes as extras), so the two
tasks cross-validate: `IOApplePCIBus`'s run reports 18 `IODisplay`-class extras
(6 + 10 + 2), and `IODisplay`'s reports 27 `IOApplePCIBus`-class extras
(9 + 9 + 5 + 3 + 1). Both match the "Source defs" columns above to the digit.

---

## 3. Non-Objective-C remainder

`--scope-to-objc` puts every non-Objective-C function outside the map. Left
alone that would read as coverage the map does not have, so every function IDA
found that the map does not cover is placed in exactly one of spec 3.4's six
buckets.

### Buckets 1 and 2 are empty across all five

**Bucket 1 (crt/dyld startup routines): 0 in all five. Bucket 2
(`__picsymbol_stub` entries): 0 in all five.** This is not an omission. Every
`_reloc` image here is a **statically linked kernel server, not an `MH_EXECUTE`
helper**: none carries `start`/`__start`/`__call_mod_init_funcs`/
`__dyld_init_check`/`dyld_stub_binding_helper`/`__dyld_func_lookup`, and none of
their analyses carries a `__picsymbol_stub` section for the stub-range check to
match against.

The crt/dyld routines do exist, but in the *bundle stubs*: all five bundle
analyses contain exactly two functions, `dyld_stub_binding_helper` (0xf04, 48
bytes) and `__dyld_func_lookup` (0xf34, 32 bytes), and no driver code at all. No
source map or bucket table was built for the stubs. This matches all eleven
binaries in the three previous reports; it is a property of the artifact shape,
not of any driver.

### Bucket 4 -- build-generated classes

Two entries in all five, identical in shape:

| Driver | Addresses | Symbols | Sizes |
| --- | --- | --- | --- |
| OHare | 0x1d8 / 0x1ec | `+[drvPPCOHareKernelServerInstance kernelServerInstance]` / `+[drvPPCOHareVersion driverKitVersionFordrvPPCOHare]` | 20 / 16 |
| PMU | 0x2424 / 0x2438 | `+[drvPPCPMUKernelServerInstance kernelServerInstance]` / `+[drvPPCPMUVersion driverKitVersionFordrvPPCPMU]` | 20 / 16 |
| Awacs | 0x1e58 / 0x1e6c | `+[PPCAwacsKernelServerInstance kernelServerInstance]` / `+[PPCAwacsVersion driverKitVersionForPPCAwacs]` | 20 / 16 |
| ApplePCIBus | 0xdec / 0xe00 | `+[IOApplePCIBusKernelServerInstance kernelServerInstance]` / `+[IOApplePCIBusVersion driverKitVersionForIOApplePCIBus]` | 20 / 16 |
| IODisplay | 0x1340 / 0x1354 | `+[IODisplayKernelServerInstance kernelServerInstance]` / `+[IODisplayVersion driverKitVersionForIODisplay]` | 20 / 16 |

These are DriverKit build-tooling output, not hand-written driver code.

### Buckets 3, 5 and 6 per driver

| Driver | b3 unnamed islands | b6 from script | to b5 by hand | b6 residue |
| --- | --- | --- | --- | --- |
| OHare | 4 | 0 | 0 | **0** |
| PMU | 44 | 2 | 2 | **0** |
| Awacs | 67 | 27 | 27 | **0** |
| ApplePCIBus | 25 | 1 | 1 (with caveat) | **0** |
| IODisplay | 37 | 7 | 1 | **6** |

**Four of five have no bucket-6 residue.** Bucket-5 moves are recorded with file
and line in each `findings.md`:

- [OHare](OHare/findings.md): nothing to move -- its bucket 6 is empty from the
  script, tied with `drvPPCCuda`'s ([Cuda/findings.md](Cuda/findings.md),
  `6-fn-no-source-site: 0`) for the smallest bucket-6 result of any driver
  measured in this project.
- [PMU](PMU/findings.md): `_gotInterruptCause` (`pmu.m:1533`) and
  `_timer_expired` (`pmu.m:1783`), both non-static C callbacks confirmed by
  basic-block structure -- 13 blocks against a 5-way `if`/`else if` chain, and 1
  block against a straight-line `msg_send_from_kernel` builder.
- [Awacs](Awacs/findings.md): 27 entries in two groups -- **11 non-static C
  helpers** with exact name matches, all declared in `PPCSound.h` and defined in
  `PPCSound.m`, and **16 renamed `PPCAwacs(Private)` methods** whose bodies
  exist at cited `PPCSoundPrivate.m` lines but under an underscore-prefixed
  selector (4.1).
- [ApplePCIBus](ApplePCIBus/findings.md): `-[IOPCIBridge registerLoudly]`
  (0x0, 12 bytes) -- moved with an explicit caveat. Its compiled body is
  `stwu; addi; blr`, with no instruction that clears or reloads `r3`, so it
  returns `self`. That matches `-[IOMacRiscPCIBridge registerLoudly]`'s
  `return (self)` (`IOMacRiscPCI.m:207`) and not `-[IODeviceTreeBus
  registerLoudly]`'s `return (nil)` (`IODeviceTreeBus.m:701`). **A logic match
  with a class attribution that does not line up** (4.6), recorded as
  resolved-with-caveat rather than folded silently into bucket 5.
- [IODisplay](IODisplay/findings.md): `_SMADBHandler` (`IOSmartDisplay.m:430`)
  alone moves. **The other 6 do not** -- see below.

**IODisplay's 6-entry bucket-6 residue is the only unresolved set in this
batch**: `+[IOSmartDisplay probe:]` (60 bytes), `_UnpackString` (232),
`-[IOSmartADBDisplay findADBDisplayInfoForType:]` (324),
`-[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]` (44),
`-[IOSmartADBDisplay IOSMADBGetLogicalRegister:size:result:size:]` (104) and
`-[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]` (68). Each was grepped
for individually across the whole shared directory and found nowhere, under any
name, spelling or declaration. Section 4.3 characterises them.

**Awacs's and PMU's bucket-5 confirmations are basic-block-shape only, not
instruction-level.** No decompiler was available in this session, so none of
this batch got the byte-level treatment [report-network.md](report-network.md)
4.3 gave Gem's `_mace_crc`. That bound is restated in section 5.

### Merged `selector_check.py` output

Per driver, re-run for this report against the `_reloc` binary and the source
directory named in spec 1.2:

| Driver | ref selectors | our defs | renames | duplicates | missing | extra | exit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| OHare | 4 | 2 | 0 | 0 | 2 | 0 | 0 |
| PMU | 44 | 43 | 0 | 0 | 2 | 1 | 0 |
| Awacs | 41 | 39 | **16** | 0 | 2 | 0 | 1 |
| ApplePCIBus | 27 | 237 | 0 | 0 | 3 | **213** | 0 |
| IODisplay | 26 | 237 | 0 | 0 | 8 | **219** | 0 |

**Zero duplicates in all five.** Exact-name match rate
(`ref - missing - renames`, over `ref`):

| Driver | matched | of | rate |
| --- | --- | --- | --- |
| OHare | 2 | 4 | 50.0% |
| PMU | 42 | 44 | 95.5% |
| Awacs | 23 | 41 | 56.1% |
| ApplePCIBus | 24 | 27 | 88.9% |
| IODisplay | 18 | 26 | 69.2% |

As the three previous reports established, **match rate does not by itself rank
the work**, and this batch is the clearest case yet. OHare's 50% is 2 of 4 on a
driver with *zero* real gaps (4.2). Awacs's 56.1% is 16 renames of a documented
convention (4.1). IODisplay's 69.2% is the only rate here that reflects
genuinely absent code. Section 5 ranks on cause, not rate.

### The 213 and 219 extras are sibling classes, not gaps

`src/driverkit-3/libDriver/ppc` is one source directory shared by three
binaries: `IOApplePCIBus`, `IODisplay`, and the deferred `IONDRVSupport`.
`--scope-to-objc` source maps only ever claim their own binary's classes, but
`selector_check.py` scans the whole directory, so it reports every method
definition belonging to the other two binaries as "extra".

**None of the 213 or the 219 is a gap in either driver.** Every extra was
grouped by class and each class checked with `read_macho` against both sibling
`_reloc` symbol tables:

| Run | Sibling-attributed | Not sibling-attributed | Same-class anomalies | Total |
| --- | --- | --- | --- | --- |
| `IOApplePCIBus` | **18** (`IODisplay`'s three classes: 6 + 10 + 2) | **192** | 3 | 213 |
| `IODisplay` | **27** (`IOApplePCIBus`'s five classes: 9 + 9 + 5 + 3 + 1) | **192** | 0 | 219 |

**Both runs report the identical 192 non-sibling selectors**, across
the identical class list -- `IOFramebuffer` (55), `IONDRVFramebuffer` (26) and
`IONDRVFramebuffer(ProgramDAC)` (6), `IOTreeDevice` (31), `IODeviceTreeBus`
(17), `IOPropertyTable` (14), `IOOFFramebuffer` (11), `IOIX3DNDRV` (9),
`IOATIMACH64NDRV` (8), `IOIXMNDRV` (8), `IODirectDevice(PPCPrivate)` (2),
`IORootDevice` (2), `IOATINDRV` (1), `IOATIRAGE128NDRV` (1),
`IOPPCDeviceDescription` (1). Each was confirmed **absent from both**
`IOApplePCIBus_reloc` and `IODisplay_reloc` by symbol table, not by name
guessing. 55+26+6+31+17+14+11+9+8+8+2+2+1+1+1 = 192.

**Absence from the two measured binaries is not presence in `IONDRVSupport`
-- that destination was never checked before this report.** Every Mach-O in
the shipped `ppc` reference tree (73 files; 26 carry compiled Objective-C
methods) was scanned by symbol table for these 192 selectors, and the
destination splits 58/134:

- **58 are defined in `IONDRVSupport_reloc`** and nowhere else --
  `IOOFFramebuffer` (11 of 11), `IOIX3DNDRV` (9 of 9), `IOIXMNDRV` (8 of 8),
  `IOATINDRV` (1 of 1), `IONDRVFramebuffer` (24 of 26) and
  `IONDRVFramebuffer(ProgramDAC)` (5 of 6).
- **134 are absent from every shipped ppc binary, `IONDRVSupport_reloc`
  included.** 131 of those sit on nine classes no shipped ppc binary defines
  at all: `IOFramebuffer` (55), `IOTreeDevice` (31), `IODeviceTreeBus` (17),
  `IOPropertyTable` (14), `IOATIMACH64NDRV` (8), `IODirectDevice(PPCPrivate)`
  (2), `IORootDevice` (2), `IOATIRAGE128NDRV` (1), `IOPPCDeviceDescription`
  (1). The remaining 3 are selector-level absences on otherwise-present
  classes: `IONDRVFramebuffer` (2 of 26) and `IONDRVFramebuffer(ProgramDAC)`
  (1 of 6).

58 + 134 = 192. 4.5 states the 131-selector remainder as a finding of its own.

The two sibling figures cross-validate: 18 + 192 + 3 = 213, and
27 + 192 + 0 = 219. `IOApplePCIBus`'s three same-class anomalies are
`-[IOMacRiscPCIBridge registerLoudly]` (the class-attribution case, 4.6) and
two confirmed-in-source but absent-from-binary trivial `[super ...]` overrides,
`-[IOPCIBridge match:key:location:]` (`IOMacRiscPCI.m:133`) and
`-[IOPCIDevice getResources]` (`IOPCIDevice.m:121`).

Without this attribution, a 213-selector extra list against a 24-method mapped
driver reads as near-total reconstruction failure. **It is not.** Evidence:
[ApplePCIBus/findings.md](ApplePCIBus/findings.md) and
[IODisplay/findings.md](IODisplay/findings.md), each "Attributing all N extras"
and "Shared source directory".

### Symbol / function-start mismatches

`ppc_invariant_check.py` reports one per artifact for nine of the ten;
`applepcibus-ppc` reports none. None is a relocation-decode defect (see
[Acceptance](#acceptance) item 2), and none overlaps any function in any bucket
table or source map, so none affects the correspondence numbers. The four
`_reloc` symbols are tabulated in section 1; all five bundle stubs report
`__mh_bundle_header`, the standard synthetic bundle-header symbol, which is not
a function at all.

---

## 4. Findings

### 4.1 The underscore convention isn't a `drvPPCBurgundy` one-off -- `PPCAwacs` shares it

**This is the question the spec was written to answer: does `PPCAwacs` share
`drvPPCBurgundy`'s private-selector renaming convention? It does.**

`selector_check.py` on `PPCAwacs` against
`src/drivers-ppc/sound/drvPPCAwacs/PPCAwacs.drvproj/PPCAwacs.lksproj`, re-run
for this report:

```
reference selectors: 41
our definitions:     39

renames (16):
    -[PPCAwacs(Private) _addAudioBuffer:Length:Interrupt:Output:] PPCSoundPrivate.m:20
    -[PPCAwacs(Private) _allocateDMAMemory]                    PPCSoundPrivate.m:119
    -[PPCAwacs(Private) _checkHeadphonesInstalled]             PPCSoundPrivate.m:208
    -[PPCAwacs(Private) _getInputSrc]                          PPCSoundPrivate.m:288
    -[PPCAwacs(Private) _getInputVol:]                         PPCSoundPrivate.m:297
    -[PPCAwacs(Private) _getOutputVol:]                        PPCSoundPrivate.m:318
    -[PPCAwacs(Private) _getRate]                              PPCSoundPrivate.m:339
    -[PPCAwacs(Private) _loopAudio:]                           PPCSoundPrivate.m:349
    -[PPCAwacs(Private) _resetAudio:]                          PPCSoundPrivate.m:414
    -[PPCAwacs(Private) _resetAwacs]                           PPCSoundPrivate.m:477
    -[PPCAwacs(Private) _setInputSource:]                      PPCSoundPrivate.m:549
    -[PPCAwacs(Private) _setInputVol:]                         PPCSoundPrivate.m:576
    -[PPCAwacs(Private) _setOutputMute:]                       PPCSoundPrivate.m:594
    -[PPCAwacs(Private) _setOutputVol:]                        PPCSoundPrivate.m:617
    -[PPCAwacs(Private) _setRate:]                             PPCSoundPrivate.m:645
    -[PPCAwacs(Private) _startIO:]                             PPCSoundPrivate.m:679

duplicates (0):

missing (2):
    +[PPCAwacsKernelServerInstance kernelServerInstance]
    +[PPCAwacsVersion driverKitVersionForPPCAwacs]

extra (0):
exit=1
```

**41 reference / 39 ours, 16 renames, 0 duplicates, 2 missing, 0 extra.** The
arithmetic: **23 exact + 16 renamed + 2 missing = 41 reference selectors**, and
23 exact + 16 renamed + 0 extra = 39 our definitions.

Every one of the 16 is the same transformation in the same direction:
`PPCAwacs(Private) _<name>` in source against a bare `<name>` in Apple's binary.
**`drvPPCBurgundy` renamed 16 of 16 the same way** -- 21 exact + 16 renamed + 3
missing = 40 reference selectors ([report.md](report.md);
[Burgundy/findings.md](Burgundy/findings.md), "Selector check"), and its 16 are
`PPCBurgundy(Private) _<name>` at cited `BurgundySoundPrivate.m` lines.

The two RhapsodiOS `IOAudio` reimplementations apply the same convention
at the same 16-of-16 rate, and **neither has any unexplained missing
selector beyond the build-generated accessors** -- Awacs's missing list is
exactly the two tool-emitted accessors, and Burgundy's is those two plus
`probe:`, which Awacs implements under its exact reference name
(`PPCSound.m:227`). **Not a one-off.** Section 6.1 states the consequence.

Evidence: [Awacs/findings.md](Awacs/findings.md), "Selector check" and
"Reimplementation note"; [Burgundy/findings.md](Burgundy/findings.md),
"Selector check".

**A third correction to the spec's numbers.** The spec described `PPCAwacs`
as having "17 of its 38 method definitions underscore-prefixed"; the
measurement above gives 39 definitions and 16 renames. The 17th
underscore-prefixed method is `-[PPCAwacs _interruptOccurred]`
(`PPCSound.m:346`, declared `PPCSound.h:108`) -- an `IOAudio` superclass
override that calls `[super _interruptOccurred]`, whose selector matches
Apple's reference exactly, so it is correctly not counted as a rename. This
sharpens the finding: the convention is "underscore our own privates", not
blanket prefixing.

### 4.2 OHare's one-method gap: spec 1.2 guessed wrong, and so did this section

Spec 1.2 wrote that `drvPPCOHare`'s binary "carries **two** real methods,
`+[AppleOHare probe:]` and `-[AppleOHare initFromDeviceDescription:]`, and
`ohare.m` appears to define only the first. If that holds, it is a one-method
driver with a one-method gap."

**It does not hold.** Re-read for this report, `ohare.m` defines both:

```
ohare.m:35   + (BOOL)probe:(IOPCIDevice *)deviceDescription
ohare.m:45   - initFromDeviceDescription:(IOPCIDevice *)deviceDescription
```

`selector_check.py` independently gives "our definitions: 2" and **`extra (0)`**
-- both source selectors have an exact-name match in the binary -- with a
`missing` list containing nothing but the two build-generated accessors.

The reason only 1 of the 2 appears as `mapped` is unrelated to source:
**`+[AppleOHare probe:]` sits at address `0x0`**, which is not a function start
in the reference analysis (its 7-entry function list carries no entry at 0), so
IDA records no function for it and nothing can map to it. Its selector matches
exactly, and `ohare.m:35-42` defines a method of that name.

> **CORRECTION.** This section originally concluded that "the guessed one-method
> gap does not exist" and that OHare has **zero real gaps**. That conclusion
> rested on the address-0 symbol being a placeholder, which section 1's
> correction withdraws. `+[AppleOHare probe:]` is real code at `__text+0` that
> IDA's analysis omits, so `drvPPCOHare` has **one real unmapped function**, not
> zero. What survives is the narrower point spec 1.2 got wrong: `ohare.m` does
> define both methods, and the selector check confirms it. What does *not*
> survive is the claim that the correspondence for `probe:` was therefore
> settled. It is **unverified**, because nothing has compared `ohare.m:35-42`
> against the 92 bytes Apple shipped.

Evidence: [OHare/findings.md](OHare/findings.md), "Correspondence" and "Selector
check".

### 4.3 `IODisplay` is the only driver in this batch with genuine unresolved gaps

Six of its seven bucket-6 entries were found **nowhere** in
`src/driverkit-3/libDriver/ppc` after exhaustive grepping, and each was checked
individually:

| Entry | Size | What the grep found |
| --- | --- | --- |
| `+[IOSmartDisplay probe:]` | 60 | No `probe:` definition anywhere in the directory for this class. `IOSmartDisplay`'s block (`IOSmartDisplay.m:108-171`) defines six other methods. |
| `_UnpackString` | 232 | Case-insensitive grep for `unpack` hits only `UnpackFullSection`, `UnpackPartialSection`, `PEF_UnpackSection` in the PEF loader -- unrelated. No `UnpackString` of any kind. |
| `-[IOSmartADBDisplay findADBDisplayInfoForType:]` | 324 | No definition, not even a declaration. |
| `-[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]` | 44 | No match anywhere. |
| `-[IOSmartADBDisplay IOSMADBGetLogicalRegister:size:result:size:]` | 104 | No match. Distinct from the present, mapped `getLogicalRegister:data:` (`IOSmartDisplay.m:486`). |
| `-[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]` | 68 | No match. Distinct from the present, mapped `setLogicalRegister:data:` (`IOSmartDisplay.m:463`). |

A seventh unresolved item sits outside the bucket table:
`-[IOSmartDisplay registerLoudly]` at address 0x0, also absent from source under
any name -- the directory's only two `registerLoudly` definitions are on
`IOMacRiscPCIBridge` and `IODeviceTreeBus`, and `IOSmartDisplay` derives
directly from `Object`, subclassing neither.

**Every other driver in this batch resolved to zero bucket-6 residue.** This one
resolved 1 of 7.

`IODisplay` also has **0 renames** -- the underscore convention of 4.1 does not
apply here, and there is no `2025 RhapsodiOS Project` copyright anywhere in
`src/driverkit-3/libDriver/ppc`. That is consistent with this being **Apple's
own original source rather than a reimplementation**, which makes the six
absences a different kind of finding from Awacs's sixteen renames: not a
deliberate convention, but code Apple shipped that this tree does not have.

Evidence: [IODisplay/findings.md](IODisplay/findings.md), "Buckets", "Unmapped
detail" and "Invariant check".

### 4.4 `ApplePMU`'s one extra selector is a protocol stub `AppleCuda` also carries

`selector_check.py` on `drvPPCPMU_reloc` reports exactly one extra:

```
extra (1):
    -[ApplePMU ADBSetFileServerMode:::]
```

It is declared as a required method of `@protocol ADBservice` (`pmu.h:99-101`)
and defined at `pmu.m:576-582` as a one-line stub returning `kPMUNotSupported`.
`pmu.h:51` documents why on the status enum itself:
`kPMUNotSupported = 3, // PMU don't do that (Cuda does, though)`. The selector
has **no** entry anywhere in `drvPPCPMU_reloc`'s 44-symbol Objective-C table, at
any arity.

**`AppleCuda`'s committed findings recorded the same odd selector as an extra**
-- [Cuda/findings.md](Cuda/findings.md), "Selector check":

```
extra (2):
    -[AppleCuda ADBSetFileServerMode:::]
    -[AppleCuda setPowerupTime::::]
```

Two drivers, the same protocol, the same source-only stub, and neither of
Apple's shipped binaries emits it. This is a **source-side** divergence -- the
opposite direction from every gap in 4.3 -- and it is the only selector in the
`ADBservice` contract that neither implementation ships. Section 6.2 carries it.
Evidence: [PMU/findings.md](PMU/findings.md), "Selector check" and "Protocol
selectors"; [Cuda/findings.md](Cuda/findings.md), "Selector check".

### 4.5 The shared `driverkit-3` directory's extras are sibling classes, not gaps

Stated in full in section 3 rather than buried. **213 extras for
`IOApplePCIBus`, 219 for `IODisplay`, all attributed.** 192 are shared in both
cases -- the identical 192 selectors across the identical class list, confirmed
absent from both sibling `_reloc` symbol tables -- and split 58 in
`IONDRVSupport_reloc` / 134 in no shipped ppc binary at all. The remainder is
attributed to each other: 18 and 27, cross-validated between the two tasks
against each binary's own symbol table.

**These are not gaps.** They are the arithmetic consequence of running a
whole-directory selector scan against one binary out of three that the directory
builds. The three residual same-class anomalies in `IOApplePCIBus`'s run are
named in sections 3 and 4.6; `IODisplay`'s run has none.

**The 131-selector remainder is a finding in its own right.** Nine classes --
`IOFramebuffer`, `IOTreeDevice`, `IODeviceTreeBus`, `IOPropertyTable`,
`IOATIMACH64NDRV`, `IODirectDevice(PPCPrivate)`, `IORootDevice`,
`IOATIRAGE128NDRV`, `IOPPCDeviceDescription` -- have source in this shared
directory but no shipped ppc binary in the reference tree, `IONDRVSupport`
included, compiles a single method of any of them. That is consistent with
this surface being kernel-resident DriverKit that never shipped as a
standalone ppc driver binary here, not with a gap in either measured driver:
the direction of measurement is source against binary, so it cannot be
missing code in `IOApplePCIBus` or `IODisplay`.

Spec 5.1 named mischaracterising these as gaps the likeliest error in the batch.
It is recorded here as a finding precisely so the number cannot be quoted
without its attribution.

### 4.6 `ApplePCIBus`'s address-0x0 symbol is the *normal* case, not the exception

Across sixteen drivers measured in four specs, every binary carries exactly one
`__TEXT,__text` symbol at address `0x0`, and in every case but one IDA's
analysis lists **no** function there. This report re-verified that disposition
firsthand for its own ten artifacts, five `_reloc` and five bundle stubs
(Acceptance item 2); the other six are carried forward from the three prior
reports and were not re-verified here.

> **CORRECTION.** This section originally called the address-0 symbol "a
> symbol-table entry with a placeholder address" and `IOApplePCIBus_reloc` "the
> exception". Both are withdrawn; see section 1's correction. Address 0 is
> `__text`'s first address, every one of these symbols names real code, and
> `IOApplePCIBus_reloc` differs only in that IDA recorded the function. The
> "exception" is IDA's analysis being complete for one binary, not Apple's
> binary being unusual.

**`IOApplePCIBus_reloc` is the exception.** `-[IOPCIBridge registerLoudly]` sits
at address 0 *and* is a real 12-byte IDA function with three instructions
(`stwu`, `addi`, `blr`). The consequence is visible in the invariant check:

```
=== applepcibus-ppc ===
10 scattered/difference-form relocations (target section verified, field is a difference, not an address)
5 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
457 fused relocations, 0 violations
```

**0 violations, and an exit code of 0** -- alone among the ten artifacts --
because `check_functions` has no symbol/function-start mismatch to flag.

Two further consequences, both recorded rather than smoothed over. First, the
`--scope-to-objc` builder classifies it into none of the map's four categories,
which is why `ApplePCIBus` is the only driver whose Objective-C function count
(27) exceeds `mapped + unmapped` (26); `bucket_functions.py` recovers it into
bucket 6. Second, its class attribution does not line up: `IOPCIBridge`'s own
`@implementation` block (`IOMacRiscPCI.m:71-204`) does not define
`registerLoudly` at all, while `IOMacRiscPCIBridge` -- its direct subclass --
defines a body whose logic matches (`return (self)`, `IOMacRiscPCI.m:207`), and
`IODeviceTreeBus` defines one whose logic does not (`return (nil)`,
`IODeviceTreeBus.m:701`). **A logic match without a class-name match.** It
surfaces once from the binary side (bucket 6, `-[IOPCIBridge registerLoudly]`)
and once from the source side (`selector_check.py` extra,
`-[IOMacRiscPCIBridge registerLoudly]`) -- one discrepancy seen from two
directions, not two. Evidence:
[ApplePCIBus/findings.md](ApplePCIBus/findings.md), "Buckets" and "Invariant
check".

### 4.7 The packaging gap

Re-read from `src/kernel-7/conf/files.ppc` for this report:

```
84:bsd/dev/ppc/drvPMU/pmu.m		optional mk_hasdrivers
94:bsd/dev/ppc/drvOHare/ohare.m		optional mk_hasdrivers
```

So the batch has **three** different in-tree build shapes:

- **`drvOHare` and `drvPMU`** build into the kernel binary whenever
  `mk_hasdrivers` is set (lines 94 and 84), not as standalone targets.
- **`PPCAwacs`** is a loadable-driver project --
  `PPCAwacs.drvproj/PPCAwacs.lksproj` with its own `Makefile`,
  `Makefile.preamble`, `PB.project` and `Load_Commands.sect`. It appears
  nowhere in `files.ppc`.
- **`IOApplePCIBus` and `IODisplay`** are `driverkit-3` framework code in
  `src/driverkit-3/libDriver/ppc`, likewise absent from `files.ppc`, and share
  that directory with each other and with the deferred `IONDRVSupport`.

**All five shipped artifacts are loadable kernel servers** -- each a
`<name>.config` bundle carrying a bundle stub plus a `_reloc` kernel-server
image (spec 1.1, and the ten identities in [Acceptance](#acceptance) item 1).

So two of the five are wired to build one way and shipped another, and three are
not wired as driver targets at all. This is the same divergence
[report-network.md](report-network.md) 4.6 recorded for `drvMaceEnet` and
`drvDECchip21040` and [report-scsi.md](report-scsi.md) 4.6 for `drvPPCMesh` and
`drvPPCSym8xx`, and this spec does not close it either: **recorded and
deferred** to the per-driver specs, per spec 1.3. Nothing in sections 1-3
depends on it, because the measurement compares compiled function bodies, which
are the same either way. Evidence: [OHare/findings.md](OHare/findings.md) and
[PMU/findings.md](PMU/findings.md), each opening section;
[ApplePCIBus/findings.md](ApplePCIBus/findings.md) and
[IODisplay/findings.md](IODisplay/findings.md), each "Shared source directory".

### 4.8 Buckets 1 and 2 are empty across all five

Stated in full in section 3 rather than omitted. Both are 0 in all five `_reloc`
binaries because these are **statically linked kernel servers, not `MH_EXECUTE`
helpers**: no crt/dyld startup routines, and no `__picsymbol_stub` section for
the stub-range check to match against. The crt/dyld routines live in the bundle
stubs instead, two per stub, identical in address and size across all five. This
matches all eleven binaries in the three previous reports.

---

## 5. Decomposition proposal

Ranked by **actionable divergence with runtime consequence** -- the criterion the
three previous reports settled on. The tie-breaker is that an unmapped or
bucket-6 entry with a documented, evidenced cause and no unexplained content is
**a result, not work**.

On that criterion the ordering is not the match-rate ordering. `IODisplay` ranks
first at 69.2% while `drvPPCOHare` ranks last at 50.0%, because IODisplay is the
only driver here with code it cannot account for and OHare's shortfall is
entirely its address-0x0 function. **Per section 1's correction that shortfall is
real code, not an artifact**, so this ordering is weaker than it reads: OHare's
92 bytes at `__text+0` are unaccounted for too, just by a source-side name
match rather than by nothing.

### 1. `IODisplay` -- six unresolved absences, the only unexplained content in the batch

- **Measured:** 18 mapped / 7 unmapped / 0 dup / 0 disputed; 3420 mapped bytes
  against 636 unmapped. 64 functions.
- **Exact-name match: 18 of 26 (69.2%)**.
- **Bucket 6 after hand resolution: 6** -- one C function and five Objective-C
  methods, each grepped for individually across the whole shared directory and
  found nowhere (4.3), plus `-[IOSmartDisplay registerLoudly]` at 0x0, also
  absent from source.
- **Drift or different version?** A **different version**, and in the direction
  that matters least comfortably: Apple's binary has **more** of this driver's
  own methods than our source defines -- 24 against 18 (section 2). The
  `IOSMADB*` family is a coherent group with a distinct argument shape (`:size:`
  result buffers) from the `getLogicalRegister:data:`/`setLogicalRegister:data:`
  pair our source does have, so it reads as an entry-point layer our tree
  predates or dropped, not as scattered loss.
- **The follow-on spec's job:** decide, per absence, whether to write the
  missing entry point or record it as intentionally unimplemented. `probe:` is
  the one with an obvious runtime shape -- a DriverKit class with no `+probe:`
  cannot be instantiated by the driver-loading path -- but this analysis did not
  demonstrate a break, only the absence. Also the packaging question (4.7): this
  is framework code sharing a directory with two other binaries, so "building
  `IODisplay`" is not a well-defined target today. Its measured gap is **6 entry
  points present in Apple's binary and absent from our source under any name**,
  plus 1 address-0x0 symbol likewise absent.
- **What is a result, not work:** the 2 build-generated accessors, the 37
  unnamed jump islands, `_SMADBHandler` resolved to bucket 5, and **all 219
  extras** (4.5) -- 27 sibling `IOApplePCIBus` selectors and 192 deferred
  `IONDRVSupport` selectors, none of them this driver's business.

### 2. `PPCAwacs` -- sixteen renames, a documented convention with a known consequence

- **Measured:** 22 mapped / 18 unmapped / 0 dup / 0 disputed; 1812 mapped bytes
  against 3128 unmapped. 118 functions.
- **Exact-name match: 23 of 41 (56.1%)**.
- **Bucket 6 after hand resolution: 0** -- all 27 entries have confirmed source
  sites (11 C helpers by exact name, 16 renamed private methods at cited lines).
- **Drift or different version?** **Neither.** This is a RhapsodiOS
  reimplementation (`PPCSound.m` carries both `Copyright (c) 1999 Apple
  Computer, Inc.` and `Copyright (c) 2025 RhapsodiOS Project`) applying a
  deliberate naming rule, confirmed by section 6.1 to also hold for
  `drvPPCBurgundy`.
- **The follow-on spec's job:** decide whether to keep the underscore prefix or
  restore Apple's selectors -- **the same decision `drvPPCBurgundy`'s follow-on
  faces, and it should be made once for both** (6.1). The runtime consequence is
  real and identical in shape: Objective-C dispatches on the exact selector
  string, so a message send to `resetAwacs` does not resolve against a class
  that defines only `_resetAwacs`. Whether anything outside the class sends
  those messages was **not** measured here; the private-category placement
  suggests not, but that is an assumption, not a result. Its measured gap is **0
  selectors absent under any name** -- every reference selector but the two
  tool-emitted accessors has a body in source.
- **What is a result, not work:** the 2 build-generated accessors, the 67
  unnamed jump islands, the 11 C helpers, and `+[PPCAwacs probe:]` at 0x0
  (present in source at `PPCSound.m:227` under its exact reference name).

### 3. `IOApplePCIBus` -- one class-attribution anomaly and two source-only overrides

- **Measured:** 24 mapped / 2 unmapped / 0 dup / 0 disputed; 3152 mapped bytes
  against 36 unmapped. 52 functions.
- **Exact-name match: 24 of 27 (88.9%)**.
- **Bucket 6 after hand resolution: 0**, with one caveat recorded (4.6).
- **Drift or different version?** **Drift, and small.** The `registerLoudly`
  body matches by logic on the wrong class, and the two extras are minimal
  `[super ...]`-only overrides -- a pattern consistent with dead-stripping of a
  zero-behaviour-change override during Apple's original build, which this
  static analysis can neither confirm nor rule out.
- **The follow-on spec's job:** three small decisions -- whether
  `registerLoudly` belongs on `IOPCIBridge` or `IOMacRiscPCIBridge`, and whether
  to keep or delete `-[IOPCIBridge match:key:location:]` and `-[IOPCIDevice
  getResources]`. Plus the packaging question (4.7). Its measured gap is **0
  selectors absent from source**; its three anomalies all run source-to-binary,
  not binary-to-source.
- **What is a result, not work:** the 2 build-generated accessors, the 25
  unnamed jump islands, **all 213 extras** (4.5), and the address-0x0
  `registerLoudly` function itself, which is fully characterised.

### 4. `drvPPCPMU` -- one source-only protocol stub

- **Measured:** 41 mapped / 2 unmapped / 0 dup / 0 disputed; 8168 mapped bytes
  against 36 unmapped. 89 functions.
- **Exact-name match: 42 of 44 (95.5%)** -- the highest in the batch.
- **Bucket 6 after hand resolution: 0**.
- **Drift or different version?** **Neither observable.** 0 renames, 0
  duplicates, and 42 of 43 source methods have exact binary counterparts.
- **The follow-on spec's job:** packaging (4.7, `files.ppc:84`) and one decision
  on `-[ApplePMU ADBSetFileServerMode:::]` -- keep the protocol-required
  `kPMUNotSupported` stub or drop it, noting `AppleCuda` carries the identical
  source-only stub (4.4, 6.2). Its measured gap is **0 binary selectors absent
  from source**.
- **What is a result, not work:** the 2 build-generated accessors, the 44
  unnamed jump islands, the 2 C callbacks resolved to bucket 5, and
  `+[ApplePMU probe:]` at 0x0.

### 5. `drvPPCOHare` -- nothing on correspondence grounds

- **Measured:** 1 mapped / 2 unmapped / 0 dup / 0 disputed; 332 mapped bytes
  against 36 unmapped. 7 functions.
- **Exact-name match: 2 of 4 (50.0%)** -- the lowest rate in the batch and the
  least meaningful, since the denominator is 4 (section 3).
- **Bucket 6 from the script: 0.** Nothing to resolve by hand at all -- tied
  with `drvPPCCuda` ([Cuda/findings.md](Cuda/findings.md),
  `6-fn-no-source-site: 0`) for the smallest bucket-6 result straight out of
  the script of any driver measured in this project. OHare is still the
  smallest measurement of the two by function count (7 against Cuda's 100).
- **Drift or different version?** **Neither.** Both source methods have
  exact-name binary counterparts; `extra` is empty and `missing` contains only
  the two tool-emitted accessors.
- **The follow-on spec's job:** packaging only (4.7, `files.ppc:94`). Nothing on
  correspondence grounds. Its measured gap is **0 selectors**. Worth a spec of
  its own only for a compile attempt once a PowerPC toolchain exists.
- **What is a result, not work:** the 2 build-generated accessors, the 4 unnamed
  jump islands, and `+[AppleOHare probe:]` at 0x0 -- the entire non-mapped
  remainder of the binary.

### The limit of this ranking

**Nothing in this method systematically checks method bodies for behavioural
equivalence.** The source maps match names, addresses and sizes, and this
batch's bucket-5 confirmations are basic-block-shape only (section 3), weaker
than the byte-level disassembly [report-network.md](report-network.md) 4.3 and
4.4 used. OHare's and PMU's clean correspondence bounds their *structure*, not
their behaviour, and no mapped body in this batch was compared
instruction-for-instruction against source. A per-driver spec for any of the
five should assume body-level divergence is possible until a compile-and-compare
exists.

**No finding in this batch demonstrates a runtime break.** Awacs's renames have
a *known mechanism* for one (exact-selector dispatch) but no measured caller was
found; IODisplay's absences are unexplained content, not a demonstrated failure.
Neither reaches the bar [report-network.md](report-network.md) 4.3 set with Gem's
CRC, which changed the hash bucket actually programmed on 5 of 5 vectors.

### Recorded follow-on questions, not chased

Per spec 5.1 and 6 these are recorded and left alone:

- Whether anything outside `PPCAwacs` or `PPCBurgundy` sends the sixteen renamed
  selectors. Not measured.
- Whether Apple's `IOSMADB*` family (4.3) is a later or an earlier entry-point
  layer than our `getLogicalRegister:data:` pair. The binary cannot say.
- Why `-[IOPCIBridge match:key:location:]` and `-[IOPCIDevice getResources]` are
  in source but not in the binary. Dead-stripping is plausible and unconfirmed.
- Why `IOApplePCIBus_reloc` references `IODeviceTreeBus` and `IOTreeDevice` as
  undefined externals while compiling neither (section 2).
- **`PPCSerialPort` and `IONDRVSupport`**, deferred behind the glue-stub naming
  work, and the residual comment-block scanner case at `IOFramebuffer.m:753`
  that additionally blocks `IONDRVSupport`. The naming work remains the
  highest-value tooling item, and is the reason all five bucket tables above are
  hand-resolved (spec 6).
- **`IOADBDevice` + `adbservd`** -- greenfield; no in-tree source, and `adbservd`
  has 0 Objective-C methods so `--scope-to-objc` would map nothing.

---

## 6. Two pairings

Thinner than the preceding reports' family sections -- **two pairs, not four or
five drivers** -- and scoped accordingly. `drvPPCBurgundy` and `drvPPCCuda` are
read from their committed artifacts and [report.md](report.md); **neither is
re-measured**. Selector sets were derived for this report from each `_reloc`'s
symbol table via `read_macho`, filtered to the module's own class, because a
source map cannot carry an address-0x0 symbol.

**This section is bounded to spec 4.6's stated questions.** Anything beyond them
is a recorded follow-on (section 5), not chased.

### 6.1 `IOAudio`: `PPCAwacs` against `drvPPCBurgundy`

Both are RhapsodiOS reimplementations of Apple audio drivers, and both are
`IOAudio` subclasses. Symbol-table selector sets, own class only:

```
--- IOAudio pairing ---
Awacs 39  Burgundy 38
  shared: 37
  Awacs only: 2
    ['resetAwacs', 'updateSampleRate:']
  Burgundy only: 1
    ['resetBurgundy']
```

**37 of 39 and 37 of 38 shared.** The two drivers are near-identical in surface:
every difference but one is the device-name method (`resetAwacs` against
`resetBurgundy`) -- the same method, named for its chip.

The 37 shared selectors:

```
_interruptOccurred, addAudioBuffer:Length:Interrupt:Output:, allocateDMAMemory,
channelCount, channelCountLimit, checkHeadphonesInstalled,
getDataEncodings:count:, getHandler:level:argument:forInterrupt:, getInputSrc,
getInputVol:, getOutputVol:, getRate, getSamplingRates:count:,
getSamplingRatesLow:high:, interruptClearFunc,
interruptOccurredForInput:forOutput:, isInputActive, isOutputActive, loopAudio:,
probe:, reset, resetAudio:, setInputSource:, setInputVol:, setOutputMute:,
setOutputVol:, setRate:, startDMAForChannel:read:buffer:bufferSizeForInterrupts:,
startIO:, stopDMAForChannel:read:, updateInputGain, updateInputGainLeft,
updateInputGainRight, updateOutputAttenuation, updateOutputAttenuationLeft,
updateOutputAttenuationRight, updateOutputMute
```

**The convention question, answered: `PPCAwacs` shares it too, not just
`drvPPCBurgundy`.**

| | Reference selectors | Exact | Renamed | Missing | Rename rate |
| --- | --- | --- | --- | --- | --- |
| `PPCAwacs` | 41 | 23 | **16** | 2 | **16 of 16** |
| `drvPPCBurgundy` | 40 | 21 | **16** | 3 | **16 of 16** |

- **Awacs: 23 exact + 16 renamed + 2 missing = 41.** Both missing are
  build-generated accessors; `extra` is empty.
- **Burgundy: 21 exact + 16 renamed + 3 missing = 40.** Missing = the same two
  accessors plus `probe:`, which Burgundy's source lacks under any name and
  Awacs's has under its exact reference name (`PPCSound.m:227`).

Every rename in both is the identical transformation: a
`<Class>(Private) _<name>` source method against a bare `<name>` reference
selector. **Neither driver has a single unexplained missing selector beyond
build-generated accessors.** The two reimplementations follow the same rule,
the same 16-of-16 rate, zero counterexamples in either direction -- Awacs has no
extras to check, and neither driver's missing accessors has an
underscore-prefixed source form (checked in [Awacs/findings.md](Awacs/findings.md),
"Reimplementation note").

**Therefore: project-wide.** The RhapsodiOS `IOAudio` reimplementations apply
underscore prefixing to private-category selectors as a rule, not a per-driver
choice. The consequence is the same for both and should be decided once
(section 5, entry 2): Objective-C dispatches on the exact selector string, so
the renamed methods are unreachable under the names Apple's binary exports.

One measured aside, within scope because it is a direct product of the pairing:
**`updateSampleRate:` is in Apple's `PPCAwacs` binary and not in Apple's
`PPCBurgundy` binary**, and Burgundy's source adds it as its single `extra`
([Burgundy/findings.md](Burgundy/findings.md), "Selector check"). So the selector
Burgundy's reimplementation introduced is real `IOAudio`-family API that Apple
shipped on the other chip -- not invented surface.

### 6.2 `IODirectDevice` + ADB/RTC: `ApplePMU` against `AppleCuda`

Both are `IODirectDevice` subclasses providing `ADBservice` and `RTCservice` --
Cuda for desk machines, PMU for PowerBooks. Source declarations, re-read for
this report:

```
pmupriv.h:136  @interface ApplePMU : IODirectDevice <ADBservice, RTCservice, NVRAMservice, PowerService>
cuda.h:141     @interface AppleCuda : IODirectDevice <ADBservice, RTCservice>
```

All four protocols are declared in `pmu.h` alone (`ADBservice` at `pmu.h:62`,
`RTCservice` at `pmu.h:129`, `NVRAMservice` at `pmu.h:148`, `PowerService` at
`pmu.h:168`); `cuda.h` redeclares its methods on the interface directly.
`AppleCuda` was measured in the first spec with **zero real gaps**
([Cuda/findings.md](Cuda/findings.md)).

Symbol-table selector sets, own class only:

```
--- IODirectDevice ADB/RTC pairing ---
PMU 42  Cuda 39
  shared: 26
  PMU only: 16
  Cuda only: 13
```

**What both implement -- 26 selectors**, which decompose cleanly by protocol:

| Group | Count | Selectors |
| --- | --- | --- |
| `ADBservice` | 12 | `registerForADBAutopoll::`, `ADBWrite:::::::`, `ADBRead:::::`, `ADBReset:::`, `ADBFlush::::`, `ADBSetPollList::::`, `ADBPollDisable:::`, `ADBPollEnable:::`, `ADBSetPollRate::::`, `ADBGetPollRate::::`, `ADBSetAlternateKeyboard::::`, `poll_device` |
| `RTCservice` | 3 | `registerForClockTicks::`, `setRealTimeClock::::`, `getRealTimeClock::::` |
| `NVRAMservice`-shaped | 2 | `readNVRAM::::::`, `writeNVRAM::::::` |
| `PowerService`-shaped | 1 | `registerForPowerInterrupts::` |
| `IODirectDevice` / common surface | 8 | `probe:`, `initFromDeviceDescription:`, `free`, `interruptOccurred`, `timeoutOccurred`, `receiveMsg`, `sendMiscCommand:::::::`, `CheckRequestQueue` |

12 + 3 + 2 + 1 + 8 = 26. **Neither driver lacks a selector from the two
protocols they both declare.** Both implement the identical 12 `ADBservice` and
3 `RTCservice` selectors.

A measured surprise on the shared list: **`AppleCuda`'s binary implements the
`NVRAMservice` and `PowerService` selectors too, despite adopting neither
protocol.** Its source defines all three, and the two NVRAM ones are stubs
returning `kPMUNotSupported` (`cuda.m:1280`, `cuda.m:1298`) -- 16-byte bodies at
0x1654 and 0x1664 -- while `registerForPowerInterrupts::` (`cuda.m:1316`) stores
the callback for real. So the ADB/RTC/NVRAM/Power surface is a *de facto*
contract wider than the declared protocol adoption, and `AppleCuda` satisfies it
by stubbing exactly the part it does not do.

**What is unique to each -- all of it transport, not contract.**

`ApplePMU` only (16): `StartPMUTransmission:`, `SendPMUByte:`, `ReadPMUByte:`,
`WaitForAckLo`, `WaitForAckHi`, `GetPMUInterruptState`, `RestorePMUInterrupt:`,
`DisablePMUInterrupt`, `EnablePMUInterrupt`, `AcknowledgePMUInterrupt`,
`GetSRInterruptState`, `RestoreSRInterrupt:`, `DisableSRInterrupt`,
`EnableSRInterrupt`, `ADBinput::`, `interruptOccurredAt:`.

`AppleCuda` only (13): `StartCudaTransmission:`, `EnableCudaInterrupt`,
`CudaMisc:::::`, `cuda_process_response`, `cuda_transmit_data`,
`cuda_receive_data`, `cuda_receive_last_byte`, `cuda_expected_attention`,
`cuda_unexpected_attention`, `cuda_queue:`, `cuda_collision`, `cuda_idle`,
`cuda_error`.

Both lists are the chip's own byte-level transport -- PMU's VIA shift-register
handshake and interrupt save/restore pairs, Cuda's request state machine -- plus
one hook each outside it (`ADBinput::`, PMU's internal ADB read callback, and
`interruptOccurredAt:`, an `IODirectDevice` override Cuda does not take).
**Nothing in either list is a selector the other should have.**

**Does either lack something the other has? No -- but both lack the same
thing.** `-[X ADBSetFileServerMode:::]` is declared as a required `ADBservice`
method and defined in *both* sources (`pmu.m:576`, `cuda.m:791`), and is absent
from *both* Apple binaries at any arity. Each driver's `selector_check.py`
reports it as an extra (4.4). It is the only member of the `ADBservice` contract
that neither shipped implementation carries, and PMU's own header documents the
asymmetry Apple intended -- `kPMUNotSupported = 3, // PMU don't do that (Cuda
does, though)`, `pmu.h:51` -- while the shipped binaries show Apple emitting it
on neither.

`AppleCuda` carries one further source-only extra,
`-[AppleCuda setPowerupTime::::]` (`cuda.h:266`), outside both shared protocols;
it is recorded in [Cuda/findings.md](Cuda/findings.md) and not chased here.

---

## Acceptance

Spec 5, items 1-8. Every item below was observed in output run for this report;
nothing is claimed that was not run.

### Item 1 -- ten analyses complete and published -- **PASS**

`complete: true` in every `run-summary.json`, and
`published/analysis-reference-ida.json` present for all ten. Each analysis's
recorded input identity matches spec 1.1's sizes exactly:

```
profile                    complete published sha256                                                           size
ohare-ppc                      True      True 56FD92D69B400F8BAB5B4453BAAAF8B4E009C615DF27B026D9B31E8E826C794A size=16568
ohare-bundle-ppc               True      True 15DCEA39494EEC4EA61DA1E62154D0731B95B3E8762A5A4BC60A465A5219A93F size=8496
pmu-ppc                        True      True 2F63C89DFEDEBCC5D1F2CEABA8417DC65BCC8BF32CA7B310B1EA0DD43831F7B5 size=41488
pmu-bundle-ppc                 True      True 4FA57C39341891263D099AC2A05647C80E2462F0B1993C16696A8CD990F05A68 size=8492
awacs-ppc                      True      True D66BE5132E4F53365D346F3ED38515C7D4024DCF13A2A3FD9711D39B04590890 size=38540
awacs-bundle-ppc               True      True 2E263A4D37E210B00F164E91E5DFC35A5605F587247CCB032B92E10F587885A4 size=8492
applepcibus-ppc                True      True 59F4DFF2481850E5F18B275CFCBE7950CCE74658D18DAD03FF68EC0A98DB9C4D size=26668
applepcibus-bundle-ppc         True      True 76BC7D0EC7599F6DC8E9B8D813DB0850C6F1B1CE62F8E9760BC857C4157EFEB8 size=8500
iodisplay-ppc                  True      True FD38FBA638BE85555D342D5349EABDE764F8562084DECEB1A3D33FDAC166B3F1 size=32640
iodisplay-bundle-ppc           True      True 50FFD4F02A9C1807D1135799D3C8A8F5BF03799BD6EE934CDF05C53D85FB83E7 size=8492
```

Exit 1 throughout was the expected outcome for reference-only profiles, per spec
3.1, and is not a failure.

### Item 2 -- 0 relocation violations across all ten -- **PASS**

`ppc_invariant_check.py --binary ... --analysis ...` re-run against all ten for
this report:

```
=== ohare-ppc ===
symbol +[AppleOHare probe:] at 0x0 is not a function start
2 scattered/difference-form relocations (target section verified, field is a difference, not an address)
1 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
98 fused relocations, 1 violations
=== ohare-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered, 0 pairs, 0 fused relocations, 1 violations
=== pmu-ppc ===
symbol +[ApplePMU probe:] at 0x0 is not a function start
14 scattered/difference-form relocations (target section verified, field is a difference, not an address)
2 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
632 fused relocations, 1 violations
=== pmu-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered, 0 pairs, 0 fused relocations, 1 violations
=== awacs-ppc ===
symbol +[PPCAwacs probe:] at 0x0 is not a function start
8 scattered/difference-form relocations (target section verified, field is a difference, not an address)
4 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
630 fused relocations, 1 violations
=== awacs-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered, 0 pairs, 0 fused relocations, 1 violations
=== applepcibus-ppc ===
10 scattered/difference-form relocations (target section verified, field is a difference, not an address)
5 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
457 fused relocations, 0 violations
=== applepcibus-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered, 0 pairs, 0 fused relocations, 1 violations
=== iodisplay-ppc ===
symbol -[IOSmartDisplay registerLoudly] at 0x0 is not a function start
8 scattered/difference-form relocations (target section verified, field is a difference, not an address)
4 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
561 fused relocations, 1 violations
=== iodisplay-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered, 0 pairs, 0 fused relocations, 1 violations
```

Nine runs print `1 violations` and one (`applepcibus-ppc`) prints `0`. In every
case where the count is 1, that 1 is the symbol/function-start mismatch from
`check_functions`, **not** a relocation-decode violation from `check_document`.
**Actual relocation violations: 0 in all ten.** The nine mismatched symbols are
enumerated in section 1 (the four `_reloc` symbols) and section 3
(`__mh_bundle_header` in all five stubs). They are not required to be zero.

`applepcibus-ppc`'s 0 is not a stronger result: its address-0x0 symbol is one
IDA's analysis happens to record, so there is no mismatch to flag. Per 4.6's
correction that makes it the complete case, not the anomalous one.

**No checker change was needed for this spec.** The two defects fixed during the
SCSI spec and the `ori`-form under-report caught in its final review all hold;
`ppc_invariant_check.py` was not touched here.

### Item 3 -- five maps load against a scoped reference analysis -- **PASS**

Each map loaded via `load_source_map` against its reference analysis restricted
to the addresses that map covers across **all four map categories** (`mapped`
union `unmapped` union `duplicate_candidates` union `boundary_disputed`), with
the repo root:

```
OHare OK (7 functions -> 3 scoped)
PMU OK (89 functions -> 43 scoped)
Awacs OK (118 functions -> 40 scoped)
ApplePCIBus OK (52 functions -> 26 scoped)
IODisplay OK (64 functions -> 25 scoped)
```

3 = 1 + 2; 43 = 41 + 2; 40 = 22 + 18; 26 = 24 + 2; 25 = 18 + 7. Scoping is
required, not a weakening: `--scope-to-objc` maps do not claim the unnamed jump
islands and `load_source_map` enforces an *exact* partition, so an unscoped
analysis fails. Over everything each map does claim, the check verifies the full
partition, names, sizes, source-line bounds and the analysis's SHA-256 identity.
Item 5 independently accounts for every function scoped out -- 4 + 46 + 78 + 26 +
39 -- so the pair together covers all 330 functions (137 scoped in, 193 out).

### Item 4 -- duplicates and disputes enumerated -- **PASS**

`duplicate_candidates` is **0 for all five**. `boundary_disputed` is **0 for all
five**. Nothing to enumerate; the counts are in section 1's summary table, and
each `findings.md` records them independently.

The one symbol per `_reloc` at address 0x0 (section 1) is recorded as a
`boundary_disputed` *candidate* by `ppc_invariant_check.py`, not by the source
map, which is why the map's own count is 0. Each is enumerated in section 1 with
whether it is a real IDA function and what source site, if any, it corresponds
to.

### Item 5 -- every function in exactly one bucket, buckets sum to total -- **PASS**

All five bucket tables re-derived for this report; **all five print
`RECONCILES: yes`**. Counted totals are 7, 89, 118, 52 and 64 against IDA's
totals of 7, 89, 118, 52 and 64. Full table in section 1.

Six bucket-6 entries carry an explicitly recorded absence rather than a source
site -- all six in `IODisplay`, each grepped for individually and characterised
in 4.3 -- and one (`-[IOPCIBridge registerLoudly]`, `IOApplePCIBus`) carries a
recorded caveat (4.6). **No entry in any of the five is unexamined.**

### Item 6 -- binrecon suite green at 845 passed, 4 skipped -- **PASS**

```
$ PYTHONPATH=tools/binrecon python -m pytest tools/binrecon/tests -q
845 passed, 4 skipped in 49.42s
```

**Exactly spec 5 item 6's figure**, no discrepancy to record. Spec 2.1 predicted
the rise from 835 to 845 because
`test_ppc_profiles_are_reference_only_ida_runs` is parametrized over the profile
glob and this spec added ten profiles.

`test_ppc_profile_inventory` passes and names **39** profiles, as spec 2.1
requires (`tools/binrecon/tests/test_profile.py:360-382`); the profile directory
holds 39 `*ppc*.json` files.

The one test known to be flaky,
`test_compare.py::test_mutation_during_later_section_reads_is_rejected`,
**passed on this run**; no retry was needed. It is a pre-existing intermittent
failure unrelated to this spec and tracked separately.

### Item 7 -- report carries all six parts, section 5 names each follow-on spec with its gap -- **PASS**

Section 1 Correspondence (spec 4.1), 2 Class inventory (4.2), 3 Non-Objective-C
remainder (4.3), 4 Findings (4.4), 5 Decomposition proposal (4.5), 6 Two
pairings (4.6).

Section 5 names five per-driver follow-on specs, each with its measured
mapped/unmapped counts, its exact-name match rate, its bucket-6 residue after
hand resolution, a drift-versus-different-version assessment and its measured
gap -- `IODisplay` **6 entry points plus 1 address-0x0 symbol**, `PPCAwacs` **0
selectors absent under any name** (16 renamed), `IOApplePCIBus` **0 selectors
absent from source** (3 source-side anomalies), `drvPPCPMU` **0**, `drvPPCOHare`
**0**.

Section 3 states explicitly that buckets 1 and 2 are empty in all five, with the
reason (statically linked kernel servers, no `__picsymbol_stub` section), and
4.8 restates it. Sections 3 and 4.5 both state that the 213 and 219 extras are
the shared directory's sibling classes, with the full per-class attribution and
the two runs cross-validating each other. Section 4.7 records the packaging gap
in all three of its shapes.

### Item 8 -- section 6 answers both pairing questions from measurement -- **PASS**

Section 6.1 answers the `IOAudio` question: **`PPCAwacs` shares
`drvPPCBurgundy`'s underscore convention**, from `PPCAwacs`'s 16 renames at 16 of 16
against `drvPPCBurgundy`'s 16 at 16 of 16, with the arithmetic stated for both
(23 + 16 + 2 = 41; 21 + 16 + 3 = 40) and neither carrying an unexplained missing
selector. It also reports the shared/unique selector split (37 shared of 39 and
38).

Section 6.2 answers the `IODirectDevice` ADB/RTC question: 26 shared selectors
decomposed by protocol, 16 unique to `ApplePMU` and 13 to `AppleCuda`, all of
them chip transport; **neither lacks a selector from the two protocols they both
declare**; and both lack the same one, `ADBSetFileServerMode:::`, present in
both sources and absent from both Apple binaries.

`drvPPCBurgundy` and `drvPPCCuda` were **not re-measured** -- their selector sets
were read from their `_reloc` symbol tables and everything else from their
committed `findings.md` and [report.md](report.md). The section is bounded to
spec 4.6's stated questions, per spec 5.1.

### Not claimed

- **No PowerPC compile.** `parity_check.py` and `import_check.py` need a rebuilt
  binary and remain unusable. Nothing here is compile-verified, and no claim is
  made that any of the five builds or runs.
- **No behavioural equivalence for mapped bodies.** The source maps match names,
  addresses and sizes, and this batch's bucket-5 confirmations are
  basic-block-shape only -- no decompiler was available, so nothing here matches
  the byte-level check [report-network.md](report-network.md) 4.3 applied to
  Gem. Section 5's closing note states what that bounds.
- **No demonstrated runtime consequence.** Awacs's 16 renames have a known
  mechanism (exact-selector dispatch) but no caller outside the class was looked
  for; IODisplay's 6 absences are unexplained content, not a demonstrated
  failure. This batch has no equivalent of Gem's CRC finding.
- **The cause of `IODisplay`'s six absences is not established** (4.3) -- only
  that they are absent, exhaustively.
- **Dead-stripping of `IOApplePCIBus`'s two `[super ...]` overrides is not
  confirmed** (4.6), only judged consistent with the evidence.
- **The packaging gap is recorded, not closed** (4.7).
- **`drvPPCBurgundy` and `drvPPCCuda` were not re-measured** -- section 6 reads
  their selector sets from their `_reloc` symbol tables and cross-references
  [report.md](report.md) for everything else.
- **`PPCSerialPort`, `IONDRVSupport`, `IOADBDevice`, `adbservd`, `Floppy`,
  `DEC21x4Ethernet`, `BPF`, `PortServer` are not measured**, per spec 1.3.
- **The "sixteen drivers... every binary" address-0x0 disposition (4.6) was not
  re-verified in full for this report.** Only this batch's own ten artifacts
  were re-run through `ppc_invariant_check.py` here; the other six are read
  from the three prior reports as committed.
