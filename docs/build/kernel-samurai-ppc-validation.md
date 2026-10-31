# PPC Samurai kernel build validation

This extends the i386 milestone recorded in `kernel-samurai-validation.md`.
The four entry manifests retain the existing Makefiles and use the in-tree
Samurai. PPC source edges and link order are explicit, maintained manifests;
configuration still uses historical doconf/config.

## Environment and configuration

Validation ran in the isolated `kernel-samurai-followup` snapshot of the
Rhapsody i386 build guest, using its historical PPC compiler backends and
native Samurai 1.9.0 and Apple cc-771.4 (GCC 2.7.2.1). This is an
i386-hosted PPC build, not execution on a PPC CPU. The base image was not
writable. Each test owns a source/output copy.

| Configuration | Regular objects | Compiler commands | DriverKit library |
| --- | ---: | ---: | --- |
| RELEASE_PPC | 467 | 505 | libDriver_kern.o |
| DEBUG_PPC | 469 | 507 | libDriver_kern.o |

Both historical configurations use `-g -O2`, `-mcpu=604`, and define DEBUG.
DEBUG adds `ddm.o` and `xpr.o`. The manifests preserve these choices, PPC's
`-fno-builtin`, libc optimization rules, the special fdesc optimization,
entry `start`, text address 0x5000, and vectors at zero.

Both platform experts were built through their existing project Makefiles.
The matching SDK headers, MIG wrapper/backends, fat DriverKit/Objective-C
objects, and fat `libcc.a` were staged only in the snapshot. A copied libcc
archive initially failed its index check; historical `ranlib` repaired the
staged index before linking.

## Configuration and regression checks

The native PPC comparison suite passed for both configurations, checking
every compiler source/flag sequence and the ordered link inputs against
the generated Makefiles. It also rejected a changed CPU flag and a PPC
local override. All four entry manifests passed host parsing.

The existing i386 full comparison suite passed, including its negative
cases. Native numeric-define tests and actual assembly-header, MIG, and
kernel-object smoke builds passed for RELEASE_I386 and DEBUG_I386. The
host test-isolation regression and shell syntax checks passed.

Independent review checked all 469 PPC source mappings, both object orders,
all 505/507 compiler commands, configuration outputs, and incremental test
structure. It caught an empty optional path breaking i386 parsing; explicit
architecture-specific configuration-output fragments fixed that regression.

Native idle testing caught RELEASE's empty phony object group forcing a
relink on every invocation. Giving the group the real preparation marker
as an input fixed it. The repeated native invocation then ran only the local
configuration check. DEBUG's group depends on its two actual extra objects.

## Artifact comparison

Both build systems compiled and linked RELEASE_PPC and DEBUG_PPC with
historical tools. The products are Mach-O PPC ALL EXECUTE files with
NOUNDEFS. For each configuration, exported symbol type/name sets and complete
unstripped load-command layouts match. The
assembly header, generated ioconf source, and meta_features header match
byte for byte. Generated MIG C sources match after removing only the
untyped generator's `stub generated` timestamp comment.

The comparison Make build explicitly generated `assym.h` before its
parallel object build after an initial missing-header failure, and staged
its expected `../newvers` link in the private output root. No historical
Makefile was changed.

| Configuration | Exported symbols | Stripped bytes (both systems) | Unstripped bytes (both systems) |
| --- | ---: | ---: | ---: |
| RELEASE_PPC | 5,916 | 2,879,280 | 31,793,120 |
| DEBUG_PPC | 5,988 | 3,065,376 | 31,982,912 |

The binaries are not byte-identical; version/debug build metadata differs.
The comparisons above establish the measured parity rather than binary
identity.

## Incremental and isolation checks

The native PPC incremental suite passed for both configurations. Changes to
`locc.c`, `xoodyak.h`, and `mach/std_types.defs` rebuilt their dependents and
relinked without rebuilding the unrelated APM object. Each following idle
build performed no compilation, generation, linking, or stripping.

An injected MIG exit status 17 failed the build without leaving its success
marker. Both configurations regenerated the missing output on retry and
returned to idle. Cleaning RELEASE removed its kernel and preserved DEBUG's
kernel byte for byte. The invoking checkout's products remained unchanged;
the original synced source checkout had no build outputs.

The final configuration-output fragment factoring retained byte-identical
`samu -t commands` listings for both configurations. The incremental suite
reused the completed build outputs in its own scratch copy, refreshing MIG
success markers there to regenerate dependencies containing absolute source
paths. This does not establish support for relocating build outputs.

## Retained evidence

Artifacts are saved under the host's
`D:/RhapsodiOS/vm/work/kernel-samurai-followup-20261015/` directory:

| Archive | Bytes | POSIX cksum | SHA-256 |
| --- | ---: | ---: | --- |
| `ppc-products.tgz` | 45,120,668 | 147529986 | `3727425c667bcb96f70a63573d9a9ec75c408fb0eaf0038dca58302851ccb379` |
| `ppc-incremental.tgz` | 95,351 | 358254409 | `cf2abc55263806ac2a3f9bc63ce16c9b042dd1e14f13685144279a25f642e40f` |

Guest and host POSIX checksums match. The product archive contains both
systems' stripped/unstripped kernels, generated files, command listings,
comparison evidence, and build logs. The incremental archive contains the
dependency, retry, idle, and isolation logs. All 52 saved text logs were
checked for NUL bytes; none were present. `products-report.json` records
individual product sizes and SHA-256 hashes, with extracted kernels under
`products/`. Earlier failed prerequisite attempts remain in the build logs
before the successful retries.

The base image SHA-256 remained
`6e55911ca3439d6cc24e687c17437c033c717df36520fce37407b0a97eed40f5`.

## Boot qualification

PPC boot execution remains unverified. No PPC guest or identified PPC boot
image was available locally; the recorded PPC host addresses did not accept
SSH connections. The i386 boot results from the earlier milestone remain
separate evidence and are not PPC boot qualification.
