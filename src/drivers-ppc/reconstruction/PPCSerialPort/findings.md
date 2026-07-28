# PPCSerialPort reconstruction findings

## Standing constraint: nothing was compiled

There is no PowerPC toolchain and no host C compiler in this environment. Nothing in this
measurement was built, linked, or executed. Every statement below is a claim of
*correspondence between our source and the shipped binary*, never a claim of buildability.

In particular: the claim that the renamed C functions "would now emit symbols matching
Apple's" follows from the Mach-O naming rule (the compiler prepends exactly one underscore,
so source `changeState` emits `_changeState`) -- it is an argument from the ABI, not an
observation of a build.

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `PPCSerialPort.config/PPCSerialPort` | 8500 | `33A0F9642F3A6A622CE5C17CF6BE08229F3586BA07ABD899E53764EFFB9847FF` |
| `PPCSerialPort.config/PPCSerialPort_reloc` | 62232 | `042AE84C5665991973441CA950F95317DF4842DB1A293CBC8E35ADDAA78270D9` |

`source-map.json`'s own `reference_sha256` reproduces the `_reloc` hash above exactly, as does
`ledger.json`. The reference analysis
(`tools/binrecon/out/ppcserialport-ppc/published/analysis-reference-ida.json`) carries the same
`input.sha256`.

Source: one file pair, `PPCSerialPort.m` (3138 lines) and `PPCSerialPort.h` (298), under
`src/drivers-ppc/input/drvPPCSerialPort/PPCSerialPort.drvproj/PPCSerialPort.lksproj/`.
Class `PPCSerialPort : IODirectDevice`.

## Reference analysis

IDA 9.2 is the only analyzer that supports PowerPC; the Ghidra and angr adapters reject a ppc
profile, so this is a single-analyzer measurement by necessity, not by choice.

```
functions: 285
unnamed  : 210
lowest   : 0x60
```

`lowest` is **greater than zero**. That is the address-0 rule confirmed *in advance*: IDA's
function list has no entry at `__text+0`, where `+[PPCSerialPort probe:]` actually lives. See
"The probe: exclusion" below -- this was established before the map was built precisely so it
could not be discovered later and misread as a missing function body.

After `filter_named_functions.py`:

```
functions: 75
unnamed  : 0
lowest   : 0x80
sha256   : 042AE84C5665991973441CA950F95317DF4842DB1A293CBC8E35ADDAA78270D9   (unchanged)
```

210 unnamed entries dropped, 75 named functions remain, and the input identity is preserved.

## The partition of `__TEXT,__text`

76 defined symbols in `__TEXT,__text`:

| Category | Count |
| --- | --- |
| Build-generated (`PPCSerialPortVersion`, `PPCSerialPortKernelServerInstance`) | 2 |
| Compiler runtime (`__udivdi3`, `__umoddi3` -- libgcc) | 2 |
| Hand-written Objective-C methods | 17 |
| Hand-written C functions | 55 |
| **Hand-written total** | **72** |

55 of the 72 are C. This is why the map was built **without `--scope-to-objc`**: scoping to
Objective-C would have covered 17 of 72 and reported itself complete. The unscoped
`--objc-methods` route is the one SCSIServer proved on PowerPC.

## Correspondence: all four categories

Coverage is judged across all four source-map categories, not `mapped` and `unmapped` alone.

| Category | Total | ObjC | C |
| --- | --- | --- | --- |
| `mapped` | 64 | 16 | 48 |
| `unmapped` | 9 | 2 | 7 |
| `duplicate_candidates` | 2 | 0 | 2 |
| `boundary_disputed` | 0 | 0 | 0 |
| **Sum** | **75** | **18** | **57** |

75 equals the analysis's named-function count exactly: every address is accounted for.

Reconciling that against the partition:

- 75 named functions = 2 build-generated + 2 compiler runtime + **71 hand-written**.
- The 72nd hand-written function is `+[PPCSerialPort probe:]`, which has no analyzer function
  entry and therefore cannot appear in any category. **The map accounts for 71 of the 72
  hand-written functions.**
- Of those 71: 66 have a source definition site (64 `mapped` + 2 `duplicate_candidates`) and 5
  are genuinely absent from our source.
- Objective-C: 16 mapped + `probe:` = 17. Complete.
- C: 48 mapped + 2 duplicate-candidates + 5 absent = 55. Complete.

### duplicate_candidates -- 2, both explained

Both are real duplicate definitions in our own source, not tool artifacts:

| Address | Symbol | Size | Definition sites in `PPCSerialPort.m` |
| --- | --- | --- | --- |
| `0x2e34` | `_SccCloseChannel` | 232 | line 2036 and line 2136 |
| `0x32b8` | `_SccChannelReset` | 76 | line 2025 and line 2174 |

`PPCSerialPort.m` defines each of these two functions **twice**, unconditionally. The file has
exactly one preprocessor conditional (`#ifdef __ppc__` at line 47, `#else` 49, `#endif` 51) and
neither pair is inside it, so both definitions of each function are live. The earlier definition
of each is a placeholder (an `IOLog(...: called)` plus one register write); the later is a full
implementation.

The source map is right to refuse to choose: the tool matches a symbol to a definition site by
name, and here the name resolves to two. It reports "symbol name resolves to multiple
definitions" rather than silently picking one.

**This is pre-existing and was not introduced by the Task 2 rename.** At the branch base
`05320f0c` the same four definitions are present under their old names:

```
2025:static void _SccChannelReset(PPCSerialPort *self)
2036:static void _SccCloseChannel(PPCSerialPort *self)
2136:static void _SccCloseChannel(PPCSerialPort *self)
2174:static void _SccChannelReset(PPCSerialPort *self)
```

The rename changed leading underscores only; it did not create or move a definition.

**Recorded as an uncertainty, not fixed here.** Two consequences follow that this measurement
cannot resolve without a compiler:

1. A C translation unit cannot define the same static function twice. If a build existed it
   would fail on these two. That the tree has never been compiled here is exactly why the defect
   survived.
2. Which of the two bodies corresponds to Apple's shipped code is a question about the 232 and
   76 bytes at `0x2e34` and `0x32b8`, and answering it means reading those bytes. Deleting the
   placeholder is the obvious guess, and a confident guess is a defect. It is left alone.

Both are outside Task 3's scope (Task 3 measures; Task 4's remit is the five absent functions
only). Flagged for the plan owner.

### boundary_disputed -- 0

No symbol's extent disagrees with its analyzer function's extent. Note that this is a statement
about the 75 functions the analysis *has*; the `probe:` anomaly at `0x0` never becomes an
analysis entry at all, so it cannot appear here either. The invariant checker catches it
separately -- see below.

### unmapped -- 9, only 5 of them gaps

| Address | Symbol | Size | Why |
| --- | --- | --- | --- |
| `0x43b4` | `+[PPCSerialPortKernelServerInstance kernelServerInstance]` | 20 | Build-generated |
| `0x43c8` | `+[PPCSerialPortVersion driverKitVersionForPPCSerialPort]` | 16 | Build-generated |
| `0x43d8` | `__udivdi3` | 1616 | Compiler runtime (libgcc) |
| `0x4a28` | `__umoddi3` | 1464 | Compiler runtime (libgcc) |
| `0x0bb0` | `_activatePort` | 204 | **Absent from our source** |
| `0x1e3c` | `_dataLatTOHandler` | 48 | **Absent from our source** |
| `0x1e9c` | `_frameTOHandler` | 108 | **Absent from our source** |
| `0x1f48` | `_delayTOHandler` | 112 | **Absent from our source** |
| `0x1ff8` | `_heartBeatTOHandler` | 132 | **Absent from our source** |

`__udivdi3` and `__umoddi3` are libgcc's 64-bit unsigned division and modulo helpers, linked into
the driver rather than written by Apple. They are excluded on the same grounds as MIG-generated
code -- they are not hand-written source and there is nothing to reconstruct. Together they are
3080 bytes, 15% of `__text`, so they dominate the byte count of the unmapped set while
contributing nothing to the reconstruction gap. **They are compiler runtime, not gaps.**

The two `+[...]` methods are emitted by the DriverKit build for every kernel server; likewise not
gaps.

## Buckets

```
total functions: 75
  mapped: 64
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 0
  4-build-generated-class: 2
      0x43b4  +[PPCSerialPortKernelServerInstance kernelServerInstance]  (20 bytes)
      0x43c8  +[PPCSerialPortVersion driverKitVersionForPPCSerialPort]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 9
      0xbb0  _activatePort  (204 bytes)
      0x1e3c  _dataLatTOHandler  (48 bytes)
      0x1e9c  _frameTOHandler  (108 bytes)
      0x1f48  _delayTOHandler  (112 bytes)
      0x1ff8  _heartBeatTOHandler  (132 bytes)
      0x2e34  _SccCloseChannel  (232 bytes)
      0x32b8  _SccChannelReset  (76 bytes)
      0x43d8  __udivdi3  (1616 bytes)
      0x4a28  __umoddi3  (1464 bytes)
counted: 75
RECONCILES: yes
```

Buckets 1 and 2 are empty, as they always are for a `_reloc` kernel server: there is no dyld
stub or CRT glue in a statically-relocatable kernel binary. Bucket 3 is empty because
`analysis-named.json` has already dropped the 210 unnamed entries. Bucket 4 holds exactly the two
build-generated class methods.

**Bucket 6 is nine, and only five of them are gaps.** The bucketer works from the map's `mapped`
list, so anything in another category lands here:

- 5 genuinely absent: `_activatePort` and the four TOHandlers.
- 2 compiler runtime: `__udivdi3`, `__umoddi3` -- accounted for above, not gaps.
- 2 duplicate-definition cases: `_SccCloseChannel`, `_SccChannelReset` -- these **do** have source
  sites, two each. Their appearance in a bucket named "no source site" is an artifact of the
  bucketer reading only `mapped`, and reading bucket 6 as the gap count would overstate the gap
  by 4.

## PowerPC invariant check

```
symbol +[PPCSerialPort probe:] at 0x0 has no function start in the analysis, but code is
present: the bytes there are a function prologue, so the analysis omits a real function
22 scattered/difference-form relocations (target section verified, field is a difference,
not an address)
4 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
1277 fused relocations, 1 violations
```

One violation, and it is the `probe:` line. Every other invariant holds: all 1277 fused
relocations reconstruct inside their named target sections, all 22 difference-form relocations
name real sections, all 4 HI16/HA16-LO16 pairs agree on their reconstructed value, no `jbsr`
island branches outside `__TEXT,__text`, and no `__OBJC` pointer lands anywhere it should not.
The decode is consistent; the byte-order and sign-extension failure modes this check exists to
catch are absent.

### The probe: exclusion -- what the violation does and does not mean

`+[PPCSerialPort probe:]` sits at `__text+0`. The first word there is `7c0802a6` -- `mflr r0`, a
function prologue. **That is real code.** IDA's function list simply has no entry at address 0,
which is why the analysis's lowest function address is `0x60` and not `0`.

The checker's wording is precise and deliberate: it distinguishes "no analyzer function and no
code" from "no analyzer function **but code is present**", and this is the second. The message
says so explicitly.

`probe:` is **present in our source**. It is therefore recorded as a **known exclusion** -- not a
gap, not a phantom, not an absent body. It is excluded from the map by construction, because a
source map is built from analyzer function entries and there is no entry to map. This is the sole
reason the map covers 71 of 72 rather than 72 of 72.

This is stated at length because the opposite reading -- treating the "not a function start"
message as evidence of a missing function body -- was recorded across five earlier specs in this
series and had to be retracted in 22 places.

## The rename: 55 missing definitions became 5

Every C function in `PPCSerialPort.m` was defined with a spurious leading underscore
(`static void _changeState(...)`), which under the Mach-O naming rule emits `__changeState` where
Apple's binary has `_changeState`. All 50 that had definition sites were wrong; none was right.

`tools/binrecon/symbol_name_check.py` is the gate. It establishes presence by a **definition
site**, never by an occurrence count and never by a regex over declaration syntax -- three ad-hoc
surveys earlier in this series were recorded as measurement and all three were retracted.

Both runs below were executed for this measurement rather than copied from prose. The "before"
run is against the pre-rename sources materialised from git at `8f71c8c9` (the rename's parent);
the "after" run is against the working tree.

**Before** (source dir: pre-rename `PPCSerialPort.m`/`.h` at `8f71c8c9`):

```
hand-written C symbols: 55
missing definitions   : 55
  _SetStructureDefaults    _activatePort           _deactivatePort
  _dataLatTOHandler        _frameTOHandler         _delayTOHandler
  _heartBeatTOHandler      _executeEvent           _freeRingBuffer
  _allocateRingBuffer      _CheckQueues            _changeState
  _watchState              _MyIOLog                _initChip
  _programChip             _ProbeSccDevice         _OpenScc
  _SccCloseChannel         _SccReadByte            _SccWriteByte
  _SccSetStopBits          _SccSetParity           _SccSetDataBits
  _SccChannelReset         _SccSetBaud             _SccReadData
  _SccWriteData            _SccReadReg             _SccWriteReg
  _SccWriteIntSafe         _PPCSerialRxDMAISR      _PPCSerialTxDMAISR
  _PPCSerialISR            _SccHandleExtInterrupt  _SccHandleRxInterrupt
  _SccHandleTxInterrupt    _SetUpTransmit          _SuspendTX
  _SendNextChar            _SccDisableInterrupts   _SccEnableInterrupts
  _SccSetDTR               _SccSetRTS              _SccGetDCD
  _SccGetCTS               _InitQueue              _CloseQueue
  _AddtoQueue              _RemovefromQueue        _FreeSpaceinQueue
  _UsedSpaceinQueue        _GetQueueSize           _AddBytetoQueue
  _GetBytetoQueue
```

(the checker prints one name per line; wrapped here for width, order preserved reading across)

**After** (source dir: the current tree):

```
hand-written C symbols: 55
missing definitions   : 5
  _activatePort
  _dataLatTOHandler
  _frameTOHandler
  _delayTOHandler
  _heartBeatTOHandler
```

**55 -> 5.** The rename fixed **50 functions at once**, and the 5 that remain are exactly the five
that are genuinely absent from our source -- they were unfixable by renaming because there was
nothing there to rename. `hand_written_c_symbols` reports 55 in both runs, so the denominator did
not move; only the numerator did.

The checker exits 1 in both runs, correctly: 5 missing is still missing.

## The five remaining gaps -- Task 4's work

| Address | Symbol | Span | Constraint available in our source |
| --- | --- | --- | --- |
| `0x0bb0` | `_activatePort` | 204 | Called 4x, never defined |
| `0x1e3c` | `_dataLatTOHandler` | 48 | No mention anywhere in source |
| `0x1e9c` | `_frameTOHandler` | 108 | No mention anywhere in source |
| `0x1f48` | `_delayTOHandler` | 112 | No mention anywhere in source |
| `0x1ff8` | `_heartBeatTOHandler` | 132 | No mention anywhere in source |

604 bytes as sized by the source map (next-symbol deltas within the map's own accounting; the
plan records 956 bytes using deltas that include trailing jump islands -- the true extent of each
function must be confirmed from its `blr` before any body is written, and neither figure should
be taken as that extent).

The four TOHandlers are **expected** to be `IOScheduleFunc` timeout callbacks. That is a
hypothesis, not a finding: nothing in our source references them at all, so nothing in the tree
constrains a wrong reading. Each one's registration site must be located in the disassembly
before its body is written.

## Route, for verbatim re-run

```bash
$VENVPY tools/binrecon/filter_named_functions.py \
  tools/binrecon/out/ppcserialport-ppc/published/analysis-reference-ida.json \
  tools/binrecon/out/ppcserialport-ppc/analysis-named.json

PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --reference-analysis tools/binrecon/out/ppcserialport-ppc/analysis-named.json \
  --binary "$REF" \
  --source-dir $LKS \
  --repo-root . \
  --objc-methods \
  --output $RECON/source-map.json

PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/seed_ledger.py \
  $RECON/source-map.json "$REF" $RECON/ledger.json

PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/ppcserialport-ppc/analysis-named.json $RECON/source-map.json

PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
  --binary "$REF" --analysis tools/binrecon/out/ppcserialport-ppc/analysis-named.json
```

`ledger.json` carries 75 entries -- one per function the map accounts for, in address order, 64
with a source path and line and 11 with nulls -- all `unexamined`, all agreement `agreed` on IDA
alone. It is seeded from the map rather than from the analyzer's raw function list, which would
have carried the 210 unnamed jump islands. It is to be changed only through the
`binrecon ledger` CLI, never by hand.

The plan lists `ledger.json` among Task 3's created files but gives no step that produces it, and
no later task reads it. It is seeded here with `seed_ledger.py` -- the tool that exists for
exactly this, and that SCSIServer's plan used at the same point -- so the named deliverable
exists. Recorded as a plan gap rather than a silent omission.
