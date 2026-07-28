# drvPPCOHare reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCOHare.config/drvPPCOHare` | 8496 | `15DCEA39494EEC4EA61DA1E62154D0731B95B3E8762A5A4BC60A465A5219A93F` |
| `drvPPCOHare.config/drvPPCOHare_reloc` | 16568 | `56FD92D69B400F8BAB5B4453BAAAF8B4E009C615DF27B026D9B31E8E826C794A` |

Both sizes were measured and matched by Task 1's `binrecon validate`; re-hashing both files directly
during this task (`sha256sum`) reproduces the same two SHA-256 values exactly, and the source map's own
`reference_sha256` field (`src/drivers-ppc/reconstruction/OHare/source-map.json`) reproduces the
`drvPPCOHare_reloc` hash above exactly.

`src/kernel-7/conf/files.ppc` lists this driver's single implementation file under `mk_hasdrivers`:

```
bsd/dev/ppc/drvOHare/ohare.m		optional mk_hasdrivers
```

i.e. the driver's source is compiled into the kernel itself whenever `mk_hasdrivers` is set, the same
pattern already established for `drvPPCMesh`/`drvPPCGem`/`drvPPCCuda`/`drvPPCSym8xx`/etc. The shipped
artifact measured here, `drvPPCOHare.config/drvPPCOHare_reloc`, is nonetheless a separate,
statically-linked loadable kernel server binary shipped as its own `.config` bundle pair for
DriverKit-style dynamic loading.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against `drvPPCOHare_reloc`,
scoped to the Objective-C methods found in that binary:

```
mapped 1 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPCOHareKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCOHareVersion driverKitVersionFordrvPPCOHare]'] 16
  MAPPED: ['-[AppleOHare initFromDeviceDescription:]'] (address 0x5c / 92, size 332 bytes)
```

- Total functions in the reference analysis (`ohare-ppc`): 7 -- 1 mapped + 2 build-generated (bucket 4)
  + 4 unnamed jump islands (bucket 3; addresses `0x4c`, `0x1a8`, `0x1b8`, `0x1c8`, all size 16, all
  `names: None`).
- `read_macho`'s own symbol table for `drvPPCOHare_reloc` lists 17 entries total, of which the
  Objective-C-method-shaped ones are exactly the two `AppleOHare` methods
  (`+[AppleOHare probe:]` at address `0`, `-[AppleOHare initFromDeviceDescription:]` at address `92`)
  plus the 2 build-generated class accessors -- 4 ObjC-shaped symbols altogether, one more than the map's
  1 mapped + 2 unmapped = 3. The extra one is `+[AppleOHare probe:]` itself, whose symbol-table `address`
  is `0` -- exactly the same address-`0x0` boundary anomaly every driver measured so far has shown
  (see Invariant check below), and confirmed directly against the reference analysis's 7-entry function
  list: no entry at address `0` exists there, so `probe:` never becomes a function-start candidate and
  therefore cannot appear in the source map's `mapped`/`unmapped`/`boundary_disputed` lists.
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0, for the same reason: the one address-`0x0` anomaly (`probe:`) has no
  function-start entry in the reference analysis at all, so it never becomes a
  `mapped`/`unmapped`/`boundary_disputed` candidate in the map.

Counting every `+`/`-` method-signature line at column 0 in `ohare.m`:

```
ohare.m:35   + (BOOL)probe:(IOPCIDevice *)deviceDescription
ohare.m:45   - initFromDeviceDescription:(IOPCIDevice *)deviceDescription
```

**2 method definitions** -- the plan's brief hedged that `ohare.m` "appears to define only
`+[AppleOHare probe:]`," implying a possible one-method gap for `initFromDeviceDescription:`. Reading the
file directly (`ohare.m:33-81`) shows the `@implementation AppleOHare` block in fact defines **both**
methods declared in `ohare.h` (`ohare.h:35-36`); there is no missing-source-method gap here. This matches
the plan-wide finding restated in every prior task's brief: "the plan's source method counts are
approximate." `selector_check.py`'s "our definitions: 2" (see Selector check below) independently
confirms the count of 2.

Of those 2 source methods:

- 1 (`-[AppleOHare initFromDeviceDescription:]`) has an address-matching counterpart the source map
  places (`mapped`).
- 1 (`+[AppleOHare probe:]`, `ohare.m:35`) has an exact-selector match in the binary's symbol table but
  at address `0x0`, which is not a function start in the reference analysis, so it cannot be
  address-mapped; it is a name match with no analysis-side function to map it to, not a genuine gap (see
  Invariant check below) -- the same `commandRequestOccurred` pattern found in `drvPPCSym8xx`.
- 0 source methods are missing a same-named binary counterpart, and 0 binary selectors (besides the 2
  build-generated ones) are missing a same-named source counterpart -- see Selector check below.

This is, as the plan's driver description anticipated, **the smallest driver in the series**: 1 mapped
method plus 1 name-only, address-`0x0` method is the entirety of `AppleOHare`'s hand-written surface.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and the reference analysis
passed to it, so verifying a `--scope-to-objc` map requires scoping the analysis to the same covered
addresses first:

```
analysis functions 7 -> scoped 3
load_source_map OK
```

3 is exactly 1 mapped + 2 unmapped, confirming the map's covered-address set is precisely the 3-entry
ObjC scope claimed above (the reference analysis's 7 functions minus the 4 unnamed jump islands not in
the ObjC scope, and independently of the 4th, address-`0x0` `probe:` symbol that isn't a function start
at all).

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/ohare-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/OHare/source-map.json`:

```
total functions: 7
  mapped: 1
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 4
  4-build-generated-class: 2
      0x1d8  +[drvPPCOHareKernelServerInstance kernelServerInstance]  (20 bytes)
      0x1ec  +[drvPPCOHareVersion driverKitVersionFordrvPPCOHare]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 0
counted: 7
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because `drvPPCOHare_reloc` is a statically
linked kernel server, not an `MH_EXECUTE` helper: it carries no crt/dyld startup routines and its
analysis has no `__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand against every bucket-6 entry.
**Bucket 6 is empty (0 entries)** for this driver -- there is nothing to resolve by hand. This is the
smallest bucket-6 result of any driver measured so far in this project, consistent with `AppleOHare`
being the smallest driver in the series: every one of its non-build-generated, non-jump-island functions
either mapped directly (`initFromDeviceDescription:`) or fell outside the reference analysis's
function-start set entirely (`probe:`, at `__text+0`).

**This is not the same as "zero real gaps", and an earlier reading of it said so wrongly.** The bucket
table enumerates IDA's 7 functions, and IDA has no function for `+[AppleOHare probe:]` -- real code at
`__text+0`. It is therefore outside every bucket, not accounted for by one. `drvPPCOHare` has **one
real unmapped function**, not zero. See the Invariant check correction below.

## Unmapped detail

Two reference selectors have no source-mapped implementation, both build-generated:

- `+[drvPPCOHareKernelServerInstance kernelServerInstance]` (20 bytes) -- build-generated: a
  KernelServer wrapper class instance accessor emitted by the driver-kit build tooling, not hand-written
  driver code (same pattern as every other `_reloc` kernel server measured so far).
- `+[drvPPCOHareVersion driverKitVersionFordrvPPCOHare]` (16 bytes) -- build-generated: the DriverKit
  version accessor, likewise tool-emitted.

Both match `selector_check.py`'s entire "missing" list exactly (see Selector check below). There is no
additional real gap in this driver's unmapped set.

## Invariant check

`ppc_invariant_check.py` output for both binaries, verbatim:

```
=== ohare-ppc ===
symbol +[AppleOHare probe:] at 0x0 is not a function start
2 scattered/difference-form relocations (target section verified, field is a difference, not an address)
1 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
98 fused relocations, 1 violations
=== ohare-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

Both runs exit with code 1 (the checker's own exit status reflects "1 violations" printed for each), and
in both cases the single reported item is the address-`0x0` symbol/function-start anomaly, not a genuine
relocation-decode defect -- the same pattern every driver measured so far in this project has shown
(`drvPPCSym8xx`'s `commandRequestOccurred`, `drvPPCMesh`, etc.). No scattered/difference-form relocation,
HI16/HA16-LO16 pairing, or fused-relocation count reported any additional problem for either binary.

- `ohare-ppc`'s anomalous symbol is `+[AppleOHare probe:]` at `0x0` -- confirmed above (Correspondence)
  to be a real, hand-written method (`ohare.m:35`) whose binary symbol-table entry simply carries no
  resolved function-start address in the reference analysis. This is a `boundary_disputed` candidate per
  the plan's established pattern, not a gap: source exists for it (`ohare.m:35-42`), and its selector
  matches exactly in the binary (see Selector check below).
> **CORRECTION.** The paragraph above read `ppc_invariant_check.py`'s "is not a function
> start" message as "there is no code at that address", and called the symbol a placeholder
> with an unresolved address. That was wrong, and the same misreading was repeated across five
> merged specs. `__text+0` in `drvPPCOHare_reloc` holds `7c0802a6` -- `mflr r0` -- and it is IDA's
> *analysis* that omits the function there, not Apple's binary that omits the code.
> `read_macho` reports address `0` for every undefined symbol too (`_IOLog`, `_objc_msgSend`,
> ...), which is what made a defined symbol at `__text+0` look empty.
>
> **`+[AppleOHare probe:]` is a real function the analysis does not record, not a phantom.** It is an
> unmapped real function. `ohare.m:35-42` defines a `probe:` whose selector matches, but that correspondence is
> now *unverified* rather than *unnecessary*: there is Apple code at `__text+0` and
> nothing here has compared the two. Its body is not written here; that is separate work. Nothing was
> re-measured for this correction and no source map was regenerated: the mapped/unmapped
> counts above are unaffected, because IDA never had this function to map. The checker now
> distinguishes the two cases. See
> `src/drivers-ppc/reconstruction/IOADBDevice/findings.md`, "The misreading".

- `ohare-bundle-ppc`'s anomalous symbol, `__mh_bundle_header`, is the standard synthetic bundle-header
  symbol every Mach-O bundle carries at its load address -- identical to every other `_reloc`/bundle pair
  measured in this project.

**Actual relocation-decode violations: 0 for both binaries.** The "1 violations" line each run prints is
the address-`0x0` symbol/function-start anomaly described above, consistent with the plan's stated
expectation ("Expect 0 relocation violations").

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 4
our definitions:     2

renames (0):

duplicates (0):

missing (2):
    +[drvPPCOHareKernelServerInstance kernelServerInstance]
    +[drvPPCOHareVersion driverKitVersionFordrvPPCOHare]

extra (0):
```

Exit code: 0.

"Reference selectors: 4" is the 2 hand-written `AppleOHare` methods (`probe:`,
`initFromDeviceDescription:`) plus the 2 build-generated accessors -- matching the `read_macho`-derived
count in Correspondence above exactly (4 ObjC-shaped symbols total, including the address-`0x0`
`probe:` anomaly, which the selector check counts by *name* even though it has no function-start
address). "Our definitions: 2" matches the method-definition recount in Correspondence exactly.

Characterising each entry, class-insensitively as well (grepping `AppleOHare|drvPPCOHare` case-
insensitively across `src/kernel-7/bsd/dev/ppc/drvOHare` finds only the exact casings already listed
here -- no additional class-name collision):

- `+[drvPPCOHareKernelServerInstance kernelServerInstance]`, `+[drvPPCOHareVersion
  driverKitVersionFordrvPPCOHare]` -- both build-generated (see Unmapped detail); no source counterpart
  exists or is expected for either class.
- **`extra (0)`**: both of the 2 source-defined selectors have an exact-selector match somewhere in the
  reference binary's 4. This includes `+[AppleOHare probe:]`, whose selector matches by name even though
  its binary-side address (`0x0`) excludes it from the source map's `mapped` list (see
  Correspondence/Invariant check above) -- `selector_check.py` matches on selector string, not on
  function-start validity, so it correctly reports 0 extra rather than flagging this as a source-only
  method.
- No renames and no duplicates: `AppleOHare` has a single `@implementation` block with exactly 2
  distinct selectors, so there is no possibility of an arity mismatch or a same-named method colliding
  across categories (this driver has no categories at all, unlike `drvPPCSym8xx`/`drvPPCMesh`).

## Bundle stub

`drvPPCOHare` (the non-relocatable bundle, profile `ohare-bundle-ppc`) analysis has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this small bundle wrapper is a
loader shim with no Objective-C methods and no driver logic of its own, so it carries no correspondence
findings against `AppleOHare`. No source map or bucket table was built for it (the source map and bucket
script in this task both target `drvPPCOHare_reloc`, the statically linked kernel server that actually
contains the driver's compiled code), matching the pattern established for every other bundle pair
measured in this project.
