"""Compile exact ext2 superblock I/O bodies with controlled buffer providers."""
from pathlib import Path
import argparse, hashlib, json, re
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src/kernel-7/bsd/ext2fs/ext2fs_vfsops.c"

def generate():
    source = SOURCE.read_text()
    bodies = []
    for name in ("ext2fs_device_bshift", "ext2fs_read_super_bytes", "ext2fs_sbupdate"):
        matches = re.findall(r"(?:static )?int\n" + name + r"\([^;]*?\n\{.*?\n\}", source, re.S)
        if not matches:
            raise ValueError("missing production body: " + name)
        bodies.append(matches[-1])
    return Path(__file__).with_suffix(".c").read_text().replace("/* PRODUCTION_BODIES */", "\n\n".join(bodies))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(exist_ok=False)
    data = generate().encode()
    (args.output / "sector_io.c").write_bytes(data)
    (args.output / "source.json").write_text(json.dumps({"source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(), "generated_sha256": hashlib.sha256(data).hexdigest(), "boundary": "bread/getblk/brelse/encode/write; exact production bodies; does not replace native filesystem execution"}, indent=2))
