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
                      "a2940_request_command_at_4", "a2940_request_request_at_8",
                      "a2940_request_buffer_at_12", "a2940_request_client_task_at_16",
                      "a2940_request_status_at_20", "a2940_request_condition_lock_at_24",
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
    config_source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Config.c").read_text(encoding="ascii")
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
                   "Ph_LogFast20Map", "Ph_Delay", "PH_PollInt", "Ph_Wait2usec",
                   "Ph_AsynchEvent", "Ph_RebuildEEControl",
                   "Ph_RemoveAndPostScb", "Ph_PostNonActiveScb",
                   "Ph_TermPostNonActiveScb", "Ph_PostCommand",
                   "Ph_ScbAbort", "Ph_Wt4Req", "Ph_ParityError",
                   "Ph_NoAssistTerm",
                   "Ph_ExtMsgo", "Ph_SyncNego",
                   "Ph_ReadCableStatus",
                   "Ph_ResetChannel",
                   "Ph_IntSelto", "Ph_IntFree", "Ph_NonInit",
                   "Ph_SendStartBitEE", "Ph_SendAddressEE",
                   "Ph_EnableEraseWriteEE", "Ph_DisableEraseWriteEE",
                   "Ph_ReadE2Register", "Ph_WriteE2Register",
                   "Ph_ReadEeprom", "Ph_UpdateEeprom",
                   "Ph_ReadBiosInfo", "Ph_WriteBiosInfo", "Ph_CheckSyncNego",
                   "Ph_CheckBiosPresence", "Ph_GetDrvrConfig", "Ph_SetHaData",
                   "SWAPCurrScratchRam", "Ph_InitDrvrHA"):
        assert re.search(r"\b" + symbol + r"\s*\(", source), f"missing HIM body: {symbol}"
    for symbol in ("PH_ReadConfigOSM", "PH_WriteConfigOSM", "PH_GetNumOfBusesOSM",
                   "PH_FindHA", "PH_GetNumOfBuses"):
        assert re.search(r"\b" + symbol + r"\s*\(", config_source), f"missing config body: {symbol}"
    for case in ("chain-empty", "chain-front-middle-tail", "chain-previous-miss",
                 "memory-set", "hcntrl-write-mask", "intstat-paused-unpaused",
                 "pause-unpause", "short-transfer", "port-buffer-transfer",
                 "interrupt-enable-disable", "negotiation-marker", "reset-trampolines",
                 "bookmark-insert-remove", "scb-mark", "scb-prepare-status-count",
                 "sync-period-map", "renegotiation-marker", "fast20-map",
                 "sequencer-delay", "poll-interrupt-mask", "wait-two-usec",
                 "async-event-callback", "rebuild-ee-control", "osm-config-stubs",
                 "post-nonactive-scb", "request-phase-parity-error",
                 "selection-timeout-free-interrupt", "noninit-event-dispatch",
                 "eeprom-write-enable-disable", "eeprom-register-read-write",
                 "eeprom-image-checksum-update", "bios-buffer-read-write",
                 "sync-negotiation-masks", "driver-config-bios-presence",
                 "optima-hardware-data-init"):
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
                 "_Ph_LogFast20Map", "_Ph_Delay", "_PH_PollInt", "_Ph_Wait2usec",
                 "_Ph_AsynchEvent", "_Ph_RebuildEEControl", "_PH_ReadConfigOSM",
                 "_PH_WriteConfigOSM", "_PH_GetNumOfBusesOSM",
                 "_Ph_SendStartBitEE", "_Ph_SendAddressEE",
                 "_Ph_EnableEraseWriteEE", "_Ph_DisableEraseWriteEE",
                 "_Ph_ReadE2Register", "_Ph_WriteE2Register",
                 "_Ph_ReadEeprom", "_Ph_UpdateEeprom", "_Ph_ReadBiosInfo",
                 "_Ph_WriteBiosInfo", "_Ph_CheckSyncNego", "_Ph_CheckBiosPresence",
                 "_Ph_GetDrvrConfig", "_Ph_SetHaData",
                 "_SWAPCurrScratchRam", "_Ph_InitDrvrHA"):
        if name in ("_PH_ReadConfigOSM", "_PH_WriteConfigOSM", "_PH_GetNumOfBusesOSM",
                    "_PH_FindHA", "_PH_GetNumOfBuses"):
            assert mapped[name]["source_path"].endswith("Adaptec2940Config.c")
        else:
            assert mapped[name]["source_path"].endswith("Adaptec2940HIM.c")
        assert entries[name]["status"] == "control-flow-confirmed"

    assert "post-nonactive-scb" in harness_text
    for name in ("_PH_ScbCompleted", "_Ph_RemoveAndPostScb",
                 "_Ph_PostNonActiveScb", "_Ph_TermPostNonActiveScb",
                 "_Ph_PostCommand", "_Ph_ScbAbort",
                 "_Ph_NoAssistTerm",
                 "_Ph_ExtMsgo", "_Ph_SyncNego",
                 "_Ph_ReadCableStatus",
                 "_Ph_ResetChannel",
                 "_Ph_Wt4Req", "_Ph_ParityError", "_Ph_IntSelto",
                 "_Ph_IntFree", "_Ph_NonInit", "_Ph_SendStartBitEE",
                 "_Ph_SendAddressEE", "_Ph_EnableEraseWriteEE",
                 "_Ph_DisableEraseWriteEE", "_Ph_ReadE2Register",
                 "_Ph_WriteE2Register", "_Ph_ReadEeprom", "_Ph_UpdateEeprom",
                 "_Ph_ReadBiosInfo", "_Ph_WriteBiosInfo", "_Ph_CheckSyncNego",
                 "_Ph_CheckBiosPresence", "_Ph_GetDrvrConfig", "_Ph_SetHaData",
                 "_SWAPCurrScratchRam", "_Ph_InitDrvrHA"):
        assert mapped[name]["source_path"].endswith(("Adaptec2940.m", "Adaptec2940HIM.c"))
        assert entries[name]["status"] == "control-flow-confirmed"


def test_him_interrupt_handler_routes_reference_events():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Interrupt.c"
    source = source_path.read_text(encoding="ascii")
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/interrupt-checks.c").read_text(encoding="ascii")
    signature = "int PH_IntHandler(int host_address)"
    start = source.index(signature)
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "Ph_ReadIntstat((short)io_base)", "saved_mode == 1 && (control & 0x10) != 0",
        "completion_handler(host_address, control, completion)",
        "Ph_IntSrst(host_address)", "Ph_CheckLength(scb_address",
        "Ph_CdbAbort(scb_address", "Ph_SendMsgo(", "Ph_CheckCondition(scb_address",
        "Ph_BadSeq(host_address", "Ph_ExtMsgi(scb_address", "Ph_HandleMsgi(scb_address",
        "Ph_TargetAbort(host_address", "Ph_Negotiate(scb_address",
        "Ph_IntSelto(host_address", "Ph_IntFree(host_address",
        "Ph_ParityError(scb_address", "Ph_SendCommand((int **)ha, io_base)",
        "Ph_PostCommand(host_address)", "saved_mode;",
    ):
        assert expression in body, expression
    for expression in ("#define A2940_INTERRUPT_STANDALONE 1",
                       '#include "../Adaptec2940Interrupt.c"',
                       "completion_control == 0x12 && completion_mask == 0x200",
                       "hcntrl_writes[1] == 0x10",
                       "post_command_calls == 2",
                       "*(unsigned short *)(ha + 284) == 1"):
        assert expression in native, expression
    name = "_PH_IntHandler"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940Interrupt.c")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_him_abort_and_message_negotiation_match_reference():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940HIM.c"
    source = source_path.read_text(encoding="ascii")
    bodies = {}
    for name, signature, end_signature in (
        ("_Ph_SendMsgo", "unsigned char Ph_SendMsgo(", "char Ph_Negotiate("),
        ("_Ph_Negotiate", "char Ph_Negotiate(", "int Ph_TargetAbort("),
        ("_Ph_TargetAbort", "int Ph_TargetAbort(", "int Ph_ScbPrepare("),
    ):
        start = source.index(signature)
        end = source.index(end_signature, start + len(signature))
        bodies[name] = source[start:end]
    checks = {
        "_Ph_SendMsgo": (
            "io_base + 3, 0xa0", "scb[10] & 2", "Ph_ExtMsgo(",
            "Ph_SyncNego(", "Ph_Negotiate(", "io_base + target + 32",
        ),
        "_Ph_Negotiate": (
            "io_base + 98, 2", "host[target + 32] & 0x81", "scb[64] = 1",
            "Ph_ExtMsgo(", "Ph_Wt4Req(", "scb[65] = 3", "Ph_SyncNego(",
        ),
        "_Ph_TargetAbort": (
            "Ph_ReadIntstat((short)io_base) & 0xf0", "Ph_Wt4Req(",
            "scb[11] == 68", "scb[11] == 65", "Ph_SendTrmMsg(",
            "Ph_TerminateCommand(", "Ph_PostCommand(", "Ph_BadSeq(",
        ),
    }
    for name, expressions in checks.items():
        for expression in expressions:
            assert expression in bodies[name], (name, expression)
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in checks:
        assert mapped[name]["source_path"].endswith("Adaptec2940HIM.c")
        assert entries[name]["status"] == "control-flow-confirmed"


def test_hard_reset_recovery_matches_reference():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Recovery.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("unsigned char Ph_HaHardReset(int host_address)")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "Ph_WriteHcntrl((short)io_base, hcntrl | 4)",
        "A2940_RECOVERY_OUTB(io_base + 146, 0x0f)",
        "Ph_InsertBookmark(host_address)",
        "if ((control & 8) == 0 || scb_index == 0xff)",
        "Ph_AsynchEvent(3, host_address, scb_address)",
        "Ph_ResetSCSI(io_base)", "Ph_CheckSyncNego(host_address)",
        "Ph_ResetChannel(host_address)", "Ph_AbortChannel(host_address, 5)",
        "Ph_RemoveBookmark(host_address)",
        "hcntrl & 0xfb",
    ):
        assert expression in body, expression
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/pci-config-checks.c").read_text(encoding="ascii")
    assert "Ph_HaHardReset((int)(unsigned long)host)" in native
    name = "_Ph_HaHardReset"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940Recovery.c")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_scb_send_matches_reference_and_native_harness():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Scb.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("char PH_ScbSend(int scb_address)")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "*(unsigned short *)(ha + 284) = 1", "scb[8] == 2 || scb[8] == 0",
        "scb[13] &= (unsigned char)~8", "if (ha[287] == 2)",
        "Ph_ChainAppendEnd(host_address", "Ph_ScbPrepare(host_address",
        "saved_mode == 0 && (unsigned char)Ph_SendCommand((int **)ha, io_base)",
        "hcntrl |= 0x10", "Ph_NonInit(scb_address)",
        "*(unsigned short *)(ha + 284) = saved_mode",
    ):
        assert expression in body, expression
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/scb-send-checks.c").read_text(encoding="ascii")
    for expression in (
        '#include "../Adaptec2940Scb.c"',
        "trace_count == 5 && trace[0] == 1 && trace[1] == 2",
        "send_calls == 1 && mode_seen == 1 && noninit_calls == 0",
        "noninit_calls == 1 && *(unsigned short *)(ha + 284) == 9",
    ):
        assert expression in native, expression
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped["_PH_ScbSend"]["source_path"].endswith("Adaptec2940Scb.c")
    assert entries["_PH_ScbSend"]["status"] == "control-flow-confirmed"


def test_special_dispatch_matches_reference_and_native_harness():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Special.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("int PH_Special(char command")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "case 0:\n\t\tPh_ScbAbort(scb_address)", "case 2:\n\t\tPh_HaHardReset(host_address)",
        "while ((status & 4) == 0)", "Ph_ScbRenego(host_address",
        "if (ha[287] != 2)", "*(unsigned int *)ha == 0xffffffffU",
        "result = SWAPCurrScratchRam(host_address, 1)", "ha[287] = 2",
        "ha[287] = 3", "(unsigned char)Ph_SendCommand((int **)ha, io_base)",
        "status | 0x10", "*(unsigned short *)(ha + 284) = saved_mode",
    ):
        assert expression in body, expression
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/special-checks.c").read_text(encoding="ascii")
    for expression in (
        '#include "../Adaptec2940Special.c"',
        "ha[287] == 3 && *(unsigned short *)(ha + 284) == 0",
        "renego_calls == 1 && renego_host == host_address && renego_target == 0x35",
        "abort_calls == 1 && abort_scb == scb_address",
        "send_calls == 1 && send_mode == 1 && writes[0] == 0x31",
    ):
        assert expression in native, expression
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped["_PH_Special"]["source_path"].endswith("Adaptec2940Special.c")
    assert entries["_PH_Special"]["status"] == "control-flow-confirmed"


def test_bus_device_reset_matches_reference_and_native_harness():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940BusReset.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("unsigned char Ph_BusDeviceReset(int scb_address)")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "((unsigned char (__cdecl *)(int *, int))ha[110])",
        "if (host[30] == target)", "Ph_HaHardReset(host_address)",
        "Ph_ChainAppendEnd(host_address", "Ph_ScbPrepare(host_address",
        "((unsigned char (__cdecl *)(int *, int))ha[112])",
        "((int **)(void *)ha)[68][index]", "Ph_TerminateCommand(scb_address",
        "for (queued = (unsigned char *)(unsigned long)(unsigned int)ha[0]",
        "Ph_ScbAbort((int)(unsigned long)queued)", "*(unsigned int *)(scb + 16) = 12",
        "((void (__stdcall *)(unsigned char))ha[120])(index)",
        "scb[43] = 48", "PH_ScbCompleted(scb_address)",
    ):
        assert expression in body, expression
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/bus-reset-checks.c").read_text(encoding="ascii")
    assert '#include "../Adaptec2940BusReset.c"' in native
    assert "test_is_active" in native and "test_scb_index" in native and "test_start_scb" in native
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped["_Ph_BusDeviceReset"]["source_path"].endswith("Adaptec2940BusReset.c")
    assert entries["_Ph_BusDeviceReset"]["status"] == "control-flow-confirmed"


def test_timeout_notification_matches_reference_and_native_harness():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Timeout.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("int a2940Timeout(int scb_address)")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "static const unsigned char timeoutMsgTemplate[24]",
        "0x00, 0x00, 0x00, 0x01, 0x18, 0x00, 0x00, 0x00",
        "*(int *)(message + 16) = *(int *)((unsigned char *)scb + 236)",
        'A2940_TIMEOUT_LOG("Adaptec2940 timeout\\n")',
        "A2940_TIMEOUT_SEND(message, 0, 0)",
        'A2940_TIMEOUT_LOG("a2940Timeout: msg_send_from_kernel() returned %d\\n", send_result)',
    ):
        assert expression in source if expression.startswith("static const") or expression.startswith("0x00") else expression in body, expression
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/timeout-checks.c").read_text(encoding="ascii")
    assert '#include "../Adaptec2940Timeout.c"' in native
    assert "a2940Timeout((int)(unsigned long)scb) == 19" in native
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped["_a2940Timeout"]["source_path"].endswith("Adaptec2940Timeout.c")
    assert entries["_a2940Timeout"]["status"] == "control-flow-confirmed"


def test_send_command_queue_drain_matches_reference_and_native_harness():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Command.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("int Ph_SendCommand(int **ha, int io_base)")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "int *scb = ha[0]", "*((unsigned short *)ha + 133) != 0",
        "ha[110])(ha, scb)", "*((unsigned char *)scb + 11) == 16",
        "ha[112])(ha, scb)", "--*((unsigned short *)ha + 133)",
        "*((unsigned char *)scb + 11) = 64", "ha[68][index] = (int)scb",
        "while ((status & 4) == 0)", "ha[119])(index, scb, io_base)",
        "Ph_WriteHcntrl((short)io_base, hcntrl)",
    ):
        assert expression in body, expression
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/command-checks.c").read_text(encoding="ascii")
    assert '#include "../Adaptec2940Command.c"' in native
    assert "active_scb[0] == scb_a_address && active_scb[1] == scb_b_address" in native
    assert "start_calls == 1 && start_index == 3 && start_scb == scb_a_address" in native
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped["_Ph_SendCommand"]["source_path"].endswith("Adaptec2940Command.c")
    assert entries["_Ph_SendCommand"]["status"] == "control-flow-confirmed"


def test_check_condition_matches_reference_and_native_harness():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940CheckCondition.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("char Ph_CheckCondition(int scb_address, short io_base)")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "if (scb[11] == 8)", "scb[43] = 27", "io_base + 58", "scb[24] = scsi_status",
        "io_base + 60", "scsi_status == 2 && (scb[10] & 0x80) != 0",
        "ha[118])(scb_address, target_status)", "ha[117])(host_address, target_status)",
        "Ph_TerminateCommand(scb_address", "host[14] & 1", "host[(scb[12] >> 4) + 32] & 0x81",
        "value | 2", "value & 0xf7", "io_base + 98", "io_base + 99",
    ):
        assert expression in body, expression
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/check-condition-checks.c").read_text(encoding="ascii")
    assert '#include "../Adaptec2940CheckCondition.c"' in native
    assert "autosense_calls == 1" in native and "terminate_calls == 1" in native
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped["_Ph_CheckCondition"]["source_path"].endswith("Adaptec2940CheckCondition.c")
    assert entries["_Ph_CheckCondition"]["status"] == "control-flow-confirmed"


def test_bios_info_matches_reference_and_native_harness():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Bios.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("int PH_GetBiosInfo(int host_address")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "Ph_ReadConfig(-1", "& 0xfffffffcu", "info[index + 3] = 0xff",
        "Ph_Pause((int)io_base)", "io_base + 144, 2", "io_base + 160",
        "io_base + 176", "scsi_bios != 0xffffffffU", "option_bios != 0xffffffffU",
        "info[0] = 5", "info[0] |= 2", "info[1] = first_id", "info[2] = last_id",
        "info[id + 3]", "restore_page = id_count", "io_base + 144, restore_page",
        "Ph_WriteHcntrl((short)io_base, saved_hcntrl)",
    ):
        assert expression in body, expression
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/bios-info-checks.c").read_text(encoding="ascii")
    assert '#include "../Adaptec2940Bios.c"' in native
    assert "info[3] == 2 && info[4] == 3 && info[5] == 4" in native
    assert "PH_GetBiosInfo(0, 1, 3, info) == 0xff" in native
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped["_PH_GetBiosInfo"]["source_path"].endswith("Adaptec2940Bios.c")
    assert entries["_PH_GetBiosInfo"]["status"] == "control-flow-confirmed"


def test_handle_message_in_matches_reference_and_native_harness():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940HandleMsgi.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("char Ph_HandleMsgi(int scb_address, int io_base)")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "io_base + 3) & 0x10", "message == 7", "status & 0xa0",
        "Ph_TargetAbort(host_address, scb_address, io_base)", "message == 35",
        "Ph_Wt4Req(scb_address, (short)io_base)", "io_base + 8",
        "*(unsigned int *)(scb + 28)", "io_base + 20", "residual -= transfer_count",
        "io_base + 136", "while ((char)status == (char)-32)",
        "Ph_BadSeq(host_address, io_base)", "io_base + 12, 0x40",
    ):
        assert expression in body, expression
    native = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/handle-msgi-checks.c").read_text(encoding="ascii")
    assert '#include "../Adaptec2940HandleMsgi.c"' in native
    assert "*(unsigned int *)(scb + 28) == 0xa126" in native
    assert "badseq_calls == 1 && badseq_host == host_address" in native
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped["_Ph_HandleMsgi"]["source_path"].endswith("Adaptec2940HandleMsgi.c")
    assert entries["_Ph_HandleMsgi"]["status"] == "control-flow-confirmed"


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


def test_controller_scb_alignment_queue_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    signature = "- (char)checkScbAlign:(Adaptec2940SCB *)scb"
    start = source.index(signature)
    body_end = source.index("\n}", start)
    body = source[start:body_end]
    for expression in ("address + 80", "address + 224", "tail == head",
                       "tail + 248", "+ 252", "return 1;"):
        assert expression in body, expression
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    name = "-[Adaptec2940 checkScbAlign:]"
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_free_scb_pool_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    signature = "- (void)freeScb:(Adaptec2940SCB *)scb"
    start = source.index(signature)
    body_end = source.index("\n}", start)
    body = source[start:body_end]
    for expression in ("scbQLength > 16", "scb + 244", "IOFree(scb, 256)",
                       "self + 340", "self + 344", "tail + 248", "+ 252",
                       "++scbQLength"):
        assert expression in body, expression
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    name = "-[Adaptec2940 freeScb:]"
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_destructor_matches_reference_cleanup_order():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="utf-8")
    start = source.index("- free\n{")
    end = source.index("\n- (void)resetStats", start)
    method = source[start:end]
    required = (
        "if (ioThreadRunning)", "stopMessage.command = 2",
        "[self executeCmdBuf:&stopMessage]", "[commandLock free]",
        "IOFree(hspStructSave, hspStructFreeSize)",
        "IOFree(channelInfo[0].hostInfo, A2940_HOST_INFO_SIZE)",
        "queue_remove_first(&scbQ", "--scbQLength",
        "if (scb->in_use == 0)", "queue_remove_first(&scbBadQ",
        "return [super free];",
    )
    positions = [method.index(expression) for expression in required]
    assert positions == sorted(positions)
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entry = next(item for item in ledger["entries"] if item["address"] == 0x804)
    assert entry["status"] == "control-flow-confirmed"
    assert entry["source_line"] == 538


def test_controller_timeout_scan_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    start = source.index("- (void)timeoutOccurred")
    end = source.index("\n- (void)commandRequestOccurred", start)
    body = source[start:end]
    for expression in (
        "IOGetTimestamp(&now)", "PH_PollInt(channelInfo[0].hostInfo)",
        "PH_IntHandler(channelInfo[0].hostInfo)", "entry = activeQ.next",
        "scb->start_time + (ns_time_t)1000000000ULL * timeoutSeconds",
        "now >= deadline", "queue_remove(&activeQ, scb",
        "--outstandingCount", "message->status = 5",
        "[self commandCompleted:scb]",
        '[self threadResetBus:nil channel:0 reason:"I/O Timeout"]',
    ):
        assert expression in body, expression
    name = "-[Adaptec2940 timeoutOccurred]"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_scb_completion_status_mapping_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    start = source.index("- (void)scbComplete:(Adaptec2940SCB *)scb")
    end = source.index("\n- (int)setIntValues:", start)
    body = source[start:end]
    for expression in (
        "if (resetState == 2)", "request[32] = scb->target_status",
        "queue_remove(&activeQ, scb", "--outstandingCount",
        "scbStatus == 2", "message->status = 12", "scbStatus == 0",
        "scbStatus != 1 && scbStatus != 4", "hostStatus == 18",
        "scb->residual_data_count", "scb->total_transfer_length - residual",
        "case 0x11:", "case 0x13:", "case 0x20:", "case 0x22:",
        "[self commandCompleted:scb]", "*((unsigned char *)self + 360) |= 0x10",
    ):
        assert expression in body, expression
    name = "-[Adaptec2940 scbComplete:]"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_thread_bus_reset_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    start = source.index("- (void)threadResetBus:(Adaptec2940RequestMessage *)message")
    end = source.index("\n- (void)commandRequestOccurred", start)
    body = source[start:end]
    for expression in (
        "if (resetState != 0)", "resetState = 1", "channelInfo[channel].hostInfo",
        "resetState = 2", "while (activeQ.next != (queue_entry *)&activeQ)",
        "queue_remove(&activeQ, scb", "--outstandingCount", "activeMessage->status = 20",
        "PH_Special(0,", "[self commandCompleted:scb]", "PH_Special(2,",
        'reason);', "[self initHostAdaptor]", "IOSleep(10000)",
        "message->status = 0", "[message->condition_lock unlockWith:1]",
        "resetState = 0", "outstandingCount = 0", "[self enableAllInterrupts]",
    ):
        assert expression in body, expression
    name = "-[Adaptec2940 threadResetBus:channel:reason:]"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_host_adaptor_initialization_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    start = source.index("- (unsigned int)initHostAdaptor")
    end = source.index("\n- (void)commandRequestOccurred", start)
    body = source[start:end]
    for expression in (
        "bzero(hostInfo, A2940_HOST_INFO_SIZE)", "bytes[18] = 0",
        "bytes + 12) = 192", "bytes[8] = busNumber", "bytes[9] = deviceNumber",
        "PH_GetConfig(", "hostInfo->bytes[19]", "*(unsigned int *)(hostInfo->bytes + 4) != ioBase",
        "bytes + 60", "hspStructFreeSize = 2 * hostSize", "[self createScbs:",
        "bytes + 100", "bytes + 52", "IOVmTaskSelf(", "bytes[31] > 0x20",
        "target + 32", "bytes[12] &= (unsigned char)~2", "PH_InitHA(",
        "0xffffff3f", "PH_EnableInt(", "[self enableAllInterrupts]", "return 0;",
    ):
        assert expression in body, expression
    name = "-[Adaptec2940 initHostAdaptor]"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_scb_region_initialization_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    signature = "- (void)createScbs:(unsigned int)base size:(unsigned int)size"
    start = source.index(signature)
    body_end = source.index("\n}", start)
    body = source[start:body_end]
    for expression in ("size + base - 255", "checkScbAlign:scb", "bzero(scb, 256)",
                       "+ 76", "+ 244", "self + 340", "self + 344",
                       "tail + 248", "+ 252", "scb_address += 256", "++scbQLength"):
        assert expression in body, expression
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    name = "-[Adaptec2940 createScbs:size:]"
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_alloc_scb_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    signature = "- (Adaptec2940SCB *)allocScb"
    start = source.index(signature)
    body_end = source.index("\n}", start)
    body = source[start:body_end]
    for expression in ("scbQLength != 0", "self + 340", "scb + 248",
                       "scb + 252", "previous + 252", "next + 248",
                       "--scbQLength", "IOMalloc(256)", "checkScbAlign:scb",
                       "[self allocScb]", "bzero(scb, 256)", "+ 76", "+ 244"):
        assert expression in body, expression
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    name = "-[Adaptec2940 allocScb]"
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_command_completion_timing_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    signature = "- (void)commandCompleted:(Adaptec2940SCB *)scb"
    start = source.index(signature)
    body_end = source.index("\n}", start)
    body = source[start:body_end]
    for expression in ("scb_bytes + 224", "command_data + 8", "scb_bytes + 228",
                       "scb_bytes + 232", "timestamp[0] < start_low", "request[10]",
                       "request[11]", "request[7] = command_data[5]",
                       "IOUnscheduleFunc(a2940Timeout, scb)", "[self freeScb:scb]",
                       "[lock lock]", "[lock unlockWith:1]"):
        assert expression in body, expression
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    name = "-[Adaptec2940 commandCompleted:]"
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_parameter_methods_match_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    for signature, expressions in (
        ("- (int)setIntValues:(unsigned int *)values forParameter:(char *)parameter count:(unsigned int)count",
         ("A2940_AutoSense", "A2940_CmdQueue", "A2940_Sync", "count != 1",
          "Enabled", "Disabled", "-706", "self + 360")),
        ("- (int)getIntValues:(unsigned int *)values forParameter:(char *)parameter count:(unsigned int *)count",
         ("A2940_AutoSense", "A2940_CmdQueue", "A2940_Sync", "*count != 1",
          "values[0] = flags & 1", "(flags >> 1) & 1", "(flags >> 2) & 1", "-706")),
    ):
        start = source.index(signature)
        body_end = source.index("\n}", start)
        body = source[start:body_end]
        for expression in expressions:
            assert expression in body, expression
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in ("-[Adaptec2940 setIntValues:forParameter:count:]",
                 "-[Adaptec2940 getIntValues:forParameter:count:]"):
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


def test_controller_device_initializer_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    start = source.index("- initFromDeviceDescription:deviceDescription")
    end = source.index("\n/*\n * Return maximum transfer size.", start)
    body = source[start:end]
    for expression in (
        "[IODirectDevice getPCIConfigSpace:&configSpace",
        "for (i = 0; i < 6; ++i)", "baseAddress[i] & 1",
        "Multiple I/O Port Bases Found", "portRange.size = 256",
        "setInterruptList:(int *)&irq num:1", "setPortRangeList:&portRange num:1",
        "[super initFromDeviceDescription:deviceDescription]",
        "getPCIdevice:&deviceNumber", "PH_FindHA(busNumber, deviceNumber)",
        "[super startIOThread]", "cmdQueueEnable =", "syncModeEnable =",
        "queue_init(&activeQ)", "queue_init(&scbBadQ)",
        "channelInfo[0].hostInfo = (Adaptec2940HostInfo *)IOMalloc(140)",
        "[self initHostAdaptor]", "[self enableAllInterrupts]",
        "IOSleep(10000)", "[self registerDevice]",
    ):
        assert expression in body, expression
    assert body.index("setInterruptList") < body.index("[super initFromDeviceDescription")
    assert body.index("setPortRangeList") < body.index("[super initFromDeviceDescription")
    name = "-[Adaptec2940 initFromDeviceDescription:]"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_command_request_dispatch_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    signature = "- (void)commandRequestOccurred"
    start = source.index(signature)
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "[commandLock lock];",
        "queue_remove_first(&commandQ, message, Adaptec2940RequestMessage *, queue_link)",
        "case 0:", "[self threadExecuteRequest:message];",
        "case 1:", 'reason:"Reset Command Received"',
        "case 2:", "[message->condition_lock unlockWith:1];", "IOExitThread();",
        "[commandLock unlock];",
    ):
        assert expression in body, expression
    name = "-[Adaptec2940 commandRequestOccurred]"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_execute_command_message_matches_reference():
    thread = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Thread.m").read_text(encoding="ascii")
    signature = "- (int)executeCmdBuf:(Adaptec2940RequestMessage *)message"
    start = thread.index(signature)
    end = thread.index("\n}", start)
    body = thread[start:end]
    for expression in (
        "bcopy(CmdMessageTemplate, commandMessage, sizeof(commandMessage))",
        "message->status = 100",
        "message->condition_lock = [[NXConditionLock alloc] initWith:0]",
        "[commandLock lock]", "queue_enter(&commandQ, message",
        "[commandLock unlock]", "commandMessage[4] = interruptPortKern",
        "msg_send_from_kernel(commandMessage, 0, 0)", "result = -703",
        "[message->condition_lock lockWhen:1]", "[message->condition_lock free]",
    ):
        assert expression in body, expression
    template = "0x01000000, 0x00000018, 0, 0, 0, 0x00232324"
    assert template in thread
    name = "-[Adaptec2940 executeCmdBuf:]"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940Thread.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_thread_execute_request_matches_reference():
    thread = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Thread.m").read_text(encoding="ascii")
    start = thread.index("- (void)threadExecuteRequest:(Adaptec2940RequestMessage *)message")
    end = thread.index("\n- (void)runPendingCommands", start)
    body = thread[start:end]
    for expression in (
        "Adaptec2940SCB *scb = [self allocScb]", "request[2] & 0xe0",
        "commandLength = 6", "commandLength = 10", "commandLength = 12",
        "request[27] >> 4", "reservedBits & 3", "pageCount > A2940_SG_MAX",
        "message->client_task", "request + 56", "bytes[18]",
        "scb->target_channel_lun", "request + 2, scb->cdb, 12",
        "scb->command_buffer = message", "IOGetTimestamp(&scb->start_time)",
        "pageEnd - cursor", "scb->sg_list[index].address",
        "scb->sg_list[index].length", "scb->sg_pointer = physicalAddress",
        "PH_ScbSend(", "scb->host_status == 0x80", "queue_enter(&activeQ, scb",
        "IOScheduleFunc(a2940Timeout, scb", "++outstandingCount",
        "message->status = 7", "message->status = 14",
        "*(int *)(request + 28) = message->status",
        "[message->condition_lock unlockWith:1]",
    ):
        assert expression in body, expression
    name = "-[Adaptec2940 threadExecuteRequest:]"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940Thread.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_controller_interrupt_dispatch_matches_reference():
    source = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940.m").read_text(encoding="ascii")
    signature = "- (void)interruptOccurred"
    start = source.index(signature)
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in (
        "PH_IntHandler(hostAddress)", "if (levelIRQ != 0)",
        "while ((PH_IntHandler(hostAddress) & 0x60) != 0)",
        "PH_PollInt(hostAddress)", "[self enableAllInterrupts];",
        "PH_EnableInt(hostAddress)",
        '[self threadResetBus:nil channel:reinitChannel reason:"Fatal Command Error"]',
        "needReinit = 0;",
    ):
        assert expression in body, expression
    name = "-[Adaptec2940 interruptOccurred]"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940.m")
    assert entries[name]["status"] == "control-flow-confirmed"


def test_optima_helpers_match_reference_and_are_linked():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Optima.c"
    assert source_path.is_file()
    source = source_path.read_text(encoding="ascii")
    expected = (
        ("int PH_CalcDataSize", "Ph_CalcOptimaSize((unsigned short)count)"),
        ("int Ph_CalcOptimaSize", "10 * (count + 1) + 1532"),
        ("int Ph_GetOptimaConfig", "host[13] |= 1;"),
        ("int Ph_OptimaIndexClearBusy", "busy_map[index] = 0xff;"),
        ("int Ph_OptimaClearTargetBusy", "(unsigned long)scb_address + 12"),
        ("void Ph_OptimaClearDevQue", "empty seven-byte prologue/epilogue"),
        ("int Ph_OptimaClearQinFifo", "index <= 255"),
        ("void Ph_OptimaClearChannelBusy", "empty seven-byte prologue/epilogue"),
        ("int Ph_OptimaMoreFreeScb", "block[271] - (block[488] - 1)"),
        ("int Ph_OptimaGetFreeScb", "free_queue"),
        ("int Ph_OptimaReturnFreeScb", "scb_array"),
        ("unsigned char Ph_OptimaEnque", "A2940_OPTIMA_OUTB"),
        ("int Ph_OptimaEnqueHead", "Ph_OptimaQHead"),
        ("unsigned char Ph_OptimaQHead", "A2940_OPTIMA_INB"),
        ("unsigned int *Ph_OptimaLoadFuncPtrs", "function_table[110]"),
        ("int Ph_OptimaRequestSense", "scb[52] = 3;"),
        ("unsigned char Ph_OptimaEnableNextScbArray", "result <= 0x7e"),
        ("int Ph_OptimaCmdComplete", "qout_map[qout_index]"),
        ("int Ph_OptimaAbortActive", "qout_map[queue_position]"),
        ("int Ph_OptimaAbortActive", "callback(scb_index, scb_address, (int)io_base)"),
        ("int Ph_SetOptimaHaData", "block + 508"),
        ("int PH_RelocatePointers", "Ph_SetOptimaHaData"),
        ("char Ph_SetOptimaScratch", "Ph_ScbPageJustifyQIN"),
        ("int Ph_ScbPageJustifyQIN", "padding"),
        ("unsigned int Ph_MovPtrToScratch", "A2940_OPTIMA_OUTB"),
    )
    for signature, expression in expected:
        assert signature in source, signature
        start = source.index(signature)
        body_end = source.index("\n}", start)
        assert expression in source[start:body_end], signature
    project = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/PB.project").read_text(encoding="ascii")
    preamble = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Makefile.preamble").read_text(encoding="ascii")
    for name in ("Adaptec2940Sequencer.c", "Adaptec2940HIM.c", "Adaptec2940Config.c", "Adaptec2940Optima.c"):
        assert name in project and name in preamble
    harness = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/adaptec2940-checks.c").read_text(encoding="ascii")
    for case in ("optima-size-bounds", "optima-host-config", "optima-busy-map",
                 "optima-free-scb-rings", "optima-qin-enqueue",
                 "optima-request-sense", "optima-enable-array",
                 "optima-command-completion", "optima-host-setup-scratch",
                 "optima-abort-active", "optima-function-table",
                 "optima-qin-fifo", "optima-clear-noops",
                 "optima-relocate-pointers"):
        assert case in harness
    names = (
        "_PH_CalcDataSize", "_Ph_GetOptimaConfig", "_Ph_CalcOptimaSize",
        "_Ph_OptimaClearDevQue", "_Ph_OptimaIndexClearBusy",
        "_Ph_OptimaClearTargetBusy", "_Ph_OptimaClearChannelBusy",
        "_Ph_OptimaClearQinFifo",
        "_Ph_OptimaMoreFreeScb", "_Ph_OptimaGetFreeScb",
        "_Ph_OptimaReturnFreeScb", "_Ph_OptimaEnque",
        "_Ph_OptimaEnqueHead", "_Ph_OptimaQHead", "_Ph_OptimaLoadFuncPtrs",
        "_Ph_OptimaRequestSense", "_Ph_OptimaEnableNextScbArray",
        "_Ph_OptimaCmdComplete",
        "_Ph_OptimaAbortActive",
        "_Ph_SetOptimaHaData", "_Ph_SetOptimaScratch",
        "_PH_RelocatePointers",
        "_Ph_ScbPageJustifyQIN", "_Ph_MovPtrToScratch",
    )
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in names:
        assert mapped[name]["source_path"].endswith("Adaptec2940Optima.c")
        assert entries[name]["status"] == "control-flow-confirmed"


def test_him_terminate_command_matches_reference():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940HIM.c"
    source = source_path.read_text(encoding="ascii")
    start = source.index("void Ph_TerminateCommand(int scb_address")
    end = source.index("\n}", start)
    body = source[start:end]
    for expression in ("abort_queue[block[270]++]", "Ph_SetMgrStat(scb)",
                       "Ph_GetScbStatus", "current[11] = 16",
                       "++*(unsigned short *)(block + 266)"):
        assert expression in body, expression
    harness = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/adaptec2940-checks.c").read_text(encoding="ascii")
    assert "terminate-queued-scb" in harness
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped["_Ph_TerminateCommand"]["source_path"].endswith("Adaptec2940HIM.c")
    assert entries["_Ph_TerminateCommand"]["status"] == "control-flow-confirmed"


def test_pci_configuration_access_matches_reference():
    config_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Config.c"
    source = config_path.read_text(encoding="ascii")
    for expression in (
        "0x80000008U | (bus << 16) | (device << 11)",
        "(value & 0xff000000U) != 0xff000000U",
        "if (device > 0x0f)",
        "A2940_CONFIG_OUTB(0xcfa, bus)",
        "A2940_CONFIG_OUTB(0xcf8, 0x60)",
        "A2940_CONFIG_OUTL(0xcf8, 0)",
        "int PH_FindHA(short bus_number, short device_number)",
        "config != 276336644",
        "int PH_GetNumOfBuses(void)",
        "class_and_subclass == 0x06040000",
        "int Ph_AutoTermCable(int host_address)",
        "Ph_UpdateEeprom((unsigned short *)host, (int)io_base, 17)",
        "unsigned char PH_GetConfig(int host_address)",
        "io_base = (bar0 & 0xffffff00U) | (bar0 & 0xfcU)",
        "host[i + 32] |= 1",
        "int PH_InitHA(int host_address)",
        "if (load_result != 0)",
        "A2940_CONFIG_OUTB(io_base + 29, mode)",
    ):
        assert expression in source, expression
    harness = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/pci-config-checks.c"
    harness_text = harness.read_text(encoding="ascii")
    assert '#include "../Adaptec2940Config.c"' in harness_text
    for case in ("Ph_AccessConfig(2) == 1", "PH_FindMechanism() == 2",
                 "Ph_ReadConfig(-1, 4, 7, 0x10)",
                 "Ph_WriteConfig(-1, 4, 7, 0x10, 0x89abcdefU)",
                 "Ph_AutoTermCable((int)(unsigned long)host)",
                 "cable_status = 6", "PH_GetConfig((int)(unsigned long)host)",
                 "eeprom_read_result = 1", "PH_InitHA((int)(unsigned long)host)",
                 "expected_ports[16]", "Ph_ResetSCSI(0x100)",
                 "expected_ports[17]"):
        assert case in harness_text
    project = (config_path.parent / "PB.project").read_text(encoding="ascii")
    preamble = (config_path.parent / "Makefile.preamble").read_text(encoding="ascii")
    assert "Adaptec2940Config.c" in project and "Adaptec2940Recovery.c" in project
    assert "Adaptec2940Config.c" in preamble and "Adaptec2940Recovery.c" in preamble

    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in ("_PH_FindMechanism", "_Ph_ReadConfig", "_Ph_WriteConfig", "_Ph_AccessConfig"):
        assert mapped[name]["source_path"].endswith("Adaptec2940Config.c")
        assert entries[name]["status"] == "control-flow-confirmed"
    for name in ("_PH_GetNumOfBuses", "_PH_FindHA", "_PH_GetNumOfBusesOSM",
                 "_Ph_AutoTermCable", "_PH_GetConfig", "_PH_InitHA"):
        assert mapped[name]["source_path"].endswith("Adaptec2940Config.c")
        assert entries[name]["status"] == "control-flow-confirmed"


def test_scsi_reset_and_channel_abort_match_reference():
    recovery_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940Recovery.c"
    source = recovery_path.read_text(encoding="ascii")
    for expression in (
        "unsigned char Ph_ResetSCSI(int io_base)",
        "A2940_RECOVERY_OUTB(io_base + 146, 0x0f)",
        "Ph_Delay(io_base, 4000)",
        "unsigned char Ph_AbortChannel(int host_address, char status)",
        "Ph_PostNonActiveScb(host_address, (int)queue[0])",
        "queue[0] = saved_head",
        "Ph_ScbPrepare(host_address, (int *)(unsigned long)scb)",
    ):
        assert expression in source, expression
    harness = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/pci-config-checks.c").read_text(encoding="ascii")
    assert "Ph_ResetSCSI(0x100) == 0xbb" in harness
    assert "Ph_AbortChannel((int)(unsigned long)host, 9) == 4" in harness
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    for name in ("_Ph_ResetSCSI", "_Ph_AbortChannel"):
        assert mapped[name]["source_path"].endswith("Adaptec2940Recovery.c")
        assert entries[name]["status"] == "control-flow-confirmed"


def test_extended_message_negotiation_matches_reference_and_native_harness():
    source_path = DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Adaptec2940ExtMsgi.c"
    source = source_path.read_text(encoding="ascii")
    for expression in (
        "message_count = A2940_EXTMSG_INB(io_base + 58)",
        "Ph_Wt4Req(scb_address, (short)io_base)",
        "message_phase == 0xb0", "Ph_SetNeedNego(target",
        "Ph_SyncSet(scb_address)", "Ph_ClearFast20Reg(host_address, scb_address)",
        "Ph_LogFast20Map(host_address, scb)", "return (char)-16",
        "Ph_BadSeq(host_address, io_base)",
    ):
        assert expression in source, expression
    project = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/PB.project").read_text(encoding="ascii")
    preamble = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/Makefile.preamble").read_text(encoding="ascii")
    assert "Adaptec2940ExtMsgi.c" in project and "Adaptec2940ExtMsgi.c" in preamble
    harness = (DRIVER / "Adaptec2940.drvproj/Adaptec2940.lksproj/tests/ext-message-checks.c").read_text(encoding="ascii")
    for case in ("Unexpected message-in phase", "target-requested negotiation",
                 "Agreed sync parameters", "peer downgrade"):
        assert case in harness
    name = "_Ph_ExtMsgi"
    source_map = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    mapped = {name: row for row in source_map["mapped"] for name in row["reference_names"]}
    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    entries = {name: row for row in ledger["entries"] for name in row["names"]}
    assert mapped[name]["source_path"].endswith("Adaptec2940ExtMsgi.c")
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
