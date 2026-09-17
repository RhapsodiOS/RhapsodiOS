"""Linux-eata stub residue must not remain in drvDPT2000 Kernel Server sources."""
from pathlib import Path

import pytest

LKS = Path(
    "src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj"
)

FORBIDDEN = (
    "@interface DPTSCSIDriver",
    "eataInitController",
    "eataResetBus",
    "eataAllocateResources",
    "eataFreeResources",
    "allocCp",
    "freeCp:",
    "runPendingCommands",
    "processCmdComplete",
    "struct dpt_config",
    "Based on Linux eata.c",
)

REQUIRED_FILES = (
    "EATAController.m",
    "EATAController.h",
    "EATASCSIBus.m",
    "EATASCSIBus.h",
)

GONE_FILES = (
    "DPTSCSIDriver.m",
    "DPTSCSIDriver.h",
    "DPTSCSIDriverRoutines.m",
    "DPTSCSIDriverThread.m",
    "DPTSCSIDriverPrivate.h",
    "DPTSCSIDriverTypes.h",
)

TEXT_SUFFIXES = {".h", ".m", ".c", ".s"}


def _lks_text_files():
    assert LKS.is_dir(), LKS
    for path in sorted(LKS.rglob("*")):
        if path.is_file() and path.suffix in TEXT_SUFFIXES:
            yield path


def test_lks_has_no_linux_eata_residue():
    hits = []
    for path in _lks_text_files():
        text = path.read_text(encoding="latin-1")
        for token in FORBIDDEN:
            if token in text:
                hits.append(f"{path.name}: {token}")
    assert hits == [], hits


def test_both_reloc_classes_exist_and_stub_files_are_gone():
    for name in REQUIRED_FILES:
        assert (LKS / name).is_file(), name
    for name in GONE_FILES:
        assert not (LKS / name).exists(), name
