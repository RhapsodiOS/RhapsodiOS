"""Unit tests for install-driver.py's Boot Drivers edit.

Run from the repository root with:
    python -m unittest discover -s vm -p test_install_driver.py -v
"""
import importlib.util
import os
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load():
    spec = importlib.util.spec_from_file_location(
        "install_driver", os.path.join(_HERE, "install-driver.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


install_driver = _load()


class BootDriversValueTest(unittest.TestCase):
    def test_appends_by_default(self):
        self.assertEqual(install_driver._boot_drivers_value("EISABus PCIBus", "VBE20DisplayDriver"),
                         "EISABus PCIBus VBE20DisplayDriver")

    def test_prepends_when_first(self):
        self.assertEqual(install_driver._boot_drivers_value("EISABus PCIBus", "VBE20DisplayDriver", True),
                         "VBE20DisplayDriver EISABus PCIBus")

    def test_already_listed_is_unchanged(self):
        self.assertIsNone(install_driver._boot_drivers_value("EISABus VBE20DisplayDriver", "VBE20DisplayDriver", True))


if __name__ == "__main__":
    unittest.main()
