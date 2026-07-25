# Intel824X0PCI and Intel82365PCMCIA Binary Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map every function in Apple's shipped `Intel824X0_reloc` and `PCIC_reloc` to our source, record the divergences, then fix them driver by driver.

**Architecture:** Each driver gets a *report pass* (run the three analyzers, build a `source-map.json` partitioning every reference function into mapped/unmapped/disputed/duplicate buckets, disassembly-diff the mapped ones, compare the config tables, write `divergences.md` and `ledger.json`) followed by a separate *fix pass* verified by a guest compile plus string and symbol parity against the reference. Smallest driver first, carried all the way through before the second starts.

**Tech Stack:** Python 3.13.9, binrecon (`tools/binrecon`), IDA Professional 9.2, Ghidra 12.1 on Java 21, angr 9.3.0, pytest 9.1.1, jsonschema 4.26.0. Guest builds use `gnumake` + `pb_makefiles` on the Rhapsody QEMU guest with the repository mounted at `/build/source`.

**Spec:** `docs/superpowers/specs/2026-07-25-intel-bus-driver-binary-reconstruction-design.md`

**Prior art:** `docs/superpowers/plans/2026-07-25-bus-driver-binary-reconstruction.md` did the same job for `drvPCIBus`, `drvPCMCIABus`, and `drvEISABus`. Its conventions are reused unchanged. Read `src/drivers-i386/bus/drvPCMCIABus/reconstruction/divergences.md` before Task 5 — it is the worked example this plan's reports should resemble.

## Global Constraints

- Python is 3.13.9 at `./.venv-binrecon/Scripts/python.exe`. The binrecon README names 3.12; 3.12 is not installed on this host and the pinned dependencies all install and pass on 3.13.9. **Do not change the pins.**
- Every binrecon invocation needs `PYTHONPATH=tools/binrecon` and runs from the repository root.
- **Test baseline is 648 passed, 4 skipped, 0 failed.** Verify with `PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`. Any failure you see is yours.
- IDA `version` must be `9.2`; Ghidra `version` must be `12.1` with a Java 21 `java.exe`. The adapters reject other versions.
- Reference binaries live under `C:\Users\raynorpat\Downloads\test\Drivers\i386` and are **never** committed.
- **Never point a profile's `rebuilt` at the reference.** That is what produced the false `exact-image` pass in the retired `tools/binrecon/out/eisabus/` run. Both profiles here are reference-only: they omit `rebuilt` entirely.
- Architecture is `i386`, endianness `little`, for both profiles.
- `source-map-v1` `reference_sha256` and all hashes use the pattern `^[0-9A-F]{64}$` — **uppercase**.
- `source_path` in a source map must be a canonical repo-relative **POSIX** path: forward slashes only, not absolute, no `.` or `..` parts, no drive letter.
- Every source-map category array must be sorted by `(address, tuple(reference_names))`, and every `reference_names` and `reasons` array must be sorted and unique. The semantic validator rejects otherwise.
- Ledger status vocabulary is exactly: `unexamined`, `signature-confirmed`, `control-flow-confirmed`, `assembly-matched`, `intentional-mismatch`. There is no "fix" state. `rebuilt_sha256` stays `null` throughout.
- A diverging function stays `unexamined` in the report pass and is written up in `divergences.md`. The fix pass advances it. This is the drvPCIBus convention; do not invent a weaker positive status for a function you know diverges.
- Commit messages: short, subsystem-prefixed (`binrecon: `, `Intel824X0PCI: `, `Intel82365PCMCIA: `, `vm: `, `drivers-i386: `), one to two lines, no metadata.
- Fixes touch only code the ledger flags. The single approved exception is the cross-file move in Task 9 Step 4. No other adjacent cleanup or refactoring.

## Reference identities

Recorded here so every task can assert against them rather than re-deriving.

| Driver | Reference path | Size | SHA-256 (uppercase) |
| --- | --- | --- | --- |
| Intel824X0PCI | `C:\Users\raynorpat\Downloads\test\Drivers\i386\Intel824X0.config\Intel824X0_reloc` | 28376 | `2056748F5588CD447F79989689BD6C8B1232A8D7CF2037FD6D4B5E7CDE4998A0` |
| Intel82365PCMCIA | `C:\Users\raynorpat\Downloads\test\Drivers\i386\PCIC.config\PCIC_reloc` | 38700 | `80360707448AF7E4E100CE24993E0728F5DDC688D1D31DA5161478B0BCC3A208` |

## Reference function inventory

`Intel824X0_reloc`, `__TEXT,__text` = 548 bytes, 4 functions:

| Address | Symbol | Size |
| --- | --- | --- |
| 0 | `+[Intel824X0 probe:]` | 64 |
| 64 | `-[Intel824X0 initFromDeviceDescription:]` | 460 |
| 524 | `+[Intel824X0KernelServerInstance kernelServerInstance]` | 12 |
| 536 | `+[Intel824X0Version driverKitVersionForIntel824X0]` | 12 |

`PCIC_reloc`, `__TEXT,__text` = 7548 bytes, 82 functions. Link order groups them by source file:

| Address range | Source file | Notes |
| --- | --- | --- |
| 0–224 | *(absent from our tree)* | `-[PCIC_PCI initFromDeviceDescription:]` |
| 224–1760 | `PCIC.m` | 12 methods, then `_socketIsValid` (1488), `_checkForCirrusChip` (1564), `_setStatusChangeInterrupt` (1684) |
| 1760–2700 | `PCICDebug.m` | `_FindEmptyMemoryRange` (1760), `_setWindow` (1872), `_MapAttributeMemory` (2308), 2 `PCIC(Debug)` methods |
| 2700–2892 | `PCICInternal.m` *or* `PCICSocket.m` | 2 `PCIC(Internal)` methods, then the second `_socketIsValid` (2816) — see spec §2.6 |
| 2892–5368 | `PCICSocket.m` | 23 `PCICSocket` methods |
| 5368–7316 | `PCICWindow.m` | 17 `PCICWindow` methods, then `_setMemoryWindow` (6620), `_setIoWindow` (7084) |
| 7316–7524 | `PCICWindowAttributes.m` | 16 `PCICWindow(Attributes)` methods |
| 7524–7548 | *(build-generated)* | `+[PCICKernelServerInstance kernelServerInstance]`, `+[PCICVersion driverKitVersionForPCIC]` |

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `tools/binrecon/profiles/intel824x0.json` | Intel824X0PCI reference-only profile |
| `tools/binrecon/profiles/intel82365pcmcia.json` | Intel82365PCMCIA reference-only profile |
| `tools/binrecon/parity_check.py` | Compare a rebuilt driver's `__cstring` set and `__text` symbol names against the reference |
| `tools/binrecon/tests/test_parity_check.py` | Tests for the above |
| `src/drivers-i386/bus/Intel824X0PCI/reconstruction/{source-map,ledger}.json`, `divergences.md` | Intel824X0PCI report-pass output |
| `src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/{source-map,ledger}.json`, `divergences.md` | Intel82365PCMCIA report-pass output |
| `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PCIC_PCI.m` | The `PCIC_PCI` class, written from the reference disassembly (Task 9) |

**Modified:**

| Path | Change |
| --- | --- |
| `vm/build-i386-bus-drivers.sh` | Add the two drivers; accept driver-name arguments |
| `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Default.table` | `"Auto Detect_IDs"` → `"Auto Detect IDs"`; add `"Version"` |
| `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Intel824X0.lksproj/Intel824X0.m` | Rewrite `initFromDeviceDescription:` |
| `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCI.table` | Add `"Version"` |
| `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PCIC.m` | Rewrite `initFromDeviceDescription:`; move out the two window functions; drop leading underscores |
| `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PCICWindow.m` | Receive the two window functions; drop the externs |
| `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PCICInternal.h` | Drop the moved prototypes; drop leading underscores |
| `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/{PCICDebug,PCICSocket}.m` | Drop leading underscores |
| `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PB.project` | Register `PCIC_PCI.m` |
| `src/drivers-i386/README` | Update both status lines |

---

### Task 1: Reference-only profiles for both drivers

**Files:**
- Create: `tools/binrecon/profiles/intel824x0.json`
- Create: `tools/binrecon/profiles/intel82365pcmcia.json`

**Interfaces:**
- Consumes: the reference-only profile support added by the prior effort — `profile-v1.json` does not require `rebuilt`, and `profile.py` loads it conditionally.
- Produces: two profile paths that every later task passes to `--profile`.

- [ ] **Step 1: Write the Intel824X0PCI profile**

Create `tools/binrecon/profiles/intel824x0.json`. This is `profiles/pcibus.json` with `name` and `output_dir` changed; copy it verbatim otherwise so the analyzer configuration stays uniform across drivers.

```json
{
  "schema_version": "profile-v1",
  "name": "Intel824X0PCI reconstruction",
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
  "output_dir": "../out/intel824x0"
}
```

- [ ] **Step 2: Write the Intel82365PCMCIA profile**

Create `tools/binrecon/profiles/intel82365pcmcia.json`, identical except for two fields:

```json
{
  "schema_version": "profile-v1",
  "name": "Intel82365PCMCIA reconstruction",
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
  "output_dir": "../out/intel82365pcmcia"
}
```

- [ ] **Step 3: Validate the Intel824X0PCI profile resolves**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/Intel824X0.config/Intel824X0_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/intel824x0.json
```

Expected: exit 0. Prints the reference absolute path, size `28376`, and SHA-256 `2056748F5588CD447F79989689BD6C8B1232A8D7CF2037FD6D4B5E7CDE4998A0`. No rebuilt artifact is reported.

- [ ] **Step 4: Validate the Intel82365PCMCIA profile resolves**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIC.config/PCIC_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/intel82365pcmcia.json
```

Expected: exit 0. Size `38700`, SHA-256 `80360707448AF7E4E100CE24993E0728F5DDC688D1D31DA5161478B0BCC3A208`.

If either prints a different hash, the reference file on disk is not the one this plan was written against. Stop and report it rather than continuing.

- [ ] **Step 5: Commit**

```bash
git add tools/binrecon/profiles/intel824x0.json tools/binrecon/profiles/intel82365pcmcia.json
git commit -m "binrecon: add Intel824X0PCI and Intel82365PCMCIA reference-only profiles"
```

---

### Task 2: String and symbol parity checker

Spec §4.2 checks 2 and 3 run four times (two drivers, baseline and post-fix), so they get a file rather than a repeated shell heredoc.

**Files:**
- Create: `tools/binrecon/parity_check.py`
- Test: `tools/binrecon/tests/test_parity_check.py`

**Interfaces:**
- Consumes: `binrecon.macho.read_macho(path) -> dict`, whose `"sections"` entries carry `{"name", "address", "offset", "size", "permissions", "sha256"}` and whose `"symbols"` entries carry `{"name", "address", "binding", "section"}`. A symbol's `"section"` is `None` for absolute and undefined symbols.
- Produces: `parity_check.compare(reference: Path, rebuilt: Path) -> dict` with the four keys `missing_strings`, `extra_strings`, `missing_symbols`, `extra_symbols`, each a sorted `list[str]`. Tasks 3, 6, and 9 call the module as a script.

- [ ] **Step 1: Write the failing test**

Create `tools/binrecon/tests/test_parity_check.py`. `read_macho` is monkeypatched, following the pattern already used in `tools/binrecon/tests/test_cli.py:529`; the temp files supply the bytes the `__cstring` offsets index into.

```python
from pathlib import Path

import parity_check


def _write(path: Path, payload: bytes) -> Path:
    path.write_bytes(payload)
    return path


def test_compare_reports_reference_strings_and_symbols_our_build_lacks(tmp_path, monkeypatch):
    reference = _write(tmp_path / "reference", b"alpha\x00beta\x00")
    rebuilt = _write(tmp_path / "rebuilt", b"alpha\x00gamma\x00")
    documents = {
        reference: {
            "sections": [{"name": "__TEXT,__cstring", "offset": 0, "size": 11}],
            "symbols": [
                {"name": "_socketIsValid", "section": "__TEXT,__text"},
                {"name": "_IOLog", "section": None},
            ],
        },
        rebuilt: {
            "sections": [{"name": "__TEXT,__cstring", "offset": 0, "size": 12}],
            "symbols": [{"name": "__socketIsValid", "section": "__TEXT,__text"}],
        },
    }
    monkeypatch.setattr("parity_check.read_macho", lambda path: documents[path])

    result = parity_check.compare(reference, rebuilt)

    assert result["missing_strings"] == ["beta"]
    assert result["extra_strings"] == ["gamma"]
    assert result["missing_symbols"] == ["_socketIsValid"]
    assert result["extra_symbols"] == ["__socketIsValid"]


def test_compare_ignores_absolute_and_undefined_symbols(tmp_path, monkeypatch):
    reference = _write(tmp_path / "reference", b"")
    rebuilt = _write(tmp_path / "rebuilt", b"")
    documents = {
        reference: {
            "sections": [],
            "symbols": [{"name": ".objc_class_name_PCIC", "section": None}],
        },
        rebuilt: {"sections": [], "symbols": []},
    }
    monkeypatch.setattr("parity_check.read_macho", lambda path: documents[path])

    assert parity_check.compare(reference, rebuilt) == {
        "missing_strings": [],
        "extra_strings": [],
        "missing_symbols": [],
        "extra_symbols": [],
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_parity_check.py -q
```

Expected: collection error, `ModuleNotFoundError: No module named 'parity_check'`.

- [ ] **Step 3: Write the implementation**

Create `tools/binrecon/parity_check.py`:

```python
"""Compare a rebuilt driver's strings and text symbols against the reference.

Our guest builds are unstripped, so extras on our side are reported separately
and are not findings by themselves. A reference string or symbol our build
lacks is a finding.
"""

import sys
from pathlib import Path

from binrecon.macho import read_macho

CSTRING_SECTION = "__TEXT,__cstring"
TEXT_SECTION = "__TEXT,__text"


def _cstrings(path):
    document = read_macho(path)
    payload = path.read_bytes()
    for section in document["sections"]:
        if section["name"] == CSTRING_SECTION:
            start = section["offset"]
            raw = payload[start:start + section["size"]]
            return {chunk.decode("latin1") for chunk in raw.split(b"\0") if chunk}
    return set()


def _text_symbols(path):
    document = read_macho(path)
    return {
        symbol["name"]
        for symbol in document["symbols"]
        if symbol["section"] == TEXT_SECTION
    }


def compare(reference, rebuilt):
    reference_strings, rebuilt_strings = _cstrings(reference), _cstrings(rebuilt)
    reference_symbols, rebuilt_symbols = _text_symbols(reference), _text_symbols(rebuilt)
    return {
        "missing_strings": sorted(reference_strings - rebuilt_strings),
        "extra_strings": sorted(rebuilt_strings - reference_strings),
        "missing_symbols": sorted(reference_symbols - rebuilt_symbols),
        "extra_symbols": sorted(rebuilt_symbols - reference_symbols),
    }


def main(argv):
    if len(argv) != 3:
        print("usage: parity_check.py REFERENCE REBUILT", file=sys.stderr)
        return 2
    result = compare(Path(argv[1]), Path(argv[2]))
    for key in ("missing_strings", "missing_symbols", "extra_strings", "extra_symbols"):
        print(f"{key} ({len(result[key])}):")
        for item in result[key]:
            print(f"    {item!r}")
    return 1 if result["missing_strings"] or result["missing_symbols"] else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

Exit 1 means the reference has strings or symbols our build lacks. That is a finding to disposition in `divergences.md`, not an automatic task failure — spec §4.2 makes checks 2 and 3 reported, not gated.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_parity_check.py -q
```

Expected: `2 passed`.

- [ ] **Step 5: Confirm the full suite still matches baseline**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: `650 passed, 4 skipped` — the 648-passing baseline plus this task's two.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/parity_check.py tools/binrecon/tests/test_parity_check.py
git commit -m "binrecon: add a string and symbol parity check against a reference binary"
```

---

### Task 3: Guest build script and both baselines

Establishes that each driver built cleanly *before* any source edits, so a pre-existing failure is never misattributed to a fix (spec §4.2). `Intel82365PCMCIA` is marked "needs compiled and then tested" and may never have been built.

**Files:**
- Modify: `vm/build-i386-bus-drivers.sh`

**Interfaces:**
- Consumes: the existing `build_one <name> <dir> <proj>` function in that script.
- Produces: `out/i386/Intel824X0PCI/Intel824X0.config/Intel824X0_reloc` and `out/i386/Intel82365PCMCIA/PCIC.config/PCIC_reloc` on the guest under `/build/out/i386/`, plus the recorded baseline verdict that Tasks 6 and 9 read.

- [ ] **Step 1: Add driver-name argument filtering**

The script currently builds all drivers unconditionally. With five drivers that is wasteful, and the fix passes need to rebuild one driver at a time. In `vm/build-i386-bus-drivers.sh`, replace the fixed invocation block:

```sh
fail=0
# Under set -e, use `|| fail=1` so a failed driver does not abort the script.
build_one PCIBus drvPCIBus PCIBus.drvproj || fail=1
build_one EISABus drvEISABus EISABus.drvproj || fail=1
build_one PCMCIABus drvPCMCIABus PCMCIABus.drvproj || fail=1
```

with a filtered version. `want` returns true when no arguments were given, or when the directory name appears among them:

```sh
# With no arguments, build every driver. Otherwise build only those named,
# by directory name, e.g. `sh build-i386-bus-drivers.sh Intel824X0PCI`.
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
# Under set -e, use `|| fail=1` so a failed driver does not abort the script.
if want drvPCIBus "$@"; then
	build_one PCIBus drvPCIBus PCIBus.drvproj || fail=1
	built="$built drvPCIBus"
fi
if want drvEISABus "$@"; then
	build_one EISABus drvEISABus EISABus.drvproj || fail=1
	built="$built drvEISABus"
fi
if want drvPCMCIABus "$@"; then
	build_one PCMCIABus drvPCMCIABus PCMCIABus.drvproj || fail=1
	built="$built drvPCMCIABus"
fi
if want Intel824X0PCI "$@"; then
	build_one Intel824X0 Intel824X0PCI Intel824X0.drvproj || fail=1
	built="$built Intel824X0PCI"
fi
if want Intel82365PCMCIA "$@"; then
	build_one PCIC Intel82365PCMCIA PCIC.drvproj || fail=1
	built="$built Intel82365PCMCIA"
fi
```

- [ ] **Step 2: Replace the hardcoded closing summary**

The script ends with a `find` and a `file` over the three original drivers. Replace that block:

```sh
echo "======== summary ========"
find "$OUT/drvPCIBus" "$OUT/drvEISABus" "$OUT/drvPCMCIABus" -type f 2>/dev/null | sort || true
file "$OUT/drvPCIBus/PCIBus.config/PCIBus_reloc" \
	"$OUT/drvEISABus/EISABus.config/EISABus_reloc" \
	"$OUT/drvPCMCIABus/PCMCIABus.config/PCMCIABus_reloc" 2>&1 || true
echo "=== bus-drivers done fail=$fail ==="
exit $fail
```

with one driven by what was actually built:

```sh
echo "======== summary ========"
for d in $built; do
	find "$OUT/$d" -type f 2>/dev/null | sort || true
done
for d in $built; do
	find "$OUT/$d" -name '*_reloc' -type f -exec file {} \; 2>&1 || true
done
echo "=== bus-drivers done fail=$fail built:$built ==="
exit $fail
```

- [ ] **Step 3: Copy the PCIC DriverInfo alongside the tables**

`PCIC.config` in the reference ships a `DriverInfo` file and our `PCIC.drvproj` has one, but `build_one` only copies `*.table` and `English.lproj`. Inside `build_one`, immediately after the `for f in "$src/$proj"/*.table` loop's closing `done`, add:

```sh
		if [ -f "$src/$proj/DriverInfo" ]; then
			cp -p "$src/$proj/DriverInfo" "$dst/"
		fi
```

- [ ] **Step 4: Build both baselines on the guest**

The repository is mounted at `/build/source` on the Rhapsody guest. Run:

```sh
sh /build/source/vm/build-i386-bus-drivers.sh Intel824X0PCI Intel82365PCMCIA
```

Expected: `Intel824X0_reloc` and `PCIC_reloc` staged under `/build/out/i386/`. Capture the full output — it is the baseline record.

**If either driver fails to build, stop.** Repairing that breakage is its own commit, made before any divergence fix, per spec §4.2. Record what failed and why in that commit message.

**If the guest is unavailable, stop and report it.** Tasks 4, 5, 7, and 8 (both report passes) do not need the guest and can proceed; Tasks 6 and 9 (both fix passes) block. Do not fabricate a baseline.

- [ ] **Step 5: Record the baseline parity for each driver**

For each driver, with the staged `_reloc` copied back to the host under `out/i386/`:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/Intel824X0.config/Intel824X0_reloc" \
  out/i386/Intel824X0PCI/Intel824X0.config/Intel824X0_reloc
```

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIC.config/PCIC_reloc" \
  out/i386/Intel82365PCMCIA/PCIC.config/PCIC_reloc
```

Expected for Intel824X0PCI: a large `missing_strings` list including `Intel 82424ZX Host-Bridge\n` and `Intel 82434%cX Host-Bridge (step A-%d)\n`, confirming spec §2.2 against the real build rather than against source reading alone. Save both outputs; Tasks 5 and 8 quote them in `divergences.md`, and Tasks 6 and 9 compare against them.

- [ ] **Step 6: Commit**

```bash
git add vm/build-i386-bus-drivers.sh
git commit -m "vm: build Intel824X0PCI and Intel82365PCMCIA, accept driver-name arguments

Adds the two drivers to the bus build script and lets it build a subset."
```

---

### Task 4: Intel824X0PCI analyzer run

**Files:**
- Creates only gitignored output under `tools/binrecon/out/intel824x0/`.

**Interfaces:**
- Consumes: `tools/binrecon/profiles/intel824x0.json` from Task 1.
- Produces: `tools/binrecon/out/intel824x0/published/analysis-reference-{ida,ghidra,angr}.json` and `consensus-reference.json`, which Task 5 reads.

- [ ] **Step 1: Run the analyzers**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/Intel824X0.config/Intel824X0_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/intel824x0.json
```

Expected: **exit code 1**, with `run-summary.json` showing `"complete": true`, `"rebuilt_sha256": null`, `"comparisons": []`, and `"acceptance": {"passed": false, ...}`.

Exit 1 is the correct outcome for every reference-only run and is not a failure. `runner.py:259` computes `expected_pass = bool(comparisons) and all(...)`, so with nothing compared the acceptance is `false`, and line 262 *enforces* that it stay `false` — the tool refuses to report acceptance as passed when no comparison happened.

**The real gate for this task** is: `"complete": true`, a `published/` directory holding the three `analysis-reference-*.json` files plus `consensus-reference.json`, and `"reference"` non-null for all three analyzers. Judge success on those, not the exit code.

If Ghidra's Mach-O loader rejects the input, the adapter falls back to deterministic raw i386 import — expected, not a failure. If a run times out, the summary is marked `"complete": false`; fix the cause and re-run rather than proceeding.

**Do not launch `analyze` from a subagent that then exits** — the run is a long-lived child process and dies with its parent. Run it as a detached background task owned by the session.

- [ ] **Step 2: Confirm the published output and that nothing is tracked**

```bash
ls tools/binrecon/out/intel824x0/published/
git status --porcelain tools/binrecon/out
```

Expected: the four JSON files; `git status` prints nothing, confirming the `.gitignore:17` rule holds.

- [ ] **Step 3: Confirm the analyzers found all four functions**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
for analyzer in ('ida', 'ghidra', 'angr'):
    path = f'tools/binrecon/out/intel824x0/published/analysis-reference-{analyzer}.json'
    functions = json.load(open(path))['functions']
    print(analyzer, len(functions), sorted((f['address'], f['size']) for f in functions))
"
```

Expected from IDA and Ghidra: 4 functions at addresses 0, 64, 524, 536, with sizes 64, 460, 12, 12. angr's `CFGFast` may report fewer or differ on sizes; that is recorded, not corrected. Any IDA/Ghidra disagreement on a boundary goes to `boundary_disputed` in Task 5.

There is no commit for this task — its entire output is gitignored.

---

### Task 5: Intel824X0PCI report pass

**Files:**
- Create: `src/drivers-i386/bus/Intel824X0PCI/reconstruction/source-map.json`
- Create: `src/drivers-i386/bus/Intel824X0PCI/reconstruction/ledger.json`
- Create: `src/drivers-i386/bus/Intel824X0PCI/reconstruction/divergences.md`

**Interfaces:**
- Consumes: the analyses from Task 4 and the baseline parity output from Task 3 Step 5.
- Produces: a validated source map plus a ledger entry for every function, and the finding list Task 6 works through.

- [ ] **Step 1: Generate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/intel824x0/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/Intel824X0.config/Intel824X0_reloc" \
  --source-dir src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Intel824X0.lksproj \
  --repo-root . \
  --output src/drivers-i386/bus/Intel824X0PCI/reconstruction/source-map.json
```

Expected: exit 0. A non-zero exit means the semantic validator rejected the document — read the `SemanticValidationError` message, which names the exact failing constraint.

- [ ] **Step 2: Review the buckets**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/drivers-i386/bus/Intel824X0PCI/reconstruction/source-map.json'))
for key in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    print(key, len(d[key]))
for entry in d['unmapped']:
    print('  unmapped:', entry['reference_names'])
"
```

Expected: `mapped` 2 (`+[Intel824X0 probe:]`, `-[Intel824X0 initFromDeviceDescription:]`), `unmapped` 2 (`+[Intel824X0KernelServerInstance kernelServerInstance]`, `+[Intel824X0Version driverKitVersionForIntel824X0]`), both other buckets 0. Anything else unmapped is a finding for Step 5.

- [ ] **Step 3: Disassembly-diff both mapped functions**

The analyses contain **disassembly, not C decompilation**. Each function carries `instructions` (address, `bytes`, `mnemonic`, `operands`, `normalized_operands`, `relocations`), `blocks` for control flow, and `calls` with resolved targets. Ghidra additionally exposes `extensions.ghidra.decompiler_pcode`, which is p-code IR rather than C. Compare at the instruction level — it is more precise than decompiled C, not less.

Reading disassembly against Objective-C source: a method's arguments arrive on the stack (`[ebp+self]`, `[ebp+arg]`), instance variables load as fixed offsets off `self`, and message sends appear as `calls` to `objc_msgSend` or `objc_msgSendSuper`.

`+[Intel824X0 probe:]` (64 bytes) is expected to match: alloc, `initFromDeviceDescription:`, nil test, return the BOOL.

`-[Intel824X0 initFromDeviceDescription:]` (460 bytes) is the finding. Anchor the comparison on the reference `__cstring` contents, which are, in section order:

```
Intel824X0
Other
%s: Detected
Intel 82424ZX Host-Bridge\n
Intel 82434%cX Host-Bridge (step A-%d)\n
Intel
Host-Bridge\n
%s: Disabling PCI-to-Memory write posting.\n
%s: PCI-to-Memory write posting disabled by BIOS.\n
```

Read the `calls` list and the relocations against `__cstring` to establish which string each `IOLog` site uses and under what condition. Determine specifically: how the two device IDs are tested, how the `%c` in `Intel 82434%cX` is computed (it selects 82434LX from 82434NX), how `step A-%d` is derived from the revision register, which register the write-posting bit lives in and at what bit position, and what the fall-through path does for an Intel device that is neither ID — the `Intel ` and `Host-Bridge\n` fragments suggest a composed name rather than a single format string.

Do not begin rewriting here. This step produces the finding; Task 6 applies it.

- [ ] **Step 4: Compare the config table**

```bash
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/Intel824X0.config/Default.table" \
     src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Default.table
```

Expected differences: our `"Auto Detect_IDs"` versus the reference `"Auto Detect IDs"`; our file missing `"Version" = "5.01";`; the reference carrying a `"Driver Version"` line that is build-generated and correctly absent from ours. Record the first two as findings and the third as accepted.

- [ ] **Step 5: Write `divergences.md`**

Create `src/drivers-i386/bus/Intel824X0PCI/reconstruction/divergences.md`. Follow the structure of `src/drivers-i386/bus/drvPCMCIABus/reconstruction/divergences.md` — read it first. Required sections:

```markdown
# Intel824X0PCI divergences

Reference: `Intel824X0_reloc`, SHA-256 `2056748F5588CD447F79989689BD6C8B1232A8D7CF2037FD6D4B5E7CDE4998A0`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0

## Baseline build

<verdict from Task 3 Step 4, with the staged artifact path and size, or the
recorded failure>

## Baseline parity

<the parity_check.py output from Task 3 Step 5, verbatim>

## Summary

| Bucket | Count |
| --- | --- |
| mapped | N |
| unmapped | N |
| duplicate_candidates | N |
| boundary_disputed | N |

State how many functions were examined at instruction level versus
control-flow level versus not examined.

## Unmapped: build-generated

`+[Intel824X0KernelServerInstance kernelServerInstance]` and
`+[Intel824X0Version driverKitVersionForIntel824X0]` — emitted by the Kernel
Server project type and `Load_Commands.sect`, not written by hand. Accepted.

## Finding 1: <name> at 0x<address>

**Source:** `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Intel824X0.lksproj/<file>:<line>`

**Reference behaviour**

<disassembly excerpt with the reasoning that reads it>

**Our source**

<source excerpt>

**Difference:** <what differs, concretely>

**Disposition:** fix | accept

**Rationale:** <why>

## Finding N: Default.table auto-detect key

...

## README status

`src/drivers-i386/README` calls this driver "complete". State whether the
evidence supports that, and what the corrected wording should be.
```

- [ ] **Step 6: Create the ledger**

Every one of the four functions needs an entry. Matching functions get the status Step 3 established; diverging ones stay `unexamined`. The two build-generated functions are accepted divergences, which require both a reason and a reviewer:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/intel824x0.json \
  --ledger src/drivers-i386/bus/Intel824X0PCI/reconstruction/ledger.json \
  --address 0x20c --status intentional-mismatch \
  --reason "build-generated kernel server glue, not present in source" \
  --reviewer "<your name>"
```

`0x20c` is 524, the `kernelServerInstance` address; repeat for `0x218` (536). For a function resolved to a source site, pass `--source-path` and `--source-line` together:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/intel824x0.json \
  --ledger src/drivers-i386/bus/Intel824X0PCI/reconstruction/ledger.json \
  --address 0x0 --status assembly-matched \
  --source-path src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Intel824X0.lksproj/Intel824X0.m \
  --source-line <the source_line the source map recorded for this address>
```

Take `--source-path` and `--source-line` from the matching `mapped` entry in
`source-map.json` rather than reading them off the file yourself; the loader in
Step 7 checks them against the same bounds.

- [ ] **Step 7: Verify the source map against the reference analysis**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/intel824x0/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drivers-i386/bus/Intel824X0PCI/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`. This enforces the complete function partition, names, sizes, and source-line bounds.

- [ ] **Step 8: Commit**

```bash
git add src/drivers-i386/bus/Intel824X0PCI/reconstruction
git commit -m "Intel824X0PCI: add reconstruction source map, ledger and divergence report"
```

---

### Task 6: Intel824X0PCI fix pass

**Files:**
- Modify: `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Default.table`
- Modify: `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Intel824X0.lksproj/Intel824X0.m`
- Modify: `src/drivers-i386/bus/Intel824X0PCI/reconstruction/{ledger.json,divergences.md}`

**Interfaces:**
- Consumes: the findings from Task 5 and the build script from Task 3.
- Produces: source matching the reference, advanced ledger statuses, and a recorded outcome per finding.

- [ ] **Step 1: Confirm the baseline build passed**

Re-read the `## Baseline build` section of `divergences.md`. If it records a failure, stop and fix the build breakage as its own commit first.

- [ ] **Step 2: Fix the config table**

In `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Default.table`, change `"Auto Detect_IDs"` to `"Auto Detect IDs"` and add the `"Version"` line the reference carries. The result must read:

```
"Title" = "Intel824X0";
"Class Names" = "Intel824X0";
"Family" = "Other";
"Instance" = "0";
"Version" = "5.01";
"Server Name" = "Intel824X0";
"Bus Type" = "PCI";
"Location" = "";
"Auto Detect IDs" = "0x04838086 0x04A38086";
"Boot Driver" = "Yes";
"Help File" = "Intel_824X0_PCI_Host_Bridge.rtfd";
"Server Name" = "Intel824X0";
```

Do not add `"Driver Version"` — it is build-generated. The duplicated `"Server Name"` is present in the reference; leave it.

- [ ] **Step 3: Rewrite `initFromDeviceDescription:`**

Apply Task 5 Step 3's finding. The 82424ZX / 82434LX / 82434NX identification, the `step A-%d` decode, and the two write-posting messages replace our 82440FX / 82443FX / "C-%d stepping" invention. Preserve the existing Apple license header and the file's `#import` block; match the surrounding comment density.

Update the register `#define` block to describe what the reference actually reads. Delete the `INTEL_82440FX_DEVID` and `INTEL_82443FX_DEVID` names and their comments — our changes are what made them wrong, so removing them is in scope.

**Size is the check on overfitting.** The reference function is 460 bytes. If the rebuilt one is materially larger, structure was invented again; re-read the disassembly rather than adding code.

- [ ] **Step 4: Rebuild**

```sh
sh /build/source/vm/build-i386-bus-drivers.sh Intel824X0PCI
```

Expected: exit 0 and `Intel824X0_reloc` staged. New warnings relative to the Task 3 baseline are reviewed but do not gate.

- [ ] **Step 5: Check string and symbol parity**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/Intel824X0.config/Intel824X0_reloc" \
  out/i386/Intel824X0PCI/Intel824X0.config/Intel824X0_reloc
```

Expected: `missing_strings` and `missing_symbols` both empty, versus the long `missing_strings` list Task 3 Step 5 recorded. If any reference string is still missing, the rewrite is incomplete — the format strings are the most direct evidence of behaviour we have. Extras are expected: our build is unstripped.

- [ ] **Step 6: Check the rebuilt function size against the reference**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
for label, path in (
    ('reference', r'C:\Users\raynorpat\Downloads\test\Drivers\i386\Intel824X0.config\Intel824X0_reloc'),
    ('rebuilt', 'out/i386/Intel824X0PCI/Intel824X0.config/Intel824X0_reloc'),
):
    document = read_macho(Path(path))
    text = [s for s in document['symbols'] if s['section'] == '__TEXT,__text']
    for symbol in sorted(text, key=lambda s: s['address']):
        print(label, symbol['address'], symbol['name'])
"
```

Expected: the rebuilt `-[Intel824X0 initFromDeviceDescription:]` spans roughly 460 bytes, judged by the gap to the next symbol. A materially larger span is a finding to resolve before committing, not something to accept.

- [ ] **Step 7: Advance the ledger**

For each fixed function, set the status to the level the change now supports:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/intel824x0.json \
  --ledger src/drivers-i386/bus/Intel824X0PCI/reconstruction/ledger.json \
  --address 0x40 --status control-flow-confirmed \
  --source-path src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Intel824X0.lksproj/Intel824X0.m \
  --source-line <line of the rewritten method>
```

`0x40` is 64, the `initFromDeviceDescription:` address. `--source-path` and `--source-line` must be supplied together.

- [ ] **Step 8: Record the outcome**

In `divergences.md`, append to each finding an `**Outcome:**` line stating what changed and the new ledger status. Update the `## Baseline parity` section with a `## Post-fix parity` section holding the Step 5 output.

- [ ] **Step 9: Commit**

```bash
git add src/drivers-i386/bus/Intel824X0PCI
git commit -m "Intel824X0PCI: identify the 82424ZX and 82434LX/NX as the reference does

Replaces the invented 82440FX/82443FX identification and fixes the misspelled
auto-detect key that stopped the driver matching any device."
```

---

### Task 7: Intel82365PCMCIA analyzer run

**Files:**
- Creates only gitignored output under `tools/binrecon/out/intel82365pcmcia/`.

**Interfaces:**
- Consumes: `tools/binrecon/profiles/intel82365pcmcia.json` from Task 1.
- Produces: `tools/binrecon/out/intel82365pcmcia/published/analysis-reference-{ida,ghidra,angr}.json` and `consensus-reference.json`, which Task 8 reads.

- [ ] **Step 1: Run the analyzers**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIC.config/PCIC_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/intel82365pcmcia.json
```

Expected: **exit code 1**, `"complete": true`, `"rebuilt_sha256": null`, `"comparisons": []`. Same reasoning as Task 4 Step 1 — judge on `"complete": true` plus a populated `published/`, not on the exit code. Run it detached; it dies with its parent otherwise.

- [ ] **Step 2: Confirm the published output and that nothing is tracked**

```bash
ls tools/binrecon/out/intel82365pcmcia/published/
git status --porcelain tools/binrecon/out
```

Expected: the four JSON files; `git status` prints nothing.

- [ ] **Step 3: Confirm the analyzers agree on the function count**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
counts = {}
for analyzer in ('ida', 'ghidra', 'angr'):
    path = f'tools/binrecon/out/intel82365pcmcia/published/analysis-reference-{analyzer}.json'
    counts[analyzer] = {(f['address'], f['size']) for f in json.load(open(path))['functions']}
    print(analyzer, len(counts[analyzer]))
print('IDA-only:', sorted(counts['ida'] - counts['ghidra']))
print('Ghidra-only:', sorted(counts['ghidra'] - counts['ida']))
"
```

Expected: IDA and Ghidra each report 82 functions matching the symbol table. Every entry printed under `IDA-only` or `Ghidra-only` is a boundary disagreement and belongs in `boundary_disputed` in Task 8 — preserved, not voted on. angr's `CFGFast` may differ; that is recorded, not corrected.

There is no commit for this task — its entire output is gitignored.

---

### Task 8: Intel82365PCMCIA report pass

The large report pass: 82 functions across seven source files, one class absent from our tree, and a known file-placement divergence.

**Files:**
- Create: `src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/source-map.json`
- Create: `src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/ledger.json`
- Create: `src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/divergences.md`

**Interfaces:**
- Consumes: the analyses from Task 7 and the baseline parity output from Task 3 Step 5.
- Produces: a validated source map, a ledger entry for every function, the finding list Task 9 works through, and the `PCIC_PCI` go/no-go.

- [ ] **Step 1: Generate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/intel82365pcmcia/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIC.config/PCIC_reloc" \
  --source-dir src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj \
  --repo-root . \
  --output src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/source-map.json
```

Expected: exit 0.

- [ ] **Step 2: Review the buckets and resolve the residue by hand**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/source-map.json'))
for key in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    print(key, len(d[key]))
for key in ('unmapped', 'duplicate_candidates', 'boundary_disputed'):
    for entry in d[key]:
        print(f'  {key}:', entry['address'], entry['reference_names'])
"
```

Expected `unmapped`, all accounted for by the spec:
- `-[PCIC_PCI initFromDeviceDescription:]` at 0 — genuinely absent (§2.1)
- `+[PCICKernelServerInstance kernelServerInstance]` at 7524 and `+[PCICVersion driverKitVersionForPCIC]` at 7536 — build-generated (§2.8)

The eight functions in the underscore group (§2.5) will likely land in `unmapped` too, because the builder matches on name and our source's C identifiers carry an extra leading underscore. That is naming divergence, not missing code — move each to `mapped` with the correct `source_path`/`source_line` and document the pattern in Step 6. The group is `_socketIsValid`, `_checkForCirrusChip`, `_setStatusChangeInterrupt`, `_FindEmptyMemoryRange`, `_setWindow`, `_MapAttributeMemory`, `_setMemoryWindow`, `_setIoWindow`.

The two `_socketIsValid` at 1488 and 2816 belong in `duplicate_candidates` until Step 4 resolves them.

After hand-editing, keep every array sorted by `(address, tuple(reference_names))` and every `reference_names` list sorted and unique, then re-run Step 8's validation.

- [ ] **Step 3: Disassembly-diff the mapped functions, one source file at a time**

Same technique as Task 5 Step 3. Work in link order, which is also source-file order: `PCIC.m`, `PCICDebug.m`, `PCICInternal.m`, `PCICSocket.m`, `PCICWindow.m`, `PCICWindowAttributes.m`.

Priorities, given 82 functions:

1. `-[PCIC initFromDeviceDescription:]` (292–932, 640 bytes) — the known invention (§2.2). The reference has three log strings in this method (`PCIC: No device at base address 0x%04x`, `PCIC: couldn't enable interrupts`, `PCIC: couldn't start IO thread`); our source has six others it does not. Establish what the reference actually does on failure, and where `No device at base address 0x%04x` is emitted — our source has no equivalent.
2. The hardware-facing helpers: `_socketIsValid`, `_checkForCirrusChip`, `_setStatusChangeInterrupt`, `_setMemoryWindow`, `_setIoWindow`. These are register-level code where a wrong port offset or bit position is a silent hardware failure. Instruction level, all of them.
3. `PCICSocket` and `PCICWindow` accessors — many are 12–16 bytes and resolve at a glance. Instance-variable offsets must match the `@interface` declaration order; a mismatch there is a genuine ABI divergence and exactly what this pass exists to catch.
4. `PCICWindowAttributes.m` — 16 methods, most 12 bytes, each returning a constant. Confirm the constants.
5. `PCICDebug.m` — expected to match; §2.7 records its four log strings as exact. Control-flow level is sufficient unless something disagrees.

Record what you examined at which level. The `divergences.md` summary states it explicitly, as drvPCMCIABus's does.

- [ ] **Step 4: Resolve the second `_socketIsValid`**

Spec §2.6: the copy at 2816 sits between `-[PCIC(Internal) writeRegister:socket:value:]` (2748) and `-[PCICSocket initWithAdapter:socketNumber:]` (2892), so link order alone cannot say whether it ends `PCICInternal.m` or begins `PCICSocket.m`.

Resolve it from evidence, not preference. Compare its instruction stream against the copy at 1488 — if they are byte-identical it is a duplicated static, and the question is only which file holds the second copy. Then check the `calls` lists: whichever of the two neighbouring functions calls it, and via a direct near call rather than through a symbol stub, shares its object file.

If the evidence does not decide, leave the entry in `duplicate_candidates` and say so in `divergences.md`. Do not guess.

- [ ] **Step 5: Compare the config table**

```bash
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIC.config/PCI.table" \
     src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCI.table
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIC.config/DriverInfo" \
     src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/DriverInfo
```

Expected in `PCI.table`: ours missing `"Version" = "5.00";` (a finding) and missing `"Driver Version"` (build-generated, accepted). Record whatever `DriverInfo` shows.

- [ ] **Step 6: Write `divergences.md`**

Create `src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/divergences.md`, same structure as Task 5 Step 5, with the header `# Intel82365PCMCIA divergences` and SHA-256 `80360707448AF7E4E100CE24993E0728F5DDC688D1D31DA5161478B0BCC3A208`.

Four sections are required beyond the per-finding ones:

**`## Naming divergence`** — the eight-function underscore group from Step 2, with the evidence that it is naming rather than absence, following the precedent in `drvPCMCIABus/reconstruction/divergences.md`.

**`## File placement`** — `_setMemoryWindow` (6620) and `_setIoWindow` (7084) sit inside `PCICWindow.m`'s address run; our source defines them in `PCIC.m`. The disposition is **fix** — approved in the spec, applied in Task 9 Step 4.

**`## PCIC_PCI: go/no-go`** — the class is absent from our tree (§2.1). State whether the reference disassembly of the 224-byte `-[PCIC_PCI initFromDeviceDescription:]` is complete enough to implement from. Its log string is `PCIC: PCMCIA->PCI Bus Bridge Detected (Dev=%d, Bus=%d)` and `PCI.table` gives its match as `"Auto Detect IDs" = "0x11001013"` (Cirrus Logic PD6832). If it is implementable, say so and Task 9 Step 3 writes it. If it is not, say why, mark it `intentional-mismatch` with a reason and reviewer, and record that it splits into its own spec — the pattern the prior effort used for `drvEISABus`'s `PnPArgStack`. **This is the one decision in the plan that can legitimately reduce Task 9's scope.**

**`## README status`** — this driver is marked "needs compiled and then tested". State what the baseline build in Task 3 actually showed.

- [ ] **Step 7: Create the ledger**

Every one of the 82 functions needs an entry. Matching functions get the status Step 3 established; diverging ones stay `unexamined`; build-generated glue gets `intentional-mismatch` with a reason and reviewer. Commands are as in Task 5 Step 6, with `--profile tools/binrecon/profiles/intel82365pcmcia.json` and `--ledger src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/ledger.json`.

- [ ] **Step 8: Verify the source map against the reference analysis**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/intel82365pcmcia/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`.

- [ ] **Step 9: Confirm every function has a ledger entry**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
ledger = json.load(open('src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/ledger.json'))
analysis = json.load(open('tools/binrecon/out/intel82365pcmcia/published/analysis-reference-ida.json'))
entries = {e['address'] for e in ledger['entries']}
functions = {f['address'] for f in analysis['functions']}
print('functions', len(functions), 'ledger', len(entries))
print('missing from ledger:', sorted(functions - entries))
"
```

Expected: equal counts and an empty missing list.

- [ ] **Step 10: Commit**

```bash
git add src/drivers-i386/bus/Intel82365PCMCIA/reconstruction
git commit -m "Intel82365PCMCIA: add reconstruction source map, ledger and divergence report"
```

---

### Task 9: Intel82365PCMCIA fix pass

**Files:**
- Create: `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PCIC_PCI.m` (only if Task 8 Step 6 returned go)
- Modify: `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCI.table`
- Modify: `.../PCIC.lksproj/{PCIC.m,PCICDebug.m,PCICInternal.h,PCICSocket.m,PCICWindow.m,PB.project}`
- Modify: `src/drivers-i386/bus/Intel82365PCMCIA/reconstruction/{ledger.json,divergences.md}`

**Interfaces:**
- Consumes: the findings and the `PCIC_PCI` go/no-go from Task 8, and the build script from Task 3.
- Produces: source matching the reference, advanced ledger statuses, and a recorded outcome per finding.

Each of Steps 2 through 6 is a separate commit. They are independent, and a reviewer should be able to reject one without rejecting the rest.

- [ ] **Step 1: Confirm the baseline build passed**

Re-read the `## Baseline build` section of `divergences.md`. If it records a failure, stop and fix the build breakage as its own commit first.

- [ ] **Step 2: Fix the config table and commit**

Add `"Version" = "5.00";` to `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCI.table`, positioned as in the reference. Do not add `"Driver Version"`.

```bash
git add src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCI.table
git commit -m "Intel82365PCMCIA: add the Version line the reference PCI.table carries"
```

- [ ] **Step 3: Write `PCIC_PCI` and commit**

Skip this step entirely if Task 8 Step 6 returned no-go; the ledger entry is already `intentional-mismatch` and the class becomes its own spec.

Otherwise create `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PCIC_PCI.m` implementing `-[PCIC_PCI initFromDeviceDescription:]` from the reference disassembly, per Task 8's finding. Constraints:

- The class subclasses `PCIC`; `.objc_class_name_PCIC` is referenced from the reference's `PCIC_PCI` object.
- Its one log string is `PCIC: PCMCIA->PCI Bus Bridge Detected (Dev=%d, Bus=%d)`, so it reads the PCI device and bus numbers and logs both.
- The reference function is 224 bytes. Materially larger means invented structure.
- Carry the same Apple license header as the sibling files.

Register the new file in `PCIC.lksproj/PB.project` under the same key the other `.m` files use, so `pb_makefiles` compiles it.

```bash
git add src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PCIC_PCI.m src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PB.project
git commit -m "Intel82365PCMCIA: add the PCIC_PCI bridge class the reference defines

PCI.table already names PCIC_PCI as its driver class; the implementation was
missing from our tree."
```

- [ ] **Step 4: Move the two window functions and commit**

Move `setIoWindow` and `setMemoryWindow` from `PCIC.m` (currently at lines 452 and 496) into `PCICWindow.m`, placing them after `-[PCICWindow set16Bit:]` and before the end of the file, matching the reference's 6620/7084 ordering. Then:

- Delete the two `extern` declarations at `PCICWindow.m:38-39`.
- Delete the two prototypes at `PCICInternal.h:40-41`.
- Make both functions `static`. Both reference symbols have **local** binding, and nothing outside `PCICWindow.m` calls them once the move is done.
- `-[PCICWindow setMapWithSize:systemAddress:cardAddress:]` calls both at `PCICWindow.m:258` and `:261`, which is *above* their new position at the end of the file. Add `static` forward declarations near the top of `PCICWindow.m`, in place of the two deleted `extern` lines, so the calls still see a prototype.

This is the one approved cross-file change. Do not clean up anything else in either file while you are in there.

```bash
git add src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj
git commit -m "Intel82365PCMCIA: move setIoWindow and setMemoryWindow into PCICWindow.m

Restores the file boundaries the reference link order shows."
```

- [ ] **Step 5: Drop the leading underscores and commit**

Rename all eight C functions so the compiled symbols match Apple's, per §2.5. Our source declares `_socketIsValid`, which compiles to `__socketIsValid`; the reference symbol is `_socketIsValid`, so the C identifier must be `socketIsValid`.

| Our identifier | Correct identifier |
| --- | --- |
| `_socketIsValid` | `socketIsValid` |
| `_checkForCirrusChip` | `checkForCirrusChip` |
| `_setStatusChangeInterrupt` | `setStatusChangeInterrupt` |
| `_FindEmptyMemoryRange` | `FindEmptyMemoryRange` |
| `_setWindow` | `setWindow` |
| `_MapAttributeMemory` | `MapAttributeMemory` |
| `_setMemoryWindow` | `setMemoryWindow` |
| `_setIoWindow` | `setIoWindow` |

Every definition, prototype, and call site across `PCIC.m`, `PCICDebug.m`, `PCICInternal.h`, `PCICSocket.m`, and `PCICWindow.m` changes together.

**One linkage change belongs with the renames.** Every helper in the table above has **local** binding in the reference except `_MapAttributeMemory`, which is **external**. Our `PCICDebug.m:87` declares it `static`. Drop the `static` so its linkage matches, and add a prototype for it to `PCICInternal.h` alongside the ones that stay. The other seven keep `static`.

Verify no old name is left:

```bash
grep -rn "_socketIsValid\|_checkForCirrusChip\|_setStatusChangeInterrupt\|_FindEmptyMemoryRange\|_setWindow\|_MapAttributeMemory\|_setMemoryWindow\|_setIoWindow" src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/
```

Expected: no output.

```bash
git add src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj
git commit -m "Intel82365PCMCIA: match Apple's symbol names for the internal helpers"
```

- [ ] **Step 6: Rewrite `-[PCIC initFromDeviceDescription:]` and apply the remaining findings, then commit**

Apply Task 8's findings in `divergences.md` order, one at a time, changing only the lines each finding names. The largest is `-[PCIC initFromDeviceDescription:]`: the reference is 640 bytes with three log strings, ours has six the reference lacks.

```bash
git add src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj
git commit -m "Intel82365PCMCIA: align the driver sources with the reference binary

Applies the divergences confirmed by the reconstruction report pass."
```

- [ ] **Step 7: Rebuild**

```sh
sh /build/source/vm/build-i386-bus-drivers.sh Intel82365PCMCIA
```

Expected: exit 0 and `PCIC_reloc` staged. New warnings relative to the Task 3 baseline are reviewed but do not gate.

- [ ] **Step 8: Check string and symbol parity**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIC.config/PCIC_reloc" \
  out/i386/Intel82365PCMCIA/PCIC.config/PCIC_reloc
```

Expected: `missing_symbols` empty — this is the direct test that Step 5's renames landed and that `PCIC_PCI` compiled. `missing_strings` empty unless Task 8 Step 6 returned no-go, in which case `PCIC: PCMCIA->PCI Bus Bridge Detected (Dev=%d, Bus=%d)` is legitimately still missing; note that explicitly rather than treating it as a pass. Extras are expected: our build is unstripped.

- [ ] **Step 9: Advance the ledger**

For each fixed function set the status to the level the change now supports, as in Task 6 Step 7, with this driver's profile and ledger paths.

- [ ] **Step 10: Record the outcome and commit**

In `divergences.md`, append an `**Outcome:**` line to each finding and add a `## Post-fix parity` section holding the Step 8 output.

```bash
git add src/drivers-i386/bus/Intel82365PCMCIA/reconstruction
git commit -m "Intel82365PCMCIA: record fix-pass outcomes and post-fix parity"
```

---

### Task 10: Update the driver status README

**Files:**
- Modify: `src/drivers-i386/README`

**Interfaces:**
- Consumes: the `## README status` sections of both `divergences.md` files.
- Produces: status lines that match the evidence.

- [ ] **Step 1: Rewrite both status lines**

In `src/drivers-i386/README`, the `bus` block currently reads:

```
 * Intel824X0PCI - complete
 * Intel82365PCMCIA - needs compiled and then tested
```

Replace both with wording matching the three drivers above them, which read "reconstructed against the reference binary, fixes applied, not yet tested". Use the actual outcome each `divergences.md` recorded — including, for Intel82365PCMCIA, whether `PCIC_PCI` was written or deferred. Do not claim testing that did not happen: no boot test is in scope.

- [ ] **Step 2: Commit**

```bash
git add src/drivers-i386/README
git commit -m "drivers-i386: update Intel824X0PCI and Intel82365PCMCIA status

Both are now reconstructed against the reference binaries."
```

---

## Verification summary

| Gate | Where | Command |
| --- | --- | --- |
| Profiles resolve | Task 1 | `binrecon validate --profile …` |
| Test suite unbroken | Task 2 | `pytest tools/binrecon/tests -q` → 650 passed, 4 skipped |
| Baseline builds recorded | Task 3 | `sh /build/source/vm/build-i386-bus-drivers.sh Intel824X0PCI Intel82365PCMCIA` |
| Analyses complete | Tasks 4, 7 | `"complete": true` plus a populated `published/` |
| Source maps valid | Tasks 5, 8 | `load_source_map(..., reference_analysis=..., repo_root=...)` |
| Every function ledgered | Task 8 | address-set difference is empty |
| Fix passes compile | Tasks 6, 9 | build script exits 0, `_reloc` produced |
| String parity | Tasks 6, 9 | `parity_check.py` → `missing_strings` empty |
| Symbol parity | Tasks 6, 9 | `parity_check.py` → `missing_symbols` empty |
| No overfitting | Task 6 | rebuilt `initFromDeviceDescription:` ≈ 460 bytes |
