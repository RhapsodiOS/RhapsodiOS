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
| `/dev/random`, `/dev/urandom` (major 17, minors 0/1) | `random_read` = squeeze, `random_write` = reseed |
| `read_random()` / `RandomULong()` | squeeze |
| libkern `random()` | `RandomULong() & 0x7fffffff` |

## Entropy model (current: "A")

Seeded once at boot from `microtime()` (`csprng_seed`), reseeded by writes
to `/dev/random` (the historical "security server sends entropy" path).
This is weak boot entropy: on 1999-era ppc/i386 there is no hardware RNG,
so early output is only as unpredictable as the boot-time clock. Writes
after boot strengthen the state.

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

## Future hooks (not yet implemented)

- **Entropy model B — opportunistic harvesting:** fold cheap timing jitter
  (interrupt timestamps, `microtime` low bits) into the state via
  `xoodyak_absorb` on paths already taken (device reads, `random()`,
  a hook in the timer/interrupt code).
- **Entropy model C — boot-time pool:** gather several early-boot timing
  samples before declaring the generator ready.
- **Per-open reseed**, an **ioctl** to report/estimate entropy, and
  optional **blocking `/dev/random`** semantics distinct from `/dev/urandom`.
