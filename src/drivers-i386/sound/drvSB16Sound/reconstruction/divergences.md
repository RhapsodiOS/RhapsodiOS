# drvSB16Sound divergences

Reference: `SoundBlaster16.config/SoundBlaster16_reloc`, 58224 bytes,
SHA-256 `08EC130B85B64E289B17DC32DBE9D69D56FF48DAA9E4CD26FA935DDFC52A9001`
Analyses: IDA 9.2 and angr 9.3.0. **Ghidra 12.1 is disabled for this driver.**
`run-summary.json` reports `complete: true` with a non-null reference consensus and three
files in `published/`.

## Stated limitation: the analyzer set is reduced to two

Ghidra reaches the end of its own analysis on this binary but `normalize.py:432` then
rejects its output with `Ghidra relocation operand metadata is ambiguous`, which writes
`complete: false` and no consensus. This is the failure the shared procedure names, and
the approved response was taken: `analyzers.ghidra.enabled` was set to `false` in
`tools/binrecon/profiles/soundblaster16.json` in its own commit, and the run was repeated
with IDA and angr. **Every statement in this document therefore rests on two analyzers,
not the three drvBeepSound and drvSB8Sound had.** The analyzer-disagreement section below
covers IDA against angr only, and `published/` holds three files rather than four.

The same environmental note drvES1x88Sound recorded applies here and is not a property of
the binary. This report was produced in a `git worktree` under
`D:\RhapsodiOS\.claude\worktrees\audio-recon`. Ghidra's headless launcher refuses any
project path containing a dot-prefixed element, so the first run failed with the
uninformative `Ghidra failed with exit code 1` before Ghidra ever looked at the input.
`tools/binrecon/out/soundblaster16` was redirected through a directory junction to
`D:\binrecon-sb16-out`, at which point Ghidra ran to completion and produced the *real*
normalization failure above. The junction is outside the repository and affects only
gitignored analyzer output.

## Baseline build

**Unmeasured, and the driver does not currently compile.**
`SoundBlaster16.m:270` reads

```c
        ioReturn = [self setDMATransferWidth:IO_16Bit forChannel:1];
```

and `IO_16Bit` is not a member of `IOEISADMATransferWidth`
(`src/driverkit-3/driverkit/i386/directDevice.h:163`–`:169` declares `IO_8Bit`,
`IO_16BitWordCount`, `IO_16BitByteCount`, `IO_32Bit`). This is the same defect
drvES1x88Sound carried. It is verified at line 270. **Task 10 must repair it as a
baseline-build fix in its own commit before any parity work**; the correct value is
`IO_16BitByteCount`, which is what the reference pushes — see Finding 13.

Every statement below is therefore derived from the reference binary and from our source
text alone.

Reference `Loaded Server` sections, read from the Mach-O section table:

| Section | Size | Content |
| --- | --- | --- |
| `Server Name` | 14 | `SoundBlaster16` |
| `Load Commands` | 210 | the audio `SMAP`/`ADVERTISE`/`WIRE` block |
| `Instance Var` | 23 | `SoundBlaster16_instance` |
| `Server Version` | 1 | `2` |

There is **no** `Unload Commands` section, matching the expectation for all four audio
drivers, and `Load Commands` is 210 bytes as the shared procedure predicts for this driver
alone. Our `SoundBlaster16.drvproj/SoundBlaster16.lksproj/Load_Commands.sect` is 210 bytes
and is **byte-identical** to the reference's `Load Commands` section, verified against the
section extracted at file offset 35178. That is a positive result, not a finding.

`__TEXT,__const` holds `_codecDeviceName` (13572, `"SoundBlaster16"`), `_codecDeviceKind`
(13587, `"Audio"`), and the SGS build stamp
`@(#)PROGRAM:SoundBlaster16  PROJECT:drvSB16Sound-23  DEVELOPER:root  BUILT:Sat Mar 28
22:04:47 PST 1998` plus the `"23"` version number, the last two emitted by Apple's build
and out of every comparison by the Global Constraints. The two device-name symbols are
`local`, matching `SoundBlaster16.m:15`–`:16`'s `static const char[]`; `-[SoundBlaster16
reset]` passes them to `setName:` (1315) and `setDeviceKind:` (1332) in that order,
matching `:95`–`:96`. This follows drvSB8Sound and drvES1x88Sound, not drvBeepSound.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 26 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

All 28 reference functions land in exactly one bucket and every one carries a ledger entry.

Ledger status counts as this report pass leaves them: `assembly-matched` 11,
`unexamined` 15, `intentional-mismatch` 2. The fifteen `unexamined` entries are the fifteen
functions carrying a divergence; per the drvPCIBus convention their status is held here and
advancing it is Task 10's job.

**The asymmetry runs one way and it is small.** There is no reference function our source
lacks, and — unlike drvES1x88Sound — **there is no method in our source without a reference
counterpart.** `__OBJC,__inst_meth` holds exactly 24 entries and `__OBJC,__cls_meth`
exactly one, and they are precisely the 24 instance methods and one class method our
`SoundBlaster16.m` defines, name for name. Nothing is excised in this driver.

Note on sizes: the ledger and source map use IDA's function-body sizes (285, 988, 396,
2991, 446, 261, 261, 492, 309, 309, 549, 15, 41, 41, 1873, 826, 96, 12, 137, 3030, 7, 12,
25, 60, 32, 12, 12, 12), not the padded gap-to-next-symbol sizes the task brief quotes
(2992 for `initializeHardware`, 3032 for `timeoutOccurred`, and so on).
`validate_source_map_semantics` enforces the former. All source line numbers were
re-derived from the current `SoundBlaster16.m`.

## The classification every function carries

This is the section Task 10's authorisation depends on. Each of the 26 hand-written
functions carries one of three classifications: **invented** ("the source does not
implement the reference's logic at all"), **divergent** ("the source implements the
reference's logic with specific differences"), or **matches** ("the source implements the
reference's logic and no difference was found"). Only **invented** authorises a rewrite;
**matches** is the strongest statement in the table and authorises nothing at all. No
function here is invented, so the classification is `divergent` or `matches` throughout.

| Reference function | Address | Size | Our source | Classification |
| --- | --- | --- | --- | --- |
| `+[SoundBlaster16 probe:]` | 0 | 285 | `.m:30` | **matches** — no divergence found |
| `-initializeDMAChannels` | 288 | 988 | `.m:163` | **divergent** — Findings 10, 11, 12, 13 |
| `-reset` | 1276 | 396 | `.m:87` | **divergent** — Findings 1, 3 |
| `-initializeHardware` | 1672 | 2991 | `.m:294` | **divergent** — Findings 1–9 |
| `-initializeLastStageGainRegisters` | 4664 | 446 | `.m:300` | **divergent** — Findings 2, 14 |
| `-updateInputGainLeft` | 5112 | 261 | `.m:341` | **divergent** — Findings 2, 16 |
| `-updateInputGainRight` | 5376 | 261 | `.m:366` | **divergent** — Findings 2, 15, 16 |
| `-updateOutputMute` | 5640 | 492 | `.m:393` | **divergent** — Findings 2, 16, 17 |
| `-updateOutputAttenuationLeft` | 6132 | 309 | `.m:422` | **divergent** — Findings 2, 16 |
| `-updateOutputAttenuationRight` | 6444 | 309 | `.m:452` | **divergent** — Findings 2, 15, 16 |
| `-updateSampleRate` | 6756 | 549 | `.m:484` | **divergent** — Findings 3, 4, 11, 22 |
| `-setBufferCount:` | 7308 | 15 | `.m:579` | **matches** — no divergence found |
| `-enableAllInterrupts` | 7324 | 41 | `.m:584` | **matches** — no divergence found |
| `-disableAllInterrupts` | 7368 | 41 | `.m:590` | **matches** — no divergence found |
| `-startDMAForChannel:read:buffer:bufferSizeForInterrupts:` | 7412 | 1873 | `.m:596` | **divergent** — Findings 4, 11, 16, 18 |
| `-stopDMAForChannel:read:` | 9288 | 826 | `.m:723` | **divergent** — Findings 4, 11, 19 |
| `_clearInterrupts` | 10116 | 96 | `Inline.h:470` | **divergent** — Findings 3, 20 |
| `-interruptClearFunc` | 10212 | 12 | `.m:772` | **matches** — no divergence found |
| `-interruptOccurredForInput:forOutput:` | 10224 | 137 | `.m:778` | **divergent** — Findings 3, 20, 21 |
| `-timeoutOccurred` | 10364 | 3030 | `.m:820` | **divergent** — Findings 1–9, inherited whole |
| `-setAnalogInputSource:` | 13396 | 7 | `.m:832` | **matches** — no divergence found |
| `-acceptsContinuousSamplingRates` | 13404 | 12 | `.m:842` | **matches** — no divergence found |
| `-getSamplingRatesLow:high:` | 13416 | 25 | `.m:847` | **matches** — no divergence found |
| `-getSamplingRates:count:` | 13444 | 60 | `.m:854` | **matches** — no divergence found |
| `-getDataEncodings:count:` | 13504 | 32 | `.m:866` | **matches** — no divergence found |
| `-channelCountLimit` | 13536 | 12 | `.m:874` | **matches** — no divergence found |

**No function in this driver is invented.** Every one of the 26 implements the reference's
logic; fifteen do so with differences, eleven with none found. **Task 10 has no
whole-method rewrite authorisation from this document.**

Three sub-blocks *inside* divergent methods do have no counterpart in the reference and
Task 10 may replace them wholesale rather than adjusting them — they are named as such in
Findings 5, 6 and 8, and each is a block inside `SoundBlaster16Inline.h`, not a method:

- the card-type classification in `resetDSP()` (`Inline.h:388`–`:404`), which derives the
  card version from the DSP version number where the reference derives it from a mixer
  register probe;
- the DSP-presence test, which our `resetDSP()` ends after the `0xAA` check and the
  reference continues with two invert-byte probes;
- the register set `initMixerRegisters()` writes, which is the MC16 address block where
  the reference writes the CT1745 block.

**Beware the drvSB8Sound lesson, and note that it holds here.** The two functions the task
brief flagged as suspect — `initializeHardware` at 2991 bytes against our six lines and
`timeoutOccurred` at 3030 against our twelve — are **structurally exact**. Both expand
`resetHardware()` (`Inline.h:421`–`:429`) and its call tree inline, and the reference's
method bodies reduce to:

```c
- (void) initializeHardware              - (void) timeoutOccurred
{                                        {
    resetHardware(&sbCardType);              if (interruptTimedOut == NO) {
    [self initializeLastStageGainRegisters];     resetHardware(&sbCardType);
}                                                IOLog("%s: reset hardware.\n",
                                                      [self name]);
                                                 interruptTimedOut = YES;
                                             }
                                         }
```

which is `SoundBlaster16.m:294`–`:298` and `:820`–`:827` line for line. The
`[self initializeLastStageGainRegisters]` send sits at 4638 at the very end of
`initializeHardware`; the `interruptTimedOut` test is `cmp byte ptr [eax+188h], 0` at
10376 and the store `mov byte ptr [eax+188h], 1` at 13377, with `IOLog("%s: reset
hardware.\n", [self name])` at 13346–13369 immediately before it. The entire 6021-byte gap
is inlining, and every divergence in these two methods lives in the inline helpers, not in
the method bodies. That is Findings 1 through 9.

## Examination depth

Twenty-four of the 26 mapped functions were read **at instruction level**, top to bottom,
against our source, from IDA's relocation-resolved instruction stream with `__cstring`,
`__message_refs` and `__DATA` symbol references decoded.

The two exceptions are the two giants. `-[SoundBlaster16 initializeHardware]` (798
instructions) was read in full. `-[SoundBlaster16 timeoutOccurred]` (807 instructions) was
read in full at its head and tail — the `interruptTimedOut` guard, the `IOLog` and the flag
store — and its 2990-instruction-byte middle was verified **mechanically** against
`initializeHardware`'s, on `(mnemonic, normalized operands)` with branch targets
normalised. The two bodies are the same inlined `resetHardware()` expansion and every
`__cstring` reference, `_sbCardType` store and register immediate occurs in the same order
in both (`DSP read error` / `DSP write error` ×3 pairs, `SoundBlaster not detected`,
`_sbCardType` ← 4, 3, then the `cmp 4` gate and ← 1). No instruction was skipped or
assumed, but that mechanical step is weaker than a fresh reading and is recorded as such.

Within every function, the `outbIXMixer()` expansion (`out dx,al` / `lock incl _xxx.86` /
`IODelay(15)` / `out dx,al` / `lock incl _xxx.86` / `IODelay(75)`, 14 instructions) recurs
roughly 90 times and the DSP wait loop (29 instructions) exactly 29 times. Each distinct
expansion was read in full once and every later occurrence checked on `(mnemonic,
operands)` with only the port address and data immediate varying. Every occurrence matched.

Eleven functions carry `assembly-matched`; fifteen diverge and are held `unexamined`. The
two build-generated glue methods are `intentional-mismatch`.

Ghidra's decompiler was **not** available as an independent cross-check on this driver.

## Weaker evidence: one function whose `source_line` is an include site

`source-map`'s `source_sites` glob matches `*.m` and `*.c` in `--source-dir`
non-recursively, so it never sees `SoundBlaster16Inline.h`, where most of this driver's
code lives.

| Reference | Address | Size | Mapped to | Actual definition |
| --- | --- | --- | --- | --- |
| `_clearInterrupts` | 10116 | 96 | `SoundBlaster16.m:23` | `SoundBlaster16Inline.h:468`–`:499` |

`SoundBlaster16.m:23` is the `#import "SoundBlaster16Inline.h"` line — the translation unit
that pulls the definition in, not the definition itself. **Task 10 must read that
`source_line` as an include site, not a definition.** This follows the precedent
drvSB8Sound set for `_writeToDSP`/`_readFromDSP` and drvES1x88Sound for its own
`_clearInterrupts`. The body itself was read instruction by instruction against the header
text; only the line number is indirect.

**`_clearInterrupts` is 96 bytes here against 15 in drvES1x88Sound and 15 in
drvSB8Sound.** It does materially more work on this card: where the other two are a single
`inb()` of the data-available status register, this one selects mixer register `82h`
(`MC16_IRQ_STATUS`), waits, reads the interrupt-status byte, stores it in
`_interruptStatus`, and then acknowledges either the 16-bit or the 8-bit interrupt by
reading `_sbAck16bitInterrupt` or `_sbAck8bitInterrupt`. Our `clearInterrupts()` does the
same; see Finding 20 for the two differences.

Our `clearInterrupts()` is `static __inline__`, yet the reference emits it out of line at
10116. That is not a divergence: `-[SoundBlaster16 interruptClearFunc]` takes its address
(`mov eax, offset _clearInterrupts` at 10215), which forces an out-of-line copy. The symbol
is `local` in the raw nlist, matching `static`. Every other helper in that header —
`assignDSPRegAddresses`, `assignMixerRegAddresses`, `outbV`, `outbIXMixer`, `dspReadWait`,
`dspWriteWait`, `initMixerRegisters`, `resetDSP`, `resetMixer`, `resetHardware`,
`stopDMATransfer`, `programDMASelect` — is inlined into its callers and has no symbol,
which is what our `static __inline__` qualifiers predict. `writeToDSP` and `readFromDSP`
are declared plain `static` in our header (`:181`, `:201`), as in drvSB8Sound, but unlike
drvSB8Sound the reference emits **no** out-of-line copy of either — Apple's SoundBlaster16
has no such helpers at all, and writes every DSP byte inline. See Finding 4.

## Unmapped

Two functions, one reason class.

**Build-generated glue** — `+[SoundBlaster16KernelServerInstance kernelServerInstance]` at
13548 (returns `offset _SoundBlaster16_instance`, `__DATA,__common:16552`) and
`+[SoundBlaster16Version driverKitVersionForSoundBlaster16]` at 13560 (returns `0x1F4` =
500). Emitted by the Kernel Server project type, not written by hand. Accepted; recorded
`intentional-mismatch` in the ledger.

Like drvSB8Sound and drvES1x88Sound and unlike drvBeepSound, this driver has **no** "no
source counterpart" entry: `+[SoundBlaster16 probe:]` is present at `SoundBlaster16.m:30`.

Data symbols outside `__TEXT,__text` do not appear in the source map. They are covered by
the `__DATA` section below.

## Analyzer disagreement

Function counts: IDA 28, angr 79. Ghidra did not contribute.

**Every one of IDA's 28 functions is present in angr at the same address, with identical
size and identical instruction count.** There is no body disagreement anywhere in this
binary. Basic-block counts differ, which is purely each analyzer's block-splitting
convention.

**angr over-splits.** Its 79 functions include 51 addresses that are not function starts in
IDA's partition: 285, 429, 450, 646, 662, 697, 710, 721, 749, 762, 927, 1134, 1193, 1231,
1398, 1501, 1585, 1597, 2523, 4663, 5110, 5373, 5637, 5875, 6441, 6753, 6942, 7261, 7286,
7305, 7323, 7365, 7409, 7838, 7887, 7946, 8105, 8658, 9285, 9462, 9718, 10114, 10186,
10302, 10335, 10361, 11231, 13394, 13403, 13441, 13587. Most are interior blocks, epilogue
tails, or the one-to-three-byte alignment padding between IDA's function bodies and the
next symbol; 13587 is `_codecDeviceKind` in `__TEXT,__const`, i.e. angr disassembling
read-only data that happens to sit in an executable segment. This is `CFGFast` splitting on
branch targets, not a claim that different functions exist there.

`consensus-reference.json` reports `reference_consensus.status: "disputed"` with reason
`conflicting reference evidence`, produced by that over-splitting. **drvSB8Sound's
three-analyzer run and drvES1x88Sound's two-analyzer run report exactly the same status for
the same reason**, so this is the normal shape of a consensus document in this effort and
not a signal about SoundBlaster16.

As on drvSB8Sound and drvES1x88Sound, **angr reported no CFG errors on this binary**
(`extensions.angr.cfg.errors` is empty) despite the `objc_msgSend` dispatch.

---

# Positive results (not findings)

## All four tables are clean

Diffing our `SoundBlaster16.drvproj/Default.table`, `SB16PnP.table`,
`SB16SingleDMAChannelPnP.table` and `SingleDMAChannel.table` against Apple's shipped copies
in `SoundBlaster16.config/`, the only difference in each of the four is the
`"Driver Version"` line, which is out of every comparison by the Global Constraints:

```
=== Default.table
19a20
> "Driver Version" = "PROGRAM:SoundBlaster16  PROJECT:drvSB16Sound-23  DEVELOPER:root  BUILT:Sat Mar 28 22:04:50 PST 1998";
=== SB16PnP.table
21a22
> "Driver Version" = "PROGRAM:SoundBlaster16  PROJECT:drvSB16Sound-23  DEVELOPER:root  BUILT:Sat Mar 28 22:04:50 PST 1998";
=== SB16SingleDMAChannelPnP.table
21a22
> "Driver Version" = "PROGRAM:SoundBlaster16  PROJECT:drvSB16Sound-23  DEVELOPER:root  BUILT:Sat Mar 28 22:04:50 PST 1998";
=== SingleDMAChannel.table
19a20
> "Driver Version" = "PROGRAM:SoundBlaster16  PROJECT:drvSB16Sound-23  DEVELOPER:root  BUILT:Sat Mar 28 22:04:50 PST 1998";
```

Every other key matches byte for byte, including `"Valid IRQ Levels" = "5 7 9 10"`,
`"Valid DMA Channels"` and `"Help File" = "SB16_3_31.rtfd"`. **There is no Task 2 defect
in any of the four tables.**

`"Help File" = "SB16_3_31.rtfd"` matches our bundle name
(`English.lproj/DriverHelp/SB16_3_31.rtfd`) and Apple's shipped
`English.lproj/Help/SB16_3_31.rtfd`, so there is no help-file finding here and
**`SB16_3_31.rtfd` must not be renamed.** drvSB8Sound's rename does not generalise.

## `+[SoundBlaster16 probe:]` matches

Read in full at 0–284. `[self alloc]`, `nil` test, `[dd portRangeList]`,
`[dd numPortRanges]`, the signed `test eax,eax / jle` bound test matching our `int
numPortRanges`, `portRangeList[0].start` as `mov eax,[ebx]`, the four base-address
comparisons `220h`/`240h`/`260h`/`280h` in our source's order, `_sbBaseRegisterAddress`
store, `IOLog("SoundBlaster16: Invalid port address 0x%0x.\n", baseAddress)` and `[dev
free]` on the failure arm, then `assignDSPRegAddresses()` and `assignMixerRegAddresses()`
inlined at 140–250 writing `_sbResetReg` (`base+6`), `_sbReadDataReg` (`base+0Ah`),
`_sbWriteDataOrCommandReg` and `_sbWriteBufferStatusReg` (both `base+0Ch`),
`_sbDataAvailableStatusReg` and `_sbAck8bitInterrupt` (both `base+0Eh`),
`_sbAck16bitInterrupt` (`base+0Fh`), `_sbMixerAddressReg` (`base+4`) and `_sbMixerDataReg`
(`base+5`), then `[dev initFromDeviceDescription:dd] != nil` as `test eax,eax / setnz al /
and eax,0FFh`. Every instruction traces to `SoundBlaster16.m:30`–`:85` and
`SoundBlaster16Inline.h:26`–`:73`.

**Both `sbAck8bitInterrupt` and `sbAck16bitInterrupt` have counterparts here**, at
`__DATA,__data:16420` and `:16424`. Do not carry drvES1x88Sound's Finding 6 across: on that
driver they were extra, on this one they are Apple's.

## The `IOAudio` parameter accessors match exactly

| Method | Reference | Our source |
| --- | --- | --- |
| `acceptsContinuousSamplingRates` | `mov eax, 1` | `return YES;` `.m:844` |
| `getSamplingRatesLow:high:` | `*low = 1388h` (5000), `*high = 0AFC8h` (45000) | `.m:850`–`:851` |
| `getSamplingRates:count:` | 5000, `1F40h`, `2B11h`, `5622h`, `0AC44h`, `0AFC8h`; `*count = 6` | `.m:857`–`:863` |
| `getDataEncodings:count:` | `enc[0] = 259h` (601, `Linear8`), `enc[1] = 258h` (600, `Linear16`); `*count = 2` | `.m:869`–`:871` |
| `channelCountLimit` | `mov eax, 2` | `.m:876` |
| `setAnalogInputSource:` | empty body, 7 bytes | `.m:834` `return;` |
| `setBufferCount:` | `mov ds:_sbBufferCounter, eax` | `.m:581` |
| `enableAllInterrupts` | `objc_msgSendSuper(enableAllInterrupts)` | `.m:587` |
| `disableAllInterrupts` | `objc_msgSendSuper(disableAllInterrupts)` | `.m:593` |
| `interruptClearFunc` | `mov eax, offset _clearInterrupts` | `.m:775` |

`NX_SoundStreamDataEncoding_Linear16 = NX_SoundStreamParameterValueBase = 600` and
`_Linear8 = 601` were confirmed against
`src/driverkit-3/driverkit/NXSoundParameterTags.h:32` and `:73`–`:74`, so the reference's
`259h` then `258h` is exactly our source's `Linear8` then `Linear16`.

## Objective-C metadata: the method set is complete on both sides

**SoundBlaster16 declares exactly one class method, `probe:`**, with encoding
`c12@8:12@16`. `__OBJC,__cls_meth` itself is 60 bytes and holds **three** single-entry
method lists, one per class in the module — `probe:` (imp 0, the `SoundBlaster16` class
list), `driverKitVersionForSoundBlaster16` (imp 13548) and `kernelServerInstance`
(imp 13560), the latter two being the build-generated glue classes recorded under
*Unmapped*. Only the first belongs to `SoundBlaster16`.
`__OBJC,__inst_meth` is 296 bytes: one list of exactly 24, and they are our 24 instance
methods with matching
encodings throughout: `enableAllInterrupts` is `i8@8:12` (`IOReturn`),
`disableAllInterrupts` is `v8@8:12`, `interruptClearFunc` is `^?8@8:12`,
`interruptOccurredForInput:forOutput:` is `v16@8:12^c16^c20`, `setAnalogInputSource:` is
`v12@8:12i16`, `setBufferCount:` is `v12@8:12i16`, `stopDMAForChannel:read:` is
`v13@8:12I16c20`, `startDMAForChannel:read:buffer:bufferSizeForInterrupts:` is
`c24@8:12I16c20^v24I28`, `getDataEncodings:count:` is `v16@8:12^i16^I20`. **No method is
missing and none is extra.**

Every `imp` field points at one of IDA's 28 function addresses, and every one of the 61
names in `__OBJC,__meth_var_names` is either one of those 25 selectors or a selector our
source sends. The pool contains **no `stringValue`** — see Finding 14.

---

# Answers to the three specific questions

## Q1 — The IRQ set: `{5, 7, 9, 10}`, tested `5`, `7`, then the range `9..10`

**Our `-[SoundBlaster16 reset]` already agrees with the reference exactly. The
contradiction is confined to dead code.**

`-[SoundBlaster16 reset]`, 1352–1391:

```
 1352: 83FE05           cmp  esi, 5              ; interrupt
 1355: 742B             jz   loc_578             ; -> 1400, status = YES
 1357: 83FE07           cmp  esi, 7
 1360: 7426             jz   loc_578
 1362: 8D46F7           lea  eax, [esi-9]        ; interrupt - 9
 1365: 83F801           cmp  eax, 1
 1368: 761E             jbe  loc_578             ; unsigned: 9 <= interrupt <= 10
 1370: 56               push esi
 1371: 6867360000       push offset "SoundBlaster16: Audio irq is %d.\n"
 1376: E89BFAFFFF       call _IOLog
 1381: 6889360000       push offset "SoundBlaster16: Audio IRQ must be one of 5, 7, 9, 10.\n"
 1386: E891FAFFFF       call _IOLog
 1391: 31D2             xor  edx, edx            ; status = NO
 1393: 83C40C           add  esp, 0Ch
 1396: EB07             jmp  loc_57D             ; -> 1405, skipping the status = YES arm
 1400: BA01000000       mov  edx, 1              ; status = YES
 1405: 84D2             test dl, dl
 1407: 7455             jz   loc_5D6             ; return NO
```

**The accepted set is exactly `{5, 7, 9, 10}`, and the test order is `== 5`, `== 7`, then
`9 <= irq <= 10` folded into one unsigned range compare.** That is
`SoundBlaster16.m:101`–`:108` character for character:

```c
    if ((interrupt == 5) || (interrupt == 7) ||
        (interrupt >= 9 && interrupt <= 10)) {
        status = YES;
    } else {
        IOLog("SoundBlaster16: Audio irq is %d.\n", interrupt);
        IOLog("SoundBlaster16: Audio IRQ must be one of 5, 7, 9, 10.\n");
        status = NO;
    }
```

The `lea eax,[esi-9] / cmp eax,1 / jbe` is the compiler folding `>= 9 && <= 10` into a
single unsigned comparison, the same transformation drvSB8Sound recorded for its
`(channel != 0) && (channel != 1)`. Not a divergence.

**Where `SoundBlaster16: IRQ must be 2, 5, 7, or 10.` comes from** is
`SoundBlaster16Inline.h:563`–`:567`, inside `checkSelectedDMAAndIRQ()`. That function
**has no caller anywhere in our tree** — `grep` over `SoundBlaster16.m` and
`SoundBlaster16Inline.h` finds only its definition at `:537`. Being `static __inline__` and
uncalled, it is never emitted, which is why none of its five strings
(`IRQ is %d.`, `IRQ must be 2, 5, 7, or 10.`, `8-bit DMA channel must be 0, 1, or 3.`,
`16-bit DMA channel must be 5, 6, or 7.`, `8-bit and 16-bit DMA channels must be
different.`) would appear in a build's `__cstring`, and none appears in the reference's.

`Default.table`'s `"Valid IRQ Levels" = "5 7 9 10"` agrees with Apple, with our
`reset`, and with the reference. **Only `checkSelectedDMAAndIRQ()` disagrees, and it is
dead.** See Finding 23.

## Q2 — The two strings absent from our source

### `SoundBlaster16: DSP read error.\n` (13763) and `SoundBlaster16: DSP write error.\n` (13796)

These are the **timeout arms of the two DSP wait loops**, and Apple emits an `IOLog`
where our `dspReadWait()`/`dspWriteWait()` emit only an `#ifdef DEBUG` message.

The read-wait, read in full at `initializeHardware`+93 (1765–1868):

```
 1765: 31DB             xor  ebx, ebx                       ; i = 0
 1768: 668B1520400000   mov  dx, word ptr ds:_sbDataAvailableStatusReg
 1775: EC               in   al, dx
 1776: 84C0             test al, al
 1778: 7C13             jl   loc_707                        ; bit 7 set -> ready, exit
 1780: 6A0A             push 0Ah
 1782: E805F9FFFF       call _IODelay                       ; IODelay(10)
 1790: 43               inc  ebx
 1791: 81FB0F270000     cmp  ebx, 270Fh                     ; i <= 9999
 1797: 7EE1             jle  loc_6E8                        ; loop
 1799: 81FB10270000     cmp  ebx, 2710h                     ; i == 10000 ?
 1805: 7540             jnz  loc_74F
 1807: ... out _sbResetReg, 1 ; IODelay(15) ; out _sbResetReg, 0 ; IODelay(15)
 1858: 68C3350000       push offset "SoundBlaster16: DSP read error.\n"
 1863: E8B4F8FFFF       call _IOLog
 1871: 668B1514400000   mov  dx, word ptr ds:_sbReadDataReg ; <- both arms arrive here
```

The write-wait is the same shape on `_sbWriteBufferStatusReg` with `test al,al / jge` and
`SoundBlaster16: DSP write error.\n`.

Three properties matter and all three differ from ours:

1. **The bound is 10000, not 2000** (`MAX_WAIT_FOR_DATA_AVAILABLE`, `Inline.h:112`).
2. **The read comes before the delay**, not after: the reference tests the port first and
   only delays if it must loop. Ours delays first (`Inline.h:126`–`:130`).
3. **The timeout arm logs unconditionally and falls through**; it does not return a status
   and no caller tests one. Both arms converge on the next instruction.

`-[SoundBlaster16 updateSampleRate]` at `SoundBlaster16.m:502`–`:517` already carries
exactly this shape, including the `timeout == 10000` post-test and the
`SoundBlaster16: DSP write error.\n` log — **that is the closest thing in our tree to
Apple's helper, and it is a good model for what `dspWriteWait()`/`dspReadWait()` should
become.** The reference emits this expansion **29** times, counted as the `cmp …, 270Fh`
bound test, one per expansion: seven in `initializeHardware` (1791, 1931, 2091, 2231, 2391,
2559, 2691), three in `updateSampleRate` (6847, 6999, 7135), eight in
`startDMAForChannel:` (8191, 8327, 8475, 8615, 8743, 8879, 9027, 9163), **four** in
`stopDMAForChannel:read:` (9363, 9575, 9619, 9827) and seven in `timeoutOccurred` (10499,
10639, 10799, 10939, 11099, 11267, 11399). 7 + 3 + 8 + 4 + 7 = 29. No other function in the
binary contains the expansion. **`stopDMAForChannel:read:` has four waits, not three** —
see Finding 19.

`SoundBlaster16: DSP read error.\n` is emitted from `initializeHardware`, `timeoutOccurred`
and `stopDMAForChannel:read:` (9894); `SoundBlaster16: DSP write error.\n` from all five.
Neither string appears anywhere in our source.

### `SoundBlaster16: SoundBlaster not detected at address 0x%0x.\n` (13830)

This is the **probe-failure message of the DSP detection sequence**, and it is reached from
three tests our `resetDSP()` does not perform in that form.
`initializeHardware`, 1892–2518:

```
 1892: 88DA             mov  dl, bl
 1894: 80FAAA           cmp  dl, 0AAh                 ; reset response
 1897: 0F8554020000     jnz  loc_9C3                  ; -> 2499
 ...  write-wait ; out _sbWriteDataOrCommandReg, 0E0h ; IODelay(75)
 ...              out _sbWriteDataOrCommandReg, 43h  ; IODelay(75)
 ...  read-wait  ; in _sbReadDataReg ; IODelay(30)
 2194: 80FABC           cmp  dl, 0BCh                 ; ~0x43
 2197: 0F8528010000     jnz  loc_9C3                  ; -> 2499
 ...  write-wait ; out 0E0h ; IODelay(75) ; out 94h ; IODelay(75)
 ...  read-wait  ; in _sbReadDataReg ; IODelay(30)
 2494: 80FA6B           cmp  dl, 6Bh                  ; ~0x94
 2497: 7419             jz   loc_9DC                  ; -> 2524, detected
 2499: A10C400000       mov  eax, ds:_sbBaseRegisterAddress
 2504: 50               push eax
 2505: 6806360000       push offset "SoundBlaster16: SoundBlaster not detected at address 0x%0x.\n"
 2510: E82DF6FFFF       call _IOLog
 2518: E934010000       jmp  loc_B0F                  ; -> 2831, the version != NONE gate
 2524: C7050040000003000000  mov ds:_sbCardType, 3    ; SB_8BIT
```

**Our probe path cannot fail the same way, and on two of the three tests it fails
silently.** Our `resetDSP()` (`Inline.h:325`–`:405`) performs only the `0xAA` check, and on
failure returns after an `#ifdef DEBUG` log — leaving `version` at `SB16_NONE`, which
`reset` then reports as `%s: None or unsupported card.` The two invert-byte probes
(`0xE0`/`0x43` → `0xBC` and `0xE0`/`0x94` → `0x6B`) have **no counterpart at all** in our
source. This is the sub-block Task 10 may add wholesale. See Finding 5.

## Q3 — The initialised mixer defaults

`__DATA,__data` is 146 bytes at address 16384, file offset 18780, and unlike drvSB8Sound
and drvES1x88Sound it is **not** all zeros. Read in full:

```
 16384: 00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
 16400: 00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
 16416: 00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
 16432: 00 00 00 00  18 00 00 00  18 00 00 00  15 00 00 00
 16448: 15 00 00 00  10 00 00 00  10 00 00 00  02 00 00 00
 16464: 15 00 00 00  08 00 00 00  08 00 00 00  09 00 00 00
 16480: 09 00 00 00  00 00 00 00  00 00 00 00  15 00 00 00
 16496: 15 00 00 00  02 00 00 00  02 00 00 00  02 00 00 00
 16512: 02 00 00 00  06 00 00 00  15 00 00 00  0b 00 00 00
 16528: 00 00
```

**Every one of the 25 values in the task brief is confirmed exactly.** The
symbol-by-symbol reading, with our source's counterpart and its value:

| Address | Symbol | Bytes | Value | Our counterpart | Our value | Match? |
| --- | --- | --- | --- | --- | --- | --- |
| 16436 | `_volMasterLeft` | 4 | `0x18` | `volMaster.reg.left` `Inline.h:78`, set `:253` | 24 = `0x18` | value yes, form no |
| 16440 | `_volMasterRight` | 4 | `0x18` | `volMaster.reg.right` `:254` | 24 = `0x18` | value yes, form no |
| 16444 | `_volVoiceLeft` | 4 | `0x15` | `volVoice.reg.left` `:258` | 24 = `0x18` | **no** |
| 16448 | `_volVoiceRight` | 4 | `0x15` | `volVoice.reg.right` `:259` | 24 = `0x18` | **no** |
| 16452 | `_volLineLeft` | 4 | `0x10` | `volLine.reg.left` `:273` | 0 | **no** |
| 16456 | `_volLineRight` | 4 | `0x10` | `volLine.reg.right` `:274` | 0 | **no** |
| 16460 | `_volPCSpeaker` | 4 | `0x02` | **none** | — | **no counterpart** |
| 16464 | `_volMic` | 4 | `0x15` | `volMic` `:83`, set `:278` | 5 | **no** |
| 16468 | `_trebleLeft` | 4 | `0x08` | **none** | — | **no counterpart** |
| 16472 | `_trebleRight` | 4 | `0x08` | **none** | — | **no counterpart** |
| 16476 | `_bassLeft` | 4 | `0x09` | **none** | — | **no counterpart** |
| 16480 | `_bassRight` | 4 | `0x09` | **none** | — | **no counterpart** |
| 16484 | `_volMIDILeft` | 4 | `0` | `volFM.reg.left` `:263` | 0 | value yes, form/name no |
| 16488 | `_volMIDIRight` | 4 | `0` | `volFM.reg.right` `:264` | 0 | value yes, form/name no |
| 16492 | `_volCDLeft` | 4 | `0x15` | `volCD.reg.left` `:268` | 0 | **no** |
| 16496 | `_volCDRight` | 4 | `0x15` | `volCD.reg.right` `:269` | 0 | **no** |
| 16500 | `_lastStageGainInputLeft` | 4 | `0x02` | `lastStageGainInputLeft` `:100` **and** `inputGainLeft` `:86` | 0 and 0 | **no** |
| 16504 | `_lastStageGainInputRight` | 4 | `0x02` | `lastStageGainInputRight` `:101` **and** `inputGainRight` `:87` | 0 and 0 | **no** |
| 16508 | `_lastStageGainOutputLeft` | 4 | `0x02` | `lastStageGainOutputLeft` `:102` **and** `outputGainLeft` `:88` | 0 and 0 | **no** |
| 16512 | `_lastStageGainOutputRight` | 4 | `0x02` | `lastStageGainOutputRight` `:103` **and** `outputGainRight` `:89` | 0 and 0 | **no** |
| 16516 | `_outputMixerSwitch` | 4 | `0x06` | **none** | — | **no counterpart** |
| 16520 | `_inputMixerSwitchLeft` | 4 | `0x15` | `inputControlLeft` `:84`, set `:282` | `INPUT_SOURCE_MIC` = 0 | **no** |
| 16524 | `_inputMixerSwitchRight` | 4 | `0x0b` | `inputControlRight` `:85`, set `:283` | `INPUT_SOURCE_MIC` = 0 | **no** |
| 16528 | `_sbStartDMACommand` | 1 | `0` | `sbStartDMACommand` `:109` | 0 | **yes** |
| 16529 | `_sbStartDMAMode` | 1 | `0` | `sbStartDMAMode` `:110` | 0 | **yes** |

Only `_sbStartDMACommand` and `_sbStartDMAMode` agree outright. `_volMasterLeft/Right`
carry the same numeric value our `initMixerRegisters()` assigns at run time but reach it a
different way. Twelve differ in value, seven have no counterpart at all, and four of ours
(`_lastStageGain*`) are shadowed by a second, duplicate set of variables.

**All 23 volume/gain symbols are four bytes wide**, not one: consecutive symbols are 4
apart, they are written whole with `mov ds:_volMic, edx` (`8915 …`) in
`updateInputGainLeft`+38 and read a byte at a time with `mov bl, byte ptr ds:_volMasterLeft`
(`8A1D …`) when the low byte is wanted for a port write. Our five
`sb16MonoMixerRegister_t` unions and seven `unsigned char` shadows cannot produce either
form. See Finding 2.

The eleven register-address globals at 16396–16435 *are* zero, and are computed at run time
in `+probe:` exactly as drvSB8Sound and drvES1x88Sound do:

| Address | Symbol | Our source | Written by |
| --- | --- | --- | --- |
| 16384 | `_sbCardType` | `.m:18` | `initializeHardware`+9, +852, `timeoutOccurred` |
| 16396 | `_sbBaseRegisterAddress` | `Inline.h:13` | `+probe:`+99 |
| 16400 | `_sbResetReg` | `:18` | `assignDSPRegAddresses()`, `+probe:`+149 |
| 16404 | `_sbReadDataReg` | `:19` | same, `+probe:`+164 |
| 16408 | `_sbWriteDataOrCommandReg` | `:20` | same, `+probe:`+178 |
| 16412 | `_sbWriteBufferStatusReg` | `:21` | same, `+probe:`+183 (shares `base+0Ch`) |
| 16416 | `_sbDataAvailableStatusReg` | `:22` | same, `+probe:`+196 |
| 16420 | `_sbAck8bitInterrupt` | `:23` | same, `+probe:`+201 (shares `base+0Eh`) |
| 16424 | `_sbAck16bitInterrupt` | `:24` | same, `+probe:`+215 |
| 16428 | `_sbMixerAddressReg` | `Inline.h:62` | `assignMixerRegAddresses()`, `+probe:`+230 |
| 16432 | `_sbMixerDataReg` | `:63` | same, `+probe:`+245 |

`__DATA,__bss` is 17 bytes at 16532: `_xxx.86`, `_xxx.89` and `_xxx.92` (the three
`static int xxx` copies from `outb`/`outw`/`outl` in
`src/kernel-7/machdep/i386/io_inline.h`, reached through `SoundBlaster16.h:11`'s
`#import <driverkit/i386/ioPorts.h>`; only `outb`'s is referenced, and every `out dx, al`
in the binary is followed by `lock incl ds:_xxx.86`), then `_sbBufferCounter` at 16544 (4
bytes) and `_interruptStatus` at 16548 (1 byte). `_SoundBlaster16_instance` is `external`
in `__DATA,__common` at 16552.

**There is no `_interruptCount` symbol anywhere.** See Finding 20.

## `_sbCardType` is `__DATA,__data:16384`, 12 bytes, and holds three `unsigned int`s

**Do not carry drvSB8Sound's field offsets across.** SoundBlaster8's `_sbCardType` is 20
bytes in `__bss` with five fields; this one is 12 bytes in `__data` with three, and its
layout is confirmed from the `IOLog` argument order at `reset`+228:

```
 1504: A108400000       mov  eax, ds:dword_4008     ; _sbCardType + 8
 1509: 50               push eax
 1510: A104400000       mov  eax, ds:dword_4004     ; _sbCardType + 4
 1515: 50               push eax
 1516: A124600000       mov  eax, ds:paName         ; sel:name
 1522: 53               push ebx
 1523: E808FAFFFF       call _objc_msgSend          ; [self name]
 1533: 52               push edx
 1534: 68F9380000       push offset "%s hardware version is %d.%d\n"
 1539: E8F8F9FFFF       call _IOLog
```

Pushed right to left the arguments are `(format, [self name], +4, +8)`, so `+4` is
`majorVersion` and `+8` is `minorVersion`. `+0` is `version`: `initializeHardware`+9 stores
`4` there, +852 stores `3`, +1451 stores `1`, and `reset`+148 loads it and compares against
`2`, `3` and `1`.

| Offset | Address | Field | Width | Evidence |
| --- | --- | --- | --- | --- |
| 0 | 16384 | `version` | 4 | `mov ds:_sbCardType, 4` at 1681, `, 3` at 2524, `, 1` at 3123; `cmp ds:_sbCardType, 4` at 2831; `mov edx, ds:_sbCardType` at 1424 |
| 4 | 16388 | `majorVersion` | 4 | `and ebx, 0Fh; mov ds:dword_4004, ebx` at 2792 |
| 8 | 16392 | `minorVersion` | 4 | `and ebx, 0Fh; mov ds:dword_4008, ebx` at 2822 |

12 bytes exactly, with no padding and **no `name`, `mixerPresent`, `supports16Bit` or
`supportsAWE`**. See Finding 1.

The enum values are confirmed: `4` is assigned before detection and reported as
`%s: None or unsupported card.`, `3` after DSP detection and reported as
`%s: This driver does not support 8-bit Sound Blaster cards.`, `1` after the mixer probe
succeeds. **`2` is never assigned anywhere in the binary**, though `reset` tests for it —
so `SB16_VIBRA` is a value Apple's `reset` can recognise but Apple's `initializeHardware`
never produces. Our enum's `SB16_BASIC = 1`, `SB16_VIBRA = 2`, `SB_8BIT = 3`,
`SB16_NONE = 4` (`SoundBlaster16Registers.h:239`–`:244`) matches the reference's numbering.

---

# Findings

Twenty-five. None is a Task 2 defect.

## Finding 1: `sb16CardParameters_t` has seven members; the reference's has three

**Source:** `SoundBlaster16Registers.h:249`–`:257`, `SoundBlaster16Inline.h:332`–`:338`,
`:388`–`:404`; `SoundBlaster16.m:18`

```c
typedef struct  {
        sb16CardVersion_t version;
        char              *name;
        unsigned int      majorVersion;
        unsigned int      minorVersion;
        BOOL              mixerPresent;
        BOOL              supports16Bit;
        BOOL              supportsAWE;
} sb16CardParameters_t;
```

That is 20 bytes with `majorVersion` at offset 8 and `minorVersion` at 12. The reference's
is 12 bytes with `majorVersion` at 4 and `minorVersion` at 8 (table above), and
`initializeHardware`'s prologue writes exactly three fields:

```
 1681: C7050040000004000000  mov ds:_sbCardType, 4        ; version = SB16_NONE
 1691: C7050440000000000000  mov ds:dword_4004, 0         ; majorVersion = 0
 1701: C7050840000000000000  mov ds:dword_4008, 0         ; minorVersion = 0
```

against our `resetDSP()`'s seven. `name`, `mixerPresent`, `supports16Bit` and
`supportsAWE` have no storage and no use anywhere in the binary; the two card-name strings
`"Sound Blaster 16"` (`Inline.h:391`) and `"Sound Blaster Pro"` (`:401`) are not in the
reference's `__cstring`.

`_sbCardType` also sits in `__DATA,__data` rather than `__bss`, so Apple's declaration
carried an explicit zero initialiser where ours (`SoundBlaster16.m:18`) has none. See
Finding 24.

**Disposition for Task 10:** reduce the struct to `version`, `majorVersion`,
`minorVersion`, drop the four dead members and the two card-name strings, and give the
declaration a `= {0}` initialiser. This changes the field offsets `reset` and
`initializeHardware` load, which is why `reset` is classified divergent despite matching
in every other respect.

## Finding 2: the mixer shadows are 23 `unsigned int` globals with compile-time initialisers

**Source:** `SoundBlaster16Inline.h:78`–`:103`; `SoundBlaster16Registers.h:207`–`:214`

Our source declares five `sb16MonoMixerRegister_t` unions of `right:4, left:4` bitfields
plus seven `unsigned char`s, all `= {0}` / `= 0`, and assigns the defaults at run time in
`initMixerRegisters()`. The reference declares twenty-three separate four-byte variables
with the initialisers read in Q3 above, and never packs two channels into one byte.

The width is proved twice over. `updateInputGainLeft`+38 stores them whole:

```
 5150: 891550400000     mov  ds:_volMic, edx
 5156: 891548400000     mov  ds:_volLineRight, edx
 5162: 891544400000     mov  ds:_volLineLeft, edx
 5168: 891570400000     mov  ds:_volCDRight, edx
 5174: 89156C400000     mov  ds:_volCDLeft, edx
```

and every port write reads the low byte back and shifts it left three, for the five-bit
CT1745 registers:

```
 5180: 8A1D44400000     mov  bl, byte ptr ds:_volLineLeft
 5186: C0E303           shl  bl, 3
```

or left six for the two-bit gain registers (`initializeLastStageGainRegisters`+198,
`shl bl, 6`), or left four for the four-bit tone registers (`initializeHardware`+2460,
`shl bl, 4`). A `right:4, left:4` union cannot emit any of these: the shift amount would
be zero for `right` and the mask-and-merge would be the paired `and`/`or` form.

**This is the settled masked-expression-versus-bitfield question in its other direction.**
The reference never uses either form for these variables, because they are not bitfields at
all — they are plain integers, one per channel.

The name mapping, for Task 10:

| Our declaration | Reference | Note |
| --- | --- | --- |
| `volMaster` (union) | `_volMasterLeft`, `_volMasterRight` | |
| `volVoice` | `_volVoiceLeft`, `_volVoiceRight` | |
| `volLine` | `_volLineLeft`, `_volLineRight` | |
| `volCD` | `_volCDLeft`, `_volCDRight` | |
| `volFM` | `_volMIDILeft`, `_volMIDIRight` | same CT1745 registers `34h`/`35h`, different name |
| `volMic` | `_volMic` | `unsigned int`, not `unsigned char` |
| `inputControlLeft`/`Right` | `_inputMixerSwitchLeft`/`Right` | |
| `inputGainLeft`/`Right` | — | duplicates `lastStageGainInput*` |
| `outputGainLeft`/`Right` | — | duplicates `lastStageGainOutput*` |
| `lastStageGainInput*`, `lastStageGainOutput*` | same names | `unsigned int`, not `unsigned char` |
| — | `_volPCSpeaker`, `_trebleLeft`/`Right`, `_bassLeft`/`Right`, `_outputMixerSwitch` | no counterpart |

The declaration order in `__data` is `volMasterLeft, volMasterRight, volVoiceLeft,
volVoiceRight, volLineLeft, volLineRight, volPCSpeaker, volMic, trebleLeft, trebleRight,
bassLeft, bassRight, volMIDILeft, volMIDIRight, volCDLeft, volCDRight,
lastStageGainInputLeft, lastStageGainInputRight, lastStageGainOutputLeft,
lastStageGainOutputRight, outputMixerSwitch, inputMixerSwitchLeft, inputMixerSwitchRight,
sbStartDMACommand, sbStartDMAMode`. If Task 10 reorders, reorder all of them together.

**Disposition for Task 10:** replace the five unions (`Inline.h:78`–`:82`) and the eleven
`unsigned char` shadows — the seven at `Inline.h:83`–`:89` plus the four `lastStageGain*`
at `:100`–`:103`, whose retyping the mapping table above already covers — with the
twenty-three `unsigned int` variables in that order, with the reference's initialisers, and delete
`inputGainLeft`/`Right` and `outputGainLeft`/`Right` as duplicates of the `lastStageGain*`
set. `sb16MonoMixerRegister_t`, `sb16MonoMixerRegister5bit_t` and
`sb16StereoMixerRegister_t` become unused; `sb16MonoMixerRegister5bit_t` and
`sb16StereoMixerRegister_t` are already unused in our own tree.

## Finding 3: `SB16_ADDRESS_WRITE_DELAY` is 15, not 10; `SB16_DATA_READ_DELAY` is 30, not 10

**Source:** `SoundBlaster16Registers.h:31`, `:33`

Every mixer-address write in the binary is followed by `push 0Fh; call _IODelay`, and every
DSP data read by `push 1Eh; call _IODelay`. The `outbIXMixer()` expansion, read at
`reset`+331 and matched at approximately 90 further sites:

```
 1607: 668B152C400000   mov  dx, word ptr ds:_sbMixerAddressReg
 1614: B080             mov  al, 80h                   ; MC16_IRQ_SELECT
 1616: EE               out  dx, al
 1617: F0FF0594400000   lock incl ds:_xxx.86
 1624: 6A0F             push 0Fh                       ; IODelay(15), not 10
 1626: E8A1F9FFFF       call _IODelay
 1631: 668B1530400000   mov  dx, word ptr ds:_sbMixerDataReg
 1641: 88D8             mov  al, bl
 1643: EE               out  dx, al
 1644: F0FF0594400000   lock incl ds:_xxx.86
 1651: 6A4B             push 4Bh                       ; IODelay(75), matches
 1653: E886F9FFFF       call _IODelay
```

The DSP read, at `initializeHardware`+199:

```
 1871: 668B1514400000   mov  dx, word ptr ds:_sbReadDataReg
 1878: EC               in   al, dx
 1879: 0FB6D8           movzx ebx, al
 1882: 6A1E             push 1Eh                       ; IODelay(30), not 10
 1884: E89FF8FFFF       call _IODelay
```

The DSP reset pulse uses `0Fh` on both halves and has **no** trailing `IODelay(100)`; our
`dspReadWait()`, `dspWriteWait()`, `resetDSPQuick()` and `resetDSP()` all append
`IODelay(SB16_RESET_DELAY)` after the second `outbV`. The mixer reset in
`initializeHardware` is followed by `push 32h` (`IODelay(50)`), not our
`IODelay(100)` (`Inline.h:250`, `:415`).

`SB16_DATA_WRITE_DELAY` 75 and `SB16_WAIT_DELAY` 10 are correct.

**Disposition for Task 10:** `SB16_ADDRESS_WRITE_DELAY` 10 → 15,
`SB16_DATA_READ_DELAY` 10 → 30, drop the trailing `IODelay(SB16_RESET_DELAY)` from every
reset pulse, and change `initMixerRegisters()`'s and `resetMixer()`'s post-reset delay from
100 to 50. This one constant touches every mapped function that writes a mixer register,
which is why Finding 3 is cited so widely.

## Finding 4: the DSP wait helpers have the wrong bound, the wrong order and no `IOLog`

**Source:** `SoundBlaster16Inline.h:119`–`:145`, `:150`–`:176`, `:181`–`:218`

Fully evidenced under Q2 above. Four differences:

1. `MAX_WAIT_FOR_DATA_AVAILABLE` is 2000 in our header (`:112`); the reference loops to
   10000 (`cmp ebx, 270Fh / jle`, post-test `cmp ebx, 2710h`).
2. Ours delays then reads; the reference reads then delays.
3. Ours logs only under `#ifdef DEBUG` and returns `NO`; the reference logs
   `SoundBlaster16: DSP read error.\n` or `SoundBlaster16: DSP write error.\n`
   unconditionally and falls through.
4. **No caller tests a return value.** Every timeout arm converges on the instruction the
   success arm reaches. Our `writeToDSP()` (`:185`) and `readFromDSP()` (`:207`) return
   early on failure, and `resetDSP()` returns at `:348`, `:372` and `:377`.

Consequentially, **the reference has no `writeToDSP`/`readFromDSP` functions at all.** They
are `static` in our header and would be emitted out of line as drvSB8Sound's are; no such
symbol exists here. Apple writes each DSP byte as an inline wait-then-`out` pair.

**Disposition for Task 10:** rewrite `dspReadWait()`/`dspWriteWait()` as `void` helpers on
the reference's shape, and make `writeToDSP()`/`readFromDSP()` `static __inline__` wrappers
with no return-value test, or remove them and inline their two lines at each call site. The
model already in our tree is `updateSampleRate` at `SoundBlaster16.m:502`–`:520`.

## Finding 5: `resetDSP()` has no invert-byte detection probe and cannot emit the probe-failure message

**Source:** `SoundBlaster16Inline.h:340`–`:365`

Fully evidenced under Q2. Our `resetDSP()` pulses reset, waits, reads, and accepts the card
if the byte is `0xAA`. The reference does that and then runs two `DC_INVERT_BYTE` probes:
write `0E0h` then `43h`, read and require `0BCh`; write `0E0h` then `94h`, read and require
`6Bh`. Any of the three failing produces
`IOLog("SoundBlaster16: SoundBlaster not detected at address 0x%0x.\n",
sbBaseRegisterAddress)` and leaves `version` at `SB16_NONE`.

Note that the second write of each pair has **no** intervening write-wait: the reference
emits write-wait, `out 0E0h`, `IODelay(75)`, `out 43h`, `IODelay(75)` — one wait for two
bytes. That is not what a `writeToDSP()` helper produces, and is further evidence for
Finding 4's conclusion that Apple wrote these inline.

**This sub-block has no counterpart in our source and Task 10 may add it wholesale.**

## Finding 6: the card type is classified by a mixer-register probe, not by the DSP version

**Source:** `SoundBlaster16Inline.h:387`–`:404`

Our `resetDSP()` classifies from `majorVersion`: `>= 4` gives `SB16_BASIC` or `SB16_VIBRA`,
`== 3` gives `SB_8BIT`. **The reference never uses `majorVersion` for classification.** It
sets `version = SB_8BIT` (3) unconditionally once the DSP answers, reads the version bytes
for reporting only, and then upgrades to `SB16_BASIC` (1) if and only if a write/read-back
probe of CT1745 mixer registers `30h` through `3Ah` succeeds. `initializeHardware`+1244:

```
 2905: BE30000000       mov  esi, 30h                  ; reg = 0x30
 2916: 89F0             mov  eax, esi
 2918: 04D5             add  al, 0D5h                  ; (reg + 0xD5) as a byte
 2920: C0E003           shl  al, 3                     ;  << 3
 2923: 8845FC           mov  [ebp+var_4], al           ; testValue
 2930: ... out _sbMixerAddressReg, esi ; IODelay(15)
       ... out _sbMixerDataReg, testValue ; IODelay(75)
 2983: 6A0A             push 0Ah                       ; IODelay(10)
 2993: ... out _sbMixerAddressReg, reg ; IODelay(15)
 3027: EC               in   al, dx                    ; read back
 3032: 6A4B             push 4Bh                       ; IODelay(75)
 3042: 88DA             mov  dl, bl
 3044: 80E2F8           and  dl, 0F8h                  ; top five bits
 3047: 3855FC           cmp  [ebp+var_4], dl
 3050: 7554             jnz  loc_C40                   ; -> 3136, leave version = 3
 3052: 46               inc  esi
 3053: 83FE3A           cmp  esi, 3Ah                  ; reg <= 0x3A
 3056: 0F8E6EFFFFFF     jle  loc_B64                   ; -> 2916
 3062: ... out _sbMixerAddressReg, 0 ; IODelay(15) ; out _sbMixerDataReg, 0 ; IODelay(75)
 3116: 6A32             push 32h                       ; IODelay(50)
 3123: C7050040000001000000  mov ds:_sbCardType, 1     ; SB16_BASIC
```

Eleven registers, `0x30`–`0x3A`, each written `((reg + 0xD5) & 0xFF) << 3` — that is 5, 6,
… 15 shifted into the five-bit volume field — and read back masked with `0xF8`. Any
mismatch aborts the loop and leaves the card classified `SB_8BIT`, which `reset` then
rejects with `%s: This driver does not support 8-bit Sound Blaster cards.`

**This sub-block has no counterpart in our source and Task 10 may replace our
version-number classification with it wholesale.**

## Finding 7: `resetDSP()` extras with no counterpart

**Source:** `SoundBlaster16Inline.h:348`–`:380`

Four smaller differences in the same function, all evidenced from `initializeHardware`:

- **`IOSleep(1)` at `:367` is extra.** `_IOSleep` is imported and called exactly once in
  the whole binary, from `stopDMAForChannel:read:`+663 with argument `32h`. There is no
  `IOSleep` in `initializeHardware` or `timeoutOccurred`.
- **The version bytes are masked with `0x0F`.** `and ebx, 0Fh; mov ds:dword_4004, ebx` at
  2792 and the same at 2822. Our `:375` and `:380` store `readFromDSP()` unmasked.
- **There is no wait before the second read.** 2801 reads `_sbReadDataReg` directly after
  storing `majorVersion`; our `:377` inserts another `dspReadWait()`.
- **The `0xAA` and version reads are `movzx`-extended and compared as bytes**
  (`movzx ebx, al` then `cmp dl, 0AAh`), consistent with a `unsigned char` local, where our
  `readFromDSP()` returns `unsigned int` and can return `0xff` as a sentinel.

## Finding 8: `initMixerRegisters()` writes the MC16 register block; the reference writes CT1745

**Source:** `SoundBlaster16Inline.h:240`–`:298`

Our `initMixerRegisters()` writes `MC16_MASTER_VOLUME` `22h`, `MC16_VOICE_VOLUME` `04h`,
`MC16_FM_VOLUME` `26h`, `MC16_CD_VOLUME` `28h`, `MC16_LINE_VOLUME` `2Eh`,
`MC16_MIC_VOLUME` `0Ah`, `MC16_INPUT_CONTROL_LEFT`/`RIGHT` `3Dh`/`3Eh`,
`MC16_INPUT_GAIN_LEFT`/`RIGHT` `3Fh`/`40h` and `MC16_OUTPUT_GAIN_LEFT`/`RIGHT` `41h`/`42h`
— twelve writes. The reference writes twenty-four, all in the CT1745 block, in this order,
read from `initializeHardware` 3136–4635:

| Register | Source value | Shift |
| --- | --- | --- |
| `30h` `CT1745_MASTER_VOLUME_LEFT` | `_volMasterLeft` | `<< 3` |
| `31h` `CT1745_MASTER_VOLUME_RIGHT` | `_volMasterRight` | `<< 3` |
| `32h` `CT1745_VOICE_VOLUME_LEFT` | `_volVoiceLeft` | `<< 3` |
| `33h` `CT1745_VOICE_VOLUME_RIGHT` | `_volVoiceRight` | `<< 3` |
| `34h` `CT1745_FM_VOLUME_LEFT` | `_volMIDILeft` | `<< 3` |
| `35h` `CT1745_FM_VOLUME_RIGHT` | `_volMIDIRight` | `<< 3` |
| `36h` `CT1745_CD_VOLUME_LEFT` | `_volCDLeft` | `<< 3` |
| `37h` `CT1745_CD_VOLUME_RIGHT` | `_volCDRight` | `<< 3` |
| `38h` `CT1745_LINE_VOLUME_LEFT` | `_volLineLeft` | `<< 3` |
| `39h` `CT1745_LINE_VOLUME_RIGHT` | `_volLineRight` | `<< 3` |
| `3Ah` `CT1745_MIC_VOLUME` | `_volMic` | `<< 3` |
| `3Bh` `MC16_PC_SPEAKER_VOLUME` | `_volPCSpeaker` | `<< 6` |
| `3Ch` `MC16_OUTPUT_CONTROL` | `_outputMixerSwitch` | none |
| `3Dh` `MC16_INPUT_CONTROL_LEFT` | `_inputMixerSwitchLeft` | none |
| `3Eh` `MC16_INPUT_CONTROL_RIGHT` | `_inputMixerSwitchRight` | none |
| `43h` `MC16_AGC` | literal `0` | none |
| `44h` `MC16_TREBLE_LEFT` | `_trebleLeft` | `<< 4` |
| `45h` `MC16_TREBLE_RIGHT` | `_trebleRight` | `<< 4` |
| `46h` `MC16_BASS_LEFT` | `_bassLeft` | `<< 4` |
| `47h` `MC16_BASS_RIGHT` | `_bassRight` | `<< 4` |
| `3Fh` `MC16_INPUT_GAIN_LEFT` | `_lastStageGainInputLeft` | `<< 6` |
| `40h` `MC16_INPUT_GAIN_RIGHT` | `_lastStageGainInputRight` | `<< 6` |
| `41h` `MC16_OUTPUT_GAIN_LEFT` | `_lastStageGainOutputLeft` | `<< 6` |
| `42h` `MC16_OUTPUT_GAIN_RIGHT` | `_lastStageGainOutputRight` | `<< 6` |

(That is 24 writes; the last four repeat what `initializeLastStageGainRegisters` writes
moments later, and the reference emits both.)

Four shift groups, and `3Bh` belongs to the last one, not to the unshifted group its
neighbours `3Ch`–`3Eh` form: `30h`–`3Ah` are `shl bl, 3`; `3Bh` and `3Fh`–`42h` are
`shl bl, 6`; `44h`–`47h` are `shl bl, 4`; `3Ch`, `3Dh` and `3Eh` are written unshifted and
`43h` is the literal `0` (`xor al, al` at 4106). The `3Bh` site is explicit at
`3829: 8A1D4C400000 mov bl, ds:_volPCSpeaker` / `3835: C0E306 shl bl, 6`. **Task 10 must
emit `_volPCSpeaker << 6` for `3Bh`.**

Every value is read from its shadow variable and shifted; **no value is a literal except
the `0` to `43h`**, and no shadow is assigned inside this block. Our version assigns the
default into the shadow and then writes it, twelve times.

**This sub-block has no counterpart in our source and Task 10 may replace it wholesale.**
Once Finding 2's initialisers are in place, the assignments disappear and only the writes
remain.

## Finding 9: `resetHardware()`'s mixer gate is `version != SB16_NONE`, not `mixerPresent`

**Source:** `SoundBlaster16Inline.h:421`–`:429`

```c
static __inline__ void
resetHardware(sb16CardParameters_t *cardType)
{
    resetDSP(cardType);
    resetMixer();
    if (cardType->mixerPresent)
        initMixerRegisters();
}
```

The reference gates *everything* after `resetDSP()` on the card version, and the mixer
reset is inside the gate, not before it:

```
 2831: 833D0040000004   cmp  ds:_sbCardType, 4         ; version == SB16_NONE ?
 2838: 0F8402070000     jz   loc_121E                  ; -> 4638, straight to the send
 2844: ... out _sbMixerAddressReg, 0 ; IODelay(15) ; out _sbMixerDataReg, 0 ; IODelay(75)
 2898: 6A32             push 32h                       ; IODelay(50)
 2905: ...              the register probe of Finding 6
 3136: ...              the register writes of Finding 8
 4638: A150600000       mov  eax, ds:paInitializelast  ; sel:initializeLastStageGainRegisters
```

The `jz` at 2838 is also the landing point of the "not detected" jump at 2518, which is how
a failed probe skips all mixer work.

**This is the "`BOOL` flag where the reference compared against a table base" pattern the
carried-forward lessons name.** A `BOOL` member test emits `cmp byte ptr [addr], 0`; the
reference emits `cmp dword ptr [addr], 4`. Even if `mixerPresent` were always set exactly
when `version != SB16_NONE`, the source construct could not produce these instructions.

**Disposition for Task 10:** replace the `mixerPresent` gate with
`if (cardType->version != SB16_NONE)` and move the `resetMixer()` call inside it. The
`mixerPresent` member then has no reader and goes with Finding 1.

## Finding 10: `initializeDMAChannels` caches `deviceDescription` and `numChannels`; the reference re-sends both

**Source:** `SoundBlaster16.m:165`, `:171`, `:173`, `:193`

```c
    id deviceDesc = [self deviceDescription];
    ...
    numChannels = [deviceDesc numChannels];

    if (numChannels == 1) {
        dma8Channel = [deviceDesc channel];
    ...
    } else if (numChannels == 2) {
        channelList = (unsigned int *)[deviceDesc channelList];
```

The reference sends `deviceDescription` **four** times and `numChannels` **twice**:

```
  299: A118600000     mov  eax, ds:paNumchannels        ; [[self deviceDescription] numChannels]
  305: A114600000     mov  eax, ds:paDevicedescript
  315/326:            two objc_msgSend
  336: 83FA01         cmp  edx, 1
  341: A11C600000     mov  eax, ds:paChannel            ; [[self deviceDescription] channel]
  347: A114600000     mov  eax, ds:paDevicedescript
  452: A118600000     mov  eax, ds:paNumchannels        ; [[self deviceDescription] numChannels] AGAIN
  458: A114600000     mov  eax, ds:paDevicedescript
  489: 83FA02         cmp  edx, 2
  498: A120600000     mov  eax, ds:paChannellist        ; [[self deviceDescription] channelList]
  504: A114600000     mov  eax, ds:paDevicedescript
```

**gcc cannot elide an `objc_msgSend`**, so this is a source difference, not codegen. Apple's
source is `if ([[self deviceDescription] numChannels] == 1) { … } else if ([[self
deviceDescription] numChannels] == 2) { … }` with no locals. This is the same shape
drvES1x88Sound's Finding 1 recorded for its `reset`.

**Disposition for Task 10:** drop `deviceDesc` and `numChannels` and inline the sends.

### The one exception to the selector-count rule in this driver: `paName` in this function

**`initializeDMAChannels` is the single function in this binary where a per-function
selector-reference count is lower than our source's send count for a reason that is *not* a
source difference.** The effort's Global Constraints say a differing per-function selector
count is always a source difference, because gcc cannot elide an `objc_msgSend`. That is
true of every send that is *executed*; it is not true of a send that gcc **tail-merges**
with an identical one, which removes the duplicate instruction without removing the source
statement.

The reference has **six** `mov eax, ds:paName` sites in this function — 664, 896, 957,
1106, 1165 and 1233 — where our source has **seven** `[self name]` sends. The missing
seventh is a tail merge, not a missing `IOLog`:

```
 1014: 0F85D4000000   jnz  loc_4D0    ; setAutoinitialize:0 forChannel:0 failed -> 1232
 ...
 1222: 7508           jnz  loc_4D0    ; setAutoinitialize:1 forChannel:1 failed -> 1232
 1224: B801000000     mov  eax, 1                     ; success return
 1229: EB23           jmp  loc_4F2
 1232: 52             push edx                        ; the single shared failure block
 1233: A124600000     mov  eax, ds:paName
 1243: E820FBFFFF     call _objc_msgSend              ; [self name]
 1254: 6844380000     push offset aSDmaAutoInitia     ; "%s: dma auto initialize error %d"
 1259: E810FBFFFF     call _IOLog
 1264: 31C0           xor  eax, eax                   ; failure return
```

Both `jnz loc_4D0` land on 1232 (`0F85 D4000000` from 1020 is 1020 + 212 = 1232; `75 08`
from 1224 is 1224 + 8 = 1232). **Both `setAutoinitialize:` failure arms share one
`[self name]` send and one `IOLog`.** The corresponding `setTransferMode:` failure blocks at
957 and 1165 were **not** merged — each keeps its own `paName` send and its own
`push offset aSDmaTransferMo`, and they converge only later, at the `call _IOLog` at 1259
(`loc_4EB`). That asymmetry — two identical error arms merged, two others not — is what
makes the count look like a source difference when it is not.

**Task 10 must keep all seven `[self name]` sends and the seven `IOLog` calls that consume
them, including both `"%s: dma auto initialize error %d"` sites — one per channel. Do not
delete an `IOLog`, and do not hoist one into a shared arm, to make the `paName` count reach
six.** Six in the binary against seven in correct source is the expected result here, not a
divergence to close. This is the only such exception in the driver; all 26 functions were checked and
the selector-count rule holds everywhere else.

## Finding 11: our class declares six instance variables; the reference has four

**Source:** `SoundBlaster16.h:14`–`:22`

`__OBJC,__instance_vars` is 52 bytes at 26808: a count word of 4 followed by four 12-byte
entries. Read in full:

| Name | Encoding | Offset |
| --- | --- | --- |
| `currentDMADirection` | `I` | 388 (`0x184`) |
| `interruptTimedOut` | `c` | 392 (`0x188`) |
| `currentEncoding` | `I` | 396 (`0x18C`) |
| `dmaChannelsAvailable` | `I` | 400 (`0x190`) |

Ours declares `currentDMADirection`, `interruptTimedOut`, `is16BitTransfer` (`BOOL`),
`dma8Channel`, `dma16Channel` and `numDMAChannels`, which lands `is16BitTransfer` at 393
and pushes `dma8Channel`/`dma16Channel`/`numDMAChannels` to 396, 400 and 404.

Three consequences:

1. **`is16BitTransfer` is `currentEncoding`, and it is `unsigned int`, not `BOOL`.**
   `startDMAForChannel:`+345 stores the raw `[self dataEncoding]` result as a dword
   (`mov [ebx+18Ch], edx`), `updateSampleRate`+484 compares
   `cmp dword ptr [edi+18Ch], 259h` (601) and `stopDMAForChannel:`+687 compares
   `cmp dword ptr [edi+18Ch], 258h` (600). A `BOOL` cannot hold 600 or 601 and a byte
   compare cannot be emitted from these. Our own source already assigns
   `is16BitTransfer = encoding` at `.m:634` and compares it against `Linear16` at `:691`,
   `:699`, `:708`, `:741` and `:754`, so the declaration is simply the wrong type.
2. **`dma8Channel` and `dma16Channel` are not ivars.** The reference holds both in
   registers for the length of `initializeDMAChannels` — `esi` and `edi`, with
   `mov edi, 63h` (99) at 294 as the function's *first* instruction, before any message
   send — and no other function reads them. Our `.m:175`, `:191`, `:196`, `:197` and `:232`
   use ivars.
3. **`numDMAChannels` is `dmaChannelsAvailable`** at 0x190, and it survives the function:
   `initializeDMAChannels` writes `1` at 375 and `2` at 537 and tests it at 1020;
   `startDMAForChannel:`+354 and `stopDMAForChannel:`+671 read it.

**Disposition for Task 10:** retype `is16BitTransfer` as `unsigned int currentEncoding`,
rename `numDMAChannels` to `dmaChannelsAvailable`, and make `dma8Channel`/`dma16Channel`
locals of `initializeDMAChannels` initialised `dma16Channel = 99` at the top. That restores
the reference's offsets 396 and 400 for the two surviving ivars.

## Finding 12: `setTransferMode:` is passed `IO_Demand`, not `IO_Single`

**Source:** `SoundBlaster16.m:248`, `:278`

```c
    ioReturn = [self setTransferMode: IO_Single forChannel: 0];
    ...
    ioReturn = [self setTransferMode: IO_Single forChannel: 1];
```

The reference pushes **0** for the mode at both sites:

```
  928: 6A00           push 0                        ; forChannel: 0
  930: 6A00           push 0                        ; mode
  932: A134600000     mov  eax, ds:paSettransfermod ; sel:setTransferMode:forChannel:
 1136: 6A01           push 1                        ; forChannel: 1
 1138: 6A00           push 0                        ; mode
```

`IODMATransferMode` in `src/driverkit-3/driverkit/i386/directDevice.h:58`–`:63` is
`IO_Demand = 0, IO_Single = 1, IO_Block = 2, IO_Cascade = 3`. The argument order was
confirmed against the adjacent `setAutoinitialize:` at 988–990, which pushes `0` then `1` —
the last-pushed value is the first argument.

This is drvES1x88Sound's Finding 2 recurring on a different chip, and it is a different DMA
mode, not a naming quibble.

**Disposition for Task 10:** change `IO_Single` to `IO_Demand` at `:248` and `:278`.

## Finding 13: the 16-bit channel takes `IO_16BitByteCount` (2); our `IO_16Bit` does not exist

**Source:** `SoundBlaster16.m:270`

This is the baseline-build breakage recorded at the top of this document, and the reference
supplies the value:

```
 1077: 6A01           push 1                        ; forChannel: 1
 1079: 6A02           push 2                        ; width
 1081: A130600000     mov  eax, ds:paSetdmatransfer ; sel:setDMATransferWidth:forChannel:
```

`IOEISADMATransferWidth` (`directDevice.h:163`–`:169`) is `IO_8Bit = 0, IO_16BitWordCount = 1,
IO_16BitByteCount = 2, IO_32Bit = 3`. The 8-bit site at 867–869 pushes `0` and `0`,
matching our `:240`.

**Disposition for Task 10:** `IO_16Bit` → `IO_16BitByteCount`, in the baseline-build repair
commit.

## Finding 14: `initializeLastStageGainRegisters` sends `stringValue`; the reference does not

**Source:** `SoundBlaster16.m:302`, `:310`, `:313`, `:321`

```c
    id deviceDesc = [self deviceDescription];
    id configTable;
    ...
    configTable = [deviceDesc configTable];
    gainStr = [[configTable valueForStringKey:"LS Input Gain"] stringValue];
```

The reference sends exactly three messages per key and stops at `valueForStringKey:`, and
re-sends `deviceDescription` and `configTable` for the second key:

```
 4676: 6817390000     push offset "LS Input Gain"
 4681: A158600000     mov  eax, ds:paValueforstring     ; sel:valueForStringKey:
 4687: A154600000     mov  eax, ds:paConfigtable        ; sel:configTable
 4693: A114600000     mov  eax, ds:paDevicedescript     ; sel:deviceDescription
 4700/4711/4722:      three objc_msgSend
 4727: 89C2           mov  edx, eax                     ; used directly as const char *
 4732: 85D2           test edx, edx                     ; if (str == NULL)
 4759: 6825390000     push offset "LS Output Gain"
 4764: A158600000     mov  eax, ds:paValueforstring
 4770: A154600000     mov  eax, ds:paConfigtable        ; re-sent
 4776: A114600000     mov  eax, ds:paDevicedescript     ; re-sent
```

**`stringValue` does not appear in `__OBJC,__meth_var_names` at all**, so no code path in
the reference sends it. This is drvES1x88Sound's Finding 1 recurring verbatim.

Two smaller differences in the same function:

- **The range test is unsigned byte arithmetic.** `mov dl,[edx]; add dl, 0D0h; cmp dl, 3;
  ja skip` — that is `(unsigned char)(str[0] - '0') <= 3`. Our `(gainStr[0] - '0') < 4` at
  `:314` and `:322` promotes to `int` and emits a signed compare.
- **The stores go right then left.** `mov ds:_lastStageGainInputRight, eax` at 4749 then
  `mov ds:_lastStageGainInputLeft, eax` at 4754, and the same pair for the output gains at
  4832/4837 — the order a chained assignment
  `lastStageGainInputLeft = lastStageGainInputRight = value;` produces. Our `:316`–`:317`
  and `:324`–`:325` are two statements in the other order. Both stores are four bytes wide
  (Finding 2).

**Disposition for Task 10:** drop the `stringValue` send, drop the `deviceDesc` and
`configTable` locals and inline both chains, and make the gain value an `unsigned char`
local so the bound test emits `ja`.

## Finding 15: two update methods write one shadow fewer than the reference

**Source:** `SoundBlaster16.m:377`–`:380`, `:462`–`:466`

`updateInputGainRight` writes `volLine.reg.right`, `volCD.reg.left`, `volCD.reg.right` and
`volMic` — four. The reference writes **five**, the same five as
`updateInputGainLeft`, including the left line channel:

```
 5414: 891550400000   mov  ds:_volMic, edx
 5420: 891548400000   mov  ds:_volLineRight, edx
 5426: 891544400000   mov  ds:_volLineLeft, edx      ; missing from our source
 5432: 891570400000   mov  ds:_volCDRight, edx
 5438: 89156C400000   mov  ds:_volCDLeft, edx
```

`updateOutputAttenuationRight` writes `volMaster.reg.right`, `volVoice.reg.left`,
`volVoice.reg.right`, `volCD.reg.left`, `volCD.reg.right` — five. The reference writes
**six**, the same six as `updateOutputAttenuationLeft`, including the left master channel:

```
 6495: 893538400000   mov  ds:_volMasterRight, esi
 6501: 893534400000   mov  ds:_volMasterLeft, esi    ; missing from our source
 6507: 893570400000   mov  ds:_volCDRight, esi
 6513: 89356C400000   mov  ds:_volCDLeft, esi
 6519: 893540400000   mov  ds:_volVoiceRight, esi
 6525: 89353C400000   mov  ds:_volVoiceLeft, esi
```

In both methods the reference's store order is right-then-left within each pair and the
whole run is emitted in one block from one register, the shape a chained assignment
produces.

The arithmetic in all four methods matches ours exactly:
`gain ? (gain * 31) >> 15 : 0` as `shl eax,5 / sub eax,edx / shr edx,0Fh` for the gains,
and `((att + 84) * 31) / 84` as `add edx,54h / shl eax,5 / sub eax,edx / xor edx,edx /
div ecx` for the attenuations — **an unsigned divide, which our `unsigned int volume`
produces and a signed `int` could not.**

**Disposition for Task 10:** add the two missing stores.

## Finding 16: the port writes re-read each shadow; our `regValue` local cannot

**Source:** `SoundBlaster16.m:359`, `:383`–`:389`, `:399`–`:408`, `:440`–`:446`,
`:469`–`:475`, `:619`–`:622`

Our `updateInputGainLeft` computes one value and reuses it for three registers:

```c
    regValue = gain << 3;
    outbIXMixer(CT1745_LINE_VOLUME_LEFT, regValue);
    outbIXMixer(CT1745_CD_VOLUME_LEFT, regValue);
    outbIXMixer(CT1745_MIC_VOLUME, regValue);
```

The reference reloads each shadow from memory immediately before its own port write:

```
 5180: 8A1D44400000   mov  bl, byte ptr ds:_volLineLeft
 5186: C0E303         shl  bl, 3
 ...   out 38h ; IODelay(15) ; out bl ; IODelay(75)
 5243: 8A1D6C400000   mov  bl, byte ptr ds:_volCDLeft
 5249: C0E303         shl  bl, 3
 ...   out 36h ; ...
 5306: 8A1D50400000   mov  bl, byte ptr ds:_volMic
 5312: C0E303         shl  bl, 3
 ...   out 3Ah ; ...
```

A value held in a register cannot produce three `mov bl, byte ptr ds:…` loads from three
different addresses. The same pattern holds in `updateOutputMute` (`_volVoiceLeft`,
`_volVoiceRight`, `_volMasterLeft`, `_volMasterRight` at 5876, 5939, 6002, 6065), both
attenuation methods, and the volume restore at the head of `startDMAForChannel:`
(7457, 7524, 7591, 7658).

Our `updateInputGainRight` (`.m:383`–`:389`) and `updateOutputMute` (`.m:399`–`:408`)
already re-read the shadows and are correct in form; `updateInputGainLeft`,
`updateOutputAttenuationLeft`/`Right` and `startDMAForChannel:` are not.

**Disposition for Task 10:** write `outbIXMixer(reg, shadow << 3)` at every site, with no
shared `regValue`.

## Finding 17: `updateOutputMute`'s branches are the wrong way round

**Source:** `SoundBlaster16.m:397`–`:416`

```c
    if (![self isOutputMuted]) {
        /* restore */
    } else {
        /* zeros */
    }
```

The reference tests the un-negated result and puts the mute block first:

```
 5654: E8E5E9FFFF     call _objc_msgSend            ; [self isOutputMuted]
 5659: 88C2           mov  dl, al
 5664: 84D2           test dl, dl
 5666: 0F84CC000000   jz   loc_16F4                 ; -> 5876, the restore block
 5672: ...            the four zero writes: 32h, 33h, 30h, 31h
 5870: E9EB000000     jmp  loc_17DE                 ; end
 5876: ...            the four shadow writes: 32h, 33h, 30h, 31h
```

`if (!cond) A else B` emits `test / jnz B`; the reference emits `test / jz` with the mute
block inline, which is `if ([self isOutputMuted]) { mute } else { restore }`. The register
order within each block, `32h 33h 30h 31h`, matches ours exactly, and the mute block writes
literal zeros (`xor al, al`) as ours does.

**Disposition for Task 10:** swap the two blocks and drop the `!`. Behaviour is identical;
only the emitted instructions differ.

## Finding 18: `startDMAForChannel:` differs in five places

**Source:** `SoundBlaster16.m:613`, `:640`–`:643`, `:681`–`:684`, `:696`, `:704`, `:716`

1. **`interruptTimedOut = NO` at `:613` has no counterpart.** There is no store to
   `[ebx+188h]` anywhere in this function; the only writes to that ivar in the binary are
   `timeoutOccurred`'s `cmp` at 10376 and `mov …, 1` at 13377.

2. **`actualChannel` defaults to `localChannel`, not to 0.** `esi` is loaded from the
   `localChannel` argument at 7423 and only overwritten inside the two-channel arm:

```
 7423: 8B7510         mov  esi, [ebp+arg_8]         ; actualChannel = localChannel
 ...
 7766: 83BB9001000002 cmp  dword ptr [ebx+190h], 2  ; dmaChannelsAvailable == 2 ?
 7773: 750B           jnz  loc_1E6A                 ; -> 7786, keep localChannel
 7775: 31F6           xor  esi, esi                 ; actualChannel = 0
 7777: 81FA58020000   cmp  edx, 258h                ; encoding == Linear16 ?
 7783: 7501           jnz  loc_1E6A
 7785: 46             inc  esi                      ; actualChannel = 1
```

   Our `.m:640` writes `actualChannel = 0;` unconditionally.

3. **`[self channelCount]` is sent only on the read path.** The reference tests `isRead`,
   *then* sends `channelCount`, then compares against 1 (7979–8009). Our `:681` sends it
   unconditionally and tests `isRead && (channelCount == 1)` afterwards. The reference then
   tests `isRead` a **second** time at 8065 for the record/playback split, matching two
   separate `if (isRead)` statements in Apple's source, which is our shape at `:682` and
   `:689`.

4. **The DMA command is assembled with separate `|=` statements, and the playback path
   clears the ADC bit.** Record path, 8081–8143:

```
 8081: C6059040000000 mov ds:_sbStartDMACommand, 0
 8088: 81FA58020000   cmp edx, 258h
 8096: C60590400000B0 mov ds:_sbStartDMACommand, 0B0h
 8108: 8025904000000F and ds:_sbStartDMACommand, 0Fh   ; else: high nibble <- 0Ch
 8115: 800D90400000C0 or  ds:_sbStartDMACommand, 0C0h
 8122: 800D9040000008 or  ds:_sbStartDMACommand, 8     ; DMA_MODE_ADC
 8129: 800D9040000004 or  ds:_sbStartDMACommand, 4     ; DMA_MODE_AUTO_INIT
 8136: 800D9040000002 or  ds:_sbStartDMACommand, 2     ; DMA_MODE_FIFO
```

   playback path, 8634–8695, identical except `and 0F7h` (clear `DMA_MODE_ADC`) in place of
   `or 8`. Our `:696` and `:704` fold the flags into one `|= 0x0e` / `|= 0x06` and the
   playback arm never clears bit 3. Three separate `or byte ptr [addr], imm` cannot come
   from one `|=`.

5. **There is no `IODelay(50)` between the mode byte and the count bytes**, and each of the
   four DSP writes is preceded by the full 10000-iteration write-wait of Finding 4, not by
   `writeToDSP()`. Our `:716` inserts `IODelay(50)`.

The rest matches: `[self isOutputMuted]` and the four-register volume restore, the
`currentDMADirection` store as `setz`/`and 0FFh`, `[self dataEncoding]` into
`currentEncoding`, `startDMAForBuffer:channel:` / `enableAllInterrupts` /
`enableChannel:` in that order with their three distinct `IOLog` messages including
`%s: could not enable interrupts%d\n`, `[self updateSampleRate]` then
`[self setBufferCount:bufferSize]`, `outbIXMixer(3Dh, 1Fh)` on the mono record path, the
`sbBufferCounter >>= 1` for 16-bit and the `--`, and the four DSP bytes
`sbStartDMACommand`, `sbStartDMAMode`, `sbBufferCounter & 0xff`,
`sbBufferCounter >> 8` (emitted as `mov al, byte ptr ds:_sbBufferCounter+1`).

## Finding 19: `stopDMAForChannel:read:` ignores `read:` where the reference branches on it

**Source:** `SoundBlaster16.m:741`–`:745`, `:753`–`:756`, `:768`

Three differences:

1. **The reference tests `isRead` and emits the whole stop sequence twice.**

```
 9321: 807DFC00       cmp  [ebp+var_4], 0           ; var_4 = the read: argument
 9325: 0F8401010000   jz   loc_2574                 ; -> 9588, the second copy
 9331: 8BB78C010000   mov  esi, [edi+18Ch]          ; currentEncoding
 ...   write-wait
 9443: 81FE59020000   cmp  esi, 259h                ; == Linear8 ?
 9449: 750D           jnz  loc_24F8
 9458: B0D5           mov  al, 0D5h                 ; DC16_PAUSE_16BIT_DMA
 9471: B0D0           mov  al, 0D0h                 ; DC16_PAUSE_8BIT_DMA
 ...   out ; IODelay(75) ; reset pulse ; read-wait
 9583: E9F7000000     jmp  loc_266B
 9588: 8BB78C010000   mov  esi, [edi+18Ch]          ; the identical second copy
```

   Both arms are instruction-identical, which is what two calls to one inline helper from
   the two arms of `if (isRead) … else …` produce — the shape drvSB8Sound recorded for its
   `stopDMAInput()`/`stopDMAOutput()` pair. Our `.m:741` has a single call site and no
   `isRead` test at all.

   **This function carries four DSP wait expansions, two per arm** — the `cmp …, 270Fh`
   bound tests are at 9363 and 9575 (the `isRead` arm's write-wait and read-wait) and at
   9619 and 9827 (the same pair in the second copy). Task 10 must emit two waits inside the
   shared helper, so that the two call sites produce four.

   **The inverted pause-command selection our source comments on is correct**:
   `currentEncoding == Linear8` selects `0D5h`, the 16-bit pause, exactly as `:741`–`:745`
   says.

2. **`actualChannel` defaults to `localChannel`**, as in Finding 18. The reference reuses
   the argument slot as the local:

```
 9959: 83BF9001000002 cmp  dword ptr [edi+190h], 2
 9966: 7516           jnz  loc_2706                 ; keep localChannel
 9968: C7451000000000 mov  [ebp+arg_8], 0
 9975: 81BF8C01000058020000 cmp dword ptr [edi+18Ch], 258h
 9985: 7503           jnz  loc_2706
 9987: FF4510         inc  [ebp+arg_8]
```

3. **The mono-record restore writes `_inputMixerSwitchLeft`, not the literal `0x15`.**

```
10047: 8A1D88400000   mov  bl, ds:_inputMixerSwitchLeft
10053: ...            out 3Dh ; IODelay(15) ; out bl ; IODelay(75)
```

   Our `:768` writes `outbIXMixer(MC16_INPUT_CONTROL_LEFT, 0x15)`. The value happens to be
   the shadow's initialiser (Q3), but a literal cannot emit the `mov bl, ds:…` load. This is
   drvES1x88Sound's Finding 3 recurring.

The rest matches: `[self disableAllInterrupts]` first, `IOSleep(50)` (`push 32h` at 9949),
`SoundBlaster16: Can not reset DSP.\n` on a reset response other than `0AAh` (9928–9936),
`[self disableChannel:actualChannel]`, `currentDMADirection = 2`
(`mov dword ptr [edi+184h], 2` at 10006), and the `isRead && channelCount == 1` guard on
the restore.

## Finding 20: `_clearInterrupts` counts interrupts the reference does not, and re-reads the status byte

**Source:** `SoundBlaster16Inline.h:479`, `:494`–`:495`

```c
    outbV(sbMixerAddressReg, MC16_IRQ_STATUS);
    interruptCount++;
    IODelay(15);
```

**There is no `_interruptCount` symbol in `__DATA,__data`, `__DATA,__bss` or `__common`.**
The reference's whole body, 10116–10211:

```
10120: 668B152C400000 mov  dx, word ptr ds:_sbMixerAddressReg
10127: B082           mov  al, 82h                  ; MC16_IRQ_STATUS
10129: EE             out  dx, al
10130: F0FF0594400000 lock incl ds:_xxx.86
10137: 6A0F           push 0Fh                      ; IODelay(15)
10144: 668B1530400000 mov  dx, word ptr ds:_sbMixerDataReg
10154: EC             in   al, dx
10159: 6A4B           push 4Bh                      ; IODelay(75)
10166: 881DA4400000   mov  ds:_interruptStatus, bl
10172: F6C302         test bl, 2                    ; IRQ_STATUS_16BIT, from the register
10175: 740B           jz   loc_27CC
10177: 668B1528400000 mov  dx, word ptr ds:_sbAck16bitInterrupt
10184: EB12           jmp  loc_27DC
10188: F605A440000001 test ds:_interruptStatus, 1   ; IRQ_STATUS_8BIT, re-read from memory
10195: 7408           jz   loc_27DD
10197: 668B1524400000 mov  dx, word ptr ds:_sbAck8bitInterrupt
10204: EC             in   al, dx
```

Two differences from `Inline.h:468`–`:499`:

1. `interruptCount++` is extra. `lock incl` of a fourth `__bss` counter would be plainly
   visible between 10129 and 10137 and is not there.
2. **The 8-bit test reads `_interruptStatus` back from memory**, where the 16-bit test uses
   the register. Our source tests the local `status` both times. Apple's second test is on
   the global.

The overall shape — assign the 16-bit ack register, take it if bit 1 is set, otherwise
assign the 8-bit ack register and take it if bit 0 is set, otherwise read nothing — is
exactly what our comma-operator construct at `:493`–`:498` produces, and the `IODelay(15)`
and `IODelay(75)` match once Finding 3 is applied.

**Disposition for Task 10:** remove `interruptCount`, and test `interruptStatus` rather
than `status` in the second arm.

## Finding 21: `interruptOccurredForInput:forOutput:` stores the status byte before acknowledging

**Source:** `SoundBlaster16.m:799`–`:806`

Our source acknowledges the interrupt and *then* records the status:

```c
    ackReg = sbAck16bitInterrupt;
    if ((status & IRQ_STATUS_16BIT) || (ackReg = sbAck8bitInterrupt, (status & IRQ_STATUS_8BIT))) {
        inb(ackReg);
    }
    interruptStatus = status;
```

The reference stores it first, at 10282, before the two tests at 10288 and 10304 — the same
order `_clearInterrupts` uses, and the reason the second test can re-read memory at all.
The remainder of the method is the same inlined `clearInterrupts()` body followed by

```
10321: 83BE8401000001 cmp  dword ptr [esi+184h], 1   ; DMA_DIRECTION_OUT
10328: 7506           jnz  loc_2860
10330: C60701         mov  byte ptr [edi], 1         ; *serviceOutput = YES
10336: 83BE8401000000 cmp  dword ptr [esi+184h], 0   ; DMA_DIRECTION_IN
10343: 7506           jnz  loc_286F
10348: C60001         mov  byte ptr [eax], 1         ; *serviceInput = YES
```

which is `SoundBlaster16.m:811`–`:814` exactly, including the second explicit comparison
against `DMA_DIRECTION_IN` rather than a bare `else`.

**Disposition for Task 10:** move `interruptStatus = status;` above the acknowledge block.
Note that the method duplicates `clearInterrupts()`'s body inline rather than calling it,
which is what our source does too.

## Finding 22: `updateSampleRate` computes the stereo flag once and stores it

**Source:** `SoundBlaster16.m:487`, `:493`, `:569`

Our source keeps `channelCount` and tests it at the end. The reference computes a boolean at
the top and stores it in a stack slot:

```
 6790: E875E5FFFF     call _objc_msgSend            ; [self channelCount]
 6795: 89C2           mov  edx, eax
 6800: 83FA02         cmp  edx, 2
 6803: 0F94C0         setz al
 6806: 25FF000000     and  eax, 0FFh
 6811: 8945F8         mov  [ebp+var_8], eax         ; stereo = (channelCount == 2)
 ...
 7271: 837DF801       cmp  [ebp+var_8], 1
 7275: 750B           jnz  loc_1C78
 7277: 800D9140000020 or   ds:_sbStartDMAMode, 20h  ; DMA_MODE_STEREO
 7288: 802591400000DF and  ds:_sbStartDMAMode, 0DFh
```

`currentDMADirection` is likewise read once into `esi` at 6814 and tested at 6927.

Everything else in this method matches ours closely, and it is the best-matching large
function in the driver: the three 10000-iteration write-waits with their reset pulses and
`SoundBlaster16: DSP write error.\n` logs (Finding 4's model), the `0x42`/`0x41` command
selection converging on one shared `out dx, al` at 6953, the `IODelay(75)` after each byte,
`rate >> 8` then `rate & 0xff`, and the `sbStartDMAMode` bit updates as paired
`and imm`/`or imm` memory operations — which is what our `&= ~DMA_MODE_SIGNED` /
`|= DMA_MODE_SIGNED` produce. The `cmp dword ptr [edi+18Ch], 259h` at 7240 is Finding 11's
evidence that `currentEncoding` is an `unsigned int`.

**Disposition for Task 10:** replace `unsigned int channelCount` with a
`BOOL stereo = ([self channelCount] == 2);` computed at the top, and hoist
`currentDMADirection` into a local read once.

## Finding 23: two inline helpers in our tree have no caller and no counterpart

**Source:** `SoundBlaster16Inline.h:303`–`:320`, `:535`–`:570`

`resetDSPQuick()` and `checkSelectedDMAAndIRQ()` are defined and never called. `grep` over
both source files finds only their definitions. Neither has a counterpart in the reference:
there is no quick-reset path anywhere (`stopDMAForChannel:read:` inlines its own reset and
`0AAh` check), and the DMA/IRQ validation lives in `initializeDMAChannels` and `reset`
respectively, in the forms Findings 10 and Q1 record.

Between them they carry six string literals that are not `#ifdef DEBUG`-guarded and not in
the reference's `__cstring`:

| String | Our source |
| --- | --- |
| `SoundBlaster16: DSP reset failed, got %x instead of 0xaa\n` | `Inline.h:317` |
| `SoundBlaster16: 8-bit DMA channel must be 0, 1, or 3.\n` | `:545` |
| `SoundBlaster16: 16-bit DMA channel must be 5, 6, or 7.\n` | `:552` |
| `SoundBlaster16: 8-bit and 16-bit DMA channels must be different.\n` | `:558` |
| `SoundBlaster16: IRQ is %d.\n` | `:564` |
| `SoundBlaster16: IRQ must be 2, 5, 7, or 10.\n` | `:565` |

Being `static __inline__` and uncalled, neither function is emitted and none of these
strings would reach a build's `__cstring`, which is why their absence from the reference is
consistent rather than surprising. **`checkSelectedDMAAndIRQ()` is nevertheless the source
of the IRQ contradiction in Q1 and the reason our tree appears to disagree with its own
`Default.table`.**

**Disposition for Task 10:** remove both. They are pre-existing dead code, but they are
dead code that contradicts the shipped configuration, so this is worth doing even under the
surgical-changes rule.

Three further unguarded literals in our source have no counterpart, and they are *not* in
dead code — they are the three `sb16CardParameters_t.name` assignments in `resetDSP()`
that Finding 1 removes: `""` at `Inline.h:333`, `"Sound Blaster 16"` at `:391` and
`"Sound Blaster Pro"` at `:401`. None is in the reference's `__cstring`, because the
reference's card-parameter struct has no `name` member.

**Every other string literal in our source is either in the reference's `__cstring` or
under `#ifdef DEBUG`.** The `#ifdef DEBUG` set is `SoundBlaster16.m:53`, `:60`, `:607`,
`:731`, `:785` and `SoundBlaster16Inline.h:54`, `:141`, `:172`, `:192`, `:214`, `:233`,
`:245`, `:350`, `:358`, `:364`, `:383` — not findings in either direction. The reference's
`__cstring` holds twenty-five strings and every one of the twenty-three that our source can
emit is present; the two that are not are Q2's `DSP read error` and `SoundBlaster not
detected`.

## Finding 24: three globals sit in the wrong section

**Source:** `SoundBlaster16.m:18`; `SoundBlaster16Inline.h:94`, `:108`

Within this one translation unit the reference distinguishes zero-valued statics by
section: `_sbStartDMACommand` and `_sbStartDMAMode` are zero and in `__DATA,__data`, while
`_sbBufferCounter` and `_interruptStatus` are zero and in `__DATA,__bss`. The only
plausible distinguisher is the presence of an explicit initialiser, which puts
`= 0` statics in `__data` — the same behaviour drvSB8Sound observed for its eight
zero-initialised mixer shadows.

On that reading:

| Symbol | Reference section | Our declaration | Implied Apple declaration |
| --- | --- | --- | --- |
| `_sbCardType` | `__data`, 16384 | `.m:18`, no initialiser | `= {0}` |
| `_sbBufferCounter` | `__bss`, 16544 | `Inline.h:108` `= 0` | no initialiser |
| `_interruptStatus` | `__bss`, 16548 | `Inline.h:94` `= 0` | no initialiser |

**This is an inference from one translation unit's section placement, flagged as such.** It
is behaviourally neutral and low priority; Task 10 should not restructure anything on the
strength of it beyond adding or removing the three initialisers.

`_sbBufferCounter` is four bytes (`shr ds:_sbBufferCounter, 1`, `dec`, and the byte reads at
`+0` and `+1`), matching our `unsigned int`. `_interruptStatus` is one byte
(`mov ds:_interruptStatus, bl`, `test ds:_interruptStatus, 1`), matching our
`unsigned char`.

## Finding 25: the method definition order differs

**Source:** `SoundBlaster16.m:87`, `:163`

IDA's address order is `+probe:` (0), `initializeDMAChannels` (288), `reset` (1276),
`initializeHardware` (1672), … so Apple's `.m` defines `initializeDMAChannels` **before**
`reset`. Ours defines `reset` at `:87` and `initializeDMAChannels` at `:163`.
`__OBJC,__inst_meth`'s order — `channelCountLimit` first, `initializeDMAChannels` last — is
the reverse of definition order and confirms it independently. Every other method is in the
same relative position on both sides.

This shifts every function address downstream of 288 and is worth fixing before any
address-level comparison of a rebuilt binary, but it changes no behaviour.

**Disposition for Task 10:** move `-initializeDMAChannels` above `-reset`.
