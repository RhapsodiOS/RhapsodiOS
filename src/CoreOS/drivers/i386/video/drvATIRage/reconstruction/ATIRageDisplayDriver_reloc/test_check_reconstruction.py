import unittest

from check_reconstruction import (
    ContractError,
    compare_thunk,
    compare_relocated_data,
    validate_static_symbols,
    validate_abi,
    validate_modes,
    validate_text_partition,
)


class ReconstructionContractTests(unittest.TestCase):
    def setUp(self):
        self.ranges = [
            {"address": 0, "size": 3, "kind": "function"},
            {"address": 5, "size": 2, "kind": "transition"},
            {"address": 8, "size": 2, "kind": "thunk"},
        ]
        self.gaps = [
            {"address": 3, "size": 2, "kind": "padding"},
            {"address": 7, "size": 1, "kind": "padding"},
        ]
        self.abi = {
            "instance_size": 12,
            "superclass_size": 4,
            "ivars": [
                {"name": "first", "encoding": "I", "offset": 4, "size": 4},
                {"name": "second", "encoding": "I", "offset": 8, "size": 4},
            ],
        }
        self.modes = [{"bytes": 136, "index": index} for index in range(72)]

    def test_complete_partition_passes(self):
        validate_text_partition(self.ranges, self.gaps, 10)

    def test_missing_bios_thunk_fails_coverage(self):
        with self.assertRaisesRegex(ContractError, "uncovered text"):
            validate_text_partition(self.ranges[:-1], self.gaps, 10)

    def test_missing_bios_transition_fails_coverage(self):
        with self.assertRaisesRegex(ContractError, "uncovered text"):
            validate_text_partition(self.ranges[:1] + self.ranges[2:], self.gaps, 10)

    def test_changed_ivar_fails_abi(self):
        self.abi["ivars"][1]["offset"] = 7
        with self.assertRaisesRegex(ContractError, "ivar second"):
            validate_abi(self.abi)

    def test_missing_mode_fails_data_coverage(self):
        self.modes.pop()
        with self.assertRaisesRegex(ContractError, "72 modes"):
            validate_modes(self.modes, expected_count=72, record_size=136)

    def test_changed_thunk_byte_fails_parity(self):
        with self.assertRaisesRegex(ContractError, "thunk differs"):
            compare_thunk(b"\x90\x90", b"\x90\x91")

    def test_relocated_data_accepts_same_symbolic_pointer(self):
        relocations = [{"offset": 0, "kind": "absolute", "target": "_strings", "addend": 4}]
        compare_relocated_data(
            b"\x00\x10\x00\x00\x02",
            b"\x00\x20\x00\x00\x02",
            relocations,
            relocations,
        )

    def test_relocated_data_rejects_changed_pointer_target(self):
        with self.assertRaisesRegex(ContractError, "relocation targets differ"):
            compare_relocated_data(
                b"\x00\x10\x00\x00\x02",
                b"\x00\x20\x00\x00\x02",
                [{"offset": 0, "kind": "absolute", "target": "_strings", "addend": 4}],
                [{"offset": 0, "kind": "absolute", "target": "_other", "addend": 4}],
            )

    def test_missing_static_symbol_fails_inventory(self):
        with self.assertRaisesRegex(ContractError, "_ValidModeList"):
            validate_static_symbols(["_AtiModeList", "_ValidModeList"], ["_AtiModeList"])


if __name__ == "__main__":
    unittest.main()
