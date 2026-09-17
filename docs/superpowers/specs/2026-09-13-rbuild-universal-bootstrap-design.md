# Universal rbuild repository bootstrap

## Purpose

Rebuild the live package repository so every `BootstrapManifest` artifact is a
real universal binary (`universal-apple-rhapsody`, i386 + ppc). After that,
ordinary rbuild operations can build ppc and i386 products against `/build/repo`
without seeding i386 runtime slices from `golden.img`.

This is the design approved in conversation on September 13, 2026. It revises
the 2026-09-12 architecture-policy exclusion that kept `rbuild bootstrap` a
deliberate single-target operation. Thin bootstrap remains, but it is no longer
the documented way to produce a dual-arch repository.

## Constraints

- Replace the live trees: `/build/repo` and `/build/bootstrap-root` (and
  `/build/state` with `-Fresh`). Do not keep a parallel private repo.
- Produce i386 slices from source only. Do not copy `crt1.o`, `System`, or
  `libcc` from `golden.img`.
- The guest is Rhapsody PPC. Host tools must keep a runnable ppc slice.
  `gcc-darwin.conf` stays `target_arch=ppc`. Universal is an operation, not a
  new compiler profile.
- Ordinary `buildall` cannot perform the second pass: it chroots and will
  reject leftover thin basedeps.
- Success is a fat `BootstrapManifest` repo plus one ordinary universal
  `buildpackage` and one `rbuild kernel --arch i386` proof. Kernel/world are
  not part of this effort. Proof artifacts are inspected, not executed.

## Current behavior and defect

- Ordinary builds already default to universal and reject thin code
  dependencies. The live repo is still thin ppc from `rbuild bootstrap`.
- `builder_resolve_architecture` accepts only a thin profile `target_arch` for
  bootstrap and forces that CPU. Universal is not a legal operation mask.
- After a thin pass, `ld_flags_ready` (System) exists but is ppc-only. A naive
  universal link probe would fail before fat crt/System exist.
- `cctools` must exist before `Csu` (`indr`). `Csu` / `Libc` / `Libsystem` must
  exist before any fat-linked executable. One manifest order cannot satisfy both
  constraints in a single universal walk.
- `Csu` copies host `/usr/lib/dyld` (ppc) and assembles `dyld_stub.s` with ppc
  `blr`. A universal `csu` package will fail product checks without a fat stub
  and a fat installed `dyld`.

## Commands

| Command | Role |
| --- | --- |
| `rbuild bootstrap` | Unchanged thin native seed. Tests and the first walk keep using it. |
| `rbuild bootstrap-universal` | Primary documented method. Native, no chroot. Rebuilds the same sysroot/repo as fat `universal-apple-rhapsody`. |

`bootstrap-universal` takes the same flags and arguments as `bootstrap`:
`--sysroot ROOT --toolchain FILE --state DIR srclist repository dstdir`.

It does not silently invoke thin bootstrap. Missing `ld_flags_ready` or missing
sysroot `indr` after the thin `cctools` step is a hard error naming the path.

`build-src.ps1 -Bootstrap` is the host primary path: thin `bootstrap`, then
`bootstrap-universal`. README and `vm/README.md` describe that pair as how you
get a repo that can build ppc and i386. Thin-only bootstrap is documented as
insufficient for ordinary universal builds.

## Architecture policy

Keep `architecture_parse` labels as they are. Extend `architecture_resolve` so
operation may be `RB_ARCH_UNIVERSAL` in addition to thin i386/ppc and ordinary
`0`.

| Source | Universal bootstrap operation | Effective |
| --- | --- | --- |
| Missing or `universal-apple-rhapsody` | universal | `universal-apple-rhapsody` |
| Explicit i386 or ppc | universal | Error before make |

Thin `bootstrap` still sets operation from the profile's thin `target_arch`.
Kernel `--arch i386` / `--arch ppc` is unchanged: a universal dependency may
satisfy a thin consumer.

## Walks

All walks are native (no `makeroot`, no chroot). They share `/build/bootstrap-root`,
`/build/repo`, and `/build/state`.

1. **Thin walk** — existing `rbuild bootstrap` of `src/BootstrapManifest`.
   Runnable ppc sysroot. APKs are `ppc-apple-rhapsody`.

2. **Universal runtime walk** — `bootstrap-universal` reads
   `src/BootstrapRuntimeManifest`, a contiguous subsequence of
   `BootstrapManifest` from `Csu-1` through `Libsystem-2`. Rebuilds crt,
   language/runtime libraries, component libs, and fat `System.framework`.

3. **Universal full walk** — the same process then reads the caller-supplied
   `BootstrapManifest`. Tools and commands fat-link against fat `System`.
   Runtime APKs already match and are reused. Thin leftovers are quarantined.

One invocation performs both universal walks. The caller passes the full
manifest (`src/BootstrapManifest`). The command loads
`BootstrapRuntimeManifest` from the same directory; if that file is missing,
it errors. The runtime walk always runs first. `build-src.ps1 -Bootstrap`
invokes `bootstrap-universal` once with the full manifest after thin
`bootstrap`.

ppc `effective_architecture` records are stale under a universal operation and
rebuild. Toolchain/profile fingerprint mismatch or corrupt state still requires
`-Fresh`.

## Per-CPU link readiness

Compile-probe every requested CPU before an `all`/`binary` build.

Link-probe a CPU only when the sysroot already contains that CPU in crt and in
the `ld_flags_ready` System binary. File existence is not enough: inspect
Mach-O slices. After the runtime walk publishes fat `System`, later entries
link both CPUs.

If readiness claims a slice exists and the link still fails, fail the entry
with the linker diagnostic. Do not retry as thin. Do not publish.

A compile-probe failure names the CPU and stage. Missing i386 compiler backend
is a failed acceptance, not a skip.

## Csu and Libsystem

**Csu**

- Add an i386 `MH_DYLINKER` stub (`ret`); keep the ppc stub (`blr`).
- Compile per architecture and lipo. Do not assemble ppc `blr` as i386.
- Installed `/usr/lib/dyld` must contain both slices: lipo the runnable host
  ppc `dyld` with the from-source i386 stub. The ppc side remains the host
  binary already copied today; the i386 side is not taken from `golden.img`.
- `indr -arch all` and existing `RC_CFLAGS` remain the fat-object path.

**Libsystem and harvested libs**

- `Libc` already has i386 and ppc subprojects. Component libs must be fat
  before `Libsystem` re-exports them.
- `Libsystem` uses singular `TARGET_ARCH` for `System.order.$(TARGET_ARCH)` and
  object-dir links. If one invocation with `RC_ARCHS="i386 ppc"` breaks that,
  fix those recipes to iterate the selected archs.
- That repair is in scope. Other unrelated project failures are reported, not
  silently thinned.

## Packaging, quarantine, and replay

Universal products, APKs, and `.PKGINFO` use `universal-apple-rhapsody`.
Mach-O files and static archives must contain both slices. Scripts, headers,
and other data stay neutral.

Thin same-name APKs in `/build/repo` are quarantined as `.invalid` before a
universal publish. An existing `.invalid` is left alone; the build stops rather
than overwriting it.

Replay into the sysroot uses the same native `apk_use_arch` path as thin
bootstrap, with the universal mask. A thin payload cannot establish universal
state.

## Proof builds

After every `BootstrapManifest` APK is fat:

1. Ordinary `rbuild buildpackage --target all` of a small unlabeled or
   universal tool or library, using a chroot populated from `/build/repo`.
   Products must be i386 + ppc. A repeat must reuse the validated cache.
2. `rbuild kernel --arch i386` into a destination that is not treated as a
   bootable ppc kernel. Metadata is `i386-apple-rhapsody`. Universal basedeps
   may satisfy this thin consumer. Inspect slices; do not boot or run it.

Proof failure fails overall acceptance. It does not delete a successful fat
repo.

## Error handling

- `bootstrap-universal` without a completed thin sysroot: hard error, missing
  path named, no implicit thin bootstrap.
- Host cannot compile `-arch i386`: compile-probe failure, no ppc-only fallback.
- i386 link attempted before crt/System contain i386: probe bug; readiness must
  skip that link.
- Thin Mach-O in a universal package: path-specific failure and quarantine as
  specified above.
- Explicit thin source under universal operation: fail before make.
- Csu/Libsystem recipe failures: real build failures.
- Proof failures: fail acceptance; leave the fat repo in place.

## Testing

**rbuild (`make test`, `make trace-test`)**

- Resolver cases for universal operation, including thin-source conflict.
- Per-CPU link readiness: ppc-only System → compile both, link ppc only; fat
  System → link both; missing marker → compile-only as today.
- CLI parity with `bootstrap`, plus universal operation; dry-run lists runtime
  walk then full walk.
- `BootstrapRuntimeManifest` is the required contiguous subsequence.
- Resume: ppc records rebuild under universal; matching universal records
  reuse; toolchain mismatch still errors.
- Quarantine of thin same-name APKs.
- Trace-test stays on ordinary/thin bootstrap flags. Do not fold universal
  bootstrap into the Perl oracle.

**Csu / Libsystem**

- Fat `dyld_stub` and installed `dyld` contain i386 and ppc.
- `System.order.i386` and `System.order.ppc` are used when both archs are
  selected.

**Host scripts (`vm/tests/test-build-src.ps1`)**

- `-Bootstrap` emits thin `rbuild bootstrap` then `rbuild bootstrap-universal`.
- README and `vm/README.md` call that pair the primary method.

**Guest acceptance (live trees, after wipe)**

1. Thin bootstrap completes.
2. `bootstrap-universal` completes. Every `BootstrapManifest` APK in
   `/build/repo` has `arch universal-apple-rhapsody`. Sampled executables,
   libraries, `System`, and `crt1.o` have both slices (`lipo` and rbuild's
   Mach-O reader).
3. Ordinary universal `buildpackage` proof, including cache reuse.
4. `rbuild kernel --arch i386` proof, not executed.

Host unit tests alone do not establish a working dual-arch repo.

## Scope exclusions

- No `golden.img` i386 runtime seed.
- No general CLI architecture override for ordinary builds.
- No automatic downgrade to thin on failure.
- No full kernel/drivers/world rebuild in this effort.
- No claim that produced i386 programs or kernels run on the PPC guest.
- No change to APK filename format. Thin and universal variants still cannot
  share one destination as interchangeable artifacts; this work replaces the
  live repo in place via quarantine and rebuild.
