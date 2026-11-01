"""Explicit isolated Task13 contract snapshot."""
import json
from pathlib import Path

def contracts():
    return json.loads(Path(__file__).with_name("task13-contracts.json").read_text())
