from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT.parent / "ATIMach64DisplayDriver.drvproj"
LKS = DRIVER / "ATIMach64DisplayDriver.lksproj"
SHIPPED_IO_PORTS = (
    "0x02e8-0x02ef 0x03b0-0x03df  0x06ec-0x06ef 0x0aec-0x0aef "
    "0x0eec-0x0eef 0x12ec-0x12ef 0x16ec-0x16ef 0x1aec-0x1aef "
    "0x1eec-0x1eef 0x42ec-0x42ef 0x46ec-0x46ef 0x4aec-0x4aef "
    "0x4eec-0x4eef 0x52ec-0x52ef 0x5eec-0x5eef 0x62ec-0x62ef "
    "0x6aec-0x6aef 0x6eec-0x6eef 0x72ec-0x72ef 0x76ec-0x76ef"
)


def _table_values(path):
    text = path.read_text(encoding="utf-8")
    return dict(re.findall(r'"([^"]+)"\s*=\s*"([^"]*)"', text))


def test_kernel_server_project_compiles_every_reconstructed_source_unit():
    preamble = (LKS / "Makefile.preamble").read_text(encoding="utf-8")
    project_makefile = (LKS / "Makefile").read_text(encoding="utf-8")
    assert "CLASSES = ATIMach64DisplayDriver.m" in project_makefile
    for source in (
        "ATIPrivate.m", "ProgramDAC.m", "ATI_BIOS.m",
        "ATIData.c", "ATIbios16.c", "ATIbios.s",
    ):
        assert source in preamble
    assert "ATIBIOS_ASM_OBJECT = ATIbios.o" in preamble
    assert "OTHERLINKEDOFILES += $(ATIBIOS_ASM_OBJECT)" in preamble
    assert "$(ATIBIOS_ASM_OBJECT): ATIbios.s" in preamble
    assert "$(CC) $(ARCHITECTURE_FLAGS) $(ALL_CFLAGS) -c -o $@ $<" in preamble


def test_wire_load_command_and_original_resource_variants_are_kept():
    load_commands = (LKS / "Load_Commands.sect").read_text(encoding="utf-8")
    assert "WIRE" in load_commands
    project = (DRIVER / "Makefile").read_text(encoding="utf-8")
    for resource in (
        "Default.table", "PCI2Mb.table", "PCI4Mb.table", "VLB4Mb.table",
        "Display.modes", "PCI2Mb.modes", "PCI4Mb.modes", "VLB4Mb.modes",
    ):
        assert resource in project


def test_device_tables_keep_the_shipped_match_ids_and_version():
    pci_ids = "0x47581002 0x43581002 0x45541002 0x56541002"
    driver_info = (DRIVER / "DriverInfo").read_text(encoding="utf-8")
    assert re.search(r'DEFAULT_DRIVER_VERSION\s*=\s*"5\.01"\s*;', driver_info)
    for name in ("Default.table", "PCI2Mb.table", "PCI4Mb.table", "VLB4Mb.table"):
        table = _table_values(DRIVER / name)
        assert table["Version"] == "5.01"
    for name in ("PCI2Mb.table", "PCI4Mb.table"):
        table = _table_values(DRIVER / name)
        assert table["Auto Detect IDs"] == pci_ids


def test_default_table_reserves_the_vga_aperture_and_device_io_ports():
    table = _table_values(DRIVER / "Default.table")
    assert table["VGA Memory Maps"] == "0xa0000-0xbffff 0xc0000-0xcffff"
    assert table["Memory Maps"] == "0x07800000-0x07bfffff 0xa0000-0xbffff 0xc0000-0xcffff"
    assert table["I/O Ports"] == SHIPPED_IO_PORTS


def test_each_configuration_keeps_its_framebuffer_and_help_resources():
    vga = "0xa0000-0xbffff 0xc0000-0xcffff"
    expected = {
        "Default.table": ("0x07800000-0x07bfffff " + vga, "ATIMach64_VL_2MB.rtfd"),
        "PCI2Mb.table": ("0xfc000000-0xfc1fffff " + vga, "ATIMach64_PCI_2MB.rtfd"),
        "PCI4Mb.table": ("0xfc000000-0xfc3fffff " + vga, "ATIMach64_PCI_4MB.rtfd"),
        "VLB4Mb.table": ("0x07800000-0x07bfffff " + vga, "ATIMach64_VL_4MB.rtfd"),
    }
    for name, (memory_maps, help_file) in expected.items():
        table = _table_values(DRIVER / name)
        assert table["Memory Maps"] == memory_maps
        assert table["VGA Memory Maps"] == vga
        assert table["I/O Ports"] == SHIPPED_IO_PORTS
        assert table["Help File"] == help_file
        assert (DRIVER / "English.lproj" / "DriverHelp" / help_file).is_dir()


def test_build_generated_server_and_driver_versions_are_not_duplicated():
    for name in ("Default.table", "PCI2Mb.table", "PCI4Mb.table", "VLB4Mb.table"):
        table = _table_values(DRIVER / name)
        assert "Server Name" not in table
        assert "Driver Version" not in table


def test_build_has_no_fixed_binary_or_host_only_assembly_shortcut():
    preamble = (LKS / "Makefile.preamble").read_text(encoding="utf-8")
    assert "ASFILES" not in preamble
    assert "ccache" not in preamble.lower()


def test_guest_build_script_uses_target_rbuild_and_stages_actual_artifact():
    script = (ROOT.parents[4] / "vm/build-i386-atimach64.sh").read_text(encoding="utf-8")
    assert "rbuild buildpackage --state" in script
    assert "--arch i386" in script
    assert "--dir --target all" in script
    assert '"./private/Drivers/i386/${NAME}.config/${NAME}_reloc"' in script
    assert "artifact is not identified as i386" in script
    assert 'cp -p "$RELOC" "$STAGE/"' in script
    assert "no package archive produced" in script
    assert "PACKAGE_STAGE" in script
    assert "rm -rf" not in script


def test_enter_linear_mode_snapshots_crtc_parameter_before_bios_call():
    source = (LKS / "ATIMach64DisplayDriver.m").read_text(encoding="utf-8")
    body = re.search(r"-\s*\(void\)enterLinearMode\s*\{(?P<body>.*?)\n\}", source, re.S)
    assert body
    method = body.group("body")
    snapshot = method.index("crtTable = mode->parameters;")
    bios_call = method.index("[atiBios setApertureEnable:")
    assert snapshot < bios_call
    assert "crtTable:(ATI_CRTCRecord *)crtTable" in method


def test_enter_linear_mode_keeps_reference_byte_and_pitch_branch_shapes():
    source = (LKS / "ATIMach64DisplayDriver.m").read_text(encoding="utf-8")
    body = re.search(r"-\s*\(void\)enterLinearMode\s*\{(?P<body>.*?)\n\}", source, re.S)
    assert body
    method = body.group("body")
    assert "char gamma;" in method
    assert "pitchSize = 2;" in method
    assert "if (mode->width == 1024)" in method
