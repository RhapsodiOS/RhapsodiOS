from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT.parent / "ATIMach64DisplayDriver.drvproj"
LKS = DRIVER / "ATIMach64DisplayDriver.lksproj"


def test_kernel_server_project_compiles_every_reconstructed_source_unit():
    preamble = (LKS / "Makefile.preamble").read_text(encoding="utf-8")
    for source in (
        "ATIMach64DisplayDriver.m", "ATIPrivate.m", "ProgramDAC.m", "ATI_BIOS.m",
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


def test_build_has_no_fixed_binary_or_host_only_assembly_shortcut():
    preamble = (LKS / "Makefile.preamble").read_text(encoding="utf-8")
    assert "ASFILES" not in preamble
    assert "ccache" not in preamble.lower()


def test_guest_build_script_uses_target_rbuild_and_stages_actual_artifact():
    script = (ROOT.parents[4] / "vm/build-i386-atimach64.sh").read_text(encoding="utf-8")
    assert "rbuild buildpackage --state" in script
    assert "--arch i386 --dir --target all" in script
    assert '"${NAME}_reloc"' in script
    assert "artifact is not identified as i386" in script
    assert 'cp -p "$RELOC" "$STAGE/"' in script
    assert "no package archive produced" in script
    assert "PACKAGE_STAGE" in script
    assert "rm -rf" not in script
