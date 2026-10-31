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

> **SUPERSEDED — this table is the Task 1 snapshot and its `assembly-matched` row was
> false.** Commit `fed2f5bd` downgraded both entries after the Task 6a review found the
> status had never been earned (`rebuilt_sha256` is `null`; `nextEvent` is 70 bytes
> against our 80 and the streams differ structurally; `release` is 561 against 544).
> **Nothing in this reconstruction has ever been `assembly-matched`.** The live counts
> are in the last addendum's ledger section; read them, not this table. **The prose in
> the rest of this section is the Task 1 snapshot too** — where it says either function
> "is `assembly-matched`", read "matches the reference at control-flow depth".

| Status | Count | Meaning here |
|---|---|---|
| `unexamined` | 41 | A divergence was found — each carries a finding below |
| `intentional-mismatch` | 2 | Build-generated glue, not present in source |
| ~~`assembly-matched`~~ | ~~2~~ | **RETRACTED — see the note above** |
| `control-flow-confirmed` | 0 | — |

**Only two of the 43 mapped functions match, and that is the honest result** *(as of Task 1 —
neither was `assembly-matched`; see the note above)*. The other 41 diverge,
because the divergence is structural and global: the reference keeps all driver state in
one 304-byte `Port` struct reached through a single pointer ivar, and our source spreads that state
across 68 invented instance variables (section 4.1). Every C function's first parameter and every
method's state access is therefore wrong in our tree, independently of whether the algorithm above
it is right.

**The two exceptions are `-[ISASerialPort nextEvent]` (6400) and `-[ISASerialPort release]`
(5448), and they are exceptions for the same reason: neither reads a single named ivar.** Both
reach every field through raw `(char *)self` offset casts that never consult `ISASerialPort.h`, so
the layout change cannot touch them, and both already reproduce the reference. ~~They are
`assembly-matched` now, not after the layout fix.~~ **RETRACTED — see the note above. Both are
`control-flow-confirmed`; neither instruction stream was ever compared against a rebuilt one, and
both differ in size from the reference.** `release`'s comments mislabelled three fields
(Finding 91, fixed in Task 8) but comments do not reach the assembly.
**Tasks 3-6 must not rewrite either body.**

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
(5448) ~~are `assembly-matched` **now**~~ **already match the reference's control flow** — they use
raw casts exclusively and no named ivar at all (Findings 91, 92). *(Neither was ever
`assembly-matched`; see the retraction in section 1 and Addendum 6.)* `requestEvent:data:` is in the same style but has independent divergences
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

**Finding 10 — CORRECTED, then RESOLVED in Task 8: two constants are needed, not one
substitution.** As first written this finding said `STATE_RX_ENABLED` "is `0x00400000`, not
`0x00080000`". That is half right, and applied literally it would have broken two call sites
that were already correct. The single name was covering two different bits:

- **`0x00400000` is the handler-internal receive gate.** `test byte ptr [ebp+var_C+2], 40h` at
  `_FIFOIntHandler` 13237 and `_NonFIFOIntHandler` 16340 and 16449 — byte 2 of the state word,
  bit `0x40`. `acquire:` sets `State = 0xA0400018`, which carries this bit.
- **`0x00080000` is correct where it was already used**, as the `watchState` mask in
  `RX_dequeueEvent` and `RX_dequeueData`: the reference pushes `80000h` at 21443 and 22292, the
  only two `push 80000h` in the binary.

Task 8 added `STATE_RX_GATE = 0x00400000` beside `STATE_RX_ENABLED = 0x00080000` and moved the
three handler sites to the new name, leaving the two queue sites alone. Corroboration that the
gate is not bit 19: `test byte ptr ..., 8` occurs **zero times** in the reference's entire
`__text`, while `test byte ptr ..., 40h` occurs seventeen times.

Until Task 8 that gate was false for the life of the port, so both interrupt handlers read bytes
out of the RBR and discarded them. **The receive path did not work at all.**

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
**RESOLVED in Task 8**: the wrap now targets `port->TX.Base`, matching its own mirror sixty
lines later and the other fifteen ring wraps across the three files.

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

**Finding 68 — ~~`_activatePort`'s final IER write is masked in ours and not in the reference.~~
FALSE. RETRACTED IN TASK 10a.**
~~`ISASerialPort.m:1248`. Reference 4119-4136: `outb(Base + 1, port->IERmask)`. Ours:
`outb(basePort + UART_IER, self->ierValue & 0x0F)`. `IERmask` is set to `0xFF` or `0xFB` by
`initFromDeviceDescription:` (2227, 2267), so the `& 0x0F` discards the top nibble — including the
MSR-interrupt enable the `"Enable MSR Interrupts"` key exists to control.~~

> **RETRACTED.** The reference *does* mask, with exactly the same constant we use. 4128 is
> `mov al, [ebx+0B0h]` and **4134 is `24 0F` = `and al, 0Fh`** — `0x24` is `AND AL, imm8`, so there
> is no other reading. The claim's second half is wrong too: IER bit `0x08` **is** the modem-status
> enable and `0x0F` keeps it; what `& 0x0F` drops is the 82510's reserved high nibble. Our
> `outb(port->Base + UART_IER, port->IERmask & 0x0F)` was correct all along and is unchanged. This
> is the third finding in this effort to be retracted as false, after 94 and 102, and the second
> whose retraction came from re-reading the bytes rather than the prose.

**Finding 69 — `_activatePort` and `_deactivatePort` return types. RESOLVED in Task 10a.**
`ISASerialPort.m:976, 1258`. `_activatePort` genuinely returns an `IOReturn` — `_executeEvent`
captures it at 10921 — and returns `0xFFFFFD42` = −702 = `IO_R_RESOURCE` on allocation failure
(3076-3081). Ours matches the value but writes the raw hex literal under a comment reading "device
not available"; the name is `IO_R_RESOURCE`. `_deactivatePort` is **`void`** — no call site reads
`eax` — where ours returns `IOReturn`.

> **RESOLVED.** `deactivatePort` is now `static void`, forward declaration included, and both
> `return IO_R_SUCCESS;` are gone. The reference's early-out at 4169 jumps to the epilogue **without
> setting `eax`**, which settles it; our four call sites (`PCMCIA_yanked`, `_executeEvent`'s `0x05`
> arm, `acquire:`'s already-open teardown and `release`) all discard the value. `_activatePort`'s
> three `0xFFFFFD42` literals are now spelled `IO_R_RESOURCE`.

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

**Finding 71 — `_dataLatTOHandler`'s entry gate is inverted. VERIFIED AND FIXED in Task 10a.**
`ISASerialPort.m:330`. Reference 9568-9574: `eax = RX.Count; cmp [RX.Enqueue], eax; ja exit` — the
whole state-update block runs only when **`RX.Enqueue <= RX.Count`**. Ours runs it when
`rxQueueUsed <= rxQueueTarget`, i.e. `Count <= Enqueue`. Inverted except when equal.

> **VERIFIED against the bytes and FIXED.** 9568 `8B431C` loads `RX.Count` into `eax`, 9571
> `394328` compares `RX.Enqueue` against it and 9574 `ja` leaves for the `splx` at 10068, so the
> block runs on `Enqueue <= Count`. The gate now reads
> `if (port->RX.Enqueue <= port->RX.Count)`.

**Finding 72 — `_dataLatTOHandler` advances the ring on the completely-full path and the reference
does not. VERIFIED AND FIXED in Task 10a.** `ISASerialPort.m:293, 322-327`. Reference 9447-9454: on
`RX.Size <= RX.Count` it sets `RX.OverRun = 1` and jumps straight to 9568, **skipping every pointer
advance**. Ours sets `rxQueueOverflow = 1` and then falls through to the common advance, bumping
`rxQueueWrite` and `rxQueueUsed` past the end of a full ring. The `0x4F`/`0`/`0` three-cell path
(9472-9565) and the one-advance `0x6C` path (9456-9467, jumping into the third advance block at
9547) both match ours.

> **VERIFIED against the bytes and FIXED.** The ladder is three cases, not two: 9434 `cmp eax, 2` /
> `ja` on `Size - Count`, then 9442 `cmp [RX.Size], eax` / `ja` on `Size` against `Count`, then the
> fall-through at 9447 which is `mov dword ptr [ebx+40h], 1` followed by `EB70` — a **jump to
> 9568**, past all three advance blocks. Our source had the advance written once after the `if`,
> which is why the full case reached it. It is now spelled out in each of the two arms that need it
> and omitted from the third; gcc's cross-jumping merges the two copies, which is exactly how the
> reference gets its jump from 9467 into the shared advance at 9547.

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

**Finding 79 — `setState:mask:` is missing its argument rejection. VERIFIED AND FIXED in Task 10a.**
`ISASerialPort.m:5150-5155`. Reference 6027-6040: `if (mask & 0xC0001000) return IO_R_INVALID_ARG;`
— the two high `State` gates and the private bit 12 may not be set through this entry point. Our
source has no such check and a comment saying "For now, we'll just proceed with the low 32 bits".
Everything else in the method matches, including the `mask &= (0xFFFF0000 | ~FlowControl)`
narrowing, the `State < 0` open test, and the whole inlined state-change tail.

> **VERIFIED and FIXED.** 6027 is `F7C6 001000C0` = `test esi, 0C0001000h` where `esi` was loaded
> from `[ebp+arg_C]` at 6024 — that is `ebp+0x14`, the **mask**, not the state at `ebp+0x10` (which
> 6122 reads as `[ebp+arg_8]`). The test comes **before** `spl4` at 6048, so the rejection needs no
> `splx`. Added verbatim, returning `0xFFFFFD3E` = −706 = `IO_R_INVALID_ARG`. Everything else in the
> method was re-read instruction by instruction and confirmed, including the detail that
> `FlowControl` is reached **through `self`** at 6088 (`[ebx+208h]`, `ebx` = `self`) for the mask
> narrowing but **through the `port` ivar** at 6233 (`[ebx+0E0h]`, `ebx` reloaded at 6109) for the
> event test — the same field by two different paths, which our source already reproduced.

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

> **CLOSED in Task 10a**, on a full re-read of all 257 instructions. Task 8 had already fixed the
> `FlowControl`/`MasterClock` crossing, both ring sizes, `RXOstate`, `RX.OverRun` and `DLRimage`, and
> the reviewer walked the write order field by field; this pass confirmed the whole reset block again
> and closed the three residues:
> - the mask is now applied to the **combination** — `(oldState & 0xFFFFFE09) | ((flowState |
>   (msrStateBits << 5)) & 0x1F6)` — matching 5171 `or esi, eax` before 5182 `and esi, 1F6h`;
> - the heartbeat test is now the reference's 64-bit form (see Finding 89);
> - the first state-change tail no longer hand-folds `State = 0xA0400018`. The reference keeps both
>   MCR tests live against the literal (4635 and 4649 each materialise `0A0400018h` and mask it) and
>   takes the event data from it (4717 `mov ecx, 0A0400018h` / 4722 `and ecx, 0FFFFh`), so the tail
>   is written like every other copy rather than collapsed to `outb(Base + 4, 8)` and `| 0x18`.
>
> Also confirmed, so nobody re-derives them: `sleep` is read as a byte at 4516; the retry sentinel
> comparison at 4785 is against `0xFFFFFD36` and both `r == −714` and `r == 0` fall into the same
> retry; the two `(2 * Size) / 3` divides really do share one `ecx = 3` (4972, reused at 5027);
> `RX.LowWater` comes from the surviving quotient in `eax` (4989 `shr eax, 1`) while `TX.LowWater`
> comes from a fresh copy in `ecx` (5037-5039); and the eight `SWspecial` stores are a real loop
> (`cmp ebx, 7` / `jle`), not unrolled.

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

> **`acquire:`'s half CLOSED in Task 10a.** The struct/ivar half was closed earlier — the four
> intervals are `tvalspec_t` in `ISASerialPortInternal.h` and `acquire:` reads
> `Port.HeartBeatInterval`, i.e. reference `[edi+238h]`/`[edi+23Ch]` — but the **test** was still
> `tv_sec != 0 || tv_nsec != 0`. The reference forms one 64-bit value and tests that: 5331
> `mov ebx, 3B9ACA00h`, 5336 `mov eax, [edi+238h]`, 5342 `mul ebx`, then 5348-5356 `mov edx,
> [edi+23Ch]` / `mov eax, edx` / `cdq` and 5363-5366 `add`/`adc`, then 5369 `test ebx, ebx` and 5373
> `test esi, esi`. Because `tv_nsec` is **signed** and sign-extended by that `cdq`, the two spellings
> disagree for a malformed `tvalspec` (a negative `tv_nsec` can cancel `tv_sec * 1e9`), so this is
> not merely stylistic. Now written as
> `(unsigned long long)tv_sec * 1000000000ULL + (long long)(int)tv_nsec`, the same spelling Task 8
> used for `requestEvent:`'s `0x4B`/`0x4F`.

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
also layout-independent** — the claim that this made it `assembly-matched` is **RETRACTED**, it
was never true, `fed2f5bd` downgraded the entry to `control-flow-confirmed`, and the measured
sizes are 561 reference against 544 ours —**:**
every field access in the body is a raw `(char *)self` or `(char *)selfPtr` offset cast — `0x134`,
`0x210`-`0x21C`, `0x1E8`, `0x1BC`-`0x1D0`, `0x208`, `0x20C`, `0x140`-`0x184`, `600`, and off the
`Port *` `0x0C`, `0x0F`, `0x10`, `0x88`, `0xE0`, `0xE8` — and **not one named ivar appears
anywhere in it**, so changing `ISASerialPort.h` cannot affect the generated code. What is wrong is
only the commentary: it mislabels `0x1CC` as `stopBits` (it is `BreakLength`) and `0x1C4` as
`flowControl` (it is `TX_Parity`), and it labels the `0x140/0x148/0x14C` block TX and
`0x178/0x180/0x184` RX — they are RX and TX respectively. ~~**Fix the comments; leave the code
alone.**~~ **RESOLVED in Task 8 (`365a526b`):** all three mislabels plus the RX/TX block crossing
were corrected and the four locals renamed; the code was not touched, and was re-verified against
reference 5569-5753 afterwards.

**Finding 92 — `nextEvent` is already done; `getState` and the three other near-matches are not.**
`-[ISASerialPort nextEvent]` (reference 6400-6469, our 5088-5111) ~~reproduces the reference
instruction for instruction~~ **matches the reference's control flow** — `spl4`; `if (RX.Count) { p = RX.Output; if (p >= RX.End) p -= RX.Size * 2; b = *p; }` —
including the `>=` wrap direction and the `Size * 2` stride, and it peeks without advancing
`Output`.

> **CORRECTION (Task 6a review, commit `fed2f5bd`).** "Instruction for instruction" was false and
> was never measured when written. The reference body is 70 bytes; ours is 80, and the streams
> differ structurally — ours emits `sub esp,4` plus a `[ebp-4]` staging slot, addresses the fields
> directly where the reference works off a single `lea` base, and inverts the sense of the first
> branch. The entry is `control-flow-confirmed`, not `assembly-matched`.

**`nextEvent` is correct as it stands and needs no work — it is not waiting on the
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

## Addendum 2: Task 3 outcome, and a finding the reline exposed

**Task 3 landed the structural change.** `__OBJC,__instance_vars` went from 820 bytes to
**28 — an exact match**. Our scattered ivars are now one embedded `Port` struct plus a
`Port *`, carrying Apple's field names. A reviewer decoded ivar 0's type encoding out of both
binaries: they are 964 characters each and differ in exactly **12** characters, every one
`L` in the reference against `I` in ours — the same width on i386. All 42 field names, their
order, the nesting and the `[8L]` array are byte-identical, and `sizeof(Port)` is 304 in both.

**Correction to an earlier draft of this addendum.** It said the struct sits at offset 296
with the pointer at 600. That is the *reference's* layout, not ours. Our rebuilt binary puts
ivar 0 at **264**, ivar 1 at **568**, with `instance_size` **572**; the reference is
296 / 600 / 604. The 32-byte delta is explained by Finding 96 below. `__OBJC,__module_info` held at **32**, so the `.c` decision paid off.
`missing_symbols` fell 24 → 13; sections matching went 17/30 → **18/30**.
`reference-only` externals is **empty**: all 11 exported functions now exist with the
reference's linkage. `ours-only` is `___udivdi3`/`___umoddi3`, our libgcc substitutes, which
are `local` in the reference — Task 6's business.

`flowMachine` and `watchState` moved to `ISASerialPortFlow.c`. `watchState`'s missing cleanup
is fixed: all four exits now funnel through `WatchStateMask = 0` plus `thread_wakeup_prim`,
mirroring the reference's three jumps into 23743 and its fall-through. Finding 76 is also
fixed — it now returns −714 and −703 where the reference does, rather than −704/−726.

**New finding: 15 C functions still carry a leading underscore the reference does not have.**

This surfaced when the source map was relined. `binrecon.source_map.source_sites` keys sites
by *compiled* symbol name, so a source function named `activatePort` keys as `_activatePort`
and matches the reference symbol, while one named `_activatePort` keys as `__activatePort`
and does not. The 11 functions Task 3 exported now match. These 15 do not:

`_activatePort`, `_deactivatePort`, `_executeEvent`, `_FIFOIntHandler`, `_NonFIFOIntHandler`,
`_PCMCIA_yanked`, `_dataLatTOHandler`, `_frameTOHandler`, `_delayTOHandler`,
`_heartBeatTOHandler`, the three `_RX_enqueueLongEvent` copies, and
`__udivdi3`/`__umoddi3`.

All are TU 1 or libgcc, so **Task 6 owns the rename** — drop one leading underscore from each
so the compiler emits the reference's symbol. This is the same divergence class that appeared
in four of the five sibling input drivers.

Note for whoever reruns the map: a fresh `binrecon source-map` will report roughly 28 mapped
and 17 unmapped rather than the committed 43 and 2, purely because the generator cannot
auto-match those 15 names. That is **not** a partition change — `fresh-only` is empty and the
committed `mapped` set is a superset. Reline by matching each reference symbol against both
its exact key and the `_`-prefixed key our still-underscored source produces, and point all
three `_RX_enqueueLongEvent` copies at our single definition. Once Task 6 lands the rename the
generator will match them directly and this workaround becomes unnecessary.

**Still open.** `__DATA,__bss` is 12 against the reference's 48. `ISASerialPortFlow.c` does no
port I/O and does not import `ioPorts.h`, so it contributes no `outb` static group. Tasks 4
and 5 will each add one, which is the decisive test of whether the fourth group belongs to
TU 4 or to the build-generated `ISASerialPort_instance.m`. Do not force it either way.

## Finding 96 — the superclass diverges, and it explains the 32-byte offset gap

**The reference subclasses `IODirectDevice`; ours subclasses `IODevice`.** The reference's
symbol table carries an undefined `.objc_class_name_IODirectDevice` that our `_reloc` does
not — verified directly in both binaries.

`IODirectDevice.h` adds exactly 32 bytes of instance variables: `_deviceDescription`,
`_interruptPort`, `_ioThread`, `_deviceDescriptionDelegate`, `_busPrivate`, `_private` and an
`int[2]`. So 264 + 32 = **296**, which is precisely the reference's ivar 0 offset.
Independently, `ISASerialPortVersion`'s `instance_size` is 264 in **both** binaries, so
`IODevice` is the same size on both sides and the entire delta is the superclass.

This is the fifth driver in this effort to carry a superclass divergence, and it has three
consequences:

1. **Every raw-offset access in `initFromDeviceDescription:` is 32 bytes short.** There are
   161 of them, spanning `self+0x128` to `self+0x23c`, plus `self+0x258`. With our 572-byte
   object, `self+0x258` (600) writes **past the end**. This is pre-existing rather than a
   Task 3 regression — the old scattered ivar block was about 250 bytes, so `self+600` was
   already out of bounds — but no offset-based claim about this driver is sound until the
   superclass is corrected.
2. It plausibly also accounts for `__OBJC,__protocol` at 20 in the reference against 0 in
   ours, and `__cat_cls_meth` 12/0 and `__cat_inst_meth` 100/0.
3. It is why our source already implements `getHandler:level:argument:forInterrupt:`, which
   is an `IODirectDevice(IOInterrupts)` method.

**Task 6 owns the `: IODirectDevice` change**, together with the two items below, because all
three touch the same declaration and should land as one coherent change.

**Also for Task 6, from the same review.** Twelve `Port` fields should be `unsigned long`
rather than `unsigned int` — `State`, `WatchStateMask`, `BaudRate`, `MasterClock`, the
`SWspecial[]` array and the six `Stats` members. On i386 that is zero codegen change, and it
makes ivar 0's type encoding byte-identical to the reference's. Note the field count is 42,
not the 43 an earlier draft claimed.

And `watchState`'s lost-lock-race path uses `continue` inside a `do…while`, which jumps to the
loop condition and reads `waitResult` uninitialised. The reference retries at its spin label
(23705 → 23688), not at the outer loop (23640). Pre-existing, and correctly still open as part
of Finding 75.

**On `___udivdi3`/`___umoddi3`:** in the reference these are `local` **and carry different
symbol names** — `__udivdi3`/`__umoddi3` — so both the linkage and the name diverge. Adding
`static` would close half of it in one token but would land a change inside code Task 6 owns,
so it is deferred alongside the other underscore renames.


## Addendum 3: Task 4 outcome — TU 3 split out and its findings closed

**The ring buffer is its own translation unit.** `TX_enqueueEvent`, `RX_dequeueEvent`,
`RX_dequeueData`, `validateRingBufferSize`, `freeRingBuffer` and `allocateRingBuffer` moved
from `ISASerialPort.m` to `ISASerialPortQueue.c`, in the reference's link order — 20884,
21400, 22252, 22932, 22976, 23068 — with `CFILES = ISASerialPortFlow.c ISASerialPortQueue.c`
in the `Makefile`. `ISASerialPort.m` lost 747 lines. All six ledger entries are now
`control-flow-confirmed`.

**The three `_RX_enqueueLongEvent` copies are confirmed, and the shared-header theory with
them.** The definition moved from `ISASerialPort.m` into `ISASerialPortInternal.h`, still
`static`. The rebuilt nlist now carries **three** copies against the reference's three, one
per translation unit that references it, and in TU 3 the copy precedes `TX_enqueueEvent`
exactly as 20684 precedes 20884. `parity_check.py` reporting "ours 0" is only the name: our
source still spells it `_RX_enqueueLongEvent`, so the emitted symbol is
`__RX_enqueueLongEvent` — one of the fifteen renames Task 6 owns.

This also settles why TU 1's copy sits at address **0**. A definition at source line 1506 of
the `.m` cannot be emitted ahead of everything else in the unit; a `static` in a header
imported at the top is. Section 9 item 1's hypothesis is now the explanation rather than a
guess. Entries 0, 20684 and 23200 are `signature-confirmed`; Finding 59 stays open.

**`__DATA,__bss` narrowed, not settled.** 12 → **24** against the reference's 48.
`ISASerialPortQueue.c` imports `ioPorts.h` and calls `outb`, so it contributes one group of
the three `xxx` statics — two of four groups now. Task 5 adds TU 2's, making three. The
fourth therefore **cannot** be TU 4: `ISASerialPortFlow.c` does no port I/O and the reference's
TU 4 shows no `out` instruction either. Section 9 item 1's remaining two hypotheses reduce to
one — the build-generated `ISASerialPort_instance.m` — but the binary still cannot prove it,
so leave it open and do not force it.

**`__TEXT,__text` is now 984 bytes under the reference (23428 against 24412), having been
over.** The Task 4 edits account for part of the drop: removing `IODelay(1)` from two MCR
sites, the `IOEnterCriticalSection`/`IOExitCriticalSection` pair from a third, and the dead
`spaceNeeded` local all deleted instructions the reference does not have, which is progress
even though the number moved away from parity in absolute terms. The residual shortfall is
overwhelmingly TU 1: `initFromDeviceDescription:` and the two interrupt handlers still have
stubbed-out call sites (`// _FIFOIntHandler(0, 0, port);` and its siblings are commented out),
and twenty-five of the TU 1 entries are still `unexamined`, so their bodies have not been read instruction by instruction.
**Do not treat the 984 bytes as a TU 3 debt.**

### Findings closed

**Finding 53 — closed.** `allocateRingBuffer` returns `1` on success, matching `mov eax, 1` at
23186; failure still returns 0 as 23113 does. Both call sites' `== 0` test is the same
predicate as the reference's `test al, al`, so neither needed touching. The port can be opened.

**Finding 54 — closed.** `AllocSize` goes to `Queue+48` (23097) and `AllocBase` to `Queue+52`
(23106), two distinct fields, through the named `Queue` members Task 3 introduced rather than
raw offsets.

**Finding 55 — closed.** `q->Enqueue = q->LowWater` (23173-23176). `LowWater` is no longer
clobbered.

**Finding 56 — closed.** `IOFree(q->AllocBase, q->AllocSize)` (22989-22997), guarded on
`q->Base != NULL` as 22983 is. No more heap corruption on deactivate.

**Finding 57 — closed.** Exactly the reference's eight fields are zeroed, in its order:
`AllocBase`, `Base`, `End`, `Output`, `Input`, `AllocSize`, `OverRun`, `Count` (23002-23051).
`Size` survives, so `allocateRingBuffer`'s `q->Size` read at 23082 sees what
`executeEvent:data:` asked for.

**Finding 58 — closed for TU 3.** `validateRingBufferSize` needed no change: the `DefaultSize`
read from `Queue+44` (22945), the `0x40000` ceiling and the `0x12` floor all match, and the
`Queue *` second parameter is the reference's. Its two **call sites** in `ISASerialPort.m`
(now lines 2999 and 3008) still pass `&self->Port.TX` for the RX size and `&self->Port.RX` for
the TX size — Task 6's, and see the addendum note on Apple's own RX/TX slip at 0x1b70.

**Finding 60 — closed.** The second TX data cell stores `(unsigned short)data`, bits 0-15
(21040), not `data >> 8`.

**Finding 61 — closed.** The MCR byte is built from the **new** state (21299-21319) and the
event payload is `(newState & 0xFFFF) | (changedBits << 16)` (21372-21377). The same
`oldState`-for-`newState` pair in `enqueueData:` is TU 1's and still open.

**Finding 62 — closed.** The dead `spaceNeeded` local is gone. The reference gates only on
`(event & 3) <= 1` (21036) and `== 3` (21077).

**Finding 63 — closed.** The hardware-flow arm sets `0x10` (21849, and `and cl, 0EFh` at
22009), not `STATE_RTS`. `RX_dequeueEvent` and `RX_dequeueData` now agree with each other and
with the reference. The third instance, `_dataLatTOHandler` against reference 9669, is TU 1's and
still open.

**Finding 64 — closed.** Both `RX_dequeueData` exits return `IO_R_RESOURCE` (−702, 22328), not
`IO_R_OFFLINE` (−727, `return.h:66`). Short reads convert to success at 9257 again. The
comments were right and the constants were wrong, for the second time on this driver after
Finding 76.

### New findings from the Task 4 read

**Finding 97 — two of the four TX level constants were values the reference never uses.**
`ISASerialPortInternal.h:104-110`. The reference's TX quartet is `0x06000000`, `0x02000000`,
`0x01800000`, `0x01000000`, and it is the **same at all six sites**: `_activatePort`
3510/3526/3570/3586, `enqueueData:` 8701/8714/8758/8774, `_executeEvent` 11741-11814 and
12926-13002, `_FIFOIntHandler` 15846-15922, `_NonFIFOIntHandler` 18319-18394,
`_TX_enqueueEvent` 21153/21166/21210/21226. `0x04000000` appears **nowhere in the binary**.
`TX_STATE_ABOVE_HIGH` (`0x01000000`) is the right value for the above-high-water case, and the
critical case — `Count > Size - 3` — needs `0x01800000`, which had no name. Added
`TX_STATE_CRITICAL 0x01800000`, mirroring `RX_STATE_CRITICAL`, and used both correctly in
`TX_enqueueEvent`. **`TX_STATE_BELOW_LOW 0x04000000` was left in the header because
`ISASerialPort.m` still uses it twice; those two uses are wrong and are Task 6's** — the value
should not survive the rename pass.

**Finding 98 — three MCR writes carried invented delay and critical-section calls.**
`ISASerialPortQueue.c`, formerly `ISASerialPort.m:1469, 1668, 1836-1838`. The reference's
inlined state change goes straight from `out dx, al` plus the `outb` inline's
`inc ds:_xxx_86_1` to the `test byte ptr [x+0Fh], 10h` that guards `thread_call_enter`:
21332-21340, 22186-22194, 22866-22874. Ours had `IODelay(1)` after two of the three writes and,
after the third, `IOEnterCriticalSection(); /* placeholder */ IOExitCriticalSection();`.
Finding 75 already established the reference calls neither critical-section routine anywhere.
All three removed. `IODelay` sites elsewhere in `ISASerialPort.m` were not audited and remain
Task 5's and Task 6's.

**Finding 99 — the RX state merge was missing its narrowing mask.** Both dequeue functions.
The reference computes `(State & 0xFFF0FE81) | (accumulated & 0x000F017E)` —
`and eax, 0F017Eh` at 22107 and 22787 — where ours ORed the accumulator in unmasked. The mask
is redundant given how the accumulator is built, so this is a codegen difference rather than a
behavioural one, but the reference emits the instruction and now so does our source.

**Finding 100 — `RX_dequeueData`'s flow-control arms were independent tests, and it shifted the
delta the wrong way.** Formerly `ISASerialPort.m:1764-1778` and `1794-1808`, and `:1847`.
The reference is an exclusive chain in both arms — RTS (22500, 22664) beats hardware (22520,
22680) beats DTR (22584, 22748) — so at most one of the three bits is touched per transition.
Ours ran all three tests, so an RTS-plus-DTR configuration set both. `RX_dequeueEvent`'s
nested form already meant the chain and was rewritten to read like it. Separately, ours tested
`FlowControl & (changedBits >> 16)` where the reference shifts the delta **up** into the event
mask before testing it (`shl edi, 10h` at 22895, matching 22215 in `RX_dequeueEvent`), so the
state-change event fired on the wrong bits or not at all. Both fixed.

### Still open in TU 3

**Finding 59 stays open.** `_RX_enqueueLongEvent` is `void` in the reference and takes an
`unsigned char event` masked with `and edx, 0FFh` at 90; ours returns `IOReturn` and takes an
`unsigned int`. Neither change would touch a call site — all fifteen discard the result and all
pass a byte-sized event — but it would change the codegen of TU 1's and TU 4's copies as well,
so it is left with the underscore rename that Task 6 owns.

The six functions are `control-flow-confirmed` rather than `assembly-matched` for one reason:
every reference instruction has been read and our source matches it branch for branch and
constant for constant, but **our rebuilt object has not been disassembled and compared**.
`ledger.json`'s `rebuilt_sha256` is still `null`. Whoever runs that comparison should be able
to close all six.

## Addendum 3: the fourth `__bss` group is settled, and three record corrections

**The `__DATA,__bss` question is closed, and an earlier hypothesis in this document was
wrong.** Addendum 2 said the fourth `outb` static group might belong to the build-generated
`ISASerialPort_instance.m`, and Task 4's report went further and said it "cannot be TU 4"
because `ISASerialPortFlow.c` performs no port I/O. Both were wrong.

The reference's `__DATA,__bss` is 48 bytes at 0x80c4 holding **four** groups of
`_xxx.86`/`_xxx.89`/`_xxx.92`, twelve bytes apart, at 0x80c4, 0x80d0, 0x80dc and 0x80e8 —
exactly one per translation unit. TU 4's group is emitted because the reference's TU 4
**includes `<driverkit/i386/ioPorts.h>`** and is simply never incremented, since that unit
does no port I/O. The mechanism is the same one that produces the unreferenced
`_RX_enqueueLongEvent` copy at 23200 in the same unit: a header contributes its statics
whether or not the including unit uses them.

Confirmed empirically. Adding that import to `ISASerialPortFlow.c` moved our
`__DATA,__bss` from **24 to 36** — a third group — with `make exit=0` and no new warnings.
Task 5's TU 2 split should supply the fourth and bring it to 48. The
`ISASerialPort_instance.m` hypothesis is unnecessary and is withdrawn.

**Correction to Finding 97.** The record says the reference uses those four TX level constants
"at all six sites". There are **seven** — `_executeEvent` accounts for two. And "`0x04000000`
appears nowhere in the binary" is true of *immediates*, which is what matters, but that byte
pattern does occur 25 times as a displacement; the claim should be stated as
"no exact-immediate occurrence".

**Correction to the `__TEXT,__text` attribution.** Task 4's report put the shortfall at 984
bytes and outside TU 3 entirely. The gap is **1028** bytes (24412 − 23384), and TU 3 carries
**−140** of it, about 14%: `_RX_enqueueLongEvent` −68, `RX_dequeueEvent` −72,
`TX_enqueueEvent` −24, `RX_dequeueData` −4, `allocateRingBuffer` **+28**, with
`validateRingBufferSize` and `freeRingBuffer` byte-size identical to the reference at 44 and
92. So −888 lies outside TU 3, which does support the conclusion that the bulk is TU 1 and
TU 2 — but `RX_dequeueEvent`'s −72 is a real TU 3 residual, not zero.

**Finding 59 is behavioural, not cosmetic.** It was deferred to Task 6 alongside the
underscore rename, which is the right call because the single `static` in
`ISASerialPortInternal.h` drives all three per-TU copies at once. But Task 6 should treat it
as a **behaviour fix**: the reference masks with `and edx, 0FFh` at 20774 where ours performs
an unmasked 16-bit load, and the three copies account for roughly 204 bytes of the text gap.

**A ceiling on achievable text parity, worth knowing before anyone chases the last bytes.**
The reference uses memory read-modify-write (`add dword ptr [ecx+0x38], 2`) and separate
per-path epilogues, where our compiler keeps the pointer in a register and tail-merges. That
is an optimisation-level difference rather than a source divergence, and it limits byte parity
independently of correctness.

## Addendum 4: Task 5 outcome — TU 2 split out, and the chip table written

**The chip table is the first thing in this reconstruction to match a whole
section exactly.** `_Chip` (180 bytes, nine rows of 20) and `_msr_state_lut`
(16 bytes) are now `external` and non-`const` in `__DATA,__data`, and that
section went **36 → 196 against the reference's 196**. Since those two symbols
are the entire section, an exact size match means the stride, the row count and
the field count are all right. `chipTypeNames[]` and `chipCapTable[]` are gone,
`__TEXT,__const` dropped from 196 to nothing as they left it, and
`__TEXT,__cstring` went 649 → 716 against 742 as the thirteen part names
replaced the nine invented ones.

The table was decoded a second time, independently, before being written:
`__DATA,__data` read raw from file offset 35164, unpacked as nine 5-dword rows,
the two `IntHandler` addresses checked against the nlist (13060 `_FIFOIntHandler`
and 16232 `_NonFIFOIntHandler`, **both `local`**), and all thirteen strings read
out of `__TEXT,__cstring` at 24412-24532. **The decode agreed with the report
pass on every one of the 45 fields.** Two things fell out of it that are worth
keeping:

- Because both interrupt handlers are `local`, the table's **definition has to
  live in `ISASerialPort.m`** — a plain C translation unit cannot name them.
  `ISASerialPortInternal.h` declares `ChipInfo` and the two `extern`s, and
  `programChip` reads `MaxBaud` through that.
- The cstring order is the exact reverse of rows 0..8 with `ShortName` before
  `LongName`, deduplicated, which is consistent with gcc emitting cstrings in
  reverse order of first appearance. That independently corroborates the row
  order and the field order, and it is why `"Auto"` sits last at 24528 rather
  than first.

**`__DATA,__bss` is 48 and section 9 item 1 is now fully closed.**
`ISASerialPortChip.c` imports `<driverkit/i386/ioPorts.h>` and does real port
I/O, so it supplied the fourth `_xxx.86/.89/.92` group: 36 → **48**, an exact
match. Four translation units, four groups, one per unit. The
`ISASerialPort_instance.m` hypothesis stays withdrawn.

`missing_strings` fell 29 → **21**, by exactly **eight**. A naive count says
nine, but `"Auto"` was already in `chipTypeNames[]` and so was never missing; the
eight are `82510`, `ST16C650`, `16C1550`, `16550AF/C/CF`,
`16550 with defective FIFO`, `16C1450`, `8250A or 16450` and `Unknown`.
`extra_strings` fell 25 → 21 as `16550A`, `16750`, `16950` and `16550?` went.
Sections matching went 18/30 → **20/30**.

### Findings closed

**Finding 2 — closed.** `_Chip` exists, external and non-`const`, all five
fields including the three pointers `chipCapTable` lacked entirely.
`ChipCapabilities` is deleted.

**Finding 3 — closed.** `_msr_state_lut` is
`00 01 08 09 04 05 0C 0D 02 03 0A 0B 06 07 0E 0F`, so DSR and DCD are no longer
transposed in every modem-status report. It was also renamed
`_msr_state_lut` → `msr_state_lut`, because the leading underscore in the C name
made the emitted symbol `__msr_state_lut` rather than the reference's. Its three
readers in `ISASerialPort.m` were updated mechanically.

**Finding 4 — closed for TU 2.** All 28 `IODelay(1)` calls in these three
functions are gone (18 in `identifyChip`, 3 in `initChip`, 7 in `programChip`).
No `IODelay` remains anywhere in TU 2. The two in TU 3 went with Task 4, so what
is left is TU 1's.

**Finding 5 — not applicable to TU 2.** No critical-section pair was in these
three functions. The remaining sites are TU 1's.

**Finding 6 — closed.** `chipTypeNames[]` is deleted. The `"Chip Type"` match
walks `Chip[i].ShortName`, so `"82510"` is now matchable and `"16550"` selects
row 5 rather than row 3.

**Finding 7 — closed.** The `CHIP_*` macros were renumbered onto the reference's
nine rows: `CHIP_UNKNOWN 0`, `CHIP_8250 1`, `CHIP_16450 2`, `CHIP_16C1450 3`,
`CHIP_16550_BADFIFO 4`, `CHIP_16550AF 5`, `CHIP_16C1550 6`, `CHIP_ST16C650 7`,
`CHIP_82510 8`. `CHIP_16750` and `CHIP_16950` are gone — the reference does not
support those parts. The one use outside TU 2 was `_activatePort`'s
`Type > CHIP_16550`, which was `> 3`; it is now `Type > 4`, the reference's
literal at 3161 and the same form `getHandler:level:argument:forInterrupt:`
already used.

**Finding 43 — closed.** All four divergences in `identifyChip`'s ladder are
fixed: rung 3's `t == 0x40` returns 5 rather than 4, `t == 0x80` returns 4
immediately rather than falling into the banked-scratchpad ladder, `t == 0xC0`
runs rungs 6 and 7 rather than returning 5 with no I/O, and the 18 delays are
gone. The unused `val3` local is dropped. `outb`/`inb` are the reference's 18
and 10. Rung 7's missing MCR write is left in place as Apple's, per section 6
item 1, and is commented as such.

**Finding 44 — closed.** Seven fields in the reference's order, the `Type == 0`
guard, three zero writes and the delegation to `programChip`. The field our
source called `flowControl` is `RX_Parity` through the shared struct.

**Finding 45 — closed.** `+2` half-bits when parity is none, `+4` otherwise
(20009-20024). `nsPerChar`, `FrameInterval` and the derived trigger level are no
longer corrupted.

**Finding 46 — closed.** The clamp is the reference's if/else, so the 100 floor
is skipped whenever the `MaxBaud` clamp fired (19892 `jnb` → 19920). The
invented `chipType < 9` guard is gone; the reference range-checks `Type`
nowhere.

**Finding 47 — closed.** The trigger loop lost its `&& triggerLevel > 0` guard
and can run negative as 20360-20377 and 20496-20513 do, which makes the type-7
`triggerLevel < 0 && BaudRate <= 0x4AFF` arm live rather than dead code.

**Finding 48 — closed.** Type 3 no longer shares type 4's arm. Types 0, 1, 2, 3
and 8 fall to the default, which clears `FCRimage` and issues **no** `outb`, and
the three separate FCR writes collapsed onto the reference's single shared write
at 20614 — the default arm skips it by the same jump the reference makes from
20628 to 20638. `programChip` is back to the reference's **5** `outb`s from
seven, closing the section 7 discrepancy.

**Finding 49 — closed.** `if (port->DLRimage != newDivisor) { … }` wraps the
frame-interval maths, the divisor writes and the whole FCR switch, so `FCRimage`
survives a no-op reprogram exactly as the reference's does.

**Finding 50 — matched.** The `CharLength` clamp, the four-way LCR/`RBRmask`
table, the stop-bit rule, the parity switch, the break bit from `State & 0x800`,
`DLR = MasterClock / (BaudRate << 3)` as a 32-bit unsigned divide, DLAB held
across both divisor halves, and the final `outb(Base+3, LCRimage)` followed by
`LCRimage = lcr`. The parity switch gained an explicit `case PARITY_NONE: break;`
so the jump table carries the reference's **five** entries (`dec ecx; cmp 4; ja;
jmp table[ecx*4]` at 19790-19796) rather than four. `IERmask` is untouched.

**Findings 51 and 52 — closed by relocation.** `RBRmask` is named for what it is
and its four values are commented as 5/6/7/8 data bits rather than
"31/63/127/255 bytes". `MinLatency`'s two arms are commented correctly: on types
5 and 6 it **enables** the FIFO at a 1-byte trigger (20328), and only on type 7
does it disable it.

**Finding 95 — closed for TU 2.** `FrameInterval` now comes from an ordinary
`unsigned long long` divide and modulo of the sign-extended `nsPerChar` by
`1000000000`, which is what the reference's `cdq` at 20052 plus `__udivdi3` at
20072 and `__umoddi3` at 20105 are. The explicit four-argument call sites
elsewhere are TU 1's and remain open.

### New findings from the Task 5 read

**Finding 101 — we emit four copies of `_RX_enqueueLongEvent` against the
reference's three, and a single shared header cannot produce the reference's
pattern.** Predicted before the build and confirmed by it: gcc 2.7 emits every
`static` defined in a translation unit whether or not that unit references it, so
`ISASerialPortChip.c` picked up a copy from `ISASerialPortInternal.h`. The
reference has copies in TUs 1, 3 and 4 at 0, 20684 and 23200 and **none** in
TU 2.

That asymmetry is the finding. One header included by all four units gives four
copies; the reference has three. So Apple's definition cannot have been in a
header that TU 2 includes. The likely shape is **two** headers: a shared one
carrying the `Port` and `Queue` structs and the eleven prototypes, which all four
units include, and a **queue-specific** one carrying `_RX_enqueueLongEvent`,
included by TUs 1, 3 and 4 but not by TU 2. That reading is consistent with what
the units do — TU 2 is chip programming and touches no ring buffer — and it also
explains the otherwise odd unreferenced copy at 23200, since TU 4's
`_flowMachine`/`_watchState` do not call it either but its unit would still
include the queue header.

This is a hypothesis about Apple's file layout, not a fact recovered from the
binary; what the binary establishes is only that TU 2 has no copy and the other
three do. **Task 6 owns the split**, because it changes TU 1's includes and
because the three per-TU copies are also where Finding 59's `and edx, 0FFh` fix
lands. Splitting the header should take the copy count from four to three and
remove roughly 197 bytes of `__TEXT,__text` we currently carry and the reference
does not.

**Finding 102 — Finding 94 is now load-bearing for the port-open path, not a
parity improvement.** `programChip` computes `FrameInterval` with a genuine
64-bit divide and modulo because that is what the reference does, so TU 2 now
calls `__udivdi3` and `__umoddi3` at runtime. Finding 94 established that our
hand-written helpers recurse infinitely: both promote to a 64/64 division that
gcc lowers to a call to the helper itself, and the recursive call re-enters on
the same branch. `programChip` is reached from `initFromDeviceDescription:`,
`acquire:`, `release` and `_executeEvent`, so **until Task 6 rewrites those two
helpers with 32-bit division only, opening a port overflows the kernel stack.**
TU 1 already called them from five sites, so this is not a new defect class, but
it is no longer avoidable by not exercising those paths.

### Still open in TU 2

**`identifyChip`'s byte size against the reference's 684 is unverified.** Our
build is unstripped and its debug stabs share addresses with real functions, so
symbol-gap arithmetic returns nonsense — it reports 7 bytes for `identifyChip`.
A capstone-based measurement is needed and has been referred to review. The
structural evidence against overfit, recorded here so the size check has
something to be checked against: 18 `outb` and 10 `inb`, matching the reference
exactly; no call instruction; nine return sites at the reference's nine values;
the rung-3 dispatch written as the same three-case comparison tree the reference
builds; and the two locals typed as the reference's spill pattern shows them
(`unsigned int` for the FIFO probes, `unsigned char` for the MCR bit, which gcc
keeps in memory at both 19114 and 19345).

**Findings 18 and 19 stay open, and they are TU 1's.** The four timeout handlers
and `getHandler:level:argument:forInterrupt:` must dispatch through
`Chip[Type].IntHandler`. The table they need now exists and carries the right
function pointers, so this is a small change, but it is in TU 1. Only what the
table's arrival forced was touched there: the `strcmp` loop, the banner's two
fields, the three `FIFOsize` reads, the three `msr_state_lut` reads and
`_activatePort`'s `Type > 4`.

**The banner's remaining divergence stays open.** It now prints
`Chip[Type].LongName` and `Chip[Type].FIFOsize`, which are the reference's
fields, but the `" (PCMCIA)"` suffix against the reference's `"PCMCIA/"` prefix
(Finding 87) is untouched and TU 1's.

The three entries are `control-flow-confirmed` rather than `assembly-matched` for
the same reason TU 3's six are: every reference instruction was read and our
source matches it branch for branch and constant for constant, but **our rebuilt
object has not been disassembled and compared**, and `ledger.json`'s
`rebuilt_sha256` is still `null`.

### A note on the relined records

`source-map.json` was regenerated and relined. The fresh run reports 28 mapped
and 17 unmapped against the committed 43 and 2, for the reason Addendum 2 gave:
`source_sites` keys sites by compiled symbol name and globs only `*.m` and `*.c`,
so the fifteen still-underscored functions and the three header-static
`_RX_enqueueLongEvent` copies cannot auto-match. **`fresh-only` is empty and the
partition is unchanged** — 43 mapped, 2 unmapped, no duplicates, no boundary
disputes, and `load_source_map` passes. Only line numbers moved. Note the
committed map had also drifted 8 lines on `ISASerialPortFlow.c`, from the
`ioPorts.h` import Addendum 3 added after it was written; that is corrected too.
The same relining was applied to `ledger.json`'s 34 stale `source_line` values so
the two artifacts continue to agree.

## Addendum 4: Findings 94 and 102 are wrong, and the real 64-bit-division picture

Both findings claimed a runtime catastrophe that does not exist. Finding 94 said our
`__udivdi3` recurses infinitely; Finding 102 said that makes opening a port overflow the
kernel stack. **Neither is true.** The mechanism was misread, and the corrected picture
changes what Task 6 should do.

**What is actually in our binary.** Four symbols, not two:

```
__udivdi3     external, section=None          <- undefined; what the compiler calls
__umoddi3     external, section=None          <- undefined; what the compiler calls
___udivdi3    external, __TEXT,__text         <- our definition, wrong name
___umoddi3    external, __TEXT,__text         <- our definition, wrong name
```

Our source names these functions `__udivdi3` in C, so the compiler emits `___udivdi3`. But a
compiler-lowered 64-bit divide relocates against the **ABI** symbol `__udivdi3`, which is a
different symbol and is undefined in our object. So our definitions are **never called**, and
the four calls inside them (at 9425, 9523, 9751, 9785) target the undefined externals rather
than themselves. There is no recursion.

**The driver nevertheless loads.** The i386 kernel exports both:

```
00218bac T __udivdi3
00218be0 T __umoddi3
```

so the undefined externals resolve at load time. The reviewer's concern that this might be a
load failure is answered: it is not.

**So our two definitions are dead code under the wrong name**, while the reference defines
both **locally** at 23800 and 24064 — 264 and 348 bytes — because Apple's link pulled them
from libgcc. Ours come from the kernel instead.

**What Task 6 should do, and what it should not.** The plan's original instruction was to
rewrite the helpers with 32-bit division only. That would **not** fix anything, because the
problem is the symbol name, not the arithmetic. The correct change is the rename that is
already on Task 6's list, understood properly: renaming the C functions to `_udivdi3` and
`_umoddi3` makes the compiler emit `__udivdi3`/`__umoddi3`, which turns them into the
definitions the lowered divides actually call — matching the reference's local definitions and
making our object self-contained rather than dependent on a kernel export.

That is worth doing on parity grounds: it should close roughly 612 bytes of the
`__TEXT,__text` gap, since the reference's two bodies total 612 bytes and ours currently
contribute dead weight under names nothing references.

Spec §2.8's reasoning still stands — the helpers stay rather than being removed, because
`/usr/lib/libcc.a` on the guest is a PPC archive that cannot load for `-arch i386`. What
changes is only the understanding of *why* they matter and what the fix is.

**Two smaller corrections to Finding 102's text.** Its caller list should read `_activatePort`,
`acquire:`, `release`, `_executeEvent` and `_initChip` — not `initFromDeviceDescription:`. And
Task 5's report says the reference's `identifyChip` is 180 instructions where capstone counts
**192**, and lists ten values under a heading of "nine return sites".

**Measured function sizes, for the record**, since Task 5 left them unverified and symbol-gap
arithmetic is useless on our unstripped build: `identifyChip` **656** against the reference's
684, `initChip` **148** against 148 — exact — and `programChip` **1077** against 1148. All at
or below the reference, so the overfit guard passes.


## Addendum 5: Task 6a outcome — the class layout is exact, and where the two section regressions come from

Task 6 was split; 6a landed the eight coupled structural changes and Step 4's protocol
conformance. `make exit=0`, zero errors, and the inline assembly the report flagged as the
main build risk compiled without complaint.

**Six sections now match the reference exactly that did not before**, and the class layout is
byte-identical:

| | before 6a | after 6a | reference |
| --- | --- | --- | --- |
| `instance_size` | 572 | **604** | 604 |
| ivar 0 / ivar 1 offset | 264 / 568 | **296 / 600** | 296 / 600 |
| `__OBJC,__meth_var_types` | 1217 | **1214** | 1214 |
| `__OBJC,__cat_inst_meth` | 0 | **100** | 100 |
| `__OBJC,__cat_cls_meth` | 0 | **12** | 12 |
| `__OBJC,__protocol` | 0 | **20** | 20 |
| `__OBJC,__class_names` | 126 | **153** | 153 |
| `_RX_enqueueLongEvent` copies | 4 | **3** | 3 |
| `missing_symbols` | 13 | **0** | — |
| `missing_strings` | 21 | **3** | — |
| sections matching | 20/30 | **25/30** | — |

`__OBJC,__instance_vars` held at 28 and `__inst_meth` at 200 through the change.

### Resolution, one line per structural change

1. **Finding 96 — closed.** `@interface ISASerialPort : IODirectDevice <PortDevices>`.
   `IODirectDevice`'s six ivars plus its reserved `int[2]` are the 32 bytes, and
   `instance_size` and both ivar offsets are now the reference's exactly. The 161 raw
   `self+offset` accesses needed no arithmetic change because they were always the
   *reference's* offsets; all 141 that survive were checked mechanically to land on the start
   of a real `Port` field, 61 distinct offsets with nothing out of range and nothing
   mid-field. The two that had been writing past the end of the old 572-byte object are now
   `self->port = &self->Port;` and `self->Port.Self = self;`.

2. **The twelve `unsigned long` fields — closed, and the count includes `FlowControl`.**
   `State`, `WatchStateMask`, `BaudRate`, `MasterClock`, `SWspecial[8]`, `FlowControl` and the
   six `Stats` members. Zero codegen change on i386; ivar 0's type encoding is now
   byte-identical.

3. **The fifteen renames — closed.** Ten TU 1 statics, the `RX_enqueueLongEvent` definition
   and the two division helpers each lost one leading underscore. Twelve of the fifteen now
   auto-match in `binrecon source-map`, which took the fresh run from 28 mapped to 40; see
   the note on the map below for the three that still cannot.

4. **The division helpers — closed, and the fix is larger than a rename.** Section below.

5. **Finding 101 — closed.** The queue header split: `ISASerialPortQueue.h` carries the
   `static void RX_enqueueLongEvent(...)`, included by `ISASerialPort.m`,
   `ISASerialPortQueue.c` and `ISASerialPortFlow.c` and **not** by `ISASerialPortChip.c`.
   Four copies became three, the reference's TU-1/3/4-but-not-2 pattern, and TU 4's copy is
   still unreferenced exactly as the reference's at 23200 is.

6. **Finding 97's leftover — closed.** `TX_STATE_BELOW_LOW` is deleted from the header and its
   two uses are `TX_STATE_BELOW_MED`. The whole five-way ladder was re-read at both sites
   (`_activatePort` 3482-3610 and `enqueueData:` 8674-8796) rather than trusting the
   constant's name: empty `0x06000000`, below-med `0x02000000`, below-high `0`, above-high
   `0x01000000`, critical `0x01800000`. `0x04000000` now appears nowhere in the source either.

7. **Finding 59 — closed.** `RX_enqueueLongEvent` is `void` and takes `unsigned char event`.
   The rebuilt body carries the `and reg, 0FFh` the reference has at 90. None of the eighteen
   call sites needed touching.

8. **The nine config keys — closed.** Section below.

### The division helpers: the rename alone would have created the bug Findings 94 and 102 imagined

Addendum 4's diagnosis was right — the problem was the symbol name — but its prescription was
incomplete, and taken literally it would have been actively harmful.

Our old bodies were written with ordinary `unsigned long long` division: three such
expressions in `__udivdi3`, two in `__umoddi3`. gcc lowers each of those into a call to
`__udivdi3`/`__umoddi3`. While our definitions were misnamed `___udivdi3`/`___umoddi3` those
calls went out to the kernel's export, which is why nothing recursed. **Rename the functions
and the same calls become self-recursive**, and the fast path recurses on arguments identical
to its own — genuinely unbounded. Findings 94 and 102 described a real hazard; they simply
attributed it to the wrong build.

So the bodies had to lose their 64-bit division, and the reference tells us what they should
be instead: `__udivdi3` and `__umoddi3` contain **no call instructions at all**, and five
`div`, one `mul` and one `bsr` each. That is `libgcc2.c`'s `__udivmoddi4`, which is
`static inline` when compiled for `L_udivdi3` or `L_umoddi3` and so collapses into exactly one
call-free function per helper. Both `libgcc2.c` and `longlong.h` are in this tree under
`src/cc-1/cc`, so the bodies were reconstructed from them rather than invented:
`udiv_qrnnd` → `divl`, `umul_ppmm` → `mull`, `count_leading_zeros` → `bsrl`,
`sub_ddmmss` → `subl`/`sbbl`. `UDIV_NEEDS_NORMALIZATION` is undefined on i386, so the
non-normalising arm is live, which is what makes the count five `divl` including the
deliberate `1 / d0`.

**Verified against the rebuilt object, not just argued.** Both reference streams were read in
full and compared instruction by instruction with ours:

- `__udivdi3`: 105 reference instructions, **branch sequence identical** — fourteen
  conditional branches in the same order with the same predicates — and the mnemonic multiset
  differs by a single `mov` the reference spills. **260 bytes against 264.**
- `__umoddi3`: 135 reference instructions. Two differences, both gcc layout rather than
  source: the reference tests `d1 > n1` and branches to the remainder-is-the-dividend arm
  where ours tests `d1 <= n1` and falls through to it, inverting one branch and adding one
  `jmp`; and the reference spills `n1` to a stack slot where ours keeps it in `ebx`, which
  accounts for eight `mov`s. **328 bytes against 348.**

The rebuilt object now defines both symbols locally as the reference does and carries **no
undefined `__udivdi3`**, so it no longer depends on the kernel export at `0x00218bac`. Both
ledger entries are `control-flow-confirmed`.

Spec §2.8's reasoning is unchanged: the helpers stay because `/usr/lib/libcc.a` is a PowerPC
archive that cannot link for `-arch i386`. What changed is that they are now reachable.

### The nine config keys, and the inversion that was waiting in two of them

The mechanism was wrong before the names were. The reference reads every key from
`[deviceDescription configTable]`, not from the device description, and logs
`ISASerialPort: Invalid Config Table` and bails when there is none. Reconstructed from the 585
instructions at address 264 plus the whole of `__TEXT,__cstring`, which turns out to be one
contiguous run of this function's literals in source order.

| Key | Feeds | Was |
| --- | --- | --- |
| `Instance` | `Port.Instance`, and `sprintf("ISASerialPort%d")` → `setName:` → `Port.PortName` | `PortNum`, with a NULL guard and log the reference does not have |
| `Chip Type` | `Port.Type`, matched against `Chip[i].ShortName`; row 0 ("Auto") matches but is ignored | `ChipType`, with two invented log strings |
| `Bus Type` | `Port.PCMCIA`, when `strncmp("PCMCIA", v, 7) == 0` | `PortType` |
| `TX Buffer Size` | `Port.TX.DefaultSize`, as `validateRingBufferSize(n * 2, &Port.TX)` | **`RXBufSize`** |
| `RX Buffer Size` | `Port.RX.DefaultSize`, as `validateRingBufferSize(n * 2, &Port.RX)` | **`TXBufSize`** |
| `Chip Clock` | `Port.MasterClock`; ≤ 999 falls back to 1843200 | `ClockRate` |
| `Heart Beat Interval` | `Port.HeartBeatInterval`, µs → ns, default 11000, clamped to 0x418937 | `HeartBeat`, written to **`CharLatInterval`** |
| `Enable MSR Interrupts` | `Port.IERmask`: present → 0xFF, absent → 0xFB | not read; `numFlagStrings` stood in |
| `Serial` | **not a key** — the `setDeviceKind:` argument | `"SerialPort"` |

**The two buffer keys were crossed, and this is exactly the failure the task was warned
about.** Our `RXBufSize` wrote `self+0x1a4`, which is `TX.DefaultSize`, validated against
`&Port.TX`; our `TXBufSize` wrote `self+0x16c` = `RX.DefaultSize` against `&Port.RX`. Each
site was internally consistent, so a naive rename of `RXBufSize` → `RX Buffer Size` would have
carried the crossing forward and quietly applied one direction's default to the other. The
reference's `TX Buffer Size` is the key that writes `0x1a4`, so the fix is to swap which key
reads which; the field and the queue argument were already right. Both also gained the `* 2`
our source had dropped — the keys are in characters and the queues count 2-byte cells.

**`Heart Beat Interval` was writing the wrong field entirely.** Ours stored the nanosecond
value into `self+0x230`/`0x234`, which is `CharLatInterval`, and filled `HeartBeatInterval`
from `__udivdi3(0, 0, 0, 0)`. The reference zeroes `0x230`/`0x234` in the init block and never
touches them here; it clamps the µs value to `0x418937` — 4294967, the largest whose `* 1000`
survives 32 bits — and splits the product into `HeartBeatInterval.tv_sec`/`.tv_nsec`.

`Enable MSR Interrupts`'s polarity happened to match what the `numFlagStrings` code did, so
nothing needed inverting there; only the source of the flag and the log string were wrong.

`Serial` is the trap in the other direction: it sits in the cstring list beside the keys and
looks like one, and it is the `setDeviceKind:` argument. The shipped `Default.table`
corroborates the whole set — it supplies `"Instance" = "0"`, `"Bus Type" = "EISA"` and
`"Family" = "Serial"` and none of the other seven keys, so every key the driver reads is now
either supplied or correctly defaulted.

### Three corrections to the Task 6a brief, accepted by the controller

1. **The twelve `unsigned long` fields include `FlowControl`.** The brief's list named
   `State`, `WatchStateMask`, `BaudRate`, `MasterClock`, the `SWspecial[]` array and the six
   `Stats` members, which is eleven. The reference's ivar-0 encoding spells `"FlowControl"L`.
2. **`Serial` is not a config key**, it is `setDeviceKind:"Serial"`.
3. **"Keep the bodies" could not be taken literally for the division helpers**, for the reason
   above. The controller has recorded the departure as correct.

### Where the two section regressions come from

**`__TEXT,__cstring` 716 → 799 against 742, and it decomposes exactly.** Four extra strings
and three missing ones, and their byte counts close the gap to the byte:

| | bytes | disposition |
| --- | --- | --- |
| extra `%s: Invalid port configuration\n` | 32 | pairs with the missing `%s: Invalid configuration\n` |
| extra `%s: superclass initFromDeviceDescription failed\n` | 49 | the reference logs nothing here |
| extra `" (PCMCIA)"` | 10 | Finding 87, pairs with the missing `"PCMCIA/"` |
| extra `%s: Failed to register interrupt\n` | 34 | pairs with the missing `%s: Unable to enable interrupts\n` |
| missing `%s: Invalid configuration\n` | 27 | |
| missing `%s: Unable to enable interrupts\n` | 33 | |
| missing `"PCMCIA/"` | 8 | |

125 extra less 68 missing is **+57**, which is precisely 799 − 742. **None of it comes from the
config-key work** — every key name and every key log string 6a added is present in the
reference. All four extras belong to the four TU 1 divergences 6a deliberately left open, and
closing them lands the section on 742 exactly. The section rose because the reference's own
strings are long: `%s: Ignoring invalid Chip Type "%s" from Instance table\n` alone is 57
bytes, and 6a removed 17 wrong strings while adding 18 right ones.

**`__TEXT,__text` 23516 → 22164 against 24412.** The gap is now −2248 and it is almost entirely
TU 1's. Measured per function with capstone against the nlist, filtering the debug stabs that
make symbol-gap arithmetic useless on our unstripped build:

| unit | reference | ours | delta |
| --- | --- | --- | --- |
| TU 1, the class | 18704 | 16768 | **−1936** |
| TU 3, the ring buffer | 2516 | 2360 | −156 |
| TU 2, the chip | 1980 | 1884 | −96 |
| TU 4, the flow machine | 576 | 540 | −36 |
| the two division helpers | 612 | 588 | −24 |
| build-generated | 24 | 24 | 0 |

Within TU 1 the four largest bodies carry **−2092** between them — `_executeEvent` −1236,
`_FIFOIntHandler` −404, `_NonFIFOIntHandler` −232, `initFromDeviceDescription:` −220 — while
the remaining twenty-seven TU 1 functions net **+156**, several of them over the reference
(`dequeueData:` +80, `_heartBeatTOHandler` +92, `enqueueData:` +44, `_activatePort` +36).
So the whole gap lives in the four bodies whose call sites are still commented out, and all
four are among the twenty-five entries still `unexamined`.

**Why the gap widened rather than narrowed, and why that is not a regression.** The movement is
−1352 and it cannot be decomposed per function, because the pre-6a `_reloc` was overwritten by
this build and `out/` is not tracked. What can be said:

- The old `___udivdi3`/`___umoddi3` were **dead code under names nothing referenced**, written
  entirely in 64-bit expressions that gcc 2.7 spills heavily on i386. They inflated the byte
  count towards the reference for the wrong reason. They are gone, replaced by 588 bytes that
  are actually called and within 24 bytes of the reference's 612.
- Dropping the fourth `RX_enqueueLongEvent` copy is **−140** exactly, our per-copy size.
- Everything else in 6a is either zero-codegen on i386 (the superclass, the field widths, the
  method-signature widening, the renames) or close to size-neutral.

Subtracting the −140 leaves ≈1212 for the helper replacement, implying the old pair weighed
≈1800 bytes against the 588 that replaced it. That figure is **inferred by subtraction, not
measured**, and is recorded as such. The direction is the same one Task 4 saw when it deleted
invented `IODelay` calls: section size moved away from parity while structural correctness
moved decisively towards it.

**A real TU 3/TU 4 residual worth knowing.** Our `RX_enqueueLongEvent` is 140 bytes against the
reference's 197, −57 per copy and −171 across the three, and reading all 69 reference
instructions shows why: the reference re-reads `RX.Input` from memory before each of the four
stores and writes the advance back with `add dword ptr [x+0x38], 2`, where our compiler keeps
the pointer in a register; and the reference emits a separate advance-and-wrap block for the
overflow marker where ours tail-merges it into the last cell, so the rebuilt stream has seven
branches where the reference has eight. Every constant and every `Queue` field offset matches.
This is the optimisation-level ceiling section 9 of this document already describes, not a
source divergence, and it is not worth chasing.

### The source map, and why three entries are still relined by hand

The renames did what Addendum 2 predicted: the fresh `binrecon source-map` run went from 28
mapped to **40**, and `fresh-only` is empty. The partition is unchanged at **43 mapped, 2
unmapped** and `load_source_map` passes.

The two permanently unmapped are the build-generated
`+[ISASerialPortKernelServerInstance kernelServerInstance]` and
`+[ISASerialPortVersion driverKitVersionForISASerialPort]`, which have no source in this tree.

The three `RX_enqueueLongEvent` copies are still carried by hand, but **not for a naming
reason any more** — `source_map.source_sites` globs only `*.m` and `*.c`
(`tools/binrecon/binrecon/source_map.py:84`), so a `static` defined in a header is structurally
invisible to the generator. They now point at `ISASerialPortQueue.h:53` instead of
`ISASerialPortInternal.h:267`. Addendum 2's expectation that the rename would make the
workaround unnecessary was half right: it removed twelve of the fifteen, and the remaining
three need the generator to glob headers.

### Ledger state after 6a

45 entries: 2 `assembly-matched`, **14** `control-flow-confirmed`, 2 `signature-confirmed`,
2 `intentional-mismatch`, **25 `unexamined`**. The five that advanced are the three
`RX_enqueueLongEvent` copies and the two division helpers, each on a full instruction-by-
instruction read of the reference against the rebuilt stream. Nothing reached
`assembly-matched`: the streams are isomorphic but not identical, differing in register
allocation, spill slots and block ordering, and `ledger.json`'s `rebuilt_sha256` is still
`null`.

The 25 remaining are TU 1 bodies and they are 6b's, together with essentially the whole
`__TEXT,__text` gap and all four extra cstrings. `__TEXT,__const` is still absent against the
reference's 682 and stays recorded rather than chased.

## Addendum 6 — Task 6a review corrections

The Task 6a review returned READY TO MERGE: NO on one Critical, plus corrections to
Addendum 5's own claims. All are recorded here rather than by editing Addendum 5, so the
record shows what was believed and when.

### C1 (resolved) — the two `assembly-matched` entries were overstated

`-[ISASerialPort release]` @5448 and `-[ISASerialPort nextEvent]` @6400 carried
`assembly-matched`. The spec defines that status as *the rebuilt instruction stream was read
against the reference*. That was never done: `rebuilt_sha256` is `null`, and the reason
`"full disassembly read instruction by instruction"` described reading the **reference**, not
a rebuilt-vs-reference diff. The streams are in fact not identical:

- `nextEvent` — reference 70 bytes / 26 instructions; ours 80. Ours emits `sub esp,4` plus a
  `[ebp-4]` staging slot with `mov byte ptr [ebp-4],0`, addresses the fields directly
  (`[ebx+0x164]`, `[ebx+0x15c]`, `[ebx+0x140]`) where the reference works off a single
  `lea eax,[ebx+140h]` base, and inverts the sense of the first branch (ours `je`, reference
  `jnz`). The entry's own text claimed it *"Reproduces the reference instruction for
  instruction."* It does not.
- `release` — reference 561 bytes, ours 544. Not byte-identical.

Both were pre-6a, but `421e2987` relined both and left the status standing.
`binrecon.ledger.transition` forbids backward moves (`ledger.py:269`), so both `status` fields
were hand-edited down to `control-flow-confirmed`, the overstated reason text was replaced
with the measured deltas above, `reasons` was re-sorted under `canonical_key` to preserve the
sorted+deduped invariant, and `binrecon ledger` was re-run: **entries=45,
control-flow-confirmed=16, intentional-mismatch=2, signature-confirmed=2, unexamined=25,
assembly-matched=0.**

Nothing in this reconstruction is `assembly-matched`, and nothing should claim to be until
somebody diffs a rebuilt stream.

### Authoritative self-relative offset table

The review found the effort's #1 known-bad pattern recurring inside the function 6a rewrote:
inline comments beside raw offsets that assert exactly the TX/RX crossing 6a spent the pass
fixing. Computed from `ISASerialPortInternal.h` with `Port` embedded at 296 — this table is
derived from the struct, not from any comment, and supersedes every offset comment in
`ISASerialPort.m`:

| offset | field | a comment in ISASerialPort.m calls it |
|---|---|---|
| 0x134 | `Port.State` | currentState (near enough) |
| 0x140 | `Port.RX.Size` | txQueueCapacity — **wrong** |
| 0x16c | `Port.RX.DefaultSize` | txQueueCapacity default — **wrong** |
| 0x178 | `Port.TX.Size` | RX queue size — **wrong** |
| 0x1a4 | `Port.TX.DefaultSize` | rxQueueCapacity default — **wrong** |
| 0x1c4 | `Port.TX_Parity` | flowControl — **wrong** |
| 0x1cc | `Port.BreakLength` | stopBits — **wrong** |
| 0x208 | `Port.FlowControl` | stateEventMask — **wrong** |
| 0x228 | `Port.DataLatInterval` | charTimeOverride — **wrong** |
| 0x230 | `Port.CharLatInterval` | heartBeatInterval — **wrong** |
| 0x238 | `Port.HeartBeatInterval` | (unlabelled) |

### Two of these are suspected live crossings, not comment noise — Task 6b must resolve them

1. **`ISASerialPort.m:3507-3538`.** The `event == 0x0F` arm is commented `offset 0x140` but
   operates on `Port.TX`; the `event == 0x0B` arm is commented `offset 0x178` but operates on
   `Port.RX`. 0x140 is `RX.Size` and 0x178 is `TX.Size`, so **the comments' offsets say the
   opposite of the code.** One of the two is wrong and the reference decides which. The
   comments in this block are visibly speculative leftovers from the original decompilation
   ("in wrong place?", "Actually this seems to be", "appears to be") and must not be trusted.
2. **`ISASerialPort.m:3556-3560`.** Stores the heartbeat pair to 0x230/0x234, which is
   `CharLatInterval`. `HeartBeatInterval` is 0x238/0x23c. Note the comment there already
   doubts itself ("These seem to be different from heartBeatInterval"). The corresponding
   store in `initFromDeviceDescription:` was verified against the reference as correct
   (`[edi+238h]`/`[edi+23Ch]`); this second site was not, and is a different function.

### Corrections to Addendum 5

- **"twenty-seven TU 1 functions" should read twenty-four.** TU 1 has 28 functions; 28 − 4 = 24.
  The +156 remainder and every individual delta are correct — the review reproduced all 28.
- **The `" (PCMCIA)"` / `"PCMCIA/"` banner divergence is Finding 84, not Finding 87.**
  Finding 87 is `getCharValues:`. The mis-citation entered in Addendum 4 and Addendum 5
  repeated it.
- **`initFromDeviceDescription:` reference size.** The −220 delta uses span 2276; the analysis
  and ledger carry function size 2273. Both now coexist in the records; the delta is quoted
  against the span.
- **`__udivdi3` "fourteen conditional branches"** is fourteen *branch instructions* — 10
  conditional plus 4 `jmp`.
- **The `__umoddi3` spill description is one-sided.** The reference spills `n1` to
  `[ebp+var_20]` while ours keeps it in `ebx`; ours symmetrically spills `d1` to `[ebp-0x24]`
  while the reference keeps it in `ebx`. Net is the stated +8 `mov`s for the reference.
- **The ≈1800-byte inference rests on a weaker premise than its label admits.** Addendum 5
  correctly labels the figure inferred rather than measured, but the inference also assumes
  everything else in 6a was size-neutral — and 6a rewrote `initFromDeviceDescription:`
  substantially (config-table mechanism, nine keys, seven new log strings, the heartbeat
  split). That premise has no measurement behind it. The figure should be read as an
  order-of-magnitude estimate only.

## Addendum 7 — Task 6b: the twenty-five TU 1 findings

Task 6b worked the `unexamined` remainder against the layout Task 6a fixed. One source file
changed, `ISASerialPort.m`. Both suspected crossings were resolved against the disassembly
rather than against the comments, the three items the 6a review reclassified as faults were
fixed, and the section table moved from 25/30 to 28/30.

### Sections after 6b

| section | before 6b | after 6b | reference | |
| --- | --- | --- | --- | --- |
| `__TEXT,__cstring` | 799 | **742** | 742 | byte-identical |
| `__OBJC,__meth_var_names` | 602 | **632** | 632 | |
| `__OBJC,__message_refs` | 68 | **76** | 76 | |
| `__TEXT,__text` | 22164 | **23080** | 24412 | −1332 |
| `__TEXT,__const` | absent | absent | 682 | see below |

All figures in this addendum are measured against the build of commit `57e57119`, **not**
against the first 6b build. The distinction matters: `57e57119`'s own EISA-typing change shrank
`initFromDeviceDescription:` by 8 bytes, so the numbers first written here — 23088 text and
−157 on init — described a binary that the same commit had already superseded. They have been
re-derived and corrected.

`missing_strings`, `missing_symbols` and `extra_strings` are all **0**. Thirteen sections are
byte-identical; every `__OBJC` section now matches by size. The two that remain are `__text`
and `__const`.

### `__TEXT,__const` is explained, and it is not a jump table

The 682 bytes decompose exactly, read out of the reference's own symbol table and bytes:

| symbol | binding | address | bytes | what it is |
| --- | --- | --- | --- | --- |
| `_ISASerialPort_VERS_STRING` | global | 25154 | 160 | `@(#)PROGRAM:ISASerialPort  PROJECT:drvISASerialPort-10  DEVELOPER:root  BUILT:Sat Mar 28 22:12:49 PST 1998\n` in a 160-byte array |
| `_ISASerialPort_VERS_NUM` | global | 25314 | 10 | `"10"` |
| `___clz_tab` | local | 25324 | 256 | libgcc's leading-zero table |
| `___clz_tab_0` | local | 25580 | 256 | a second copy of the same table |

160 + 10 + 256 + 256 = 682, to the byte.

**Neither part is driver source.** The version pair is emitted by the project's build system
into a generated `*_vers.c` and embeds a 1998 build date and the account name that ran the
build; it cannot be reproduced and is recorded, not chased. The two `__clz_tab` copies are
**dead data**: `longlong.h` declares the table for the portable `count_leading_zeros`, and
libgcc2.c defines it whenever `L_udivdi3` or `L_umoddi3` is compiled — but on i386
`count_leading_zeros` expands to `bsrl`, and the reference's helpers do exactly that
(`bsr edx, edi` at 23912 and `bsr edx, ebx` at 24161). Nothing in the reference reads either
table. They are there because the reference built the two helpers as two separate libgcc
translation units, each of which emitted its own local copy; our reconstruction defines both
helpers in `ISASerialPort.m`, so no copy is emitted at all.

Reproducing 512 bytes of provably unread data, and a banner containing someone else's build
timestamp, would be moving a size number and nothing else. **`__TEXT,__const` is recorded as a
permanent, understood absence.**

One qualification on "cannot be reproduced": that is true of the banner's *content*, not of the
section's *existence*. `VERS_STRING` and `VERS_NUM` are 170 of the 682 bytes, and they are
emitted by the build system into a generated `*_vers.c`. If this project's `pb_makefiles`
carried the `vers_string` rule, `__TEXT,__const` would appear at 170 bytes with different text
rather than being absent altogether. That is a build-system question, not a driver-source one,
and it is left open rather than answered here.

### The `lock incl` lead was wrong, and the correction is measured

Task 6b's interim report suggested the reference's `lock incl` after every `out` was a
statistics counter our source omitted, and estimated it at several hundred bytes. That was
wrong on both counts.

`_xxx.86`, `_xxx.89` and `_xxx.92` are three per translation unit, twelve in all, and they are
the whole of `__DATA,__bss` — 48 bytes, and our `__bss` is byte-identical to the reference's.
They are the static operands of the `asm volatile` in `driverkit/i386/ioPorts.h:101`, where
`outb` expands to `outb %2,%1; lock; incl %0`. The count follows `out`, not `in`: the reference
has 59 `out` and 59 `lock incl`, matching one-for-one in every function (`_identifyChip` has 18
of each and 10 `in`). **Our build also has 59 `out` and 59 lock-prefixed increments**, counted
with capstone over the rebuilt `__text`. The idiom costs us nothing and explains none of the
gap. The `// Atomic increment` comments beside our `outb` calls describe what the macro already
does.

### The two live crossings, resolved

**(a) `executeEvent:data:` events 0x0F and 0x0B — a real crossing, and our code was wrong.**
The reference's event `0x0F` arm at 6921–6986 writes `[edi+140h]`, `[edi+148h]` and
`[edi+14Ch]`, which are `Port.RX.Size`, `.HighWater` and `.LowWater`; the `0x0B` arm at
7040–7089 writes `[edi+178h]`, `[edi+180h]` and `[edi+184h]`, the `Port.TX` triple. Our source
had them the other way round. The comments were right about the offsets and wrong about which
arm owned them; the code was wrong about both. Fixed.

**A second original bug found in the same block.** Both arms pass `lea edx, [edi+140h]` —
`&Port.RX` — to `validateRingBufferSize`, at 6921 for the RX arm and again at **7024 for the
TX arm**. The TX resize therefore validates the requested size against the RX queue's limits
and stores the result in `TX.Size`. This is the reference's behaviour, it is reproduced, and
the source says so at the call site.

**(b) `executeEvent:data:` event 0x4B — not a crossing.** The reference stores the split
nanosecond value to `[edi+230h]` and `[edi+234h]` at 6889 and 6898, which is
`Port.CharLatInterval`, exactly what our source already did. Only the comment, which doubted
itself, was wrong. It has been corrected.

### The three faults

1. **`registerInterrupt:` — fixed, and the driver can now initialise.** The reference's tail at
   2340–2419 is `[self enableAllInterrupts]`, and on success `[self registerDevice]`. The
   selector our source sent was implemented nowhere in the tree, so `objc_msgSend` would have
   faulted on the driver's only entry point.
2. **`getHandler:level:argument:forInterrupt:` — fixed.** `Chip[Port.Type].IntHandler`, read at
   stride 20 field +8 (2793–2809). The `Type > 4` test our source used gave `Chip[8]`, the
   82510, `FIFOIntHandler`, because that part reports `FIFOsize` 4 while its table row names
   `NonFIFOIntHandler`. The same table dispatch appears in `frameTOHandler`, `delayTOHandler`
   and `heartBeatTOHandler`, where our source had the FIFO arm **commented out entirely** — a
   FIFO part serviced no interrupt at all from those three timers.
3. **`getCharValues:forParameter:count:` — fixed.** Three chained `objc_msgSend` calls and no
   `stringValue`; the reference treats `valueForStringKey:`'s result as the string. Our version
   sent a message to a `char *`, which faults on any successful key lookup. 172 bytes against
   172.

### `initFromDeviceDescription:`, the six inherited divergences

All six are closed. The validation block is
`numPortRanges != 1 || numInterrupts != 1 || numChannels != 0` sharing one log string
(1009–1099); the four `thread_call_allocate` calls bind `frameTOHandler`, `dataLatTOHandler`,
`delayTOHandler` and `heartBeatTOHandler` with `&self->Port` (1561–1620), where our source
passed two `NULL`s; every early exit is `return [self free]`; the banner puts the `"PCMCIA/"`
prefix **before** `Chip[Type].LongName`; and the method returns super's result (`mov eax, ebx`
at 2525), not `self`.

`numPortRanges`, `numChannels` and `portRangeList` are `IOEISADeviceDescription`'s, not
`IODeviceDescription`'s. Sending them to the declared parameter type left gcc assuming an `id`
return and comparing a pointer against an integer — the same class of defect as
`registerInterrupt:`, and it was introduced by 6b's own first draft. The description is now
held in an `IOEISADeviceDescription *` local, and `portRangeList` returns `IORange *`, so the
base and size are `portRanges[0].start` and `portRanges[0].size` rather than two `unsigned int`
subscripts.

### `_executeEvent` was a different function

The reference's 2704 bytes at 10356 were read in full. It returns `IOReturn`; it guards on
`Port.State`'s sign bit and returns `0xFFFFFD33` when the port is not acquired (10384–10395);
and it does not compute a state at all — `*statePtr` arrives holding `Port.State`, `*maskPtr`
holding zero, each arm edits the bits it owns and records them in the mask, and the caller
merges the two. Substantive divergences found and fixed:

- **Three cases were missing.** `0x37`, `0x3F` and `0xF7` all reach 11636, where a non-zero
  argument is rejected and zero is accepted as a no-op.
- **`0xE9` and `0xED` were swapped.** The reference writes `XONchar` at Port+0xBD for event
  `0xED` (10704) and `XOFFchar` at Port+0xBE for event `0xE9` (10716). Neither has the
  `<= 0xFF` guard our source carried; both simply store the low byte.
- **`0x4F` was wrong.** It is a microseconds-to-`tvalspec` split into `DataLatInterval`
  (10948–11027), and is the second of the two 64-bit division pairs Finding 95 predicted, not
  a pair of 16-bit halves.
- **`0x33`, `0x3B`, `0x43`, `0xF3` and `0xE5` set their field and call `programChip`
  unconditionally.** Our source derived `LCRimage` and `DLRimage` by hand and guarded the call
  on `STATE_ACTIVE`; the reference leaves all of that to `programChip`. `0x33` also range-checks
  against `Chip[Type].MaxBaud` (11118), which our source did not do at all.
- **`0x53` drives the flow signals from outside**, masking the request against
  `~Port.FlowControl` (10811–10836) and writing the MCR unconditionally; our source treated it
  as a wholesale state assignment.
- **`0x55` and `0x59` have no range guard**, and `0x05` tests only the low byte of the
  argument.

**A third original bug, reproduced.** Case `0x1B`, the TX high watermark, stores its argument
into `[edi+20h]` — `RX.HighWater` — at 12740, and then clamps `TX.HighWater` against
`TX.Size - 3` by reading the field back rather than the value just stored. Case `0x1F`, its RX
twin, stores to the same offset at 12080 and compares against `eax`. The shape is a copy of the
RX case with the first line's substitution missed. Reproduced, and commented at the site.

The RX and TX watermark recomputations are inlined three times each in the reference (events
`0x17`, `0x1F`, `0x2F` and `0x13`, `0x1B`, `0x28`). They are `static inline` helpers in our
source. **Their first comparisons genuinely differ**: the RX arm takes the empty/below-low path
on `Count < LowWater` (`jbe` at 11282 against `cmp LowWater, Count`) while the TX arm takes it
on `Count <= LowWater` (`jb` at 11719). That asymmetry is the reference's, not a transcription
error.

`_executeEvent` is now **2800 bytes against 2704**, from −1236.

### Division call sites

Three of ours were removed. `NonFIFOIntHandler`, `FIFOIntHandler` and `dequeueData:` were
round-tripping an existing `tvalspec_t` through a `(high << 32) | low` helper and back, which
is both meaningless and the source of a `__udivdi3`/`__umoddi3` pair each. The reference passes
the struct straight to `deadline_from_interval` — verified at 9295–9301 in `dequeueData:` and
10280–10294 in `heartBeatTOHandler`. The three helper functions that existed only to perform
that round trip were deleted.

**That verification covered the interval and not the callout, and the callout was also wrong.**
Finding 90 names both halves; 6b's first pass fixed one and left the reader of Addendum 7 to
assume the site was closed. `dequeueData:` armed and cancelled `Port.DelayTOEntry`
(Port+0xF0), where the reference reads `[edx+0ECh]` — `Port.DataLatTOEntry` — at both 9327
(`thread_call_enter_delayed`) and 9374 (`thread_call_cancel`). The allocation sites decide it:
1586 binds `dataLatTOHandler` to `[esi+214h]` = Port+0xEC and 1603 binds `delayTOHandler` to
`[esi+218h]` = Port+0xF0. Across the whole reference `[+0ECh]` appears **only** in
`dequeueData:` and `[+0F0h]` **only** in `_executeEvent`'s 0x4B arm, so there is no ambiguity.
The consequence of the old code was that a read carrying a data-latency interval armed the
delay timer: `delayTOHandler` would fire instead of `dataLatTOHandler`, clearing `State` bit
0x1000 and driving the interrupt handler, and any delay timer event 0x4B had set was first
clobbered and then cancelled. **Both identifiers are now `DataLatTOEntry`**, and Finding 90's
callout half is closed. The ledger entry for `dequeueData:` stays `unexamined`: the fix is
evidenced, but the body as a whole has still not been read.

### `requestEvent:data:` — the comments were crossed the same way, the code was not

The sibling of the method 6b de-crossed carries the effort's known-bad pattern in its purest
form: **every RX/TX label in its switch is backwards, and every offset and expression is
right.** All 24 cases were checked against 7816–8004; nothing in the code changed. Corrected
labels, against Addendum 6's table:

| case | comment said | offset is |
| --- | --- | --- |
| 0x0B | RX buffer capacity | `Port.TX.Size` |
| 0x0F | TX buffer capacity | `Port.RX.Size` |
| 0x13 | RX low watermark | `Port.TX.LowWater` |
| 0x17 | TX med watermark | `Port.RX.LowWater` |
| 0x1B | RX high watermark | `Port.TX.HighWater` |
| 0x1F | TX low watermark | `Port.RX.HighWater` |
| 0x23 | RX available count | `Port.TX.Size − Port.TX.Count` |
| 0x43 | Flow control | `Port.TX_Parity` |
| 0x47 | Flow control state? | `Port.RX_Parity` |
| 0x4B | Heartbeat interval | `Port.CharLatInterval`, not `HeartBeatInterval` (0x238) |
| 0x4F | Character time override | `Port.DataLatInterval` |
| 0x53 | State event mask | `Port.FlowControl` |
| 0xF3 | Parity | `Port.StopBits` |

Case `0x27` is a **fourth original bug**, already reproduced: the reference computes
`[0x140] − [0x17C]` at 7932–7938, which is `RX.Size − TX.Count` — the RX twin of case 0x23 with
one substitution missed, the same shape as `_executeEvent`'s case `0x1B`. The comment now says
so.

### Two findings opened, deliberately not fixed

1. **`requestEvent:` cases 0x4B and 0x4F compute the wrong number.** This is arithmetic, not
   style. Ours reads the `tvalspec` pair as one little-endian `unsigned long long` — which is
   `tv_sec | (tv_nsec << 32)` — and then multiplies by 1e9 before dividing by 1000. The
   reference at 7704–7808 loads the two words separately, computes
   `(unsigned long long)tv_sec * 1000000000 + (long long)(int)tv_nsec` (`mul`, then `cdq` to
   sign-extend `tv_nsec`, then `add`/`adc`), and divides that by 1000 through `__udivdi3`.
   Finding 95 states the correct formula but frames the item as a call-site *style* question;
   nothing in the record said the result was wrong. It is. Left for the pass that takes
   `requestEvent:data:` as a whole.
2. **Finding 10 is half wrong and would break code if applied literally.** It says
   `STATE_RX_ENABLED` should be `0x00400000` rather than `0x00080000`. `0x00080000` is
   *correct* where it is used — as the `watchState` mask, which the reference pushes as
   `80000h` at 21443 and 22292 (against `800000h` at 20937). `0x00400000` is a **different**
   bit: the handler-internal RX gate, tested as `test byte ptr [ebp+var_C+2], 40h` at 13237,
   16340 and 16449. **Two constants are needed, not one substitution.** A future pass following
   Finding 10 as written would change `ISASerialPortQueue.c:375` and `:555` and break them.

### A known non-literal equivalence, left alone

`executeEvent:data:`'s 0x53 arm builds the MCR byte from `flowState` where the reference builds
it from `newState` (6718 and 6728). These are the same value in the bits that matter:
`newState = (oldState & 0xFFFFFFE9) | (flowState & 0x16)`, and the mask clears exactly 0x02 and
0x04, so both bits can only have come from `flowState`. Recorded so a later reader does not
mistake it for a divergence.

### What is left, measured per function

Per-function sizes were taken from the rebuilt object with capstone against the `nlist`,
filtering the debug stabs; our figures are symbol-gap derived and so include up to three bytes
of inter-function alignment, which is why several exact matches read `+1` to `+3`.

| function | reference | ours | delta |
| --- | --- | --- | --- |
| `_FIFOIntHandler` | 3172 | 2652 | **−520** |
| `_NonFIFOIntHandler` | 2472 | 2128 | **−344** |
| `initFromDeviceDescription:` | 2273 | 2108 | −165 |
| `_RX_dequeueEvent` | 852 | 780 | −72 |
| `_programChip` | 1148 | 1080 | −68 |
| `acquire:` | 944 | 880 | −64 |
| `_RX_enqueueLongEvent` ×3 | 197 | 140 | −57 each |
| `setState:mask:` | 267 | 232 | −35 |
| `_identifyChip` | 684 | 656 | −28 |
| … | | | |
| `_executeEvent` | 2704 | 2800 | **+96** |
| `enqueueData:` | 696 | 740 | +44 |
| `_activatePort` | 1144 | 1180 | +36 |
| `_deactivatePort` | 345 | 380 | +35 |
| `requestEvent:data:` | 746 | 768 | +22 |

**The accounting closes exactly.** The per-function deltas sum to **−1279**, not to the
section's −1332, and the 53-byte difference is not a remainder — it is the reference's own
inter-function padding. Our sizes are symbol-gap derived and therefore tile the section, so
they already contain our padding; IDA's reference sizes are function extents and exclude the
reference's, whose 45 functions total 24359 against a 24412-byte section. So

    −1279  (per-function, ours gap-derived against IDA extents)
    −   53  (reference padding IDA does not count: 24412 − 24359)
    = −1332  (the section delta)

Our build also spends its padding differently — 49 alignment `nop`s inside `_NonFIFOIntHandler`
alone, against the reference's 2 — which is why several functions that are otherwise exact read
`+1` to `+3`.

### The two interrupt handlers: deliberately not fixed, with the reason

`_FIFOIntHandler` and `_NonFIFOIntHandler` carry −864 of the remaining −1332 and are left at
`signature-confirmed`. The signature is verified — `void (void *identity, void *state,
Port *port)`, the `Port *` arriving as `arg_8` and matching the three-argument indirect call the
timeout handlers make through `Chip[Type].IntHandler`. **The bodies were not verified**, and the
ledger says so.

What the partial comparison did establish, and what a later task should start from:

- The mnemonic histograms differ mainly in `lea` (−18 and −24), `mov` (−43 and −75) and `call`
  (+7 and +9). We make *more* calls and far fewer address computations.
- The call-target sets are otherwise identical — `PCMCIA_yanked`, `executeEvent`,
  `deadline_from_interval`, `thread_call_cancel`, `thread_call_enter_delayed`,
  `thread_wakeup_prim`, and for the FIFO handler `NonFIFOIntHandler` — with exactly one
  difference: **the reference never calls `RX_enqueueLongEvent` from either handler.**
- It writes the enqueue out inline instead. At 18568–18664 the state-change event is three
  cells — the `0x53` marker, the low half and the high half — each followed by its own
  advance-and-wrap and `Count` increment, preceded at 18494–18520 by the same
  `RX.Size - RX.Count > 2` space check and `0x6C` overflow-marker path that the out-of-line
  helper at 0 has at 21–80. That is the same code, inlined, and it is where the `lea` deficit
  comes from.

Closing this means hand-inlining a helper into two functions whose remaining ~700 and ~880
instructions have not been read. Doing it on the strength of a histogram would be guessing, and
the two bodies are the driver's interrupt path. It is left for a dedicated pass.

### Ledger

45 entries: **28 `control-flow-confirmed`, 4 `signature-confirmed`, 2 `intentional-mismatch`,
11 `unexamined`, 0 `assembly-matched`.** Twelve entries advanced to `control-flow-confirmed` on
a full instruction-by-instruction read of the reference against the rewritten source; two
advanced to `signature-confirmed` only. The eleven still `unexamined` are `_activatePort`,
`_deactivatePort`, `acquire:`, `setState:mask:`, `watchState:mask:`, `requestEvent:data:`,
`enqueueEvent:data:sleep:`, `dequeueEvent:data:sleep:`, `enqueueData:…`, `dequeueData:…` and
`_dataLatTOHandler`.

**Nothing is `assembly-matched` and nothing claims to be.** Task 6b did diff rebuilt
instruction streams, but only in aggregate — mnemonic histograms and call-target sets — not
instruction by instruction, which is what that status requires.

The reason string `"full disassembly read instruction by instruction"` was inherited by 34
entries, nine of them `unexamined` and two of them the interrupt handlers whose own reason says
the body was **not** verified. Read literally it claims a rebuilt-versus-reference diff, which
is the class of overstatement that cost two entries their status in the 6a review. On all
thirteen entries that are neither `control-flow-confirmed` nor `intentional-mismatch` it has
been replaced with wording that says what actually happened — the *reference* was read, and no
rebuilt comparison was made. It is left in place only where the entry's status is consistent
with it.

The source map is unchanged in shape: **43 mapped, 2 unmapped**, no duplicates and no disputed
boundaries. Twenty-nine `source_line` values moved because the rewrite shifted the file; each
was re-derived and then verified by printing the line it points at.

## Addendum 8 — Task 8: the driver could not receive, and could not reliably transmit

The whole-effort review returned four Criticals. Two were recorded findings that had never been
implemented, and two were unrecorded. Together they meant that a port which initialised
cleanly, enumerated correctly and published itself to the system **dropped every byte it
received and retransmitted stale cells when its TX ring wrapped**. All four are fixed here, plus
the interval-query arithmetic.

None of this was visible in section parity. `__cstring` was already byte-identical and
`__OBJC` already matched entry for entry while the receive path was dead. Size agreement is not
evidence of behaviour, and this addendum is the clearest demonstration of that the effort has
produced.

### Finding 103 (new) — `acquire:` put `0x126` in `MasterClock` and never sized the rings

`acquire:`'s reset block is reference 4853–5063. Two independent defects sat in it.

**The `0x126` crossing.** The reference stores `0x126` to `[edi+208h]` — `Port.FlowControl` —
at 4937. It is stored to `FlowControl` at three sites in the binary (659, 4937, 5653) and
**never** to `[+0x1dc]`; `MasterClock` only ever receives `0x1c2000` (350, 1991) or the
`"Chip Clock"` key's value (1946). Our source assigned it to `MasterClock`, under the comment
*"UART clock rate (seems odd, might be scaled)"* — the effort's known-bad pattern in its purest
form, a hedge sitting on top of a real defect instead of a check against the header.

The consequence was not cosmetic. `ISASerialPortChip.c:256` computes
`newDivisor = MasterClock / (BaudRate << 3)`; with `MasterClock` = 294 and `BaudRate` = 19200
that is **0**, and `programChip` runs eight lines later in the same block. Every acquire
programmed a zero baud divisor.

**The watermark block was structurally wrong.** The reference assigns
`Size = DefaultSize` for both rings and then derives `HighWater = (2 * Size) / 3` and
`LowWater = HighWater >> 1` from it (4954–5041). Ours never assigned `Size` at all, and instead
wrote `TX.Enqueue = TX.Size`, `RX.HighWater = RX.Size` and `RX.Enqueue = rxLowWater`. Since
`initFromDeviceDescription:` zeroes `0x140` and `0x178`, **every watermark came out zero on the
first acquire** — and with `RX.HighWater == 0` the very first received byte trips the
above-high-water arm, so the port asserts flow-control back-pressure and never releases it.

Also corrected in the same block: `RX_Parity` was 2 where the reference writes 0, and
`BreakLength = 2`, `MinLatency = 0`, `DLRimage = 0` and `RX.OverRun = 0` were missing entirely.

**Finding 88 (line 1460) already carried the correct table**, `| 224 | FlowControl | 0x126 |`
included. It was never implemented. The `MasterClock` crossing was recorded nowhere.

### Finding 104 (new) — both interrupt handlers' TX-watermark tails were inverted

Reference `_NonFIFOIntHandler` 18285–18416, and the identical block in `_FIFOIntHandler`:

```
18294  cmp TX.LowWater, Count ; jb 18344   -> LowWater <  Count goes to the HIGH arm
18299  Dequeue = 0 ; EMPTY (0x6000000) or BELOW_MED (0x2000000)
18344  cmp TX.HighWater, Count ; jae 18404 -> HighWater >= Count goes to BELOW_HIGH
18352  Enqueue = Size-3 ; CRITICAL (0x1800000) or ABOVE_HIGH (0x1000000)
18404  Enqueue = HighWater ; Dequeue = LowWater ; 0
```

Ours had **both branch senses inverted** — the high-water logic sat under `Count < LowWater` —
**and both level constants one rung low**, emitting `TX_STATE_ABOVE_HIGH` where the reference
emits `TX_STATE_CRITICAL` and `0` where it emits `TX_STATE_ABOVE_HIGH`. The block is duplicated
verbatim in the two handlers, so the defect was too. Both copies are fixed.

The corrected shape is the same one `TX_updateState` already carried for `_executeEvent`, which
is where the discrepancy should have been caught: two spellings of one algorithm sat forty lines
apart in the same file and disagreed.

### The two recorded-but-unfixed Criticals

**Finding 10 — the RX gate.** Corrected in place above: two constants, not one substitution.
`STATE_RX_GATE = 0x00400000` for the three handler sites, `STATE_RX_ENABLED = 0x00080000` kept
for the two `watchState` masks. My earlier framing of this as "would break working code if
followed literally" was itself wrong in an important way, and is retracted: the code was
**already broken**. Following the finding literally would have broken two *further* sites while
fixing three.

**Finding 24 — the TX ring wrap.** Resolved in place above: `port->TX.Base`, per reference
17598–17606.

### `requestEvent:` 0x4B and 0x4F

Fixed rather than left open. The reference at 7704–7808 loads `tv_sec` and `tv_nsec`
separately, `mul`s `tv_sec` by `3B9ACA00h`, `cdq`s `tv_nsec` to sign-extend it, adds the pair
and divides by 1000 through `__udivdi3`. Ours read the `tvalspec` as one little-endian 64-bit
word, which is `tv_sec | (tv_nsec << 32)`, and then multiplied *that* by 1e9. The two queries
are the inverse of what events 0x4B and 0x4F set, so they were returning nonsense for any
non-zero interval.

### One place a clamp was deliberately not added

`-[ISASerialPort executeEvent:data:]`'s 0x4B arm has no `0x418937` clamp, while its two
siblings — `initFromDeviceDescription:` and `_executeEvent`'s own 0x4B — do. That asymmetry is
the reference's: 6816–6831 is an unguarded `lea`/`shl` chain, so `data * 1000` can wrap in 32
bits. Adding the clamp would make the driver diverge from the binary being reconstructed. It is
commented at the site instead.

### Comment sweep

`-[ISASerialPort release]`'s reset block had the same RX/TX crossing in its comments that
`requestEvent:` had, with correct code underneath — the fifth pass this pattern has survived in
that method. Both watermark locals were also named for the wrong queue (`txWaterLow` held the RX
high watermark), which is how a comment crossing turns into a code crossing, so they were
renamed as well. Fixed alongside: the `0xA0400018` decomposition, which claimed the constant
contains `STATE_ACTIVE` and `0x80000` when it contains neither and does carry the `0x00400000`
gate Finding 10 needed; `0x208` labelled `stateEventMask` at four sites; `Port.Type` labelled
"also used as hasFIFO"; `0x228/0x22c` labelled `charTimeOverride`; three wrong `IO_R_*` names; a
nine-digit `0xFFFFFFD3E`; and the ring-size clamps described in bytes where the header counts
cells.

The double write of `0x1cc` in `initFromDeviceDescription:` is the reference's own — 330 and
again at 427 — and is now commented as deliberate rather than left to look like a mistake.

### Departure from a stated acceptance criterion

**Spec §4.2 and plan Task 6 Step 8 require `unexamined: 0`. This effort delivers 11.** The
counts have been disclosed in every report, but that they constitute a departure from an
acceptance criterion rather than a neutral status has not been written down until now. The
eleven are `_activatePort`, `_deactivatePort`, `acquire:`, `setState:mask:`, `watchState:mask:`,
`requestEvent:data:`, `enqueueEvent:data:sleep:`, `dequeueEvent:data:sleep:`, `enqueueData:…`,
`dequeueData:…` and `_dataLatTOHandler`.

Task 8 is direct evidence that this matters: three of the four Criticals were in bodies carrying
`unexamined` (`acquire:`) or `signature-confirmed` (both interrupt handlers). The status was
honest; the gap it described was real, and it contained defects that stopped the driver working.
Anyone resuming should treat the remaining eleven the same way.

### A note on the reason text in this document

The free-text citations inside findings are **as-of the report pass that wrote them**. Four cite
line numbers past the current end of `ISASerialPort.m` and roughly eight name identifiers that
no longer exist (`txQueueRead`, `spaceNeeded`, `defaultRingBufferSize`, `_msr_state_lut`) — all
casualties of Task 6a's rename and Task 6b's rewrite. The **structured** fields are current:
every `source_path` and `source_line` in `source-map.json` and `ledger.json` is re-derived and
verified after each change. Reference addresses in the findings are stable and remain the
authority.

## Addendum 9 — Task 9: the two interrupt handler bodies, read

Task 6b left both interrupt handlers at `signature-confirmed` with their bodies unread, arguing
that closing the size gap meant guessing inside ~1600 unexamined instructions. A reviewer
endorsed that. Then the whole-effort review found two Criticals inside those very bodies, both
provable from under 130 instructions. This pass read them: `_FIFOIntHandler` 13060–16231 (880
instructions) and `_NonFIFOIntHandler` 16232–18703 (682), every instruction against the source.

Ten recorded findings were checked. **All ten were real** — none turned out to be the kind of
false report Findings 94 and 102 were. Three new divergences were found inside the handlers, and
three more outside them, one of which was a load-time failure.

### The three ours-only imports — a load failure that section parity could not see

Our binary imported **30** external-undefined symbols; the reference imports **27**. Nothing was
reference-only, so we were a strict superset and every extra was a symbol Apple's driver never
needed:

| symbol | site | recorded as |
|---|---|---|
| `_IOEnterCriticalSection` | 8 pairs in the two handlers, 1 in `watchState` | Finding 105 |
| `_IOExitCriticalSection` | same | Finding 105 |
| `_strncmp` | `initFromDeviceDescription:` | Finding 106 |

Neither `IOEnterCriticalSection` nor `IOExitCriticalSection` exists **anywhere in this source
tree** — not in `driverkit-3`, not in `kernel-7`, nowhere. The kernel does not export them, so
this driver could not have loaded. All three are gone; the import sets are now identical, 27
against 27, with no remainder in either direction.

**The rule this establishes, stated as a rule.** An implicit-declaration warning in this codebase
is a **load-failure signal until the symbol has been checked against the reference's import
list**. The warning text is identical for `_thread_wakeup_prim`, which *is* one of Apple's 27 and
is genuinely just a missing prototype, and for `_IOEnterCriticalSection`, which is not and does
not exist. Nothing in the compiler output distinguishes them. These warnings were reported as
benign three times across earlier passes on exactly that reasoning.

### Finding 105 (new) — the critical-section pairs were the last of Finding 4/5's mistranscription

Finding 5 identified the `IOEnterCriticalSection()`/`IOExitCriticalSection()` pairs as the same
mistranscription as Finding 4's 30 spurious `IODelay(1)` calls: what the original decompilation
read as a critical section is the `lock incl` that `ioPorts.h`'s inline `outb` emits after the
`out`. Eight surviving pairs sat in the two interrupt handlers, each immediately after an `OUTB`,
against the reference's `lock inc ds:_xxx_86` at the corresponding site (17288, 17444, 14212,
14380 and so on). Deleted; `outb()` emits the increment by itself.

The ninth was **not** the same thing. `ISASerialPortFlow.c` wrapped a non-atomic
read-then-write of `Port.WatchLock.locked` in the pair. Reference 23684–23705 is `simple_lock()`
from `src/kernel-7/mach/i386/simple_lock.h` inlined instruction for instruction:

| reference | `simple_lock` / `simple_lock_try` |
|---|---|
| `lea edx,[esi+14h]` | `&slock->locked`, i.e. `Port+0x14` |
| `cmp [edx],0` / `jnz` back | `while (slock->locked) continue;` |
| `mov eax,1` / `xchg eax,[edx]` / `xor eax,1` | `asm("xchgl %1,%0; xorl %3,%0")`, `"0" (TRUE)`, `"i" (TRUE)` |
| `test eax,eax` / `jz` back | `while (!simple_lock_try(slock))` |

`xchg` against memory is atomic on x86 by itself, so there is no critical section and no unlock
afterwards — `thread_sleep(event, lock, interruptible)` drops it, which is why 23710–23720 passes
`lea eax,[esi+14h]` as its second argument. Our old code was wrong twice over: the test-and-set
was not atomic, and its lost-race `continue` targeted the outer `do`/`while`, re-running the
`changedBits` test, where the reference retries the spin.

**`Port.WatchLock` deliberately stays `struct { unsigned int locked; }`** and is cast at the call
rather than becoming a `simple_lock_data_t`. The reference's own ivar type encoding decides this:
it reads `"WatchLock"{?="locked"I}` — an anonymous struct holding an **unsigned** int — where
`simple_lock_data_t` would encode as `{slock="locked"i}`. The two are layout-identical, so
switching the declared type would have flipped `I` to `i` in a published encoding string and
broken a currently byte-identical section for no gain. This is the reference's encoding settling a
type question, which is the strongest kind of evidence available in this reconstruction.

### Finding 106 (new) — it is `strcmp`, not `strncmp`, and there is no call at all

Task 6b introduced `strncmp("PCMCIA", busTypeStr, 7)` in `initFromDeviceDescription:` on the
strength of `mov ecx, 7` at reference 1507. The Task 6b reviewer independently confirmed it.
**Both were wrong.** Reference 1499–1521 reads:

```
1499  mov  eax, offset aPcmcia      ; "PCMCIA"
1504  mov  edx, [ebp+__str]
1507  mov  ecx, 7
1512  mov  esi, eax / mov edi, edx / cld
1517  test al, 0
1519  repz cmpsb                    ; F3 A6 - IDA folds the F3 prefix onto the mnemonic
1521  jnz  loc_5FD
```

There is **no `call` instruction**. This is the compiler's `cmpstrsi` expansion of `strcmp`
against a string literal: `expand_builtin_strcmp` takes `c_strlen` of the constant operand and
uses `len + 1` as the byte count, so the `7` is `strlen("PCMCIA") + 1` and **not a
caller-supplied length**. It is safe as a full `strcmp` because `repz` stops at the first
mismatch, so a shorter `busTypeStr` fails on its own NUL terminator rather than reading past it.
The `strcmp` at 1267 stays out of line precisely because there neither operand has a
compile-time-known length — which is exactly why `_strcmp` is imported and `_strncmp` never was.

**The reference's import list was the discriminator.** A driver that called `strncmp` would import
`_strncmp`; Apple's imports `_strcmp` and `_strncpy` and not `_strncmp`. Reading `mov ecx, 7` as
an argument is a locally plausible misreading that survived a write and a review, and what exposed
it was a set comparison, not a closer look at the instruction.

### The ten recorded findings against the handlers

| Finding | verdict | evidence |
|---|---|---|
| 15 IIR read unconditional | **real, fixed** | 18179 tests the executed-event flag and only falls through to the read at 18189; 15692/15702/15710 test all three flags before 15716 |
| 16 TX comparisons inverted | already closed in Task 8 | re-derived at 18294/18344 and 15821/15875; correct, untouched |
| 17 TX level constants | already closed in Task 8 | all five re-verified at 18319/18334/18378/18394/18416 |
| 21 ladder enqueues the raw RBR byte | **real, fixed** | 16521, 16716 and 16780 all load `byte ptr [ebp+var_8]`, the slot 16567 masks with `RBRmask` |
| 23 NonFIFO's five structural differences | **correct in ours**, untouched | as recorded |
| 25 flow adjustments are independent `if`s | **real, fixed** | 16971/16988/17052, 17131/17144/17212, 13895/13912/13976, 14055/14068/14136 |
| 26 watermark bits from the local copy | **real, fixed** | 13830 masks the local, *then* 13837 reads `[ebx+0Ch]` |
| 27 long-event enqueue is inlined | **real, fixed** | the two handlers are the only 2 of 14 sites not calling the helper at 0 |
| 28 `timerNeeded` on the wrong paths | **real, fixed** | only 14969 and 15344 reach 15684 |
| 29 `fifoRemaining` zeroed on the drain break | **real, fixed** | 15020 breaks with `edi` live; 15708 re-enters the outer loop on it |

Findings 25 and 26 are behavioural, not cosmetic. With `FlowControl == 0x14` the reference sets
only bit 2 and never reaches the `RXOstate` machine; ours set bits 2 and 4 and ran it. And the
`0x17E` seed must come from `port->State` because the local copy's bit 3 may already have been
moved by the XON/XOFF handling twenty instructions earlier.

Finding 27 is the structural one Task 6b named and declined. The reference's class translation unit
has fourteen sites that write the three-cell state-change event; twelve call `_RX_enqueueLongEvent`
at 0, and the two that do not are these handlers, which spell out the `RX.Size - RX.Count > 2`
capacity check, the `0x6C` overflow cell and three advance-wrap-increment cells in full
(18486–18664 and 16014–16192). Inlined only there.

### Finding 107 (new) — the FIFO burst-setup arm had no THRE test

Reference 14572 gates the peek-ahead on `test cl, 20h` before looking at the cell after the TX
head. Ours had no such test. This was **latent until Finding 29 was fixed**: with the burst counter
always zeroed on the drain break, `fifoRemaining` was necessarily 0 at the loop top, so the outer
guard `(lsr & 0x20) || fifoRemaining != 0` could only be satisfied by THRE. Fixing 29 makes
re-entry with a live counter and THRE clear reachable, at which point the unguarded arm writes THR
with no room in the holding register. The two findings had to be closed together.

### Finding 108 (new) — the FIFO full-queue arms must not run the overrun countdown

All four of `_FIFOIntHandler`'s full-queue arms share one site, reference 13684, which sets
`RX.OverRun` and then jumps to **13691 → 13172, the drain-loop top** — skipping the overrun
countdown at 13728 entirely. Ours fell through into it, so a full receive queue could still
decrement the FIFO-overrun counter and enqueue the `0x68` event. Four `continue`s.

`_NonFIFOIntHandler` is not affected and must not be changed to match: its shared overrun site at
16840 jumps to 16884, the RX watermark block, which is the natural fall-through in a handler that
has no drain loop. Two handlers, two different correct answers — recorded so nobody unifies them.

### Finding 109 (new, for Task 10b) — `executeEvent:data:` writes the event tail twice

> **RETRACTED — FALSE at the binary level.** The source observation is correct: our
> `executeEvent:data:` does contain two `RX_enqueueLongEvent` call sites
> (`ISASerialPort.m:3819` and `:3865`). The conclusion drawn from it is wrong. **gcc
> tail-merges the two identical tails, so the emitted code contains exactly one call —
> the same as the reference.** Verified by resolving every call relocation in both bodies:
> both emit **14 calls**, and the target counts are identical function for function —
> `_spl4` ×1, `_splx` ×2, `_thread_wakeup_prim` ×2, `_thread_call_enter` ×2,
> `_flowMachine` ×1, `__udivdi3` ×1, `__umoddi3` ×1, `_validateRingBufferSize` ×2,
> `_executeEvent` ×1, and `__TEXT,__text+-4` (address 0, the TU-1
> `RX_enqueueLongEvent`) **×1 in each**. There is no extra enqueue in the binary, so
> there is nothing to fix and Task 10b correctly did not act on this.
>
> The lesson is the one Finding 106 already recorded from the other direction: a count
> taken from source does not establish a count in the object. This is the **fourth**
> finding in this reconstruction to prove false, after 94, 102 and 68.

*Original text, retained for the record:*

`ISASerialPort.m` calls `RX_enqueueLongEvent` thirteen times where the reference calls it twelve.
The extra one is in `-[ISASerialPort executeEvent:data:]`, which carries two structurally identical
tails — MCR rebuild, `thread_call_enter`, mask test, enqueue — one in the `0x53` arm and one in
`default`. Reference `executeEvent:data:` (6472–7337) calls it **once**, at 7308, so its two arms
converge on a shared tail. Not fixed: that function is outside this task's scope and its ledger
entry is `control-flow-confirmed` from Task 6b. Left for Task 10b, which owns the adjacent group.

### Two spellings of one algorithm, again

The FIFO handler's XON/XOFF-character block was written differently from the NonFIFO handler's — a
nested `if`/`else` with a `goto` into the else branch, against NonFIFO's flat form. The reference's
two copies (13410–13501 and 16570–16661) are structurally identical. Unified on the NonFIFO
spelling. This is the same hazard that produced Critical C4: four spellings of the TX watermark
algorithm in one file, one of which was wrong. Where the reference writes a block twice, our two
copies should be textually identical, so that a defect in one is visibly a defect in both.

### Reproduced, not fixed

`_FIFOIntHandler`'s loop-bottom test re-enters on `overrunCounter != 0` (15698), but that counter
is decremented **only** inside the RX drain loop (13738). If receive data stops arriving while the
counter is non-zero, the handler spins without ever reaching the IIR read at 15716. This is what
the reference does and it is reproduced unchanged. Flagged rather than corrected, per the effort's
rule on Apple's own defects; it is not added to section 6's catalogue because it is a liveness
hazard rather than a wrong value, and it may be unreachable in practice.

### Measured after this commit

The figures below are for the binary **this commit produces** — the build was run after the last
source edit, not before it, which is the error that made Addendum 7's headline numbers stale by
8 bytes.

| metric | before Task 9 | after Task 9 |
|---|---|---|
| `__TEXT,__text` | 23136 | **23244** |
| gap to reference 24412 | −1276 | **−1168** |
| sections matching | 28/30 | 28/30 |
| byte-identical sections | 13 | 13 |
| `missing_strings` / `missing_symbols` / `extra_strings` | 0 / 0 / 0 | 0 / 0 / 0 |
| external-undefined imports | 30 (3 ours-only) | **27 (0 ours-only, 0 reference-only)** |
| build warnings | 8 | **5** |

−1168 is the narrowest the gap has been in this effort, and it closed on a pass whose purpose was
correctness rather than size. `__TEXT,__const` remains absent — the understood permanent absence.

Per-function extents were measured over the rebuilt `__text` by parsing the Mach-O nlist directly
and **excluding `N_STAB` entries by `n_type`**. This matters: the object carries 6819 nlist entries
of which **6732 are stabs**, and a name-based extraction splits every function at each line-number
stab — it reported `_FIFOIntHandler` as 115 bytes. With stabs filtered, 45 non-stab `__text`
symbols remain, matching the reference's 45 exactly. Each extent was then disassembled with
capstone and required to decode cleanly end to end and terminate in `ret`; both handlers do, at
807 and 663 instructions.

| function | reference | ours before | ours after | delta before | delta after |
|---|---|---|---|---|---|
| `_FIFOIntHandler` | 3172 | 2668 | **2664** | −504 | **−508** |
| `_NonFIFOIntHandler` | 2472 | 2144 | **2136** | −328 | **−336** |

Both handlers moved 4 and 8 bytes **further** from the reference, and that is the expected sign:
inlining the three-cell enqueue grows them, but deleting eight critical-section call pairs shrinks
them by more. The pass's +108 bytes came from `initFromDeviceDescription:` (the inline `repz cmpsb`
is larger than a `strncmp` call) and `watchState` (inline `simple_lock` against two calls). Size
was not the objective and was not chased.

**The accounting closes both ways, exactly.** Summing all 45 per-function deltas over IDA extents
gives **−1115**, and 24359 − 23244 = 1115 to the byte. Subtracting the 53 bytes of reference
inter-function padding IDA does not count (24412 − 24359) gives **−1168**, the measured `__text`
gap. No residual.

### Ledger

Both handlers advance `signature-confirmed` → `control-flow-confirmed`. That is the ceiling this
evidence supports, and the pass stops there deliberately: the **reference** stream was read
instruction by instruction, but no rebuilt-versus-reference instruction diff was performed, which
is what `assembly-matched` requires. Nothing in this reconstruction is `assembly-matched` and these
two are not either. `entries=45`, control-flow-confirmed 28 → **30**, signature-confirmed 4 → **2**,
intentional-mismatch 2, unexamined 11 unchanged.

### On re-lining, for Tasks 10a and 10b

`source_line` values were re-derived by aligning the `HEAD` version of each source file against the
working-tree version with a `difflib` opcode alignment and mapping each entry through the `equal`
runs, **asserting that the destination line's text is byte-identical to the source line's** and
refusing to move any entry whose line text changed. 46 values moved across `ledger.json` and
`source-map.json`; 0 were unmappable.

This method caught a failure in this pass that a hand reline would have shipped. The first reline
was computed from a hand-derived +87/+25 offset, and then later comment edits shifted the file a
second time and silently invalidated it — the same staleness that made Addendum 7 wrong. Both JSON
files were reset to `HEAD` and re-lined once, from the committed state to the final state. Use the
alignment, not arithmetic.

**A known property, not drift:** thirteen `source_line` values point at a line inside their
function's leading doc comment rather than at the definition line — `getHandler:…`,
`getCharValues:…`, `release`, `setState:mask:`, `getState`, `watchState:mask:`, `nextEvent`,
`executeEvent:data:`, `requestEvent:data:`, `enqueueEvent:…`, `dequeueEvent:…`, `enqueueData:…`
and `dequeueData:…`. This predates Task 9 and was **preserved rather than corrected**, because
re-lining is only verifiable if it reproduces the previous target exactly; improving thirteen
unrelated entries in the same pass would have destroyed that check. Fix them in a pass that does
nothing else, or leave them.

### Gates

- `load_source_map(...)` prints `source map OK`; partition unchanged at **43 mapped / 2 unmapped**,
  0 duplicate candidates, 0 boundary disputed.
- `binrecon ledger` validates with **45 entries**.
- All touched files LF-only per `git ls-files --eol`.

## Addendum 10 — Task 10a: the port and state group, read

Six bodies, all `unexamined`, read instruction by instruction against the reference:
`_activatePort` 3012–4155 (311 instructions), `_deactivatePort` 4156–4500 (116),
`-[ISASerialPort acquire:]` 4504–5447 (257), `-[ISASerialPort setState:mask:]` 6012–6278 (86),
`-[ISASerialPort watchState:mask:]` 6300–6399 (37) and `_dataLatTOHandler` 9408–10086 (186). That
last one is the reason this task's brief named it: its own ledger entry admitted only **90 of 186**
instructions had ever been read.

Nine recorded findings were re-verified from the bytes before anything was touched. **Seven were
real, one was already correct in our tree, and one — Finding 68 — is outright false.** Three new
divergences were found, one of them a real behavioural defect.

### The ledger status was predictive of defect location, for the third time

This is the result worth stating plainly, because it is the argument for reading bodies rather than
relabelling them.

The reference contains **nine copies** of the RX flow-control ladder. Every copy asserts and drops
the throttling signal with the same three-way triple — `or 4` / `or 0x10` / `or 2` on the way down,
`and 0xFB` / `and 0xEF` / `and 0xFD` on the way up. **Seven of our nine copies already used the
right bit in the hardware-flow arm.** The two that did not were `_activatePort` and
`_dataLatTOHandler` — *precisely the two of the nine that were `unexamined`.*

That is now three for three:

| task | function | status when the defect was found | defect |
|---|---|---|---|
| 8 | `acquire:` | `unexamined` | `0x126` into `MasterClock`, zero baud divisor on every open |
| 8 | both interrupt handlers | `signature-confirmed`, body unread | inverted watermark comparisons, dead RX gate, wrong ring wrap |
| **10a** | `_activatePort`, `_dataLatTOHandler` | **`unexamined`** | **wrong State bit in the hardware-flow arm (Finding 110)** |

`unexamined` was never bookkeeping in this reconstruction. It marked where the bugs were, and it did
so accurately enough that a defect class present in nine places was wrong in exactly the two places
the ledger said had not been checked. Task 10b's five bodies carry the same status.

### Finding 68 is FALSE, and acting on it would have broken correct code

Finding 68 claimed `_activatePort`'s final IER write is *"masked in ours and not in the reference"*
and that our `& 0x0F` *"discards the top nibble — including the MSR-interrupt enable."* Both halves
are wrong.

```
4119  mov  dx, [ebx+88h]      ; Port.Base
4126  inc  dx                 ; Base + 1 = IER
4128  mov  al, [ebx+0B0h]     ; Port.IERmask
4134  24 0F                   ; and al, 0Fh   <-- 0x24 is AND AL, imm8
4136  out  dx, al
```

`24 0F` admits no other reading: **the reference masks with exactly the `0x0F` we always used.** And
IER bit `0x08` *is* the modem-status enable — `0x0F` keeps all four defined enables (RDA, THRE, RLS,
MS) and drops only the 82510's reserved high nibble. Our
`outb(port->Base + UART_IER, port->IERmask & 0x0F)` was correct all along and is unchanged; only its
comment was, and that now cites 4134.

**A finding whose only possible action would have introduced a defect into correct code.** That is
the same shape as Finding 10, which claimed a single substitution where two distinct constants were
needed and would have broken two working sites while fixing three.

### The verification tally, stated as a number

Across Tasks 8, 9 and 10a, every recorded finding touching a body being read has been re-derived
from the disassembly before being acted on. The outcome:

| verdict | findings |
|---|---|
| outright **false** | **3** — 94, 102, **68** |
| **half wrong**, in a way that would have broken working code | **1** — 10 |
| real, and shipped unfixed anyway until a later pass | 2 — 24, 71/72 |
| real and closed | the rest |

Three false and one half wrong out of the recorded set is not an anecdote about the "verify before
acting" rule; it is the rule's justification. Two of the three falsehoods were caught by re-reading
bytes rather than prose, and the third (102) by a set comparison. Prose review did not catch any of
them — it produced two of them.

### Finding 110 (new) — the hardware-flow arm sets State bit `0x10`, not RTS

Reference `or dl, 10h` at 3705 (`_activatePort`) and `or cl, 10h` at 9669 (`_dataLatTOHandler`),
with the mirrors `and dl, 0EFh` at 3865 and `and cl, 0EFh` at 9829. Our two copies used
`STATE_RTS` = `0x04`.

The census is the evidence. Across the reference's `__text` the ladder's three arms appear as:

| function | RTS arm | HW arm | DTR arm | and the clears |
|---|---|---|---|---|
| `_activatePort` | 3685 | **3705** | 3773 | 3849 / **3865** / 3933 |
| `_dataLatTOHandler` | 9649 | **9669** | 9737 | 9813 / **9829** / 9897 |
| `_executeEvent` | 11336, 11694, 12464 | **11353, 12213, 12481** | 11421, 12549 | 11496 / **11509, 12321, 12637** / 11577, 12705 |
| `_FIFOIntHandler` | 13904 | **13921** | 13989 | 14064 / **14077** / 14145 |
| `_NonFIFOIntHandler` | 16980 | **16997** | 17065 | 17140 / **17153** / 17221 |
| `_RX_dequeueEvent` | 21829 | **21849** | 21917 | 21993 / **22009** / 22077 |
| `_RX_dequeueData` | 22509 | **22529** | 22597 | 22673 / **22689** / 22757 |
| `_flowMachine` | 23466 | **23497** | 23433, 23567 | 23472 / **23528** / 23440, 23572 |

`0x10` is a reported-only State bit: the merge masks carry it (`0xF0016`, `0x78F0016`, `0x1F6`) but
the MCR rebuild tests only `0x02` and `0x04`. So the wrong constant did two things at once — it
failed to report the hardware-flow state, and it **drove the real RTS line in the Modem Control
Register** on a port configured with `FlowControl & 0x10` and not `& 0x04`. Not reachable at
`acquire:`'s default `FlowControl = 0x126`, which carries `0x04` and takes the RTS arm first, but
reachable the moment the flow mode is changed through `executeEvent:`.

Both fixed. Both nested chains were also flattened to the reference's `else if` form: the nested
spelling `if ((FC & 4) == 0) { if ((FC & 0x10) == 0) { … } else { … } } else { … }` is logically
identical but inverts every branch sense, where the flat chain compiles to the reference's
`test / jz` / `test / jz` / `test / jz`. In the rebuilt binary the three tests now sit at our 488,
508 and 572 inside `_dataLatTOHandler` against the reference's 9640, 9660 and 9724 — **the same two
intervals, 20 and 64, to the byte.**

### Finding 111 (new) — the `eventMask` staging local is a decompilation artifact

Eleven sites read `Port.FlowControl` into a local before testing it:

```c
memcpy(&eventMask, &port->FlowControl, sizeof(unsigned int));
if (eventMask & (changedBits << 16)) { … }
```

The reference tests the field in place, one instruction — `test [ebx+0E0h], edi` at 10043,
`test [ebx+0E0h], esi` at 3308, `test [esi+0E0h], ebx` at 4308 and so on. The `memcpy` inlines to a
load plus a store, so each site cost a wasted `mov` to a stack slot, and the local it staged into
occupied a frame slot of its own: `_activatePort`'s prologue drops from `sub esp, 0Ch` to
`sub esp, 4` on its removal, three slots to one, against a reference that needs none. There was
never a type problem to work around: `FlowControl` is a 32-bit `unsigned long` and
`port->FlowControl & (changedBits << 16)` is an ordinary expression.

Removed at the **seven** sites inside this task's six functions. **Three remain, and they are
recorded here rather than fixed because they are outside this task's scope:**

| site | owner |
|---|---|
| `enqueueData:bufferSize:transferCount:sleep:` | Task 10b |
| `executeEvent:data:` ×2 | **nobody's current scope** |

`executeEvent:data:` is flagged explicitly so it does not fall through the gap between 10a and 10b.
It is `control-flow-confirmed` from Task 6b and already carries **Finding 109** from Task 9 for the
duplicated `RX_enqueueLongEvent` tail, so it now has two open items and no owner.

### Finding 112 (new, recorded and deliberately not fixed) — `allocateRingBuffer` returns `BOOL`

`_activatePort`'s two calls test the return value as a **byte**:

```
3049  add  esp, 4
3052  84 C0                   ; test al, al
3054  jz   loc_C09
```

`84 C0` is `TEST AL, AL`. A function declared `int` would be tested as `test eax, eax`; the
reference's caller therefore saw a prototype returning `BOOL` (`signed char`) or `char`. Our
`extern int allocateRingBuffer(Queue *q)` makes our build emit `85 C0` = `test eax, eax` at both
sites — the same two bytes' worth of instruction, so **zero size effect and zero behavioural
effect**, but a different instruction than the reference's.

**Not fixed, on scope grounds.** The change is to the declaration in `ISASerialPortInternal.h` and
the definition in `ISASerialPortQueue.c` — `_allocateRingBuffer` @23068, a different ledger entry,
`control-flow-confirmed`. This task's brief says not to touch anything outside its six. The doc
comment in `ISASerialPortQueue.c` already says *"1 on success, 0 on failure (a BOOL, not an
IOReturn)"*, so the intent was known and only the declared type lags. Whoever next owns TU 3 can
close it from the evidence above; the callee's own `mov eax, 1` at 23186 is consistent with either
type, so **the call site is the only discriminator** and it is unambiguous.

### `-[ISASerialPort watchState:mask:]` needed no change at all

Stated affirmatively, because a function verified as already correct is a result and should not read
as an omission. All 37 instructions of reference 6300–6399 match ours:

- the `spl4` / `splx` bracket, with `splx` on both exits;
- the `Port.State < 0` open test read **through the `port` ivar** (`[ebx+258h]` at 6326, then
  `cmp dword ptr [eax+0Ch], 0` / `jge`), not through `self`;
- `mask &= 0xFFFFEFFF` before the call **and** `*state &= 0xFFFFEFFF` after it — two separate
  narrowings, 6338 and 6354;
- `_watchState(port, statePtr, mask)` at 6347 receiving the **`Port *`**, which was Finding 76's
  complaint and is already fixed;
- `IO_R_NOT_OPEN` (−717, `0xFFFFFD33`) on the not-open exit at 6385.

Ours is 88 bytes against 100. The whole 12-byte difference is register allocation: the reference
spills `spl4`'s result to `[ebp+var_4]` and needs `sub esp, 4`, where ours keeps it in `edi`; and the
reference masks the mask in a register it loaded at entry (`and esi, 0FFFFEFFFh`, 6 bytes) where ours
re-reads the argument and masks the high byte (`mov eax, [ebp+0x14]` / `and ah, 0EFh`). No
instruction is missing and none is extra.

### The seven findings that were real

| finding | evidence re-derived | disposition |
|---|---|---|
| **71** `_dataLatTOHandler` entry gate inverted | 9568 `8B431C` loads `RX.Count`, 9571 `394328` compares `RX.Enqueue` against it, 9574 `ja` exits | **fixed** — `if (port->RX.Enqueue <= port->RX.Count)` |
| **72** advances the ring on the completely-full path | 9447 `C743 40 01000000` sets `RX.OverRun`, then `EB 70` jumps to **9568**, past all three advance blocks | **fixed** — three arms, advance in the two that need it, absent from the third |
| **69** `_deactivatePort` is `void`; raw `0xFFFFFD42` | 4169 `jz` goes to the epilogue **without setting `eax`** | **fixed** — `static void`, and three literals now `IO_R_RESOURCE` |
| **79** `setState:mask:` missing its argument rejection | 6027 `F7C6 001000C0` tests `[ebp+arg_C]` = `ebp+0x14` = the **mask**, before `spl4` at 6048 | **fixed** — `if (mask & 0xC0001000) return -706;` |
| **88** `acquire:`'s reset block, three residues | 5171 `or esi, eax` precedes 5182 `and esi, 1F6h`; 4635/4649/4717 keep the `0xA0400018` tail live | **fixed** — see below |
| **89** the heartbeat test | 5331–5375: `mul 3B9ACA00h` on `tv_sec`, `cdq` on `tv_nsec`, `add`/`adc`, `test`/`test` | **fixed** — and it is behavioural, see below |
| **67, 70, 73, 3, 12, 76** | re-derived in full | already correct, untouched |

**Finding 89's remaining half was substance, not style.** The struct half was closed earlier — the
intervals are `tvalspec_t` and `acquire:` reads `Port.HeartBeatInterval` at `[edi+238h]`/`[edi+23Ch]`
— but the *test* was still `tv_sec != 0 || tv_nsec != 0`. The reference forms one 64-bit value and
tests that, and `tv_nsec` is `clock_res_t`, a **signed** type that 5356's `cdq` sign-extends. A
negative `tv_nsec` can therefore cancel `tv_sec * 1e9` and produce a zero the field-wise test would
call non-zero. Now written
`(unsigned long long)tv_sec * 1000000000ULL + (long long)(int)tv_nsec`, the spelling Task 8
established for `requestEvent:`'s `0x4B`/`0x4F`.

**Finding 88's third residue was a hand-folded constant.** `acquire:`'s first state-change tail
stores the literal `State = 0xA0400018`, and our source had folded the consequences by hand —
`outb(Base + 4, MCR_OUT2)` with no tests, and event data `(changedBits << 16) | 0x18`. The reference
does not fold: 4635 and 4649 each materialise `0A0400018h` and mask it before branching, and 4717
does `mov ecx, 0A0400018h` / `and ecx, 0FFFFh`. The tail is now written like the other five copies.

### Made literal where the value was already right

All of these were verified value-equivalent before being changed, so none is a behaviour fix; each
removes a spelling that disagreed with a sibling copy of the same block, which is the hazard that
produced Critical C4.

| site | was | now | why equivalent |
|---|---|---|---|
| `_activatePort` tail 1 MCR + event data | `oldState` | `newState` | the merge only sets bit 30; bits 0–15 identical |
| `_activatePort` tail 2, `_deactivatePort` tail 2 | `flowState` | `newState` | mask `0xFFFFFFE9` clears `0x02`/`0x04`, which `flowState & 0x16` then supplies |
| `_activatePort` tail 3 | `rxState` | `newState` | mask `0xF870FFE9` clears `0x02`/`0x04`/`0x10`; `txState ⊂ 0x7800000` |
| `acquire:` tail 2 | `flowState` | `newState` | mask `0xFFFFFE09` clears `0x02`/`0x04`; `msr << 5 ⊆ 0x1E0` cannot touch them |
| `acquire:` `newState` | `(flow & 0x1F6) \| (msr << 5)` | `((flow \| (msr << 5)) & 0x1F6)` | `0xF << 5 = 0x1E0 ⊂ 0x1F6`, so the mask is a no-op on the LUT term |
| `_activatePort` TX ladder | nested, raw hex `0x1800000`/`0x1000000` | `TX_updateState`'s flat form, named constants | same predicate; and `Count <= LowWater` first is what compiles to the reference's `cmp [TX.LowWater], eax` / `jb` at 3482 |
| both `Size - 3` tests | `Size - 3 < Count` | `Count > Size - 3` | reference 3811 and 9775 are both `cmp [RX.Count], eax` / `jbe`, i.e. `Count` is the left operand |

### Measured after this commit

The build was run **after** the last source edit, on a guest with the stale `_reloc` deleted first,
so these describe the object this commit produces.

| metric | before Task 10a | after Task 10a |
|---|---|---|
| `make` | exit 0, 0 errors | exit 0, 0 errors |
| build warnings | 5 | **5** (identical set) |
| external-undefined imports | 27, 0 ours-only, 0 reference-only | **27, 0 ours-only, 0 reference-only** |
| sections matching | 28/30 | 28/30 |
| byte-identical sections | 13 | 13 |
| `missing_strings` / `missing_symbols` / `extra_strings` | 0 / 0 / 0 | 0 / 0 / 0 |
| `__TEXT,__text` | 23244 | **23260** |
| gap to reference 24412 | −1168 | **−1152** |

−1152 is the narrowest the gap has been, and again it closed on a pass whose purpose was
correctness. `__TEXT,__const` remains absent — the permanent understood absence.

The five warnings are unchanged and none is new: three `thread_wakeup_prim` implicit declarations
(`ISASerialPort.m:298`, `ISASerialPortFlow.c:200`, `ISASerialPortQueue.c:135`), the `thread_sleep`
argument-2 pointer type at `ISASerialPortFlow.c:186`, and `RX_enqueueLongEvent defined but not used`
at `ISASerialPortQueue.h:54`. Per Addendum 9's rule, each implicit declaration was re-checked against
the reference's import list rather than assumed benign: `_thread_wakeup_prim` is one of Apple's 27, so
those three are missing prototypes only.

### Per-function extents

Measured with capstone over the rebuilt `__text` by parsing the Mach-O nlist and **excluding
`N_STAB` entries by `n_type`** — 45 non-stab `__text` symbols, matching the reference's 45.

| function | reference | before | after | delta before | delta after |
|---|---|---|---|---|---|
| `_activatePort` | 1144 | 1180 | **1168** | +36 | **+24** |
| `_deactivatePort` | 345 | 380 | **352** | +35 | **+7** |
| `-[ISASerialPort acquire:]` | 944 | 892 | **920** | −52 | **−24** |
| `-[ISASerialPort setState:mask:]` | 267 | 232 | **256** | −35 | **−11** |
| `-[ISASerialPort watchState:mask:]` | 100 | 88 | 88 | −12 | −12 |
| `_dataLatTOHandler` | 679 | 672 | **676** | −7 | **−3** |
| **the six** | 3479 | 3444 | **3460** | **−35** | **−19** |

**Every byte of the movement is inside the six.** The other 39 extents are unchanged, and the six
sum to exactly +16, which is the whole of 23260 − 23244. Five of the six moved toward the reference;
`watchState:mask:` did not move because it needed no change.

**The accounting closes both ways, exactly.** The 45 per-function deltas over IDA extents sum to
**−1099**, and 24359 − 23260 = 1099 to the byte. Subtracting the 53 bytes of reference
inter-function padding IDA does not count (24412 − 24359) gives **−1152**, the measured `__text` gap.
No residual.

### Corroboration from the rebuilt stream

Not a full rebuilt-versus-reference diff — that is what `assembly-matched` would require and it was
not done — but four structural checks were made against the rebuilt bytes rather than the source:

- `_dataLatTOHandler`'s capacity ladder is three arms with the full path advancing nothing:
  our 286 `cmp eax, 2` / `jbe` on `Size - Count`, then 364–370 `mov eax, [RX.Size]` /
  `cmp [RX.Count], eax` / `jae`, then 408 `mov dword ptr [ebx+40h], 1` falling straight into the
  state gate at 415 with no advance in between. Structurally the reference's 9434 / 9442 / 9447. gcc
  chose the opposite operand order for the second test than the reference did — ours computes
  `Count − Size` and branches `jae`, the reference computes `Size − Count` at 9442 and branches `ja`
  — which are the two encodings of the same `Size > Count`.
- the entry gate is now 415 `mov eax, [RX.Enqueue]` / `cmp [RX.Count], eax` / `jb` to the `splx`,
  i.e. the block runs on `Enqueue <= Count`, against the reference's 9568–9574.
- **gcc's cross-jumping did merge the trailing advance**, as predicted: our 361 `jmp 0x17c` sends the
  `0x4F` arm into the `0x6C` arm's advance at 380, the mirror of the reference's 9467 → 9547. The two
  arms are written out in full in the source and the compiler shares them, which is why writing them
  out was the right way to express it.
- the flow chain's three tests sit at our 488 / 508 / 572, the reference's at 9640 / 9660 / 9724 —
  the same intervals of 20 and 64. Ours emits `or esi, 0x10` where the reference emits `or cl, 10h`,
  because our `newState` landed in `esi`, which has no byte-addressable low half; both encode in
  3 bytes.
- `setState:mask:`'s new rejection is `F7C7 001000C0` / `74 0D` / `mov eax, 0FFFFFD3Eh` / `jmp`
  against the reference's `F7C6 001000C0` / `74 0D` / same / same — identical but for the register.

### Ledger

All six advance `unexamined` → `signature-confirmed` → `control-flow-confirmed`, stepping through
each state because skipping is forbidden. **`control-flow-confirmed` is the ceiling and the pass
stops there deliberately**: the *reference* stream was read instruction by instruction, and four
structural spot-checks were made against the rebuilt stream, but no full rebuilt-versus-reference
instruction diff was performed, which is what `assembly-matched` requires. Nothing in this
reconstruction is `assembly-matched` and these six are not either.

`entries=45`, control-flow-confirmed 30 → **36**, `unexamined` 11 → **5**, signature-confirmed 2,
intentional-mismatch 2, assembly-matched 0.

The five that remain `unexamined` are exactly Task 10b's scope: `requestEvent:data:`,
`enqueueEvent:data:sleep:`, `dequeueEvent:data:sleep:`,
`enqueueData:bufferSize:transferCount:sleep:` and
`dequeueData:bufferSize:transferCount:minCount:`. Spec §4.2 and plan Task 6 Step 8 require
`unexamined: 0`; after this pass the departure is down from 11 to 5 and 10b closes it.

### Re-lining

`source_line` values were re-derived by Addendum 9's method, which is the one to keep using: re-lined
**once** through a `difflib` opcode alignment of the `HEAD` version of each source file against the
final working-tree version, mapping each entry through the `equal` runs and **asserting that the
destination line's text is byte-identical to the source line's**, refusing to move any entry whose
line text changed. Done last, after every source edit, because doing it earlier has gone stale twice
in this effort. Rather than resetting the two JSON files to `HEAD` first, the script asserts for every
entry that its `(source_path, source_line)` still equals `HEAD`'s before mapping it — the same
guarantee, and it also proves that this pass's status and reason edits did not disturb a line number.

**52 values moved across the two files, 0 unmappable, 0 refused — and the rule earned its keep by
refusing one.** `_deactivatePort`'s `source_line` pointed at its own definition line, and Finding 69
rewrote that line from `static IOReturn deactivatePort(Port *port)` to
`static void deactivatePort(Port *port)`. The byte-identical assertion fired, exactly as designed. It
is the only entry retargeted outside the alignment, and the override is **checked rather than
trusted**: the script asserts the `HEAD` line still has the old text, and that the new text occurs
**exactly once** in the working tree, before accepting 639 → 635. Had it matched zero or two lines,
the reline would have aborted rather than guessed.

The thirteen `source_line` values that point at a doc-comment line rather than a definition line are
**preserved exactly**, as Addendum 9 recorded them. Two of the thirteen belong to this task's six —
`setState:mask:` and `watchState:mask:` — and re-lining is only verifiable if it reproduces the
previous target, so they were not "improved" here either. Fix all thirteen in a pass that does
nothing else, or leave them.

### Gates

Both run after the reline, on the committed state.

```
source map OK: mapped 43 unmapped 2 duplicate 0 disputed 0
ledger … entries=45 control-flow-confirmed=36 intentional-mismatch=2 signature-confirmed=2 unexamined=5
```

- `load_source_map(...)` prints `source map OK`; the partition is **unchanged at 43 mapped /
  2 unmapped**, 0 duplicate candidates, 0 boundary disputed. **No function entered or left the mapped
  set.**
- `binrecon ledger` validates with **45 entries**.
- All touched files LF-only per `git ls-files --eol`; the three records are `i/lf w/lf`.
- `ledger.json.lock` is recreated by every `binrecon ledger` run and stays untracked.

## Addendum 11 — Task 10b: the last five bodies, read — `unexamined` reaches 0

The five bodies that were still `unexamined`, read instruction by instruction against the
reference and then diffed against the rebuilt stream: `-[ISASerialPort requestEvent:data:]`
7340–8085 (182 instructions), `-[ISASerialPort enqueueEvent:data:sleep:]` 8088–8207 (44),
`-[ISASerialPort dequeueEvent:data:sleep:]` 8208–8324 (45),
`-[ISASerialPort enqueueData:bufferSize:transferCount:sleep:]` 8328–9023 (213) and
`-[ISASerialPort dequeueData:bufferSize:transferCount:minCount:]` 9024–9406 (121).

**`unexamined` is now 0.** That closes the departure from Spec §4.2 — *"No entry ends
`unexamined`"* — and from plan Task 6 Step 8, which Addendum 8 recorded as open at 11 and
Addendum 10 brought down to 5.

### The ledger status was predictive of defect location, for the fourth time

`requestEvent:data:` dispatched on `event & 0xFF`. The reference loads the whole 32-bit argument
at 7352 and every comparison in the dispatch tree is a full-width `cmp ebx, imm32` — there is no
`and`, no `movzx` and no byte compare anywhere in 7340–7672. So `requestEvent:0x105` was silently
serviced as event `0x05`, and any event number whose low byte happened to collide with a known one
returned the wrong field instead of `IO_R_INVALID_ARG`. It is reachable from a caller with no
hardware involved at all.

| task | function | status when the defect was found | defect |
|---|---|---|---|
| 8 | `acquire:` | `unexamined` | `0x126` into `MasterClock`, zero baud divisor on every open |
| 8 | both interrupt handlers | `signature-confirmed`, body unread | inverted watermark comparisons, dead RX gate, wrong ring wrap |
| 10a | `_activatePort`, `_dataLatTOHandler` | `unexamined` | wrong `State` bit in the hardware-flow arm (Finding 110) |
| **10b** | **`requestEvent:data:`** | **`unexamined`** | **dispatch masked to the low byte; `0x105` aliased to `0x05`** |

Four for four. Every batch of `unexamined` bodies this effort has opened has had a defect in it,
and the last batch was no exception.

### Two entries reach `assembly-matched`, the first in this reconstruction

`enqueueEvent:data:sleep:` and `dequeueEvent:data:sleep:` are **byte-identical to the reference**.
The spec defines `assembly-matched` as *"the rebuilt instruction stream was read against the
reference"*; that had never been done here, which is why Addendum 6's C1 downgraded the only two
entries that claimed it. This pass did it, and the method is stated so it can be reproduced:

1. Extract the rebuilt body from `__TEXT,__text` by parsing the Mach-O nlist and **excluding
   `N_STAB` entries by `n_type`** — 45 non-stab `__text` symbols, matching the reference's 45.
2. Disassemble with capstone; take the reference stream from the published IDA analysis.
3. Drop alignment `nop`s from both.
4. Mask the relative displacement of every `call`, `jmp` and `jcc` — these *must* differ, because
   our functions sit at different addresses inside a smaller `__text`.
5. Compare the remaining bytes.

| function | ref instrs | our instrs | masked bytes | equal |
|---|---|---|---|---|
| `enqueueEvent:data:sleep:` | 44 | 44 | 117 vs 117 | **yes** |
| `dequeueEvent:data:sleep:` | 45 | 45 | 114 vs 114 | **yes** |

Not one instruction differs in either — same opcodes, same registers, same displacements, same
order. `enqueueEvent:`'s extent is 120 against 120; `dequeueEvent:`'s is 120 against 117 because
ours carries three trailing alignment `nop`s the reference does not.

**`rebuilt_sha256` stays `null`**, per the plan's standing convention, so the two reasons carry the
`__TEXT,__text` sha256 `E437CED7AA46313D811065DB415280608734C6BC768C52905495EB5DC49EBCF6` at size
23272 instead. That is the anchor a reviewer should check the claim against. Addendum 6's C1
objected to `assembly-matched` on two grounds — a null `rebuilt_sha256` **and** a reason that
described reading the *reference* rather than a diff. The second ground is now answered directly;
the first is answered by naming the hash in the reason.

### `dequeueEvent:data:sleep:` needed no source change at all

Stated affirmatively, because a function verified as already correct is a result. All 45
instructions of 8208–8324 were already reproduced exactly: the `!event || !data` guard returning
`0xFFFFFD3E`, the `spl4`/`splx` bracket with `splx` on both exits, the `State` bit 30 gate
returning `IO_R_NOT_OPEN`, the `movsx` of the `BOOL` `sleep` argument at 8259, the `Port *` taken
from `[self+258h]`, the one-byte staging local at `[ebp-1]` and the zero-extending store back into
`*event` at 8282. The only edit was to a comment that called `self+0x137` a separate `statusFlags`
field when it is `Port.State`'s top byte.

### Finding 90 is now closed entirely, and its `minCount` half was never wrong

The callout half was fixed in `1bcc4300`. The `minCount` half was re-derived from the bytes before
anything was touched, and **it was already correct**. `minCount` is a sleep budget, not a floor:

- 9216–9226 `cmp [remainingMin], 0` / `setnz al` / `movzx edx, al` / `push edx` — the countdown's
  only use is as `RX_dequeueData`'s third argument, the `sleep` flag.
- 9272–9278 decrements it, and only on the success path.
- Nothing anywhere in 9024–9406 compares `*count` against `minCount`. A short read is not an error.

So the first `minCount` bytes block until they arrive and every byte after that is taken only if it
is already queued. Finding 90's own text says as much; what was missing was any record that
somebody had checked it against the disassembly rather than repeating it. That check is now made
and the finding is closed. The two callout reads were also moved onto the `port` ivar, since 9318
and 9365 go `[self+258h]` then `[port+0ECh]` rather than straight to `self+0x214`.

### Finding 113 (new) — `tv_nsec` zero-extended where the reference sign-extends

`dequeueData:` staged the interval into `unsigned int charTimeLo, charTimeHi` and formed the
64-bit test as `(unsigned long long)charTimeLo * 1000000000ULL + (long long)charTimeHi`. Because
`charTimeHi` was `unsigned`, the widening **zero**-extended. Reference 9090–9095:

```
9090  mov  edx, [ebp+var_C]     ; tv_nsec
9093  mov  eax, edx
9095  99                        ; cdq   <- sign extension
```

`tv_nsec` is `clock_res_t`, which `mach/clock_types.h:74` makes a plain **signed** `int`. A negative
nanosecond value can therefore cancel `tv_sec * 1e9` and produce a genuine zero, which the
zero-extending form would read as non-zero and arm the data-latency callout on an interval the
reference treats as unset. Now written against a `tvalspec_t` local so `tv_nsec` keeps its declared
type, and the rebuilt stream carries `mul ecx` / `mov ebx, eax` / `mov esi, edx` / `mov edx, [nsec]`
/ `mov eax, edx` / `cdq` / `add` / `adc` at our 52–81, byte-identical to reference 9076–9105.

**This is the third occurrence of one shape, so it is worth stating as a rule rather than a
defect.** Finding 89 had it in `acquire:`'s heartbeat test and Critical C5 had it in
`requestEvent:`'s `0x4B`/`0x4F` conversion. Three independent sites is a systematic misreading of
the `tvalspec` idiom, not three typos. **Whoever next forms a 64-bit value out of a `tvalspec_t` in
this driver should expect the nanosecond half to be sign-extended and should check for `cdq`.**

### Finding 114 (new) — the nested TX watermark ladder in `enqueueData:`

`enqueueData:` spelled the TX watermark ladder as a nested `if`/`else` testing
`Count > LowWater` and `Count > HighWater`, which inverts both of the reference's branch senses:
8676 is `cmp [TX.LowWater], Count` / `jb` and 8727 is `cmp [TX.HighWater], Count` / `jnb`, so the
reference's first arm is `Count <= LowWater` and its second is `HighWater < Count`. It also carried
the top two level values as raw `0x1800000` and `0x1000000` and the third as a bare `0`, where
`TX_STATE_CRITICAL`, `TX_STATE_ABOVE_HIGH` and `TX_STATE_BELOW_HIGH` have existed in the header
since Finding 17.

Rewritten in `TX_updateState`'s exact form with the constants named. This is the same hazard that
produced Critical C4 — four spellings of this one algorithm in one file, one of which was wrong —
and Addendum 10 flattened `_activatePort`'s copy for the same reason. **Where the reference writes
a block more than once, our copies should be textually identical, so a defect in one is visibly a
defect in both.** All copies of this ladder now agree.

The same pass found `spaceToEnd` computed as
`((unsigned int)TX.End - (unsigned int)TX.Input) >> 1`, which emits `shr`. Reference 8554 is
`D1F8`, `sar eax, 1` — the shift is on the `char *` pointer difference, an `int`. The report pass's
own entry for 8328 records *"the signed 'sar 1' cell count ... match"*, so **that was recorded as
matching when it was not**. Now written as the pointer difference and the rebuilt stream carries
`D1F8` at our 230.

### The `0x210` comment — the effort's number-one pattern, caught in the act

Both `enqueueEvent:` and `enqueueData:` reached the frame callout through a raw cast:

```c
txTimerPtr = (void **)((char *)self + 0x210);
// Access timer at offset 0x210 (TX operation timer)
// This is a field not yet defined in the header - likely txOperationCallout
thread_call_enter(*txTimerPtr);
```

There is no such field and there never was. `Port` is embedded at 296 and `FrameTOEntry` is at 232,
so `296 + 232 = 0x210`, and the reference reads that same word two ways in the same function:
`[esi+210h]` off `self` at 8175 and 8978, and `[port+0E8h]` off the `Port *` at 8916. This is
exactly the shape that hid the `MasterClock`/`FlowControl` crossing behind *"UART clock rate (seems
odd, might be scaled)"* — a speculative hedge sitting on a raw offset. It is worse here in one
respect: **entry 8088's own `analyzer_agreement` reason had said `FrameTOEntry` since the report
pass.** The record was right and the code's comment contradicted it, and nothing reconciled the
two for ten tasks.

No behaviour changed; `mov esi, [esi+210h]` encodes as `8BB610020000` in both streams either way.
What changed is that the offset is gone.

### The same reasoning, applied to `requestEvent:`'s 22 cases

`requestEvent:` read every field through a cast — `*(unsigned int *)((char *)self + 0x178)` and
21 more — each annotated with a hand-written field name. Those annotations have been wrong in this
method before: Addendum 6's I2 found them *systematically RX/TX crossed*, and `1bcc4300` corrected
them.

Every one was re-checked here against `ISASerialPortInternal.h` with `Port` embedded at 296 **and**
against the reference instruction that reads it, and all 22 were correct. They were then converted
to named `self->Port.…` accesses anyway. The codegen is identical — the offsets are the same
displacements off the same base — and the trade is that 22 hand-checked comments become 22
compiler-checked field references. Given that wrong comments beside raw offsets have caused six
real defects in this effort, two of them Criticals, moving a whole method off raw casts removes the
failure mode rather than re-auditing it.

The check that this was value-preserving is independent of the reading: **the Port-relative
field-access multiset over the rebuilt body is identical to the reference's** — 21 distinct
offsets, same counts on each. `dequeueData:` is identical on the same measure, 5 offsets.

### An observation recorded rather than acted on: `self->Port` versus `self->port`

The reference reaches queue state through the `port` ivar and ours reaches it through the embedded
struct. In `enqueueData:` this is the single largest remaining difference, and it is measurable:
`[self+258h]` is loaded **nine** times in the reference and twice in ours, while each of our field
accesses pays a 4-byte displacement off `self` where the reference pays a 1-byte displacement off
`port`. Over roughly thirty accesses the two effects very nearly cancel, which is consistent with
the measured +48.

**Deliberately not changed.** Converting this one method would leave it disagreeing with the
twenty-odd other TX ring sites in the file, which is precisely the two-spellings hazard Finding 114
above exists to close; and the only gain would be codegen shape, which is size-chasing. Recorded
with the numbers so a future pass that wants to unify all of them can, in one pass that does
nothing else.

### Every recorded finding touching these five, and its disposition

| finding | verdict | evidence re-derived | disposition |
|---|---|---|---|
| **31** dispatch masked to the low byte | **real** | 7352 `mov ebx, [ebp+arg_8]`, then `cmp ebx, 3Bh`, `cmp ebx, 0EDh` — no `and`, no `movzx` in 7340–7672 | **fixed** — `switch (event)`; Finding 31's last open half, so 31 is now closed |
| **11** `FlowControl` reached by `memcpy` type-pun | **real** | 8941 `859FE0000000` tests `[port+0E0h]` in place | **fixed** — same site as Finding 111 |
| **111** the `eventMask` staging local | **real** | as Addendum 10 recorded | **fixed** — the last in-scope site |
| **61** `oldState` where the reference reads `newState` | **real** | 8865 / 8875 test `esi` = `newState`; 8949 `movzx eax, si` | **fixed** — value-equivalent, but `newState` is what the reference reads; 61 now closed at both its sites |
| **17** two TX level values, one unnamed | already closed; last raw-hex site | 8701 `6000000h`, 8714 `2000000h`, 8758 `1800000h`, 8774 `1000000h`, 8796 `xor edx, edx` | **constants named** |
| **90** wrong callout, and `minCount` | callout real and closed in `1bcc4300`; **`minCount` half already correct** | 9216–9226, 9272–9278; nothing compares `*count` to `minCount` | **closed entirely** |
| **92** the near-matches, incl. the `Port *` arguments | **real, already closed** | `[self+258h]` passed at 8145, 8268, 9231 | untouched, re-verified |
| **95** the `0x4B`/`0x4F` formula | **real, closed in Task 8** | 7742 `mul 3B9ACA00h`, 7761 `cdq`, 7774 `add`/`adc`, 7797 `__udivdi3` by 1000 | **verified correct, not assumed** |
| §6 Apple bug: `0x27` computes `RX.Size − TX.Count` | **real, reproduced** | 7932 `[ecx+140h]`, 7938 `sub … [ecx+17Ch]` — the RX twin of `0x23` at 7912/7918 with one substitution missed | reproduced and commented at the site |

### Measured after this commit

The build was run **after** the last source edit, on a guest with the stale `_reloc` deleted first
and `stale=0` confirmed, so these describe the object this commit produces. Getting this order
wrong is what made Addendum 7's headline numbers stale by 8 bytes.

| metric | before Task 10b | after Task 10b |
|---|---|---|
| `make` | exit 0, 0 errors | **exit 0, 0 errors** |
| build warnings | 5 | **5** (identical set, none new) |
| external-undefined imports | 27, 0 ours-only, 0 reference-only | **27, 0 ours-only, 0 reference-only** |
| sections matching | 28/30 | 28/30 |
| byte-identical sections | 13 | 13 |
| `missing_strings` / `missing_symbols` / `extra_strings` | 0 / 0 / 0 | 0 / 0 / 0 |
| `__TEXT,__text` | 23260 | **23272** |
| gap to reference 24412 | −1152 | **−1140** |

−1140 is the narrowest the gap has been, and for the fourth pass running it closed on work whose
purpose was correctness. `__TEXT,__const` remains absent — the permanent understood absence.

Per Addendum 9's rule, each of the five warnings was re-checked against the reference's import list
rather than assumed benign: the three implicit declarations are all `thread_wakeup_prim`, which is
one of Apple's 27, so they are missing prototypes only. **No new warning appeared**, and in
particular no new implicit declaration.

### Per-function extents

Measured with capstone over the rebuilt `__text` by parsing the Mach-O nlist and **excluding
`N_STAB` entries by `n_type`** — 45 non-stab `__text` symbols, matching the reference's 45.

| function | reference | before | after | delta before | delta after |
|---|---|---|---|---|---|
| `-[ISASerialPort requestEvent:data:]` | 746 | 780 | 780 | +34 | +34 |
| `-[ISASerialPort enqueueEvent:data:sleep:]` | 120 | 120 | 120 | **0** | **0** |
| `-[ISASerialPort dequeueEvent:data:sleep:]` | 117 | 120 | 120 | +3 | +3 |
| `-[ISASerialPort enqueueData:…sleep:]` | 696 | 740 | **744** | +44 | **+48** |
| `-[ISASerialPort dequeueData:…minCount:]` | 383 | 364 | **372** | −19 | **−11** |
| **the five** | 2062 | 2124 | **2136** | **+62** | **+74** |

**Every byte of the movement is inside the five.** The other 40 extents are byte-for-byte
unchanged, and the five sum to exactly +12, which is the whole of 23272 − 23260.

`requestEvent:`'s extent did not move even though the `and` on the dispatch argument is gone: the
saving was absorbed by interior alignment padding, of which our body carries seven bytes across
three sites. `dequeueData:` moved 8 bytes **toward** the reference. `enqueueData:` moved 4 further
out, which is the expected sign — naming the level constants and flattening the ladder is
size-neutral, and the in-place `FlowControl` test saves a store while `sar` on a pointer difference
and the `newState` reads cost nothing, so the movement is gcc's block placement responding to a
restructured ladder. Size was not the objective and was not chased.

**The accounting closes both ways, exactly.** The 45 per-function deltas over IDA extents sum to
**−1087**, and 24359 − 23272 = 1087 to the byte. Subtracting the 53 bytes of reference
inter-function padding IDA does not count (24412 − 24359) gives **−1140**, the measured `__text`
gap. No residual.

### Corroboration from the rebuilt stream

Beyond the two exact diffs above, the three remaining bodies were diffed against the reference
instruction sequence and every difference accounted for. None is a missing or extra operation.

- `dequeueData:` — **118 instructions against 121.** The prologue is byte-identical from the
  `mov ecx, 3B9ACA00h` through the `test`/`test` pair (our 52–90 against 9076–9114), as is the
  whole tail from the `thread_call_enter_delayed` argument setup to the `ret` (our 282–370 against
  9318–9406), including `dec edi` / `cmp edi, -1` / `jnz`. The three-instruction difference is that
  ours keeps `size` in `edi` where the reference reloads `[ebp+0x14]` twice before the `minCount`
  compare, and that gcc branched the `0xFFFFFD42`-to-success conversion where the reference
  materialised it with `xor ecx, ecx` / `cmp` / `jz` / `mov ecx, ebx` / `mov ebx, ecx`. Our frame
  is one 4-byte slot smaller, `sub esp, 0x28` against `0x2C`.
- `enqueueData:` — **196 instructions against 213.** `sar eax, 1` at our 230 matches 8554's `D1F8`;
  `test esi, 2` and `test esi, 4` at our 589 and 599 match 8865 and 8875 byte for byte;
  `movzx eax, si` at our 665 matches 8949's `0FB7C6`; `test [ebx+0x208], edx` at our 657 is 8941's
  in-place `FlowControl` test; `dec edx` / `cmp edx, -1` / `jnz` at our 294–298 is 8624–8628. The
  residual is the `self->Port`-versus-`self->port` addressing described above (nine `[self+258h]`
  loads against two), `add eax, 0x10` versus `lea` for `&WatchStateMask`, one re-read of `State`
  the reference makes and ours does not, and gcc's placement of the two early-exit blocks plus one
  `lea` hoisted into a spill slot.
- `requestEvent:` — **187 instructions against 182**, differing only in prologue register
  allocation and the placement of the shared zero-return epilogue. The dispatch tree itself is the
  same binary search over the same 22 values in the same order, and the field-access multiset is
  identical.

### Ledger

`entries=45`. `unexamined` **5 → 0**. `control-flow-confirmed` 36 → **39**, `assembly-matched`
0 → **2**, `signature-confirmed` 2, `intentional-mismatch` 2. Every advance stepped through each
intermediate state, because skipping is forbidden.

Three of the five stop at `control-flow-confirmed` and say why in their own reason: a
rebuilt-versus-reference diff *was* performed on all three, and all three differ.
`control-flow-confirmed` is the correct status for a body whose reference stream has been read in
full and whose rebuilt stream has been diffed and found merely equivalent. Only the two that came
out byte-identical claim `assembly-matched`.

**The two entries still at `signature-confirmed` are `_flowMachine` @23400 and `_watchState`
@23584.** They are not in this task's scope, they were `signature-confirmed` before it, and they are
the only two bodies in the driver whose instruction streams have never been read in full. They are
now the whole of the remaining depth gap.

### Still open, and owned by nobody

`-[ISASerialPort executeEvent:data:]` @6472 carries **two open items**, is
`control-flow-confirmed` from Task 6b, and has had no owner since Task 9 flagged it:

- **Finding 109** — it calls `RX_enqueueLongEvent` twice, at `:3764` and `:3810`, where reference
  7308 calls it once, because its `0x53` arm and its `default` arm carry two structurally identical
  tails instead of converging on a shared one.
- **Finding 111, two sites** — the `memcpy(&eventMask, &self->Port.FlowControl, …)` staging idiom,
  the last two copies in the driver now that this pass removed the third.

Nothing 10b read changes the diagnosis of either, and reading `enqueueData:`'s tail in full
corroborates Finding 109's shape: the reference's state-change tail is one block ending in a single
`RX_enqueueLongEvent`, and `enqueueData:` reaches it from one place. Recorded here so it does not
fall through the gap now that every other body in the driver has been read.

`__TEXT,__const` remains a permanent understood absence. And **the driver has still never been
run** — everything above is static verification against the binary, not evidence that it
enumerates, opens or passes traffic on real or emulated hardware.

### Re-lining

By Addendum 9's method, unchanged, and done **last**, after every source edit: re-lined once
through a `difflib` opcode alignment of the `HEAD` version of each source file against the final
working-tree version, mapping each entry through the `equal` runs and **asserting that the
destination line's text is byte-identical to the source line's**, refusing to move any entry whose
line text changed. The script also asserts, for every entry, that its `(source_path, source_line)`
still equals `HEAD`'s before mapping it — which additionally proves this pass's status and reason
edits did not disturb a line number.

The thirteen `source_line` values that point at a doc-comment line rather than a definition line are
**preserved exactly**, as Addenda 9 and 10 recorded them. Five of the thirteen belong to this task's
five, and re-lining is only verifiable if it reproduces the previous target, so they were not
"improved" here either. That leaves the thirteen as the one piece of tidying this effort has
consistently declined; fix all of them in a pass that does nothing else, or leave them.

### Gates

Both run after the reline, on the committed state.

```
source map OK: mapped 43 unmapped 2 duplicate 0 disputed 0
ledger … entries=45 assembly-matched=2 control-flow-confirmed=39 intentional-mismatch=2 signature-confirmed=2
```

- `load_source_map(...)` prints `source map OK`; the partition is **unchanged at 43 mapped /
  2 unmapped**, 0 duplicate candidates, 0 boundary disputed. **No function entered or left the
  mapped set.**
- `binrecon ledger` validates with **45 entries**, and `unexamined` no longer appears in the
  summary because the count is zero.
- All touched files LF-only per `git ls-files --eol`; the two records are `i/lf w/lf`.
- `ledger.json.lock` is recreated by every `binrecon ledger` run and stays untracked.

## Addendum 12 — `executeEvent:data:` read against the reference

`-[ISASerialPort executeEvent:data:]` was the last function carrying open findings and no owning
task. It is `control-flow-confirmed` from Task 6b and sat in neither Task 10a's nor 10b's scope.
Read here against reference 6472–7340. **No defect found.** Ours is 864 bytes against the
reference's 868, 238 instructions against 246.

### The call graphs are identical

Every call relocation in both bodies was resolved. Both emit **14 calls** and the per-target
counts match exactly:

| target | reference | ours |
|---|---|---|
| `_spl4` | 1 | 1 |
| `_splx` | 2 | 2 |
| `_thread_wakeup_prim` | 2 | 2 |
| `_thread_call_enter` | 2 | 2 |
| `_flowMachine` | 1 | 1 |
| `__udivdi3` | 1 | 1 |
| `__umoddi3` | 1 | 1 |
| `_validateRingBufferSize` | 2 | 2 |
| `_executeEvent` | 1 | 1 |
| `RX_enqueueLongEvent` (address 0) | 1 | 1 |

This retracts **Finding 109** — see the note at that finding. The TU-1 copy of
`RX_enqueueLongEvent` lives at address 0 and is reached by a *relocated* `call 0`, which is
indistinguishable from an `objc_msgSend` call site until the relocation is resolved. Any future
call-graph comparison in this driver must resolve relocations; comparing raw `call` operands will
silently merge the static helper with every Objective-C dispatch.

### Field accesses agree once addressing modes are folded

Comparing memory operands normalised to `Port`-relative (subtracting 296 from self-relative
offsets, since `Port` is embedded at 296), **fourteen of seventeen offsets match exactly**:
`RX.Size`, `RX.HighWater`, `RX.LowWater`, `TX.Size`, `TX.HighWater`, `TX.LowWater`, `Base`,
`FlowControl`, `RXOstate`, `FrameTOEntry`, `CharLatInterval` and its nanosecond half, `WatchLock`,
and the `State` high byte at +15.

The three that appear to differ are addressing-mode and caching artifacts, not missing or extra
operations:

- **`WatchStateMask` (+16)** — both touch it **four times**. The reference computes
  `&port->WatchStateMask` with `add edx, 0x10` (arithmetic, no memory operand) where ours uses
  `lea edx, [edi+0x138]`; and at the first of the two sites the reference tests in place
  (`test [ebx+0x10], edi`) where ours loads to a register first. Equal work.
- **`State` (+12)** — the reference re-reads it where ours keeps it live in a register.
- **the `Port *` ivar (+600)** — the reference re-reads it **six** times, ours **three**. This is
  the `self->port->` versus cached-local shape; it is the largest single contributor to the size
  difference and it is a source-spelling choice, not a divergence.

### Still open, and deliberately not acted on

**Finding 111's last two sites** are real: `ISASerialPort.m:3817` and `:3863` stage
`self->Port.FlowControl` through a local via `memcpy` where the reference tests the field in place.
They cost no net bytes — ours is 4 bytes *smaller* than the reference overall — so this is
literalness polish rather than a defect. Left recorded rather than fixed, since the two sites sit
immediately before the two tail-merged `RX_enqueueLongEvent` calls and touching them risks
perturbing the merge that currently reproduces the reference's single call.

### Method note

Two of this pass's own measurements were wrong before they were right, and both errors were the
same kind: a normalisation applied to one side but not the other, then a regex that matched
`add esp, 0x10` and `shl edi, 0x10` as if they were `Port+16` accesses. Both inflated an apparent
divergence that did not exist. A field-count comparison in this driver is only meaningful when the
same fold is applied to both binaries and the operand is confirmed to be a memory reference.
