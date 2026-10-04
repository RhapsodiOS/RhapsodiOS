"""Source and bundle checks against Apple's EtherLink3 reference bundle."""

import os
import sys
import unittest
import hashlib
from pathlib import Path


REPO = Path(__file__).resolve().parents[5]
REFERENCE = Path(os.environ["BINRECON_REFERENCE"])
SOURCE = REPO / "src/drivers-i386/network/drvEtherLink3/EtherLink3.drvproj/EtherLink3.lksproj"
PROJECT = REPO / "src/drivers-i386/network/drvEtherLink3/EtherLink3.drvproj/Makefile"
sys.path.insert(0, str(REPO / "tools/binrecon"))
from selector_check import classify, reference_selectors, source_methods


class ReferenceTests(unittest.TestCase):
    def test_all_reference_methods_are_reconstructed_without_extras(self):
        reference = reference_selectors(REFERENCE)
        methods = list(source_methods(SOURCE))
        renames, duplicates, missing, extra = classify(reference, methods)
        generated = {
            "+[EtherLink3KernelServerInstance kernelServerInstance]",
            "+[EtherLink3Version driverKitVersionForEtherLink3]",
        }
        self.assertEqual(renames, [])
        self.assertEqual(duplicates, [])
        self.assertEqual(set(missing), generated)
        self.assertEqual(extra, [])

    def test_instance_fields_follow_the_reference_order(self):
        header = (SOURCE / "EtherLink3.h").read_text()
        fields = [
            "ioBase", "reported_irq", "real_irq", "myAddress", "myConnector",
            "autoConnector", "myType", "isISA", "networkInterface",
            "resetInProgress", "rxEarlyThreshold", "rxModes", "currentWindow",
            "txQ", "txFreeQ", "rxQ", "rxPoolQ", "interruptHappened",
            "outputErrors", "collisions", "outputPackets", "inputErrors",
        ]
        offsets = [header.index(" " + field + ";") for field in fields]
        self.assertEqual(offsets, sorted(offsets))

    def test_driver_project_packages_all_reference_adapter_resources(self):
        project = PROJECT.read_text()
        global_resources = _resource_list(project, "GLOBAL_RESOURCES")
        local_resources = _resource_list(project, "LOCAL_RESOURCES")
        self.assertEqual(
            global_resources,
            {"Default.table", "EtherLink3EISA.table", "EtherLink3PCMCIA.table", "EtherLink3PnP.table"},
        )
        self.assertEqual(
            local_resources,
            {"Localizable.strings", "EtherLink3EISA.strings", "EtherLink3PCMCIA.strings", "EtherLink3PnP.strings", "DriverHelp"},
        )

    def test_bundle_resources_match_the_reference_byte_for_byte(self):
        bundle = REFERENCE.parent
        source_bundle = PROJECT.parent
        ignored = {"EtherLink3", "EtherLink3_reloc", "EtherLink3_reloc.til", "EtherLink3_reloc.nam"}
        checked = 0
        for reference_file in bundle.rglob("*"):
            if (
                not reference_file.is_file()
                or reference_file.name in ignored
                or reference_file.name.startswith("EtherLink3_reloc.id")
            ):
                continue
            relative = reference_file.relative_to(bundle)
            source_relative = relative
            if relative.parts[:2] and relative.parts[0] == "English.lproj" and relative.parts[1] == "Help":
                source_relative = Path("English.lproj", "DriverHelp", *relative.parts[2:])
            source_file = source_bundle / source_relative
            self.assertTrue(source_file.is_file(), f"missing resource: {source_relative}")
            self.assertEqual(
                hashlib.sha256(source_file.read_bytes()).digest(),
                hashlib.sha256(reference_file.read_bytes()).digest(),
                str(source_relative),
            )
            checked += 1
        self.assertGreaterEqual(checked, 25)


def _resource_list(project, variable):
    for line in project.splitlines():
        if line.startswith(variable + " ="):
            return set(line.split("=", 1)[1].split())
    return set()


if __name__ == "__main__":
    unittest.main()
