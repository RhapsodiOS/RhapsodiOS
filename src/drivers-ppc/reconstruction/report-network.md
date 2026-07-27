# PowerPC network driver evidence base

Four in-tree PowerPC network driver sources measured against Apple's shipped
Rhapsody binaries, per
[docs/superpowers/specs/2026-07-27-ppc-network-driver-evidence-base-design.md](../../../docs/superpowers/specs/2026-07-27-ppc-network-driver-evidence-base-design.md).

This report changes no driver source and no build wiring. It records what was
measured. Every number below comes from a command run for this report against
the published analyses, the checked-in source maps and the reference binaries;
the per-driver `findings.md` beside this file carries the evidence for each
cause attributed here.

It is a **second** report rather than an extension of [report.md](report.md),
which measured `drvPPCCuda`, `drvPPC53c96`, `drvPPCATA`, `drvPPCBMac` and
`drvPPCBurgundy` against a different set of binaries with its own acceptance
run. §6 cross-references it for `drvPPCBMac`, which is **not re-measured
here**.

**What this does not establish.** No PowerPC toolchain exists in this
environment, so nothing here is compile-verified. These are structural
correspondences between our sources and Apple's binaries, not proof that any of
these drivers builds or runs.

Reference artifacts are the eight Mach-O files under
`C:\Users\raynorpat\Downloads\test\Drivers\ppc`, four bundle stubs and four
kernel-server `_reloc` images. All eight SHA-256 identities and sizes carried in
the published analyses match spec §1.1; see [Acceptance](#acceptance) item 1.

---

## 1. Correspondence

Summary table, re-derived from
`tools/binrecon/out/<profile>/published/analysis-reference-ida.json` and each
`source-map.json`:

```
driver      total  mapped  unmap  dup  disp     mapB   unmapB
GNic          156      47      2    0     0     8156       36
Gem           157      48      2    0     0     9152       36
Mace          183      47      2    0     0    12372       36
Dec21040      161      48      2    0     0    10244       36
```

`total` is IDA's total function count for the `_reloc` binary. `mapB`/`unmapB`
are mapped and unmapped bytes.

This is the most uniform result the method has produced: **47-48 mapped, exactly
2 unmapped, 0 duplicate candidates and 0 boundary-disputed entries in all
four**, and in all four the two unmapped entries are the same build-generated
pair (§3). The 36 unmapped bytes are identical across the four because they are
the same two tool-emitted accessors, 20 + 16 bytes.

### Named / unnamed split

`--scope-to-objc` restricts each map to the binary's Objective-C methods, so the
named/unnamed split is what makes the rest of the binary countable:

```
driver      total  named  unnamed   objc  nonobjc
GNic          156     52      104     49        3
Gem           157     55      102     50        5
Mace          183     55      128     49        6
Dec21040      161     52      109     50        2
```

`objc` is the in-scope set the source map operates on (`mapped + unmapped`);
`nonobjc` is the named C functions the map deliberately does not claim, which §3
buckets by hand. `unnamed` is bucket 3 throughout.

### Row reconciliation

Each row reconciles as `mapped + bucket1..6 = total`. The `unmapped` column
above is not a separate term: in all four it lands entirely in bucket 4.

| Driver | mapped | b1 | b2 | b3 | b4 | b5 | b6 | sum | total |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GNic | 47 | 0 | 0 | 104 | 2 | 0 | 3 | 156 | 156 |
| Gem | 48 | 0 | 0 | 102 | 2 | 0 | 5 | 157 | 157 |
| Mace | 47 | 0 | 0 | 128 | 2 | 0 | 6 | 183 | 183 |
| Dec21040 | 48 | 0 | 0 | 109 | 2 | 0 | 2 | 161 | 161 |

All four print `RECONCILES: yes`. Bucket 5 is 0 straight out of the bucketing
script by construction - entries move into it by hand, per §3.

### One symbol per binary sits at address 0x0

Each `_reloc` carries exactly one `__TEXT,__text` symbol at address `0x0` that
IDA does not treat as a function start, so it can appear in neither `mapped` nor
`unmapped`. This is why each driver's source-side method count exceeds its
mapped count by exactly one:

| Driver | Symbol at 0x0 | Source site | source methods | - 1 | = mapped |
| --- | --- | --- | --- | --- | --- |
| GNic | `-[GNicEnet(Private) _allocateMemory]` | `GNicEnetPrivate.m:115` | 48 | 47 | 47 |
| Gem | `+[GemEnet probe:]` | `GemEnet.m:118` | 49 | 48 | 48 |
| Mace | `+[MaceEnet probe:]` | `MaceEnet.m:45` | 48 | 47 | 47 |
| Dec21040 | `-[DECchip21041 initFromDeviceDescription:]` | `DECchip21041.m:52` | 49 compilable | 48 | 48 |

Address 0x0 is the Mach-O header/load-command region, not a code address in a
relocatable object: these are symbol-table entries with placeholder addresses,
the same disposition the previous report recorded for its five binaries. None
overlaps any function in any bucket table or source map, so none affects the
correspondence numbers. Evidence: each driver's `findings.md`, "Invariant check"
- [GNic](GNic/findings.md), [Gem](Gem/findings.md), [Mace](Mace/findings.md),
[Dec21040](Dec21040/findings.md).

---

## 2. Class inventory

Module-owned classes, derived for this report from the `-[...]`/`+[...]` symbols
in each `_reloc` via `binrecon.macho.read_macho` (which, unlike IDA's export,
preserves category tags):

| Driver | Binary classes (methods) | Binary categories | Source `@implementation` blocks |
| --- | --- | --- | --- |
| GNic | `GNicEnet` (48) | `Private` | `GNicEnet` (`GNicEnet.m:94`), `GNicEnet(Private)` (`GNicEnetPrivate.m:21`) |
| Gem | `GemEnet` (49) | `Private` | `GemEnet` (`GemEnet.m:112`), `GemEnet(Private)` (`GemEnetPrivate.m:156`) |
| Mace | `MaceEnet` (48) | `Private` | `MaceEnet` (`MaceEnet.m:39`), `MaceEnet(Private)` (`MaceEnetPrivate.m:66`) |
| Dec21040 | `DECchip2104x` (41), `DECchip21040` (4), `DECchip21041` (4) | `Private`, on `DECchip2104x` only | `DECchip21040`, `DECchip21041`, `DECchip2104x`, `DECchip2104x (Private)` |

Every binary additionally carries `drv<Name>KernelServerInstance` and
`drv<Name>Version`, one method each - the build-generated pair that populates
bucket 4 in all four (§3).

**Class and category structure corresponds one-for-one in all four.** Nothing
resembling the previous report's `IdeDisk`/`ATADisk` rename occurs here.

### How `drvPPCDec21040`'s three classes divide its binary

Dec21040 is the only driver in this batch carrying more than one class. The 48
mapped entries divide **4 / 3 / 41**:

| Class | Binary symbols | Mapped | Source |
| --- | --- | --- | --- |
| `DECchip21040` | 4 | 4 | `DECchip21040.m` (4/4) |
| `DECchip21041` | 4 | 3 | `DECchip21041.m` (3/4; `initFromDeviceDescription:` is the address-0x0 symbol, §1) |
| `DECchip2104x` incl. its `(Private)` category | 41 | 41 | `DECchip2104x.m` (26) + `DECchip2104xPrivate.m` (15 of 17; 2 `#ifdef DEBUG`-excluded) |

4 + 3 + 41 = 48, and 4 + 4 + 41 = 49 binary symbols = 48 mapped + 1 at 0x0.
`DECchip21040` and `DECchip21041` both subclass `DECchip2104x`, and each
overrides `getStationAddress:`, `selectInterface` and
`initFromDeviceDescription:`; `_setInterface:` is defined on the two subclasses
only. Those overrides are why the binary's 51 Objective-C symbols collapse to 44
distinct selectors (§6). They raise no `duplicate_candidates`, because the map
keys on the full `Class selector` reference name and each override is a distinct
symbol at a distinct address with its own source site. Evidence:
[Dec21040/findings.md](Dec21040/findings.md), "Three classes".

---

## 3. Non-Objective-C remainder

`--scope-to-objc` puts every non-Objective-C function outside the map. Left
alone that would read as coverage the map does not have, so every function IDA
found that the map does not cover is placed in exactly one of spec §3.4's six
buckets.

### Buckets 1 and 2 are empty across all four

**Bucket 1 (crt/dyld startup routines): 0 in all four. Bucket 2
(`__picsymbol_stub` entries): 0 in all four.** This is not an omission. All four
`_reloc` images are **statically linked kernel servers, not `MH_EXECUTE`
helpers**: they carry no `start`/`__start`/`__call_mod_init_funcs`/
`__dyld_init_check`/`dyld_stub_binding_helper`/`__dyld_func_lookup`, and their
analyses carry **no `__picsymbol_stub` section** for the stub-range check to
match against. The section list re-derived for this report is identical in shape
across all four - `__text`, `__cstring`, `__const`, `__data`/`__bss` where
present, `__common`, the Objective-C metadata sections, `__symbols` and the
DriverKit `Server Name`/`Server Version` pseudo-sections - with no stub section
anywhere.

The crt/dyld routines do exist, but in the *bundle stubs*: each of the four
bundle analyses contains exactly two functions, `dyld_stub_binding_helper` (48
bytes) and `__dyld_func_lookup` (32 bytes), and no driver code at all. No source
map or bucket table was built for the stubs.

### Bucket 4 - build-generated classes

Two entries in every driver, identical in shape, and in all four they are the
whole of the "unmapped" column:

| Driver | Address | Symbol | Size |
| --- | --- | --- | --- |
| GNic | 0x28c0 / 0x28d4 | `+[drvPPCGNicKernelServerInstance kernelServerInstance]` / `+[drvPPCGNicVersion driverKitVersionFordrvPPCGNic]` | 20 / 16 |
| Gem | 0x2c18 / 0x2c2c | `+[drvPPCGemKernelServerInstance ...]` / `+[drvPPCGemVersion ...]` | 20 / 16 |
| Mace | 0x39bc / 0x39d0 | `+[drvPPCMaceKernelServerInstance ...]` / `+[drvPPCMaceVersion ...]` | 20 / 16 |
| Dec21040 | 0x33ec / 0x3400 | `+[drvPPCDec21040KernelServerInstance ...]` / `+[drvPPCDec21040Version ...]` | 20 / 16 |

These are DriverKit build-tooling output, not hand-written driver code.

### Buckets 3, 5 and 6 per driver

| Driver | b3 unnamed islands | b6 from script | to b5 by hand | b6 residue |
| --- | --- | --- | --- | --- |
| GNic | 104 | 3 | 2 | **1** (`__udivdi3`) |
| Gem | 102 | 5 | 3 | **2** (`_crc416`, `__udivdi3`) |
| Mace | 128 | 6 | 5 | **1** (`__udivdi3`) |
| Dec21040 | 109 | 2 | 2 | **0** |

Bucket-5 moves are recorded with file and line in each `findings.md`:

- [GNic](GNic/findings.md): `_WriteGNicRegister` (`GNicEnet.m:66`),
  `_ReadGNicRegister` (`GNicEnet.m:32`).
- [Gem](Gem/findings.md): `_WriteGemRegister` (`GemEnet.m:76`),
  `_ReadGemRegister` (`GemEnet.m:32`), `_mace_crc` (`GemEnetPrivate.m:135`).
  **`_mace_crc`'s move is a name-only match**, not a confirmed correspondence -
  see §4.3.
- [Mace](Mace/findings.md): `_WriteMaceRegister` (`MaceEnetHW.m:39`),
  `_ReadMaceRegister` (`MaceEnetHW.m:46`), `_reverseBitOrder`
  (`MaceEnetPrivate.m:51`), `_crc416` (`MaceEnetPrivate.m:1510`), `_mace_crc`
  (`MaceEnetPrivate.m:1548`) - all five confirmed by disassembly against the
  source, not by name alone.
- [Dec21040](Dec21040/findings.md): `_reverseBitOrder` (`DECchip21041.m:281`),
  `_IOUpdateDescriptorFromNetBuf` (`DECchip2104xPrivate.m:97`) - both confirmed
  by disassembly.

`__udivdi3` (1616 bytes) is libgcc's 64-bit unsigned-division runtime helper,
emitted by the compiler with no driver-source counterpart (§4.2). `_crc416` is
the one bucket-6 residue in this batch that is a genuine driver-code absence
(§4.3).

### Merged `selector_check.py` output

Per driver, re-run for this report against the `_reloc` binary and the source
directory named in spec §1.2:

| Driver | ref selectors | our defs | renames | duplicates | missing | extra | exit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GNic | 50 | 48 | 0 | 0 | 2 | 0 | 0 |
| Gem | 51 | 49 | 0 | 0 | 2 | 0 | 0 |
| Mace | 50 | 48 | 0 | 0 | 2 | 0 | 0 |
| Dec21040 | 51 | 51 | 0 | 0 | 2 | 2 | 0 |

**Zero renames and zero duplicates in all four.** The `missing` two are the
build-generated pair in every case, matching each source map's unmapped set
exactly. `ref selectors` exceeds `mapped + missing` by one in each driver - that
one is the address-0x0 symbol from §1.

Exact-name match rate (`ref - missing - renames`):

| Driver | matched | of | rate |
| --- | --- | --- | --- |
| GNic | 48 | 50 | 96.0% |
| Gem | 49 | 51 | 96.1% |
| Mace | 48 | 50 | 96.0% |
| Dec21040 | 49 | 51 | 96.1% |

The four cluster within 0.1 points of each other. As the previous report
established, match rate does not rank the work: Gem's rate is joint-highest here
and Gem carries this batch's only divergence with a runtime consequence (§4.3).
§5 ranks by that, not by rate.

Dec21040's two `extra` entries are §4.5.

### Symbol / function-start mismatches

`ppc_invariant_check.py` reports one per artifact, eight in eight. None is a
relocation-decode defect (see [Acceptance](#acceptance) item 2), and none
overlaps any function in any bucket table or source map, so none affects the
correspondence numbers. The four `_reloc` symbols are tabulated in §1; all four
bundle stubs report `__mh_bundle_header`, the standard synthetic bundle-header
symbol, which is not a function at all.

---

## 4. Findings

### 4.1 All four are near-complete matches

This is the headline structural result, and it is uniform. Per §1 and §3, and
per each driver's `findings.md`:

- **47-48 mapped** methods each.
- **Exactly 2 unmapped** each, and in all four both are the build-generated
  `drv<Name>KernelServerInstance` and `drv<Name>Version` accessors - DriverKit
  tool output, not driver code.
- **0 `duplicate_candidates`** and **0 `boundary_disputed`** in all four.
- **0 renames and 0 duplicates** from `selector_check.py` in all four.
- Every bucket table prints `RECONCILES: yes`.

No class rename, no selector rename, no class-placement divergence, no duplicate
implementation. Evidence: [GNic/findings.md](GNic/findings.md),
[Gem/findings.md](Gem/findings.md), [Mace/findings.md](Mace/findings.md),
[Dec21040/findings.md](Dec21040/findings.md).

### 4.2 `__udivdi3` is a real gap in GNic, Gem and Mace - and an expected one

`__udivdi3` (1616 bytes) appears in the bucket-6 residue of GNic (0x28e4), Gem
(0x2c3c) and Mace (0x39e0), and matches nothing anywhere under the respective
source directory. It is libgcc's 64-bit unsigned-division runtime helper, which
the PowerPC compiler emits when the source divides a 64-bit quantity. It is
**compiler-generated code with no driver-source counterpart, not a
reconstruction gap** - the same disposition the previous report gave it in BMac
and ATA. No caller could be identified in any of the three: the reference
analyses carry no call-graph edges for these binaries.

Dec21040 is the one driver in this batch that does not carry it, which is why
its bucket-6 residue is 0. Evidence: [GNic/findings.md](GNic/findings.md),
[Gem/findings.md](Gem/findings.md), [Mace/findings.md](Mace/findings.md), each
under "Buckets".

### 4.3 Gem's CRC divergence - the headline finding

**Apple's `drvPPCGem_reloc` and this repository's `GemEnetPrivate.m` compute
different multicast-hash CRCs under the same function name, and the difference
changes which hash bucket gets programmed.**

**The binary evidence.** Gem's `_crc416` (0x2920, 100 bytes) and `_mace_crc`
(0x2984, 68 bytes) are **byte-for-byte identical** to Mace's (0x371c / 0x3780)
and to BMac's (0x4ec0 / 0x4f24). Re-verified for this report by SHA-256 over the
`__TEXT,__text` bytes of each function in all three `_reloc` files, using each
file's own `__text` file-offset delta:

```
crc416   {'gem': ('0x2920', 100), 'mace': ('0x371c', 100), 'bmac': ('0x4ec0', 100)}
   byte-identical across gem/mace/bmac: True
mace_crc {'gem': ('0x2984',  68), 'mace': ('0x3780',  68), 'bmac': ('0x4f24',  68)}
   byte-identical across gem/mace/bmac: True
```

Apple's compiled `_mace_crc` is a thin wrapper that reads three 16-bit halfwords
from the address argument and calls `_crc416` on each, and `_crc416` is a
16-iteration bit loop with polynomial `0x04c11db7` - exactly the pair
`MaceEnetPrivate.m:1510`/`:1548` and `BMacEnetPrivate.m:1622`/`:1660` define.

**The source divergence.**
`src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnetPrivate.m:135`
defines `_mace_crc` as a *different algorithm* - a byte-wise reflected CRC-32
with polynomial `0xEDB88320` over all six address bytes, calling nothing - and
the tree carries **no `_crc416` at all**, which is why `_crc416` is Gem's one
genuine driver-code bucket-6 residue (§3).

**They are not behaviour-equivalent.** Re-derived for this report by
implementing both - Apple's `crc416`/`mace_crc` pair reading each halfword
big-endian, which is the correct byte order on PowerPC, and this repository's
`GemEnetPrivate.m:135` version - and running both over five MAC addresses
including the standard IPv4 and IPv6 multicast addresses:

```
MAC                apple CRC   top6   ours CRC    top6   | Gem 8-bit index (apple CRC / ours CRC)
01:00:5E:00:00:01  0x7FA32D9B    31   0xD9B4C5FE    54   |   38 / 128  DIFFER
33:33:00:00:00:01  0xF99BAABA    62   0x5D55D99F    23   |  162 /   6  DIFFER
FF:FF:FF:FF:FF:FF  0xFF48647D    63   0xBE2612FF    47   |   65 /   0  DIFFER
00:00:00:00:00:00  0x3A7ABC72    14   0x4E3D5E5C    19   |  177 / 197  DIFFER
01:23:45:67:89:AB  0xA72FE892    41   0x4917F4E5    18   |  182 /  88  DIFFER

raw CRC identical on 0/5 vectors
top-6-bit index identical on 0/5 vectors
Gem's own 8-bit hash index identical on 0/5 vectors
```

**0 of 5 agree on every metric.** The rightmost column feeds each CRC through
this repository's own `-[GemEnet(Private) _addToHashTableMask:]`
(`GemEnetPrivate.m:1063`: low 8 bits, bit-reversed, then inverted) - so it is
the bucket this driver as written would actually program. It differs on all
five. The concrete consequence: **`GemEnet` would program the wrong multicast
hash bucket**, dropping multicast frames it should accept and accepting frames
it should not.

This is the only finding in this batch with a demonstrated runtime consequence,
and it is why Gem ranks first in §5 despite numbers as clean as the other three.
`_mace_crc` remains a bucket-5 entry because a source site genuinely exists -
the bucket taxonomy is about source-site existence, not logic equivalence - but
**it must not be counted as a confirmed match**. Evidence:
[Gem/findings.md](Gem/findings.md), "Buckets" and "Headline finding".

### 4.4 Mace is the control that makes §4.3 meaningful

Mace's compiled `_crc416`/`_mace_crc` pair is byte-identical to BMac's and to
Gem's (the comparison above covers all three), **and Mace's own source
matches**: `MaceEnetPrivate.m:1510` defines `crc416` as the same 16-iteration
bit loop with polynomial `0x04c11db7` (`#define ENET_CRCPOLY 0x04c11db7`,
`MaceEnetPrivate.m:1496`) that `BMacEnetPrivate.m:1608`/`:1622` carries, and
`MaceEnetPrivate.m:1548` defines `mace_crc` as exactly three chained `crc416`
calls on the address's three 16-bit halfwords.

So the divergence in §4.3 is **specific to Gem's reimplementation, not a general
property of the family**. The distinction tracks source provenance: Mace and
Dec21040 sit in Apple's Darwin tree at `src/kernel-7/bsd/dev/ppc/`, while GNic
and Gem are this project's own driver projects under
`src/drivers-ppc/network/`. Evidence: [Mace/findings.md](Mace/findings.md),
"CRC finding".

### 4.5 Dec21040's two "extra" selectors are preprocessor exclusions

`selector_check.py` reports 2 `extra` entries for Dec21040 and 0 for the other
three: `-[DECchip2104x(Private) _dumpDescriptor:]` and
`-[DECchip2104x(Private) _dumpRegisters]`. Both sit inside `#ifdef DEBUG` blocks
at `DECchip2104xPrivate.m:223` and `:237`, and `#define DEBUG` is commented out
at `DECchip2104xPrivate.m:64`, so neither compiles into the shipped binary. The
source-selector parser counts them regardless of the inactive guard.

The previous spec's review found "extra" selectors mislabelled as naming
artifacts when they were genuinely absent, and two more that existed on a
*different* class (`drvPPCATA`'s `matchDevicePath:` and
`getDevicePath:maxLength:useAlias:`). So this was re-checked class-insensitively
for this report against the full 51-entry Objective-C symbol dump of
`drvPPCDec21040_reloc` read via `read_macho`:

```
objc symbols: 51
  class-insensitive search "_dumpRegisters": 0 []
  class-insensitive search "_dumpDescriptor:": 0 []
```

Neither selector exists in the binary under **any** class or category. This is a
preprocessor-exclusion gap, not a sibling-class placement difference: **the
`drvPPCATA` pattern does not recur here.** The same check confirms each driver's
two `missing` entries are the build-generated accessors and nothing else.
Evidence: [Dec21040/findings.md](Dec21040/findings.md), "Selector check".

The two guarded static C functions `IOBreak` (`DECchip2104xPrivate.m:69`) and
`printDesc` (`:75`) sit in the same inactive block and likewise raise no
bucket-6 entry.

### 4.6 The packaging gap

Two of the four sources build **into the kernel**. Re-read from
`src/kernel-7/conf/files.ppc` for this report:

```
109:bsd/dev/ppc/drvMaceEnet/MaceEnet.m 			optional mk_hasdrivers
110:bsd/dev/ppc/drvMaceEnet/MaceEnetPrivate.m 		optional mk_hasdrivers
111:bsd/dev/ppc/drvMaceEnet/MaceEnetHW.m 			optional mk_hasdrivers
118:bsd/dev/ppc/drvDECchip21040/DECchip21040.m         optional mk_hasdrivers
119:bsd/dev/ppc/drvDECchip21040/DECchip21041.m         optional mk_hasdrivers
120:bsd/dev/ppc/drvDECchip21040/DECchip2104x.m         optional mk_hasdrivers
121:bsd/dev/ppc/drvDECchip21040/DECchip2104xPrivate.m  optional mk_hasdrivers
```

The other two are **already loadable-driver projects**:
`src/drivers-ppc/network/drvPPCGNic/GNic.drvproj` and
`src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj`, each with its own
`Makefile`, `Makefile.preamble` and `dpkg` directory. Neither appears anywhere
in `files.ppc`.

**All four shipped artifacts are loadable kernel servers** - each is a
`<name>.config` bundle carrying a bundle stub plus a `_reloc` kernel-server
image (§1.1, and the eight identities in [Acceptance](#acceptance) item 1).

So `drvMaceEnet` and `drvDECchip21040` are wired to build one way and shipped
another. This is a real divergence in how the code is packaged and loaded, and
this spec does not close it: **recorded and deferred** to the per-driver specs,
per spec §1.3. Nothing in §1-§3 depends on it, because the measurement compares
compiled function bodies, which are the same either way. Evidence:
[Mace/findings.md](Mace/findings.md) and
[Dec21040/findings.md](Dec21040/findings.md), each opening section.

### 4.7 Buckets 1 and 2 are empty across all four

Stated in full in §3 rather than omitted. Both are 0 in all four binaries
because these are **statically linked kernel servers, not `MH_EXECUTE`
helpers**: no crt/dyld startup routines, and no `__picsymbol_stub` section for
the stub-range check to match against. The crt/dyld routines live in the bundle
stubs instead, two per stub. This matches the previous report's result for all
five of its binaries; it is a property of the artifact shape, not of any driver.

---

## 5. Decomposition proposal

Ranked by **actionable divergence with runtime consequence** - the criterion the
previous report settled on. The tie-breaker is that an unmapped or bucket-6
entry with a documented, evidenced cause and no runtime consequence (a libgcc
helper, a preprocessor exclusion) is **a result, not work**.

Raw counts do not rank this batch: all four are 47-48 mapped / 2 unmapped / 0
dup / 0 disputed, and their exact-name match rates sit within 0.1 points of each
other. On the criterion, one driver separates cleanly from the rest.

### 1. `drvPPCGem` - the only demonstrated runtime consequence

- **Measured:** 48 mapped / 2 unmapped / 0 dup / 0 disputed; 9152 mapped bytes
  against 36 unmapped. 157 functions.
- **Exact-name match: 49 of 51 (96.1%)** - joint-highest in the batch.
- **Bucket 6 after hand resolution: 2** - `_crc416` (a genuine driver-code
  absence) and `__udivdi3` (libgcc, expected).
- **Drift or different version?** Neither. This is a **reimplementation**, and
  the divergence is algorithmic: `GemEnetPrivate.m:135` implements a different
  CRC under Apple's function name, with **0/5 agreement** on the bucket it
  programs (§4.3).
- **The follow-on spec's job:** replace `_mace_crc` with the `crc416`/`mace_crc`
  pair Apple shipped - `MaceEnetPrivate.m:1510`/`:1548` in this same tree is a
  working, byte-verified template - and reconcile
  `_addToHashTableMask:`/`_removeFromHashTableMask:` with the hash-index
  derivation that pair implies. This is the only item in the batch that changes
  what runs.

### 2. `drvPPCDec21040` - largest structural surface, no correspondence gap

- **Measured:** 48 mapped / 2 unmapped / 0 dup / 0 disputed; 10244 mapped bytes
  against 36 unmapped. 161 functions.
- **Exact-name match: 49 of 51 (96.1%)**.
- **Bucket 6 after hand resolution: 0** - the only driver in the batch with
  nothing left over, not even `__udivdi3`.
- **Drift or different version?** Neither observable. Three classes, three
  matching `@implementation` sets, no placement difference under a
  class-insensitive check.
- **The follow-on spec's job:** packaging (§4.6, `files.ppc:118-121`), and a
  decision on the two `#ifdef DEBUG` methods and the two guarded static C
  helpers - keep them dormant or delete them. Both are decisions, not gaps. It
  ranks second only because it has the most structure to carry through a
  packaging change: three classes across four source files.

### 3. `drvPPCMace` - packaging only; the control for §4.3

- **Measured:** 47 mapped / 2 unmapped / 0 dup / 0 disputed; 12372 mapped bytes
  against 36 unmapped. 183 functions, the largest count in the batch.
- **Exact-name match: 48 of 50 (96.0%)**.
- **Bucket 6 after hand resolution: 1** (`__udivdi3`). All five of its other C
  helpers are confirmed by disassembly, not by name.
- **Drift or different version?** Neither. Zero divergence in the driver's own
  code - this is Apple's own Darwin source, and it is the control that makes
  Gem's divergence attributable to Gem.
- **The follow-on spec's job:** packaging (§4.6, `files.ppc:109-111`). Nothing
  on correspondence grounds.

### 4. `drvPPCGNic` - nothing on correspondence grounds

- **Measured:** 47 mapped / 2 unmapped / 0 dup / 0 disputed; 8156 mapped bytes
  against 36 unmapped. 156 functions, the smallest in the batch.
- **Exact-name match: 48 of 50 (96.0%)**.
- **Bucket 6 after hand resolution: 1** (`__udivdi3`).
- **Drift or different version?** Neither observable. Like Gem it is a
  reimplementation, but unlike Gem no probe found a divergent body.
- **The follow-on spec's job:** none on correspondence grounds, and it does not
  even carry the packaging gap - it is already a `.drvproj` under
  `src/drivers-ppc`. Worth a spec only for a compile attempt once a PowerPC
  toolchain exists.

### The limit of this ranking

§4.3 was found because a 68-byte compiled body was too small to be the loop the
source contained, which prompted a disassembly. **Nothing in this method
systematically checks method bodies for behavioural equivalence** - the source
maps match names, addresses and sizes. GNic and Gem are both reimplementations
and only Gem was probed at body level, so GNic's clean correspondence bounds the
*structure*, not the behaviour. A per-driver spec for either should assume
body-level divergence is possible until a compile-and-compare exists.

### Recorded follow-on questions, not chased

Per spec §5.1 these are recorded and left alone:

- Why Apple's `DECchip2104x` factors its private interface without the
  underscore-prefixed helper set the other four share (§6, question 4).
- Whether the byte-identical `crc416`/`mace_crc` pair in three separate binaries
  came from a shared header, a shared `.m`, or copy-paste - the binaries cannot
  distinguish these.
- `drvPPCGNic` writes hardware register offsets as inline numeric literals
  (`GNicEnet.m` and `GNicEnetPrivate.m`, 79 call sites) and its only named
  register constant is an unused `kGNicRegExample` placeholder carrying two
  `TODO` comments, where `drvPPCGem` defines 61 named constants. A source
  hygiene observation with no measured correspondence consequence.

---

## 6. The `IOEthernet` family

With `drvPPCBMac` from the previous spec, **five `IOEthernet` subclasses are now
measured**. This section is the evidence no single-driver measurement can
produce. `drvPPCBMac` is read from its committed
[BMac/source-map.json](BMac/source-map.json) and
[BMac/findings.md](BMac/findings.md) and from [report.md](report.md); **it is
not re-measured**.

Selector sets are the selector part of each binary's `-[Class selector]` /
`+[Class selector]` symbols. Two derivations were run: from the five committed
source maps (`mapped` union `unmapped`, as the plan specifies), and
independently from the five `_reloc` symbol tables via `read_macho`. They differ
by exactly one selector per binary - the address-0x0 symbol from §1, which a
source map cannot carry. **The symbol-table derivation is the one reported
below**, since it is the complete picture of what Apple shipped; where the two
disagree it is called out.

```
GNic       objc symbols  50  distinct selectors  50
Gem        objc symbols  51  distinct selectors  51
Mace       objc symbols  50  distinct selectors  50
Dec21040   objc symbols  51  distinct selectors  44
BMac       objc symbols  67  distinct selectors  67
```

Only Dec21040's symbol count exceeds its distinct-selector count, by 6 - its
three classes' shared overrides (§2).

**This section is bounded to spec §4.6's four questions.** Anything beyond them
is a recorded follow-on question (§5), not chased.

### Question 1 - the selector set all five implement

**30 selectors**, the de facto `IOEthernet` contract as Apple actually shipped
it on PowerPC:

```
_allocateMemory                  free
_initChip                        getPowerManagement:
_initRxRing                      getPowerState:
_initTxRing                      initFromDeviceDescription:
_receiveInterruptOccurred        kernelServerInstance
_resetChip                       probe:
_transmitInterruptOccurred       receivePacket:length:timeout:
_transmitPacket:                 removeMulticastAddress:
addMulticastAddress:             resetAndEnable:
disableMulticastMode             sendPacket:length:
disablePromiscuousMode           serviceTransmitQueue
enableMulticastMode              setPowerManagement:
enablePromiscuousMode            setPowerState:
                                 timeoutOccurred
                                 transmit:
                                 transmitQueueCount
                                 transmitQueueSize
```

Two notes on reading this list. `kernelServerInstance` is the build-generated
accessor (§3) and is universal only because the tooling emits it everywhere;
`driverKitVersionFordrv<Name>` is its pair but embeds the driver name, so it
lands under "per-driver" by construction rather than by design. And the
underscore-prefixed entries are *private-category* methods, so the 30 split
**22 unprefixed / 8 underscore-prefixed** - the unprefixed 22 (21 of them plus
the build-generated `kernelServerInstance`) are the public contract, and the 8
underscored (`_allocateMemory`, `_initChip`, `_initRxRing`, `_initTxRing`,
`_receiveInterruptOccurred`, `_resetChip`, `_transmitInterruptOccurred`,
`_transmitPacket:`) are a shared *implementation* convention, which is itself
the interesting result: five separately-authored drivers factor that much of
their private layer identically.

From the source-map derivation this set is 28 rather than 30: `_allocateMemory`
and `probe:` drop out because each is the address-0x0 symbol in some binary
(GNic's `_allocateMemory`; Gem's, Mace's and BMac's `probe:`). That is a
measurement artifact of §1, not a gap.

### Question 2 - implemented by some but not all

24 selectors, from the source-map derivation (the artifact above shifts
`_allocateMemory` and `probe:` into this band; both are universal in the
binaries):

| In | Selector | Drivers |
| --- | --- | --- |
| 4 | `_disableAdapterInterrupts` | GNic, Gem, Mace, BMac |
| 4 | `_enableAdapterInterrupts` | GNic, Gem, Mace, BMac |
| 4 | `_getStationAddress:` | GNic, Gem, Mace, BMac |
| 4 | `_packetToDebugger:` | GNic, Gem, Mace, BMac |
| 4 | `_receivePacket:length:timeout:` | GNic, Gem, Mace, BMac |
| 4 | `_receivePackets:` | GNic, Gem, Mace, BMac |
| 4 | `_sendPacket:length:` | GNic, Gem, Mace, BMac |
| 4 | `_startChip` | GNic, Gem, Mace, BMac |
| 4 | `_stopReceiveDMA` | GNic, Gem, Mace, BMac |
| 4 | `_stopTransmitDMA` | GNic, Gem, Mace, BMac |
| 4 | `_updateDescriptorFromNetBuf:Desc:ReceiveFlag:` | GNic, Gem, Mace, BMac |
| 4 | `_allocateMemory` | Gem, Mace, Dec21040, BMac |
| 3 | `_addToHashTableMask:` | Gem, Mace, BMac |
| 3 | `_removeFromHashTableMask:` | Gem, Mace, BMac |
| 3 | `_dumpRegisters` | Gem, Mace, BMac |
| 3 | `_restartReceiver` | GNic, Gem, BMac |
| 3 | `_restartTransmitter` | GNic, Gem, BMac |
| 3 | `_sendDummyPacket` | GNic, Gem, BMac |
| 3 | `interruptOccurred` | GNic, Gem, Dec21040 |
| 2 | `_dumpDesc:Size:` | Mace, BMac |
| 2 | `_monitorLinkStatus` | GNic, Gem |
| 2 | `allocateNetbuf` | Mace, Dec21040 |
| 2 | `interruptOccurredAt:` | Mace, BMac |
| 2 | `probe:` | GNic, Dec21040 |

The dominant pattern is an eleven-selector private block shared by GNic, Gem,
Mace and BMac and absent from Dec21040 - question 4.
`_addToHashTableMask:`/`_removeFromHashTableMask:` on Gem, Mace and BMac is
exactly the trio whose CRC helper is byte-identical (§4.3, §4.4).
`interruptOccurred` versus `interruptOccurredAt:` is the DriverKit
direct-versus-indirect interrupt convention splitting the five. The
`_allocateMemory` and `probe:` rows are the address-0x0 artifact, not real
partial sharing.

### Question 3 - per-driver selectors, indicating hardware-specific behaviour

```
GNic: 4       _addMulticastAddress:, _findMulticastAddress:Index:,
              _removeMulticastAddress:, driverKitVersionFordrvPPCGNic
Gem: 2        _updateGemHashTableMask, driverKitVersionFordrvPPCGem
Mace: 3       _restartChip, _updateHashTableMask, driverKitVersionFordrvPPCMace
Dec21040: 12  _initRegisters, _loadSetupFilter:, _setAddressFiltering:,
              _setInterface:, _startReceive, _startTransmit,
              disableAdapterInterrupts, enableAdapterInterrupts,
              getStationAddress:, pendingTransmitCount, selectInterface,
              driverKitVersionFordrvPPCDec21040
BMac: 18      _dump_srom, _setDuplexMode:, _updateBMacHashTableMask,
              miiCheckZeroBit, miiFindPHY:, miiInitializePHY:,
              miiOutThreeState, miiReadBit, miiReadWord:reg:phy:,
              miiResetPHY:, miiRestartAutoNegotiation:,
              miiWaitForAutoNegotiation:, miiWaitForLink:, miiWrite:size:,
              miiWriteWord:reg:phy:, releaseDebuggerLock,
              reserveDebuggerLock, driverKitVersionFordrvPPCBMac
```

One entry in each list - `driverKitVersionFordrv<Name>` - is per-driver by
construction, not by hardware. Discounting it: GNic 3, Gem 1, Mace 2, Dec21040
11, BMac 17.

BMac's 17 are dominated by its 12-method `(MII)` category - the only driver of
the five with a media-independent-interface PHY layer, matching
[report.md](report.md)'s class inventory, which shows BMac as the only binary
with two categories. Its `reserveDebuggerLock`/`releaseDebuggerLock` pair
reflects its role as the kernel debugger's network transport. GNic's three are a
multicast-list layer the others do not carry. Gem's single
`_updateGemHashTableMask` and Mace's `_updateHashTableMask` are the same
function under driver-specific names - a naming difference, not a capability
difference.

### Question 4 - is any driver missing a selector the other four share?

Re-derived both ways. From the `_reloc` symbol tables:

```
GNic: 0
Gem: 0
Mace: 0
BMac: 0
Dec21040: 11
      _disableAdapterInterrupts        _sendPacket:length:
      _enableAdapterInterrupts         _startChip
      _getStationAddress:              _stopReceiveDMA
      _packetToDebugger:               _stopTransmitDMA
      _receivePacket:length:timeout:   _updateDescriptorFromNetBuf:Desc:ReceiveFlag:
      _receivePackets:
```

**Four of the five are missing nothing.** The source-map derivation reports one
extra for GNic (`_allocateMemory`), which is the address-0x0 artifact of §1 and
**not** a gap: `-[GNicEnet(Private) _allocateMemory]` is in the binary's symbol
table and is defined at `GNicEnetPrivate.m:115`.
[GNic/findings.md](GNic/findings.md) records this. Checking both derivations is
what distinguishes the artifact from a real gap.

**Dec21040's 11 are not a reconstruction gap either.** Both sides of this
comparison are Apple's own binaries, so a "missing" selector means Apple's
`DECchip2104x` does not implement it - not that our source lost it. Three of the
eleven exist on Dec21040 under the unprefixed name (question 3):
`disableAdapterInterrupts`, `enableAdapterInterrupts` and `getStationAddress:`
are public methods there where the other four carry private `_`-prefixed
versions. The remaining eight are functions Dec21040 factors differently -
`_initRegisters`, `_loadSetupFilter:`, `_setAddressFiltering:`, `_startTransmit`
and `_startReceive` are its own equivalents. It is the only non-Apple-integrated
part in the set (a DEC 21x4x PCI NIC rather than a Mac-integrated Ethernet
controller), and the only one with a class hierarchy. Recorded as a follow-on
question (§5), not chased.

**On the source side the answer is uniform.** `selector_check.py`'s `missing`
list is exactly the two build-generated accessors for each of GNic, Gem, Mace
and Dec21040 (§3), and for BMac in [report.md](report.md). So **no driver's
source is missing any family-shared selector** - the only selectors present in
any of the five binaries and absent from our sources are the ten tool-emitted
accessors.

Union across the five: **91 selectors**, distributed 30 / 11 / 7 / 4 / 39 across
in-5 / in-4 / in-3 / in-2 / in-1 from the binary symbol tables (source-map
derivation: 28 / 12 / 7 / 5 / 39, the same 91, shifted by the two address-0x0
selectors).

---

## Acceptance

Spec §5, items 1-8. Every item below was observed in output run for this report;
nothing is claimed that was not run.

### Item 1 - eight analyses complete and published - **PASS**

`complete: true` in every `run-summary.json`, and
`published/analysis-reference-ida.json` present for all eight. Each analysis's
recorded input identity matches spec §1.1's sizes exactly:

```
profile                 complete  published sha256                                                            size
gnic-ppc                    True       True 1D208A3E49CD9DDD6692C81AEACC9C0A5C4BF97F45827EF30DECC495E851B760  size=48432
gnic-bundle-ppc             True       True ED1143591121941501257DB21841CE795014C31C75A2985F9A2F3F49E8D8B159  size=8496
gem-ppc                     True       True D1836DDC7B8B4A8BC8C035B586E6036D054CAAC78380AC6DFB79E7760D644A70  size=58072
gem-bundle-ppc              True       True 20EBB21BB1D2CA3AB28E7F266809BC87A156C745E6A6A2F0E7C0A7DE477DA318  size=8492
mace-ppc                    True       True 3D8C168B0A3F2485D6F9B43D8C1290E0A46974F45A715C2778DA97C3A4BBC87C  size=60744
mace-bundle-ppc             True       True E8F6692C4FDF6EC94FF0BBA8A8C0363DDDDCF179AB31574F0BBAE142540E3B17  size=8496
dec21040-ppc                True       True CA1B142E20E0A26C6D702D2EF3562880AAAB2EF11D15198FB739B37967DCDCEB  size=51872
dec21040-bundle-ppc         True       True 106826E0950C50F8E0853CC584B403E05B5F7C8145F0BFDC5BDECFC128A1850B  size=8504
```

Exit 1 throughout was the expected outcome for reference-only profiles, per spec
§3.1, and is not a failure.

### Item 2 - 0 relocation violations across all eight - **PASS**

`ppc_invariant_check.py --binary ... --analysis ...` re-run against all eight.
Every run's `violations` count is 1, and in every case that 1 is the
symbol/function-start mismatch from `check_functions`, **not** a
relocation-decode violation from `check_document`. Actual relocation violations:
**0 in all eight**.

```
=== gnic-ppc ===         6 scattered/difference-form, 3 HI16/HA16-LO16 pairs, 1022 fused, 1 violations
=== gem-ppc ===          6 scattered/difference-form, 3 HI16/HA16-LO16 pairs, 1165 fused, 1 violations
=== mace-ppc ===         6 scattered/difference-form, 3 HI16/HA16-LO16 pairs, 1249 fused, 1 violations
=== dec21040-ppc ===    12 scattered/difference-form, 6 HI16/HA16-LO16 pairs, 1233 fused, 1 violations
=== all four bundles === 0 scattered, 0 pairs, 0 fused, 1 violations
```

The eight mismatched symbols are enumerated in §1 (the four `_reloc` symbols at
0x0) and §3 (`__mh_bundle_header` in all four stubs). They are not required to
be zero.

### Item 3 - four maps load against a scoped reference analysis - **PASS**

Each map loaded via `load_source_map` against its reference analysis restricted
to the addresses that map covers across **all four map categories** (`mapped`
union `unmapped` union `duplicate_candidates` union `boundary_disputed`), with
the repo root:

```
GNic OK (156 functions -> 49 scoped)
Gem OK (157 functions -> 50 scoped)
Mace OK (183 functions -> 49 scoped)
Dec21040 OK (161 functions -> 50 scoped)
```

Scoping is required, not a weakening: `--scope-to-objc` maps do not claim the
unnamed jump islands and `load_source_map` enforces an *exact* partition, so an
unscoped analysis fails. Over everything each map does claim, the check verifies
the full partition, names, sizes, source-line bounds and the analysis's SHA-256
identity. Item 5 independently accounts for every function scoped out - 107 +
107 + 134 + 111 - so the pair together covers all 657 functions.

### Item 4 - duplicates and disputes enumerated - **PASS**

`duplicate_candidates` is **0 for all four**. `boundary_disputed` is **0 for all
four**. Nothing to enumerate; the counts are in §1's summary table, and each
`findings.md` records them independently.

The one symbol per binary at address 0x0 (§1) is recorded as a
`boundary_disputed` *candidate* by `ppc_invariant_check.py`, not by the source
map, which is why the map's own count is 0. Each is enumerated with its source
site in §1 and in the relevant `findings.md`.

### Item 5 - every function in exactly one bucket, buckets sum to total - **PASS**

All four bucket tables re-derived for this report; all four print
`RECONCILES: yes`. Full table in §1; counted totals are 156, 157, 183 and 161
against IDA's totals of 156, 157, 183 and 161.

Four bucket-6 entries carry an explicitly recorded disposition rather than a
source site: `__udivdi3` in GNic, Gem and Mace (libgcc, expected - §4.2), and
`_crc416` in Gem (a genuine driver-code absence with an evidenced cause -
§4.3). None is unexamined.

### Item 6 - binrecon suite green - **PASS**

```
$ PYTHONPATH=tools/binrecon python -m pytest tools/binrecon/tests -q
826 passed, 4 skipped in 50.25s
```

818 was the pre-Task-1 baseline. `test_ppc_profile_inventory` was updated from
17 to 25 profile names and passes; the eight new profiles each add one instance
of the parametrized `test_ppc_profiles_are_reference_only_ida_runs`, which is
the +8.

### Item 7 - report carries all six parts, §5 names each spec with its gap - **PASS**

§1 Correspondence (spec §4.1), §2 Class inventory (§4.2), §3 Non-Objective-C
remainder (§4.3), §4 Findings (§4.4), §5 Decomposition proposal (§4.5), §6 The
`IOEthernet` family (§4.6). §5 names four per-driver follow-on specs, each with
its measured mapped/unmapped counts, its bucket-6 residue after hand resolution,
and a drift-versus-different-version assessment.

### Item 8 - family comparison covers all five, answers the missing-selector question - **PASS**

§6 covers GNic, Gem, Mace, Dec21040 and BMac, and answers spec §4.6's four
questions in order. For the missing-selector question it states, for each of the
four measured here: GNic **0**, Gem **0**, Mace **0**, Dec21040 **11** (with the
cause characterised, and recorded as a follow-on question rather than chased);
BMac, carried from the previous spec, is likewise **0**. The section is bounded
to the four questions, per spec §5.1.

### Not claimed

- **No PowerPC compile.** `parity_check.py` and `import_check.py` need a rebuilt
  binary and remain unusable. Nothing here is compile-verified, and no claim is
  made that any of these four drivers builds or runs.
- **No behavioural equivalence for mapped bodies.** The source maps match names,
  addresses and sizes. §4.3 was found by a targeted disassembly, not by the
  method; §5's closing note states what that bounds.
- **The packaging gap is recorded, not closed** (§4.6).
- **`drvPPCBMac` was not re-measured** - §6 reads it from its committed source
  map, its `findings.md` and [report.md](report.md).
- **Dec21040's 11-selector divergence from the family is Apple's own factoring,
  not a reconstruction gap**, and no cause beyond that is assigned (§6).
