# drvPPCSym8xx reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCSym8xx.config/drvPPCSym8xx` | 8500 | `6459396AF147D3BE11510553034744BB22BAFA647C12F1B3A97CEBA751E917A3` |
| `drvPPCSym8xx.config/drvPPCSym8xx_reloc` | 59128 | `45092B9D7C33E4B9688C215D1806F1B1808670A61A2B6C376660B608B5746514` |

Both sizes were measured and matched by Task 1's `binrecon validate`; re-hashing both files directly
during this task reproduces the same two SHA-256 values exactly, and the source map's own
`reference_sha256` field (`src/drivers-ppc/reconstruction/Sym8xx/source-map.json`) reproduces the
`drvPPCSym8xx_reloc` hash above exactly.

`src/kernel-7/conf/files.ppc` lists all four of this driver's implementation files under
`mk_hasdrivers`:

```
bsd/dev/ppc/drvSymbios8xx/Sym8xxInit.m 		optional mk_hasdrivers
bsd/dev/ppc/drvSymbios8xx/Sym8xxClient.m 		optional mk_hasdrivers
bsd/dev/ppc/drvSymbios8xx/Sym8xxExecute.m 		optional mk_hasdrivers
bsd/dev/ppc/drvSymbios8xx/Sym8xxMisc.m 			optional mk_hasdrivers
```

i.e. the driver's source is compiled into the kernel itself whenever `mk_hasdrivers` is set, the same
pattern already established for `drvPPCMesh`/`drvPPCGem`/`drvPPCCuda`/etc. The shipped artifact measured
here, `drvPPCSym8xx.config/drvPPCSym8xx_reloc`, is nonetheless a separate, statically-linked loadable
kernel server binary shipped as its own `.config` bundle pair for DriverKit-style dynamic loading.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCSym8xx_reloc`, scoped to the Objective-C methods found in that binary:

```
mapped 44 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPCSym8xxKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCSym8xxVersion driverKitVersionFordrvPPCSym8xx]'] 16
```

- Total functions in the reference analysis (`sym8xx-ppc`): 146.
- `read_macho`'s own count of ObjC-method-shaped symbols in the binary is **47** (see Categories below:
  22 Execute + 8 Init + 15 Client + 2 build-generated `(primary)`), one more than the map's 44+2=46. The
  extra one is `-[Sym8xxController(Execute) commandRequestOccurred]` at address `0x0` -- flagged by the
  invariant checker as "not a function start" (see Invariant check below) and, because it never appears
  as a function-start entry in the 146-function reference analysis at all, it cannot appear in the
  source map's `mapped` or `unmapped` lists either (the map's universe is scoped to the reference
  analysis's function set, not to every named symbol in the binary). This is the same address-`0x0`
  boundary anomaly every driver measured so far has shown, except here for the first time the anomalous
  symbol is itself an Objective-C method rather than a plain C function.
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0, for the same reason given above: the one address-`0x0` anomaly in this binary
  is a symbol with no function-start entry in the reference analysis, so it never becomes a
  `mapped`/`unmapped`/`boundary_disputed` candidate in the map at all.

Counting every `+`/`-` method-signature line at column 0 in each of the driver's four implementation
blocks:

```
Sym8xxClient.m:34    @implementation Sym8xxController(Client)    -- 15
Sym8xxExecute.m:36   @implementation Sym8xxController(Execute)   -- 22
Sym8xxInit.m:107     @implementation Sym8xxController(Init)      --  8
Sym8xxMisc.m:29      @implementation Sym8xxController            --  0 (empty; @implementation/@end only)
```

15 + 22 + 8 + 0 = **45** method definitions, one more than the plan's orientation figure of 44 and
matching `selector_check.py`'s "our definitions: 45" exactly (see Selector check below) -- consistent
with every prior task's finding that the plan's counts are approximate.

Of those 45 source methods:

- 44 have an address-matching counterpart the source map places (`mapped`).
- 1 -- `-[Sym8xxController(Execute) commandRequestOccurred]` (`Sym8xxExecute.m:44`) -- has an
  exact-selector match in the binary's symbol table but at address `0x0`, which is not a function start
  in the reference analysis, so it cannot be address-mapped; it is a name match with no analysis-side
  function to map it to, not a genuine gap (see Correspondence above and Invariant check below).
- 0 source methods are missing a same-named binary counterpart, and 0 binary selectors (besides the
  2 build-generated ones) are missing a same-named source counterpart -- this driver has no
  arity/rename mismatches of the kind found in `drvPPCMesh` (`ResetHardware:` vs `ResetHardware:reason:`,
  etc.). See Selector check below.

That leaves the reference binary's own unmapped set at 2 (both build-generated), the number reported by
the source map above.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and the reference analysis
passed to it, so verifying a `--scope-to-objc` map requires scoping the analysis to the same covered
addresses first:

```
analysis functions 146 -> scoped 46
load_source_map OK
```

46 is exactly 44 mapped + 2 unmapped, confirming the map's covered-address set is precisely the
46-entry ObjC scope claimed above (the reference analysis's 146 functions minus the jump islands/
build-generated-class/C-helper functions not in the ObjC scope, and independently of the 47th,
address-`0x0` symbol that isn't a function start at all).

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/sym8xx-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/Sym8xx/source-map.json`:

```
total functions: 146
  mapped: 44
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 96
  4-build-generated-class: 2
      0x3ebc  +[drvPPCSym8xxKernelServerInstance kernelServerInstance]  (20 bytes)
      0x3ed0  +[drvPPCSym8xxVersion driverKitVersionFordrvPPCSym8xx]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 4
      0x3ad8  _Sym8xxGrowSRBPool  (44 bytes)
      0x3d04  _Sym8xxTimerReq  (132 bytes)
      0x3d98  _Sym8xxReadRegs  (128 bytes)
      0x3e28  _Sym8xxWriteRegs  (132 bytes)
counted: 146
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because `drvPPCSym8xx_reloc` is a statically
linked kernel server, not an `MH_EXECUTE` helper: it carries no crt/dyld startup routines and its
analysis has no `__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand against every bucket-6 entry.
This source has **0 static C functions** (per the brief), and all 4 bucket-6 entries confirm that: every
one is a non-static free function declared in `Sym8xxController.h` and defined in a `.m` file, not a
libgcc helper and not a static file-local helper.

- `_Sym8xxGrowSRBPool` -- `Sym8xxClient.m:798`, `IOThreadFunc Sym8xxGrowSRBPool( Sym8xxController
  *controller )` (non-static). 44 bytes, 1 basic block. Source is a 2-statement thread-entry thunk with
  an explicit comment: "We need this entry thunk since the thread creation routines dont support objC
  interfaces directly." (`Sym8xxClient.m:793-796`). Its body is `[controller Sym8xxGrowSRBPool]; return
  NULL;` -- straight-line, no branches, consistent with 1 block. This is a distinct C function from the
  ObjC method `-[Sym8xxController(Client) Sym8xxGrowSRBPool]` of the same name that it calls (mapped,
  address `0x3b14`); the two coexist deliberately (a C-callable trampoline plus the ObjC method it
  invokes). Logic confirmed by structure.
- `_Sym8xxTimerReq` -- `Sym8xxClient.m:853`, `IOThreadFunc Sym8xxTimerReq( Sym8xxController *device )`
  (non-static). 132 bytes, 1 basic block. Source builds a `msg_header_t` on the stack, sets three
  fields, and calls `msg_send_from_kernel` once before returning `NULL` -- straight-line, no branches,
  consistent with 1 block despite the larger size (stack struct initialization). Logic confirmed by
  structure.
- `_Sym8xxReadRegs` -- `Sym8xxMisc.m:36`, `u_int32_t Sym8xxReadRegs( volatile u_int8_t *chipRegs,
  u_int32_t regOffset, u_int32_t regSize )` (non-static). 128 bytes, 8 basic blocks: an `if`/`if-else
  if`/`else` chain over `regSize` (1, 2, 4, default) with a distinct return in each of the 4 arms --
  entry plus 3 comparisons plus 4 leaf blocks is consistent with 8 blocks. Logic confirmed by structure.
- `_Sym8xxWriteRegs` -- `Sym8xxMisc.m:57`, `void Sym8xxWriteRegs( volatile u_int8_t *chipRegs, u_int32_t
  regOffset, u_int32_t regSize, u_int32_t regValue )` (non-static). 132 bytes, 8 basic blocks: the same
  4-arm `if`/`else if`/`else` shape over `regSize`, followed by a shared `eieio()` call -- consistent
  with 8 blocks. Logic confirmed by structure.

All 4 bucket-6 entries therefore belong in bucket 5 (`fn-with-source-site`) by hand; none is a genuine
gap. This differs from `drvPPCMesh`, whose bucket 6 also contained 4 unmapped Objective-C methods with
no exact-selector source match -- this driver's bucket 6 contains only plain C functions, all resolved.

## Unmapped detail

Two reference selectors have no source-mapped implementation, both build-generated:

- `+[drvPPCSym8xxKernelServerInstance kernelServerInstance]` (20 bytes) -- build-generated: a
  KernelServer wrapper class instance accessor emitted by the driver-kit build tooling, not hand-written
  driver code (same pattern as every other `_reloc` kernel server measured so far).
- `+[drvPPCSym8xxVersion driverKitVersionFordrvPPCSym8xx]` (16 bytes) -- build-generated: the DriverKit
  version accessor, likewise tool-emitted.

Both match `selector_check.py`'s entire "missing" list exactly (see Selector check below). There is no
additional real gap in this driver's unmapped set -- unlike `drvPPCMesh`, which had 4 real
arity/selector-mismatch gaps beyond its 2 build-generated entries.

## Invariant check

`ppc_invariant_check.py` output for both binaries, verbatim (`sym8xx-ppc` re-run after the
`_OBJC_METHOD_LIST_SECTIONS` fix described below; `sym8xx-bundle-ppc` unaffected by that fix):

```
=== sym8xx-ppc ===
symbol -[Sym8xxController(Execute) commandRequestOccurred] at 0x0 is not a function start
16 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1129 fused relocations, 1 violations
=== sym8xx-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

The original run of this checker (before the fix below) reported an additional line for `sym8xx-ppc`:

```
__OBJC pointer at 0x6010 points into __TEXT,__text
```

(2 violations total in that run.) This driver was the first measured so far to report a violation type
other than the expected address-`0x0` symbol/function-start anomaly, so it was investigated by hand
rather than taken at face value. The raw relocation record at `0x6010` is:

```
{'address': 24592, 'kind': 'ppc-vanilla-32-absolute', 'target': '__TEXT,__text', 'addend': 8184,
 'section': '__OBJC,__cat_cls_meth', 'section_ordinal': 6, 'target_section_ordinal': 1,
 'original_bytes': '00001FF8', 'scattered': False}
```

It lives in `__OBJC,__cat_cls_meth` -- the method-list section for a category's **class** (`+`) methods
-- and points at address `0x1ff8` (8184), which the binary's own symbol table identifies as
`+[Sym8xxController(Init) probe:]` (`Sym8xxInit.m:113`, `+ (BOOL)probe:(IOPCIDevice *)deviceDescription`)
-- a real function in `__TEXT,__text`. This is exactly the legitimate pattern the checker's own comment
already documents: "Method lists ... carry an IMP field alongside the selector/types pointers, and IMP
addresses code in `__TEXT,__text`". Objective-C emits four distinct method-list sections
(`__cls_meth`, `__inst_meth`, `__cat_inst_meth`, `__cat_cls_meth`) but the checker's allow-list carried
only three of the four -- `__cat_cls_meth` was missing -- because `drvPPCSym8xx` is the first driver
measured in this project to declare a class method inside a category. (`Sym8xxController(Init)` is a
category holding the class-side `probe:` entry point, standard for IOKit drivers since `probe:` must run
before any instance exists; its `__inst_meth` section is even size 0, with every method landing in a
category section instead of the primary class.) **This has been fixed in the tool**
(`ppc_invariant_check.py`, commit `da51d92d`, with a regression test, RED confirmed first), and this
task's re-run of the checker (verbatim above) now shows `sym8xx-ppc` reporting 1 violation instead of 2.
No other relocation-decode issue class (address-form bounds, jbsr islands, HI16/LO16 pairing,
paired-principal counts) reported anything for either binary, before or after the fix.

**The single remaining violation, `-[Sym8xxController(Execute) commandRequestOccurred]` at `0x0`, is the
same anomaly every driver measured so far has shown -- not a relocation violation.** `Sym8xxExecute.m:44`
defines `- (void)commandRequestOccurred`, so source exists for it. Because the 146 reference-analysis
functions never include an entry at `0x0`, it cannot appear in the source map's
`mapped`/`unmapped`/`boundary_disputed` categories at all (see Correspondence above). This is the
`boundary_disputed` pattern, not a relocation-decode defect.
> **CORRECTION.** The paragraph above read `ppc_invariant_check.py`'s "is not a function
> start" message as "there is no code at that address", and called the symbol a placeholder
> with an unresolved address. That was wrong, and the same misreading was repeated across five
> merged specs. `__text+0` in `drvPPCSym8xx_reloc` holds `7c0802a6` -- `mflr r0` -- and it is IDA's
> *analysis* that omits the function there, not Apple's binary that omits the code.
> `read_macho` reports address `0` for every undefined symbol too (`_IOLog`, `_objc_msgSend`,
> ...), which is what made a defined symbol at `__text+0` look empty.
>
> **`-[Sym8xxController(Execute) commandRequestOccurred]` is a real function the analysis does not record, not a phantom.** It is an
> unmapped real function. `Sym8xxExecute.m:44` defines a method of that name, but the correspondence is now
> *unverified* rather than *unnecessary*. Its body is not written here; that is separate work. Nothing was
> re-measured for this correction and no source map was regenerated: the mapped/unmapped
> counts above are unaffected, because IDA never had this function to map. The checker now
> distinguishes the two cases. See
> `src/drivers-ppc/reconstruction/IOADBDevice/findings.md`, "The misreading".


`sym8xx-bundle-ppc`'s `__mh_bundle_header` at address `0x0` is the standard synthetic bundle-header
symbol every Mach-O bundle carries at its load address -- identical to every other `_reloc`/bundle pair
measured in this project.

**Acceptance item 2 (0 relocation violations) is met for this driver.** With the checker fix applied,
`sym8xx-ppc` and `sym8xx-bundle-ppc` both report exactly one item each, and in both cases that item is the
address-`0x0` `boundary_disputed` symbol/function-start pattern, not a relocation violation. Actual
relocation-decode violations: 0 for both binaries.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 47
our definitions:     45

renames (0):

duplicates (0):

missing (2):
    +[drvPPCSym8xxKernelServerInstance kernelServerInstance]
    +[drvPPCSym8xxVersion driverKitVersionFordrvPPCSym8xx]

extra (0):
```

Exit code: 0.

"Reference selectors: 47" matches the `read_macho`-derived category count (22 + 8 + 15 + 2 = 47) above
exactly, including the address-`0x0` `commandRequestOccurred` anomaly, which the selector check counts
by *name* (it has a real selector string) even though it has no function-start address. "Our
definitions: 45" matches the method-definition recount above exactly.

Characterising each entry, class-insensitively as well (grepping `Sym8xx[Cc]ontroller` case-insensitively
across the source directory finds only the single casing `Sym8xxController` everywhere, so the
class-insensitive re-check changes nothing here):

- `+[drvPPCSym8xxKernelServerInstance kernelServerInstance]`, `+[drvPPCSym8xxVersion
  driverKitVersionFordrvPPCSym8xx]` -- both build-generated (see Unmapped detail); no source counterpart
  exists or is expected for either class.
- **`extra (0)`**: every one of the 45 source-defined selectors has an exact-selector match somewhere in
  the reference binary's 47. This includes `-[Sym8xxController(Execute) commandRequestOccurred]`, whose
  selector matches by name even though its binary-side address (`0x0`) excludes it from the source map's
  `mapped` list (see Correspondence/Invariant check above) -- `selector_check.py` matches on selector
  string, not on function-start validity, so it correctly reports 0 extra rather than flagging this as a
  source-only method.
- No renames and no duplicates: this driver, unlike `drvPPCMesh`, has zero arity mismatches
  (`ResetHardware:` vs `ResetHardware:reason:`-style splits) and zero same-named methods across its four
  implementation blocks. The four blocks (`Client`, `Execute`, `Init`, and the empty primary
  `@implementation Sym8xxController` in `Sym8xxMisc.m`) contribute disjoint selector sets.

## Bundle stub

`drvPPCSym8xx` (the non-relocatable bundle, profile `sym8xx-bundle-ppc`) analysis has exactly 2
functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this small bundle wrapper is a
loader shim with no Objective-C methods and no driver logic of its own, so it carries no correspondence
findings against `Sym8xxController`. No source map or bucket table was built for it (the source map and
bucket script in this task both target `drvPPCSym8xx_reloc`, the statically linked kernel server that
actually contains the driver's compiled code), matching the pattern established for every other bundle
pair measured in this project.

## Categories

Step 5's map-derived per-category count comes back entirely under `(primary)`, exactly as the brief
predicted (IDA's export strips Objective-C category tags):

```
mapped 44 unmapped 2 dup 0 disputed 0
```

The real split was obtained by reading the binary's own symbol table directly with
`binrecon.macho.read_macho` (bypassing the IDA export) and matching the category-tag regex against every
Objective-C-shaped symbol name:

```
{'Execute': 22, 'Init': 8, 'Client': 15, '(primary)': 2}
```

Total: 22 + 8 + 15 + 2 = 47, one more than the source map's 44 mapped + 2 unmapped = 46 -- the
difference being `-[Sym8xxController(Execute) commandRequestOccurred]` at address `0x0` (see
Correspondence/Invariant check above), which `read_macho` still lists as a named Execute-category symbol
even though it never enters the map's `mapped`/`unmapped` universe.

To attribute each of the map's 44 `mapped` addresses to a real category, each mapped entry's address was
looked up a second time directly against `read_macho`'s symbol table (which retains the category tag),
joining on address rather than on name:

```
mapped by real category: {'Execute': 21, 'Init': 8, 'Client': 15}
unmapped by category: {'(primary)': 2}
```

21 + 8 + 15 = 44, matching `mapped` exactly, and the 2 unmapped entries are both `(primary)`
(build-generated classes, not `Sym8xxController` itself). Combining this with the excluded
`commandRequestOccurred` entry accounts for the full 47-selector split:

| Category | Mapped | Unmapped | Excluded (0x0 anomaly) | Total (this class) |
| --- | --- | --- | --- | --- |
| `Client` | 15 | 0 | 0 | 15 |
| `Execute` | 21 | 0 | 1 (`commandRequestOccurred`) | 22 |
| `Init` | 8 | 0 | 0 | 8 |
| **`Sym8xxController` subtotal** | **44** | **0** | **1** | **45** |
| build-generated (`drvPPCSym8xxKernelServerInstance`, `drvPPCSym8xxVersion`) | 0 | 2 | 0 | 2 |
| **Grand total** | **44** | **2** | **1** | **47** |

This reconciles exactly against both the `read_macho`-derived category counts above (22 Execute + 8 Init
+ 15 Client + 2 build-generated `(primary)` = 47) and the source map's `mapped 44 unmapped 2` headline
(44 + 2 = 46, plus the 1 excluded anomaly = 47). Unlike `drvPPCMesh` (the most category-fragmented driver
measured so far, with unmapped/extra selectors spread across most of its six categories), every one of
`Sym8xxController`'s three real categories (`Client`, `Init`) has a perfect 1:1 match to its full named
selector count, and `Execute`'s only shortfall is the single address-`0x0` anomaly rather than a genuine
selector mismatch -- the cleanest correspondence result of any driver measured in this project so far.
