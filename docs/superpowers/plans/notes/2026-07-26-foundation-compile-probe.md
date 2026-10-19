# Foundation compile probe (stage 1 go/no-go gate)

Records whether an unmodified `src/Kits/Foundation` stub `.m` compiles to a
`.o` against the unmodified 66-header set, with no Foundation implementation
existing anywhere in the tree. This is spec §5.3's go/no-go gate: everything
after it (Tasks 2-15) assumes this works.

## RESULT: compiles

## How Libsystem-2 / LibcAT-1 are built

`grep -rn "Libsystem-2\|LibcAT-1" src/rbuild-1/*.sh` turns up two different
things, not one build script:

- `src/rbuild-1/host-fixes.sh` (~line 539) patches
  `src/Libsystem-2/Makefile.postamble`'s `ofileList` path as part of a much
  larger sequence of guest environment fixes.
- `src/rbuild-1/summarize-retry.sh` lists `Libsystem-2` alongside `Libc-1`,
  `cc-1`, `cctools-2`, `objc4-1`, `bootstrap_cmds-1`, `system_cmds-2` as one
  of the seed packages built by the **`rbuild bootstrap`** pipeline
  (`src/rbuild-1/rbuild-bootstrap.sh`), which runs entirely inside the guest
  against `/build/source/src/...` and drives the whole stage-0 bootstrap via
  `rbuild bootstrap BootstrapManifest /build/repo /build/repo`.

That pipeline is a **native, host-arch (ppc) whole-OS bootstrap** of ~dozens
of packages via a C89 reimplementation of `darwin-buildpackage`/
`darwin-buildall` (`src/rbuild-1`, producing `.apk` packages) — it is not a
single reusable per-framework command, and is far heavier than this task
needs. It is not what Tasks 12-14 should invoke to build three Foundation
`.m` files.

The actually reusable model, and the one this probe follows, is the
lighter per-module harness pattern already used and documented for driver
builds (see `docs/drivers/drvVGA-baseline-build.md`, `vm/build-i386-vga.sh`):
sync a subtree to the guest with `pscp`, then invoke `cc`/`gnumake` directly
over `plink`, using connection details from `vm/vm.conf` (gitignored;
`vm/vm.conf.example` documents the format — `Host`, `User`, `Password`,
`RemoteRoot=/build/source`, `Plink=plink.exe`, `Pscp=pscp.exe`). This probe
used that same connection info and the PuTTY tools directly (no repo script
wraps a single-file `cc -c` invocation, since none existed before this task).

## Guest image and compiler

- Guest reachable at `10.10.0.241` (hecnet/VMnet8), reached via
  `"C:\Program Files\PuTTY\plink.exe"` / `pscp.exe`, credentials from
  `vm/vm.conf` (root / see `vm.conf`, not reproduced here).
- `uname -a`: `Rhapsody rhap 5.6 Kernel Release 5.6: Tue Aug 8 18:54:21 PDT
  2000; root(rcbuilder):Objects/kernel-190.1.obj~4/RELEASE_PPC ... Power
  Macintosh` — the guest is a **native PowerPC** Rhapsody/Mac OS X Server 1.x
  install; i386 output is produced by cross-compiling with `-arch i386`,
  exactly as the existing driver builds already do (`/usr/libexec/i386`
  exists alongside `/usr/libexec/ppc`).
- `cc -v`: `Apple Computer, Inc. version cc-783.1, based on gcc version
  2.7.2.1` (reading specs from `/usr/libexec/ppc/2.7.2.1/specs` for the
  native arch; `-arch i386` selects the i386 backend from the same
  driver-front-end `cc`).
- Target architecture for Foundation, per
  `docs/superpowers/plans/2026-07-26-foundation-i386-reconstruction.md`, is
  **i386** (the reference binary used throughout that plan is the thin i386
  slice of the shipped fat `Foundation` framework).

## What was actually done

1. `/build/source/src/Kits/Foundation` already existed on the guest from a
   prior/other session. To avoid overwriting shared guest state other agents
   may depend on (per this repo's CLAUDE.md caution about concurrent
   debugging sessions), this probe did **not** touch that directory. Instead
   it copied this worktree's `src/Kits/Foundation` to a brand-new,
   non-colliding path:

   ```bash
   "/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST \
     "mkdir -p /build/source/src/Kits/Foundation-task1-probe"
   "/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" src/Kits/Foundation \
     root@$HOST:/build/source/src/Kits/Foundation-task1-probe
   ```

   (`pscp -r DIR dest` nests the source directory one level under `dest`, so
   the sources land at
   `/build/source/src/Kits/Foundation-task1-probe/Foundation/*`.)

2. Located the ObjC runtime headers `NSObjCRuntime.h` needs
   (`#import <objc/objc.h>`, `<objc/zone.h>`): not under `/usr/include`, but
   under `/System/Library/Frameworks/System.framework/Headers/objc/` — i.e.
   the brief's guessed `-I/System/Library/Frameworks/System.framework/Headers`
   was correct.

3. Because every Foundation header imports with the angle-bracket framework
   form `#import <Foundation/NSWhatever.h>`, the include path must point at
   the **parent** of the directory named `Foundation`, not at `Foundation`
   itself. `-I.` (the brief's placeholder) does not work; `-I..` does, given
   the compile runs with cwd inside the `Foundation` subdirectory.

## The exact working command line

Run from inside the synced `Foundation` directory on the guest
(`/build/source/src/Kits/Foundation-task1-probe/Foundation` for this probe;
Tasks 12-14 will run it from wherever `src/Kits/Foundation` actually lands
on the guest, e.g. `/build/source/src/Kits/Foundation`):

```bash
cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/NSGeometry.o NSGeometry.m
```

Output:

```
NSGeometry.m:39: warning: incomplete implementation of class `NSValue'
NSGeometry.m:39: warning: method definition for `-objCType' not found
NSGeometry.m:39: warning: method definition for `-getValue:' not found
NSGeometry.m:39: warning: incomplete implementation of class `NSValue'
NSGeometry.m:39: warning: method definition for `-copyWithZone:' not found
NSGeometry.m:39: warning: class `NSValue' does not fully implement the `NSCopying' protocol
NSGeometry.m:39: warning: incomplete implementation of class `NSValue'
NSGeometry.m:39: warning: method definition for `-initWithCoder:' not found
NSGeometry.m:39: warning: method definition for `-encodeWithCoder:' not found
NSGeometry.m:39: warning: class `NSValue' does not fully implement the `NSCoding' protocol
NSGeometry.m:70: warning: incomplete implementation of class `NSCoder'
NSGeometry.m:70: warning: method definition for `-versionForClassName:' not found
NSGeometry.m:70: warning: method definition for `-decodeDataObject' not found
NSGeometry.m:70: warning: method definition for `-decodeValueOfObjCType:at:' not found
NSGeometry.m:70: warning: method definition for `-encodeDataObject:' not found
NSGeometry.m:70: warning: method definition for `-encodeValueOfObjCType:at:' not found
EXIT=0
```

`/tmp/NSGeometry.o`: 4,324 bytes, `Mach-O object i386`.

All warnings are expected consequences of the stub's incomplete method
bodies (declared-but-undefined methods from the real headers) — not errors,
and not something this task should or does fix.

## Sanity check: the other two Task 12-14 modules

The same command form (only the filename changed) was also run against
`NSRange.m` and `NSDecimal.m` — the other two modules Tasks 12-14 will
reconstruct — as extra confidence that the invocation generalizes, not
because the brief required it:

```bash
cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/NSRange.o NSRange.m    # EXIT=0
cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/NSDecimal.o NSDecimal.m  # EXIT=0
```

`/tmp/NSRange.o`: 2,688 bytes, Mach-O object i386.
`/tmp/NSDecimal.o`: 768 bytes, Mach-O object i386.

## What Tasks 12-14 need to know

- **Command form** (generalizes to any Foundation `.m`, run with cwd inside
  the Foundation source directory on the guest):

  ```bash
  cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o <OUT>.o <MODULE>.m
  ```

- **`-I..` is load-bearing.** It only works because the source directory on
  the guest is literally named `Foundation` and every header uses
  `#import <Foundation/Header.h>`. If Tasks 12-14 sync sources to a
  differently-named directory, adjust `-I..` (or add an explicit
  `-IPARENT_OF_Foundation`) accordingly — don't assume `-I.` or `-I..` blind.
- **`/build/source/src/Kits/Foundation` already exists on the guest**, seeded
  by an earlier/other session. This probe deliberately did not inspect,
  diff, or overwrite it — it used an isolated `Foundation-task1-probe`
  sibling instead, which it deleted afterward, along with the three `/tmp`
  `.o` files, leaving the guest exactly as found (`AppKit`, `Foundation`,
  `SoundKit` under `/build/source/src/Kits`). **Before Tasks 12-14 write
  their reconstructed `.m` files there, they should check what's already on
  the guest at that path** — it may be stale, may be a different commit, or
  may already hold in-progress work from another session. Do not assume it
  matches this worktree without checking.
- **No linking was attempted or is implied by this result.** The stub
  compiles to a relocatable `.o` only because nothing it declares is
  referenced from outside the translation unit; it does not prove any two
  Foundation `.m` files link together, nor that a `Foundation` framework
  binary can be produced. That question is out of scope for this gate.
- **This is a probe copy, not a build integration.** `src/Kits/Foundation`
  is still in no `Makefile`/`Manifest`/build script in this repo (untouched,
  per this task's constraint). Tasks 12-14 (or whichever task wires
  Foundation into the real build) still need to decide how the framework's
  own `Makefile`/`Makefile.preamble` (`PROJECT_TYPE = Framework`,
  `MAKEFILE = framework.make`) fits in, or whether they'll keep using direct
  `cc -c` invocations like this one for the three target modules only.
- **Guest is shared.** Other agents may be using the same VM concurrently
  (this session found `who` reporting 3 logged-in sessions and load average
  ~3.5 before starting). Follow the same isolation discipline used here:
  never write to `/build/source/src/Kits/Foundation` without checking its
  current contents first, and clean up any temp/probe paths afterward.
