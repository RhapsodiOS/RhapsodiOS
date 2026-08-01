#!/usr/bin/env python3
"""Host-side contract tests for the AHCI build and q35 launch scripts."""

import os
import pathlib
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
import json


VM = pathlib.Path(__file__).resolve().parent
ROOT = VM.parent
BUILD = VM / "build-i386-kernel-ahci.sh"
RUN = VM / "run-q35-ahci.sh"
if str(VM) not in sys.path:
    sys.path.insert(0, str(VM))


class AHCIScriptTests(unittest.TestCase):
    def sh_path(self, path):
        value = str(path.resolve()).replace("\\", "/")
        if len(value) >= 3 and value[1:3] == ":/":
            return "/" + value[0].lower() + value[2:]
        return value

    def run_sh(self, script, *args, env=None):
        merged = os.environ.copy()
        git_usr_bin = pathlib.Path(r"C:\Program Files\Git\usr\bin")
        if git_usr_bin.is_dir():
            merged["PATH"] = str(git_usr_bin) + os.pathsep + merged["PATH"]
        merged["AHCI_PYTHON"] = self.sh_path(pathlib.Path(sys.executable))
        if env:
            merged.update(env)
        return subprocess.run(
            ["sh", script.relative_to(ROOT).as_posix(), *map(str, args)],
            cwd=ROOT,
            env=merged,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

    def test_build_runs_tests_then_stages_exact_fresh_artifacts(self):
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            source = td / "source"
            install = source / "vm" / "install"
            log = td / "make.log"
            fake_make = td / "gnumake"
            for rel in (
                "src/kernel-7/conf",
                "src/drivers-i386/ide/drvEIDE",
                "src/drivers-i386/ide/drvAHCI",
                "src/drivers-i386/ide/drvAHCI/tests",
                "vm",
            ):
                (source / rel).mkdir(parents=True)
            fake_make.write_text(
                "#!/bin/sh\n"
                "echo \"$PWD:$*\" >> \"$AHCI_TEST_LOG\"\n"
                "case \"$PWD\" in\n"
                "*/tests) exit 0 ;;\n"
                "*/kernel-7/conf)\n"
                "  case \" $* \" in *' I386 '*) mkdir -p ../BUILD/RELEASE_I386; "
                "printf kernel > ../BUILD/RELEASE_I386/mach_kernel;; esac ;;\n"
                "*/drvEIDE|*/drvAHCI)\n"
                "  case \" $* \" in *' install '*)\n"
                "    dst=; for a in \"$@\"; do case \"$a\" in DSTROOT=*) dst=${a#DSTROOT=};; esac; done\n"
                "    case \"$PWD\" in */drvEIDE) n=EIDE;; *) n=AHCI;; esac\n"
                "    mkdir -p \"$dst/private/Drivers/i386/$n.config\"\n"
                "    printf reloc > \"$dst/private/Drivers/i386/$n.config/${n}_reloc\"\n"
                "    printf table > \"$dst/private/Drivers/i386/$n.config/Default.table\";; esac ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            fake_make.chmod(0o755)
            fake_find = td / "find"
            fake_find.write_text(
                "#!/bin/sh\n"
                "artifact=$1; shift\n"
                "while [ $# -gt 0 ]; do\n"
                "  if [ \"$1\" = -newer ]; then marker=$2; shift 2; else shift; fi\n"
                "done\n"
                "\"$AHCI_PYTHON\" -c 'import os,sys; "
                "c=lambda s: (s[1].upper()+\":/\"+s[3:]) if len(s)>3 and s[0]==\"/\" and s[2]==\"/\" else s; "
                "print(sys.argv[1]) if os.path.getmtime(c(sys.argv[1])) > os.path.getmtime(c(sys.argv[2])) else None' "
                "\"$artifact\" \"$marker\"\n",
                encoding="utf-8",
            )
            fake_find.chmod(0o755)
            result = self.run_sh(
                BUILD,
                env={
                    "AHCI_SOURCE_ROOT": self.sh_path(source),
                    "AHCI_INSTALL_DIR": self.sh_path(install),
                    "AHCI_MAKE": self.sh_path(fake_make),
                    "AHCI_TEST_LOG": self.sh_path(log),
                    "PATH": self.sh_path(td) + ":" + os.environ["PATH"],
                },
            )
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(
                sorted(p.relative_to(install).as_posix() for p in install.rglob("*") if p.is_file()),
                [
                    "AHCI.config/AHCI_reloc",
                    "AHCI.config/Default.table",
                    "EIDE.config/Default.table",
                    "EIDE.config/EIDE_reloc",
                    "mach_kernel",
                ],
            )
            calls = log.read_text(encoding="utf-8").splitlines()
            self.assertTrue(calls[0].endswith("/tests:clean all check"), calls)
            kernel_call = next(x for x in calls if "/kernel-7/conf:" in x)
            self.assertIn("I386 OBJROOT=../BUILD SYMROOT=../BUILD", kernel_call)
            self.assertNotIn("kernels", kernel_call)
            self.assertLess(next(i for i, x in enumerate(calls) if "/kernel-7/conf:" in x),
                            next(i for i, x in enumerate(calls) if "/drvEIDE:" in x))
            self.assertLess(next(i for i, x in enumerate(calls) if "/drvEIDE:" in x),
                            next(i for i, x in enumerate(calls) if "/drvAHCI:" in x))

            stale_make = td / "stale-gnumake"
            stale_make.write_text(
                fake_make.read_text(encoding="utf-8")
                + "\nif [ \"${AHCI_TEST_STALE:-0}\" = 1 ]; then\n"
                  "  sleep 1\n"
                  "  echo newer >> \"$AHCI_BUILD_STARTED_MARKER\"\n"
                  "fi\n",
                encoding="utf-8",
            )
            stale_make.chmod(0o755)
            stale = self.run_sh(
                BUILD,
                env={
                    "AHCI_SOURCE_ROOT": self.sh_path(source),
                    "AHCI_INSTALL_DIR": self.sh_path(install),
                    "AHCI_MAKE": self.sh_path(stale_make),
                    "AHCI_TEST_LOG": self.sh_path(log),
                    "AHCI_TEST_STALE": "1",
                    "PATH": self.sh_path(td) + ":" + os.environ["PATH"],
                },
            )
            self.assertNotEqual(stale.returncode, 0, stale.stdout)
            self.assertIn("stale build output", stale.stdout)

            (td / "unrelated").mkdir()
            unsafe = self.run_sh(
                BUILD,
                env={
                    "AHCI_SOURCE_ROOT": self.sh_path(source),
                    "AHCI_INSTALL_DIR": self.sh_path(td / "unrelated" / "install"),
                    "AHCI_MAKE": self.sh_path(fake_make),
                    "AHCI_TEST_LOG": self.sh_path(log),
                    "PATH": self.sh_path(td) + ":" + os.environ["PATH"],
                },
            )
            self.assertNotEqual(unsafe.returncode, 0, unsafe.stdout)
            self.assertIn("exactly", unsafe.stdout)
            root_install = self.run_sh(
                BUILD,
                env={
                    "AHCI_SOURCE_ROOT": self.sh_path(source),
                    "AHCI_INSTALL_DIR": "/install",
                    "AHCI_MAKE": self.sh_path(fake_make),
                    "AHCI_TEST_LOG": self.sh_path(log),
                    "PATH": self.sh_path(td) + ":" + os.environ["PATH"],
                },
            )
            self.assertNotEqual(root_install.returncode, 0, root_install.stdout)
            self.assertIn("exactly", root_install.stdout)
            self.assertNotIn(" -nt ", BUILD.read_text(encoding="utf-8"))

    def test_launcher_dry_run_has_q35_ports_root_keys_and_logs(self):
        work_dir = VM / "work" / "script-test"
        shutil.rmtree(work_dir, ignore_errors=True)
        work_dir.mkdir(parents=True)
        self.addCleanup(lambda: shutil.rmtree(work_dir, ignore_errors=True))
        source = work_dir / "source.img"
        target = work_dir / "boot.img"
        second = work_dir / "second.img"
        iso = work_dir / "test.iso"
        for path in (source, second, iso):
            path.write_bytes(b"test")
        result = self.run_sh(RUN, "--dry-run", "--iso", self.sh_path(iso),
                             "--second-disk", self.sh_path(second),
                             self.sh_path(source), self.sh_path(target))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("\n  -M\n  q35\n", result.stdout)
        self.assertIn("bus=ide.0", result.stdout)
        self.assertIn("bus=ide.1", result.stdout)
        self.assertIn("bus=ide.2", result.stdout)
        self.assertIn("mach_kernel rootdev=hd0a", result.stdout)
        self.assertIn("vm/logs/ahci-serial.log", result.stdout.replace("\\", "/"))
        self.assertFalse(target.exists(), "dry-run must not create a working image")

        iso_only = self.run_sh(RUN, "--dry-run", "--iso", self.sh_path(iso),
                               self.sh_path(source), self.sh_path(target))
        self.assertEqual(iso_only.returncode, 0, iso_only.stdout)
        self.assertIn("bus=ide.2", iso_only.stdout)
        self.assertNotIn("bus=ide.1", iso_only.stdout)
        second_only = self.run_sh(
            RUN, "--dry-run", "--second-disk", self.sh_path(second),
            self.sh_path(source), self.sh_path(target))
        self.assertEqual(second_only.returncode, 0, second_only.stdout)
        self.assertIn("bus=ide.1", second_only.stdout)
        self.assertNotIn("bus=ide.2", second_only.stdout)

    def test_launcher_rejects_non_disposable_and_identical_targets(self):
        with tempfile.TemporaryDirectory() as td:
            source = pathlib.Path(td) / "source.img"
            source.write_bytes(b"source")
            outside = pathlib.Path(td) / "outside.img"
            result = self.run_sh(RUN, "--dry-run", self.sh_path(source),
                                 self.sh_path(outside))
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("vm/work", result.stdout)
        work_dir = VM / "work" / "script-test-identical"
        shutil.rmtree(work_dir, ignore_errors=True)
        work_dir.mkdir(parents=True)
        self.addCleanup(lambda: shutil.rmtree(work_dir, ignore_errors=True))
        image = work_dir / "same.img"
        image.write_bytes(b"source")
        result = self.run_sh(RUN, "--dry-run", self.sh_path(image),
                             self.sh_path(image))
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("distinct", result.stdout)

        source = work_dir / "source-under-work.img"
        target = work_dir / "different.img"
        source.write_bytes(b"source")
        target.write_bytes(b"old work")
        same_source = self.run_sh(
            RUN, "--dry-run", "--second-disk", self.sh_path(source),
            self.sh_path(source), self.sh_path(target))
        self.assertNotEqual(same_source.returncode, 0, same_source.stdout)
        self.assertIn("second disk must be distinct", same_source.stdout)
        same_work = self.run_sh(
            RUN, "--dry-run", "--second-disk", self.sh_path(target),
            self.sh_path(source), self.sh_path(target))
        self.assertNotEqual(same_work.returncode, 0, same_work.stdout)
        self.assertIn("second disk must be distinct", same_work.stdout)

    def test_qmp_helper_skips_events_and_unrelated_replies(self):
        import ahci_qmp_sendkeys

        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = server.getsockname()[1]

        def serve():
            conn, _ = server.accept()
            stream = conn.makefile("rwb", buffering=0)
            stream.write(b'{"QMP":{"version":{},"capabilities":[]}}\n')
            for _ in range(2):
                request = json.loads(stream.readline())
                stream.write(b'{"event":"RESET"}\n')
                stream.write(b'{"return":{},"id":999}\n')
                stream.write(json.dumps({"return": {}, "id": request["id"]}).encode() + b"\n")
            conn.close()
            server.close()

        thread = threading.Thread(target=serve)
        thread.start()
        ahci_qmp_sendkeys.send_keys("127.0.0.1", port, 0, "a", timeout=2)
        thread.join(2)
        self.assertFalse(thread.is_alive())

    def test_qmp_helper_rejects_error_reply(self):
        import ahci_qmp_sendkeys

        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = server.getsockname()[1]

        def serve():
            conn, _ = server.accept()
            stream = conn.makefile("rwb", buffering=0)
            stream.write(b'{"QMP":{"version":{},"capabilities":[]}}\n')
            request = json.loads(stream.readline())
            stream.write(json.dumps({"return": {}, "id": request["id"]}).encode() + b"\n")
            request = json.loads(stream.readline())
            stream.write(json.dumps({"error": {"class": "GenericError", "desc": "bad key"},
                                     "id": request["id"]}).encode() + b"\n")
            conn.close()
            server.close()

        thread = threading.Thread(target=serve)
        thread.start()
        with self.assertRaisesRegex(ahci_qmp_sendkeys.QMPError, "bad key"):
            ahci_qmp_sendkeys.send_keys("127.0.0.1", port, 0, "a", timeout=2)
        thread.join(2)
        self.assertFalse(thread.is_alive())

    def test_launcher_propagates_boot_key_helper_failure(self):
        work_dir = VM / "work" / "script-test-helper"
        shutil.rmtree(work_dir, ignore_errors=True)
        work_dir.mkdir(parents=True)
        self.addCleanup(lambda: shutil.rmtree(work_dir, ignore_errors=True))
        source = work_dir / "source.img"
        target = work_dir / "boot.img"
        source.write_bytes(b"source")
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            fake_python = td / "python"
            fake_qemu = td / "qemu"
            fake_mv = td / "mv"
            real_python = self.sh_path(pathlib.Path(sys.executable))
            fake_python.write_text(
                "#!/bin/sh\n"
                "case \"$1\" in */ahci_qmp_sendkeys.py) exit 7;; esac\n"
                f'exec "{real_python}" "$@"\n', encoding="utf-8")
            fake_qemu.write_text(
                "#!/bin/sh\ntrap 'exit 0' 15\nwhile :; do sleep 1; done\n",
                encoding="utf-8")
            fake_mv.write_text(
                "#!/bin/sh\ncp \"$2\" \"$3\" && rm -f \"$2\"\n",
                encoding="utf-8")
            for path in (fake_python, fake_qemu, fake_mv):
                path.chmod(0o755)
            env = {
                "AHCI_PYTHON": self.sh_path(fake_python),
                "AHCI_QEMU": self.sh_path(fake_qemu),
                "PATH": self.sh_path(td) + ":" + os.environ["PATH"],
            }
            result = self.run_sh(RUN, self.sh_path(source),
                                 self.sh_path(target), env=env)
            self.assertEqual(result.returncode, 7, result.stdout)
            self.assertIn("boot-key injection failed", result.stdout)

    def test_launcher_preserves_early_qemu_failure(self):
        work_dir = VM / "work" / "script-test-qemu-failure"
        shutil.rmtree(work_dir, ignore_errors=True)
        work_dir.mkdir(parents=True)
        self.addCleanup(lambda: shutil.rmtree(work_dir, ignore_errors=True))
        source = work_dir / "source.img"
        target = work_dir / "boot.img"
        source.write_bytes(b"source")
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            fake_python = td / "python"
            fake_qemu = td / "qemu"
            fake_mv = td / "mv"
            real_python = self.sh_path(pathlib.Path(sys.executable))
            fake_python.write_text(
                "#!/bin/sh\n"
                "case \"$1\" in */ahci_qmp_sendkeys.py) exit 7;; esac\n"
                f'exec "{real_python}" "$@"\n', encoding="utf-8")
            fake_qemu.write_text("#!/bin/sh\nexit 23\n", encoding="utf-8")
            fake_mv.write_text(
                "#!/bin/sh\ncp \"$2\" \"$3\" && rm -f \"$2\"\n",
                encoding="utf-8")
            for path in (fake_python, fake_qemu, fake_mv):
                path.chmod(0o755)
            result = self.run_sh(
                RUN, self.sh_path(source), self.sh_path(target), env={
                    "AHCI_PYTHON": self.sh_path(fake_python),
                    "AHCI_QEMU": self.sh_path(fake_qemu),
                    "PATH": self.sh_path(td) + ":" + os.environ["PATH"],
                })
            self.assertEqual(result.returncode, 23, result.stdout)
            self.assertIn("QEMU exited before boot-key injection", result.stdout)


if __name__ == "__main__":
    unittest.main()
