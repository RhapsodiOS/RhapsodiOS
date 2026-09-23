# i386 VESA booter support: evidence record

## Conventions

**The reference** is the 4.2 booter, `./usr/standalone/i386/boot` from
OPENSTEP 4.2 User Patch 4 (`OS42MachUserPatch4.tar`).
- 44,848 bytes, SHA-256
  `925D35B683644CDA6C090B223B00C115F1C83116D466F230B71231B7AB75CBCE`.
- It is a headerless flat image. It prints itself as `OPENSTEP boot
  v40.13.1.2`.

**Offsets and addresses.**
- `boot+N` is a **file offset** into that image. The image loads at
  `0x3000`, so the address is `boot+N + 0x3000`.
  - This holds for the text and for the data: all twelve VBE string operands
    resolve at base `0x3000` and at no other base.
- A bare hex value such as `0xDA7C` is an **address**, not an offset.
  - Its file offset is the address minus `0x3000`: `0xDA7C` is `boot+43644`.
- `kbs+0xNNNN` is an offset into `KERNBOOTSTRUCT`, which is at `0x11000`.
- Kernel addresses such as `0x0018F1B4` are virtual addresses in the i386
  slice of 4.2's `mach_kernel`. That slice is `$KREF`, described in
  `src/kernel-7/reconstruction/vbe/divergences.md`.

**"Extent"** means a function's first byte up to the byte before the next
function. It therefore includes the trailing alignment `nop`s, which occupy
the image just as the code does.

**Our build** is `src/boot-2` built with `rbuild` at this record's commit.
Its function sizes are `nm -n` deltas in `boot.sys`, which is the same kind
of extent.

**Tags.** Claims are **[measured]** when read out of a binary, a file, a
memory dump or a boot, and **[inference]** when reasoned from those. The tag
is on the line that makes the claim. Text that is later retracted will be
labelled in place, not deleted.

## Staging

The reference was extracted as follows; Task 2 staged it, and Task 3 re-hashed
it:

```
$VENVPY vm/extract-os42-patch.py "$PATCH" <dest> ./usr/standalone/i386/boot
925D35B683644CDA6C090B223B00C115F1C83116D466F230B71231B7AB75CBCE  44848  boot   [measured]
```

Other inputs, re-hashed on 2026-09-22 [measured]:

| input | bytes | SHA-256 |
| --- | --- | --- |
| `$KREF`, the 4.2 kernel's i386 slice | 1,117,920 | `33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890` |
| `vm/golden.img` | 8,589,934,592 | `E1968E3EF57F3060AA01CEAB8B4D5C49C067E6ACC5F8626EBABEEFE0E663879F` |
| stock booter on `golden.img` (`/usr/standalone/i386/boot`, v5.0.41.1) | 39,616 | `AA06C3C5BFE56C79573E36D20C662DA10CA67D0CEC5BE17F13A5B562F6B5F2C2` |

The stock booter is byte-identical to both boot-area copies on
`golden.img`, and each copy is followed by zeros [measured].

---

## Task 3: measurements

### Our booter as it stands

**The build.** It used `rbuild buildpackage --state /build/state --arch i386
--dir --target all /build/src/boot-2 /build/repo <dest>`. The Makefile's
check printed [measured]:

```
booter 44576 bytes of 45056, 480 to spare
size boot.sys: __TEXT 43008  __DATA 4768
```

**Keeping `boot.sys`.** rbuild builds inside a chroot and `rm -rf`s it once
the package is written (`src/rbuild-1/builder.c:1759-1761`, with
`opt.clean = 1` at `runner.c:858`). So `boot.sys` does not survive a normal
build [measured].
- The copy measured here was taken from inside the chroot, by the same shell
  that ran rbuild, before the cleanup.
- The flat `boot` in that copy is byte-identical to the one in the built
  package [measured].

| file | bytes | BSD `sum` | `cksum` | SHA-256 |
| --- | --- | --- | --- | --- |
| `boot` | 44,576 | `50728 44` | `1719693408 44576` | `1647E453291F012F4505444E6BC7F1E2B1C0B5F0FFBB14379ED2EBB8002BC122` |
| `boot.sys` | 1,095,680 | `27156 1070` | `4088755961 1095680` | `1C5B9C79155830484632A59E361E73F021518628ECE3EF4078F48333FADBF24A` |

Both `sum` and `cksum` were printed on the guest and recomputed locally from
the decoded bytes; they agree [measured].

**Sections of `boot.sys` [measured].**

| section | start | bytes |
| --- | --- | --- |
| `__text` | `0x3000` | 37,405 |
| `__cstring` | `0xC21D` | 4,208 |
| `__const` | `0xD290` | 1,384 |
| `__TEXT` pad, to `0xD800` | | 8 |
| `__data` | `0xD800` | 1,564 (file: 1,568) |
| `__bss` | | 1,332 |
| `__common` | | 1,864 |

The flat file is exactly `__TEXT` (43,008) plus `__DATA`'s file part (1,568).
So `-g` stabs never reach it [measured].

**Flags [measured, from the build log].** `boot2/*.c` is compiled `-O2 -g`,
and `libsaio/*.c` and `libsa/*.c` are compiled `-O -g`. All three also get
`-arch i386 -Wmost -Wno-precomp -munaligned-text -static`.

### Which booter ran: the proof later gates use [measured]

The image was `golden.img` with our `boot` in both boot-area slots
(`vm/install-booter.py`). It was booted on qemu-shot's default `cirrus`, with
`mach_kernel -v` typed at 8 s. A same-session control used the stock booter.

| line | ours | stock |
| --- | --- | --- |
| boot1 | `Rhapsody boot1 v5.0.41.1` | `Rhapsody boot1 v5.0.41.1` |
| sizing | `Sizing memory... 130559K` | `Sizing memory... 131072K` |
| **banner** | **`Rhapsody boot v5.0.2`** | **`Rhapsody boot v5.0.41.1`** |
| memory | `639K conventional / 129535K total memory` | `639K conventional / 131072K total memory` |

- **The banner is the proof of which booter ran.** It comes from
  `boot2/prompt.c:31`.
- **Both runs end on the same screen line.** The image's own kernel writes
  nothing to COM2, so both serial logs are empty. The last screen line is
  `hc0: Restore: error=0x0 secCnt=0x1 secNum=0x1 cyl=0x0 drhd=0xe0
  status=0x50`, the drvEIDE deadlock of `docs/drivers/drvEIDE-issues.md`,
  with either booter.
- **Our booter reaches userland with a working kernel.** With spec 2's kernel
  (`74B12FCD...25CFF4`) grafted in, our booter's boot reaches the rc scripts:
  its serial log ends at `Continue without network? (y/n)`.

---

## The 4.2 VBE functions (item 1)

The table below was read with capstone at base `0x3000` [measured unless
tagged]. Function starts are the targets of direct calls. The names are ours,
given by correspondence.

| 4.2 function | extent | bytes | what it does | ours | 32-bit operands |
| --- | --- | --- | --- | --- | --- |
| `execKernel` | `boot+184..1287` | 1104 | the VBE lookup (`boot+949..1059`, 111 B); the VBE set (`boot+1224..1263`, 40 B) | `boot2/boot.c:158`, 932 | in window: `0xE470`, `0xE474`, `0xC6A8` |
| `getBootString` | `boot+2244..3175` | 932 | the `VBE Check` listing (`boot+2556..2879`, 324 B) | `boot2/boot.c:563`, 616 | in window: strings, `0xDA7C`; compared: `0x1870`, `0x1876` |
| `convert_vbe_mode` | `boot+4480..4595` | 116 | a name, or failing that a decimal, to a mode number | `boot2/graphics.c:252`, 84 | in window: `0xD7C8` |
| `setMode` | `boot+4164..4459` | 296 | text, or the VGA mode `0x12` panel; no VBE path | `boot2/graphics.c:176`, 420 | not VBE code |
| mode-attributes test | `boot+27424..27515` | 92 | usable(`ModeInfoBlock*`) | new | none |
| usable and at least 640x480 | `boot+27516..27555` | 40 | the above, plus `YRes > 479 && XRes > 639` | new | none |
| record writer | `boot+27556..27703` | 148 | `(VBEModeRec*, mode, MIB*)`, fourteen stores | new | none |
| enumerator | `boot+27704..28031` | 328 | fills `kbs+0x1870` and caches the count | new | in window: `0xDA7C`, `0xDEAC`; compared: `0x1840`, `0x1870`, `0x897`, `0x308` |
| mode setter | `boot+28032..28463` | 432 | validates, sets the mode, writes `kbs+0x1858`, sets the palette | `libsaio/vbe.c:55` `set_linear_video_mode`, 304 | in window: strings, globals, `0xDAAC`, and **`0xFFFF`** (a non-address; see below); compared: `0x14C`, `0x1858`, `0x104` |
| `getVBEInfo`, `getVBEModeInfo`, `getVBEDACFormat`, `setVBEDACFormat`, `setVBEMode`, `setVBEPalette`, `getVBEPalette`, `getVBECurrentMode` | `boot+28464..29047` | 68, 80, 68, 60, 56, 96, 96, 60 | BIOS `INT 10h` `4F0x` wrappers | `libsaio/vbe.c:126-212` | **byte parity today**: `compare_flat` MATCH for all eight |

**The masking window `[0x3000, 0x11000)`.** `tools/binrecon/compare_flat.py`
masks a 32-bit operand only when it lies in this window.
- **Addresses.** Every address operand above falls inside it.
- **Other constants.** Every non-address constant falls outside it and is
  compared exactly, with one exception: the mode setter's
  `and eax, 0xFFFF` at `boot+28212`.
  - `0xFFFF` lies inside the window.
  - A rebuild that emitted any *other* in-window constant there would be
    masked and mapped, not failed.
  - That byte must be checked by hand [measured operand sweep; the risk is
    arithmetic].

**Also byte-identical to ours today** [measured]: `printf` (`boot+27392`),
`reallyPrint` (`boot+30244`) and `currentMode` (`boot+4460`).

**Data the VBE code uses [measured].**

| address | bytes | what |
| --- | --- | --- |
| `0xD7C8` | 280 | mode-name table: 13 entries plus a terminator of `{char name[16]; int mode;}`, from `640x400x256` = 0x100 to `1280x1024x888` = 0x11B; no `x16` modes |
| `0xDAAC` | 1,024 | 256-entry palette, `0x00RRGGBB` with 6-bit components |
| `0xDEAC` | 4 | enumerator's cached count, initialised to -1 |
| `0xE470`, `0xE474` | | `loaded_drivers`, `num_loaded` (bss) |
| `0xE498`, `0xE49C`, `0xEB7C`, `0xEB80`, `0xEB84` | | screen height, width, bits per pixel, frame buffer, `in_linear_mode` (bss) [names: inference, from `vbe.c:95-102`] |
| `0xEB88` | 2 | bytes per scan line: a global with no counterpart in our tree |

- **The palette is not our palette.** It is not `appleClut8 >> 2`: 254 of the
  256 entries differ [measured]. So the reference carries its own colour
  table as data, where our `setupPalette` converts `appleClut8` at run time.
- **Four wrappers are dead in the reference too.** `getVBEDACFormat`,
  `setVBEDACFormat`, `getVBEPalette` and `getVBECurrentMode` have no
  reference in the 4.2 image: a raw scan for rel32 and abs32 found none
  [measured].

### Item 4: where `VBE Mode` is read [measured]

The lookup is in `execKernel`, after the boot drivers are loaded:

```
boot+949   mode = 0
boot+956   call enumerator                        ; unconditional
boot+961   for i < num_loaded:                    ; [0xE474]
             getValueForStringTableKey(loaded_drivers[i].configTable, "VBE Mode", &val, &len)
             ; configTable is +0xC of a 28-byte record at [0xE470]; the first match wins
boot+1020  no match: skip the VBE path entirely
boot+1026  s = newStringForKey("VBE Mode")        ; getValueForKey: kbs+2 (boot line), then kbs+0x24FC (config)
           convert_vbe_mode(s ? s : val, &mode)
```

- **A driver's table must carry the key, or nothing happens.** When one does,
  a value on the boot line or in System.config overrides it.
- **What a test image needs** [inference]: it must install the VBE driver,
  whose `Default.table` sets `"VBE Mode" = "257"`. System.config needs
  nothing.
- **Our driver list is `static`.** `loaded_drivers` and `num_loaded` are
  `static` in our `libsaio/drivers.c:44-45`. The reference reads them from
  `execKernel`, so they must become visible to `boot.c` [inference].
- **Possible reference defect: a mode name from the driver's table is never
  matched.** The driver table's `val` is not NUL-terminated: it points at
  `257";...`. `convert_vbe_mode` compares whole strings with `strcmp` before
  it parses digits. So a mode name given only in a driver's table would never
  match, while a number parses [inference, from the code; a candidate
  reference defect].

### Item 5: the VESA version test [measured]

The test is in the enumerator, which the mode setter calls first.
1. `VbeSignature` is preset to `"VBE2"` (`boot+27735..27756`).
2. `getVBEInfo` is called.
3. `cmp word [ebp-1FCh], 1FFh; ja` at `boot+27782` is an unsigned test.

**4.2 accepts `VESAVersion >= 0x200`.** Any lower version, or a failed call,
leaves zero modes.

`VESA not available.\n` (`boot+28079`) is printed whenever the enumerator
returns zero, which includes the case of a VBE 2 BIOS that offers no usable
mode.

Our `vbe.c:66` accepts only `== 0x200`. The reconstruction takes 4.2's `>=`,
so **the version check is not a forced divergence**. QEMU reports 0x0300; see
item 6.

### Item 8: no terminator record [measured]

- The enumerator stores records only through the writer, at `boot+27974`.
  After its loop it stores nothing but the count, to `0xDEAC`, at
  `boot+28006`.
- **No zero record is written.** The array ends where the booter's `bzero`
  left zeros.
- The loop's bound, `edi - (kbs+0x1840) > 0x897` at `boot+27911`, admits
  indices 0 to 89: 90 records.
- At run time the record after the last was zero on both QEMU adapters (item
  6).

### Every store through the `KERNBOOTSTRUCT` pointer at `0xDA7C` [measured, coverage stated]

**Method.** A linear, per-function register tracker covered all 43 loads of
`[0xDA7C]`. It followed every register derived from the pointer through
`mov`, `lea` and `add imm`.

**What it found.**
- **Direct stores.** None into `[0x38C, 0x20D8)`. The highest is
  `kbs+0x388` (APM, `boot+8006`).
- **The mode array.** The VBE-area stores are the record writer's, through
  pointers passed as `kbs+0x1858` (`boot+28262`) and `kbs+0x1870`
  (`boot+27973`).
- **Other pointer arguments.** The remaining kbs-derived pointers handed to
  callees are `+0`, `+2`, `+0xB8`, `+0x15C`, `+0x160`, `+0x164` and
  `+0x24FC`. All of them are outside the VBE area.

**One more VBE store: `kbs+0x14C = 0`, that is `graphicsMode`,** at
`boot+28273`. The mode setter makes it right after writing the current-mode
record. The only other store to `+0x14C` is `setMode`'s (`boot+4207`).
- The offset is the same in our struct.
- Other 4.2 offsets agree with ours as well: `config` is at `+0x24FC` and
  `eisaConfigFunctions` at `+0x20F8` [measured, against
  `libsa/kernBootStruct.h`].

**Not covered.** A pointer spilled to the stack, or copied through another
global, is invisible to this method.

### The rest of the VBE path, as the code reads [measured from the disassembly]

- **The enumerator runs whether or not a mode is wanted.** `execKernel` calls
  it at `boot+956` on every boot that gets that far, so a VBE 2 adapter fills
  `kbs+0x1870..` even when no mode is ever set.
- **The mode is set last.** The set block (`boot+1224..1263`) does not test
  `-v` (`0xE480`). It runs after `Starting OPENSTEP` and after APM, right
  before `startprog`:
  1. `setMode(TEXT_MODE)`;
  2. `modeSet(mode)`;
  3. if that returns non-zero, `sleep(5)`.
- **Success prints nothing.** The mode is set with bit `0x4000` (the linear
  frame buffer), and the booter writes the record at `kbs+0x1858`,
  `graphicsMode = 0`, the globals above, and the palette at `0xDAAC` if the
  memory model is 4.
- **When the requested mode fails.** "Fails" means `getVBEModeInfo`, or the
  attribute test; the 640x480 minimum is *not* applied here. The booter
  prints `VBE mode %d not supported.\n` and then:
  - if `kbs+0x1874` is non-zero, it prints `Using VBE Mode %d.\n` naming
    `modes[0]`, sleeps 5 s, and sets `modes[0]`;
  - otherwise it prints `No usable VBE mode. Reverting to VGA.\n` and returns
    1.
- **A palette error returns 1, but the mode stays set.**

**The attribute test** (`boot+27424`) accepts a mode when all of these hold:
- the attributes have the supported, graphics and linear-frame-buffer bits;
- if the memory model is 6 (direct colour), the red, green and blue mask
  sizes are equal and are 5 or 8, and the depth is 15, 16 or 32.

Packed-pixel modes pass on their attributes alone. 565 and 24-bit
direct-colour modes are rejected.

---

## Item 6: the reference booter under QEMU [measured]

**Setup.**
- The image was `golden.img` with the spec 2 kernel (`74B12FCD...25CFF4`)
  grafted in, spec 1's driver installed (`_reloc` `77399531...`), and the 4.2
  booter written to both boot slots.
- Every installed file was read back and hashed before booting.
- The run typed `"VBE Check"=Yes` and Return at 7 s. The key has a space in
  it, so it must be quoted: `getBootString` looks it up with
  `getValueForBootKey` (`boot+2592`).
- Memory was saved at 12 s: `0x11000..0x131FF` and `0x0..0xFFFF`.

| | `-vga cirrus` | `-vga std` |
| --- | --- | --- |
| `VbeVersion` (the `VbeInfoBlock` was still on the stack at `0xFCF8`) | 0x0300 | 0x0300 |
| video memory | 4 MB | 16 MB |
| `VideoModePtr` | `0000:FD1A`, inside the caller's buffer | `0000:FD1A` |
| BIOS mode list | 31 entries, 15 of them VBE | 93 entries, 77 of them VBE |
| records 4.2 wrote | 8 | 30 |
| record 0 | mode 257, 640x480, 640 B/line, 8 bpp, model 4, attr `0xBB`, fb `0xFC000000` | mode 257, the same, fb `0xFD000000` |
| usable modes | 257, 272, 259, 275, 261, 278, 263, 281 | 257, 259, 261, 263, 272, 275, 278, 281, 284, 285, 322-325, 327, 328, 329, 332, 375, 378, 381, 384, 387, 390, 393, 396, 399, 402, 405, 408 |

- **The segment is 0, so 4.2's pointer shortcut works here.** 4.2 uses
  `VideoModePtr` as `(segment << 16) | offset`, and with a zero segment that
  is the right address. Under a BIOS that returned a non-zero segment it
  would read the wrong memory [inference].
- **The on-screen listing matches the records** (`Usable VBE modes:`, three
  per line).
- **The dumps.** `kbs+0x1854..0x186F` is zero. The array occupies
  `0x1870..0x192F` on cirrus and `0x1870..0x1B3F` on std, and everything
  after it up to `0x20D8` is zero. `boot_video` is zero. Neither adapter
  comes near the 89-record cap.
- **The 4.2 booter cannot boot this image.** After `-v`, or after the
  countdown expires, it prints four `Bad superblock: error 2`, then `Config
  file "/private/Drivers/i386/System.config/Default.table" not found` and
  `System config file 'System' not found`, and returns to `boot:`. It
  byte-swaps the little-endian superblock, which is the bug
  `docs/boot/sarld-driver-link-limit.md` fixed in our `sys.c`. So
  `execKernel` never runs, and items 7 and 10 below rest on the code
  [measured].

### Item 7: VBE mode on a `-v` boot [inference, from the code above]

- **The mode is entered whether or not `-v` was given.**
- **The booter draws nothing in the VBE mode.** It switches to text mode
  first and sets `graphicsMode` to 0 after the mode set.
- **G2 will see the kernel's scrolling console** on the frame-buffer
  console, not a booter panel.

### Item 10: after `Reverting to VGA` [inference, from the code above]

- **No BIOS mode is set** and no record is written; `graphicsMode` is
  untouched.
- **The screen stays in VGA text mode 2.** `execKernel`'s `setMode(0)` call
  (`boot+1232`) put it there: `setMode` sets video mode 2 at `boot+4361`, and
  sets `graphicsMode` 0 if it changed the mode.
- **Then a 5 s pause** (`boot+1254`), and the kernel starts.
- **`VESA not available.` takes the same path.**

## Item 9: which depths the frame-buffer console draws [measured, `src/kernel-7/bsd/dev/i386/FBConsole.c`]

- **What `FBAllocateConsole` does (`:1354`).** It copies the display
  information and checks no depth.
- **What the drawing code handles.** Every drawing switch covers exactly
  three pixel sizes and `panic`s on anything else:
  - `IO_8BitsPerPixel`, 1 byte;
  - `IO_12BitsPerPixel` and `IO_15BitsPerPixel`, 2 bytes;
  - `IO_24BitsPerPixel`, 4 bytes.
  The switches are at `:152`, `:175`, `:221`, `:310`, `:414`, `:466`, `:708`
  and `:1036`.
- **`IO_2BitsPerPixel` cannot be drawn.** It appears only in `BPPToPPW`
  (`:142`), and drawing it would panic.
- **How VBE depths map.** `VBEModeInfo2IODisplayInfo` maps 8 to IO_8, 15 and
  16 to IO_15, and 24 and 32 to IO_24.

**G2 uses mode 257 (640x480, 8 bpp) on `-vga cirrus`.**
- Mode 257 is record 0 on both adapters, and IO_8 draws it.
- `cirrus` is qemu-shot's default and the adapter every spec 2 capture
  used.
- `-vga std` is the alternative. It is the only one of the two with usable
  32-bpp modes.

---

## Item 2: the byte budget

**Byte parity means the reconstruction costs what the reference's functions
cost.** Growth is the reference size minus our counterpart's, or the full
reference size for a new function.

| item | 4.2 | ours | growth |
| --- | --- | --- | --- |
| `execKernel` | 1104 | 932 | +172 (its VBE blocks alone: 151) |
| `getBootString` | 932 | 616 | +324 (its VBE block; larger than the whole-function delta, 316) |
| `convert_vbe_mode` | 116 | 84 | +32 |
| `setMode` | 296 | 420 | -124 |
| four new functions | 92 + 40 + 148 + 328 | none | +608 |
| mode setter | 432 | 304 | +128 |
| `setupPalette` | none | 84 | -84 |
| eight BIOS wrappers | 584 | 584 | 0 |
| palette, count, name table | 1024 + 4 + 280 | 340 | +968 |
| `appleClut8`, `models[]` | none | 768 + 32 | -800 |
| strings: 14 added, 13 removed | 331 | 215 | +116 |
| **total** | | | **+1,340** |

- **Where the sizes come from.** The 4.2 figures are extents and ours are
  `nm` deltas [measured]. The growth column is arithmetic.
- **Segment rounding can add up to 15 bytes**, since `__TEXT` is rounded to
  16. **Budget: at most 1,355.**
- **Spare today: 480** [measured]. **So trimming must find 875.**

## Item 3: where our extra ~5 KB comes from

Measured against the stock booter on `golden.img`:

| | ours | stock | difference |
| --- | --- | --- | --- |
| `__text` | 37,405 | 34,708 | +2,697 |
| rest of `__TEXT` | 5,603 | 4,268 | +1,335 |
| `__DATA` in the file | 1,568 | 640 | +928 |
| file | 44,576 | 39,616 | +4,960 |

1. **VBE code: about 2,600 bytes, which the reconstruction replaces.** The
   stock booter has none: no `4F0x` function code and no VBE string
   [measured]. Ours has `vbe.o` (2,025), `convert_vbe_mode` and
   `mode_table` (424), `setMode`'s VBE branch and `"Graphics Mode"`
   [measured parts].
2. **Dead code: 1,602 bytes**, listed below [measured].
3. **A second 64-bit divide, `__divdi3` plus its own `__clz_tab`: 669
   bytes.** It is called from `open()`, so it runs. Stock and 4.2 have one
   divide routine each; ours has two [measured].
4. **Wait-cursor data: 864 bytes in ours** [measured], against about 270 in
   4.2 [inference, by inspection]. It runs in graphics mode.
5. **Functions of ours with no stock match found:** `getMemoryMap`,
   `getExtendedMemoryE801`, `ebiosread`, `get_diskinfo`. They run
   [inference, from a fuzzy match].
6. **Flags are not a source** [inference]. `-g` does not reach the file
   [measured]. Eleven of our functions are byte-identical to 4.2's across
   both `-O` and `-O2` objects [measured].

### Trim candidates, ranked: input to Task 5, not a decision

**Method.** "Unreachable" means no rel32, rel8 or abs32 reference to the
function's start at *any* byte offset in the linked image, and no path from
`boot2`, `__real_to_prot` or `do_int` [measured]. This over-approximates
references, so an unreachable result is a strong claim.

| rank | bytes | what | why nothing needs it |
| --- | --- | --- | --- |
| 1 | 600 | `blit_string`, `blit_bm`, `blit_clear`, `strheight` (`libsaio/font.c`) | unreachable. The callers are in `browser.c`, `button.c` and `questionbox.c`, which `boot2/Makefile:36-39` does not build, and in a comment at `graphics.c:74-80` [measured] |
| 2 | 408 | `strtol` (`libsa/strtol.c:112`) | unreachable; no caller [measured]. `strtoul`, in the same object, is used |
| 3 | 284 | `getVBEDACFormat`, `setVBEDACFormat`, `getVBEPalette`, `getVBECurrentMode` | unreachable here **and in 4.2** [measured]. They belong to the reference's `vbe.c`, so removing them is a departure. **Not counted** |
| 4 | 116 | `loadModule` (`boot2/module.c:35`) | unreachable; its only caller is under `#if TEST` [measured] |
| 5 | 76 | `swapBigIntsToHost`, `swapBigShortToHosts` (`libsaio/ufs_byteorder.c`) | unreachable; the callers are commented out [measured] |
| 6 | 64 | `slvprintf` (`libsa/sprintf.c:66`) | unreachable [measured] |
| 7 | 48 | `realloc` (`libsa/zalloc.c:251`) | unreachable. The callers are in unbuilt `libsaio/old` and in `nasm` [measured] |
| 8 | 6 | `__sp` (`libsaio/asm.s:282`) | unreachable [measured] |

**Ranks 1, 2 and 4 to 8 total 1,318 bytes.** Each size includes the function's
alignment pad. So the saving per object can differ by a few bytes once the
alignment shifts [inference].

### The stop gate

Growth, at most 1,355, is less than spare plus the [measured] candidates:
480 + 1,318 = 1,798.
- **The gate passes, with 443 bytes to spare.**
- It passes without rank 3 and without anything that runs.
- Ranks 1, 2 and 4 alone give 1,124, which is more than the 875 needed.

---

## The frame-buffer mapping (kernel half, in short)

The full record is in `src/kernel-7/reconstruction/vbe/divergences.md`,
"Spec 3: the frame-buffer mapping".

In brief: 4.2's `pmap_bootstrap` inlines `pmap_map` to map
`[trunc_page(fb), end)` read-write, at the first free kernel virtual address
after the physical-memory map and a 64 MB page-table reservation. It stores
that address, plus `fb`'s page offset, at `0x12854`. It does all of this only
when the booter's record at `0x12858` has a non-zero `xResolution`
[measured].

**This closes spec 2's D2 inference as correct.** The booter never writes
`0x12854`. It writes `0x12858..` only.

## Where the evidence contradicts the plan or the spec

1. **G1.** The spec expects `kbs+0x1854` to `+0x20D8` all zero when no
   `VBE Mode` key is set. 4.2 runs the enumerator on every boot that reaches
   `execKernel`, so on a VBE 2 adapter `kbs+0x1870..` is filled with or
   without the key. A byte-parity booter will fill it too.
   - Only `kbs+0x1854..0x186F` stays zero.
   - This was not observed at run time, because the 4.2 booter cannot read
     `golden.img` [measured code; inference for the run].
2. **G2.**
   - **No panel.** "The booter's panel is drawn in the VBE mode" cannot
     happen. 4.2 sets the mode last, after switching to text, and draws
     nothing in it.
   - **No `Using VBE Mode N` on success.** The success path prints nothing.
     `Using VBE Mode %d.` is printed only when the booter falls back to
     `modes[0]`.
   - **Nothing on serial.** The booter prints to the screen, never to serial
     [measured code].
3. **G3 case 1.** When a `VBE Mode` names a mode the BIOS does not offer,
   4.2 does not revert to VGA if any usable mode exists. It prints `VBE mode
   N not supported.` and `Using VBE Mode M.`, then sets `modes[0]` and writes
   its record [measured code].
4. **`setMode`.** 4.2's `setMode` has a VGA mode-`0x12` panel path. Ours
   falls back to text whenever the `Graphics Mode` key is absent. Byte parity
   for `setMode` would therefore bring the VGA panel back on `Boot Graphics`
   boots, a visible change. The budget uses 4.2's size, -124. Deleting only
   our VBE branch would save more [inference].
5. **The spec's §4.1 omits the `graphicsMode = 0` store.** It lists the
   stores through `0xDA7C` as `+0x1858` and `+0x1870`. There is a third, in
   the mode setter: `kbs+0x14C = 0` [measured].
6. **The palette.** Byte parity needs 4.2's own 1,024-byte palette, whose
   colours differ from `appleClut8`'s. That costs +172 net against
   `setupPalette` plus `appleClut8` [measured].
