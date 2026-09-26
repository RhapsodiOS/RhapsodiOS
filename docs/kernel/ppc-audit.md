# PowerPC kernel and platform expert audit

Scope: `src/kernel-7/machdep/ppc`, `src/kernel-7/driverkit/ppc`,
`src/kernel-7/kernserv/ppc`, `src/kernel-7/mach/ppc`, the ppc paths in
`kern/`, `vm/` and `bsd/dev/ev.c` that the machdep code calls, and every
file under `src/drivers-ppc/bus/drvPExpert/powermac`. Read-only review;
nothing here has been changed yet. Every finding below was checked against
the cited lines. Items that came from a second reviewer and were not
re-traced end-to-end are marked *(not independently re-traced)*.

The kernel is the MkLinux DR2 lineage: single processor, no kernel
preemption, kernel in segments 0-3 (0x0000_0000-0x3FFF_FFFF) with segment
registers 0-3 swapped to kernel VSIDs on every exception entry, user
segments 4-15 loaded at task switch, and copyin/copyout through a borrowed
segment register 14.

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
| 8 | `identify_machine.c:279-283`, `mpic.c:189-196` | OpenPIC base not offset by mac-io base; Fat Man register accessed at physical 0x160 | On Sawtooth-class trees the MPIC registers land in kernel RAM |
| 9 | `movc.s:240-246,281-287` | `pmap_copy_page` does `dcbst; sync; icbi; sync; isync` per 32-byte line | 256 syncs per page copy on the copy-on-write and fork path |
| 10 | `pmap.c:533` | `32*1024*104` caps the hash table at 4 MB | 768 MB and 1 GB machines get half the architected table size |

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
(`heathrow.c:241-244` is an empty function; the assignment at `:133` is
commented out). So splbio, splimp, splnet, spltty and splsoftclock all
mask the decrementer and every device for the length of the critical
section. `rtclock_intr` (`rtclock.c:116-129`) catches up on missed ticks,
so time is not lost, but scheduling, timeouts, ADB, serial and network
latency are bounded by the longest spl>0 section in the BSD layer.

Not a quick fix. The MPIC current-task-priority path exists but is under
`#if 0` (`mpic.c:401-426`). A cheaper intermediate step is to keep the
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
`chips/grand_central.c:292-310`, `heathrow.c:336-357`, `ohare.c:367-388`,
`mpic.c:514-535`:
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

### B6. MPIC dispatch has no vector bounds check and EOIs before the handler (Medium)
`chips/mpic.c:482-503`: the acked vector indexes `mpic_interrupts[irq]`
and `MPIC_INT_CFG + irq*0x20` unchecked. The spurious vector is 0x31
(`:236`), which is outside PowerExpress's 38-entry table and aliases
source 49 on Sawtooth. EOI is written before the handler runs and the
`while (1)` re-ack loop runs with EE off; a non-shared level source whose
handler only queues work (the DriverKit default) would be re-presented
immediately and livelock. The autoconf default `Share IRQ Levels = YES`
is what hides this today *(livelock path not independently re-traced)*.

Fix: `if (irq == MPIC_SPURIOUS_VECTOR || irq >= nmpic_interrupts) break;`
before touching CFG/EOI; program the spurious vector to an unused value;
mask level sources before EOI.

### B7. Old World controllers never read the LEVELS register (Medium, hardware-dependent)
`heathrow.c:286-292`, `grand_central.c:264-265`, `ohare.c:309-310` read
EVENTS, write CLEAR and dispatch. A level line that stays asserted across
the CLEAR produces no new edge. Apple's later Heathrow driver and Linux's
`pmac_pic` both OR in `LEVELS & MASK` and re-kick on unmask. The macros
can't even compile: `heathrow.h:46-47` spell the constants
`HEATHROW_INTT_LEVELS*` while `:70-71` reference `HEATHROW_INT_LEVELS*`.

### B8. `interrupt()` recovery path leaves `current_priority` at SPLHIGH (Low)
`interrupt.c:271-275` longjmps out of the DSI recovery case before the
`current_priority = old_spl` at `:303`. Debug/KDP path only.

### B9. `machine_clock.c` guards hardclock state with the soft-clock level (Low, latent)
`machine_clock.c:245-273` uses `splusclock()`, which the pexpert maps to
SPLSCLK (5), below SPLCLOCK. It works only because of B1. Use
`splclock()`.

### B10. VIA IER initialisation is a no-op (Low)
`grand_central.c:146`, `heathrow.c:149`, `ohare.c:146`, `mpic.c:288` write
`0x00` to IER. On a 6522 a write with bit 7 clear *clears* the bits that
are set in the data, so `0x00` clears nothing. Write `0x7f` to disable,
`0x80 | bit` to enable.

## C. Platform expert: machine setup

### C1. Sawtooth OpenPIC and Fat Man addresses (High for New World)
`identify_machine.c:279-283` returns `reg[0]` of the `open-pic` node
verbatim. The other offsets at `:183-186` are added to `io_base_phys`;
this one is not. On Apple OF 3.x and OpenBIOS `mac99` trees the node is
`mac-io/interrupt-controller@40000` with a mac-io-relative `reg`, so
`int_cntlr_base_phys = 0x40000` and every MPIC register macro
(`mpic.h:46-56`) resolves into kernel RAM. `mpic_interrupt_initialize`
(`mpic.c:189-196`) also does two read-modify-writes through
`FM_MPIC_CTRL`, which is `mem_cntlr_base_phys + 0x160`; that base is 0 on
anything that is not `hammerhead`/`fatman` (`identify_machine.c:251-266`),
so the writes hit physical 0x160, inside the system-reset vector. The
hard-coded `lwbrx(0xf2041080)` is PowerExpress-only.

Fix: add `io_base_phys` when `reg[0] < io_size`; guard the Fat Man
accesses with `mem_cntlr_base_phys != 0`.

### C2. `RunCacheTests` clobbers DBAT3 and scribbles 1 MB at 0x01F0_0000 (Medium)
`backsideL2.c:171-187,229-233`: invalidates DBAT3, maps 0xE000_0000 onto
physical 0x01F0_0000, runs the pattern test, and leaves DBAT3 invalid.
It runs from `identify_machine2()` *after* `initialize_processors()` has
handed BAT1-3 to `PEMapSegment` (`powermac_init.c:126-131`). Triggered
whenever PVR is 750 and OF left L2CR = 0 (emulators, G3 upgrade cards).
The scratch address ignores `PhysicalDRAM[]`.

### C3. Clock calibration divides by measured counts with no guard (Medium)
`clock_speed.c:115-124`: `cpu_pll = 10000000 / dec_ticks`, then
`raw_cpu_freq / (via_ticks * ...)` and `raw_cpu_freq * 2 / cpu_pll`.
`divw` does not trap, so a stalled VIA T1 or decrementer yields garbage
bus and decrementer rates and a wrong HZ. The OF-derived path exists but
is disabled by `if (0 && IsYosemite())` at `:73`. Up to 11 passes of
10 M cycles each run at boot with EE off.

### C4. Smaller platform-expert defects (Low)
- `identify_machine.c:606`: `strncmp(cpu_model, "AAPL,", 5)` tests the
  still-empty global instead of `family`, so the prefix is never stripped;
  the `compatible` lookup at `:606` is unchecked.
- `identify_machine.c:937`: NVRAM partition walk does `curOffset += len*16`
  and never terminates on a zero-length header.
- `chips/mpic.h:46`, `mpic.c:199`: `MPIC_GLOBAL_CFG` is the one MPIC
  register accessed big-endian; it works because two mistakes cancel
  *(not independently re-traced)*.
- `gc_int_to_number`/`heathrow_int_to_number` accept negative indices
  *(not independently re-traced)*.
- `get_dma_offset()` returns the PCI config `phys.hi`, which equals the
  0x8000 DBDMA offset only for device 0x10 *(not independently re-traced)*.
- The pexpert and kernel copies of `interrupts.h` disagree
  (`PMAC_DEV_PDS` 270 vs 280; kernel-only USB/UIDE/CARD12-17 ids)
  *(not independently re-traced)*.
- PVR 0x000C (7400) is not recognised in `backsideL2.c:112` or
  `powermac_init.c:203-223`.

## D. VM and pmap

### D1. Hash table size capped by a typo (Medium)
`pmap.c:533`: `while (hash_table_size < 32*1024*104 && ...)`. The intent
is `32*1024*1024`; the clamp at `:602` uses the right constant. Computed
result with the typo versus the intended loop:

| RAM | as written | intended |
|-----|-----------:|---------:|
| 512 MB | 4 MB | 4 MB |
| 768 MB | 4 MB | 8 MB |
| 1 GB | 4 MB | 8 MB |
| 1.5 GB | 4 MB | 16 MB |

An undersized table means more PTEG overflows, each of which evicts a
live user mapping (`pteg_pte_exchange`, `pmap.c:2398`) and costs a
later fault.

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
`pmap.c:1280` calls `find_or_allocate_pte(..., TRUE)`, which writes
`pte0`/`pte1` and may evict through `pmap_pteg_overflow`, before the
`splhigh()` at `:1293`. Safe only while nothing at interrupt level calls
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

- `driverkit/ppc/autoconf_ppc.m:912`: `FindStringKey` does an unbounded
  `strncpy` into 128-byte `IOMalloc` buffers (`:740-743`, `:802-804`) from
  bundle config tables at boot. (Medium-Low)
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
- `autoconf_ppc.m:409-616`: `StartDriver` leaks `nameBuf` and the class
  list on abort *(not independently re-traced)*. (Low)
- `driverkit/ppc/PPCKernBus.m:80-84`: `-dealloc` never unregisters the
  IRQ *(not independently re-traced)*. (Low)
- `unix_startup.c:66`: `int nmfsbuf = NMFSBUF` has no semicolon; dead
  until someone defines `NMFSBUF`. (Low)
- `machine_clock.c:78`: `read_processor_clock_tval()` (two 64-bit
  divides) runs every tick even with no timer armed. (Perf, negligible)

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
