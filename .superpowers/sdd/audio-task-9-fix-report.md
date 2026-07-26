# Task 9 fix report — drvSB16Sound report pass

Worktree `D:\RhapsodiOS\.claude\worktrees\audio-recon`, branch `audio-recon`.
Only `src/drivers-i386/sound/drvSB16Sound/reconstruction/divergences.md` was edited.
`ledger.json` needed no change: none of the three defects was an examination-status error,
so `assembly-matched=11 / intentional-mismatch=2 / unexamined=15` is unchanged and correct.

The central conclusion — nothing is invented, both giants are one inlined `resetHardware()`
expansion — was not disturbed.

---

## Verification (verbatim)

Run from the worktree root with `PYTHONPATH=tools/binrecon` and
`BINRECON_REFERENCE=C:/Users/raynorpat/Downloads/test/Drivers/i386/SoundBlaster16.config/SoundBlaster16_reloc`
exported, after deleting `ledger.json.lock`.

```
--- CHECK 1: load_source_map ---
source map OK
--- CHECK 2: binrecon ledger ---
ledger D:\RhapsodiOS\.claude\worktrees\audio-recon\src\drivers-i386\sound\drvSB16Sound\reconstruction\ledger.json entries=28 assembly-matched=11 intentional-mismatch=2 unexamined=15
--- CHECK 3: buckets ---
ledger entries: 28
duplicate addresses: []
buckets: {'assembly-matched': 11, 'unexamined': 15, 'intentional-mismatch': 2}
bucket sum: 28
IDA function set == ledger address set: True
--- CHECK 4: driver source untouched ---
(both empty above = no driver source touched)
```

Check 2 matches the expected `entries=28 assembly-matched=11 intentional-mismatch=2
unexamined=15` exactly — no finding forced a status change.

Check 3: 28 ledger entries, no duplicate address, every entry carries exactly one `status`
string, the three buckets sum to 28, and the ledger's address set is identical to the set of
28 function addresses in `analysis-reference-ida.json`.

Check 4: `git diff --stat` and `git status --porcelain` over
`src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj` both
produced no output. `SoundBlaster16.m:270`'s nonexistent `IO_16Bit` enumerator is still
broken, as required — Task 10 repairs it in its own baseline-build commit.

---

## Important 1 — the `3Bh` mixer row stated the wrong shift

**Changed.** `divergences.md` table row for `3Bh` now reads `<< 6`.

I dumped `initializeHardware` 3100–4660 from the IDA listing and read all 24 writes.
My independent count, in binary order:

| # | Reg | Value read | Shift | Shift site |
| --- | --- | --- | --- | --- |
| 1 | `30h` | `_volMasterLeft` | `shl bl, 3` | 3142 |
| 2 | `31h` | `_volMasterRight` | `shl bl, 3` | 3205 |
| 3 | `32h` | `_volVoiceLeft` | `shl bl, 3` | 3268 |
| 4 | `33h` | `_volVoiceRight` | `shl bl, 3` | 3331 |
| 5 | `34h` | `_volMIDILeft` | `shl bl, 3` | 3394 |
| 6 | `35h` | `_volMIDIRight` | `shl bl, 3` | 3457 |
| 7 | `36h` | `_volCDLeft` | `shl bl, 3` | 3520 |
| 8 | `37h` | `_volCDRight` | `shl bl, 3` | 3583 |
| 9 | `38h` | `_volLineLeft` | `shl bl, 3` | 3646 |
| 10 | `39h` | `_volLineRight` | `shl bl, 3` | 3709 |
| 11 | `3Ah` | `_volMic` | `shl bl, 3` | 3772 |
| 12 | `3Bh` | `_volPCSpeaker` | **`shl bl, 6`** | **3835** |
| 13 | `3Ch` | `_outputMixerSwitch` | none | — |
| 14 | `3Dh` | `_inputMixerSwitchLeft` | none | — |
| 15 | `3Eh` | `_inputMixerSwitchRight` | none | — |
| 16 | `43h` | literal `0` (`xor al, al` at 4106) | none | — |
| 17 | `44h` | `_trebleLeft` | `shl bl, 4` | 4132 |
| 18 | `45h` | `_trebleRight` | `shl bl, 4` | 4195 |
| 19 | `46h` | `_bassLeft` | `shl bl, 4` | 4258 |
| 20 | `47h` | `_bassRight` | `shl bl, 4` | 4321 |
| 21 | `3Fh` | `_lastStageGainInputLeft` | `shl al, 6` | 4402 |
| 22 | `40h` | `_lastStageGainInputRight` | `shl bl, 6` | 4463 |
| 23 | `41h` | `_lastStageGainOutputLeft` | `shl bl, 6` | 4522 |
| 24 | `42h` | `_lastStageGainOutputRight` | `shl bl, 6` | 4581 |

**24 writes. The reviewer's grouping is right on every row, and `3Bh` was the single wrong
one.** `3Bh` shifts left six, not zero:

```
 3829: 8A1D4C400000   mov  bl, ds:_volPCSpeaker
 3835: C0E306         shl  bl, 6
 3838: 668B152C400000 mov  dx, word ptr ds:_sbMixerAddressReg
 3845: B03B           mov  al, 3Bh
 3847: EE             out  dx, al          ; then IODelay(15), out bl, IODelay(75)
```

(The reviewer's quoted bytes for 3829 were `8A1D5C400000`; the actual encoding is
`8A1D4C400000` — `ds:404Ch` is `_volPCSpeaker`, `ds:405Ch` is `_bassLeft` at 4252. The
address, symbol and shift in the finding were all correct; only the byte string was
transcribed from the neighbouring site.)

Beyond the table row I added a paragraph naming the four shift groups explicitly and
quoting the `3Bh` site, so a Task 10 agent reading only the prose still emits
`_volPCSpeaker << 6`.

## Important 2 — the DSP wait-loop count was wrong twice and did not sum

**Changed in both places.** I counted `cmp …, 270Fh` (the 10000 bound test, one per
expansion) across all 28 functions:

```
-[SoundBlaster16 initializeHardware]                     7  [1791, 1931, 2091, 2231, 2391, 2559, 2691]
-[SoundBlaster16 updateSampleRate]                       3  [6847, 6999, 7135]
-[SoundBlaster16 startDMAForChannel:read:buffer:...]     8  [8191, 8327, 8475, 8615, 8743, 8879, 9027, 9163]
-[SoundBlaster16 stopDMAForChannel:read:]                4  [9363, 9575, 9619, 9827]
-[SoundBlaster16 timeoutOccurred]                        7  [10499, 10639, 10799, 10939, 11099, 11267, 11399]
TOTAL 29
```

No other function in the binary contains the expansion. **7 + 3 + 8 + 4 + 7 = 29.** The old
text said 25 with a per-function tally that summed to 28, and understated
`stopDMAForChannel:read:` at three.

- `:485`–`:487` now says 29, lists every address, states the arithmetic, and calls out the
  four-not-three correction with a pointer to Finding 19.
- `:199` now says "exactly 29 times" instead of "roughly 25 times".
- Finding 19 gained an explicit note: four waits, two per `isRead` arm (9363/9575 in the
  first copy, 9619/9827 in the second), so Task 10 puts two waits in the shared helper and
  the two call sites produce four. Without this a Task 10 agent writes one wait too few.

## Important 3 — the unrecorded tail-merge that makes a selector count a false positive

**Changed.** Finding 10 gained a subsection, "The one exception to the selector-count rule
in this driver". Verified from the listing:

- `paName` sites in `initializeDMAChannels` (288–1275): **664, 896, 957, 1106, 1165, 1233 —
  six.**
- `[self name]` sends in our `SoundBlaster16.m` `initializeDMAChannels`: **seven**
  (`"Must specify either one or two channels"`, `"could not set transfer width to 8 bits"`,
  `"dma transfer mode error"` ×2, `"dma auto initialize error"` ×2, `"could not set
  transfer width to 16 bits"`).
- Branch targets confirmed: `1014: 0F85 D4000000 jnz loc_4D0` → 1020 + 212 = **1232**;
  `1222: 75 08 jnz loc_4D0` → 1224 + 8 = **1232**. Both `setAutoinitialize:` failure arms
  land on one shared block at 1232 holding the single surviving `paName` send (1233), the
  `push offset aSDmaAutoInitia` (1254) and the `IOLog` (1259).
- The string at `0x3844` is `'%s: dma auto initialize error %d'` — no trailing `\n`,
  matching our source exactly.
- The `setTransferMode:` failure blocks at 957 and 1165 were **not** merged: each keeps its
  own `paName` send and its own `push offset aSDmaTransferMo` (`0x3824`), converging only
  at the `call _IOLog` at 1259 (`loc_4EB`). That asymmetry is what made the count look like
  a source difference.

The new text states in bold that Task 10 must keep all seven `[self name]` sends and the
seven `IOLog` calls that consume them, must not delete an `IOLog` or hoist one into a
shared arm to reach six, and that six-in-binary against seven-in-source is the expected
result here rather than a divergence to close.

---

## Minor findings

**`:927` "nineteen" vs the 24-row table.** Changed to "twenty-four". 24 is right — I
counted the writes myself (table above) and the parenthetical at `:957` already said 24.

**`:366` `__OBJC,__cls_meth` "exactly one entry".** Reworded. The section is 60 bytes =
3 × (8-byte list header + 12-byte method), i.e. **three single-entry method lists**. Decoded
from the file: `probe:` (name ptr 25707, imp 0), `driverKitVersionForSoundBlaster16`
(26753, imp 13548), `kernelServerInstance` (26787, imp 13560) — the latter two being the
build-generated glue classes already recorded under *Unmapped*. The intended claim
(SoundBlaster16 declares one class method) is now stated as such and the section's actual
contents are described separately. `__inst_meth` is 296 bytes = 8 + 24 × 12, one list of
24, which the text now also states.

**`IODMATransferWidth` → `IOEISADMATransferWidth`.** The typedef at
`src/driverkit-3/driverkit/i386/directDevice.h:163`–`:169` is named `IOEISADMATransferWidth`
(name on `:169`). Corrected at Finding 13 (`:1132` originally) and at the Baseline build
section (`:39`), which carried the same wrong name; the brief cited `:1109`, but that line
names `IODMATransferMode`, which is correct as written (`directDevice.h:63`). The member
`IO_16BitByteCount` and its value 2 were correct, so Finding 13's fix still lands unchanged.

**`:763` "the five unions and seven bytes".** Reworded to eleven. `SoundBlaster16Inline.h`
has five `sb16MonoMixerRegister_t` unions at `:78`–`:82` and eleven `unsigned char` mixer
shadows: seven at `:83`–`:89` (`volMic`, `inputControlLeft`/`Right`,
`inputGainLeft`/`Right`, `outputGainLeft`/`Right`) plus the four `lastStageGain*` at
`:100`–`:103`. The disposition now names both groups and points at the mapping table that
already covers retyping the `lastStageGain*` set. (`interruptStatus` at `:94` is also
`unsigned char` but is not a mixer shadow and is excluded.) Wording only — no substantive
change.

**`:389`–`:408` unmarked elision in the `reset` listing.** Fixed by including the two
dropped instructions rather than adding an ellipsis, since they are only two and they
matter to the control flow:

```
 1391: 31D2             xor  edx, edx            ; status = NO
 1393: 83C40C           add  esp, 0Ch
 1396: EB07             jmp  loc_57D             ; -> 1405, skipping the status = YES arm
 1400: BA01000000       mov  edx, 1              ; status = YES
```

Confirmed against the listing: `loc_57D` is 1405 (1398 + 7), the `test dl, dl`. Every
elision in the document is now either marked or absent.

**`:104`–`:107` classification promise vs. eleven "matches" rows.** Reconciled by widening
the promise rather than weakening the table. The paragraph now names three classifications —
**invented** (authorises a rewrite), **divergent**, and **matches** ("the source implements
the reference's logic and no difference was found") — states that **matches** is the
strongest form in the table and authorises nothing, and notes that no function here is
invented, so every row is `divergent` or `matches`. This preserves `:138`–`:140`'s
statement that nothing is invented.
