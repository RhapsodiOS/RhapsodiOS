"""Execute the native trampoline with reset ESP and the kernel's segment bases.

Usage: python smp_trampoline_test.py NATIVE_OBJECT OUTPUT_DIRECTORY
The generated floppy is a disposable fixture, not an OS disk.
"""
import argparse
from pathlib import Path
import shutil
import struct
import subprocess
import time


def object_text(path):
    data = Path(path).read_bytes()
    magic, _, _, _, count, _, _ = struct.unpack_from('<7I', data)
    if magic != 0xFEEDFACE:
        raise ValueError('expected a 32-bit native Mach-O object')
    offset = 28
    text = None
    symbols = {}
    for _ in range(count):
        command, size = struct.unpack_from('<2I', data, offset)
        if command == 1:
            sections = struct.unpack_from('<I', data, offset + 48)[0]
            for i in range(sections):
                section = offset + 56 + i * 68
                if data[section:section+16].rstrip(b'\0') == b'__text':
                    address, length, start = struct.unpack_from('<3I', data, section+32)
                    text = bytearray(data[start:start+length])
        elif command == 2:
            start, length, strings, _ = struct.unpack_from('<4I', data, offset+8)
            for i in range(length):
                name, kind, _, _, value = struct.unpack_from('<IBBHI', data, start+i*12)
                if name and kind & 0x0E == 0x0E:
                    end = data.index(b'\0', strings+name)
                    symbols[data[strings+name:end].decode()] = value
        offset += size
    if text is None:
        raise ValueError('missing text section')
    return text, {name: value-address for name, value in symbols.items()}


def floppy(path):
    code, symbols = object_text(path)
    page = bytearray(4096)
    start = symbols['_smp_tramp_start']
    page[:symbols['_smp_tramp_end']-start] = code[start:symbols['_smp_tramp_end']]
    base = 0x10000
    put = lambda off, value: struct.pack_into('<I', page, off, value)
    value = lambda name: struct.unpack_from('<I', code, symbols[name])[0]
    put(symbols['_smp_tramp_ljmp']-start, base+value('_smp_tramp_entry32'))
    if '_smp_tramp_base' in symbols:
        put(symbols['_smp_tramp_base']-start, base)
    put(0xF00, 0x12000)
    struct.pack_into('<HI', page, 0xF10, 23, base+0xF80)
    struct.pack_into('<HI', page, 0xF18, 0, 0)
    put(0xF20, base+0xD00)
    put(0xF24, 7)
    put(0xF28, base+0xE00)
    struct.pack_into('<IH', page, 0xF30, base+value('_smp_tramp_reload'), 8)
    struct.pack_into('<HI', page, 0xF40, 23, base+0xF50)
    # Temporary flat GDT, then kernel code/data based at 0xc0000000.
    for off, high in [(0xF50, 0x00CF9A00), (0xF80, 0xC0CF9A00)]:
        struct.pack_into('<6I', page, off, 0, 0, 0xFFFF, high,
                         0xFFFF, high-0x800)
    # The called entry checks its argument through the kernel stack segment.
    entry = bytes.fromhex('83 7c 24 04 07 75 10 66 ba e9 00')
    entry += b''.join(b'\xb0'+bytes([c])+b'\xee' for c in b'PASS')
    entry += bytes.fromhex('fa f4 eb fd')
    page[0xE00:0xE00+len(entry)] = entry
    # BIOS reads eight sectors to 0x10000; reset the stack before jumping.
    boot = bytearray(bytes.fromhex(
        'fa 31 c0 8e d8 8e d0 bc 00 7c fb '
        'b8 00 10 8e c0 31 db b8 08 02 b9 02 00 ba 00 00 cd 13 '
        'fa b8 00 12 8e c0 31 ff 31 c0 b9 00 08 f3 ab '
        '26 66 c7 06 00 00 03 30 01 00 '
        '26 66 c7 06 00 0c 03 30 01 00 '
        'b8 00 13 8e c0 31 ff 66 b8 03 00 00 00 b9 00 04 '
        '66 ab 66 05 00 10 00 00 e2 f6 '
        '66 31 e4 ea 00 00 00 10'))
    boot.extend(bytes(510-len(boot)))
    boot.extend(b'\x55\xaa')
    image = boot+page
    image.extend(bytes(1474560-len(image)))
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('object')
    parser.add_argument('output', type=Path)
    parser.add_argument('--qemu', default=shutil.which('qemu-system-i386'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    disk = args.output.resolve()/'trampoline.img'
    log = args.output.resolve()/'debug.log'
    disk.write_bytes(floppy(args.object))
    log.write_bytes(b'')
    process = subprocess.Popen([
        args.qemu, '-M', 'pc', '-accel', 'tcg', '-m', '16', '-nodefaults',
        '-display', 'none', '-serial', 'none', '-monitor', 'none',
        '-drive', f'file={disk.as_posix()},format=raw,if=floppy',
        '-boot', 'a', '-debugcon', f'file:{log.as_posix()}',
        '-global', 'isa-debugcon.iobase=0xe9', '-no-reboot',
    ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic()+10
        while time.monotonic() < deadline and process.poll() is None:
            if log.read_bytes() == b'PASS':
                break
            time.sleep(0.05)
    finally:
        if process.poll() is None:
            process.terminate()
        _, errors = process.communicate(timeout=5)
    if log.read_bytes() != b'PASS':
        print('FAIL: trampoline did not reach its entry with the expected stack argument')
        print(errors.decode(errors='replace'))
        return 1
    print('PASS: native trampoline enters paged kernel segments with a valid stack')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
