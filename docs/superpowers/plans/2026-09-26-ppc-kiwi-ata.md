# PPC Kiwi ATA Implementation Plan

**Goal:** The in-kernel PPC ATA driver probes and drives both channels of
each Kiwi (Promise PDC2027x) function on the Xserve G4. Design:
`docs/superpowers/specs/2026-09-26-ppc-kiwi-ata-design.md`.

**Ground rules:** C89 for the pure module; 1999 Objective-C for the glue;
one commit per task with a `drvPPCATA:` prefix and no metadata; host tests
under `-std=c89 -pedantic -Wall -Wextra -Werror`.

### Task 1: Kiwi helpers

**Files:** create `src/kernel-7/bsd/dev/ppc/drvPPCATA/KiwiATA.h`,
`KiwiATA.c`, `tests/kiwi_ata_test.c`; modify `tests/Makefile.host`.

- [x] Write the tests first:
  - every listed Promise part maps to Ultra DMA 6 or 5; other devices and
    other vendors map to 0; a 40-wire cable caps either at 2;
  - `kiwi-root` is found anywhere in a `compatible` list, but not as a
    prefix, and not past the property's length;
  - BAR0-BAR4 are found in `assigned-addresses` in any order; a missing BAR,
    a memory-space BAR, or a short property fails;
  - counter bytes assemble to 30 bits, ignoring each high byte's top bit;
  - a 16.949 MHz input measured over 10 ms, with a counter that wraps, gives
    about 16.9 MHz; zero elapsed time gives 0;
  - F/R for 16.949 MHz and 33 MHz inputs at 100 and 133 MHz match Linux's
    arithmetic; inputs outside 5-70 MHz fail;
  - 133 MHz timing writes for PIO 0-4, multiword 0-2 and Ultra 0-6 on
    master and slave; 100 MHz parts write only the Ultra DMA 2 tHOLD clear;
    invalid modes fail;
  - the boot-path rule skips a matching channel component, refuses the other
    channel's, and leaves a lone disk component alone.
- [x] Implement `KiwiATA.c`; run the tests; host syntax check for PowerPC.
- [x] Commit: `drvPPCATA: add Kiwi PLL, timing and probe helpers`.

### Task 2: Drive the Kiwi controller

**Files:** both `ata_extern.h` copies, `IdeCnt.h`, `IdeCnt.m`,
`IdeCntInit.h`, `IdeCntInit.m`, `IdeCntDma.h`, `IdeCntDma.m`,
`AtapiCntCmds.m`, `drvATADisk/ATADiskInternal.m`,
`driverkit/ppc/autoconf_ppc.m`, `src/kernel-7/conf/files.ppc`.

- [x] Add `kControllerTypeKiwi`; match `kiwi-root` in the EIDE entry.
- [x] Probe: select Kiwi from `compatible`; check one interrupt, the part,
      and the BAR layout; set the Ultra DMA cap from the part and the cable.
- [x] `assignRegisterAddresses:` maps the primary channel and BAR4, and runs
      the chip setup (Apple configuration bit, PCI command, PLL, secondary
      channel quiet).
- [x] Ultra DMA selection covers Kiwi; extend the mode table to mode 6.
- [x] Timing writes after SET FEATURES; nothing for Kiwi in
      `calcIdeConfig:` or `setTransferRate:`.
- [x] PRD table address, DMA start and stop for ATA and ATAPI; skip the DBDMA
      reset on the error path; odd buffers use PIO.
- [x] Clear the bus-master interrupt latch and re-enable the interrupt in
      `ideWaitForInterrupt:`.
- [x] Boot-path channel component in `matchDevicePath:`.
- [x] Add `KiwiATA.c` to `files.ppc`; host tests pass.
- [x] Commit: `drvPPCATA: drive the primary channel of Kiwi ATA controllers`.

The Objective-C changes were checked with a host clang syntax pass for
PowerPC using stub headers for the MIG-generated and missing system headers;
they parse, and add no warnings over the previous tree. The PPC kernel build
in Task 3 is the first real compile.

### Task 3: Drive the secondary channel

**Files:** `KiwiATA.h`, `IdeCnt.h`, `IdeCnt.m`, `IdeCntInit.m`.

- [x] The PCI node's probe publishes a description per channel through the
      bridge's `createDevice:ref:`; each is probed as a controller.
- [x] Per-channel interrupt handler that claims on the channel's bus-master
      latch, acknowledges at interrupt level, and always re-enables; attach it
      after the registers are mapped.
- [x] Drop a firmware-pending interrupt at mapping; a per-channel device path.
- [x] Host tests pass; Objective-C syntax check.
- [x] Commit: `drvPPCATA: drive both Kiwi channels through per-channel descriptions`.

### Task 4: Validate on hardware

- [ ] Build the PPC kernel. Boot an Xserve G4 (`RackMac1,1` or `RackMac1,2`)
      from a temporary disk.
- [ ] Record the probe lines, the measured PLL input, chosen modes, sustained
      disk I/O on both Kiwi functions and reboot in
      `docs/boot/ppc-macrisc-validation.md`.
- [ ] Check that the two Kiwi functions have different interrupt sources.
- [ ] Identify drives on both channels (PIO interrupts) without timeouts or a
      hang; if PIO interrupts are not latched, add Promise's per-channel
      status bit to the handler.
- [ ] Capture the Xserve device tree under each `kiwi-root` node.
