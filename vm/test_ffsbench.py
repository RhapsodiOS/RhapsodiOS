"""Host-side tests for ffsbench.py; nothing here boots a guest."""

import ffsbench as fb
from ffsbench import ProbeSample


def _drive(args, index):
    for i, a in enumerate(args):
        if a == "-drive" and ("index=%d," % index) in args[i + 1]:
            return args[i + 1]
    raise AssertionError("no drive %d in %r" % (index, args))


def test_qemu_args_snapshot_only_root():
    args = fb.qemu_args("root.img", "hd1.img", "hd2.img", "serial.log")
    assert "-snapshot" not in args
    assert "snapshot=on" in _drive(args, 0)
    assert "snapshot=off" in _drive(args, 1)
    assert "snapshot=off" in _drive(args, 2)
    assert args[args.index("-m") + 1] == "128"
    joined = " ".join(args)
    assert "hostfwd=tcp:127.0.0.1:2532-10.10.0.240:22" in joined
    assert args[args.index("-gdb") + 1] == "tcp:127.0.0.1:1232"
    assert args[args.index("-qmp") + 1] == "tcp:127.0.0.1:4532,server=on,wait=off"


def test_parse_probe():
    assert fb.parse_probe("wp 17 2350 412 8812") == ProbeSample(17, 2350, 412, 8812)
    assert fb.parse_probe("garbage") is None
    assert fb.parse_probe("wp 1 2") is None


def test_summarize():
    samples = [ProbeSample(i, late, 100, 0) for i, late in enumerate([10, 20, 3000])]
    s = fb.summarize(samples, [0.1, None, 1.5])
    assert s["late_max_ms"] == 3000
    assert s["banner_max_s"] == 1.5
    assert s["banner_missed"] == 1


def test_classify_destroyed():
    assert fb.classify("** /dev/hd1a\nBAD SUPER BLOCK: MAGIC NUMBER WRONG\n", 8) == "destroyed"


CLEAN = ("** /dev/hd1a (NO WRITE)\n"
         "** Last Mounted on /mnt1\n"
         "** Phase 1 - Check Blocks and Sizes\n"
         "** Phase 2 - Check Pathnames\n"
         "** Phase 3 - Check Connectivity\n"
         "** Phase 4 - Check Reference Counts\n"
         "** Phase 5 - Check Cyl groups\n"
         "12 files, 30 used, 900 free (20 frags, 110 blocks, 0.1% fragmentation)\n")


def test_classify_clean():
    assert fb.classify(CLEAN, 0) == "clean"


def test_classify_preen():
    text = CLEAN + "FREE BLK COUNT(S) WRONG IN SUPERBLK\nSALVAGE? no\n"
    assert fb.classify(text, 0) == "preen"


def test_unknown_fsck_text_is_manual():
    assert fb.classify("something new\n", 8) == "manual"


def test_crash_before_replay_start_is_invalid():
    assert fb.crash_valid("booted\n") is False
    assert fb.crash_valid("x\nREPLAY-START\n") is True


def test_silence_triggers_hardlock():
    w = fb.Watchdog(60)
    w.feed(100)
    assert w.expired(159.9) is False
    assert w.expired(160.1) is True


def test_csv_row_matches_header():
    assert fb.CSV_HEADER == ("label,replay_s,rm_s,slow1_mbs,slow2_mbs,"
                             "late_max_ms,late_p99_ms,banner_max_s,banner_missed")
    run = {"replay_s": 100, "rm_s": 20, "slow1_mbs": 5.5, "slow2_mbs": 4.0,
           "late_max_ms": 3000, "late_p99_ms": 900, "banner_max_s": 1.5,
           "banner_missed": 1}
    assert fb.csv_row("x", run).count(",") == fb.CSV_HEADER.count(",")


# --- Task 2: disks and guest scripts --------------------------------------

import os
import struct

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "..", "tests", "ffsbench")


def _labels(path):
    with open(path, "rb") as f:
        head = f.read(32768)
    return [off for off in fb.LABEL_OFFSETS if head[off:off + 4] == b"dlV3"]


def test_build_scratch_label(tmp_path):
    if not os.path.exists(fb.label_template()):
        pytest.skip("installation floppy template is not present")
    path = str(tmp_path / "scratch.img")
    fb.build_scratch(path, mb=4)
    copies = _labels(path)
    assert copies
    with open(path, "rb") as f:
        head = f.read(32768)
    for off in copies:
        # 1024-byte label sectors, as on the installed root disk
        assert struct.unpack_from(">i", head, off + 92)[0] == 1024        # dl_secsize
        assert struct.unpack_from(">i", head, off + 194)[0] == 4 * 1024   # p_size
    assert os.path.getsize(path) == fb.label_front() + 4 * 1024 * 1024


def test_run_script_prints_every_marker():
    text = open(os.path.join(SCRIPTS, "run.sh")).read()
    for marker in fb.RUN_MARKERS:
        assert "echo " + marker in text or "echo \"" + marker in text, marker


def test_crash_script_stops_at_replay():
    text = open(os.path.join(SCRIPTS, "crash.sh")).read()
    assert "REPLAY-START" in text
    assert "RM-END" not in text and "SLOW1" not in text


def test_wakeprobe_prints_probe_format():
    text = open(os.path.join(SCRIPTS, "wakeprobe.c")).read()
    assert r'"wp %d %d %d %d\n"' in text
    assert "vm_statistics" in text


# --- Task 4: bench and crash drivers --------------------------------------

import socket
import threading


STAMP_A = "Mon Oct  5 22:00:53 PDT 2026; root(rcbuilder):kernel-154.5.1-7.obj/RELEASE_I386"
STAMP_B = "Fri Sep 18 12:06:49 PDT 2026; root(rcbuilder):kernel-154.5.1-7.obj/RELEASE_I386"


def test_kernel_stamp():
    kernel = b"\0Kernel Release 5.3:\0" + STAMP_A.encode() + b"\0more"
    assert fb.kernel_stamp(kernel) == STAMP_A
    assert fb.kernel_stamp(b"no stamp here") is None


def test_kernel_stamp_takes_the_last_boot_in_a_serial_log():
    serial = "Kernel Release 5.3:\r\n%s\r\n...\r\nKernel Release 5.3:\r\n%s\r\n" % (
        STAMP_B, STAMP_A)
    assert fb.kernel_stamp(serial) == STAMP_A


def test_kernel_stamp_mismatch_refuses():
    with pytest.raises(SystemExit):
        fb.check_stamp("boot\r\n%s\r\n" % STAMP_B, STAMP_A.encode())
    fb.check_stamp("boot\r\n%s\r\n" % STAMP_A, b"xx" + STAMP_A.encode() + b"\0")


def _serve_once(payload):
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)

    def run():
        conn, _ = srv.accept()
        if payload:
            conn.sendall(payload)
        threading.Event().wait(2)
        conn.close()
        srv.close()
    threading.Thread(target=run, daemon=True).start()
    return srv.getsockname()[1]


def test_banner_time_against_local_server():
    t = fb.banner_time(_serve_once(b"SSH-2.0-x\r\n"))
    assert t is not None and t < 1
    assert fb.banner_time(_serve_once(b""), timeout=1) is None


def test_ssh_argv_puts_port_first():
    conf = {"Host": "127.0.0.1", "User": "root", "Ssh": "ssh.exe", "Port": "2222"}
    argv = fb.ssh_argv(conf, 2532, "echo hi")
    assert argv[:4] == ["ssh.exe", "-T", "-p", "2532"]
    assert "Port=2222" not in " ".join(argv)
    assert argv[-2:] == ["root@127.0.0.1", "/bin/sh -c 'echo hi'"]


def test_ssh_argv_runs_under_sh_not_the_login_csh():
    conf = {"Host": "h", "User": "u"}
    assert fb.ssh_argv(conf, 1, "echo $? 2>&1")[-1] == "/bin/sh -c 'echo $? 2>&1'"
    assert fb.ssh_argv(conf, 1, "echo 'a'")[-1] == r"""/bin/sh -c 'echo '\''a'\'''"""


def test_boot_line():
    # the test kernel is installed as /mach_kernel itself: kernload links
    # drivers against /mach_kernel's symbols, so any other name hangs at
    # "Configuring device drivers".  The line is typed only for boot args.
    assert fb.boot_line("") is None
    assert fb.boot_line("bufpages=1638") == "mach_kernel bufpages=1638"


def test_lane_defaults():
    assert fb.lane(None) == (2532, 4532, 1232, "workload.img")


def test_second_lane_has_its_own_ports_and_workload_copy():
    assert fb.lane("2533,4533,1233") == (2533, 4533, 1233, "workload-2533.img")


def test_qemu_args_uses_the_lane_ports():
    args = fb.qemu_args("r", "h1", "h2", "s", ssh_port=2533, qmp_port=4533,
                        gdb_port=1233)
    assert "hostfwd=tcp:127.0.0.1:2533-10.10.0.240:22" in " ".join(args)
    assert args[args.index("-gdb") + 1] == "tcp:127.0.0.1:1233"
