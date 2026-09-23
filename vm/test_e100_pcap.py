"""Unit test for e100-pcap.py.

Run with: cd vm && python -m unittest test_e100_pcap -v
"""
import importlib.util
import os
import struct
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "e100_pcap", os.path.join(_HERE, "e100-pcap.py"))
pcap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pcap)

MAC = "52:54:00:12:34:56"
GUEST = bytes.fromhex("525400123456")
SLIRP = bytes.fromhex("52550a000202")
OTHER = bytes.fromhex("020000000001")
BCAST = b"\xff" * 6


def eth(dst, src, etype, payload):
    return dst + src + struct.pack(">H", etype) + payload


def arp(op):
    return struct.pack(">HHBBH", 1, 0x0800, 6, 4, op) + b"\0" * 20


def icmp(kind):
    ip = bytes([0x45, 0, 0, 28, 0, 0, 0, 0, 64, 1, 0, 0,
                10, 0, 2, 2, 10, 0, 2, 15])
    return ip + bytes([kind, 0, 0, 0, 0, 0, 0, 0])


def write_pcap(path, frames, big_endian=False):
    e = ">" if big_endian else "<"
    with open(path, "wb") as f:
        f.write(struct.pack(e + "IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for fr in frames:
            f.write(struct.pack(e + "IIII", 0, 0, len(fr), len(fr)))
            f.write(fr)


class SummarizeTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "t.pcap")

    def tearDown(self):
        self.dir.cleanup()

    def both_ways(self):
        return [eth(BCAST, GUEST, 0x0806, arp(1)),
                eth(GUEST, SLIRP, 0x0806, arp(2)),
                eth(SLIRP, GUEST, 0x0800, icmp(8)),
                eth(GUEST, SLIRP, 0x0800, icmp(0)),
                eth(OTHER, SLIRP, 0x0800, icmp(0))]

    def test_counts_both_directions(self):
        write_pcap(self.path, self.both_ways())
        s = pcap.summarize(self.path, MAC)
        self.assertEqual(s["from_guest"], 2)
        self.assertEqual(s["to_guest"], 2)
        self.assertEqual(s["arp_replies_to_guest"], 1)
        self.assertEqual(s["icmp_replies_to_guest"], 1)
        self.assertEqual(pcap.main(["e100-pcap.py", self.path, MAC]), 0)

    def test_one_direction_fails(self):
        write_pcap(self.path, [eth(BCAST, GUEST, 0x0806, arp(1))])
        self.assertEqual(pcap.main(["e100-pcap.py", self.path, MAC]), 1)

    def test_big_endian_file(self):
        write_pcap(self.path, self.both_ways(), big_endian=True)
        self.assertEqual(pcap.summarize(self.path, MAC)["to_guest"], 2)

    def test_not_a_pcap(self):
        with open(self.path, "wb") as f:
            f.write(b"\0" * 64)
        with self.assertRaises(ValueError):
            pcap.summarize(self.path, MAC)


if __name__ == "__main__":
    unittest.main()
