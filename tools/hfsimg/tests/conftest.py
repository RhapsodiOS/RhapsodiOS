import os
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))

import hfsfmt  # noqa: E402

TOAST = os.path.join(os.environ.get("RHAP_VM_ASSETS") or os.path.join(hfsfmt.REPO, "vm"),
                     "devtools.toast")
TOAST_OFFSET = 968 * 512


@pytest.fixture
def toast_location():
    """(path, byte offset) of the HFS partition in vm/devtools.toast."""
    if not os.path.exists(TOAST):
        pytest.skip("vm/devtools.toast is not present")
    return TOAST, TOAST_OFFSET


@pytest.fixture
def toast():
    """The Apple-mastered wrapped HFS Plus volume on the Developer Tools CD."""
    if not os.path.exists(TOAST):
        pytest.skip("vm/devtools.toast is not present")
    import volume
    v = volume.Volume(TOAST, TOAST_OFFSET)
    yield v
    v.close()
