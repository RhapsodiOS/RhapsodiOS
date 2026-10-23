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
prefix and Objective-C class/category identities from that image's metadata.
The existing source-map category aliases are retained. `contracts.json`
contains reference-only aliases for the six unnamed
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
The gate checks their independently resolved target addresses, including
alternate names at those addresses. The pinned reference additionally retains
all frozen driver extents, so an unnamed or interior alias cannot hide a body.

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
instruction budgets fail. Synchronization instructions, including `lwarx`
and `stwcx.`, are rejected for separate review rather than replaced with
no-ops. No reservation or concurrency semantics are claimed.

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
driver source was changed to address it. The unchanged clean-scratch rerun
then completed with exit 0: both Samurai RELEASE_PPC and DEBUG_PPC products,
PPC header/start-symbol checks and idle checks passed. The task report retains
the actual logs and hashes. The object smoke check
produced `locc.c.o` as big-endian PPC Mach-O CPU type 18 with SHA-256
`C6F77F053FFDC862DFE8BC8F1F28FFC647B02264F9EBF9FCE9080C2825D67016`.
The full four-build wrapper is syntax/interface checked here; final driver
compile/link acceptance remains a later reconstruction task.

## ABI stack observations

A case may supply `observe_stack`, a list of `{offset, size}` ranges relative
to entry r1. The runner bounds every read to its mapped stack and rejects
duplicate offsets. Such a case additionally observes `stack` (offset strings
to exact byte hex) and `stack_pointer` (final r1 minus entry r1). An empty
list still observes stack restoration. This supports the complete frozen
OSMSynchronizeRange register-homing contract; it does not supply stack
arguments, serialize aggregates, decode aggregate callbacks, or implement
void-result observations. Those separate convention extensions remain
required before their later behavioral cases can pass.

## Task 3 target ABI audit

`verify.py layouts --reference DIR --repo-root ROOT --objects DIR` requires
the historical PPC `layout-checks.m` object, its `objects.json`, its `1.log`,
and `header-inputs.sha256`. The latter lists SHA-256 and canonical kernel-root
relative paths for the six delivered headers, captured identically before
and after native compilation. The audit rejects changed source/header/object
bytes, missing provenance, non-PPC objects, any unexpected compiler diagnostic,
wrong callback relocations or reserved/version words, and mismatched metadata.
The two existing SDK obsolete-header warnings are the only diagnostic allowance.
The target source emits32 constant sets (535 values), all25 controller/category
method encodings, every controller ivar, and typed initializers for eight tables.

The dispatch audit binds392 CHIM declarations to their pinned addresses,
owners and individual reviewed evidence in `reconstruction/signatures.json`.
It requires the exact eleven CHIM and separate three OSM formal-erasure sets.
Tests exercise22 CHIM and six OSM varied-register reference cases, including
the complete SynchronizeRange stack writes. They do not substitute for later
paired product execution. The seven unnamed helper declarations retain the
frozen `sub_ADDRESS` inventory names for source-map and fixture resolution.

Run the Task3 gate with the task-local Python environment:

```
python -m pytest -p no:faulthandler tests/test_reconstruction.py -k 'layout or dispatch or input_erased or osm_erased'
```

Set PYTHONPATH to `tools/binrecon` from the repository root and use the actual
driver test path when invoking there. Keep build artifacts/logs outside Git.
The Task3 report identifies the exact native inputs, commit and retained outputs.

Layout and standalone dispatch audits first run the same reference-input
authentication as the inventory audit. The pinned image establishes freshly
read class/category metadata; extracted identities, function extents/names,
owner lists, ABI content and data records must agree. Each data object's
fixed extent, path, recorded size/hash and full bytes are checked against the
image, including non-callback portions of descriptor tables. Downstream
comparisons consume those checked in-memory values without reloading the
extracted metadata or tables. Validator-only changes can reuse an unchanged
native witness; its manifest retains the actual producing revision and input
hashes rather than claiming a rebuild at the validator's newer revision.

## Task 4 firmware/static-data gate

`verify.py firmware --reference OUT/reference --repo-root ROOT --objects OUT/objects/firmware`
requires both actual production PPC C objects and their manifest/header hash
closure. It authenticates the reference once, verifies all 48 envelope records,
and compares all 21 recovered CHIM definitions: exact bytes/extents/scalars,
261 symbolic nonzero pointers, null/header/reserved values, selectors and
profile/device data. The actual PPC setup instructions authenticate image
address/count metadata; field appearance alone never establishes a pointer.

Focused command: `python -m pytest tests/test_reconstruction.py -k 'firmware or descriptor' -q`.
Required named tests are `test_firmware_bytes_lengths_and_selection` and
`test_descriptor_targets_and_profile_scalars`. Native byte/target rejection
fixtures refresh the object hash and must still fail on the actual mismatch.
Forged loader metadata and unresolved final data obligations are also rejected.

The five pending OSM/controller envelopes require Task14 native verification.
All 22 switch envelopes require owning-body/control-flow reproduction and
final-analysis checking. The final gate fails while either set remains
pending; a passing Task4 gate is not complete spec3.3 data acceptance or
paired/hardware validation. The task report records actual producing
revisions, intermediate versus clean native products and commands/results.

## Task 5 service/OSD owner gates

`verify.py group --reference OUT/reference --repo-root ROOT --objects OUT/objects/task5 --group OWNER`
accepts only `AdaptecU2OSMServices.m` (37 bodies) and `AdaptecU2CHIMOSD.c`
(14 bodies). It requires the actual PPC production objects, exact owner symbol
sets, raw source/header hashes and canonical Git blobs from the actual native
producer, unchanged target layout inputs, individual source locations, reviewed
control flow and corresponding ledger artifacts. `reconstruction/task5.json`
records the seven batches, per-body native bytes/relocations/access opcodes and
direct successful fixture IDs. Unknown owners remain unimplemented failures.

`tests/task5-cases.json` freezes 199 successful reference cases. Required tests
are `test_osm_access_width_endian_and_dma_boundary`,
`test_osd_scb_encoding_all_modes` and `test_osd_completion_status`; they execute
the reference code with the actual aggregate/stack/narrow argument conventions.
Void cases omit undefined r3. The separate three OSM machine contracts retain
their exact bytes and defined register/stack effects. Internal driver callbacks
execute their actual bodies; provider-specific Objective-C dispatch rejects
frozen Ultra2 selectors and unsupported argument conventions.

The two owned switch envelopes now have source/native/control-flow evidence:
`switch_231258` and `switch_2314c0`. Their gates decode actual object table
words, normalization, guards, indexed dispatch and case/default effects, with
executed fixtures for all normalized slots and required default inputs.
Isolated negative tests reject missing/incorrect source, object, body review,
ledger and fixture evidence; an incorrect native guard still fails after all
object/proof hashes are refreshed. Five controller data envelopes and 20 other
switches remain required pending. The final gate remains closed.

Task5 native objects were produced by
`8e60bd5b71dc6f340b06cf314033ac74d1bc0626`; later test/evidence changes do not
relabel them. Current source/canonical/header closure is checked separately
from the current reference-result revision/runner hash. This is intermediate
reference execution plus PPC object/source/native review; Task16 must perform
paired execution against linked rebuilt kernels.

## Task6 hardware owner

`AdaptecU2CHIMHardware.c` supplies all 61 owned bodies. The hardware group
gate checks their exact native export set, canonical source and six-header
producing-commit closure, per-body native hashes and source locations, ledger
artifacts, and direct successful fixtures. The producing commit is
`333ab0a779a625b5455570b7e778f11baa66be64`; the native PPC big-endian object
SHA-256 is `A4C8085B3DB5951294B55B9D85B6D4F2687F4648297C248B64D1ACBD4E7D5202`.
The compiler emitted no diagnostics for this source.

`tests/task6-cases.json` contains 331 frozen reference cases, including all
four sequencer images, readback failures without successful cleanup, EEPROM
handshakes, register widths and masks, profiles, all breakpoint variants,
cable modes, an actual 8,000-transition bus-stability bound, and abort completion
paths. All internal CHIM/OSM functions and callbacks execute. The runner and
its existing service conventions are unchanged. Polling bounds are recorded
separately from physical elapsed time, which these fixtures do not establish.

`switch_230ef4` is now recovered through the actual owner source and native
compiler output. Its 144-byte native owner body matches the reference after
only the four relocated table-address immediates are normalized. The group
gate checks those relocations, the complete instruction sequence, ten native
table targets, masked/subtracted input normalization, and executed case/default
inputs. Five controller data envelopes and 19 other switch envelopes remain
pending; no other body owner is accepted by this work.

Task6 retains the actual reference execution revision in its saved result.
A subsequent evidence-only commit may reuse it only when canonical Git blobs
for the cases, contracts, runner, hardware source, six headers, and four accepted
Task4/5 source dependencies are unchanged. Their accepted native manifests and
object hashes are also checked. Task4 raw CRLF inputs and canonical Git blobs
have separate hashes. Changed executable/fixture inputs or dependencies fail
the gate; results are never relabeled to a newer revision. The public runner's
existing current-revision validation is unchanged.

Thirteen isolated mutation tests cover source, per-body review, ledger,
fixture membership, unknown internal calls, changed runner/cases/contracts,
dependency source/object, invalid execution revision, and native switch guard
or target corruption even after enclosing hashes are refreshed. These are
intermediate reference/native-object checks. Linked-kernel pairing, complete
kernel builds, and physical adapter validation remain later obligations.


## Task7 bounded full bus reset execution

The reference SCSIhScsiBusReset graph includes actual DelayCount500us calls
with counts2000 and4000. ResetScsi alone executes883124 instructions; the full
graph exceeds the previous1000000-instruction ceiling. The controller approved
an explicit per-case ceiling4000000 for evidence-backed bounded fixtures;
existing case budgets and other resource bounds remain unchanged. The full
Task7 bus-reset fixture uses that budget and executes every internal body;
unknown calls, unsupported instructions, and budget exhaustion remain fatal.
This is routine execution evidence, not elapsed-time or physical-bus proof.

### Task7 SCB owner evidence

All67 SCB/software-state bodies are control-flow-confirmed in task7.json and
the ledger. The225 frozen reference fixtures directly cover all67 entries,
execute internal CHIM/Resource/OSD callbacks, and preserve all four shipped
modes0/3/4/5. The full bus reset executes2649163 instructions with its explicit
4000000 budget; the separate reset routine executes883124 instructions.
The owner gate rejects24 isolated omissions/stale or forged evidence cases.

Native source/reference execution producer is
`deea0fd8ef1b21f13e135349da36e95871fefccd`; native object SHA-256 is
`1EC706B6721664A71B95F7261D926A279A19747FAB1DED6662C36E149A72B051`.
All67 native bodies exactly equal their individually reviewed bounded batch
objects. Source plus six canonical Git headers and five accepted source/native
dependencies are authenticated separately from the complete Python/fixture
execution dependency closure. Metadata-only reuse retains actual producing
revisions. No paired linked-kernel, physical adapter or timing claim is made.

## Task9 negotiation and transfer state

All63 owned bodies in [0x198100,0x19cb3c) are control-flow-confirmed in
task9.json and the ledger. The456 frozen reference cases directly cover all63
entries, with actual internal bodies, all four modes and exact MMIO/cache
ordering. The212 final native scalar cases include all5 normalized entries
and3 guard defaults of switch_230ec0, plus its unflagged period paths. Sixteen
critical native/reference access checks preserve byte stores, reversed
halfwords, cache lengths and both HIOB residue word publications.

Actual native producer is059ddb279776604696f391d16a96511a95dbf9f9; native
object SHA256 isA42D11C1DECE9D3EB26C21A6493FD3C2AAFCF702877F2B0FFD3C8E73574F14DD.
Actual public456case/helper producer isd641f073c6946fc6a2c4e52d4cb729c08fba9aa7.
The original CLI reference envelope is retained. Complete13input execution
closure, separate production plus six-header native closure, seven accepted
source/native dependencies and four particular owner proofs are checked;
metadata-only reuse preserves actual producers. Public current-HEAD result
validation remains strict. The scoped gate passes source/object/case/runner/
dependency/switch/import/result/relocation mutations, LF/CRLF checkouts and
native widened-store/changed-return negatives. No shared runner/type/header
or incoming-r28 exception was changed. Linked pairing, four-kernel builds,
physical validation and prior-group final freshness/portability remain later
Tasks12/15/16 obligations; see the Task9 report for exact paths and limits.

## Task12 hardware interface

Source/native/runtime input freeze78b79a22bdbdde4f6b88792bc650035590bb17c3.
All31 SCSIH bodies are in AdaptecU2CHIMHIM.c. Actual public135 cases
(6,304,724 instructions) and mixed compiled135 cases(6,305,734 instructions)
passed with exact frozen observations. Two realSCSIRInitialize context pairs
preserve explicit incomingr28 through nativeHIM/nativeConfig to MMIO255;
2 directFreeUnit no-op pairs retain the public alias-parser Task16 obligation.
Native switch graph proves all8 paths including index4/default no-sync and
indices3/7 shared-sync. Owner gate resolves146 exact snapshot permission rows
to538 raw CPU-derived operation records, actual owner/callsite/instruction
bytes and acceptedcallee proofs. tests/task12-contracts.json is exact accepted
Task11 snapshot plus isolatedTask12 additions; accepted shared inputs unchanged.

Raw outputs: OUT/objects/task12/reference-results.json and native-results.json.
Actual native compilation is608e9f5+WIP batch4 RELEASE_PPC, with all7 compiled
LF inputs separately equal canonical78b79a22b blobs. This is an intermediate
control-flow proof with pinned real reference remaining callees. Complete
Task15 four builds, Task13 nativeAPI r28 forwarding, Task16 fresh allcorpora/
linked pairs and all4-context witnesses remain mandatory. See fullTask12 report
and reconstruction/task12.json for producer identities, commands and limits.


## Task13 transport and public API

Source/runtime execution freeze5d3b106789f600dc0897003efd0d9bf8d197c020.
Transport19/API42 are recovered, all392 CHIM bodies accounted; ledger429CF
of476, map436mapped/24unmapped/16duplicate candidates, data41recovered /
2switch-pending /5controller-body-pending. task13.json binds787 frozen public
cases and787 genuine native root cases, plus2 full realAPI r28 context pairs
and2 independently mapped original private-byte pairs. Both owner gates
validate all61 bodies jointly, all11 switch envelopes, ten native tables /
401 entries, exact41 public dispatch identities/version4/168-byte bounds,
actual MMIO owner/callee/callsite/primitive attribution and store widths.

Actual native producers remain distinct: base926+WIP b10Transport andb9API;
each actual compiled source+6headers matches canonical5d LF blobs. The old
b9Transport warning/object remains rejecting evidence: original private
uninitialized qualifier was wrongly allocated to incomingr27, so minimal
volatile BYTE storage now materializes the original private machine byte.
No default/formal or after-entry register/stack patch was introduced.
Exact pre-entry byte127/53 witnesses produce37/32 after realcallback48->1.

Public raw SHA8682A7165634C97B0FE6459984937A1BA25B42660F76C4B3F274C73942727672;
native raw E022F0C4B2B670AFA9E982670D9B6A70D326C07B8A342002F5345C5C259EF816.
Supplementary six-object arena includes genuine Tables/HIM/Resource/Config;
remaining callees execute pinned reference code. Exact getter-only external
copy adaptation derives its output from the genuine relocated native table;
privileged fast_bcopy/memcpy is not claimed executed. Public ABI parser adds
only CHIM.h strict discovery and exactPciLocation16 mapping. Older current
owner gates fail contracts/runner freshness, with raw evidence unchanged.
Task16 fresh consolidated runtime/allcorpora and all4 independently mapped
fullnative builds/context pairs remain mandatory; see Task13 report for
actual commands/results, accepted rulings, source reviews and inherited limits.

## Task16 linked-kernel verification

Evidence is in `reconstruction/task16.json`; scripts and raw outputs are in
`vm/work/au2-t16` (outside git). Nothing here needs a guest: both kernels are
read from disk.

- Reference: MOSXS 1.2v3 `mach_kernel`, cksum `3765629243 2983828`, SHA-256
  `D01D748C...6494BD`.
- Rebuilt: the Task15 PPC kernel from `f7765cdb5`, cksum `3685141911 3056040`,
  SHA-256 `A9AA8B26...4C708B0B`. Its 22 driver sources equal this tree.

### Body comparison

`cmp476.py <kernel>` compares all 476 driver bodies of the linked kernel
with the reference, mapped by symbol, by ObjC method IMP for the 25 methods,
and by `_sub_XXXXXX` symbol for the seven unnamed helpers. It reuses the
Task14 normalization: calls, symbols, strings and selectors resolve by name,
and the two unnamed statics (`request_message`, `event_names`) by the code
that uses them. Classes: exact; registers-only (register choice, spill
slots and frame size); reordered (same basic blocks, instructions reordered
inside them); differs.

| Class | Bodies |
|---|---:|
| exact | 160 |
| registers-only | 25 |
| reordered | 20 |
| differs | 271 |

The 271 differing bodies were triaged in three groups:

- 122 have the same calls, symbol references, memory accesses and
  constants (as multisets) in a different block layout.
- 103 have the same call sequence on every CFG path (NFA language
  equality over calls, checked with a mutation self-test) and the same
  sets of accesses and constants. Most of the remaining differences are
  reloads and base+offset folding.
- 46 were reviewed by hand. Three are the Task14 labelled divergences
  (`-threadExecuteRequest:`, `NormalPostRoutine`, `ProbeTarget`). The
  other 43 are compiler differences: stack temporaries for byte-reversed
  accesses, base+offset folding, jump tables compiled as compare chains,
  tail merging, and a byte-swapped constant folded at compile time. One
  harmless source difference: `SCSIClearTargetTSH` passes `&adapter->hhcb`
  where the reference passes `target->unit.hhcb`, the same pointer once the
  unit handle is set, and the callee ignores the argument.
  `SCSIGetNVOSMSegment` computes the SEEPROM length unsigned where the
  reference uses signed, which is harmless because the size is 0, 64 or
  128. Each reason is in `task16.json`.

No real behavioral difference was found, so no source changed and no new
divergence was added. The 47 OSM/controller ledger rows are now
control-flow-confirmed, or intentional-mismatch for the three divergences,
with `task16.json` as their artifact.

### Frozen cases on the linked kernel

`runcases.py` runs every frozen corpus with the unchanged `ppc_cases.run_case`,
on the reference and on the linked kernel. For the rebuilt image it changes
three things:

- Body extents are the rebuilt image's own.
- The two contract-aliased objects are named at their rebuilt addresses:
  `event_names`, which is byte- and pointer-equal, and the `IODevice`
  class-name string.
- It seeds the incoming r28 and the PostBusScan private byte the same way
  the Task12/13 runners do.

| Corpus | Cases | Reference | Rebuilt |
|---|---:|---|---|
| reference, task5-8 | 1004 | pass | pass |
| task9 | 456 | pass | pass |
| task9-ack | 2 | pass | not run (the runner allows ACK exhaustion only on the pinned reference) |
| task10, task11 | 382 | pass | pass |
| task12 | 135 | pass | 126 pass; 9 differ only in the undeclared HHCB+244 hardware-table pointer (0x278cf4 against 0x290880, both `SCSIHardwareAICBayonet`) |
| task12/13 context, task13 stack | 6 | pass | pass |
| task13 | 787 | pass | 785 pass; 2 `SCSIGetFunctionPointers` getter cases need the reference-only scripted table copy (the body is exact; the table matches by pointer target) |
| task13-fix1 | 22 | pass | pass |

The frozen cases enter 427 of the 476 bodies directly and 9 more as
internal callees, including all 43 compiler-differing hand-reviewed bodies.
The 40 that are never executed are controller/OSM methods and lifecycle
routines, which have only the static comparison above.

### Data parity

`datacheck.py <kernel>` compares every `data.json` object in the linked
kernel byte for byte. Pointer slots are compared by their target's name or
string. All 25 non-switch objects are equal: the four `_Seq_*` firmware
arrays, all CHIM tables (including `SCSIFuncPtrs`, `SCSIHardware*` and
`SCSIFirmware*` by pointer target), `OSMRoutines`, `adapterQ`,
`request_message` and `event_names`. The diagnostic literal pool is checked
through each consumer's string references in the body comparison. The 22
compiler switch tables are checked through their owning bodies. All 48
data objects are now recovered.

### Task13 concerns

The "stale result" and "uncommitted input" gate failures listed in the
Task13 report are freshness checks on harness identity hashes. Removing the
fixture JSON from git history makes them permanent. They do not indicate a
behavioral problem, and the fresh linked-kernel runs above replace them. The
Task11 volatile-qualifier warning in `SCSIrAsyncEventCommand` is still in the
Task15 build and is harmless. The "four native builds" obligation is met by
the single linked kernel. The `task13-fix1.json` proof was never committed,
so `test_fix1_canonical_proof_and_runtime_identity` still fails.

### Tests

`tests/conftest.py` hard-links the stripped fixtures from `AU2_FIXTURES`
for the session. Tests whose fixtures or generated
`tools/binrecon/out` evidence are absent skip, with the missing path as the
reason. Two tests that pinned the pre-Task14 draft `OSMFunctions.m` were
removed. The Task13 delta test now reads the Task13 acceptance commit
`55e348168` and checks the current map at 469 mapped, 7 unmapped and 0
duplicates.

### Not verified

- Runtime on hardware or in an emulated machine: probe, DMA, interrupts,
  timing and concurrency.
- The 40 bodies the frozen cases never execute, beyond the static comparison.
- The two ACK-exhaustion cases on the rebuilt image.
- Tests that need `tools/binrecon/out`, which is not present here.
