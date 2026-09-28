# i386 Kernel Audit for Modern Machines — Findings

Date: 2026-09-26
Status: findings verified against source; no code changed

Companion plan: [plan.md](plan.md)

## Scope

`src/kernel-7` machine-dependent i386 code: `machdep/i386`, `mach/i386`,
`bsd/i386`, `bsd/dev/i386`, `kernserv/i386`, the i386 idle path in
`kern/sched_prim.c`, the PCI bus driver in `src/drivers-i386/bus/drvPCIBus`,
and the memory-sizing path in `src/boot-2/i386`.

The question asked: what in this 1999 Darwin 0.3 kernel breaks, or is
needlessly slow, on hardware and hypervisors from the last fifteen years
(multi-GHz CPUs, 1–4 GB+ RAM, QEMU/KVM, VirtualBox, VMware, UEFI, machines
with no ISA-era devices).

Every finding below was read in the source by a second pass after the initial
sweep. **Confirmed** means the code does what is described. **Latent** means
the code is wrong but the current NeXT toolchain or single-CPU design masks
it. **Speculative** means the trigger depends on firmware or hardware
behaviour that was not tested.

Two findings overlap existing design work and are only summarised here:

- Memory ceiling and E820 handling → `docs/superpowers/specs/2026-07-25-i386-large-memory-design.md`
  and its plan `docs/superpowers/plans/2026-09-20-i386-large-memory.md` (unstarted).
- CPUID-based CPU identification → `docs/superpowers/specs/2026-07-24-i386-cpu-detection-design.md`.

## Tier 1 — Breaks boot or corrupts state on modern machines

### 1.1 More than ~800 MB of RAM overruns the kernel page directory — Confirmed

`machdep/i386/pmap.c:398-416` (`pmap_bootstrap`) maps all physical memory
V==P from kernel VA 0, then reserves `64 MB + zone_map_sizer() +
buffer_map_sizer()` after it. The kernel window is 1 GB
(`mach/i386/vm_param.h:69`). `kernel_pmap->root` is offset 768 entries into
a single 1024-entry page-directory page, and `pd_to_pd_entry`
(`pmap_inline.h:117`) indexes it with VA bits 22–31. Any kernel VA ≥ 1 GB
therefore writes past the page.

`size_memory()` (`i386_init.c:448-466`) applies no clamp. With
`zone_map_sizer` capped at 128 MB and `buffer_map_sizer ≈ mem/50 + ≤64 MB`,
the reserve is ≈ 1.15 × mem + 128 MB, so the ceiling is about 780 MB.

Failure mode: `panic("pmap_kernel_pt_alloc")` if the stray entry happens to
have its valid bit set, otherwise silent corruption of whatever
`alloc_cnvmem` handed out after the directory page.

Trigger: any VM or PC with ≥ 1 GB, unless booted with `maxmem=`.

Covered by the large-memory plan. This audit only adds: the interim clamp in
`size_memory()` is the single highest-value change in the whole list and
should not wait for the rest of that plan.

### 1.2 `copyin`/`copyout`/`copywithin` leak the fault-recovery vector — Confirmed

`machdep/i386/fault_copy.c:288-295`, `:337-344`, `:383-390`. Each calls
`set_recover(&&do_fault)` and then, for `len < MIN_TO_ALIGN` (16 bytes),
returns 0 without `clear_recover()`. Only the long paths clear it
(lines 316, 365, 411).

Nearly every syscall copies a small argument block, so `thread->recover`
almost always points at a `do_fault` label inside a frame that no longer
exists. The next genuine kernel fault (`trap.c:256,318,458`
`kernel_try_recover`) jumps into that dead frame instead of panicking: the
fault is swallowed, `EFAULT` is returned to whichever caller's frame is
found, and callee-saved registers are restored from garbage. Panics become
silent corruption.

### 1.3 `us_spin` calibration overflows, or divides by zero, on fast CPUs — Confirmed

`machdep/i386/machine_clock.c:161-189`. One `us_spin(1)` (0x2000 empty
iterations, ~2 µs at 3 GHz) is timed against PIT counter 0, then

    us_spin_us_const = 0x2000 * (1193167 / d) / 1000000

in `unsigned int`. For d = 2 the product is 4.89 × 10⁹ and wraps, giving
592 instead of 4887: every `DELAY`/`IODelay` is ~8× too short. For d = 0 the
kernel takes a divide trap at boot. d is typically 2–6 on a modern CPU, and
the four port I/Os inside the timed window are VM exits under a hypervisor,
which inflates d and shortens delays further. One sample, no sanity check.

`DELAY` feeds ATA, UART, keyboard-controller and DMA reset timing.

Latent on top of this: the timed loop has no `volatile` and an optimising
compiler may delete it entirely.

### 1.4 CR4 is never written — Confirmed

No `cr4` access exists in `src/kernel-7` or `src/boot-2` (the only hits are
PPC headers and NASM opcode tables). The kernel runs with whatever CR4 the
firmware left.

- CR4 = 0 (legacy BIOS, SeaBIOS): `OSFXSR` is clear, so any SSE
  instruction raises #UD → `EXC_BAD_INSTRUCTION` → SIGILL. Binaries from a
  modern compiler that default to SSE math die on first use.
- `OSFXSR` = 1 (some UEFI/CSM paths): SSE executes, but `fp_save`/
  `fp_restore` (`fp_support.c:292-397`) use FNSAVE/FRSTOR into a 108-byte
  area. XMM0–7 and MXCSR are never saved, so two SSE-using processes
  silently corrupt each other on every context switch.
- Inherited PGE/PSE/VME bits also change behaviour; VME in particular
  alters V86 semantics for `pc_support`.

### 1.5 #AC and later vectors get a fake error code — Confirmed for 0x11

`locore.s:44-53`: `EXCEPTION` pushes `$0` then the vector; `EXCEPTERR`
pushes only the vector because the CPU already pushed an error code.
Vector 0x11 (#AC) is declared with `EXCEPTION` (`locore.s:87`) although the
CPU pushes an error code for it. The frame is off by four: `eip` holds the
error code, `cs` holds EIP, and the `iret` returns to garbage.

Trigger: a user process with CR0.AM set and EFLAGS.AC set. The kernel
preserves inherited CR0 bits (`pmap.c:341` sets only PG/WP;
`fp_support.c` read-modify-writes).

The same applies to #CP (0x15), #VC (0x1D) and #SX (0x1E) if they are ever
given stubs.

### 1.6 Vectors 0x50–0xFF index `dispatch_table[16]` out of bounds; NMI is an ordinary trap — Confirmed

`locore.s:151-326` routes every vector from 0x40 to 0xFF through the
`INTERRUPT` macro to `intr_handler`. `intr.c:682` computes
`irq = trapno - INTR_VECT_OFF` and indexes `dispatch_table[irq]` with no
check against `INTR_NIRQ` (16, `intr_internal.h:48`). The garbage entry is
then used for `set_masked_ipl`, `send_eoi` and an indirect call.

Trigger: a LAPIC spurious-interrupt vector (commonly 0xFF), or any stray
vector from an IOAPIC or virtual-wire setup.

Vector 2 (NMI) is declared with `EXCEPTION` and reaches `trap_handler`.
`trap.c` has no case for it: in kernel mode the `default:` arm panics
(`trap.c:375-392`); in user mode it delivers `EXC_BAD_INSTRUCTION` code 2
to whichever thread was running (`trap.c:188`). `virsh inject-nmi`,
VMware "send NMI", or a chipset watchdog kills a random process or the
machine.

### 1.7 Reboot hangs on machines with no 8042 keyboard controller — Confirmed

`bsd/dev/i386/kbd_entries.m:53`: `while (inb(K_STATUS) & K_IBUF_FUL)` with
no bound, run with interrupts off from `md_do_shutdown`. With no 8042 the
port reads 0xFF and the loop never exits. Legacy-free PCs, Hyper-V Gen 2
and some cloud images hang on reboot.

## Tier 2 — Correctness and robustness

### 2.1 Idle loop halts once, then busy-spins — Confirmed

`kern/sched_prim.c:1693-1729`. `MARK_CPU_IDLE` → `PMSetCpuState(PM_CPU_IDLE)`
issues a single `hlt` (`APM_i386.c:149`) at the top of the outer loop. The
inner `while (*threadp == NULL && *gcount == 0 && *lcount == 0)` spins with
nothing in it; the comment "machine_idle is a machine dependent function,
to conserve power" has no code behind it. An idle guest pegs a host core.

### 2.2 Interrupts: 8259 only, no IRQ sharing — Confirmed

`intr.c:489` `if (dispatch_table[irq].routine) return FALSE;` refuses a
second handler on a line. In PIC mode firmware routes all PCI INTx through
4–8 PIRQ links (QEMU i440fx/q35 use 5/9/10/11), so the second PCI driver on
a line fails to attach. No IOAPIC, no LAPIC, no MSI: devices on IOAPIC
inputs 16–23 or MSI-only devices are unreachable. The VirtIO design
(`docs/superpowers/specs/2026-09-24-virtio-driver-set-design.md`) already
lists shared IRQs as a kernel prerequisite.

Speculative: UEFI without CSM may leave PIRQ routers unprogrammed or the
LAPIC out of virtual-wire mode, in which case no PCI interrupt arrives.

What is correct today: spurious IRQ 7/15 handling, specific EOI ordering,
mask-before-EOI for level-triggered lines (`intr.c:703-745`).

### 2.3 Timekeeping — Confirmed

- Time advances only by counting IRQ0 ticks (`machine_clock.c:97`,
  `:403-437`). No resync from TSC or RTC. Ticks lost while the vCPU is
  descheduled, or while ipl ≥ 6 masks IRQ0 for longer than one period, are
  lost for good.
- `TIMER_CONSTANT` (`timer.h:84`) is 1193167; the PIT runs at 1193182 Hz.
  With divisor rounding the clock runs ~15 ppm slow, ≈ 1.3 s/day on bare
  metal.
- Every `clock_get_counter` (`gettimeofday`, `microtime`) does a PIT latch
  plus two `inb`s: three VM exits per timestamp.

### 2.4 RTC — Confirmed

`bsd/dev/i386/rtc.c`:

- `:86` `inb(RTC_DATA) & RTC_VRT == 0` parses as `& (RTC_VRT == 0)` = `& 0`;
  the "RTC invalid" check never fires.
- `rtcinit` writes `RTC_HM` (0x02) to register B, which forces BCD and
  24-hour mode and clears DSE/PIE/AIE/UIE. Firmware that keeps the RTC in
  binary mode then reads a wrong date.
- `rtcget` checks update-in-progress once and reads the registers once; a
  vCPU preempted in between reads a torn value.
- Century inferred as `yr < 70`; 32-bit `time_t`.

### 2.5 BIOS/APM call path loses the return value — Confirmed

`bios_asm.s:107-111`: after the far call returns, `mov $KDSSEL, %eax` runs
before `movl %eax, save_eax`, so APM error codes (AH) are lost. `bios32`
locking and fault recovery are `#if NOTYET`; a BIOS fault is fatal.

### 2.6 Signal frames — Confirmed

`unix_signal.c:60-160` (`sendsig`): the handler's EFLAGS is the interrupted
EFLAGS unmodified, so DF (and TF) are not cleared; the frame is not 16-byte
aligned; `struct sigcontext` (`bsd/i386/signal.h`) carries no FP state. A
signal landing inside a backwards `rep movs` runs the handler's `memcpy`
backwards; a handler using x87 clobbers the interrupted x87 stack; a
modern-ABI handler that spills with `movaps` faults.

### 2.7 TLB invalidated before the PTE is changed — Confirmed pattern, low risk on UP

`pmap.c:906, 973, 1057, 1104, 1228, 1247`: `PMAP_UPDATE_TLBS` runs before
the entry is cleared or downgraded. `pmap_deallocate_mappings`
(`pmap.c:1594-1601`) clears the PDE and recycles the page table with no
flush after the clear.

Since the P6, a speculative page walk in the window can refill the stale
entry. On this single-CPU kernel nothing touches the affected VA inside
that window, so the practical exposure is small; it becomes a real
corruption path the moment SMP is considered. The correct order costs
nothing, so it is worth fixing regardless.

### 2.8 Kernel-mode #NM is ignored — Confirmed, speculative trigger

`trap.c:228` `case T_NOEXTENSION: return;` with no `clts`. Kernel or driver
code that executes an x87 instruction while CR0.TS is set re-faults forever;
with TS clear it silently corrupts the owning thread's FPU context. The
i386 kernel is not built with `-msoft-float`.

### 2.9 Double-fault task stack is 1 KB — Confirmed

`dbl_fault.c:47-48`. `kernel_trap`, `printf`, `panic` and the kdp path run
on it. A second overflow triple-faults: a silent reset instead of a panic
message.

### 2.10 `memcmp` ordering result is garbage — Confirmed, low impact

`libc/memcmp.c:68-80`. After `repe cmpsb`, the mismatch path does `subb` on
the low byte of `%ecx` and then `movl %ecx` out, so bits 8–31 of the result
are the remaining `rep` count. Equality is correct; sign and magnitude are
not. Nothing in the kernel appears to depend on the sign.

### 2.11 Minor confirmed items

- `dma.c:370`: ISA bounce decision checks only the start address; a
  transfer that starts below 16 MB and crosses it is not bounced.
- `pc_support/PCtimers.c:50`: `TVALSPEC_USEC` sets `tv_nsec = usec * 1000`
  without reducing modulo one second; ≥ 1 s double-counts, ≥ 4.29 s
  overflows.
- `PCIKernBus.m:139-170`: when function 0 is absent the loop `continue`s
  through functions 1–7 (≈ 65 k config probes over 256 buses, 4 port I/Os
  each); the multifunction bit is tested on every function, not only
  function 0, so a function N > 0 without the bit ends the scan early. No
  ECAM/MMCONFIG access.

## Tier 3 — Performance

- **TLB**: `pmap_update_tlbs` (`pmap.c:181-184`) reloads CR3 for any range
  larger than one 8 KB page. CR4.PGE is never enabled and the PTE bitfield
  (`pmap.h:50-66`) has no G bit, so every CR3 load also discards all kernel
  translations. The V==P map uses 4 KB pages (no PSE).
- **Context switch** (`pcb.c:133-148, 186-201`): rewrites the GDT TSS
  descriptor, `ltr`, and read-modify-writes CR0 (`setts`) on every switch,
  even back to the thread that already owns the FPU. FNSAVE/FRSTOR are
  microcoded and slower than FXSAVE.
- **Interrupt path** (`intr.c:138-178, 720-766`): mask and unmask always
  write both PICs, plus one or two EOIs: 5–6 `outb` per interrupt, each a VM
  exit.
- **`copyout`** (`fault_copy.c:232-262`): one `movl %fs:` per word because
  `rep movs` cannot take a segment override on ES:EDI. Loading ES from FS
  around a `rep movsl` and restoring it is safe: `trap_handler` reloads ES
  on entry (`locore.s:338-341`).
- **Frame buffer**: mapped with default caching (`pmap.c:459`); no PAT, so
  no write-combining. Console scrolling hits uncached video memory.
- **Locks** (`mach/i386/simple_lock.h`): `locked` is not `volatile`, no
  `"memory"` clobber, no `pause`; `simple_unlock` uses a locked `xchg`
  where a plain store would do. `DRIVERKIT` forces `MACH_SLOCKS` on, so the
  real locks are compiled into the UP kernel.
- **Small primitives**: `ffs.c:45-54` loops bit by bit (hot in `select`);
  `memset`/`page_set` use 4-byte store loops; `memcmp` uses `repe cmps`.

## Latent toolchain hazards

These are correct with the in-tree NeXT `cc`/`as` and become bugs the day
the kernel is built with GNU tools.

- `libc/pagesize.c:57-66` `page_set` closes its loop with `jne .-30`,
  assuming `0x00(%reg)` is encoded with an explicit disp8 (30-byte body).
  GNU `as` drops the zero displacement, the body is 29 bytes, and the branch
  lands mid-instruction. `.align 2` is also read as 4 bytes (Mach-O) rather
  than 2 (ELF).
- `"&c"` input constraints and clobbers that overlap inputs in `memcpy.c`,
  `memmove.c`, `memcmp.c`, `fault_copy.c`, `pagesize.c`, `in_cksum.c:97`.
  Modern gcc and clang reject them outright.
- No `"memory"` clobbers on `cli`/`sti`/`set_cr3`/`invlpg`
  (`cpu_inline.h:67,75,172,193`), `inb`/`outb` (`io_inline.h`), or the lock
  primitives. A modern optimiser may move stores to `current_ipl` out of
  the `cli`/`sti` window or DMA descriptor writes past a doorbell `outb`.
- The empty `us_spin` loop (1.3) is deletable.

## Checked and found fine

- CR0.WP is set (`pmap.c:341`); kernel writes honour read-only and COW.
- CLD on every kernel entry (`locore.s:349, 404, 464, 522, 580`); the
  `std`/`cld` window in `memmove` is covered.
- CR0.NE = 1 (`fp_support.c:125`): x87 errors go to #MF, no IRQ13/FERR#
  dependence. CR0.MP/EM correct for a hardware FPU; detection always
  selects `FPU_HDW` on modern CPUs.
- CPU subtype is forced to 586 (`i386_init.c:378-440`), so family 6/15
  cannot be misdetected (see the cpu-detection spec for the real fix).
- NT-through-call-gate and TF-on-call-gate are handled (`trap.c:302, 435`).
- IOPB absent by default (`TSS_SIZE(0)`).
- `lcall` call-gate syscalls with four segment reloads each way are slow
  but correct on every modern CPU and hypervisor.
- `pv_entry_zone` is expandable; the 10000 max does not panic.
- Missing APM is handled: the kernel falls back to `hlt` and
  `PM_R_NOT_CONNECTED`.
- `serial_dbg` copes with a missing UART.
- `KB(extmem)` does not overflow for the values the loaders actually
  produce (they subtract 1 MB and cap at 4 GB); the large-memory spec's
  exact-4 GB overflow needs the raw 4194304 KB figure, which the E820 path
  never emits.

## Not verified

Dropped from the sweep because the second pass did not confirm them:

- That IDT entries 0x88+ are trap gates rather than interrupt gates.
- The `ret == FALSE` vs `PM_R_SUCCESS` comparison in `PMSetCpuState`.
