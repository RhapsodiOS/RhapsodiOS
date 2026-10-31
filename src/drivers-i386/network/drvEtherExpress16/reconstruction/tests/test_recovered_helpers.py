from pathlib import Path
import re


SOURCE = Path(
    "src/drivers-i386/network/drvEtherExpress16/EtherExpress16.drvproj/"
    "EtherExpress16.lksproj/EtherExpress16.m"
)


def method_body(source, signature):
    match = re.search(signature + r"\s*\{", source)
    assert match is not None
    start = match.end()
    depth = 1
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index]
    raise AssertionError("unterminated method")


def test_wait_scb_reads_once_per_bounded_retry():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, r"static void _wait_scb\([^)]*\)")
    assert re.search(r"while\s*\(\s*retries\s*!=\s*0\s*\)", body)
    assert "scbCmd = inw(base);" in body
    assert "count = 0;" not in body
    assert "do {" not in body


def test_reference_backed_selectors_have_binary_return_shapes():
    source = SOURCE.read_text(encoding="utf-8-sig")
    for signature in (
        r"-\s*\(void\)hwInit:\(BOOL\)reset",
        r"-\s*\(void\)swInit",
        r"-\s*\(unsigned int\)memAvail",
        r"-\s*\(unsigned short\)memRegion:",
    ):
        assert re.search(signature, source), signature


def test_rfd_reader_reads_four_header_words_and_one_magic_word():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, r"static void _get_rfd\([^)]*\)")
    assert "count = 3;" in body
    assert "buffer[7] = inw(base);" in body
    assert "do {" not in body
    assert "count = 0;" not in body


def test_descriptor_link_helpers_write_only_the_two_link_words():
    source = SOURCE.read_text(encoding="utf-8-sig")
    for helper in ("_put_rfd_lnk", "_put_rbd_nxt"):
        body = method_body(source, rf"static void {helper}\([^)]*\)")
        assert body.count("outw(base,") == 2
        assert "count = 0;" not in body
        assert "do {" not in body


def test_adapter_memory_offsets_use_word_sized_port_writes():
    source = SOURCE.read_text(encoding="utf-8-sig")
    assert not re.search(r"outb\(base\s*\+\s*[24]\s*,", source)
    for helper in ("_get_rfd", "_put_rfd", "_get_scb", "_put_scb", "_put_scp"):
        body = method_body(source, rf"static void {helper}\([^)]*\)")
        assert re.search(r"outw\(base\s*\+\s*[24]\s*,", body)


def test_single_word_helpers_do_not_underflow_an_unbounded_counter():
    source = SOURCE.read_text(encoding="utf-8-sig")
    for helper in (
        "_get_iscp_busy", "_get_scb_stat", "_get_tcb_stat",
        "_put_rbd_magic", "_put_rfd_magic", "_put_tbd_count",
    ):
        body = method_body(source, rf"static void {helper}\([^)]*\)")
        assert "count = 0;" not in body
        assert "do {" not in body


def test_receive_descriptors_keep_rbd_pointer_and_magic_in_distinct_words():
    source = SOURCE.read_text(encoding="utf-8-sig")
    recv_init = method_body(source, r"-\s*\(void\)recvInit")
    recv_restart = method_body(source, r"-\s*\(void\)recvRestart")
    assert "rfdBuffer[3] = currentRBD;" in recv_init
    assert "rfdBuffer[11] = RFD_MAGIC;" in recv_init
    assert "rbdBuffer[5] = RBD_MAGIC;" in recv_init
    assert "rfdBuffer[3] = frb_off;" in recv_restart


def test_memory_size_probe_uses_byte_data_and_word_address_ports():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, r"static unsigned short _setup_mem\([^)]*\)")
    assert "inb(base);" in body
    assert "outb(base, 0);" in body
    assert "outb(base, 0xAA);" in body
    assert "inw(base);" not in body
    assert "outw(base, 0xAA);" not in body


def test_transmit_completion_always_checks_the_queue_after_acknowledging():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, r"-\s*\(void\)cxIntr")
    assert "if (!xmtActive) {\n        return;" not in body
    assert "nextPacket = [xmtQueue dequeue];" in body


def test_16_bit_mode_handshake_matches_ida_interrupt_and_port_sequence():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, r"-\s*\(id\)_configEE16:\(BOOL\)doConfig")
    assert body.count("_disable();") == 2
    assert body.count("_enable();") == 2
    assert body.count("inw(ctrlPort);") == 2
    assert body.count("IODelay(50);") == 2
    assert "ctrlReg &= 0xEF;" in body
    assert "ctrlReg & 0xF7" in body
