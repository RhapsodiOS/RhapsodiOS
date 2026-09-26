# i386 Kernel Audit — Implementation Plan

Date: 2026-09-26
Spec: [spec.md](spec.md)

**Goal:** Work the audit findings from the cheapest, highest-value fixes to
the structural ones, one commit per task, each boot-tested on a throwaway
disk image before it lands.

**Ground rules**

- 1999 toolchain: no C99, no `long long` in kernel code, locals at the top
  of a block. Compile-time checks use `typedef char name[(cond) ? 1 : -1];`.
- Every task is one commit with the message prefix `kernel: ` (or `boot: `
  for `src/boot-2`). No metadata in commit bodies.
- Boot gate for every task: build the i386 kernel, graft it onto a copy of
  the golden image (`vm/graft-kernel.py` on a temporary image, never the
  shared one), boot under QEMU, reach multi-user, run the task's specific
  check, then `reboot` and confirm the guest restarts.
- Don't fold tasks together. A regression must be bisectable to one change.
- Phase 1 has no dependencies between tasks and can be split across
  sessions. Phases 2 and 3 are ordered.

## Phase 1 — Small, isolated fixes

### Task 1: Clamp physical memory in `size_memory()`

Spec 1.1. Interim fix; the full change is the large-memory plan.

- [ ] In `machdep/i386/i386_init.c` `size_memory()`, after `end_of_memory`
      is chosen, compute the reserve the way `pmap_bootstrap` will
      (`64 MB + zone_map_sizer() + buffer_map_sizer()`; both are callable
      this early because they read only `mem_size`) and reduce
      `end_of_memory` until `end_of_memory + reserve <= VM_MAX_KERNEL_ADDRESS`.
      A simple loop stepping down by 16 MB is fine; this runs once.
- [ ] Print one line when the clamp fires: reported vs. used.
- [ ] Add `panic` in `pmap_kernel_pt_alloc` if `addr >= VM_MAX_KERNEL_ADDRESS`.
- [ ] Verify: QEMU `-m 1024` and `-m 4096` boot to multi-user without
      `maxmem=`; `sysctl hw.physmem` shows the clamped figure; `-m 512`
      still reports 512.

### Task 2: Clear the recovery vector on the short copy paths

Spec 1.2.

- [ ] `machdep/i386/fault_copy.c`: add `clear_recover();` before the
      `return 0;` in the `len < MIN_TO_ALIGN` branch of `copyin`,
      `copywithin` and `copyout`.
- [ ] Verify: boot to multi-user. From a shell, run a program that calls
      `read(fd, buf, 4)` then dereferences NULL via a syscall argument
      known to fault in the kernel (e.g. `ioctl` with a bad pointer);
      confirm `EFAULT` is returned rather than a hang or a later
      unexplained panic. A deliberate kernel NULL dereference (temporary
      test hook, not committed) must now panic instead of returning.

### Task 3: Fix the #AC stub frame

Spec 1.5.

- [ ] `machdep/i386/locore.s:87`: change `EXCEPTION(trp_0x11,0x11)` to
      `EXCEPTERR(trp_0x11,0x11)`.
- [ ] Clear CR0.AM explicitly in `i386_init` so the inherited bit does not
      decide whether user code can raise #AC at all.
- [ ] Verify: boot. With a temporary test that sets EFLAGS.AC and does a
      misaligned access, confirm SIGBUS/`EXC_I386_ALIGNMENT_CHECK` with a
      sane `eip` in the core, not a triple fault.

### Task 4: Bound-check the IRQ number; give NMI its own handler

Spec 1.6.

- [ ] `machdep/i386/intr.c` `intr_handler`: if `irq < 0 || irq >= INTR_NIRQ`,
      bump a `intr_cnt.stray` counter and return without touching the PIC.
- [ ] `locore.s`: a dedicated `int__nmi` stub that saves registers, calls
      a C `nmi_handler` (read port 0x61, `printf` once, return), and
      returns without `sti`. Do not route it through `trap_handler`.
- [ ] Verify: QEMU monitor `nmi` → kernel logs one line and keeps running.
      `info irq` before/after shows no stray-IRQ side effects.

### Task 5: Bound the 8042 wait on reboot

Spec 1.7.

- [ ] `bsd/dev/i386/kbd_entries.m` `kdreboot`: loop at most ~64 k
      iterations with a short `DELAY` each (this runs after Task 7 fixes
      `DELAY`; until then, use a raw count). If the status port reads
      0xFF, skip the 8042 entirely.
- [ ] Fall back to `outb(0xCF9, 0x02); outb(0xCF9, 0x06);` then a triple
      fault (load a zero-limit IDT, `int $3`).
- [ ] Verify: `reboot` on QEMU `pc` (has 8042) and on a `q35 -machine
      ...,i8042=off` guest both restart.

### Task 6: Halt in the idle loop

Spec 2.1.

- [ ] `kern/sched_prim.c` inner idle loop: `cli`; re-check
      `*threadp`, `*gcount`, `*lcount`; if still idle, `sti; hlt` (the
      `sti` shadow makes the check-then-halt atomic). Put the asm in
      `machdep/i386` behind a `machine_idle()` and keep the ppc side a
      no-op.
- [ ] Verify: idle guest drops from ~100 % to a few % host CPU (`top` on
      the host); `sleep 5` in the guest returns in 5 s, not later.

### Task 7: Rewrite `us_spin_calibrate`

Spec 1.3.

- [ ] `machdep/i386/machine_clock.c`: calibrate over a fixed PIT window of
      ≥ 10 ms (count `us_spin` iterations until the counter has advanced N
      ticks) instead of timing one short spin. Do the arithmetic as
      `(loops * 1000) / window_us`-style 32-bit math that cannot wrap
      for any plausible CPU speed; reject a zero window and fall back to
      a conservative constant with a printed warning.
- [ ] Mark the loop counter `volatile`.
- [ ] Verify: print the constant at boot; `DELAY(1000000)` from a test
      hook takes 1 s ± 5 % measured against the RTC on QEMU with and
      without KVM. ATA and keyboard still probe.

### Task 8: RTC fixes

Spec 2.4.

- [ ] `bsd/dev/i386/rtc.c:86`: `(inb(RTC_DATA) & RTC_VRT) == 0`.
- [ ] `rtcget`: read the registers twice until two reads agree.
- [ ] `rtcinit`: read register B, set only the bits we need (24-hour), and
      honour DM: if the RTC is in binary mode, skip the BCD conversion.
- [ ] Verify: `date` matches the host at boot on QEMU (`-rtc base=utc`)
      and after `date -u` sets the clock and the guest reboots.

### Task 9: PIT constant

Spec 2.3.

- [ ] `machdep/i386/timer.h:84`: `1193182`.
- [ ] Verify: guest clock drift over one hour against the host is below
      100 ms on QEMU.

### Task 10: Save the BIOS call return value

Spec 2.5.

- [ ] `bios_asm.s:107-111`: save `%eax` to `save_eax` before loading
      `KDSSEL`.
- [ ] Verify: APM-enabled boot logs the real return code on an APM error
      (force one with a bad function number in a temporary test).

### Task 11: Signal frame: DF, TF, alignment

Spec 2.6 (FP state is Phase 2).

- [ ] `unix_signal.c` `sendsig`: clear `EFL_DF` and `EFL_TF` in the
      handler's EFLAGS; round the frame down to 16 bytes before placing
      `sigframe`.
- [ ] Verify: a test program that installs a handler, then runs a
      backwards `rep movsb` with DF=1 and gets a signal in the middle,
      ends with correct memory contents.

### Task 12: Minor confirmed items

- [ ] `dma.c:370`: bounce when `phys + len > 16 MB`, not only when
      `phys >= 16 MB`.
- [ ] `pc_support/PCtimers.c:50`: `tv_nsec = (usec % USEC_PER_SEC) * NSEC_PER_USEC`.
- [ ] `PCIKernBus.m`: `break` when function 0 is absent; test the
      multifunction bit only on function 0.
- [ ] `trap.c:228` kernel #NM: `panic("kernel FPU use")` instead of
      `return;`.
- [ ] `dbl_fault.c`: 8 KB double-fault stack.
- [ ] Verify each: boot, PCI probe log unchanged apart from time,
      `stat` on a floppy transfer straddling 16 MB (if a floppy image is
      attached), and the DOS-emulation timer path via `pc_support`
      tests if any exist.

## Phase 2 — Ordered structural fixes

### Task 13: Write CR4 explicitly, x87-only for now

Spec 1.4, first half.

- [ ] `i386_init`: if CPUID exists, write `CR4 = 0`. This makes SSE a
      deterministic SIGILL instead of silent corruption, until Task 15.
- [ ] Verify: boot; a test binary executing `movaps` gets SIGILL on every
      firmware; `pc_support` V86 still works (VME cleared).

### Task 14: TLB invalidation order and page-table recycle

Spec 2.7.

- [ ] In `pmap_remove_range`, `pmap_remove_all`, `pmap_copy_on_write`,
      `pmap_protect` and `pmap_enter`, move `PMAP_UPDATE_TLBS` after the
      PTE store.
- [ ] `pmap_deallocate_mappings`: `PMAP_UPDATE_TLBS` for the section after
      clearing the PDE, before `pt_free_add`.
- [ ] `pmap_update_tlbs`: loop `invlpg` for ranges up to 32 pages; full
      CR3 reload above that.
- [ ] Verify: fork-heavy test (`make -j4` of a small tree) and a
      COW-specific test (parent writes after fork, child verifies) pass;
      no panics over a 1-hour stress run.

### Task 15: FXSAVE and SSE support

Spec 1.4, second half. Depends on Task 13.

- [ ] Grow `fp_state_t` to a 512-byte, 16-byte-aligned FXSAVE area in the
      pcb; keep the FNSAVE layout for `thread_get/set_state` and translate.
- [ ] `fp_save`/`fp_restore`: FXSAVE/FXRSTOR when CPUID.FXSR.
- [ ] Set `CR4.OSFXSR | OSXMMEXCPT`; `fp_init` sets MXCSR = 0x1F80.
- [ ] `trap.c`: vector 19 (#XM) → `EXC_ARITHMETIC`.
- [ ] Extend `sigcontext` with a versioned FP area; save it in `sendsig`,
      restore in `sigreturn`.
- [ ] Verify: two processes running SSE arithmetic in tight loops for ten
      minutes produce correct results; a signal handler that uses x87
      does not perturb the interrupted computation.

### Task 16: Shared IRQ handlers

Spec 2.2, near-term half. Unblocks the VirtIO plan.

- [ ] `intr.c`: replace the single `routine` per IRQ with a chain; keep
      the existing `intr_register_irq` signature and add
      `intr_register_shared_irq`. Only level-triggered lines (ELCR) may
      be shared.
- [ ] Verify: QEMU with two PCI devices routed to the same PIRQ (e.g.
      e1000 + a second NIC) both attach and pass traffic.

### Task 17: TSC-based timekeeping

Spec 2.3.

- [ ] Calibrate the TSC against the PIT at boot (reuse Task 7's window).
- [ ] `clock_get_counter` reads `rdtsc` when CPUID reports an invariant
      TSC (0x80000007 EDX bit 8); fall back to the PIT otherwise.
- [ ] Resync the tick-driven clock from the TSC each tick, so lost ticks
      no longer lose time.
- [ ] Verify: drift < 10 ms/hour under KVM with the guest paused for 30 s
      mid-run; `gettimeofday` cost measured in a tight loop drops by an
      order of magnitude.

### Task 18: Global pages and cheaper context switches

Spec Tier 3.

- [ ] Add the G bit to `pt_entry_t`; set it in `pmap_map` and
      `pmap_kernel_pt_alloc`; enable `CR4.PGE` when CPUID reports it.
      `flush_tlb()` for kernel ranges toggles PGE.
- [ ] `pcb.c`: one TSS per CPU, update only `esp0`; `ltr` only when the
      incoming thread has an I/O-bitmap TSS; `setts()` only when
      `new != fp_thread`.
- [ ] Verify: context-switch microbenchmark (pipe ping-pong) improves;
      no regressions in the Task 14 stress run.

## Phase 3 — Larger projects, each its own spec

Not planned here; listed so the audit is complete.

- **Memory above ~800 MB**: the large-memory plan
  (`docs/superpowers/plans/2026-09-20-i386-large-memory.md`).
- **E820 map into the kernel, `mem_region[]` with holes**: same plan.
- **IOAPIC/LAPIC and MSI** (spec 2.2, long-term half).
- **PAT and write-combined frame buffer** (spec Tier 3).
- **`copyout` via `rep movsl` with ES = FS**, `rep stosl` in `page_set`,
  `bsf` in `ffs` (spec Tier 3).
- **Inline-asm modernisation** (spec "Latent toolchain hazards"): local
  labels in `page_set`, `"memory"` clobbers, `volatile` on lock words,
  `"+m"` on `xchg` outputs. Only worth doing together with a decision to
  build the kernel with GNU tools.
