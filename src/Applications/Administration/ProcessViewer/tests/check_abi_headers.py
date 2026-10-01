"""Static checks for recovered 32-bit Objective-C instance layouts."""

from pathlib import Path
import hashlib
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


LAYOUTS = {
    "Process.h": {
        "Process": ["_pid", "_ppid", "_pgid", "_saved_euid", "_real_uid", "_args", "_values"],
        "MapTableEnumerator": ["_mapEnum"],
    },
    "ProcessControl.h": {
        "ProcessControl": [
            "processTable", "sortOrderButton", "filterText", "typePopup", "rateField",
            "countField", "timer", "allColumns", "fieldNames", "filteredProcesses",
            "allProcesses", "optionsDictionary", "moreInfoSwitch", "inspector", "processTypes",
        ],
    },
    "ProcessType.h": {"ProcessType": ["_name", "_key", "_values"]},
    "ProcessTableView.h": {
        "ProcessTableView": ["_highlightedColumnIdentifier"],
        "ProcessTableHeaderView": [],
    },
    "Inspector.h": {
        "Inspector": [
            "_process", "splitView", "tabContainer", "invalidSelectionView", "tabView",
            "pidView", "statsView", "argsView", "invalidSelectionText", "pathField",
            "argumentsTable", "pidField", "parentField", "processGroupField", "savedUidField",
            "terminalField", "realMemoryField", "virtualMemoryField", "timeField", "_isVisible",
            "_minTabContainerHeight", "_minMainContainerHeight",
        ],
    },
}


class RecoveredLayoutTests(unittest.TestCase):
    def test_headers_declare_every_recovered_class_and_ivar_in_order(self):
        for filename, classes in LAYOUTS.items():
            source = (ROOT / filename).read_text(encoding="utf-8")
            for name, expected_ivars in classes.items():
                with self.subTest(header=filename, class_name=name):
                    if not expected_ivars:
                        declaration = re.search(
                            rf"@interface\s+{name}\s*:\s*[^{{@]+(?P<body>.*?)@end",
                            source,
                            re.DOTALL,
                        )
                        self.assertIsNotNone(declaration, f"missing @interface for {name}")
                        self.assertNotIn("{", declaration.group("body"))
                        continue
                    declaration = re.search(
                        rf"@interface\s+{name}\s*:\s*[^{{]+\{{", source
                    )
                    self.assertIsNotNone(declaration, f"missing @interface for {name}")
                    start = declaration.end()
                    depth = 1
                    end = start
                    while depth and end < len(source):
                        depth += (source[end] == "{") - (source[end] == "}")
                        end += 1
                    self.assertEqual(depth, 0, f"unterminated ivar block for {name}")
                    ivar_block = source[start : end - 1]
                    ivar_block = re.sub(
                        r"struct\s*\{.*?\}\s*([A-Za-z_][A-Za-z_0-9]*)\s*;",
                        r"\1;",
                        ivar_block,
                        flags=re.DOTALL,
                    )
                    actual_ivars = re.findall(r"\b([A-Za-z_][A-Za-z_0-9]*)\s*;", ivar_block)
                    self.assertEqual(actual_ivars, expected_ivars)

    def test_application_project_uses_shared_sources_and_preserved_nibs(self):
        makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
        preamble = (ROOT / "Makefile.preamble").read_text(encoding="utf-8")
        project = (ROOT / "PB.project").read_text(encoding="utf-8")
        settings = makefile + preamble + project
        for expected in (
            "NAME = ProcessViewer",
            "PROJECT_TYPE = Application",
            "MAKEFILE = app.make",
            "Process.m",
            "ProcessType.m",
            "ProcessTableView.m",
            "ProcessControl.m",
            "Inspector.m",
            "ProcessViewer.nib",
            "inspector.nib",
        ):
            with self.subTest(setting=expected):
                self.assertIn(expected, settings)
        self.assertIn("PROJECTTYPE = Application", project)
        controller = (ROOT / "ProcessControl.m").read_text(encoding="utf-8")
        self.assertRegex(controller, r"\bint\s+main\s*\(int\s+argc,")
        self.assertTrue((ROOT / "Resources/English.lproj/ProcessViewer.nib/objects.nib").is_file())
        self.assertTrue((ROOT / "Resources/English.lproj/inspector.nib/objects.nib").is_file())

    def test_copied_bundle_resources_match_the_reference_hashes(self):
        manifest = ROOT / "reconstruction/resources.sha256"
        for line in manifest.read_text(encoding="utf-8").splitlines():
            digest, relative_path = line.split(maxsplit=1)
            with self.subTest(resource=relative_path):
                actual = hashlib.sha256((ROOT / relative_path).read_bytes()).hexdigest()
                self.assertEqual(actual, digest)

    def test_c_prototypes_use_source_names_without_macho_prefixes(self):
        process = (ROOT / "Process.h").read_text(encoding="utf-8")
        process_type = (ROOT / "ProcessType.h").read_text(encoding="utf-8")
        for pattern in (
            r"\bdouble\s+floatFromNumberWithSuffix\s*\(id\s+",
            r"\bint\s+sortFunction\s*\(id\s+",
            r"\bvoid\s*\*\s*NameForUID\s*\(uid_t\s+",
        ):
            with self.subTest(pattern=pattern):
                self.assertRegex(process, pattern)
        self.assertRegex(
            process_type,
            r"\bvoid\s+_readTypesFromFile\s*\(\s*id\s+processTypeClass\s*,\s*"
            r"NSString\s*\*\s*processTypesDirectory\s*,\s*"
            r"NSString\s*\*\s*path\s*\)",
        )


if __name__ == "__main__":
    unittest.main()
