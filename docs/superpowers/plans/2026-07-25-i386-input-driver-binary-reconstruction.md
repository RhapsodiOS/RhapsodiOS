# i386 Input Driver Binary Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `drvPS2Mouse`, `drvSerialPointingDevice`, `drvPS2Keyboard`, `drvPCParallel` and `drvBusMouse` against Apple's shipped i386 driver binaries, producing a committed source map, parity ledger and divergence document per driver, and fixing every divergence found.

**Architecture:** Per driver, a report pass runs three disassemblers over the reference binary, maps every reference function to a file and line, and records divergences; a separate fix pass then repairs the source and advances the ledger. A one-off table pass runs first, ahead of all report passes, to land five fixes whose evidence is a direct diff of checked-in tables rather than a decompilation.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, `tools/binrecon` (angr 9.3.0, jsonschema 4.26.0), IDA Professional 9.2 (`idat.exe`), Ghidra 12.1 headless on Java 21, Objective-C for Rhapsody DriverKit, `gnumake` with NeXT `pb_makefiles` inside a Rhapsody DR2 guest.

**Spec:** [2026-07-25-i386-input-driver-binary-reconstruction-design.md](../specs/2026-07-25-i386-input-driver-binary-reconstruction-design.md)

## Global Constraints

Every task's requirements implicitly include this section.

- **Never commit reference binaries, rebuilt artifacts, or analyzer output.** `tools/binrecon/out/` is excluded by `.gitignore:17`. Rebuilt `_reloc` files stage to `out/i386/` and stay untracked.
- **Run all `binrecon` commands from the repository root `D:\RhapsodiOS`** with `PYTHONPATH=tools/binrecon`. Analyzer executable paths in profiles are resolved by the host process, so a different cwd breaks them.
- **Python interpreter is `.venv-binrecon/Scripts/python.exe`.** Not `python`, not `py`. It has angr 9.3.0 and jsonschema 4.26.0 pinned.
- **`${BINRECON_REFERENCE}` is the only variable expanded in profile artifact paths.** It must be set per shell session. An unset variable is an error.
- **`"Driver Version"` is out of every comparison.** It is emitted by Apple's build.
- **Commit messages start with the subsystem**, e.g. `drivers-i386: `, `binrecon: `. One to two lines, describing what the change does, not which files moved. No metadata, no `Co-Authored-By`, no `Generated with` trailer.
- **A diverging function stays `unexamined` in the ledger** and gets an entry in `divergences.md`. Advancing its status is the fix pass's job. This is the drvPCIBus convention.
- **Never advance a ledger status without evidence.** `assembly-matched` means the full disassembly was read instruction by instruction. `control-flow-confirmed` means block shape and call targets were checked but not every instruction. Claiming the stronger status without doing the work is the single worst failure mode in this plan.
- **Surgical changes only.** Every changed line traces to a ledger-flagged divergence or to an explicitly approved exception (§4.3 of the spec names two). Do not improve adjacent code, reformat, or refactor code that is not divergent.
- **`out/` and `tools/binrecon/out/` already exist.** Do not `mkdir` them.

### Reference binaries

External to the repo, under `C:\Users\raynorpat\Downloads\test\Drivers\i386`:

| Driver | Reference `_reloc` | Size | `__text` | Functions | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| drvPS2Mouse | `PS2Mouse.config/PS2Mouse_reloc` | 30204 | 1804 | 13 | `4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E` |
| drvSerialPointingDevice | `SerialPointingDevice.config/SerialPointingDevice_reloc` | 39928 | 4468 | 18 | `59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59` |
| drvPS2Keyboard | `PS2Keyboard.config/PS2Keyboard_reloc` | 43460 | 4952 | 49 | `AB413CA3919950F22A1F5D10B0BF1167387FEF320C9FB82A3EA66E586A6BE02A` |
| drvPCParallel | `ParallelPort.config/ParallelPort_reloc` | 45312 | 7416 | 75 | `D188A4D909005683B0C943C84CD99514C14A84AD1D378425B3B1DB343F1EAAA2` |
| drvBusMouse | `BusMouse.config/BusMouse_reloc` | 29796 | 1592 | 13 | `A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864` |

The SHA-256 in each committed `source-map.json` and `ledger.json` must match its row exactly. `load_source_map` enforces this.

### Standard report pass procedure

Tasks 3, 5, 7, 9 and 11 all follow this. Each of those tasks supplies its own driver-specific values for `<name>`, `<drv>`, `<lksproj>` and its expected function count; nothing else varies.

**Step A — set the reference and analyze.** From the repo root:

```bash
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\<Config>.config\<Config>_reloc'
./.venv-binrecon/Scripts/python.exe -m binrecon analyze \
  --profile tools/binrecon/profiles/<name>.json \
  --output tools/binrecon/out/<name>/run-summary.json
```

**Expected: exit 1, and that is success here.** `binrecon analyze` returns 0 only when the profile's acceptance level passes, and `normalized-functions` acceptance compares a reference against a *rebuilt* artifact. These are reference-only profiles with no `rebuilt` key, so acceptance can never pass and the last line always reads `normalized-functions=FAIL`. The three bus drivers' committed runs (`tools/binrecon/out/{pcibus,pcmciabus,eisabus}/run-summary.json`) all show the same `acceptance.passed: false`. Do not treat this as a failure, and do not add a `rebuilt` key to make it go away.

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

Expected: `complete: True`, the SHA-256 matching this task's row in the Global Constraints table, and four files — `analysis-reference-ida.json`, `-ghidra.json`, `-angr.json`, `consensus-reference.json`.

A run that times out or genuinely fails writes `complete: false` and no reference consensus. *That* is a failure, and it must not be worked around by reusing an earlier run's output — the runner refuses leftover output from an earlier run as evidence, and so must you.

Note also that piping this command through `tail` or `head` makes `$?` report the pipe's last stage, not binrecon's. Redirect to a file if you need the exit code.

If a staging directory named `binrecon-run-*` is left under `tools/binrecon/out/<name>/` with no `published/` beside it, the run did not finish. `tools/binrecon/out/intel824x0/` is in exactly that state from an earlier, unrelated effort; do not mistake such a directory for output.

Two adapter behaviours are automatic and are not errors: Ghidra first tries its Mach-O loader and falls back to deterministic raw i386 import using parsed Mach-O sections when that loader rejects a legacy input, and angr's `CFGFast` records unresolved indirect control flow as CFG errors. Neither means a function is absent.

**Step B — build the source map.** IDA is authoritative for the function partition, per the drvPCIBus convention:

```bash
./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/<name>/published/analysis-reference-ida.json \
  --binary "$BINRECON_REFERENCE" \
  --source-dir src/drivers-i386/input/<drv>/<lksproj> \
  --repo-root . \
  --output src/drivers-i386/input/<drv>/reconstruction/source-map.json
```

`source_sites` globs `*.m` and `*.c` in `--source-dir` non-recursively. All five drivers keep their kernel sources in a single `.lksproj` directory, so one `--source-dir` covers each.

**Step C — hand-resolve the residue.** Every reference function must land in exactly one of `mapped`, `unmapped`, `boundary_disputed`, `duplicate_candidates`. Entries within each bucket must be sorted by `(address, reference_names)` — `validate_source_map_semantics` rejects any other order. The two build-generated glue methods per driver (`+[<Name>KernelServerInstance kernelServerInstance]` and `+[<Name>Version driverKitVersionFor<Name>]`) belong in `unmapped`. Data symbols outside `__TEXT,__text` do not appear in the source map at all.

**Step D — validate the source map.** This is the report pass's gate:

```bash
cat > /tmp/check_map.py <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.schema import load_json, load_source_map
name, drv = sys.argv[1], sys.argv[2]
analysis = load_json(Path(f'tools/binrecon/out/{name}/published/analysis-reference-ida.json'))
load_source_map(
    Path(f'src/drivers-i386/input/{drv}/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map OK')
PY
./.venv-binrecon/Scripts/python.exe /tmp/check_map.py <name> <drv>
```

Expected: `source map OK`. Any `SemanticValidationError` names the exact failure — a missing address, a wrong size, a source line outside the function, a partition gap. Fix the map, do not weaken the check.

**Step E — diff every mapped function.** Decompile each and compare against our source, batched by source file. Compare control-flow shape, literal constants, I/O port addresses, struct field offsets, and call targets. Read the disassembly; do not infer from names.

**Step F — compare the table.** Diff `src/drivers-i386/input/<drv>/<drvproj>/Default.table` against `C:\Users\raynorpat\Downloads\test\Drivers\i386\<Config>.config\Default.table`, ignoring `"Driver Version"`. After Task 2 this must be clean. A residual difference is a Task 2 defect, not a new finding — say so explicitly in `divergences.md`.

**Step G — write `divergences.md`.** Follow the shape of `src/drivers-i386/bus/drvPCIBus/reconstruction/divergences.md`: a header naming the reference and its SHA-256 and the three analyzer versions, a baseline-build note, a bucket-count summary table, a statement of how many functions were examined at which depth, an unmapped/build-generated section, an analyzer-disagreement section, then numbered findings. Each finding carries the source path and line, the reference disassembly, and our source side by side.

Two scaffolding gaps are recorded here, with **no change made** — the spec's §2.7 fixes them for drvPCParallel only and explicitly declines the rest:

- For drvPS2Keyboard, drvPS2Mouse and drvSerialPointingDevice: the project has no `Load_Commands.sect` and its `.lksproj/Makefile` does not name one, so the built `Loaded Server,Load Commands` section will not match Apple's 164 bytes. Record the section sizes our build actually produces once the fix pass has a binary, or state that they are unmeasured if the guest was unavailable.
- For drvPS2Keyboard, drvPS2Mouse, drvSerialPointingDevice and drvBusMouse: the reference carries a `Loaded Server,Unload Commands` section of 102 bytes that nothing in this repository produces, including the three already-reconstructed bus drivers. Closing it would mean a build-system change plus a retrofit, which the spec puts out of scope.

drvPCParallel's `divergences.md` records instead that its two `PB.project` files were added in Task 2, that its `Load_Commands.sect` was already present and tracked since `3a0ab68f`, and what section sizes the build actually produces.

**Step H — write `ledger.json`.** `schema-version` `ledger-v1`, `reference_sha256` from the table above, `rebuilt_sha256` `null`. One entry per reference function with `address`, `names`, `size`, `source_path`, `source_line`, `status`, `reason`, `reviewer`, `artifacts`, and `analyzer_agreement` (`{analyzers, reasons, status}`). Build-generated glue gets `intentional-mismatch` with a reason naming the Kernel Server project type and a reviewer. Verify with:

```bash
./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/<name>.json \
  --ledger src/drivers-i386/input/<drv>/reconstruction/ledger.json
```

**Step I — commit.** Two commits: one for the source map, one for the ledger and divergence document.

### Standard fix pass procedure

Tasks 4, 6, 8, 10 and 12 all follow this.

**Step A — baseline build, before any source edit.** Inside the Rhapsody guest:

```bash
sh /build/source/vm/build-i386-input-drivers.sh <drv>
```

Expected: `=== input-drivers done fail=0 built: <drv> ===` and a `_reloc` staged under `/build/out/i386/<drv>/`. Record the size. If the baseline fails, repairing that breakage is a separate commit landed **before** any divergence fix, so a pre-existing failure is never misattributed to this work.

**Step B — baseline parity.** Copy the staged `_reloc` to the host, then:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "$BINRECON_REFERENCE" out/i386/<drv>/<Config>.config/<Config>_reloc
```

Prints `missing_strings`, `missing_symbols`, `extra_strings`, `extra_symbols` with counts, and exits 1 if either `missing_` list is non-empty. Record the baseline numbers — they are what the fix has to improve.

**Step C — fix each finding.** Work through `divergences.md` in order. Every finding resolves one of two ways: source changed to match the reference, or accepted as `intentional-mismatch`. Nothing is left undecided.

**Step D — advance the ledger.** For each fixed function, set the status the new evidence supports. For each accepted divergence:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/<name>.json \
  --ledger src/drivers-i386/input/<drv>/reconstruction/ledger.json \
  --address 0x<addr> --status intentional-mismatch \
  --reason '<why this divergence is accepted>' --reviewer 'Pat Raynor'
```

An `intentional-mismatch` requires both `--reason` and `--reviewer`; the CLI rejects it otherwise.

**Step E — rebuild and re-check parity.** Repeat Steps A and B. `missing_strings` and `missing_symbols` must be at or below the baseline, and every string or symbol named in a fixed finding must be gone from the missing lists. Extras are not automatically findings — our build is unstripped.

**Step F — commit.** One commit for the source fixes, one for the ledger and `divergences.md` update.

**Guest dependency.** Steps A, B and E need the Rhapsody DR2 guest. If it is unavailable, the source fixes and ledger work still land, and the task reports explicitly which of the three §4.3 checks went unrun. Do not claim a check passed that was not run.

---

### Task 1: Profiles and build harness

**Files:**
- Create: `tools/binrecon/profiles/ps2mouse.json`
- Create: `tools/binrecon/profiles/serialpointingdevice.json`
- Create: `tools/binrecon/profiles/ps2keyboard.json`
- Create: `tools/binrecon/profiles/parallelport.json`
- Create: `tools/binrecon/profiles/busmouse.json`
- Create: `vm/build-i386-input-drivers.sh`
- Reference: `tools/binrecon/profiles/pcmciabus.json`, `vm/build-i386-bus-drivers.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: five profile paths named `tools/binrecon/profiles/<name>.json` where `<name>` is `ps2mouse`, `serialpointingdevice`, `ps2keyboard`, `parallelport`, `busmouse` — the lower-cased reference server name, not the `drv` directory name, matching the existing `pcibus.json` / `pcmciabus.json` convention. Each sets `output_dir` to `../out/<name>`, resolved relative to the `profiles` directory, so analyzer output lands in `tools/binrecon/out/<name>`. Also produces `vm/build-i386-input-drivers.sh`, invoked as `sh vm/build-i386-input-drivers.sh [<drv> …]`, which with no arguments builds all five and with arguments builds only the named `drv*` directories.

- [ ] **Step 1: Write the five profiles**

Each is `pcmciabus.json` with two fields changed. `tools/binrecon/profiles/ps2mouse.json`:

```json
{
  "schema_version": "profile-v1",
  "name": "drvPS2Mouse reconstruction",
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
  "output_dir": "../out/ps2mouse"
}
```

The other four are byte-identical except for `name` and `output_dir`:

| File | `name` | `output_dir` |
| --- | --- | --- |
| `serialpointingdevice.json` | `drvSerialPointingDevice reconstruction` | `../out/serialpointingdevice` |
| `ps2keyboard.json` | `drvPS2Keyboard reconstruction` | `../out/ps2keyboard` |
| `parallelport.json` | `drvPCParallel reconstruction` | `../out/parallelport` |
| `busmouse.json` | `drvBusMouse reconstruction` | `../out/busmouse` |

There is no `rebuilt` key. These are reference-only profiles: the fix passes verify with `parity_check.py`, not with a binrecon comparison.

- [ ] **Step 2: Validate all five profiles**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
for pair in "ps2mouse:PS2Mouse" "serialpointingdevice:SerialPointingDevice" \
            "ps2keyboard:PS2Keyboard" "parallelport:ParallelPort" "busmouse:BusMouse"; do
  name=${pair%%:*}; cfg=${pair##*:}
  export BINRECON_REFERENCE="C:\\Users\\raynorpat\\Downloads\\test\\Drivers\\i386\\${cfg}.config\\${cfg}_reloc"
  echo "--- $name"
  ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile "tools/binrecon/profiles/${name}.json"
done
```

Expected: five blocks, each printing the resolved absolute reference path, its size, and its SHA-256, with no rebuilt artifact. Each SHA-256 must match its row in the Global Constraints table. Exit 0 for all five.

- [ ] **Step 3: Write the build script**

`vm/build-i386-input-drivers.sh`, modelled on `vm/build-i386-bus-drivers.sh`. The `build_one` body is identical to the bus script's; only `INPUT` replaces `BUS` and the driver list differs.

```sh
#!/bin/sh
# Build the i386 input drivers; stage reloc bundles.
# Userspace helpers (PreLoad/PostLoad) may fail on a PPC host — accept
# success when the loadable *_reloc exists.
set -e
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
INPUT=/build/source/src/drivers-i386/input
mkdir -p "$OUT"

FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

build_one() {
	name="$1"	# PS2Mouse / SerialPointingDevice / ...
	dir="$2"	# drvPS2Mouse / ...
	proj="$3"	# PS2Mouse.drvproj / ...
	src="$INPUT/$dir"
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

	set +e
	gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
	ec=$?
	set -e
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

	# drvPCParallel also builds two user-space tools named in Default.table
	# as "Pre-Load" and "Post-Load"; stage them beside the reloc if present.
	for tool in InstallPPDev RemovePPDev; do
		t=`find "$src" -name "$tool" -type f 2>/dev/null | head -1`
		if [ -n "$t" ]; then
			cp -p "$t" "$dst/"
			echo "staged tool $tool"
		fi
	done

	cat > "$OUT/$dir/README.txt" <<EOF
i386 $name ($dir)
-----------------
${name}_reloc is the i386 loadable kernel server (kl_ld).
Userspace helpers (PreLoad / PostLoad) may be absent: they need i386
crt/libDriver which this PPC guest does not provide.
make exit status was: $ec
EOF
	echo "staged $dst"
	ls -la "$dst"
	return 0
}

# With no arguments, build every driver. Otherwise build only those named,
# by directory name, e.g. `sh build-i386-input-drivers.sh drvPS2Mouse`.
want() {
	[ $# -eq 1 ] && return 0
	target=$1
	shift
	for arg in "$@"; do
		[ "$arg" = "$target" ] && return 0
	done
	return 1
}

fail=0
built=
if want drvPS2Mouse "$@"; then
	build_one PS2Mouse drvPS2Mouse PS2Mouse.drvproj || fail=1
	built="$built drvPS2Mouse"
fi
if want drvSerialPointingDevice "$@"; then
	build_one SerialPointingDevice drvSerialPointingDevice SerialPointingDevice.drvproj || fail=1
	built="$built drvSerialPointingDevice"
fi
if want drvPS2Keyboard "$@"; then
	build_one PS2Keyboard drvPS2Keyboard PS2Keyboard.drvproj || fail=1
	built="$built drvPS2Keyboard"
fi
if want drvPCParallel "$@"; then
	build_one ParallelPort drvPCParallel PCParallelPort.drvproj || fail=1
	built="$built drvPCParallel"
fi
if want drvBusMouse "$@"; then
	build_one BusMouse drvBusMouse BusMouse.drvproj || fail=1
	built="$built drvBusMouse"
fi

echo "======== summary ========"
for d in $built; do
	find "$OUT/$d" -type f 2>/dev/null | sort || true
done
for d in $built; do
	find "$OUT/$d" -name '*_reloc' -type f -exec file {} \; 2>&1 || true
done
echo "=== input-drivers done fail=$fail built:$built ==="
exit $fail
```

The closing `exit $fail` is required. `vm/build-i386-bus-drivers.sh:141` has it, and without it the script always exits 0 — which would make the "Expected: exit 0" gate in the Standard fix pass procedure's Steps A and E vacuous, letting a failed driver build pass every check.

Note the `drv` directory name and the reference `_reloc` name differ for two drivers: `drvPCParallel` builds `ParallelPort` from `PCParallelPort.drvproj`, and `drvSerialPointingDevice` builds `SerialPointingDevice` from `SerialPointingDevice.drvproj`. The `build_one name dir proj` argument order above is correct for all five; do not reorder it.

- [ ] **Step 4: Check the script parses**

The guest may be unavailable, but a syntax error is catchable on the host:

```bash
sh -n vm/build-i386-input-drivers.sh && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/binrecon/profiles/ps2mouse.json tools/binrecon/profiles/serialpointingdevice.json \
        tools/binrecon/profiles/ps2keyboard.json tools/binrecon/profiles/parallelport.json \
        tools/binrecon/profiles/busmouse.json vm/build-i386-input-drivers.sh
git commit -m "binrecon: add i386 input driver profiles and build harness

Reference-only profiles for the five input drivers plus a build script
modelled on the bus-driver one."
```

---

### Task 2: Table pass

Lands the five fixes whose evidence is a direct diff of our checked-in source against Apple's, or a contradiction internal to our own tree. This is the spec's §4.1 carve-out from the ledger-first discipline; it is authorised for exactly these five items and nothing else.

**Files:**
- Modify: `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m` at `:312`, `:326-334`, `:411-414`, `:509`, `:512`
- Modify: `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.h:45`
- Modify: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/IOParallelPort.m:92-102`
- Modify: `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/Default.table`
- Modify: `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/Default.table`
- Modify: `src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/Default.table`
- Modify: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/Default.table`
- Create: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PB.project`
- Create: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/PB.project`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: a tree in which `PS2Mouse.m` looks up device name `"PS2Controller"` and config key `"Force Detection"` through an ivar now named `forceDetection`, `IOParallelPort.m` reads config key `"Minor Device Number"` into `minorDevStr`, all five `Default.table` files differ from the reference only in `"Driver Version"`, and `drvPCParallel` has the three files its Makefiles and the tree's conventions require. Tasks 3 through 12 all assume this state. Task 3 additionally owes an answer on whether `forceDetection`'s test at `PS2Mouse.m:414` should invert; Task 9 owes one on the `"Location"` read at `IOParallelPort.m:158`.

- [ ] **Step 1: Confirm the two PS2Mouse defects are still present**

```bash
cd /d/RhapsodiOS
grep -n 'PS2KeyboardController\|SkipDetection' \
  src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m
grep -n '"PS2Controller"' \
  src/drivers-i386/input/drvPS2Keyboard/PS2Keyboard.drvproj/PS2Keyboard.lksproj/PS2Controller.m
```

Expected: `PS2Mouse.m:328` reading `"SkipDetection"`, `PS2Mouse.m:512` reading `"PS2KeyboardController"`, and `PS2Controller.m:182-183` registering `"PS2Controller"`. This is the contradiction: the name PS2Mouse looks up is not the name PS2Controller publishes, and the reference's only such string is `PS2Controller`.

- [ ] **Step 2: Fix the device name**

In `PS2Mouse.m:512`, change the lookup to the name `PS2Controller` publishes and the reference uses:

```objc
    result = IOGetObjectForDeviceName("PS2Controller", &controllerObject);
```

The reference's log string for this failure path is `initPointer: Can't find PS2Controller (%s)`. Do not change the log string in this task — it belongs to Task 4, which has the disassembly to justify its exact form.

- [ ] **Step 3: Rename the config key, and only the key**

`PS2Mouse.m:326-334` currently reads:

```objc
    /* Read "SkipDetection" parameter (offset 0x148)
     * If set to 'y' or 'Y', skip mouse presence detection
     */
    skipDetectionStr = [configTable valueForStringKey:"SkipDetection"];
    if ((skipDetectionStr == NULL) ||
        ((*skipDetectionStr != 'y') && (*skipDetectionStr != 'Y'))) {
        skipDetection = NO;
    } else {
        skipDetection = YES;
    }
```

Replace it with the key the shipped table actually provides, renaming the local and the ivar to match, and leaving the sense of the test exactly as it is:

```objc
    /* Read "Force Detection" parameter (offset 0x148)
     * If set to 'y' or 'Y', bypass mouse presence detection
     */
    forceDetectionStr = [configTable valueForStringKey:"Force Detection"];
    if ((forceDetectionStr == NULL) ||
        ((*forceDetectionStr != 'y') && (*forceDetectionStr != 'Y'))) {
        forceDetection = NO;
    } else {
        forceDetection = YES;
    }
```

Then rename the four other occurrences: the local declaration at `PS2Mouse.m:312`, the default at `PS2Mouse.m:509`, the consumer at `PS2Mouse.m:411-414`, and the ivar at `PS2Mouse.h:45`. The consumer keeps its sense:

```objc
    /* Check if mouse is present (only if forceDetection is not set)
     * Offset 0x148 is the forceDetection flag
     */
    if (!forceDetection) {
```

**Do not invert this test.** Whether `Force Detection = Yes` means "attach even though detection failed" — the same operation `SkipDetection = Yes` performs today, needing no inversion — or "run the check that would otherwise be skipped" cannot be settled from the strings. It needs the disassembly of `-[PS2Mouse readConfigTable:]` (684) and `-[PS2Mouse initWithController:]` (332), so Task 3 resolves it and Task 4 applies whatever it finds. Renaming the key is unambiguously correct on its own: the current code reads a key the table does not contain, so the value always parses as `NO`.

- [ ] **Step 4: Make drvPCParallel read its minor device number key**

`IOParallelPort.m:92-102` currently derives the minor device number from the device name rather than the config table:

```objc
    // Get device name (like "ParallelPort0")
    deviceName = [deviceDescription name];

    // Extract minor device number (last character)
    minorDevStr = deviceName + strlen(deviceName) - 1;

    // Check if minor device number is "0"
    if (strcmp(minorDevStr, "0") != 0) {
        IOLog("Nonzero Minor Device Number - only one dev this version\n");
        [self free];
        return nil;
    }
```

The reference reads the key — `Minor Device Number` and `0` are both in its `__cstring` — and `Default.table` supplies `"Minor Device Number" = "0"`. Read it from the table, defaulting to `"0"` when absent:

```objc
    // Get device name (like "ParallelPort0")
    deviceName = [deviceDescription name];

    // Get minor device number from the config table
    minorDevStr = [configTable valueForStringKey:"Minor Device Number"];
    if (minorDevStr == NULL) {
        minorDevStr = "0";
    }

    // Check if minor device number is "0"
    if (strcmp(minorDevStr, "0") != 0) {
        IOLog("Nonzero Minor Device Number - only one dev this version\n");
        [self free];
        return nil;
    }
```

`minorDevStr` is also consumed at `IOParallelPort.m:149` by `sprintf(nameBuffer, "%s%s", "pp", minorDevStr)`, whose `pp` and `%s%s` literals both match the reference, so the table value must reach that call too — which it does, since only the assignment changed. Both `deviceName` and `minorDevStr` are already declared `const char *` at lines 73-74, so the `valueForStringKey:` result assigns without a cast.

Do **not** free `minorDevStr` with `freeString:` unconditionally — the `NULL` fallback assigns a string literal, so a `freeString:` on that path would be wrong. Leave it unfreed and record the question in Task 9's report: the reference's own free discipline here can only be read from the disassembly.

**Leave `deviceName` and its `freeString:` at line 132 alone.** After this change `deviceName` is fetched at line 93 and freed at line 132 without being read in between, which looks like an orphan this edit created. Do not remove it: whether the reference calls `[deviceDescription name]` at all is a Task 9 question, and freeing a `[deviceDescription name]` result through `[configTable freeString:]` is pre-existing oddness that predates this work. Record both observations in Task 9's report and let the disassembly settle them. Deleting the fetch now would be a guess dressed up as cleanup.

Leave `IOParallelPort.m:158`'s `"Location"` read alone. It feeds `setLocation:` and the reference `Default.table` carries `"Location" = "System Baseboard"`. The reference's `__cstring` has no `Location` entry, which suggests it does not read that key — but that is a Task 9 report-pass question, not a table-pass one.

- [ ] **Step 5: Add the four missing `"Version"` lines**

Insert each so it sits where the reference puts it. `drvBusMouse/BusMouse.drvproj/Default.table` gains `"Version" = "5.01";` immediately after the `"Family"` line. `drvSerialPointingDevice/.../Default.table` gains `"Version" = "5.01";` immediately after `"Family"`. `drvPS2Mouse/.../Default.table` gains `"Version" = "5.00";` as the last line. `drvPCParallel/PCParallelPort.drvproj/Default.table` gains `"Version" = "5.01";` as the last line.

Verify each against the reference before inserting:

```bash
for pair in "drvBusMouse/BusMouse.drvproj:BusMouse" \
            "drvPS2Mouse/PS2Mouse.drvproj:PS2Mouse" \
            "drvSerialPointingDevice/SerialPointingDevice.drvproj:SerialPointingDevice" \
            "drvPCParallel/PCParallelPort.drvproj:ParallelPort"; do
  d=${pair%%:*}; cfg=${pair##*:}
  echo "=== $cfg"
  grep -n 'Version' "C:/Users/raynorpat/Downloads/test/Drivers/i386/${cfg}.config/Default.table"
done
```

Expected: each reference table shows its `"Version"` line and its `"Driver Version"` line, confirming the value and the position.

- [ ] **Step 6: Create `Load_Commands.sect` for drvPCParallel**

`PCParallelPort.lksproj/Makefile:20` names this file in `OTHERSRCS` and it is absent. The reference `ParallelPort_reloc` has a `Loaded Server,Load Commands` section of 164 bytes and, unlike BusMouse/PS2Mouse/PS2Keyboard/SerialPointingDevice, no `Unload Commands` section — the same shape as ISASerialPort. Copy ISASerialPort's content, which is that shape:

```
#
# This loadable kernel driver does not use a Mig-generated interface,
# so no handler or server interface is specified.
#
# This driver must be wired down.
WIRE
```

Whether the absent file makes `gnumake` fail outright or merely omits the `Loaded Server` sections is not yet known — Task 10's baseline build is what determines that. Either way the file must exist for the section to match Apple's 164 bytes.

- [ ] **Step 7: Create the two `PB.project` files**

These are Project Builder metadata, not build inputs — `gnumake` reads the Makefiles. They are added for consistency with every other driver in the tree, and their contents must agree with the Makefiles that already exist.

`PCParallelPort.drvproj/PB.project`, following the format `drvBusMouse` and `drvPS2Keyboard` use for a `.drvproj`, with values taken from `PCParallelPort.drvproj/Makefile` (`NAME = ParallelPort`, `PROJECTVERSION = 2.6`, `TOOLS = PCParallelPort.lksproj PostLoad.tproj PreLoad.tproj`, `OTHERSRCS = Makefile Makefile.preamble DriverInfo` — note no `Makefile.postamble`, which does not exist here):

```
FILESTABLE = {
    OTHER_SOURCES = (Makefile.preamble, Makefile, DriverInfo);
    OTHER_RESOURCES = (Default.table);
    STRINGS_FILES = (Localizable.strings);
    TOOLS = (PCParallelPort.lksproj, PostLoad.tproj, PreLoad.tproj);
    SUBPROJECTS = ();
};
LANGUAGE = English;
LOCALIZABLE_FILES = {
    Localizable.strings;
};
PROJECTVERSION = 2.6;
INSTALLDIR = "$(NEXT_ROOT)/private/Drivers";
PROJECTTYPE = Bundle;
PROJECTNAME = ParallelPort;
GENERATEMAIN = YES;
BUNDLE_EXTENSION = config;
```

`PCParallelPort.lksproj/PB.project`, following the format `BusMouse.lksproj/PB.project` uses, with values from `PCParallelPort.lksproj/Makefile` (`CLASSES = IOParallelPort.m IOParallelPortKern.m`, `HFILES = IOParallelPort.h IOParallelPortKern.h`, `OTHERSRCS = Load_Commands.sect Makefile Makefile.preamble`, `PROJECTVERSION = 2.6`, and `NEXTSTEP_PB_CFLAGS = -Wno-format -DDRIVER_PRIVATE`):

```
{
    DYNAMIC_CODE_GEN = NO;
    FILESTABLE = {
        CLASSES = (IOParallelPort.m, IOParallelPortKern.m);
        H_FILES = (IOParallelPort.h, IOParallelPortKern.h);
        OTHER_LINKED = ();
        OTHER_SOURCES = (
            Load_Commands.sect,
            Makefile,
            Makefile.preamble
        );
        SUBPROJECTS = ();
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_COMPILEROPTIONS = "-Wno-format -DDRIVER_PRIVATE";
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac;
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc;
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac";
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc";
    PROJECTNAME = ParallelPort;
    PROJECTTYPE = "Kernel Server";
    PROJECTVERSION = 2.6;
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe";
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc";
}
```

- [ ] **Step 8: Verify the tables now differ only in `"Driver Version"`**

```bash
cd /d/RhapsodiOS
REF='C:/Users/raynorpat/Downloads/test/Drivers/i386'
for pair in "drvBusMouse/BusMouse.drvproj:BusMouse" \
            "drvPS2Mouse/PS2Mouse.drvproj:PS2Mouse" \
            "drvSerialPointingDevice/SerialPointingDevice.drvproj:SerialPointingDevice" \
            "drvPCParallel/PCParallelPort.drvproj:ParallelPort" \
            "drvPS2Keyboard/PS2Keyboard.drvproj:PS2Keyboard"; do
  d=${pair%%:*}; cfg=${pair##*:}
  echo "=== $cfg"
  diff <(grep -v 'Driver Version' "$REF/${cfg}.config/Default.table" | sed 's/[[:space:]]*$//' | grep -v '^$' | sort) \
       <(grep -v 'Driver Version' "src/drivers-i386/input/${d}/Default.table" | sed 's/[[:space:]]*$//' | grep -v '^$' | sort) \
    && echo "  identical"
done
```

Expected: `identical` for all five. Any remaining difference must be resolved here, not deferred.

- [ ] **Step 9: Verify the source fixes landed**

```bash
cd /d/RhapsodiOS
grep -rn 'PS2KeyboardController\|SkipDetection\|skipDetection' src/drivers-i386/input/ \
  && echo "STILL PRESENT — FAIL" || echo "clean: no SkipDetection"
grep -n 'valueForStringKey:"Minor Device Number"' \
  src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/IOParallelPort.m \
  || echo "MISSING — FAIL"
grep -n 'IOGetObjectForDeviceName("PS2Controller"' \
  src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m \
  || echo "MISSING — FAIL"
grep -n 'strlen(deviceName) - 1' \
  src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/IOParallelPort.m \
  && echo "name-derived minor still present — FAIL" || echo "clean: minor comes from the table"
```

Expected: `clean: no SkipDetection`, a hit for `valueForStringKey:"Minor Device Number"`, a hit for `IOGetObjectForDeviceName("PS2Controller"`, and `clean: minor comes from the table`. No `FAIL` line.

Note `"Location"` is *expected* to remain at `IOParallelPort.m:158` — it is not part of this task.

- [ ] **Step 10: Commit**

Two commits, because the source fixes and the build scaffolding are independently reviewable:

```bash
git add src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m \
        src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.h \
        src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/IOParallelPort.m \
        src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/Default.table \
        src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/Default.table \
        src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/Default.table \
        src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/Default.table
git commit -m "drivers-i386: fix the input driver config keys and table versions

PS2Mouse looked up PS2KeyboardController, which nothing registers, and read a
SkipDetection key the table never supplies; ParallelPort derived its minor
device number from the device name instead of reading the table key. Adds the
four missing table Version lines."

git add src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/Load_Commands.sect \
        src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PB.project \
        src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/PB.project
git commit -m "drivers-i386: add the drvPCParallel project files its Makefiles expect

Load_Commands.sect is named in OTHERSRCS but was absent, and both PB.project
files were missing."
```

---

### Task 3: drvPS2Mouse report pass

11 hand-written functions plus 2 glue. Establishes the `PCPointer` subclass shape — `mouseInit:`, `getResolution`, `getIntValues:forParameter:count:`, `setIntValues:forParameter:count:`, `getHandler:level:argument:forInterrupt:` — that Task 11 reuses for drvBusMouse.

**Files:**
- Create: `src/drivers-i386/input/drvPS2Mouse/reconstruction/source-map.json`
- Create: `src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json`
- Create: `src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md`
- Read: `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m` (689 lines), `PS2Mouse.h` (76 lines)

**Interfaces:**
- Consumes: `tools/binrecon/profiles/ps2mouse.json` from Task 1; the Task 2 tree state.
- Produces: a validated `source-map-v1` with a complete 13-function partition, a `ledger-v1` with 13 entries, and a `divergences.md` whose findings Task 4 consumes. Also produces the worked `PCPointer` method mapping that Task 11 reuses.

**Standard report pass procedure values:** `<name>` = `ps2mouse`, `<drv>` = `drvPS2Mouse`, `<Config>` = `PS2Mouse`, `<drvproj>` = `PS2Mouse.drvproj`, `<lksproj>` = `PS2Mouse.drvproj/PS2Mouse.lksproj`.

**Reference function partition** (from the Mach-O symbol table, all 13 `local`):

| Address | Size | Name |
| --- | --- | --- |
| 0 | 180 | `-[PS2Mouse mouseInit:]` |
| 180 | 112 | `-[PS2Mouse isMousePresent]` |
| 292 | 40 | `-[PS2Mouse resetMouse]` |
| 332 | 352 | `-[PS2Mouse initWithController:]` |
| 684 | 216 | `-[PS2Mouse readConfigTable:]` |
| 900 | 528 | `_PS2MouseIntHandler` |
| 1428 | 52 | `-[PS2Mouse interruptOccurred]` |
| 1480 | 40 | `-[PS2Mouse getHandler:level:argument:forInterrupt:]` |
| 1520 | 16 | `-[PS2Mouse getResolution]` |
| 1536 | 96 | `-[PS2Mouse getIntValues:forParameter:count:]` |
| 1632 | 148 | `-[PS2Mouse setIntValues:forParameter:count:]` |
| 1780 | 12 | `+[PS2MouseKernelServerInstance kernelServerInstance]` |
| 1792 | 12 | `+[PS2MouseVersion driverKitVersionForPS2Mouse]` |

Sizes are the gaps between consecutive addresses, with the last bounded by `__text` size 1804. Confirm each against the IDA partition; where IDA disagrees, IDA wins for the partition and the disagreement is recorded.

**Reference `__cstring` set**, for the string comparison:

```
'PS2Controller'
"initPointer: Can't find PS2Controller (%s)\n"
'PS2Mouse: no PS2Controller present\n'
'PS2Mouse'
"PS2Mouse: couldn't find a mouse!\n"
'PS2Mouse readConfigTable: no configuration table\n'
'Force Detection'
'Inverted'
'Resolution'
'PS2Mouse readConfigTable: no resolution in config table.  Default is %d\n'
'PS2Mouse: mouse reset\n'
'PS2Mouse: mouse reset after resync\n'
```

Our source has `PS2Mouse: no PS2Controller present`, `PS2Mouse: couldn't find a mouse!`, `Inverted`, `Resolution`, `PS2Mouse`, and after Task 2 also `PS2Controller` and `Force Detection`. It does **not** have `initPointer: Can't find PS2Controller (%s)`, `PS2Mouse readConfigTable: no configuration table`, `PS2Mouse readConfigTable: no resolution in config table.  Default is %d`, `PS2Mouse: mouse reset`, or `PS2Mouse: mouse reset after resync`; and it has five the reference lacks, including `PS2Mouse: Using default resolution %d`, `PS2Mouse: No device description provided`, `PS2Mouse: Failed to get controller: %s`, and two self-test messages. Each of those is a finding.

- [ ] **Step 1: Run the analyzers**

Standard report pass Step A with `<name>` = `ps2mouse` and

```bash
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Mouse.config\PS2Mouse_reloc'
```

Expected: exit 1 (see Step A — reference-only profiles always fail acceptance), and `tools/binrecon/out/ps2mouse/run-summary.json` reporting `"complete": true` with three analyzer records and a reference consensus.

**This run has already been performed and verified by the controller.** `tools/binrecon/out/ps2mouse/published/` holds all four documents and the summary reports `complete: true` with `reference_sha256` `4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E`. Confirm that state rather than re-running; re-run only if the files are missing or the SHA-256 disagrees.

Verify:

```bash
cd /d/RhapsodiOS
./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('tools/binrecon/out/ps2mouse/run-summary.json'))
print(d['complete'], d['reference_sha256'],
      [(a['name'], a['version']) for a in d['analyzers']],
      d['consensus']['reference'] is not None)
"
```

Expected exactly:

```
True 4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E [('IDA', '9.2'), ('Ghidra', '12.1'), ('angr', '9.3.0')] True
```

Each entry in `run-summary.json`'s `analyzers` list has keys `name`, `version`, `reference` (with `path` and `sha256`) and `rebuilt` (`null` here). The analyzer's name is under `name` — there is no `analyzer` key.

- [ ] **Step 2: Generate the source map**

Standard report pass Step B with `--source-dir src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj`.

- [ ] **Step 3: Run the validator to see it fail**

Standard report pass Step D with `<name>` = `ps2mouse`, `<drv>` = `drvPS2Mouse`. Expected on the raw generated map: a `SemanticValidationError`, or a map with entries the generator could not place. The generated map is a starting point, not an answer — the two glue methods have no source site and must be moved to `unmapped` by hand, and any `_PS2MouseIntHandler` mapping needs checking because `source_sites` matches C definitions by a regex that can catch declarations.

- [ ] **Step 4: Hand-resolve until the validator passes**

Standard report pass Step C, then Step D. Expected: `source map OK`. All 13 addresses accounted for; 11 in `mapped`, 2 in `unmapped`, and — unless the analyzers genuinely disagree — nothing in `boundary_disputed` or `duplicate_candidates`.

- [ ] **Step 5: Diff all 11 mapped functions**

Standard report pass Step E. Decompile each and read it against `PS2Mouse.m`. Specific things to resolve, in addition to whatever the disassembly shows:

- `-[PS2Mouse readConfigTable:]` (684, 216 bytes) — the reference logs `no configuration table` and `no resolution in config table.  Default is %d`; ours logs different text and reads different keys. Does the control flow match once the strings are set aside?
- `_PS2MouseIntHandler` (900, 528 bytes) — the largest function. The reference logs `mouse reset` and `mouse reset after resync`; ours logs two self-test messages instead. Establish whether ours has the reference's resync state machine at all.
- `-[PS2Mouse mouseInit:]` (0, 180) versus `-[PS2Mouse initWithController:]` (332, 352) — which of the two holds the `initPointer: Can't find PS2Controller (%s)` call, and does our split match.
- **`Force Detection` sense — Task 2 deferred this and Task 4 depends on the answer.** Read `-[PS2Mouse readConfigTable:]` (684, 216) to see how the parsed value is stored, and `-[PS2Mouse initWithController:]` (332, 352) to see how it gates the presence check. Decide which of these the reference means, and record it as an explicit finding either way:
  - `Force Detection = Yes` bypasses the presence check and attaches regardless — identical to what our `if (!forceDetection)` at `PS2Mouse.m:414` already does, so no inversion is needed.
  - `Force Detection = Yes` runs a check that is otherwise skipped — the sense is opposite and Task 4 must invert the test.

  If the disassembly cannot settle it, say so and record `intentional-mismatch` with that reason rather than guessing. A wrong guess here silently changes whether the driver attaches on hardware where detection fails.
- The `__DATA,__bss` statics `_indexInSequence`, `_currentEvent`, `_pendingEvent`, `_summedEvent`, `_lastTimeStamp`, `_seqBeingProcessed`, `_seqInProgress`, `_func_list` — confirm ours declares the same set with the same widths. `_lastTimeStamp` is 8 bytes, `_seqBeingProcessed` and `_seqInProgress` are 1 byte each with 2 bytes of padding before `_func_list`.

- [ ] **Step 6: Compare the table**

Standard report pass Step F. Expected clean after Task 2; if not, that is a Task 2 defect and must be said so.

- [ ] **Step 7: Write `divergences.md` and `ledger.json`**

Standard report pass Steps G and H. The baseline-build note says the build has not been attempted yet and that Task 4 establishes it — do not invent a size. Record in the unmapped section that the two glue methods are emitted by the Kernel Server project type and `Load_Commands.sect`, and that `_PS2Mouse_VERS_STRING`, `_PS2Mouse_VERS_NUM` and `_PS2Mouse_instance` are data symbols outside `__TEXT,__text` that therefore do not appear in the map at all.

Record the Task 2 fixes as already-resolved findings, with their status advanced only if the disassembly of the containing function was actually read.

- [ ] **Step 8: Verify the ledger loads**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/ps2mouse.json \
  --ledger src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json
```

Expected: the ledger prints without error, showing 13 entries and `reference_sha256` matching `4C43D8A9…`.

- [ ] **Step 9: Re-run the source map validator as a final gate**

Standard report pass Step D. Expected: `source map OK`.

- [ ] **Step 10: Commit**

```bash
git add src/drivers-i386/input/drvPS2Mouse/reconstruction/source-map.json
git commit -m "drivers-i386: map drvPS2Mouse against the reference binary"

git add src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json \
        src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md
git commit -m "drivers-i386: record the drvPS2Mouse parity ledger and divergences"
```

---

### Task 4: drvPS2Mouse fix pass

**Files:**
- Modify: `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m`, `PS2Mouse.h` as the ledger requires
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json`
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md`
- Stage (untracked): `out/i386/drvPS2Mouse/PS2Mouse.config/PS2Mouse_reloc`

**Interfaces:**
- Consumes: `divergences.md` and `ledger.json` from Task 3; `vm/build-i386-input-drivers.sh` from Task 1.
- Produces: a drvPS2Mouse whose `__cstring` set contains every reference string, and a ledger with no `unexamined` entry left.

**Standard fix pass procedure values:** `<name>` = `ps2mouse`, `<drv>` = `drvPS2Mouse`, `<Config>` = `PS2Mouse`.

- [ ] **Step 1: Baseline build**

Standard fix pass Step A: `sh /build/source/vm/build-i386-input-drivers.sh drvPS2Mouse`. Expected `fail=0` and a staged `PS2Mouse_reloc`. Record its size — it will exceed the reference's 30204 bytes because our build is unstripped, which is expected and not a finding.

If the guest is unavailable, say so and continue to Step 3; Steps 1, 2 and 6 then report as unrun.

- [ ] **Step 2: Baseline parity**

Standard fix pass Step B. Record the four counts. Based on Task 3's string analysis, expect roughly five `missing_strings` and zero `missing_symbols`.

- [ ] **Step 3: Fix every finding**

Standard fix pass Step C, working `divergences.md` in order. The known set from Task 3's scoping, to be confirmed and extended by that task's actual findings:

- add `initPointer: Can't find PS2Controller (%s)` on the controller-lookup failure path, replacing `PS2Mouse: Failed to get controller: %s`
- replace `PS2Mouse: Using default resolution %d` with `PS2Mouse readConfigTable: no resolution in config table.  Default is %d` (note the two spaces after the period)
- add `PS2Mouse readConfigTable: no configuration table`, replacing `PS2Mouse: No device description provided` if that is what occupies the path
- replace the two self-test messages with `PS2Mouse: mouse reset` and `PS2Mouse: mouse reset after resync`, and align `_PS2MouseIntHandler`'s resync logic with the reference
- **apply Task 3's answer on the `Force Detection` sense.** If Task 3 found that `Yes` bypasses the presence check, `PS2Mouse.m:414`'s `if (!forceDetection)` is already correct and nothing changes. If it found the opposite, invert to `if (forceDetection)`. If Task 3 could not settle it, leave the test alone and confirm the ledger entry says `intentional-mismatch` with that reason — do not decide it here without the disassembly.
- whatever control-flow divergences Task 3 recorded

- [ ] **Step 4: Advance the ledger**

Standard fix pass Step D. Every entry that was `unexamined` becomes either a confirmed status or an `intentional-mismatch` with a reason and `--reviewer 'Pat Raynor'`. Verify none is left:

```bash
./.venv-binrecon/Scripts/python.exe -c "
import json
d=json.load(open('src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json'))
left=[e['names'] for e in d['entries'] if e['status']=='unexamined']
print('unexamined:', len(left)); [print(' ', n) for n in left]
"
```

Expected: `unexamined: 0`.

- [ ] **Step 5: Update `divergences.md`**

Add a resolution line per finding stating what changed and the new ledger status, or why the divergence was accepted.

- [ ] **Step 6: Rebuild and re-check parity**

Standard fix pass Step E. Expected: `missing_strings` reduced to 0, `missing_symbols` still 0. Every string listed in Step 3 must be absent from `missing_strings`.

- [ ] **Step 7: Commit**

```bash
git add src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/
git commit -m "drivers-i386: align drvPS2Mouse with the reference binary

Restores the reference log strings and the interrupt handler's resync
handling."

git add src/drivers-i386/input/drvPS2Mouse/reconstruction/
git commit -m "drivers-i386: advance the drvPS2Mouse ledger after the fix pass"
```

---

### Task 5: drvSerialPointingDevice report pass

16 hand-written functions plus 2 glue. This driver is in the best shape of the five — its string set nearly matches, including the reference's own typo `SerialPorintingDevice: Main thread terminated.`

**Files:**
- Create: `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/source-map.json`
- Create: `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/ledger.json`
- Create: `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/divergences.md`
- Read: `.../SerialPointingDevice.lksproj/SerialPointingDevice.m` (911 lines), `SerialPointingDevice.h` (96 lines)

**Interfaces:**
- Consumes: `tools/binrecon/profiles/serialpointingdevice.json` from Task 1.
- Produces: a validated 18-function `source-map-v1`, an 18-entry `ledger-v1`, and a `divergences.md` Task 6 consumes.

**Standard report pass procedure values:** `<name>` = `serialpointingdevice`, `<drv>` = `drvSerialPointingDevice`, `<Config>` = `SerialPointingDevice`, `<drvproj>` = `SerialPointingDevice.drvproj`, `<lksproj>` = `SerialPointingDevice.drvproj/SerialPointingDevice.lksproj`.

**Reference function partition** (`_mainLoop` is `external`; the rest are `local`):

| Address | Size | Name |
| --- | --- | --- |
| 0 | 28 | `_mainLoop` (external) |
| 28 | 880 | `-[SerialPointingDevice mouseInit:]` |
| 908 | 108 | `-[SerialPointingDevice free]` |
| 1016 | 16 | `-[SerialPointingDevice getResolution]` |
| 1032 | 72 | `-[SerialPointingDevice setEventTarget:]` |
| 1104 | 96 | `-[SerialPointingDevice getIntValues:forParameter:count:]` |
| 1200 | 264 | `-[SerialPointingDevice setIntValues:forParameter:count:]` |
| 1464 | 308 | `-[SerialPointingDevice mainLoop:]` |
| 1772 | 104 | `-[SerialPointingDevice getByte:sleep:]` |
| 1876 | 1380 | `-[SerialPointingDevice detect]` |
| 3256 | 444 | `-[SerialPointingDevice MSProtocol]` |
| 3700 | 24 | `-[SerialPointingDevice MPlusProtocol]` |
| 3724 | 600 | `-[SerialPointingDevice FiveBProtocol]` |
| 4324 | 40 | `-[SerialPointingDevice MMProtocol]` |
| 4364 | 40 | `-[SerialPointingDevice RBProtocol]` |
| 4404 | 40 | `-[SerialPointingDevice UnknownProtocol]` |
| 4444 | 12 | `+[SerialPointingDeviceKernelServerInstance kernelServerInstance]` |
| 4456 | 12 | `+[SerialPointingDeviceVersion driverKitVersionForSerialPointingDevice]` |

Last bounded by `__text` size 4468.

**Known divergences to confirm and resolve:**

- **`_mouseTypeList` slot 3.** The reference has six `char *` at `__DATA,__data:8192` (24 bytes, ending where `_protocolList` starts at 8216) holding `C`, `W3`, `W`, `V3`, `M`, `UNKNOWN`. Our `mouseTypeNames` at `SerialPointingDevice.m:41` has `UNKNOWN`, `M`, `V3`, `M`, `W3`, `C` — reverse order, which is expected since `__cstring` emission is reversed, but with `M` where the reference has `W`. Resolve from the disassembly of `-[SerialPointingDevice detect]` (1876, 1380 bytes) what `W` denotes and how `detect` reaches it. Our `detect` looks for the `M3` signature at `SerialPointingDevice.m:121` and has no `W` path at all. If the disassembly cannot settle it, the entry becomes `intentional-mismatch` with the reason recorded — do not guess.
- **Four linkage divergences.** The reference exports `_mainLoop` (`__text:0`), `_mouseTypeList` (8192), `_protocolList` (8216) and `_active` (8240) as `external`. Ours declares all four `static` — `mainLoop` at `SerialPointingDevice.m:65`, `mouseTypeNames` at 41, `protocolList` at 51, `active` at 60. `_active` is 1 byte, confirming `BOOL`; `__DATA,__data` totals 49 bytes = 24 + 24 + 1. Precedent for the fix is commit b27e22b8 in drvPCMCIABus.
- **Two extra log strings.** Ours emits `%s: MSProtocol started` and `%s: FiveBProtocol started`; the reference has neither. Establish from the disassembly of `MSProtocol` (3256) and `FiveBProtocol` (3724) whether the reference has any logging there.
- **One dropped space.** Reference: `%s: No resolution in config table.  Defaulting to %d`. Ours has one space after the period.
- **`protocolList` matches** the reference exactly. Expected `assembly-matched` on whatever function indexes it.

- [ ] **Step 1: Run the analyzers**

Standard report pass Step A with `<name>` = `serialpointingdevice` and

```bash
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\SerialPointingDevice.config\SerialPointingDevice_reloc'
```

Expected: exit 1 (see Step A — reference-only profiles always fail acceptance) and `"complete": true` with `reference_sha256` `59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59`.

- [ ] **Step 2: Generate the source map**

Standard report pass Step B with `--source-dir src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj`.

- [ ] **Step 3: Run the validator to see it fail**

Standard report pass Step D with `<name>` = `serialpointingdevice`, `<drv>` = `drvSerialPointingDevice`. Expected: an error or unplaced entries. `_mainLoop` at address 0 and the static `mainLoop` at `SerialPointingDevice.m:65` are the same function under different linkage, so the generator should place it; confirm rather than assume.

- [ ] **Step 4: Hand-resolve until the validator passes**

Standard report pass Steps C then D. Expected: `source map OK`, 16 in `mapped`, 2 in `unmapped`.

- [ ] **Step 5: Diff all 16 mapped functions**

Standard report pass Step E, resolving each item in the Known divergences list above plus whatever the disassembly shows. `-[SerialPointingDevice detect]` at 1380 bytes is the bulk of the reading and the only place the `W` mouse type can be settled.

- [ ] **Step 6: Compare the table**

Standard report pass Step F.

- [ ] **Step 7: Write `divergences.md` and `ledger.json`**

Standard report pass Steps G and H. `_SerialPointingDevice_VERS_STRING`, `_VERS_NUM` and `_instance` are data symbols outside `__TEXT,__text` and do not appear in the map.

- [ ] **Step 8: Verify the ledger loads**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/serialpointingdevice.json \
  --ledger src/drivers-i386/input/drvSerialPointingDevice/reconstruction/ledger.json
```

Expected: 18 entries, `reference_sha256` matching `59C0C95C…`.

- [ ] **Step 9: Re-run the source map validator as a final gate**

Standard report pass Step D. Expected: `source map OK`.

- [ ] **Step 10: Commit**

```bash
git add src/drivers-i386/input/drvSerialPointingDevice/reconstruction/source-map.json
git commit -m "drivers-i386: map drvSerialPointingDevice against the reference binary"

git add src/drivers-i386/input/drvSerialPointingDevice/reconstruction/ledger.json \
        src/drivers-i386/input/drvSerialPointingDevice/reconstruction/divergences.md
git commit -m "drivers-i386: record the drvSerialPointingDevice parity ledger and divergences"
```

---

### Task 6: drvSerialPointingDevice fix pass

**Files:**
- Modify: `.../SerialPointingDevice.lksproj/SerialPointingDevice.m`, `SerialPointingDevice.h` as the ledger requires
- Modify: `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/ledger.json`, `divergences.md`
- Stage (untracked): `out/i386/drvSerialPointingDevice/SerialPointingDevice.config/SerialPointingDevice_reloc`

**Interfaces:**
- Consumes: Task 5's `divergences.md` and `ledger.json`; Task 1's build script.
- Produces: a driver whose `__text` symbol set includes `_mainLoop` and whose `__DATA,__data` exports `_mouseTypeList`, `_protocolList` and `_active`, with no `unexamined` ledger entry.

**Standard fix pass procedure values:** `<name>` = `serialpointingdevice`, `<drv>` = `drvSerialPointingDevice`, `<Config>` = `SerialPointingDevice`.

- [ ] **Step 1: Baseline build**

Standard fix pass Step A: `sh /build/source/vm/build-i386-input-drivers.sh drvSerialPointingDevice`.

- [ ] **Step 2: Baseline parity**

Standard fix pass Step B. Expect `missing_symbols` to include `_mainLoop` — ours is `static`, so it emits no `__text` symbol at all — and `missing_strings` to include the two-space resolution message.

- [ ] **Step 3: Fix the four linkage divergences**

Remove `static` from `mainLoop` (`SerialPointingDevice.m:65`), `mouseTypeNames` (41), `protocolList` (51) and `active` (60), so each emits an `external` symbol as the reference does. Rename `mouseTypeNames` to `mouseTypeList` to match the reference symbol `_mouseTypeList`; the other three already carry the reference's names. Add declarations to `SerialPointingDevice.h` only if the file's existing convention requires them — the reference gives no evidence either way, and adding unneeded declarations is scope creep.

- [ ] **Step 4: Fix the `mouseTypeList` slot**

Set slot 3 to `W` per Task 5's resolution, and implement whatever `detect` path reaches it. If Task 5 could not settle it from the disassembly, do not guess: leave the slot, and record `intentional-mismatch` with the reason.

- [ ] **Step 5: Fix the strings**

Remove `%s: MSProtocol started` and `%s: FiveBProtocol started` if Task 5 confirmed the reference has no logging there. Restore the second space in `%s: No resolution in config table.  Defaulting to %d`.

- [ ] **Step 6: Fix remaining findings and advance the ledger**

Standard fix pass Steps C and D. Verify none is left:

```bash
./.venv-binrecon/Scripts/python.exe -c "
import json
d=json.load(open('src/drivers-i386/input/drvSerialPointingDevice/reconstruction/ledger.json'))
left=[e['names'] for e in d['entries'] if e['status']=='unexamined']
print('unexamined:', len(left)); [print(' ', n) for n in left]
"
```

Expected: `unexamined: 0`.

- [ ] **Step 7: Update `divergences.md`**

A resolution line per finding.

- [ ] **Step 8: Rebuild and re-check parity**

Standard fix pass Step E. `_mainLoop` must now be present in our `__text` symbols, and the two-space message present in our `__cstring`.

- [ ] **Step 9: Commit**

```bash
git add src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/
git commit -m "drivers-i386: align drvSerialPointingDevice with the reference binary

Restores Apple's external linkage for mainLoop, mouseTypeList, protocolList
and active, and corrects the mouse type table."

git add src/drivers-i386/input/drvSerialPointingDevice/reconstruction/
git commit -m "drivers-i386: advance the drvSerialPointingDevice ledger after the fix pass"
```

---

### Task 7: drvPS2Keyboard report pass

47 hand-written functions plus 2 glue, across two source files.

**Files:**
- Create: `src/drivers-i386/input/drvPS2Keyboard/reconstruction/source-map.json`
- Create: `src/drivers-i386/input/drvPS2Keyboard/reconstruction/ledger.json`
- Create: `src/drivers-i386/input/drvPS2Keyboard/reconstruction/divergences.md`
- Read: `.../PS2Keyboard.lksproj/PS2Controller.m` (1029 lines), `PS2Keyboard.m` (624), `PS2Controller.h` (124), `PS2Keyboard.h` (63)

**Interfaces:**
- Consumes: `tools/binrecon/profiles/ps2keyboard.json` from Task 1.
- Produces: a validated 49-function `source-map-v1`, a 49-entry `ledger-v1`, and a `divergences.md` Task 8 consumes.

**Standard report pass procedure values:** `<name>` = `ps2keyboard`, `<drv>` = `drvPS2Keyboard`, `<Config>` = `PS2Keyboard`, `<drvproj>` = `PS2Keyboard.drvproj`, `<lksproj>` = `PS2Keyboard.drvproj/PS2Keyboard.lksproj`.

**File boundary from link order.** Reference addresses run `PS2Controller` material from 0 to 2404, then `PS2Keyboard` material from 2404 to 4952. The boundary sits between `_NewStealKeyboardEvent` (2320, external) and `+[PS2Keyboard deviceStyle]` (2404), which matches our two-file split: `PS2Controller.m` then `PS2Keyboard.m`. Confirm this rather than assume it — a function on the wrong side of the boundary is a file-placement finding of the kind the Intel spec found in `PCIC`.

**Fourteen external C functions**, all with reference names carrying no extra underscore, against our source's one-underscore-deeper spelling:

| Address | Reference symbol | C source name the reference implies |
| --- | --- | --- |
| 484 | `_keyboardDataPresent` | `keyboardDataPresent` |
| 1608 | `_getKeyboardData` | `getKeyboardData` |
| 1768 | `_getKeyboardDataIfPresent` | `getKeyboardDataIfPresent` |
| 1824 | `_getMouseData` | `getMouseData` |
| 1892 | `_getMouseDataIfPresent` | `getMouseDataIfPresent` |
| 1960 | `_clearOutputBuffer` | `clearOutputBuffer` |
| 2004 | `_sendControllerData` | `sendControllerData` |
| 2084 | `_resendControllerData` | `resendControllerData` |
| 2132 | `_sendControllerCommand` | `sendControllerCommand` |
| 2208 | `_sendMouseCommand` | `sendMouseCommand` |
| 2264 | `_disableMouse` | `disableMouse` |
| 2292 | `_enableMouse` | `enableMouse` |
| 2320 | `_NewStealKeyboardEvent` | `NewStealKeyboardEvent` |
| 3520 | `_scancodeToKeyEvent` | `scancodeToKeyEvent` |

One further external, `__PS2KeyboardNumKeysDown` at 3364, implies the C name `_PS2KeyboardNumKeysDown` — a genuine leading underscore in source, unlike the fourteen above. Do not "fix" that one.

**`_exported_funcs`** at `__DATA,__data:8192` is 32 bytes — eight pointers, since `_lalt_ralt_numlock` starts at 8224 — so it publishes eight of the fourteen. Establish which eight and in what order from the disassembly. If that cannot be settled, record it in `divergences.md` unresolved; the rename still proceeds because it is a source-name change.

**Two log strings diverge**, and both are behavioural claims, not wording:

- reference `PS2Keyboard kbdInit: no Interface ID; use default`, ours `PS2Keyboard kbdInit: no Interface key in config table`
- reference `PS2Keyboard kbdInit: no Handler ID; use default`, ours `PS2Keyboard kbdInit: no Handler ID key in config table`

"Use default" asserts the driver continues. Confirm from `-[PS2Keyboard readConfigTable:]` (2588, 172 bytes) that it does.

Ours also has `Write to Auxiliary Device` at `PS2Controller.m:753`, which the reference lacks — check whether it is a comment rather than a literal before recording it as a finding.

- [ ] **Step 1: Run the analyzers**

Standard report pass Step A with `<name>` = `ps2keyboard` and

```bash
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Keyboard.config\PS2Keyboard_reloc'
```

Expected: exit 1 (see Step A), `"complete": true`, `reference_sha256` `AB413CA3919950F22A1F5D10B0BF1167387FEF320C9FB82A3EA66E586A6BE02A`.

- [ ] **Step 2: Generate the source map**

Standard report pass Step B with `--source-dir src/drivers-i386/input/drvPS2Keyboard/PS2Keyboard.drvproj/PS2Keyboard.lksproj`. Both `.m` files are in that one directory, so a single `--source-dir` covers them.

- [ ] **Step 3: Run the validator to see it fail**

Standard report pass Step D with `<name>` = `ps2keyboard`, `<drv>` = `drvPS2Keyboard`. Expected: failures, most likely on the fourteen C functions — our source spells them `_getKeyboardData` and so on, which does not match the reference symbol `_getKeyboardData` after the compiler's leading underscore is accounted for. Resolve by name in the map now; the source rename is Task 8's job.

- [ ] **Step 4: Hand-resolve until the validator passes**

Standard report pass Steps C then D. Expected: `source map OK`, 47 in `mapped`, 2 in `unmapped`.

- [ ] **Step 5: Diff all 47 mapped functions**

Standard report pass Step E, batched by file — `PS2Controller.m` for addresses 0 to 2404, `PS2Keyboard.m` for 2404 to 4952. Give particular attention to:

- `_scancodeToKeyEvent` (3520, 820 bytes) — the largest function in the driver
- `_isEscape` (756, 208), `_resetEscapes` (964), `_undoEscape` (1020), `_doEscape` (1100, 192) and the `_escapes` table at `__DATA,__data:8288` (144 bytes), plus `_lalt_ralt_numlock`, `_ralt_lalt_numlock`, `_lalt_numlock` and `_ralt_numlock` at 8224/8240/8256/8272, 16 bytes each
- `-[PS2Keyboard dispatchKeyboardEvents]` (3140, 224) and `-[PS2Keyboard enqueueKeyEvent:goingDown:atTime:]` (3420, 100)
- the ownership trio `becomeOwner:` (4416, 216), `relinquishOwnership:` (4632, 196), `desireOwnership:` (4828, 100), whose two `%s:` log strings already match
- `__kbdBitVector` at `__DATA,__bss:8520` (16 bytes) and `_keyboardQueueElements` at `__DATA,__common:8536` (384 bytes)

- [ ] **Step 6: Compare the table**

Standard report pass Step F. drvPS2Keyboard's table already matched the reference before Task 2, including its `"Version"` line. Record in `divergences.md` that it is the only one of the five carrying a verbatim copy of Apple's `"Driver Version"` build stamp in checked-in source, that the line is out of the comparison, and that it is deliberately left alone rather than widening the diff.

- [ ] **Step 7: Write `divergences.md` and `ledger.json`**

Standard report pass Steps G and H.

- [ ] **Step 8: Verify the ledger loads**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/ps2keyboard.json \
  --ledger src/drivers-i386/input/drvPS2Keyboard/reconstruction/ledger.json
```

Expected: 49 entries, `reference_sha256` matching `AB413CA3…`.

- [ ] **Step 9: Re-run the source map validator as a final gate**

Standard report pass Step D. Expected: `source map OK`.

- [ ] **Step 10: Commit**

```bash
git add src/drivers-i386/input/drvPS2Keyboard/reconstruction/source-map.json
git commit -m "drivers-i386: map drvPS2Keyboard against the reference binary"

git add src/drivers-i386/input/drvPS2Keyboard/reconstruction/ledger.json \
        src/drivers-i386/input/drvPS2Keyboard/reconstruction/divergences.md
git commit -m "drivers-i386: record the drvPS2Keyboard parity ledger and divergences"
```

---

### Task 8: drvPS2Keyboard fix pass

**Files:**
- Modify: `.../PS2Keyboard.lksproj/PS2Controller.m`, `PS2Keyboard.m`, `PS2Controller.h`, `PS2Keyboard.h` as the ledger requires
- Modify: `src/drivers-i386/input/drvPS2Keyboard/reconstruction/ledger.json`, `divergences.md`
- Stage (untracked): `out/i386/drvPS2Keyboard/PS2Keyboard.config/PS2Keyboard_reloc`

**Interfaces:**
- Consumes: Task 7's `divergences.md` and `ledger.json`; Task 1's build script.
- Produces: a driver whose fourteen exported C functions carry Apple's names, so that `parity_check.py` reports them present, and whose two `kbdInit` log strings match the reference.

**Standard fix pass procedure values:** `<name>` = `ps2keyboard`, `<drv>` = `drvPS2Keyboard`, `<Config>` = `PS2Keyboard`.

**Cross-driver caution.** drvPS2Mouse reaches this driver through `IOGetObjectForDeviceName("PS2Controller", …)` after Task 2, and `PS2Controller.m:182-183` publishes that name. Do not change either. If the rename in Step 3 touches anything drvPS2Mouse calls, check `src/drivers-i386/input/drvPS2Mouse/` for references before committing.

- [ ] **Step 1: Baseline build**

Standard fix pass Step A: `sh /build/source/vm/build-i386-input-drivers.sh drvPS2Keyboard`.

- [ ] **Step 2: Baseline parity**

Standard fix pass Step B. Expect `missing_symbols` to list the fourteen reference names — `_getKeyboardData`, `_scancodeToKeyEvent` and the rest — because our source spells each one underscore deeper, so our build emits `__getKeyboardData` and so on. Expect `missing_strings` to list the two `kbdInit` messages.

- [ ] **Step 3: Rename the fourteen C functions**

In `PS2Controller.m`, `PS2Keyboard.m` and their headers, drop the leading underscore from each of the fourteen source names in the Task 7 table, so the compiler emits the reference's symbol. Precedent is commit b27e22b8 in drvPCMCIABus, which resolved the same divergence by renaming our source to match Apple's.

Leave `_PS2KeyboardNumKeysDown` alone — the reference symbol `__PS2KeyboardNumKeysDown` already implies a genuine leading underscore in source.

Verify afterwards that no call site was missed:

```bash
grep -rn '_keyboardDataPresent\|_getKeyboardData\|_getKeyboardDataIfPresent\|_getMouseData\|_getMouseDataIfPresent\|_clearOutputBuffer\|_sendControllerData\|_resendControllerData\|_sendControllerCommand\|_sendMouseCommand\|_disableMouse\|_enableMouse\|_NewStealKeyboardEvent\|_scancodeToKeyEvent' \
  src/drivers-i386/input/drvPS2Keyboard/ src/drivers-i386/input/drvPS2Mouse/
```

Expected: only `_PS2KeyboardNumKeysDown` and any legitimate substring matches remain. Every bare `_getKeyboardData`-style spelling must be gone.

- [ ] **Step 4: Fix the two `kbdInit` log strings**

Set them to the reference's exact text, and confirm the surrounding control flow actually continues with a default as `use default` asserts:

```objc
        IOLog("PS2Keyboard kbdInit: no Interface ID; use default\n");
```

```objc
        IOLog("PS2Keyboard kbdInit: no Handler ID; use default\n");
```

- [ ] **Step 5: Fix remaining findings and advance the ledger**

Standard fix pass Steps C and D, including the `_exported_funcs` layout if Task 7 settled it. Verify none is left:

```bash
./.venv-binrecon/Scripts/python.exe -c "
import json
d=json.load(open('src/drivers-i386/input/drvPS2Keyboard/reconstruction/ledger.json'))
left=[e['names'] for e in d['entries'] if e['status']=='unexamined']
print('unexamined:', len(left)); [print(' ', n) for n in left]
"
```

Expected: `unexamined: 0`.

- [ ] **Step 6: Update `divergences.md`**

A resolution line per finding.

- [ ] **Step 7: Rebuild and re-check parity**

Standard fix pass Step E. All fourteen names must be gone from `missing_symbols`, and both `kbdInit` messages gone from `missing_strings`.

- [ ] **Step 8: Commit**

```bash
git add src/drivers-i386/input/drvPS2Keyboard/PS2Keyboard.drvproj/PS2Keyboard.lksproj/
git commit -m "drivers-i386: align drvPS2Keyboard with the reference binary

Renames the fourteen exported C functions to Apple's spelling and restores
the kbdInit log strings."

git add src/drivers-i386/input/drvPS2Keyboard/reconstruction/
git commit -m "drivers-i386: advance the drvPS2Keyboard ledger after the fix pass"
```

---

### Task 9: drvPCParallel report pass

73 hand-written functions plus 2 glue — the largest in scope. Most are one-line accessors, which makes the count less daunting than it looks: 40 of the 75 are between 16 and 40 bytes.

**Files:**
- Create: `src/drivers-i386/input/drvPCParallel/reconstruction/source-map.json`
- Create: `src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json`
- Create: `src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md`
- Read: `.../PCParallelPort.lksproj/IOParallelPort.m` (1058 lines), `IOParallelPortKern.m` (1377), `IOParallelPort.h` (233), `IOParallelPortKern.h` (125)

**Interfaces:**
- Consumes: `tools/binrecon/profiles/parallelport.json` from Task 1; the Task 2 tree state, including the three new project files.
- Produces: a validated 75-function `source-map-v1`, a 75-entry `ledger-v1`, and a `divergences.md` Task 10 consumes.

**Standard report pass procedure values:** `<name>` = `parallelport`, `<drv>` = `drvPCParallel`, `<Config>` = `ParallelPort`, `<drvproj>` = `PCParallelPort.drvproj`, `<lksproj>` = `PCParallelPort.drvproj/PCParallelPort.lksproj`.

**Scope boundary.** `InstallPPDev` and `RemovePPDev` are user-space tools built from `PreLoad.tproj` and `PostLoad.tproj` and named in `Default.table` as `"Pre-Load"` and `"Post-Load"`. They are compiled in Task 10 but are **not** function-compared, and their sources are not in `--source-dir`. `IODeviceMaster.m` (2180 lines, under `PreLoad.tproj`) is therefore out of scope for this task entirely.

**File boundary from link order.** The `-[IOParallelPort …]` methods and the `cdevsw` entry points are interleaved in a way that has to be read from the addresses rather than assumed. The three externals — `__strobeChar` (4232, implying C source name `_strobeChar`), `_IOParallelPortThread` (4512, implying `IOParallelPortThread`), `_IOParallelPortInterruptHandler` (5240, implying `IOParallelPortInterruptHandler`) — sit between `-[IOParallelPort cmdBufComplete:]` (4184) and `_ppopen` (5520), which is where `IOParallelPortKern.m` material would start if the split follows ours. Confirm from the addresses.

Note `__strobeChar` has two leading underscores in the symbol, so its C source name genuinely starts with one underscore, unlike `IOParallelPortThread` and `IOParallelPortInterruptHandler`. Check each of the three separately against our source's spelling rather than applying one rule to all.

**The seven `cdevsw` entry points**, all `local`: `_ppopen` (5520), `_ppclose` (5652), `_ppread` (5692), `_ppwrite` (5828), `_ppminphys` (6252), `_ppstrategy` (6304), `_ppioctl` (6708, 684 bytes — the largest). `_pp_softc` is at `__DATA,__data:8192` (12 bytes).

**Known string divergences to confirm:**

- reference `IOParallelPort not allocated: controller not detected at address 0x%x`, ours `IOParallelPort: parallel port at 0x%x not found`
- ours has `ParallelPort0` and `pp0` which the reference lacks; check whether each is a `__cstring` literal or a value the compiler routes elsewhere before recording it. `parity_check.py` reads `__cstring` only, so `__OBJC` selector and class-name literals such as `NXConditionLock`, `writeToPort` and `setBlockSize:` cannot appear as findings.
- ours has `IOThreadDelay` as both a selector string at `IOParallelPortKern.m:854` and a method name; the reference has no such `__cstring` entry, consistent with it being `__OBJC` material on both sides
- after Task 2, both `Minor Device Number` and `0` must be present in ours

**Expect angr CFG errors.** `IOParallelPortKern.m` dispatches through `sel_getUid` at lines 787, 854 and 1189. `CFGFast` cannot resolve those indirect targets. They are recorded as CFG errors and never read as "function absent".

- [ ] **Step 1: Run the analyzers**

Standard report pass Step A with `<name>` = `parallelport` and

```bash
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\ParallelPort.config\ParallelPort_reloc'
```

Expected: exit 1 (see Step A), `"complete": true`, `reference_sha256` `D188A4D909005683B0C943C84CD99514C14A84AD1D378425B3B1DB343F1EAAA2`. Expect a non-empty angr CFG error list; that does not make the run incomplete.

- [ ] **Step 2: Generate the source map**

Standard report pass Step B with `--source-dir src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj`. This excludes `PreLoad.tproj` and `PostLoad.tproj`, which is correct per the Scope boundary above.

- [ ] **Step 3: Run the validator to see it fail**

Standard report pass Step D with `<name>` = `parallelport`, `<drv>` = `drvPCParallel`. Expected: failures. With 75 functions this is the task most likely to hit `boundary_disputed` entries and accessor-sized functions the generator mis-lines.

- [ ] **Step 4: Hand-resolve until the validator passes**

Standard report pass Steps C then D. Expected: `source map OK`, 73 in `mapped`, 2 in `unmapped`.

- [ ] **Step 5: Diff all 73 mapped functions**

Standard report pass Step E, batched by file. Budget the reading by size rather than count — the 40 accessors between 16 and 40 bytes are checkable in bulk, and the real work is in:

- `-[IOParallelPort initFromDeviceDescription:]` (456, 996 bytes) — holds the Task 2 config-key fix and three of the reference's `not allocated` messages. **Four questions Task 2 deferred here, all of which Task 10 depends on.** First, does the reference call `setLocation:` at all? Its `__cstring` has no `Location` entry, so it does not read that key, but `setLocation:` could take its argument from elsewhere. Ours reads the key at `IOParallelPort.m:158` and the reference `Default.table` does carry `"Location" = "System Baseboard"`, so the key is legitimate — the question is only whether the reference's driver consumes it. Second, does the reference free the `Minor Device Number` string it reads? Ours has a `NULL` fallback to a string literal that must not reach `freeString:`. Third, does the reference call `[deviceDescription name]` at all? After Task 2, ours fetches it at line 93 and frees it at line 132 without reading it in between — if the reference does not fetch it, both lines go; if it does, find out what it does with it. Fourth, is freeing a `[deviceDescription name]` result through `[configTable freeString:]` correct? That pairing is pre-existing and looks wrong regardless of the reference. Record all four as findings whichever way they resolve.
- `_ppioctl` (6708, 684)
- `_IOParallelPortThread` (4512, 728) and `_IOParallelPortInterruptHandler` (5240, 280)
- `-[IOParallelPort msgTypeToIOReturn:]` (3492, 200), `_ppstrategy` (6304, 404), `-[IOParallelPort writeToPort]` (3212, 268)
- `__strobeChar` (4232, 280)

- [ ] **Step 6: Compare the table**

Standard report pass Step F. Expected clean after Task 2.

- [ ] **Step 7: Write `divergences.md` and `ledger.json`**

Standard report pass Steps G and H. Record in the unmapped section that `InstallPPDev` and `RemovePPDev` are out of the function comparison by design, so a reader does not mistake their absence for a gap. Record the angr `sel_getUid` CFG errors in the analyzer-disagreement section.

- [ ] **Step 8: Verify the ledger loads**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/parallelport.json \
  --ledger src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json
```

Expected: 75 entries, `reference_sha256` matching `D188A4D9…`.

- [ ] **Step 9: Re-run the source map validator as a final gate**

Standard report pass Step D. Expected: `source map OK`.

- [ ] **Step 10: Commit**

```bash
git add src/drivers-i386/input/drvPCParallel/reconstruction/source-map.json
git commit -m "drivers-i386: map drvPCParallel against the reference binary"

git add src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json \
        src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md
git commit -m "drivers-i386: record the drvPCParallel parity ledger and divergences"
```

---

### Task 10: drvPCParallel fix pass

**Files:**
- Modify: `.../PCParallelPort.lksproj/IOParallelPort.m`, `IOParallelPortKern.m`, and their headers as the ledger requires
- Modify: `src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json`, `divergences.md`
- Stage (untracked): `out/i386/drvPCParallel/ParallelPort.config/ParallelPort_reloc`, plus `InstallPPDev` and `RemovePPDev`

**Interfaces:**
- Consumes: Task 9's `divergences.md` and `ledger.json`; Task 1's build script; Task 2's three new project files.
- Produces: a driver whose `__cstring` set contains every reference string, and the first evidence of whether drvPCParallel builds at all.

**Standard fix pass procedure values:** `<name>` = `parallelport`, `<drv>` = `drvPCParallel`, `<Config>` = `ParallelPort`.

- [ ] **Step 1: Baseline build**

Standard fix pass Step A: `sh /build/source/vm/build-i386-input-drivers.sh drvPCParallel`. This driver has never been built, and its `Load_Commands.sect` was present all along, so this baseline establishes for the first time whether it compiles. Record in `divergences.md` whether the build succeeds and whether the `Loaded Server,Load Commands` section is present at Apple's 164 bytes:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import sys
from pathlib import Path
from binrecon.macho import read_macho
d = read_macho(Path(sys.argv[1]))
for s in d['sections']:
    if s['name'].startswith('Loaded Server'):
        print(s['name'], s['size'])
" out/i386/drvPCParallel/ParallelPort.config/ParallelPort_reloc
```

Expected: `Loaded Server,Server Name`, `Loaded Server,Load Commands 164`, `Loaded Server,Instance Var`, `Loaded Server,Server Version`. The reference has no `Unload Commands` section for this driver, so ours must not either.

`InstallPPDev` and `RemovePPDev` are expected to build; if they do not — the bus script's own comment notes user-space helpers need i386 crt/libDriver a PPC guest may lack — record that as a known-environment limitation rather than a source finding.

- [ ] **Step 2: Baseline parity**

Standard fix pass Step B. Expect `missing_strings` to include `IOParallelPort not allocated: controller not detected at address 0x%x`.

- [ ] **Step 3: Fix the detection log string**

Replace ours with the reference's exact text on the same path:

```objc
        IOLog("IOParallelPort not allocated: controller not detected at address 0x%x\n", address);
```

Match the surrounding code's existing argument naming; `IOParallelPort.m` around line 100 through 175 is the region.

- [ ] **Step 4: Fix remaining findings and advance the ledger**

Standard fix pass Steps C and D, including the three external C names — `_strobeChar`, `IOParallelPortThread`, `IOParallelPortInterruptHandler` — each checked separately per Task 9's note, since only one of the three genuinely carries a leading underscore in source.

Also apply Task 9's two deferred answers: whether the reference consumes the `"Location"` key at all, and whether the `Minor Device Number` string is freed. If Task 9 found the reference does not call `setLocation:`, remove the read at `IOParallelPort.m:158` and its `freeString:`; if it does, leave them. If Task 9 could not settle either, leave the code alone and record `intentional-mismatch` with that reason.

Verify none is left:

```bash
./.venv-binrecon/Scripts/python.exe -c "
import json
d=json.load(open('src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json'))
left=[e['names'] for e in d['entries'] if e['status']=='unexamined']
print('unexamined:', len(left)); [print(' ', n) for n in left]
"
```

Expected: `unexamined: 0`.

- [ ] **Step 5: Update `divergences.md`**

A resolution line per finding, plus the Step 1 findings about the `Loaded Server` sections and the two user-space tools.

- [ ] **Step 6: Rebuild and re-check parity**

Standard fix pass Step E. `missing_strings` reduced to 0; `missing_symbols` at or below baseline.

- [ ] **Step 7: Commit**

```bash
git add src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/
git commit -m "drivers-i386: align drvPCParallel with the reference binary

Restores the controller-detection log string and Apple's external C names."

git add src/drivers-i386/input/drvPCParallel/reconstruction/
git commit -m "drivers-i386: advance the drvPCParallel ledger after the fix pass"
```

---

### Task 11: drvBusMouse report pass

11 hand-written functions plus 2 glue. Its `__cstring` set is fully disjoint from ours, so this report pass exists mainly to give Task 12 a mapped, sized partition to write against — expect most entries to end `unexamined` with a finding, and that is the correct outcome, not a failure.

**Files:**
- Create: `src/drivers-i386/input/drvBusMouse/reconstruction/source-map.json`
- Create: `src/drivers-i386/input/drvBusMouse/reconstruction/ledger.json`
- Create: `src/drivers-i386/input/drvBusMouse/reconstruction/divergences.md`
- Read: `.../BusMouse.lksproj/BusMouse.m` (489 lines), `BusMouse.h` (75 lines)
- Read for reference: `src/drivers-i386/input/drvPS2Mouse/reconstruction/` from Task 3

**Interfaces:**
- Consumes: `tools/binrecon/profiles/busmouse.json` from Task 1; Task 3's worked `PCPointer` method mapping, which covers `mouseInit:`, `getResolution`, `getIntValues:forParameter:count:`, `setIntValues:forParameter:count:` and `getHandler:level:argument:forInterrupt:` — the same five selectors appear here.
- Produces: a validated 13-function `source-map-v1`, a 13-entry `ledger-v1`, and a `divergences.md` detailed enough for Task 12 to rewrite all 11 functions from.

**Standard report pass procedure values:** `<name>` = `busmouse`, `<drv>` = `drvBusMouse`, `<Config>` = `BusMouse`, `<drvproj>` = `BusMouse.drvproj`, `<lksproj>` = `BusMouse.drvproj/BusMouse.lksproj`.

**Reference function partition** (all 13 `local`):

| Address | Size | Name |
| --- | --- | --- |
| 0 | 112 | `_GetIRQFromBoard` |
| 112 | 132 | `-[BusMouse validConfiguration:]` |
| 244 | 408 | `_MouseIntHandler` |
| 652 | 56 | `-[BusMouse interruptHandler]` |
| 708 | 124 | `_BusMouseThread` |
| 832 | 392 | `-[BusMouse mouseInit:]` |
| 1224 | 44 | `-[BusMouse free]` |
| 1268 | 40 | `-[BusMouse getHandler:level:argument:forInterrupt:]` |
| 1308 | 16 | `-[BusMouse getResolution]` |
| 1324 | 96 | `-[BusMouse getIntValues:forParameter:count:]` |
| 1420 | 148 | `-[BusMouse setIntValues:forParameter:count:]` |
| 1568 | 12 | `+[BusMouseKernelServerInstance kernelServerInstance]` |
| 1580 | 12 | `+[BusMouseVersion driverKitVersionForBusMouse]` |

Last bounded by `__text` size 1592.

**Reference `__cstring` set**, none of which appears in our source:

```
'Bus Mouse : No bus mouse installed.\n'
"Bus Mouse : configured IRQ (%d) doesn't equal actual IRQ (%d)\n"
'BusMouseThread: msg_receive() returned %d\n'
'BusMouseThread: Bogus msg_local_port\n'
'BusMouse'
'BusMouse mouseInit: no configuration table\n'
'Inverted'
'Resolution'
'BusMouse mouseInit: no resolution in config table.  Default is %d\n'
'Bus mouse running\n'
```

Our source has instead `BusMouse: Bus mouse not detected (signature mismatch)`, `BusMouse: IRQ mismatch - config: %d, detected: %d`, `BusMouse: msg_receive failed: %d`, `BusMouse: interrupt port mismatch`, `BusMouse: No config table`, `BusMouse: Using default resolution %d`, `BusMouse: Initialized successfully`, plus `Inverted`, `Resolution` and `BusMouse`, which do match. Note the reference's `Bus Mouse : ` spelling, with a space before the colon, in exactly two of the ten.

**`__DATA,__bss` layout to match**: `_higherLevelsBusy` (8204, 4), `_event` (8208, 12), `_summedEvent` (8220, 12), `_lastRightButton` (8232, 4), `_lastLeftButton` (8236, 4), preceded by the build-generated `_xxx.86`/`.89`/`.92` at 8192/8196/8200. `_BusMouse_instance` is at `__DATA,__common:8240`.

**Externals the reference imports**, which constrain the rewrite: `_IOForkThread`, `_IOGetTimestamp`, `_IOLog`, `_IOSendInterrupt`, `_PCPatoi`, `_msg_receive`, `_us_spin`, and the classes `IODevice`, `Object`, `PCPointer`. `_us_spin` is notable — our source may not use it, and the reference's use of it is a real behavioural constraint. There is no `_IOSleep` and no `_IODelay`.

- [ ] **Step 1: Run the analyzers**

Standard report pass Step A with `<name>` = `busmouse` and

```bash
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\BusMouse.config\BusMouse_reloc'
```

Expected: exit 1 (see Step A), `"complete": true`, `reference_sha256` `A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864`.

- [ ] **Step 2: Generate the source map**

Standard report pass Step B with `--source-dir src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj`.

- [ ] **Step 3: Run the validator to see it fail**

Standard report pass Step D with `<name>` = `busmouse`, `<drv>` = `drvBusMouse`. Expected: failures.

- [ ] **Step 4: Hand-resolve until the validator passes**

Standard report pass Steps C then D. Expected: `source map OK`, 11 in `mapped`, 2 in `unmapped`. Every function still maps to a source site even though its body diverges — `mapped` records where our implementation lives, not that it is correct.

- [ ] **Step 5: Diff all 11 mapped functions at instruction level**

Standard report pass Step E, but deeper than the other four tasks: Task 12 rewrites from this reading, so `divergences.md` must carry enough disassembly to write against. For each of the 11, record the reference's control-flow shape, every literal constant, every I/O port address, every struct field offset, and every call target. `_MouseIntHandler` (244, 408 bytes) and `-[BusMouse mouseInit:]` (832, 392) are the two that matter most.

Compare the five shared `PCPointer` selectors against Task 3's drvPS2Mouse findings — `getHandler:level:argument:forInterrupt:` is 40 bytes in both drivers, `getResolution` is 16, `getIntValues:forParameter:count:` is 96, `setIntValues:forParameter:count:` is 148. Identical sizes across two independently compiled drivers is strong evidence of a shared implementation shape, so if drvPS2Mouse's versions came out matching, drvBusMouse's should too, and any divergence there is ours.

- [ ] **Step 6: Compare the table**

Standard report pass Step F. Expected clean after Task 2.

- [ ] **Step 7: Write `divergences.md` and `ledger.json`**

Standard report pass Steps G and H. State plainly in the summary that the string sets are disjoint, that this indicates invented control flow rather than invented wording, and that Task 12 rewrites all 11 functions as a unit under the spec's §4.3 approved exception. Most entries will be `unexamined`; that is the convention for a diverging function.

- [ ] **Step 8: Verify the ledger loads**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/busmouse.json \
  --ledger src/drivers-i386/input/drvBusMouse/reconstruction/ledger.json
```

Expected: 13 entries, `reference_sha256` matching `A1AAB49F…`.

- [ ] **Step 9: Re-run the source map validator as a final gate**

Standard report pass Step D. Expected: `source map OK`.

- [ ] **Step 10: Commit**

```bash
git add src/drivers-i386/input/drvBusMouse/reconstruction/source-map.json
git commit -m "drivers-i386: map drvBusMouse against the reference binary"

git add src/drivers-i386/input/drvBusMouse/reconstruction/ledger.json \
        src/drivers-i386/input/drvBusMouse/reconstruction/divergences.md
git commit -m "drivers-i386: record the drvBusMouse parity ledger and divergences"
```

---

### Task 12: drvBusMouse fix pass

Rewrites all 11 hand-written functions against the reference disassembly. This is the largest single piece of work in the plan and the only wholesale rewrite; the spec approves it as a unit rather than finding-by-finding.

**Files:**
- Modify: `.../BusMouse.lksproj/BusMouse.m` (489 lines), `BusMouse.h` (75 lines)
- Modify: `src/drivers-i386/input/drvBusMouse/reconstruction/ledger.json`, `divergences.md`
- Stage (untracked): `out/i386/drvBusMouse/BusMouse.config/BusMouse_reloc`

**Interfaces:**
- Consumes: Task 11's `divergences.md` — specifically its per-function disassembly — and its `ledger.json`; Task 1's build script; Task 4's finished drvPS2Mouse as the worked example of the shared `PCPointer` method set.
- Produces: a drvBusMouse whose `__cstring` set matches the reference's ten entries and whose per-function sizes are close to the reference's.

**Standard fix pass procedure values:** `<name>` = `busmouse`, `<drv>` = `drvBusMouse`, `<Config>` = `BusMouse`.

**Overfit guard.** The whole driver is 1592 bytes of `__text` across 13 functions. A rewritten function materially larger than its reference counterpart means structure was invented again rather than reconstructed. Per-function size against the Task 11 partition table is the check, and it runs at Step 6.

- [ ] **Step 1: Baseline build**

Standard fix pass Step A: `sh /build/source/vm/build-i386-input-drivers.sh drvBusMouse`. drvBusMouse already has its `Load_Commands.sect` and both `PB.project` files, so nothing from Task 2 changed its buildability.

- [ ] **Step 2: Baseline parity**

Standard fix pass Step B. Expect `missing_strings` to list seven of the reference's ten — all but `BusMouse`, `Inverted` and `Resolution` — and `missing_symbols` to be empty, since every reference symbol name already exists in our source.

- [ ] **Step 3: Rewrite the three C functions**

Working from Task 11's disassembly: `_GetIRQFromBoard` (0, 112 bytes), `_MouseIntHandler` (244, 408), `_BusMouseThread` (708, 124).

`_BusMouseThread` must log `BusMouseThread: msg_receive() returned %d` and `BusMouseThread: Bogus msg_local_port` — note `msg_receive()` with parentheses, and `Bogus msg_local_port` rather than our `interrupt port mismatch`. The reference imports `_msg_receive` and `_IOSendInterrupt`.

`_MouseIntHandler` must maintain the `__DATA,__bss` state the reference declares — `_higherLevelsBusy` (4 bytes), `_event` (12), `_summedEvent` (12), `_lastRightButton` (4), `_lastLeftButton` (4) — and the reference imports `_IOGetTimestamp` and `_us_spin`. Our source's use or non-use of `_us_spin` is a real behavioural difference, not a stylistic one.

- [ ] **Step 4: Rewrite the eight methods**

`-[BusMouse validConfiguration:]` (112, 132), `-[BusMouse interruptHandler]` (652, 56), `-[BusMouse mouseInit:]` (832, 392), `-[BusMouse free]` (1224, 44), `-[BusMouse getHandler:level:argument:forInterrupt:]` (1268, 40), `-[BusMouse getResolution]` (1308, 16), `-[BusMouse getIntValues:forParameter:count:]` (1324, 96), `-[BusMouse setIntValues:forParameter:count:]` (1420, 148).

Required log strings, exactly as the reference has them:

- `validConfiguration:` — `Bus Mouse : No bus mouse installed.` and `Bus Mouse : configured IRQ (%d) doesn't equal actual IRQ (%d)`. Both use `Bus Mouse : ` with a space before the colon; the other eight strings do not.
- `mouseInit:` — `BusMouse mouseInit: no configuration table`, `BusMouse mouseInit: no resolution in config table.  Default is %d` (two spaces after the period), and `Bus mouse running` — lower-case `mouse`, no `BusMouse:` prefix, replacing our `BusMouse: Initialized successfully`.

The last four selectors are the shared `PCPointer` set. Take their shape from Task 4's finished drvPS2Mouse, where the same four have the same reference sizes: 40, 16, 96 and 148 bytes.

- [ ] **Step 5: Advance the ledger**

Standard fix pass Step D. Every one of the 13 entries resolves. The 11 rewritten functions get the status their new evidence supports; the 2 glue methods keep `intentional-mismatch`. Verify none is left:

```bash
./.venv-binrecon/Scripts/python.exe -c "
import json
d=json.load(open('src/drivers-i386/input/drvBusMouse/reconstruction/ledger.json'))
left=[e['names'] for e in d['entries'] if e['status']=='unexamined']
print('unexamined:', len(left)); [print(' ', n) for n in left]
"
```

Expected: `unexamined: 0`.

- [ ] **Step 6: Rebuild, re-check parity, and check per-function sizes**

Standard fix pass Step E, then the overfit guard. `missing_strings` must be 0.

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import sys
from pathlib import Path
from binrecon.macho import read_macho
REF = {0:112, 112:132, 244:408, 652:56, 708:124, 832:392, 1224:44,
       1268:40, 1308:16, 1324:96, 1420:148, 1568:12, 1580:12}
d = read_macho(Path(sys.argv[1]))
syms = sorted((s['address'], s['name']) for s in d['symbols']
              if s['section'] == '__TEXT,__text')
text = next(s for s in d['sections'] if s['name'] == '__TEXT,__text')
end = text['address'] + text['size']
for i, (addr, name) in enumerate(syms):
    nxt = syms[i+1][0] if i+1 < len(syms) else end
    print(f'{addr:>6} {nxt-addr:>5} {name}')
print('reference total 1592, ours', text['size'])
" out/i386/drvBusMouse/BusMouse.config/BusMouse_reloc
```

Compare each size against the Task 11 partition table. Our build is unstripped so absolute totals differ, but a *function* materially larger than its reference counterpart is a finding. Record the comparison in `divergences.md` whatever the outcome.

- [ ] **Step 7: Update `divergences.md`**

A resolution line per finding, plus the Step 6 per-function size table.

- [ ] **Step 8: Commit**

```bash
git add src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/
git commit -m "drivers-i386: rewrite drvBusMouse against the reference binary

Its log strings shared nothing with Apple's, indicating invented control
flow; all eleven hand-written functions are reconstructed from the
disassembly."

git add src/drivers-i386/input/drvBusMouse/reconstruction/
git commit -m "drivers-i386: advance the drvBusMouse ledger after the fix pass"
```

---

### Task 13: README status lines

**Files:**
- Modify: `src/drivers-i386/README:15-20`

**Interfaces:**
- Consumes: the outcome of Tasks 4, 6, 8, 10 and 12 — specifically, for each driver, whether it built and whether its fix pass completed.
- Produces: nothing later tasks consume. This is the last task.

- [ ] **Step 1: Read the current lines and the wording the bus drivers use**

```bash
sed -n '1,22p' src/drivers-i386/README
```

Today the `input` block reads:

```
input
 * drvBusMouse - needs compiled and then tested
 * drvISASerialPort - needs compiled and then tested
 * drvPCParallel - needs compiled and then tested
 * drvPS2Keyboard - needs compiled and then tested
 * drvPS2Mouse - needs compiled and then tested
 * drvSerialPointingDevice - needs compiled and then tested
```

The reconstructed bus drivers use these forms, and the correct one depends on what actually happened:

```
 * drvPCIBus - complete; reconstructed against the reference binary
 * drvPCMCIABus - compiles; reconstructed against the reference binary, fixes applied, not yet tested
 * drvEISABus - crashing; reconstructed against the reference binary, fixes applied, not yet retested
```

- [ ] **Step 2: Update the five lines to match reality**

Since this plan's verification is static only — no boot test — a driver that built clean and whose fix pass completed gets `compiles; reconstructed against the reference binary, fixes applied, not yet tested`. A driver whose build could not be run because the guest was unavailable says so instead. Do not write `complete` for any of the five: none has been booted.

`drvISASerialPort` keeps `needs compiled and then tested` — it is out of scope and gets its own spec.

- [ ] **Step 3: Verify only the intended lines changed**

```bash
git diff --stat src/drivers-i386/README
git diff src/drivers-i386/README
```

Expected: five changed lines inside the `input` block, no other block touched, `drvISASerialPort` unchanged.

- [ ] **Step 4: Commit**

```bash
git add src/drivers-i386/README
git commit -m "drivers-i386: record the input driver reconstruction status"
```
