# drvPPCATA / drvATADisk reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCATA.config/drvPPCATA` | 8492 | `348D054DF4EA489937D1980128E0EC0F451FE0983BE21AB8D7C5D44858D19DD7` |
| `drvPPCATA.config/drvPPCATA_reloc` | 134952 | `734464DC6604C7430761D95E3FA2D51C3C5A9E38956FD847B15390CD3448F597` |

Sizes and hashes as supplied by the controller for
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`, taken as verified.

This driver's source is split across two directories:
`src/kernel-7/bsd/dev/ppc/drvPPCATA` (the `IdeController`/`AtapiController`
controller classes) and `src/kernel-7/bsd/dev/ppc/drvATADisk` (the disk-object
class, `ATADisk`). Both were built into one source map in a single
`binrecon source-map` invocation using two `--source-dir` flags (see
"Two source directories" below).

## Correspondence

Source map built with
`binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCATA_reloc`, scoped to the Objective-C methods found in that binary:

```
mapped 101 unmapped 42 dup 4 disputed 0
unmapped IdeDisk methods: 38
```

- `mapped`: 101 -- reference selectors resolved unambiguously to one source
  definition.
- `unmapped` (raw): 42, of which 38 are `-[IdeDisk ...]` / `+[IdeDisk ...]`
  selectors that fail to match by name because the binary links `IdeDisk`
  while our tree defines `ATADisk : IODisk` (see IdeDisk / ATADisk below).
  The remaining 4 are 2 real `IdeController` gaps
  (`-[IdeController setTransferRate:]`, a single-argument selector our source
  does not define -- only the two-argument
  `-[IdeController setTransferRate:UseDMA:]` exists, at
  `src/kernel-7/bsd/dev/ppc/drvPPCATA/IdeCnt.m:493`) and 2 build-generated
  DriverKit accessors (`+[drvPPCATAKernelServerInstance kernelServerInstance]`,
  `+[drvPPCATAVersion driverKitVersionFordrvPPCATA]`), which fall into bucket 4
  below.
- `duplicate_candidates`: 4 -- every entry is enumerated and explained in
  "Duplicate candidates" below.
- `boundary_disputed`: 0 from the source-map builder's own semantics; see
  Invariant check for the one function-start mismatch the invariant checker
  separately flags (not a boundary dispute in the source-map sense).

**Raw vs. rename-adjusted correspondence.** Because Step 6 (below) establishes
that the binary's `IdeDisk` and our tree's `ATADisk` are the same class under
two names, the 38 unmapped `IdeDisk` selectors are not real gaps -- our source
defines all of them under the `ATADisk` name. Adjusting for the rename:

| | raw | rename-adjusted |
| --- | --- | --- |
| mapped | 101 | 139 (101 + 38 `IdeDisk`/`ATADisk` selectors) |
| unmapped | 42 | 4 (2 real `IdeController` gaps + 2 build-generated) |

The difference (38) is entirely attributable to the `IdeDisk`/`ATADisk`
naming mismatch documented in "IdeDisk / ATADisk" below; no other unmapped
entries are affected by the rename.

## Duplicate candidates

All four `duplicate_candidates` entries, enumerated with cause:

**Scanner limitation (preprocessor-guarded, not a real duplicate):**

- `-[AtapiController allocAtapiBuf]` (address 5204, size 244) --
  `src/kernel-7/bsd/dev/ppc/drvPPCATA/AtapiCntInternal.m:124` (inside
  `#ifdef NO_ATAPI_RUNTIME_MEMORY_ALLOCATION`) and `:161` (inside the matching
  `#else`). `AtapiCnt.h:45` unconditionally
  `#define NO_ATAPI_RUNTIME_MEMORY_ALLOCATION`, so only the `:124` branch is
  ever compiled. `source_map.py`'s scanner is line-based and does not
  evaluate C preprocessor conditionals, so it records both branches as
  candidate definitions of the same selector in the same file.
- `-[AtapiController freeAtapiBuf:]` (address 5496, size 128) -- same file
  and same cause: `AtapiCntInternal.m:151` (`#ifdef` branch, compiled) and
  `:172` (`#else` branch, dead).

**Real property of Apple's source (primary class vs. category, same
selector):**

- `-[IdeController getIdeDriveInfo:]` (address 20176, size 76) --
  `src/kernel-7/bsd/dev/ppc/drvPPCATA/IdeCnt.m:475` inside
  `@implementation IdeController` (the primary class, `IdeCnt.m:56`), and
  `src/kernel-7/bsd/dev/ppc/drvPPCATA/IdeCntInit.m:443` inside
  `@implementation IdeController(Initialize)` (a category on the same class,
  `IdeCntInit.m:131`).
- `-[IdeController getIdeIdentifyInfo:]` (address 23280, size 48) --
  `IdeCnt.m:469` (primary class) and `IdeCntInit.m:1101`
  (`(Initialize)` category).

**Which one Apple shipped.** For both `IdeController` pairs, the two source
bodies are functionally and near-textually identical -- they differ only in
whitespace/parenthesization, not logic:

```
IdeCnt.m:475           - (ideDriveInfo_t *) getIdeDriveInfo:(unsigned int)unit
                       { return (&_ideInfo[unit]); }
IdeCntInit.m:443       -(ideDriveInfo_t *)getIdeDriveInfo:(unsigned int)unit
                       { return &_ideInfo[unit]; }

IdeCnt.m:469           - (ideIdentifyInfo_t *) getIdeIdentifyInfo:(unsigned int)unit
                       { return _ideIdentifyInfoSupported[unit] ? &_ideIdentifyInfo[unit] : NULL; }
IdeCntInit.m:1101      -(ideIdentifyInfo_t *)getIdeIdentifyInfo:(unsigned int)unit
                       { return _ideIdentifyInfoSupported[unit] ? &_ideIdentifyInfo[unit] : NULL; }
```

The reference binary contains exactly one compiled function per selector (one
address, one size each -- 76 bytes / 19 instructions and 48 bytes / 12
instructions, both plausible for a trivial array-index accessor plus PPC
ObjC-method prologue/epilogue). I looked for a structural signal -- size,
instruction-count, anything that would favor one candidate file over the
other -- and there is none available: the two textual definitions are
close enough to identical that they would assemble to indistinguishable
object code. I did not find (and Mach-O symbol lookup by exact reference
name against `read_macho` returned nothing keyed this way either, since the
binary's raw symbol table does not carry per-category disambiguation for
this analysis) any byte-level evidence that could attribute the single
compiled function to `IdeCnt.m` specifically over `IdeCntInit.m`, or vice
versa. **This does not settle to a specific file/line; I am reporting it as
unresolved rather than guessing.** What the evidence does establish: Apple's
shipped binary contains only one compiled instance of each selector, while
our tree carries two textual definitions of each (one in the primary class,
one in the `(Initialize)` category) that are logically redundant with each
other. Since Objective-C category methods override same-named primary-class
methods in the runtime's method table, at most one of the two textual
definitions in our tree is ever actually invoked at runtime for either
selector regardless of which one the compiler happened to keep in Apple's
original build -- the two are dead-code duplicates of each other in our
source, independent of which specific line matches the shipped bytes.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses
(across all four categories: `mapped`, `unmapped`, `duplicate_candidates`,
and `boundary_disputed`) and the reference analysis passed to it. Because
this map has a nonzero `duplicate_candidates` count (unlike BMac's map, which
had zero), scoping the analysis correctly requires including
`duplicate_candidates` addresses in the covered set, not just
`mapped`/`unmapped`. Attempting to scope with only `mapped ∪ unmapped`
(the shape that worked when duplicates were empty) fails:

```
binrecon.schema.SemanticValidationError: source map partition mismatch: missing=[], unexpected=[5204, 5496, 20176, 23280]
analysis functions 420 -> scoped 143
```

The four "unexpected" addresses are exactly the four `duplicate_candidates`
entries above. Scoping to `mapped ∪ unmapped ∪ duplicate_candidates ∪
boundary_disputed` (147 addresses: 101 + 42 + 4 + 0) resolves it:

```
analysis functions 420 -> scoped 147
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/ata-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/ATA/source-map.json`:

```
total functions: 420
  mapped: 101
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 254
  4-build-generated-class: 2
      0xa39c  +[drvPPCATAKernelServerInstance kernelServerInstance]  (20 bytes)
      0xa3b0  +[drvPPCATAVersion driverKitVersionFordrvPPCATA]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 63
      (38 -[IdeDisk ...]/+[IdeDisk ...] selectors, the 4 duplicate_candidates,
       2 IdeController real gaps, and 19 named C functions -- see below)
counted: 420
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`drvPPCATA_reloc` is a statically linked kernel server, not an `MH_EXECUTE`
helper: it carries no crt/dyld startup routines and its analysis has no
`__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand
against the 19 named, non-Objective-C C functions in bucket 6 (searching both
`drvPPCATA` and `drvATADisk`, per the task's expectation of genuine bucket-5
moves from this driver's static functions):

`drvPPCATA` has 3 static C functions, all in `IdeCntInit.m`, and one more
non-static file-local thread entry point:

- `_endianSwap16Bit` -- `src/kernel-7/bsd/dev/ppc/drvPPCATA/IdeCntInit.m:100` (static)
- `_endianSwap32Bit` -- `src/kernel-7/bsd/dev/ppc/drvPPCATA/IdeCntInit.m:109` (static)
- `_rnddiv` -- `src/kernel-7/bsd/dev/ppc/drvPPCATA/IdeCntInit.m:123` (static)
- `_atapiThread` -- `src/kernel-7/bsd/dev/ppc/drvPPCATA/AtapiCntInternal.m:278`
  (declared `AtapiCntInternal.h:91`, not static, but not Objective-C either)

`drvATADisk` has 2 static C functions (`ideminphys`, `ide_dev_to_id`), each
appearing twice in `grep -n static` output -- once as a forward declaration,
once as the definition -- for 4 total "static"-tagged lines, which likely
accounts for the task's expectation of "4 static C functions" for this
directory. Plus 12 more non-static named C functions with real source sites
(BSD block/char-device switch-table entry points and helpers):

- `_ideminphys` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:701` (static;
  declared `:141`)
- `_ide_dev_to_id` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:711` (static;
  declared `:142`)
- `_ideThread` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskInternal.m:794`
  (declared `ATADiskInternal.h:157`)
- `_iderToIo` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskInternal.m:842`
  (declared `:50`)
- `_ide_init_idmap` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:147`
  (declared `ATADiskInternal.h:72`)
- `_ide_idmap` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:170`
  (declared `ATADiskInternal.h:73`)
- `_ideopen` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:176`
  (declared `ATADiskKernel.h:39`)
- `_ideclose` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:202`
  (declared `ATADiskKernel.h:40`)
- `_ideread` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:242`
  (declared `ATADiskKernel.h:41`)
- `_idewrite` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:265`
  (declared `ATADiskKernel.h:42`)
- `_idestrategy` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:287`
  (declared `ATADiskKernel.h:43`)
- `_ideioctl` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:359`
  (declared `ATADiskKernel.h:44`)
- `_idesize` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:680`
  (declared `ATADiskKernel.h:45`)
- `_ide_block_char_majors` -- `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskKernel.m:695`
  (declared `ATADiskKernel.h:46`)

That is 4 (drvPPCATA) + 14 (drvATADisk) = 18 bucket-6 entries with a real
source site, moved to bucket 5 by hand. The one remaining named C function,
`__udivdi3` (1616 bytes), has no match anywhere under either source
directory -- it is the libgcc 64-bit unsigned-division runtime helper the
PPC compiler emits, the same function BMac's reconstruction found in the
identical role. It stays in bucket 6 as a real, expected gap: compiler-
generated code, not driver source.

## Unmapped detail

Raw unmapped entries fall into three groups:

1. **38 `IdeDisk` selectors** (26 primary-class, incl. 4 class methods, plus
   12 in an `(Internal)` category) -- not real gaps; see IdeDisk / ATADisk
   below. Full source coverage confirmed via the merged selector check.
2. **2 real `IdeController` gaps**: `-[IdeController setTransferRate:]` (our
   source only has the two-argument
   `-[IdeController setTransferRate:UseDMA:]`, `IdeCnt.m:493`); the
   reference's `-[IdeController(Dma) isDmaSupported:]` and
   `-[IdeController(Initialize) calcIdeConfigWord:]` are also present in the
   raw unmapped set with a category tag our source's
   `-[IdeController isDmaSupported:]` (`IdeCnt.m:480`, no category) and
   `-[IdeController calcIdeConfigWord:]` (present, per bucket 6, but reported
   unmapped because the reference and source category tags differ) do not
   carry. This is a category-boundary characteristic of the reference
   symbol naming, not a missing implementation, but it is recorded here as
   observed rather than resolved.
3. **2 build-generated DriverKit accessors** (`kernelServerInstance`,
   `driverKitVersionFordrvPPCATA`), the same pattern seen in every driver so
   far -- tool-emitted, not hand-written.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== ata-ppc ===
symbol -[IdeController(ATAPI) atapiWaitForNotBusy] at 0x0 is not a function start
26 scattered/difference-form relocations (target section verified, field is a difference, not an address)
5 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
3418 fused relocations, 1 violations
=== ata-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

Actual relocation-decode violations (`check_document`, the byte-order and
HI16/HA16-LO16 agreement checks): 0 for both binaries, despite
`drvPPCATA_reloc`'s size (134,952 bytes) making it a plausible carrier of
`PPC_RELOC_SECTDIFF` switch tables -- the 26 scattered/difference-form
relocations and 5 HI16/HA16-LO16 pairs all checked out with no disagreement.
The single "violation" counted for each run is a symbol/function-start
mismatch from `check_functions`, not a relocation defect:

- `ata-ppc`: `-[IdeController(ATAPI) atapiWaitForNotBusy]` at address `0x0`
  is a symbol in `__TEXT,__text` that is not one of IDA's recognized function
  starts -- address 0x0 is the Mach-O header/load-command region, the same
  placeholder-address pattern BMac's reconstruction saw for
  `+[BMacEnet probe:]`.
- `ata-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the standard
  synthetic bundle-header symbol, likewise not a real function.

Neither candidate overlaps any function reported in the bucket table or the
source map, so neither affects the correspondence numbers above.

## Selector check

`selector_check.py` run once per source directory against `drvPPCATA_reloc`
(148 reference selectors in both runs, same binary):

```
=== src/kernel-7/bsd/dev/ppc/drvPPCATA ===
reference selectors: 148
our definitions:     124
renames (0):
duplicates (1):
    -[IdeController(Commands) _ideExecuteCmd:ToDrive:]         IdeCntCmds.m:714
missing (43): [38 -[IdeDisk ...]/+[IdeDisk ...] entries + 2 IdeController real
gaps + 2 build-generated + this driver's own directory does not define
AtapiDisk/ATADisk at all]
extra (17): [-[IdeController ...] entries whose category tag differs from the
reference's, e.g. isDmaSupported:, getControllerType, setTransferRate:UseDMA:,
numberOfDrives, configReadByte:value:, configWriteByte:value:, plus
AtapiController(ATAPI)/IdeController(Dma)/IdeController(Initialize) entries
with mismatched category tags]

=== src/kernel-7/bsd/dev/ppc/drvATADisk ===
reference selectors: 148
our definitions:     40
renames (0):
duplicates (0):
missing (148): [all 148 -- this directory does not define IdeController or
AtapiController at all, only ATADisk]
extra (38): [+[ATADisk deviceStyle], +[ATADisk hd_devsw_init:], +[ATADisk
probe:], +[ATADisk requiredProtocols], and 34 -[ATADisk ...]/-[ATADisk
(Internal) ...] entries]
```

Exit codes: 1 for the `drvPPCATA` run (the one `duplicates` entry), 0 for
`drvATADisk`.

**Merging the two runs**, per the task: a selector reported missing by one
run but present in the other is not missing. All 148 `-[AtapiController ...]`
and `-[IdeController ...]` selectors that show as "missing" in the
`drvATADisk`-only run are defined in the `drvPPCATA` directory (they show as
either matched or as one of the 17 category-tag "extra" entries there, not
as missing) -- they are not real gaps, just in the other directory.
Conversely, the `drvATADisk` run's 38 `-[ATADisk ...]`/`+[ATADisk ...]`
"extra" entries are, selector-for-selector, the same 38 selectors the
`drvPPCATA` run reports "missing" as `-[IdeDisk ...]`/`+[IdeDisk ...]` --
this is the strongest evidence for the rename (see IdeDisk / ATADisk below).
One entry differs syntactically only because of a trailing same-line `//`
comment in the source
(`src/kernel-7/bsd/dev/ppc/drvATADisk/ATADiskInternal.m:754`,
`- (void)logRwErr : (const char *)errType	// e.g., "RECALIBRATING"`), which
`selector_check.py`'s line-based parser folds into the printed name
(`logRwErr://:status:readFlag:`); it is the same selector as
`-[IdeDisk(Internal) logRwErr:block:status:readFlag:]` in the `drvPPCATA`
run's missing list.

The one genuine `drvPPCATA`-run finding, `duplicates (1)`: our source defines
both `-[IdeController ideExecuteCmd:ToDrive:]` (the public entry point,
`IdeCnt.m:414`) and `-[IdeController(Commands) _ideExecuteCmd:ToDrive:]` (the
underscore-prefixed implementation it delegates to, `IdeCntCmds.m:714`,
literally `return [self _ideExecuteCmd:ideIoReq ToDrive:drive];`). This is a
legitimate public-wrapper/private-implementation split (a common
underscore-prefix convention), not redundant dead code; the tool's generic
heuristic for underscore-prefixed selectors flags it as a "duplicate" because
it cannot distinguish a delegating wrapper from truly redundant code.

The 17 `drvPPCATA`-run "extra" entries and the corresponding "missing"
category-tagged reference names (e.g. our source's
`-[IdeController isDmaSupported:]`, no category, vs. the reference's
`-[IdeController(Dma) isDmaSupported:]`) are a real, observed
category-boundary difference between our source's `@implementation
IdeController` grouping and the reference binary's per-category symbol
naming; recorded here as observed, not resolved further.

## IdeDisk / ATADisk

The binary links a class `IdeDisk`; our tree defines `ATADisk : IODisk` in
`src/kernel-7/bsd/dev/ppc/drvATADisk/ATADisk.m`. Existing comments in the
tree already point at the old name:
`drvATADisk/ATADiskKernel.m:90` cites `IdeDiskInternal.h`, and
`drvPPCATA/AtapiCnt.m:76`, `drvPPCATA/IdeCntCmds.h:100` and
`drvPPCATA/IdeCntCmds.m:59` all name `IdeDisk` in comments.

**Step 6's raw selector-set comparison** (regex-based, single source line per
selector):

```
IdeDisk selectors in binary: 38
ATADisk selectors in source: 34
intersection: 25
binary only: ['deviceRwCommon:block:length:buffer:client:pending:actualLength:', 'free',
  'getDevicePath:maxLength:useAlias:', 'getIntValues:forParameter:count:', 'initResources:',
  'isDiskReady:', 'logRwErr:block:status:readFlag:', 'probe:',
  'property_IOUnit:length:', 'readAsyncAt:length:buffer:pending:client:',
  'readAt:length:buffer:actualLength:client:', 'writeAsyncAt:length:buffer:pending:client:',
  'writeAt:length:buffer:actualLength:client:']
source only: ['deviceRwCommon:', 'getIntValues:', 'isDiskReady', 'logRwErr',
  'probe', 'readAsyncAt', 'readAt', 'writeAsyncAt', 'writeAt']
```

25/38 (66%) and 25/34 (74%) is already a large majority -- sufficient by
itself to establish the rename. But every "binary only"/"source only"
mismatch above is a parsing artifact, not a real gap: Apple's original
source style wraps method signatures across multiple lines (e.g.
`ATADisk.m:271-276` writes `- (IOReturn) readAt : (unsigned)offset` on one
line and `length :`, `buffer :`, `actualLength :`, `client :` on the
following four), and the Step 6 script's regex reads one line at a time, so
it only captures the first keyword of each such selector. Checked directly
against source (`ATADisk.m:87` `+ (BOOL)probe : deviceDescription`,
`ATADisk.m:271` `readAt`, `ATADisk.m:411` `getIntValues:...`, etc.): every
"binary only"/"source only" pair names the same method.

**The merged selector check (Step 8) settles it completely.** Every one of
the 38 `-[IdeDisk ...]`/`+[IdeDisk ...]` selectors reported "missing" when
scanning only `drvPPCATA` is, selector-string-for-selector-string (same
keywords, same category tag `(Internal)` where present), reported as an
`-[ATADisk ...]`/`+[ATADisk ...]` "extra" entry when scanning only
`drvATADisk` -- a full 38/38 match once the properly-parsed
`selector_check.py` tool (which stitches wrapped signatures across up to 20
lines) is used instead of the single-line regex from Step 6.

**Verdict: RENAME ESTABLISHED.** `IdeDisk` (the binary) and `ATADisk` (our
tree) are the same class under two names. The Step 6 script's 25/38 raw
intersection was itself an undercount caused by its single-line parsing; the
true correspondence, confirmed by the merged selector check, is complete
(38/38). See "Correspondence" above for the resulting raw vs.
rename-adjusted numbers.

## Two source directories

This driver's source map spans two directories in one `binrecon source-map`
invocation, passed as two `--source-dir` flags (the scanner does not
recurse, so both had to be named explicitly):
`src/kernel-7/bsd/dev/ppc/drvPPCATA` (the `IdeController`/`AtapiController`
controller classes) and `src/kernel-7/bsd/dev/ppc/drvATADisk` (the `ATADisk`
disk-object class). Both directories' addresses and source lines appear
together in the single `source-map.json` produced for this task.

`selector_check.py` takes a single source directory per invocation, so the
selector check (Step 8) was run twice -- once per directory -- against the
same reference binary, and the two outputs were merged by hand in
"Selector check" above. The `drvPPCATA` run alone reports 105 of the
reference's 148 selectors as either matched or present-with-different-
category (124 of our definitions map, less the 1 duplicate); the
`drvATADisk` run alone reports all 148 as missing, because that directory
defines only `ATADisk`, never the reference's literal `IdeController`/
`AtapiController`/`IdeDisk` names. Read separately, either run
overstates a gap that resolves once both directories -- and the rename --
are accounted for together.
