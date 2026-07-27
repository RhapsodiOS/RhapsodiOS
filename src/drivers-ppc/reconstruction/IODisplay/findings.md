# IODisplay reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `IODisplay.config/IODisplay` | 8492 | `50FFD4F02A9C1807D1135799D3C8A8F5BF03799BD6EE934CDF05C53D85FB83E7` |
| `IODisplay.config/IODisplay_reloc` | 32640 | `FD38FBA638BE85555D342D5349EABDE764F8562084DECEB1A3D33FDAC166B3F1` |

Both re-verified locally with `sha256sum` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`. Both match.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`IODisplay_reloc`, scoped to the Objective-C methods found in that binary
(25 of the 64 total functions IDA reported):

```
mapped 18 unmapped 7 dup 0 disputed 0
  unmapped: ['+[IOSmartDisplay probe:]'] 60
  unmapped: ['-[IOSmartADBDisplay findADBDisplayInfoForType:]'] 324
  unmapped: ['-[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]'] 44
  unmapped: ['-[IOSmartADBDisplay IOSMADBGetLogicalRegister:size:result:size:]'] 104
  unmapped: ['-[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]'] 68
  unmapped: ['+[IODisplayKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[IODisplayVersion driverKitVersionForIODisplay]'] 16
```

Reading the binary's own symbol table directly with `read_macho` (not just
IDA's export) gives a per-class census of 26 ObjC symbols: `IOSmartDisplay`
8, `IOSmartDDCDisplay` 2, `IOSmartADBDisplay` 14, plus the 2 build-generated
wrapper classes -- one more than the 25 that appear in IDA's own function
list, because `-[IOSmartDisplay registerLoudly]` is a symbol-table entry at
address `0x0` that is not a recognized IDA function start (see Invariant
check below; this is the standard pattern already seen for `+probe:` in
Cuda/BMac/Burgundy/OHare/Awacs, not the address-0x0-is-a-real-function
anomaly `IOApplePCIBus` (Task 5) showed).

- Total functions in the reference analysis: 64.
- Named Objective-C methods, in scope: 25 -- 18 mapped + 7 unmapped.
- Out of scope: 39, composed of 37 unnamed jump islands (bucket 3) plus 2
  named, non-Objective-C C helper functions the `--scope-to-objc` map
  deliberately does not claim (part of bucket 6, see Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0.

Unlike Awacs and Burgundy, none of the 7 unmapped entries here are
underscore-prefix renames -- `selector_check.py` (see below) confirms 0
renames for this driver. Five of the seven are genuinely absent from
source under any name (see Unmapped detail and Buckets), and two are the
usual build-generated accessors.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses
and the reference analysis passed to it, so verifying a `--scope-to-objc`
map requires scoping the analysis to the same covered addresses first: the
map does not claim the 37 unnamed jump islands or the 2 non-Objective-C C
helper functions, and the bucket reconciliation below accounts for those 39
separately.

```
analysis functions 64 -> scoped 25
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/iodisplay-ppc/published/analysis-reference-ida.json`
and `src/drivers-ppc/reconstruction/IODisplay/source-map.json`:

```
total functions: 64
  mapped: 18
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 37
  4-build-generated-class: 2
      0x1340  +[IODisplayKernelServerInstance kernelServerInstance]  (20 bytes)
      0x1354  +[IODisplayVersion driverKitVersionForIODisplay]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 7
      0x10  +[IOSmartDisplay probe:]  (60 bytes)
      0x314  _UnpackString  (232 bytes)
      0x754  -[IOSmartADBDisplay findADBDisplayInfoForType:]  (324 bytes)
      0xa48  _SMADBHandler  (68 bytes)
      0x1248  -[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]  (44 bytes)
      0x1274  -[IOSmartADBDisplay IOSMADBGetLogicalRegister:size:result:size:]  (104 bytes)
      0x12ec  -[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]  (68 bytes)
counted: 64
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`IODisplay_reloc` is a statically linked kernel server, not an
`MH_EXECUTE` helper: it carries no crt/dyld startup routines and its
analysis has no `__picsymbol_stub` section for the stub-range check to
match against.

**Bucket 6, resolved one at a time against `src/driverkit-3/libDriver/ppc`
(the whole directory grepped, case-sensitively, for each exact symbol; the
directory's only display-related file is `IOSmartDisplay.m`, 626 lines,
holding `@implementation` blocks for `IOSmartDisplay` (line 108),
`IOSmartDDCDisplay` (line 173), and `IOSmartADBDisplay` (line 380)):**

- `_SMADBHandler` (68 bytes) -- **confirmed source site**, `IOSmartDisplay.m:430`
  (`void SMADBHandler( int number, unsigned char *buffer, int count, void *
  ssp)`). Exact name match modulo the standard C-symbol leading underscore
  (not an ObjC selector rename -- this is a plain C function, registered as
  an ADB callback at `IOSmartDisplay.m:533`). Moves to bucket 5.
- `+[IOSmartDisplay probe:]` (60 bytes) -- grepped for `probe:` across the
  whole directory: **no definition found anywhere.** `IOSmartDisplay`'s
  `@implementation` block (`IOSmartDisplay.m:108`-`171`) defines
  `findForConnection:refCon:`, `attach:refCon:`, `detach`, `attached`,
  `getDisplayInfoForMode:flags:`, and `getGammaTableByIndex:...`, but no
  `probe:`. **Genuinely absent from source under any name.**
- `-[IOSmartADBDisplay findADBDisplayInfoForType:]` (324 bytes) -- grepped
  for `findADBDisplayInfoForType` across the whole directory: **no
  definition found anywhere**, not even a declaration. **Genuinely absent.**
- `-[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]` (44 bytes) -- grepped
  for `IOSMADBGetAVDeviceID`: **no match anywhere.** **Genuinely absent.**
- `-[IOSmartADBDisplay IOSMADBGetLogicalRegister:size:result:size:]`
  (104 bytes) -- grepped for `IOSMADBGetLogicalRegister`: **no match
  anywhere** (note this is distinct from the *compiled* `-[IOSmartADBDisplay
  getLogicalRegister:data:]`, which *is* present and mapped at
  `IOSmartDisplay.m:486` -- the `IOSMADBGet...` family with the `size:`
  argument list is a different, unimplemented entry point). **Genuinely
  absent.**
- `-[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]` (68 bytes) --
  same situation as the previous entry, distinct from the present
  `setLogicalRegister:data:` (`IOSmartDisplay.m:463`). **Genuinely absent.**
- `_UnpackString` (232 bytes) -- grepped case-insensitively for `unpack`
  across the whole directory: the only hits are `UnpackFullSection`,
  `UnpackPartialSection`, and `PEF_UnpackSection` in `IOPEFInternals.c` /
  `IOPEFLoader.c` (PEF binary-loader code, unrelated). **No `UnpackString`
  of any kind exists in this source directory.** **Genuinely absent.**

Only 1 of the 7 bucket-6 entries (`_SMADBHandler`) has a confirmed source
site and moves to bucket 5. The other 6 -- one non-ObjC C helper
(`_UnpackString`) and five Objective-C methods -- are **real, unresolved
gaps**: code the reference binary contains that this source directory does
not implement under any name, spelling, or declaration.
This is a materially different outcome from every other driver measured in
this batch (Awacs, Burgundy, OHare, ApplePCIBus), where every bucket-6
entry either resolved to a confirmed source site or to a well-understood
class-attribution artifact.

## Unmapped detail

Seven reference selectors have no exact-name-matching source
implementation:

- Two are build-generated, matching the pattern seen throughout this batch:
  - `+[IODisplayKernelServerInstance kernelServerInstance]` (20 bytes).
  - `+[IODisplayVersion driverKitVersionForIODisplay]` (16 bytes).
- Five are real, unresolved gaps (see Buckets above for the full grep
  evidence against each): `+[IOSmartDisplay probe:]`,
  `-[IOSmartADBDisplay findADBDisplayInfoForType:]`,
  `-[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]`,
  `-[IOSmartADBDisplay IOSMADBGetLogicalRegister:size:result:size:]`, and
  `-[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]`.

Unlike Awacs and Burgundy, none of these five are underscore-prefix
renames of a private category method -- `selector_check.py` independently
confirms 0 renames for this driver (see Selector check below), and direct
grepping (above) found no trace of any of the five under any spelling.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== iodisplay-ppc ===
symbol -[IOSmartDisplay registerLoudly] at 0x0 is not a function start
8 scattered/difference-form relocations (target section verified, field is a difference, not an address)
4 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
561 fused relocations, 1 violations
=== iodisplay-bundle-ppc ===
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

- `iodisplay-ppc`: `-[IOSmartDisplay registerLoudly]` at address `0x0` is a
  symbol in `__TEXT,__text` that is not one of IDA's recognized function
  starts -- confirmed absent from the 64-entry function list of
  `analysis-reference-ida.json` (checked programmatically). Also grepped
  for `registerLoudly` across the whole `src/driverkit-3/libDriver/ppc`
  directory: it is defined only for `IOMacRiscPCIBridge`
  (`IOMacRiscPCI.m:207`) and `IODeviceTreeBus` (`IODeviceTreeBus.m:701`),
  the two class-attribution sites already documented in Task 5's findings
  -- neither is `IOSmartDisplay`, and `IOSmartDisplay` does not itself
  subclass either of those classes (it derives directly from `Object`).
  So this address-0x0 symbol has **no candidate source implementation at
  all**, unlike the `IOApplePCIBus` `registerLoudly` case, which had a
  logic-matching implementation on a related class. This is the same
  general pattern as `+[AppleOHare probe:]`, `+[PPCBurgundy probe:]`, and
  `+[PPCAwacs probe:]` from earlier tasks: a real symbol-table entry with
  no corresponding IDA function and (here) no corresponding source
  implementation either.
- `iodisplay-bundle-ppc`: `__mh_bundle_header` at address `0x0` -- the
  standard synthetic bundle-header symbol every Mach-O bundle in this
  series carries at its load address; not a real function.

Neither candidate overlaps any function reported in the bucket table or
the source map, so neither affects the 18/7/0/0 correspondence numbers
above. `selector_check.py`'s "missing" list (below) includes
`-[IOSmartDisplay registerLoudly]` for the same reason
`+[PPCBurgundy probe:]` appeared there in the Burgundy task: it is a real,
named selector in the reference binary's symbol table that resolves to
address 0x0, so it never becomes one of the 25 in-scope functions the
source map is built from, and it is also absent from source under any
name -- a second confirmed gap independent of the five bucket-6 entries.

## Selector check

`selector_check.py` output against `src/driverkit-3/libDriver/ppc` (the
full shared directory, per the task brief), verbatim:

```
reference selectors: 26
our definitions:     237

renames (0):

duplicates (0):

missing (8):
    +[IODisplayKernelServerInstance kernelServerInstance]
    +[IODisplayVersion driverKitVersionForIODisplay]
    +[IOSmartDisplay probe:]
    -[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]
    -[IOSmartADBDisplay IOSMADBGetLogicalRegister:size:result:size:]
    -[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]
    -[IOSmartADBDisplay findADBDisplayInfoForType:]
    -[IOSmartDisplay registerLoudly]

extra (219):
    [see full verbatim list and class attribution below]
```

The "missing" list is the union of the two build-generated accessors, the
five genuine bucket-6 gaps, and `-[IOSmartDisplay registerLoudly]` (the
Invariant-check address-0x0 symbol, absent from source under any name) --
8 total, all independently confirmed above. 0 renames confirms the
underscore-prefix convention documented for `PPCAwacs` and `PPCBurgundy`
does **not** apply here -- consistent with `IODisplay`'s source being
Apple's own original code (no `2025 RhapsodiOS Project` copyright anywhere
in `src/driverkit-3/libDriver/ppc`), not a RhapsodiOS reimplementation.

### Attributing all 219 extras

Grouped by class and checked with `read_macho` against the two candidate
sibling binaries measured in this batch -- `IOApplePCIBus.config/IOApplePCIBus_reloc`
(Task 5's own 27 ObjC symbols: `IOPCIBridge` 9, `IOMacRiscPCIBridge` 4,
`IOMacRiscVCIBridge` 1, `IOGracklePCIBridge` 3, `IOPCIDevice` 8, plus 2
build-generated) and `IODisplay_reloc` itself:

| Class | Count | Attribution |
| --- | --- | --- |
| `IOFramebuffer` | 55 | Not a sibling -- absent from every shipped ppc binary, `IONDRVSupport_reloc` included. |
| `IONDRVFramebuffer` | 32 | Not a sibling -- 29 of 32 (24 base + 5 `(ProgramDAC)`) are defined in `IONDRVSupport_reloc`; 3 (2 base + 1 `(ProgramDAC)`) are absent from every shipped ppc binary. |
| `IOTreeDevice` | 31 | Not a sibling -- absent from every shipped ppc binary (see Task 5's findings for the note on this class). |
| `IODeviceTreeBus` | 17 | Not a sibling -- absent from every shipped ppc binary (see Task 5's findings). |
| `IOPropertyTable` | 14 | Not a sibling -- absent from every shipped ppc binary. |
| `IOOFFramebuffer` | 11 | Not a sibling -- defined in `IONDRVSupport_reloc`. |
| `IOPCIDevice` | 9 | Sibling: `IOApplePCIBus` (confirmed present in `IOApplePCIBus_reloc`; 8 of these 9 compiled, the 9th (`getResources`) is the unexplained source-only extra documented in Task 5). |
| `IOPCIBridge` | 9 | Sibling: `IOApplePCIBus` (8 of 9 compiled; the 9th (`match:key:location:`) is the unexplained source-only extra documented in Task 5). |
| `IOIX3DNDRV` | 9 | Not a sibling -- defined in `IONDRVSupport_reloc`. |
| `IOIXMNDRV` | 8 | Not a sibling -- defined in `IONDRVSupport_reloc`. |
| `IOATIMACH64NDRV` | 8 | Not a sibling -- absent from every shipped ppc binary. |
| `IOMacRiscPCIBridge` | 5 | Sibling: `IOApplePCIBus` (4 compiled selectors plus `registerLoudly`, the class-attribution anomaly fully resolved in Task 5's findings). |
| `IOGracklePCIBridge` | 3 | Sibling: `IOApplePCIBus` (all 3 compiled). |
| `IORootDevice` | 2 | Not a sibling -- absent from every shipped ppc binary. |
| `IODirectDevice(PPCPrivate)` | 2 | Not a sibling -- absent from every shipped ppc binary. |
| `IOPPCDeviceDescription` | 1 | Not a sibling -- absent from every shipped ppc binary. |
| `IOMacRiscVCIBridge` | 1 | Sibling: `IOApplePCIBus` (its 1 compiled selector). |
| `IOATIRAGE128NDRV` | 1 | Not a sibling -- absent from every shipped ppc binary. |
| `IOATINDRV` | 1 | Not a sibling -- defined in `IONDRVSupport_reloc`. |

Sum: 55+32+31+17+14+11+9+9+9+8+8+5+3+2+2+1+1+1+1 = 219. Matches the header
count exactly.

**Sibling attribution (27 total):** `IOPCIBridge` (9) + `IOMacRiscPCIBridge`
(5) + `IOMacRiscVCIBridge` (1) + `IOGracklePCIBridge` (3) + `IOPCIDevice`
(9) = 27 selectors belong to `IOApplePCIBus` (Task 5), all five of whose
classes are confirmed present in `IOApplePCIBus_reloc`'s own symbol table.
These counts cross-check exactly against Task 5's own findings: its five
classes' source-side method counts (9, 5, 1, 3, 9) match here to the digit,
including the two same-class anomalies (`registerLoudly` on
`IOMacRiscPCIBridge`, `match:key:location:` on `IOPCIBridge`) and the one
extra `IOPCIDevice` selector (`getResources`) that Task 5 already
identified as unexplained.

**Not-sibling attribution (192 total):** every remaining class --
`IOFramebuffer`, `IONDRVFramebuffer`, `IOTreeDevice`, `IODeviceTreeBus`,
`IOPropertyTable`, `IOOFFramebuffer`, `IOIX3DNDRV`, `IOIXMNDRV`,
`IOATIMACH64NDRV`, `IORootDevice`, `IODirectDevice(PPCPrivate)`,
`IOPPCDeviceDescription`, `IOATIRAGE128NDRV`, `IOATINDRV` -- was checked
against both `IOApplePCIBus_reloc` and `IODisplay_reloc` and found in
neither, the same 192-selector count and class list Task 5 independently
arrived at. **That does not mean all 192 are in the deferred `IONDRVSupport`
binary** -- every Mach-O in the shipped `ppc` reference tree was scanned by
symbol table for this fix, and the destination splits 58/134: 58 are defined
in `IONDRVSupport_reloc` (`IOOFFramebuffer` 11 of 11, `IOIX3DNDRV` 9 of 9,
`IOIXMNDRV` 8 of 8, `IOATINDRV` 1 of 1, `IONDRVFramebuffer` 24 of 26,
`IONDRVFramebuffer(ProgramDAC)` 5 of 6), and 134 are absent from every
shipped ppc binary, `IONDRVSupport_reloc` included -- 131 of those on the
nine classes with no defined method anywhere (`IOFramebuffer`,
`IOTreeDevice`, `IODeviceTreeBus`, `IOPropertyTable`, `IOATIMACH64NDRV`,
`IODirectDevice(PPCPrivate)`, `IORootDevice`, `IOATIRAGE128NDRV`,
`IOPPCDeviceDescription`), and the remaining 3 on otherwise-present classes
(`IONDRVFramebuffer` 2 of 26, `IONDRVFramebuffer(ProgramDAC)` 1 of 6). That
131-selector remainder is most plausibly kernel-resident DriverKit surface
that never shipped as a standalone ppc driver binary in this reference
tree -- a result in its own right, not an artifact of this attribution.

No extras in this run are same-class anomalies specific to `IODisplay`
itself -- unlike Task 5, every extra here belongs to one of the two
sibling attributions above; this driver's own real discrepancies surface
entirely through the "missing" list (5 genuine gaps plus
`registerLoudly`), not through unexplained extras.

### Full verbatim extras list

```
reference selectors: 26
our definitions:     237

renames (0):

duplicates (0):

missing (8):
    +[IODisplayKernelServerInstance kernelServerInstance]
    +[IODisplayVersion driverKitVersionForIODisplay]
    +[IOSmartDisplay probe:]
    -[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]
    -[IOSmartADBDisplay IOSMADBGetLogicalRegister:size:result:size:]
    -[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]
    -[IOSmartADBDisplay findADBDisplayInfoForType:]
    -[IOSmartDisplay registerLoudly]

extra (219):
    +[IODeviceTreeBus probe:]
    +[IODeviceTreeBus probeTree]
    +[IOFramebuffer convertCursorImage:hwDescription:cursorResult:]
    +[IOFramebuffer initialize]
    +[IOFramebuffer probe:]
    +[IONDRVFramebuffer probe:]
    +[IOPropertyTable freeString:]
    +[IOTreeDevice findForIndex:]
    +[IOTreeDevice findMatchingDevice:location:]
    -[IOATIMACH64NDRV hideCursor:]
    -[IOATIMACH64NDRV initEngine]
    -[IOATIMACH64NDRV moveCursor:frame:token:]
    -[IOATIMACH64NDRV open]
    -[IOATIMACH64NDRV setDisplayMode:depth:page:]
    -[IOATIMACH64NDRV setIntValues:forParameter:count:]
    -[IOATIMACH64NDRV showCursor:frame:token:]
    -[IOATIMACH64NDRV tempFlags]
    -[IOATINDRV getStartupMode:depth:]
    -[IOATIRAGE128NDRV moveCursor:frame:token:]
    -[IODeviceTreeBus addressCells]
    -[IODeviceTreeBus createDevice:ref:]
    -[IODeviceTreeBus getDevicePath:path:maxLength:]
    -[IODeviceTreeBus getDeviceUnitStr:name:maxLength:]
    -[IODeviceTreeBus getSlotName:index:]
    -[IODeviceTreeBus initFromDeviceDescription:]
    -[IODeviceTreeBus interruptSpecCells:count:]
    -[IODeviceTreeBus makeNVRAMDescriptor:descriptor:]
    -[IODeviceTreeBus mapInterrupts:interrupts:num:]
    -[IODeviceTreeBus mapUnitInterrupt:toInterrupt:parentHandle:]
    -[IODeviceTreeBus match:key:location:]
    -[IODeviceTreeBus probeBus]
    -[IODeviceTreeBus registerLoudly]
    -[IODeviceTreeBus resolveAddressCell:physicalAddress:]
    -[IODeviceTreeBus sizeCells]
    -[IODirectDevice(PPCPrivate) freePPC]
    -[IODirectDevice(PPCPrivate) initPPC]
    -[IOFramebuffer Description:]
    -[IOFramebuffer IOFBSetUserRange:size:]
    -[IOFramebuffer IOGetApertures:size:]
    -[IOFramebuffer IOGetDeviceName:size:]
    -[IOFramebuffer _commitToPendingMode]
    -[IOFramebuffer addUserRanges:num:]
    -[IOFramebuffer convertPixelInfoToDisplayInfo:mono:displayInfo:]
    -[IOFramebuffer getApertureInformationByIndex:apertureInfo:]
    -[IOFramebuffer getAttribute:value:]
    -[IOFramebuffer getAttributeForMode:andDepth:attribute:value:]
    -[IOFramebuffer getCharValues:forParameter:count:]
    -[IOFramebuffer getConfigIndexForDisplayModeAndDepth:depth:mono:configIndex:]
    -[IOFramebuffer getConfiguration:]
    -[IOFramebuffer getConnectionAttribute:attribute:value:]
    -[IOFramebuffer getConnections:connectInfo:]
    -[IOFramebuffer getCurrentConfigIndex:]
    -[IOFramebuffer getDisplayInfoForConfigIndex:info:connectFlags:]
    -[IOFramebuffer getDisplayModeAndDepthForIndex:mode:depth:mono:]
    -[IOFramebuffer getDisplayModeByIndex:displayMode:]
    -[IOFramebuffer getDisplayModeInformation:info:]
    -[IOFramebuffer getDisplayModeTiming:mode:timingInfo:connectFlags:]
    -[IOFramebuffer getIntValues:forParameter:count:]
    -[IOFramebuffer getNextMode:modeInfo:needFlags:]
    -[IOFramebuffer getPixelInformationForDisplayMode:andDepthIndex:pixelInfo:]
    -[IOFramebuffer getStartupMode:depth:]
    -[IOFramebuffer hideCursor:]
    -[IOFramebuffer initFromDeviceDescription:]
    -[IOFramebuffer makeConfigList]
    -[IOFramebuffer moveCursor:frame:token:]
    -[IOFramebuffer open]
    -[IOFramebuffer pendingDisplayMode]
    -[IOFramebuffer privateCall:select:paramSize:params:resultSize:results:]
    -[IOFramebuffer property_IODeviceClass:length:]
    -[IOFramebuffer registerForInterruptType:proc:refcon:]
    -[IOFramebuffer setAttribute:value:]
    -[IOFramebuffer setBrightness:token:]
    -[IOFramebuffer setCLUT:index:numEntries:brightness:options:]
    -[IOFramebuffer setCharValues:forParameter:count:]
    -[IOFramebuffer setConnectionAttribute:attribute:value:]
    -[IOFramebuffer setCursorImage:]
    -[IOFramebuffer setCursorState:y:visible:]
    -[IOFramebuffer setDisplayMode:depth:page:]
    -[IOFramebuffer setGammaTable:dataCount:dataWidth:data:]
    -[IOFramebuffer setIntValues:forParameter:count:]
    -[IOFramebuffer setInterruptState:state:]
    -[IOFramebuffer setPendingDisplayMode:]
    -[IOFramebuffer setStartupMode:depth:]
    -[IOFramebuffer setTransferTable:count:]
    -[IOFramebuffer setUserRanges]
    -[IOFramebuffer setupForCurrentConfig]
    -[IOFramebuffer showCursor:frame:token:]
    -[IOFramebuffer tempFlags]
    -[IOGracklePCIBridge getIOAperture]
    -[IOGracklePCIBridge mapRegisters:]
    -[IOGracklePCIBridge setConfigAddress:offset:]
    -[IOIX3DNDRV getHandler:level:argument:forInterrupt:]
    -[IOIX3DNDRV hideCursor:]
    -[IOIX3DNDRV initEngine]
    -[IOIX3DNDRV moveCursor:frame:token:]
    -[IOIX3DNDRV open]
    -[IOIX3DNDRV setDisplayMode:depth:page:]
    -[IOIX3DNDRV setIntValues:forParameter:count:]
    -[IOIX3DNDRV showCursor:frame:token:]
    -[IOIX3DNDRV tempFlags]
    -[IOIXMNDRV hideCursor:]
    -[IOIXMNDRV initEngine]
    -[IOIXMNDRV moveCursor:frame:token:]
    -[IOIXMNDRV open]
    -[IOIXMNDRV setDisplayMode:depth:page:]
    -[IOIXMNDRV setIntValues:forParameter:count:]
    -[IOIXMNDRV showCursor:frame:token:]
    -[IOIXMNDRV tempFlags]
    -[IOMacRiscPCIBridge getIOAperture]
    -[IOMacRiscPCIBridge isVCI]
    -[IOMacRiscPCIBridge mapRegisters:]
    -[IOMacRiscPCIBridge registerLoudly]
    -[IOMacRiscPCIBridge setConfigAddress:offset:]
    -[IOMacRiscVCIBridge isVCI]
    -[IONDRVFramebuffer IONDRVDoControl:inputSize:params:outputSize:privileged:]
    -[IONDRVFramebuffer IONDRVDoStatus:inputSize:params:outputSize:]
    -[IONDRVFramebuffer IONDRVGetDriverName:size:]
    -[IONDRVFramebuffer checkDriver]
    -[IONDRVFramebuffer doControl:params:]
    -[IONDRVFramebuffer doStatus:params:]
    -[IONDRVFramebuffer free]
    -[IONDRVFramebuffer getApertureInformationByIndex:apertureInfo:]
    -[IONDRVFramebuffer getAppleSense:info:]
    -[IONDRVFramebuffer getConfiguration:]
    -[IONDRVFramebuffer getDDCBlock:blockNumber:blockType:options:data:length:]
    -[IONDRVFramebuffer getDisplayModeByIndex:displayMode:]
    -[IONDRVFramebuffer getDisplayModeInformation:info:]
    -[IONDRVFramebuffer getDisplayModeTiming:mode:timingInfo:connectFlags:]
    -[IONDRVFramebuffer getIntValues:forParameter:count:]
    -[IONDRVFramebuffer getInterruptFunctionsTV:refCon:handler:enabler:disabler:]
    -[IONDRVFramebuffer getPixelInformationForDisplayMode:andDepthIndex:pixelInfo:]
    -[IONDRVFramebuffer getResInfoForMode:info:]
    -[IONDRVFramebuffer getStartupMode:depth:]
    -[IONDRVFramebuffer hasDDCConnect:]
    -[IONDRVFramebuffer initFromDeviceDescription:]
    -[IONDRVFramebuffer open]
    -[IONDRVFramebuffer setDisplayMode:depth:page:]
    -[IONDRVFramebuffer setInterruptFunctionsTV:refCon:handler:enabler:disabler:]
    -[IONDRVFramebuffer setStartupMode:depth:]
    -[IONDRVFramebuffer(ProgramDAC) getTransferTable:count:]
    -[IONDRVFramebuffer(ProgramDAC) interruptOccurred]
    -[IONDRVFramebuffer(ProgramDAC) setBrightness:token:]
    -[IONDRVFramebuffer(ProgramDAC) setCLUT:index:numEntries:brightness:options:]
    -[IONDRVFramebuffer(ProgramDAC) setTheTable]
    -[IONDRVFramebuffer(ProgramDAC) setTransferTable:count:]
    -[IOOFFramebuffer getConfiguration:]
    -[IOOFFramebuffer getDisplayModeByIndex:displayMode:]
    -[IOOFFramebuffer getDisplayModeInformation:info:]
    -[IOOFFramebuffer getDisplayModeTiming:mode:timingInfo:connectFlags:]
    -[IOOFFramebuffer getIntValues:forParameter:count:]
    -[IOOFFramebuffer getPixelInformationForDisplayMode:andDepthIndex:pixelInfo:]
    -[IOOFFramebuffer getStartupMode:depth:]
    -[IOOFFramebuffer initFromDeviceDescription:]
    -[IOOFFramebuffer setBrightness:token:]
    -[IOOFFramebuffer setDisplayMode:depth:page:]
    -[IOOFFramebuffer setTransferTable:count:]
    -[IOPCIBridge configReadLong:offset:value:]
    -[IOPCIBridge configWriteLong:offset:value:]
    -[IOPCIBridge createDevice:ref:]
    -[IOPCIBridge getDeviceUnitStr:name:maxLength:]
    -[IOPCIBridge getIOAperture]
    -[IOPCIBridge initFromDeviceDescription:]
    -[IOPCIBridge mapRegisters:]
    -[IOPCIBridge match:key:location:]
    -[IOPCIBridge setConfigAddress:offset:]
    -[IOPCIDevice configReadLong:value:]
    -[IOPCIDevice configWriteLong:value:]
    -[IOPCIDevice getIOAperture]
    -[IOPCIDevice getLocation:device:function:]
    -[IOPCIDevice getResources]
    -[IOPCIDevice initAt:parent:ref:]
    -[IOPCIDevice property_IODeviceType:length:]
    -[IOPCIDevice resolveAddressing]
    -[IOPCIDevice resolveInterrupts]
    -[IOPPCDeviceDescription property_IODeviceType:length:]
    -[IOPropertyTable addConfigData:]
    -[IOPropertyTable createProperty:flags:value:length:]
    -[IOPropertyTable deleteEntry:prev:]
    -[IOPropertyTable deleteProperty:]
    -[IOPropertyTable findProperty:prev:]
    -[IOPropertyTable freeString:]
    -[IOPropertyTable free]
    -[IOPropertyTable getProperty:flags:value:length:]
    -[IOPropertyTable getPropertyWithIndex:name:]
    -[IOPropertyTable init]
    -[IOPropertyTable setEntryProperty:flags:value:length:]
    -[IOPropertyTable setProperty:flags:value:length:]
    -[IOPropertyTable valueForStringKey:]
    -[IORootDevice initAt:ref:]
    -[IORootDevice match:location:]
    -[IOTreeDevice addressCells]
    -[IOTreeDevice configTable]
    -[IOTreeDevice denyNVRAM:]
    -[IOTreeDevice findMemoryApertures:num:]
    -[IOTreeDevice getApertures:items:]
    -[IOTreeDevice getDevicePath:maxLength:useAlias:]
    -[IOTreeDevice getLocation:device:function:]
    -[IOTreeDevice getRef]
    -[IOTreeDevice getResources]
    -[IOTreeDevice initAt:parent:ref:]
    -[IOTreeDevice isNVRAMProperty:]
    -[IOTreeDevice lookUpProperty:value:length:selector:isString:]
    -[IOTreeDevice match:location:]
    -[IOTreeDevice matchDevicePath:]
    -[IOTreeDevice nodeName]
    -[IOTreeDevice parent]
    -[IOTreeDevice propertyTable]
    -[IOTreeDevice property_IODeviceType:length:]
    -[IOTreeDevice property_IOSlotName:length:]
    -[IOTreeDevice publish]
    -[IOTreeDevice readNVRAMProperty:value:length:]
    -[IOTreeDevice resolveAddressCell:physicalAddress:]
    -[IOTreeDevice resolveAddressing]
    -[IOTreeDevice resolveInterrupts]
    -[IOTreeDevice setDelegate:]
    -[IOTreeDevice setNVRAMProperty:]
    -[IOTreeDevice sizeCells]
    -[IOTreeDevice taken:]
    -[IOTreeDevice writeNVRAMProperty:value:length:]
```

## Bundle stub

`IODisplay` (the non-relocatable bundle, profile `iodisplay-bundle-ppc`)
analysis has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) --
this small bundle wrapper is a loader shim with no Objective-C methods and
no driver logic of its own, so it carries no correspondence findings
against `IODisplay_reloc`. No source map or bucket table was built for it
(the source map and bucket script in this task both target
`IODisplay_reloc`, the statically linked kernel server that actually
contains the driver's compiled code).

## Shared source directory

`src/driverkit-3/libDriver/ppc` is framework code, not a self-contained
driver project -- the same directory Task 5 (`IOApplePCIBus`) used, and
also the home of the deferred `IONDRVSupport`. `--scope-to-objc` source
maps built against one binary only ever claim that binary's own classes,
so mapping `IODisplay_reloc` produces a clean 18 mapped / 7 unmapped / 0
dup / 0 disputed result restricted to its three actually-compiled classes
(`IOSmartDisplay`, `IOSmartADBDisplay`, `IOSmartDDCDisplay` -- per-class
split enumerated in Correspondence above).

Running `selector_check.py` against the whole shared directory again picks
up every method definition in the directory regardless of binary, giving
219 "extra" selectors here (vs. 213 for `IOApplePCIBus` in Task 5).
**None of the 219 extras are gaps in this driver.** 27 belong to
`IOApplePCIBus`'s five classes (confirmed via `read_macho` against
`IOApplePCIBus_reloc`, and cross-checked digit-for-digit against Task 5's
own source-side counts, including its two documented same-class
anomalies), and the remaining 192 are not on either sibling's own class
list (confirmed absent from both sibling binaries in this batch), of which
58 are defined in the deferred `IONDRVSupport_reloc` and 134 are absent
from every shipped ppc binary. This driver
carries no same-class anomalies of its own among the extras -- the
important discrepancies here are on the "missing" side instead: 5
Objective-C/C entry points the reference binary implements that this
source directory does not, under any name (see Buckets and Unmapped detail
above), which is the opposite failure mode from the extras
mischaracterization the task brief warns about, and is called out
explicitly rather than folded into the sibling-attribution story.
