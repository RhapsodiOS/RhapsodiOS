# Samurai i386 kernel validation

Both native Make baselines and final Samurai acceptance passed on graph
revision `d5aa8f431`. Both corrected Samurai kernels booted to userspace
and passed the filesystem/process smoke test on isolated disk images.

## Environment and inputs

- Source base: `a168c0bcc9b39d9b7f2517fe20becd13f2376f28`.
- Kernel prerequisite repairs: `ba330c631`; manifests and tests:
  `84adc6601`, with shell-quoting correction `d5aa8f431`.
- Host evidence: `D:/RhapsodiOS/vm/work/kernel-samurai-20261015/`.
  Large logs, disk images, binaries, and transport scripts stay outside git.
- Builder guest: `kernel-samurai-native`, SSH 2295/QMP 4495/monitor 4595,
  booted with `-snapshot`. Sources: `/tmp/kernel-samurai/src`;
  Make baseline output: `/tmp/kernel-samurai/baseline`.
- Actual base image: `vm/work/rhap-i386-bootstrapped-v2.img`. AGENTS.md's
  example path omits `work`. SHA-256, checked before and after boot testing:
  `6e55911ca3439d6cc24e687c17437c033c717df36520fce37407b0a97eed40f5`.
- Native architecture: i386. Compiler: Apple cc-771.4, GCC 2.7.2.1.
  Compiler/linker/MIG are `/usr/bin/{cc,ld,mig}`; configuration and relpath
  are under `/build/tools/bin`. MIG's matching typed/untyped backends are
  installed under `/usr/libexec`.
- In-tree Samurai passed native `gnumake test` and installation to
  `/tmp/kernel-samurai/stage/usr/bin/samu`; version 1.9.0.
- PATH used: `/build/tools/bin:/tmp/kernel-samurai/stage/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
  `CONFIG_DIR=/build/tools/bin`.

External headers/libraries were staged within the private builder snapshot
from `/build/bootstrap-root`. Native and baseline library copies passed
`cmp`. System.framework Headers and PrivateHeaders must both be present.
The platform-expert public header was installed from the matching source.
DriverKit and platform expert were built with their existing Makefiles;
no non-kernel project source or build rule was changed.

DriverKit debug prerequisite, from `src/driverkit-3/libDriver`:

```sh
gnumake MACHINE=i386 RC_ARCHS=i386 kerndebug OBJROOT=/tmp/kernel-samurai/driver-debug SYMROOT=/tmp/kernel-samurai/driver-debug
```

The resulting `syms/libDriveri386_kern_g.o` was staged under the required
`/usr/local/lib/libDriver_kern_g.o` name. It was never replaced by release.

| Installed input | POSIX cksum | Bytes |
| --- | ---: | ---: |
| libDriver_kern.o | 3534484624 | 6104804 |
| libDriver_kern_g.o | 515438825 | 2915776 |
| libkobjc.o | 2365978533 | 936852 |
| pexperti386.o | 1561587722 | 1700108 |
| /usr/lib/libcc.a | 2658205958 | 24428 |
| config | 4075087201 | 93868 |
| samu | 441982513 | 68424 |

## Baselines and comparisons

From `src/kernel-7/conf`, tools were prepared using the existing `tools`
target. Both baseline builds completed with the same final kernel sources:

```sh
gnumake ARCH=I386 TYPE=RELEASE mach_kernel.kernel OBJROOT=/tmp/kernel-samurai/baseline SYMROOT=/tmp/kernel-samurai/baseline NEXT_ROOT=/build/bootstrap-root
gnumake ARCH=I386 TYPE=DEBUG mach_kernel.kernel OBJROOT=/tmp/kernel-samurai/baseline SYMROOT=/tmp/kernel-samurai/baseline NEXT_ROOT=/build/bootstrap-root
```

Final native logs are `make-RELEASE-final.log` and
`make-DEBUG-link-green.log` under `/tmp/kernel-samurai`. Generated Makefiles,
load commands, symbol inventories, and checksums are captured as evidence.
The reference selects 349 regular source objects in each configuration;
the comparator checks 389 compiler commands plus the complete ordered link,
including libc, Mach user API objects, assembly offsets, profiling, ioconf,
and version compilation.

Both use the historical `-g -O3 -fno-omit-frame-pointer`, file-specific
exceptions, native MIG modes, `_start`, `__TEXT=0x00100000`,
`__LINKEDIT=0x00780000`, and `strip -x`. Global exported symbol names/types
match the Make baselines. Native `size` headings are `__TEXT`, `__DATA`,
`__OBJC`, and `others`; `others` must not be interpreted as BSS. Debug
assertion filename strings differ between absolute Make source paths and
relative Samurai paths, so DEBUG data sizes and subsequent addresses need
not be byte-identical. Per-object comparison located those differences in
HFS assertion data; code sizes were unchanged.

## Regressions exercised

The selection suite first failed on the missing DEBUG DriverKit mapping.
Both native Make and Samurai then exposed pre-existing i386 DEBUG defects:
PowerPC-only NFS backtrace assembly and missing `call_kdp`, `debug2`, and
`libIO_dbg` definitions. Narrow kernel-side fixes preserve PPC behavior,
use i386 EBP/return-address layout and `int3`, keep the PPC Cuda sysctl slot,
and provide a default-off i386 DriverKit logging switch. A native frame-chain
test reproduced a terminal-frame bus error before its i386 guard was added.

Configuration tests cover initial preparation, no repeated doconf, missing
meta header recovery, missing config tool failure/retry, and local overrides
after earlier success. Because config appends meta imports only when
creating option headers, preparation recreates the declared headers together.

Comparison tests reject missing/extra source edges, reordered link inputs,
changed optimization/defines, the wrong debug library, MASTER/files changes,
unsupported assignment operators, and changed shell quoting. Tool wrappers
verify that rejected configurations run no compiler or linker. Actual cc
argument checks additionally require numeric TIMEZONE/PST definitions;
the earlier over-escaped candidate and permissive checker were rejected.

Historical strip backdates output by five seconds. A native regression
proved that this caused an unnecessary second strip immediately after link.
The graph retains `strip -x` and touches its completed output afterward.
The focused `strip-idle` regression passed for both variants.

The guest initially restored an older filesystem date. Its clock was fixed
before final clean/incremental acceptance. Runs before that correction,
and runs whose executing scripts were overwritten in place, are excluded.
Final suites use immutable script copies. Historical `/dev/stderr` reopening
can truncate logs; the checker relays captured diagnostics through fd 2.
A native prefix/error/suffix regression verifies log preservation.

## Acceptance status

Final corrected run: `/tmp/kernel-samu-acceptance5`, with verbose clean
build logs and retained compiler/linker/MIG invocation logs per mutation.
Earlier acceptance4 dependency/recovery cases passed, but its kernels used
string-valued numeric defines and are superseded by the corrected run.

| Check | RELEASE_I386 | DEBUG_I386 |
| --- | --- | --- |
| Make baseline link | Passed | Passed |
| Corrected clean Samurai compile/link | Passed | Passed |
| Native configuration comparison | Passed | Passed |
| Incremental/concurrent/recovery checks | Passed | Passed |
| Corrected kernel boot and userspace smoke | Passed | Passed |

Boot guests use independent full copies `release.img` and `debug.img`,
with names `kernel-samurai-release` and `kernel-samurai-debug`. Ports are
SSH/QMP/monitor 2296/4496/4596 and 2297/4497/4597. QMP `query-name` confirms
ownership. Writable staging uses `sync; /sbin/reboot`, then QMP quit at the
next kernel start. Acceptance boots use `-snapshot`. The SSH smoke captures
uname, kern.version, root mount, installed checksum, file write/copy/cmp,
and a process-list check. No stock-kernel boot counts as acceptance.

## Verified boot artifacts

| Configuration | Build time (EDT, October 15) | POSIX cksum | Bytes |
| --- | --- | ---: | ---: |
| RELEASE_I386 | 12:12:47 | 1623952506 | 1811256 |
| DEBUG_I386 | 12:13:38 | 2458358702 | 2091684 |

SHA-256 of the stripped kernels:

- RELEASE: `1e0512c2f2714e6d20ffd58618fe23a3de616c9d6e7e6cc35bd3dbf68b7622fc`.
- DEBUG: `4956175eb560f22eb3479f46612816f9f5a14aa8ec07ba112c7310fbc13b2122`.

Host copies are `artifacts/verified-release/mach_kernel` and
`artifacts/verified-debug/mach_kernel` under the session directory.
Native captured stripped/symbol pairs are `/tmp/kernel-samurai/boot-final5`.
Re-stripping each captured symbol file reproduced its stripped file exactly.
Both final Mach-O headers report I386/ALL/EXECUTE/NOUNDEFS. Release has
__TEXT/__DATA/__OBJC sizes 1478656/405504/98304; debug has
1642496/606208/98304. The Make debug __DATA size is 614400 because of the
HFS filename strings described above. The corrected param.o data size is
64 bytes in both builds; string-valued defines had incorrectly made it 68.

`verified-release-install.log` and `verified-debug-install.log` record the
matching installed checksums. The corresponding `verified-*-boot-smoke.log`
files record the correct `BUILD.ninja/<CONFIG>` version, `/dev/hd0a` mounted
as root, matching checksum, and `BOOT_SMOKE_PASS`. Serial evidence is in
`release-boot-kernel.log` and `debug-boot-kernel.log`; neither contains a
panic or failure. These are basic emulator boot/smoke checks, not hardware
or filesystem stress testing.

`native-evidence5.tgz` preserves the native verbose clean logs, mutation
invocation logs, comparison diagnostics, baseline Makefiles/binaries,
captured symbol files, representative compiler/MIG dependencies, and
external library/tool identities. Missing-final-output recovery performed
only strip; a missing private debug library failed without compilation or
release-library fallback. Restoring it returned to an idle build.

Existing kernel Makefiles remain the fallback. rbuild, installation,
packaging, PPC, and every non-kernel project remain outside this milestone.
