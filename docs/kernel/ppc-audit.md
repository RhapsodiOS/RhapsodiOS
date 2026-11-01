# PowerPC kernel and platform expert audit

Scope: `src/kernel-7/machdep/ppc`, `src/kernel-7/driverkit/ppc`,
`src/kernel-7/kernserv/ppc`, `src/kernel-7/mach/ppc`, the ppc paths in
`kern/`, `vm/` and `bsd/dev/ev.c` that the machdep code calls, and every
file under `src/drivers-ppc/bus/drvPExpert/powermac`. Every finding below
was checked against the cited lines. Items that came from a second
reviewer and were not re-traced end-to-end are marked *(not independently
re-traced)*.

The first pass was written against master at 267d9fbc. This revision
re-checks every item against master at 8e195a55, after the ppc-qemu merge
that boots on QEMU mac99 and g3beige. Line numbers are master's.
Items that master fixed or partly fixed say so in their heading; every
other item is still open. Section H covers code that is new since the
first pass.

The kernel is the MkLinux DR2 lineage: single processor, no kernel
preemption, kernel in segments 0-3 (0x0000_0000-0x3FFF_FFFF) with segment
registers 0-3 swapped to kernel VSIDs on every exception entry, user
segments 4-15 loaded at task switch, and copyin/copyout through a borrowed
segment register 14.

## What changed on master since the first pass

| Item | Status | Commit | Notes |
|------|--------|--------|-------|
| C1 Sawtooth OpenPIC base and Fat Man accesses | Fixed | eb4b43dd, 86f2501c | open-pic `reg` made absolute on Sawtooth; Fat Man and the 0xF204_1080 read guarded by `IsPEx()` |
| D1 hash table capped at 4 MB | Fixed | 8e195a55 | `32*1024*1024` now |
| B6 MPIC spurious vector aliasing source 49 | Fixed | 86f2501c | spurious vector is now 0xFF and dispatch stops on it |
| B7 Heathrow LEVELS never read; `INTT_` typo | Partly fixed | 2f4326b9 | Heathrow bank 1 PCI slots now sampled from LEVELS; Grand Central and O'Hare unchanged |
| C3 clock calibration divides by measured counts | Partly fixed | fa78ceaf, 036a053c | Gossamer, Yosemite and Sawtooth take clocks from OF; PowerSurge, PowerStar and PowerExpress still run the unguarded VIA test |
| C4 header drift between the two `interrupts.h` copies | Fixed | c14acd57 | copies now agree except the pexpert-only `PMAC_DEV_MPIC_DIRECT_BASE` |

Every other item is unchanged. In particular `unix_signal.c`, `pcb.c`,
`alignment.c`, `systemcalls.c`, `PseudoKernel.c`, `hw_exception.s`,
`lowmem_vectors.s`, `movc.s`, `misc_asm.s`, `trap.c`, `fault_copy.c`,
`interrupt.c` and `backsideL2.c` are byte-identical to the first pass, so
none of the security items in section A has been addressed.

Two open items matter more after the ppc-qemu merge:

- **B6, MPIC EOI before the handler.** The Sawtooth source table now
  follows 5.6 and programs most sources level-triggered, so more sources
  can be re-presented while their handler is still pending. B6 traces
  which drivers are exposed; none are today.
- **C4, no G4 PVR recognised.** QEMU mac99 presents a G4, so the L2 is
  never reported and the CPU subtype is `CPU_SUBTYPE_POWERPC_ALL` there.

One new Low finding is in section H: `pmap_set_cache_spec`, added for the
Screamer driver, can leave a cached BAT0 alias of a cache-inhibited page.
C3 also gains a latent overflow in the new OF clock path.

## Summary: what to fix first

| # | Where | What | Why it matters |
|---|-------|------|----------------|
| 1 | `unix_signal.c:200` | sigreturn copies the whole saved state, including the SR14 value, from user memory | Any process can point SR14 at kernel VSID 0-3 with supervisor key bits and read or write kernel memory through 0xE000_0000 |
| 2 | `pcb.c:448`, `unix_signal.c:52` | User MSR is only OR-ed, never masked | FP bit set without ownership reads another thread's live FPRs; IP bit moves the vectors and hangs the machine |
| 3 | `alignment.c:749,781` | lswi/lswx emulation writes to `(char *)r0_value + rT` | User-controlled kernel write; reachable in LE mode (via 2) or for a string op crossing a segment boundary |
| 4 | `systemcalls.c:283-305`, `PseudoKernel.c:258` | Blue Box syscalls 0x7FFF/0x7FFD have no privilege check; 0x7FFF stores through a raw user pointer; unknown numbers return stack garbage | Kernel write from any process, unbounded wired allocation, tear-down of another process's mapping |
| 5 | `hw_exception.s:1140-1142` | "Switch on interrupts" in the syscall handler is `rlwimi r0,r0,...`, a no-op | Every `sc` runs its prologue, argument copyin and the syscall body with MSR[EE]=0 until the first `splx(SPLLO)` |
| 6 | `interrupt.c:141-163` | Every spl level above SPLLO clears MSR[EE] | splbio/splnet/spltty/splsoftclock all mask the decrementer and every device |
| 7 | `grand_central.c:292-310` and the other three chips | VIA cascade dispatches `via1_interrupts[7]` on every VIA interrupt | Bit 7 of IFR/IER is always set; all six tables have 7 entries, so this reads the next table's entry 0 |
| 8 | `movc.s:240-246,281-287` | `pmap_copy_page` does `dcbst; sync; icbi; sync; isync` per 32-byte line | 256 syncs per page copy on the copy-on-write and fork path |
| 9 | `mpic.c:427-450` | MPIC writes EOI before the handler and re-acks in a loop with EE off | A mac-io level source on the default DriverKit handler would re-present forever on real OpenPIC hardware |

All nine are open. The first pass's items 8 (Sawtooth OpenPIC base) and
10 (hash-table cap) are fixed.

## A. Security and privilege boundaries

### A1. sigreturn lets a process choose its own SR14 value (High)
`machdep/ppc/unix_signal.c:200-202` copies an entire `struct ppc_saved_state`
from the user frame into `thread->pcb->ss`. The struct ends with
`sr_copyin` (`mach/ppc/thread_status.h:152`), and only `srr0`/`srr1` are
re-set afterwards. Both return paths load that field straight into the
hardware register: `hw_exception.s:1243-1245` (syscall return) and
`hw_exception.s:1664-1666` (trap return). Segment 14 is the process's own
0xE000_0000 segment in user mode, so the process picks T, Ks, Ku and the
VSID. VSID 0..3 are the kernel's; with Ku=0 the PP=2 pages are writable.
`set_thread_state` gets this right by re-deriving the value
(`pcb.c:448`).

Fix: copyin into a local, copy only the `ppc_thread_state` prefix into
the pcb, then set `ss.sr_copyin = pcb->sr0 + SR_COPYIN`. Using a local
also stops a fault mid-copy from leaving `pcb->ss` half written.

### A2. User-supplied MSR is never masked (High)
`pcb.c:446-450`:
```c
*((struct ppc_thread_state *)saved_state) = *state;
saved_state->sr_copyin = thread->pcb->sr0 + SR_COPYIN;
saved_state->srr1 |= MSR_EXPORT_MASK_SET;
```
Nothing is cleared. The value reaches `rfi` verbatim
(`hw_exception.s:1329`, `lowmem_vectors.s:701`). Consequences for a thread
another thread in the task sets state on: MSR[FP] set while
`per_proc_info.fpu_pcb` belongs to someone else means no FP-unavailable
trap fires and the thread reads and clobbers the other thread's registers;
MSR[IP] moves the exception prefix to 0xFFFn_nnnn and hangs the machine;
MSR[LE] makes the string and multiple instructions trap into the alignment
emulator (see A3). sigreturn clears POW/ILE/IP/LE (`unix_signal.c:52`) but
not FP.

Fix: `proc_reg.h:104-108` already defines `MSR_IMPORT_BITS` and
`MSR_PREPARE_FOR_IMPORT()`; use them in both places and add FP to the
sigreturn clear set.

### A3. String-load emulation writes through the value of r0 (High)
`alignment.c:749` and `:781`:
```c
bcopy((char *) align_buffer, (char *) ssp->r0+DSISR_BITS_REG(dsisr), nb );
```
The cast binds to `ssp->r0`, the saved register value, so the destination
is `user_r0 + rT`, not `&ssp->r0 + rT`. Up to 31 bytes that were just
copied in from the user's `dar` are written to that kernel address. The
string instructions reach this handler in little-endian mode and, on
implementations that trap them, when the operand crosses a segment or BAT
boundary. The guard on line 742 should also be `nr + rT > 32`, and `nb ==
0` (meaning 32 bytes) is not handled.

Fix: `bcopy(align_buffer, (char *)(&ssp->r0 + DSISR_BITS_REG(dsisr)), nb)`.

### A4. Blue Box syscalls are unprivileged and unsafe; unknown syscall numbers succeed (High)
`systemcalls.c:283-305`: for `code > nsysent` only 0x7FFA checks
`PCB_BB_MASK`. 0x7FFF calls `mapBlueBoxShmem` and 0x7FFD calls
`unmapBlueBoxShmem` for any caller, and any other large number leaves
`error == 0` with `rval[]` uninitialised, so lines 409-410 hand two words
of kernel stack back as the return value instead of ENOSYS.

`PseudoKernel.c:258` does `*addr = task_addr;` where `addr` is the raw
user register. Addresses below 0x4000_0000 are the kernel's segments; a
non-resident user address takes a kernel-mode DSI that trap.c resolves
against `kernel_map` and panics. `createEventShmem` (`bsd/dev/ev.c:106-110`)
wires `round_page(size)` with no cap, and 0x7FFD destroys whatever mapping
the real Blue Box currently holds.

Fix: initialise `rval`, return ENOSYS for unknown codes, apply the
`PCB_BB_MASK` check to all three codes, write the result with `copyout`,
and cap `size`.

### A5. NotifyInterruption (privileged) dereferences raw user pointers and hangs on a bad port (Medium)
`PseudoKernel.c:150,164-166,183-185` read and write five user pointers
under `splsched()` + `thread_lock()`; a non-resident page panics. If the
thread lookup fails, `:136-137` is `while (1);`. Also the loop at
`:103-106` copies out a send right for every thread in the task on every
call *(not independently re-traced)*.

Fix: copyin the descriptor words before taking splsched, copyout after,
and return EINVAL instead of spinning.

### A6. sendsig leaks four bytes of kernel stack (Low)
`unix_signal.c:74,121-128`: `context.sc_sp` is never set before the
`copyout`. Set it to `statep->r1`.

## B. Interrupts, spl and latency

### B1. All spl levels above SPLLO disable every interrupt (design, high impact)
`drvPExpert/powermac/interrupt.c:141-163`:
```c
if (lvl == SPLLO) { current_priority = lvl; interrupt_enable(); }
else              { interrupt_disable(); current_priority = lvl; }
```
The per-chip `*_set_priority_level` hooks are empty or unhooked
(`heathrow.c:240-243` is an empty function; the assignment at `:133` is
commented out). So splbio, splimp, splnet, spltty and splsoftclock all
mask the decrementer and every device for the length of the critical
section. `rtclock_intr` (`rtclock.c:116-129`) catches up on missed ticks,
so time is not lost, but scheduling, timeouts, ADB, serial and network
latency are bounded by the longest spl>0 section in the BSD layer.

Not a quick fix. The MPIC current-task-priority path exists but is under
`#if 0` (`mpic.c:348-373`). A cheaper intermediate step is to keep the
decrementer unmasked at levels below SPLCLOCK.

### B2. System calls enter C with interrupts masked (High)
`hw_exception.s:1140-1142`:
```
mfmsr	r0
rlwimi	r0,	r0,	0,	MSR_EE_BIT,	MSR_EE_BIT
mtmsr	r0
```
`rlwimi` with the same source and destination and a zero shift leaves the
register unchanged, and the handler was entered with EE clear
(`lowmem_vectors.s:660-662`). The trap handler does it correctly by
inserting the *saved SRR1's* EE bit into a fresh value
(`hw_exception.s:247-248`). Nothing in `systemcalls.c` enables EE, so a
syscall runs until its first `splx(SPLLO)` with interrupts off; getters,
sysctl-style copyouts and page faults taken during argument copyin all run
masked.

Fix: `ori r0,r0,MASK(MSR_EE)` (syscalls always come from user mode where
EE was set), followed by `isync` to match the trap path.

### B3. Trap return to user mode never checks for a pending AST (Medium)
`hw_exception.s:338-478` (`thread_return`): after `bl EXT(trap)` the
registers are restored, EE is disabled and `rfi` runs. The syscall exit
(`:1341-1354`), bootstrap exit and interrupt exit all call `check_for_ast`
first. The gap is exactly the successful user-mode fault path: a thread
that slept in `vm_fault` while a higher-priority thread was woken or a
signal was posted returns to user with the AST pending until the next
tick or syscall.

Fix: after `bl EXT(trap)`, test `SS_SRR1` for MSR_PR and branch to
`thread_exception_return` for user-mode traps, or end `trap()` with
`thread_exception_return()` when `USER_MODE(ssp->srr1)`.

### B4. Every interrupt that returns to user mode takes a full extra trap (Perf)
`hw_exception.s:1699-1735`: `.L_check_int_ast` is entered purely on
MSR[PR]; `need_ast` is never tested. Each such return re-saves the whole
`ppc_saved_state` through `thandler`, calls `trap()` and `check_for_ast()`,
and restores again. `PP_NEED_AST` is exported by `genassym.c:193` and
unused. `ast_on()` sets `need_ast[]` for every source, including signals
to the current process (`kern_sig.c:945`), so gating the detour on
`need_ast` is safe.

### B5. VIA cascade dispatch indexes past every 7-entry table (High)
`chips/grand_central.c:292-310`, `heathrow.c:344-362`, `ohare.c:367-385`,
`mpic.c:461-479`:
```c
irq = via_reg(PCI_VIA1_IFR); eieio();
irq &= via_reg(PCI_VIA1_IER); eieio();
...
bit = 31 - cntlzw(irq);
handler = &gc_via1_interrupts[bit];
```
On a 6522, IFR bit 7 is set whenever any enabled source is pending and IER
bit 7 always reads as 1, so `irq` has bit 7 set on every VIA interrupt and
the highest-bit-first loop dispatches index 7 first. All six family
tables are declared with 7 entries (`families/*.c`,
`N*_VIA1_INTERRUPTS 7`), so this reads the 16 bytes after the table: with
normal `.data` layout that is the next table's entry 0 (`PMAC_DEV_CARD4`
on Gossamer, Yosemite and PowerSurge). Once a PCI driver registers CARD4
it is called on every cuda/ADB interrupt with the wrong device id.

Fix: `irq &= 0x7f;` after the IER mask.

### B6. MPIC EOIs before the handler and has no vector bounds check (Medium; spurious vector fixed)
**Fixed on master (86f2501c):** the spurious vector is now 0xFF
(`mpic.c:205`) and dispatch stops on it (`:432`), so it no longer aliases
source 49 or indexes past PowerExpress's 38-entry table. The init sequence
now resets the controller (`:196-199`), which masks every source, IPI and
timer, and the old unmask-and-drain loop is gone.

**Still open:** `mpic.c:427-450` writes EOI at `:435`, before the handler,
then loops back to `INT_ACK` with EE off. `mpic_interrupts[irq]` at `:441`
is still indexed without `irq < nmpic_interrupts`; with every non-source
vector masked by the reset that is now defensive only.

The EOI order matters more now, because the 5.6 Sawtooth table
(`families/sawtooth.c:46-110`) programs sources 16-18 and 22-63
level-triggered. An OpenPIC re-presents a level source that is still
asserted as soon as it is EOI'd. Traced through DriverKit:

- `PPCKernBusInterruptDispatch` (`driverkit/ppc/PPCKernBus.m:49-62`) masks
  the line only when the bus interrupt reports it suspended.
- Only `KernDeviceInterruptDispatchShared` (`driverkit/KernDevice.m:444`)
  suspends it. The non-shared `KernDeviceInterruptDispatch` and the default
  handler `IOSendInterrupt` (`:511`) only queue a message.
- Every PCI device gets `"Share IRQ Levels" = "YES"` from
  `driverkit-3/libDriver/ppc/IOPCIDevice.m:100`, so gmac (UniNEnet), USB
  and the PCI slots are masked on dispatch. The first pass attributed this
  to an autoconf default; that was wrong.

So the exposure is a mac-io device on a level source that uses the
default handler. Today the mac-io level sources are SCC A/B, audio and
the VIA cascade: PPCSerialPort and the audio drivers install their own
handlers, and the cascade handler clears the VIA in place. A future
mac-io driver on the default handler would spin in this loop with EE off
on real hardware. This was not reproduced; QEMU mac99 boots.

Fix: mask level sources in their VPR before the EOI and let
`pmac_enable_irq` unmask them, or EOI after the handler; add the bounds
check.

### B7. Old World controllers never read the LEVELS register (Partly fixed; Medium, hardware-dependent)
**Fixed on master (2f4326b9) for Heathrow:** `heathrow_interrupt` now ORs
`LEVELS1 & MASK1 & HEATHROW_LEVEL1_SLOTS` into the pending set
(`heathrow.c:280-295`), and the `INTT_` typo in `heathrow.h:46-47` is
fixed. The mask 0x0000E01F is External Int 1-8 (physical bits 21-28)
through the n^0x18 byte-swap permutation, which checks out. A held PCI
slot interrupt is now dispatched on every pass instead of storming with
nothing dispatched.

**Still open:** Grand Central (`grand_central.c:264-265`) and O'Hare
(`ohare.c:309-310`, `:337-338`) still read only EVENTS. A level line that
stays asserted across the CLEAR produces no new edge. These chips are on
PowerSurge/PowerStar-class machines rather than the QEMU targets. Apple's
later drivers and Linux's `pmac_pic` also re-kick on unmask, which none of
the three do.

### B8. `interrupt()` recovery path leaves `current_priority` at SPLHIGH (Low)
`interrupt.c:271-275` longjmps out of the DSI recovery case before the
`current_priority = old_spl` at `:303`. Debug/KDP path only.

### B9. `machine_clock.c` guards hardclock state with the soft-clock level (Low, latent)
`machine_clock.c:245-273` uses `splusclock()`, which the pexpert maps to
SPLSCLK (5), below SPLCLOCK. It works only because of B1. Use
`splclock()`.

### B10. VIA IER initialisation is a no-op (Low)
`grand_central.c:146`, `heathrow.c:149`, `ohare.c:146`, `mpic.c:235` write
`0x00` to IER. On a 6522 a write with bit 7 clear *clears* the bits that
are set in the data, so `0x00` clears nothing. Write `0x7f` to disable,
`0x80 | bit` to enable.

## C. Platform expert: machine setup

### C1. Sawtooth OpenPIC and Fat Man addresses (Fixed)
**Fixed on master (eb4b43dd, 86f2501c).** The first pass found that
`get_int_cntlr_base_addr()` returned the mac-io-relative `reg` of the
`open-pic` node verbatim, putting every MPIC register in kernel RAM, and
that the Fat Man enable wrote physical 0x160 on anything but PowerExpress.

Now `identify_machine.c:296-297` adds the mac-io base on Sawtooth, and
writes the absolute address back into the device-tree property so
DriverKit sees the same value, as 5.6 does. It has one caller (`:193`), so
the in-place edit is applied once. `mpic_interrupt_initialize` touches
`FM_MPIC_CTRL` only under `IsPEx()` (`mpic.c:190`, `:228`), and the stray
`lwbrx(0xf2041080)` is gone. NVRAM got the same treatment
(`identify_machine.c:162-167`): an absolute `reg` past mac-io is used as is.

The fix keys on `IsSawtooth()` rather than on the address, so a future
New World family with a mac-io-relative `open-pic` needs the same line.

### C2. `RunCacheTests` clobbers DBAT3 and scribbles 1 MB at 0x01F0_0000 (Medium)
`backsideL2.c:171-187,229-233`: invalidates DBAT3, maps 0xE000_0000 onto
physical 0x01F0_0000, runs the pattern test, and leaves DBAT3 invalid.
It runs from `identify_machine2()` *after* `initialize_processors()` has
handed BAT1-3 to `PEMapSegment` (`powermac_init.c:126-131`). Triggered
whenever PVR is 750 and OF left L2CR = 0 (emulators, G3 upgrade cards).
The scratch address ignores `PhysicalDRAM[]`.

On Gossamer (QEMU g3beige) the family has no BAT routine of its own and
`initialize_bats` maps only 0xF000_0000 and the frame buffer, so DBAT3
is free and only the scratch-address part applies. Yosemite (also a 750)
and G3-upgraded Sawtooths can lose a mapped I/O segment.

### C3. Clock calibration (Partly fixed; Medium)
**Fixed on master (fa78ceaf, 036a053c) for Gossamer, Yosemite and
Sawtooth:** `DetermineClockSpeeds` now calls `derive_from_of()` first on
those families (`clock_speed.c:75`), and `derive_from_of` rejects a missing
or zero `clock-frequency` and a `bus-frequency` below 4 before dividing
(`:180-200`). It also fixes the old `4 * cpu_freq` overflow.

**Still open:**

- PowerSurge, PowerStar and PowerExpress, and any family whose OF lacks
  the properties, still run the VIA test. `clock_speed.c:114-123` divides
  by `dec_ticks`, `via_ticks` and `cpu_pll` unguarded. `divw` does not
  trap, so a stalled VIA T1 or decrementer gives garbage bus and
  decrementer rates and a wrong HZ. Up to 11 passes of 10 M cycles each
  run at boot with EE off.
- New: after `derive_from_of()` succeeds, `clock_speed.c:81` throws away
  the OF CPU clock and recomputes it as `bus_freq * cpu_pll / 2` in
  32-bit `long`s. The product wraps above about 1.07 GHz. Computed with
  the same arithmetic:

  | OF CPU | OF bus | reported `cpu_clock_rate_hz` |
  |-------:|-------:|-----------------------------:|
  | 266 MHz | 66 MHz | 264,000,000 |
  | 900 MHz | 100 MHz | 900,000,000 |
  | 1000 MHz | 133 MHz | 997,500,000 |
  | 1100 MHz | 100 MHz | -1,047,483,648 |

  No model in the current Core99 list (`keylargo_model.h`) runs that fast,
  so this is latent; `display_frequency` already prints GHz. Keep the OF
  value when `derive_from_of()` succeeded.

### C4. Smaller platform-expert defects (Low)
- `identify_machine.c:639`: `strncmp(cpu_model, "AAPL,", 5)` tests the
  still-empty global instead of `family`, so the prefix is never stripped;
  the `compatible` lookup at `:629` is unchecked.
- `identify_machine.c:971`: NVRAM partition walk does `curOffset += len*16`
  and never terminates on a zero-length header.
- `chips/mpic.h:46-48`: `MPIC_GLOBAL_CFG` is the one MPIC register
  accessed big-endian. It works because the constants are pre-swapped:
  `MPIC_CASCADE` 0x20 lands on GCR bit 29 and the new `MPIC_RESET` 0x80 on
  GCR bit 31, the reset bit. The reset poll at `mpic.c:198` is unbounded.
- `grand_central.c:169-172` and `heathrow.c:175-178`: a negative index
  fails the first test and passes the second, indexing before
  `*_via1_interrupts`. `ohare_int_to_number` checks `index < 0`.
- `get_dma_offset()` (`identify_machine.c:307`) returns the PCI config
  `phys.hi`, which equals the 0x8000 DBDMA offset only for device 0x10
  *(not independently re-traced)*.
- No G4 PVR (0x000C for the 7400, or the later 74xx values) is recognised
  in `backsideL2.c:112` or `powermac_init.c:203-223`, which stop at the
  750. QEMU mac99 presents a G4, so there the L2 is never reported and the
  CPU subtype is `CPU_SUBTYPE_POWERPC_ALL`.
- **Fixed (c14acd57):** the pexpert and kernel copies of `interrupts.h`
  now agree, including `PMAC_DEV_PDS` 282 and the UIDE, USB and
  CARD12-25 ids. Only the pexpert-internal `PMAC_DEV_MPIC_DIRECT_BASE`
  differs.

## D. VM and pmap

### D1. Hash table size capped by a typo (Fixed)
**Fixed on master (8e195a55):** `pmap.c:533` now reads `32*1024*1024`,
matching the clamp at `:602`. The first pass found
`while (hash_table_size < 32*1024*104 && ...)`. Computed result with the
typo versus the corrected loop:

| RAM | as written | intended |
|-----|-----------:|---------:|
| 512 MB | 4 MB | 4 MB |
| 768 MB | 4 MB | 8 MB |
| 1 GB | 4 MB | 8 MB |
| 1.5 GB | 4 MB | 16 MB |

An undersized table means more PTEG overflows, each of which evicts a
live user mapping (`pteg_pte_exchange`, `pmap.c:2398`) and costs a
later fault. `vm/ppc-guest.py` boots QEMU guests with 512 MB, where both
loops give 4 MB, so the QEMU targets do not see a difference.

### D2. Two full TLB invalidate sequences per new mapping (Perf)
`pmap_enter` on the new-mapping path does `sync; tlbie; eieio; tlbsync;
sync` at `pmap.c:1417-1421`, then `pmap_enter_mapping` repeats it at
`:2156-2160`. The PTE was just allocated invalid and every removal path
(`pmap_free_mapping`, `pteg_pte_exchange`) already invalidates, so both
are redundant on the page-fault path.

### D3. `pmap_copy_page` serialises per cache line (Perf, high impact)
`movc.s:216-291`: for each of the 128 lines it does `dcbz`, 8 loads, 8
stores, then `dcbst; sync; icbi; sync; isync` (`:240-246` and
`:281-287`). That is 256 `sync` and 128 `isync` per copied page, each
`sync` waiting for the just-pushed line to reach DRAM. `cache.s` already
shows the right shape: copy the page, one `dcbst` loop, `sync`, one
`icbi` loop, `sync`, `isync`. Same semantics, a fraction of the cost.
`pmap_zero_page` (`:97-127`) is fine.

### D4. Spin-lock acquire pays two `sync` barriers (Perf)
`misc_asm.s:153-165` (`test_and_set`, used by `simple_lock` on
`mach/ppc/simple_lock.h`):
```
Ltasl:	sync
	lwarx	r5, 0, r4
	...
	sync
	stwcx.	r5, 0, r4
	bne-	Ltasl
	isync
```
`kern/lock.h:66` turns real simple locks on whenever DRIVERKIT is
configured, which the ppc RELEASE config does, so these run on the
uniprocessor kernel for every vm_object, page-queue, ipc and zone lock.
Acquire needs only `lwarx/stwcx./isync`; release already has `sync` in
`simple_unlock`. The `hw_exception.s` comment "bug fix for 3.2
processors" near its own `sync; stwcx.` suggests an erratum motivated one
of these; check that before removing the one inside the reservation.

### D5. `isync; mtsr; isync` on every exception return (Perf, low)
`hw_exception.s:391-394, 1243-1246, 1664-1667, 2026-2030`. `mtsr` needs a
context-synchronising instruction after it (the `rfi` is one) and nothing
before it. Two pipeline flushes per return can go.

### D6. `pmap_enter` touches the hash table before `splhigh()` (Low)
`pmap.c:1270` calls `find_or_allocate_pte(..., TRUE)`, which writes
`pte0`/`pte1` and may evict through `pmap_pteg_overflow`, before the
`splhigh()` at `:1278`. The first pass cited the wrong lines here. Safe only while nothing at interrupt level calls
`pmap_enter`.

### D7. Per-page kernel mapping for every vnode pager I/O (Perf, design)
`vm/vnode_pager.c:693-708`: on ppc each page read or written through the
vnode pager costs `vm_map_find` + `pmap_enter_phys_page` (two tlbie
sequences), `vm_map_remove` (one more), and `flush_cache(page)`
(`:791`). i386 returns the physical address directly. BAT0 is shrunk to
`virtual_avail` at `vm/vm_init.c:71`, so there is no direct window; a
permanent BAT window over RAM would remove all of this but changes the
kernel VA layout.

### D8. Smaller VM items (Low)
- `pmap_clear_reference` (`pmap.c:1989-2045`) issues a full tlbie sequence
  per mapping, including the kernel's phys-window mapping, on every
  pageout scan.
- `pmap_bootstrap` sizes the mapping table at one 20-byte `struct
  mapping` per PTE slot: 10 MB wired for a 4 MB hash table.
- `pmap_bootstrap` only adds region 0's tail to `free_regions`; the
  booter (`boot-2/ppc/SecondaryLoader/SecondaryInC.c:1724`) only ever
  passes one bank, so this is latent.
- `pmap_add_physical_memory` leaves R/C bits of the kalloc'd phys entries
  uninitialised.
- `lowmem_vectors.s:3334-3420`: every DSI/ISI spills ten registers, calls
  the `LookupPTE` stub at `:3884` that always fails, and reloads them
  before reaching the normal entry.
- `machdep/ppc/mem.c` is a stale copy of `htab.c`; `conf/files.ppc`
  compiles `htab.c`. Fixes go in `htab.c`.

## E. Traps, signals, FPU and alignment (correctness)

### E1. Alternate signal stack frame is placed below the stack (Medium)
`unix_signal.c:90`: `sp = ss_sp` then subtracts the frame. `sigaltstack`
(`bsd/kern/kern_sig.c:543-575`) stores `ss_sp` as the base and `ss_size`
as the length. Use `ss_sp + ss_size`; `osigstack` sets `ss_size = 0`
with `ss_sp` as the top, so that stays correct.

### E2. sigreturn restores float state the FPU still owns (Medium)
`unix_signal.c:206-208` copies into `pcb->fs` without releasing FPU
ownership. `fpu_switch` (`fpu.s:349-356`) returns early when the current
pcb already owns the FPU, so the restored state is discarded and a later
`fpu_save` overwrites it with stale hardware values. `set_thread_fpstate`
(`pcb.c:475-476`) does `fpu_save(); fpu_disable();` first.

### E3. Kernel-side fault recovery only honoured in DEBUG builds (Medium)
`trap.c:221-233`: for a kernel DSI whose DAR is not in the copy segment,
`th->recover` is checked only under `#if DEBUG`; release kernels panic.
That defeats `safe_bzero`, `copywithin`, `copystr` and the KDP wrappers.
Separately `fault_copy.c:423-424` and `:457-458` compute
`SEGOFFSET(p) + len > NBSEG`, which wraps for `len > 0xF000_0000` and lets
`bcopy` run out of segment 14.

### E4. FP exception reports the wrong FPSCR (Low)
`trap.c:383-389`: `fpu_save()` stores 0 into `PP_FPU_PCB`
(`fpu.s:141-142`), then `per_proc_info[..].fpu_pcb->fs.fpscr` is read
through NULL. BAT0 covers page 0 so it reads the vector page rather than
faulting; the subcode is garbage. Use `th->pcb->fs.fpscr`.

### E5. Alignment emulator defects (Medium/Low)
- `alignment.c:184-187`: `GET_REG/SET_REG(..., unsigned short)` take the
  *high* halfword of the 32-bit slot on big-endian, so sth/sthu/sthx/
  sthux/sthbrx store the wrong half and lhzu/lhzx/lhbrx leave the low
  half untouched. Reachable only in LE mode.
- `alignment.c:326`: `_AFENTRY(lfdux, 0, 8)` marks a *load* as an 8-byte
  store, so an unaligned `lfdux` (which does trap) loads garbage and
  writes 8 uninitialised bytes back to user memory. Siblings at `:219`,
  `:235`, `:310` are `(8, 0)`. `lhzux`/`lhaux`/`sthux` at `:321-323`
  declare 4 bytes instead of 2.
- `alignment.c:815-816,837`: `lwbrx`/`lhbrx` inline asm lists the result
  only as an input, so the written register is uninitialised.
- `alignment.c:217,249-250`: lmw/lswi always read 128/32 bytes from
  `dar` regardless of rT *(not independently re-traced)*.

### E6. Other trap-path items (Low)
- `trap.c:642`: missing comma in `trap_type[]` shifts the names for
  0x2100-0x2F00 and makes `trap_type[47]` an out-of-bounds read.
- `systemcalls.c:123,173`: `uasfp` is an `int`, so `uasfp++` steps 1 byte
  for stack-passed mach trap arguments; latent (only `mach_msg_overwrite_trap`
  has 9 args and reads one word).
- `ast_ppc.c:105`: `p->p_stats` dereferenced without the `p` guard used
  above it *(not independently re-traced)*.
- `lowmem_vectors.s:755-761` and `hw_exception.s:577-581`: the Blue Box
  fast trap reads the word after the trap instruction with translation on
  but no recovery point; a page boundary there panics.
- `lowmem_vectors.s:876` and `hw_exception.s:615`: `rlwimi r6,r6,0,...`
  is another self-insert no-op, so SE/BE are not cleared on PseudoKernel
  entry.
- `mcount.s:44-53`: PROFILE builds only; the stub does not save r3-r10.
- Kernel stack frames handed to C are 4 mod 16 aligned
  (`KERNEL_STACK_SIZE 16372`, `FM_SIZE 72`, `KF_SIZE 312`) *(arithmetic
  not independently re-traced)*.
- `setjmp.s:106-129`: FP save offsets are wrong; dead under the undefined
  `FLOATING_POINT_SUPPORT`.
- `hw_exception.s:1371-1377`: the syscall-mark test compares the whole
  upper MSR half instead of one bit.

## F. Driver support and console

- `driverkit/ppc/autoconf_ppc.m:968`: `FindStringKey` does an unbounded
  `strncpy` into 128-byte `IOMalloc` buffers (`:783-791`, `:855-860`) from
  bundle config tables at boot. The new Floppy check at `:822-824` reads
  `"Driver Name"` through it into the same buffer. (Medium-Low)
- `kdp_machdep.c:127-133`: `hdr.len` counts `exc_info` twice, so 16 bytes
  of kernel stack go into the packet. The i386 version sets
  `hdr.len = sizeof(*rq)` first. (Low)
- `serial_io.c:668-696`: `scc_putc` spins at spltty for TX_EMPTY *after*
  writing, about one character time per byte; `scc_delay(100)` is a
  million volatile iterations independent of CPU speed. (Perf)
- `dbdma.c:70-101`: only `eieio` separates cacheable descriptor stores
  from the control-register kick; `sync` is what the architecture asks
  for. All status polls are unbounded. (Low, hardware-dependent)
- `DeviceTree.c:113-125`, `swapgeneric.m:366-404`, `machdep.c:158-195`:
  unbounded copies into fixed stack buffers; callers are literal paths,
  the console and NVRAM today. (Low)
- `autoconf_ppc.m:440-650`: `StartDriver` leaks `nameBuf` and the class
  list on abort *(not independently re-traced)*. (Low)
- `driverkit/ppc/PPCKernBus.m:80-84`: `-dealloc` never unregisters the
  IRQ *(not independently re-traced)*. (Low)
- `unix_startup.c:66`: `int nmfsbuf = NMFSBUF` has no semicolon; dead
  until someone defines `NMFSBUF`. (Low)
- `machine_clock.c:78`: `read_processor_clock_tval()` (two 64-bit
  divides) runs every tick even with no timer armed. (Perf, negligible)

## H. Code that is new since the first pass

### H1. `pmap_set_cache_spec` ignores the BAT0 alias (Low, hardware-dependent)
`pmap.c:2707-2746` is new: it switches one wired, exclusively mapped
kernel page between cached and cache-inhibited, and the PPCScreamer driver
uses it for its two DMA ring pages (`PPCScreamer.m:258-263`, restored at
`:297-298` before `kmem_free`). The sequence is right: it drains and
invalidates the page before flipping WIMG (`:2730`), runs the full
invalidate-tlbie-revalidate sequence, and records the new default in the
`phys_entry` (`:2738`) so a later mapping of that page agrees.

The exclusivity check at `:2720-2723` counts PTE mappings only. BAT0 maps
physical memory V=R and cached from 0 up to a power of two:
`initialize_bats` sets it up cached (`bat_init.c:152-158`) and
`vm/vm_init.c:71` rounds its limit up past `virtual_avail`. Free VM pages
start at the old `virtual_avail` (`vm/vm_mem_region.c:134-137`), so the
pages between there and the rounded limit are in the free pool and also
mapped cached through BAT0. A ring page taken from that range gets a
cache-inhibited PTE and keeps a cached BAT alias; the PowerPC architecture
treats mixed WIMG for one physical page as a programming error. Nothing
dereferences the alias deliberately, so the exposure is speculative
accesses through it.

Fix: refuse a page whose physical address is below the BAT0 limit, or
allocate the ring pages from above it.

### Reviewed and sound
- **Heathrow level sampling** (`heathrow.c:280-295`): the 0x0000E01F mask
  is External Int 1-8 through the byte-swap permutation; see B7.
- **MPIC reset path** (`mpic.c:190-231`): reset, mask every source,
  spurious vector 0xFF, cascade enable, task priority 0, then load the
  table; Fat Man only on PowerExpress. The reset poll is unbounded (C4).
- **`DTFindChildEntry` / `DTIterateChildren`** (`DeviceTree.c:433-446`):
  no allocation, so both are usable before `kalloc_init`. The iterator is
  bounded by `nChildren` and steps siblings with `skipTree`, which skips
  each child's subtree. `DTFindChildEntry` shares `DTFindEntry`'s static
  `startingP` (`:417`), so neither is reentrant; both run at boot only.
- **DAVbus and KeyLargo audio binding** (`chips/davbus_audio.c`,
  `chips/keylargo.c:271-413`): `ranges` and `reg` are validated with
  overflow-safe bounds against mac-io, interrupt specifiers are limited to
  three distinct sources below 64, the binding runs allocation-free from
  `configure_machine`, and FCR1 access uses `stwbrx`/`lwbrx` with
  `eieio; sync`.
- **Sawtooth `PEEditDTEntry`** (`identify_machine.c:745-763`): supplies the
  three DAVbus MPIC sources as `AAPL,interrupts` for the one DAVbus node it
  first sees, and refuses any other.
- **OF clock path** (`clock_speed.c:180-231`): the divide-by-zero and the
  old `4 * cpu_freq` overflow are both guarded; see C3 for what is left.
- **`*_register_int` no longer panics** on an unknown device id
  (97dc15f7). A driver whose interrupt is not in the family table now
  attaches without interrupts and logs one line. That is a deliberate
  behaviour change.

## G. Verified as sound

- `htab.c`: SDR1 mask and secondary-hash arithmetic for 64 KB to 32 MB
  tables; `PTE_EMPTY` initialisation is one-time.
- `cache.s`: barrier order (`dcbst` loop, `sync`, `icbi` loop, `sync`,
  `isync`) and the unaligned start/end arithmetic, checked by hand; the
  double `dcbi` is a documented erratum workaround; DR-off with EE-on is
  safe because exception exit restores SRR1 unchanged.
- 603 software TLB-miss handlers (`lowmem_vectors.s:229-520`): PTEG scan,
  secondary hash, R/C update, `tlbli/tlbld` order and the store-miss
  protection check; the 0x1200 handler fits its slot.
- Exception entry/exit register discipline, `PCB_KSP` busy/free protocol,
  the physical-mode exit trampoline, and interrupt-stack nesting.
- Lazy FPU on UP: `fpu_save` clears the previous owner's MSR[FP];
  `pcb_terminate`, `thread_dup`, `set_thread_fpstate` and `sendsig` flush
  first; `bcopy.s` brackets its FP use.
- copyin/copyout/copystr: every user address goes through `cioseg()`,
  which installs the current task's VSID, so user pointers cannot reach
  kernel mappings; `recover` is restored on every exit; length accounting
  in `copyinstr` is right.
- Syscall dispatch bounds for mach traps, `sysent[63]` fallback, cerror
  and ERESTART PC adjustment.
- `rtclock.c`: torn-safe timebase read, phase-preserving decrementer
  reload, 8.24 fixed-point conversion.
- BAT setup: 256 MB cached BAT0 for RAM, `PTE_WIMG_IO` BATs with Vp=0 for
  I/O segments, correct upper-invalidate/lower/upper sequence.
- Old World byte-swap permutation, VIA cascade bit, MPIC register offsets
  and VPR encodings; family tables match their `N*_INTERRUPTS` counts.
- L2 invalidate/enable sequence in `backsideL2.c`; KeyLargo I2C polling
  is bounded and range-checked.
- SCC register access ordering (`eieio` after every access), channel
  offsets and reset values.
- `mtmsr` without `isync` for EE-only changes.

## Method

Two passes over the hot paths (pmap, hash table, cache ops, spl, clock,
BAT setup, page copy) by hand, plus four parallel reviews of the
assembly, the platform expert, the trap/copy/FPU code and the machdep C
support, each of whose findings was re-read at the cited lines before
inclusion. The hash-table sizing table was produced by compiling the
sizing loop from `pmap_bootstrap` on the host with both constants.

The second pass diffed every file the audit cites, plus the new
platform-expert, device-tree, pmap and autoconf code, between 267d9fbc
and master at 8e195a55, then re-read each finding at master's lines. The
C3 clock table was produced by compiling `DetermineClockSpeeds`'
arithmetic with 32-bit `long`s. The B6 DriverKit path was traced through
`PPCKernBus.m`, `KernBusInterrupt.m`, `KernDevice.m` and
`IOPCIDevice.m`. Nothing was booted for this pass.
