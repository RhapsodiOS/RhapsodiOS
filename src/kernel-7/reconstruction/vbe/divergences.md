# i386 VESA kernel support — evidence record

## Conventions for the addresses cited below

The reference is the **i386 slice of OPENSTEP 4.2's fat `mach_kernel`**, as
shipped in `OS42MachUserPatch4.tar`. Slice 1 of 3 (`cputype` 7, `cpusub` 3), at
offset 835,584 of the fat file, 1,117,920 bytes, SHA-256
`33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890`. The fat
file itself is 3,399,572 bytes, SHA-256
`6D602AAD16720EA413B90F716E90C83A942961BEECC48663626DE6807DB620EE`.

Bare hex addresses such as `0x0019ED8C` are **virtual addresses in that slice**.
The slice is `MH_EXECUTE`, its `__TEXT` segment has `vmaddr` `0x00100000` and
`fileoff` 0, so within `__TEXT`:

```
file offset = virtual address - 0x100000
```

`__text` is `vmaddr` `0x001012D0`, file offset 4,816, size `0xCFDEC`. Every
address quoted here is in `__text` unless said otherwise.

**"function offset N"** means byte offset `N` from a named function's entry,
counted from the first opcode byte.

`boot+N` means byte offset `N` into the 4.2 booter, `./usr/standalone/i386/boot`
from the same patch: 44,848 bytes, SHA-256
`925D35B683644CDA6C090B223B00C115F1C83116D466F230B71231B7AB75CBCE`. It is a
headerless image; the offsets quoted for it are **file offsets**, and its own
load address was not calibrated (not needed for anything below).

`kbs+0xNNNN` means an offset into `KERNBOOTSTRUCT`, whose fixed address is
`0x11000` (`src/kernel-7/machdep/i386/kernBootStruct.h:101`,
`src/boot-2/i386/libsa/kernBootStruct.h:175`). So `0x12858` is `kbs+0x1858`.

Claims are marked **[measured]** when read directly out of a binary or emitted
by a compiler, and **[inference]** when reasoned from those readings. Nothing
here is asserted from the plan, the design spec or any brief without
independent confirmation; where this record contradicts them it says so.

## Staging (Task 1)

```
$VENVPY vm/extract-os42-patch.py "$PATCH" <dest> ./mach_kernel
6D602AAD16720EA413B90F716E90C83A942961BEECC48663626DE6807DB620EE   3399572  mach_kernel
```

Fat header, parsed rather than assumed **[measured]**:

| slice | cputype | cpusub | offset | size | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| 0 | 6 (m68k) | 1 | 68 | 832,380 | `FDE7C8A6…E87933` |
| 1 | **7 (i386)** | 3 | **835,584** | **1,117,920** | `33469393…F14890` |
| 2 | 14 (sparc) | 0 | 1,957,888 | 1,441,684 | `96926E13…9C19294` |

Slice 1 was written to `$KREF` and re-hashed there: 1,117,920 bytes,
`33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890`. Matches
`$KREFSHA`.

`$PROFILE` (`tools/binrecon/profiles/os42-kernel-vbe.json`) is
`cirruslogic-gd5434.json` with `name` and `output_dir` changed, IDA enabled,
Ghidra and angr disabled. `binrecon validate` reports both artifacts with the
expected size and hash.

### The slice has no relocation table at all [measured]

Every section in the slice reports `nreloc = 0` — `__text`, `__const`,
`__cstring`, `__data` and all twenty `__OBJC` sections. `filetype` is 2
(`MH_EXECUTE`) and the only load commands are five `LC_SEGMENT`, one
`LC_SYMTAB` and one `LC_UNIXTHREAD`; there is no `LC_DYSYMTAB`.

The design spec's §6 says "The reference kernel, like the driver, carries
scattered relocations" and directs Task 2 to reuse spec 1's
scattered-relocation-aware masking. **That is false for this binary.** There are
no relocations of any kind to be aware of. The plan's own
"Why the compare harness cannot use relocations" section has it right; §6
contradicts it. Task 2 must mask by pattern only.

### The symbol table carries no local symbols [measured]

`LC_SYMTAB` has 3,751 symbols: 3,651 of `n_type` `0x0F` (`N_SECT | N_EXT`) and
100 of `n_type` `0x03` (`N_ABS | N_EXT`). There are no `N_STAB` entries and no
non-external `N_SECT` entries, so every `static` function in the kernel is
nameless. This is why D1 and D4 cannot be answered from the symbol table.

The three symbols that matter, and their neighbours **[measured]**:

| Address | Symbol | Delta to next |
| --- | --- | --- |
| `0x0019B760` | `_VGAAllocateConsole` | 13,508 |
| `0x0019EC24` | `_FBAllocateConsole` | 148 |
| `0x0019ECB8` | `_FBAllocateVBEConsole` | 212 |
| `0x0019ED8C` | `_VBEModeInfo2IODisplayInfo` | 7,484 |
| `0x001A0AC8` | `_PCPatoi` | — |

---

## D1: the real extent of `VBEModeInfo2IODisplayInfo`

**Answer:** 539 bytes of code; jump table at function offset **76**;
**31** entries.

### The three numbers [measured]

| | Value | Plan's reading | |
| --- | --- | --- | --- |
| Function size | **539** bytes (`0x21B`), `0x0019ED8C`–`0x0019EFA6` inclusive, one past the end `0x0019EFA7` | not stated | derived here |
| Jump-table offset | **76** (`0x4C`), i.e. `0x0019EDD8` | 76 | confirmed |
| Entry count | **31** | 31 | confirmed |

A fourth number the harness needs, which the plan got wrong:

| | Value | Plan's reading |
| --- | --- | --- |
| Dispatch instruction offset | **68** (`0x44`) | 69 — **refuted** |
| Its `imm32` offset | **71**, four bytes at 71–74 | would be 72 under the plan's 69 |

`0x0019EDD0 - 0x0019ED8C = 0x44 = 68`. The plan's off-by-one matters: a harness
that masks four bytes at offset 72 masks `ED 19 00 90` — three bytes of the
table base plus the alignment `nop` — leaving byte `D8` of the relocated operand
exposed and needlessly masking a byte that must compare.

### Why 539 and not the 7,484-byte symbol delta

The next *named* symbol is `_PCPatoi` at `0x001A0AC8`. The end was established
by a recursive control-flow walk from the entry plus all 31 table targets as
seeds, following every direct branch, stopping at `ret`:

- Reachable code spans `0x0019ED8C`–`0x0019EFA6`; the last instruction is the
  single `ret` at `0x0019EFA6`, one byte long, so the code ends at
  `0x0019EFA7`. **[measured]**
- There are **no direct calls** anywhere in the walk — it is a leaf.
  **[measured]** (This confirms the design spec's §3 claim independently.)
- No branch leaves `[0x0019ED8C, 0x0019EFA7)`. **[measured]**

Coverage check: with the 124 table bytes accounted for, the only bytes in
`[0x0019ED8C, 0x0019EFA7)` not covered by a decoded instruction are seven runs
of `0x90`, 17 bytes in all, listed here with their function offsets:

```
0x0019EDD7  fn+75   1 byte   90            (aligns the table to 4)
0x0019EE5D  fn+209  3 bytes  90 90 90      (after case body 0; aligns body 1)
0x0019EE69  fn+221  3 bytes  90 90 90      (after body 1; aligns body 2)
0x0019EE75  fn+233  3 bytes  90 90 90      (after body 2; aligns body 3)
0x0019EE81  fn+245  3 bytes  90 90 90      (after body 3; aligns body 4)
0x0019EE8D  fn+257  3 bytes  90 90 90      (after body 4; aligns the default body)
0x0019EED3  fn+327  1 byte   90            (aligns 0x0019EED4)
```

So **the 124-byte table at offset 76 is the only inline data in the function**
— there is no second table for the harness to find. **[measured]**

`0x0019EFA7` holds one more `0x90`, and `0x0019EFA8` begins `55 89 E5` —
`push ebp; mov ebp,esp`. **[measured]** Counting that pad, the distance to the
next function is 540. Task 2 should compare **539 bytes** and treat the pad as
inter-function alignment, since our build's own padding depends on where the
next function lands.

Function bytes, for re-checking: `0x0019ED8C`, 539 bytes, file offset 650,636,
SHA-256 `BDDC94F5BF87EB434DCC0E72650CF9975528F2A1E7FE67CF1AC65D9079CD2B21`.

### The dispatch, byte for byte [measured]

```
0019EDC0  0fb6430a        movzx eax, byte ptr [ebx+0xa]   ; bitsPerPixel
0019EDC4  83c0fe          add   eax, -2
0019EDC7  83f81e          cmp   eax, 0x1e
0019EDCA  0f87c0000000    ja    0x0019EE90                ; default
0019EDD0  ff2485d8ed1900  jmp   dword ptr [eax*4 + 0x19edd8]
0019EDD7  90              nop                             ; align table to 4
0019EDD8  <table>
```

`cmp eax,0x1E` + `ja` admits `eax` in `0..0x1E`, which is **31** values, so 31
entries, 124 bytes, occupying function offsets **76 through 199** (half-open
`[76, 200)`).

The count is also **forced independently**: entry 0 is `0x0019EE54`, and
`0x0019EDD8 + 31*4 = 0x0019EE54`. The first case body begins exactly where the
table ends, so a 32nd entry would overlap it. **[measured]**

### The 31 entries [measured]

`eax = bitsPerPixel - 2`, so table **index** `i` is `bitsPerPixel = i + 2`. The
two columns below are different numbers; read them separately.

| table index (`eax`) | bpp (`index + 2`) | target | fn offset |
| --- | --- | --- | --- |
| 0 | 2 | `0x0019EE54` | 200 |
| 6 | 8 | `0x0019EE60` | 212 |
| 10 | 12 | `0x0019EE6C` | 224 |
| 13, 14 | 15, 16 | `0x0019EE78` | 236 |
| 22, 30 | 24, 32 | `0x0019EE84` | 248 |
| the other 24: 1–5, 7–9, 11–12, 15–21, 23–29 | 3–7, 9–11, 13–14, 17–23, 25–31 | `0x0019EE90` | 260 |

The two `13`–`14` pairs are unrelated: **indices** 13 and 14 are bpp 15 and 16,
while **bpp** 13 and 14 are indices 11 and 12, which go to the default body.

`0x0019EE90` is also the `ja` default target, so unlisted depths and
out-of-range depths share one body.

Raw table bytes, for re-checking:

```
0019EDD8  54ee190090ee190090ee190090ee1900
0019EDE8  90ee190090ee190060ee190090ee1900
0019EDF8  90ee190090ee19006cee190090ee1900
0019EE08  90ee190078ee190078ee190090ee1900
0019EE18  90ee190090ee190090ee190090ee1900
0019EE28  90ee190090ee190084ee190090ee1900
0019EE38  90ee190090ee190090ee190090ee1900
0019EE48  90ee190090ee190084ee1900
```

### What the five case bodies do [measured]

Each is `mov dword ptr [esi+0x18], N` then `jmp 0x0019EE9C`:

| target | `N` | `IOBitsPerPixel` |
| --- | --- | --- |
| `0x0019EE54` | 0 | `IO_2BitsPerPixel` |
| `0x0019EE60` | 1 | `IO_8BitsPerPixel` |
| `0x0019EE6C` | 2 | `IO_12BitsPerPixel` |
| `0x0019EE78` | 3 | `IO_15BitsPerPixel` |
| `0x0019EE84` | 4 | `IO_24BitsPerPixel` |

The default at `0x0019EE90` is `or byte ptr [esi+0x80], 0x10` then
`jmp 0x0019EF9D` — straight to the epilogue, skipping everything else.

`[esi+0x18]` is `IODisplayInfo.bitsPerPixel`, whose offset 24 is measured by the
D3 probe. `[esi+0x80]` is `modeUnavailableFlag` **[inference]**: the D3 probe
does not include that field, so the name comes from the header layout (see the
field map below), with the total pinned at 136 but not the order of members
between offsets 32 and 135.

The value `0x10` corroborates that name. `IO_DISPLAY_HAS_TRANSFER_TABLE` is also
`0x10`, but that is a `flags` bit and not what this store targets. The header
does enumerate the `modeUnavailableFlag` reason bits
(`src/driverkit-3/driverkit/displayDefs.h:108-116`), and `0x10` there is
`IO_DISPLAY_MODE_OTHER_INVALID`, which is what a depth outside the five handled
ones should set on the default path. **[inference: a match between a measured
constant and a header enumeration, not a measurement of the field's identity]**

The enum values 0–4 are `src/driverkit-3/driverkit/displayDefs.h:41-49`. The
bpp-to-enum mapping matching the enum exactly is strong corroboration that the
table was decoded correctly. **[inference]**

### The padding is inside the 539 bytes, all seven runs [measured]

These seven runs are **part of the compared range**, not inter-function
alignment: five are 3-byte pads between the case bodies (`fn+209`, `+221`,
`+233`, `+245`, `+257`) and two are 1-byte pads (`fn+75` before the table,
`fn+327` before a loop target). Byte parity needs all seven reproduced; none is
exempt from the comparison and none belongs in a mask. Every run ends on a
4-byte-aligned virtual address (`0x0019EDD8`, `0x0019EE60`, `0x0019EE6C`,
`0x0019EE78`, `0x0019EE84`, `0x0019EE90`, `0x0019EED4`). **[measured
arithmetic]** How the reference compiler came to emit them, and whether ours will
emit the same runs, was not established here; the parity test will show it.
The one pad outside the 539 bytes is the trailing byte at `0x0019EFA7`, covered
above.

### The absolute 32-bit operands, and why a pattern mask suffices [measured]

A pattern-only mask is complete only if the bytes that change when the function
moves are exactly the ones the mask names. The 128 instructions of the walk were
checked for every place a 32-bit *absolute* value can hide:

- **One** instruction has a base-less memory operand: the dispatch
  `jmp dword ptr [eax*4 + 0x19edd8]` at `0x0019EDD0`, whose `disp32` is at
  function offsets **71–74**.
- **Zero** other instructions carry an immediate that could be an address. The
  only 4-byte immediates are the `mov dword ptr [esi+disp8], N` stores, with `N`
  in `0`–`4` and `disp8` `0x10`, `0x18`, `0x1c` or `0x60`. Every other immediate
  is one byte: `-2` and `0x1e` in the range check, `0x10`, `8`, `4`, `0`, and
  the fill characters `0x50 0x2d 0x52 0x47 0x42 0x57`.
- There are **no calls**, and every direct branch (`ja`, `jmp`, `je`, `jne`,
  `jl`) is relative and lands inside `[0x0019ED8C, 0x0019EFA7)`, so none carries
  an address that depends on where the function sits.
- The 31 table entries at function offsets **76–199** are the only data that are
  absolute addresses.

So the **only absolute 32-bit operands are the dispatch `disp32` (4 bytes at
71–74) plus the 31 table entries (124 bytes at 76–199)**: 128 bytes to mask, 411
to compare. This is the precondition for Task 2's pattern-only mask. If it were
wrong the failure would be a *false* diff (a moved absolute showing as a
mismatch), not a hidden one. What this check does **not** cover is our build:
that it emits the same instruction shapes is what the parity test measures.

---

## D2: what `0x12854` is

**Answer: a word the kernel itself writes and reads, which by inference holds
the kernel virtual address of the mapped VESA linear frame buffer** — the
measured part and the inferred part are split here and marked where each is
argued below.

- **Measured:** `pmap_bootstrap` writes `0x12854` at `0x0018F1B4`, and it is the
  only writer. `FBAllocateVBEConsole` reads it at function offset +57
  (`0x0019ECF1`) and stores it into `IODisplayInfo.frameBuffer` (offset `0x14`),
  overwriting the physical address `VBEModeInfo2IODisplayInfo` had just stored
  there from the `VBEModeRec`.
- **Inferred:** that the value is specifically a *mapped virtual* address. That
  is the reading under which a pixel-writing console works, and the write's
  arithmetic and the mapping loop that follows it are consistent with it. The
  code that produces the `ecx` being stored was **not** traced back to its
  source: in particular where `[ebp-4]` gets its value before `0x0018F169` was
  not read. So this is not a measurement.

`0x12854` is `kbs+0x1854`, four bytes below the `VBEModeRec` at `kbs+0x1858`.

### Every reference to it in the kernel slice [measured]

Found by decoding `__text` and collecting instructions whose memory operand has
no base and no index register and a displacement in `[0x11000, 0x13000)` — not
by byte-matching, which produced hundreds of false positives.

There are exactly three:

```
0018F1B4  890d54280100      mov  dword ptr [0x12854], ecx     ; in _pmap_bootstrap
0019ECCE  833d5428010000    cmp  dword ptr [0x12854], 0       ; in _FBAllocateVBEConsole
0019ECF1  8b1554280100      mov  edx, dword ptr [0x12854]     ; in _FBAllocateVBEConsole
```

`0x0018F1B4` lies inside `_pmap_bootstrap`, which spans
`0x0018EEE8`–`0x0018F330` (next symbol `_pmap_init`). **One writer, one
reader.**

Neighbouring words, same scan:

| address | | references |
| --- | --- | --- |
| `0x12850` | `kbs+0x1850` | none |
| `0x12854` | `kbs+0x1854` | the three above |
| `0x12858` | `kbs+0x1858` = `VBEModeRec` | `push 0x12858` at `0x0019ECE7` |
| `0x1285C` | `+4` `xResolution` | `cmp word` at `0x0018F16C` and `0x0019ECC4` |
| `0x1285E` | `+6` `yResolution` | `movzx` at `0x0018F181` |
| `0x12860` | `+8` `bytesPerScanline` | `movzx` at `0x0018F17A` |
| `0x1286C` | `+0x14` `frameBuffer` | `mov` at `0x0018F195`, `0x0018F19D` |
| `0x12870`, `0x12874`, `0x12878` | second `VBEModeRec` | none |

### The write, in context [measured]

```
0018F169  895dfc            mov   [ebp-4], ebx              ; [ebp-4] = "virt_cursor" (a name, inferred below)
0018F16C  66833d5c28010000  cmp   word ptr [0x1285c], 0     ; xResolution == 0?
0018F174  0f8421010000      je    0x0018F29B                ;   -> skip the whole block
0018F17A  0fb71560280100    movzx edx, word ptr [0x12860]   ; bytesPerScanline
0018F181  0fb7055e280100    movzx eax, word ptr [0x1285e]   ; yResolution
0018F188  0fafd0            imul  edx, eax                  ; edx = frame-buffer byte size
0018F18B  8b35ec891e00      mov   esi, dword ptr [0x1e89ec] ; _page_mask (exact symbol)
0018F191  89f7              mov   edi, esi
0018F193  f7d7              not   edi                       ; edi = ~page_mask
0018F195  8b1d6c280100      mov   ebx, dword ptr [0x1286c]  ; frameBuffer (physical)
0018F19B  21fb              and   ebx, edi                  ; ebx = trunc_page(fb)
0018F19D  8b0d6c280100      mov   ecx, dword ptr [0x1286c]  ; ecx = fb
0018F1A3  8d044a            lea   eax, [edx + ecx*2]
0018F1A6  29d8              sub   eax, ebx
0018F1A8  01f0              add   eax, esi
0018F1AA  21f8              and   eax, edi                  ; eax = physical end, page-rounded
0018F1AC  8945f0            mov   [ebp-0x10], eax
0018F1AF  034dfc            add   ecx, dword ptr [ebp-4]
0018F1B2  29d9              sub   ecx, ebx
0018F1B4  890d54280100      mov   dword ptr [0x12854], ecx  ; <-- the write
```

So, exactly:

```
[0x12854] = [ebp-4] + fb_phys - trunc_page(fb_phys)          [measured]
[0x12854] = virt_cursor + fb_phys - trunc_page(fb_phys)      [same, with an inferred name]
```

`virt_cursor` is this record's name for `[ebp-4]`; the formula above is
measured, the name is not. This record **infers** that `[ebp-4]` is the virtual
address at which the loop that follows begins mapping, and that the loop maps
physical pages from `trunc_page(fb_phys)` upward while incrementing both
cursors by `0x1000` (`0x0018F1E4`–`0x0018F289`: it indexes the page directory
through `_kernel_pmap` at `0x001F63F0`, calls the nameless static at
`0x0018ECC0` when a directory entry's present bit is clear, writes each PTE at
`0x0018F263`, sets bit 3 of the PTE when the physical page is within
`[0xA0000, 0xFFFFF]`, and reloads `cr3` at `0x0018F28F`). Therefore
`virt_cursor` maps to `trunc_page(fb_phys)`, and `[0x12854]` is the virtual
address that corresponds exactly to `fb_phys`.
**[inference, from the loop's structure; where `[ebp-4]` gets its value before
`0x0018F169` was not traced]**

`_page_mask` (`0x001E89EC`), `_kernel_pmap` (`0x001F63F0`), `_IOMalloc`
(`0x001A5448`) and `_IOFree` (`0x001A5458`) are all exact symbol-table matches.
`0x0018ECC0` is a nameless static: `_pmap_pd_entry` ends at its `ret` at
`0x0018ECBC`, three `nop`s follow, and `0x0018ECC0` opens `55 89 E5`. What that
static does beyond testing a directory entry was not pursued. **[measured]**

`lea eax,[edx+ecx*2]` — note the scale of **2** — makes the physical end
`fb_size + 2*fb_phys - trunc_page(fb_phys)`, i.e. `fb_phys + fb_size` plus the
page offset of `fb_phys` counted a second time. For a page-aligned frame buffer
(the normal case) that is exactly `fb_phys + fb_size`; otherwise it over-maps by
up to one page. It is conservative, not short. The C form that produced it was
not determined. **[measured arithmetic; the "why" is not established]**

### The read, in context [measured]

In `FBAllocateVBEConsole`:

```
0019ECBB  81ec88000000      sub   esp, 0x88                 ; a local IODisplayInfo (136 bytes)
0019ECC4  66833d5c28010000  cmp   word ptr [0x1285c], 0     ; xResolution
0019ECCC  7409              je    0x0019ECD7                ;   -> return NULL
0019ECCE  833d5428010000    cmp   dword ptr [0x12854], 0    ; the word under discussion
0019ECD5  7509              jne   0x0019ECE0
0019ECD7  31c0              xor   eax, eax
0019ECD9  e99f000000        jmp   0x0019ED7D                ; return NULL
0019ECE0  8db578ffffff      lea   esi, [ebp-0x88]
0019ECE6  56                push  esi
0019ECE7  6858280100        push  0x12858                   ; the VBEModeRec
0019ECEC  e89b000000        call  0x0019ED8C                ; VBEModeInfo2IODisplayInfo
0019ECF1  8b1554280100      mov   edx, dword ptr [0x12854]
0019ECF7  89558c            mov   [ebp-0x74], edx           ; <-- info.frameBuffer
```

`[ebp-0x74]` is `[ebp-0x88] + 0x14`, and `offsetof(IODisplayInfo, frameBuffer)`
is 20 = `0x14` (measured under D3). `VBEModeInfo2IODisplayInfo` has just stored
the *physical* `frameBuffer` there from `VBEModeRec+0x14`; the caller
immediately replaces it with the word read from `0x12854`. Measured: that
replacement, and the field it lands in. That the word is a mapped *virtual*
address is what settles the meaning, and it is the inference.
**[inference, but tightly constrained: the value is written into a field whose
name and offset are both measured, and it replaces the physical address of that
same frame buffer]**

### No booter reference to `0x12854` was found [measured absence, with named blind spots]

Scanned the whole 44,848-byte booter for the four-byte little-endian value of
every address in `[0x1284C, 0x12878]`: **no hits for any of them.** The booter
addresses the struct through a pointer instead. `boot+0xDA7C` holds the
`kernBootStruct` pointer, and the booter adds a displacement to it:

```
boot+0x0A5C  8b1d7cda0000  mov ebx, dword ptr [0xda7c]
boot+0x0A62  8dbb70180000  lea edi, [ebx + 0x1870]        ; kbs+0x1870, the 2nd VBEModeRec

boot+0x6CCC  8b3d7cda0000  mov edi, dword ptr [0xda7c]
boot+0x6CD2  81c770180000  add edi, 0x1870
boot+0x6CFC  0540180000    add eax, 0x1840

boot+0x6D9A  8b3d7cda0000  mov edi, dword ptr [0xda7c]
boot+0x6DA0  81c758180000  add edi, 0x1858                ; kbs+0x1858, the 1st VBEModeRec
```

A sweep for every 4-byte value in `[0x1800, 0x1900)` anywhere in the booter
finds `0x1858` once, `0x1870` twice, `0x1840` once, and **`0x1854` not at all.**
Those four hits (three distinct values) are the positive controls: they are the disassembled sites
above, so the method finds a reference when one exists.
The booter is the VBE-aware one — it carries the strings `Usable VBE modes:`
(`boot+39254`), `VBE mode %d not supported.` (`boot+42105`), `Using VBE Mode
%d.` (`boot+42133`), `No usable VBE mode. Reverting to VGA.` (`boot+42153`).

**What both sweeps cannot see.** Both match **4-byte** little-endian values
only. The booter can contain real-mode code (this record did not delineate the
16-bit and 32-bit regions of the 44,848-byte headerless image), and a 16-bit
instruction carries a 2-byte immediate: `mov di, 1854h` would be `BF 54 18`.
A **2-byte** little-endian scan, run after the 4-byte sweeps, for `54 18` across the same
44,848 bytes (SHA-256 `925D35B6…75CBCE`) found **0 hits**, against roughly 0.7
expected if the bytes were uniformly random. Its positive controls, the same
scan for the other three values: `58 18` at `boot+0x6DA2` (1 hit), `70 18` at
`boot+0x0A64` and `boot+0x6CD4` (2), `40 18` at `boot+0x6CFD` (1). Each sits
exactly at the `imm32` of a disassembled site above, so the 2-byte scan finds
nothing the 4-byte scan did not, and no 16-bit-immediate form of any of the
four values exists in the booter. **[measured]**

Still **not** covered by any scan here, and not claimed: an address split into
a segment and an offset; a value computed at run time in a register and then
dereferenced; a value carried in data. A scan can only ever show that a
constant is absent from the bytes.

**The argument that does not depend on any scan.** A booter cannot publish a
kernel virtual address that `pmap_bootstrap` has not yet chosen. The write is,
measured, `[0x12854] = [ebp-4] + fb_phys - trunc_page(fb_phys)`
(`0x0018F1AF`–`0x0018F1B4`): an expression over `pmap_bootstrap`'s own stack
local `[ebp-4]` and the physical frame-buffer address, in a function whose page
table writes (`0x0018F263`, above) are what would give such an address meaning.
`pmap_bootstrap` belongs to the *kernel*, which the booter loads and then hands
control to, so the booter is finished before that function runs. The booter has
no way to know a value that function computes, short of reproducing the
kernel's address-space setup, and it cannot create the mapping. So even a
booter whose stores were invisible to every scan could not have supplied this
particular value, whatever the sweeps' blind spots are.
**[inference: the formula and the writer's location are measured; that
`[ebp-4]` is a kernel-side quantity is inferred, its source not having been
traced]**

### Correction: `0x12854` is not the booter's to write

The design spec's D2 row says of `0x12854` that "Spec 3 has to write it." The
evidence says otherwise: **`0x12854` is kernel-private.** The booter writes the
`VBEModeRec` at `kbs+0x1858`; the *kernel's* `pmap_bootstrap` writes the word at
`kbs+0x1854` **[measured: the kernel has the one writer, and the booter has no
reference found above]**, and by the inference under D2 that word is the
virtual address of the frame buffer it maps. The word lives inside
`_reserved[7500]` (offsets 908–8408 of Rhapsody's `KERNBOOTSTRUCT`), i.e. in
slack, used as a fixed low-memory letterbox from very-early VM setup to console
allocation. **[inference from the one-writer/one-reader split above]**

Task 3 therefore does not need the booter to supply this word, and spec 3's
booter work does not either — but *something on our side must map the frame
buffer and set it*, or `FBAllocateVBEConsole`'s second guard never passes.
Whether that belongs in our `pmap_bootstrap` or elsewhere is not settled here.

### The zeroing that makes the guards meaningful [measured]

`getKernBootStruct()` (`src/boot-2/i386/libsaio/bootstruct.c:79`) does
`bzero((char *)kernBootStruct, sizeof(*kernBootStruct))` over the whole struct,
and `src/boot-2/i386/boot2/boot.c:414` calls it early, before any mode is
chosen. Both guarded words are therefore zero unless something deliberately
sets them. This is what the two `!= 0` guards rely on; it is a supporting fact,
not a hazard.

---

## D3: `sizeof(ConsoleRep)` here versus the reference's 228

**Answer: identical — 228 bytes. No divergence.**

### The reference's number [measured]

Twice, independently:

```
0019ED14  68e4000000    push 0xe4          ; 228, IOMalloc for cso->priv
0019ED19  e82a670000    call 0x001A5448    ; _IOMalloc
```

and in the function immediately after `VBEModeInfo2IODisplayInfo`, which
`FBAllocateVBEConsole` installs in the `Free` slot:

```
0019EFA8  55 89e5 53     push ebp; mov ebp,esp; push ebx
0019EFAC  8b5d08         mov  ebx, [ebp+8]
0019EFAF  68e4000000     push 0xe4          ; 228
0019EFB4  8b531c         mov  edx, [ebx+0x1c]   ; ->priv
0019EFB7  52 e89b640000  push edx; call 0x001A5458   ; _IOFree
0019EFBD  6a20           push 0x20          ; 32
0019EFBF  53 e893640000  push ebx; call 0x001A5458   ; _IOFree
```

### Our number, measured on the guest, not by hand [measured]

Per the brief, not computed by hand. A probe `#include`s
`src/kernel-7/bsd/dev/i386/FBConsole.c` itself — so the real `ConsoleRep`
definition is used, not a transcription — appends an initialised
`unsigned long[]` of `sizeof`/`offsetof` values between two sentinels, and is
compiled with the **exact** command line the kernel build uses for
`FBConsole.o`, recovered with `gnumake -n FBConsole.o` in
`BUILD/RELEASE_I386`, including `-arch i386`. The guest is PPC, so the object
was not run: it was copied back and the values read out of its `__data`.

Probe object: `Mach-O object i386`, `cputype` 7, 53,288 bytes, SHA-256
`1599B6C2E37FAE2C85C685AE44A99448AD0111E8CA831F3FEFC0975845971DEF`. Sentinels
`0xC0DEF00D` and `0x0DF00DED` both present and in the right places.

| expression | value | reference's corresponding number |
| --- | --- | --- |
| `sizeof(ConsoleRep)` | **228** | `IOMalloc(0xE4)` / `IOFree(…, 0xE4)` — **same** |
| `offsetof(ConsoleRep, window_type)` | 0 | `mov [priv+0], 0` at `0x0019ED75` |
| `offsetof(ConsoleRep, display)` | **4** | `add edi,4` at `0x0019ED67` — **same** |
| `sizeof(IODisplayInfo)` | **136** | `sub esp,0x88`; `rep movsd` `ecx=0x22` = 34 dwords — **same** |
| `sizeof(IOConsoleInfo)` | **32** | `IOMalloc(0x20)` — **same** |
| `offsetof(IOConsoleInfo, priv)` | **28** | `[ebx+0x1c]` — **same** |
| `offsetof(IODisplayInfo, width)` | 0 | `mov [esi], edi` |
| `offsetof(IODisplayInfo, height)` | 4 | `mov [esi+4], edi` |
| `offsetof(IODisplayInfo, totalWidth)` | 8 | `mov [esi+8], edi` |
| `offsetof(IODisplayInfo, rowBytes)` | 12 | `mov [esi+0xc], edi` |
| `offsetof(IODisplayInfo, frameBuffer)` | 20 | `mov [esi+0x14], edi` |
| `offsetof(IODisplayInfo, bitsPerPixel)` | 24 | `mov [esi+0x18], 0..4` |
| `offsetof(IODisplayInfo, colorSpace)` | 28 | `mov [esi+0x1c], 1 or 2` |
| `SCM_UNINIT` | 0 | the `0` stored at `priv+0` |
| `sizeof(ScreenMode)` | 4 | — |

Every one of the reference's constants is reproduced by our own headers. The
design spec's §4 claim that our `IOConsoleInfo` is "exactly 32 bytes" is
confirmed by compiler measurement rather than by counting the seven pointers.

---

## D4: do both functions live in the FBConsole translation unit

**Answer: yes** — on the strength of link-order adjacency, with the reasoning
marked below, because the symbol table cannot prove it directly.

### What is measured

`FBAllocateVBEConsole` stores seven function pointers into the freshly allocated
`IOConsoleInfo`, matching our `IOConsoleInfo`'s seven slots in order
(`src/kernel-7/bsd/dev/i386/ConsoleSupport.h:74-92`):

```
0019ED34  mov [ebx],     0x0019EFA8    ; Free
0019ED3A  mov [ebx+4],   0x0019DF7C    ; Init
0019ED41  mov [ebx+8],   0x0019EFCC    ; Restore
0019ED48  mov [ebx+0xc], 0x0019E23C    ; DrawRect
0019ED4F  mov [ebx+0x10],0x0019E7CC    ; EraseRect
0019ED56  mov [ebx+0x14],0x0019F050    ; PutC
0019ED5D  mov [ebx+0x18],0x0019F068    ; GetSize
```

All seven are nameless (no symbol-table entry), and they span
`0x0019DF7C`–`0x0019F068`. Both target functions sit strictly inside that
span:

```
0x0019DF7C  Init            <- FBConsole console-op
0x0019E23C  DrawRect        <- FBConsole console-op
0x0019E7CC  EraseRect       <- FBConsole console-op
0x0019EC24  _FBAllocateConsole          (named)
0x0019ECB8  _FBAllocateVBEConsole       (named)
0x0019ED8C  _VBEModeInfo2IODisplayInfo  (named)
0x0019EFA8  Free            <- FBConsole console-op, and the very next function
0x0019EFCC  Restore         <- FBConsole console-op
0x0019F050  PutC            <- FBConsole console-op
0x0019F068  GetSize         <- FBConsole console-op
```

The function at `0x0019EFA8` — the one that starts one padding byte after
`VBEModeInfo2IODisplayInfo` ends — frees a 228-byte `priv` and a 32-byte
`IOConsoleInfo`, i.e. it is FBConsole's own `Free`. **[measured]**

### The inference

`ld` lays each object file's `__text` contributions out contiguously. Both
target functions are *interleaved between* FBConsole's own console operations —
bracketed by `EraseRect` before and `Free` immediately after — so they are
contributions of the same object file. Taking that object file to be
`FBConsole.o`, compiled from `FBConsole.c`, both functions belong in
`FBConsole.c`. **[inference]**

Two caveats, stated rather than hidden:

- The step from "same `.o`" to "same `.c`" assumes the `.o` is not built from
  several sources via `#include`. Nothing observed suggests it is, and
  `FBConsole.c` is a single 39,380-byte source in our tree, but the binary
  cannot rule it out.
- No source-file name survives in the binary (no `N_STAB`, no `__DWARF`), so
  this cannot be upgraded to a measurement from this artifact alone.

The plan's §"File Structure" note said the adjacency "suggests one translation
unit" and asked D4 to confirm or refute before Task 2 writes anything. It is
confirmed as far as the binary can confirm it: **put both in `FBConsole.c`.**

---

## D5: does the reference's `ConsoleRep` put `display` at offset 4

**Answer: yes.**

Reference **[measured]**:

```
0019ED64  8b7b1c        mov  edi, [ebx+0x1c]   ; cso->priv
0019ED67  83c704        add  edi, 4            ; priv + 4
0019ED6A  fc            cld
0019ED6B  b922000000    mov  ecx, 0x22         ; 34 dwords
0019ED70  f3a5          rep movsd              ; 136 bytes from the local IODisplayInfo
0019ED72  8b431c        mov  eax, [ebx+0x1c]
0019ED75  c70000000000  mov  dword ptr [eax], 0  ; priv + 0 = 0
```

136 bytes land at `priv+4`; `priv+0` is a separate 4-byte field set to zero.

Ours **[measured, same probe as D3]**: `offsetof(ConsoleRep, display)` = **4**,
`offsetof(ConsoleRep, window_type)` = 0, `sizeof(IODisplayInfo)` = 136,
`SCM_UNINIT` = 0.

So the reference's `rep movsd` is our `((ConsolePtr)cso->priv)->display = *info`
and its `mov [priv+0], 0` is our `window_type = SCM_UNINIT`. The two layouts
agree field for field at both offsets. Our `FBAllocateConsole`
(`FBConsole.c:1354`) assigning `((ConsolePtr)cso->priv)->display` is the same
store.

---

## The full `IODisplayInfo` field map (for Task 2)

Task 2 has to write `VBEModeInfo2IODisplayInfo` to byte parity, so every store
it makes is listed here with the field it targets. The **store offsets** are all
measured: they are the `[esi+disp]` destinations in the disassembly (the
`pixelEncoding` fills are indexed stores at `[reg+esi+0x20]`), and every
instruction that writes through the output pointer is in the list (`esi` is
loaded once from `[ebp+0xc]` and never copied). What is measured about the
**field names** differs by offset:

- **Offsets 0, 4, 8, 12, 20, 24 and 28** (`width`, `height`, `totalWidth`,
  `rowBytes`, `frameBuffer`, `bitsPerPixel`, `colorSpace`) are named from the D3
  probe **[measured]**.
- **Offset 16 (`refreshRate`) is not in the probe output** and is
  **header-inferred**, like 32 and above. It is forced by its two measured
  neighbours, `rowBytes` at 12 and `frameBuffer` at 20 (one `int` slot between),
  but the *name* comes from the header's member order. **[inference]**
- **Offsets 32 and above** are computed from
  `src/driverkit-3/driverkit/displayDefs.h:124-170` with `IOPixelEncoding` =
  `char[64]` (`IO_MAX_PIXEL_BITS` 64, line 118) and check out against
  `sizeof(IODisplayInfo)` = 136. **[inference, but the total is pinned]** The
  total being pinned does not pin the *order* of members between 32 and 135, and
  the reference's own struct definition was not read.

| offset | field | what the reference stores |
| --- | --- | --- |
| 0 | `width` | `VBEModeRec+4` `xResolution`, zero-extended |
| 4 | `height` | `VBEModeRec+6` `yResolution` |
| 8 | `totalWidth` | `VBEModeRec+4` `xResolution` again |
| 12 | `rowBytes` | `VBEModeRec+8` `bytesPerScanline` |
| 16 | `refreshRate` **[name inferred]** | literal `0` |
| 20 | `frameBuffer` | `VBEModeRec+0x14`, a dword |
| 24 | `bitsPerPixel` | `0`–`4` from the jump table; untouched on the default path |
| 28 | `colorSpace` | `2` (`IO_RGBColorSpace`) if `VBEModeRec+2 & 8`, else `1` (`IO_OneIsWhiteColorSpace`) |
| 32 | `pixelEncoding` **[name inferred]** | `char[64]`, filled byte-wise — see below |
| 96 (`0x60`) | `flags` **[name inferred]** | literal `2` |
| 100 (`0x64`) | `parameters` **[name inferred]** | `VBEModeRec+0`, a word, zero-extended |
| 104 (`0x68`) | `memorySize` **[name inferred]** | `yResolution * bytesPerScanline` |
| 108 (`0x6C`) | `scanRate` **[name inferred]** | **never stored** |
| 112 (`0x70`) | `_reserved1` **[name inferred]** | **never stored** |
| 116 (`0x74`) | `dotClockRate` **[name inferred]** | **never stored** |
| 120 (`0x78`) | `screenWidth` **[name inferred]** | **never stored** |
| 124 (`0x7C`) | `screenHeight` **[name inferred]** | **never stored** |
| 128 (`0x80`) | `modeUnavailableFlag` **[name inferred]** | sets bit `0x10` (`or byte ptr [esi+0x80], 0x10`) on the default path only |
| 132 (`0x84`) | `_reserved[0]` **[name inferred]** | **never stored** |

The `never stored` rows are **[measured]**: no instruction in the function writes
to `[esi+0x6C]` through `[esi+0x7F]` or to `[esi+0x84]`. The field names on
those rows and on offset 128 are the header's, applied by layout.

Offset 128 is the one to be careful with. The store is measured; that the field
at 128 is `modeUnavailableFlag` is inferred from the header layout, and setting a
bit in a field named "…Flag" would be odd if the name were wrong. The value
corroborates the name (`0x10` is `IO_DISPLAY_MODE_OTHER_INVALID`, see D1), but
that is a match against the header and not a measurement of the reference's
struct.

The stores above leave `scanRate` through `screenHeight` and `_reserved[0]`
untouched, and the caller does not initialise its local `IODisplayInfo` between
`sub esp, 0x88` at `0x0019ECBB` and the call at `0x0019ECEC` — the only stores in
that stretch are `push`es. **[measured, from a linear listing of
`0x0019ECB8`–`0x0019ED8B`]** So in the reference those 24 bytes, the unfilled
tail of `pixelEncoding`, and all of `modeUnavailableFlag` (except bit `0x10` on
the default path) are whatever was on the stack when `rep movsd` copied the
struct into `priv+4`. Whether that matters to Task 2 or Task 3 is theirs to
decide; it is recorded so it is not rediscovered.

`refreshRate = 0` at `0x0019EDB3` is why spec 1's driver hardcodes `Refresh:0Hz`
— the kernel never sets one.

`memorySize` is `yResolution * bytesPerScanline` (`0x0019EF8F`–`0x0019EF9A`),
which is the correct product. It is **not** the `bytesPerScanLine * XResolution`
defect spec 1 found in the driver; that defect is the driver's own and does not
appear here.

`pixelEncoding` (`0x0019EE9C`–`0x0019EF80`) **[measured]**:

- `test byte ptr [ebx+2], 8` — `VBEModeRec+2`, the VBE mode-attributes word,
  bit 3. Set means colour.
- **Not set:** `colorSpace = 1`, then fill `bitsPerPixel` bytes with `'W'`
  (`0x57`).
- **Set:** `colorSpace = 2`; then if `VBEModeRec+0x0B == 4` fill `bitsPerPixel`
  bytes with `'P'` (`0x50`); otherwise fill `bitsPerPixel` bytes with `'-'`
  (`0x2D`) and overlay, each written from the high end downward,
  `'R'` (`0x52`) `VBEModeRec+0x0C` times starting at
  `bitsPerPixel - VBEModeRec+0x0D - 1`, then `'G'` (`0x47`) using
  `+0x0E` / `+0x0F`, then `'B'` (`0x42`) using `+0x10` / `+0x11`.

### `VBEModeRec` fields this function uses

Spec 1's D1 established `+4` `xResolution`, `+6` `yResolution`, `+8`
`bytesPerScanline`, `+0x0A` `bitsPerPixel`, `+0x14` `frameBuffer`, 24 bytes
total. This function's reads confirm all five and add six more **[measured
reads; the VBE names are inference from the VBE 2.0 `ModeInfoBlock`, whose
`BitsPerPixel` and `MemoryModel` are likewise adjacent bytes]**:

| offset | width | used as |
| --- | --- | --- |
| `+0` | word | stored into `parameters` — the mode number |
| `+2` | word | attributes; bit 3 tested for colour |
| `+0x0B` | byte | memory model; `4` selects the `'P'` fill |
| `+0x0C`, `+0x0D` | bytes | red mask size, red field position |
| `+0x0E`, `+0x0F` | bytes | green mask size, green field position |
| `+0x10`, `+0x11` | bytes | blue mask size, blue field position |

---

## Not determinable, and what was ruled out

- **The return type of `VBEModeInfo2IODisplayInfo`.** Still the `void` spec 1
  inferred. This slice adds nothing: the function writes `eax` only as scratch
  (`movzx eax, byte ptr [ebx+0xa]` and the pixel-encoding loops), and the one
  call site at `0x0019ECEC` ignores `eax` — but the caller reloading `edx` from
  `0x12854` immediately afterwards would look identical either way.
  **[inference, unchanged]**
- **The C source form of `lea eax,[edx+ecx*2]`** in `pmap_bootstrap`. The
  arithmetic is measured; the expression that produced the `*2` is not
  established.
- **Whether `0x12854` has any indirect reader or writer.** The scan covers
  absolute-addressed operands in `__text`, which is the only code section. A
  reference formed at runtime (a pointer computed into the struct and then
  offset) would not be caught. Nothing in the three sites found suggests one,
  and the write/read pair is a complete producer/consumer story on its own, but
  the method cannot exclude it.
- **Whether the booter references `0x12854` by any form the scans cannot see.**
  The 4-byte and 2-byte little-endian scans found nothing, but an address split
  into segment and offset, computed at run time, or carried in data would not
  show up in either. The record does not close this by scanning; it rests on the
  argument under D2 that a booter cannot know the value, which is itself an
  inference (the source of `[ebp-4]` was not traced).
- **`D4` to the level of a measurement.** See the two caveats under D4.
- **What `flags = 2` is for.** `2` is
  `IO_DISPLAY_NEEDS_SOFTWARE_GAMMA_CORRECTION`
  (`src/driverkit-3/driverkit/displayDefs.h:177`). The store is measured; why a
  VESA linear frame buffer would want it is not established here.

## Corrections to the plan and design spec

Recorded so they are not re-derived, and so nothing downstream inherits them:

1. **The dispatch is at function offset 68, not 69**; its `imm32` is at 71.
   Task 2's harness must mask bytes 71–74, and the 31 table entries at 76–199.
   Those 128 bytes are the only absolute 32-bit operands (D1, "The absolute
   32-bit operands").
2. **The i386 slice has no relocation table** — `nreloc = 0` everywhere,
   `MH_EXECUTE`, no `LC_DYSYMTAB`. The design spec's §6 instruction to reuse
   scattered-relocation-aware masking does not apply.
3. **`0x12854` is written by the kernel, not the booter** **[measured: the
   kernel's `pmap_bootstrap` is the one writer, and no reference to it was
   found in the booter by a 4-byte or a 2-byte scan]**. The design spec's D2 row
   ("Spec 3 has to write it") misplaces the responsibility **[inference for the
   "not the booter" half: it also rests on the argument under D2 that a booter
   cannot know the value]**.

## Reproducing these measurements

```bash
# Both paths are machine-local inputs, not repo paths: the tar is not in the
# repo, and the venv lives beside it on the recording machine.
VENVPY=${VENVPY:-D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe}
PATCH=${PATCH:?set PATCH to your copy of OS42MachUserPatch4.tar}

# fat kernel, then slice 1 (offset 835584, length 1117920) -> $KREF
$VENVPY vm/extract-os42-patch.py "$PATCH" <dest> ./mach_kernel
# the booter
$VENVPY vm/extract-os42-patch.py "$PATCH" <dest> ./usr/standalone/i386/boot

# profile
BINRECON_REFERENCE=$KREF BINRECON_REBUILT=<a copy of $KREF> \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon validate \
    --profile tools/binrecon/profiles/os42-kernel-vbe.json
```

Disassembly used `capstone` 5.0.6 in `.venv-binrecon`, `CS_ARCH_X86` /
`CS_MODE_32`, reading at `file offset = va - 0x100000`. The D1 extent came from
a recursive walk seeded with the entry and all 31 table targets; the D2 scan
decoded `__text` linearly (restarting past undecodable bytes) and kept operands
with `mem.base == 0 && mem.index == 0 && 0x11000 <= mem.disp < 0x13000`.

Verify your copy of the patch before trusting any offset here: the extracted
fat kernel must hash to `6D602AAD…20EE` and the booter to `925D35B6…75CBCE`
(full values in the conventions above). The recording used a copy from the
author's Downloads directory; nothing about that path matters.

The booter absence checks are plain byte searches over the extracted 44,848-byte
`boot`: a 4-byte little-endian search for each value in `[0x1800, 0x1900)` and
in `[0x1284C, 0x12878]`, and a 2-byte little-endian search for `54 18` with
`58 18`, `70 18` and `40 18` as positive controls. The D1 mask-completeness
check reran the same recursive decode and listed, per instruction, every
memory operand with `base == 0`, every immediate, and every branch. The
`IODisplayInfo` store list came from filtering that decode, and the
`FBAllocateVBEConsole` prefix from a linear listing of
`0x0019ECB8`–`0x0019ED8B`.

The D3/D5 probe compiled on the Rhapsody guest in
`/build/src/kernel-7/BUILD/RELEASE_I386` with the line from
`gnumake -n FBConsole.o`, substituting a probe source that `#include`s
`FBConsole.c` and appends the sentinel-wrapped `unsigned long[]`; the resulting
`-arch i386` object was copied back and its `__data` read.
