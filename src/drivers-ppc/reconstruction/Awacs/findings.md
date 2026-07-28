# drvPPCAwacs reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `PPCAwacs.config/PPCAwacs` | 8492 | `2E263A4D37E210B00F164E91E5DFC35A5605F587247CCB032B92E10F587885A4` |
| `PPCAwacs.config/PPCAwacs_reloc` | 38540 | `D66BE5132E4F53365D346F3ED38515C7D4024DCF13A2A3FD9711D39B04590890` |

Both re-verified locally with `sha256sum` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`. Both match.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`PPCAwacs_reloc`, scoped to the Objective-C methods found in that binary
(40 of the 118 total functions IDA reported):

```
mapped 22 unmapped 18 dup 0 disputed 0
  unmapped: ['-[PPCAwacs resetAwacs]'] 340
  unmapped: ['-[PPCAwacs allocateDMAMemory]'] 408
  unmapped: ['-[PPCAwacs startIO:]'] 268
  unmapped: ['-[PPCAwacs addAudioBuffer:Length:Interrupt:Output:]'] 504
  unmapped: ['-[PPCAwacs loopAudio:]'] 320
  unmapped: ['-[PPCAwacs resetAudio:]'] 216
  unmapped: ['-[PPCAwacs setInputVol:]'] 104
  unmapped: ['-[PPCAwacs setOutputVol:]'] 192
  unmapped: ['-[PPCAwacs setOutputMute:]'] 84
  unmapped: ['-[PPCAwacs setRate:]'] 120
  unmapped: ['-[PPCAwacs setInputSource:]'] 88
  unmapped: ['-[PPCAwacs checkHeadphonesInstalled]'] 320
  unmapped: ['-[PPCAwacs getRate]'] 16
  unmapped: ['-[PPCAwacs getInputSrc]'] 16
  unmapped: ['-[PPCAwacs getOutputVol:]'] 48
  unmapped: ['-[PPCAwacs getInputVol:]'] 48
  unmapped: ['+[PPCAwacsKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[PPCAwacsVersion driverKitVersionForPPCAwacs]'] 16
```

- Total functions in the reference analysis: 118.
- Named Objective-C methods, in scope: 40 -- 22 mapped + 18 unmapped.
- Out of scope: 78, composed of 67 unnamed jump islands (bucket 3) plus 11
  named, non-Objective-C C helper functions the `--scope-to-objc` map
  deliberately does not claim (part of bucket 6, see Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0 (from the source-map builder's own semantics; see
  Invariant check below for the one function-start mismatch the invariant
  checker separately flags).

Sixteen of the 18 unmapped entries are not missing code: they are
`PPCAwacs(Private)` methods whose reference selector has no underscore
prefix while the RhapsodiOS source's equivalent method is a private,
underscore-prefixed selector (`-resetAwacs` in the reference vs.
`-_resetAwacs` in source, etc.). Because Objective-C dispatches on the
exact selector string, the source-map's structural matcher correctly refuses
to call these a match; see Buckets and Selector check below for the full
sixteen and their source sites. Only 2 of the 18 unmapped entries are a real
gap (the build-generated class accessors, see Unmapped detail).

## Map validation

`load_source_map` enforces an exact partition between the map's addresses
and the reference analysis passed to it, so verifying a `--scope-to-objc`
map requires scoping the analysis to the same covered addresses first: the
map does not claim the 67 unnamed jump islands or the 11 non-Objective-C C
helper functions, and the bucket reconciliation below accounts for those 78
separately.

```
analysis functions 118 -> scoped 40
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/awacs-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/Awacs/source-map.json`:

```
total functions: 118
  mapped: 22
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 67
  4-build-generated-class: 2
      0x1e58  +[PPCAwacsKernelServerInstance kernelServerInstance]  (20 bytes)
      0x1e6c  +[PPCAwacsVersion driverKitVersionForPPCAwacs]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 27
      0x304  _PPCSoundOutputInt  (160 bytes)
      0x3d4  _PPCSoundInputInt  (160 bytes)
      0xbc0  _clearInterrupts  (12 bytes)
      0xbe0  -[PPCAwacs resetAwacs]  (340 bytes)
      0xd84  _serviceOutputInterrupt  (232 bytes)
      0xe7c  _serviceInputInterrupt  (232 bytes)
      0xf74  -[PPCAwacs allocateDMAMemory]  (408 bytes)
      0x116c  -[PPCAwacs startIO:]  (268 bytes)
      0x1288  -[PPCAwacs addAudioBuffer:Length:Interrupt:Output:]  (504 bytes)
      0x14c0  -[PPCAwacs loopAudio:]  (320 bytes)
      0x1660  -[PPCAwacs resetAudio:]  (216 bytes)
      0x1778  -[PPCAwacs setInputVol:]  (104 bytes)
      0x1800  -[PPCAwacs setOutputVol:]  (192 bytes)
      0x18e0  -[PPCAwacs setOutputMute:]  (84 bytes)
      0x1944  -[PPCAwacs setRate:]  (120 bytes)
      0x19cc  -[PPCAwacs setInputSource:]  (88 bytes)
      0x1a34  -[PPCAwacs checkHeadphonesInstalled]  (320 bytes)
      0x1bb4  _scale_volume  (172 bytes)
      0x1c60  _unscale_volume  (164 bytes)
      0x1d04  -[PPCAwacs getRate]  (16 bytes)
      0x1d14  -[PPCAwacs getInputSrc]  (16 bytes)
      0x1d24  -[PPCAwacs getOutputVol:]  (48 bytes)
      0x1d64  -[PPCAwacs getInputVol:]  (48 bytes)
      0x1da4  _writeCodecControlReg  (76 bytes)
      0x1df0  _writeSoundControlReg  (40 bytes)
      0x1e18  _readCodecStatusReg  (32 bytes)
      0x1e38  _readClippingCountReg  (32 bytes)
counted: 118
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`PPCAwacs_reloc` is a statically linked kernel server, not an `MH_EXECUTE`
helper: it carries no crt/dyld startup routines and its analysis has no
`__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand
against every bucket-6 entry, by grepping
`src/drivers-ppc/sound/drvPPCAwacs/PPCAwacs.drvproj/PPCAwacs.lksproj`
for each symbol. All 27 entries have a confirmed source site and move to
bucket 5, in two distinct groups:

**Eleven non-static C helper functions** (name matches the reference symbol
exactly; declared in `PPCSound.h`, defined in `PPCSound.m`):

- `_PPCSoundOutputInt` -- `PPCSound.m:852` (declared `PPCSound.h:188`)
- `_PPCSoundInputInt` -- `PPCSound.m:819` (declared `PPCSound.h:187`)
- `_clearInterrupts` -- `PPCSound.m:886` (declared `PPCSound.h:191`)
- `_serviceOutputInterrupt` -- `PPCSound.m:772` (declared `PPCSound.h:190`)
- `_serviceInputInterrupt` -- `PPCSound.m:724` (declared `PPCSound.h:189`)
- `_scale_volume` -- `PPCSound.m:156` (declared `PPCSound.h:183`)
- `_unscale_volume` -- `PPCSound.m:196` (declared `PPCSound.h:184`)
- `_writeCodecControlReg` -- `PPCSound.m:88` (declared `PPCSound.h:178`)
- `_writeSoundControlReg` -- `PPCSound.m:114` (declared `PPCSound.h:179`)
- `_readCodecStatusReg` -- `PPCSound.m:75` (declared `PPCSound.h:177`)
- `_readClippingCountReg` -- `PPCSound.m:62` (declared `PPCSound.h:176`)

These are exact-name matches; the `--scope-to-objc` source map does not
claim them only because they are not Objective-C methods. (This driver has
one more such helper than Burgundy's ten -- `_unscale_volume` -- which has
no counterpart in the Burgundy source at all.)

**Sixteen renamed `PPCAwacs(Private)` methods.** The reference binary's
selector has no underscore prefix; the source's equivalent method is the
same private method under an underscore-prefixed selector. `selector_check.py`
(see Selector check below) independently confirms each pairing and gives the
exact source line, reproduced here:

- `-[PPCAwacs resetAwacs]` -> `-[PPCAwacs(Private) _resetAwacs]` -- `PPCSoundPrivate.m:477`
- `-[PPCAwacs allocateDMAMemory]` -> `_allocateDMAMemory` -- `PPCSoundPrivate.m:119`
- `-[PPCAwacs startIO:]` -> `_startIO:` -- `PPCSoundPrivate.m:679`
- `-[PPCAwacs addAudioBuffer:Length:Interrupt:Output:]` -> `_addAudioBuffer:Length:Interrupt:Output:` -- `PPCSoundPrivate.m:20`
- `-[PPCAwacs loopAudio:]` -> `_loopAudio:` -- `PPCSoundPrivate.m:349`
- `-[PPCAwacs resetAudio:]` -> `_resetAudio:` -- `PPCSoundPrivate.m:414`
- `-[PPCAwacs setInputVol:]` -> `_setInputVol:` -- `PPCSoundPrivate.m:576`
- `-[PPCAwacs setOutputVol:]` -> `_setOutputVol:` -- `PPCSoundPrivate.m:617`
- `-[PPCAwacs setOutputMute:]` -> `_setOutputMute:` -- `PPCSoundPrivate.m:594`
- `-[PPCAwacs setRate:]` -> `_setRate:` -- `PPCSoundPrivate.m:645`
- `-[PPCAwacs setInputSource:]` -> `_setInputSource:` -- `PPCSoundPrivate.m:549`
- `-[PPCAwacs checkHeadphonesInstalled]` -> `_checkHeadphonesInstalled` -- `PPCSoundPrivate.m:208`
- `-[PPCAwacs getRate]` -> `_getRate` -- `PPCSoundPrivate.m:339`
- `-[PPCAwacs getInputSrc]` -> `_getInputSrc` -- `PPCSoundPrivate.m:288`
- `-[PPCAwacs getOutputVol:]` -> `_getOutputVol:` -- `PPCSoundPrivate.m:318`
- `-[PPCAwacs getInputVol:]` -> `_getInputVol:` -- `PPCSoundPrivate.m:297`

These are confirmed source sites, not confirmed identical selectors: the
method body exists at the cited file/line, but under a different
Objective-C selector than the one the reference binary exports. A message
send to the reference's exact selector name (e.g. `resetAwacs`) would not
resolve against this class as currently written; only the underscore-prefixed
form would. See Reimplementation note.

No static C functions were found anywhere in the source directory (grep for
lines starting with `static` in the `.m` files matches only local variable
declarations, never a function definition), the same result as Burgundy.

## Unmapped detail

Eighteen reference selectors have no exact-name-matching source
implementation:

- Sixteen `PPCAwacs(Private)` methods, all renamed (see Buckets above) --
  the underlying logic exists, but under a different, underscore-prefixed
  selector.
- Two are build-generated, matching the same pattern seen in Burgundy, Cuda
  and BMac:
  - `+[PPCAwacsKernelServerInstance kernelServerInstance]` (20 bytes) --
    a KernelServer wrapper class instance accessor emitted by the driver-kit
    build tooling, not hand-written driver code.
  - `+[PPCAwacsVersion driverKitVersionForPPCAwacs]` (16 bytes) -- the
    DriverKit version accessor, likewise tool-emitted.

All eighteen match the `selector_check.py` "renames" (16) and "missing" (2)
lists exactly.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== awacs-ppc ===
symbol +[PPCAwacs probe:] at 0x0 is not a function start
8 scattered/difference-form relocations (target section verified, field is a difference, not an address)
4 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
630 fused relocations, 1 violations
=== awacs-bundle-ppc ===
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

- `awacs-ppc`: `+[PPCAwacs probe:]` at address `0x0` is a symbol in
  `__TEXT,__text` that is not one of IDA's recognized function starts.
  Confirmed this symbol does not appear anywhere in the 118-entry function
  list of `analysis-reference-ida.json` (checked programmatically), the
  same pattern seen for `+[PPCBurgundy probe:]` and `+[AppleOHare probe:]`
  in the earlier batches.
> **CORRECTION.** The bullet above read `ppc_invariant_check.py`'s "is not a function
> start" message as "there is no code at that address", and called address 0x0 an
> unresolved/placeholder address rather than a real code address. That was wrong, and the
> same misreading was repeated across every driver spec in this series. `__text+0` in
> `PPCAwacs_reloc` holds `7c0802a6` -- `mflr r0` -- and it is IDA's *analysis* that omits
> the function there, not Apple's binary that omits the code. `read_macho` reports address
> `0` for every undefined symbol too (`_IOLog`, `_objc_msgSend`, ...), which is what made a
> defined symbol at `__text+0` look empty.
>
> **`+[PPCAwacs probe:]` is a real function the analysis does not record, not a phantom.**
> It is an unmapped real function -- a genuine gap, not an artifact of the tooling. Its
> body is not written here; that is separate work. Nothing was re-measured for this
> correction and no source map was regenerated: the mapped/unmapped counts above are
> unaffected, because IDA never had this function to map. The checker now distinguishes the
> two cases. See `src/drivers-ppc/reconstruction/IOADBDevice/findings.md`,
> "The misreading".

- `awacs-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the standard
  synthetic bundle-header symbol Mach-O bundles carry at their load
  address; not a real function, so not a function start either.

Neither candidate overlaps any function reported in the bucket table or the
source map, so neither affects the 22/18/0/0 correspondence numbers above.
Unlike Burgundy, where `+probe:` is also absent from source under any name,
this driver's `PPCSound.m:227` defines `+ (BOOL)probe:(IODeviceDescription *)`
with the exact reference selector name -- so `selector_check.py`'s "missing"
list below does *not* include `probe:` here, because the source does
implement it. Its absence from the reference's 118-function IDA list is an
analysis-side artifact -- but, per the correction above, Apple's `probe:` body
at `__text+0` is real, so `PPCSound.m:227`'s correspondence to it is
*unverified* rather than *unnecessary*: nothing here has compared the two.

## Selector check

`selector_check.py` output, verbatim:

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

Of the 41 reference selectors: 23 match by exact name (41 - 16 renames - 2
missing), 16 are implemented under a renamed, underscore-prefixed private
selector, and 2 are build-generated accessors with no source counterpart
under any name. Confirmed `+[PPCAwacs probe:]` is one of the 23 exact
matches (`PPCSound.m:227`), not a gap -- unlike Burgundy, where the
equivalent `probe:` selector was entirely absent from source.

23 (exact) + 16 (renamed) + 2 (missing) = 41 reference selectors.
23 (exact) + 16 (renamed) + 0 (extra) = 39 our definitions. Both totals
reconcile with the header counts above.

## Bundle stub

`PPCAwacs` (the non-relocatable bundle, profile `awacs-bundle-ppc`)
analysis has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) --
this small bundle wrapper is a loader shim with no Objective-C methods and
no driver logic of its own, so it carries no correspondence findings
against `PPCAwacs`. No source map or bucket table was built for it (the
source map and bucket script in this task both target `PPCAwacs_reloc`, the
statically linked kernel server that actually contains the driver's
compiled code).

## Reimplementation note

`PPCAwacs`'s source at
`src/drivers-ppc/sound/drvPPCAwacs/PPCAwacs.drvproj/PPCAwacs.lksproj` is a
RhapsodiOS reimplementation, not Apple's own shipped source: `PPCSound.m`
carries both `Copyright (c) 1999 Apple Computer, Inc.` and
`Copyright (c) 2025 RhapsodiOS Project` headers, and 17 of its ~38 method
definitions in that file are underscore-prefixed. This is the second
reimplementation measured in this batch, after `drvPPCBurgundy`, and the
task set out to test whether Burgundy's underscore-prefix convention for
private selectors is a project-wide practice or a one-off.

**The underscore-rename hypothesis, tested explicitly:**

For every reference selector `selector_check.py` reported **missing** (2:
`+[PPCAwacsKernelServerInstance kernelServerInstance]` and
`+[PPCAwacsVersion driverKitVersionForPPCAwacs]`), checked whether an
underscore-prefixed source selector `_<selector>` exists anywhere in the
`.lksproj` directory (grepped for `_kernelServerInstance` and
`_driverKitVersionForPPCAwacs`): **neither does.** These are DriverKit
build-tooling-generated class accessors on separate wrapper classes
(`PPCAwacsKernelServerInstance`, `PPCAwacsVersion`), not `PPCAwacs(Private)`
methods, so there is no hand-written implementation under any name to rename
-- 0 of 2 missing correspond under the underscore transformation.

For every selector `selector_check.py` reported **extra** (0: the extra
list is empty), checked whether stripping a leading underscore from a
source-only selector would yield a reference selector: vacuously, 0 of 0
correspond (there is nothing to check).

For the 16 selectors that *did* rename, the correspondence is exact and
complete: every one of the 16 reference selectors reported "missing" from a
plain `--objc-methods` source map (`resetAwacs`, `allocateDMAMemory`,
`startIO:`, `addAudioBuffer:Length:Interrupt:Output:`, `loopAudio:`,
`resetAudio:`, `setInputVol:`, `setOutputVol:`, `setOutputMute:`,
`setRate:`, `setInputSource:`, `checkHeadphonesInstalled`, `getRate`,
`getInputSrc`, `getOutputVol:`, `getInputVol:`) corresponds to a
`PPCAwacs(Private)` method under the exact underscore-prefixed selector
(`_resetAwacs`, `_allocateDMAMemory`, `_startIO:`, ...) at a confirmed
source line. 16 of 16 correspond -- the same 16-of-16 rate Burgundy showed
for its own private-method set.

**Result: the convention repeats.** Both reimplementations in the tree
apply the identical rule -- every `IOAudio` subclass's private-category
methods are defined under an underscore-prefixed selector, one character
different from the reference binary's public-looking (but actually private)
selector. The arithmetic, kept in the same shape as Burgundy's:

- Burgundy: 21 exact + 16 renamed + 3 missing = 40 reference selectors
  (missing = 2 build-generated accessors + 1 genuinely absent `probe:`).
- Awacs: 23 exact + 16 renamed + 2 missing = 41 reference selectors
  (missing = 2 build-generated accessors only; `probe:` is present here,
  under its exact reference name, so it counts among the 23 exact matches
  rather than among the missing).

The renamed set is 16 of 16 for both drivers -- full correspondence under
the underscore transformation, with zero counterexamples in either
direction (no missing selector's underscore form exists in either driver's
"missing" bucket, and Awacs has zero extras to check). Awacs differs from
Burgundy only in the *size* of its non-renamed gap (2 vs. 3, because Awacs's
source does implement `probe:` under its exact reference selector while
Burgundy's does not) and in carrying one additional non-static C helper,
`_unscale_volume`, that has no Burgundy counterpart. Both are consistent
with a single, deliberate project-wide convention: private `IOAudio`
subclass methods get an underscore prefix in RhapsodiOS's reimplementation,
regardless of driver.
