# Samurai builds for release and debug i386 kernels

## Purpose

Build bootable `RELEASE_I386` and `DEBUG_I386` kernels with the in-tree
Samurai tool and hand-maintained Ninja manifests. Preserve the historical
compiler, linker, configuration tools, source selections, and kernel layout.
This is the first kernel build migration milestone, not a replacement for
the whole OS build system.

The user approved two configurations, automatic configuration preparation,
shared manifest fragments, separate output directories, and a kernel-side
fix for the missing i386 debug DriverKit library selection. This document
records that design for review before implementation planning.

## Scope and prerequisites

The build runs natively in an i386 Rhapsody guest on a case-sensitive
filesystem. Samurai comes from `src/Developer/Commands/samurai-1`. The guest
already supplies the historical compiler, assembler, linker, `strip`, MIG,
`config`, `relpath`, shells, and basic text tools, plus installed kernel
headers and external kernel libraries. Building or installing those
prerequisites remains the responsibility of their existing build systems.

Within `src/kernel-7`, Samurai owns configuration preparation, generated
sources and headers, compilation, linking, and the final stripped kernel.
There is no separate Make preparation command for the kernel. Existing
`doconf` and `newvers` scripts are reused from the source tree; installed
copies from a previous kernel build are not required.

The existing kernel Makefiles remain usable as a fallback and comparison
baseline. Non-kernel project sources and build rules remain unchanged.
The new build is opt-in: rbuild and package installation continue to use
their existing paths.

PPC, PROFILE, arbitrary custom configurations, cross-compilation, universal
kernels, header installation, packaging, and automatic disk-image creation
are outside this milestone. No C build generator or generated Ninja
manifests are introduced. Small shell/awk helpers are permitted for
configuration preparation, validation, and existing multi-command recipes;
they must not implement another configuration language or build scheduler.

## Commands and outputs

Run from `src/kernel-7`:

```sh
samu -f build.ninja
samu -f build-debug.ninja
```

| Entry manifest | Configuration | Output directory |
| --- | --- | --- |
| `build.ninja` | `RELEASE_I386` | `BUILD.ninja/RELEASE_I386` |
| `build-debug.ninja` | `DEBUG_I386` | `BUILD.ninja/DEBUG_I386` |

Each directory contains `mach_kernel.sys` with link-time symbols and the
bootable `mach_kernel` produced by the historical `strip -x` step. Objects,
generated headers, MIG outputs, dependency files, version files, temporary
files, and Samurai logs are private to that configuration. Configuration
descriptions under `BUILD.ninja` also have configuration-specific names.

Release and debug may build concurrently without sharing writable outputs.
Neither uses the Make build's `BUILD` directory. Cleanup through Samurai
must be limited to its own declared outputs. Kernel installation into a
guest image is an explicit verification step, not part of the default build.

## Manifest organization

```text
src/kernel-7/
|-- build.ninja
|-- build-debug.ninja
`-- ninja/
    |-- common.ninja
    |-- i386.ninja
    |-- config.ninja
    |-- mig.ninja
    |-- sources.ninja
    |-- release.ninja
    |-- debug.ninja
    `-- kernel.ninja
```

The entry manifests load common rules with `include`, then use `subninja`
for the selected configuration. `release.ninja` and `debug.ninja` establish
their configuration, output paths, flags, and library selections before
including the shared i386 graph. Shared files use `include` so build edges
see those configuration bindings. Each entry declares its kernel as the
default target. Per-entry Samurai `builddir` settings keep logs separate.

| Fragment | Responsibility |
| --- | --- |
| `common.ninja` | Tool commands and shared compile rules |
| `i386.ninja` | i386 flags, special libc rules, assembly offsets, and graph composition |
| `config.ninja` | Run historical configuration tools and validate the result |
| `mig.ninja` | Explicit MIG generation and compilation edges |
| `sources.ninja` | Source-to-object edges shared by release and debug |
| `release.ninja`, `debug.ninja` | Configuration bindings and configuration-specific edges |
| `kernel.ninja` | Version generation, ordered link inputs, link, and strip |

Common source edges are written once. Any source-selection differences are
explicit in the configuration fragments. The ordered object lists are
hand-maintained and checked against the historical configuration output.
No filesystem glob decides what is compiled or linked. Shared rule reuse
does not imply shared object files.

## Historical configuration and manifest consistency

`conf/MASTER`, `conf/MASTER.i386`, `conf/files`, and `conf/files.i386` remain
the configuration authority. The build invokes `doconf -c -cpu i386` for
the selected RELEASE or DEBUG configuration with a Samurai-owned object
root, preserving its invocation of the existing `config` executable.
`doconf` is not passed its option to invoke Make.

The configuration edge declares the generated files required by the
kernel, including configuration headers, generated C files and machine
links where emitted by `config`. The generated Makefile remains an output
of the historical tools and a validation reference; it does not schedule
the Samurai kernel build.

A small validation helper checks the generated configuration against the
selected manifest graph before compilation. It compares the selected
source/object mappings, ordered link inputs, configuration defines, compile
settings, and external library selections. It reads the known output
format of the in-tree configuration tools rather than implementing a
general Make parser. Missing, extra, or reordered inputs and mismatched
settings fail with a diagnostic identifying the configuration and difference.
The checker does not emit or rewrite Ninja manifests.

The validation result depends on the configuration inputs, relevant
manifests, helper, and generated reference files. Compilation requires a
successful validation result. Changes to `MASTER*`, `files*`, or the
historical templates must therefore either validate against the maintained
graph or stop the build before producing a kernel from stale selections.
The output lists themselves must be maintained when configuration changes
alter the generated-file set.

This milestone supports the two checked-in configurations. The historical
tools also discover `MASTER.local`, `MASTER.i386.local`, and other local
configuration extensions. The new entry points must detect and reject
unsupported local overrides with a clear message; they must not silently
combine custom options with a fixed source graph. Detection must cover an
override added after an earlier successful build. This narrowly scoped
check may run on every invocation without making kernel outputs dirty.

## Compilation and generated files

Preserve the commands selected by the current historical build, including:

- C, Objective-C, and assembly compilation with the historical include
  order, feature headers, defines, and architecture flags.
- i386 libc optimization exceptions, including the separate unrolled-loop
  rules.
- MIG typed/untyped modes, kernel-server and kernel-user flags, output
  naming, and generated-source compilation.
- `genassym.c` compilation to assembly and the existing awk extraction of
  `assym.h`.
- Configuration-generated sources, feature headers, and special rules
  required by the selected kernel.

Each generated file has one producer. Multi-output commands declare all
outputs consumed by the graph. Generated headers have explicit first-build
dependencies so parallel compilation cannot run before they exist.

Use the historical tools' dependency output for subsequent header and MIG
include tracking. Verify the actual compiler/MIG depfile format and paths
against the in-tree Samurai parser; do not assume modern GCC options work.
If path or target normalization is needed, keep it in a small native helper
and test it using real tool output. Missing generated files must be
regenerated, even if an associated stamp or another output still exists.

Configuration changes may conservatively rebuild affected configuration
objects. Ordinary source and header changes should rebuild only their
dependents. An unchanged second build runs no configuration generation,
compilation, MIG, version generation, linking, or stripping. The read-only
local-override check is the sole allowed always-run preparation check.

## Release and debug behavior

The configurations retain their historical meanings. Both currently select
`gdb` and therefore use `-g -O3 -fno-omit-frame-pointer`; DEBUG must not be
reinterpreted as an unoptimized build. DEBUG additionally selects options
including `debug`, `xpr_debug`, and `diagnostic`. Generated options and
source selections must match each configuration independently.

The existing i386 DEBUG definition selects `libdriver_g`, but neither the
common MASTER nor MASTER.i386 maps it to `LIBDRIVER`. Add the missing
i386-specific mapping to `libDriver_kern_g.o` in `conf/MASTER.i386`. Keep the
existing release mapping to `libDriver_kern.o`. This is the only planned
change to existing kernel configuration behavior and applies equally to
the Make and Samurai debug builds.

DriverKit already has a `kerndebug` target. For i386 it emits
`libDriveri386_kern_g.o` into its symbol directory; prerequisite preparation
must stage that artifact under the kernel's expected `libDriver_kern_g.o`
name or use the existing library aggregation rules. Do not assume the
normal DriverKit installation supplies this debug artifact. Document and
verify the prerequisite procedure using existing DriverKit rules, without
changing that project. If it is unavailable, the debug build fails clearly
instead of falling back to the release library.

## Linking and version generation

Preserve the historical object order, libc prefix objects, generated MIG
objects, version object, DriverKit/Objective-C/platform-expert inputs,
compiler support library, and any configuration-specific link inputs.
External libraries are explicit dependencies so replacing one triggers a
relink.

Retain the i386 entry point `_start`, text address `0x00100000`, link-edit
address `0x00780000`, segment alignment, CPU subtype handling, and other
effective historical linker flags. Use the historical linker directly.
Do not assume it accepts modern response-file syntax. The final commands
produce `mach_kernel.sys` and then `mach_kernel` through `strip -x`.

Reuse `newvers` in the configuration's build directory. Version generation
depends on the inputs that require a new link, including object/library
changes, version inputs, and link recipe changes; it is not unconditional.
It must not depend on its own `vers.o` or final kernel. Preserve the
configuration name in the version string and keep version state separate
between release and debug.

Build failures propagate as nonzero exits. Helpers must not report success
after a failed configuration, generator, or validation step. Failed or
interrupted generation must not leave a success marker that allows stale
outputs to pass on the next invocation.

## Verification and acceptance

Verification uses the same source revision, installed headers, toolchain,
and external libraries for Make and Samurai. Record those inputs along
with commands, logs, artifact hashes, and observed boot results. Build-time
timestamps and directory strings in `newvers` make whole-kernel byte
identity unsuitable as the sole comparison criterion.

1. **Historical baseline:** Configure and build both Make kernels in
   separate directories, including the approved debug mapping fix. Record
   selected sources, compile settings, ordered link inputs, and libraries.
   Any pre-existing debug build failure is investigated and reported;
   debug acceptance cannot be inferred from release success.
2. **Clean Samurai builds:** From empty Samurai output directories, build
   both configurations with parallel jobs. Compare actual commands and
   selected inputs with their Make baselines. Verify i386 Mach-O output,
   entry point, segment layout, expected symbols, and successful stripping.
3. **Configuration isolation:** Build release and debug concurrently and
   verify that objects, generated files, temporary files, and logs do not
   collide or cross-contaminate the resulting kernels.
4. **Incremental behavior:** Repeat each build unchanged and verify no
   kernel-producing work. Change a representative C source, ordinary
   header, and MIG definition or included definition, and verify dependent
   generation/compilation and relinking. Replace an external library and
   verify relinking. Remove representative generated headers and outputs
   and verify recovery without a clean build.
5. **Configuration mismatch:** In an isolated test tree, change a selected
   source or option without updating its manifests and verify a useful
   pre-compilation failure. Test introduction of a local override after a
   successful build. Restore the inputs and verify recovery.
6. **Boot both kernels:** Stage each verified Samurai artifact into its
   own temporary copy or snapshot of `vm/rhap-i386-bootstrapped-v2.img`.
   Boot with the existing compatible booter, drivers, and userspace. Verify
   root mount, userspace startup, an SSH login, and kernel version evidence
   matching the artifact/configuration under test. Record console output
   and a basic filesystem/command smoke test for both configurations.

Boot tests follow repository QEMU rules: distinct guest names and SSH/QMP/
monitor ports; wait for the SSH banner; verify ownership with `query-name`
before stopping a guest. Never modify the base image or stop QEMU by
process name. For writable guests, use `sync; /sbin/reboot` and QMP `quit`
at the next kernel start. Snapshot restarts require restaging lost files.

The milestone is complete only when both Samurai kernels pass these build
and boot checks. A linked kernel alone does not meet acceptance. Kernel
Makefiles remain available after this milestone; retiring them requires
separate parity work.

## Deliverables

- The two entry manifests and shared fragments under `src/kernel-7`.
- Only the native helper scripts needed for configuration, validation,
  dependency handling, and historical recipes.
- The i386 debug DriverKit mapping correction.
- Usage and prerequisite documentation, including debug library staging.
- Focused dependency/configuration checks and recorded evidence for both
  clean builds, incremental builds, and boots.

This spec does not claim the new builds have been implemented or tested.
After written-spec approval, the implementation plan will sequence the
baseline capture, manifests, validation checks, and isolated guest tests.
