"""Deterministic file contents and POSIX cksum, mirrored by the guest script.

A file's contents are its name followed by a newline, repeated and cut to
length.  The guest regenerates the same bytes with the one-line perl in
GUEST_PERL, so nothing large ever has to cross the serial console.
"""

GUEST_PERL = ("perl -e 'print substr(($ARGV[0].\"\\n\") x "
              "(int($ARGV[1]/(1+length $ARGV[0]))+1), 0, $ARGV[1])'")


def data(name, size):
    unit = name.encode("utf-8") + b"\n"
    return (unit * (size // len(unit) + 1))[:size]


def _crc_table():
    table = []
    for i in range(256):
        c = i << 24
        for _ in range(8):
            c = ((c << 1) ^ 0x04C11DB7) if c & 0x80000000 else (c << 1)
        table.append(c & 0xFFFFFFFF)
    return table


_TABLE = _crc_table()


def cksum(b):
    """The CRC printed by POSIX cksum(1)."""
    crc = 0
    for x in b:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _TABLE[(crc >> 24) ^ x]
    n = len(b)
    while n:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _TABLE[(crc >> 24) ^ (n & 0xFF)]
        n >>= 8
    return (~crc) & 0xFFFFFFFF
