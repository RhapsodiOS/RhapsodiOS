# PPC Kiwi ATA Design

## Purpose

Let the in-kernel PPC ATA driver (`src/kernel-7/bsd/dev/ppc/drvPPCATA`) drive
both channels of Kiwi, the Promise PDC2027x ATA controller that Apple fitted to the Xserve G4
(`RackMac1,1` and `RackMac1,2`) for its drive bays. The optical drive stays on
KeyLargo's ATA cell, which the driver already handles.

Each Xserve has two Kiwi PCI functions. Each function has two ATA channels,
and each channel carries one Apple Drive Module wired as master. The original
Xserve runs the bays at ATA/100; the slot-load model runs them at ATA/133.

## Existing state

- The EIDE entry in `driverkit/ppc/autoconf_ppc.m` matches
  `ide ata ATA pci1095,646` against a node's model, compatible, name and
  `device_type`. Kiwi's PCI node is `compatible = "kiwi-root"`; nothing
  guarantees one of the existing keys matches it.
- `+probe:` creates one `IdeController` per device description. Every
  controller type drives one channel. The CMD646 path drives only the primary
  channel of its two.
- PCI controllers map their BARs with `mapMemoryRange:`. DriverKit builds the
  range list from `assigned-addresses` in property order and drops any entry
  it cannot translate, so a range index is only a BAR number by convention.
- The CMD646 reaches its bus-master registers through PCI configuration space
  (0x70 and 0x74). Kiwi has no such mirror; its bus-master block is only in
  BAR4.
- The CMD646 and Kauai paths re-enable the device interrupt after each
  interrupt. PCI devices get shareable IRQ levels, and the shared dispatcher
  suspends a device's interrupt before sending the interrupt message.

## Hardware facts

From Linux `drivers/ide/pdc202xx_new.c` (v5.10) and
`drivers/ata/pata_pdc2027x.c`, used as hardware references only. Promise's
documentation is under NDA.

| Item | Value |
|---|---|
| Vendor | 0x105a |
| Ultra DMA 133 parts (max mode 6) | 0x4d69, 0x6269, 0x1275, 0x5275, 0x7275 |
| Ultra DMA 100 parts (max mode 5) | 0x4d68, 0x6268 |
| Primary task file, control | BAR0, BAR1 + 2 (I/O space) |
| Secondary task file, control | BAR2, BAR3 + 2 (I/O space) |
| Bus-master block | BAR4, 8 bytes per channel (SFF-8038i) |
| Indexed registers | index at bus-master + 1, data at bus-master + 3 |
| Cable | index 0x0b, bit 0x04 set means a 40-wire cable |
| Timing, master | index 0x0c-0x13 (slave + 8) |
| Test mode | primary index 0x01, bit 0x40 |
| Clock counter | index 0x20, 0x21 on both channels; 30 bits, counts down |
| PLL control | secondary index 0x02 (F), 0x03 (R) |
| Apple setup | revision >= 3: set bit 0 of configuration byte 0x40 |

PLL: the chip derives its ATA clock from a PLL fed at half the PCI clock
(about 16.9 MHz on a 33 MHz bus). The driver measures the input over about
10 ms with the counter in test mode, then programs
`output = input * (F + 2) / (R + 2)` for 133 MHz (Ultra DMA 133 parts) or
100 MHz. R is 13, 8, 6 or 0 as the ratio passes 8.6, 12.9 and 16.1; inputs
outside 5-70 MHz, ratios of 64 or more, and F outside 0-127 are refused and
leave the firmware's setting alone. The PLL then needs 30 ms to settle.

Timing: at 100 MHz the chip sets its own timing registers when it sees SET
FEATURES; the driver only clears the tHOLD bit (index 0x10 bit 7) for Ultra
DMA 2. At 133 MHz the driver must write Promise's tables after SET FEATURES:
PIO 0-4 into 0x0c, 0x0d and 0x13; multiword DMA 0-2 into 0x0e and 0x0f; Ultra
DMA 0-6 into 0x10-0x12.

## Design

- A pure C89 module, `KiwiATA.{h,c}` in `drvPPCATA`, holds the register
  layout, the part table, the compatible and `assigned-addresses` scans, the
  counter and PLL arithmetic, the timing writes, and the boot-path channel
  rule. Host tests exercise it.
- `kControllerTypeKiwi` joins the controller types in both `ata_extern.h`
  copies, and `kiwi-root` joins the EIDE matching keys.
- `+probe:` selects Kiwi when any `compatible` entry is `kiwi-root`. It
  requires a supported Promise part in configuration word 0 and BAR0-BAR4 as
  I/O entries in `assigned-addresses` with every entry translated, so a range
  index is the entry's position.
- The PCI node stands for both channels, as Mac OS X's AppleKiwiRoot does.
  Its probe publishes one description per channel through the PCI bridge's
  `createDevice:ref:`: a copy of the node's properties plus
  `rhapsodios,kiwi-channel`. Each copy gets its own `KernDevice` and
  interrupt port, shares the node's registers and interrupt, and is probed as
  its own controller with one interrupt required. The firmware's channel child
  nodes are not used; their properties are unknown.
- `assignRegisterAddresses:` maps the channel's two BARs and BAR4, reads the
  channel's status to drop an interrupt firmware left pending, and clears the
  bus master. Channel 0 runs the one-time chip setup first: the Apple
  configuration bit, PCI I/O space and bus mastering, the PLL, and a quiet
  channel 1 (nIEN set) until channel 1's controller attaches.
- Each channel installs its own interrupt handler (`getHandler:...`), attached
  after the registers are mapped. It claims an interrupt only when its
  channel's bus-master interrupt latch is set: it reads the ATA status so the
  line drops, clears the latch, and sends the interrupt message. Claimed or
  not, it re-enables the interrupt at once, so an idle channel never holds the
  shared line off.
- The highest Ultra DMA mode is the part's limit, or 2 on a 40-wire cable.
  The Ultra DMA table grows a mode 6 entry (15 ns).
- `setTransferMode:` writes the Kiwi timing registers for the drive after its
  SET FEATURES commands. `calcIdeConfig:` and `setTransferRate:` have nothing
  to compute or write for Kiwi. Single-word DMA is timed as multiword DMA 0,
  as the Kauai path does.
- DMA reuses the CMD646's physical region descriptor builder. Kiwi writes the
  table address to bus-master + 4 and the direction to the command register,
  sets the start bit after the ATA command, and clears it after the interrupt.
  A bus-master error fails the transfer. The error path skips the DBDMA reset,
  which Kiwi has no channel for. ATAPI DMA gets the same start and stop.
- Buffers at odd addresses fall back to PIO, as on the CMD646, since region
  descriptors need even addresses. This covers `atapiDmaAllowed:` and
  `drvATADisk`.
- `matchDevicePath:` skips a firmware path component naming the channel, so a
  root path through the channel node still reaches that channel's disk.
  `getDevicePath:` adds `/@<channel>`, so the two channels' disks differ.

## Channels

DriverKit gives each device description one `KernDevice`, and a
`KernDevice` accepts one interrupt port, so two controllers cannot share the
PCI node's description. Publishing a description per channel gives each
channel its own port. Both still sit on one level-triggered PCI interrupt,
and the shared dispatcher suspends every attached device's interrupt before
calling its handler. With the default handler an idle channel would keep the
line suspended until its next command, stalling the other channel; the
per-channel handler above avoids that.

The handler trusts the SFF-8038i bus-master interrupt bit, which is set on
the rising edge of the channel's INTRQ. That is certain for DMA commands. If
these parts do not latch it for PIO commands, a PIO interrupt would go
unclaimed and re-fire; hardware validation must confirm PIO interrupts on
both channels. The fallback would be a Promise per-channel interrupt status
bit (believed to be index 0x0b, bit 0x20, as FreeBSD's driver reads it; not
yet confirmed here), which the handler could add.

## Out of scope

- DriverKit gives a device interrupts only from `AAPL,interrupts` on these
  machines. The PExpert's MacRISC discovery publishes it when the node's
  inherited `interrupt-parent` is the OpenPIC; that lives in `drvPExpert`.
- Promise's memory-mapped register set (BAR5), sleep and wake, and hot-plug
  of drive modules.

## Verification

- Host tests for the part table, the compatible and `assigned-addresses`
  scans, counter assembly, PLL input and F/R arithmetic, the timing writes
  for both part classes, and the boot-path rule, under
  `-std=c89 -pedantic -Wall -Wextra -Werror`.
- The Objective-C glue needs the PPC kernel build.
- Hardware: boot an Xserve G4 from a temporary disk. Confirm the probe lines,
  the measured PLL input (about 16.9 MHz), the selected modes, sustained
  read/write on both Kiwi functions, and a clean reboot. Record results in
  `docs/boot/ppc-macrisc-validation.md`.
- Hardware: identify a drive on each channel (PIO commands) without interrupt
  timeouts or a hang, then run DMA on both channels at once.
- Hardware: confirm the two Kiwi functions have different `AAPL,interrupts`
  sources. DriverKit's shared dispatch suspends every driver on a line until
  each one re-enables, so an idle function sharing a source with a busy one
  would stall it.
