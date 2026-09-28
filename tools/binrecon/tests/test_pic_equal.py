import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pic_equal  # noqa: E402


def _fn(address, rows):
    return {"address": address, "names": ["_f"],
            "instructions": [{"bytes": b, "mnemonic": m, "operands": o} for b, m, o in rows]}


def test_i386_pic_base_only_difference_is_equal():
    ref = _fn(0x3D4C, [("8D8303", "lea", "eax, (aUsage - 3D55h)[ebx]"),
                       ("8B55", "mov", "edx, dword ptr [ebp+arg_0]")])
    new = _fn(0x4A58, [("8D83FF", "lea", "eax, (aUsage - 4A61h)[ebx]"),
                       ("8B55", "mov", "edx, [ebp+arg_0]")])
    assert pic_equal.compare(ref, new) is None


def test_ppc_pic_label_and_local_branch_are_equal():
    ref = _fn(0x3024, [("01", "bcl", "20, 4*cr7+so, loc_3038"),
                       ("02", "addis", "r3, r31, (aOps - loc_3038)@ha")])
    new = _fn(0x2E74, [("03", "bcl", "20, 4*cr7+so, loc_2E88"),
                       ("04", "addis", "r3, r31, (aOps - loc_2E88)@ha")])
    assert pic_equal.compare(ref, new) is None


def test_different_symbol_target_stays_different():
    ref = _fn(0x100, [("01", "lea", "eax, (aUsage - 109h)[ebx]")])
    new = _fn(0x200, [("02", "lea", "eax, (aOther - 209h)[ebx]")])
    assert pic_equal.compare(ref, new) is not None


def test_scheduling_difference_stays_different():
    ref = _fn(0x100, [("01", "mr", "r9, r3"), ("02", "lwz", "r4, 0(r9)")])
    new = _fn(0x200, [("03", "lwz", "r4, 0(r3)")])
    assert pic_equal.compare(ref, new) is not None


def test_address_named_data_is_equal_when_paired_consistently():
    ref = _fn(0x100, [("01", "mov", "eax, ds:(off_C014)[ebx]"), ("02", "mov", "ecx, [ecx+287Ah]"),
                      ("03", "mov", "edx, ds:(off_C014)[ebx]")])
    new = _fn(0x200, [("04", "mov", "eax, ds:(off_8014)[ebx]"), ("05", "mov", "ecx, [ecx+20B2h]"),
                      ("06", "mov", "edx, ds:(off_8014)[ebx]")])
    assert pic_equal.compare(ref, new) is None


def test_address_named_data_paired_inconsistently_is_different():
    ref = _fn(0x100, [("01", "mov", "eax, ds:(off_C014)[ebx]"), ("02", "mov", "edx, ds:(off_C014)[ebx]")])
    new = _fn(0x200, [("03", "mov", "eax, ds:(off_8014)[ebx]"), ("04", "mov", "edx, ds:(off_8018)[ebx]")])
    assert pic_equal.compare(ref, new) is not None


def test_jump_tables_and_ida_pointer_names_pair_consistently():
    ref = _fn(0x100, [("01", "addi", "r9, r9, (jpt_467C)@l"), ("02", "lwz", "r4, (off_8028)@l(r4)"),
                      ("03", "lwz", "r5, (off_8028)@l(r4)")])
    new = _fn(0x200, [("04", "addi", "r9, r9, (jpt_4424)@l"), ("05", "lwz", "r4, (paLockwhen)@l(r4)"),
                      ("06", "lwz", "r5, (paLockwhen)@l(r4)")])
    assert pic_equal.compare(ref, new) is None


def test_ppc_symbol_minus_absolute_address_pairs_consistently():
    ref = _fn(0x100, [("01", "lwz", "r3, (_kl_port - 0x71B4)(r9)")])
    new = _fn(0x200, [("02", "lwz", "r3, (_kl_port - 0x71C0)(r9)")])
    assert pic_equal.compare(ref, new) is None
    other = _fn(0x200, [("02", "lwz", "r3, (_reply_port - 0x71C0)(r9)")])
    assert pic_equal.compare(ref, other) is not None


def test_i386_pic_add_immediate_pairs_consistently():
    ref = _fn(0x100, [("01", "add", "eax, 6843h")])
    new = _fn(0x200, [("02", "add", "eax, 239Fh")])
    assert pic_equal.compare(ref, new) is None
    small = _fn(0x200, [("02", "add", "eax, 10h")])
    assert pic_equal.compare(_fn(0x100, [("01", "add", "eax, 14h")]), small) is not None


def test_i386_pic_add_immediate_on_esi_edi_pairs():
    ref = _fn(0x100, [("01", "add", "edi, 6882h")])
    new = _fn(0x200, [("02", "add", "edi, 23DEh")])
    assert pic_equal.compare(ref, new) is None
