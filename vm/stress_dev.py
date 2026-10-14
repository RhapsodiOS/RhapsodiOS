"""Dev guest for the system stress suite: one long-lived v2 snapshot guest.

    python vm/stress_dev.py up           boot it, wait for a real login
    python vm/stress_dev.py sync         tar src/Commands/stress to /tmp/stress-src
    python vm/stress_dev.py sh "<cmd>"   run a /bin/sh command, exit with its status
    python vm/stress_dev.py down         QMP quit, after query-name answers

STRESS_DEV_PORTS="ssh,qmp,gdb" overrides the default 2548,4548,1248.  The
guest is a snapshot: a restart loses /tmp/stress-src, so sync again.
"""
import io
import json
import os
import sys
import tarfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SRC = os.path.join(REPO, "src", "Commands", "stress")
DEFAULT_PORTS = "2548,4548,1248"
LOGIN_TRIES, LOGIN_GAP = 15, 20       # up to ~5 minutes after the banner
GUEST_SRC = "/tmp/stress-src"
GUEST_NAME = "RhapsodiOS stress-dev"


def load(ports):
    """Import ffsbench configured for these ports; its settings are read at
    import time."""
    os.environ["FFSBENCH_PORTS"] = ports
    os.environ.setdefault("RHAP_VM_ASSETS", r"D:\RhapsodiOS\vm")
    os.environ.setdefault("FFSBENCH_ROOT", os.path.join(
        os.environ["RHAP_VM_ASSETS"], "work", "rhap-i386-bootstrapped-v2.img"))
    sys.path.insert(0, HERE)
    import ffsbench
    return ffsbench


def state_path():
    assets = os.environ.get("RHAP_VM_ASSETS", r"D:\RhapsodiOS\vm")
    return os.path.join(assets, "work", "stress-dev.json")


def saved_ports():
    try:
        with open(state_path()) as f:
            return json.load(f)["ports"]
    except (OSError, ValueError, KeyError):
        return os.environ.get("STRESS_DEV_PORTS", DEFAULT_PORTS)


def up():
    ports = os.environ.get("STRESS_DEV_PORTS", DEFAULT_PORTS)
    fb = load(ports)
    outdir = os.path.join(fb.ASSETS, "work", "stress-dev")
    g = fb.Guest(outdir, fb._fresh_hd1(outdir), fb._workload(), name=GUEST_NAME)
    with open(state_path(), "w") as f:
        json.dump({"ports": ports}, f)
    if not g.wait_sshd():
        raise SystemExit("sshd never answered")
    ssh = fb.Ssh(fb._conf())
    for _ in range(LOGIN_TRIES):
        rc, out = ssh.run("true")
        if rc == 0:
            print("stress-dev up on ports %s" % ports)
            return 0
        time.sleep(LOGIN_GAP)
    raise SystemExit("no login after the banner")


def tar_source():
    """USTAR tar of src/Commands/stress, file bytes untouched (LF)."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
        for root, dirs, files in os.walk(SRC):
            dirs.sort()
            for name in sorted(files):
                path = os.path.join(root, name)
                arc = "stress-src/" + os.path.relpath(path, SRC).replace(os.sep, "/")
                info = t.gettarinfo(path, arc)
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                info.mode = 0o755 if info.mode & 0o100 else 0o644
                with open(path, "rb") as f:
                    t.addfile(info, f)
    return buf.getvalue()


def sync():
    fb = load(saved_ports())
    ssh = fb.Ssh(fb._conf())
    local = os.path.join(fb.ASSETS, "work", "stress-dev", "stress-src.tar")
    with open(local, "wb") as f:
        f.write(tar_source())
    ssh.push(local, "/tmp/stress-src.tar")
    rc, out = ssh.run("rm -rf %s /tmp/stress-x && mkdir /tmp/stress-x && "
                      "cd /tmp/stress-x && tar xf /tmp/stress-src.tar && "
                      "mv stress-src %s" % (GUEST_SRC, GUEST_SRC))
    if rc != 0:
        raise SystemExit("sync failed: %s" % out)
    return 0


def sh(command):
    fb = load(saved_ports())
    rc, out = fb.Ssh(fb._conf()).run(command)
    print(out)
    return rc


def down():
    ports = saved_ports()
    fb = load(ports)
    qmp = fb.Qmp(int(ports.split(",")[1]))
    if qmp.execute("query-name").get("name") != GUEST_NAME:
        raise SystemExit("QMP on %s is not our guest" % ports.split(",")[1])
    qmp.quit()
    try:
        os.remove(state_path())
    except OSError:
        pass
    print("stress-dev down")
    return 0


def main(argv):
    if argv[1:2] == ["up"]:
        return up()
    if argv[1:2] == ["sync"]:
        return sync()
    if argv[1:2] == ["sh"] and len(argv) == 3:
        return sh(argv[2])
    if argv[1:2] == ["down"]:
        return down()
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
