# PowerPC TAS audio driver

`drvPPCTASAudio` is a Rhapsody DriverKit `IOAudio` kernel-server bundle for
PowerPC Macs whose Open Firmware audio hierarchy identifies a Tumbler
(TAS3001C) or Snapper (TAS3004) codec. The broad `i2s` table match only asks
the driver to probe; attachment succeeds only after the firmware graph and all
required resources have been validated.

## Architecture

The Objective-C adapter in `PPCTASAudio.m` owns the `IOAudio` lifecycle,
device-tree access, memory mappings, interrupts, callouts, and controls. The
hardware-independent C modules provide:

- immutable firmware parsing and I2S clock selection in `TASCore`;
- TAS3001C and TAS3004 register backends with commit-on-success shadows;
- independent input and output DBDMA rings in `PPCDBDMAAudio`;
- serialized stream, routing, recovery, and power transactions in
  `TASRuntime`; and
- wrap-safe deadline arithmetic in `TASTime`.

Platform Expert owns the shared KeyLargo-family services: serialized KeyWest
I2C, polarity-normalized GPIO access, and locked I2S-cell feature-control
transitions. AWACS and Burgundy matching and code are unchanged.

DBDMA uses the canonical 16-byte `IODBDMADescriptor` layout. DriverKit's
`IOSetDBDMADescriptor` and `IOGetDBDMADescriptor` accessors use `WriteSwap32`
and `ReadSwap32`; equivalently, every 32-bit operation, address, dependency,
and result field has a little-endian memory image on the PowerPC host. Rings
are 16-byte aligned, page-split through a translation callback, bounded by the
16-bit transfer-count and 4096-byte contiguous-allocation limits, and
published or invalidated with cache barriers before ownership changes.

## Supported behavior

Both codecs run I2S with 64 clocks per frame and 20-bit codec slots while the
public PCM format is signed 16-bit stereo. The driver provides playback and
capture, stereo volume, mute, input gain, and microphone/line-in selection.
TAS3001C and TAS3004 receive different reset images and register widths; the
TAS3004 backend also restores its ACR and six-byte DRC image.

The speaker, headphone, and line-out endpoints are external analog paths.
Their firmware-described mute GPIOs are the authoritative output routing
mechanism: a route change mutes all amplifiers first, then unmutes only the
selected endpoints after the transition succeeds. Codec mixer registers stay
on a fixed unity input path and are not treated as an output mux. The required
codec-input-data-mux GPIO selects microphone or line-in.

Input and output have independent DBDMA rings but share one I2S clock. Full
duplex is supported only when both directions use the same active sample rate;
a conflicting second rate is rejected. Advertised rates are the unique
firmware-listed values from 32 through 48 kHz for which the driver can compute
an exact I2S divisor. A usable configuration must include 44.1 kHz. Arbitrary
rates and rate conversion are not supported.

## Firmware requirements

The parser accepts structurally valid machines rather than a model-name
allowlist. It requires one unambiguous `i2s`/sound/codec chain whose compatible
values identify `tumbler` or `snapper`, plus:

- the I2S cell and three ordered physical ranges: I2S registers, output DBDMA,
  then input DBDMA;
- the three delivered interrupt identities in codec, output-DMA, input-DMA
  order;
- a resolvable codec reference, KeyWest I2C port, and normalized seven-bit
  codec address (`0x34`/`0x35`; historical even `0x68`/`0x6a` forms are
  normalized once);
- hardware-reset, amplifier-mute, and codec-input-data-mux GPIOs with valid
  offsets and active states;
- for each advertised headphone or line-out path, both mute and detect GPIO
  descriptions with valid polarity and detect-interrupt metadata; and
- a nonempty `sample-rates` property containing 44.1 kHz and at least one
  exact supported clock configuration.

Phandle-based properties and the historical Apple `audio-gpio` names are
understood. Missing, malformed, conflicting, ambiguous, out-of-range, or
guessed resources cause probe to decline. The `IODeviceDescription` must
deliver exactly the three ranges and three interrupt identities that the
validated firmware configuration names.

## Jack detection and lifecycle limitations

The main I2S `IODeviceDescription` cannot bind the child GPIO jack-detect
interrupts through this DriverKit resource path. While ready, the driver polls
the detect GPIOs every 250 ms and then applies a two-sample, 5 ms confirmation.
A stable insertion or removal can therefore take roughly 255 ms to affect the
route in the worst scheduled case, plus worker scheduling time.

Rhapsody `IOAudio` does not terminate its worker threads during `-free`.
Following successful initialization, the driver can quiesce and fail-mute the
hardware but deliberately retains its object, locks, callout-owner singleton,
and any DMA storage that could still be observed by hardware. This retained
tombstone prevents unsafe use-after-free, but it also means the loaded driver
cannot be unloaded or replaced safely and a second probe remains rejected
until reboot.

Power-state callbacks and their transaction logic are implemented and covered
by deterministic tests. The current PPC `PMSetPowerState` path does not
dispatch DriverKit power callbacks end to end, so system sleep/wake remains a
platform-integration limitation rather than validated support.

## Build and test

Run the deterministic driver tests in the configured Rhapsody guest:

<!-- markdownlint-disable MD013 -->

```powershell
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/sound/drvPPCTASAudio/tests && gnumake -f Makefile.host clean test"
```

Run the Platform Expert state-machine tests:

```powershell
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/bus/drvPExpert/tests && gnumake -f Makefile.host clean test"
```

Build Platform Expert and the driver with the period PPC toolchain:

```powershell
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake installhdrs DSTROOT=/tmp/tas-dst"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/bus/drvPExpert && gnumake clean && gnumake"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/sound/drvPPCTASAudio && gnumake clean && gnumake"
```

<!-- markdownlint-enable MD013 -->

The Windows host has no compatible period PPC compiler. A successful host
static audit is not a substitute for the two target builds. At the Task 10
documentation checkpoint the wrapper stopped before guest contact because
`vm/vm.conf` was absent (it directs the user to copy and edit
`vm.conf.example`). The exact guest build and test commands therefore remain
pending; emulator and physical endpoint acceptance also remain pending.

Source provenance and datasheet corrections are recorded in [SOURCES.md](SOURCES.md).
