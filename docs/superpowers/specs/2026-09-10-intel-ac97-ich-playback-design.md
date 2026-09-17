# Intel AC97 ICH Playback Design

**Date:** 2026-09-10

## Objective

Make `drvIntelAC97Sound` play 16-bit linear stereo through an Intel ICH
AC'97 controller, using the hardware sequences proven by
[openstep-ac97](https://github.com/onionmixer/openstep-ac97) on real ICH5,
while keeping Rhapsody DriverKit `IOAudio` and the existing `.lksproj`
build.

Success for this milestone: QEMU `8086:2415` probe and codec ready; 16-bit
stereo playback across several descriptor-ring wraps; no DMA FIFO errors
and no `Timeout waiting for interrupt`; SoundKit can see the device.

This spec supersedes
`docs/superpowers/specs/2026-08-01-intel-ac97-qemu-refactor-design.md`
for the playback milestone. Capture, full duplex, and the uncorrected
August controller stubs (Linux `outb` order, no LVI chase) are not this
work.

## Scope

In scope:

- QEMU Intel 82801AA AC97 (`8086:2415`) as the verification target.
- Existing Intel ICH family IDs already listed in `Default.table`.
- One primary audio codec.
- Stereo signed 16-bit PCM **playback** only.
- 48 kHz, plus 8–48 kHz when VRA enables and reads back.
- Master / headphone / surround output levels the codec actually has.
- SoundKit load commands (`SMAP` / `ADVERTISE` / `WIRE`).
- Host tests for BDL, reset/BDBAR, LVI chase, CAS/RCS, volume packing, and
  codec identification.
- Opt-in QEMU `--ac97` playback smoke on a disposable image.

Out of scope:

- Recording, mic DMA, input gain, record-select.
- MMIO (MMBAR/MBBAR).
- Secondary/modem codecs, S/PDIF, 4/6-channel.
- OPENSTEP SDL start/stop coalescing.
- A driver-side workaround for the `IOAudio` stereo-init bug (fixed in
  `src/driverkit-3/libDriver/Kernel/IOAudio.m`).
- Importing openstep-ac97’s `IntelAC97Driver.m`.
- A generalized `IOAC97Family`.

## References

openstep-ac97 read this tree, listed the defects in `ASSESSMENT.md`, and
rewrote rather than ported. Take their **hardware protocol** (NetBSD
`auich` + measured ICH5 behaviour). Do not copy their OPENSTEP bundle
or the 136 KB adapter.

Rhapsody `ioPorts.h` is port-then-value, same as OPENSTEP. Linux/NetBSD
and the current driver are value-then-port. Every current `outb` /
`outw` / `outl` in `IntelAC97Driver.m` is reversed and writes the legacy
DMA controller when it intends a channel reset.

## Architecture

```
IntelAC97Driver (ObjC)
  PCI, port/IRQ registration, IOAudio callbacks, instance-owned state

ICH controller (C, host-testable)
  reset, BDL, DMA start/stop, LVI chase, IRQ ack, codec port protocol

AC97 codec (existing helper, corrected)
  probe, VRA readback, mixer packing from measured bit width
```

`IntelAC97Driver` remains the only `IOAudio` subclass and the only
Objective-C file. It owns one controller/codec state object. The
file-scope `static struct ich_state *s` goes away.

Rhapsody `IOAudioInterruptClearFunc` is `void (*)(void)`, so one
active-instance pointer remains solely for `clearInterrupts` and the
hardware IRQ handler. A second attach fails closed. All other functions
take state explicitly.

No DriverKit or Objective-C type appears in the C ICH core. I/O uses
injected callbacks. The kernel adapter binds them to `inb`/`outb` and
friends **port-first**: `outb(port, value)`. The core itself never calls
`outb`; it uses `(base, offset, value)` accessors so Linux-style call
sites cannot happen.

## DMA and playback

`createDMABufferFor:` returns `NULL` for a read. For output it maps the
`AudioChannel` buffer, stores virt/phys/size, and allocates an 8-byte
aligned 32-entry BDL. It does not choose fragment size, write BDBAR, or
start the engine.

`startDMAForChannel:` refuses capture. Fragment size is
`bufferSizeForInterrupts`. It must divide the buffer, be even, and
encode as at most 65535 16-bit samples. Unique fragment count is
`bufferBytes / fragBytes`.

The ICH ring is always 32 entries. Unique fragments repeat to fill all
32 slots:

- address = `bufPhys + (i % nFrags) * fragBytes`
- length = `fragBytes / 2` (samples, not bytes)
- `IOC` on every entry (one completion = one IOAudio fragment)

Then: channel `RR` and poll until it clears; write BDBAR **after** that
(openstep-ac97 5b-2a: `RR` left BDBAR at 0); LVI = 31; ack status;
`RPBM | FEIE | IOCE`. Enable DriverKit interrupts after a successful
start.

LVI chase is in the interrupt handler. On `BCIS`, LVI = `(CIV - 1) & 31`.
Ack channel write-1-to-clear (`BCIS`, `LVBCI`, `FIFOE`) and `GSTS.POINT`.
Call `IOEnableInterrupt` on every path out, including “not our
interrupt.” Chain to IOAudio’s handler only on a real output completion.

`interruptOccurredForInput:forOutput:` sets `*serviceInput = NO` and
`*serviceOutput` from the latched completion, never from a `running`
flag.

`stopDMAForChannel:` clears that engine’s run and interrupt-enable bits
and acks it. It does not call `disableAllInterrupts`. Global interrupt
disable is only in teardown.

`timeoutOccurred` logs and does not restart the engine.

## Mixer, rates, and codec access

Codec access waits for `CAS` (NABMBAR+0x34) to drop, then reads or writes
NAMBAR, then checks `GSTS.RCS`. A failed read returns `0xffff`.

Identify with the **full 32-bit** vendor ID. Do not mask with
`0xffffff00` and then compare to table keys that still contain the model
byte.

After attach, set `VRA` and read `EXT_AUDIO_CTRL` back. If the bit stayed
set, advertise 8000–48000 and the seven conventional rates. If not,
advertise 48000 only and reject anything else. `updateSampleRate`
programs the DAC, reads it back, and does not cache a rejected value.
The ADC is not programmed this pass.

NeXT attenuation is 0 (loud) … −84 (quiet). Measure bit width per output
register the codec has (master, headphone, surround). Packing:

```
field = (-atten * ((1 << bits) - 1)) / 84
```

A 6-bit value written into a 5-bit field can read back as 0 (full
volume); that is why width is per register, not a global 5-bit clamp.

Mute is a separate bit. The driver does not unmute unless the playback
engine is running. Attach starts muted. IOAudio defaults (−42 / −42)
are applied only after `[super initFromDeviceDescription:]` returns, or
at the first `startDMA`. Input-gain callbacks are no-ops.

## Init, teardown, and SoundKit

`+probe:` remains the Device Manager entry. `initFromDeviceDescription:`
validates Intel vendor/device, BAR0/BAR1 as I/O NAMBAR/NABMBAR, and a
non-zero IRQ. Enable PCI command I/O space, memory space, and bus
master. Register one IRQ and two port ranges (mixer 256 bytes, bus
master 64 bytes).

`-reset` (called from `IOAudio` before `_initAudioHardwareSettings`):
bounded PCM-out channel reset; AC-link reset (warm if `GLOB_CNT.COLD`
is already set, else cold); wait for `GLOB_STA.PCR` with a timeout;
CAS/RCS codec attach. Failure returns `NO` with the engine stopped.

After `[super initFromDeviceDescription:]` returns, apply mixer from
IOAudio left/right attenuation, still muted until DMA runs.

One idempotent release helper: stop the engine, ack leftover status,
release IRQ and port ranges only if acquired, free BDL and state, clear
the interrupt bridge. `-free` and every init failure call it. No codec
power-down on partial-init cleanup.

`Load_Commands.sect` matches the other Rhapsody audio drivers:

```
SMAP        audio0 audioMessages 0
ADVERTISE   audio0
WIRE
```

Remove the missing-icon `sectcreate`. Keep `"Share IRQ Levels" = "Yes"`.
When ICH constants move into the C header, `ICH_GLOB_STA_S2CR` is
`0x10000000` (NetBSD), not `0x00100000`. The playback path does not
depend on that bit.

## Error handling

Every wait has an iteration limit (channel `RR`, codec-ready, CAS).
Timeouts log once and fail closed. FIFO errors increment a counter and
log on the first occurrence and every 256th. Public callbacks return
`NO` / `NULL` without starting hardware when preconditions fail. A failed
start leaves the engine stopped and its interrupt enables clear.

## Testing

Host tests compile the C ICH core and codec packing against a fake port
backend. No DriverKit headers. They cover:

- BDL: 32 KiB / 4 KiB and 64 KiB / 8 KiB; sample-unit length; `IOC` on
  every entry; 32 slots wrapping unique fragments; reject odd sizes,
  non-divisible buffers, and sample counts over 65535.
- Channel `RR` clears BDBAR; start writes BDBAR only after `RR` clears.
- LVI starts at 31; after CIV = *n*, LVI is `(n - 1) & 31`.
- CAS wait; `RCS` makes codec read return `0xffff`.
- Volume packing for 5-bit and 6-bit registers at 0, −42, and −84.
- Full 32-bit codec ID (AD1980 is not AD1819).

A Python source-contract test on the adapter:

- the ICH C core does not call `outb` / `outw` / `outl`
- the kernel I/O adapter calls `outb(port, value)` (Rhapsody order)
- `IntelAC97Driver.m` contains no Linux-order `outb(value, port)` writes
- `Load_Commands.sect` contains `SMAP`, `ADVERTISE`, and `WIRE`
- `startDMAForChannel:` does not start a read
- `stopDMAForChannel:` does not call `disableAllInterrupts`
- `IOEnableInterrupt` is on every `clearInt` path

Native: `gnumake` from `src/drivers-i386/sound/drvIntelAC97Sound` in the
Rhapsody guest.

QEMU: disposable image with `--ac97`; confirm `8086:2415`, primary
codec ready, play 16-bit stereo across several ring wraps, no FIFO or
IOAudio timeout. Capture is not a gate. Real ICH is best-effort after
QEMU passes; this milestone does not require a physical machine.

## Provenance

Controller/codec sequences follow NetBSD `auich.c` / `ac97.c` (BSD-2)
as confirmed by openstep-ac97 on ICH5. DriverKit wiring follows this
tree’s Sound Blaster and ES1x88 drivers. The August QEMU duplex split is
kept only as adapter + C core; its recording path, Linux `outb` adapters,
and “set LVI once” start are not used.
