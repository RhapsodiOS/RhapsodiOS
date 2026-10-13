"""Portable tools must use precisely the kernel admission codec."""
from pathlib import Path

def test_shared_codec_matches():
    root = Path(__file__).resolve().parents[1]
    for name in ("ext2_disk.c", "ext2fs_bswap.c"):
        assert (root / "src/ext2fs-1/common" / name).read_bytes() == (root / "src/kernel-7/bsd/ext2fs" / name).read_bytes()
