# drvPPCBurgundy reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCBurgundy.config/drvPPCBurgundy` | 8504 | `D16D9B2355C96D6CEEBEA6346454BE438D5B5DB589F53BD8EDB457182304A1CE` |
| `drvPPCBurgundy.config/drvPPCBurgundy_reloc` | 38652 | `D49E3479C9F0D2E7417A10ABAA3DC7D49562C1D4D2E1DCE77CAE467B96EB97CE` |

Both re-verified locally with `sha256sum` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`. Both match.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCBurgundy_reloc`, scoped to the Objective-C methods found in that binary
(39 of the 111 total functions IDA reported):

```
mapped 21 unmapped 18 dup 0 disputed 0
  unmapped: ['-[PPCBurgundy resetBurgundy]'] 608
  unmapped: ['-[PPCBurgundy allocateDMAMemory]'] 408
  unmapped: ['-[PPCBurgundy startIO:]'] 268
  unmapped: ['-[PPCBurgundy addAudioBuffer:Length:Interrupt:Output:]'] 504
  unmapped: ['-[PPCBurgundy loopAudio:]'] 320
  unmapped: ['-[PPCBurgundy resetAudio:]'] 216
  unmapped: ['-[PPCBurgundy setInputVol:]'] 120
  unmapped: ['-[PPCBurgundy setOutputVol:]'] 152
  unmapped: ['-[PPCBurgundy setOutputMute:]'] 120
  unmapped: ['-[PPCBurgundy setRate:]'] 60
  unmapped: ['-[PPCBurgundy setInputSource:]'] 344
  unmapped: ['-[PPCBurgundy checkHeadphonesInstalled]'] 156
  unmapped: ['-[PPCBurgundy getRate]'] 16
  unmapped: ['-[PPCBurgundy getInputSrc]'] 16
  unmapped: ['-[PPCBurgundy getOutputVol:]'] 12
  unmapped: ['-[PPCBurgundy getInputVol:]'] 12
  unmapped: ['+[drvPPCBurgundyKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCBurgundyVersion driverKitVersionFordrvPPCBurgundy]'] 16
```

- Total functions in the reference analysis: 111.
- Named Objective-C methods, in scope: 39 -- 21 mapped + 18 unmapped.
- Out of scope: 72, composed of 62 unnamed jump islands (bucket 3) plus 10
  named, non-Objective-C C helper functions the `--scope-to-objc` map
  deliberately does not claim (part of bucket 6, see Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0 (from the source-map builder's own semantics; see
  Invariant check below for the one function-start mismatch the invariant
  checker separately flags).

Sixteen of the 18 unmapped entries are not missing code: they are
`PPCBurgundy(Private)` methods whose reference selector has no underscore
prefix while the RhapsodiOS source's equivalent method is a private,
underscore-prefixed selector (`-resetBurgundy` in the reference vs.
`-_resetBurgundy` in source, etc.). Because Objective-C dispatches on the
exact selector string, the source-map's structural matcher correctly refuses
to call these a match; see Buckets and Selector check below for the full
sixteen and their source sites. Only 2 of the 18 unmapped entries are a real
gap (the build-generated class accessors, see Unmapped detail).

## Map validation

`load_source_map` enforces an exact partition between the map's addresses
and the reference analysis passed to it, so verifying a `--scope-to-objc`
map requires scoping the analysis to the same covered addresses first: the
map does not claim the 62 unnamed jump islands or the 10 non-Objective-C C
helper functions, and the bucket reconciliation below accounts for those 72
separately.

```
analysis functions 111 -> scoped 39
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/burgundy-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/Burgundy/source-map.json`:

```
total functions: 111
  mapped: 21
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 62
  4-build-generated-class: 2
      0x1f10  +[drvPPCBurgundyKernelServerInstance kernelServerInstance]  (20 bytes)
      0x1f24  +[drvPPCBurgundyVersion driverKitVersionFordrvPPCBurgundy]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 26
      0x238  _PPCSoundOutputInt  (160 bytes)
      0x308  _PPCSoundInputInt  (160 bytes)
      0xa78  _clearInterrupts  (12 bytes)
      0xa98  -[PPCBurgundy resetBurgundy]  (608 bytes)
      0xd28  _serviceOutputInterrupt  (232 bytes)
      0xe20  _serviceInputInterrupt  (232 bytes)
      0xf18  -[PPCBurgundy allocateDMAMemory]  (408 bytes)
      0x1110  -[PPCBurgundy startIO:]  (268 bytes)
      0x122c  -[PPCBurgundy addAudioBuffer:Length:Interrupt:Output:]  (504 bytes)
      0x1464  -[PPCBurgundy loopAudio:]  (320 bytes)
      0x1604  -[PPCBurgundy resetAudio:]  (216 bytes)
      0x171c  -[PPCBurgundy setInputVol:]  (120 bytes)
      0x17b4  -[PPCBurgundy setOutputVol:]  (152 bytes)
      0x186c  -[PPCBurgundy setOutputMute:]  (120 bytes)
      0x18f4  -[PPCBurgundy setRate:]  (60 bytes)
      0x1940  -[PPCBurgundy setInputSource:]  (344 bytes)
      0x1ab8  -[PPCBurgundy checkHeadphonesInstalled]  (156 bytes)
      0x1b84  _scale_volume  (140 bytes)
      0x1c10  -[PPCBurgundy getRate]  (16 bytes)
      0x1c20  -[PPCBurgundy getInputSrc]  (16 bytes)
      0x1c30  -[PPCBurgundy getOutputVol:]  (12 bytes)
      0x1c3c  -[PPCBurgundy getInputVol:]  (12 bytes)
      0x1c48  _writeCodecReg  (204 bytes)
      0x1d14  _readCodecReg  (420 bytes)
      0x1ec8  _readCodecSenseLines  (32 bytes)
      0x1ee8  _writeSoundControlReg  (40 bytes)
counted: 111
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`drvPPCBurgundy_reloc` is a statically linked kernel server, not an
`MH_EXECUTE` helper: it carries no crt/dyld startup routines and its
analysis has no `__picsymbol_stub` section for the stub-range check to match
against.

Bucket 5 prints 0 from the script by construction; it is populated by hand
against every bucket-6 entry, by grepping
`src/drivers-ppc/sound/drvPPCBurgundy/PPCBurgundy.drvproj/PPCBurgundy.lksproj`
for each symbol. All 26 entries have a confirmed source site and move to
bucket 5, in two distinct groups:

**Ten non-static C helper functions** (name matches the reference symbol
exactly; declared in `BurgundySound.h`, defined in `BurgundySound.m`):

- `_PPCSoundOutputInt` -- `BurgundySound.m:290` (declared `BurgundySound.h:148`)
- `_PPCSoundInputInt` -- `BurgundySound.m:268` (declared `BurgundySound.h:147`)
- `_clearInterrupts` -- `BurgundySound.m:259` (declared `BurgundySound.h:151`)
- `_serviceOutputInterrupt` -- `BurgundySound.m:350` (declared `BurgundySound.h:150`)
- `_serviceInputInterrupt` -- `BurgundySound.m:312` (declared `BurgundySound.h:149`)
- `_scale_volume` -- `BurgundySound.m:227` (declared `BurgundySound.h:162`)
- `_writeCodecReg` -- `BurgundySound.m:150` (declared `BurgundySound.h:158`)
- `_readCodecReg` -- `BurgundySound.m:77` (declared `BurgundySound.h:156`)
- `_readCodecSenseLines` -- `BurgundySound.m:144` (declared `BurgundySound.h:157`)
- `_writeSoundControlReg` -- `BurgundySound.m:192` (declared `BurgundySound.h:159`)

These are exact-name matches; the `--scope-to-objc` source map does not
claim them only because they are not Objective-C methods.

**Sixteen renamed `PPCBurgundy(Private)` methods.** The reference binary's
selector has no underscore prefix; the source's equivalent method is the
same private method under an underscore-prefixed selector. `selector_check.py`
(see Selector check below) independently confirms each pairing and gives the
exact source line, reproduced here:

- `-[PPCBurgundy resetBurgundy]` -> `-[PPCBurgundy(Private) _resetBurgundy]` -- `BurgundySoundPrivate.m:287`
- `-[PPCBurgundy allocateDMAMemory]` -> `_allocateDMAMemory` -- `BurgundySoundPrivate.m:121`
- `-[PPCBurgundy startIO:]` -> `_startIO:` -- `BurgundySoundPrivate.m:471`
- `-[PPCBurgundy addAudioBuffer:Length:Interrupt:Output:]` -> `_addAudioBuffer:Length:Interrupt:Output:` -- `BurgundySoundPrivate.m:40`
- `-[PPCBurgundy loopAudio:]` -> `_loopAudio:` -- `BurgundySoundPrivate.m:185`
- `-[PPCBurgundy resetAudio:]` -> `_resetAudio:` -- `BurgundySoundPrivate.m:240`
- `-[PPCBurgundy setInputVol:]` -> `_setInputVol:` -- `BurgundySoundPrivate.m:388`
- `-[PPCBurgundy setOutputVol:]` -> `_setOutputVol:` -- `BurgundySoundPrivate.m:433`
- `-[PPCBurgundy setOutputMute:]` -> `_setOutputMute:` -- `BurgundySoundPrivate.m:409`
- `-[PPCBurgundy setRate:]` -> `_setRate:` -- `BurgundySoundPrivate.m:459`
- `-[PPCBurgundy setInputSource:]` -> `_setInputSource:` -- `BurgundySoundPrivate.m:348`
- `-[PPCBurgundy checkHeadphonesInstalled]` -> `_checkHeadphonesInstalled` -- `BurgundySoundPrivate.m:129`
- `-[PPCBurgundy getRate]` -> `_getRate` -- `BurgundySoundPrivate.m:179`
- `-[PPCBurgundy getInputSrc]` -> `_getInputSrc` -- `BurgundySoundPrivate.m:161`
- `-[PPCBurgundy getOutputVol:]` -> `_getOutputVol:` -- `BurgundySoundPrivate.m:173`
- `-[PPCBurgundy getInputVol:]` -> `_getInputVol:` -- `BurgundySoundPrivate.m:167`

These are confirmed source sites, not confirmed identical selectors: the
method body exists at the cited file/line, but under a different
Objective-C selector than the one the reference binary exports. A message
send to the reference's exact selector name (e.g. `resetBurgundy`) would not
resolve against this class as currently written; only the underscore-prefixed
form would. This is recorded as the central reimplementation gap, not
papered over -- see Reimplementation note.

No static C functions were found anywhere in the source directory (grep for
lines starting with `static` in the `.m` files matches only local variable
declarations, never a function definition), matching the task brief's
prediction of 0 static C functions for this driver.

## Unmapped detail

Eighteen reference selectors have no exact-name-matching source
implementation:

- Sixteen `PPCBurgundy(Private)` methods, all renamed (see Buckets above)
  -- the underlying logic exists, but under a different, underscore-prefixed
  selector.
- Two are build-generated, matching the same pattern seen in Cuda and BMac:
  - `+[drvPPCBurgundyKernelServerInstance kernelServerInstance]` (20 bytes) --
    a KernelServer wrapper class instance accessor emitted by the driver-kit
    build tooling, not hand-written driver code.
  - `+[drvPPCBurgundyVersion driverKitVersionFordrvPPCBurgundy]` (16 bytes) --
    the DriverKit version accessor, likewise tool-emitted.

All eighteen match the `selector_check.py` "renames" (16) and "missing" (2 of
the 3, see Selector check) lists exactly.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== burgundy-ppc ===
symbol +[PPCBurgundy probe:] at 0x0 is not a function start
4 scattered/difference-form relocations (target section verified, field is a difference, not an address)
2 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
623 fused relocations, 1 violations
=== burgundy-bundle-ppc ===
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

- `burgundy-ppc`: `+[PPCBurgundy probe:]` at address `0x0` is a symbol in
  `__TEXT,__text` that is not one of IDA's recognized function starts.
  Confirmed this symbol does not appear anywhere in the 111-entry function
  list of `analysis-reference-ida.json` (checked programmatically), the
  same pattern documented for `+[BMacEnet probe:]` in the BMac task: address
  0x0 is a symbol-table entry with an unresolved/placeholder address, not a
  real code address in this relocatable object.
- `burgundy-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the
  standard synthetic bundle-header symbol Mach-O bundles carry at their
  load address; not a real function, so not a function start either.

Neither candidate overlaps any function reported in the bucket table or the
source map, so neither affects the 21/18/0/0 correspondence numbers above.
This also explains why `selector_check.py`'s "missing" list below includes
`+[PPCBurgundy probe:]` even though the source map's `unmapped` list does
not: `probe:` is a real, named selector in the reference binary's symbol
table, but it resolves to address 0x0, so IDA's function list -- and
therefore the `--scope-to-objc` source map built from it -- never counts it
as one of the 39 in-scope functions in the first place.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 40
our definitions:     38

renames (16):
    -[PPCBurgundy(Private) _addAudioBuffer:Length:Interrupt:Output:] BurgundySoundPrivate.m:40
    -[PPCBurgundy(Private) _allocateDMAMemory]                 BurgundySoundPrivate.m:121
    -[PPCBurgundy(Private) _checkHeadphonesInstalled]          BurgundySoundPrivate.m:129
    -[PPCBurgundy(Private) _getInputSrc]                       BurgundySoundPrivate.m:161
    -[PPCBurgundy(Private) _getInputVol:]                      BurgundySoundPrivate.m:167
    -[PPCBurgundy(Private) _getOutputVol:]                     BurgundySoundPrivate.m:173
    -[PPCBurgundy(Private) _getRate]                           BurgundySoundPrivate.m:179
    -[PPCBurgundy(Private) _loopAudio:]                        BurgundySoundPrivate.m:185
    -[PPCBurgundy(Private) _resetAudio:]                       BurgundySoundPrivate.m:240
    -[PPCBurgundy(Private) _resetBurgundy]                     BurgundySoundPrivate.m:287
    -[PPCBurgundy(Private) _setInputSource:]                   BurgundySoundPrivate.m:348
    -[PPCBurgundy(Private) _setInputVol:]                      BurgundySoundPrivate.m:388
    -[PPCBurgundy(Private) _setOutputMute:]                    BurgundySoundPrivate.m:409
    -[PPCBurgundy(Private) _setOutputVol:]                     BurgundySoundPrivate.m:433
    -[PPCBurgundy(Private) _setRate:]                          BurgundySoundPrivate.m:459
    -[PPCBurgundy(Private) _startIO:]                          BurgundySoundPrivate.m:471

duplicates (0):

missing (3):
    +[PPCBurgundy probe:]
    +[drvPPCBurgundyKernelServerInstance kernelServerInstance]
    +[drvPPCBurgundyVersion driverKitVersionFordrvPPCBurgundy]

extra (1):
    -[PPCBurgundy updateSampleRate:]
```

Exit code: 1.

This is the most interesting output in the whole task. Of the 40 reference
selectors: 21 match by exact name (the `mapped` set above), 16 are
implemented under a renamed, underscore-prefixed private selector, 2 are
build-generated accessors with no source counterpart, and 1
(`+[PPCBurgundy probe:]`) is genuinely absent from the source under any
name -- and, per the Invariant check above, does not correspond to a real
function body in the reference binary either (address 0x0), so its absence
from source has no runtime consequence that this analysis can observe.
The reimplementation also adds one selector, `-[PPCBurgundy
updateSampleRate:]` (`BurgundySound.m:646`), that the reference binary does
not have at all -- extra public API surface introduced during the
reimplementation.

21 (exact) + 16 (renamed) + 3 (missing) = 40 reference selectors.
21 (exact) + 16 (renamed) + 1 (extra) = 38 our definitions. Both totals
reconcile with the header counts above.

## Bundle stub

`drvPPCBurgundy` (the non-relocatable bundle, profile `burgundy-bundle-ppc`)
analysis has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this
small bundle wrapper is a loader shim with no Objective-C methods and no
driver logic of its own, so it carries no correspondence findings against
`PPCBurgundy`. No source map or bucket table was built for it (the source
map and bucket script in this task both target `drvPPCBurgundy_reloc`, the
statically linked kernel server that actually contains the driver's compiled
code).

## Reimplementation note

`drvPPCBurgundy`'s source at
`src/drivers-ppc/sound/drvPPCBurgundy/PPCBurgundy.drvproj/PPCBurgundy.lksproj`
is a RhapsodiOS reimplementation, not Apple's own shipped source -- unlike
Cuda and BMac, whose sources are Apple's originals already sitting in the
kernel tree. This is the first time this source has been measured against
Apple's compiled binary, and the gap here is expected to differ in *kind*
from the other four drivers, not merely in size.

Cuda measured 0 real gaps and BMac measured 1 (both build-generated
accessors, i.e. tooling artifacts outside hand-written code). Burgundy's
headline gap is structural: of the 39 in-scope Objective-C methods, only 21
(54%) match the reference by exact selector name. The other 18 split into
two very different categories:

- 16 (41%) are present with equivalent logic and argument lists, but under a
  systematically renamed selector -- the reimplementation's author added an
  underscore prefix to every private method (`_resetBurgundy`,
  `_startIO:`, etc.) where the reference binary's compiled selectors have no
  such prefix (`resetBurgundy`, `startIO:`). This is a naming-convention
  choice that is invisible at the source level (both read as "private
  helper methods") but is a real, exact-selector-string mismatch at the
  Objective-C runtime level: a message send using the reference's selector
  name would not dispatch to this implementation.
- 2 (5%) are the class-accessor methods DriverKit's build tooling generates
  (`kernelServerInstance`, `driverKitVersionFor...`), the same category of
  gap Cuda and BMac also show and not something hand-written source could
  supply.

Additionally, the reference binary carries one more selector,
`+[PPCBurgundy probe:]`, that does not exist in source under any name --
but per the Invariant check above, this selector does not correspond to a
real function body in the reference binary either (its address resolves to
0x0), so this could not be verified as a functional gap one way or another
from static analysis alone. The reimplementation also adds one selector the
reference lacks entirely (`-[PPCBurgundy updateSampleRate:]`).

No static C helper functions exist anywhere in this source (confirmed by
grep across both `.m` files), so none of the ten non-static C helper
functions resolved into bucket 5 were static-function moves -- consistent
with the task brief's prediction that Burgundy would show few or no
bucket-5 moves from *static* C functions specifically. What the brief did
not predict, and what this measurement surfaces, is the systematic private-
selector rename across the entire `PPCBurgundy(Private)` category -- a
finding specific to a reimplementation, not something that could occur when
measuring Apple's own source against Apple's own binary.
