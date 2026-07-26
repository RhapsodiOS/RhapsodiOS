# drvSB8Sound divergences

Reference: `SoundBlaster8.config/SoundBlaster8_reloc`, 53552 bytes,
SHA-256 `3CE9787321C1E52D62BF1B19CFC58BD6F7340A98D5C6FEAEC8B92B5E6A8EC9D4`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0 — all three enabled and all three completed.
`run-summary.json` reports `complete: true` with a non-null reference consensus and four
files in `published/`. Ghidra did **not** hit the relocation-operand normalization abort
on this driver, so no analyzer was disabled and no profile change was needed.

## Baseline build

There is no rebuilt drvSB8Sound artifact on disk: `out/i386/` contains no `drvSB8Sound`
directory, so the driver has not been built in the guest during this pass. Every
statement below is derived from the reference binary and from our source text, not from a
rebuilt binary. The `Loaded Server` section sizes our build actually produces are
therefore **unmeasured**.

Reference `Loaded Server` sections, for the fix pass to compare against once a build
exists:

| Section | Size | Content |
| --- | --- | --- |
| `Server Name` | 13 | `SoundBlaster8` |
| `Load Commands` | 144 | the audio `SMAP`/`ADVERTISE`/`WIRE` block |
| `Instance Var` | 22 | `SoundBlaster8_instance` |
| `Server Version` | 1 | `2` |

There is **no** `Unload Commands` section, matching the expectation for all four audio
drivers. Our
`SoundBlaster8.drvproj/SoundBlaster8.lksproj/Load_Commands.sect` is 144 bytes and is
**byte-identical** to the reference's `Load Commands` section (verified by `cmp` against
the section extracted at file offset 35177). That is a positive result from Task 2, not a
finding.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 27 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

All 29 reference functions land in exactly one bucket and every one carries a ledger
entry.

**No code divergence was found in any of the 27 mapped functions.** This document
therefore has one finding, and it is not about code: a help-file bundle name mismatch
inside our own tree. Everything else below is recorded as a positive result, as
supporting evidence, or as a statement of where the evidence is weaker than usual.

Note on sizes: the task brief's disposition table lists padded gap-to-next-symbol sizes
(40, 32, 16, 2176, 1440, 776, …). IDA's function bodies — which
`validate_source_map_semantics` checks against — are 37, 31, 15, 2175, 1437, 773. The
source map and ledger use IDA's sizes. All source line numbers in the brief were
re-derived from the current `SoundBlaster8.m`; every one of them had drifted by the
handful of lines the file has moved, and the values in `source-map.json` are the
re-derived ones.

## Examination depth

All 27 mapped reference functions were read **at instruction level**. Every function's
complete IDA instruction stream was dumped and read against our source.

Three inline helpers from `SoundBlaster8Inline.h` — `dspReadWait()`, `dspWriteWait()` and
the reset pulse at the head of `resetDSPQuick()` — expand to long, byte-identical
instruction runs that recur 30 times across the binary. Those three runs were read in
full once, inside `-[SoundBlaster8 initializeHardware]`. Every other occurrence was then
verified **mechanically**, by token-for-token comparison of `(mnemonic, normalized
operands)` against the run read in full, with branch targets normalised and `nop` padding
dropped. Every occurrence matched exactly. No instruction in any of the 27 functions was
skipped or assumed.

All 27 are recorded `assembly-matched` in the ledger. The two build-generated glue
methods are `intentional-mismatch`. Nothing is left `unexamined`.

Ghidra's decompiler was used as an independent cross-check on `_writeToDSP`,
`_readFromDSP`, `_clearInterrupts`, `-[SoundBlaster8 acceptsContinuousSamplingRates]` and
`-[SoundBlaster8 channelCountLimit]`, and agreed with the hand reading on every body.
**It is not usable as a cross-check on call targets** — see the analyzer-disagreement
section.

## Weaker evidence: two functions whose `source_line` is an include site

`source_map`'s `source_sites` glob matches `*.m` and `*.c` in `--source-dir`
non-recursively, so it never sees `SoundBlaster8Inline.h`, where most of this driver's
code lives. Twenty-five of the 27 mapped functions are `SoundBlaster8` methods (or
`_clearInterrupts`) defined directly in `SoundBlaster8.m`, so their `source_line` points
at a real definition and is strong evidence.

Two are not:

| Reference | Address | Size | Mapped to | Actual definition |
| --- | --- | --- | --- | --- |
| `_writeToDSP` | 0 | 37 | `SoundBlaster8.m:23` | `SoundBlaster8Inline.h:151`–`:163` |
| `_readFromDSP` | 40 | 31 | `SoundBlaster8.m:23` | `SoundBlaster8Inline.h:168`–`:182` |

`SoundBlaster8.m:23` is the `#import "SoundBlaster8Inline.h"` line — the translation unit
that pulls the definitions in, not the definitions themselves. **The fix pass must read
those two `source_line` values as include sites, not definitions.** The bodies themselves
were still read instruction by instruction against the header text; only the line number
is indirect.

## Unmapped

Two functions, one reason class.

**Build-generated glue** — `+[SoundBlaster8KernelServerInstance kernelServerInstance]` at
8872 (returns `offset _SoundBlaster8_instance`, `__DATA,__common:16460`) and
`+[SoundBlaster8Version driverKitVersionForSoundBlaster8]` at 8884 (returns `0x1F4` =
500). Emitted by the Kernel Server project type, not written by hand. Accepted; recorded
`intentional-mismatch` in the ledger.

Unlike drvBeepSound, this driver has **no** "no source counterpart" entry:
`+[SoundBlaster8 probe:]` is present in `SoundBlaster8.m:30` and matches.

Data symbols outside `__TEXT,__text` do not appear in the source map, which lists
functions only. They are covered by the `__DATA` and `_sbCardType` sections below.

## Analyzer disagreement

Function counts: IDA 29, Ghidra 28, angr 83.

**Ghidra does not detect `+[SoundBlaster8KernelServerInstance kernelServerInstance]`** at
8872 (12 bytes). It finds the other twenty-eight. This is the same omission Ghidra made
on drvBeepSound. IDA is authoritative for the partition, so it does not affect the source
map; it is recorded in that entry's `analyzer_agreement` as an IDA + angr agreement.

**For all 28 functions present in both IDA and Ghidra, and for all 29 present in both IDA
and angr, size and instruction count are identical.** There is no body disagreement
anywhere in this binary. Basic-block counts differ, which is purely each analyzer's
block-splitting convention.

**angr over-splits.** Its 83 functions include 54 addresses that are not function starts
in IDA's partition: 37, 71, 347, 585, 658, 682, 797, 849, 883, 2397, 3099, 3215, 3331,
3627, 3870, 3889, 4722, 4753, 4825, 4897, 5283, 5425, 5793, 5837, 5881, 6039, 6054, 6183,
6202, 6509, 6754, 6842, 6902, 7055, 7165, 7205, 7355, 7465, 7493, 7753, 7771, 7963, 8073,
8113, 8243, 8353, 8375, 8586, 8719, 8757, 8813, 8841, 8910, 9076. Most are interior
blocks or epilogue tails of functions IDA reports whole; the last two (8910, 9076) are
`_codecDeviceKind` and `_SoundBlaster8_VERS_NUM` in `__TEXT,__const`, i.e. angr disassembling
read-only data that happens to sit in an executable segment. This is `CFGFast` splitting on
branch targets, not a claim that different functions exist there.

Unusually for this effort, **angr reported no CFG errors on this binary** (`extensions.angr.cfg.errors`
is empty), despite the `objc_msgSend` dispatch. Do not read that as a general expectation
for the other three drivers.

**Ghidra's decompiler mis-resolves import call targets, and its output must not be used to
check them.** Under its raw i386 fallback loader Ghidra does not resolve the import
pointer table at 32976–33004, and renders every call through it as a call to whatever
`__text` symbol it last named. Concretely, its decompilation of `_writeToDSP` reads

```c
undefined4 _writeToDSP(undefined1 param_1)
{
  out(_sbWriteDataOrCommandReg,param_1);
  LOCK(); __xxx_86 = __xxx_86 + 1; UNLOCK();
  _writeToDSP(0x19);          /* this is _IODelay(25), not recursion */
  return 1;
}
```

The `_writeToDSP(0x19)` is `call near ptr _IODelay` at address 23, which IDA resolves
correctly from relocation 2. Ghidra also loses all Objective-C method names, rendering
them `binrecon_symbol_NN`. Its *bodies* agree with IDA everywhere; its *names* do not.
Every call target in this document comes from IDA's relocation-resolved disassembly.

## Positive results (not findings)

### All 19 reference `__cstring` entries are present in our source

`__TEXT,__cstring` runs from 9086 to the end of the `__TEXT` segment at 16384; the live
content ends at 9741 and the remaining 6643 bytes are zero padding. It holds exactly
nineteen non-empty strings:

| Address | String | Our source |
| --- | --- | --- |
| 9086 | `SoundBlaster8: Can not reset DSP.\n` | `SoundBlaster8Inline.h:384` |
| 9122 | `SoundBlaster8: Audio DMA channel is %d.\n` | `SoundBlaster8Inline.h:778` |
| 9163 | `SoundBlaster8: Audio DMA channel must be one of 0, 1, 3.\n` | `SoundBlaster8Inline.h:779` |
| 9221 | `SoundBlaster8: Audio irq is %d.\n` | `SoundBlaster8Inline.h:784` |
| 9254 | `SoundBlaster8: Audio IRQ must be one of 3, 5, 7, 10.\n` | `SoundBlaster8Inline.h:785` |
| 9308 | `SoundBlaster8: Invalid port address 0x%0x.\n` | `SoundBlaster8.m:76` |
| 9352 | `Classic` | `SoundBlaster8.m:121` |
| 9360 | `2.0` | `SoundBlaster8.m:124` |
| 9364 | `Pro` | `SoundBlaster8.m:127` and `:130` (coalesced) |
| 9368 | `SoundBlaster8: Hardware not detected at port 0x%0x.\n` | `SoundBlaster8.m:134` |
| 9421 | `SoundBlaster8: Sound Blaster %s (ver %d.%d) at port 0x%0x.\n` | `SoundBlaster8.m:140` |
| 9481 | `SoundBlaster8: could not set transfer width to 8 bits, error %d.\n` | `SoundBlaster8.m:159` |
| 9547 | `%s: dma transfer mode error %d\n` | `SoundBlaster8.m:166` |
| 9579 | `%s: dma auto initialize error %d` | `SoundBlaster8.m:177` |
| 9612 | `recording` | `SoundBlaster8.m:401` |
| 9622 | `playback` | `SoundBlaster8.m:401` |
| 9631 | `%s: unsupported %s mode.\n` | `SoundBlaster8.m:400` |
| 9657 | `%s: could not start DMA channel error %d\n` | `SoundBlaster8.m:439` |
| 9699 | `%s: could not enable DMA channel error %d\n` | `SoundBlaster8.m:447` |

There is a twentieth string literal in our source that is not a separate `__cstring`
entry: the `sbCardType.name = "";` at `SoundBlaster8Inline.h:406`. The reference resolves
it to address 9121 — the second of the two NUL bytes that terminate and pad the string at
9086. That is the compiler folding an empty string literal onto an existing terminator,
and it is exactly what our source produces. Confirmed at `initializeHardware`+14
(`mov ds:dword_4038, offset unk_23A1`, where `0x23A1` is 9121).

**Every extra string our source can emit sits under `#ifdef DEBUG`.** Every string
literal in both source files was enumerated and classified by whether it lies inside an
`#ifdef DEBUG` block. The unguarded set is exactly the nineteen strings in the table
above plus the `""` at `SoundBlaster8Inline.h:406`. The guarded set is:

- `SoundBlaster8.m` lines 53, 60, 207, 227, 249, 266, 341, 344, 346, 348, 351, 353, 355,
  357, 359, 392, 426, 428, 431, 433, 479, 529, 570.
- `SoundBlaster8Inline.h` lines 54, 114, 142, 159, 178, 198, 216, 242, 317, 421, 426,
  427, 455, 459, 460, 483, 548, 550, 581, 608, 641, 749, 757.

(Three of those — `SoundBlaster8Inline.h:159`, `:483` and `:641` — are themselves
commented out inside their `#ifdef DEBUG` block, so they never compile at all.
`SoundBlaster8.m:503` contains the text `"DMA block"`, but it is inside a C comment, not
a literal.)

Whether the guest build defines `DEBUG` decides whether the guarded strings appear;
either way this is expected and is not a finding in either direction. Their absence from
the reference's `__cstring` does confirm that the reference was built with `DEBUG`
undefined.

### `_codecDeviceName` and `_codecDeviceKind` are `__TEXT,__const`, matching `static const char[]`

`_codecDeviceName` at 8896 (14 bytes, `"SoundBlaster8"`) and `_codecDeviceKind` at 8910
(6 bytes, `"Audio"`), both `local` in the raw nlist. That matches
`SoundBlaster8.m:14`–`:15` exactly:

```c
static const char codecDeviceName[] = "SoundBlaster8";
static const char codecDeviceKind[] = "Audio";
```

`-[SoundBlaster8 reset]` passes `offset _codecDeviceName` at 419 and
`offset _codecDeviceKind` at 437 to `setName:` and `setDeviceKind:`, in that order,
matching `SoundBlaster8.m:98`–`:99`. **This is where drvSB8Sound differs from
drvBeepSound**, whose equivalents are mutable `__DATA,__data` arrays (drvBeepSound
Finding 4). Do not carry drvBeepSound's disposition across.

### `_writeToDSP` and `_readFromDSP` are already declared correctly

This is the item the task brief flagged as an open question, and the brief's premise is
wrong. It states that our copies are `static inline`. **They are not.**
`SoundBlaster8Inline.h:151`–`:153` and `:168`–`:170` read:

```c
static
BOOL
writeToDSP(unsigned int dataOrCommand)
```

```c
static
unsigned int
readFromDSP(void)
```

Plain `static`, with **no** `__inline__`. Every *other* helper in that header carries
`static __inline__` (`assignDSPRegAddresses`, `outbV`, `dspReadWait`, `dspWriteWait`,
`inbIXMixer`, `outbIXMixer`, `resetDSPQuick`, `resetDSP`, `resetMixer`, `startDMA`,
`setCodecSamplingRate`, and the rest). These two are the deliberate exceptions, and that
is precisely why the reference emits them out of line as `local` symbols at 0 and 40
while every other helper is inlined into its callers.

Both bodies match instruction for instruction:

```
_writeToDSP, 0..36, complete:
     0: 55               push  ebp
     1: 89E5             mov   ebp, esp
     3: 668B150C400000   mov   dx, word ptr ds:_sbWriteDataOrCommandReg
    10: 8A4508           mov   al, [ebp+arg_0]
    13: EE               out   dx, al
    14: F0FF0528400000   lock incl ds:_xxx.86
    21: 6A19             push  19h                    ; SB_DATA_WRITE_DELAY == 25
    23: E8E4FFFFFF       call  _IODelay
    28: B801000000       mov   eax, 1                 ; return YES
    33: 89EC             mov   esp, ebp
    35: 5D               pop   ebp
    36: C3               retn
```

```
_readFromDSP, 40..70, complete:
    40: 55               push  ebp
    41: 89E5             mov   ebp, esp
    43: 53               push  ebx
    44: 668B1508400000   mov   dx, word ptr ds:_sbReadDataReg
    51: EC               in    al, dx
    52: 0FB6D8           movzx ebx, al
    55: 6A0A             push  0Ah                    ; SB_DATA_READ_DELAY == 10
    57: E8C2FFFFFF       call  _IODelay
    62: 89D8             mov   eax, ebx               ; return val
    64: 8B5DFC           mov   ebx, [ebp+var_4]
    67: 89EC             mov   esp, ebp
    69: 5D               pop   ebp
    70: C3               retn
```

Both are `local` in the raw Mach-O nlist (`read_macho` reports `binding: local` for both),
matching `static`. IDA's analysis JSON reports `_writeToDSP`'s binding as `global`; that
is the same adapter artifact drvBeepSound recorded for `+[Beep probe:]`, and the raw nlist
is authoritative.

**There is nothing for the fix pass to do here.** Do not remove `inline` — there is none
to remove. Do not add `__attribute__((noinline))` — the reference has no source for it,
and none is needed. The fallback the brief describes (reclassify as
`intentional-mismatch` if removing `inline` does not reproduce the out-of-line copies)
does not arise. Both are `assembly-matched`.

The `lock incl ds:_xxx.86` after each `out dx, al` is the expansion of `outb()` from
`src/kernel-7/machdep/i386/io_inline.h`, reached through
`SoundBlaster8.h:10`'s `#import <driverkit/i386/ioPorts.h>`. `_xxx.86`, `_xxx.89` and
`_xxx.92` in `__DATA,__bss` at 16424, 16428 and 16432 are the three `static int xxx`
copies from `outb`/`outw`/`outl`; only `outb`'s is referenced. Same mechanism as
drvBeepSound.

### `Default.table` is clean

Diffing our `SoundBlaster8.drvproj/Default.table` against the reference's, the only
difference is the `"Driver Version"` line, which is out of every comparison by the shared
procedure's Global Constraints:

```
19d18
< "Driver Version" = "PROGRAM:SoundBlaster8  PROJECT:drvSB8Sound-11  DEVELOPER:root  BUILT:Sat Mar 28 22:05:29 PST 1998";
```

All eighteen remaining keys match byte for byte, including `"Help File" = "SB8.rtfd"`,
`"Valid DMA Channels" = "0 1 3"`, `"Valid IRQ Levels" = "3 5 7 10"` and
`"I/O Ports" = "0x0220-0x22f 0x200-0x207 0x388-0x389"`. Task 2's transcription is correct
and there is no Task 2 defect in the table. (The `"Valid DMA Channels"` and
`"Valid IRQ Levels"` values are the same sets `checkSelectedDMAAndIRQ()` enforces in code
— see the reset disassembly below.)

### Objective-C metadata matches exactly

`__OBJC,__instance_vars` holds four entries, matching `SoundBlaster8.h:15`–`:18` name for
name, type for type and offset for offset:

| Name | Encoding | Offset |
| --- | --- | --- |
| `currentDMADirection` | `I` | 388 (`0x184`) |
| `interruptTimedOut` | `c` | 392 (`0x188`) |
| `dmaDescriptorSize` | `I` | 396 (`0x18C`) |
| `isValidRequest` | `c` | 400 (`0x190`) |

`__cls_meth` holds exactly one method, `probe:` with encoding `c12@8:12@16`.
`__inst_meth` holds exactly 23, one for every instance method in `SoundBlaster8.m`, with
encodings that match our declarations throughout — `enableAllInterrupts` is `i8@8:12`
(`IOReturn`), `disableAllInterrupts` is `v8@8:12`, `interruptClearFunc` is `^?8@8:12`,
`interruptOccurredForInput:forOutput:` is `v16@8:12^c16^c20`, `setAnalogInputSource:` is
`v12@8:12i16`, `getDataEncodings:count:` is `v16@8:12^i16^I20`. No method is missing and
none is extra.

---

# Answers to the questions the fix pass acts on

## Q1 — Where does each side put the initialisation work?

**Both sides put it in exactly the same place. The size difference is entirely
inlining, and it is not a divergence.**

The brief flags that our `initializeHardware` (`SoundBlaster8.m:185`) is three lines
while the reference's is 2175 bytes, and that our `reset` (`:91`) is ninety-two lines
while the reference's is 576. Both differences are fully accounted for.

**`-[SoundBlaster8 initializeHardware]`, 924, 2175 bytes.** Our source is:

```c
- (void) initializeHardware
{
    resetHardware();
}
```

`resetHardware()` is `static __inline__` (`SoundBlaster8Inline.h:557`) and calls three
more `static __inline__` functions, each of which calls more. The reference's 2175 bytes
are that entire tree inlined into one method body. Reading it top to bottom, in reference
address order, against `SoundBlaster8Inline.h`:

| Reference range | Inlined from | Confirmed |
| --- | --- | --- |
| 928–968 | `resetDSP()` prologue, `:405`–`:409` | `version = 5` (`SB_NONE`), `name = ""`, `majorVersion = 0`, `minorVersion = 0`, `mixerPresent = 0` |
| 975–1026 | `resetDSP()` `:411`–`:414` | `outbV(sbResetReg,1)`, `IODelay(10)`, `outbV(sbResetReg,0)`, `IODelay(10)` |
| 1029–1123 | `dspReadWait()` `:92`–`:118` | 2000-iteration poll of `sbDataAvailableStatusReg` bit 7, then the reset-and-recover tail with `IODelay(100)` |
| 1124–1147 | `resetDSP()` `:418`–`:423` | `readFromDSP()`, `cmp 0AAh`, `IOSleep(1)` |
| 1150 | `:437` | `version = 1` (`SB_CLASSIC`) |
| 1160–1255 | `dspWriteWait()` `:120`–`:146` | poll of `sbWriteBufferStatusReg` bit 7 clear |
| 1256 | `:445` | `writeToDSP(0E0h)` = `DC_INVERT_BYTE` |
| 1269–1370 | `dspWriteWait()`, `:448` | `writeToDSP(43h)`, the test pattern |
| 1374–1468 | `dspReadWait()`, `:451` | `readFromDSP()` — its result is **not compared**, because both arms of the `val == 0xbc` test at `:453`–`:463` are `#ifdef DEBUG`-only and empty otherwise |
| 1473–1648 | `resetDSPQuick()` `:372`–`:386` | reset pulse, `dspReadWait()`, `readFromDSP() != 0xaa` → `IOLog("SoundBlaster8: Can not reset DSP.\n")` |
| 1649–1743 | `dspWriteWait()` | |
| 1744 | `:476` | `writeToDSP(0E1h)` = `DC_GET_VERSION` |
| 1757–1851 | `dspReadWait()` | one wait, then **two** consecutive reads — matching `:479`–`:480` exactly |
| 1852–1877 | `:479`–`:480` | `majorVersion = readFromDSP() & 0x0f`, `minorVersion = readFromDSP() & 0x0f` |
| 1878–1915 | `:490`–`:494` | `major >= 2 → version = 2`; `major >= 4 → version = 4`, emitted as `cmp 1/jbe` and `cmp 3/jbe` |
| 1916–2477 | `resetMixer()` `:497`–`:552` | `outbIXMixer(0,0)`; write/read-back 22h←15h and 0Ah←13h; write/read-back 2Eh←17h and 26h←19h; `mixerPresent`; on success `version = 3` (`SB_PRO`) and a second `outbIXMixer(0,0)` |
| 2480–2487 | `initMixerRegisters()` `:238`–`:239` | `if (mixerPresent == NO) return;` |
| 2493–3091 | `initMixerRegisters()` `:248`–`:284` | the eight shadow-register writes, in our source's exact order |

`initDSPRegisters()` (`:224`–`:228`) is empty and contributes nothing, as our source
implies.

**`-[SoundBlaster8 reset]`, 348, 576 bytes.** Our 92 lines and the reference's 576 bytes
correspond one to one. The only inlining here is `checkSelectedDMAAndIRQ()`
(`SoundBlaster8Inline.h:771`–`:790`), 58 bytes at 458–541:

```
 458: B001             mov  al, 1                  ; BOOL status = YES
 460: 83FE01           cmp  esi, 1                 ; channel
 463: 761F             jbe  loc_1F0                ; channel == 0 || channel == 1
 465: 83FE03           cmp  esi, 3
 468: 741A             jz   loc_1F0                ; channel == 3
 470: 56               push esi
 471: 68A2230000       push offset "SoundBlaster8: Audio DMA channel is %d.\n"
 476: E81FFEFFFF       call _IOLog
 481: 68CB230000       push offset "SoundBlaster8: Audio DMA channel must be one of 0, 1, 3.\n"
 486: E815FEFFFF       call _IOLog
 491: 30C0             xor  al, al                 ; status = NO
 493: 83C40C           add  esp, 0Ch
 496: 83FB03           cmp  ebx, 3                 ; irq
 499: 7429             jz   loc_21E
 501: 83FB05           cmp  ebx, 5
 504: 7424             jz   loc_21E
 506: 83FB07           cmp  ebx, 7
 509: 741F             jz   loc_21E
 511: 83FB0A           cmp  ebx, 0Ah
 514: 741A             jz   loc_21E
 516: 53               push ebx
 517: 6805240000       push offset "SoundBlaster8: Audio irq is %d.\n"
 522: E8F1FDFFFF       call _IOLog
 527: 6826240000       push offset "SoundBlaster8: Audio IRQ must be one of 3, 5, 7, 10.\n"
 532: E8E7FDFFFF       call _IOLog
 537: 30C0             xor  al, al
 539: 83C40C           add  esp, 0Ch
 542: 84C0             test al, al                 ; return status
 544: 0F846A010000     jz   loc_390                ; if (... == NO) return NO
```

Two details are worth naming because they look like divergences and are not.

1. **`(channel != 0) && (channel != 1)` becomes an unsigned `cmp esi, 1 / jbe`.** Our
   source at `:777` writes three inequalities; the compiler folds the first two into one
   unsigned comparison. Same predicate, fewer instructions.
2. **Both failure paths run to completion.** The reference does *not* return early after
   the DMA-channel failure; it clears `al` and falls through into the IRQ check, so a bad
   channel *and* a bad IRQ produce all four `IOLog` lines. That is exactly what our
   `BOOL status = YES; … return status;` shape produces, and it is why the `[self
   initializeHardware]` send at 550 sits *after* the combined test rather than inside
   either branch.

Everything else in `reset` is a direct send-for-send match with `SoundBlaster8.m:91`–`:182`:
`deviceDescription`/`channel`, `deviceDescription`/`interrupt`, `setName:`,
`setDeviceKind:`, `initializeHardware`, the five-arm switch on `sbCardType.version`, the
`IOLog` with four arguments, `disableChannel:0`, `isEISAPresent`,
`setDMATransferWidth:IO_8Bit forChannel:0`, `setTransferMode:IO_Single forChannel:0`,
`setAutoinitialize:YES forChannel:0`. `IO_8Bit == 0` and `IO_Single == 1` were confirmed
against `src/driverkit-3/driverkit/i386/directDevice.h:58`–`:63` and `:163`–`:169`, and
the reference pushes exactly those immediates.

**Conclusion: nothing is missing on either side.** Every piece of initialisation work in
our source appears in the reference, and every instruction in the reference's
`initializeHardware` and `reset` traces to a line in our source.

## Q2 — The `_sbCardType` layout

`_sbCardType` is `local` in `__DATA,__bss` at 16436, 20 bytes. **All five field offsets
are confirmed from the disassembly**, and they match `sbCardParameters_t`
(`SoundBlaster8Registers.h:216`–`:222`) exactly.

| Offset | Address | Field | Width | Evidence |
| --- | --- | --- | --- | --- |
| 0 | 16436 | `version` | 4 | `initializeHardware`+4 `mov ds:_sbCardType, 5`; `reset`+218 `mov eax, ds:_sbCardType` then `cmp eax, 1/2/3/4`; `channelCountLimit`+8 `cmp ds:_sbCardType, 3` |
| 4 | 16440 | `name` | 4 | `initializeHardware`+14 `mov ds:dword_4038, offset unk_23A1`; `reset`+252 `mov ds:dword_4038, offset aClassic` / `a20` / `aPro` |
| 8 | 16444 | `majorVersion` | 4 | `initializeHardware`+928 `and eax, 0Fh; mov ds:dword_403C, eax` after the first `readFromDSP`; `cmp ds:dword_403C, 1` and `cmp ds:dword_403C, 3` for the `>= 2` and `>= 4` upgrades |
| 12 | 16448 | `minorVersion` | 4 | `initializeHardware`+941 `and eax, 0Fh; mov ds:dword_4040, eax` after the second `readFromDSP` |
| 16 | 16452 | `mixerPresent` | 1 | `initializeHardware`+44 `mov ds:byte_4044, 0`; `mov ds:byte_4044, 1` at 2171 and 2388; `cmp ds:byte_4044, 0/1` in six functions |

16452 + 1 byte + 3 bytes of alignment padding = 20 bytes, which is the symbol's size.
`mixerPresent` is written and tested as a **byte**, confirming `BOOL` (`char`), not `int`.

The strongest single piece of evidence for the `name`/`majorVersion`/`minorVersion`
ordering is the `IOLog` at `reset`+336:

```
 684: 8B1500400000     mov  edx, ds:_sbBaseRegisterAddress
 690: 52               push edx
 691: 8B1540400000     mov  edx, ds:dword_4040      ; +12  minorVersion
 697: 52               push edx
 698: 8B153C400000     mov  edx, ds:dword_403C      ; +8   majorVersion
 704: 52               push edx
 705: 8B1538400000     mov  edx, ds:dword_4038      ; +4   name
 711: 52               push edx
 712: 68CD240000       push offset "SoundBlaster8: Sound Blaster %s (ver %d.%d) at port 0x%0x.\n"
 717: E82EFDFFFF       call _IOLog
```

Pushed right to left, the arguments are `(format, name, majorVersion, minorVersion,
sbBaseRegisterAddress)` — precisely `SoundBlaster8.m:140`–`:143`.

The enum values are confirmed too: the `reset` switch tests 1, 2, 3, 4 against
`SB_CLASSIC`, `SB_20`, `SB_PRO`, `SB_16`, and `initializeHardware` initialises to 5 =
`SB_NONE`, matching `SoundBlaster8Registers.h:212`–`:214`.

## Q3 — `_lowSpeedDMA`

**It has a counterpart, and the declaration matches.** `_lowSpeedDMA` is `local` in
`__DATA,__bss` at 16456, immediately after `_sbCardType`'s 20 bytes. Our source declares
it at `SoundBlaster8.m:18`:

```c
static  BOOL lowSpeedDMA;		 	// different programming
```

directly after `static sbCardParameters_t sbCardType;` at `:17`, which is why the two land
adjacent in `__bss` in that order. It is uninitialised in our source and lives in `__bss`
in the reference, which agrees.

It is written as a **byte** in all three of its assignment sites and tested with
`cmp ds:_lowSpeedDMA, 0`, confirming `BOOL`:

| Site | Reference | Our source |
| --- | --- | --- |
| `updateSampleRate`+61 | `mov ds:_lowSpeedDMA, 1` | `SoundBlaster8.m:286`, the `SB_CLASSIC` arm |
| `updateSampleRate`+129 | `mov ds:_lowSpeedDMA, al` after `setbe` | `:289`, `:291`, `:295` — see below |

Reads occur in six places: `setBufferCount:`+11, `startDMAForChannel:`+863 and +976 and
+1276, `stopDMAForChannel:`+67, `interruptOccurredForInput:`+39 and +156 and +276 and
+436. Each corresponds to a `lowSpeedDMA` test in our source.

One compiler transformation in `updateSampleRate` is worth recording so it is not
mistaken for a divergence later. Our source has three independent comparisons:

```c
} else if (sbCardType.version == SB_20) {
    if (currentDMADirection == DMA_DIRECTION_IN)
        lowSpeedDMA = (rate < SB_20_LOW_SPEED_RECORD) ? YES : NO;    /* 15000 */
    else
        lowSpeedDMA = (rate < SB_20_LOW_SPEED_PLAYBACK) ? YES : NO;  /* 23000 */
} else if (sbCardType.version == SB_PRO) {
    if (mode == DSP_STEREO_MODE)
        rate *= 2;
    lowSpeedDMA = (rate < SB_PRO_LOW_SPEED) ? YES : NO;              /* 23000 */
}
```

`SB_20_LOW_SPEED_PLAYBACK` and `SB_PRO_LOW_SPEED` are both 23000, so the compiler emits
the `cmp esi, 59D7h / setbe al` **once** and branches into it from both paths:

```
4724: cmp ds:_sbCardType, 2
4731: jnz loc_1294                    ; -> 4756, the SB_PRO test
4733: cmp dword ptr [ebx+184h], 0     ; currentDMADirection == DMA_DIRECTION_IN
4740: jnz loc_12A4                    ; -> 4772, the shared 23000 compare
4742: cmp esi, 3A97h                  ; rate <= 14999, i.e. rate < 15000
4748: setbe al
4751: jmp loc_12AD                    ; -> 4781
4756: cmp ds:_sbCardType, 3
4763: jnz loc_12B3
4765: cmp edi, 1                      ; mode == DSP_STEREO_MODE
4768: jnz loc_12A4                    ; -> 4772
4770: 01F6  add esi, esi              ; rate *= 2
4772: cmp esi, 59D7h                  ; rate <= 22999, i.e. rate < 23000
4778: setbe al
4781: mov ds:_lowSpeedDMA, al
```

That is common-subexpression elimination across two source branches, not a different
predicate. `rate < 15000` becoming `rate <= 14999` and `rate < 23000` becoming
`rate <= 22999` is the same folding.

## Q4 — `__DATA,__data` is all zeros in the reference

**Confirmed, byte for byte.** The `__data` section is 40 bytes at address 16384, file
offset 18780, and reads:

```
16384: 00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
16400: 00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
16416: 00 00 00 00  00 00 00 00
```

Every one of the sixteen symbols in it is zero at link time and is computed at run time.
The layout matches our source's declaration order in `SoundBlaster8Inline.h` exactly:

| Address | Symbol | Bytes | Our source | Written at run time by |
| --- | --- | --- | --- | --- |
| 16384 | `_sbBaseRegisterAddress` | 4 | `:14` | `+probe:`+113 |
| 16388 | `_sbResetReg` | 4 | `:21` | `assignDSPRegAddresses()`, inlined at `+probe:`+157 |
| 16392 | `_sbReadDataReg` | 4 | `:22` | same, `+probe:`+172 |
| 16396 | `_sbWriteDataOrCommandReg` | 4 | `:23` | same, `+probe:`+186 |
| 16400 | `_sbWriteBufferStatusReg` | 4 | `:25` | same, `+probe:`+191 (shares `base+0Ch` with the previous) |
| 16404 | `_sbDataAvailableStatusReg` | 4 | `:26` | same, `+probe:`+205 |
| 16408 | `_sbMixerAddressReg` | 4 | `:59` | `assignMixerRegAddresses()`, `+probe:`+220 |
| 16412 | `_sbMixerDataReg` | 4 | `:60` | same, `+probe:`+235 |
| 16416 | `_volMaster` | 1 | `:76` | `initMixerRegisters()` and `setOutputAttenuation()` |
| 16417 | `_volFM` | 1 | `:77` | `initMixerRegisters()` |
| 16418 | `_volLine` | 1 | `:78` | `initMixerRegisters()`, `setOutputAttenuation()` |
| 16419 | `_volVoc` | 1 | `:79` | `initMixerRegisters()`, `setOutputAttenuation()` |
| 16420 | `_volCD` | 1 | `:80` | `initMixerRegisters()`, `setOutputAttenuation()` |
| 16421 | `_volMic` | 1 | `:82` | `initMixerRegisters()`, `setInputGain()` |
| 16422 | `_sbRecord` | 1 | `:84` | `initMixerRegisters()`, `setInputLevel()` |
| 16423 | `_sbPlayback` | 1 | `:85` | `initMixerRegisters()`, `setCodecDataMode()` |

The eight one-byte shadow registers are `= {0}` / `= 0` initialised in our source, which is
why they sit in `__data` rather than `__bss` — an explicit zero initialiser, but a zero
one, so the section content is zero.

**Task 9 must not carry this assumption to drvSB16Sound.** SoundBlaster16's equivalents
*are* compile-time initialised, so its `__DATA,__data` will not be all zeros and its
`_sb*Reg` values must be read from the section content rather than assumed to be computed
in `probe:`. Verify before assuming either way.

The bitfield packing of the shadow registers was confirmed independently, from the
constant folding the compiler did on `initMixerRegisters()`:

- `sbStereoMixerRegister_t` (`SoundBlaster8Registers.h:198`–`:205`) declares `right:4`
  then `left:4`. The reference emits `volMaster.reg.left = 10` as
  `and ds:_volMaster, 0Fh` / `or ds:_volMaster, 0A0h` — high nibble — and
  `volMaster.reg.right = 10` as `and 0F0h` / `or 0Ah` — low nibble. `right` is the low
  nibble, matching the declaration order under little-endian bitfield allocation.
- `sbRecordingMode_t` (`:238`–`:249`): our source sets `data = 0`, then `source = 0`,
  `inputFilter = 0`, `highFreq = 1`. The compiler folds all four to
  `mov ds:_sbRecord, 8` — bit 3 — which is `highFreq`'s position given
  `rsvd1:1, source:2, highFreq:1`. Confirmed.
- `sbPlaybackMode_t` (`:260`–`:270`): `data = 0`, `outputFilter = 0`, `stereo = 1` folds
  to `mov ds:_sbPlayback, 2` — bit 1 — which is `stereo`'s position given `rsvd1:1,
  stereo:1`. Confirmed. `setCodecDataMode()` later emits `or ds:_sbPlayback, 2` and
  `and ds:_sbPlayback, 0FDh` on the same bit.

## Q5 — Where the `IOAudio` method set lands, for Tasks 7 and 9

Tasks 7 (drvES1x88Sound) and 9 (drvSB16Sound) are meant to read this rather than
re-derive it. The shared `IOAudio` override set, as drvSB8Sound implements it:

| Method | Address | Size | What the reference does |
| --- | --- | --- | --- |
| `updateInputGainLeft` | 3100 | 115 | `[self inputGainLeft]`; `gain ? gain*7/32768 : 0` as `lea/lea/shr 15`; `setInputGain()` writes `volMic` and `outbIXMixer(0Ah, volMic)` |
| `updateInputGainRight` | 3216 | 115 | identical with `inputGainRight`; both write the same single mono `volMic` register |
| `updateOutputMute` | 3332 | 557 | `enableAudioOutput(![self isOutputMuted])`; `unMuteOutput()` restores the four shadow registers, `muteOutput()` writes zeros to the same four; then `writeToDSP(0D1h)` or `writeToDSP(0D3h)` |
| `updateOutputAttenuationLeft` | 3892 | 380 | `(att+84)*15/84` as `lea [edx+edx*2+0FCh]`, `lea [edx+edx*4]`, `div 54h`; `setOutputAttenuation()` writes the **high** nibble of `volCD`, `volMaster`, `volLine`, `volVoc` in that order, then `outbIXMixer` to 22h, 28h, 04h, 2Eh |
| `updateOutputAttenuationRight` | 4272 | 380 | identical, writing the **low** nibble |
| `updateSampleRate` | 4652 | 773 | the `lowSpeedDMA` decision (Q3), then `setCodecDataMode()` and `setCodecSamplingRate()` |
| `setBufferCount:` | 5428 | 365 | `if (!lowSpeedDMA) { dspWriteWait(); writeToDSP(48h); }`, `count -= 1`, then the low and high bytes each behind a `dspWriteWait()` |
| `enableAllInterrupts` | 5796 | 41 | empty `enableCodecInterrupts()`, then `objc_msgSendSuper` — the whole body is the super send |
| `disableAllInterrupts` | 5840 | 41 | mirror image |
| `startDMAForChannel:read:buffer:bufferSizeForInterrupts:` | 6056 | 1437 | see below |
| `stopDMAForChannel:read:` | 7496 | 257 | see below |
| `interruptClearFunc` | 7772 | 12 | `mov eax, offset _clearInterrupts; retn` |
| `interruptOccurredForInput:forOutput:` | 7784 | 591 | see below |
| `timeoutOccurred` | 8376 | 210 | `if (!interruptTimedOut) { resetDSPQuick(); interruptTimedOut = YES; }` |
| `setAnalogInputSource:` | 8588 | 131 | `0C8h`/`0C9h` = `NX_SoundDeviceAnalogInputSource_Microphone`/`_LineIn`; default shares the microphone path; writes `sbRecord.reg.source` and `outbIXMixer(0Ch, …)` |
| `acceptsContinuousSamplingRates` | 8720 | 12 | `mov eax, 1; retn` |
| `getSamplingRatesLow:high:` | 8732 | 25 | `*low = 0FA0h` (4000), `*high = 0AC44h` (44100) |
| `getSamplingRates:count:` | 8760 | 53 | 4000, 8000, 11025 (`2B11h`), 22050 (`5622h`), 44100; `*count = 5` |
| `getDataEncodings:count:` | 8816 | 25 | `enc[0] = 259h` = 601 = `NX_SoundStreamDataEncoding_Linear8`; `*count = 1` |
| `channelCountLimit` | 8844 | 26 | `sbCardType.version == SB_PRO ? 2 : 1` |

**The DMA start sequence**, `startDMAForChannel:read:buffer:bufferSizeForInterrupts:`, in
reference order:

1. `isValidRequest = [self isValidRequest:isRead]` → ivar at `0x190` (6091–6098).
2. `interruptTimedOut = NO` → ivar at `0x188` (6104).
3. If invalid: `IOLog("%s: unsupported %s mode.\n", [self name], isRead ? "recording" :
   "playback")`, then **`return YES` on the read path and `NO` on the write path**
   (6168–6178). That asymmetry is real and deliberate; it is in our source at
   `SoundBlaster8.m:403`–`:406`.
4. `currentDMADirection` → ivar at `0x184`, 0 for read and 1 for write (6190/6204).
5. `if (![self isOutputMuted]) enableAudioOutput(isRead ? NO : YES)` (6214–6761).
6. `[self updateSampleRate]` (6776).
7. `dmaDescriptorSize = bufferSize` → ivar at `0x18C` (6784).
8. `[self startDMAForBuffer:buffer channel:localChannel]`, error → `IOLog` + `return NO`
   (6802–6840).
9. `[self enableChannel:localChannel]`, error → `IOLog` + `return NO` (6852–6897).
10. `(void)[self enableAllInterrupts]` (6911).
11. **Order matters here, and the reference honours it.** If `lowSpeedDMA`:
    `startDMA(dir)` then `[self setBufferCount:dmaDescriptorSize]` (6919–7200).
    Otherwise: `[self setBufferCount:…]` then `startDMA(dir)` (7208–7473).
12. `return YES`.

`startDMA()` is inlined at all four sites and re-tests `lowSpeedDMA` itself, which is why
`cmp ds:_lowSpeedDMA, 0` appears twice per arm. The four DSP commands are `24h`
(`DC_START_LS_DMA_ADC_8`), `99h` (`DC_START_HS_DMA_ADC_8`), `14h`
(`DC_START_LS_DMA_DAC_8`) and `91h` (`DC_START_HS_DMA_DAC_8`).

**`stopDMAForChannel:read:`**: guard on `isValidRequest`; `writeToDSP(0D0h)`
(`DC_HALT_DMA`); `[self disableAllInterrupts]`; `[self disableChannel:localChannel]`;
`if (lowSpeedDMA == NO) resetDSPQuick()`. Note that the reference contains **no test of
`isRead`** — the `mov dl, [ebp+arg_C]` at 7503 loads it and never uses it. That is the
compiler merging our source's identical `stopDMAInput()` and `stopDMAOutput()` arms
(`SoundBlaster8Inline.h:687`–`:700`, both of which call `stopDMA()`). Not a divergence.

**`interruptOccurredForInput:forOutput:`**: `inb(sbDataAvailableStatusReg)` to
acknowledge; then `*serviceOutput = YES` if `currentDMADirection == DMA_DIRECTION_OUT`
else `*serviceInput = YES`; then `startDMA(dir)`, followed by
`[self setBufferCount:dmaDescriptorSize]` **only on the `lowSpeedDMA` path**. The
high-speed path ends at the `writeToDSP` with no `setBufferCount:` send, which is exactly
what our commented-out line at `SoundBlaster8.m:554` describes.

**`interruptClearFunc` and `_clearInterrupts`**: the C function at 7756 is 15 bytes, all
of it `inb(sbDataAvailableStatusReg)`. It is `local` in the raw nlist, matching
`static void clearInterrupts(void)` at `SoundBlaster8.m:511`, and
`-[SoundBlaster8 interruptOccurredForInput:forOutput:]` duplicates the same `inb` inline
at 7798 rather than calling it, matching `SoundBlaster8.m:536`.

---

# Findings

## Finding 1: the help-file bundle in our tree is named `SB8_3_31.rtfd`, but the table names `SB8.rtfd`

**Source:** `src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/Default.table:17`
and
`src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/English.lproj/DriverHelp/SB8_3_31.rtfd/`

**This is not a Task 2 defect, and it is not a table divergence.** Task 2 transcribed
Apple's value correctly. Apple's shipped
`SoundBlaster8.config/Default.table` and ours both read:

```
"Help File" = "SB8.rtfd";
```

and Apple's shipped bundle is `SoundBlaster8.config/English.lproj/Help/SB8.rtfd`. The
mismatch is entirely internal to our tree: our `Default.table` names `SB8.rtfd` while the
bundle on disk is `English.lproj/DriverHelp/SB8_3_31.rtfd`. The driver's help panel would
not resolve.

**drvSB8Sound is the only one of the four in this state.** The other three are
self-consistent, and in each of those our bundle name also equals Apple's shipped bundle
name:

| Driver | Our `"Help File"` | Our bundle | Apple's shipped bundle |
| --- | --- | --- | --- |
| drvBeepSound | `Beep.rtfd` | `DriverHelp/Beep.rtfd` | `Help/Beep.rtfd` |
| **drvSB8Sound** | **`SB8.rtfd`** | **`DriverHelp/SB8_3_31.rtfd`** | **`Help/SB8.rtfd`** |
| drvES1x88Sound | `ES1x88_3_30.rtfd` | `DriverHelp/ES1x88_3_30.rtfd` | `Help/ES1x88_3_30.rtfd` |
| drvSB16Sound | `SB16_3_31.rtfd` | `DriverHelp/SB16_3_31.rtfd` | `Help/SB16_3_31.rtfd` |

So the anomaly is our *bundle name*, not the table value: `SB8_3_31.rtfd` follows the
`_3_31` convention that Apple used for SB16 but not for SB8. Our copy most likely came
from a different revision of the driver.

**Disposition:** the two available resolutions are not equivalent.

- **Rename the bundle** `English.lproj/DriverHelp/SB8_3_31.rtfd` →
  `English.lproj/DriverHelp/SB8.rtfd`. This makes our tree self-consistent *and* matches
  Apple's shipped layout on both the table value and the bundle name. This is the
  parity-preserving fix and is the one I recommend.
- **Change the table** back to `"SB8_3_31.rtfd"`. This also makes the tree
  self-consistent, but it reintroduces a divergence from Apple's `Default.table` — the
  one Task 2 removed — and would have to be recorded as an `intentional-mismatch` with a
  reason.

The task brief anticipates the second and asks Task 6 to record it as
`intentional-mismatch`. That disposition is available, but note that it is a *choice to
diverge*, not a forced one: the first option costs nothing and diverges from Apple in
neither the table nor the bundle name. Neither option affects any of the 29 functions, so
this finding has no ledger entry either way.
