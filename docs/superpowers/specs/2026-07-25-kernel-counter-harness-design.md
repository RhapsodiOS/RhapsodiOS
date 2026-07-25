# Kernel Counter Harness and Verifiable Optimizations

Date: 2026-07-25
Status: design approved
Scope: `src/kernel-7`, plus one new tool under `src/Commands`

## Problem

A survey of `src/kernel-7` turned up several concrete optimization and stability
opportunities. None of them can be honestly justified today, because the kernel
has no way to report what its hot paths are doing. `tlb_stat`
(`machdep/i386/pmap_private.h:294`) counts full versus single TLB flushes and
nothing ever reads it. The `MACH_COUNTERS` facility (`kern/counters.h`) has
broken config plumbing. `cpu_sysctl` (`machdep/i386/i386_init.c:690`) is an
empty stub.

The reference environment is QEMU with a software-emulated CPU (TCG), per
`vm/README.md`. Under TCG the paging cost model is fictional: QEMU flushes its
own software TLB, so a full CR3 reload is cheaper relative to real hardware than
it should be, and wall-clock timing drifts with host load and translation-block
caching. Elapsed time is therefore not a usable metric here.

This design builds a counter harness first, then lands only the optimizations
that a counter can confirm or refute.

## Non-goals

Named explicitly so they do not leak into implementation:

- `CR4.PGE` (global bit on kernel mappings) and `PSE` 4 MB pages. Substantial
  paging changes with real crash risk, they need the harness to exist first, and
  TCG cannot confirm their payoff. Separate spec.
- `memcpy` / `memset` rewrites in `machdep/i386/libc`. They are `rep movsl`
  tuned for the 486 and align on source rather than destination, but confidence
  in a payoff across the actual targets is low and the rewrite is easy to get
  wrong.
- The `MACH_COUNTERS` config mismatch: `conf/MASTER:121` gates it on the
  `<count>` tag while `conf/files:42` expects an option named `mach_counters`,
  which nothing declares. A real latent bug, fixed separately.
- A full ppc `cpu_sysctl` implementation beyond the stub W1 adds.
- Scheduler and IPC work.

## Architecture

### Readout seam: `CTL_MACHDEP`

`bsd/sys/sysctl.h` is an exported header. Adding a `KERN_*` id would mean
bumping `KERN_MAXID`, extending `CTL_KERN_NAMES`, and shipping a header that
installed binaries were not compiled against — a real hazard on a system with
prebuilt userland.

`CTL_MACHDEP` requires no change to `sysctl.h` at all: the node exists, it is
already routed to `cpu_sysctl` at `bsd/kern/kern_sysctl.c:205`, and sub-names can
be defined in a private kernel header. The cost is that machine-independent
counters live under a `machdep` node. That is cosmetically wrong and functionally
irrelevant; it is the accepted trade.

`cpu_sysctl` is defined only for i386, with no ppc definition anywhere in the
tree despite the `extern` at `bsd/kern/kern_sysctl.c:101`. W1 adds a ppc stub so
`CTL_MACHDEP` behaves identically on both arches.

### Components

1. **`kern/kcounters.{h,c}`** — a flat struct of named `unsigned long`
   counters, compiled unconditionally rather than behind `MACH_COUNTERS`;
   release-build numbers are the point, and an unconditional increment is free
   relative to the work already done at these sites. Exports
   `kcounters_format(buf, len)`, rendering `name value\n` lines, and
   `kcounters_reset()`.

2. **`cpu_sysctl` handler** — one read node returning the formatted text, one
   write node triggering reset. Text rather than a struct, so the reader needs
   no shared layout and adding a counter never breaks it.

3. **`kcstat`** — a small guest tool under `src/Commands` that reads the node
   and prints it.

`kcounters_format` writing into a caller-supplied buffer is what would let a
console dump reuse it later without a second implementation. One function, not a
speculative layer.

## Instrumentation

Every counter maps to exactly one work item. Nothing is collected in case it
proves useful later.

### TLB (i386 only)

ppc already invalidates per-VA with `tlbie` and has no full-flush heuristic, so
this group and W5 are i386-only. Replaces the write-only `tlb_stat`:

| Counter | Purpose |
|---|---|
| `tlb_flush_full` | full-flush path taken |
| `tlb_flush_single` | `invlpg` path taken |
| `tlb_invlpg_pages` | pages invalidated via `invlpg` |
| `tlb_full_pages` | sum of range sizes, in pages, that took the full-flush path |

`tlb_full_pages` decides W5. If the baseline shows `tlb_flush_full` dominated by
small ranges, raising the threshold converts them; if it is dominated by large
ranges, the threshold buys nothing and W5 is dropped. The counter is permitted
to veto its own work item.

### kalloc

| Counter | Purpose |
|---|---|
| `kalloc_zone_hits[NKSIZE]` | per-zone-index allocation histogram |
| `kalloc_calls`, `kfree_calls` | totals |
| `kalloc_oversize` | fell through to `kmem_alloc_wired` |
| `kalloc_oversize_page` | of those, `size <= PAGE_SIZE` |

The histogram is an array rather than a scalar loop-step counter deliberately.
Scan cost for index *i* is *i+1* iterations, so total scan cost is derivable
from it, and unlike a step counter it stays meaningful after the loop is gone —
showing which zones carry traffic and whether the size table is well chosen.

### Zone

| Counter | Purpose |
|---|---|
| `zone_expansions` | zone grew past `max_size` via the `expandable` path |
| `zone_space_failures` | `zget_space` returned 0 — today's panic trigger |
| `zone_reclaims`, `zone_reclaim_pages` | in-kernel reclaim runs, pages returned |
| `zone_expand_races` | two allocators inside the non-pageable expansion window at once |

`zone_expand_races` establishes whether the `kern/zalloc.c:1543-1547` race is real
rather than theoretical, via a global in-flight depth around the unlocked
`zget_space` call, counted when it exceeds 1. If the baseline never trips it, W7
is dropped and the finding becomes a comment.

## Measurement protocol

### Quiescing

Measurements run in **single-user mode**. Clock ticks, `netinfod`, `inetd`, and
the network stack all allocate independently of the workload; single-user mode
is the largest available lever on variance. It also means no SSH during a run,
so `kcstat` output goes to a file and is collected afterward from multi-user
mode.

Accepted trade: the measured profile never exercises the network stack or daemon
allocation, so it is narrower than a real running system's. Attribution of
changes is worth more here than breadth of profile.

### Two classes of criteria

**Exact.** `kalloc_zone_hits[]` must be *identical* before and after W3 — not
close. Divergence means the lookup table is not a faithful rewrite of the scan,
which is a correctness bug rather than a measurement artifact. Likewise
`kalloc_oversize` must fall by exactly `kalloc_oversize_page` under W4.

**Statistical.** Flush and expansion counts: three runs, report the median,
require the before/after gap to exceed observed run-to-run spread. If it does
not, the change had no measurable effect and the spec records that rather than
claiming a win.

### Workloads

Two fixed workloads, committed so they are re-runnable:

- **`vfs-alloc`** — extract a fixed tarball, `find`, `wc -l` every file,
  `rm -rf`. Drives `kalloc`, zone, and VFS traffic. Also computes checksums of
  the extracted tree and compares against a committed manifest; see W5.
- **`fork-cow`** — a fixed fork/exec loop plus a small mmap write-fault
  exerciser. Drives `pmap_protect` and `pmap_remove` ranges. Needs to exist as a
  small C program.

A kernel compile is deliberately not used: most realistic, least repeatable,
since output caching changes the work between runs.

### Procedure

`kcstat -z` (reset), run workload, `kcstat > result` (dump). Reset-then-read
rather than diffing two snapshots — no arithmetic in the tool.

### Ordering constraint

The harness lands, and a baseline is captured and committed, **before any
optimization commit**. A baseline taken from a tree that already contains a
change is not a baseline.

### Zone exhaustion procedure

`zone_space_failures` will not move under normal load, so W6 needs forced
exhaustion. Rather than build a test hook: a throwaway kernel with
`zone_map_size_min` and `zone_map_size_max` both pinned to 1 MB
(`kern/zalloc.c:156-157`), which any real workload exhausts within seconds. Two
lines, not committed, documented as a manual procedure.

The current kernel is expected to `panic("zalloc")` there. Reproducing that
panic is the baseline for W6 and is what validates the test.

### Results

Counter dumps are appended per work item to `docs/kernel/perf-baseline.md` and
committed — durable before/after evidence rather than terminal scrollback.

## Work items

Ordered so that risk arrives after diagnosability.

### W1 — Counter harness (mandatory, no behavior change)

`kern/kcounters.{h,c}`; `cpu_sysctl` read and reset nodes; ppc `cpu_sysctl`
stub; `kcstat`; both workload scripts and the `vfs-alloc` checksum manifest.
Baseline captured in single-user mode and committed.

**Verify:** boots on both arches; both workloads complete; counters non-zero and
plausible.

### W2 — Frame pointers in release builds

Release builds are bare `-O3` (`conf/MASTER.i386:82`, `conf/MASTER.ppc:82`);
only the `<gdb>` variant passes `-fno-omit-frame-pointer`. Panic backtraces from
a shipping kernel are therefore unreliable. Add the flag to both `<!gdb>` lines.

**Verify:** statically — disassemble several functions in the release
`mach_kernel` and confirm frame-pointer prologues. A check on the binary, not an
attempt to crash the machine.

Sequenced early because W5 and W6 are the items most likely to panic, and this
is what makes those panics readable.

### W3 — `kalloc` size-to-index lookup table

`kalloc`, `kalloc_noblock`, `kget`, `kfree`, and `kalloc_zone` each linear-scan
`k_zone_elemsize[16]` on every call — up to 12 iterations per allocation and per
free.

Every entry in `k_zone_elemsize` is a multiple of 16, so a table indexed by
`(size + 15) >> 4` is exact, not approximate: 193 entries covering 16 through
3072, built once in `kalloc_init`. A single `kalloc_zindex()` inline replaces the
scan in all five entry points. Collapsing that fivefold duplication is cleanup
the change itself forces, not gratuitous refactoring.

**Verify:** `kalloc_zone_hits[]` byte-identical to baseline on both workloads.

### W4 — Page-sized zone (gated on baseline `kalloc_oversize_page`)

`kalloc_init` breaks out when `size >= PAGE_SIZE` (`kern/kalloc.c:121`), so 4096
never gets a zone and every 3073–4096 byte request takes a full
`kmem_alloc_wired`. Changing the test to `>` gives it one and lifts
`k_zone_maxsize` to 4096; the W3 table grows to 257 entries.

Mechanically sound: these zones are non-pageable, so elements come individually
from `zget_space` rather than `zcram`, making `alloc_size` irrelevant. The path
is already proven by the existing 3072 zone. The win is element reuse in place of
a fresh VM map operation per request.

Skipped if baseline `kalloc_oversize_page` is negligible.

**Verify:** `kalloc_oversize_page` reaches 0; `kalloc_oversize` drops by exactly
that amount; a new histogram bucket appears carrying the matching count.

### W5 — TLB flush threshold, i386 (gated on baseline `tlb_full_pages`)

`pmap_update_tlbs` (`machdep/i386/pmap.c:174`) calls `flush_tlb()` — a full CR3
reload — for any range larger than one page. Every two-page `pmap_protect`, COW
downgrade, and `pmap_remove` range discards the entire TLB. Raise the cutoff to a
named constant, starting at 8 pages of `invlpg`.

**Verify:** `tlb_flush_full` down beyond run-to-run spread; `tlb_invlpg_pages`
grows by no more than threshold times the converted count; **and the
`vfs-alloc` checksum comparison passes.** A missed invalidation here produces
silent data corruption rather than a crash, so the checksum is the load-bearing
check — a change that passes the counters and fails the checksum is a stale-TLB
bug, and without it the change would ship believed working.

### W6 — In-kernel zone reclaim before panic (highest risk)

`zone_collect()` (`kern/zalloc.c:925`) and `zone_free_space_reclaim()`
(`kern/zalloc.c:1038`) are compiled unconditionally, but their only caller is
`host_zone_collect()` (`kern/zalloc.c:2036`), which sits inside `#if MACH_DEBUG`
and is reachable only as a MIG RPC (`mach_debug/mach_debug.defs:222`). Zone
reclaim is entirely userland-triggered: nothing in the kernel ever reclaims zone
memory, including the path that panics for want of it. The primitives exist; the
wiring does not.

Factor `zone_reclaim_all()` out of `host_zone_collect`, compiled outside
`#if MACH_DEBUG`, with `host_zone_collect` becoming a caller. Call it once —
guarded by a retry flag so it cannot loop — from the `zget_space` failure path in
`zalloc_canblock` before `panic("zalloc")`.

The risk is lock state, not logic. `host_zone_collect` acquires `zget_space_lock`
and per-zone locks, and the failure site sits in an unlocked window inside a zone
allocation. Reentrancy — reclaim itself needing to allocate — must be ruled out
during implementation. **If it cannot be, this item degrades to "log diagnostics,
then panic" rather than being forced through.**

**Verify:** against the pinned-1 MB-`zone_map` kernel. The baseline must
reproduce `panic("zalloc")` first. After: `zone_space_failures >= 1`,
`zone_reclaims >= 1`, and the system makes forward progress.

### W7 — `doing_alloc` for non-pageable expansion (gated on `zone_expand_races`)

`zone->doing_alloc` is set only in the pageable branch (`kern/zalloc.c:1526`).
The non-pageable branch drops the zone lock and calls `zget_space`, which can
block, so a second allocator finds the zone empty with `doing_alloc` false and
expands it too. Set and clear `doing_alloc` in the non-pageable branch as the
pageable branch already does, with the matching wakeup.

**Verify:** `zone_expand_races` reaches 0.

## Honest expectations

W3 and W4 are certain but small: they remove real work from a hot path, and on a
uniprocessor kernel of this vintage that is unlikely to be user-visible. W5 is
the only item with a plausibly noticeable effect, and TCG cannot confirm it. W2,
W6, and W7 buy stability and diagnosability, not speed. Three of the seven items
can be vetoed by their own baselines.

This spec will not produce a step change in system responsiveness. Deferred
`PGE` is the better candidate for that, and even it is unmeasurable in this
environment.
