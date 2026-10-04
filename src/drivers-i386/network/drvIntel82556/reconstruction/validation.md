# Intel82556 reconstruction validation

The complete reference function inventory is reconstructed and builds with the
native i386 toolchain. All 92 functions decompile in the reviewed IDA database.
Strict BinRecon binary acceptance still fails, and physical-card operation has
not been tested. These are separate results, not a global equivalence claim.

## Artifact identity

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Original `Intel82556NetworkDriver_reloc` | 68284 | `C26B34F0A07346F20C1D51795C601BED436CF3BE20E0AB6882E98C9114508B72` |
| Rebuilt `Intel82556NetworkDriver_reloc.rebuilt` | 308992 | `28C2E3CBB96C47E8F88300E0F1BD51C3D400904ED3A39AEDC2F5C18C09FB50A9` |
| `Intel82556NetworkDriver-install.tar.gz` | 89350 | `F0DB4B75D231DA1EACF6BAD35E1D262C89F1523FFFF7D0FAAE1FDA1C4B21C235` |

The rebuilt module includes debug information. Local generated evidence is in
`tools/binrecon/out/intel82556/`; comparison exports are in
`tools/binrecon/out/intel82556-compare/`. These directories are ignored by Git.

## Results

| Check | Result | Evidence |
|---|---|---|
| IDA 9.4 decompilation | 92/92 successful after import typing and stack reanalysis | `ida-reviewed.json`, `Intel82556NetworkDriver-reference-reviewed.i64` |
| Source coverage | 90 handwritten + 2 generated; no missing, duplicate or disputed functions | `source-map.json`, `verify_evidence.py` |
| Native production build | All four Objective-C sources compile/link; zero compiler warnings | `native-build-final.log` |
| Buffer pool | 57 reference-derived checks pass | `native-tests.log` |
| Native ABI | All 48 driver/pool ivar offsets and descriptor layouts pass | `native-tests.log` |
| Engine behaviors | 28 reference-derived checks pass | `native-core-tests.log` |
| Adapter port traces | 9103 checks, zero failures | `native-adapter-tests.log` |
| Objective-C inventory | All 85 method names match | `verify_evidence.py --rebuilt ...` |
| Kernel imports | Exact set equality | `verify_evidence.py --rebuilt ...` |
| Review ledger | Binary identities, complete partition and source sites validate | `verify_evidence.py --ledger ...` |
| Loader metadata and staged install | Server name, load commands, instance and version bytes match; archived module hash and resources verified | `packaging-verification.json` |
| Strict BinRecon acceptance | **FAIL**, analysis completed | `intel82556-compare/run-summary.json` |

The behavioral total is **9188** checks, in addition to ABI assertions. The old
source failed native compilation; its core selector contract also fails before
compilation (four of eight required selectors, status 3). The tests use mocks
for kernel services and hardware. Their detailed scope is in
[tests/README.md](tests/README.md).

The native compiler was Apple cc-771.4, based on GCC 2.7.2.1, with the original
`pb_makefiles`/`kl_ld`. The private guest reports 8192-byte pages. The final
production build, pool/core tests and staged install ran together; the adapter
suite subsequently ran on the same source and toolchain without changing the
production artifact. The reusable VM script now runs all three suites. The
private QEMU snapshot was shut down after verification; no base disk was changed.

## Binary comparison limits

All 92 functions pair by name. Eighteen are raw-byte equal and 50 are equal with
relocations masked. Zero satisfy the current strict normalized-function test;
the normalized representation retains address, call and control-flow layout
differences even for functions whose masked bytes match. The comparison was
not relaxed or relabeled PASS.

The final comparison reports 328 code, 17 layout, 1193 metadata, 5326 padding,
and one relocation finding. These are report records, not counts of defective
functions. No final per-function finding reports different relocation target
semantics. Native debug metadata accounts for much of the image size difference.

Independent assembly reviews covered the shared engine, pool and both adapters.
Review found and corrected collapsed volatile writes, an extra pool-free flag
read and missing protocol conformance before the final rebuild. Remaining
reviewed differences include register allocation and compiler block ordering;
`setThrottleTimers` has the same calls, polling, port writes and return paths
with success/error blocks emitted in a different order. No unresolved concrete
behavior difference was identified by those reviews. This is not a proof that
every compiled path is equivalent. Supporting local notes:
`core-independent-review.md`, `adapters-review.md`, and
`rebuilt-divergence-review.md`.

The ledger uses `control-flow-confirmed`, not `assembly-matched`. Reviews were
performed by Codex using one analyzer, IDA; they are not independent-analyzer
consensus or human review.

## Reproduction and remaining validation

Use [README.md](README.md) for BinRecon commands and
`vm/build-i386-intel82556.sh` for the native build/test/install workflow.
Add `--ledger src/drivers-i386/network/drvIntel82556/reconstruction/ledger.json`
to the evidence verifier to validate the review ledger as well.

Run `ida_annotations.py` in the reference IDA database as described in its
docstring, then save the database. It checks the reference SHA-256, applies
reviewed cdecl import types, reruns debugger-receive stack analysis, adds source
links and exports all 92 pseudocode bodies. It makes no binary patches. The
unmodified analysis exports remain the inputs of the strict BinRecon comparison.

Hardware validation requires an appropriate Intel PRO/100 EISA or PCI adapter:
probe and resource allocation, DMA, real interrupt delivery, packet traffic,
link/PHY behavior, reset recovery, multicast and debugger transport remain
untested on physical hardware. No driver was loaded on the host machine.

The native staged install succeeds. Its legacy `driver.make` emits an ignored
chmod error after `thindriver.sh` moves the bundle into the i386 directory;
the final destination, resources and module hash were independently checked.
APK generation through `rbuild` remains blocked by the guest repository's
missing `cc` dependency package (`drivertools-build.log`). The install archive
is available independently. The unrelated userspace inspector executable/nib
is outside this kernel-driver reconstruction.
