"""DragonFly reference guest: command line, transfer disk, result parsing."""
import importlib.util

import pytest

_spec = importlib.util.find_spec('dfly_guest')
dg = None if _spec is None else __import__('dfly_guest')


@pytest.fixture(autouse=True)
def implementation_exists():
    assert dg is not None, 'dfly guest harness is not implemented'


def test_qemu_args_isolation(tmp_path):
    args = dg.qemu_args('dfly.iso', 'vol.img', 'xfer.img', 'dfly-abc', 4800, 4801)
    assert args[args.index('-name') + 1] == 'dfly-abc'
    assert 'tcp:127.0.0.1:4800,server=on,wait=off' in args
    assert 'tcp:127.0.0.1:4801,server=on,wait=off' in args
    drives = [args[i + 1] for i, a in enumerate(args) if a == '-drive']
    assert any('vol.img' in d and 'index=0' in d for d in drives)
    assert any('xfer.img' in d and 'index=1' in d for d in drives)
    assert any('dfly.iso' in d and 'media=cdrom' in d and 'readonly=on' in d for d in drives)


def test_rc_marker():
    out = 'noise\r\n__DFLY_RC=3__\r\n# '
    assert dg.parse_rc(out) == 3
    assert dg.parse_rc('no marker here') is None


def test_transfer_disk_roundtrip(tmp_path):
    import fat32
    img = tmp_path/'xfer.img'
    dg.make_transfer_disk(img, {'RUN.SH': b'echo hi\n', 'WALK.C': b'int main(){}\n'})
    assert fat32.read_file(img.read_bytes(), 'RUN.SH') == b'echo hi\n'
    assert fat32.read_file(img.read_bytes(), 'WALK.C') == b'int main(){}\n'


def test_run_refuses_existing_outdir(tmp_path):
    out = tmp_path/'run'
    out.mkdir()
    with pytest.raises(FileExistsError):
        dg.run_script('dfly.iso', tmp_path/'vol.img', 'true', out)
