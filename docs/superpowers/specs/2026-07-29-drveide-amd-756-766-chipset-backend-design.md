# drvEIDE: AMD-756 and AMD-766 chipset back-end

**Date:** 2026-07-29

**Status:** Approved

**Component:** `src/drivers-i386/ide/drvEIDE`

## Problem

`drvEIDE` separates its SFF-8038i bus-master engine from chipset-specific
timing back-ends, but it has only Intel and generic implementations. The
generic implementation leaves firmware timings intact and deliberately avoids
UDMA on unknown hardware. It therefore cannot safely use the documented
transfer ceilings of the AMD-756 and AMD-766 peripheral bus controllers.

Add a dedicated AMD back-end for these exact PCI IDE functions:

| Controller | PCI ID | Maximum modes | Cable policy |
|------------|--------|---------------|--------------|
| AMD-756 | `1022:7409` | PIO4, MWDMA2, UDMA4 | Follow NetBSD: do not cable-gate UDMA4 |
| AMD-766 | `1022:7411` | PIO4, MWDMA2, UDMA5 | Require the documented BIOS cable bits for UDMA3-5 |

AMD-756 revisions through D2, represented by IDE-function PCI revision `3` or
lower, must not advertise MWDMA. This follows NetBSD's workaround for the AMD
erratum that can hard-hang the system in MWDMA while leaving UDMA unaffected.

## Goals

- Select AMD-756 and AMD-766 by exact PCI vendor/device ID.
- Program PIO, MWDMA, and UDMA timings through each controller's safe ceiling.
- Match NetBSD's AMD-756 transfer policy, including ungated UDMA4 and the D2
  MWDMA restriction.
- Gate AMD-766 UDMA3-5 using its documented BIOS cable bits.
- Preserve reserved fields, the sibling drive, and the sibling channel on PCI
  configuration writes.
- Keep the generic back-end as the fallback for every other PCI IDE device.
- Add deterministic register-level tests because supported hardware or a
  suitable device model is not available for runtime validation.

## Non-goals

- AMD-755, AMD-768, AMD-8111, NVIDIA-compatible derivatives, or later AMD
  controllers.
- SATA, RAID, or AHCI support.
- Changing the SFF-8038i bus-master engine or ATA command protocol.
- Changing AMD-756's cable policy to a firmware inference or a conservative
  UDMA2 cap.
- Claiming validation on physical AMD-756 or AMD-766 silicon.

## Selected approach

Add a dedicated DriverKit wrapper and a dependency-free register model:

- `IdeAMD.h` and `IdeAMD.m` own PCI matching, configuration-space access, and
  the `ideChipsetOps_t` integration.
- `AMDTiming.h` and `AMDTiming.c` own exact device lookup, ATA timing
  quantization, register snapshot calculation, reset calculation, and AMD-766
  cable-bit interpretation.

This keeps DriverKit APIs out of the timing calculations and lets standalone C
tests exercise the production register logic. Folding AMD into a future VIA
back-end was rejected even though NetBSD describes AMD 7x6 as VIA
Apollo-compatible: identification, revision handling, cable policy, and FIFO
behavior differ enough that a shared back-end would obscure the boundaries.
Direct writes entirely inside `IdeAMD.m` were rejected because complete
snapshot and preservation tests would be harder to construct.

## Back-end integration

Probe order becomes:

1. Intel back-end.
2. AMD back-end.
3. Generic PCI IDE back-end.

The chipset match context is extended narrowly to include the PCI revision
byte already read from configuration register `0x08`. `ideChipCaps_t` gains a
private per-controller value that records AMD-756 versus AMD-766. There is no
mutable process-global chipset, revision, cable, or timing state; the primary
and secondary channels are independent `IdeController` instances sharing one
PCI configuration space.

Matching performs no writes. The exact ID and revision determine capabilities:

- AMD-756 revision `<= 3`: PIO4, no MWDMA, UDMA4.
- AMD-756 revision `> 3`: PIO4, MWDMA2, UDMA4.
- AMD-766: PIO4, MWDMA2, UDMA5.

Unrecognized IDs fall through unchanged to `IdeGeneric`. A recognized AMD
controller remains AMD-specific if a later timing or cable read fails; those
failures use conservative behavior described below rather than silently
switching register models.

The existing `ideChipsetOps_t` seam remains the boundary:

- `match` identifies the controller and fills its capabilities.
- `detectCable` implements the controller-specific cable policy.
- `resetTiming` restores only the current channel to compatible timings.
- `setTiming` programs the current channel for its negotiated drive modes.

The new files are registered in both `PB.project` and the generated-era
`Makefile` source and header lists.

## Register model and ownership

The AMD back-end reads configuration bytes `0x40-0x53`. It changes only the
documented fields owned by the current controller and channel:

| Offset | Purpose | Ownership |
|--------|---------|-----------|
| `0x40` | Channel enables | Read only |
| `0x41` | Posted-write and read-prefetch controls | Preserve on AMD-756; clear current-channel controls on AMD-766 |
| `0x42` | AMD-766 BIOS cable flags | Read only |
| `0x48-0x4b` | Per-drive PIO/MWDMA active and recovery timing | Current channel |
| `0x4c` | Per-drive address setup timing | Current channel fields |
| `0x4d` | Reserved | Preserve |
| `0x4e-0x4f` | Per-channel 8-bit command timing | Current channel byte |
| `0x50-0x53` | Per-drive UDMA timing and enable | Current channel |

For `dn = channel * 2 + unit`, the byte and field mappings are reversed:

- drive active/recovery byte: `0x48 + (3 - dn)`;
- address setup field in `0x4c`: shift `(3 - dn) * 2`;
- channel command byte: `0x4e + (1 - channel)`;
- UDMA byte: `0x50 + (3 - dn)`.

Thus primary master uses `0x4b/0x53`, primary slave `0x4a/0x52`, secondary
master `0x49/0x51`, and secondary slave `0x48/0x50`.

AMD-766's PIO FIFO is treated as broken, following the historical and current
Linux AMD PATA drivers. The back-end clears only the current channel's
posted-write and read-prefetch bits in `0x41`: `0xc0` for primary or `0x30` for
secondary. AMD-756 preserves those firmware fields. No back-end path enables
either controller's FIFO policy bits.

Every update begins with a successful configuration snapshot, modifies a copy,
and writes only aligned dwords whose final value changed. Read-modify-write
preserves the sibling channel and all reserved or read-only positions.

## Timing calculation

Use ATA minimum timing requirements and a conservative 33.333 MHz PCI clock
(30 ns period). Convert nanoseconds to whole clocks by rounding upward so the
programmed timing is never faster than the selected mode. Clamp address setup
to 1-4 clocks and active/recovery fields to 1-16 clocks.

For each present drive:

- address setup comes from its selected PIO command timing;
- active/recovery data timing satisfies the stricter of selected PIO and
  MWDMA requirements;
- the channel-shared 8-bit command timing satisfies the slower requirement of
  both attached drives;
- UDMA timing is programmed independently when UDMA is selected and disabled
  otherwise.

`setTiming` treats the current channel as one transaction. It first gives both
units compatible timing and disabled UDMA, then replaces those values for each
present drive. An absent unit therefore cannot retain stale accelerated
timing, while the two present units retain their independently calculated
drive fields. The sibling channel remains untouched.

AMD's documented UDMA encoding is direct:

| Mode | Register value `bits[2:0]` |
|------|-----------------------------|
| UDMA0 | `2` |
| UDMA1 | `1` |
| UDMA2 | `0` |
| UDMA3 | `4` |
| UDMA4 | `5` |
| UDMA5 | `6` |

A selected UDMA mode sets software-controlled enable bits `7:6` and the mode
encoding. Disabling UDMA sets the owned fields to cycle value `3` with enable
bits clear while preserving read-only `bits[5:3]`.

Compatibility reset stops the current channel's BMIDE engine, restores both
current-channel drive timing bytes to PIO0 (`0xa8`), restores its address setup
fields and command timing byte to compatible values, and disables its two UDMA
bytes. It does not change the sibling channel or unrelated fields.

## Cable handling

AMD-756 always returns cable-qualified. This intentionally matches NetBSD,
which advertises UDMA4 without applying host-side cable detection. The common
core therefore does not reduce AMD-756 to UDMA2.

AMD-766 reads the BIOS-programmed cable field at `0x42[3:0]`:

- bit 0: primary master;
- bit 1: primary slave;
- bit 2: secondary master;
- bit 3: secondary slave.

Either bit for the current channel is positive evidence of that channel's
80-conductor cable. A zero field, a bit belonging only to the other channel,
or a failed PCI read returns `NO`, causing the existing common gate to cap the
channel at UDMA2. The back-end never writes the cable bits.

## Transfer-mode negotiation

The existing negotiation and recovery flow remains:

1. Read drive capabilities with IDENTIFY.
2. Intersect them with the AMD ceiling, AMD-766 cable gate, and configured
   per-drive mode masks.
3. Send SET FEATURES for the selected drive mode.
4. Program matching AMD host timing.
5. Run the existing DMA read self-test.
6. On failure, mask the failed mode, reset timings, and retry at the next lower
   mode until a working DMA mode or PIO is reached.

`getTransferModes:fromInfo:` currently scans IDENTIFY word 88 only through
UDMA2. Extend that scan through UDMA5, the highest mode already represented by
the driver's masks and required by AMD-766. No new ATA modes or command
behavior are introduced.

## Error handling

- Exact-ID matching failures fall through to `IdeGeneric` without AMD writes.
- Timing and reset programming require a complete successful snapshot before
  any write.
- A failed AMD-766 cable read is treated as a 40-wire or unknown cable and caps
  the channel at UDMA2.
- Failed configuration writes are logged and exposed operationally by the
  existing DMA self-test and mode-demotion path.
- Reset and programming never overwrite shared configuration registers with
  constants; they merge only owned fields into the snapshot.
- AMD-756 revision `<= 3` never offers MWDMA, preventing the documented
  hard-hang path while retaining PIO and UDMA.
- The driver's existing PIO floor remains available if DMA cannot be used.

## Validation

There is no physical target or emulator model for these controllers, so
validation is split into deterministic register tests and build checks.

### Pure register tests

The standalone C tests use the same `AMDTiming` functions as the driver and
cover:

- positive matching for `1022:7409` and `1022:7411`;
- rejection of nearby AMD IDs and non-AMD IDs without writes;
- AMD-756 revisions below, at, and above revision `3`;
- PIO0-4 and MWDMA0-2 rounding and clamping;
- UDMA0-5 direct encodings and enable/disable values;
- AMD-756 ungated UDMA4;
- every AMD-766 cable bit, both channels, zero bits, other-channel-only bits,
  and read failure;
- AMD-766 current-channel FIFO clearing and AMD-756 FIFO preservation;
- absent drives receiving compatible timing, mixed modes retaining distinct
  per-drive fields, channel-shared command timing, and complete sibling-channel
  preservation;
- compatibility reset for both controllers.

All snapshots use nonzero sentinel patterns. Tests compare the entire
`0x40-0x53` region so any undocumented or over-broad modification fails.

### Common mode-selection tests

Add coverage proving that IDENTIFY word 88 selects UDMA3, UDMA4, and UDMA5
when present. Verify that AMD-756 reaches UDMA4 without cable evidence and
AMD-766 remains capped at UDMA2 when its current-channel cable bits are clear.

### Build and review

- Build the standalone register test with strict C89 warnings.
- Build drvEIDE with the repository's period toolchain and project manifests.
- Review final register masks and encodings against AMD's data sheets, the
  AMD-756 revision guide, NetBSD's `viaide` implementation, and Linux's AMD
  PATA implementation.
- Report register-test, driver-build, and real-hardware validation separately.

## Expected files

| File | Change |
|------|--------|
| `IdeAMD.h`, `IdeAMD.m` | DriverKit wrapper, matching, PCI snapshot access, and ops table |
| `AMDTiming.h`, `AMDTiming.c` | Pure lookup, timing, reset, FIFO, and cable logic |
| `IdeBMIDE.h` | Revision-aware match context and per-instance private data |
| `IdePIIX.m`, `IdeGeneric.m` | Updated match signature and AMD probe insertion |
| `IdeCntInit.m` | Scan IDENTIFY UDMA support through mode 5 |
| `PB.project`, `EIDE.lksproj/Makefile` | Register new production sources and headers |
| standalone test source/build file | Pure lookup, register, cable, and mode-selection tests |

## Sources

- [AMD-766 Peripheral Bus Controller Data Sheet](https://theretroweb.com/chip/documentation/amd-766-698c47dab5cd8615719439.PDF), publication 23167B, March 2001.
- [AMD-756 Peripheral Bus Controller Revision Guide](https://theretroweb.com/chip/documentation/22591-64e7d8590ed64465091296.pdf), publication 22591C, May 2000.
- [AMD-756 Peripheral Bus Controller Data Sheet](https://static6.arrow.com/aropdfconversion/294ec654c099401a5ad996d19b423e729247ea63/22548.pdf), publication 22548B, August 1999.
- [NetBSD `viaide.c`](https://github.com/NetBSD/src/blob/trunk/sys/dev/pci/viaide.c).
- [NetBSD `pciide_apollo_reg.h`](https://github.com/NetBSD/src/blob/trunk/sys/dev/pci/pciide_apollo_reg.h).
- [Linux `pata_amd.c`](https://codebrowser.dev/linux/linux/drivers/ata/pata_amd.c.html).
