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

### QEMU trace evidence: IRQ 14 is never reasserted after the failing command

Reproduced under `vm/start-vm.cmd -trace` (`ide_*`/`pci_cfg_*` trace events plus
`-d int`), correlated against the guest console captured headlessly with
`vm/qemu-shot.py`, sampled to 140s wall-clock. Three candidate mechanisms were
in play: (a) QEMU never raises IRQ 14 again after the failing command; (b) it
raises it but the driver never reads the primary Status register to acknowledge
it; (c) the driver sets `nIEN` (bit 1 of the Device Control register, port
`0x3F6`) and leaves it set.

**(c) is ruled out.** The `ide_ctrl_write` immediately before the failing
command is issued clears the Device Control register, not sets it:

```
ide_ctrl_write IDE PIO wr @ 0x3f6 (Device Control); val 0x00; bus 000002bcfa720b40
ide_ioport_write IDE PIO wr @ 0x1f7 (Command); val 0xc4; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
ide_bus_exec_cmd IDE exec cmd: bus 000002bcfa720b40; state 000002bcfa720bc8; cmd 0xc4
ide_sector_read sector=97120 nsectors=16
```

`nIEN` is clear (`val 0x00`, interrupts enabled) at the moment the fatal Read
Multiple is issued.

**The trace supports (a).** QEMU's PIC emulation logs `Servicing hardware
INT=0x4e` every time it actually delivers IRQ 14 to the CPU (identified by
correlation: this line fires immediately after every *successful* `cmd 0xc4`'s
`ide_sector_read`, 25 times total across the boot). The last one appears two
lines before the setup for the command that hangs:

```
ide_sector_read sector=97488 nsectors=2
Servicing hardware INT=0x4e
```

That is the last IRQ 14 ever delivered in the entire trace. After it, the
driver sets up and issues the command that wedges (`sector=97120 nsectors=16`,
matching the console's `secNum=0x70 cyl=0x17b` after the 16-sector
auto-increment), and `Servicing hardware INT=0x4e` does not appear again
anywhere in the remaining ~205,000 lines — through the timeout, the software
reset, the IDENTIFY retry, and a subsequent RECALIBRATE retry. This is not a
general interrupt-delivery failure: IRQ 0 (`Servicing hardware INT=0x40`) fires
over 10,000 more times, and one IRQ 15 (`0x4f`) fires, in that same span, so the
PIC and CPU interrupt path are demonstrably still live.

During the timeout the driver's poll loop also only ever reads the **Alternate**
Status register at `0x3F6`, never the primary Status register at port `0x1F7`:

```
ide_ioport_read IDE PIO rd @ 0x1f6 (Device/Head); val 0xe0; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
ide_status_read IDE PIO rd @ 0x3f6 (Alt Status); val 0x58; bus 000002bcfa720b40; IDEState 000002bcfa720bc8
```

repeated twice before the driver gives up and writes SRST
(`ide_ctrl_write ... val 0x04`, producing the console's `Resetting drives...`).
Reading Alt Status does not clear a pending INTRQ per the ATA spec, so this is
a real, independently worth-fixing gap in the timeout path. That gap does not,
however, leave room for a competing theory in which the wedge is really a
*stale*, unacknowledged INTRQ left over from the previous command rather than
QEMU failing to reassert the line for this one. On an edge-triggered ISA IRQ,
the device only deasserts INTRQ when the host reads the **primary** Status
register at `0x1F7`; reading Alternate Status (`0x3F6`) does not. Had the
driver's interrupt handler never read `0x1F7` for the *preceding* command, the
line would have stayed asserted and no new edge could ever be generated for
the next one — a failure mode that looks identical to (a) in the
interrupt-timeout evidence alone. It did not: immediately after the last
`Servicing hardware INT=0x4e` at line 1748253, the driver's handler for that
(successful) command reads primary Status:

```
1748273: ide_ioport_read IDE PIO rd @ 0x1f7 (Status); val 0x58; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
```

That is the correct acknowledgement register, so INTRQ was properly deasserted
going into the command that hangs. A stale, unread INTRQ is therefore ruled
out as the cause of the missing interrupt. The evidence points at (a): the
device model itself stops reasserting the line for the failing command, rather
than the driver missing an interrupt that was actually raised or leaving a
prior one unacknowledged. It does not explain *why* QEMU's IDE model stops —
nothing in the `ide_*`/`-d int` trace surface used here exposes the model's
internal DRQ/INTRQ bookkeeping, so the §2 sector-vs-block accounting
hypothesis remains plausible but unconfirmed. This is TCG-emulated PIIX3 IDE
only; real hardware is not addressed by this trace.

### Addendum: was SET MULTIPLE MODE (0xC6) ever issued?

The console prints `hd0: using multisector (16) transfers.`, which only
happens if the driver believes multi-sector transfers were successfully
negotiated. That requires **SET MULTIPLE MODE** (`0xC6`) to have been issued
first — QEMU's IDE model tracks the negotiated block size in `mult_sectors`,
and a READ MULTIPLE (`0xC4`) issued without a prior, accepted `0xC6` is
operating against an unconfigured value.

**`0xC6` was issued, once, on the primary channel.** Searching the full trace
for `ide_bus_exec_cmd` events with `cmd 0xc6`, and for `0x1f7 (Command)`
writes with `val 0xc6`, both find exactly one hit, at line 1694036 (port
write at line 1694035):

```
1694035: ide_ioport_write IDE PIO wr @ 0x1f7 (Command); val 0xc6; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
1694036: ide_bus_exec_cmd IDE exec cmd: bus 000002bcfa720b40; state 000002bcfa720bc8; cmd 0xc6
```

The Sector Count register (`0x1F2`), which for `0xC6` carries the requested
block size, was written immediately before it:

```
1694033: ide_ioport_write IDE PIO wr @ 0x1f2 (Sector Count); val 0x10; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
```

`0x10` = 16, matching the console's "multisector (16)". The command also
completed cleanly: an IRQ 14 fires immediately (`Servicing hardware
INT=0x4e`, line 1694037) and the following Status reads are `0x50`
(`DRDY | DSC`, no `ERR`, no `DRQ`) — a normal successful completion, not a
rejection.

**This weakens, rather than supports, the "multisector was never configured"
explanation.** `0xC6` was issued once, accepted, and matches the sector count
the driver later uses. It is not the case that `0xC4` is being sent to a
device with `mult_sectors` unset.

For the record, what QEMU's model did immediately after the fatal `0xc4` at
line 1748798 (`ide_bus_exec_cmd`, cmd 0xc4) — the next `ide_*` trace event of
any kind does not appear until line 1808840, roughly 60,000 lines later, when
the driver's timeout handler starts polling:

```
1748798: ide_bus_exec_cmd IDE exec cmd: bus 000002bcfa720b40; state 000002bcfa720bc8; cmd 0xc4
1748799: ide_sector_read sector=97120 nsectors=16
1808840: ide_ioport_read IDE PIO rd @ 0x1f1 (Error); val 0x00; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
1808841: ide_ioport_read IDE PIO rd @ 0x1f2 (Sector Count); val 0x00; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
1808842: ide_ioport_read IDE PIO rd @ 0x1f3 (Sector Number); val 0x70; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
1808843: ide_ioport_read IDE PIO rd @ 0x1f4 (Cylinder Low); val 0x7b; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
1808844: ide_ioport_read IDE PIO rd @ 0x1f5 (Cylinder High); val 0x01; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
1808845: ide_ioport_read IDE PIO rd @ 0x1f6 (Device/Head); val 0xe0; bus 000002bcfa720b40 IDEState 000002bcfa720bc8
1808846: ide_status_read IDE PIO rd @ 0x3f6 (Alt Status); val 0x58; bus 000002bcfa720b40; IDEState 000002bcfa720bc8
```

So on this trace surface QEMU does not abort the command, does not report an
error, and generates no further logged IDE bus activity at all after setting
up the sector read — it is simply silent (`ide_*` trace points do not cover
internal DRQ/`mult_sectors` state transitions). When the driver eventually
polls, the device is still sitting at `DRDY | DSC | DRQ`, unchanged from the
state described earlier in this section. This is consistent with, but does
not by itself prove, an internal `mult_sectors`/block-boundary accounting
issue in QEMU's read-multiple path — a hypothesis to be tested by Task 7
(disable multi-sector transfers), not an established conclusion here.

### Task 7 result: disabling multi-sector transfers does not fix the boot

`vm/rhap_inject.py set-key` was used to flip `"Multiple Sectors"` from
`"Yes"` to `"No"` in
`/private/Drivers/i386/EIDE.config/Instance0.table` on a reset working
image, and the guest was booted headlessly with `vm/qemu-shot.py`,
capturing the VGA console out to 180 seconds.

The write landed and took effect: the console now prints `hd0: using
single sector transfers.` in place of `hd0: using multisector (16)
transfers.`, confirming the driver reads the table key rather than
falling back to a compiled-in default.

**The guest still does not boot — outcome 2, a different failure.** The
`0xC4` (READ MULTIPLE) timeout is gone, but a new one appears on `0x20`
(READ SECTOR(S)) shortly afterward:

```
hd0: using single sector transfers.
...
rootdev 300, howto 40000
hc0: interrupt timeout, cmd: 0x20
hc0: ATA command 20 failed. Retrying...
hc0: ATA Command: error=0x0 secCnt=0xd secNum=0x53 cyl=0x5 drhd=0xe0 status=0x58
hc0: Resetting drives...
hc0: interrupt timeout, cmd: 0xec
hc0: ATA drive 0 is not present.
```

After this the driver cycles indefinitely through `RESTORE` (`0x10`),
`READ SECTOR(S)` (`0x20`) and drive resets, each attempt timing out the
same way, with no further progress visible through 180 seconds.

**Reading:** the multisector hypothesis was at least partly right — the
specific command that stops getting an IRQ changed from `0xC4` to `0x20`
once multi-sector was disabled — but the underlying mechanism is not
command-specific. Something about the driver's read path past
`rootdev`/root-mount time stops receiving IRQ 14 regardless of which read
command it uses. This does **not** change Tasks 8-11: the sacrificial-inode
graft and rebuilt-driver injection plan stands, since no config-table
workaround alone resolves the wedge.

### Task 9 result: the rebuilt driver survives longer, but multisector still wedges

The i386 `drvEIDE` (findings A-G above) was built on the PPC toolchain host
as unstripped `kl_ld` output (`EIDE_reloc`, 856,404 bytes — about 7x the
stock 121,056-byte binary; the userspace `PostLoad` helper did not link on
that host, so only `EIDE_reloc` was replaced). It replaced the image's
installed **`drvEIDE-28` / version `5.01`** (`Instance0.table`'s `Driver
Version` string: `PROGRAM:EIDE PROJECT:drvEIDE-28 DEVELOPER:root
BUILT:Sat Mar 28 22:23:22 PST 1998`). Since it exceeds the target's
121,856-byte writable bound, it was installed via the sacrificial-inode
graft from Task 8, onto `InterfaceBuilderGuide.pdf` (kept separate from the
donor Task 11 uses for the kernel), and verified byte-for-byte identical
after a read-back.

**With `"Multiple Sectors" = "No"`**, the rebuilt driver's boot trace is
identical to Task 7's stock-driver baseline: `using single sector
transfers.`, then `hc0: interrupt timeout, cmd: 0x20` shortly after
`rootdev 300, howto 40000`, cycling through resets/retries with no boot
inside 180 seconds. The larger unstripped binary loads and runs with no
regression.

**With `"Multiple Sectors" = "Yes"` — the real test — the driver gets
substantially further before wedging, but still wedges.** `hd0: using
multisector (16) transfers.` appears and, unlike the original reference
failure (which hangs on the very next `0xC4`), the boot continues through
device-attribute printing, serial/keyboard/PCI/EISA registration, and into
`rootdev 300, howto 40000` — all without an interrupt timeout. The wedge
then reappears at the start of root-device I/O, with the same signature as
the original reference failure: `hc0: interrupt timeout, cmd: 0xc4`,
`status=0x58` (`DRDY|DSC|DRQ`, `error=0x0`), followed by the same permanent
reset/retry cycle (`RESTORE`/`READ MULTIPLE`/`ATA drive 0 is not present`)
with no progress through 180 seconds.

**Reading:** findings A-G's recovery logic (particularly C,
`-recoverFromLostInterrupt:command:`) lets the boot survive well past where
the stock driver hung, but does not fix the root cause QEMU's IDE trace
identified — IRQ 14 simply stops being reasserted for a `cmd: 0xc4`, and no
amount of driver-side recovery logic can wait out an interrupt the device
model never raises. The serial console in Tasks 10-11 remains the priority
for `IOLog` visibility into exactly where in `-recoverFromLostInterrupt:` or
the retry path this instance of the wedge is being hit.

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
