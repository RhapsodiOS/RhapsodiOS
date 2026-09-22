# Pico Text Editor Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port pico 4.3 from the pine 4.50 release into `src/Commands/pico-1` so rbuild packages it as a universal (ppc+i386) apk listed in `src/Manifest`.

**Architecture:** Upstream `pine4.50/pico/` is imported verbatim, then a new Rhapsody port is added alongside the existing ones: `makefile.rhp`, `osdep/os-rhp.h` and `osdep/os-rhp.ic`, all derived from the NeXT port. A `Common.make` wrapper, following the `src/tcp_wrappers-1` pattern, drives `makefile.rhp` inside rbuild's chroot and installs `/usr/bin/pico` and `pico.1`.

**Tech Stack:** Apple CoreOS ReleaseControl makefiles (`Common.make`), GNU make (`/bin/gnumake` on the guest), Rhapsody `cc`/`lipo`/`otool`, rbuild and apk-tools 2.0, PowerShell guest helpers in `vm/`.

**Spec:** `docs/superpowers/specs/2026-09-21-pico-editor-design.md`

## Global Constraints

- Work only in the worktree `D:\RhapsodiOS\.claude\worktrees\pico-editor` (branch `pico-editor`). Never run git commands in `D:\RhapsodiOS` itself, because other sessions share that checkout's index.
- Project directory: `src/Commands/pico-1`.
- The binary reports version `4.3L`. The apk `pkgver` is `4.3l`; apk-tools only accepts a lowercase letter suffix.
- The only edits to upstream files are `pico/pico.h` (`version = "4.3"` becomes `version = "4.3L"`) and `pico/osdep/unix` (`#define MAX` guarded with `#ifndef MAX`).
- Ship pico only: no `pilot`.
- Installed files are exactly `/usr/bin/pico` (fat ppc+i386, stripped), `/usr/share/man/man1/pico.1`, `/usr/share/doc/pico/CPYRIGHT` and `/usr/share/doc/pico/LOCAL-CHANGES`.
- `apk/pkginfo`: `license = Pine`, `makedepends = build-base`.
- Manifest line: `dir     Commands/pico-1       all`.
- Commit messages start with `pico: `, are one or two lines, and carry **no trailers or metadata** (CLAUDE.md: "Do not add any metadata to commits").
- "Done" means build only. Never run pico on the guest.
- The guest (10.10.0.241) is shared. Use only `/tmp/pico-*`, `/build/out/pico-rbuild` and `/build/state-pico` there. Never start `rbuild bootstrap`, and never touch `/build/state` or `/build/repo` contents.

## Shell variables used throughout

Every Bash command in this plan runs from Git Bash on the Windows host and assumes these two variables. Define them at the start of each command:

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
```

- `$S/pine4.50/` holds the extracted upstream files: `pico/`, `doc/pico.1`, `CPYRIGHT`, and the full `pine4.50.tar` beside it. It was downloaded from `https://ftp.gwdg.de/pub/gnu2/pine/old/pine4.50.tar.Z` (5,773,029 bytes). If it's missing, re-extract with `cd "$S" && gzip -dc pine4.50.tar.Z > pine4.50.tar && tar xf pine4.50.tar ./pine4.50/pico ./pine4.50/doc/pico.1 ./pine4.50/CPYRIGHT`. Run tar from inside `$S`: GNU tar misreads `C:` in a path argument as a remote host.
- Guest scripts and the SSH runner live in `$S`, not in the repository.

## File Map

| Path (under `src/Commands/pico-1/`) | Task | Responsibility |
|---|---|---|
| `pico/**` (186 files), `doc/pico.1`, `CPYRIGHT` | 1 | Upstream pine 4.50 files, verbatim |
| `pico/makefile.rhp` | 2 | Builds `pico` from the port; links objects directly |
| `pico/osdep/os-rhp.h` | 2 | Rhapsody OS settings (termios, `/var/mail`, no `sys_errlist` externs) |
| `pico/osdep/os-rhp.ic` | 2 | Tells `includer` which osdep pieces make up `os-rhp.c` |
| `pico/pico.h` (line 409) | 2 | Version string `4.3L` |
| `pico/osdep/unix` | 2 | `#define MAX` guarded with `#ifndef MAX` (post-review) |
| `LOCAL-CHANGES` | 2 | The change list Pine's license asks for |
| `Makefile` | 3 | Common.make wrapper: shadow build, install |
| `apk/pkginfo` | 3 | Package metadata |
| `src/Manifest` (repo root relative) | 3 | World build entry |

---

### Task 1: Import pico 4.3 from pine 4.50 unmodified

**Files:**
- Create: `src/Commands/pico-1/pico/` (copy of `$S/pine4.50/pico/`, 186 files)
- Create: `src/Commands/pico-1/doc/pico.1`
- Create: `src/Commands/pico-1/CPYRIGHT`
- Test: `$S/check-import.sh` (scratch, not committed)

**Interfaces:**
- Consumes: the upstream extract in `$S/pine4.50/`.
- Produces: `src/Commands/pico-1/pico/`, `doc/pico.1` and `CPYRIGHT` at their tarball-relative paths. Tasks 2 and 3 rely on these exact paths.

- [ ] **Step 1: Confirm the workspace**

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W" && git branch --show-current && git status --short && ls src/Commands
```

Expected: `pico-editor`, no status lines, and no `pico-1` in the Commands listing.

- [ ] **Step 2: Write the import check**

Create `$S/check-import.sh`:

```sh
#!/bin/sh
# Compare src/Commands/pico-1 against the pine 4.50 extract.
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
U="$S/pine4.50"
T="$W/src/Commands/pico-1"
rc=0
# --strip-trailing-cr: four Cygwin/Windows files are stored LF (see Step 5).
diff -r --strip-trailing-cr "$U/pico" "$T/pico" || rc=1
cmp "$U/CPYRIGHT" "$T/CPYRIGHT" || rc=1
cmp "$U/doc/pico.1" "$T/doc/pico.1" || rc=1
n=`find "$T/pico" -type f 2>/dev/null | wc -l | tr -d ' '`
[ "$n" = 186 ] || { echo "expected 186 files under pico/, found $n"; rc=1; }
cr=`grep -rl "$(printf '\r')" "$T" 2>/dev/null`
[ -z "$cr" ] || { echo "CR bytes remain in: $cr"; rc=1; }
[ $rc = 0 ] && echo IMPORT_MATCHES_UPSTREAM
exit $rc
```

- [ ] **Step 3: Run it to verify it fails**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
sh "$S/check-import.sh"; echo "exit=$?"
```

Expected: `diff: .../src/Commands/pico-1/pico: No such file or directory`, `expected 186 files under pico/, found 0`, and `exit=1`.

- [ ] **Step 4: Copy the upstream files**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
mkdir -p "$W/src/Commands/pico-1/doc"
cp -R "$S/pine4.50/pico" "$W/src/Commands/pico-1/pico"
cp "$S/pine4.50/CPYRIGHT" "$W/src/Commands/pico-1/CPYRIGHT"
cp "$S/pine4.50/doc/pico.1" "$W/src/Commands/pico-1/doc/pico.1"
```

- [ ] **Step 5: Store the four CRLF files as LF**

The repository's `.gitattributes` (`* text=auto eol=lf`) would convert these four files on `git add` anyway. Converting them now keeps the working tree identical to what gets committed.

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W/src/Commands/pico-1" && sed -i 's/\r$//' pico/makefile.cyg pico/osdep/os-cyg.h pico/osdep/os-cyg.ic pico/resource.h
```

- [ ] **Step 6: Run the check to verify it passes**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
sh "$S/check-import.sh"; echo "exit=$?"
```

Expected: `IMPORT_MATCHES_UPSTREAM` and `exit=0`.

- [ ] **Step 7: Commit**

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W" && git add src/Commands/pico-1 && git commit -q -m "pico: import pico 4.3 from pine 4.50 unmodified" && git ls-files src/Commands/pico-1 | wc -l && git status --short
```

Expected: `188` (186 + `doc/pico.1` + `CPYRIGHT`) and no status lines.

---

### Task 2: Rhapsody port files and the 4.3L version

**Files:**
- Create: `src/Commands/pico-1/pico/makefile.rhp`
- Create: `src/Commands/pico-1/pico/osdep/os-rhp.h`
- Create: `src/Commands/pico-1/pico/osdep/os-rhp.ic`
- Modify: `src/Commands/pico-1/pico/pico.h:409`
- Create: `src/Commands/pico-1/LOCAL-CHANGES`
- Test: `$S/port-test.sh` (guest script, scratch)
- Setup (not committed): `vm/vm.conf` copied into the worktree, plus `$S/rx.ps1`

**Interfaces:**
- Consumes: Task 1's `src/Commands/pico-1/pico/` tree.
- Produces: `pico/makefile.rhp` with target `pico`, which reads `EXTRACFLAGS` (compiler flags, including `-arch`) and `EXTRALDFLAGS` (linker flags) from the make command line and leaves `pico/pico` in its directory. Task 3's wrapper calls exactly `$(MAKE) -C $(BuildDirectory)/pico -f makefile.rhp EXTRACFLAGS="$(CFLAGS)" EXTRALDFLAGS="$(LDFLAGS)" pico`.
- Produces: `$S/rx.ps1 -ScriptFile <file>`, which runs a local sh script on the guest, streams its output, and exits with the script's exit code. Task 3 uses it.

**Background:** the guest's stock `cc` can compile i386 but can't link it: the PPC host has no i386 `crt1.o` or System library. So this standalone test links ppc only, and separately compiles every object for i386. The real fat link happens in Task 3, inside rbuild's chroot.

- [ ] **Step 1: Set up guest access**

`vm/vm.conf` holds the guest host, user and password. It's gitignored, so the worktree doesn't have it; copy it in. `sync-src.ps1` syncs the `src/` next to its own `vm/` directory, so running it from the worktree syncs the worktree.

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cp /d/RhapsodiOS/vm/vm.conf "$W/vm/vm.conf" && cd "$W" && git check-ignore -q vm/vm.conf && echo VM_CONF_IGNORED
```

Expected: `VM_CONF_IGNORED`.

Create `$S/rx.ps1`:

```powershell
# Run a local sh script on the Rhapsody guest; exit with its exit code.
param([Parameter(Mandatory=$true)][string]$ScriptFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RhapVmDir = 'D:\RhapsodiOS\.claude\worktrees\pico-editor\vm'
. (Join-Path $script:RhapVmDir 'rhap-remote.ps1')
$cfg = Get-RhapVmConfig -DiePrefix 'rx'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'rx'
$body = Get-Content -LiteralPath $ScriptFile -Raw
$ec = Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody $body -Stream
exit $ec
```

Create `$S/rx-smoke.sh`:

```sh
echo RX_OK
uname -a
exit 0
```

Run it:

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/rx-smoke.sh")"; echo "exit=$?"
```

Expected: `RX_OK`, a `uname` line, and `exit=0`.

- [ ] **Step 2: Write the guest port test**

Create `$S/port-test.sh`:

```sh
# Standalone build of pico's Rhapsody port with the guest's stock cc.
# Links ppc; compiles (does not link) every object for i386.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
T=/tmp/pico-port-test
OBJS="main.o attach.o basic.o bind.o browse.o buffer.o composer.o display.o
      file.o fileio.o line.o pico_os.o pico.o random.o region.o search.o
      window.o word.o"
rm -rf $T && mkdir -p $T || exit 1
(cd /build/src/Commands/pico-1 && tar cf - pico) | (cd $T && tar xf -) || exit 1
cd $T/pico || exit 1
[ -f makefile.rhp ] || { echo "PORT_TEST_FAILED: no makefile.rhp"; exit 1; }

echo "== ppc build"
gnumake -f makefile.rhp EXTRACFLAGS="-arch ppc -O" pico > $T/ppc.log 2>&1
rc=$?
tail -15 $T/ppc.log
echo "ppc warnings: `grep -ci warning $T/ppc.log`"
[ $rc = 0 ] || { echo "PORT_TEST_FAILED: ppc build rc=$rc"; exit 1; }
lipo -info pico
otool -L pico
echo "version strings: `grep -c '4\.3L' pico`"
nm pico_os.o | grep winch_handler || { echo "PORT_TEST_FAILED: RESIZING is off"; exit 1; }
nm pico_os.o | grep getwd && { echo "PORT_TEST_FAILED: osdep/getcwd compiled in"; exit 1; }

echo "== i386 compile"
gnumake -f makefile.rhp clean > /dev/null 2>&1
gnumake -f makefile.rhp EXTRACFLAGS="-arch i386 -O" $OBJS > $T/i386.log 2>&1
rc=$?
tail -15 $T/i386.log
echo "i386 warnings: `grep -ci warning $T/i386.log`"
[ $rc = 0 ] || { echo "PORT_TEST_FAILED: i386 compile rc=$rc"; exit 1; }
lipo -info pico_os.o
echo PORT_TEST_OK
exit 0
```

- [ ] **Step 3: Sync and run the test to verify it fails**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W" && powershell -NoProfile -File vm/sync-src.ps1 -Path Commands/pico-1 && powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/port-test.sh")"; echo "exit=$?"
```

Expected: `sync-src: complete`, then `PORT_TEST_FAILED: no makefile.rhp` and `exit=1`.

- [ ] **Step 4: Create `pico/makefile.rhp`**

Recipe lines and the aligned assignments use **tab characters**, exactly as in `makefile.nxt`. Write the file with an editor or tool that keeps tabs.

Create `src/Commands/pico-1/pico/makefile.rhp`:

```make
# Rhapsody port for RhapsodiOS, derived from makefile.nxt,v 4.13
#
#   Michael Seibel
#   Networks and Distributed Computing
#   Computing and Communications
#   University of Washington
#   Administration Builiding, AG-44
#   Seattle, Washington, 98195, USA
#   Internet: mikes@cac.washington.edu
#
#   Please address all bugs and comments to "pine-bugs@cac.washington.edu"
#
#
#   Pine and Pico are registered trademarks of the University of Washington.
#   No commercial use of these trademarks may be made without prior written
#   permission of the University of Washington.
#
#   Pine, Pico, and Pilot software and its included text are Copyright
#   1989-1998 by the University of Washington.
#
#   The full text of our legal notices is contained in the file called
#   CPYRIGHT, included with this distribution.
#

#
# Makefile for Rhapsody version of the stand-alone editor pico.
# CFLAGS for the target architectures arrive in EXTRACFLAGS and
# linker flags in EXTRALDFLAGS.
#

RM=          rm -f
LN=          ln -s
OPTIMIZE=    # -O
PROFILE=     # -pg
DEBUG=       # -g -DDEBUG

STDCFLAGS=	-Drhp -DJOB_CONTROL -DMOUSE
CFLAGS=         $(OPTIMIZE) $(PROFILE) $(DEBUG) $(EXTRACFLAGS) $(STDCFLAGS)

# termcap is part of System, which cc links by default
LIBS=		$(EXTRALDFLAGS)

OFILES=		attach.o basic.o bind.o browse.o buffer.o \
		composer.o display.o file.o fileio.o line.o pico_os.o \
		pico.o random.o region.o search.o \
		window.o word.o

HFILES=		headers.h estruct.h edef.h efunc.h pico.h os.h

#
# dependencies for the Rhapsody version of pico.  The objects are linked
# directly rather than through libpico.a: ranlib can't index an archive
# of fat (multi-architecture) objects.
#
all:		pico

pico:		main.o $(OFILES)
		$(CC) $(CFLAGS) main.o $(OFILES) $(LIBS) -o pico

clean:
		rm -f *.o *~ pico_os.c os.h pico
		cd osdep; $(MAKE) clean; cd ..

os.h:		osdep/os-rhp.h
		$(RM) os.h
		$(LN) osdep/os-rhp.h os.h

pico_os.c:	osdep/os-rhp.c
		$(RM) pico_os.c
		$(LN) osdep/os-rhp.c pico_os.c

$(OFILES) main.o:	$(HFILES)
pico.o:				ebind.h

osdep/os-rhp.c:	osdep/header osdep/unix osdep/read.sel osdep/raw.ios \
		osdep/spell.unx osdep/term.cap \
		osdep/os-rhp.ic
		cd osdep; $(MAKE) includer os-rhp.c; cd ..
```

Verify it against the NeXT makefile:

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W/src/Commands/pico-1/pico" && diff makefile.nxt makefile.rhp; grep -c "$(printf '\t\t')\$(CC)" makefile.rhp
```

Expected: the final `grep -c` prints `1`, which proves the link recipe line starts with two tabs. The diff shows exactly these hunks and no others:

```
1c1
< # $Id: makefile.nxt,v 4.13 2001/10/23 22:18:36 hubert Exp $
---
> # Rhapsody port for RhapsodiOS, derived from makefile.nxt,v 4.13
26,27c26,28
< # Makefile for NeXT version of the PINE composer library and 
< # stand-alone editor pico.
---
> # Makefile for Rhapsody version of the stand-alone editor pico.
> # CFLAGS for the target architectures arrive in EXTRACFLAGS and
> # linker flags in EXTRALDFLAGS.
32d32
< MAKE=        make
35c35
< DEBUG=       -g -DDEBUG
---
> DEBUG=       # -g -DDEBUG
37c37
< STDCFLAGS=	-Dnxt -DJOB_CONTROL -DMOUSE
---
> STDCFLAGS=	-Drhp -DJOB_CONTROL -DMOUSE
40,45c40,41
< # switches for library building
< LIBCMD=		ar
< LIBARGS=	ru
< RANLIB=		ranlib
< 
< LIBS=		$(EXTRALDFLAGS) -ltermcap
---
> # termcap is part of System, which cc links by default
> LIBS=		$(EXTRALDFLAGS)
55c51,53
< # dependencies for the Unix versions of pico and libpico.a
---
> # dependencies for the Rhapsody version of pico.  The objects are linked
> # directly rather than through libpico.a: ranlib can't index an archive
> # of fat (multi-architecture) objects.
57,64c55
< all:		pico pilot
< pico pilot:	libpico.a
< 
< pico:		main.o
< 		$(CC) $(CFLAGS) main.o libpico.a $(LIBS) -o pico
< 
< pilot:		pilot.o
< 		$(CC) $(CFLAGS) pilot.o libpico.a $(LIBS) -o pilot
---
> all:		pico
66,68c57,58
< libpico.a:	$(OFILES)
< 		$(LIBCMD) $(LIBARGS) libpico.a $(OFILES)
< 		$(RANLIB) libpico.a
---
> pico:		main.o $(OFILES)
> 		$(CC) $(CFLAGS) main.o $(OFILES) $(LIBS) -o pico
71c61
< 		rm -f *.a *.o *~ pico_os.c os.h pico pilot
---
> 		rm -f *.o *~ pico_os.c os.h pico
74c64
< os.h:		osdep/os-nxt.h
---
> os.h:		osdep/os-rhp.h
76c66
< 		$(LN) osdep/os-nxt.h os.h
---
> 		$(LN) osdep/os-rhp.h os.h
78c68
< pico_os.c:	osdep/os-nxt.c
---
> pico_os.c:	osdep/os-rhp.c
80c70
< 		$(LN) osdep/os-nxt.c pico_os.c
---
> 		$(LN) osdep/os-rhp.c pico_os.c
82c72
< $(OFILES) main.o pilot.o:	$(HFILES)
---
> $(OFILES) main.o:	$(HFILES)
85c75
< osdep/os-nxt.c:	osdep/header osdep/unix osdep/read.sel osdep/raw.brk \
---
> osdep/os-rhp.c:	osdep/header osdep/unix osdep/read.sel osdep/raw.ios \
87,89c77,78
< 		osdep/getcwd \
< 		osdep/os-nxt.ic
< 		cd osdep; $(MAKE) includer os-nxt.c; cd ..
---
> 		osdep/os-rhp.ic
> 		cd osdep; $(MAKE) includer os-rhp.c; cd ..
```

- [ ] **Step 5: Create `pico/osdep/os-rhp.h`**

`os-rhp.h` is `os-nxt.h` with exactly four changes: termios instead of sgtty, `MAILDIR` `/var/mail`, the `sys_errlist`/`sys_nerr` externs commented out (Rhapsody's `stdio.h` declares them `const`, so NeXT's redeclaration won't compile), and the header comment. Copying and editing preserves the file's tabs exactly:

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W/src/Commands/pico-1/pico/osdep" && sed \
    -e 's/OS dependencies, NeXT version.  See also the os-nxt.c file./OS dependencies, Rhapsody version.  See also the os-rhp.c file./' \
    -e 's|^#include <sgtty.h>      /\* BSD-based systems \*/|/* #include <sgtty.h> */   /* BSD-based systems */|' \
    -e 's|^/\* #define HAVE_TERMIOS \*/ /\* this is an alternative \*/|#define HAVE_TERMIOS    /* this is an alternative */|' \
    -e 's|^/\* #include <termios.h> \*/ /\* POSIX \*/|#include <termios.h>    /* POSIX */|' \
    -e 's|^#define MAILDIR\t\t"/usr/spool/mail"|#define MAILDIR\t\t"/var/mail"|' \
    -e 's|^extern char \*sys_errlist\[\];|/* extern char *sys_errlist[]; */|' \
    -e 's|^extern int   sys_nerr;|/* extern int   sys_nerr; */|' \
    os-nxt.h > os-rhp.h && diff os-nxt.h os-rhp.h
```

Expected diff, exactly:

```
7c7
<    OS dependencies, NeXT version.  See also the os-nxt.c file.
---
>    OS dependencies, Rhapsody version.  See also the os-rhp.c file.
89c89
< #include <sgtty.h>      /* BSD-based systems */
---
> /* #include <sgtty.h> */   /* BSD-based systems */
96,97c96,97
< /* #define HAVE_TERMIOS */ /* this is an alternative */
< /* #include <termios.h> */ /* POSIX */
---
> #define HAVE_TERMIOS    /* this is an alternative */
> #include <termios.h>    /* POSIX */
154c154
< #define MAILDIR		"/usr/spool/mail"
---
> #define MAILDIR		"/var/mail"
175,176c175,176
< extern char *sys_errlist[];
< extern int   sys_nerr;
---
> /* extern char *sys_errlist[]; */
> /* extern int   sys_nerr; */
```

`RESIZING` stays enabled: `<termios.h>` includes `<sys/termios.h>`, which includes `<sys/ttycom.h>` (where `TIOCGWINSZ` is defined). The port test's `winch_handler` check in Step 9 confirms this.

- [ ] **Step 6: Create `pico/osdep/os-rhp.ic`**

This is `os-nxt.ic` with `raw.brk` changed to `raw.ios` and the `getcwd` include dropped. Create `src/Commands/pico-1/pico/osdep/os-rhp.ic`:

```
;
; Rhapsody os-rhp.ic file for building os-rhp.c.
;
; Boilerplate header.
include(header)

include(unix)

include(spell.unx)

include(read.sel)

include(raw.ios)

include(term.cap)
```

Verify:

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W/src/Commands/pico-1/pico/osdep" && diff os-nxt.ic os-rhp.ic
```

Expected:

```
2c2
< ; NeXT os-nxt.ic file for building os-nxt.c.
---
> ; Rhapsody os-rhp.ic file for building os-rhp.c.
13c13
< include(raw.brk)
---
> include(raw.ios)
16,17d15
< 
< include(getcwd)
```

- [ ] **Step 7: Mark the version 4.3L**

`pico/pico.h` line 409 is `char<TAB>*version = "4.3";<TAB><TAB>/* PICO version number */`. It's the only `"4.3"` in pico's `.c` and `.h` files.

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W/src/Commands/pico-1/pico" && sed -i 's/^\(char\t\*version = "\)4\.3";/\14.3L";/' pico.h && sed -n 409p pico.h
```

Expected: `char	*version = "4.3L";		/* PICO version number */`

- [ ] **Step 8: Check the upstream delta locally**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
diff -r --strip-trailing-cr "$S/pine4.50/pico" "$W/src/Commands/pico-1/pico"
```

Expected: exactly four entries. The paths start with the `$S` and `$W` prefixes.

```
Only in .../src/Commands/pico-1/pico: makefile.rhp
Only in .../src/Commands/pico-1/pico/osdep: os-rhp.h
Only in .../src/Commands/pico-1/pico/osdep: os-rhp.ic
diff -r --strip-trailing-cr .../pine4.50/pico/pico.h .../src/Commands/pico-1/pico/pico.h
409c409
< char	*version = "4.3";		/* PICO version number */
---
> char	*version = "4.3L";		/* PICO version number */
```

- [ ] **Step 9: Sync and run the port test to verify it passes**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W" && powershell -NoProfile -File vm/sync-src.ps1 -Path Commands/pico-1 && powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/port-test.sh")"; echo "exit=$?"
```

Expected, in order:
- `lipo -info pico` shows `Non-fat file: pico is architecture: ppc`.
- `otool -L pico` lists only `/System/Library/Frameworks/System.framework/Versions/B/System (...)`.
- `version strings:` is 1 or more.
- An `nm` line naming `_winch_handler`.
- No `getwd` line.
- `lipo -info pico_os.o` shows architecture `i386`.
- `PORT_TEST_OK` and `exit=0`.

Read both `warnings:` counts and the log tails. Warnings don't fail the test, but an "implicit declaration" or "conflicting types" warning points at a wrong `os-rhp.h` setting. Report any to the controller.

If the ppc link fails with `tgetent` (or another termcap symbol) undefined, change the `LIBS` line in `makefile.rhp` to `LIBS=		$(EXTRALDFLAGS) -lcurses`. Libsystem installs `libcurses.dylib` as an alias for System. Then add that change to the `makefile.rhp` entry in `LOCAL-CHANGES` (Step 10) and re-run this step. Any other failure: fix it at its cause, keep the fix inside the three new port files if at all possible, and list any upstream-file edit in `LOCAL-CHANGES`.

- [ ] **Step 10: Write `LOCAL-CHANGES`**

Create `src/Commands/pico-1/LOCAL-CHANGES`:

```
Local changes to pico 4.3 for RhapsodiOS
========================================

This is pico 4.3L: pico 4.3 as released in pine 4.50, modified locally
to build on Rhapsody (Mac OS X Server 1.x) for RhapsodiOS. As the
University of Washington's legal notices (CPYRIGHT) request, the version
number carries the "L" suffix and the local changes are listed here.

Source: https://ftp.gwdg.de/pub/gnu2/pine/old/pine4.50.tar.Z
        (pine4.50/pico, pine4.50/doc/pico.1, pine4.50/CPYRIGHT)

Changed upstream file
  pico/pico.h          version string "4.3" -> "4.3L"

New files: a Rhapsody port alongside the existing ones
  pico/makefile.rhp    derived from makefile.nxt.  Builds pico only (no
                       pilot), links the objects directly instead of
                       through libpico.a (ranlib can't index an archive
                       of fat objects), and gets termcap from System
                       instead of -ltermcap.
  pico/osdep/os-rhp.h  derived from os-nxt.h.  POSIX termios instead of
                       sgtty, MAILDIR /var/mail, and no sys_errlist or
                       sys_nerr declarations (stdio.h declares them).
  pico/osdep/os-rhp.ic derived from os-nxt.ic.  raw.ios instead of
                       raw.brk, and libc's getcwd instead of
                       osdep/getcwd.

Line endings
  pico/makefile.cyg, pico/osdep/os-cyg.h, pico/osdep/os-cyg.ic and
  pico/resource.h (Cygwin and Windows only) are stored with LF line
  endings instead of CRLF, as the repository's .gitattributes requires.

Outside pico/
  Makefile, apk/pkginfo and this file are RhapsodiOS build glue.
```

- [ ] **Step 11: Commit**

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W" && git add src/Commands/pico-1 && git status --short && git commit -q -m "pico: add a Rhapsody port and mark the build 4.3L" && git status --short
```

Expected before the commit: `A` lines for `LOCAL-CHANGES`, `pico/makefile.rhp`, `pico/osdep/os-rhp.h` and `pico/osdep/os-rhp.ic`, plus `M` for `pico/pico.h`. Nothing under `vm/`. After the commit: no status lines.

**Post-review decision (2026-09-21):** the review found the NeXT `HAVE_WAIT_UNION` setting and upstream's unconditional `MAX` each produced a warning in both builds. The user chose to comment out `HAVE_WAIT_UNION` in `os-rhp.h` (as `os-neb.h` does) and guard `MAX` in `osdep/unix`; both are listed in `LOCAL-CHANGES`, and the port test then reported 0 warnings.

---

### Task 3: Package with rbuild and list it in the Manifest

**Files:**
- Create: `src/Commands/pico-1/Makefile`
- Create: `src/Commands/pico-1/apk/pkginfo`
- Modify: `src/Manifest`, adding one line after `dir     perl-1                all`
- Test: `$S/pkg-precheck.sh`, `$S/pkg-start.sh`, `$S/pkg-check.sh` (guest scripts, scratch)

**Interfaces:**
- Consumes: Task 2's `makefile.rhp` target `pico`, with `EXTRACFLAGS`/`EXTRALDFLAGS`, and `$S/rx.ps1`.
- Produces: `/build/out/pico-rbuild/pico-4.3l-1-universal.apk` on the guest.

**Background:** rbuild runs `make install` in a chroot built from `/build/repo`, passing `SRCROOT`, `OBJROOT`, `SYMROOT`, `DSTROOT` and the `RC_*` variables. `Common.make`'s `install::` runs `build` first, and the `install::` rule below then appends to it. `INSTALL_PROGRAM` strips the binary. When this plan was written, another session was re-running `rbuild bootstrap` on the guest and `/build/repo` held only 7 thin apks. The universal build-base packages pico needs don't exist until that finishes, including its `bootstrap-universal` pass. Hence the precheck.

- [ ] **Step 1: Write the guest scripts**

Create `$S/pkg-precheck.sh`:

```sh
# Is /build/repo ready for a universal buildpackage?
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
busy=`ps -ax | grep 'rbuild bootstrap' | grep -v grep | wc -l | tr -d ' '`
echo "rbuild bootstrap processes running: $busy"
ls /build/repo/libsystem-*-universal.apk 2>/dev/null
if [ "$busy" = 0 ] && ls /build/repo/libsystem-*-universal.apk > /dev/null 2>&1; then
    echo REPO_READY
    exit 0
fi
echo REPO_NOT_READY
exit 1
```

Create `$S/pkg-start.sh`:

```sh
# Start rbuild buildpackage for pico under nohup; returns immediately.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
rm -rf /build/out/pico-rbuild
mkdir -p /build/out/pico-rbuild /build/state-pico
rm -f /tmp/pico-rbuild.log /tmp/pico-rbuild.rc
cat > /tmp/pico-rbuild.sh <<'EOF'
#!/bin/sh
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
rbuild buildpackage --state /build/state-pico --dir --target all \
    /build/src/Commands/pico-1 /build/repo /build/out/pico-rbuild \
    > /tmp/pico-rbuild.log 2>&1
echo $? > /tmp/pico-rbuild.rc
EOF
chmod a+x /tmp/pico-rbuild.sh
nohup /tmp/pico-rbuild.sh > /dev/null 2>&1 < /dev/null &
echo PKG_BUILD_STARTED
exit 0
```

Create `$S/pkg-check.sh`:

```sh
# Report on the pico buildpackage: running, failed, or check the apk.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
APK=/build/out/pico-rbuild/pico-4.3l-1-universal.apk
X=/tmp/pico-apk-check
if [ ! -f /tmp/pico-rbuild.rc ]; then
    echo PKG_BUILD_RUNNING
    tail -3 /tmp/pico-rbuild.log 2>/dev/null
    exit 2
fi
rc=`cat /tmp/pico-rbuild.rc`
tail -25 /tmp/pico-rbuild.log
echo "RBUILD_RC=$rc"
[ "$rc" = 0 ] || { echo "PACKAGE_TEST_FAILED: rbuild rc=$rc"; exit 1; }
ls -l /build/out/pico-rbuild
[ -f $APK ] || { echo "PACKAGE_TEST_FAILED: missing $APK"; exit 1; }
echo "== regular files in the apk"
gzip -dc $APK | tar tvf - | grep '^-'
rm -rf $X && mkdir -p $X && cd $X || exit 1
gzip -dc $APK | tar xf - ./usr/bin/pico ./usr/share/man/man1/pico.1 \
    || { echo "PACKAGE_TEST_FAILED: extract"; exit 1; }
echo "== lipo"
lipo -info usr/bin/pico
lipo -info usr/bin/pico | grep ppc | grep i386 > /dev/null \
    || { echo "PACKAGE_TEST_FAILED: not fat ppc+i386"; exit 1; }
for a in ppc i386; do
    echo "== otool -arch $a"
    otool -arch $a -L usr/bin/pico
    otool -arch $a -L usr/bin/pico | sed 1d | grep System.framework > /dev/null \
        || { echo "PACKAGE_TEST_FAILED: $a does not link System"; exit 1; }
    other=`otool -arch $a -L usr/bin/pico | sed 1d | grep -v System.framework`
    [ -z "$other" ] || { echo "PACKAGE_TEST_FAILED: $a links more than System"; exit 1; }
done
echo PACKAGE_TEST_OK
exit 0
```

- [ ] **Step 2: Check the repo precondition**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-precheck.sh")"; echo "exit=$?"
```

If `REPO_NOT_READY`: carry on with Steps 4–6 (writing the files), then **stop before Step 7 and report BLOCKED** to the controller with the precheck output. Do not start, restart or wait on a bootstrap yourself; the controller resumes this task at Step 3 once the repo is ready. If `REPO_READY`, continue in order.

- [ ] **Step 3: Run the package build to verify it fails**

The project has no `Makefile` or `apk/pkginfo` yet, so rbuild must refuse it.

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W" && powershell -NoProfile -File vm/sync-src.ps1 -Path Commands/pico-1 && powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-start.sh")"; sleep 20; powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-check.sh")"; echo "exit=$?"
```

Expected: `PKG_BUILD_STARTED`, then a log tail with an rbuild error about the missing `apk/pkginfo` (the exact wording may vary), a non-zero `RBUILD_RC=`, `PACKAGE_TEST_FAILED: rbuild rc=...`, and `exit=1`. If you get `PKG_BUILD_RUNNING` instead, wait 20 seconds and re-run only the `pkg-check.sh` command.

- [ ] **Step 4: Create the wrapper `Makefile`**

Recipe lines start with a **tab**. Create `src/Commands/pico-1/Makefile`:

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

Check the tabs:

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
grep -c "^$(printf '\t')" "$W/src/Commands/pico-1/Makefile"
```

Expected: `6` (four `install::` lines, the `$(_v)` line, and its continuation).

- [ ] **Step 5: Create `apk/pkginfo`**

Create `src/Commands/pico-1/apk/pkginfo`:

```
pkgname = pico
pkgver = 4.3l
pkgdesc = Pico text editor
maintainer = Darwin Developers <darwin-development@public.lists.apple.com>
license = Pine
url = https://ftp.gwdg.de/pub/gnu2/pine/old/pine4.50.tar.Z
makedepends = build-base
```

- [ ] **Step 6: Add the Manifest entry**

In `src/Manifest`, insert one line directly after `dir     perl-1                all`. Entries are ordered by project name, so `pico` goes between `perl-1` and `project_makefiles-1`. The project column is 22 characters wide: `Commands/pico-1` (15 characters) plus 7 spaces.

```
dir     perl-1                all
dir     Commands/pico-1       all
dir     project_makefiles-1   all
```

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W" && sed -i 's|^dir     perl-1                all$|&\ndir     Commands/pico-1       all|' src/Manifest && grep -n -B1 -A1 'Commands/pico-1' src/Manifest && git diff --stat src/Manifest
```

Expected: the three lines shown above, and `1 file changed, 1 insertion(+)`. (Another session may be rewriting other `src/Manifest` entries on its own branch. This line doesn't touch those entries; any merge conflict is resolved when the branches merge, not here.)

- [ ] **Step 7: Sync, build, and run the package check to verify it passes**

Only when Step 2 printed `REPO_READY` (re-run Step 2 first if in doubt). The build extracts the whole build-base into a chroot and compiles pico for two architectures, so it takes several minutes.

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W" && powershell -NoProfile -File vm/sync-src.ps1 -Path Commands/pico-1 && powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-start.sh")"
```

Expected: `PKG_BUILD_STARTED`. Then poll roughly every 2 minutes until the exit code isn't 2:

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-check.sh")"; echo "exit=$?"
```

Expected at the end:
- `RBUILD_RC=0`.
- `pico-4.3l-1-universal.apk` in the `ls -l` output (`pico-hdrs-…`/`pico-obj-…` companions may also appear).
- The regular files are exactly `./usr/bin/pico`, `./usr/share/man/man1/pico.1` and apk metadata such as `.PKGINFO`.
- `lipo -info` shows `Architectures in the fat file: usr/bin/pico are: ppc i386` (either order).
- Both `otool -arch` blocks list only `/System/Library/Frameworks/System.framework/Versions/B/System (...)`.
- `PACKAGE_TEST_OK` and `exit=0`.

On failure, read `/tmp/pico-rbuild.log` on the guest (the check prints its tail; for more, put `tail -200 /tmp/pico-rbuild.log` in a script and run it through `rx.ps1`). If a termcap symbol is undefined at link time, apply the `-lcurses` fallback from Task 2 Step 9 and record it in `LOCAL-CHANGES`. Fix any other failure at its cause, then re-run this step.

- [ ] **Step 8: Commit**

```bash
W=/d/RhapsodiOS/.claude/worktrees/pico-editor
cd "$W" && git add src/Commands/pico-1/Makefile src/Commands/pico-1/apk/pkginfo src/Manifest && git status --short && git commit -q -m "pico: package pico with rbuild and list it in the world Manifest" && git status --short
```

Expected before the commit: `A` for `Makefile` and `apk/pkginfo`, and `M` for `src/Manifest`. If Step 7 changed `LOCAL-CHANGES` or `makefile.rhp`, add those paths too. After the commit: no status lines.

- [ ] **Step 9: Clean up guest scratch space**

Create `$S/pkg-cleanup.sh`:

```sh
rm -rf /tmp/pico-port-test /tmp/pico-apk-check /tmp/pico-rbuild.sh
ls -l /build/out/pico-rbuild
exit 0
```

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/b87a747c-bf4d-4edc-957f-272a66e044d0/scratchpad"
powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-cleanup.sh")"; echo "exit=$?"
```

Expected: the apk listing and `exit=0`. The apk in `/build/out/pico-rbuild`, `/tmp/pico-rbuild.log` and `/build/state-pico` are kept as evidence.

**Run note (2026-09-22):** this plan originally expected `pico-4.3l-universal.apk`. rbuild appends the source directory's version suffix (`pico-1` gives `-1`), so the real file is `pico-4.3l-1-universal.apk`, with `.PKGINFO` `pkgver = 4.3l-1`. The first `pkg-check.sh` run failed only on that name, even though `RBUILD_RC=0`. With the name corrected, it printed `PACKAGE_TEST_OK`: fat ppc+i386 `pico`, System as the only library for both, 0 warnings in the rbuild log, and no `-hdrs`/`-obj` companions. The RED run in Step 3 was skipped because Steps 4–6 had been written while the repo was blocked.

---

## After all tasks

**Final review decisions (2026-09-22):** the whole-branch review found that Rhapsody's `install` moves its source unless given `-c`, so the wrapper now installs files from the source tree with `-c`. At the user's direction, the package also installs `CPYRIGHT` and `LOCAL-CHANGES` in `/usr/share/doc/pico/` so Pine's permission notice ships with the binary; `osdep/makedep` and `cc5.sol` got upstream's exec bit back; and `makefile.rhp`'s `clean` also removes `osdep/os-rhp.c`. Task 2's Steps 5, 8 and 10 and Task 3's Steps 4 and 7 still show the pre-review text; the post-review note at the end of Task 2 and this note supersede them.

Use superpowers:finishing-a-development-branch to decide how `pico-editor` goes back to `master`.
