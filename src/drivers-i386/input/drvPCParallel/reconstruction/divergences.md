# drvPCParallel reconstruction divergences

Report pass over Apple's shipped `ParallelPort_reloc`
(`reference_sha256` `D188A4D909005683B0C943C84CD99514C14A84AD1D378425B3B1DB343F1EAAA2`,
45312 bytes, `MH_OBJECT` i386). This document records where our reimplementation in
`src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/`
diverges from that binary. **It changes no driver source.** Task 10 does the fixing.

Line numbers are against the current committed tree (`IOParallelPort.m` 1070 lines,
`IOParallelPortKern.m` 1360 lines, `IOParallelPort.h` 233, `IOParallelPortKern.h` 119),
verified with `git status` before the pass began.

---

## 1. Coverage and examination depth

The reference partitions into **75 functions**: 73 hand-written plus 2 pieces of
build-generated Kernel Server glue. All 73 are mapped; the 2 glue functions are
`unmapped` by design.

| Depth | Count | What was done |
|---|---|---|
| `assembly-matched` | 30 | Every instruction read, and no divergence found |
| `control-flow-confirmed` | 1 | Block shape and every call target checked; a short stretch not read instruction by instruction |
| `unexamined` | 42 | Every instruction read, **and a divergence found** — these carry a finding below |
| `intentional-mismatch` | 2 | Build-generated glue, not present in source |

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

**Finding 29 — roughly thirty `sel_getUid("…")` literals emit `__cstring` entries the
reference does not have.** Throughout `IOParallelPortKern.m`. The reference's 476-byte
`__cstring` contains exactly fifteen entries and **not one is a selector**; every message
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
`IOParallelPort.m:536`. The reference initialises its return value to `0` at 3268 and only
assigns `cmdBuffer->returnCode` in the `IO_R_TIMEOUT` arm (3403) and the default arm. For
`IO_R_NOT_READY`, `IO_R_OFFLINE`, `IO_R_NO_PAPER` and `IO_R_BUSY` it sets the status bit
and **returns 0**. Ours assigns `returnCode = cmdBuffer->returnCode` before the switch and
so returns the error. This changes what `_ppstrategy` sees and hence the `errno` the
caller gets.

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
the opposite. Because `msgTypeToIOReturn:` maps `0x232336` to `IO_R_TIMEOUT` (-714) and
`0x232339` to `IO_R_OFFLINE` (-738), our version reports a timeout when the printer goes
offline. The `#define` names in `IOParallelPortKern.h`/`.m` compound the confusion:
`PP_INT_MSG_OFFLINE` is `0x232336`, which the reference's own switch maps to *timeout*.
The rest of the decode — the `(status & 0x28) == 0x08` arm, the busy test and the
paper-out test — matches.

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
— the 8192-byte `IOMalloc` from init — to `msg_receive` with `MSG_OPTION_RCV_LARGE`. Ours
calls the accessor for its side effect and then hands `msg_receive` a small stack struct,
which is what `RCV_LARGE` is meant to avoid. Everything else in the loop matches,
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

### Linkage and packaging

**Finding 54 — linkage differs, and `parity_check.py` cannot see it.** Reading the
reference's nlist:

- `-[IOParallelPort _waitForDevice:isReady:]` (0) is **`global`**; all 61 other instance
  methods and `+probe:` are `local`. This is an artefact of it being the first symbol in
  `__text`, but Task 10 should confirm rather than assume.
- `__strobeChar` (4232), `_IOParallelPortThread` (4512) and
  `_IOParallelPortInterruptHandler` (5240) are **`global`**.
- All seven `cdevsw` entry points — `_ppopen` (5520), `_ppclose` (5652), `_ppread` (5692),
  `_ppwrite` (5828), `_ppminphys` (6252), `_ppstrategy` (6304), `_ppioctl` (6708) — are
  **`local`**, i.e. declared `static` in the reference source. Ours declares all seven in
  `IOParallelPortKern.h:98-104`, making them external.
- `_pp_softc` (8192) is `local`; ours has one `static` and one external definition
  (Finding 37).
- `_ParallelPort_instance` (8216, `__common`, `global`) and the three `_xxx.NNN` counters
  in `__bss` are compiler- and glue-generated.

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

- Whether `-[IOParallelPort _waitForDevice:isReady:]`'s `global` binding is meaningful or
  merely an artefact of being the first `__text` symbol. Task 10 can settle it by checking
  whether our rebuilt binary reproduces it without any source change.
- The reference ivar `dataRegisterData` (`C`, 0x134) is never read or written by any of the
  75 functions. Its purpose is unknown; it is presumably vestigial. Ours has no
  counterpart, and adding one is needed only for layout fidelity.
- The exact declared type of the reference's `_pp_softc` struct. The three fields and the
  12-byte size are certain from nine independent access sites; the field *names* are not
  recoverable from the binary.
- Whether the `-725` (`IO_R_BUSY`) arm that our first `_IOParallelPortThread` decode
  produces (Finding 47) is reachable in the reference by some path not visible in the
  static control flow. Reading the disassembly, it is not.
