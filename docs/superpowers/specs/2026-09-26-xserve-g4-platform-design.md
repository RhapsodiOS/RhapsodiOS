# Xserve G4 Platform Support Design

**Date:** 2026-09-26
**Status:** Approved direction, pending spec review
**Scope:** Boot the Apple Xserve G4 (`RackMac1,1` and `RackMac1,2`) from a
drive-bay disk to a networked, multi-user RhapsodiOS system.

## Summary

RhapsodiOS cannot boot on the Xserve G4 today. There is no New World booter,
`get_machine_id()` panics on any `RackMac` compatible string, the kernel does
not know the MPC745x CPU, the drive-bay ATA controller has no timing support,
the GMAC Ethernet driver is not built, and Core99 NVRAM writes are unsafe.

This design layers Xserve support on top of the existing, unimplemented
[MacRISC platform plan](../plans/2026-08-01-ppc-macrisc-platform-support.md).
That plan supplies the generic New World platform expert (descriptor-driven
UniNorth/KeyLargo/Intrepid discovery, MPIC setup, parked secondary CPU). This
design adds everything that plan explicitly excludes and an Xserve needs to be
a usable headless server:

1. A New World booter reconstructed from Apple's BootX-34.
2. MPC7450-family CPU identification, L2/L3 cache setup, and safe AltiVec
   exception handling.
3. Correct, crash-safe Core99 flash NVRAM reads and writes.
4. Drive-bay ATA with UDMA.
5. Built-in Gigabit Ethernet (GMAC).
6. A headless console (serial or firmware framebuffer plus USB keyboard).

## Existing state (verified against source)

| Area | State | Reference |
|---|---|---|
| Machine ID | Exact `strcmp` on the first root `compatible` string; unknown strings panic. No `RackMac` entries. `strncmp(cpu_model, "AAPL,", 5)` tests the unset global rather than `family`. | `src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c:598-658` |
| Newest family | Sawtooth (`PowerMac3,1-3,3`, `PowerMac5,1`, `PowerBook2,1`) with a fixed 64-source MPIC table and fixed DBDMA map. | `powermac/families/sawtooth.c` |
| Booter | `SecondaryLoader`, XCOFF, Old World OF 1.0.5/2.x workarounds, links boot drivers into the kernel BSS appendix with `sarld` driven by `Default.table`. No `tbxi`, no `<CHRP-BOOT>` script. | `src/boot-2/ppc/SecondaryLoader/SecondaryInC.c:1717-2830` |
| Kernel handoff | `boot_args` version 1 / revision 1; flattened device tree with 32-byte property names; `ppc_init(boot_args *)` copies the structure before use. | `src/kernel-7/machdep/ppc/boot.h`, `powermac/powermac_init.c:94-137` |
| CPU | PVR table and `CPU_SUBTYPE_POWERPC_*` stop at the 750; unknown PVRs become `CPU_SUBTYPE_POWERPC_ALL`; `grade_cpu_subtype` has no G4 case. | `machdep/ppc/proc_reg.h:475-484`, `mach/machine.h:269-278`, `powermac_init.c:203-224`, `machdep/ppc/kern_machdep.c:77-122` |
| AltiVec | No `MSR_VEC`, no handler at 0xF20, no vector context. | `machdep/ppc/lowmem_vectors.s` |
| Caches | `backsideL2.c` returns early unless the CPU is a 750; no L3CR support. | `powermac/backsideL2.c:112` |
| NVRAM | Core99 path maps `POWERMAC_IO(nvram_addr_reg_phys)` (Mac-IO relative) and writes flash with `bcopy`, with no erase/program command sequence and no readback. | `src/kernel-7/bsd/dev/ppc/PowerSurgeMB.m:221-410` |
| ATA | `drvPPCATA` recognises `keylargo-ata` / `ata-4` but programs only Heathrow-clock PIO/MWDMA timings; UDMA only on CMD646. No Kauai / ATA-100. | `bsd/dev/ppc/drvPPCATA/IdeCnt.m:113-150`, `IdeCntInit.m` |
| Ethernet | `drvUniNEnet` exists but is absent from `conf/files.ppc` and the autoconf tables, and pokes a hardcoded `0xf8000020`. `drvPPCGem` matches Sun GEM `pci108e,2bad`, not Apple `gmac`. | `bsd/dev/ppc/drvUniNEnet/UniNEnet.m:155`, `driverkit/ppc/autoconf_ppc.m:93-205` |
| Console input | Sawtooth `PEEditDTEntry` hides every USB node except the first HID-bearing one. | `identify_machine.c:726-760` |
| Video | Unaccelerated `IOOFFramebuffer` fallback over the firmware-initialised framebuffer; NDRV path for Rage 128. | `driverkit-3/libDriver/ppc/IONDRVFramebuffer.m` |

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Relation to MacRISC plan | Build on it; Xserve is its lead validation machine | Avoids a second, Xserve-only platform family. |
| Models | `RackMac1,1` and `RackMac1,2` | Both G4 Xserve revisions. |
| SMP | Uniprocessor; CPU 1 stays parked | SMP needs Mach kernel changes; separate design. |
| Booter | Reconstruct BootX-34 as `src/BootX-1` for New World | Native OF 3.x/4.x client-interface support, HFS+/UFS, `<CHRP-BOOT>` bootinfo. |
| Old World | Keep `SecondaryLoader` unchanged | No regression risk to Old World and Sawtooth machines already booting. |
| AltiVec | Minimal: identify, keep `MSR_VEC` clear, deliver `SIGILL` on vector-unavailable | Userland is scalar; full vector context is a separate design. |
| NVRAM | Full Core99 flash erase/program with double-bank commit | User requirement. |
| Finish line | Headless multi-user server over GMAC | Server use case; no accelerated graphics. |
| Test hardware | Dedicated Xserve G4 test unit(s), separate from the 10.2 build host | Boot and NVRAM experiments must not risk the build host. |

## Design

### P0 — Hardware evidence

Everything model-specific in P3–P5 is resolved from firmware data, not from
memory. Before implementation:

- Capture `ioreg -l -p IODeviceTree -w0` on the Mac OS X Server 10.2 build host
  (an Xserve G4) and on each test unit booted into Mac OS X, and capture
  `dev / ls` plus `.properties` for `/`, `/cpus/*`, `/pci*`, `mac-io`,
  `/nvram`, every `ata`/`ide`, `gmac`, `usb`, `escc`, and `display` node from
  Open Firmware.
- Record in `docs/hardware/xserve-g4/` per model: root `model`/`compatible`,
  CPU PVR and cache properties, Mac-IO `compatible` (KeyLargo vs Intrepid),
  drive-bay ATA node names/`compatible`/`reg`/interrupts, GMAC `compatible`
  and PCI ID, `/nvram` `compatible`/`reg`, and whether a DB-9 serial `escc`
  channel is present.
- Save a raw copy of each unit's NVRAM (`nvram -p` and the full 16 KiB/bank
  image read through `/dev/mem` or OF `dump`) as the recovery baseline for P3.

These dumps also become host-test fixtures.

### P1 — MacRISC platform (existing plan)

Execute `docs/superpowers/plans/2026-08-01-ppc-macrisc-platform-support.md`
Tasks 1–11 unchanged. Two amendments:

- Its model catalogue must include `RackMac1,2` alongside `RackMac1,1`, with
  the Mac-IO family recorded in P0.
- Its Task 9 ("Preserve Core99 NVRAM") keeps read-only behaviour; P3 of this
  design replaces the write path.

Task 12 (hardware validation) runs after P2 here, because the Xserve cannot
load a kernel until BootX exists.

### P2a — BootX New World booter

Import BootX-34 (`apple-opensource-mirror/BootX` at `cd13aef5`, APSL 1.1)
as `src/BootX-1`, built with the tree's `pb_makefiles`.

Keep unchanged in behaviour:

- `ci.subproj`: Open Firmware client interface for OF 1.x–3.x+ (`kOFVersion3x`
  paths are what the Xserve uses).
- `fs.subproj`: HFS/HFS+, UFS, and network loading.
- `sl.subproj/macho.c`: Mach-O kernel loading.
- `sl.subproj/device_tree.c`: flattening. Its `DTProperty`/`DTNode` layout
  matches `machdep/ppc/boot.h` field for field.
- `SetUpBootArgs()`: its `boot_args` version 1 / revision 1 matches the
  kernel's structure.

Replace:

- `sl.subproj/drivers.c` (IOKit `.kext`/`.mkext` loading and
  `/chosen/memory-map` `Driver-*` publication). Rhapsody's kernel does not
  consume kexts. Port SecondaryLoader's boot-driver path instead: read the boot
  driver list, process each DriverKit bundle's `Default.table`, and link the
  relocatables into the kernel with `sarld`
  (`SecondaryInC.c` `InitializeSARLD`, `ProcessDriverBundle`,
  `FindNetDrivers`, and the BSS-appendix claim in `loadAndCallKernel`).
- `bootinfo.hdr`: a RhapsodiOS `<CHRP-BOOT>` header whose `<COMPATIBLE>` is
  `MacRISC` and whose `<BOOT-SCRIPT>` loads the XCOFF BootX image, producing a
  `tbxi` file of type `tbxi`.
- Branding images: use neutral RhapsodiOS artwork or none. No Apple Happy Mac
  bitmaps are required for booting.

Kernel handoff: BootX passes the `boot_args` address in `r3`, and
`ppc_init(boot_args *)` copies it. The layout of the kernel, BSS appendix,
boot arguments, and flattened tree must lie below `topOfKernelData`, which the
kernel reserves. A host test compares BootX's flattened tree against
`SecondaryLoader`'s flattening of the same fixture tree, byte for byte.

Installation: `src/cdis-3/rc.cdrom.PPC` already writes
`boot-device=...,\\:tbxi` for New World. Wire it to install BootX's `tbxi`
into the root of the HFS boot partition and bless it.

### P2b — MPC7450-family CPU

- Add `PROCESSOR_VERSION_7400` (0x000C), `_7410` (0x800C), `_7450` (0x8000),
  and `_7455` (0x8001) to both copies of `proc_reg.h`.
- Add `CPU_SUBTYPE_POWERPC_7400` (10) and `CPU_SUBTYPE_POWERPC_7450` (11) to
  `mach/machine.h`, matching the values later Darwin releases use so that
  binaries built elsewhere grade the same way.
- `powermac_init.c`: map these PVRs to the new subtypes.
- `kern_machdep.c`: grade 7450 > 7400 > 750 > …, and accept all older
  subtypes on G4 hardware.
- `backsideL2.c`: replace the 750-only guard with per-family L2CR handling.
  Use the firmware's `l2cr` / `l3cr` / cache properties where present. Only
  program L3CR on 745x when the firmware reports an L3 cache and it is not
  already enabled. Never reprogram a cache the firmware enabled.
- `lowmem_vectors.s`: install a handler at 0xF20 (AltiVec unavailable) and
  0x1600 (AltiVec assist on 745x) that routes to the existing illegal-
  instruction path, delivering `SIGILL` to user mode and panicking with a
  clear message in kernel mode. `MSR_VEC` remains clear in every context.
- Add `MSR_VEC_BIT` (bit 6) to `proc_reg.h`, and assert at context-switch
  time that it is never set.

### P3 — Core99 flash NVRAM

Rework the Core99 path in `PowerSurgeMB.m`, gated on a platform capability
("Core99 NVRAM") that both Sawtooth and MacRISC set instead of `IsSawtooth()`.

- **Location:** map the `/nvram` node's `reg` physical address and size with
  the kernel I/O mapper, not `POWERMAC_IO(...)`. The platform expert publishes
  the address in `powermac_io_info`.
- **Format:** two 8 KiB banks. The header holds signature `0x5A` at +0,
  header checksum at +1, length at +2, name at +4, Adler-32 over the data at
  +0x10, and generation at +0x14. Select the bank with a valid signature, a
  valid header checksum, a valid Adler-32, and the higher generation. A bank
  failing validation is never chosen. If neither validates, the device is
  read-only for the session.
- **Flash programming:** the `/nvram` node `compatible` selects the command
  set (AMD-style and Sharp/Micron-style parts, per P0 evidence). Implement
  bank erase, byte program, and status polling with a bounded timeout. Use
  Apple's APSL Core99 NVRAM sources and the flash data sheets as references.
  Linux's implementation is used only as a behaviour reference and is not
  copied.
- **Commit protocol:** increment the generation, compute the checksums, erase
  the inactive bank, program it, read it back and compare, then switch
  primary/backup. On any failure, leave the old primary untouched and report
  the error. Writes happen only from `SyncCore99NVRAM()` (shutdown and
  explicit sync), never per byte.
- **Safety gate:** writes are disabled unless the boot argument
  `nvram-write=1` is present, until the P3 hardware validation passes. After
  that the default flips to enabled in a separate commit. The DRAM shadow
  always works, so readers never touch flash after init.
- **Host tests:** a flash simulator (both command sets, injected
  erase/program failures, power-cut between erase and program) exercises bank
  selection, checksums, the commit protocol, and rollback.

### P4 — Drive-bay ATA

Extend `bsd/dev/ppc/drvPPCATA` (and its loadable copy) for the controller(s)
recorded in P0:

- Add controller types for the recorded `compatible` values (KeyLargo ATA-4
  UDMA/66 and, if present, Kauai ATA-100).
- Add per-controller timing tables for PIO 0–4, MWDMA 0–2, and UDMA 0–5.
  Select the mode from IDENTIFY data and the cable/controller limit.
- DMA uses the existing DBDMA path. Kauai-style controllers get their register
  offsets from the node's `reg`, not from Heathrow constants.
- Extend autoconf matching for each additional `compatible`.
- Bring-up order: PIO first (root mount), then MWDMA, then UDMA, each
  validated separately on hardware with a data-integrity test.

### P5 — GMAC Ethernet

- Add `drvUniNEnet` to `conf/files.ppc` and an autoconf entry matching Apple's
  `gmac` node (and the PCI ID recorded in P0).
- Replace the hardcoded `0xf8000020` write with a UniNorth clock-enable
  helper in the platform expert. It uses the UniNorth base from the MacRISC
  descriptor.
- Verify PHY discovery on both models, link negotiation at 10/100/1000, and
  DBDMA/descriptor-ring operation under load.
- Leave `drvPPCGem` (Sun GEM) as is.

### P6 — Headless console

- If P0 shows an `escc` channel on a DB-9 connector, make it the default
  console when no display is attached (`/chosen` `stdout` is serial). The
  kernel ESCC console path already exists.
- Otherwise use `IOOFFramebuffer` over the firmware-initialised Rage 128.
- Generalise the Sawtooth USB-node filter in `PEEditDTEntry` to MacRISC
  machines so that the first USB HID keyboard is published and the second
  USB controller does not break input.

## Acceptance

On each of `RackMac1,1` and `RackMac1,2`:

1. BootX loads from the drive-bay disk's HFS boot partition via `tbxi`.
2. The kernel identifies the model, CPU subtype 7450, and L2/L3 caches, and
   reports two CPUs found with one available.
3. The root filesystem mounts from a drive-bay disk using UDMA, and passes a
   1 GiB write/read/compare test.
4. The system reaches multi-user. `ping` and `ssh` over GMAC work at 1000
   Mb/s, and a 1 GiB `rsync` completes without driver errors.
5. `nvram` changes survive reboot. A write interrupted by power loss leaves
   the previous contents bootable.
6. The system runs for 10 minutes with less than 1 s clock drift, then shuts
   down cleanly.

Regression: the `PowerMac5,1` Cube and one Old World machine still boot via
`SecondaryLoader` with unchanged behaviour.

## Out of scope (separate designs)

- SMP and starting secondary CPUs.
- AltiVec context save/restore and `MSR_VEC` enablement.
- Thermal sensors, fan control, and the front-panel/drive-bay LEDs over I2C.
- FireWire, USB mass storage, and accelerated graphics.
- PowerPC 970 Xserve G5 (`RackMac3,1`).
- Replacing `SecondaryLoader` on Old World machines.

## Risks

| Risk | Mitigation |
|---|---|
| NVRAM flash corruption bricks OF settings | P0 baseline image; write gate; erase-inactive-bank-only protocol; readback verification; host power-cut tests; `Cmd-Opt-P-R` recovery documented. |
| BootX memory layout collides with the BSS appendix or `sarld` | Byte-compare the flattened tree in host tests; log the claimed ranges; test first with no boot drivers. |
| Fans run at full or uncontrolled speed without an OS thermal driver | Observe behaviour during P1/P2 bring-up. Limit unattended runs until a thermal design exists. |
| `RackMac1,2` differs from `1,1` (Mac-IO, ATA) | All model differences come from P0 dumps and are covered by host fixtures for both. |
