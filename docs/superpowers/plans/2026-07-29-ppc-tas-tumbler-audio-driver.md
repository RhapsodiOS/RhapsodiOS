# PowerPC TAS/Tumbler Audio Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a BSD-compatible `IOAudio` driver for Apple PowerPC I2S machines using TAS3001C (Tumbler) and TAS3004 (Snapper), with full-duplex 16-bit stereo PCM, safe routing and power transitions, and shared KeyLargo-family services in Platform Expert.

**Architecture:** A single `drvPPCTASAudio` bundle owns DriverKit/IOAudio lifecycle, I2S format and clock programming, independent input/output DBDMA rings, codec operations, routing, and recovery. Hardware-independent C modules are tested with fake register/I2C/GPIO transports. Platform Expert owns serialized KeyWest I2C, polarity-normalized GPIO, and locked I2S-cell FCR transitions, while a generic MPIC-direct mapping lets firmware-provided later-Mac interrupts reach DriverKit without guessed tables.

**Tech Stack:** C89 and Objective-C for Rhapsody DriverKit, PowerPC DBDMA, flattened Open Firmware device tree, KeyLargo/Pangea/K2 mac-io, ProjectBuilder `pb_makefiles`/`gnumake`, deterministic C host tests, Rhapsody guest builds, BSD/Apple/TI published references.

---

## Global constraints

- Work only in the isolated `codex/ppc-tas-audio` worktree. Do not alter AWACS or Burgundy matching or code.
- All hardware polls take one absolute deadline and return a distinct timeout; there are no unbounded DBDMA, I2C, GPIO, or codec waits.
- An interrupt handler may acknowledge hardware and enqueue/record work only. It may not perform I2C, route changes, debounce, allocations, or Objective-C framework work.
- Failures after an output has been enabled must leave every amplifier muted. Codec shadows change only after the complete bus write succeeds.
- Do not infer addresses, GPIO polarity, IRQs, or routing from model names. Validate firmware properties and decline attach when a required resource is absent or malformed.
- The codec uses I2S/64fs/20-bit slots (`MCR = 0x6a`); the I2S data-word register remains 16-bit stereo (`0x02000200`). Advertise only firmware-listed rates in the codec's 32–48 kHz range that have an exact I2S divisor; 44.1 kHz is mandatory.
- TAS3004 DRC has six data bytes. Avoid the published sample-code mistakes that duplicate RB1 and omit/duplicate later biquad registers.
- Normalize the historical firmware `i2c-address` from even eight-bit form (`0x68`/`0x6a`) to the seven-bit PE API (`0x34`/`0x35`) exactly once; reject odd, invalid, or conflicting forms.
- Production code must remain C89/period-compiler compatible: no C99 declarations in `for`, designated initializers, `//` comments, VLAs, or compiler atomics.
- Commit messages are short and subsystem-prefixed. Do not add metadata trailers.

## Verification primitives

`HOST-TEST` runs the dependency-free tests in the configured Rhapsody guest (the Windows host has no C compiler):

```powershell
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/sound/drvPPCTASAudio/tests && gnumake -f Makefile.host clean test"
```

Expected final line: `tas_audio_test: all tests passed`.

`PEXPERT-TEST` runs the pure Platform Expert state-machine tests:

```powershell
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/bus/drvPExpert/tests && gnumake -f Makefile.host clean test"
```

Expected final line: `pe_keylargo_test: all tests passed`.

`TARGET-BUILD` requires the period PPC-capable toolchain on a case-sensitive filesystem:

```powershell
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake installhdrs DSTROOT=/tmp/tas-dst"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/bus/drvPExpert && gnumake clean && gnumake"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/sound/drvPPCTASAudio && gnumake clean && gnumake"
```

Expected: the Platform Expert kernel server and `PPCTASAudio_reloc` compile and link for `ppc` with no undefined PE symbols. If the configured guest lacks the PPC toolchain, record this separately from host-test results; do not call it a product failure.

`STATIC-CHECK`:

```powershell
rg -n "SMAP audio0 audioMessages 0|ADVERTISE audio0|WIRE|Server Name|Class Names" src/drivers-ppc/sound/drvPPCTASAudio
rg -n "while[[:space:]]*\(|for[[:space:]]*\(" src/drivers-ppc/bus/drvPExpert/powermac/chips/keylargo.c src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj
rg -n "PEKeyWestI2CTransfer|applyRoute|debounce" src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PPCTASAudio.m
```

Expected: bundle metadata has all required declarations; every polling loop found by the second command is visibly deadline-bounded; no I2C, routing, or debounce call is reachable from the interrupt callback.

---

## Task 1: Add firmware-driven MPIC interrupt identities

Later KeyLargo-family GPIO interrupts currently disappear because reserved physical MPIC sources map to logical device `-1`. Add a direct logical namespace without changing established Sawtooth device mappings.

**Files:**

- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/interrupts.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/chips/mpic.c`
- Create: `src/drivers-ppc/bus/drvPExpert/tests/mpic_direct_test.c`
- Create: `src/drivers-ppc/bus/drvPExpert/tests/Makefile.host`

- [ ] **Step 1: Write the failing direct-map test**

Extract the physical/logical conversion into a pure helper callable by the test. Assert that a legacy mapped source still yields its historical device number, an in-range `-1` entry yields `PMAC_DEV_MPIC_DIRECT_BASE + source`, and out-of-range sources fail.

```c
ASSERT_EQ(17, PEMPIClogicalForSource(map, 64, 40));
ASSERT_EQ(PMAC_DEV_MPIC_DIRECT_BASE + 47,
          PEMPIClogicalForSource(map, 64, 47));
ASSERT_EQ(-1, PEMPIClogicalForSource(map, 64, 64));
```

- [ ] **Step 2: Run the test and observe the expected failure**

Run `PEXPERT-TEST`. Expected: compilation/link failure because the helper and direct base do not exist.

- [ ] **Step 3: Implement the compatibility-preserving mapping**

Define a non-overlapping direct range in `interrupts.h`. In `mpic.c`, make `mpic_int_to_number`, registration, enable, and disable accept direct identities and index the physical source directly. Keep the existing XOR translation only at the old OF compatibility boundary; do not XOR a direct identity.

- [ ] **Step 4: Run `PEXPERT-TEST` and the existing static mappings audit**

Expected: tests pass, and sources 8/9/device 17 retain their existing mapping.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-ppc/bus/drvPExpert/powermac/interrupts.h src/drivers-ppc/bus/drvPExpert/powermac/chips/mpic.c src/drivers-ppc/bus/drvPExpert/tests
git commit -m "drvPExpert: map firmware MPIC sources directly"
```

---

## Task 2: Define and test the Platform Expert audio boundary

Introduce one installed ABI and dependency-free KeyWest/GPIO/FCR engines. Keep hardware constants and MMIO access private to Platform Expert.

**Files:**

- Create: `src/kernel-7/machdep/ppc/PEKeyLargo.h`
- Create: `src/drivers-ppc/bus/drvPExpert/powermac/chips/keylargo_audio.h`
- Create: `src/drivers-ppc/bus/drvPExpert/powermac/chips/keylargo_audio.c`
- Create: `src/drivers-ppc/bus/drvPExpert/tests/pe_keylargo_test.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/Makefile.host`

- [ ] **Step 1: Add failing fake-register tests**

Test KeyWest write/read success, address and data NACK, initially busy controller, timeout at every phase, STOP/cleanup, and serialization. Test both GPIO polarities. Test all three I2S-cell states and preservation of unrelated FCR1 bits.

- [ ] **Step 2: Run `PEXPERT-TEST` and confirm missing interfaces**

Expected: compile failure for `PEKeyWestI2CTransfer`, `PEAudioGPIORead/Write`, `PEI2SSetCellState`, and the transport injection type.

- [ ] **Step 3: Add the installed public API**

`PEKeyLargo.h` includes `<mach/boolean.h>`, `<mach/kern_return.h>`, and `<mach/clock_types.h>` and defines:

```c
typedef enum { kPEKeyWestWrite = 0, kPEKeyWestRead = 1 } PEKeyWestDirection;
typedef struct {
    unsigned int port;
    unsigned char address;
    unsigned char subaddress;
    PEKeyWestDirection direction;
    unsigned char *buffer;
    unsigned int length;
    tvalspec_t deadline;
} PEKeyWestI2CRequest;
typedef struct { unsigned int offset; boolean_t activeHigh; } PEAudioGPIO;
typedef enum {
    kPEI2SCellDisabledReset = 0,
    kPEI2SCellEnabledClockHeld = 1,
    kPEI2SCellRunning = 2
} PEI2SCellState;

kern_return_t PEKeyWestI2CTransfer(const PEKeyWestI2CRequest *request);
kern_return_t PEAudioGPIORead(const PEAudioGPIO *gpio, boolean_t *active);
kern_return_t PEAudioGPIOWrite(const PEAudioGPIO *gpio, boolean_t active);
kern_return_t PEI2SSetCellState(unsigned int cell, PEI2SCellState state);
```

Also define stable PE-specific error returns for NACK, busy, arbitration loss, and timeout so callers can distinguish retryable failures.

- [ ] **Step 4: Implement pure engines over injected operations**

The private transport supplies byte reads/writes, little-endian FCR reads/writes, current time, deadline comparison, and lock hooks. KeyWest shifts the 7-bit API address only when writing the hardware address register. It selects port/mode, clears status/interrupt state, issues address/subaddress/data, always attempts STOP/cleanup, and never polls without checking the request's absolute deadline.

For FCR1, use these documented bit positions: I2S0 interface/clock/reset/cell = 13/12/11/10; I2S1 = 20/19/18/17. State transitions preserve unrelated bits and order reset/clock/cell safely.

- [ ] **Step 5: Run `PEXPERT-TEST`**

Expected: all fake-register traces and error-injection cases pass.

- [ ] **Step 6: Commit**

```bash
git add src/kernel-7/machdep/ppc/PEKeyLargo.h src/drivers-ppc/bus/drvPExpert/powermac/chips/keylargo_audio.h src/drivers-ppc/bus/drvPExpert/powermac/chips/keylargo_audio.c src/drivers-ppc/bus/drvPExpert/tests
git commit -m "drvPExpert: add testable KeyLargo audio services"
```

---

## Task 3: Bind Platform Expert audio services to KeyLargo-family hardware

Discover the mac-io-local KeyWest controller and expose the tested engines through locked production wrappers.

**Files:**

- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/chips/keylargo.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/chips/keylargo.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/chips/Makefile`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/chips/PB.project`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/families/sawtooth.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/pe_keylargo_test.c`

- [ ] **Step 1: Add failing DT/range validation tests**

Cover relative `reg`, absolute `AAPL,address`, non-unit `AAPL,address-step`, malformed property sizes, overflow/out-of-mac-io offsets, invalid port/cell/address/buffer/enum, and calls before initialization.

- [ ] **Step 2: Implement discovery and production operations**

Initialize a singleton from the `device_type=mac-io` node and its relative `i2c` child, not a global first-match `i2c`. Validate every property cell and computed address against the discovered mac-io size. Use the existing BAT/identity `POWERMAC_IO` mapping, byte access for KeyWest/GPIO, and `lwbrx`/`stwbrx` plus `eieio()`/`sync()` for FCR.

Use a sleepable `lock_data_t` across the complete I2C transaction and locked FCR read-modify-write. Do not hold a spin lock through I2C. Reject interrupt-context calls. Leave FCR3 oscillator selection at its firmware setting in this release.

- [ ] **Step 3: Make initialization nonfatal**

Call `PEKeyLargoInitialize()` from `configure_sawtooth()` after installing the MPIC tables. Log one diagnostic and continue boot if discovery fails; the exported functions then return not-ready and TAS probing declines attachment.

- [ ] **Step 4: Correct mac-io size selection from firmware**

Replace the unconditional Heathrow-sized Sawtooth region with validated DT size data so Pangea/K2 offsets are not rejected or overrun. Preserve the existing fallback only for known legacy layouts.

- [ ] **Step 5: Run `PEXPERT-TEST`, `TARGET-BUILD` (Platform Expert portion), and the deadline audit**

Expected: tests pass; production symbols are global; every hardware polling loop is bounded.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-ppc/bus/drvPExpert src/kernel-7/machdep/ppc/PEKeyLargo.h
git commit -m "drvPExpert: bind KeyLargo audio services"
```

---

## Task 4: Scaffold the TAS bundle and validate device-tree configuration

Create the complete bundle shape and a pure immutable configuration parser. Matching is based on codec compatibility plus structural resources, never model-name guesses.

**Files:**

- Create: `src/drivers-ppc/sound/drvPPCTASAudio/Makefile`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/Makefile.preamble`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/Makefile.postamble`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/dpkg/control`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/{Makefile,Makefile.preamble,Makefile.postamble,Default.table,DriverInfo}`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/English.lproj/Localizable.strings`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/{Makefile,Makefile.preamble,Makefile.postamble,PB.project,Load_Commands.sect}`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASCore.h`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASCore.c`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/tests/{Makefile.host,tas_audio_test.c,tas_fixtures.c,tas_fixtures.h}`

- [ ] **Step 1: Copy only the AWACS project structure and rename metadata**

Retain PPC build flags and the load-command contract:

```text
SMAP audio0 audioMessages 0
ADVERTISE audio0
WIRE
```

Set the server/class names to `drvPPCTASAudio`/`PPCTASAudio`. `Default.table` must match I2S audio with `tumbler` or `snapper` codec compatibility and must not overlap `awacs`/`burgundy`.

- [ ] **Step 2: Add failing fixture tests**

Provide TAS3001C and TAS3004 fixtures derived from published DT shapes. Test the three ordered I2S `reg` ranges, codec/output/input interrupt pairs, `platform-tas-codec-ref`, old `/mac-io/i2c/deq` fallback, `0x68`/`0x6a` address normalization, I2C port selection, GPIO phandles and old `audio-gpio` names, GPIO offsets/polarity, and rates. Test that an unknown model with complete structural properties is accepted, while a known model missing a resource is rejected. An absent optional route is valid; a present route missing mute/detect/polarity/interrupt dependencies is not.

- [ ] **Step 3: Implement `TASMachineConfig` parsing**

The parser consumes a small property-reader interface so host tests need no DriverKit. It emits codec kind, I2S cell/range, input/output DBDMA ranges and IRQs, KeyWest address/port, optional detect GPIOs, required amplifier/mux GPIOs, firmware rates, and polarity. Require exact property byte lengths and overflow-safe address arithmetic.

- [ ] **Step 4: Run `HOST-TEST`**

Expected: fixture and rejection tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-ppc/sound/drvPPCTASAudio
git commit -m "drvPPCTASAudio: scaffold bundle and parse firmware"
```

---

## Task 5: Implement exact I2S format and rate selection

Keep sample-rate policy and register encoding pure; MMIO application remains in the Objective-C adapter.

**Files:**

- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASCore.h`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASCore.c`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/tests/tas_audio_test.c`

- [ ] **Step 1: Add failing clock-vector tests**

Assert 44.1 kHz produces an exact supported clock tuple and `0x02000200` data-word format. Cover exact accepted firmware rates in 32–48 kHz and reject approximate divisors, out-of-codec-range rates, rates absent from firmware, and a second full-duplex direction requesting a different active rate.

- [ ] **Step 2: Implement rate intersection and tuple search**

Search only documented KeyLargo clock sources 18.432, 45.1584, and 49.152 MHz and valid divisors, using MCLK = 256fs and SCLK = 64fs. Compare by integer products to avoid rounding; accept only exact equality. Golden tuples are 32 kHz from 49.152 MHz / 6, 44.1 kHz from 45.1584 MHz / 4, and 48 kHz from 49.152 MHz / 4, each with SCLK divisor 4. Guarantee 44.1 kHz or reject the device at probe. Treat input/output as two streams sharing one `activeRate` and reference count.

- [ ] **Step 3: Implement safe I2S programming order**

Produce a register plan that requests and deadline-checks I2S clock stop, then holds the PE cell in `EnabledClockHeld`, writes serial format/frame/data-word/clock registers, barriers, and requests `Running`. A stop timeout produces no format-register writes. On a live rate change, first quiesce both DMA directions and mute outputs.

- [ ] **Step 4: Run `HOST-TEST` and commit**

```bash
git add src/drivers-ppc/sound/drvPPCTASAudio
git commit -m "drvPPCTASAudio: validate and program I2S clocks"
```

---

## Task 6: Implement TAS3001C and TAS3004 codec backends

Use a shared operation table and a commit-on-success shadow cache. Register values are based on TI documentation and cross-checked against Apple/OpenBSD BSD-compatible sources.

**Files:**

- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASCodec.h`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TAS3001C.c`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TAS3004.c`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PB.project`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/Makefile`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/tests/Makefile.host`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/tests/tas_audio_test.c`

- [ ] **Step 1: Add failing register-transport tests**

Verify every register address and width, reset/init order, `MCR=0x6a`, volume/mute/input-gain encoding, complete RB register sequences, and six-byte TAS3004 DRC (five bytes must be rejected). Require each TAS3001 right biquad `0x13..0x18` and TAS3004 right biquad `0x13..0x19` exactly once. Inject failure at every byte/write and assert later writes stop, the shadow remains unchanged, and the caller remains fail-muted. Model successful 49 ms volume and 167 ms tone clock stretching and timeout beyond a 200 ms transfer deadline.

- [ ] **Step 2: Define `TASCodecOps`**

Include codec name, address validation, reset/init, volume, mute, input gain/source, DRC capability, register widths, and restore-from-shadow. The transport callback takes register, byte buffer, length, and absolute deadline.

- [ ] **Step 3: Implement both backends**

Encode multibyte payloads explicitly, never by casting packed structs. Initialize RB0 through the last documented RB register exactly once and in order. With I2S clocks running, apply the codec-specific reset delay (TAS3001C: at least ten MCLK cycles plus 5 ms initialization; TAS3004: 5 ms settle, reset low 20 ms, reset high 10 ms), enter fast load, program all neutral biquads, leave fast load, then program DRC/volume/tone/mixers and TAS3004 analog/MCR2 state. Update each shadow field only after its whole I2C transaction succeeds.

- [ ] **Step 4: Run `HOST-TEST` and commit**

```bash
git add src/drivers-ppc/sound/drvPPCTASAudio
git commit -m "drvPPCTASAudio: add Tumbler and Snapper codecs"
```

---

## Task 7: Build bounded, endian-correct DBDMA rings

Use canonical `IODBDMADescriptor` semantics, not the reconstructed AWACS/Burgundy 0x20-byte layout.

**Files:**

- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PPCDBDMAAudio.h`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PPCDBDMAAudio.c`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PB.project`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/Makefile`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/tests/Makefile.host`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/tests/tas_audio_test.c`

- [ ] **Step 1: Add failing descriptor tests**

Cover 16-byte alignment, big-endian command/address/dependency/result fields, physical-page splits, 16-bit transfer-count limits, ring wrap/branch descriptor, independent input/output rings, completion decoding, and rejection of unmappable or oversized buffers.

- [ ] **Step 2: Implement pure ring construction**

Use a physical-translation callback for every virtually contiguous segment; never translate only the base. Keep each command count within the hardware field. Allocate each descriptor ring within the period contiguous allocator's 4096-byte limit or reject the requested geometry.

- [ ] **Step 3: Implement bounded controller transitions**

Wrap start, stop, flush, and reset using register operations and one deadline. Do not call the canonical `IODBDMAStop/Reset` helpers on power paths because their polling is unbounded. A timeout marks only that direction faulted unless the shared I2S clock is invalid.

- [ ] **Step 4: Run `HOST-TEST` and commit**

```bash
git add src/drivers-ppc/sound/drvPPCTASAudio
git commit -m "drvPPCTASAudio: add bounded full-duplex DBDMA"
```

---

## Task 8: Implement routing, debounce, and power state machines

Make ordering testable before binding it to interrupts and IOAudio controls.

**Files:**

- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASCore.h`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASCore.c`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/tests/tas_audio_test.c`

- [ ] **Step 1: Add failing routing/debounce tests**

Assert: speaker is selected only with no headphone/lineout detect; headphone and lineout may both be selected; user mute wins; a route change mutes all amplifiers before mux/codec changes and unmutes only selected outputs after success. Test bouncing edges, coalescing, stale generations, and no hardware work in the edge callback.

An ANDed-reset topology is enabled only by an explicit parsed machine-profile property/quirk; never infer it from two mute GPIOs. Test that unsupported line-out plus this explicit topology is rejected.

- [ ] **Step 2: Add failing power/failure tests**

For `PM_STANDBY`, `PM_SUSPENDED`, and `PM_OFF`, verify mute → stop/reset both DMA directions → codec low power → hold/reset I2S → disable cell. For `PM_READY`, verify enable/clock → I2S restore → codec restore → route restore → unmute. Inject failure at each stage and assert fail-muted rollback.

- [ ] **Step 3: Implement event-driven state transitions**

The GPIO ISR-facing function records the newest detect bits/generation only. A deferred worker samples after the debounce deadline and applies a route transaction. Power transitions invalidate outstanding generations and serialize with control changes and codec I2C.

- [ ] **Step 4: Run `HOST-TEST` and commit**

```bash
git add src/drivers-ppc/sound/drvPPCTASAudio
git commit -m "drvPPCTASAudio: add safe routing and power states"
```

---

## Task 9: Bind the core to IOAudio and Open Firmware

Add the Objective-C adapter that uses IOAudio's lifecycle and deferred interrupt thread without duplicating framework behavior.

**Files:**

- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PPCTASAudio.h`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PPCTASAudio.m`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PB.project`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/Makefile`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/tests/tas_audio_test.c`

- [ ] **Step 1: Add adapter failure-contract tests**

Through fake ops, cover probe decline, initialization failure after each acquisition, channel start/stop in either order, concurrent full duplex at one rate, conflicting-rate rejection, input/output DMA faults, control write failure, and reset/recovery.

- [ ] **Step 2: Implement canonical IOAudio overrides**

Subclass `IOAudio`, adopt `<IOPower>`, and implement `+probe:`, `-reset` returning `BOOL`, `startDMAForChannel:read:buffer:bufferSizeForInterrupts:`, `stopDMAForChannel:read:`, `interruptOccurredForInput:forOutput:`, `getHandler:level:argument:forInterrupt:`, sampling-rate/encoding/channel queries, attenuation/gain/mute updates, and input/output enable selectors. Let `IOAudio` create channels, its interrupt port/thread, and register the device.

- [ ] **Step 3: Implement acquisition and unwind**

Parse the OF-backed `IODeviceDescription`, acquire PE services, map one I2S plus two DBDMA ranges, install DMA and detect interrupts, enable/format I2S, reset/init the codec while muted, allocate both rings, create IOAudio channels/controls, then apply the initial route. Unwind in exact reverse order on every failure.

- [ ] **Step 4: Keep handlers minimal and deferred**

DMA handlers acknowledge status, capture completion/fault state, and signal the IOAudio interrupt mechanism. Detect handlers capture GPIO state/generation and schedule deferred debounce. No handler calls PE I2C, codec operations, or route application.

- [ ] **Step 5: Implement power callbacks and document platform limitation**

Forward `setPowerState:` to the tested state machine. Note in `DriverHelp` that current PPC `PMSetPowerState` does not dispatch DriverKit callbacks; callback behavior is implemented and testable, but actual system sleep/wake requires future PMU/platform integration. Do not silently claim end-to-end PPC suspend support.

- [ ] **Step 6: Run `HOST-TEST`, `STATIC-CHECK`, and `TARGET-BUILD` (driver portion)**

Expected: deterministic tests pass; metadata and ISR audits pass; the target link resolves all Platform Expert and DriverKit symbols.

- [ ] **Step 7: Commit**

```bash
git add src/drivers-ppc/sound/drvPPCTASAudio
git commit -m "drvPPCTASAudio: bind TAS core to IOAudio"
```

---

## Task 10: Complete packaging, provenance, and acceptance evidence

Ensure the driver is buildable/discoverable and its source provenance is explicit.

**Files:**

- Modify: all `Makefile`, `PB.project`, `Default.table`, `DriverInfo`, localization, and `dpkg/control` files under `src/drivers-ppc/sound/drvPPCTASAudio`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/README.md`
- Create: `src/drivers-ppc/sound/drvPPCTASAudio/SOURCES.md`
- Modify: `docs/superpowers/plans/2026-07-29-ppc-tas-tumbler-audio-driver.md` (checkboxes/evidence only)

- [ ] **Step 1: Register every production source/header**

Verify each `.m`, `.c`, and `.h` appears in `PPCTASAudio.lksproj/PB.project` and generated Makefile source lists. Keep `INCLUDED_ARCHS = ppc` in every project preamble.

- [ ] **Step 2: Record sources and corrections**

List TI TAS3001C/TAS3004 documentation, AppleOnboardAudio files, and OpenBSD `tumbler.c`, `snapper.c`, `i2s.c`, `i2sreg.h`, `kiic.c`, and `macgpio.c` with URLs and licenses. State that behavior/register facts were reimplemented and that no GPL source was copied. Record the six-byte TAS3004 DRC and RB-sequence corrections.

- [ ] **Step 3: Run the full verification set**

Run `HOST-TEST`, `PEXPERT-TEST`, `STATIC-CHECK`, and `TARGET-BUILD`. Also run:

```powershell
git diff --check
rg -n "TODO|TBD|FIXME|XXX" src/drivers-ppc/sound/drvPPCTASAudio src/drivers-ppc/bus/drvPExpert/powermac/chips/keylargo_audio.c
```

Expected: no whitespace errors or unresolved placeholders. If target build is unavailable, preserve its exact command and mark only that verification pending.

- [ ] **Step 4: Review against the approved design**

Confirm: one bundle/two codec backends; structural unknown-machine attach; no guessed resources; 44.1 kHz full-duplex; exact-rate filtering; independent DBDMA rings/one clock; volume/mute/input controls; speaker fallback plus headphone/lineout mask; mute-before-switch; deferred debounce; bounded failure recovery; PE ownership; AWACS/Burgundy unchanged.

- [ ] **Step 5: Perform emulator and hardware acceptance when available**

Using throwaway images, boot an older no-TAS Sawtooth and verify no regression or accidental attach. On a supported real or emulated fixture, verify attach/init, playback/capture, simultaneous full duplex, jack routing, control persistence, fault recovery, and PM callback sequences. Physical speaker/headphone/line-level validation remains required before declaring Tier 1 hardware support.

- [ ] **Step 6: Request code review, fix findings, and commit**

```bash
git add src/drivers-ppc/sound/drvPPCTASAudio src/drivers-ppc/bus/drvPExpert src/kernel-7/machdep/ppc/PEKeyLargo.h docs/superpowers/plans/2026-07-29-ppc-tas-tumbler-audio-driver.md
git commit -m "drvPPCTASAudio: document support and verification"
```

## Final acceptance gate

- Host and PE deterministic suites pass with failure injection.
- The period PPC target builds Platform Expert and the new bundle, or the unavailable toolchain is reported precisely without weakening host evidence.
- No unbounded hardware wait, I2C in interrupt context, guessed OF resource, or amplifier-on failure path remains.
- No AWACS/Burgundy file changed.
- Review confirms the implementation matches the approved design and the license/provenance record.
