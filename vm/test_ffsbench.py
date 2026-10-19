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


def test_qemu_args_throttles_only_hd1():
    args = fb.qemu_args("r", "h1", "h2", "s", iops=100)
    assert "throttling.iops-total=100" in _drive(args, 1)
    assert "throttling" not in _drive(args, 0)
    assert "throttling" not in _drive(args, 2)
    assert "throttling" not in " ".join(fb.qemu_args("r", "h1", "h2", "s"))


def test_boot_failure_is_skipped_not_fatal(tmp_path, monkeypatch):
    def fail(*a):
        raise SystemExit("sshd never answered on mach_kernel_ffs")
    monkeypatch.setattr(fb, "boot_test_kernel", fail)
    assert fb.boot_or_skip(None, None, "k", "", str(tmp_path)) is False
    assert "bootfail" in (tmp_path / "result.txt").read_text()


def test_wrong_kernel_stays_fatal(tmp_path, monkeypatch):
    def wrong(*a):
        raise SystemExit("WRONG KERNEL: booted 'a', wanted 'b'")
    monkeypatch.setattr(fb, "boot_test_kernel", wrong)
    with pytest.raises(SystemExit):
        fb.boot_or_skip(None, None, "k", "", str(tmp_path))


def test_qemu_args_can_throttle_the_root_disk():
    args = fb.qemu_args("r", "h1", "h2", "s", root_iops=100)
    assert "throttling.iops-total=100" in _drive(args, 0)
    assert "throttling" not in _drive(args, 1)


def test_run_command_targets_hd1_by_default():
    cmd = fb.run_command("run.sh")
    assert cmd.endswith("sh /tmp/ffsbench/run.sh /mnt2 /mnt1")


def test_run_command_single_disk_targets_the_root():
    cmd = fb.run_command("run.sh", single=True)
    assert "mkdir -p /private/tmp/ffsbench-root" in cmd
    assert cmd.endswith("sh /tmp/ffsbench/run.sh /mnt2 /private/tmp/ffsbench-root")


def test_qemu_extra_args_are_appended():
    args = fb.qemu_args("r", "h1", "h2", "s", extra="-d cpu_reset -D x.log")
    assert args[-4:] == ["-d", "cpu_reset", "-D", "x.log"]


def test_rbuild_start_command_runs_in_background_with_probe():
    cmd = fb.rbuild_start_command()
    assert "rbuild kernel" in cmd and "--arch i386" in cmd
    assert "/tmp/ffsbench/rbuild.log" in cmd
    assert "nohup" in cmd and cmd.rstrip().endswith("&)")


def test_stall_summary():
    s = fb.stall_summary([1.2, 3.4, None, 2.0], limit=120)
    assert s == {"logins": 4, "login_max_s": 3.4, "login_median_s": 2.0,
                 "login_timeouts": 1}


def test_rbuild_start_command_records_exit_status():
    assert "RBUILD-EXIT $?" in fb.rbuild_start_command()


def test_run_script_writes_a_manifest_after_the_replay():
    text = open(os.path.join(SCRIPTS, "run.sh")).read()
    i, j = text.index("echo REPLAY-END"), text.index("rm -rf $T/root")
    assert "manifest.txt" in text[i:j] and "cksum" in text[i:j]


def test_no_update_command_kills_update_and_checks():
    cmd = fb.no_update_command()
    assert "kill" in cmd and "update" in cmd
    assert "UPDATE-GONE" in cmd


def test_push_retries_a_dropped_connection(tmp_path, monkeypatch):
    src = tmp_path / "f"
    src.write_bytes(b"abc")
    calls = []

    def run(self, command, stdin=None, on_line=None):
        calls.append(command)
        if len(calls) == 1:
            return 255, "kex_exchange_identification: read: Connection aborted"
        return 0, "3"
    monkeypatch.setattr(fb.Ssh, "run", run)
    monkeypatch.setattr(fb.time, "sleep", lambda s: None)
    fb.Ssh({"User": "u", "Host": "h"}).push(str(src), "/tmp/f")
    assert len(calls) == 2


def test_run_script_remounts_hd1_before_the_manifest():
    text = open(os.path.join(SCRIPTS, "run.sh")).read()
    i, j = text.index("echo REPLAY-END"), text.index("manifest.txt")
    assert "umount /mnt1" in text[i:j] and "mount /dev/hd1a /mnt1" in text[i:j]


def test_guest_memory_comes_from_the_environment(monkeypatch):
    assert fb.guest_mem(None) == 128
    assert fb.guest_mem("512") == 512


def test_a_refused_login_counts_as_failed():
    assert fb.login_ok(0, "Building build root:") is True
    assert fb.login_ok(255, "kex_exchange_identification: read: Connection aborted") is False
    assert fb.login_ok(255, "") is False


def test_stress_state():
    assert fb.stress_state(None, "") == "lost"
    assert fb.stress_state(1.0, "") == "running"
    assert fb.stress_state(1.0, "\n") == "running"
    assert fb.stress_state(1.0, "3\n") == "3"


def test_stress_records_replay_fields_when_the_guest_cannot_start(tmp_path, monkeypatch):
    import json
    out = tmp_path / "stress-0"

    def hd1(outdir):
        os.makedirs(outdir, exist_ok=True)
        (out / "hd1.img").write_bytes(b"")
        return str(out / "hd1.img")

    def no_guest(*a, **k):
        raise RuntimeError("qemu missing")
    monkeypatch.setattr(fb, "_new_outdir", lambda label, name: str(out))
    monkeypatch.setattr(fb, "_conf", lambda: None)
    monkeypatch.setattr(fb, "_fresh_hd1", hd1)
    monkeypatch.setattr(fb, "_workload", lambda: "w")
    monkeypatch.setattr(fb, "Guest", no_guest)
    with pytest.raises(RuntimeError):
        fb.stress(None, "lab", seed=7)
    res = json.loads((out / "result.txt").read_text())
    assert (res["seed"], res["label"], res["kernel"]) == (7, "lab", "image")
    assert "qemu missing" in res["error"]
    assert not (out / "hd1.img").exists()


def test_stress_run_command():
    cmd = fb.stress_run_command(["ipc"], 1, 7, False)
    assert "-s 7" in cmd and "ipc" in cmd and "-D" not in cmd
    cmd = fb.stress_run_command(["ipc", "disk"], 1, 7, True)
    assert "-D /dev/rhd1a" in cmd and "ipc disk" in cmd


def test_devzero_command():
    assert fb.DEVZERO.startswith("test -c /dev/zero")
    assert "mknod /dev/zero c 3 3" in fb.DEVZERO


def test_stress_soak_command():
    cmd = fb.stress_soak_command(600, 7)
    assert "/usr/local/stress/soak -s 7 -t 600 -d /mnt1" in cmd
    assert cmd.endswith("echo $? > /tmp/stress.exit' > /tmp/stress.log 2>&1 &)")


def test_stress_cats_adds_disk_once():
    assert fb.stress_cats("disk", True) == ["disk"]
    assert fb.stress_cats("vm", True) == ["vm", "disk"]
    assert fb.stress_cats("", True)[-1] == "disk"


def test_stress_cats_disk_needs_the_flag():
    with pytest.raises(SystemExit):
        fb.main(["ffsbench", "stress", "--label", "x", "--cats", "disk"])


def test_stress_disk_conflicts_with_fs():
    with pytest.raises(SystemExit):
        fb.main(["ffsbench", "stress", "--label", "x", "--disk", "--cats", "vm fs"])


def test_stress_state_ignores_ssh_noise():
    warn = "Warning: Permanently added '10.10.0.240' to the list of known hosts."
    assert fb.stress_state(1.0, warn) == "running"
    assert fb.stress_state(1.0, warn + "\n0\n") == "0"
    assert fb.stress_state(1.0, "137") == "137"


# --- phase 4: --fs targets -------------------------------------------------

def test_parse_fs_defaults_and_all():
    assert fb.parse_fs("") == ["ufs"]
    assert fb.parse_fs("ufs") == ["ufs"]
    assert fb.parse_fs("all") == ["ufs", "ext2", "hfs", "msdos", "nfs"]
    assert fb.parse_fs("ext2,msdos") == ["ext2", "msdos"]


def test_parse_fs_rejects_unknown():
    with pytest.raises(ValueError):
        fb.parse_fs("ext2,bogus")


def test_targets_disk_has_three_128m_partitions(tmp_path, monkeypatch):
    import struct
    # the floppy label template lives with the VM assets, like stress_dev's default
    assets = os.environ.get("RHAP_VM_ASSETS", "D:/RhapsodiOS/vm")
    if not os.path.exists(os.path.join(assets, "install", "rhapsody_dr2_x86_InstallationFloppy.img")):
        pytest.skip("no VM assets")
    monkeypatch.setattr(fb, "ASSETS", assets)
    path = str(tmp_path / "t.img")
    fb.targets_disk(path, mb=1)
    raw = open(path, "rb").read()
    off = raw.index(b"dlV3")
    sectors = 1024 * 1024 // 512
    assert struct.unpack_from(">ii", raw, off + 190) == (0, sectors)
    assert struct.unpack_from(">ii", raw, off + 236) == (sectors, sectors)
    assert struct.unpack_from(">ii", raw, off + 282) == (2 * sectors, sectors)
    assert fb.TARGET_PART == {"ext2": "a", "hfs": "b", "msdos": "c"}
    assert fb.TARGET_MOUNT["nfs"] == "/mnt/nfs"


def test_target_result_unsup_and_ran():
    u = fb.target_result("hfs", "unsup", reason="mount_hfs: no such device")
    assert u == {"status": "unsup", "reason": "mount_hfs: no such device",
                 "counts": {}, "fails": [], "fsck": ""}
    text = ("STRESS fs rw PASS iters=1 procs=1 secs=1.0 ops=1/s maxlat=1ms seed=1\n"
            "STRESS fs tree FAIL reason=x worker=0 iter=0 seed=1\n")
    r = fb.target_result("ext2", "ran", report_text=text, fsck="clean")
    assert r["status"] == "ran" and r["fsck"] == "clean"
    assert r["counts"]["fs"]["PASS"] == 1 and r["counts"]["fs"]["FAIL"] == 1
    assert r["fails"] == ["STRESS fs tree FAIL reason=x worker=0 iter=0 seed=1"]


def test_stress_fs_conflicts_with_soak(capsys):
    with pytest.raises(SystemExit):
        fb.main(["ffsbench", "stress", "--label", "x", "--fs", "ext2", "--soak", "60"])
    assert "--soak runs on UFS only" in capsys.readouterr().err


def test_stress_fs_rejects_unknown_target(capsys):
    with pytest.raises(SystemExit):
        fb.main(["ffsbench", "stress", "--label", "x", "--fs", "zfs"])
    assert "unknown --fs target" in capsys.readouterr().err


def test_fs_src_tar_has_the_tool_sources_and_no_e2fsprogs():
    import io
    import tarfile
    names = tarfile.open(fileobj=io.BytesIO(fb.fs_src_tar())).getnames()
    assert "src/msdosfs-1/msdos_newfs/newfs_msdos.c" in names
    assert "src/hfs-1/hfs_newfs/newfs_hfs.c" in names
    assert "src/kernel-7/bsd/dev/disk.h" in names
    assert not any(n.endswith("e2fsprogs-1.35.tar.gz") for n in names)


def test_stress_fs_command_runs_ufs_then_each_target():
    c = fb.stress_fs_command(["ufs", "ext2", "nfs"], "fs mmap", 7)
    assert c.index("/usr/local/stress/run -a -s 7 -d /mnt1") < c.index("stress_fs.sh run ext2 ")
    assert c.index("stress_fs.sh run ext2") < c.index("stress_fs.sh run nfs")
    assert ">> /tmp/stressfs.out" in c and "/tmp/stress.exit" in c
    assert "/usr/local/stress/run" not in fb.stress_fs_command(["msdos"], "fs", 7)


def test_parse_stressfs_unsup_and_lost():
    text = ('BUILD mount_hfs ok\n'
            'STRESSFS ext2 status=ran reason="" fsck="host"\n'
            'STRESSFS hfs status=unsup reason="mount: mount_hfs: Input/output error" fsck=""\n')
    r = fb.parse_stressfs(text, ["ext2", "hfs", "msdos"])
    assert r["ext2"] == ("ran", "", "host")
    assert r["hfs"] == ("unsup", "mount: mount_hfs: Input/output error", "")
    assert r["msdos"] == ("lost", "no result: the guest stopped answering or the run ended first", "")


def test_assemble_targets_ran_unsup_lost_and_fsck():
    tout = ('STRESSFS ext2 status=ran reason="" fsck="host"\n'
            'STRESSFS hfs status=unsup reason="mount: no" fsck=""\n'
            'STRESSFS msdos status=ran reason="" fsck="clean"\n')
    texts = {"ext2": "STRESS fs rw PASS iters=1 procs=1 secs=1.0 ops=1/s maxlat=1ms seed=1\n"}
    r = fb.assemble_targets(tout, texts, ["ext2", "hfs", "msdos", "nfs"], lambda name: "clean-" + name)
    assert r["ext2"]["status"] == "ran" and r["ext2"]["fsck"] == "clean-ext2"
    assert r["ext2"]["counts"]["fs"]["PASS"] == 1
    assert r["hfs"]["status"] == "unsup" and r["hfs"]["reason"] == "mount: no"
    assert r["msdos"]["fsck"] == "clean"
    assert r["nfs"]["status"] == "lost"


def test_assemble_targets_reports_a_failed_fetch():
    tout = 'STRESSFS ext2 status=ran reason="" fsck="clean"\n'
    r = fb.assemble_targets(tout, {}, ["ext2"], lambda name: "x")
    assert r["ext2"]["reason"] == "results could not be fetched"


def test_need_fetch_retries_an_empty_result():
    assert fb.need_fetch("ext2", {"ext2": ""})
    assert not fb.need_fetch("ext2", {"ext2": "STRESS x"})
    assert fb.need_fetch("hfs", {})


def test_ext2_unavailable_makes_only_ext2_unsup(monkeypatch):
    def boom(workdir, mb=128):
        raise OSError("wsl: not found")
    monkeypatch.setattr(fb, "ext2_volume", boom)
    vol, why = fb.try_ext2_volume("/nonexistent")
    assert vol is None and "wsl: not found" in why


def test_print_lines_survives_a_console_that_cannot_encode():
    import io
    raw = io.BytesIO()
    out = io.TextIOWrapper(raw, encoding="cp1252")
    fb.print_lines(["msdos fsck=/t[.Å←T", "ok"], out)
    out.flush()
    assert raw.getvalue().splitlines()[1] == b"ok"
