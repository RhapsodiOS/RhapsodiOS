# Native i386 Samurai kernel builds

From `src/kernel-7`, run:

```sh
samu -f build.ninja
samu -f build-debug.ninja
```

These build `RELEASE_I386` and `DEBUG_I386`, respectively. Outputs are
`BUILD.ninja/<configuration>/mach_kernel` and the unstripped
`mach_kernel.sys`. Both configurations use their historical options,
including `-g -O3 -fno-omit-frame-pointer`. DEBUG additionally enables its
diagnostic options and links `libDriver_kern_g.o`.

## Prerequisites

Use an i386 Rhapsody guest with a case-sensitive source filesystem and the
historical compiler/linker installed. Build and install Samurai from
`src/Developer/Commands/samurai-1` using its existing Makefile. Put `samu`,
`cc`, `ld`, `mig`, and `relpath` on PATH. Configuration uses
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
/usr/lib/libcc.a
```

Use the existing project build systems to supply those dependencies. The
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

Entry manifests select independent output/log directories and use
`subninja` for configuration scope. The fragments under this directory use
`include` for shared rules. Source edges and link order are maintained by
hand; no generator writes Ninja manifests during the build.

Preparation runs the source-tree doconf through `/bin/csh -f`, then the
existing config tool. Its generated Makefile is the reference for validating
the selected sources, compiler settings, and ordered link inputs. A mismatch
stops the build before compilation. After editing MASTER, files, or a
historical template, update the appropriate manifests to agree with the
generated reference and run the configuration comparison tests.

`MASTER.local`, `MASTER.i386.local`, and `files.NEXT` overrides are rejected.
These entry points support the checked-in release/debug i386 configurations.
Kernel installation, packaging, and other architectures use their existing
build systems.

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
```

The acceptance suite uses one scratch tree for concurrent clean builds,
incremental source/header/MIG checks, failure recovery, library replacement,
link-recipe invalidation, and configuration cleanup isolation.
The recovery suite copies the source tree and existing build outputs, then
checks failed assembly generation, version write errors, interrupted
version generation, and successful retries for both configurations.

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
`docs/build/kernel-samurai-validation.md` for the measured acceptance record.
