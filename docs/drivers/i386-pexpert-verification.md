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
| APIC interrupt delivery | IDE edge loss reproduced and corrected; final combined boot passes shell and 32 MiB disk readback without polling recovery |
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

1. Investigate the intermittent standalone APIC startup inconsistencies
   described below: one missing SSH listener and one blank login desktop.
2. Exercise MSI/MSI-X, MP-derived PCI INTx routes, bridge routing, ECAM and an actual FADT reset register.
   This QEMU PC firmware has no reset register; S5 power-off is verified.
3. Exercise the complete package pipeline and physical hardware. The runtime
   checks below use QEMU TCG and do not establish correctness on real boards.

## Boot-flag follow-up before the APIC IDE fix

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

## APIC IDE interrupt follow-up

The preceding fixes and boot-flag verification were committed as
`a6619bc76` (`pexpert: fix i386 boot paths and add verification tests`). The
APIC changes described here were subsequently committed as `bf83c1bc1`.

The original `apic=1` trace contains 3318 IRQ14 rising edges after the input
was first enabled, including nine while the I/O APIC entry was masked. The
first is at trace line 526389, during IDE command 0xc4, with entry 0x1004e.
Nearby writes show the other inputs being masked too, consistent with an IPL
change. The console reports `lost IDE interrupt (cmd 0xc4); using polled mode`.
This explains the failure: masking an I/O APIC edge input discards requests.

The controller callback now receives both the combined priority mask and the
hard mask for disabled/unregistered inputs. Enabled I/O APIC edge inputs remain
unmasked during IPL changes; their handlers defer in software. Level inputs
retain priority masking, and the 8259 retains its existing combined mask.
Both the kernel and platform expert must be rebuilt together for this callback
interface change.

Kernel deferred storage is now an IRQ bitmap per IPL instead of a single
handler pointer, so distinct edges at one priority cannot overwrite each
other. Unregister removes pending bits; interrupt return drains nested deferred
requests. Interrupt entry only raises the hardware-masking IPL, preserving
pending or active higher-priority level inputs when a lower edge arrives.

Native regression evidence:

- The APIC fixture reproduces three failures with the original controller;
  the updated controller passes all six checks.
- The kernel fixture reproduces enable/bitmap failures and a nested-return
  failure before their respective fixes. All nine final checks pass.
- Review identified premature unmasking of a pending/active level input by a
  lower edge. Two new native checks fail before the entry-mask correction and
  pass afterwards. Read-only re-review found no remaining findings.
- Parser, physical mapper, clock width, calibration and shutdown regressions
  still pass. Native Project Builder headers/install and configured kernel
  rebuilds exit 0. Existing legacy compiler warnings remain.

Final native products:

| Product | Bytes | SHA-256 |
| --- | ---: | --- |
| pexperti386-ide-fixed.o | 1722968 | bd926c144012cdbef8ad9768bbbf2af310eb265f21824779a758083e7df06fcf |
| mach_kernel-ide-reviewed | 1610800 | 8dfe7a3abbac18673c3aadb16b13449d1381615eecdcdd28d100d09e3638a7a4 |

The revised kernel version is 23:35:33 EDT on 2026-10-07. Both canonical image
aliases point at its inode, and image readback matches its checksum. Runtime
tests use `ide-debug.raw`, QEMU snapshots, 128 MiB RAM, SSH 5385 and QMP 5387.

The first corrected revision passed `apic=1`, the four-CPU combined flags and
the default PIC control, including a native 32 MiB write/fsync/reopen/readback
test. Its two APIC traces contain 12237 and 12128 IRQ14 rises with zero masked
rises; neither boot reports IDE polling recovery. The final revision adds the
review correction above and is tested separately below.

The final four-CPU `apic=1 lapictimer=1 smp=1 acpi=1` boot passes userspace,
network, graphical login and the 32 MiB disk workload. Its trace records 12207
IRQ14 rises with zero masked rises. All three APs are halted as expected.
LAPIC vector 126 is periodic with reload 625307; thirty guest seconds take
31.976 host seconds including SSH. The virtual power button produces QMP
`SHUTDOWN` with `guest=true`, `reason=guest-shutdown`.

The final default PIC control also passes shell, network, graphical login and
the same disk workload. Final screenshots for the combined and PIC cases
were visually inspected and show normal login rendering.

One final-revision standalone APIC boot reaches graphical login with no IDE
warning and 3009 unmasked IRQ14 rises, but fails the 420-second SSH readiness
window. Packet capture shows the guest answering TCP SYNs with RST/ACK;
there is no SSH listener. The older control responds and the fresh combined
and PIC boots pass. The cause of this startup failure is unconfirmed; this
case is preserved as `flags-ide-reviewed-apic`, including `network.pcap`.

A fresh standalone `apic=1` repeat passes SSH/shell, network and the 32 MiB
disk workload. Its trace contains 12145 IRQ14 rises and zero
masked rises; no IDE polling recovery, panic or kernel trap is reported.
Its screenshots show a blank desktop despite live loginwindow/WindowServer
processes, so this repeat does not establish graphical login success.
The missing-listener boot did not recur in this repeat, but its cause has not
been established.

All three final cases (`flags-ide-reviewed-apic-repeat`,
`flags-ide-reviewed-combined`, `flags-ide-reviewed-pic`) pass their disk and
userspace assertions. The matrix guests were stopped or shut down after
verification. An additional standalone APIC guest remains available below.
The original default control, earlier corrected default and
native builder remain separate. `ide-debug.raw` retains the final kernel and
`apic=1` for reproduction.

The additional `flags-ide-reviewed-apic-visual` boot passes SSH and shell,
shows the normal login window, and displays a QMP-injected `a` in the name
field. Its startup process/system/network logs are saved. This demonstrates
that normal graphics and keyboard delivery also work with the final standalone
APIC configuration; the earlier startup inconsistencies remain unexplained.
This same boot passes the 32 MiB disk workload with 12093 IRQ14 rises and zero
masked rises, without IDE polling recovery. It remains running as host process
50492 on SSH 5385 / QMP 5387 with the final kernel.

Evidence is in the same local directory: `flags-ide-red`,
`flags-ide-green`, `flags-ide-combined`, `flags-ide-pic-control`,
`flags-ide-reviewed-*`, their trace analyses, userspace and disk logs,
`apic-mask-red/green.log`, `interrupt-*-red/green.log`,
`rebuild-ide-host.log`, `rebuild-ide-reviewed-host.log`, and the reproduction
helpers `analyze-ide-trace.py`, `verify-ide-io.sh`, `ide-io-test.c`,
`install-ide-kernel.py`, `start-ide-boot.ps1`, and `verify-reviewed-ide.py`.

## Bus consolidation and master integration, 2026-10-08

The superseded standalone EISA, PCI and PCMCIA projects were removed in
`ef8892b5d`. Their classes remain in PExpert; Intel chipset drivers remain
separate. The historical EISA source-map JSON moved unchanged into the
binrecon test fixtures. The obsolete blacklist entry and VM reconstruction
helper were removed, and the chipset build helper selects only retained
projects. Installed, network, generated and installer-media boot lists now
omit the old bundles, and the base installation set no longer requests their
packages. These dependent changes are committed through `d6e4fc20a`.

Current `master` (`2820d48b3`) was merged into the verification branch in
`9e5bc8e08`. The EFI source list includes both `efi_sector.c` and `efi_acpi.c`.
PExpert retains its recursive PCI bridge scanner; master's fix to the old
flat scan's eight-bit bus counter is unnecessary in that implementation.
Read-only review confirmed the resolutions and dependency cleanup.

All 8 installer template/package-list tests, 44 live-media/image-builder
tests and 29 source-map tests pass. Native `/bin/sh -n` accepts the updated
chipset helper. Tests reproduce the old installer boot-list/package failures
before their corrections.

The integrated RELEASE_I386 kernel builds natively with exit 0 and reports
Rhapsody 5.6. `mach_kernel-master-integrated` is 1763764 bytes, SHA-256
`5c221ecef29f828f670a686c3750564a836f6656b4851cc9df887a549d26c5ae`.
Image readback matches the product. Build evidence is in
`kernel-master-integration-host.log`; runtime evidence uses
`flags-master-integrated` in the same private test-image directory.

With explicit `apic=1 lapictimer=1 smp=1 acpi=1` and four CPUs, this integrated
kernel passes userspace/network checks and the 32 MiB disk workload. The
trace has 12173 IRQ14 rises with zero masked rises and no IDE polling recovery.
The three APs are halted as expected; thirty guest seconds take 31.289 host
seconds including SSH. The virtual power button completes guest ACPI shutdown.
