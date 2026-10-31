"""Generate controls using exact PExpert helper bodies, for host/native builds."""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c"
HELPERS = ("get_scsi_int_offset", "get_scsi_int_dma_offset", "get_audio_offset")


def generate(source=SOURCE):
    text = source.read_text()
    bodies = []
    for name in HELPERS:
        match = re.search(r"vm_offset_t " + name + r"\(\)\n\{.*?\n\}", text, re.S)
        if match is None:
            raise ValueError("cannot extract helper " + name)
        bodies.append(match.group())
    template = Path(__file__).with_suffix(".c").read_text()
    return template.replace("/* PRODUCTION_HELPERS */", "\n\n".join(bodies))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--source", type=Path, default=SOURCE)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    generated = generate(args.source).encode()
    (args.output / "pexpert_optional.c").write_bytes(generated)
    (args.output / "source.json").write_text(json.dumps({
        "source": str(args.source),
        "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
        "generated_sha256": hashlib.sha256(generated).hexdigest(),
        "helpers": HELPERS,
        "provider_boundary": "DTFindEntry/DTGetProperty; panic traps non-returning",
        "not_covered": "DriverKit matching, hardware probe, PPC execution on host",
    }, indent=2) + "\n")
