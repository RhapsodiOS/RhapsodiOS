import importlib.util
import os
import tempfile

import pytest

import make_badfs
import rhap_image
import ufs_build
import ufs_check
import ufs_extract

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")

pytestmark = pytest.mark.skipif(not os.path.exists(make_badfs.TEMPLATE),
                                reason="install floppy template not present")


def _load():
    spec = importlib.util.spec_from_file_location(
        "ufs_e2e_image", os.path.join(HERE, "ufs-e2e-image.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _image_with_kernel(d, data):
    N = ufs_extract.Node
    path = os.path.join(d, "k.img")
    with open(path, "wb") as f:
        f.write(ufs_build.build(make_badfs.TEMPLATE, [
            N("/", "dir", 0o040755, 0, 0, 0, None),
            N("/mach_kernel", "reg", 0o100444, 0, 0, 0, data)]))
    return path


def test_install_kernel_rewrites_the_same_inode_consistently():
    m = _load()
    old = bytes(range(256)) * 400                # 100 KB
    new = bytes(reversed(range(256))) * 900      # 225 KB, so it must allocate
    os.makedirs(WORK, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=WORK) as d:
        path = _image_with_kernel(d, old)
        with rhap_image.Image(path) as img:
            before = img.resolve("/mach_kernel")
        assert m.install_kernel(path, new) == before
        with rhap_image.Image(path) as img:
            ino = img.resolve("/mach_kernel")
            inode = img.inode(ino)
            assert ino == before
            assert inode.mode == 0o100444
            assert inode.nlink == 1
            assert img.read_file(ino) == new
        assert ufs_check.check(path) == []


def test_main_refuses_an_existing_output():
    m = _load()
    os.makedirs(WORK, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=WORK) as d:
        out = os.path.join(d, "exists.img")
        open(out, "wb").close()
        assert m.main(["ufs-e2e-image.py", "unread-golden.img",
                       "unread-kernel", out]) == 1
        assert os.path.getsize(out) == 0


def test_main_refuses_an_output_outside_vm_work():
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "outside.img")
        assert m.main(["ufs-e2e-image.py", "unread-golden.img",
                       "unread-kernel", out]) == 1
        assert not os.path.exists(out)


def test_main_removes_a_partial_copy(monkeypatch):
    m = _load()
    os.makedirs(WORK, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=WORK) as d:
        golden = os.path.join(d, "golden.img")
        kernel = os.path.join(d, "kernel")
        out = os.path.join(d, "out.img")
        # Write minimal files so main can read them
        with open(golden, "wb") as f:
            f.write(b"golden" * 1000)
        with open(kernel, "wb") as f:
            f.write(b"kernel")

        # Replace shutil.copyfile with one that fails partway
        def failing_copyfile(src, dst):
            with open(dst, "wb") as f:
                f.write(b"partial")
            raise OSError("disk full")

        monkeypatch.setattr(m.shutil, "copyfile", failing_copyfile)

        # main should raise the OSError
        with pytest.raises(OSError, match="disk full"):
            m.main(["ufs-e2e-image.py", golden, kernel, out])

        # The partial file should be cleaned up
        assert not os.path.exists(out)
