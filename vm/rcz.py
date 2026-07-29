"""Codec for the rcz executable-compression format.

Ported from src/boot-2/gen/rcz/rcz_compress_mem.c and rcz_decompress_mem.c
(R. E. Crandall, July 1995).  The format is a 16-bit-symbol move-toward-front
queue: every two input bytes form a word which is either found in a 255-entry
queue and emitted as a one-byte index, or missed and emitted as the two-byte
literal.  A 32-bit token word, read from bit 31 down, says which.

The stream header is big-endian, unlike the little-endian UFS filesystem these
files normally live in.
"""

import struct
import sys

MAGIC = 666           # METHOD_17_JUL_95
QLEN = 255
F1 = 12
F2 = 12
ABOVE = (F2 * QLEN) >> 4   # 191
HEADER = 8


class RczError(Exception):
    pass


def decompress(data):
    if len(data) < HEADER:
        raise RczError("stream is %d bytes, shorter than the %d-byte header"
                       % (len(data), HEADER))
    version, length = struct.unpack_from(">II", data, 0)
    if version != MAGIC:
        raise RczError("bad method %d, expected %d" % (version, MAGIC))

    que = list(range(QLEN))
    out = bytearray()
    p = HEADER
    even = 2 * (length // 2)

    while len(out) < even:
        token = struct.unpack_from(">I", data, p)[0]
        p += 4
        c = 1 << 31
        for _ in range(32):
            if token & c:
                jmatch = data[p]
                p += 1
                word = que[jmatch]
                jabove = (F1 * jmatch) >> 4
                que[jabove + 1:jmatch + 1] = que[jabove:jmatch]
                que[jabove] = word
            else:
                word = (data[p] << 8) | data[p + 1]
                p += 2
                que[ABOVE + 1:QLEN] = que[ABOVE:QLEN - 1]
                que[ABOVE] = word
            out.append((word >> 8) & 0xff)
            out.append(word & 0xff)
            if len(out) >= even:
                break
            c >>= 1

    if even != length:
        out.append(data[p])
    return bytes(out)


def main(argv):
    if len(argv) != 4 or argv[1] != "-d":
        print("usage: rcz.py -d <infile> <outfile>", file=sys.stderr)
        return 2
    with open(argv[2], "rb") as f:
        data = f.read()
    with open(argv[3], "wb") as f:
        f.write(decompress(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
