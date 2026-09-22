"""Compare one i386 function between two flat images, masking only addresses.

Byte parity for code with no relocation table -- the headerless 4.2 booter,
or a fully linked MH_EXECUTE kernel -- cannot mask by relocation. This tool
decodes both slices with capstone and requires the two instruction streams to
agree exactly, with three allowances:

- a 32-bit displacement or immediate whose two values differ is masked only
  when each value lies inside its own image's address window;
- a relative branch or call leaving the function is masked the same way, by
  its absolute target;
- a relative branch staying inside the function must land at the same
  function-relative offset in both.

Every masked reference address must map to one rebuilt address throughout,
and vice versa, or the comparison fails. An inline jump table (--table) is
compared entry by entry as function-relative offsets.

Usage:
  compare_flat.py REF REF_BASE REF_START OURS OURS_BASE OURS_START SIZE
                  [--ours-size N] [--table OFF:COUNT]...
                  [--ref-window LO:HI] [--ours-window LO:HI]

BASE is the address of the file's first byte. Numbers accept a 0x prefix.
Exit status: 0 MATCH, 1 MISMATCH, 2 usage error.
"""
import argparse
import sys

import capstone

BOOTER_WINDOW = (0x3000, 0x11000)


class Result(object):
    def __init__(self):
        self.problems = []
        self.mapping = {}
        self.reverse = {}
        self.compared = 0
        self.masked = 0
        self.instructions = 0

    @property
    def match(self):
        return not self.problems

    def fail(self, message):
        self.problems.append(message)

    def map_address(self, ref, ours, where):
        if self.mapping.setdefault(ref, ours) != ours:
            self.fail("%s: 0x%x maps to 0x%x here but 0x%x elsewhere"
                      % (where, ref, ours, self.mapping[ref]))
        elif self.reverse.setdefault(ours, ref) != ref:
            self.fail("%s: rebuilt 0x%x is 0x%x here but 0x%x elsewhere"
                      % (where, ours, ref, self.reverse[ours]))


def _inside(value, window):
    return window[0] <= value < window[1]


def _decode(code, address):
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.detail = True
    return list(md.disasm(code, address))


def _regions(size, tables):
    """Split [0, size) into code regions around the jump tables."""
    edges = sorted((off, off + 4 * count) for off, count in tables)
    regions, pos = [], 0
    for lo, hi in edges:
        if lo > pos:
            regions.append((pos, lo))
        pos = hi
    if pos < size:
        regions.append((pos, size))
    return regions


def _compare_insn(r, o, ref_fn, ours_fn, size, windows, res):
    where = "+%d" % (r.address - ref_fn)
    rb, ob = bytes(r.bytes), bytes(o.bytes)
    if r.size != o.size or r.mnemonic != o.mnemonic:
        res.fail("%s: %s %s | %s %s" % (where, r.mnemonic, r.op_str, o.mnemonic, o.op_str))
        return
    masked = set()
    groups = set(r.groups)
    if capstone.CS_GRP_BRANCH_RELATIVE in groups:
        tr, to = r.operands[0].imm, o.operands[0].imm
        in_r = ref_fn <= tr < ref_fn + size
        in_o = ours_fn <= to < ours_fn + size
        if in_r and in_o:
            if tr - ref_fn != to - ours_fn:
                res.fail("%s: branch to +%d | +%d" % (where, tr - ref_fn, to - ours_fn))
        elif _inside(tr, windows[0]) and _inside(to, windows[1]):
            res.map_address(tr, to, where)
        else:
            res.fail("%s: branch target 0x%x | 0x%x" % (where, tr, to))
        masked.update(range(r.imm_offset, r.imm_offset + r.imm_size))
    else:
        for off, width in ((r.disp_offset, r.disp_size), (r.imm_offset, r.imm_size)):
            if width != 4:
                continue
            vr = int.from_bytes(rb[off:off + 4], "little")
            vo = int.from_bytes(ob[off:off + 4], "little")
            if _inside(vr, windows[0]) and _inside(vo, windows[1]):
                res.map_address(vr, vo, where)
                masked.update(range(off, off + 4))
    for i in range(r.size):
        if i in masked:
            res.masked += 1
        elif rb[i] != ob[i]:
            res.fail("%s: byte %d differs in %s %s | %s %s"
                     % (where, i, r.mnemonic, r.op_str, o.mnemonic, o.op_str))
            return
        else:
            res.compared += 1


def compare(ref, ref_base, ref_fn, ours, ours_base, ours_fn, size,
            ours_size=None, tables=(), ref_window=BOOTER_WINDOW,
            ours_window=BOOTER_WINDOW):
    res = Result()
    if ours_size is not None and ours_size != size:
        res.fail("size %d | %d" % (size, ours_size))
    ref_code = ref[ref_fn - ref_base:ref_fn - ref_base + size]
    ours_code = ours[ours_fn - ours_base:ours_fn - ours_base + size]
    if len(ref_code) != size or len(ours_code) != size:
        res.fail("function runs past the end of an image")
        return res
    windows = (ref_window, ours_window)

    for off, count in tables:
        for k in range(count):
            at = off + 4 * k
            er = int.from_bytes(ref_code[at:at + 4], "little") - ref_fn
            eo = int.from_bytes(ours_code[at:at + 4], "little") - ours_fn
            if er != eo or not 0 <= er < size:
                res.fail("+%d: table entry %d is +%d | +%d" % (at, k, er, eo))
            res.masked += 4

    for lo, hi in _regions(size, tables):
        ri = _decode(ref_code[lo:hi], ref_fn + lo)
        oi = _decode(ours_code[lo:hi], ours_fn + lo)
        for insns, fn, label in ((ri, ref_fn, "reference"), (oi, ours_fn, "rebuilt")):
            covered = sum(i.size for i in insns)
            if covered != hi - lo:
                res.fail("%s does not decode at +%d" % (label, lo + covered))
        for r, o in zip(ri, oi):
            res.instructions += 1
            _compare_insn(r, o, ref_fn, ours_fn, size, windows, res)
            if not res.match:
                return res
        if len(ri) != len(oi):
            res.fail("+%d..+%d: %d instructions | %d" % (lo, hi, len(ri), len(oi)))
    return res


def _number(text):
    return int(text, 0)


def _pair(text):
    a, b = text.split(":")
    return _number(a), _number(b)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("ref")
    p.add_argument("ref_base", type=_number)
    p.add_argument("ref_start", type=_number)
    p.add_argument("ours")
    p.add_argument("ours_base", type=_number)
    p.add_argument("ours_start", type=_number)
    p.add_argument("size", type=_number)
    p.add_argument("--ours-size", type=_number)
    p.add_argument("--table", type=_pair, action="append", default=[])
    p.add_argument("--ref-window", type=_pair, default=BOOTER_WINDOW)
    p.add_argument("--ours-window", type=_pair, default=BOOTER_WINDOW)
    a = p.parse_args(argv)
    with open(a.ref, "rb") as f:
        ref = f.read()
    with open(a.ours, "rb") as f:
        ours = f.read()
    res = compare(ref, a.ref_base, a.ref_start, ours, a.ours_base, a.ours_start,
                  a.size, a.ours_size, a.table, a.ref_window, a.ours_window)
    for problem in res.problems:
        print("MISMATCH %s" % problem)
    for ref_addr in sorted(res.mapping):
        print("map 0x%x -> 0x%x" % (ref_addr, res.mapping[ref_addr]))
    print("%s: %d instructions, %d bytes compared, %d masked, %d addresses mapped"
          % ("MATCH" if res.match else "MISMATCH", res.instructions,
             res.compared, res.masked, len(res.mapping)))
    return 0 if res.match else 1


if __name__ == "__main__":
    sys.exit(main())
