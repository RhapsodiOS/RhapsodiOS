"""Synthetic apks for the install-media builder's tests.

make() writes a gzip'd tar the way rbuild packs one: .PKGINFO first, then
the members, named with a leading "./" unless dot_slash is False (the
bootstrap repository's apks have it, rbuild's newer ones do not).
"""
import gzip
import io
import os
import tarfile

T = 946684800


def pkginfo(name, version="1", arch="universal-apple-rhapsody", **extra):
    lines = ["pkgname = %s" % name, "pkgver = %s" % version,
             "arch = %s" % arch]
    lines += ["%s = %s" % kv for kv in sorted(extra.items())]
    return ("\n".join(lines) + "\n").encode()


def d(path, mode=0o755, mtime=T):
    return ("dir", path, mode, mtime, None)


def f(path, data, mode=0o644, mtime=T, uid=0, gid=0):
    return ("reg", path, mode, mtime, data, uid, gid)


def ln(path, target, mtime=T):
    return ("sym", path, 0o755, mtime, target)


def hard(path, target, mtime=T):
    return ("lnk", path, 0o644, mtime, target)


def dev(path, kind, major, minor, mode=0o640, mtime=T):
    return (kind, path, mode, mtime, (major, minor))


def tar_bytes(info, members, dot_slash=True):
    buf = io.BytesIO()
    prefix = "./" if dot_slash else ""
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
        if info is not None:
            ti = tarfile.TarInfo(".PKGINFO")
            ti.size, ti.mtime = len(info), T
            t.addfile(ti, io.BytesIO(info))
        for m in members:
            kind, path, mode, mtime = m[:4]
            ti = tarfile.TarInfo(prefix + path)
            ti.mode, ti.mtime = mode, mtime
            payload = None
            if kind == "dir":
                ti.type = tarfile.DIRTYPE
            elif kind == "reg":
                payload = m[4]
                ti.size = len(payload)
                ti.uid, ti.gid = m[5], m[6]
            elif kind == "sym":
                ti.type, ti.linkname = tarfile.SYMTYPE, m[4]
            elif kind == "lnk":
                ti.type, ti.linkname = tarfile.LNKTYPE, prefix + m[4]
            else:
                ti.type = tarfile.CHRTYPE if kind == "chr" else tarfile.BLKTYPE
                ti.devmajor, ti.devminor = m[4]
            t.addfile(ti, io.BytesIO(payload) if payload is not None else None)
    return gzip.compress(buf.getvalue(), mtime=0)


def make(directory, filename, info, members=(), dot_slash=True):
    path = os.path.join(directory, filename)
    with open(path, "wb") as out:
        out.write(tar_bytes(info, members, dot_slash))
    return path
