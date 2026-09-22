import compare_flat

BASE = 0x3000
FN = 0x3100


def _image(code, fn=FN, base=BASE):
    """A flat image with `code` at address `fn`, zero-filled around it."""
    return bytes(fn - base) + code + bytes(64)


def _run(ref_code, ours_code, **kw):
    return compare_flat.compare(_image(ref_code), BASE, FN,
                                _image(ours_code), BASE, FN,
                                len(ref_code), **kw)


PROLOGUE = bytes.fromhex("5589e5")          # push ebp; mov ebp,esp
EPILOGUE = bytes.fromhex("c9c3")            # leave; ret


def _push(addr):
    return b"\x68" + addr.to_bytes(4, "little")


def test_identical_code_matches():
    code = PROLOGUE + _push(0x9000) + EPILOGUE
    res = _run(code, code)
    assert res.match, res.problems
    assert res.mapping == {0x9000: 0x9000}


def test_string_address_differing_inside_window_is_masked_and_mapped():
    res = _run(PROLOGUE + _push(0x9000) + EPILOGUE,
               PROLOGUE + _push(0x9400) + EPILOGUE)
    assert res.match, res.problems
    assert res.mapping == {0x9000: 0x9400}
    assert res.masked == 4


def test_constant_outside_window_must_match():
    add_1870 = bytes.fromhex("81c770180000")   # add edi,0x1870
    add_1858 = bytes.fromhex("81c758180000")   # add edi,0x1858
    res = _run(PROLOGUE + add_1870 + EPILOGUE, PROLOGUE + add_1858 + EPILOGUE)
    assert not res.match


def test_external_call_targets_are_mapped():
    def call_to(target):
        # call rel32 at FN+3; next instruction at FN+8
        return b"\xe8" + (target - (FN + 8)).to_bytes(4, "little", signed=True)
    res = _run(PROLOGUE + call_to(0x6000) + EPILOGUE,
               PROLOGUE + call_to(0x7000) + EPILOGUE)
    assert res.match, res.problems
    assert res.mapping == {0x6000: 0x7000}


def test_internal_branch_to_a_different_offset_fails():
    ref = PROLOGUE + bytes.fromhex("7501") + b"\x90" + EPILOGUE    # jne +1
    ours = PROLOGUE + bytes.fromhex("7500") + b"\x90" + EPILOGUE   # jne +0
    assert not _run(ref, ours).match


def test_one_reference_address_mapped_two_ways_fails():
    ref = PROLOGUE + _push(0x9000) + _push(0x9000) + EPILOGUE
    ours = PROLOGUE + _push(0x9400) + _push(0x9800) + EPILOGUE
    res = _run(ref, ours)
    assert not res.match
    assert "elsewhere" in res.problems[0]


def test_sixteen_bit_immediate_is_never_masked():
    # mov word ptr [0x9000], 0x4f02 versus 0x4f01: the disp is an address,
    # the imm16 is a VBE function number and must compare.
    ref = PROLOGUE + bytes.fromhex("66c70500900000024f") + EPILOGUE
    ours = PROLOGUE + bytes.fromhex("66c70500940000014f") + EPILOGUE
    assert not _run(ref, ours).match


def test_jump_table_entries_compare_as_function_offsets():
    body = PROLOGUE + b"\x90" * 5 + EPILOGUE           # 10 bytes
    ref_table = (FN + 3).to_bytes(4, "little") + (FN + 4).to_bytes(4, "little")
    same = _run(body + ref_table, body + ref_table, tables=[(10, 2)])
    assert same.match, same.problems
    moved = (FN + 3).to_bytes(4, "little") + (FN + 5).to_bytes(4, "little")
    assert not _run(body + ref_table, body + moved, tables=[(10, 2)]).match


def test_different_mnemonic_fails():
    ref = PROLOGUE + b"\x90" + EPILOGUE
    ours = PROLOGUE + b"\x40" + EPILOGUE        # inc eax
    assert not _run(ref, ours).match


def test_different_sizes_fail_even_when_the_prefix_matches():
    code = PROLOGUE + EPILOGUE
    res = compare_flat.compare(_image(code), BASE, FN, _image(code), BASE, FN,
                               len(code), ours_size=len(code) + 1)
    assert not res.match


def test_cli_exit_status(tmp_path):
    ref = tmp_path / "ref.bin"
    ours = tmp_path / "ours.bin"
    ref.write_bytes(_image(PROLOGUE + _push(0x9000) + EPILOGUE))
    ours.write_bytes(_image(PROLOGUE + _push(0x9400) + EPILOGUE))
    args = [str(ref), "0x3000", "0x3100", str(ours), "0x3000", "0x3100", "10"]
    assert compare_flat.main(args) == 0
    ours.write_bytes(_image(PROLOGUE + bytes.fromhex("81c770180000")[:5] + EPILOGUE))
    assert compare_flat.main(args) == 1
