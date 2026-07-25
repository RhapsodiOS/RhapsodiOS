# drvEIDE: known issues, audit and resolutions

Audit of the i386 EIDE/ATAPI driver (`src/drivers-i386/ide/drvEIDE`) as inherited
from Apple's Darwin 0.3 drop, and the changes made to resolve them.

Two separate problems are covered:

1. **Attach failure on post-1997 PCI IDE controllers** — the driver refused to
   attach to anything outside the Intel PIIX family (§1).
2. **`ATA command ... failed` / `interrupt timeout` deadlock** — a lost interrupt
   could wedge the driver permanently, even on hardware it supported (§2).

They are independent. A machine can hit (2) without ever hitting (1), which is
what the reference failure below does.

---

## 1. Post-1997 PCI IDE controllers were rejected

### Symptom

On ICH-series and non-Intel PCI IDE controllers the driver logged

```
hcN: Unknown PCI IDE controller (0x........)
```

and failed to attach, after which the system fell back to the legacy ISA
personality (0x1f0/IRQ 14) with DMA silently disabled and no host timing
programmed.

### Root cause

`probePCIController:` matched on a hardcoded list of five PIIX device IDs and
returned `NO` for anything else, which made `initFromDeviceDescription:` free the
instance. Meanwhile `EIDE_PIIX.table` advertised `Auto Detect IDs` for ICH0–ICH4
(`0x2411`, `0x2421`, `0x244A/B`, `0x248A/B`, `0x24CA/B`), so the matcher bound the
driver to controllers the probe then rejected. In that fallback state
`_controllerID == PCI_ID_NONE`, so `getControllerCapability` advertised PIO but
left every DMA mode `NONE`, and the driver assumed edge-triggered ISA IRQ 14/15.

### Resolution

Restructured the PCI half of the driver into a generic core plus swappable
chipset back-ends:

- **`IdeBMIDE.m/.h`** (new) — chipset-independent SFF-8038i bus-master core:
  controller discovery by **PCI class code and programming-interface byte**
  instead of a device-ID allow-list, BAR4 register mapping, PRD table handling
  and the DMA engine. Relocated from `IdePIIX.m` without behaviour change.
- **`ideChipsetOps_t`** — a per-chipset op table (`match` / `setTiming` /
  `resetTiming` / `detectCable`) selected once at probe time. Adding a new
  chipset family is now one table, not a driver change.
- **`IdePIIX.m`** — reduced to the Intel back-end. Now covers PIIX, PIIX3,
  PIIX4/4E/4M **and ICH0–ICH4**, with per-chip UDMA ceilings.
- **`IdeGeneric.m`** (new) — fallback back-end claiming any bus-master-capable
  PCI IDE device. Programs no chip timing (keeps BIOS/POST timing) and offers PIO
  plus an MWDMA2 attempt that the driver's own self-test must validate.
- **Attach policy: the probe never returns `NO` for an IDE-class device.** Intel →
  Intel back-end; other bus-master IDE → generic back-end; anything else →
  legacy PIO on the same ports. This removed the whole reject-and-fall-back
  failure class.

ICH ATA/66 and ATA/100 support was added on top: the `IDE_CONFIG` register
(PCI config `0x54`) drives the UDMA mode 3–5 base-clock bits, and real
80-conductor cable detection replaced a stub that always assumed 40-wire. UDMA is
capped at mode 2 whenever an 80-wire cable is not detected.

Register semantics for `SDMA_CNT` (`0x48`), `SDMA_TIM` (`0x4a`) and `IDE_CONFIG`
(`0x54`) were verified against the *Intel 82801AA/82801AB I/O Controller Hub
Datasheet*, order number 290655-003, §9.1.16–9.1.18. That check corrected the
`SDMA_TIM` cycle-time encoding, which is **clock-dependent** rather than a plain
mode number:

```
utim = MIN(2 - (m & 1), m)        /* modes 0,1,2,3,4 -> 0,1,2,1,2 */
```

Design and implementation notes: `docs/superpowers/specs/2026-07-24-drveide-modern-controllers-design.md`
and `docs/superpowers/plans/2026-07-24-drveide-modern-controllers.md`.

---

## 2. A lost interrupt wedged the driver permanently

### Reference failure

QEMU i440fx (PIIX3 IDE present at `0x70108086`, Dev 1 Func 1), driver bound via
the **legacy non-PCI** personality, so no DMA and 16-bit PIO:

```
hd0: using multisector (16) transfers.
hc0: interrupt timeout, cmd: 0xc4
hc0: Read Multiple: error=0x0 secCnt=0x0 secNum=0x1 cyl=0x0 drhd=0xe0 status=0x58
hc0: ATA command c4 failed. Retrying...
hc0: ATA Command: error=0x0 secCnt=0x0 secNum=0x1 cyl=0x0 drhd=0xe0 status=0x58
hc0: Resetting drives...
```

Reading the state: `cmd 0xc4` is READ MULTIPLE; `status 0x58` is
`DRDY | DSC | DRQ` with `error = 0`. **The drive is holding a full sector buffer
with no error while the host waits for an interrupt.** Interrupts were working
moments earlier for IDENTIFY, SET FEATURES, SET MULTIPLE and the init-time Read
Multiple self-test, so this is not a dead IRQ line — it is a single lost
interrupt that the driver could not recover from, followed by a retry path that
made the situation permanent.

### Root cause: the unrecoverability chain

| Step | Location |
|---|---|
| The disk object caches `_ideReadCommand = IDE_READ_MULTIPLE` **once**, at init, and uses it forever | `IdeDiskInternal.m` |
| Any command failure sends `ideExecuteCmd:ToDrive:` into a retry that called full `resetAndInit` | `IdeCntCmds.m` |
| `resetAndInit` zeroes `multiSector` for every drive at the top of its per-drive loop | `IdeCntInit.m` |
| If its Read Multiple self-test then fails it sets `_multiSectorRequested = NO`, so the next pass skips SET MULTIPLE and `multiSector` stays **0** | `IdeCntInit.m` |
| The disk still issues READ MULTIPLE. The drain loop computes `nSectors = 0`, transfers **zero** bytes, `sec_cnt` never decreases, and it waits for an interrupt that cannot arrive because DRQ is still set | `IdeCntCmds.m` |

The result is a zero-progress loop: `interrupt timeout` with `DRQ=1, error=0`,
forever. One transient lost interrupt was enough to convert a working drive into
a permanently failing one. The same pattern existed in `ideWriteMultiple`.

The polled-mode fallback added in §1 did **not** catch this: its probe-time health
check uses READ VERIFY, which has no data/DRQ phase, so a data-block interrupt
loss passes the check.

### Findings and resolutions

| ID | Severity | Finding | Resolution |
|---|---|---|---|
| A | Critical | `multiSector == 0` with a Multiple command → zero-progress drain loop, permanent hang | A `blockSize` local is captured once and the command is rejected with `IDER_REJECT` if it is zero, so the loop can never spin |
| B | Critical | Disk's cached read/write command goes stale against controller state after any re-init | Command is re-derived from `isDmaSupported:`/`isMultiSectorAllowed:` per request, **and** `ideExecuteCmd:ToDrive:` re-qualifies it against the drive's live state each retry (DMA→PIO, MULTIPLE→single). The cached ivars were removed |
| C | Important | No interrupt-loss recovery for PIO. Only the DMA path had a "trust the controller" escape | New `-recoverFromLostInterrupt:command:`: after a timeout, if `BSY` is clear the command *did* complete, so acknowledge it, latch polled mode (logged once) and return success. Both timeout branches route through it |
| D | Important | `resetAndInit` as the retry action re-negotiated capabilities, ran self-tests, clobbered `_driveNum` and mutated shared state under the in-flight request | New lightweight `-recoverDrives`: reset, then re-apply only the already-negotiated drive params, transfer mode and multi-sector block size (all cleared by a software reset). Full `resetAndInit` is now escalated to only before the **final** retry, so mode demotion still gets one chance |
| E | Moderate | The legacy/unknown-controller path advertised **PIO mode 4** and SET-FEATURES'd the drive into it with no host timing programmed and 16-bit PIO — modes 3/4 require host IORDY | Re-enabled the existing (but `#if 0`'d) `"IOCHRDY Support"` config key, which already ships in all four config tables. Without it the legacy ceiling is now PIO mode 2 |
| F | Minor | `setATADriveCapabilities:` passed an uninitialised `ideRegsVal_t`; `ideReadGetInfoCommon:` reads `sectCnt` from it before assignment | `bzero` before first use |
| G | Minor | `_multiSectorRequested` is a per-controller *user option*, but a self-test failure on one drive set it to `NO`, disabling multisector on the other drive and discarding the user's setting | New per-drive `multiSectorDisabled` flag carries the disable; `_multiSectorRequested` is no longer written at runtime |

Two further defects were found while auditing the §1 work and are fixed on the
same branch:

- `-free` released the PRD table only for the five PIIX device IDs, leaking a page
  per free on ICH and generic controllers (which allocate it too).
- `bmInitPRDTable`'s error path freed the table without clearing `_prdTable.ptr`,
  leaving a latent double-free.

### Why the reference failure no longer wedges

Fix **C** is the direct remedy: on interrupt timeout the driver now checks the
drive, finds `BSY=0`, drains the block that was already waiting, and switches to
polled mode instead of failing. Fixes **A** and **B** remove the zero-progress
loop that made the failure permanent, and **D** stops the retry path from
destroying the configuration it is supposed to be recovering.

---

## 3. Verification status

**None of this has been built or run.** The development host has no
Rhapsody/DR2 toolchain, and no emulator exposes an ICH PATA controller. Every
change above is code-review-verified only — each landed through an independent
review that checked it against its requirements, and four real defects were
caught and fixed that way (bus-master capability latching, a generic-path
`return NO`, an `IDE_CONFIG` write being clobbered by a config-space snapshot
write-back, and a missing `Makefile` source registration that would have broken
the link outright).

Before trusting this driver:

1. **Build in-target** — `make` in the drvEIDE project directory under the period
   toolchain on a case-sensitive filesystem.
2. **PIIX regression** — boot on QEMU i440fx / VMware / VirtualBox with
   `"Debug" = "Yes"`, on a throwaway disk image. Expect the same transfer mode as
   before and a clean mount, with no `interrupt timeout` and no
   `ATA command ... failed` lines.
3. **ICH** — datasheet-verified and protected at runtime by the transfer self-test
   and the PIO fallback ladder, but never executed on real silicon.

Useful when diagnosing: set `"Debug" = "Yes"` in the driver's config table for the
extra `_ide_debug` logging, and note that a `using polled mode` line means the
driver detected undelivered interrupts and degraded deliberately.

### Worth trying on the reference QEMU setup

The failing boot bound the **legacy non-PCI** personality, so none of the §1 PCI
work was in play. Booting with `EIDE_PIIX.table` (`"Bus Type" = "PCI"`) instead
engages the PIIX3 back-end, bus-master DMA and 32-bit PIO, which bypasses the PIO
multisector path entirely.

---

## 4. Change history

Commits on `drveide-modern-controllers`, oldest first.

Modern controller support (§1):

| Commit | Change |
|---|---|
| `74666a86` | chipset-ops seam types and controller state |
| `3fccf588` | split generic SFF-8038i DMA core out of IdePIIX into IdeBMIDE |
| `feb9426d` | drive PIIX timing through the chipset-ops back-end |
| `4d301cbf` | advertise bus-master DMA only if bus-master init succeeded |
| `9938c022` | attach to any PCI IDE via class-code discovery + generic back-end |
| `84712b97` | guard PIIX IDETIM and IRQ 14/15 checks to Intel-only |
| `fae67292` | polled-mode fallback for missing IDE interrupts |
| `f0b92a19` | program ICH UDMA/66/100 timing and detect 80-wire cable |
| `73341019` | fix IDE_CONFIG write being clobbered by snapshot write-back |
| `85fb8588` | gate UDMA by cable type and per-chip ceiling |
| `086a41ec` | fix Makefile missing new sources, PRD table leak on free, dead ivar |
| `2291f726` | null PRD table pointer on init failure to avoid double-free |

Hang fixes (§2):

| Commit | Findings |
|---|---|
| `18cde3f5` | A, B — re-qualify command against live drive state |
| `248d3167` | C — recover from lost/misrouted interrupts on PIO timeout |
| `b4d49e08` | D — lightweight `recoverDrives` in the command retry path |
| `12907a6e` | E, F, G — legacy PIO cap, zeroed taskfile, per-drive multisector disable |
| `61886ca9` | D — escalate to full reinit before the final retry so a failing mode still demotes |
