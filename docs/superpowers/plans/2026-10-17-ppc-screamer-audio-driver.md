# PPC Screamer Audio Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a PPC-only Screamer `IOAudio` driver with full-duplex PCM,
controls, automatic routing, and tested power restoration, targeting Sawtooth
first and admitting other machines only with verified resources and wiring.

**Architecture:** A separate `drvPPCScreamer` bundle owns the legacy DriverKit
adapter, with small C modules for discovery, codec transactions, and runtime
state. Compile the existing TAS DBDMA/deadline sources into the new bundle;
Platform Expert owns shared DAVbus clocks, power, and mux exclusion. System
sleep support remains an external prerequisite for physical power acceptance.

**Tech Stack:** Period PPC Objective-C DriverKit, C89, Project Builder
`pb_makefiles`, DBDMA, Open Firmware, existing Platform Expert and APK packaging.

**Spec:** [Approved design](../specs/2026-10-17-ppc-screamer-audio-driver-design.md).

## Global Constraints

- Create `src/drivers-ppc/sound/drvPPCScreamer`, containing one DriverKit kernel-server bundle and one `PPCScreamer : IOAudio` adapter.
- Set `INCLUDED_ARCHS = ppc` in the project's architecture selection and package it using the existing driver-project conventions.
- Do not alter the public SoundKit or DriverKit audio ABI.
- Expose signed 16-bit stereo PCM through the existing `IOAudio` callbacks.
- 44.1 kHz is required.
- Rate changes require both directions to be stopped.
- Reuse the checked-in `PPCDBDMAAudio.c/.h` implementation and its `TASTime` deadline helper from `drvPPCTASAudio` as source inputs to the new bundle, after auditing their contracts for DAVbus use.
- Do not copy the files or move TAS sources into a new framework.
- Do not advertise hot unload or driver replacement.
- Do not copy GPL code, tables, or comments into this driver.
- Do not add i386 support, other codec families, EQ, bass/treble, SRS controls, PCMCIA audio, software rate conversion, QEMU audio emulation, or unrelated audio-framework repairs.
- Never test by modifying `vm/rhap-i386-bootstrapped-v2.img` directly.

## Review Focus

These failure classes get explicit tests in the named tasks:

1. A NUL-separated compatibility list identifies Screamer after its first entry, or conflicts with another codec identity: recognize the former and reject the latter in Tasks 1-2.
2. A physically fragmented period spans multiple descriptors: notify `IOAudio` once per completed period, not once per descriptor, in Tasks 5 and 8.
3. DAVbus is present without a usable KeyWest I2C node, or I2S0 already owns its mux: independent discovery succeeds and conflicting ownership fails without writes in Task 3.
4. A user changes input or rate through inherited private parameter selectors while streaming: rejection must preserve the running hardware and reported state in Task 7.
5. A queued timer/ISR arrives after close or a failed wake: ignore stale work without freeing observed storage or restarting DMA in Tasks 8-9.

## Execution boundaries and repository map

This plan authorizes no implementation until the user reviews it and selects
execution. At execution time follow `AGENTS.md` and the worktree skill; preserve
the checkout's unrelated tracked and untracked work. Do not spawn agents merely
to write/review this plan. Each task ends with its stated tests and a short
subsystem-prefixed commit without metadata. Stage only that task's files.

Paths below are repository-relative. For compact file lists define:

| Alias | Exact directory |
| --- | --- |
| `D` | `src/drivers-ppc/sound/drvPPCScreamer` |
| `L` | `src/drivers-ppc/sound/drvPPCScreamer/PPCScreamer.drvproj/PPCScreamer.lksproj` |
| `T` | `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj` |
| `P` | `src/drivers-ppc/bus/drvPExpert/powermac/chips` |
| `PT` | `src/drivers-ppc/bus/drvPExpert/tests` |
| `A` | `src/drivers-ppc/sound/drvPPCAwacs/PPCAwacs.drvproj/PPCAwacs.lksproj` |

| Files | Responsibility |
| --- | --- |
| `L/ScreamerIdentity.h` | Length-aware, header-only codec classification shared with the AWACS probe. |
| `L/ScreamerCore.h`, `L/ScreamerCore.c` | Immutable property reader/configuration, resource decoding, rates, control quantization. |
| `L/ScreamerProfiles.h`, `L/ScreamerProfiles.c` | Only source-backed wiring/power profiles, with provenance identifiers. |
| `L/ScreamerCodec.h`, `L/ScreamerCodec.c` | MMIO protocol, successful register shadows, calibration and power register sequences. |
| `L/ScreamerRuntime.h`, `L/ScreamerRuntime.c` | Duplex rings, completion-to-period accounting, serialized controls, routing, power, closing. |
| `L/PPCScreamer.h`, `L/PPCScreamer.m` | DriverKit lifecycle, firmware reader, mappings, interrupt/deferred work, parameter and power adapters. |
| `D/tests/Makefile.host`, `screamer_fixtures.h/.c` | C89 test runner and fake firmware/MMIO/time/cache/platform facilities. |
| `D/tests/screamer_identity_test.c`, `screamer_core_test.c`, `screamer_codec_test.c`, `screamer_runtime_test.c` | Component test executables. |
| `D/tests/screamer_adapter_test.m`, `D/tests/check_project.ps1` | Period-runtime adapter tests and Windows metadata/source-path checks. |
| `D/package-source.sh` | Stage a fresh minimal source package preserving sibling shared-source paths for rbuild's isolated project copy. |
| `D/SOURCES.md`, `D/README.md`, `D/VALIDATION.md` | Evidence, operation, and separate test/build/physical acceptance records. |
| `src/kernel-7/machdep/ppc/PEDAVBus.h`, `P/davbus_audio.h/.c` | Narrow public DAVbus service and its injected, testable implementation. |

`T/PPCDBDMAAudio.c` and `T/TASTime.c` are reused, not recreated. `P/keylargo.c`,
`P/keylargo_audio.h/.c`, `P/Makefile`, `P/PB.project`, and `PT/Makefile.host`
receive only the changes needed for DAVbus transport and mux ownership.
`A/PPCSound.m`, its `Makefile.preamble`, and `PB.project` receive the identity
guard/include metadata. No changes to PPC `APM.c` are planned.

## Commands and test harness contract

Run the following commands from the indicated working directory; all task
commands assume a C89 compiler and `gnumake` are on that host's PATH. Windows
may use an existing compatible compiler, or invoke the commands on the
configured Rhapsody build guest. Do not install product dependencies for this
plan. Do not assume that an i386 guest can execute a PPC kernel server.

| Label | Working directory and command | Passing result |
| --- | --- | --- |
| `IDENTITY` | `D/tests`: `gnumake -f Makefile.host identity-test` | All identity assertions pass; exit 0. |
| `CORE` | `D/tests`: `gnumake -f Makefile.host core-test` | Discovery/rate/control assertions pass; exit 0. |
| `CODEC` | `D/tests`: `gnumake -f Makefile.host codec-test` | Register traces/deadlines pass; exit 0. |
| `RUNTIME` | `D/tests`: `gnumake -f Makefile.host runtime-test` | Stream/routing/power assertions pass; exit 0. |
| `ALL` | `D/tests`: `gnumake -f Makefile.host clean test` | All four C executables pass; exit 0. |
| `PLATFORM` | `PT`: `gnumake -f Makefile.host clean test` | Existing tests and new DAVbus tests pass; exit 0. |
| `TAS` | TAS `tests`: `gnumake -f Makefile.host clean test` | Existing codec/runtime suites pass; exit 0. |
| `ADAPTER` | `D/tests`: `gnumake -f Makefile.host adapter-test` | Objective-C adapter assertions pass on period runtime; exit 0. |

The adapter target compiles production adapter code against test substitutes
for DriverKit services, using the period Objective-C compiler/runtime and
fake hardware. Test substitutes live under `D/tests`, never in installed
headers. Keep real `IOAudio.h`, `IOAudioPrivate.h`, `NXSoundParameterTags.h`,
and `IOPower.h` method signatures in the target compilation check.

Task 1 defines `ScreamerFixture` and these test-only operations:
`FixtureInit`, `FixtureSetProperty`, `FixtureSetRange`, `FixtureSetInterrupt`,
`FixtureAdvanceMS`, `FixtureInjectFailure`, `FixtureTraceCount`, and
`FixtureAssertTrace`. Property setters take explicit byte lengths; trace
assertions compare ordered operation kind, address, value, and timestamp.
Fake time advances on sleep/poll operations, and a capped-operation assertion
fails infinite loops. Every executable prints its assertion/failure counts and
returns nonzero on failure. These facilities are extended only when a task
needs them; no general mocking framework.

## Fixed numeric and interface decisions

Core public types use `unsigned int` for 32-bit wire/register values (compile-time
assert `sizeof(unsigned int) == 4`) and `unsigned long` for the reused DBDMA/time
interfaces; explicitly range-check conversions on wider test hosts. Define
`ScreamerStatus` values `kScreamerOK`, `Invalid`, `Unsupported`, `Unresolved`,
`Busy`, `Timeout`, `IOError`, `Fault`, and `Closed`, consistently prefixed
`kScreamer`. Do not reinterpret raw DriverKit or Mach errors as these values.

`ScreamerBytes` is `{ const unsigned char *bytes; unsigned int length; }`.
`ScreamerPropertyReader` has context plus bounded node iteration, parent lookup,
and property lookup callbacks; node IDs are `unsigned int`, with zero invalid.
`ScreamerMachineConfig` contains translated register ranges in controller/out/in
order, the three local interrupt indices and delivered identities, controller
family, rates, and a resolved `ScreamerProfile`. `ScreamerControls` contains
left/right attenuation, left/right input gain, input-source tag, and user mute.
`ScreamerStream` is input=0/output=1, matching `PPCDBDMADirection`.
Use `kScreamerStreamInput` and `kScreamerStreamOutput` as its enumerators.
`ScreamerCodec` contains `unsigned int shadow[8]` and a valid-shadow bitmask;
`ScreamerRuntime.streams[2]` each contains a `running` flag, buffer identity,
rate, and period-byte remainder, plus the shared rings/ops described in Task 5.
Define portable `ScreamerPowerState` in `ScreamerCore.h` with
`kScreamerPowerReady`, `kScreamerPowerStandby`, `kScreamerPowerSuspended`,
and `kScreamerPowerOff`. Mach/DriverKit power values are converted only in the
adapter. A read-only `ScreamerReadDescription(IODeviceDescription *,
ScreamerPropertyReader *, ScreamerDeliveredResources *)` is an adapter-local
function returning `ScreamerStatus`; its reader storage remains valid through
discovery, and the final configuration owns any retained property data.

Deadlines are normalized 32-bit milliseconds using `TASTime`; every interval
is below `0x80000000`. Use 1 ms readiness/busy polling, 1000 ms per codec
command/readiness phase, and a 5000 ms overall initialization/wake budget.
These are bounded driver policy limits, not claimed hardware maxima. Preserve
Apple's conservative 750 ms pre-calibration delay, at least 2 ms after asserting
recalibration, and 5 ms run/idle settling where that sequence requires it;
the enclosing deadline includes all delays and must never be refreshed by
retries. Use a 100 ms DMA stop/reset budget. Poll jacks at 250 ms, confirm a
changed sample after at least 5 ms, and invalidate timer generations on power
or close. Tests cover equality, wrap, and unordered half-range deadlines.

The controller offsets are sound control `0x00`, codec command `0x10`, codec
status `0x20`, clipping count `0x30`, and byte swapping `0x40`. Readiness is
status bit 22; codec-command busy is `0x01000000`. Codec commands contain a
12-bit payload and register index shifted by 12. Resolve register fields and
machine port mapping from the pinned references; never derive an input's
physical label from a generic AWACS bit name.

Use native big-endian 16-bit PCM buffers with the controller byte-swap function
disabled; test bytes `12 34 ed cc` as signed samples `0x1234`, `-0x1234`.
MMIO and DBDMA descriptors independently use little-endian access. Rate codes
are 44100:0, 29400:1, 22050:2, 17640:3, 14700:4, 11025:5, 8820:6, 7350:7 in
sound-control bits 8-10. The admitted configuration must include 44100; unknown
or malformed firmware rates do not get rounded. Profiles may supply a missing
rate property only with explicit source evidence, as required by the spec.

## Task 1: Establish identity and auditable hardware evidence

**Files:** Create `L/ScreamerIdentity.h`, `D/tests/Makefile.host`,
`D/tests/screamer_identity_test.c`, `D/tests/screamer_fixtures.h/.c`,
`D/SOURCES.md`, `D/VALIDATION.md`.

**Interfaces:** Produce header-only
`ScreamerIdentity ScreamerClassify(ScreamerBytes model, ScreamerBytes compatible)`;
identity values are `Unknown`, `Screamer`, `Other`, and `Conflict`, prefixed
`kScreamerIdentity`. Bytes/type definitions needed by this header live in it;
`ScreamerCore.h` includes it rather than redeclaring them.

- [ ] **Step 1:** Pin the spec's Apple/BSD references in `SOURCES.md`, plus
  [AppleKeyLargo `KeyLargo.h`](https://github.com/apple-oss-distributions/AppleKeyLargo/blob/d53ef3af164ee7f3323a46f1db01846e233b0f33/KeyLargo.h),
  Apple's `AppleLegacyAudio/AudioHardwarePower.h/.cpp`, and NetBSD's `obio.c`
  at the spec's respective commits. Record symbols for readiness, byte order,
  calibration, FCR/mux, and profile power/port fields. Distinguish active code
  from commented alternatives. Record real firmware dumps if available;
  label constructed fixtures synthetic. Initialize four separate validation
  rows: C tests, PPC build, physical audio, physical power, all not yet run.
- [ ] **Step 2:** Write `classify_compatible_list`, `reject_unterminated_list`,
  `reject_conflicting_codec`, and `reject_prefix_match`. Assert that
  `{'v','e','n','d','o','r',0,'s','c','r','e','a','m','e','r',0}` classifies as
  Screamer; `screamer-extra` does not; `model=screamer` combined with
  `compatible=burgundy` is Conflict; null/zero-length input is Unknown.
  Accept an exact single `model` value with or without one trailing NUL,
  but require terminated entries in a compatibility list.
- [ ] **Step 3:** Run `IDENTITY`; confirm it fails for absent classification,
  then implement the bounded classifier with no allocation or hardware access.
- [ ] **Step 4:** Run `IDENTITY` to exit 0. Review the evidence table for
  Sawtooth routing/power and reject any unsupported assertion. Record the
  existing `APM.c` stub as a physical-power blocker without modifying it.
- [ ] **Step 5:** Stage the listed files; commit `audio: identify Screamer codecs from firmware`.

Representative test assertion (the explicit trailing NUL is part of the list):

```c
ScreamerBytes model = { 0, 0 };
ScreamerBytes list = { (const unsigned char *)"vendor\0screamer\0", 16 };
assert(ScreamerClassify(model, list) == kScreamerIdentityScreamer);
list.length = 15;
assert(ScreamerClassify(model, list) != kScreamerIdentityScreamer);
```

## Task 2: Resolve resources, rates, and machine wiring

**Files:** Create `L/ScreamerCore.h/.c`, `L/ScreamerProfiles.h/.c`,
`D/tests/screamer_core_test.c`; extend fixtures and `Makefile.host`, `SOURCES.md`.

**Interfaces:** Produce
`ScreamerStatus ScreamerDiscover(const ScreamerPropertyReader *, unsigned int candidate, ScreamerMachineConfig *)`,
`ScreamerStatus ScreamerRateCode(const ScreamerMachineConfig *, unsigned int hz, unsigned int *code)`,
and `unsigned int ScreamerQuantize(unsigned int value, unsigned int maximum)`.
`ScreamerProfile` records source ID, machine identity, codec applicability,
input-tag-to-register mapping, output mute/amp operations, jack mask/polarity,
and platform power kind. No arbitrary executable profile callbacks.

- [ ] **Step 1:** Add `resolve_parent_ranges`, `validate_irq_order`,
  `reject_overflow_overlap`, `reject_ambiguous_sound`, `reject_profile_conflict`,
  `rates_are_intersection`, and `controls_saturate`. Assert controller/out/in
  order with distinguishable synthetic addresses; shuffled resources must fail
  validation against the delivered description. Reject truncated cells,
  translation overflow and ambiguous parent chains without writes.
  Assert 44100=>0, 22050=>2, 48000=>Unsupported, and absent 44100=>Unresolved.
- [ ] **Step 2:** Run `CORE` and observe failure; implement discovery using
  bounded properties, parent `ranges`, and delivered interrupt metadata.
  Quantization is `(min(value, maximum) * 15 + maximum / 2) / maximum`, using
  wide intermediates/checked arithmetic and a positive domain maximum;
  output attenuation and gain get their
  own adapter-domain conversions, not the same assumed public scale.
- [ ] **Step 3:** Add Sawtooth and additional profiles only when their complete
  wiring/power facts are evidenced. NetBSD's `use_gpio4` corroborates sense
  mask `0x04`, active value `0x04` for `PowerMac3,1/3,2/3,3`; this fact alone
  does not define their output or power wiring. Test iMac connector differences
  and PowerBook no-parallel-output behavior using fully evidenced fixtures.
  Unknown models require complete supported firmware wiring, not guessed
  profile selection. Record withheld candidate profiles and the precise
  missing evidence in `VALIDATION.md` instead of adding guessed entries.
- [ ] **Step 4:** Run `IDENTITY` and `CORE` to exit 0, including exact 4-byte
  and historical fixed-point rate encodings only where source/fixture evidence
  establishes their interpretation. Assert that the maximum gain maps to 15,
  zero maps to 0, and one-over-maximum saturates without wrapping.
- [ ] **Step 5:** Stage the listed files; commit `audio: resolve Screamer resources and wiring`.

Representative assertions, with a valid fixture configuration containing 44100:

```c
assert(ScreamerRateCode(&config, 44100U, &code) == kScreamerOK);
assert(code == 0U);
assert(ScreamerRateCode(&config, 48000U, &code) == kScreamerUnsupported);
assert(ScreamerQuantize(32769U, 32768U) == 15U);
```

## Task 3: Add independent DAVbus platform control

**Files:** Create `src/kernel-7/machdep/ppc/PEDAVBus.h`,
`P/davbus_audio.h/.c`, `PT/pe_davbus_test.c`; modify `P/keylargo.c`,
`P/keylargo_audio.h/.c`, `P/Makefile`, `P/PB.project`, `PT/Makefile.host`.

**Interfaces:** Public
`kern_return_t PEDAVBusGetInfo(unsigned int controllerBase, PEDAVBusInfo *info)`
and `kern_return_t PEDAVBusSetState(unsigned int controllerBase, PEDAVBusState state)`.
States: `kPEDAVBusOff`, `kPEDAVBusReady`; info reports family and availability,
not raw writable register addresses. Internal
`kern_return_t PEDAVBusSetStateCore(const PEDAVBusTransport *, PEDAVBusState)`.
Transport contains verified base/family, feature read/write, barrier,
lock/unlock, interrupt-context and validity callbacks, and shared mux-owner
storage. `PEDAVBusBindTransport` is Platform Expert internal.

- [ ] **Step 1:** Add `davbus_without_i2c`, `mux_conflict_no_writes`,
  `preserve_unrelated_bits`, `reject_wrong_controller`, and
  `reject_interrupt_context` tests. Seed IDE/USB/unrelated feature bits and
  assert they survive every transition. Claiming DAVbus while I2S0 owns the
  mux returns an existing appropriate Mach error; neither owner changes.
- [ ] **Step 2:** Run `PLATFORM` to see the absent service fail. Implement the
  KeyLargo backend, using its verified FCR1 offset `0x3c`, audio-clock bit 3,
  clock-output bit 5, cell bit 6, audio-select bit 7, and 22-MHz-select bit 1.
  The software sequence is: under the common lock reject active I2S0 hardware
  or ownership; save the audio-owned FCR1 bits; clear 22-MHz selection and
  external clock-output enable; select audio; enable its clock; enable its
  cell, using a barrier/readback after each changed write. Off disables the
  cell before its clock, then restores saved selection/output bits before
  releasing ownership. Retain a failed transition's owner and report failure.
  Task 1 must corroborate this sequence before hardware execution; if sources
  do not establish a safe sequence for a variant, keep that backend unavailable.
  Preserve shared FCR3 oscillator bits and unrelated I2S cells. A variant reusing these bits
  for USB, including Intrepid, must not take this backend.
- [ ] **Step 3:** Initialize the common mac-io context and lock after valid
  mac-io discovery, bind DAVbus independently, then attempt KeyWest discovery.
  Keep KeyWest unavailable if I2C discovery fails while retaining usable
  DAVbus control. Add a shared `audioMuxOwner` pointer to the injected
  KeyLargo transport; production points it at the common locked owner value.
  `PEI2SSetCellStateCore` claims/releases I2S0 ownership under that same lock
  and rejects a DAVbus conflict. DAVbus releases ownership only after a
  successful off transition. Null pointers in legacy test transports mean
  no competing consumer; production requires owner storage.
- [ ] **Step 4:** Run `PLATFORM` and `TAS` to exit 0. Add the reverse conflict
  test (DAVbus owner blocks I2S0), harmless I2S1 transitions, malformed I2C
  discovery, failed binding, and idempotent on/off. Unsupported mac-io families
  report unavailable; a Heathrow/Paddington profile stays withheld until a
  separate evidenced backend exists, rather than using KeyLargo bit meanings.
- [ ] **Step 5:** Stage the listed files; commit `PExpert: control DAVbus without I2C dependencies`.

The injected transport exposes an ordered write trace; the conflict case pins
both the status and the absence of writes:

```c
assert(PEDAVBusSetStateCore(&transport, kPEDAVBusReady) == KERN_RESOURCE_SHORTAGE);
assert(write_count == 0U);
assert(mux_owner == kPEAudioMuxI2S0);
```

Use `KERN_RESOURCE_SHORTAGE` consistently for mux ownership conflicts and
`KERN_INVALID_ARGUMENT` for an invalid state/controller; unbound transport
returns `KERN_FAILURE`. Define the shared owner values none/I2S0/DAVbus in
`davbus_audio.h`, prefixed `kPEAudioMux`.

## Task 4: Implement bounded codec operations

**Files:** Create `L/ScreamerCodec.h/.c`, `D/tests/screamer_codec_test.c`;
extend fixtures, host makefile and `SOURCES.md`.

**Interfaces:** `ScreamerCodecOps` supplies context, `readLE32`, `writeLE32`,
barrier, normalized `nowMS`, and `sleepMS` callbacks. Produce
`ScreamerStatus ScreamerCodecWrite(ScreamerCodec *, unsigned int reg, unsigned int payload, unsigned long deadline)`,
`ScreamerStatus ScreamerCodecRead(ScreamerCodec *, unsigned int reg, unsigned int *payload, unsigned long deadline)`,
`ScreamerStatus ScreamerCodecInitialize(ScreamerCodec *, const ScreamerMachineConfig *, unsigned long deadline)`,
and `ScreamerStatus ScreamerCodecSetPower(ScreamerCodec *, ScreamerPowerState, unsigned long deadline)`.
Keep platform power requests outside the codec; this last function changes
codec power registers only. Portable codec code does not include Mach headers.

- [ ] **Step 1:** Write `wait_ready_before_write`, `busy_never_clears`,
  `readback_twice`, `calibration_deadline_includes_delay`,
  `shadow_commits_only_after_success`, and `pcm_endian_is_independent`.
  For a write to register 4 of `0x03cf`, assert command `0x43cf` at offset
  `0x10`, with the little-endian byte image; assert no command before ready.
  Busy held until 1000 ms returns Timeout with the old shadow intact.
- [ ] **Step 2:** Run `CODEC` to confirm failure. Implement readiness and busy
  deadlines using the common policy above, including the two-command readback
  protocol through register 7. Do not use guessed object offsets or depend on
  the reconstructed AWACS global instance.
- [ ] **Step 3:** Implement muted initialization/restoration for registers
  0,1,2,4,5,6,7 as applicable, loop-through disabled, source-backed input and
  output mappings, calibration, and shadow preservation. Tests assert 750 ms
  pre-calibration and at least 2 ms settling fit inside the same 5000 ms budget;
  half-range deadlines fail closed. Never copy the obsolete commented
  fixed-1000-ms calibration body instead of the active readiness sequence.
- [ ] **Step 4:** Run `CODEC` and `CORE` to exit 0, with ready-at-deadline,
  missing-ready, register/payload bounds, failure during register restoration,
  and sample-byte tests. Add contract assertions to each fake MMIO callback
  so use in simulated interrupt context fails the test.
- [ ] **Step 5:** Stage the listed files; commit `audio: implement bounded Screamer codec transactions`.

Representative failure assertions, with a fake codec whose busy bit stays set:

```c
assert(ScreamerCodecWrite(&codec, 4U, 0x03cfU, 1000UL) == kScreamerTimeout);
assert(codec.shadow[4] == previous_shadow);
assert(now_ms == 1000UL);
```

## Task 5: Implement duplex streaming with reused DBDMA

**Files:** Create `L/ScreamerRuntime.h/.c`,
`D/tests/screamer_runtime_test.c`; extend `D/tests/Makefile.host` and fixtures.
Modify `T/PPCDBDMAAudio.c/.h` only if a reproducible contract defect requires it.

**Interfaces:** Runtime holds validated configuration, codec, two rings and
`PPCDBDMAOps`, logical stream state, byte-to-period remainders, and power state.
Produce
`ScreamerStatus ScreamerRuntimeInitialize(ScreamerRuntime *, const ScreamerMachineConfig *, const ScreamerRuntimeOps *, unsigned long deadline)`,
`ScreamerStatus ScreamerStart(ScreamerRuntime *, ScreamerStream, void *buffer, unsigned long bytes, unsigned long period, unsigned int hz, unsigned long deadline)`,
`ScreamerStatus ScreamerStop(ScreamerRuntime *, ScreamerStream, unsigned long deadline)`,
and `ScreamerStatus ScreamerCaptureCompletions(ScreamerRuntime *, ScreamerStream, unsigned int *periods)`.
Runtime ops contain codec/platform access, two DMA operation sets, and platform
resource ownership; later tasks extend the same named structure.

- [ ] **Step 1:** Add `duplex_matching_rate`, `second_rate_preserves_first`,
  `stop_one_direction`, `fragmented_period_one_notification`,
  `cache_before_handoff`, and `stop_timeout_retains_storage`. A 4096-byte
  period fragmented into 1024+3072 bytes yields zero periods after the first
  descriptor and one after the second. Assert bytes/period counts over two
  ring wraps and multiple completed periods in one service call.
- [ ] **Step 2:** Run `RUNTIME` to confirm failure. Compile the actual shared
  `T/PPCDBDMAAudio.c` and `T/TASTime.c` using relative source paths; from `L`
  the directory is `../../../drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj`.
  From `D/tests` it is `../../drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj`.
  Do not copy or wrap the sources with textual `.c` includes.
- [ ] **Step 3:** Use `PPCDBDMABuildRing`, `StartRing`, `StopRing`,
  `ServiceCompletions` and the existing storage/scratch contract. Convert
  completed bytes into framework periods, carrying the remainder; never use
  `completion.descriptors` as a period count. Start only after config/rate,
  mapping, buffer/period divisibility, 32-bit addressability and cache checks
  succeed. Shared-clock failure faults both directions; direction-local stop
  preserves the peer. Do not release storage when inactivity cannot be proved.
- [ ] **Step 4:** Run `RUNTIME` and `TAS` to exit 0. Add translation failure,
  >65535-byte span splitting, ring-storage overflow, 16-byte misalignment,
  invalid residual count, spurious completion, DEAD status, and callback failure
  tests. Reuse existing helper coverage instead of repeating its implementation.
- [ ] **Step 5:** Stage the listed files; commit `audio: stream Screamer PCM through DBDMA`.

Representative assertions after the fixture has started both directions at
44100 and injected 1024 then 3072 completed bytes of a 4096-byte output period:

```c
assert(ScreamerCaptureCompletions(&runtime, kScreamerStreamOutput, &periods) == kScreamerOK);
assert(periods == 0U); /* after the first fragment */
/* Inject the second completion before the next call. */
assert(ScreamerCaptureCompletions(&runtime, kScreamerStreamOutput, &periods) == kScreamerOK);
assert(periods == 1U);
assert(ScreamerStop(&runtime, kScreamerStreamInput, deadline) == kScreamerOK);
assert(runtime.streams[kScreamerStreamOutput].running);
```

## Task 6: Serialize controls and automatic routing

**Files:** Modify `L/ScreamerRuntime.h/.c`, `L/ScreamerCodec.h/.c`,
`D/tests/screamer_runtime_test.c`, fixtures.

**Interfaces:** Produce
`ScreamerStatus ScreamerApplyControls(ScreamerRuntime *, const ScreamerControls *, unsigned long deadline)`,
`ScreamerStatus ScreamerObserveJack(ScreamerRuntime *, unsigned int sense, unsigned long nowMS, unsigned long generation)`,
`ScreamerStatus ScreamerServiceDeferred(ScreamerRuntime *, unsigned long deadline, unsigned int periods[2])`.
Runtime exposes desired/applied controls, pending sense/generation, and
per-direction pending framework periods; the adapter owns locking.

- [ ] **Step 1:** Add `unsupported_input_unchanged`, `mute_switch_unmute_order`,
  `jack_bounce_no_route`, `user_mute_survives_insert`, and
  `partial_control_write_reports_truth`. A changed sense at 100 ms and a
  matching sense at 104 ms must not route; at 105 ms it may route. A stale
  generation cannot change outputs. Verify profile-specific active-low sense.
- [ ] **Step 2:** Run `RUNTIME` to confirm failure, then implement transaction
  planning against the resolved profile. Preserve unaffected register bits;
  clear loop-through and unused routes rather than exposing speculative
  controls. Quantize once and keep successful shadows distinct from desired
  values. A partially committed, uncertain route faults/mutes affected paths;
  do not claim that software rollback undid successful hardware writes.
- [ ] **Step 3:** Implement the 250 ms fallback poll and >=5 ms confirmation
  decision as scheduled work requests, not sleeps inside the ISR. Reliable
  port-change interrupts also use deferred confirmation. A jack switch honors
  profile power/anti-pop settling before unmute, the same deadline, and the
  user mute flag; it does not alter the selected recording input.
- [ ] **Step 4:** Run `RUNTIME`, `CODEC`, `CORE` to exit 0. Test each profile's
  exposed connector, independent left/right levels, insertion/removal during
  playback/capture, failed amplifier operations, and controls arriving while
  suspended/closing. No inaccessible connector or phantom input is advertised.
- [ ] **Step 5:** Stage the listed files; commit `audio: route Screamer outputs and apply controls`.

The runtime test's fake output trace must also assert:

```c
assert(route_write_time_ms >= first_changed_sample_ms + 5UL);
assert(runtime.applied.userMuted == 1); /* insertion must preserve user mute */
assert(unmute_write_count == 0U);
```

## Task 7: Build the DriverKit adapter and exclusive probe

**Files:** Create `L/PPCScreamer.h/.m`, `D/tests/screamer_adapter_test.m`,
`D/tests/check_project.ps1`; modify `A/PPCSound.m`, `A/Makefile.preamble`,
`A/PB.project`. Create the new project's `Makefile`, `Makefile.preamble`,
`Makefile.postamble` at `D`, `D/PPCScreamer.drvproj`, and `L`; create
`PB.project` metadata at all three levels, `Default.table` and `DriverInfo`
under the `.drvproj`, `L/Load_Commands.sect`, help resources and
`D/apk/pkginfo`. Extend the test makefile. Reuse TAS project conventions,
not its stale `dpkg/control` entry or duplicated `Server Name` setting.

**Interfaces:** Produce `PPCScreamer : IOAudio <IOPower>`, implementing
`+probe:`, `-reset`, the exact `IOAudio.h` start/stop/format/control selectors,
and private parameter selectors with the signatures in `IOAudioPrivate.h`:
`-_setParameter:toInt:forObject:`, `-_intValueForParameter:forObject:`,
`-_getSupportedParameters:count:forObject:`, and `-_getValues:count:forParameter:forObject:`
only where required to constrain the inherited defaults. The last returns
`BOOL`, takes `NXSoundParameterTag *`, `unsigned int *`, `NXSoundParameterTag`,
and `id`, respectively. `ScreamerReadDescription` converts the matching `IOTreeDevice` and its
property table into `ScreamerPropertyReader` plus delivered resource metadata;
it must identify the candidate by exact device path, not the first sound node.

- [ ] **Step 1:** Add adapter tests `both_probe_orders_one_owner`,
  `failed_probe_no_writes`, `failed_gain_readback`, `unknown_input_no_change`,
  `running_rate_rejected`, and `advertised_controls_match_profile`. Exercise
  the real selector path through an `IOAudio` test double and fake hardware;
  assert bool parameter setters return NO on rejection and readback retains
  applied values after a failed codec write. Include multi-entry compatibility
  and unrelated controller nodes.
- [ ] **Step 2:** Run `ADAPTER` to see the missing adapter fail, then implement
  read-only validation, lock/owner reservation, correct physical mappings,
  DMA ops, and source-backed platform readiness checks before superclass
  activation. Include the shared classifier in AWACS by an explicit relative
  include path; walk the same controller/sound identity relationship and
  reject Screamer/Conflict before AWACS allocation or MMIO. AWACS must still
  accept its legacy identity. No runtime dependency between the bundles.
- [ ] **Step 3:** Implement framework parameter conversion through existing
  getters/private selectors, never by offsets into `self` or direct access to
  private superclass ivars. Rates are `NX_SoundStreamSamplingRate` on stream
  objects, not a nonexistent device sampling-rate tag. Validate stream
  rate/encoding/channel requests and changes to the device's active format
  before calling inherited setters. Intercept only the hardware parameters;
  preserve superclass behavior for unrelated channel/stream parameters.
  A void control callback logs a failed application and restores reported
  state through supported selectors/overrides; it cannot invent a return value.
- [ ] **Step 4:** Wire Project Builder/make source lists to the two shared
  sources and headers. Use class `PPCScreamer`, driver `PPCScreamer`, server
  `drvPPCScreamer`, table nomination `awacs davbus`, installed bundle
  `PPCScreamer.config`, and package `drvppcscreamer`. Include `SMAP audio0
  audioMessages 0`, `ADVERTISE audio0`, `WIRE` like TAS. Keep `Server Name`
  generation consistent with current driver builds. Add `arch = ppc-apple-rhapsody`
  to `apk/pkginfo` so rbuild's ordinary universal default cannot select i386.
  Run `ADAPTER`, `ALL`, and
  `powershell -File D/tests/check_project.ps1` (expand `D`); expect exit 0,
  all declared source paths existing and PPC-only metadata. Do not load the
  unfinished bundle; interrupt/power integration follows.
- [ ] **Step 5:** Stage the listed files; commit `audio: attach the PPC Screamer DriverKit bundle`.

The Objective-C failure test must exercise inherited parameter dispatch:

```objective-c
assert([device _setParameter:NX_SoundStreamSamplingRate
                       toInt:48000 forObject:inputStream] == NO);
assert([inputStream samplingRate] == 44100U);
assert([device sampleRate] == 44100U);
assert([device _intValueForParameter:NX_SoundDeviceAnalogInputSource
                         forObject:inputChannel] == previous_input);
```

Also start a supported second stream at a rate different from the running
peer and assert that negotiation/start fails without changing the peer's
reported rate, clock, or DMA state.

## Task 8: Connect interrupts, cache ownership, and deferred service

**Files:** Modify `L/PPCScreamer.h/.m`, `L/ScreamerRuntime.h/.c`,
`D/tests/screamer_adapter_test.m`, `D/tests/screamer_runtime_test.c`.

**Interfaces:** Adapter `-getHandler:level:argument:forInterrupt:` uses the
validated local indices for codec/output/input. Match `IODirectDevice.h`:
handler and level output pointers, `unsigned int *argument` containing the
32-bit instance address, and `unsigned int localInterrupt`. Return NULL from
`-interruptClearFunc`; direction handlers own source acknowledgement.
`-interruptOccurredForInput:forOutput:` drains pending per-direction period
counts through `ScreamerServiceDeferred`. Provide `screamer_now_ms`,
`screamer_publish`, `screamer_invalidate`, and `screamer_barrier` callbacks
with the existing `PPCDBDMAOps` signatures.

- [ ] **Step 1:** Add `codec_irq_ack_once`, `dma_irq_ack_once`,
  `isr_never_sleeps`, `two_periods_two_services`, and
  `deferred_after_close_ignored`. Script a coalesced output IRQ with two
  completed periods and one input period; require exactly two output services
  and one input service, independent of descriptor count.
- [ ] **Step 2:** Run `ADAPTER` to confirm failure. Establish lock order:
  task paths take `operationLock` then short `stateLock`; raw ISRs take only
  `interruptLock`. Task code may briefly take `interruptLock` after operation
  lock to detach pending status, but releases it before cache ranges or codec
  waits. Timer bookkeeping never holds its owner lock while acquiring the
  operation lock. Timer callbacks schedule work, not codec transactions.
- [ ] **Step 3:** Bind actual `IOPhysicalFromVirtual`, `flush_cache_v`, and
  `invalidate_cache_v` contracts. Allocate each descriptor ring as its own
  page using `kmem_alloc_wired(kernel_map, &address, PAGE_SIZE)`; verify its
  physical extent and 32-bit address before exposure. Clean/invalidate that
  private page and remap the same kernel address with
  `pmap_enter_cache_spec(kernel_pmap, address, physical, VM_PROT_READ | VM_PROT_WRITE,
  TRUE, cache_disable)` before writing descriptors. Use only that inhibited
  mapping and an ordinary separate scratch allocation. Do not create a cached
  alias. Free a proven-unobserved ring using
  `kmem_free(kernel_map, address, PAGE_SIZE)`, which removes the VM mapping;
  do not modify heap-shared pages. Build-check the needed existing VM/pmap
  exports rather than silently falling back to cached descriptors.
  Publish clean playback/descriptor data before DMA ownership; invalidate
  completed capture/status ranges before CPU reads. Respect cache-line
  ownership when CPU and DMA descriptors share a line: descriptor callbacks
  use ordering barriers on the inhibited mapping, while audio buffers use real
  cache operations. Never flush a stale cached adjacent DMA result.
  Inspect `src/kernel-7/machdep/ppc/cache.s` instead of treating `eieio` as
  a replacement. Use descriptor bytes/remainders to service complete periods.
- [ ] **Step 4:** Implement W1C codec port-change/error acknowledgement while
  preserving configured sound-control bits. Audit `mpic.c` and `IODBDMA.m`
  to assign controller EOI versus device-source handling exactly once; do not
  assume a channel-status read universally acknowledges DBDMA. Use bounded
  deferred notifications, monotonic generation/token ownership and pending
  counts that cannot be lost to concurrent IRQs. Run `ADAPTER`, `ALL`, and
  `PLATFORM` to exit 0, including bad local index, coalesced IRQ, immediate
  completion, timer cancellation, reentrant callback and counter-overflow tests.
- [ ] **Step 5:** Stage the listed files; commit `audio: service Screamer interrupts and cache handoffs`.

Keep the following runtime adapter assertions in the coalesced IRQ test:

```c
assert(output_framework_services == 2U);
assert(input_framework_services == 1U);
assert(device_source_acks == 1U);
assert(codec_writes_in_isr == 0U);
```

## Task 9: Implement power restoration and safe close

**Files:** Modify `L/ScreamerRuntime.h/.c`, `L/PPCScreamer.h/.m`,
`D/tests/screamer_runtime_test.c`, `D/tests/screamer_adapter_test.m`,
`D/VALIDATION.md`.

**Interfaces:** Produce
`ScreamerStatus ScreamerSetPower(ScreamerRuntime *, ScreamerPowerState, unsigned long deadline)`
and `ScreamerStatus ScreamerBeginClose(ScreamerRuntime *, unsigned long deadline)`.
Power states distinguish ready/standby/suspended/off; lifecycle additionally
tracks uninitialized/faulted/closing. Adapter implements the four `IOPower.h`
methods, rejects unknown states and returns IO errors without updating its
reported PM state on failure. `-free` returns the retained object once worker
publication makes destruction unsafe.

- [ ] **Step 1:** Add `suspend_stops_before_clocks`, `wake_muted_restore_order`,
  `wake_rebuilds_current_buffers`, `wake_failure_never_restarts`,
  `close_with_queued_timer`, and `super_init_failure_retains_observed_object`.
  Assert standby/suspend/off preserve desired controls; DMA stop timeout
  prevents clock removal. A wake after a jack change reevaluates the route
  before unmute, with unchanged user volume and recording source.
- [ ] **Step 2:** Run `RUNTIME` and `ADAPTER` to observe failure. Implement
  quiesce, bounded codec sleep, platform off, and ready restoration under the
  established lock order. Advance generation before draining/cancelling timers.
  Retain buffer ownership tokens and restart only streams whose framework
  buffer/lifetime still matches; otherwise report stopped, never reuse a
  saved hardware command pointer.
- [ ] **Step 3:** Implement phased cleanup with an acquisition/publication
  record. Before any worker observes the object, unwind in reverse order;
  after attempted superclass initialization, conservatively retain the object,
  locks, callback owner and potentially observed DMA storage until proven safe.
  If hardware cannot be stopped, preserve its mappings/storage and ownership.
  Closing and faulted callbacks do not restart hardware; reject reprobe until
  reboot when retaining the instance.
- [ ] **Step 4:** Run `ALL`, `ADAPTER`, `TAS`, `PLATFORM` to exit 0. Include
  PM_READY twice, invalid PM state, close during an interrupt/deferred callback,
  partial map/allocation/init failures, and each wake-phase failure. Record the
  platform PM stub check separately: manual callback tests pass driver-local
  behavior but cannot pass physical sleep/wake. Do not implement system PM.
- [ ] **Step 5:** Stage the listed files; commit `audio: restore Screamer state across power transitions`.

Representative failed-wake assertions after injecting a readiness timeout:

```c
assert(ScreamerSetPower(&runtime, kScreamerPowerReady, deadline) == kScreamerTimeout);
assert(!runtime.streams[kScreamerStreamInput].running);
assert(!runtime.streams[kScreamerStreamOutput].running);
assert(dma_starts_after_failure == 0U);
```

## Task 10: Verify target builds, source packaging, and ownership regressions

**Files:** Create `D/README.md`; update `D/VALIDATION.md`, `D/SOURCES.md`,
`D/tests/check_project.ps1` and only project/packaging files exposed by actual
build failures. Include the adapter test's `.m` file, fixture files and makefile
in `OTHERSRCS`; `adapter-test` is a make target, not a source file.
Create `D/package-source.sh` for the staging contract below.

**Interfaces:** Deliver one PPC kernel-server bundle with all planned callbacks,
the installed Platform Expert service symbols, and a reproducible package.
Record artifact SHA-256, toolchain identity, and exact build/test commands.
The portable shell command `sh package-source.sh SOURCE_ROOT EMPTY_OUTPUT_DIR`
accepts the repository's `src` directory and a new/nonexistent staging path.
It rejects an existing nonempty output and never deletes the source tree.

- [ ] **Step 1:** Run the full C/adapter/regression commands. From repository
  root run `powershell -File src/drivers-ppc/sound/drvPPCScreamer/tests/check_project.ps1`.
  Extend that check to reject missing external source inputs, accidental i386
  selection, copied DBDMA sources, wrong table names, and obsolete dpkg paths.
  Test source staging into a fresh temporary directory: hashes and relative
  source paths match, a second run into nonempty output is rejected, and the
  original source files are byte-identical afterward. Reproduce the missing
  sibling failure in an isolated direct-project copy before adding staging.
- [ ] **Step 2:** Resolve the configured guest `RemoteRoot` without printing
  credentials. Sync with `powershell -File vm/rhap-vm.ps1 sync`; on the guest,
  `cd` to that root's `src` directory. Run `gnumake installhdrs
  DSTROOT=/tmp/screamer-dst` in `kernel-7`, then build `bus/drvPExpert`,
  `sound/drvPPCScreamer`, and the changed `sound/drvPPCAwacs` with
  `gnumake clean` followed by `gnumake RC_ARCHS=ppc`. Use the installed/staged
  headers consistently through the configured `NEXT_ROOT`; record the value.
  These are period PPC toolchain builds, not Windows syntax checks.
- [ ] **Step 3:** Inspect bundle relocatables with period `lipo -info`,
  `otool -hv`, and `nm`. Expected: PPC Mach-O only; `PPCScreamer` selectors
  and generated glue present; `PEDAVBusGetInfo`/`PEDAVBusSetState` resolved
  against Platform Expert and installed headers. Stage a source package with
  the driver under `drivers-ppc/sound/drvPPCScreamer` and the four canonical
  shared `.c/.h` inputs under their original sibling TAS path. Copy driver
  metadata to the staging root's `apk/pkginfo`; generate a small root makefile
  forwarding `all`, `installhdrs`, `install`, `clean` to the driver's aggregate,
  rebasing only `SRCROOT` to its nested directory and preserving other builder
  flags. This is ordinary generated build staging; no source copies are
  checked into `D`, and no rbuild changes are needed. Verify the staged helper
  hashes against their canonical inputs and build after hiding the original
  checkout from the build environment. No loaded TAS driver is required.
- [ ] **Step 3a:** In the guest shell set `SCREAMER_SOURCE` to the synced
  `src` directory and `SCREAMER_REPOSITORY` to the configured seed APK
  repository, without exposing credentials. Use a fresh numbered directory
  under `/tmp/screamer-acceptance` for each run; set `SCREAMER_RUN` to it.
  Run the following commands separately (exit 0 is required for each):

  ```sh
  sh "$SCREAMER_SOURCE/drivers-ppc/sound/drvPPCScreamer/package-source.sh" "$SCREAMER_SOURCE" "$SCREAMER_RUN/drvPPCScreamer-1"
  rbuild buildpackage --state "$SCREAMER_RUN/state" --arch ppc --toolchain "$SCREAMER_SOURCE/rbuild-1/toolchains/gcc-darwin-ppc.conf" --dir "$SCREAMER_RUN/drvPPCScreamer-1" "$SCREAMER_REPOSITORY" "$SCREAMER_RUN/packages"
  ```

  Expected: a `drvppcscreamer` PPC APK containing one config bundle. Attempt
  `--arch i386` using different state/output directories; expect rejection
  of the explicitly PPC source before an i386 compile. Archive the source
  staging tree to establish reproducibility of the external build inputs.
- [ ] **Step 4:** Run the real adapter tests on the period runtime. Check both
  load orders with AWACS, plus existing AWACS, Burgundy and TAS nomination
  cases. If a required compiler, guest, SDK, linker service, or package tool is
  unavailable, record the exact missing prerequisite and keep target acceptance
  pending; do not substitute a source scan. Run `git diff --check` and inspect
  the diff for unrelated changes. README documents no hot unload and pending
  platform PM rather than implying full machine support.
- [ ] **Step 5:** Commit only verified fixes/documentation as
  `audio: verify Screamer PPC build and packaging`.

## Task 11: Record physical acceptance per machine

**Files:** Update `D/VALIDATION.md`, `D/README.md`; add only real capture/log
artifacts under `D/tests/evidence/` when their size and content suit source
control. Large WAV captures stay outside git with path and hash recorded.
Newly evidenced profiles return through Tasks 2-4 and the full regression gates.

**Interfaces:** One record per model/firmware/codec/profile/build hash, with
independent statuses for tests, target build, physical audio, physical power.

- [ ] **Step 1:** On a throwaway test installation of Sawtooth, save firmware
  and device-tree evidence, boot logs, artifact hashes and exactly-one-driver
  attachment results. Follow `AGENTS.md` for guest snapshots, distinct names
  and ports, QMP identity, and clean shutdown. An emulator without Screamer
  hardware cannot satisfy this task.
- [ ] **Step 2:** Run the spec's ten-minute simultaneous 44.1 kHz stereo
  playback/capture test and 100 start/stop cycles. Include independent stream
  stops, every advertised rate, and conflicting duplex rates. Record known
  signal channel order, pitch, audibility, recording integrity, completion
  counts and any timeouts/faults. User-facing hardware passes require actual
  signal evidence, not only increasing interrupt counters.
- [ ] **Step 3:** Check each exposed input, gain, left/right volume endpoint,
  mute, and output connector while idle and streaming. Check user state across
  jack changes. Do not substitute a generic microphone for an input whose
  electrical requirements differ; use the machine's documented input source.
- [ ] **Step 4:** Check whether platform sleep entry, callback delivery and
  resume ordering really work. If so, run ten physical sleep/wake cycles
  covering idle/active streams and jack changes during sleep. If not, mark
  physical power blocked with the platform prerequisite; do not mark full
  release acceptance complete. Repeat the entire per-machine acceptance for
  every additional claimed profile, leaving candidates unvalidated otherwise.
- [ ] **Step 5:** Commit measured results only as
  `audio: record Screamer hardware validation`. If hardware is unavailable,
  record that fact and hand off the checklist without claiming this task or
  full hardware support passed.

## Plan self-review and handoff

Spec coverage: discovery/machine admission => Tasks 1-2; platform ownership =>
Task 3; protocol/timing => Task 4; duplex/cache/period accounting => Tasks 5,8;
controls/routing => Task 6; DriverKit ABI, probe exclusion and packaging =>
Tasks 7,10; power/lifetime/failures => Task 9; measured acceptance => Task 11.
Review Focus cases are assigned to named tests above. All prospective code
remains unimplemented when this planning document is delivered.

Recommended execution is native implementation in this chat: adapter, shared
clock ownership, IRQ accounting and lifecycle depend closely on the same
interfaces. The user may instead select subagent-driven implementation with
per-task independent review. In either case, review the plan before execution;
preserve the explicit external platform-PM and physical-hardware gates.
