"""Mailbox protocol residue must not remain in drvAdaptec6X60 sources."""
from pathlib import Path

import pytest

LKS = Path("src/drivers-i386/scsi/drvAdaptec6X60/Adaptec6X60.drvproj/Adaptec6X60.lksproj")

FORBIDDEN = (
    "AIC_CMD_INIT",
    "AIC_CMD_START_SCSI",
    "AIC_CMD_SET_MB_ENABLE",
    "AIC_CMD_GET_BIOS_INFO",
    "aic_setup_mb_area",
    "aicMbArea",
    "runPendingCommands",
    "allocCcb:",
)

SOURCE_SUFFIXES = (".h", ".m", ".c")


def _source_text():
    chunks = []
    for path in LKS.iterdir():
        if path.suffix in SOURCE_SUFFIXES:
            chunks.append(path.read_text(encoding="utf-8", errors="replace"))
    return "\n".join(chunks)


@pytest.mark.parametrize("token", FORBIDDEN)
def test_no_mailbox_residue(token):
    assert token not in _source_text(), token
