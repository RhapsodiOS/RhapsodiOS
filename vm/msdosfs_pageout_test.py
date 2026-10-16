"""Compile and run the actual MSDOSFS pageout body against a write fixture."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args()
    source = (ROOT / "src/kernel-7/bsd/msdosfs/msdosfs_vnops.c").read_text()
    body = re.search(r"static int\nmsdosfs_pageout\(.*?\n\}", source, re.S).group()
    template = Path(__file__).with_suffix(".c").read_text()
    start = source.index("\t\tif (uio->uio_offset + n > dep->de_FileSize) {")
    end = source.index("\n\n\t\tbn =", start)
    template = template.replace("/* BODY write growth */", source[start:end])
    with tempfile.TemporaryDirectory(prefix="msdosfs-pageout-") as tmp:
        path = Path(tmp) / "pageout.c"
        binary = Path(tmp) / "pageout.exe"
        path.write_text(template.replace("/* BODY msdosfs_pageout */", body))
        subprocess.run([args.cc, "-std=gnu89", "-Wno-deprecated-non-prototype",
                        str(path), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
