# i386 Audio Driver Binary Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `drvBeepSound`, `drvSB8Sound`, `drvES1x88Sound` and `drvSB16Sound` against Apple's shipped i386 driver binaries, producing a committed source map, parity ledger and divergence document per driver, and fixing every divergence found.

**Architecture:** Per driver, a report pass runs disassemblers over the reference binary, maps every reference function to a file and line, and records divergences; a separate fix pass then repairs the source and advances the ledger. A one-off table pass runs first, ahead of all report passes, to land the fixes whose evidence is a direct diff of checked-in files rather than a decompilation.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, `tools/binrecon` (angr 9.3.0, jsonschema 4.26.0), IDA Professional 9.2 (`idat.exe`), Ghidra 12.1 headless on Java 21, Objective-C for Rhapsody DriverKit, `gnumake` with NeXT `pb_makefiles` inside a Rhapsody DR2 guest.

**Spec:** [2026-07-25-i386-audio-driver-binary-reconstruction-design.md](../specs/2026-07-25-i386-audio-driver-binary-reconstruction-design.md)

## Global Constraints

Every task's requirements implicitly include this section.

- **Never commit reference binaries, rebuilt artifacts, or analyzer output.** `tools/binrecon/out/` is excluded by `.gitignore:17`. Rebuilt `_reloc` files stage to `out/i386/` and stay untracked.
- **Run all `binrecon` commands from the repository root `D:\RhapsodiOS`** with `PYTHONPATH=tools/binrecon`. Analyzer executable paths in profiles are resolved by the host process, so a different cwd breaks them.
- **Python interpreter is `.venv-binrecon/Scripts/python.exe`.** Not `python`, not `py`. Bare `python` is not on `PATH` in this environment and a heredoc piped to it will hang waiting on stdin.
- **`${BINRECON_REFERENCE}` is the only variable expanded in profile artifact paths.** It must be set per shell session. An unset variable is an error.
- **`"Driver Version"` is out of every comparison.** It is emitted by Apple's build.
- **Commit messages start with the subsystem**, e.g. `drivers-i386: `, `binrecon: `. One to two lines, describing what the change does, not which files moved. No metadata, no `Co-Authored-By`, no `Generated with` trailer.
- **A diverging function stays `unexamined` in the ledger** and gets an entry in `divergences.md`. Advancing its status is the fix pass's job. This is the drvPCIBus convention.
- **Never advance a ledger status without evidence.** `assembly-matched` means the full disassembly was read instruction by instruction. `control-flow-confirmed` means block shape and call targets were checked but not every instruction. Claiming the stronger status without doing the work is the single worst failure mode in this plan.
- **Surgical changes only.** Every changed line traces to a ledger-flagged divergence or to an explicitly approved exception (§4.3 of the spec names three). Do not improve adjacent code, reformat, or refactor code that is not divergent.
- **`out/` and `tools/binrecon/out/` already exist.** Do not `mkdir` them.
- **`$SCRATCH` is this session's scratchpad directory**, given in the environment preamble as `C:\Users\RAYNOR~2\AppData\Local\Temp\claude\D--RhapsodiOS\<session-id>\scratchpad`. Export it once per shell before running any step that writes a helper script: `export SCRATCH='<that path>'`. Helper scripts written there are per-session; a task that needs one writes it itself rather than assuming an earlier task's copy survives.
- **`MicrosoftSound` is not in this effort.** `MicrosoftSound.config` sits in the same reference directory and has no source anywhere in `src/drivers-i386/sound`. So do `drvIntelAC97Sound` and `drvSB128Sound`, which have no reference binary. No task touches any of the three.

### Reference binaries

External to the repo, under `C:\Users\raynorpat\Downloads\test\Drivers\i386`:

| Driver | Reference `_reloc` | Size | `__text` | Functions | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| drvBeepSound | `Beep.config/Beep_reloc` | 37984 | 2060 | 13 | `752B5A078A747CE0ED0C36951C5DED5DD99DD2420CD4CFF979D12059A53D6C73` |
| drvSB8Sound | `SoundBlaster8.config/SoundBlaster8_reloc` | 53552 | 8896 | 29 | `3CE9787321C1E52D62BF1B19CFC58BD6F7340A98D5C6FEAEC8B92B5E6A8EC9D4` |
| drvES1x88Sound | `ES1x88AudioDriver.config/ES1x88AudioDriver_reloc` | 53280 | 8660 | 25 | `196F94DC778DB5A2AFE7763A2F4559ED96F27B46AB813674A5C098B75667DAD3` |
| drvSB16Sound | `SoundBlaster16.config/SoundBlaster16_reloc` | 58224 | 13572 | 28 | `08EC130B85B64E289B17DC32DBE9D69D56FF48DAA9E4CD26FA935DDFC52A9001` |

The SHA-256 in each committed `source-map.json` and `ledger.json` must match its row exactly. `load_source_map` enforces this.

### Per-driver naming

Every task substitutes from this table. Nothing else varies between drivers.

| `<name>` | `<drv>` | `<drvproj>` | `<lksproj>` | `<Config>` | Functions |
| --- | --- | --- | --- | --- | --- |
| `beep` | `drvBeepSound` | `Beep.drvproj` | `Beep.lksproj` | `Beep` | 13 |
| `soundblaster8` | `drvSB8Sound` | `SoundBlaster8.drvproj` | `SoundBlaster8.lksproj` | `SoundBlaster8` | 29 |
| `es1x88audiodriver` | `drvES1x88Sound` | `ES1x88AudioDriver.drvproj` | `ES1x88AudioDriver.lksproj` | `ES1x88AudioDriver` | 25 |
| `soundblaster16` | `drvSB16Sound` | `SoundBlaster16.drvproj` | `SoundBlaster16.lksproj` | `SoundBlaster16` | 28 |

Source directory is always `src/drivers-i386/sound/<drv>/<drvproj>/<lksproj>`. All four keep their kernel sources in that one directory, so a single `--source-dir` covers each.

### Standard report pass procedure

Tasks 3, 5, 7 and 9 all follow this.

**Step A — set the reference and analyze.** From the repo root:

```bash
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\<Config>.config\<Config>_reloc'
./.venv-binrecon/Scripts/python.exe -m binrecon analyze \
  --profile tools/binrecon/profiles/<name>.json \
  --output tools/binrecon/out/<name>/run-summary.json
```

**Expected: exit 1, and that is success here.** `binrecon analyze` returns 0 only when the profile's acceptance level passes, and `normalized-functions` acceptance compares a reference against a *rebuilt* artifact. These are reference-only profiles with no `rebuilt` key, so acceptance can never pass and the last line always reads `normalized-functions=FAIL`. Every committed run under `tools/binrecon/out/` shows the same `acceptance.passed: false`. Do not treat this as a failure, and do not add a `rebuilt` key to make it go away.

**The real gate is the summary, not the exit code:**

```bash
./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('tools/binrecon/out/<name>/run-summary.json'))
assert d['complete'] is True, d
assert d['consensus']['reference'] is not None, d
print('complete:', d['complete'], 'sha:', d['reference_sha256'])
"
ls tools/binrecon/out/<name>/published/
```

Expected: `complete: True`, the SHA-256 matching this driver's row in the Reference binaries table, and — with all three analyzers enabled — four files: `analysis-reference-ida.json`, `-ghidra.json`, `-angr.json`, `consensus-reference.json`.

A run that times out or genuinely fails writes `complete: false` and no reference consensus. *That* is a failure, and it must not be worked around by reusing an earlier run's output — the runner refuses leftover output from an earlier run as evidence, and so must you.

Piping this command through `tail` or `head` makes `$?` report the pipe's last stage, not binrecon's. Redirect to a file if you need the exit code.

If a staging directory named `binrecon-run-*` is left under `tools/binrecon/out/<name>/` with no `published/` beside it, the run did not finish. Do not mistake such a directory for output.

Two adapter behaviours are automatic and are not errors: Ghidra first tries its Mach-O loader and falls back to deterministic raw i386 import using parsed Mach-O sections when that loader rejects a legacy input, and angr's `CFGFast` records unresolved indirect control flow as CFG errors. Neither means a function is absent. All four drivers dispatch through `objc_msgSend`, so expect angr CFG errors in every task.

**If Ghidra aborts normalization** with `Ghidra relocation operand metadata is ambiguous` (`normalize.py:432`), the run writes `complete: false` and no consensus. Three of the five input drivers hit this. The approved response, per the spec's Failure modes section, is to set `analyzers.ghidra.enabled: false` in that driver's profile and re-run with IDA + angr. Do **not** work around it any other way, and do not re-enable Ghidra later to "fix" a two-analyzer run. Consequences: `published/` holds three files instead of four with no `analysis-reference-ghidra.json`, `run-summary.json`'s `analyzers` list has two entries, that driver's `divergences.md` must state the reduced analyzer set as a stated limitation of its evidence, and its analyzer-disagreement section covers IDA against angr only. Commit the profile change in its own commit with a message naming the normalization error.

**Step B — build the source map.** IDA is authoritative for the function partition, per the drvPCIBus convention:

```bash
./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/<name>/published/analysis-reference-ida.json \
  --binary "$BINRECON_REFERENCE" \
  --source-dir src/drivers-i386/sound/<drv>/<drvproj>/<lksproj> \
  --repo-root . \
  --output src/drivers-i386/sound/<drv>/reconstruction/source-map.json
```

`source_sites` globs `*.m` and `*.c` in `--source-dir` non-recursively. Three of the four drivers keep substantial code in `*Inline.h` headers that this glob does not see; a function whose body lives in a header still maps to the `.m` translation unit that includes it, and the `source_line` points at the `#import` site or the call site. Record which functions are in that situation in `divergences.md`, because their `source_line` is weaker evidence than a direct definition.

**Step C — hand-resolve the residue.** Every reference function must land in exactly one of `mapped`, `unmapped`, `boundary_disputed`, `duplicate_candidates`. Entries within each bucket must be sorted by `(address, reference_names)` — `validate_source_map_semantics` rejects any other order. The two build-generated glue methods per driver (`+[<Config>KernelServerInstance kernelServerInstance]` and `+[<Config>Version driverKitVersionFor<Config>]`) belong in `unmapped`. Data symbols outside `__TEXT,__text` do not appear in the source map at all.

One driver has a third `unmapped` entry: `+[Beep probe:]` at address 0, 68 bytes, has no source counterpart at all. Its reason class is "no source counterpart", not "build-generated glue"; Task 4 writes the method.

**Step D — validate the source map.** This is the report pass's gate. Write the checker to the scratchpad rather than piping a heredoc into Python:

```bash
cd /d/RhapsodiOS
cat > "$SCRATCH/check_map.py" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.schema import load_json, load_source_map
name, drv = sys.argv[1], sys.argv[2]
analysis = load_json(Path(f'tools/binrecon/out/{name}/published/analysis-reference-ida.json'))
load_source_map(
    Path(f'src/drivers-i386/sound/{drv}/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map OK')
PY
./.venv-binrecon/Scripts/python.exe "$SCRATCH/check_map.py" <name> <drv>
```

Expected: `source map OK`. Any `SemanticValidationError` names the exact failure — a missing address, a wrong size, a source line outside the function, a partition gap. Fix the map, do not weaken the check.

**Step E — diff every mapped function.** Decompile each and compare against our source, batched by source file. Compare control-flow shape, literal constants, I/O port addresses, struct field offsets, and call targets. Read the disassembly; do not infer from names.

**Step F — compare the tables.** Diff every config table for this driver against the reference copy, ignoring `"Driver Version"`. After Task 2 this must be clean. A residual difference is a Task 2 defect, not a new finding — say so explicitly in `divergences.md`.

Which tables per driver:

| Driver | Tables |
| --- | --- |
| drvBeepSound | `Default.table` |
| drvSB8Sound | `Default.table` |
| drvES1x88Sound | `Default.table`, `ESPnP.table` |
| drvSB16Sound | `Default.table`, `SB16PnP.table`, `SB16SingleDMAChannelPnP.table`, `SingleDMAChannel.table` |

**Step G — write `divergences.md`.** Follow the shape of `src/drivers-i386/bus/drvPCIBus/reconstruction/divergences.md`: a header naming the reference and its SHA-256 and the analyzer versions actually used, a baseline-build note, a bucket-count summary table, a statement of how many functions were examined at which depth, an unmapped/build-generated section, an analyzer-disagreement section, then numbered findings. Each finding carries the source path and line, the reference disassembly, and our source side by side.

Also record, for every driver, the `Loaded Server` section sizes the build actually produces, or state that they are unmeasured if the guest was unavailable. The reference values are `Load Commands` 144 for Beep, SoundBlaster8 and ES1x88AudioDriver and 210 for SoundBlaster16, with **no** `Unload Commands` section in any of the four.

**Step H — write `ledger.json`.** `binrecon ledger` resolves the profile's reference artifact, so `BINRECON_REFERENCE` must still be exported in the shell when you run it — the same value Step A used.

`schema-version` `ledger-v1`, `reference_sha256` from the Reference binaries table, `rebuilt_sha256` `null`. One entry per reference function with `address`, `names`, `size`, `source_path`, `source_line`, `status`, `reason`, `reviewer`, `artifacts`, and `analyzer_agreement` (`{analyzers, reasons, status}`). Build-generated glue gets `intentional-mismatch` with a reason naming the Kernel Server project type and a reviewer. Verify with:

```bash
./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/<name>.json \
  --ledger src/drivers-i386/sound/<drv>/reconstruction/ledger.json
```

**Step I — commit.** Two commits: one for the source map, one for the ledger and divergence document.

### Standard fix pass procedure

Tasks 4, 6, 8 and 10 all follow this.

**Step A — baseline build, before any source edit.**

The guest is a separate Rhapsody 5.6 PPC machine; connection details are in `vm/vm.conf` (`Host`, `User`, `Password`, `RemoteRoot=/build/source`). Reach it with `plink`/`pscp` from `C:\Program Files\PuTTY\`.

**Sync only this driver's directory.** Do not use `vm/rhap-vm.ps1 sync` — it uploads all of `src/`, which would carry a concurrent session's uncommitted work onto the shared build host:

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" \
  src/drivers-i386/sound/<drv> root@$HOST:/build/source/src/drivers-i386/sound/
"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$PW" \
  vm/build-i386-sound-recon.sh root@$HOST:/build/source/vm/
```

Then strip CR (Windows checkouts carry CRLF, and Rhapsody's `gnumake` treats CR as part of target names) and build. The guest's root shell is `tcsh` and `/bin/sh` is a 1999 Bourne shell: **no `2>&1` inside the remote command string, and no nested double quotes.** Redirect on the local side:

```bash
"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST \
  'tr -d "\r" < /build/source/vm/build-i386-sound-recon.sh > /tmp/br && mv /tmp/br /build/source/vm/build-i386-sound-recon.sh; sh /build/source/vm/build-i386-sound-recon.sh <drv>' \
  > /tmp/bld.log 2>&1
echo "EXIT=$?"
tail -3 /tmp/bld.log
```

Expected on success: `EXIT=0` and a final line `=== sound-recon done fail=0 built: <drv> ===`. On failure: `EXIT=1` and `FAILED: no <Config>_reloc for <Config>`.

Inside the guest the equivalent single command is:

```bash
sh /build/source/vm/build-i386-sound-recon.sh <drv>
```

**No baselines have been established for any of these four.** All are marked "needs compiled and then tested" in `src/drivers-i386/README` and may never have been built. Record whatever this run produces, including the staged `_reloc` size — ours is unstripped and will be several times the reference size, which is expected and not a finding. If the baseline fails, repairing that breakage is a separate commit landed **before** any divergence fix, so a pre-existing failure is never misattributed to this work.

**Step B — baseline parity.** Copy the staged `_reloc` to the host, then:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "$BINRECON_REFERENCE" out/i386/<drv>/<Config>.config/<Config>_reloc
```

Prints `missing_strings`, `missing_symbols`, `extra_strings`, `extra_symbols` with counts, and exits 1 if either `missing_` list is non-empty. Record the baseline numbers — they are what the fix has to improve.

Two expected classes of extra, neither a finding: our unstripped build carries symbols Apple's does not, and drvSB8Sound and drvSB16Sound wrap many `IOLog` calls in `#ifdef DEBUG`. If the guest build defines `DEBUG`, those strings appear as extras; if it does not, they are absent from both sides. Either way they are not findings.

**Step C — fix each finding.** Work through `divergences.md` in order. Every finding resolves one of two ways: source changed to match the reference, or accepted as `intentional-mismatch`. Nothing is left undecided.

**Step D — advance the ledger.** For each fixed function, set the status the new evidence supports. For each accepted divergence:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/<name>.json \
  --ledger src/drivers-i386/sound/<drv>/reconstruction/ledger.json \
  --address 0x<addr> --status intentional-mismatch \
  --reason '<why this divergence is accepted>' --reviewer 'Pat Raynor'
```

An `intentional-mismatch` requires both `--reason` and `--reviewer`; the CLI rejects it otherwise.

**Step E — rebuild and re-check parity.** Repeat Steps A and B. `missing_strings` and `missing_symbols` must be at or below the baseline, and every string or symbol named in a fixed finding must be gone from the missing lists.

**Step E2 — reline the source map. MANDATORY, and the step most easily forgotten.**

Any fix pass that adds or removes source lines invalidates every `source_line` in `source-map.json` and `ledger.json`. This bit the input effort twice. **Regenerate before committing, every time.**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='<this driver's reference path>'
./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/<name>/published/analysis-reference-ida.json \
  --binary "$BINRECON_REFERENCE" \
  --source-dir src/drivers-i386/sound/<drv>/<drvproj>/<lksproj> \
  --repo-root . --output "$SCRATCH/<name>-fresh.json"
```

Write it to scratch, **not** over the committed map — the fresh one has no hand-resolved bucket assignments. Then copy `source_line` and `source_path` across by `address` into both `source-map.json` and `ledger.json`, keeping the committed bucket assignments. If the fresh run's bucket counts differ from the committed map's, stop: the fix changed the function partition and that needs a human look, not an automatic merge. For drvES1x88Sound (Task 8) the counts *will* differ, because methods are being removed — that task says what to do.

Confirm with the report-pass gate from Step D of the report procedure, which must print `source map OK`.

**Step F — per-function size check.** For every function rewritten from the disassembly, compare its size in the rebuilt binary against the reference:

```bash
cd /d/RhapsodiOS
cat > "$SCRATCH/fnsize.py" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.macho import read_macho

TEXT = '__TEXT,__text'

def sizes(p):
    d = read_macho(Path(p))
    sec = next(s for s in d['sections'] if s['name'] == TEXT)
    syms = sorted([s for s in d['symbols'] if s['section'] == TEXT],
                  key=lambda s: s['address'])
    end = sec['address'] + sec['size']
    out = {}
    for i, s in enumerate(syms):
        nxt = syms[i + 1]['address'] if i + 1 < len(syms) else end
        out[s['name']] = nxt - s['address']
    return out

ref, built = sizes(sys.argv[1]), sizes(sys.argv[2])
for name in sorted(set(ref) & set(built)):
    r, b = ref[name], built[name]
    flag = '  <-- LARGER' if b > r * 1.25 else ''
    print(f'{r:6} {b:6} {name}{flag}')
for name in sorted(set(ref) - set(built)):
    print(f'{ref[name]:6}      - {name}  <-- MISSING')
PY
./.venv-binrecon/Scripts/python.exe "$SCRATCH/fnsize.py" \
  "$BINRECON_REFERENCE" out/i386/<drv>/<Config>.config/<Config>_reloc
```

A rewritten function flagged `LARGER` means we invented structure again — go back to the disassembly rather than accepting it. Our build is unoptimised relative to Apple's, so a modest excess on functions we did *not* rewrite is expected and is not a finding.

**Step G — commit.** One commit for the source fixes, one for the ledger and `divergences.md` update.

**Guest dependency.** Steps A, B, E and F need the Rhapsody DR2 guest. If it is unavailable, the source fixes and ledger work still land, and the task reports explicitly which of the three §4.3 checks went unrun. Do not claim a check passed that was not run.

---

### Task 1: Profiles and build harness

**Files:**
- Create: `tools/binrecon/profiles/beep.json`
- Create: `tools/binrecon/profiles/soundblaster8.json`
- Create: `tools/binrecon/profiles/es1x88audiodriver.json`
- Create: `tools/binrecon/profiles/soundblaster16.json`
- Create: `vm/build-i386-sound-recon.sh`
- Reference: `tools/binrecon/profiles/ps2mouse.json`, `vm/build-i386-input-recon.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: four profile paths named `tools/binrecon/profiles/<name>.json` where `<name>` is `beep`, `soundblaster8`, `es1x88audiodriver`, `soundblaster16` — the lower-cased reference server name, not the `drv` directory name, matching the existing `pcibus.json` / `ps2keyboard.json` convention. Each sets `output_dir` to `../out/<name>`, resolved relative to the `profiles` directory, so analyzer output lands in `tools/binrecon/out/<name>`. Also produces `vm/build-i386-sound-recon.sh`, invoked as `sh vm/build-i386-sound-recon.sh [<drv> …]`, which with no arguments builds all four and with arguments builds only the named `drv*` directories.

- [ ] **Step 1: Write the four profiles**

`tools/binrecon/profiles/beep.json`:

```json
{
  "schema_version": "profile-v1",
  "name": "drvBeepSound reconstruction",
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
      "enabled": true,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": true,
      "executable": ".venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/beep"
}
```

The other three are byte-identical except for `name` and `output_dir`:

| File | `name` | `output_dir` |
| --- | --- | --- |
| `soundblaster8.json` | `drvSB8Sound reconstruction` | `../out/soundblaster8` |
| `es1x88audiodriver.json` | `drvES1x88Sound reconstruction` | `../out/es1x88audiodriver` |
| `soundblaster16.json` | `drvSB16Sound reconstruction` | `../out/soundblaster16` |

All four start with Ghidra enabled. A driver that aborts normalization gets it disabled in its own report-pass task, per the Standard report pass procedure. There is no `rebuilt` key: these are reference-only profiles, and the fix passes verify with `parity_check.py`, not with a binrecon comparison.

- [ ] **Step 2: Validate all four profiles**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
for pair in "beep:Beep" "soundblaster8:SoundBlaster8" \
            "es1x88audiodriver:ES1x88AudioDriver" "soundblaster16:SoundBlaster16"; do
  name=${pair%%:*}; cfg=${pair##*:}
  export BINRECON_REFERENCE="C:\\Users\\raynorpat\\Downloads\\test\\Drivers\\i386\\${cfg}.config\\${cfg}_reloc"
  echo "--- $name"
  ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile "tools/binrecon/profiles/${name}.json"
done
```

Expected: four blocks, each printing the resolved absolute reference path, its size, and its SHA-256, with no rebuilt artifact. Each size and SHA-256 must match its row in the Reference binaries table. Exit 0 for all four.

- [ ] **Step 3: Write the build script**

`vm/build-i386-sound-recon.sh`. The `build_one` body is copied verbatim from the committed `vm/build-i386-input-recon.sh` with three changes: `INPUT` becomes `SOUND` and points at `sound`, the `InstallPPDev`/`RemovePPDev` staging loop is dropped (no audio driver has user-space helpers), and the `README.txt` heredoc loses its PreLoad/PostLoad sentence.

```sh
#!/bin/sh
# Build the i386 audio drivers under reconstruction; stage reloc bundles.
# Accept success when the loadable *_reloc exists.
#
# No `set -e`: Rhapsody's 1999 Bourne /bin/sh applies it to any function
# returning nonzero, so a driver that fails to build would abort the loop
# instead of setting fail=1 and letting the rest run.

export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
SOUND=/build/source/src/drivers-i386/sound
mkdir -p "$OUT"

FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

build_one() {
	name="$1"	# Beep / SoundBlaster8 / ...
	dir="$2"	# drvBeepSound / drvSB8Sound / ...
	proj="$3"	# Beep.drvproj / SoundBlaster8.drvproj / ...
	src="$SOUND/$dir"
	if [ ! -f "$src/Makefile" ]; then
		echo "MISSING $src/Makefile" >&2
		return 1
	fi
	echo "======== build $name ($dir) ========"
	cd "$src"
	find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
	while read f; do
		tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
	done

	gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
	ec=$?
	echo "make exit=$ec for $name"

	reloc=
	for cand in \
		"$src/$name.config/${name}_reloc" \
		"$src/$proj/$name.config/${name}_reloc" \
		"$src/${name}.config/${name}_reloc"
	do
		if [ -f "$cand" ]; then
			reloc=$cand
			break
		fi
	done
	if [ -z "$reloc" ]; then
		reloc=`find "$src" -name "${name}_reloc" -type f 2>/dev/null | head -1`
	fi
	if [ -z "$reloc" ] || [ ! -f "$reloc" ]; then
		echo "FAILED: no ${name}_reloc for $name" >&2
		find "$src" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2 || true
		return 1
	fi
	file "$reloc"

	dst="$OUT/$dir/$name.config"
	rm -rf "$dst"
	mkdir -p "$dst"
	cp -p "$reloc" "$dst/"
	if [ -d "$src/$proj" ]; then
		for f in "$src/$proj"/*.table; do
			[ -f "$f" ] || continue
			cp -p "$f" "$dst/"
		done
		if [ -f "$src/$proj/DriverInfo" ]; then
			cp -p "$src/$proj/DriverInfo" "$dst/"
		fi
		if [ -d "$src/$proj/English.lproj" ]; then
			cp -rp "$src/$proj/English.lproj" "$dst/"
		fi
	fi
	if [ ! -f "$dst/Default.table" ] && [ -f "$src/$proj/Default.table" ]; then
		cp -p "$src/$proj/Default.table" "$dst/"
	fi

	cat > "$OUT/$dir/README.txt" <<EOF
i386 $name ($dir)
-----------------
${name}_reloc is the i386 loadable kernel server (kl_ld).
make exit status was: $ec
EOF
	echo "staged $dst"
	ls -la "$dst"
	return 0
}

# With no arguments, build every driver. Otherwise build only those named,
# by directory name, e.g. `sh build-i386-sound-recon.sh drvBeepSound`.
#
# This dispatches through `case` rather than a want()-returns-status helper,
# for the same shell reason given above.
if [ $# -eq 0 ]; then
	TARGETS="drvBeepSound drvSB8Sound drvES1x88Sound drvSB16Sound"
else
	TARGETS="$*"
fi

fail=0
built=
for d in $TARGETS; do
	case "$d" in
	drvBeepSound)
		build_one Beep drvBeepSound Beep.drvproj || fail=1
		;;
	drvSB8Sound)
		build_one SoundBlaster8 drvSB8Sound SoundBlaster8.drvproj || fail=1
		;;
	drvES1x88Sound)
		build_one ES1x88AudioDriver drvES1x88Sound ES1x88AudioDriver.drvproj || fail=1
		;;
	drvSB16Sound)
		build_one SoundBlaster16 drvSB16Sound SoundBlaster16.drvproj || fail=1
		;;
	*)
		echo "unknown driver: $d" >&2
		fail=1
		continue
		;;
	esac
	built="$built $d"
done

echo "======== summary ========"
for d in $built; do
	find "$OUT/$d" -type f 2>/dev/null | sort || true
done
for d in $built; do
	find "$OUT/$d" -name '*_reloc' -type f -exec file {} \; 2>&1 || true
done
echo "=== sound-recon done fail=$fail built:$built ==="
exit $fail
```

The closing `exit $fail` is required. Without it the script always exits 0, which would make the "Expected: `EXIT=0`" gate in the Standard fix pass procedure vacuous and let a failed driver build pass every check.

The `drv` directory name and the reference `_reloc` name differ for three of the four: `drvSB8Sound` builds `SoundBlaster8`, `drvSB16Sound` builds `SoundBlaster16`, `drvES1x88Sound` builds `ES1x88AudioDriver`. The `build_one name dir proj` argument order above is correct for all four; do not reorder it.

- [ ] **Step 4: Check the script parses**

```bash
cd /d/RhapsodiOS
sh -n vm/build-i386-sound-recon.sh && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/binrecon/profiles/beep.json tools/binrecon/profiles/soundblaster8.json \
        tools/binrecon/profiles/es1x88audiodriver.json tools/binrecon/profiles/soundblaster16.json \
        vm/build-i386-sound-recon.sh
git commit -m "binrecon: add i386 audio driver profiles and build harness

Reference-only profiles for Beep, SoundBlaster8, ES1x88AudioDriver and
SoundBlaster16 plus a build script modelled on the input-driver one."
```

---

### Task 2: Table pass

Lands the fixes whose evidence is a direct diff of our checked-in file against Apple's, a byte-count comparison against a reference section, or a file that is simply absent. This is the spec's §4.1 carve-out from the ledger-first discipline; it is authorised for exactly these three groups and nothing else.

**Files:**
- Modify: `src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Default.table`
- Modify: `src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/Default.table`
- Modify: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/Default.table`
- Modify: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SB16PnP.table`
- Modify: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SB16SingleDMAChannelPnP.table`
- Modify: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SingleDMAChannel.table`
- Modify: `src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Beep.lksproj/Load_Commands.sect`
- Modify: `src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/Load_Commands.sect`
- Modify: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/Load_Commands.sect`
- Create: `src/drivers-i386/sound/drvSB8Sound/PB.project`
- Create: `src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/PB.project`
- Create: `src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/SoundBlaster8.lksproj/PB.project`
- Create: `src/drivers-i386/sound/drvSB16Sound/PB.project`
- Create: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/PB.project`
- Create: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/PB.project`
- Create: `src/drivers-i386/sound/drvES1x88Sound/PB.project`
- Create: `src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/PB.project`
- Create: `src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/PB.project`
- Reference: `src/drivers-i386/sound/drvBeepSound/PB.project` and its two siblings

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: a tree in which all eight config tables differ from their reference copies only in `"Driver Version"`, all four `Load_Commands.sect` files are byte-identical to their reference `Loaded Server,Load Commands` sections, and every audio driver in scope has the three `PB.project` files the tree's conventions require. Tasks 3 through 11 all assume this state.

- [ ] **Step 1: Confirm the table gaps are still present**

```bash
cd /d/RhapsodiOS
REF='C:/Users/raynorpat/Downloads/test/Drivers/i386'
S=src/drivers-i386/sound
diff -u "$S/drvBeepSound/Beep.drvproj/Default.table"        "$REF/Beep.config/Default.table"
diff -u "$S/drvSB8Sound/SoundBlaster8.drvproj/Default.table" "$REF/SoundBlaster8.config/Default.table"
diff -u "$S/drvSB16Sound/SoundBlaster16.drvproj/Default.table" "$REF/SoundBlaster16.config/Default.table"
```

Expected: Beep differs only by two trailing added lines (`"Driver Version"` and `"Version" = "5.00"`); SoundBlaster8 shows `"Version" = "4.00"` removed after `"Instance"` and four lines added at the end; SoundBlaster16 shows two trailing added lines.

- [ ] **Step 2: Fix `drvBeepSound/Beep.drvproj/Default.table`**

Append one line after `"Server Name" = "Beep";` so the file reads:

```
"Title" = "Beep";
"Family" = "Audio";
"Location" = "";
"Instance" = "0";
"Driver Name" = "Beep";
"Frequency" = "880";
"Duration" = "100";
"Style" = "Plain";
"Help File" = "Beep.rtfd";
"Server Name" = "Beep";
"Version" = "5.00";
```

`"Driver Version"` is not added — our build regenerates it.

- [ ] **Step 3: Fix `drvSB8Sound/SoundBlaster8.drvproj/Default.table`**

Remove the `"Version" = "4.00";` line that currently sits after `"Instance" = "0";`, and append the three keys Apple's table ends with. The whole file becomes:

```
"Title" = "Sound Blaster 8";
"Family" = "Audio";
"Location" = "";
"Instance" = "0";
"Driver Name" = "SoundBlaster8";
"DMA Channels" = "1";
"IRQ Levels" = "5";
/* Valid I/O ports */
/* SB DSP: 0x210-0x21f 0x220-0x22f 0x230-0x23f 0x240-0x24f 0x250-0x25f 0x260-0x26f  */
/* Analog Joystick: 0x200-0x207 */
/* Adlib compatibility 0x388-0x389 */
/* SB20 DSP ports are: 0x220-0x22f and 0x240-0x24f */
/* SBPro DSP ports are: 0x220-0x237 and 0x240-0x257 */
"I/O Ports" = "0x0220-0x22f 0x200-0x207 0x388-0x389";
"Valid DMA Channels" = "0 1 3";
"Valid IRQ Levels" = "3 5 7 10";
"Help File" = "SB8.rtfd";
"Server Name" = "SoundBlaster8";
"Version" = "5.01";
```

`SB8.rtfd` is the name Apple's table uses. Our tree carries the help bundle as `SoundBlaster8.drvproj/English.lproj/DriverHelp/SB8_3_31.rtfd`, so the key does not resolve to a file that exists under that exact name. **Do not rename either side to make them agree** — the reference table is the artifact being matched, and whether Apple shipped a differently-named help bundle is not something this task can determine. Record the mismatch in drvSB8Sound's `divergences.md` in Task 5.

- [ ] **Step 4: Fix the four drvSB16Sound tables**

Each gains `"Version" = "4.02";` as its last line, after `"Server Name" = "SoundBlaster16";`. `SB16PnP.table` currently has no trailing newline after that line; add one, then the new line, so the file ends with a newline like the other three.

```bash
cd /d/RhapsodiOS
S=src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj
tail -c 1 "$S/SB16PnP.table" | od -c | head -1
```

Expected before the edit: the last byte is `;`, not `\n`. After the edit, re-run and expect `\n`.

- [ ] **Step 5: Verify all eight tables now differ only in `"Driver Version"`**

```bash
cd /d/RhapsodiOS
REF='C:/Users/raynorpat/Downloads/test/Drivers/i386'
S=src/drivers-i386/sound
for pair in \
  "drvBeepSound/Beep.drvproj/Default.table:Beep.config/Default.table" \
  "drvSB8Sound/SoundBlaster8.drvproj/Default.table:SoundBlaster8.config/Default.table" \
  "drvSB16Sound/SoundBlaster16.drvproj/Default.table:SoundBlaster16.config/Default.table" \
  "drvSB16Sound/SoundBlaster16.drvproj/SB16PnP.table:SoundBlaster16.config/SB16PnP.table" \
  "drvSB16Sound/SoundBlaster16.drvproj/SB16SingleDMAChannelPnP.table:SoundBlaster16.config/SB16SingleDMAChannelPnP.table" \
  "drvSB16Sound/SoundBlaster16.drvproj/SingleDMAChannel.table:SoundBlaster16.config/SingleDMAChannel.table" \
  "drvES1x88Sound/ES1x88AudioDriver.drvproj/Default.table:ES1x88AudioDriver.config/Default.table" \
  "drvES1x88Sound/ES1x88AudioDriver.drvproj/ESPnP.table:ES1x88AudioDriver.config/ESPnP.table"; do
  ours=${pair%%:*}; theirs=${pair##*:}
  echo "=== $theirs"
  diff <(grep -v 'Driver Version' "$REF/$theirs" | sed 's/[[:space:]]*$//' | grep -v '^$') \
       <(grep -v 'Driver Version' "$S/$ours"    | sed 's/[[:space:]]*$//' | grep -v '^$') \
    && echo "  identical"
done
```

Expected: `identical` for all eight. Any remaining difference must be resolved here, not deferred.

- [ ] **Step 6: Fix the three `Load_Commands.sect` files**

drvSB8Sound's already matches Apple's 144 bytes byte for byte and must not be touched.

drvBeepSound's and drvES1x88Sound's are 143 bytes: they are missing the trailing space on the fourth line, which reads `#` where Apple's reads `# `. drvSB16Sound's is the same generic 143-byte file where Apple ships a different 210-byte one.

Write all three with Python so the trailing space and the tab characters survive, and assert the lengths:

```bash
cd /d/RhapsodiOS
cat > "$SCRATCH/write_lc.py" <<'PY'
from pathlib import Path

GENERIC = (
    b"#\n"
    b"# Audio drivers must use these load commands to connect to\n"
    b"# NeXT user-level sound API.\n"
    b"# \n"
    b"SMAP\t\taudio0 audioMessages 0\n"
    b"ADVERTISE\taudio0\n"
    b"WIRE\n"
)
SB16 = (
    b"# \n"
    b"# This loadable kernel driver does not use a Mig-generated interface,\n"
    b"# so no handler or server interface is specified.\n"
    b"#\n"
    b"# This driver must be wired down.\n"
    b"WIRE\n"
    b"SMAP\t\taudio0 audioMessages 0\n"
    b"ADVERTISE\taudio0\n"
)
assert len(GENERIC) == 144, len(GENERIC)
assert len(SB16) == 210, len(SB16)

S = Path('src/drivers-i386/sound')
targets = [
    (S / 'drvBeepSound/Beep.drvproj/Beep.lksproj/Load_Commands.sect', GENERIC),
    (S / 'drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/Load_Commands.sect', GENERIC),
    (S / 'drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/Load_Commands.sect', SB16),
]
for path, content in targets:
    path.write_bytes(content)
    print(f'wrote {len(content)} bytes to {path}')
PY
./.venv-binrecon/Scripts/python.exe "$SCRATCH/write_lc.py"
```

Expected: three lines reporting 144, 144 and 210 bytes.

- [ ] **Step 7: Verify the four `Load_Commands.sect` files against the reference sections**

```bash
cd /d/RhapsodiOS
cat > "$SCRATCH/check_lc.py" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.macho import read_macho

REF = Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386')
S = Path('src/drivers-i386/sound')
PAIRS = [
    ('Beep', 'drvBeepSound/Beep.drvproj/Beep.lksproj'),
    ('SoundBlaster8', 'drvSB8Sound/SoundBlaster8.drvproj/SoundBlaster8.lksproj'),
    ('ES1x88AudioDriver', 'drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj'),
    ('SoundBlaster16', 'drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj'),
]
ok = True
for cfg, rel in PAIRS:
    binary = REF / f'{cfg}.config' / f'{cfg}_reloc'
    doc = read_macho(binary)
    raw = binary.read_bytes()
    sec = next(s for s in doc['sections'] if s['name'] == 'Loaded Server,Load Commands')
    want = raw[sec['offset']:sec['offset'] + sec['size']]
    have = (S / rel / 'Load_Commands.sect').read_bytes()
    match = want == have
    ok &= match
    print(f'{cfg:20} ref={len(want):4} ours={len(have):4} match={match}')
    assert not any(s['name'].startswith('Loaded Server,Unload') for s in doc['sections']), cfg
print('ALL MATCH' if ok else 'MISMATCH')
PY
./.venv-binrecon/Scripts/python.exe "$SCRATCH/check_lc.py"
```

Expected: four lines with `match=True` and sizes 144, 144, 144, 210, then `ALL MATCH`. The assertion also confirms no reference carries an `Unload Commands` section — no `Unload_Commands.sect` is created for any audio driver, unlike the input drivers.

- [ ] **Step 8: Create drvSB8Sound's three `PB.project` files**

These are Project Builder metadata, not build inputs — `gnumake` reads the Makefiles. They are added for consistency with every other driver in the tree, and their contents must agree with the Makefiles that already exist.

`src/drivers-i386/sound/drvSB8Sound/PB.project`, following `drvBeepSound/PB.project` with values from `drvSB8Sound/Makefile` (`NAME = SoundBlaster8`, `PROJECTVERSION = 2.6`, `PROJECT_TYPE = Aggregate`, `TOOLS = SoundBlaster8.drvproj`, `OTHERSRCS = Makefile.preamble Makefile Makefile.postamble README SoundBlaster8.info`):

```
{
    FILESTABLE = {
        BUNDLES = (SoundBlaster8.drvproj);
        OTHER_SOURCES = (Makefile, Makefile.preamble, Makefile.postamble, README, SoundBlaster8.info);
        SUBPROJECTS = ();
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac;
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc;
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac";
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc";
    PROJECTNAME = SoundBlaster8;
    PROJECTTYPE = Aggregate;
    PROJECTVERSION = 2.6;
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe";
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc";
}
```

`src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/PB.project`, following `drvBeepSound/Beep.drvproj/PB.project` — note this one is **not** brace-wrapped, matching the existing file — with values from `SoundBlaster8.drvproj/Makefile` (`PROJECTVERSION = 2.7`, `GLOBAL_RESOURCES = Default.table`, `TOOLS = SoundBlaster8.lksproj`, `OTHERSRCS = Makefile.preamble Makefile Makefile.postamble DriverInfo`):

```
FILESTABLE = {
    OTHER_SOURCES = (Makefile.preamble, Makefile, Makefile.postamble, DriverInfo);
    OTHER_RESOURCES = (Default.table);
    STRINGS_FILES = (Localizable.strings);
    TOOLS = (SoundBlaster8.lksproj);
    SUBPROJECTS = ();
};
LANGUAGE = English;
LOCALIZABLE_FILES = {
    Localizable.strings;
};
PROJECTVERSION = 2.7;
INSTALLDIR = "$(NEXT_ROOT)/private/Drivers";
PROJECTTYPE = Bundle;
PROJECTNAME = SoundBlaster8;
GENERATEMAIN = YES;
BUNDLE_EXTENSION = config;
```

`src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/SoundBlaster8.lksproj/PB.project`, following `Beep.lksproj/PB.project` with values from `SoundBlaster8.lksproj/Makefile` (`CLASSES = SoundBlaster8.m`, `HFILES = SoundBlaster8.h SoundBlaster8Inline.h SoundBlaster8Registers.h`, `OTHERSRCS = Makefile.preamble Makefile Makefile.postamble Load_Commands.sect`, `NEXTSTEP_PB_CFLAGS = -Wno-format`):

```
{
    DYNAMIC_CODE_GEN = NO;
    FILESTABLE = {
        CLASSES = (SoundBlaster8.m);
        H_FILES = (SoundBlaster8.h, SoundBlaster8Inline.h, SoundBlaster8Registers.h);
        OTHER_LINKED = ();
        OTHER_SOURCES = (
            Makefile.preamble,
            Makefile,
            Makefile.postamble,
            Load_Commands.sect
        );
        SUBPROJECTS = ();
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_COMPILEROPTIONS = "-Wno-format";
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac;
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc;
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac";
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc";
    PROJECTNAME = SoundBlaster8;
    PROJECTTYPE = "Kernel Server";
    PROJECTVERSION = 2.7;
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe";
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc";
}
```

Note the reference `Beep.lksproj/PB.project` names `Beep.lkc` in `OTHER_SOURCES` where the directory actually holds `Load_Commands.sect`. That is a pre-existing inconsistency in a file this task does not touch; the three new `.lksproj` files name `Load_Commands.sect`, matching their Makefiles' `OTHERSRCS`.

- [ ] **Step 9: Create drvSB16Sound's three `PB.project` files**

`src/drivers-i386/sound/drvSB16Sound/PB.project` — same shape as drvSB8Sound's root file, from `drvSB16Sound/Makefile` (`OTHERSRCS = Makefile.preamble Makefile Makefile.postamble`, no `README` or `.info`):

```
{
    FILESTABLE = {
        BUNDLES = (SoundBlaster16.drvproj);
        OTHER_SOURCES = (Makefile, Makefile.preamble, Makefile.postamble);
        SUBPROJECTS = ();
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac;
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc;
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac";
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc";
    PROJECTNAME = SoundBlaster16;
    PROJECTTYPE = Aggregate;
    PROJECTVERSION = 2.6;
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe";
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc";
}
```

`src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/PB.project` — from `SoundBlaster16.drvproj/Makefile`, whose `GLOBAL_RESOURCES` names all four tables:

```
FILESTABLE = {
    OTHER_SOURCES = (Makefile.preamble, Makefile, Makefile.postamble, DriverInfo);
    OTHER_RESOURCES = (
        Default.table,
        SB16PnP.table,
        SB16SingleDMAChannelPnP.table,
        SingleDMAChannel.table
    );
    STRINGS_FILES = (Localizable.strings);
    TOOLS = (SoundBlaster16.lksproj);
    SUBPROJECTS = ();
};
LANGUAGE = English;
LOCALIZABLE_FILES = {
    Localizable.strings;
};
PROJECTVERSION = 2.7;
INSTALLDIR = "$(NEXT_ROOT)/private/Drivers";
PROJECTTYPE = Bundle;
PROJECTNAME = SoundBlaster16;
GENERATEMAIN = YES;
BUNDLE_EXTENSION = config;
```

`src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/PB.project` — from `SoundBlaster16.lksproj/Makefile`. This is the one `.lksproj` of the three with a `LOCAL_RESOURCES = Localizable.strings` line and an `English.lproj` directory holding it, so it is the only one whose `LOCALIZABLE_FILES` is non-empty:

```
{
    DYNAMIC_CODE_GEN = NO;
    FILESTABLE = {
        CLASSES = (SoundBlaster16.m);
        H_FILES = (SoundBlaster16.h, SoundBlaster16Registers.h, SoundBlaster16Inline.h);
        OTHER_LINKED = ();
        OTHER_SOURCES = (
            Makefile.preamble,
            Makefile,
            Makefile.postamble,
            Load_Commands.sect
        );
        STRINGS_FILES = (Localizable.strings);
        SUBPROJECTS = ();
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {
        Localizable.strings;
    };
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_COMPILEROPTIONS = "-Wno-format";
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac;
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc;
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac";
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc";
    PROJECTNAME = SoundBlaster16;
    PROJECTTYPE = "Kernel Server";
    PROJECTVERSION = 2.7;
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe";
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc";
}
```

- [ ] **Step 10: Create drvES1x88Sound's three `PB.project` files**

`src/drivers-i386/sound/drvES1x88Sound/PB.project`:

```
{
    FILESTABLE = {
        BUNDLES = (ES1x88AudioDriver.drvproj);
        OTHER_SOURCES = (Makefile, Makefile.preamble, Makefile.postamble);
        SUBPROJECTS = ();
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac;
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc;
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac";
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc";
    PROJECTNAME = ES1x88AudioDriver;
    PROJECTTYPE = Aggregate;
    PROJECTVERSION = 2.6;
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe";
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc";
}
```

`src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/PB.project` — `GLOBAL_RESOURCES = Default.table ESPnP.table`:

```
FILESTABLE = {
    OTHER_SOURCES = (Makefile.preamble, Makefile, Makefile.postamble, DriverInfo);
    OTHER_RESOURCES = (Default.table, ESPnP.table);
    STRINGS_FILES = (Localizable.strings);
    TOOLS = (ES1x88AudioDriver.lksproj);
    SUBPROJECTS = ();
};
LANGUAGE = English;
LOCALIZABLE_FILES = {
    Localizable.strings;
};
PROJECTVERSION = 2.7;
INSTALLDIR = "$(NEXT_ROOT)/private/Drivers";
PROJECTTYPE = Bundle;
PROJECTNAME = ES1x88AudioDriver;
GENERATEMAIN = YES;
BUNDLE_EXTENSION = config;
```

`src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/PB.project`:

```
{
    DYNAMIC_CODE_GEN = NO;
    FILESTABLE = {
        CLASSES = (ES1x88AudioDriver.m);
        H_FILES = (
            ES1x88AudioDriver.h,
            ES1x88AudioDriverRegisters.h,
            ES1x88AudioDriverInline.h
        );
        OTHER_LINKED = ();
        OTHER_SOURCES = (
            Makefile.preamble,
            Makefile,
            Makefile.postamble,
            Load_Commands.sect
        );
        SUBPROJECTS = ();
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_COMPILEROPTIONS = "-Wno-format";
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac;
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc;
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac";
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc";
    PROJECTNAME = ES1x88AudioDriver;
    PROJECTTYPE = "Kernel Server";
    PROJECTVERSION = 2.7;
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe";
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc";
}
```

- [ ] **Step 11: Verify every audio driver in scope has three `PB.project` files**

```bash
cd /d/RhapsodiOS
for d in drvBeepSound drvSB8Sound drvES1x88Sound drvSB16Sound; do
  n=$(find "src/drivers-i386/sound/$d" -name PB.project | wc -l)
  echo "$d $n"
done
```

Expected: `3` for all four.

- [ ] **Step 12: Commit**

Three commits, because the three groups have independent evidence:

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Default.table \
        src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/Default.table \
        src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/Default.table \
        src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SB16PnP.table \
        src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SB16SingleDMAChannelPnP.table \
        src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SingleDMAChannel.table
git commit -m "drivers-i386: match the audio driver config tables to Apple's

Adds the missing Version lines, and gives SoundBlaster8 the Help File and
Server Name keys it was missing in place of a stray Version."

git add src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Beep.lksproj/Load_Commands.sect \
        src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/Load_Commands.sect \
        src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/Load_Commands.sect
git commit -m "drivers-i386: match the audio Load_Commands sections to Apple's

Beep and ES1x88 were one byte short; SoundBlaster16 ships a different
210-byte variant that wires down before mapping the sound port."

git add src/drivers-i386/sound/drvSB8Sound/PB.project \
        src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/PB.project \
        src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/SoundBlaster8.lksproj/PB.project \
        src/drivers-i386/sound/drvSB16Sound/PB.project \
        src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/PB.project \
        src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/PB.project \
        src/drivers-i386/sound/drvES1x88Sound/PB.project \
        src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/PB.project \
        src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/PB.project
git commit -m "drivers-i386: add the missing audio driver PB.project scaffolding

SoundBlaster8, SoundBlaster16 and ES1x88AudioDriver each lacked all three
levels; contents follow their existing Makefiles."
```

---

### Task 3: drvBeepSound report pass

11 hand-written functions across 2060 bytes of `__text` — the smallest body of code in the effort, and the one whose reference data is already known to match ours exactly. Establishes the `IOAudio` subclass shape the other three reuse.

**Files:**
- Create: `src/drivers-i386/sound/drvBeepSound/reconstruction/source-map.json`
- Create: `src/drivers-i386/sound/drvBeepSound/reconstruction/ledger.json`
- Create: `src/drivers-i386/sound/drvBeepSound/reconstruction/divergences.md`
- Read: `src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Beep.lksproj/Beep.m`, `Beep.h`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/beep.json` from Task 1; the table and scaffolding state from Task 2.
- Produces: a complete function partition for the 13 reference functions, and a `divergences.md` that answers four questions Task 4 acts on: what `+[Beep probe:]` does, how `-[Beep beep]` computes its `thread_set_timeout` argument, whether the `__timer_cnt_port_` table is read at all, and whether `_beepDeviceName`/`_beepDeviceKind` are passed to `setName:`/`setDeviceKind:` or used some other way.

- [ ] **Step 1: Run the analyze step**

Follow Standard report pass procedure Step A with `<name>` = `beep` and the reference path `C:\Users\raynorpat\Downloads\test\Drivers\i386\Beep.config\Beep_reloc`.

Expected: `complete: True` and SHA-256 `752B5A078A747CE0ED0C36951C5DED5DD99DD2420CD4CFF979D12059A53D6C73`.

- [ ] **Step 2: Build and hand-resolve the source map**

Follow Standard report pass procedure Steps B and C with `<drv>` = `drvBeepSound`, `<drvproj>` = `Beep.drvproj`, `<lksproj>` = `Beep.lksproj`.

The 13 reference functions and their expected disposition:

| Address | Size | Name | Bucket |
| --- | --- | --- | --- |
| 0 | 68 | `+[Beep probe:]` | `unmapped` — no source counterpart |
| 68 | 100 | `_stringToStyle` | `mapped` — `Beep.m:81` |
| 168 | 100 | `-[Beep reset]` | `mapped` — `Beep.m:173` |
| 268 | 320 | `-[Beep initFromDeviceDescription:]` | `mapped` — `Beep.m:110` |
| 588 | 444 | `-[Beep beep]` | `mapped` — `Beep.m:195` |
| 1032 | 28 | `-[Beep _channelWillAddStream]` | `mapped` — `Beep.m:462` |
| 1060 | 224 | `-[Beep getIntValues:forParameter:count:]` | `mapped` — `Beep.m:269` |
| 1284 | 192 | `-[Beep setIntValues:forParameter:count:]` | `mapped` — `Beep.m:393` |
| 1476 | 356 | `-[Beep getCharValues:forParameter:count:]` | `mapped` — `Beep.m:315` |
| 1832 | 124 | `-[Beep setCharValues:forParameter:count:]` | `mapped` — `Beep.m:432` |
| 1956 | 80 | `-[Beep _getSupportedParameters:count:forObject:]` | `mapped` — `Beep.m:471` |
| 2036 | 12 | `+[BeepKernelServerInstance kernelServerInstance]` | `unmapped` — build-generated glue |
| 2048 | 12 | `+[BeepVersion driverKitVersionForBeep]` | `unmapped` — build-generated glue |

The source lines above are the current ones; re-derive them rather than trusting this table if `Beep.m` has changed. Note the reference emits `getIntValues:` before `setIntValues:` before `getCharValues:`, while our source orders them get-int, get-char, set-int, set-char — an ordering difference, not a divergence, since the linker lays out by translation-unit order.

- [ ] **Step 3: Validate the source map**

Follow Standard report pass procedure Step D with `<name>` = `beep`, `<drv>` = `drvBeepSound`.

Expected: `source map OK`.

- [ ] **Step 4: Diff every mapped function**

Follow Standard report pass procedure Step E. Four questions must be answered explicitly, because Task 4 acts on each:

1. **`+[Beep probe:]` (0, 68 bytes).** What does it test, and what does it return? 68 bytes is small — likely an allocation and an `initFromDeviceDescription:` call — but read it, do not assume.

2. **`-[Beep beep]` (588, 444 bytes).** The reference imports `_assert_wait`, `_thread_set_timeout`, `_thread_block` and `_hz` and imports no `_IOSleep`. Establish the exact call sequence and how the timeout argument is computed from `_defaultDuration` and `_hz`. Our `Beep.m:253` computes `IOSleep(timeout * 1000 / hz)`, which suggests the reference's argument is in ticks rather than milliseconds — confirm or refute from the disassembly.

3. **`__timer_cnt_port_` at `__TEXT,__const:2060`.** Twelve bytes holding `{0x40, 0x41, 0x42}`. Which function reads it, and with what index? Our source uses the `PIT_COUNTER2` constant `0x42` directly. If nothing reads it, say so.

4. **`_beepDeviceName` (`__DATA,__data:8192`, `Beep`) and `_beepDeviceKind` (`:8197`, `Audio`).** Confirm `-[Beep initFromDeviceDescription:]` passes them to `setName:` and `setDeviceKind:`. Our `Beep.m:176` and `:179` pass string literals instead.

Also settle `_defaultBeepSequences` at `__DATA,__data:8204`, 96 bytes of six 16-byte records. **Resolve each record's name pointer against `__TEXT,__cstring` — do not match value triples against our array's ordering.** The strings are laid out in `__cstring` in the reverse of source order, and comparing triples alone produces a false match. The reference is `Plain {1,1,1}`, `Blip {2,3,4}`, `Up {8,17,16}`, `Down {8,15,16}`, `Octave {2,2,1}`, null; our `Beep.m:66` labels the first two the other way round. Record the swap as a finding — it is behavioural, since `Default.table` ships `"Style" = "Plain"`.

The symbol is `external` in the reference where ours is `static`, while `_stringToStyle` is `local`, matching our `static`.

- [ ] **Step 5: Compare the table**

Follow Standard report pass procedure Step F. `Default.table` only. After Task 2 this must be clean.

- [ ] **Step 6: Write `divergences.md` and `ledger.json`**

Follow Standard report pass procedure Steps G and H. Findings to record at minimum:

- `+[Beep probe:]` absent from our source entirely.
- `_defaultBeepSequences` `static` where the reference is `external`.
- Device name and kind as literals where the reference uses `__DATA` symbols.
- `IOSleep` where the reference uses thread primitives; `_IOSleep` and `_IOLog` are imports the reference does not have.
- The extra `Beep: Initialized (default: %d Hz, %d ms)` log at `Beep.m:167`.
- `__timer_cnt_port_` has no counterpart in our source.
- All nine reference `__cstring` entries are present in our source; record that as a positive result, not a finding.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/sound/drvBeepSound/reconstruction/source-map.json
git commit -m "drvBeepSound: map every reference function to source

Complete partition of the 13 functions in Apple's Beep_reloc; probe: and
the two glue methods are unmapped."

git add src/drivers-i386/sound/drvBeepSound/reconstruction/ledger.json \
        src/drivers-i386/sound/drvBeepSound/reconstruction/divergences.md
git commit -m "drvBeepSound: record the parity ledger and divergences

Our source has no +probe:, sleeps through IOSleep rather than the thread
primitives Apple uses, and keeps the sequence table static."
```

---

### Task 4: drvBeepSound fix pass

**Files:**
- Modify: `src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Beep.lksproj/Beep.m`
- Modify: `src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Beep.lksproj/Beep.h`
- Modify: `src/drivers-i386/sound/drvBeepSound/reconstruction/ledger.json`
- Modify: `src/drivers-i386/sound/drvBeepSound/reconstruction/source-map.json`
- Modify: `src/drivers-i386/sound/drvBeepSound/reconstruction/divergences.md`

**Interfaces:**
- Consumes: `divergences.md` and `ledger.json` from Task 3.
- Produces: a `Beep.m` that defines `+ (BOOL)probe:deviceDescription`, declares `BeepSequence defaultBeepSequences[]` without `static`, and reaches `setName:`/`setDeviceKind:` through file-scope `beepDeviceName`/`beepDeviceKind` arrays. Task 11 relies on nothing from this task beyond its completion.

- [ ] **Step 1: Baseline build**

Follow Standard fix pass procedure Step A with `<drv>` = `drvBeepSound`, `<Config>` = `Beep`. This driver has never been built. Record the result, including the make exit status and the staged `_reloc` size.

If the build fails, repair it in its own commit before proceeding to Step 3.

- [ ] **Step 2: Baseline parity**

Follow Standard fix pass procedure Step B. Record all four counts. The expected extras before any fix are `Beep`, `Audio`, `PC Speaker` and `Beep: Initialized (default: %d Hz, %d ms)\n`.

- [ ] **Step 3: Add `+probe:`**

Write the method from the disassembly Task 3 read. Declare it in `Beep.h` alongside the other class-level declarations:

```objc
/* Initialization and lifecycle */
+ (BOOL)probe:deviceDescription;
- initFromDeviceDescription:deviceDescription;
- (BOOL)reset;
```

Implement it in `Beep.m` immediately before `- initFromDeviceDescription:`, since the reference places it at `__text:0` ahead of everything else. The body follows whatever Task 3 recorded; the conventional DriverKit shape, which the reference's 68 bytes is consistent with, is:

```objc
+ (BOOL)probe:deviceDescription
{
    Beep *instance = [[self alloc] initFromDeviceDescription:deviceDescription];

    if (instance == nil)
        return NO;

    return YES;
}
```

**Do not ship this body unless Task 3's disassembly supports it.** If the reference does something else in those 68 bytes, write what it does and say so in `divergences.md`.

- [ ] **Step 4: De-staticise the sequence table**

`Beep.m:66` currently reads `static BeepSequence defaultBeepSequences[] = {`. Remove `static` so the symbol is `external`, matching the reference:

```objc
BeepSequence defaultBeepSequences[] = {
```

Leave `static int stringToStyle(...)` at `Beep.m:81` alone — the reference's `_stringToStyle` is `local`, so our `static` already matches.

- [ ] **Step 4a: Swap the `Blip` and `Plain` labels**

Task 3 established that the reference's first two records are `Plain {1,1,1}` and `Blip {2,3,4}`, where ours are `Blip {1,1,1}` and `Plain {2,3,4}`. Swap the two names, leaving the value triples and the ordering alone:

```objc
BeepSequence defaultBeepSequences[] = {
    /* Plain style: single short beep */
    { "Plain", 1, 1, 1 },
    /* Blip style: two-tone, frequency ratio 3:4 (perfect fifth down) */
    { "Blip", 2, 3, 4 },
```

Update the two comments to describe the sequence each name now labels — the existing ones describe the values, so leaving them attached to the swapped names would make them wrong. Do not touch the `Up`, `Down` or `Octave` records.

Confirm against the reference rather than by reading the source back:

```bash
cd /d/RhapsodiOS
cat > "$SCRATCH/check_seq.py" <<'PY'
import struct
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.macho import read_macho

def table(p):
    p = Path(p)
    d = read_macho(p)
    raw = p.read_bytes()
    sec = {s['name']: s for s in d['sections']}
    cs = sec['__TEXT,__cstring']
    strings, addr = {}, cs['address']
    for chunk in raw[cs['offset']:cs['offset'] + cs['size']].split(b'\0'):
        if chunk:
            strings[addr] = chunk.decode()
            addr += len(chunk) + 1
    ds = sec['__DATA,__data']
    sym = next(s['address'] for s in d['symbols']
               if s['name'] == '_defaultBeepSequences')
    blob = raw[ds['offset']:ds['offset'] + ds['size']]
    seqs = blob[sym - ds['address']:]
    out = []
    for i in range(0, len(seqs) - 15, 16):
        ptr, a, b, c = struct.unpack('<4i', seqs[i:i + 16])
        out.append((strings.get(ptr), a, b, c))
    return out

ref, built = table(sys.argv[1]), table(sys.argv[2])
for i, (r, b) in enumerate(zip(ref, built)):
    print(f'{i}: ref={r}  ours={b}  {"OK" if r == b else "<-- MISMATCH"}')
PY
./.venv-binrecon/Scripts/python.exe "$SCRATCH/check_seq.py" \
  "$BINRECON_REFERENCE" out/i386/drvBeepSound/Beep.config/Beep_reloc
```

Expected after the rebuild in Step 8: `OK` on every row.

- [ ] **Step 5: Move the device name and kind into data symbols**

Add two file-scope arrays above `defaultBeepSequences`, matching the reference's `_beepDeviceName` and `_beepDeviceKind`:

```objc
/* Device name and kind, published through setName: and setDeviceKind: */
static char beepDeviceName[] = "Beep";
static char beepDeviceKind[] = "Audio";
```

Then change `Beep.m:176` and `:179` to use them:

```objc
    [self setName:beepDeviceName];
    ...
    [self setDeviceKind:beepDeviceKind];
```

The reference symbols are `local`, so `static` is correct here — unlike `_defaultBeepSequences`.

- [ ] **Step 6: Replace `IOSleep` with the thread primitives**

`Beep.m:253` currently reads:

```objc
        IOSleep(timeout * 1000 / hz);
```

Replace it with the `assert_wait` / `thread_set_timeout` / `thread_block` sequence Task 3 recorded, and add the header the primitives need if it is not already imported. `Beep.m:37` already imports `<kernserv/prototypes.h>`, which declares them.

**Write what the disassembly showed.** The reference's imports establish the mechanism and `_hz` establishes that a tick conversion happens, but the exact argument is Task 3's finding, not a guess this step may invent.

- [ ] **Step 7: Drop the extra log**

Remove the `IOLog` at `Beep.m:167` and its string. The reference imports no `_IOLog` at all, so any remaining `IOLog` call in this file is a divergence — grep for others:

```bash
cd /d/RhapsodiOS
grep -n 'IOLog\|IOSleep' src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Beep.lksproj/Beep.m
```

Expected after this step: no output.

- [ ] **Step 8: Rebuild and re-check parity**

Follow Standard fix pass procedure Steps A, B and F. `missing_symbols` must no longer contain `+[Beep probe:]`. `extra_strings` must no longer contain `Beep`, `Audio` or the `Beep: Initialized` line. `_defaultBeepSequences` must appear as `external` in the rebuilt binary:

```bash
cd /d/RhapsodiOS
cat > "$SCRATCH/check_binding.py" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.macho import read_macho
d = read_macho(Path(sys.argv[1]))
for s in d['symbols']:
    if s['name'] in ('_defaultBeepSequences', '_stringToStyle',
                     '_beepDeviceName', '_beepDeviceKind'):
        print(f"{s['name']:24} {str(s['section']):20} {s['binding']}")
PY
./.venv-binrecon/Scripts/python.exe "$SCRATCH/check_binding.py" \
  out/i386/drvBeepSound/Beep.config/Beep_reloc
```

Expected: `_defaultBeepSequences` `external`, the other three `local`.

- [ ] **Step 9: Reline the source map and advance the ledger**

Follow Standard fix pass procedure Steps E2 and D. Adding `+probe:` moves every line below it, so relining is mandatory. `+[Beep probe:]` moves from `unmapped` to `mapped` — that is a bucket-count change, and it is the one expected change for this driver, so do not stop on it; verify it is the *only* one.

- [ ] **Step 10: Commit**

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Beep.lksproj/Beep.m \
        src/drivers-i386/sound/drvBeepSound/Beep.drvproj/Beep.lksproj/Beep.h
git commit -m "drvBeepSound: add +probe: and match Apple's data and sleep path

Writes the probe method our source never had, exports the sequence table,
publishes the device name and kind from data, and sleeps through the
thread primitives instead of IOSleep."

git add src/drivers-i386/sound/drvBeepSound/reconstruction/
git commit -m "drvBeepSound: advance the ledger after the fix pass"
```

---

### Task 5: drvSB8Sound report pass

27 hand-written functions across 8896 bytes. The cleanest starting point of the four, and it establishes the shared `IOAudio` mixer, DMA and interrupt method set that drvES1x88Sound and drvSB16Sound both build on.

**Files:**
- Create: `src/drivers-i386/sound/drvSB8Sound/reconstruction/source-map.json`
- Create: `src/drivers-i386/sound/drvSB8Sound/reconstruction/ledger.json`
- Create: `src/drivers-i386/sound/drvSB8Sound/reconstruction/divergences.md`
- Read: `src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/SoundBlaster8.lksproj/SoundBlaster8.m`, `SoundBlaster8.h`, `SoundBlaster8Inline.h`, `SoundBlaster8Registers.h`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/soundblaster8.json` from Task 1; Task 2's tree state.
- Produces: a complete partition of the 29 reference functions, and a worked reference decompilation of the shared `IOAudio` method set — `updateInputGainLeft`, `updateInputGainRight`, `updateOutputMute`, `updateOutputAttenuationLeft`, `updateOutputAttenuationRight`, `updateSampleRate`, `enableAllInterrupts`, `disableAllInterrupts`, `startDMAForChannel:read:buffer:bufferSizeForInterrupts:`, `stopDMAForChannel:read:`, `interruptClearFunc`, `interruptOccurredForInput:forOutput:`, `timeoutOccurred`, `setAnalogInputSource:`, `acceptsContinuousSamplingRates`, `getSamplingRatesLow:high:`, `getSamplingRates:count:`, `getDataEncodings:count:`, `channelCountLimit` — that Tasks 7 and 9 read rather than re-deriving.

- [ ] **Step 1: Run the analyze step**

Follow Standard report pass procedure Step A with `<name>` = `soundblaster8` and the reference path `C:\Users\raynorpat\Downloads\test\Drivers\i386\SoundBlaster8.config\SoundBlaster8_reloc`.

Expected: `complete: True` and SHA-256 `3CE9787321C1E52D62BF1B19CFC58BD6F7340A98D5C6FEAEC8B92B5E6A8EC9D4`.

- [ ] **Step 2: Build and hand-resolve the source map**

Follow Standard report pass procedure Steps B and C with `<drv>` = `drvSB8Sound`, `<drvproj>` = `SoundBlaster8.drvproj`, `<lksproj>` = `SoundBlaster8.lksproj`.

Two functions need care. `_writeToDSP` (0, 40 bytes) and `_readFromDSP` (40, 32 bytes) are `local` out-of-line functions in the reference; ours are `static inline` in `SoundBlaster8Inline.h:153` and `:170`, which the `*.m`/`*.c` glob does not see. Map both to `SoundBlaster8.m` at its `#import "SoundBlaster8Inline.h"` line and record in `divergences.md` that their `source_line` is an include site rather than a definition. `_clearInterrupts` (7756, 16 bytes) is defined at `SoundBlaster8.m:511` and maps directly.

The remaining 24 hand-written functions are `SoundBlaster8` methods with name-level counterparts in `SoundBlaster8.m`; the two glue methods at 8872 and 8884 go to `unmapped`.

- [ ] **Step 3: Validate the source map**

Follow Standard report pass procedure Step D with `<name>` = `soundblaster8`, `<drv>` = `drvSB8Sound`.

Expected: `source map OK`.

- [ ] **Step 4: Diff every mapped function**

Follow Standard report pass procedure Step E. Give the largest three the most attention, since they carry most of the logic: `-[SoundBlaster8 initializeHardware]` (924, 2176 bytes), `-[SoundBlaster8 startDMAForChannel:read:buffer:bufferSizeForInterrupts:]` (6056, 1440) and `-[SoundBlaster8 updateSampleRate]` (4652, 776).

Our source distributes work differently from the reference: our `initializeHardware` at `SoundBlaster8.m:185` is ten lines while the reference's is 2176 bytes, and our `reset` at `:91` is 94 lines against the reference's 576. Establish where each piece of work lives on each side before concluding anything is missing — much of ours is in `SoundBlaster8Inline.h`, which the compiler inlines into whichever method calls it.

Also settle:

- The `_sbCardType` layout. The reference has it in `__DATA,__bss` at 16436, 20 bytes. Our `SoundBlaster8Inline.h` uses `sbCardType.majorVersion` and `.minorVersion`. Confirm the field offsets from the disassembly.
- `_lowSpeedDMA` (`__DATA,__bss:16456`). Find its counterpart in our source, or record that it has none.
- The eight `_sb*Reg` pointers at `__DATA,__data:16384` through `:16412` and the eight volume bytes at `:16416` through `:16423`. `__DATA,__data` is all zeros in the reference, so these are computed at runtime, not initialised — note that, because the SoundBlaster16 equivalents *are* initialised and Task 9 must not assume the same.

- [ ] **Step 5: Compare the table**

Follow Standard report pass procedure Step F. `Default.table` only. Record the `SB8.rtfd` versus `SB8_3_31.rtfd` help-file mismatch that Task 2 Step 3 deferred here.

- [ ] **Step 6: Write `divergences.md` and `ledger.json`**

Follow Standard report pass procedure Steps G and H. Record as positive results, not findings: all 19 reference `__cstring` entries are present in our source, and every extra string of ours sits under `#ifdef DEBUG`. Record as a finding the `_writeToDSP`/`_readFromDSP` `static inline` versus out-of-line `local` question, with Task 6's fallback stated.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/sound/drvSB8Sound/reconstruction/source-map.json
git commit -m "drvSB8Sound: map every reference function to source

Complete partition of the 29 functions in Apple's SoundBlaster8_reloc."

git add src/drivers-i386/sound/drvSB8Sound/reconstruction/ledger.json \
        src/drivers-i386/sound/drvSB8Sound/reconstruction/divergences.md
git commit -m "drvSB8Sound: record the parity ledger and divergences

Every reference string is present; the open questions are the inlined DSP
helpers and where each side puts the initialisation work."
```

---

### Task 6: drvSB8Sound fix pass

**Files:**
- Modify: `src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/SoundBlaster8.lksproj/SoundBlaster8.m` (per findings)
- Modify: `src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/SoundBlaster8.lksproj/SoundBlaster8Inline.h` (per findings)
- Modify: `src/drivers-i386/sound/drvSB8Sound/reconstruction/ledger.json`
- Modify: `src/drivers-i386/sound/drvSB8Sound/reconstruction/source-map.json`
- Modify: `src/drivers-i386/sound/drvSB8Sound/reconstruction/divergences.md`

**Interfaces:**
- Consumes: `divergences.md` and `ledger.json` from Task 5.
- Produces: a drvSB8Sound whose every finding is either repaired or recorded as `intentional-mismatch`.

- [ ] **Step 1: Baseline build**

Follow Standard fix pass procedure Step A with `<drv>` = `drvSB8Sound`, `<Config>` = `SoundBlaster8`. Never built before; record the result. Repair a failure in its own commit before Step 3.

- [ ] **Step 2: Baseline parity**

Follow Standard fix pass procedure Step B. Record all four counts.

- [ ] **Step 3: Try to reproduce the out-of-line DSP helpers**

`SoundBlaster8Inline.h:153` and `:170` currently declare:

```c
static __inline__ void
writeToDSP(unsigned int dataOrCommand)
```

Remove the inline qualifier from both so the compiler must emit an out-of-line copy, matching the reference's `local` `_writeToDSP` at `__text:0` and `_readFromDSP` at `:40`:

```c
static void
writeToDSP(unsigned int dataOrCommand)
```

Read the file to confirm the exact current qualifier before editing — it may be `static inline`, `static __inline__`, or `__inline__ static`, and the edit must preserve everything else on the line.

Rebuild, then check whether the symbols appear and at what size:

```bash
cd /d/RhapsodiOS
cat > "$SCRATCH/check_dsp.py" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.macho import read_macho

TEXT = '__TEXT,__text'
d = read_macho(Path(sys.argv[1]))
sec = next(s for s in d['sections'] if s['name'] == TEXT)
syms = sorted([s for s in d['symbols'] if s['section'] == TEXT],
              key=lambda s: s['address'])
end = sec['address'] + sec['size']
found = False
for i, s in enumerate(syms):
    if s['name'] in ('_writeToDSP', '_readFromDSP'):
        nxt = syms[i + 1]['address'] if i + 1 < len(syms) else end
        print(f"{s['name']:16} addr={s['address']:6} size={nxt - s['address']:4} {s['binding']}")
        found = True
if not found:
    print('neither _writeToDSP nor _readFromDSP is in __TEXT,__text')
PY
./.venv-binrecon/Scripts/python.exe "$SCRATCH/check_dsp.py" \
  out/i386/drvSB8Sound/SoundBlaster8.config/SoundBlaster8_reloc
```

If `_writeToDSP` and `_readFromDSP` appear as `local` in `__TEXT,__text`, the change worked; keep it. If they do not — the compiler may still inline a `static` function used once, or may emit them at sizes far from 40 and 32 bytes — **revert the edit** and record the entry as `intentional-mismatch` with the reason that out-of-line emission of a `static` function is a toolchain property our source cannot control. Do not force it with `__attribute__((noinline))`; the reference has no such annotation and adding one would be inventing source Apple did not write.

- [ ] **Step 4: Fix the remaining findings**

Follow Standard fix pass procedure Step C, working through `divergences.md` in order. Every finding resolves to a source change or to `intentional-mismatch` with a reason and a reviewer.

The `SB8.rtfd` help-file key recorded in Task 5 is resolved here as `intentional-mismatch`: the table matches Apple byte for byte, and renaming our help bundle to suit would change a file the reference comparison does not cover.

- [ ] **Step 5: Rebuild, re-check parity, and size-check**

Follow Standard fix pass procedure Steps A, B and F. `missing_strings` and `missing_symbols` must be at or below the baseline.

- [ ] **Step 6: Reline the source map and advance the ledger**

Follow Standard fix pass procedure Steps E2 and D. Bucket counts must be unchanged for this driver — no method is added or removed. A count change means something went wrong; stop and look.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/sound/drvSB8Sound/SoundBlaster8.drvproj/SoundBlaster8.lksproj/
git commit -m "drvSB8Sound: resolve the divergences against Apple's binary"

git add src/drivers-i386/sound/drvSB8Sound/reconstruction/
git commit -m "drvSB8Sound: advance the ledger after the fix pass"
```

---

### Task 7: drvES1x88Sound report pass

23 hand-written functions across 8660 bytes. Confirms, before anything is removed, that Apple's binary has no counterpart for the four methods our source carries from SoundBlaster16.

**Files:**
- Create: `src/drivers-i386/sound/drvES1x88Sound/reconstruction/source-map.json`
- Create: `src/drivers-i386/sound/drvES1x88Sound/reconstruction/ledger.json`
- Create: `src/drivers-i386/sound/drvES1x88Sound/reconstruction/divergences.md`
- Read: `src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/ES1x88AudioDriver.m`, `ES1x88AudioDriver.h`, `ES1x88AudioDriverInline.h`, `ES1x88AudioDriverRegisters.h`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/es1x88audiodriver.json` from Task 1; Task 5's worked decompilation of the shared `IOAudio` method set.
- Produces: a complete partition of the 25 reference functions, and an explicit statement in `divergences.md` — required before Task 8 may remove anything — that `initializeDMAChannels`, `initializeLastStageGainRegisters`, `updateSampleRate` and `setBufferCount:` have no symbol in the reference and that no reference function calls into their logic.

- [ ] **Step 1: Run the analyze step**

Follow Standard report pass procedure Step A with `<name>` = `es1x88audiodriver` and the reference path `C:\Users\raynorpat\Downloads\test\Drivers\i386\ES1x88AudioDriver.config\ES1x88AudioDriver_reloc`.

Expected: `complete: True` and SHA-256 `196F94DC778DB5A2AFE7763A2F4559ED96F27B46AB813674A5C098B75667DAD3`.

- [ ] **Step 2: Build and hand-resolve the source map**

Follow Standard report pass procedure Steps B and C with `<drv>` = `drvES1x88Sound`, `<drvproj>` = `ES1x88AudioDriver.drvproj`, `<lksproj>` = `ES1x88AudioDriver.lksproj`.

23 hand-written functions plus the two glue methods at 8636 and 8648. `_clearInterrupts` (7972, 16 bytes) is defined in `ES1x88AudioDriverInline.h:179`, not in the `.m` — map it to the `#import` site and record that, as in Task 5's Step 2.

Note the direction of the asymmetry: the reference has **no** function our source lacks. Every unmapped entry is build-generated glue. The four extra source methods do not appear in the source map at all, because the map partitions *reference* functions; they are recorded in `divergences.md` instead.

- [ ] **Step 3: Validate the source map**

Follow Standard report pass procedure Step D with `<name>` = `es1x88audiodriver`, `<drv>` = `drvES1x88Sound`.

Expected: `source map OK`.

- [ ] **Step 4: Confirm the four extra methods have no reference counterpart**

This is the gate Task 8's excision depends on. Two independent checks:

```bash
cd /d/RhapsodiOS
cat > "$SCRATCH/find_syms.py" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.macho import read_macho
d = read_macho(Path(sys.argv[1]))
needles = sys.argv[2:]
names = [s['name'] for s in d['symbols']]
for n in needles:
    hits = [x for x in names if n in x]
    print(f'{n}: {hits if hits else "ABSENT"}')
PY
./.venv-binrecon/Scripts/python.exe "$SCRATCH/find_syms.py" \
  'C:\Users\raynorpat\Downloads\test\Drivers\i386\ES1x88AudioDriver.config\ES1x88AudioDriver_reloc' \
  initializeDMAChannels initializeLastStageGainRegisters updateSampleRate setBufferCount
```

Expected: `ABSENT` for all four.

Then read the `__OBJC,__inst_meth` selector list, which is what the runtime dispatches through, and confirm none of the four selectors appears there either. A method absent from `__text` but present in `__inst_meth` would mean something stranger than "not defined", and would block the excision.

- [ ] **Step 5: Diff every mapped function**

Follow Standard report pass procedure Step E. Give the largest four the most attention: `-[ES1x88AudioDriver startDMAForChannel:read:buffer:bufferSizeForInterrupts:]` (5804, 1580 bytes), `-[ES1x88AudioDriver configureHardwareForDataTransfer:]` (4388, 1328), `-[ES1x88AudioDriver initializeHardware]` (1396, 1240) and `-[ES1x88AudioDriver reset]` (300, 1096).

Two questions Task 8 acts on:

1. **Where does the sample-rate work live?** The reference has no `updateSampleRate`, but it does set a rate somewhere — `configureHardwareForDataTransfer:` is the likeliest home given its size. Establish which reference function does it, because Task 8 removes our `updateSampleRate` and its logic has to end up wherever the reference puts it, not simply vanish.

2. **Where does the DMA channel setup live?** Same question for our `initializeDMAChannels`. The reference logs `Audio DMA channel is %d` and `2nd Audio DMA channel is %d`, so it validates two channels somewhere — find where.

Also confirm `_essHardware` (`__DATA,__bss:16436`, 8 bytes) against our `ES1x88AudioDriverInline.h:82` `static unsigned int essHardware`, and `_sbRecordSource` (`__DATA,__data:16422`) against `:88`.

- [ ] **Step 6: Compare the tables**

Follow Standard report pass procedure Step F. `Default.table` and `ESPnP.table`. Both already matched the reference before Task 2 and must still match; a difference here means Task 2 damaged something.

- [ ] **Step 7: Write `divergences.md` and `ledger.json`**

Follow Standard report pass procedure Steps G and H. The excision finding must name all four methods, their current line numbers, the Step 4 evidence, and — from Step 5 — where the reference puts the work that our `updateSampleRate` and `initializeDMAChannels` do. Also record the seven SoundBlaster16-derived strings our source emits and the reference does not: `%s: Must specify either one or two channels.`, `%s: could not set transfer width to 16 bits, error %d.`, `%s: could not set transfer width to 8 bits, error %d.`, `LS Input Gain`, `LS Output Gain`, `ES1x88AudioDriver: 16-Bit DMA channel must be one of 5, 6 and 7.`, `ES1x88AudioDriver: 16-bit DMA channel is %d.`, plus the two 8-bit DMA variants and `ES1x88AudioDriver: DSP write error.`

Record as a positive result: all 23 reference `__cstring` entries are present in our source.

- [ ] **Step 8: Commit**

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/sound/drvES1x88Sound/reconstruction/source-map.json
git commit -m "drvES1x88Sound: map every reference function to source

Complete partition of the 25 functions in Apple's ES1x88AudioDriver_reloc."

git add src/drivers-i386/sound/drvES1x88Sound/reconstruction/ledger.json \
        src/drivers-i386/sound/drvES1x88Sound/reconstruction/divergences.md
git commit -m "drvES1x88Sound: record the parity ledger and divergences

Confirms four of our methods and their strings come from SoundBlaster16 and
have no counterpart in Apple's binary."
```

---

### Task 8: drvES1x88Sound fix pass

**Files:**
- Modify: `src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/ES1x88AudioDriver.m`
- Modify: `src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/ES1x88AudioDriver.h`
- Modify: `src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/ES1x88AudioDriverInline.h` (per findings)
- Modify: `src/drivers-i386/sound/drvES1x88Sound/reconstruction/ledger.json`
- Modify: `src/drivers-i386/sound/drvES1x88Sound/reconstruction/source-map.json`
- Modify: `src/drivers-i386/sound/drvES1x88Sound/reconstruction/divergences.md`

**Interfaces:**
- Consumes: `divergences.md` from Task 7, specifically its statement that the four methods have no reference counterpart and its finding of where the reference puts their work.
- Produces: an `ES1x88AudioDriver.m` with no `initializeDMAChannels`, `initializeLastStageGainRegisters`, `updateSampleRate` or `setBufferCount:` method, and none of the SoundBlaster16-derived strings.

- [ ] **Step 1: Baseline build**

Follow Standard fix pass procedure Step A with `<drv>` = `drvES1x88Sound`, `<Config>` = `ES1x88AudioDriver`. Never built before; record the result. Repair a failure in its own commit before Step 3.

- [ ] **Step 2: Baseline parity**

Follow Standard fix pass procedure Step B. Record all four counts.

- [ ] **Step 3: Confirm the excision is authorised**

The spec's §4.3 makes the wholesale removal conditional on Task 7 having recorded it. Before touching a line:

```bash
cd /d/RhapsodiOS
grep -n 'initializeDMAChannels\|initializeLastStageGainRegisters\|updateSampleRate\|setBufferCount' \
  src/drivers-i386/sound/drvES1x88Sound/reconstruction/divergences.md
```

Expected: hits naming all four with the Step-4 evidence from Task 7. **If `divergences.md` does not record them, stop and finish Task 7 first.** Removing them on the strength of this plan alone is exactly the pre-authorisation-by-heuristic the spec rules out.

- [ ] **Step 4: Relocate the work before removing the methods**

Task 7 established where the reference does the sample-rate and DMA-channel work. Move our equivalent logic there first, so that removing the four methods deletes only dead wrappers rather than behaviour. Do this as its own edit and confirm the driver still compiles before Step 5.

If Task 7 could not establish where the reference does that work, **do not remove `updateSampleRate` or `initializeDMAChannels`.** Record both as unresolved in `divergences.md` and remove only `initializeLastStageGainRegisters` and `setBufferCount:`, whose SoundBlaster16 origin is unambiguous from the `LS Input Gain` / `LS Output Gain` strings and the `_sbBufferCounter` symbol that exists in SoundBlaster16's `__DATA,__bss` and not in ES1x88's.

- [ ] **Step 5: Remove the methods and their declarations**

Delete each method body from `ES1x88AudioDriver.m` and its declaration from `ES1x88AudioDriver.h`. Then remove any now-unreferenced file-scope statics in `ES1x88AudioDriverInline.h` that only those methods used — `sbBufferCounter` at `ES1x88AudioDriver.m:983` is the clear case, since the reference has no `_sbBufferCounter` symbol.

Removing orphans your own change creates is required; removing pre-existing dead code is not. If a static was already unused before this task, leave it and note it.

- [ ] **Step 6: Verify the SoundBlaster16-derived strings are gone**

```bash
cd /d/RhapsodiOS
F=src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj
grep -n 'LS Input Gain\|LS Output Gain\|16-bit DMA\|16-Bit DMA\|one or two channels\|transfer width to 16 bits' \
  "$F"/*.m "$F"/*.h
```

Expected: no output. If a string survives because a reference function genuinely emits it, that contradicts Task 7's finding — go back rather than deleting the call site blind.

- [ ] **Step 7: Fix the remaining findings**

Follow Standard fix pass procedure Step C for everything in `divergences.md` that is not the excision.

- [ ] **Step 8: Rebuild, re-check parity, and size-check**

Follow Standard fix pass procedure Steps A, B and F. `missing_strings` must stay empty — all 23 reference strings were present before this task and removal must not have taken one with it. `extra_strings` must have shrunk by the SoundBlaster16-derived set.

- [ ] **Step 9: Reline the source map and advance the ledger**

Follow Standard fix pass procedure Steps E2 and D. **This is the driver where bucket counts legitimately change**, because our method set shrank. The reference function set does not change, so `mapped` + `unmapped` + `boundary_disputed` + `duplicate_candidates` still totals 25; what changes is the `source_line` of nearly every entry. Confirm the total is still 25 and that no entry moved from `mapped` to `unmapped` — a reference function losing its source counterpart would mean the excision took something the reference needs.

- [ ] **Step 10: Commit**

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/sound/drvES1x88Sound/ES1x88AudioDriver.drvproj/ES1x88AudioDriver.lksproj/
git commit -m "drvES1x88Sound: drop the SoundBlaster16 code Apple's driver lacks

Removes four methods with no symbol in the reference binary along with the
16-bit DMA and last-stage-gain strings that came with them."

git add src/drivers-i386/sound/drvES1x88Sound/reconstruction/
git commit -m "drvES1x88Sound: advance the ledger after the fix pass"
```

---

### Task 9: drvSB16Sound report pass

26 hand-written functions across 13572 bytes — the largest and most divergent driver in the effort. `initializeHardware` and `timeoutOccurred` alone are 6024 bytes, 44 percent of the reference `__text`.

**Files:**
- Create: `src/drivers-i386/sound/drvSB16Sound/reconstruction/source-map.json`
- Create: `src/drivers-i386/sound/drvSB16Sound/reconstruction/ledger.json`
- Create: `src/drivers-i386/sound/drvSB16Sound/reconstruction/divergences.md`
- Read: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/SoundBlaster16.m`, `SoundBlaster16.h`, `SoundBlaster16Inline.h`, `SoundBlaster16Registers.h`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/soundblaster16.json` from Task 1; the worked decompilations from Tasks 5 and 7.
- Produces: a complete partition of the 28 reference functions, and — for each method the report finds invented rather than divergent — an explicit statement to that effect, which is what authorises Task 10's rewrite.

- [ ] **Step 1: Run the analyze step**

Follow Standard report pass procedure Step A with `<name>` = `soundblaster16` and the reference path `C:\Users\raynorpat\Downloads\test\Drivers\i386\SoundBlaster16.config\SoundBlaster16_reloc`.

Expected: `complete: True` and SHA-256 `08EC130B85B64E289B17DC32DBE9D69D56FF48DAA9E4CD26FA935DDFC52A9001`.

This is the largest binary in the effort and the likeliest to hit the Ghidra normalization abort. If it does, disable Ghidra in `soundblaster16.json`, commit that separately, and re-run — see the Standard report pass procedure.

- [ ] **Step 2: Build and hand-resolve the source map**

Follow Standard report pass procedure Steps B and C with `<drv>` = `drvSB16Sound`, `<drvproj>` = `SoundBlaster16.drvproj`, `<lksproj>` = `SoundBlaster16.lksproj`.

`_clearInterrupts` (10116, 96 bytes) is defined in `SoundBlaster16Inline.h:470`, not the `.m` — map it to the `#import` site as in Tasks 5 and 7. Note it is 96 bytes here against 16 in both SoundBlaster8 and ES1x88, so it does materially more work on this card. The two glue methods at 13548 and 13560 go to `unmapped`.

- [ ] **Step 3: Validate the source map**

Follow Standard report pass procedure Step D with `<name>` = `soundblaster16`, `<drv>` = `drvSB16Sound`.

Expected: `source map OK`.

- [ ] **Step 4: Diff every mapped function, and classify each as divergent or invented**

Follow Standard report pass procedure Step E. For each method, `divergences.md` must state one of two things: the source implements the reference's logic with specific differences (divergent), or the source does not implement the reference's logic at all (invented). Only the second wording authorises Task 10 to rewrite.

The four to read first, in this order:

1. **`-[SoundBlaster16 timeoutOccurred]` (10364, 3032 bytes).** Our `SoundBlaster16.m:820` is twelve lines. The reference emits `%s: reset hardware.` and this is the only plausible home for it.
2. **`-[SoundBlaster16 initializeHardware]` (1672, 2992 bytes).** Our `:294` is six lines. The reference emits `%s: This driver does not support 8-bit Sound Blaster cards.`, `%s: None or unsupported card.` and `%s hardware version is %d.%d`.
3. **`-[SoundBlaster16 startDMAForChannel:read:buffer:bufferSizeForInterrupts:]` (7412, 1876 bytes).** Our `:596`.
4. **`-[SoundBlaster16 initializeDMAChannels]` (288, 988 bytes).** Our `:163`. This is where the IRQ and DMA validation messages live.

Three specific questions:

- **The IRQ set.** Our `SoundBlaster16.m` logs `IRQ must be 2, 5, 7, or 10`; the reference logs `Audio IRQ must be one of 5, 7, 9, 10`. Our own `Default.table` says `"Valid IRQ Levels" = "5 7 9 10"`, agreeing with Apple and contradicting our code. Read the reference's comparison chain and record the exact accepted set and the order it tests them in.
- **The two missing strings.** `SoundBlaster16: DSP read error.` and `SoundBlaster16: SoundBlaster not detected at address 0x%0x.` appear in the reference and nowhere in our source. Find which functions emit them and on what condition.
- **The initialised mixer defaults.** The reference `__DATA,__data` from offset 52 holds `_volMasterLeft`/`Right` `0x18`, `_volVoiceLeft`/`Right` `0x15`, `_volLineLeft`/`Right` `0x10`, `_volPCSpeaker` `0x02`, `_volMic` `0x15`, `_trebleLeft`/`Right` `0x08`, `_bassLeft`/`Right` `0x09`, `_volMIDILeft`/`Right` `0`, `_volCDLeft`/`Right` `0x15`, the four `_lastStageGain*` `0x02`, `_outputMixerSwitch` `0x06`, `_inputMixerSwitchLeft` `0x15`, `_inputMixerSwitchRight` `0x0b`, and `_sbStartDMACommand`/`_sbStartDMAMode` both `0`. Compare each against our source's initialiser and record every mismatch. Unlike SoundBlaster8, these are compile-time initialised, so the comparison is exact.

Also note `_sbCardType` is `__DATA,__data:16384`, 12 bytes, here — against SoundBlaster8's 20-byte `__bss` version. The struct differs between the two drivers; do not carry Task 5's field offsets over.

- [ ] **Step 5: Compare the tables**

Follow Standard report pass procedure Step F. All four tables. After Task 2 this must be clean.

- [ ] **Step 6: Write `divergences.md` and `ledger.json`**

Follow Standard report pass procedure Steps G and H. Every one of the 26 hand-written functions gets an explicit divergent-or-invented classification, because Task 10's authorisation depends on it. If Ghidra was disabled in Step 1, state the reduced analyzer set as a limitation.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/sound/drvSB16Sound/reconstruction/source-map.json
git commit -m "drvSB16Sound: map every reference function to source

Complete partition of the 28 functions in Apple's SoundBlaster16_reloc."

git add src/drivers-i386/sound/drvSB16Sound/reconstruction/ledger.json \
        src/drivers-i386/sound/drvSB16Sound/reconstruction/divergences.md
git commit -m "drvSB16Sound: record the parity ledger and divergences

Classifies each method as divergent or invented, and pins down the IRQ set,
the two missing strings and the initialised mixer defaults."
```

---

### Task 10: drvSB16Sound fix pass

**Files:**
- Modify: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/SoundBlaster16.m`
- Modify: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/SoundBlaster16Inline.h` (per findings)
- Modify: `src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/SoundBlaster16.h` (per findings)
- Modify: `src/drivers-i386/sound/drvSB16Sound/reconstruction/ledger.json`
- Modify: `src/drivers-i386/sound/drvSB16Sound/reconstruction/source-map.json`
- Modify: `src/drivers-i386/sound/drvSB16Sound/reconstruction/divergences.md`

**Interfaces:**
- Consumes: `divergences.md` from Task 9 and its per-method divergent-or-invented classification.
- Produces: a drvSB16Sound that validates IRQs 5, 7, 9 and 10, emits both previously-missing strings, and whose invented methods are rewritten from the disassembly.

- [ ] **Step 1: Baseline build**

Follow Standard fix pass procedure Step A with `<drv>` = `drvSB16Sound`, `<Config>` = `SoundBlaster16`. Never built before; record the result. Repair a failure in its own commit before Step 3.

- [ ] **Step 2: Baseline parity**

Follow Standard fix pass procedure Step B. Record all four counts. `missing_strings` should show at least the two known absences.

- [ ] **Step 3: Fix the IRQ set**

Change the validation to accept exactly the set the reference accepts, in the order Task 9 recorded, and change the message to the reference's wording:

```objc
        IOLog("SoundBlaster16: Audio IRQ must be one of 5, 7, 9, 10.\n");
```

Our `Default.table` already says `"Valid IRQ Levels" = "5 7 9 10"`, so this brings the code into agreement with our own table as well as with Apple's binary.

Change the DMA validation wording to the reference's at the same time, since Task 9 read both from the same function:

```objc
        IOLog("SoundBlaster16: 8-Bit DMA channel must be one of 0, 1 and 3.\n");
        IOLog("SoundBlaster16: 16-Bit DMA channel must be one of 5, 6 and 7.\n");
```

Whether our extra `8-bit and 16-bit DMA channels must be different` check survives depends on what Task 9 found in `initializeDMAChannels`; if the reference has no such check and no such string, remove it.

- [ ] **Step 4: Add the two missing strings at the sites Task 9 identified**

`SoundBlaster16: DSP read error.` and `SoundBlaster16: SoundBlaster not detected at address 0x%0x.`, each on the condition the reference emits it on. Do not add them at a site of your own choosing to satisfy the parity check — a string in the wrong function is worse than a missing one, because it makes the check pass while the behaviour stays wrong.

- [ ] **Step 5: Correct the initialised mixer defaults**

Set each file-scope initialiser to the value Task 9 read from the reference `__DATA,__data`. Verify against the rebuilt binary rather than by reading the source back:

```bash
cd /d/RhapsodiOS
cat > "$SCRATCH/check_mixer.py" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.macho import read_macho

def data_bytes(p):
    p = Path(p)
    d = read_macho(p)
    raw = p.read_bytes()
    sec = next(s for s in d['sections'] if s['name'] == '__DATA,__data')
    syms = {s['name']: s['address'] for s in d['symbols']
            if s['section'] == '__DATA,__data'}
    base = sec['address']
    blob = raw[sec['offset']:sec['offset'] + sec['size']]
    return {n: blob[a - base] for n, a in syms.items() if 0 <= a - base < len(blob)}

ref, built = data_bytes(sys.argv[1]), data_bytes(sys.argv[2])
for name in sorted(set(ref) & set(built)):
    r, b = ref[name], built[name]
    if r != b:
        print(f'{name:28} ref=0x{r:02x} ours=0x{b:02x}  <-- MISMATCH')
print('compared', len(set(ref) & set(built)), 'symbols')
PY
./.venv-binrecon/Scripts/python.exe "$SCRATCH/check_mixer.py" \
  "$BINRECON_REFERENCE" out/i386/drvSB16Sound/SoundBlaster16.config/SoundBlaster16_reloc
```

Expected after the fix: no `MISMATCH` lines. This reads one byte at each symbol's address, which is correct for the `unsigned char` mixer values; a symbol our build declares at a different width will show a spurious mismatch, and that is itself a finding.

- [ ] **Step 6: Rewrite the invented methods**

For each method Task 9 classified as invented — expected to include `timeoutOccurred` and `initializeHardware` — rewrite the body from the reference disassembly as a unit. This is the spec's §4.3 conditional authorisation; it applies only to methods `divergences.md` explicitly classified that way.

```bash
cd /d/RhapsodiOS
grep -n 'invented' src/drivers-i386/sound/drvSB16Sound/reconstruction/divergences.md
```

Expected: one hit per method being rewritten. **A method not named here does not get rewritten**, however wrong it looks.

Commit each rewritten method separately, so a reviewer can reject one without rejecting the others.

- [ ] **Step 7: Fix the remaining findings**

Follow Standard fix pass procedure Step C for everything left in `divergences.md`.

- [ ] **Step 8: Rebuild, re-check parity, and size-check**

Follow Standard fix pass procedure Steps A, B and F. `missing_strings` must no longer contain the two strings from Step 4. Every rewritten method must appear in the size check within 25 percent of its reference size; a `LARGER` flag on a rewritten method means we invented structure again and the disassembly needs another read.

- [ ] **Step 9: Reline the source map and advance the ledger**

Follow Standard fix pass procedure Steps E2 and D. The rewrites move many lines, so relining is mandatory. Bucket counts must be unchanged — no method is added or removed in this driver — so a count change means something went wrong.

- [ ] **Step 10: Commit**

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/sound/drvSB16Sound/SoundBlaster16.drvproj/SoundBlaster16.lksproj/
git commit -m "drvSB16Sound: match Apple's IRQ set, strings and mixer defaults

Accepts IRQ 9 and rejects IRQ 2 as the reference and our own table do, adds
the two log strings our source never emitted, and corrects the compile-time
mixer values."

git add src/drivers-i386/sound/drvSB16Sound/reconstruction/
git commit -m "drvSB16Sound: advance the ledger after the fix pass"
```

---

### Task 11: README status lines

**Files:**
- Modify: `src/drivers-i386/README:52-56`

**Interfaces:**
- Consumes: the four completed fix passes.
- Produces: nothing downstream.

- [ ] **Step 1: Read the wording the bus drivers use**

```bash
cd /d/RhapsodiOS
grep -n -B2 -A12 '^bus' src/drivers-i386/README
sed -n '50,58p' src/drivers-i386/README
```

Expected: the `bus` section shows the reconstructed wording to copy, and the `sound` section shows the five current lines, four of which read "needs compiled and then tested".

- [ ] **Step 2: Update the four lines**

Change only `drvBeepSound`, `drvES1x88Sound`, `drvSB8Sound` and `drvSB16Sound` to the reconstructed wording. **Leave `drvIntelAC97Sound` and `drvSB128Sound` alone** — neither has a reference binary and neither was touched by this effort.

If any driver's fix pass could not run its guest build, its line says so rather than claiming a status the evidence does not support.

- [ ] **Step 3: Verify**

```bash
cd /d/RhapsodiOS
sed -n '50,58p' src/drivers-i386/README
grep -c 'needs compiled and then tested' src/drivers-i386/README
```

Expected: the four updated lines, `drvIntelAC97Sound` still reading "needs compiled and then tested", and the total count reduced by exactly four from its pre-edit value.

- [ ] **Step 4: Commit**

```bash
cd /d/RhapsodiOS
git add src/drivers-i386/README
git commit -m "drivers-i386: mark the four audio drivers reconstructed"
```
