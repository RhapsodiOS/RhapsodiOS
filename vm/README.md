# Rhapsody QEMU VM

Automated boot/inspect/patch loop for a Rhapsody disk image under modern QEMU
on Windows: boot headlessly or interactively, inspect the UFS image offline,
patch a driver config table or binary in place, and re-boot to observe the
result - without a human watching the VGA window for most of that cycle.

This does not claim the underlying IDE/interrupt boot bug is solved. See
`docs/drivers/drvEIDE-issues.md` for the current state of that investigation.

## Image chain

| File | Role |
|------|------|
| `rhapsody.vmdk` | Original guest disk. Never opened for write, never booted. |
| `golden.img` | Raw conversion of `rhapsody.vmdk` (`qemu-img convert -O raw`). The read-only master; never booted, never written. |
| `work/test.img` | Writable scratch copy of `golden.img`. The **only** image any tool here will boot or write. Disposable - recreate it any time. |

`golden.img` and `rhapsody.vmdk` are never written to directly: `rhap_inject.py`
and `qemu-shot.py` both refuse any path that doesn't resolve to
`vm/work/test.img` (`rhap_inject.check_target`), and `qemu-shot.py` additionally
boots with `-snapshot` so QEMU itself can't write through to the backing file.

## reset-image.cmd

```bat
reset-image.cmd
```

Recreates `work\test.img` from `golden.img` (deletes the old one, then
`qemu-img convert`). Run it whenever the working image might be in a bad
state - before a test run, after an injection you don't want to keep, or
after a rebuild that no longer fits a previously grafted donor (see
`rhap_inject.py` below).

## start-vm.cmd

```bat
start-vm.cmd [-trace]
```

Interactive boot of `work\test.img`. COM1 is `-serial null` (it belongs to
the guest's `drvISASerialPort`); COM2 is `-serial stdio`, so the kernel's
serial debug console (see "Boot prompt" below) prints directly into this
window. `-trace` adds QEMU's `ide_*`/`pci_cfg_*` event tracing plus `-d int`,
logged to `logs\qemu-trace.log`.

## qemu-shot.py

```
python qemu-shot.py IMAGE OUTDIR [--at SECONDS[,SECONDS...]] [--keys STRING] [--keys-at SECONDS] [--trace]
```

Headless capture harness, standard library only:

- `IMAGE` must resolve to `vm/work/test.img`; anything else (including
  `golden.img`) is refused before QEMU is launched. The drive is also opened
  with `-snapshot`.
- Writes `OUTDIR/shot-<seconds>s.png` at each `--at` point via QMP
  `screendump`. These filenames encode **host wall-clock seconds**, not
  guest boot progress - under TCG they are not comparable between runs.
- Writes the guest's COM2 serial console to `OUTDIR/serial.log`. COM1 stays
  `null`, same reasoning as `start-vm.cmd`.
- `--keys STRING` sends keystrokes at the boot prompt via QMP `send-key` at
  `--keys-at` seconds (default 3.0), e.g. `--keys="mach_kernel -v"` to pick a
  kernel and boot verbosely. Supported characters: `a-z`, `0-9`, `-`, `_`,
  `=`, space, and `\n`/`\r` for Return. Typing *any* character at the boot
  prompt cancels its 10-second auto-boot countdown, so a custom command line
  (e.g. one with `rootdev=...` or `serial=...`) needs an explicit trailing
  `\n` in `--keys` to actually submit it - `--keys="-v"` alone still
  auto-boots after the countdown, but `--keys="mach_kernel rootdev=9999 -v"`
  without a trailing newline just sits at the prompt forever.
- `--trace` adds the same tracing `start-vm.cmd -trace` does.

## rhap_image.py (read-only inspector)

```
python rhap_image.py IMAGE {ls|stat|cat|slack} PATH
```

Parses the NeXT disk label and UFS filesystem directly (no `mount`, no
external tools). Read-only, so it accepts any image path, including
`golden.img`. `slack` prints `size max_writable slack`, i.e. how many more
bytes could be written in place before `rhap_inject.py` would refuse.

## rhap_inject.py (in-place writer)

```
python rhap_inject.py IMAGE {set-key|put} ...
```

Only `vm/work/test.img` may be targeted; `check_target` is checked before the
image is ever opened for write. Never allocates - it can only overwrite
bytes within a file's already-allocated fragments.

- `set-key PATH KEY VALUE` - rewrite one `"key" = "value";` entry in a
  DriverKit `.table` config file in place.
- `put PATH LOCAL-FILE` - overwrite an existing regular file in place.
  Refused if the payload needs a different number of fragments than the
  file currently occupies, or if the file has holes.
- `graft_file(img, target_path, donor_path, data)` - Python function only,
  no CLI command. Use it when a payload (typically a rebuilt kernel) is too
  large for its own file's allocation: it repoints `target_path`'s directory
  entry at a donor file's inode after overwriting the donor's blocks and
  bumping its link count. The donor must be an existing, hole-free regular
  file with `nlink == 1` (a private, single-named file) - unless re-grafting
  the same target onto the same donor again, which is idempotent **only**
  while the new payload still fits the donor's *current* size. The first
  graft onto a donor sets its addressable size to that payload's size; a
  later, larger payload does not fit and cannot be grafted onto the same
  donor again. Recovering from that requires `reset-image.cmd` followed by
  re-applying whatever injections are needed, not another graft.

## Boot prompt

At the `boot:` prompt (10 second timeout), type `<kernel> <args>`, e.g.:

```
mach_kernel -v serial=0x2f8
```

- Leaving it blank boots the default kernel from the startup device.
- `serial=0x2f8` selects the kernel serial debug console port (default is
  already COM2/0x2f8; `serial=0x3f8` would use COM1 instead, `serial=0`
  disables it).
- `-v` boots verbosely.
- `rootdev=9999` does **not** panic the kernel: `getargs()` parses a
  purely-numeric `rootdev=` value as an integer and stores its raw bytes
  into `swapgeneric.m`'s `rootdevice` buffer (see `i386_init.c`'s
  `kernargs` table), which then fails `setconf()`'s name match and drops
  into an interactive `root device?` retry loop (`bsd/kern/init_main.c`'s
  mountroot loop) rather than calling `panic()`. Useful for exercising that
  code path, not for producing a `panic:` line.
- A driver's own `IOLog` output reaches serial before `syslogd` opens
  `/dev/klog` too, via the same `putchar()` tap's `TOCONS` pass (see
  `bsd/kern/subr_prf.c`) - so `"Debug" = "Yes"` in a driver's `.table` (e.g.
  `set-key /private/Drivers/i386/EIDE.config/Instance0.table "Debug" Yes`)
  is visible on serial from early boot, not just after login.

## Tests

Standard library only (`unittest`), run from inside `vm/`:

```bat
cd vm
python -m unittest test_rhap_image -v
python -m unittest test_rhap_inject -v
python -m unittest test_qemu_shot -v
```

Tests that need `golden.img` / `work/test.img` skip automatically if those
files haven't been built yet.
