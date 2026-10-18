# Bounded PPC verification

Task 2 supplies execution and build infrastructure. Its passing fixtures do
not promote any reconstruction ledger entry, establish paired acceptance,
or validate physical hardware, DMA, timing, or concurrency.

## Runtime and focused checks

Create the driver-only environment without changing shared binrecon packages:

```powershell
$au2Out = 'tools/binrecon/out/adaptecu2scsi-ppc'
$au2Tests = 'src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests'
& D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m venv --system-site-packages "$au2Out/venv"
$au2Python = "$au2Out/venv/Scripts/python.exe"
& $au2Python -m pip install -r "$au2Tests/requirements.txt"
$env:PYTHONPATH = 'tools/binrecon'
& $au2Python -m pytest -p no:faulthandler "$au2Tests/test_reconstruction.py" -k 'runner or stale' -q
& $au2Python "$au2Tests/ppc_cases.py" reference --reference "$au2Out/reference" --cases "$au2Tests/reference-cases.json" --contracts "$au2Tests/contracts.json" --output "$au2Out/reference-results.json"
```

The actual primary environment is Python 3.13.9 with Unicorn 2.1.4. A separate
bundled Python 3.12.14 probe reproduced the same Windows behavior. Unicorn's
Windows demand paging deliberately raises handled first-chance access
violations during its first `mem_map`; pytest's faulthandler prints misleading
fatal-exception messages even when execution succeeds. The focused command
disables only that pytest plugin. The runner does not suppress Unicorn
execution errors. See the [upstream FAQ](https://github.com/unicorn-engine/unicorn/blob/master/docs/FAQ.md#i-debug-my-application-but-soon-get-an-access-violation-inside-unicorn)
and [maintainer explanation](https://github.com/unicorn-engine/unicorn/issues/1841).
Standalone CLI execution needs no workaround.

The independent synthetic smoke image asserts executed instruction counts,
32-bit wrap, big-endian writes, LR return behavior, relocated symbols, BSS
zeroing, scripted service/register traces, and rejection of unknown calls,
registers, barriers, cache operations, forged returns, loops, stale results,
and internal bodies incorrectly declared as services. The six committed
reference fixtures have manually specified scalar expectations from the
reviewed conversion-helper instruction semantics at `0x189120..0x1891bc`.
They have no scripted kernel services. These observations are not generated
from a prior runner result.

## Fixture and execution contract

`run_case(binary: Path, case: dict, contracts: dict) -> dict` loads the
existing reader's linked PPC Mach-O segments at their own addresses, with
their protections and zero-filled BSS. It uses a 64 KiB stack at `0x7ff00000`,
initial `r1=0x7ff0ff00`, return sentinel `0x7fff0000`, and PPC 604 CPU model.
The sentinel is accepted only after an actual `blr` with the correct LR.
Reviewed integer/pointer arguments occupy `r3..r10`; stack and floating-point
arguments are unsupported and must not be silently approximated.

Each case has:

- `id`, symbolic `entry`, reviewed byte `size`, and optional `internal` bodies
  (`entry`, `size`). Only these function extents may execute.
- `arguments`, integers masked to 32 bits or `{region, offset}` pointers.
- `memory`, named regions with declared `size` and initial hexadecimal `bytes`.
  Optional `pointers` contain `{offset, value}` initial pointer fields.
- `observe`, records with `region`, `offset`, and byte `size`. Optional
  `pointer_fields` list four-byte field offsets relative to that observation.
- `external_outcomes`, a single ordered stream of service and register events.
- Positive `instruction_limit` up to 1,000,000; `expected` observations; and
  `evidence` containing `reference_sha256`, `entry_address`, and review text.

An expected observation is `{return, memory, trace}`. Return values are raw
32-bit register bits unless `return_kind` explicitly equals `pointer`.
Memory is keyed by `region+offset` and contains exact lowercase hexadecimal
bytes. Explicit pointer observations instead contain `{bytes, pointers}`:
pointer slots are zeroed in `bytes`, with their symbolic values in `pointers`.
Only declared pointers normalize to a region plus offset, an exact image
symbol with one C prefix removed, or null. Ordinary scalars are never
normalized by their numeric value.

Symbols resolve separately in each binary, including one ordinary Mach-O C
prefix. `contracts.json` contains reference-only aliases for the six unnamed
helpers from the frozen inventory. Those addresses are available only when
the binary hash equals the pinned reference. A rebuilt binary must supply
its own symbols; an absent symbol fails.

`contracts.services` maps symbolic external targets to `boundary`
(`kernel-service` or `callback`), reviewed `evidence`, argument kinds
(`scalar` or `pointer`), and return kind. A service outcome contains `service`,
the exact normalized `arguments`, `return`, and optional ordinary-memory
`writes` (`region`, `offset`, hexadecimal `bytes`). Call traces contain
symbolic `target`, arguments and return. Bodies in the frozen driver inventory
cannot be replaced by services, including bodies outside the selected case.

A fixture memory region may name an `mmio` bank in `contracts.mmio`. A bank
lists reviewed register records (`offset`, `size`, allowed `access` kinds,
`evidence`). The ordered outcome is `{register: regionName, access, offset,
size, value}`. Read hooks supply that exact big-endian value; writes must
match it. Traces identify `region+offset`, access, size and value. Unknown
register offsets, widths, directions or event order fail. Scripted service
writes cannot bypass register hooks. No actual adapter register contract is
claimed by the synthetic bank smoke test.

Unknown control transfers, unsupported instructions, trap/privileged/cache/
barrier operations, invalid memory accesses, unused outcomes and exhausted
instruction budgets fail. Synchronization instructions are rejected for
separate review rather than replaced with no-ops.

`execute` checks every observation against the committed `expected` object.
`validate_result` rejects wrong binary, case, contract, source-revision or
runner identities; missing/skipped cases; unknown calls; or absent returns.
The runner version includes its source SHA-256 and Unicorn version. Result
documents identify selected IDs and executed instruction counts.

The CLI's `reference` and `pair` modes both verify the pinned extraction
identity. `pair` requires `--rebuilt`; each image must independently satisfy
the frozen expectations. Output is published only after all cases succeed.
Results produced before a commit are stale after that commit and must be
regenerated. The task has not run reconstructed kernels as a behavioral pair.

## Private guest builds

Follow repository `AGENTS.md` for isolation, SSH-banner readiness, QMP
ownership and snapshot restart rules. Do not reuse another task's guest.
Task 2 used `adaptecu2scsi-kbuild`, SSH 2293, QMP 4693, monitor 4793, with
`-snapshot` protecting `D:/RhapsodiOS/vm/work/rhap-i386-bootstrapped-v2.img`.
Its canonical staging root is `/private/tmp/adaptecu2scsi-task2`; private
kernel sources are beneath `src/kernel-7`. Credentials remain in the
existing local helpers and are never recorded here.

Install the matching SDK/DriverKit headers, MIG typed/untyped backends,
compiler PPC backends, config/relpath tools, PPC link libraries and Samurai
inside that private snapshot. `ninja/README.md` documents the prerequisites.
Task 2 rebuilt Samurai 1.9.0 and the PPC platform expert using their existing
project systems. The primary compiler identifies itself as Apple cc-771.4,
based on GCC 2.7.2.1. Do not copy generated products from another running guest.

From the private kernel root:

```sh
export CONFIG_DIR=/build/tools/bin
export PATH=/private/tmp/adaptecu2scsi-task2/stage/usr/bin:/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export AU2_SOURCE_REVISION=FULL_STAGED_GIT_REVISION
export AU2_SHA256=/private/tmp/adaptecu2scsi-task2/sha256sum
/bin/sh -n bsd/dev/ppc/drvAdaptecU2SCSI/tests/build-objects.sh
/bin/sh -n bsd/dev/ppc/drvAdaptecU2SCSI/tests/build-kernels.sh
/bin/sh bsd/dev/ppc/drvAdaptecU2SCSI/tests/build-objects.sh /private/tmp/au2-objects bsd/libkern/locc.c
/bin/sh bsd/dev/ppc/drvAdaptecU2SCSI/tests/build-kernels.sh /private/tmp/au2-kernels
```

Both output roots must be absolute, initially absent and outside the source
tree. They accept shell-safe path characters only. `AU2_SOURCE_REVISION`
must be the full 40-digit commit of the staged production sources; staging
and revision verification belong to the caller. `AU2_SHA256` must name a
native executable returning `64-hex-digest filename`; default `sha256sum`.
The old guest lacks SHA-256 tooling. Task 2 privately compiled Brad Conte's
public SHA-256 implementation plus a small file frontend, then verified its
output against host hashlib. That prerequisite is not a product dependency.

`build-objects.sh` prepares the existing PPC generated headers, takes compiler
flags from Samurai's generated `locc.o` command, and substitutes only the
explicit source/output paths. It never adds test objects to a kernel link.
`objects.json` has schema version 1, source revision/root, original guest
output root, hash algorithm, configuration, and `objects` records containing
source and SHA-256, relative object path and SHA-256, CPU type 18, full command
and relative log path. Copy the whole output directory to preserve its
portable relative paths. The host must independently check target layout.

`build-kernels.sh` reuses `ninja/tests/ppc.sh build` for RELEASE/DEBUG Samurai
products, then generates historical Make configurations in a separate copy.
It supplies the missing `BUILD.make/newvers` link and generates each
configuration's `assym.h` before parallel Make. It retains all four stripped
and unstripped product pairs. `builds.json` has schema version 1, source and
guest-root identities, tool/version output, commands, and eight `builds`
records: `system` (`samurai`/`make`), configuration, product, relative path,
SHA-256 and relative log path. A failure leaves logs but no success manifest.
Observe growing logs only with `ninja/tests/read-log.sh`.

The initial unchanged baseline failed before compilation because the base
guest lacked the framework's `PrivateHeaders` symlink. Its `Versions/B`
headers already existed; staging that symlink fixed the prerequisite. No
driver source was changed to address it. The task report records the clean
scratch rerun outcome and current build limitations. The object smoke check
produced `locc.c.o` as big-endian PPC Mach-O CPU type 18 with SHA-256
`C6F77F053FFDC862DFE8BC8F1F28FFC647B02264F9EBF9FCE9080C2825D67016`.
The full four-build wrapper is syntax/interface checked here; final driver
compile/link acceptance remains a later reconstruction task.
