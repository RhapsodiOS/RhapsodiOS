"""Gather the apks the install media is built from into one directory.

    python -m instmedia.collect OUTDIR --image IMAGE [--add DIR ...]

Takes the universal apks in IMAGE's /build/repo, the bootstrapped build
guest's repository, read in place without writing the image.  Then every
apk in each --add directory, in order; an added apk replaces the image's
builds, and any earlier added build, of the same package.  The image's thin
-i386 bootstrap builds are left out: the universal pass rebuilt those, and
phase 2's apk-installed root was proven with the universal ones.

Every apk is decompressed in full on the way in, so a damaged one is
refused rather than copied: the image's filesystem has known DUP blocks.
"""
import argparse
import gzip
import os
import sys
import tarfile
import zlib

import rhap_image
from instmedia import apkrepo

REPO = "/build/repo"


class CollectError(Exception):
    pass


def verify(name, data):
    """The apk's pkgname, after decompressing all of it, which checks the
    gzip CRC, and reading every member of it.  tarfile alone stops quietly
    at a damaged header and never reaches the CRC."""
    try:
        gzip.decompress(data)
        with apkrepo.open_apk(data) as tar:
            for m in tar:
                if m.isreg():
                    tar.extractfile(m).read()
        return apkrepo.read_pkginfo(data)["pkgname"]
    except (OSError, EOFError, tarfile.TarError, zlib.error, KeyError,
            apkrepo.RepoError) as e:
        raise CollectError("%s is damaged: %s" % (name, e))


def image_apks(image):
    """[(filename, bytes)] for the universal apks in image's repository."""
    out = []
    with rhap_image.Image(image) as img:
        repo = img.resolve(REPO)
        if repo is None:
            raise CollectError("%s has no %s" % (image, REPO))
        for name, ino, _ in sorted(img.listdir(REPO)):
            if name.endswith("-universal.apk"):
                out.append((name, img.read_file(ino)))
    return out


def dir_apks(directory):
    out = []
    for name in sorted(os.listdir(directory)):
        if name.endswith(".apk"):
            with open(os.path.join(directory, name), "rb") as f:
                out.append((name, f.read()))
    return out


def merge(*sources):
    """{filename: bytes}: each source's apks replace earlier sources'
    apks of the same package."""
    chosen = {}                 # pkgname -> [(filename, bytes)]
    for source in sources:
        mine = {}
        for name, data in source:
            mine.setdefault(verify(name, data), []).append((name, data))
        chosen.update(mine)
    out = {}
    for builds in chosen.values():
        for name, data in builds:
            if name in out:
                raise CollectError("two apks named %s" % name)
            out[name] = data
    return out


def main(argv):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("outdir")
    p.add_argument("--image", required=True)
    p.add_argument("--add", action="append", default=[])
    a = p.parse_args(argv[1:])
    try:
        if os.path.exists(a.outdir) and os.listdir(a.outdir):
            raise CollectError("%s is not empty" % a.outdir)
        apks = merge(image_apks(a.image), *[dir_apks(d) for d in a.add])
    except CollectError as e:
        print("instmedia.collect: %s" % e, file=sys.stderr)
        return 1
    os.makedirs(a.outdir, exist_ok=True)
    for name in sorted(apks):
        with open(os.path.join(a.outdir, name), "wb") as f:
            f.write(apks[name])
    print("%s: %d apks" % (a.outdir, len(apks)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
