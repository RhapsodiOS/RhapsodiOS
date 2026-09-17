# drvPCParallel reconstruction divergences

Report pass over Apple's shipped `ParallelPort_reloc`
(`reference_sha256` `D188A4D909005683B0C943C84CD99514C14A84AD1D378425B3B1DB343F1EAAA2`,
45312 bytes, `MH_OBJECT` i386). This document records where our reimplementation in
`src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/`
diverges from that binary.

**The fix pass has landed.** Sections 1 to 6 and the numbered findings below are the
report pass as written, preserved so the evidence behind each finding stays readable.
**Section 8 records what the fix pass did with every one of them**, and the line numbers
quoted in the findings are against the *pre-fix* tree (`IOParallelPort.m` 1070 lines,
`IOParallelPortKern.m` 1360, `IOParallelPort.h` 233, `IOParallelPortKern.h` 119).
`source-map.json` and `ledger.json` have been relined against the rewritten sources.

---

## 1. Coverage and examination depth

The reference partitions into **75 functions**: 73 hand-written plus 2 pieces of
build-generated Kernel Server glue. All 73 are mapped; the 2 glue functions are
`unmapped` by design.

As the report pass left it:

| Depth | Count | What was done |
|---|---|---|
| `assembly-matched` | 29 | Every instruction read, and no divergence found |
| `control-flow-confirmed` | 1 | Block shape and every call target checked; a short stretch not read instruction by instruction |
| `unexamined` | 43 | Every instruction read, **and a divergence found** — these carry a finding below |
| `intentional-mismatch` | 2 | Build-generated glue, not present in source |

After the fix pass: **50 `assembly-matched`, 18 `control-flow-confirmed`,
7 `intentional-mismatch`, 0 `unexamined`.** Section 8 explains the rule used.

**Every one of the 73 mapped functions had its full instruction stream read**, including
the 23-entry jump table behind `-[IOParallelPort msgTypeToIOReturn:]` at 3520 and the
36-entry table behind `_ppstrategy` at 6496, both decoded directly from the binary. The
single exception is `-[IOParallelPort waitForCmdBuf]` (4040), where a stretch between
4070 and 4095 was checked at block-and-call-target level only; it is recorded as
`control-flow-confirmed` rather than `assembly-matched` for that reason.

`unexamined` is used, per the ledger convention, for a function that diverges — not for
one that was skipped. No function in this driver was skipped.

The ObjC metadata was read directly out of the binary (`__OBJC,__class`,
`__meta_class`, `__instance_vars`, `__inst_meth`, `__cls_meth`, `__meth_var_types`,
`__message_refs`, `__cls_refs`, `__class_names`, `__module_info`, `__cstring`), not
inferred from disassembly.

## 2. Stated limitations

- **Two analyzers, not three.** Ghidra is disabled in `tools/binrecon/profiles/parallelport.json`
  because normalization aborts with `Ghidra relocation operand metadata is ambiguous`, a
  known and approved binrecon limitation. There is no `analysis-reference-ghidra.json`,
  `analyzers` has two entries, and every analyzer-disagreement statement in this document
  and in `ledger.json` compares **IDA against angr only**.
- **`InstallPPDev` and `RemovePPDev` are out of the function comparison by design.** They
  are user-space tools built from `PreLoad.tproj` and `PostLoad.tproj` and named in
  `Default.table` as `"Pre-Load"` and `"Post-Load"`. Their sources are deliberately not
  under `--source-dir`, and `IODeviceMaster.m` (2180 lines, under `PreLoad.tproj`) is out
  of scope entirely. Their absence from `source-map.json` is **not** a gap.
- **`parity_check.py` compares symbol names only.** It cannot see the
  `static`-versus-`external` linkage divergences in Finding 54. Task 10 must verify those
  by reading the rebuilt binary's nlist directly — `binrecon.macho.read_macho`, checking
  each symbol's `binding` and `section` — and **not** by parity counts.
- **Our source's `IO_R_*` comments are not to be trusted.** The first pass over this driver
  compared the reference's numeric constants against the `// -726`-style comments beside
  the `IO_R_*` names in our source rather than against what those macros expand to. Several
  of those comments are wrong. The authoritative values are in
  `src/driverkit-3/driverkit/return.h`: `IO_R_IO` is **−714**, `IO_R_BUSY` **−725**,
  `IO_R_TIMEOUT` **−726**, `IO_R_OFFLINE` **−727**, `IO_R_NOT_READY` **−728**; `return.h`
  has no name at all for −738, and −737 is `IO_R_MSG_TOO_LARGE` (which our source
  re-`#define`s locally as `IO_R_NO_PAPER`, `IOParallelPort.m:51-56`). This mistake
  produced three wrong verdicts, now recorded as Findings 57, 58 and 59. **All 30 entries
  originally marked `assembly-matched` were re-audited against `return.h` and every other
  macro their justification rests on; exactly one — `msgTypeToIOReturn:` at 3492 — did not
  hold and has been downgraded to `unexamined`. The remaining 29 were confirmed.**
  Task 10 must fix Findings 57-59 **by value, not by constant name**. *(Done — see the
  resolution notes on Findings 57, 58 and 59; 3492 is `assembly-matched` again.)*

## 3. Analyzer agreement

IDA reports 75 functions. angr reports 187. Every one of IDA's 75 start addresses is also
an angr start address, and **all 75 sizes are identical**; angr's extra 112 entries are
interior addresses that `CFGFast` promotes to function starts because it splits basic
blocks more finely. Call targets agree throughout. The consensus document groups 196
regions as 179 `partial` and 17 `disputed`, all attributable to that same block-splitting.

**The expected angr CFG error list is empty, not non-empty.** The brief predicted
`sel_getUid` indirect-dispatch errors at three sites in `IOParallelPortKern.m`. That
prediction was drawn from *our* source; the analyzers run only against the *reference*,
and the reference contains **no `sel_getUid` calls at all** — it dispatches through
compiler-emitted `__message_refs` entries, of which there are 64. The empty error list is
therefore correct and expected, and the `sel_getUid` idiom is itself a divergence
(Finding 29).

IDA's function extents run 1–3 bytes under the brief's symbol-gap sizes because the
linker pads with `nop`. IDA is authoritative for the partition; the brief's table was used
only to identify functions.

## 4. Answers to the four questions deferred from the table pass

All four concern `-[IOParallelPort initFromDeviceDescription:]` (456, 996 bytes), read
instruction by instruction.

**Q1 — Does the reference call `setLocation:` at all? No.** `setLocation:` does not appear
anywhere in `__message_refs`, and `Location` does not appear in `__cstring`. The reference
neither reads the `Location` key nor sends `setLocation:`. The key in `Default.table` is
consumed by the configuration machinery, not by the driver. `IOParallelPort.m:170-172`
should go. **`setDriverName:` is also absent from `__message_refs`** — the reference reads
the `Driver Name` key and passes the result to **`setDeviceKind:`** (see Finding 18).

**Q2 — Does the reference free the `Minor Device Number` string? Yes, twice.** At 1028 it
sends `[configTable freeString:minorDevStr]` on the success path, and at 828 it sends the
same on the controller-not-found path. The reference has **no `NULL` fallback** — it
passes the `valueForStringKey:` result straight into an inlined `strcmp` against `"0"`
with no null check, so nothing guards against a string literal reaching `freeString:`.
Our `NULL`-to-`"0"` fallback at `IOParallelPort.m:104-106` therefore creates a hazard the
reference does not have: if the key is missing, our code would pass the read-only literal
`"0"` to `freeString:`.

**Q3 — Does the reference call `[deviceDescription name]` at all? No.** The `name`
selector is in `__message_refs` (16536), but its only use is in `_IOParallelPortThread` at
5125, where it is `[self name]` feeding the `%s: msg_receive returned %d\n` log. There is
no `name` send on the device description anywhere in `initFromDeviceDescription:`. Both
`IOParallelPort.m:100` and `:142` go.

**Q4 — Is freeing a `[deviceDescription name]` result through `[configTable freeString:]`
correct? No.** `freeString:` releases a string vended by `[configTable valueForStringKey:]`.
`[deviceDescription name]` is not such a string. The reference only ever passes
`freeString:` a `valueForStringKey:` result — the `Minor Device Number` string and the
`Driver Name` string. The pairing at `IOParallelPort.m:142` is wrong independently of
Q3, and since Q3 removes the fetch, the fix is to free the `Minor Device Number` string
there instead.

## 5. The three external-symbol underscore verdicts

Each was checked separately against our source's spelling. **All three are correct.**

| Reference symbol | Implied C name | Our spelling | Verdict |
|---|---|---|---|
| `__strobeChar` (4232, `global`) | `_strobeChar` | `_strobeChar` — `IOParallelPortKern.m:1275`, `IOParallelPortKern.h:109` | correct |
| `_IOParallelPortThread` (4512, `global`) | `IOParallelPortThread` | `IOParallelPortThread` — `IOParallelPortKern.m:1088`, `IOParallelPortKern.h:108` | correct |
| `_IOParallelPortInterruptHandler` (5240, `global`) | `IOParallelPortInterruptHandler` | `IOParallelPortInterruptHandler` — `IOParallelPortKern.m:1003`, `IOParallelPortKern.h:107` | correct |

No underscore-depth fix is needed. (The linkage of these three, and of the seven `cdevsw`
entry points, is a separate matter — see Finding 54.)

## 6. Does the superclass / return-polarity pattern repeat? Yes, on both counts.

It does, and the superclass divergence is the largest finding in this driver.

- **Superclass:** the reference's `IOParallelPort` derives from **`IODirectDevice`**
  (`instance_size` 404, first ivar at 296). Ours derives from `IODevice`. Finding 1.
- **Return polarity:** five methods have a different return type, and one of them is a
  true polarity inversion — `probeForController` returns `BOOL` (1 = found) in the
  reference and `IOReturn` (0 = success) in ours, so the caller's test is inverted.
  Findings 5–9.
- **Extra compiled class:** `__OBJC,__class` is 120 bytes = **exactly 3 classes**
  (`IOParallelPort`, `ParallelPortVersion`, `ParallelPortKernelServerInstance`), which is
  what our sources plus the Kernel Server glue should emit. No extra class is expected
  here — but `__inst_meth` is 752 bytes = `8 + 62*12`, i.e. **62 instance methods**, and
  our class declares 63. Finding 16.

---

## Findings

### Class and layout

**Finding 1 — superclass is `IODevice` where the reference has `IODirectDevice`.**
`IOParallelPort.h:88`. Reference `__OBJC,__class[0]`: `super_class = IODirectDevice`,
`instance_size = 404`, first ivar at offset 296. This is the root cause of several
downstream findings: `attachInterruptPort`, `interruptPort`, `enableAllInterrupts` and
`getHandler:level:argument:forInterrupt:` are `IODirectDevice` API, and the reference's
`initFromDeviceDescription:` relies on `IODirectDevice`'s own implementation to attach the
interrupt port (Finding 25). Largest single finding.

**Finding 2 — `-[IOParallelPort _waitForDevice:isReady:]` is a stub.**
`IOParallelPort.m:868-879`. The reference (0, 112 bytes) implements the driver's core
wait: poll the status register until `(status & 0xB8) == 0x98`, bounded by
`busyMaxRetries` with `IOSleep(busyRetryInterval)` between attempts, looping indefinitely
when the `waitForever` argument is 1; set `*isReady` to 1 if the pattern was seen and 0
otherwise; return whether it ever slept. Ours sets `*isReady = NO` and returns.

**Finding 3 — the ivar block does not match.** 33 ivars in `IOParallelPort.h:89-132`
against the reference's 27, with different names, types and offsets. Reference ivars, read
from `__instance_vars`:

| Offset | Reference | Type | Ours |
|---|---|---|---|
| 0x128 | `inUse` | `c` | `inUse` |
| 0x129 | `writing` | `c` | *(absent — ours has `initialized`)* |
| 0x12c | `configRegister` | `*` | `configReg` (`unsigned int`) |
| 0x130 | `dataRegister` | `*` | `dataReg` (`unsigned int`) |
| 0x134 | `dataRegisterData` | `C` | *(absent)* |
| 0x138 | `statusRegister` | `*` | `statusReg` (`unsigned int`) |
| 0x13c | `controlRegister` | `*` | `controlReg` (`unsigned int`) |
| 0x140 | `controlRegisterDefaults` | `C` | `controlRegDefaults` |
| 0x144 | `busyMaxRetries` | `I` | `busyMaxRetries` |
| 0x148 | `busyRetryInterval` | `I` | `busyRetryInterval` |
| 0x14c | `autofeedOutput` | `i` | `autofeedOutput` (`BOOL`) |
| 0x150 | `IOThreadDelay` | `I` | `ioThreadDelay` |
| 0x154 | `intHandlerDelay` | `I` | `intHandlerDelay` |
| 0x158 | `minPhys` | `I` | `minPhys` |
| 0x15c | `blockSize` | `I` | `blockSize` |
| 0x160 | `ioTimeout` | `i` | `ioTimeout` (`unsigned int`) |
| 0x164 | `ioQueueLock` | `@` | `cmdBufLock` |
| 0x168 | `ioQueue` | `{?="next"^{queue_entry}"prev"^{queue_entry}}` | `cmdBufHead` + `cmdBufTail` |
| 0x170 | `ioTaskThread` | `^v` | `threadID` (`unsigned int`) |
| 0x174 | `physbuf` | `^{buf}` | `physbuf` (`void *`) |
| 0x178 | `interruptMessage` | `^{?=b24b8Iiiii}` | `interruptMessage` (`unsigned int`) — ours puts the allocation in `cmdBuf` |
| 0x17c | `majorDevNum` | `i` | `majorDevNum` |
| 0x180 | `minorDevNum` | `i` | `minorDevNum` |
| 0x184 | `dataBuffer` | `^v` | `dataBuffer` |
| 0x188 | `sizeLock` | `@` | *(absent — see Finding 4)* |
| 0x18c | `waitForever` | `c` | `waitForever` |
| 0x190 | `statusWord` | `I` | `statusWord` (`unsigned short`) |

Ours additionally declares `portRange`, `lockSize`, `unlockSize`, `cmdBuf`, `physbufArg`,
`interruptPortHandle`, `initialized` and `controlRegContents`, none of which the reference
has. `lockSize` and `unlockSize` are especially bad: they are declared as `unsigned int`
ivars while also being method names, and the reference has neither ivar.

**Finding 4 — `sizeLock` is missing, and `lockSize`/`unlockSize` lock the wrong object.**
`IOParallelPort.m:692-704`. The reference allocates an `NXLock` into `sizeLock` (0x188)
during init and sends it `lock`/`unlock` from `-lockSize`/`-unlockSize` (3708, 3744).
Ours sends `lock`/`unlock` to `interruptPortHandle`, which is a Mach port handle and not a
lock. `__cls_refs` in the reference carries both `NXConditionLock` and `NXLock`,
confirming two distinct lock classes.

**Finding 16 — one extra instance method: `-interruptPort`.**
`IOParallelPort.h:207`, `IOParallelPort.m:842-845`. `__inst_meth` is 752 bytes = 62
methods; our class declares 63. `interruptPort` is inherited from `IODirectDevice` and the
reference does not override it, though it does *send* it (`__message_refs` 16532, used
from `_IOParallelPortThread`).

### Return type and polarity

**Finding 5 — `probeForController` polarity is inverted.** `IOParallelPort.m:242`.
Reference type `c8@8:12`; the body (1452) returns `1` when both readback patterns verify
and `0` otherwise. Ours returns `IOReturn` — `IO_R_SUCCESS` (0) on success — and the
caller at `:140` tests `!= IO_R_SUCCESS`. Both the method and its caller must change
together.

**Finding 6 — `free` returns `void`; the reference returns `id`.** `IOParallelPort.m:372`.
Reference type `@8@8:12`; the body (1740) leaves `[super free]`'s result in `eax`.

**Finding 7 — `printerInit` returns `void`; the reference returns `IOReturn`.**
`IOParallelPort.m:355`. Reference type `i8@8:12`; the body (3132) ends `xor eax, eax`.

**Finding 8 — `cmdBufExec:` returns `IOReturn`; the reference returns `void`.**
`IOParallelPort.m:917`. Reference type `v12@8:12^{?=@i*ic{?=^{queue_entry}^{queue_entry}}}16`.

**Finding 9 — `_waitForDevice:isReady:` returns `void`; the reference returns `BOOL`.**
`IOParallelPort.m:868`. Reference type `c16@8:12c16^c20`. `_IOParallelPortThread` ignores
the result, so this is a signature fix rather than a behavioural one.

### Ivar and argument types

**Finding 10 — `statusWord` is `unsigned short`; the reference is `unsigned int`.**
`IOParallelPort.h:99`, `IOParallelPort.m:489`, `:494`. Reference type `I` on the ivar and
`I8@8:12` / `@12@8:12I16` on the accessors; `-initDevice` at 261 and 372 manipulates 0x190
with 32-bit `and`/`mov`.

**Finding 11 — `autofeedOutput` is `BOOL`; the reference is `int`.**
`IOParallelPort.h:101`, `IOParallelPort.m:620`, `:625`. Reference ivar type `i`, accessors
`i8@8:12` / `@12@8:12i16`, and the getter (2664) emits a full 32-bit load.

**Finding 12 — `ioTimeout` is `unsigned int`; the reference is signed `int`.**
`IOParallelPort.h:115`, `IOParallelPort.m:779`, `:784`. Reference ivar `i`, accessors
`i8@8:12` / `@12@8:12i16`. This matters: `_IOParallelPortThread` compares the elapsed time
against it with a signed `jl` at 5106.

**Finding 13 — the four register accessors are typed `unsigned int`; the reference types
them `const char *`.** `IOParallelPort.m:424`, `:429`, `:435`, `:440`, `:446`, `:451`,
`:457`, `:462` and the matching ivars. Reference encodings `r*8@8:12` and `@12@8:12r*16`,
ivar type `*`. The emitted code is identical 32-bit loads and stores; only the type
encoding in `__meth_var_types` differs.

**Finding 14 — `physbuf`/`setPhysbuf:` are typed `void *`; the reference uses
`struct buf *`.** `IOParallelPort.m:742`, `:747`. Reference encoding
`^{buf={?=^{buf}^^{buf}}…}8@8:12`. This is load-bearing: `_IOParallelPortInterruptHandler`
reads `physbuf->b_flags` at offset 0x24 to decide read versus write.

**Finding 15 — `interruptMessage`/`setInterruptMessage:` are typed `unsigned int`; the
reference uses a message-struct pointer, and the ivar holds the 8192-byte allocation.**
`IOParallelPort.h:127`, `IOParallelPort.m:831`, `:836`. Reference encoding
`^{?=b24b8Iiiii}8@8:12`, and `initFromDeviceDescription:` stores `IOMalloc(0x2000)` into
0x178 at 1271. Ours declares `interruptMessage` as an integer, puts the allocation in a
separate `cmdBuf` ivar, and assigns `0x54e` to `interruptMessage` at `:215`.

**Finding 17 — `getHandler:…` passes the wrong argument, with the wrong type.**
`IOParallelPort.m:847-862`. The reference (1692) writes `[self+0x180]`, the **minor device
number**, through `*arg` — which is exactly the third parameter
`IOParallelPortInterruptHandler(param1, param2, portNum)` expects. Ours writes
`physbufArg`, an ivar the reference does not have. The argument is also typed
`unsigned int *` (`^I`) in the reference, not `void **`.

### `initFromDeviceDescription:` (456)

**Finding 18 — `setDriverName:` where the reference sends `setDeviceKind:`.**
`IOParallelPort.m:166`. At 1012-1023 the reference passes the `Driver Name` value to
`setDeviceKind:`. `setDriverName:` is absent from `__message_refs` entirely.

**Finding 19 — the `Location` key read and `setLocation:` send do not exist in the
reference.** `IOParallelPort.m:170-172`. See Q1.

**Finding 20 — the wrong string is freed on the controller-not-found path.**
`IOParallelPort.m:142`. The reference at 828-843 frees the **`Minor Device Number`**
string. See Q2 and Q4.

**Finding 21 — `[deviceDescription name]` is never sent by the reference.**
`IOParallelPort.m:100`. See Q3.

**Finding 22 — `setMinorDevNum:` is never sent.** The reference sends
`[self setMinorDevNum:0]` at 1068-1080, using the zero it established at 624. Our
`initFromDeviceDescription:` leaves `minorDevNum` untouched, so
`getIntValues:forParameter:count:` and every `pp_softc` index derived from it read
uninitialised memory.

**Finding 23 — `IOThreadDelay` and `intHandlerDelay` are never initialised.** The
reference stores `1` into both (0x150 and 0x154) at 1118 and 1128. Ours initialises
neither, so `_strobeChar`'s `IODelay` argument and the interrupt handler's delay are
uninitialised.

**Finding 24 — `cdevsw` slot 8 is `enodev`; the reference passes `seltrue`.**
`IOParallelPort.m:148-151`. The reference pushes, in argument order:
`ppopen, ppclose, enodev, ppwrite, ppioctl, enodev, enodev, seltrue, enodev, enodev, enodev`.
Ours has `enodev` in position 8. Everything else, including the deliberate `enodev` in the
read slot, matches.

**Finding 25 — the explicit interrupt-attach block has no counterpart.**
`IOParallelPort.m:205-215`. The reference calls neither `[self attachInterruptPort]` nor
`[self interruptPort]` nor `[self setInterruptMessage:0x54e]` from init; `IODirectDevice`'s
own `initFromDeviceDescription:` attaches the port, which triggers our overridden
`-attachInterruptPort` (1616) and hence `IOForkThread`. This follows directly from
Finding 1. The reference's init goes straight from the `NXLock` setup to
`[self enableAllInterrupts]` at 1358.

**Finding 26 — `dataBuffer` is allocated from `blockSize`; the reference uses `minPhys`.**
`IOParallelPort.m:202`. The reference at 1277 loads `[self+0x158]` (`minPhys`). Both are
`0x200` at this point, so there is no behavioural difference at init — but the same
divergence in `-free` and the two size setters is behavioural.

**Finding 27 — the controller-not-found message text differs.**
`IOParallelPort.m:141` reads `IOParallelPort: parallel port at 0x%x not found`; the
reference `__cstring` at 7608 reads
`IOParallelPort not allocated: controller not detected at address 0x%x\n`. The reference
also passes the address as a **16-bit** value (`movzx eax, word ptr [ebx]` at 814).

**Finding 28 — `objc_getClass("NXConditionLock")` emits a `__cstring` literal the
reference does not have.** `IOParallelPort.m:191` and `:896`. The reference resolves the
class through a compiler-emitted `__cls_refs` entry (16640), which puts the name in
`__class_names`, not `__cstring`. Our two `objc_getClass` calls put `NXConditionLock` into
`__cstring`, where `parity_check.py` will see it.

**Finding 29 — 37 distinct `sel_getUid("…")` literals emit `__cstring` entries the
reference does not have.** Throughout `IOParallelPortKern.m`: 55 call sites naming **37
distinct** selector strings, all in that one file (`IOParallelPort.m` has none). Counting
every distinct string literal in our two sources and discarding the two `#import` header
names, which emit nothing, our `__cstring` would carry **54** entries — those 37 selector
strings plus 17 others — against the reference's **15**. The reference's 476-byte
`__cstring` contains exactly those fifteen entries and **not one is a selector**; every message
send in the reference goes through one of the 64 `__message_refs` entries. The table pass
recorded that `IOThreadDelay` appearing as both a selector string and a method name was
"consistent with it being `__OBJC` material on both sides" — that conclusion was wrong.
`sel_getUid("IOThreadDelay")` at `IOParallelPortKern.m:837` puts the literal in
`__cstring`. The same applies to every other `sel_getUid` call site. Fixing this means
declaring the receiver's type and using ordinary message-send syntax, which also removes
Finding 51's incidental differences.

The full `__cstring` of the reference, for comparison:
`Minor Device Number`, `0`, `Nonzero Minor Device Number - only one dev this version\n`,
`IOParallelPort not allocated: too many register ranges\n`,
`IOParallelPort not allocated: register range is invalid\n`,
`IOParallelPort not allocated: controller not detected at address 0x%x\n`,
`IOParallelPort: could not add to device switch\n`, `pp`, `%s%s`, `Driver Name`,
`IOParallelPort: could not enable interrupts\n`,
`IOParallelPort: could not register device\n`, `IOMajorDevice`, `IOMinorDevice`,
`%s: msg_receive returned %d\n`.

Ours has `Minor Device Number` and `0` present, as the table pass required, and neither
`ParallelPort0` nor `pp0` appears as a literal — `pp` and `%s%s` are used exactly as the
reference does. The only `__cstring` divergences are Finding 27's message text,
Finding 19's `Location`, Finding 28 and Finding 29.

### Behaviour

**Finding 30 — `writeToPort` sets `inUse`; the reference sets `writing`.**
`IOParallelPort.m:517`, `:583`. The reference (3212) writes `1` then `0` to offset
**0x129** (`writing`), not 0x128 (`inUse`). `inUse` is owned by `ppopen`/`ppclose`, and
`_IOParallelPortInterruptHandler` gates on `writing` at 5318 — so with our version the
handler's gate is driven by the wrong flag.

**Finding 31 — `writeToPort` returns the error code where the reference returns 0.**
`IOParallelPort.m:536`. The reference initialises its return value to `0` at 3268 (`xor
edi, edi`) and only assigns `cmdBuffer->returnCode` in the **−714** arm (3403) and the
default arm. For **−726**, **−738**, **−737** and **−725** it sets the status bit and
**returns 0**. Ours assigns `returnCode = cmdBuffer->returnCode` before the switch and so
returns the error. This changes what `_ppstrategy` sees and hence the `errno` the caller
gets. (The arms are stated by value deliberately — our source's case labels do not select
the arms their names suggest; see Finding 59.)

**Finding 32 — the two size setters guard on each other's ivar.**
`IOParallelPort.m:669` and `:714`. The reference's `-setBlockSize:` (3024) compares the
new size against `blockSize` (0x15c); ours compares it against `unlockSize`. The
reference's `-setMinPhys:` (2900) compares against `minPhys` (0x158); ours compares
against `blockSize`. Both bodies otherwise match, including that both write the new size
to **both** 0x158 and 0x15c and reallocate from 0x158.

**Finding 33 — `-free` frees `interruptPortHandle`; the reference frees `sizeLock`.**
`IOParallelPort.m:405-414`. The reference (1902-1935) sends `free` to `sizeLock` (0x188)
and then to `ioQueueLock` (0x164), both unconditionally, and never frees an interrupt
port. Ours frees `interruptPortHandle` and `cmdBufLock`.

**Finding 34 — four `NULL` guards the reference does not have.** `IOParallelPort.m:379`
(`cmdBufAlloc` result in `-free`), `:674` and `:719` (`dataBuffer` before `IOFree` in the
size setters), `:892` (`IOMalloc` result in `-cmdBufAlloc`), plus `:387`, `:393`, `:399`,
`:405`, `:411`. The reference checks `physbuf`, `interruptMessage` and `dataBuffer` before
`IOFree` in `-free` but nothing else. Ours is safer; recorded so Task 10 makes a deliberate
choice rather than an accidental one.

**Finding 35 — `-free` sizes the `dataBuffer` free from `blockSize`; the reference uses
`minPhys`.** `IOParallelPort.m:400`. The reference loads `[esi+0x158]` at 1880. Combined
with Finding 32 these can diverge at runtime.

**Finding 36 — `pp_softc` has the wrong shape.** The reference's `_pp_softc` is a
**12-byte** `static` array in `__DATA,__data` at 8192 with **one** element:

```c
static struct {
    id             device;   /* +0 */
    int            count;    /* +4 */
    unsigned char *data;     /* +8 */
} pp_softc[1];
```

Every access is `pp_softc[minor(dev) * 3]` in word units — `lea eax,[eax+eax*2]` then
`ds:_pp_softc[eax*4]` — seen identically in `ppopen`, `ppclose`, `ppread`, `ppwrite`,
`ppioctl`, `ppstrategy`, `ppminphys`, `_strobeChar` and the interrupt handler. One element
is consistent with the `only one dev this version` message. Ours instead has
`pp_port_controls[4]`, `pp_bytes_remaining[4]` and `pp_data_buffers[4]`
(`IOParallelPortKern.m:139-141`) as three separate arrays, and `pp_data_buffers` carries an
extra level of indirection (`unsigned char **`, dereferenced twice) because `ppstrategy`
stores the *address* of `bp->b_un.b_addr` rather than its value (Finding 43).

**Finding 37 — `pp_softc` is defined twice with conflicting linkage.**
`IOParallelPort.m:51` declares `static void *pp_softc = NULL;` and
`IOParallelPortKern.m:526` declares `void *pp_softc = NULL;`, with
`IOParallelPortKern.h:115` declaring it `extern`. The reference has exactly one, `local`
(i.e. `static`) in `__data`. `IOParallelPort.m`'s assignment at `:185` therefore writes to
a file-scope object that `IOParallelPortKern.m` never reads.

**Finding 38 — seventeen invented `pp_kern_*` functions.**
`IOParallelPortKern.m:197-520` defines `pp_kern_init`, `pp_kern_probe`, `pp_kern_reset`,
`pp_kern_set_mode`, `pp_kern_get_mode`, `pp_kern_read_data`, `pp_kern_write_data`,
`pp_kern_read_status`, `pp_kern_read_control`, `pp_kern_write_control`,
`pp_kern_get_state`, `pp_kern_set_state`, `pp_kern_delay`, `pp_kern_wait_busy`,
`pp_kern_strobe`, `pp_kern_enable_interrupts` and `pp_kern_disable_interrupts`, declared in
`IOParallelPortKern.h:79-95`. **None of them exists in the reference**, and nothing in our
own driver calls any of them except `pp_kern_init`/`pp_kern_reset`/`pp_kern_delay` calling
each other. The supporting statics `pp_base_addrs`, `pp_modes` and `pp_strobe_count` are
invented alongside them. They are dead weight that will show up as extra symbols in any
parity comparison.

**Finding 39 — `ppopen` is a stub.** `IOParallelPortKern.m:530-538`. The reference (5520):

```c
port = pp_softc[minor(dev)].device;
if ([port isInUse]) return EBUSY;            /* 16 */
r = [port initDevice];
if (r != 0 && r != -725 && r != -726 && r != -737 && r != -738) return EIO;  /* 5 */
[port setInUse:YES];
return 0;
```

The acceptance test is written as two signed range comparisons: `r > -725` requires
`r == 0`; `r <= -725` accepts `[-726,-725]` and `[-738,-737]` and rejects everything else.
Ours returns 0 unconditionally.

**Finding 40 — `ppminphys` is declared `void` and mutates the buffer; the reference returns
a value and does not.** `IOParallelPortKern.m:966-997`. The reference (6252) is
`unsigned int ppminphys(struct buf *bp)` returning `MIN(bp->b_bcount, [port minPhys])`;
there is no store to `b_bcount` anywhere in the body. Ours writes
`buf->count = minPhysValue`.

**Finding 41 — `ppstrategy` is declared `void`; the reference returns `int`.**
`IOParallelPortKern.m:890`. The reference returns `-1` on every error path (6346) and `0`
on success (6697).

**Finding 42 — `ppstrategy` maps the paper-out and offline codes to the wrong `errno`.**
`IOParallelPortKern.m:947-950`. The reference's jump table at 6496 sends `-738` and `-737`
to a store of **`0x53` (83)**, `-726` to `0x3C` (60), `-725` to `0x10` (16), and the
default to `0x05` (5). Ours writes `EIO` for both the `-737`/`-738` case and the default,
so both become 5. The comments in our source already say `0x53 (83)` and `0x05 (5)` — the
code does not match its own comment.

**Finding 43 — `ppstrategy` stores the address of the buffer pointer, not its value.**
`IOParallelPortKern.m:919`. The reference at 6396-6399 copies `bp->b_un.b_addr`
(offset 0x3c) **by value** into `pp_softc[minor].data`, and `_strobeChar` and the interrupt
handler then advance that private copy. Ours stores `&buf->dataPtr`, which is why
`pp_data_buffers` is `unsigned char **` and why every use needs a double dereference — and
it means our code advances the caller's `b_un.b_addr` in place.

**Finding 44 — the interrupt handler's SELECT-bit arm is inverted.**
`IOParallelPortKern.m:1039-1044`. The reference (5352-5367):

```
msg = 0x232336;
if (status & 0x10) goto send;   /* SELECT set   -> 0x232336 */
msg = 0x232339;                 /* SELECT clear -> 0x232339 */
```

Ours assigns `0x232336` when SELECT is **clear** and `0x232339` when it is set — exactly
the opposite. Because the reference's `msgTypeToIOReturn:` maps `0x232336` to **−714** and
`0x232339` to **−738**, our version reports −714 when the printer goes offline and −738
when it is selected. The `#define` names compound the confusion at both ends:
`IOParallelPortKern.m:59` calls `0x232336` `PP_INT_MSG_OFFLINE`, and `IOParallelPort.h:71`
calls the same code `PP_MSG_TIMEOUT`, while what the reference actually returns for it is
−714 — which `return.h` names `IO_R_IO`, not `IO_R_TIMEOUT` (−726). Likewise −738, the
code for `0x232339`, has no `IO_R_*` name in `return.h` at all; our source's
`IO_R_OFFLINE` is −727. Task 10 must reproduce these codes **by value**. The rest of the
decode — the `(status & 0x28) == 0x08` arm, the busy test and the paper-out test —
matches.

**Finding 45 — the interrupt handler's read path stores before advancing; the reference
advances first.** `IOParallelPortKern.m:1065-1068`. The reference at 5454-5476 does
`inc data; dec count; *data = inb(dataReg)` — it increments the pointer and *then* stores,
i.e. `*++p`. Ours does `*p = byte; p++`. The reference also tests the count for equality
with zero (`jz`) here, where the write path tests `<= 0` (`jle`).

**Finding 46 — `_IOParallelPortThread` mis-splits a nested message send, twice.**
`IOParallelPortKern.m:1138-1142` and `:1215-1219`. The reference source is a single
statement:

```c
[self _waitForDevice:[self waitForever] isReady:&ready];
```

The compiler pushes `&ready` first (4616), then evaluates `[self waitForever]`
(4620-4628), sign-extends its result (4636), pushes it, and calls
`_waitForDevice:isReady:`. Our source read that argument-evaluation order as program
structure and produced:

```c
shouldWait = (char)objc_msgSend(portObject, sel_getUid("waitForever"), &deviceReady);
objc_msgSend(portObject, sel_getUid("_waitForDevice:isReady:"), (int)shouldWait);
```

which passes a spurious argument to `waitForever` and **omits the `isReady:` argument
entirely**, so `deviceReady` is never written and the `if (!deviceReady)` test that follows
reads an uninitialised local. This occurs at both sites.

**Finding 47 — the first not-ready decode in `_IOParallelPortThread` has a different
shape.** `IOParallelPortKern.m:1150-1165`. The reference's first decode (4662-4747) is:

```
if (!(status & 0x08)) {
    errorFlag = 1;
    if (status & 0x20)      returnCode = -737;
    else if (status & 0x10) { errorFlag = 0; returnCode = -726; }
    else                    returnCode = -738;
} else {
    errorFlag = 0;
    returnCode = (status & 0x20) ? -737 : -726;
}
```

It never yields `-725`, and it clears `errorFlag` in the SELECT-set case. Our version uses
the shape of the reference's *second* decode for both sites. The second decode
(5040-5091) — `errorFlag = 0; if (!(status & 8)) errorFlag = 1;` then paper-out /
offline / signed-negative / busy — **does** match ours exactly, including the `-725` arm.

**Finding 48 — `_IOParallelPortThread` discards `[self interruptMessage]` and uses a stack
local.** `IOParallelPortKern.m:1108-1109` and the `pp_interrupt_msg_t interruptMsg` local
at `:1091`. The reference (4524-4537) saves the returned pointer and passes *that buffer*
— the 8192-byte `IOMalloc` from init — to `msg_receive`. Ours calls the accessor for its
side effect and then hands `msg_receive` a small stack struct, so a message larger than
that struct would overrun it. The receive option is `0x500` in both — the only `push`
of that shape in the reference's `__text`, at 4929 — which is
`RCV_TIMEOUT|RCV_INTERRUPT`, **not** `RCV_LARGE` (0x1000); our macro is now named
`MSG_OPTION_RCV_TIMEOUT_INTR` accordingly. Everything else in the loop matches,
including the `0x2000` message size, the 500 ms / `ioTimeout` clamp, the `-207` and `-203`
arms, the `IOLog` argument order and the `msgTypeToIOReturn:` tail.

**Finding 49 — `ppwrite` continues into the write where the reference returns 0.**
`IOParallelPortKern.m:647-660`. The reference (5924-5963) returns **0 immediately, without
writing**, when `initDevice` yields `-725`, `-726`, `-737` or `-738`, and returns `EIO`
for anything else nonzero. Ours treats those four as "continue". Our range tests are also
wrong on both ends: `[-726, -724]` admits `-724`, and `[-739, -736]` admits `-739` and
`-736`; the reference admits exactly `[-726,-725]` and `[-738,-737]`. Ours additionally
returns `ENOMEM` on a failed `IOMalloc`, which the reference does not check. The rest of
`ppwrite` — the `uio_segflg` test, the `0x8000` clamp, `copyin`, the iovec save/restore,
the `IOFree` and the `uio_resid` adjustment — matches instruction for instruction.

**Finding 50 — `pp_strobe_count` is invented.** `IOParallelPortKern.m:144`, incremented at
`:1315`, `:1324` and `:1333`. There is no such counter in the reference. The
`lock inc ds:_xxx_102` instructions visible after each `outb` come from the `outb()` macro
in `<driverkit/i386/ioPorts.h>` and correspond to the three `_xxx.NNN` counters in
`__bss`, not to anything in the source.

**Finding 51 — bounds and `NULL` checks the reference does not have.** Every
`portNum >= PP_KERN_MAX_PORTS` test in `IOParallelPortKern.m` (`:549`, `:576`, `:629`,
`:748`, `:901`, `:978`, `:1013`, `:1284`) and most of the accompanying `NULL` tests. The
reference bounds-checks nothing — it relies on `pp_softc` having one element and on
`initFromDeviceDescription:` refusing any nonzero minor number. It does `NULL`-check the
device pointer in `ppread`, `ppwrite`, `ppioctl` and `ppstrategy`, but not in `ppopen`,
`ppclose`, `ppminphys`, `_strobeChar` or the interrupt handler. Recorded so Task 10 keeps
them deliberately rather than by accident; they are defensible, but they change the
function sizes.

**Finding 52 — `initDevice` sets an `initialized` ivar the reference does not have.**
`IOParallelPort.m:343`. The reference (358-365) only sets bit 0 of `statusWord`;
`-isInitialized` (2788) reads that bit and nothing else.

**Finding 53 — the control byte is built from the read-back value; the reference builds it
from uninitialised stack.** `IOParallelPort.m:252`, `:263`, `:285-288`. In both
`probeForController` (1472-1497, 1540-1560) and `initDevice` (122-160) the reference reads
the control register into one stack slot and then constructs the pattern with
`and`/`or` on a *different, never-initialised* slot, leaving bits 6 and 7 as garbage. Our
versions start from the value just read and use single-step masks
(`(v & 0xDE) | 0x1E`, `(v & 0xE5) | 0x04`). For bits 0-5 the results agree in
`initDevice`; in `probeForController` they do not — the reference clears bits 0 and 5 in
the second pattern where ours preserves them. Our behaviour is arguably better; it is
recorded because it is a real difference and because reproducing the reference exactly
would mean reproducing a bug.

### `IO_R_*` constant values

The three findings below share one cause: our source names return codes with `IO_R_*`
macros whose comments claim values the macros do not have. `src/driverkit-3/driverkit/return.h`
gives `IO_R_IO` −714, `IO_R_BUSY` −725, `IO_R_TIMEOUT` −726, `IO_R_OFFLINE` −727,
`IO_R_NOT_READY` −728, `IO_R_MSG_TOO_LARGE` −737; there is no macro for −738.
`IOParallelPort.m:51-56` adds `IO_R_NO_PAPER (-737)` locally, which is correct.
**Task 10 must fix these by value. Fixing them by constant name would target the wrong
arms, because the names in our source are wrong.**

**All three are now fixed.** `IOParallelPort.m:43-56` keeps the local `IO_R_NO_PAPER`
(−737) and adds a local `IO_R_PRINTER_OFFLINE` (−738) — deliberately *not* spelled
`IO_R_OFFLINE`, which `return.h` already owns at −727. The three arms that wanted a stock
code now name the macro that actually holds it: −726 is `IO_R_TIMEOUT`, −714 is `IO_R_IO`.
`IO_R_OFFLINE` and `IO_R_NOT_READY` no longer appear anywhere in the driver. Every
`IO_R_*` in the file was re-checked by expanding it against `return.h` rather than by
reading the comment beside it, and each comment now states the expansion.

**Finding 57 — four of `msgTypeToIOReturn:`'s seven arms return the wrong value.**
`IOParallelPort.m:1044-1067`. The reference (3492, jump table at 3520, all 23 entries
decoded from the binary) dispatches on `msgType - 0x232323` with a range check against
0x16. Its arms and ours:

| `msgType` | Source case | Reference returns | Our source names | Which compiles to | Verdict |
|---|---|---|---|---|---|
| `0x232323` | `PP_MSG_NOT_READY` | **−726** | `IO_R_NOT_READY` (comment says −726) | **−728** | diverges |
| `0x232325` | `PP_MSG_SUCCESS` | 0 | `IO_R_SUCCESS` | 0 | matches |
| `0x232336` | `PP_MSG_TIMEOUT` | **−714** | `IO_R_TIMEOUT` (comment says −714) | **−726** | diverges |
| `0x232337` | `PP_MSG_NO_PAPER` | −737 | `IO_R_NO_PAPER` | −737 | matches |
| `0x232338` | `PP_MSG_BUSY` | −725 | `IO_R_BUSY` | −725 | matches |
| `0x232339` | `PP_MSG_OFFLINE` | **−738** | `IO_R_OFFLINE` (comment says −738) | **−727** | diverges |
| default | `default` | **−714** | `IO_R_TIMEOUT` | **−726** | diverges |

The 20 unlisted table indices (`0x232324`, `0x232326`-`0x232335`) all target the default
arm, so the reference's default really is −714. This entry was previously recorded as
`assembly-matched` on the strength of the comments; it is now `unexamined`.

*Resolved.* The four diverging arms now read `IO_R_TIMEOUT` (−726), `IO_R_IO` (−714),
`IO_R_PRINTER_OFFLINE` (−738) and `IO_R_IO` (−714) for the default; all seven values match
the reference and the entry is `assembly-matched` again. The `PP_MSG_*` labels are left
alone — they name the message code, not the return code, and the two do not line up (see
Finding 44); a comment above the method says so. The method is now at
`IOParallelPort.m:1059-1082`.

**Finding 58 — three of `initDevice`'s six return values are wrong.**
`IOParallelPort.m:276-352`. The reference (112) returns, from its five error paths and its
success path: paper-out **−737** (281), offline **−738** (301), busy **−725** (321),
ready-during-wait **−714** (344), success `0` (365) and not-ready **−726** (382). Ours
returns `IO_R_NO_PAPER` (−737, matches), `IO_R_OFFLINE` (**−727**, wants −738), `IO_R_BUSY`
(−725, matches), `IO_R_TIMEOUT` (**−726**, wants −714), `IO_R_SUCCESS` (0, matches) and
`IO_R_NOT_READY` (**−728**, wants −726). The status-word bit for each arm — 0x04, 0x08,
0x02, 0x10, 0x01 and a full 32-bit clear — matches throughout; only the returned values
diverge. This matters at the callers: `ppopen` (Finding 39) and `ppwrite` (Finding 49)
accept exactly `{0, −725, −726, −737, −738}` from `initDevice`, so under our constants an
offline or not-ready printer falls through to the `EIO` path.

*Resolved.* The three wrong arms now read `IO_R_PRINTER_OFFLINE` (−738), `IO_R_IO` (−714)
and `IO_R_TIMEOUT` (−726), so all six returns match and the caller-side set
`{0, −725, −726, −737, −738}` is satisfied. This entry's other divergences (Findings 10,
52, 53) stand, so 112 stays `unexamined`. The method is now at `IOParallelPort.m:286-362`.

**Finding 59 — `writeToPort`'s switch labels select the wrong arms.**
`IOParallelPort.m:538-568`. The reference (3212) switches `cmdBuffer->returnCode` on
−726 → status bit 0x10, −738 → 0x08, −737 → 0x04, −714 → 0x20 **and propagate the return
code**, −725 → 0x02, 0 → no bit, default → propagate. Ours labels those cases
`IO_R_NOT_READY`, `IO_R_OFFLINE`, `IO_R_NO_PAPER`, `IO_R_TIMEOUT`, `IO_R_BUSY` — which
compile to −728, −727, −737, −726 and −725. So −737 and −725 land correctly, −728 and −727
are codes nothing ever produces, and −726 — which the reference sends to the 0x10 arm —
is instead routed to the 0x20 "propagate" arm. The `PP_SW_*` bit values themselves are all
correct (`IOParallelPort.h:61-66`).

*Resolved.* The labels are now `IO_R_TIMEOUT` (−726 → 0x10), `IO_R_PRINTER_OFFLINE`
(−738 → 0x08), `IO_R_NO_PAPER` (−737 → 0x04), `IO_R_IO` (−714 → 0x20 and propagate),
`IO_R_BUSY` (−725 → 0x02) and `IO_R_SUCCESS`, so every arm selects the value the reference
selects. Findings 30 and 31 still stand, so 3212 stays `unexamined`. The switch is now at
`IOParallelPort.m:548-578`.

### Linkage and packaging

**Finding 54 — linkage differs, and `parity_check.py` cannot see it.** Reading the
reference's nlist with `binrecon.macho.read_macho`: 110 symbols, 76 `local` and 34
`external`. Of the 34 externals, 28 are undefined imports with no section; the reference
therefore has exactly **six externally defined symbols**, and these are all of them —
`__strobeChar`, `_IOParallelPortThread`, `_IOParallelPortInterruptHandler`,
`_ParallelPort_VERS_STRING`, `_ParallelPort_VERS_NUM`, `_ParallelPort_instance`.

- `-[IOParallelPort _waitForDevice:isReady:]` (0) is **`local`**, like every other instance
  method and `+probe:`. Being the first symbol in `__text` confers nothing. Our source
  already declares it as an ordinary method, so **no linkage change is needed here** —
  do not de-staticise it.
- `__strobeChar` (4232), `_IOParallelPortThread` (4512) and
  `_IOParallelPortInterruptHandler` (5240) are the only **`global`** `__text` symbols.
- All seven `cdevsw` entry points — `_ppopen` (5520), `_ppclose` (5652), `_ppread` (5692),
  `_ppwrite` (5828), `_ppminphys` (6252), `_ppstrategy` (6304), `_ppioctl` (6708) — are
  **`local`**, i.e. declared `static` in the reference source. Ours declares all seven in
  `IOParallelPortKern.h:98-104`, making them external.
- `_pp_softc` (8192) is `local`; ours has one `static` and one external definition
  (Finding 37).
- `_ParallelPort_instance` (8216, `__common`, `external`) and the two `__const` version
  symbols `_ParallelPort_VERS_STRING` (7892) and `_ParallelPort_VERS_NUM` (8052) are
  glue-generated, as are the three `_xxx.NNN` counters in `__bss` (which are `local`).

**`parity_check.py` compares symbol names only and will report all of these as matching.**
Task 10 must verify them by reading the rebuilt binary's nlist directly with
`binrecon.macho.read_macho` and checking each symbol's `binding` and `section` fields —
**not** by parity counts.

**Finding 55 — the driver links but does not package.** `kl_ld` produces a 185032-byte
`ParallelPort_reloc`, so what remains is a packaging failure and not a compile error:
`post_copy_tables` runs `chmod` over `$(NAME).config/*.table`, which does not exist,
and `gnumake` exits 2 after an otherwise successful link. Two contributing facts, both
verifiable from the repo:

- `Default.table` lives in `PCParallelPort.drvproj/`, and `PB.project:3` lists it under
  `OTHER_RESOURCES`, but the generated `PCParallelPort.drvproj/Makefile` has
  `GLOBAL_RESOURCES =` empty — so nothing copies it into `ParallelPort.config/`.
- The `post_copy_tables` rule lives in `driver.make`, which is **not** in this repo:
  `src/pb_makefiles-1/` has no `driver.make`, so the rule comes from the guest's installed
  `$(MAKEFILEPATH)/pb_makefiles`. It cannot be inspected or patched from here.

Task 10 should either add `Default.table` to `GLOBAL_RESOURCES` (or copy it in a
`Makefile.postamble` step) or accept the exit-2 and gate on the `_reloc` artefact instead.

**Finding 56 — the module list confirms the file split.** `__module_info` names exactly
three modules: `IOParallelPort.m`, `IOParallelPortKern.m` and `ParallelPort_instance.m`.
The first two are ours; the third is generated. The address boundary follows: everything
from 0 to 4231 is `IOParallelPort.m`, everything from 4232 (`__strobeChar`) to 7391 is
`IOParallelPortKern.m`, and 7392-7403 is the glue. `source-map.json` reflects this.

### Configuration table

`Default.table` matches the reference byte for byte except for the build-stamped
`"Driver Version"` line
(`PROGRAM:ParallelPort  PROJECT:drvPCParallel-9  DEVELOPER:root  BUILT:Sat Mar 28 22:11:23 PST 1998`),
which the build injects. No finding.

---

## Unresolved

- The reference ivar `dataRegisterData` (`C`, 0x134) is never read or written by any of the
  75 functions. Its purpose is unknown; it is presumably vestigial. Ours has no
  counterpart, and adding one is needed only for layout fidelity.
- The exact declared type of the reference's `_pp_softc` struct. The three fields and the
  12-byte size are certain from nine independent access sites; the field *names* are not
  recoverable from the binary.
- Whether the `-725` (`IO_R_BUSY`) arm that our first `_IOParallelPortThread` decode
  produces (Finding 47) is reachable in the reference by some path not visible in the
  static control flow. Reading the disassembly, it is not.

---

## 8. Fix pass (Task 10)

Two commits: the driver source, then this document plus the relined `ledger.json` and
`source-map.json`. Everything below was verified against the rebuilt
`ParallelPort_reloc`, not asserted.

### 8.1 Build

| | Baseline | After |
|---|---|---|
| `gnumake` | **exit 2** (`post_copy_tables`) | **exit 0** |
| `_reloc` size | 185032 | 165556 |
| Harness | `fail=0` | `fail=0` |

The driver had never been built before this pass. It compiled on the first attempt after
the rewrite; the only surviving warnings are `implicit declaration of physio` (no
prototype exists in the tree) and a false-positive `might be used uninitialized` pair on
`ppwrite`'s save/restore locals, both pre-existing.

`Loaded Server` sections, ours against the reference:

| Section | Reference | Ours |
|---|---|---|
| `Server Name` | 12 | 12 |
| `Load Commands` | 164 | 164 |
| `Instance Var` | 21 | 21 |
| `Server Version` | 1 | 1 |
| `Unload Commands` | *absent* | *absent* |

No `Unload_Commands.sect` was created: this reference does not have that section, unlike
the four other input drivers.

`InstallPPDev` and `RemovePPDev` were **not** built. `PostLoad.tproj` and `PreLoad.tproj`
were removed from the `.drvproj` Makefile's `TOOLS` by an earlier build-repair effort
because those user-space helpers need i386 crt and libDriver that the PPC cross-host does
not provide. That line was deliberately left alone. Recorded as an environment limitation,
not a source finding.

### 8.2 Parity and emitted metadata

`parity_check.py`, reference against rebuilt:

| | Baseline | After |
|---|---|---|
| `missing_strings` | 1 | **0** |
| `missing_symbols` | 0 | **0** |
| `extra_strings` | 40 | **0** |
| `extra_symbols` | 116 | 80 |
| exit | 1 | **0** |

The 80 extra `__TEXT,__text` symbols are our build's unstripped per-function and per-file
debug entries (3593 symbols against the reference's 110). Not findings.

Stronger than parity: every `__OBJC` section in the rebuilt binary is the reference's
size, with one exception.

| Section | Reference | Ours |
|---|---|---|
| `__class` / `__meta_class` | 120 / 120 | 120 / 120 |
| `__cls_meth` | 60 | 60 |
| `__inst_meth` | 752 | 752 |
| `__instance_vars` | 328 | 328 |
| `__message_refs` | 256 | 256 |
| `__cls_refs` | 8 | 8 |
| `__class_names` | 184 | 184 |
| `__meth_var_names` | 1312 | 1312 |
| `__module_info` / `__symbols` | 48 / 48 | 48 / 48 |
| `__meth_var_types` | 713 | **715** |

And the three string tables are **identical sets**, not merely identical sizes:
`__TEXT,__cstring` (15 entries), `__OBJC,__class_names` (11) and
`__OBJC,__meth_var_names` (90).

The 27 ivars land at the reference's 27 offsets, one for one, checked by decoding both
`__instance_vars` tables: `0x128` through `0x190`, instance size 404.

The two remaining `__meth_var_types` bytes are `-physbuf` and `-setPhysbuf:`. Ours encode
`struct buf` as `...^vi[3l]`, the reference as `...^vllll`: this tree's
`src/kernel-7/bsd/sys/buf.h` ends the struct with `int b_timestamp; long b_reserved[3]`
where Apple's 1998 header had four `long`s. Same 16 bytes, same offsets for every field
the driver touches. The fix is in a kernel header this task must not touch, so entries
2372 and 2388 are `intentional-mismatch`.

### 8.3 Linkage - a correction to Finding 54

Verified by reading both nlists with `binrecon.macho.read_macho` and checking `binding`
and `section`, not by parity counts.

- **The duplicate `_pp_softc` is gone.** The baseline binary carried two symbols of that
  name - one `local` in `__DATA,__data` from `IOParallelPort.m`'s `static`, one `external`
  from `IOParallelPortKern.m`. There is now exactly one, in `__DATA,__data`, the
  reference's section. It needed an explicit `= { { nil, 0, NULL } }` initialiser: without
  one it landed in `__DATA,__common`.
- **Finding 54's reading of the seven `cdevsw` entry points was wrong, and so was its
  reading of `_pp_softc`.** They are `local` in the reference, but they cannot have been
  `static` in Apple's source: `initFromDeviceDescription:` - which `__module_info` places
  in `IOParallelPort.m` - pushes `offset _ppopen` through `offset _ppioctl` into
  `IOAddToCdevsw` at 856-911 and writes `ds:_pp_softc` at 1165, while every read of
  `_pp_softc` is in `IOParallelPortKern.m`. Those are cross-module references; `static`
  would not link. The `local` binding is therefore produced by the kernel-server link
  step, not by a `static` in the source. Our build does not run that step at all - it
  ships 3593 symbols against the reference's 110 - so **no source change is possible or
  warranted here**, and none was made. Nothing was de-staticised either.

  A note on how much this explains: the reference has **34** external symbols, not six,
  and three of them (`__strobeChar`, `_IOParallelPortThread`,
  `_IOParallelPortInterruptHandler`) live in the *same* object file as the seven `local`
  `cdevsw` entry points. So the link step privatises selectively, and exactly which
  symbols it keeps external is not explained by "what the loader needs". That split is
  unresolved. It does not affect the conclusion above - the cross-module references are
  proof enough that `static` was never in the source - but the mechanism should not be
  stated more confidently than the evidence supports.
- `__strobeChar`, `_IOParallelPortThread` and `_IOParallelPortInterruptHandler` are
  external and defined in `__TEXT,__text` in both binaries. All three spellings were
  already correct and were left alone.
- `_ParallelPort_VERS_STRING` and `_ParallelPort_VERS_NUM` (`__TEXT,__const` in the
  reference) are **absent** from our build. They are version-stamp symbols the guest's
  build tooling does not emit. `parity_check.py` compares `__TEXT,__text` only and cannot
  see this; it is recorded here rather than hidden.

### 8.4 Decision on Finding 29 - taken all the way

Every `sel_getUid` / `objc_msgSend` pair in `IOParallelPortKern.m` was replaced with
ordinary message-send syntax against an `IOParallelPort *`. All 37 selector literals are
gone from `__cstring`, which now holds exactly the reference's 15 strings and nothing
else, and dispatch goes through the 64 `__message_refs` entries - 256 bytes, the
reference's count. This also dissolved Finding 46: the mis-split nested send in
`_IOParallelPortThread` becomes the single statement
`[port _waitForDevice:[port waitForever] isReady:&deviceReady]` at both sites.

Two consequences worth naming. The ivars are now `@public`, because the reference's
`_strobeChar` and interrupt handler read `controlRegisterDefaults`, the three register
addresses, `physbuf`, `intHandlerDelay` and `writing` straight out of the instance rather
than through accessors; ObjC does not record ivar protection in `__instance_vars`, so this
is invisible in the binary. And `objc_getClass("NXConditionLock")` is gone in favour of
`#import <machkit/NXLock.h>` and direct class references, which is what puts
`NXConditionLock` and `NXLock` in `__class_names` instead of `__cstring` (Finding 28).

### 8.5 Decision on Finding 55 - repaired, not accepted

`PCParallelPort.drvproj/Makefile` had `GLOBAL_RESOURCES =` empty while `PB.project`
already listed `Default.table` under `OTHER_RESOURCES`, so nothing copied the table into
`ParallelPort.config/` and `post_copy_tables` then ran `chmod` over a path that did not
exist. The four sibling input drivers all carry `GLOBAL_RESOURCES = Default.table`;
drvPCParallel now does too. `gnumake` exits 0. `driver.make` itself was not touched - it
is not in this repo.

### 8.6 Two findings the fix pass discovered

**Finding 60 - `Load_Commands.sect` was one byte short.** Ours began `#` newline where the
reference's section begins `#`, space, newline. 163 bytes against Apple's 164, confirmed
by dumping `Loaded Server,Load Commands` out of the reference at file offset 26984. The
trailing space is restored and the emitted section is now 164 bytes.

**Finding 61 - `registerDevice`'s result was tested with the wrong polarity.**
`IODevice.h:173` declares `- registerDevice;` with "nil return means failure", not an
`IOReturn`. The reference tests it accordingly: `test eax, eax; jz` to the
`could not register device` log at 1407-1416, and returns `self` when it is non-nil. Ours
compared it against `IO_R_SUCCESS`, i.e. treated 0 as success - which for an `id` return
inverts the test and would have failed initialisation on every successful registration.
Now `if ([self registerDevice] == nil)`.

### 8.7 Every finding and what became of it

| # | Resolution |
|---|---|
| 1 | Fixed. `IOParallelPort : IODirectDevice`. Instance size 404, first ivar 0x128, both confirmed in the rebuilt `__class` and `__instance_vars`. |
| 2 | Fixed. `_waitForDevice:isReady:` implements the poll loop decoded from 0-111. |
| 3 | Fixed. 27 ivars, the reference's names, types and order; all 27 offsets verified against the reference's `__instance_vars`. |
| 4 | Fixed. `sizeLock` is an `NXLock` at 0x188; `-lockSize` and `-unlockSize` send it `lock` and `unlock`. |
| 5 | Fixed. `probeForController` returns `BOOL`, and its caller now tests `if (![self probeForController])`. Landed in the same commit as the re-parent. |
| 6 | Fixed. `- free` returns `id`. |
| 7 | Fixed. `- (IOReturn)printerInit`. |
| 8 | Fixed. `- (void)cmdBufExec:`. |
| 9 | Fixed. `- (BOOL)_waitForDevice:isReady:`. |
| 10 | Fixed. `statusWord` is `unsigned int`. |
| 11 | Fixed. `autofeedOutput` is `int`. |
| 12 | Fixed. `ioTimeout` is signed `int`, which is what makes `_IOParallelPortThread`'s elapsed-time test signed. |
| 13 | Fixed. The four register ivars are `char *` and the eight accessors `const char *`; `PP_PORT()` narrows to `IOEISAPortAddress` at each port access, which is the reference's 16-bit load. |
| 14 | Fixed as far as this task may go - see 8.2. `physbuf` is `struct buf *`; the encoding differs by one character because of `src/kernel-7/bsd/sys/buf.h`. |
| 15 | Fixed. `interruptMessage` is `msg_header_t *` and holds the `IOMalloc(0x2000)`; the separate `cmdBuf` ivar and the `0x54e` assignment are gone. |
| 16 | Fixed. `-interruptPort` removed; inherited from `IODirectDevice`. `__inst_meth` is 752 bytes, 62 methods, the reference's count. |
| 17 | Fixed. `getHandler:` writes `minorDevNum` through an `unsigned int *`. |
| 18 | Fixed. `setDeviceKind:` replaces `setDriverName:`. |
| 19 | Fixed. The `Location` read and `setLocation:` are gone; `Location` is gone from `__cstring`. |
| 20 | Fixed. The `Minor Device Number` string is freed on both paths. |
| 21 | Fixed. `[deviceDescription name]` is gone from both sites. |
| 22 | Fixed. `[self setMinorDevNum:0]`. |
| 23 | Fixed. `IOThreadDelay` and `intHandlerDelay` both initialised to 1. |
| 24 | Fixed. `cdevsw` slot 8 is `seltrue`. |
| 25 | Fixed. The explicit attach block is gone; `IODirectDevice`'s init attaches the port, which runs our `-attachInterruptPort` override and forks the I/O thread. |
| 26 | Fixed. `dataBuffer` is allocated from `minPhys`. |
| 27 | Fixed. The message text is the reference's and the address is passed as `(unsigned short)`. `missing_strings` is 0. |
| 28 | Fixed. `NXConditionLock` resolves through `__cls_refs`; `__class_names` is 184 bytes and its 11 entries match the reference's exactly. |
| 29 | Fixed in full - see 8.4. |
| 30 | Fixed. `writeToPort` and the interrupt handler both use `writing` (0x129). |
| 31 | Fixed. The return value starts at 0 and is only propagated in the -714 and default arms. |
| 32 | Fixed. `setBlockSize:` guards on `blockSize`, `setMinPhys:` on `minPhys`. |
| 33 | Fixed. `-free` frees `sizeLock` and `ioQueueLock`, unconditionally, and no interrupt port. |
| 34 | Fixed, deliberately. All four NULL guards removed, matching the reference. The reference checks `physbuf`, `interruptMessage` and `dataBuffer` before `IOFree` and nothing else; ours now checks exactly those three. |
| 35 | Fixed. `-free` sizes the `dataBuffer` free from `minPhys`. |
| 36 | Fixed. `pp_softc` is a one-element 12-byte `{ id device; int count; unsigned char *data; }` in `__DATA,__data`; the three parallel arrays are gone. |
| 37 | Fixed. One definition. Verified in the nlist - see 8.3. |
| 38 | Fixed. All seventeen `pp_kern_*` functions and the `pp_base_addrs` and `pp_modes` statics deleted, along with their prototypes and the `pp_mode_t` and `pp_port_state_t` types. |
| 39 | Fixed. `ppopen` implements the reference's body, including the two-range acceptance test. |
| 40 | Fixed. `unsigned int ppminphys(struct buf *)` returns the clamp and stores nothing. |
| 41 | Fixed. `int ppstrategy(struct buf *)`, -1 on error and 0 on success. |
| 42 | Fixed. -738 and -737 give 83, -726 gives 60, -725 gives 16, default gives 5, from all 36 decoded jump-table entries. |
| 43 | Fixed. `bp->b_un.b_addr` is copied by value; the double indirection is gone. |
| 44 | Fixed. SELECT set gives `0x232336`, SELECT clear gives `0x232339`. |
| 45 | Fixed. The read path advances then stores, and tests the count for equality where the write path tests `<= 0`. |
| 46 | Fixed - see 8.4. |
| 47 | Fixed. The first decode now has its own shape; the second was already right and is unchanged. |
| 48 | Fixed. `[port interruptMessage]` is fetched once and that 8192-byte buffer is what `msg_receive` fills; the stack struct is gone. |
| 49 | Fixed. The four accepted codes return 0 without writing, the ranges are exactly -726 to -725 and -738 to -737, and the `ENOMEM` check is gone. |
| 50 | Fixed. `pp_strobe_count` deleted. |
| 51 | Fixed, deliberately. Every `PP_KERN_MAX_PORTS` bounds check removed; NULL checks kept in exactly the four functions that have one in the reference - `ppread`, `ppwrite`, `ppioctl`, `ppstrategy` - and removed from `ppopen`, `ppclose`, `ppminphys`, `_strobeChar` and the interrupt handler. **Task 7 reversed the leftover `_strobeChar` ordering:** the device pointer and three registers now load before testing `pp_softc[portNum].count`, so a nil device with leftover count faults like Apple. Ledger 4232 stays `intentional-mismatch`; leftover is gcc 2.x CSE / register allocation. |
| 52 | Fixed. The `initialized` ivar is gone; `-isInitialized` reads bit 0 of `statusWord`. |
| 53 | **Reversed.** `probeForController` and `initDevice` now `and`/`or` an uninitialized `controlValue` with Apple's immediates (`0xFE`/`0x02`/`0x04`/`0x08`/`0x10`/`0xDF`, then `0xFE`/`0xFD`/`0x04`/`0xF7`/`0xEF`/`0xDF` in probe; `0xFE`/`0xFD`, autofeed `<< 1`, `0x04`/`0x08`/`0xEF`/`0xDF` in initDevice). Guest gcc 2.x `-O` folds those immediates (`or …, 1Eh`, `and …, 0C7h`, `and bl, 0FCh` / `or bl, 0Ch`) and does not emit the unused first `inb` store, so both rows stay `intentional-mismatch`. Leftover is compiler-shaped, not a missing reconstruction. |
| 54 | **Corrected and accepted** - see 8.3. No source change. |
| 55 | **Repaired** - see 8.5. |
| 56 | No action. `__module_info` is 48 bytes in both binaries and the three modules are unchanged. |
| 57-59 | Already fixed in `15ce9007`, by value. Re-verified: the `writeToPort` and `initDevice` arms select the values the reference selects. Ledger entry 3492 is `control-flow-confirmed`, not `assembly-matched` - the ledger is the authority here and is deliberately the more conservative of the two. |
| 60 | Fixed - see 8.6. |
| 61 | Fixed - see 8.6. |

### 8.8 The Unresolved items, revisited

`dataRegisterData` (`C`, 0x134) is still never read or written by any of the 75 functions.
It is declared so the ivars after it land at the reference's offsets, and is commented as
such.

The reference's `_pp_softc` field *names* are still unrecoverable; the three fields and
the 12-byte stride are certain from nine independent access sites, and the names chosen
here - `device`, `count`, `data` - are ours.

One item can now be closed: `-[IOParallelPort waitForCmdBuf]`'s return type cannot be
determined, because the reference's encoding for it is uniqued with `-dataBuffer`'s
`^v8@8:12`. It is left as `void *`.

---

## Finish campaign (2026-09-16)

Instruction-stream baseline against Apple's `ParallelPort_reloc`, measured after Tasks
1–3 with no reloc shape edits and no guest rebuild. Rebuilt SHA-256:
`FA106F9173FC78D431579AA8CCD458C8FF2FC35B2AA5036F8FDD42B6DBB51D56` (165552 bytes,
unstripped guest `kl_ld` image).

IDA `--list` on this reloc: **36** `raw_equal` (byte-identical) and **14** `masked_equal`
(instruction streams match under the binrecon mask). Task 5 promoted every paired row in
those classes to `assembly-matched` except the two Kernel Server glue methods
(`+[ParallelPortKernelServerInstance kernelServerInstance]`,
`+[ParallelPortVersion driverKitVersionForParallelPort]`), the `physbuf` / `setPhysbuf:`
pair (Finding 14 / `struct buf` encoding), and compiler-shaped leftovers
(`+[IOParallelPort probe:]`, `controlRegisterContents`, `statusRegisterContents`,
`isInitialized`, and the swapped accessor name-pairing rows). Five former
`control-flow-confirmed` entries that were already `masked_equal` — `free`,
`getIntValues:forParameter:count:`, `setMinPhys:`, `setBlockSize:`, and `_ppread` — were
advanced forward-only to `assembly-matched`. Ledger counts after the transition: **55**
`assembly-matched`, **13** `control-flow-confirmed`, **7** `intentional-mismatch`.

`_ParallelPort_VERS_STRING` and `_ParallelPort_VERS_NUM` were checked: the reference holds
them in `__TEXT,__const`; the rebuilt reloc has no `__const` section and neither symbol.

Tools: `InstallPPDev` was not staged — PreLoad `gnumake` failed on `IODeviceMaster.m`
(`illegal expression, found unsigned`). `RemovePPDev` was staged but is a Mach-O **ppc**
executable, not i386. Phase 3 / Task 10 converts both tproj trees to `tool.make`.

### Task 6 — Finding 53 reversed (uninitialized control byte)

`probeForController` and `initDevice` now build the control byte with `and`/`or` on an
uninitialized local, using the reference immediates from the Task 4 IDA `--name` dump.
Guest `cc -O` still folds consecutive constant `and`/`or` and does not keep the unused
first `inb` store, so neither function is `masked_equal`. Ledger entries 112 and 1452
stay `intentional-mismatch` with reason `Finding 53 uninitialized control byte; leftover
is gcc 2.x zero-fill`. Rebuilt SHA-256
`F1FDFD0943E86BA99F2AA510DF54AFE1CD1A9F7ACB675CA17755CC32DBDD6883` (165600 bytes).
`parity_check.py`: `missing_strings (0):`, `missing_symbols (0):`. Previously identical
and `masked_equal` rows stayed equal (40 `raw_equal`, 14 `masked_equal`, 0 unpaired).

`--name -[IOParallelPort probeForController]` after the rewrite:

```
status=different raw_equal=False masked_equal=False
reason: cfg differs
reason: function range bytes differ
reason: instruction shape differs
```

Reference emits `and [ebp+var_2], 0FEh` / `or …, 2` / `or …, 4` / `or …, 8` /
`or …, 10h` / `and al, 0DFh`, then the second pattern as separate `0FEh`/`0FDh`/`4`/
`0F7h`/`0EFh`/`0DFh` ops. Rebuilt folds to `and [ebp+var_8], 0FEh` / `or …, 1Eh` /
`and …, 0DFh` and `and …, 0FCh` / `or …, 4` / `and …, 0C7h`. The unused `mov [ebp+var_1], al`
after the first `inb` is dropped.

`--name -[IOParallelPort initDevice]`:

```
status=different raw_equal=False masked_equal=False
reason: calls differ
reason: cfg differs
reason: function range bytes differ
reason: instruction shape differs
```

Reference: `and [ebp+var_1], 0FEh` then `and al, 1` / `add al, al` / `and [ebp+var_1], 0FDh`
/ `or [ebp+var_1], al` / `or …, 4` / `or …, 8` / `and …, 0EFh` / `and al, 0DFh`. Rebuilt
keeps the autofeed `and al, 1` / `add al, al` but holds the byte in `bl` and folds to
`and bl, 0FCh` / `or bl, al` / `or bl, 0Ch` / `and bl, 0CFh`. `IO_R_*` immediates
(`0xFFFFFD1F`, `0xFFFFFD1E`, `0xFFFFFD2B`, `0xFFFFFD36`, `0xFFFFFD2A`) are unchanged.

### Task 7 — `_strobeChar` load-then-test reversed

`_strobeChar` now loads `pp_softc[portNum].device` and the three register values
(`controlRegisterDefaults`, `controlRegister`, `dataRegister`) before testing
`pp_softc[portNum].count`. A nil device with leftover count faults like Apple. `useSpl` /
`spl3`, the second count check, the three `outb`/`IODelay` strobes, and pointer/count
advance are unchanged. Rebuilt SHA-256
`562D9829B43605A045C84FA4253C90206BECE0E236695BB3782B2E9D5A867A1E` (165620 bytes).
`parity_check.py`: `missing_strings (0):`, `missing_symbols (0):`. Previously identical
and `masked_equal` rows stayed equal (40 `raw_equal`, 14 `masked_equal`, 0 unpaired).

`--name __strobeChar` after the rewrite:

```
status=different raw_equal=False masked_equal=False
reason: calls differ
reason: cfg differs
reason: function range bytes differ
reason: instruction shape differs
```

Both sides now load the device pointer and three ivars before `cmp dword ptr [eax+2004h], 0`.
Diff count dropped from 70 to 55 (84 vs 80 instructions). Leftover is compiler-shaped: Apple
`sub esp, 10h` and reloads `_pp_softc[eax]` three times, keeping the control byte at
`[ebp+var_1]` via `ebx`; gcc 2.x `-O` uses `sub esp, 14h`, one `_pp_softc` load into `edx`,
and holds the control byte in `bl`. Ledger 4232 stays `intentional-mismatch`.

### Task 8 — `msgTypeToIOReturn:` case order (`masked_equal`)

Swapped the `PP_MSG_OFFLINE` (−738 / `0xFFFFFD1E`) and `PP_MSG_BUSY` (−725 /
`0xFFFFFD2B`) cases in `IOParallelPort.m` so gcc 2.x emits the jump-table bodies
in Apple's order. `--name -[IOParallelPort msgTypeToIOReturn:]`:
`masked_equal=True`; leftover stars are jump-table label addresses only.
Rebuilt SHA-256 `7DD159FCB4BCD936009C2B5FB9F89859A4E171DAA75266036958CF45AF1C2D23`
(165620 bytes). Parity `missing_strings (0):`, `missing_symbols (0):`. Previously
identical rows stayed identical (40 `raw_equal`, 15 `masked_equal`, 0 unpaired).
Ledger 3492 is `assembly-matched`.

### Task 8 — `cmdBufExec:` prev-link first (compiler-shaped leftover)

Store `cmdBuffer->link.prev` before `link.next` so the enqueue writes match Apple.
Operand-reversed empty-queue compare (`ioQueue.prev == &ioQueue`) inverted `cmp`
operands (`cmp edx, eax`) and was reverted. `&ioQueue` local skipped (invented temp).
C89 cannot declare `oldTail` after the lock.

Leftover is gcc 2.x `add esp, 8` scheduling after `[ioQueueLock lock]`. Rebuilt
SHA-256 `49863885A11EC0AE2FFD49F9297D54E0702CBC364C1ABEB398D73F5AB742456A`.
Parity 0/0. Previously identical rows stayed identical. Ledger 3896
`intentional-mismatch`, reviewer Pat Raynor, reason
`compiler-shaped leftover after exhausted source-shape list`.

```
-[IOParallelPort cmdBufExec:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push esi                                push esi
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov esi, [ebp+arg_8]                    mov esi, [ebp+arg_8]
  mov ecx, ds:paLock                      mov ecx, ds:paLock
  push ecx                                push ecx
  mov ecx, [ebx+164h]                     mov ecx, [ebx+164h]
  push ecx                                push ecx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 8
  mov edx, [ebx+16Ch]                     mov edx, [ebx+16Ch]
  lea eax, [ebx+168h]                     lea eax, [ebx+168h]
*                                         add esp, 8
  cmp eax, edx                            cmp eax, edx
* jnz loc_F74                             jnz loc_DC0
  mov [ebx+168h], esi                     mov [ebx+168h], esi
* jmp loc_F77                             jmp loc_DC3
  mov [edx+14h], esi                      mov [edx+14h], esi
  mov [esi+18h], edx                      mov [esi+18h], edx
  lea ecx, [ebx+168h]                     lea ecx, [ebx+168h]
  mov [esi+14h], ecx                      mov [esi+14h], ecx
  mov [ebx+16Ch], esi                     mov [ebx+16Ch], esi
```

### Task 8 — `cmdBufAlloc` dropped lock local (`masked_equal`)

`cmdBufAlloc` now stores `[NXConditionLock new]` straight into
`cmdBuffer->conditionLock` and sends `lock` / `unlockWith:0` through that
ivar. gcc keeps the buffer in `ebx` and the `new` result in `eax` for the
`lock` send, matching Apple. `--name` `masked_equal=True` (no starred
mnemonics). Rebuilt SHA-256
`EC622A557A0FD4AB3D3B444F6C4B731747B10FC83B1EC02844990F84F7B895C3` (165576 bytes).
Parity 0/0. Previously identical rows stayed identical. Ledger 3780
`assembly-matched`. source-map relined 6 later `IOParallelPort.m` sites
(73 mapped / 2 unmapped).

### Task 8 — `waitForCmdBuf` if/else dequeue (compiler-shaped leftover)

Replaced the `unlockWith:` ternary with if/else (`empty → 0`, else `1`) and inverted
the prev-link arms so `prev != &ioQueue` updates `prev->next` first. `--name`
still `masked_equal=False`. Leftover is gcc 2.x `add esp, 0Ch` scheduling after
`lockWhen:` and else-block placement of the head store. Rebuilt SHA-256
`D9B5138F47C5CFFF3682FE9D7FBBD6BD1E7D05CFCC11A3F78F6E7D6FE3DF440A`.
Parity 0/0. Previously identical rows stayed identical. Ledger 4040
`intentional-mismatch`, reviewer Pat Raynor, reason
`compiler-shaped leftover after exhausted source-shape list`.

```
-[IOParallelPort waitForCmdBuf]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs
* add esp, 0Ch                            (scheduled after lea vs immediately after lockWhen)
  cmp eax, edx                            cmp eax, edx
* jz loc_102C                             jz loc_E98
  mov [edx+14h], ecx                      mov [edx+14h], ecx
*                                         jmp loc_E9E / mov [ebx+168h], ecx
  cmp [ebx+168h], eax                     cmp [ebx+168h], eax
* jnz loc_1034                            jnz loc_EB0
  push 0                                  push 0
```

### Task 8 — `printerInit` compiler-shaped leftover

Source-shape list exhausted. Split load/`&=` did not change codegen; `int`
`controlValue` shrank `__text` and unpaired `blockSize` / `intHandlerDelay`
(reverted). Leftover is gcc 2.x keeping the control byte in `bl` vs Apple's
`[ebp+var_1]` and `self` in `ebx`. Rebuilt SHA-256
`D9B5138F47C5CFFF3682FE9D7FBBD6BD1E7D05CFCC11A3F78F6E7D6FE3DF440A`.
Parity 0/0. Previously identical rows stayed identical. Ledger 3132
`intentional-mismatch`, reviewer Pat Raynor, reason
`compiler-shaped leftover after exhausted source-shape list`.

```
-[IOParallelPort printerInit]
  status=different raw_equal=False masked_equal=False
* sub esp, 4
  push ebx                                push ebx
* mov ebx, [ebp+self]                     mov eax, [ebp+self]
* mov cl, [ebx+140h]                      mov bl, [eax+140h]
* mov [ebp+var_1], cl                     and bl, 0FBh
* and [ebp+var_1], 0FBh                   mov dx, [eax+13Ch]
* mov dx, [ebx+13Ch]                      mov al, bl
* mov al, [ebp+var_1]
  out dx, al                              out dx, al
```

### Task 8 — `_waitForDevice:isReady:` for-loop leftover

Kept a `for (tries = 0; ; tries++)` with `if (!(tries < busyMaxRetries || wait))`
break so the first compare is `cmp [busyMaxRetries], ebx` / `ja` like Apple, with
matching `nop` padding and `inc ebx` after `add esp, 4`. Leftover is gcc 2.x
leaving `in al` in `al` instead of `[ebp+var_1]` (`sub esp, 4` vs `8`). Rebuilt
SHA-256 `76CA62E75C2467B5E0BFA25A61BB433DF1385F389D0D4DA66E98FD8411CD753F`.
Parity 0/0. Previously identical rows stayed identical. Ledger 0
`intentional-mismatch`, reviewer Pat Raynor, reason
`compiler-shaped leftover after exhausted source-shape list`. source-map relined
7 later `IOParallelPort.m` sites (73 mapped / 2 unmapped).

```
-[IOParallelPort _waitForDevice:isReady:]
  status=different raw_equal=False masked_equal=False
* sub esp, 8                              sub esp, 4
  xor cl, cl                              xor cl, cl
  xor ebx, ebx                            xor ebx, ebx
  cmp [esi+144h], ebx                     cmp [esi+144h], ebx
  nop                                     nop
  in al, dx                               in al, dx
* mov [ebp+var_1], al
  and al, 0B8h                            and al, 0B8h
```

### Task 8 — `_ppopen` nested signed initDevice range

Replaced the combined range predicate with Apple's signed compare tree
(`result <= BUSY` then timeout/paper/offline bounds, else `result != 0`).
`--name` now matches `cmp 0FFFFFD2Bh` / `jg` / `cmp 0FFFFFD2Ah` / `jge`.
Leftover is gcc 2.x `jge` vs Apple's `jl` on the offline bound and where
`mov eax, 5` is placed. Rebuilt SHA-256
`5F8A0FDE2A167B1DF11035829FA2D2117D5D101357BFE2EB6BEC5D33D70AD624`.
Parity 0/0. Previously identical rows stayed identical. Ledger 5520
`intentional-mismatch`, reviewer Pat Raynor, reason
`compiler-shaped leftover after exhausted source-shape list`. source-map
relined 8 later `IOParallelPortKern.m` sites (73 mapped / 2 unmapped).

```
_ppopen
  status=different raw_equal=False masked_equal=False
  cmp eax, 0FFFFFD2Bh                     cmp eax, 0FFFFFD2Bh
* jg loc_15F0                             jg loc_10A4
  cmp eax, 0FFFFFD2Ah                     cmp eax, 0FFFFFD2Ah
* jge loc_15F4                            jge loc_10A8
  cmp eax, 0FFFFFD1Fh                     cmp eax, 0FFFFFD1Fh
* jg loc_1608                             jg loc_109C
  cmp eax, 0FFFFFD1Eh                     cmp eax, 0FFFFFD1Eh
* jl loc_1608                             jge loc_10A8
* jmp loc_15F4                            mov eax, 5
  test eax, eax                           test eax, eax
```

### Task 8 — `writeToPort` IO_R_IO fallthrough

`IO_R_IO` now falls into `default` so `returnCode = cmdBuffer->returnCode` is the
shared `mov edi, [ebx+0Ch]`. Switch cases reordered BUSY / PAPER / OFFLINE /
TIMEOUT / SUCCESS / IO so the `or al, 2/4/8/10h` bodies match Apple. Leftover
is gcc 2.x SUCCESS `jz` vs `jnz` polarity. Rebuilt SHA-256
`D13D6D48DA5CB5B131E2F1BBF6A56A59B68EEC72583A7A74FC18880CF159C6EF`.
Parity 0/0. Previously identical rows stayed identical. Ledger 3212
`intentional-mismatch`, reviewer Pat Raynor, reason
`compiler-shaped leftover after exhausted source-shape list`. source-map relined
42 later `IOParallelPort.m` sites (73 mapped / 2 unmapped).

```
-[IOParallelPort writeToPort]
  status=different raw_equal=False masked_equal=False
  test edx, edx                           test edx, edx
* jnz loc_D4B                             jz loc_88E
* jmp loc_D22                             jmp loc_8B7
  or al, 2                                or al, 2
  or al, 4                                or al, 4
  or al, 8                                or al, 8
  or al, 10h                              or al, 10h
  or al, 20h                              or al, 20h
  mov edi, [ebx+0Ch]                      mov edi, [ebx+0Ch]
```

### Task 8 — `_ppwrite` signed range, no pre-zero

Nested signed `initDevice` compares (`cmp 0FFFFFD2Bh` / `jle`) plus dropping
pre-zeroed `uioPtr` / `iov` / `tempBuffer` locals. Diff 112→80. Leftover is
gcc 2.x `ebx` vs Apple's `esi` and Apple's extra prologue zeros. Rebuilt
SHA-256 `C439A3442A4B9600B5C0281A3877C2645A3C979EE472234505BD6CA88248FB7F`.
Parity 0/0. Previously identical rows stayed identical. Ledger 5828
`intentional-mismatch`. source-map Kern.m sites resynced (73 mapped / 2 unmapped).

```
_ppwrite
  status=different raw_equal=False masked_equal=False
* sub esp, 18h                            sub esp, 14h
  movzx eax, byte ptr [ebp+dev]           movzx eax, byte ptr [ebp+dev]
* mov esi, ds:_pp_softc[eax*4]            mov ebx, ds:_pp_softc[eax*4]
* xor ebx, ebx                            test ebx, ebx
```

### Task 8 — `_IOParallelPortInterruptHandler` decode leftover

Inverted the outer `(status & 0x28) != 8` so Apple's `jz` busy-arm polarity
matches, stored OFFLINE then overwrote ERROR on SELECT-clear, and sent
nonzero `interruptMsg` before the transfer path (`test ecx` / `jz` transfer /
`push ecx`). Leftover is gcc 2.x `inb` stack slot vs `dl`. Rebuilt SHA-256
`4286DBE19D7CAEA41A8E990E3CC4DA6EC057816542D47F944028291F7FDC3CED`.
Parity 0/0. Previously identical rows stayed identical. Ledger 5240
`intentional-mismatch`.

```
_IOParallelPortInterruptHandler
  status=different raw_equal=False masked_equal=False
* sub esp, 10h                            sub esp, 8
  cmp al, 8                               cmp al, 8
* jz loc_14FC                             jz loc_178C
  mov ecx, 232336h                        mov ecx, 232336h
* test byte ptr [esi], 10h                test dl, 10h
* jnz loc_1506                            jnz loc_1795
  mov ecx, 232339h                        mov ecx, 232339h
  test ecx, ecx                           test ecx, ecx
* jz loc_1510                             jz loc_179C
  push ecx                                push ecx
  push 232325h                            push 232325h
```

### Task 8 — `_ppstrategy` jump table

READ-first so `jz` takes WRITE, `minor(bp->b_dev)` at each `pp_softc` access,
`if (result != 0)` so `test edx` / `jz` success, missing `case PP_IO_ERROR`
(-703) so gcc emits `lea eax, [edx+2E2h]` / `cmp eax, 23h`, BUSY before
TIMEOUT so the case bodies are 0x53 / 0x10 / 0x3C / 0x5. IDA `masked_equal`
(label/jpt addresses only). Rebuilt SHA-256
`B2569ED7E39790C27046346BCE98B6B8115F37428CB8796C75D51C94F14ABA32`.
Parity 0/0. Previously identical rows stayed identical (40). Ledger 6304
`assembly-matched`.

```
_ppstrategy
  status=different raw_equal=False masked_equal=True
  lea eax, [edx+2E2h]                     lea eax, [edx+2E2h]
  cmp eax, 23h                            cmp eax, 23h
* ja def_1957                             ja def_1683
* jmp ds:jpt_1957[eax*4]                  jmp ds:jpt_1683[eax*4]
  mov dword ptr [esi+28h], 53h            mov dword ptr [esi+28h], 53h
  mov dword ptr [esi+28h], 10h            mov dword ptr [esi+28h], 10h
  mov dword ptr [esi+28h], 3Ch            mov dword ptr [esi+28h], 3Ch
  mov dword ptr [esi+28h], 5              mov dword ptr [esi+28h], 5
```

### Task 8 — `_ppioctl` signed switch leftover

`int cmd` so gcc emits signed `jg` (SET codes sort below GET), `timeout = *uintData`
then `* 1000`, cases grouped GET-then-SET by field. Switch pivots and timeout
`lea [ebx+ebx*4]` match. Leftover is gcc 2.x inlining getter `objc_msgSend`
instead of Apple's shared `jmp loc_1C82` / `jmp loc_1C99` tails. Rebuilt
SHA-256 `1276E0E5BFDA0E577ED4949E842DAE136BF3CA16588143A32960915448A88D4E`.
Parity 0/0. Previously identical rows stayed identical (40). Ledger 6708
`intentional-mismatch`, reviewer Pat Raynor, reason
`compiler-shaped leftover after exhausted source-shape list`.

```
_ppioctl
  status=different raw_equal=False masked_equal=False
  cmp edx, 40047004h                      cmp edx, 40047004h
* jz loc_1C18                             jz loc_14E0
* jg loc_1AF0                             jg loc_13B8
  mov ecx, ds:paStatusword                mov ecx, ds:paStatusword
* jmp loc_1C82                            push ecx
*                                         push esi
*                                         call near ptr _objc_msgSend
  mov ebx, [ebx]                          mov ebx, [ebx]
  cmp ebx, 0FFFFFFFFh                     cmp ebx, 0FFFFFFFFh
  lea eax, [ebx+ebx*4]                    lea eax, [ebx+ebx*4]
```

### Task 8 — `initFromDeviceDescription:` frame leftover

`minorDevStr` declared before `configTable` so both sides store the table in
`var_1C` and the minor string in `var_18`. `int validRange` unpaired
`blockSize` / `intHandlerDelay` (reverted). Leftover is gcc 2.x `sub esp,20h`
vs Apple's `24h`/`mov [ebp+var_20],0`, `strcmp` length in `edx` vs
`[ebp+var_24]`, and error-path `free` register choice. Rebuilt SHA-256
`C61ABDE8F2360A74AEFAE11B5CED36E8F0F998D133F40C503889A313E85D242D`.
Parity 0/0. Previously identical rows stayed identical (40). Ledger 456
`intentional-mismatch`, reviewer Pat Raynor, reason
`compiler-shaped leftover after exhausted source-shape list`.

```
-[IOParallelPort initFromDeviceDescription:]
  status=different raw_equal=False masked_equal=False
* sub esp, 24h                            sub esp, 20h
  mov [ebp+var_1C], eax                   mov [ebp+var_1C], eax
  mov [ebp+var_18], eax                   mov [ebp+var_18], eax
* mov edi, offset a0                      mov [ebp+var_20], offset a0
* mov [ebp+var_24], 2                     mov edx, 2
  cmp eax, 1                              cmp eax, 1
* jbe loc_294                             jbe loc_100
```

### Task 8 — remaining large functions

### Task 8 — `_IOParallelPortThread` commandType leftover

Load `commandType` then `if (commandType == 0) write; if (commandType == 1)
exit`. `--name` now matches `test eax,eax` / `jz` write / `cmp eax,1`.
Inverted paper test still emitted `jnz` (reverted). Leftover is gcc 2.x `inb`
in `bl` vs Apple's `[ebp+var_1]`, `esi` vs `ebx`, and `cmp 1` / `jnz`
complete vs `jz` exit. Rebuilt SHA-256
`F31C01A0FBB4F010AADC205C8CAE011A501FD6D5016BFCEC10022AA65E2BA9DC`.
Parity 0/0. Previously identical rows stayed identical (40). Ledger 4512
`intentional-mismatch`, reviewer Pat Raynor, reason
`compiler-shaped leftover after exhausted source-shape list`. source-map
relined later `IOParallelPortKern.m` sites (73 mapped / 2 unmapped).

```
_IOParallelPortThread
  status=different raw_equal=False masked_equal=False
  test eax, eax                           test eax, eax
* jz loc_11E8                             jz loc_1900
  cmp eax, 1                              cmp eax, 1
* jz loc_144C                             jnz loc_1B3B
  in al, dx                               in al, dx
* mov [ebp+var_1], al                     mov bl, al
```

### 8.9 The status rule used

- `assembly-matched` (53) - the reference's full instruction stream was read and our
  source is a statement-for-statement transliteration of it with no remaining difference,
  and the function's emitted metadata was verified identical in the rebuilt binary. Used
  for the accessors and the short bodies. Task 8 promoted `msgTypeToIOReturn:`,
  `cmdBufAlloc`, and `_ppstrategy` (`masked_equal`). Task 9 demoted the four
  compiler-shaped skips that stayed `different` on reloc `F31C01A0…`.
- `control-flow-confirmed` (0) - the reference's full instruction stream was read and our
  source reproduces its block structure, every call target and every constant, but the
  rebuilt output was **not** itself disassembled and compared instruction by instruction.
  Used for the larger functions.
- `intentional-mismatch` (22) - a deliberate difference remains: 0 (`_waitForDevice:isReady:`
  for-loop with `tries < busyMaxRetries`; leftover is the `inb` stack slot), 112 and 1452
  (Finding 53, uninitialized control byte reconstructed; leftover is gcc 2.x zero-fill /
  immediate fold), 2372 and 2388 (`struct buf` encoding), 3132 (`printerInit` control byte
  in `bl` vs `[ebp+var_1]`; leftover is gcc 2.x register allocation), 3212
  (`writeToPort` IO_R_IO falls into default; leftover is SUCCESS `jz` vs `jnz`),
  3896 (`cmdBufExec:`
  prev-link stored first; leftover is `add esp,8` scheduling), 4040 (`waitForCmdBuf`
  if/else dequeue; leftover is `add esp,0Ch` scheduling and else-block placement), 4232
  (`_strobeChar` load-then-test reversed; leftover is gcc 2.x CSE / register allocation),
  5520 (`_ppopen` nested signed initDevice range; leftover is `jl` vs `jge`),
  456 (`initFromDeviceDescription:` `minorDevStr` before `configTable`; leftover is
  extra `var_20` / `strcmp` length slot), 4512
  (`_IOParallelPortThread` commandType ==0 write then ==1 exit; leftover is
  `inb` slot vs `bl`), 5240
  (`_IOParallelPortInterruptHandler` decode invert; leftover is `inb` slot vs `dl`), 5828
  (`_ppwrite` signed initDevice range without pre-zeroed locals; leftover is
  `esi` vs `ebx` and Apple's extra zeroing), 6708 (`_ppioctl` signed `int cmd` /
  GET-then-SET grouping; leftover is getter/setter tail-merge),
  7392 and 7404, untouched from the report pass. Task 9 demoted 396
  (`+[IOParallelPort probe:]`, BOOL `setnz` / `and eax, 0FFh` vs `jz` / `mov eax,1` /
  `xor eax,eax`), 2252 and 2320 (`statusRegisterContents` / `controlRegisterContents`,
  reference spills `in al, dx` to `[ebp+var_1]` with `sub esp, 4`; rebuilt leaves the
  byte in `eax`), and 2788 (`isInitialized`, same BOOL materialization as `probe:`).

### Task 9 — four skipped compiler-shaped rows

Task 8 deliberately skipped these four; on final reloc `F31C01A0…` all four remain
`status=different`, `masked_equal=False`. Demoted to `intentional-mismatch`, reviewer
Pat Raynor, reason `compiler-shaped leftover after exhausted source-shape list`.

`--name +[IOParallelPort probe:]` (diff 4): reference `jz` / `mov eax, 1` /
`xor eax, eax`; rebuilt `setnz` / `and eax, 0FFh`.

`--name -[IOParallelPort isInitialized]` (diff 8): reference `jnz` / `mov eax, 1` /
`xor eax, eax`; rebuilt `xor edx, edx` / `jz` / `inc edx` / `mov eax, edx`.

`--name -[IOParallelPort controlRegisterContents]` and
`--name -[IOParallelPort statusRegisterContents]` (diff 2 each): reference
`sub esp, 4` / `in al, dx` / `mov [ebp+var_1], al` / `movzx eax, [ebp+var_1]`;
rebuilt `in al, dx` / `movzx eax, al` with no stack slot.

### Task 10 — tool.make conversion; i386 bootstrap-root link

Nlist on Apple's `InstallPPDev`: `IODeviceMaster` methods are `local` in
`__TEXT,__text`; `__IOGetCharValues` and the rest of the MIG family are
`external` in `__TEXT,__text` (defined, not imports). Took the **local-TU**
path. Replaced the 2180-line invented `IODeviceMaster.m` with a
libDriver-shaped TU. Both tproj Makefiles are PB `tool.make`. IDA-only
profiles: `tools/binrecon/profiles/installppdev.json` and `removeppdev.json`.

Live `/lib/crt1.o` stayed ppc. Tools link with `I386_SYSROOT=/build/bootstrap-root`
and `OTHER_LDFLAGS = -nostdlib $(I386_SYSROOT)/lib/crt1.o -L$(I386_SYSROOT)/usr/lib -F$(I386_SYSROOT)/System/Library/Frameworks -framework System`.
PreLoad does not use `-lDriver`: `driverServer.defs` is compiled into
InstallPPDev (`DEFSFILES` / `OTHER_OFILES = driverServerUser.o`). Makefile
`LIBS` stays empty. Darwin MIG emits `_IOServerConnect` instead of Apple's
`_IOCreateMachPort`. Copied-back nlist:

```
external __TEXT,__text __IOGetCharValues
```

not `external None`. Guest `file`:

```
ParallelPort_reloc: Mach-O preload executable i386
InstallPPDev: Mach-O executable i386
RemovePPDev: Mach-O executable i386
```

Reloc SHA-256 unchanged
`F31C01A0FBB4F010AADC205C8CAE011A501FD6D5016BFCEC10022AA65E2BA9DC`.

### Task 11 — RemovePPDev `_main`

Reference 17272 bytes
(`ADE6C2176D8FDE1EF8AC6EE6A1F3EC72ECC7B7FE74813320AEEF1C12929353A8`).
Rebuilt 21756 bytes
(`BE525C8553C7EC73390AE84BDD4EE4118465BB824827FC1B6DF2B0E1844DC16A`),
Mach-O executable i386. Reloc SHA after the last guest rebuild still
`F31C01A0FBB4F010AADC205C8CAE011A501FD6D5016BFCEC10022AA65E2BA9DC`.

The invented Post-Load main (stack `devicePath[20]`, `"Parallel Port Post-Load"`,
`Instance=%u`, sscanf-return check, two invalid-instance strings) is replaced
with Apple's Pre-Load tool: `PROGRAM_NAME` `"Parallel Port Pre-Load"`, external
`char path[20]`, `"Instance=%d"` / `"%s%s%d"`, one `"%s: invalid instance number\n"`
arm (`cmp [ebp+var_4], 9` / `jbe`), `unlink` then `errno != 2` with `strerror`.

`--name _main` on the kept rebuild: `status=different`, `masked_equal=False`,
diff 35, 105 vs 105. Exhausted allowed source-shape list (for-loop kept;
goto-around-if and while-loop reverted). Accept as compiler-shaped, reviewer
Pat Raynor.

Leftover: reference encodes `if (argc > 1)` as `jg` + `jmp` and parks the
`instanceArg = argv[i]; break;` block in that hole; rebuilt falls through with
`jle`. Same calls and constants. `lea ecx` vs `lea edx` for the loop-invariant
`"Instance="` slot; PIC displacements `3CEEh` vs `3CF2h` follow the extra jmp.

```
_main
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs
  reason: instruction references differ
  reason: instruction semantics differ

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  xor edi, edi                            xor edi, edi
  cmp [ebp+argc], 1                       cmp [ebp+argc], 1
* jg loc_3D04                             jle loc_3D35
* jmp loc_3D41
* mov edx, [ebp+argv]
* mov edi, [edx+ebx*4]
* jmp loc_3D3D
  mov ebx, 1                              mov ebx, 1
  cmp [ebp+argc], ebx                     cmp [ebp+argc], ebx
* jle loc_3D3D                            jle loc_3D35
* lea ecx, (aInstance - 3CEEh)[esi]       lea edx, (aInstance - 3CF2h)[esi]
* mov [ebp+__s2], ecx                     mov [ebp+__s2], edx
  nop                                     nop
* mov edx, [ebp+argv]                     nop
* cmp dword ptr [edx+ebx*4], 0            mov ecx, [ebp+argv]
* jz loc_3D37                             cmp dword ptr [ecx+ebx*4], 0
*                                         jz loc_3D2F
  push 9                                  push 9
* mov ecx, [ebp+__s2]                     mov edx, [ebp+__s2]
*                                         push edx
*                                         mov ecx, [ecx+ebx*4]
  push ecx                                push ecx
* mov edx, [edx+ebx*4]
* push edx
  call _strncmp                           call _strncmp
  add esp, 0Ch                            add esp, 0Ch
  test eax, eax                           test eax, eax
* jz loc_3CFC                             jz loc_3D60
  inc ebx                                 inc ebx
  cmp [ebp+argc], ebx                     cmp [ebp+argc], ebx
* jg loc_3D18                             jg loc_3D10
  test edi, edi                           test edi, edi
  jnz loc_3D68                            jnz loc_3D68
  ... sscanf / invalid instance / bzero(path, 14h) / sprintf / unlink ...
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

## Task 12 — reconstruct InstallPPDev

Reference 37364 bytes, SHA-256
`3B0EECB6934DA0717985C59B2457DE5CD99E4A547E6D8BB074FD05EE63CD9AE5`.
Kept rebuilt 137008 bytes, SHA-256
`BEF20B96FAF67BC488C72B74EAB5FEC4A609877CC03B558013B29D2B47DF7B65`.
Reloc SHA unchanged `F31C01A0FBB4F010AADC205C8CAE011A501FD6D5016BFCEC10022AA65E2BA9DC`.
RemovePPDev SHA unchanged `BE525C8553C7EC73390AE84BDD4EE4118465BB824827FC1B6DF2B0E1844DC16A`
(12 identical / 3 differing / 0 unpaired; `_main` still the only accepted paired row).

`_IOCreateMachPort` wrapper moved to after `@end` so IODeviceMaster methods keep
Apple's text order. Live `--list` pairs `getIntValues:` and `getCharValues:`
again (0-diff each). No `-lDriver`. Defs not subset.

Unpaired Darwin extras (5): `__IOGetByteProperty`, `__IOGetStringPropertyList`,
`__IOLookUpByStringPropertyList`, `__IOServerConnect`, extra `_mig_get_reply_port`.

Live `--list`: `58 functions: 2 byte-identical, 51 differing, 5 unpaired`.
Identical: `-[IODeviceMaster free]`, `start`. Every other paired row accepted
below with full live `--name` dump. Reviewer Pat Raynor.

### Live `--name` dumps (paired leftovers)

+[IODeviceMaster new]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: function range bytes differ
  reason: instruction references differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
* cmp ds:(_thisTasksId - 3D1Dh)[ebx], 0   cmp ds:(_thisTasksId - 34EDh)[ebx], 0
* jnz loc_3D4F                            jnz loc_351F
  mov ecx, ebx                            mov ecx, ebx
* mov ecx, [ecx+42EFh]                    mov ecx, [ecx+4B1Fh]
  push ecx                                push ecx
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  push ecx                                push ecx
  call _objc_msgSend                      call _objc_msgSend
* mov ds:(_thisTasksId - 3D1Dh)[ebx], eax  mov ds:(_thisTasksId - 34EDh)[ebx], eax
  call _device_master_self                call _device_master_self
  mov edx, eax                            mov edx, eax
* mov eax, ds:(_thisTasksId - 3D1Dh)[ebx]  mov eax, ds:(_thisTasksId - 34EDh)[ebx]
  mov [eax+4], edx                        mov [eax+4], edx
* mov eax, ds:(_thisTasksId - 3D1Dh)[ebx]  mov eax, ds:(_thisTasksId - 34EDh)[ebx]
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

-[IODeviceMaster createMachPort:objectNumber:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: function range bytes differ
  reason: instruction references differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOCreateMachPort                 call __IOCreateMachPort
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

-[IODeviceMaster getCharValues:forParameter:objectNumber:count:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: function range bytes differ
  reason: instruction references differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  mov eax, [ebp+arg_14]                   mov eax, [ebp+arg_14]
  push eax                                push eax
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
  mov eax, [eax]                          mov eax, [eax]
  push eax                                push eax
  mov ecx, [ebp+arg_C]                    mov ecx, [ebp+arg_C]
  push ecx                                push ecx
  mov ecx, [ebp+arg_10]                   mov ecx, [ebp+arg_10]
  push ecx                                push ecx
  mov edx, [edx+4]                        mov edx, [edx+4]
  push edx                                push edx
  call __IOGetCharValues                  call __IOGetCharValues
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

-[IODeviceMaster getIntValues:forParameter:objectNumber:count:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: function range bytes differ
  reason: instruction references differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  mov eax, [ebp+arg_14]                   mov eax, [ebp+arg_14]
  push eax                                push eax
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
  mov eax, [eax]                          mov eax, [eax]
  push eax                                push eax
  mov ecx, [ebp+arg_C]                    mov ecx, [ebp+arg_C]
  push ecx                                push ecx
  mov ecx, [ebp+arg_10]                   mov ecx, [ebp+arg_10]
  push ecx                                push ecx
  mov edx, [edx+4]                        mov edx, [edx+4]
  push edx                                push edx
  call __IOGetIntValues                   call __IOGetIntValues
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

-[IODeviceMaster lookUpByDeviceName:objectNumber:deviceKind:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: function range bytes differ
  reason: instruction references differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOLookupByDeviceName             call __IOLookupByDeviceName
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

-[IODeviceMaster lookUpByObjectNumber:deviceKind:deviceName:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: function range bytes differ
  reason: instruction references differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOLookupByObjectNumber           call __IOLookupByObjectNumber
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

-[IODeviceMaster setCharValues:forParameter:objectNumber:count:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: function range bytes differ
  reason: instruction references differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_14]                   mov edx, [ebp+arg_14]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOSetCharValues                  call __IOSetCharValues
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

-[IODeviceMaster setIntValues:forParameter:objectNumber:count:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: function range bytes differ
  reason: instruction references differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_14]                   mov edx, [ebp+arg_14]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOSetIntValues                   call __IOSetIntValues
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOCallDeviceMethod
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 888h                           sub esp, 88Ch
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_884]                       pop [ebp+var_884]
* mov ebx, [ebp+arg_10]                   lea edx, [ebp+var_880]
* lea esi, [ebp+var_880]                  mov [ebp+var_888], edx
* mov [ebp+var_888], esi                  mov ebx, [ebp+var_888]
* mov edi, [ebp+var_884]                  mov [ebp+var_88C], 80h
* mov edi, [ebp+var_884]                  mov ecx, [ebp+var_884]
* mov edi, [edi+803h]                     mov ecx, [ebp+var_884]
* mov [ebp+var_868], edi                  mov ecx, [ecx+0E93h]
* mov esi, [ebp+arg_4]                    mov [ebp+var_868], ecx
* mov [ebp+var_864], esi                  mov edx, [ebp+arg_4]
* mov edi, [ebp+var_884]                  mov [ebp+var_864], edx
* mov edi, [ebp+var_884]                  mov ecx, [ebp+var_884]
* mov edi, [edi+807h]                     mov ecx, [ebp+var_884]
* mov [ebp+var_860], edi                  mov ecx, [ecx+0E97h]
* lea edx, [ebp+var_85C]                  mov [ebp+var_860], ecx
* mov eax, [ebp+arg_8]                    lea edi, [ebp+var_85C]
* mov edi, edx                            mov esi, [ebp+arg_8]
* mov esi, eax
  cld                                     cld
  mov ecx, 14h                            mov ecx, 14h
  movsd                                   movsd
* mov esi, [ebp+var_884]                  mov edx, [ebp+var_884]
* mov esi, [ebp+var_884]                  mov edx, [ebp+var_884]
* mov esi, [esi+80Bh]                     mov edx, [edx+0E9Bh]
* mov [ebp+var_80C], esi                  mov [ebp+var_80C], edx
* cmp ebx, 800h                           cmp [ebp+arg_10], 800h
* ja loc_5A69                             ja loc_53DA
* push ebx                                mov ecx, [ebp+arg_10]
* lea eax, [ebp+var_808]                  push ecx
*                                         lea eax, [ebx+78h]
  push eax                                push eax
* mov edi, [ebp+arg_C]                    mov edx, [ebp+arg_C]
* push edi                                push edx
  call _bcopy                             call _bcopy
* mov edx, ebx                            mov ax, word ptr [ebp+arg_10]
* and dh, 0Fh                             and ah, 0Fh
* mov ax, word ptr [ebp+var_80C+2]        and word ptr [ebx+76h], 0F000h
* and ax, 0F000h                          or [ebx+76h], ax
* or ax, dx                               mov eax, [ebp+arg_10]
* mov word ptr [ebp+var_80C+2], ax        add eax, 3
* lea eax, [ebx+3]                        and al, 0FCh
* mov edx, eax                            lea ebx, [eax+ebx-800h]
* and dl, 0FCh                            mov ecx, [ebp+var_884]
* mov eax, [ebp+var_888]                  mov ecx, [ebp+var_884]
* add eax, edx                            mov ecx, [ecx+0E9Fh]
* mov esi, [ebp+var_884]                  mov [ebx+878h], ecx
* mov esi, [ebp+var_884]                  mov edx, [ebp+arg_14]
* mov esi, [esi+80Fh]                     mov edx, [edx]
* mov [eax+78h], esi                      mov [ebx+87Ch], edx
* mov edi, [ebp+arg_14]                   lea ebx, [ebp+var_880]
* mov edi, [edi]
* mov [eax+7Ch], edi
  mov [ebp+var_87D], 1                    mov [ebp+var_87D], 1
* add edx, 80h                            add eax, [ebp+var_88C]
* mov [ebp+var_87C], edx                  mov [ebp+var_87C], eax
  mov [ebp+var_878], 100h                 mov [ebp+var_878], 100h
* mov esi, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
* mov [ebp+var_870], esi                  mov [ebp+var_870], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_874], eax                  mov [ebp+var_874], eax
  mov [ebp+var_86C], 0AB3h                mov [ebp+var_86C], 0AB3h
  push 0                                  push 0
  push 0                                  push 0
  push 82Ch                               push 82Ch
  push 0                                  push 0
* mov edi, [ebp+var_888]                  push ebx
* push edi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 20h                            add esp, 20h
  test ebx, ebx                           test ebx, ebx
* jz loc_5928                             jz loc_5270
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_5920                            jnz loc_5266
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_5A6E                            jmp loc_53DF
* mov ebx, [ebp+var_87C]                  mov edx, [ebp+var_888]
* movzx edx, [ebp+var_87D]                mov edx, [edx+4]
* cmp [ebp+var_86C], 0B17h                mov [ebp+var_88C], edx
* jz loc_594C                             mov ecx, [ebp+var_888]
*                                         movzx ebx, byte ptr [ecx+3]
*                                         cmp dword ptr [ecx+14h], 0B17h
*                                         jz loc_529C
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_5A6E                            jmp loc_53DF
* lea eax, [ebx-2Ch]                      mov eax, [ebp+var_88C]
*                                         add eax, 0FFFFFFD4h
  cmp eax, 800h                           cmp eax, 800h
* ja loc_595B                             ja loc_52B1
* cmp edx, 1                              cmp ebx, 1
* jz loc_597A                             jz loc_52D7
* cmp ebx, 20h                            cmp [ebp+var_88C], 20h
* jnz loc_59FB                            jnz loc_535D
* cmp edx, 1                              cmp ebx, 1
* jnz loc_59FB                            jnz loc_535D
* cmp [ebp+var_864], 0                    mov edx, [ebp+var_888]
* jz loc_59FB                             cmp dword ptr [edx+1Ch], 0
* mov esi, [ebp+var_884]                  jz loc_535D
* mov eax, [esi+813h]                     mov ecx, [ebp+var_888]
* mov edi, [ebp+var_888]                  mov eax, [ecx+18h]
* cmp [edi+18h], eax                      mov edx, [ebp+var_884]
* jnz loc_59FB                            cmp [edx+0EA3h], eax
* mov esi, [ebp+var_888]                  jnz loc_535D
* mov eax, [esi+1Ch]                      mov ecx, [ebp+var_888]
* test eax, eax                           cmp dword ptr [ecx+1Ch], 0
* jnz loc_5A6E                            jz loc_5304
* mov edi, [ebp+var_884]                  mov eax, [ecx+1Ch]
* mov eax, [edi+817h]                     jmp loc_53DF
* mov esi, [ebp+var_888]                  mov edx, [ebp+var_888]
* cmp [esi+20h], eax                      mov eax, [edx+20h]
* jnz loc_59FB                            mov ecx, [ebp+var_884]
* mov edi, [ebp+var_888]                  cmp [ecx+0EA7h], eax
* mov esi, [edi+24h]                      jnz loc_535D
* mov edi, [ebp+arg_14]                   mov edx, [ebp+var_888]
* mov [edi], esi                          mov ecx, [edx+24h]
* mov edi, [ebp+var_888]                  mov edx, [ebp+arg_14]
* mov eax, [edi+28h]                      mov [edx], ecx
*                                         mov edx, [ebp+var_888]
*                                         mov eax, [edx+28h]
  and eax, 3000FFFFh                      and eax, 3000FFFFh
  cmp eax, 10000808h                      cmp eax, 10000808h
* jnz loc_59FB                            jnz loc_535D
* mov esi, [ebp+var_888]                  mov ecx, [ebp+var_888]
* mov cx, [esi+2Ah]                       mov ax, [ecx+2Ah]
* and ecx, 0FFFh                          and eax, 0FFFh
* lea eax, [ecx+3]                        add eax, 3
* mov edx, eax                            and al, 0FCh
* and dl, 0FCh                            add eax, 2Ch
* lea eax, [edx+2Ch]                      cmp [ebp+var_88C], eax
* cmp ebx, eax                            jz loc_5364
* jz loc_5A04
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_5A6E                            jmp loc_53DF
* mov edi, [ebp+arg_1C]                   mov edx, [ebp+var_888]
* mov eax, [edi]                          mov ax, [edx+2Ah]
* cmp ecx, eax                            and eax, 0FFFh
* ja loc_5A40                             mov ecx, [ebp+arg_1C]
* push ecx                                cmp [ecx], eax
* mov esi, [ebp+arg_18]                   jb loc_53AC
* push esi                                push eax
*                                         mov edx, [ebp+arg_18]
*                                         push edx
  mov eax, [ebp+var_888]                  mov eax, [ebp+var_888]
  add eax, 2Ch                            add eax, 2Ch
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov edi, [ebp+var_888]                  mov ecx, [ebp+var_888]
* mov si, [edi+2Ah]                       mov dx, [ecx+2Ah]
* and esi, 0FFFh                          and edx, 0FFFh
* mov edi, [ebp+arg_1C]                   mov ecx, [ebp+arg_1C]
* mov [edi], esi                          mov [ecx], edx
  mov eax, [ebp+var_864]                  mov eax, [ebp+var_864]
* jmp loc_5A6E                            jmp loc_53DF
* push eax                                mov ecx, [ebp+arg_1C]
* mov edi, [ebp+arg_18]                   mov ecx, [ecx]
* push edi                                push ecx
*                                         mov edx, [ebp+arg_18]
*                                         push edx
  mov eax, [ebp+var_888]                  mov eax, [ebp+var_888]
  add eax, 2Ch                            add eax, 2Ch
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov esi, [ebp+var_888]                  mov ecx, [ebp+var_888]
* mov di, [esi+2Ah]                       mov dx, [ecx+2Ah]
* and edi, 0FFFh                          and edx, 0FFFh
* mov esi, [ebp+arg_1C]                   mov ecx, [ebp+arg_1C]
* mov [esi], edi                          mov [ecx], edx
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
* lea esp, [ebp-894h]                     lea esp, [ebp-898h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOCreateMachPort
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 28h
* push edi
  push esi                                push esi
  push ebx                                push ebx
* call $+5                                mov esi, [ebp+arg_0]
* pop edi                                 mov ebx, [ebp+arg_4]
* lea esi, [ebp+var_28]                   mov edx, [ebp+arg_8]
* mov edx, edi                            push edx
* mov edx, [edx+56Ah]                     call _task_self
* mov [ebp+var_10], edx                   push eax
* mov ecx, [ebp+arg_4]                    push ebx
* mov [ebp+var_C], ecx
* mov [ebp+var_25], 1
* mov [ebp+var_24], 20h
* mov [ebp+var_20], 100h
* mov edx, [ebp+arg_0]
* mov [ebp+var_18], edx
* call _mig_get_reply_port
* mov [ebp+var_1C], eax
* mov [ebp+var_14], 0AB4h
* push 0
* push 0
* push 28h
* push 0
  push esi                                push esi
* call _msg_rpc                           call __IOServerConnect
* mov ebx, eax                            lea esp, [ebp-8]
* add esp, 14h
* test ebx, ebx
* jz loc_5AF0
* cmp ebx, 0FFFFFF36h
* jnz loc_5AEA
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_5B51
* mov ebx, [ebp+var_24]
* movzx eax, [ebp+var_25]
* cmp [ebp+var_14], 0B18h
* jz loc_5B08
* mov eax, 0FFFFFED3h
* jmp loc_5B51
* cmp ebx, 28h
* jnz loc_5B11
* test eax, eax
* jz loc_5B21
* cmp ebx, 20h
* jnz loc_5B4C
* cmp eax, 1
* jnz loc_5B4C
* cmp [ebp+var_C], 0
* jz loc_5B4C
* mov eax, ds:(_RetCodeCheck_184 - 5A8Ah)[edi]
* cmp [esi+18h], eax
* jnz loc_5B4C
* mov eax, [esi+1Ch]
* test eax, eax
* jnz loc_5B51
* mov eax, ds:(_machPortCheck_185 - 5A8Ah)[edi]
* cmp [esi+20h], eax
* jnz loc_5B4C
* mov edx, [esi+24h]
* mov ecx, [ebp+arg_8]
* mov [ecx], edx
* mov eax, [esi+1Ch]
* jmp loc_5B51
* mov eax, 0FFFFFED4h
* lea esp, [ebp-34h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOGetCharValues
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 22Ch                           sub esp, 22Ch
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_228]                       pop [ebp+var_228]
* lea esi, [ebp+var_224]                  lea ecx, [ebp+var_224]
* mov [ebp+var_22C], esi                  mov [ebp+var_22C], ecx
  mov edi, [ebp+var_228]                  mov edi, [ebp+var_228]
  mov edi, [ebp+var_228]                  mov edi, [ebp+var_228]
* mov edi, [edi+1BEFh]                    mov edi, [edi+2333h]
  mov [ebp+var_20C], edi                  mov [ebp+var_20C], edi
* mov esi, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
* mov [ebp+var_208], esi                  mov [ebp+var_208], ecx
  mov edi, [ebp+var_228]                  mov edi, [ebp+var_228]
  mov edi, [ebp+var_228]                  mov edi, [ebp+var_228]
* mov edi, [edi+1BF3h]                    mov edi, [edi+2337h]
  mov [ebp+var_204], edi                  mov [ebp+var_204], edi
* lea edx, [ebp+var_200]                  lea eax, [ebp+var_200]
* mov eax, [ebp+arg_8]                    mov esi, [ebp+arg_8]
* mov edi, edx                            mov edi, eax
* mov esi, eax
  cld                                     cld
  mov ecx, 10h                            mov ecx, 10h
  movsd                                   movsd
* mov esi, [ebp+var_228]                  mov ecx, [ebp+var_228]
* mov esi, [ebp+var_228]                  mov ecx, [ebp+var_228]
* mov esi, [esi+1BF7h]                    mov ecx, [ecx+233Bh]
* mov [ebp+var_1C0], esi                  mov [ebp+var_1C0], ecx
  mov edi, [ebp+arg_C]                    mov edi, [ebp+arg_C]
  mov [ebp+var_1BC], edi                  mov [ebp+var_1BC], edi
  mov [ebp+var_221], 1                    mov [ebp+var_221], 1
  mov [ebp+var_220], 6Ch                  mov [ebp+var_220], 6Ch
  mov [ebp+var_21C], 100h                 mov [ebp+var_21C], 100h
* mov esi, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
* mov [ebp+var_214], esi                  mov [ebp+var_214], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_218], eax                  mov [ebp+var_218], eax
  mov [ebp+var_210], 0AA1h                mov [ebp+var_210], 0AA1h
  push 0                                  push 0
  push 0                                  push 0
  push 224h                               push 224h
  push 0                                  push 0
  mov edi, [ebp+var_22C]                  mov edi, [ebp+var_22C]
  push edi                                push edi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_4418                             jz loc_3CA4
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_4410                            jnz loc_3C9A
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_452A                            jmp loc_3DC7
* mov ecx, [ebp+var_220]                  mov ecx, [ebp+var_22C]
* movzx edx, [ebp+var_221]                mov edx, [ecx+4]
* cmp [ebp+var_210], 0B05h                movzx ebx, byte ptr [ecx+3]
* jz loc_443C                             cmp dword ptr [ecx+14h], 0B05h
*                                         jz loc_3CC4
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_452A                            jmp loc_3DC7
* lea eax, [ecx-24h]                      lea eax, [edx-24h]
  cmp eax, 200h                           cmp eax, 200h
* ja loc_444B                             ja loc_3CD3
* cmp edx, 1                              cmp ebx, 1
* jz loc_445E                             jz loc_3CE9
* cmp ecx, 20h                            cmp edx, 20h
* jnz loc_44B7                            jnz loc_3D44
* cmp edx, 1                              cmp ebx, 1
* jnz loc_44B7                            jnz loc_3D44
* cmp [ebp+var_208], 0
* jz loc_44B7
* mov esi, [ebp+var_228]
* mov eax, [esi+1BFBh]
  mov edi, [ebp+var_22C]                  mov edi, [ebp+var_22C]
* cmp [edi+18h], eax                      cmp dword ptr [edi+1Ch], 0
* jnz loc_44B7                            jz loc_3D44
* mov esi, [ebp+var_22C]                  mov ecx, [ebp+var_22C]
* mov eax, [esi+1Ch]                      mov eax, [ecx+18h]
* test eax, eax                           mov edi, [ebp+var_228]
* jnz loc_452A                            cmp [edi+233Fh], eax
*                                         jnz loc_3D44
*                                         mov ecx, [ebp+var_22C]
*                                         cmp dword ptr [ecx+1Ch], 0
*                                         jz loc_3D14
*                                         mov eax, [ecx+1Ch]
*                                         jmp loc_3DC7
  mov edi, [ebp+var_22C]                  mov edi, [ebp+var_22C]
  mov eax, [edi+20h]                      mov eax, [edi+20h]
  and eax, 3000FFFFh                      and eax, 3000FFFFh
  cmp eax, 10000808h                      cmp eax, 10000808h
* jnz loc_44B7                            jnz loc_3D44
* mov esi, [ebp+var_22C]                  mov ecx, [ebp+var_22C]
* mov dx, [esi+22h]                       mov ax, [ecx+22h]
* and edx, 0FFFh                          and eax, 0FFFh
* lea eax, [edx+3]                        add eax, 3
  and al, 0FCh                            and al, 0FCh
  add eax, 24h                            add eax, 24h
* cmp ecx, eax                            cmp edx, eax
* jz loc_44C0                             jz loc_3D4C
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_452A                            jmp loc_3DC7
* mov edi, [ebp+arg_14]
* mov eax, [edi]
* cmp edx, eax
* ja loc_44FC
* push edx
* mov esi, [ebp+arg_10]
* push esi
* mov eax, [ebp+var_22C]
* add eax, 24h
* push eax
* call _bcopy
  mov edi, [ebp+var_22C]                  mov edi, [ebp+var_22C]
* mov si, [edi+22h]                       mov ax, [edi+22h]
* and esi, 0FFFh                          and eax, 0FFFh
* mov edi, [ebp+arg_14]                   mov ecx, [ebp+arg_14]
* mov [edi], esi                          cmp [ecx], eax
* mov eax, [ebp+var_208]                  jb loc_3D94
* jmp loc_452A
  push eax                                push eax
  mov edi, [ebp+arg_10]                   mov edi, [ebp+arg_10]
  push edi                                push edi
  mov eax, [ebp+var_22C]                  mov eax, [ebp+var_22C]
  add eax, 24h                            add eax, 24h
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov esi, [ebp+var_22C]                  mov ecx, [ebp+var_22C]
* mov di, [esi+22h]                       mov di, [ecx+22h]
  and edi, 0FFFh                          and edi, 0FFFh
* mov esi, [ebp+arg_14]                   mov ecx, [ebp+arg_14]
* mov [esi], edi                          mov [ecx], edi
*                                         mov eax, [ebp+var_208]
*                                         jmp loc_3DC7
*                                         mov ecx, [ebp+arg_14]
*                                         mov ecx, [ecx]
*                                         push ecx
*                                         mov edi, [ebp+arg_10]
*                                         push edi
*                                         mov eax, [ebp+var_22C]
*                                         add eax, 24h
*                                         push eax
*                                         call _bcopy
*                                         mov ecx, [ebp+var_22C]
*                                         mov di, [ecx+22h]
*                                         and edi, 0FFFh
*                                         mov ecx, [ebp+arg_14]
*                                         mov [ecx], edi
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
  lea esp, [ebp-238h]                     lea esp, [ebp-238h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOGetDriverConfig
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 102Ch                          sub esp, 1030h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop edi                                 pop edi
  lea esi, [ebp+var_102C]                 lea esi, [ebp+var_102C]
* mov ecx, edi                            mov edx, edi
* mov ecx, [ecx+0D3Fh]                    mov edx, [edx+1407h]
* mov [ebp+var_1014], ecx                 mov [ebp+var_1014], edx
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  mov [ebp+var_1010], ecx                 mov [ebp+var_1010], ecx
* mov ecx, edi                            mov edx, edi
* mov ecx, [ecx+0D43h]                    mov edx, [edx+140Bh]
* mov [ebp+var_100C], ecx                 mov [ebp+var_100C], edx
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov [ebp+var_1008], ecx                 mov [ebp+var_1008], ecx
  mov [ebp+var_1029], 1                   mov [ebp+var_1029], 1
  mov [ebp+var_1028], 28h                 mov [ebp+var_1028], 28h
  mov [ebp+var_1024], 100h                mov [ebp+var_1024], 100h
* mov ecx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
* mov [ebp+var_101C], ecx                 mov [ebp+var_101C], edx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_1020], eax                 mov [ebp+var_1020], eax
  mov [ebp+var_1018], 0AADh               mov [ebp+var_1018], 0AADh
  push 0                                  push 0
  push 0                                  push 0
  push 102Ch                              push 102Ch
  push 0                                  push 0
  push esi                                push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_5304                             jz loc_4C0C
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_52FA                            jnz loc_4C02
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_53C7                            jmp loc_4CE0
* mov ebx, [ebp+var_1028]                 mov ecx, [esi+4]
* movzx edx, [ebp+var_1029]               mov [ebp+var_1030], ecx
* cmp [ebp+var_1018], 0B11h               movzx ebx, byte ptr [esi+3]
* jz loc_5328                             cmp dword ptr [esi+14h], 0B11h
*                                         jz loc_4C2C
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_53C7                            jmp loc_4CE0
* lea eax, [ebx-2Ch]                      mov eax, [ebp+var_1030]
*                                         add eax, 0FFFFFFD4h
  cmp eax, 1000h                          cmp eax, 1000h
* ja loc_5337                             ja loc_4C41
* cmp edx, 1                              cmp ebx, 1
* jz loc_534A                             jz loc_4C55
* cmp ebx, 20h                            cmp [ebp+var_1030], 20h
* jnz loc_537D                            jnz loc_4C91
* cmp edx, 1                              cmp ebx, 1
* jnz loc_537D                            jnz loc_4C91
* cmp [ebp+var_1010], 0                   cmp dword ptr [esi+1Ch], 0
* jz loc_537D                             jz loc_4C91
* mov eax, ds:(_RetCodeCheck_151 - 5265h)[edi]  mov eax, [esi+18h]
* cmp [esi+18h], eax                      cmp ds:(_RetCodeCheck_151 - 4B6Dh)[edi], eax
* jnz loc_537D                            jnz loc_4C91
*                                         cmp dword ptr [esi+1Ch], 0
*                                         jz loc_4C6C
  mov eax, [esi+1Ch]                      mov eax, [esi+1Ch]
* test eax, eax                           jmp loc_4CE0
* jnz loc_53C7
  mov al, [esi+23h]                       mov al, [esi+23h]
  and al, 30h                             and al, 30h
  cmp al, 30h                             cmp al, 30h
* jnz loc_537D                            jnz loc_4C91
  cmp dword ptr [esi+24h], 80008h         cmp dword ptr [esi+24h], 80008h
* jnz loc_537D                            jnz loc_4C91
* mov edx, [esi+28h]                      mov eax, [esi+28h]
* lea eax, [edx+3]                        add eax, 3
  and al, 0FCh                            and al, 0FCh
  add eax, 2Ch                            add eax, 2Ch
* cmp ebx, eax                            cmp [ebp+var_1030], eax
* jz loc_5384                             jz loc_4C98
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_53C7                            jmp loc_4CE0
* mov ecx, [ebp+arg_10]                   mov eax, [esi+28h]
* mov eax, [ecx]                          mov edx, [ebp+arg_10]
* cmp edx, eax                            cmp [edx], eax
* ja loc_53AC                             jb loc_4CC0
* push edx
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, [esi+2Ch]
* push eax
* call _bcopy
* mov esi, [esi+28h]
* mov ecx, [ebp+arg_10]
* mov [ecx], esi
* mov eax, [ebp+var_1010]
* jmp loc_53C7
  push eax                                push eax
  mov ecx, [ebp+arg_C]                    mov ecx, [ebp+arg_C]
  push ecx                                push ecx
  lea eax, [esi+2Ch]                      lea eax, [esi+2Ch]
  push eax                                push eax
  call _bcopy                             call _bcopy
  mov esi, [esi+28h]                      mov esi, [esi+28h]
*                                         mov edx, [ebp+arg_10]
*                                         mov [edx], esi
*                                         mov eax, [ebp+var_1010]
*                                         jmp loc_4CE0
*                                         mov ecx, [ebp+arg_10]
*                                         mov ecx, [ecx]
*                                         push ecx
*                                         mov edx, [ebp+arg_C]
*                                         push edx
*                                         lea eax, [esi+2Ch]
*                                         push eax
*                                         call _bcopy
*                                         mov esi, [esi+28h]
  mov ecx, [ebp+arg_10]                   mov ecx, [ebp+arg_10]
  mov [ecx], esi                          mov [ecx], esi
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
* lea esp, [ebp-1038h]                    lea esp, [ebp-103Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOGetEISADeviceConfig
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 150h                           sub esp, 148h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_148]                       pop [ebp+var_148]
* mov esi, [ebp+arg_8]                    lea ebx, [ebp+var_144]
* lea edi, [ebp+var_144]
  mov [ebp+var_141], 1                    mov [ebp+var_141], 1
  mov [ebp+var_140], 18h                  mov [ebp+var_140], 18h
  mov [ebp+var_13C], 100h                 mov [ebp+var_13C], 100h
* mov ecx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
* mov [ebp+var_134], ecx                  mov [ebp+var_134], edx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_138], eax                  mov [ebp+var_138], eax
  mov [ebp+var_130], 0AA4h                mov [ebp+var_130], 0AA4h
  push 0                                  push 0
  push 0                                  push 0
  push 144h                               push 144h
  push 0                                  push 0
* push edi                                push ebx
  call _msg_rpc                           call _msg_rpc
* mov ebx, eax                            mov esi, eax
  add esp, 14h                            add esp, 14h
* test ebx, ebx                           test esi, esi
* jz loc_48F8                             jz loc_41B0
* cmp ebx, 0FFFFFF36h                     cmp esi, 0FFFFFF36h
* jnz loc_48F0                            jnz loc_41A9
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
* mov eax, ebx                            mov eax, esi
* jmp loc_4BB6                            jmp loc_44A1
* mov ecx, [ebp+var_140]                  mov edi, [ebx+4]
* mov [ebp+var_150], ecx                  movzx esi, byte ptr [ebx+3]
* movzx edx, [ebp+var_141]                cmp dword ptr [ebx+14h], 0B08h
* cmp [ebp+var_130], 0B08h                jz loc_41CC
* jz loc_4924
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_4BB6                            jmp loc_44A1
* mov eax, [ebp+var_150]                  lea eax, [edi-30h]
* add eax, 0FFFFFFD0h
  cmp eax, 114h                           cmp eax, 114h
* ja loc_4939                             ja loc_41DB
* cmp edx, 1                              cmp esi, 1
* jz loc_495C                             jz loc_41F7
* cmp [ebp+var_150], 20h                  cmp edi, 20h
* jnz loc_4B4F                            jnz loc_4416
* cmp edx, 1                              cmp esi, 1
* jnz loc_4B4F                            jnz loc_4416
* cmp [ebp+var_128], 0                    cmp dword ptr [ebx+1Ch], 0
* jz loc_4B4F                             jz loc_4416
*                                         mov eax, [ebx+18h]
  mov ecx, [ebp+var_148]                  mov ecx, [ebp+var_148]
* mov eax, [ecx+16C7h]                    cmp [ecx+1DDBh], eax
* cmp [edi+18h], eax                      jnz loc_4416
* jnz loc_4B4F                            cmp dword ptr [ebx+1Ch], 0
* mov eax, [edi+1Ch]                      jz loc_421C
* test eax, eax                           mov eax, [ebx+1Ch]
* jnz loc_4BB6                            jmp loc_44A1
* mov eax, [edi+20h]                      mov eax, [ebx+20h]
  and eax, 3000FFFFh                      and eax, 3000FFFFh
  cmp eax, 10002002h                      cmp eax, 10002002h
* jnz loc_4B4F                            jnz loc_4416
* mov dx, [edi+22h]                       mov si, [ebx+22h]
* and edx, 0FFFh                          and esi, 0FFFh
* lea ebx, ds:0[edx*4]                    shl esi, 2
* lea eax, [ebx+30h]                      lea eax, [esi+30h]
* cmp [ebp+var_150], eax                  cmp edi, eax
* jb loc_4B4F                             jb loc_4416
* sub [ebp+var_150], ebx                  sub edi, esi
* mov eax, [esi]                          mov ax, [ebx+22h]
* cmp edx, eax                            and eax, 0FFFh
* jbe loc_49E0                            mov edx, [ebp+arg_8]
*                                         cmp [edx], eax
*                                         jnb loc_4284
*                                         mov ecx, [edx]
*                                         lea eax, ds:0[ecx*4]
*                                         push eax
*                                         mov edx, [ebp+arg_4]
*                                         push edx
*                                         lea eax, [ebx+24h]
*                                         push eax
*                                         call _bcopy
*                                         mov bx, [ebx+22h]
*                                         and ebx, 0FFFh
*                                         mov ecx, [ebp+arg_8]
*                                         mov [ecx], ebx
*                                         jmp loc_449C
*                                         mov ax, [ebx+22h]
*                                         and eax, 0FFFh
  shl eax, 2                              shl eax, 2
  push eax                                push eax
* mov ecx, [ebp+arg_4]                    mov edx, [ebp+arg_4]
* push ecx                                push edx
* lea eax, [edi+24h]                      lea eax, [ebx+24h]
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov di, [edi+22h]                       mov dx, [ebx+22h]
* and edi, 0FFFh                          and edx, 0FFFh
* mov [esi], edi                          mov ecx, [ebp+arg_8]
* jmp loc_4BB1                            mov [ecx], edx
* push ebx                                lea ebx, [esi+ebx-1Ch]
* mov ecx, [ebp+arg_4]                    mov eax, [ebx+40h]
* push ecx
* lea eax, [edi+24h]
* push eax
* call _bcopy
* mov cx, [edi+22h]
* and ecx, 0FFFh
* mov [esi], ecx
* lea esi, [ebx+edi]
* lea edi, [esi-1Ch]
* mov eax, [esi+24h]
  and eax, 3000FFFFh                      and eax, 3000FFFFh
  add esp, 0Ch                            add esp, 0Ch
  cmp eax, 10002002h                      cmp eax, 10002002h
* jnz loc_4B4F                            jnz loc_4416
* mov dx, [esi+26h]                       mov si, [ebx+42h]
* and edx, 0FFFh                          and esi, 0FFFh
* lea ebx, ds:0[edx*4]                    shl esi, 2
* lea eax, [ebx+30h]                      lea eax, [esi+30h]
* cmp [ebp+var_150], eax                  cmp edi, eax
* jb loc_4B4F                             jb loc_4416
* sub [ebp+var_150], ebx                  sub edi, esi
*                                         mov ax, [ebx+42h]
*                                         and eax, 0FFFh
  mov ecx, [ebp+arg_10]                   mov ecx, [ebp+arg_10]
* mov eax, [ecx]                          cmp [ecx], eax
* cmp edx, eax                            jnb loc_431C
* jbe loc_4A6C                            mov edx, [ecx]
*                                         lea eax, ds:0[edx*4]
*                                         push eax
*                                         mov ecx, [ebp+arg_C]
*                                         push ecx
*                                         lea eax, [ebx+44h]
*                                         push eax
*                                         call _bcopy
*                                         mov bx, [ebx+42h]
*                                         and ebx, 0FFFh
*                                         mov edx, [ebp+arg_10]
*                                         mov [edx], ebx
*                                         jmp loc_449C
*                                         mov ax, [ebx+42h]
*                                         and eax, 0FFFh
  shl eax, 2                              shl eax, 2
  push eax                                push eax
  mov ecx, [ebp+arg_C]                    mov ecx, [ebp+arg_C]
  push ecx                                push ecx
* lea eax, [esi+28h]                      lea eax, [ebx+44h]
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov si, [esi+26h]                       mov cx, [ebx+42h]
* and esi, 0FFFh                          and ecx, 0FFFh
* mov ecx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
* mov [ecx], esi                          mov [edx], ecx
* jmp loc_4BB1                            lea ebx, [esi+ebx-10h]
* push ebx                                mov eax, [ebx+54h]
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, [esi+28h]
* push eax
* call _bcopy
* mov si, [esi+26h]
* and esi, 0FFFh
* mov ecx, [ebp+arg_10]
* mov [ecx], esi
* lea esi, [ebx+edi]
* lea edi, [esi-10h]
* mov eax, [esi+44h]
  and eax, 3000FFFFh                      and eax, 3000FFFFh
  add esp, 0Ch                            add esp, 0Ch
  cmp eax, 10002002h                      cmp eax, 10002002h
* jnz loc_4B4F                            jnz loc_4416
* mov dx, [esi+46h]                       mov si, [ebx+56h]
* and edx, 0FFFh                          and esi, 0FFFh
* lea ebx, ds:0[edx*4]                    shl esi, 2
* lea eax, [ebx+30h]                      lea eax, [esi+30h]
* cmp [ebp+var_150], eax                  cmp edi, eax
* jb loc_4B4F                             jb loc_4416
* sub [ebp+var_150], ebx                  sub edi, esi
* mov eax, edx                            mov ax, [ebx+56h]
* shr eax, 1                              and eax, 0FFFh
* mov ecx, [ebp+arg_18]                   sar eax, 1
* mov edx, [ecx]                          mov edx, [ebp+arg_18]
* cmp eax, edx                            cmp [edx], eax
* jbe loc_4B00                            jnb loc_43B8
* lea eax, ds:0[edx*8]                    mov ecx, [edx]
*                                         lea eax, ds:0[ecx*8]
  push eax                                push eax
* mov ecx, [ebp+arg_14]                   mov edx, [ebp+arg_14]
* push ecx                                push edx
* lea eax, [esi+48h]                      lea eax, [ebx+58h]
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov ax, [esi+46h]                       mov ax, [ebx+56h]
  and eax, 0FFFh                          and eax, 0FFFh
* shr eax, 1                              sar eax, 1
  mov ecx, [ebp+arg_18]                   mov ecx, [ebp+arg_18]
* jmp loc_4BAF                            jmp loc_449A
* push ebx                                mov ax, [ebx+56h]
* mov ecx, [ebp+arg_14]                   and eax, 0FFFh
* push ecx                                shl eax, 2
* lea eax, [esi+48h]                      push eax
*                                         mov edx, [ebp+arg_14]
*                                         push edx
*                                         lea eax, [ebx+58h]
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov ax, [esi+46h]                       mov ax, [ebx+56h]
  and eax, 0FFFh                          and eax, 0FFFh
* shr eax, 1                              sar eax, 1
  mov ecx, [ebp+arg_18]                   mov ecx, [ebp+arg_18]
  mov [ecx], eax                          mov [ecx], eax
* lea esi, [ebx+edi]                      lea ebx, [esi+ebx-0A0h]
* mov eax, [esi+58h]                      mov eax, [ebx+0F8h]
  and eax, 3000FFFFh                      and eax, 3000FFFFh
  add esp, 0Ch                            add esp, 0Ch
  cmp eax, 10002002h                      cmp eax, 10002002h
* jnz loc_4B4F                            jnz loc_4416
* mov dx, [esi+5Ah]                       mov si, [ebx+0FAh]
* and edx, 0FFFh                          and esi, 0FFFh
* lea ebx, ds:0[edx*4]                    lea eax, ds:30h[esi*4]
* lea eax, [ebx+30h]                      cmp edi, eax
* cmp [ebp+var_150], eax                  jz loc_4420
* jz loc_4B58
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_4BB6                            jmp loc_44A1
* mov eax, edx                            mov si, [ebx+0FAh]
*                                         and esi, 0FFFh
*                                         mov eax, esi
  shr eax, 1                              shr eax, 1
* mov ecx, [ebp+arg_20]                   mov edx, [ebp+arg_20]
* mov edx, [ecx]                          cmp [edx], eax
* cmp eax, edx                            jb loc_446C
* ja loc_4B8C                             lea eax, ds:0[esi*4]
* push ebx
* mov ecx, [ebp+arg_1C]
* push ecx
* lea eax, [esi+5Ch]
* push eax
* call _bcopy
* mov ax, [esi+5Ah]
* and eax, 0FFFh
* shr eax, 1
* mov ecx, [ebp+arg_20]
* mov [ecx], eax
* mov eax, [ebp+var_128]
* jmp loc_4BB6
* lea eax, ds:0[edx*8]
  push eax                                push eax
  mov ecx, [ebp+arg_1C]                   mov ecx, [ebp+arg_1C]
  push ecx                                push ecx
* lea eax, [esi+5Ch]                      lea eax, [ebx+0FCh]
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov ax, [esi+5Ah]                       mov ax, [ebx+0FAh]
  and eax, 0FFFh                          and eax, 0FFFh
* shr eax, 1                              sar eax, 1
*                                         mov edx, [ebp+arg_20]
*                                         mov [edx], eax
*                                         mov eax, [ebp+var_128]
*                                         jmp loc_44A1
*                                         mov ecx, [ebp+arg_20]
*                                         mov ecx, [ecx]
*                                         lea eax, ds:0[ecx*8]
*                                         push eax
*                                         mov edx, [ebp+arg_1C]
*                                         push edx
*                                         lea eax, [ebx+0FCh]
*                                         push eax
*                                         call _bcopy
*                                         mov ax, [ebx+0FAh]
*                                         and eax, 0FFFh
*                                         sar eax, 1
  mov ecx, [ebp+arg_20]                   mov ecx, [ebp+arg_20]
  mov [ecx], eax                          mov [ecx], eax
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
* lea esp, [ebp-15Ch]                     lea esp, [ebp-154h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOGetIntValues
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 82Ch                           sub esp, 82Ch
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_828]                       pop [ebp+var_828]
  lea ecx, [ebp+var_824]                  lea ecx, [ebp+var_824]
  mov [ebp+var_82C], ecx                  mov [ebp+var_82C], ecx
* mov esi, [ebp+var_828]                  mov edi, [ebp+var_828]
* mov esi, [ebp+var_828]                  mov edi, [ebp+var_828]
* mov esi, [esi+1E03h]                    mov edi, [edi+2563h]
* mov [ebp+var_80C], esi                  mov [ebp+var_80C], edi
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  mov [ebp+var_808], ecx                  mov [ebp+var_808], ecx
* mov esi, [ebp+var_828]                  mov edi, [ebp+var_828]
* mov esi, [ebp+var_828]                  mov edi, [ebp+var_828]
* mov esi, [esi+1E07h]                    mov edi, [edi+2567h]
* mov [ebp+var_804], esi                  mov [ebp+var_804], edi
* lea edi, [ebp+var_800]                  lea eax, [ebp+var_800]
* mov eax, [ebp+arg_8]                    mov esi, [ebp+arg_8]
* mov esi, eax                            mov edi, eax
  cld                                     cld
  mov ecx, 10h                            mov ecx, 10h
  movsd                                   movsd
  mov ecx, [ebp+var_828]                  mov ecx, [ebp+var_828]
  mov ecx, [ebp+var_828]                  mov ecx, [ebp+var_828]
* mov ecx, [ecx+1E0Bh]                    mov ecx, [ecx+256Bh]
  mov [ebp+var_7C0], ecx                  mov [ebp+var_7C0], ecx
* mov esi, [ebp+arg_C]                    mov edi, [ebp+arg_C]
* mov [ebp+var_7BC], esi                  mov [ebp+var_7BC], edi
  mov [ebp+var_821], 1                    mov [ebp+var_821], 1
  mov [ebp+var_820], 6Ch                  mov [ebp+var_820], 6Ch
  mov [ebp+var_81C], 100h                 mov [ebp+var_81C], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  mov [ebp+var_814], ecx                  mov [ebp+var_814], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_818], eax                  mov [ebp+var_818], eax
  mov [ebp+var_810], 0AA0h                mov [ebp+var_810], 0AA0h
  push 0                                  push 0
  push 0                                  push 0
  push 824h                               push 824h
  push 0                                  push 0
* mov esi, [ebp+var_82C]                  mov edi, [ebp+var_82C]
* push esi                                push edi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_41F4                             jz loc_3A64
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_41EA                            jnz loc_3A5A
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_4309                            jmp loc_3B96
* mov ebx, [ebp+var_820]                  mov ecx, [ebp+var_82C]
* movzx edx, [ebp+var_821]                mov edx, [ecx+4]
* cmp [ebp+var_810], 0B04h                movzx ebx, byte ptr [ecx+3]
* jz loc_4218                             cmp dword ptr [ecx+14h], 0B04h
*                                         jz loc_3A84
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_4309                            jmp loc_3B96
* lea eax, [ebx-24h]                      lea eax, [edx-24h]
  cmp eax, 800h                           cmp eax, 800h
* ja loc_4227                             ja loc_3A93
* cmp edx, 1                              cmp ebx, 1
* jz loc_423A                             jz loc_3AA9
* cmp ebx, 20h                            cmp edx, 20h
* jnz loc_4295                            jnz loc_3B03
* cmp edx, 1                              cmp ebx, 1
* jnz loc_4295                            jnz loc_3B03
* cmp [ebp+var_808], 0                    mov edi, [ebp+var_82C]
* jz loc_4295                             cmp dword ptr [edi+1Ch], 0
* mov ecx, [ebp+var_828]                  jz loc_3B03
* mov eax, [ecx+1E0Fh]
* mov esi, [ebp+var_82C]
* cmp [esi+18h], eax
* jnz loc_4295
  mov ecx, [ebp+var_82C]                  mov ecx, [ebp+var_82C]
*                                         mov eax, [ecx+18h]
*                                         mov edi, [ebp+var_828]
*                                         cmp [edi+256Fh], eax
*                                         jnz loc_3B03
*                                         mov ecx, [ebp+var_82C]
*                                         cmp dword ptr [ecx+1Ch], 0
*                                         jz loc_3AD4
  mov eax, [ecx+1Ch]                      mov eax, [ecx+1Ch]
* test eax, eax                           jmp loc_3B96
* jnz loc_4309                            mov edi, [ebp+var_82C]
* mov esi, [ebp+var_82C]                  mov eax, [edi+20h]
* mov eax, [esi+20h]
  and eax, 3000FFFFh                      and eax, 3000FFFFh
  cmp eax, 10002002h                      cmp eax, 10002002h
* jnz loc_4295                            jnz loc_3B03
  mov ecx, [ebp+var_82C]                  mov ecx, [ebp+var_82C]
* mov dx, [ecx+22h]                       mov ax, [ecx+22h]
* and edx, 0FFFh                          and eax, 0FFFh
* lea edi, ds:0[edx*4]                    lea eax, ds:24h[eax*4]
* lea eax, [edi+24h]                      cmp edx, eax
* cmp ebx, eax                            jz loc_3B10
* jz loc_429C
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_4309                            jmp loc_3B96
* mov esi, [ebp+arg_14]                   mov edi, [ebp+var_82C]
* mov eax, [esi]                          mov ax, [edi+22h]
* cmp edx, eax                            and eax, 0FFFh
* ja loc_42D8                             mov ecx, [ebp+arg_14]
* push edi                                cmp [ecx], eax
* mov ecx, [ebp+arg_10]                   jb loc_3B5C
* push ecx
* mov eax, [ebp+var_82C]
* add eax, 24h
* push eax
* call _bcopy
* mov esi, [ebp+var_82C]
* mov cx, [esi+22h]
* and ecx, 0FFFh
* mov esi, [ebp+arg_14]
* mov [esi], ecx
* mov eax, [ebp+var_808]
* jmp loc_4309
  shl eax, 2                              shl eax, 2
  push eax                                push eax
* mov esi, [ebp+arg_10]                   mov edi, [ebp+arg_10]
* push esi                                push edi
  mov eax, [ebp+var_82C]                  mov eax, [ebp+var_82C]
  add eax, 24h                            add eax, 24h
  push eax                                push eax
  call _bcopy                             call _bcopy
  mov ecx, [ebp+var_82C]                  mov ecx, [ebp+var_82C]
* mov si, [ecx+22h]                       mov di, [ecx+22h]
* and esi, 0FFFh                          and edi, 0FFFh
  mov ecx, [ebp+arg_14]                   mov ecx, [ebp+arg_14]
* mov [ecx], esi                          mov [ecx], edi
*                                         mov eax, [ebp+var_808]
*                                         jmp loc_3B96
*                                         mov ecx, [ebp+arg_14]
*                                         mov ecx, [ecx]
*                                         lea eax, ds:0[ecx*4]
*                                         push eax
*                                         mov edi, [ebp+arg_10]
*                                         push edi
*                                         mov eax, [ebp+var_82C]
*                                         add eax, 24h
*                                         push eax
*                                         call _bcopy
*                                         mov ecx, [ebp+var_82C]
*                                         mov di, [ecx+22h]
*                                         and edi, 0FFFh
*                                         mov ecx, [ebp+arg_14]
*                                         mov [ecx], edi
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
  lea esp, [ebp-838h]                     lea esp, [ebp-838h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOGetSystemConfig
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 1030h                          sub esp, 1034h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_1030]                      pop [ebp+var_1030]
* lea esi, [ebp+var_102C]                 mov edi, [ebp+arg_C]
* mov ecx, [ebp+var_1030]                 lea ebx, [ebp+var_102C]
* mov ecx, [ebp+var_1030]                 mov edx, [ebp+var_1030]
* mov ecx, [ecx+0FD7h]                    mov edx, [ebp+var_1030]
* mov [ebp+var_1014], ecx                 mov edx, [edx+16A7h]
* mov edi, [ebp+arg_4]                    mov [ebp+var_1014], edx
* mov [ebp+var_1010], edi                 mov ecx, [ebp+arg_4]
*                                         mov [ebp+var_1010], ecx
  mov [ebp+var_1029], 1                   mov [ebp+var_1029], 1
  mov [ebp+var_1028], 20h                 mov [ebp+var_1028], 20h
  mov [ebp+var_1024], 100h                mov [ebp+var_1024], 100h
* mov ecx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
* mov [ebp+var_101C], ecx                 mov [ebp+var_101C], edx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_1020], eax                 mov [ebp+var_1020], eax
  mov [ebp+var_1018], 0AABh               mov [ebp+var_1018], 0AABh
  push 0                                  push 0
  push 0                                  push 0
  push 102Ch                              push 102Ch
  push 0                                  push 0
* push esi                                push ebx
  call _msg_rpc                           call _msg_rpc
* mov ebx, eax                            mov esi, eax
  add esp, 14h                            add esp, 14h
* test ebx, ebx                           test esi, esi
* jz loc_504C                             jz loc_494C
* cmp ebx, 0FFFFFF36h                     cmp esi, 0FFFFFF36h
* jnz loc_5042                            jnz loc_4945
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
* mov eax, ebx                            mov eax, esi
* jmp loc_5117                            jmp loc_4A1E
* mov ebx, [ebp+var_1028]                 mov ecx, [ebx+4]
* movzx edx, [ebp+var_1029]               mov [ebp+var_1034], ecx
* cmp [ebp+var_1018], 0B0Fh               movzx esi, byte ptr [ebx+3]
* jz loc_5070                             cmp dword ptr [ebx+14h], 0B0Fh
*                                         jz loc_496C
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_5117                            jmp loc_4A1E
* lea eax, [ebx-2Ch]                      mov eax, [ebp+var_1034]
*                                         add eax, 0FFFFFFD4h
  cmp eax, 1000h                          cmp eax, 1000h
* ja loc_507F                             ja loc_4981
* cmp edx, 1                              cmp esi, 1
* jz loc_5092                             jz loc_4995
* cmp ebx, 20h                            cmp [ebp+var_1034], 20h
* jnz loc_50CB                            jnz loc_49D9
* cmp edx, 1                              cmp esi, 1
* jnz loc_50CB                            jnz loc_49D9
* cmp [ebp+var_1010], 0                   cmp dword ptr [ebx+1Ch], 0
* jz loc_50CB                             jz loc_49D9
* mov edi, [ebp+var_1030]                 mov eax, [ebx+18h]
* mov eax, [edi+0FDBh]                    mov edx, [ebp+var_1030]
* cmp [esi+18h], eax                      cmp [edx+16ABh], eax
* jnz loc_50CB                            jnz loc_49D9
* mov eax, [esi+1Ch]                      cmp dword ptr [ebx+1Ch], 0
* test eax, eax                           jz loc_49B4
* jnz loc_5117                            mov eax, [ebx+1Ch]
* mov al, [esi+23h]                       jmp loc_4A1E
*                                         mov al, [ebx+23h]
  and al, 30h                             and al, 30h
  cmp al, 30h                             cmp al, 30h
* jnz loc_50CB                            jnz loc_49D9
* cmp dword ptr [esi+24h], 80008h         cmp dword ptr [ebx+24h], 80008h
* jnz loc_50CB                            jnz loc_49D9
* mov edx, [esi+28h]                      mov eax, [ebx+28h]
* lea eax, [edx+3]                        add eax, 3
  and al, 0FCh                            and al, 0FCh
  add eax, 2Ch                            add eax, 2Ch
* cmp ebx, eax                            cmp [ebp+var_1034], eax
* jz loc_50D4                             jz loc_49E0
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_5117                            jmp loc_4A1E
* mov ecx, [ebp+arg_C]                    mov eax, [ebx+28h]
* mov eax, [ecx]                          cmp [edi], eax
* cmp edx, eax                            jb loc_4A04
* ja loc_50FC                             push eax
* push edx                                mov ecx, [ebp+arg_8]
* mov edi, [ebp+arg_8]                    push ecx
* push edi                                lea eax, [ebx+2Ch]
* lea eax, [esi+2Ch]
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov esi, [esi+28h]                      mov ebx, [ebx+28h]
* mov ecx, [ebp+arg_C]                    mov [edi], ebx
* mov [ecx], esi
  mov eax, [ebp+var_1010]                 mov eax, [ebp+var_1010]
* jmp loc_5117                            jmp loc_4A1E
* push eax                                mov edx, [edi]
* mov edi, [ebp+arg_8]                    push edx
* push edi                                mov ecx, [ebp+arg_8]
* lea eax, [esi+2Ch]                      push ecx
*                                         lea eax, [ebx+2Ch]
  push eax                                push eax
  call _bcopy                             call _bcopy
* mov esi, [esi+28h]                      mov ebx, [ebx+28h]
* mov ecx, [ebp+arg_C]                    mov [edi], ebx
* mov [ecx], esi
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
* lea esp, [ebp-103Ch]                    lea esp, [ebp-1040h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOLookupByDeviceName
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 84h                            sub esp, 84h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_80]                        pop [ebp+var_80]
* lea edx, [ebp+var_7C]                   lea ecx, [ebp+var_7C]
* mov ecx, [ebp+var_80]                   mov [ebp+var_84], ecx
* mov ecx, [ebp+var_80]                   mov edi, [ebp+var_80]
* mov ecx, [ecx+1F1Fh]                    mov edi, [ebp+var_80]
* mov [ebp+var_64], ecx                   mov edi, [edi+26BFh]
* lea edi, [ebp+var_60]                   mov [ebp+var_64], edi
*                                         lea eax, [ebp+var_60]
  mov esi, [ebp+arg_4]                    mov esi, [ebp+arg_4]
*                                         mov edi, eax
  cld                                     cld
  mov ecx, 14h                            mov ecx, 14h
  movsd                                   movsd
  mov [ebp+var_79], 1                     mov [ebp+var_79], 1
  mov [ebp+var_78], 6Ch                   mov [ebp+var_78], 6Ch
  mov [ebp+var_74], 100h                  mov [ebp+var_74], 100h
* mov ebx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
* mov [ebp+var_6C], ebx                   mov [ebp+var_6C], ecx
* mov [ebp+var_84], edx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_70], eax                   mov [ebp+var_70], eax
  mov [ebp+var_68], 0A9Fh                 mov [ebp+var_68], 0A9Fh
  push 0                                  push 0
  push 0                                  push 0
  push 7Ch                                push 7Ch
  push 0                                  push 0
* mov edx, [ebp+var_84]                   mov edi, [ebp+var_84]
* push edx                                push edi
  call _msg_rpc                           call _msg_rpc
* mov esi, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
* mov edx, [ebp+var_84]                   test ebx, ebx
* test esi, esi                           jz loc_388C
* jz loc_4060                             cmp ebx, 0FFFFFF36h
* cmp esi, 0FFFFFF36h                     jnz loc_3885
* jnz loc_4059
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
* mov eax, esi                            mov eax, ebx
* jmp loc_40E5                            jmp loc_3955
* mov esi, [ebp+var_78]                   mov ecx, [ebp+var_84]
* movzx eax, [ebp+var_79]                 mov eax, [ecx+4]
* cmp [ebp+var_68], 0B03h                 movzx edx, byte ptr [ecx+3]
* jz loc_4078                             cmp dword ptr [ecx+14h], 0B03h
*                                         jz loc_38AC
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_40E5                            jmp loc_3955
* cmp esi, 7Ch                            cmp eax, 7Ch
* jnz loc_4082                            jnz loc_38B6
* cmp eax, 1                              cmp edx, 1
* jz loc_4092                             jz loc_38D4
* cmp esi, 20h                            cmp eax, 20h
* jnz loc_40E0                            jnz loc_3950
* cmp eax, 1                              cmp edx, 1
* jnz loc_40E0                            jnz loc_3950
* cmp [ebp+var_60], 0                     mov edi, [ebp+var_84]
* jz loc_40E0                             cmp dword ptr [edi+1Ch], 0
*                                         jz loc_3950
*                                         mov ecx, [ebp+var_84]
*                                         mov eax, [ecx+18h]
*                                         mov edi, [ebp+var_80]
*                                         cmp [edi+26C3h], eax
*                                         jnz loc_3950
*                                         mov ecx, [ebp+var_84]
*                                         cmp dword ptr [ecx+1Ch], 0
*                                         jz loc_38FC
*                                         mov eax, [ecx+1Ch]
*                                         jmp loc_3955
*                                         mov edi, [ebp+var_84]
*                                         mov eax, [edi+20h]
  mov ecx, [ebp+var_80]                   mov ecx, [ebp+var_80]
* mov eax, [ecx+1F23h]                    cmp [ecx+26C7h], eax
* cmp [edx+18h], eax                      jnz loc_3950
* jnz loc_40E0                            mov edi, [ebp+var_84]
* mov eax, [edx+1Ch]                      mov ecx, [edi+24h]
* test eax, eax                           mov edi, [ebp+arg_8]
* jnz loc_40E5                            mov [edi], ecx
* mov ebx, [ebp+var_80]                   mov edi, [ebp+var_84]
* mov eax, [ebx+1F27h]                    mov eax, [edi+28h]
* cmp [edx+20h], eax
* jnz loc_40E0
* mov ebx, [edx+24h]
* mov ecx, [ebp+arg_8]
* mov [ecx], ebx
  mov ecx, [ebp+var_80]                   mov ecx, [ebp+var_80]
* mov eax, [ecx+1F2Bh]                    cmp [ecx+26CBh], eax
* cmp [edx+28h], eax                      jnz loc_3950
* jnz loc_40E0                            mov eax, [ebp+arg_C]
* mov edi, [ebp+arg_C]                    mov esi, edi
* lea esi, [edx+2Ch]                      add esi, 2Ch
*                                         mov edi, eax
  cld                                     cld
  mov ecx, 14h                            mov ecx, 14h
  movsd                                   movsd
* mov eax, [edx+1Ch]                      mov ecx, [ebp+var_84]
* jmp loc_40E5                            mov eax, [ecx+1Ch]
*                                         jmp loc_3955
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
  lea esp, [ebp-90h]                      lea esp, [ebp-90h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOLookupByObjectNumber
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 0D0h                           sub esp, 0D0h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_CC]                        pop [ebp+var_CC]
* lea edx, [ebp+var_C8]                   lea ecx, [ebp+var_C8]
* mov ecx, [ebp+var_CC]                   mov [ebp+var_D0], ecx
* mov ecx, [ebp+var_CC]                   mov edi, [ebp+var_CC]
* mov ecx, [ecx+207Bh]                    mov edi, [ebp+var_CC]
* mov [ebp+var_B0], ecx                   mov edi, [edi+2853h]
* mov ebx, [ebp+arg_4]                    mov [ebp+var_B0], edi
* mov [ebp+var_AC], ebx                   mov ecx, [ebp+arg_4]
*                                         mov [ebp+var_AC], ecx
  mov [ebp+var_C5], 1                     mov [ebp+var_C5], 1
  mov [ebp+var_C4], 20h                   mov [ebp+var_C4], 20h
  mov [ebp+var_C0], 100h                  mov [ebp+var_C0], 100h
* mov ecx, [ebp+arg_0]                    mov edi, [ebp+arg_0]
* mov [ebp+var_B8], ecx                   mov [ebp+var_B8], edi
* mov [ebp+var_D0], edx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_BC], eax                   mov [ebp+var_BC], eax
  mov [ebp+var_B4], 0A9Eh                 mov [ebp+var_B4], 0A9Eh
  push 0                                  push 0
  push 0                                  push 0
  push 0C8h                               push 0C8h
  push 0                                  push 0
* mov edx, [ebp+var_D0]                   mov ecx, [ebp+var_D0]
* push edx                                push ecx
  call _msg_rpc                           call _msg_rpc
* mov esi, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
* mov edx, [ebp+var_D0]                   test ebx, ebx
* test esi, esi                           jz loc_3708
* jz loc_3F14                             cmp ebx, 0FFFFFF36h
* cmp esi, 0FFFFFF36h                     jnz loc_36FE
* jnz loc_3F0C
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
* mov eax, esi                            mov eax, ebx
* jmp loc_3FB9                            jmp loc_37E9
* mov esi, [ebp+var_C4]                   mov edi, [ebp+var_D0]
* movzx eax, [ebp+var_C5]                 mov eax, [edi+4]
* cmp [ebp+var_B4], 0B02h                 movzx edx, byte ptr [edi+3]
* jz loc_3F38                             cmp dword ptr [edi+14h], 0B02h
*                                         jz loc_3728
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_3FB9                            jmp loc_37E9
* cmp esi, 0C8h                           cmp eax, 0C8h
* jnz loc_3F45                            jnz loc_3734
* cmp eax, 1                              cmp edx, 1
* jz loc_3F58                             jz loc_3756
* cmp esi, 20h                            cmp eax, 20h
* jnz loc_3FB4                            jnz loc_37E4
* cmp eax, 1                              cmp edx, 1
* jnz loc_3FB4                            jnz loc_37E4
* cmp [ebp+var_AC], 0                     mov ecx, [ebp+var_D0]
* jz loc_3FB4                             cmp dword ptr [ecx+1Ch], 0
* mov ebx, [ebp+var_CC]                   jz loc_37E4
* mov eax, [ebx+207Fh]                    mov edi, [ebp+var_D0]
* cmp [edx+18h], eax                      mov eax, [edi+18h]
* jnz loc_3FB4
* mov eax, [edx+1Ch]
* test eax, eax
* jnz loc_3FB9
  mov ecx, [ebp+var_CC]                   mov ecx, [ebp+var_CC]
* mov eax, [ecx+2083h]                    cmp [ecx+2857h], eax
* cmp [edx+20h], eax                      jnz loc_37E4
* jnz loc_3FB4                            mov edi, [ebp+var_D0]
* mov edi, [ebp+arg_8]                    cmp dword ptr [edi+1Ch], 0
* lea esi, [edx+24h]                      jz loc_3780
*                                         mov eax, [edi+1Ch]
*                                         jmp loc_37E9
*                                         mov ecx, [ebp+var_D0]
*                                         mov eax, [ecx+20h]
*                                         mov edi, [ebp+var_CC]
*                                         cmp [edi+285Bh], eax
*                                         jnz loc_37E4
*                                         mov eax, [ebp+arg_8]
*                                         mov esi, [ebp+var_D0]
*                                         add esi, 24h
*                                         mov edi, eax
  cld                                     cld
  mov ecx, 14h                            mov ecx, 14h
  movsd                                   movsd
* mov ebx, [ebp+var_CC]                   mov ecx, [ebp+var_D0]
* mov eax, [ebx+2087h]                    mov eax, [ecx+74h]
* cmp [edx+74h], eax                      mov edi, [ebp+var_CC]
* jnz loc_3FB4                            cmp [edi+285Fh], eax
* mov edi, [ebp+arg_C]                    jnz loc_37E4
* lea esi, [edx+78h]                      mov eax, [ebp+arg_C]
*                                         mov esi, ecx
*                                         add esi, 78h
*                                         mov edi, eax
  cld                                     cld
  mov ecx, 14h                            mov ecx, 14h
  movsd                                   movsd
* mov eax, [edx+1Ch]                      mov ecx, [ebp+var_D0]
* jmp loc_3FB9                            mov eax, [ecx+1Ch]
*                                         jmp loc_37E9
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
  lea esp, [ebp-0DCh]                     lea esp, [ebp-0DCh]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOMapEISADeviceMemory
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 48h                            sub esp, 48h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop edi
  mov al, [ebp+arg_14]                    mov al, [ebp+arg_14]
* lea edi, [ebp+var_48]                   lea esi, [ebp+var_48]
* mov edx, esi                            mov edx, edi
* mov edx, [edx+1212h]                    mov edx, [edx+18E6h]
  mov [ebp+var_30], edx                   mov [ebp+var_30], edx
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  mov [ebp+var_2C], ecx                   mov [ebp+var_2C], ecx
* mov edx, esi                            mov edx, edi
* mov edx, [edx+1216h]                    mov edx, [edx+18EAh]
  mov [ebp+var_28], edx                   mov [ebp+var_28], edx
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov [ebp+var_24], ecx                   mov [ebp+var_24], ecx
* mov edx, esi                            mov edx, edi
* mov edx, [edx+121Ah]                    mov edx, [edx+18EEh]
  mov [ebp+var_20], edx                   mov [ebp+var_20], edx
  mov ecx, [ebp+arg_C]                    mov ecx, [ebp+arg_C]
  mov [ebp+var_1C], ecx                   mov [ebp+var_1C], ecx
* mov edx, esi                            mov edx, edi
* mov edx, [edx+121Eh]                    mov edx, [edx+18F2h]
  mov [ebp+var_18], edx                   mov [ebp+var_18], edx
  mov ecx, [ebp+arg_10]                   mov ecx, [ebp+arg_10]
  mov ecx, [ecx]                          mov ecx, [ecx]
  mov [ebp+var_14], ecx                   mov [ebp+var_14], ecx
* mov edx, esi                            mov edx, edi
* mov edx, [edx+1222h]                    mov edx, [edx+18F6h]
  mov [ebp+var_10], edx                   mov [ebp+var_10], edx
  mov [ebp+var_C], al                     mov [ebp+var_C], al
* mov ecx, esi                            mov ecx, edi
* mov ecx, [ecx+1226h]                    mov ecx, [ecx+18FAh]
  mov [ebp+var_8], ecx                    mov [ebp+var_8], ecx
  mov edx, [ebp+arg_18]                   mov edx, [ebp+arg_18]
  mov [ebp+var_4], edx                    mov [ebp+var_4], edx
  mov [ebp+var_45], 0                     mov [ebp+var_45], 0
  mov [ebp+var_44], 48h                   mov [ebp+var_44], 48h
  mov [ebp+var_40], 100h                  mov [ebp+var_40], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  mov [ebp+var_38], ecx                   mov [ebp+var_38], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_3C], eax                   mov [ebp+var_3C], eax
  mov [ebp+var_34], 0AA7h                 mov [ebp+var_34], 0AA7h
  push 0                                  push 0
  push 0                                  push 0
  push 28h                                push 28h
  push 0                                  push 0
* push edi                                push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_4E08                             jz loc_4704
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_4E01                            jnz loc_46FD
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_4E69                            jmp loc_4769
* mov ebx, [ebp+var_44]                   mov eax, [esi+4]
* movzx eax, [ebp+var_45]                 movzx ebx, byte ptr [esi+3]
* cmp [ebp+var_34], 0B0Bh                 cmp dword ptr [esi+14h], 0B0Bh
* jz loc_4E20                             jz loc_471C
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_4E69                            jmp loc_4769
* cmp ebx, 28h                            cmp eax, 28h
* jnz loc_4E2A                            jnz loc_4726
* cmp eax, 1                              cmp ebx, 1
* jz loc_4E3A                             jz loc_4736
* cmp ebx, 20h                            cmp eax, 20h
* jnz loc_4E64                            jnz loc_4764
* cmp eax, 1                              cmp ebx, 1
* jnz loc_4E64                            jnz loc_4764
* cmp [ebp+var_2C], 0                     cmp dword ptr [esi+1Ch], 0
* jz loc_4E64                             jz loc_4764
* mov eax, ds:(_RetCodeCheck_133 - 4D4Ah)[esi]  mov eax, [esi+18h]
* cmp [edi+18h], eax                      cmp ds:(_RetCodeCheck_133 - 4646h)[edi], eax
* jnz loc_4E64                            jnz loc_4764
* mov eax, [edi+1Ch]                      cmp dword ptr [esi+1Ch], 0
* test eax, eax                           jz loc_474C
* jnz loc_4E69                            mov eax, [esi+1Ch]
* mov eax, ds:(_addrCheck_134 - 4D4Ah)[esi]  jmp loc_4769
* cmp [edi+20h], eax                      mov eax, [esi+20h]
* jnz loc_4E64                            cmp ds:(_addrCheck_134 - 4646h)[edi], eax
* mov ecx, [edi+24h]                      jnz loc_4764
*                                         mov ecx, [esi+24h]
  mov edx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
  mov [edx], ecx                          mov [edx], ecx
* mov eax, [edi+1Ch]                      mov eax, [esi+1Ch]
* jmp loc_4E69                            jmp loc_4769
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
  lea esp, [ebp-54h]                      lea esp, [ebp-54h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOMapEISADevicePorts
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 20h                            sub esp, 20h
*                                         push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop edi
* lea ebx, [ebp+var_20]                   lea esi, [ebp+var_20]
* mov ecx, esi                            mov ecx, edi
* mov ecx, [ecx+137Bh]                    mov ecx, [ecx+1A5Eh]
  mov [ebp+var_8], ecx                    mov [ebp+var_8], ecx
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  mov [ebp+var_4], ecx                    mov [ebp+var_4], ecx
  mov [ebp+var_1D], 0                     mov [ebp+var_1D], 0
  mov [ebp+var_1C], 20h                   mov [ebp+var_1C], 20h
  mov [ebp+var_18], 100h                  mov [ebp+var_18], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  mov [ebp+var_10], ecx                   mov [ebp+var_10], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_14], eax                   mov [ebp+var_14], eax
  mov [ebp+var_C], 0AA5h                  mov [ebp+var_C], 0AA5h
  push 0                                  push 0
  push 0                                  push 0
  push 20h                                push 20h
  push 0                                  push 0
* push ebx                                push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_4C38                             jz loc_4524
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_4C31                            jnz loc_451E
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_4C75                            jmp loc_4567
* mov edx, [ebp+var_1C]                   mov eax, [esi+4]
* movzx eax, [ebp+var_1D]                 movzx edx, byte ptr [esi+3]
* cmp [ebp+var_C], 0B09h                  cmp dword ptr [esi+14h], 0B09h
* jz loc_4C50                             jz loc_453C
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_4C75                            jmp loc_4567
* cmp edx, 20h                            cmp eax, 20h
* jnz loc_4C65                            jnz loc_4551
* cmp eax, 1                              cmp edx, 1
* jnz loc_4C65                            jnz loc_4551
* mov eax, ds:(_RetCodeCheck_120 - 4BD1h)[esi]  mov eax, [esi+18h]
* cmp [ebp+var_8], eax                    cmp ds:(_RetCodeCheck_120 - 44BEh)[edi], eax
* jz loc_4C6C                             jz loc_4558
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_4C75                            jmp loc_4567
* mov eax, [ebp+var_4]                    cmp dword ptr [esi+1Ch], 0
* test eax, eax                           jnz loc_4564
* jnz loc_4C75
  xor eax, eax                            xor eax, eax
* lea esp, [ebp-28h]                      jmp loc_4567
*                                         mov eax, [esi+1Ch]
*                                         lea esp, [ebp-2Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
*                                         pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOProbeDriver
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 1024h                          sub esp, 1028h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop [ebp+var_1028]
* mov ebx, [ebp+arg_8]
  lea edi, [ebp+var_1024]                 lea edi, [ebp+var_1024]
* mov ecx, esi                            mov ebx, edi
* mov ecx, [ecx+10F7h]                    mov esi, 24h
* mov [ebp+var_100C], ecx                 mov eax, [ebp+var_1028]
* mov ecx, esi                            add eax, 17C7h
* mov ecx, [ecx+10FBh]                    mov edx, [ebp+var_1028]
*                                         mov edx, [ebp+var_1028]
*                                         mov edx, [edx+17C7h]
*                                         mov [ebp+var_100C], edx
*                                         mov ecx, [eax+4]
  mov [ebp+var_1008], ecx                 mov [ebp+var_1008], ecx
* mov ecx, esi                            mov eax, [eax+8]
* mov ecx, [ecx+10FFh]                    mov [ebp+var_1004], eax
* mov [ebp+var_1004], ecx                 cmp [ebp+arg_8], 1000h
* cmp ebx, 1000h                          jbe loc_47E0
* jbe loc_4ECC
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
* jmp loc_4F94                            jmp loc_4897
* push ebx                                mov edx, [ebp+arg_8]
* lea eax, [ebp+var_1000]                 push edx
*                                         lea eax, [ebx+24h]
  push eax                                push eax
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  push ecx                                push ecx
  call _bcopy                             call _bcopy
* mov [ebp+var_1004], ebx                 mov edx, [ebp+arg_8]
* lea eax, [ebx+3]                        mov [ebx+20h], edx
*                                         mov eax, [ebp+arg_8]
*                                         add eax, 3
  and al, 0FCh                            and al, 0FCh
* mov [ebp+var_1021], 1                   mov byte ptr [ebx+3], 1
* add eax, 24h                            add esi, eax
* mov [ebp+var_1020], eax                 mov [ebx+4], esi
* mov [ebp+var_101C], 100h                mov dword ptr [ebx+8], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
* mov [ebp+var_1014], ecx                 mov [ebx+10h], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
* mov [ebp+var_1018], eax                 mov [ebx+0Ch], eax
* mov [ebp+var_1010], 0AAAh               mov dword ptr [ebx+14h], 0AAAh
  push 0                                  push 0
  push 0                                  push 0
  push 20h                                push 20h
  push 0                                  push 0
* push edi                                push ebx
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 20h                            add esp, 20h
  test ebx, ebx                           test ebx, ebx
* jz loc_4F48                             jz loc_484C
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_4F44                            jnz loc_4848
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_4F94                            jmp loc_4897
* mov eax, [ebp+var_1020]                 mov esi, [edi+4]
* movzx edx, [ebp+var_1021]               movzx eax, byte ptr [edi+3]
* cmp [ebp+var_1010], 0B0Eh               cmp dword ptr [edi+14h], 0B0Eh
* jz loc_4F68                             jz loc_4864
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_4F94                            jmp loc_4897
* cmp eax, 20h                            cmp esi, 20h
* jnz loc_4F80                            jnz loc_487F
* cmp edx, 1                              cmp eax, 1
* jnz loc_4F80                            jnz loc_487F
* mov eax, ds:(_RetCodeCheck_138 - 4E85h)[esi]  mov eax, [edi+18h]
* cmp [ebp+var_100C], eax                 mov edx, [ebp+var_1028]
* jz loc_4F88                             cmp [edx+17D3h], eax
*                                         jz loc_4888
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_4F94                            jmp loc_4897
* mov eax, [ebp+var_1008]                 cmp dword ptr [edi+1Ch], 0
* test eax, eax                           jnz loc_4894
* jnz loc_4F94
  xor eax, eax                            xor eax, eax
* lea esp, [ebp-1030h]                    jmp loc_4897
*                                         mov eax, [edi+1Ch]
*                                         lea esp, [ebp-1034h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOSetCharValues
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 270h                           sub esp, 274h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_26C]                       pop [ebp+var_26C]
* mov ebx, [ebp+arg_10]                   lea edx, [ebp+var_268]
* lea ecx, [ebp+var_268]                  mov [ebp+var_270], edx
* mov [ebp+var_270], ecx                  mov ebx, [ebp+var_270]
* mov esi, [ebp+var_26C]                  mov [ebp+var_274], 68h
* mov esi, [ebp+var_26C]                  mov ecx, [ebp+var_26C]
* mov esi, [esi+184Fh]                    mov ecx, [ebp+var_26C]
* mov [ebp+var_250], esi                  mov ecx, [ecx+1F6Fh]
* mov ecx, [ebp+arg_4]                    mov [ebp+var_250], ecx
* mov [ebp+var_24C], ecx                  mov edx, [ebp+arg_4]
* mov esi, [ebp+var_26C]                  mov [ebp+var_24C], edx
* mov esi, [ebp+var_26C]                  mov ecx, [ebp+var_26C]
* mov esi, [esi+1853h]                    mov ecx, [ebp+var_26C]
* mov [ebp+var_248], esi                  mov ecx, [ecx+1F73h]
*                                         mov [ebp+var_248], ecx
  lea edi, [ebp+var_244]                  lea edi, [ebp+var_244]
* mov eax, [ebp+arg_8]                    mov esi, [ebp+arg_8]
* mov esi, eax
  cld                                     cld
  mov ecx, 10h                            mov ecx, 10h
  movsd                                   movsd
* mov ecx, [ebp+var_26C]                  mov edx, [ebp+var_26C]
* mov ecx, [ebp+var_26C]                  mov edx, [ebp+var_26C]
* mov ecx, [ecx+1857h]                    mov edx, [edx+1F77h]
* mov [ebp+var_204], ecx                  mov [ebp+var_204], edx
* cmp ebx, 200h                           cmp [ebp+arg_10], 200h
* jbe loc_4774                            jbe loc_4030
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
* jmp loc_4860                            jmp loc_411D
* push ebx                                mov ecx, [ebp+arg_10]
* lea eax, [ebp+var_200]                  push ecx
*                                         lea eax, [ebx+68h]
  push eax                                push eax
* mov esi, [ebp+arg_C]                    mov edx, [ebp+arg_C]
* push esi                                push edx
  call _bcopy                             call _bcopy
* mov edx, ebx                            mov ax, word ptr [ebp+arg_10]
* and dh, 0Fh                             and ah, 0Fh
* mov ax, word ptr [ebp+var_204+2]        and word ptr [ebx+66h], 0F000h
* and ax, 0F000h                          or [ebx+66h], ax
* or ax, dx                               mov eax, [ebp+arg_10]
* mov word ptr [ebp+var_204+2], ax        add eax, 3
* lea eax, [ebx+3]
  and al, 0FCh                            and al, 0FCh
* mov [ebp+var_265], 1                    mov byte ptr [ebx+3], 1
* add eax, 68h                            add eax, [ebp+var_274]
* mov [ebp+var_264], eax                  mov [ebx+4], eax
* mov [ebp+var_260], 100h                 mov dword ptr [ebx+8], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
* mov [ebp+var_258], ecx                  mov [ebx+10h], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
* mov [ebp+var_25C], eax                  mov [ebx+0Ch], eax
* mov [ebp+var_254], 0AA3h                mov dword ptr [ebx+14h], 0AA3h
  push 0                                  push 0
  push 0                                  push 0
  push 20h                                push 20h
  push 0                                  push 0
* mov esi, [ebp+var_270]                  push ebx
* push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 20h                            add esp, 20h
  test ebx, ebx                           test ebx, ebx
* jz loc_480C                             jz loc_40AC
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_4806                            jnz loc_40A7
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_4860                            jmp loc_411D
* mov eax, [ebp+var_264]                  mov edx, [ebp+var_270]
* movzx edx, [ebp+var_265]                mov edx, [edx+4]
* cmp [ebp+var_254], 0B07h                mov [ebp+var_274], edx
* jz loc_482C                             mov ecx, [ebp+var_270]
*                                         movzx eax, byte ptr [ecx+3]
*                                         cmp dword ptr [ecx+14h], 0B07h
*                                         jz loc_40D8
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_4860                            jmp loc_411D
* cmp eax, 20h                            cmp [ebp+var_274], 20h
* jnz loc_484A                            jnz loc_40FD
* cmp edx, 1                              cmp eax, 1
* jnz loc_484A                            jnz loc_40FD
*                                         mov edx, [ebp+var_270]
*                                         mov eax, [edx+18h]
  mov ecx, [ebp+var_26C]                  mov ecx, [ebp+var_26C]
* mov eax, [ecx+185Bh]                    cmp [ecx+1F7Bh], eax
* cmp [ebp+var_250], eax                  jz loc_4104
* jz loc_4854
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_4860                            jmp loc_411D
* mov eax, [ebp+var_24C]                  mov edx, [ebp+var_270]
* test eax, eax                           cmp dword ptr [edx+1Ch], 0
* jnz loc_4860                            jnz loc_4114
  xor eax, eax                            xor eax, eax
* lea esp, [ebp-27Ch]                     jmp loc_411D
*                                         mov ecx, [ebp+var_270]
*                                         mov eax, [ecx+1Ch]
*                                         lea esp, [ebp-280h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOSetIntValues
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 870h                           sub esp, 878h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_86C]                       pop [ebp+var_86C]
* lea ecx, [ebp+var_868]                  lea edx, [ebp+var_868]
* mov [ebp+var_870], ecx                  mov [ebp+var_870], edx
*                                         mov [ebp+var_878], edx
*                                         mov [ebp+var_874], 68h
  mov esi, [ebp+var_86C]                  mov esi, [ebp+var_86C]
  mov esi, [ebp+var_86C]                  mov esi, [ebp+var_86C]
* mov esi, [esi+19DFh]                    mov esi, [esi+2113h]
  mov [ebp+var_850], esi                  mov [ebp+var_850], esi
* mov ecx, [ebp+arg_4]                    mov edx, [ebp+arg_4]
* mov [ebp+var_84C], ecx                  mov [ebp+var_84C], edx
  mov esi, [ebp+var_86C]                  mov esi, [ebp+var_86C]
  mov esi, [ebp+var_86C]                  mov esi, [ebp+var_86C]
* mov esi, [esi+19E3h]                    mov esi, [esi+2117h]
  mov [ebp+var_848], esi                  mov [ebp+var_848], esi
  lea edi, [ebp+var_844]                  lea edi, [ebp+var_844]
  mov eax, [ebp+arg_8]                    mov eax, [ebp+arg_8]
  mov esi, eax                            mov esi, eax
  cld                                     cld
  mov ecx, 10h                            mov ecx, 10h
  movsd                                   movsd
* mov ecx, [ebp+var_86C]                  mov edx, [ebp+var_86C]
* mov ecx, [ebp+var_86C]                  mov edx, [ebp+var_86C]
* mov ecx, [ecx+19E7h]                    mov edx, [edx+211Bh]
* mov [ebp+var_804], ecx                  mov [ebp+var_804], edx
  cmp [ebp+arg_10], 200h                  cmp [ebp+arg_10], 200h
* jbe loc_45D4                            jbe loc_3E80
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
* jmp loc_46C8                            jmp loc_3F79
  mov esi, [ebp+arg_10]                   mov esi, [ebp+arg_10]
  lea ebx, ds:0[esi*4]                    lea ebx, ds:0[esi*4]
  push ebx                                push ebx
* lea eax, [ebp+var_800]                  mov eax, [ebp+var_878]
*                                         add eax, 68h
  push eax                                push eax
* mov ecx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
* push ecx                                push edx
  call _bcopy                             call _bcopy
* mov dx, word ptr [ebp+arg_10]           mov ax, word ptr [ebp+arg_10]
* and dh, 0Fh                             and ah, 0Fh
* mov ax, word ptr [ebp+var_804+2]        mov esi, [ebp+var_878]
* and ax, 0F000h                          and word ptr [esi+66h], 0F000h
* or ax, dx                               or [esi+66h], ax
* mov word ptr [ebp+var_804+2], ax        mov byte ptr [esi+3], 1
* mov [ebp+var_865], 1                    add ebx, [ebp+var_874]
* add ebx, 68h                            mov [esi+4], ebx
* mov [ebp+var_864], ebx                  mov dword ptr [esi+8], 100h
* mov [ebp+var_860], 100h                 mov edx, [ebp+arg_0]
* mov esi, [ebp+arg_0]                    mov [esi+10h], edx
* mov [ebp+var_858], esi
  call _mig_get_reply_port                call _mig_get_reply_port
* mov [ebp+var_85C], eax                  mov [esi+0Ch], eax
* mov [ebp+var_854], 0AA2h                mov dword ptr [esi+14h], 0AA2h
  push 0                                  push 0
  push 0                                  push 0
  push 20h                                push 20h
  push 0                                  push 0
* mov ecx, [ebp+var_870]                  push esi
* push ecx
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 20h                            add esp, 20h
  test ebx, ebx                           test ebx, ebx
* jz loc_4674                             jz loc_3F08
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_466D                            jnz loc_3F02
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_46C8                            jmp loc_3F79
* mov eax, [ebp+var_864]                  mov esi, [ebp+var_870]
* movzx edx, [ebp+var_865]                mov esi, [esi+4]
* cmp [ebp+var_854], 0B06h                mov [ebp+var_874], esi
* jz loc_4694                             mov edx, [ebp+var_870]
*                                         movzx eax, byte ptr [edx+3]
*                                         cmp dword ptr [edx+14h], 0B06h
*                                         jz loc_3F34
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_46C8                            jmp loc_3F79
* cmp eax, 20h                            cmp [ebp+var_874], 20h
* jnz loc_46B2                            jnz loc_3F59
* cmp edx, 1                              cmp eax, 1
* jnz loc_46B2                            jnz loc_3F59
* mov esi, [ebp+var_86C]                  mov esi, [ebp+var_870]
* mov eax, [esi+19EBh]                    mov eax, [esi+18h]
* cmp [ebp+var_850], eax                  mov edx, [ebp+var_86C]
* jz loc_46BC                             cmp [edx+211Fh], eax
*                                         jz loc_3F60
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_46C8                            jmp loc_3F79
* mov eax, [ebp+var_84C]                  mov esi, [ebp+var_870]
* test eax, eax                           cmp dword ptr [esi+1Ch], 0
* jnz loc_46C8                            jnz loc_3F70
  xor eax, eax                            xor eax, eax
* lea esp, [ebp-87Ch]                     jmp loc_3F79
*                                         mov edx, [ebp+var_870]
*                                         mov eax, [edx+1Ch]
*                                         lea esp, [ebp-884h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOUnMapEISADevicePorts
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 20h                            sub esp, 20h
*                                         push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop edi
* lea ebx, [ebp+var_20]                   lea esi, [ebp+var_20]
* mov ecx, esi                            mov ecx, edi
* mov ecx, [ecx+12C7h]                    mov ecx, [ecx+19A2h]
  mov [ebp+var_8], ecx                    mov [ebp+var_8], ecx
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  mov [ebp+var_4], ecx                    mov [ebp+var_4], ecx
  mov [ebp+var_1D], 0                     mov [ebp+var_1D], 0
  mov [ebp+var_1C], 20h                   mov [ebp+var_1C], 20h
  mov [ebp+var_18], 100h                  mov [ebp+var_18], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  mov [ebp+var_10], ecx                   mov [ebp+var_10], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_14], eax                   mov [ebp+var_14], eax
  mov [ebp+var_C], 0AA6h                  mov [ebp+var_C], 0AA6h
  push 0                                  push 0
  push 0                                  push 0
  push 20h                                push 20h
  push 0                                  push 0
* push ebx                                push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_4CF4                             jz loc_45E8
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_4CED                            jnz loc_45E2
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_4D31                            jmp loc_462B
* mov edx, [ebp+var_1C]                   mov eax, [esi+4]
* movzx eax, [ebp+var_1D]                 movzx edx, byte ptr [esi+3]
* cmp [ebp+var_C], 0B0Ah                  cmp dword ptr [esi+14h], 0B0Ah
* jz loc_4D0C                             jz loc_4600
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_4D31                            jmp loc_462B
* cmp edx, 20h                            cmp eax, 20h
* jnz loc_4D21                            jnz loc_4615
* cmp eax, 1                              cmp edx, 1
* jnz loc_4D21                            jnz loc_4615
* mov eax, ds:(_RetCodeCheck_124 - 4C8Dh)[esi]  mov eax, [esi+18h]
* cmp [ebp+var_8], eax                    cmp ds:(_RetCodeCheck_124 - 4582h)[edi], eax
* jz loc_4D28                             jz loc_461C
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_4D31                            jmp loc_462B
* mov eax, [ebp+var_4]                    cmp dword ptr [esi+1Ch], 0
* test eax, eax                           jnz loc_4628
* jnz loc_4D31
  xor eax, eax                            xor eax, eax
* lea esp, [ebp-28h]                      jmp loc_462B
*                                         mov eax, [esi+1Ch]
*                                         lea esp, [ebp-2Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
*                                         pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__IOUnloadDriver
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 1024h                          sub esp, 1028h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop [ebp+var_1028]
* mov ebx, [ebp+arg_8]
  lea edi, [ebp+var_1024]                 lea edi, [ebp+var_1024]
* mov ecx, esi                            mov ebx, edi
* mov ecx, [ecx+0E5Fh]                    mov esi, 24h
* mov [ebp+var_100C], ecx                 mov eax, [ebp+var_1028]
* mov ecx, esi                            add eax, 1527h
* mov ecx, [ecx+0E63h]                    mov edx, [ebp+var_1028]
*                                         mov edx, [ebp+var_1028]
*                                         mov edx, [edx+1527h]
*                                         mov [ebp+var_100C], edx
*                                         mov ecx, [eax+4]
  mov [ebp+var_1008], ecx                 mov [ebp+var_1008], ecx
* mov ecx, esi                            mov eax, [eax+8]
* mov ecx, [ecx+0E67h]                    mov [ebp+var_1004], eax
* mov [ebp+var_1004], ecx                 cmp [ebp+arg_8], 1000h
* cmp ebx, 1000h                          jbe loc_4A98
* jbe loc_517C
  mov eax, 0FFFFFECDh                     mov eax, 0FFFFFECDh
* jmp loc_5244                            jmp loc_4B4F
* push ebx                                mov edx, [ebp+arg_8]
* lea eax, [ebp+var_1000]                 push edx
*                                         lea eax, [ebx+24h]
  push eax                                push eax
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  push ecx                                push ecx
  call _bcopy                             call _bcopy
* mov [ebp+var_1004], ebx                 mov edx, [ebp+arg_8]
* lea eax, [ebx+3]                        mov [ebx+20h], edx
*                                         mov eax, [ebp+arg_8]
*                                         add eax, 3
  and al, 0FCh                            and al, 0FCh
* mov [ebp+var_1021], 1                   mov byte ptr [ebx+3], 1
* add eax, 24h                            add esi, eax
* mov [ebp+var_1020], eax                 mov [ebx+4], esi
* mov [ebp+var_101C], 100h                mov dword ptr [ebx+8], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
* mov [ebp+var_1014], ecx                 mov [ebx+10h], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
* mov [ebp+var_1018], eax                 mov [ebx+0Ch], eax
* mov [ebp+var_1010], 0AACh               mov dword ptr [ebx+14h], 0AACh
  push 0                                  push 0
  push 0                                  push 0
  push 20h                                push 20h
  push 0                                  push 0
* push edi                                push ebx
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 20h                            add esp, 20h
  test ebx, ebx                           test ebx, ebx
* jz loc_51F8                             jz loc_4B04
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_51F4                            jnz loc_4B00
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_5244                            jmp loc_4B4F
* mov eax, [ebp+var_1020]                 mov esi, [edi+4]
* movzx edx, [ebp+var_1021]               movzx eax, byte ptr [edi+3]
* cmp [ebp+var_1010], 0B10h               cmp dword ptr [edi+14h], 0B10h
* jz loc_5218                             jz loc_4B1C
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_5244                            jmp loc_4B4F
* cmp eax, 20h                            cmp esi, 20h
* jnz loc_5230                            jnz loc_4B37
* cmp edx, 1                              cmp eax, 1
* jnz loc_5230                            jnz loc_4B37
* mov eax, ds:(_RetCodeCheck_146 - 5135h)[esi]  mov eax, [edi+18h]
* cmp [ebp+var_100C], eax                 mov edx, [ebp+var_1028]
* jz loc_5238                             cmp [edx+1533h], eax
*                                         jz loc_4B40
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_5244                            jmp loc_4B4F
* mov eax, [ebp+var_1008]                 cmp dword ptr [edi+1Ch], 0
* test eax, eax                           jnz loc_4B4C
* jnz loc_5244
  xor eax, eax                            xor eax, eax
* lea esp, [ebp-1030h]                    jmp loc_4B4F
*                                         mov eax, [edi+1Ch]
*                                         lea esp, [ebp-1034h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__PMGetPowerEvent
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 28h                            sub esp, 28h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop edi                                 pop edi
  lea esi, [ebp+var_28]                   lea esi, [ebp+var_28]
  mov [ebp+var_25], 1                     mov [ebp+var_25], 1
  mov [ebp+var_24], 18h                   mov [ebp+var_24], 18h
  mov [ebp+var_20], 100h                  mov [ebp+var_20], 100h
  mov edx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
  mov [ebp+var_18], edx                   mov [ebp+var_18], edx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_1C], eax                   mov [ebp+var_1C], eax
  mov [ebp+var_14], 0AAFh                 mov [ebp+var_14], 0AAFh
  push 0                                  push 0
  push 0                                  push 0
  push 28h                                push 28h
  push 0                                  push 0
  push esi                                push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_5504                             jz loc_4E28
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_54FD                            jnz loc_4E21
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_5565                            jmp loc_4E8D
* mov ebx, [ebp+var_24]                   mov eax, [esi+4]
* movzx eax, [ebp+var_25]                 movzx ebx, byte ptr [esi+3]
* cmp [ebp+var_14], 0B13h                 cmp dword ptr [esi+14h], 0B13h
* jz loc_551C                             jz loc_4E40
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_5565                            jmp loc_4E8D
* cmp ebx, 28h                            cmp eax, 28h
* jnz loc_5526                            jnz loc_4E4A
* cmp eax, 1                              cmp ebx, 1
* jz loc_5536                             jz loc_4E5A
* cmp ebx, 20h                            cmp eax, 20h
* jnz loc_5560                            jnz loc_4E88
* cmp eax, 1                              cmp ebx, 1
* jnz loc_5560                            jnz loc_4E88
* cmp [ebp+var_C], 0                      cmp dword ptr [esi+1Ch], 0
* jz loc_5560                             jz loc_4E88
* mov eax, ds:(_RetCodeCheck_159 - 54AEh)[edi]  mov eax, [esi+18h]
* cmp [esi+18h], eax                      cmp ds:(_RetCodeCheck_159 - 4DD2h)[edi], eax
* jnz loc_5560                            jnz loc_4E88
*                                         cmp dword ptr [esi+1Ch], 0
*                                         jz loc_4E70
  mov eax, [esi+1Ch]                      mov eax, [esi+1Ch]
* test eax, eax                           jmp loc_4E8D
* jnz loc_5565                            mov eax, [esi+20h]
* mov eax, ds:(_eventCheck_160 - 54AEh)[edi]  cmp ds:(_eventCheck_160 - 4DD2h)[edi], eax
* cmp [esi+20h], eax                      jnz loc_4E88
* jnz loc_5560
  mov edx, [esi+24h]                      mov edx, [esi+24h]
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  mov [ecx], edx                          mov [ecx], edx
  mov eax, [esi+1Ch]                      mov eax, [esi+1Ch]
* jmp loc_5565                            jmp loc_4E8D
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
  lea esp, [ebp-34h]                      lea esp, [ebp-34h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__PMGetPowerStatus
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 34h                            sub esp, 34h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop [ebp+var_34]                        pop [ebp+var_34]
  mov edi, [ebp+arg_4]                    mov edi, [ebp+arg_4]
  lea esi, [ebp+var_30]                   lea esi, [ebp+var_30]
  mov [ebp+var_2D], 1                     mov [ebp+var_2D], 1
  mov [ebp+var_2C], 18h                   mov [ebp+var_2C], 18h
  mov [ebp+var_28], 100h                  mov [ebp+var_28], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  mov [ebp+var_20], ecx                   mov [ebp+var_20], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_24], eax                   mov [ebp+var_24], eax
  mov [ebp+var_1C], 0AB0h                 mov [ebp+var_1C], 0AB0h
  push 0                                  push 0
  push 0                                  push 0
  push 30h                                push 30h
  push 0                                  push 0
  push esi                                push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_55D8                             jz loc_4F00
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_55D2                            jnz loc_4EFA
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_5649                            jmp loc_4F75
* mov edx, [ebp+var_2C]                   mov eax, [esi+4]
* movzx eax, [ebp+var_2D]                 movzx edx, byte ptr [esi+3]
* cmp [ebp+var_1C], 0B14h                 cmp dword ptr [esi+14h], 0B14h
* jz loc_55F0                             jz loc_4F18
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_5649                            jmp loc_4F75
* cmp edx, 30h                            cmp eax, 30h
* jnz loc_55FA                            jnz loc_4F22
* cmp eax, 1                              cmp edx, 1
* jz loc_560A                             jz loc_4F32
* cmp edx, 20h                            cmp eax, 20h
* jnz loc_5644                            jnz loc_4F70
* cmp eax, 1                              cmp edx, 1
* jnz loc_5644                            jnz loc_4F70
* cmp [ebp+var_14], 0                     cmp dword ptr [esi+1Ch], 0
* jz loc_5644                             jz loc_4F70
*                                         mov eax, [esi+18h]
  mov ecx, [ebp+var_34]                   mov ecx, [ebp+var_34]
* mov eax, [ecx+0A46h]                    cmp [ecx+10EEh], eax
* cmp [esi+18h], eax                      jnz loc_4F70
* jnz loc_5644                            cmp dword ptr [esi+1Ch], 0
*                                         jz loc_4F4C
  mov eax, [esi+1Ch]                      mov eax, [esi+1Ch]
* test eax, eax                           jmp loc_4F75
* jnz loc_5649                            mov eax, [esi+20h]
  mov ecx, [ebp+var_34]                   mov ecx, [ebp+var_34]
* mov eax, [ecx+0A4Ah]                    cmp [ecx+10F2h], eax
* cmp [esi+20h], eax                      jnz loc_4F70
* jnz loc_5644
  mov ecx, [esi+24h]                      mov ecx, [esi+24h]
  mov [edi], ecx                          mov [edi], ecx
  mov ecx, [esi+28h]                      mov ecx, [esi+28h]
  mov [edi+4], ecx                        mov [edi+4], ecx
  mov ecx, [esi+2Ch]                      mov ecx, [esi+2Ch]
  mov [edi+8], ecx                        mov [edi+8], ecx
  mov eax, [esi+1Ch]                      mov eax, [esi+1Ch]
* jmp loc_5649                            jmp loc_4F75
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
  lea esp, [ebp-40h]                      lea esp, [ebp-40h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__PMRestoreDefaults
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 20h                            sub esp, 20h
*                                         push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop edi
* lea ebx, [ebp+var_20]                   lea esi, [ebp+var_20]
  mov [ebp+var_1D], 1                     mov [ebp+var_1D], 1
  mov [ebp+var_1C], 18h                   mov [ebp+var_1C], 18h
  mov [ebp+var_18], 100h                  mov [ebp+var_18], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  mov [ebp+var_10], ecx                   mov [ebp+var_10], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_14], eax                   mov [ebp+var_14], eax
  mov [ebp+var_C], 0AB2h                  mov [ebp+var_C], 0AB2h
  push 0                                  push 0
  push 0                                  push 0
  push 20h                                push 20h
  push 0                                  push 0
* push ebx                                push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_5780                             jz loc_50B8
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_577C                            jnz loc_50B1
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_57BD                            jmp loc_50FB
* mov edx, [ebp+var_1C]                   mov eax, [esi+4]
* movzx eax, [ebp+var_1D]                 movzx edx, byte ptr [esi+3]
* cmp [ebp+var_C], 0B16h                  cmp dword ptr [esi+14h], 0B16h
* jz loc_5798                             jz loc_50D0
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_57BD                            jmp loc_50FB
* cmp edx, 20h                            cmp eax, 20h
* jnz loc_57AD                            jnz loc_50E5
* cmp eax, 1                              cmp edx, 1
* jnz loc_57AD                            jnz loc_50E5
* mov eax, ds:(_RetCodeCheck_172 - 572Dh)[esi]  mov eax, [esi+18h]
* cmp [ebp+var_8], eax                    cmp ds:(_RetCodeCheck_172 - 5062h)[edi], eax
* jz loc_57B4                             jz loc_50EC
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_57BD                            jmp loc_50FB
* mov eax, [ebp+var_4]                    cmp dword ptr [esi+1Ch], 0
* test eax, eax                           jnz loc_50F8
* jnz loc_57BD
  xor eax, eax                            xor eax, eax
* lea esp, [ebp-28h]                      jmp loc_50FB
*                                         mov eax, [esi+1Ch]
*                                         lea esp, [ebp-2Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
*                                         pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__PMSetPowerManagement
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 28h                            sub esp, 28h
*                                         push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop edi
* lea ebx, [ebp+var_28]                   lea esi, [ebp+var_28]
* mov ecx, esi                            mov ecx, edi
* mov ecx, [ecx+96Bh]                     mov ecx, [ecx+100Eh]
  mov [ebp+var_10], ecx                   mov [ebp+var_10], ecx
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  mov [ebp+var_C], ecx                    mov [ebp+var_C], ecx
* mov ecx, esi                            mov ecx, edi
* mov ecx, [ecx+96Fh]                     mov ecx, [ecx+1012h]
  mov [ebp+var_8], ecx                    mov [ebp+var_8], ecx
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov [ebp+var_4], ecx                    mov [ebp+var_4], ecx
  mov [ebp+var_25], 1                     mov [ebp+var_25], 1
  mov [ebp+var_24], 28h                   mov [ebp+var_24], 28h
  mov [ebp+var_20], 100h                  mov [ebp+var_20], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  mov [ebp+var_18], ecx                   mov [ebp+var_18], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_1C], eax                   mov [ebp+var_1C], eax
  mov [ebp+var_14], 0AB1h                 mov [ebp+var_14], 0AB1h
  push 0                                  push 0
  push 0                                  push 0
  push 20h                                push 20h
  push 0                                  push 0
* push ebx                                push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_56D8                             jz loc_5004
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_56D2                            jnz loc_4FFF
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_5715                            jmp loc_5047
* mov edx, [ebp+var_24]                   mov eax, [esi+4]
* movzx eax, [ebp+var_25]                 movzx edx, byte ptr [esi+3]
* cmp [ebp+var_14], 0B15h                 cmp dword ptr [esi+14h], 0B15h
* jz loc_56F0                             jz loc_501C
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_5715                            jmp loc_5047
* cmp edx, 20h                            cmp eax, 20h
* jnz loc_5705                            jnz loc_5031
* cmp eax, 1                              cmp edx, 1
* jnz loc_5705                            jnz loc_5031
* mov eax, ds:(_RetCodeCheck_169 - 5661h)[esi]  mov eax, [esi+18h]
* cmp [ebp+var_10], eax                   cmp ds:(_RetCodeCheck_169 - 4F8Eh)[edi], eax
* jz loc_570C                             jz loc_5038
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_5715                            jmp loc_5047
* mov eax, [ebp+var_C]                    cmp dword ptr [esi+1Ch], 0
* test eax, eax                           jnz loc_5044
* jnz loc_5715
  xor eax, eax                            xor eax, eax
* lea esp, [ebp-30h]                      jmp loc_5047
*                                         mov eax, [esi+1Ch]
*                                         lea esp, [ebp-34h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
*                                         pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__PMSetPowerState
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 28h                            sub esp, 28h
*                                         push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop edi
* lea ebx, [ebp+var_28]                   lea esi, [ebp+var_28]
* mov ecx, esi                            mov ecx, edi
* mov ecx, [ecx+0BCFh]                    mov ecx, [ecx+1282h]
  mov [ebp+var_10], ecx                   mov [ebp+var_10], ecx
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  mov [ebp+var_C], ecx                    mov [ebp+var_C], ecx
* mov ecx, esi                            mov ecx, edi
* mov ecx, [ecx+0BD3h]                    mov ecx, [ecx+1286h]
  mov [ebp+var_8], ecx                    mov [ebp+var_8], ecx
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov [ebp+var_4], ecx                    mov [ebp+var_4], ecx
  mov [ebp+var_25], 1                     mov [ebp+var_25], 1
  mov [ebp+var_24], 28h                   mov [ebp+var_24], 28h
  mov [ebp+var_20], 100h                  mov [ebp+var_20], 100h
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  mov [ebp+var_18], ecx                   mov [ebp+var_18], ecx
  call _mig_get_reply_port                call _mig_get_reply_port
  mov [ebp+var_1C], eax                   mov [ebp+var_1C], eax
  mov [ebp+var_14], 0AAEh                 mov [ebp+var_14], 0AAEh
  push 0                                  push 0
  push 0                                  push 0
  push 20h                                push 20h
  push 0                                  push 0
* push ebx                                push esi
  call _msg_rpc                           call _msg_rpc
  mov ebx, eax                            mov ebx, eax
  add esp, 14h                            add esp, 14h
  test ebx, ebx                           test ebx, ebx
* jz loc_5458                             jz loc_4D74
  cmp ebx, 0FFFFFF36h                     cmp ebx, 0FFFFFF36h
* jnz loc_5452                            jnz loc_4D6F
  call _mig_dealloc_reply_port            call _mig_dealloc_reply_port
  mov eax, ebx                            mov eax, ebx
* jmp loc_5495                            jmp loc_4DB7
* mov edx, [ebp+var_24]                   mov eax, [esi+4]
* movzx eax, [ebp+var_25]                 movzx edx, byte ptr [esi+3]
* cmp [ebp+var_14], 0B12h                 cmp dword ptr [esi+14h], 0B12h
* jz loc_5470                             jz loc_4D8C
  mov eax, 0FFFFFED3h                     mov eax, 0FFFFFED3h
* jmp loc_5495                            jmp loc_4DB7
* cmp edx, 20h                            cmp eax, 20h
* jnz loc_5485                            jnz loc_4DA1
* cmp eax, 1                              cmp edx, 1
* jnz loc_5485                            jnz loc_4DA1
* mov eax, ds:(_RetCodeCheck_156 - 53E1h)[esi]  mov eax, [esi+18h]
* cmp [ebp+var_10], eax                   cmp ds:(_RetCodeCheck_156 - 4CFEh)[edi], eax
* jz loc_548C                             jz loc_4DA8
  mov eax, 0FFFFFED4h                     mov eax, 0FFFFFED4h
* jmp loc_5495                            jmp loc_4DB7
* mov eax, [ebp+var_C]                    cmp dword ptr [esi+1Ch], 0
* test eax, eax                           jnz loc_4DB4
* jnz loc_5495
  xor eax, eax                            xor eax, eax
* lea esp, [ebp-30h]                      jmp loc_4DB7
*                                         mov eax, [esi+1Ch]
*                                         lea esp, [ebp-34h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
*                                         pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__call_mod_init_funcs
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 4                              sub esp, 4
  call $+5                                call $+5
  pop edx                                 pop edx
  lea eax, [ebp+var_4]                    lea eax, [ebp+var_4]
  push eax                                push eax
* lea eax, (aDyldMakeDelaye - 3A7Bh)[edx]  lea eax, (aDyldMakeDelaye - 324Bh)[edx]
  push eax                                push eax
  call __dyld_func_lookup                 call __dyld_func_lookup
  mov eax, [ebp+var_4]                    mov eax, [ebp+var_4]
  call eax                                call eax
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

__dyld_func_lookup
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ

  reference                               rebuilt                               
  jmp ds:dyld_func_lookup_pointer         jmp ds:dyld_func_lookup_pointer

__dyld_init_check
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  cmp ds:dyld_lazy_symbol_binding_entry_point, 0  cmp ds:dyld_lazy_symbol_binding_entry_point, 0
* jz loc_3AA2                             jz loc_3272
  retn                                    retn
  push 4Eh                                push 4Eh
* push 5B89h                              push 5B42h
  push 2                                  push 2
  push 0                                  push 0
  mov eax, 4                              mov eax, 4
  call far ptr 2Bh:0                      call far ptr 2Bh:0
  add esp, 10h                            add esp, 10h
  push 3Bh                                push 3Bh
  push 0                                  push 0
  mov eax, 1                              mov eax, 1
  call far ptr 2Bh:0                      call far ptr 2Bh:0

__objcInit
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(__objcInit_ptr - 5D64h)[eax]  mov edx, ds:(__objcInit_ptr - 5D1Dh)[eax]
  jmp edx                                 jmp edx

__start
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 4                              sub esp, 4
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
  mov edi, [ebp+argv]                     mov edi, [ebp+argv]
  call __dyld_init_check                  call __dyld_init_check
  mov esi, [ebp+argc]                     mov esi, [ebp+argc]
* mov ds:(_NXArgc - 39B6h)[ebx], esi      mov ds:(_NXArgc - 3186h)[ebx], esi
* mov ds:(_NXArgv - 39B6h)[ebx], edi      mov ds:(_NXArgv - 3186h)[ebx], edi
  mov esi, [ebp+envp]                     mov esi, [ebp+envp]
* mov ds:(_environ - 39B6h)[ebx], esi     mov ds:(_environ - 3186h)[ebx], esi
* mov eax, ds:(off_6014 - 39B6h)[ebx]     mov eax, ds:(off_6014 - 3186h)[ebx]
  cmp dword ptr [eax], 0                  cmp dword ptr [eax], 0
* jz loc_39E6                             jz loc_31B6
  mov eax, [eax]                          mov eax, [eax]
  call eax                                call eax
* mov eax, ds:(off_6010 - 39B6h)[ebx]     mov eax, ds:(off_6010 - 3186h)[ebx]
  cmp dword ptr [eax], 0                  cmp dword ptr [eax], 0
* jz loc_39F5                             jz loc_31C5
  mov eax, [eax]                          mov eax, [eax]
  call eax                                call eax
* mov eax, ds:(__objcInit_ptr_0 - 39B6h)[ebx]  mov eax, ds:(__objcInit_ptr_0 - 3186h)[ebx]
  cmp dword ptr [eax], 0                  cmp dword ptr [eax], 0
* jz loc_3A05                             jz loc_31D5
  call __objcInit                         call __objcInit
  call __call_mod_init_funcs              call __call_mod_init_funcs
* mov eax, ds:(_errno_ptr - 39B6h)[ebx]   mov eax, ds:(_errno_ptr - 3186h)[ebx]
  mov dword ptr [eax], 0                  mov dword ptr [eax], 0
  cmp dword ptr [edi], 0                  cmp dword ptr [edi], 0
* jz loc_3A5C                             jz loc_322C
  mov [ebp+var_4], 0                      mov [ebp+var_4], 0
  xor edx, edx                            xor edx, edx
  mov eax, [edi]                          mov eax, [edi]
  mov ecx, eax                            mov ecx, eax
  cmp byte ptr [eax], 0                   cmp byte ptr [eax], 0
* jz loc_3A46                             jz loc_3216
  nop                                     nop
  nop                                     nop
  nop                                     nop
  cmp byte ptr [edx+ecx], 2Fh             cmp byte ptr [edx+ecx], 2Fh
* jnz loc_3A3D                            jnz loc_320D
  mov esi, edx                            mov esi, edx
  add esi, [edi]                          add esi, [edi]
  mov [ebp+var_4], esi                    mov [ebp+var_4], esi
  inc edx                                 inc edx
  mov ecx, [edi]                          mov ecx, [edi]
  cmp byte ptr [edx+ecx], 0               cmp byte ptr [edx+ecx], 0
* jnz loc_3A30                            jnz loc_3200
  cmp [ebp+var_4], 0                      cmp [ebp+var_4], 0
* jz loc_3A54                             jz loc_3224
  mov esi, [ebp+var_4]                    mov esi, [ebp+var_4]
  inc esi                                 inc esi
* jmp loc_3A56                            jmp loc_3226
  mov esi, [edi]                          mov esi, [edi]
* mov ds:(___progname - 39B6h)[ebx], esi  mov ds:(___progname - 3186h)[ebx], esi
  mov esi, [ebp+envp]                     mov esi, [ebp+envp]
  push esi                                push esi
  push edi                                push edi
  mov esi, [ebp+argc]                     mov esi, [ebp+argc]
  push esi                                push esi
  call _main                              call _main
  push eax                                push eax
  call _exit                              call _exit

_atoi
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_atoi_ptr - 5E1Ah)[eax]    mov edx, ds:(_atoi_ptr - 5DD3h)[eax]
  jmp edx                                 jmp edx

_bcopy
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_bcopy_ptr - 5E82h)[eax]   mov edx, ds:(_device_master_self_ptr - 5E3Bh)[eax]
  jmp edx                                 jmp edx

_bzero
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_bzero_ptr - 5E00h)[eax]   mov edx, ds:(_bzero_ptr - 5DB9h)[eax]
  jmp edx                                 jmp edx

_device_master_self
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_device_master_self_ptr - 5E68h)[eax]  mov edx, ds:(_task_self_ptr - 5E21h)[eax]
  jmp edx                                 jmp edx

_exit
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_exit_ptr - 5D4Ah)[eax]    mov edx, ds:(_exit_ptr - 5D03h)[eax]
  jmp edx                                 jmp edx

_main
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 60h                            sub esp, 60h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  mov edi, [ebp+argc]                     mov edi, [ebp+argc]
  mov ebx, [ebp+argv]                     mov ebx, [ebp+argv]
  mov [ebp+var_5C], 1                     mov [ebp+var_5C], 1
  push 9                                  push 9
* lea eax, (aInstance - 3AEEh)[esi]       lea eax, (aInstance - 32BEh)[esi]
  push eax                                push eax
  mov edx, [ebx+edi*4-4]                  mov edx, [ebx+edi*4-4]
  push edx                                push edx
  call _strncmp                           call _strncmp
  add esp, 0Ch                            add esp, 0Ch
  test eax, eax                           test eax, eax
* jz loc_3B30                             jz loc_3300
* lea eax, (aErrorInitializ - 3AEEh)[esi]  lea eax, (aErrorInitializ - 32BEh)[esi]
  push eax                                push eax
* lea eax, (aSCanTFindInsta - 3AEEh)[esi]  lea eax, (aSCanTFindInsta - 32BEh)[esi]
  push eax                                push eax
  call _printf                            call _printf
* jmp loc_3D05                            jmp loc_34D5
  mov eax, [ebx+edi*4-4]                  mov eax, [ebx+edi*4-4]
  add eax, 9                              add eax, 9
  push eax                                push eax
  call _atoi                              call _atoi
  mov edi, eax                            mov edi, eax
  add esp, 4                              add esp, 4
  cmp edi, 9                              cmp edi, 9
* jbe loc_3B60                            jbe loc_3330
* lea eax, (aErrorInitializ - 3AEEh)[esi]  lea eax, (aErrorInitializ - 32BEh)[esi]
  push eax                                push eax
* lea eax, (aSInvalidInstan - 3AEEh)[esi]  lea eax, (aSInvalidInstan - 32BEh)[esi]
  push eax                                push eax
  call _printf                            call _printf
* jmp loc_3D05                            jmp loc_34D5
  push 0Ah                                push 0Ah
* mov ebx, ds:(off_6018 - 3AEEh)[esi]     mov ebx, ds:(off_6018 - 32BEh)[esi]
  push ebx                                push ebx
  call _bzero                             call _bzero
  push edi                                push edi
* lea eax, (aPp - 3AEEh)[esi]             lea eax, (aPp - 32BEh)[esi]
  push eax                                push eax
* lea eax, (aDev - 3AEEh)[esi]            lea eax, (aDev - 32BEh)[esi]
  push eax                                push eax
* lea eax, (aSSD - 3AEEh)[esi]            lea eax, (aSSD - 32BEh)[esi]
  push eax                                push eax
  push ebx                                push ebx
  call _sprintf                           call _sprintf
  mov edx, esi                            mov edx, esi
* mov edx, [edx+4512h]                    mov edx, [edx+4D42h]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+4522h]                    mov edx, [edx+4D52h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov edi, eax                            mov edi, eax
  add esp, 24h                            add esp, 24h
  lea eax, [ebp+var_50]                   lea eax, [ebp+var_50]
  push eax                                push eax
  lea eax, [ebp+var_54]                   lea eax, [ebp+var_54]
  push eax                                push eax
  add ebx, 5                              add ebx, 5
  push ebx                                push ebx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+4516h]                    mov edx, [edx+4D46h]
  push edx                                push edx
  push edi                                push edi
  call _objc_msgSend                      call _objc_msgSend
  add esp, 14h                            add esp, 14h
  test eax, eax                           test eax, eax
* jz loc_3BE4                             jz loc_33B4
  push eax                                push eax
* lea eax, (aErrorInitializ - 3AEEh)[esi]  lea eax, (aErrorInitializ - 32BEh)[esi]
  push eax                                push eax
* lea eax, (aSCouldnTFindDr - 3AEEh)[esi]  lea eax, (aSCouldnTFindDr - 32BEh)[esi]
  push eax                                push eax
  call _printf                            call _printf
* jmp loc_3D05                            jmp loc_34D5
  mov [ebp+var_58], 0FFFFFFFFh            mov [ebp+var_58], 0FFFFFFFFh
  lea eax, [ebp+var_5C]                   lea eax, [ebp+var_5C]
  push eax                                push eax
  mov edx, [ebp+var_54]                   mov edx, [ebp+var_54]
  push edx                                push edx
* lea eax, (aIomajordevice - 3AEEh)[esi]  lea eax, (aIomajordevice - 32BEh)[esi]
  push eax                                push eax
  lea eax, [ebp+var_58]                   lea eax, [ebp+var_58]
  push eax                                push eax
  mov edx, esi                            mov edx, esi
* mov edx, [edx+451Ah]                    mov edx, [edx+4D4Ah]
  push edx                                push edx
  push edi                                push edi
  call _objc_msgSend                      call _objc_msgSend
  add esp, 18h                            add esp, 18h
  test eax, eax                           test eax, eax
* jz loc_3C30                             jz loc_3400
  push eax                                push eax
* lea eax, (aErrorInitializ - 3AEEh)[esi]  lea eax, (aErrorInitializ - 32BEh)[esi]
  push eax                                push eax
* lea eax, (aSCouldnTGetMaj - 3AEEh)[esi]  lea eax, (aSCouldnTGetMaj - 32BEh)[esi]
  push eax                                push eax
  call _printf                            call _printf
* jmp loc_3D05                            jmp loc_34D5
  mov [ebp+var_60], 0FFFFFFFFh            mov [ebp+var_60], 0FFFFFFFFh
  lea eax, [ebp+var_5C]                   lea eax, [ebp+var_5C]
  push eax                                push eax
  mov edx, [ebp+var_54]                   mov edx, [ebp+var_54]
  push edx                                push edx
* lea eax, (aIominordevice - 3AEEh)[esi]  lea eax, (aIominordevice - 32BEh)[esi]
  push eax                                push eax
  lea eax, [ebp+var_60]                   lea eax, [ebp+var_60]
  push eax                                push eax
  mov edx, esi                            mov edx, esi
* mov edx, [edx+451Ah]                    mov edx, [edx+4D4Ah]
  push edx                                push edx
  push edi                                push edi
  call _objc_msgSend                      call _objc_msgSend
  add esp, 18h                            add esp, 18h
  test eax, eax                           test eax, eax
* jz loc_3C7C                             jz loc_344C
  push eax                                push eax
* lea eax, (aErrorInitializ - 3AEEh)[esi]  lea eax, (aErrorInitializ - 32BEh)[esi]
  push eax                                push eax
* lea eax, (aSCouldnTGetMin - 3AEEh)[esi]  lea eax, (aSCouldnTGetMin - 32BEh)[esi]
  push eax                                push eax
  call _printf                            call _printf
* jmp loc_3D05                            jmp loc_34D5
* mov ebx, ds:(off_6018 - 3AEEh)[esi]     mov ebx, ds:(off_6018 - 32BEh)[esi]
  push ebx                                push ebx
  call _unlink                            call _unlink
  add esp, 4                              add esp, 4
  test eax, eax                           test eax, eax
* jz loc_3CB0                             jz loc_3480
* mov eax, ds:(_errno_ptr - 3AEEh)[esi]   mov eax, ds:(_errno_ptr - 32BEh)[esi]
  cmp dword ptr [eax], 2                  cmp dword ptr [eax], 2
* jz loc_3CB0                             jz loc_3480
  mov eax, [eax]                          mov eax, [eax]
  push eax                                push eax
  push ebx                                push ebx
* lea eax, (aErrorInitializ - 3AEEh)[esi]  lea eax, (aErrorInitializ - 32BEh)[esi]
  push eax                                push eax
* lea eax, (aSCouldNotDelet - 3AEEh)[esi]  lea eax, (aSCouldNotDelet - 32BEh)[esi]
* jmp loc_3CFF                            jmp loc_34CF
  push 0                                  push 0
  call _umask                             call _umask
  mov eax, [ebp+var_58]                   mov eax, [ebp+var_58]
  shl eax, 8                              shl eax, 8
  or eax, [ebp+var_60]                    or eax, [ebp+var_60]
  push eax                                push eax
  push 21B6h                              push 21B6h
  mov edx, esi                            mov edx, esi
* mov edx, [edx+252Ah]                    mov edx, [edx+2D5Ah]
  push edx                                push edx
  call _mknod                             call _mknod
  add esp, 10h                            add esp, 10h
  test eax, eax                           test eax, eax
* jnz loc_3CE0                            jnz loc_34B0
  xor eax, eax                            xor eax, eax
* jmp loc_3D0A                            jmp loc_34DA
* mov eax, ds:(_errno_ptr - 3AEEh)[esi]   mov eax, ds:(_errno_ptr - 32BEh)[esi]
  mov eax, [eax]                          mov eax, [eax]
  push eax                                push eax
  mov edx, esi                            mov edx, esi
* mov edx, [edx+252Ah]                    mov edx, [edx+2D5Ah]
  push edx                                push edx
* lea eax, (aErrorInitializ - 3AEEh)[esi]  lea eax, (aErrorInitializ - 32BEh)[esi]
  push eax                                push eax
* lea eax, (aSCouldNotCreat - 3AEEh)[esi]  lea eax, (aSCouldNotCreat - 32BEh)[esi]
  push eax                                push eax
  call _printf                            call _printf
  mov eax, 0FFFFFFFFh                     mov eax, 0FFFFFFFFh
  lea esp, [ebp-6Ch]                      lea esp, [ebp-6Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn

_mig_dealloc_reply_port
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_mig_dealloc_reply_port_ptr - 5E9Ch)[eax]  mov edx, ds:(_bcopy_ptr - 5E55h)[eax]
  jmp edx                                 jmp edx

_mig_get_reply_port
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_mig_get_reply_port_ptr - 5ED0h)[eax]  mov edx, ds:(_msg_rpc_ptr - 5E89h)[eax]
  jmp edx                                 jmp edx

_mknod
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_mknod_ptr - 5D7Eh)[eax]   mov edx, ds:(_mknod_ptr - 5D37h)[eax]
  jmp edx                                 jmp edx

_msg_rpc
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_msg_rpc_ptr - 5EB6h)[eax]  mov edx, ds:(_mig_dealloc_reply_port_ptr - 5E6Fh)[eax]
  jmp edx                                 jmp edx

_objc_msgSend
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_objc_msgSend_ptr - 5DCCh)[eax]  mov edx, ds:(_objc_msgSend_ptr - 5D85h)[eax]
  jmp edx                                 jmp edx

_printf
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_printf_ptr - 5E34h)[eax]  mov edx, ds:(_printf_ptr - 5DEDh)[eax]
  jmp edx                                 jmp edx

_sprintf
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_sprintf_ptr - 5DE6h)[eax]  mov edx, ds:(_sprintf_ptr - 5D9Fh)[eax]
  jmp edx                                 jmp edx

_strncmp
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_strncmp_ptr - 5E4Eh)[eax]  mov edx, ds:(_strncmp_ptr - 5E07h)[eax]
  jmp edx                                 jmp edx

_umask
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_umask_ptr - 5D98h)[eax]   mov edx, ds:(_umask_ptr - 5D51h)[eax]
  jmp edx                                 jmp edx

_unlink
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  call $+5                                call $+5
  pop eax                                 pop eax
* mov edx, ds:(_unlink_ptr - 5DB2h)[eax]  mov edx, ds:(_unlink_ptr - 5D6Bh)[eax]
  jmp edx                                 jmp edx

dyld_stub_binding_helper
  status=different raw_equal=False masked_equal=False
  reason: function range bytes differ

  reference                               rebuilt                               
  push 2000h                              push 2000h
  jmp ds:dyld_lazy_symbol_binding_entry_point  jmp ds:dyld_lazy_symbol_binding_entry_point
