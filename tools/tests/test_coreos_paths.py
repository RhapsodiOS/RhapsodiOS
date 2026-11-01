"""Host-side path checks; no Rhapsody SDK or compiler required."""
from pathlib import Path
import re
import shlex
import subprocess

import unittest

ROOT = Path(__file__).resolve().parents[2]
BOOTEFI = ROOT / 'src/CoreOS/bootefi-1'


def check_bootefi_make_include_paths():
    # Ask make to expand its variables without invoking the compiler.
    result = subprocess.run(
        ['make', '-s', '-f', 'Makefile', '-f', '-', 'check-paths'],
        cwd=BOOTEFI, input='check-paths:\n\t@echo $(CFLAGS)\n',
        text=True, capture_output=True, check=True,
    )
    includes = [arg[2:] for arg in shlex.split(result.stdout)
                if arg.startswith('-I')]
    assert includes
    for include in includes:
        assert (BOOTEFI / include).is_dir(), include
    assert (BOOTEFI / 'vendor_includes/objc/objc.h').is_file()


def check_installer_command_paths(name):
    text = (ROOT / 'docs/build' / name).read_text()
    # Follow the documented cd commands, without running builds/image writes.
    block = next(block for block in re.findall(r'```bash\n(.*?)```', text, re.S)
                 if 'cd src/CoreOS/bootefi-1' in block)
    cwd = ROOT
    for line in block.splitlines():
        args = shlex.split(line)
        if args[:1] == ['cd']:
            cwd = (cwd / args[1]).resolve()
            assert cwd.is_dir(), str(cwd)
        for arg in args:
            if arg.startswith('CCTOOLS='):
                headers = cwd / arg.split('=', 1)[1]
                assert (headers / 'mach-o/loader.h').is_file(), str(headers)
            if arg == 'instmedia.collect':
                assert cwd == ROOT / 'vm'
            if arg == '--efi':
                artifact = cwd / args[args.index(arg) + 1]
                assert artifact.parent.parent.resolve() == BOOTEFI


class CoreOSPathsTest(unittest.TestCase):
    def test_bootefi_make_include_paths(self):
        check_bootefi_make_include_paths()

    def test_installer_command_paths(self):
        for name in ('instmedia-cd.md', 'instmedia-live.md', 'sysinstall.md'):
            with self.subTest(document=name):
                check_installer_command_paths(name)


if __name__ == '__main__':
    unittest.main()
