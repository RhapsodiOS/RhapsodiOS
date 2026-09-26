# PPC Kauai ATA Implementation Plan

**Goal:** The in-kernel PPC ATA driver probes and drives the Kauai
UltraATA/100 controller. Design:
`docs/superpowers/specs/2026-09-26-ppc-kauai-ata-design.md`.

**Ground rules:** C89 for the pure module; 1999 Objective-C for the glue;
one commit per task with a `drvPPCATA:` prefix and no metadata; host tests
under `-std=c89 -pedantic -Wall -Wextra -Werror`.

### Task 1: Kauai timing and cable helpers

**Files:** create `src/kernel-7/bsd/dev/ppc/drvPPCATA/KauaiATA.h`,
`KauaiATA.c`, `tests/kauai_ata_test.c`, `tests/Makefile.host`.

- [x] Write the test first: PIO 0-4, multiword 0-2 and Ultra 0-5 words;
      PIO 0 with no DMA equals Linux's default `0x08618a92` / `0`; invalid
      modes and null outputs fail; `cable-type` `80-conductor` allows Ultra 5,
      anything else (including absent or unterminated) allows 2.
- [x] Implement `KauaiTimingWords()` and `KauaiMaxUltraMode()`; run the tests.
- [x] Commit: `drvPPCATA: add Kauai timing tables`.

### Task 2: Drive the Kauai controller

**Files:** `ata_extern.h`, `IdeCnt.h`, `IdeCnt.m`, `IdeCntInit.h`,
`IdeCntInit.m`, `src/kernel-7/conf/files.ppc`.

- [x] Add `kControllerTypeKauai`, the Kauai timing words to the
      `ideConfig` union, and a per-controller Ultra DMA cap.
- [x] Probe: select Kauai, check one interrupt and a large enough range 0,
      read `cable-type`; CMD646 keeps cap 2.
- [x] `assignRegisterAddresses:` returns `BOOL`; map BAR0, enable the cell
      and PCI bus mastering for Kauai.
- [x] Ultra DMA selection covers Kauai; extend the mode table to mode 5.
- [x] `calcIdeTimingsKauai:` and the two-register write in
      `setTransferRate:`.
- [x] Add `KauaiATA.c` to `files.ppc`; host tests pass; host syntax check of
      `KauaiATA.c`.
- [x] Commit: `drvPPCATA: drive the Kauai UltraATA/100 controller`.

The Objective-C changes could not be compiled here: the driver needs
MIG-generated and architecture-selected kernel headers that are not in the
tree. `KauaiATA.c` passes the host tests and a PowerPC syntax check; the PPC
kernel build in Task 3 is the first compile of the glue.

### Task 3: Validate on hardware

- [ ] Build the PPC kernel. Boot an Intrepid machine (iBook G4, eMac,
      iMac G4 USB 2.0 or Mac mini G4) from a temporary disk once the
      `AAPL,interrupts` change lands.
- [ ] Record the probe line, chosen PIO/DMA modes, sustained disk I/O and
      reboot in `docs/boot/ppc-macrisc-validation.md`.
