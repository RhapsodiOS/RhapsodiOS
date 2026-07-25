"""Unit test for qemu-shot.py's PPM parser and PNG writer.

Run with: python -m unittest vm.test_qemu_shot -v
(or: cd vm && python -m unittest test_qemu_shot -v)
"""
import importlib.util
import os
import struct
import tempfile
import unittest
import zlib

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load_qemu_shot():
    spec = importlib.util.spec_from_file_location("qemu_shot", os.path.join(_HERE, "qemu-shot.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


qemu_shot = _load_qemu_shot()


def _decode_png(path):
    """Minimal PNG decoder for PNGs produced by qemu_shot.write_png: a
    single IDAT chunk, filter type 0 (none) on every scanline, 8-bit RGB."""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    width = height = None
    idat = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        chunk_data = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, bitdepth, colortype = struct.unpack(">IIBB", chunk_data[:10])
            assert bitdepth == 8 and colortype == 2, "expected 8-bit RGB PNG"
        elif tag == b"IDAT":
            idat += chunk_data
        elif tag == b"IEND":
            break
        pos += 8 + length + 4  # length + tag + data + crc
    raw = zlib.decompress(idat)
    stride = width * 3 + 1
    pixels = bytearray()
    for y in range(height):
        row = raw[y * stride:(y + 1) * stride]
        assert row[0] == 0, "expected filter type 0 (none)"
        pixels += row[1:]
    return width, height, bytes(pixels)


class TestParsePpm(unittest.TestCase):
    def test_header_with_comment_and_pixels_roundtrip(self):
        width, height = 4, 3
        pixels = bytes((x * 7 + y * 13 + c) % 256 for y in range(height) for x in range(width) for c in range(3))

        ppm = (
            b"P6\n"
            b"# a comment line in the header\n"
            b"4 3\n"
            b"# another comment, with weird   spacing\n"
            b"255\n"
        ) + pixels

        width2, height2, maxval, parsed_pixels = qemu_shot.parse_ppm(ppm)
        self.assertEqual(width2, width)
        self.assertEqual(height2, height)
        self.assertEqual(maxval, 255)
        self.assertEqual(parsed_pixels, pixels)

        with tempfile.TemporaryDirectory() as tmpdir:
            png_path = os.path.join(tmpdir, "out.png")
            qemu_shot.write_png(png_path, width2, height2, parsed_pixels)

            png_w, png_h, png_pixels = _decode_png(png_path)
            self.assertEqual(png_w, width)
            self.assertEqual(png_h, height)
            self.assertEqual(png_pixels, pixels)

    def test_rejects_non_p6_magic(self):
        with self.assertRaises(ValueError):
            qemu_shot.parse_ppm(b"P3\n2 2\n255\n")


class TestCharsToQcodes(unittest.TestCase):
    def test_accepts_boot_prompt_characters(self):
        qemu_shot.chars_to_qcodes("-v\nmach_kernel")  # must not raise

    def test_rejects_unmapped_character(self):
        with self.assertRaises(ValueError):
            qemu_shot.chars_to_qcodes("@")


class TestFixKeysArg(unittest.TestCase):
    def test_rewrites_dash_value_to_equals_form(self):
        # argparse would otherwise mistake "-v" for another option.
        argv = ["image.img", "outdir", "--keys", "-v", "--keys-at", "3"]
        fixed = qemu_shot._fix_keys_arg(argv)
        self.assertEqual(fixed, ["image.img", "outdir", "--keys=-v", "--keys-at", "3"])

    def test_leaves_equals_form_untouched(self):
        argv = ["image.img", "outdir", "--keys=-v"]
        self.assertEqual(qemu_shot._fix_keys_arg(argv), argv)


if __name__ == "__main__":
    unittest.main()
