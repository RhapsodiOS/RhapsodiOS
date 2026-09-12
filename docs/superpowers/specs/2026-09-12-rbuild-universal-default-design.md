# rbuild architecture-driven universal builds

## Purpose

Make package architecture metadata determine the architectures rbuild builds.
Ordinary packages default to universal i386 + ppc when Architecture is absent.
An explicit label must never be replaced silently with a host-derived policy.

This is the design approved in conversation on September 12, 2026. It describes
planned behavior; no implementation or guest validation has been performed.

## Current behavior and defect

- `src/rbuild-1/package.c` already parses Architecture into Package.
- `builder.c:readcontrol` unconditionally replaces that value with
  `universal-apple-rhapsody`; `makecontrol` uses the same default.
- `builder_buildflags` selects the compiled host architecture for ordinary
  builds. Bootstrap instead uses the toolchain's single target_arch.
- `pkginfo.c` emits the package architecture, allowing thin products to be
  advertised as universal today.
- Existing driver controls include Architecture: i386, so preserving explicit
  source metadata is necessary, not merely future extensibility.
- APK filenames omit architecture. Runner checks include metadata identity,
  but metadata alone cannot distinguish old falsely universal artifacts.

## Architecture policy

| Source Architecture value | Ordinary target slices | Output architecture |
| --- | --- | --- |
| Field absent, including synthesized control | i386 and ppc | universal-apple-rhapsody |
| universal-apple-rhapsody | i386 and ppc | universal-apple-rhapsody |
| i386 or i386-apple-rhapsody | i386 | i386-apple-rhapsody |
| ppc or ppc-apple-rhapsody | ppc | ppc-apple-rhapsody |
| Empty or unsupported value | Error | No artifact |

Normalize supported aliases to the canonical output values above. Do not
interpret Debian any/all values from unrelated debian/control files: the input
remains the project's dpkg/control. Unknown labels must produce a diagnostic
naming the source and value, not fall through to synthesized universal control.

Resolve this policy before cache decisions, dependency selection, or building.
Keep source intent distinguishable from an effective bootstrap target so that
validation does not depend on rewriting the input file.

## Build approach

Use the existing project make frameworks' multi-architecture support in one
build invocation. Universal means RC_ARCHS="i386 ppc", matching -arch i386 and
-arch ppc entries in RC_CFLAGS, and both RC_i386=YES and RC_ppc=YES. Thin builds
enable only their selected architecture. Retain existing Rhapsody defines and
path/toolchain handling. Audit TARGETS consumers before setting it consistently
where required; do not assume every legacy project interprets it identically.

Do not add separate build-tree merging or a host-only fallback. Separate
builds plus merging would introduce conflicts for headers, resources, archives,
and install products. A host fallback would contradict source metadata.

## Bootstrap and explicit kernel targets

Bootstrap remains a deliberate single-target operation using target_arch from
its profile. A missing or universal source label permits this bootstrap-only
subset; its effective output label must be the corresponding thin label.
An explicitly thin source label must match the profile, otherwise fail before
building. This exception is visible in diagnostics and output metadata.

Kernel and kerneldrivers keep their required --arch selection. Carry that target
through to build policy, rather than merely using it to select project paths.
Missing/universal source labels permit the explicitly requested subset here;
an explicit thin label that conflicts is an error. Emit the effective thin
label. Ordinary buildpackage/buildall do not inherit this exception.

Do not broaden this work into a universal bootstrap toolchain or a multi-host
build coordinator. Existing supported bootstrap configurations must continue
to work; architecture policy must reject unsupported target combinations
clearly rather than silently choosing ppc.

## Prerequisite and product validation

Before compiling an ordinary package, test each requested architecture with
the actual compiler, linker, and dependency root used by that build. A compiler
accepting -arch is insufficient: verify the resulting object architecture and
perform a representative link for targets that link. Header-only targets must
not require linking. Probes run in private build paths, never modify the live
host root, and appear without execution in dry-run output.

Report which architecture or prerequisite failed. Never retry as a thin build.
The current host-only comment documents real missing compiler/runtime support;
changing flags alone is not an acceptable completed implementation.

Before publishing or reusing a universal binary package, inspect its Mach-O
products and static-library members for the requested slices. Inspect binary
content rather than executable permissions or filename extensions. Scripts,
resources, and headers need no Mach-O slices. Apply the same policy to object
packages where they contain machine code. A universal product may store slices
in a fat container; architecture-specific intermediate objects must be assessed
as the intended paired collection, not individually required to be fat.

Reject missing slices and mismatched thin products with a path-specific error.
Use the repository/target's available Mach-O tools or a narrowly scoped reader;
the implementation plan must choose the concrete mechanism after inspecting
tool output and existing packaging layouts. Validation must not claim that
resource-only packages prove compiler support.

## Metadata, dependencies, and reuse

Use the resolved effective architecture consistently for make flags, package
identity, emitted .PKGINFO, and runner decisions. Header/object variants inherit
the effective package policy even when a header payload contains no code.

Include architecture policy and a policy-version marker in resumable state.
Old state records cannot establish that an artifact satisfies this contract.
Inspect old universal artifacts before reuse; rebuild those missing slices.
Apply checks to paths that skip existing packages as well as stateful runner
paths. `missing` must not count an incompatible artifact as satisfying a build.

Dependency lookup must reject incompatible machine-code payloads: universal
builds need both slices; a thin build can consume its matching slice from a
universal dependency. Header-only dependencies do not require code slices.
Bootstrap replay must accept only products compatible with its effective target.

Keep existing APK filenames in this change. Separate repositories/destination
directories are required when retaining thin and universal variants of the same
name/version simultaneously. An incompatible same-name artifact must not be
silently reused or published over as if it were the requested build.

## Implementation boundaries

- `package.c/.h` and/or a focused architecture module: supported label parsing,
  canonicalization, source/effective policy resolution.
- `builder.c/.h`: preserve labels, propagate resolved policy, generate flags,
  run build-environment probes, and validate products before packaging.
- `runner.c/.h`: propagate explicit targets, architecture-aware reuse and state.
- `apk.c/.h`: validation of reusable/extracted package products where needed.
- `pkginfo.c`: retain its existing metadata-emission role; consume resolved data.
- `main.c`: adjust missing/command plumbing only as required by the policy.
- Existing tests, trace fixtures, Makefile, README, and relevant build docs:
  regression coverage and migration instructions.

Avoid unrelated refactoring, source-project fixes, or edits to the user's
ongoing driver reconstruction work. If a legacy project cannot build universal,
report that failure; an intentional architecture restriction belongs in its
reviewed package metadata.

## Verification and acceptance

1. Unit fixtures prove omitted/default, universal, both thin aliases, empty,
   unsupported, and conflicting explicit targets resolve as specified.
2. Command tests prove flags follow metadata regardless of the rbuild host and
   retain correct bootstrap compiler/sysroot handling.
3. Controlled probes cover missing compiler support, wrong-slice objects,
   missing runtime libraries, header-only builds, and dry-run behavior.
4. Product fixtures cover fat/thin Mach-O, archives, paired object collections,
   resource-only payloads, and missing-slice rejection.
5. Runner/dependency tests reject incompatible reuse, invalidate old state,
   accept a compatible universal dependency for a thin build, and keep metadata
   consistent with effective targets.
6. Run `make test` and `make trace-test` in a supported POSIX build environment.
   Update only intentional trace differences; do not mask architecture checks.
7. In an isolated guest build root, build representative executable, library,
   and object-package products with both toolchains/runtimes available. Inspect
   extracted APK metadata and slices, and exercise one thin labeled package.
8. Record unavailable toolchain or guest prerequisites as unverified coverage;
   host unit tests alone do not establish working universal OS builds.

## Scope exclusions

No general CLI architecture override for ordinary builds, new package naming
scheme, automatic architecture downgrade, independent cross-host merge system,
or wholesale repair of all OS projects. The source label is the ordinary build
policy, with only the explicit bootstrap/kernel operations described above.
