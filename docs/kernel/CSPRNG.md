# Kernel CSPRNG (Xoodyak)

The kernel's random number generator is a single Xoodyak-based CSPRNG that
backs `/dev/random`, `/dev/urandom`, the in-kernel `read_random()` /
`RandomULong()` exports, and libkern `random()`.

## Construction

- **Primitive:** Xoodoo[12] permutation (384-bit state) with the Xoodyak
  Cyclist mode in keyed operation. Implemented clean-room from the public
  specification in `bsd/dev/random/xoodyak.c`; the state is stored as 48
  little-endian bytes and lanes are packed with explicit shifts, so the
  code is correct on both i386 (LE) and ppc (BE).
- **Instance:** one global `xoodyak_t` in `bsd/dev/random/randomdev.c`,
  serialized by a `simple_lock`.
- **Output:** `xoodyak_squeeze`. After serving a request the state is
  advanced with `xoodyak_ratchet` for forward secrecy.
- **Reseed:** `xoodyak_absorb` of caller-supplied bytes (device writes).

## Consumers

| Consumer | Path |
|----------|------|
| `/dev/random`, `/dev/urandom` (major 17, minors 0/1) | `random_read` = squeeze (blocks on minor 0 until warm), `random_write` = reseed, `random_ioctl` = `RANDOM_GETENTROPY` |
| `read_random()` / `RandomULong()` | squeeze |
| libkern `random()` | `RandomULong() & 0x7fffffff` |

## Entropy model

Seeded once at boot from `microtime()` (`csprng_seed`), then continuously
strengthened by three complementary paths. This is still weak boot
entropy in the classical sense: on 1999-era ppc/i386 there is no hardware
RNG, so the earliest output is only as unpredictable as the boot-time
clock and the timing jitter described below.

### Model A — explicit reseed

Writes to `/dev/random` (the historical "security server sends entropy"
path) are absorbed directly via `xoodyak_absorb` in `random_write`.
Per-open reseed also falls in this category: every `open()` of
`/dev/random` or `/dev/urandom` (`random_open`) folds in a fresh
`microtime()` sample, so distinct opens never draw from identical state.

### Model B — opportunistic harvesting

`random_harvest_jitter()` in `randomdev.c` folds cheap timing jitter into
the state via `xoodyak_absorb`, on paths already taken:

- a hook in `hardclock()` (`bsd/kern/kern_clock.c`), passing the
  interrupted PC and PSL — sampled roughly every `RANDOM_HARVEST_DIV`
  (32) ticks, and mixed with the current `microtime()` microsecond
  field.

Because this can run from interrupt context while process-context code
(`random_read`/`random_write`/`read_random`) holds `gRandomLock`, it uses
`simple_lock_try` and simply skips the harvest if the lock is busy,
rather than risking a spin against itself.

### Model C — boot-time pool

The generator does not consider its jitter pool "warm" until
`RANDOM_BOOT_SAMPLES` (8) harvest samples have been folded in by model B.
`gRandomWarm` tracks this and gates the blocking behavior of
`/dev/random` (see below).

### Per-open reseed, ioctl, and blocking semantics

- **Per-open reseed:** see model A above (`random_open`).
- **ioctl:** `RANDOM_GETENTROPY` (`_IOR('R', 1, int)`) returns a
  conservative entropy estimate in bits: `min(harvested_samples *
  RANDOM_BITS_PER_SAMPLE, RANDOM_MAX_BITS)`.
- **Blocking `/dev/random`:** reads from minor `RANDOM_MINOR_RANDOM` (0,
  i.e. `/dev/random`) block in `tsleep()` until `gRandomWarm` is set,
  re-checking once a second and honoring signals (`PCATCH`).
  `/dev/urandom` (minor `RANDOM_MINOR_URANDOM`, 1) never blocks and
  always returns output from current state, matching the historical
  `/dev/random` vs. `/dev/urandom` distinction.

### Seed size refinement (16 → 8 bytes)

The approved design called for a 16-byte `microtime()` seed. This was
refined to **8 bytes**: `struct timeval` on the 32-bit ppc/i386 targets is
two 32-bit longs (`tv_sec` + `tv_usec`), i.e. 8 bytes, so a single
`microtime()` yields 8 bytes — matching what the original Yarrow code
sampled. `csprng_seed()` packs those two longs little-endian into an
8-byte buffer and keys the generator with it.

## Wiring

- Static `cdevsw[]` entry at major 17 in `bsd/dev/i386/conf.c` and
  `bsd/dev/ppc/conf.c` (kept identical).
- Device nodes created by `src/MAKEDEV/MAKEDEV.csh` (`std` stanza).
- `random_init()` is called from `bsd_init()` in `bsd/kern/init_main.c`
  after `log_init()`; device paths also lazy-init on first use.

## Testing

`bsd/dev/random/xoodyak_kat.c` is a standalone host known-answer test (not
part of the kernel build). Build and run:

    cd bsd/dev/random
    mkdir -p /tmp/xdkinc/dev/random && cp xoodyak.h /tmp/xdkinc/dev/random/
    cc -std=c89 -Wall -Wextra -I/tmp/xdkinc -o /tmp/xoodyak_kat xoodyak_kat.c xoodyak.c
    /tmp/xoodyak_kat

All vectors must print `PASS`.
