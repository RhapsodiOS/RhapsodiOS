# drvBPF and drvPortServer Binary Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map every function in Apple's shipped `BPF_reloc` and `PortServer_reloc` to our source, record the divergences, then fix them driver by driver.

**Architecture:** Each driver gets a *report pass* — run the three analyzers, build a `source-map.json` partitioning every reference function into mapped/unmapped/disputed/duplicate buckets, disassembly-diff the mapped ones, diff the shipped config table and strings file, then write `divergences.md` and `ledger.json` — followed by a separate *fix pass*. There is no guest build and no compile gate; the fix pass is verified by re-reading each repaired function against the reference disassembly and re-validating the source map. Smallest driver first, carried all the way through before the second starts.

**Tech Stack:** Python 3.13.9, binrecon (`tools/binrecon`), IDA Professional 9.2, angr 9.3.0 (Ghidra 12.1 disabled — see Global Constraints), pytest 9.1.1, jsonschema 4.26.0.

**Spec:** `docs/superpowers/specs/2026-07-25-bpf-portserver-binary-reconstruction-design.md`

**Prior art:** `docs/superpowers/plans/2026-07-25-intel-bus-driver-binary-reconstruction.md` and `docs/superpowers/plans/2026-07-25-bus-driver-binary-reconstruction.md` did this job for five other i386 drivers. Their conventions are reused unchanged. **Read `src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md` before Task 3** — it is the worked example this plan's reports should resemble.

## Global Constraints

- **This plan executes in a git worktree at `D:/RhapsodiOS/.claude/worktrees/bpf-portserver-reconstruction` on branch `bpf-portserver-reconstruction`,** branched from `748c0be9`. A second session is concurrently editing `binrecon`'s analyzer adapters in the main tree; the worktree exists to keep this plan's analyses and review diffs uncontaminated. Do not `cd` to `D:/RhapsodiOS`, and do not merge or rebase onto `qemu-debug-loop` during execution.
- Python is 3.13.9. The venv is untracked and lives only in the main tree, so invoke it by **absolute path**: `/d/RhapsodiOS/.venv-binrecon/Scripts/python.exe`. Wherever a step below writes `./.venv-binrecon/Scripts/python.exe`, use the absolute path instead. The binrecon README names 3.12; 3.12 is not installed on this host and the pinned dependencies all install and pass on 3.13.9. **Do not change the pins.**
- Every binrecon invocation needs `PYTHONPATH=tools/binrecon` and runs from the worktree root. With that set, the main tree's interpreter loads the worktree's `binrecon` package — verified.
- **Test baseline is 662 passed, 4 skipped, 0 failed (666 collected).** Verify with `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`. Any failure you see is yours.
- **`binrecon ledger` fails silently without `BINRECON_REFERENCE`.** It prints `reference artifact: artifact variable BINRECON_REFERENCE is not set` to stderr and then **exits 0**, so a scripted loop of ledger updates reports success while writing nothing. Every `binrecon ledger` invocation below is prefixed with the variable for this reason — keep it. After any batch of ledger writes, re-read the ledger and assert the entry count and status distribution rather than trusting exit codes. This bit Task 4 and would bite Task 6 far harder, where 113 entries are written.
- **This plan adds no tests, by design** — it adds no code to `binrecon`. A task that ends with the baseline unchanged is correct, not a coverage gap.
- IDA `version` must be `9.2`; Ghidra `version` must be `12.1` with a Java 21 `java.exe`. The adapters reject other versions.
- **Ghidra is disabled in both profiles.** It cannot analyze either reference binary: its raw-i386 fallback import fails validation with `external relocation symbol association is missing`, deterministically, on both `BPF_reloc` (40 undefined externals) and `PortServer_reloc` (59). Java 21 and Ghidra 12.1 are both installed and working — this is not an environment fault. Repairing it means editing `adapters/ghidra.py` and `adapters/ghidra/ExportAnalysis.java`, which is outside this plan's scope and collides with concurrent work in the main tree. Precedent for running without Ghidra: the `parallelport`, `ps2keyboard`, `serialpointingdevice`, `vga-psdrvr`, and `kernel-driverkit` runs. **Consequence to record in both `divergences.md` files:** cross-analyzer boundary checking rests on IDA versus angr alone, and angr's `CFGFast` is the weaker of the two, so `boundary_disputed` is less sensitive than a three-analyzer run would be. IDA remains authoritative for the function partition, which is what every source-map step already uses.
- Reference binaries live under `C:\Users\raynorpat\Downloads\test\Drivers\i386` and are **never** committed.
- **Never point a profile's `rebuilt` at the reference.** That is what produced the false `exact-image` pass in the retired `tools/binrecon/out/eisabus/` run. Both profiles here are reference-only: they omit `rebuilt` entirely.
- Architecture is `i386`, endianness `little`, for both profiles.
- `source-map-v1` `reference_sha256` and all hashes use the pattern `^[0-9A-F]{64}$` — **uppercase**.
- `source_path` in a source map must be a canonical repo-relative **POSIX** path: forward slashes only, not absolute, no `.` or `..` parts, no drive letter.
- Every source-map category array must be sorted by `(address, tuple(reference_names))`, and every `reference_names` and `reasons` array must be sorted and unique. The semantic validator rejects otherwise.
- Ledger status vocabulary is exactly: `unexamined`, `signature-confirmed`, `control-flow-confirmed`, `assembly-matched`, `intentional-mismatch`. There is no "fix" state. `rebuilt_sha256` stays `null` throughout.
- A diverging function stays `unexamined` in the report pass and is written up in `divergences.md`. The fix pass advances it. Do not invent a weaker positive status for a function you know diverges.
- **There is no guest build in this plan.** No `vm/` script is written or run, no `.config` is staged to `out/i386/`, and no rebuilt artifact is fed to binrecon. Spec §1.2.
- **Before recording an absent function as a finding**, check whether our definition sits inside a false preprocessor conditional, is declared `__inline`, or is a macro the live branch redefines. Spec §5 and §2.1; this is the mistake that scoping made.
- Commit messages: short, subsystem-prefixed (`binrecon: `, `drvBPF: `, `drvPortServer: `, `drivers-i386: `), one to two lines, no metadata.
- Fixes touch only code the ledger flags. Exactly one exception is approved: the NUL-byte repair in Task 7, which is a pre-existing compile blocker. No other adjacent cleanup or refactoring.

## Reference identities

Recorded here so every task can assert against them rather than re-deriving.

| Driver | Reference path | Size | SHA-256 (uppercase) |
| --- | --- | --- | --- |
| drvBPF | `C:\Users\raynorpat\Downloads\test\Drivers\i386\BPF.config\BPF_reloc` | 32020 | `56DF84EDC7D77C0799A036C21BE43D833A926BCAA6DA48512DF99CEE7A1B86DB` |
| drvPortServer | `C:\Users\raynorpat\Downloads\test\Drivers\i386\PortServer.config\PortServer_reloc` | 69112 | `D724803154872B1D8199BE0426EAC4FDBE499C56FB81CCF07D5706916FF9B949` |

Both are `MH_PRELOAD` (Mach-O file type 5), i386, little-endian.

## Reference function inventory

Sizes below are derived from the gap to the next `__TEXT,__text` symbol. IDA's own `size` field is authoritative where the two disagree; a disagreement between IDA and angr is a `boundary_disputed` entry, not something to average.

**Measured, Task 2:** IDA's 30 addresses match this table exactly. 22 of the 30 sizes are 1–3 bytes *smaller* than the gap-derived figure, because the gap includes padding to the next 4-byte boundary and IDA reports true function extent. Use IDA's sizes. A gap-vs-IDA size difference of 1–3 bytes on a correctly aligned successor is padding and is **not** a `boundary_disputed` entry — reserve that bucket for genuine IDA-versus-angr disagreement. The same will hold for `PortServer_reloc` in Task 5.

### `BPF_reloc`, `__TEXT,__text` = 6296 bytes, 30 functions

| Address | Symbol | Size | Source file |
| --- | --- | --- | --- |
| 0 | `+[BPF probe:]` | 156 | `BPF.m` |
| 156 | `-[BPF initFromDeviceDescription:]` | 108 | `BPF.m` |
| 264 | `-[BPF getIntValues:forParameter:count:]` | 148 | `BPF.m` |
| 412 | `_bpfilterattach` | 8 | `bpf.c` |
| 420 | `_bpf_movein` | 536 | `bpf.c` |
| 956 | `_bpf_attachd` | 32 | `bpf.c` |
| 988 | `_bpf_detachd` | 132 | `bpf.c` |
| 1120 | `_bpfopen` | 88 | `bpf.c` |
| 1208 | `_bpfclose` | 68 | `bpf.c` |
| 1276 | `_bpfread` | 240 | `bpf.c` |
| 1516 | `_bpfwrite` | 160 | `bpf.c` |
| 1676 | `_reset_d` | 60 | `bpf.c` |
| 1736 | `_bpfioctl` | 796 | `bpf.c` |
| 2532 | `_bpf_setf` | 196 | `bpf.c` |
| 2728 | `_bpf_setif` | 252 | `bpf.c` |
| 2980 | `_bpf_ifname` | 44 | `bpf.c` |
| 3024 | `_bpf_select` | 100 | `bpf.c` |
| 3124 | `_bpf_tap` | 80 | `bpf.c` |
| 3204 | `_bpf_mcopy` | 92 | `bpf.c` |
| 3296 | `_bpf_mtap` | 92 | `bpf.c` |
| 3388 | `_catchpacket` | 244 | `bpf.c` |
| 3632 | `_bpf_allocbufs` | 96 | `bpf.c` |
| 3728 | `_bpf_freed` | 96 | `bpf.c` |
| 3824 | `_ifpromisc` | 100 | `bpf.c` |
| 3924 | `_m_xword` | 236 | `bpf_filter.c` |
| 4160 | `_m_xhalf` | 116 | `bpf_filter.c` |
| 4276 | `_bpf_filter` | 1840 | `bpf_filter.c` |
| 6116 | `_bpf_validate` | 156 | `bpf_filter.c` |
| 6272 | `+[BPFKernelServerInstance kernelServerInstance]` | 12 | *(build-generated)* |
| 6284 | `+[BPFVersion driverKitVersionForBPF]` | 12 | *(build-generated)* |

Link order groups the functions by source file exactly: `BPF.m` 0–412, `bpf.c` 412–3924, `bpf_filter.c` 3924–6272, glue 6272–6296.

`_bpf_wakeup` is **not** in this table and its absence is not a finding — our `bpf.c:526` declares it `static __inline`, so GCC inlines it into `_catchpacket`. Likewise `bpf_timeout`, `bpf_sleep`, `bpfselect`, and `bpf_alloc` are inside `#if BSD < 199103` blocks and are never compiled. Spec §2.1.

### `PortServer_reloc`, `__TEXT,__text` = 16160 bytes, 113 functions

Link order groups them by source file:

| Address range | Source file | Functions | Notes |
| --- | --- | --- | --- |
| 0–1188 | `AppleIOPSSafeCondLock.m` | 21 | 13 methods interleaved with 8 `_AIOPSSCL_*` C wrappers; `+initialize` is at address 0 and is 224 bytes |
| 1188–4324 | `IOPortSession.m` | 23 | 19 plain methods, then the 4 `IOPortSession(Private)` methods at 2772, 3332, 3588, 3824 |
| 4324–4692 | `PDPseudo.m` | 15 | 3 real methods, then 12 twelve-byte forwarding stubs from 4548 |
| 4692–6576 | `PortServer.m` | 12 | 9 methods, then `_portServeropen` 6112, `_portServerclose` 6212, `_portServerioctl` 6312 |
| 6576–8768 | `IOPortSessionKern.m` | 14 | 10 class methods, then the 4 get/set value instance methods from 8512 |
| 8768–15728 | `ttyiops.m` | 25 | 23 `_ttyiops_*`, plus `_tiotors232` 14216 and `_rs232totio` 14232, both 16 bytes |
| 15728–15752 | *(build-generated)* | 2 | `+[PortServerKernelServerInstance kernelServerInstance]`, `+[PortServerVersion driverKitVersionForPortServer]` |
| 15752–16160 | *(libgcc)* | 1 | `__divdi3`, 408 bytes, with its `___clz_tab` at 16782 in `__TEXT,__const` |

The ten largest functions, which carry most of the risk:

| Address | Symbol | Size |
| --- | --- | --- |
| 11592 | `_ttyiops_acquireSession` | 668 |
| 10676 | `_ttyiops_ioctl` | 636 |
| 13040 | `_ttyiops_param` | 636 |
| 12260 | `_ttyiops_init` | 620 |
| 8888 | `_ttyiops_open` | 596 |
| 2772 | `-[IOPortSession(Private) acquirePort:sleep:]` | 560 |
| 7440 | `+[IOPortSession(IOPortSessionKern) iopsKernMsgIoctl:data:]` | 508 |
| 3824 | `-[IOPortSession(Private) requestType:sleep:]` | 500 |
| 5128 | `-[PortServer initFromDeviceDescription:]` | 492 |
| 9484 | `_ttyiops_close` | 488 |

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `tools/binrecon/profiles/bpf.json` | drvBPF reference-only profile |
| `tools/binrecon/profiles/portserver.json` | drvPortServer reference-only profile |
| `src/drvBPF/reconstruction/source-map.json` | drvBPF function partition |
| `src/drvBPF/reconstruction/ledger.json` | drvBPF parity ledger |
| `src/drvBPF/reconstruction/divergences.md` | drvBPF report-pass findings |
| `src/drvPortServer/reconstruction/source-map.json` | drvPortServer function partition |
| `src/drvPortServer/reconstruction/ledger.json` | drvPortServer parity ledger |
| `src/drvPortServer/reconstruction/divergences.md` | drvPortServer report-pass findings |

**Modified:**

| Path | Change |
| --- | --- |
| `src/drvBPF/BPF.drvproj/Default.table` | Add `"Version" = "1.0";` |
| `src/drvBPF/BPF.drvproj/BPF.lksproj/{BPF.m,bpf.c,bpf_filter.c}` | Whatever Task 3 flags |
| `src/drvPortServer/PortServer.drvproj/Default.table` | Add `"Version"`; `"Support DialIn"` → `"Support Dialin"`; `"...rtf"` → `"...rtfd"`; restore reference comments |
| `src/drvPortServer/PortServer.drvproj/English.lproj/Localizable.strings` | `"Port Server" = ` key → `"PortServer" = ` |
| `src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m` | Two NUL bytes → `\0` escapes (Task 7), then whatever Task 6 flags |
| `src/drvPortServer/PortServer.drvproj/PortServer.lksproj/AppleIOPSSafeCondLock.m` | Remove the duplicate IMP cache set; implement the three TODO bodies |
| `src/drvPortServer/PortServer.drvproj/PortServer.lksproj/IOPortSessionKern.{h,m}` | `iopsServerIoctlCommand:data:` instance → class method |
| `src/drvPortServer/PortServer.drvproj/PortServer.lksproj/ttyiops.m` | Add `dtrDownDelay` and the `ttyiops_devsw` struct; implement the DCD TODO |
| `src/drivers-i386/README` | Add a section for the two top-level `src/drv*` drivers |

---

### Task 1: Reference-only profiles for both drivers

**Files:**
- Create: `tools/binrecon/profiles/bpf.json`
- Create: `tools/binrecon/profiles/portserver.json`

**Interfaces:**
- Consumes: the reference-only profile support added by the bus-driver effort — `profile-v1.json` does not require `rebuilt`, and `profile.py` loads it conditionally.
- Produces: two profile paths that every later task passes to `--profile`.

- [ ] **Step 1: Write the drvBPF profile**

Create `tools/binrecon/profiles/bpf.json`. This is `profiles/pcmciabus.json` with `name` and `output_dir` changed; copy it otherwise verbatim so the analyzer configuration stays uniform across drivers.

```json
{
  "schema_version": "profile-v1",
  "name": "drvBPF reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": false,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": true,
      "executable": "D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/bpf"
}
```

There is no `rebuilt` key. Do not add one.

- [ ] **Step 2: Write the drvPortServer profile**

Create `tools/binrecon/profiles/portserver.json`, identical but for two fields:

```json
{
  "schema_version": "profile-v1",
  "name": "drvPortServer reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": false,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": true,
      "executable": "D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/portserver"
}
```

- [ ] **Step 3: Validate the drvBPF profile resolves**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/BPF_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/bpf.json
```

Expected: exit 0. Prints the reference absolute path, size `32020`, and SHA-256 `56DF84EDC7D77C0799A036C21BE43D833A926BCAA6DA48512DF99CEE7A1B86DB`. No rebuilt artifact is reported.

- [ ] **Step 4: Validate the drvPortServer profile resolves**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/PortServer_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/portserver.json
```

Expected: exit 0. Size `69112`, SHA-256 `D724803154872B1D8199BE0426EAC4FDBE499C56FB81CCF07D5706916FF9B949`.

If either prints a different hash, the reference file on disk is not the one this plan was written against. Stop and report it rather than continuing.

- [ ] **Step 5: Confirm the test suite still matches baseline**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: `662 passed, 4 skipped`.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/profiles/bpf.json tools/binrecon/profiles/portserver.json
git commit -m "binrecon: add drvBPF and drvPortServer reference-only profiles"
```

---

### Task 2: drvBPF analyzer run

**Files:**
- Creates only gitignored output under `tools/binrecon/out/bpf/`.

**Interfaces:**
- Consumes: `tools/binrecon/profiles/bpf.json` from Task 1.
- Produces: `tools/binrecon/out/bpf/published/analysis-reference-{ida,angr}.json` and `consensus-reference.json`, which Task 3 reads.

- [ ] **Step 1: Run the analyzers**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/BPF_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/bpf.json
```

Expected: **exit code 1**, with `run-summary.json` showing `"complete": true`, `"rebuilt_sha256": null`, `"comparisons": []`, and `"acceptance": {"passed": false, ...}`.

Exit 1 is the correct outcome for every reference-only run and is not a failure. `runner.py:259` computes `expected_pass = bool(comparisons) and all(...)`, so with nothing compared the acceptance is `false`, and line 262 *enforces* that it stay `false` — the tool refuses to report acceptance as passed when no comparison happened.

**The real gate for this task** is: `"complete": true`, a `published/` directory holding the two `analysis-reference-*.json` files plus `consensus-reference.json`, and `"reference"` non-null for both analyzers. Judge success on those, not the exit code.

Ghidra is disabled for both profiles (see Global Constraints), so only IDA and angr run. If a run times out, the summary is marked `"complete": false`; fix the cause and re-run rather than proceeding.

**Do not launch `analyze` from a subagent that then exits** — the run is a long-lived child process and dies with its parent. Run it as a detached background task owned by the session.

- [ ] **Step 2: Confirm the published output and that nothing is tracked**

```bash
ls tools/binrecon/out/bpf/published/
git status --porcelain tools/binrecon/out
```

Expected: the three JSON files; `git status` prints nothing, confirming the `.gitignore` rules at lines 17 (`tools/binrecon/out/`) and 19 (`out/`) hold.

- [ ] **Step 3: Confirm the analyzers found all thirty functions**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
for analyzer in ('ida', 'angr'):
    path = f'tools/binrecon/out/bpf/published/analysis-reference-{analyzer}.json'
    functions = json.load(open(path))['functions']
    print(analyzer, len(functions))
    print('   ', sorted((f['address'], f['size']) for f in functions))
"
```

Expected from IDA: 30 functions whose addresses and sizes match the inventory table above. angr's `CFGFast` may report fewer or differ on sizes; that is recorded, not corrected. Any IDA/angr disagreement on a boundary goes to `boundary_disputed` in Task 3.

`_bpf_filter` at 4276 is 1840 bytes and is a large switch over BPF opcodes. If an analyzer splits it, that is a boundary dispute, not two functions.

There is no commit for this task — its entire output is gitignored.

---

### Task 3: drvBPF report pass

**Files:**
- Create: `src/drvBPF/reconstruction/source-map.json`
- Create: `src/drvBPF/reconstruction/ledger.json`
- Create: `src/drvBPF/reconstruction/divergences.md`

**Interfaces:**
- Consumes: the analyses from Task 2.
- Produces: a validated source map plus a ledger entry for every one of the 30 functions, and the finding list Task 4 works through.

- [ ] **Step 1: Generate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/bpf/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/BPF_reloc" \
  --source-dir src/drvBPF/BPF.drvproj/BPF.lksproj \
  --repo-root . \
  --output src/drvBPF/reconstruction/source-map.json
```

`--source-dir` is the `.lksproj` only. `PostLoad.tproj` is out of scope (spec §1.2) and must not be scanned; a symbol resolving into it would be a false mapping.

Expected: exit 0. A non-zero exit means the semantic validator rejected the document — read the `SemanticValidationError` message, which names the exact failing constraint.

- [ ] **Step 2: Review the buckets**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/drvBPF/reconstruction/source-map.json'))
for key in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    print(key, len(d[key]))
for entry in d['unmapped']:
    print('  unmapped:', entry['address'], entry['reference_names'])
"
```

Expected: `mapped` 28, `unmapped` 2 (`+[BPFKernelServerInstance kernelServerInstance]` at 6272 and `+[BPFVersion driverKitVersionForBPF]` at 6284), both other buckets 0.

Anything else unmapped is a finding for Step 6. Before writing it up, apply the Global Constraints check: is our definition inside a false `#if`, declared `__inline`, or a redefined macro?

- [ ] **Step 3: Disassembly-diff the three `BPF.m` methods**

The analyses contain **disassembly, not C decompilation**. Each function carries `instructions` (address, `bytes`, `mnemonic`, `operands`, `normalized_operands`, `relocations`), `blocks` for control flow, and `calls` with resolved targets. Compare at the instruction level — it is more precise than decompiled C, not less.

Reading disassembly against Objective-C source: a method's arguments arrive on the stack (`[ebp+self]`, `[ebp+arg]`), instance variables load as fixed offsets off `self`, and message sends appear as `calls` to `objc_msgSend` or `objc_msgSendSuper`.

- `+[BPF probe:]` at 0, 156 bytes. Our `BPF.m:57` passes twelve `IOSwitchFunc` arguments to `addToCdevswFromDescription:`. Check each against the reference's argument pushes in order — which entry points are `nulldev`, which are `enodev`, and that `bpf_select` is the select slot. The reference imports `_nulldev` and `_enodev`, so both appear as relocations.
- `-[BPF initFromDeviceDescription:]` at 156, 108 bytes. Check the `setName:` string, the `super` call, and the `registerDevice` call, in that order.
- `-[BPF getIntValues:forParameter:count:]` at 264, 148 bytes. Our source at `BPF.m:95` hand-rolls a string comparison against `"BpfMajorMinor"`; the reference imports `_strcmp`. Establish whether the reference calls `strcmp` here, and whether the count check is `== 2` as ours is. Record the comparison method as a finding if it differs.

The reference `__TEXT,__cstring` is 86 bytes. Dump it and anchor the reading on it:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
path = Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\BPF.config\BPF_reloc')
document = read_macho(path)
payload = path.read_bytes()
for section in document['sections']:
    if section['name'] == '__TEXT,__cstring':
        raw = payload[section['offset']:section['offset'] + section['size']]
        for chunk in raw.split(b'\0'):
            if chunk:
                print(repr(chunk.decode('latin1')))
"
```

- [ ] **Step 4: Disassembly-diff the twenty-one `bpf.c` functions and four `bpf_filter.c` functions**

Work in link order, which is source order. For each, compare block shape, the `calls` list against our call sites, and every literal constant. The ones that carry the most risk:

- `_bpfioctl` at 1736, 796 bytes — a large switch. Decode the jump table out of `__TEXT,__const` (170 bytes at 6382) and check every `BIOC*` command value against `bpf.c:612`.
- `_bpf_filter` at 4276, 1840 bytes — the interpreter switch. Check every BPF opcode case and the `__divdi3`-free division handling.
- `_bpf_movein` at 420, 536 bytes — mbuf allocation. The reference imports `_m_clalloc`, `_m_retry`, `_m_freem`, `_mbutl`, `_mclfree`, `_mclrefcnt`, `_mbstat`; confirm our `MGET`/`MCLGET` macro expansion produces the same set.
- `_catchpacket` at 3388, 244 bytes — this is where inlined `bpf_wakeup` lives. Expect `_wakeup` and `_selwakeup` calls inline, and `_microtime` for the timestamp. Their presence confirms §2.1 rather than contradicting it.

Record each function's examination depth as you go; Step 6's summary table needs the counts.

- [ ] **Step 5: Diff the config table and strings file**

```bash
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/Default.table" src/drvBPF/BPF.drvproj/Default.table
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/English.lproj/Localizable.strings" src/drvBPF/BPF.drvproj/English.lproj/Localizable.strings
```

Expected: `Localizable.strings` is identical. `Default.table` differs on exactly two lines — ours lacks `"Version" = "1.0";` (a finding, fixed in Task 4) and lacks the `"Driver Version"` line recording Apple's 1998 build host (build-generated, accepted). Any third difference is a new finding.

The reference `.config` has `English.lproj/Help/` where our source has `English.lproj/DriverHelp/`. That rename is a `pb_makefiles` convention, not a divergence. `BPF.rtfd` is present in ours.

- [ ] **Step 6: Write `divergences.md`**

Create `src/drvBPF/reconstruction/divergences.md`. Follow the structure of `src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md` — read it first. Required sections:

```markdown
# drvBPF reconstruction divergences

Report pass over Apple's shipped `BPF_reloc`
(`reference_sha256` `56DF84EDC7D77C0799A036C21BE43D833A926BCAA6DA48512DF99CEE7A1B86DB`,
32020 bytes, `MH_PRELOAD` i386). This document records where our reimplementation in
`src/drvBPF/BPF.drvproj/BPF.lksproj/` diverges from that binary.
**It changes no driver source.** Task 4 does the fixing.

Line numbers are against the current committed tree (`BPF.m` 132 lines,
`bpf.c` 1291, `bpf_filter.c` 565, `BPF.h` 47), verified with `git status`
before the pass began.

---

## 1. Coverage and examination depth

The reference partitions into **30 functions**: 28 hand-written plus 2 pieces of
build-generated Kernel Server glue.

| Depth | Count | What was done |
|---|---|---|
| `assembly-matched` | N | Every instruction read, and no divergence found |
| `control-flow-confirmed` | N | Block shape and every call target checked |
| `unexamined` | N | Every instruction read, **and a divergence found** |
| `intentional-mismatch` | 2 | Build-generated glue, not present in source |

## 2. Functions absent from the binary that are not findings

`bpf_timeout`, `bpf_sleep`, `bpfselect`, and `bpf_alloc` are defined in our
`bpf.c` inside `#if BSD < 199103` blocks and are never compiled. `bpf_wakeup`
is `static __inline` and is inlined into `catchpacket`. Our 26 definitions
therefore compile to the reference's 21 functions. Not findings.

## 3. Unmapped: build-generated

`+[BPFKernelServerInstance kernelServerInstance]` (6272) and
`+[BPFVersion driverKitVersionForBPF]` (6284) — emitted by the Kernel Server
project type and `Load_Commands.sect`, not written by hand. Accepted.

## Finding 1: <name> at 0x<address>

**Source:** `src/drvBPF/BPF.drvproj/BPF.lksproj/<file>:<line>`

**Reference behaviour**

<disassembly excerpt with the reasoning that reads it>

**Our source**

<source excerpt>

**Difference:** <what differs, concretely>

**Disposition:** fix | accept

**Rationale:** <why>

## Finding N: Default.table lacks the Version key

...

## README status

`src/drivers-i386/README` does not list this driver at all. State what the
status line should say, for Task 9.
```

- [ ] **Step 7: Create the ledger**

Every one of the 30 functions needs an entry. Functions Steps 3 and 4 confirmed get the status the evidence supports; diverging ones stay `unexamined`. The two build-generated functions are accepted divergences, which require both a reason and a reviewer:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/BPF_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/bpf.json \
  --ledger src/drvBPF/reconstruction/ledger.json \
  --address 0x1880 --status intentional-mismatch \
  --reason "build-generated kernel server glue, not present in source" \
  --reviewer "<your name>"
```

`0x1880` is 6272; repeat for `0x188c` (6284). For a function resolved to a source site, pass `--source-path` and `--source-line` together:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/BPF_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/bpf.json \
  --ledger src/drvBPF/reconstruction/ledger.json \
  --address 0x0 --status assembly-matched \
  --source-path src/drvBPF/BPF.drvproj/BPF.lksproj/BPF.m \
  --source-line <the source_line the source map recorded for this address>
```

Take `--source-path` and `--source-line` from the matching `mapped` entry in `source-map.json` rather than reading them off the file yourself; the loader in Step 8 checks them against the same bounds.

- [ ] **Step 8: Verify the source map against the reference analysis**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/bpf/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drvBPF/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`. This enforces the complete function partition, names, sizes, and source-line bounds.

- [ ] **Step 9: Commit**

```bash
git add src/drvBPF/reconstruction
git commit -m "drvBPF: record the parity ledger and divergences against the reference"
```

---

### Task 4: drvBPF fix pass

**Files:**
- Modify: `src/drvBPF/BPF.drvproj/Default.table`
- Modify: whichever of `src/drvBPF/BPF.drvproj/BPF.lksproj/{BPF.m,bpf.c,bpf_filter.c}` Task 3 flagged
- Modify: `src/drvBPF/reconstruction/{ledger.json,divergences.md}`

**Interfaces:**
- Consumes: the findings from Task 3.
- Produces: source matching the reference, advanced ledger statuses, and a recorded outcome per finding.

- [ ] **Step 1: Fix the config table**

In `src/drvBPF/BPF.drvproj/Default.table`, add the `"Version"` line the reference carries, in the reference's position — after `"Driver Name"`, before `"Post-Load"`. The result must read:

```
"Title" = "Berkeley Packet Filter";
"Family" = "Other";
"Instance" = "0";
"Driver Name" = "BPF";
"Version" = "1.0";
"Post-Load" = "PostLoad";
"Help File" = "BPF.rtfd";
"Server Name" = "BPF";
```

Do not add `"Driver Version"` — it is build-generated and records Apple's 1998 build host.

- [ ] **Step 2: Apply each source finding**

Work through `divergences.md` in order. For each finding whose disposition is `fix`, change the source to match the reference and nothing else. Preserve the existing Apple license header and each file's `#import` block, and match the surrounding comment density.

**Size is the check on overfitting.** Each reference function's size is in the inventory table at the top of this plan. A repair that would plausibly compile to a materially larger function means structure was invented; re-read the disassembly rather than adding code.

For each finding whose disposition is `accept`, make no source change — Step 4 records it in the ledger instead.

- [ ] **Step 3: Confirm the sources still read as text and the tree is otherwise untouched**

```bash
file src/drvBPF/BPF.drvproj/BPF.lksproj/*.c src/drvBPF/BPF.drvproj/BPF.lksproj/*.m
git diff --stat
```

Expected: every source file reports as ASCII or UTF-8 text, never `data`. `git diff --stat` lists only `Default.table`, the source files Task 3 flagged, and nothing under `PostLoad.tproj/`.

- [ ] **Step 4: Advance the ledger**

For each fixed function, set the status to the level the re-read supports. A repair you verified instruction by instruction earns `assembly-matched`; one where you checked block shape and call targets earns `control-flow-confirmed`. Do not claim `assembly-matched` for a function you did not read in full after the edit.

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/BPF_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/bpf.json \
  --ledger src/drvBPF/reconstruction/ledger.json \
  --address <address> --status control-flow-confirmed \
  --source-path src/drvBPF/BPF.drvproj/BPF.lksproj/<file> \
  --source-line <line of the repaired function>
```

For each accepted divergence:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/BPF_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/bpf.json \
  --ledger src/drvBPF/reconstruction/ledger.json \
  --address <address> --status intentional-mismatch \
  --reason "<why the reference form is not reproducible from our source>" \
  --reviewer "<your name>"
```

- [ ] **Step 5: Re-validate the source map**

Source-line bounds move when functions are edited, so the map must be regenerated and re-checked:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/bpf/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/BPF.config/BPF_reloc" \
  --source-dir src/drvBPF/BPF.drvproj/BPF.lksproj \
  --repo-root . \
  --output src/drvBPF/reconstruction/source-map.json
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/bpf/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drvBPF/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`, and `mapped` still 28 with `unmapped` still 2. A function that fell out of `mapped` means an edit moved or renamed a definition; fix that before committing.

- [ ] **Step 6: Record the outcome**

In `divergences.md`, append to each finding an `**Outcome:**` line stating what changed and the new ledger status. A finding whose repair could not be confirmed keeps its `unexamined` status and says so.

- [ ] **Step 7: Commit**

```bash
git add src/drvBPF
git commit -m "drvBPF: align the driver with Apple's shipped BPF_reloc"
```

Split into more than one commit if the findings group naturally — for example, the config table separately from the source repairs. Keep each message one to two lines.

---

### Task 5: drvPortServer analyzer run

**Files:**
- Creates only gitignored output under `tools/binrecon/out/portserver/`.

**Interfaces:**
- Consumes: `tools/binrecon/profiles/portserver.json` from Task 1.
- Produces: `tools/binrecon/out/portserver/published/analysis-reference-{ida,angr}.json` and `consensus-reference.json`, which Task 6 reads.

- [ ] **Step 1: Run the analyzers**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/PortServer_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/portserver.json
```

Expected: **exit code 1** with `"complete": true`, for the reason given in Task 2 Step 1. The gate is the same: `"complete": true`, three files in `published/`, `"reference"` non-null for both analyzers.

This binary is more than twice the size of `BPF_reloc`; if 900 seconds proves short for IDA, raise `timeout_seconds` in the profile and re-run rather than accepting an incomplete summary. Record any raise in the commit message.

**Do not launch `analyze` from a subagent that then exits.**

- [ ] **Step 2: Confirm the published output and that nothing is tracked**

```bash
ls tools/binrecon/out/portserver/published/
git status --porcelain tools/binrecon/out
```

Expected: the three JSON files; `git status` prints nothing.

- [ ] **Step 3: Confirm the analyzers found all 113 functions**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
for analyzer in ('ida', 'angr'):
    path = f'tools/binrecon/out/portserver/published/analysis-reference-{analyzer}.json'
    functions = json.load(open(path))['functions']
    print(analyzer, len(functions))
"
```

Expected 113 from IDA. angr may differ.

Two specific risks to check rather than assume:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
functions = {f['address']: f['size'] for f in json.load(open('tools/binrecon/out/portserver/published/analysis-reference-ida.json'))['functions']}
for address in (4548, 4560, 4572, 15752):
    print(address, functions.get(address))
"
```

Expected: `4548`, `4560`, and `4572` each report size 12 — the `PDPseudo` forwarding stubs are twelve identical-shaped bodies and an analyzer may coalesce them. `15752` reports 408, `__divdi3`. A missing entry is a boundary dispute for Task 6, not a missing function.

There is no commit for this task.

---

### Task 6: drvPortServer report pass

**Files:**
- Create: `src/drvPortServer/reconstruction/source-map.json`
- Create: `src/drvPortServer/reconstruction/ledger.json`
- Create: `src/drvPortServer/reconstruction/divergences.md`

**Interfaces:**
- Consumes: the analyses from Task 5.
- Produces: a validated source map plus a ledger entry for every one of the 113 functions, and the finding list Tasks 7 and 8 work through.

- [ ] **Step 1: Generate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/portserver/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/PortServer_reloc" \
  --source-dir src/drvPortServer/PortServer.drvproj/PortServer.lksproj \
  --repo-root . \
  --output src/drvPortServer/reconstruction/source-map.json
```

`--source-dir` is the `.lksproj` only. `pdservd.tproj` is out of scope (spec §1.2) and must not be scanned.

`PortServer.m` still contains the two NUL bytes at this point (spec §2.2, repaired in Task 7). The builder reads sources with `path.read_text(encoding="utf-8", errors="replace").splitlines()`, and `str.splitlines()` does not split on `\x00`, so line numbering is unaffected. If the builder nevertheless raises on that file, do Task 7 first and return here.

Expected: exit 0.

- [ ] **Step 2: Review the buckets**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/drvPortServer/reconstruction/source-map.json'))
for key in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    print(key, len(d[key]))
for key in ('unmapped', 'duplicate_candidates', 'boundary_disputed'):
    for entry in d[key]:
        print(' ', key, entry['address'], entry['reference_names'])
"
```

Expected: `unmapped` 3 — the two glue methods at 15728 and 15740, plus `__divdi3` at 15752. `mapped` 110.

Two known deviations from that expectation, both already findings:

- `+[IOPortSession(IOPortSessionKern) iopsServerIoctlCommand:data:]` at 6912 may land in `unmapped` or `duplicate_candidates` because ours is an instance method (spec §2.4, `IOPortSessionKern.m:776`). Either bucket is correct; record which.
- `AppleIOPSSafeCondLock` functions may land in `duplicate_candidates` because the file declares two parallel IMP cache sets (spec §2.3, lines 18–25 and 529–536). Record which functions and which sites.

Any other unmapped entry gets the Global Constraints check — false `#if`, `__inline`, or redefined macro — before being written up.

- [ ] **Step 3: Disassembly-diff `AppleIOPSSafeCondLock.m` (21 functions, 0–1188)**

The eight `_AIOPSSCL_*` C wrappers are each 28 or 32 bytes and do the same thing: load the cached IMP global and tail-call it. Read `_AIOPSSCL_interuptable` at 368 in full, then confirm the other seven match that shape against their own IMP global. Establish **which of the two IMP sets in our source the wrappers actually read** — that determines whether the second set is dead code or whether the two sets split the work, which Task 8 needs.

`+[AppleIOPSSafeCondLock initialize]` at 0 is 224 bytes and populates all eight globals. Check that it caches exactly eight selectors, in the order our `AppleIOPSSafeCondLock.m:40-78` caches them.

Three methods in our source have unimplemented `TODO` bodies — `AppleIOPSSafeCondLock.m:140`, `:491` (`unlockWith:`), and `:508`. Their reference counterparts are `-[AppleIOPSSafeCondLock free]` at 520 (44 bytes), `-[AppleIOPSSafeCondLock unlockWith:]` at 712 (84 bytes), and `-[AppleIOPSSafeCondLock setCondition:]` at 484 (36 bytes). Read all three in full; Task 8 writes the bodies from what you record here.

`AppleIOPSSafeCondLock.m:485` annotates a deliberate return-type deviation. Check `-[AppleIOPSSafeCondLock unlock]` at 592 against it and state whether the reference returns a value.

- [ ] **Step 4: Disassembly-diff `IOPortSession.m` (23 functions, 1188–4324)**

The four `IOPortSession(Private)` methods carry the size: `acquirePort:sleep:` at 2772 is 560 bytes, `requestType:sleep:` at 3824 is 500, `releasePort` at 3332 is 256, `getType:sleep:` at 3588 is 236. Read each in full.

`-[IOPortSession initForDevice:result:]` at 1304 is 456 bytes; check every instance variable offset it writes against our `@interface` layout, since a wrong ivar order here corrupts every other method.

- [ ] **Step 5: Disassembly-diff `PDPseudo.m` (15 functions, 4324–4692)**

Twelve of the fifteen are twelve-byte forwarding stubs from 4548. Read one in full, confirm the other eleven are byte-identical modulo the forwarded selector, and record them as a group rather than individually. The three real methods are `+deviceStyle` at 4324, `+probe:` at 4336, and `-initFromDeviceDescription:` at 4400 (148 bytes).

- [ ] **Step 6: Disassembly-diff `PortServer.m` (12 functions, 4692–6576)**

`-[PortServer initFromDeviceDescription:]` at 5128 is 492 bytes and is the method whose source contains the two NUL bytes, at `PortServer.m:192` and `:224`. Read it in full and record what the reference does at both sites — the first is a `*device_name == '\0'` test, the second a `name_buffer[7] = '\0'` terminator, and Task 7 needs the reference's confirmation that both are NUL comparisons rather than something else.

`+[PortServer serverMajor:]` at 4692 is 236 bytes; `-[PortServer getIntValues:forParameter:count:]` at 5620 is 276. The three `_portServer*` C entry points at 6112, 6212, and 6312 are the cdevsw hooks.

- [ ] **Step 7: Disassembly-diff `IOPortSessionKern.m` (14 functions, 6576–8768)**

`+[IOPortSession(IOPortSessionKern) iopsKernMsgIoctl:data:]` at 7440 is 508 bytes and is the largest. `iopsServerIoctlCommand:data:` at 6912 is 320 bytes — read it against our `IOPortSessionKern.m:776` and record specifically what it does with `self`, since a class method receiving the metaclass is what distinguishes it from our instance method.

The four get/set value methods from 8512 are 64 bytes each.

- [ ] **Step 8: Disassembly-diff `ttyiops.m` (25 functions, 8768–15728)**

This is the largest translation unit and the five biggest functions in the driver are here: `_ttyiops_acquireSession` 668, `_ttyiops_ioctl` 636, `_ttyiops_param` 636, `_ttyiops_init` 620, `_ttyiops_open` 596. Read each in full.

`_ttyiops_waitForDCD` at 12880 is 160 bytes and corresponds to our `ttyiops.m:1786` `TODO`; record its behaviour for Task 8.

`_tiotors232` at 14216 and `_rs232totio` at 14232 are 16 bytes each — table lookups. Find their tables in `__TEXT,__const` and check them against `ttyiops.m`.

Two data objects are referenced here and absent from our source (spec §2.5): `_dtrDownDelay` at 16604 in `__TEXT,__const` and `_ttyiops_devsw` at 33072 in `__DATA,__data`. Dump both and record their contents:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
path = Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\PortServer.config\PortServer_reloc')
document = read_macho(path)
payload = path.read_bytes()
sections = {s['name']: s for s in document['sections']}
for name, address, length in (('__TEXT,__const', 16604, 8), ('__DATA,__data', 33072, 56)):
    section = sections[name]
    start = section['offset'] + (address - section['address'])
    print(name, address, payload[start:start + length].hex())
"
```

`_ttyiops_devsw` is followed at 33128 by the IMP globals, so 56 bytes covers it. Read the relocations against those bytes to recover which function pointer sits in each devsw slot.

- [ ] **Step 9: Diff the config table and strings file**

```bash
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/Default.table" src/drvPortServer/PortServer.drvproj/Default.table
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/English.lproj/Localizable.strings" src/drvPortServer/PortServer.drvproj/English.lproj/Localizable.strings
ls src/drvPortServer/PortServer.drvproj/English.lproj/DriverHelp/
```

Expected differences, all findings except the last:

- ours lacks `"Version" = "5.00";`
- ours has `"Support DialIn"` where the reference has `"Support Dialin"` — a key the driver reads by exact name
- ours has `"Help File" = "PortServer_Main.rtf";` where the reference has `"...rtfd"`
- the three trailing comments differ in text and spacing
- `Localizable.strings` line 1: ours is `"Port Server" = "Port Server";`, the reference is `"PortServer" = "Port Server";` — the key is the lookup key, so ours resolves nothing
- `DriverHelp/` holds only `TableOfContents.rtf`; the `PortServer_Main.rtfd` bundle the `Help File` key names is absent from our tree
- ours lacks the `"Driver Version"` line — build-generated, accepted

Check whether `"Support Dialin"` is read anywhere in `PortServer.lksproj` and record the call site; that is what makes the capitalisation a behavioural finding rather than a cosmetic one.

- [ ] **Step 10: Write `divergences.md`**

Create `src/drvPortServer/reconstruction/divergences.md`, following the same structure as Task 3 Step 6 with these substitutions: reference `PortServer_reloc`, SHA-256 `D724803154872B1D8199BE0426EAC4FDBE499C56FB81CCF07D5706916FF9B949`, 69112 bytes, `MH_PRELOAD` i386; source directory `src/drvPortServer/PortServer.drvproj/PortServer.lksproj/`; 113 functions of which 110 are hand-written and 3 are residue (2 glue, 1 libgcc).

Line-count line: `AppleIOPSSafeCondLock.m` 632, `IOPortSession.m` 1132, `IOPortSessionKern.m` 860, `PDPseudo.m` 283, `PortServer.m` 546, `ttyiops.m` 2206.

Beyond the per-function findings, these sections are required:

```markdown
## Compile blocker

`PortServer.m` contains two literal NUL bytes, at lines 192 and 224, where
`'\0'` was intended. `file(1)` classifies the source as `data`. This predates
the reconstruction. Repaired in its own commit ahead of the divergence fixes.

## Absent from source

`_dtrDownDelay` (`__TEXT,__const`, 16604) and `_ttyiops_devsw`
(`__DATA,__data`, 33072) — contents recovered in Step 8, recorded here.

## Duplicate IMP caches

`AppleIOPSSafeCondLock.m` declares two parallel sets of the eight IMP globals,
at lines 18-25 and 529-536, where the reference has eight. State which set the
`_AIOPSSCL_*` wrappers read.

## Unimplemented bodies

Four `TODO` markers: `AppleIOPSSafeCondLock.m:140`, `:491`, `:508`, and
`ttyiops.m:1786`. Reference behaviour for each, recovered in Steps 3 and 8.

## Config table and strings

<the Step 9 findings, with the "Support Dialin" call site>

## README status

`src/drivers-i386/README` does not list this driver at all. State what the
status line should say, for Task 9.
```

- [ ] **Step 11: Create the ledger**

Every one of the 113 functions needs an entry, by the same rules as Task 3 Step 7. The three residue functions are accepted divergences:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/PortServer_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/portserver.json \
  --ledger src/drvPortServer/reconstruction/ledger.json \
  --address 0x3d70 --status intentional-mismatch \
  --reason "build-generated kernel server glue, not present in source" \
  --reviewer "<your name>"
```

`0x3d70` is 15728; repeat for `0x3d7c` (15740). For `__divdi3` at `0x3d88` (15752):

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/PortServer_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/portserver.json \
  --ledger src/drvPortServer/reconstruction/ledger.json \
  --address 0x3d88 --status intentional-mismatch \
  --reason "libgcc 64-bit division helper linked in by the toolchain, not source" \
  --reviewer "<your name>"
```

The twelve `PDPseudo` forwarding stubs still need twelve individual entries even though Step 5 examined them as a group; the ledger is per-function.

- [ ] **Step 12: Verify the source map against the reference analysis**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/portserver/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drvPortServer/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`.

- [ ] **Step 13: Commit**

```bash
git add src/drvPortServer/reconstruction
git commit -m "drvPortServer: record the parity ledger and divergences against the reference"
```

---

### Task 7: Repair drvPortServer's pre-existing compile blockers

**Scope widened during execution.** This task was written to repair two NUL bytes in
`PortServer.m`. The Task 6 report pass found that five of the six `.m` files in
`PortServer.lksproj` cannot compile as committed, all of it predating this work:

| File | Defect | Signal |
| --- | --- | --- |
| `AppleIOPSSafeCondLock.m` | missing `}` on `-setCondition:` (~line 361); orphaned comment tail 487-489 | brace delta `+1` |
| `PDPseudo.m` | one extra `}` (~line 209) | brace delta `-1` |
| `ttyiops.m` | two unclosed braces | brace delta `+2` |
| `IOPortSessionKern.m` | raw newline inside a string literal, lines 472-473 | odd quote count |
| `PortServer.m` | two literal NUL bytes (below) **and** a raw newline in a string literal, lines 101-102 | `file(1)` says `data` |

Only `IOPortSession.m` is clean. Repair all of it in this task, each file in its own
commit, before any divergence fix. Verify with a brace/NUL/quote scan, not by eye.
The NUL-specific steps below remain exactly as written.

#### Task 7 original scope: the NUL bytes in PortServer.m

Spec §2.2. This is the one approved change outside the ledger's findings, because it is a pre-existing compile blocker rather than a divergence. It gets its own commit ahead of the fix pass.

**Files:**
- Modify: `src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m`

**Interfaces:**
- Consumes: Task 6 Step 6's reading of `-[PortServer initFromDeviceDescription:]` at 5128, which confirms both sites are NUL handling.
- Produces: a `PortServer.m` that reads as text, which every later task's `grep` and `diff` depend on.

- [ ] **Step 1: Confirm the two sites and their current state**

Every Python snippet in this task is fed through a `<<'PY'` heredoc and avoids
`\\` in its literals. Bash collapses `\\` to `\` even inside double quotes, which
silently turns a `'\0'` replacement into a NUL and makes the repair a no-op that
still reports success. Do not rewrite these as `python -c "..."`.

```bash
./.venv-binrecon/Scripts/python.exe - <<'PY'
path = "src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m"
payload = open(path, "rb").read()
offsets = [i for i, byte in enumerate(payload) if byte == 0]
print("NUL count", len(offsets))
for offset in offsets:
    line = payload[:offset].count(b"\n") + 1
    start = payload.rfind(b"\n", 0, offset) + 1
    print(line, offset, payload[start:payload.find(b"\n", offset)])
PY
```

Expected exactly:

```
NUL count 2
192 5972 b"    if (device_name == NULL || *device_name == '\x00') {"
224 6685 b"        name_buffer[7] = '\x00';"
```

If the count or the lines differ, the file has changed since this plan was written. Stop and report it.

- [ ] **Step 2: Replace both NUL bytes with the escape sequence**

Rewrite the two bytes as the two-character escape `\0`, changing nothing else in the file:

```bash
./.venv-binrecon/Scripts/python.exe - <<'PY'
from pathlib import Path
path = Path("src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m")
payload = path.read_bytes()
needle = b"'" + bytes([0]) + b"'"
assert payload.count(bytes([0])) == 2, payload.count(bytes([0]))
assert payload.count(needle) == 2, payload.count(needle)
path.write_bytes(payload.replace(needle, rb"'\0'"))
print("repaired")
PY
```

The needle is built with `bytes([0])` and the replacement is a raw literal, so no
backslash reaches the shell. Both asserts must hold: the second is what catches a
NUL sitting somewhere other than inside a character literal, before anything is
written.

The replacement is scoped to the exact three-byte sequence `'<NUL>'`. The file
grows from 15655 bytes to 15657 — two bytes, one per site. A run that reports
`repaired` while leaving the size at 15655 replaced nothing; that is the failure
mode the heredoc exists to prevent.

- [ ] **Step 3: Verify the file is text and holds no NUL bytes**

```bash
file src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m
./.venv-binrecon/Scripts/python.exe - <<'PY'
path = "src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m"
payload = open(path, "rb").read()
print("NUL count", payload.count(bytes([0])))
print("line count", payload.count(b"\n"))
print("byte count", len(payload))
PY
sed -n '192p;224p' src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m
```

Expected exactly:

```
src/drvPortServer/.../PortServer.m: Objective-C source, ASCII text
NUL count 0
line count 546
byte count 15657
    if (device_name == NULL || *device_name == '\0') {
        name_buffer[7] = '\0';
```

`file` must not say `data`. `sed` printing those two lines legibly is the proof — before the repair, `grep` and `diff` treated the file as binary and would not show them.

- [ ] **Step 4: Confirm the diff is exactly two characters' worth**

```bash
git diff --stat src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m
git diff src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m
```

Expected: 2 insertions, 2 deletions, on lines 192 and 224 only. Any other changed line means the rewrite touched something it should not have; revert and redo.

- [ ] **Step 5: Confirm the source map still validates**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/portserver/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drvPortServer/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`. Line numbering did not change, so no entry should have moved.

- [ ] **Step 6: Commit**

```bash
git add src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m
git commit -m "drvPortServer: write the two NUL character literals as \\0 escapes

The raw bytes made PortServer.m a binary file that could not compile."
```

---

### Task 8: drvPortServer fix pass

**Files:**
- Modify: `src/drvPortServer/PortServer.drvproj/Default.table`
- Modify: `src/drvPortServer/PortServer.drvproj/English.lproj/Localizable.strings`
- Modify: whichever of `src/drvPortServer/PortServer.drvproj/PortServer.lksproj/*.{h,m}` Task 6 flagged
- Modify: `src/drvPortServer/reconstruction/{ledger.json,divergences.md}`

**Interfaces:**
- Consumes: the findings from Task 6 and the repaired `PortServer.m` from Task 7.
- Produces: source matching the reference, advanced ledger statuses, and a recorded outcome per finding.

- [ ] **Step 1: Confirm Task 7 landed**

```bash
file src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m
```

Expected: text, not `data`. If it still reports `data`, do Task 7 first.

- [ ] **Step 2: Fix the config table**

Rewrite `src/drvPortServer/PortServer.drvproj/Default.table` to match the reference on every key, including the comment text and column alignment. The result must read exactly:

```
"Title" = "Port Server";
"Version" = "5.00";
"Class Names" = "PDPseudo PortServer";
"Family" = "Serial";
"Instance" = "0";
"Post-Load" = "pdservd";
"Driver Name" = "Port Server";
"Maximum Sessions" = "16";
"Port Count" = "0";
"Support CTS" = "YES";     /* All ports support hardware handshaking */
"Support Dialin" = "YES";  /* All ports support dialout (ttyd*) */
"Support Dialout" = "YES"; /* All ports support dialin (cu*) */
"Help File" = "PortServer_Main.rtfd";
"Server Name" = "PortServer";
```

Do not add `"Driver Version"` — it is build-generated. The reference's dialin and dialout comments are transposed relative to their keys; that is Apple's, so preserve it rather than correcting it.

- [ ] **Step 3: Fix the strings file key**

In `src/drvPortServer/PortServer.drvproj/English.lproj/Localizable.strings`, change line 1 from `"Port Server" = "Port Server";` to:

```
"PortServer" = "Port Server";
```

Leave the 27 following lines alone. The key is what the driver looks up; the value is the display string and is already correct.

- [ ] **Step 4: Apply each source finding**

Work through `divergences.md` in order. The four known ones:

- **`iopsServerIoctlCommand:data:` becomes a class method.** In `IOPortSessionKern.h:155` and `IOPortSessionKern.m:776`, change the leading `-` to `+`. Check every call site the change breaks and update it to send to the class rather than an instance.
- **The duplicate IMP cache set goes.** Delete whichever of the two sets in `AppleIOPSSafeCondLock.m` Task 6 Step 3 established is unread, and any code that only wrote to it. If Step 3 found the two sets split the work, consolidate onto the set `+initialize` populates, since the reference has exactly eight globals.
- **`dtrDownDelay` and `ttyiops_devsw` get definitions** in `ttyiops.m`, from the bytes and relocations Task 6 Step 8 recovered.
- **The four `TODO` bodies get written** from the reference behaviour Task 6 Steps 3 and 8 recorded: `AppleIOPSSafeCondLock.m:140`, `:491`, `:508`, and `ttyiops.m:1786`.

Preserve each file's Apple license header and `#import` block, and match the surrounding comment density.

**Size is the check on overfitting.** Reference sizes are in the inventory at the top of this plan and in `divergences.md`. A body that would plausibly compile much larger than its reference counterpart means structure was invented; re-read the disassembly rather than adding code.

For each finding whose disposition is `accept`, make no source change — Step 6 records it in the ledger instead.

- [ ] **Step 5: Confirm the sources read as text and the tree is otherwise untouched**

```bash
file src/drvPortServer/PortServer.drvproj/PortServer.lksproj/*.m src/drvPortServer/PortServer.drvproj/PortServer.lksproj/*.h
git diff --stat
```

Expected: every source file reports as text. `git diff --stat` lists only the config table, the strings file, the source files Task 6 flagged, and nothing under `pdservd.tproj/`.

- [ ] **Step 6: Advance the ledger**

By the same rules as Task 4 Step 4, against `tools/binrecon/profiles/portserver.json` and `src/drvPortServer/reconstruction/ledger.json`. A repair you verified instruction by instruction earns `assembly-matched`; one checked at block and call-target level earns `control-flow-confirmed`. A `TODO` body you wrote from the disassembly but could not re-read against it in full stays `unexamined` and says so in the outcome.

- [ ] **Step 7: Re-validate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/portserver/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/PortServer.config/PortServer_reloc" \
  --source-dir src/drvPortServer/PortServer.drvproj/PortServer.lksproj \
  --repo-root . \
  --output src/drvPortServer/reconstruction/source-map.json
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/portserver/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drvPortServer/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`, `unmapped` still 3, and `mapped` now 111 or higher if the `iopsServerIoctlCommand:data:` change moved it out of `unmapped`. A function that fell *out* of `mapped` means an edit moved or renamed a definition; fix that before committing.

- [ ] **Step 8: Record the outcome**

In `divergences.md`, append to each finding an `**Outcome:**` line stating what changed and the new ledger status. State explicitly whether `PortServer_Main.rtfd` was supplied or left absent, since it is named by a config key the fix pass just corrected.

- [ ] **Step 9: Commit**

```bash
git add src/drvPortServer
git commit -m "drvPortServer: align the driver with Apple's shipped PortServer_reloc"
```

Split into more than one commit if the findings group naturally — for example, the config table and strings key separately from the source repairs. Keep each message one to two lines.

---

### Task 9: Add both drivers to the status README

**Files:**
- Modify: `src/drivers-i386/README`

**Interfaces:**
- Consumes: the `## README status` sections of both `divergences.md` files.
- Produces: the repository's driver status index covering these two drivers for the first time.

- [ ] **Step 1: Add a section for the top-level drivers**

`src/drivers-i386/README` lists drivers under `bus`, `ide`, `input`, `network`, `scsi`, `sound`, and `video`. Neither driver here lives under `src/drivers-i386/`; both sit at the top of `src/`. Append a new section after `video`, naming the location so the discrepancy is not mistaken for an omission:

```
other (these live at src/drvBPF and src/drvPortServer, not under drivers-i386)
 * drvBPF - <status from divergences.md>
 * drvPortServer - <status from divergences.md>
```

Match the existing entries' phrasing. The vocabulary already in the file is: `complete`, `compiles`, `crashing`, `needs compiled and then tested`, `reconstructed against the reference binary`, `fixes applied`, `not yet compiled or tested`. Neither driver has ever been built, so neither can claim more than "reconstructed against the reference binary, fixes applied, not yet compiled or tested."

Do not relocate the sources; that is out of scope (spec §1.2).

- [ ] **Step 2: Verify both drivers now appear**

```bash
grep -n "drvBPF\|drvPortServer" src/drivers-i386/README
```

Expected: one line each, with a status consistent with the ledgers.

- [ ] **Step 3: Confirm the whole reconstruction is committed and the test suite is clean**

```bash
git status --porcelain
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: `git status` shows only `src/drivers-i386/README`, and nothing under `tools/binrecon/out/`. The suite reports `662 passed, 4 skipped` — this plan adds no tests, because it adds no code to `binrecon`.

- [ ] **Step 4: Commit**

```bash
git add src/drivers-i386/README
git commit -m "drivers-i386: record drvBPF and drvPortServer reconstruction status"
```
