# drvPPC53c96 / drvApple96_SCSI reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPC53c96.config/drvPPC53c96` | 8496 | `4DC866362B9394DD093FF967C2CA5BF25AC2813E64ECABC5BBDDF44719F69C1D` |
| `drvPPC53c96.config/drvPPC53c96_reloc` | 151244 | `D4E01B128C43F18EB1357FC62874A8B89471C77F2BE4C0D955BE18054700B251` |

Both re-verified locally with `sha256sum` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`; sizes confirmed with `ls -la`.
Both match. This is the largest binary of the five measured, at 151,244 bytes.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPC53c96_reloc`, scoped to the Objective-C methods found in that binary
(91 of the 424 total functions IDA reported):

```
mapped 89 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPC53c96KernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPC53c96Version driverKitVersionFordrvPPC53c96]'] 16
```

**This is down from `mapped 88 unmapped 3` at first measurement.**
`-[Apple96_SCSI maxTransfer]`, previously the one unmapped entry that was not
build-generated, has been written and now maps to
`src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96SCSI.m:114`. Only the two
build-generated accessors remain unmapped. See Unmapped detail below.

- Total functions in the reference analysis: 424.
- Named Objective-C methods, in scope: 91 -- 89 mapped + 2 unmapped.
- Out of scope: 333, composed of 316 unnamed jump islands (bucket 3) plus 17
  named, non-Objective-C symbols the `--scope-to-objc` map deliberately does
  not claim (bucket 6, see Buckets below). This figure is unchanged:
  `maxTransfer` moved out of bucket 6 into `mapped`, which is inside the
  Objective-C scope, not out of it.
- `duplicate_candidates`: 0. Checked directly against `read_macho` (which,
  unlike IDA's exported analysis, preserves category tags) for collisions:
  stripping every `-[Apple96_SCSI(Category) selector]` name down to
  `-[Apple96_SCSI selector]` across all 91 reference selectors produces zero
  name collisions -- none of the nine categories on `Apple96_SCSI` implements
  a selector name also implemented by another category in this binary, so
  category information was never needed to disambiguate a match here.
- `boundary_disputed`: 0 (from the source-map builder's own semantics; see
  Invariant check below for the one function-start mismatch the invariant
  checker separately flags).

The source directory's raw method-definition count (`grep` for lines opening
a `-`/`+` method signature) is roughly 124-125 across the nine categories, well
above the 91 Objective-C symbols the compiled `drvPPC53c96_reloc` actually
contains. This gap is explained in Selector check below: 37 of the source
tree's method definitions are excluded from this build by `#if
USE_CURIO_METHODS` (32 in the `Curio` category, 4 in `Curio_DBDMA`) or by
`#if 0` (1, `killCurrentRequest`), so they never reach the compiled binary at
all and are outside the scope of a map keyed off the binary's own selectors.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and
the reference analysis passed to it, so verifying a `--scope-to-objc` map
requires scoping the analysis to the same covered addresses first: the map
does not claim the 316 unnamed jump islands or the 17 non-Objective-C named
symbols, and the bucket reconciliation below accounts for those 333
separately.

```
analysis functions 424 -> scoped 91
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/53c96-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/53c96/source-map.json`:

```
total functions: 424
  mapped: 89
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 316
  4-build-generated-class: 2
      0xbf94  +[drvPPC53c96KernelServerInstance kernelServerInstance]  (20 bytes)
      0xbfa8  +[drvPPC53c96Version driverKitVersionFordrvPPC53c96]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 17
      0x28b0  _getConfigParam  (260 bytes)
      0x29e4  _GetSCSICommandLength  (132 bytes)
      0x61e8  _serviceTimeoutInterrupt  (348 bytes)
      0x84c0  ___CurioReadRegister__  (516 bytes)
      0x86d4  ___CurioWriteRegister__  (544 bytes)
      0xb75c  _MakeTimestampRecord  (148 bytes)
      0xb800  _StoreNSecTimestamp  (208 bytes)
      0xb8f0  _StoreTimestamp  (88 bytes)
      0xb968  _StoreRawTimestamp  (292 bytes)
      0xba8c  _ReadTimestamp  (392 bytes)
      0xbc24  _ReadTimestampVector  (448 bytes)
      0xbdf4  _EnableTimestamp  (136 bytes)
      0xbe7c  _PreserveTimestamp  (136 bytes)
      0xbf04  _ResetTimestampIndex  (56 bytes)
      0xbf3c  _GetTimestampSemaphoreLostCounter  (88 bytes)
      0xbfb8  __divdi3  (1736 bytes)
      0xc680  __udivdi3  (1616 bytes)
counted: 424
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`drvPPC53c96_reloc` is a statically linked kernel server, not an `MH_EXECUTE`
helper: it carries no crt/dyld startup routines and its analysis has no
`__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand
against every bucket-6 entry (`grep -rn <symbol>
src/kernel-7/bsd/dev/ppc/drvApple96_SCSI`, including `Timestamp.c`). Fifteen
of the seventeen have a source definition and move to bucket 5:

- `_getConfigParam` (static) -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96Hardware.m:576`
  (prototype at `Apple96Hardware.m:56`)
- `_GetSCSICommandLength` (static) -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96Hardware.m:597`
  (prototype at `Apple96Hardware.m:60`)
- `_serviceTimeoutInterrupt` (static) -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96SCSIPrivate.m:1009`
  (prototype at `Apple96SCSIPrivate.m:79`)
- `___CurioReadRegister__` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96Curio.m:465`,
  declared `extern` in `Apple96CurioPrivate.h:57`. The binary symbol carries
  one more leading underscore than the source name (`__CurioReadRegister__`)
  -- the standard Mach-O C-symbol leading-underscore convention, not a naming
  mismatch.
- `___CurioWriteRegister__` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96Curio.m:497`,
  declared `extern` in `Apple96CurioPrivate.h:61`. Same leading-underscore
  convention as above.
- `_MakeTimestampRecord` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:137`
- `_StoreNSecTimestamp` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:196`
- `_StoreTimestamp` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:217`
- `_StoreRawTimestamp` (static) -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:236`
  (prototype at `Timestamp.c:126`)
- `_ReadTimestamp` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:298`
- `_ReadTimestampVector` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:350`
- `_EnableTimestamp` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:386`
- `_PreserveTimestamp` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:410`
- `_ResetTimestampIndex` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:434`
- `_GetTimestampSemaphoreLostCounter` -- `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Timestamp.c:443`

These fifteen account for the "9 static C functions plus `Timestamp.c`" the
task brief calls out: a direct count of `static` function *definitions*
(excluding prototypes and non-function `static` variables) in this source
directory finds 8 -- `getConfigParam`, `GetSCSICommandLength`,
`serviceTimeoutInterrupt`, `StoreRawTimestamp` (all four listed above),
`isCmdTimedOut` (`Apple96SCSI.m:335`, `static inline`, not a bucket-6 entry --
it has no reference-analysis symbol because it is inlined/private and never
exported), plus `IncrementAtomicAligned`, `BitAndAtomicAligned` and
`CompareAndSwapAligned` (`Timestamp.c:86/94/103`, all `static inline`,
likewise not separately named in the reference analysis). Recorded here as an
observed discrepancy against the brief's "9": this source tree has 8 static
function definitions, not 9, by an exhaustive `grep -n '\bstatic\b'` of every
`.m`/`.c` file in the directory. Eleven non-static C helpers plus the two
libgcc routines round out the seventeen bucket-6 entries.

The remaining two bucket-6 entries do not move to bucket 5:

- `__divdi3` and `__udivdi3` -- the libgcc signed/unsigned 64-bit division
  runtime helpers the PPC compiler emits (the same `__udivdi3` gap recorded
  for `drvPPCBMac`). No match anywhere under
  `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI`. Compiler-generated code, not
  driver source -- an expected gap, not an open question, and explicitly out
  of scope to write.

`-[Apple96_SCSI maxTransfer]` (`0x260`, 40 bytes) **was an eighteenth bucket-6
entry at first measurement and is gone from this table**: it is now written,
so the source map claims it and the bucket script counts it under `mapped`.
See Unmapped detail below.

## Unmapped detail

**Two** reference selectors have no source-mapped implementation, down from
three, and **both remaining ones are build-generated**:

- `+[drvPPC53c96KernelServerInstance kernelServerInstance]` (20 bytes) --
  a KernelServer wrapper class instance accessor emitted by the driver-kit
  build tooling, not hand-written driver code.
- `+[drvPPC53c96Version driverKitVersionFordrvPPC53c96]` (16 bytes) --
  the DriverKit version accessor, likewise tool-emitted.

There is no absent hand-written Objective-C method left in this driver. Both
entries match the `selector_check.py` "missing" list below exactly.

### `-[Apple96_SCSI maxTransfer]` -- written

`-[Apple96_SCSI maxTransfer]` (`0x260`, 40 bytes) was the third unmapped
entry, and the only one that was not build-generated. It has been written to
`src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96SCSI.m:114` (and the
identical `src/drivers-ppc/scsi/drvPPC53c96/…` copy), and the regenerated
source map now places it there:

```
53c96 | -[Apple96_SCSI maxTransfer] -> src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96SCSI.m 114
```

Body:

```objc
- (unsigned int) maxTransfer
{
    return (page_size * gDBDMADescriptorMax);
}
```

i.e. the largest transfer describable by a single DBDMA channel program: one
page per DATA descriptor.

**Class-hierarchy and layout check (spec §3.3), performed before writing any
ivar access.** `maxTransfer` reads one ivar, so the shipped class's
`super_class`, `instance_size` and ivar table were read from the binary's
`__OBJC,__class` / `__OBJC,__instance_vars` sections and compared against our
`@interface`:

```
class Apple96_SCSI  super="IOSCSIController"  instance_size=872  ivar_count=62
   +0x0244 ( 580)  gSCSIPhysicalAddress             ^v
   +0x0248 ( 584)  gSCSILogicalAddress              *
   +0x024c ( 588)  gSCSIRegisterLength              I
   +0x0250 ( 592)  gDBDMAPhysicalAddress            ^v
   +0x0254 ( 596)  gDBDMALogicalAddress             ^{?}
   +0x0258 ( 600)  gDBDMARegisterLength             I
   +0x025c ( 604)  gDBDMAChannelAddress             ^v
   +0x0260 ( 608)  gChannelCommandArea              ^{?}
   +0x0264 ( 612)  gChannelCommandAreaSize          I
   +0x0268 ( 616)  gDBDMADescriptorMax              I
   ...
```

- Superclass agrees: the binary says `IOSCSIController`, and
  `Apple96SCSI.h:102` declares `@interface Apple96_SCSI : IOSCSIController`.
- **The ivar the method reads, `+0x268`, is `gDBDMADescriptorMax`** -- the
  ivar the written body uses. Declared in our tree at `Apple96SCSI.h:119`.
- All 62 ivar entries in the binary's table were checked by name against our
  `@interface` block: **every one is present**, and no ordering divergence was
  found. (`gSelectionTimeout` appears in our header only inside a comment at
  `Apple96SCSI.h:248` and is not a live declaration.)

So, unlike `IOSmartDisplay` in the IODisplay spec and unlike `AppleMesh_SCSI`
in this one, **no layout divergence was found for `Apple96_SCSI`**, and the
method was writable. Note the limit of this check: the binary's
`instance_size` of 872 is a measured fact, but *our* side's computed size
cannot be verified without a compiler, so what is claimed is only that the
declared ivar set and ordering match, not that the two sizes were both
computed and compared.

**Not compile-verified.** There is no PowerPC toolchain in this environment.
Nothing here was compiled, linked or loaded. The source map matching proves
the *selector* matches the binary's; it does not prove the *body* does.

Uncertainty carried forward: `page_size` is used unqualified, as the kernel
global this tree exposes; no named constant was invented for it.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== 53c96-ppc ===
symbol +[Apple96_SCSI probe:] at 0x0 is not a function start
85 scattered/difference-form relocations (target section verified, field is a difference, not an address)
4 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
3751 fused relocations, 1 violations
=== 53c96-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

Actual relocation-decode violations (`check_document`, the byte-order and
HI16/HA16-LO16 agreement checks): 0 for both binaries, despite this binary
carrying 85 scattered/difference-form relocations -- the largest count of the
five measured, consistent with the task brief's expectation that this binary
(151 KB) was the likeliest to carry `PPC_RELOC_SECTDIFF` switch tables. All
85 verified clean. The single "violation" counted for each run is a
symbol/function-start mismatch from `check_functions`, not a relocation
defect. Recorded as `boundary_disputed` candidates:

- `53c96-ppc`: `+[Apple96_SCSI probe:]` at address `0x0` -- the same pattern
  recorded for `drvPPCBMac`'s `+[BMacEnet probe:]`: a symbol in
  `__TEXT,__text` that is not one of IDA's recognized function starts.
  `Apple96_SCSI` does not define its own `probe:` in
  `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI` (not found by grep); this looks
  like an unresolved/placeholder symbol-table entry pointing at the
  inherited `IOSCSIController` implementation, not a genuine boundary dispute
  affecting any mapped function.
- `53c96-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the standard
  synthetic bundle-header symbol Mach-O bundles carry at their load address;
  not a real function, so not a function start either.

Neither candidate overlaps any function reported in the bucket table or the
source map, so neither affects the 89/2/0/0 correspondence numbers above.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 92
our definitions:     127

renames (0):

duplicates (0):

missing (2):
    +[drvPPC53c96KernelServerInstance kernelServerInstance]
    +[drvPPC53c96Version driverKitVersionFordrvPPC53c96]

extra (37):
    -[Apple96_SCSI(Curio) curioClearATN]
    -[Apple96_SCSI(Curio) curioClearTransferCountZeroBit]
    -[Apple96_SCSI(Curio) curioConfigForDMA]
    -[Apple96_SCSI(Curio) curioConfigForNonDMA]
    -[Apple96_SCSI(Curio) curioDisconnect]
    -[Apple96_SCSI(Curio) curioEnableSelectionOrReselection]
    -[Apple96_SCSI(Curio) curioFlushFifo]
    -[Apple96_SCSI(Curio) curioGetFifoByte]
    -[Apple96_SCSI(Curio) curioGetFifoCount]
    -[Apple96_SCSI(Curio) curioGetTransferCount]
    -[Apple96_SCSI(Curio) curioInitiatorCommandComplete]
    -[Apple96_SCSI(Curio) curioMessageAccept]
    -[Apple96_SCSI(Curio) curioMessageReject]
    -[Apple96_SCSI(Curio) curioNop]
    -[Apple96_SCSI(Curio) curioPutByteIntoFifo:]
    -[Apple96_SCSI(Curio) curioReadCommandRegister]
    -[Apple96_SCSI(Curio) curioReadInterruptRegister]
    -[Apple96_SCSI(Curio) curioReadRegister:]
    -[Apple96_SCSI(Curio) curioReadSequenceStateRegister]
    -[Apple96_SCSI(Curio) curioReadStatusRegister]
    -[Apple96_SCSI(Curio) curioSelectTimeout:curioClockMHz:curioClockFactor:]
    -[Apple96_SCSI(Curio) curioSetATN]
    -[Apple96_SCSI(Curio) curioSetCommandRegister:]
    -[Apple96_SCSI(Curio) curioSetDestinationID:]
    -[Apple96_SCSI(Curio) curioSetSelectionTimeout:]
    -[Apple96_SCSI(Curio) curioSetSynchronousOffset:]
    -[Apple96_SCSI(Curio) curioSetSynchronousPeriod:]
    -[Apple96_SCSI(Curio) curioStartDMATransfer:]
    -[Apple96_SCSI(Curio) curioStartMSGIAction]
    -[Apple96_SCSI(Curio) curioStartNonDMATransfer]
    -[Apple96_SCSI(Curio) curioTransferPad:]
    -[Apple96_SCSI(Curio) curioWriteRegister:value:]
    -[Apple96_SCSI(Curio_DBDMA) dbdmaReset]
    -[Apple96_SCSI(Curio_DBDMA) dbdmaSpinUntilIdle]
    -[Apple96_SCSI(Curio_DBDMA) dbdmaStartTransfer]
    -[Apple96_SCSI(Curio_DBDMA) dbdmaStopTransfer]
    -[Apple96_SCSI(Private) killCurrentRequest]
```

Exit code: 0. `selector_check.py` reads the binary's raw symbol table via
`read_macho` (category tags preserved) rather than IDA's exported analysis,
so its "reference selectors" count is 92 -- one more than the 91-function
Objective-C scope used above. The extra one is `+[Apple96_SCSI probe:]`,
present as a raw symbol at address `0x0` but excluded from IDA's function
list (see Invariant check); it is the same symbol flagged there, not a new
gap.

"Our definitions: 127" is one more than the 126 recorded at first measurement;
the difference is exactly the newly written `-[Apple96_SCSI maxTransfer]`,
which also removes the third "missing" entry. The two remaining "missing"
entries match the source map's unmapped set exactly (see Unmapped detail). All
37 "extra" entries -- source-tree method definitions
with no corresponding binary selector -- are explained by conditional
compilation, verified by inspection of the source:

- 32 entries under `Apple96_SCSI(Curio)` and 4 under
  `Apple96_SCSI(Curio_DBDMA)` fall inside `#if USE_CURIO_METHODS` blocks
  (`Apple96Curio.m:180-459`, `Apple96CurioDBDMA.m:67-103`) that this build
  does not define; the unconditional methods in those same two categories
  (e.g. `curioInterruptPending`, `dbdmaTerminate`) are compiled in and do
  appear in the binary's selector table.
- `-[Apple96_SCSI(Private) killCurrentRequest]` is inside an `#if 0` block
  (`Apple96SCSIPrivate.m:528-550`) -- permanently disabled dead code, never
  compiled under any configuration.

None of the 37 are gaps in the reconstruction; they are source that the
shipped binary's own build configuration excludes.

## Bundle stub

`drvPPC53c96` (the non-relocatable bundle, profile `53c96-bundle-ppc`)
analysis has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this
small bundle wrapper is a loader shim with no Objective-C methods and no
driver logic of its own, so it carries no correspondence findings against
`drvApple96_SCSI`. No source map or bucket table was built for it (the source
map and bucket script in this task both target `drvPPC53c96_reloc`, the
statically linked kernel server that actually contains the driver's compiled
code).

## Open questions

**Resolved: `-[Apple96_SCSI maxTransfer]` has been written.** It is no longer
an open question; the record of the search that established it was genuinely
absent is kept below, and the method as written is documented under Unmapped
detail above. Nothing in the investigation below was contradicted -- the
override really was missing from this source tree, and has now been supplied.

- `-[Apple96_SCSI maxTransfer]` (0x260, 40 bytes) had no source site anywhere
  in `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI`. What was tried:
  - `grep -rn maxTransfer` across every `.m`, `.h`, and `.c` file in the
    directory -- every hit is a `scsiReq->maxTransfer` struct-field access,
    never a method signature (`- ... maxTransfer`).
  - Checked `Apple96SCSI.h` for a declaration alongside the neighboring
    statistics accessors (`numQueueSamples`, `sumQueueLengths`,
    `maxQueueLength`, all present) -- no `maxTransfer` declaration exists.
  - Checked for the NeXT-era semicolon-before-body pattern that Task 2b's
    scanner fix recovered two other methods from in this same directory --
    no `maxTransfer` line of any form (with or without a stray semicolon)
    appears in any `.m` file.
  - Confirmed `maxTransfer` is a real `IOSCSIController` virtual accessor
    that sibling drivers in this tree do override
    (`src/kernel-7/bsd/dev/ppc/drvPPCATA/AtapiCnt.m:451`,
    `src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2SCSI.m`), each with a
    short (single-`return`) body of similar size to the compiled method's 40
    bytes, so a real, small override in `Apple96_SCSI` is plausible and
    consistent with the binary evidence.
  - No candidate source line was found. The override that produced the
    compiled 40-byte `-[Apple96_SCSI maxTransfer]` was genuinely missing from
    this source tree, rather than present under another name or hidden by the
    NeXT-era semicolon pattern. It has since been written; see Unmapped detail.
