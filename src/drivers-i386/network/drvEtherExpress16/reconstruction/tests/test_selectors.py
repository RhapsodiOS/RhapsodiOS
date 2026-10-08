from pathlib import Path
import sys

import pytest

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / "tools" / "binrecon"))
from binrecon.source_map import source_sites

SOURCE_DIR = ROOT / "src/drivers-i386/network/drvEtherExpress16/EtherExpress16.drvproj/EtherExpress16.lksproj"
PRIVATE_CLASS = "EtherExpress16(EtherExpress16Private)"


@pytest.mark.parametrize(
    "selector",
    ["_configEE16:", "_resetEE16:", "_configureMulticastAddresses"],
)
def test_private_selectors_match_reference(selector):
    sites = source_sites(ROOT, SOURCE_DIR)
    symbol = f"-[{PRIVATE_CLASS} {selector}]"
    assert symbol in sites
