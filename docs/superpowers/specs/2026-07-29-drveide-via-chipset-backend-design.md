# drvEIDE: VIA VT82C5xx/VT82C686A chipset back-end

**Date:** 2026-07-29

**Status:** Approved

**Component:** `src/drivers-i386/ide/drvEIDE`

## Problem

`drvEIDE` now separates the standard SFF-8038 bus-master engine from thin
chipset timing back-ends, but it has only Intel and generic implementations.
The generic implementation deliberately leaves chipset-specific timing at the
firmware settings and therefore cannot safely use the full transfer ceilings of
VIA's early PCI IDE southbridges.

Add a VIA back-end for these exact controllers:

| Southbridge | IDE function | Companion function 0 | Maximum modes |
|-------------|--------------|----------------------|---------------|
| VT82C586    | `1106:1571`  | `1106:0586`, rev `00-0f` | PIO4, MWDMA2 |
| VT82C586A   | `1106:0571`  | `1106:0586`, rev `20-2f` | PIO4, MWDMA2, UDMA2 |
| VT82C596A   | `1106:0571`  | `1106:0596`, rev `00-0f` | PIO4, MWDMA2, UDMA2 |
| VT82C686A   | `1106:0571`  | `1106:0686`, rev `10-2f` | PIO4, MWDMA2, UDMA4 |

The revision ranges follow the historical Linux VIA IDE table. The primary
datasheets establish the device IDs, register layouts, and transfer ceilings.
Unknown revisions are intentionally not inferred to be equivalent.

## Goals

- Select the exact VIA variant without confusing controllers that share the
  `1106:0571` IDE function ID.
- Program PIO, MWDMA, and UDMA timings through each supported chipset's full
  documented ceiling.
- Preserve reserved fields, firmware policy fields, the sibling drive, and the
  sibling channel on every PCI configuration write.
- Keep the existing generic back-end as the fail-closed path for incomplete or
  unknown identification.
- Add deterministic register-level tests because no supported VIA hardware or
  device model is available for runtime validation.

## Non-goals

- VT82C596B, VT82C686B, later VIA southbridges, or non-VIA chipsets.
- SATA or AHCI support.
- Blindly enabling UDMA66 when an 80-conductor cable cannot be inferred.
- Reworking the SFF-8038 bus-master engine or ATA command layer.
- Claiming real-hardware validation.

## Selected approach

Identify the southbridge using the IDE function together with function 0 of
the same PCI multifunction device. This is preferable to either relying on the
IDE revision alone or scanning the bus for an unrelated VIA ISA bridge.

The device description supplies the IDE function's bus/device/function
coordinates. `PCIKernBus` already supports arbitrary PCI configuration reads,
so the matcher reads vendor/device and revision from function 0 at the same bus
and device number. Matching performs no writes.

Probe order is:

1. Intel back-end.
2. VIA back-end.
3. Generic PCI IDE back-end.

If the PCI bus cannot be found, either configuration read fails, the IDE ID is
wrong, or the companion ID/revision is outside the table, VIA returns `NO` and
the generic back-end handles the controller without VIA register writes.

## Back-end integration

Add `IdeVIA.h` and `IdeVIA.m` alongside `IdePIIX` and `IdeGeneric`, and add them
to both `PB.project` and the generated-era `Makefile` source/header lists.
`IdeVIA.h` owns VIA IDs, register offsets, masks, and the public ops symbol;
`IdeVIA.m` owns matching, capabilities, cable inference, reset, and timing
programming.

The selected VIA variant is stored per `IdeController` instance. There must be
no mutable process-global variant or timing state: primary and secondary
channels are separate driver instances and may initialize independently while
sharing one PCI configuration space.

The existing `ideChipsetOps_t` seam remains the boundary:

- `match` identifies the exact variant and fills PIO/MWDMA/UDMA ceilings.
- `detectCable` performs the pre-reset VT82C686A cable inference.
- `resetTiming` returns only the current channel to compatible timings.
- `setTiming` computes and programs timing for the current channel's drives.

The common probe must pass enough PCI device-description context to `match` for
the companion-function lookup. This should be a narrow signature extension,
not VIA-specific logic in the BMIDE core.

## Register model

The back-end uses the common VIA IDE timing register family:

| Offset | Purpose |
|--------|---------|
| `0x40` | Channel enable state; read only by this back-end |
| `0x43` | FIFO configuration; variant-dependent |
| `0x48-0x4b` | Per-drive active/recovery timing |
| `0x4c` | Per-drive address setup timing fields |
| `0x4d` | VT82C586 half-clock control; reserved on later chips |
| `0x4e-0x4f` | Per-channel 8-bit command timing |
| `0x50-0x53` | Per-drive UDMA timing on UDMA-capable variants |

For `dn = channel * 2 + unit`, the VIA byte mapping is deliberately reversed:

- drive active/recovery byte: `0x48 + (3 - dn)`;
- two-bit setup field in `0x4c`: shift `(3 - dn) * 2`;
- channel 8-bit command byte: `0x4e + (1 - (dn >> 1))`;
- UDMA byte: `0x50 + (3 - dn)`.

Every update starts from a configuration snapshot and changes only masks owned
by the current variant and channel. The sibling channel's bytes and shared
register fields survive unchanged.

## Timing calculation

Use ATA minimum timing requirements and a conservative 33.333 MHz PCI clock
(30 ns period) to convert nanoseconds to whole PCI clocks, rounding up so the
programmed timing is never faster than the requested mode. These southbridges
target conventional PCI at no more than that rate, and the existing DriverKit
interfaces do not expose a reliable measured PCI clock; a slower actual bus
only lengthens the programmed times. Use a 15 ns period for the VT82C686A's
explicit 66 MHz UDMA clock. Clamp the result to the chipset field width. A pure
timing helper will be shared by the driver and register tests so the tests
exercise the production encoding rather than a duplicate formula.

For each present drive:

- Address setup comes from the selected PIO command timing.
- Active/recovery data timing satisfies the stricter of the selected PIO and
  MWDMA requirements.
- The channel-shared 8-bit command timing satisfies the slower requirement of
  both attached drives.
- UDMA timing is programmed independently when UDMA is selected and disabled
  otherwise.

Compatibility reset programs conservative whole-clock PIO timings, disables
UDMA for the current channel, and leaves unrelated fields intact. Cable state
must be captured before this reset because the VT82C686A inference uses the
firmware's pre-existing UDMA programming.

## Variant-specific behavior

### VT82C586

- Advertise PIO4 and MWDMA2; advertise no UDMA.
- Maintain the early FIFO allocation in `0x43[6:5]`. Derive the split from the
  channel-enable bits in `0x40`: give all entries to the sole enabled channel,
  or use the documented 8/8 split when both channels are enabled.
- `0x4d` contains per-drive half-clock controls only on this variant. Clear the
  current channel's fields and use whole-clock timing encodings. This trades a
  small amount of theoretical granularity for explicit, testable behavior.
- Never access `0x50-0x53` as UDMA timing registers.

### VT82C586A

- Advertise PIO4, MWDMA2, and UDMA2.
- Maintain the same early FIFO split fields as the VT82C586.
- Preserve `0x4d`; it is reserved on this variant.
- Use the documented two-bit UDMA33 cycle field in each byte of `0x50-0x53`:
  encodings `0..3` represent `2T..5T`. Select software control and enable only
  for a selected UDMA mode, while preserving reserved/read-only bits.

### VT82C596A

- Advertise PIO4, MWDMA2, and UDMA2.
- Preserve `0x43`; its layout is no longer the early FIFO split control.
- Preserve `0x4d`.
- Use the later three-bit UDMA33 cycle field. Preserve the positions identified
  by the datasheet revision notes as reserved rather than treating them as
  clock-source controls.

### VT82C686A

- Advertise PIO4, MWDMA2, and UDMA4 before cable qualification.
- Preserve `0x43`, `0x4d`, `0x44`, and `0x54`; the back-end does not own their
  threshold, reserved, host-behavior, or FIFO policy fields.
- Use the three-bit UDMA timing field and its per-channel 33/66 MHz clock-source
  bit. UDMA0-2 uses the valid 33 MHz encoding. UDMA3-4 uses the 66 MHz source
  and a rounded-up valid cycle encoding.
- There is no direct cable-present register. Infer an 80-conductor cable only
  when the firmware's pre-reset per-channel UDMA configuration supplies the
  same positive evidence used by the historical Linux driver: 66 MHz clock
  selection plus enabled high-speed UDMA timing on at least one channel drive.
  Missing or ambiguous evidence returns `NO`, limiting the common core to
  UDMA2. False negatives are acceptable; unsafe UDMA66 enablement is not.

## Transfer-mode negotiation

The common mode flow remains:

1. Read drive capabilities with IDENTIFY.
2. Intersect them with the VIA variant ceiling, cable gate, and existing
   master/slave mode-mask configuration.
3. Send SET FEATURES for the chosen drive mode.
4. Program the matching VIA host timing.
5. Run the existing DMA read self-test.
6. On failure, mask the failed mode, reset timings, and retry at the next lower
   mode until a working DMA mode or PIO is reached.

`getTransferModes:fromInfo:` currently scans IDENTIFY word 88 only through
UDMA2. Extend that scan through UDMA5, the highest mode represented by the
driver's existing masks. Without this focused common fix the VT82C686A could
never reach its UDMA4 ceiling even with correct host timing and cable evidence.

No new transfer modes or ATA protocol behavior are introduced.

## Error handling

- Identification failures are non-fatal and fall through to `IdeGeneric`.
- No VIA timing register is written until exact identification succeeds.
- Timing programming requires a successful configuration read before the
  corresponding read-modify-write. Failed accesses are logged and left for the
  existing DMA self-test/demotion path to expose operationally.
- Reset and programming never overwrite a full shared register with a constant.
- A controller that cannot prove an 80-conductor cable is capped at UDMA2.
- The driver retains its existing PIO floor rather than refusing an IDE-class
  device solely because VIA-specific acceleration is unavailable.

## Validation

There is no physical target or emulator/device model for these VIA southbridges,
so validation is split into deterministic register tests and build checks.

### Pure register tests

Feed synthetic PCI configuration snapshots into the same computation helpers
used by `IdeVIA.m`, then compare the complete changed region byte-for-byte.
Cover:

- all four positive companion ID/revision cases;
- both ends of every accepted revision range;
- the revision immediately below and above every range;
- mismatched IDE IDs, companion IDs, BDF/function relationships, and failed
  reads falling through without writes;
- PIO0-4 and MWDMA0-2 rounding/clamping at representative PCI clock periods;
- VT82C586 and VT82C586A FIFO allocation for primary-only, secondary-only, and
  dual-channel enablement;
- VT82C586 current-channel half-clock clearing with the sibling fields intact;
- VT82C586A two-bit UDMA encodings;
- VT82C596A three-bit UDMA33 encodings and reserved-bit preservation;
- VT82C686A 33/66 MHz selection, UDMA4 timing, positive cable inference, and
  conservative UDMA2 fallback;
- absent drives, mixed modes on a channel, sibling drive preservation, and
  sibling channel preservation;
- reset snapshots for every variant.

Use sentinel patterns in all unowned bytes and bits so an over-broad write is a
test failure.

### Common mode-selection tests

Add coverage proving that IDENTIFY word 88 selects UDMA3, UDMA4, and UDMA5 when
present, while controller ceilings and a negative cable result still cap the
negotiated mode correctly.

### Build and review

- Build the driver with the repository's period toolchain/project manifests.
- Review generated register masks and encodings against the four primary VIA
  datasheets and the historical Linux implementation.
- State explicitly in the implementation handoff that real silicon remains
  untested.

## Files expected to change

| File | Change |
|------|--------|
| `IdeVIA.h` | VIA IDs, variants, offsets/masks, timing-helper declarations, ops symbol |
| `IdeVIA.m` | Matching, capability selection, cable inference, reset, and timing programming |
| `IdeBMIDE.h` | Narrow match-context adjustment if required for companion PCI access |
| `IdeBMIDE.m` | Insert VIA between Intel and generic selection; no VIA timing policy |
| `IdeCnt.h` | Per-instance VIA variant/cached state only if it cannot live in existing capability storage |
| `IdeCntInit.m` | Scan IDENTIFY UDMA support through mode 5 |
| `PB.project`, `Makefile` | Add VIA source/header |
| register-test source/build file | Pure match/timing/snapshot tests |

Exact test-file placement will follow the repository's build conventions during
implementation planning. No unrelated driver behavior or configuration tables
need to change.

## Risks and mitigations

- **Shared IDE ID selects the wrong layout.** Require function 0 at the same BDF
  and an accepted companion revision; otherwise use generic.
- **Primary and secondary instances clobber each other.** Keep variant state per
  instance and test full snapshots with sentinel sibling fields.
- **Datasheet generations reuse offsets with different meanings.** Encode four
  explicit variants; in particular distinguish VT82C586 `0x4d`, VT82C586A
  two-bit UDMA, and later three-bit UDMA.
- **Cable inference produces a false negative.** Performance falls to UDMA2,
  which is safe on a 40-conductor cable.
- **Timing formula or documentation interpretation is wrong.** Use rounded-up
  calculations, complete-snapshot tests, DMA self-test demotion, and review
  against primary documents.
- **No hardware validation.** Do not present register tests as proof of silicon
  behavior; retain the generic/PIO safety floor and document the limitation.

## References

- [VT82C586 register documentation](https://dosdays.co.uk/media/via/VIA_82C580.pdf)
- [VT82C586A datasheet](https://theretroweb.com/chip/documentation/vt82c586a-pci-integrated-periph-ctlr-199610-64542f279ad96450212023.pdf)
- [VT82C596A datasheet excerpt](https://theretroweb.com/chip/documentation/vt82c596a-etc-648648e14242a315109703.pdf)
- [VT82C686A datasheet, revision 1.82](https://theretroweb.com/chip/documentation/vt82c686a-sb-datasheet-rev-1-82-64c95b54c31db013951220.pdf)
- [Historical Linux 2.4 VIA IDE back-end](https://www.kernel.org/pub/linux/kernel/people/marcelo/linux-2.4/drivers/ide/via82cxxx.c)
