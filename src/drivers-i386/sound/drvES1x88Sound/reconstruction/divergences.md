# drvES1x88Sound divergences

Reference: `ES1x88AudioDriver.config/ES1x88AudioDriver_reloc`, 53280 bytes,
SHA-256 `196F94DC778DB5A2AFE7763A2F4559ED96F27B46AB813674A5C098B75667DAD3`
Analyses: IDA 9.2 and angr 9.3.0. **Ghidra 12.1 is disabled for this driver.**
`run-summary.json` reports `complete: true` with a non-null reference consensus and three
files in `published/`.

## Stated limitation: the analyzer set is reduced to two

Ghidra reaches the end of its own analysis on this binary but `normalize.py:432` then
rejects its output with `Ghidra relocation operand metadata is ambiguous`, which writes
`complete: false` and no consensus. This is the failure the shared procedure names, and
the approved response was taken: `analyzers.ghidra.enabled` was set to `false` in
`tools/binrecon/profiles/es1x88audiodriver.json` in its own commit, and the run was
repeated with IDA and angr. **Every statement in this document therefore rests on two
analyzers, not the three drvBeepSound and drvSB8Sound had.** The analyzer-disagreement
section below covers IDA against angr only, and `published/` holds three files rather than
four.

One environmental note, recorded so a later pass does not mistake it for a property of the
binary. This report was produced in a `git worktree` under
`D:\RhapsodiOS\.claude\worktrees\audio-recon`. Ghidra's headless launcher refuses any
project path containing a dot-prefixed element (`GhidraURL.checkValidProjectPath`,
`Path element starting with '.' is not permitted`), so the first two runs failed with the
uninformative `Ghidra failed with exit code 1` before Ghidra ever looked at the input.
`tools/binrecon/out/es1x88audiodriver` was redirected through a directory junction to a
dot-free path, at which point Ghidra ran to completion and produced the *real*
normalization failure above. The junction is outside the repository and affects only
gitignored analyzer output.

## Baseline build

**Unmeasured.** No rebuilt artifact exists for this driver; the guest was not used in this
pass. Every statement below is derived from the reference binary and from our source text
alone.

Reference `Loaded Server` sections, read from the Mach-O section table:

| Section | Size | Content |
| --- | --- | --- |
| `Server Name` | 17 | `ES1x88AudioDriver` |
| `Load Commands` | 144 | the audio `SMAP`/`ADVERTISE`/`WIRE` block |
| `Instance Var` | 26 | `ES1x88AudioDriver_instance` |
| `Server Version` | 1 | `2` |

There is **no** `Unload Commands` section, matching the expectation for all four audio
drivers, and `Load Commands` is 144 bytes as the shared procedure predicts. Our
`ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/Load_Commands.sect` is 144 bytes and
is **byte-identical** to the reference's `Load Commands` section, verified with `cmp`
against the section extracted at file offset 35181. That is a positive result, not a
finding.

`__TEXT,__const` holds the SGS build stamp
`@(#)PROGRAM:ES1x88AudioDriver  PROJECT:drvES1x88Sound-10  DEVELOPER:root  BUILT:Sat Mar
28 22:07:21 PST 1998` and the `"10"` version number, both emitted by Apple's build and out
of every comparison by the Global Constraints.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 23 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

All 25 reference functions land in exactly one bucket and every one carries a ledger entry.

Ledger status counts **as this report pass left them**: `assembly-matched` 12,
`unexamined` 11, `intentional-mismatch` 2. The eleven `unexamined` entries are the eleven
functions carrying a divergence; per the drvPCIBus convention their status was held here
and advancing it was Task 8's job. **Task 8 has since run**; the counts are now
`assembly-matched` 21 and `intentional-mismatch` 4, and the outcome of every finding is
recorded in "Task 8 fix-pass resolutions" at the end of this document.

**The asymmetry runs one way.** There is no reference function our source lacks. Both
`unmapped` entries are build-generated glue. The four extra methods our source carries
have no reference counterpart at all and so cannot appear in a map that partitions
*reference* functions; they are recorded below under "The excision gate".

Note on sizes: the ledger and source map use IDA's function-body sizes (298, 1094, 1237,
229, 551, 367, 1325, 41, 1578, 540, 48, 15, 12, 360, 133, 12, 25, 53, 32, 12), not the
padded gap-to-next-symbol sizes (300, 1096, 1240, 232, 552, 368, 1328, 44, 1580, 540, 48,
16, 12, 360, 136, 12, 28, 56, 32, 12). `validate_source_map_semantics` enforces the
former.

## Examination depth

Twelve functions were read **at instruction level**, top to bottom, against our source,
and carry `assembly-matched`: `updateInputGainLeft`, `updateInputGainRight`,
`enableAllInterrupts`, `disableAllInterrupts`, `stopDMAForChannel:read:`,
`interruptOccurredForInput:forOutput:`, `_clearInterrupts`, `interruptClearFunc`,
`acceptsContinuousSamplingRates`, `getSamplingRatesLow:high:`, `getSamplingRates:count:`
and `channelCountLimit`.

Eleven functions were also read at instruction level but **diverge** and are held
`unexamined`: `+probe:`, `reset`, `initializeHardware`, `updateOutputMute`,
`updateOutputAttenuationLeft`, `updateOutputAttenuationRight`,
`configureHardwareForDataTransfer:`,
`startDMAForChannel:read:buffer:bufferSizeForInterrupts:`, `timeoutOccurred`,
`setAnalogInputSource:` and `getDataEncodings:count:`. For the three largest of these —
`configureHardwareForDataTransfer:` (379 instructions), `startDMAForChannel:` (approx.
430) and `initializeHardware` (318) — the long `outbIXMixer()` and `waitForDSP*()`
expansions recur dozens of times; each distinct expansion was read in full once and every
later occurrence was checked mechanically on `(mnemonic, operands)` with only the port
address and data immediate varying. No instruction was skipped or assumed, but that
mechanical step is weaker than a fresh reading and is recorded as such.

The two build-generated glue methods are `intentional-mismatch`.

Ghidra's decompiler was **not** available as an independent cross-check on this driver.

## Weaker evidence: one function whose `source_line` is an include site

`source-map`'s `source_sites` glob matches `*.m` and `*.c` in `--source-dir`
non-recursively, so it never sees `ES1x88AudioDriverInline.h`.

| Reference | Address | Size | Mapped to | Actual definition |
| --- | --- | --- | --- | --- |
| `_clearInterrupts` | 7972 | 15 | `ES1x88AudioDriver.m:24` | `ES1x88AudioDriverInline.h:177`–`:185` |

`ES1x88AudioDriver.m:24` is the `#import "ES1x88AudioDriverInline.h"` line — the
translation unit that pulls the definition in, not the definition itself. **Task 8 must
read that `source_line` as an include site, not a definition.** This follows the precedent
drvSB8Sound set for `_writeToDSP` and `_readFromDSP`. The body itself was read instruction
by instruction against the header text; only the line number is indirect.

Our `clearInterrupts()` is `static __inline__`, yet the reference emits it out of line at
7972. That is not a divergence: `-[ES1x88AudioDriver interruptClearFunc]` takes its
address (`mov eax, offset _clearInterrupts` at 7991), which forces an out-of-line copy.
The symbol is `local` in the raw nlist, matching `static`. Every other helper in that
header — `assignDSPRegAddresses`, `assignMixerRegAddresses`, `outbIXMixer`,
`waitForDSPDataAvailable`, `waitForDSPWriteReady` — is inlined into its callers and has no
symbol, which is what our `static __inline__` qualifiers predict. `programDMASelect()` has
no counterpart anywhere; see the excision gate.

## Unmapped

Two functions, one reason class.

**Build-generated glue** — `+[ES1x88AudioDriverKernelServerInstance kernelServerInstance]`
at 8636 (returns `offset _ES1x88AudioDriver_instance`, `__DATA,__common:16444`) and
`+[ES1x88AudioDriverVersion driverKitVersionForES1x88AudioDriver]` at 8648 (returns
`0x1F4` = 500). Emitted by the Kernel Server project type, not written by hand. Accepted;
recorded `intentional-mismatch` in the ledger.

Like drvSB8Sound and unlike drvBeepSound, this driver has **no** "no source counterpart"
entry: `+[ES1x88AudioDriver probe:]` is present in `ES1x88AudioDriver.m:31`.

Data symbols outside `__TEXT,__text` do not appear in the source map. They are covered by
the `__DATA` section below.

## Analyzer disagreement

Function counts: IDA 25, angr 88. Ghidra did not contribute.

**Every one of IDA's 25 functions is present in angr at the same address, with identical
size and identical instruction count.** There is no body disagreement anywhere in this
binary. Basic-block counts differ, which is purely each analyzer's block-splitting
convention.

**angr over-splits.** Its 88 functions include 63 addresses that are not function starts
in IDA's partition: 137, 298, 514, 653, 747, 779, 811, 843, 877, 894, 910, 1002, 1031,
1047, 1063, 1079, 1094, 1279, 1346, 1394, 2633, 2678, 2865, 2910, 3097, 3382, 3617, 3651,
4019, 4387, 4749, 4897, 5234, 5250, 5278, 5482, 5498, 5514, 5610, 5713, 5757, 5801, 5847,
6062, 6255, 6314, 6662, 6678, 6694, 7113, 7178, 7382, 7987, 8223, 8438, 8493, 8533, 8589,
8660, 8684, 8844, 8854, 9560. Most are interior blocks or epilogue tails of functions IDA
reports whole; 8660, 8684 and 8844 are `_codecDeviceName`,
`_ES1x88AudioDriver_VERS_STRING` and `_ES1x88AudioDriver_VERS_NUM` in `__TEXT,__const` and
8854 is the head of `__TEXT,__cstring`, i.e. angr disassembling read-only data that
happens to sit in an executable segment. This is `CFGFast` splitting on branch targets,
not a claim that different functions exist there.

`consensus-reference.json` reports `reference_consensus.status: "disputed"` with reason
`conflicting reference evidence`, produced by that over-splitting. **drvSB8Sound's
three-analyzer run reports exactly the same status for the same reason**, so this is the
normal shape of a consensus document in this effort and not a signal about ES1x88.

Unusually for this effort, **angr reported no CFG errors on this binary**
(`extensions.angr.cfg.errors` is empty), despite the `objc_msgSend` dispatch — the same
result drvSB8Sound saw.

---

# The excision gate

This is the section Task 8's removal depends on.

## Step 4 evidence: the four methods have no counterpart anywhere in the reference

Three independent checks, all negative.

**1. No symbol in `__TEXT,__text` or anywhere in the nlist.** `binrecon.macho.read_macho`
substring search over every symbol name:

```
initializeDMAChannels: ABSENT
initializeLastStageGainRegisters: ABSENT
updateSampleRate: ABSENT
setBufferCount: ABSENT
```

The reference's `__TEXT,__text` holds exactly 25 functions, all named above. None of the
four is among them.

**2. No selector in `__OBJC,__inst_meth`, which is what the runtime dispatches through.**
The section is 260 bytes at 25008: an 8-byte header plus **21** 12-byte entries. Read in
full:

```
channelCountLimit  getDataEncodings:count:  getSamplingRates:count:
getSamplingRatesLow:high:  acceptsContinuousSamplingRates  setAnalogInputSource:
timeoutOccurred  interruptClearFunc  interruptOccurredForInput:forOutput:
stopDMAForChannel:read:  startDMAForChannel:read:buffer:bufferSizeForInterrupts:
disableAllInterrupts  enableAllInterrupts  configureHardwareForDataTransfer:
updateOutputAttenuationRight  updateOutputAttenuationLeft  updateOutputMute
updateInputGainRight  updateInputGainLeft  initializeHardware  reset
```

`__OBJC,__cls_meth` holds exactly one entry, `probe:`. **None of the four selectors is
present in either list.** Every entry's `imp` field points at one of IDA's 25 function
addresses, so there is no selector without a body and no body without a selector.

**3. No selector name in `__OBJC,__meth_var_names` either.** That pool is the union of
every selector the translation unit emits *or sends*, 57 names, read in full. It contains
neither the four selectors nor any name unique to their bodies. In particular it contains
no `stringValue` — see Finding 1.

**Nothing in the reference calls into their logic.** Every `objc_msgSend` and
`objc_msgSendSuper` site in the binary resolves through `__OBJC,__message_refs`, whose 33
entries were decoded to selector strings; none of the four appears. There is no indirect
call in `__text` that is not an `objc_msgSend`/`objc_msgSendSuper` through that table.

**Conclusion: the excision of all four is evidenced.** Task 8 may remove
`initializeDMAChannels`, `initializeLastStageGainRegisters`, `updateSampleRate` and
`setBufferCount:` from `ES1x88AudioDriver.m` and their declarations from
`ES1x88AudioDriver.h`.

## Step 5 answer A: the sample-rate work lives in `configureHardwareForDataTransfer:`

**Established, at instruction level.** `-[ES1x88AudioDriver configureHardwareForDataTransfer:]`
(4388, 1325 bytes) programs the ESS sample-rate register `A1h` and filter register `A2h`
directly, and it is the only place in the binary that sets a rate.

```
 4865: 8B75FC       mov  esi, [ebp+var_4]        ; sampleRate, from [self sampleRate]
 4868: 81FEF0550000 cmp  esi, 55F0h              ; rate <= 22000, i.e. rate < 22001
 4874: 7718         ja   loc_1324                ; -> 4900
 4876: B884110600   mov  eax, 61184h
 4881: 31D2         xor  edx, edx
 4883: F7F6         div  esi                     ; 0x61184 / rate
 4885: BB80000000   mov  ebx, 80h
 4890: 29C3         sub  ebx, eax                ; 0x80 - quotient
 4892: 83E37F       and  ebx, 7Fh                ; & 0x7F
 4895: EB16         jmp  loc_1337                ; -> 4919
 4900: B86C230C00   mov  eax, 0C236Ch
 4905: 31D2         xor  edx, edx
 4907: F7F6         div  esi                     ; 0xC236C / rate
 4909: BB00010000   mov  ebx, 100h
 4914: 29C3         sub  ebx, eax                ; negate in a byte
 4916: 80CB80       or   bl, 80h                 ; | 0x80
 4919: ... out A1h ; IODelay(25) ; out bl ; IODelay(25)

 4975: 89F0         mov  eax, esi
 4977: C1E005       shl  eax, 5                  ; rate * 32
 4980: 01C6         add  esi, eax                ; rate * 33  (ES_FILTER_DIVISOR)
 4982: BAC0406D00   mov  edx, 6D40C0h            ; ES_FILTER_CONST
 4991: F7F6         div  esi
 4995: BB00010000   mov  ebx, 100h
 5000: 29CB         sub  ebx, ecx                ; negate in a byte
 5002: ... out A2h ; IODelay(25) ; out bl ; IODelay(25)
```

That is `ES1x88AudioDriver.m:872`–`:886` line for line, including
`ES_SAMPLE_RATE_THRESHOLD` `0x55F1`, `ES_SAMPLE_RATE_CONST_LOW` `0x61184`,
`ES_SAMPLE_RATE_CONST_HIGH` `0xC236C`, `ES_FILTER_CONST` `0x6D40C0` and
`ES_FILTER_DIVISOR` `0x21`.

**Nothing in the reference does what our `updateSampleRate` (`ES1x88AudioDriver.m:705`–`:795`)
does.** That method is SoundBlaster16 code: it writes DSP commands `41h`/`42h`
(`DC16_SET_SAMPLE_RATE_OUTPUT`/`_INPUT`) followed by the rate as two bytes, with three
copies of a 10000-iteration busy-wait that logs `ES1x88AudioDriver: DSP write error.\n`,
and it then updates `sbStartDMAMode` with `DMA_MODE_SIGNED`/`DMA_MODE_STEREO`. Neither
`41h` nor `42h` is ever written to `sbWriteDataOrCommandReg` anywhere in the reference;
the string `DSP write error` is not in `__cstring`; and `_sbStartDMAMode`,
`_sbStartDMACommand` and `_is16BitTransfer` have no symbol or ivar in the reference. The
stereo/mono and 8-/16-bit selection our `updateSampleRate` performs is done by the
reference through ES registers `A8h` (audio mode), `B6h` (output mode) and `B7h` (audio
control 1), all inside `configureHardwareForDataTransfer:`.

**What Task 8 must do:** remove `updateSampleRate` outright. Its work is *already* present
in our `configureHardwareForDataTransfer:` at `:872`–`:886` and `:904`–`:943`; nothing
needs relocating. Our `configureHardwareForDataTransfer:` is called from our
`startDMAForChannel:` at `:1044`, matching the reference's send at 6191, and our
`updateSampleRate` is called from nowhere at all — it is dead code in our own tree.

## Step 5 answer B: the DMA-channel validation lives in `-[ES1x88AudioDriver reset]`

**Established, at instruction level.** Both `Audio DMA channel is %d` and
`2nd Audio DMA channel is %d` are referenced from exactly one function each, and it is the
same one: `-[ES1x88AudioDriver reset]` at 300.

```
 516: 89F3       mov  ebx, esi              ; dmaChannel2 = dmaChannel1
 518: B101       mov  cl, 1                 ; BOOL valid = YES
 520: 83FE01     cmp  esi, 1                ; dmaChannel1 <= 1  (0 or 1 accepted)
 523: 761F       jbe  loc_22C
 525: 83FE03     cmp  esi, 3
 528: 741A       jz   loc_22C
 530: 56         push esi
 531: 68BD220000 push offset "ES1x88AudioDriver: Audio DMA channel is %d.\n"
 536: E8E3FDFFFF call _IOLog
 541: 68EA220000 push offset "ES1x88AudioDriver: Audio DMA channel must be one of 0, 1, 3.\n"
 546: E8D9FDFFFF call _IOLog
 551: 30C9       xor  cl, cl                ; valid = NO
 556: 39F3       cmp  ebx, esi              ; dmaChannel2 == dmaChannel1 -> skip
 558: 7424       jz   loc_254
 560: 83FB01     cmp  ebx, 1
 563: 761F       jbe  loc_254
 565: 83FB03     cmp  ebx, 3
 568: 741A       jz   loc_254
 570: 53         push ebx
 571: 6828230000 push offset "ES1x88AudioDriver: 2nd Audio DMA channel is %d.\n"
 576: E8BBFDFFFF call _IOLog
 581: 6859230000 push offset "ES1x88AudioDriver: 2nd Audio DMA channel must be one of 0, 1, 3.\n"
 586: E8B1FDFFFF call _IOLog
 591: 30C9       xor  cl, cl
 596: 83FF09     cmp  edi, 9                ; interrupt
 ...                                        ; 5, 7, 0Ah, then the two IRQ IOLogs
 642: 84C9       test cl, cl
 644: 750A       jnz  loc_290
 646: 31C0       xor  eax, eax              ; return NO
```

`ebx` and `esi` come from `channelList[1]` and `channelList[0]`; `edi` from
`[deviceDescription interrupt]`. This is `ES1x88AudioDriver.m:103`–`:125` exactly,
including the `BOOL valid = YES` accumulator that lets all three failures log before the
single `return NO`, and including the "second channel equal to the first is not
re-checked" short-circuit at 556.

**Both channels the reference validates are ordinary 8-bit ISA channels: 0, 1 or 3.**
There is no 16-bit channel anywhere. `disableChannel:` is sent with a literal `0` at 1130
and again in the `while (numChannels > 1)` loop at 1348–1377, matching
`ES1x88AudioDriver.m:184` and `:207`–`:210`. `setDMATransferWidth:forChannel:`,
`setTransferMode:forChannel:` and `setAutoinitialize:forChannel:` are each sent exactly
once, all with `forChannel:0`. The mixer DMA-select register `81h` (`MC16_DMA_SELECT`) is
never written.

**What Task 8 must do:** remove `initializeDMAChannels` outright. Its 8-bit validation is
already in our `reset` at `:103`–`:114` in the reference's exact form; its 16-bit half
(`dma16Channel`, `MC16_DMA_SELECT`, the `IO_16Bit` transfer-width call) has no hardware to
address on an ES-1688 and no counterpart in the reference. Our `initializeDMAChannels` is,
like `updateSampleRate`, called from nowhere in our own tree. `programDMASelect()`
(`ES1x88AudioDriverInline.h:190`–`:216`) is its only caller-side dependency and becomes
dead with it.

## The other two: `initializeLastStageGainRegisters` and `setBufferCount:`

Their SoundBlaster16 origin is unambiguous and needs no inference.

- `initializeLastStageGainRegisters` (`ES1x88AudioDriver.m:456`–`:492`) reads the config
  keys `"LS Input Gain"` and `"LS Output Gain"` and writes the SB16 mixer registers
  `MC16_INPUT_GAIN_LEFT` `3Fh`, `MC16_INPUT_GAIN_RIGHT` `40h`, `MC16_OUTPUT_GAIN_LEFT`
  `41h` and `MC16_OUTPUT_GAIN_RIGHT` `42h`. Neither string is in the reference's
  `__cstring`; the only config key the reference reads is `"Input Source"` at 9258. None
  of those four mixer register addresses is ever written. The four backing variables
  `_lastStageGainInputLeft`, `_lastStageGainInputRight`, `_lastStageGainOutputLeft` and
  `_lastStageGainOutputRight` (`ES1x88AudioDriverInline.h:74`–`:77`) have no symbol in
  `__DATA,__data`, which holds exactly the fifteen symbols listed below and no others.
- `setBufferCount:` (`ES1x88AudioDriver.m:981`–`:984`) assigns `sbBufferCounter`.
  `_sbBufferCounter` has no symbol in the reference's `__DATA,__data` or `__DATA,__bss`,
  and the ES-1688 gets its transfer count from registers `A4h`/`A5h` inside
  `configureHardwareForDataTransfer:` (5058–5193), not from a DSP buffer-count command.

## The strings our source emits that the reference does not

Every one of these comes from the four methods above.

| String | Our source | In reference `__cstring`? |
| --- | --- | --- |
| `ES1x88AudioDriver: 8-bit DMA channel is %d.\n` | `:234`, `:256` | no |
| `ES1x88AudioDriver: 8-Bit DMA channel must be one of 0, 1 and 3.\n` | `:235`, `:257` | no |
| `ES1x88AudioDriver: 16-bit DMA channel is %d.\n` | `:268` | no |
| `ES1x88AudioDriver: 16-Bit DMA channel must be one of 5, 6 and 7.\n` | `:269` | no |
| `%s: Must specify either one or two channels.\n` | `:277` | no |
| `%s: could not set transfer width to 8 bits, error %d.\n` | `:294` | no |
| `%s: could not set transfer width to 16 bits, error %d.\n` | `:324` | no |
| `LS Input Gain` | `:469` | no |
| `LS Output Gain` | `:477` | no |
| `ES1x88AudioDriver: DSP write error.\n` | `:737`, `:757`, `:777` | no |

The reference does carry
`ES1x88AudioDriver: could not set transfer width to 8 bits, error %d.\n` at 9430 — the
`ES1x88AudioDriver:`-prefixed variant our `reset` uses at `:189`. It is the `%s:`-prefixed
variant at `:294`, inside `initializeDMAChannels`, that is extra.

`%s: dma transfer mode error %d\n` and `%s: dma auto initialize error %d` also appear
inside `initializeDMAChannels` (`:302`, `:308`, `:332`, `:338`), but they coalesce with
the copies in `reset` (`:196`, `:202`) which the reference does have, so they add no
`__cstring` entry. Removing `initializeDMAChannels` leaves them referenced from `reset`.

## Positive result: all 23 reference `__cstring` entries are present in our source

`__TEXT,__cstring` runs from 8854 for 796 bytes and holds exactly 23 non-empty strings,
with no zero padding beyond the final terminator.

| Address | String | Our source |
| --- | --- | --- |
| 8854 | `ES1x88AudioDriver: Can not reset DSP.\n` | `.m:1027`, `:1040`, `:1268`, `:1282` |
| 8893 | `ES1x88AudioDriver: Audio DMA channel is %d.\n` | `.m:104` |
| 8938 | `ES1x88AudioDriver: Audio DMA channel must be one of 0, 1, 3.\n` | `.m:105` |
| 9000 | `ES1x88AudioDriver: 2nd Audio DMA channel is %d.\n` | `.m:111` |
| 9049 | `ES1x88AudioDriver: 2nd Audio DMA channel must be one of 0, 1, 3.\n` | `.m:112` |
| 9115 | `ES1x88AudioDriver: Audio irq is %d.\n` | `.m:118` |
| 9152 | `ES1x88AudioDriver: Audio IRQ must be one of 5, 9, 7, 10.\n` | `.m:119` |
| 9210 | `ES1x88AudioDriver: Invalid port address 0x%0x.\n` | `.m:69` |
| 9258 | `Input Source` | `.m:132` |
| 9271 | `Mic` | `.m:136` |
| 9275 | `CD` | `.m:138` |
| 9278 | `Line` | `.m:140` |
| 9283 | `ES688` | `.m:170` |
| 9289 | `ES1688` | `.m:168` |
| 9296 | `ES1788` | `.m:172` |
| 9303 | `ES1888` | `.m:174` |
| 9310 | `ES1x88AudioDriver: Hardware not detected at port 0x%0x.\n` | `.m:176` |
| 9367 | `ES1x88AudioDriver: %s AudioDrive (version: %x) at port 0x%0x.\n` | `.m:180` |
| 9430 | `ES1x88AudioDriver: could not set transfer width to 8 bits, error %d.\n` | `.m:189` |
| 9500 | `%s: dma transfer mode error %d\n` | `.m:196` |
| 9532 | `%s: dma auto initialize error %d` | `.m:202` |
| 9565 | `%s: could not start DMA channel error %d\n` | `.m:1049` |
| 9607 | `%s: could not enable DMA channel error %d\n` | `.m:1056` |

`ES1x88AudioDriver.m` has no `#ifdef DEBUG` blocks at all and
`ES1x88AudioDriverInline.h` contains no string literals, so unlike drvSB8Sound there is no
guarded set to classify.

`_codecDeviceName` (8660, `"ES1x88AudioDriver"`) and `_codecDeviceKind` (8678, `"Audio"`)
are `local` in `__TEXT,__const`, matching `ES1x88AudioDriver.m:16`–`:17`'s
`static const char[]`. `-[ES1x88AudioDriver reset]` passes `offset _codecDeviceName` at
417 and `offset _codecDeviceKind` at 441 to `setName:` and `setDeviceKind:` in that order,
matching `:93`–`:94`. This follows drvSB8Sound, not drvBeepSound.

---

# `__DATA` and the two symbols the brief asked about

## `__DATA,__data` is 39 bytes and is all zeros

**Read directly, byte for byte.** The section is at address 16384, file offset 18780:

```
16384: 00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
16400: 00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
16416: 00 00 00 00  00 00 00
```

**drvSB8Sound's warning that this varies by driver does not bite here: ES1x88 matches
drvSB8Sound, not SoundBlaster16.** Every register pointer is computed at run time in
`+probe:` and every volume shadow is `= {0}` / `= 0` initialised, so the section content is
zero even though the symbols are in `__data` rather than `__bss`.

| Address | Symbol | Bytes | Our source | Written at run time by |
| --- | --- | --- | --- | --- |
| 16384 | `_sbBaseRegisterAddress` | 4 | `Inline.h:13` | `+probe:`+130 |
| 16388 | `_sbResetReg` | 4 | `:18` | `assignDSPRegAddresses()`, inlined at `+probe:`+177 |
| 16392 | `_sbReadDataReg` | 4 | `:19` | same, `+probe:`+192 |
| 16396 | `_sbWriteDataOrCommandReg` | 4 | `:20` | same, `+probe:`+206 |
| 16400 | `_sbWriteBufferStatusReg` | 4 | `:21` | same, `+probe:`+211 (shares `base+0Ch`) |
| 16404 | `_sbDataAvailableStatusReg` | 4 | `:22` | same, `+probe:`+225 |
| 16408 | `_sbMixerAddressReg` | 4 | `:49` | `assignMixerRegAddresses()`, `+probe:`+240 |
| 16412 | `_sbMixerDataReg` | 4 | `:50` | same, `+probe:`+255 |
| 16416 | `_volMaster` | 1 | `:65` | `initializeHardware`+699 |
| 16417 | `_volFM` | 1 | `:66` | `initializeHardware`+790 |
| 16418 | `_volLine` | 1 | `:68` | `initializeHardware`+958 |
| 16419 | `_volVoc` | 1 | — | `initializeHardware`+1049 |
| 16420 | `_volCD` | 1 | `:67` | `initializeHardware`+867 |
| 16421 | `_volMic` | 1 | `:69` | `initializeHardware`+1140 |
| 16422 | `_sbRecordSource` | 1 | `:88` | `initializeHardware`+1168, `reset`, `startDMAForChannel:`, `setAnalogInputSource:` |

## `_sbRecordSource` — confirmed, and our declaration is right

`_sbRecordSource` is `local` in `__DATA,__data` at 16422, the last byte of the section.
Our `ES1x88AudioDriverInline.h:88` declares:

```c
static unsigned char sbRecordSource =           0;
```

It is written as a **byte** at every one of its five assignment sites and read back with
`movzx`, confirming `unsigned char`:

| Site | Reference | Value | Our source |
| --- | --- | --- | --- |
| `initializeHardware`+1168 | `mov ds:_sbRecordSource, 7` | 7 | `.m:449` |
| `reset`+568/+585/+601/+612 | `mov ds:_sbRecordSource, 0/6/2/7` | 0, 6, 2, 7 | `.m:148`, `:151`, `:154`, `:157` |
| `startDMAForChannel:`+849/+865/+881/+892 | same four | 0, 6, 2, 7 | `.m:1094`, `:1098`, `:1102`, `:1104` |
| `setAnalogInputSource:`+14 | `mov ds:_sbRecordSource, 0` | 0 | `.m:1308` |
| `setAnalogInputSource:`+88 | `mov ds:_sbRecordSource, 6` | 6 | `.m:1304` |

**Nothing to change.** The one difference is how the value reaches the port, and that is
Finding 3.

## `_essHardware` — confirmed as a 4-byte value, but the symbol covers 8 bytes

`_essHardware` is `local` in `__DATA,__bss` at 16436. `__DATA,__bss` is 20 bytes at 16424,
so 16424 + 20 = 16444, which is where `__DATA,__common` starts; `_essHardware` is
therefore the last symbol in `__bss` and covers 16436–16443, eight bytes.

**The variable itself is four bytes**, and matches our `ES1x88AudioDriverInline.h:82`
`static unsigned int essHardware` on width and on every value:

```
 1401: C7053440000000000000  mov  ds:_essHardware, 0     ; 4-byte store, initializeHardware+5
 2031: C7053440000001000000  mov  ds:_essHardware, 1     ; on chipId1 == 'h'
  982: 8B0D34400000          mov  ecx, ds:_essHardware   ; reset+682, then cmp 2/1/3/4
```

`reset` tests it against 2, 1, 3 and 4 in that order, selecting `"ES1688"`, `"ES688"`,
`"ES1788"` and `"ES1888"`, exactly as `ES1x88AudioDriver.m:167`–`:178` does. Only the
value 1 is ever stored, so `ES688` is the only name the reference can report — that is a
property of Apple's binary, not of our source, and our source reproduces it.

**The remaining four bytes at 16440 are the chip revision, and they carry no symbol of
their own:**

```
 2025: 880538400000  mov   ds:byte_4038, al      ; 16440 <- chipId2 & 0x0F
 1102: 0FB61538400000 movzx edx, ds:byte_4038    ; reset+802, pushed as the %x argument
```

That is our `essChipRevision` (`ES1x88AudioDriverInline.h:83`), read at `reset` +802 and
pushed into `ES1x88AudioDriver: %s AudioDrive (version: %x) at port 0x%0x.\n` between
`hardwareName` and `sbBaseRegisterAddress`, matching `ES1x88AudioDriver.m:180`–`:181`.

**Inference, flagged as such:** every other `static` in this binary has its own `local`
nlist entry, including the three `_xxx.NN` compiler temporaries. A separate
`static unsigned char essChipRevision` would have one too. A single 8-byte symbol covering
both, with the byte at +4, is what a **struct** of `unsigned int` plus `unsigned char`
produces (4 + 1, padded to 8 at alignment 4). That is the most likely shape of Apple's
declaration, but it is not proved, and the *behaviour* of our two separate variables is
identical. **Task 8 should not restructure this on the strength of an inference.** The one
part that is proved is Finding 5's second half: both live in `__bss`, so neither carried an
initialiser.

`_xxx.86`, `_xxx.89` and `_xxx.92` at 16424, 16428 and 16432 are the three `static int xxx`
copies from `outb`/`outw`/`outl` in `src/kernel-7/machdep/i386/io_inline.h`, reached
through `ES1x88AudioDriver.h:11`'s `#import <driverkit/i386/ioPorts.h>`. Only `outb`'s is
referenced, and every `out dx, al` in the binary is followed by
`lock incl ds:_xxx.86`. Same mechanism as drvBeepSound and drvSB8Sound.

`_ES1x88AudioDriver_instance` is `external` in `__DATA,__common` at 16444, 4 bytes,
returned by the kernel-server glue at 8636.

## Positive result: both tables are byte-identical

Diffing `ES1x88AudioDriver.drvproj/Default.table` and
`ES1x88AudioDriver.drvproj/ESPnP.table` against Apple's shipped copies in
`ES1x88AudioDriver.config/` produces **no output at all** — not even the `"Driver Version"`
line, which Task 2 transcribed verbatim rather than regenerating. The shared procedure
predicted these two would be the only tables in the effort needing no change; that holds.
`"Help File" = "ES1x88_3_30.rtfd"` matches our bundle name and Apple's, so there is no
help-file finding here and `ES1x88_3_30.rtfd` must not be renamed.

---

# Findings

Fifteen. Every one is a real difference between our source and Apple's binary; none is a
Task 2 defect. Findings 1–3 and 6–15 name a concrete source change; Findings 4, 5 and 7
are structural and Task 8 should weigh them together.

## Finding 1: `reset` sends `stringValue` to the config-table value; the reference does not

**Source:** `ES1x88AudioDriver.m:132`

```c
inputSourceStr = [[configTable valueForStringKey:"Input Source"] stringValue];
```

The reference sends exactly three messages here and stops at `valueForStringKey:`:

```
 671: 682A240000   push offset "Input Source"
 676: A134600000   mov  eax, ds:paValueforstring     ; sel:valueForStringKey:
 682: 8B1530600000 mov  edx, ds:paConfigtable        ; sel:configTable
 689: A118600000   mov  eax, ds:paDevicedescript     ; sel:deviceDescription
 699: E840FDFFFF   call _objc_msgSend                ; [self deviceDescription]
 710: E835FDFFFF   call _objc_msgSend                ; [dd configTable]
 721: E82AFDFFFF   call _objc_msgSend                ; [ct valueForStringKey:"Input Source"]
 726: 89C3         mov  ebx, eax                     ; used directly as const char *
 731: 85DB         test ebx, ebx                     ; if (str == NULL)
```

`ebx` then goes straight into the three inlined `strcmp` blocks. **`stringValue` does not
appear in `__OBJC,__meth_var_names` at all**, so no code path in the reference sends it.
`valueForStringKey:` on `IOConfigTable` already returns `const char *`.

**Disposition for Task 8:** drop the `stringValue` send. Note also that the reference
re-sends `deviceDescription` here rather than reusing the local from `:87`, so the
original wrote `[[[self deviceDescription] configTable] valueForStringKey:"Input Source"]`.

## Finding 2: `reset` passes `IO_Demand`, not `IO_Single`, to `setTransferMode:forChannel:`

**Source:** `ES1x88AudioDriver.m:194`

```c
ioReturn = [self setTransferMode:IO_Single forChannel:0];
```

The reference pushes **0** for the mode:

```
1220: 6A00         push 0                        ; forChannel: 0
1222: 6A00         push 0                        ; mode
1224: 8B1544600000 mov  edx, ds:paSettransfermod ; sel:setTransferMode:forChannel:
1235: E828FBFFFF   call _objc_msgSend
```

`IODMATransferMode` in `src/driverkit-3/driverkit/i386/directDevice.h:58`–`:63` is
`IO_Demand = 0, IO_Single = 1, IO_Block = 2, IO_Cascade = 3`. The argument order was
confirmed against the adjacent `setAutoinitialize:YES forChannel:0` at 1280–1282, which
pushes `0` then `1` — the last-pushed value is the first argument.

**This is not a naming quibble; it is a different DMA mode.** ESS AudioDrive parts are
normally driven in demand mode. `setDMATransferWidth:` at 1173–1175 does push `0`
(`IO_8Bit`), matching our `:187`, and `setAutoinitialize:` pushes `1` (`YES`), matching
our `:200`.

**Disposition for Task 8:** change `IO_Single` to `IO_Demand` at `:194`.

## Finding 3: the mixer record-source byte is re-read from `_sbRecordSource`

**Source:** `ES1x88AudioDriver.m:85`, `:147`–`:163`, `:1005`, `:1093`–`:1109`

Our source keeps a parallel local:

```c
unsigned char recordSourceValue;
...
if (inputSource == 0) { sbRecordSource = 0; recordSourceValue = 0; }
...
outb(sbMixerDataReg, recordSourceValue);
```

The reference stores only the global and reads it back for the port write:

```
 912: C6052640000007  mov   ds:_sbRecordSource, 7
 919: 0FB61D26400000  movzx ebx, ds:_sbRecordSource     ; re-read
 926: ... out 1Ch ; IODelay(10) ; out bl ; IODelay(25)
```

The same shape appears in `startDMAForChannel:` at 6696/6703. A local held in a register
cannot produce the `movzx` from memory.

**Disposition for Task 8:** drop `recordSourceValue` and write `sbRecordSource` to the
port.

## Finding 4: the volume shadows are written as 4-bit bitfields, not as `rawValue`

**Source:** `ES1x88AudioDriver.m:411`, `:418`, `:425`, `:432`, `:439`

```c
volMaster.rawValue = 0xAA;
outb(sbMixerAddressReg, ES_MIXER_MASTER_VOLUME);
IODelay(10);
outb(sbMixerDataReg, 0xAA);
```

The reference performs two separate 4-bit field assignments and then reads the byte back:

```
2095: 8025204000000F  and   ds:_volMaster, 0Fh    ; volMaster.reg.left  = 0xA
2102: 800D20400000A0  or    ds:_volMaster, 0A0h
2109: 802520400000F0  and   ds:_volMaster, 0F0h   ; volMaster.reg.right = 0xA
2116: 800D204000000A  or    ds:_volMaster, 0Ah
2123: 0FB61D20400000  movzx ebx, ds:_volMaster    ; re-read, then out bl
```

The same four-instruction pattern with the same `0xA`/`0xA` pair appears for `_volCD`
(2263–2291), `_volLine` (2354–2382) and `_volVoc` (2445–2473); `_volFM` uses the
zero-valued form `and 0Fh / and 0F0h` (2186–2200), the compiler having dropped the two
`or 0` instructions. Our single-store `rawValue = 0xAA` plus a literal `0xAA` at the port
cannot produce any of this.

`_volMic` is the odd one: 2536–2557 emits `and 0Fh / or 0A0h` **twice**, and no port write
follows. Our `:446` `volMic = (volMic & 0x0F) | 0xA0;` produces the pair once. The reason
for the duplication is not established; it is recorded as an observation, not a
prescription.

**Disposition for Task 8:** express these as bitfield assignments through
`sb16MonoMixerRegister_t`'s `reg.left` / `reg.right` and write the shadow variable to the
port rather than a literal. The values are unchanged; only the construct differs.

## Finding 5: `volVoc` is a bitfield mixer register in the reference, a plain byte in ours

**Source:** `ES1x88AudioDriverInline.h:93`

```c
static unsigned char volVoc =                   0;
```

`_volVoc` at `__DATA,__data:16419` is manipulated exactly like `_volMaster`, `_volCD` and
`_volLine` — `and 0Fh / or 0A0h / and 0F0h / or 0Ah` in `initializeHardware` (2445–2473),
`and 0Fh / or al` in `updateOutputAttenuationLeft` (3758–3765), `and 0F0h / or al` in
`updateOutputAttenuationRight` (4126–4133). Those are the same instructions the other
three `sb16MonoMixerRegister_t` shadows get.

**Open question for Task 8, not a finding: can a single masked expression emit two
read-modify-write memory operations?** The attenuation and input-gain methods write each
shadow as `and ds:_volX, imm` followed by `or ds:_volX, reg` — two loads and two stores of
the same byte. Our source writes those sites as one expression each:
`volVoc = (volVoc & 0x0F) | volInUpperNibble;` at `:639` and the matching form at `:678`,
and the `.rawValue = (rawValue & mask) | …` form at `:512`–`:514`, `:543`–`:545`,
`:636`–`:638` and `:675`–`:677`. A single expression whose destination is a global byte
normally compiles to load / `and` / `or` / store through one register — one load, one
store. The paired read-modify-write form is characteristic of a **bitfield store**, where
the compiler uses the destination itself as the target of both the mask and the merge, or
of two separate compound assignments. On that reading Apple's construct here is
`volVoc.reg.left = volumeValue;`, not our expression.

**This could not be settled from the reference by Task 7**, which had no compiler: the
binary shows the emitted instructions only, and both constructs are candidate sources for
them. The earlier confident claim that our hand-written masks reproduce the reference was
therefore withdrawn as unproven in either direction.

**The question is now settled. See "Finding 5 settled: the masked expression does not
produce the paired form" below.** Task 8's brief carried an instruction to leave it open;
Task 8's own rebuild — this driver's first ever — superseded that instruction, because it
supplied exactly the evidence the question was waiting for, and the review pass that
followed acted on it. Recording the supersession here rather than obeying the stale
instruction is the correct disposition.

Two consequences for Task 8. First, **the question is not specific to `volVoc`**: the
identical construct produces the identical instructions for `_volLine`, `_volMic` and
`_volCD` in `updateInputGainLeft` (2687–2729) and `updateInputGainRight` (2919–2961), and
both of those functions are recorded `assembly-matched`. If Task 8 settles the question
against the expression form, it must reopen those two entries too; the answer cannot apply
to `volVoc` alone. Second, **this does not unsettle Finding 4**, which rests on separate
evidence: `initializeHardware` emits *four* read-modify-write operations per shadow where
our single `rawValue = 0xAA` store would emit one `mov` of an immediate, and `_volFM`'s
`and 0Fh / and 0F0h` pair (2186–2193) shows two source-level assignments with the `or 0`
folded away.

Related: `_volVoc` sits at 16419, **between** `_volLine` (16418) and `_volCD` (16420),
whereas our header declares `volMaster, volFM, volCD, volLine, volMic` at `:65`–`:69` and
`volVoc` far below at `:93`. The reference's declaration order is
`volMaster, volFM, volLine, volVoc, volCD, volMic, sbRecordSource`.

**Disposition for Task 8:** low priority, and behaviourally neutral. If the declarations
are reordered, reorder all seven together; a partial reorder makes the layout worse, not
better.

## Finding 6: our source declares data the reference does not have

**Source:** `ES1x88AudioDriverInline.h:23`–`:24`, `:74`–`:77`, `:98`–`:100`;
`ES1x88AudioDriver.m:19`

The reference's `__DATA,__data` holds exactly fifteen symbols (table above) and its
`__DATA,__bss` exactly four. Our source declares nine more that have no counterpart:

| Ours | Where | Why it has no counterpart |
| --- | --- | --- |
| `sbAck8bitInterrupt` | `Inline.h:23` | `assignDSPRegAddresses()` in the reference writes five registers, not seven — `+probe:` 168–225 |
| `sbAck16bitInterrupt` | `Inline.h:24` | same; `SB16_DSP_16BIT_ACK_OFFSET` is never used |
| `lastStageGainInputLeft` | `Inline.h:74` | only `initializeLastStageGainRegisters` touches it |
| `lastStageGainInputRight` | `Inline.h:75` | same |
| `lastStageGainOutputLeft` | `Inline.h:76` | same |
| `lastStageGainOutputRight` | `Inline.h:77` | same |
| `sbBufferCounter` | `Inline.h:98` | only `setBufferCount:` touches it |
| `sbStartDMACommand` | `Inline.h:99` | touched by nothing at all, even in our tree |
| `sbStartDMAMode` | `Inline.h:100` | only `updateSampleRate` touches it |
| `sb16CardType` | `.m:19` | no `_sb16CardType` symbol; ES1x88 uses `_essHardware` instead |

`sb16CardType` deserves a separate note. `sb16CardParameters_t`
(`ES1x88AudioDriverRegisters.h:215`–`:223`) is SoundBlaster16's card-parameter struct and
nothing in our own `.m` reads or writes `sb16CardType`. Its `sb16CardVersion_t` enum is
likewise unused. **Do not carry drvSB8Sound's `_sbCardType` layout across; there is no
such symbol here.**

**Disposition for Task 8:** the seven variables tied to the four excised methods become
dead when those methods go and should go with them. `sbAck8bitInterrupt` and
`sbAck16bitInterrupt` require editing `assignDSPRegAddresses()` at
`ES1x88AudioDriverInline.h:40`–`:43`. `sb16CardType` and its two types are pre-existing
dead code; mention rather than remove unless Task 8's brief says otherwise.

## Finding 7: our class declares eight instance variables; the reference has four

**Source:** `ES1x88AudioDriver.h:14`–`:24`

`__OBJC,__instance_vars` is 52 bytes at 26712: a count word of 4 followed by four 12-byte
entries. Read in full:

| Name | Encoding | Offset |
| --- | --- | --- |
| `currentDMADirection` | `I` | 388 (`0x184`) |
| `interruptTimedOut` | `c` | 392 (`0x188`) |
| `hardwareName` | `*` | 396 (`0x18C`) |
| `inputSource` | `C` | 400 (`0x190`) |

Our interface declares those four plus `is16BitTransfer`, `dma8Channel`, `dma16Channel`
and `numDMAChannels`, in an order that puts the extras *between* `interruptTimedOut` and
`hardwareName`. Our `hardwareName` would land at 408 and our `inputSource` at 412, not 396
and 400.

The reference's offsets are confirmed at every use site: `[esi+184h]` in
`interruptOccurredForInput:forOutput:` (7946), `configureHardwareForDataTransfer:` (4529,
5196) and `startDMAForChannel:` (5835, 5848); `[esi+188h]` in `startDMAForChannel:` (5824)
and `timeoutOccurred` (8008, 8344); `[edx+18Ch]` in `reset` (1019, 1035, 1051, 1067, 1113);
`[eax+190h]` in `reset` (738, 770, 802, 834, 847, 857) and `startDMAForChannel:` (6642,
6766, 7116).

The four extras are exactly the ivars the excised methods use: `is16BitTransfer` by
`updateSampleRate` (`.m:784`), and `dma8Channel`, `dma16Channel` and `numDMAChannels` by
`initializeDMAChannels` (`.m:227`–`:315`).

**Disposition for Task 8:** removing the four methods makes all four ivars dead; removing
the ivars restores the reference's offsets. Do both, or neither — leaving the ivars in
place keeps every `hardwareName` and `inputSource` access at the wrong offset.

## Finding 8: the two DSP wait helpers' return values are discarded in the reference

**Source:** `ES1x88AudioDriver.m:361`–`:363`, `:375`–`:377`, `:381`–`:383`, `:388`–`:390`,
`:1026`–`:1029`, `:1036`–`:1038`, `:1267`–`:1271`, `:1278`–`:1280`

Our source guards on both helpers:

```c
if (!waitForDSPDataAvailable()) {
    return;
}
dspVersion = inb(sbReadDataReg);
```

The reference has no such arm. In `initializeHardware`, the success branch and the timeout
branch converge on the same next instruction:

```
1486: 84C0  test al, al
1488: 7C50  jl   loc_622        ; 0x622 = 1570, the inb below
1490: 43    inc  ebx
1491: 81FBCF070000 cmp ebx, 7CFh
1497: 7EE1  jle  loc_5BC        ; loop
1499: ...                       ; timeout: reset pulse, IODelay(100), out 0C6h
1563: F0FF0528400000 inc ds:_xxx_86    ; last instruction of the timeout arm
1570: 668B1508400000 mov dx, word ptr ds:_sbReadDataReg   ; <- both arms arrive here
```

The identical convergence occurs at 1636→1718, 1760→1842 and 1892→1974 in
`initializeHardware`, at 5936→6018 and 6088→6170 in `startDMAForChannel:`, and at
8100→8172 and 8248→8317 in `timeoutOccurred`. In every case the timeout arm's own
recovery — reset pulse, `IODelay(100)`, `outb(sbWriteDataOrCommandReg, 0xC6)` — runs and
execution continues as if the wait had succeeded. On the timeout path in
`startDMAForChannel:` this makes `0xC6` go out twice, once from the recovery and once from
the main path at 6177.

Our `startDMAForChannel:` and `timeoutOccurred` additionally log
`ES1x88AudioDriver: Can not reset DSP.\n` and return early on timeout. In the reference
that string is reached **only** from the `dspVersion != 0xAA` test (6045→6047,
8209→8211), which our `:1039`–`:1041` and `:1281`–`:1283` else-branches also do.

**Disposition for Task 8:** call both helpers for effect and drop the guards, in
`initializeHardware`, `startDMAForChannel:` and `timeoutOccurred`. Our `:1036`
`if (waitForDSPWriteReady()) { outb(...); }` becomes an unconditional pair.

## Finding 9: `+probe:` compares `numChannels` unsigned; our local is `int`

**Source:** `ES1x88AudioDriver.m:36`, `:48`

```c
int             numChannels;
...
if ((numPortRanges < 1) || ((numChannels - 1) > 1))
    return NO;
```

```
 90: 85DB   test ebx, ebx        ; numPortRanges
 92: 7E46   jle  loc_A4          ; signed:   numPortRanges < 1
 94: 48     dec  eax             ; numChannels - 1
 95: 83F801 cmp  eax, 1
 98: 7740   ja   loc_A4          ; unsigned: (numChannels - 1) > 1
```

`numPortRanges` is compared signed (`jle`) and `numChannels` unsigned (`ja`). A signed
`int numChannels` produces `jg`, not `ja`. `[deviceDescription numChannels]` returns
`unsigned int`.

**Disposition for Task 8:** declare `numChannels` as `unsigned int` at `:36`. Leave
`numPortRanges` as `int`.

## Finding 10: `updateOutputMute` computes and stores a negated flag

**Source:** `ES1x88AudioDriver.m:559`–`:617`

```
3117: E8CEF3FFFF   call _objc_msgSend      ; [self isOutputMuted]
3122: 88C2         mov  dl, al
3127: 84D2         test dl, dl
3129: 0F94C0       setz al                 ; al = !isOutputMuted
3132: 8845FC       mov  [ebp+var_4], al    ; stored in a local
3135: 84C0         test al, al
3137: 0F84F1000000 jz   loc_D38            ; muted -> the zero-writing branch
```

and the speaker command is a separate immediate in each branch — `mov al, 0D1h` at 3613 on
the restore path, `mov al, 0D3h` at 3627 on the mute path — not one `out` fed by a
variable. Our `BOOL isMuted = [self isOutputMuted]; if (isMuted) {...} else {...}` followed
by a single trailing `outb(sbWriteDataOrCommandReg, speakerCommand)` produces neither the
`setz`/store nor the duplicated tail.

This is the shape drvSB8Sound recorded as `enableAudioOutput(![self isOutputMuted])` — a
helper taking a `BOOL`, inlined, with the DSP command inside each arm. **Behaviour is
identical either way**; only the emitted instructions differ.

**Disposition for Task 8:** restructure as a negated flag with the command inside each
branch, or accept the divergence explicitly. Do not claim `assembly-matched` without
making the change.

## Finding 11: three inverted predicates in `configureHardwareForDataTransfer:`

**Source:** `ES1x88AudioDriver.m:828`–`:832`, `:846`–`:850`, `:905`, `:915`

This is the most consequential code finding in the driver: all three flip a run-time
decision, so the reference and our source program the chip differently for the *same*
input.

**(a) The Audio Control 2 mode value.** Reference: input selects `0Eh`, output selects
`04h`.

```
4529: 8BB784010000 mov  esi, [edi+184h]   ; currentDMADirection
4538: 85F6         test esi, esi
4540: 7526         jnz  loc_11E4          ; -> 4580, the OUT arm
4542: ... out B8h ; IODelay(25)
4576: B00E         mov  al, 0Eh           ; IN  -> 0Eh
4578: EB24         jmp  loc_1208
4580: ... out B8h ; IODelay(25)
4614: B004         mov  al, 4             ; OUT -> 04h
4616: EE           out  dx, al
```

Ours has `ES_MODE_INPUT 0x04` on the `DMA_DIRECTION_IN` arm and `ES_MODE_OUTPUT 0x0E` on
the other. On the ES-1688, register `B8h` bit 1 selects DMA direction, so `0Eh` is the
record setting and `04h` the playback setting; the reference is right and the two
`#define` names in `ES1x88AudioDriverRegisters.h:115`–`:116` are attached to the wrong
directions.

**(b) The Audio Mode channel-clear mask.** Reference: input clears three bits, output
clears two.

```
4720: 85F6         test esi, esi
4722: 7508         jnz  loc_127C          ; -> 4732
4724: 81E3F8000000 and  ebx, 0F8h         ; IN  -> clear lower 3
4730: EB06         jmp  loc_1282
4732: 81E3FC000000 and  ebx, 0FCh         ; OUT -> clear lower 2
```

Ours has `0xFC` on the `DMA_DIRECTION_IN` arm and `0xF8` on the other.

**(c) The mode-command group is selected on `Linear8`, not `Linear16`.** Both selection
sites test `259h`:

```
5202: 837DF800     cmp  [ebp+var_8], 0    ; var_8 = (channelCount == 2)
5206: 752C         jnz  loc_1484          ; -> 5252, stereo
5208: 817DF459020000 cmp [ebp+var_C], 259h ; mono: dataEncoding == 601 = Linear8
5215: 7513         jnz  loc_1474
5217: BB80000000   mov  ebx, 80h          ; modeData
5222: BE51000000   mov  esi, 51h          ; cmd1
5227: BFD0000000   mov  edi, 0D0h         ; cmd2  (mono, first group)
5236: 31DB         xor  ebx, ebx          ; else: modeData 0
5238: BE71000000   mov  esi, 71h
5243: BFF4000000   mov  edi, 0F4h         ; cmd2  (mono, second group)
5252: 817DF459020000 cmp [ebp+var_C], 259h ; stereo: same constant
5261: BB80000000   mov  ebx, 80h
5266: BE51000000   mov  esi, 51h
5271: BF98000000   mov  edi, 98h          ; cmd2  (stereo, first group)
5280: 31DB         xor  ebx, ebx
5282: BE71000000   mov  esi, 71h
5287: BFBC000000   mov  edi, 0BCh         ; cmd2  (stereo, second group)
```

`NX_SoundStreamDataEncoding_Linear16 = 600 = 0x258` and `Linear8 = 601 = 0x259`
(`src/driverkit-3/driverkit/NXSoundParameterTags.h:73`–`:74`). **The reference selects the
`80h`/`51h` group when the encoding is `Linear8`; our `:905` and `:915` select it when the
encoding is `Linear16`.** All eight constants themselves match ours exactly
(`ES_OUTPUT_MODE_16BIT 0x80`, `ES_OUTPUT_MODE_8BIT 0x00`, `0x51`/`0xD0`, `0x71`/`0xF4`,
`0x51`/`0x98`, `0x71`/`0xBC`); only the predicate differs. It pairs with Finding 14, which
also has our encoding order reversed.

Everything else in this function matches: the `A8h` read-modify-write with `01h` for
stereo and `02h` for mono (`:853`–`:857`), the `B9h`←`02h` DMA setup (`:866`–`:868`), the
sample-rate and filter arithmetic quoted earlier, the negated transfer count into `A4h`
and `A5h` (`:889`–`:900`), the `B6h` write gated on direction, the two `B7h` writes, and
the IRQ (`B1h`, `00h`/`04h`/`08h`/`0Ch` `| 50h`) and DMA (`B2h`, `04h`/`08h`/`0Ch`
`| 50h`) tables.

Two smaller construct notes on the same function, not separate findings. The reference
gates the `B6h` write on `cmp edx, 1` (5292) where our `:927` writes
`!= DMA_DIRECTION_IN`; and it builds the IRQ and DMA bytes with paired `or`/`and`
bit operations (5490–5525, 5600–5638) rather than whole-value assignments, which is the
bitfield idiom again.

**Disposition for Task 8:** swap (a) and (b), and change the encoding test in (c) to
`NX_SoundStreamDataEncoding_Linear8`. If the `ES_MODE_INPUT`/`ES_MODE_OUTPUT` names are
corrected in the header instead of the call site, correct both call sites consistently.

## Finding 12: the DSP identity compare in our source can never be true

**Source:** `ES1x88AudioDriver.m:1004` and `:1035`; `:1257` and `:1277`

```c
unsigned char dspVersion;
...
if (dspVersion == (char)ES_DSP_READY_RESPONSE) {
```

`ES_DSP_READY_RESPONSE` is `0xAA`. `(char)0xAA` is `-86` where `char` is signed.
`dspVersion` is `unsigned char`, so it promotes to an `int` in `0..255` and can never
equal `-86`. **The `if` is dead in both `startDMAForChannel:` and `timeoutOccurred`**, and
both take the else-branch unconditionally, logging `Can not reset DSP.` on every start and
every timeout and never sending the `0xC6` extended-ID command.

The reference compares the byte zero-extended:

```
6026: 0FB6D8       movzx ebx, al
6039: 81FBAA000000 cmp   ebx, 0AAh
6045: 7411         jz    loc_17B0
```

identically at 8190/8203 in `timeoutOccurred` and at 1578/1591 in `initializeHardware`.

`initializeHardware` is a different case: our `:348` declares `char dspVersion`, so
`(char)0xAA == (char)0xAA` is true and the comparison works — but a signed `char` compare
emits `movsx`/`cmp -86`, not the reference's `movzx`/`cmp 0AAh`, so it still diverges at
instruction level.

**Disposition for Task 8:** drop the `(char)` cast at `:1035`, `:1277` and `:370`, and
make `dspVersion` `unsigned char` at `:348`. This is a behaviour fix in two of the three
sites, not a cosmetic one.

## Finding 13: `setAnalogInputSource:` tests the microphone tag first

**Source:** `ES1x88AudioDriver.m:1294`–`:1317`

```
8366: 81FAC8000000 cmp edx, 0C8h      ; NX_SoundDeviceAnalogInputSource_Microphone
8372: 7542         jnz loc_20F8       ; -> 8440
8374: C6052640000000 mov ds:_sbRecordSource, 0
...
8440: 81FAC9000000 cmp edx, 0C9h      ; NX_SoundDeviceAnalogInputSource_LineIn
8446: 75B6         jnz loc_20B6       ; -> 8374, the microphone path
8448: C6052640000006 mov ds:_sbRecordSource, 6
```

Two compares, in the order `0C8h` then `0C9h`, with the default branching back into the
microphone arm — the same "default shares the microphone path" shape drvSB8Sound recorded.
Our source tests `val == NX_SoundStreamDataAnalogSourceLineIn` only, and emits one compare.
Behaviour is identical; the instructions are not.

The two `#define`s at `ES1x88AudioDriverRegisters.h:233`–`:234` carry the right values
(`0xC8`, `0xC9`) under non-standard names; the real enumerators are in
`src/driverkit-3/driverkit/NXSoundParameterTags.h:57`–`:59`.

**Disposition for Task 8:** rewrite as an explicit two-test chain with a default that
shares the microphone arm.

**Keep the `sourceValue` local at `:1296`.** It has the shape of the parallel local
Finding 3 tells Task 8 to remove, but the reference does *not* re-read `_sbRecordSource`
here. The whole binary contains exactly two `movzx ebx, ds:_sbRecordSource` instructions —
`reset`+619 (919) and `startDMAForChannel:`+899 (6703), the two sites Finding 3 names.
`setAnalogInputSource:` keeps the port byte in a register instead:

```
8374: C6052640000000 mov  ds:_sbRecordSource, 0
8408: 668B151C400000 mov  dx, word ptr ds:_sbMixerDataReg
8415: 30C9           xor  cl, cl              ; the value written to the port
8417: 88C8           mov  al, cl
8419: EE             out  dx, al
...
8448: C6052640000006 mov  ds:_sbRecordSource, 6
8489: B106           mov  cl, 6
8491: EBB4           jmp  loc_20E1            ; -> 8417, the shared tail
```

That is exactly our `:1304`/`:1308` global store plus the `:1305`/`:1309` `sourceValue`
assignment plus `:1315` `outb(sbMixerDataReg, sourceValue)`. **Finding 3 must not be
applied to this method**; removing `sourceValue` here would introduce a divergence rather
than remove one.

## Finding 14: `getDataEncodings:count:` returns the two encodings in the wrong order

**Source:** `ES1x88AudioDriver.m:1349`–`:1350`

```c
encodings[0] = NX_SoundStreamDataEncoding_Linear16;   /* 600 */
encodings[1] = NX_SoundStreamDataEncoding_Linear8;    /* 601 */
```

The reference, read in full:

```
8595: 8B4510       mov   eax, [ebp+arg_8]
8598: 8B5514       mov   edx, [ebp+arg_C]
8601: C70059020000 mov   dword ptr [eax], 259h      ; 601 = Linear8
8607: C7400458020000 mov dword ptr [eax+4], 258h    ; 600 = Linear16
8614: C70202000000 mov   dword ptr [edx], 2
```

`*count = 2` matches; the order is reversed. `IOAudio` treats `encodings[0]` as the
preferred encoding, so this is a behavioural difference, and it is consistent with
Finding 11(c), where the reference also keys its mode selection on `Linear8`.

**Disposition for Task 8:** swap the two assignments.

## Finding 15: the attenuation division is unsigned; our `attenuation` locals are `int`

**Source:** `ES1x88AudioDriver.m:625` and `:665`

```c
int             attenuation;
...
volumeValue = (unsigned char)(((attenuation * ES_ATTENUATION_MULTIPLIER
                                + ES_ATTENUATION_OFFSET)
                               * ES_ATTENUATION_SCALE) / ES_ATTENUATION_RANGE);
```

The reference divides **unsigned** in both methods. `updateOutputAttenuationLeft`:

```
3674: 89C2           mov  edx, eax                ; [self outputAttenuationLeft]
3676: 8D9452FC000000 lea  edx, [edx+edx*2+0FCh]   ; attenuation*3 + 252
3686: 8D1492         lea  edx, [edx+edx*4]        ; *5
3689: 89D0           mov  eax, edx
3691: B954000000     mov  ecx, 54h                ; 84
3696: 31D2           xor  edx, edx                ; zero-extend, not sign-extend
3698: F7F1           div  ecx                     ; unsigned divide
```

and the identical shape in `updateOutputAttenuationRight`:

```
4059: B954000000     mov  ecx, 54h
4064: 31D2           xor  edx, edx
4066: F7F1           div  ecx
```

`xor edx, edx` followed by `div` is reachable only from unsigned operands. A signed `int`
division by a non-power-of-two constant emits `cltd; idiv ecx`, and the compiler cannot
substitute `div` for `idiv` without knowing the dividend is non-negative — there is no
such range information here, since `[self outputAttenuationLeft]` is an opaque
`objc_msgSend` return. The four constants themselves match ours exactly
(`ES_ATTENUATION_MULTIPLIER` 3, `ES_ATTENUATION_OFFSET` 252, `ES_ATTENUATION_SCALE` 5,
`ES_ATTENUATION_RANGE` 84, `ES1x88AudioDriverRegisters.h:163`–`:166`); only the signedness
of the arithmetic differs.

**Behaviour is identical.** The attenuation range is 0 to -84, which `*3 + 252` maps to
0..1260 and `*5` to 0..6300 — all non-negative, so signed and unsigned division agree on
every value that can occur. That is exactly the case the binding rule covers: a source
construct that cannot produce the reference's instructions is a divergence even when the
behaviour matches. It is the same signal Finding 9 turns on for `numChannels` (`ja` versus
`jg`), and the same signal that makes `updateInputGain*`'s `shr ecx, 0Fh` at 2673 and 2905
evidence for their `unsigned int gain`.

**Disposition for Task 8:** declare `attenuation` as `unsigned int` at `:625` and `:665`.
Note that this is the only reason both entries are held `unexamined`; the open question in
Finding 5 about the `_volVoc` masks is recorded there and is not a finding.

**Correction after the rebuild.** This disposition claimed "both `lea`s and the `54h`
divisor already match". Only the divisor did. The `54h` divisor and the `xor edx, edx /
div ecx` pair match after the signedness fix, but the `lea` pair does not: the reference
folds the `0FCh` offset into the first address computation, `lea edx, [edx+edx*2+0FCh]`
then `lea edx, [edx+edx*4]`, while our gcc distributes it into the second,
`lea edx, [edx+edx*2]` then `lea edx, [edx+edx*4+4ECh]`. The values agree; the
instructions do not. See "One negative result worth recording" below for the two source
forms that were built against this.

---

# Task 8 fix-pass resolutions

Every finding above resolved one of two ways: the source changed to match the reference, or
the ledger entry became `intentional-mismatch` with a reason and a reviewer. Nothing is
left undecided.

## The baseline this driver had never had

`drvES1x88Sound` had never been compiled. The first build failed on two pre-existing
errors, repaired in their own commit before any divergence work:

- `sb16MonoMixerRegister_t` named its byte member `data` while all 33 use sites in
  `ES1x88AudioDriver.m` said `.rawValue`.
- `IO_16Bit` is not an `IODMATransferWidth` enumerator; the type is
  `IO_8Bit`/`IO_16BitWordCount`/`IO_16BitByteCount`
  (`src/driverkit-3/driverkit/i386/directDevice.h:164`). The one use was inside
  `initializeDMAChannels`, which this pass then removed. `drvSB16Sound.m:270` carries the
  same error and is Task 10's to repair.

## Gate results

| Gate | Baseline | After fix pass | After review pass | After selector-reference pass |
| --- | --- | --- | --- | --- |
| guest build | `EXIT=0`, `fail=0` (after the repair commit) | `EXIT=0`, `fail=0` | `EXIT=0`, `fail=0` | `EXIT=0`, `fail=0` |
| `missing_strings` | 0 | 0 | 0 | 0 |
| `missing_symbols` | 0 | 0 | 0 | 0 |
| `extra_strings` | 12 | **0** | 0 | 0 |
| `extra_symbols` | 38 | 30 | 30 | 30 |
| staged `_reloc` | 190328 bytes | 179264 bytes | 179244 bytes | 179156 bytes |
| source-map buckets | 23 / 2 / 0 / 0 = 25 | 23 / 2 / 0 / 0 = 25 | 23 / 2 / 0 / 0 = 25 | 23 / 2 / 0 / 0 = 25 |
| `load_source_map` | not run | `source map OK` | `source map OK` | `source map OK` |
| `binrecon ledger` | not run | accepted, `entries=25` | accepted, `entries=25` | accepted, `entries=25` |

The "After review pass" `_reloc` figure was recorded as 179332; the artifact that pass
staged is 179244 bytes. That was a transcription slip in this table alone — the `__text`
figure and every per-function size in this document match the artifact exactly — and it is
corrected above.

All 30 remaining `extra_symbols` are stabs from our unstripped build: `''`, the two source
filenames, the `ioPorts.h` and `ES1x88AudioDriver_instance.m` paths, and the `:fNN` N_FUN
entries. No entry moved from `mapped` to `unmapped`.

The 12 strings that were extra are exactly the ten this report predicted plus `Audio` and
`ES1x88AudioDriver`; see Finding 16.

## Per-function sizes, gap-to-next-symbol

Ours is unstripped and its stabs share addresses inside `__TEXT,__text`, which collapses
every computed size to zero; the helper filters them, which is a no-op on the reference.
25 functions on both sides, none missing, none extra, none flagged `LARGER`.

Exact matches after the review pass: `+probe:` 300, `timeoutOccurred` 360,
`getDataEncodings:count:` 32, `interruptOccurredForInput:forOutput:` 48,
`getSamplingRates:count:` 56, `getSamplingRatesLow:high:` 28, `enableAllInterrupts` 44,
`disableAllInterrupts` 44, `channelCountLimit` 12, `acceptsContinuousSamplingRates` 12,
`interruptClearFunc` 12 and both glue methods 12.

The two attenuation methods were 368 against 368 after the first fix pass and are 356
against 368 after the review pass. **That earlier equality was a coincidence and was the
whole of the evidence the first pass offered for `assembly-matched` on both entries** — 95
reference instructions against 100 built. Size alone is the weakest signal available here
and is not, on its own, grounds for that status.

**A systemic code-generation difference accounts for the remainder**, and it is not a
source divergence. Our gcc omits the `movzx` zero-extension the reference emits before
`out dx, al`, and it tail-merges further. `reset` has 1 `movzx` where the reference has 3;
`startDMAForChannel:` has 0 where the reference has 10. The same shortfall appears in
`updateInputGainLeft`, `updateInputGainRight` and `stopDMAForChannel:`, which this report
pass already recorded `assembly-matched` on instruction-level reading, so it cannot be
evidence of a source difference.

## Finding by finding

| # | Resolution |
| --- | --- |
| 1 | Source. `reset` sends `[[[self deviceDescription] configTable] valueForStringKey:"Input Source"]`; the `stringValue` send and the `configTable` local are gone. |
| 2 | Source. `IO_Single` became `IO_Demand` at the `setTransferMode:forChannel:` call. |
| 3 | Source. `recordSourceValue` dropped from `reset` and `startDMAForChannel:`; both write `sbRecordSource` to the port. **Not applied to `setAnalogInputSource:`**, per Finding 13. |
| 4 | Source. The six volume shadows are written as `reg.left` then `reg.right` and read back for the port write. One residual, see below. |
| 5 | Source. The seven `__DATA,__data` declarations were reordered to `volMaster, volFM, volLine, volVoc, volCD, volMic, sbRecordSource`, and `volVoc` was retyped to `sb16MonoMixerRegister_t`, which Finding 4 required at its `initializeHardware` site. `essHardware` and `essChipRevision` lost their `= 0` initialisers, the part this report called proved. The expression-versus-bitfield question was left open by the first fix pass and **settled by the review pass**, against the expression form; `volMic` was retyped and every remaining masked expression became a bitfield store. See the section below. |
| 6 | Source. `sbAck8bitInterrupt`, `sbAck16bitInterrupt`, the four `lastStageGain*`, `sbBufferCounter` and `sbStartDMAMode` removed, with the two `assignDSPRegAddresses()` assignments. `sbStartDMACommand` and `sb16CardType` were dead **before** this pass and were left; see "Pre-existing dead code". |
| 7 | Source. `is16BitTransfer`, `dma8Channel`, `dma16Channel` and `numDMAChannels` removed, restoring `hardwareName` to 396 and `inputSource` to 400. |
| 8 | Source. Both DSP wait helpers are called for effect in `initializeHardware`, `startDMAForChannel:` and `timeoutOccurred`; no early return, no `IOLog` on their failure. |
| 9 | Source. `numChannels` is `unsigned int` in `+probe:`. |
| 10 | Source, in two steps. The first pass put `D1h`/`D3h` inside their branches, which the rebuild confirms; it did **not** produce the stored negated flag, because with one use of `enableOutput` our gcc folded the `!` into a reversed branch. The review pass made the speaker write a second `if (enableOutput)`, and the rebuild then emits `sete`. See below. |
| 11 | Source. `ES_MODE_INPUT` is `0x0E` and `ES_MODE_OUTPUT` is `0x04`; the `0xF8`/`0xFC` masks are swapped; the mode-command group keys on `Linear8`. Verified in the rebuilt disassembly: `mov al, 0xe` on the IN arm, `mov al, 4` on the other, matching 4576 and 4614. |
| 12 | Source. The `(char)` cast dropped at all three sites and `initializeHardware`'s `dspVersion` is `unsigned char`. |
| 13 | Source. Two tests, `0C8h` then `0C9h`, default sharing the microphone arm. **`sourceValue` kept.** Entry `8360` is `intentional-mismatch`, not `assembly-matched`: the join point and the register allocation still differ, see below. |
| 14 | Source. `encodings[0]` is `Linear8`, `encodings[1]` is `Linear16`. |
| 15 | Source, in part. `attenuation` is `unsigned int` at both sites, which fixes the division. The `lea` pair is **not** fixed and holds both entries at `intentional-mismatch`. |
| 16 | Source. New; see below. |

## Finding 16: `reset` passed string literals where the reference passes the statics

This report stated under "Positive result" that `reset` passing `offset _codecDeviceName`
and `offset _codecDeviceKind` matches `:93`-`:94`. It did not: `:93`-`:94` passed the
literals `"ES1x88AudioDriver"` and `"Audio"`, which our build emitted into `__cstring`
while `codecDeviceName` and `codecDeviceKind` sat unreferenced in `__TEXT,__const`. They
were the two `extra_strings` this report did not predict.

`reset` now passes `codecDeviceName` and `codecDeviceKind`. That removed both extras and is
what closed `extra_strings` to zero.

## The entries held as `intentional-mismatch`

**`initializeHardware` (1396).** Findings 4 and 8 are resolved in source. The reference
emits the `and 0Fh` / `or 0A0h` pair for `_volMic` **twice** at 2536-2557 with no port write
following; our `volMic.reg.left = 0xA` emits it once. This report recorded the duplication
as an unexplained observation rather than a prescription, and no source construct that
produces it can be derived from the binary. Writing the statement twice would be inventing
structure, so the divergence is accepted.

The first fix pass wrote that our `volMic = (volMic & 0x0F) | 0xA0` "produces the pair
once". It did not produce the pair at all — it produced the register form
`mov al, [0x4025] / and al, 0Fh / or al, 0A0h / mov [0x4025], al`. The review pass retyped
`volMic` to `sb16MonoMixerRegister_t` and the bitfield store now emits the pair. **Only the
duplication is underivable; the instruction form is not.**

**`configureHardwareForDataTransfer:` (4388).** Finding 11 is resolved in source and
verified in the rebuilt disassembly, and the `B6h` write is now gated on
`== DMA_DIRECTION_OUT` so it emits `cmp 1` as the reference does at 5292. Two construct
differences remain: the reference caches `(channelCount == 2)` as a boolean in a stack slot
at 4500-4511, and it builds the IRQ and DMA control bytes with paired bit operations on a
local byte at 5490-5525 and 5600-5638 rather than whole-value assignments.

The first fix pass wrote that reproducing either "needs Apple's declarations, not the
binary". **That is withdrawn**: the review pass's rebuild reproduces the paired form for
the mixer shadows from bitfield members alone, so the construct is derivable in general.
What blocks it here is narrower. Unlike the mixer shadows, whose two 4-bit halves the
`0Fh`/`0F0h` masks pin down exactly, the binary does not determine the field decomposition
of these two control bytes: `or dl, 50h` at 5525 sets two bits in one instruction, and a
single two-bit field cannot be told apart from two one-bit fields. The type would be
invented rather than derived, so it was not written.

**`updateOutputAttenuationLeft` (3652) and `updateOutputAttenuationRight` (4020).** Held
for the `lea` reassociation; see the Finding 15 correction above and the negative result
below.

**`setAnalogInputSource:` (8360).** Held for the join point and the `ebx` allocation; see
the negative result below.

## Negative results worth recording

**`setAnalogInputSource:`.** Finding 13's remaining 32-byte gap is not reachable from
source. The reference programs the mixer inside each arm and joins only at `mov al, cl`
(8417); our build hoists the port sequence into a shared tail and joins at its head.
Writing the whole port sequence out in all three arms was built and the rebuilt function
came out **byte-identical** — our gcc cross-jumps it straight back. The simpler shared-tail
form was therefore kept. Our gcc also allocates `sourceValue` to `bl`, paying a prologue
`push ebx` and an epilogue `mov ebx, [ebp-4]` that the reference, using `cl`, does not.

The first fix pass advanced this entry to `assembly-matched` on the strength of the
negative experiment alone. A 104-against-136 size gap and a different join point do not
support that status, and the review pass downgraded it to `intentional-mismatch`.

**The attenuation `lea` pair.** Two source forms were built against the reassociation, both
on the guest, neither of which reproduced the reference's fold:

- a named `unsigned int scaledAttenuation = attenuation * 3 + 252;` with
  `(scaledAttenuation * 5) / 84` as the next statement — emitted the identical
  `lea edx, [edx+edx*2]` / `lea edx, [edx+edx*4+4ECh]` as the single expression;
- a further split putting `scaledAttenuation = scaledAttenuation * 5;` in its own statement
  — still folded, and **worse**, because it also dropped the `mov dword ptr [ebp-4], edx`
  spill store that both the reference and the single-expression form emit.

The single-expression form was therefore kept, and the divergence is accepted as a
code-generation difference between our gcc and Apple's. Unlike the `movzx` shortfall it has
not been shown to be systemic, so it is recorded as a divergence rather than as noise, and
both entries are `intentional-mismatch` rather than `assembly-matched`.

## Pre-existing dead code, left in place and reported

None of these was orphaned by this pass; all were already unreferenced before it.

- `sb16CardType` (`ES1x88AudioDriver.m:19`) with its `sb16CardParameters_t` and
  `sb16CardVersion_t` types (`ES1x88AudioDriverRegisters.h`).
- `sbStartDMACommand` (`ES1x88AudioDriverInline.h`), which this report notes is "touched by
  nothing at all, even in our tree".
- `es1x88MixerRegister_t` (`ES1x88AudioDriverRegisters.h`), a duplicate of
  `sb16MonoMixerRegister_t` that nothing declares.

The first two draw a `defined but not used` warning from the guest compiler.

## What did not change

`Default.table` and `ESPnP.table` still diff clean against Apple's shipped copies.
`Load_Commands.sect` is still 144 bytes. `ES1x88_3_30.rtfd` was not renamed. The `__data`
symbol addresses now match the reference exactly: `_volMaster` 0x4020, `_volVoc` 0x4023,
`_volMic` 0x4025, `_sbRecordSource` 0x4026, and `_essHardware` moved to `__DATA,__bss`.

---

# Finding 5 settled: the masked expression does not produce the paired form

Task 7 could not decide whether `x = (x & 0x0F) | v` or a bitfield member store produces
the reference's paired memory read-modify-write, and left the question open. Task 8's fix
pass produced this driver's first rebuild with the period compiler and left the question
open anyway. **The rebuild answers it.** Both forms were present in the same rebuilt
binary, so the comparison needed no new experiment — only reading it.

## The two constructs, from the two binaries

Take `updateInputGainLeft`. The reference writes three shadows as paired
read-modify-writes on the destination byte:

```
2684: C0E204          shl  dl, 4
2687: 8025224000000F  and  ds:_volLine, 0Fh
2694: 081522400000    or   ds:_volLine, dl
```

The masked-expression source that produced our first-pass build,
`volLine.rawValue = (volLine.rawValue & ES_VOLUME_BITS) | (gainValue << 4);`, emitted the
**register form** instead — one load, a register `and`, a register `or`, one store:

```
mov  al, byte ptr [0x4022]
and  al, 0Fh
or   al, dl
mov  byte ptr [0x4022], al
```

Three such quads appeared, at `0x4022`, `0x4025` and `0x4024`, with no `and byte ptr` or
`or byte ptr` anywhere in the function.

The counter-construct was already in the same binary. `initializeHardware` writes
`volMaster.reg.left = 0xA; volMaster.reg.right = 0xA;` through the union's **bitfield
members**, and that emitted the reference's form exactly:

```
and byte ptr [0x4020], 0Fh
or  byte ptr [0x4020], 0A0h
and byte ptr [0x4020], 0F0h
or  byte ptr [0x4020], 0Ah
```

with the matching quads at `0x4024`, `0x4022` and `0x4023`. One source file, one compiler,
one build: **the bitfield member store produces the paired memory form and the masked
expression does not.** No further experiment can be needed.

## What changed as a consequence

Every remaining masked expression over a mixer shadow became a bitfield store, and `volMic`
was retyped from `unsigned char` to `sb16MonoMixerRegister_t` so that it could be one. The
union is one byte wide either way, so `__DATA,__data` is unchanged and `_volMic` stays at
`0x4025`. `startDMAForChannel:` reads it as `volMic.rawValue`.

| Site | Was | Now |
| --- | --- | --- |
| `initializeHardware` | `volMic = (volMic & 0x0F) \| 0xA0;` | `volMic.reg.left = 0xA;` |
| `updateInputGainLeft` | three `(x & 0x0F) \| (gainValue << 4)` | `volLine`, `volMic`, `volCD` `.reg.left = gainValue;` |
| `updateInputGainRight` | three `(x & 0xF0) \| (gainValue & 0x0F)` | the same three `.reg.right = gainValue;` |
| `updateOutputAttenuationLeft` | four `(x & 0x0F) \| volInUpperNibble`, plus the `volInUpperNibble` local | `volCD`, `volMaster`, `volLine`, `volVoc` `.reg.left = volumeValue;` |
| `updateOutputAttenuationRight` | four `(x & 0xF0) \| volumeValue`, plus a `volumeValue &= 0x0F` statement | the same four `.reg.right = volumeValue;` |

The rebuild then emits `and byte ptr [addr], 0Fh` / `or byte ptr [addr], reg` — or the
`0F0h` form for the right nibble — at every one of those fifteen sites, in the reference's
order and with the reference's masks. The 4-bit field also emits the
`and reg, 0Fh` truncation that the right-hand methods previously wrote out by hand, so both
hand-written masking statements are gone.

Consistency mattered here: the identical construct backed `updateInputGainLeft`,
`updateInputGainRight`, both attenuation methods and `initializeHardware`'s `volMic` site.
Holding two of them and advancing the others is what produced the review finding, so all
five moved together.

## `updateOutputMute`: the flag, not the commands

Finding 10 has two halves. The first fix pass fixed one and claimed both.

The `D1h`/`D3h` speaker commands were genuinely moved inside their own branches, joining at
`out dx, al`, matching the reference at 3613 and 3627. The negated flag was not: with the
single trailing `outb` inside each arm, `enableOutput` had exactly one use and our gcc
folded the `!` straight into a reversed branch, emitting `test dl, dl` / `jne` with no
`sete` and no stack slot at all. The reference emits

```
3129: 0F94C0    sete al
3132: 8845FC    mov  [ebp+var_4], al
...
3600: 807DFC00  cmp  byte ptr [ebp+var_4], 0
```

— it materialises the flag and re-tests it after the mixer block. The ledger reason
asserting that our method "computes and stores the negated flag" was contradicted by our
own rebuild.

The fix is structural, not an annotation: the speaker write became a **second**
`if (enableOutput)` after the mixer block, which is what makes the flag live across it. The
rebuild now emits `sete bl`, tests it for the mixer block and re-tests it with
`test bl, bl` before the `D1h`/`D3h` pair. Our gcc keeps the flag in `bl` where the
reference spills it to `[ebp-4]`; that is register allocation, not a source construct.

## The `movzx` shortfall is unchanged

Our gcc still omits the `movzx ebx, byte ptr [addr]` zero-extension the reference emits
before `out dx, al`, and so needs no `push ebx` where the reference has one. That accounts
for the residual size gaps in `updateInputGainLeft` and `updateInputGainRight` (216 against
232 each) and contributes to the rest. It is systemic across functions whose source is not
in question, so it is not evidence of a source difference.

## `drvSB16Sound`'s `IO_16Bit` line number

The review pass was asked to correct this report's citation of the `IO_16Bit` bug from
`SoundBlaster16.m:270` to `:269`. It was checked directly: the file has no CRLF, and the
sole occurrence of `IO_16Bit` is on line 270. **`:270` is correct and was left alone.** The
bug itself belongs to Task 10 and was not touched.

# Selector-reference pass: the four `objc_msgSend` calls `reset` was missing

`reset` was `assembly-matched`, but our build omitted four `objc_msgSend` calls the
reference makes. The evidence is an ordered comparison of the `__OBJC,__message_refs`
loads per function across both binaries. Both sections sit at `0x6000` and are 132 bytes,
and the 33 slots hold the same selectors in the same order except that `free` and
`initFromDeviceDescription:` are swapped at `0x6010`/`0x6014`, so the addresses are
directly comparable. `0x6018` is `deviceDescription` and `0x601c` is `channelList` on both
sides.

Before:

```
REF   0x601c 0x6018 0x600c 0x6018 0x6020 0x6018 0x6024 0x6028 0x601c 0x6018 0x602c ...  (22)
OURS  0x6018 0x601c        0x600c        0x6020 0x6024 0x6028               0x602c ...  (18)
```

The reference sends `deviceDescription` five times and `channelList` twice; our source
cached both in locals at `:85`–`:86` and sent them twice and once. `gcc` cannot elide an
`objc_msgSend` — it is an opaque external call — so this was a source-construct
difference, not code generation, and it accounted exactly for the entry's `call: -4` /
`push: -8` deficit, which the ledger reason had misattributed to the systemic `movzx` and
tail-merge shortfall.

Apple caches nothing here. Reading the reference's load order outward — `gcc` loads the
outer selector first, as Finding 1's quoted block shows — the groups are
`[[self deviceDescription] channelList]`, `[[self deviceDescription] numChannels]`,
`[[self deviceDescription] interrupt]`, then `setName:` and `setDeviceKind:`, then a second
`[[self deviceDescription] channelList]` for `channelList[1]`. The two locals were dropped
and the four sites written out. This is Finding 1's own observation applied to the rest of
the method; Task 8 had fixed only the site Finding 1 named.

`configureHardwareForDataTransfer:` had the same defect at `:541` and the same fix applies:
one missing `0x6018` send, now `[[self deviceDescription] channelList]` and
`[[self deviceDescription] interrupt]`.

After, both functions agree entry for entry:

```
reset                             REF/OURS  0x601c 0x6018 0x600c 0x6018 0x6020 0x6018 0x6024
                                            0x6028 0x601c 0x6018 0x602c 0x6034 0x6030 0x6018
                                            0x6038 0x603c 0x6040 0x6044 0x6048 0x604c 0x6048
                                            0x6038                                       (22)
configureHardwareForDataTransfer: REF/OURS  0x601c 0x6018 0x6020 0x6018 0x6064 0x6068 0x606c
```

No other function in the binary differs in its selector sequence, before or after.

`reset`'s `call` and `push` counts are now identical to the reference's, 33 and 46, and its
`out` and `lock inc` counts already were. What remains is the codegen classes already
recorded: `mov` −24, `nop` −7, `jmp` −5, `xor` −3, `movzx` −2, and the branch-form shifts
that follow from tail merging. Rebuilt size 1008 against the reference's 1096; it fell by
20 because the two stack locals went with the fix.

## One new residual in `configureHardwareForDataTransfer:`

The selector fix closed the `objc_msgSend` gap but not the port-write gap: the rebuilt
function emits 26 `out` against the reference's 27. The whole of the difference is the
`B8h` write. The reference emits it **inside both arms** of the direction test —

```
4540: jne  4580                    ; not IN
4542: mov  dx, [0x400c]            ; IN arm
4549: mov  al, 0xb8
4551: out  dx, al
4559: push 0x19                    ; IODelay(25)
4576: mov  al, 0xe                 ; ES_MODE_INPUT
4578: jmp  4616
4580: mov  dx, [0x400c]            ; OUT arm
4587: mov  al, 0xb8
4589: out  dx, al
4597: push 0x19                    ; IODelay(25)
4614: mov  al, 4                   ; ES_MODE_OUTPUT
4616: out  dx, al                  ; shared
```

— joining only at the shared `out` at 4616. Our source writes `B8h` and delays once ahead
of the test, so our build emits that block once, costing one `out`, one `IODelay` call, one
`push` and one `lock inc`. Whether Apple's source duplicated the two statements into each
arm or Apple's `gcc` duplicated the block cannot be told from the binary, so the source was
left alone rather than restructured on a guess. The entry is already
`intentional-mismatch`; its reason now names this alongside the `(channelCount == 2)` stack
boolean and the paired IRQ/DMA byte construction. Rebuilt size 1180 against the
reference's 1328.
