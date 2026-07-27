# drvPPCDec21040 reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCDec21040.config/drvPPCDec21040` | 8504 | `106826E0950C50F8E0853CC584B403E05B5F7C8145F0BFDC5BDECFC128A1850B` |
| `drvPPCDec21040.config/drvPPCDec21040_reloc` | 51872 | `CA1B142E20E0A26C6D702D2EF3562880AAAB2EF11D15198FB739B37967DCDCEB` |

Both re-verified locally with `sha256sum` and `ls -la` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`. Both match.

This driver's source (`src/kernel-7/bsd/dev/ppc/drvDECchip21040`) builds into
the kernel via `src/kernel-7/conf/files.ppc:118-121`, all four `.m` files
gated `optional mk_hasdrivers` -- statically linked into the kernel server,
the same build pattern as GNic, Gem and Mace.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`drvPPCDec21040_reloc`, scoped to the Objective-C methods found in that binary:

```
mapped 48 unmapped 2 dup 0 disputed 0
mapped per class: {'DECchip21041': 3, 'DECchip2104x': 41, 'DECchip21040': 4}
  unmapped: ['+[drvPPCDec21040KernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCDec21040Version driverKitVersionFordrvPPCDec21040]'] 16
```

- Total functions in the reference analysis: 161.
- Named Objective-C methods, in scope: 50 -- 48 mapped + 2 unmapped.
- Out of scope: 111, composed of 109 unnamed jump islands (bucket 3) plus 2
  named, non-Objective-C symbols the `--scope-to-objc` map deliberately does
  not claim (bucket 6, see Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0 (from the source-map builder's own semantics; see
  Invariant check below for the one symbol/function-start mismatch the
  invariant checker separately flags).

`grep -n "^[+-]" DECchip21040.m DECchip21041.m DECchip2104x.m
DECchip2104xPrivate.m` finds **51** method definitions total (4 + 4 + 26 +
17), four more than the 47 the task description cites. Of those 51, two are
guarded by `#ifdef DEBUG` in `DECchip2104xPrivate.m` (`_dumpRegisters` at
line 223, `_dumpDescriptor:` at line 237) and `#define DEBUG` is commented
out at `DECchip2104xPrivate.m:64`, so neither compiles into the shipped
binary -- confirmed by `selector_check.py`'s "extra" list below and by their
absence from the full Objective-C symbol dump of the reference binary. That
leaves 49 method definitions that do compile.

Of those 49, one -- `-[DECchip21041 initFromDeviceDescription:]`
(`DECchip21041.m:52`) -- exists in the binary only as a symbol-table entry
at address `0x0`, not a recognized function start (Step 3's invariant
check flags this; see Invariant check below). Because the reference
analysis's 161 functions never include an entry at `0x0`, this method
cannot appear as "mapped" or "unmapped" in the address-keyed source map, the
same anomaly Task 2 (GNic's `_allocateMemory`), Task 3 (Gem's `probe:`) and
Task 4 (Mace) each hit once. That leaves 48 methods with a genuine
reference-function counterpart to map, matching `mapped 48` above exactly
(49 compilable methods - 1 at address 0x0 = 48).

The per-class mapped counts reconcile exactly against the source files:
- `DECchip21040.m` defines 4 methods, all 4 mapped (`DECchip21040: 4`).
- `DECchip21041.m` defines 4 methods; 3 mapped (`DECchip21041: 3`) because
  `initFromDeviceDescription:` is the address-`0x0` anomaly above.
- `DECchip2104x.m` (26 methods, `@implementation DECchip2104x`) plus
  `DECchip2104xPrivate.m`'s 15 compilable methods (17 minus the 2
  DEBUG-guarded ones, `@implementation DECchip2104x (Private)`) sum to 41
  mapped (`DECchip2104x: 41`) -- the regex used for the per-class count
  collapses the `(Private)` category tag into its base class name, so both
  categories land under the single `DECchip2104x` key.

4 + 3 + 41 = 48, matching the map's total exactly.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and
the reference analysis passed to it, so verifying a `--scope-to-objc` map
requires scoping the analysis to the same covered addresses first: the map
does not claim the 109 unnamed jump islands or the 2 non-Objective-C
symbols, and the bucket reconciliation below accounts for those 111
separately.

```
analysis functions 161 -> scoped 50
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/dec21040-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/Dec21040/source-map.json`:

```
total functions: 161
  mapped: 48
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 109
  4-build-generated-class: 2
      0x33ec  +[drvPPCDec21040KernelServerInstance kernelServerInstance]  (20 bytes)
      0x3400  +[drvPPCDec21040Version driverKitVersionFordrvPPCDec21040]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 2
      0xa64  _reverseBitOrder  (56 bytes)
      0xa9c  _IOUpdateDescriptorFromNetBuf  (284 bytes)
counted: 161
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`drvPPCDec21040_reloc` is a statically linked kernel server, not an
`MH_EXECUTE` helper: it carries no crt/dyld startup routines and its
analysis has no `__picsymbol_stub` section for the stub-range check to
match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand
against every bucket-6 entry. Both of the two entries have a source site and
move to bucket 5, each confirmed by comparing decompiled logic against the
source, not just the name:

- `_reverseBitOrder` -- `src/kernel-7/bsd/dev/ppc/drvDECchip21040/DECchip21041.m:281`
  (static, forward-declared `DECchip21041.m:44`). Disassembly at `0xa64` is
  an 8-iteration loop: `clrlwi r9,r3,24` masks the argument to a byte, then
  each iteration left-shifts an accumulator (`clrlslwi r3,r3,25,1`), ORs in
  the low bit of the remaining value (`andi. r0,r9,1` / `ori r3,r3,1`),
  right-shifts the remaining value (`srwi r9,r9,1`), and loops 8 times
  (`cmpwi cr1,r11,7` / `ble- loc_A74`) -- this is exactly the C source's
  `for (i=0;i<8;i++){ val<<=1; if (data&1) val|=1; data>>=1; }` bit-reversal
  loop, instruction-for-instruction. Confirmed match, not just a name match.
- `_IOUpdateDescriptorFromNetBuf` -- `src/kernel-7/bsd/dev/ppc/drvDECchip21040/DECchip2104xPrivate.m:97`
  (static). Disassembly at `0xa9c` (284 bytes) branches on the `isReceive`
  argument (`cmpwi cr1,r5,0` / `bne`) to pick a fixed length constant versus
  a call returning the netbuf's own size, calls a function matching
  `nb_map`'s role, computes two bitfield-packed byte counts via `insrwi`
  (matching the source's `control.reg.byteCountBuffer1`/`byteCountBuffer2`
  bitfield struct), calls a physical-address-translation helper twice
  (matching the two `IOPhysicalFromVirtual` calls), and in between contains
  a page-boundary comparison later followed by a `round_page`-style
  recomputation of both byte counts -- structurally matching the source's
  "assume contiguous, then correct if the buffer crosses a page boundary"
  logic in shape and call count. Confirmed match, not just a name match.

Grepping for lines starting with the word `static` in all four `.m` files
finds exactly 4 matches: `reverseBitOrder` (`DECchip21041.m:281`, forward
declaration at line 44), `IOBreak` (`DECchip2104xPrivate.m:69`), `printDesc`
(`DECchip2104xPrivate.m:75`), and `IOUpdateDescriptorFromNetBuf`
(`DECchip2104xPrivate.m:97`) -- exactly the "4 static C functions" the task
description cites. `IOBreak` and `printDesc` are both guarded by the same
`#ifdef DEBUG` block (`DECchip2104xPrivate.m:68-87`) that is inactive
(`#define DEBUG` commented out at line 64), so neither compiles into the
shipped binary and neither raises a bucket-6 entry; only the two
unconditional static functions above do.

No caller could be identified from the reference analysis for either
bucket-5 entry from IDA's own call-graph data; both are called only from
inside the driver's own Objective-C methods, consistent with the source.

## Unmapped detail

Two reference selectors have no source-mapped implementation, both
build-generated:

- `+[drvPPCDec21040KernelServerInstance kernelServerInstance]` (20 bytes) --
  a KernelServer wrapper class instance accessor emitted by the driver-kit
  build tooling, not hand-written driver code.
- `+[drvPPCDec21040Version driverKitVersionFordrvPPCDec21040]` (16 bytes) --
  the DriverKit version accessor, likewise tool-emitted.

Both match the `selector_check.py` "missing" list below exactly.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== dec21040-ppc ===
symbol -[DECchip21041 initFromDeviceDescription:] at 0x0 is not a function start
12 scattered/difference-form relocations (target section verified, field is a difference, not an address)
6 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1233 fused relocations, 1 violations
=== dec21040-bundle-ppc ===
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

- `dec21040-ppc`: `-[DECchip21041 initFromDeviceDescription:]` at address
  `0x0` is a symbol in `__TEXT,__text` that is not one of IDA's recognized
  function starts. `DECchip21041.m:52` defines this method
  (`- initFromDeviceDescription:(IODeviceDescription *)devDesc`), so source
  exists for it, but the reference binary carries only a symbol-table entry
  at address 0x0 -- a placeholder/unresolved address, not a genuine
  boundary dispute affecting any mapped function. This is the same anomaly
  the Correspondence section above explains: it is why the source has 49
  compilable methods but the map only reconciles 48.
- `dec21040-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the
  standard synthetic bundle-header symbol Mach-O bundles carry at their
  load address; not a real function, so not a function start either.

Neither candidate overlaps any function reported in the bucket table or the
source map, so neither affects the 48/2/0/0 correspondence numbers above.

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 51
our definitions:     51

renames (0):

duplicates (0):

missing (2):
    +[drvPPCDec21040KernelServerInstance kernelServerInstance]
    +[drvPPCDec21040Version driverKitVersionFordrvPPCDec21040]

extra (2):
    -[DECchip2104x(Private) _dumpDescriptor:]
    -[DECchip2104x(Private) _dumpRegisters]
```

Exit code: 0. The "missing" two match the source map's unmapped set exactly,
both build-generated (see Unmapped detail).

The "extra" two, `-[DECchip2104x(Private) _dumpDescriptor:]` and
`-[DECchip2104x(Private) _dumpRegisters]`, are the same `#ifdef DEBUG`-guarded
methods described in Correspondence above (`DECchip2104xPrivate.m:223,237`);
the source-selector parser counts them regardless of the inactive `#ifdef`,
but they never reach the compiled binary. A full class-insensitive dump of
every Objective-C symbol in the reference binary (via `read_macho`, 51
entries total, listed in `## Three classes` below) confirms neither
`_dumpRegisters` nor `_dumpDescriptor:` exists anywhere in the binary under
any class or category -- this is a preprocessor-exclusion gap, not a
placement difference onto a sibling class (the pattern the previous spec
found in `drvPPCATA`). Re-checking the two "missing" entries
class-insensitively against the same 51-entry dump likewise finds no trace
of either selector under any class name -- both are genuinely absent from
source, not misplaced.

## Bundle stub

`drvPPCDec21040` (the non-relocatable bundle, profile `dec21040-bundle-ppc`)
analysis has exactly 2 functions:

```
3844 ['dyld_stub_binding_helper'] 48
3892 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this
small bundle wrapper is a loader shim with no Objective-C methods and no
driver logic of its own, so it carries no correspondence findings against
`DECchip21040`/`DECchip21041`/`DECchip2104x`. No source map or bucket table
was built for it (the source map and bucket script in this task both target
`drvPPCDec21040_reloc`, the statically linked kernel server that actually
contains the driver's compiled code).

## Three classes

Per-class split of the 48 mapped entries (Step 5, `source-map.json`):

| Class | Mapped | Source file |
| --- | --- | --- |
| `DECchip21040` | 4 | `DECchip21040.m` (4/4 methods mapped) |
| `DECchip21041` | 3 | `DECchip21041.m` (3/4 methods mapped; `initFromDeviceDescription:` is the address-`0x0` anomaly, see Invariant check) |
| `DECchip2104x` (incl. `(Private)` category) | 41 | `DECchip2104x.m` (26 methods) + `DECchip2104xPrivate.m` (15 of 17 compilable methods; 2 DEBUG-guarded methods excluded) |

4 + 3 + 41 = 48, reconciling exactly with `mapped 48`. The per-class regex
used in Step 5 (`^[-+]\[([A-Za-z0-9_]+)`) stops at the first non-word
character, so it collapses `DECchip2104x` and `DECchip2104x(Private)` into
the single `DECchip2104x` key -- the map itself still distinguishes the two
via the full `reference_names` string (e.g.
`-[DECchip2104x(Private) _allocateMemory]` vs.
`-[DECchip2104x initFromDeviceDescription:]`).

Full Objective-C symbol dump of `drvPPCDec21040_reloc` via `read_macho`
(51 entries, category tags preserved -- IDA's exported analysis strips
them), used to settle every bucket-6/selector ambiguity above:

```
      0 -[DECchip21041 initFromDeviceDescription:]
   1028 -[DECchip21041 getStationAddress:]
   1896 -[DECchip21041 _setInterface:]
   2184 -[DECchip21041 selectInterface]
   3064 -[DECchip2104x(Private) _allocateMemory]
   3600 -[DECchip2104x(Private) _initTxRing]
   3940 -[DECchip2104x(Private) _initRxRing]
   4276 -[DECchip2104x(Private) _initChip]
   4420 -[DECchip2104x(Private) _resetChip]
   4540 -[DECchip2104x(Private) _startTransmit]
   4580 -[DECchip2104x(Private) _startReceive]
   4620 -[DECchip2104x(Private) _initRegisters]
   4932 -[DECchip2104x(Private) _transmitPacket:]
   5412 -[DECchip2104x(Private) receivePacket:length:timeout:]
   5800 -[DECchip2104x(Private) sendPacket:length:]
   6492 -[DECchip2104x(Private) _receiveInterruptOccurred]
   7228 -[DECchip2104x(Private) _transmitInterruptOccurred]
   7636 -[DECchip2104x(Private) _loadSetupFilter:]
   7996 -[DECchip2104x(Private) _setAddressFiltering:]
   8528 -[DECchip21040 initFromDeviceDescription:]
   9192 -[DECchip21040 getStationAddress:]
   9340 -[DECchip21040 _setInterface:]
   9664 -[DECchip21040 selectInterface]
   9924 +[DECchip2104x probe:]
  10228 -[DECchip2104x initFromDeviceDescription:]
  10452 -[DECchip2104x free]
  10712 -[DECchip2104x enableAdapterInterrupts]
  10744 -[DECchip2104x disableAdapterInterrupts]
  10776 -[DECchip2104x resetAndEnable:]
  11120 -[DECchip2104x interruptOccurred]
  11388 -[DECchip2104x serviceTransmitQueue]
  11556 -[DECchip2104x transmit:]
  11868 -[DECchip2104x transmitQueueSize]
  11884 -[DECchip2104x transmitQueueCount]
  11944 -[DECchip2104x pendingTransmitCount]
  12028 -[DECchip2104x timeoutOccurred]
  12172 -[DECchip2104x allocateNetbuf]
  12356 -[DECchip2104x enablePromiscuousMode]
  12476 -[DECchip2104x disablePromiscuousMode]
  12592 -[DECchip2104x enableMulticastMode]
  12616 -[DECchip2104x disableMulticastMode]
  12800 -[DECchip2104x addMulticastAddress:]
  12972 -[DECchip2104x removeMulticastAddress:]
  13136 -[DECchip2104x getPowerState:]
  13152 -[DECchip2104x setPowerState:]
  13236 -[DECchip2104x getPowerManagement:]
  13252 -[DECchip2104x setPowerManagement:]
  13268 -[DECchip2104x getStationAddress:]
  13280 -[DECchip2104x selectInterface]
  13292 +[drvPPCDec21040KernelServerInstance kernelServerInstance]
  13312 +[drvPPCDec21040Version driverKitVersionFordrvPPCDec21040]
```

**Cross-class selector observation:** `getStationAddress:` and
`selectInterface` are each defined on all three classes
(`DECchip21040`, `DECchip21041`, and `DECchip2104x`), and
`initFromDeviceDescription:` and `_setInterface:` are each defined on both
`DECchip21040` and `DECchip21041` (`DECchip2104x` additionally defines its
own `initFromDeviceDescription:` at `0x2824`/10228). These are ordinary
Objective-C method overrides across a class hierarchy (`DECchip21040` and
`DECchip21041` both subclass `DECchip2104x`, each providing its own
chip-specific implementation of the same selector), not naming collisions:
`source-map`'s `duplicate_candidates` count is 0 because the map keys on
the full `Class selector` reference name, and each class's implementation
is a distinct symbol at a distinct address with its own distinct source
site. No selector was found placed on an unexpected sibling class relative
to where its source defines it -- the `drvPPCATA`-style placement
difference does not recur here; every selector's binary class tag matches
the `@implementation` block its source site is defined under.

This driver's source builds into the kernel via `src/kernel-7/conf/files.ppc:118-121`
(`bsd/dev/ppc/drvDECchip21040/{DECchip21040,DECchip21041,DECchip2104x,DECchip2104xPrivate}.m`,
all `optional mk_hasdrivers`) -- the statically linked kernel-server pattern
common to all four network drivers in this measurement batch.
