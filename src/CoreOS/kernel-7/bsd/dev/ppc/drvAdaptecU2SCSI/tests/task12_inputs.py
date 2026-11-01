"""The explicit isolated HIM fixture and contract inputs."""

import json
from pathlib import Path


def contracts():
    return json.loads(Path(__file__).with_name("task12-contracts.json").read_text())
