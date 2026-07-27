# drvPPCMesh reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCMesh.config/drvPPCMesh` | 8496 | `681289A4691DD6D092D9CE4F98CF3D96690EC0AD8C850D54E587469A430E7B4F` |
| `drvPPCMesh.config/drvPPCMesh_reloc` | 66712 | `3B7251FBD0B83A14655E011B5033A4582DE88CCAC6B600FB3F940BDFF7127173` |

Both sizes were measured and matched by Task 1's `binrecon validate`; the source map's own
`reference_sha256` field (`src/drivers-ppc/reconstruction/Mesh/source-map.json`) reproduces the
`drvPPCMesh_reloc` hash above exactly.

`src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m` is built into the kernel itself: the sole
entry for this driver in `src/kernel-7/conf/files.ppc` is

```
bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m		optional mk_hasdrivers
```

i.e. it is compiled into the kernel binary whenever the `mk_hasdrivers` kernel-configuration option
is set, not built as its own standalone target. The shipped artifact measured here,
`drvPPCMesh.config/drvPPCMesh_reloc`, is nonetheless a separate, statically-linked loadable kernel
server binary (a `KernelServer`-style relocatable Mach-O), matching the pattern already established
for `drvPPCGem`/`drvPPCCuda`/etc. in this reconstruction effort: the driver's source lives inside the
monolithic kernel source tree under `mk_hasdrivers`, but Apple additionally shipped it as its own
loadable `.config` bundle pair for DriverKit-style dynamic loading.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCMesh_reloc`, scoped to the Objective-C methods found in that binary:

```
mapped 66 unmapped 6 dup 0 disputed 0
  unmapped: ['-[AppleMesh_SCSI ResetHardware:reason:]'] 76
  unmapped: ['-[AppleMesh_SCSI ResetMESH:reason:]'] 348
  unmapped: ['-[AppleMesh_SCSI IssueAbort]'] 352
  unmapped: ['-[AppleMesh_SCSI killActiveCommandAndResetBus:reason:]'] 92
  unmapped: ['+[drvPPCMeshKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCMeshVersion driverKitVersionFordrvPPCMesh]'] 16
```

- Total functions in the reference analysis (`mesh-ppc`): 173.
- Named Objective-C methods, in scope: 72 -- 66 mapped + 6 unmapped. This matches `read_macho`'s own
  count of ObjC-method-shaped symbols in the binary exactly (see Categories below: 22 + 3 + 6 + 13 +
  10 + 18 = 72).
- Out of scope: 101, composed of 96 unnamed jump islands (bucket 3, see Buckets below) plus 5 named,
  non-Objective-C C functions the `--scope-to-objc` map deliberately does not claim (bucket 6).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0, from the source-map builder's own semantics -- see Invariant check below
  for the one symbol/function-start anomaly (`_AllocateEventLog` at `0x0`) the invariant checker
  separately flags, which never becomes a function-analysis entry and so cannot appear as
  `boundary_disputed` in this map either.

`MESH_DBDMA.m` defines all six implementation blocks for this driver in a single file (there is no
`AppleMesh_SCSICategory.m`-per-category split as with some other drivers):

```
444:@implementation AppleMesh_SCSI
1046:@implementation AppleMesh_SCSI( Hardware )
1506:@implementation AppleMesh_SCSI( HardwarePrivate )
2204:@implementation AppleMesh_SCSI( MeshInterrupt )
3386:@implementation AppleMesh_SCSI( Mesh )
3930:@implementation AppleMesh_SCSI( Private )
```

Counting every `+`/`-` method-signature line at column 0 in each block (including methods with no
explicit return type, e.g. `- free`, which the naive `grep -c "^[+-]"` style used for prior drivers
would still catch, but a stricter `^[+-]\s*\(` regex misses) gives 22 (primary) + 3 (Hardware) + 7
(HardwarePrivate) + 13 (MeshInterrupt) + 11 (Mesh) + 17 (Private) = **73** method definitions, two
more than the plan's orientation figure of 71 and matching `selector_check.py`'s "our definitions: 73"
exactly (see Selector check below). This is the pattern the brief warned about: the plan's counts are
approximate and every prior task has found more than stated.

Of those 73 source methods:

- 66 have an address-matching counterpart the source map places (`mapped`).
- 4 are genuinely absent from the reference binary's selector table (`-[AppleMesh_SCSI
  getIntValues:forParameter:count:]`, `-[AppleMesh_SCSI setIntValues:forParameter:count:]`,
  `-[AppleMesh_SCSI(HardwarePrivate) StartBucket]`; the fourth and fifth,
  `-[AppleMesh_SCSI(Mesh) AbortActiveCommand]` and `-[AppleMesh_SCSI(Mesh)
  AbortDisconnectedCommand]`, bring the "extra" total to 7 -- see Selector check).
- 3 are same-named-but-different-selector siblings of a binary-only selector: source's
  `-[AppleMesh_SCSI(Hardware) ResetHardware:]` (one keyword) vs. the binary's unmapped
  `ResetHardware:reason:` (two keywords); source's `-[AppleMesh_SCSI(Mesh) ResetMESH:]` vs. the
  binary's unmapped `ResetMESH:reason:`; and the pair `-[AppleMesh_SCSI(Mesh) AbortActiveCommand]` /
  `AbortDisconnectedCommand]` vs. the binary's single unmapped `IssueAbort`.
- 73 - 66 mapped = 7 "extra" source methods total, consistent with `selector_check.py`'s count.

That leaves the reference binary's own unmapped set at 6 (4 real methods with no exact-selector
source match + 2 build-generated), the number reported by the source map above.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and the reference analysis
passed to it, so verifying a `--scope-to-objc` map requires scoping the analysis to the same covered
addresses first: the map does not claim the 96 unnamed jump islands or the 5 non-Objective-C C
functions, and the bucket reconciliation below accounts for those 101 separately.

```
analysis functions 173 -> scoped 72
load_source_map OK
```

72 is exactly 66 mapped + 6 unmapped, confirming the map's covered-address set is precisely the
72-selector ObjC scope claimed above.

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/mesh-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/Mesh/source-map.json`:

```
total functions: 173
  mapped: 66
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 96
  4-build-generated-class: 2
      0x4cec  +[drvPPCMeshKernelServerInstance kernelServerInstance]  (20 bytes)
      0x4d00  +[drvPPCMeshVersion driverKitVersionFordrvPPCMesh]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 9
      0xc0  _EvLog  (292 bytes)
      0x204  _Pause  (388 bytes)
      0x3c8  _serviceTimeoutInterrupt  (124 bytes)
      0x1164  -[AppleMesh_SCSI ResetHardware:reason:]  (76 bytes)
      0x16b4  _getConfigParam  (132 bytes)
      0x1758  _GetSCSICommandLength  (132 bytes)
      0x3348  -[AppleMesh_SCSI ResetMESH:reason:]  (348 bytes)
      0x3b4c  -[AppleMesh_SCSI IssueAbort]  (352 bytes)
      0x480c  -[AppleMesh_SCSI killActiveCommandAndResetBus:reason:]  (92 bytes)
counted: 173
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because `drvPPCMesh_reloc` is a statically
linked kernel server, not an `MH_EXECUTE` helper: it carries no crt/dyld startup routines and its
analysis has no `__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand against every bucket-6
entry (`grep -n <symbol> src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m`). This bucket splits
cleanly into two groups.

**Group A -- the 5 named C functions all have an exact-name source definition and move to bucket 5:**

- `_EvLog` -- `MESH_DBDMA.m:317`, `void EvLog( UInt32 a, UInt32 b, UInt32 ascii, char* str )`
  (non-static). 292 bytes, 7 basic blocks in the reference analysis. Source has one early-return
  guard (`if ( g.evLogFlag == 0 ) return;`), a wrap-around check, and a final conditional `kprintf`
  -- three independent branches is consistent with 7 blocks (entry/early-return, main path, two
  wrap-around outcomes, two step-flag outcomes, exit). Logic confirmed by structure, not just name.
- `_Pause` -- `MESH_DBDMA.m:350`, `void Pause( UInt32 a, UInt32 b, UInt32 ascii, char* str )`
  (non-static). 388 bytes, 15 basic blocks. Source calls `EvLog` twice, then runs two 8-iteration
  hex-digit-formatting loops (each with an if/else branch) followed by a bounded copy loop into
  `work[256]` and a final `kprintf`. Two loops-with-branches plus a bounded copy loop is consistent
  with 15 blocks. Logic confirmed by structure.
- `_serviceTimeoutInterrupt` -- `MESH_DBDMA.m:406`, `static void serviceTimeoutInterrupt( void *arg )`
  (static). 124 bytes, 3 basic blocks: straight-line body (`ELG` macro, `IOScheduleFunc`,
  `msg_send_from_kernel`), consistent with the source's lack of any branching besides the `ELG` trace
  macro. Logic confirmed by structure.
- `_getConfigParam` -- `MESH_DBDMA.m:1465`, `static int getConfigParam( id configTable, const char
  *paramName )` (static). 132 bytes, 3 basic blocks: `valueForStringKey:`, an `if (value)` guard
  containing a `strcmp`/`freeString:` pair, and the common return -- matches 3 blocks. Logic
  confirmed by structure.
- `_GetSCSICommandLength` -- `MESH_DBDMA.m:1482`, `static unsigned int GetSCSICommandLength( const
  cdb_t *cdbPtr, unsigned int defaultLength )` (static). 132 bytes, 18 basic blocks: a 6-way `switch`
  on the top 3 bits of the CDB opcode byte, two of whose cases also branch on `defaultLength != 0`
  -- a 6-case switch with two nested ternaries plausibly compiles to this many blocks. Logic
  confirmed by structure, not decompiled instruction-by-instruction (no decompiler was available in
  this session; the reference analysis JSON carries only basic-block/CFG shape, not disassembly
  text, so this confirmation is structural, unlike the deeper byte-level check done for Gem's
  `_mace_crc`).

These 5 match the file's non-inline static/free-function count precisely: grepping
`^static\|^void \|^int \|^unsigned int \|^BOOL \|^UInt32 ` at column 0 finds 7 candidate C function
definitions -- `AllocateEventLog` (298), `EvLog` (317), `Pause` (350), `serviceTimeoutInterrupt`
(406, static), `isCmdTimedOut` (426, static), `getConfigParam` (1465, static),
`GetSCSICommandLength` (1482, static). Of the 4 that are declared `static` (`serviceTimeoutInterrupt`,
`isCmdTimedOut`, `getConfigParam`, `GetSCSICommandLength`), matching the plan's orientation figure of
"4 static C functions" exactly, one -- `isCmdTimedOut` (`MESH_DBDMA.m:426`, called twice, at
`MESH_DBDMA.m:730` and `:753`) -- has **no corresponding symbol anywhere in the 173-function reference
analysis** (checked by name against every function's `names` field). It is small (14 lines) and
called only from within the same file, so the most likely explanation is that the compiler inlined it
at both call sites; it never surfaces as a bucket-6 entry because bucket 6 only lists *named symbols
IDA found*, and an inlined static function leaves no such symbol. This is a real, if unsurprising, gap
between the source's function count and the binary's -- noted here rather than asserted as fact,
since no decompiler was available to directly confirm inlining at the two call sites.

**Group B -- the 4 unmapped Objective-C methods stay in bucket 6 as genuine gaps, not moved to
bucket 5**, because none has a source site with the *same selector* -- only a related, differently
named or different-arity sibling (see Selector check below for the full detail):

- `-[AppleMesh_SCSI ResetHardware:reason:]` (76 bytes) -- source only defines
  `-[AppleMesh_SCSI(Hardware) ResetHardware:]` (`MESH_DBDMA.m:1208`, one keyword, `(Boolean)
  resetSCSIBus`), a different (one-fewer-keyword) selector. No `reason:` variant exists in source.
- `-[AppleMesh_SCSI ResetMESH:reason:]` (348 bytes) -- source only defines
  `-[AppleMesh_SCSI(Mesh) ResetMESH:]` (`MESH_DBDMA.m:3392`, one keyword), same pattern.
- `-[AppleMesh_SCSI IssueAbort]` (352 bytes) -- source has no method named `IssueAbort` at all; the
  closest related methods are `-[AppleMesh_SCSI(Mesh) AbortActiveCommand]` (`MESH_DBDMA.m:3739`) and
  `-[AppleMesh_SCSI(Mesh) AbortDisconnectedCommand]` (`MESH_DBDMA.m:3788`), two separate zero-argument
  methods where the binary appears to have one combined selector.
- `-[AppleMesh_SCSI killActiveCommandAndResetBus:reason:]` (92 bytes) -- source keeps this as two
  separate, already-mapped methods, `-[AppleMesh_SCSI(Private) killActiveCommand:]`
  (`MESH_DBDMA.m:4429`, mapped to `0x4879`) and `-[AppleMesh_SCSI(Private) threadResetBus:]`
  (`MESH_DBDMA.m:3998`, mapped to `0x3fe4`, which itself calls `killActiveCommand:` at
  `MESH_DBDMA.m:3982`). The binary carries an additional combined-selector wrapper this
  repository's source never implements as a single method.

None of these four is a name match at all once arity/selector is considered exactly, so none
qualifies for bucket 5 under the taxonomy established by prior tasks ("a source site genuinely
exists" for the *same* function). They remain real, characterised gaps.

## Unmapped detail

Six reference selectors have no source-mapped implementation:

- `-[AppleMesh_SCSI ResetHardware:reason:]` (76 bytes) -- real gap; source has a same-named,
  different-arity sibling (`ResetHardware:`), not a source-site match. See Buckets/Selector check.
- `-[AppleMesh_SCSI ResetMESH:reason:]` (348 bytes) -- same pattern (`ResetMESH:`).
- `-[AppleMesh_SCSI IssueAbort]` (352 bytes) -- real gap; source splits this into
  `AbortActiveCommand`/`AbortDisconnectedCommand`, neither named `IssueAbort`.
- `-[AppleMesh_SCSI killActiveCommandAndResetBus:reason:]` (92 bytes) -- real gap; source keeps
  `killActiveCommand:` and `threadResetBus:` as two separate, already-mapped methods rather than one
  combined selector.
- `+[drvPPCMeshKernelServerInstance kernelServerInstance]` (20 bytes) -- build-generated: a
  KernelServer wrapper class instance accessor emitted by the driver-kit build tooling, not
  hand-written driver code (same pattern as every other `_reloc` kernel server measured so far).
- `+[drvPPCMeshVersion driverKitVersionFordrvPPCMesh]` (16 bytes) -- build-generated: the DriverKit
  version accessor, likewise tool-emitted.

The last two match the `selector_check.py` "missing" list's two build-generated entries exactly; the
first four match its remaining four "missing" entries exactly (see Selector check below).

## Invariant check

`ppc_invariant_check.py` output for both binaries, verbatim:

```
=== mesh-ppc ===
ppc-scattered-ha16-32-absolute at 0x120 and ppc-scattered-lo16-32-absolute at 0x124 reconstruct different values (0x8 vs 0xc)
ppc-scattered-ha16-32-absolute at 0x2b2c and ppc-scattered-lo16-32-absolute at 0x2b28 reconstruct different values (0x18 vs 0x16)
symbol _AllocateEventLog at 0x0 is not a function start
137 scattered/difference-form relocations (target section verified, field is a difference, not an address)
45 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1559 fused relocations, 3 violations
=== mesh-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

This driver is the first measured so far where `check_document` itself (the byte-order/HI16-LO16
agreement checks) reports non-zero violations, rather than only `check_functions`' symbol/boundary
check. Both are investigated below rather than taken at face value.

**The two HI16/LO16 "mismatches" are checker pairing-heuristic artifacts, not decode defects.**
`ppc_invariant_check.py`'s own pairing function documents that it greedily matches each scattered
HI16/HA16 relocation to the *nearest* scattered LO16 targeting the same section within an 8-byte
window -- a heuristic, not the Mach-O relocation table's actual structural PPC_RELOC_PAIR
association. Dumping the raw relocations around both flagged addresses shows an alternate, exact-value
match exists just outside the greedy choice in each case:

- At `0x120`/HA16 addend `8`: candidates within the window are LO16 at `0x124` (addend `12`,
  distance 4 -- the one the greedy algorithm picks, and reports as a mismatch) and LO16 at `0x128`
  (addend `8`, distance 8 -- exact value match, but farther away). The compiled code at this address
  loads one high-half base register reused by two adjacent field accesses at different offsets
  (`0x124` and `0x128`), which the proximity heuristic cannot disambiguate correctly when the nearer
  candidate happens to belong to a different field access.
- At `0x2b2c`/HA16 addend `24` (`0x18`): candidates are LO16 at `0x2b28` (addend `22`/`0x16`, distance
  4, the checker's pick) and LO16 at `0x2b30` (addend `24`/`0x18`, distance 4, an exact match with a
  tied distance). Because both candidates are equidistant, the checker's `min()` tie-break picks
  whichever appears first in relocation-table order, which here is the wrong one.

In both cases the exact-value candidate exists nearby; this is consistent with the checker's own
documented caveat that its pairing is a heuristic, not with an actual byte-order or sign-extension
defect in `read_macho`'s decode. No other relocation-decode issue class (address-form bounds,
`__OBJC` pointer targets, jbsr islands, paired-principal counts) reported anything for either binary.

**The `_AllocateEventLog` symbol-at-`0x0` is the same anomaly every driver measured so far has
shown.** `MESH_DBDMA.m:298` defines `void AllocateEventLog( UInt32 size )` (non-static, called once
at `MESH_DBDMA.m:460`, inside `#if USE_ELG && !CustomMiniMon`), so source exists for it, but the
reference binary carries only a symbol-table entry at address `0x0` -- a placeholder/unresolved
address, not a genuine boundary dispute affecting any mapped function or method. Because it is a
plain C function rather than an Objective-C method, and the 173 reference-analysis functions never
include an entry at `0x0`, it cannot appear in the source map's `mapped`/`unmapped`/`boundary_disputed`
categories at all -- it is simply absent from both the map and the bucket table.

`mesh-bundle-ppc`'s `__mh_bundle_header` at address `0x0` is the standard synthetic bundle-header
symbol Mach-O bundles carry at their load address; not a real function, so not a function start
either -- identical to every other `_reloc`/bundle pair measured in this project.

Actual relocation-decode violations, once the two pairing-heuristic artifacts and the two symbol/
function-start anomalies are accounted for: 0 for both binaries, consistent with every driver
measured so far.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 72
our definitions:     73

renames (0):

duplicates (0):

missing (6):
    +[drvPPCMeshKernelServerInstance kernelServerInstance]
    +[drvPPCMeshVersion driverKitVersionFordrvPPCMesh]
    -[AppleMesh_SCSI(Hardware) ResetHardware:reason:]
    -[AppleMesh_SCSI(Mesh) IssueAbort]
    -[AppleMesh_SCSI(Mesh) ResetMESH:reason:]
    -[AppleMesh_SCSI(Private) killActiveCommandAndResetBus:reason:]

extra (7):
    -[AppleMesh_SCSI getIntValues:forParameter:count:]
    -[AppleMesh_SCSI setIntValues:forParameter:count:]
    -[AppleMesh_SCSI(Hardware) ResetHardware:]
    -[AppleMesh_SCSI(HardwarePrivate) StartBucket]
    -[AppleMesh_SCSI(Mesh) AbortActiveCommand]
    -[AppleMesh_SCSI(Mesh) AbortDisconnectedCommand]
    -[AppleMesh_SCSI(Mesh) ResetMESH:]
```

Exit code: 0 (`renames`/`duplicates` both empty, so the check does not fail on an internal
inconsistency; it still reports non-empty `missing`/`extra` sets, which this task's brief requires
characterising rather than treating as failure).

"Reference selectors: 72" and "our definitions: 73" match the read_macho category count (72) and the
method-definition recount (73) above exactly. Characterising each entry, class-insensitively as well
(the class name `AppleMesh_SCSI` and its lower/upper-case variants do not appear misspelled or
differently-cased anywhere in either list, so the class-insensitive re-check changes nothing here):

- `+[drvPPCMeshKernelServerInstance kernelServerInstance]`, `+[drvPPCMeshVersion
  driverKitVersionFordrvPPCMesh]` -- both build-generated (see Unmapped detail); no source
  counterpart exists or is expected for either class.
- `-[AppleMesh_SCSI(Hardware) ResetHardware:reason:]` (missing) pairs with `-[AppleMesh_SCSI(Hardware)
  ResetHardware:]` (extra): the reference binary's two-keyword selector has no source match; source's
  one-keyword selector has no binary match. Same method name, genuinely different selector (different
  argument count), not a rename or duplicate in `selector_check.py`'s own sense (which reserves
  "renames" for exact-selector matches at different addresses).
- `-[AppleMesh_SCSI(Mesh) ResetMESH:reason:]` (missing) pairs with `-[AppleMesh_SCSI(Mesh) ResetMESH:]`
  (extra): identical pattern.
- `-[AppleMesh_SCSI(Mesh) IssueAbort]` (missing) pairs with the two extra `-[AppleMesh_SCSI(Mesh)
  AbortActiveCommand]` / `-[AppleMesh_SCSI(Mesh) AbortDisconnectedCommand]`: the binary's single
  no-argument selector corresponds, in source, to two separately named no-argument methods with
  completely different selector names (not merely different arity).
- `-[AppleMesh_SCSI(Private) killActiveCommandAndResetBus:reason:]` (missing) has no "extra"
  counterpart in this list, because its two source-side relatives (`killActiveCommand:` and
  `threadResetBus:`) are *not* extra -- both already have their own exact-selector match in the
  binary and are counted in `mapped` (addresses `0x4879` and `0x3fe4` respectively). The binary
  additionally carries a combined-selector wrapper source never implements as its own method.
- `-[AppleMesh_SCSI getIntValues:forParameter:count:]`, `-[AppleMesh_SCSI
  setIntValues:forParameter:count:]` (extra) -- genuinely extra, three-keyword selectors with no
  missing counterpart at all; the reference binary has no `IntValues`-shaped selector anywhere
  (checked directly against the source map: no `mapped`/`unmapped`/`duplicate_candidates`/
  `boundary_disputed` entry mentions either name).
- `-[AppleMesh_SCSI(HardwarePrivate) StartBucket]` (extra) -- genuinely extra; no missing counterpart.
  The binary has 7 named `HardwarePrivate`-category methods total (see Categories) and this makes 8
  in source, so this is source-only functionality (or renamed/refactored functionality) with no
  binary selector to reconcile against under any name in the missing list.

## Bundle stub

`drvPPCMesh` (the non-relocatable bundle, profile `mesh-bundle-ppc`) analysis has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this small bundle wrapper is
a loader shim with no Objective-C methods and no driver logic of its own, so it carries no
correspondence findings against `AppleMesh_SCSI`. No source map or bucket table was built for it (the
source map and bucket script in this task both target `drvPPCMesh_reloc`, the statically linked
kernel server that actually contains the driver's compiled code), matching the pattern established for
every other bundle pair measured in this project.

## Categories

Step 5's map-derived per-category count comes back entirely under `(primary)`:

```
mapped 66 unmapped 6 dup 0 disputed 0
mapped per category: {'(primary)': 66}
```

This is IDA's export stripping Objective-C category tags, exactly as the brief predicted -- the
source-map builder itself uses `binrecon.macho.read_macho` internally and does correctly place each
method by source file/line, but the reference-names it reports come from the IDA-exported analysis
JSON, which flattens `-[AppleMesh_SCSI(Category) selector]` down to `-[AppleMesh_SCSI selector]`. The
real split was obtained by reading the binary's own symbol table directly with
`binrecon.macho.read_macho` (bypassing the IDA export) and matching the category-tag regex against
every Objective-C-shaped symbol name:

```
{'(primary)': 22, 'Hardware': 3, 'HardwarePrivate': 6, 'MeshInterrupt': 13, 'Mesh': 10, 'Private': 18}
```

Total: 22 + 3 + 6 + 13 + 10 + 18 = 72, matching the source map's 66 mapped + 6 unmapped exactly.

To attribute each of the map's 66 `mapped` addresses to a real category (not just the flattened
`(primary)` IDA gives), each mapped entry's address was looked up a second time directly against
`read_macho`'s symbol table (which retains the category tag), joining on address rather than on name:

```
mapped by real category: {'(primary)': 20, 'Hardware': 2, 'HardwarePrivate': 6, 'MeshInterrupt': 13, 'Mesh': 8, 'Private': 17}
```

20 + 2 + 6 + 13 + 8 + 17 = 66, matching `mapped` exactly. Combining this with the 6 unmapped entries'
own categories (looked up the same way) accounts for the full 72-selector, 6-category split:

| Category | Mapped | Unmapped | Total (this class) |
| --- | --- | --- | --- |
| `(primary)` | 20 | 0 | 20 |
| `Hardware` | 2 | 1 (`ResetHardware:reason:`) | 3 |
| `HardwarePrivate` | 6 | 0 | 6 |
| `MeshInterrupt` | 13 | 0 | 13 |
| `Mesh` | 8 | 2 (`ResetMESH:reason:`, `IssueAbort`) | 10 |
| `Private` | 17 | 1 (`killActiveCommandAndResetBus:reason:`) | 18 |
| **`AppleMesh_SCSI` subtotal** | **66** | **4** | **70** |
| build-generated (`drvPPCMeshKernelServerInstance`, `drvPPCMeshVersion`) | 0 | 2 | 2 |
| **Grand total** | **66** | **6** | **72** |

This reconciles exactly against both the `read_macho`-derived category counts above (22 = 20
`AppleMesh_SCSI` primary + 2 build-generated classes' own primary-category methods) and the source
map's `mapped 66 unmapped 6` headline. `MeshInterrupt` (13 mapped, 0 unmapped) is the only category
with a perfect 1:1 match to its source-block count (13, see Correspondence); every other category has
at least one unmapped/extra selector, consistent with this driver being "the most category-fragmented
driver measured so far" per the brief.
