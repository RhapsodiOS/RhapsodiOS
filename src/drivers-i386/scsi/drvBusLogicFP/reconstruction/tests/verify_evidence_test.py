import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[6]
sys.path.insert(0, str(REPO / "src/drivers-i386/scsi/drvBusLogicFP/reconstruction"))

try:
    from verify_evidence import validate_bundle
except ImportError:
    validate_bundle = None


class EvidenceValidationTests(unittest.TestCase):
    def setUp(self):
        self.analysis = REPO / "tools/binrecon/out/buslogicfp/published/analysis-reference-ida.json"
        self.source_map = REPO / "src/drivers-i386/scsi/drvBusLogicFP/reconstruction/source-map.json"
        self.ledger = REPO / "src/drivers-i386/scsi/drvBusLogicFP/reconstruction/ledger.json"
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ledger_copy = Path(self.tmp.name) / "ledger.json"
        self.original = json.loads(self.ledger.read_text(encoding="utf-8"))

    def call(self, final=False, rebuilt=None):
        return validate_bundle(self.analysis, self.source_map, self.ledger_copy,
                               REPO, final=final, rebuilt_path=rebuilt)

    def test_reference_partition_and_identity_validate(self):
        self.ledger_copy.write_text(json.dumps(self.original), encoding="utf-8")
        result = self.call()
        self.assertEqual(result["functions"], 123)
        self.assertEqual(result["reference_sha256"], "C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E")

    def test_missing_function_is_rejected(self):
        damaged = dict(self.original)
        damaged["entries"] = damaged["entries"][:-1]
        self.ledger_copy.write_text(json.dumps(damaged), encoding="utf-8")
        with self.assertRaises(ValueError):
            self.call()

    def test_incorrect_reference_hash_is_rejected(self):
        damaged = json.loads(json.dumps(self.original))
        damaged["reference_sha256"] = "0" * 64
        self.ledger_copy.write_text(json.dumps(damaged), encoding="utf-8")
        with self.assertRaises(ValueError):
            self.call()

    def test_duplicate_function_is_rejected(self):
        damaged = dict(self.original)
        damaged["entries"] = damaged["entries"] + [damaged["entries"][0]]
        self.ledger_copy.write_text(json.dumps(damaged), encoding="utf-8")
        with self.assertRaises(ValueError):
            self.call()

    def test_final_mode_rejects_premature_evidence_claim(self):
        damaged = json.loads(json.dumps(self.original))
        rebuilt = REPO / "README.md"
        damaged["rebuilt_sha256"] = hashlib.sha256(rebuilt.read_bytes()).hexdigest().upper()
        damaged["entries"][0]["status"] = "control-flow-confirmed"
        damaged["entries"][0]["source_path"] = None
        damaged["entries"][0]["source_line"] = None
        for entry in damaged["entries"]:
            if entry["address"] in (0x7780, 0x778C):
                entry["analyzer_agreement"]["generated"] = True
        self.ledger_copy.write_text(json.dumps(damaged), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "has no source site"):
            self.call(final=True, rebuilt=rebuilt)


if __name__ == "__main__":
    unittest.main()





