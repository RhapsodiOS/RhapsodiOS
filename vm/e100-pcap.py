"""Summarise a QEMU filter-dump capture for one guest MAC address.

usage: python e100-pcap.py FILE.pcap GUEST_MAC

Counts frames the guest sent, frames addressed to it, and among the latter
the ARP replies and ICMP echo replies. Exits 0 only when frames went both
ways, which is what proves a network driver both transmits and receives.
"""
import struct
import sys


def frames(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 24:
        raise ValueError("%s is too short to be a pcap file" % path)
    magic = struct.unpack("<I", data[:4])[0]
    if magic == 0xA1B2C3D4:
        endian = "<"
    elif magic == 0xD4C3B2A1:
        endian = ">"
    else:
        raise ValueError("%s is not a pcap file" % path)
    off = 24
    while off + 16 <= len(data):
        incl = struct.unpack(endian + "I", data[off + 8:off + 12])[0]
        off += 16
        yield data[off:off + incl]
        off += incl


def summarize(path, mac):
    me = bytes(int(x, 16) for x in mac.split(":"))
    s = {"from_guest": 0, "to_guest": 0,
         "arp_replies_to_guest": 0, "icmp_replies_to_guest": 0}
    for fr in frames(path):
        if len(fr) < 14:
            continue
        dst, src = fr[0:6], fr[6:12]
        etype = struct.unpack(">H", fr[12:14])[0]
        if src == me:
            s["from_guest"] += 1
            continue
        if dst != me:
            continue
        s["to_guest"] += 1
        if etype == 0x0806 and len(fr) >= 22 \
                and struct.unpack(">H", fr[20:22])[0] == 2:
            s["arp_replies_to_guest"] += 1
        if etype == 0x0800 and len(fr) >= 15:
            ihl = (fr[14] & 0x0F) * 4
            if len(fr) > 14 + ihl and fr[23] == 1 and fr[14 + ihl] == 0:
                s["icmp_replies_to_guest"] += 1
    return s


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    s = summarize(argv[1], argv[2])
    for key in sorted(s):
        print("%s %d" % (key, s[key]))
    return 0 if s["from_guest"] and s["to_guest"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
