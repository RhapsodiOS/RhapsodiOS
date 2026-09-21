"""Extract the VBE20DisplayDriver reference out of OS42MachUserPatch4.tar.

Usage: extract-os42-patch.py <OS42MachUserPatch4.tar> <dest-dir>

GNU tar and Python tarfile both reject the inner tar: it uses a 225-byte name
field instead of the standard 100, so every other header field sits at +125
from standard (size at 249, mtime at 261).  This script walks the headers by
hand.  Widen `want` to pull other members out of the same patch.

The outer .pkg tar is standard, and its .tar.Z is compress(1) (LZW) data, not
gzip, so tarfile reads the outer and unlzw() unpacks the inner.
"""
import os, re, sys, hashlib, tarfile

PATCH = sys.argv[1]
DEST = sys.argv[2]
NAME_LEN = 225          # not the standard 100
SIZE_OFF = 249          # standard 124, shifted by +125

def members(buf):
    for m in re.finditer(rb'\./[A-Za-z0-9_./+-]{2,220}', buf):
        i = m.start()
        if i % 512:
            continue
        hdr = buf[i:i + 512]
        name = hdr[:NAME_LEN].split(b'\x00')[0].decode('ascii', 'replace')
        raw = hdr[SIZE_OFF:SIZE_OFF + 12].split(b'\x00')[0].strip()
        if not raw:
            continue
        yield name, int(raw, 8), i + 512

def unlzw(z):
    """Decode compress(1) .Z data (block mode, 9..maxbits codes)."""
    assert z[:2] == b'\x1f\x9d', 'not compress(1) data'
    maxbits, block = z[2] & 0x1f, z[2] & 0x80
    z = z[3:]
    first = 257 if block else 256
    table = [bytes([i]) for i in range(256)] + [b''] * ((1 << maxbits) - 256)
    nbits, free, pos, base, old = 9, first, 0, 0, None
    out = bytearray()
    end = len(z) * 8

    def align(p, n):        # a width change or clear flushes a group of 8 codes
        step = n * 8
        return base + (p - base + step - 1) // step * step

    while True:
        if free > (1 << nbits) - 1 and nbits < maxbits:
            pos = base = align(pos, nbits)
            nbits += 1
        if pos + nbits > end:
            return bytes(out)
        code = (int.from_bytes(z[pos >> 3:(pos >> 3) + 3], 'little')
                >> (pos & 7)) & ((1 << nbits) - 1)
        pos += nbits
        if block and code == 256:
            pos = base = align(pos, nbits)
            nbits, free, old = 9, first, None
            continue
        if old is None:
            entry = table[code]
        else:
            prev = table[old]
            # code == free is the KwKwK case: the entry is not defined yet
            entry = table[code] if code < free else prev + prev[:1]
            if free < (1 << maxbits):
                table[free] = prev + entry[:1]
                free += 1
        out += entry
        old = code

# outer .pkg tar -> inner .tar.Z -> inner tar
with tarfile.open(PATCH) as outer:
    inner_z = outer.extractfile('OS42MachUserPatch4.pkg/OS42MachUserPatch4.tar.Z').read()
inner = unlzw(inner_z)

want = './private/Drivers/i386/VBE20DisplayDriver.config/'
os.makedirs(DEST, exist_ok=True)
for name, size, off in members(inner):
    if not name.startswith(want) or size == 0:
        continue
    rel = name[len(want):]
    out = os.path.join(DEST, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    data = inner[off:off + size]
    open(out, 'wb').write(data)
    print(f'{hashlib.sha256(data).hexdigest().upper()}  {size:8d}  {rel}')
