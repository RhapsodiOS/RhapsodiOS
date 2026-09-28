"""Index a flat directory of rbuild apks.

An apk is a gzip'd tar whose .PKGINFO holds "key = value" lines.  index()
picks one build per pkgname: the i386 one when there is one, else the
universal one, and refuses a package built only for ppc.  -hdrs and -obj
companions are left out, because they repeat files their base package
ships and apk refuses to install a path two packages both claim.
"""
import collections
import io
import os
import tarfile

Apk = collections.namedtuple("Apk", "path name version cpu info")

# Members apk reads as metadata.  Everything else, /.hidden included, is
# data (see src/apk-tools-1/PORTING.md).
CONTROL = (".PKGINFO", ".pre-install", ".post-install", ".pre-deinstall",
           ".post-deinstall")
COMPANION_SUFFIXES = ("-hdrs", "-obj")
CPUS = ("i386", "universal", "ppc")


class RepoError(Exception):
    pass


def member_name(name):
    """A tar member name as a root-relative path: no "./" prefix and no
    leading or trailing slash; "" for the archive's own "." entry."""
    while name.startswith("./"):
        name = name[2:]
    name = name.strip("/")
    return "" if name == "." else name


def is_control(name):
    return name in CONTROL or name.startswith(".SIGN.")


def open_apk(source):
    """A tarfile over source, an apk's path or its bytes."""
    if isinstance(source, bytes):
        return tarfile.open(fileobj=io.BytesIO(source), mode="r:gz")
    return tarfile.open(source, "r:gz")


def parse_pkginfo(text):
    info = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        info[key.strip()] = value.strip()
    return info


def read_pkginfo(source):
    """The .PKGINFO of source (a path or the apk's bytes) as a dict."""
    with open_apk(source) as tar:
        for m in tar:
            if member_name(m.name) == ".PKGINFO" and m.isfile():
                return parse_pkginfo(
                    tar.extractfile(m).read().decode("latin-1"))
    raise RepoError("%s has no .PKGINFO"
                    % (source if isinstance(source, str) else "apk"))


def cpu_of(arch):
    """"i386-apple-rhapsody" -> "i386"; also accepts the bare CPU."""
    cpu = arch.split("-", 1)[0]
    if cpu not in CPUS:
        raise RepoError("unknown arch %r" % arch)
    return cpu


def index(directory):
    """{pkgname: Apk} for the apks in directory, one build per package."""
    builds = collections.defaultdict(dict)
    for fn in sorted(os.listdir(directory)):
        if not fn.endswith(".apk"):
            continue
        path = os.path.join(directory, fn)
        info = read_pkginfo(path)
        name = info.get("pkgname")
        if not name:
            raise RepoError("%s: .PKGINFO has no pkgname" % fn)
        if name.endswith(COMPANION_SUFFIXES):
            continue
        cpu = cpu_of(info.get("arch", ""))
        if cpu in builds[name]:
            raise RepoError("two %s builds of %s: %s and %s"
                            % (cpu, name,
                               os.path.basename(builds[name][cpu].path), fn))
        builds[name][cpu] = Apk(path, name, info.get("pkgver", ""), cpu, info)
    chosen = {}
    for name in sorted(builds):
        for cpu in ("i386", "universal"):
            if cpu in builds[name]:
                chosen[name] = builds[name][cpu]
                break
        else:
            raise RepoError("%s is built only for ppc" % name)
    return chosen
