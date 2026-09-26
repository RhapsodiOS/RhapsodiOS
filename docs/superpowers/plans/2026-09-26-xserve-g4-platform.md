# Xserve G4 Platform Support Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.
> Execute phases in order. Each task ends in one commit whose subject starts
> with the subsystem (`kernel:`, `drvPExpert:`, `BootX:`, `drvPPCATA:`, …).

**Goal:** Boot `RackMac1,1` and `RackMac1,2` Xserve G4 systems from a
drive-bay disk to multi-user, with GMAC networking, a headless console, and
working Core99 NVRAM, without regressing Sawtooth or Old World machines.

**Design:** `docs/superpowers/specs/2026-09-26-xserve-g4-platform-design.md`

**Depends on:** `docs/superpowers/plans/2026-08-01-ppc-macrisc-platform-support.md`
Tasks 1–11 (phase P1 below).

**Tech stack:** ANSI C89 and Objective-C DriverKit, PowerPC assembly, Open
Firmware Forth (bootinfo), Project Builder makefiles, host C tests
(`-std=c89 -pedantic -Wall -Wextra -Werror`), Rhapsody PPC kernel build,
dedicated Xserve G4 test units.

## Invariants for every task

- Host tests compile with `-std=c89 -pedantic -Wall -Wextra -Werror` and pass.
- No behaviour change for Old World machines or `SecondaryLoader`.
- Anything model-specific comes from P0 evidence or firmware properties, never
  from a guess.
- Boot tests use the dedicated test unit and a scratch drive-bay disk, never
  the 10.2 build host.
- Flash NVRAM is never written unless `nvram-write=1` is set, until Task 13
  records a passing validation.
- Firmware property bytes are never modified in early boot.

## File structure

- `docs/hardware/xserve-g4/`: device-tree dumps, NVRAM baselines, and the
  validation record.
- `src/BootX-1/`: the imported and adapted BootX booter.
- `src/drivers-ppc/bus/drvPExpert/tests/fixtures/rackmac1_{1,2}.dt`: flattened
  device-tree fixtures generated from P0 dumps.
- `src/kernel-7/bsd/dev/ppc/core99_nvram.{c,h}`: the Core99 bank and flash
  logic, split out of `PowerSurgeMB.m` so the host can test it.
- `src/kernel-7/bsd/dev/ppc/tests/core99_nvram_test.c`: the flash simulator
  and commit tests.
- Integration changes land in the existing files named in each task.

---

## P0 — Evidence and safety

### Task 1: Capture Xserve device trees and NVRAM baselines

**Files:**
- Create: `docs/hardware/xserve-g4/README.md`
- Create: `docs/hardware/xserve-g4/rackmac1_1-ioreg.txt`, `rackmac1_2-ioreg.txt`
- Create: `docs/hardware/xserve-g4/rackmac1_1-of.txt`, `rackmac1_2-of.txt`

- [ ] **Step 1:** On each unit running Mac OS X, run
      `ioreg -l -p IODeviceTree -w0 > rackmacX_Y-ioreg.txt`. The 10.2 build
      host also counts as a `RackMac1,x` data point.
- [ ] **Step 2:** In Open Firmware on each test unit, run `dev / ls`, then
      `.properties` for each of: `/`, `/cpus/*`, the UniNorth host bridges,
      `mac-io`, `/nvram`, every `ata`/`ide` node, `gmac`, both `usb` nodes,
      `escc` with its `ch-a`/`ch-b`, and `display`. Save the output to
      `rackmacX_Y-of.txt`.
- [ ] **Step 3:** In `README.md`, write one table per model with these
      rows: `model`, `compatible`, CPU PVR, L2/L3 properties, Mac-IO
      `compatible`, each ATA node (`name`, `compatible`, `model`, `reg`,
      interrupts), GMAC `compatible` and PCI vendor/device, `/nvram`
      `compatible` and `reg`, whether a DB-9 serial port exists and which
      `escc` channel it is on, and the MPIC source numbers for ATA, GMAC,
      USB and ESCC.
- [ ] **Step 4:** Commit with `docs: record Xserve G4 device trees`.

### Task 2: Save NVRAM recovery baselines

**Files:**
- Create: `docs/hardware/xserve-g4/nvram-recovery.md`
- Create (not committed, see Step 2): per-unit raw NVRAM images

- [ ] **Step 1:** Under Mac OS X, save `nvram -xp` output. From Open
      Firmware, `dump` both 8 KiB banks at the `/nvram` `reg` address.
- [ ] **Step 2:** Store the images next to the test unit, outside the repo:
      they contain serial numbers and the unit's MAC address. In
      `nvram-recovery.md`, record only their SHA-256, the bank generation
      numbers, and the recovery procedure: `Cmd-Opt-P-R`, OF
      `reset-nvram`/`set-defaults`, and restoring from `nvram -xp` output.
- [ ] **Step 3:** Commit with `docs: add Xserve NVRAM recovery procedure`.

### Task 3: Build host-test fixtures from the dumps

**Files:**
- Create: `src/drivers-ppc/bus/drvPExpert/tests/fixtures/rackmac1_1.dt`, `rackmac1_2.dt`
- Create: `src/drivers-ppc/bus/drvPExpert/tests/tools/ioreg_to_dt.py`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/Makefile.host`

- [ ] **Step 1:** Write `ioreg_to_dt.py`. It converts an
      `ioreg -p IODeviceTree` dump into the flattened `DTNode`/`DTProperty`
      format from `src/kernel-7/machdep/ppc/boot.h`: 32-byte names, and
      values padded to 4 bytes.
- [ ] **Step 2:** Generate both fixtures. Add a `fixtures` make target that
      regenerates them, and a check that the committed output matches.
- [ ] **Step 3:** Commit with `drvPExpert: add RackMac device-tree test fixtures`.

---

## P1 — MacRISC platform

### Task 4: Amend and execute the MacRISC plan

**Files:** as listed in `2026-08-01-ppc-macrisc-platform-support.md`.

- [ ] **Step 1:** In that plan's Task 2 classifier table and Task 10 model
      catalogue, add `RackMac1,2` with the Mac-IO family recorded in Task 1.
      Add the Task 3 fixtures to its Task 4 DeviceTree capture tests.
- [ ] **Step 2:** Execute MacRISC Tasks 1–11. Its Task 9 keeps Core99 NVRAM
      read-only; Task 11 here replaces that.
- [ ] **Step 3:** Change the `get_machine_id()` `AAPL,` prefix test at
      `identify_machine.c:616` to test `family` instead of the unset
      `cpu_model`, with a host test. Commit that fix on its own.
- [ ] **Step 4:** Defer MacRISC Task 12 (hardware validation) until after
      Task 9 here.

---

## P2a — BootX

### Task 5: Import BootX-34 unmodified

**Files:**
- Create: `src/BootX-1/` (from `apple-opensource-mirror/BootX` at `cd13aef5c52e2d2c9c577127056d37d5edfd9968`)
- Create: `src/BootX-1/IMPORT.md`
- Modify: `src/Manifest`

- [ ] **Step 1:** Copy the tree without `.git`. In `IMPORT.md`, record the
      upstream URL, the commit, the APSL 1.1 licence, and that this import
      is unmodified.
- [ ] **Step 2:** Add `BootX-1` to `src/Manifest` next to `boot-2`.
- [ ] **Step 3:** Commit with `BootX: import Apple BootX-34 unmodified`.
      This keeps every later diff reviewable against upstream.

### Task 6: Build BootX in the tree

**Files:**
- Modify: `src/BootX-1/Makefile*`, `src/BootX-1/*/Makefile.preamble`

- [ ] **Step 1:** Build it on the ppc build box with the tree's
      `pb_makefiles` and `cc`, and record the first failure.
- [ ] **Step 2:** Fix only build issues: include paths, missing libc-lite
      symbols, and `macho-to-xcoff`. The tree's `boot-2` already has an
      XCOFF converter. Use one converter and delete neither.
- [ ] **Step 3:** The build must produce `BootX` (XCOFF) and a `tbxi` built
      from `bootinfo.hdr` plus the image. Check with `file` and
      `otool -h`.
- [ ] **Step 4:** Commit with `BootX: build with the RhapsodiOS makefiles`.

### Task 7: Replace kext loading with DriverKit boot drivers

**Files:**
- Modify: `src/BootX-1/bootx.tproj/sl.subproj/drivers.c`
- Modify: `src/BootX-1/bootx.tproj/sl.subproj/main.c`
- Create: `src/BootX-1/bootx.tproj/sl.subproj/sarld_glue.{c,h}`

- [ ] **Step 1:** Remove the `.kext`/`.mkext`/`Info.plist` scanning and the
      `Driver-*` memory-map publication.
- [ ] **Step 2:** Port from `src/boot-2/ppc/SecondaryLoader/SecondaryInC.c`
      the pieces that load drivers:
      - reading the boot-driver list from BootInfo (`readBootInfo`);
      - claiming the BSS appendix after the kernel, as in
        `loadAndCallKernel`;
      - `InitializeSARLD`, loading `/usr/standalone/ppc/sarld`, and calling
        it;
      - `ProcessDriverBundle` and `Default.table` handling;
      - `FindNetDrivers`.

      Route file I/O through BootX's `fs.subproj` instead of
      SecondaryLoader's vectors.
- [ ] **Step 3:** Allocate `boot_args` in the BSS appendix, as
      `setupKernelParams` does, so `topOfKernelData` covers the kernel, the
      linked drivers, `boot_args` and the flattened tree. Keep BootX's `r3`
      handoff.
- [ ] **Step 4:** Add a host test built from `device_tree.c` and the Task 3
      fixtures. It byte-compares BootX's flattened output with
      SecondaryLoader's `GetDeviceTree` output for the same input. Expected:
      identical output.
- [ ] **Step 5:** Commit with `BootX: link DriverKit boot drivers with sarld
      instead of loading kexts`.

### Task 8: RhapsodiOS bootinfo and installation

**Files:**
- Modify: `src/BootX-1/bootx.tproj/bootinfo.hdr`
- Modify: `src/cdis-3/rc.cdrom.PPC`

- [ ] **Step 1:** Change `<DESCRIPTION>` to RhapsodiOS and replace the
      Apple `<OS-BADGE-ICONS>` with neutral artwork, or remove them. Keep
      `<COMPATIBLE>MacRISC</COMPATIBLE>`.
- [ ] **Step 2:** In `rc.cdrom.PPC` (lines 391–420), set New World detection
      explicitly (`/openprom` version ≥ 3 or `MacRISC2` compatible). Install
      `tbxi` at the root of the HFS boot partition, bless it, and set
      `boot-device` to it.
- [ ] **Step 3:** Commit with `BootX: add RhapsodiOS bootinfo and New World
      install step`.

### Task 9: First Xserve boot

**Files:**
- Create: `docs/hardware/xserve-g4/validation.md`

- [ ] **Step 1:** On a scratch drive-bay disk, install the P1 kernel and
      BootX. Boot with `boot-args` set to `-v nvram-write=0` and with no
      boot drivers.
- [ ] **Step 2:** Expected: BootX runs, the kernel enters `ppc_init`, and the
      MacRISC descriptor prints `RackMac1,x`, two CPUs found and one
      available. Record the first failure line if any.
- [ ] **Step 3:** Repeat with the normal boot-driver set.
- [ ] **Step 4:** Run MacRISC plan Task 12 on the Xserve and the Cube
      control, and record the results.
- [ ] **Step 5:** Commit with `docs: record first Xserve BootX boot`.

---

## P2b — G4 CPU

### Task 10: Identify MPC7400/7450-family CPUs

**Files:**
- Modify: `src/kernel-7/machdep/ppc/proc_reg.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/proc_reg.h`
- Modify: `src/kernel-7/mach/machine.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/powermac_init.c`
- Modify: `src/kernel-7/machdep/ppc/kern_machdep.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/backsideL2.c`

- [ ] **Step 1:** Add `PROCESSOR_VERSION_7400 12`, `_7410 0x800C`,
      `_7450 0x8000` and `_7455 0x8001` to both `proc_reg.h` copies. Add
      `MSR_VEC_BIT 6`.
- [ ] **Step 2:** Add `CPU_SUBTYPE_POWERPC_7400 10` and
      `CPU_SUBTYPE_POWERPC_7450 11`.
- [ ] **Step 3:** Map 7400/7410 to subtype 7400, and 7450/7455 to subtype
      7450, in `powermac_init.c:203-224`.
- [ ] **Step 4:** In `grade_cpu_subtype`, raise the exact-match return from
      8 to 10. Make 7450 return 9 and 7400 return 8. Leave 750 at 7 and
      the rest of the order unchanged, and update the comment above the
      function. In `check_cpu_subtype`, accept both new subtypes.
- [ ] **Step 5:** `backsideL2.c:112`: replace the 750-only return with a
      family switch.
      - 750: keep the existing path.
      - 7400/7410 and 745x: use the firmware L2CR if L2E is already set;
        otherwise read the `l2cr` property.
      - 745x only: apply the same rule to L3CR, using the `l3cr` property.
      - Never touch an enabled cache.
- [ ] **Step 6:** Rebuild the kernel and drvPExpert. Boot the Xserve and
      the Cube. Expected: `hostinfo` reports ppc7450 on the Xserve and ppc750
      on a G3, and the kernel prints the cache sizes.
- [ ] **Step 7:** Commit with `kernel: identify MPC7400 and MPC7450 CPUs and
      keep firmware L2/L3 settings`.

### Task 11: Safe AltiVec exceptions

**Files:**
- Modify: `src/kernel-7/machdep/ppc/lowmem_vectors.s`
- Modify: the trap dispatch that handles `EXC_PROGRAM` (locate it from
  `lowmem_vectors.s`)

- [ ] **Step 1:** Split the 0xF00 performance-monitor slot so that 0xF20
      has its own `HANDLER(F20, EXC_VECTOR_UNAVAILABLE)`. Map 0x1600
      (`EXC_RESERVED_16`) to `EXC_VECTOR_ASSIST`.
- [ ] **Step 2:** In trap dispatch, from user mode deliver `SIGILL` with
      `ILL_ILLOPC`. From kernel mode, panic with
      `"AltiVec used in kernel"`.
- [ ] **Step 3:** In the context-switch path, add a debug assertion that
      `MSR_VEC` is clear in every saved MSR.
- [ ] **Step 4:** Test on the Xserve with a user program that executes
      `vor v0,v0,v0` (`.long 0x10000484`). Expected: the program dies of
      `SIGILL` and the system keeps running.
- [ ] **Step 5:** Commit with `kernel: send SIGILL for AltiVec instructions
      instead of taking an unhandled vector`.

---

## P3 — Core99 NVRAM

### Task 12: Extract and host-test Core99 bank logic

**Files:**
- Create: `src/kernel-7/bsd/dev/ppc/core99_nvram.{c,h}`
- Create: `src/kernel-7/bsd/dev/ppc/tests/core99_nvram_test.c`, `Makefile.host`
- Modify: `src/kernel-7/bsd/dev/ppc/PowerSurgeMB.m`
- Modify: `src/kernel-7/conf/files.ppc`

- [ ] **Step 1:** Write failing tests against a simulated 16 KiB flash
      holding two 8 KiB banks. Cover:
      - header checksum, Adler-32 and signature validation;
      - picking the higher valid generation;
      - rejecting a bank with a bad checksum, even when its generation is
        higher;
      - generation wrap;
      - neither bank valid: the result is read-only.
- [ ] **Step 2:** Implement pure C89 functions with no kernel dependency:
      `core99_bank_valid()`, `core99_select_bank()` and
      `core99_prepare_commit()`. The last one increments the generation and
      fills in both checksums.
- [ ] **Step 3:** Wire `InitCore99NVRAM` and `SyncCore99NVRAM` in
      `PowerSurgeMB.m` to these functions. Change nothing else yet.
- [ ] **Step 4:** Commit with `kernel: validate Core99 NVRAM banks before
      use`.

### Task 13: Map the real NVRAM and program flash safely

**Files:**
- Modify: `src/kernel-7/bsd/dev/ppc/core99_nvram.{c,h}`
- Modify: `src/kernel-7/bsd/dev/ppc/PowerSurgeMB.m`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c`, `powermac.h` (both copies)
- Modify: `src/kernel-7/bsd/dev/ppc/tests/core99_nvram_test.c`

- [ ] **Step 1:** In the platform expert, publish the `/nvram` `reg`
      physical base and size, plus a `Core99 NVRAM` capability flag, in
      `powermac_io_info` for both Sawtooth and MacRISC. Replace the
      `IsSawtooth()` checks in `ReadNVRAM`, `WriteNVRAM` and
      `SyncCore99NVRAM` with the capability.
- [ ] **Step 2:** In `InitCore99NVRAM`, map the published physical range
      uncached instead of using `POWERMAC_IO(PCI_NVRAM_ADDR_PHYS)`.
- [ ] **Step 3:** Add a flash operations table selected by the `/nvram`
      `compatible` recorded in Task 1. Each entry provides `erase_bank`,
      `program_byte` and `status`, with a bounded busy-wait that returns an
      error on timeout. Take the command sequences from the flash data
      sheet and Apple's APSL Core99 NVRAM source, and cite them in comments.
      Do not copy GPL code.
- [ ] **Step 4:** Extend the simulator to model both command sets and to
      inject erase failures, program failures and a power cut between
      erase and program. Test the commit order:
      1. prepare;
      2. erase the inactive bank;
      3. program it;
      4. read back and compare;
      5. swap.

      Expected: after any injected fault, `core99_select_bank()` still
      returns the old contents.
- [ ] **Step 5:** Gate the flash write on the `nvram-write=1` boot argument,
      parsed in `bootargs.c`. Without it, `SyncCore99NVRAM` logs once and
      keeps the RAM shadow.
- [ ] **Step 6:** Hardware test on the Xserve with `nvram-write=1`:
      1. Change `boot-args` with `nvram`, reboot, and check it in OF with
         `printenv`.
      2. Pull power during 20 write cycles; each time, confirm the machine
         boots with either the old or the new value.
      3. Compare both banks against the Task 2 baseline apart from the
         intended changes.

      Repeat on the Cube.
- [ ] **Step 7:** Record the results in `validation.md`. Commit with
      `kernel: program Core99 NVRAM flash with a verified double-bank
      commit`.
- [ ] **Step 8:** Once Step 6 passes on every Core99 machine in
      `validation.md`, flip the default to enabled, keeping
      `nvram-write=0` as an opt-out. Commit this on its own with
      `kernel: enable Core99 NVRAM writes by default`.

---

## P4 — Drive-bay ATA

### Task 14: Controller detection and timing tables

**Files:**
- Modify: `src/kernel-7/bsd/dev/ppc/drvPPCATA/IdeCnt.m`, `IdeCntInit.m`, `ata_extern.h`
- Create: `src/kernel-7/bsd/dev/ppc/drvPPCATA/ata_timing.{c,h}`
- Create: `src/kernel-7/bsd/dev/ppc/drvPPCATA/tests/ata_timing_test.c`
- Modify: `src/kernel-7/driverkit/ppc/autoconf_ppc.m`

- [ ] **Step 1:** Add controller types for each ATA `compatible` recorded in
      Task 1, for example a UDMA-capable KeyLargo ATA-4 and Kauai ATA-100.
      Extend `+probe:` and the autoconf `"Matching"` string.
- [ ] **Step 2:** Write host tests: for each controller type, check the
      PIO 0–4, MWDMA 0–2 and UDMA register values against a table derived
      from Apple's APSL `AppleKeyLargoATA`/`AppleKauaiATA` timing sources,
      cited in the test.
- [ ] **Step 3:** Implement `ata_timing.c` as pure functions: controller
      type and mode in, register value out. Call them from
      `IdeCntInit.m`, and read register offsets from the node `reg` rather
      than Heathrow constants.
- [ ] **Step 4:** Commit with `drvPPCATA: add KeyLargo and Kauai timing
      tables`.

### Task 15: Bring up PIO, then MWDMA, then UDMA

**Files:**
- Modify: `src/kernel-7/bsd/dev/ppc/drvPPCATA/IdeCntDma.m`, `IdeCntInit.m`
- Modify: the loadable copy under `src/drivers-ppc/ide/` if one exists, then run `tools/ppc_package_check.py`

- [ ] **Step 1:** Limit mode selection to PIO, boot the Xserve from a
      drive-bay disk, and run a 1 GiB write/read/compare. Commit.
- [ ] **Step 2:** Allow MWDMA through the existing DBDMA path and repeat
      the test. Commit.
- [ ] **Step 3:** Allow UDMA, choosing the mode from IDENTIFY words 53/88
      and the controller maximum, then repeat the test in every bay.
      Commit with `drvPPCATA: enable UDMA on Xserve drive bays`.
- [ ] **Step 4:** Regression: the Cube still boots from its ATA disk.

---

## P5 — GMAC Ethernet

### Task 16: Build and match drvUniNEnet

**Files:**
- Modify: `src/kernel-7/conf/files.ppc`
- Modify: `src/kernel-7/driverkit/ppc/autoconf_ppc.m`
- Modify: `src/kernel-7/bsd/dev/ppc/drvUniNEnet/UniNEnet.m`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/families/macrisc.c` (from P1), plus a matching header export

- [ ] **Step 1:** Add every `drvUniNEnet/*.m` source to `files.ppc` as
      `optional mk_hasdrivers`, next to `drvBMacEnet`.
- [ ] **Step 2:** Add an autoconf entry with `"Driver Name"` set to
      `UniNEnet`. Set `"Matching"` to the GMAC `compatible` from Task 1,
      use `ENET_LOAD_PRI_PROP`, and set `"Network Interface"` to `AUTO`.
- [ ] **Step 3:** Replace the hardcoded `0xf8000020` access at
      `UniNEnet.m:155` with a platform-expert
      `PEUniNorthEnableClock(kPEUniNClockGMAC)`. That function uses the
      UniNorth base from the MacRISC descriptor and is a no-op on machines
      without one.
- [ ] **Step 4:** Build the kernel and fix compile errors only.
- [ ] **Step 5:** Commit with `kernel: build the GMAC Ethernet driver and
      match Apple gmac nodes`.

### Task 17: Validate GMAC on hardware

- [ ] **Step 1:** Boot each model and confirm PHY detection, then check
      link at 1000, 100 and 10 Mb/s against a switch.
- [ ] **Step 2:** Test `ping -f` for 5 minutes, then a 1 GiB `rsync` in each
      direction. Expected: no driver errors and no ring stalls.
- [ ] **Step 3:** Fix defects as separate, focused commits. Record the
      results in `validation.md`.

---

## P6 — Headless console

### Task 18: Serial or framebuffer console, and USB keyboard

**Files:**
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c` (`PEEditDTEntry`)
- Modify: `src/kernel-7/machdep/ppc/serial_io.c` (only if the Task 1 evidence requires it)

- [ ] **Step 1:** If Task 1 found a DB-9 `escc` channel, make it the kernel
      console when `/chosen` `stdout` resolves to it or no display is
      present. Check this at 57600 8N1, or at the rate firmware reports.
- [ ] **Step 2:** Apply the Sawtooth USB filter at
      `identify_machine.c:742` to MacRISC machines too. Publish the first
      keyboard even when it sits on the second OHCI controller.
- [ ] **Step 3:** Boot headless over serial, then with VGA and a USB
      keyboard. Expected: login works both ways.
- [ ] **Step 4:** Commit with `drvPExpert: give MacRISC machines a serial or
      USB-keyboard console`.

---

## Final acceptance

### Task 19: Run acceptance and the regression audit

**Files:**
- Modify: `docs/hardware/xserve-g4/validation.md`
- Modify: `src/drivers-ppc/README`

- [ ] **Step 1:** On `RackMac1,1` and `RackMac1,2`, run every acceptance
      item from the design: BootX, CPU and caches, UDMA root with a 1 GiB
      compare, multi-user with ssh and a 1 GiB rsync, NVRAM persistence
      and power-cut survival, 10-minute clock drift, and clean shutdown.
- [ ] **Step 2:** Regression: the `PowerMac5,1` Cube (Sawtooth, via
      SecondaryLoader) and one Old World machine boot with unchanged logs,
      apart from the new CPU and cache lines.
- [ ] **Step 3:** Rerun all host test suites from a clean tree, then
      `git diff --check`.
- [ ] **Step 4:** Update `src/drivers-ppc/README` with the GMAC and ATA
      status. Commit with `docs: record Xserve G4 acceptance`.

## Deferred (each needs its own design)

SMP, AltiVec context save and restore, I2C thermal and fan control and the
front-panel LEDs, FireWire, USB storage, accelerated Rage 128 graphics, and
the Xserve G5.
