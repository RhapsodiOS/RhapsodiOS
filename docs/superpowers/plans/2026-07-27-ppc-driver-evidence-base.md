# PowerPC Driver Evidence Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure how closely five in-tree PowerPC driver sources correspond to Apple's shipped Rhapsody binaries, and publish the evidence base that later per-driver reconstruction specs will build on.

**Architecture:** Ten binrecon profiles drive IDA against ten reference Mach-O artifacts. Five `--scope-to-objc` source maps record the machine-checkable correspondence. Everything the scoped maps leave out is bucketed into explained classes versus real gaps, so the coverage gap is countable rather than invisible. A synthesis task assembles one report and ranks the follow-on per-driver specs by measured gap.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, binrecon (`tools/binrecon`), IDA Professional 9.2 headless (`idat.exe`), Mach-O 32-bit big-endian PowerPC.

**Spec:** [2026-07-27-ppc-driver-evidence-base-design.md](../specs/2026-07-27-ppc-driver-evidence-base-design.md)

## Global Constraints

Every task's requirements implicitly include this section.

- **This work happens in the `ppc-driver-recon` worktree**, not the main checkout. Every prior reconstruction used its own worktree, and the main checkout's `qemu-debug-loop` branch has unrelated work in flight.
- **Start every shell with these two assignments**, then use `$REPO` and `$VENVPY` exactly as the steps write them:

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-driver-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
```

  `$VENVPY` points into the **main checkout** on purpose: `.venv-binrecon` is gitignored, exists only there, and is a shared tool rather than per-worktree state. `PYTHONPATH=tools/binrecon` stays relative and resolves against `$REPO` because every command runs after `cd $REPO`.

- **Always set** `PYTHONPATH=tools/binrecon` on binrecon invocations.
- **Reference artifacts live at** `C:/Users/raynorpat/Downloads/test/Drivers/ppc/` and stay outside Git. Never copy them into the repo.
- **`binrecon analyze` exits 1 for every profile in this plan.** These are reference-only profiles with no rebuilt artifact, so `normalized-functions` acceptance is unsatisfiable by construction. **Exit 1 is success.** The pass condition is `"complete": true` in the run summary plus a published `published/analysis-reference-ida.json`. Do not "fix" the exit code, do not invent a rebuilt artifact, and do not change the acceptance level.
- **Never commit anything under `tools/binrecon/out/`.** Generated evidence, excluded by `.gitignore:25`.
- **Do not modify any driver source, any header, or `src/kernel-7/conf/files.ppc`.** This plan measures. Repairing divergences is out of scope.
- **Do not modify binrecon tooling** except under the narrow allowance in Task 8, which applies only when a defect blocks an artifact from publishing.
- **Commit messages:** start with the subsystem (`binrecon: `, `drivers-ppc: `), one to two lines, describing what the change does. No metadata, no trailers, no emoji.
- **`--scope-to-objc` is mandatory** on every `source-map` invocation. Without it the run fails: IDA's PowerPC linker glue stubs carry no name and `source-map-v1` requires every analyzed function to have one.
- **`SCRATCH`** is `C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad`. Assign it at the top of each shell.

### Driver parameter table

Every per-driver task substitutes from its row. `KEY` is the profile slug, `DIR` the reconstruction subdirectory.

| KEY | DIR | Bundle artifact | `_reloc` artifact | `--source-dir` arguments |
| --- | --- | --- | --- | --- |
| `cuda` | `Cuda` | `drvPPCCuda.config/drvPPCCuda` | `drvPPCCuda.config/drvPPCCuda_reloc` | `src/kernel-7/bsd/dev/ppc/drvCuda` |
| `53c96` | `53c96` | `drvPPC53c96.config/drvPPC53c96` | `drvPPC53c96.config/drvPPC53c96_reloc` | `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI` |
| `ata` | `ATA` | `drvPPCATA.config/drvPPCATA` | `drvPPCATA.config/drvPPCATA_reloc` | `src/kernel-7/bsd/dev/ppc/drvPPCATA` **and** `src/kernel-7/bsd/dev/ppc/drvATADisk` |
| `bmac` | `BMac` | `drvPPCBMac.config/drvPPCBMac` | `drvPPCBMac.config/drvPPCBMac_reloc` | `src/kernel-7/bsd/dev/ppc/drvBMacEnet` |
| `burgundy` | `Burgundy` | `drvPPCBurgundy.config/drvPPCBurgundy` | `drvPPCBurgundy.config/drvPPCBurgundy_reloc` | `src/drivers-ppc/sound/drvPPCBurgundy/PPCBurgundy.drvproj/PPCBurgundy.lksproj` |

### Expected SHA-256 (spec §1.1)

`validate` prints these. Any mismatch means the artifact changed; stop and report.

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `drvPPCCuda` | 8496 | `B82C4317C9DE095AC20C96FB69D902AE7C90DEAA6DB2443F50A7C3AAA5B1C07A` |
| `drvPPCCuda_reloc` | 43328 | `8CA26E3452246DE99BBD1731586B154B0B339DF3F4C2E65A50C000CC33EE1D1F` |
| `drvPPC53c96` | 8496 | `4DC866362B9394DD093FF967C2CA5BF25AC2813E64ECABC5BBDDF44719F69C1D` |
| `drvPPC53c96_reloc` | 151244 | `D4E01B128C43F18EB1357FC62874A8B89471C77F2BE4C0D955BE18054700B251` |
| `drvPPCATA` | 8492 | `348D054DF4EA489937D1980128E0EC0F451FE0983BE21AB8D7C5D44858D19DD7` |
| `drvPPCATA_reloc` | 134952 | `734464DC6604C7430761D95E3FA2D51C3C5A9E38956FD847B15390CD3448F597` |
| `drvPPCBMac` | 8496 | `193D2E4FA1BF8DD70A48AB78F6335CC416864FE6504546C68774B21603C468C9` |
| `drvPPCBMac_reloc` | 77828 | `F940BFBF0B67652409BF430F2A380D432B4BA59EAEE377A5FF218A0AE49DE616` |
| `drvPPCBurgundy` | 8504 | `D16D9B2355C96D6CEEBEA6346454BE438D5B5DB589F53BD8EDB457182304A1CE` |
| `drvPPCBurgundy_reloc` | 38652 | `D49E3479C9F0D2E7417A10ABAA3DC7D49562C1D4D2E1DCE77CAE467B96EB97CE` |

### Calibration measured before this plan was written

A trial of the whole pipeline against `drvPPCCuda` produced these numbers. Task 2 must reproduce them exactly; a difference means something changed and must be investigated, not accepted.

- `analyze` on the 8,496-byte bundle: **2.3 s**. On the 43,328-byte `_reloc`: **6.6 s**. The 151 KB `drvPPC53c96_reloc` will still finish well inside the 900 s timeout. **Run everything inline; no background jobs are needed.**
- `drvPPCCuda_reloc` analysis: **100 functions**, 40 carrying names, all 40 Objective-C, **0 named C functions**, 60 unnamed.
- Cuda source map: **mapped 38, unmapped 2, duplicate_candidates 0, boundary_disputed 0**. The 2 unmapped are the build-generated accessors `+[drvPPCCudaKernelServerInstance kernelServerInstance]` and `+[drvPPCCudaVersion driverKitVersionFordrvPPCCuda]`; there are **zero real gaps**. (The original calibration read 37/3 and counted `-[AppleCuda StartCudaTransmission:]` as a real gap; that was a scanner defect -- `cuda.m:1399` defines it with a NeXT-era `;` between the signature and the body -- fixed in `source_map.py`.)
- Reconciliation: 38 + 2 + 60 = 100. ✅
- The bundle stub analysis has **2 functions, both unnamed**. Bundle stubs are loader shims and carry no correspondence findings. They are analyzed because the spec requires all ten.

### Correction to spec §3.4, buckets 1 and 2

The spec expected `__picsymbol_stub` entries and crt/dyld startup routines. **The five `_reloc` artifacts have neither** — they are statically linked kernel servers, not `MH_EXECUTE` helpers, and they use jump islands instead of PIC stubs. `drvPPCCuda_reloc`'s section list confirms there is no `__picsymbol_stub` section.

**Buckets 1 and 2 will be empty for all five drivers.** The report must state this and say why, not silently omit the buckets.

### No profiles exist yet in this worktree

Two Cuda profiles were created during calibration, but they were never committed and live only in the main checkout. **This worktree has none of them.** Task 1 creates all ten from scratch.

Likewise `tools/binrecon/out/` does not exist here and will be created by the first `analyze` run.

---

## File Structure

**Created — committed:**

- `tools/binrecon/profiles/{cuda,53c96,ata,bmac,burgundy}-ppc.json` — one per `_reloc` artifact.
- `tools/binrecon/profiles/{cuda,53c96,ata,bmac,burgundy}-bundle-ppc.json` — one per bundle stub.
- `src/drivers-ppc/reconstruction/{Cuda,53c96,ATA,BMac,Burgundy}/source-map.json` — the durable, machine-re-verifiable measurement.
- `src/drivers-ppc/reconstruction/{Cuda,53c96,ATA,BMac,Burgundy}/findings.md` — per-driver raw measurement: bucket tables, selector-check output, findings.
- `src/drivers-ppc/reconstruction/report.md` — the synthesis, organized by spec §4's five parts.

**Created — not committed:**

- `tools/binrecon/out/<KEY>-ppc/`, `tools/binrecon/out/<KEY>-bundle-ppc/` — analyzer output, gitignored.
- `$SCRATCH/bucket_functions.py` — classification helper, written in full in Task 2.

**Modified:** none. No driver source, no header, no build wiring.

### Deviation from spec §2.2

Spec §2.2 lists only `report.md` and five `source-map.json`. This plan adds `findings.md` per driver, because five per-driver tasks cannot each append to a single `report.md` organized by cross-cutting part without conflicting, and because the per-driver raw measurement is worth keeping as evidence behind the synthesis. `report.md` remains the deliverable and cites each `findings.md`.

---

## Task 1: Ten binrecon profiles

**Files:**
- Create: `tools/binrecon/profiles/{cuda,53c96,ata,bmac,burgundy}-ppc.json`
- Create: `tools/binrecon/profiles/{cuda,53c96,ata,bmac,burgundy}-bundle-ppc.json`

**Interfaces:**
- Produces: ten profiles at `tools/binrecon/profiles/<KEY>-ppc.json` and `<KEY>-bundle-ppc.json`, with `output_dir` of `../out/<KEY>-ppc` and `../out/<KEY>-bundle-ppc`. Tasks 2–6 consume these paths.

- [ ] **Step 1: Confirm the worktree and venv are wired up**

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-driver-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
cd $REPO && git branch --show-current && $VENVPY --version && \
  PYTHONPATH=tools/binrecon $VENVPY -m binrecon --help | head -3
```

Expected: `ppc-driver-recon`, `Python 3.13.9`, and the binrecon usage banner listing `validate,analyze,ledger,compare,consensus,source-map`.

(`tools/binrecon/README.md` says the supported runtime is 3.12. The venv on this machine is 3.13.9 and the whole pipeline was calibrated on it. Use it as-is; do not rebuild the venv.)

- [ ] **Step 2: Generate all ten profiles**

Ghidra and angr are disabled because both reject a PowerPC profile before starting a subprocess.

```bash
cd $REPO && $VENVPY - <<'PY'
import json
from pathlib import Path

TEMPLATE = {
    'schema_version': 'profile-v1',
    'name': None,
    'architecture': 'ppc',
    'endianness': 'big',
    'reference': {'path': '${BINRECON_REFERENCE}'},
    'analyzers': {
        'ida': {'enabled': True,
                'executable': 'C:/Program Files/IDA Professional 9.2/idat.exe',
                'timeout_seconds': 900, 'version': '9.2'},
        'ghidra': {'enabled': False,
                   'executable': 'D:/ghidra/support/analyzeHeadless.bat',
                   'timeout_seconds': 900, 'version': '12.1'},
        'angr': {'enabled': False,
                 'executable': '.venv-binrecon/Scripts/python.exe',
                 'timeout_seconds': 900, 'version': '9.3.0'},
    },
    'comparison': {'acceptance': 'normalized-functions',
                   'ignore_metadata': [], 'entry_points': []},
    'output_dir': None,
}

DRIVERS = {'cuda': 'drvPPCCuda', '53c96': 'drvPPC53c96', 'ata': 'drvPPCATA',
           'bmac': 'drvPPCBMac', 'burgundy': 'drvPPCBurgundy'}

out = Path('tools/binrecon/profiles')
for key, driver in DRIVERS.items():
    for suffix, label in (('', 'ppc'), ('-bundle', 'bundle ppc')):
        d = json.loads(json.dumps(TEMPLATE))
        d['name'] = f'{driver} {label} reconstruction'
        d['output_dir'] = f'../out/{key}{suffix}-ppc'
        p = out / f'{key}{suffix}-ppc.json'
        p.write_text(json.dumps(d, indent=2) + '\n')
        print('wrote', p)
PY
```

Expected: ten `wrote tools/binrecon/profiles/...` lines.

- [ ] **Step 3: Validate all ten against the real artifacts**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && while read -r slug rel; do
  BINRECON_REFERENCE="$REF/$rel" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon validate \
    --profile "tools/binrecon/profiles/$slug.json"
done <<'EOF'
cuda-ppc drvPPCCuda.config/drvPPCCuda_reloc
cuda-bundle-ppc drvPPCCuda.config/drvPPCCuda
53c96-ppc drvPPC53c96.config/drvPPC53c96_reloc
53c96-bundle-ppc drvPPC53c96.config/drvPPC53c96
ata-ppc drvPPCATA.config/drvPPCATA_reloc
ata-bundle-ppc drvPPCATA.config/drvPPCATA
bmac-ppc drvPPCBMac.config/drvPPCBMac_reloc
bmac-bundle-ppc drvPPCBMac.config/drvPPCBMac
burgundy-ppc drvPPCBurgundy.config/drvPPCBurgundy_reloc
burgundy-bundle-ppc drvPPCBurgundy.config/drvPPCBurgundy
EOF
```

Expected: ten `reference ... size=... sha256=...` lines. **Check every size and SHA-256 against the Global Constraints table.** Any mismatch: stop and report.

- [ ] **Step 4: Commit**

```bash
cd $REPO && git add tools/binrecon/profiles/*-ppc.json && git commit -m "binrecon: add ten PowerPC profiles for the five shipped drivers

Covers the bundle stub and kernel-server _reloc of drvPPCCuda, drvPPC53c96,
drvPPCATA, drvPPCBMac and drvPPCBurgundy."
```

---

## Task 2: Cuda — analyses, source map, buckets

This is the reference task. It reproduces the calibration numbers and writes the bucket script that Tasks 3–6 reuse.

**Files:**
- Create: `$SCRATCH/bucket_functions.py`
- Create: `src/drivers-ppc/reconstruction/Cuda/source-map.json`
- Create: `src/drivers-ppc/reconstruction/Cuda/findings.md`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/cuda-ppc.json`, `cuda-bundle-ppc.json` from Task 1.
- Produces: `$SCRATCH/bucket_functions.py`, invoked as `python bucket_functions.py <analysis.json> <source-map.json>`, printing a bucket table and a `RECONCILES: yes|no` line. Tasks 3–6 invoke it unchanged.
- Produces: `src/drivers-ppc/reconstruction/Cuda/{source-map.json,findings.md}`. Task 7 reads both.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "cuda-ppc drvPPCCuda.config/drvPPCCuda_reloc" "cuda-bundle-ppc drvPPCCuda.config/drvPPCCuda"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze \
    --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

Expected: two `analysis complete; analyzers=1 comparisons=0 normalized-functions=FAIL` lines, each followed by `exit=1`. **Exit 1 is success here** — see Global Constraints.

- [ ] **Step 2: Verify both runs are complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['cuda-ppc','cuda-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

Expected:
```
cuda-ppc complete= True published= True
cuda-bundle-ppc complete= True published= True
```

- [ ] **Step 3: Run the relocation invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "cuda-ppc drvPPCCuda.config/drvPPCCuda_reloc" "cuda-bundle-ppc drvPPCCuda.config/drvPPCCuda"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: **0 relocation violations** for both. Any symbol/function-start mismatch it reports is recorded verbatim in `findings.md` as a `boundary_disputed` candidate — it is not a failure and does not block the task.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/Cuda && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/cuda-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCCuda.config/drvPPCCuda_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvCuda \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/Cuda/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Confirm the map reproduces the calibration numbers**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/Cuda/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
assert len(d['mapped'])==38 and len(d['unmapped'])==2
assert len(d['duplicate_candidates'])==0 and len(d['boundary_disputed'])==0
print('MATCHES CALIBRATION')
"
```

Expected:
```
mapped 38 unmapped 2 dup 0 disputed 0
  unmapped: ['+[drvPPCCudaKernelServerInstance kernelServerInstance]'] 20
  unmapped: ['+[drvPPCCudaVersion driverKitVersionFordrvPPCCuda]'] 16
MATCHES CALIBRATION
```

If the assertion fails, **stop and report** — the pipeline changed since calibration.

- [ ] **Step 6: Write the bucket classification script**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && cat > "$SCRATCH/bucket_functions.py" <<'PY'
"""Classify every function IDA found into exactly one bucket.

Usage: bucket_functions.py <analysis.json> <source-map.json>

Buckets follow spec section 3.4. Buckets 1 and 2 are expected to be empty for
the five _reloc kernel servers: they are statically linked, not MH_EXECUTE
helpers, so they carry no crt/dyld routines and no __picsymbol_stub section.
"""
import json
import sys

CRT = {
    "start", "__start", "__call_mod_init_funcs", "__dyld_init_check",
    "dyld_stub_binding_helper", "__dyld_func_lookup",
}

analysis = json.load(open(sys.argv[1]))
smap = json.load(open(sys.argv[2]))

stub_ranges = [
    (s["address"], s["address"] + s["size"])
    for s in analysis["sections"]
    if s.get("name") == "__picsymbol_stub"
]

mapped = {e["address"] for e in smap["mapped"]}
unmapped = {e["address"] for e in smap["unmapped"]}

buckets = {
    "mapped": [],
    "1-crt-dyld": [],
    "2-picsymbol-stub": [],
    "3-unnamed-jump-island": [],
    "4-build-generated-class": [],
    "5-fn-with-source-site": [],
    "6-fn-no-source-site": [],
}

for fn in analysis["functions"]:
    addr = fn["address"]
    names = fn.get("names") or []
    first = names[0] if names else None

    if addr in mapped:
        buckets["mapped"].append((addr, first, fn["size"]))
    elif first in CRT:
        buckets["1-crt-dyld"].append((addr, first, fn["size"]))
    elif any(lo <= addr < hi for lo, hi in stub_ranges):
        buckets["2-picsymbol-stub"].append((addr, first, fn["size"]))
    elif not names:
        buckets["3-unnamed-jump-island"].append((addr, first, fn["size"]))
    elif "KernelServerInstance" in first or "Version driverKitVersion" in first:
        buckets["4-build-generated-class"].append((addr, first, fn["size"]))
    else:
        # Named, not glue, not placed by the map. Two cases land here: an
        # Objective-C method the map could not place, and a C function outside
        # --scope-to-objc entirely. Both need a manual source lookup, so the
        # script emits them together for triage and the operator moves any
        # confirmed match into bucket 5 with its file and line. Bucket 5 is
        # therefore always 0 straight out of the script.
        buckets["6-fn-no-source-site"].append((addr, first, fn["size"]))

total = len(analysis["functions"])
counted = sum(len(v) for v in buckets.values())

print(f"total functions: {total}")
for name, entries in buckets.items():
    print(f"  {name}: {len(entries)}")
    for addr, nm, size in entries:
        if not name.startswith(("mapped", "3-")):
            print(f"      0x{addr:x}  {nm}  ({size} bytes)")
print(f"counted: {counted}")
print(f"RECONCILES: {'yes' if counted == total else 'no'}")
PY
echo "written"
```

Expected: `written`.

- [ ] **Step 7: Run the bucket script and confirm reconciliation**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/cuda-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/Cuda/source-map.json
```

Expected exactly:

```
total functions: 100
  mapped: 38
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 60
  4-build-generated-class: 2
      0x2428  +[drvPPCCudaKernelServerInstance kernelServerInstance]  (20 bytes)
      0x243c  +[drvPPCCudaVersion driverKitVersionFordrvPPCCuda]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 0
counted: 100
RECONCILES: yes
```

`RECONCILES: no` means a function fell through every branch — **stop and report**; acceptance item 5 cannot be met until it reconciles.

- [ ] **Step 8: Run the selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY \
  tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCCuda.config/drvPPCCuda_reloc" \
  src/kernel-7/bsd/dev/ppc/drvCuda
```

Record the output verbatim in `findings.md`. It is measurement — a nonzero exit is a finding, not a task failure.

- [ ] **Step 9: Write `findings.md`**

Create `src/drivers-ppc/reconstruction/Cuda/findings.md` with these sections, filled from the output of Steps 3, 5, 7 and 8:

1. `## Artifacts` — both artifacts with size and SHA-256 from the Global Constraints table.
2. `## Correspondence` — mapped, unmapped, duplicate_candidates, boundary_disputed; total functions; named vs unnamed.
3. `## Buckets` — the Step 7 table verbatim, including the explicit statement that buckets 1 and 2 are empty **because this is a statically linked kernel server with no `__picsymbol_stub` section and no crt/dyld routines**.
4. `## Unmapped detail` — each unmapped entry with its size, classified as build-generated or a real gap. Both unmapped entries are the build-generated accessors (`kernelServerInstance`, `driverKitVersionFordrvPPCCuda`); state each size and that Cuda has **zero real gaps**. `-[AppleCuda StartCudaTransmission:]` is *not* a gap: `drvCuda/cuda.m:1399` defines it.
5. `## Invariant check` — Step 3 output; relocation violations must be 0; list any symbol/function-start mismatches as `boundary_disputed` candidates.
6. `## Selector check` — Step 8 output verbatim.
7. `## Bundle stub` — 2 functions, both unnamed; a loader shim carrying no correspondence findings.

Every number must come from command output pasted into the document. Do not write a number you did not observe.

- [ ] **Step 10: Verify the map loads against the reference analysis**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/Cuda/source-map.json'
a = load_json(Path('tools/binrecon/out/cuda-ppc/published/analysis-reference-ida.json'))
m = json.load(open(MAP))
covered = set()
for cat in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    covered |= {e['address'] for e in m[cat]}
before = len(a['functions'])
a['functions'] = [f for f in a['functions'] if f['address'] in covered]
print('analysis functions', before, '-> scoped', len(a['functions']))
load_source_map(Path(MAP), reference_analysis=a, repo_root=Path.cwd())
print('load_source_map OK')
"
```

Expected: an `analysis functions N -> scoped M` line followed by `load_source_map OK`.

**Why the analysis is scoped before the check.** The map was built with `--scope-to-objc`, so it covers only the Objective-C functions. `load_source_map` enforces an *exact* partition, so handing it the unscoped analysis fails with `SemanticValidationError: source map partition mismatch` listing the unnamed jump islands — the very functions the map deliberately excludes. Restricting the analysis to the addresses the map covers checks the full partition, names, sizes and source-line bounds over everything the map claims. The functions removed here are not lost: the bucket reconciliation accounts for every one of them.

- [ ] **Step 11: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/Cuda && git commit -m "drivers-ppc: measure drvPPCCuda against its shipped binary

38 of 40 Objective-C methods map to bsd/dev/ppc/drvCuda; the two that do not
are build-generated accessors, so there is no real gap."
```

---

## Task 3: BMac — analyses, source map, buckets

**Files:**
- Create: `src/drivers-ppc/reconstruction/BMac/source-map.json`
- Create: `src/drivers-ppc/reconstruction/BMac/findings.md`

**Interfaces:**
- Consumes: `bmac-ppc.json`, `bmac-bundle-ppc.json` (Task 1); `$SCRATCH/bucket_functions.py` (Task 2), invoked as `python bucket_functions.py <analysis.json> <source-map.json>`.
- Produces: `src/drivers-ppc/reconstruction/BMac/{source-map.json,findings.md}` for Task 7.

Source: `src/kernel-7/bsd/dev/ppc/drvBMacEnet` — 63 ObjC method definitions, 3 static C functions, classes `BMacEnet` plus categories `(Private)` and `(MII)`. The binary links `BMacEnet` and `IONetbufQueue`.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "bmac-ppc drvPPCBMac.config/drvPPCBMac_reloc" "bmac-bundle-ppc drvPPCBMac.config/drvPPCBMac"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze \
    --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

Expected: two `normalized-functions=FAIL` lines, each with `exit=1`. Success.

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['bmac-ppc','bmac-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

Expected: both lines `complete= True published= True`.

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "bmac-ppc drvPPCBMac.config/drvPPCBMac_reloc" "bmac-bundle-ppc drvPPCBMac.config/drvPPCBMac"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both. Record any symbol/function-start mismatches.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/BMac && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/bmac-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCBMac.config/drvPPCBMac_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvBMacEnet \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/BMac/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/BMac/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'], e.get('source_sites') or '')
"
```

`duplicate_candidates` must be 0, **or** every entry must be enumerated in `findings.md` with the evidence establishing its cause (acceptance item 4, as amended during the ATA measurement). A nonzero `boundary_disputed` is a finding, not a failure — record each entry the same way.

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/bmac-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/BMac/source-map.json
```

Expected: `RECONCILES: yes`. Buckets 1 and 2 must be 0. `RECONCILES: no` → stop and report.

Every entry the script lists under `6-fn-no-source-site` needs a manual source lookup against `src/kernel-7/bsd/dev/ppc/drvBMacEnet`: grep for the symbol name; if a definition exists, it belongs in bucket 5 and the move is recorded with file and line in `findings.md`. If none exists, it stays in bucket 6 as a real gap.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY \
  tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCBMac.config/drvPPCBMac_reloc" \
  src/kernel-7/bsd/dev/ppc/drvBMacEnet
```

Record verbatim.

- [ ] **Step 8: Write `findings.md`**

`src/drivers-ppc/reconstruction/BMac/findings.md`, same seven sections as Task 2 Step 9: Artifacts, Correspondence, Buckets, Unmapped detail, Invariant check, Selector check, Bundle stub. Every number pasted from observed output. Bucket-5 moves cite file and line.

- [ ] **Step 9: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/BMac/source-map.json'
a = load_json(Path('tools/binrecon/out/bmac-ppc/published/analysis-reference-ida.json'))
m = json.load(open(MAP))
covered = set()
for cat in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    covered |= {e['address'] for e in m[cat]}
before = len(a['functions'])
a['functions'] = [f for f in a['functions'] if f['address'] in covered]
print('analysis functions', before, '-> scoped', len(a['functions']))
load_source_map(Path(MAP), reference_analysis=a, repo_root=Path.cwd())
print('load_source_map OK')
"
```

Expected: an `analysis functions N -> scoped M` line followed by `load_source_map OK`.

**Why the analysis is scoped before the check.** The map was built with `--scope-to-objc`, so it covers only the Objective-C functions. `load_source_map` enforces an *exact* partition, so handing it the unscoped analysis fails with `SemanticValidationError: source map partition mismatch` listing the unnamed jump islands — the very functions the map deliberately excludes. Restricting the analysis to the addresses the map covers checks the full partition, names, sizes and source-line bounds over everything the map claims. The functions removed here are not lost: the bucket reconciliation accounts for every one of them.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/BMac && git commit -m "drivers-ppc: measure drvPPCBMac against its shipped binary

Source map and bucket reconciliation for bsd/dev/ppc/drvBMacEnet."
```

---

## Task 4: Burgundy — analyses, source map, buckets

**Files:**
- Create: `src/drivers-ppc/reconstruction/Burgundy/source-map.json`
- Create: `src/drivers-ppc/reconstruction/Burgundy/findings.md`

**Interfaces:**
- Consumes: `burgundy-ppc.json`, `burgundy-bundle-ppc.json` (Task 1); `$SCRATCH/bucket_functions.py` (Task 2).
- Produces: `src/drivers-ppc/reconstruction/Burgundy/{source-map.json,findings.md}` for Task 7.

This is the only driver whose source already lives in `src/drivers-ppc`, and the only one that is a RhapsodiOS reimplementation rather than Apple's own source. 38 ObjC method definitions across `BurgundySound.m` and `BurgundySoundPrivate.m`; the binary links `PPCBurgundy` and `IOAudio`. Expect a larger gap here than for the Apple-sourced drivers, and do not treat that as an error.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "burgundy-ppc drvPPCBurgundy.config/drvPPCBurgundy_reloc" "burgundy-bundle-ppc drvPPCBurgundy.config/drvPPCBurgundy"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze \
    --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

Expected: two `normalized-functions=FAIL` lines, each with `exit=1`. Success.

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['burgundy-ppc','burgundy-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

Expected: both lines `complete= True published= True`.

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "burgundy-ppc drvPPCBurgundy.config/drvPPCBurgundy_reloc" "burgundy-bundle-ppc drvPPCBurgundy.config/drvPPCBurgundy"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/Burgundy && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/burgundy-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCBurgundy.config/drvPPCBurgundy_reloc" \
  --source-dir src/drivers-ppc/sound/drvPPCBurgundy/PPCBurgundy.drvproj/PPCBurgundy.lksproj \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/Burgundy/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/Burgundy/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'], e.get('source_sites') or '')
"
```

`duplicate_candidates` must be 0, or every entry enumerated with its cause (acceptance item 4, as amended).

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/burgundy-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/Burgundy/source-map.json
```

Expected: `RECONCILES: yes`. Resolve every `6-fn-no-source-site` entry by grepping `src/drivers-ppc/sound/drvPPCBurgundy/PPCBurgundy.drvproj/PPCBurgundy.lksproj` for the symbol; move confirmed matches to bucket 5 with file and line.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY \
  tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCBurgundy.config/drvPPCBurgundy_reloc" \
  src/drivers-ppc/sound/drvPPCBurgundy/PPCBurgundy.drvproj/PPCBurgundy.lksproj
```

Record verbatim. This is the driver most likely to show renamed or absent selectors, since it is a reimplementation.

- [ ] **Step 8: Write `findings.md`**

`src/drivers-ppc/reconstruction/Burgundy/findings.md`, same seven sections as Task 2 Step 9. Add an eighth: `## Reimplementation note` — state that this driver is a RhapsodiOS reimplementation, not Apple source, and that its gap is therefore expected to differ in kind from the other four.

- [ ] **Step 9: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/Burgundy/source-map.json'
a = load_json(Path('tools/binrecon/out/burgundy-ppc/published/analysis-reference-ida.json'))
m = json.load(open(MAP))
covered = set()
for cat in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    covered |= {e['address'] for e in m[cat]}
before = len(a['functions'])
a['functions'] = [f for f in a['functions'] if f['address'] in covered]
print('analysis functions', before, '-> scoped', len(a['functions']))
load_source_map(Path(MAP), reference_analysis=a, repo_root=Path.cwd())
print('load_source_map OK')
"
```

Expected: an `analysis functions N -> scoped M` line followed by `load_source_map OK`.

**Why the analysis is scoped before the check.** The map was built with `--scope-to-objc`, so it covers only the Objective-C functions. `load_source_map` enforces an *exact* partition, so handing it the unscoped analysis fails with `SemanticValidationError: source map partition mismatch` listing the unnamed jump islands — the very functions the map deliberately excludes. Restricting the analysis to the addresses the map covers checks the full partition, names, sizes and source-line bounds over everything the map claims. The functions removed here are not lost: the bucket reconciliation accounts for every one of them.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/Burgundy && git commit -m "drivers-ppc: measure drvPPCBurgundy against its shipped binary

First measurement of the sound driver reimplementation against Apple's build."
```

---

## Task 5: ATA — analyses, source map, buckets, and the IdeDisk rename

**Files:**
- Create: `src/drivers-ppc/reconstruction/ATA/source-map.json`
- Create: `src/drivers-ppc/reconstruction/ATA/findings.md`

**Interfaces:**
- Consumes: `ata-ppc.json`, `ata-bundle-ppc.json` (Task 1); `$SCRATCH/bucket_functions.py` (Task 2).
- Produces: `src/drivers-ppc/reconstruction/ATA/{source-map.json,findings.md}` for Task 7.

This driver spans two source directories and carries the rename finding from spec §4.2. **Expect a large raw unmapped count and do not treat it as a defect** — see Step 6.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "ata-ppc drvPPCATA.config/drvPPCATA_reloc" "ata-bundle-ppc drvPPCATA.config/drvPPCATA"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze \
    --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

Expected: two `normalized-functions=FAIL` lines, each with `exit=1`. Success. If either run fails to publish, go to Task 8 before continuing.

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['ata-ppc','ata-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

Expected: both lines `complete= True published= True`.

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "ata-ppc drvPPCATA.config/drvPPCATA_reloc" "ata-bundle-ppc drvPPCATA.config/drvPPCATA"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both. `drvPPCATA_reloc` is 134,952 bytes and is a plausible carrier of `PPC_RELOC_SECTDIFF` switch tables; if the invariant check reports violations, that is a genuine finding to record, not a tool bug to fix.

- [ ] **Step 4: Build the source map across both source directories**

`--source-dir` is repeatable and the scanner does not recurse, so both directories must be passed explicitly.

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/ATA && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/ata-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCATA.config/drvPPCATA_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvPPCATA \
  --source-dir src/kernel-7/bsd/dev/ppc/drvATADisk \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/ATA/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/ATA/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
ide=[u for u in d['unmapped'] if any('IdeDisk' in n for n in u['reference_names'])]
print('unmapped IdeDisk methods:', len(ide))
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'], e.get('source_sites') or '')
"
```

`duplicate_candidates` must be 0, or every entry enumerated with its cause (acceptance item 4, as amended).

- [ ] **Step 6: Establish or refute the IdeDisk/ATADisk rename**

The binary links `IdeDisk`; the tree defines `ATADisk : IODisk` in `src/kernel-7/bsd/dev/ppc/drvATADisk/ATADisk.m`. `source-map` matches by name, so **every `-[IdeDisk …]` will report unmapped** and the raw count will overstate the real gap.

Compare the two selector sets:

```bash
cd $REPO && $VENVPY - <<'PY'
import json, re, pathlib

d = json.load(open('src/drivers-ppc/reconstruction/ATA/source-map.json'))
binary_sel = set()
for u in d['unmapped']:
    for n in u['reference_names']:
        m = re.match(r'[-+]\[IdeDisk (.+)\]$', n)
        if m:
            binary_sel.add(m.group(1))

src_sel = set()
for p in pathlib.Path('src/kernel-7/bsd/dev/ppc/drvATADisk').glob('*.m'):
    for line in p.read_text(errors='replace').splitlines():
        m = re.match(r'^[-+]\s*\([^)]*\)\s*(.+)', line.strip())
        if m:
            sig = m.group(1).split('{')[0].strip()
            parts = re.findall(r'(\w+):', sig)
            src_sel.add(''.join(p + ':' for p in parts) if parts else sig.split()[0])

print('IdeDisk selectors in binary:', len(binary_sel))
print('ATADisk selectors in source:', len(src_sel))
print('intersection:', len(binary_sel & src_sel))
print('binary only:', sorted(binary_sel - src_sel)[:20])
print('source only:', sorted(src_sel - binary_sel)[:20])
PY
```

**Interpretation, to be recorded in `findings.md`:** a large intersection establishes the rename — `IdeDisk` and `ATADisk` are the same class under two names. A small intersection refutes it, and they are genuinely different classes. Record the counts and the verdict either way, with the supporting comment references already found in the tree: `drvATADisk/ATADiskKernel.m:90` cites `IdeDiskInternal.h`, and `drvPPCATA/AtapiCnt.m:76`, `IdeCntCmds.h:100` and `IdeCntCmds.m:59` name `IdeDisk` in comments.

If the rename is established, `findings.md` reports **both** a raw mapped/unmapped count and a rename-adjusted count, with the difference attributed to this finding.

- [ ] **Step 7: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/ata-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/ATA/source-map.json
```

Expected: `RECONCILES: yes`. The `IdeDisk` methods appear under bucket 6; annotate them in `findings.md` as rename-explained rather than real gaps, if Step 6 established the rename.

- [ ] **Step 8: Selector check, both directories**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCATA.config/drvPPCATA_reloc" && \
for d in src/kernel-7/bsd/dev/ppc/drvPPCATA src/kernel-7/bsd/dev/ppc/drvATADisk; do
  echo "=== $d ==="
  PYTHONPATH=tools/binrecon $VENVPY \
    tools/binrecon/selector_check.py "$REF" "$d"
done
```

`selector_check.py` takes one directory, so this runs twice. Merge the two outputs in `findings.md`: a selector reported missing by one run but present in the other is **not** missing.

- [ ] **Step 9: Write `findings.md`**

`src/drivers-ppc/reconstruction/ATA/findings.md`, the seven sections from Task 2 Step 9, plus:

8. `## IdeDisk / ATADisk` — Step 6's counts, the verdict, the supporting comment references, and the rename-adjusted correspondence numbers.
9. `## Two source directories` — that the map spans `drvPPCATA` and `drvATADisk`, and that the selector check was run once per directory and merged.

- [ ] **Step 10: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/ATA/source-map.json'
a = load_json(Path('tools/binrecon/out/ata-ppc/published/analysis-reference-ida.json'))
m = json.load(open(MAP))
covered = set()
for cat in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    covered |= {e['address'] for e in m[cat]}
before = len(a['functions'])
a['functions'] = [f for f in a['functions'] if f['address'] in covered]
print('analysis functions', before, '-> scoped', len(a['functions']))
load_source_map(Path(MAP), reference_analysis=a, repo_root=Path.cwd())
print('load_source_map OK')
"
```

Expected: an `analysis functions N -> scoped M` line followed by `load_source_map OK`.

**Why the analysis is scoped before the check.** The map was built with `--scope-to-objc`, so it covers only the Objective-C functions. `load_source_map` enforces an *exact* partition, so handing it the unscoped analysis fails with `SemanticValidationError: source map partition mismatch` listing the unnamed jump islands — the very functions the map deliberately excludes. Restricting the analysis to the addresses the map covers checks the full partition, names, sizes and source-line bounds over everything the map claims. The functions removed here are not lost: the bucket reconciliation accounts for every one of them.

- [ ] **Step 11: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/ATA && git commit -m "drivers-ppc: measure drvPPCATA against its shipped binary

Maps drvPPCATA and drvATADisk as one unit and settles whether the shipped
IdeDisk class is our ATADisk under another name."
```

---

## Task 6: 53c96 — analyses, source map, buckets

**Files:**
- Create: `src/drivers-ppc/reconstruction/53c96/source-map.json`
- Create: `src/drivers-ppc/reconstruction/53c96/findings.md`

**Interfaces:**
- Consumes: `53c96-ppc.json`, `53c96-bundle-ppc.json` (Task 1); `$SCRATCH/bucket_functions.py` (Task 2).
- Produces: `src/drivers-ppc/reconstruction/53c96/{source-map.json,findings.md}` for Task 7.

The largest binary at 151,244 bytes. `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI` has 124 ObjC method definitions across nine categories of `Apple96_SCSI`, plus 9 static C functions and `Timestamp.c`. This is the task most likely to produce a long tail under bucket 6 — spec §5.1 anticipates exactly this.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "53c96-ppc drvPPC53c96.config/drvPPC53c96_reloc" "53c96-bundle-ppc drvPPC53c96.config/drvPPC53c96"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze \
    --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

Expected: two `normalized-functions=FAIL` lines, each with `exit=1`. Success. If either run fails to publish, go to Task 8 before continuing.

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['53c96-ppc','53c96-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

Expected: both lines `complete= True published= True`.

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "53c96-ppc drvPPC53c96.config/drvPPC53c96_reloc" "53c96-bundle-ppc drvPPC53c96.config/drvPPC53c96"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/53c96 && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/53c96-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPC53c96.config/drvPPC53c96_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvApple96_SCSI \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/53c96/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/53c96/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'], e.get('source_sites') or '')
"
```

`duplicate_candidates` must be 0, or every entry enumerated with its cause (acceptance item 4, as amended).

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/53c96-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/53c96/source-map.json
```

Expected: `RECONCILES: yes`.

Resolve every `6-fn-no-source-site` entry by grepping `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI` (including `Timestamp.c`) for the symbol name. Confirmed definitions move to bucket 5 with file and line. Per spec §5.1, an entry that resists classification is recorded in `findings.md` as an open question **with what was tried** — an explicitly recorded unbucketable function satisfies acceptance item 5; an unexamined one does not.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY \
  tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPC53c96.config/drvPPC53c96_reloc" \
  src/kernel-7/bsd/dev/ppc/drvApple96_SCSI
```

Record verbatim.

- [ ] **Step 8: Write `findings.md`**

`src/drivers-ppc/reconstruction/53c96/findings.md`, the seven sections from Task 2 Step 9, plus:

8. `## Open questions` — every function that could not be bucketed, with what was tried. Empty is a valid answer; omitting the section is not.

- [ ] **Step 9: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/53c96/source-map.json'
a = load_json(Path('tools/binrecon/out/53c96-ppc/published/analysis-reference-ida.json'))
m = json.load(open(MAP))
covered = set()
for cat in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    covered |= {e['address'] for e in m[cat]}
before = len(a['functions'])
a['functions'] = [f for f in a['functions'] if f['address'] in covered]
print('analysis functions', before, '-> scoped', len(a['functions']))
load_source_map(Path(MAP), reference_analysis=a, repo_root=Path.cwd())
print('load_source_map OK')
"
```

Expected: an `analysis functions N -> scoped M` line followed by `load_source_map OK`.

**Why the analysis is scoped before the check.** The map was built with `--scope-to-objc`, so it covers only the Objective-C functions. `load_source_map` enforces an *exact* partition, so handing it the unscoped analysis fails with `SemanticValidationError: source map partition mismatch` listing the unnamed jump islands — the very functions the map deliberately excludes. Restricting the analysis to the addresses the map covers checks the full partition, names, sizes and source-line bounds over everything the map claims. The functions removed here are not lost: the bucket reconciliation accounts for every one of them.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/53c96 && git commit -m "drivers-ppc: measure drvPPC53c96 against its shipped binary

Source map and bucket reconciliation for the largest of the five,
bsd/dev/ppc/drvApple96_SCSI."
```

---

## Task 7: Synthesis — `report.md` and full acceptance

**Files:**
- Create: `src/drivers-ppc/reconstruction/report.md`

**Interfaces:**
- Consumes: all five `src/drivers-ppc/reconstruction/<DIR>/findings.md` and `source-map.json` from Tasks 2–6.
- Produces: `src/drivers-ppc/reconstruction/report.md`, the spec's deliverable.

- [ ] **Step 1: Re-verify all five maps load**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map

PAIRS = [('Cuda','cuda-ppc'), ('53c96','53c96-ppc'), ('ATA','ata-ppc'),
         ('BMac','bmac-ppc'), ('Burgundy','burgundy-ppc')]
for d, key in PAIRS:
    mp = f'src/drivers-ppc/reconstruction/{d}/source-map.json'
    a = load_json(Path(f'tools/binrecon/out/{key}/published/analysis-reference-ida.json'))
    m = json.load(open(mp))
    covered = set()
    for cat in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
        covered |= {e['address'] for e in m[cat]}
    before = len(a['functions'])
    a['functions'] = [f for f in a['functions'] if f['address'] in covered]
    load_source_map(Path(mp), reference_analysis=a, repo_root=Path.cwd())
    print(f'{d} OK ({before} functions -> {len(a["functions"])} scoped)')
PY
```

Expected: five `OK` lines, each reporting the scoped count. This is acceptance item 3.

The analysis is restricted to the addresses each map covers before the check. `--scope-to-objc` maps do not claim the unnamed jump islands, and `load_source_map` enforces an exact partition, so the unscoped analysis fails with `SemanticValidationError: source map partition mismatch`. Scoping checks the full partition, names, sizes and source-line bounds over everything the map does claim; acceptance item 5's bucket reconciliation accounts for every function removed here.

- [ ] **Step 2: Collect the summary table**

```bash
cd $REPO && $VENVPY - <<'PY'
import json

PAIRS = [('Cuda','cuda-ppc'), ('53c96','53c96-ppc'), ('ATA','ata-ppc'),
         ('BMac','bmac-ppc'), ('Burgundy','burgundy-ppc')]
print(f"{'driver':10} {'total':>6} {'mapped':>7} {'unmap':>6} {'dup':>4} {'disp':>5} {'mapB':>8} {'unmapB':>8}")
for d, key in PAIRS:
    a = json.load(open(f'tools/binrecon/out/{key}/published/analysis-reference-ida.json'))
    m = json.load(open(f'src/drivers-ppc/reconstruction/{d}/source-map.json'))
    mb = sum(e['size'] for e in m['mapped'])
    ub = sum(e['size'] for e in m['unmapped'])
    print(f"{d:10} {len(a['functions']):6} {len(m['mapped']):7} {len(m['unmapped']):6} "
          f"{len(m['duplicate_candidates']):4} {len(m['boundary_disputed']):5} {mb:8} {ub:8}")
PY
```

Paste this table into `report.md` §1. Every `dup` column entry must be 0 (acceptance item 4).

- [ ] **Step 3: Write `report.md`**

`src/drivers-ppc/reconstruction/report.md`, five parts matching spec §4:

1. `## Correspondence` — Step 2's table, plus for each driver the named/unnamed split. Each row reconciles: mapped + unmapped + buckets = total.
2. `## Class inventory` — binary versus source per driver. Include the `IdeDisk`/`ATADisk` verdict from Task 5 Step 6.
3. `## Non-Objective-C remainder` — the bucket tables from all five `findings.md`, and merged `selector_check.py` output per driver. **State explicitly that buckets 1 and 2 are empty across all five, because these are statically linked kernel servers with no crt/dyld routines and no `__picsymbol_stub` section** — do not omit the buckets.
4. `## Findings` — each with its reference evidence. Must include the packaging gap: four of the five sources build into the kernel via `src/kernel-7/conf/files.ppc:83-133` under `mk_hasdrivers`, while the shipped artifacts are loadable kernel servers with their own `Default.table`, `DriverInfo` and `_reloc`. Recorded and deferred, per spec §1.2.
5. `## Decomposition proposal` — the per-driver specs to follow, **ranked by measured gap, not binary size**. Each entry states its mapped/unmapped counts, its bucket-6 functions, and whether the findings look like drift or a different driver version. List the tooling follow-on (naming IDA's PowerPC glue stubs so unscoped maps become possible, using this report's bucket tables as fixtures) as its own candidate.

Cite each per-driver `findings.md` from the section that summarizes it. Every number must trace to observed command output.

- [ ] **Step 4: Run the binrecon test suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: green. Baseline is 750 passed, 4 skipped. This is acceptance item 6. If Task 8 ran, the count will be higher by the tests it added.

- [ ] **Step 5: Confirm no generated evidence is staged**

```bash
cd $REPO && git status --porcelain | grep -c "tools/binrecon/out/" || echo "0 - clean"
```

Expected: `0 - clean`. Anything under `tools/binrecon/out/` must never be committed.

- [ ] **Step 6: Walk the acceptance list**

Confirm each item against observed output and record the evidence in `report.md` under a final `## Acceptance` section:

1. Ten `analyze` runs reported `"complete": true` and published `analysis-reference-ida.json`; exit 1 throughout, as designed.
2. `ppc_invariant_check.py` reported 0 relocation violations across all ten. Symbol/function-start mismatches enumerated, not required to be zero.
3. Five maps load via `load_source_map`, each against its reference analysis restricted to the addresses that map covers — Step 1.
4. `duplicate_candidates` is 0, or every entry is enumerated in the relevant `findings.md` with the evidence establishing its cause — Step 2. `boundary_disputed` likewise. `drvPPCATA` carries four explained entries; see spec §5 item 4.
5. Every function in every binary lands in exactly one bucket; per binary the buckets sum to IDA's **total** function count. `RECONCILES: yes` in Tasks 2–6.
6. Suite green — Step 4.
7. `report.md` carries all five parts, and §5 names each follow-on spec with its measured gap.

Any item that cannot be satisfied is stated plainly in `report.md` with what was tried. Do not claim an item that was not observed.

- [ ] **Step 7: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/report.md && git commit -m "drivers-ppc: report the five-driver PowerPC evidence base

Correspondence, class inventories, bucket reconciliation and the ranked
decomposition proposal for the per-driver reconstruction specs."
```

---

## Task 8: Contingency — an exporter defect blocks publication

**Run this task only if a `binrecon analyze` run in Tasks 5 or 6 fails to publish `analysis-reference-ida.json`.** If all ten published, skip it entirely.

**Files:**
- Modify: whichever `tools/binrecon/` exporter module rejects the fixup
- Test: `tools/binrecon/tests/` — a new test reproducing the rejected input

**Interfaces:**
- Produces: a published `analysis-reference-ida.json` for the blocked artifact, unblocking the task that sent you here.

Precedent: `scsitape-ppc` failed with `IDA export failed: malformed fixup target at 0x2e34`. IDA's PowerPC loader logged a `PPC_RELOC_SECTDIFF`-derived switch table in `__TEXT,__const` as an unhandled relocation, and the exporter's fixup-integrity check rejected the legitimate negative displacement as corruption. Commit `12a64a6c` fixed it; a later pass replaced the masking arithmetic with an explicit sign-extend-then-range-check so a target genuinely outside the 32-bit space is still rejected.

- [ ] **Step 1: Capture the exact failure**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
BINRECON_REFERENCE="$REF/<blocked artifact relative path>" PYTHONPATH=tools/binrecon \
  $VENVPY -m binrecon analyze \
  --profile "tools/binrecon/profiles/<blocked profile>.json" \
  --output "tools/binrecon/out/<blocked profile>/run-summary.json" 2>&1 | tail -40
```

Record the message and the address verbatim.

- [ ] **Step 2: Read the run summary diagnostic**

```bash
cd $REPO && $VENVPY -c "
import json
s=json.load(open('tools/binrecon/out/<blocked profile>/run-summary.json'))
print('complete',s['complete'])
print(json.dumps(s.get('diagnostic') or s, indent=1)[:2000])
"
```

A failed run is marked `complete: false` with a bounded diagnostic. That diagnostic names the check that rejected the input.

- [ ] **Step 3: Write a failing test for the rejected input**

Add a test under `tools/binrecon/tests/` that feeds the exact fixup shape from Step 1 to the rejecting function and asserts the correct decode. Follow the existing PowerPC relocation tests for structure.

Run it and confirm it fails:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests/<new test file> -q
```

Expected: FAIL, for the reason Step 1 reported.

- [ ] **Step 4: Make the narrowest fix**

Fix only the rejecting check, following `12a64a6c`'s precedent: sign-extend then range-check, so a fixup target genuinely outside the 32-bit address space is still rejected. **Do not widen what the integrity check accepts** beyond the legitimate case, and do not touch anything the blocked artifact does not exercise.

- [ ] **Step 5: Confirm the test passes and nothing regressed**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: green, with the new test included and the prior baseline intact.

- [ ] **Step 6: Re-run the blocked analysis**

Repeat Step 1's command. Expected: `normalized-functions=FAIL`, exit 1, `"complete": true`, and `published/analysis-reference-ida.json` present.

- [ ] **Step 7: Commit**

```bash
cd $REPO && git add tools/binrecon && git commit -m "binrecon: accept the scattered section-difference fixup at <address>

The exporter rejected a legitimate negative displacement as corruption,
blocking <artifact> from publishing."
```

- [ ] **Step 8: Return to the task that sent you here** and continue from its verification step.

---

## Notes for the executing agent

- **Exit 1 from `analyze` is success.** It will happen twenty times. Do not treat it as a failure, do not try to make it exit 0.
- **Never commit `tools/binrecon/out/`.**
- **Never edit driver source.** If a divergence looks trivially fixable, record it; do not fix it.
- **Every number in a `findings.md` or `report.md` must come from output you observed.** Do not infer, round, or carry a number forward from this plan's calibration section except where a step explicitly asks you to compare against it.
- **`RECONCILES: no` is a stop condition.** Acceptance item 5 cannot be met until every function is bucketed.
