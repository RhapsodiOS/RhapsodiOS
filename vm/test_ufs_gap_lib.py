import os
import socket
import tempfile

import ufs_gap_lib as lib


def test_overlay_args_name_a_raw_backing_file():
    overlay = os.path.join("r", "disk.qcow2")
    assert lib.overlay_args("base.img", overlay) == [
        "qemu-img", "create", "-q", "-f", "qcow2", "-F", "raw",
        "-b", os.path.abspath("base.img"), os.path.abspath(overlay)]


def test_wait_for_sees_text_already_there():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "serial.log")
        with open(p, "w") as f:
            f.write("boot\nContinue without network? (y/n)")
        assert lib.wait_for(p, "Continue without network?", timeout=0, tick=0)


def test_wait_for_times_out_and_ticks_while_waiting():
    ticks = []
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "serial.log")
        with open(p, "w") as f:
            f.write("boot\n")
        assert not lib.wait_for(p, "never", timeout=0.05, tick=0.01,
                                on_tick=lambda: ticks.append(1))
    assert ticks


def test_wait_for_notices_text_written_between_polls():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "serial.log")
        open(p, "w").close()

        def tick():
            with open(p, "a") as f:
                f.write("initPointer: Can't find active pointer device\n")
        assert lib.wait_for(p, "initPointer:", timeout=5, tick=0, on_tick=tick)


def test_wait_for_tolerates_a_missing_file():
    with tempfile.TemporaryDirectory() as d:
        assert not lib.wait_for(os.path.join(d, "none.log"), "x",
                                timeout=0, tick=0)


def test_ffs_lines_keeps_only_the_kernels_ffs_lines():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "serial.log")
        with open(p, "wb") as f:
            f.write(b"serial_dbg: i386 kernel console up\r\n"
                    b"ffs: / was unclean when mounted; mounting read-write anyway\r\n"
                    b"Registering: en0\n"
                    b"\rffs: /mnt not cleanly unmounted, refusing read-write upgrade; run fsck\n")
        assert lib.ffs_lines(p) == [
            "ffs: / was unclean when mounted; mounting read-write anyway",
            "ffs: /mnt not cleanly unmounted, refusing read-write upgrade; run fsck"]


def test_ffs_lines_of_a_missing_log_is_empty():
    with tempfile.TemporaryDirectory() as d:
        assert lib.ffs_lines(os.path.join(d, "serial.log")) == []


def test_write_result_lists_notes_then_ffs_lines():
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "serial.log"), "w") as f:
            f.write("ffs: superblock magic invalid, refusing\n")
        lib.write_result(d, ["note one"])
        with open(os.path.join(d, "result.txt")) as f:
            assert f.read() == ("note one\nffs: lines:\n"
                                "  ffs: superblock magic invalid, refusing\n")


def test_port_free_sees_a_listener():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    s.listen(1)
    try:
        assert not lib.port_free(s.getsockname()[1])
    finally:
        s.close()
