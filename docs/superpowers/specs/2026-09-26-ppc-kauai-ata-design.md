# PPC Kauai ATA Design

## Purpose

Let the in-kernel PPC ATA driver (`src/kernel-7/bsd/dev/ppc/drvPPCATA`) drive
the Kauai UltraATA/100 controller, so Intrepid-era G4 Macs can mount their
internal disk. Kauai is the `ata-6` node with `compatible = "kauai-ata"` on
UniNorth's internal PCI bus. The iBook G4, eMac (USB 2.0), iMac G4 (USB 2.0),
Mac mini G4 and aluminium PowerBook G4 keep their internal disk on it.

This is the external-driver dependency split out of the MacRISC platform plan
(`docs/superpowers/plans/2026-08-01-ppc-macrisc-platform-support.md`).

## Existing state

- The in-kernel EIDE entry in `driverkit/ppc/autoconf_ppc.m` matches
  `ide ata ATA pci1095,646` against a node's model, compatible, name and
  `device_type`. Kauai's `device_type` is `ata`, so the driver already probes
  it.
- `+probe:` recognises `keylargo-ata` (and its `ata-4` model) and the CMD646.
  Everything else is treated as Heathrow and must have exactly two memory
  ranges and two interrupts. Kauai has one PCI BAR and one interrupt, so the
  probe fails with `Invalid port ranges`.
- Mac-IO controllers use their `reg` ranges as physical addresses: task file
  registers 0x10 apart, control at 0x160, one little-endian timing register at
  0x200, and a separate DBDMA range. The CMD646 maps its PCI BARs with
  `mapMemoryRange:` and uses PCI configuration space for timing and DMA.
- Ultra DMA is only used on the CMD646, capped at mode 2.

## Hardware facts

From Linux `drivers/ata/pata_macio.c`, used as a hardware reference only:

| Item | Value |
|---|---|
| Feature control register | BAR0 + 0x0000, little-endian |
| DBDMA channel registers | BAR0 + 0x1000 |
| Task file base | BAR0 + 0x2000, same 0x10 stride and 0x160 control |
| PIO and multiword DMA timing | task file + 0x200, little-endian |
| Ultra DMA timing | task file + 0x210, little-endian |
| Enable value | `0x00000007` (magic, reset negated, enable) |

Timing words come from a fixed table, not a formula: PIO 0-4 and multiword
DMA 0-2 OR into the first register; Ultra DMA 0-5 fill the second (bit 0
enables it). Linux's power-on default, PIO 0 with multiword DMA 0, is
`0x08618a92` / `0`.

Kauai signals DMA completion through the device interrupt. The existing
`IODBDMAStop()` already flushes the channel FIFO before stopping, which covers
the "interrupt before the FIFO drains" case Linux handles.

## Design

- A pure C89 module, `KauaiATA.{h,c}` in `drvPPCATA`, holds the register
  offsets, the timing table and the cable rule. Host tests exercise it.
- `kControllerTypeKauai` joins the controller types in the driver's
  `ata_extern.h`.
- `+probe:` selects Kauai for `compatible = "kauai-ata"`. It requires at
  least one memory range covering the registers above and exactly one
  interrupt. The highest Ultra DMA mode is 5 when the node's `cable-type`
  starts with `80-`, else 2, following Linux. The CMD646 keeps its cap of 2
  through the same per-controller field.
- `assignRegisterAddresses:` maps BAR0, derives every register from it, sets
  the feature control register to the enable value, and turns on PCI memory
  space and bus mastering. It now reports failure, so an unmappable BAR fails
  initialisation instead of dereferencing garbage.
- Timing: `calcIdeConfig:` stores two byte-swapped words for Kauai;
  `setTransferRate:` writes both registers. Single-word DMA, which the table
  lacks, is timed as multiword DMA 0, as Linux does.
- Transfers use the existing DBDMA path unchanged.

## Out of scope

- DriverKit gives a device interrupts only from `AAPL,interrupts` on these
  machines. Kauai, like the Mac-IO devices, depends on the PExpert publishing
  that property; that is a separate change.
- K2 and Shasta (G5) cells, sleep and wake, and the UniNorth clock gate for
  the cell, which firmware leaves on when it boots from the disk.

## Verification

- Host tests for the timing table, invalid modes and the cable rule, under
  `-std=c89 -pedantic -Wall -Wextra -Werror`.
- A host syntax check of `KauaiATA.c`; the Objective-C glue needs the PPC
  kernel build.
- Hardware: boot an Intrepid machine from a temporary disk, confirm the probe
  line, the selected modes, sustained read/write, and a clean reboot. Record
  results in `docs/boot/ppc-macrisc-validation.md`.
