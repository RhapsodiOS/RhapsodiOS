# Pico text editor package

## Goal

Give RhapsodiOS a friendly command-line text editor by porting pico 4.3
from the pine 4.50 release into `src/Commands/pico-1`. The project must be
packaged by rbuild as an apk and listed in `src/Manifest`.

Source: <https://ftp.gwdg.de/pub/gnu2/pine/old/pine4.50.tar.Z>
(5,773,029 bytes). The `pico/` subtree holds about 21k lines of C.

## Non-goals

- `pilot`, the file browser that pico's makefile also builds. It can be
  added later.
- Fixing the 18 stale Commands entries in `src/Manifest` (`bash-1`,
  `tcsh-1`, and so on). Those directories moved to `src/Commands/<name>`
  and the Manifest was never updated. This is a separate job.
- Running pico. For this work, "done" means a clean universal build with
  the right package contents. Running it on the guest or booting it in
  QEMU is out of scope.

## License

Pine's `CPYRIGHT` allows free-of-charge redistribution and local
modification. It asks that locally modified versions append "L" to the
version number and list their local changes. We follow that request:

- pico's version string becomes `4.3L`.
- `LOCAL-CHANGES` at the project root lists every change from upstream.
- `CPYRIGHT` ships verbatim.

The apk `pkgver` is `4.3l`. apk-tools only accepts a lowercase letter
suffix (`islower` in `apk-tools/src/version.c`), so the package version
and the binary's own version string differ in case.

## Layout

Files keep their paths from the pine tarball, so any file can be diffed
against upstream directly.

```
src/Commands/pico-1/
  Makefile           new: Common.make wrapper
  apk/pkginfo        new
  LOCAL-CHANGES      new
  CPYRIGHT           verbatim from pine4.50/
  doc/pico.1         verbatim from pine4.50/doc/
  pico/              verbatim pine4.50/pico/, all of it, plus:
    makefile.rhp       new
    osdep/os-rhp.h     new
    osdep/os-rhp.ic    new
```

The only edit to an upstream file is `pico/pico.h`, which changes
`version = "4.3"` to `version = "4.3L"`.

Four Cygwin- and Windows-only files ship with CRLF line endings:
`pico/makefile.cyg`, `pico/osdep/os-cyg.h`, `pico/osdep/os-cyg.ic`, and
`pico/resource.h`. The repository's `.gitattributes` (`* text=auto eol=lf`)
stores them with LF. `LOCAL-CHANGES` records this. All 186 files in
`pico/` are plain text, with no symlinks and no names that collide on a
case-insensitive filesystem.

## Packaging and hook-up

`apk/pkginfo`:

```
pkgname = pico
pkgver = 4.3l
pkgdesc = Pico text editor
maintainer = Darwin Developers <darwin-development@public.lists.apple.com>
license = Pine
url = https://ftp.gwdg.de/pub/gnu2/pine/old/pine4.50.tar.Z
makedepends = build-base
```

`build-base` already includes `libsystem`, which carries termcap, so no
other dependency is needed.

`src/Manifest` gains one line, placed alphabetically:

```
dir     Commands/pico-1       all
```

This uses the `Commands/<name>` form from `src/BootstrapManifest`, which is
the form that resolves to real directories.

Installed files:

- `/usr/bin/pico`: fat ppc+i386, stripped
- `/usr/share/man/man1/pico.1`

## Build flow

### Wrapper `Makefile`

The wrapper follows `src/tcp_wrappers-1/Makefile`, the existing pattern for
a non-autoconf upstream kept in a subdirectory:

```make
##
# Makefile for pico
##

# Project info
Project  = pico
UserType = Administration
ToolType = Commands

include $(MAKEFILEPATH)/CoreOS/ReleaseControl/Common.make

install::
	$(INSTALL_DIRECTORY) $(DSTROOT)$(USRBINDIR)
	$(INSTALL_DIRECTORY) $(DSTROOT)$(MANDIR)/man1
	$(INSTALL_PROGRAM)   $(BuildDirectory)/pico/pico $(DSTROOT)$(USRBINDIR)
	$(INSTALL_FILE)      $(Sources)/doc/pico.1       $(DSTROOT)$(MANDIR)/man1

build:: shadow_source
	$(_v) $(MAKE) -C $(BuildDirectory)/pico -f makefile.rhp \
	      EXTRACFLAGS="$(CFLAGS)" EXTRALDFLAGS="$(LDFLAGS)" pico
```

- `shadow_source` mirrors the source tree into `OBJROOT` as symlinks.
  Generated files (`os.h`, `pico_os.c`, `osdep/os-rhp.c`, `includer`,
  objects) never land in `src/`.
- `CFLAGS` comes from `Standard/Implicit.make` and `Common.make`:
  `-arch ppc -arch i386 -g -O3 $(RC_CFLAGS)`. Passing it as `CFLAGS=` would
  override pico's own `CFLAGS` and drop its `-D` flags, so it enters
  through pico's existing `EXTRACFLAGS` hook instead.
- `LDFLAGS` enters through pico's `EXTRALDFLAGS` hook for the same
  reason. It carries the `-arch` flags plus `OTHER_LDFLAGS`, which rbuild
  fills with the sysroot `-F`/`-L` flags when it builds with a toolchain
  profile. Repeating `-arch` flags is harmless; Common.make already puts
  them in both `CC_Archs` and `RC_CFLAGS`.
- `INSTALL_PROGRAM` includes `-s`. strip handles fat binaries, as it
  already does for tcp_wrappers.

### `pico/makefile.rhp`

`makefile.rhp` is `makefile.nxt` with these changes:

1. `STDCFLAGS = -Drhp -DJOB_CONTROL -DMOUSE`. `OPTIMIZE`, `PROFILE`, and
   `DEBUG` are left empty because the wrapper supplies optimization and
   debug flags.
2. No `libpico.a`, `ar`, or `ranlib` step. `pico` links from
   `main.o $(OFILES)` directly. An archive of fat (ppc+i386) objects does
   not work with the NeXT-era `ranlib`.
3. `LIBS = $(EXTRALDFLAGS)`, with no termcap library. `tgetent`,
   `tgetstr`, `tgoto`, and `tputs` come from Libcurses, which Libsystem
   harvests into System.framework (`ARGON_PROJECTS` in
   `Libsystem-2/Makefile.postamble`), and `cc` links System by default.
   There is no `libtermcap`, so the NeXT port's `-ltermcap` would fail.
4. It builds `pico` only: no `pilot` target, no `MAKE = make` override
   (the inherited `$(MAKE)` is used), and `os.h` and `pico_os.c` link to
   `osdep/os-rhp.h` and `osdep/os-rhp.c`.

Everything else carries over from `makefile.nxt` unchanged: the `OFILES`
and `HFILES` lists, the header dependencies, and the `clean` target minus
`pilot`.

### osdep generation

`os-rhp.c` is generated the same way upstream generates the others:
`cd osdep; $(MAKE) includer os-rhp.c`. `osdep/makefile` builds `includer`
with plain `$(CC) -o includer includer.c`, so it is a native binary that
runs on the build host. Its `.ic.c` suffix rule then assembles `os-rhp.c`
from the `include(...)` pieces. `osdep/makefile` is not edited, because the
suffix rule works for any name. `makefile.rhp` lists the `os-rhp.c`
dependencies itself, as `makefile.nxt` does for `os-nxt.c`.

## Port settings

### `pico/osdep/os-rhp.h`

`os-rhp.h` is a copy of `os-nxt.h` with exactly four changes:

| Setting | NeXT | Rhapsody | Reason |
|---|---|---|---|
| Terminal driver | `#include <sgtty.h>` | `#define HAVE_TERMIOS` and `#include <termios.h>` | termios is Rhapsody's native 4.4BSD API; sgtty would depend on the kernel's `compat_43` layer. The NetBSD port (`os-neb.h`) makes the same choice. |
| `sys_errlist` and `sys_nerr` externs | declared | removed | `kernel-7/bsd/include/stdio.h` already declares `extern __const char *__const sys_errlist[]`. NeXT's `extern char *sys_errlist[]` conflicts with it and won't compile. |
| `MAILDIR` | `"/usr/spool/mail"` | `"/var/mail"` | Matches `_PATH_MAILDIR` in `kernel-7/bsd/include/paths.h`. |
| Header comment | "NeXT version" | "Rhapsody version" | |

Everything else keeps NeXT's settings, since Rhapsody's userland comes from
NeXT's:

- `ANSI`
- `<sys/dir.h>`
- `<locale.h>` with `collator strucmp`
- BSD signals with `SIGNALHASARG` and `SIG_PROTO(args) args`
- `QSType void`
- `NON_BLOCKING_IO FNDELAY`
- `USE_TERMCAP`
- `HAVE_WAIT_UNION` (`union wait` exists in `kernel-7/bsd/sys/wait.h`)
- `RESIZING` via `TIOCGWINSZ`/`SIGWINCH`. It stays enabled with termios:
  `<termios.h>` includes `<sys/termios.h>`, which includes
  `<sys/ttycom.h>` (where `TIOCGWINSZ` is defined) whenever
  `_POSIX_SOURCE` is not set.
- `SPELLER "/usr/bin/spell"`
- the xterm mouse strings

### `pico/osdep/os-rhp.ic`

`os-rhp.ic` is `os-nxt.ic` with two changes:

- `include(raw.brk)` becomes `include(raw.ios)`, the termios raw-mode code
  that matches `HAVE_TERMIOS`.
- `include(getcwd)` is removed, so libc's `getcwd` is used instead of the
  NeXT replacement built on `getwd`.

The result:

```
include(header)
include(unix)
include(spell.unx)
include(read.sel)
include(raw.ios)
include(term.cap)
```

## Error handling

If the link reports `tgetent` or another termcap symbol as undefined, set
`LIBS = $(EXTRALDFLAGS) -lcurses` in `makefile.rhp`. Libsystem installs
`/usr/lib/libcurses.dylib` as an alias for System (`after_install` in
`Libsystem-2/Makefile.postamble`), so this is a one-line fix and needs no
design change. There are no other planned fallbacks. Any other build
failure is fixed at its cause, and the fix is recorded in `LOCAL-CHANGES`
if it touches an upstream file.

## Verification

Build only; nothing is run.

1. Sync the project to the guest (10.10.0.241, `/build`):
   `powershell -File vm\sync-src.ps1 -Path Commands/pico-1`.
2. Precondition: `/build/repo` must hold the universal build-base
   packages. When this spec was written, another session was running
   `rbuild bootstrap` on the guest and `/build/repo` held only 7 thin
   apks. The packaging build waits until no `rbuild bootstrap` process is
   running and `libsystem-*-universal.apk` exists. It never starts a
   bootstrap itself.
3. On the guest, with `/build/tools/bin` on `PATH`:
   ```sh
   rbuild buildpackage --state /build/state-pico --dir --target all \
       /build/src/Commands/pico-1 /build/repo /build/out/pico-rbuild
   ```
   It must exit 0. The dedicated state and output directories keep this
   build away from other sessions' state and results on the shared guest.
4. `/build/out/pico-rbuild/pico-4.3l-universal.apk` exists. In
   `gzip -dc /build/out/pico-rbuild/pico-4.3l-universal.apk | tar tvf -`,
   the only regular files are `./usr/bin/pico`,
   `./usr/share/man/man1/pico.1`, and apk metadata. Their parent
   directories may also be listed.
5. Extract `usr/bin/pico` from the apk without running it:
   - `lipo -info` must report both `ppc` and `i386`.
   - `otool -L` must list System.framework as the only library.
6. The Manifest entry must name `Commands/pico-1`, and
   `src/Commands/pico-1` must exist.

## Workflow

- The work is done in the `pico-editor` worktree
  (`.claude/worktrees/pico-editor`, branched from `master`). Other sessions
  share the main checkout's index.
- Commits use the `pico:` prefix and short messages, per `CLAUDE.md`.
