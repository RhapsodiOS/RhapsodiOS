# drvPPCBMac reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCBMac.config/drvPPCBMac` | 8496 | `193D2E4FA1BF8DD70A48AB78F6335CC416864FE6504546C68774B21603C468C9` |
| `drvPPCBMac.config/drvPPCBMac_reloc` | 77828 | `F940BFBF0B67652409BF430F2A380D432B4BA59EAEE377A5FF218A0AE49DE616` |

Both re-verified locally with `sha256sum` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`; sizes confirmed with `ls -la`. Both match.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCBMac_reloc`, scoped to the Objective-C methods found in that binary
(66 of the 238 total functions IDA reported):

```
mapped 64 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPCBMacKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCBMacVersion driverKitVersionFordrvPPCBMac]'] 16
```

- Total functions in the reference analysis: 238.
- Named Objective-C methods, in scope: 66 -- 64 mapped + 2 unmapped.
- Out of scope: 172, composed of 162 unnamed jump islands (bucket 3) plus 10
  named, non-Objective-C symbols the `--scope-to-objc` map deliberately does
  not claim (bucket 6, see Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0 (from the source-map builder's own semantics; see Invariant
  check below for the one function-start mismatch the invariant checker separately
  flags).

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and
the reference analysis passed to it, so verifying a `--scope-to-objc` map
requires scoping the analysis to the same covered addresses first: the map
does not claim the 162 unnamed jump islands or the 10 non-Objective-C symbols,
and the bucket reconciliation above accounts for those 172 separately.

```
analysis functions 238 -> scoped 66
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/bmac-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/BMac/source-map.json`:

```
total functions: 238
  mapped: 64
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 162
  4-build-generated-class: 2
      0x5170  +[drvPPCBMacKernelServerInstance kernelServerInstance]  (20 bytes)
      0x5184  +[drvPPCBMacVersion driverKitVersionFordrvPPCBMac]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 10
      0x1008  _WriteBigMacRegister  (40 bytes)
      0x1030  _ReadBigMacRegister  (28 bytes)
      0x104c  _clock_out_bit  (132 bytes)
      0x1100  _clock_in_bit  (160 bytes)
      0x11d0  _reset_and_select_srom  (96 bytes)
      0x1260  _read_srom  (180 bytes)
      0x1cd0  _reverseBitOrder  (56 bytes)
      0x4ec0  _crc416  (100 bytes)
      0x4f24  _mace_crc  (68 bytes)
      0x5194  __udivdi3  (1616 bytes)
counted: 238
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`drvPPCBMac_reloc` is a statically linked kernel server, not an `MH_EXECUTE`
helper: it carries no crt/dyld startup routines and its analysis has no
`__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand
against every bucket-6 entry (`grep -rn <symbol> src/kernel-7/bsd/dev/ppc/drvBMacEnet`).
Nine of the ten have a source definition and move to bucket 5:

- `_WriteBigMacRegister` -- `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetHW.m:38`
- `_ReadBigMacRegister` -- `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetHW.m:45`
- `_clock_out_bit` -- `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetHW.m:65`
- `_clock_in_bit` -- `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetHW.m:83`
- `_reset_and_select_srom` -- `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetHW.m:104`
  (declared `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetPrivate.h:41`)
- `_read_srom` -- `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetHW.m:116`
  (declared `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetPrivate.h:42`)
- `_reverseBitOrder` (static) -- `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetPrivate.m:47`
- `_crc416` (static) -- `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetPrivate.m:1622`
- `_mace_crc` (static) -- `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetPrivate.m:1660`

`reverseBitOrder`, `crc416`, and `mace_crc` are the three static C functions
the task description calls out for this source (searching for lines starting
with the word static in the .m files confirms exactly these three function
definitions, alongside other static, non-function declarations in
`BMacEnetPrivate.m` -- six module-scope `IODBDMADescriptor` variables and one
`static int reverse6[]` array). The other six moved entries are non-static
C helpers declared in `BMacEnetPrivate.h` and defined in `BMacEnetHW.m`; the
`--scope-to-objc` source map does not claim them because they are not
Objective-C methods, not because they lack source.

The tenth entry, `__udivdi3`, has no match anywhere under
`src/kernel-7/bsd/dev/ppc/drvBMacEnet`. It is the libgcc 64-bit
unsigned-division runtime helper the PPC compiler emits; it stays in bucket 6
as a real, expected gap -- it is compiler-generated code, not driver source.
No caller could be identified from the reference analysis, which carries no
call-graph edges for this binary.

## Unmapped detail

Two reference selectors have no source-mapped implementation, both
build-generated:

- `+[drvPPCBMacKernelServerInstance kernelServerInstance]` (20 bytes) --
  a KernelServer wrapper class instance accessor emitted by the driver-kit
  build tooling, not hand-written driver code.
- `+[drvPPCBMacVersion driverKitVersionFordrvPPCBMac]` (16 bytes) --
  the DriverKit version accessor, likewise tool-emitted.

Both match the `selector_check.py` "missing" list below exactly.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== bmac-ppc ===
symbol +[BMacEnet probe:] at 0x0 is not a function start
10 scattered/difference-form relocations (target section verified, field is a difference, not an address)
5 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1795 fused relocations, 1 violations
=== bmac-bundle-ppc ===
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

- `bmac-ppc`: `+[BMacEnet probe:]` at address `0x0` is a symbol in
  `__TEXT,__text` that is not one of IDA's recognized function starts. Address
  0x0 is the Mach-O header/load-command region, not a real code address in
  this relocatable object -- this looks like a symbol-table entry with an
  unresolved/placeholder address rather than a genuine boundary dispute
  affecting any mapped function.
- `bmac-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the standard
  synthetic bundle-header symbol Mach-O bundles carry at their load address;
  not a real function, so not a function start either.

Neither candidate overlaps any function reported in the bucket table or the
source map, so neither affects the 64/2/0/0 correspondence numbers above.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 67
our definitions:     65

renames (0):

duplicates (0):

missing (2):
    +[drvPPCBMacKernelServerInstance kernelServerInstance]
    +[drvPPCBMacVersion driverKitVersionFordrvPPCBMac]

extra (0):
```

Exit code: 0. The "missing" two match the source map's unmapped set exactly,
both build-generated (see Unmapped detail) -- there is no "extra" list this
time, unlike Cuda, so `drvBMacEnet`'s selector table has zero surplus
definitions relative to the reference binary's selector table.

## Bundle stub

`drvPPCBMac` (the non-relocatable bundle, profile `bmac-bundle-ppc`) analysis
has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this
small bundle wrapper is a loader shim with no Objective-C methods and no
driver logic of its own, so it carries no correspondence findings against
`drvBMacEnet`. No source map or bucket table was built for it (the source map
and bucket script in this task both target `drvPPCBMac_reloc`, the statically
linked kernel server that actually contains the driver's compiled code).
