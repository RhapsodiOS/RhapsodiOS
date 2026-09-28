import importlib.util
import os
import shutil
import subprocess
import tempfile

import pytest

import make_badfs
import ufs_gap_lib as lib

HERE = os.path.dirname(os.path.abspath(__file__))

needs_qemu = pytest.mark.skipif(
    not (shutil.which("qemu-img") and shutil.which("qemu-io")
         and os.path.exists(make_badfs.TEMPLATE)),
    reason="needs qemu-img, qemu-io and the install floppy template")


def _load():
    spec = importlib.util.spec_from_file_location(
        "ufs_e2e_boot", os.path.join(HERE, "ufs-e2e-boot.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def test_dirty_args_write_one_zero_byte():
    overlay = os.path.join("x", "disk.qcow2")
    assert _load().dirty_args(overlay, 106705) == [
        "qemu-io", "-f", "qcow2", "-c", "write -P 0 106705 1",
        os.path.abspath(overlay)]


@needs_qemu
def test_new_dirty_changes_the_overlay_and_not_the_base(monkeypatch):
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        base = os.path.join(d, "base.img")
        make_badfs.build_good(base)
        monkeypatch.setattr(lib, "WORK", d)
        m.new(base, "t", dirty=True)
        flat = os.path.join(d, "flat.img")
        subprocess.run(["qemu-img", "convert", "-O", "raw",
                        os.path.join(d, "t", "disk.qcow2"), flat], check=True)
        assert make_badfs.read_field(flat, "fs_clean") == 0
        assert make_badfs.read_field(flat, "fs_magic") == 0x00011954
        assert make_badfs.read_field(base, "fs_clean") == 1


@needs_qemu
def test_new_refuses_to_reuse_an_overlay(monkeypatch):
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        base = os.path.join(d, "base.img")
        make_badfs.build_good(base)
        monkeypatch.setattr(lib, "WORK", d)
        m.new(base, "t", dirty=False)
        with pytest.raises(SystemExit):
            m.new(base, "t", dirty=False)
