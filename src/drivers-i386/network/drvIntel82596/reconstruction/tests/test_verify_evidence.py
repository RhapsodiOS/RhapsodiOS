import json
from pathlib import Path
import subprocess
import sys


REPO = Path(__file__).resolve().parents[6]
RECON = REPO / "src/drivers-i386/network/drvIntel82596/reconstruction"
ANALYSIS = REPO / "tools/binrecon/out/intel82596/published/analysis-reference-ida.json"
BINARY = Path(r"C:\Users\raynorpat\Downloads\test\Drivers\i386\Intel82596NetworkDriver.config\Intel82596NetworkDriver_reloc")


def invoke(tmp_path, *, mutate=None):
    source_map = json.loads((RECON / "source-map.json").read_text())
    ledger = json.loads((RECON / "ledger.json").read_text())
    if mutate:
        mutate(source_map, ledger)
    map_path = tmp_path / "source-map.json"
    ledger_path = tmp_path / "ledger.json"
    map_path.write_text(json.dumps(source_map))
    ledger_path.write_text(json.dumps(ledger))
    return subprocess.run(
        [sys.executable, str(RECON / "verify_evidence.py"), "--analysis", str(ANALYSIS),
         "--source-map", str(map_path), "--ledger", str(ledger_path), "--repo-root", str(REPO)],
        cwd=REPO, capture_output=True, text=True,
    )


def test_intact_initial_partition_passes(tmp_path):
    result = invoke(tmp_path)
    assert result.returncode == 0, result.stderr + result.stdout
    assert "86 reference functions" in result.stdout


def test_probe_at_zero_required(tmp_path):
    def remove_probe(source_map, ledger):
        source_map["unmapped"] = [entry for entry in source_map["unmapped"] if entry["address"] != 0]
        ledger["entries"] = [entry for entry in ledger["entries"] if entry["address"] != 0]
    result = invoke(tmp_path, mutate=remove_probe)
    assert result.returncode != 0
    assert "missing reference function at 0x0" in result.stderr


def test_duplicate_address_rejected(tmp_path):
    def duplicate(source_map, ledger):
        ledger["entries"].append(dict(ledger["entries"][0]))
    result = invoke(tmp_path, mutate=duplicate)
    assert result.returncode != 0
    assert "duplicate ledger address" in result.stderr


def test_generated_names_at_expected_addresses(tmp_path):
    def rename_generated(source_map, ledger):
        entry = next(item for item in ledger["entries"] if item["address"] == 0x4228)
        entry["names"] = ["+[Intel82596NetworkDriverKernelServerInstance unexpected]"]
    result = invoke(tmp_path, mutate=rename_generated)
    assert result.returncode != 0
    assert "generated exception identity mismatch at 0x4228" in result.stderr
