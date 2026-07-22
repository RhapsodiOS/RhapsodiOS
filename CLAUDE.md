# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

RhapsodiOS is an open-source reimplementation of Apple's Rhapsody (which became Mac OS X Server 1.0–1.2v3), forked from Apple's Darwin 0.3 release (summer 1999). It targets **ppc** and **i386** and builds best on a case-sensitive filesystem, historically on a Rhapsody DR2 / Mac OS X Server 1.x guest.

All OS project sources live under `src/` — each is a self-contained Apple/NeXT project (kernel, libc, commands, drivers, etc.) with its own `Makefile.preamble` / `pb_makefiles` framework. The repo root adds tooling that did not ship with Darwin: a ninja build orchestrator (`ninja/`), a QEMU dev-VM harness (`vm/`), and a binary-reconstruction toolkit (`tools/binrecon/`).

## Building

The build replaces **only the orchestration layer** — each project still builds with its own NeXT make framework; ninja/samurai (`samu`, vendored in `ninja/samurai/`) decides *what* builds, *in what order*, in parallel. There is **no chroot**: everything installs into one shared `DSTROOT` (default `/tmp/rhapsody/dst`). Runtime packaging is **apk** (Alpine's apk-tools, in `src/apk-tools/`), not `.deb`/dpkg.

```sh
make -C ninja world        # build samu + rhap-build, generate build.ninja, build everything
make -C ninja kernel       # just the kernel
make -C ninja generate     # (re)write ./build.ninja only
samu zlib                  # build one project by directory name (after `generate`)
samu Commands/adv_cmds     # nested project path
```

- `rhap-build` (built from `ninja/*.c`) is the single entry point: `generate` (write `build.ninja`), `build` (regenerate + run samu), `mkapk` (build one `.apk`), `index`, `publish`. See [`ninja/README.md`](ninja/README.md) for all flags/env (`SRCROOT`, `DSTROOT`, `OBJROOT`, `RC_ARCHS`, `APKREPO`, …).
- A directory under `src/` is a **project** if it contains `apk/PKGINFO`. Regenerate `build.ninja` whenever projects or their deps change.
- The native build targets the Rhapsody/Darwin toolchain; on a Windows/other host you can edit and regenerate, but final compiles run on the guest.

## Testing

- **apk integration** (`ninja/tests/*.sh`): run on Darwin/RhapsodiOS after `apk` is built. `export APK=/path/to/apk`, then e.g. `sh ninja/tests/apk-roundtrip.sh`. Exit `0`=pass, `77`=skip (apk not found), other=fail.
- **binrecon** (`tools/binrecon/`, Python): `python -m pytest tools/binrecon/tests` (deps in `tools/binrecon/requirements.txt`; venv at `.venv-binrecon/`). Run one test: `python -m pytest tools/binrecon/tests/test_cli.py::test_help_lists_all_commands`.

## Dev VM and Dev connections (`vm/`)

Windows + QEMU harness for booting a Rhapsody guest and doing remote builds over SSH. Local binaries (`qemu.exe`, `rhapsody.vmdk`, etc.) and machine-specific config are gitignored; scripts/docs are tracked. `start-hecnet.cmd` + `start-vm.cmd` to run; `vm/rhap-vm.ps1 sync` / `build` to sync the tree and run `make world` on a PPC Macintosh on the network. See [`vm/README.md`](vm/README.md). Per §6 below, use a **temporary disk image** when boot-testing so you don't collide with another debugging session.

## Boot Path & Source Provenance

`docs/boot-i386.md`, `docs/boot-ppc.md`, and `docs/boot-source-map.md` trace the loader→kernel→BSD→`/sbin/mach_init`→`rc` path. These docs follow a strict **evidence discipline**: every claim is labeled **Verified** (a named symbol/call/path exists in-tree), **Inferred** (joins verified adjacent facts), or **Research gap** (source absent/config-dependent — stated, never filled with a historical guess). Match this style when editing them: cite `src/...` source anchors and do not assert provenance you cannot ground in the checked-in tree. Design docs and plans live under `docs/superpowers/{specs,plans}/`.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Committing Changes

**Keep commit messages short, human-readable, and descriptive.**

- Always keep the commit messages short, human-readable, and descriptive.
- Start the commit line with whatever subsystem you are working on, e.g. "kernel: ", "boot: ", "AppKit: ", etc.
- Describe what the changes actually do instead of listing the changed files. Keep commit messages as one to two lines.
- Do not add any metadata to commits.

## 6. Debugging

- Make sure to use temporary disk images if testing a boot to isolate testing if another agent is working a different debugging session
