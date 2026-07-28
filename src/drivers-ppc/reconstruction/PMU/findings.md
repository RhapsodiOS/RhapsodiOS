# drvPPCPMU reconstruction findings

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCPMU.config/drvPPCPMU` | 8492 | `4FA57C39341891263D099AC2A05647C80E2462F0B1993C16696A8CD990F05A68` |
| `drvPPCPMU.config/drvPPCPMU_reloc` | 41488 | `2F63C89DFEDEBCC5D1F2CEABA8417DC65BCC8BF32CA7B310B1EA0DD43831F7B5` |

Both sizes were measured and matched by Task 1's `binrecon validate`; re-hashing both files directly
during this task (`sha256sum`) reproduces the same two SHA-256 values exactly, and the source map's own
`reference_sha256` field (`src/drivers-ppc/reconstruction/PMU/source-map.json`) reproduces the
`drvPPCPMU_reloc` hash above exactly.

`src/kernel-7/conf/files.ppc` lists this driver's single implementation file under `mk_hasdrivers`:

```
bsd/dev/ppc/drvPMU/pmu.m		optional mk_hasdrivers
```

i.e. the driver's source is compiled into the kernel itself whenever `mk_hasdrivers` is set, the same
pattern already established for `drvPPCMesh`/`drvPPCGem`/`drvPPCCuda`/`drvPPCSym8xx`/`drvPPCOHare`/etc.
The shipped artifact measured here, `drvPPCPMU.config/drvPPCPMU_reloc`, is nonetheless a separate,
statically-linked loadable kernel server binary shipped as its own `.config` bundle pair for
DriverKit-style dynamic loading.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against `drvPPCPMU_reloc`,
scoped to the Objective-C methods found in that binary:

```
mapped 41 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPCPMUKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCPMUVersion driverKitVersionFordrvPPCPMU]'] 16
```

- Total functions in the reference analysis (`pmu-ppc`): 89.
- `read_macho`'s own symbol table for `drvPPCPMU_reloc` lists exactly 44 Objective-C-method-shaped
  symbols: 42 real `ApplePMU` methods (`+[ApplePMU probe:]` plus 41 instance methods) and the 2
  build-generated class accessors. `+[ApplePMU probe:]`'s symbol-table address is `0` -- the same
  address-`0x0` boundary anomaly every driver measured so far has shown (see Invariant check below),
  confirmed against the reference analysis's 89-entry function list: no entry at address `0` exists
  there, so `probe:` never becomes a function-start candidate and cannot appear in the source map's
  `mapped`/`unmapped`/`boundary_disputed` lists. Excluding it, 41 real `ApplePMU` methods have
  function-start addresses in the reference analysis -- exactly the map's 41 `mapped` count.
- `duplicate_candidates`: 0.
- `boundary_disputed`: 0, for the same reason given above: the one address-`0x0` anomaly (`probe:`) has
  no function-start entry in the reference analysis at all, so it never becomes a
  `mapped`/`unmapped`/`boundary_disputed` candidate in the map.

Counting every `+`/`-` method-signature line at column 0 in `pmu.m`'s single `@implementation ApplePMU`
block: **43 method definitions** (`grep -n '^[+-] '`), one more than the plan's orientation figure and
matching `selector_check.py`'s "our definitions: 43" exactly (see Selector check below) -- the same
"plan's counts are approximate" pattern noted in every prior task.

Of those 43 source methods:

- 41 have an address-matching counterpart the source map places (`mapped`).
- 1 -- `+[ApplePMU probe:]` (`pmu.m:62`) -- has an exact-selector match in the binary's symbol table but
  at address `0x0`, which is not a function start in the reference analysis, so it cannot be
  address-mapped; it is a name match with no analysis-side function to map it to -- the same anomaly
  pattern found in `drvPPCSym8xx` and `drvPPCOHare`. This line originally called that "not a genuine
  gap". Per the Invariant check correction below, it **is** one: `__text+0` holds real code IDA's
  analysis omits, so `drvPPCPMU` has one real unmapped function, not zero.
- 1 -- `-[ApplePMU ADBSetFileServerMode:::]` (`pmu.m:576`) -- is a genuine source-only selector: it has
  **no** counterpart anywhere in the shipped binary's 44-entry ObjC symbol table (confirmed directly
  against `read_macho`'s full selector list; no similarly-named selector at any arity exists either, so
  this is not an arity/rename mismatch). See Selector check below for the full characterisation.
- 0 binary selectors besides the 2 build-generated ones are missing a same-named source counterpart.

That leaves the reference binary's own unmapped set at 2 (both build-generated), the number reported by
the source map above.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and the reference analysis
passed to it, so verifying a `--scope-to-objc` map requires scoping the analysis to the same covered
addresses first:

```
analysis functions 89 -> scoped 43
load_source_map OK
```

43 is exactly 41 mapped + 2 unmapped, confirming the map's covered-address set is precisely the 43-entry
ObjC scope claimed above (the reference analysis's 89 functions minus the unnamed jump islands/
build-generated-class overlap and the bucket-6 helpers not in the ObjC scope, and independently of the
44th, address-`0x0` `probe:` symbol that isn't a function start at all).

## Buckets

Bucket table from `bucket_functions.py` run against
`tools/binrecon/out/pmu-ppc/published/analysis-reference-ida.json` and
`src/drivers-ppc/reconstruction/PMU/source-map.json`:

```
total functions: 89
  mapped: 41
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 44
  4-build-generated-class: 2
      0x2424  +[drvPPCPMUKernelServerInstance kernelServerInstance]  (20 bytes)
      0x2438  +[drvPPCPMUVersion driverKitVersionFordrvPPCPMU]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 2
      0x1ebc  _gotInterruptCause  (148 bytes)
      0x23bc  _timer_expired  (88 bytes)
counted: 89
RECONCILES: yes
```

Buckets 1 (`crt-dyld`) and 2 (`picsymbol-stub`) are empty because `drvPPCPMU_reloc` is a statically
linked kernel server, not an `MH_EXECUTE` helper: it carries no crt/dyld startup routines and its
analysis has no `__picsymbol_stub` section for the stub-range check to match against.

Bucket 5 prints 0 from the script by construction; it is populated by hand against every bucket-6 entry.
Both bucket-6 entries are non-static, non-ObjC C functions declared with file-local prototypes at the top
of `pmu.m` (`pmu.m:45-46`) and defined later in the same file -- neither is a libgcc helper.

- `_gotInterruptCause` -- `pmu.m:1533`, `void gotInterruptCause(id PMUdriver, UInt32 unused, UInt32
  length, UInt8 * data)` (non-static). 148 bytes, 13 basic blocks: source is a 5-way `if`/`else if`-chain
  over `interruptSource` bits (ADB, battery, one-second, environment, brightness), the first arm calling
  `[PMUdriver ADBinput:length:data]` and every other arm calling `IOLog` with a distinct string, no shared
  join between arms -- consistent with roughly 2 blocks per branch level (condition + leaf) across 5
  levels plus the entry/epilogue. It is set as the `pmCallback_func` callback for the debug-mode PMU
  interrupt handler (`getInterruptState.pmCallback = gotInterruptCause;`, `pmu.m:1519`), which is why it
  is a plain C function rather than an ObjC method -- the callback typedef (`pmCallback_func`,
  `pmu.h:42`) is a C function pointer, not a selector. Logic confirmed by structure.
- `_timer_expired` -- `pmu.m:1783`, `void timer_expired(port_t mach_port)` (non-static). 88 bytes, 1
  basic block. Source builds a `PMUmachMessage` struct on the stack, sets six fields, and calls
  `msg_send_from_kernel` once before returning -- straight-line, no branches, consistent with 1 block
  despite the larger size (stack struct initialization). It is registered with `ns_timeout`/`ns_untimeout`
  (`pmu.m:726`, `pmu.m:1432`) as the ADB-read timer's expiry callback, the same "C-callable entry thunk
  for a non-ObjC subsystem" pattern as `drvPPCSym8xx`'s `_Sym8xxTimerReq`, which also builds a
  `msg_header_t` and calls `msg_send_from_kernel`. Logic confirmed by structure.

Both bucket-6 entries therefore belong in bucket 5 (`fn-with-source-site`) by hand; neither is a genuine
gap.

## Unmapped detail

Two reference selectors have no source-mapped implementation, both build-generated:

- `+[drvPPCPMUKernelServerInstance kernelServerInstance]` (20 bytes) -- build-generated: a
  KernelServer wrapper class instance accessor emitted by the driver-kit build tooling, not hand-written
  driver code (same pattern as every other `_reloc` kernel server measured so far).
- `+[drvPPCPMUVersion driverKitVersionFordrvPPCPMU]` (16 bytes) -- build-generated: the DriverKit
  version accessor, likewise tool-emitted.

Both match `selector_check.py`'s entire "missing" list exactly (see Selector check below). There is no
additional binary-only gap in this driver's unmapped set. The other real gap this driver has runs in the
opposite direction -- a *source*-only selector with no binary counterpart, `-[ApplePMU
ADBSetFileServerMode:::]` -- which is not part of the `unmapped` category (that category is scoped to
binary functions the map's universe covers) and is instead characterised under Selector check below.

## Invariant check

`ppc_invariant_check.py` output for both binaries, verbatim:

```
=== pmu-ppc ===
symbol +[ApplePMU probe:] at 0x0 is not a function start
14 scattered/difference-form relocations (target section verified, field is a difference, not an address)
2 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
632 fused relocations, 1 violations
=== pmu-bundle-ppc ===
symbol __mh_bundle_header at 0x0 is not a function start
0 scattered/difference-form relocations (target section verified, field is a difference, not an address)
0 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
0 fused relocations, 1 violations
```

Both runs exit with code 1 (the checker's own exit status reflects "1 violations" printed for each), and
in both cases the single reported item is the address-`0x0` symbol/function-start anomaly, not a genuine
relocation-decode defect -- the same pattern every driver measured so far in this project has shown. No
scattered/difference-form relocation, HI16/HA16-LO16 pairing, or fused-relocation count reported any
additional problem for either binary.

- `pmu-ppc`'s anomalous symbol is `+[ApplePMU probe:]` at `0x0` -- confirmed above (Correspondence) to be
  a real, hand-written method (`pmu.m:62`) whose binary symbol-table entry simply carries no resolved
  function-start address in the reference analysis. This is a `boundary_disputed` candidate per the
  plan's established pattern, not a gap: source exists for it, and its selector matches exactly in the
  binary (see Selector check below).
> **CORRECTION.** The bullet above read `ppc_invariant_check.py`'s "is not a function
> start" message as "there is no code at that address", and called the symbol a
> symbol-table entry with no resolved function-start address. That was wrong, and the same
> misreading was repeated across every driver spec in this series. `__text+0` in
> `drvPPCPMU_reloc` holds `7c0802a6` -- `mflr r0` -- and it is IDA's *analysis* that omits
> the function there, not Apple's binary that omits the code. `read_macho` reports address
> `0` for every undefined symbol too (`_IOLog`, `_objc_msgSend`, ...), which is what made a
> defined symbol at `__text+0` look empty.
>
> **`+[ApplePMU probe:]` is a real function the analysis does not record, not a phantom.**
> It is an unmapped real function -- a genuine gap, not an artifact of the tooling.
> `pmu.m:62` defines a `probe:` whose selector matches, but that correspondence is now
> *unverified* rather than *unnecessary*: there is Apple code at `__text+0` and nothing here
> has compared the two. Its body is not written here; that is separate work. Nothing was
> re-measured for this correction and no source map was regenerated: the mapped/unmapped
> counts above are unaffected, because IDA never had this function to map. The checker now
> distinguishes the two cases. See
> `src/drivers-ppc/reconstruction/IOADBDevice/findings.md`, "The misreading".

- `pmu-bundle-ppc`'s anomalous symbol, `__mh_bundle_header`, is the standard synthetic bundle-header
  symbol every Mach-O bundle carries at its load address -- identical to every other `_reloc`/bundle pair
  measured in this project.

**Actual relocation-decode violations: 0 for both binaries.** The "1 violations" line each run prints is
the address-`0x0` symbol/function-start anomaly described above, consistent with the plan's stated
expectation ("Expect 0 relocation violations").

## Selector check

`selector_check.py` output, verbatim:

```
reference selectors: 44
our definitions:     43

renames (0):

duplicates (0):

missing (2):
    +[drvPPCPMUKernelServerInstance kernelServerInstance]
    +[drvPPCPMUVersion driverKitVersionFordrvPPCPMU]

extra (1):
    -[ApplePMU ADBSetFileServerMode:::]
```

Exit code: 0.

"Reference selectors: 44" matches the `read_macho`-derived count in Correspondence above exactly (42 real
`ApplePMU` methods, including the address-`0x0` `probe:` anomaly counted by *name*, plus the 2
build-generated accessors). "Our definitions: 43" matches the method-definition recount in Correspondence
exactly.

Characterising each entry, class-insensitively as well (grepping `ApplePMU|drvPPCPMU` case-insensitively
across `src/kernel-7/bsd/dev/ppc/drvPMU` finds only the exact casings already listed here -- no additional
class-name collision):

- `+[drvPPCPMUKernelServerInstance kernelServerInstance]`, `+[drvPPCPMUVersion
  driverKitVersionFordrvPPCPMU]` -- both build-generated (see Unmapped detail); no source counterpart
  exists or is expected for either class.
- `-[ApplePMU ADBSetFileServerMode:::]` -- a genuine source-only selector, the only one found across all
  driver reconstructions in this project so far. It is declared as a required method of the shared
  `@protocol ADBservice` (`pmu.h:99-101`, inside the protocol block spanning `pmu.h:62-125`) and defined
  in `pmu.m:576-582` as a one-line stub: `return kPMUNotSupported;`, with no branches. This matches a
  header comment on the status enum itself (`pmu.h:51`): `kPMUNotSupported = 3, // PMU don't do that
  (Cuda does, though)` -- i.e. the driver's own source documents that this protocol method is
  intentionally a PowerBook/PMU no-op, contrasted with `AppleCuda`'s desk-machine implementation of the
  same `ADBservice` protocol, which does support it. Despite being real, hand-written, protocol-required
  source, this selector has **no** entry anywhere in the shipped `drvPPCPMU_reloc` binary's 44-symbol
  ObjC table (confirmed directly against `read_macho`'s full selector list above) -- not a
  trivial-function compiler elision (every other equally small ADB stub, e.g. the 1-block bucket-6
  entries, is still present as a distinct symbol) but a selector that Apple's shipped binary simply never
  emitted. This is a genuine, characterised gap in the opposite direction from every other driver
  measured so far (source has it, binary doesn't, rather than the reverse), and it is exactly the item
  Task 7 needs when pairing `ApplePMU`'s `ADBservice` conformance against `AppleCuda`'s.
- No renames and no duplicates: `ApplePMU` has a single `@implementation` block with 43 distinct
  selectors, so there is no possibility of an arity mismatch or a same-named method colliding across
  categories (this driver has no categories at all, unlike `drvPPCSym8xx`/`drvPPCMesh`).

## Bundle stub

`drvPPCPMU` (the non-relocatable bundle, profile `pmu-bundle-ppc`) analysis has exactly 2 functions:

```
0xf04 ['dyld_stub_binding_helper'] 48
0xf34 ['__dyld_func_lookup'] 32
```

Both are named, standard dyld loader-glue routines (not driver code) -- this small bundle wrapper is a
loader shim with no Objective-C methods and no driver logic of its own, so it carries no correspondence
findings against `ApplePMU`. No source map or bucket table was built for it (the source map and bucket
script in this task both target `drvPPCPMU_reloc`, the statically linked kernel server that actually
contains the driver's compiled code), matching the pattern established for every other bundle pair
measured in this project.

## Protocol selectors

`ApplePMU : IODirectDevice <ADBservice, RTCservice, NVRAMservice, PowerService>`. The four protocols are
declared in `pmu.h` (`@protocol ADBservice` at `pmu.h:62-125`, `RTCservice` at `pmu.h:129-144`,
`NVRAMservice` at `pmu.h:148-164`, `PowerService` at `pmu.h:168-173`); the concrete `@interface ApplePMU`
adopting all four lives in `pmupriv.h:136-337`, which redeclares each protocol's methods (grouped under
matching comments, e.g. `// ADB protocol`, `pmupriv.h:197`) plus a `// private methods` block
(`pmupriv.h:303-336`) of methods outside all four protocols. This section lists the full set of selectors
the shipped `drvPPCPMU_reloc` binary implements, grouped by declaring protocol (or driver-private), for
Task 7's pairing against `AppleCuda` (`<ADBservice, RTCservice>` on the same `IODirectDevice` superclass).

**`ADBservice`** (`pmu.h:62-125`) -- 13 protocol-declared selectors, 12 present in the binary:

```
-[ApplePMU registerForADBAutopoll::]
-[ApplePMU ADBWrite:::::::]
-[ApplePMU ADBRead:::::]
-[ApplePMU ADBReset:::]
-[ApplePMU ADBFlush::::]
-[ApplePMU ADBSetPollList::::]
-[ApplePMU ADBPollDisable:::]
-[ApplePMU ADBPollEnable:::]
-[ApplePMU ADBSetPollRate::::]
-[ApplePMU ADBGetPollRate::::]
-[ApplePMU ADBSetAlternateKeyboard::::]
-[ApplePMU poll_device]
```

(12 present; the 13th, `-[ApplePMU ADBSetFileServerMode:::]`, is the one genuine source-only gap
characterised in Selector check above and has **no** binary entry.) Note `-[ApplePMU ADBinput::]`, despite
its name, is **not** part of the `ADBservice` protocol block in `pmu.h` -- it is declared in
`pmupriv.h`'s `// private methods` section instead (see Driver-private below), the callback `ApplePMU`'s
own ADB read path invokes internally rather than a protocol-required entry point.

**`RTCservice`** (`pmu.h:129-144`) -- 3 of 3 protocol-declared selectors present in the binary:

```
-[ApplePMU registerForClockTicks::]
-[ApplePMU setRealTimeClock::::]
-[ApplePMU getRealTimeClock::::]
```

**`NVRAMservice`** (`pmu.h:148-164`) -- 2 of 2 protocol-declared selectors present in the binary:

```
-[ApplePMU readNVRAM::::::]
-[ApplePMU writeNVRAM::::::]
```

**`PowerService`** (`pmu.h:168-173`) -- 1 of 1 protocol-declared selector present in the binary:

```
-[ApplePMU registerForPowerInterrupts::]
```

**Driver-private** (declared on `ApplePMU` itself, outside all four protocols -- `IODirectDevice`
overrides, the `ADBinput::` internal callback, PMU-transmission internals, the un-protocoled
`sendMiscCommand:::::::` labelled only by a `// Misc protocol` comment with no matching `@protocol`, and
VIA shift-register/interrupt helpers) -- 24 declared, all 24 present in the binary:

```
+[ApplePMU probe:]                            (address 0x0, boundary_disputed anomaly)
-[ApplePMU initFromDeviceDescription:]
-[ApplePMU free]
-[ApplePMU interruptOccurred]
-[ApplePMU interruptOccurredAt:]
-[ApplePMU timeoutOccurred]
-[ApplePMU receiveMsg]
-[ApplePMU sendMiscCommand:::::::]
-[ApplePMU ADBinput::]
-[ApplePMU StartPMUTransmission:]
-[ApplePMU SendPMUByte:]
-[ApplePMU ReadPMUByte:]
-[ApplePMU WaitForAckLo]
-[ApplePMU WaitForAckHi]
-[ApplePMU GetPMUInterruptState]
-[ApplePMU RestorePMUInterrupt:]
-[ApplePMU DisablePMUInterrupt]
-[ApplePMU EnablePMUInterrupt]
-[ApplePMU AcknowledgePMUInterrupt]
-[ApplePMU GetSRInterruptState]
-[ApplePMU RestoreSRInterrupt:]
-[ApplePMU DisableSRInterrupt]
-[ApplePMU EnableSRInterrupt]
-[ApplePMU CheckRequestQueue]
```

12 (`ADBservice` present) + 3 (`RTCservice`) + 2 (`NVRAMservice`) + 1 (`PowerService`) + 24
(driver-private, all present) = **42**, matching the real-`ApplePMU`-selector count established in
Correspondence above exactly (44 total ObjC symbols in the binary minus the 2 build-generated accessors).
Declared-but-absent count: 13+3+2+1 = 19 protocol-declared selectors, 18 present, 1 missing
(`ADBSetFileServerMode:::`); 24 private declared, 24 present, 0 missing; 19+24 = 43 total declared,
matching the source method recount in Correspondence exactly.
`ADBSetFileServerMode:::` is the sole protocol-declared selector with no binary implementation, and it
belongs to `ADBservice` -- the one protocol `ApplePMU` and `AppleCuda` have in common per the plan's Task
7 pairing note.
