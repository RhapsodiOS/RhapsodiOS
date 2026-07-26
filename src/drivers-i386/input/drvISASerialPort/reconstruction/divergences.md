# drvISASerialPort reconstruction divergences

Report pass over Apple's shipped `ISASerialPort_reloc`
(`reference_sha256` `4CAA1BB9E8CE3309560F14E352F3D68902EA1C59937DC84DBB5EBCDA330EA932`,
67328 bytes, i386). This document records where our reimplementation in
`src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/`
diverges from that binary.

Analyzers: **IDA 9.2 and angr 9.3.0 only** — see section 2.

**This is a report pass. No driver source was changed.** Line numbers are against the tree as
committed alongside this document (`ISASerialPort.m` 5349 lines, `ISASerialPort.h` 321 lines).
Tasks 3 to 6 do the fixing, translation unit by translation unit; every finding below is written
so that those tasks do not have to reopen the binary.

---

## 1. Coverage and examination depth

The reference partitions into **45 functions**: 41 hand-written, 2 pieces of build-generated
Kernel Server glue, and 2 libgcc 64-bit division helpers. 43 are `mapped`; the 2 glue functions
are `unmapped` by design.

| Bucket | Count |
|---|---|
| `mapped` | 43 |
| `unmapped` | 2 |
| `duplicate_candidates` | 0 |
| `boundary_disputed` | 0 |

Ledger status:

| Status | Count | Meaning here |
|---|---|---|
| `unexamined` | 41 | A divergence was found — each carries a finding below |
| `intentional-mismatch` | 2 | Build-generated glue, not present in source |
| `assembly-matched` | 2 | `nextEvent` (6400) and `release` (5448) — already correct |
| `control-flow-confirmed` | 0 | — |

**Only two of the 43 mapped functions match, and that is the honest result.** The other 41 diverge,
because the divergence is structural and global: the reference keeps all driver state in
one 304-byte `Port` struct reached through a single pointer ivar, and our source spreads that state
across 68 invented instance variables (section 4.1). Every C function's first parameter and every
method's state access is therefore wrong in our tree, independently of whether the algorithm above
it is right.

**The two exceptions are `-[ISASerialPort nextEvent]` (6400) and `-[ISASerialPort release]`
(5448), and they are exceptions for the same reason: neither reads a single named ivar.** Both
reach every field through raw `(char *)self` offset casts that never consult `ISASerialPort.h`, so
the layout change cannot touch them, and both already reproduce the reference. They are
`assembly-matched` now, not after the layout fix. `release`'s comments mislabel three fields
(Finding 91) but comments do not reach the assembly. **Tasks 3-6 must not rewrite either body.**

Several other functions — `_flowMachine`, `_watchState`, `-[ISASerialPort free]`,
`-[ISASerialPort requestEvent:data:]`, `-[ISASerialPort dequeueEvent:data:sleep:]` — have
algorithms that match the reference closely and would reach `assembly-matched` once the layout is
fixed. They are called out as such in their findings so Tasks 3-6 know where the cheap wins are.

`unexamined` is used, per the ledger convention, for a function that diverges — **not** for one
that was skipped. No function in this driver was skipped.

**Where to find each function's verdict in `ledger.json`.** `binrecon.ledger` reserves the `reason`
field for `intentional-mismatch` entries and rejects it on any other status
(`tools/binrecon/binrecon/ledger.py:182`), so the 41 `unexamined` entries and the 2
`assembly-matched` entries all carry `reason: null`. Each one's per-function verdict is the **third
element of `analyzer_agreement.reasons`**, prefixed `report pass:`; the first element is the shared
IDA-versus-angr note and the second states the depth actually reached. The two glue entries carry
their reason in the `reason` field as the schema requires.

**Advancing an entry out of `unexamined` — read this before trying.**
`tools/binrecon/binrecon/ledger.py` defines
`_ORDER = ("unexamined", "signature-confirmed", "control-flow-confirmed", "assembly-matched")` and
`transition()` enforces two rules that will otherwise cost a later task an hour:

1. **`ledger.py:270` — skipping states is forbidden.** `unexamined` → `assembly-matched` in one call
   raises `skipping ledger states is forbidden`. You must step one rung at a time.
2. **`ledger.py:262` — `unexamined` → `intentional-mismatch` is forbidden.** It "requires a reviewed
   state", so an entry must first reach at least `signature-confirmed`.

So Tasks 3-6 must either issue **successive** `binrecon ledger --address … --status …` calls, one per
rung, or edit `ledger.json` directly and then revalidate with a plain
`binrecon ledger --profile … --ledger …` (no transition flags — it loads, validates and prints the
counts). Note that a direct edit must preserve this file's on-disk shape: `json.dumps` with
`indent=1`, `sort_keys=True`, CRLF line endings. The CLI's own writer emits **compact** JSON, so
letting it write the file reformats the whole thing into one line. `binrecon ledger` also leaves a
`ledger.json.lock` beside the ledger — delete it before staging; it belongs in no commit.

### Depth actually reached, per function

Stated honestly, because a reviewer will spot-check it.

**Every instruction read (38 functions):** all three copies of `_RX_enqueueLongEvent`,
`_watchState`, `_flowMachine`, `_deactivatePort`, `_frameTOHandler`, `_delayTOHandler`,
`_heartBeatTOHandler`, `_PCMCIA_yanked`, `_validateRingBufferSize`, `_freeRingBuffer`,
`_allocateRingBuffer`, `_identifyChip`, `_initChip`, `_programChip`, `_TX_enqueueEvent`,
`_RX_dequeueEvent`, `_RX_dequeueData`, `+[ISASerialPort probe:]`,
`-[ISASerialPort initFromDeviceDescription:]`, `free`, `getHandler:level:argument:forInterrupt:`,
`getCharValues:forParameter:count:`, `acquire:`, `release`, `setState:mask:`, `getState`,
`watchState:mask:`, `nextEvent`, `executeEvent:data:`, `requestEvent:data:`,
`enqueueEvent:data:sleep:`, `dequeueEvent:data:sleep:`,
`enqueueData:bufferSize:transferCount:sleep:`, `dequeueData:bufferSize:transferCount:minCount:`,
and both glue stubs.

**Every instruction read, with repeated inlined blocks confirmed by pattern rather than re-derived
(3 functions):** `_FIFOIntHandler` (880 instructions; 2 of the 5 inlined TX-dequeue copies read
instruction by instruction, the other 3 confirmed as the same mnemonic sequence with different
stack slots), `_NonFIFOIntHandler` (682; 2 of 3), `_executeEvent` (672; 1 of 2 RX and 1 of 2 TX
watermark-recompute copies).

**Control-flow depth only (2 functions):** `_activatePort` (86 blocks — every call target, every
port access and every `Port` field reference extracted and checked, but not every arithmetic
instruction) and `_dataLatTOHandler` (186 instructions — the first 90 read instruction by
instruction, the remainder at block-and-field level).

**Not read instruction by instruction (2 functions):** `__udivdi3` and `__umoddi3`. For these only
the mnemonic inventory, the relocation list and the block count were examined. That is enough to
establish the findings recorded against them (Findings 94 and 95) and no more.

38 + 3 + 2 + 2 = 45.

The ObjC metadata was decoded directly out of the binary — `__OBJC,__instance_vars`,
`__module_info`, `__class_names`, `__protocol`, `__class`, `__DATA,__data`, `__DATA,__bss`,
`__TEXT,__const`, `__TEXT,__cstring`, `Loaded Server,*` — not inferred from disassembly.

## 2. Stated limitations

- **Two analyzers, not three — a limitation of this driver's evidence.** Ghidra is disabled in
  `tools/binrecon/profiles/isaserialport.json` because normalization aborts with
  `Ghidra relocation operand metadata is ambiguous` (`tools/binrecon/binrecon/normalize.py:432`),
  which leaves `complete: false` and no reference consensus. There is therefore **no**
  `analysis-reference-ghidra.json`, `run-summary.json`'s `analyzers` list has **two** entries, and
  every analyzer-agreement statement in this document and in `ledger.json` compares **IDA against
  angr only**. Do not re-enable Ghidra for this driver.
- **`binrecon analyze` exits 1 on this profile and that is success.** A reference-only profile can
  never satisfy `normalized-functions` acceptance, which compares a reference against a *rebuilt*
  artifact. The gate is `complete: true` plus a reference consensus, both of which hold.
- **`parity_check.py` compares symbol NAMES only.** It cannot see linkage. Eleven of the
  reference's `__TEXT,__text` symbols are **external** and all of ours are `static` (Finding 1).
  That difference is invisible to parity counts. **Tasks 3 to 6 must verify linkage by reading the
  rebuilt binary's nlist** — `binrecon.macho.read_macho`, checking each symbol's `binding` and
  `section` — and not by `parity_check.py` output.
- **`__TEXT,__const` cannot be brought to parity in this environment.** The reference's 682 bytes
  are exactly `_ISASerialPort_VERS_STRING` (160) + `_ISASerialPort_VERS_NUM` (10) + **two copies of
  `___clz_tab` (256 each)**. Both `___clz_tab` copies are **unreferenced**: the reference's
  `__udivdi3`/`__umoddi3` use `bsr`, not the table, and carry it only because it sits in the same
  libgcc object. `/usr/lib/libcc.a` on the guest is a PPC archive that cannot load for
  `-arch i386`, so we cannot link the real libgcc objects and `___clz_tab` stays absent. 512 of
  those 682 bytes are structurally unreachable for us. Recorded as an environment limitation, not a
  defect.
- **Our source's inline comments are not evidence.** Several are wrong in ways that produced wrong
  verdicts elsewhere in this effort. Findings 33 to 37 are all cases where the comment beside a
  named constant contradicts the constant's definition. Every constant in this document was
  resolved to its definition — `IO_R_*` against `src/driverkit-3/driverkit/return.h`, `outb`/`inb`
  against `src/driverkit-3/driverkit/i386/ioPorts.h`, `THREAD_RESTART` against
  `src/kernel-7/kern/sched_prim.h`.
- **`out/i386/drvISASerialPort/.../ISASerialPort_reloc`, if present in the worktree, is OUR build,
  not Apple's.** Anyone reading strings or sections from that path gets our own. All evidence here
  comes from the reference path recorded in `analysis-reference-ida.json`.

## 3. Analyzer agreement

IDA reports **45** functions; angr reports **353** function starts. angr's set is a strict superset
— there are **no IDA-only starts** — and **all 45 shared starts agree exactly on size**. The
partition is therefore agreed; only granularity differs.

The 308 angr-only starts break down as:

| Kind | Count | Note |
|---|---|---|
| Interior to an IDA function | 283 | CFGFast promotes finely-split basic blocks to function starts |
| On inter-function `nop` alignment padding | 23 | e.g. 197, 261 — the 1-3 pad bytes the linker inserts |
| In `__TEXT,__const` **data** | 2 | `_ISASerialPort_VERS_NUM` @25314 and `___clz_tab` @25324, disassembled as code |

angr's basic-block count is greater than or equal to IDA's in **every** shared function; 31 of the
45 differ. **IDA is authoritative for the function partition** throughout this effort, and its
function extents run 1-3 bytes shorter than the symbol-address gaps because the linker pads with
`nop`. That is normal and is not an analyzer disagreement. `load_source_map` checks sizes against
the IDA analysis, so `source-map.json` carries IDA's extents.

## 4. The four decodes Tasks 3-6 depend on

### 4.1 The reference's instance variables — 28 bytes, and there are exactly two

`__OBJC,__instance_vars` is 28 bytes = a 4-byte count plus **two** 12-byte entries. Ours is 820
bytes = 4 + 68 x 12, i.e. **68 instance variables**. Decoded from the section:

| # | name | type encoding | ivar offset |
|---|---|---|---|
| 0 | `Port` | inline anonymous struct, 304 bytes | **296** (`0x128`) |
| 1 | `port` | `^{?}` — pointer to that struct | **600** (`0x258`) |

296 + 304 = 600 is self-consistent, and `-[ISASerialPort initFromDeviceDescription:]` proves the
relationship directly at 273-294:

```
273: mov edi, [ebp+self]
276: add edi, 128h
282: mov esi, [ebp+self]
285: mov [esi+258h], edi     ; self->port = &self->Port
291: mov edi, [ebp+self]
294: mov [esi+128h], edi     ; self->Port.Self = self
```

**All driver state lives in that one struct.** Apple's own field names come out of the type
encoding, which the section stores in full:

```
  0 Self @              (id, points back at the object)
  4 Instance I
  8 PortName *          (char *, = [self name])
 12 State L             <-- ONE 32-bit field. Bytes 12,13,14,15.
 16 WatchStateMask L
 20 WatchLock {locked I}
 24 RX  <Queue, 56 bytes>
 80 TX  <Queue, 56 bytes>
136 Base I              (I/O base port)
140 IRQ I
144 Type I              (index into _Chip[])
148 CharLength I        (half-bit units: 16 == 8 data bits)
152 StopBits I          (half-bit units: 2 == 1 stop bit)
156 TX_Parity I
160 RX_Parity I
164 BreakLength I
168 BaudRate L          (half-bits/s: 19200 == 9600 bps)
172 DLRimage S
174 LCRimage C
175 FCRimage C
176 IERmask C
177 RBRmask C
180 MasterClock L
184 MinLatency c
185 WaitingForTXIdle c
186 JustDoneInterrupt c
187 PCMCIA c
188 PCMCIA_yanked c
189 XONchar C
190 XOFFchar C
192 SWspecial [8L]      (32 bytes = a 256-bit character bitmap)
224 FlowControl L       <-- 32 bits, NOT a byte
228 RXOstate i          (signed)
232 FrameTOEntry ^v
236 DataLatTOEntry ^v
240 DelayTOEntry ^v
244 HeartBeatTOEntry ^v
248 FrameInterval     {tv_sec I, tv_nsec i}
256 DataLatInterval   {tv_sec I, tv_nsec i}
264 CharLatInterval   {tv_sec I, tv_nsec i}
272 HeartBeatInterval {tv_sec I, tv_nsec i}
280 Stats {ints L, txInts L, rxInts L, mdmInts L, txChars L, rxChars L}
    -> 280 ints, 284 txInts, 288 rxInts, 292 mdmInts, 296 txChars, 300 rxChars
304 = sizeof
```

`Queue`, 56 bytes, `RX` at 24 and `TX` at 80. Offsets are **relative to the Queue base**, because
`_validateRingBufferSize`, `_freeRingBuffer` and `_allocateRingBuffer` take a `Queue *` directly:

```
 0 Size I          16 Enqueue I      32 Input *        48 AllocSize I
 4 Count I         20 Dequeue I      36 Output *       52 AllocBase *
 8 HighWater I     24 Base *         40 OverRun I
12 LowWater I      28 End *          44 DefaultSize I
```

`Size`, `Count`, `HighWater`, `LowWater`, `Enqueue` and `Dequeue` are counts of **2-byte cells**,
not bytes: `AllocSize = Size*2 + 2` and `End = Base + Size*2`, and `-[ISASerialPort nextEvent]`
steps by `Size*2` at 6446. `Enqueue` and `Dequeue` are hysteresis thresholds — the next queue level
at which a state change must be reported — not pointers.

The layout is corroborated at four independent points, which is why it can be relied on:
`-[ISASerialPort getState]` reads `[self+134h]` = 296+12 = `State`; `_PCMCIA_yanked` writes
`[port+0BCh]` = 188 = `PCMCIA_yanked`; the second ivar's offset 600 equals 296+304; and our own
source at `ISASerialPort.m:3963` already contains `*(unsigned int *)((char *)self + 0x1b8)`, which
is 296+144 = `Port.Type` — a decompiler leftover that accidentally records the true layout.

**Consequence, and the reason this section is first.** Our header's ivar offset comments (`0x88`,
`0xbc`, `0xe0`, ...) are in fact *this struct's* offsets, which is why they look plausible and why
the arithmetic in much of our source is right. What is wrong is the **base**: those offsets are
relative to the `Port` struct, not to the object. Task 3 must adopt the two-ivar layout. Our source
is currently split between two mutually incompatible styles — `requestEvent:data:`, `nextEvent` and
`release` use raw `self + 0x1xx` casts, while `acquire:`, `enqueueData:` and the C functions use
named ivars (which all need rewriting). Do not convert the raw-offset half to named ivars.

**The raw-offset half is not waiting on the layout fix; it is already emitting the reference's
offsets.** A raw `*(T *)((char *)self + N)` never consults `ISASerialPort.h`, so replacing 68 ivars
with two changes nothing about what it compiles to. That is why `nextEvent` (6400) and `release`
(5448) are `assembly-matched` **now** — they use raw casts exclusively and no named ivar at all
(Findings 91, 92). `requestEvent:data:` is in the same style but has independent divergences
(Findings 31 and 92) and so is not yet matched.

**Fields the reference does not have at all**, and which our header invents: `hasFIFO`,
`deviceDescription`, `timerPending`, `heartBeatPending`, `pcmciaDetect`, `chipType` as distinct
from `Type`, `charTimeNS`/`charTimeFracNS` as a 64-bit nanosecond pair, `heartBeatInterval` as an
`unsigned long long`, `defaultRingBufferSize` as one object-wide value, and the three-way split of
`State` into `currentState`/`flags`/`statusFlags`.

### 4.2 `_Chip` — all 180 bytes, field by field

`_Chip` is at `__DATA,__data` +0 (address 32768), 180 bytes, and is an **external, non-`const`**
symbol. Nine entries of **20 bytes**; stride confirmed from the addressing
(`lea eax,[eax+eax*4]` then scale 4).

| offset | field | type |
|---|---|---|
| +0 | `MaxBaud` | `unsigned long`, half-bits/s |
| +4 | `FIFOsize` | `unsigned int` |
| +8 | `IntHandler` | function pointer |
| +12 | `ShortName` | `char *` — matched against the `"Chip Type"` Instance-table key |
| +16 | `LongName` | `char *` — printed in the banner |

| idx | MaxBaud | FIFO | IntHandler | ShortName | LongName |
|---|---|---|---|---|---|
| 0 | 0 | 0 | `_NonFIFOIntHandler` (16232) | `Auto` | `Unknown` |
| 1 | 38400 | 0 | `_NonFIFOIntHandler` | `8250` | `8250` |
| 2 | 76800 | 0 | `_NonFIFOIntHandler` | `16450` | `8250A or 16450` |
| 3 | 76800 | 0 | `_NonFIFOIntHandler` | `16450` | `16C1450` |
| 4 | 76800 | 0 | `_NonFIFOIntHandler` | `16450` | `16550 with defective FIFO` |
| 5 | 230400 | 16 | `_FIFOIntHandler` (13060) | `16550` | `16550AF/C/CF` |
| 6 | 230400 | 16 | `_FIFOIntHandler` | `16550` | `16C1550` |
| 7 | 921600 | 32 | `_FIFOIntHandler` | `16650` | `ST16C650` |
| 8 | 230400 | 4 | `_NonFIFOIntHandler` | `82510` | `82510` |

The task brief lists twelve part names. Those twelve are the nine `LongName`s plus the distinct
extra `ShortName`s, and the brief's list omits a **thirteenth** string, `"Auto"` at 24528, which is
entry 0's `ShortName`. All thirteen live in `__TEXT,__cstring` at 24412-24532.

Note that `Type > 4` is exactly equivalent to `_Chip[Type].FIFOsize != 0`, which is the test
`_activatePort` (3161) and `_executeEvent` (11251, 11696) actually use.

The dispatch idiom, which appears in `_frameTOHandler`, `_delayTOHandler`, `_heartBeatTOHandler`
and `getHandler:level:argument:forInterrupt:`:

```
mov eax, [port+90h]                  ; port->Type
lea eax, [eax+eax*4]                 ; x5 dwords = x20 bytes
mov eax, ds:_Chip+8[eax*4]           ; .IntHandler
push port ; push 0 ; push 0 ; call eax
                                     ; => _Chip[port->Type].IntHandler(0, 0, port)
```

### 4.3 `_msr_state_lut` — 16 bytes

`__DATA,__data` +180 (address 32948), 16 bytes, also **external and non-`const`**:

```
00 01 08 09 04 05 0C 0D 02 03 0A 0B 06 07 0E 0F
```

It swaps bits 1 and 3 of the index, leaving bits 0 and 2 alone. Indexed by the MSR high nibble, it
maps the hardware bit order (bit0 CTS, bit1 DSR, bit2 RI, bit3 DCD) into the driver's `State` order
(bit0 CTS, bit1 DCD, bit2 RI, bit3 DSR). Both interrupt handlers and `acquire:` use it as

```
State = (State & ~0x1E0) | (_msr_state_lut[(MSR >> 4) & 0x0F] << 5)
```

**Our copy (`ISASerialPort.m:110-113`) is the identity table `0..15` and is wrong**, so DSR and DCD
are transposed in every state report. See Finding 3.

Together `_Chip` (180) and `_msr_state_lut` (16) are the **whole** of the reference's 196-byte
`__DATA,__data`. Ours holds those two as `static const` in `__TEXT,__const` (180 + 16 = our 196
bytes there) and puts a 36-byte `chipTypeNames[]` pointer array in `__DATA,__data`. Deleting
`chipTypeNames` (its contents belong in `_Chip`'s `ShortName`/`LongName`) and making both tables
external and non-`const` should bring `__DATA,__data` to exactly 196.

### 4.4 The four translation units — confirmed, not assumed

`src/driverkit-3/driverkit/i386/ioPorts.h` defines `outb`, `outw` and `outl` as `static __inline__`
functions, each containing its own `static int xxx;` and inline asm of the form
`"outb %2,%1; lock; incl %0"` with `xxx` as an output operand. Each translation unit that includes
the header therefore gets **three** function-local statics in `__DATA,__bss`.

The reference's `__DATA,__bss` is **48 bytes** = 12 dwords = **four** groups of three, and IDA
disambiguates the referenced copies as `_xxx_86`, `_xxx_86_0`, `_xxx_86_1`. Which functions
increment which copy pins the boundaries directly:

| TU | `__bss` group | addresses | functions incrementing it |
|---|---|---|---|
| 1 | `_xxx_86` @32964 | 0 - 18703 | `_activatePort`, `_deactivatePort`, `acquire:`, `release`, `setState:mask:`, `executeEvent:data:`, `enqueueData:...`, `_dataLatTOHandler`, `_executeEvent`, `_FIFOIntHandler`, `_NonFIFOIntHandler` |
| 2 | `_xxx_86_0` @32976 | 18704 - 20683 | `_identifyChip`, `_initChip`, `_programChip` |
| 3 | `_xxx_86_1` @32988 | 20684 - 23199 | `_TX_enqueueEvent`, `_RX_dequeueEvent`, `_RX_dequeueData` |
| 4 | @33000, unreferenced — **owner not established**, see the risk note below | 23200 - 23775 | none — TU 4 performs no port I/O |

The plan's boundaries 18704, 20684, 23200 and 23776 are all confirmed. `_RX_enqueueLongEvent` is a
`static` defined in a shared header and emitted in TUs 1, 3 and 4 — and **not** in TU 2, exactly as
the plan predicted. The three copies are **byte-identical**: all three are 193 instruction bytes
with the same SHA-256 over the concatenated instruction encodings, padded to a 197-byte extent.

The `.89` and `.92` statics (`outw` and `outl`) are allocated in all four groups but **never
referenced** — the driver only ever does byte-width port writes. Across the whole binary there are
59 `out` and 20 `in` instructions, and **every one of the 59 `out`s is followed by a `lock incl` of
its TU's `.86` copy, while no `in` is.** That is the mechanical signature of `ioPorts.h`'s `outb`,
and it is the key to Finding 4.

**`ISASerialPort.m` is the only source filename recorded anywhere in the binary.**
`__OBJC,__module_info` is 32 bytes / 2 modules, naming exactly `ISASerialPort.m` and the
build-generated `ISASerialPort_instance.m`; `__OBJC,__class_names` contains the same two and no
others. **`ISASerialPortChip.c`, `ISASerialPortQueue.c` and `ISASerialPortFlow.c` are OUR names for
TUs 2, 3 and 4, not Apple's.** Apple's filenames for them are not recoverable from this binary. Do
not let a later reader take those three names for recovered facts.

The class conforms to a **`PortDevices`** protocol: `__OBJC,__protocol` has `protocol_name` pointing
at `"PortDevices"` in `__OBJC,__class_names` and `instance_methods` pointing at
`__OBJC,__cat_inst_meth`.

**A risk Task 3 must plan for.** TU 4 (`_RX_enqueueLongEvent`, `_flowMachine`, `_watchState`)
contains **no `out` instruction at all**, yet the reference still emits a fourth copy of all three
`xxx` statics. The mechanism is not established, and there are **two** live hypotheses:

1. **The fourth group belongs to TU 4** — gcc 2.7 emitting the statics for a parsed
   `static __inline__` whose calls were all optimised away.
2. **The fourth group does not belong to TU 4 at all** — it belongs to the build-generated
   `ISASerialPort_instance.m`, which `__OBJC,__module_info` and `__OBJC,__class_names` both name as
   the binary's second module. That file includes the driver headers, so it would pick up
   `ioPorts.h` and its three statics for exactly the same reason and without performing any port
   I/O. On this reading the four `__bss` groups are TU 1, TU 2, TU 3 and the instance glue, and TU 4
   contributes nothing — which is also consistent with the fourth group being **unreferenced**.

**The binary cannot decide between them, and that is not a gap in the reading.** Both hypotheses
predict an identical section layout: four groups of three dwords, 48 bytes, the fourth never
referenced. There is no observable in the reference that separates a group emitted-and-unused by
TU 4 from a group emitted-and-unused by the instance file, because the linker records neither one's
origin. Resolving it needs a rebuild, not more disassembly.

**The failure mode is the same under either hypothesis, so plan for it once.** If our TU-4 `.c`
file performs no `outb` and our `ISASerialPort_instance.m` does not supply a fourth group either,
`__DATA,__bss` comes out **36 bytes instead of 48** and that section will not match. It is a visible,
unambiguous 36-versus-48 diff at rebuild — not a silent one — so **do not assume** either mechanism.
Verify it against the rebuilt nlist rather than reasoning about it, and let which hypothesis is true
fall out of what the rebuild produces.

## 5. The eleven exported functions' real signatures, and the `.c`-versus-`.m` question

Eleven `__TEXT,__text` symbols are **external** in the reference. All eleven are `static` in ours
(Finding 1). Their real parameter lists, derived from what each caller pushes and what each callee
reads off its stack frame — **not** from our source, whose signatures are decompiler artifacts:

| Function | Real signature | Return used by callers? |
|---|---|---|
| `_identifyChip` | `int (Port *)` | yes — stored into `port->Type` |
| `_initChip` | `void (Port *)` | no |
| `_programChip` | `void (Port *)` | no (all six sites discard) |
| `_TX_enqueueEvent` | `IOReturn (Port *, unsigned char event, unsigned int data, signed char sleep)` | yes |
| `_RX_dequeueEvent` | `IOReturn (Port *, unsigned char *eventType, unsigned int *eventData, signed char sleep)` | yes |
| `_RX_dequeueData` | `IOReturn (Port *, unsigned char *byteOut, signed char sleep)` | yes |
| `_validateRingBufferSize` | `unsigned int (unsigned int requestedSize, Queue *)` | yes |
| `_freeRingBuffer` | `void (Queue *)` | no |
| `_allocateRingBuffer` | `int (Queue *)` — a **BOOL**, `test al,al` at both call sites | yes |
| `_flowMachine` | `unsigned int (Port *)` — returns the new `State` | yes |
| `_watchState` | `IOReturn (Port *, unsigned int *state, unsigned int mask)` | yes |

**Not one of the eleven takes an `ISASerialPort *`.** Every one takes a `Port *` or a `Queue *`.
Our source gives all eleven an `ISASerialPort *self` first parameter; that parameter is pure
decompiler residue in every case. `_allocateRingBuffer` additionally has a second parameter in our
source that does not exist in the reference, and `_validateRingBufferSize`'s second parameter is a
`Queue *` rather than the object.

For completeness, the same is true of the four timeout handlers and the two interrupt handlers,
which are `static` in both trees: `_frameTOHandler`, `_delayTOHandler`, `_heartBeatTOHandler` and
`_dataLatTOHandler` are each `void (Port *)`, and `_FIFOIntHandler`/`_NonFIFOIntHandler` are
`void (void *identity, void *state, Port *port)`. `_executeEvent` is
`IOReturn (Port *, unsigned int eventType, unsigned int eventData, unsigned int *state, unsigned int *changedBits)`.
`-[ISASerialPort getHandler:level:argument:forInterrupt:]` hands the `Port *` back as the interrupt
`argument` at 2817-2823, which is what makes the handlers' third parameter a `Port *`, and
`thread_call_allocate` is given `self+0x128` as each callout's parameter at 1551-1620, which is what
makes the timeout handlers' single parameter a `Port *`.

### The answer on `.c` versus `.m`

**All three extracted translation units can be `.c` files, and no message-send conflict exists.**

`objc_msgSend` and `objc_msgSendSuper` are called from exactly four places in the reference, all of
them methods in TU 1: `+[ISASerialPort probe:]`, `-[ISASerialPort initFromDeviceDescription:]`,
`-[ISASerialPort free]` and `-[ISASerialPort getCharValues:forParameter:count:]`. **None of the
eleven exported functions, and none of the other functions in TUs 2, 3 or 4, sends a message or
references any Objective-C construct.** They reach state through a `Port *` or `Queue *` parameter
and plain C struct member access, so they never need to parse `@interface`.

That resolves the constraint cleanly. `__OBJC,__module_info` is 32 bytes / 2 modules in the
reference and **already exactly matching in our build**; making TUs 2-4 `.c` files keeps it that
way, whereas `.m` files would add module entries and break a section that currently matches.

The one thing Task 3 must actually change to make this work is the `_flowMachine` problem the plan
anticipated: our `_flowMachine` dereferences `self->currentState`, which a `.c` file cannot parse.
The fix is not a file-type change but the layout change in section 4.1 — `_flowMachine` becomes
`unsigned int _flowMachine(Port *port)` reading `port->State`, which is ordinary C. The same
applies to `_watchState` and to all nine others. **No human decision is required here.**

## 6. Apple's own defects — reproduce these, do not fix them

Four places where the reference does something that looks wrong and demonstrably is. A
reconstruction that "corrects" them will not match. Each is recorded with its address so a later
reader can confirm it rather than trusting this note.

1. **`_identifyChip` rung 7 reads MCR without writing it first.** At 19328 the default arm reads
   `inb(Base+4) & 0x80` to distinguish a 16550 from a 16C1550, but no `outb(Base+4, 0x80)` precedes
   it on that path — every instruction from 19172 to 19328 was checked and MCR is never written.
   The rung-5 path (19076) does write it first. So the 16550-vs-16C1550 decision reads whatever the
   MCR happened to hold.
2. **`_executeEvent` case 0x1B writes `RX.HighWater` while operating on TX.** At 12740 the store is
   `mov [edi+20h], data` — `RX.HighWater` — and everything after it clamps and recomputes `TX`. The
   encoding `894720` is byte-identical to the correct RX case at 12080, which is what makes it look
   like a copy-paste slip in Apple's source.
3. **`-[ISASerialPort executeEvent:data:]` case 0x0B validates the TX buffer size against the RX
   queue.** At 7024 it pushes `edi+140h` (`&Port->RX`) to `_validateRingBufferSize` while storing
   the result into `[edi+178h]` (`TX.Size`), so the TX buffer size falls back to
   **`RX.DefaultSize`**. The RX case at 6921 is correct.
4. **`-[ISASerialPort requestEvent:data:]` case 0x27 subtracts the TX count from the RX size.** At
   7932 it computes `[0x140] - [0x17C]` = `RX.Size - TX.Count`; it should be `[0x144]`
   (`RX.Count`). Our source already reproduces this at line 5030.

## 7. Per-function port-access inventory

A cheap, checkable target for Tasks 3-6. `outb`/`inb` counts, reference against ours. Register
offsets from `Base`: 0 RBR/THR/DLL, 1 IER/DLM, 2 IIR(read)/FCR(write), 3 LCR, 4 MCR, 5 LSR, 6 MSR,
7 SCR.

| Function | ref out | ref in | ours out | ours in | |
|---|---|---|---|---|---|
| `_identifyChip` | 18 | 10 | 18 | 10 | matches |
| `_initChip` | 3 | 0 | 3 | 0 | matches |
| `_programChip` | 5 | 0 | **7** | 0 | 2 extra (Finding 20) |
| `_activatePort` | 5 | 0 | 5 | 0 | matches |
| `_deactivatePort` | 3 | 0 | 3 | 0 | matches |
| `_dataLatTOHandler` | 1 | 0 | 1 | 0 | matches |
| `_executeEvent` | 4 | 0 | **1** | 0 | 3 missing (Finding 29) |
| `_FIFOIntHandler` | 4 | 4 | **5** | 4 | 1 extra (Finding 15) |
| `_NonFIFOIntHandler` | 3 | 5 | **4** | 5 | 1 extra (Finding 15) |
| `_TX_enqueueEvent` | 1 | 0 | 1 | 0 | matches |
| `_RX_dequeueEvent` | 1 | 0 | 1 | 0 | matches |
| `_RX_dequeueData` | 1 | 0 | 1 | 0 | matches |
| `acquire:` | 3 | 1 | 3 | 1 | matches |
| `release` | 3 | 0 | 3 | 0 | matches |
| `setState:mask:` | 1 | 0 | 1 | 0 | matches |
| `executeEvent:data:` | 2 | 0 | 2 | 0 | matches |
| `enqueueData:...` | 1 | 0 | 1 | 0 | matches |
| all others | 0 | 0 | 0 | 0 | matches |
| **total** | **59** | **20** | **60** | **20** | |

## Findings

### Linkage, tables and global structure

**Finding 1 — eleven symbols must be external, and all of ours are static.**
`ISASerialPort.m:147, 176, 455, 525, 601, 733, 769, 1379, 1452, 1715, 1859, 23584`-equivalents.
The reference's `__TEXT,__text` has exactly 11 `external` symbols: `_identifyChip`, `_initChip`,
`_programChip`, `_TX_enqueueEvent`, `_RX_dequeueEvent`, `_RX_dequeueData`,
`_validateRingBufferSize`, `_freeRingBuffer`, `_allocateRingBuffer`, `_flowMachine`, `_watchState`.
Every one is `static` in our single file. Those eleven are exactly TUs 2-4's functions and are what
an `ISASerialPortInternal.h` must declare. `parity_check.py` cannot see this; verify against the
rebuilt nlist.

**Finding 2 — `_Chip` does not exist in our source; `chipCapTable` is not it.**
`ISASerialPort.m:88-105`. Our `ChipCapabilities` struct is `{maxBaudRate, fifoSize, reserved[3]}`,
which is 20 bytes by accident of the 3-dword padding, so the *stride* matches. Nothing else does:

| idx | ref MaxBaud | our maxBaudRate | ref FIFO | our fifoSize |
|---|---|---|---|---|
| 0 | 0 | 9600 | 0 | 0 |
| 1 | 38400 | 9600 | 0 | 0 |
| 2 | 76800 | 19200 | 0 | 0 |
| 3 | 76800 | 38400 | 0 | 0 |
| 4 | 76800 | 38400 | 0 | 0 |
| 5 | 230400 | 115200 | 16 | 16 |
| 6 | 230400 | 230400 | 16 | **32** |
| 7 | 921600 | 460800 | 32 | **64** |
| 8 | 230400 | 921600 | 4 | **128** |

Every `MaxBaud` is wrong, and ours is in bps where the reference is in half-bits/s. `FIFOsize` is
wrong for indices 6, 7 and 8; `_FIFOIntHandler` consumes it directly at 13296, 14519 and 14637, so
`fifoRemaining` (our lines 2880, 2938) is wrong for those chips. The three pointer fields
(`IntHandler` +8, `ShortName` +12, `LongName` +16) are absent from our struct entirely, and all
three are load-bearing: `+8` drives the interrupt dispatch, `+12` is what
`initFromDeviceDescription:` `strcmp`s the `"Chip Type"` key against (1267), and `+16` is printed in
the banner (2515). The table must also be **external and non-`const`** and live in `__DATA,__data`.

**Finding 3 — `_msr_state_lut` is the identity table and is wrong.**
`ISASerialPort.m:110-113`. Must be `00 01 08 09 04 05 0C 0D 02 03 0A 0B 06 07 0E 0F` (section 4.3).
Consumed at our lines 2328, 2840 and 4160, where the surrounding expression
`(newState & 0xFFFFFE1F) | (lut[msr >> 4] << 5)` is correct. With the identity table DSR and DCD are
transposed in every modem-status report, so CTS/DCD/DSR/RI state changes reach the port server on
the wrong bits.

**Finding 4 — our 30 `IODelay(1)` calls are a mistranscription of `outb`'s internal counter, and
the reference has no delays at all.**
`ISASerialPort.m:608, 612, 621, 630, 634, 643, 652, 659, 666, 669, 677, 680, 697, 699, 701, 703,
707, 717` (`_identifyChip`), `748, 752, 756` (`_initChip`), `868, 874, 876, 885, 911, 936, 948`
(`_programChip`), `1621` (`_RX_dequeueEvent`), `1819` (`_TX_enqueueEvent`).
Neither `_IODelay` nor `_IOSleep` appears anywhere in the reference — not in the import list, not as
a string, and `_identifyChip` contains **zero `call` instructions**. What our source transcribed as
a delay is the `lock incl` that `ioPorts.h`'s inline `outb` emits after the `out` (section 4.4). The
correspondence is exact: in every function that has any `IODelay`, the `IODelay` count equals the
`outb` count — 18/18, 3/3, 7/7, 1/1, 1/1. All 30 must be deleted; calling `outb()` produces the
`lock incl` automatically. `IODelay` is microseconds and `IOSleep` milliseconds
(`src/driverkit-3/driverkit/generalFuncs.h:89,94`), so these are also 30 spurious 1 µs busy-waits.

**Finding 5 — the `IOEnterCriticalSection()`/`IOExitCriticalSection()` pairs are the same
mistranscription.** `ISASerialPort.m:2318-2320, 2399-2401, 2474-2476, 2834-2835, 2933-2934,
3004-3005, 3085-3086, 1987-1989`. Same cause as Finding 4, different placeholder. The reference
makes no such calls anywhere; they are not in its import list. `ISASerialPort.m:1987-1989` is the
worst instance — an empty acquire/release pair on a path reachable from interrupt context.

**Finding 6 — `chipTypeNames[]` is an invention and must be deleted.**
`ISASerialPort.m:76-86`. Nine `char *` = the 36 bytes our build puts in `__DATA,__data`. The
reference has no standalone name array; the names are `_Chip`'s `ShortName`/`LongName` fields. Our
name set is also different — `{Auto, 8250, 16450, 16550, 16550?, 16550A, 16650, 16750, 16950}`
against the reference's `ShortName` set `{Auto, 8250, 16450, 16450, 16450, 16550, 16550, 16650,
82510}` — so a `"Chip Type" = "82510"` Instance-table entry is unmatchable in our tree and
`"16550"` selects index 3 instead of 5.

**Finding 7 — our `CHIP_*` enumeration is not the reference's `Type` index.**
`ISASerialPort.h:73-82`. Ours is `{UNKNOWN 0, 8250 1, 16450 2, 16550 3, UNKNOWN_FIFO 4, 16550A 5,
16650 6, 16750 7, 16950 8}`. The reference's indices are the `_Chip` rows in section 4.2: index 3 is
`16C1450`, index 4 is `16550 with defective FIFO`, index 7 is `ST16C650` and index 8 is `82510`.
`CHIP_16750` and `CHIP_16950` have no counterpart at all; the reference does not support those
parts. Every comparison against a `CHIP_*` name is therefore suspect — see Findings 19 and 22.

**Finding 8 — `State` is one 32-bit field and our header splits it into three ivars.**
`ISASerialPort.h:156-158` declares `unsigned char flags` (`0xd`), `unsigned int currentState`
(`0xc`) and `unsigned char statusFlags` (`0xf`). Those are bytes 1, 0-3 and 3 of the single
`State L` field at `Port+12`. Consequences that recur throughout the findings below: the reference's
`test byte ptr [x+0Fh], 40h` means `State & 0x40000000`, `test byte ptr [x+0Fh], 10h` means
`State & 0x10000000`, `test byte ptr [x+0Dh], 8` means `State & 0x00000800`, and
`cmp dword ptr [x+0Ch], 0 / jl` means `State & 0x80000000`. Anywhere our source says
`statusFlags & 0x40` it means `State & 0x40000000`; anywhere it says `flags & 0x08` it means
`State & 0x800`.

**Finding 9 — the two high `State` gates are distinct and both are used.**
`State & 0x80000000` ("acquired") gates `acquire:` (4559), `release` (5468), `setState:mask:` (6068),
`executeEvent:data:` (6508), `_executeEvent` (10384) and `_heartBeatTOHandler` (10223).
`State & 0x40000000` ("active") gates `_activatePort` (3200 sets it), `_deactivatePort` (4165),
`_flowMachine` (23427), `enqueueEvent:` (8122), `dequeueEvent:` (8310), `enqueueData:` (8415) and
`dequeueData:` (9189). Our header names only the second (`STATE_ACTIVE 0x40000000`,
`ISASerialPort.h:92`) and has no name for the first; our `_heartBeatTOHandler` (line 2050) uses
`STATE_ACTIVE` where the reference tests the sign bit. Bit 12 (`0x1000`) is private: `getState`
masks it out (6292) and `setState:mask:` rejects any attempt to set it (6027).

**Finding 10 — `STATE_RX_ENABLED` is `0x00400000`, not `0x00080000`.**
`ISASerialPort.h:94`, used at `ISASerialPort.m:2122, 2151, 2640`. Reference:
`test byte ptr [ebp+var_C+2], 40h` at `_FIFOIntHandler` 13237 and `_NonFIFOIntHandler` 16340 and
16449 — byte 2 of the state word, bit `0x40`, i.e. `0x00400000`. With the wrong bit the entire RX
path in both interrupt handlers is gated on an unrelated flag.

**Finding 11 — `FlowControl` is 32 bits and our `flowControlMode` is an `unsigned char`.**
`ISASerialPort.h:195`. `Port+224` is `FlowControl L`. Four places gate a state-change event on
`FlowControl & (changedBits << 16)`, which cannot work against a byte: `_RX_dequeueEvent`
(reference 22218, our line 1630) and `_RX_dequeueData` (reference 22895, our line 1998) are
**dead code** as written, and `enqueueData:` (our line 4684) and `_TX_enqueueEvent` (our line 1829)
only work because they type-pun around the declaration with `memcpy` and an explicit cast. Our
`_RX_dequeueData` also has the shift **backwards** — `changedBits >> 16` at line 1998 where the
reference shifts left at 22895.

**Finding 12 — our TX queue field names are shifted one slot from Apple's.**
`ISASerialPort.h:176-185`. The offsets our code uses are right; the names mislead.

| ours | offset | Apple |
|---|---|---|
| `txQueueLowWater` | `0x58` | `TX.HighWater` |
| `txQueueMedWater` | `0x5c` | `TX.LowWater` |
| `txQueueHighWater` | `0x60` | `TX.Enqueue` |
| `txQueueTarget` | `0x64` | `TX.Dequeue` |

Our **RX** names for `0x20`/`0x24` (`HighWater`/`LowWater`) are correct, so the header contradicts
itself between the two queues. This is the direct cause of the inverted comparisons in Findings 16
and 17: a reader checking `txQueueUsed < txQueueMedWater` against the reference's
`cmp TX.LowWater, TX.Count` will believe it matches. Rename before touching the logic.

**Finding 13 — `defaultRingBufferSize` must be per-queue.**
`ISASerialPort.h:187`, used at `ISASerialPort.m:153`. The reference has `RX.DefaultSize` at
`Port+68` and `TX.DefaultSize` at `Port+124`, both seeded to `0x4B0` (1200) by
`initFromDeviceDescription:` (739, 669) and then overwritten independently from the
`"RX Buffer Size"` and `"TX Buffer Size"` keys. `_validateRingBufferSize` reads it from its
`Queue *` argument at `Queue+44` (22945). Ours has one object-wide value.

**Finding 14 — the ring cell is 2 bytes and this is load-bearing.** Confirmed at
`_allocateRingBuffer` (`AllocSize = Size*2 + 2`, 23092; `End = Base + Size*2`, 23138-23147),
`nextEvent` (`Size*2` stride, 6446) and every enqueue/dequeue step (`mov word ptr`, `add ptr, 2`).
Our source models this correctly everywhere with `unsigned short *` walks and `>= end` wraps. Noted
so nobody "simplifies" it.

### Interrupt handlers and dispatch

**Finding 15 — the IIR read must be short-circuited, and in our source it is not.**
`ISASerialPort.m:2486` (`_NonFIFOIntHandler`) and `3097` (`_FIFOIntHandler`).
Reference `_FIFOIntHandler` reaches its IIR read at 15716 only after three tests fail
(`var_20 == 0 && var_18 == 0 && edi == 0`, at 15688/15698/15708); `_NonFIFOIntHandler` reaches its
at 18189 only when `var_1C == 0` (18179). Ours reads IIR unconditionally at the top of the loop
condition. **Reading IIR clears a pending THRE interrupt on a 16550**, so the extra read can
silently drop a transmit interrupt. This is also the one extra `out`/`in` each handler shows in the
section 7 inventory.

**Finding 16 — both TX watermark comparisons are inverted in both handlers.**
`ISASerialPort.m:3119-3120` (`_FIFOIntHandler`) and `2508-2509` (`_NonFIFOIntHandler`).
Reference `_FIFOIntHandler` 15821 is `cmp TX.LowWater, TX.Count / jb`, so `LowWater >= Count` takes
the empty/below-low arm; ours takes the *high-water* arm on that condition. Reference 15875 is
`cmp TX.HighWater, TX.Count / jnb`, so the `Enqueue = Size-3` sub-arm needs `HighWater < Count`.
Same pair at `_NonFIFOIntHandler` 18294 and 18347. Read Finding 12 first — the names make these
look correct.

**Finding 17 — two TX watermark state constants are wrong and one has no name.**
`ISASerialPort.m:3124, 3127` and `2513, 2516`; `ISASerialPort.h:102-107`.
The reference's complete TX set, inside mask `0x07800000`, is `0x06000000` (empty), `0x02000000`
(below low), `0` (mid), `0x01800000` (`Count > Size-3`) and `0x01000000` (above high) — at
`_FIFOIntHandler` 15846, 15862, 15944, 15906, 15922 and `_NonFIFOIntHandler` 18378, 18394. Ours
emits `TX_STATE_ABOVE_HIGH` (`0x01000000`) where the reference emits `0x01800000`, and `0` where it
emits `0x01000000`. `0x01800000` — the TX analogue of `RX_STATE_CRITICAL` — has no name in our
header, and `TX_STATE_BELOW_LOW` (`0x04000000`, `ISASerialPort.h:104`) is **never produced by the
reference at all**. The same wrong pair appears in `_TX_enqueueEvent` (our 1775, 1778, reference
21210, 21226) and in `enqueueData:` (our 4645-4646 emits `0x04000000` where reference 8714 emits
`0x02000000`).

**Finding 18 — the timeout handlers must dispatch through `_Chip`, and two of ours are commented
out.** `ISASerialPort.m:229-234` (`_frameTOHandler`), `2055-2061` (`_heartBeatTOHandler`),
`258-262` (`_delayTOHandler`).
Reference `_frameTOHandler` (10110-10131), `_delayTOHandler` (10170-10191) and
`_heartBeatTOHandler` (10247-10268) each make an **unconditional** indirect call
`_Chip[port->Type].IntHandler(0, 0, port)`. There is no chip test. Ours replaces the table with an
`if (self->hasFIFO)` branch on an invented ivar, and in `_frameTOHandler` the FIFO arm is
**commented out entirely** (line 231) while in `_heartBeatTOHandler` **both** arms are commented out
(2057, 2060). Since `_Chip[5..7].IntHandler == _FIFOIntHandler`, on any 16550AF/16C1550/ST16C650 the
frame timeout is the mechanism that resumes a stalled transmitter — both handlers arm it
(`_FIFOIntHandler` 15766-15801, `_NonFIFOIntHandler` 18239-18274) precisely on the paths where TX
could not proceed. As written, a FIFO port that arms the frame timer is never re-entered and TX
stalls permanently. `_delayTOHandler` is the only one of the three still wired up.

**Finding 19 — `getHandler:level:argument:forInterrupt:` must select by `Type`, not by `hasFIFO`.**
`ISASerialPort.m:5333-5337`. Reference 2776-2838, 22 instructions, no calls:

```
*(IOInterruptHandler *)handler = _Chip[self->Port.Type].IntHandler;   /* 2793-2809 */
*level                         = 3;                                    /* 2811 */
*argument                      = self->port;                           /* 2817-2823 */
/* forInterrupt ignored */
return 1;
```

Ours branches on `hasFIFO`, which is not one of the reference's two ivars. FIFO for
`Type` in {5,6,7}, non-FIFO for {0,1,2,3,4,8}. The `*argument = self->port` store at our line 5344
is **already correct** and is the fact that pins the handlers' third parameter to a `Port *`. The
method returns a literal `1` — a BOOL — where our header types it `IOReturn`
(`ISASerialPort.h:314`).

**Finding 20 — `_FIFOIntHandler`'s delegation condition matches; do not change it.**
Reference 13081-13104: `if (!(port->FCRimage & 1)) { _NonFIFOIntHandler(identity, state, port); return; }`.
Our line 2600 does exactly this. Recorded so it is not "fixed".

**Finding 21 — the LSR error decode ladder.** Identical in both handlers (`_FIFOIntHandler`
13306-13346, `_NonFIFOIntHandler` 16465-16506). `edx = LSR & 0x1C`:

| `LSR & 0x1C` | RX cell written | notes |
|---|---|---|
| `0x00` | `event \| (data << 8)`, `event = 0x59` if `SWspecial[data>>5] & (1 << (data & 31))` else `0x55` | normal data |
| `0x04` | if `RX_Parity == 6` then `data &= RBRmask` and fall into the no-error path, else `(data << 8) \| 0x61` | parity |
| `0x08`, `0x0C` | `(data << 8) \| 0x5D` | framing |
| `0x10/0x14/0x18/0x1C` | `0x00FC` | break |

In every case the byte OR'd in is the **post-`RBRmask` eventData**, not the raw RBR read
(13361, 13556, 13624 all read the same stack slot). Our lines 2670, 2712, 2726 use the raw
`dataByte`, which differs only on the `RX_Parity == 6` masked path. When the queue is full
(`RX.Size <= RX.Count`) all four paths converge on `RX.OverRun = 1` (13684).

**Finding 22 — the FIFO overrun countdown uses `_Chip[Type].FIFOsize`.**
Reference 13273-13303 and 13728-13800: `if ((LSR & 2) && var_18 == 0) var_18 = _Chip[Type].FIFOsize;`
then `if (var_18 && --var_18 == 0)` enqueue `0x0068`. Our lines 2652, 2880, 2938 read
`chipCapTable[chipType].fifoSize`, whose values are wrong for indices 6-8 (Finding 2) over an index
space that is not the reference's (Finding 7). `_NonFIFOIntHandler` has no countdown at all — it
handles overrun at the **top** of the loop before RBR is read (16332), gated on
`(LSR & 2) && (State & 0x400000)`.

**Finding 23 — `_NonFIFOIntHandler`'s structure differs from `_FIFOIntHandler`'s in five ways, and
ours already gets these right.** LSR is read once before the loop (16277) and re-read at the bottom
(18164), never at the top; there is no RX drain loop, one byte per outer iteration; `Stats.rxInts`
and `Stats.txInts` are incremented once before the loop (16298-16326); MSR handling is gated on
`msr & 0x0F` and increments `Stats.mdmInts` at `Port+292` (17309-17320), neither of which
`_FIFOIntHandler` does; and `port->JustDoneInterrupt` is set by `_FIFOIntHandler` only (13159).
Our lines 2109-2115, 2122-2136, 2325-2326, 2337 and 2483 reproduce all five. Recorded so they are
not "unified" with the FIFO handler.

**Finding 24 — `txQueueStart` written as `txQueueRead` in the TX ring wrap.**
`ISASerialPort.m:2357`. The wrap reads
`if ((void *)readPtr >= self->txQueueEnd) { readPtr = (unsigned short *)self->txQueueRead; }` —
assigning the read pointer to itself, so the ring never wraps. Reference 17598-17606:
`cmp TX.End, TX.Output / ja skip / mov TX.Output, TX.Base`. Every other wrap in our file uses the
start pointer; this one line does not. A plain typo with a hard consequence.

**Finding 25 — the flow-control adjustments are exclusive `if / else if` chains, not independent
`if`s.** `ISASerialPort.m:2265, 2268, 2276` and `2290, 2293, 2301` (`_NonFIFOIntHandler`);
`2783, 2786, 2794` and `2807, 2810, 2818` (`_FIFOIntHandler`); `1915-1923` and `1945-1953`
(`_RX_dequeueData`).
Reference low-water arm: `test FlowControl, 4 / jz` → `or al, 4` then **jump to the merge**;
else `test FlowControl, 0x10 / jz` → `or al, 0x10` plus the `RXOstate` machine; else
`test FlowControl, 2 / jz` → `or al, 2`. (`_FIFOIntHandler` 13895/13912/13976 and
14055/14068/14136; `_NonFIFOIntHandler` 16971/16988/17052 and 17131/17144/17212;
`_RX_dequeueData` 22500/22520/22584.) With `FlowControl == 0x14` the reference sets only `0x04`;
ours sets `0x04` *and* `0x10` and additionally runs the `RXOstate` machine, which the reference
reaches only when bit 2 is clear.

**Finding 26 — the RX watermark's preserved bits come from `port->State`, not the local copy.**
`ISASerialPort.m:2252` and `2771`. Reference `_FIFOIntHandler` 13837-13840 is
`mov eax, [port+0Ch] / and eax, 17Eh` — the **struct field**, read after
`and [ebp+var_C], 0FFF0FFE9h` (13830) has already modified the local, which the XON/XOFF handling
at 13434/13472/13497 may also have changed. Same at `_NonFIFOIntHandler` 16913. Ours reads the
local.

**Finding 27 — `_RX_enqueueLongEvent` is inlined in both handlers, not called.**
`ISASerialPort.m:2563, 3174`. Reference `_FIFOIntHandler` 16096-16192 and `_NonFIFOIntHandler`
18568-18664 write the three cells (`0x0053`, `delta & 0xFFFF`, `delta >> 16`) inline, each with wrap
and `RX.Count++`. Behaviour is identical; the instruction stream is not, and this accounts for a
visible part of the `__text` size gap.

**Finding 28 — `timerNeeded` is set on the wrong paths in `_FIFOIntHandler`.**
`ISASerialPort.m:3069`. Reference sets it at exactly two places: 14969 (`edi == 0` after the
burst-eligibility tests) and 15344 (TX head is a non-data event **and** `!(LSR & 0x40)`). Ours sets
it when the head is `'U'` but flow control blocks TX — where the reference goes to 15328
(`xor edi, edi`) and leaves the flag alone — and never sets it for the `edi == 0` case.

**Finding 29 — `fifoRemaining` is zeroed on the drain-loop break, killing the outer re-iteration.**
`ISASerialPort.m:2956, 3074`. Reference 15017-15020: when the next TX head is not `0x55` it jumps to
15688 with `edi` still non-zero, so the test at 15708 re-enters the whole loop. Ours breaks out and
then sets `fifoRemaining = 0`, terminating the outer loop.

### `_executeEvent` and the event interface

**Finding 30 — `_executeEvent` returns `IOReturn` and ours returns `void`; the open guard is
missing.** `ISASerialPort.m:3201`. Reference 10384-10395:

```
cmp dword ptr [port+0Ch], 0
jl  proceed
mov eax, 0FFFFFD33h      ; -717 = IO_R_NOT_OPEN
ret
```

so `!(State & 0x80000000)` returns `IO_R_NOT_OPEN`. The default arm returns
`-706 = IO_R_INVALID_ARG` (13040); event 0x05 returns `_activatePort`'s result (10926); everything
else returns 0. `-[ISASerialPort executeEvent:data:]` captures it at 7141 and returns it at 7325.
Ours is `void`, has no open guard, and at line 4904 **overwrites the result with 0** — so the
port's entire error-reporting path for every non-generic event is lost.

**Finding 31 — `eventType` is 32 bits, not a byte.** `ISASerialPort.m:3201, 4903, 5044`.
Reference `_executeEvent` loads it with a dword `mov edx, [ebp+arg_4]` (10368) and compares the full
register (`cmp edx, 0EDh`); `-[ISASerialPort executeEvent:data:]` passes the raw `event:` dword
(6484) and `-[ISASerialPort requestEvent:data:]` compares unmasked (7352-7372). Ours declares
`unsigned char eventType`, truncates at line 4903 and does `switch (event & 0xFF)` at 5044, so
`0x105` aliases to `0x05` instead of returning `IO_R_INVALID_ARG`.

**Finding 32 — `*statePtr` and `*changedBitsPtr` are read-modify-written, and `changedBits` is a
mask not a xor-diff.** `ISASerialPort.m:3241, 3257, 3370, 3394, 3470, 3475, 3478`.
Reference uses `and`/`or` throughout — `or [esi], edx` (10821), `and [ebx], ~edx` (10827),
`or [ebx], edx & eax` (10836), `or dword [esi], 0F0016h` (11601),
`or dword [esi], 7800000h` (11843), `and dword [ecx], 0FFF0FFE9h` (11262),
`and dword [ecx], 0F87FFFFFh` (11707) — so `changedBits` accumulates a mask of *authoritative bits*
and `state` accumulates the values for them. The caller then computes
`newState = (port->State & ~changedBits) | (changedBits & state)` (7156-7172) and only then writes
`port->State`. Ours **assigns** both out-parameters (3475, 3478), destroying the values the two
interrupt handlers pass in, computes `changedBits` as `tempValue ^ oldState`, and additionally
writes `self->currentState` at line 3470 — a field the reference's `_executeEvent` never touches.

**Finding 33 — events 0xE9 and 0xED are swapped.** `ISASerialPort.m:3421, 3427`.
Reference: `cmp EDh / jz 10704` → `mov [port+0BDh], al` = **`XONchar`**;
`cmp E9h / jz 10716` → `mov [port+0BEh], al` = **`XOFFchar`**. So `0xED` sets XON and `0xE9` sets
XOFF. Ours has `case 0xE9: xonChar` and `case 0xED: xoffChar`. `requestEvent:data:` reads them back
the same way round as the reference writes them (0xED → `XONchar` at 8016, 0xE9 → `XOFFchar` at
8028), so the two halves of our source are also inconsistent with each other.

**Finding 34 — events 0x37, 0x3F and 0xF7 are missing.** `ISASerialPort.m:3463`.
Reference 11636: each returns `0` if `data == 0` and `-706 = IO_R_INVALID_ARG` otherwise. Ours has
no cases for them, so they fall into `default` and are silently ignored.
`requestEvent:data:` answers all three with `*data = 0` (8008).

**Finding 35 — the FCR FIFO-reset writes on the flush events are missing.**
`ISASerialPort.m:3262-3285`. Reference event 0x2F (RX flush) does
`if (Type > 4) outb(Base + 2, FCRimage | 2)` at 11251, and event 0x28 (TX flush) does
`if (Type > 4) outb(Base + 2, FCRimage | 4)` at 11696. Our cases perform **no I/O at all**, so a
flush leaves stale bytes in the hardware FIFO. These are three of the four `out`s our
`_executeEvent` is missing in the section 7 inventory (the fourth is Finding 36).

**Finding 36 — event 0x53 is unrecognisable, and the MCR write is lost.**
`ISASerialPort.m:3391-3395`. Reference 10800-10911:

```
mask = ((data & 0x160000) >> 16) & ~FlowControl;
*changedBits |= mask;
*state = (*state & ~mask) | (mask & data);
if (mask & 0x10) RXOstate = (data & 0x10) ? 2 : 1;
/* MCR rebuilt from the UPDATED *state, then: */
outb(Base + 4, mcr);                                  /* 10902 */
```

Ours sets `newState = eventData; changedBits = newState ^ oldState;` and performs no I/O. Losing the
MCR write means a manual DTR/RTS change never reaches the chip.

**Finding 37 — event 0x4B loses the suspend bit, the clamp and the microsecond scaling.**
`ISASerialPort.m:3374-3384`. Reference 11948-12077: return 0 if `data == 0`; clamp
`data > 0x418937` to `0x418937`; **`*state |= 0x1000`**; `ns = data * 1000`;
`tv_sec = ns / 1000000000`, `tv_nsec = ns % 1000000000`;
`thread_call_enter_delayed(DelayTOEntry, deadline_from_interval(tv_sec, tv_nsec))`. Ours cancels
`delayTimeoutCallout` first (the reference does not), omits the clamp, omits the `0x1000` bit — which
both interrupt handlers test (`_FIFOIntHandler` 14408, `_NonFIFOIntHandler` 17474) and
`_delayTOHandler` clears (10163) — and omits the `* 1000` scaling. The argument is in
**microseconds**.

**Finding 38 — event 0x4F stores a `tvalspec_t`, not two 16-bit halves.**
`ISASerialPort.m:3386-3388`. Reference 10948-11039: `ns = data * 1000`;
`DataLatInterval.tv_sec = ns / 1e9` (`Port+256`), `.tv_nsec = ns % 1e9` (`Port+260`). Ours splits
`eventData` into two 16-bit halves.

**Finding 39 — the watermark events 0x13/0x17/0x1B/0x1F omit the clamps, the floors and the
recompute.** `ISASerialPort.m:3230-3260`. Reference: 0x17 (12356) sets `RX.LowWater = data`, clamps
it to `RX.HighWater - 3`, applies a floor of 3, does `*state &= 0xFFF0FFE9`, runs the inlined RX
watermark recompute and ORs `0xF0016` into `*changedBits`. 0x1F (12080) sets `RX.HighWater = data`,
clamps to `RX.Size - 3`, floor 6, then clamps `RX.LowWater` to `RX.HighWater - 3`. 0x13 (12860) and
0x1B (12740) are the TX equivalents with mask `0xF87FFFFF` and `0x7800000`. Ours only range-checks
against the queue capacity and stores the field, and calls `_flowMachine` (3240, 3256) where the
reference inlines the recompute. See also section 6 item 2 — 0x1B's write target is Apple's own bug.

**Finding 40 — event 0x33 does not belong to `_executeEvent`'s arithmetic.**
`ISASerialPort.m:3287-3310`. Reference 11100-11139: `if (data <= 0x63) return -706;`
`if (data > _Chip[Type].MaxBaud) return -706;` `BaudRate = data;` then `_programChip(port)` and
return 0. That is all. Ours computes a divisor and a character time inline, including
`__udivdi3`/`__umoddi3` calls at 3308-3309 with a different quantity
(`tempValue * 1000000000 / eventData`). The divisor and frame interval are `_programChip`'s job.

**Finding 41 — events 0x3B, 0x43, 0xF3, 0xE5 and 0xF9 mutate register images they should not, and
gate a write they should not gate.** `ISASerialPort.m:3317, 3329-3347, 3417, 3438-3440, 3458`.
Reference: 0x3B (11140) validates `(data - 10) <= 6 && !(data & 1)` and stores `CharLength`;
0x43 (11064) validates `data != 0 && data <= 5`, stores `TX_Parity` and **also clears `RX_Parity`**;
0xF3 (11168) validates `(data - 2) <= 2` and stores `StopBits`; 0xE5 (11040) sets
`MinLatency = (data != 0)` and **zeroes `DLRimage`**. All four then call `_programChip(port)`
unconditionally. 0xF9 (11856) does `*state &= 0xFFFFF7FF`, sets or clears `LCRimage` bit `0x40`,
writes `outb(Base + 3, LCRimage)` **unconditionally** (11919), then `*state |= bit` and
`*changedBits |= 0x800`. Ours mutates `lcrValue`/`divisor` inline, calls `_initChip` for 0xE5, gates
the reprogram and the 0xF9 `outb` on `oldState & STATE_ACTIVE`, and omits the `*state`/`*changedBits`
updates.

**Finding 42 — events 0x55 and 0x59 are correct; do not change them.**
`ISASerialPort.m:3397-3411`. Reference 10768 and 10728 manipulate `SWspecial[data >> 5]` bit
`data & 31`; the reference's `rol 0xFFFFFFFE, n` is exactly `~(1 << n)`. Ours adds an
`eventData <= 0xFF` guard the reference lacks, which is harmless given the callers.

### Chip identification and programming (TU 2)

**Finding 43 — `_identifyChip`'s decision ladder, and the four places ours differs.**
`ISASerialPort.m:601-732`. Reference 18704-19387, 180 instructions, **zero calls**. `Base` is
re-read from `port->Base` before every one of the 28 accesses.

| rung | reference | outcome |
|---|---|---|
| 1 | `outb(Base+3, 0x80)`; `outb(Base+0, 0x5A)`; `inb(Base+0) != 0x5A` → **0**; `outb(Base+0, 0xA5)`; `inb(Base+0) != 0xA5` → **0** | DLL read/write |
| 2 | `outb(Base+3, 0x00)`; `outb(Base+7, 0x5A)`; `inb(Base+7) != 0x5A` → **1**; `outb(Base+7, 0xA5)`; `inb(Base+7) != 0xA5` → **1** | scratch register |
| 3 | `outb(Base+2, 0x07)`; `t = inb(Base+2) & 0xC0`; `outb(Base+2, 0x00)` | FIFO probe |
| | `t == 0x40` → **5** (18974 → 19369) | |
| | `t == 0x80` → **4** (18998 → 19160) | |
| | `t == 0x00` → rung 4 (18984 → 19012) | |
| | `t == 0xC0` (default) → rung 6 (18986/19004 → 19172) | |
| 4 | `outb(Base+2, 0x60)`; `u = inb(Base+2) & 0x60`; `outb(Base+2, 0x00)`; `u == 0x60` → **8** | 82510 |
| 5 | `outb(Base+4, 0x80)`; `v = inb(Base+4) & 0x80`; `outb(Base+4, 0x00)`; `v == 0x80` → **3** else → **2** | MCR bit 7 |
| 6 | `outb(Base+3, 0)`; `outb(Base+7, 0xDE)`; `outb(Base+3, 0x80)`; `outb(Base+7, 0xA9)`; `a = inb(Base+7)`; `outb(Base+3, 0)`; `b = inb(Base+7)`; `b == 0xDE && a == 0xA9` → **7** | ST16C650 banked scratchpad |
| 7 | `w = inb(Base+4) & 0x80`; `outb(Base+4, 0x00)`; `w == 0x80` → **6** else → **5** | 16550 vs 16C1550 |

The return value is an index into `_Chip[]`, stored straight into `port->Type` by
`initFromDeviceDescription:` at 1401-1406; 0 means "no UART" and the caller logs and fails.

Divergences: (a) our line 688-690 returns `CHIP_UNKNOWN_FIFO` = 4 where rung 3's `t == 0x40` arm
returns **5**; (b) our line 692 routes `t == 0x80` into the whole rung-6/7 ladder where the
reference returns **4** immediately; (c) our line 726 returns `CHIP_16550A` = 5 with no I/O for the
`t == 0xC0` case where the reference runs rungs 6 and 7 — so our `0x80` and `0xC0` arms are
effectively swapped; (d) 18 `IODelay(1)` calls with no counterpart (Finding 4). Rungs 1, 4 and 5
return values that match numerically (0, 1, 8, 3, 2) but our *names* for 3 and 8 contradict `_Chip`
(Finding 7). Rung 7's missing MCR write is Apple's, not ours — see section 6 item 1.
Our line 603 declares an unused `val3`.

**Finding 44 — `_initChip` is `void`, initialises seven fields, and ours adds three delays.**
`ISASerialPort.m:733-768`. Reference 19388-19535, 30 instructions:

```
CharLength = 16;  StopBits = 2;  TX_Parity = 1;  RX_Parity = 0;
BaudRate = 0x4B00 /* 19200 half-bits/s = 9600 bps */;
DLRimage = 0 /* 16-bit store */;  FCRimage = 0 /* 8-bit store */;
if (port->Type == 0) return;
outb(Base+3, 0);  outb(Base+1, 0);  outb(Base+4, 0);
_programChip(port);
```

It does **not** initialise `IERmask`, `LCRimage`, `RBRmask`, `MasterClock` or any queue field. Our
field order, all seven constants and the `Type == 0` guard (line 745) match. Divergences: the
`IOReturn` return type (line 762); our line 739 writes `self->flowControl`, whose header comment
places it at `0xa0` = 160, which is `RX_Parity` — the byte is right, the name is wrong, and the real
`FlowControl` is at `Port+224`; and the three `IODelay(1)` calls (Finding 4).

**Finding 45 — `_programChip`'s parity frame-bit adjustment is inverted.**
`ISASerialPort.m:855-859`. Reference 20009-20024: `halfBits = CharLength + StopBits + (TX_Parity == 1 ? 2 : 4)`
— **+2 when parity is none**, +4 otherwise. Ours has
`if (parity != PARITY_NONE) totalBits += 2; else totalBits += 4;`. This corrupts `nsPerChar`, and
therefore both `FrameInterval` and the FIFO trigger level derived from it.

**Finding 46 — `_programChip`'s baud clamp is an if/else, not two independent ifs, and ours adds a
bounds check.** `ISASerialPort.m:839-846`. Reference 19865-19940:

```
if (_Chip[Type].MaxBaud < BaudRate)  BaudRate = _Chip[Type].MaxBaud;
else if (BaudRate < 100)            BaudRate = 100;
```

The 100 floor is skipped whenever the MaxBaud clamp fired (19892 `jnb` → 19920). Ours makes the
floor an independent `if` and adds a `chipType < 9` guard the reference does not have. There is no
bounds check on `Type` anywhere in `_programChip`; the stride is `lea ecx,[edx+edx*4]; shl ecx,2`.

**Finding 47 — `_programChip`'s FIFO trigger loop can go negative and ours cannot, making one of
our branches dead.** `ISASerialPort.m:898, 921, 925`. Reference 20340-20377 (types 5/6) and
20476-20513 (type 7):

```
n = (10000000 - 3 * nsPerChar) / nsPerChar;          /* signed idiv */
while ((17 - n) * nsPerChar < 2000000) n--;          /* cmp 1E847Fh; jle */
```

The loop only ever decrements and **can drive `n` negative** — at 230400 half-bits/s, `nsPerChar`
is 86800, `n` starts at 112 and ends at −7. Ours appends `&& triggerLevel > 0` to the loop
condition, so `n` can never go negative, which makes our line 925
(`if (triggerLevel < 0 && baudRate < 19200)`) **dead code**. The reference's type-7 path at
20515-20541 is live and is proven so by the `test ecx,ecx / jge` at 20515.

**Finding 48 — `_programChip`'s FCR switch covers types 4, 5, 6 and 7 only, and ours includes 3.**
`ISASerialPort.m:880-886`. Reference 20243-20281 dispatches on `Type`: 4 → `FCRimage = 0` then
`outb(Base+2, 0)`; 5 or 6 → the trigger ladder `n <= 3 ? 0x01 : n <= 7 ? 0x41 : 0x81` (or `0x01` if
`MinLatency`), then `outb(Base+2, FCRimage)`; 7 → `MinLatency ? 0x00` (note: **0**, not 1) else
`n < 0 && BaudRate <= 0x4AFF ? 0` else `n <= 15 ? 0x01 : n <= 23 ? 0x41 : 0x81`, then
`outb(Base+2, FCRimage)`; **types 0, 1, 2, 3 and 8 → `FCRimage = 0` and no `outb` at all** (20628).
Ours lumps `CHIP_16550` (3) in with 4 and issues `outb(Base+2, 0)` for it. Ours also emits three
separate FCR writes where the reference shares one tail at 20614 — the two extra `out`s in
section 7.

**Finding 49 — `_programChip`'s early-out skips the FCR programming entirely.**
Reference 19981-19988: `if (port->DLRimage == DLR) goto write_LCR;` — jumping to 20638 and skipping
the frame-interval math, the DLL/DLM writes **and the whole FCR switch, including the
`FCRimage = 0` default**. Worth stating because it means `FCRimage` is not reset on a no-op
reprogram. Our source has no equivalent early-out.

**Finding 50 — `_programChip`'s remaining structure, for reference.** `MasterClock` is set once, by
`initFromDeviceDescription:` at 350, to **0x1C2000 = 1,843,200**. The divisor is
`DLR = (unsigned short)(MasterClock / (BaudRate << 3))` (19942-19974) — a 32-bit unsigned `div`. The
LCR image is built from `CharLength` (clamped to 10..16 then `&= 0xFE`; 10→`{LCR 0, RBRmask 0x1F}`,
12→`{1, 0x3F}`, 14→`{2, 0x7F}`, 16→`{3, 0xFF}`), `StopBits` (`<= 2` → 2, else `LCR |= 0x04` and
`StopBits = CharLength == 10 ? 3 : 4`), a 5-entry jump table on `TX_Parity - 1`
(1→nothing, 2→`|= 0x08`, 3→`|= 0x18`, 4→`|= 0x28`, 5→`|= 0x38`), and `State & 0x800` → `LCR |= 0x40`.
`FrameInterval.tv_sec`/`.tv_nsec` come from `__udivdi3`/`__umoddi3` of the sign-extended
`nsPerChar` by `1000000000` (20059-20116). The divisor writes are
`outb(Base+3, LCRimage | 0x80)`, `outb(Base+0, DLR & 0xFF)`, `outb(Base+1, DLR >> 8)` with DLAB held
set across both, and the final write is `outb(Base+3, LCRimage)` followed by
`port->LCRimage = LCRimage`. **`_programChip` never touches `IERmask`** — there is no IER image
construction in it at all. Ours does a plain 32-bit `/` and `%` where the reference uses the 64-bit
helpers (our lines 863-864), and returns `IOReturn` where the reference is `void`.

**Finding 51 — `RBRmask` is a data mask, not a FIFO size.** `ISASerialPort.h:151`,
`ISASerialPort.m:789, 793, 797, 801`. The values `0x1F/0x3F/0x7F/0xFF` match the reference
(19659/19675/19691/19707), but ours calls the field `rxFIFOMask` and comments it "31/63/127/255
bytes". `Port+177` is `RBRmask`, the received-character mask for 5/6/7/8 data bits.

**Finding 52 — `MinLatency` is not `forceFIFODisable`.** `ISASerialPort.h:153`,
`ISASerialPort.m:915-916`. The values match, but in the type-5/6 arm `MinLatency != 0` sets
`FCRimage = 0x01`, which **enables** the FIFO at a 1-byte trigger (20328). Our name inverts the
meaning. Only in the type-7 arm does it set `FCRimage = 0`.

### Ring buffers and queues (TU 3)

**Finding 53 — `_allocateRingBuffer` returns a BOOL, and ours returns 0 on success, so
`_activatePort` can never succeed.** `ISASerialPort.m:1379, 1412, 1444, 996, 1001.`
Reference 23068-23197 returns `1` on success (`mov eax, 1` at 23186) and `0` on failure
(`xor eax, eax` at 23113); both call sites test `test al, al` (3052, 3068). Ours returns
`0` on failure (line 1412) and `IO_R_SUCCESS` on success (line 1444) — and `IO_R_SUCCESS` **is 0**
(`return.h:38`). The call sites are `if (_allocateRingBuffer(...) == 0) return 0xFFFFFD42;`, so the
first one always fires and `_activatePort` always returns −702. **This is the highest-impact defect
in our tree: the port can never be opened.**

**Finding 54 — `_allocateRingBuffer` stores `AllocSize` and `AllocBase` at the same offset.**
`ISASerialPort.m:1404, 1408`. Reference writes `AllocSize` to `Queue+48` (23097) and `AllocBase` to
`Queue+52` (23106) — two distinct fields. Ours writes both through `allocStart` at `queueBase+0x30`,
and our own comment at line 1403 admits it ("temporarily, will be overwritten with pointer"). So
`AllocSize` is destroyed and `_freeRingBuffer` has nothing to work with. Our `Queue` has no slots at
`+44`, `+48` or `+52` at all — the header runs RX from `0x18` straight to `0x40` and TX ends at
`0x74` — so the 56-byte `Queue` cannot currently be represented.

**Finding 55 — `_allocateRingBuffer`'s watermark seed is one slot low in both source and
destination.** `ISASerialPort.m:1439`. Reference 23173-23176: `q->Enqueue (+16) = q->LowWater (+12)`.
Ours: `*(queueBase + 0x0c) = *(queueBase + 0x08)`, i.e. `LowWater = HighWater`, which also silently
overwrites `LowWater`. Line 1442's `Dequeue = 0` (`+0x14`) does match 23179.

**Finding 56 — `_freeRingBuffer` frees the wrong pointer with the wrong size.**
`ISASerialPort.m:191`. Reference 22989-22997: `IOFree(q->AllocBase, q->AllocSize)`. Ours:
`IOFree(*start /* Base */, *end - *start /* = Size*2 */)`. When `AllocBase` was odd,
`_allocateRingBuffer` set `Base = AllocBase + 1` (23120-23129), so we hand the allocator a pointer
**one byte inside** its own block; and even when it was even, the size is `Size*2` where the
allocation was `Size*2 + 2`. `IOMalloc`/`IOFree` are size-matched, so a `0x102`-byte allocation
freed as `0x100` lands in the wrong bucket. Heap corruption on every port deactivate.

**Finding 57 — `_freeRingBuffer` zeroes the wrong set of fields, and clearing `Size` breaks
reallocation.** `ISASerialPort.m:195-207`. Reference zeroes exactly eight: `AllocBase`(52),
`Base`(24), `End`(28), `Output`(36), `Input`(32), `AllocSize`(48), `OverRun`(40), `Count`(4). Ours
zeroes `Size`(0), `Count`(4), `End`(28), `Base`(24), `Input`(32), `Output`(36), `HighWater`(8),
`LowWater`(12), `Enqueue`(16) — and leaves `AllocSize`, `AllocBase` and `OverRun` set. Clearing
`Size` is the harmful one: `_allocateRingBuffer` calls `_freeRingBuffer` **first** and then reads
`q->Size` as its requested size (23076 → 23082), so after our free the requested size is always 0
and every buffer silently falls back to `DefaultSize`, discarding whatever `executeEvent` set.

**Finding 58 — `_validateRingBufferSize`'s second parameter is a `Queue *` and ours passes the
object, in the wrong order.** `ISASerialPort.m:147, 1397, 3897, 3906`.
Reference 22932-22973: `if (size == 0) size = q->DefaultSize /* [edx+2Ch] = Queue+44 */;`
`if (size > 0x40000) size = 0x40000;` `if (size <= 0x11) size = 0x12;`. The clamps and both limits
(`MAX_RING_BUFFER_SIZE 0x40000`, `MIN_RING_BUFFER_SIZE 0x12`) match ours, and the reference's
`cmp eax, 11h / ja` is identical to our `size < 0x12`. What differs: the second argument is a
`Queue *` (Finding 13), and our call sites at 3897 and 3906 pass the arguments in the **opposite
order** to our own prototype at line 147 — two type errors.

**Finding 59 — `_RX_enqueueLongEvent` is `void` and truncates the event to 8 bits.**
`ISASerialPort.m:1658, 1667, 1682, 1698`. Reference 20684-20880 (and the identical copies at 0 and
23200): `void _RX_enqueueLongEvent(Port *port, unsigned char event, unsigned int data)`. The event
parameter is loaded as a byte (`mov dl, [ebp+arg_4]`) and masked with `and edx, 0FFh` before the
16-bit store; ours takes an `unsigned int` and stores `(unsigned short)event`, so a caller passing
more than 0xFF would write a value the reference cannot produce. Ours also returns
`IO_R_SUCCESS`; all 15 reference call sites discard `eax`. The algorithm — `Size - Count > 2` → three
cells `{event, data & 0xFFFF, data >> 16}`; else `Size > Count` → one cell `0x6C`; else
`OverRun = 1`; with `Input += 2`, wrap when `Input >= End`, and `Count++` per cell — matches ours
exactly.

**Finding 60 — `_TX_enqueueEvent` writes the wrong second data cell.**
`ISASerialPort.m:1748`. Reference 21040-21048 stores `(unsigned short)data` — bits 0-15,
deliberately duplicating byte 0, which the header cell already carries in its high byte. Ours stores
`(unsigned short)(data >> 8)`, bits 8-23. Any 2- or 3-cell TX event is corrupted.

**Finding 61 — `_TX_enqueueEvent` drives the MCR from the old state and sends the wrong event
payload.** `ISASerialPort.m:1812, 1815, 1830`. Reference 21299-21319 builds the MCR byte from the
**new** state (`al = 8; if (new & 2) al = 9; if (new & 4) al |= 2`); ours tests `oldState`. Since the
block only runs when bits 1-2 changed, ours drives DTR/RTS to the previous — i.e. inverted — value.
Reference 21372-21377 pushes `(newState & 0xFFFF) | (changedBits << 16)`; ours passes
`oldState | (changedBits << 16)`, which is both the wrong half and unmasked, so `oldState`'s high 16
bits collide with the delta field. The same `oldState`-instead-of-`newState` pair appears in
`enqueueData:` at our lines 4666-4671 and 4685-4687 against reference 8865-8883 and 8949-8958.

**Finding 62 — `_TX_enqueueEvent` has a dead local.** `ISASerialPort.m:1731` computes
`spaceNeeded = 1 + (event & 3)` and never uses it. The reference has no such computation; it gates
on `(event & 3) <= 1` (21036) and `== 3` (21077), which our lines 1746 and 1755 do match. Its return
values match too: `0` on success and on a zero event byte (20915), `IO_R_RESOURCE` (−702) when full
with `!sleep` (20964), and `_watchState`'s error otherwise.

**Finding 63 — `_RX_dequeueEvent`'s hardware-flow arm sets `0x04` where the reference sets `0x10`,
and our two dequeue functions disagree with each other.** `ISASerialPort.m:1552, 1583`.
Reference 21849 is `or cl, 10h` and 22009 is `and cl, 0EFh`; ours uses `STATE_RTS` (0x04). Our own
`_RX_dequeueData` uses `0x10` correctly at lines 1919 and 1949, so the two functions are
inconsistent. The same wrong constant appears in `_dataLatTOHandler` at our line 357 against
reference 9669.

**Finding 64 — `_RX_dequeueData` returns `IO_R_OFFLINE` where the reference returns
`IO_R_RESOURCE`.** `ISASerialPort.m:1875, 2023`. Reference 22320-22333: **both** the
`marker != 0x55` path and the `empty && !sleep` path jump to 22328,
`mov eax, 0FFFFFD42h` = **−702 = `IO_R_RESOURCE`**. Ours returns `IO_R_OFFLINE`, which
`return.h:66` defines as **−727**. The comments beside both `return` statements say "−702" — the
comment is right and the constant is wrong. This matters beyond the number:
`dequeueData:bufferSize:transferCount:minCount:` converts −702 to success (9257), treating "ring
empty" as a short read rather than an error, so with −727 every short read becomes a hard failure.

**Finding 65 — `_RX_dequeueEvent` and `_RX_dequeueData` otherwise match closely.** Recorded so
Tasks 3-6 do not rewrite what is already right. Confirmed matching in `_RX_dequeueEvent`: the
`Count != 0` / `!sleep → *eventType = 0, return 0` / `_watchState` loop (21424-21475); the length
switch on `cell & 3` (0 → `data = 0`, 1 → `data = cell >> 8`, 2 → one extra cell, 3 → two extra); the
`OverRun` re-enqueue at 21702-21744 **falling through** to the watermark update, where
`_RX_dequeueData` instead skips it (22378/22423) — our lines 1512-1524 and 1888/2003 reproduce that
asymmetry correctly; the `Dequeue >= Count` gate (21750); all nine RX `Enqueue`/`Dequeue` writes;
every `RXOstate` transition (−1→2, 1→−2, −2|0→1, 2→−1); the masks `State & 0x17E` and
`0xFFF0FE81`; the constants `0xC0000/0x40000/0x30000/0x20000`; `Size - 3`; the MCR built from
**newState** (correct in both, our lines 1614-1618 and 1980-1984); and
`!(State & 0x10000000) → thread_call_enter(FrameTOEntry)`. In `_RX_dequeueData`: the `0x55` marker
check reading `*(unsigned char *)Output` **before** consuming (22320-22326), and
`*byteOut = cell >> 8` (22370-22376).

**Finding 66 — the event-type byte constants are all real; two are mis-named.**
`ISASerialPort.h:124-125`, `ISASerialPort.m:116-121`. Every one of the nine appears in the
reference: `0x6C` (overflow marker, 54 and 8 other sites), `0x53` (state change, 21378 and 14 more),
`0x55` (valid-data marker, 22323, 8596), `0x68` (13774, 16370), `0x59` (13543, 16703), `0xFC`
(13702, 16858). But `0x61` (13388, 16548) and `0x5D` (13647, 16803) appear only as
`or dl, 61h` / `or dl, 5Dh` — they are OR'd into a byte being assembled, not used as standalone
event types, so naming them `EVENT_PARITY_ERROR` and `EVENT_FRAMING_ERROR` overstates what the
binary shows. TU 3 uses only `0x6C`, `0x53` and `0x55`; the other six are TU-1-only. Nothing is
invented.

### `_activatePort`, `_deactivatePort` and `_dataLatTOHandler`

**Finding 67 — `_activatePort`'s FCR gate uses the wrong threshold over the wrong enum.**
`ISASerialPort.m:1019-1021`. Reference 3161-3189:
`if (Type > 4) outb(Base + 2, FCRimage | 6);`. Ours:
`if (chipType > CHIP_16550 /* 3 */) outb(basePort + UART_FCR, fcrValue | 0x06);`. The `| 6` matches;
the threshold does not, and our enum is not the reference's index space (Finding 7). `Type > 4` is
exactly `_Chip[Type].FIFOsize != 0`.

**Finding 68 — `_activatePort`'s final IER write is masked in ours and not in the reference.**
`ISASerialPort.m:1248`. Reference 4119-4136: `outb(Base + 1, port->IERmask)`. Ours:
`outb(basePort + UART_IER, self->ierValue & 0x0F)`. `IERmask` is set to `0xFF` or `0xFB` by
`initFromDeviceDescription:` (2227, 2267), so the `& 0x0F` discards the top nibble — including the
MSR-interrupt enable the `"Enable MSR Interrupts"` key exists to control.

**Finding 69 — `_activatePort` and `_deactivatePort` return types.**
`ISASerialPort.m:976, 1258`. `_activatePort` genuinely returns an `IOReturn` — `_executeEvent`
captures it at 10921 — and returns `0xFFFFFD42` = −702 = `IO_R_RESOURCE` on allocation failure
(3076-3081). Ours matches the value but writes the raw hex literal under a comment reading "device
not available"; the name is `IO_R_RESOURCE`. `_deactivatePort` is **`void`** — no call site reads
`eax` — where ours returns `IOReturn`.

**Finding 70 — `_deactivatePort`'s structure, confirmed.** Reference 4156-4500, all 116
instructions read: early-out unless `State & 0x40000000`; `outb(Base + 1, IERmask & 8)`; clear
`0x40000000` and wake watchers; if `delta & 6` rebuild the MCR as
`8 | (new & 2 ? 1 : 0) | (new & 4 ? 2 : 0)` and `outb(Base + 4, mcr)`; if
`!(State & 0x10000000)` `thread_call_enter(FrameTOEntry)`; if `FlowControl & (delta << 16)`
`_RX_enqueueLongEvent(port, 0x53, (new & 0xFFFF) | (delta << 16))`; then
`_freeRingBuffer(&port->TX)`, `_freeRingBuffer(&port->RX)`, `_flowMachine(port)`, and a second
state merge `State = (State & 0xFFFFFFE9) | (flowResult & 0x16)` followed by the same
wake/MCR/timer/event tail. Note the merge mask is `0xFFFFFFE9` — `and dl, 0E9h` touches only the low
byte. Our source reproduces the shape; the divergences are the return type (Finding 69), the
parameter type (section 5) and the `State` split (Finding 8).

**Finding 71 — `_dataLatTOHandler`'s entry gate is inverted.**
`ISASerialPort.m:330`. Reference 9568-9574: `eax = RX.Count; cmp [RX.Enqueue], eax; ja exit` — the
whole state-update block runs only when **`RX.Enqueue <= RX.Count`**. Ours runs it when
`rxQueueUsed <= rxQueueTarget`, i.e. `Count <= Enqueue`. Inverted except when equal.

**Finding 72 — `_dataLatTOHandler` advances the ring on the completely-full path and the reference
does not.** `ISASerialPort.m:293, 322-327`. Reference 9447-9454: on
`RX.Size <= RX.Count` it sets `RX.OverRun = 1` and jumps straight to 9568, **skipping every pointer
advance**. Ours sets `rxQueueOverflow = 1` and then falls through to the common advance, bumping
`rxQueueWrite` and `rxQueueUsed` past the end of a full ring. The `0x4F`/`0`/`0` three-cell path
(9472-9565) and the one-advance `0x6C` path (9456-9467, jumping into the third advance block at
9547) both match ours.

**Finding 73 — the `Size - 3` watermark ladder is real, is inlined at 44 sites, and ours is
correct.** Recorded because an earlier reading of this binary wrongly concluded the reference had no
`- 3` arithmetic. It is emitted as `add reg, 0FFFFFFFDh`, not `sub reg, 3`, and appears in **10**
functions: `_activatePort` (3547, 3556, 3799, 3808), `executeEvent:data:` (6945, 6971, 7048, 7074),
`enqueueData:` (8735, 8744), `_dataLatTOHandler` (9763, 9772), `_executeEvent` (**18** sites),
`_FIFOIntHandler` (14011, 14020, 15883, 15892), `_NonFIFOIntHandler` (17087, 17096, 18355, 18364),
`_TX_enqueueEvent` (21187, 21196), `_RX_dequeueEvent` (21943, 21952), `_RX_dequeueData` (22623,
22632). Our `rxQueueCapacity - 3` and `txQueueCapacity - 3` are right. **The ladder is inlined at
every site in the reference**, so our source must inline it too — factoring it into a shared static
helper would emit a call the reference does not have.

### `_flowMachine` and `_watchState` (TU 4)

**Finding 74 — `_flowMachine`'s algorithm matches; only the layout is wrong.**
`ISASerialPort.m:455-518`. Reference 23400-23580, all 53 instructions read. The structure —
`if (FlowControl & 0x14)` then the DTR sub-test and the exclusive RTS/HW chain, else the DTR-only
arm; `HighWater < Count` selecting clear-versus-set; `RXOstate` transitions −1→2 and 1→−2; the
return of the new `State` in `eax` — is identical to ours. The only divergences are the parameter
type (`Port *`, section 5) and the `State` split: `test byte ptr [ecx+0Fh], 40h` at 23427, 23460,
23509, 23561 is `State & 0x40000000`, which our source reads as `statusFlags & 0x40`
(Finding 8). **This function will reach `assembly-matched` from the layout fix alone.**

**Finding 75 — `_watchState`'s algorithm matches except for the lock idiom, two return
constants and a cleanup our version skips.** `ISASerialPort.m:525-595`. Reference 23584-23774, all
71 instructions read.
Matching: the `mask & 0xC0000000` test adding `0x40000000` to both the mask and the cleared desired
state (23611-23634); the loop condition `((~State ^ desired) & mask) != 0` (23640-23650); the
`*state = State` store; `WatchStateMask |= mask`;
`thread_sleep(&WatchStateMask, &WatchLock.locked, 1)`; and
`while (thread_wait_result() == 4)`.

**Three** divergences. First, the lock: reference 23684-23705 is a bare `xchg`-based test-and-set —
`edx = &WatchLock.locked; spin: if (*edx) goto spin; eax = 1; xchg eax, *edx; if ((eax ^ 1) == 0)
goto spin;` — with the retry going back to the **spin label**. Ours (lines 562-573) calls
`IOEnterCriticalSection()`/`IOExitCriticalSection()`, which the reference never calls anywhere, and
its `continue` restarts the **outer** loop, re-testing the state. Second, the return constants —
Finding 76.

Third, **the cleanup is on every exit path in the reference and on only one of ours.**
`WatchStateMask = 0` and `thread_wakeup_prim(&WatchStateMask, 0, 4)` live at **23743**, and the
reference funnels its early exits into that block rather than returning around it: `jz loc_5CBF` at
**23666** (no active check, `ebx` still 0 — success), `jz loc_5CBF` at **23673** (active check made
but the active bit did not change — also success), and `jmp loc_5CBF` at **23680** after
`mov ebx, 0FFFFFD36h` at 23675 (the −714 exit). The wait-failed path at 23738 falls straight into
it. Ours instead `return`s at `ISASerialPort.m:553` and `:556`, so it runs the cleanup **only** when
the sleep fails — on the ordinary state-change return the watch mask stays set and **every other
thread blocked in `thread_sleep` on `&WatchStateMask` is left unwoken**. This is a live bug, not a
cosmetic one: the reference wakes those waiters on the common path. `4` is `THREAD_RESTART`
(`src/kernel-7/kern/sched_prim.h:74`), not `THREAD_AWAKENED`, which is 0.

There are three `nop`s at 23637-23639, interior alignment padding, which is why IDA's
extent is 191 against the 192-byte symbol gap.

### `IO_R_*` constant values

**Finding 76 — `_watchState`'s two return constants are both wrong, and both comments are right.**
`ISASerialPort.m:553, 588`. Resolved against `src/driverkit-3/driverkit/return.h`:

| site | reference returns | our source returns | our comment |
|---|---|---|---|
| 23675, state changed to inactive | `0xFFFFFD36` = **−714** = `IO_R_IO` | `IO_R_NO_DEVICE` = **−704** | `// -714 (0xfffffd36)` |
| 23738, wait failed | `0xFFFFFD41` = **−703** = `IO_R_IPC_FAILURE` | `IO_R_TIMEOUT` = **−726** | `// -703 (0xfffffd41)` |

In both cases the numeric value in the comment matches the reference and the **named constant does
not**. This is exactly the failure mode that has cost this effort four wrong verdicts.
`-[ISASerialPort acquire:]` compares `_watchState`'s result against −714 at 4785 as a retry
sentinel, so returning −704 breaks the acquire retry loop.

**Finding 77 — the complete `IO_R_*` audit.** Every constant the reference returns:

| hex | value | constant | reference sites |
|---|---|---|---|
| 0 | 0 | `IO_R_SUCCESS` | all success exits |
| `0xFFFFFD3B` | −709 | `IO_R_EXCLUSIVE_ACCESS` | `acquire:` 5405 |
| `0xFFFFFD3E` | −706 | `IO_R_INVALID_ARG` | `setState:` 6035; `requestEvent:` 7362; `dequeueEvent:` 8233; `enqueueData:` 8365; `dequeueData:` 9151; `_executeEvent` 13040 |
| `0xFFFFFD42` | −702 | `IO_R_RESOURCE` | `_activatePort` 3079; `enqueueData:` 8501; `dequeueData:` 9257 (compared, converted to 0); `_TX_enqueueEvent` 20964; `_RX_dequeueData` 22328 |
| `0xFFFFFD41` | −703 | `IO_R_IPC_FAILURE` | `_watchState` 23738 |
| `0xFFFFFD36` | −714 | `IO_R_IO` | `_watchState` 23675; `acquire:` 4785 (compared) |
| `0xFFFFFD33` | −717 | `IO_R_NOT_OPEN` | `release` 5483; `setState:` 6077; `executeEvent:` 6520; `enqueueEvent:` 8122; `dequeueEvent:` 8310; `enqueueData:` 8415; `dequeueData:` 9189; `_executeEvent` 10390 |
| `0xFFFFFD2B` | −725 | `IO_R_BUSY` | `executeEvent:` 7009 (buffer resize while active) |

**Finding 78 — both header `#define`s at `ISASerialPort.h:40-45` are dead and misleading.**
`IO_R_NO_RESOURCES` falls back to `IO_R_RESOURCE` (−702): the value is right but the name does not
exist in `return.h`, and the reference uses no name for −702. `IO_R_NO_PAPER` is defined as −737,
which is **already taken** — `return.h:77` defines `IO_R_MSG_TOO_LARGE` as −737 — so the `#define`
silently aliases an unrelated DriverKit error. Neither symbol is referenced anywhere in
`ISASerialPort.m` and neither value appears in the reference. Both should go. The identical
invented `IO_R_NO_PAPER` appears in `drvPCParallel`, so this is a pattern copied between drivers.

**Finding 79 — `setState:mask:` is missing its argument rejection.**
`ISASerialPort.m:5150-5155`. Reference 6027-6040: `if (mask & 0xC0001000) return IO_R_INVALID_ARG;`
— the two high `State` gates and the private bit 12 may not be set through this entry point. Our
source has no such check and a comment saying "For now, we'll just proceed with the low 32 bits".
Everything else in the method matches, including the `mask &= (0xFFFF0000 | ~FlowControl)`
narrowing, the `State < 0` open test, and the whole inlined state-change tail.

### `initFromDeviceDescription:`, `acquire:`, `release` and the Instance table

**Finding 80 — the `Port` struct's initial values.** Complete, from
`-[ISASerialPort initFromDeviceDescription:]` 273-842. Everything not listed is left zero by
`alloc`.

| `Port` off | field | initial value |
|---|---|---|
| — | ivar `port` (600) | `self + 296` |
| 0 | `Self` | `self` |
| 12 | `State` | **`0x060C0000`** — TX empty, TX below low, RX empty, RX below low |
| 68 | `RX.DefaultSize` | **1200** (`0x4B0`) |
| 124 | `TX.DefaultSize` | **1200** |
| 148 | `CharLength` | 0 (set to 16 by `_initChip`) |
| 180 | `MasterClock` | **1843200** (`0x1C2000`) |
| 189 | `XONchar` | **`0x11`** (DC1) |
| 190 | `XOFFchar` | **`0x13`** (DC3) |
| 224 | `FlowControl` | **`0x126`** (written 0 at 509, then `0x126` at 659) |

`Instance`, `PortName`, `IRQ`, `BreakLength`, `BaudRate`, `DLRimage`, `LCRimage`, `FCRimage`,
`IERmask`, `RBRmask`, `Type`, `Base`, `StopBits`, `TX_Parity`, `RX_Parity`, `WaitingForTXIdle`,
`MinLatency`, `PCMCIA`, `PCMCIA_yanked`, `RXOstate`, the four callout entries, all four intervals,
`SWspecial[0..7]`, `WatchStateMask`, `WatchLock`, and the RX/TX `Size`/`Count`/`Base`/`End`/`Input`/
`Output` and `RX.OverRun` are all explicitly stored as 0. **Never written by init:** the RX/TX
`HighWater`/`LowWater`/`Enqueue`/`Dequeue`/`AllocSize`/`AllocBase`, `TX.OverRun`, and all six
`Stats` counters — these rely on `alloc` zeroing.

**Finding 81 — the Instance-table keys are all different, and the configuration is fetched through
`configTable`.** `ISASerialPort.m:3795-3948`. The reference sends
`[deviceDescription configTable]` **once** (844-855), caches it, and then sends
`valueForStringKey:` to *that* object for every key. Ours sends `valueForStringKey:` directly to the
device description and never sends `configTable` at all.

| reference key | our key | reference handling |
|---|---|---|
| `"Instance"` | `"PortNum"` | `Instance = strtol(str, 0, 10)`, **no NULL check**; then `sprintf(buf, "ISASerialPort%d", n)`, `[self setName:buf]`, `[self setDeviceKind:"Serial"]`, `PortName = [self name]` |
| `"Chip Type"` | `"ChipType"` | loop `i = 0..8` `strcmp(_Chip[i].ShortName, str)`; no match → log and ignore; `i == 0` (`"Auto"`) → nothing; else `Type = i` and log |
| `"Bus Type"` | `"PortType"` | inline 7-byte `repe cmpsb` against `"PCMCIA"` → `PCMCIA = 1` |
| `"TX Buffer Size"` | `"TXBufSize"` | `TX.DefaultSize = _validateRingBufferSize(2 * strtol(str,0,10), &Port->TX)` |
| `"RX Buffer Size"` | `"RXBufSize"` | `RX.DefaultSize = _validateRingBufferSize(2 * strtol(str,0,10), &Port->RX)` |
| `"Chip Clock"` | `"ClockRate"` | `v = strtol(...)`; **`v > 999`** → `MasterClock = v` and log; else `MasterClock = 0x1C2000` |
| `"Heart Beat Interval"` | `"HeartBeat"` | present → `v = strtol(...)` and log; **absent → `v = 11000`**; clamp `v > 0x418937`; `ns = v * 1000`; `HeartBeatInterval.tv_sec = ns / 1e9`, `.tv_nsec = ns % 1e9`. Units are **microseconds** |
| `"Enable MSR Interrupts"` | `[dd numFlagStrings] == 0` | present → `IERmask = 0xFF` and log; absent → `IERmask = 0xFB` |

Two further defects here: the reference **doubles** the parsed buffer size before validating and
ours does not; and the two buffer-size slots are **swapped** in our source — the reference writes
`self+0x1A4` (`TX.DefaultSize`) from the TX key and `self+0x16C` (`RX.DefaultSize`) from the RX key,
while ours writes `0x1A4` from `"RXBufSize"` and `0x16C` from `"TXBufSize"`. The `IERmask` values
`0xFF`/`0xFB` match; note that `0xFB` clears **bit 2**, which is ELSI in standard 8250 numbering
rather than EDSSI (`0x08`) — that is what the code does, recorded without correction.

**Finding 82 — the four `thread_call_allocate` registrations, which pin the timeout handlers.**
`ISASerialPort.m:3878-3881`. Reference 1551-1620:

| `Port` off | field | handler | address |
|---|---|---|---|
| 232 | `FrameTOEntry` | `_frameTOHandler` | 10088 |
| 236 | `DataLatTOEntry` | `_dataLatTOHandler` | 9408 |
| 240 | `DelayTOEntry` | `_delayTOHandler` | 10148 |
| 244 | `HeartBeatTOEntry` | `_heartBeatTOHandler` | 10208 |

All four receive the **same** second argument, `self + 0x128` — the `Port *`. Ours passes
`thread_call_allocate(NULL, NULL)` for the first two, so our `_frameTOHandler` (line 215) and
`_dataLatTOHandler` (line 274) are **never registered and are dead code**, and it passes `self`
rather than the `Port *` for the others.

**Finding 83 — `initFromDeviceDescription:`'s call order, validation gates and return value.**
Reference: `configTable` → `"Instance"` → `strtol` → `sprintf` → `setName:` →
`setDeviceKind:"Serial"` → `name` → `numPortRanges` → `numInterrupts` → `numChannels` →
`portRangeList` → `interruptList` → `"Chip Type"` → up to 9 `strcmp` → `_identifyChip(port)` →
`"Bus Type"` → `_initChip(port)` → 4x `thread_call_allocate` → `"TX Buffer Size"` → `strtol` →
`_validateRingBufferSize` → same for RX → `"Chip Clock"` → `"Heart Beat Interval"` → `__udivdi3`
→ `__umoddi3` → `"Enable MSR Interrupts"` → **`objc_msgSendSuper(initFromDeviceDescription:)`** →
`[self enableAllInterrupts]` → `[self registerDevice]` → the final banner `IOLog`. It returns the
**super's** return value (2525); ours returns `self` (line 3967).
Validation: `numPortRanges != 1 || numInterrupts != 1 || numChannels != 0` →
`"%s: Invalid configuration\n"`; `(Base & 3) != 0 || portRangeList[0].size != 8` →
`"%s: Invalid Port configuration\n"` (one argument). Ours checks only `numPortRanges != 1` and never
sends `numInterrupts`, `numChannels`, `enableAllInterrupts` or `registerDevice`; it sends
`registerInterrupt:0`, a selector that does not appear in the reference's `__OBJC,__meth_var_names`.

**Finding 84 — every `IOLog` format string differs.** `ISASerialPort.m:3795-3966`. The reference's
complete set, from `__TEXT,__cstring`: `"ISASerialPort: Invalid Config Table\n"` (no argument),
`"%s: Invalid configuration\n"`, `"%s: Invalid Port configuration\n"`,
`"%s: Ignoring invalid Chip Type \"%s\" from Instance table\n"`,
`"%s: Using Chip Type \"%s\" from Instance table\n"`,
`"%s: Unable to determine chip type at I/O base 0x%x\n"`,
`"%s: Unable to allocate callout entries\n"`, `"%s: Master Clock set to %ld hz.\n"`,
`"%s: Heart Beat Interval set to %ld us.\n"`, `"%s: MSR Interrupts enabled.\n"`,
`"%s: Unable to enable interrupts\n"`, and the banner
`"%s: Base=0x%04x, IRQ=%d, Type=%s%s, FIFO=%d\n"`. Ours matches none of them exactly. In the banner
the two `%s` arguments are **transposed**: the reference passes
`PCMCIA ? "PCMCIA/" : ""` (the empty string is at 25108) then `_Chip[Type].LongName` then
`_Chip[Type].FIFOsize`, printing `Type=PCMCIA/16550AF/C/CF`; ours passes
`chipTypeNames[Type]` then `" (PCMCIA)"`, printing `Type=16550A (PCMCIA)`. `sprintf`'s format is
`"ISASerialPort%d"`, not `"%ld"`, and `setDeviceKind:` takes `"Serial"`, not `"SerialPort"`.

**Finding 85 — `+[ISASerialPort probe:]` must not free the instance.**
`ISASerialPort.m:3696-3705`. Reference 200-260, all 24 instructions:
`id o = [[ISASerialPort alloc] initFromDeviceDescription:dd]; return o != nil;` — and it **never
frees**, because `initFromDeviceDescription:` has already called `registerDevice`. Ours calls
`[instance free]` at line 3701, tearing down the device it just registered. Returning `YES`/`NO`
against the reference's literal `1`/`0` is equivalent.

**Finding 86 — `-[ISASerialPort free]` is the closest match in TU 1.**
`ISASerialPort.m:3978-4036`. Reference 2540-2772, all 68 instructions:
`s = spl4(); _deactivatePort(self->port); [self disableAllInterrupts];` then, for each of
`FrameTOEntry`, `DataLatTOEntry`, `DelayTOEntry`, `HeartBeatTOEntry` **in that order**,
`if (e) { thread_call_cancel(e); thread_call_free(e); }`; then `splx(s); [super free];`. Order, the
per-entry NULL guard, the cancel-then-free pairing, the `spl` bracket and the `[super free]` tail
all match ours. The only divergence is `_deactivatePort(self->port)` versus our
`_deactivatePort(self)`. Note `release` cancels in the **reverse** order (`HeartBeatTOEntry` first).

**Finding 87 — `getCharValues:forParameter:count:` answers any Instance-table key and adds no
`stringValue` send.** `ISASerialPort.m:5262-5325`. Reference 2840-3011:

```
if (!values || !count || *count == 0) goto super;
s = [[[self deviceDescription] configTable] valueForStringKey:parameter];
if (!s) goto super;
strncpy(values, s, *count - 1);
values[*count - 1] = '\0';
*count = strlen(values) + 1;
return 0;
```

There is no hard-coded parameter-name list. Ours reads the `deviceDescription` **ivar** directly
rather than sending the accessor — and that ivar does not exist in the reference — and adds a fourth
message, `[paramValue stringValue]` (line 5290), a selector absent from the reference's
`__OBJC,__meth_var_names`. The reference treats `valueForStringKey:`'s result as the
`const char *` itself. Everything else matches, including `*count = strlen + 1` counting the NUL.

**Finding 88 — `acquire:`'s reset block and its default values.**
`ISASerialPort.m:4038-4237`. Reference 4504-5447, all 257 instructions. `sleep` is read as a
**byte**. The retry loop: `spl4()`; `if (port->PCMCIA_yanked) return IO_R_EXCLUSIVE_ACCESS (−709)`;
`if (State & 0x80000000)` then `if (!sleep) return −709` else
`r = [self watchState:&v mask:0x80000000]` and retry when `r == 0` or `r == −714`, otherwise return
`r`. On success it does the inlined state change to the constant **`State = 0xA0400018`** and then:

| `Port` off | field | value |
|---|---|---|
| 192-220 | `SWspecial[0..7]` | 0 |
| 148 | `CharLength` | **16** |
| 164 | `BreakLength` | **2** |
| 189/190 | `XONchar`/`XOFFchar` | `0x11` / `0x13` |
| 152 | `StopBits` | **2** |
| 156 | `TX_Parity` | **1** |
| 160 | `RX_Parity` | 0 |
| 168 | `BaudRate` | **19200** (`0x4B00`) |
| 228 | `RXOstate` | **0** |
| 224 | `FlowControl` | **`0x126`** |
| 184 | `MinLatency` | 0 |
| 24/32/36 | `RX.Size = RX.DefaultSize`; `RX.HighWater = (2 * Size) / 3`; `RX.LowWater = HighWater >> 1` | |
| 64 | `RX.OverRun` | 0 |
| 80/88/92 | `TX.Size = TX.DefaultSize`; `TX.HighWater = (2 * Size) / 3`; `TX.LowWater = HighWater >> 1` | |
| 172 | `DLRimage` | 0 |

then `_programChip(port)`; `outb(Base + 1, IERmask & 0x08)`; `r = _flowMachine(port)`;
`msr = inb(Base + 6)`; the inlined state change with `mask = 0x1F6` and
`value = r | (_msr_state_lut[msr >> 4] << 5)`; and finally
`if (HeartBeatInterval.tv_sec * 1e9 + (int)tv_nsec) thread_call_enter(HeartBeatTOEntry) else thread_call_enter(FrameTOEntry)`.

Divergences: ours never resets `RXOstate`; our `RX.OverRun = 0` (line 4136) and `DLRimage = 0`
(line 4147) are **commented out**; the watermark block (4123-4139) writes the wrong slots per
Finding 12 and sets `rxQueueTarget = rxLowWater` where the reference sets
`TX.LowWater = HighWater >> 1`; `_msr_state_lut` is the identity table (Finding 3); and the
heartbeat test (4196-4201) reads a single `unsigned long long heartBeatInterval` ivar which our init
never populates (Finding 89), so ours always takes the `FrameTOEntry` branch. Ours masking
`_flowMachine`'s result and the LUT contribution separately instead of masking the combination with
`0x1F6` is numerically identical, since `0xF << 5 = 0x1E0` is a subset of `0x1F6`.

**Finding 89 — `HeartBeatInterval` and the three other intervals are `tvalspec_t` pairs, not 64-bit
nanosecond counts.** `ISASerialPort.h:154-155, 202-204`; `ISASerialPort.m:47-67, 3921-3939,
2068-2070, 3109-3111, 2498-2501, 4384-4385`.
The four intervals at `Port+248/256/264/272` are each `{tv_sec I, tv_nsec i}` and are passed
**straight** to `deadline_from_interval(tv_sec, tv_nsec)` with no division —
`_heartBeatTOHandler` 10280-10294, `_FIFOIntHandler` 15773-15787, `_NonFIFOIntHandler`
18246-18274, `dequeueData:` 9051/9060. Our header models `charTimeNS`/`charTimeFracNS` and
`heartBeatInterval` as a 64-bit nanosecond value and our helpers
`_ISASerialPortCombineParts`/`_ISASerialPortIntervalFromNanoseconds`/
`_ISASerialPortDeadlineFromParts` (lines 47-67) reconstruct a `u64` and re-divide by
`NSEC_PER_SEC` — work the reference does not do. Worse, our init at line 3934 writes
`HeartBeatInterval` from `__udivdi3(0,0,0,0)`/`__umoddi3(0,0,0,0)`, so it is **always 0**, and it
stores the parsed value at `0x230`/`0x234`, which is `CharLatInterval` — clobbering it. Also note
`charTimeNS`/`charTimeFracNS` are `FrameInterval.tv_sec`/`.tv_nsec`, and `charTimeOverrideLow`/
`charTimeOverrideHigh` are `DataLatInterval.tv_sec`/`.tv_nsec`.

**Finding 90 — `dequeueData:` arms the wrong callout, and `minCount` is a sleep budget.**
`ISASerialPort.m:4436, 4444, 4384-4385`. Reference 9024-9406, all 121 instructions. `minCount` is
purely a sleep budget: `_RX_dequeueData` is called with `sleep = (left != 0)`, so the call blocks
until at least `minCount` bytes have arrived and then drains the rest without blocking. `−702` from
`_RX_dequeueData` means "ring empty" and is converted to **success** (9257) — a short read is not an
error. The interval comes from `Port.DataLatInterval` (`self+0x228/0x22C`) and the callout armed and
cancelled is **`DataLatTOEntry`** (`port+0xEC` = `Port+236`) at 9327 and 9374. Ours uses
`self->delayTimeoutCallout`, which our header places at the `DelayTOEntry` slot — the **wrong
callout** — and reads the interval from `charTimeOverrideLow`/`High`. The `armed` 0/1/−1 tri-state,
the once-only arming, the `(left != 0)` sleep argument, the `−702 → 0` conversion, the
`minCount > size → IO_R_INVALID_ARG` guard and the trailing cancel-if-armed all match.

**Finding 91 — `release`'s teardown order and its two unconditional final writes.**
`ISASerialPort.m:4251-4348`. Reference 5448-6008, all 146 instructions:
`spl4()`; `if (State >= 0) return IO_R_NOT_OPEN`; `thread_call_cancel` in the order
`HeartBeatTOEntry`, `DelayTOEntry`, `DataLatTOEntry`, `FrameTOEntry` — the **reverse** of `free`;
the same reset block as `acquire:` **minus** `MinLatency` and `DLRimage`; `_programChip(port)`;
`_deactivatePort(port)` in that order; the inlined state change with `value = 0` (which folds the
MCR to `0x08`); then **unconditionally** `outb(Base + 1, 0)` and `outb(Base + 4, 0)`; `splx`;
return 0. Our version reproduces all 146 instructions and passes the `Port *` correctly. **It is
also layout-independent, and therefore `assembly-matched` now rather than after the layout fix:**
every field access in the body is a raw `(char *)self` or `(char *)selfPtr` offset cast — `0x134`,
`0x210`-`0x21C`, `0x1E8`, `0x1BC`-`0x1D0`, `0x208`, `0x20C`, `0x140`-`0x184`, `600`, and off the
`Port *` `0x0C`, `0x0F`, `0x10`, `0x88`, `0xE0`, `0xE8` — and **not one named ivar appears
anywhere in it**, so changing `ISASerialPort.h` cannot affect the generated code. What is wrong is
only the commentary: it mislabels `0x1CC` as `stopBits` (it is `BreakLength`) and `0x1C4` as
`flowControl` (it is `TX_Parity`), and it labels the `0x140/0x148/0x14C` block TX and
`0x178/0x180/0x184` RX — they are RX and TX respectively. **Fix the comments; leave the code
alone.**

**Finding 92 — `nextEvent` is already done; `getState` and the three other near-matches are not.**
`-[ISASerialPort nextEvent]` (reference 6400-6469, our 5088-5111) reproduces the reference
instruction for instruction — `spl4`; `if (RX.Count) { p = RX.Output; if (p >= RX.End) p -= RX.Size * 2; b = *p; }` —
including the `>=` wrap direction and the `Size * 2` stride, and it peeks without advancing
`Output`.

**`nextEvent` is correct as it stands and is `assembly-matched` now — it is not waiting on the
layout fix and it is not a cheap win, it is zero work.** The reference reads
`cmp dword ptr [ebx+144h], 0` for the count and then, off the `lea eax, [ebx+140h]` base,
`[eax+24h]` (`Output`), `[eax+1Ch]` (`End`) and `[eax]` (`Size`). Our lines 5097-5104 use the same
absolute offsets — `0x144`, `0x164`, `0x15C`, `0x140` — through raw `(char *)self` casts that never
consult `ISASerialPort.h`. The two-ivar layout change therefore cannot reach this method, in either
direction. **Task 6 must not edit it.**

`-[ISASerialPort getState]` (6280-6298, our 5120-5136) is
`return self->Port.State & ~0x1000` and matches. `-[ISASerialPort requestEvent:data:]`
(7340-8085, our 4958-5086) matches on every one of its 24 cases' offsets and expressions,
including Apple's `0x27` bug (section 6 item 4); its divergences are the `& 0xFF` masking
(Finding 31) and cases 0x4B/0x4F, where the reference computes
`(tv_sec * 1e9 + (int)tv_nsec) / 1000` from the two halves (7742-7802) while ours loads the pair as
one `unsigned long long` and multiplies the whole value by 1e9 before dividing (lines 5063, 5070).
`-[ISASerialPort dequeueEvent:data:sleep:]` (8208-8324, our 4466-4513) matches completely apart
from the `Port *` argument, including the `unsigned char` staging local and the zero-extending
store. `-[ISASerialPort enqueueEvent:data:sleep:]` (8088-8207, our 4717-4762) likewise, including
the `r == 0 && !(State & 0x10000000)` conjunction guarding
`thread_call_enter(FrameTOEntry)`. **Those four are cheap wins once the layout lands; `nextEvent`
is already banked.**

**Finding 93 — the inlined state-change sequence appears six times in TU 1 and must stay inlined.**
Reference sites: `setState:mask:` 6109-6255, `acquire:` 4580-4742 and 5165-5328, `release`
5783-5932, `executeEvent:data:` 6646-6811 and 7144-7313, `enqueueData:` 8798-8963. The body is:

```c
newState = (port->State & ~mask) | (value & mask);
delta    = newState ^ port->State;
port->State = newState;
if (port->WatchStateMask & delta)
        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
if (delta & 0x6) {                        /* DTR or RTS changed */
        mcr = 0x08;                       /* OUT2 */
        if (newState & 0x2) mcr = 0x09;   /* + DTR */
        if (newState & 0x4) mcr |= 0x02;  /* + RTS */
        outb(port->Base + 4, mcr);
}
if (!(port->State & 0x10000000))          /* NOT inside the delta & 6 block */
        thread_call_enter(port->FrameTOEntry);
delta <<= 16;
if (port->FlowControl & delta)
        _RX_enqueueLongEvent(port, 0x53, (newState & 0xFFFF) | delta);
```

The `thread_call_enter` placement was checked at all six sites: the `jz` that skips the MCR block
lands **on** the `test byte [x+0Fh], 10h` (6209, 4685, 6760, 7261, 5879, 8907), so it is
unconditional. Factoring this into a shared static function would emit a call the reference does not
have.

### libgcc helpers

**Finding 94 — our hand-written `__udivdi3` and `__umoddi3` recurse infinitely.**
`ISASerialPort.m:3490, 3588`. Our `__udivdi3` declares `unsigned long long dividend, divisor`
(line 3500) and then divides with the `/` operator — `remainder_and_low / divisor_lo` and
`return dividend / divisor_lo;`. Both promote to a 64/64 division, which gcc lowers to a **call to
`__udivdi3` itself**; the recursive call re-enters with `divisor_hi == 0` and takes the same branch,
so the recursion does not terminate. Kernel stack overflow on the first 64-bit divide.
`__umoddi3` needs the same audit. The reference bodies are libgcc's and use `bsr` plus 32-bit
`div`/`mul` only, with no 64-bit division operator, no recursion and no relocations.
**These helpers must stay** — `/usr/lib/libcc.a` on the guest is a PPC archive that cannot link for
`-arch i386` — but they must be rewritten using only 32-bit division. Depth note: for these two
functions only the mnemonic inventory, relocation list and block count were examined; the reference
bodies were **not** read instruction by instruction.

**Finding 95 — the explicit four-argument `__udivdi3`/`__umoddi3` call sites are a decompiler
artifact.** `ISASerialPort.m:70-73, 3308-3309, 3934-3935, 4837-4838, 5033, 5041`. gcc emits these
calls implicitly from an ordinary `unsigned long long` division; the four pushed dwords are just the
32-bit ABI for two 64-bit arguments. What the reference actually divides, in every case, is a
nanosecond count by `1000000000`: `_executeEvent` events 0x4B (12012, 12036) and 0x4F (10983,
11007) divide `(unsigned long long)(eventData * 1000)`, `_programChip` (20059, 20092) divides the
sign-extended `nsPerChar`, `initFromDeviceDescription:` (2137, 2161) divides
`heartBeatMicroseconds * 1000`, and `requestEvent:data:` (7797) divides
`tv_sec * 1e9 + (int)tv_nsec` by **1000** to convert back to microseconds. Our source should write
these as ordinary `unsigned long long` divisions and drop the forward declarations at lines 70-73.

## 8. Configuration table — a residual Task 1 defect

`diff` of `ISASerialPort.drvproj/Default.table` against Apple's, ignoring `"Driver Version"`:

```
 "Auto Resolve Conflicts";
-
 "Server Name" = "ISASerialPort";
```

The reference has a **blank line** between `"Auto Resolve Conflicts";` and
`"Server Name" = "ISASerialPort";`; ours does not. Every key and value is otherwise identical.
Per the task brief, a residual difference after Task 1 is a Task 1 defect, and this is one — a
single missing `\n`. It should be fixed in whichever task next touches the table.

`ISASerialPort.drvproj/ISASerialPort.lksproj/Load_Commands.sect` is now **164 bytes and
byte-identical** to the reference's `Loaded Server,Load Commands` section (both SHA-256
`78FEAAD1F976BAF28AFE83EC73EC4393BA16F514FEB3EED3E67609FB29FFED7F`). The plan's note that it was
163 bytes and "must be 164" is already resolved.

## 9. Unresolved

1. **Where the fourth copy of `ioPorts.h`'s three `xxx` statics comes from** (section 4.4). The four
   groups are definitely there and three are definitely TUs 1-3. Two hypotheses remain for the
   fourth: that TU 4 emits it despite performing no port I/O, or that it belongs to the
   build-generated `ISASerialPort_instance.m` and TU 4 contributes nothing. **Both predict the same
   48-byte section with the fourth group unreferenced, so the binary cannot distinguish them** — this
   one is closed only by a rebuild. Task 3 must verify `__DATA,__bss` from the rebuilt nlist rather
   than assume either; the failure mode either way is a visible 36-versus-48-byte
   `__DATA,__bss`.
2. **Apple's filenames for TUs 2, 3 and 4.** Not recoverable from this binary — only
   `ISASerialPort.m` and the generated `ISASerialPort_instance.m` are recorded.
3. **`_activatePort` and `_dataLatTOHandler` were examined at control-flow depth only.** Their
   findings (67-69, 71-72) are sound, but neither function has had every arithmetic instruction
   read, so a later task may find additional divergences in them.
4. **`__udivdi3`/`__umoddi3` reference bodies were not read instruction by instruction.** Finding 94
   rests on our side of the comparison plus the reference's mnemonic inventory.
5. **Whether `_identifyChip`'s missing MCR write (section 6 item 1) was intentional.** It is
   certainly what the binary does; whether Apple meant it is unknowable from here.

## Addendum: three points settled after the report pass

**The exported-symbol count is 11, not 12.** An independent verification pass read
`_RX_enqueueLongEvent` (address 0) as a twelfth `global` symbol. It is not. Decoding the
Mach-O nlist directly with `binrecon.macho.read_macho` gives exactly **11** externally
defined `__TEXT,__text` symbols — `identifyChip`, `initChip`, `programChip`,
`TX_enqueueEvent`, `RX_dequeueEvent`, `RX_dequeueData`, `validateRingBufferSize`,
`freeRingBuffer`, `allocateRingBuffer`, `flowMachine`, `watchState` — and **all three**
`_RX_enqueueLongEvent` copies report `binding=local`.

The `global` reading comes from `analysis-reference-ida.json`, which mislabels the copy at
address 0. This is the second time IDA's linkage metadata has disagreed with the nlist on
this driver, so treat the nlist as authoritative for every linkage question and never the
analysis JSON. `ISASerialPortInternal.h` declares **11** functions.

**`_programChip` has five call sites, not six**: 0xc51, 0x13c7, 0x1686, 0x2bb3, 0x4c47. The
top-level `references` entry for 0x4c50 lists exactly those five and no data references.

**Two incidental findings worth carrying into Task 6.**

`Port+0` holds a back-pointer to the owning Objective-C object.
`-[ISASerialPort initFromDeviceDescription:]` at 0x0123-0x0126 does
`mov edi,[ebp+self]` / `mov [esi+128h], edi`, having already stored `self+0x128` into
`self+0x258` at 0x011d. So the `Port` struct knows its owner, which is how the exported C
functions reach anything that genuinely needs the object.

`-[ISASerialPort executeEvent:data:]` at 0x1b70-0x1b80 looks like an original Apple bug: it
passes the **RX** queue (`lea edx,[edi+140h]`) to `validateRingBufferSize` but stores the
result into the **TX** size field (`mov [edi+178h], eax`). Harmless unless the requested
size is 0, in which case the RX default is applied to TX. The sibling site at 0x1b14 is
self-consistent RX/RX. Reproduce the reference's behaviour rather than correcting it, and
record the disposition — this is a parity effort, and an Apple bug faithfully reproduced is
a match, not a defect.
