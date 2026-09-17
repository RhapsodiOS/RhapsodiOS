# Intel AC97 QEMU Playback and Recording Refactor Design

**Date:** 2026-08-01

## Objective

Refactor `drvIntelAC97Sound` so RhapsodiOS can provide reliable stereo PCM
playback and recording with QEMU's emulated Intel 82801AA AC97 controller.
Preserve the Rhapsody DriverKit `IOAudio` interface while isolating the ICH
controller logic enough to test reset, DMA, interrupt, and codec behavior on
the host.

The milestone is successful when playback and recording each run through
multiple descriptor-ring wraps without `IOAudio` timeouts or FIFO errors,
can run concurrently without disabling one another, and recorded non-silent
input can be played back in the guest.

## Scope

In scope:

- QEMU's Intel 82801AA AC97 PCI device (`8086:2415`).
- One primary AC97 audio codec.
- Stereo, signed 16-bit PCM playback and PCM capture.
- Fixed 48 kHz operation and variable-rate audio when the codec accepts it.
- Master/PCM output attenuation and mute.
- PCM record gain.
- Independent PCM input and output DMA engines on the shared interrupt.
- Host tests for hardware-independent controller and codec behavior.
- A reproducible QEMU launch and playback/recording smoke-test procedure.

Out of scope:

- Secondary or tertiary codecs.
- Modem codecs.
- Mic DMA, multichannel PCM, and S/PDIF.
- VIA, AMD, or other non-Intel AC97 controllers.
- Codec-specific physical-machine quirks.
- Sleep, wake, and general AC-link power management beyond safe shutdown.
- A reusable Rhapsody equivalent of Apple's `IOAC97Family`.

Existing Intel device IDs may remain advertised so the refactor does not
unnecessarily remove current matching behavior, but this milestone makes no
compatibility claim beyond QEMU's 82801AA model.

## Reference Comparison

The current driver combines PCI discovery, DriverKit lifecycle, I/O-port
access, channel reset, descriptor construction, DMA control, interrupt
handling, and mixer updates in `IntelAC97Driver.m`. Its controller state is a
file-global pointer. The separate `ac97.m` codec helper is mostly C, but is
coupled to kernel delay and logging functions. Recording interrupts and input
gain are incomplete, DMA descriptor geometry is chosen before `IOAudio`
provides its service-block size, and stopping either direction disables the
shared interrupt path.

[AppleIntelAC97Driver](https://github.com/apple-oss-distributions/AppleIntelAC97Driver)
separates the Intel controller, codec, audio device, and audio engine. It also
models each DMA channel explicitly and separates interrupt acknowledgement
from audio-engine service. Those boundaries and hardware sequences are useful,
but its IOKit and IOAudioFamily class structure cannot be backported directly
to Rhapsody DriverKit.

[AppleAC97Audio](https://github.com/apple-oss-distributions/AppleAC97Audio)
generalizes the same ideas into `IOAC97Family`, controller-specific DMA
implementations, codec devices, audio configurations, and codec plugins. That
architecture is intentionally not reproduced for a single QEMU/ICH target.

The refactor adopts the later drivers' separation of controller, codec, and
audio-service responsibilities. It does not copy their IOKit service hierarchy
or introduce a generalized AC97 family. Source notes will identify the Apple
references and the independently adapted behavior.

## Architecture

### DriverKit adapter

`IntelAC97Driver.m` remains the only Objective-C `IOAudio` subclass. It owns
one controller state object and translates DriverKit callbacks into controller
and codec operations. It is responsible for PCI discovery, DriverKit resource
registration, bus-master enablement, `IOAudio` lifecycle calls, and conversion
between `IOAudio` controls and AC97 mixer values.

The existing file-global controller pointer is removed from ordinary driver
operations. Rhapsody defines `IOAudioInterruptClearFunc` as `void (*)(void)`,
so the callback cannot receive an instance context. One narrow active-instance
bridge remains solely for this callback. The milestone therefore supports one
active Intel AC97 controller, matching the QEMU target. All other functions
receive controller state explicitly.

### ICH controller core

A pure-C `ICHAC97Controller.c/.h` module owns:

- NAMBAR and NABMBAR access through injected I/O callbacks.
- AC-link and DMA-channel reset sequencing.
- One state record each for PCM input and PCM output.
- Physical buffer information and buffer descriptor lists.
- DMA preparation, start, stop, and status queries.
- Shared-interrupt decoding and write-one-to-clear acknowledgement.

The injected operations include 8-, 16-, and 32-bit reads and writes plus a
bounded-delay callback. The kernel adapter binds them to `inb`/`inw`/`inl`,
`outb`/`outw`/`outl`, and `IODelay`. Host tests bind them to scripted fake
registers. No DriverKit or Objective-C type appears in the controller core.

### AC97 codec core

The existing codec helper becomes a pure-C module while retaining the current
register definitions and focused API. It owns codec probing, capability state,
VRA enable/readback, sample-rate programming, master and PCM output levels,
record gain, and cached mixer state. Hardware reads, writes, delays, and logging
are supplied through callbacks rather than imported directly from DriverKit.

Only the primary audio codec and the controls needed by this milestone remain
on the active path. Existing speculative modem, multichannel, S/PDIF, and broad
power-management code may be left present if removing it would create unrelated
churn, but it is not extended or treated as tested functionality.

## Initialization and Shutdown

Initialization is staged, with ownership recorded after each successful step:

1. Read PCI configuration space and validate the Intel device identity.
2. Decode the expected mixer and bus-master I/O BARs and the interrupt line.
3. Register the two port ranges and interrupt with the device description.
4. Enable PCI bus mastering.
5. Initialize the `IOAudio` superclass.
6. Reset PCM input, PCM output, and mic DMA registers, polling each bounded
   reset rather than relying on an unverified delay.
7. Perform the AC-link cold-reset sequence and wait for primary-codec ready
   with a bounded timeout.
8. Allocate and probe the primary codec.
9. Request VRA, read the control bit back, and use variable rates only when the
   codec retained the bit. Otherwise expose fixed 48 kHz operation.
10. Initialize master/PCM output levels, output mute state, record gain, and a
    stable record-select value.

QEMU's AC97 model stores the record-select register but connects PCM input to
its generic audio input voice, so record-source mux emulation is not an
acceptance requirement. The relevant behavior is visible in QEMU's
[`hw/audio/ac97.c`](https://gitlab.com/qemu-project/qemu/-/blob/master/hw/audio/ac97.c).

Every failure unwinds only resources acquired by completed stages. Cleanup
must be safe after partial initialization. Normal shutdown stops both engines,
clears their interrupt-enable bits, acknowledges pending write-one-to-clear
causes, releases DriverKit resources, and frees the codec, BDLs, lock, and
controller state. Codec power-down is used only where it cannot interfere with
partial-init cleanup.

## DMA Buffer and Descriptor Model

`createDMABufferFor:length:read:needsLowMemory:limitSize:` maps the contiguous
`AudioChannel` buffer and records its virtual address, physical address, byte
length, and direction. It allocates the channel BDL if needed, but does not
choose descriptor geometry before `IOAudio` supplies the service size.

`startDMAForChannel:read:buffer:bufferSizeForInterrupts:` validates and builds
the BDL. The active descriptor count is:

```
total DMA bytes / bufferSizeForInterrupts
```

The division must be exact, the result must be between 1 and the ICH limit of
32, each service block must be aligned to a 16-bit sample, and its sample count
must fit the descriptor length field. Each descriptor address advances by the
service-block byte size. Its length is encoded as `service block bytes / 2`
because ICH AC97 BDL lengths count 16-bit samples, not bytes. Each active entry
requests an interrupt on completion so the hardware cadence matches
`AudioChannel`'s descriptor cadence.

For the current i386 `IOAudio` defaults, a 32 KiB channel buffer with 4 KiB
service blocks creates eight entries; a 64 KiB buffer creates sixteen. Unused
BDL entries are cleared. BDBAR and LVI are programmed only after the BDL is
valid, and DMA starts only after stale channel status has been acknowledged.

The existing Rhapsody allocation path uses `alloc_cnvmem` for a physically
contiguous i386 channel buffer. This milestone preserves that contract rather
than introducing a new scatter/gather allocator.

## Playback and Recording Flow

PCM output and PCM input have separate state containing the mapped sample
buffer, BDL, BDL physical address, byte length, service-block size, active
descriptor count, and running flag.

Starting a channel:

1. Reject an invalid or already-inconsistent buffer configuration.
2. Program the applicable codec DAC or ADC rate.
3. Reset and verify the selected DMA engine.
4. Build and publish its BDL and last-valid index.
5. Clear stale completion, last-valid, and FIFO-error causes.
6. Enable completion and FIFO-error interrupts and set run/pause bus master.
7. Mark only that channel running.

Stopping a channel clears its run and interrupt-enable bits and acknowledges
its pending causes. It does not disable DriverKit interrupt handling or modify
the other channel. Global interrupt disablement is allowed only when neither
PCM direction is running.

The interrupt path reads global status and then the indicated channel status.
It acknowledges only the completion, last-valid, and FIFO-error
write-one-to-clear bits. The decoded result records separate input and output
service flags. Simultaneous input and output causes are both preserved for
`interruptOccurredForInput:forOutput:`. FIFO and last-valid conditions are
counted and logged with rate limiting so a broken ring is diagnosable without
flooding the kernel log.

## Audio Controls and Rates

The driver exposes signed 16-bit linear stereo PCM only. It reports continuous
8–48 kHz sampling when VRA was enabled and read back successfully. Without
VRA, it reports only 48 kHz and rejects attempts to program another rate.
Requested DAC and ADC rates are written separately and read back; a rejected
or altered value is reported to the caller rather than silently cached as
successful.

Output attenuation is converted to the AC97 5-bit inverse attenuation range,
with clamping before register packing. Mute preserves the cached left and
right attenuation values. Input gain converts the `IOAudio` left and right
gain values to AC97 record-gain fields, updates both channels atomically from
the cached pair, and preserves the mute bit deliberately.

## Error Handling and Diagnostics

All waits have explicit iteration limits. Reset timeout, codec-ready timeout,
invalid BDL geometry, physical mapping failure, codec readback failure, DMA
FIFO error, and unexpected halted-channel state have distinct log messages.
Expected status polling remains quiet. Register dumps are debug-only and are
never part of normal probe or interrupt handling.

Public DriverKit callbacks fail without starting hardware when their
preconditions are not met. A failed start leaves the selected engine stopped
and its interrupt enables clear. Errors in one direction do not tear down an
already-running opposite direction.

## Verification

### Host tests

A test target under the driver project compiles the pure-C controller and codec
modules against a fake I/O backend. Tests cover:

- 32 KiB/4 KiB and 64 KiB/4 KiB BDL geometry.
- Sample-unit length encoding, IOC bits, physical-address progression, and
  clearing unused entries.
- Rejection of zero, misaligned, non-divisible, and over-32-entry geometry.
- DMA reset success and timeout.
- AC-link cold-reset ordering, codec-ready success, and codec-ready timeout.
- Output-only, input-only, simultaneous, last-valid, and FIFO-error interrupt
  decoding and acknowledgement.
- Independence of input and output start/stop state.
- Codec identification, VRA enable/readback, fixed-rate fallback, DAC/ADC rate
  programming, attenuation/mute conversion, and record-gain conversion.
- Cleanup after failure at every controller/core allocation or preparation
  point represented by the pure-C API.

The tests run through a small host makefile and require no QEMU or DriverKit
headers.

### Native build

The driver must build with the historical Project Builder makefile framework
in the supported Rhapsody/Mac OS X Server build guest. The link project adds
the controller and codec modules as `CFILES` and retains only the Objective-C
adapter as a `CLASSES` source.

### QEMU smoke test

The disposable-image QEMU launcher gains an explicit AC97 option that adds a
named audio backend and `-device AC97`. It never modifies the source disk image.
The backend is selectable so Windows DSound can provide the normal manual path
and JACK or another routable backend can provide deterministic input.

Acceptance procedure:

1. Boot a disposable image and confirm `8086:2415`, primary-codec readiness,
   codec identification, and successful driver initialization in the log.
2. Play a known PCM sample long enough to cross multiple BDL wraps; confirm
   audible or captured output and no FIFO or `IOAudio` timeout errors.
3. Feed a known host tone into QEMU PCM input, capture it in the guest, confirm
   the capture contains non-silent changing samples, and play it back.
4. Run playback and recording concurrently and confirm both continue across
   multiple BDL wraps.
5. Stop each direction separately and confirm the other continues.

When JACK or another routable input backend is available, the host tone is
connected deterministically and the captured signal is compared with the
known stimulus. On the current Windows host, DSound microphone capture and
guest playback is the documented fallback; it must still demonstrate
non-silent changing input rather than merely a successful open call.

## Deliverables

- Refactored `IntelAC97Driver.m/.h` DriverKit adapter.
- Pure-C ICH controller core and header.
- Pure-C AC97 codec core and existing register definitions.
- Updated link-project makefile.
- Host controller/codec tests and host test makefile.
- QEMU AC97 launcher option and smoke-test documentation.
- Source/provenance note linking the two Apple reference implementations and
  documenting the architectural adaptation.

No other sound driver, shared DriverKit audio implementation, or unrelated VM
workflow is changed.
