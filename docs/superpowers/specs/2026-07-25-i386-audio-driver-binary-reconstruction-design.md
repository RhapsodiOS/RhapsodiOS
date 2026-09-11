# Binary reconstruction of the i386 audio drivers

Reconstruct `drvBeepSound`, `drvSB8Sound`, `drvES1x88Sound` and `drvSB16Sound`
against Apple's shipped i386 driver binaries, using the `tools/binrecon`
toolchain. Each driver gets a report pass that maps every reference function to
our source and records the divergences, followed by a separate fix pass.

This continues
[2026-07-25-bus-driver-binary-reconstruction-design.md](2026-07-25-bus-driver-binary-reconstruction-design.md),
[2026-07-25-intel-bus-driver-binary-reconstruction-design.md](2026-07-25-intel-bus-driver-binary-reconstruction-design.md)
and
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md).
Everything those efforts built — reference-only profiles, the
`binrecon source-map` subcommand, the `load_source_map` semantic loader, the
`reconstruction/` artifact layout, the `ledger-v1` vocabulary,
`tools/binrecon/parity_check.py`, and `vm/build-i386-input-recon.sh` as a build
harness model — is in place and is reused unchanged.

## Motivation

`src/drivers-i386/README` marks all four "needs compiled and then tested". None
has been checked against the binary Apple shipped. Scoping this work read the
reference symbol tables, `__TEXT,__cstring` sections, `__DATA` contents and
config tables directly, before any analyzer run, and found one driver missing a
method it cannot load without (§2.1), one whose IRQ validation admits an
interrupt the hardware does not use and rejects one it does (§2.2), one carrying
four methods copied from a different card's driver (§2.3), scaffolding gaps in
three of the four (§2.6), and table gaps in three of the four (§2.5).

Unlike the Intel effort, every reference driver has a source counterpart in our
tree, and every reference method name except one has a name-level counterpart.
Nothing is missing wholesale. Scoping suspected that two of the four were closer
to inventions than reconstructions, on a size heuristic, and §4.3 was written to
allow for that. The report passes refuted it: no method in any of the four
drivers was classified invented, and the §4.3 rewrite authorisation was never
exercised. See the retraction in §2.2.

## 1. Scope

### 1.1 Targets

The `_reloc` preload executables under
`C:\Users\raynorpat\Downloads\test\Drivers\i386`:

| Driver | Reference binary | File size | `__text` | Functions | Hand-written |
| --- | --- | --- | --- | --- | --- |
| drvBeepSound | `Beep.config/Beep_reloc` | 37984 | 2060 | 13 | 11 |
| drvSB8Sound | `SoundBlaster8.config/SoundBlaster8_reloc` | 53552 | 8896 | 29 | 27 |
| drvES1x88Sound | `ES1x88AudioDriver.config/ES1x88AudioDriver_reloc` | 53280 | 8660 | 25 | 23 |
| drvSB16Sound | `SoundBlaster16.config/SoundBlaster16_reloc` | 58224 | 13572 | 28 | 26 |

95 functions, of which 87 are hand-written; the remaining 8 are the two
build-generated glue methods per driver described in §2.7. All four retain full
symbol tables, so address-to-name resolution is exact rather than inferred.

### 1.2 Config tables are in scope

Each driver's `Default.table` is compared against the reference copy, as in the
Intel and input specs. So are drvSB16Sound's `SB16PnP.table`,
`SB16SingleDMAChannelPnP.table` and `SingleDMAChannel.table`, and
drvES1x88Sound's `ESPnP.table`. They are checked-in source, not build output.

`"Driver Version"` is emitted by Apple's build and stays out of the comparison.

### 1.3 Out of scope

**MicrosoftSound.** `MicrosoftSound.config` ships in the same reference
directory, but nothing under `src/drivers-i386/sound` corresponds to it. Writing
that driver is a from-scratch effort, not a reconstruction, and belongs to its
own spec.

**drvIntelAC97Sound and drvSB128Sound.** Neither has a reference binary in the
Rhapsody driver set. drvSB128Sound is already marked "complete"; drvIntelAC97Sound
is a later addition with no Apple counterpart to compare against.

No boot testing, no QEMU run, and no binrecon comparison of a rebuilt artifact
against the reference. Verification of the fix passes is defined in §4.3.

`src/kernel-7` is untouched, including the `IOAudio` class all four drivers
subclass.

## 2. Findings that shaped this design

All of these come from reading the reference Mach-O symbol table,
`__TEXT,__cstring` section, `__TEXT,__const` and `__DATA` contents, the
`Loaded Server` sections, and the config tables during scoping, before any
analyzer run. They are recorded so the plan can be checked against them.

### 2.1 drvBeepSound has no `+probe:`

The reference defines `+[Beep probe:]` at `__text:0`, 68 bytes. Our `Beep.m`
defines no such method and `Beep.h` declares none — the string `probe` does not
appear in either file. `+probe:` is how DriverKit decides whether to instantiate
a driver at all, so its absence is the same class of load blocker as
drvPS2Mouse's `PS2KeyboardController` lookup and `Intel824X0`'s
`"Auto Detect_IDs"` typo. Unlike those it cannot be fixed from a string
comparison; the reference body has to be read.

Three further divergences in the same driver, none of them behavioural on their
own:

**The sequence table has its first two names swapped.** The reference
`_defaultBeepSequences` occupies `__DATA,__data:8204` for 96 bytes — six 16-byte
records. Resolving each record's name pointer against `__TEXT,__cstring` gives
`Plain {1, 1, 1}`, `Blip {2, 3, 4}`, `Up {8, 17, 16}`, `Down {8, 15, 16}`,
`Octave {2, 2, 1}` and the null terminator, in that order. Our
`defaultBeepSequences` in `Beep.m:66` has the same five value triples in the same
order, but labels the first two `Blip` and `Plain` — the reverse of Apple's.

This is behavioural, not cosmetic. `Default.table` ships `"Style" = "Plain"`, so
our driver plays Apple's `Blip` when asked for `Plain`, and every index
`stringToStyle` returns for those two names is swapped with respect to the
reference.

An earlier draft of this section claimed the table matched Apple byte for byte
and cited it as the effort's strongest evidence that drvBeepSound is a real
reconstruction. That was a scoping error: the value triples were compared against
our array's ordering without resolving the name pointers, which happen to be laid
out in `__cstring` in the reverse of source order. drvBeepSound's report pass
(§5, Phase 2) caught it. The three remaining triples are correctly labelled, so
the driver is still a reconstruction rather than an invention — but the table is
not the clean evidence it was presented as.

The reference exports it `external`; ours is `static`. That is the
static-versus-external divergence commit `b27e22b8` resolved in `drvPCMCIABus` by
renaming our source to match Apple's, and the drvSerialPointingDevice §2.4
precedent follows it. `_stringToStyle` is `local` in the reference, so our
`static int stringToStyle` already matches and must be left alone.

**The device name and kind are data, not literals.** The reference holds
`_beepDeviceName` and `_beepDeviceKind` at `__DATA,__data:8192` and `:8197`,
containing `Beep` and `Audio`. Our `Beep.m:176` and `:179` pass string literals
to `setName:` and `setDeviceKind:` instead. Apple's `__cstring` has neither
string, confirming the reference reads the data symbols. Our form would route
both literals into `__cstring` and show up as string-parity extras.

**The sleep mechanism differs.** The reference imports `_assert_wait`,
`_thread_block`, `_thread_set_timeout` and `_hz`, and imports neither `_IOSleep`
nor `_IOLog` nor `_IODelay`. Our `Beep.m:253` calls `IOSleep(timeout * 1000 / hz)`
and our `Beep.m:167` calls `IOLog`, emitting
`Beep: Initialized (default: %d Hz, %d ms)` — a string the reference does not
have. The reference also carries a `__timer_cnt_port_` table at
`__TEXT,__const:2060` holding `{0x40, 0x41, 0x42}`, the three PIT counter ports,
where our source uses the `PIT_COUNTER2` constant directly.

Every one of the reference's nine `__cstring` entries appears in our source.

### 2.2 drvSB16Sound validates the wrong IRQ set

Our `SoundBlaster16.m` logs `SoundBlaster16: IRQ must be 2, 5, 7, or 10.`; the
reference logs `SoundBlaster16: Audio IRQ must be one of 5, 7, 9, 10.`. The two
sets differ in both directions: the string admits IRQ 2, which Apple does not,
and rejects IRQ 9, which Apple accepts.

**But the string is in dead code.** The report pass found the divergence confined
to `checkSelectedDMAAndIRQ()`, which nothing calls. Our `-[SoundBlaster16 reset]`
already implements Apple's set exactly, compiling to the reference's own
`cmp esi,5 / jz / cmp esi,7 / jz / lea eax,[esi-9] / cmp eax,1 / jbe` at
1352–1368. So the shipped behaviour was never wrong, and this is a stale-code
finding rather than a validation bug. The `Default.table` reading below still
holds and is what made the contradiction visible.

Two reference strings are absent from our source entirely:
`SoundBlaster16: DSP read error.` and
`SoundBlaster16: SoundBlaster not detected at address 0x%0x.`. The second is the
probe-failure message, which means our probe path either cannot fail the same way
or fails silently.

Our DMA validation wording also diverges — `8-bit DMA channel must be 0, 1, or 3`
against Apple's `8-Bit DMA channel must be one of 0, 1 and 3` — and we emit an
`8-bit and 16-bit DMA channels must be different` check the reference has no
string for. These are wording-and-behaviour claims, not just wording.

**~~Structurally the driver is closer to an invention than a divergence.~~**
Retracted. Apple's `-[SoundBlaster16 initializeHardware]` is 2992 bytes and its
`-[SoundBlaster16 timeoutOccurred]` is 3032 against our six and twelve lines —
together 44 percent of the reference `__text` — and this section concluded from
that size gap that our source does not implement their logic.

drvSB16Sound's report pass (§5, Phase 8) refuted it. Both methods are one
inlined `resetHardware()` expansion out of `SoundBlaster16Inline.h`: taking
`initializeHardware` from 1681 and `timeoutOccurred` from 10389, the two bodies
run 792 instructions of which **780 are byte-identical**, diverging first at
index 780. This was reproduced independently during review. Neither method is
invented, and the same size-gap-means-invention inference had already failed
once in this effort on drvSB8Sound, whose 2176-byte `initializeHardware` against
ten source lines turned out to have no divergences at all.

**No method in any of the four drivers was classified invented**, so the
conditional rewrite authorisation §4.3 grants was never exercised. Three
*sub-blocks* inside `SoundBlaster16Inline.h` do lack counterparts and are
replaced wholesale — the two invert-byte DSP probes, the mixer-register-probe
card classification, and `initMixerRegisters()`'s register set — but those are
recorded findings against a helper, not a rewrite of a method.

The reference `__DATA,__data` carries initialised mixer defaults from offset 52
that our source will have to match. Decoded: `_volMasterLeft` and
`_volMasterRight` `0x18`; `_volVoiceLeft` and `_volVoiceRight` `0x15`;
`_volLineLeft` and `_volLineRight` `0x10`; `_volPCSpeaker` `0x02`; `_volMic`
`0x15`; `_trebleLeft` and `_trebleRight` `0x08`; `_bassLeft` and `_bassRight`
`0x09`; `_volMIDILeft` and `_volMIDIRight` `0`; `_volCDLeft` and `_volCDRight`
`0x15`; the four `_lastStageGain*` fields `0x02`; `_outputMixerSwitch` `0x06`;
`_inputMixerSwitchLeft` `0x15`; `_inputMixerSwitchRight` `0x0b`. This is
evidence for the fix pass, not a finding on its own.

### 2.3 drvES1x88Sound carries SoundBlaster16 code

Four methods in our `ES1x88AudioDriver.m` have no symbol anywhere in the
reference binary: `initializeDMAChannels` (line 215),
`initializeLastStageGainRegisters` (456), `updateSampleRate` (705) and
`setBufferCount:` (981). Objective-C methods appear in `__text` whether or not
they are called, so their absence from a symbol table this complete means Apple's
driver does not define them.

The accompanying string set says where they came from. Our source emits
`%s: Must specify either one or two channels.`,
`%s: could not set transfer width to 16 bits, error %d.`,
`LS Input Gain`, `LS Output Gain`, and four 16-bit DMA channel messages — all of
which appear verbatim in the SoundBlaster16 reference and none of which appear in
the ES1x88 reference. The ES-1688 family drives a single DMA channel; the 16-bit
channel logic has no hardware to address.

Every one of the reference's 23 `__cstring` entries does appear in our source, so
this is an excision problem rather than a missing-code problem.

`Default.table` and `ESPnP.table` both match the reference exactly, including
Apple's `"Driver Version"` stamp. They are the only two tables in this effort
that need no change.

### 2.4 drvSB8Sound is in good shape

Every one of the reference's 19 `__cstring` entries appears in our source, and
every string of ours the reference lacks sits under `#ifdef DEBUG` in
`SoundBlaster8.m` or `SoundBlaster8Inline.h`. Our method set matches the
reference method set name for name.

The reference defines `_writeToDSP` at `__text:0` (40 bytes) and `_readFromDSP`
at `__text:40` (32 bytes) as out-of-line `local` functions, and our source
already matches: both are declared plain `static` at
`SoundBlaster8Inline.h:151` and `:169`, alone among the twenty-two functions in
that header, every other one of which is `static __inline__`. Apple made the
same distinction we did, which is why the compiler emits these two out of line
and inlines the rest.

An earlier draft of this section claimed ours were `static inline` and treated
reproducing Apple's out-of-line emission as an open risk. That was a scoping
error — the qualifier was read from the surrounding functions rather than from
these two. drvSB8Sound's report pass (§5, Phase 4) caught it. There is nothing
to change and no fallback to record.

Our help bundle is misnamed. `Default.table` names `"Help File" = "SB8.rtfd"`,
matching Apple's table exactly, but our tree carries the bundle as
`English.lproj/DriverHelp/SB8_3_31.rtfd`, so the key resolves to nothing.
Apple's shipped `SoundBlaster8.config/English.lproj/Help/SB8.rtfd` settles the
correct name. drvSB16Sound's `SB16_3_31.rtfd` and drvES1x88Sound's
`ES1x88_3_30.rtfd` both already match their references and must not be renamed.

### 2.5 Three of the four table sets have gaps

drvBeepSound's `Default.table` is missing `"Version" = "5.00"`.

drvSB16Sound's `Default.table`, `SB16PnP.table`,
`SB16SingleDMAChannelPnP.table` and `SingleDMAChannel.table` are each missing
`"Version" = "4.02"`. `SB16PnP.table` also lacks a trailing newline.

drvSB8Sound's `Default.table` is missing `"Help File" = "SB8.rtfd"`,
`"Server Name" = "SoundBlaster8"` and `"Version" = "5.01"`, and carries a stray
`"Version" = "4.00"` on a line Apple's table does not have. The stray line is
removed rather than edited in place, because Apple's `"Version"` sits at the end
of the file with the other build-adjacent keys.

drvES1x88Sound needs no table change (§2.3).

Every other line in all eight tables matches the reference.

### 2.6 Three of the four are missing `PB.project`

drvSB8Sound, drvSB16Sound and drvES1x88Sound each lack the `PB.project` at the
project root, in the `.drvproj`, and in the `.lksproj` — nine files. drvBeepSound
has all three. This is the same gap the drvPCParallel and drvVGA efforts closed,
and it is fixed the same way. Nothing else in the build system is touched.

### 2.6a The `Loaded Server` sections are close but not exact

`src/driverTools-1/KernelServerProjectType/kernelserver.make` emits each section
from whether a filename appears in the project's `OTHERSRCS`. All four drivers
already name `Load_Commands.sect`, so the section is produced; the content is
what diverges.

Apple's `Loaded Server,Load Commands` is 144 bytes for Beep, SoundBlaster8 and
ES1x88AudioDriver — the generic audio load commands, with a trailing space on the
fourth line's `# `. Our `Load_Commands.sect` is 144 bytes for drvSB8Sound and 143
for drvBeepSound and drvES1x88Sound, which have dropped that trailing space.

Apple's SoundBlaster16 section is a different 210-byte file:

```
# 
# This loadable kernel driver does not use a Mig-generated interface,
# so no handler or server interface is specified.
#
# This driver must be wired down.
WIRE
SMAP		audio0 audioMessages 0
ADVERTISE	audio0
```

Ours is the generic 143-byte one.

**No `Unload_Commands.sect`.** None of the four references carries a
`Loaded Server,Unload Commands` section, so unlike the input drivers, none is
added and none must be.

### 2.7 The build-generated residue is the same as before

`+[<Name>KernelServerInstance kernelServerInstance]` and
`+[<Name>Version driverKitVersionFor<Name>]` appear in all four binaries, as do
the `_xxx.86`/`_xxx.89`/`_xxx.92` `__DATA,__bss` statics and the
`_<Name>_VERS_STRING`, `_<Name>_VERS_NUM` and `_<Name>_instance` data symbols.
They are emitted by the Kernel Server project type and `Load_Commands.sect`, not
written by hand, and are expected to be absent from source. Only the two glue
methods carry function bodies and therefore appear in the source map's `unmapped`
bucket; the rest are data symbols outside `__TEXT,__text` and do not appear there
at all, per the drvPCIBus precedent.

## 3. Artifact layout

### 3.1 Committed

Per driver, a `reconstruction/` directory beside the sources:

```
src/drivers-i386/sound/drvBeepSound/reconstruction/
    source-map.json      # source-map-v1, complete function partition
    ledger.json          # ledger-v1, human-reviewed parity ledger
    divergences.md       # report-pass findings, including table divergences
```

Also committed: one reference-only profile per driver at
`tools/binrecon/profiles/{beep,soundblaster8,es1x88audiodriver,soundblaster16}.json`,
copied from the existing `ps2keyboard.json` with `output_dir` set to
`../out/<driver>`; and `vm/build-i386-sound-recon.sh`, modelled on the committed
`vm/build-i386-input-recon.sh`.

### 3.2 Not committed

Reference binaries (already external to the repo), rebuilt artifacts staged under
`out/i386/`, and all analyzer output under `tools/binrecon/out/`, which
`.gitignore:17` already excludes. The `.i64` databases, `.log` files and `.lock`
files are machine- and run-specific. The durable, reviewable evidence is the
source map, the ledger and the divergence document, all of which are text.

### 3.3 Reference paths

`BINRECON_REFERENCE` is per-shell-session. The values are:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\Beep.config\Beep_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\SoundBlaster8.config\SoundBlaster8_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\ES1x88AudioDriver.config\ES1x88AudioDriver_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\SoundBlaster16.config\SoundBlaster16_reloc
```

## 4. The three kinds of pass

### 4.1 Table pass

Runs once, covering all four drivers, before any report pass. This is a
deliberate carve-out from the standing discipline that fixes touch only what the
ledger flags. It is justified because every fix in it rests on evidence stronger
than a decompilation: a direct diff of our checked-in table against Apple's
checked-in table, a byte-count comparison against a reference section, or a file
that is simply absent. No analyzer run is needed and no ledger entry is required
to authorise them.

The complete list:

1. The six missing `"Version"` lines and drvSB8Sound's two missing keys, with its
   stray `"Version" = "4.00"` removed (§2.5).
2. The nine missing `PB.project` files (§2.6).
3. The trailing space restored in drvBeepSound's and drvES1x88Sound's
   `Load_Commands.sect`, and drvSB16Sound's replaced with Apple's 210-byte
   variant (§2.6a).

Nothing else. Every other finding in §2 waits for its driver's report pass — in
particular drvSB16Sound's IRQ set (§2.2), which is a code change and not a table
change, even though a table key names the same quantity.

*Verify:* `binrecon validate --profile …` prints each reference identity with no
rebuilt artifact; each of the eight tables in scope differs from the reference
only in `"Driver Version"`; each `Load_Commands.sect` matches its reference
`Loaded Server,Load Commands` byte count — 144, 144, 144 and 210.

### 4.2 Report pass

Runs per driver, needs no VM.

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/<driver>.json`
   produces IDA 9.2, Ghidra 12.1 and angr 9.3.0 analyses plus
   `consensus-reference.json` under the gitignored `tools/binrecon/out/<driver>/`.

2. **Map.** `binrecon source-map --reference-analysis … --binary … --source-dir …
   --repo-root … --output …` anchored on the Mach-O symbol table, then
   hand-resolve the residue. Every reference function lands in exactly one
   bucket:

   - `mapped` — resolved to a file and line.
   - `unmapped` — build-generated glue (§2.7), or, for `+[Beep probe:]`, a
     reference function with no source counterpart at all (§2.1).
   - `boundary_disputed` — analyzers disagree on function extent.
   - `duplicate_candidates` — a name resolves to two or more plausible sites.

3. **Diff.** Decompile every `mapped` function and compare against our source,
   batched by source file. The comparison covers control-flow shape, literal
   constants, I/O port addresses, struct field offsets, and call targets.

4. **Compare tables.** Diff each config table against the reference copy,
   ignoring `"Driver Version"`. After the table pass this is expected to be clean
   for all four; a residual difference is a table-pass defect, not a new finding.

5. **Report.** Write `divergences.md` with the reference decompilation beside our
   source for each finding, and assign each function a `ledger-v1` status. The
   ledger records parity confidence, not a repair queue; its vocabulary is
   `unexamined`, `signature-confirmed`, `control-flow-confirmed`,
   `assembly-matched`, and `intentional-mismatch`. A function that matches gets
   the strongest status the evidence supports. A function that diverges stays
   `unexamined` and gets an entry in `divergences.md`, per the convention
   established by the drvPCIBus pass. `rebuilt_sha256` is `null` throughout,
   which `ledger-v1` permits.

**Done when** `load_source_map(path, reference_analysis=…, repo_root=…)` passes —
it enforces the complete function partition, names, full function sizes, and
source-line bounds — every `unmapped` entry has a stated reason class in
`divergences.md`, and no function remains without a ledger entry.

### 4.3 Fix pass

Runs per driver, after that driver's report pass is committed, as a separate
phase with its own commits.

**Disposition.** Every finding in `divergences.md` is resolved one of two ways.
Either the source is changed to match the reference, after which the function's
ledger status advances to the level the new evidence supports, or the divergence
is accepted and the ledger status becomes `intentional-mismatch` with a reason
and a reviewer — the ledger CLI requires both. Accepted by default:
build-generated glue, compiler-emitted statics, and anything whose reference form
depends on Apple's toolchain rather than on our source.

**Discipline.** Fixes touch only code the ledger flags. Three approved
exceptions:

- The §2.1 `static` → `external` linkage change on `_defaultBeepSequences`, which
  is a property of a declaration the ledger already flags rather than a separate
  finding.
- `+[Beep probe:]` is written from the reference disassembly (§2.1). It has no
  source counterpart, so it cannot be a ledger-flagged divergence of existing
  code.
- **Wholesale rewrite where the report pass confirms invention.** Where a
  method's body is invented rather than divergent, the fix pass rewrites or
  removes it as a unit rather than finding-by-finding, on the drvBusMouse §2.3
  precedent. The authorisation is conditional: it applies only to methods whose
  report pass says the source does not implement the reference's logic, and the
  report pass must say so in `divergences.md` before the rewrite starts.

  **The rewrite half of this was granted and never exercised.** It was written
  with `-[SoundBlaster16 initializeHardware]` and `-[SoundBlaster16
  timeoutOccurred]` in view, on §2.2's size heuristic. §2.2 now retracts that
  premise: drvSB16Sound's report pass found both methods are one inlined
  `resetHardware()` expansion, 780 of 792 instructions byte-identical, and **no
  method in any of the four drivers was classified invented**. The condition was
  therefore never met and no method was rewritten. The excision half *was*
  exercised, once: drvES1x88Sound's four SB16-derived methods (§2.3), removed in
  Phase 7 after Phase 6 recorded that the reference has no counterpart for them.
  Do not read this bullet as authorising a rewrite on the strength of §2.2 —
  read §2.2 first, which says the opposite.

No other adjacent cleanup, no refactoring of code that is not divergent.

**Verification.** Three checks per driver, each against the rebuilt `_reloc`:

1. **Compiles.** `vm/build-i386-sound-recon.sh` exits 0 and a `_reloc` lands on
   disk. Warnings are captured to a log and reviewed, but do not gate.

2. **String parity.** `tools/binrecon/parity_check.py` against the reference's
   `__TEXT,__cstring` set. This is the check that would have caught §2.1 through
   §2.3 immediately, and it costs nothing. It reads `__cstring` only, so string
   literals the compiler routes to `__OBJC` sections — selector names, class
   names — cannot produce false positives.

3. **Symbol parity.** `parity_check.py` against the reference's `__TEXT,__text`
   symbol names. Catches the §2.1 linkage change and the §2.3 excisions.

Checks 2 and 3 are reported, not gated: our build is unstripped and will carry
extras. A reference string or symbol missing from our build is a finding; an
extra one of ours is not automatically a finding. drvSB8Sound's and
drvSB16Sound's `#ifdef DEBUG` strings are expected extras when the build defines
`DEBUG`, and expected absences when it does not; either way they are not
findings.

`parity_check.py` compares symbol names as a set, so a name defined more than
once in one binary collapses to a single entry. All four drivers here have fully
distinct `__text` symbol names, so that limitation does not bite.

**Per-function size.** Every rewritten function is compared in size against its
reference counterpart, as in the Intel and input specs. A rebuilt function
materially larger than the reference means we invented structure again.

**Baseline first.** Each driver is built before any source edits, so a
pre-existing failure cannot be misattributed to our changes. All four are marked
"needs compiled and then tested" and may never have been built. If a baseline
build fails, repairing that breakage is an explicit, separately committed step
ahead of that driver's divergence fixes. The three missing `PB.project` sets are
the one known exception: they are already diagnosed (§2.6) and are fixed in the
table pass instead.

The rebuilt `_reloc` is staged to `out/i386/<driver>/` but is not fed to binrecon
as a comparison artifact.

## 5. Sequencing

Ascending difficulty rather than ascending size, one driver carried all the way
through before the next starts.

**Phase 0 — tooling.** Write the four profiles. Write
`vm/build-i386-sound-recon.sh` with a `build_one` line per driver and the four
resulting paths in its closing summary.

*Verify:* `binrecon validate --profile tools/binrecon/profiles/<driver>.json`
prints the reference identity for each of the four with no rebuilt artifact.

**Phase 1 — table pass.** §4.1, all four drivers at once.

*Verify:* the three §4.1 checks.

**Phase 2 — drvBeepSound report pass** (11 hand-written functions). Report pass
per §4.2. The smallest body of code in the effort, and the one where the
reference data is already known to match ours exactly, so it establishes the
`IOAudio` subclass shape — `initFromDeviceDescription:`, `reset`,
`getIntValues:forParameter:count:`, `setIntValues:forParameter:count:`,
`getCharValues:forParameter:count:`, `setCharValues:forParameter:count:`,
`_channelWillAddStream`, `_getSupportedParameters:count:forObject:` — that the
other three reuse. Settles the `+probe:` body and the `assert_wait` sleep
mechanism.

*Verify:* `load_source_map` passes against the reference analysis.

**Phase 3 — drvBeepSound fix pass.** Per §4.3. Write `+probe:`, de-staticise
`_defaultBeepSequences`, move the device name and kind into `__DATA` symbols,
replace `IOSleep` with the reference's thread primitives, and drop the extra
`IOLog`.

*Verify:* the three §4.3 checks.

**Phase 4 — drvSB8Sound report pass** (27 functions). The cleanest starting
point, and it establishes the shared `IOAudio` mixer, DMA and interrupt method
set — `updateInputGain*`, `updateOutputMute`, `updateOutputAttenuation*`,
`startDMAForChannel:read:buffer:bufferSizeForInterrupts:`,
`stopDMAForChannel:read:`, `interruptOccurredForInput:forOutput:`,
`interruptClearFunc`, `timeoutOccurred` — that drvES1x88Sound and drvSB16Sound
both build on.

*Verify:* `load_source_map` passes.

**Phase 5 — drvSB8Sound fix pass.** Per §4.3, including the `_writeToDSP` and
`_readFromDSP` linkage question (§2.4).

*Verify:* the three §4.3 checks.

**Phase 6 — drvES1x88Sound report pass** (23 functions). Confirms that Apple's
binary has no counterpart for the four extra methods before anything is removed.

*Verify:* `load_source_map` passes.

**Phase 7 — drvES1x88Sound fix pass.** Excise the four SB16-derived methods and
their strings (§2.3), and resolve the remaining findings. The excision is
authorised by §4.3 only once Phase 6 has recorded it.

*Verify:* the three §4.3 checks, plus per-function size against the reference.

**Phase 8 — drvSB16Sound report pass** (26 functions, 13572 bytes). The largest
and most divergent. `initializeHardware` and `timeoutOccurred` alone are 44
percent of the reference `__text` — which this phase established is one inlined
`resetHardware()` expansion present in our source, not the invention §2.2 first
read it as.

*Verify:* `load_source_map` passes.

**Phase 9 — drvSB16Sound fix pass.** Fix the IRQ set and the two missing strings
(§2.2), then rewrite whatever Phase 8 confirmed as invented, informed by Phase 4
and Phase 6's worked examples of the shared method set. The `__DATA` mixer
defaults recorded in §2.2 are the target for the initialisation path.

*Outcome:* Phase 8 confirmed nothing as invented, so the rewrite half of this
phase produced no work. The IRQ set, the two missing strings and the `__DATA`
mixer defaults were all resolved finding-by-finding under the ordinary §4.3
discipline.

*Verify:* the three §4.3 checks, plus per-function size against the reference.

**Phase 10 — README.** Update the four `sound` status lines in
`src/drivers-i386/README` to the reconstructed wording the bus drivers use.
drvIntelAC97Sound and drvSB128Sound are left alone.

## 6. Failure modes

**drvSB16Sound and drvES1x88Sound can overfit.** 13572 and 8660 bytes
respectively. A rebuilt function materially larger than its reference
counterpart means we invented structure again. Per-function size against the
reference is the check, as in the Intel and input specs.

*Outcome:* neither driver was rewritten — the §4.3 rewrite authorisation was
never exercised — so the exposure this anticipated never arose. The
per-function size check ran anyway on both, and no function was flagged
`LARGER`.

**`+[Beep probe:]` may not be fully recoverable.** 68 bytes is small enough that
the disassembly should be unambiguous, but if it turns out to depend on an
`IOAudio` or `IODeviceDescription` detail we cannot see, the method still gets
written — a driver without `+probe:` cannot load — and the uncertain part is
recorded in `divergences.md` rather than presented as confirmed.

**Beep's sleep mechanism may not be recoverable from the imports alone.** We know
the reference imports `assert_wait`, `thread_set_timeout`, `thread_block` and
`_hz` and does not import `IOSleep`, which establishes the mechanism but not the
argument computation. If `-[Beep beep]` (444 bytes) does not settle it, the
finding is recorded rather than guessed.

**~~Apple's out-of-line `_writeToDSP` and `_readFromDSP` may not be
reproducible.~~** Retired. This risk rested on the misreading corrected in §2.4:
both functions are already plain `static` in our source and already emit out of
line at Apple's sizes.

**Ghidra may reject these binaries.** Three of the five input drivers aborted
normalization with `Ghidra relocation operand metadata is ambiguous`
(`normalize.py:432`), leaving `complete: false` and no reference consensus. The
cause is specific instruction forms, not scale — `Intel82365PCMCIA` is larger
than `ParallelPort` and normalizes cleanly — so it cannot be predicted from the
sizes in §1.1. Any driver that hits it has Ghidra disabled in its profile and
runs IDA + angr, which the input effort verified produces `complete: true` with a
valid reference consensus. Each affected driver's `divergences.md` states the
reduced analyzer set as a limitation of its evidence.

This is a real weakening: the effort's premise is multi-analyzer corroboration
with disagreement preserved rather than voted away. It is tolerable because IDA
is already authoritative for the function partition by the convention drvPCIBus
established, and angr still supplies an independent second opinion. Fixing
`normalize.py` is the better answer and belongs to its own effort, because ten
already-committed reconstructions depend on that code.

**Analyzer disagreement is preserved, not resolved by majority.** IDA and Ghidra
function discovery are claims, not truth. Conflicting boundaries go to
`boundary_disputed` for human resolution.

**angr `CFGFast` misses on indirect control flow** are recorded as CFG errors,
never read as "function absent". All four drivers dispatch through
`objc_msgSend`, so expect some in every phase.

**A failed or timed-out run** yields `complete: false` and cannot report passing
acceptance. The runner refuses to accept leftover output from an earlier run as
evidence.

**The Rhapsody guest may be unavailable.** The table pass and all four report
passes still deliver in full; only the fix passes block. The table pass is
unverifiable without a build, so it ships as a stated-unverified change if the
guest is down.

**A baseline build may fail for reasons unrelated to us.** None of the four has
been built. Repairing that is separately committed, ahead of the divergence fixes
for that driver.

## 7. Deliverables

Per driver — drvBeepSound, drvSB8Sound, drvES1x88Sound, drvSB16Sound:

- `src/drivers-i386/sound/<driver>/reconstruction/source-map.json`
- `src/drivers-i386/sound/<driver>/reconstruction/ledger.json`
- `src/drivers-i386/sound/<driver>/reconstruction/divergences.md`
- `tools/binrecon/profiles/<name>.json`, where `<name>` is the lower-cased
  reference server name rather than the `drv` directory name — `beep`,
  `soundblaster8`, `es1x88audiodriver`, `soundblaster16` — matching the existing
  `pcibus.json` / `ps2keyboard.json` convention

Repository-wide:

- `vm/build-i386-sound-recon.sh`
- Nine `PB.project` files: root, `.drvproj` and `.lksproj` for drvSB8Sound,
  drvSB16Sound and drvES1x88Sound
- Corrected `Load_Commands.sect` for drvBeepSound, drvES1x88Sound and
  drvSB16Sound
- Table fixes for drvBeepSound, drvSB8Sound and drvSB16Sound's four tables
- `src/drivers-i386/README` status lines updated for all four

Not deliverables: a MicrosoftSound driver, any change to drvIntelAC97Sound or
drvSB128Sound, any change under `src/kernel-7`, an `Unload_Commands.sect` for any
of the four, and any boot test.
