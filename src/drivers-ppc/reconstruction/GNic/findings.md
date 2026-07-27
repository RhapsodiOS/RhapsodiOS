# drvPPCGNic reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCGNic.config/drvPPCGNic` | 8496 | `ED1143591121941501257DB21841CE795014C31C75A2985F9A2F3F49E8D8B159` |
| `drvPPCGNic.config/drvPPCGNic_reloc` | 48432 | `1D208A3E49CD9DDD6692C81AEACC9C0A5C4BF97F45827EF30DECC495E851B760` |

Both re-verified locally with `sha256sum` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`; sizes confirmed with `ls -la`. Both match.

## Correspondence

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
(22 + 26, counted with `grep -c "^[+-]" GNicEnet.m GNicEnetPrivate.m`), one
more than the 46 the task description cites. The extra method,
`-[GNicEnet(Private) _allocateMemory]` (`GNicEnetPrivate.m:115`), has source
but never surfaces as an analysis function -- it is the one entry the
invariant checker (Step 3) flags as a symbol at address `0x0`, so the 156
functions IDA reported never include it and it cannot appear as "mapped" or
"unmapped" against the source map. See Invariant check for detail. That
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
  (`- (BOOL)_allocateMemory`), so source exists for it, but the reference
  binary carries only a symbol-table entry at address 0x0 -- a
  placeholder/unresolved address, not a genuine boundary dispute affecting
  any mapped function. This is the same anomaly the Correspondence section
  above explains: it is why the source has 48 methods but the map only
  reconciles 47.
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
