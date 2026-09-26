# Symmetric multiprocessing on ppc and i386 — design

**Date:** 2026-09-26
**Status:** Design proposal, pending maintainer review; implementation plan in
[`docs/superpowers/plans/2026-09-26-smp.md`](../plans/2026-09-26-smp.md)

## Summary

Make the kernel run on every CPU a machine has, on both architectures, with
one execution model and one set of machine-independent changes. The Mach core
(scheduler, VM, IPC, zones, timers) already carries CMU's multiprocessor
support behind `NCPUS > 1`; it has never been compiled that way in this tree
and neither architecture supplies the machine-dependent half. The BSD and
DriverKit layers were written for one CPU and rely on `spl` for mutual
exclusion, which only masks interrupts on the CPU that calls it.

The design keeps the Mach core multiprocessor-safe with its existing simple
locks, runs all BSD and DriverKit code on the master CPU using the Mach 2.5
`unix_master()` binding that is already in the tree, keeps device interrupts on
the master CPU, and gives each architecture the pieces it lacks: per-CPU state,
`cpu_number()`, inter-processor interrupts, a per-CPU clock, TLB coherence, CPU
discovery, and secondary-CPU bring-up. Symmetric scheduling of user threads and
pure-Mach kernel work is the payoff; a later phase can replace master binding
with a funnel lock once the base is stable.

## Current state (verified in the tree)

### Machine-independent scaffolding that already exists

| Area | Where | State |
|---|---|---|
| CPU count | `conf/MASTER` `pseudo-device cpus N` under tags `multi2/16/32/64`; generates `cpus.h` `NCPUS` | Present. No config selects a `multi*` tag; every kernel is `NCPUS == 1`. |
| Processors and sets | `kern/processor.c`, `kern/machine.c` (`cpu_up`, `cpu_down`, `processor_assign`, `processor_shutdown`, `action_thread`) | Present, `NCPUS > 1` paths intact. |
| Scheduler | `kern/sched_prim.c` (per-processor run queues, idle dispatch through `processor->next_thread`, `cause_ast_check`), `kern/priority.c`, `kern/thread.c` (`last_processor`), `kern/timer.c` (per-CPU timers), `kern/mach_clock.c` (master-only housekeeping) | Present. |
| ASTs | `kern/ast.c` `need_ast[NCPUS]`; arch `check_for_ast` on both | Present. `cause_ast_check()` / `init_ast_check()` are called but defined nowhere. |
| Slave start | `kern/slave.c` `slave_main()`, `bsd/kern/kern_synch.c` `slave_start()`, `bsd/kern/init_main.c` calling `start_other_cpus()` and creating one bound idle thread per slot | Present. `slave_config()`, `start_other_cpus()`, `ns_hardclock_init()` are undefined. |
| Master funnel | `kern/parallel.c` `unix_master()` / `unix_release()` / `unix_reset()`; `thread->unix_lock` initialised to -1; `bound_processor` honoured by `thread_setrun` | Present. Used only in `vnode_pager.c`, `vm_unix.c`, `kern_exec.c`, `kern_synch.c`, `subr_prf.c`, `subr_log.c`, `mach_net_tcp.c`. Neither `unix_syscall` funnels. |
| Simple locks | `mach/i386/simple_lock.h` (`xchgl`), `mach/ppc/simple_lock.h` over `test_and_set` in `machdep/ppc/misc_asm.s` (`lwarx`/`stwcx.`) | Real atomics on both. `MACH_SLOCKS` is already on because `DRIVERKIT` is on. |
| Locked subsystems | `vm_object` (simple lock), `vm_map` (`lock_t`), zones (`zone->lock`), IPC ports, `printf_lock`, `panic_lock` with `paniccpu`, `kern_lock.c` spin-then-sleep, `ipc_kmsg_cache[NCPUS]` | Present. |
| `cpu_number()` | `kern/cpu_number.h` includes `<machine/cpu_number.h>` when `NCPUS > 1` | That header exists on neither architecture. `bsd/i386/cpu.h` and `bsd/ppc/cpu.h` hard-code `0`. |
| Shutdown / panic | `kern_shutdown.c` stops every other processor; `subr_prf.c` panic halts non-panicking CPUs | Present. |

### ppc

| Piece | State |
|---|---|
| Per-CPU exception state | `struct per_proc_info per_proc_info[NCPUS]` reached through `sprg0`; `cpu_data[NCPUS]`, `active_pcbs[NCPUS]`, `active_stacks[NCPUS]` all indexed by CPU; `hw_exception.s` and `cswtch.s` go through `PP_CPU_DATA` / `PP_ACTIVE_STACKS`. Inherently per-CPU; only slot 0 is ever initialised (`powermac_vm_init.c`). |
| Interrupt stack | One global `intstack` and one `istackptr`. |
| FPU ownership | `per_proc_info[cpu].fpu_pcb`; `pcb.c` already saves FPU state on switch when `NCPUS > 1`. |
| Interrupt controller | `drivers-ppc/bus/drvPExpert/powermac/chips/mpic.c` programs only the processor-0 bank (`MPIC_P0_*`), masks all four IPI vectors, and routes every source to CPU 0. `spl` is a global `current_priority` plus the P0 task-priority register. |
| Clock | Per-CPU decrementer; `rtclock_intr()` → `ppc_hardclock()` → `clock_interrupt()`; BSD `hardclock()` already returns early on non-master CPUs. |
| pmap / TLB | `tlbie` + `tlbsync` sequences exist; comments say "TODO - locks and tlbsync in SMP configurations"; hash-table updates are unlocked. |
| Discovery | `machdep/ppc/DeviceTree.c` can walk the flattened tree; `/cpus` is never read. |
| Secondary start | Nothing. MacRISC design deliberately parks extra CPUs. |
| Test hardware | QEMU `mac99` is single-CPU. The MacRISC spec names a dual-processor `RackMac1,1`. |

### i386

| Piece | State |
|---|---|
| Per-CPU state | `stack_pointers[NCPUS]`, `empty_stacks[NCPUS]` exist, but `locore.s` reads `_stack_pointers` at index 0 in five places. `fp_thread` (FPU owner) is a single global. |
| Descriptor tables | One GDT; `TSS_SEL` is remapped to the incoming thread's TSS on every switch (`pcb.c` `map_tss`), likewise the per-task LDT. A second CPU cannot share this GDT. |
| Interrupt controller | 8259 PIC only (`intr.c`); `current_ipl`, `masked_ipl`, mask caches are globals. No local APIC, no I/O APIC. |
| Clock | PIT on IRQ 0 (`machine_clock.c`). |
| pmap / TLB | `pmap->cpus_using` is a boolean; no cross-CPU invalidation. |
| Discovery | None. The i386 platform expert (`2026-07-24-i386-platform-expert-design.md`, P3 plan) specifies MP-table and MADT discovery but is not built. The UEFI loader does not pass the ACPI RSDP to the kernel, and OVMF does not put one in the legacy scan area. |
| Secondary start | Nothing. |
| Test hardware | QEMU `-M pc`/`q35` with `-smp N` provides MP tables, MADT and local APICs; `-cpu pentium` reports the APIC feature. |

## Scope

### Included

- Both architectures, one machine-independent design.
- Kernel configurations with `NCPUS > 1` that boot unchanged on one CPU.
- `cpu_number()`, per-CPU data, per-CPU interrupt stacks, per-CPU `spl`.
- Inter-processor interrupts for AST checks, TLB shootdown, and halt.
- Per-CPU clock ticks (local APIC timer, decrementer).
- CPU discovery (MP table / MADT on i386, `/cpus` device-tree node on ppc)
  and secondary-CPU bring-up.
- pmap coherence: `cpus_using` bitmask and shootdown on i386; locked hash
  table updates and `tlbsync` on ppc.
- Master-CPU binding of BSD syscalls, signal delivery, BSD kernel threads and
  DriverKit I/O threads; device interrupts pinned to CPU 0.
- Panic, kernel debugger and shutdown behaviour with several CPUs.
- Host-side unit tests for every table parser, register-encoding and layout
  computation; QEMU `-smp` runs for i386; real dual-G4 hardware for ppc.

### Excluded

- A funnel lock replacing master binding (follow-on design once SMP boots).
- Routing device interrupts to non-master CPUs (I/O APIC, MPIC destinations).
- MP-safe rewrites of BSD subsystems or DriverKit.
- PowerPC 970 / G5 and 64-bit kernels; x86-64; hyper-threading topology.
- CPU hot-plug, power states, frequency switching, `processor_set` policy
  changes beyond what CMU's code already does.
- User-space changes (`hostinfo` already reports slots; `hw.ncpu` exists).

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Execution model | Mach core MP-safe on all CPUs; BSD and DriverKit run only on the master CPU via `unix_master()`; device interrupts only on CPU 0 | Preserves the `spl` exclusion model the BSD and driver code depends on without auditing hundreds of files. The mechanism is already in the tree and is what the CMU scheduler comment "unparallelized U*x code" expects. A funnel is a later optimisation, not a prerequisite. |
| Where the binding happens | `unix_syscall` on both arches, the BSD half of `check_for_ast` and signal delivery, BSD kernel threads at creation, DriverKit `IOForkThread` | These are the only ways into BSD from a thread that may be on another CPU; page faults already funnel in `vnode_pager.c`. |
| Kernel-thread default | `kernel_thread()` binds to the master processor; the Mach daemons that must run anywhere (`sched_thread`, `vm_pageout`, `action_thread`, idle threads, swapper) opt out explicitly | Almost every kernel thread in this tree is BSD or DriverKit. Opting the handful of Mach daemons out is safer than finding every BSD thread. |
| `cpu_number()` on i386 | Per-CPU GDT with a data segment in `%gs` pointing at `cpu_data_t`; `cpu_number()` reads `%gs:0` | `%fs` is already the linear-data segment; `%gs` is loaded with `NULLSEL` on every kernel entry, so it is free. Per-CPU GDT is needed anyway for `TSS_SEL` and the task LDT slot. Cheaper than a local APIC ID lookup on every call. |
| `cpu_number()` on ppc | New `cpu_number` field in `per_proc_info`, read through `sprg0` | Every exception already arrives with `sprg0` = physical `per_proc_info`; the virtual address is stored in the same struct. |
| i386 interrupts on secondaries | Local APIC only: timer and IPIs. `spl` on a secondary programs the APIC task-priority register; CPU 0 keeps the PIC mask logic | Devices stay on CPU 0 by design (drivers are master-bound), so no I/O APIC work is required. |
| i386 discovery | Kernel-side scanner `machdep/i386/mpspec.c` (MP floating pointer, MP config table, ACPI RSDP/RSDT/XSDT/MADT), written as a host-testable pure parser so it can move into `drvPExpert` when that lands; UEFI loader passes the RSDP address in the boot struct | The i386 platform expert is unbuilt and its P1–P4 plans are large. SMP should not wait on it, and the parser style matches what the P3 plan specifies. |
| i386 AP start | INIT-SIPI-SIPI to a real-mode trampoline in a page from `alloc_cnvmem()`; the AP loads the kernel `cr3`, its own GDT, a per-CPU stack, then calls `slave_main()` | Standard; the conventional-memory allocator already exists in `i386_init.c`. |
| ppc AP start | Patch the system-reset vector at physical `0x100` with a branch to the secondary entry, pulse the CPU's KeyLargo soft-reset GPIO (offset from the cpu node's `soft-reset` property), wait for the AP to publish itself, restore the vector | This is how Mac OS X and Linux start Core99 secondaries; it needs no Open Firmware call at run time. |
| ppc interrupt controller | Extend `mpic.c` with per-CPU register banks (stride `0x1000`), unmask one IPI vector per purpose, keep all device destinations at CPU 0 | Minimal change to a driver that already has host tests. |
| ppc timebase | Synchronise with the `timebase-enable` GPIO during AP start when the cpu node has that property; otherwise accept per-CPU skew and never compare timebase values across CPUs | Needed for a monotonic system clock; property-driven so it is safe where the GPIO is absent. |
| TLB coherence | i386: `cpus_using` bitmask + shootdown IPI, Mach 3 style. ppc: `pmap` lock around hash-table updates, `sync; tlbie; eieio; tlbsync; sync` | Standard for each architecture; ppc broadcasts `tlbie` in hardware. |
| Configuration | New `SMP` config per arch: `SMP = [RELEASE multi16]` on i386, `SMP = [RELEASE multi2]` on ppc; `RELEASE` stays uniprocessor until SMP is validated, then flips | Keeps the shipping kernel unchanged during bring-up. 32-bit PowerPC Macs top out at two CPUs; i386 guests and hosts routinely have more. |
| Phase order | Compile `NCPUS > 1` uniprocessor first, then per-CPU plumbing, then i386 bring-up under QEMU, then ppc bring-up on hardware, then coherence and hardening | Each phase boots and is testable before the next; i386 gets the emulator, ppc gets the design proven on i386 first. |

## Architecture

### Execution model

```
CPU 0 (master)                        CPU 1..N-1
------------------------------        -------------------------------
device interrupts (PIC / MPIC)        local timer + IPIs only
BSD syscalls, signals, exit           Mach traps, page faults, IPC
BSD kernel threads, DriverKit         user threads, Mach daemons,
   I/O threads (bound)                   idle thread
Mach core                             Mach core
```

A user thread on CPU 1 that issues a BSD syscall enters `unix_syscall`, which
calls `unix_master()`. That sets `bound_processor = master_processor` and
blocks; the scheduler resumes the thread on CPU 0, where the syscall runs with
exactly the interrupt-masking guarantees it has today. `unix_release()` before
`thread_exception_return()` unbinds it. Threads that never leave BSD (BSD
daemons, DriverKit I/O threads) are bound once at creation.

Mach paths that call into BSD from arbitrary context are the audit surface:
`check_for_ast` signal handling, `thread_terminate`/`task_terminate` process
teardown, `kern_exec`, the vnode pager (already funnelled), console output
(already funnelled) and kernel-server loading. The plan lists them.

### Per-CPU state

Both architectures get a `cpu_data_t` (ppc already has one) holding at least:

```c
typedef struct {
	int		cpu_number;
	thread_t	active_thread;
	vm_offset_t	interrupt_stack;	/* top of this CPU's intstack */
	int		interrupt_level;	/* nesting depth */
	spl_t		current_ipl;		/* what spl() reads on secondaries */
	int		preemption_level;
	int		simple_lock_count;
	unsigned	flags;
} cpu_data_t;
extern cpu_data_t cpu_data[NCPUS];
```

- **i386:** `gdt[NCPUS][GDTSZ]`; each CPU's `CPUDATA_SEL` descriptor has base
  `&cpu_data[cpu]`; `%gs` is loaded with it on every kernel entry in
  `locore.s` (where `NULLSEL` is loaded today) and by the AP start code.
  `TSS_SEL`, `LDT_SEL` and the double-fault task gate become per-GDT entries
  mapped by `pcb.c` on that CPU's GDT. `locore.s` replaces the five
  `movl _stack_pointers,%esp` with a `%gs`-relative load.
- **ppc:** `per_proc_info[cpu]` gains `cpu_number` and points at
  `cpu_data[cpu]`, `active_stacks[cpu]`, `need_ast[cpu]` and its own
  `intstack`. `istackptr` becomes a `per_proc_info` field; `hw_exception.s`
  and `cswtch.s` read it through `r2`/`sprg0` instead of the global.

Per-CPU interrupt stacks: `INTSTACK_SIZE * NCPUS` on ppc; a new
`interrupt_stack[NCPUS]` on i386 used by the local-APIC vectors (device
interrupts on CPU 0 keep the current stack discipline).

### Interrupts, spl, IPIs, clocks

| | i386 | ppc |
|---|---|---|
| Device IRQs | 8259 on CPU 0 (unchanged) | MPIC sources, destination mask CPU 0 (unchanged) |
| Local timer | LAPIC timer at `hz`, calibrated against the PIT at boot | Decrementer, programmed by each CPU in `slave_main` |
| IPI vectors | `IPI_AST`, `IPI_TLB`, `IPI_HALT` in the `0xF0` range, sent through the ICR | MPIC IPI 0..2 with the same meaning, per-CPU dispatch registers |
| `spl` on secondaries | `cpu_data.current_ipl` + LAPIC TPR | `cpu_data.current_ipl` + that CPU's MPIC task-priority register |
| `cause_ast_check(processor)` | ICR fixed IPI to the target's APIC ID; the handler sets `AST_BLOCK` in `need_ast[cpu]` and returns through the normal AST check | MPIC IPI to that CPU; handler identical |
| `clock_interrupt()` | Runs on every CPU from its local timer; `hardclock()` and callouts remain master-only (existing `master_cpu` checks) | Same, from the decrementer |

### pmap and TLB coherence

- **i386:** `pmap->cpus_using` becomes a bitmask maintained by
  `PMAP_ACTIVATE`/`PMAP_DEACTIVATE`; every place that calls `flush_tlb()` or
  `invlpg()` after changing a mapping also calls `pmap_update_tlbs(pmap,
  start, end)`, which sends `IPI_TLB` to the other CPUs in the mask and spins
  until they acknowledge. The kernel pmap always targets all running CPUs.
- **ppc:** hash-table insert/remove/protect paths take the pmap's simple lock;
  each `tlbie` is wrapped `sync; tlbie; eieio; tlbsync; sync`. The 7400-class
  parts snoop `tlbie` in hardware, so no IPI is needed for user mappings.
  Kernel BAT changes never happen after boot.

### Discovery and secondary-CPU bring-up

**i386.** `mpspec.c` finds the MP floating pointer (EBDA, top of base memory,
`0xF0000`–`0xFFFFF`) and the ACPI RSDP (same areas, plus the address the
UEFI loader stores in a new `KERNBOOTSTRUCT` field taken from the reserved
area). It fills `struct mp_cpu { u8 apic_id; boolean_t bsp; boolean_t
enabled; } mp_cpus[NCPUS]` and the LAPIC base. `start_other_cpus()` maps the
LAPIC uncached, enables it on the BSP, allocates the trampoline page, and for
each enabled non-BSP CPU: copies the trampoline, writes that CPU's stack and
GDT pointer into it, sends INIT, waits 10 ms, sends SIPI twice 200 µs apart,
waits up to 100 ms for `machine_slot[cpu].running`. The trampoline switches to
protected mode, loads the temporary GDT, sets `cr3` to the kernel page
directory, enables paging, jumps to `slave_start_high`, which loads the
per-CPU GDT/TSS/`%gs`, enables its LAPIC and timer, and calls `slave_main()`.

**ppc.** `initialize_processors()` (drvPExpert) walks `/cpus`, records each
child with `device_type` `cpu`, its `reg`, `soft-reset` and `timebase-enable`
properties, and fills `machine_slot[i].is_cpu`. `start_other_cpus()` saves the
32-bit word at physical `0x100`, patches in a branch to `secondary_start`
(physical, in `start.s`), pulses the CPU's soft-reset GPIO (write
`OUTPUT_ENABLE`, read back, 1 µs, write `0`), waits for
`machine_slot[cpu].running`, restores the vector. `secondary_start` runs with
translation off: it copies HID0 and L2/L3 configuration from CPU 0's saved
values, programs BATs identically to CPU 0, loads `sprg0` with its physical
`per_proc_info`, switches to its own interrupt stack, turns on translation,
and calls `slave_main()`. If the cpu node has `timebase-enable`, CPU 0 freezes
the timebase through that GPIO, both CPUs load the same value, and CPU 0
releases it.

### Configuration and build

- `conf/MASTER.i386`: `#  SMP = [RELEASE multi16]`; `conf/MASTER.ppc`:
  `#  SMP = [RELEASE multi2]`; `conf/Makefile` gains an `smp` build type.
- `conf/files.i386` adds `machdep/i386/mpspec.c`, `lapic.c`, `mp_start.s`,
  `mp.c`; `conf/files.ppc` adds `machdep/ppc/mp.c` and the secondary entry in
  `start.s`; `drvPExpert` adds `powermac/cpus.c`.
- Nothing in the `NCPUS == 1` build changes behaviour; the `RELEASE` config
  is untouched until the final phase.

### Panic, debugger, shutdown

- `panic()` sends `IPI_HALT` to every other running CPU after taking
  `panic_lock`; the handler marks the slot not running and spins with
  interrupts off, so the panicking CPU owns the console.
- `enter_debugger` / miniMon / kdp stop the other CPUs the same way and resume
  them on continue.
- `kern_shutdown.c` already walks the processors; `halt_cpu()` halts only the
  caller. `md_do_shutdown` runs on the master.

## Phases

1. **Build with `NCPUS > 1` on one CPU.** Define the missing symbols
   (`cause_ast_check`, `init_ast_check`, `slave_config`, `start_other_cpus`,
   `ns_hardclock_init`, `machine/cpu_number.h`), fix bit-rot, boot the `SMP`
   config on QEMU and on the ppc build box with one CPU. No behaviour change.
2. **Per-CPU plumbing.** i386 `%gs` cpu data and per-CPU GDT; ppc
   `per_proc_info` cpu number and per-CPU interrupt stack; per-CPU `spl` and
   `fp_thread`; master binding at `unix_syscall`, AST/signal path, kernel
   threads, DriverKit. Still one CPU running; verifies nothing regressed.
3. **i386 bring-up under QEMU.** `mpspec.c` with host tests, UEFI RSDP
   handoff, LAPIC driver, trampoline, `slave_main`, IPIs, LAPIC timer.
   Exit: `hostinfo` reports N processors, `-smp 4` boots to multi-user and
   survives a parallel build.
4. **ppc bring-up on hardware.** `/cpus` discovery, MPIC per-CPU banks and
   IPIs, decrementer on secondaries, soft-reset start, timebase sync. Exit:
   dual-G4 boots to multi-user with two running slots.
5. **Coherence and hardening.** i386 TLB shootdown, ppc pmap locking, binding
   audit, `MACH_LDEBUG` runs, panic/debugger/shutdown with several CPUs,
   stress under `MACH_ASSERT`.
6. **Default and docs.** Flip `RELEASE` to the multiprocessor count, update
   `docs/boot/*.md`, add `docs/kernel/smp.md`.

## Verification strategy

- **Host tests** (repository convention: `tools/<name>/` and
  `drvPExpert/tests/Makefile.host`, C89, no kernel headers beyond stubs):
  MP-table and MADT parsers against synthetic tables; LAPIC ICR and trampoline
  layout encoders; `cpu_data_t` offset assertions used by `genassym`; MPIC
  per-CPU offset and IPI register computations; the ppc `soft-reset` GPIO
  write sequence; device-tree `/cpus` walker over a captured tree.
- **QEMU i386:** `vm/qemu_boot.py` and `vm/run-q35-uefi.sh` gain an `--smp`
  option. Every i386 phase boots with `-smp 1` and the last two with
  `-smp 2` and `-smp 4`; the serial log shows `cpu N: up` lines and
  `hostinfo` output.
- **ppc:** QEMU `mac99` is single-CPU, so phases 1–2 run there and on the
  build box; phases 4–5 need a dual-CPU G4 with a serial console. Boots use
  a temporary disk image copy, per `CLAUDE.md`.
- **Behavioural checks:** `hostinfo`; `processor_set` info; a two-thread
  spin test that expects both CPUs to reach `CPU_STATE_USER`; `make -j` of a
  kernel package; `kdp`/miniMon entry and continue on the secondary.

## Risks

1. **ppc hardware-only validation.** No emulator covers a dual-CPU 32-bit
   Mac. Mitigation: prove the shared design on i386 first, keep every ppc
   change UP-safe and boot-tested on QEMU, and gate secondary start behind a
   boot argument (`smp=0` parks them) so a bad bring-up is recoverable.
2. **Mach-to-BSD entry points missed by the binding audit.** A BSD path
   reached from a secondary CPU runs unprotected. Mitigation: assert
   `cpu_number() == master_cpu` in `unix_syscall`'s callee table and in
   `sleep()`/`tsleep()` under `DEBUG`, so a miss is a loud panic in the test
   build rather than a silent corruption.
3. **Syscall migration cost.** Every syscall from a secondary CPU takes two
   context switches. This is the accepted cost of the model; the funnel
   follow-on removes it. The scheduler's refusal to IPI the master
   (`sched_prim.c` `thread_setrun`) adds up to one tick of latency; the plan
   makes that a tunable.
4. **Kernel ObjC runtime (`libkobjc`) method-cache updates** are not known to
   be MP-safe. Mitigation: all ObjC code in the kernel is DriverKit and
   therefore master-bound; documented as a constraint of the model.
5. **Register offsets taken from other systems' sources** (KeyLargo GPIO
   numbers, MPIC per-CPU stride, LAPIC timer calibration) must be verified on
   the target; the plan reads GPIO offsets from the device tree and only
   falls back to constants with a console warning.
6. **`locore.s` and `hw_exception.s` edits** touch every trap. Mitigation:
   each is a separate commit, boot-tested UP before any secondary starts.
7. **OVMF and ACPI.** The legacy RSDP scan fails under UEFI; without the
   boot-struct field the kernel sees one CPU. That is a safe failure, and the
   field makes it work.

## Open questions for the maintainer

1. Master-bound BSD/DriverKit first, funnel later — agreed? The alternative
   (funnel from the start) is a larger change to `thread_block` and every
   interrupt-level BSD path.
2. i386 discovery in the kernel now, moving into `drvPExpert` when it exists —
   or block SMP on the platform-expert P1–P3 plans?
3. Which dual-CPU PowerPC machine is available for phase 4, and does it have
   a serial console? The MacRISC spec names a `RackMac1,1`; a dual
   `PowerMac3,x` on the Sawtooth path is the other candidate.
4. `multi16` for i386 and `multi2` for ppc, or one value for both?
