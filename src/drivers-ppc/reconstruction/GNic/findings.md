# drvPPCGNic reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCGNic.config/drvPPCGNic` | 8496 | `ED1143591121941501257DB21841CE795014C31C75A2985F9A2F3F49E8D8B159` |
| `drvPPCGNic.config/drvPPCGNic_reloc` | 48432 | `1D208A3E49CD9DDD6692C81AEACC9C0A5C4BF97F45827EF30DECC495E851B760` |

Both re-verified locally with `sha256sum` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`; sizes confirmed with `ls -la`. Both match.

## Correspondence

> **SUPERSEDED (2026-07-28).** The numbers in this section describe the original
> `--scope-to-objc` map, which by construction never claimed this driver's two
> hand-written C functions and so could not report them as unmapped. That map has
> been replaced by one built on the PPCSerialPort route (`filter_named_functions.py`
> then `source-map --objc-methods`, **without** `--scope-to-objc`), which covers
> all 52 named functions. See "The underscore defect and the remap" at the end of
> this file for the current counts. The Objective-C conclusions below are
> unchanged by the reroute: 47 methods mapped, then and now.

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCGNic_reloc`, scoped to the Objective-C methods found in that binary
(49 of the 156 total functions IDA reported):

```
mapped 47 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPCGNicKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCGNicVersion driverKitVersionFordrvPPCGNic]'] 16
```

- Total functions in the reference analysis: 156.
- Named Objective-C methods, in scope: 49 -- 47 mapped + 2 unmapped.
- Out of scope: 107, composed of 104 unnamed jump islands (bucket 3) plus 3
  named, non-Objective-C symbols the `--scope-to-objc` map deliberately does
  not claim (bucket 6, see Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0 (from the source-map builder's own semantics; see
  Invariant check below for the one symbol/function-start mismatch the
  invariant checker separately flags).

`GNicEnet.m` and `GNicEnetPrivate.m` (`@implementation GNicEnet` and
`@implementation GNicEnet(Private)`) together define 48 Objective-C methods
(22 + 26, counted with `grep -c "^[+-]" GNicEnet.m GNicEnetPrivate.m`), two
more than the 46 the task description cites. The extra method,
`-[GNicEnet(Private) _allocateMemory]` (`GNicEnetPrivate.m:115`), has source
but never surfaces as an analysis function -- it is the one entry the
invariant checker (Step 3) flags as a symbol at address `0x0`, so the 156
functions IDA reported never include it and it cannot appear as "mapped" or
"unmapped" against the source map. See Invariant check for detail -- including
the correction that `__text+0` holds a real body IDA's analysis omits, making
this an unmapped real function rather than an empty symbol. That
leaves 47 methods with a genuine reference-function counterpart to map,
matching `mapped 47` above exactly.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and
the reference analysis passed to it, so verifying a `--scope-to-objc` map
requires scoping the analysis to the same covered addresses first: the map
does not claim the 104 unnamed jump islands or the 3 non-Objective-C symbols,
and the bucket reconciliation below accounts for those 107 separately.

```
analysis functions 156 -> scoped 49
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/gnic-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/GNic/source-map.json`:

```
total functions: 156
  mapped: 47
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 104
  4-build-generated-class: 2
      0x28c0  +[drvPPCGNicKernelServerInstance kernelServerInstance]  (20 bytes)
      0x28d4  +[drvPPCGNicVersion driverKitVersionFordrvPPCGNic]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 3
      0x27bc  _WriteGNicRegister  (128 bytes)
      0x283c  _ReadGNicRegister  (132 bytes)
      0x28e4  __udivdi3  (1616 bytes)
counted: 156
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`drvPPCGNic_reloc` is a statically linked kernel server, not an `MH_EXECUTE`
helper: it carries no crt/dyld startup routines and its analysis has no
`__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand
against every bucket-6 entry
(`grep -n <symbol> src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj`).
Two of the three have a source definition and move to bucket 5:

- `_WriteGNicRegister` -- `src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj/GNicEnet.m:66`
  (non-static, called from both `GNicEnet.m` and `GNicEnetPrivate.m`, which
  `extern`-declares it at `GNicEnetPrivate.m:13`)
- `_ReadGNicRegister` -- `src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj/GNicEnet.m:32`
  (non-static, `extern`-declared at `GNicEnetPrivate.m:12`)

> **CORRECTION (2026-07-28).** Both bucket-5 moves above were made **on the
> wrong name**. The source spelled these functions `_ReadGNicRegister` and
> `_WriteGNicRegister`, with a leading underscore *in the C identifier*. The
> Mach-O naming rule prepends exactly one underscore, so those definitions would
> have emitted `__ReadGNicRegister` and `__WriteGNicRegister` -- not the
> `_ReadGNicRegister` / `_WriteGNicRegister` the binary carries. The hand move to
> bucket 5 matched the binary's symbol against a source identifier that already
> contained the underscore the compiler adds, so it was a coincidence of
> spelling, not a correspondence. Both were renamed on 2026-07-28; see
> "The underscore defect and the remap" at the end of this file for the
> before/after map counts.

Neither is the "1 static C function" the task description calls out for this
source -- that is `static inline void enforceInOrderExecutionIO(void)` at
`GNicEnet.m:27` (confirmed with `grep -n "^static\b"` across the `.lksproj`,
which returns exactly this one line). Being `static inline`, it does not
survive as a distinct symbol in the compiled binary, so it makes no
appearance in the reference analysis and raises no bucket-6 entry.
`_WriteGNicRegister` and `_ReadGNicRegister` are ordinary non-static C
helpers that the `--scope-to-objc` source map does not claim because they
are not Objective-C methods, not because they lack source.

The third entry, `__udivdi3`, has no match anywhere under
`src/drivers-ppc/network/drvPPCGNic`. It is the libgcc 64-bit
unsigned-division runtime helper the PPC compiler emits; it stays in bucket 6
as a real, expected gap -- it is compiler-generated code, not driver source.
No caller could be identified from the reference analysis, which carries no
call-graph edges for this binary.

## Unmapped detail

Two reference selectors have no source-mapped implementation, both
build-generated:

- `+[drvPPCGNicKernelServerInstance kernelServerInstance]` (20 bytes) --
  a KernelServer wrapper class instance accessor emitted by the driver-kit
  build tooling, not hand-written driver code.
- `+[drvPPCGNicVersion driverKitVersionFordrvPPCGNic]` (16 bytes) --
  the DriverKit version accessor, likewise tool-emitted.

Both match the `selector_check.py` "missing" list below exactly.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== gnic-ppc ===
symbol -[GNicEnet(Private) _allocateMemory] at 0x0 is not a function start
6 scattered/difference-form relocations (target section verified, field is a difference, not an address)
3 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1022 fused relocations, 1 violations
=== gnic-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

Actual relocation-decode violations (`check_document`, the byte-order and
HI16/HA16-LO16 agreement checks): 0 for both binaries. The single
"violation" counted for each run is a symbol/function-start mismatch from
`check_functions`, not a relocation defect. Recorded as `boundary_disputed`
candidates:

- `gnic-ppc`: `-[GNicEnet(Private) _allocateMemory]` at address `0x0` is a
  symbol in `__TEXT,__text` that is not one of IDA's recognized function
  starts. `GNicEnetPrivate.m:115` defines this method
  (`- (BOOL)_allocateMemory`), so source exists for it. This is the same
  anomaly the Correspondence section above explains: it is why the source has
  48 methods but the map only reconciles 47.
> **CORRECTION.** The bullet above said the reference binary carries "only a symbol-table
> entry at address 0x0 -- a placeholder/unresolved address". That was wrong, and the same
> misreading was repeated across every driver spec in this series. `__text+0` in
> `drvPPCGNic_reloc` holds `7c0802a6` -- `mflr r0` -- and it is IDA's *analysis* that omits
> the function there, not Apple's binary that omits the code. `read_macho` reports address
> `0` for every undefined symbol too (`_IOLog`, `_objc_msgSend`, ...), which is what made a
> defined symbol at `__text+0` look empty.
>
> **`-[GNicEnet(Private) _allocateMemory]` is a real function the analysis does not record,
> not a phantom.** It is an unmapped real function -- a genuine gap, not an artifact of the
> tooling. `GNicEnetPrivate.m:115`'s correspondence to it is now *unverified* rather than
> *unnecessary*: there is Apple code at `__text+0` and nothing here has compared the two.
> Nothing was re-measured for this correction and no source map was regenerated: the
> mapped/unmapped counts above are unaffected, because IDA never had this function to map.
> The checker now distinguishes the two cases. See
> `src/drivers-ppc/reconstruction/IOADBDevice/findings.md`, "The misreading".

- `gnic-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the standard
  synthetic bundle-header symbol Mach-O bundles carry at their load address;
  not a real function, so not a function start either.

Neither candidate overlaps any function reported in the bucket table or the
source map, so neither affects the 47/2/0/0 correspondence numbers above.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 50
our definitions:     48

renames (0):

duplicates (0):

missing (2):
    +[drvPPCGNicKernelServerInstance kernelServerInstance]
    +[drvPPCGNicVersion driverKitVersionFordrvPPCGNic]

extra (0):
```

Exit code: 0. The "missing" two match the source map's unmapped set exactly,
both build-generated (see Unmapped detail). "Reference selectors: 50"
includes the 47 mapped, the 2 missing/build-generated, and
`-[GNicEnet(Private) _allocateMemory]` (the symbol-table-only entry from
Invariant check) -- 47 + 2 + 1 = 50. "Our definitions: 48" is the 48 method
signatures actually present in `GNicEnet.m`/`GNicEnetPrivate.m` (47 mapped
plus `_allocateMemory`). There is no "extra" list to characterise -- the
count is 0, so `drvPPCGNic`'s selector table has zero surplus definitions
relative to the reference binary's selector table, and a class-insensitive
re-check is moot since nothing is flagged as extra to begin with.

## Bundle stub

`drvPPCGNic` (the non-relocatable bundle, profile `gnic-bundle-ppc`) analysis
has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this
small bundle wrapper is a loader shim with no Objective-C methods and no
driver logic of its own, so it carries no correspondence findings against
`GNicEnet`. No source map or bucket table was built for it (the source map
and bucket script in this task both target `drvPPCGNic_reloc`, the statically
linked kernel server that actually contains the driver's compiled code).

---

# The underscore defect and the remap (2026-07-28)

Added by Task 5 of the PPCSerialPort reconstruction
([docs/superpowers/specs/2026-07-28-ppcserialport-reconstruction-design.md](../../../../docs/superpowers/specs/2026-07-28-ppcserialport-reconstruction-design.md),
§3.2 and acceptance item 8). **Nothing was compiled for it** -- there is no
PowerPC toolchain and no host C compiler here, and `make` was not run. Every
claim below is of correspondence between our source and the shipped binary.

## The defect

`drvPPCGNic` has exactly two hand-written C functions with external linkage, and
**both carried a spurious leading underscore in the source identifier**:

| Binary symbol | Old source name | Would have emitted | New source name |
| --- | --- | --- | --- |
| `_ReadGNicRegister` (0x283c, 132 bytes) | `_ReadGNicRegister` | `__ReadGNicRegister` | `ReadGNicRegister` |
| `_WriteGNicRegister` (0x27bc, 128 bytes) | `_WriteGNicRegister` | `__WriteGNicRegister` | `WriteGNicRegister` |

The C compiler prepends exactly one underscore when forming a Mach-O symbol, so a
source identifier that already begins with one produces a symbol with two. Neither
old name could have matched Apple's. That the new names *would* now match follows
from that naming rule; it is **not** an observation of a build.

Fixed in commit `913c733a`, "drivers-ppc: drop the spurious leading underscore
from PPCSerialPort and GNic C functions", which renamed the two definitions, the
two `extern` declarations at `GNicEnetPrivate.m:12-13`, and all 79 call sites
across `GNicEnet.m` and `GNicEnetPrivate.m`.

## The definition-site gate

`symbol_name_check.py` reads the binary's own `__TEXT,__text` symbol table,
filters out compiler runtime, and requires each remaining symbol to have a source
definition named the symbol minus one leading underscore:

```
$ PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
    --binary .../drvPPCGNic.config/drvPPCGNic_reloc \
    --source-dir src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj
hand-written C symbols: 2
missing definitions   : 0
EXIT=0
```

Two symbols, zero missing.

## Before and after, on the same route

The old map used `--scope-to-objc`, whose universe is Objective-C methods only:
it never claimed `_ReadGNicRegister` or `_WriteGNicRegister`, so it could not
report them as unmapped either. To get a real before/after, both runs below use
the **same** route -- `filter_named_functions.py` on the published IDA analysis,
then `source-map --objc-methods` without `--scope-to-objc` -- over the same
52-function universe. The "before" run is against `GNicEnet.{h,m}` and
`GNicEnetPrivate.m` materialised from git at `8f71c8c9`, the rename commit's
parent.

```
                      mapped  unmapped  dup  disputed  sum
before (8f71c8c9)         47         5    0         0   52
after  (renamed)          49         3    0         0   52
```

The two functions moved from `unmapped` to `mapped`; nothing else changed.

Before, `unmapped` was:

```
0x27bc  _WriteGNicRegister                                        128
0x283c  _ReadGNicRegister                                         132
0x28c0  +[drvPPCGNicKernelServerInstance kernelServerInstance]     20
0x28d4  +[drvPPCGNicVersion driverKitVersionFordrvPPCGNic]         16
0x28e4  __udivdi3                                                1616
```

After, it is the three that are not driver code:

```
0x28c0  +[drvPPCGNicKernelServerInstance kernelServerInstance]     20   build-generated
0x28d4  +[drvPPCGNicVersion driverKitVersionFordrvPPCGNic]         16   build-generated
0x28e4  __udivdi3                                               1616   compiler runtime
```

And the two now map to real definition sites:

```
0x27bc  _WriteGNicRegister  128  GNicEnet.m:66
0x283c  _ReadGNicRegister   132  GNicEnet.m:32
```

For reference, the **checked-in** map before this change was the `--scope-to-objc`
one: `mapped 47, unmapped 2, dup 0, disputed 0` over a 49-method universe.
`source-map.json` in this directory is now the 52-function map.

## Reference analysis and identity

The analysis was re-run for this remap
(`BINRECON_REFERENCE=... binrecon analyze --profile tools/binrecon/profiles/gnic-ppc.json`)
and reproduces the identity recorded above:

```
published/analysis-reference-ida.json   functions 156  unnamed 104  lowest 0x160
analysis-named.json                     functions  52  unnamed   0  lowest 0x190
input.sha256 (both)  1D208A3E49CD9DDD6692C81AEACC9C0A5C4BF97F45827EF30DECC495E851B760
```

`analyze` exits 1 on a reference-only profile (no second analyzer to compare
against, so `normalized-functions` cannot pass); the report is complete and the
JSON is written. `filter_named_functions.py` exits 0 and leaves `input.sha256`
untouched.

## Buckets on the new route

```
$ PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/bucket_functions.py \
    tools/binrecon/out/gnic-ppc/analysis-named.json \
    src/drivers-ppc/reconstruction/GNic/source-map.json

total functions: 52
  mapped: 49
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 0
  4-build-generated-class: 2
      0x28c0  +[drvPPCGNicKernelServerInstance kernelServerInstance]  (20 bytes)
      0x28d4  +[drvPPCGNicVersion driverKitVersionFordrvPPCGNic]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 1
      0x28e4  __udivdi3  (1616 bytes)
counted: 52
RECONCILES: yes
```

Bucket 3 is 0 here rather than 104 because the 104 unnamed jump islands were
dropped by `filter_named_functions.py` before the map was built; they are the
same islands the old table counted, not islands that went missing. **Bucket 5 is
0 and stays 0** -- the two C functions no longer need a hand move, because the
map claims them.

Bucket 6's residue is `__udivdi3` alone, unchanged: libgcc's 64-bit unsigned
division helper, compiler runtime rather than a reconstruction gap.

## Unchanged by the remap

- `selector_check.py`: reference selectors 50, our definitions 48, renames 0,
  duplicates 0, missing 2 (the build-generated pair), extra 0, exit 0.
- `ppc_invariant_check.py` still reports one violation, and it is
  `-[GNicEnet(Private) _allocateMemory]` at `0x0` **with code present** -- IDA's
  function list omits a real function there. It is a known exclusion from any
  map's universe, not a phantom and not an absent body, and its correspondence to
  `GNicEnetPrivate.m:115` remains unverified. 6 difference-form relocations, 3
  HI16/HA16-LO16 pairs, 1022 fused relocations.
- The 47 mapped Objective-C methods and their source sites.
