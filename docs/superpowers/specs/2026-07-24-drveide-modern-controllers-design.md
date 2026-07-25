# drvEIDE: Support for post-1997 (ICH-class) EIDE controllers

**Date:** 2026-07-24
**Status:** Design approved, pending spec review
**Component:** `src/drivers-i386/ide/drvEIDE`

## Problem

The i386 EIDE driver fails on many EIDE controllers newer than ~1997, reporting
`ATA command <x> failed. Retrying...` and `interrupt timeout, cmd: 0x...`, and
often failing to boot.

### Root cause

The driver's PCI path is hardcoded to the Intel PIIX family only.
`probePCIController` (`IdePIIX.m`) switches on the PCI device ID and accepts only
`PIIX / PIIX3 / PIIX4 / PIIX4E / PIIX4M`. Any other ID hits `default:`, logs
`Unknown PCI IDE controller`, sets `_controllerID = PCI_ID_NONE`, and **returns
NO**, which makes `initFromDeviceDescription` free the instance and refuse to
attach.

Meanwhile `EIDE_PIIX.table` advertises `Auto Detect IDs` that include ICH-series
controllers the code does not handle:

```
0x1230 0x7010 0x7111 0x7112 0x7113            (PIIX family — code accepts)
0x2411 0x2421 0x244A 0x244B 0x248A 0x248B     (ICH..ICH4 — code REJECTS)
0x24CA 0x24CB
```

So on an ICH-class machine the matcher binds the driver, the probe rejects the
ID, and the system falls back to the legacy ISA personality (`Default.table`,
0x1f0/IRQ14). In that fallback:

- `_controllerID == PCI_ID_NONE` ⟹ `getControllerCapability` advertises PIO
  mode 4 but leaves all DMA modes `NONE` (DMA silently off);
- no host timing is programmed;
- interrupts are assumed to be edge-triggered ISA IRQ 14/15.

The last assumption is the direct cause of the timeouts: post-1997 controllers
frequently run in PCI-native mode and route the IDE interrupt to a shared PCI
IRQ rather than 14/15. The driver waits on IRQ14, the interrupt never arrives,
`ideWaitForInterrupt:` times out, and `ideExecuteCmd:` enters its retry storm.

Two failure mechanisms are plausible and lead to identical symptoms:

1. **Native-mode IRQ misrouting** — the completion interrupt is delivered on a
   PCI IRQ, not 14/15.
2. **Botched DMA programming on non-PIIX chips** — the bus-master DMA path runs
   with PIIX-shaped register writes the chip does not honor, producing BM errors
   and missed completion interrupts.

Because no boot logs or ICH emulation are available, the design must handle both
robustly rather than assume one.

## Scope

Decisions made during brainstorming:

- **Target hardware:** Intel PIIX→ICH lineage plus emulators that mimic it
  (VMware=PIIX4, VirtualBox/QEMU-i440fx=PIIX3). Non-Intel chipsets (VIA, SiS,
  ALi, Promise, ServerWorks) are **not** an immediate target but must not be
  designed out.
- **Transfer-mode ambition:** Reliability first, **plus** ICH ATA/66/100 (UDMA
  modes 3/4/5) with 80-wire cable detection.
- **Verification posture:** Design defensively; assume logs are not available.
  Guarantee a correct PIO floor for any controller.
- **Architecture:** Build a generic SFF-8038i bus-master core with swappable
  thin chipset back-ends (future-proofing), populating only the Intel and
  generic back-ends now. This is the "seams now, back-ends as needed" version of
  a full generic rewrite — chosen to avoid putting the working PIIX path at risk.

### Non-goals

- Non-Intel chipset timing back-ends (the seam exists; implementations are
  future work).
- SATA/AHCI (a different controller class this driver does not touch).
- Changing the ATA command layer, ATAPI layer, or disk/geometry logic beyond
  what the mode-fallback ladder already requires.

## Architecture

Split the PCI/DMA responsibilities into two layers with a clean seam.

### Generic BMIDE core (chipset-independent)

Everything that touches only the SFF-8038i standard bus-master registers — which
is already how most of `IdePIIX.m` is written:

- Controller discovery by **PCI class code** (`0x0101xx` = IDE) and the
  **programming-interface byte** (native/legacy bits, bus-master-capable bit 7),
  rather than a device-ID allow-list.
- Bus-master register base from BAR4 (PCI config 0x20).
- PRD table allocation and setup.
- DMA start/stop/status/prepare and the DMA transfer sequencing
  (`performDMA`, `performATAPIDMA`) — these already touch only standard
  registers and get de-PIIX-named and relocated here.
- Interrupt-vs-polled completion (see Timeout fix).

### Chipset back-end (thin, swappable)

A C ops table selected once at probe time and stored in `_chipsetOps`:

```c
typedef struct {
    unsigned char maxPIO;    // highest PIO mode (ATA mode number)
    unsigned char maxMWDMA;  // highest multiword DMA mode, or 0xff = none
    unsigned char maxUDMA;   // highest ultra DMA mode, or 0xff = none
    unsigned int  flags;     // CHIP_HAS_UDMACTL, CHIP_HAS_IDECONFIG, ...
} ideChipCaps_t;

typedef struct {
    const char *name;
    BOOL (*match)(unsigned long pciID, unsigned char progIf,
                  ideChipCaps_t *out);            // claim device, fill caps
    void (*setTiming)(id self, driveInfo_t *drives);  // program timing regs
    void (*resetTiming)(id self);                     // revert to compatible
    BOOL (*detectCable)(id self);                     // 80-wire? (UDMA>2 gate)
} ideChipsetOps_t;
```

The core calls `_chipsetOps->setTiming(self, _drives)` etc. and holds no chipset
knowledge.

### Back-ends shipped now

1. **Intel back-end** (`IdePIIX.m`, slimmed): PIIX/PIIX3/PIIX4/4E/4M **and**
   ICH0–ICH4. Reuses the existing IDETIM/SIDETIM/UDMACTL/UDMATIM programming;
   ICH adds the `IDE_CONFIG` register (0x54) for UDMA modes 3/4/5 and real cable
   detection.
2. **Generic back-end** (`IdeGeneric.m`, new): any bus-master-capable PCI IDE no
   other back-end claims. Programs no chip timing registers (leaves BIOS/POST
   timing); advertises PIO always plus an MWDMA2 attempt gated by the DMA
   self-test. UDMA disabled (we will not blind-program unknown timing).

### Attach policy

At probe: try the Intel back-end's `match`; else the Generic back-end if class
code says IDE and bus-master bit is set; else legacy PIO on the same ports.
**The probe never returns NO for an IDE-class device.** This removes the
reject-and-fragile-fallback failure class entirely.

## Timeout fix: interrupt delivery

The defensive core, since both candidate causes end in a wait that never
completes.

### Probe-time IRQ health check

- Read the PCI programming-interface byte to learn native vs. legacy mode per
  channel.
- **Prefer legacy mode:** if the controller is native-mode but the prog-if bits
  are writable, clear them so the interrupt lands on IRQ 14/15 (what the
  DriverKit config table pins). ICH PATA is compatibility-only, so this is
  mainly a safety net.
- Issue the first interrupt-driven command (the existing IDENTIFY / DMA
  self-test) with a **short** timeout (a few seconds, not 30). If no interrupt
  arrives but drive/BM status shows completion, set `_pollMode = YES`.

### Polled-completion fallback (`_pollMode`)

When set, `ideWaitForInterrupt:` stops blocking on the interrupt port and polls
ATA `altStatus` (BSY→0, plus DRQ / BM status as appropriate) with a bounded
delay, returning success/timeout from the actual hardware state.

- A misrouted or dead IRQ degrades to slow-but-correct operation instead of a
  30-second-per-command retry storm that eventually fails the boot.
- Interrupt mode stays the default, fast path; polling engages only after we
  have proven interrupts are not delivered. No perf hit on the working
  PIIX/emulator path.

### Generalize "TRUST_PIIX"

The DMA path already treats "BM status OK even though the interrupt timed out"
as success (the `TRUST_PIIX` block in `IdePIIX.m`). Lift this from a PIIX
`#define` into the generic core so every transfer type benefits; it also becomes
the mechanism by which the probe-time health check detects "completed without
IRQ."

### Tiered timeouts

Keep the 30s ceiling only for genuinely long ATAPI operations; use a
few-second timeout for normal disk commands so any pathological misconfiguration
surfaces in seconds, not minutes.

## Transfer modes

### Intel capability table

One static table drives `match` and caps:

| Chip        | PCI IDs                          | Max UDMA     | Notes                    |
|-------------|----------------------------------|--------------|--------------------------|
| PIIX        | 0x1230·8086                      | none (MWDMA2)| no UDMA                  |
| PIIX3       | 0x7010·8086                      | none (MWDMA2)| per-drive timing (SITRE) |
| PIIX4/4E/4M | 0x7111 / 0x7112 / 0x7113·8086    | UDMA2 (/33)  | UDMACTL/UDMATIM          |
| ICH0        | 0x2421·8086                      | UDMA2 (/33)  |                          |
| ICH         | 0x2411·8086                      | UDMA4 (/66)  | IDE_CONFIG 0x54          |
| ICH2/3/4    | 0x244A/B, 0x248A/B, 0x24CA/B·8086 | UDMA5 (/100) | IDE_CONFIG 0x54          |

### PIIX path unchanged

The existing `PIIXComputePCIConfigSpace` IDETIM/SIDETIM/UDMACTL/UDMATIM
programming stays as-is for PIIX/PIIX4 — no behavior change on the working path.

### ICH additions (ATA/66/100)

- Program `IDE_CONFIG` (0x54, 16-bit): set the per-drive UDMA-mode-3/4/5 enable
  bits that the PIIX4 `UDMATIM` register alone cannot express. UDMA 0–2 continue
  through `UDMACTL`/`UDMATIM` exactly like PIIX4; modes 3–5 layer on the ICH
  register.
- **Real 80-wire cable detection** replaces the current `PIIXDetect80WireCable`
  stub: read the cable-report bits in `IDE_CONFIG`. If 40-wire or undetectable,
  cap UDMA at mode 2 regardless of the table ceiling.

### Generic back-end modes

No timing-register writes. PIO from the drive's IDENTIFY, plus an MWDMA2 attempt;
UDMA off. Everything it offers is validated by the self-test before use.

### Mode-fallback ladder (safety floor)

Leans on the retry loop already in `resetAndInit`, which masks a failing mode and
retries. New modes flow through it unchanged:

1. Negotiate best mode = min(drive caps, back-end caps, cable gate, user's
   `Master/Slave Modes Mask` config value).
2. Set it via SET FEATURES + `_chipsetOps->setTiming`.
3. Run the DMA read self-test (`performDMATest`).
4. On failure: mask out that mode, revert timing, retry →
   UDMA5 → … → UDMA2 → MWDMA2 → … → PIO.

Worst case for any controller — Intel, generic, or mis-detected — is correct PIO
operation, never a hang. The existing `Master/Slave Modes Mask` config keys keep
working as a manual override/ceiling.

## File layout and project wiring

New ivars on the `IdeController` `@interface` (`IdeCnt.h`, near
`_controllerID`/`_busMaster`/`_has80WireCable`):

```c
const ideChipsetOps_t *_chipsetOps;   // selected back-end
ideChipCaps_t          _chipCaps;     // caps for this chip
BOOL                   _pollMode;     // interrupts proven undeliverable → poll
```

File changes (declared in `EIDE.lksproj/PB.project` `CLASSES` / `H_FILES`):

| File                 | Change                                                                 |
|----------------------|------------------------------------------------------------------------|
| `IdeBMIDE.h` (new)   | SFF-8038i register defs; `ideChipsetOps_t`, `ideChipCaps_t`, flag enums |
| `IdeBMIDE.m` (new)   | `IdeController(BMIDE)` generic core: discovery, BAR4, PRD, DMA engine, `performDMA`/`performATAPIDMA`, polled completion (moved out of `IdePIIX.m`) |
| `IdePIIX.m`          | Slimmed to the Intel back-end: ops entry + `setTiming`/`resetTiming`/`detectCable`, incl. ICH `IDE_CONFIG` |
| `PIIX.h`             | Add ICH IDs + `IDE_CONFIG` bit defs                                     |
| `IdeGeneric.m` (new) | Generic fallback back-end (PIO + gated MWDMA2)                          |
| `IdeCnt.h`           | New ivars                                                               |
| `IdeCnt.m`           | `ideWaitForInterrupt:` honors `_pollMode`; tiered timeouts              |
| `IdeCntInit.m`       | Probe-time IRQ health check; wire mode-fallback ladder to new caps      |

Config tables need no structural change; the ICH IDs already present in
`EIDE_PIIX.table` become functional.

## Validation

The honest weak spot: no logs, and no emulator exposes an ICH PATA controller.

1. **PIIX regression — the go/no-go gate.** Exercise the paths we can: QEMU
   i440fx (PIIX3), VMware (PIIX4), VirtualBox (PIIX3). Must still attach, pass
   the DMA self-test, and boot with no behavior change. This proves the refactor
   did not break the working path.
2. **ICH path — review plus safety net.** Ships validated by (a) code review
   against the Intel ICH datasheet register semantics and (b) the in-driver
   self-test + mode-fallback ladder, which masks a mis-programmed mode down to
   PIO at runtime rather than hanging. **Not pre-validated on real ICH silicon.**
3. **Generic path.** Same self-test gating; worst case is PIO.
4. **Build.** Compiles under the period ProjectBuilder / `gnumake` toolchain on
   a case-sensitive filesystem; it will not build on modern macOS.

The mode-fallback ladder and polled-mode carry much of the assurance precisely
because the new silicon cannot be pre-tested — the deliberate tradeoff of the
defensive posture.

## Risks

- **Refactor regresses the working PIIX path.** Mitigation: PIIX programming
  code is moved, not rewritten; item 1 above is a hard gate.
- **ICH `IDE_CONFIG` semantics wrong.** Register layouts for `0x48`/`0x4a`/`0x54`
  are now verified against the Intel 82801AA/AB datasheet (290655-003
  §9.1.16–9.1.18), which corrected the SDMA_TIM cycle-time encoding. ICH2–ICH4
  UDMA5/ATA-100 timing is still from Linux `piix.c`. Mitigation: self-test ladder
  falls back to a known-good mode; UDMA>2 gated behind cable detection.
- **Polled mode masks a real hardware fault as "slow but working."** Acceptable:
  booting slowly beats not booting; `_pollMode` only engages after interrupts
  are proven absent, and the condition can be logged.
