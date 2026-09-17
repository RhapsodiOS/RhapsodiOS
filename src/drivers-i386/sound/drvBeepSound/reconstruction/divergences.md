# drvBeepSound divergences

Reference: `Beep.config/Beep_reloc`, 37984 bytes,
SHA-256 `752B5A078A747CE0ED0C36951C5DED5DD99DD2420CD4CFF979D12059A53D6C73`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0 — all three enabled and all three completed.

## Baseline build

There is no rebuilt drvBeepSound artifact on disk: `out/i386/` contains no
`drvBeepSound` directory, so the driver has not been built in the guest during this
pass. Every statement below is derived from the reference binary and from our source
text, not from a rebuilt binary. The `Loaded Server` section sizes our build actually
produces are therefore **unmeasured**.

Reference `Loaded Server` sections, for the fix pass to compare against once a build
exists:

| Section | Size | Content |
| --- | --- | --- |
| `Server Name` | 4 | `Beep` |
| `Load Commands` | 144 | see below |
| `Instance Var` | 13 | `Beep_instance` |
| `Server Version` | 1 | `2` |

There is **no** `Unload Commands` section, matching the expectation for all four
audio drivers. Our `Beep.drvproj/Beep.lksproj/Load_Commands.sect` is 144 bytes and is
**byte-identical** to the reference's `Load Commands` section (verified by direct
comparison). That is a positive result from Task 2, not a finding.

## Summary

| Bucket | Count (report pass) | Count (after the fix pass) |
| --- | --- | --- |
| mapped | 10 | 11 |
| unmapped | 3 | 2 |
| duplicate_candidates | 0 | 0 |
| boundary_disputed | 0 | 0 |

All 13 reference functions land in exactly one bucket and every one carries a ledger
entry. The single bucket move is `+[Beep probe:]`, which the fix pass wrote; see
Finding 1 and the resolution section at the end of this document.

Note on sizes: the task brief's disposition table lists each function's size as the
gap to the next function start (68, 100, 100, 320, 444, 28, 224, 192, 356, 124, 80,
12, 12). Those are padded values. IDA's function bodies — which
`validate_source_map_semantics` checks against — are 66, 99, 97, 318, 441, 25, 223,
192, 356, 123, 77, 12, 12. The source map and ledger use IDA's sizes. The bucket
assignments and source lines in the brief's table were re-derived from the current
`Beep.m` and all matched.

## Examination depth

All 13 reference functions were read **at instruction level**: the complete IDA
disassembly of every function was dumped and read instruction by instruction against
our source. Ghidra's decompiler output was used as an independent cross-check on
`+[Beep probe:]`, `-[Beep reset]`, `_stringToStyle` and `-[Beep beep]`, and it agreed
with the hand reading in every case.

Two functions are recorded `assembly-matched` (`_channelWillAddStream`,
`_getSupportedParameters:count:forObject:`). Two are `intentional-mismatch`
(build-generated glue). The remaining nine carry a confirmed divergence and stay
`unexamined` per the convention that advancing a diverging function's status is the
fix pass's job.

`getCharValues:forParameter:count:` and `setCharValues:forParameter:count:` were
*read* instruction by instruction, and their bodies are otherwise faithful, but both
carry findings — Finding 16 (a construct in `getCharValues:` that cannot compile to
the reference's instructions) and Finding 14 (an Objective-C type-encoding divergence
in both) — so both stay `unexamined`. The reading is recorded here; promoting the
status is the fix pass's job.

**Scope caveat on the two `assembly-matched` entries:** that status covers the
*instructions of those two functions only*. `getCharValues:`, `setCharValues:` and
`setIntValues:`/`getIntValues:` all read `_defaultBeepSequences`, whose *contents*
diverge (Finding 11). The code that walks the table matches; the table it walks does
not. Nothing in this document should be read as "this method behaves identically"
until Finding 11 is fixed.

`source_map`'s `source_sites` glob saw only `Beep.m` — this driver keeps no code in
a `*Inline.h` header of its own, so every mapped `source_line` points at a direct
definition in `Beep.m` and is strong evidence. (The reference does inline code from
the kernel's `machdep/i386/io_inline.h` and `machdep/i386/timer_inline.h`; see
Findings 3 and 7.)

## Unmapped

Three functions, two reason classes.

**No source counterpart** — `+[Beep probe:]` at address 0, 66 bytes. It is absent
from `Beep.m` and `Beep.h` entirely. This is not build-generated glue; the fix pass
writes the method. See Finding 1.

**Build-generated glue** — `+[BeepKernelServerInstance kernelServerInstance]` at
2036 (returns `&_Beep_instance`) and `+[BeepVersion driverKitVersionForBeep]` at 2048
(returns `0x1F4` = 500). Emitted by the Kernel Server project type, not written by
hand. Accepted; recorded `intentional-mismatch` in the ledger.

Data symbols outside `__TEXT,__text` (`__timer_cnt_port_`, `_Beep_VERS_STRING`,
`_Beep_VERS_NUM`, `_beepDeviceName`, `_beepDeviceKind`, `_defaultBeepSequences`,
`_Beep_instance`, the three `_xxx.*` counters) do not appear in the source map, which
lists functions only. They are covered by Findings 3, 4, 11 and 12.

## Analyzer disagreement

Function counts: IDA 13, Ghidra 12, angr 36.

**Ghidra does not detect `+[BeepKernelServerInstance kernelServerInstance]`** at 2036
(12 bytes). It finds the other twelve. IDA is authoritative for the partition, so
this does not affect the source map. It is recorded in that entry's
`analyzer_agreement` as an IDA + angr agreement.

**angr over-splits.** Its 36 functions include 23 addresses that are not function
starts in IDA's partition (57, 66, 141, 167, 265, 326, 465, 523, 586, 931, 1029,
1057, 1237, 1283, 1334, 1413, 1423, 1463, 1782, 1897, 1907, 1955, 2072); every one is
an interior block or epilogue tail of a function IDA reports whole. This is `CFGFast`
splitting on branch targets, not a claim that a different function exists there.
angr also reports CFG errors for the unresolved indirect control flow through
`objc_msgSend`, which is expected for every driver in this effort.

For all twelve functions present in all three analyzers, **size and instruction count
are identical across IDA, Ghidra and angr**. Basic-block counts differ, which is
purely each analyzer's block-splitting convention. There is no body disagreement
anywhere in this binary.

## Positive results (not findings)

- **All nine reference `__cstring` entries are present in our source.** The
  reference's `__TEXT,__cstring` is 61 bytes holding exactly
  `Octave\0Down\0Up\0Blip\0Plain\0Duration\0Frequency\0Style\0AllStyles\0`. Every one
  of those nine appears in `Beep.m`. (Our source additionally emits `PC Speaker`,
  `Beep`, `Audio` and the `Beep: Initialized ...` format string; see Findings 4 and 5.)
- **`Default.table` is clean.** Diffing our
  `Beep.drvproj/Default.table` against the reference's, ignoring `"Driver Version"`,
  produces no output. All eleven remaining keys match, including `"Style" = "Plain"`.
- **`_stringToStyle` is `local` in the reference**, matching our `static`. Confirmed
  from the symbol table.
- **`_defaultBeepSequences` numeric triples match.** The five `{noteCount,
  freqMultiplier, freqDivisor}` triples in the reference are, in table order,
  `{1,1,1}`, `{2,3,4}`, `{8,17,16}`, `{8,15,16}`, `{2,2,1}`, followed by a
  `{NULL,0,0,0}` terminator. Our `Beep.m:65` table carries the same six triples in the
  same order and the same 16-byte stride. **The names attached to the first two
  triples do not match** — see Finding 11.
- **`inb`/`outb` codegen matches.** The reference's `out dx, al; lock incl
  ds:_xxx.86` pairs are the expansion of `outb()` from
  `src/kernel-7/machdep/i386/io_inline.h:103`, which `Beep.m:39` already imports.
  `_xxx.86`, `_xxx.89` and `_xxx.92` in `__DATA,__bss` are the three `static int xxx`
  copies from `outb`/`outw`/`outl`; only `outb`'s is referenced.
- **`NX_SoundDeviceMuteSpeaker` is 7**, and the reference writes literal 7 into
  `list[0]`. Confirmed against
  `src/driverkit-3/driverkit/NXSoundParameterTags.h:44`. Matches `Beep.m:486`.

---

# Answers to the four questions the fix pass acts on

## Q1 — What does `+[Beep probe:]` test, and what does it return?

**Fully determined by the 66 bytes.** Nothing is left to guess.

Reference disassembly, complete:

```
   0: 55               push  ebp
   1: 89E5             mov   ebp, esp
   3: 8B1500400000     mov   edx, ds:paAlloc
   9: 52               push  edx
  10: 8B5508           mov   edx, [ebp+arg_0]        ; self (the class)
  13: 52               push  edx
  14: E8EDFFFFFF       call  _objc_msgSend           ; [self alloc]
  19: 83C408           add   esp, 8
  22: 85C0             test  eax, eax
  24: 7422             jz    loc_3C                  ; alloc returned nil
  26: 8B5510           mov   edx, [ebp+arg_8]        ; deviceDescription
  29: 52               push  edx
  30: 8B1504400000     mov   edx, ds:paInitfromdevice
  36: 52               push  edx
  37: 50               push  eax                     ; the new instance
  38: E8D5FFFFFF       call  _objc_msgSend           ; [inst initFromDeviceDescription:deviceDescription]
  43: 85C0             test  eax, eax
  45: 0F95C0           setnz al
  48: 25FF000000       and   eax, 0FFh
  53: 89EC             mov   esp, ebp
  55: 5D               pop   ebp
  56: C3               retn
loc_3C:
  60: 31C0             xor   eax, eax                ; return NO
  62: 89EC             mov   esp, ebp
  64: 5D               pop   ebp
  65: C3               retn
```

The ObjC metadata in `__OBJC,__cls_meth` gives the signature encoding
`'c12@8:12@16'` — return type `c` (`char`, i.e. `BOOL`), arguments `(id self, SEL
_cmd, id deviceDescription)`. It is the class's only class method.

Ghidra's decompiler, independently, produces:

```c
bool probe(param_1, param_2, param_3) {
  iVar1 = objc_msgSend(param_1, PTR_s_alloc);
  if (iVar1 != 0) {
    iVar1 = objc_msgSend(iVar1, PTR_s_initFromDeviceDescription__, param_3);
    return iVar1 != 0;
  }
  return false;
}
```

**What it tests:** only that `[self alloc]` yields a non-nil object and that
`-initFromDeviceDescription:` on that object yields a non-nil result. It performs no
hardware probing, reads no ports, and consults no config table. The PC speaker is
assumed present.

**What it returns:** `YES` if `initFromDeviceDescription:` returned non-nil, `NO` if
either `alloc` or `initFromDeviceDescription:` returned nil. The `setnz al` / `and
eax, 0FFh` pair normalises the result to exactly 0 or 1.

**One behaviour worth naming explicitly:** on the `initFromDeviceDescription:`-
returns-nil path the allocated instance is **not** freed and **not** released. The
reference leaks it. Reproduce this if the goal is byte parity; deviate only
deliberately.

Source to write (fix pass's call):

```objc
+ (BOOL)probe:deviceDescription
{
    id instance = [self alloc];

    if (instance == nil)
        return NO;

    return [instance initFromDeviceDescription:deviceDescription] != nil;
}
```

`Beep.h` needs the matching `+ (BOOL)probe:deviceDescription;` declaration.

## Q2 — How does `-[Beep beep]` compute its `thread_set_timeout` argument?

**Confirmed: the argument is in ticks, not milliseconds.** Our `Beep.m:228` already
computes the tick count correctly; `Beep.m:253` then converts it *back* to
milliseconds only because it calls `IOSleep`.

The timeout is computed once, before the note loop, and reused unchanged for every
note:

```
 689: 8B5508           mov   edx, [ebp+self]
 692: 8BBA8C010000     mov   edi, [edx+18Ch]     ; edi = duration        (ivar `duration`)
 698: 0FAF3D00000000   imul  edi, ds:_hz         ; edi = duration * hz
 705: 8D0CB6           lea   ecx, [esi+esi*4]    ; ecx = noteCount * 5
 708: 8D0C89           lea   ecx, [ecx+ecx*4]    ; ecx = noteCount * 25
 711: 8D0C89           lea   ecx, [ecx+ecx*4]    ; ecx = noteCount * 125
 714: C1E103           shl   ecx, 3              ; ecx = noteCount * 1000
 717: 894DF0           mov   [ebp+var_10], ecx
 720: 89F8             mov   eax, edi
 722: 31D2             xor   edx, edx
 724: F775F0           div   [ebp+var_10]        ; UNSIGNED divide
 727: 89C7             mov   edi, eax            ; edi = (duration * hz) / (noteCount * 1000)
```

That is exactly `(_defaultDuration * hz) / (noteCount * 1000)` — an unsigned
division, which is what our source's `unsigned int timeout` already produces. Ghidra
renders the same expression:
`uVar5 = (uint)(*(int *)(param_1 + 0x18c) * _hz) / (uint)(iVar2 * 1000);`

The value in `edi` is passed **directly, unscaled**, to `thread_set_timeout`. It is
a tick count. Our `Beep.m:253` `IOSleep(timeout * 1000 / hz)` multiplies it back into
milliseconds for `IOSleep`, which is the correct conversion for `IOSleep` but is not
what the reference does.

**Exact call sequence, per note** (identical in both the peeled first note at
842–866 and the loop body at 977–1000):

```
 842: 6A00             push  0
 844: 6A00             push  0
 846: E8ADFCFFFF       call  _assert_wait          ; assert_wait(0, 0)
 851: 57               push  edi
 852: E8A7FCFFFF       call  _thread_set_timeout   ; thread_set_timeout(timeoutTicks)
 857: E8A2FCFFFF       call  _thread_block         ; thread_block()
 862: 4E               dec   esi
 863: 83C40C           add   esp, 0Ch              ; pop 2 + 1 dwords
```

So in C:

```c
assert_wait(0, 0);
thread_set_timeout(timeoutTicks);
thread_block();
```

`thread_block` is called with **no** arguments — the caller-cleanup of `0Ch` accounts
for exactly `assert_wait`'s two dwords plus `thread_set_timeout`'s one, leaving none
for `thread_block`. Declare it `void thread_block(void)`.

The reference's import list is complete and contains `_assert_wait`, `_hz`,
`_thread_block`, `_thread_set_timeout`, `_objc_msgSend`, `_objc_msgSendSuper`,
`_strncmp`, `_strncpy`, `_strtol` and three of the six `.objc_class_name_*` symbols —
`IOAudio`, `IODevice` and `Object`, the three that are undefined (`n_type` `0x01`,
`N_UNDF|N_EXT`); the other three, `Beep`, `BeepKernelServerInstance` and `BeepVersion`,
are defined absolute symbols (`n_type` `0x03`, `N_ABS|N_EXT`) and are not imports — and
**no `_IOSleep` and no `_IOLog`**. (`strlen` and `strcmp` are absent too, but only
because the compiler inlined them as `repne scasb` / `repe cmpsb`; our source's
`strlen`/`strcmp` calls will inline the same way and are not a divergence.)

Full reconstruction of the reference's note loop, for the fix pass:

```c
/* first note, peeled out of the loop by the reference */
outb(TIMER_CTL_PORT, self->timer_as_byte);
timer_write(TIMER_CNT2_SEL, TIMER_CONSTANT / (currentFreq > 0 ? currentFreq : 1));
outb(PPI_PORT_B, savedPortB | 3);
assert_wait(0, 0); thread_set_timeout(timeoutTicks); thread_block();

while (--noteCount != 0) {
    currentFreq = (freqMult * currentFreq) / freqDiv;
    outb(TIMER_CTL_PORT, self->timer_as_byte);
    timer_write(TIMER_CNT2_SEL, TIMER_CONSTANT / (currentFreq > 0 ? currentFreq : 1));
    assert_wait(0, 0); thread_set_timeout(timeoutTicks); thread_block();
}

outb(PPI_PORT_B, savedPortB);
```

The peeling of the first note is a faithful rendering of our source's
`if (i == 0) outb(PPI_PORT_B, savedPortB | 3);` plus
`if (i < noteCount - 1) currentFreq = ...;`, and produces the same sequence of
frequencies. The peeling itself is a compiler transformation and is **not** a
divergence. Likewise, the reference writes the control byte *before* computing the
divisor while our source computes the divisor first; the divisor computation has no
I/O side effects, so the ordering is not observable and is not a divergence.

## Q3 — Is `__timer_cnt_port_` read, and with what index?

**Yes. `-[Beep beep]` reads it, at index 2 only, twice.**

The symbol is `local` in `__TEXT,__const` at 2060, 12 bytes, holding three 32-bit
ints:

```
2060: 40 00 00 00  41 00 00 00  42 00 00 00      -> {0x40, 0x41, 0x42}
```

Cross-references, from the IDA reference analysis:

| Address | Reads | From |
| --- | --- | --- |
| 2060 (`[0]`, 0x40) | 0 | — |
| 2064 (`[1]`, 0x41) | 0 | — |
| 2068 (`[2]`, 0x42) | 2 | `-[Beep beep]` at 788 and at 944 |

Both reads are 16-bit loads of the port number into `dx`, each feeding the pair of
counter-2 data writes:

```
 785: 8A45F0           mov   al, byte ptr [ebp+var_10]   ; low byte of divisor
 788: 668B0D14080000   mov   cx, ds:word_814             ; _timer_cnt_port_[2] == 0x42
 795: 89CA             mov   edx, ecx
 797: EE               out   dx, al
 798: F0FF056C200000   lock inc ds:_xxx.86
 805: 668B45F0         mov   ax, word ptr [ebp+var_10]
 809: 66C1E808         shr   ax, 8                       ; high byte of divisor
 813: EE               out   dx, al
 814: F0FF056C200000   lock inc ds:_xxx.86
```

`0x814` is 2068 decimal — index 2. Indices 0 and 1 are never read; they exist only
because the array is initialised whole.

**This symbol is not Apple-Beep-specific — it is already in our tree.**
`src/kernel-7/machdep/i386/timer_inline.h:81`–`:84` defines:

```c
#define TIMER_CNT_PORT(n)	_timer_cnt_port_[(n)]
static const int	_timer_cnt_port_[] =
	{ TIMER_CNT0_PORT, TIMER_CNT1_PORT, TIMER_CNT2_PORT };
```

and `timer_inline.h:102` defines `timer_write(sel, val)` as exactly the two
`outb(TIMER_CNT_PORT(sel), byte)` writes seen above. So the reference's `Beep.m`
imported `<machdep/i386/timer_inline.h>` and called
`timer_write(TIMER_CNT2_SEL, divisor)`. Our `Beep.m` imports only
`<machdep/i386/io_inline.h>` (line 39) and writes the literal `PIT_COUNTER2` (`0x42`,
`Beep.m:49`) instead. See Finding 3.

## Q4 — Are `_beepDeviceName` / `_beepDeviceKind` passed to `setName:` / `setDeviceKind:`?

**Yes — but from `-[Beep reset]`, not from `-[Beep initFromDeviceDescription:]`.**
The question as posed names the wrong method; the placement in our source is
already correct.

`__DATA,__data` at 8192:

```
8192: 42 65 65 70 00  41 75 64 69 6F 00  00
      _beepDeviceName = "Beep"   _beepDeviceKind = "Audio"  (+1 pad byte)
```

Both are `local` symbols in `__DATA,__data` — writable data, not `__TEXT,__cstring`
literals. Each has exactly one cross-reference in the whole binary, and both are in
`-[Beep reset]`:

```
 172: 8B5D08           mov   ebx, [ebp+self]
 175: 6800200000       push  offset _beepDeviceName     ; 0x2000 == 8192
 180: 8B1508400000     mov   edx, ds:paSetname
 186: 52               push  edx
 187: 53               push  ebx
 188: E83FFFFFFF       call  _objc_msgSend              ; [self setName:_beepDeviceName]
 193: 6805200000       push  offset _beepDeviceKind     ; 0x2005 == 8197
 198: 8B150C400000     mov   edx, ds:paSetdevicekind
 204: 52               push  edx
 205: 53               push  ebx
 206: E82DFFFFFF       call  _objc_msgSend              ; [self setDeviceKind:_beepDeviceKind]
```

`-[Beep initFromDeviceDescription:]` never touches either symbol, and there is no
`setName:`/`setDeviceKind:` send anywhere else in `__text`.

So the *placement* matches our `Beep.m:176` and `Beep.m:179` exactly — both sends are
in `reset`, in that order, first `setName:` then `setDeviceKind:`. The divergence is
only that ours passes `__TEXT,__cstring` string literals where the reference passes
the addresses of two mutable `__DATA,__data` char arrays. See Finding 4.

---

# Findings

## Finding 1: `+[Beep probe:]` is absent from our source

**Reference:** address 0, 66 bytes, `__TEXT,__text`, `local` binding, the class's
only entry in `__OBJC,__cls_meth`. (Its `n_type` is `0x0E` — `N_SECT` without
`N_EXT`. Every method symbol in this binary is local; the defined symbols that are
genuinely `global` are `_Beep_VERS_STRING`, `_Beep_VERS_NUM`, `_defaultBeepSequences`
and `_Beep_instance`. Note that the IDA analysis JSON reports this symbol's binding
as `global`; that is an adapter artifact — the raw `nlist` is authoritative and says
local.)

**Our source:** `Beep.m` and `Beep.h` contain no `probe`. Grep finds no occurrence.

**Difference:** an entire class method is missing. Without it, the driver cannot be
probed by `IODevice`'s driver-loading path in the way the reference expects.

**Disposition:** fix — write the method. Full reconstruction and the exact source to
write are in Q1 above.

## Finding 2: `IOSleep` where the reference uses Mach thread primitives

**Source:** `Beep.m:253`

**Reference behaviour**

```
 842: 6A00             push  0
 844: 6A00             push  0
 846: E8ADFCFFFF       call  _assert_wait
 851: 57               push  edi                  ; timeout in TICKS
 852: E8A7FCFFFF       call  _thread_set_timeout
 857: E8A2FCFFFF       call  _thread_block
 863: 83C40C           add   esp, 0Ch
```

**Our source**

```c
/* Wait for note duration using kernel sleep */
IOSleep(timeout * 1000 / hz);
```

**Difference:** our source calls `IOSleep` with a millisecond argument reconstituted
from the tick count. The reference blocks the calling thread directly with
`assert_wait(0, 0)` / `thread_set_timeout(ticks)` / `thread_block()`, passing the
tick count unscaled. The reference's import table has no `_IOSleep` entry at all, so
this is not a matter of which wrapper the linker resolved — the reference genuinely
does not use `IOSleep`.

**The divergence is mechanism, not magnitude.** On i386 `hz` is 100
(`src/kernel-7/machdep/i386/mach_param.h:55` defines `HZ` as `(100)`;
`src/kernel-7/kern/mach_clock.c:84` is `int hz = HZ;`), so one tick is exactly 10 ms
and the `timeout * 1000 / hz` round-trip back to milliseconds is exact — it is a
multiply by 10, with no truncation. The only truncation anywhere in the chain is the
tick division `(duration * hz) / (noteCount * 1000)`, which our source performs
identically to the reference and which is therefore faithful.

Worked through for the shipped `Duration = 100` ms at `hz = 100`
(`duration * hz` = 10000), across every `noteCount` in `_defaultBeepSequences`:

| `noteCount` | `timeout` (ticks) | our `IOSleep` argument (ms) | reference sleep |
| --- | --- | --- | --- |
| 1 | 10000 / 1000 = 10 | 100 | 10 ticks = 100 ms |
| 2 | 10000 / 2000 = 5 | 50 | 5 ticks = 50 ms |
| 8 | 10000 / 8000 = 1 | 10 | 1 tick = 10 ms |

The table's largest `noteCount` is 8. `timeout` only reaches 0 when
`duration * 100 < noteCount * 1000`, i.e. when the configured `Duration` is below
`noteCount * 10` ms — below 80 ms at `noteCount = 8`. That degenerate case is reached
identically on both sides (the reference passes 0 to `thread_set_timeout`), so it is
not a divergence in the computed value either. What differs is only *how* the wait is
performed.

(The round-trip would stop being exact if `hz` did not divide 1000. It does on every
i386 configuration in this tree, so no such case arises here.)

**Disposition:** fix — replace `IOSleep(...)` with the three-call sequence and pass
`timeout` unchanged. Declare `thread_block` as taking no arguments.

## Finding 3: PIT counter-2 port literal where the reference indexes `_timer_cnt_port_`

**Source:** `Beep.m:49` (`#define PIT_COUNTER2 0x42`), used at `Beep.m:244` and
`Beep.m:245`; `Beep.m:39` imports only `io_inline.h`.

**Reference behaviour:** loads the port number from `_timer_cnt_port_[2]`
(`__TEXT,__const:2068`) into `dx` before each pair of data writes — see Q3 for the
disassembly and the cross-reference table.

**Our source**

```c
outb(PIT_CONTROL, _pitCommand);
outb(PIT_COUNTER2, (unsigned char)(pitDivisor & 0xFF));
outb(PIT_COUNTER2, (unsigned char)(pitDivisor >> 8));
```

**Difference:** ours emits `mov edx, 42h` immediates; the reference emits a load from
`__TEXT,__const`. The 12-byte `__timer_cnt_port_` array itself has no counterpart in
our build because our source never imports `<machdep/i386/timer_inline.h>`. The port
value written is the same (0x42), so run-time behaviour is identical — this is a
binary-layout divergence, not a behavioural one.

Note that `PIT_CONTROL` (`0x43`) and `PPI_PORT_B` (`0x61`) *are* immediates in the
reference too (`mov edx, 43h`, `mov edx, 61h`). Only the counter data port comes from
the table, because `timer_write()` is the only helper that indexes it.

**Disposition:** fix — import `<machdep/i386/timer.h>` and
`<machdep/i386/timer_inline.h>` and replace the two counter writes with
`timer_write(TIMER_CNT2_SEL, pitDivisor)`, which emits both bytes. Replace
`PIT_CONTROL` with `TIMER_CTL_PORT`.

## Finding 4: device name and kind as string literals where the reference uses `__DATA` symbols

**Source:** `Beep.m:176` and `Beep.m:179`

**Reference behaviour:** `-[Beep reset]` passes `offset _beepDeviceName` (8192) and
`offset _beepDeviceKind` (8197) — see Q4 for the disassembly. Both are `local`
symbols in `__DATA,__data`.

**Our source**

```c
[self setName:"Beep"];
[self setDeviceKind:"Audio"];
```

**Difference:** ours puts `"Beep"` and `"Audio"` in `__TEXT,__cstring` as read-only
literals; the reference has them as two mutable `char[]` arrays at the head of
`__DATA,__data`, immediately before `_defaultBeepSequences`. The `__DATA,__data`
layout is `_beepDeviceName` (5 bytes) + `_beepDeviceKind` (6 bytes) + 1 pad byte +
`_defaultBeepSequences` (96 bytes) = 108 bytes total.

**Disposition:** fix — declare two file-scope arrays and pass them:

```c
static char beepDeviceName[] = "Beep";
static char beepDeviceKind[] = "Audio";
```

(`local` binding matches `static`.) The call sites and their order in `reset` are
already correct and must not move.

## Finding 5: `initFromDeviceDescription:` does three things the reference does not

**Source:** `Beep.m:162` (`setLocation:`), `Beep.m:165` (`[self reset]`),
`Beep.m:167` (`IOLog`).

**Reference behaviour:** the complete tail of `-[Beep initFromDeviceDescription:]`,
after the style lookup, is:

```
 556: C1E004           shl   eax, 4
 559: 050C200000       add   eax, offset _defaultBeepSequences
 564: 8B5508           mov   edx, [ebp+self]
 567: 898290010000     mov   [edx+190h], eax
 573: 8B4508           mov   eax, [ebp+self]        ; return self
 576: 8D65E8           lea   esp, [ebp-18h]
 ...
 585: C3               retn
```

There is nothing between the style assignment and the return.

**Our source**

```c
    /* Set device location */
    [self setLocation:"PC Speaker"];

    /* Initialize device and build PIT command byte */
    [self reset];

    IOLog("Beep: Initialized (default: %d Hz, %d ms)\n",
          _defaultFrequency, _defaultDuration);

    return self;
```

**Difference:** three additions, each independently verifiable from the reference's
metadata rather than only from absence in the disassembly:

1. **`setLocation:` is not sent.** The reference's `__OBJC,__message_refs` section
   holds exactly fifteen selectors — `alloc`, `initFromDeviceDescription:`, `setName:`,
   `setDeviceKind:`, `configTable`, `valueForStringKey:`, `freeString:`,
   `isOutputMuted`, `beep`, `getIntValues:forParameter:count:`,
   `setIntValues:forParameter:count:`, `getCharValues:forParameter:count:`,
   `setCharValues:forParameter:count:`, `_outputChannel`, `isEqual:`. There is no
   `setLocation:` reference, and no `"PC Speaker"` string in `__cstring`.
2. **`reset` is not called from `init`.** There is no `reset` selector in
   `__message_refs` and no direct `call` to 168 anywhere in `__text`. `-[Beep reset]`
   is reachable only through the runtime, from `__inst_meth`.
3. **`IOLog` is not called.** `_IOLog` is absent from the import table, and the
   format string `Beep: Initialized (default: %d Hz, %d ms)\n` has no counterpart in
   the reference's 61-byte `__cstring`.

**Disposition:** fix — remove all three. Removing `[self reset]` is the consequential
one: it means `timer`/`_pitCommand` is *not* initialised at `init` time in the
reference. That is safe there because the reference's bit sequence in `reset`
produces `0xB6` from any starting value (see Finding 8) and because `alloc`
zero-fills ivars, but it is a real behavioural difference: in the reference, `beep`
called before any `reset` writes a zero control byte to `TIMER_CTL_PORT`.

Flag for the fix pass: verify whether `IODevice` or `IOAudio` invokes `-reset`
automatically during registration before deciding this is harmless. This report does
not establish that.

## Finding 6: `_stringToStyle` has a NULL check the reference does not

**Source:** `Beep.m:87`–`Beep.m:88`

**Reference behaviour** — the function's first instructions, with no test of the
argument:

```
  68: 55               push  ebp
  69: 89E5             mov   ebp, esp
  71: 57               push  edi
  72: 56               push  esi
  73: 53               push  ebx
  74: 8B7508           mov   esi, [ebp+__s2]     ; styleStr
  77: 30C0             xor   al, al
  79: 89F7             mov   edi, esi
  81: FC               cld
  82: B9FFFFFFFF       mov   ecx, 0FFFFFFFFh
  87: F2AE             scasb                     ; inlined strlen -> dereferences immediately
  89: 89C8             mov   eax, ecx
  91: F7D0             not   eax
  93: 8D78FF           lea   edi, [eax-1]        ; nameLen
```

**Our source**

```c
if (styleStr == NULL)
    return -1;

/* Calculate length of input string */
nameLen = strlen(styleStr);
```

**Difference:** ours guards against a NULL argument; the reference dereferences it
straight away via the inlined `strlen`. Ghidra's decompilation confirms the absence
of the guard.

This matters because `-[Beep setCharValues:forParameter:count:]` passes the
caller-supplied `parameterArray` to `_stringToStyle` with no check of its own — the
`call _stringToStyle` is at **1870**, with the argument loaded at 1866
(`mov edx, [ebp+__s2]`) and pushed at 1869 — so the reference will fault on a NULL
`parameterArray`. Our guard makes that case return `-711` instead.

**Second divergence in the same function: the loop carries an `index` counter the
reference does not have.** The reference computes the return value as
`(seq - _defaultBeepSequences) >> 4` — a pointer subtraction performed once, at the
match site:

```
  96: BB0C200000       mov   ebx, offset _defaultBeepSequences
 101: 833D0C20000000   cmp   ds:_defaultBeepSequences, 0
 108: 742A             jz    loc_98
 112: 57               push  edi                    ; nameLen
 113: 56               push  esi                    ; styleStr
 114: 8B13             mov   edx, [ebx]             ; seq->name
 116: 52               push  edx
 117: E886FFFFFF       call  _strncmp
 122: 83C40C           add   esp, 0Ch
 125: 85C0             test  eax, eax
 127: 750F             jnz   loc_90
 129: 89D8             mov   eax, ebx
 131: 2D0C200000       sub   eax, offset _defaultBeepSequences
 136: C1F804           sar   eax, 4                 ; (seq - table) / 16
 139: EB10             jmp   loc_9D
loc_90:
 144: 83C310           add   ebx, 10h
 147: 833B00           cmp   dword ptr [ebx], 0
 150: 75D8             jnz   loc_70
```

Ours (`Beep.m:85`, `:94`, `:95`, `:98`) declares `int index`, initialises it to 0 and
advances it in the loop's third clause. That cannot compile to the instructions
above: there is no fourth callee-saved register free (`ebx` holds `seq`, `esi` holds
`styleStr`, `edi` holds `nameLen`, and `index` must survive the `strncmp` call), so
our build must spill `index` to a stack slot — yet the reference's prologue has **no
`sub esp` at all** (`push ebp; mov ebp, esp; push edi; push esi; push ebx`, epilogue
`lea esp, [ebp-0Ch]`), meaning the reference allocates zero stack locals. Our build
would additionally emit an increment of that slot on every iteration, which is absent
here.

The two constructs are semantically identical — they yield the same index — but they
are not the same instructions, so this is recorded as a divergence, on the same
threshold applied to Finding 16. An earlier revision of this document called it "not
a divergence"; that was inconsistent and is corrected here.

**Disposition of this second point:** fix — drop the `index` variable and return
`(int)(seq - defaultBeepSequences)` from the loop, which the compiler renders as the
subtract-and-shift above.

**Disposition:** fix if strict parity is the goal; the guard is strictly safer than
the reference. Flagged rather than decided, because removing it introduces a
NULL-dereference path that our source currently does not have. The fix pass should
choose deliberately and record the choice.

## Finding 7: `PIT_FREQUENCY` is 1193182 where the reference uses 1193167

**Source:** `Beep.m:61` (`#define PIT_FREQUENCY 1193182`), used at `Beep.m:237`.

**Reference behaviour**

```
 759: 85DB             test  ebx, ebx
 761: 7E0D             jle   loc_308
 763: B8CF341200       mov   eax, 1234CFh        ; 0x1234CF == 1193167
 768: 99               cdq
 769: F7FB             idiv  ebx
 771: 0FB7C8           movzx ecx, ax             ; truncate to 16 bits
 774: EB05             jmp   loc_30D
loc_308:
 776: B9CF340000       mov   ecx, 34CFh          ; 0x34CF == 1193167 & 0xFFFF
```

**Our source**

```c
if (currentFreq > 0) {
    pitDivisor = PIT_FREQUENCY / currentFreq;      /* 1193182 / freq */
} else {
    pitDivisor = 0x34cf;  /* fallback value */
}
```

**Difference:** the reference's dividend is `0x1234CF` = **1193167**, which is exactly
`TIMER_CONSTANT` from `src/kernel-7/machdep/i386/timer.h:84`. Ours is 1193182 — the
true 1.193182 MHz PIT rate, but not the constant Apple's driver used.

The audible effect is small but real: across the 20 Hz–20 kHz range the two dividends
produce a different 16-bit divisor at 58 of 19981 integer frequencies, all of them at
the low end (20, 21, 22, 23, 25, 29, 33, 37, 41, 42, 45, 55, …). At the default
880 Hz both give 1355, so the shipped configuration is unaffected. The divergence is
in the constant, not in its consequences at the default.

The `0x34CF` fallback is not an arbitrary magic number: it is
`(unsigned short)(1193167 / 1)`, i.e. the compiler constant-folding the `freq <= 0`
arm of `TIMER_CONSTANT / (currentFreq > 0 ? currentFreq : 1)`. That also explains the
signed `jle` rather than a test for zero. Our source hard-codes `0x34cf` with the
comment "fallback value", which happens to be right only because it was copied from
the 1193167 constant — it is inconsistent with our own `PIT_FREQUENCY` of 1193182.

**Disposition:** fix — use `TIMER_CONSTANT` from `<machdep/i386/timer.h>` (already
being imported per Finding 3) and express the fallback as the ternary
`TIMER_CONSTANT / (currentFreq > 0 ? currentFreq : 1)` so the two can never drift
apart again.

## Finding 8: `initFromDeviceDescription:` initialises `_pitCommand`; the reference does not

**Source:** `Beep.m:132`

**Reference behaviour:** `-[Beep initFromDeviceDescription:]` writes only two ivars
directly — `[edx+190h]` (`currentBeepSequence`) at 410 and 567, `[edx+18Ch]`
(`duration`) at 440 and 471, `[edx+188h]` (`frequency`) at 498 and 527. There is no
write to `[edx+185h]` anywhere in the function. Across the whole `__text` section the
only accesses to offsets `0x180`–`0x187` are the six read-modify-writes in
`-[Beep reset]` (211, 218, 225, 232, 239, 246) and the two reads in `-[Beep beep]`
(738, 893).

**Our source**

```c
/* Initialize PIT command byte */
_pitCommand = PIT_CMD_COUNTER2_LOHI_MODE3;
```

**Difference:** an extra store the reference does not perform. It is also redundant
even in our own code, because `reset`'s bit sequence produces `0xB6` from *any*
starting value: `((X & 0xFE & 0xF1) | 0x06 | 0x30) & 0x3F | 0x80` reduces to
`(X & 0x30) | 0x36 | 0x80` = `0xB6` for all X. The reference relies on exactly that.

**Disposition:** fix — remove the assignment. Note that `Beep.m:53`'s
`PIT_CMD_COUNTER2_LOHI_MODE3` becomes unused once this store goes, since `reset`
builds the byte through bit operations rather than assigning the constant.

## Finding 9: `getIntValues:` and `setIntValues:` have NULL checks the reference does not

**Source:** `Beep.m:276`–`Beep.m:278` and `Beep.m:397`–`Beep.m:399`

**Reference behaviour** — `getIntValues:forParameter:count:` dereferences `count`
in its first four instructions after the prologue, with no test:

```
1069: 8B5518           mov   edx, [ebp+arg_10]   ; count
1072: 8B02             mov   eax, [edx]          ; *count -- unguarded
1074: 8945F4           mov   [ebp+var_C], eax
1077: 85C0             test  eax, eax
1079: 7507             jnz   loc_440
1081: C745F400020000   mov   [ebp+var_C], 200h
```

`setIntValues:forParameter:count:` likewise loads `parameterArray` at 1293 and
dereferences it at 1318/1355/1387 with no NULL test.

**Our source**

```c
if (parameterArray == NULL || count == NULL) {     /* getIntValues:  */
    return IO_R_INVALID_ARG;
}
...
if (parameterArray == NULL) {                      /* setIntValues:  */
    return IO_R_INVALID_ARG;
}
```

**Difference:** two guards the reference does not have. Everything else in both
methods matches instruction for instruction, including several details worth
recording as confirmed:

- the `*count == 0 -> 512` default (`mov [ebp+var_C], 200h`) in `getIntValues:`;
- `getIntValues:` passing `&maxLen` (the local at `var_C`) to `super`, not the
  caller's `count` — our `Beep.m:312` `count:&maxLen` is correct;
- `getCharValues:` passing the caller's `count` to `super` — our `Beep.m:390` is
  correct; the asymmetry between the two methods is faithful;
- `setIntValues:` rejecting a style index with `cmp dword ptr [edx], 4 / ja` — an
  **unsigned** compare against 4, matching our `if (parameterArray[0] > 4)` on an
  `unsigned *`, returning `0FFFFFD39h` (`-711`);
- the style index in `getIntValues:` computed as
  `(_beepSequence - _defaultBeepSequences) >> 4`.

**Disposition:** fix if strict parity is the goal; as with Finding 6 the guards are
strictly safer than the reference. Flagged rather than decided.

## Finding 10: `-[Beep beep]` is declared `IOReturn`; the reference declares it `void`

**Source:** `Beep.h:65` and `Beep.m:195`

**Reference behaviour:** `__OBJC,__inst_meth` gives `-[beep]` the type encoding
`'v8@8:12'` — return type `v` (`void`), arguments `(id self, SEL _cmd)`. The
disassembly agrees: no path through the function loads a return value into `eax`. On
the muted early exit `eax` still holds `isOutputMuted`'s result; on the
`frequency == 0` exit it holds `self`; on the normal exit it holds the saved port-B
byte. Ghidra renders the tail as `return uVar5;` over an undefined value, which is
what a `void` function compiled with a live `eax` looks like.

The sole caller inside the binary, `-[Beep _channelWillAddStream]` at 1046, discards
the result and returns a fresh `xor eax, eax`.

**Our source**

```c
- (IOReturn)beep
{
    ...
    return IO_R_SUCCESS;
}
```

**Difference:** the declared return type, which is observable in the emitted
`__OBJC,__meth_var_types` string, and four `xor eax, eax` / `mov eax, 0` stores our
build will emit that the reference does not.

**Disposition:** fix — change to `- (void)beep` in both `Beep.h` and `Beep.m` and
drop the four `return IO_R_SUCCESS;` statements. Before doing so, confirm that
neither `IOAudio` nor `IODevice` declares `-beep` with a conflicting return type;
`src/driverkit-3/driverkit/IOAudio.h` declares `isOutputMuted` (line 115) but the
grep for `beep` in that header found no method declaration, so this looks safe.

## Finding 11: `_defaultBeepSequences` has "Blip" and "Plain" swapped

**This is the most consequential finding in this pass, and it contradicts what
scoping recorded.** The task brief states that `_defaultBeepSequences` holds
`Blip {1,1,1}`, `Plain {2,3,4}`, ... "matching `Beep.m:66` field for field". It does
not. The names on the first two entries are transposed.

**Source:** `Beep.m:65`–`Beep.m:78`

**Reference data**, `__DATA,__data` at 8204, 96 bytes, raw:

```
8204: D6 08 00 00  01 00 00 00  01 00 00 00  01 00 00 00
8220: D1 08 00 00  02 00 00 00  03 00 00 00  04 00 00 00
8236: CE 08 00 00  08 00 00 00  11 00 00 00  10 00 00 00
8252: C9 08 00 00  08 00 00 00  0F 00 00 00  10 00 00 00
8268: C2 08 00 00  02 00 00 00  02 00 00 00  01 00 00 00
8284: 00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
```

The name pointers are corroborated by the binary's own relocation entries, so this
is not a mis-resolution on my part:

```
{"address": 8204, "target": "aPlain",  "addend": 2262}
{"address": 8220, "target": "aBlip",   "addend": 2257}
{"address": 8236, "target": "aUp",     "addend": 2254}
{"address": 8252, "target": "aDown",   "addend": 2249}
{"address": 8268, "target": "aOctave", "addend": 2242}
```

| Index | Reference | Our `Beep.m:65` |
| --- | --- | --- |
| 0 | `{ "Plain", 1, 1, 1 }` | `{ "Blip",  1, 1, 1 }` |
| 1 | `{ "Blip",  2, 3, 4 }` | `{ "Plain", 2, 3, 4 }` |
| 2 | `{ "Up",     8, 17, 16 }` | `{ "Up",     8, 17, 16 }` |
| 3 | `{ "Down",   8, 15, 16 }` | `{ "Down",   8, 15, 16 }` |
| 4 | `{ "Octave", 2, 2, 1 }` | `{ "Octave", 2, 2, 1 }` |
| 5 | `{ NULL, 0, 0, 0 }` | `{ NULL, 0, 0, 0 }` |

The three triples at indices 2–4 match, and all six triples appear in the same order
with the same 16-byte stride. Only the two names are exchanged.

**Difference and why it is behavioural, not cosmetic:**

1. **The default sound is wrong.** `Default.table` ships `"Style" = "Plain"` in both
   the reference and our tree. In the reference that resolves to index 0 —
   `noteCount = 1`, ratio 1:1 — a single tone at the default frequency. In our source
   "Plain" resolves to index 1 — `noteCount = 2`, ratio 3:4 — two tones, a descending
   fourth. Out of the box, our driver produces a different sound from Apple's.
2. **`setIntValues:` for `"Style"` takes an index 0–4**, so any caller selecting by
   number gets a different style than it would on the reference.
3. **`getIntValues:` for `"Style"` returns the index**, so a round-trip through a
   configuration tool would relabel the user's choice.
4. **`getCharValues:` for `"AllStyles"`** returns the names in table order, so our
   driver reports `"Blip Plain Up Down Octave"` where the reference reports
   `"Plain Blip Up Down Octave"`.

The reference's assignment is also the semantically sensible one: "Plain" being the
one-note, no-pitch-change style, and "Blip" the short two-tone. Our table gives
"Blip" the plain single tone.

**Disposition:** fix — swap the two names so index 0 is `{ "Plain", 1, 1, 1 }` and
index 1 is `{ "Blip", 2, 3, 4 }`. Leave the numeric triples exactly where they are;
only the two string literals move.

## Finding 12: `_defaultBeepSequences` is `static` where the reference is `external`

**Source:** `Beep.m:65` (`static BeepSequence defaultBeepSequences[]`)

**Reference:** the symbol `_defaultBeepSequences` at `__DATA,__data:8204` has
`global` binding in the Mach-O symbol table. By contrast `_stringToStyle` at
`__TEXT,__text:68` has `local` binding, matching our `static int stringToStyle`.

**Difference:** ours emits a local symbol where the reference emits a global one. No
behavioural consequence within a single translation unit — the eleven references to
the table from six functions are identical either way — but the symbol table differs.

**Disposition:** fix — drop `static` from the array definition (keep it on
`stringToStyle`). This is the confirmation the brief asked for: `_defaultBeepSequences`
external, `_stringToStyle` local, both verified from the reference symbol table.

## Finding 13: `Beep`'s instance-variable block is missing an ivar, and all four names differ

**Source:** `Beep.h:54`–`Beep.h:57`

**Reference `__OBJC,__instance_vars`** — five entries, not four:

| Name | Type encoding | Offset |
| --- | --- | --- |
| `isMute` | `c` | 388 (`0x184`) |
| `timer` | `{?="bcd"b1"mode"b3"rw"b2"sel"b2}` | 389 (`0x185`) |
| `frequency` | `I` | 392 (`0x188`) |
| `duration` | `I` | 396 (`0x18C`) |
| `currentBeepSequence` | `^{?}` | 400 (`0x190`) |

**Our source**

```c
unsigned char _pitCommand;        /* PIT command byte (0xB6) */
unsigned int _defaultFrequency;   /* Default frequency in Hz */
unsigned int _defaultDuration;    /* Default duration in ms */
BeepSequence *_beepSequence;      /* Pointer to beep sequence */
```

**Differences, three of them:**

1. **`isMute` is missing.** The reference declares a `char isMute` at `0x184` that no
   instruction in `__text` ever reads or writes — it is dead in Apple's source too,
   but it occupies a byte. Without it our `_pitCommand` lands at `0x184`, not the
   `0x185` that `Beep.h:50`'s own comment claims. The three aligned ivars at `0x188`,
   `0x18C` and `0x190` happen to land correctly regardless, because `unsigned int`
   forces 4-byte alignment either way — so only the char ivar is displaced. Note that
   this is *not* `IOAudio`'s own `_isOutputMuted` (`IOAudio.h:68`), which lives inside
   `IOAudio`'s ivar block below `0x184`; `Beep` declares a second, unused one.
2. **`timer` is a bitfield struct, not a plain `unsigned char`.** Its encoding
   `{?="bcd"b1"mode"b3"rw"b2"sel"b2}` is exactly `timer_ctl_reg_t` from
   `src/kernel-7/machdep/i386/timer.h:42`–`:61` (the `typedef struct {` opens at 42
   and `} timer_ctl_reg_t;` closes it at 61). This is the direct confirmation that
   `-[Beep reset]`'s six read-modify-writes are bitfield assignments —
   `and 0xFE` is `reg.bcd = 0`, `and 0xF1` + `or 0x06` is `reg.mode = TIMER_SQWAVEMODE`
   (3), `or 0x30` is `reg.rw = TIMER_CTL_RW_BOTH` (3), `and 0x3F` + `or 0x80` is
   `reg.sel = TIMER_CNT2_SEL` (2). Our source reproduces the same six masks by hand
   with literal comments, which produces identical code but loses the connection to
   the header.
3. **All four surviving names differ**: `timer`/`frequency`/`duration`/
   `currentBeepSequence` versus `_pitCommand`/`_defaultFrequency`/`_defaultDuration`/
   `_beepSequence`. Ivar names are emitted verbatim into `__OBJC,__instance_vars`, so
   this is binary-observable, not cosmetic.

The `currentBeepSequence` encoding `^{?}` is a pointer to an anonymous struct, which
is what `BeepSequence *` produces given `Beep.h:39`'s anonymous `typedef struct {...}
BeepSequence`. That part matches.

**Disposition:** fix — add the leading `char isMute;`, rename the four ivars to the
reference's names, and type the control byte as `timer_ctl_reg_t` (which requires the
`<machdep/i386/timer.h>` import already needed for Findings 3 and 7). Renaming the
ivars touches every use site in `Beep.m`; that churn traces to this finding and is in
scope for it.

## Finding 14: `getCharValues:`/`setCharValues:` encode `parameterArray` as `char *`, ours as `unsigned char *`

**Source:** `Beep.h:72` and `Beep.h:80`; `Beep.m:315` and `Beep.m:432`

**Reference `__OBJC,__inst_meth` type encodings**, complete, for comparison:

| Method | Encoding |
| --- | --- |
| `-[Beep reset]` | `c8@8:12` |
| `-[Beep initFromDeviceDescription:]` | `@12@8:12@16` |
| `-[Beep beep]` | `v8@8:12` |
| `-[Beep _channelWillAddStream]` | `c8@8:12` |
| `-[Beep getIntValues:forParameter:count:]` | `i20@8:12^I16*20^I24` |
| `-[Beep setIntValues:forParameter:count:]` | `i20@8:12^I16*20I24` |
| `-[Beep getCharValues:forParameter:count:]` | `i20@8:12*16*20^I24` |
| `-[Beep setCharValues:forParameter:count:]` | `i20@8:12*16*20I24` |
| `-[Beep _getSupportedParameters:count:forObject:]` | `v20@8:12^i16^I20@24` |
| `+[Beep probe:]` | `c12@8:12@16` |

**Difference:** in the two char-values methods the reference encodes `parameterArray`
as `*` (i.e. `char *`). Our headers declare `unsigned char *`, which encodes as `^C`.
Everything else in the table matches our declarations, including `^i` for the
`NXSoundParameterTag *` list and `^I`/`I` for the count parameters.

**Tension the fix pass must resolve, not this report:**
`src/driverkit-3/driverkit/IODevice.h:209` and `:217` declare these methods with
`(unsigned char *)parameterArray`. Changing `Beep.h`/`Beep.m` to `char *` to match the
reference's encoding will disagree with the inherited declaration and may warn.
Recorded as observed; the fix pass should weigh metadata parity against a clean build
and record the choice. Do not change `IODevice.h` — it is outside this effort's scope.

**Disposition:** flagged, low severity, metadata only. No behavioural effect. The
divergence is in emitted Objective-C metadata rather than in the instruction stream,
but it is a confirmed divergence, so both ledger entries (1476 and 1832) are
`unexamined`; advancing them is the fix pass's job.

## Finding 15: `-[Beep beep]`'s early exits skip the port-B restore — confirmed matching, recorded for the fix pass

Not a divergence; recorded because it is easy to break while fixing Findings 2, 3, 7
and 10.

All three early exits (`isOutputMuted` true at 619, `frequency == 0` at 635,
`duration == 0` at 648) jump to `loc_3FB` at 1019, which is the *epilogue only*. The
`outb(PPI_PORT_B, savedPortB)` restore at 1003–1012 is on the fall-through path from
the note loop and is **not** executed on any early exit — correctly, since
`savedPortB` has not been read yet on those paths. Our `Beep.m:209`–`Beep.m:216`
returns before `inb(PPI_PORT_B)` for the same reason. This matches; keep it that way.

## Finding 16: `getCharValues:` uses a `BOOL firstItem` flag where the reference tests the table cursor

**Source:** `Beep.m:324` (declaration), `:354` (set), `:368` (test), `:377` (clear)

**Reference behaviour** — in the `"AllStyles"` loop, the list separator is suppressed
on the first entry by comparing the walking cursor `ebx` against the address of the
table itself:

```
1634: BB0C200000       mov   ebx, offset _defaultBeepSequences   ; seq = table
...
1689: 81FB0C200000     cmp   ebx, offset _defaultBeepSequences   ; seq == table?
1695: 7420             jz    loc_6C1                             ; -> 1729, no separator
1697: 8B7518           mov   esi, [ebp+arg_10]
1700: 8B36             mov   esi, [esi]
1702: 83C602           add   esi, 2                              ; *count + 2
1705: 8B45F4           mov   eax, [ebp+var_C]                    ; maxLen
1708: 39C6             cmp   esi, eax
1710: 7711             ja    loc_6C1                             ; -> 1729
1712: 8B7518           mov   esi, [ebp+arg_10]
1715: 8B36             mov   esi, [esi]
1717: 8B4510           mov   eax, [ebp+__dst]
1720: C6040620         mov   byte ptr [esi+eax], 20h             ; ' '
1724: 8B7518           mov   esi, [ebp+arg_10]
1727: FF06             inc   dword ptr [esi]                     ; ++*count
loc_6C1:
1729: 57               push  edi
```

There is no boolean anywhere in the function: nothing is stored to or loaded from a
flag byte, and the loop's only per-iteration state is `ebx` (advanced by `add ebx,
10h` at 1753).

**Our source**

```c
    firstItem = YES;
    for (seq = defaultBeepSequences; seq->name != NULL; seq++) {
        ...
        /* Add space separator (except for first item) */
        if (!firstItem && (*count + 2 <= maxLen)) {
            parameterArray[*count] = ' ';
            *count = *count + 1;
        }
        ...
        firstItem = NO;
    }
```

**Difference:** ours carries a `BOOL firstItem` local. That cannot compile to the
instructions above — our build must allocate a stack byte for it and emit a store of
1 before the loop, a `cmpb`/`testb` against it at the separator test, and a store of 0
at the bottom of every iteration. None of those instructions exist in the reference,
which instead does the single `cmp ebx, offset _defaultBeepSequences`. The two are
semantically identical (`firstItem` is true exactly when `seq == table`), so there is
no behavioural difference; the divergence is in the emitted instruction stream.

The rest of the function's body **does** match instruction for instruction, including
the `*count == 0 -> 512` default, the `maxLen <= nameLen -> nameLen = maxLen - 1`
clamp in the `"Style"` branch, the `*count + nameLen >= maxLen` truncation in the
`"AllStyles"` loop, the trailing NUL plus `++*count`, and the delegation to `super`
with the caller's `count`.

Same threshold as the second point in Finding 6: a construct that cannot produce the
reference's instructions is a divergence even when the behaviour is identical.

**Disposition:** fix — drop `firstItem` and suppress the separator with
`if (seq != defaultBeepSequences && (*count + 2 <= maxLen))`, which is what the
reference compiles from.

---

# Fix pass resolution

Every finding above is resolved below. The driver was built for the first time in
this pass: `gnumake RC_ARCHS=i386` exits 0, `Beep.m` compiles under `-Wmost` with no
warnings, and the staged `Beep_reloc` is 106816 bytes (unstripped; the reference is
37984).

Parity, before and after the source fixes:

| List | Baseline | After |
| --- | --- | --- |
| `missing_strings` | 0 | 0 |
| `missing_symbols` | 1 (`+[Beep probe:]`) | 0 |
| `extra_strings` | 4 (`Beep`, `Audio`, `PC Speaker`, `Beep: Initialized ...`) | 0 |
| `extra_symbols` | 16 | 18 |

Both `extra_symbols` counts are entirely stabs from our unstripped build — `Beep.m`,
the `machdep/i386/*_inline.h` file entries and one `name:fN` entry per function. The
two added ones are `+[Beep probe:]:f2` and the `timer_inline.h` file entry, both
consequences of fixes below. `parity_check.py` now exits 0.

Per-function sizes in the rebuilt binary against the reference:

```
   ref   ours name
    68     68 +[Beep probe:]
    12     12 +[BeepKernelServerInstance kernelServerInstance]
    12     12 +[BeepVersion driverKitVersionForBeep]
    28     28 -[Beep _channelWillAddStream]
    80     80 -[Beep _getSupportedParameters:count:forObject:]
   444    356 -[Beep beep]
   356    356 -[Beep getCharValues:forParameter:count:]
   224    248 -[Beep getIntValues:forParameter:count:]
   320    316 -[Beep initFromDeviceDescription:]
   100    100 -[Beep reset]
   124    124 -[Beep setCharValues:forParameter:count:]
   192    196 -[Beep setIntValues:forParameter:count:]
   100    104 _stringToStyle
```

Nothing is flagged `LARGER`. The three functions that exceed the reference —
`getIntValues:` by 24 bytes, `setIntValues:` by 4 and `_stringToStyle` by 4 — are
exactly the three where a NULL guard was deliberately retained, and the excess is
exactly the guard. `beep` is *smaller* than the reference because our gcc rolls the
note loop the reference peels.

Every rewritten function was disassembled out of the rebuilt binary with capstone and
read against the reference instruction by instruction. `+[Beep probe:]` (31/31
instructions), `-[Beep reset]` (28/28) and `-[Beep getCharValues:forParameter:count:]`
(138/138) came out identical in sequence, not merely in content.

## Finding-by-finding

| # | Resolution |
| --- | --- |
| 1 | **Fixed.** `+ (BOOL)probe:deviceDescription` written from the disassembly in Q1 and declared in `Beep.h`. It allocates, sends `initFromDeviceDescription:`, and returns the non-nil test; it does not free the instance on failure, reproducing the reference's leak. Rebuilt at 68 bytes, instruction for instruction identical. |
| 2 | **Fixed.** `IOSleep` replaced by `assert_wait(0, 0)` / `thread_set_timeout(timeout)` / `thread_block()`, with the tick count passed unscaled. The rebuilt stream carries the same `push 0; push 0; call; push; call; call; add esp, 0Ch`. `<kernserv/prototypes.h>` already declared all three, `thread_block` as `void thread_block(void)`. |
| 3 | **Fixed.** `<machdep/i386/timer.h>` and `<machdep/i386/timer_inline.h>` imported; the control write is `timer_set_ctl(timer)` and the two counter writes are `timer_write(TIMER_CNT2_SEL, pitDivisor)`. `PIT_CONTROL` and `PIT_COUNTER2` are gone. The rebuilt binary loads the port from `_timer_cnt_port_[2]` in `__TEXT,__const`, as the reference does. |
| 4 | **Fixed.** `static char beepDeviceName[] = "Beep";` and `static char beepDeviceKind[] = "Audio";` at file scope; `reset` passes their addresses. Both come out `local` in `__DATA,__data`, and the two `__TEXT,__cstring` literals are gone. The call sites did not move — they were already in `reset`, as Q4 records. The plan's Step 5 named `Beep.m:176`/`:179` as needing relocation; that was not necessary. |
| 5 | **Fixed.** `setLocation:"PC Speaker"`, the `[self reset]` send and the `IOLog` are all removed. Removing the `reset` send is safe and is now established rather than assumed: `src/driverkit-3/libDriver/Kernel/IOAudio.m:1647` shows `-[IOAudio initFromDeviceDescription:]` sending `[self reset]` itself and returning nil if it answers `NO`, so `reset` still runs during registration, before `super`'s initialiser returns. Ours was a second, redundant send. |
| 6 | **Split.** The `index` counter is **fixed** — the loop returns `(int)(seq - defaultBeepSequences)`, and the rebuilt prologue has no `sub esp`, so no stack local is allocated, matching the reference's `sub`/`sar`. The NULL guard is **accepted as `intentional-mismatch`** (reviewer Pat Raynor). `setCharValues:` hands the caller's `parameterArray` straight to `stringToStyle`, so dropping the guard would buy 4 bytes of parity in exchange for a kernel-mode NULL dereference. |
| 7 | **Fixed.** `PIT_FREQUENCY` and `PIT_DIVISOR` are gone; the divisor is `TIMER_CONSTANT / (currentFreq > 0 ? currentFreq : 1)`. The rebuilt stream divides by `0x1234CF`. One residual: our gcc keeps the ternary as a select (`cmp ebx, 1; jge; mov ecx, 1`) where the reference constant-folds the false arm to `mov ecx, 0x34CF`. Same value, different fold; no source form controls this. |
| 8 | **Fixed.** The `_pitCommand = PIT_CMD_COUNTER2_LOHI_MODE3;` store is removed, and `PIT_CMD_COUNTER2_LOHI_MODE3` with it. `initFromDeviceDescription:` now writes only `0x188`, `0x18C` and `0x190`, as the reference does. |
| 9 | **Accepted as `intentional-mismatch`** (reviewer Pat Raynor) on both `getIntValues:` and `setIntValues:`, on the same reasoning as Finding 6's guard. The disassembly confirms the guards are the *only* difference in either method; the +24 and +4 bytes are entirely theirs. |
| 10 | **Fixed.** `- (void)beep` in both `Beep.h` and `Beep.m`; the four `return IO_R_SUCCESS;` statements are gone. Neither `IOAudio.h` nor `IODevice.h` declares `-beep`, so nothing conflicts. |
| 11 | **Fixed.** Index 0 is `{ "Plain", 1, 1, 1 }` and index 1 is `{ "Blip", 2, 3, 4 }`; the comments moved with the names. Confirmed against the reference's own `__DATA` image: all six records, names and triples, compare `OK`. The shipped `"Style" = "Plain"` now selects the single-note style, as on Apple's driver. |
| 12 | **Fixed.** `static` dropped from `defaultBeepSequences`; the symbol is `external`. `stringToStyle` keeps its `static` and stays `local`. |
| 13 | **Fixed.** `char isMute;` added ahead of the others, `timer` typed `timer_ctl_reg_t`, and all four surviving ivars renamed to `timer`, `frequency`, `duration`, `currentBeepSequence`. `reset` now assigns the four bitfields by name, and the rebuilt code is the reference's six read-modify-writes on `[ebx+0x185]` — which also confirms the offsets, since without `isMute` the control byte would sit at `0x184`. |
| 14 | **Fixed**, not accepted. `getCharValues:`/`setCharValues:` declare `char *parameterArray` in both `Beep.h` and `Beep.m`, so the encodings are `i20@8:12*16*20^I24` and `i20@8:12*16*20I24`. The tension with `src/driverkit-3/driverkit/IODevice.h:209`/`:217` turned out to be theoretical: the build compiles `Beep.m` under `-Wmost` with **no** diagnostic of any kind, so there was no build cost to weigh against metadata parity. `IODevice.h` was not touched. |
| 15 | **No change.** The three early exits still return before `inb(PPI_PORT_B)`, and the restore is still only on the fall-through. Verified in the rebuilt stream: all three jump to the shared epilogue. |
| 16 | **Fixed.** `firstItem` is gone; the separator is suppressed by `seq != defaultBeepSequences`. The rebuilt `getCharValues:` is instruction for instruction identical to the reference across all 138 instructions, which is the direct confirmation that the flag was the only thing standing between the two. |

## Residuals recorded rather than fixed

Three things remain that are visible in the binary and that this pass did not act on.

1. **`beep`'s note loop is rolled where the reference peels the first note.** Q2 calls
   the peeling a compiler transformation and not a divergence; our build simply does
   not perform it. It is why `beep` is 356 bytes against the reference's 444.
2. **The `currentFreq > 0` ternary is not constant-folded** on the false arm — see
   Finding 7.
3. **Function order in `__text` differs.** The reference emits `+[Beep probe:]` at 0,
   then `_stringToStyle` at 68, then `-[Beep reset]` at 168 and
   `-[Beep initFromDeviceDescription:]` at 268. Ours emits `_stringToStyle` first (a
   file-scope function ahead of the `@implementation`), and `reset` after `init`.
   Matching it would mean moving `stringToStyle` between `+probe:` and `-reset` and
   swapping `reset` and `initFromDeviceDescription:` in the `@implementation`. No
   finding above covers this, so it is left for a later pass to decide; it changes no
   addresses that the source map or ledger depend on, both of which are keyed to
   reference addresses.

## Ledger after this pass

| Status | Count |
| --- | --- |
| `assembly-matched` | 7 |
| `intentional-mismatch` | 6 |
| `unexamined` | 0 |

The six `intentional-mismatch` entries are the two build-generated glue methods
carried over from the report pass, the three NULL-guard retentions (`_stringToStyle`,
`getIntValues:`, `setIntValues:`) and `-[Beep beep]`, whose two residual codegen
differences are recorded above.
