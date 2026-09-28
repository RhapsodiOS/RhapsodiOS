"""Compose the install media's root: every apk, then the live overlay.

The apks go in the order the installer installs them, files first so the
etc, var and tmp links exist, then the rest by package name.  The cdis apk
brings the installer: /System/Installation/CDIS and its tools, the
installer script parked inert as /private/etc/rc.cdrom.hidden, and
/private/var/tmp/mnta, where it mounts the target.  The live overlay adds
only:

    /private/etc/rc.cdrom        rc.cdrom.hidden, made live; rc and rc.boot
                                 run it when /System/Installation is there
    .../System.config/Instance0.table
                                 CDIS's i386 template for hd1, the disk
                                 the media is in the QEMU harness
    /System/Installation/Packages/*.apk  every apk the root was made from
    /System/Installation/esp.img.gz      the ESP the installer writes

With preinstalled set there is no overlay.  Instead the installed-system
templates are rendered for hd0, /private/Devices is linked to Drivers/i386
as CDIS's installer links it on its target, and root gets the test
password, so the image boots as an installed disk.  /System/Installation is there too, from
the cdis apk, but without /private/etc/rc.cdrom rc starts the system.
"""
import gzip
import os

from ufs_extract import Node
from instmedia import rootfs

INSTALLATION = "/System/Installation"
CDIS = INSTALLATION + "/CDIS"
TEMPLATES = CDIS + "/templates"
# The media are i386; CDIS carries an Instance0 template per architecture.
ARCH = "i386"
INSTANCE0_TEMPLATE = "Instance0-%s.table" % ARCH
SYSTEM_TABLE = "/private/Drivers/%s/System.config/Instance0.table" % ARCH
# files links /usr/Devices to ../private/Devices; the installer links
# /private/Devices on to the architecture's drivers (rc.cdrom).
DEVICES = "/private/Devices"
FSTAB = "/private/etc/fstab"
HOSTCONFIG = "/private/etc/hostconfig"
MASTER_PASSWD = "/private/etc/master.passwd"
RC_CDROM = "/private/etc/rc.cdrom"
RC_CDROM_INERT = RC_CDROM + ".hidden"
MEDIA_DISK = "hd1"
INSTALLED_DISK = "hd0"


class ComposeError(Exception):
    pass


def render(template, disk):
    """A template with its device name filled in."""
    return template.replace(b"@DISK@", disk.encode("ascii"))


def set_root_password(passwd, crypted):
    """master.passwd's text with root's password field replaced."""
    lines = passwd.split(b"\n")
    for i, line in enumerate(lines):
        fields = line.split(b":")
        if fields[0] == b"root" and len(fields) > 1:
            fields[1] = crypted.encode("ascii")
            lines[i] = b":".join(fields)
            return b"\n".join(lines)
    raise ComposeError("master.passwd has no root entry")


def install_order(apks):
    if "files" not in apks:
        raise ComposeError("no files apk: it makes the root's links and "
                           "/dev")
    return [apks["files"]] + [apks[n] for n in sorted(apks) if n != "files"]


def compose(apks, esp, preinstalled=False, password_hash=None):
    """(nodes, conflicts) for apks, apkrepo.index()'s result.

    esp is the ESP image hdimage writes, stored gzip'd for the installer.
    """
    order = install_order(apks)
    tree = rootfs.Tree()
    for apk in order:
        rootfs.add_apk(tree, apk.path, apk.name)
    now = tree.newest_mtime()
    tree.put(tree.get("/")._replace(mtime=now))

    def template(name):
        return tree.data(TEMPLATES + "/" + name)

    def put_file(path, data, mode=0o644):
        tree.put(Node(path, "reg", mode, 0, 0, now, data))

    if preinstalled:
        if password_hash is None:
            raise ComposeError("a pre-installed image needs a password hash")
        put_file(FSTAB, render(template("fstab"), INSTALLED_DISK))
        put_file(SYSTEM_TABLE,
                 render(template(INSTANCE0_TEMPLATE), INSTALLED_DISK))
        put_file(HOSTCONFIG, template("hostconfig"))
        tree.put(Node(DEVICES, "lnk", 0o755, 0, 0, now, "Drivers/" + ARCH))
        put_file(MASTER_PASSWD,
                 set_root_password(tree.data(MASTER_PASSWD), password_hash),
                 0o600)
    else:
        put_file(RC_CDROM, tree.data(RC_CDROM_INERT), 0o755)
        put_file(SYSTEM_TABLE,
                 render(template(INSTANCE0_TEMPLATE), MEDIA_DISK))
        tree.put(Node(INSTALLATION + "/Packages", "dir", 0o755, 0, 0, now,
                      None))
        for apk in order:
            with open(apk.path, "rb") as f:
                put_file("%s/Packages/%s" % (INSTALLATION,
                                             os.path.basename(apk.path)),
                         f.read())
        put_file(INSTALLATION + "/esp.img.gz",
                 gzip.compress(esp, compresslevel=9, mtime=0))
    return tree.nodes(), list(tree.conflicts)
