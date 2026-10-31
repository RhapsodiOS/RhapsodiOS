# Samurai kernel builds

From `src/kernel-7`, run:

```sh
samu -f build.ninja
samu -f build-debug.ninja
samu -f build-ppc.ninja
samu -f build-ppc-debug.ninja
samu -f build-universal.ninja
samu -f build-universal-debug.ninja
```

The architecture entries select `RELEASE_I386`, `DEBUG_I386`, `RELEASE_PPC`,
and `DEBUG_PPC`.
Outputs are
`BUILD.ninja/<configuration>/mach_kernel` and the unstripped
`mach_kernel.sys`. Both i386 configurations use their historical options,
including `-g -O3 -fno-omit-frame-pointer`. DEBUG_I386 additionally enables its
diagnostic options and links `libDriver_kern_g.o`.

PPC preserves its historical `-g -O2 -mcpu=604` settings. Both PPC
configurations define DEBUG and use `libDriver_kern.o`; DEBUG_PPC adds
`ddm.o` and `xpr.o`. PPC links entry `start`, text at 0x5000, and vectors
at zero. These choices come from the generated historical Makefiles.

The universal entry points build matching RELEASE or DEBUG i386/PPC slices,
then combine them with historical `lipo -create`. Outputs are
`BUILD.ninja/RELEASE_UNIVERSAL/{mach_kernel,mach_kernel.sys}` and
`BUILD.ninja/DEBUG_UNIVERSAL/{mach_kernel,mach_kernel.sys}`. They reuse the
architecture manifests and their existing output directories. Each child
checks its own dependencies on every invocation; unchanged slices avoid
repackaging. A failed child or `lipo` command fails the universal build.
Packaging writes a temporary file and publishes it only after success.
PPC is the first slice for compatibility with the DR2 i386 booter.

The coordinator runs one job per architecture, with up to two children
running together. `-j 1` on the universal invocation builds the slices
sequentially. Run only one build at a time for any architecture/configuration
output directory; a universal RELEASE build owns both RELEASE slice builds.
RELEASE and DEBUG universal builds can run independently. Ordinary
`samu -f build-universal.ninja -t clean` removes universal products and keeps
the thin kernels. Adding `-g` also removes the thin products.

## Prerequisites

Use an i386 Rhapsody guest with a case-sensitive source filesystem and the
historical compiler/linker installed. Build and install Samurai from
`src/Developer/Commands/samurai-1` using its existing Makefile. Put `samu`,
`cc`, `ld`, `mig`, `lipo`, and `relpath` on PATH. Configuration uses
`${CONFIG_DIR-/usr/local/bin}/config`; the selected executable is recorded
as a dependency of preparation.

Set the guest clock at least as new as the synced source timestamps before
building. A guest restored with an older filesystem/RTC date can otherwise
rebuild future-dated inputs on every invocation.

Install current kernel and DriverKit headers in System.framework's Headers
and PrivateHeaders directories. MIG must have its matching typed and
untyped backends installed. The kernel requires these link inputs:

```text
/usr/local/lib/libDriver_kern.o
/usr/local/lib/libDriver_kern_g.o
/usr/local/lib/libkobjc.o
/usr/local/lib/pexperti386.o
/usr/local/lib/pexpertpowermac.o
/usr/lib/libcc.a
```

Install the libraries for the selected architecture. An i386 Rhapsody host
can build PPC with its historical cross backends, including
`/usr/libexec/ppc/2.7.2.1/cpp`; PPC MIG commands explicitly select `-arch ppc`.
Both PPC configurations require `pexpertpowermac.o` and a PPC `libcc.a`.
Run historical `ranlib` after staging `libcc.a` if the linker reports an
out-of-date archive index.

Use the existing project build systems to supply those dependencies.
Build the platform experts from `src/drivers-i386/bus/drvPExpert/i386`
and `src/drivers-ppc/bus/drvPExpert/powermac`, respectively. The
DriverKit default installation may omit the debug object. From
`src/driverkit-3/libDriver`, its existing target is:

```sh
gnumake MACHINE=i386 RC_ARCHS=i386 kerndebug OBJROOT=/tmp/driver-debug SYMROOT=/tmp/driver-debug
```

Create the two output directories first. Stage the resulting
`/tmp/driver-debug/syms/libDriveri386_kern_g.o` as
`/usr/local/lib/libDriver_kern_g.o`. Do not substitute the release object.
The platform-expert contract header must also be installed as
`System.framework/Headers/pexpert/pexpert_i386.h` from the matching
`drvPExpert/i386/pexpert_i386.h` source.

## Build graph and maintenance

Architecture entry manifests select independent output/log directories and use
`subninja` for configuration scope. The fragments under this directory use
`include` for shared rules. Source edges and link order are maintained by
hand; no generator writes Ninja manifests during the build.

Preparation runs the source-tree doconf through `/bin/csh -f`, then the
existing config tool. Its generated Makefile is the reference for validating
the selected sources, compiler settings, and ordered link inputs. A mismatch
stops the build before compilation. After editing MASTER, files, or a
historical template, update the appropriate manifests to agree with the
generated reference and run the configuration comparison tests.

`MASTER.local`, the selected architecture's `MASTER.<arch>.local`, and
`files.NEXT` overrides are rejected. The architecture entry points support the
checked-in RELEASE/DEBUG i386 and PPC configurations. Kernel installation,
distribution packaging, and other configurations use their existing build
systems.

Compiler dependencies come from native `-MD` output. MIG include
dependencies come from native `cc -M` preprocessing with the corresponding
MIG preprocessor flags, because the current MIG wrapper discards `-MD`.
The helper normalizes paths from each command directory to graph paths.
Multi-output generators retain a success marker that is removed before
generation, so interrupted work is retried.

Useful targets and checks:

```sh
samu -f build.ninja configured
samu -f build.ninja objects
samu -f build.ninja -t commands BUILD.ninja/RELEASE_I386/mach_kernel
/bin/sh ninja/tests/config.sh selection /tmp/kernel-selection
/bin/sh ninja/tests/config.sh prepare /tmp/kernel-prepare
/bin/sh ninja/tests/config.sh compare /tmp/kernel-compare
/bin/sh ninja/tests/config.sh syntax /tmp/kernel-syntax
/bin/sh ninja/tests/config.sh defines /tmp/kernel-defines
/bin/sh ninja/tests/config.sh quoting /tmp/kernel-quoting
/bin/sh ninja/tests/build.sh objects /tmp/kernel-objects
/bin/sh ninja/tests/build.sh link /tmp/kernel-link
/bin/sh ninja/tests/build.sh strip-idle /tmp/kernel-strip-idle
/bin/sh ninja/tests/build.sh acceptance /tmp/kernel-acceptance
/bin/sh ninja/tests/build.sh recovery /tmp/kernel-recovery
/bin/sh ninja/tests/logging.sh safe /tmp/kernel-logging
/bin/sh ninja/tests/ppc.sh compare /tmp/kernel-ppc-compare
/bin/sh ninja/tests/ppc.sh build /tmp/kernel-ppc-build
/bin/sh ninja/tests/ppc.sh incremental /tmp/kernel-ppc-incremental
/bin/sh ninja/tests/universal.sh /tmp/kernel-universal /tmp/kernel-seeds
```

The acceptance suite uses one scratch tree for concurrent clean builds,
incremental source/header/MIG checks, failure recovery, library replacement,
link-recipe invalidation, and configuration cleanup isolation.
The recovery suite copies the source tree and existing build outputs, then
checks failed assembly generation, version write errors, interrupted
version generation, and successful retries for both configurations.

The PPC incremental suite checks both configurations for source/header/MIG
dependency rebuilds, failed MIG recovery, idle builds, and cleanup isolation.

The universal suite accepts thin Mach-O executables from an absolute seed
directory, `<configuration>_<architecture>/{mach_kernel,mach_kernel.sys}`, for RELEASE
and DEBUG and architectures I386 and PPC. In its own scratch tree, small
child graphs copy these inputs to exercise the coordinator. Full kernels or
small executable fixtures can be supplied. Native `lipo` extraction must
reproduce every slice byte for byte. The suite checks changed/missing inputs,
idle builds, child and packaging failures with retries, timestamp preservation,
and cleanup isolation.

The configuration and build suites copy the kernel tree and existing outputs
into its scratch directory before running tools. The invoking checkout is
left untouched. `strip-idle` requires a previously linked kernel in the
copied outputs. The toolchain-independent isolation regression is:

```sh
/bin/sh ninja/tests/isolation.sh /tmp/kernel-isolation
```

Use the streaming reader when inspecting a live build log:

```sh
/bin/sh ninja/tests/read-log.sh /tmp/kernel-build.log 20
```

Native Rhapsody `tail` maps regular files. Observing a growing file through
that path can replace appended data with NUL bytes; this was reproduced
without Samurai. The reader pipes the file into `tail`, avoiding its mapped
file path. The `logging` regression verifies the resulting file bytes.
Its `legacy` mode reproduces the unsafe direct-file observation and is
expected to fail on the affected native kernel.

Each test scratch directory must be absolute and initially absent. The
local-override check runs on every build; an unchanged build performs no
kernel-producing work. Release and debug may run concurrently. See
`docs/build/kernel-samurai-validation.md`,
`docs/build/kernel-samurai-ppc-validation.md`, and
`docs/build/kernel-samurai-universal-validation.md` for the measured acceptance records.
