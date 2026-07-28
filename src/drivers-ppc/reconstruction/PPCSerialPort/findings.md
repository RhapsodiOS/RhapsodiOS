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

---

# Task 4: the five absent C functions

Nothing was compiled for this task either. `make` was not run, there is no PowerPC toolchain
and no host C compiler here. Deleting the duplicate definitions below removes a known compile
error; that is not a claim that the file builds.

## Measured extents -- each function's own `blr`

Task 3 said neither 604 nor 956 should be taken as the measured extent. Measuring it:

| Symbol | Start | Last insn | Body | Trailing islands | Span to next symbol |
| --- | --- | --- | --- | --- | --- |
| `_activatePort` | `0x0bb0` | `blr` at `0x0c78` | 204 | 80 (5 islands) | 284 |
| `_dataLatTOHandler` | `0x1e3c` | `blr` at `0x1e68` | 48 | 48 (3 islands) | 96 |
| `_frameTOHandler` | `0x1e9c` | `blr` at `0x1f04` | 108 | 64 (4 islands) | 172 |
| `_delayTOHandler` | `0x1f48` | `blr` at `0x1fb4` | 112 | 64 (4 islands) | 176 |
| `_heartBeatTOHandler` | `0x1ff8` | `blr` at `0x2078` | 132 | 96 (6 islands) | 228 |

Bodies sum to 604, spans to 956. **The source map's 604 is the measured body extent** -- it
agrees with the `blr` measurement on all five, exactly. The plan's 956 is bodies plus the 352
bytes of trailing jump islands. Task 3 was right that the two figures differ for that reason and
right to refuse to pick one on argument; the measurement settles it in the map's favour.

## Step 1: how the four handlers are registered -- a finding, not the hypothesis

The hypothesis carried into this task was `IOScheduleFunc`. **It is wrong.** All four are Mach
`thread_call` callbacks.

Each handler's address is materialised exactly once in `__TEXT,__text`, by an `lis`/`addi` pair
carrying a `ppc-ha16-32-absolute` / `ppc-lo16-32-absolute` relocation against
`__TEXT,__text + <handler>`. All four pairs sit inside
`-[PPCSerialPort initFromDeviceDescription:]` (`0x80`), within 0x44 bytes of each other:

```
0x03c0  addi  r31, r29, 0x128            ; r31 = &self->portInfo
0x03c4  lis   r3, ha16(_frameTOHandler)      0x03c8  addi r3, r3, lo16(0x1e9c)
0x03cc  mr    r4, r31
0x03d0  bl    _thread_call_allocate  (island 0x5f4)
0x03d4  stw   r3, 0x200(r29)
0x03d8  lis   r3, ha16(_dataLatTOHandler)    0x03dc  addi r3, r3, lo16(0x1e3c)
0x03e0  mr    r4, r31    0x03e4 bl _thread_call_allocate    0x03e8 stw r3, 0x204(r29)
0x03ec  lis   r3, ha16(_delayTOHandler)      0x03f0  addi r3, r3, lo16(0x1f48)
0x03f4  mr    r4, r31    0x03f8 bl _thread_call_allocate    0x03fc stw r3, 0x208(r29)
0x0400  lis   r3, ha16(_heartBeatTOHandler)  0x0404  addi r3, r3, lo16(0x1ff8)
0x0408  mr    r4, r31    0x040c bl _thread_call_allocate    0x0410 stw r3, 0x20c(r29)
```

`_thread_call_allocate` is an undefined symbol reached through a jump island at `0x5f4`; the
island's own HI16/LO16 pair names it. It is declared in this tree at
`src/kernel-7/kern/thread_call.h`:

```c
typedef void  *thread_call_spec_t;
typedef void  *thread_call_t;
typedef void  (*thread_call_func_t)(thread_call_spec_t spec, thread_call_t call);

thread_call_t thread_call_allocate(thread_call_func_t func, thread_call_spec_t spec);
```

and `src/kernel-7/kern/thread_call.c:933` invokes the callout as `(*func)(spec, call)`. So the
**true signature of all four handlers is `void (*)(thread_call_spec_t, thread_call_t)`**, which
after typedef expansion is `void (*)(void *, void *)` -- the form written into the source, so no
kernel header is required for it.

`spec` is `r29 + 0x128`. `r29` is the ObjC `self`, and `initFromDeviceDescription:` at `0xc0`
sets `self->0x294 = self + 0x128` and `self->0x128 = self` -- the port info block lives at
instance offset `0x128` and carries a back-pointer to the instance at its own offset 0. Every C
helper in this file already takes that pointer under the name `PPCSerialPort *self`
(`-[release]` passes `*(basePtr + 0x294)` to `deactivatePort` and `changeState`), so the
handlers receive the same thing the rest of the file does.

Cross-check that closes it: `heartBeatTOHandler` re-arms itself through
`*(void **)(spec + 0xe4)`, and `0x128 + 0xe4 = 0x20c`, which is exactly the slot
`initFromDeviceDescription:` stored *its* `thread_call_t` into. Frame `0x200`, dataLat `0x204`,
delay `0x208`, heartBeat `0x20c` -- port-relative `0xd8`, `0xdc`, `0xe0`, `0xe4`. The registration
site and the body agree on the same pointer.

No handler reads `r4`. The second parameter is unused in all four.

## Step 2: `dataLatTOHandler` (`0x1e3c`, body 48 bytes)

```
1e3c mflr r0 / 1e40 stw r0,8(r1) / 1e44 stwu r1,-0x40(r1)   prologue; no callee-saved regs
1e48 lis  r3, ha16 __TEXT,__cstring+0x574   \  "dataLatTOHandler\n\r"
1e4c addi r3, r3, lo16                      /
1e50 bl   0x1e8c   island -> __TEXT,__text+0x2b6c = _MyIOLog
1e54 bl   0x1e7c   island -> _splpower      (undefined symbol, HI16/LO16 on the island)
1e58 bl   0x1e6c   island -> _splx          (r3 still holds splpower's result)
1e5c addi r1,r1,0x40 / 1e60 lwz r0,8(r1) / 1e64 mtlr r0 / 1e68 blr   epilogue
1e6c..1e9b  three jump islands: _splx, _splpower, _MyIOLog
```

No branches other than the three `bl`s and the final `blr`; no conditional branch at all. r31 is
not saved because the parameters are never read. `splpower`'s result reaches `splx` in r3 without
a spill, which is what a compiler emits for `s = splpower(); splx(s);` with nothing between.

The body raises the priority level and immediately restores it, doing no data-latency work. That
is what the shipped code does; it is recorded, not repaired -- repairing it would require
inventing behaviour, which is the opposite of a measurement.

## Step 3: `frameTOHandler` (`0x1e9c`, body 108 bytes)

```
1e9c mflr r0 / 1ea0-1ea8 stw r29,r30,r31 / 1eac stw r0,8(r1) / 1eb0 stwu r1,-0x50(r1)
1eb4 mr   r31, r3                        r31 = spec = port info block
1eb8 lis/1ebc addi r3 = "frameToHandler\n\r"     (__cstring+0x588)
1ec0 bl   0x1f38  island -> _MyIOLog
1ec4 bl   0x1f28  island -> _splpower
1ec8 mr   r29, r3                        r29 = saved priority level
1ecc li   r0, 0
1ed0 stb  r0, 0x9d(r31)                  port->0x9d = 0
1ed4 li   r3, 0   /  1ed8 li r4, 0  /  1edc mr r5, r31
1ee0 bl   0x1f18  island -> __TEXT,__text+0x3564 = _PPCSerialISR      PPCSerialISR(0,0,port)
1ee4 mr   r3, r29
1ee8 bl   0x1f08  island -> _splx
1eec-1f04 epilogue, blr
1f08..1f47  four jump islands: _splx, _PPCSerialISR, _splpower, _MyIOLog
```

Every instruction accounted for; no conditional branch anywhere in the body. r30 is saved and
restored but never used -- a register-allocation artifact, reproduced by nothing in the C source.

`0x9d` is written as a byte, and `SetStructureDefaults` zeroes the same byte
(`*(unsigned char *)(basePtr + 0x9d) = 0;`, already in our source), which is why it is written as
a byte here too.

The log string is `"frameToHandler\n\r"` -- lower case `o`, while the symbol is `frameTOHandler`.
That is Apple's spelling in `__cstring` at offset `0x588` and is kept verbatim. It is a string
literal, not behaviour, so the "reproduce form, not defects" rule does not bite.

## Step 4: `delayTOHandler` (`0x1f48`, body 112 bytes)

Identical in shape to `frameTOHandler`; the only difference is the three instructions between
`splpower` and `PPCSerialISR`:

```
1f78 lwz    r0, 0xc(r31)
1f7c rlwinm r0, r0, 0, 20, 18        SH=0, MB=20, ME=18 -> wrapping mask, bit 19 clear
1f80 stw    r0, 0xc(r31)
```

`MB=20 > ME=18` is the wrapping form: the mask is all ones except bit 19, and PowerPC bit 19 has
value `1 << (31-19)` = `0x1000`. So the mask is `0xffffefff` and the instruction is
`port->state &= ~0x1000`.

`0xffffefff` is not a bare constant invented here: it is already the established idiom in this
file, at `-[getState]` (`return *(unsigned int *)(basePtr + 0x134) & 0xffffefff;`) and twice in
`-[watchState:mask:]`. Bit `0x1000` is an internal state bit masked out of anything handed to a
client. Written as the literal, matching those three existing sites, rather than as a new name.

All other instructions match `frameTOHandler` one for one, including the unused r30 save. Four
trailing islands: `_splx`, `_PPCSerialISR`, `_splpower`, `_MyIOLog`.

## Step 5: `heartBeatTOHandler` (`0x1ff8`, body 132 bytes)

```
1ff8-200c prologue, saves r29 r30 r31, frame 0x50
2010 mr   r31, r3                       r31 = spec = port info block
2014 lis/2018 addi r3 = "heartBeatTOHandler\n\r"   (__cstring+0x5b0)
201c bl   0x20cc  island -> _MyIOLog
2020 bl   0x20bc  island -> _splpower
2024 mr   r29, r3
2028 li   r3, 0 / 202c li r4, 0 / 2030 mr r5, r31
2034 bl   0x20ac  island -> _PPCSerialISR          PPCSerialISR(0,0,port)
2038 addi r3, r1, 0x38                  hidden struct-return slot on the stack
203c lwz  r4, 0x100(r31)                interval.tv_sec
2040 lwz  r5, 0x104(r31)                interval.tv_nsec
2044 bl   0x209c  island -> _deadline_from_interval
2048 lwz  r3, 0xe4(r31)                 this handler's own thread_call_t
204c lwz  r4, 0x38(r1)                  deadline.tv_sec
2050 lwz  r5, 0x3c(r1)                  deadline.tv_nsec
2054 bl   0x208c  island -> _thread_call_enter_delayed
2058 mr   r3, r29 / 205c bl 0x207c island -> _splx
2060-2078 epilogue, blr
207c..20db  six jump islands: _splx, _thread_call_enter_delayed, _deadline_from_interval,
            _PPCSerialISR, _splpower, _MyIOLog
```

No conditional branch; every instruction accounted for. r30 is again saved and unused.

The r3-as-hidden-pointer plus r4/r5-by-value pattern is a two-word struct returned and passed by
value. `src/kernel-7/kern/thread_call.h` declares
`tvalspec_t deadline_from_interval(tvalspec_t interval)` and
`void thread_call_enter_delayed(thread_call_t call, tvalspec_t deadline)`, and
`src/kernel-7/mach/clock_types.h` defines `struct tvalspec { unsigned int tv_sec; clock_res_t
tv_nsec; }` -- two 32-bit words. The ABI in the disassembly matches those declarations exactly.
The heartbeat interval is therefore the `tvalspec_t` at port offset `0x100`, and
`SetStructureDefaults`'s full-init path zeroing both `0x100` and `0x104` (already in our source)
is that same field.

`0xe4` is this handler's own `thread_call_t`, as shown in Step 1: the handler re-arms itself.

## Step 6: `activatePort` (`0x0bb0`, body 204 bytes)

**The dispatch's premise for this function is wrong, and Task 3's gap table repeats it.**
`activatePort` is **not** called four times in our source. It is not called at all. The four
matches are `deactivatePort`, of which `activatePort` is a substring; a word-boundary grep for
`activatePort` in `PPCSerialPort.m` and `PPCSerialPort.h` returns nothing and exits 1.

So `activatePort` was exactly as unconstrained as the four handlers, and its signature had to
come from the disassembly alone. Recorded because the dispatch offered those call sites as the
thing that made this function "the best constrained" of the five, and they do not exist.

```
0bb0-0bc0 prologue, saves r30 r31, frame 0x40
0bc4 mr    r31, r3                        r31 = port info block
0bc8 lis/0bcc addi r3 = " activatePort\n\r"   (__cstring+0x370, leading space)
0bd0 bl    0xcbc  island -> _MyIOLog
0bd4 lwz   r0, 0xc(r31)                   state
0bd8 andis. r9, r0, 0x4000                r9 = state & 0x40000000, CR0 set
0bdc beq   0xbe8                          not active -> go allocate
0be0 li    r3, 0                          already active
0be4 b     0xc64                          -> return 0
0be8 addi  r30, r31, 0x3c
0bec mr    r3, r30  /  0bf0 lwz r4, 0x64(r31)
0bf4 bl    0xcac  island -> __TEXT,__text+0x2724 = _allocateRingBuffer
0bf8 extsb r3, r3  /  0bfc cmpwi cr1, r3, 0
0c00 bne   cr1, 0xc0c                     succeeded -> second buffer
0c04 mr    r3, r30                        failed: r3 = port + 0x3c
0c08 b     0xc5c                          -> free and fail
0c0c addi  r3, r31, 0x24  /  0c10 lwz r4, 0x54(r31)
0c14 bl    0xcac  -> _allocateRingBuffer
0c18 extsb r3, r3  /  0c1c cmpwi cr1, r3, 0
0c20 beq   cr1, 0xc58                     failed -> free and fail
0c24 mr    r3, r31 / 0c28 li r4, 0
0c2c bl    0xc9c  island -> __TEXT,__text+0x664  = _SetStructureDefaults(port, NO)
0c30 mr    r3, r31 / 0c34 lis r4, 0x4000 / 0c38 lis r5, 0x4000
0c3c bl    0xc8c  island -> __TEXT,__text+0x292c = _changeState(port, 0x40000000, 0x40000000)
0c40 lis/0c44 addi r3 = "End Act State %x\n\r"  (__cstring+0x380)
0c48 lwz   r4, 0xc(r31)  /  0c4c bl 0xcbc -> _MyIOLog
0c50 li    r3, 0  /  0c54 b 0xc64         -> return 0
0c58 addi  r3, r31, 0x3c                  second-buffer failure: r3 = port + 0x3c
0c5c bl    0xc7c  island -> __TEXT,__text+0x26ac = _freeRingBuffer
0c60 li    r3, -0x2be                     = -702
0c64-0c78 epilogue, blr
0c7c..0ccb five jump islands: _freeRingBuffer, _changeState, _SetStructureDefaults,
           _allocateRingBuffer, _MyIOLog
```

Every instruction and every branch is above. Three conditional branches (`beq` at `0xbdc`,
`bne cr1` at `0xc00`, `beq cr1` at `0xc20`) and three unconditional ones (`0xbe4`, `0xc08`,
`0xc54`), all landing on `0xc64` or on the shared failure tail at `0xc5c`.

Signature, from the disassembly: one argument in r3 (the port info block), a value returned in
r3 that is either `0` or `-702`. `-702` is `IO_R_RESOURCE` in
`src/driverkit-3/driverkit/return.h` -- traced to the named constant rather than written as a
bare number. `0x40000000` is `STATE_ACTIVE`, already defined in our `PPCSerialPort.h`. So
`static IOReturn activatePort(PPCSerialPort *self)`, matching the file's convention of naming the
port info block `PPCSerialPort *self`.

`andis. rA,rS,UIMM` computes `rS & (UIMM << 16)`, so the test is `state & 0x40000000` and the
`beq` falls through to the early return when the port is **already** active.

The two failure paths converge on one `freeRingBuffer(port + 0x3c)`. That is exactly what `&&`
compiles to, and it is why the first-buffer failure frees a buffer that was never allocated and
the second-buffer failure frees the first buffer but not the second. That asymmetry is in the
shipped code; it is a consequence of the source's shape, not a separate defect, so reproducing
the shape reproduces it.

### Which queue is which

`0x3c` is the **TX** ring buffer and `0x24` the **RX** ring buffer. Evidence:
`SccHandleRxInterrupt` at `0x395c` does `addi r3, r31, 0x24; bl _AddBytetoQueue` -- received
bytes go into the queue at `0x24`. It then measures `UsedSpaceinQueue(port + 0x24)` against
`port->0x58`, which places the RX stats block at `0x54`: `0x54` size, `0x58` high water, `0x5c`
low water; and the TX stats block at `0x64`: `0x64` size, `0x68` high water, `0x6c` low water.
`SetStructureDefaults` in our source already sets `0x54 = 0x4b0`, `0x58 = 800`, `0x5c = 400`,
`0x64 = 0x4b0`, `0x68 = (0x54 << 1)/3` = 800, `0x6c = 0x58 >> 1` = 400 -- two mirrored triples,
which is what makes the pairing legible.

`activatePort` therefore allocates TX first (`0x3c` with `port->0x64`) and RX second (`0x24` with
`port->0x54`), and the failure tail frees TX.

**The existing comments in `CheckQueues` have this inverted** ("RX Queue (at offset 0x3c)",
"TX Queue (at offset 0x24)"), as does the `0x64` comment in `SetStructureDefaults` ("TX high
water"). Pre-existing, in code this task was not asked to touch, and wrong only in the comments
-- the code itself is offset-based and unaffected. Mentioned, not changed.

### `allocateRingBuffer` gained its second parameter

Both call sites pass a size in r4. `_allocateRingBuffer` at `0x2724` never reads r4 -- it
hard-codes `IOMalloc(0x1000)` and `InitQueue(queue, buf, 0x1000)`. Our source declared it with
one parameter, so writing the call sites faithfully would have been a prototype violation, i.e.
a second compile error introduced while removing the first.

The parameter list was widened to `allocateRingBuffer(void *queueBase, unsigned int bufferSize)`
with the body unchanged, which is what a caller passing an argument the callee ignores means in
C. This is the one edit in this task outside the five functions and the two deletions; it is
recorded here rather than made silently. Uncertainty 3 below covers what was not settled.

## Also fixed: two functions defined twice

`PPCSerialPort.m` defined `SccChannelReset` and `SccCloseChannel` twice each, unconditionally --
a compile error, pre-existing at the branch base `05320f0c` under the old underscored names, and
recorded but left alone by Task 3.

**The later body of each is Apple's. Verified against the disassembly, not assumed from length.**

`_SccChannelReset` at `0x32b8` (76 bytes) reads `lbz r0, 0x148(r3)`, compares against 0 and 1,
and issues `SccWriteReg(self, 9, 0x82)` for channel 0, `SccWriteReg(self, 9, 0x42)` for channel 1,
and nothing at all otherwise (`b 0x32f4` straight to the epilogue). The body at line 2174 is that,
instruction for instruction. The stub at line 2025 wrote `WR9 = 0x80` unconditionally and never
read `0x148` -- it matches neither arm.

`_SccCloseChannel` at `0x2e34` (232 bytes) is a fixed sequence:
`SccDisableInterrupts(self, 6)`, `(self, 5)`, `(self, 4)`, then `SccWriteReg` of
`(1,0) (0xb,0) (0xe,0) (0xf,8) (0,0x10) (0,0x10) (1,1) (9,0x80) (9,0x40)`, then
`MyIOLog("In SccCloseChannel %d\n\r", *(unsigned char *)(self + 0x148))`. The body at line 2136 is
that, in that order, with that string. The stub at line 2036 called
`SccDisableInterrupts(self)` -- one argument to a two-argument function, a third compile error --
and did nothing else.

Both stubs deleted. Their two `IOLog` literals naming the functions under the old underscored
spelling go with them. The `duplicate_candidates` count in the map is now stale at 2 and should
be 0 on Task 5's remap.

## Gate

```
$ PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
    --binary "$REF" --source-dir $LKS
hand-written C symbols: 55
missing definitions   : 0
EXIT=0
```

55 and 0, exit 0, as the task required. Suite: `864 passed, 4 skipped`.

## Uncertainties

1. **What the four handlers are *for* is not established, only what they do.** The registration
   site gives the signature and the argument with certainty. It does not give the trigger: no
   `thread_call_enter` / `thread_call_enter_delayed` for `0x200`, `0x204` or `0x208` (frame,
   dataLat, delay) appears anywhere in `__text` -- only `heartBeatTOHandler` re-arms, and only its
   own. Three of the four thread calls are allocated in `initFromDeviceDescription:`, freed in
   `-[release]`, and never entered. Either the arming code was cut before this build or it is
   reached by a path the relocation table does not expose. To settle it: a caller-side search for
   `thread_call_enter*` against `0x200`/`0x204`/`0x208` in a build that has them, or Apple's
   source. The bodies above do not depend on the answer.

2. **`dataLatTOHandler` does nothing but log and cycle the priority level.** `splx(splpower())`
   with no code between is not a plausible finished function; it is what remains when the guarded
   region has been removed. It is written as measured. It would be a defect to invent the missing
   region, and a different defect to record the function as complete. To settle: Apple's source.

3. **`allocateRingBuffer`'s second parameter has no name in evidence.** The call sites prove an
   argument is passed and the callee proves it is unread, so a parameter exists and its type is
   32-bit; the name `bufferSize` is inferred from the values (`0x4b0` from the two stats blocks)
   and is not measured. The alternative reading -- that Apple's prototype had one parameter and
   both call sites were sloppy pre-prototype calls -- would not survive a prototype being in
   scope, and the file's forward-declaration block shows Apple did use prototypes. Recorded
   rather than resolved.

4. **`#import <mach/clock_types.h>` may not be on this driver's header search path.** The
   `tvalspec_t` in `heartBeatTOHandler` needs a declaration. `<driverkit/generalFuncs.h>` reaches
   `<mach/clock_types.h>` through `<kernserv/clock_timer.h>` -> `<kern/clock.h>`, but only under
   `#if KERNEL_PRIVATE`, so the import was made explicit. The header is guarded
   (`_MACH_CLOCK_TYPES_H_`), so the import is harmless if it was already reachable. Whether
   `src/kernel-7` is on the include path for a `.lksproj` build is untested -- nothing was
   compiled. If it is not, this import is the line that will say so.

5. **r30 is saved and restored, unused, in all three of `frameTOHandler`, `delayTOHandler` and
   `heartBeatTOHandler`.** No C construct in the source produces that; it is a compiler artifact
   of the frame these functions were given. Nothing was written to reproduce it. Noted so a later
   byte-level comparison does not read it as a missing statement.

6. **`splpower` and `splx` are declared locally, as `unsigned int`.** The tree's real
   declarations are `spl_t splpower(void)` / `void splx(spl_t)` in `<kernserv/machine/spl.h>`
   (`src/drivers-ppc/bus/drvPExpert/powermac/interrupt.c` defines them). The file's three
   existing spl call sites already use local declarations of the form
   `extern unsigned int FUN_0000108c(void);` -- those `FUN_` names are `splpower`, `splx` and
   `thread_call_free`, now identified from the islands they name. The new functions follow the
   file's local-extern convention with the real names rather than importing a kernel header or
   renaming the three existing sites, which are out of this task's scope.

## Correction to Task 3's gap table

The row `| 0x0bb0 | _activatePort | 204 | Called 4x, never defined |` is wrong on its last
column. `activatePort` had no call site in our source; the four hits were substrings of
`deactivatePort`. The span, 204, is correct and is confirmed by the `blr` measurement above.
