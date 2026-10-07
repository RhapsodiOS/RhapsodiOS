"""Prepare disposable labelled ext2 disks and drive i386 native cases.

Usage: ext2_guest.py wrap VOLUME OUT
       ext2_guest.py capacity 512|1024 OUT
       ext2_guest.py tiny OUT
       ext2_guest.py run CASE OUTDIR IMAGE TOOLS_DIR
RHAP_TEST_IMAGE selects the root source; each run copies it before booting.
"""
import importlib.util
import os
from pathlib import Path
import shutil
import socket
import struct
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
RUN_COMMAND = 'cd /mnt; sh run-case.sh'
RESULT_SCRIPT = b'sh run-native.sh readonly /dev/hd1a /mnt/e >out.txt 2>&1\necho $? >status.txt\nsync\n'
TEMPLATE = str(Path(os.environ.get('RHAP_VM_ASSETS', HERE))/'install'/'rhapsody_dr2_x86_InstallationFloppy.img')
import ufs_build
import ufs_extract
import rhap_image


def wrap_volume(volume: bytes) -> bytes:
    if not volume or len(volume) % 512 or len(volume)//512 > 0x7fffffff:
        raise ValueError('volume must have a bounded whole number of 512-byte sectors')
    with open(TEMPLATE,'rb') as stream:
        prefix = stream.read(32767 * 512)
    copies = [off for off in range(0,min(len(prefix),65536),512) if prefix[off:off+4] == b'dlV3']
    if not copies:
        raise ValueError('no NeXT label')
    part = None
    for off in copies:
        if off+560 > len(prefix): raise ValueError('truncated NeXT label')
        sector = struct.unpack_from('>i',prefix,off+92)[0]
        front = struct.unpack_from('>h',prefix,off+112)[0]
        base = struct.unpack_from('>i',prefix,off+190)[0]
        start = (front+base)*sector
        if sector not in (512,1024,2048,4096) or front < 0 or base != 0 or start % 512 or start//512 > 32767:
            raise ValueError('unsupported label geometry')
        if start < off+560 or start > len(prefix) or (part is not None and part != start):
            raise ValueError('label outside front area or inconsistent copies')
        part = start
    image = bytearray(prefix[:part])
    for off in copies:
        struct.pack_into('>i',image,off+92,512)
        struct.pack_into('>h',image,off+112,part//512)
    image += volume
    ufs_build.patch_labels(image,part,len(volume)//512)
    # The legacy IDE driver exposes whole 16-head/63-sector cylinders.
    # Pad outside partition-a so its final sector remains addressable.
    cylinder = 512*16*63
    image += bytes((-len(image)) % cylinder)
    return bytes(image)


def capacity_fixture(sector):
    """NeXT partitions for native capacity checks, with no filesystem writes."""
    if sector not in (512,1024): raise ValueError('unsupported capacity sector')
    raw = bytearray(wrap_volume(bytes(16*1024*1024)))
    for off in range(0,65536,512):
        if raw[off:off+4] != b'dlV3': continue
        front = struct.unpack_from('>h',raw,off+112)[0]*512
        struct.pack_into('>i',raw,off+92,sector)
        struct.pack_into('>h',raw,off+112,front//sector)
        raw[off+190:off+190+8*46] = bytes(8*46)
        for part,count in enumerate((16*1024*1024//sector,len(raw)//sector,len(raw)//sector+1)):
            struct.pack_into('>ii',raw,off+190+part*46,0,count)
        struct.pack_into('>H',raw,off+558,ufs_build.label_checksum(raw[off:off+560]))
    return bytes(raw)


def wrap_volumes(volumes):
    """Pack up to seven independent disposable volumes; slot h is live."""
    if not 1 <= len(volumes) <= 7:
        raise ValueError('suite requires one to seven logical partitions')
    if any(not volume or len(volume) % 512 for volume in volumes):
        raise ValueError('suite volumes must be sector aligned')
    raw = bytearray(wrap_volume(b''.join(volumes)))
    # wrap_volume validated the first template label and normalized its sector
    # size to 512. Its front boundary separates labels from supplied payloads.
    label = next(off for off in range(0,min(len(raw),65536),512)
                 if raw[off:off+4] == b'dlV3')
    front = struct.unpack_from('>h',raw,label+112)[0]*512
    for off in range(0,min(front,65536),512):
        if raw[off:off+4] != b'dlV3': continue
        prototype = raw[off+190:off+236]
        raw[off+190:off+558] = bytes(8*46)
        base = 0
        for part,volume in enumerate(volumes):
            start = off+190+part*46
            raw[start:start+46] = prototype
            struct.pack_into('>ii',raw,start,base,len(volume)//512)
            base += len(volume)//512
        struct.pack_into('>H',raw,off+558,ufs_build.label_checksum(raw[off:off+560]))
    return bytes(raw)


def tiny_fixture():
    """Four zero-filled partitions bounding the initial superblock read."""
    raw = bytearray(wrap_volume(bytes(2048)))
    for off in range(0,min(len(raw),65536),512):
        if raw[off:off+4] != b'dlV3': continue
        raw[off+190:off+558] = bytes(8*46)
        for part in range(4):
            struct.pack_into('>ii',raw,off+190+part*46,0,part+1)
        struct.pack_into('>H',raw,off+558,ufs_build.label_checksum(raw[off:off+560]))
    return bytes(raw)


def _new_target(path):
    path = Path(path).resolve()
    if path.name.lower() in ('golden.img','rhapsody.vmdk'):
        raise ValueError('protected master path')
    if path.exists(): raise FileExistsError(str(path))
    return path


def wrap_file(volume,output):
    output = _new_target(output)
    wrapped = wrap_volume(Path(volume).read_bytes())
    with output.open('xb') as stream: stream.write(wrapped)


def prepare_run(outdir,image,root):
    outdir = _new_target(outdir)
    image,root = Path(image).resolve(),Path(root).resolve()
    if not image.is_file() or not root.is_file(): raise ValueError('missing source disk')
    outdir.mkdir()
    private_root,private_data = outdir/'root.img',outdir/'ext2.img'
    shutil.copyfile(root,private_root)
    shutil.copyfile(image,private_data)
    return str(private_root),str(private_data)


def verify_result(case: str,status: int,stdout: str) -> list[str]:
    problems = []
    if status != 0: problems.append('case exited with status %s' % status)
    if 'EXT2_OK '+case not in stdout.splitlines(): problems.append('missing exact case marker')
    return problems


def check_qmp_port(port):
    with socket.socket() as probe:
        try:
            probe.bind(('127.0.0.1',port))
        except OSError as error:
            raise OSError('QMP port is already in use: %s' % port) from error


def check_guest(guest,name):
    if guest.proc.poll() is not None:
        raise OSError('private QEMU process exited before boot')
    reply = guest.cmd('query-name')
    if not reply or reply.get('return',{}).get('name') != name:
        raise OSError('QMP connection does not belong to private guest')


def start_guest(guest_class,*args,**kwargs):
    # Keep the instance if QMP setup fails after Popen succeeded.
    guest = guest_class.__new__(guest_class)
    try:
        guest_class.__init__(guest,*args,**kwargs)
    except BaseException:
        if getattr(guest,'proc',None) is not None: guest.close()
        raise
    return guest


def _read_result(path):
    with rhap_image.Image(str(path)) as disk:
        def read(name):
            ino = disk.resolve('/'+name)
            return None if ino is None else disk.read_file(disk.inode(ino)).decode('utf-8','replace')
        return read('status.txt'),read('out.txt')


def run(case,outdir,image,tools_dir):
    if case not in ('recovery-write','dirty-refusal','ioerror-suite','ioerror-transition-suite','ioerror-allocation-suite','ioerror-read-suite','task5-covering-suite','persistence-write-suite','ioerror-allocation','ioerror-truncate','ioerror-admission','ioerror-metadata','ioerror-first-push','ioerror-clean','ioerror-close','ioerror-rewrite','ioerror-short-inode','remount','busy','persistence-write','persistence-read','mutation','limits','mmap','mmap-size','mmap-fsync','mmap-limits','permissions','special','write-red-suite','mmap-diagnostic-suite','append-control-suite','rejected-inode-suite','fresh-mmap-suite','fresh-control-suite','write-suite','write-fsync-suite','write-core-suite','readonly','mapping','directory','mmap-readonly','malformed','read-suite','malformed-suite','truncated-suite','tiny','capacity512','capacity1024'): raise ValueError('unsupported case')
    port = int(os.environ.get('RHAP_EXT2_QMP_PORT','5303'))
    check_qmp_port(port)
    tools_dir = Path(tools_dir)
    names = ('partition_info',) if case.startswith('capacity') else ('mount_ext2fs','ext2_io')
    binaries = {name:(tools_dir/name).read_bytes() for name in names}
    result_script = RESULT_SCRIPT
    if case in ('mutation','limits','mmap','mmap-size','mmap-fsync','mmap-limits','permissions','special','mapping','directory','mmap-readonly','malformed'):
        kind = os.environ.get('RHAP_EXT2_MALFORMED','directory')
        if kind not in ('directory','indirect'): raise ValueError('unsupported malformed kind')
        extra = ' '+kind if case == 'malformed' else ''
        result_script = ('sh run-native.sh %s /dev/hd1a /mnt/e%s >out.txt 2>&1\necho $? >status.txt\nsync\n' % (case,extra)).encode('ascii')
    if case.endswith('-suite') or case in ('recovery-write','dirty-refusal','ioerror-suite','ioerror-transition-suite','ioerror-allocation-suite','ioerror-read-suite','task5-covering-suite','persistence-write-suite','ioerror-allocation','ioerror-truncate','ioerror-admission','ioerror-metadata','ioerror-first-push','ioerror-clean','ioerror-close','ioerror-rewrite','ioerror-short-inode','remount','busy','persistence-write','persistence-read'):
        result_script = ('sh run-native.sh %s /mnt/e >out.txt 2>&1\necho $? >status.txt\nsync\n' % case).encode('ascii')
    if case == 'tiny':
        result_script = b'sh run-native.sh tiny /mnt/e >out.txt 2>&1\necho $? >status.txt\nsync\n'
    if case.startswith('capacity'):
        sector = int(case[8:])
        result_script = ('sh run-native.sh %s %d %d >out.txt 2>&1\necho $? >status.txt\nsync\n' %
                         (case,16*1024*1024//sector,Path(image).stat().st_size//512)).encode('ascii')
    root = os.environ.get('RHAP_TEST_IMAGE')
    if not root: raise ValueError('set RHAP_TEST_IMAGE to a root-image source')
    private_root,private_data = prepare_run(outdir,image,root)
    outdir = Path(outdir).resolve()
    runner = (HERE.parent/'src/ext2fs-1/tests/run-native.sh').read_bytes()
    N = ufs_extract.Node
    nodes = [N('/','dir',0o40755,0,0,0,None),N('/e','dir',0o40755,0,0,0,None),
             N('/run-case.sh','reg',0o100755,0,0,0,result_script),
             N('/run-native.sh','reg',0o100755,0,0,0,runner)]
    nodes += [N('/'+name,'reg',0o100755,0,0,0,data) for name,data in binaries.items()]
    result = outdir/'results.img'
    result.write_bytes(ufs_build.build(TEMPLATE,nodes))
    spec = importlib.util.spec_from_file_location('ext2_console',HERE/'guest-console.py')
    gc = importlib.util.module_from_spec(spec); spec.loader.exec_module(gc)
    drive = 'file=%s,format=raw,if=ide,index=%d,media=disk,snapshot=off'
    name = 'ext2fs-'+uuid.uuid4().hex
    check_qmp_port(port)
    guest = start_guest(gc.Guest,str(outdir),image=private_root,port=port,
                     extra=('-name',name,'-drive',drive%(private_data,1),'-drive',drive%(result,2)))
    try:
        time.sleep(6)
        check_guest(guest,name)
        guest.line('-s'); time.sleep(135)
        guest.line('mount -uw /'); time.sleep(5)
        guest.line('mknod /dev/hd2a b 3 16'); time.sleep(3)
        guest.line('mount /dev/hd2a /mnt'); time.sleep(5)
        guest.line(RUN_COMMAND)
        deadline = time.monotonic()+1800
        while time.monotonic()<deadline:
            time.sleep(15)
            if 'panic:' in (outdir/'serial.log').read_text(errors='replace'): break
            try:
                status,stdout = _read_result(result)
                if status is not None: break
            except (OSError,ValueError): pass
        guest.shot('end')
    finally: guest.close()
    status,stdout = _read_result(result)
    (outdir/'out.txt').write_text(stdout or '')
    (outdir/'status.txt').write_text(status or 'missing')
    problems = verify_result(case,int(status.strip()) if status and status.strip().isdigit() else -1,stdout or '')
    if case not in ('recovery-write','dirty-refusal','ioerror-suite','ioerror-transition-suite','ioerror-allocation-suite','ioerror-read-suite','task5-covering-suite','persistence-write-suite','ioerror-allocation','ioerror-truncate','ioerror-admission','ioerror-metadata','ioerror-first-push','ioerror-clean','ioerror-close','ioerror-rewrite','ioerror-short-inode','remount','busy','persistence-write','persistence-read','mutation','limits','mmap','mmap-size','mmap-fsync','mmap-limits','permissions','special','write-suite','write-fsync-suite','write-core-suite','mmap-diagnostic-suite','append-control-suite','rejected-inode-suite','fresh-mmap-suite','fresh-control-suite') and Path(image).read_bytes() != Path(private_data).read_bytes(): problems.append('readonly data image changed')
    serial = (outdir/'serial.log').read_text(errors='replace')
    if 'panic:' in serial: problems.append('kernel panic in serial log')
    for problem in problems: print(problem)
    return int(bool(problems))


def main(argv):
    if len(argv)==4 and argv[1]=='wrap': wrap_file(argv[2],argv[3]); return 0
    if len(argv)==3 and argv[1]=='tiny':
        target = _new_target(argv[2])
        raw = tiny_fixture()
        with target.open('xb') as stream: stream.write(raw)
        return 0
    if len(argv)==4 and argv[1]=='capacity':
        target = _new_target(argv[3])
        raw = capacity_fixture(int(argv[2]))
        with target.open('xb') as stream: stream.write(raw)
        return 0
    if len(argv)==6 and argv[1]=='run': return run(*argv[2:])
    raise ValueError('usage: wrap VOLUME OUT | capacity 512|1024 OUT | tiny OUT | run CASE OUTDIR IMAGE TOOLS_DIR')

if __name__=='__main__':
    try: sys.exit(main(sys.argv))
    except (OSError,ValueError) as error: print(error,file=sys.stderr); sys.exit(1)
