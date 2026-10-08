# i386 drvPExpert verification, 2026-10-07

Verification of `origin/claude/nifty-dirac-9kwabs`, commit
`3fac9af2cef1ef1af7b2d2714aa1772b2bd94ac5`, in the isolated
`codex/i386-pexpert-verification` worktree. Native Project Builder and the
configured kernel build pass with the fixes below. The corrected kernel
reaches firmware discovery, built-in bus registration, root mounting, graphical
login and a verified SSH shell after correcting the test-image kernel aliases
and restoring the normal boot graphics settings.

## Results

| Check | Result |
| --- | --- |
| Existing builder image | Graphical login and SSH reached |
| Native platform expert compilation | 46 C/Objective-C units, zero failures; native assembly passed |
| Project Builder installhdrs and install | Both exit 0; actual pexperti386.o and PnPDump produced |
| Configured RELEASE_I386 kernel | Exit 0, linked against the actual Project Builder product; relink after mapper fix also exit 0 |
| ACPI parser regression tests | Ten checks pass on Clang and native Rhapsody; original source fails seven |
| Physical mapping regression test | Original mapper fails four assertions; fixed mapper passes on Clang and native Rhapsody |
| Native SMP trampoline execution in QEMU | Original faults; patched object reaches the paged entry with the expected stack argument |
| Initial new-kernel boot | Panics in pmap_remove_range during ACPI mapping; reproduced and fixed |
| Corrected new-kernel boot, 8259 mode | ACPI/MP discovery, bus registration, root mount, display/network startup and verified SSH shell |
| APM comparison | Both settings failed with the old canonical kernel; corrected canonical kernel reaches a shell with APM restored to Yes |
| drivertools packaging | Existing staged products successfully packaged through rbuild's packaging API |
| Full drvPExpert/kernel APK pipeline | Not verified; direct native Project Builder and kernel targets were used |
| APIC interrupt delivery | Shell, PCI network, PS/2 keyboard and graphics work; IDE reports an interrupt loss and switches to polling |
| LAPIC clock | Boot and thirty-second timing comparison pass after width and calibration fixes |
| Actual AP startup | Two-CPU boot parks one AP; combined four-CPU boot parks three APs |
| ACPI power button and S5 | Actual guest power-off verified with APM disabled and in the combined APIC boot |
| MSI/MSI-X and FADT reset register | Not runtime-verified |

The trampoline fixture tests the actual assembled transition, paging, segment
bases and stack setup. It does not send startup IPIs or exercise the kernel's
AP lifecycle. See `src/drivers-i386/bus/drvPExpert/tests/README.md` for test
commands and their limits.

## Fixes made

- Declare `i8259_controller` before its first use in intr.c; native compilation
  reproduced the missing declaration and passed after the change.
- Use the historical assembler's accepted `ljmp 0x0F30(%ebx)` syntax.
- Replace the trampoline's call/pop before ESP initialization with an immediate
  base address patched by build_trampoline(). QEMU execution reproduces the
  original fault and verifies the patched transition.
- Check the mapped revision-2 RSDP length, MADT header length and known entry
  lengths before reading them. Exclude unreachable x2APIC IDs from startup's
  processor list.
- Use the kernel's `page_size` for physical mapping alignment, reservations
  and pmap calls. i386_init.c selects 8192-byte VM pages; each pmap call maps
  two 4096-byte hardware pages. The original 4096-byte steps overlap successive
  mappings and panic when removing a mapping missing from the expected PV list.
- Store clock countdowns and reload values as unsigned 32-bit quantities.
  The old 16-bit PIT type truncates LAPIC values above 65535, corrupting
  fractional timestamps and preventing startup from progressing.
- Calibrate the LAPIC against IOGetTimestamp() while the PIT is still the
  clock, rather than an IODelay() spin loop. Normalize the measured interval
  and reject a stopped reference clock. The spin estimate ran too short under
  TCG, making guest time advance too fast even after fixing field widths.
- Preserve the kernel-private i386 RB_POWERDOWN value in the public-SDK
  fallback. Its original zero value made a power-button event halt without
  attempting ACPI S5.

The first boot's saved stack identifies this path:
`pexpert_init -> acpi_discover -> map_table -> pexpert_map_physical ->
pmap_enter_cache_spec -> pmap_remove_range -> panic`.
After the mapper fix, the same boot proceeds through those steps.

## Native build setup

A private QEMU builder uses a writable QCOW2 overlay over
`D:/RhapsodiOS/vm/work/rhap-i386-bootstrapped.img`, pentium3, 512 MiB RAM,
SSH 5361 and QMP 5363. Sources and guest logs are under
`/build/pexpert-verification-20261007`; NEXT_ROOT is `/build/bootstrap-root`.

The drivertools prerequisite's build/install had completed but its initial
rbuild invocation exited before packaging. A temporary helper invoked the
current builder_buildpackage() API on those staged products with the i386
operation architecture selected, producing binary and header APKs. The freshly
built rbuild's existing test suite passed 567 checks. No rbuild source changes
were retained.

Project Builder was run with RC_ARCHS=i386, INCLUDED_ARCHS=i386 and explicit
OBJROOT, SYMROOT and DSTROOT, including both installhdrs and install. Because
NEXT_ROOT is included in its header install path, the staged pexpert header
was copied from `pb-hdr/build/bootstrap-root/System/.../Headers/pexpert`
into the SDK before kernel compilation.

The configured kernel command selected ARCH=I386, TYPE=RELEASE,
BUILD_ARCHS=I386, HEADER_ARCHS=I386 and explicit build/symbol roots. The private
guest needed /usr/local/bin links for config, decomment, mig and relpath, and
/usr/libexec links for the existing MIG backends. A fresh configured build
then passed. Existing legacy compiler warnings remain in the saved logs.

An earlier private builder stopped responding to filesystem operations. Its
state was checkpointed and preserved; builds resumed on a clean overlay.
The cause of that guest failure is unconfirmed. Other guests and shared base
images were not modified.

## Boot evidence and resolved loader failure

The test disk is a separate raw copy, booted with QEMU -snapshot. The allocating
writer refused to resize the old grafted kernel inode, so the new kernel was
installed as `/mach_kernel.pexpert` and selected by the System.config table.
Readback matches the linked kernel byte for byte. EISABus and PCIBus were
removed from Boot Drivers; the other boot drivers remain.

The corrected kernel reports ACPI 1.0, MADT/FADT/HPET, one processor, one I/O
APIC, ISA overrides and an MP configuration table. It enumerates PCI devices,
registers EISA0, PCI0 and PCMCIA0, detects the root disk and reaches
`rootdev 300, howto 40000`.

It then reports `unexpected kernel trap e eip 1b2cba`, with failing address
`e997295b`, followed by repeated trap 6 at eip 3. Disabling APM reproduces the
same first fault. A hardware breakpoint before that instruction showed the
kernel continuation was 0x001b2cb8, exactly kern_server_main in the old kernel.
The new symbol is 0x001b34c8. The stale address points into a jump instruction
inside host_zone_info in the rebuilt kernel; this was not a valid call to that
routine.

The test image still exposed the old kernel at /mach_kernel while the booter
selected /mach_kernel.pexpert. Runtime kern_loader uses the canonical /mach
executable, a symlink to /mach_kernel, when resolving module symbols. Updating
/mach_kernel to link to the new inode and booting that canonical filename
removed the stale addresses. The old inode remains under mach_kernel.previous.
This was a test-image installation error, not a host_zone_info source defect.

The corrected boot registered the Cirrus display, PS2Mouse and NE2000 network
driver and completed startup to a working remote shell. SSH on 127.0.0.1:5367 executed /bin/sh,
id, uname, arithmetic and sysctl kern.version successfully. The running version
matches the built kernel (21:40:45 EDT, kernel-build2/RELEASE_I386). A second
normal boot with APM restored to Yes also completes startup and passes
the same shell commands. The verified guest remains running on SSH 5367,
QMP 5369 (host process 54996 at final verification), separate from the builder.

The diagnostic configuration (Boot Graphics=No, Kernel Flags=-v) produced
visible framebuffer corruption after the Cirrus display started. Restoring
Boot Graphics=Yes removed the stripes; restoring Kernel Flags to the original
empty value produced a fully rendered graphical login. The final screenshot
was inspected, and SSH shell commands passed again on this same normal boot.
APM is also restored to Yes. No display driver or kernel code was changed for
this comparison.

## Artifacts and reproduction

Local evidence is in `D:/RhapsodiOS/vm/work/pexpert-verification-20261007/`:

- `pb-build.sh`, `pb-build.log`, `pb-build-host.log`: complete Project Builder
  build and successful target exits.
- `kernel-build2-clean.sh`, `kernel-build2-clean.log`,
  `kernel-build2-clean-host.log`: configured kernel build and exit 0.
- `rebuild-mapping.sh`, `rebuild-mapping-host.log`, `kernel-mapping-fix.log`:
  native mapping test, Project Builder rebuild and successful kernel relink.
- `native-tests-combined.log`, ACPI red/green logs, physical-mapping red/green
  logs and `smp-red`/`smp-green-final`: regression evidence.
- `prepare-boot.py`, `prepare-boot-final.log`, `start-default-boot.ps1`:
  image preparation, checksum readback and exact test VM arguments.
- `default-panic-com2.log`, `panic-decoded.txt`: original mapping panic.
- `default-apm-trap-com2.log`, `default-apm-off-com2.log` and screenshots:
  corrected discovery/root mounting and the unresolved later fault.
- `gdb-first-fault.py`, `first-fault-registers.json`, `first-fault-stack.bin`:
  debugger capture showing the stale continuation before its first fault.
- `canonical-kernel.py`, `restore-apm.py`, `verified-shell-apm-on.log`:
  canonical inode links, boot configuration and successful shell verification.
- `final-normal-login.png`, `final-normal-com2.log`: diagnostic video corruption.
- `graphics-boot.py`, `normal-flags.py`, `verified-normal-login.png`,
  `normal-graphics-com2.log`, `verified-shell-normal-graphics.log`: original
  graphics/boot settings, visually verified login and working shell.
- `baseline-login.png`: existing kernel's login; not a boot of the new kernel.
- `builder.qcow2`, `builder-recovery.qcow2`, `checkpoint.raw`,
  `builder-clean.qcow2`: preserved original/recovery and current build state.

Native products before the boot-flag follow-up:

| Product | Bytes | SHA-256 |
| --- | ---: | --- |
| pexperti386-final.o | 1722188 | 71614e478c52fe27859643a1f2683ae9ed47a135b3bf8266f2f50ebb0afcc732 |
| mach_kernel | 1602588 | da9ddacb2019b730396c11f2303322092979845e9523cd2fe2667895a4d83762 |

## Remaining verification

1. Diagnose the IDE interrupt loss in APIC boots. Boot and userspace success
   depend on the existing EIDE polling recovery; this is not a clean result for
   disk interrupt delivery. The default 8259 boots do not show this warning.
2. Exercise MSI/MSI-X, MP-derived PCI INTx routes, bridge routing, ECAM and an actual FADT reset register.
   This QEMU PC firmware has no reset register; S5 power-off is verified.
3. Exercise the complete package pipeline and physical hardware. The runtime
   checks below use QEMU TCG and do not establish correctness on real boards.

## Boot-flag follow-up

All cases use a second disposable raw image, `flags-test.raw`, with QEMU
`-snapshot`, SSH 5375 and QMP 5377. The working default control and native
builder remain separate. Initial APIC comparisons used 512 MiB; subsequent
cases use 128 MiB to shorten legacy memory sizing. Cirrus, EIDE, NE2K and the
normal boot graphics settings are retained.

The fixed native products are:

| Product | Bytes | SHA-256 |
| --- | ---: | --- |
| pexperti386-bootflags-fixed.o | 1722456 | b9cf78368f81048fba205a67c9fe5c0805ea98ac152ef1a9d93b955b298eef23 |
| mach_kernel-bootflags-fixed | 1602608 | 23a32ec86bcf7a0961040d4edec1b099423ce5c4896b78f4c15f28362f002af0 |

`/mach_kernel` and `/mach_kernel.pexpert` point at the same updated inode;
image readback matches the linked kernel. Native Project Builder install and
kernel relink exit 0. The final kernel version is 22:41:51 EDT on 2026-10-07.

| Flags | Hardware / result |
| --- | --- |
| apic=1 | APIC routes programmed; shell, NE2K network and graphical login pass with APM Yes and No. A typed character appears in the login field. IDE switches to polling after a lost interrupt. |
| apic=1 lapictimer=1 | Fixed kernel reaches userspace; vector 126 is periodic, PIT IRQ 0 masked. Final reload is 623891 counts/tick. Thirty guest seconds take 31.532 host seconds including SSH, compared with 31.613 for the PIT control. |
| apic=1 smp=1 | Two CPUs: AP 1 reports up and parked, and userspace passes. QEMU confirms its kernel segments/page tables, HLT=1 and interrupts disabled. |
| acpi=1 | SCI IRQ 9 and S5 discovered; shell passes. With APM No, the virtual power button completes orderly shutdown and QEMU reports guest-shutdown. |
| apic=1 lapictimer=1 smp=1 acpi=1 rsdp=0xf52e0 | Four CPUs: three APs park, each confirmed halted with interrupts disabled. Shell, network, clock and graphics pass. Power button produces guest-shutdown with APM Yes. |
| smp=1 rsdp=0xff000 | Invalid hint is rejected; BIOS scan finds RSDP 0xf52e0. Warns that SMP needs apic=1 and retains the default interrupt path. Shell passes. Debugger readback confirms the requested flag values. |
| lapictimer=1 | Warns that apic=1 is required and retains the PIT/8259 path. Shell, network, timed sleep and graphical login pass. |
| apic=1 lapictimer=1 smp=1, CPU pentium,-apic | Reports no local APIC and remains on the 8259s; shell, network, timed sleep and graphics pass. |
| apic=1 lapictimer=1 smp=1 acpi=1, machine pc,acpi=off | Reports no ACPI tables, no MADT and no FADT PM1 blocks; keeps the 8259/PIT path and boots to a working shell and graphical login. |
| Empty flags, corrected kernel | Fresh default boot passes shell, network, timed sleep and graphical login, with no IDE interrupt-loss warning. |

The corrected default guest remains running on SSH 5375 / QMP 5377, host
process 44488. Its final graphical login was visually inspected. The original
control remains on SSH 5367 / QMP 5369, and the native builder on SSH 5361.

SMP here means starting and parking application processors. This kernel still
schedules on the boot CPU only; these results do not claim SMP scheduling.

The original LAPIC boot stalled after PnP probing. The native regression
reproduces four fractional-clock errors with the 16-bit fields; all six clock
checks pass after widening them. A width-only boot reaches userspace but a
ten-second guest sleep takes about three host seconds. Calibration against
the PIT-backed timestamp fixes that rate error. The native calibration test
also covers an inaccurate spin delay, sample overshoot and a stopped clock.

The original ACPI power-button boot synced disks and halted with howto=8,
leaving the VM powered on. The shutdown regression reproduces the missing
powerdown bit; the fixed request is 0x10008. Both corrected power-button boots
produce a QMP SHUTDOWN event with guest=true and reason=guest-shutdown.

Evidence includes `flags-*/com2.log`, `userspace.log`, `pic.txt`, `lapic.txt`,
`irq.txt`, `registers.txt`, screenshots, AP register captures and QMP power
events. `clock-width-red/green.log`, `lapic-calibration-red/green.log` and
`acpi-shutdown-red/green.log` preserve reproductions and fixes.
`native-bootflags-regressions.log` shows the final parser, mapper, clock,
calibration and shutdown checks passing. `rebuild-bootflags-host.log` records
the successful native rebuild. `set-flags.py`, `install-flags-kernel.py`,
`start-flag-boot.ps1`, `wait-flag.py` and `matrix-tail.py` reproduce the boots.
`bootflag-matrix.log` contains the first three cases; its last assertion used
the wrong wording for the invalid-hint diagnostic. The diagnostic and debugger
readback were checked against the production message, and the remaining cases
continued in `bootflag-matrix-tail.log` without repeating the completed boots.
The tail reaches `MATRIX COMPLETE`. A final audit finds
successful userspace checks and no panic/trap in all ten matrix cases; the five
APIC-enabled cases consistently contain the IDE polling-recovery warning.
