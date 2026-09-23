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
    **[CORRECTED — Task 3b, review M6: "no other base" overstates. Only the
    bases 0, `0x1000` and `0x2000` were tested, and the operands resolve at
    none of them [measured].]**
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
| `0xE470`, `0xE474` | | `loaded_drivers`, `num_loaded` (bss) [names: inference, by correspondence with `libsaio/drivers.c:44-45` and the writer `addToLoadedDriverList`; added in Task 3b, review M6] |
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

**[CORRECTED — Task 3b, review M3: the coverage statement was imprecise; the
conclusion is unchanged.]** [measured, re-read in Task 3b]
- **There are 45 references to `0xDA7C`, not 43.** The 43 are loads. The
  other two are `sub eax,[0xDA7C]` at `boot+17344` and `boot+17487`: each
  computes `configEnd - kbs` and compares it with `0xD000` before printing
  `No room in memory for config files`. They derive no pointer.
- **Indexed stores, which the tracker also found.** There are two, and both
  are bounded:
  - `boot+489`, one byte (`' '`) into `bootString` at `kbs+2`, at an index
    bounded by the string's length;
  - `boot+19171`, `diskInfo[0..3]` at `kbs+0x13C..0x148`, in a loop bounded
    by `cmp byte [ebp-4],3; jbe`.
- **The `+0` pointer below is not outside the VBE area.** It is the
  whole-struct `bzero(kbs, 0xF4FC)` at `boot+19079`, which runs before any
  VBE store.

**What it found.**
- **Direct stores.** None into `[0x38C, 0x20D8)`. The highest is
  `kbs+0x388` (APM, `boot+8006`).
- **The mode array.** The VBE-area stores are the record writer's, through
  pointers passed as `kbs+0x1858` (`boot+28262`) and `kbs+0x1870`
  (`boot+27973`).
- **Other pointer arguments.** The remaining kbs-derived pointers handed to
  callees are `+0`, `+2`, `+0xB8`, `+0x15C`, `+0x160`, `+0x164` and
  `+0x24FC`. All of them are outside the VBE area.
  **[CORRECTED — Task 3b, review M3: `+0` is the whole-struct `bzero`
  above, so it covers the VBE area; the other six are outside it.]**

**One more VBE store: `kbs+0x14C = 0`, that is `graphicsMode`,** at
`boot+28273`. The mode setter makes it right after writing the current-mode
record. The only other store to `+0x14C` is `setMode`'s (`boot+4207`).
- The offset is the same in our struct.
- Other 4.2 offsets agree with ours as well: `config` is at `+0x24FC` and
  `eisaConfigFunctions` at `+0x20F8` [measured, against
  `libsa/kernBootStruct.h`].

**Not covered.** A pointer spilled to the stack, or copied through another
global, is invisible to this method.
- **One such copy exists** [measured, Task 3b, review M3]: `kbs+0x158`
  (`configEnd`) receives the kbs-derived pointer `kbs+0x24FC` at
  `boot+19217`, and later writes go through it. That is a copy into the
  struct itself, of the kind this paragraph names.

**What is covered, stated whole** [measured, Task 3b's re-reading agrees with
the review's]: nothing stores into `[0x38C, 0x20D8)` except the record writer
(through `kbs+0x1858` and `kbs+0x1870`) and the whole-struct `bzero`.

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
  **[CORRECTED — Task 3b, review M6: two claims in this bullet carried the
  wrong tag.]**
  - **Measured:** the messages above, and that the enumerator never ran: on
    the plain runs `[0x1854, 0x20D8)` is all zero in the dumps.
  - **Inference:** that it byte-swaps the superblock. That rests on the
    message matching `docs/boot/sarld-driver-link-limit.md`, not on a
    reading of 4.2's `sys` code.
  - **Inference:** that `execKernel` never runs. With the config unread,
    `boot()` loops back at `boot+1961..1968` before calling it. But
    `execKernel` could also have been entered and have returned at
    `boot+369..373`, before the enumerator, and the dumps cannot tell the
    two apart.

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
  **[CORRECTED — Task 3b, review M1: that mechanism holds only when the
  `Boot Graphics` panel is up. The corrected bullet follows.]**
- **The screen is in VGA text, by one of two routes** [inference, from the
  code]:
  - `setMode` returns at once when `currentMode() == mode`
    (`boot+4172..4179`), and only two calls set a video mode, both in
    `setMode`: `set_video_mode(0x12)` at `boot+4256` and
    `set_video_mode(2)` at `boot+4363` [measured].
  - **When the panel is not up** (a typed boot line, or no `Boot
    Graphics`), `graphicsMode` is still 0 at `boot+1232`. `setMode(0)` then
    does nothing, and the screen stays in the text mode the BIOS left.
  - **When the panel is up** (nothing typed, `Boot Graphics` = Yes, as on
    `golden.img`; see Task 3b), `graphicsMode` is 1 at `boot+1232`.
    `setMode(0)` then writes `graphicsMode` 0 (`boot+4207`), sets mode 2
    (`boot+4363`) and replays the text it buffered.
  - Either way the outcome is the same: a VGA text console, no record,
    `graphicsMode` 0.
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

**[SUPERSEDED — Task 3b: after the user's decisions, the budget is 492, at
most 537. The palette's +172 (the rows for the palette, `appleClut8` and
`setupPalette`) leaves it, and the panel path adds -676. See "Task 3b".]**

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
| 2 | 408 | `strtol` (`libsa/strtol.c:112`) | unreachable; no caller [measured]. `strtoul`, in the same object, is used. **[CORRECTED — Task 5: "no caller" holds for `boot` only. `libsa.a` is also linked into `sarld`, which the same package builds and ships, and `libsarld.a` has `U _strtol`. With `strtol` deleted, the `sarld` link failed with `Undefined symbols: _strtol` [measured]. Not removable from source; see "Task 5: the trim".]** |
| 3 | 284 | `getVBEDACFormat`, `setVBEDACFormat`, `getVBEPalette`, `getVBECurrentMode` | unreachable here **and in 4.2** [measured]. They belong to the reference's `vbe.c`, so removing them is a departure. **Not counted** |
| 4 | 116 | `loadModule` (`boot2/module.c:35`) | unreachable; its only caller is under `#if TEST` [measured] |
| 5 | 76 | `swapBigIntsToHost`, `swapBigShortToHosts` (`libsaio/ufs_byteorder.c`) | unreachable; the callers are commented out [measured] |
| 6 | 64 | `slvprintf` (`libsa/sprintf.c:66`) | unreachable [measured]. **[CORRECTED — Task 3b, review M7: its one caller, `tests/satest.c:44`, is a test program the booter does not build.]** **[CORRECTED — Task 5: it has a caller in the package. `sarld` links `libsa.a`, and `libsarld.a` has `U _slvprintf`, from `vprint` (`src/cctools-2/ld/rld.c:1787`, under `SA_RLD`) [measured]. Not removable from source.]** |
| 7 | 48 | `realloc` (`libsa/zalloc.c:251`) | unreachable. The callers are in unbuilt `libsaio/old` and in `nasm` [measured]. **[CORRECTED — Task 3b, review M7: the host-side callers are `nasm` and `util/mkfont.c:321`; neither is part of the booter.]** **[CORRECTED — Task 5: `sarld`, built by the same package from the same `libsa.a`, calls it. `libsarld.a` has `U _realloc`, from `reallocate` (`src/cctools-2/ld/rld.c:1823`, under `SA_RLD`) [measured]. Not removable from source.]** |
| 8 | 6 | `__sp` (`libsaio/asm.s:282`) | unreachable [measured] |

**Ranks 1, 2 and 4 to 8 total 1,318 bytes.** Each size includes the function's
alignment pad. So the saving per object can differ by a few bytes once the
alignment shifts [inference].
**[CORRECTED — Task 5: the method scanned the linked `boot` only. Ranks 2, 6
and 7 live in `libsa.a`, which `sarld` links too, and `sarld` needs all three
[measured]. Only ranks 4, 5 and 8 (198 bytes) could be removed, and they saved
192 bytes of file [measured]. See "Task 5: the trim".]**

### The stop gate

Growth, at most 1,355, is less than spare plus the [measured] candidates:
480 + 1,318 = 1,798.
- **The gate passes, with 443 bytes to spare.**
- It passes without rank 3 and without anything that runs.
- Ranks 1, 2 and 4 alone give 1,124, which is more than the 875 needed.

**[SUPERSEDED — Task 3b: re-evaluated after the panel decision. Rank 1
becomes reachable through 4.2's `message`, so the pool is 718. The gate
still passes: at most 537 against 480 + 718 = 1,198. See "Task 3b".]**

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
   **[CORRECTED — Task 3b, review M6: "every boot that reaches `execKernel`"
   overstates. The call at `boot+956` is unconditional once the kernel has
   loaded; `execKernel` returns earlier, at `boot+369..373`, when `loadprog`
   fails. So it runs on every boot whose kernel load succeeds [measured].]**
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
     **[Method added in Task 3b, review M6.]** [measured] The only `int`
     instruction the linear decode finds in `__text` is the trampoline's
     `int 0` at `boot+31015` (function `boot+30924`), whose operand is
     patched at run time with the interrupt number the caller stored. Its 19
     callers store only 0x10, 0x12, 0x13, 0x15, 0x16 and 0x1A; none stores
     0x14, the serial BIOS.
     `__text` (`boot+0..38175`) holds no `0x3F8`, `0x2F8` or `0x2E8`
     immediate. Its only `0x3E8` is `push 0x3e8`, the `spin(1000)` count in
     `set_video_mode`.
3. **G3 case 1.** When a `VBE Mode` names a mode the BIOS does not offer,
   4.2 does not revert to VGA if any usable mode exists. It prints `VBE mode
   N not supported.` and `Using VBE Mode M.`, then sets `modes[0]` and writes
   its record [measured code].
4. **`setMode`.** 4.2's `setMode` has a VGA mode-`0x12` panel path. Ours
   falls back to text whenever the `Graphics Mode` key is absent. Byte parity
   for `setMode` would therefore bring the VGA panel back on `Boot Graphics`
   boots, a visible change. The budget uses 4.2's size, -124. Deleting only
   our VBE branch would save more [inference].
   **[SUPERSEDED — decided by the user after Task 3: rebuild 4.2's `setMode`,
   panel path included. Task 3b measures it.]**
5. **The spec's §4.1 omits the `graphicsMode = 0` store.** It lists the
   stores through `0xDA7C` as `+0x1858` and `+0x1870`. There is a third, in
   the mode setter: `kbs+0x14C = 0` [measured].
6. **The palette.** Byte parity needs 4.2's own 1,024-byte palette, whose
   colours differ from `appleClut8`'s. That costs +172 net against
   `setupPalette` plus `appleClut8` [measured].
   **[SUPERSEDED — decided by the user after Task 3: keep our palette
   (`setupPalette(appleClut8)`), a forced divergence in the mode setter. The
   +172 leaves the budget; see Task 3b.]**

---

## Task 3b: setMode and the Boot Graphics panel

After Task 3, the user chose to rebuild 4.2's `setMode` with its VGA
mode-`0x12` panel, and to keep our palette (spec §1). This section measures
what that costs and what a default boot then does.

**Inputs, re-hashed on 2026-09-22 [measured]:**
- `$BREF`, `925D35B6...CBCE`;
- our Task 3 booter, `1647E453...BC122`;
- the stock booter, `AA06C3C5...F6B5F2C2`.

**Method.**
- The listings are Task 3's capstone listings, at base `0x3000`.
- The call graph follows direct calls and absolute function references.
- Pairs of functions were compared with `compare_flat`, with the trailing
  `nop` or `00` pad stripped on both sides.
- Nothing was built or booted.

### What 4.2's `setMode` does [measured]

```
setMode(mode)                                    ; boot+4164..4459, 296 B
  if (currentMode() == mode) return;             ; boot+4172..4179
  if (!initMode(mode)) return;                   ; boot+4186
  kernBootStruct->graphicsMode = mode;           ; boot+4207: both branches, before the mode set
  if (mode == GRAPHICS_MODE) {
      textBuf = malloc(0x600); showText = 0; bufIndex = 0;
      set_video_mode(0x12);                      ; boot+4256
      clearRect(0, 0, SCREEN_W, SCREEN_H, 1);    ; boot+4283
      copyImage(bitmapList[0].bitmap,            ; boot+4347, the panel, centred
                (SCREEN_W - panel->width) / 2, (SCREEN_H - panel->height) / 2);
  } else {
      showText = 1;
      set_video_mode(2);                         ; boot+4363
      if (textBuf) { replay bufIndex bytes through putchar; free(textBuf); textBuf = 0; }
  }
  currentIndicator = 0;                          ; boot+4440
```

- **`boot+4256` is not a BIOS call** [measured].
  - `set_video_mode` first sets `SCREEN_W` and `SCREEN_H` to 640 and 480
    (`boot+30343..30352`).
  - It sends modes 2 and 3 to the BIOS through `video_mode` (`INT 10h`).
  - It programs mode `0x12` itself, from the register table `VGAMode12` at
    `0xD65C`.
  - It then loads all 256 DAC entries with the four greys of `colorData`,
    `{0x00, 0x15, 0x2A, 0x3F}`. This is the panel's whole palette.
    The user's palette decision does not touch it.
- **How ours differs** (`boot2/graphics.c:176-221`):
  - Ours has no panel branch. Its graphics branch needs a `Graphics Mode` key
    (`:189-190`) and sets a linear VBE mode.
  - Without that key, ours takes the text branch, which never writes
    `graphicsMode`. Ours writes it only in the VBE branch (`:203`).
- **The callers** [measured]:
  - `setMode(1)`: `boot+2042` in `boot()`, and `boot+1119` in `execKernel`;
  - `setMode(0)`: `boot+605`, `+739`, `+778`, `+1071`, `+1232`, `+1571`,
    `+1777` and `+18425`;
  - `initMode(1)`: `boot+3051` in `getBootString`.

### The `Boot Graphics` handling [measured]

| where | 4.2 | ours |
| --- | --- | --- |
| `getBootString`, `boot+3007..3059` | if nothing was typed (`line[0] == 0`), `errors == 0` and `Boot Graphics` is Yes: `wantBootGraphics = 1` (`0xE484`), then `initMode(1)` | the same statement, `boot.c:631-641` |
| `boot()`, `boot+2031..2042` | outside Install Mode: `if (wantBootGraphics) setMode(1)` | the same, `boot.c:518-519` |
| `boot()`, after the config is loaded | **no `Boot Graphics` test** | **`boot.c:503-506` sets `wantBootGraphics` whenever the key is Yes, typed line or not**: 24 bytes at `0x364E..0x3665` in our build |
| `execKernel`, `boot+1108..1124` | after the `errors` pause: `if (wantBootGraphics) setMode(1)` | the same, `boot.c:320-321` |

**`boot.c:503-506` must go with the rebuild** [inference, from the code].
- 4.2's `boot()` has no such test [measured].
- Suppose only `setMode` were rebuilt. A typed `mach_kernel -v` boot would
  then:
  - show the panel;
  - buffer its text instead of printing it;
  - hand the kernel `graphicsMode` 1.
- 4.2 keeps that boot in text, so G1's verbose comparison would fail.
- Today the test is harmless: our `setMode` falls back to text.

### Inventory: the panel path

**How the path was found** [measured, call graph].
- In 4.2, five functions have code that depends on the panel: `setMode`,
  `initMode`, `message`, `spinActivityIndicator` and
  `clearActivityIndicator`.
- With those five cut from the call graph, 18 more functions become
  unreachable from the entry at `boot+0`.
- A scan of every byte offset of the image, for `E8`/`E9` rel32 targets and
  for abs32 values, confirms it: every reference to the 18 is a call from
  inside the path, and none is an address held in data.
- These 23 functions, 4,180 bytes, are the panel path.

**What is left out.** `setMode`'s own transitive closure is 88 functions.
- The other 74 are the file system, disk, BIOS, `malloc`, `printf` and
  string layers, which `loadFont` and `loadBitmap` reach through `open` and
  `read`.
- The booter reaches all of them without the panel, so they are not listed.

| 4.2 function | extent | bytes | role | ours | compare |
| --- | --- | --- | --- | --- | --- |
| `setMode` | `boot+4164..4459` | 296 | text, or the mode-`0x12` panel | `boot2/graphics.c:176`, 420 | same lineage; ours has a VBE branch where 4.2 has the panel |
| `currentMode` | `boot+4460..4479` | 20 | `kbs->graphicsMode` | `graphics.c:223`, 20 | **MATCH** |
| `initMode` | `boot+4068..4163` | 96 | loads the panel and the font, once | `graphics.c:150`, 96 | **MATCH** |
| `loadAllBitmaps` | `boot+4940..5083` | 144 | reads `Panel.image` | `graphics.c:324`, 144 | **MATCH** |
| `loadFont` | `boot+5084..5271` | 188 | reads `Default.font` | `graphics.c:348`, 188 | **MATCH** |
| `loadBitmap` | `boot+30028..30243` | 216 | reads a 24-byte header, then two planes | `libsaio/bitmap.c:37`, 200 | same lineage; differs only through `struct bitmap` (`sizeof` `0x18` against `0x20`, `short` against `long` fields) |
| `PackBitsDecode` | `boot+33512..33675` | 164 | unpacks one plane row | `libsaio/unpackbits.c:60`, 164 | **MATCH** |
| `set_video_mode` | `boot+30332..30923` | 592 | modes 2 and 3 by BIOS; `0x12` by registers; the grey DAC | `libsaio/vga.c:216`, 592 | **MATCH**; `VGAMode12` (61 B) and `colorData` (4 B) are byte-equal too |
| `spin` | `boot+30300..30331` | 32 | the DAC write delay | `vga.c:209`, 32 | **MATCH** |
| `video_mode` | `boot+6664..6707` | 44 | BIOS `INT 10h`, `AH=0` | `libsaio/biosfn.c:204`, 44 | **MATCH** |
| `clearRect` | `boot+20276..20547` | 272 | planar fill; returns at once if `in_linear_mode` | `libsaio/console.c:298`, 380 | same lineage; ours adds a linear branch (`:321-337`) |
| `copyImage` | `boot+20024..20275` | 252 | planar blit; returns at once if `in_linear_mode` | `console.c:241`, 400 | same lineage; the planar part differs only through `struct bitmap`; ours adds a linear branch (`:270-290`) |
| `blitRow` | `boot+19580..20023` | 444 | one planar row, through the GC bit mask | `console.c:178`, 444 | **MATCH** |
| `message` | `boot+3764..4067` | 304 | in graphics mode, `blit_clear` and `blit_string` in the panel; otherwise it prints | `graphics.c:57`, 200 | same lineage; ours comments the graphics branch out (`:75-81`) and calls `strwidth("9")` instead |
| `spinActivityIndicator` | `boot+4596..4827` | 232 | in graphics mode, `copyImage` of the wait cursors | `graphics.c:286`, 232 | differs in two `struct bitmap` offsets only (`+8`/`+0xA` against `+0xC`/`+0xE`) |
| `clearActivityIndicator` | `boot+4828..4939` | 112 | in graphics mode, `clearRect(cursor, 16, 16, 2)` | `graphics.c:310`, 28 | same lineage; ours comments the `clearRect` out (`:319`) |
| `getbm` | `boot+29256..29291` | 36 | glyph lookup | `libsaio/font.c:60`, 36 | **MATCH** |
| `blit_bm` | `boot+29292..29451` | 160 | draws a glyph through `clearRect` | `font.c:80`, 160 | **MATCH** |
| `strwidth_internal` | `boot+29452..29567` | 116 | | `font.c:100`, 116 | **MATCH** |
| `strwidth` | `boot+29568..29587` | 20 | | `font.c:125`, 20 | **MATCH** |
| `strheight` | `boot+29588..29663` | 76 | | `font.c:140`, 76 | **MATCH** |
| `blit_clear` | `boot+29664..29783` | 120 | clears a text line | `font.c:155`, 120 | **MATCH** |
| `blit_string` | `boot+29784..30027` | 244 | draws a string | `font.c:167`, 244 | **MATCH** |

- **Every function on the path has a counterpart in our tree, and no new
  function is needed.**
  - 16 of the 23 are byte-identical to ours today.
  - The other 7 are same-lineage variants of ours.
- `putchar` (`boot+19396`, 112 B, `console.c:79`) replays the buffered text.
  It is also **MATCH**, but it is shared, not panel-only.

**Data on the path.**

| item | 4.2 | ours |
| --- | --- | --- |
| `struct bitmap` | 24 B: six `short`s (`packed`, `bytes_per_plane`, `bytes_per_row`, `bits_per_pixel`, `width`, `height`), `short plane_len[2]`, two plane pointers [measured offsets; the names by correspondence] | `util/bitmap.h:39-47`: 32 B, with `long` `packed`, `bytes_per_plane` and `plane_len[2]`. The 24-byte layout is in our tree at `src/boot-2/ppc/ppcMac/util/bitmap.h:39-47` |
| wait cursors | `0xD944..0xDA4B`, 264 B: three of (64 B of two planes plus a 24 B struct). The plane bytes equal `util/ns_wait{1,2,3}_bitmap.h` [measured] | `0xD804..0xDB63`, 864 B: three of (a 256 B 8-bpp image plus a 32 B struct), from `util/spin_cursor.h` |
| `indicator_bitmap[4]` | `0xD8EC`, 16 B | `0xDCD8`, 16 B |
| `VGAMode12`, `colorData` | `0xD65C`, 61 + 4 B | `0xD5B0`, `0xD5ED`: byte-equal |
| `leftMaskArray` | `0xDA85`, 8 B | `0xDD55`: byte-equal |
| strings | `Panel.image`, `Default.font`, the two path formats, `English.lproj`, the four error messages | all present in ours [measured]; none added or removed |

**What `golden.img` holds, read from the image without writing to it
[measured]:**
- **`Panel.image`**: 6,785 bytes, SHA-256
  `654B3AF2EA437AA24DDACE21570A0EAAAECB77CDA234BC0A9163F490754F070E`.
  - Its header, read with 4.2's layout, is `{1, 11616, 44, 1, 352, 264,
    {3537, 3224}}`, and 24 + 3,537 + 3,224 = 6,785 exactly.
  - Our 32-byte layout reads it as width 3,537, height 3,224 and plane
    lengths `{0, 0}`.
  - Drawn that way, it would write far outside the 64 KB VGA window
    [inference, arithmetic].
  - **So the rebuild needs 4.2's `struct bitmap`.** It also changes
    `util/bitmap.h`, which the host tool `util/dumptiff.m` includes; Task 6
    or 7 should check whether anything in the booter build runs that tool
    [inference].
- **`English.lproj/Default.font`**: 1,387 bytes, `17F5AB21...C25D53`. It is
  read by the byte-identical `loadFont`.
- **`Default.table` and `Instance0.table`** both set `"Boot Graphics" =
  "Yes"`, and neither has a `VBE Mode` or `Graphics Mode` key.

**Colours and geometry, read from 4.2's call arguments [measured; the macro
names are ours, by correspondence].** Tasks 6 and 7 need these values.

| constant | 4.2 | ours (`boot2/graphics.h`) |
| --- | --- | --- |
| `SCREEN_BG` | 1 (`clearRect`, `boot+4279`) | `COLOR_PLATNUM` 0x80 (`:79`) |
| `TEXT_BG` | 2 (`blit_clear`, `boot+3924`; `clearActivityIndicator`, `boot+4854`) | `COLOR_LT_GREY` 0xFA (`:77`) |
| `TEXT_FG` | 0 (`blit_string`, `boot+3957`) | `COLOR_DK_GREY` 0xFE (`:78`) |
| the message's x | `SCREEN_W / 2` | `BOX_C_X` = `SCREEN_W / 2 + 4` (`:42`) |
| the message's y | `BOX_Y + BOX_H / 2` | `MESSAGE_Y` = `BOX_Y + 182` (`:64`) |
| the width `blit_clear` clears | `BOX_W - 16` | `BOX_W - 48`, in the commented-out code |
| the cursor | `BOX_Y + 148` and centred, as ours | `CURSOR_Y` (`:62`) |

With `colorData`'s greys, 0 is black, 1 dark grey, 2 light grey and 3
white [inference].

**The stock booter has the same panel.**
- **What was measured:**
  - its `setMode` (`stock+3616..3903`) pushes `0x12`;
  - it reads the bitmap at `+8` and `+0xA`;
  - it uses the constants 640 and 480 where 4.2 reads `SCREEN_W` and
    `SCREEN_H`;
  - its `VGAMode12` is byte-identical, at `stock+38676`.
- **What follows** [inference]: the panel that spec 2 captured on
  `golden.img` (`shots-t5-dC1`, 15 s) is VGA mode `0x12`.
  `docs/kernel/i386-vbe-console.md` had left that mode undetermined.

### Is there planar or mode-`0x12` drawing code in our tree? Yes [measured]

**Coverage.**
- `git grep -E "VGA_BUF_ADDR|VGAMode12|blitRow|set_video_mode|in_linear_mode|VGA_SEQ_ADDR|VGA_GC_ADDR"`
  over all 32,370 tracked files under `src/`, and a reading of every hit.
- The file lists of `src/boot-2/i386/util` and `src/boot-2/ppc/ppcMac`.
- The only hits outside the booter are the kernel's VGA console
  (`src/kernel-7/bsd/dev/i386/VGAConsole.c`, `VGAConsPriv.h`,
  `BasicConsole.c`).

**In the i386 booter, and built today:**
- `libsaio/vga.c:109-130` (`VGAMode12`) and `:215-323` (`set_video_mode`):
  byte-identical to 4.2;
- `libsaio/console.c:178-234`, `blitRow`: byte-identical;
- `console.c:247-269` and `:308-320`, the `!in_linear_mode` branches of
  `copyImage` and `clearRect`: the planar code. They differ from 4.2 only
  through `struct bitmap`;
- `libsaio/font.c`, whose glyph drawing goes through `clearRect`:
  byte-identical.

None of this code runs today. Our `setMode` never calls
`set_video_mode(0x12)` (`graphics.c:176-221`) [measured source].

**In the tree, but not built:**
- `util/ns_wait{1,2,3}_bitmap.h`: 4.2's planar wait cursors, byte-equal.
  `boot2/bitmaps.c:31-35` comments out their `#import`s.
- `ppc/ppcMac/util/bitmap.h:39-47`: 4.2's 24-byte `struct bitmap`.
- `ppc/ppcMac/libsaio/console.c:170-287`: `blitRow`, `copyImage` and
  `clearRect` with no linear branch.
- `util/Panel.image`: a planar panel in the 24-byte format (5,584 B; not
  golden's). `util/Newpanel.image` is the 32-byte, 8-bpp one.

### The budget delta [measured sizes; the sums are arithmetic]

**Task 3's budget included 4.2's palette, and it now leaves.** [measured, in
item 2's table]
- The table counts:
  - the 1,024-byte palette (+1,024, in the "palette, count, name table" row);
  - the removal of `appleClut8` (-768);
  - the removal of `setupPalette` (-84).
- The net is +172. Keeping our palette removes all three: 1,340 - 172 =
  **1,168**.
- The mode setter then calls `setupPalette(appleClut8)` where 4.2 passes its
  table. How that changes the mode setter's own size cannot be measured
  without a build [inference: a few bytes].

**What the panel path adds on top.**

| item | 4.2 | ours | growth |
| --- | --- | --- | --- |
| `setMode` | 296 | 420 | -124, already in Task 3's budget and not added again |
| `copyImage` | 252 | 400 | -148 |
| `clearRect` | 272 | 380 | -108 |
| `loadBitmap` | 216 | 200 | +16 |
| `message` | 304 | 200 | +104 |
| `clearActivityIndicator` | 112 | 28 | +84 |
| `spinActivityIndicator` | 232 | 232 | 0 |
| `boot()`: drop the second `Boot Graphics` test | none | 24 | -24 |
| the other 16 functions on the path | | | 0 (byte-identical) |
| **code** | | | **-76** |
| wait cursors | 264 | 864 | -600 |
| the other data and the strings | | | 0 |
| **panel path** | | | **-676** |

- **The new budget: 1,168 - 676 = 492.**
- **Rounding.** It can add about 45 bytes: 15 for `__TEXT`, and about 30 more
  for `__DATA`'s file part and `__const`'s alignment (review M4). **So the
  budget is at most 537.**
- **The rest of `boot()`.** Byte parity for the whole of `boot()` would give
  -12, not -24.
  - The other 12 bytes are a memory-size check that is larger in 4.2, and
    that check is outside the panel path.
  - Counting -12 instead gives 504, at most 549. The verdict below does not
    change.

### The stop gate, re-evaluated

- **The trim pool shrinks.** 4.2's `message` calls `blit_clear` and
  `blit_string` (`boot+3950`, `boot+3976`), and `blit_string` calls
  `blit_bm` and `strheight` [measured]. So all of rank 1 (600 bytes) becomes
  reachable once `message` is rebuilt, and it leaves the pool. The pool is
  now 1,318 - 600 = **718**, all [measured].
- **Available:** 480 spare + 718 = **1,198**.
- **Growth:** 492, at most 537.
- **The gate passes:** 537 <= 1,198, with 661 bytes to spare.
  - Trimming must find only 12 bytes, or 57 at the rounding bound.
  - Rank 2 (`strtol`, 408) covers that alone.

  **[CORRECTED — Task 5: the pool is not 718. Ranks 2, 6 and 7 are needed
  by `sarld`, so the pool is ranks 4, 5 and 8: 198 by `nm`, 192 in the file
  [measured]. Measured spare after them: **672**. The gate still passes,
  537 <= 672, with 135 to spare, but the 256-byte margin is not met. Rank 2
  does not cover it. See "Task 5: the trim".]**
- **A narrower reading gives the same verdict.** Suppose only `setMode`'s
  closure is rebuilt, and `message` and `clearActivityIndicator` stay ours.
  - The code delta is then -264 and the data delta -600.
  - The budget is 304, at most 349, which is under the 480 spare with no
    trimming at all.
  - Rank 1 then stays a trim.

### The default boot after the rebuild [inference, from the code, unless tagged]

**Setup.** `golden.img`'s config has `Boot Graphics` = Yes and no `VBE Mode`
[measured above]. Nothing is typed.

1. **`getBootString`.** The countdown expires with an empty line and no
   errors, so it sets `wantBootGraphics` and calls `initMode(1)`, which loads
   `Panel.image` and `Default.font` (`boot+3007..3059`).
2. **`boot()`.** Outside Install Mode it calls `setMode(1)` (`boot+2042`),
   which:
   - writes `graphicsMode` = 1 (`boot+4207`);
   - buffers the booter's text (`showText` = 0);
   - programs VGA mode `0x12` (`boot+4256`);
   - clears the screen to colour 1;
   - copies the 352x264 panel to (144, 108).
3. **While the panel is up**:
   - `message` draws `Loading OPENSTEP` and the later messages in the panel,
     centred at (320, 240);
   - the wait cursor spins at (312, 256) during disk reads;
   - `clearActivityIndicator` erases it.
4. **`execKernel`.**
   - The enumerator fills `kbs+0x1870..` (C1).
   - No loaded driver carries `VBE Mode`, so the lookup is skipped
     (`boot+1020`).
   - `setMode(1)` at `boot+1119` is a no-op.
   - The VBE set block is skipped, because the mode is 0 (`boot+1224..1228`).
   - `startprog` then starts the kernel.
5. **The kernel receives `graphicsMode` = 1**, with the screen still in mode
   `0x12` showing the panel. `kbs+0x1854..0x186F` and `boot_video` are zero.
6. **Mode 2 is never set on this path.**
   - Only `setMode(0)`, called while `graphicsMode` is 1, sets mode 2
     (`boot+4363`).
   - The default path calls `setMode(0)` only at `boot+1571` and
     `boot+1777`, both before the panel exists.
   - The other `setMode(0)` calls (above) run only on one of these:
     - errors (`+1071`);
     - `Prompt For Driver Disk` (`+605`);
     - `Ask For Drivers` (`+739`);
     - a missing driver (`+778`);
     - `Query` (`+18425`);
     - a VBE mode (`+1232`).
7. **The kernel side** [inference, from our source]:
   - `kminit` (`bsd/dev/i386/km.m:501-504`) starts the basic console in
     `SCM_GRAPHIC`;
   - `kmEnableAnimation` (`kmDevice.m:594-608`) animates the wait cursor, and
     the `kmDevice` probe also opens in `SCM_GRAPHIC` (`kmDevice.m:119`).

**What corroborates this [measured, spec 2].** Spec 2 booted `golden.img`
with the stock booter, whose `setMode` has the same shape.
- The default boot handed the kernel `graphicsMode` 1, and the verbose boot 0.
- `boot_video` was zero on both.
- The default boot settled on the kernel's panel.
- See `src/kernel-7/reconstruction/vbe/divergences.md`, "What the booter
  hands the kernel, measured in guest memory".

**Our booter today, on the same boot** [inference, from the source].
`setMode(GRAPHICS_MODE)` finds no `Graphics Mode` key and takes the text
branch (`graphics.c:189-211`). That sets mode 2 through the BIOS and leaves
`graphicsMode` 0.

**A typed `mach_kernel -v` boot in 4.2** [measured code]. `getBootString`
skips the `Boot Graphics` test when the line is not empty
(`boot+3007..3014`). So there is no panel, and the kernel gets
`graphicsMode` 0, as spec 2 measured for the stock booter. Our rebuilt booter
matches this only if `boot.c:503-506` goes.

**For G1:**
- **Default boots:** the control hands the kernel 0 and the candidate 1.
  That difference is by design. The candidate's booter-phase frames show the
  panel.
- **Verbose boots:** both hand the kernel 0, and the kernel-phase frames must
  match. That needs `boot.c:503-506` removed.
- **The boot that settles this:** a no-keys boot of Task 7's booter on
  `golden.img`, dumping `0x11000..` at about 15 s. It should show
  `graphicsMode` = 1 at `0x1114C`, and the 15 s frame should show the panel.
  A typed `-v` boot should show 0.
- **With a `VBE Mode` on a default boot**, `setMode(0)` at `boot+1232` leaves
  the panel for mode 2 and replays the buffered text. Then the mode setter
  sets the VBE mode and writes `graphicsMode` 0. G2 therefore needs no typed
  line [inference].

---

## Task 5: the trim

**Target.** Spare of at least 793 bytes: Task 3b's budget of at most 537,
plus a 256-byte margin. Spare before Task 5: 480 [measured, Task 3].

**Result: the target is not met, and the user accepted that.**
- The candidates that can be removed give **672** spare [measured]. That
  covers the budget, with 135 bytes to spare instead of 256.
- 793 was not reached because ranks 2, 6 and 7 are still linked by `sarld`
  (below).
- **The user accepted 672 spare on 2026-09-22**: the 537 budget with a
  135-byte margin. See "The decision".

### How each candidate's evidence was re-checked

- **Our source.** It is Task 4's commit, whose build is byte-identical to
  Task 3's `1647E453...BC122` [measured, Task 4]. So Task 3's binary evidence
  applies to it.
- **References in `boot`.** The control booter was re-scanned at every byte
  offset for an `E8`/`E9`/`0F 8x` rel32, an `EB`/`7x` rel8 or an abs32 value
  landing on each candidate's start. Every candidate got 0 hits [measured].
- **Callers in source.** `git grep` over `src/boot-2/i386` [measured].
- **Other programs that link the same archive (new in Task 5).**
  - `libsa.a` is linked into two programs of this package: `boot`
    (`boot2/Makefile:27`) and `sarld` (`sarld/Makefile:10`, `:25-28`: `-lsarld
    $(LIBSA)` with `-nostdlib`). The package ships `sarld` as
    `/usr/standalone/i386/sarld` [measured, the Makefiles and the package].
  - The build root's `/usr/local/lib/libsarld.a` (2,549,964 bytes) has
    `U _realloc`, `U _slvprintf`, `U _strtol` and `U _strtoul` [measured,
    `nm -o`].
  - Its sources are `src/cctools-2/ld`, built with `-DRLD -DSA_RLD`. Under
    `SA_RLD`, `rld.c:1787` (`vprint`) calls `slvprintf` and `rld.c:1823`
    (`reallocate`) calls `realloc` [measured source]. `pass1.c` calls
    `strtol`; which of its calls survive `-DRLD` was not determined.
  - Task 4's `sarld.sys` defines all four [measured, `nm -n`].
  - `libsaio.a` and the `boot2` objects are linked into `boot` only. The one
    other Makefile that names `libsaio.a`, `testmodule`'s, is not in
    `i386/Makefile`'s `SUBDIRS` [measured].
- **4.2.** A fuzzy match of our functions against `$BREF` (Task 3's
  `match.py`) found each counterpart, and a raw scan looked for references to
  it.

| rank | bytes (`nm`) | candidate | taken? | evidence, re-checked |
| --- | --- | --- | --- | --- |
| 1 | 600 | `blit_string`, `blit_bm`, `blit_clear`, `strheight` | no | on 4.2's panel path, which a later task rebuilds: 4.2's `message` reaches them (Task 3b) |
| 2 | 408 | `strtol` | **skipped** | no reference in `boot` [measured]. But `sarld` needs it: the first Task 5 build, with `strtol` deleted, failed at the `sarld` link with `/usr/bin/ld: Undefined symbols: _strtol`, `rbuild: failed with status 2` [measured]. 4.2 has a counterpart at `boot+35436` (472 B, similarity 0.91) with 0 references [measured] |
| 3 | 284 | 4 VBE wrappers | no | part of 4.2's `vbe.c`. Tasks 6 and 7 rebuild it; all eight wrappers are byte-identical today (Task 3). Not counted by Task 3 either |
| 4 | 116 | `loadModule` | **taken** | 0 references in `boot` [measured]. Its one caller, `module.c:56`, is under `#if TEST`, and `TEST` is not defined for the booter: `boot2/Makefile:9-11` sets no `-DTEST`, and the control's `nm` has no `_testModules` [measured]. 4.2's counterpart, `boot+3648` (116 B, similarity 1.00), has 0 references [measured]. Not on the VBE or panel path |
| 5 | 76 | `swapBigIntsToHost`, `swapBigShortToHosts` | **taken** | 0 references in `boot` [measured]. The only mentions are in comments (`ufs_byteorder.c:127`, `:159`, before the edit) [measured]. 4.2 does call both, from `boot+31192` [measured]. That function is not on the VBE or panel path, and ours has no live call |
| 6 | 64 | `slvprintf` | **skipped** | no reference in `boot` [measured], but `sarld` needs it (`U _slvprintf`, `rld.c:1787`) [measured] |
| 7 | 48 | `realloc` | **skipped** | no reference in `boot` [measured], but `sarld` needs it (`U _realloc`, `rld.c:1823`) [measured] |
| 8 | 6 | `__sp` | **taken** | 0 references in `boot` [measured]. The only other mention is a comment at `libsa/zalloc.c:121` [measured]. 4.2 has the same three bytes, `89 E0 C3`, at `boot+6334`, with 0 references [measured] |

### The edits, one per candidate

| rank | file:line (before the edit) | change |
| --- | --- | --- |
| 4 | `i386/boot2/Makefile:36` | `module.o` leaves `OBJS`. `module.c` holds only `loadModule` (`:34-50`) and the `#if TEST` block, so nothing else leaves |
| 5 | `i386/libsaio/ufs_byteorder.c:71-89` | both functions deleted |
| 8 | `i386/libsaio/asm.s:281-284` | `LABEL(__sp)` and its two instructions deleted |

The rank 2 edit (`strtol.c:105-197` and its `libsa.h:67-71` prototype) was
reverted after its build failed.

### The build [measured]

`rbuild` as Task 3 Step 2, with a mid-build copy of the symbol tree:

```
RC=0
booter 44384 bytes of 45056, 672 to spare
size boot.sys: __TEXT 42816  __DATA 4768
```

| file | bytes | guest `sum` | guest `cksum` | SHA-256 |
| --- | --- | --- | --- | --- |
| `boot` | 44,384 | `283 44` | `952813041 44384` | `A75FCA09F27B28A46A5626289F4A36335FAB273F556341390E5461B9C556F31A` |
| `boot.sys` | 1,075,408 | `63720 1051` | `2204390520 1075408` | `D5C58CDAA826C293CC9289E3686EBFC97948C4A87F8FBED74275C4E4B21D3D8C` |

- The package's `boot` is `cmp`-identical to the copy.
- The local decode reproduces both `sum`s and both `cksum`s.
- `sarld` (`2333113453 148108`) and `sarld.sys` (`1163817294 1414240`) are
  `cmp`-identical to Task 4's.

**Where the 192 bytes came from.**
- `__text` went from 37,405 to 37,209 bytes, 196 fewer:
  - `module.o`: -116;
  - `ufs_byteorder.o`: -76;
  - `asm.o`: -4, not 6. `__sp`'s 6-byte extent was 3 bytes of code and 3 of
    pad, and `_startprog` now carries 2 bytes of pad.
- `__TEXT` is rounded to 16 bytes: 43,008 became 42,816, 192 fewer. The file
  shrank by the same 192.

### Nothing else changed [measured]

Every function and every data section of the trimmed `boot` was compared
with the control's (`t3-ours-boot`), using both `boot.sys` symbol tables.
- **Symbols.** Exactly four symbols are gone: `_loadModule`, `__sp`,
  `_swapBigIntsToHost` and `_swapBigShortToHosts`. The other 363 are in the
  same order.
- **Functions.** 225 functions are in both.
  - 55 are byte-identical.
  - 170 differ only in 1,094 abs32 addresses and 365 rel32 targets. Each maps
    to where the same symbol, string or offset moved. No byte is left
    unexplained.
- **`__data`.** It has 33 differing addresses, all mapped, and nothing else
  differs. One of them is the GDT base inside the GDTR at `0xDD2C`, which is
  unaligned.
- **`__const`.** Byte-identical.
- **`__cstring`.** The same 196 strings. `/usr/standalone/i386/%s` used to be
  placed by `module.o` and is now placed by `graphics.o` (`graphics.c:335`),
  so it and the 7 strings between those two places moved differently from the
  rest.

### The boot comparison: A-B-A on the verbose path [measured]

**Setup.**
- Three boots in one session: A1 = the control, B = the trimmed booter, A2 =
  the control again.
- Before each boot, `test.img` was rebuilt from `$GOLDEN`: `$KSPEC2` was
  grafted, then the booter installed. `/mach_kernel` and both boot slots were
  read back and matched.
- `qemu-shot.py --at 5,15,30,60,120 --keys $'mach_kernel -v\n' --keys-at 8`,
  on cirrus.
- Captures: `vm/shots-t5trim-{A1,B,A2}`.

**Which booter ran.** All three 5 s frames show `Rhapsody boot v5.0.2`. They
are pixel-identical: `276180227B36...`, which is also Task 3's 5 s hash.

**Serial.**
- Each log has 76 lines, 8 of them `intr: phantom IRQ 15, EOI to master`.
- Line 4 is identical in all three, date included, because the kernel is the
  same.
- With the 8 phantom lines removed, the three logs are identical (69 lines,
  `54292347...`).
- The phantom lines sit in different places in each boot:
  - A1 has 1 after `hc0: device detected` and 7 after `Registering: hd0`,
    all inside the IDE-probe block;
  - B has the first of those, and 7 after `Power management is enabled.`;
  - A2 has all 8 after `Power management is enabled.`.
- Rule 3 allows this.

**Frames.** Masked as rule 4 says: the `HH:MM:SS` cells, spec 2's mask.

| pair | 5 s | 15 s | 30, 60 and 120 s |
| --- | --- | --- | --- |
| A1 / B | 0 px | 10,870 px | 2,443 px, text rows 0-4 |
| B / A2 | 0 px | 9,669 px | **0 px, raw** |
| A1 / A2 (control against control) | 0 px | 15,017 px | 2,443 px, text rows 0-4 |

- **Rule 4 fails for A1 / B** at 15 s and in the settled frames.
- **Each difference is where the phantom lines landed on screen.**
  - All three 15 s frames are at the same stage, just after `Power management
    is enabled.`, and differ only in where the phantom lines are.
  - A1's settled frame scrolled its phantom lines off the top. B's and A2's
    show five of them in text rows 0-4.
- **A1 differs from A2, the same booter, by exactly the same 2,443 px.**
  - B's settled frame and A2's are one image, `125C4133...`.
- This is the verbose-mode race spec 2 recorded (`docs/kernel/i386-vbe-console.md`,
  "The comparison rules as applied"), where a same-kernel pair also failed
  rule 4.

**Verdict: pass.** The controller ruled on 2026-09-22; this was a question
of method, not of behaviour.
- **B equals A2 pixel for pixel, with no mask,** in the 30, 60 and 120 s
  frames [measured].
- **The A1 differences are the phantom-IRQ placement race.** The A1 / A2
  control pair differs by the same 2,443 px [measured].
- **The serial matches under rule 3** [measured].
- Rule 4 as written did not allow for the race on screen. The plan's rule is
  being amended to match rule 3.
- The static comparison above agrees: nothing changed beyond the removed
  functions and the moved addresses.

### A dead function Task 3's scan missed [measured]

`setCursorPosition` (`libsaio/biosfn.c:362`, 60 bytes) has no reference in
the trimmed `boot`.
- In the control, its only raw hit is the rel32 of `call _free` at
  `boot+14399` in `removeKeyFromTable`. The bytes `30 49 00 00` happen to
  equal its address, `0x4930`: a false positive of the over-approximating
  scan.
- It is not in Task 3's list, so Task 5 did not remove it. It would add at
  most 64 bytes, not the 121 still needed [arithmetic].

### The decision

The shortfall is 793 - 672 = 121 bytes [arithmetic].

**On 2026-09-22 the user accepted 672 spare**, the 537 budget with a
135-byte margin. The trim stays at ranks 4, 5 and 8.

**A fallback, not taken:** split `strtoul` into its own object [inference].
- `boot` would then link only `strtoul`, and `sarld` would still find
  `strtol` in `libsa.a`.
- That frees about 400 bytes for `boot`, if Tasks 6 and 7 run short.
- `sarld` needs both symbols (`U _strtol`, `U _strtoul`), so it would link
  two objects where it links one today. Whether its bytes change is not
  measured.

Two other options were raised and not taken:
- separate objects for `slvprintf` and `realloc`, about 112 bytes
  [inference];
- removing `setCursorPosition`, up to 64 bytes, which is not on Task 3's
  list.

---

## Task 6: 4.2's VBE functions in `libsaio/vbe.c`

**What is rebuilt.** The five functions of the 4.2 image's
`boot+0x6B00..0x6F30` region that our tree lacks or has only in part (item 1's
table): the mode-attributes test, the 640x480 test, the record writer, the
enumerator and the mode setter. `printf` (`boot+27392`) and the eight BIOS
wrappers after the setter (`boot+28464..29047`) already match. They sit in
4.2's order in `vbe.c`, ahead of `setupPalette` and the wrappers.

**Method.**
- Each build is `rbuild` as Task 3 Step 2, after `vm/sync-src.ps1 -Path
  boot-2`, with a copy of `boot-64-2.sym/i386` taken from inside the chroot
  before the cleanup. Each binary was checked by its guest `sum` and `cksum`,
  recomputed locally from the decoded bytes.
- Our function's extent is its `nm -n` delta in `boot.sys`, as in Task 3.
- `compare_flat.py` compares it with the reference at base `0x3000` on both
  sides.

**Names.** Only the mode setter has a counterpart, `set_linear_video_mode`,
and it keeps that name. The other four have none in our tree, so they are
named here: `vbeModeIsUsable`, `vbeModeIsLargeEnough`, `recordVBEMode` and
`enumerateVBEModes`. 4.2's own names are not in the image.

### The record writer [measured]

| | |
| --- | --- |
| reference | `boot+27556..27703`, 148 bytes (`0x9BA4`) |
| ours | `_recordVBEMode`, `0x98D4`, 148 bytes (next: `_set_linear_video_mode` at `0x9968`) |
| `compare_flat` | `MATCH: 50 instructions, 148 bytes compared, 0 masked, 0 addresses mapped` |
| outcome | **byte parity** |

- The signature is Task 3's, `(boot_vbe_mode *, unsigned short, VBEModeInfoBlock *)`,
  with Task 4's type for the record.
- The physical address goes through `vbe.h`'s `ADDRESS()` macro. It builds the
  same byte-by-byte `shl`/`or` sequence as 4.2, including the spill to
  `[ebp-4]`.
- The build, `t6a`: `booter 44528 bytes of 45056, 528 to spare`; `boot`
  `sum 10234 44`, `cksum 3300415786 44528`, SHA-256
  `443A8AF8E4DDD6719E3A4961E8F76E5E2ED9E2139D6599A32FDEA730CABD6C06`;
  `boot.sys` `cksum 198241776 1075932`. The package's `boot` is
  `cmp`-identical to the copy. The file grew by 144 bytes over Task 5's
  44,384.

### The two mode tests [measured]

| | the mode-attributes test | the 640x480 test |
| --- | --- | --- |
| reference | `boot+27424..27515`, 92 bytes (`0x9B20`) | `boot+27516..27555`, 40 bytes (`0x9B7C`) |
| ours | `_vbeModeIsUsable`, `0x98D4`, 92 bytes | `_vbeModeIsLargeEnough`, `0x9930`, 40 bytes (next: `_recordVBEMode` at `0x9958`) |
| `compare_flat` | `MATCH: 39 instructions, 82 bytes compared, 10 masked, 0 addresses mapped` | `MATCH: 17 instructions, 34 bytes compared, 6 masked, 1 addresses mapped` (`map 0x9b20 -> 0x98d4`) |
| outcome | **byte parity** | **byte parity** |

- The masked bytes are relative branches. The first function's 10 are its ten
  short conditional jumps, which `compare_flat` checks as function-relative
  offsets. The second's 6 are its `call` to the first and its two short
  jumps.
- Each attribute bit is its own `if`, in 4.2's order: supported, linear,
  graphics. The compiler narrows each to a byte test, as 4.2's does.
- `BitsPerPixel != 15 && != 16` compiles to 4.2's range test (`add al,0F1h;
  cmp al,1; jbe`).
- Measured in build `t6b`, which also carries the enumerator; its size line
  and hashes are under the enumerator below.
