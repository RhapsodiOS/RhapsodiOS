import json
from pathlib import Path
import subprocess
import sys

_SCRIPT = Path(__file__).resolve().parents[1] / "bucket_functions.py"


def test_buckets_reconcile_against_a_synthetic_analysis_and_source_map(tmp_path):
    # One function per bucket, chosen so a silently different reconstruction
    # (e.g. one that dumps everything into a single bucket) would still
    # reconcile but would not match these per-bucket counts.
    analysis = {
        "functions": [
            {"address": 0, "names": ["start"], "size": 4},  # 1-crt-dyld
            {"address": 4, "names": [], "size": 4},  # 3-unnamed-jump-island
            {"address": 8, "names": ["_mapped_fn"], "size": 8},  # mapped
            {"address": 16, "names": ["+[FooKernelServerInstance kernelServerInstance]"],
             "size": 20},  # 4-build-generated-class
            {"address": 40, "names": ["_stub_fn"], "size": 4},  # 2-picsymbol-stub
            {"address": 100, "names": ["_orphan_fn"], "size": 12},  # 6-fn-no-source-site
        ],
        "sections": [{"name": "__picsymbol_stub", "address": 40, "size": 8}],
    }
    source_map = {"mapped": [{"address": 8}], "unmapped": [{"address": 999}]}

    analysis_path = tmp_path / "analysis.json"
    analysis_path.write_text(json.dumps(analysis), encoding="utf-8")
    source_map_path = tmp_path / "source-map.json"
    source_map_path.write_text(json.dumps(source_map), encoding="utf-8")

    completed = subprocess.run(
        [sys.executable, str(_SCRIPT), str(analysis_path), str(source_map_path)],
        capture_output=True, text=True, timeout=60, check=False,
    )

    assert completed.returncode == 0
    assert "total functions: 6" in completed.stdout
    assert "mapped: 1" in completed.stdout
    assert "1-crt-dyld: 1" in completed.stdout
    assert "2-picsymbol-stub: 1" in completed.stdout
    assert "3-unnamed-jump-island: 1" in completed.stdout
    assert "4-build-generated-class: 1" in completed.stdout
    assert "5-fn-with-source-site: 0" in completed.stdout
    assert "6-fn-no-source-site: 1" in completed.stdout
    assert "counted: 6" in completed.stdout
    assert "RECONCILES: yes" in completed.stdout
