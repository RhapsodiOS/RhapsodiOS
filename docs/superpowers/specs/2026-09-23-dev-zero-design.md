# /dev/zero support in the memory device driver — design

Date: 2026-09-23
Status: approved design, ready for an implementation plan

## Goal

Add `/dev/zero` to the kernel's memory-device driver (`mem.c`), on both
`i386` and `ppc`. Reads return zero-filled bytes; writes succeed and discard
their input, matching how `/dev/null` already behaves.

Success: after `MAKEDEV zero`, `dd if=/dev/zero of=/tmp/x bs=4096 count=4`
produces an all-zero 16KB file, and writing to `/dev/zero` succeeds silently
for both architectures.

## Context

`kernel-7/bsd/dev/i386/mem.c` and the parallel `ppc/mem.c` implement the
memory device (major 3) via a shared `mmrw()` function, switched on minor
number:

- minor 0 — `/dev/mem` (physical memory)
- minor 1 — `/dev/kmem` (kernel memory)
- minor 2 — `/dev/null` (EOF/RATHOLE: reads return EOF, writes are discarded)

Both `conf.c` files already register `cdevsw[3]` (the `mem` major) with
`mmread`/`mmwrite` covering all minors uniformly — `mmrw()`'s switch is the
only place minor-specific behavior lives, so no `conf.c` change is needed.

`src/MAKEDEV/MAKEDEV.csh` creates a node at `c 3 3` named `dsp` — a leftover
from NeXT hardware's DSP56001, which has no corresponding case in `mmrw()`
today and is therefore dead. Real Darwin/xnu convention uses minor 3 for
`/dev/zero` on this same driver, so this work repurposes that node.

## Decisions made during brainstorming

- **Minor number 3, replacing `dsp`.** Matches real historical Darwin
  numbering. The existing `dsp` MAKEDEV entry is non-functional (no case 3 in
  `mmrw()` handles it), so renaming it costs nothing real.
- **Read/write only — no `mmap()` support.** The kernel's `mmap()` syscall
  (`kern_mman.c`) unconditionally rejects every character-special device
  (`vp->v_type == VCHR` → `EOPNOTSUPP`) before ever consulting a device's
  `cdevsw` mmap entry, and does not support `MAP_ANON` either. Wiring up
  `/dev/zero` for `mmap()` would mean building general character-device mmap
  support into the VM subsystem for the first time in this kernel tree — a
  materially larger, separate project. This design keeps `/dev/zero`
  consistent with the rest of the kernel's current behavior: `mmap()` on it
  fails with `EOPNOTSUPP`, same as every other device today.
- **Both architectures.** `i386/mem.c` and `ppc/mem.c` are near-identical;
  the change is mirrored in both.

## Design

### `mem.c` (both `i386` and `ppc`)

Add a new `case 3:` branch to the `mmrw()` switch, alongside the existing
minor 2 case:

- **`UIO_WRITE`**: behave exactly like minor 2 — set `c = iov->iov_len` and
  `break` into the existing shared tail that advances `iov`/`uio` without
  copying any data. Writes succeed and are discarded.
- **`UIO_READ`**: copy zeroed bytes to the caller via `uiomove()`, sourced
  from a static, file-scope, BSS-zeroed buffer of `PAGE_SIZE` bytes (BSS is
  zero-initialized, so no explicit zeroing code is needed). Loop like minors
  0/1 do — copy `min(iov->iov_len, PAGE_SIZE)` bytes per `uiomove()` call,
  then `continue` back to the top of the `while (uio->uio_resid > 0 ...)`
  loop — so reads of any size are correctly served in page-sized chunks.

`ppc/mem.c` has a `default: goto fault;` after its switch cases; the new
`case 3:` is inserted before that default, alongside the existing cases.
`i386/mem.c` has no `default:`; the new case is inserted the same way,
before the switch's closing brace.

No changes to either `conf.c` — `cdevsw[3]` already dispatches all minors of
the `mem` major through `mmread`/`mmwrite`.

### `MAKEDEV.csh`

Rename the `dsp` line to `zero`, keeping the same major/minor and
permissions style as the neighboring `null` entry:

```
mknod zero	c 3 3	; chmod 666 zero
```

## Data flow

`read(fd)` on `/dev/zero` → VFS → `spec_read` → `cdevsw[3].d_read`
(`mmread`) → `mmrw(dev, uio, UIO_READ)` → new `case 3` → `uiomove()` copies
zeros from the static zero buffer into the caller's buffer, chunked at
`PAGE_SIZE`, looping until the request is satisfied.

`write(fd, ...)` on `/dev/zero` → same path → `mmwrite` → new `case 3` write
branch discards input, returns success with all bytes "written," identical
to minor 2's behavior.

## Error handling

None needed beyond what's already there. No new fault paths, no
allocations, no locking beyond what `mmrw()` already does — a zero-read
touches no VM state, unlike minors 0/1 which map physical/kernel memory and
take `splvm()`.

## Testing

Per this repo's debugging guidance, use a temporary disk image to keep this
isolated from any other in-progress boot/debug session.

1. Build the kernel for `i386` (and `ppc` if the build box supports it)
   with the new `case 3:` in both `mem.c` files; confirm a clean, warning-
   free compile.
2. Boot a temporary disk image, run `MAKEDEV zero` (or `MAKEDEV std` on a
   fresh image) to create the node.
3. `dd if=/dev/zero of=/tmp/x bs=4096 count=4` — confirm the result is
   16384 bytes and every byte is `0x00` (e.g. via `cmp` against a
   known-zero reference, or `od -An -tx1 /tmp/x | grep -v '^0000000 00'`
   finding nothing).
4. `dd if=/dev/urandom of=/dev/zero bs=4096 count=4` (or equivalent) —
   confirm the write succeeds (exit status 0, no error) and discards its
   input.
5. Repeat 2-4 on `ppc` if a bootable `ppc` image is available in this
   session.
