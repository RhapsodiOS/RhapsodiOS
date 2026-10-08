from pathlib import Path
import re

HEADER = Path("src/drivers-i386/network/drvEtherExpress16/EtherExpress16.drvproj/EtherExpress16.lksproj/EtherExpress16.h")
EXPECTED_IVARS = (
    "base", "irq", "myAddress", "network", "resetLabel", "boardID",
    "interfaceConnector", "boardType", "xmtQueue", "xmtActive",
    "promiscuousEnabled", "multicastEnabled", "multicastConfigured",
    "membase", "memused", "scb_off", "frf_off", "lrf_off", "frb_off",
    "lrb_off", "tcb_off", "tbd_off", "tbuf_off",
)
EXPECTED_TYPES = (
    "unsigned short", "int", "enet_addr_t", "IONetwork *",
    "struct { int val[14]; }", "unsigned short", "int", "int", "id",
    "char", "char", "char", "char", "unsigned short", "unsigned int",
    "unsigned short", "unsigned short", "unsigned short", "unsigned short",
    "unsigned short", "unsigned short", "unsigned short", "unsigned short",
)


def test_class_superclass_and_ivar_order_match_reference_metadata():
    source = HEADER.read_text(encoding="utf-8-sig")
    declaration = re.search(r"@interface\s+EtherExpress16\s*:\s*(\w+)\s*\{(.*?)\n\}", source, re.S)
    assert declaration is not None
    assert declaration.group(1) == "IOEthernet"
    body = re.sub(r"/\*.*?\*/", "", declaration.group(2), flags=re.S)
    names = []
    types = []
    for line in body.splitlines():
        line = line.strip()
        if not line:
            continue
        match = re.search(r"(.+?)([A-Za-z_]\w*)\s*(?:\[[^\]]+\])?\s*;\s*$", line)
        assert match is not None, f"unrecognized ivar declaration: {line}"
        types.append(" ".join(match.group(1).split()))
        names.append(match.group(2))
    assert tuple(names) == EXPECTED_IVARS
    assert tuple(types) == EXPECTED_TYPES
