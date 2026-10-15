# Kernel Samurai i386 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and boot both `RELEASE_I386` and `DEBUG_I386` kernels using the in-tree Samurai and hand-maintained Ninja manifests.

**Architecture:** Keep `doconf`/`config` as the configuration authority, with Samurai scheduling preparation, generated files, compilation, and linking. Two entry manifests share rules through `include` and configuration scopes through `subninja`, with separate writable outputs. Validate the maintained graph against historical configuration output before compilation.

**Tech Stack:** In-tree Samurai, Ninja language supported by that Samurai, native Rhapsody i386 compiler/linker/MIG, `/bin/sh`, `/bin/csh`, awk, existing Make build tools for baselines and external prerequisites, QEMU for acceptance.

**Spec:** [2026-10-15-kernel-samurai-design.md](../specs/2026-10-15-kernel-samurai-design.md)

## Global Constraints

- The build runs natively in an i386 Rhapsody guest on a case-sensitive filesystem.
- Samurai comes from `src/Developer/Commands/samurai-1`.
- No C build generator or generated Ninja manifests are introduced.
- There is no separate Make preparation command for the kernel.
- Non-kernel project sources and build rules remain unchanged.
- The existing kernel Makefiles remain usable as a fallback and comparison baseline.
- `build.ninja` selects `RELEASE_I386`; `build-debug.ninja` selects `DEBUG_I386`.
- Outputs are `BUILD.ninja/RELEASE_I386` and `BUILD.ninja/DEBUG_I386`.
- Both configurations retain `-g -O3 -fno-omit-frame-pointer` and their actual historical feature selections.
- Retain `_start`, text address `0x00100000`, link-edit address `0x00780000`, and the historical `strip -x` step.
- Unsupported local configuration overrides fail explicitly; they never silently change a fixed graph.
- PPC, PROFILE, custom configurations, cross-compilation, universal kernels, header installation, packaging, and automatic disk-image creation are outside this milestone.
- Boot only copies or snapshots of `vm/rhap-i386-bootstrapped-v2.img`, following AGENTS.md guest ownership and shutdown rules.
- Commit messages start with `kernel:`, are short and descriptive, and contain no added metadata.

## Review Focus

1. A local override added after a successful build must fail before any kernel-producing command (Tasks 2 and 5).
2. Deleting one output of a multi-output generator must rebuild it even when sibling outputs remain; files suppressed by MIG must not be declared as real outputs (Tasks 2 and 3).
3. Relative dependencies emitted from an object or MIG subdirectory must resolve correctly from Samurai's invocation directory (Task 3).
4. A failed generator or validator must not leave a stamp that permits stale compilation on the next invocation (Tasks 2, 3, and 5).
5. Library or link-recipe changes must refresh version information and relink once, without release/debug interference or a perpetual rebuild (Tasks 4 and 6).

## File map and execution conventions

All paths below are repository-relative. Guest commands run from the isolated
checkout's `src/kernel-7` unless another working directory is stated. Host
commands run from the isolated checkout root. At execution time, use the
using-git-worktrees skill to obtain an isolated checkout; do not mix this
work with the existing AppKit and other uncommitted changes.

| File | Responsibility |
| --- | --- |
| `src/kernel-7/conf/MASTER.i386` | Add the missing `libdriver_g` mapping |
| `src/kernel-7/build.ninja`, `build-debug.ninja` | Select configuration, top-level log directory and default target |
| `src/kernel-7/ninja/common.ninja` | Shared tool bindings and compile rules |
| `src/kernel-7/ninja/i386.ninja` | Shared graph composition, i386 settings, libc exceptions, assembly offsets |
| `src/kernel-7/ninja/release.ninja`, `debug.ninja` | Configuration bindings and source-selection differences |
| `src/kernel-7/ninja/config.ninja` | Configuration, local-override check, and validation dependencies |
| `src/kernel-7/ninja/mig.ninja` | Actual MIG outputs and their compilation edges |
| `src/kernel-7/ninja/sources.ninja` | Shared source-to-object edges |
| `src/kernel-7/ninja/kernel.ninja` | Version, ordered link, and strip edges |
| `src/kernel-7/ninja/configure.sh` | Run source-tree doconf, verify required outputs, manage preparation success |
| `src/kernel-7/ninja/check-config.sh`, `check-config.awk` | Compare historical configuration with expanded Samurai commands |
| `src/kernel-7/ninja/depfile.awk` | Only if native depfiles require normalization; no speculative implementation |
| `src/kernel-7/ninja/mig.sh` | Only multi-command MIG recipes that need a shell helper |
| `src/kernel-7/ninja/tests/config.sh` | Configuration, override, and comparison regression checks |
| `src/kernel-7/ninja/tests/build.sh` | Native generated-file, object, link, and incremental checks |
| `src/kernel-7/ninja/README.md` | Commands, prerequisites, debug library staging, limits and maintenance |
| `src/kernel-7/.gitignore` | Ignore `/BUILD.ninja/` only |
| `docs/build/kernel-samurai-validation.md` | Baseline inventory and measured acceptance evidence |

Reuse `vm/rhap-remote.ps1`, the SSH procedures in `vm/README.md`, and existing
image inspection tools where appropriate. Inspect their configured target
before use: the saved build-guest configuration must not redirect this work
to another agent's guest. Do not modify shared VM configuration. Session
scripts, disk copies, raw logs, and binary evidence belong under a unique
`vm/work/kernel-samurai-<session>/` directory, not in source control.

Tests use `/bin/sh` and native utilities, with no Python or modern compiler
dependency inside the guest. Define these test entry points:

```text
/bin/sh ninja/tests/config.sh SUITE WORKDIR
  SUITE = selection | prepare | compare
/bin/sh ninja/tests/build.sh SUITE WORKDIR
  SUITE = objects | link | incremental | concurrent
```

`WORKDIR` is an absolute, initially nonexistent scratch directory. Each
invocation creates and owns its scratch copy and writes logs there; it
never mutates the working checkout or installed library inputs. Tests may
copy libraries into a private staging directory for mutation cases, changing
the scratch historical `LIBDRIVER_SOURCE`/`LIBOBJC_SOURCE`/`LIBPEXPERT_SOURCE`
bindings and scratch Ninja library paths together before configuring.
Suites obtain their own generated historical configuration references;
they do not depend on a previous suite's scratch directory or saved logs. Each
suite prints `PASS: <suite>` only after all assertions succeed and exits
nonzero on failure. `SAMU` selects the executable for tests, defaulting to
`samu`. Sleep across the guest filesystem's timestamp resolution before
mutation tests; do not infer rebuilds solely from same-second mtimes.

## Task 1: Establish native release/debug Make baselines

**Files:** Modify `src/kernel-7/conf/MASTER.i386`. Create
`src/kernel-7/ninja/tests/config.sh`, `src/kernel-7/ninja/README.md`, and
`docs/build/kernel-samurai-validation.md`.

**Interfaces:** The `selection` suite configures both variants in private
directories using source-tree doconf and installed config. The evidence
document records prerequisite paths, compiler/MIG versions, selected
libraries, generated-file inventory, source mappings, effective flags,
ordered link inputs, and locations/hashes of raw build evidence.

- [ ] **1. Create the isolated build guest and record prerequisites.** Use a uniquely named guest and disk copy/snapshot, reserve unused SSH/QMP/monitor ports, wait for an `SSH-` banner, and sync the isolated source revision. Verify native `arch` is i386 and exercise the in-tree Samurai port tests. Record actual tool paths and versions; existing docs are guidance, not proof of the current guest state.
- [ ] **2. Write and run the failing configuration-selection test.** From `conf`, invoke `/bin/csh tools/doconf/doconf.csh -c -cpu i386 -d <absolute-private-root> RELEASE DEBUG`. Assert the generated RELEASE Makefile selects `LIBDRIVER=libDriver_kern.o`, DEBUG selects `LIBDRIVER=libDriver_kern_g.o`, both select the historical optimization flags, and DEBUG's feature headers contain its extra options. Run `/bin/sh ninja/tests/config.sh selection /tmp/kernel-samu-selection-before`; expect the missing DEBUG mapping assertion to fail.
- [ ] **3. Add the kernel-side mapping and rerun.** Add `makeoptions LIBDRIVER = "libDriver_kern_g.o" # <libdriver_g>` in MASTER.i386's existing makeoptions section, matching local formatting. Run the suite with a new scratch directory; expect `PASS: selection`. Do not change the DEBUG feature set or release library mapping.
- [ ] **4. Prepare the debug library with existing DriverKit rules.** In `src/driverkit-3/libDriver`, run `gnumake MACHINE=i386 RC_ARCHS=i386 kerndebug OBJROOT=<private-absolute-root> SYMROOT=<private-absolute-root>`. Verify `syms/libDriveri386_kern_g.o`, then stage it under the kernel's expected `libDriver_kern_g.o` name in this isolated guest. Record the exact successful command, environment, hash, and staging path in README/evidence. Missing prerequisites are errors, not grounds to substitute the release library.
- [ ] **5. Build both Make baselines.** Create the private baseline root. From `conf`, first run `gnumake tools OBJROOT=<absolute-baseline-root> SYMROOT=<absolute-baseline-root>` to install the historical kernel scripts there, then `gnumake ARCH=I386 TYPE=RELEASE mach_kernel.kernel OBJROOT=<absolute-baseline-root> SYMROOT=<absolute-baseline-root>` and the corresponding DEBUG command. Preserve full logs and generated Makefiles. Inventory configuration outputs and actual MIG outputs, capture representative native depfiles, and record the complete source/flag/link comparison inputs. Fix only the approved mapping here; report other baseline defects with evidence before expanding scope.
- [ ] **6. Commit the baseline deliverable.** Verify both baseline artifacts exist and the selection suite passes. Commit only this task's source test, mapping, and documentation with `kernel: fix i386 debug library selection`.

## Task 2: Add automatic configuration and isolated manifest entry points

**Files:** Create both entry manifests, `common.ninja`, `i386.ninja`,
`release.ninja`, `debug.ninja`, `config.ninja`, `configure.sh`, and
`src/kernel-7/.gitignore`. Extend `ninja/tests/config.sh` and README.

**Interfaces:** Entry scope defines `builddir` and `outdir` as the selected
`BUILD.ninja/<TYPE>_I386`; configuration scope defines `config = RELEASE`
or `DEBUG` and `manifest = build.ninja` or `build-debug.ninja`.
`configure.sh check CONFIG OUTROOT` checks overrides without writing build
outputs; `configure.sh prepare CONFIG OUTROOT` runs configuration and exits
zero only after all declared required outputs exist, publishing
`OUTROOT/<CONFIG>_I386/prepared` as its success stamp. Both run from the
kernel source root; `OUTROOT` is `BUILD.ninja` converted to an absolute
path before doconf is invoked. The graph exposes a `configured` phony target.

- [ ] **1. Write and run failing preparation tests.** Add the `prepare` suite: first configuration succeeds; a repeat does not rerun doconf; deleting `meta_features.h` regenerates it; missing `config` causes nonzero exit without a success stamp; fixing the tool permits retry. Adding `MASTER.local` after a successful invocation must fail before preparation. Run the suite and confirm failure from the absent helper/manifests.
- [ ] **2. Implement native preparation.** Use the source-tree doconf through `/bin/csh` from `conf`; respect `CONFIG_DIR` and preserve its historical default. Check the actual exit status and the required output inventory from Task 1. Remove an old preparation stamp before starting and publish success only after output checks. `check` covers `MASTER.local`, `MASTER.i386.local`, and configuration-specific `files.<IDENT>` overrides found through the existing config lookup rules; derive the relevant IDENT from the supported baseline. Reject unsupported configurations.
- [ ] **3. Declare configuration outputs and dependencies.** Include MASTER, files, templates, scripts, and the selected config executable. Declare generated headers/C files/symlinks required by the baseline as outputs, so missing individual outputs trigger preparation. Make the always-run read-only override check an order-only prerequisite of preparation and all downstream kernel work; it must not dirty compiled outputs. Generated headers still need real dependency tracking for content changes.
- [ ] **4. Wire scopes and output isolation.** Top-level entry files `include ninja/common.ninja` and `subninja` the selected configuration; configuration fragments include i386 composition. Keep logs, stamps, and temporary paths configuration-specific. Temporarily default to `configured` until Task 4 adds the kernel. Add only `/BUILD.ninja/` to the kernel-local ignore file.
- [ ] **5. Run native verification and commit.** Run `/bin/sh ninja/tests/config.sh prepare /tmp/kernel-samu-prepare-after`, then `samu -f build.ninja configured` and `samu -f build-debug.ninja configured`. Check actual generated paths and independent logs. Commit with `kernel: configure i386 Samurai builds`.

## Task 3: Build generated files and all kernel objects

**Files:** Create `ninja/sources.ninja`, `ninja/mig.ninja`, and
`ninja/tests/build.sh`. Extend `common.ninja`, `i386.ninja`, and both
configuration fragments. Add `mig.sh` and `depfile.awk` only where the
native recipes/depfile captures require them.

**Interfaces:** Each configuration supplies complete compile flags and
explicit ordered variables `kernel_objects`, `libc_objects`, and
`mach_user_objects`. `kernel_objects` reflects historical OBJS plus special
objects such as `subr_prof.o` and `ioconf.o`, without double inclusion.
The graph exposes `objects` and `generated` phony targets. Compile commands
execute in the configuration directory while graph paths remain relative
to the kernel root. Optional `mig.sh MODE OUTDIR SOURCE_ROOT` runs only the
named multi-command recipe (`mach` or `host`), with absolute directory
arguments. Optional depfile normalization uses
`awk -v target=GRAPH_OUTPUT -v base=COMMAND_CWD -f ninja/depfile.awk RAW_D`.

- [ ] **1. Write the failing object/generator suite.** Add `objects`: build both configurations from empty output directories with `-j 4`; assert every selected object exists, every declared generated output exists, and source mappings match the baseline inventory. Delete `mach/mach_interface.h` while keeping its sibling outputs; assert its producer runs once and recreates it. Run the suite and confirm absent object targets fail.
- [ ] **2. Write hand-maintained source edges.** Transcribe the baseline selections and mappings, sharing common edges in sources.ninja and placing only differences in the variant fragments. Preserve `cc -static -nostdinc -nostdlib -traditional-cpp`, include order, defines, language handling, and per-file exceptions. Do not use source globs or derive a Ninja manifest at build time. Retain basename mappings unless a real collision demands an explicit path; reject duplicate outputs.
- [ ] **3. Implement generated inputs and special compile rules.** Declare config-generated C compilation, `genassym.s` to `assym.h`, feature generation where consumed, libc `-O4` rules, and `-O4 -funroll-all-loops` rules exactly as the effective baseline requires. Keep copied/imported inputs explicit. All first-build generated headers precede their consumers.
- [ ] **4. Implement MIG edges from observed outputs.** Cover mach, memory_object, memory_object_default, exc, mach_host, mach_port, mach_debug, kern_server, kern_server_reply, and imported driverServer definitions where selected. Preserve typed/untyped, `KERNEL_SERVER`, `KERNEL_USER`, `SEQNOS`, handler, architecture, and external-name behavior. Treat the mach recipe's repeated output writes as one producer. Do not declare server files suppressed with `-server /dev/null`. Include actual split-user outputs and `mach_kernloader.h`. Preserve the `-DMACH_USER_API -D<routine>=<routine>_EXTERNAL` object rules.
- [ ] **5. Integrate actual depfiles.** Feed verified compiler/MIG dependency output to Samurai. Normalize targets and prerequisites from the command cwd to graph paths only when needed; merge multi-invocation MIG dependency sets without dropping includes, using one accepted depfile target. Keep first-build dependencies explicit. Reject malformed normalization input rather than publishing incomplete dependencies. Test a header under `bsd`, a nested MIG include, deletion of an included generated header, and a forced failure on the second command of a multi-command MIG recipe.
- [ ] **6. Verify recovery and command parity.** Run `/bin/sh ninja/tests/build.sh objects /tmp/kernel-samu-objects-after`. Compare compiler/MIG invocations with Task 1, allowing only output paths and dependency plumbing to differ. Verify a repeat builds no objects and a failed MIG recipe retries successfully after restoring the tool. Commit with `kernel: compile i386 objects with Samurai`.

## Task 4: Link both kernels and preserve incremental version generation

**Files:** Create `ninja/kernel.ninja`. Extend entry manifests,
configuration bindings, `i386.ninja`, `ninja/tests/build.sh`, and README.

**Interfaces:** `link_objects` composes the baseline-ordered inputs from
Task 3 plus explicit external libraries and version object in their exact
positions. `external_libraries` contains the actual DriverKit, Objective-C,
platform-expert, and compiler support library files. Default outputs become
`BUILD.ninja/<TYPE>_I386/mach_kernel`; unstripped output is adjacent.

- [ ] **1. Write and run the failing link suite.** Add `link`: both defaults produce i386 Mach-O kernels; their ordered inputs and flags match the baselines; unstripped symbols include `_start` and the expected kernel exports; missing debug DriverKit fails without substituting release. Run the suite before adding link edges and observe the missing-output failure.
- [ ] **2. Add historical linking and stripping.** Preserve `_start`, `__TEXT 0x00100000`, `__LINKEDIT 0x00780000`, `-segalign 0x1000`, `-force_cpusubtype_ALL`, `-u __muldi3`, library order, and other baseline flags. Locate the actual library selected by `-lcc` in the native toolchain and declare it as a dependency without changing resolution. Use the historical linker, then `strip -x`; avoid unverified `@response` syntax. Keep any `a.out` or temporary link file private to the configuration.
- [ ] **3. Make version generation conditional on relinking inputs.** Run `/bin/sh conf/tools/newvers/newvers.csh` by its resolved source path from the configuration directory with the historical version arguments. Depend on non-version objects, external libraries, version files, script, and manifests carrying the link recipe. Declare consumed version outputs. Keep `vers.o` and kernel outputs out of its input set to avoid cycles. A changed link recipe must trigger new version generation even if no object changed.
- [ ] **4. Verify link behavior and commit.** Run `/bin/sh ninja/tests/build.sh link /tmp/kernel-samu-link-after`. Inspect native `otool -hv`, `otool -l`, and `nm` results against baseline layouts/symbols. Test replacing a private staged library, removing a final kernel, changing a link binding, and repeating each build unchanged. Require one necessary relink followed by no kernel-producing work. Commit with `kernel: link release and debug Samurai kernels`.

## Task 5: Enforce configuration-to-manifest consistency

**Files:** Create `ninja/check-config.sh` and `ninja/check-config.awk`.
Extend `config.ninja`, object/generator prerequisites, and
`ninja/tests/config.sh`.

**Interfaces:** `check-config.sh CONFIG OUTDIR MANIFEST` runs from the
kernel root, reads `OUTDIR/Makefile`, captures `samu -f MANIFEST -t commands`
for that configuration's final kernel, and uses check-config.awk to compare
them. Its success output is `OUTDIR/validated`; it exits nonzero on any
unsupported relevant syntax or mismatch. Command capture does not execute
the captured commands or regenerate manifests. Test override `SAMU` must
be passed explicitly by the validation edge when needed.

- [ ] **1. Write the failing comparison suite.** Add `compare`: accept both unmodified graphs; reject one removed source edge, one extra object, swapped link inputs, an altered configuration define, changed optimization flag, and release DriverKit selected for DEBUG. Also mutate MASTER/files in scratch copies and add a local override after prior success. Assert nonzero exit, a diagnostic naming the configuration and difference, and no compiler/linker command executed. Run before implementing the checker and observe failure.
- [ ] **2. Implement the bounded reference reader.** Parse the known generated assignments and source/rule forms for `IDENT`, source/object groups, configuration makeoptions, compile settings, and link composition. Resolve only the variable references and suffix substitutions required by those forms; reject unknown relevant constructs. Canonicalize source/output roots and known dependency-only additions while preserving flag ordering, repeated options, source identity, and link order. Compare actual expanded Samurai compile/link commands, not a separately maintained expected-source list. Unknown commands that could compile/link inputs are errors, not silently skipped lines.
- [ ] **3. Gate the graph.** Make validation depend on generated configuration output, all graph fragments, and checker scripts. It must precede every compilation, downstream kernel-source generator, and link, without depending on compiled objects itself. Configuration preparation precedes validation and must not depend on it. Delete stale validation success before checking; publish success only after every comparison passes. `-t commands` inspection is read-only and must not recursively execute the validation edge.
- [ ] **4. Verify mismatch recovery and commit.** Run `/bin/sh ninja/tests/config.sh compare /tmp/kernel-samu-compare-after`, including forced checker failure followed by a successful retry. Restore scratch inputs and ensure a valid build resumes. Re-run both normal builds and no-op checks with the gate enabled. Commit with `kernel: validate Samurai configuration parity`.

## Task 6: Complete incremental and concurrent build acceptance

**Files:** Extend `ninja/tests/build.sh`, README, and
`docs/build/kernel-samurai-validation.md`. Fix only graph/helper defects
demonstrated by these checks.

**Interfaces:** `incremental` exercises dependency invalidation for both
configurations in scratch trees. `concurrent` starts release and debug
Samurai processes against one scratch source tree and checks output/log
isolation. Both retain native command logs and artifact evidence.

- [ ] **1. Add the acceptance assertions.** `incremental` must compare logs and artifact changes after a source change, ordinary header change, nested MIG include change, missing individual generated output, external-library replacement, and link-binding change. Preserve an unrelated object as a negative control. Every case must reach a stable second invocation. Include a path containing `..` in the native dependency data and test a missing generated header with an existing `.ninja_deps` file.
- [ ] **2. Add concurrent checks.** Start `samu -j 4 -f build.ninja` and `samu -j 4 -f build-debug.ninja` from an empty shared scratch tree, wait for both exit statuses, and assert separate logs, correct configuration headers, correct selected DriverKit objects, and correct version strings. Cleaning one graph must leave the other graph and the Make baseline intact.
- [ ] **3. Run and repair only demonstrated defects.** Run `/bin/sh ninja/tests/build.sh incremental /tmp/kernel-samu-incremental` and `/bin/sh ninja/tests/build.sh concurrent /tmp/kernel-samu-concurrent`. For failures, retain the reproducer, make the smallest graph/helper correction, and rerun that case plus affected suites. Do not broaden into unrelated kernel or Samurai changes.
- [ ] **4. Record final build evidence and commit.** Capture both full `samu -v` build logs, comparison results, stable repeated builds, artifact hashes, and prerequisite identities. Complete README commands and maintenance instructions for synchronizing manifests with configuration changes. Commit with `kernel: verify Samurai rebuild behavior`.

## Task 7: Boot release and debug artifacts and finish the evidence record

**Files:** Update `docs/build/kernel-samurai-validation.md` and, only if
observed usage requires clarification, `src/kernel-7/ninja/README.md`.
No new VM framework is part of this task.

**Interfaces:** Consume Task 6's verified kernels and their hashes. Produce
a recorded boot result for each configuration, tied to the exact installed
artifact, guest name, disk copy, ports, source revision, and boot log.

- [ ] **1. Prepare two independent boot images.** Copy `vm/rhap-i386-bootstrapped-v2.img` to unique session paths. Boot each owned copy writable to install its kernel via the guest filesystem, preserving the original boot assets and sufficient free space. Verify the installed kernel hash against the fetched artifact. Use the existing SSH transport patterns; do not assume host image-injection tools can grow the kernel inode. Stop each staging guest with `sync; /sbin/reboot`, then verified-owner QMP `quit` at the next kernel start.
- [ ] **2. Boot the release image with snapshot protection.** Assign a distinct `-name` and unused SSH/QMP/monitor ports. Confirm `query-name`, wait for the SSH banner, and capture root mount, userspace startup, login, `uname -a`, and `sysctl kern.version` where available. Match the configuration/build identity to the staged kernel; a stock-kernel boot does not pass.
- [ ] **3. Boot the debug image with the same criteria.** Use its own image, name, and ports. DEBUG must reach userspace with its selected debug kernel/library; do not disable diagnostic options or replace the library to get a passing boot. Investigate and report pre-existing debug failures before proposing scope changes.
- [ ] **4. Run a basic guest smoke test on each.** Create a temporary directory with `mkdir`, write/read a small file, verify contents with `cmp`, run a basic command/process check, and remove only the test directory. Record status and console evidence of any panic or driver-load failure. Stop only the owned guests through QMP after confirming their names.
- [ ] **5. Review and commit the evidence.** Confirm all spec acceptance rows have measured outcomes for both configurations. Record limitations honestly; no boot claim follows merely from a successful link. Run `git diff --check`, review the changed-file list for non-kernel project edits, and commit with `kernel: record Samurai release and debug boots`. Keep large logs/images/binaries under the ignored session directory.

## Coverage and handoff

The test drivers implement the named cases above with real native command
execution. Their core assertions include the following shell checks;
`work` denotes that suite's owned directory, `tree` its scratch kernel root,
and each named log is captured by the corresponding test case:

```sh
# selection: run after doconf has populated $work/config.
grep '^LIBDRIVER=libDriver_kern.o$' "$work/config/RELEASE_I386/Makefile"
grep '^LIBDRIVER=libDriver_kern_g.o$' "$work/config/DEBUG_I386/Makefile"

# prepare: a failed preparation must not publish success.
test ! -f "$tree/BUILD.ninja/DEBUG_I386/prepared"

# objects: deletion recovery must restore an actual MIG output.
test -s "$tree/BUILD.ninja/RELEASE_I386/mach/mach_interface.h"

# link: both products exist; otool/nm checks establish their contents.
test -s "$tree/BUILD.ninja/RELEASE_I386/mach_kernel.sys"
test -s "$tree/BUILD.ninja/RELEASE_I386/mach_kernel"
test -s "$tree/BUILD.ninja/DEBUG_I386/mach_kernel"

# compare: failure names the configuration, and no compile/link ran.
grep 'DEBUG_I386' "$work/mismatch.log"
test ! -s "$work/compiler-linker-invocations"

# incremental: a second invocation preserves kernel-producing log entries.
cmp "$work/kernel-commands.before" "$work/kernel-commands.after"

# concurrent: logs exist independently and version identity is preserved.
test -f "$tree/BUILD.ninja/RELEASE_I386/.ninja_log"
test -f "$tree/BUILD.ninja/DEBUG_I386/.ninja_log"
grep RELEASE_I386 "$tree/BUILD.ninja/RELEASE_I386/vers.c"
grep DEBUG_I386 "$tree/BUILD.ninja/DEBUG_I386/vers.c"
```

For the failure tests, first assert the command's exit status is nonzero;
an absent output alone does not prove the intended failure occurred.
Record compiler/linker invocations with test wrappers around the native
tools, not by guessing from progress descriptions. These wrappers are test
fixtures inside the owned scratch directory and delegate to the real tools.

| Spec requirement | Owning tasks |
| --- | --- |
| Historical toolchain, Make baselines, debug DriverKit mapping/prerequisite | 1 |
| Two entry manifests, include/subninja scoping, output/log isolation | 2, 6 |
| Automatic doconf/config, override rejection, failed preparation recovery | 2, 5 |
| Source selections, MIG, generated headers, special flags, depfiles | 3, 5 |
| Ordered link, explicit libraries, version generation, strip | 4, 5 |
| Configuration mismatch checks and unsupported syntax diagnostics | 5 |
| Clean, incremental, missing-output and concurrent acceptance | 3, 4, 6 |
| Both kernels boot to userspace on isolated images | 7 |
| Usage, prerequisite instructions and measured evidence | 1, 6, 7 |

All task boxes remain unchecked until execution. This plan does not claim
baseline builds, new manifests, tests, or boots have run.

Recommended execution is native in this session: these tasks share one
historical toolchain, configuration inventory, and evolving guest build
state. Retaining that context should reduce duplicated investigation.
Review the whole change independently at the end. Subagent-driven execution
is also available if the user prefers separate implementation/review gates
per task. Wait for plan review and the user's execution-method selection
before starting either workflow.
