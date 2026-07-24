# i386 Platform Expert — Phase 4: Bus Driver Rehosting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `drvPCIBus`, `drvEISABus`, `drvPCMCIABus` and `Intel824X0PCI` consume the platform expert's discovery and configuration services instead of carrying private copies, removing the duplicated PCI config cycles, ISA PnP protocol, EISA slot access and PnP resource parsing.

**Architecture:** One driver per task, ordered by ascending risk and by how well the QEMU harness can verify it. The boundary rule is fixed: **if it pokes a port or decodes a firmware structure it belongs to the platform expert; if it is an `IODeviceDescription`, a resource reservation, or a probe/match decision it stays in the bus driver.**

**Tech Stack:** Objective-C DriverKit drivers (NeXT `driverkit-3`), C platform expert, `gnumake`, QEMU boot verification.

## Global Constraints

- **Design spec:** `docs/specs/2026-07-24-i386-platform-expert-design.md`.
- **Phases 1-3 must be complete** and their exit criteria met.
- **Verification is boot plus device presence, not unit tests.** The parsers already have host-side tests from Phase 3; nothing new here is pure enough to unit test.
- **Deleted code must be genuinely dead.** Before deleting any file or method, grep the whole of `src/drivers-i386` for callers. A driver that still compiles after a deletion is not proof — DriverKit resolves some calls dynamically.
- **The success gate for the phase is `vm/README.md`'s own criterion:** the guest boots with NE2000-PCI networking up and is reachable over SSH from the host.
- **Commit messages** start with the driver name (`drvPCIBus: `, `drvEISABus: `, `drvPCMCIABus: `) or `pexpert: `.
- **All boot testing uses a throwaway copy of `vm/rhapsody.vmdk`.**

## Scope corrections inherited from the spec

The spec says to "delete `pci.c`" from `drvPCIBus`. **That is wrong.** `drvPCIBus/…/pci.c` (223 lines) contains `PCIParsePrefix` and `PCIParseKeys` — location-string parsing, which is driver policy and stays. The duplicated configuration-cycle code is in **`PCIKernBusPrivate.m:62-158`**: the mechanism #1 probe, the mechanism #2 probe scanning `0xC000`–`0xD000`, and the config address/data cycles on `0xCF8`/`0xCFC`. Task 1 replaces those, not `pci.c`.

## Known gap carried in from Phase 3

**ISA PnP isolation is untested and defaults off.** Task 2 depends on it. `drvEISABus` will build and link with `isapnp=0`, but its PnP card enumeration will find nothing until the code path is validated on real hardware with `isapnp=1`. Task 2's exit criteria distinguish "builds and boots with PnP disabled" from "PnP enumeration verified", and only the first is achievable on the QEMU harness.

---

### Task 1: Rehost drvPCIBus on the platform expert's config service

Lowest risk and best verified: the QEMU guest's NE2000 is a PCI device, so a regression is immediately visible as a dead NIC.

**Files:**
- Modify: `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBusPrivate.m:62-158`
- Modify: `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBusPrivate.h`
- Modify: `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBus.m` (call sites)
- Unchanged: `pci.c`, `pci.h`, `PCIResourceDriver.m`

**Interfaces:**
- Consumes: `pexpert_pci_config_read(bus, dev, fn, off, size, *val)` and `pexpert_pci_config_write(...)` from `machdep/i386/pexpert_i386.h`, plus `i386_firmware_info.pci_config_mechanism` and `pci_last_bus`.

- [ ] **Step 1: Inventory the config-access call sites**

```bash
grep -n "PCI_CONFIG_ADDRESS\|PCI_CONFIG_DATA\|0xCF8\|0xcf8\|0xCFC\|outl\|inl\|outb\|inb" \
  src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/*.m
```

Record every hit. Expected: all inside `PCIKernBusPrivate.m`. **If any appear in `PCIKernBus.m` or `PCIResourceDriver.m`, extend this task to cover them** rather than leaving a second config path alive.

- [ ] **Step 2: Replace the mechanism probes with the published result**

The two probe functions in `PCIKernBusPrivate.m` (mechanism #1 at lines 62-84, mechanism #2 at lines 95-132) duplicate `pcicfg_probe_mechanism()`. Replace both bodies with a read of the published value:

```objc
#import <machdep/i386/pexpert_i386.h>

/*
 * The platform expert probes the configuration mechanism during early boot
 * and publishes the result.  Probing again here would be a second, competing
 * source of truth -- and would poke 0xCF8 after devices are live.
 */
static int
pciConfigMechanism(void)
{
    return (i386_firmware_info.pci_config_mechanism);
}
```

Delete the two probe functions and their declarations in `PCIKernBusPrivate.h`.

- [ ] **Step 3: Replace the config read and write cycles**

Replace the mechanism #1 address-construction and `inl`/`outl` sequence beginning at line 138 with calls into the platform expert. The driver's existing accessors keep their names and signatures so `PCIKernBus.m` does not change shape; only their bodies do:

```objc
static unsigned int
pciConfigReadLong(int bus, int dev, int fn, int off)
{
    unsigned int	val = 0xffffffff;

    (void) pexpert_pci_config_read(bus, dev, fn, off, 4, &val);

    return (val);
}

static void
pciConfigWriteLong(int bus, int dev, int fn, int off, unsigned int val)
{
    (void) pexpert_pci_config_write(bus, dev, fn, off, 4, val);
}
```

**Read the existing accessor names before writing this** — use whatever `PCIKernBusPrivate.m` actually declares, and add byte and word variants only if the existing code has them. Returning `0xffffffff` on failure preserves the convention that an absent device reads all-ones.

- [ ] **Step 4: Take the bus count from the platform expert**

Replace any hardcoded maximum bus number in `PCIKernBus.m`'s enumeration loop with `i386_firmware_info.pci_last_bus`. If the existing code scans a fixed range, note the old value in the commit message so a regression in device discovery can be attributed.

- [ ] **Step 5: Build and boot gate**

```bash
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPCIBus && gnumake"
```

Install the driver and boot. **Expected: the NE2000-PCI NIC is present and the guest is reachable over SSH from the host.** This is the phase's headline gate and it is fully met by this one task.

```bash
ping <guest-ip>
ssh <user>@<guest-ip> hostname
```

**If the NIC disappears,** the config cycles are wrong — compare `pexpert_pci_config_read`'s address construction against the original at `PCIKernBusPrivate.m:152` before changing anything in the driver.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/bus/drvPCIBus
git commit -m "drvPCIBus: use the platform expert's PCI config service

Removes the private mechanism probes and config cycles; pci.c location-string
parsing is unchanged."
```

---

### Task 2: Rehost drvEISABus

The largest cleanup in the project. `drvEISABus` is 8,886 lines across `EISABus.lksproj`, of which the duplicated discovery code is: `eisa.c` (389), `bios.c` (345), the inline PnP port access in `EISAKernBus+PlugAndPlay.m` (319) and `EISAKernBus+PlugAndPlayPrivate.m` (1,188), and the six-file PnP resource parser totalling 2,530 lines.

**Files:**
- Delete: `.../EISABus.lksproj/eisa.c`, `eisa.h`
- Delete: `.../EISABus.lksproj/bios.c`, `bios.h`
- Modify: `.../EISABus.lksproj/EISAKernBus+PlugAndPlay.m`, `EISAKernBus+PlugAndPlayPrivate.m`
- Modify: `.../EISABus.lksproj/PnPResources.m`, `PnPDeviceResources.m`, `pnpIRQ.m`, `pnpDMA.m`, `pnpIOPort.m`, `pnpMemory.m`
- Modify: `.../EISABus.lksproj/EISAKernBus.m`
- Modify: the project's `Makefile` and `PB.project` file lists

**Interfaces:**
- Consumes: `pnp_resource_parse()`, `pnp_resource_t`, `eisa_id_decode()`, `eisa_id_string()`, `eisa_slot_id()`, `isapnp_*()`, `pnpbios_*()`, and `i386_firmware_info.{eisa_present,eisa_slots,isapnp_cards,pnp_bios}`.

- [ ] **Step 1: Verify each deletion candidate is genuinely dead**

For each of `eisa.c`, `bios.c` and their headers:

```bash
grep -rn "EISAParseID\|EISAMatchIDs\|getEISASlotInfo\|getEISAFunctionInfo\|testSlotForID" src/drivers-i386
grep -rn "call_pnp_bios\|isolateCard\|clearPnPConfigRegisters\|readIsolationBit" src/drivers-i386
```

Record every caller. Each must be rewritten against the platform expert before its callee is deleted. **Do not delete a file with live callers and fix the fallout afterwards** — rewrite callers first, in the steps below, then delete.

- [ ] **Step 2: Route EISA slot access through the platform expert**

Replace calls to `getEISASlotInfo` / `getEISAFunctionInfo` — which read the booter's output at the hardcoded `EISA_SLOT_DATA_ADDR` and `EISA_CONFIG_DATA_ADDR` (`eisa.c:40,42`) — with reads of the arena-copied data published by `bootinfo_collect()`. Replace `EISAParseID` and `EISAMatchIDs` with `eisa_id_decode()` and `eisa_id_string()` from `chips/eisa.h`.

This removes the undocumented booter-to-driver contract identified in the spec.

- [ ] **Step 3: Route ISA PnP port access through the platform expert**

Delete the inline `outb` sequences at `EISAKernBus+PlugAndPlay.m:74-94` and every equivalent in `EISAKernBus+PlugAndPlayPrivate.m`, replacing them with `isapnp_*()` calls. The driver keeps CSN bookkeeping and the `maxPnPCard` bound; it stops owning the protocol.

- [ ] **Step 4: Rebuild the PnP resource classes on the shared parser**

`PnPResources.m`, `PnPDeviceResources.m`, `pnpIRQ.m`, `pnpDMA.m`, `pnpIOPort.m` and `pnpMemory.m` become thin wrappers: each calls `pnp_resource_parse()` once and turns the resulting `pnp_resource_t` array into the DriverKit objects it already vends. The tag-walking loops inside them are deleted.

Keep the classes' public interfaces unchanged — `EISAResourceDriver.m` and `PnPLogicalDevice.m` consume them and are not in scope.

- [ ] **Step 5: Update the project file lists**

Remove `eisa.c`, `eisa.h`, `bios.c` and `bios.h` from `CFILES`/`HFILES` in the driver's `Makefile` and from `OTHER_LINKED`/`H_FILES` in its `PB.project`, then delete the files.

- [ ] **Step 6: Build and boot gate**

Build the driver, install, and boot with `isapnp=0` (the default).

Expected: the guest boots to login and SSH still works. **EISA and ISA PnP enumeration find nothing on QEMU, which is correct** — the guest has neither. What this gate proves is that the driver still loads, still builds against the platform expert, and does not break the boot.

- [ ] **Step 7: Record the line-count reduction**

```bash
git diff --stat HEAD~1
```

Put the net figure in the commit message. The spec predicts this task is the bulk of the project's line reduction; recording the actual number makes that claim checkable.

- [ ] **Step 8: Commit**

```bash
git add -A src/drivers-i386/bus/drvEISABus
git commit -m "drvEISABus: rehost EISA and ISA PnP on the platform expert

Deletes the private eisa.c/bios.c and the inline PnP port access; the PnP
resource classes now wrap the shared parser."
```

---

### Task 3: Re-point drvPCMCIABus and Intel824X0PCI

Smallest of the three, and the spec is explicit that it delivers the least: the 82365 is a socket controller but it is optional hardware discovered by probe, not board-level, so it stays a driver. Only its resource requests re-route.

**Files:**
- Modify: `src/drivers-i386/bus/drvPCMCIABus/PCMCIABus.drvproj/PCMCIABus.lksproj/PCMCIAKernBus.m`
- Modify: `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Intel824X0.lksproj/Intel824X0.m`
- Unchanged: everything under `Intel82365PCMCIA`

- [ ] **Step 1: Re-point Intel824X0PCI at the config service**

```bash
grep -n "0xCF8\|0xcf8\|0xCFC\|outl\|inl" \
  src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Intel824X0.lksproj/Intel824X0.m
```

Replace each config cycle with `pexpert_pci_config_read` / `pexpert_pci_config_write`, exactly as in Task 1 Step 3. If the grep returns nothing, the driver already goes through `drvPCIBus` and this step is a no-op — record that in the commit message rather than inventing work.

- [ ] **Step 2: Re-point PCMCIA IRQ requests**

`PCMCIAKernBus.m:45` imports `intr_exported.h`, which is unchanged, so interrupt registration needs no edit. What changes is where the driver learns which IRQs are *available*: replace any hardcoded candidate-IRQ list with one derived from `i386_firmware_info.pir_table` when present, falling back to the existing list when it is `NULL`.

If the driver has no hardcoded list — check before writing — this step is a no-op. Record that rather than adding a dependency the driver does not need.

- [ ] **Step 3: Build and boot gate**

Build both drivers and boot. Expected: login prompt and working SSH. QEMU has no PCMCIA socket controller, so this gate proves the drivers still build and load, nothing more. State that plainly in the commit message.

- [ ] **Step 4: Commit**

```bash
git add -A src/drivers-i386/bus/drvPCMCIABus src/drivers-i386/bus/Intel824X0PCI
git commit -m "drvPCMCIABus: take PCI config and IRQ routing from the platform expert"
```

---

### Task 4: Update the driver README and the boot documentation

**Files:**
- Modify: `src/drivers-i386/README`
- Modify: `docs/boot/boot-i386.md`

- [ ] **Step 1: Add the platform expert to the i386 driver README**

`src/drivers-i386/README` currently lists drivers by category with no bus entry for the platform expert. Add, matching the existing format:

```
bus
 * drvPExpert - i386 platform expert; owns CPU identification, firmware table
   discovery, PCI configuration access, EISA and ISA Plug and Play enumeration.
   See docs/specs/2026-07-24-i386-platform-expert-design.md.
 * drvPCIBus - rehosted on drvPExpert
 * drvEISABus - rehosted on drvPExpert
 * drvPCMCIABus - resource requests routed through drvPExpert
```

Read the file first and match its actual heading style and status-annotation convention rather than the shape above.

- [ ] **Step 2: Update the DriverKit section of the boot trace**

In `docs/boot/boot-i386.md`, under "DriverKit, drivers, and service activation", add:

```markdown
The i386 bus drivers no longer carry private discovery code. `PCIKernBus` obtains configuration cycles from `pexpert_pci_config_read`/`_write`; `EISAKernBus` obtains EISA slot data, the ISA Plug and Play protocol and PnP resource parsing from the platform expert. Discovery has already run by this point — it happens in `i386_identify()` before `pmap_bootstrap()`, not at driver load. **Source anchor:** `src/kernel-7/machdep/i386/pexpert_i386.h`; `src/drivers-i386/bus/drvPExpert/i386/identify_machine.c` `i386_identify()`.
```

- [ ] **Step 3: Commit**

```bash
git add src/drivers-i386/README docs/boot/boot-i386.md
git commit -m "docs: record the rehosted i386 bus drivers"
```

---

## Phase 4 exit criteria

1. The guest boots to login with NE2000-PCI networking up and is reachable over SSH — `vm/README.md`'s own success criterion.
2. `drvPCIBus` contains no `0xCF8`/`0xCFC` access; `pci.c` location-string parsing is untouched.
3. `drvEISABus/…/eisa.c` and `bios.c` are deleted, no inline PnP port access remains, and the six PnP resource classes contain no tag-walking loops.
4. `grep -rn "0x279\|0xa79" src/drivers-i386` matches only inside `drvPExpert`.
5. The net line-count reduction is recorded in the Task 2 commit message.
6. `docs/boot/boot-i386.md` and `src/drivers-i386/README` describe the new arrangement.

## Explicitly not achieved by this phase

- **EISA and ISA PnP enumeration are not verified.** QEMU provides neither. Both paths build, link and boot, and ISA PnP defaults off. Real-hardware validation with `isapnp=1` remains outstanding and is the last blocker before this work can be called finished.
- **PCMCIA is not verified** for the same reason — no socket controller in the harness.
