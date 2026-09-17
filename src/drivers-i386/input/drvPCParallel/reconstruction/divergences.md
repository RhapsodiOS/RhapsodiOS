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

### Task 8 — remaining large functions

### 8.9 The status rule used

- `assembly-matched` (57) - the reference's full instruction stream was read and our
  source is a statement-for-statement transliteration of it with no remaining difference,
  and the function's emitted metadata was verified identical in the rebuilt binary. Used
  for the accessors and the short bodies. Task 8 promoted `msgTypeToIOReturn:`,
  `cmdBufAlloc`, and `_ppstrategy` (`masked_equal`).
- `control-flow-confirmed` (0) - the reference's full instruction stream was read and our
  source reproduces its block structure, every call target and every constant, but the
  rebuilt output was **not** itself disassembled and compared instruction by instruction.
  Used for the larger functions.
- `intentional-mismatch` (18) - a deliberate difference remains: 0 (`_waitForDevice:isReady:`
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
  456 (`initFromDeviceDescription:` extra `var_20` / register choice), 4512
  (`_IOParallelPortThread` commandType test vs cmp / status slot), 5240
  (`_IOParallelPortInterruptHandler` decode invert; leftover is `inb` slot vs `dl`), 5828
  (`_ppwrite` signed initDevice range without pre-zeroed locals; leftover is
  `esi` vs `ebx` and Apple's extra zeroing), 6708 (`_ppioctl` signed `int cmd` /
  GET-then-SET grouping; leftover is getter/setter tail-merge),
  7392 and 7404, untouched from the report pass.
