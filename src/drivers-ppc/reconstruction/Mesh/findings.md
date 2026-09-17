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
mapped 70 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPCMeshKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCMeshVersion driverKitVersionFordrvPPCMesh]'] 16
```

**This is down from `mapped 66 unmapped 6` at first measurement.** All four of this driver's absent
Objective-C methods have been written, and each now maps:

```
-[AppleMesh_SCSI ResetHardware:reason:]                -> MESH_DBDMA.m:1223
-[AppleMesh_SCSI ResetMESH:reason:]                    -> MESH_DBDMA.m:3470
-[AppleMesh_SCSI IssueAbort]                           -> MESH_DBDMA.m:3822
-[AppleMesh_SCSI killActiveCommandAndResetBus:reason:] -> MESH_DBDMA.m:4555
```

(paths relative to `src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI/`). Only the two build-generated
accessors remain unmapped. See Unmapped detail below for what was written, the class-layout
divergence found while writing it, and every uncertainty carried forward.

- Total functions in the reference analysis (`mesh-ppc`): 173.
- Named Objective-C methods, in scope: 72 -- 70 mapped + 2 unmapped. This matches `read_macho`'s own
  count of ObjC-method-shaped symbols in the binary exactly (see Categories below: 22 + 3 + 6 + 13 +
  10 + 18 = 72).
- Out of scope: 101, composed of 96 unnamed jump islands (bucket 3, see Buckets below) plus 5 named,
  non-Objective-C C functions the `--scope-to-objc` map deliberately does not claim (bucket 6). This
  figure is unchanged: the four written methods moved from `unmapped` to `mapped`, both of which are
  inside the Objective-C scope.
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
would still catch, but a stricter `^[+-]\s*\(` regex misses) gave **73** method definitions at first
measurement: 22 (primary) + 3 (Hardware) + 7 (HardwarePrivate) + 13 (MeshInterrupt) + 11 (Mesh) + 17
(Private). **It is now 77** -- the four written methods added one to `Hardware`, two to `Mesh` and
one to `Private` -- matching `selector_check.py`'s current "our definitions: 77" exactly (see
Selector check below).

Of those 77 source methods:

- 70 have an address-matching counterpart the source map places (`mapped`), up from 66.
- 7 remain "extra": source method definitions with no binary selector at all. These are unchanged
  from first measurement and are **not** gaps in the reconstruction -- see Selector check for each.
- 0 binary selectors now lack an exact-selector source match, down from 4.

The four that were previously "same-named-but-different-selector siblings of a binary-only selector"
are no longer that. Source still defines the one-keyword `-[AppleMesh_SCSI(Hardware)
ResetHardware:]` and `-[AppleMesh_SCSI(Mesh) ResetMESH:]`, and still defines
`-[AppleMesh_SCSI(Mesh) AbortActiveCommand]` / `AbortDisconnectedCommand]`; those four stay in the
"extra" list, because the binary genuinely has no counterpart for them. What changed is that the
binary's two-keyword `ResetHardware:reason:` / `ResetMESH:reason:`, its `IssueAbort`, and its
`killActiveCommandAndResetBus:reason:` now each have their own exact-selector definition alongside
them, rather than only a near-miss relative.

77 - 70 mapped = 7 "extra" source methods, consistent with `selector_check.py`'s count. That leaves
the reference binary's own unmapped set at 2, both build-generated -- the number reported by the
source map above.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and the reference analysis
passed to it, so verifying a `--scope-to-objc` map requires scoping the analysis to the same covered
addresses first: the map does not claim the 96 unnamed jump islands or the 5 non-Objective-C C
functions, and the bucket reconciliation below accounts for those 101 separately.

```
analysis functions 173 -> scoped 72
load_source_map OK
```

72 is exactly 70 mapped + 2 unmapped, confirming the map's covered-address set is precisely the
72-selector ObjC scope claimed above. The scope itself is a property of the binary and did not
change; only the split between `mapped` and `unmapped` did.

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/mesh-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/Mesh/source-map.json`:

```
total functions: 173
  mapped: 70
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 96
  4-build-generated-class: 2
      0x4cec  +[drvPPCMeshKernelServerInstance kernelServerInstance]  (20 bytes)
      0x4d00  +[drvPPCMeshVersion driverKitVersionFordrvPPCMesh]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 5
      0xc0  _EvLog  (292 bytes)
      0x204  _Pause  (388 bytes)
      0x3c8  _serviceTimeoutInterrupt  (124 bytes)
      0x16b4  _getConfigParam  (132 bytes)
      0x1758  _GetSCSICommandLength  (132 bytes)
counted: 173
RECONCILES: yes
```

Bucket 6 is down from 9 entries to 5, and **bucket 6 now contains no Objective-C methods at all**.
The four that were there -- `ResetHardware:reason:` (`0x1164`), `ResetMESH:reason:` (`0x3348`),
`IssueAbort` (`0x3b4c`) and `killActiveCommandAndResetBus:reason:` (`0x480c`) -- have been written
and are counted under `mapped`. The five that remain are all plain C functions, which the
`--scope-to-objc` map never claims (see Group A below).

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because `drvPPCMesh_reloc` is a statically
linked kernel server, not an `MH_EXECUTE` helper: it carries no crt/dyld startup routines and its
analysis has no `__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand against every bucket-6
entry (`grep -n <symbol> src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m`). Since the four
absent methods were written, this bucket no longer splits into two groups -- **all 5 remaining
entries are Group A, and all 5 move to bucket 5.** Group B, the four unmapped Objective-C methods,
is now empty; it is retained below as a record of what was gap and how it was closed.

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

**Group B -- now empty.** These 4 Objective-C methods were bucket-6 gaps at first measurement,
because none had a source site with the *same selector* -- only a related, differently named or
different-arity sibling. All four have since been written and now appear under `mapped`:

| Binary selector | Size | Was | Now written at |
| --- | --- | --- | --- |
| `-[AppleMesh_SCSI ResetHardware:reason:]` | 76 B | source had only one-keyword `ResetHardware:` | `MESH_DBDMA.m:1223`, category `Hardware` |
| `-[AppleMesh_SCSI ResetMESH:reason:]` | 348 B | source had only one-keyword `ResetMESH:` | `MESH_DBDMA.m:3470`, category `Mesh` |
| `-[AppleMesh_SCSI IssueAbort]` | 352 B | source had `AbortActiveCommand` / `AbortDisconnectedCommand`, no `IssueAbort` | `MESH_DBDMA.m:3822`, category `Mesh` |
| `-[AppleMesh_SCSI killActiveCommandAndResetBus:reason:]` | 92 B | source kept `killActiveCommand:` and `threadResetBus:` separate | `MESH_DBDMA.m:4555`, category `Private` |

The sibling methods that made these near-misses all still exist and are unchanged --
`-[AppleMesh_SCSI(Hardware) ResetHardware:]`, `-[AppleMesh_SCSI(Mesh) ResetMESH:]`,
`-[AppleMesh_SCSI(Mesh) AbortActiveCommand]` / `AbortDisconnectedCommand]`,
`-[AppleMesh_SCSI(Private) killActiveCommand:]` (mapped to `0x4879`) and `threadResetBus:` (mapped
to `0x3fe4`). Nothing was renamed or removed to make these map; four new methods were added
alongside them.

Each was placed in the category block matching the binary's own category tag for that selector
(`Hardware`, `Mesh`, `Mesh`, `Private` respectively -- see the Categories table below), verified
against `MESH_DBDMA.m`'s `@implementation` block boundaries. The source map does not check category
placement and would happily map a method written into the wrong block, so this was checked
separately.

## Unmapped detail

**Two** reference selectors have no source-mapped implementation, down from six, and **both
remaining ones are build-generated**:

- `+[drvPPCMeshKernelServerInstance kernelServerInstance]` (20 bytes) -- build-generated: a
  KernelServer wrapper class instance accessor emitted by the driver-kit build tooling, not
  hand-written driver code (same pattern as every other `_reloc` kernel server measured so far).
- `+[drvPPCMeshVersion driverKitVersionFordrvPPCMesh]` (16 bytes) -- build-generated: the DriverKit
  version accessor, likewise tool-emitted.

There is no absent hand-written Objective-C method left in this driver. Both entries match the
`selector_check.py` "missing" list exactly (see Selector check below).

### The four written methods

All four of this driver's previously absent methods were written from their own disassembly in
`drvPPCMesh_reloc`, into both copies of `MESH_DBDMA.m` (the `src/kernel-7/bsd/dev/ppc/` original and
the `src/drivers-ppc/scsi/drvPPCMesh/…` packaged copy; `tools/ppc_package_check.py` reports **no
divergences**, so the two copies stayed identical).

| Method | Size | Category | Line |
| --- | --- | --- | --- |
| `- (IOReturn) ResetHardware : (Boolean) reason : (const char*)` | 76 B | `Hardware` | `MESH_DBDMA.m:1223` |
| `- (IOReturn) ResetMESH : (Boolean) reason : (const char*)` | 348 B | `Mesh` | `MESH_DBDMA.m:3470` |
| `- (void) IssueAbort` | 352 B | `Mesh` | `MESH_DBDMA.m:3822` |
| `- (void) killActiveCommandAndResetBus : (sc_status_t) reason : (const char*)` | 92 B | `Private` | `MESH_DBDMA.m:4555` |

`ResetMESH:reason:` (348 B) and `IssueAbort` (352 B) are the two largest bodies written anywhere in
this reconstruction series.

**None of this is compile-verified.** There is no PowerPC toolchain in this environment; nothing was
compiled, linked or loaded. The source map matching proves the *selectors* match the binary's; it
does not prove the *bodies* do.

### Class-layout divergence in `AppleMesh_SCSI` -- the second in this project

Per spec §3.3, the shipped class's `super_class`, `instance_size` and ivar table were read from the
binary's `__OBJC,__class` / `__OBJC,__instance_vars` sections before any ivar access was written,
and compared against our `@interface` in `MESH_DBDMA.h:668`.

```
class AppleMesh_SCSI  super="IOSCSIController"  instance_size=816  ivar_count=43
```

- **Superclass agrees.** The binary says `IOSCSIController`; `MESH_DBDMA.h:668` declares
  `@interface AppleMesh_SCSI : IOSCSIController < IOPower >`. This is unlike `IOSmartDisplay` in the
  IODisplay spec, where the superclass itself diverged.
- **The ivar layout does not agree.** Eight of the binary's 43 ivar names have no counterpart in our
  `@interface`, and our `@interface` carries one the binary does not:

```
in binary but NOT in our @interface:
    gKernelInterruptPort  gIncomingCmdQ  gIncomingCmdLock  gPendingCmdQ
    gDisconnectedCmdQ  gMsgOutPtr  gMsgInTagType  gMsgInTag

in our @interface but NOT in the binary:
    abortCmdQ  incomingCmdQ  incomingCmdLock  pendingCmdQ
    disconnectedCmdQ  msgOutPtr  msgInTagType  msgInTag
```

Two distinct things are mixed in those lists, and they matter differently:

1. **A pure naming divergence, harmless.** Seven of the eight pairs are the same ivar under a
   different spelling: Apple prefixes with `g` where our header does not (`gIncomingCmdQ` /
   `incomingCmdQ`, `gIncomingCmdLock` / `incomingCmdLock`, `gPendingCmdQ` / `pendingCmdQ`,
   `gDisconnectedCmdQ` / `disconnectedCmdQ`, `gMsgOutPtr` / `msgOutPtr`, `gMsgInTagType` /
   `msgInTagType`, `gMsgInTag` / `msgInTag`). Same type, same purpose, same relative position.
2. **A real structural divergence.** Apple's class has `gKernelInterruptPort` (`int`, at `+0x264`)
   which ours does not have at all, and ours has `abortCmdQ` (`queue_head_t`, 8 bytes) which Apple's
   does not. Apple also orders the incoming-queue lock *after* `gIncomingCmdQ` (`+0x268` queue,
   `+0x270` lock) where ours declares the lock first.

The net size effect is **-4 bytes (the missing port) +8 bytes (the added queue) = +4**: Apple's
`instance_size` is **816**, and our declarations describe a class of **820**. Every ivar from
`gActiveCommand` onward therefore sits 4 bytes higher in our layout than in Apple's
(Apple `gActiveCommand` `+0x284`, ours `+0x288`).

**This did not block any of the four methods.** Every ivar the four bodies touch --
`gFlagIncompleteDBDMA`, `gActiveCommand`, `gCurrentTarget`, `gCurrentLUN`, `gMsgInState`,
`msgOutPtr`, `gPerTargetData`, `gMsgInFlag`, `meshAddr` -- exists in our `@interface` under a name
our source can compile against, so all four were written rather than recorded as unwritable the way
`findADBDisplayInfoForType:` was. The bodies use *our* spellings (`msgOutPtr`, not `gMsgOutPtr`),
because they must compile against our header, not Apple's.

**But it is a finding in its own right, and the second class-layout divergence this project has
found**, after `IOSmartDisplay`'s in the IODisplay spec. Consequences worth recording:

- Any future reconstruction of a `drvPPCMesh` method that reads an ivar **by offset**, or that
  touches `gKernelInterruptPort`, is not writable against this header as it stands.
- A binary compiled from our header would not be layout-compatible with Apple's shipped
  `AppleMesh_SCSI`, so the two are not interchangeable at the ABI level.
- Which side is "right" is not established here. `abortCmdQ` may be a later revision, or a
  reconstruction-era addition; `gKernelInterruptPort` may have been dropped for the same reason.
  **This is recorded, not resolved** -- settling it needs evidence this task did not gather.

### Uncertainties carried forward

Per spec §3.4, a confident guess is a defect and a recorded uncertainty is a result. These are the
open ones from writing the four bodies:

- **`ResetMESH:reason:` never uses its `reason` argument.** Under the Objective-C ABI this method's
  arguments arrive in `r5` (`resetSCSIBus`) and `r6` (`reason`). Across all 87 instructions of the
  348-byte body at `0x3348`, **`r6` is never referenced** -- not read, not saved, not forwarded.
  `r5` is used: `mr r31, r5` at `0x3370` parks `resetSCSIBus`, and `cmpwi cr1, r31, 0` at `0x33e0`
  is the `if (resetSCSIBus)` branch the written body has. Nor is `r6` forwarded implicitly: every
  call this method makes (`SetSeqReg:`, `GetHBARegsAndClear:`, `dbdma_reset`, `IODelay`, `IOSleep`)
  is single-argument, so nothing could pass it along untouched.

  The parameter is in the selector and in the `__OBJC,__meth_var_types` encoding, so it must be in
  the signature, but the shipped build makes no use of it -- most plausibly a logging call compiled
  out by a disabled `ELG`/`kprintf` macro, which is exactly the shape `EvLog`/`Pause` take elsewhere
  in this file. **That explanation is not confirmed**, because a compiled-out call leaves nothing to
  read. What is confirmed is only that the argument is unused.

  Note the contrast, which was checked rather than assumed: `ResetHardware:reason:` (`0x1164`) also
  never *references* `r6`, but there it is a pass-through, not disuse -- the method calls
  `ResetMESH:reason:` without touching `r5` or `r6`, so both incoming arguments are forwarded
  exactly as received. `killActiveCommandAndResetBus:reason:` does use its `reason`: `mr r29, r6`
  at `0x4828`, restored to `r5` at `0x4844` for the `threadResetBus:` call.
- **`IssueAbort` sets `transferCount0 = 0` where `AbortActiveCommand` sets `1`.** The existing,
  already-mapped `-[AppleMesh_SCSI(Mesh) AbortActiveCommand]` writes `meshAddr->transferCount0 = 1`
  with Apple's own comment "set TC low = 1". `IssueAbort`'s disassembly writes `0`: `li r0, 0` at
  `0x3c14` feeding `stb r0, 0(r9)` at `0x3c18`, where `r9` is `meshAddr` (`lwz r9, 0x244(r30)`).
  The written body follows the binary, not the sibling. Whether the difference is deliberate or an
  Apple-side inconsistency is **not established**.
- **`IssueAbort` preloads the FIFO before issuing the Message Out command; `AbortActiveCommand`
  issues the command first.** In `AbortActiveCommand` the source order is `SetSeqReg :
  kMeshMessageOutCmd`, *then* `meshAddr->xFIFO = kScsiMsgAbort`. In `IssueAbort` the disassembly
  reverses it: `stb r0, 0x20(r9)` with `r0 = 6` (`kScsiMsgAbort` into `xFIFO`) at `0x3c0c`, then the
  counters and `busStatus0`, then `SetSeqReg : kMeshEnableReselect` (`li r5, 0xC`, `0x3c38`),
  `SetIntMask` (`0x3c50`), and only at `0x3c60` `SetSeqReg : kMeshMessageOutCmd` (`li r5, 7`). The
  written body follows the binary. This is a real ordering difference against the sibling method and
  is **recorded, not reconciled**.
- **`IODelay( 25 )` in `ResetMESH:reason:` has no named constant.** The 25-microsecond SCSI reset
  assertion window is a bare literal in the binary, and a search of this tree found no named
  constant for it -- unlike `APPLE_SCSI_RESET_DELAY`, which *was* found and is used for the 250 ms
  settling delay in the same method, and unlike `SR_IOST_RESET` (`= 20`,
  `src/kernel-7/bsd/dev/scsireg.h:806`), which was traced from the bare `li r5, 0x14` in
  `ResetHardware:reason:`. Written as a literal with a comment recording that no name was found, per
  spec §4 item 4. The SCSITape spec's observation that every unknown constant is defined somewhere
  in this tree has held twice before; **this is its counterexample.**
- **`r30` in `killActiveCommandAndResetBus:reason:` is saved but never used.** The 92-byte body
  saves `r30` (`stw r30, var_8(r1)` at `0x4814`) and restores it (`lwz r30, var_8(r1)` at `0x485c`),
  and across all 23 instructions those two are the **only** references to `r30` -- nothing in
  between reads or writes it. Almost certainly a compiler artifact: a callee-saved register
  allocated for a value that was then optimised away. The written body has no counterpart for it,
  which is correct if that reading is right. Recorded because spec §3.2 requires accounting for
  every instruction, and this is the one instruction pair with no source-level counterpart by
  design.

One more uncertainty is inherited rather than new: `defaultSelectionTimeout = 25` in
`ResetMESH:reason:` carries Apple's own `// mlj ??? fix this value` comment, transcribed as-is from
the sibling `ResetMESH:`. That is Apple's uncertainty, not this reconstruction's.

## Invariant check

`ppc_invariant_check.py` output for both binaries, verbatim (`mesh-ppc` re-run after the checker fix
described below; `mesh-bundle-ppc` unaffected by that fix and unchanged from the original run):

```
=== mesh-ppc ===
symbol _AllocateEventLog at 0x0 is not a function start
137 scattered/difference-form relocations (target section verified, field is a difference, not an address)
45 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1559 fused relocations, 1 violations
=== mesh-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

The original run of this checker (before the fix below) reported two additional lines for
`mesh-ppc`:

```
ppc-scattered-ha16-32-absolute at 0x120 and ppc-scattered-lo16-32-absolute at 0x124 reconstruct different values (0x8 vs 0xc)
ppc-scattered-ha16-32-absolute at 0x2b2c and ppc-scattered-lo16-32-absolute at 0x2b28 reconstruct different values (0x18 vs 0x16)
```

(3 violations total in that run.) This driver was the first measured so far where `check_document`
itself, not just `check_functions`' symbol/boundary check, reported non-zero. Rather than take it at
face value, both sites were decoded by hand from the binary:

- **Site 1 (`0x120`/`0x124`/`0x128`):** `0x0120: addis r9,r0,0` (HA16, addend 8) was paired by the
  checker's proximity heuristic with `0x0124: lwz r11,r11,0x600c` (LO16, addend 12) -- but that
  instruction's **base register is r11**, not the `r9` the `addis` actually wrote, so it can never
  have been that `addis`'s real partner. The true partner is `0x0128: lwz r9,r9,0x6008` -- base
  register `r9`, addend 8, matching the `addis` exactly.
- **Site 2 (`0x2b28`/`0x2b2c`/`0x2b30`):** `0x2b2c: addis r9,r0,0` (HA16, addend 24) was paired with
  `0x2b28: addi r25,r9,0x6016` (addend 22) -- but that instruction **precedes** the `addis` and
  belongs to the previous computation. The true partner is `0x2b30: addi r26,r9,0x6018`, addend 24,
  which matches.

Both sites confirm the relocation decode itself was correct throughout; only the checker's
address-proximity pairing heuristic picked the wrong LO16 partner in each case (its own comment
already flagged this pairing as a heuristic, not the Mach-O table's actual structural
`PPC_RELOC_PAIR` association). **This has been fixed in the tool** (`ppc_invariant_check.py`,
commit `151282da`, with two regression tests), and this task's re-run of the checker (verbatim
above) now shows `mesh-ppc` reporting 1 violation instead of 3. No other relocation-decode issue
class (address-form bounds, `__OBJC` pointer targets, jbsr islands, paired-principal counts)
reported anything for either binary, before or after the fix.

**The single remaining violation, `_AllocateEventLog` at `0x0`, is the same anomaly every driver
measured so far has shown -- not a relocation violation.** `MESH_DBDMA.m:298` defines `void
AllocateEventLog( UInt32 size )` (non-static, called once at `MESH_DBDMA.m:460`, inside `#if USE_ELG
&& !CustomMiniMon`), so source exists for it. Because it is a plain C function rather than an
Objective-C method, and the 173 reference-analysis functions never include an entry at `0x0`, it
cannot appear in the source map's `mapped`/`unmapped`/`boundary_disputed` categories at all -- it is
simply absent from both the map and the bucket table. This is the `boundary_disputed` pattern, not a
relocation-decode defect.
> **CORRECTION.** The paragraph above read `ppc_invariant_check.py`'s "is not a function
> start" message as "there is no code at that address", and called the symbol a placeholder
> with an unresolved address. That was wrong, and the same misreading was repeated across five
> merged specs. `__text+0` in `drvPPCMesh_reloc` holds `7c0802a6` -- `mflr r0` -- and it is IDA's
> *analysis* that omits the function there, not Apple's binary that omits the code.
> `read_macho` reports address `0` for every undefined symbol too (`_IOLog`, `_objc_msgSend`,
> ...), which is what made a defined symbol at `__text+0` look empty.
>
> **`_AllocateEventLog` is a real function the analysis does not record, not a phantom.** It is an
> unmapped real function. `MESH_DBDMA.m:298` defines a function of that name, but the correspondence is now
> *unverified* rather than *unnecessary*. Its body is not written here; that is separate work. Nothing was
> re-measured for this correction and no source map was regenerated: the mapped/unmapped
> counts above are unaffected, because IDA never had this function to map. The checker now
> distinguishes the two cases. See
> `src/drivers-ppc/reconstruction/IOADBDevice/findings.md`, "The misreading".


`mesh-bundle-ppc`'s `__mh_bundle_header` at address `0x0` is the standard synthetic bundle-header
symbol Mach-O bundles carry at their load address; not a real function, so not a function start
either -- identical to every other `_reloc`/bundle pair measured in this project.

**Acceptance item 2 (0 relocation violations) is now met for this driver.** With the checker fix
applied, `mesh-ppc` and `mesh-bundle-ppc` both report exactly one item each, and in both cases that
item is the address-`0x0` `boundary_disputed` symbol/function-start pattern, not a relocation
violation. Actual relocation-decode violations: 0 for both binaries, consistent with every driver
measured so far.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 72
our definitions:     77

renames (0):

duplicates (0):

missing (2):
    +[drvPPCMeshKernelServerInstance kernelServerInstance]
    +[drvPPCMeshVersion driverKitVersionFordrvPPCMesh]

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

**The `missing` list is down from 6 entries to 2, and `our definitions` up from 73 to 77** -- the
four written methods, exactly. `missing` now contains only the two build-generated classes.
Critically, `renames` and `duplicates` are both still **0**: the four were added under selectors that
match the binary's exactly, not under near-miss or double-underscored names, so `selector_check.py`
corroborates the source map's own verdict from the binary's raw symbol table rather than from IDA's
export.

"Reference selectors: 72" is unchanged and is a property of the binary. "Our definitions: 77" matches
the method-definition recount (77) above exactly. Characterising each entry, class-insensitively as
well (the class name `AppleMesh_SCSI` and its lower/upper-case variants do not appear misspelled or
differently-cased anywhere in either list, so the class-insensitive re-check changes nothing here):

- `+[drvPPCMeshKernelServerInstance kernelServerInstance]`, `+[drvPPCMeshVersion
  driverKitVersionFordrvPPCMesh]` -- both build-generated (see Unmapped detail); no source
  counterpart exists or is expected for either class.

The four entries below are **no longer missing** -- each now has an exact-selector definition. The
pairings are kept because they explain why the four "extra" siblings are still extra:

- `-[AppleMesh_SCSI(Hardware) ResetHardware:reason:]` (was missing, now written) pairs with
  `-[AppleMesh_SCSI(Hardware)
  ResetHardware:]` (extra): the reference binary's two-keyword selector had no source match; source's
  one-keyword selector still has no binary match. Same method name, genuinely different selector (different
  argument count), not a rename or duplicate in `selector_check.py`'s own sense (which reserves
  "renames" for exact-selector matches at different addresses).
- `-[AppleMesh_SCSI(Mesh) ResetMESH:reason:]` (was missing, now written) pairs with
  `-[AppleMesh_SCSI(Mesh) ResetMESH:]` (extra): identical pattern.
- `-[AppleMesh_SCSI(Mesh) IssueAbort]` (was missing, now written) pairs with the two extra
  `-[AppleMesh_SCSI(Mesh) AbortActiveCommand]` / `-[AppleMesh_SCSI(Mesh) AbortDisconnectedCommand]`:
  the binary's single no-argument selector corresponds, in the pre-existing source, to two
  separately named no-argument methods with completely different selector names (not merely
  different arity). Those two remain, unmodified; `IssueAbort` was written alongside them, following
  its own disassembly rather than being synthesised from either.
- `-[AppleMesh_SCSI(Private) killActiveCommandAndResetBus:reason:]` (was missing, now written) has
  no "extra" counterpart in this list, because its two source-side relatives (`killActiveCommand:`
  and `threadResetBus:`) are *not* extra -- both already have their own exact-selector match in the
  binary and are counted in `mapped` (addresses `0x4879` and `0x3fe4` respectively). The written
  method is the combined-selector wrapper that calls them both, matching the binary's 92-byte body.
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
mapped 70 unmapped 2 dup 0 disputed 0
mapped per category: {'(primary)': 70}
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

Total: 22 + 3 + 6 + 13 + 10 + 18 = 72, matching the source map's 70 mapped + 2 unmapped exactly.
(This split is a property of the binary and is unchanged from first measurement.)

To attribute each of the map's 70 `mapped` addresses to a real category (not just the flattened
`(primary)` IDA gives), each mapped entry's address was looked up a second time directly against
`read_macho`'s symbol table (which retains the category tag), joining on address rather than on name:

```
mapped by real category:   {'(primary)': 20, 'Hardware': 3, 'HardwarePrivate': 6, 'MeshInterrupt': 13, 'Mesh': 10, 'Private': 18}
unmapped by real category: {'(primary)': 2}
```

20 + 3 + 6 + 13 + 10 + 18 = 70, matching `mapped` exactly:

| Category | Mapped | Unmapped | Total (this class) |
| --- | --- | --- | --- |
| `(primary)` | 20 | 0 | 20 |
| `Hardware` | 3 | 0 | 3 |
| `HardwarePrivate` | 6 | 0 | 6 |
| `MeshInterrupt` | 13 | 0 | 13 |
| `Mesh` | 10 | 0 | 10 |
| `Private` | 18 | 0 | 18 |
| **`AppleMesh_SCSI` subtotal** | **70** | **0** | **70** |
| build-generated (`drvPPCMeshKernelServerInstance`, `drvPPCMeshVersion`) | 0 | 2 | 2 |
| **Grand total** | **70** | **2** | **72** |

This reconciles exactly against both the `read_macho`-derived category counts above (22 = 20
`AppleMesh_SCSI` primary + 2 build-generated classes' own primary-category methods) and the source
map's `mapped 70 unmapped 2` headline.

**Every category of `AppleMesh_SCSI` is now fully mapped**, and the only two unmapped selectors in
the whole binary belong to the two build-generated classes. At first measurement `MeshInterrupt` was
the only category with a perfect 1:1 match; `Hardware` (2/3), `Mesh` (8/10) and `Private` (17/18)
each had a hole, and writing the four methods closed all three. The driver the brief called "the
most category-fragmented measured so far" now has no unmapped hand-written method in any category.

**What this table does not prove.** The `mapped by real category` join is on address, and takes the
category from the *binary's* symbol table -- so it shows which binary selectors are now mapped, not
where in our source they were written. The source map does not check category placement and would
map a method written into the wrong `@implementation` block just as happily. Placement was therefore
checked separately, against `MESH_DBDMA.m`'s own block boundaries:

```
444:@implementation AppleMesh_SCSI          1042:@end
1046:@implementation AppleMesh_SCSI( Hardware )         1468:@end
1519:@implementation AppleMesh_SCSI( HardwarePrivate )  2212:@end
2217:@implementation AppleMesh_SCSI( MeshInterrupt )    3396:@end
3399:@implementation AppleMesh_SCSI( Mesh )             4050:@end
4053:@implementation AppleMesh_SCSI( Private )          4724:@end
```

Line 1223 falls inside `Hardware`, 3470 and 3822 inside `Mesh`, and 4555 inside `Private` --
matching each selector's category tag in the binary. That is the check; the table above is
corroboration that the corresponding binary selectors stopped being unmapped.
