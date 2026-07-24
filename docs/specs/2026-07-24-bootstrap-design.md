# From-source build bootstrap design (breaking the seed chicken-and-egg)

## Problem

`rbuild buildpackage` builds every project inside a fresh `BUILDROOT` chroot
that `builder_makeroot()` populates by extracting the `build-base` dependency
set — `cc, cctools, gnumake, pb-makefiles, coreosmakefiles, libsystem,
libc-hdrs, kernel-hdrs, architecture-hdrs, csu, objc4-hdrs, files, awk, grep,
gnutar, zsh, tcsh, {file,text,shell,developer,basic,bootstrap,system}-cmds` —
as `.apk`s pulled from the repository (`src/rbuild-1/builder.c:401`,
`basedeps[]`). Those packages are themselves Manifest projects built by rbuild.
With an empty repository `builder_makeroot()` fails on the first project with
"unable to find dependency," so nothing can ever be built. Today this is papered
over by seeding the repository from Apple's released `.deb`/`.apk` set.

Goal: produce the initial build-base `.apk` set **from RhapsodiOS source**, with
no pre-built package repository, so the whole system can then build itself.

## Constraints and decisions

- **Host is a running Rhapsody DR2 / Mac OS X Server 1.x guest** with Apple's
  native toolchain already installed (cc, cctools, make, tar/gzip, libsystem,
  system headers, and the pb_makefiles / CoreOSMakefiles / project_makefiles
  frameworks). We are bootstrapping the **package repository**, not the
  toolchain.
- **Seed is built from source**, not harvested from host binaries. The stage-0
  build compiles the build-base projects from the RhapsodiOS source tree using
  the host toolchain.
- **Stage-0 bypasses the chroot.** Because the host already provides every tool
  and framework, the seed projects can build directly against the host root in
  **any order**; their real inter-dependencies are exercised and validated only
  in stage 1.
- **New `rbuild bootstrap` subcommand** drives stage 0, reusing the existing
  `buildall` manifest loop and "already have" skip logic.
- **No new external dependencies** — the same runtime tools rbuild already
  requires (`tar`, `gzip`, `make`, `rsync`, `cp`, `rm`, `mkdir`). `apk` and
  `chroot` are not needed in stage 0.

## Staged bootstrap model

```
Stage 0  rbuild bootstrap BootstrapManifest <repo> <repo>
         native build (no makeroot, no chroot) of the build-base closure;
         seed .apks written into <repo>

Stage 1  rbuild buildall Manifest <repo> <built>
         chroot-builds the whole system from the seed, rebuilding
         build-base self-hosted

Stage 2  rbuild buildall Manifest <built> <built2>   (reseed from stage 1)
         rebuild; compare build-base apks stage1 vs stage2 for
         self-consistency (reproducibility)
```

Stage 1 and stage 2 use the existing `buildall` path unchanged. Only stage 0 is
new.

## Component: `rbuild bootstrap` subcommand

`rbuild bootstrap <srclist> <repository> <dstdir>` — same argument shape as
`buildall`. It iterates the manifest exactly like `cmd_buildall`
(`src/rbuild-1/main.c:57`): scan each project, skip if an `.apk` already exists
in `<dstdir>`, otherwise build. The only difference is that it invokes a
**native** build path.

A `native` flag threads into `builder_build()` and gates four points; everything
else — source rsync into `SRCROOT`, `installhdrs`/`install` to
`HDRROOT`/`DSTROOT`, object harvest, and `.apk` packaging — is shared with the
normal path, so stage-0 apks are the same artifacts rbuild always emits
(`<name>.apk`, `<name>-hdrs.apk`, `<name>-obj.apk`).

1. **Skip `builder_makeroot()`** — no dependency resolution, no `.apk`
   extraction. An empty repository is expected and fine.
2. **Skip `builder_chrootparams()`** — build against unprefixed host absolute
   paths (the host root serves as `BUILDROOT`).
3. **`builder_buildcmd()` drops the `chroot <BUILDROOT>` prefix** — runs
   `make -w -C <SRCROOT> <flags> <target>` directly on the host, with
   `DSTROOT`/`OBJROOT`/etc. pointing at the unprefixed host build paths.
4. **`builder_harvest_objects()`** runs its object copy as a plain `cp` instead
   of `chroot <BUILDROOT> cp` (`src/rbuild-1/builder.c:833`).

The build/header/object roots still live under `BUILDIT_DIR` (default
`/private/tmp/roots`), so stage-0 output does not pollute the host system — the
build is isolated by path, just not by chroot.

`buildpackage` and `buildall` are unchanged; the native path is reachable only
through `bootstrap`.

## Component: `src/BootstrapManifest`

A new manifest in the same three-column format as `src/Manifest`
(`dir <project> <target>`), listing the build-base closure. rbuild auto-emits
`-hdrs` apks for every project it builds, so only source projects are listed;
the `-hdrs` build-base members (`libc-hdrs`, `kernel-hdrs`, `architecture-hdrs`,
`objc4-hdrs`) fall out of the `-hdrs` outputs of `Libc-1`, `kernel-7`,
`architecture-1`, `objc4-1`. Heavy projects use a headers-only target where only
their headers are needed.

```
#       Project[-Version]     Target
#------ --------------------- -------
dir     CoreOSMakefiles-1     all
dir     pb_makefiles-1        all
dir     project_makefiles-1   all
dir     cc-1                  all
dir     cctools-2             all
dir     gnumake-1             all
dir     gnutar-1              all
dir     awk-1                 all
dir     grep-1                all
dir     Csu-1                 all
dir     objc4-1               all
dir     Libc-1                all
dir     Libsystem-2           all
dir     architecture-1        all
dir     kernel-7              headers
dir     files-5               all
dir     basic_cmds-1          all
dir     bootstrap_cmds-1      all
dir     system_cmds-2         all
dir     shell_cmds-2          all
dir     file_cmds-1           all
dir     text_cmds-1           all
dir     developer_cmds-1      all
dir     zsh-1                 all
dir     tcsh-1                all
```

- The compiler seed is `cc-1` (not `cc-791`).
- `kernel-7` uses `headers` so stage 0 emits `kernel-hdrs.apk` without building
  the full kernel.
- Ordering is irrelevant in stage 0 (host provides everything); the file is
  ordered roughly framework → toolchain → libs → commands only for readability.

## Risks and mitigations

- **Host drift.** A native build against host `/` can pick up host headers/libs
  that differ from our source-tree versions, yielding a subtly inconsistent
  seed. Mitigation is structural: stage 1 rebuilds everything in clean chroots
  seeded **only** by stage-0 apks, and stage 2 confirms reproducibility. Drift
  surfaces as a stage-1 build failure or a stage1≠stage2 diff — never a silent
  bad seed.
- **Self-referential seed projects** (e.g. `Libsystem-2` needing newer `Libc-1`
  headers than the host ships) are exactly the case validated by the stage-1
  chroot rebuild.
- **Manifest completeness.** If a build-base member is missing from
  `BootstrapManifest`, stage 1 fails loudly at `makeroot` with "unable to find
  dependency" naming the missing package — a clear, non-silent signal to add it.

## Testing (goal-driven ladder)

1. **Unit:** `bootstrap` argument parsing and dispatch; `native`-flag gating in
   `builder_build`/`builder_buildcmd` produces a make command with no `chroot`
   prefix and unprefixed roots (assert on the command trace, mirroring the
   existing `make trace-test` style).
2. **Dry-run:** `rbuild -n bootstrap BootstrapManifest <repo> <repo>` on the
   host prints the expected per-project native `make` command lines and no
   dependency-resolution/makeroot output.
3. **Stage 0 end-to-end (on host):** `rbuild bootstrap` produces an `.apk` for
   every project in `BootstrapManifest`, covering the full `basedeps[]` closure.
4. **Stage 1:** `rbuild buildall Manifest <repo> <built>` completes `makeroot`
   for the first project using only stage-0 apks (proves the seed satisfies
   `build-base`), then builds the tree.
5. **Stage 2 self-consistency:** reseed from stage-1 output and rebuild;
   build-base apks from stage 1 and stage 2 match.

## Documentation

- This spec: `docs/specs/2026-07-24-bootstrap-design.md`.
- `README.md` "Pre-requisites": replace the "Download the released set of
  packages from the GitHub releases page…" step with the from-source
  stage-0/1/2 bootstrap procedure (`rbuild bootstrap` → `rbuild buildall` →
  optional self-consistency rebuild).

## Out of scope

- Harvesting seed packages from host binaries (rejected in favor of
  from-source).
- Clean-room / cross-compilation from a non-Rhapsody host.
- The host-side Python image builder (`vm/imgbuild/`) — separate spec
  (`docs/specs/2026-07-24-image-builder-design.md`); it consumes packages, it
  does not produce the seed.
