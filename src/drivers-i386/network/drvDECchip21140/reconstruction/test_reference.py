"""Reference-driven source and bundle checks for DECchip21140."""

import hashlib
import os
import re
import sys
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[5]
REFERENCE = Path(os.environ["BINRECON_REFERENCE"])
PROJECT = REPO / "src/drivers-i386/network/drvDECchip21140/DECchip21140.drvproj"
SOURCE = PROJECT / "DECchip21140.lksproj"
sys.path.insert(0, str(REPO / "tools/binrecon"))
from selector_check import reference_selectors, source_methods


GENERATED_SELECTORS = {
    "+[DECchip21140NetworkDriverKernelServerInstance kernelServerInstance]",
    "+[DECchip21140NetworkDriverVersion driverKitVersionForDECchip21140NetworkDriver]",
}


def _without_category(selector):
    return re.sub(r"(?<=\w)\(\w+\)(?= )", "", selector)


def _resource_list(project_file, variable):
    for line in project_file.read_text().splitlines():
        if line.startswith(variable + " ="):
            return set(line.split("=", 1)[1].split())
    return set()


def _pb_resource_list(project_file, variable):
    text = project_file.read_text()
    match = re.search(r"\b" + re.escape(variable) + r"\s*=\s*\(([^)]*)\)", text)
    return set() if match is None else {item.strip().strip('"') for item in match.group(1).split(",")}


class ReferenceTests(unittest.TestCase):
    def test_reference_methods_match_source_without_selector_drift(self):
        expected = {_without_category(selector) for selector in reference_selectors(REFERENCE)}
        source_methods_list = list(source_methods(SOURCE))
        actual = [_without_category(method[0]) for method in source_methods_list]
        self.assertEqual(len(actual), len(set(actual)), "duplicate source method")
        self.assertEqual(set(actual) - expected, set())
        self.assertEqual(expected - set(actual), {_without_category(s) for s in GENERATED_SELECTORS})

    def test_project_manifest_includes_every_reference_adapter_resource(self):
        reference_tables = {p.name for p in REFERENCE.parent.glob("*.table")}
        reference_strings = {p.name for p in (REFERENCE.parent / "English.lproj").glob("*.strings")}
        project_file = PROJECT / "Makefile"
        self.assertEqual(_resource_list(project_file, "GLOBAL_RESOURCES"), reference_tables)
        self.assertEqual(
            _resource_list(project_file, "LOCAL_RESOURCES"),
            reference_strings | {"DriverHelp"},
        )

        pb_project = PROJECT / "PB.project"
        self.assertEqual(_pb_resource_list(pb_project, "OTHER_RESOURCES"),
                         reference_tables | reference_strings | {"DriverHelp"})

    def test_kernel_server_compiles_each_source_unit(self):
        makefile = SOURCE / "Makefile"
        classes = _resource_list(makefile, "CLASSES")
        self.assertEqual(
            classes,
            {"DECchip21140.m", "DECchip21140Private.m", "DECchip21140VendorSpecific.m"},
        )

    def test_every_quoted_source_header_exists(self):
        missing = []
        for source_file in SOURCE.glob("*.m"):
            for header in re.findall(r'^#import\s+"([^"]+)"', source_file.read_text(), re.MULTILINE):
                if not (SOURCE / header).is_file():
                    missing.append((source_file.name, header))
        self.assertEqual(missing, [])

    def test_reference_bundle_resources_are_present_and_unchanged(self):
        checked = 0
        for reference_file in REFERENCE.parent.rglob("*"):
            if (
                not reference_file.is_file()
                or reference_file.name in {REFERENCE.name, REFERENCE.stem}
                or reference_file.name == "DECchip21140NetworkDriver"
                or reference_file.name.startswith("DECchip21140NetworkDriver.")
                or reference_file.name.startswith(REFERENCE.name + ".id")
                or reference_file.name.startswith(REFERENCE.name + ".nam")
                or reference_file.name.startswith(REFERENCE.name + ".til")
            ):
                continue
            relative = reference_file.relative_to(REFERENCE.parent)
            source_relative = relative
            if relative.parts[:2] == ("English.lproj", "Help"):
                source_relative = Path("English.lproj", "DriverHelp", *relative.parts[2:])
            source_file = PROJECT / source_relative
            self.assertTrue(source_file.is_file(), f"missing bundle resource: {source_relative}")
            self.assertEqual(
                hashlib.sha256(source_file.read_bytes()).digest(),
                hashlib.sha256(reference_file.read_bytes()).digest(),
                str(source_relative),
            )
            checked += 1
        self.assertGreaterEqual(checked, 30)


if __name__ == "__main__":
    unittest.main()
