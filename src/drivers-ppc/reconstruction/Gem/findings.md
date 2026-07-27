# drvPPCGem reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCGem.config/drvPPCGem` | 8492 | `20EBB21BB1D2CA3AB28E7F266809BC87A156C745E6A6A2F0E7C0A7DE477DA318` |
| `drvPPCGem.config/drvPPCGem_reloc` | 58072 | `D1836DDC7B8B4A8BC8C035B586E6036D054CAAC78380AC6DFB79E7760D644A70` |

Both re-verified locally with `sha256sum` and `ls -la` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`. Both match.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCGem_reloc`, scoped to the Objective-C methods found in that binary:

```
mapped 48 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPCGemKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCGemVersion driverKitVersionFordrvPPCGem]'] 16
```

- Total functions in the reference analysis: 157.
- Named Objective-C methods, in scope: 50 -- 48 mapped + 2 unmapped.
- Out of scope: 107, composed of 102 unnamed jump islands (bucket 3) plus 5
  named, non-Objective-C symbols the `--scope-to-objc` map deliberately does
  not claim (bucket 6, see Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0 (from the source-map builder's own semantics; see
  Invariant check below for the one symbol/function-start mismatch the
  invariant checker separately flags).

`GemEnet.m` and `GemEnetPrivate.m` (`@implementation GemEnet` and
`@implementation GemEnet(Private)`) together define 49 Objective-C methods
(22 + 27, counted with `grep -c "^[+-]" GemEnet.m GemEnetPrivate.m`, confirmed
a second way by grepping for lines starting `+`/`-` in both files and
counting: 49), two more than the 47 the task description cites. The extra
method is `+[GemEnet probe:]` (`GemEnet.m:118`, declared `GemEnet.h:81`): it
has source but never surfaces as an analysis function -- it is the entry the
invariant checker (Step 3) flags as a symbol at address `0x0`, the same
anomaly Task 2 hit for GNic's `_allocateMemory`. Because the 157 functions
IDA reported never include an entry at `0x0`, `probe:` cannot appear as
"mapped" or "unmapped" in the source map. That leaves 48 methods with a
genuine reference-function counterpart to map, matching `mapped 48` above
exactly (49 total methods - 1 at address 0x0 = 48).

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and
the reference analysis passed to it, so verifying a `--scope-to-objc` map
requires scoping the analysis to the same covered addresses first: the map
does not claim the 102 unnamed jump islands or the 5 non-Objective-C symbols,
and the bucket reconciliation below accounts for those 107 separately.

```
analysis functions 157 -> scoped 50
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/gem-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/Gem/source-map.json`:

```
total functions: 157
  mapped: 48
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 102
  4-build-generated-class: 2
      0x2c18  +[drvPPCGemKernelServerInstance kernelServerInstance]  (20 bytes)
      0x2c2c  +[drvPPCGemVersion driverKitVersionFordrvPPCGem]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 5
      0xcf0  _WriteGemRegister  (128 bytes)
      0xd70  _ReadGemRegister  (132 bytes)
      0x2920  _crc416  (100 bytes)
      0x2984  _mace_crc  (68 bytes)
      0x2c3c  __udivdi3  (1616 bytes)
counted: 157
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`drvPPCGem_reloc` is a statically linked kernel server, not an `MH_EXECUTE`
helper: it carries no crt/dyld startup routines and its analysis has no
`__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand
against every bucket-6 entry
(`grep -n <symbol> src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj`).
Three of the five have a straightforward source definition and move to
bucket 5:

- `_WriteGemRegister` -- `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnet.m:76`
  (non-static, `extern`-declared at `GemEnetPrivate.m:70`)
- `_ReadGemRegister` -- `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnet.m:32`
  (non-static, `extern`-declared at `GemEnetPrivate.m:69`)
- `_mace_crc` -- `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnetPrivate.m:135`
  (static; **name-only match, not a confirmed correspondence** -- the source
  site exists, satisfying the bucket-5 criterion, but the compiled function
  implements measurably different, non-equivalent logic; see the headline
  finding below)

Neither `_WriteGemRegister`/`_ReadGemRegister` is one of the "2 static C
functions" the task description calls out for this source. Grepping for
lines starting with the word `static` in both `.m` files finds three
matches: `static inline void enforceInOrderExecutionIO(void)` (`GemEnet.m:27`,
does not survive as a distinct symbol because it is `static inline`, so it
raises no bucket-6 entry), `static GemRegisterDef gemRegisterTable[]`
(`GemEnetPrivate.m:89`, a static array, not a function), and
`static unsigned int _mace_crc(unsigned char *address)`
(`GemEnetPrivate.m:135`). Excluding the data declaration, that is exactly
the 2 static C functions the task description cites.

`_mace_crc` needed closer scrutiny than a name match because its 68-byte
compiled body did not look like it could correspond to the byte-wise loop in
`GemEnetPrivate.m:135`. Disassembling it
(`tools/binrecon/out/gem-ppc/published/analysis-reference-ida.json`, address
`0x2984`) shows it loads three 16-bit halfwords from the address argument
and calls an unnamed 16-byte jump-island (address `0x29c8`, bucket 3 --
`lis/ori/mtctr/bctr` loading `_crc416`'s address) three times, then returns --
i.e. the compiled function is a thin wrapper calling `_crc416` on each
16-bit chunk of a MAC address. That does not match the source at
`GemEnetPrivate.m:135`, which computes CRC-32 byte-by-byte with polynomial
`0xEDB88320` and calls nothing. To check whether this is boilerplate shared
with another driver of the same era, I ran `binrecon analyze` against
`drvPPCBMac_reloc` (profile `bmac-ppc`, already defined in
`tools/binrecon/profiles/`) and compared raw instruction bytes: BMac's
`_crc416` (`0x4ec0`, 100 bytes) and `_mace_crc` (`0x4f24`, 68 bytes) are
byte-for-byte identical to Gem's `_crc416` (`0x2920`, 100 bytes) and
`_mace_crc` (`0x2984`, 68 bytes). `src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetPrivate.m:1622`
defines BMac's `crc416(current, nxtval)` as a 16-iteration bit loop with
polynomial `0x04c11db7`, and `BMacEnetPrivate.m:1660` defines its `mace_crc`
as exactly three calls to `crc416` on the address's three 16-bit halfwords --
this matches Gem's compiled `_mace_crc`/`_crc416` instruction-for-instruction.
So the reference binary's `_mace_crc`/`_crc416` implement the same
shared/boilerplate CRC-32 pair BMac's original source carries, not the
different reflected-CRC algorithm that this repository's
`GemEnetPrivate.m:135` currently implements under the same function name.

**Headline finding: the two algorithms are measurably not
behavior-equivalent.** I implemented both (BMac's `crc416`/`mace_crc` pair,
reading each halfword big-endian -- the correct byte order on PowerPC -- and
this repository's byte-wise reflected-CRC version) and ran both against five
MAC addresses, including the standard IPv4 and IPv6 multicast addresses. The
raw CRCs differ on all five outright; two index derivations were checked on
top of them, and neither derivation is the top 6 bits, despite that label
below -- see the correction after the table:

```
01:00:5E:00:00:01  apple=0x7FA32D9B (hash 31)  ours=0xD9B4C5FE (hash 54)  DIFFER
33:33:00:00:00:01  apple=0xF99BAABA (hash 62)  ours=0x5D55D99F (hash 23)  DIFFER
FF:FF:FF:FF:FF:FF  apple=0xFF48647D (hash 63)  ours=0xBE2612FF (hash 47)  DIFFER
00:00:00:00:00:00  apple=0x3A7ABC72 (hash 14)  ours=0x4E3D5E5C (hash 19)  DIFFER
01:23:45:67:89:AB  apple=0xA72FE892 (hash 41)  ours=0x4917F4E5 (hash 18)  DIFFER

identical on 0/5 vectors
```

**Correction: neither driver uses the top 6 bits as its hash-table index.**
Apple's Mace and BMac compute `mace_crc(...) & 0x3f` (the low 6 bits) and then
look the result up in a `reverse6[]` bit-reversal table
(`MaceEnetPrivate.m:1499`/`:1568`-`:1569`). Gem uses the low 8 bits of its own
CRC, bit-reversed and then inverted, in `-[GemEnet(Private)
_addToHashTableMask:]` (`GemEnetPrivate.m:1062`-`1084`). The `(hash N)` values
above are the raw top-6-bit slice for illustration only, not either driver's
actual index.

**The divergence holds under Apple's real index derivation, not just the
illustrative one.** Re-running the same five vectors through `crc & 0x3f` then
`reverse6[]` -- the index Mace and BMac's own source actually computes --
still gives 0/5 agreement:

```
01:00:5E:00:00:01  apple idx=54  ours idx=31  DIFFER
33:33:00:00:00:01  apple idx=23  ours idx=62  DIFFER
FF:FF:FF:FF:FF:FF  apple idx=47  ours idx=63  DIFFER
00:00:00:00:00:00  apple idx=19  ours idx=14  DIFFER
01:23:45:67:89:AB  apple idx=18  ours idx=41  DIFFER

reverse6[crc & 0x3f] identical on 0/5 vectors
```

So the divergence is not an artifact of which index derivation is used for
the comparison: raw CRC, illustrative top-6-bit slice and Mace/BMac's real
`& 0x3f` + `reverse6[]` derivation all show 0/5 agreement.

Zero of five vectors agree, including both standard multicast addresses.
The runtime consequence is concrete, and traceable end to end in this
driver's own source, not just asserted: `_mace_crc` is called at
`GemEnetPrivate.m:1071` (inside `-[GemEnet(Private) _addToHashTableMask:]`)
and `:1110` (inside `-[GemEnet(Private) _removeFromHashTableMask:]`); those
two methods are called from `GemEnet.m:445` and `:463`; and
`-[GemEnet(Private) _updateGemHashTableMask]`
(`GemEnetPrivate.m:1049`-`1053`) writes `hashTableMask[]` into the GMAC
hardware hash registers. So this repository's `GemEnet` would program the
wrong multicast hash bucket for every address tested, so it would drop
multicast frames the real hardware/driver combination should accept, and
accept frames it should not -- a real behavioral divergence, not just a
naming/bookkeeping mismatch. `_mace_crc` stays in bucket 5 because a
source site genuinely exists (the bucket taxonomy is about source-site
existence, not logic equivalence), but a later reader must not count it as
a confirmed match: it is a name-only correspondence with divergent, tested,
non-equivalent logic.

The remaining two entries are real gaps:

- `_crc416` has no match anywhere under
  `src/drivers-ppc/network/drvPPCGem`. Given the byte-identical match with
  BMac's `crc416` above, it is very likely the same shared driver-era CRC
  helper Apple's original Gem driver carried, simply not present in this
  repository's `GemEnetPrivate.m` reconstruction (which reimplements
  multicast-hash filtering with a different, tested-non-equivalent
  algorithm -- see the headline finding above). This absence is internally
  consistent: this repository's version computes CRC-32 byte-by-byte over
  the whole address in one self-contained loop and never decomposes the
  computation into per-16-bit-halfword steps, so it has no reason to carry
  a `crc416`-shaped helper at all. It stays in bucket 6 as a real gap
  relative to this repository's current source tree.
- `__udivdi3` has no match anywhere under `src/drivers-ppc/network/drvPPCGem`
  either. It is the libgcc 64-bit unsigned-division runtime helper the PPC
  compiler emits; it stays in bucket 6 as a real, expected gap -- it is
  compiler-generated code, not driver source.

No caller could be identified from the reference analysis for either gap; it
carries no call-graph edges for this binary (`calls: []` on every function
entry checked).

## Unmapped detail

Two reference selectors have no source-mapped implementation, both
build-generated:

- `+[drvPPCGemKernelServerInstance kernelServerInstance]` (20 bytes) --
  a KernelServer wrapper class instance accessor emitted by the driver-kit
  build tooling, not hand-written driver code.
- `+[drvPPCGemVersion driverKitVersionFordrvPPCGem]` (16 bytes) --
  the DriverKit version accessor, likewise tool-emitted.

Both match the `selector_check.py` "missing" list below exactly.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== gem-ppc ===
symbol +[GemEnet probe:] at 0x0 is not a function start
6 scattered/difference-form relocations (target section verified, field is a difference, not an address)
3 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1165 fused relocations, 1 violations
=== gem-bundle-ppc ===
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

- `gem-ppc`: `+[GemEnet probe:]` at address `0x0` is a symbol in
  `__TEXT,__text` that is not one of IDA's recognized function starts.
  `GemEnet.m:118` defines this method (`+ (BOOL)probe:(IODeviceDescription *)devDesc`,
  declared `GemEnet.h:81`), so source exists for it, but the reference
  binary carries only a symbol-table entry at address 0x0 -- a
  placeholder/unresolved address, not a genuine boundary dispute affecting
  any mapped function. This is the same anomaly the Correspondence section
  above explains: it is why the source has 49 methods but the map only
  reconciles 48.
- `gem-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the standard
  synthetic bundle-header symbol Mach-O bundles carry at their load address;
  not a real function, so not a function start either.

Neither candidate overlaps any function reported in the bucket table or the
source map, so neither affects the 48/2/0/0 correspondence numbers above.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 51
our definitions:     49

renames (0):

duplicates (0):

missing (2):
    +[drvPPCGemKernelServerInstance kernelServerInstance]
    +[drvPPCGemVersion driverKitVersionFordrvPPCGem]

extra (0):
```

Exit code: 0. The "missing" two match the source map's unmapped set exactly,
both build-generated (see Unmapped detail). "Reference selectors: 51"
includes the 48 mapped, the 2 missing/build-generated, and `+[GemEnet
probe:]` (the symbol-table-only entry from Invariant check) -- 48 + 2 + 1 =
51. "Our definitions: 49" is the 49 method signatures actually present in
`GemEnet.m`/`GemEnetPrivate.m` (48 mapped plus `probe:`). There is no "extra"
list to characterise -- the count is 0, so `drvPPCGem`'s selector table has
zero surplus definitions relative to the reference binary's selector table,
and a class-insensitive re-check is moot since nothing is flagged as extra
to begin with.

## Bundle stub

`drvPPCGem` (the non-relocatable bundle, profile `gem-bundle-ppc`) analysis
has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this
small bundle wrapper is a loader shim with no Objective-C methods and no
driver logic of its own, so it carries no correspondence findings against
`GemEnet`. No source map or bucket table was built for it (the source map
and bucket script in this task both target `drvPPCGem_reloc`, the statically
linked kernel server that actually contains the driver's compiled code).
