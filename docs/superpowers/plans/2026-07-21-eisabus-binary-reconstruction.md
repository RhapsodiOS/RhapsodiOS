# EISABus Binary-First Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct the i386 EISABus kernel server from the known-good reference, eliminate its kernel crash, restore ISA Plug-and-Play enumeration/configuration, repair PnPDump, and match the relocated binary byte-for-byte.

**Architecture:** Use the completed `tools/binrecon` pipeline to establish immutable reference identity, three-analyzer consensus, and a per-function ledger. Restore ABI and functions in reference dependency order, accepting only evidence-backed edits. Gate physical hardware behind static parity, deterministic resource-stream tests, and repeated QEMU no-crash boots.

**Tech Stack:** Rhapsody i386 DriverKit/Objective-C, NeXT Project Builder makefiles, IDA 9.2, Ghidra 12.1, angr 9.3.0, Python 3.12+, existing PuTTY/QEMU guest workflow.

**Spec:** [docs/superpowers/specs/2026-07-21-eisabus-binary-reconstruction-design.md](../specs/2026-07-21-eisabus-binary-reconstruction-design.md)

**Prerequisite:** Complete [2026-07-21-binrecon-toolkit.md](2026-07-21-binrecon-toolkit.md).

---

## File structure

| Path | Responsibility |
|------|----------------|
| `src/drivers/x86/bus/drvEISABus/reconstruction/profile.json` | External reference, build artifact, analyzer, and acceptance configuration |
| `src/drivers/x86/bus/drvEISABus/reconstruction/source-map.json` | Reference address to source symbol/file mapping |
| `src/drivers/x86/bus/drvEISABus/reconstruction/abi.json` | Structure, class, global, selector, and section expectations |
| `src/drivers/x86/bus/drvEISABus/reconstruction/ledger.json` | Reviewed function parity status |
| `src/drivers/x86/bus/drvEISABus/reconstruction/captures/` | Non-proprietary PnP byte streams and expected summaries |
| `src/drivers/x86/bus/drvEISABus/reconstruction/README.md` | Baseline, build, QEMU, and physical A/B procedures |
| `src/drivers/x86/bus/drvEISABus/EISABus.drvproj/EISABus.lksproj/` | Reconstructed kernel-server source |
| `src/drivers/x86/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/` | Restored native diagnostic tool |

Generated IDA/Ghidra/angr exports, logs, binaries, and crash dumps go under `tools/binrecon/out/eisabus` and remain ignored.

---

### Task 1: Freeze the reference and create the EISABus profile

**Files:**
- Create: `src/drivers/x86/bus/drvEISABus/reconstruction/profile.json`
- Create: `src/drivers/x86/bus/drvEISABus/reconstruction/README.md`
- Create: `src/drivers/x86/bus/drvEISABus/reconstruction/source-map.json`
- Create: `src/drivers/x86/bus/drvEISABus/reconstruction/ledger.json`

- [ ] **Step 1: Write the profile with exact identities**

Use `${EISABUS_REFERENCE}` as the bundle directory and require:

```json
{
  "EISABus": {"size": 25792, "sha256": "8192FDA61EEE306A655966FBFF5FB4FF5E4932C44933B2495ED1121022A0830F"},
  "EISABus_reloc": {"size": 100752, "sha256": "8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23"},
  "PnPDump": {"size": 59260, "sha256": "006DC6BB73CEBC6243DA669E5199AEC808F309E72C3EE617A3FD8ED310364772"}
}
```

Configure i386 little-endian, IDA/Ghidra/angr required, `EISABus_reloc` exact-image acceptance, and final `EISABus` comparison without making exact final image a blocking requirement.

- [ ] **Step 2: Validate the reference**

```powershell
$env:EISABUS_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config'
$env:PYTHONPATH='tools/binrecon'
python -m binrecon validate --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json
```

Expected: all three names, sizes, and hashes match.

- [ ] **Step 3: Generate baseline analysis**

```powershell
python -m binrecon analyze --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json
python -m binrecon consensus --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json
python -m binrecon ledger --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json --initialize
```

Expected: 144 Objective-C methods reported by the IDA baseline, analyzer disagreements enumerated, and every ledger entry initially `unexamined`.

- [ ] **Step 4: Map symbols to existing source**

Populate `source-map.json` only when a reference function has one unambiguous source function. Unmapped, duplicate, and boundary-disputed functions remain explicit arrays in the file and block later parity status.

- [ ] **Step 5: Document the external-artifact rule and commit**

```powershell
git add src/drivers/x86/bus/drvEISABus/reconstruction
git commit -m "drivers: add EISABus reconstruction baseline"
```

---

### Task 2: Establish a reproducible current build and crash baseline

**Files:**
- Modify: `src/drivers/x86/bus/drvEISABus/reconstruction/README.md`
- Modify only if evidence requires it: `src/drivers/x86/bus/drvEISABus/EISABus.drvproj/EISABus.lksproj/Makefile.preamble`

- [ ] **Step 1: Sync the exact source and build orchestration**

```powershell
& vm\rhap-vm.ps1 sync
& vm\rhap-vm.ps1 ssh 'cd /build/source/ninja && gnumake all RC_ARCHS=i386'
```

- [ ] **Step 2: Build the project through staged dependencies**

Generate `build.ninja` and invoke the project-directory phony target rather than compiling the leaf project against unstaged headers:

```powershell
& vm\rhap-vm.ps1 ssh 'cd /build/source && grep -n "drvEISABus" build.ninja'
& vm\rhap-vm.ps1 ssh 'cd /build/source && ninja/samurai/samu src/drivers/x86/bus/drvEISABus'
```

Record the generated edge and its resolved dependency stamps in `reconstruction/README.md`.

- [ ] **Step 3: Preserve current build identities**

Copy current `EISABus` and `EISABus_reloc` to the configured generated-output directory, run `binrecon compare`, and save the report hash in the ledger. Do not commit binaries.

- [ ] **Step 4: Reproduce the crash in QEMU three times**

Boot the same image/configuration with the reconstructed module, enable serial capture and QEMU exception/I/O logging, and record faulting EIP, exception, CR2 when relevant, module load address, and last matched reference function. Then boot the reference module with identical configuration and capture the corresponding path.

- [ ] **Step 5: State the first root-cause hypothesis**

Add one evidence-backed hypothesis to `README.md` in this form:

```text
First divergence: reference address and mapped source function
Observed state: reference/reconstructed value pairs from the trace
Root-cause hypothesis: one specific ABI, control-flow, data, or I/O mismatch
Minimal parity gate that will falsify it: one named comparison or replay test
```

Do not edit driver code in this task.

- [ ] **Step 6: Commit evidence documentation**

```powershell
git add src/drivers/x86/bus/drvEISABus/reconstruction/README.md
git commit -m "docs: record EISABus build and crash baseline"
```

---

### Task 3: Restore binary layout and ABI foundation

**Files:**
- Modify as proven: every header in `EISABus.lksproj`
- Modify as proven: `Load_Commands.sect`
- Modify as proven: `biospnp.s`
- Modify: `src/drivers/x86/bus/drvEISABus/reconstruction/abi.json`
- Modify: `src/drivers/x86/bus/drvEISABus/reconstruction/ledger.json`

- [ ] **Step 1: Add failing ABI probes**

Generate a temporary guest-only Objective-C/C probe from `abi.json` that prints `sizeof`, field offsets, class instance sizes, selector type encodings, and global widths. Compare it to sizes and offsets inferred independently by IDA/Ghidra and reference access instructions.

- [ ] **Step 2: Run the probe and retain the failing report**

Expected before corrections: every mismatch is listed by type and offset; a clean report is also valid evidence and moves this task directly to section layout.

- [ ] **Step 3: Correct one ABI mismatch at a time**

For each failing entry, change only its declaration, packing, signedness, or field order. Rebuild the probe after each change. Never reorder fields to improve readability. Preserve `pnp_bios_install_struct` at exactly 0x21 bytes and verify every field offset from reference loads/stores.

- [ ] **Step 4: Match assembly bridge and sections**

Compare `biospnp.s`, load commands, segment protections, generated instance source, class/category metadata, globals, and source/link order. Correct only differences visible in the report.

- [ ] **Step 5: Rebuild and run normalized comparison**

```powershell
python -m binrecon compare --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json --require normalized-functions
```

Advance ABI and bridge functions through `signature-confirmed` and `control-flow-confirmed`; use `assembly-matched` only on a clean function report.

- [ ] **Step 6: Commit**

```powershell
git add src/drivers/x86/bus/drvEISABus/EISABus.drvproj/EISABus.lksproj src/drivers/x86/bus/drvEISABus/reconstruction
git commit -m "drivers: restore EISABus binary ABI"
```

---

### Task 4: Reconstruct low-level EISA and ISA PnP primitives

**Files:**
- Modify: `EISABus.lksproj/eisa.c`
- Modify: `EISABus.lksproj/eisa.h`
- Modify: `EISABus.lksproj/bios.c`
- Modify: `EISABus.lksproj/bios.h`
- Modify: `EISABus.lksproj/EISAKernBusPortRange.m`
- Modify: related reconstruction artifacts

- [ ] **Step 1: Create failing pure-function parity checks**

Add angr checks and concrete fixture tests for EISA ID conversion/matching, initiation-key generation, isolation checksum, and resource checksum. Require reference and rebuilt functions to produce equal return values and writes for all bounded symbolic inputs.

- [ ] **Step 2: Create failing port-trace checks**

Represent `outb`, `inb`, delay/barrier, and sleep as hooks that append `(operation, width, port, value)` events. Compare reference and rebuilt traces for register read/write, wake, reset-CSN, set-read-port, isolation, assign-CSN, and activate/deactivate sequences.

- [ ] **Step 3: Transliterate mismatched functions in reference address order**

For each function, use the consensus report to lock boundaries, inspect every reference basic block, preserve access width and branch order, edit only that source function, and rerun its focused check before proceeding.

- [ ] **Step 4: Verify complete primitive group**

Require no unexplained IDA/Ghidra/angr disagreements and no port-trace differences. Rebuild the kernel server and compare normalized assembly.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers/x86/bus/drvEISABus
git commit -m "drivers: reconstruct EISA and PnP hardware primitives"
```

---

### Task 5: Reconstruct scalar resource classes

**Files:**
- Modify: `EISABus.lksproj/pnpIRQ.h`
- Modify: `EISABus.lksproj/pnpIRQ.m`
- Modify: `EISABus.lksproj/pnpDMA.h`
- Modify: `EISABus.lksproj/pnpDMA.m`
- Modify: `EISABus.lksproj/pnpIOPort.h`
- Modify: `EISABus.lksproj/pnpIOPort.m`
- Modify: `EISABus.lksproj/pnpMemory.h`
- Modify: `EISABus.lksproj/pnpMemory.m`

- [ ] **Step 1: Capture constructor and matcher vectors**

For every supported small/large resource descriptor, record input bytes, object fields, accessor results, match result, and emitted configuration bytes from the reference. Include boundary masks, empty choices, fixed/ranged ports, 24-bit memory, and 32-bit memory descriptors.

- [ ] **Step 2: Run vectors against current source and require failure for every known divergence**

The harness reports source class, constructor selector, differing field offset/value, and reference function address.

- [ ] **Step 3: Reconstruct in reference link/address order**

Preserve allocation sizes, ivar order, byte shifts, signed comparisons, boolean normalization, and free paths. Rerun the one-class vector set and normalized assembly comparison after each class.

- [ ] **Step 4: Run group verification and commit**

```powershell
python -m binrecon compare --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json --require normalized-functions
git add src/drivers/x86/bus/drvEISABus
git commit -m "drivers: reconstruct EISABus scalar resources"
```

---

### Task 6: Reconstruct aggregate resources and logical devices

**Files:**
- Modify: `EISABus.lksproj/PnPResource.h`
- Modify: `EISABus.lksproj/PnPResource.m`
- Modify: `EISABus.lksproj/PnPResources.h`
- Modify: `EISABus.lksproj/PnPResources.m`
- Modify: `EISABus.lksproj/PnPDependentResources.h`
- Modify: `EISABus.lksproj/PnPDependentResources.m`
- Modify: `EISABus.lksproj/PnPLogicalDevice.h`
- Modify: `EISABus.lksproj/PnPLogicalDevice.m`
- Modify: `EISABus.lksproj/PnPDeviceResources.h`
- Modify: `EISABus.lksproj/PnPDeviceResources.m`

- [ ] **Step 1: Add failing resource-stream fixtures**

Use reference-captured streams containing multiple logical devices, compatible IDs, start/end dependent functions, priorities, ANSI names, IRQ/DMA/port/memory combinations, and end tags. Expected JSON records exact object ordering and values.

- [ ] **Step 2: Add malformed and boundary streams derived from valid captures**

Truncate each descriptor at every byte boundary, corrupt the checksum, omit end-dependent/end-tag descriptors, and exceed reference lengths. Expected behavior is copied from reference outcomes, including reference failures.

- [ ] **Step 3: Reconstruct one class at a time**

Follow `PnPResource -> PnPResources -> PnPDependentResources -> PnPLogicalDevice -> PnPDeviceResources`. Preserve List ownership, object insertion order, dependent-function indexing, compatible-ID representation, and parser cursor advancement.

- [ ] **Step 4: Verify no leaks or double frees on reference error paths**

Use allocation/free hooks in the replay harness and require the same live-object count and cleanup order as the reference.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers/x86/bus/drvEISABus
git commit -m "drivers: reconstruct EISABus PnP resource parsing"
```

---

### Task 7: Reconstruct PnP BIOS transport

**Files:**
- Modify: `EISABus.lksproj/PnPArgStack.h`
- Modify: `EISABus.lksproj/PnPArgStack.m`
- Modify: `EISABus.lksproj/PnPBios.h`
- Modify: `EISABus.lksproj/PnPBios.m`
- Modify: `EISABus.lksproj/biospnp.s`

- [ ] **Step 1: Add failing argument-stack vectors**

Verify reset, word push, far-pointer push, selector/offset order, capacity boundary, and final stack pointer against reference memory writes.

- [ ] **Step 2: Add a mocked BIOS-call transcript**

Hook GDT access, selector allocation, wired-memory allocation, BIOS entry, and copy operations. Cover `Present`, init/free, `getDeviceNode`, `getNumNodes`, `getPnPConfig`, setup, every partial setup failure, and repeated release.

- [ ] **Step 3: Reconstruct segment setup and restoration first**

Match descriptor bytes, selector indices, access bits, saved GDT values, self-modifying call targets, buffer size/alignment, and reverse-order cleanup before reconstructing higher-level BIOS methods.

- [ ] **Step 4: Reconstruct BIOS methods and verify transcripts**

Preserve BIOS function numbers, argument order, handle update, returned size semantics, and error codes.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers/x86/bus/drvEISABus
git commit -m "drivers: reconstruct EISABus PnP BIOS transport"
```

---

### Task 8: Reconstruct bus initialization, matching, allocation, and programming

**Files:**
- Modify: `EISABus.lksproj/EISAKernBus+PlugAndPlayPrivate.h`
- Modify: `EISABus.lksproj/EISAKernBus+PlugAndPlayPrivate.m`
- Modify: `EISABus.lksproj/EISAKernBus+PlugAndPlay.h`
- Modify: `EISABus.lksproj/EISAKernBus+PlugAndPlay.m`
- Modify: `EISABus.lksproj/EISAKernBus.h`
- Modify: `EISABus.lksproj/EISAKernBus.m`

- [ ] **Step 1: Add failing initialization transcripts**

Cover PnP BIOS present/absent, configured read port, automatic read-port scan, zero/one/multiple cards, checksum failure, and logical-device deactivation. Assert global values, card-table keys, message order, and port transcript.

- [ ] **Step 2: Add failing lookup/allocation vectors**

Cover card ID, logical-device ID, compatible ID, repeated instances, dependent configurations, unavailable resources, shareable IRQ, DMA constraints, alignment, allocation rollback, and reprogramming.

- [ ] **Step 3: Reconstruct private category in reference order**

Start with initialization and card-table construction, then allocation search, then register programming. Re-run the focused transcript after each function.

- [ ] **Step 4: Reconstruct public category exactly**

Keep `readSystemNode:length:forNode:` as the reference `NO` stub. Match CSN and logical-device bounds, HashTable key casts, compatible-ID iteration, instance counting, output initialization, and return object.

- [ ] **Step 5: Reconstruct main bus lifecycle**

Match probe/init/free, resource reservation, interrupt/DMA/port helper construction, device-description allocation, and publish order.

- [ ] **Step 6: Commit**

```powershell
git add src/drivers/x86/bus/drvEISABus
git commit -m "drivers: reconstruct EISABus PnP orchestration"
```

---

### Task 9: Reconstruct resource-driver and helper classes

**Files:**
- Modify: `EISABus.lksproj/EISAKernBusDMAChannel.*`
- Modify: `EISABus.lksproj/EISAKernBusInterrupt.*`
- Modify: `EISABus.lksproj/EISAKernBusPortRange.*`
- Modify: `EISABus.lksproj/EISAResourceDriver.*`

- [ ] **Step 1: Add failing DriverKit-message transcripts**

Cover resource insertion/removal, sharing flags, boot flag, parameter-name dispatch, EISA slot/function data, PnP card/device config reads, system-node stub result, ID lookup, and set-parameter operations.

- [ ] **Step 2: Reconstruct helpers before the resource driver**

Match superclass initialization, resource/item indexes, ownership, read/write access widths, interrupt attach/detach, DMA assignment, and free behavior.

- [ ] **Step 3: Reconstruct `EISAResourceDriver` dispatch**

Preserve parameter string comparisons, count semantics, output layout, and exact error codes. Verify every switch branch against the reference transcript.

- [ ] **Step 4: Run full normalized function comparison and commit**

```powershell
python -m binrecon compare --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json --require normalized-functions
git add src/drivers/x86/bus/drvEISABus
git commit -m "drivers: reconstruct EISABus DriverKit resources"
```

---

### Task 10: Restore PnPDump

**Files:**
- Create: `EISABus.drvproj/PnPDump.tproj/PnPDump.m`
- Modify: `EISABus.drvproj/PnPDump.tproj/Makefile`
- Modify: `EISABus.drvproj/PnPDump.tproj/PB.project`
- Modify as reference requires: existing PnPDump support sources
- Modify: `EISABus.drvproj/Makefile`

- [ ] **Step 1: Map the 59,260-byte reference tool**

Run all three analyzers, inventory classes/functions/imports/strings, and map existing `dumpConfig.m`, `IODeviceMaster`, `NXLock`, and `R.m`. Determine whether `PnPDump.m` is missing source, an expected generated/renamed unit, or a stale project-list entry from binary evidence.

- [ ] **Step 2: Add a failing build gate**

Uncomment `PnPDump.tproj` in the parent `TOOLS` list only on the test branch, build through staged headers/frameworks, and retain the exact missing-source/link/runtime error.

- [ ] **Step 3: Restore source and project inputs from the reference map**

Create `PnPDump.m` only if the binary map proves it is a distinct translation unit; otherwise correct the project metadata to the proven source name. Match class layout, calls, output strings, and source/link order.

- [ ] **Step 4: Verify native output shape**

Run reference and rebuilt `PnPDump` against the reference module in QEMU. Normalize only volatile addresses and timestamps; require identical card/device/resource fields and ordering.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers/x86/bus/drvEISABus/EISABus.drvproj
git commit -m "drivers: restore PnPDump diagnostics"
```

---

### Task 11: Close function and relocated-image parity

**Files:**
- Modify: any EISABus source/build file with a classified mismatch
- Modify: reconstruction ledger and build manifest

- [ ] **Step 1: Require every function to leave `unexamined`**

No disputed boundary, unmapped function, unknown selector, or unexplained global may remain. Intentional reference stubs must still reach `assembly-matched` when source reproduces them.

- [ ] **Step 2: Classify every relocated-image mismatch**

Run exact comparison and group remaining differences into code, relocation, symbol/string ordering, layout, padding, or metadata. Resolve groups in that order, one build change at a time.

- [ ] **Step 3: Require exact relocated image**

```powershell
python -m binrecon compare --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json --require exact-image --artifact EISABus_reloc
```

Expected: size `100752`, SHA-256 `8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23`, exit 0.

- [ ] **Step 4: Compare final loadable image**

Require a complete classified report. If exact, record size `25792` and SHA-256 `8192FDA61EEE306A655966FBFF5FB4FF5E4932C44933B2495ED1121022A0830F`; if not exact, retain the non-code classification without weakening runtime gates.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers/x86/bus/drvEISABus
git commit -m "drivers: match EISABus reference binary"
```

---

### Task 12: Run QEMU no-crash and enumeration gates

**Files:**
- Modify: `src/drivers/x86/bus/drvEISABus/reconstruction/README.md`

- [ ] **Step 1: Create immutable reference/rebuilt VM snapshots**

Use identical kernel, driver set, and VM arguments; change only `EISABus.config`. Record hashes installed in each snapshot.

- [ ] **Step 2: Run ten cold boots and ten module-load cycles**

Require no panic, trap, hang, selector corruption, or leaked resource reservation. Compare initialization path and port-I/O trace with reference.

- [ ] **Step 3: Run PnP enumeration or replay**

If QEMU exposes ISA PnP, require identical `PnPDump`. Otherwise run the complete captured-stream suite in the guest and state explicitly that QEMU provides kernel stability plus replay coverage, not physical enumeration coverage.

- [ ] **Step 4: Verify dependent drivers and ordinary boot devices**

Storage, console, network, and unrelated bus enumeration must remain operational.

- [ ] **Step 5: Document evidence and commit**

```powershell
git add src/drivers/x86/bus/drvEISABus/reconstruction/README.md
git commit -m "docs: record EISABus QEMU qualification"
```

---

### Task 13: Qualify physical Sound Blaster hardware

**Files:**
- Modify: `src/drivers/x86/bus/drvEISABus/reconstruction/README.md`
- Create: non-proprietary captures under `reconstruction/captures/physical/`

- [ ] **Step 1: Capture the reference baseline**

Cold boot each available Sound Blaster card with the reference module. Record discovered card ID, serial number, logical-device IDs, compatible IDs, resource alternatives, selected IRQ/DMA/I/O/memory, consuming-driver attachment, and working audio operation.

- [ ] **Step 2: Test reconstructed module with one card**

Change only EISABus, cold boot, and require byte-for-byte normalized `PnPDump` equivalence plus the same attached audio driver and working playback/record functions supported by that card.

- [ ] **Step 3: Repeat all cards and warm boots**

Run at least three cold and three warm boots per card. Any intermittent isolation or cleanup difference returns work to the first divergent function; do not add retries without reference evidence.

- [ ] **Step 4: Record anonymized captures and final matrix**

Commit PnP IDs/resource bytes and expected summaries, but exclude machine serials, unrelated firmware data, full memory dumps, and proprietary binaries.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers/x86/bus/drvEISABus/reconstruction
git commit -m "docs: qualify EISABus on physical PnP hardware"
```

---

### Task 14: Final verification and handoff

**Files:**
- Modify only for factual corrections: both reconstruction READMEs and ledgers

- [ ] **Step 1: Run all binrecon tests**

```powershell
$env:PYTHONPATH='tools/binrecon'
python -m pytest tools/binrecon/tests -q
```

- [ ] **Step 2: Revalidate reference, consensus, ledger, and exact relocated image**

```powershell
python -m binrecon validate --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json
python -m binrecon consensus --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json
python -m binrecon ledger --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json --check
python -m binrecon compare --profile src/drivers/x86/bus/drvEISABus/reconstruction/profile.json --require exact-image --artifact EISABus_reloc
```

- [ ] **Step 3: Rebuild from a clean guest staging tree**

Remove only the documented per-project source/object/symbol/package roots, regenerate the build graph, and rebuild EISABus/PnPDump. Re-run hashes to prove the result does not depend on stale objects.

- [ ] **Step 4: Review runtime evidence**

Confirm QEMU repetitions, physical card matrix, dependent audio attachment, and no unrelated boot regression are all recorded with exact artifact hashes.

- [ ] **Step 5: Check repository cleanliness and commit factual corrections**

```powershell
git diff --check
git status --short
```

Do not stage unrelated pre-existing changes.

---

## Spec coverage

| Requirement | Tasks |
|-------------|-------|
| Immutable reference identity | 1 |
| Three-analyzer map and ledger | 1, 3-11 |
| Root-cause-first crash investigation | 2 |
| ABI and section parity | 3 |
| Hardware primitive parity | 4 |
| Resource representation and parsing | 5-6 |
| PnP BIOS transport | 7 |
| Bus initialization, matching, allocation, programming | 8-9 |
| Intentional `readSystemNode` stub preserved | 8 |
| PnPDump restored | 10 |
| Byte-identical `EISABus_reloc` | 11, 14 |
| Final `EISABus` comparison | 11 |
| QEMU stability | 12, 14 |
| Physical Sound Blaster A/B qualification | 13-14 |
| No proprietary reference artifacts committed | 1, 10, 13 |
