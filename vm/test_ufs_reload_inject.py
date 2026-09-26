import importlib.util
import os
import shutil
import subprocess
import tempfile

import pytest

import make_badfs

HERE = os.path.dirname(os.path.abspath(__file__))


def _load():
    spec = importlib.util.spec_from_file_location(
        "ufs_reload_inject", os.path.join(HERE, "ufs-reload-inject.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def test_blkdebug_config_names_both_sectors():
    c = _load().blkdebug_config(208, 2880)
    assert 'sector = "208"' in c
    assert 'sector = "2880"' in c
    assert c.count("[set-state]") == 2
    assert c.count("[inject-error]") == 2


@pytest.mark.skipif(not shutil.which("qemu-io"), reason="needs qemu-io")
def test_blkdebug_config_arms_and_disarms_under_qemu_io():
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        disk = os.path.join(d, "disk.raw")
        with open(disk, "wb") as f:
            f.write(bytes(1 << 20))
        conf = os.path.join(d, "blkdebug.conf")
        with open(conf, "w") as f:
            # error on sector 16; the dummy is sector 128, the one the host
            # writes to arm and disarm
            f.write(m.blkdebug_config(16, 128))
        opts = ("driver=raw,file.driver=blkdebug,file.config=%s,"
                "file.image.filename=%s"
                % (conf.replace("\\", "/"), disk.replace("\\", "/")))
        out = subprocess.run(
            ["qemu-io", "--image-opts",
             "-c", "read 8192 8192",     # before arming: fine
             "-c", "write 65536 512",    # arm
             "-c", "read 0 512",         # another sector: fine
             "-c", "read 8192 8192",     # covers sector 16: fails
             "-c", "read 8192 8192",     # a retry fails too
             "-c", "write 65536 512",    # disarm
             "-c", "read 8192 8192",     # fine again
             opts],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
        results = [l for l in out.splitlines()
                   if l.startswith(("read ", "wrote "))]
        assert results == [
            "read 8192/8192 bytes at offset 8192",
            "wrote 512/512 bytes at offset 65536",
            "read 512/512 bytes at offset 0",
            "read failed: Input/output error",
            "read failed: Input/output error",
            "wrote 512/512 bytes at offset 65536",
            "read 8192/8192 bytes at offset 8192"]


def test_drive_args_plain_and_through_blkdebug():
    m = _load()
    disk = os.path.abspath("t.img").replace("\\", "/")
    conf = os.path.abspath("b.conf").replace("\\", "/")
    assert m.drive_args("t.img") == [
        "-drive", "file=%s,format=raw,if=ide,index=1,media=disk" % disk]
    assert m.drive_args("t.img", "b.conf") == [
        "-drive",
        "file.driver=blkdebug,file.config=%s,file.image.filename=%s,"
        "format=raw,if=ide,index=1,media=disk,id=t1" % (conf, disk)]


def test_hmp_write_writes_one_sector_through_the_drive():
    assert _load().hmp_write(1474560) == 'qemu-io t1 "write -P 0 1474560 512"'


@pytest.mark.skipif(not os.path.exists(make_badfs.TEMPLATE),
                    reason="install floppy template not present")
def test_make_test_disk_is_dirty_and_padded():
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "test.img")
        assert m.make_test_disk(p) == 1474560
        assert os.path.getsize(p) == 1474560 + m.PAD
        assert make_badfs.read_field(p, "fs_clean") == 0
        assert make_badfs.read_field(p, "fs_magic") == 0x00011954
