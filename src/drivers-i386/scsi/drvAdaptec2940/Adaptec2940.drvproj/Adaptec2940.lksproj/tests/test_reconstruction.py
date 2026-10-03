"""Evidence-backed checks for the Adaptec 2940 SCSI reconstruction."""

import argparse
import hashlib
import json
import os
import re
from pathlib import Path

from binrecon.macho import read_macho
from binrecon.schema import load_json, load_source_map


REPO_ROOT = Path(__file__).resolve().parents[7]
DRIVER = REPO_ROOT / "src/drivers-i386/scsi/drvAdaptec2940"
RECON = DRIVER / "reconstruction"
REFERENCE = Path(os.environ.get(
    "BINRECON_REFERENCE",
    r"C:\Users\raynorpat\Downloads\test\Drivers\i386\Adaptec2940SCSI.config\Adaptec2940SCSI_reloc",
))
REFERENCE_SIZE = 87676
REFERENCE_SHA256 = "08E6C11EEC125847F485C86250C94C4AFCC025E59CF085B0C8039B94B2E79DF7"
TEXT_SIZE = 32568
GENERATED = {
    (0x7F20, "+[Adaptec2940SCSIKernelServerInstance kernelServerInstance]"),
    (0x7F2C, "+[Adaptec2940SCSIVersion driverKitVersionForAdaptec2940SCSI]"),
}
REQUIRED_CASES = {
    "scb-page-boundary", "completion-timeout-order", "completion-reset-order",
    "short-transfer", "autosense-completion", "free-scb-exhaustion",
    "abort-active", "sequencer-readback-failure", "eeprom-failure", "init-unwind",
    "queue-chain-insert-remove", "scb-layout", "negotiation-message",
    "pci-device-match", "sequencer-runtime-patch", "register-width-order",
}


def _analysis_path(path=None):
    value = path or os.environ.get("ADAPTEC_ANALYSIS")
    assert value, "set ADAPTEC_ANALYSIS or pass --analysis"
    result = Path(value)
    assert result.is_file(), f"IDA analysis not generated: {result}"
    return result


def audit_inventory(analysis_path=None, repo_root=REPO_ROOT):
    analysis_file = _analysis_path(analysis_path)
    analysis = load_json(analysis_file)
    assert analysis["schema_version"] == "analysis-v1"
    assert analysis["input"]["sha256"].upper() == REFERENCE_SHA256
    assert analysis["analyzer"]["name"] == "IDA"
    assert analysis["analyzer"]["version"] == "9.4"
    functions = analysis["functions"]
    assert len(functions) == 170
    addresses = [function["address"] for function in functions]
    assert len(addresses) == len(set(addresses))

    generated, controllers, buses, c_functions = set(), set(), set(), set()
    for function in functions:
        names = function["names"]
        assert names
        for name in names:
            pair = (function["address"], name)
            if name.startswith("+[Adaptec2940SCSIKernelServerInstance ") \
                    or name.startswith("+[Adaptec2940SCSIVersion "):
                generated.add(pair)
            elif name.startswith(("+[SCSIBus", "-[SCSIBus")):
                buses.add(pair)
            elif name.startswith(("+[Adaptec2940", "-[Adaptec2940")):
                controllers.add(pair)
            else:
                c_functions.add(pair)
    assert generated == GENERATED
    assert len(controllers) == 30
    assert len(buses) == 13
    assert len(c_functions) == 125

    source_map = load_source_map(
        RECON / "source-map.json",
        reference_analysis=analysis,
        repo_root=Path(repo_root),
    )
    buckets = ("mapped", "unmapped", "duplicate_candidates", "boundary_disputed")
    assert sum(len(source_map[key]) for key in buckets) == 170
    assert len({entry["address"] for key in buckets for entry in source_map[key]}) == 170

    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    assert ledger["schema_version"] == "ledger-v1"
    assert ledger["reference_sha256"].upper() == REFERENCE_SHA256
    assert len(ledger["entries"]) == 170
    assert {entry["address"] for entry in ledger["entries"]} == set(addresses)
    published = REPO_ROOT / "tools/binrecon/out/adaptec2940/baseline"
    for entry in ledger["entries"]:
        for artifact in entry["artifacts"]:
            artifact_path = published / artifact["path"]
            assert artifact_path.is_file(), f"missing ledger evidence: {artifact_path}"
            digest = hashlib.sha256(artifact_path.read_bytes()).hexdigest().upper()
            assert digest == artifact["sha256"], f"ledger artifact digest mismatch: {artifact_path}"

    cases = json.loads((RECON / "reference-cases.json").read_text(encoding="utf-8"))
    found_cases = {case["id"] for case in cases["cases"]}
    assert found_cases == REQUIRED_CASES
    for case in cases["cases"]:
        assert case["evidence"], f"case has no evidence: {case['id']}"
        assert all(item["address"] is not None for item in case["evidence"]), case["id"]
        assert case["expected"], case["id"]

    interfaces = (RECON / "interfaces.md").read_text(encoding="utf-8")
    for marker in ("Controller (30)", "Bus (13)", "C (125)", "Generated (2)",
                   "Adaptec2940` — 396 bytes", "SCSIBus` — 588 bytes",
                   "P_Seq_01", "P_SeqExist"):
        assert marker in interfaces, marker
    return True


def test_reference_identity():
    document = read_macho(REFERENCE)
    assert document["input"]["size"] == REFERENCE_SIZE
    assert document["input"]["sha256"] == REFERENCE_SHA256
    assert document["input"]["architecture"] == "i386"
    assert document["input"]["endianness"] == "little"
    text = next(section for section in document["sections"]
                if section["name"] == "__TEXT,__text")
    assert text["address"] == 0
    assert text["size"] == TEXT_SIZE


def test_inventory_partition():
    assert audit_inventory()


def test_shared_layouts():
    layout_path = RECON / "layouts.json"
    layouts = json.loads(layout_path.read_text(encoding="utf-8"))
    assert layouts["schema_version"] == "adaptec2940-layouts-v1"
    assert layouts["reference_sha256"] == REFERENCE_SHA256
    assert layouts["structures"]["scb"]["size"] == 256
    scb_fields = layouts["structures"]["scb"]["fields"]
    for field, offset, width in (
        ("chain_next", 0, 4), ("host_info", 4, 4), ("scb_status", 8, 1),
        ("host_status", 9, 1), ("flags", 10, 1), ("manager_status", 11, 1),
        ("target_channel_lun", 12, 1), ("control", 13, 1),
        ("command_length", 14, 1), ("sg_count", 15, 1), ("sg_pointer", 16, 4),
        ("command_pointer", 20, 4), ("target_status", 24, 1),
        ("residual_data_count", 28, 4), ("sense_physical", 44, 4),
        ("cdb", 52, 12), ("host_self", 76, 4), ("scatter_gather", 80, 144),
        ("command_buffer", 224, 4), ("start_time", 228, 8),
        ("timeout_port", 236, 4), ("total_transfer_length", 240, 4),
        ("in_use", 244, 1), ("queue_next", 248, 4), ("queue_previous", 252, 4),
    ):
        assert scb_fields[field] == {"offset": offset, "width": width}, field
    assert layouts["structures"]["scb"]["fields"]["queue_next"] == {"offset": 248, "width": 4}
    assert layouts["structures"]["scb"]["fields"]["queue_previous"] == {"offset": 252, "width": 4}
    assert layouts["structures"]["host_info"]["size"] == 140
    assert layouts["structures"]["channel_info"]["size"] == 8
    assert layouts["structures"]["request_message"]["size"] == 36
    assert layouts["structures"]["scatter_gather"]["size"] == 8
    assert layouts["structures"]["queue_head"]["size"] == 8
    assert layouts["structures"]["sense_data"]["size"] == 26
    assert layouts["structures"]["scb"]["alignment"] == 256
    assert layouts["structures"]["scb"]["hardware_size"] == 32
    for field, contract in layouts["structures"]["host_info"]["verified_fields"].items():
        assert contract["offset"] >= 0 and contract["offset"] + contract["width"] <= 140, field
    assert layouts["structures"]["controller"]["size"] == 396
    assert layouts["structures"]["scsi_bus"]["size"] == 588
    assert layouts["structures"]["scsi_request"]["size"] == 84
    assert layouts["data"]["P_Seq_01"]["size"] == 1960
    assert layouts["structures"]["command_message_template"]["size"] == 24
    assert layouts["structures"]["timeout_message_template"]["size"] == 24
    check_source = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/adaptec2940-checks.c"
    assert check_source.is_file(), "guest layout check must compile the production types"
    check_text = check_source.read_text(encoding="utf-8")
    types_header = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Types.h").read_text(encoding="utf-8")
    for assertion in ("a2940_scb_size_is_256", "a2940_scb_chain_next_at_0",
                      "a2940_scb_host_info_at_4", "a2940_scb_status_at_8",
                      "a2940_scb_host_status_at_9", "a2940_scb_flags_at_10",
                      "a2940_scb_manager_status_at_11", "a2940_scb_tcl_at_12",
                      "a2940_scb_sg_count_at_15",
                      "a2940_scb_sg_pointer_at_16", "a2940_scb_command_pointer_at_20",
                      "a2940_scb_target_status_at_24", "a2940_scb_residual_at_28",
                      "a2940_scb_sense_physical_at_44", "a2940_scb_cdb_at_52",
                      "a2940_scb_host_self_at_76", "a2940_scb_sg_offset_is_80",
                      "a2940_scb_command_buffer_is_224", "a2940_scb_queue_link_is_248",
                      "a2940_scb_queue_previous_is_252", "a2940_request_channel_at_0",
                      "a2940_request_command_at_4", "a2940_request_host_info_at_8",
                      "a2940_request_buffer_at_12", "a2940_request_length_at_16",
                      "a2940_request_status_at_20", "a2940_request_client_at_24",
                      "a2940_request_link_is_28", "a2940_host_info_is_140",
                      "a2940_channel_info_owner_at_0", "a2940_channel_info_host_at_4",
                      "a2940_scsi_request_sense_at_56"):
        assert assertion in types_header, f"missing compiler layout assertion: {assertion}"
    for name, offset in layouts["structures"]["host_info"]["verified_fields"].items():
        macro = {
            "io_base": "A2940_HA_IO_BASE_OFFSET",
            "bus_number": "A2940_HA_BUS_NUMBER_OFFSET",
            "device_number": "A2940_HA_DEVICE_NUMBER_OFFSET",
            "options_byte": "A2940_HA_OPTIONS_OFFSET",
            "adapter_mode": "A2940_HA_MODE_OFFSET",
            "irq": "A2940_HA_IRQ_OFFSET",
            "structure_length": "A2940_HA_SIZE_OFFSET",
            "max_targets": "A2940_HA_TARGETS_OFFSET",
            "physical_self": "A2940_HA_SELF_OFFSET",
        }[name]
        assert re.search(rf"#define {macro}\s+{offset['offset']}\b", types_header), macro
    assert '#import "../Adaptec2940.h"' in check_text
    assert '#import "../SCSIBus.h"' in check_text
    for assertion in ("a2940_ivar_ioBase_at_296", "a2940_ivar_ioBase_pad_at_298",
                      "a2940_ivar_channel_at_300", "a2940_ivar_host_block_at_308",
                      "a2940_ivar_host_block_size_at_312", "a2940_ivar_interrupt_port_at_316",
                      "a2940_ivar_command_queue_at_320", "a2940_ivar_command_lock_at_328",
                      "a2940_ivar_active_queue_at_332", "a2940_ivar_scb_queue_at_340",
                      "a2940_ivar_scb_queue_length_at_348", "a2940_ivar_bad_scb_queue_at_352",
                      "a2940_ivar_flags_at_360", "a2940_ivar_reinit_channel_at_364",
                      "a2940_ivar_reset_state_at_368", "a2940_ivar_max_queue_at_372",
                      "a2940_ivar_queue_total_at_376", "a2940_ivar_total_commands_at_380",
                      "a2940_ivar_outstanding_count_at_384", "a2940_ivar_bus_type_at_388",
                      "a2940_ivar_level_irq_at_392", "a2940_ivar_bus_number_at_393",
                      "a2940_ivar_device_number_at_394", "a2940_ivar_function_number_at_395",
                      "a2940_bus_direct_at_580", "a2940_bus_channel_at_584"):
        assert assertion in check_text, f"missing Objective-C ivar assertion: {assertion}"
    runner = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/run-checks.sh"
    assert runner.is_file(), "guest runner is missing"
    for group in ("layouts", "firmware", "him", "config", "optima", "integration", "all"):
        assert group in runner.read_text(encoding="utf-8"), f"runner does not accept group {group}"
    runner_text = runner.read_text(encoding="utf-8")
    assert "../../../../../../.." in runner_text
    assert "A2940_BUILD_HASH" in runner_text


def test_sequencer_bytes():
    layouts = json.loads((RECON / "layouts.json").read_text(encoding="utf-8"))
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Sequencer.c").read_text(encoding="ascii")
    image_match = re.search(r"unsigned char P_Seq_01\[A2940_SEQ_IMAGE_SIZE\] = \{(.*?)\};", source, re.S)
    table_match = re.search(r"unsigned char P_SeqExist\[A2940_SEQ_PRESENCE_SIZE\] = \{(.*?)\};", source, re.S)
    assert image_match and table_match, "mutable reference firmware and descriptor table are missing"
    image = bytes(int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]{2})", image_match.group(1)))
    table = bytes(int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]{2})", table_match.group(1)))
    expected = layouts["data"]["P_Seq_01"]
    expected_table = layouts["data"]["P_SeqExist"]
    assert len(image) == expected["size"] == 1960
    assert hashlib.sha256(image).hexdigest().upper() == expected["sha256"]
    assert len(table) == expected_table["size"] == 24
    assert hashlib.sha256(table).hexdigest().upper() == expected_table["sha256"]
    assert table[:12] == bytes(12)
    assert int.from_bytes(table[12:14], "little") == 1960
    assert int.from_bytes(table[20:24], "little") == 0
    assert "P_SeqExist + 12 * mode" in source
    assert "return -2;" in source and "return 255;" in source and "return 0;" in source
    assert "AIC_SEQRAM, P_Seq_01[i]" in source
    assert '#include <driverkit/i386/ioPorts.h>' in source
    assert "a2940_io_barrier" not in source, "DriverKit outb already emits the lock-increment barrier"
    harness = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/adaptec2940-checks.c").read_text(encoding="ascii")
    for case in ("sequencer-absent", "sequencer-success", "sequencer-runtime-patch",
                 "sequencer-readback-failure"):
        assert case in harness, f"firmware harness is missing {case}"
    assert "sequencer_trace_port[1967] != 0x160" in harness
    assert "sequencer_trace_count == 1967" in harness
    assert "sequencer_barriers != 1968" in harness


def test_him_helper_batch_is_mapped_and_exercised():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940HIM.c"
    source = source_path.read_text(encoding="ascii")
    native = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/him-chain-checks.c"
    native_text = native.read_text(encoding="ascii")
    harness = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/adaptec2940-checks.c"
    harness_text = harness.read_text(encoding="ascii")
    for symbol in ("Ph_MemorySet", "Ph_ChainAppendEnd", "Ph_ChainInsertFront",
                   "Ph_ChainRemove", "Ph_ChainPrevious", "Ph_Pause", "Ph_UnPause",
                   "Ph_WriteHcntrl", "Ph_ReadIntstat", "Ph_CheckLength",
                   "Ph_GetScbStatus", "Ph_SetMgrStat", "PH_EnableInt",
                   "PH_DisableInt", "Ph_InBuffer", "Ph_OutBuffer", "Ph_SetNeedNego",
                   "Ph_Abort", "Ph_SendTrmMsg", "Ph_TrmCmplt", "Ph_BusReset",
                   "Ph_HaSoftReset", "Ph_SoftReset", "Ph_SetScbMark",
                   "Ph_InsertBookmark", "Ph_RemoveBookmark", "Ph_ScbPrepare",
                   "Ph_SyncSet", "Ph_ScbRenego", "Ph_ClearFast20Reg",
                   "Ph_LogFast20Map", "Ph_Delay", "PH_PollInt"):
        assert re.search(r"\b" + symbol + r"\s*\(", source), f"missing HIM body: {symbol}"
    for case in ("chain-empty", "chain-front-middle-tail", "chain-previous-miss",
                 "memory-set", "hcntrl-write-mask", "intstat-paused-unpaused",
                 "pause-unpause", "short-transfer", "port-buffer-transfer",
                 "interrupt-enable-disable", "negotiation-marker", "reset-trampolines",
                 "bookmark-insert-remove", "scb-mark", "scb-prepare-status-count",
                 "sync-period-map", "renegotiation-marker", "fast20-map",
                 "sequencer-delay", "poll-interrupt-mask"):
        assert case in harness_text, f"HIM guest harness is missing {case}"
    assert '#include "../Adaptec2940HIM.c"' in native_text
    assert "0xffffffffU" in native_text and "Ph_MemorySet(fill" in native_text

    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in ("_Ph_MemorySet", "_Ph_ChainAppendEnd", "_Ph_ChainInsertFront",
                 "_Ph_ChainRemove", "_Ph_ChainPrevious", "_Ph_Pause", "_Ph_UnPause",
                 "_Ph_WriteHcntrl", "_Ph_ReadIntstat", "_Ph_CheckLength",
                 "_Ph_GetScbStatus", "_Ph_SetMgrStat", "_PH_EnableInt",
                 "_PH_DisableInt", "_Ph_InBuffer", "_Ph_OutBuffer", "_Ph_SetNeedNego",
                 "_Ph_Abort", "_Ph_SendTrmMsg", "_Ph_TrmCmplt", "_Ph_BusReset",
                 "_Ph_HaSoftReset", "_Ph_SoftReset", "_Ph_SetScbMark",
                 "_Ph_InsertBookmark", "_Ph_RemoveBookmark", "_Ph_ScbPrepare",
                 "_Ph_SyncSet", "_Ph_ScbRenego", "_Ph_ClearFast20Reg",
                 "_Ph_LogFast20Map", "_Ph_Delay", "_PH_PollInt"):
        assert mapped[name]["source_path"].endswith("Adaptec2940HIM.c")
        assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_statistics_methods_match_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    for signature, expression in (
        ("- (void)resetStats", "queueLenTotal = 0;\n\tmaxQueueLen = 0;\n\ttotalCommands = 0;"),
        ("- (unsigned int)numQueueSamples", "return totalCommands;"),
        ("- (unsigned int)sumQueueLengths", "return queueLenTotal;"),
        ("- (unsigned int)maxQueueLength", "return maxQueueLen;"),
        ("- (unsigned)maxTransfer", "return (AIC_SG_COUNT * PAGE_SIZE);"),
    ):
        assert signature in source, signature
        start = source.index(signature)
        body_end = source.index("\n}", start)
        assert expression in source[start:body_end], signature
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in ("-[Adaptec2940 resetStats]", "-[Adaptec2940 numQueueSamples]",
                 "-[Adaptec2940 sumQueueLengths]", "-[Adaptec2940 maxQueueLength]",
                 "-[Adaptec2940 maxTransfer]"):
        assert mapped[name]["source_path"].endswith("Adaptec2940.m")
        assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_channel_methods_match_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    expected = (
        ("- (int)numberOfTargets:(int)channel", "A2940_CHANNEL_TARGET_COUNT_OFFSET"),
        ("- (char)acquireSCSIBus:(unsigned int)channel owner:(id)owner", "channel != 0 || info->owner != nil || info->hostInfo == nil"),
        ("- (void)releaseSCSIBus:(unsigned int)channel owner:(id)owner", "channelInfo[channel].owner == owner"),
        ("- (int)scsiBusId:(unsigned int)channel", "A2940_CHANNEL_BUS_ID_OFFSET"),
    )
    for signature, expression in expected:
        start = source.index(signature)
        body_end = source.index("\n}", start)
        assert expression in source[start:body_end], signature
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in ("-[Adaptec2940 numberOfTargets:]", "-[Adaptec2940 acquireSCSIBus:owner:]",
                 "-[Adaptec2940 releaseSCSIBus:owner:]", "-[Adaptec2940 scsiBusId:]"):
        assert mapped[name]["source_path"].endswith("Adaptec2940.m")
        assert entries[name]["status"] == "control-flow-confirmed"


def test_scsi_bus_class_matches_reference():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/SCSIBus.m"
    assert source_path.is_file(), "the recovered SCSIBus implementation must be part of the driver"
    source = source_path.read_text(encoding="ascii")
    project = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/PB.project").read_text(encoding="ascii")
    preamble = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Makefile.preamble").read_text(encoding="ascii")
    assert "SCSIBus.m" in project and "SCSIBus.h" in project
    assert "CLASSES += SCSIBus.m" in preamble and "HFILES += SCSIBus.h" in preamble
    for signature, expression in (
        ("+ (BOOL)probe:", "channel != 0"),
        ("+ (int)deviceStyle", "return IO_IndirectDevice;"),
        ("+ (Protocol **)requiredProtocols", "return protocols;"),
        ("- (unsigned int)maxTransfer", "[_direct maxTransfer]"),
        ("- (void)resetStats", "if (_scsiChannel == 0)"),
        ("- (int)numberOfTargets", "[_direct numberOfTargets:_scsiChannel]"),
        ("- (sc_status_t)executeRequest:", "request[1] = 0;"),
        ("- (sc_status_t)resetSCSIBus", "request[1] = 1;"),
        ("- initSCSIBus:", "for (target = 0; target <= 7; ++target)"),
    ):
        assert signature in source, signature
        start = source.index(signature)
        body_end = source.index("\n}", start)
        assert expression in source[start:body_end], signature
    assert "@protocol(IOSCSIControllerExported)" in source
    names = (
        "+[SCSIBus probe:]", "+[SCSIBus deviceStyle]", "+[SCSIBus requiredProtocols]",
        "-[SCSIBus maxTransfer]", "-[SCSIBus free]", "-[SCSIBus resetStats]",
        "-[SCSIBus numQueueSamples]", "-[SCSIBus sumQueueLengths]",
        "-[SCSIBus maxQueueLength]", "-[SCSIBus numberOfTargets]",
        "-[SCSIBus executeRequest:buffer:client:]", "-[SCSIBus resetSCSIBus]",
        "-[SCSIBus initSCSIBus:channel:]",
    )
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in names:
        assert mapped[name]["source_path"].endswith("SCSIBus.m")
        assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_entry_and_notification_methods_match_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    expected = (
        ("+ (BOOL)probe:", "[instance initFromDeviceDescription:deviceDescription] != nil"),
        ("- (void)interruptOccurredAt:", 'interruptOccurredAt:%d\\n'),
        ("- (void)otherOccurred:", 'otherOccurred:%d\\n'),
        ("- (void)receiveMsg", 'receiveMsg\\n'),
    )
    for signature, expression in expected:
        assert signature in source, signature
        start = source.index(signature)
        body_end = source.index("\n}", start)
        assert expression in source[start:body_end], signature
    receive_start = source.index("- (void)receiveMsg")
    receive_end = source.index("\n}", receive_start)
    assert "[super receiveMsg];" in source[receive_start:receive_end]
    names = (
        "+[Adaptec2940 probe:]", "-[Adaptec2940 interruptOccurredAt:]",
        "-[Adaptec2940 otherOccurred:]", "-[Adaptec2940 receiveMsg]",
    )
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in names:
        assert mapped[name]["source_path"].endswith("Adaptec2940.m")
        assert entries[name]["status"] == "control-flow-confirmed"


def _main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", choices=("inventory", "layouts", "firmware"))
    parser.add_argument("--analysis")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    args, pytest_args = parser.parse_known_args()
    if args.audit:
        if args.audit == "inventory":
            audit_inventory(args.analysis, args.repo_root)
        elif args.audit == "layouts":
            test_shared_layouts()
        else:
            test_sequencer_bytes()
        print(f"{args.audit} audit passed")
        return 0
    import pytest
    return pytest.main([str(Path(__file__)), *pytest_args])


if __name__ == "__main__":
    raise SystemExit(_main())
