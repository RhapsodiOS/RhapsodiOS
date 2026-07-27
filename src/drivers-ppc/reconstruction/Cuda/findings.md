# drvPPCCuda reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCCuda.config/drvPPCCuda` | 8496 | `B82C4317C9DE095AC20C96FB69D902AE7C90DEAA6DB2443F50A7C3AAA5B1C07A` |
| `drvPPCCuda.config/drvPPCCuda_reloc` | 43328 | `8CA26E3452246DE99BBD1731586B154B0B339DF3F4C2E65A50C000CC33EE1D1F` |

Both re-verified locally with `certutil -hashfile ... SHA256` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`; sizes confirmed with `ls -la`. Both match.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCCuda_reloc`, scoped to the Objective-C methods found in that binary
(40 of the 100 total functions IDA reported):

```
mapped 37 unmapped 3 dup 0 disputed 0
  unmapped: ['-[AppleCuda StartCudaTransmission:]'] 284
  unmapped: ['+[drvPPCCudaKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCCudaVersion driverKitVersionFordrvPPCCuda]'] 16
MATCHES CALIBRATION
```

- Total functions in the reference analysis: 100.
- Named (Objective-C methods, in scope): 40 -- 37 mapped + 3 unmapped.
- Unnamed: 60 (all unnamed jump islands; see Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0 (from the source-map builder's own semantics; see Invariant
  check below for the one function-start mismatch the invariant checker separately
  flags).

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/cuda-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/Cuda/source-map.json`:

```
total functions: 100
  mapped: 37
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 60
  4-build-generated-class: 2
      0x2428  +[drvPPCCudaKernelServerInstance kernelServerInstance]  (20 bytes)
      0x243c  +[drvPPCCudaVersion driverKitVersionFordrvPPCCuda]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 1
      0x179c  -[AppleCuda StartCudaTransmission:]  (284 bytes)
counted: 100
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`drvPPCCuda_reloc` is a statically linked kernel server, not an `MH_EXECUTE`
helper: it carries no crt/dyld startup routines and its analysis has no
`__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 (`fn-with-source-site`) is 0 straight out of the script, as expected --
it is populated only by hand after triage of bucket 6. For Cuda,
`src/kernel-7/bsd/dev/ppc/drvCuda/cuda.m` defines 0 static C functions (only
static *variables*; every function in the file is an Objective-C method), and
the single bucket-6 entry, `-[AppleCuda StartCudaTransmission:]`, is itself an
Objective-C method that the source map could not place (see Unmapped detail).
No entries were moved from bucket 6 to bucket 5.

## Unmapped detail

Three reference selectors have no source-mapped implementation:

- `+[drvPPCCudaKernelServerInstance kernelServerInstance]` (20 bytes) --
  build-generated: a KernelServer wrapper class instance accessor emitted by
  the driver-kit build tooling, not hand-written driver code.
- `+[drvPPCCudaVersion driverKitVersionFordrvPPCCuda]` (16 bytes) --
  build-generated: the DriverKit version accessor, likewise tool-emitted.
- `-[AppleCuda StartCudaTransmission:]` (284 bytes) -- **the one real gap**.
  `cuda.m` contains a method block under that name at line 1399, but its
  signature line ends in a stray `;` before the opening `{` (every other method
  in the file omits that semicolon -- confirmed by scanning all 27 other
  `- (` signature lines in the file). That semicolon turns the line into a bare
  forward declaration, so the block that follows is not attached to it as an
  implementation. `selector_check.py`, which parses real method definitions
  independently of the source-map builder, agrees: it lists this selector
  under "missing" (see Selector check below), not among "our definitions:
  40". Net effect: `drvCuda/cuda.m` does not currently define this selector,
  matching the source map's classification of it as unmapped.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== cuda-ppc ===
symbol +[AppleCuda probe:] at 0x0 is not a function start
53 scattered/difference-form relocations (target section verified, field is a difference, not an address)
2 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
949 fused relocations, 1 violations
=== cuda-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

Actual relocation-decode violations (`check_document`, the byte-order and
HI16/HA16-LO16 agreement checks): **0** for both binaries. The single
"violation" counted for each run is a symbol/function-start mismatch from
`check_functions`, not a relocation defect. Recorded as `boundary_disputed`
candidates:

- `cuda-ppc`: `+[AppleCuda probe:]` at address `0x0` is a symbol in
  `__TEXT,__text` that is not one of IDA's recognized function starts. Address
  0x0 is the Mach-O header/load-command region, not a real code address in
  this relocatable object -- this looks like a symbol-table entry with an
  unresolved/placeholder address rather than a genuine boundary dispute
  affecting any mapped function.
- `cuda-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the standard
  synthetic bundle-header symbol Mach-O bundles carry at their load address;
  not a real function, so not a function start either.

Neither candidate overlaps any function reported in the bucket table or the
source map, so neither affects the 37/3/0/0 correspondence numbers above.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 41
our definitions:     40

renames (0):

duplicates (0):

missing (3):
    +[drvPPCCudaKernelServerInstance kernelServerInstance]
    +[drvPPCCudaVersion driverKitVersionFordrvPPCCuda]
    -[AppleCuda StartCudaTransmission:]

extra (2):
    -[AppleCuda ADBSetFileServerMode:::]
    -[AppleCuda setPowerupTime::::]
```

Exit code: 0. The "missing" three match the source map's unmapped set exactly
(two build-generated, one real gap -- see Unmapped detail). The "extra" two are
selectors `cuda.m` defines (`ADBSetFileServerMode:` with 3 keyword parts,
`setPowerupTime:` with 4) that the reference binary's selector table does not
carry under that exact name; this is a finding to record, not a task failure,
and is orthogonal to the function-address correspondence measured above (the
source map operates on IDA function addresses, not selector-table name
matching).

## Bundle stub

`drvPPCCuda` (the non-relocatable bundle, profile `cuda-bundle-ppc`) analysis
has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this
small bundle wrapper is a loader shim with no Objective-C methods and no
driver logic of its own, so it carries no correspondence findings against
`drvCuda`. No source map or bucket table was built for it (the source map and
bucket script in this task both target `drvPPCCuda_reloc`, the statically
linked kernel server that actually contains the driver's compiled code).
