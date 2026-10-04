"""Reference-driven source and bundle checks for drvDEC21X4X."""

import hashlib
import os
import re
import sys
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[5]
REFERENCE = Path(os.environ["BINRECON_REFERENCE"])
PROJECT = REPO / "src/drivers-i386/network/drvDEC21X4X/DEC21X4X.drvproj"
SOURCE = PROJECT / "DEC21X4X.lksproj"
sys.path.insert(0, str(REPO / "tools/binrecon"))
from selector_check import reference_selectors, source_methods


GENERATED_SELECTORS = {
    "+[DEC21X4XNetworkKernelServerInstance kernelServerInstance]",
    "+[DEC21X4XNetworkVersion driverKitVersionForDEC21X4XNetwork]",
}


def _resource_list(project_file, variable):
    for line in project_file.read_text().splitlines():
        if line.startswith(variable + " ="):
            return set(line.split("=", 1)[1].split())
    return set()


def _pb_resource_list(project_file, variable):
    text = project_file.read_text()
    match = re.search(r"\b" + re.escape(variable) + r"\s*=\s*\(([^)]*)\)", text)
    return set() if match is None else {item.strip().strip('"') for item in match.group(1).split(",")}


def _default_table_content(path):
    return "\n".join(
        line for line in path.read_text().splitlines()
        if not line.startswith(('"Driver Version"', '"Version"'))
    ).strip()


class ReferenceTests(unittest.TestCase):
    def test_reference_methods_match_source_without_selector_drift(self):
        expected = reference_selectors(REFERENCE)
        actual = [method[0] for method in source_methods(SOURCE)]
        self.assertEqual(len(actual), len(set(actual)), "duplicate source method")
        self.assertEqual(set(actual) - expected, set())
        self.assertEqual(expected - set(actual), GENERATED_SELECTORS)

    def test_project_manifest_includes_reference_resources(self):
        reference_tables = {path.name for path in REFERENCE.parent.glob("*.table")}
        reference_strings = {path.name for path in (REFERENCE.parent / "English.lproj").glob("*.strings")}
        makefile = PROJECT / "Makefile"
        self.assertEqual(_resource_list(makefile, "GLOBAL_RESOURCES"), reference_tables)
        self.assertEqual(_resource_list(makefile, "LOCAL_RESOURCES"), reference_strings | {"DriverHelp"})
        pb_project = PROJECT / "PB.project"
        self.assertEqual(_pb_resource_list(pb_project, "OTHER_RESOURCES"), reference_tables | reference_strings | {"DriverHelp"})
        self.assertIn("DEC21X4XInspector.nib = DEC21X4XInspector.nib;", pb_project.read_text())

    def test_kernel_server_compiles_each_source_unit(self):
        makefile = SOURCE / "Makefile"
        self.assertEqual(
            _resource_list(makefile, "CLASSES"),
            {"DEC21142.m", "DEC21x4Init.m", "DEC21x4SRom.m"},
        )
        self.assertEqual(_resource_list(makefile, "CFILES"), {"DEC21X4XMII.c", "DEC21X4XUtil.c"})

    def test_class_fields_follow_recovered_instance_layout(self):
        header = (SOURCE / "DEC21X4X.h").read_text()
        ordered_fields = (
            "unsigned short ioBase;",
            "unsigned short irq;",
            "IONetwork *networkInterface;",
            "IONetbufQueue *transmitQueue;",
            "char isPromiscuous;",
            "char multicastEnabled;",
            "char resetAndEnabled;",
            "unsigned char sromAddressBits;",
            "netbuf_t txNetbuf[32];",
            "netbuf_t rxNetbuf[64];",
            "void *rxRing;",
            "void *txRing;",
            "unsigned int txPutIndex;",
            "unsigned int txDoneIndex;",
            "unsigned int txNumFree;",
            "unsigned int txIntCount;",
            "unsigned int rxDoneIndex;",
            "netbuf_t KDB_txBuf;",
            "void *memoryPtr;",
            "unsigned int memorySize;",
            "void *setupBuffer;",
            "unsigned int setupBufferPhysical;",
            "void *Adapter;",
            "unsigned int MediaCapableSaved;",
        )
        positions = [header.index(field) for field in ordered_fields]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("self->Adapter = adapterInfo;", (SOURCE / "DEC21142.m").read_text())

    def test_reference_bundle_resources_are_present_and_unchanged(self):
        checked = 0
        for reference_file in REFERENCE.parent.rglob("*"):
            if not reference_file.is_file() or reference_file.name.startswith((REFERENCE.name, REFERENCE.stem)):
                continue
            if reference_file.name == "DEC21X4XNetwork":
                continue
            relative = reference_file.relative_to(REFERENCE.parent)
            source_relative = relative
            if relative.parts[:2] == ("English.lproj", "Help"):
                source_relative = Path("English.lproj", "DriverHelp", *relative.parts[2:])
            source_file = PROJECT / source_relative
            self.assertTrue(source_file.is_file(), f"missing bundle resource: {source_relative}")
            if source_relative.name == "Default.table":
                self.assertEqual(_default_table_content(source_file), _default_table_content(reference_file))
            else:
                self.assertEqual(hashlib.sha256(source_file.read_bytes()).digest(), hashlib.sha256(reference_file.read_bytes()).digest(), str(source_relative))
            checked += 1
        self.assertGreaterEqual(checked, 10)


if __name__ == "__main__":
    unittest.main()
