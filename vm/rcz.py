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


def _emit_group(token, tokenct, payload, final):
    """Serialise one token word and its payload entries."""
    tok = ((token << (32 - tokenct)) if final else token) & 0xffffffff
    buf = bytearray(struct.pack(">I", tok))
    c = 1 << 31
    for j in range(tokenct):
        if tok & c:
            buf.append(payload[j] & 0xff)
        else:
            buf.append((payload[j] >> 8) & 0xff)
            buf.append(payload[j] & 0xff)
        c >>= 1
    return bytes(buf)


def compress(data):
    out = bytearray(struct.pack(">II", MAGIC, len(data)))
    que = list(range(QLEN))
    token = 0
    tokenct = 0
    payload = []
    word = 0

    for ct in range(len(data)):
        word = ((word << 8) | data[ct]) & 0xffffff
        if ct % 2 == 1:
            word &= 0xffff
            try:
                jmatch = que.index(word)
            except ValueError:
                jmatch = -1
            token = (token << 1) | (1 if jmatch >= 0 else 0)
            if jmatch >= 0:
                c = que[jmatch]
                jabove = (F1 * jmatch) >> 4
                que[jabove + 1:jmatch + 1] = que[jabove:jmatch]
                que[jabove] = c
                payload.append(jmatch)
            else:
                que[ABOVE + 1:QLEN] = que[ABOVE:QLEN - 1]
                que[ABOVE] = word
                payload.append(word)
            tokenct += 1
            if tokenct == 32:
                out += _emit_group(token, tokenct, payload, False)
                token = 0
                tokenct = 0
                del payload[:]

    if tokenct > 0:
        out += _emit_group(token, tokenct, payload, True)
    if len(data) % 2 == 1:
        out.append(word & 0xff)
    return bytes(out)


def main(argv):
    if len(argv) != 4 or argv[1] not in ("-c", "-d"):
        print("usage: rcz.py {-c|-d} <infile> <outfile>", file=sys.stderr)
        return 2
    with open(argv[2], "rb") as f:
        data = f.read()
    result = compress(data) if argv[1] == "-c" else decompress(data)
    with open(argv[3], "wb") as f:
        f.write(result)
    print("%s: %d -> %d bytes" % (argv[2], len(data), len(result)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
