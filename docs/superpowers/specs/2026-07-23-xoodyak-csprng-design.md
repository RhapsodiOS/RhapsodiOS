# Xoodyak CSPRNG for the RhapsodiOS kernel

**Date:** 2026-07-23
**Status:** Approved design, ready for implementation planning

## Problem

The kernel ships a dead, incompatible `/dev/random` implementation and a weak
internal PRNG:

- `src/kernel-7/bsd/dev/random/` contains `randomdev.c` (a `/dev/random` +
  `/dev/urandom` driver) plus `YarrowCoreLib/` (~3,700 lines). It is **never
  compiled** (absent from every `conf/files*` list) and **never referenced**
  (nothing calls `random_init()`, `read_random()`, or `RandomULong()`). It also
  relies on `devfs_make_node`/`cdevsw_add`, a mechanism this kernel does **not**
  use — so the code is not merely dormant, it is incompatible with this kernel.
- The only PRNG actually compiled is `src/kernel-7/bsd/libkern/random.c`, a
  Park–Miller LCG providing `random()`. It is non-cryptographic (a predictable
  31-bit LCG) and is the source used by in-kernel callers (AppleTalk `netat`
  AARP/ADSP, IGMP macros in `netinet`).

There is currently no working `/dev/random` or `/dev/urandom` in this kernel.

## Goal

Remove the Yarrow code and replace it with a single Xoodyak-based CSPRNG that is
actually live in the kernel and backs every random source:

1. `/dev/random` and `/dev/urandom` (wired up and functional for the first time).
2. The kernel-wide exports `read_random()` / `RandomULong()`.
3. The internal `random()` in `libkern`, routed through the same core.

## Non-goals (future work)

Documented as future hooks in `docs/kernel/CSPRNG.md`, not implemented now:

- Opportunistic entropy harvesting (interrupt/timing jitter) — "entropy model B".
- A boot-time entropy pool gathered before the CSPRNG is declared ready —
  "entropy model C".
- Per-open reseed, an ioctl for entropy estimation, blocking `/dev/random`
  semantics.

## Design

### 1. Resulting behavior

One global Xoodyak-based CSPRNG, three consumers:

- **`/dev/random` + `/dev/urandom`** — identical, non-blocking. Read = squeeze
  output. Write = reseed (the existing "Security Server sends entropy" path).
- **`read_random(buf, n)` / `RandomULong()`** kernel exports — squeeze.
- **`random()`** in `libkern` — thin wrapper over `RandomULong()`, masked to 31
  bits, preserving the existing signature and `[0, 2^31 - 1]` range.

Entropy model **A**: a `microtime()` seed at initialization plus reseeds via
device writes. Honest about weak boot entropy on this 1999-era ppc/i386 hardware
(no `RDRAND`, no hardware RNG).

### 2. Crypto primitive — new `bsd/dev/random/xoodyak.{c,h}`

Pure, self-contained, C89 (the `rbuild-c89` branch constraint). No globals, no
locks, no kernel dependencies (fixed-width integer types + `memcpy` only), so it
can be tested in isolation in userland.

- Xoodoo[12] permutation on the 384-bit state (12 x `u_int32_t` lanes).
- Xoodyak Cyclist **keyed mode** API:
  - `xoodyak_init(st, key, keylen)`
  - `xoodyak_absorb(st, buf, len)`
  - `xoodyak_squeeze(st, buf, len)`
  - `xoodyak_ratchet(st)`

Construction as a CSPRNG: initialize keyed mode from the seed, `absorb` to
reseed, `squeeze` for output, `ratchet` after serving output for forward
secrecy.

### 3. CSPRNG driver + state — rewritten `bsd/dev/random/randomdev.{c,h}`

- A single global `xoodyak_state` protected by a **statically-initialized lock**
  (`simple_lock`), replacing the old `mutex_alloc` — this removes any
  init-ordering / allocation-timing dependency, which matters because `random()`
  can be called early.
- `csprng_init()`: build a 16-byte seed from `microtime()`, call `xoodyak_init`,
  set a ready flag. Lazy-initialize on first use so early callers are safe.
- Device ops run under the lock:
  - **read**: loop `xoodyak_squeeze` into the user buffer via `uiomove`, then
    `xoodyak_ratchet` after the request (forward secrecy).
  - **write**: `xoodyak_absorb` the user-supplied bytes (reseed). Keep the
    existing `securelevel` / privilege checks in `open()` for `FWRITE`.
- `read_random()` / `RandomULong()`: lock, squeeze, unlock.
- **Remove** `devfs_make_node`, `cdevsw_add`, `random_cdevsw`, and the
  `<dev/random/YarrowCoreLib/include/yarrow.h>` include from this file — that
  device-registration mechanism is not used by this kernel.

### 4. Static device wiring

- Add one `cdevsw[]` entry in **both** `bsd/dev/i386/conf.c` and
  `bsd/dev/ppc/conf.c`, at the next free major number, kept identical across the
  two architectures. Entry points at `random_open` / `random_close` /
  `random_read` / `random_write`, with `eno_*` stubs for the unused slots.
- `MAKEDEV.csh` (`src/kernel-7/src/MAKEDEV/MAKEDEV.csh`): add
  `mknod random c <maj> 0` and `mknod urandom c <maj> 1` (mode 0644), and add
  `random urandom` to the `rhapsody` device bundle line.

### 5. libkern delegation — `bsd/libkern/random.c`

Replace the Park–Miller body with `return RandomULong() & 0x7fffffff;`. Keeps the
`random()` signature and `[0, 2^31 - 1]` range as a drop-in; drops the static
seed / `first` bootstrap logic.

### 6. Build wiring — `conf/files`

- Add `bsd/dev/random/xoodyak.c` and `bsd/dev/random/randomdev.c` as `standard`.
- `bsd/libkern/random.c` stays `standard`.
- **Delete** `bsd/dev/random/YarrowCoreLib/` entirely (~3,700 lines).

### 7. Testing / verification

- **Primitive (strong criterion):** a standalone C89 known-answer-test harness in
  userland exercising the Xoodyak/Xoodoo test vectors from the specification;
  verify absorb -> squeeze output byte-for-byte.
- **Build:** the kernel compiles for both i386 and ppc with the new files in
  place and Yarrow removed.
- **Runtime (per CLAUDE.md section 6, using a temporary disk image):**
  `head -c 32 /dev/random | hexdump`, `dd if=/dev/urandom bs=16 count=1`; confirm
  reads are non-blocking, writes succeed, and output differs between reads.

There is no in-kernel unit-test framework; the userland KAT harness is the
primary correctness gate for the crypto core.

### 8. Documentation — new `docs/kernel/CSPRNG.md`

Written as part of implementation. Covers: the construction (Xoodoo[12] + Xoodyak
Cyclist keyed mode), the three consumers, entropy model A, the concurrency model,
and the major-number / MAKEDEV wiring. Records the future hooks listed under
Non-goals above.

## Open implementation decisions (resolved)

- The next free `cdevsw[]` major number is chosen during implementation and used
  identically on both architectures.
- `random()` becomes CSPRNG-backed but keeps its exact signature and range, so it
  is a drop-in for existing callers.
