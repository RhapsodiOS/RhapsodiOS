"""BusLogic CCB residue must not remain in drvSym53C8xx sources."""
from pathlib import Path

import pytest

LKS = Path("src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj")

FORBIDDEN = (
    "sym_reset_chip",
    "sym_init_chip",
    "runPendingCommands",
    "allocCcb:",
    "@interface SYM53c8Controller",
    "@implementation SYM53c8Controller",
)

SOURCE_SUFFIXES = (".h", ".m", ".c")


def _source_text():
    chunks = []
    for path in LKS.iterdir():
        if path.suffix in SOURCE_SUFFIXES:
            chunks.append(path.read_text(encoding="utf-8", errors="replace"))
    return "\n".join(chunks)


@pytest.mark.parametrize("token", FORBIDDEN)
def test_no_buslogic_residue(token):
    assert token not in _source_text(), token
