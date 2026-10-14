"""Dev guest for the Open POSIX test suite: one long-lived v2 snapshot guest.

    python vm/posix_dev.py up [--kernel PATH]   boot it, wait for a real login;
                                         with PATH, install it as /mach_kernel and reboot
    python vm/posix_dev.py sync         tar src/Commands/posixtestsuite-1 to
                                         /tmp/posix-src, make install it
    python vm/posix_dev.py sh "<cmd>"   run a /bin/sh command, exit with its status
    python vm/posix_dev.py run [ARGS]   run the suite detached, wait, copy Report/
                                         to vm/work/posix/<time>/, exit with its status
    python vm/posix_dev.py baseline     copy the last run's Report/baseline.new
                                         over src/Commands/posixtestsuite-1/baseline
    python vm/posix_dev.py down         QMP quit, after query-name answers

POSIX_DEV_PORTS="ssh,qmp,gdb" overrides the default 2549,4549,1249.  The
guest is a snapshot: a restart loses /tmp/posix-src and the install, so sync
again.
"""
import gzip
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SRC = os.path.join(REPO, "src", "Commands", "posixtestsuite-1")
DEFAULT_PORTS = "2549,4549,1249"
LOGIN_TRIES, LOGIN_GAP = 15, 20       # up to ~5 minutes after the banner
GUEST_SRC = "/tmp/posix-src"
GUEST_RUN = "/tmp/posix-run"
GUEST_NAME = "RhapsodiOS posix-dev"
POLL, RUN_HOURS = 300, 8


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


def assets():
    return os.environ.get("RHAP_VM_ASSETS", r"D:\RhapsodiOS\vm")


def state_path():
    return os.path.join(assets(), "work", "posix-dev.json")


def load_state():
    try:
        with open(state_path()) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(**kw):
    state = load_state()
    state.update(kw)
    with open(state_path(), "w") as f:
        json.dump(state, f)


def saved_ports():
    return load_state().get("ports") or os.environ.get("POSIX_DEV_PORTS", DEFAULT_PORTS)


def login(ssh):
    for _ in range(LOGIN_TRIES):
        rc, out = ssh.run("true")
        if rc == 0:
            return
        time.sleep(LOGIN_GAP)
    raise SystemExit("no login after the banner")


def ssh_now():
    fb = load(saved_ports())
    return fb.Ssh(fb._conf())


def up(kernel=None):
    ports = os.environ.get("POSIX_DEV_PORTS", DEFAULT_PORTS)
    fb = load(ports)
    outdir = os.path.join(fb.ASSETS, "work", "posix-dev")
    g = fb.Guest(outdir, fb._fresh_hd1(outdir), fb._workload(), name=GUEST_NAME)
    save_state(ports=ports)
    if not g.wait_sshd():
        raise SystemExit("sshd never answered")
    ssh = fb.Ssh(fb._conf())
    login(ssh)
    if kernel:
        fb.boot_test_kernel(g, ssh, kernel, "")
        login(ssh)
    print("posix-dev up on ports %s" % ports)
    return 0


def tar_source():
    """USTAR tar of src/Commands/posixtestsuite-1, file bytes untouched."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
        for root, dirs, files in os.walk(SRC):
            dirs[:] = sorted(d for d in dirs if d != "Report")
            for name in sorted(files):
                path = os.path.join(root, name)
                arc = "posix-src/" + os.path.relpath(path, SRC).replace(os.sep, "/")
                info = t.gettarinfo(path, arc)
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                info.mode = 0o644
                with open(path, "rb") as f:
                    t.addfile(info, f)
    return buf.getvalue()


def hex_to_bytes(text):
    """Bytes from `od -An -v -tx1` output."""
    return bytes.fromhex(" ".join(text.split()))


def sync():
    ssh = ssh_now()
    local = os.path.join(assets(), "work", "posix-dev", "posix-src.tar")
    os.makedirs(os.path.dirname(local), exist_ok=True)
    with open(local, "wb") as f:
        f.write(tar_source())
    ssh.push(local, "/tmp/posix-src.tar")
    rc, out = ssh.run("rm -rf %s /tmp/posix-x && mkdir /tmp/posix-x && "
                      "cd /tmp/posix-x && tar xf /tmp/posix-src.tar && "
                      "mv posix-src %s && cd %s && make && make install"
                      % (GUEST_SRC, GUEST_SRC, GUEST_SRC))
    if rc != 0:
        raise SystemExit("sync failed: %s" % out)
    return 0


def sh(command):
    rc, out = ssh_now().run(command)
    print(out)
    return rc


def shquote(s):
    return "'" + s.replace("'", "'\\''") + "'"


def run(args):
    ssh = ssh_now()
    inner = "/usr/local/posixtestsuite/run %s >run.out 2>&1; echo $? >status" % (
        " ".join(shquote(a) for a in args))
    rc, out = ssh.run("mkdir -p %s && cd %s && rm -f status && "
                      "nohup sh -c %s </dev/null >/dev/null 2>&1 &"
                      % (GUEST_RUN, GUEST_RUN, shquote(inner)))
    if rc != 0:
        raise SystemExit("could not start the run: %s" % out)
    deadline = time.time() + RUN_HOURS * 3600
    while True:
        time.sleep(POLL)
        rc, _ = ssh.run("test -f %s/status" % GUEST_RUN)
        if rc == 0:
            break
        if time.time() > deadline:
            raise SystemExit("run not finished after %d hours" % RUN_HOURS)
    rc, out = ssh.run("cd %s && tar cf - Report run.out status | gzip -c | od -An -v -tx1"
                      % GUEST_RUN)
    if rc != 0:
        raise SystemExit("could not fetch the report: %s" % out[-500:])
    dest = os.path.join(assets(), "work", "posix", time.strftime("%Y%m%d-%H%M%S"))
    os.makedirs(dest)
    with tarfile.open(fileobj=io.BytesIO(gzip.decompress(hex_to_bytes(out)))) as t:
        t.extractall(dest)
    save_state(last_run=dest)
    with open(os.path.join(dest, "Report", "summary")) as f:
        print(f.read())
    print("report in %s" % dest)
    with open(os.path.join(dest, "status")) as f:
        return int(f.read().strip())


def baseline():
    last = load_state().get("last_run")
    if not last:
        raise SystemExit("no run recorded; run first")
    shutil.copyfile(os.path.join(last, "Report", "baseline.new"),
                    os.path.join(SRC, "baseline"))
    subprocess.call(["git", "-C", REPO, "diff", "--stat", "--",
                     os.path.join(SRC, "baseline")])
    return 0


def down():
    ports = saved_ports()
    fb = load(ports)
    qmp = fb.Qmp(int(ports.split(",")[1]))
    if qmp.execute("query-name").get("name") != GUEST_NAME:
        raise SystemExit("QMP on %s is not our guest" % ports.split(",")[1])
    qmp.quit()
    save_state(ports=None)
    print("posix-dev down")
    return 0


def main(argv):
    if argv[1:2] == ["up"] and len(argv) == 2:
        return up()
    if argv[1:2] == ["up"] and len(argv) == 4 and argv[2] == "--kernel":
        return up(argv[3])
    if argv[1:2] == ["sync"] and len(argv) == 2:
        return sync()
    if argv[1:2] == ["sh"] and len(argv) == 3:
        return sh(argv[2])
    if argv[1:2] == ["run"]:
        return run(argv[2:])
    if argv[1:2] == ["baseline"] and len(argv) == 2:
        return baseline()
    if argv[1:2] == ["down"] and len(argv) == 2:
        return down()
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
