from pathlib import Path
import re


HEADER = Path(
    "src/drivers-i386/network/drvDEC21142/DEC21142.drvproj/"
    "DEC21142.lksproj/DEC21142.h"
)
SOURCE = Path(
    "src/drivers-i386/network/drvDEC21142/DEC21142.drvproj/"
    "DEC21142.lksproj/DEC21142.m"
)


def declarations(header):
    match = re.search(
        r"@interface\s+DEC21142\s*:\s*\w+\s*\{(.*?)\n\}",
        header,
        re.S,
    )
    assert match is not None
    names = []
    for line in match.group(1).splitlines():
        line = line.split("/*", 1)[0].strip()
        field = re.search(r"([A-Za-z_]\w*)(?:\s*\[[^]]+\])?\s*;$", line)
        if field:
            names.append(field.group(1))
    return names


def test_instance_variables_match_reference_order():
    header = HEADER.read_text(encoding="utf-8-sig")
    assert re.search(r"@interface\s+DEC21142\s*:\s*IOEthernet\b", header)
    assert declarations(header) == [
        "ioBase", "irq", "myAddress", "networkInterface", "transmitQueue",
        "isPromiscuous", "multicastEnabled", "resetAndEnabled",
        "sromAddressBits", "enetAddressOffset", "txNetbuf", "rxNetbuf",
        "rxRing", "txRing", "txPutIndex", "txDoneIndex", "txNumFree",
        "txIntCount", "rxDoneIndex", "KDB_txBuf", "memoryPtr", "memorySize",
        "setupBuffer", "setupBufferPhysical", "interruptMask", "operationMode",
        "connector",
    ]


def test_instance_variable_types_offsets_and_total_size_match_ida():
    header = HEADER.read_text(encoding="utf-8-sig")
    match = re.search(
        r"@interface\s+DEC21142\s*:\s*\w+\s*\{(.*?)\n\}", header, re.S
    )
    assert match is not None
    counts = {"TX_RING_SIZE": 32, "RX_RING_SIZE": 64}
    sizes = {
        "unsigned short": (2, 2),
        "enet_addr_t": (6, 2),
        "IONetwork *": (4, 4),
        "IONetbufQueue *": (4, 4),
        "char": (1, 1),
        "unsigned char": (1, 1),
        "unsigned int": (4, 4),
        "netbuf_t": (4, 4),
        "void *": (4, 4),
        "unsigned long": (4, 4),
        "int": (4, 4),
    }
    expected_offsets = {
        "ioBase": 372, "irq": 374, "myAddress": 376,
        "networkInterface": 384, "transmitQueue": 388,
        "isPromiscuous": 392, "multicastEnabled": 393,
        "resetAndEnabled": 394, "sromAddressBits": 395,
        "enetAddressOffset": 396, "txNetbuf": 400, "rxNetbuf": 528,
        "rxRing": 784, "txRing": 788, "txPutIndex": 792,
        "txDoneIndex": 796, "txNumFree": 800, "txIntCount": 804,
        "rxDoneIndex": 808, "KDB_txBuf": 812, "memoryPtr": 816,
        "memorySize": 820, "setupBuffer": 824,
        "setupBufferPhysical": 828, "interruptMask": 832,
        "operationMode": 836, "connector": 840,
    }
    offset = 372
    parsed_offsets = {}
    for raw_line in match.group(1).splitlines():
        line = raw_line.split("/*", 1)[0].strip()
        if not line:
            continue
        field = re.fullmatch(
            r"(?P<type>.+?)(?P<name>[A-Za-z_]\w*)"
            r"(?:\[(?P<count>[^]]+)\])?\s*;", line
        )
        assert field is not None, line
        type_name, name = field.group("type").strip(), field.group("name")
        assert type_name in sizes, type_name
        size, alignment = sizes[type_name]
        count = counts.get(field.group("count"), 1)
        offset = (offset + alignment - 1) & ~(alignment - 1)
        parsed_offsets[name] = offset
        offset += size * count
    assert parsed_offsets == expected_offsets
    assert offset == 844


def test_header_selectors_match_recovered_method_shapes():
    header = HEADER.read_text(encoding="utf-8-sig")
    expected = (
        r"-\s*\(IOReturn\)getPowerState:\(void\s*\*\)powerState\s*;",
        r"-\s*\(IOReturn\)getPowerManagement:\(void\s*\*\)powerManagement\s*;",
        r"-\s*\(BOOL\)_verifyCheckSum\s*;",
        r"-\s*\(BOOL\)_loadSetupFilter:\(BOOL\)waitForCompletion\s*;",
        r"-\s*\(BOOL\)_setAddressFiltering:\(BOOL\)waitForCompletion\s*;",
        r"-\s*\(void\)_getStationAddress:\(enet_addr_t\s*\*\)address\s*;",
    )
    for signature in expected:
        assert re.search(signature, header), signature


def test_implementation_keeps_reference_reset_and_power_behavior():
    source = SOURCE.read_text(encoding="utf-8-sig")
    reset = re.search(r"-\s*\(BOOL\)resetAndEnable:\(BOOL\)enable", source)
    assert reset is not None
    reset_body = source[reset.start():source.index("\n}", reset.start())]
    assert "resetAndEnabled = 0;" in reset_body
    assert "resetAndEnabled = 1;" in reset_body
    assert "if ([self _initRxRing] == NO || [self _initTxRing] == NO)" in reset_body
    assert "if (enable) {" in reset_body
    assert "if ([self enableAllInterrupts] != IO_R_SUCCESS)" in reset_body
    power = re.search(r"-\s*\(IOReturn\)setPowerState:\(unsigned int\)powerState", source)
    assert power is not None
    power_body = source[power.start():source.index("\n}", power.start())]
    assert "if (powerState != 3)" in power_body
    assert "resetAndEnabled = 0;" in power_body
    assert "return IO_R_SUCCESS;" in power_body


def test_tx_ring_initialization_uses_the_instance_queue():
    source = SOURCE.read_text(encoding="utf-8-sig")
    start = re.search(r"-\s*\(BOOL\)_initTxRing", source)
    assert start is not None
    body = source[start.start():source.index("\n}", start.start())]
    assert "void *transmitQueue;" not in body
    assert "txNumFree = TX_RING_SIZE;" in body
    assert "if (transmitQueue != nil)" in body
    assert "transmitQueue = [[IONetbufQueue alloc]" in body


def test_register_setup_uses_instance_connector_and_operation_mode():
    source = SOURCE.read_text(encoding="utf-8-sig")
    start = re.search(r"-\s*\(void\)_initRegisters", source)
    assert start is not None
    body = source[start.start():source.index("\n}", start.start())]
    assert "unsigned int mediaSelection;" not in body
    assert "unsigned int connector;" not in body
    assert "if (connector == CONNECTOR_AUI)" in body
    assert "else if (connector == CONNECTOR_10BASET)" in body
    assert "else if (connector == CONNECTOR_BNC)" in body
    assert "operationMode = 65609;" in body


def test_dma_translation_uses_output_addresses_and_checks_failures():
    source = SOURCE.read_text(encoding="utf-8-sig")
    register_start = re.search(r"-\s*\(void\)_initRegisters", source)
    allocation_start = re.search(r"-\s*\(BOOL\)_allocateMemory", source)
    assert register_start is not None and allocation_start is not None
    register_body = source[register_start.start():source.index("\n}", register_start.start())]
    allocation_body = source[allocation_start.start():source.index("\n}", allocation_start.start())]
    assert "IOPhysicalFromVirtual(task, (vm_address_t)rxRing, &physAddr) != IO_R_SUCCESS" in register_body
    assert "IOPhysicalFromVirtual(task, (vm_address_t)txRing, &physAddr) != IO_R_SUCCESS" in register_body
    assert "IOPhysicalFromVirtual(task, (vm_address_t)setupBuffer, &setupBufferPhysical) != IO_R_SUCCESS" in allocation_body


def test_packet_descriptor_translation_checks_both_page_segments():
    source = SOURCE.read_text(encoding="utf-8-sig")
    start = re.search(r"static BOOL IOUpdateDescriptorFromNetBuf", source)
    assert start is not None
    body = source[start.start():source.index("\n}", start.start())]
    assert "IOPhysicalFromVirtual(task, (vm_address_t)bufAddr, &physAddr1) != IO_R_SUCCESS" in body
    assert "IOPhysicalFromVirtual(task, (vm_address_t)nextPageAddr, &physAddr2) != IO_R_SUCCESS" in body


def test_descriptor_helper_uses_the_reference_receive_buffer_length():
    source = SOURCE.read_text(encoding="utf-8-sig")
    start = re.search(r"static BOOL IOUpdateDescriptorFromNetBuf", source)
    assert start is not None
    body = source[start.start():source.index("\n}", start.start())]
    assert "bufSize = 1520;" in body
    assert "bufSize = SETUP_FRAME_SIZE;" not in body


def test_debugger_receive_uses_the_same_first_last_error_mask():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, "receivePacket")
    assert "(status & 0x00008300) == 0x00000300" in body


def test_network_attachment_passes_station_address_by_value():
    source = SOURCE.read_text(encoding="utf-8-sig")
    assert "[super attachToNetworkWithAddress:myAddress]" in source


def test_initializer_uses_reference_debug_buffer_and_reset_path():
    source = SOURCE.read_text(encoding="utf-8-sig")
    start = re.search(r"-\s*initFromDeviceDescription:\(IODeviceDescription \*\)deviceDescription", source)
    assert start is not None
    body = source[start.start():source.index("\n}", start.start())]
    assert "[self _getStationAddress:&myAddress];" in body
    assert "KDB_txBuf = [self allocateNetbuf];" in body
    assert "resetAndEnabled = 0;" in body
    assert "[self resetAndEnable:NO] == NO" in body
    assert "[self _init]" not in body


def test_rx_ring_uses_aligned_netbufs_and_reference_descriptor_flags():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, "_initRxRing")
    assert "[self allocateNetbuf]" in body
    assert "IOUpdateDescriptorFromNetBuf(netbuf, descriptor, YES)" in body
    assert 'IOPanic("allocateNetbuf returned NULL in _initRxRing")' in body
    assert 'IOPanic("_initRxRing")' in body


def test_receive_interrupt_matches_descriptor_validity_and_network_delivery():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, "_receiveInterruptOccurred")
    assert "(status & 0x00008300) == 0x00000300" in body
    assert "frameLength > 0x3B" in body
    assert "IOUpdateDescriptorFromNetBuf(newNetbuf, descriptor, YES)" in body
    assert "[networkInterface incrementInputErrors]" in body
    assert "[networkInterface handleInputPacket:oldNetbuf extra:0]" in body


def test_tx_completion_updates_the_attached_network_interface():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, "_transmitInterruptOccurred")
    assert "[networkInterface incrementOutputPackets]" in body
    assert "[networkInterface incrementOutputErrors]" in body
    assert "[_serverInstance" not in body


def test_recovered_method_return_types_are_declared_in_the_header():
    header = HEADER.read_text(encoding="utf-8-sig")
    assert "- (void)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout;" in header
    assert "- (BOOL)_initRxRing;" in header
    assert "- (BOOL)_initTxRing;" in header
    assert "- (BOOL)_receiveInterruptOccurred;" in header
    assert "- (BOOL)_transmitInterruptOccurred;" in header
    assert "- (void)_transmitPacket:(netbuf_t)packet;" in header


def test_public_method_signatures_match_ida_return_abi():
    header = HEADER.read_text(encoding="utf-8-sig")
    assert re.search(r"-\s*\(id\)free\s*;", header)
    assert "- (void)addMulticastAddress:(enet_addr_t *)address;" in header
    assert "- (void)removeMulticastAddress:(enet_addr_t *)address;" in header
    assert "- (BOOL)enablePromiscuousMode;" in header
    assert "- (BOOL)enableMulticastMode;" in header
    assert "- (int)pendingTransmitCount;" in header
    assert "- (int)transmitQueueCount;" in header
    assert "- (int)transmitQueueSize;" in header


def test_cleanup_uses_the_network_interface_and_declared_instance_state():
    source = SOURCE.read_text(encoding="utf-8-sig")
    assert "_serverInstance" not in source
    start = re.search(r"-\s*\(id\)free\b", source)
    assert start is not None
    free_body = source[start.start():source.index("\n}", start.start())]
    assert "[networkInterface free]" in free_body


def test_chip_init_propagates_address_filter_setup_failure():
    source = SOURCE.read_text(encoding="utf-8-sig")
    body = method_body(source, "_init")
    assert "return [self _setAddressFiltering:YES];" in body


def test_media_constants_match_the_configuration_connector_values():
    header = HEADER.read_text(encoding="utf-8-sig")
    for name, value in (("AUTO", 0), ("BNC", 1), ("AUI", 2), ("10BASET", 3)):
        assert re.search(r"#define CONNECTOR_" + name + r"\s+" + str(value) + r"\b", header)


def method_body(source, name):
    start = re.search(r"-\s*\([^)]*\)" + re.escape(name) + r"\b", source)
    assert start is not None, name
    end = source.index("\n}", start.start())
    return source[start.start():end]
