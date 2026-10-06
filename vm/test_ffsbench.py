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
        assert struct.unpack_from(">i", head, off + 194)[0] == 4 * 2048   # p_size
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
