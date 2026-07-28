# drvPPCMace reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCMace.config/drvPPCMace` | 8496 | `E8F6692C4FDF6EC94FF0BBA8A8C0363DDDDCF179AB31574F0BBAE142540E3B17` |
| `drvPPCMace.config/drvPPCMace_reloc` | 60744 | `3D8C168B0A3F2485D6F9B43D8C1290E0A46974F45A715C2778DA97C3A4BBC87C` |

Both re-verified locally with `sha256sum` and `ls -la` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`. Both match.

Unlike GNic and Gem, which are already loadable-driver projects, `drvMaceEnet`'s
source builds into the kernel itself: `src/kernel-7/conf/files.ppc:109-111` lists
`MaceEnet.m`, `MaceEnetPrivate.m`, and `MaceEnetHW.m` as `optional mk_hasdrivers`.
The shipped artifact measured here, `drvPPCMace.config/drvPPCMace_reloc`, is
nonetheless a loadable kernel-server binary (same relocatable-object shape as
GNic's and Gem's `_reloc` artifacts) -- the packaging model (source built
directly into the kernel image via a config option) and the shipped-binary
packaging (a separate loadable driver bundle) do not match. That mismatch is
itself a packaging finding: the reference binary was evidently built as a
loadable driver from the same source that, in this repository's kernel
config, is instead wired to build in-tree.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCMace_reloc`, scoped to the Objective-C methods found in that binary:

```
mapped 47 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPCMaceKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCMaceVersion driverKitVersionFordrvPPCMace]'] 16
```

- Total functions in the reference analysis: 183.
- Named Objective-C methods, in scope: 49 -- 47 mapped + 2 unmapped.
- Out of scope: 134, composed of 128 unnamed jump islands (bucket 3) plus 6
  named, non-Objective-C symbols the `--scope-to-objc` map deliberately does
  not claim (bucket 6, see Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0 (from the source-map builder's own semantics; see
  Invariant check below for the one symbol/function-start mismatch the
  invariant checker separately flags).

`MaceEnet.m` (`@implementation MaceEnet`) and `MaceEnetPrivate.m`
(`@implementation MaceEnet(Private)`) together define 48 Objective-C methods
(23 + 25, counted with `grep -c "^[+-]" MaceEnet.m MaceEnetPrivate.m`, confirmed
a second way by listing every `^[+-]` line in both files and counting: 48),
two more than the 46 the task description cites -- the same pattern Task 2
(GNic, 48 vs. 46 cited) and Task 3 (Gem, 49 vs. 47 cited) hit. The extra
method relative to the map is `+[MaceEnet probe:]` (`MaceEnet.m:45`, declared
`MaceEnet.h`): it has source but never surfaces as an analysis function -- it
is the entry the invariant checker (Step 3) flags as a symbol at address
`0x0`, the same anomaly Task 2 hit for GNic's `_allocateMemory` and Task 3 hit
for Gem's `probe:`. (Per the Invariant check correction below, `__text+0` does
hold a real body IDA's analysis omits, so this is an unmapped real function,
not an empty symbol.) Because the 183 functions IDA reported never include an
entry at `0x0`, `probe:` cannot appear as "mapped" or "unmapped" in the source
map. That leaves 47 methods with a genuine reference-function counterpart to
map, matching `mapped 47` above exactly (48 total methods - 1 at address 0x0 =
47).

`MaceEnetHW.m` defines the two C register-access helpers (`WriteMaceRegister`,
`ReadMaceRegister`) but has no `@implementation` block and contributes no
Objective-C methods.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and
the reference analysis passed to it, so verifying a `--scope-to-objc` map
requires scoping the analysis to the same covered addresses first: the map
does not claim the 128 unnamed jump islands or the 6 non-Objective-C symbols,
and the bucket reconciliation below accounts for those 134 separately.

```
analysis functions 183 -> scoped 49
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/mace-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/Mace/source-map.json`:

```
total functions: 183
  mapped: 47
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 128
  4-build-generated-class: 2
      0x39bc  +[drvPPCMaceKernelServerInstance kernelServerInstance]  (20 bytes)
      0x39d0  +[drvPPCMaceVersion driverKitVersionFordrvPPCMace]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 6
      0xde4  _WriteMaceRegister  (20 bytes)
      0xdf8  _ReadMaceRegister  (16 bytes)
      0xe08  _reverseBitOrder  (56 bytes)
      0x371c  _crc416  (100 bytes)
      0x3780  _mace_crc  (68 bytes)
      0x39e0  __udivdi3  (1616 bytes)
counted: 183
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`drvPPCMace_reloc` is a statically linked kernel server, not an `MH_EXECUTE`
helper: it carries no crt/dyld startup routines and its analysis has no
`__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand
against every bucket-6 entry
(`grep -n <symbol> src/kernel-7/bsd/dev/ppc/drvMaceEnet/`). All six entries
resolve:

- `_WriteMaceRegister` -- `src/kernel-7/bsd/dev/ppc/drvMaceEnet/MaceEnetHW.m:39`
  (non-static, `extern`-declared at `MaceEnetPrivate.h:40`). Source:
  `*((u_int8_t *)ioEnetBase + reg_offset) = data; eieio();` -- a single store
  plus enforced in-order I/O barrier, consistent with a 20-byte compiled
  body.
- `_ReadMaceRegister` -- `src/kernel-7/bsd/dev/ppc/drvMaceEnet/MaceEnetHW.m:46`
  (non-static, `extern`-declared at `MaceEnetPrivate.h:41`). Source:
  `return ((u_int8_t *)ioEnetBase)[reg_offset];` -- a single load, consistent
  with a 16-byte compiled body.
- `_reverseBitOrder` -- `src/kernel-7/bsd/dev/ppc/drvMaceEnet/MaceEnetPrivate.m:51`
  (static). Disassembled (`0xe08`, 56 bytes): mask the input byte
  (`clrlwi r9, r3, 24`), then an 8-iteration loop that shifts an accumulator
  left, ORs in the low bit of the source byte, shifts the source right, and
  compares the iteration count against 7 (`cmpwi cr1, r11, 7` / `ble- cr1`) --
  instruction-for-instruction the same shape as the source's
  `for (i=0; i<8; i++) { val <<= 1; if (data & 1) val |= 1; data >>= 1; }`
  8-iteration bit-reversal loop. Confirmed logic match, not just a name
  match.
- `_crc416` -- `src/kernel-7/bsd/dev/ppc/drvMaceEnet/MaceEnetPrivate.m:1510`
  (static). See the CRC finding below: confirmed logic match.
- `_mace_crc` -- `src/kernel-7/bsd/dev/ppc/drvMaceEnet/MaceEnetPrivate.m:1548`
  (static). See the CRC finding below: confirmed logic match.
- `__udivdi3` -- no match anywhere under `src/kernel-7/bsd/dev/ppc/drvMaceEnet`.
  It is the libgcc 64-bit unsigned-division runtime helper the PPC compiler
  emits; it stays in bucket 6 as a real, expected gap -- compiler-generated
  code, not driver source. No caller could be identified from the reference
  analysis (`calls: []` on every function entry checked).

Grepping for lines starting with the word `static` in the driver's three
`.m` files finds exactly three static function definitions --
`static u_int8_t reverseBitOrder(u_int8_t data)` (`MaceEnetPrivate.m:51`),
`static u_int32_t crc416(unsigned int current, unsigned short nxtval)`
(`MaceEnetPrivate.m:1510`), and `static u_int32_t mace_crc(unsigned short
*address)` (`MaceEnetPrivate.m:1548`) -- plus a handful of `static
IODBDMADescriptor` variable declarations and a `static int reverse6[]` lookup
table, which are data, not functions. That matches the task description's
"3 static C functions" for this driver exactly.

### CRC finding: `_mace_crc` / `_crc416` match, unlike Gem's

Following the brief's specific concern -- Gem's binary carried BMac's
`_crc416`/`_mace_crc` pair byte-for-byte while Gem's own source implemented a
different, non-equivalent reflected-CRC algorithm under the same names -- I
ran the same byte-comparison against Mace, BMac, and Gem's compiled
functions:

```
_crc416 {'mace': 100, 'bmac': 100, 'gem': 100} mace==bmac: True
_mace_crc {'mace': 68, 'bmac': 68, 'gem': 68} mace==bmac: True
```

Mace's compiled `_crc416` (`0x371c`, 100 bytes) and `_mace_crc` (`0x3780`, 68
bytes) are byte-for-byte identical to BMac's `crc416` (100 bytes) and
`mace_crc` (68 bytes) -- and, by transitivity with Task 3's finding, also
byte-for-byte identical to Gem's compiled `_crc416`/`_mace_crc`.

Unlike Gem, **this driver's own source matches**. `MaceEnetPrivate.m:1510`
defines `static u_int32_t crc416(unsigned int current, unsigned short
nxtval)` as the same 16-iteration bit loop with polynomial `0x04c11db7`,
byte-swapping `nxtval` first, that BMac's `BMacEnetPrivate.m:1622` carries;
`MaceEnetPrivate.m:1548` defines `mace_crc(unsigned short *address)` as
exactly three calls to `crc416` on the address's three 16-bit halfwords
(`0xffffffff` seed, then chained), matching BMac's `mace_crc` structure at
`BMacEnetPrivate.m:1660` and the compiled instruction sequence
instruction-for-instruction. This is expected and unsurprising: unlike Gem
(a from-scratch reimplementation under this project), `drvMaceEnet` is
Apple's own shipped source carried through from Darwin, and BMac and Mace
share the same MACE-chip-derived CRC helper by design -- both `crc416` and
`mace_crc` are named after the MACE chip. No behavioral divergence was found
here; this driver's `_addToHashTableMask`/`_removeFromHashTableMask`
(`MaceEnetPrivate.m:1563`, `:1583`) call `mace_crc` exactly the way the
compiled binary does.

## Unmapped detail

Two reference selectors have no source-mapped implementation, both
build-generated:

- `+[drvPPCMaceKernelServerInstance kernelServerInstance]` (20 bytes) --
  a KernelServer wrapper class instance accessor emitted by the driver-kit
  build tooling, not hand-written driver code.
- `+[drvPPCMaceVersion driverKitVersionFordrvPPCMace]` (16 bytes) --
  the DriverKit version accessor, likewise tool-emitted.

Both match the `selector_check.py` "missing" list below exactly.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== mace-ppc ===
symbol +[MaceEnet probe:] at 0x0 is not a function start
6 scattered/difference-form relocations (target section verified, field is a difference, not an address)
3 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1249 fused relocations, 1 violations
=== mace-bundle-ppc ===
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

- `mace-ppc`: `+[MaceEnet probe:]` at address `0x0` is a symbol in
  `__TEXT,__text` that is not one of IDA's recognized function starts.
  `MaceEnet.m:45` defines this method (`+ (BOOL)probe:(IODeviceDescription *)devDesc`),
  so source exists for it. This is the same anomaly the Correspondence
  section above explains: it is why the source has 48 methods but the map
  only reconciles 47.
> **CORRECTION.** The bullet above said the reference binary carries "only a symbol-table
> entry at address 0x0 -- a placeholder/unresolved address". That was wrong, and the same
> misreading was repeated across every driver spec in this series. `__text+0` in
> `drvPPCMace_reloc` holds `7c0802a6` -- `mflr r0` -- and it is IDA's *analysis* that omits
> the function there, not Apple's binary that omits the code. `read_macho` reports address
> `0` for every undefined symbol too (`_IOLog`, `_objc_msgSend`, ...), which is what made a
> defined symbol at `__text+0` look empty.
>
> **`+[MaceEnet probe:]` is a real function the analysis does not record, not a phantom.**
> It is an unmapped real function -- a genuine gap, not an artifact of the tooling.
> `MaceEnet.m:45`'s correspondence to it is now *unverified* rather than *unnecessary*:
> there is Apple code at `__text+0` and nothing here has compared the two. Nothing was
> re-measured for this correction and no source map was regenerated: the mapped/unmapped
> counts above are unaffected, because IDA never had this function to map. The checker now
> distinguishes the two cases. See
> `src/drivers-ppc/reconstruction/IOADBDevice/findings.md`, "The misreading".

- `mace-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the standard
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
    +[drvPPCMaceKernelServerInstance kernelServerInstance]
    +[drvPPCMaceVersion driverKitVersionFordrvPPCMace]

extra (0):
```

Exit code: 0. The "missing" two match the source map's unmapped set exactly,
both build-generated (see Unmapped detail). "Reference selectors: 50"
includes the 47 mapped, the 2 missing/build-generated, and `+[MaceEnet
probe:]` (the symbol-table-only entry from Invariant check) -- 47 + 2 + 1 =
50. "Our definitions: 48" is the 48 method signatures actually present in
`MaceEnet.m`/`MaceEnetPrivate.m` (47 mapped plus `probe:`). There is no
"extra" list to characterise -- the count is 0, so `drvPPCMace`'s selector
table has zero surplus definitions relative to the reference binary's
selector table, and a class-insensitive re-check is moot since nothing is
flagged as extra to begin with.

## Bundle stub

`drvPPCMace` (the non-relocatable bundle, profile `mace-bundle-ppc`) analysis
has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this
small bundle wrapper is a loader shim with no Objective-C methods and no
driver logic of its own, so it carries no correspondence findings against
`MaceEnet`. No source map or bucket table was built for it (the source map
and bucket script in this task both target `drvPPCMace_reloc`, the statically
linked kernel server that actually contains the driver's compiled code).
