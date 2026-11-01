"""DragonFly BSD reference guest for HAMMER: run a script against a volume.

Usage: dfly_guest.py run ISO VOLUME SCRIPT OUTDIR [NAME=FILE...]

Boots the DragonFly live ISO single-user with its console on a TCP serial
socket, attaches VOLUME (written in place) as the first IDE disk and an
empty FAT32 transfer disk as the second, types SCRIPT (as RUN.SH) and any
FILEs into /tmp/in over the serial shell (MD5-checked), runs it with output
to OUT.TXT on the transfer disk, and quits through QMP after checking the
guest's name.  The guest sees the disks as /dev/ad0 (VOLUME) and /dev/ad1
(transfer); RUN.SH runs in the transfer disk's /tmp/x, which also takes any
result files, with an empty /tmp/h for a mount point.

DFLY_SERIAL_PORT / DFLY_QMP_PORT pick the ports (default 4761/4762),
DFLY_ACCEL the accelerator (default whpx).
"""
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
import uuid

import fat32

QEMU = r'C:\Program Files\qemu\qemu-system-x86_64.exe'
XFER_SECTORS = 131072           # 64 MiB, comfortably FAT32
RC_RE = re.compile(rb'__DFLY_RC=(\d+)__')


def qemu_args(iso, volume, xfer, name, serial_port, qmp_port, accel='whpx'):
    return [
        QEMU, '-name', name, '-M', 'pc', '-accel', accel, '-m', '1024',
        '-nodefaults', '-vga', 'std', '-display', 'none',
        '-drive', 'file=%s,format=raw,if=ide,index=0,media=disk' % volume,
        '-drive', 'file=%s,format=raw,if=ide,index=1,media=disk' % xfer,
        '-drive', 'file=%s,format=raw,if=ide,index=2,media=cdrom,readonly=on' % iso,
        '-boot', 'd',
        '-serial', 'tcp:127.0.0.1:%d,server=on,wait=off' % serial_port,
        '-qmp', 'tcp:127.0.0.1:%d,server=on,wait=off' % qmp_port,
    ]


def parse_rc(text):
    if isinstance(text, str):
        text = text.encode('latin-1')
    m = RC_RE.search(text)
    return None if m is None else int(m.group(1))


def make_transfer_disk(path, files):
    Path(path).write_bytes(fat32.build(XFER_SECTORS, files, label='DFLYXFER'))


def _check_free(port):
    with socket.socket() as probe:
        try:
            probe.bind(('127.0.0.1', port))
        except OSError as error:
            raise OSError('port already in use: %d' % port) from error


class Guest(object):
    def __init__(self, args, name, serial_port, qmp_port, outdir):
        self.name = name
        self.log = open(Path(outdir)/'serial.log', 'wb')
        self.buf = b''
        self.proc = subprocess.Popen(
            args, creationflags=0x00000008 | 0x00000200,
            stdin=subprocess.DEVNULL, stdout=open(Path(outdir)/'qemu.out', 'wb'),
            stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 30
        while True:
            try:
                self.qmp = socket.create_connection(('127.0.0.1', qmp_port), timeout=10)
                self.serial = socket.create_connection(('127.0.0.1', serial_port), timeout=1)
                break
            except OSError:
                if time.monotonic() > deadline or self.proc.poll() is not None:
                    raise OSError('QEMU did not come up; see qemu.out')
                time.sleep(0.5)
        self.qf = self.qmp.makefile('rw')
        self.qf.readline()
        self.qmp_cmd('qmp_capabilities')
        reply = self.qmp_cmd('query-name')
        if reply.get('return', {}).get('name') != name:
            raise OSError('QMP connection does not belong to this guest')

    def qmp_cmd(self, execute, **arguments):
        msg = {'execute': execute}
        if arguments:
            msg['arguments'] = arguments
        self.qf.write(json.dumps(msg) + '\n')
        self.qf.flush()
        while True:
            line = self.qf.readline()
            if not line:
                return {}
            reply = json.loads(line)
            if 'event' not in reply:
                return reply

    def pump(self, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                data = self.serial.recv(65536)
            except socket.timeout:
                continue
            if data:
                self.buf += data
                self.log.write(data)
                self.log.flush()

    def wait_for(self, pattern, seconds, start=0):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if pattern in self.buf[start:]:
                return True
            self.pump(1)
        return pattern in self.buf[start:]

    def send(self, text):
        self.serial.sendall(text.encode('latin-1'))
        time.sleep(0.2)

    def boot_single_user(self):
        steps = ((b'Booting in', 300, '\x1b'), (b'OK ', 30, 'console=comconsole\r'),
                 (b'OK ', 30, 'menu\r'), (b'single user', 30, 's'),
                 (b'RETURN for /bin/sh', 900, '\r'), (b'# ', 30, None))
        for pattern, seconds, reply in steps:
            mark = len(self.buf)
            if not self.wait_for(pattern, seconds, 0 if pattern == b'Booting in' else mark - 64):
                raise OSError('DragonFly boot stalled waiting for %r' % pattern)
            if reply is not None:
                self.send(reply)

    def put_file(self, path, data):
        """Type a text file into the guest and check its MD5 there."""
        text = data.decode('latin-1')
        if '\r' in text or any(len(line) > 200 for line in text.split('\n')):
            raise ValueError('%s: serial transfer needs LF text with short lines' % path)
        for attempt in range(3):
            # cat reads the tty in cooked mode; a here-document would go
            # through sh's line editor, which eats TABs as completion.
            self.send('cat > %s\r' % path)
            self.pump(1)
            for line in text.rstrip('\n').split('\n'):
                self.serial.sendall((line + '\r').encode('latin-1'))
                time.sleep(0.03)
                self.pump(0.01)
            self.send('\x04')
            mark = len(self.buf)
            self.send('md5 -q %s\r' % path)
            self.wait_for(b'# ', 30, mark + 8)
            if hashlib.md5(text.rstrip('\n').encode('latin-1') + b'\n').hexdigest().encode() \
                    in self.buf[mark:]:
                return
        raise OSError('serial transfer of %s kept failing' % path)

    def run(self, command, seconds):
        mark = len(self.buf)
        self.send('%s; echo __DFLY_RC=$?__\r' % command)
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            rc = parse_rc(self.buf[mark:].split(b'\n', 1)[-1])
            if rc is not None:
                return rc
            self.pump(1)
        raise OSError('command timed out: %s' % command)

    def quit(self):
        try:
            reply = self.qmp_cmd('query-name')
            if reply.get('return', {}).get('name') == self.name:
                self.qmp_cmd('quit')
        finally:
            self.log.close()
            try:
                self.proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                pass


SETUP = ('mount_tmpfs tmpfs /tmp && mkdir -p /tmp/x /tmp/h /tmp/in && '
         'mount_msdos /dev/ad1 /tmp/x')


def run_script(iso, volume, script, outdir, files=None):
    """Run SCRIPT on DragonFly against VOLUME; return (status, OUT.TXT text)."""
    outdir = Path(outdir)
    outdir.mkdir()                      # refuses an existing directory
    serial_port = int(os.environ.get('DFLY_SERIAL_PORT', '4761'))
    qmp_port = int(os.environ.get('DFLY_QMP_PORT', '4762'))
    _check_free(serial_port)
    _check_free(qmp_port)
    inputs = {'RUN.SH': script.encode('latin-1') if isinstance(script, str) else script}
    inputs.update(files or {})
    xfer = outdir/'xfer.img'
    # DragonFly misreads files pre-written on fat32.py's one-sector clusters
    # (files it writes itself read back fine), so the transfer disk carries
    # results only; inputs go over the serial shell.
    make_transfer_disk(xfer, {})
    name = 'dfly-' + uuid.uuid4().hex[:12]
    args = qemu_args(iso, volume, xfer, name, serial_port, qmp_port,
                     os.environ.get('DFLY_ACCEL', 'whpx'))
    guest = Guest(args, name, serial_port, qmp_port, outdir)
    try:
        guest.boot_single_user()
        if guest.run(SETUP, 120) != 0:
            raise OSError('could not mount the transfer disk')
        for name, data in inputs.items():
            guest.put_file('/tmp/in/' + name, data)
        status = guest.run('cd /tmp/x && sh /tmp/in/RUN.SH > OUT.TXT 2>&1', 4 * 3600)
        guest.run('cd / && sync && umount /tmp/x', 120)
    finally:
        guest.quit()
    text = fat32.read_file(xfer.read_bytes(), 'OUT.TXT').decode('latin-1')
    (outdir/'out.txt').write_text(text)
    return status, text


def main(argv):
    if len(argv) >= 6 and argv[1] == 'run':
        files = {}
        for spec in argv[6:]:
            name, _, path = spec.partition('=')
            if not path:
                raise ValueError('extra files are NAME=PATH with an 8.3 NAME')
            files[name] = Path(path).read_bytes()
        status, text = run_script(argv[2], argv[3], Path(argv[4]).read_text(), argv[5], files)
        sys.stdout.write(text)
        print('DFLY status %d' % status)
        return status
    raise ValueError(__doc__)


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv))
    except (OSError, ValueError, fat32.FatError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
