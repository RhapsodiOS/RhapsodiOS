# IOApplePCIBus reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `IOApplePCIBus.config/IOApplePCIBus` | 8500 | `76BC7D0EC7599F6DC8E9B8D813DB0850C6F1B1CE62F8E9760BC857C4157EFEB8` |
| `IOApplePCIBus.config/IOApplePCIBus_reloc` | 26668 | `59F4DFF2481850E5F18B275CFCBE7950CCE74658D18DAD03FF68EC0A98DB9C4D` |

Both re-verified locally with `sha256sum` against the paths under
`C:/Users/raynorpat/Downloads/test/Drivers/ppc/`. Both match.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`IOApplePCIBus_reloc`, scoped to the Objective-C methods found in that binary
(26 of the 52 total functions IDA reported claimed by the map; see the note
on the 27th ObjC-named function below):

```
mapped 24 unmapped 2 dup 0 disputed 0
  unmapped: ['+[IOApplePCIBusKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[IOApplePCIBusVersion driverKitVersionForIOApplePCIBus]'] 16
```

- Total functions in the reference analysis: 52.
- IDA's function list carries 27 named Objective-C methods (verified by
  filtering `analysis-reference-ida.json` for `-[`/`+[` names). The
  `--scope-to-objc` map claims only 26 of them (24 mapped + 2 unmapped) --
  see the note below on the 27th.
- Out of scope: 26, composed of 25 unnamed jump islands (bucket 3) plus the
  1 named function the map does not classify into any of its four
  categories (see next paragraph and Buckets below).
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0.

**The 27th ObjC function is `-[IOPCIBridge registerLoudly]` at address
`0x0`, 12 bytes.** Unlike the address-0x0 symbol seen in every other driver
in this batch (`+[AppleOHare probe:]`, `+[PPCBurgundy probe:]`,
`+[PPCAwacs probe:]`), which is a symbol-table entry that never appears in
IDA's own function list, this one *does* appear as a genuine IDA function
(three instructions: `stwu`, `addi`, `blr`) -- and correspondingly
`ppc_invariant_check.py` reports **0** `check_functions` violations for
this binary (see Invariant check below), because there is no
symbol/function-start mismatch to flag. It is simply absent from all four
of the source map's own output categories (`mapped`, `unmapped`,
`duplicate_candidates`, `boundary_disputed`) -- the `--scope-to-objc`
builder does not classify it at all. `bucket_functions.py` independently
recovers it into bucket 6 (see Buckets below), which is how this task
resolves it.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses
and the reference analysis passed to it, so verifying a `--scope-to-objc`
map requires scoping the analysis to the same covered addresses first: the
map does not claim the 25 unnamed jump islands or the address-0x0
`registerLoudly` function, and the bucket reconciliation below accounts for
those 26 separately.

```
analysis functions 52 -> scoped 26
load_source_map OK
```

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/applepcibus-ppc/published/analysis-reference-ida.json`
and `src/drivers-ppc/reconstruction/ApplePCIBus/source-map.json`:

```
total functions: 52
  mapped: 24
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 25
  4-build-generated-class: 2
      0xdec  +[IOApplePCIBusKernelServerInstance kernelServerInstance]  (20 bytes)
      0xe00  +[IOApplePCIBusVersion driverKitVersionForIOApplePCIBus]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 1
      0x0  -[IOPCIBridge registerLoudly]  (12 bytes)
counted: 52
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because
`IOApplePCIBus_reloc` is a statically linked kernel server, not an
`MH_EXECUTE` helper: it carries no crt/dyld startup routines and its
analysis has no `__picsymbol_stub` section for the stub-range check to
match against.

**Bucket 6's single entry, resolved.** Grepping
`src/driverkit-3/libDriver/ppc` for `registerLoudly` finds two
definitions, neither on `IOPCIBridge`:

- `IOMacRiscPCI.m:207`, under `@implementation IOMacRiscPCIBridge`
  (`IOPCIBridge`'s own direct subclass):
  ```
  - registerLoudly
  {
      return( self);
  }
  ```
- `IODeviceTreeBus.m:701`, under `@implementation IODeviceTreeBus`:
  ```
  - registerLoudly
  {
      return( nil);
  }
  ```

`IOPCIBridge`'s own `@implementation` block (`IOMacRiscPCI.m:71`-`204`)
does **not** define `registerLoudly` at all (confirmed by listing every
method signature in that span). The reference binary's compiled body at
address `0x0` is `stwu; addi; blr` -- a bare prologue/epilogue with no
instruction that clears or reloads `r3`, so it returns whatever was passed
in as `self` (the ObjC calling convention already has `self` in `r3` on
entry). That matches the *logic* of `IOMacRiscPCIBridge`'s `return (self)`
exactly, and does not match `IODeviceTreeBus`'s `return (nil)` (which would
require an explicit zero load).

So this bucket-6 entry has a **logic match without a class-name match**:
the reference binary attributes `registerLoudly` to the base class
`IOPCIBridge`, while this source implements the matching body only on the
subclass `IOMacRiscPCIBridge` (`IOMacRiscPCI.m:207`). Per the established
caution that "a name match is not a logic match," the converse also
applies here -- this is a logic match with a class attribution that does
not line up, so it is recorded as resolved-with-caveat rather than folded
silently into bucket 5. It is the same phenomenon `selector_check.py`
reports from the source side as the extra `-[IOMacRiscPCIBridge
registerLoudly]` (see Selector check below) -- one real discrepancy, visible
from both directions of the comparison, not two.

No static C functions were found anywhere in `src/driverkit-3/libDriver/ppc`
relevant to this binary's five classes.

## Unmapped detail

Two reference selectors have no exact-name-matching source implementation,
both build-generated DriverKit accessors with no hand-written counterpart:

- `+[IOApplePCIBusKernelServerInstance kernelServerInstance]` (20 bytes) --
  a KernelServer wrapper class instance accessor, matching the pattern seen
  in every other driver measured in this series.
- `+[IOApplePCIBusVersion driverKitVersionForIOApplePCIBus]` (16 bytes) --
  the DriverKit version accessor, likewise tool-emitted.

This driver has no `duplicate_candidates` and no `boundary_disputed`
entries from the source-map builder itself; its one true anomaly
(`registerLoudly`) is bucket-6 only, as described above.

## Invariant check

`ppc_invariant_check.py` output for both binaries:

```
=== applepcibus-ppc ===
10 scattered/difference-form relocations (target section verified, field is a difference, not an address)
5 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
457 fused relocations, 0 violations
=== applepcibus-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

`applepcibus-ppc` reports **0** violations -- unlike every other driver
measured in this series, its address-0x0 symbol (`-[IOPCIBridge
registerLoudly]`) *is* a recognized IDA function start, so `check_functions`
has nothing to flag. This is consistent with, not contrary to, the general
"one address-0x0 symbol per driver" pattern: the symbol still exists at
0x0, it just happens to be a genuine function this time rather than a
placeholder, so it does not surface as a `boundary_disputed` candidate from
the invariant checker (see the Correspondence section above for how it
still surfaces, via `bucket_functions.py`, and the Buckets section for its
resolution).

`applepcibus-bundle-ppc`'s single violation is the standard synthetic
`__mh_bundle_header` symbol every Mach-O bundle carries at its load
address -- not a real function, the same pattern seen in every bundle
profile in this series.

## Selector check

`selector_check.py` output against `src/driverkit-3/libDriver/ppc`
(the full shared directory, per the task brief):

```
reference selectors: 27
our definitions:     237

renames (0):

duplicates (0):

missing (3):
    +[IOApplePCIBusKernelServerInstance kernelServerInstance]
    +[IOApplePCIBusVersion driverKitVersionForIOApplePCIBus]
    -[IOPCIBridge registerLoudly]

extra (213):
    +[IODeviceTreeBus probe:]
    +[IODeviceTreeBus probeTree]
    +[IOFramebuffer convertCursorImage:hwDescription:cursorResult:]
    +[IOFramebuffer initialize]
    +[IOFramebuffer probe:]
    +[IONDRVFramebuffer probe:]
    +[IOPropertyTable freeString:]
    +[IOSmartADBDisplay probeADBForDisplays]
    +[IOSmartDisplay findForConnection:refCon:]
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
    -[IOMacRiscPCIBridge registerLoudly]
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
    -[IOPCIBridge match:key:location:]
    -[IOPCIDevice getResources]
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
    -[IOSmartADBDisplay attach:refCon:]
    -[IOSmartADBDisplay doConnect]
    -[IOSmartADBDisplay free]
    -[IOSmartADBDisplay getDisplayInfoForMode:flags:]
    -[IOSmartADBDisplay getLogicalRegister:data:]
    -[IOSmartADBDisplay initForADB:]
    -[IOSmartADBDisplay setLogicalRegister:data:]
    -[IOSmartADBDisplay setWiggle:]
    -[IOSmartADBDisplay writeWithAcknowledge:data:ackValue:]
    -[IOSmartDDCDisplay attach:refCon:]
    -[IOSmartDDCDisplay getDisplayInfoForMode:flags:]
    -[IOSmartDisplay attach:refCon:]
    -[IOSmartDisplay attached]
    -[IOSmartDisplay detach]
    -[IOSmartDisplay getDisplayInfoForMode:flags:]
    -[IOSmartDisplay getGammaTableByIndex:dataCount:dataWidth:data:]
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
exit=0
```

The "missing" list adds `-[IOPCIBridge registerLoudly]` to the same two
build-generated accessors already covered in Unmapped detail -- this is
the source-side view of the bucket-6/class-attribution anomaly above, not
a third independent gap.

### Attributing all 213 extras

`src/driverkit-3/libDriver/ppc` also holds the sources for `IODisplay`
(Task 6, classes `IOSmartDisplay`, `IOSmartADBDisplay`, `IOSmartDDCDisplay`)
and the deferred `IONDRVSupport`. Every extra was grouped by its class name
and each class checked with `read_macho` against the two candidate sibling
binaries -- `IODisplay.config/IODisplay_reloc` (26 ObjC symbols: 8
`IOSmartDisplay`, 2 `IOSmartDDCDisplay`, 14 `IOSmartADBDisplay`, plus the 2
build-generated accessors) and `IOApplePCIBus_reloc` itself (this binary's
own 27 ObjC symbols, enumerated in Correspondence above). Class-by-class
counts among the 213 extras:

| Class | Count | Attribution |
| --- | --- | --- |
| `IOFramebuffer` | 55 | Deferred `IONDRVSupport` -- absent from both `IOApplePCIBus_reloc` and `IODisplay_reloc`. |
| `IONDRVFramebuffer` | 32 | Deferred `IONDRVSupport`. |
| `IOTreeDevice` | 31 | Deferred `IONDRVSupport` -- see note below on the brief's seven-class list. |
| `IODeviceTreeBus` | 17 | Deferred `IONDRVSupport` -- see note below. |
| `IOPropertyTable` | 14 | Deferred `IONDRVSupport`. |
| `IOOFFramebuffer` | 11 | Deferred `IONDRVSupport`. |
| `IOSmartADBDisplay` | 10 | Sibling: `IODisplay` (confirmed present in `IODisplay_reloc`). |
| `IOIX3DNDRV` | 9 | Deferred `IONDRVSupport`. |
| `IOIXMNDRV` | 8 | Deferred `IONDRVSupport`. |
| `IOATIMACH64NDRV` | 8 | Deferred `IONDRVSupport`. |
| `IOSmartDisplay` | 6 | Sibling: `IODisplay` (confirmed present in `IODisplay_reloc`). |
| `IOSmartDDCDisplay` | 2 | Sibling: `IODisplay` (confirmed present in `IODisplay_reloc`). |
| `IORootDevice` | 2 | Deferred `IONDRVSupport`. |
| `IODirectDevice(PPCPrivate)` | 2 | Deferred `IONDRVSupport` (category on a DriverKit base class, source-only in this directory). |
| `IOPPCDeviceDescription` | 1 | Deferred `IONDRVSupport`. |
| `IOPCIDevice` | 1 | **Not a sibling -- see below.** |
| `IOPCIBridge` | 1 | **Not a sibling -- see below.** |
| `IOMacRiscPCIBridge` | 1 | **Not a sibling -- the `registerLoudly` anomaly, see Buckets above.** |
| `IOATIRAGE128NDRV` | 1 | Deferred `IONDRVSupport`. |
| `IOATINDRV` | 1 | Deferred `IONDRVSupport`. |

Sum: 55+32+31+17+14+11+10+9+8+8+6+2+2+2+1+1+1+1+1+1 = 213. Matches the
header count exactly.

**Sibling attribution (18 total):** `IOSmartDisplay` (6) + `IOSmartADBDisplay`
(10) + `IOSmartDDCDisplay` (2) = 18 selectors belong to `IODisplay`
(Task 6), confirmed present in `IODisplay_reloc`'s own symbol table via
`read_macho`, not by name guessing.

**Deferred `IONDRVSupport` attribution (192 total):** every remaining class
except the three flagged "not a sibling" -- `IOFramebuffer`,
`IONDRVFramebuffer`, `IOTreeDevice`, `IODeviceTreeBus`, `IOPropertyTable`,
`IOOFFramebuffer`, `IOIX3DNDRV`, `IOIXMNDRV`, `IOATIMACH64NDRV`,
`IORootDevice`, `IODirectDevice(PPCPrivate)`, `IOPPCDeviceDescription`,
`IOATIRAGE128NDRV`, `IOATINDRV` -- was checked against both
`IOApplePCIBus_reloc` and `IODisplay_reloc` and found in neither, so all
192 selectors are attributed to the deferred `IONDRVSupport` binary that
also lives in this shared source directory.

**Note on `IODeviceTreeBus` and `IOTreeDevice` specifically:** the task
brief lists these two as part of *this* binary's seven classes. Empirically
they are not: `IOApplePCIBus_reloc`'s full symbol table (52 entries, listed
in full) contains only four `.objc_class_name_*` references to these two
classes -- `.objc_class_name_IODevice`, `.objc_class_name_IODeviceTreeBus`,
`.objc_class_name_IOPCIDevice`, `.objc_class_name_IOTreeDevice` -- and all
four are `binding: external`, `address: 0`, `section: None`, i.e.
*undefined* symbols this object file references but does not itself
define. Neither the relocatable object nor the bundle (`applepcibus-bundle-ppc`,
2 functions, both dyld stubs) contains a single compiled
`IODeviceTreeBus` or `IOTreeDevice` method. All 48 of their selectors
(17 + 31) found in source are therefore genuinely absent from both of
this task's reference artifacts and are attributed to the deferred
`IONDRVSupport` binary, which must be where these two classes are actually
compiled and where the external references resolve at link time.

**Three same-class extras, not sibling attributions:**

- `-[IOMacRiscPCIBridge registerLoudly]` -- `IOMacRiscPCI.m:207`. This is
  the source-side half of the bucket-6 `registerLoudly` class-attribution
  anomaly fully resolved in Buckets above; not a new finding.
- `-[IOPCIBridge match:key:location:]` -- `IOMacRiscPCI.m:133`
  (`- (BOOL) match:(IOPCIDevice *)device key:(const char *)key
  location:(const char *)location { return( [super match:device key:key
  location:location]); }`). A real, compilable trivial-override method on
  `IOPCIBridge` itself, confirmed present in source with a real body.
  `IOPCIBridge`'s 9 methods in the reference binary (enumerated in
  Correspondence above) do not include it under any name. **Recorded as a
  genuinely unexplained extra** -- present in source, absent from the
  compiled reference, with no rename or class-boundary explanation found.
- `-[IOPCIDevice getResources]` -- `IOPCIDevice.m:121`
  (`- getResources { [super getResources]; }`). Same situation: a real
  trivial-override method in source, confirmed by grep, not among
  `IOPCIDevice`'s 8 reference-binary methods. **Recorded as a genuinely
  unexplained extra.**

Both unexplained extras are minimal `[super ...]`-only overrides -- a
pattern consistent with (but not proof of) dead-stripping of a
zero-behavior-change override during Apple's original build, which this
static analysis cannot confirm or rule out.

## Bundle stub

`IOApplePCIBus` (the non-relocatable bundle, profile
`applepcibus-bundle-ppc`) analysis has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) --
this small bundle wrapper is a loader shim with no Objective-C methods and
no driver logic of its own, so it carries no correspondence findings
against `IOApplePCIBus_reloc`. No source map or bucket table was built for
it (the source map and bucket script in this task both target
`IOApplePCIBus_reloc`, the statically linked kernel server that actually
contains the driver's compiled code).

## Shared source directory

`src/driverkit-3/libDriver/ppc` is framework code, not a self-contained
driver project: it is the single source directory shared by three separate
binaries measured across this batch -- `IOApplePCIBus` (this task),
`IODisplay` (Task 6), and the deferred `IONDRVSupport` (not measured in
this batch at all). `--scope-to-objc` source maps built against one
binary only ever claim that binary's own classes, so mapping
`IOApplePCIBus_reloc` produces a clean 24 mapped / 2 unmapped / 0 dup / 0
disputed result restricted to its five actually-compiled classes
(`IOPCIBridge`, `IOMacRiscPCIBridge`, `IOMacRiscVCIBridge`,
`IOGracklePCIBridge`, `IOPCIDevice` -- per-class split enumerated in
Correspondence and the Selector check attribution table above).

Running `selector_check.py` against the whole shared directory, however,
necessarily picks up every method definition in every file in that
directory, regardless of which binary it belongs to -- which is exactly
why this task's selector check reports 213 "extra" selectors and only 0
renames. **None of the 213 extras are gaps in this driver's
reimplementation.** 18 belong to `IODisplay`'s three classes (confirmed via
`read_macho` against `IODisplay_reloc`), 192 belong to the deferred
`IONDRVSupport`'s classes (confirmed absent from both `IOApplePCIBus_reloc`
and `IODisplay_reloc`, including the `IODeviceTreeBus`/`IOTreeDevice`
classes the task brief nominally lists as this binary's own -- see the note
above), and the remaining 3 are same-class anomalies specific to this
binary, fully accounted for in Buckets and Selector check above (one
class-attribution mismatch on `registerLoudly`, and two confirmed-in-source
but absent-from-binary trivial overrides).

The task brief's warning that "mischaracterising those extras as gaps is
the single likeliest error in this batch" is borne out by the scale here:
without per-class attribution, a 213-selector extra list against a
24-method mapped driver would look like a near-total reimplementation
failure. It is not -- it is the shared-directory artifact the brief
predicted, now fully itemized by class and cross-checked against the
sibling binary's own symbol table rather than by name alone.
