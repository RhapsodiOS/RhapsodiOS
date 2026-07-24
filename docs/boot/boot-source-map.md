# Rhapsody i386 and PPC boot source map

This map records only relationships supported by the checked-in source. It is a
trace index, not a claim that every implementation detail or build-time choice
has been recovered. The kernel source is shared until the architecture entry
points; user-space startup is represented here because it is the checked-in
continuation of the kernel's first user-process handoff.

## Evidence levels

- **Verified** — the cited source contains the named symbol or an explicit
  direct call, branch, pathname, or control-flow relationship.
- **Inferred** — the conclusion follows by connecting verified adjacent facts,
  but no one source location makes the complete relationship explicit.
- **Research gap** — the relevant source is absent, conditional on an
  unverified build configuration, or does not establish the needed handoff.
  The gap is stated instead of filling it with a historical assumption.

## Source map

| stage | i386 path/symbol | PPC path/symbol | shared path/symbol | evidence | notes/next trace |
| --- | --- | --- | --- | --- | --- |
| Loader handoff | `src/boot-2/i386/boot2/boot.c` `execKernel()` loads an image and calls `startprog(kernelEntry)`; `src/boot-2/i386/libsaio/asm.s` `_startprog` transfers to the supplied entry offset. | `src/boot-2/ppc/SecondaryLoader/SecondaryInAsm.s` loads `loadBase` into `r6`, uses it as the count-register target, prepares the next-stage arguments in `r3`–`r7`, and executes `bctrl`; `src/kernel-7/machdep/ppc/start.s` documents its `start` entry as the address to which the SecondaryLoader transfers the Mach-O image. | — | Verified for the i386 loader calls and the PPC transfer instruction/entry contract. | Trace the PPC image-loading path that establishes `loadBase`, then confirm the loaded next stage is the kernel image containing `start`. |
| Architecture entry | `src/kernel-7/machdep/i386/start.s` `_start` calls `_gdt_init`, `_idt_init`, then `_i386_init`; after paging it calls `_startup_early`, `_setup_main`, and `_start_initial_context`. | `src/kernel-7/machdep/ppc/start.s` `start` sets processor state and stack, then branches-and-links to `ppc_init`; `src/drivers/ppc/bus/drvPExpert/powermac/powermac_init.c` defines the PowerMac `ppc_init`. | — | Verified for the checked-in source and build relationship: `MASTER.ppc` selects `pexpertpowermac.o`, and the PPC linker includes the selected Platform Expert object. | The remaining gap is whether a particular loaded kernel image was built from this configuration and artifact. |
| VM | `src/kernel-7/machdep/i386/i386_init.c` `i386_init()` calls `pmap_bootstrap(...)`; `src/kernel-7/machdep/i386/start.s` then calls `_setup_main`. | PowerMac `ppc_init()` calls `initialize_vm()`, which sets the page size and calls `ppc_vm_init(mem_size, &our_boot_args)`; PPC-specific `pmap_init()` is in `src/kernel-7/machdep/ppc/pmap.c`. | `src/kernel-7/kern/mach_init.c` `setup_main()` calls `vm_mem_init()`; `src/kernel-7/vm/vm_init.c` `vm_mem_init()` calls `vm_page_startup`, initializes VM packages, and calls `pmap_init`. | Verified for the checked-in PowerMac build and shared calls. | Trace a particular loaded image; implementation-specific calls behind `powermac_init_p` still require a selected platform implementation. |
| Mach | `src/kernel-7/machdep/i386/start.s` calls `_setup_main` and passes its returned thread to `_start_initial_context`; `src/kernel-7/machdep/i386/pcb.c` `start_initial_context()` switches to that thread. | PowerMac `ppc_init()` calls `setup_main()` and passes its returned thread to `start_initial_context()`; `src/kernel-7/machdep/ppc/pcb.c` `start_initial_context()` activates the thread map and calls `load_context()`. | `src/kernel-7/kern/mach_init.c` `setup_main()` initializes scheduling, IPC, task/thread subsystems, creates `first_thread`, starts it at BSD `main`, and returns it. | Verified for the checked-in PPC build and source sequence. | Trace a particular loaded image before asserting that it contains this configured PowerMac artifact. |
| BSD | — | — | `src/kernel-7/bsd/kern/init_main.c` `main()` initializes BSD process, filesystem, protocol, and networking state; `src/kernel-7/kern/mach_init.c` starts `first_thread` at this `main`. | Verified. | Continue from `main()` to configuration, root mount, and `init_task()` below. |
| Drivers | `src/kernel-7/bsd/kern/init_main.c` calls `autoconf()` when `DRIVERKIT` is enabled. `src/kernel-7/driverkit/i386/autoconf_i386.m` supplies i386 `probeNativeDevices()`, `probeHardware()`, and `probeDirectDevices()`. `src/system_config-1/i386/Default.table` provides a checked-in default Boot Drivers and Active Drivers inventory. | The same call site additionally calls `bsd_autoconf()` when `ppc` is defined; `src/kernel-7/machdep/ppc/swapgeneric.m` defines it. | `src/kernel-7/driverkit/autoconfCommon.m` `autoconf()` initializes the I/O task and library functions, starts `autoconfInt` in that task, and waits for completion; `autoconfInt()` orders native, hardware, direct, and pseudo-device probes. i386 `probeNativeDevices()` reads `KERNBOOTSTRUCT.config`; its hardware/direct probe functions are empty. | Verified for conditional calls, i386 probe source/order, and the checked-in i386 default table; **Research gap** for the table or a driver inventory installed into a particular target. | Trace packaging/install manifests, `KERNBOOTSTRUCT.config`, and a target boot configuration. |
| Root filesystem | — | — | `src/kernel-7/bsd/kern/init_main.c` `main()` calls `setconf()` and retries `vfs_mountroot()` until it succeeds, then obtains the root vnode with `VFS_ROOT`. | Verified. | Trace `setconf`, the selected root-device implementation, and `vfs_mountroot()` if device-to-root provenance is needed. |
| First user process | — | — | `src/kernel-7/bsd/kern/init_main.c` starts `init_task()`; it calls `load_init_program(p)`. `src/kernel-7/bsd/kern/kern_exec.c` sets `init_program_name` to `/sbin/mach_init` and `load_init_program()` calls `execve`. `src/Commands/system_cmds/mach_init.tproj/bootstrap.c` defines a fallback configuration of `init \"/sbin/init\";`; `src/Commands/system_cmds/mach_init.tproj/parser.c` selects that fallback when `/etc/bootstrap.conf` cannot be opened or parsed. | Verified. | The kernel's first attempted user executable is `/sbin/mach_init`. `/sbin/init` is the fallback configured when `/etc/bootstrap.conf` cannot be opened or parsed; trace an installed configuration before claiming the normal configured init path. |
| `rc` | — | — | `src/Commands/system_cmds/init.tproj/pathnames.h` defines `_PATH_RUNCOM` as `/etc/rc` and `_PATH_RUNCOM_BOOT` as `/etc/rc.boot`; `src/Commands/system_cmds/init.tproj/init.c` selects one of those paths in `runcom()` and executes it through the Bourne shell. `src/files-5/private/etc/rc.boot` performs early filesystem checks; `src/files-5/private/etc/rc` performs multi-user startup and runs scripts in `/etc/startup`. | Verified for the source-level path selection and script behavior. | Trace the `files-5` packaging/install rules only if an installed-image provenance claim is required. |

## Direct-call spine

The verified i386 kernel spine is:

`_start` → `i386_init` → `startup_early` → `setup_main` → `main` →
`init_task` → `load_init_program` → `execve(/sbin/mach_init)`.

The checked-in PowerMac PPC spine is:

`start` → `ppc_init` → `setup_main` → `start_initial_context` → BSD `main`.

`start.s` directly calls `ppc_init`; the PowerMac PExpert source defines it,
calls `setup_main()`, and passes the returned thread to
`start_initial_context()`. `MASTER.ppc` selects `pexpertpowermac.o`;
the PPC kernel link suffix includes `$(LIBPEXPERT_SOURCE)/$(LIBPEXPERT)`; and
the PowerMac project builds that product from `powermac_init.c`.
`SecondaryLoader` selects a kernel pathname through BootInfo `kernel` or Open
Firmware `boot-file`, then transfers control through the `loadprog()`-returned
entry address. The remaining research gap is provenance: whether a particular
loaded kernel image was built from this configuration and artifact.

The checked-in user-space continuation is:

`/sbin/mach_init` → configured init server → `runcom()` → shell execution of
`/etc/rc.boot` for the boot script and `/etc/rc` for the regular run-com path.
The checked-in `/sbin/init` configuration is a fallback for an unavailable or
unparseable `/etc/bootstrap.conf`, not proof of the normal installed setting.
