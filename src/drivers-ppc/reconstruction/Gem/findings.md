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

**These counts are unchanged after the multicast CRC correction** (see The
multicast CRC correction below), and that is expected, not a null result. The
two functions that changed -- `mace_crc` (replaced) and `crc416` (added) --
are plain C functions, not Objective-C methods, so they fall outside the
`--scope-to-objc` scope entirely: the map neither claimed them before the
change nor claims them after. Their evidence lives in the bucket table, where
`_crc416` moves from bucket 6 to bucket 5 for the first time. Re-running
`source-map` after the change reproduces `mapped 48 unmapped 2 dup 0
disputed 0` exactly.

`GemEnet.m` and `GemEnetPrivate.m` (`@implementation GemEnet` and
`@implementation GemEnet(Private)`) together define 49 Objective-C methods
(22 + 27, counted with `grep -c "^[+-]" GemEnet.m GemEnetPrivate.m`, confirmed
a second way by grepping for lines starting `+`/`-` in both files and
counting: 49), two more than the 47 the task description cites. The extra
method is `+[GemEnet probe:]` (`GemEnet.m:118`, declared `GemEnet.h:81`): it
has source but never surfaces as an analysis function -- it is the entry the
invariant checker (Step 3) flags as a symbol at address `0x0`, the same
anomaly Task 2 hit for GNic's `_allocateMemory`. (Per the Invariant check
correction below, `__text+0` does hold a real body IDA's analysis omits, so
this is an unmapped real function, not an empty symbol.) Because the 157 functions
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
**Four of the five now have a source definition and move to bucket 5** -- one
more than when this driver was first measured, because `crc416` did not exist
in this tree then (see The multicast CRC correction below):

- `_WriteGemRegister` -- `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnet.m:76`
  (non-static, `extern`-declared at `GemEnetPrivate.m:70`)
- `_ReadGemRegister` -- `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnet.m:32`
  (non-static, `extern`-declared at `GemEnetPrivate.m:69`)
- `_mace_crc` -- `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnetPrivate.m:173`
  (static). **No longer the name-only match it was when first measured**: the
  body is now transcribed from the verified in-tree source that produced this
  exact compiled code. See The multicast CRC correction below.
- `_crc416` -- `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnetPrivate.m:137`
  (static). **New in bucket 5.** This function had no source site anywhere
  under `src/drivers-ppc/network/drvPPCGem` when this driver was first
  measured; it was a genuine absent function, and it has since been written.

`bucket_functions.py` still lists all four under `6-fn-no-source-site`, and it
always will: bucket 6 is computed against the source map, and the map is built
with `--scope-to-objc`, which calls `scope_analysis()`
(`tools/binrecon/binrecon/cli.py:231`) and drops every plain C function from
the map entirely. The bucket-5 promotion is a by-hand result for all four, as
it has been for every driver measured in this series. The printed table above
is the verbatim tool output, not a corrected one.

Neither `_WriteGemRegister`/`_ReadGemRegister` is one of the static C
functions the task description calls out for this source. Grepping for
lines starting with the word `static` in both `.m` files now finds four
matches: `static inline void enforceInOrderExecutionIO(void)` (`GemEnet.m:27`,
does not survive as a distinct symbol because it is `static inline`, so it
raises no bucket-6 entry), `static GemRegisterDef gemRegisterTable[]`
(`GemEnetPrivate.m:89`, a static array, not a function), and the two CRC
functions `static unsigned int crc416(unsigned int, unsigned short)`
(`GemEnetPrivate.m:137`) and `static unsigned int mace_crc(unsigned short *)`
(`GemEnetPrivate.m:173`). Excluding the data declaration, that is 3 static C
functions, one more than the 2 the task description cited -- the difference is
exactly `crc416`, which did not exist in this tree when that count was taken.

### Leading-underscore naming defect in `_ReadGemRegister` / `_WriteGemRegister`

Recorded here because it is invisible to every automated check in this project
and was found only by reading the source.

`GemEnet.m:32` and `GemEnet.m:76` spell these two functions with an explicit
leading underscore *in the C identifier*:

```c
unsigned int _ReadGemRegister(int base, unsigned int offset_and_size)
void _WriteGemRegister(int base, unsigned int offset_and_size, unsigned int value)
```

The leading underscore on the binary's `_ReadGemRegister` / `_WriteGemRegister`
symbols is the Mach-O C ABI prefix the assembler prepends, not part of the C
identifier. A C identifier already spelled `_ReadGemRegister` therefore emits
the symbol `__ReadGemRegister` -- two underscores -- which is **not** the
symbol Apple's binary carries. To produce the shipped symbols, the source
identifiers would have to be bare `ReadGemRegister` / `WriteGemRegister`.

This is the same trap the CRC transcription had to avoid, and it is why
`crc416` and `mace_crc` are spelled **bare** in `GemEnetPrivate.m` rather than
`_crc416` / `_mace_crc`: source `_crc416` would have emitted `__crc416` and
failed to match Apple's `_crc416`. The pre-existing pair was written the wrong
way; the new pair was not.

**This defect is out of scope for the current work and has not been fixed** --
it is recorded, not repaired. It is also mechanically undetectable here:
`--scope-to-objc` calls `scope_analysis()`
(`tools/binrecon/binrecon/cli.py:231`) and drops plain C functions from the
source map entirely, so neither the map, the bucket table, nor
`selector_check.py` (which only reads Objective-C selectors) would ever flag
it. Nothing in this repository currently checks C symbol spelling against the
reference symbol table.

## The multicast CRC correction

**This is the headline finding for this driver, and the only change in the
whole "absent functions" series with a demonstrated runtime consequence.** It
is recorded here in full: what was wrong, how wrong it was measured to be,
what breaks because of it, and what replaced it.

### What was wrong

`GemEnetPrivate.m` defined a function under the right name, `_mace_crc`, that
implemented **a different algorithm from the one Apple's binary contains**.
Ours was a byte-wise reflected CRC-32 with polynomial `0xEDB88320`, computed
over all six address bytes in one self-contained loop, calling nothing.
Apple's is a `crc416`-based CRC with polynomial `0x04C11DB7`, decomposed into
three 16-bit halfword steps. The two are not equivalent, and the difference
was not cosmetic.

### How it was found

`_mace_crc` needed closer scrutiny than a name match because its 68-byte
compiled body did not look like it could correspond to the byte-wise loop the
source then had. Disassembling it
(`tools/binrecon/out/gem-ppc/published/analysis-reference-ida.json`, address
`0x2984`) shows it loads three 16-bit halfwords from the address argument
and calls an unnamed 16-byte jump-island (address `0x29c8`, bucket 3 --
`lis/ori/mtctr/bctr` loading `_crc416`'s address) three times, then returns --
i.e. the compiled function is a thin wrapper calling `_crc416` on each
16-bit chunk of a MAC address. That did not match the source, which computed
CRC-32 byte-by-byte with polynomial `0xEDB88320` and called nothing.

### Byte-identity against BMac and Mace

To check whether this is boilerplate shared with other drivers of the same
era, the instruction bytes of both functions were compared across all three
binaries' published analyses. **They are byte-for-byte identical in all
three**, re-confirmed independently after the correction was written:

```
gem-ppc    _crc416     100 B  sha256=789fbf4f36550f72edb5e8e1d4b980592270010f0f2bfc4ee02a3dab02aba5c7
gem-ppc    _mace_crc    68 B  sha256=0a99a7fd3d4af3e8bc08e5b20ab4d6b2da1bd51d3a2342912f4973de8737ad64
bmac-ppc   _crc416     100 B  sha256=789fbf4f36550f72edb5e8e1d4b980592270010f0f2bfc4ee02a3dab02aba5c7
bmac-ppc   _mace_crc    68 B  sha256=0a99a7fd3d4af3e8bc08e5b20ab4d6b2da1bd51d3a2342912f4973de8737ad64
mace-ppc   _crc416     100 B  sha256=789fbf4f36550f72edb5e8e1d4b980592270010f0f2bfc4ee02a3dab02aba5c7
mace-ppc   _mace_crc    68 B  sha256=0a99a7fd3d4af3e8bc08e5b20ab4d6b2da1bd51d3a2342912f4973de8737ad64

_crc416:   gem==bmac True   gem==mace True
_mace_crc: gem==bmac True   gem==mace True
```

(SHA-256 over the concatenated instruction bytes of each function, from
`tools/binrecon/out/<profile>/published/analysis-reference-ida.json`. Addresses
differ per binary -- Gem `0x2920`/`0x2984`, BMac `0x4ec0`/`0x4f24`, Mace
`0x371c`/`0x3780` -- the bytes do not.)

Both BMac's and Mace's *sources* are in this tree. **What the earlier specs
established, precisely:** BMac's measurement moved `_crc416`/`_mace_crc` from
bucket 6 to bucket 5 by locating a definition site *by name*, not by comparing
bodies -- so the earlier work established correspondence by name, not by
disassembly. `_mace_crc`'s 68-byte body was disassembled and compared during
this spec (see above); `_crc416`'s 100-byte body was disassembled and checked
against `BMacEnetPrivate.m:1622` during this spec's final review, confirming
the byte swap, the `ENET_CRCPOLY` load, the sign test, the low-bit test, the
XOR and the 16-iteration bound. Both bodies are therefore now verified against
the binary directly, rather than inherited transitively.
`src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetPrivate.m:1622` defines
`crc416(current, nxtval)` as a 16-iteration bit loop with polynomial
`0x04c11db7`, and `:1660` defines `mace_crc` as exactly three calls to
`crc416` on the address's three 16-bit halfwords;
`src/kernel-7/bsd/dev/ppc/drvMaceEnet/MaceEnetPrivate.m:1510` and `:1548`
carry the identical pair. So the reference binary's `_mace_crc`/`_crc416`
implement the shared CRC pair that BMac's and Mace's own sources carry.

### How far apart the two algorithms measured

**The two algorithms are measurably not behavior-equivalent.** Both were
implemented (BMac's `crc416`/`mace_crc` pair,
reading each halfword big-endian -- the correct byte order on PowerPC -- and
this repository's then-current byte-wise reflected-CRC version) and run
against five MAC addresses, including the standard IPv4 and IPv6 multicast
addresses. The raw CRCs differ on all five outright; two index derivations
were checked on top of them, and neither derivation is the top 6 bits, despite
that label below -- see the correction after the table:

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

### The runtime consequence

The consequence is concrete and traceable end to end in this driver's own
source, not merely asserted: `mace_crc` is called at `GemEnetPrivate.m:1099`
(inside `-[GemEnet(Private) _addToHashTableMask:]`) and `:1138` (inside
`-[GemEnet(Private) _removeFromHashTableMask:]`); those two methods are called
from `GemEnet.m:445` and `:463`; and `-[GemEnet(Private)
_updateGemHashTableMask]` writes `hashTableMask[]` into the GMAC hardware hash
registers.

So with the old algorithm this repository's `GemEnet` programmed **the wrong
multicast hash bucket for every address tested**. It would therefore drop
multicast frames the real hardware/driver combination should accept, and
accept frames it should not. This is a real behavioral divergence, not a
naming or bookkeeping mismatch, and it is the only change in this series with
a demonstrated runtime effect.

### What replaced it

Both functions are now transcribed from the verified in-tree source, **not
reconstructed from disassembly**:

| Function | Now at | Transcribed from |
| --- | --- | --- |
| `crc416` | `GemEnetPrivate.m:137` | `BMacEnetPrivate.m:1622` / `MaceEnetPrivate.m:1510` |
| `mace_crc` | `GemEnetPrivate.m:173` | `BMacEnetPrivate.m:1660` / `MaceEnetPrivate.m:1548` |

The old `_mace_crc` was **replaced in place, not renamed or commented out**;
no copy of the byte-wise `0xEDB88320` version remains anywhere in the file.
Both call sites were updated from `(unsigned char *)` to `(unsigned short *)`
to match the transcribed signature. `ENET_CRCPOLY 0x04c11db7` is defined at
`GemEnetPrivate.m:132`, matching `BMacEnetPrivate.m:1608` and
`MaceEnetPrivate.m:1496`.

The only differences from the donor source are stylistic, to match the
surrounding file: `u_int32_t` is spelled `unsigned int` (the spelling
`GemEnetPrivate.m` uses throughout), and `/* ... */` comments are `//`
comments. The control flow, the polynomial, the loop bound, the byte swap and
the three-halfword decomposition are transcribed verbatim.

Both functions are spelled **bare** -- `crc416` and `mace_crc`, not `_crc416`
and `_mace_crc`. The leading underscore in the binary's symbols is the Mach-O
ABI prefix; see the naming section above for why the underscored spelling
would have been wrong.

### What is and is not claimed

**This is not compile-verified. There is no PowerPC toolchain in this
environment, and nothing here was compiled, linked or loaded.**

What *is* claimed, and is stronger than for anything else written in this
series: the transcription source is in-tree source that was already measured
against its own shipped binaries and found to match, and the compiled bytes
those sources produced are byte-identical to the bytes in Gem's binary (table
above). That makes this a transcription from proven-correct source rather than
a reconstruction from disassembly. It is still not a compiled claim.

### The one remaining bucket-6 gap

`__udivdi3` has no match anywhere under `src/drivers-ppc/network/drvPPCGem`.
It is the libgcc 64-bit unsigned-division runtime helper the PPC compiler
emits; it stays in bucket 6 as a real but expected gap -- compiler-generated
code, not driver source, and explicitly out of scope to write.

No caller could be identified from the reference analysis for it; the analysis
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

**This set did not change when the multicast CRC was corrected, and could not
have.** Gem's two changed functions are plain C, so they never entered the
`--scope-to-objc` map in either direction; the unmapped set contains only
Objective-C selectors. Both remaining entries are build-generated, so Gem has
no absent hand-written Objective-C method left to write. Re-running
`selector_check.py` after the change reproduces `reference selectors: 51 / our
definitions: 49`, `missing (2)`, `extra (0)`, exit code 0 -- unchanged.

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
  declared `GemEnet.h:81`), so source exists for it. This is the same anomaly
  the Correspondence section above explains: it is why the source has 49
  methods but the map only reconciles 48.
> **CORRECTION.** The bullet above said the reference binary carries "only a symbol-table
> entry at address 0x0 -- a placeholder/unresolved address". That was wrong, and the same
> misreading was repeated across every driver spec in this series. `__text+0` in
> `drvPPCGem_reloc` holds `7c0802a6` -- `mflr r0` -- and it is IDA's *analysis* that omits
> the function there, not Apple's binary that omits the code. `read_macho` reports address
> `0` for every undefined symbol too (`_IOLog`, `_objc_msgSend`, ...), which is what made a
> defined symbol at `__text+0` look empty.
>
> **`+[GemEnet probe:]` is a real function the analysis does not record, not a phantom.**
> It is an unmapped real function -- a genuine gap, not an artifact of the tooling.
> `GemEnet.m:118`'s correspondence to it is now *unverified* rather than *unnecessary*:
> there is Apple code at `__text+0` and nothing here has compared the two. Nothing was
> re-measured for this correction and no source map was regenerated: the mapped/unmapped
> counts above are unaffected, because IDA never had this function to map. The checker now
> distinguishes the two cases. See
> `src/drivers-ppc/reconstruction/IOADBDevice/findings.md`, "The misreading".

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
