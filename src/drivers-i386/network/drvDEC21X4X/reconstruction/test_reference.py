"""Reference-driven source and bundle checks for drvDEC21X4X."""

import hashlib
import os
import re
import sys
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[5]
REFERENCE = Path(os.environ["BINRECON_REFERENCE"])
PROJECT = REPO / "src/drivers-i386/network/drvDEC21X4X/DEC21X4X.drvproj"
SOURCE = PROJECT / "DEC21X4X.lksproj"
sys.path.insert(0, str(REPO / "tools/binrecon"))
from selector_check import reference_selectors, source_methods


GENERATED_SELECTORS = {
    "+[DEC21X4XNetworkKernelServerInstance kernelServerInstance]",
    "+[DEC21X4XNetworkVersion driverKitVersionForDEC21X4XNetwork]",
}


def _resource_list(project_file, variable):
    for line in project_file.read_text().splitlines():
        if line.startswith(variable + " ="):
            return set(line.split("=", 1)[1].split())
    return set()


def _pb_resource_list(project_file, variable):
    text = project_file.read_text()
    match = re.search(r"\b" + re.escape(variable) + r"\s*=\s*\(([^)]*)\)", text)
    return set() if match is None else {item.strip().strip('"') for item in match.group(1).split(",")}


def _default_table_content(path):
    return "\n".join(
        line for line in path.read_text().splitlines()
        if not line.startswith(('"Driver Version"', '"Version"'))
    ).strip()


class ReferenceTests(unittest.TestCase):
    def test_reference_methods_match_source_without_selector_drift(self):
        expected = reference_selectors(REFERENCE)
        actual = [method[0] for method in source_methods(SOURCE)]
        self.assertEqual(len(actual), len(set(actual)), "duplicate source method")
        self.assertEqual(set(actual) - expected, set())
        self.assertEqual(expected - set(actual), GENERATED_SELECTORS)

    def test_project_manifest_includes_reference_resources(self):
        reference_tables = {path.name for path in REFERENCE.parent.glob("*.table")}
        reference_strings = {path.name for path in (REFERENCE.parent / "English.lproj").glob("*.strings")}
        makefile = PROJECT / "Makefile"
        self.assertEqual(_resource_list(makefile, "GLOBAL_RESOURCES"), reference_tables)
        self.assertEqual(_resource_list(makefile, "LOCAL_RESOURCES"), reference_strings | {"DriverHelp"})
        pb_project = PROJECT / "PB.project"
        self.assertEqual(_pb_resource_list(pb_project, "OTHER_RESOURCES"), reference_tables | reference_strings | {"DriverHelp"})
        self.assertIn("DEC21X4XInspector.nib = DEC21X4XInspector.nib;", pb_project.read_text())

    def test_kernel_server_compiles_each_source_unit(self):
        makefile = SOURCE / "Makefile"
        self.assertEqual(
            _resource_list(makefile, "CLASSES"),
            {"DEC21142.m", "DEC21x4Init.m", "DEC21x4SRom.m"},
        )
        self.assertEqual(_resource_list(makefile, "CFILES"), {"DEC21X4XMII.c", "DEC21X4XUtil.c"})

    def test_class_fields_follow_recovered_instance_layout(self):
        header = (SOURCE / "DEC21X4X.h").read_text()
        ordered_fields = (
            "unsigned short ioBase;",
            "unsigned short irq;",
            "IONetwork *networkInterface;",
            "IONetbufQueue *transmitQueue;",
            "char isPromiscuous;",
            "char multicastEnabled;",
            "char resetAndEnabled;",
            "unsigned char sromAddressBits;",
            "netbuf_t txNetbuf[32];",
            "netbuf_t rxNetbuf[64];",
            "void *rxRing;",
            "void *txRing;",
            "unsigned int txPutIndex;",
            "unsigned int txDoneIndex;",
            "unsigned int txNumFree;",
            "unsigned int txIntCount;",
            "unsigned int rxDoneIndex;",
            "netbuf_t KDB_txBuf;",
            "void *memoryPtr;",
            "unsigned int memorySize;",
            "void *setupBuffer;",
            "unsigned int setupBufferPhysical;",
            "void *Adapter;",
            "unsigned int MediaCapableSaved;",
        )
        positions = [header.index(field) for field in ordered_fields]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("self->Adapter = adapterInfo;", (SOURCE / "DEC21142.m").read_text())

    def test_adapter_initialization_uses_recovered_adapter_state(self):
        source = (SOURCE / "DEC21x4Init.m").read_text()
        initializer = source.split("- (void)_initRegisters", 1)[0]
        self.assertNotIn("TODO", initializer)
        self.assertIn("DC21X4WriteGepRegister(adapterInfo,", initializer)
        self.assertIn("chipRevision = word[21]", initializer)
        self.assertIn("if (byte[485])", initializer)
        self.assertIn("case 0x141011:", initializer)
        self.assertIn("case 0x91011:", initializer)
        self.assertIn("case CHIP_REV_DC21142:", initializer)
        self.assertIn("DC21X4StartAdapter(adapterInfo)", initializer)
        self.assertIn("DC21X4StartAutoSenseTimer(adapterInfo, 6000)", initializer)

    def test_transmit_paths_use_recovered_ring_and_accounting_state(self):
        source = (SOURCE / "DEC21142.m").read_text()
        transmit = source.split("- (void)_transmitPacket:", 1)[1].split("\n- (", 1)[0]
        interrupt = source.split("- (void)_transmitInterruptOccurred", 1)[1].split("\n- (", 1)[0]
        self.assertNotIn("TODO", transmit)
        self.assertNotIn("TODO", interrupt)
        self.assertIn("self->txRing", transmit)
        self.assertIn("self->txPutIndex", transmit)
        self.assertIn("self->txNumFree", transmit)
        self.assertIn("self->txDoneIndex", interrupt)
        self.assertIn("incrementOutputPackets", interrupt)
        self.assertIn("nb_free(self->txNetbuf[index])", interrupt)

    def test_receive_interrupt_recycles_descriptors_and_delivers_replacements(self):
        source = (SOURCE / "DEC21142.m").read_text()
        receive = source.split("- (BOOL)_receiveInterruptOccurred", 1)[1].split("\n- (", 1)[0]
        self.assertNotIn("TODO", receive)
        self.assertIn("self->rxDoneIndex", receive)
        self.assertIn("self->rxRing", receive)
        self.assertIn("self->rxNetbuf", receive)
        self.assertIn("handleInputPacket:receivedNetbuf", receive)

    def test_debugger_send_uses_reserved_netbuf_and_records_polling_result(self):
        source = (SOURCE / "DEC21142.m").read_text()
        send = source.split("- (BOOL)sendPacket:", 1)[1].split("\n- (", 1)[0]
        self.assertNotIn("TODO", send)
        self.assertIn("self->KDB_txBuf", send)
        self.assertIn("self->txRing", send)
        self.assertIn("*((unsigned int *)adapterInfo + 156)", send)
        self.assertIn("*((unsigned int *)adapterInfo + 157)", send)

    def test_setup_filter_uses_transmit_ring_setup_frame_and_multicast_list(self):
        source = (SOURCE / "DEC21142.m").read_text()
        load_filter = source.split("- (BOOL)_loadSetupFilter:", 1)[1].split("\n- (", 1)[0]
        address_filter = source.split("- (BOOL)_setAddressFiltering:", 1)[1].split("\n- (", 1)[0]
        self.assertNotIn("TODO", load_filter)
        self.assertNotIn("TODO", address_filter)
        self.assertIn("self->setupBufferPhysical", load_filter)
        self.assertIn("self->txPutIndex", load_filter)
        self.assertIn("self->setupBuffer", address_filter)
        self.assertIn("self->multicastEnabled", address_filter)
        self.assertIn("[super multicastQueue]", address_filter)

    def test_transmit_queue_and_engine_controls_use_live_driver_state(self):
        source = (SOURCE / "DEC21142.m").read_text()
        transmit = source.split("- (void)_startTransmit", 1)[1].split("\n- (", 1)[0]
        receive = source.split("- (void)_startReceive", 1)[1].split("\n- (", 1)[0]
        queue = source.split("- (void)serviceTransmitQueue", 1)[1].split("\n- (", 1)[0]
        self.assertNotIn("TODO", transmit + receive + queue)
        self.assertIn("self->Adapter", transmit + receive)
        self.assertIn("self->txNumFree", queue)
        self.assertIn("self->transmitQueue", queue)

    def test_interrupt_dispatch_and_queue_entry_points_follow_reference_masks(self):
        source = (SOURCE / "DEC21142.m").read_text()
        interrupt = source.split("- (void)interruptOccurred", 1)[1].split("\n- (", 1)[0]
        transmit = source.split("- (void)transmit:", 1)[1].split("\n- (", 1)[0]
        counters = source.split("- (unsigned int)transmitQueueCount", 1)[1].split("\n- (", 1)[0]
        self.assertNotIn("TODO", interrupt + transmit + counters)
        self.assertIn("HandleGepInterrupt", interrupt)
        self.assertIn("_receiveInterruptOccurred", interrupt)
        self.assertIn("_transmitInterruptOccurred", interrupt)
        self.assertIn("self->transmitQueue", transmit + counters)

    def test_debugger_receive_uses_active_ring_and_hardware_timeout_state(self):
        source = (SOURCE / "DEC21142.m").read_text()
        receive = source.split("- (void)receivePacket:", 1)[1].split("\n- (", 1)[0]
        self.assertNotIn("TODO", receive)
        self.assertIn("self->resetAndEnabled", receive)
        self.assertIn("self->rxRing", receive)
        self.assertIn("self->rxDoneIndex", receive)
        self.assertIn("self->rxNetbuf", receive)

    def test_mode_and_lifecycle_methods_use_recovered_fields(self):
        source = (SOURCE / "DEC21142.m").read_text()
        methods = (
            "addMulticastAddress:", "disableAdapterInterrupts", "disableMulticastMode",
            "disablePromiscuousMode", "enableAdapterInterrupts", "enableMulticastMode",
            "enablePromiscuousMode", "free", "setPowerState:",
        )
        for method in methods:
            body = source.split("- (", 1)
            start = source.index(method)
            start = source.rfind("\n- (", 0, start)
            end = source.find("\n- (", start + 1)
            self.assertNotIn("TODO", source[start:end], method)
        self.assertIn("self->isPromiscuous = YES", source)
        self.assertIn("self->multicastEnabled = YES", source)
        self.assertIn("self->resetAndEnabled = NO", source)

    def test_device_initialization_allocates_rings_and_kdb_buffer_before_attach(self):
        source = (SOURCE / "DEC21142.m").read_text()
        initializer = source.split("- initFromDeviceDescription:", 1)[1].split("\n- (", 1)[0]
        self.assertNotIn("TODO", initializer)
        self.assertIn("[self _allocateMemory]", initializer)
        self.assertIn("self->KDB_txBuf = [self allocateNetbuf]", initializer)
        self.assertIn("[self resetAndEnable:YES]", initializer)
        self.assertIn("self->networkInterface = networkInterface", initializer)

    def test_c_translation_units_define_each_helper_once(self):
        definition = re.compile(
            r"(?m)^[A-Za-z_][\w\s\*]*?\s*([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\n\{"
        )
        definitions = {}
        for source_file in ("DEC21X4XMII.c", "DEC21X4XUtil.c"):
            names = definition.findall((SOURCE / source_file).read_text())
            for name in names:
                definitions.setdefault(name, []).append(source_file)
        duplicates = {name: files for name, files in definitions.items() if len(files) > 1}
        self.assertEqual(duplicates, {})

    def test_mii_autodetect_helpers_are_defined_by_the_recovered_media_state_machine(self):
        util = (SOURCE / "DEC21X4XUtil.c").read_text()
        mii = (SOURCE / "DEC21X4XMII.c").read_text()
        for name in ("DC21X4MiiAutoDetect", "DC21X4MiiAutoSense"):
            body = util.split("int " + name + "(", 1)[1].split("\n}", 1)[0]
            self.assertNotIn("return 0;", body)
            self.assertNotIn("int " + name + "(", mii)
        write_mii = mii.split("void WriteMii(", 1)[1].split("\n}", 1)[0]
        self.assertIn("*(unsigned short *)(adapter + 0x30)", write_mii)
        self.assertNotIn("csr9Port = 0", write_mii)

    def test_phy_connection_status_combines_negotiation_and_link_state(self):
        mii = (SOURCE / "DEC21X4XMII.c").read_text()
        body = mii.split("int MiiPhyGetConnectionStatus(", 1)[1].split("\n}", 1)[0]
        self.assertIn("*status = linkStatus | negotiationStatus", body)
        self.assertIn("negotiationStatus == 0x400", body)
        self.assertIn("linkStatus != 0", body)

    def test_adapter_helpers_use_pointer_signatures_and_reference_media_branches(self):
        header = (SOURCE / "DEC21X4X.h").read_text()
        util = (SOURCE / "DEC21X4XUtil.c").read_text()
        self.assertNotIn("unsigned void *adapter", header)
        self.assertIn("extern void DC21X4InitializeMediaRegisters(void *adapter, char reset);", header)
        self.assertIn("void DC21X4DynamicAutoSense(void *timerArg, void *adapter)", util)
        initializer = util.split("void DC21X4InitializeMediaRegisters(", 1)[1].split("\n}", 1)[0]
        self.assertIn("chipRevision == 0x141011 || chipRevision == 0x21011", initializer)
        self.assertIn("chipRevision == 0x91011", initializer)
        self.assertIn("chipRevision == 0x191011 || chipRevision == 0xff1011", initializer)

    def test_header_return_types_match_c_helper_definitions(self):
        header = (SOURCE / "DEC21X4X.h").read_text()
        sources = "\n".join(
            (SOURCE / name).read_text() for name in ("DEC21X4XUtil.c", "DEC21X4XMII.c")
        )
        definition = re.compile(
            r"(?m)^([A-Za-z_][\w\s\*]*?)\s*([A-Za-z_]\w*)\s*\(([^;{}]*)\)\s*\n\{"
        )
        defined_names = {match.group(2) for match in definition.finditer(sources)}
        declared_names = {
            match.group(1)
            for match in re.finditer(
                r"extern\s+[^\n;]*?\b([A-Za-z_]\w*)\s*\(", header
            )
        }
        self.assertEqual(defined_names - declared_names, set())
        declarations = re.finditer(
            r"extern\s+([^\n;]*?)([A-Za-z_]\w*)\s*\([^;]*\)\s*;", header
        )
        mismatches = {}
        for declaration in declarations:
            return_type, name = " ".join(declaration.group(1).split()), declaration.group(2)
            definition = re.search(
                r"(?m)^([^\n;{}]+?)\b" + re.escape(name) + r"\s*\([^;{}]*\)\s*\n\{",
                sources,
            )
            if definition:
                source_return = " ".join(definition.group(1).split())
                if source_return != return_type:
                    mismatches[name] = (return_type, source_return)
        self.assertEqual(mismatches, {})

    def test_srom_block_helpers_advance_the_callers_cursor(self):
        util = (SOURCE / "DEC21X4XUtil.c").read_text()
        fixed = util.split("void DC21X4ParseFixedBlock(", 1)[1].split("\n}", 1)[0]
        extended = util.split("void DC21X4ParseExtendedBlock(", 1)[1].split("\n}", 1)[0]
        self.assertIn("unsigned char **blockPtr", fixed)
        self.assertIn("*blockPtr = block", fixed)
        self.assertIn("unsigned char **blockPtr", extended)
        self.assertIn("*blockPtr = blockEnd", extended)

    def test_srom_root_parser_uses_byte_offsets_and_info_leaf_pointer(self):
        util = (SOURCE / "DEC21X4XUtil.c").read_text()
        parser = util.split("BOOL DC21X4ParseSRom(", 1)[1].split("\n}", 1)[0]
        self.assertIn("unsigned char *sromData", parser)
        self.assertIn("currentPtr = sromData + infoLeafLength", parser)
        self.assertIn("currentPtr += 2", parser)
        self.assertIn("*currentPtr++", parser)

    def test_reference_bundle_resources_are_present_and_unchanged(self):
        checked = 0
        for reference_file in REFERENCE.parent.rglob("*"):
            if not reference_file.is_file() or reference_file.name.startswith((REFERENCE.name, REFERENCE.stem)):
                continue
            if reference_file.name == "DEC21X4XNetwork":
                continue
            relative = reference_file.relative_to(REFERENCE.parent)
            source_relative = relative
            if relative.parts[:2] == ("English.lproj", "Help"):
                source_relative = Path("English.lproj", "DriverHelp", *relative.parts[2:])
            source_file = PROJECT / source_relative
            self.assertTrue(source_file.is_file(), f"missing bundle resource: {source_relative}")
            if source_relative.name == "Default.table":
                self.assertEqual(_default_table_content(source_file), _default_table_content(reference_file))
            else:
                self.assertEqual(hashlib.sha256(source_file.read_bytes()).digest(), hashlib.sha256(reference_file.read_bytes()).digest(), str(source_relative))
            checked += 1
        self.assertGreaterEqual(checked, 10)


if __name__ == "__main__":
    unittest.main()
