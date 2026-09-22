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

**What the four hits are, from spec 1's record [measured there, by
disassembly].** None of them reaches `kbs+0x1854`. Spec 1's record
(`src/drivers-i386/video/drvVBE20DisplayDriver/reconstruction/divergences.md`,
D1, "What fills that memory is the booter, and the stores are located")
locates the booter's stores into this region: one leaf mode-record writer at
`boot+27556..27702`, which stores only at `+0x00..+0x11` and `+0x14` of its
destination record, called at `boot+27974` with `edi` = `kbs+0x1870` stepped
by 24 and at `boot+28263` with `edi` = `kbs+0x1858`. Against the sweep:
`0x1870` at `boot+0x6CD2` (27858) and `0x1858` at `boot+0x6DA0` (28064) are
those two destination bases; `0x1870` at `boot+0x0A62` (2658) is in the routine
at `boot+2652..2857`, which spec 1's record found stores nothing into the
region; and `0x1840` at `boot+0x6CFC` (27900) is the mode enumerator's loop
bound, `edi - (base + 0x1840)` compared against `0x897`. That is a subtracted
operand, not a store base, so `0x1840 + 0x14 = 0x1854` describes no store.
This accounts for every constant the sweep found; it does not close the blind
spots named below, which are about addresses no sweep can see.

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
evidence says otherwise: **`0x12854` is kernel-private** **[inference: from
the one kernel writer, measured, and an absence in the booter that is measured
only up to the blind spots named above]**. The booter writes the
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

Per the plan (Task 1 Step 5, D3), not computed by hand. A probe `#include`s
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

---

## Task 2: writing `VBEModeInfo2IODisplayInfo`

**Result: byte-identical.** 411 of the 539 bytes compare equal; the other 128
are the masked absolute operands, and those agree too once expressed relative
to the function entry.

### What was compared, and against what

| | reference | ours |
| --- | --- | --- |
| binary | i386 slice, `33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890` | `BUILD/RELEASE_I386/mach_kernel`, 1,486,224 bytes, `605F6A3940464D3C2E40541A0ECA79480F88CDA1932B552EC7BD281748DD27C1` |
| `_VBEModeInfo2IODisplayInfo` | `0x0019ED8C` | `0x001E8804` (`nm`: `T`, defined and external) |
| entry alignment | `≡ 0 mod 4` | `≡ 0 mod 4` |
| 539-byte SHA-256 | `BDDC94F5BF87EB434DCC0E72650CF9975528F2A1E7FE67CF1AC65D9079CD2B21` (Task 1's value, re-confirmed) | `CFA460B379ABBE1E3B2DC9A808BCE5C1E74416327EBEEF4EA9CFE9AF6812C596` |

Both reference hashes are given in full above because the truncated forms they
first appeared in (`33469393…F14890`, `BDDC94F5…2B21`) are not checkable. The
full value of the slice hash is also in the "Conventions" section at the top of
this file, and of the 539-byte extent hash under D1.

The two function hashes differ **only** because the 128 masked bytes hold
different absolute addresses; see the mask check below. **[measured]**

**Where that kernel is, and an earlier hash you may run into.** It lives on the
guest at `/build/src/kernel-7/BUILD/RELEASE_I386/mach_kernel` (equivalently
`/build/source/src/kernel-7/…`; `/build/source/src` is a symlink). It is **not**
at `vm/install/mach_kernel`: `vm/build-i386-kernel-ahci.sh` never reaches its
staging step — under the guest's `/bin/sh` it stops at the very first
`command -v` (item 2 below), and under `/bin/bash`, which does have
`command -v`, it then stops at the AHCI tests (item 4). Either way nothing is
ever staged there. Pulling the kernel over SSH needs the legacy options from
`vm/rhap-remote.ps1` (`KexAlgorithms=diffie-hellman-group1-sha1`,
`HostKeyAlgorithms=ssh-dss`, `Ciphers=3des-cbc`, `MACs=hmac-sha1`,
`PubkeyAuthentication=no`).

An earlier draft of this table carried
`AC2213A3F4EBF7429708BD4B66DEDD1D960346CE97B7FEB12B7A2FB57245010F`, which is a
**real but superseded artifact**: the kernel built before the source comments
were finalised, differing from the one above only in the version string's
embedded build timestamp and in comments, neither of which generates code. The
539-byte comparison was re-run against both and both MATCH, 411/411.
**[measured at the time]** That artifact no longer exists: a `find /` for
`mach_kernel*` on the guest returns only the PPC `/mach_kernel` and its two
copies, `/build/pull/kern/…`, and the `RELEASE_I386` pair, and no local copy
was kept either. Nothing below can be re-measured against it. **[measured
absence, Task 3]**

### The BSD `sum` value, and which artifact it belongs to (re-measured, Task 3)

The guest has no `sha256`, so the cheap post-pull integrity check is BSD `sum`.
The value this record originally gave, `17135 1452`, was printed without saying
which of the two kernels produced it. Re-measured, it belongs to the **current**
one:

| artifact | size | SHA-256 | BSD `sum` |
| --- | --- | --- | --- |
| `/build/src/kernel-7/BUILD/RELEASE_I386/mach_kernel`, as it stands | 1,486,224 | `605F6A3940464D3C2E40541A0ECA79480F88CDA1932B552EC7BD281748DD27C1` | **`17135 1452`** |
| the superseded `AC2213A3…010F` | — | `AC2213A3F4EBF7429708BD4B66DEDD1D960346CE97B7FEB12B7A2FB57245010F` | **not measurable** — the artifact is gone (above) |

Method, so the two columns are pinned to the same bytes **[measured]**: `sum`
was run on the guest (`17135 1452`); the file was then pulled with `scp` and
hashed locally (`605F6A39…27C1`, 1,486,224 bytes); and the historic 16-bit
rotate-and-add checksum was reimplemented over the *pulled* bytes, reproducing
`17135 1452`. So the `sum` value and the SHA-256 are two measurements of one
byte stream, not two measurements that happen to sit in the same table row. The
second field, `1452`, is only `ceil(1486224 / 1024)`, the 1 KiB block count; the
discriminating half is `17135`.

**This establishes the attribution: `17135 1452` belongs to the current kernel**,
`605F6A39…27C1`. The guest's `sum` and a local reimplementation over the pulled
bytes both produce it from that one byte stream. It does **not** establish the
provenance. A 16-bit sum can collide, so these measurements cannot show that
Task 2 did not run `sum` on the superseded build and happen to obtain the same
value; how Task 2 came by the number is not recoverable from here. What the
superseded kernel's own `sum` was is now unknowable. No claim is made about
either.

### The 539-byte extent hashes, re-measured (Task 3)

Both were recomputed from the artifacts as they stand, with the same
`compare_kvbe.py` extraction the Task 2 comparison used **[measured]**:

| | entry | 539-byte SHA-256 |
| --- | --- | --- |
| reference i386 slice `33469393…F14890` | `0x0019ED8C` | `BDDC94F5BF87EB434DCC0E72650CF9975528F2A1E7FE67CF1AC65D9079CD2B21` |
| ours, `605F6A39…27C1` | `0x001E8804` | `CFA460B379ABBE1E3B2DC9A808BCE5C1E74416327EBEEF4EA9CFE9AF6812C596` |

Whether the superseded `AC2213A3…010F` also hashed its extent to
`CFA460B3…C596` **cannot be measured** — the artifact is gone. It probably did:
the two builds differ only in a fixed-width build-timestamp string and in
comments, so `__TEXT` keeps its size, the function keeps its address, and the
128 masked bytes (absolute addresses into the function itself) keep their
values. **[inference; the artifact needed to check it no longer exists]**

Our compiler is Apple `cc-783.1`, gcc 2.7.2.1 — the same family as the
reference's — invoked with the kernel build's own line for `FBConsole.o`
(`-static -nostdinc -nostdlib -traditional-cpp -g -O3 -fno-omit-frame-pointer
-arch i386 -fwritable-strings -fno-common -fpascal-strings`, plus the kernel's
`-D` set). **[measured: recovered with `gnumake -n FBConsole.o`]**

### The mask, and why masking does not hide a wrong answer

`compare_kvbe.py` (harness, deliberately not committed) masks by pattern, as
Task 1 requires — there are no relocations in either binary:

- the dispatch `disp32` at function offsets **71–74**, after asserting that
  `ff 24 85` really is at offset **68** in *both* binaries, so the mask cannot
  drift onto the wrong bytes;
- the **31** jump-table entries at offsets **76–199**.

Masking those 128 bytes would by itself let a build with a *wrong* jump table
compare clean. So the harness additionally re-expresses both masked regions
relative to the function entry and compares them:

```
masked region agrees: dispatch -> fn+76, 31 table targets identical
```

All 31 relative targets match entry for entry — `[200, 260, 260, 260, 260,
260, 212, …, 248]`, the table Task 1 tabulated. **[measured]**

The harness was negative-tested with three mutations of our own object, each
correctly reported: a compared code byte (`fn+43`), a jump-table entry (caught
only by the relative check), and an interior pad byte (`fn+209`). The pads are
**not** masked and do compare. **[measured]**

### All seven interior pad runs reproduced, and why

Task 1 left open "whether ours will emit the same runs". It does — all seven,
with no source-side effort. The rule the reference's padding follows, and ours
reproduces, is gcc 2.x's i386 4-byte code alignment applied in exactly two
places **[inference from the addresses; the parity result is the measurement]**:

- **after a barrier** (an unconditional `jmp`): the table at `0x0019EDD8`, the
  case bodies at `0x0019EE60`/`EE6C`/`EE78`/`EE84`/`EE90`, and `0x0019EED4`;
- **at a loop top**: `0x0019EEC0`, `0x0019EF00`, `0x0019EF28`, `0x0019EF50`,
  `0x0019EF74`.

Labels reached only by falling through get no alignment, which is why
`0x0019EF12`, `0x0019EF3A` and `0x0019EF82` sit at `≡ 2 mod 4` with no pad
before them. **[measured: those addresses, and the absence of a pad]**

This is a property of the compiler and the function's own offsets, not of the
source text, so it holds only while our entry stays 4-aligned — which the
harness checks and reports.

### The one source shape that is codegen-determined

Everything else in the function follows from the disassembly directly. One
construct does not, and it is called out on the line in `FBConsole.c`:

```c
lsb = mode->bitsPerPixel - mode->redFieldPosition - 1;
for (i = 0; i < mode->redMaskSize; i++)
    info->pixelEncoding[lsb - i] = IO_SampleTypeRed;
```

The invariant has to be **its own statement ahead of the loop**. The reference
computes it before the mask-size guard (`0x0019EEEA`–`EEF6`, and likewise at
`EF12` and `EF3A`) and reloads only the mask size per iteration.

**The rejected alternative, measured rather than reasoned:** folding the
expression into the subscript —
`info->pixelEncoding[mode->bitsPerPixel - mode-><c>FieldPosition - 1 - i]` —
compiles to a function of the **same 539 bytes** but with **114 differing
bytes**. gcc 2.7.2.1 then sinks the computation past the guard and reloads
`bitsPerPixel` and the field position inside the loop body, and switches the
index register from `edx` to `ecx`. **[measured: both variants compiled with
the kernel's own command line and compared with the harness; the two objects'
`__TEXT` sizes are identical at 11,217 bytes, so size alone would not have
caught this]**

An earlier draft of that source comment asserted the alternative cost "3 extra
instructions per loop, 9 for the three loops". That was reasoning, not
measurement, and it was **wrong** — the cost is zero bytes and 114 changed
ones. Recorded because it is the same unmarked-inference failure this project
has now hit four times.

### Reference behaviours reproduced deliberately

Both are labelled in `FBConsole.c` so a later reader does not "repair" them:

- **`refreshRate = 0`** (`0x0019EDB3`). The mode record carries no refresh
  rate. This is the reason spec 1's driver prints `Refresh:0Hz`. **[measured]**
- **`pixelEncoding` is never terminated.** Only `bitsPerPixel` bytes are
  written and no `'\0'` follows, although `displayDefs.h` documents the array
  as NUL-terminated and says `strlen` of it returns the pixel depth. Combined
  with the 4.2 caller handing in an uninitialized stack `IODisplayInfo`
  (recorded under the field map above), the tail is stack residue. Adding a
  terminator would add bytes and change behaviour. **[measured: no store to
  `[esi+0x20+bitsPerPixel]` exists]**

A third, **not** reproduced because it is not present here: the
`bytesPerScanLine * XResolution` transposition spec 1 found in the driver. This
function's `memorySize` is `yResolution * bytesPerScanline`
(`0x0019EF8F`–`EF9A`), which is correct. **[measured]**

### `info->parameters` takes a cast

`IODisplayInfo.parameters` is `void *`; the reference stores the 16-bit mode
number into it zero-extended (`movzx edi, word ptr [ebx]` / `mov [esi+0x64],
edi`). `info->parameters = (void *)mode->modeNumber;` reproduces that and draws
one warning, `cast to pointer from integer of different size`, which is
expected and harmless. **[measured]**

### Guest environment, as found — none of this is a source problem

Recorded so the next task does not re-diagnose it. The kernel half of
`vm/build-i386-kernel-ahci.sh` was run directly after the script stopped
short; the compile and link commands used are the script's own.

1. **`/usr/lib/libcc.a` on the guest is PPC-only** (33,620 bytes, Feb 1999), so
   the i386 link fails with undefined `__muldi3`, `__udivdi3`, `__divdi3`,
   `__moddi3`, `__umoddi3` and `ld: warning … cputype (18, architecture ppc)
   does not match cputype (7 architecture i386)`. A **fat** `libcc.a`
   (i386+ppc) carrying exactly those five symbols does exist, at
   `/build/bootstrap-root/usr/lib/libcc.a`. The link was completed with
   `LIBS="-L/build/bootstrap-root/usr/lib -lcc"` on the make command line —
   **an environment override only; no repo file was changed**, and
   `vm/tests/test-build-src.ps1:261` deliberately asserts the i386 kernel must
   *not* carry a workaround object, so the fix belongs in guest provisioning.
   **[measured]**
2. **`build-i386-kernel-ahci.sh` cannot run under the guest's `/bin/sh`.** It
   uses `command -v`, which that shell lacks (`-v: not found`, rc 127); it runs
   under `/bin/bash`. **[measured]**
3. **The script never creates `BUILD/`.** It removes `BUILD/RELEASE_I386` but
   `conf/Makefile`'s `tools` target does `cd ${OBJROOT}` with no `mkdir`, so on
   a tree that has never been built — or one just re-synced, since `BUILD/` is
   not in the repo — the build dies with `cd: can't cd to ../BUILD`.
   **[measured]**
4. **The portable AHCI tests fail before the kernel is reached**, unrelated to
   anything here: they compile natively with `-ansi -pedantic -Wall -Werror`
   and trip on `static __inline` at
   `/System/Library/Frameworks/System.framework/Headers/bsd/stdio.h:338`.
   **[measured]**

### Still not determined

- **The return type.** Unchanged from Task 1: `void` remains an inference. Our
  `void` definition reproduces the reference's bytes, which is consistent with
  `void` but does not prove it — a function returning a value it never sets
  would compile the same. **[inference]**
- **Whether the reference's `lsb` was one reused local or three.** Both spell
  the same instructions; ours reuses one. Not decidable from the binary.
  **[inference]**
- **D4 is still an inference.** Placing the function in `FBConsole.c` followed
  Task 1's link-order argument. It built and linked with no friction, which is
  consistent with D4 but does not upgrade it to a measurement.

---

## Task 3: writing `FBAllocateVBEConsole`

**Result: structural parity. Byte parity was never a target here**, for a
reason that is measured rather than assumed — see "Why byte parity is out of
reach" below. The function is defined and exported in the built kernel, and
Task 2's 539-byte extent still matches.

### The reference, decoded here rather than taken from the plan

`_FBAllocateVBEConsole`, `0x0019ECB8`, **212 bytes**, all 212 decoded with no
undecodable residue **[measured]**. The whole function, condensed:

```
fn+0    push ebp; mov ebp,esp; sub esp,0x88; push edi; push esi; push ebx
fn+12   cmp  word  [0x1285C],0 ; je  fn+31       ; xResolution
fn+22   cmp  dword [0x12854],0 ; jne fn+40
fn+31   xor eax,eax ; jmp fn+197                 ; return NULL
fn+38   nop nop                                  ; align fn+40
fn+40   lea esi,[ebp-0x88]                       ; &info
fn+46   push esi ; push 0x12858 ; call 0x0019ED8C  (VBEModeInfo2IODisplayInfo)
fn+57   mov edx,[0x12854]
fn+63   mov [ebp-0x74],edx                       ; info.frameBuffer, OVERWRITTEN
fn+66   add esp,8
fn+69   push 0x20   ; call 0x001A5448 (_IOMalloc) ; mov ebx,eax
fn+81   test ebx,ebx ; jne fn+92 ; xor eax,eax ; jmp fn+197
fn+89   nop nop nop                              ; align fn+92
fn+92   push 0xE4   ; call 0x001A5448 (_IOMalloc) ; mov [ebx+0x1C],eax
fn+108  test eax,eax ; jne fn+124
fn+112  push 0x20 ; push ebx ; call 0x001A5458 (_IOFree) ; xor eax,eax ; jmp fn+197
fn+124  <seven vtable stores, [ebx+0] .. [ebx+0x18]>
fn+172  mov edi,[ebx+0x1C]; add edi,4; cld; mov ecx,0x22; rep movsd
fn+186  mov eax,[ebx+0x1C]; mov dword [eax],0
fn+195  mov eax,ebx
fn+197  lea esp,[ebp-0x94]; pop ebx; pop esi; pop edi; mov esp,ebp; pop ebp; ret
fn+210  nop nop                                  ; inter-function padding
```

The function takes **no arguments** — nothing reads `[ebp+8]` — and returns
`IOConsoleInfo *` in `eax`. **[measured]**

### The reference does not call `FBAllocateConsole`; it carries a copy of it

This is the single most important structural fact, and it was measured, not
assumed. `_FBAllocateConsole` sits at `0x0019EC24`, 148 bytes, and
`FBAllocateVBEConsole` never calls it — its four `call`s go to
`_VBEModeInfo2IODisplayInfo` once, `_IOMalloc` twice and `_IOFree` once.
Instead, `FBAllocateVBEConsole`'s tail (`fn+69`..`fn+196`) **is**
`FBAllocateConsole`'s body (`fn+6`..`fn+135`), normalised and diffed
instruction by instruction:

- both are **37 instructions**; excluding `nop`s and the one instruction with
  no counterpart, both are **34 instructions**, and all 34 agree in mnemonic
  and operands **[measured]**;
- the seven that "differ" differ only in a displacement: the body's three
  `call`s resolve to the **same absolute targets in both** (`0x001A5448`
  twice, `0x001A5458` once), and the four intra-function branches land at the
  same place within each body;
- the one instruction without a counterpart is `mov esi,[ebp+8]` at
  `FBAllocateConsole+114`, which loads the *parameter*.
  `FBAllocateVBEConsole` instead does `lea esi,[ebp-0x88]` at `fn+40`, hoisted
  to before the conversion call because it needs `&info` as an argument;
- the pads differ by one byte — `FBAllocateConsole` has two `nop`s at its
  `fn+26`, `FBAllocateVBEConsole` three at its `fn+89` — because the copies
  start at different offsets (6 versus 69) within their functions, so the
  4-byte alignment pad before the same label differs. **[measured]**

**Why this matters for how we write it.** The kernel is built with `-O3`, and
gcc 2.7.2.1 at `-O3` turns on `-finline-functions`, which inlines suitable
same-file functions even when they are `extern` (it still emits the
out-of-line copy, which is why `_FBAllocateConsole` exists as its own symbol).
So a reference that duplicates the body is exactly what
`return FBAllocateConsole(&info);` compiles to under this compiler.
**[INFERENCE — that the 4.2 source said `FBAllocateConsole(&info)` rather than
repeating the allocation by hand is NOT decidable from the binary; both spell
the same instructions. What is measured is only that the reference does not
call it and that the bodies correspond instruction for instruction.]**

Either way, calling it is the right spelling for this tree: transcribing the
body would duplicate console machinery that already sits in `FBConsole.c` a
few lines above.

### Why byte parity is out of reach, counted rather than asserted

Of the 212 bytes, the ones that hold an address **[measured, by decoding every
operand]**:

| kind | count | bytes | can it match? |
| --- | --- | --- | --- |
| `rel32` call operands | **4** (not five) | 16 | **no** — `_IOMalloc`, `_IOFree` and `_VBEModeInfo2IODisplayInfo` all sit elsewhere in our kernel |
| vtable `imm32` (the seven console ops) | 7 | 28 | **no** — all seven targets are nameless statics at different addresses |
| `KERNBOOTSTRUCT` operands: `disp32` at fn+15, fn+24, fn+59 and `imm32` at fn+48 | 4 | 16 | **yes** — `0x1285C`, `0x12854`, `0x12858` are fixed low-memory constants and we hard-code the same ones |

So **44 of 212 bytes cannot match** no matter how the source is written, and
168 could in principle. That is why the target here is structural
correspondence and not a byte count. The plan's figure of "five `rel32` calls"
is one too many; there are four. **[measured]**

No byte comparison of this function was run. Running one would report the 44
bytes above plus whatever gcc chose for the call sequence, and would measure
nothing that this table does not already state.

### The structural correspondence, item by item

**The guard.** The reference tests `xResolution` **first** and the
frame-buffer word second (`fn+12` then `fn+22`), both against zero, falling
into a shared `return NULL`. That is `A == 0 || B == 0` with `A` =
`xResolution`, and it is the order ours uses. (The plan's sketch had the two
operands the other way round; the reference is what was followed.)
**[measured]**

| reference | ours |
| --- | --- |
| `cmp word [0x1285C],0 ; je -> NULL` | `VBE_BOOTER_MODE->xResolution == 0` |
| `cmp dword [0x12854],0 ; jne -> go` | `VBE_FRAMEBUFFER_VIRT == NIL` |
| `push 0x12858 ; call _VBEModeInfo2IODisplayInfo` | `VBEModeInfo2IODisplayInfo(VBE_BOOTER_MODE, &info)` |
| `mov edx,[0x12854] ; mov [ebp-0x74],edx` | `info.frameBuffer = VBE_FRAMEBUFFER_VIRT` |

**The two `IOMalloc` sizes**, against the numbers D3 measured on the guest with
the kernel build's own command line (not counted by hand):

| reference | our expression | our measured value | same? |
| --- | --- | --- | --- |
| `push 0x20 ; call _IOMalloc` (fn+69) | `sizeof(IOConsoleInfo)` | **32** | yes |
| `push 0xE4 ; call _IOMalloc` (fn+92) | `sizeof(ConsoleRep)` | **228** | yes |
| `push 0x20 ; push ebx ; call _IOFree` (fn+112) | `IOFree(cso, sizeof(IOConsoleInfo))` | **32** | yes |
| `mov ecx,0x22 ; rep movsd` to `priv+4` (fn+179) | `sizeof(IODisplayInfo)` = 34 dwords | **136** | yes |
| `mov [ebx+0x1C],eax` | `offsetof(IOConsoleInfo, priv)` | **28** | yes |

**The seven vtable stores.** The reference's order against our
`IOConsoleInfo`'s seven slots (`ConsoleSupport.h:74-92`, read and confirmed
here) and `FBAllocateConsole`'s seven assignments (`FBConsole.c`):

| store | reference target | our slot | our assignment |
| --- | --- | --- | --- |
| `mov [ebx+0x00],0x0019EFA8` | the 228+32 freeing function one pad byte after `VBEModeInfo2IODisplayInfo` | `Free` | `cso->Free = Free` |
| `mov [ebx+0x04],0x0019DF7C` | nameless static | `Init` | `cso->Init = Init` |
| `mov [ebx+0x08],0x0019EFCC` | nameless static | `Restore` | `cso->Restore = Restore` |
| `mov [ebx+0x0C],0x0019E23C` | nameless static | `DrawRect` | `cso->DrawRect = DrawRect` |
| `mov [ebx+0x10],0x0019E7CC` | nameless static | `EraseRect` | `cso->EraseRect = EraseRect` |
| `mov [ebx+0x14],0x0019F050` | nameless static | `PutC` | `cso->PutC = PutC` |
| `mov [ebx+0x18],0x0019F068` | nameless static | `GetSize` | `cso->GetSize = GetSize` |

Seven stores, seven slots, same order, offsets 0/4/8/0xC/0x10/0x14/0x18 against
seven consecutive function pointers followed by `priv` at 28. **[measured for
the offsets and the store order; that each nameless target is the console op
named beside it is Task 1's D4 argument, which remains an inference for the
five middle rows — only `0x0019EFA8` was independently identified, by its
`IOFree(priv,228)` + `IOFree(cso,32)` body.]**

In our tree all seven reach the freshly allocated struct through
`FBAllocateConsole`, which performs the identical seven assignments. We do not
repeat them in `FBAllocateVBEConsole`.

**The tail.** `mov edi,[ebx+0x1C]; add edi,4; rep movsd` of 34 dwords is
`((ConsolePtr)cso->priv)->display = *display` (D5: `display` at offset 4,
measured both sides), and `mov dword [eax],0` is
`window_type = SCM_UNINIT` (D5: offset 0, `SCM_UNINIT` = 0). Both live in
`FBAllocateConsole` already.

### The uninitialised local, verified independently

The plan asserted it and this task re-checked it: between `sub esp,0x88` at
`0x0019ECBB` and the `call` at `0x0019ECEC` the reference executes
`push edi`, `push esi`, `push ebx`, two compares, two branches, a `lea` and two
`push`es — **no `rep stos`, no `bzero`, and no call of any kind**.
**[measured, from the full 212-byte decode above]** So
`VBEModeInfo2IODisplayInfo`'s `default:` arm ORs its bit into stack residue,
and the fields that arm never stores are copied into `priv+4` as residue too.
Ours does the same: `info` is a plain local and is not zeroed. Both halves are
now labelled in `FBConsole.c` — on the `default:` arm and on the call site.

### `0x12854` has no producer in this tree, and that is the correct state

Nothing under `src/` writes `kbs+0x1854`. In 4.2 the writer is the kernel's own
`pmap_bootstrap` (D2: one writer, one reader); in Rhapsody's `KERNBOOTSTRUCT`
the offset lands inside `_reserved[7500]`, which `getKernBootStruct()`
`bzero`s **[QUALIFIED — `getKernBootStruct()` is `src/boot-2`'s. The booter
that actually runs is Apple's stock v5.0.41.1, whose zeroing was not read; Task 5's
`pmemsave` dump measured `kbs+0x1854` zero under it on both boot paths (Task
5, "What the booter hands the kernel"), and that is the stronger basis]**. So
`VBE_FRAMEBUFFER_VIRT` reads 0, the second guard fails, and
`FBAllocateVBEConsole` returns `NIL` on every boot. **Spec 3 owns the
producer** — mapping the linear frame buffer and publishing its kernel virtual
address. Until it lands, Task 4's wiring falls through to the existing VGA
console, which is what boots today regardless, so nothing observable changes.

No placeholder producer was written, the address was not stubbed, and the
guard was not weakened. The function compiles, links and exports, and is not
reached.

### Open for spec 3: two spellings of the same address must be reconciled

`FBConsole.c` now hard-codes `#define VBE_BOOTER_MODE ((VBEModeRec *)0x12858)`,
**the same spelling spec 1's driver uses** at
`src/drivers-i386/video/drvVBE20DisplayDriver/VBE20DisplayDriver.drvproj/VBE20DisplayDriver_reloc.lksproj/VBE20DisplayDriver.m:79`.
That is deliberate: driver and kernel must read one record, not two. Neither
side invents a `KERNBOOTSTRUCT` member for it, because introducing one would
have to change both at once.

**Spec 3 must reconcile them.** Whatever it does — add a named member, keep the
literals, or move the record — it has to change both sites together, and the
kernel's `VBE_FRAMEBUFFER_VIRT` (`0x12854`) with them. If the two drift apart
the driver and the console will read different memory and neither will say so.

Neither `VBE_BOOTER_MODE` nor `VBE_FRAMEBUFFER_VIRT` is `volatile`. That is
harmless today — boot is single-threaded and there is no producer — but once
spec 3 supplies one, both become reads of a word written by unrelated code, so
Task 4/5 and spec 3 should decide the question rather than inherit it. The code
was deliberately left unchanged.

**Spec 3's producer must also write `0x12854` after `getKernBootStruct()`'s
`bzero` of `_reserved[7500]`, or narrow that `bzero` to exclude it.** Both
`0x12854` and `0x12858` sit inside `_reserved[7500]` (see above), and that
`bzero` is in the booter (`src/boot-2/i386/libsaio/bootstruct.c:79`, called
early from `boot.c:414`). A write that lands before the zeroing is silently
erased, and the failure would present as "the guard never passes" with nothing
else visibly wrong. A booter-side producer is therefore the exposed one; a
kernel-side producer, as 4.2's `pmap_bootstrap` is, runs after the booter has
finished **[INFERENCE: from the booter-then-kernel order, not traced here]**.
Whether anything else clears the word between the producer and this function's
read was not checked.

### The build: `rbuild kernel` needs `--toolchain`, and the documented line omits it

The invocation in `docs/build/rbuild-universal.md:195`:

```
rbuild kernel --state /build/state --arch i386 /build/src /build/repo <dest>
```

**fails before compiling anything**, with:

```
Building build root:
tar: Unable to set file uid/gid of ./usr/bin/chgrp <No such file or directory>
tar: Unable to set file uid/gid of ./usr/bin/cpio <No such file or directory>
tar: Unable to set file uid/gid of ./usr/bin/tar <No such file or directory>
rbuild: unable to find dependency for "file-cmds"
rbuild: kernel failed: driverkit-3
```

Diagnosed rather than worked around **[measured]**:

- `file-cmds` is one of rbuild's built-in `basedeps`
  (`src/rbuild-1/builder.c:747-759`), so this blocks **every** build root, not
  just the kernel's.
- `/build/repo/file-cmds-1998.10.06-universal.apk` does exist and does match by
  name (`builder_match_pkgfile`). It is rejected by the *validation* step,
  which extracts the APK to inspect it.
- The package ships `usr/bin/chgrp`, `usr/bin/cpio` and `usr/bin/tar` as
  **symlinks to `../../bin/pax`, which the package does not contain**.
  Rhapsody's `/usr/bin/tar` follows each dangling symlink to set its uid/gid,
  warns, and **exits 1**. rbuild reads that as "cannot validate" and then as
  "cannot find".
- With no `--toolchain`, rbuild falls back to plain `tar`
  (`src/rbuild-1/apk.c:1050`, `fallback.tar = "tar"`). The toolchain profile
  instead names `/build/src/rbuild-1/pax-gnutar.sh`.

Measured side by side on the same APK:

```
gunzip -c file-cmds-...apk | tar -C /tmp/a -xf -             ->  rc 1  (3 warnings)
gunzip -c file-cmds-...apk | pax-gnutar.sh -C /tmp/b -xf -   ->  rc 0
```

The project's own build driver **always** passes the flag —
`vm/build-src-lib.ps1:498` is
`rbuild kernel --state $state --toolchain $profilePath --arch $targetArch …` —
so the doc line is the outlier, not the scripts. The working invocation, and
the one this task used:

```
rbuild kernel --state /build/state \
  --toolchain /build/src/rbuild-1/toolchains/gcc-darwin.conf \
  --arch i386 /build/src /build/repo /tmp/task3-kvbe-dst
```

The profile's `target_arch=ppc` does not interfere: `--arch` selects the kernel
architecture and the package set, while the profile supplies `tar`, `gzip`,
`make` and `PATH`. No fallback to `gnumake` was used, and no repo file was
changed — `file-cmds`'s dangling symlinks are still there and will bite the
next caller who omits the flag.

### A second blocker behind the first: the profile's `PATH` loses `relpath`

With `--toolchain`, the build root assembles and driverkit, drivertools and
kernload all build — then `kernel-7` dies in `installhdrs`, before compiling
anything **[measured]**:

```
================= make installhdrs for conf =================
relpath: not found
relpath: not found
make[1]: Entering directory `.../kernel-154.5.1-7/conf'
Must define OBJROOT
make[1]: *** [OBJROOT] Error 1
```

`src/kernel-7/MakeInc.dir:69-71` passes ``OBJROOT=`relpath -d $VERSDIR . $OBJROOT` ``
and the same for `SYMROOT` into every subdirectory make. With `relpath`
missing both backticks expand to nothing, the sub-make receives `OBJROOT=`,
and `conf/Makefile:358` (`DSTROOT OBJROOT: ALWAYS`) prints `Must define
OBJROOT` and exits 1. The two `relpath: not found` lines per recursion are the
two backticks.

`relpath` is **present** in the build root, at `/usr/local/bin/relpath`,
installed there by the `bootstrap-cmds-13.2-universal.apk` basedep. It is the
**`PATH` that is wrong**: `gcc-darwin.conf` has

```
path=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

which omits `/usr/local/bin`, and `/build/tools` does not exist inside the
chroot at all. With no `--toolchain` rbuild leaves `tc->path` unset and the
ambient `PATH` (which does find `/usr/local/bin/relpath`) applies — which is
why the two failure modes are complementary: **without** the flag the build
root cannot be assembled, **with** it the kernel cannot configure.
**[measured]**

This task worked around it with a `sed` copy of the profile in `/tmp` adding
`/usr/local/bin` to `path`, passed as `--toolchain /tmp/task3-gcc-darwin.conf`.
The copy is ephemeral, so here is the exact command, as run on the guest
**[measured]** — it writes the copy and leaves the repo's profile untouched:

```
sed -e 's|^path=.*|path=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin|' \
    /build/src/rbuild-1/toolchains/gcc-darwin.conf > /tmp/task3-gcc-darwin.conf
```

Its only effect is the one `path=` line; `grep '^path=' /tmp/task3-gcc-darwin.conf`
afterwards should show `/usr/local/bin` as the last component. **No repo file
was changed** — as with Task 2's `libcc.a` override, the real fix belongs in
guest provisioning or in the profile, and is not Task 3's to make.

### The build that the results below come from

```
rbuild kernel --state /build/state --toolchain /tmp/task3-gcc-darwin.conf \
  --arch i386 /build/src /build/repo /tmp/task3-kvbe-dst
```

ends `rbuild: kernel complete`, exit 0. Eight APKs, all `i386`:
`driverkit-139.1-3`, `drivertools-24-1`, `kernload-60-1`, `kernel-154.5.1-7`
and their `-hdrs` companions. The kernel was taken from
`kernel-154.5.1-7-i386.apk`, not from a hand-run `gnumake` — `./mach_kernel`,
1,490,352 bytes, SHA-256
`1C0F8B804A5ECEF5124B3FCE9C3335356B7692B7C1FD11E2A40CFD6B87F7215D`, BSD `sum`
**`39989 1456`** (printed on the guest and reproduced from the pulled bytes, as
under A1 above). **[measured]**

This is the **second** build of this source. The first differed only in a
comment inside `FBAllocateVBEConsole`, corrected before commit, and the two
make a useful control for the A1 inference above: the whole-kernel SHA-256
changed (`81CA970C…EC4F` -> `1C0F8B80…215D`) and the `sum` with it
(`26491 1456` -> `39989 1456`), while the **539-byte extent hashed identically
across both** (`DE5CA40A…1E13`) and `nm` gave the same three addresses. A
comment edit moves the embedded build timestamp and nothing else — which is
exactly the relationship A1 could only infer for the vanished
`AC2213A3…010F`, here measured on a pair that still exists. **[measured]**

The only diagnostic from the new code is Task 2's known one, on the
`(void *)mode->modeNumber` cast:

```
FBConsole.c:1477: warning: cast to pointer from integer of different size
```

### Where the kernel these results come from is kept

`/tmp/task3-kvbe-dst` and the guest's `/tmp` are ephemeral, which is exactly how
`AC2213A3…010F` was lost (A1). The evidence below is **not** pinned to that
path. A retained copy of the extracted kernel, `task3-mach_kernel-final`,
exists **outside the repo**, in a session scratchpad (its machine-local path is
not recorded, since the scratchpad does not outlive the session):
1,490,352 bytes; re-checked when this note was written: SHA-256
`1C0F8B80…215D` and a reimplemented BSD `sum` of `39989 1456`, both equal to
the values above **[measured]**. It is a session scratchpad, so it is retained
for that session and is not a durable store; built kernels are deliberately not
committed.

Nor is the check re-runnable from the commit alone. A rebuild from this source
with the commands above should reproduce the 539-byte extent hash
(`DE5CA40A…1E13`) and the three `nm` addresses, and should **not** reproduce the
whole-kernel SHA-256 or `sum`, which move with the embedded build timestamp
**[INFERENCE: from the two-build control above; a third build was not run]**.
`compare_kvbe.py` is not in the commit either — harnesses are not committed —
so the 411/411 comparison needs that script supplied separately.

### Symbols, and Task 2's extent re-checked against this kernel

`nm` on the stripped kernel that ships in the APK **[measured]**:

```
001e8740 T _FBAllocateConsole
001e87d4 T _VBEModeInfo2IODisplayInfo
001e89f0 T _FBAllocateVBEConsole
```

All three defined (`T`) and external. Note the layout: ours puts
`FBAllocateVBEConsole` *after* `VBEModeInfo2IODisplayInfo` (source order),
where 4.2 has it before — an ordering difference with no behavioural
consequence, recorded so nobody reads it as a discrepancy. As in the
reference, exactly one pad byte separates the 539-byte function from the next
one (`0x001E87D4 + 539 = 0x001E89EF`, and the next entry is `0x001E89F0`).

`compare_kvbe.py <reference i386 slice> <this kernel>`, run against the kernel
built from the committed source:

```
reference _VBEModeInfo2IODisplayInfo at 0x0019ed8c  (539 bytes)
built     _VBEModeInfo2IODisplayInfo at 0x001e87d4  (539 bytes)
masked 128 bytes (dispatch imm32 at fn+71, 31 table entries at fn+76); comparing 411
masked region agrees: dispatch -> fn+76, 31 table targets identical relative to the entry
MATCH: all 411 compared bytes identical
```

**Task 2 is not regressed.** The entry moved from `0x001E8804` to
`0x001E87D4` — still `≡ 0 mod 4`, so the seven alignment-driven interior pads
still line up — and the extent's SHA-256 changed with it, from
`CFA460B3…C596` to
`DE5CA40A4DFCA646FAAD2CE183FC301E394CD1DE86EBE9AFF63DC2DF7E381E13`. That
change is **entirely** the 128 masked bytes, which hold absolute addresses into
the function itself; the harness's relative check confirms the dispatch and all
31 table targets are unchanged relative to the entry. A moved function is
expected to re-hash. **[measured]**

### Nothing calls it yet

`FBAllocateVBEConsole` appears in exactly two places outside comments: its
definition in `FBConsole.c` and its declaration in `FBConsole.h`. Task 4 owns
the wiring. The diff for this task is **insertions only, zero deletions**, so
no existing behaviour changed; adding a function shifts later addresses, which
is relocation, not behaviour.

---

## Task 4: wiring `BasicAllocateConsole`

### Correction to the plan: there *is* a reference, and it is ours

Task 4's plan step, as committed up to `3188aa18d` (Step 1; the plan's Task 4
was rewritten afterwards), states that 4.2's `BasicAllocateConsole`
"is not ours" and that the shape therefore has to be inferred from ppc. **Both
claims are wrong, and the evidence is direct.** The reference kernel exports
`_BasicAllocateConsole` at `0x00197C58`, it is 72 bytes
(`0x00197C58`-`0x00197C9F`), and it is our function **[measured]**:

```
  00197c58  push     ebp
  00197c59  mov      ebp, esp
  00197c5b  sub      esp, 0x88
  00197c61  push     ebx
  00197c62  call     0x19ecb8      ; _FBAllocateVBEConsole
  00197c67  test     eax, eax
  00197c69  jne      0x197c96
  00197c6b  push     0x88
  00197c70  lea      ebx, [ebp - 0x88]
  00197c76  push     ebx
  00197c77  call     0x101600      ; _bzero
  00197c7c  mov      dword ptr [ebp - 0x88], 0x280
  00197c86  mov      dword ptr [ebp - 0x84], 0x1e0
  00197c90  push     ebx
  00197c91  call     0x19b760      ; _VGAAllocateConsole
  00197c96  mov      ebx, dword ptr [ebp - 0x8c]
  00197c9c  mov      esp, ebp
  00197c9e  pop      ebp
  00197c9f  ret
```

```
  00197c58  55 89 e5 81 ec 88 00 00 00 53 e8 51 70 00 00 85
  00197c68  c0 75 2b 68 88 00 00 00 8d 9d 78 ff ff ff 53 e8
  00197c78  84 99 f6 ff c7 85 78 ff ff ff 80 02 00 00 c7 85
  00197c88  7c ff ff ff e0 01 00 00 53 e8 ca 3a 00 00 8b 9d
  00197c98  74 ff ff ff 89 ec 5d c3
```

`0x88` is `sizeof(IODisplayInfo)` exactly - 72 bytes of scalars plus
`IOPixelEncoding pixelEncoding`, `char[IO_MAX_PIXEL_BITS]` with
`IO_MAX_PIXEL_BITS` 64 (`src/driverkit-3/driverkit/displayDefs.h:118,120`), so
136 = `0x88`. `0x280` is 640 and `0x1E0` is 480. That is `IODisplayInfo di;
bzero(&di, sizeof(di)); di.width = 640; di.height = 480; return
VGAAllocateConsole(&di);` - the body that was already in
`bsd/dev/i386/BasicConsole.c` before this task.

The two call targets were resolved from the slice's own symbol table, not
guessed: `0x0019B760` is `_VGAAllocateConsole` and `0x00101600` is `_bzero`
**[measured]**.

### Our pre-Task-4 build is the reference minus exactly nine bytes

Same function in the kernel built at the end of Task 3 (the retained artifact
described under "Where the kernel these results come from is kept"),
`_BasicAllocateConsole` at `0x001E214C`, **63 bytes** **[measured]**:

```
  001e214c  push     ebp
  001e214d  mov      ebp, esp
  001e214f  sub      esp, 0x88
  001e2155  push     ebx
  001e2156  push     0x88
  001e215b  lea      ebx, [ebp - 0x88]
  001e2161  push     ebx
  001e2162  call     0x100c40      ; _bzero
  001e2167  mov      dword ptr [ebp - 0x88], 0x280
  001e2171  mov      dword ptr [ebp - 0x84], 0x1e0
  001e217b  push     ebx
  001e217c  call     0x1e5c68      ; _VGAAllocateConsole
  001e2181  mov      ebx, dword ptr [ebp - 0x8c]
  001e2187  mov      esp, ebp
  001e2189  pop      ebp
  001e218a  ret
```

72 minus 63 is 9, and the nine are precisely `e8 <rel32>` (5) plus `85 c0` (2)
plus `75 2b` (2). Every other instruction agrees in mnemonic, operands and
encoding, including the two `mov`s of 640 and 480 and the `[ebp-0x8c]` `ebx`
restore. **The two functions differ by the `FBAllocateVBEConsole()` call and
nothing else.** This is a far stronger statement than the plan's Task 4 step
(as committed up to `3188aa18d`) expected to be available, and it is what the
source change was written from.

### Answering the design question: no outer `v_baseAddr` test

The predecessor's uncommitted draft guarded the new arm with
`if (kernbootstruct->video.v_baseAddr)`, mirroring ppc. **Dropped, on
measurement, not on taste.**

- The reference calls `_FBAllocateVBEConsole` **unconditionally, as the first
  instruction after the prologue**. Nothing is tested before it **[measured]**.
- The reference's `_BasicAllocateConsole` touches **no** part of
  `KERNBOOTSTRUCT`: over its 72 bytes there is no memory operand in
  `[0x11000, 0x13000)` and no argument access at `[ebp+8]` **[measured]**.
- ppc's outer test is not a counter-example, it is a different situation:
  `bsd/dev/ppc/kmDevice.m:150-167` tests `framebufferArgs->v_baseAddr` because
  **the caller builds the `IODisplayInfo` inline** and then passes it to a
  `BasicAllocateConsole(IODisplayInfo *)` that takes it as an argument
  (`bsd/dev/ppc/FBConsole.c:1720`). i386's `BasicAllocateConsole` takes no
  argument and `FBAllocateVBEConsole` encapsulates both the test and the
  build, so there is no work to guard.
- The two predicates are not even the same fact. `video.v_baseAddr` is the
  *physical* linear-frame-buffer base, and on i386 **the booter already writes
  it today** **[QUALIFIED — true only of `src/boot-2`, and there only with a
  `Graphics Mode` config key, which no shipped config sets; the booter actually
  on the image, Apple's stock v5.0.41.1, leaves it zero even in graphics mode
  (measured, Task 5 "Corrections")]** - `src/boot-2/i386/boot2/graphics.c:200-208`, in `setMode()`, on a
  graphics-mode boot with a linear VBE mode. `FBAllocateVBEConsole`'s guards
  read `kbs+0x1858` (`xResolution` of the booter's `VBEModeRec`) and
  `kbs+0x1854` (the *mapped virtual* address), neither of which the booter
  writes **[QUALIFIED — the word the first guard reads is `kbs+0x185C`,
  `xResolution` at `+4` into the `VBEModeRec` at `kbs+0x1858`; that
  `kbs+0x1854` holds a mapped virtual address is D2's inference; and "the
  booter" here is `src/boot-2`, which writes neither word. The stock v5.0.41.1
  booter that ran left both zero (measured, Task 5). OPENSTEP 4.2's own booter
  does write the `VBEModeRec` at `kbs+0x1858`, `xResolution` included, but no
  reference in it to `kbs+0x1854` was found (D2)]**. Gating on `v_baseAddr` would therefore couple "the console may use a
  frame buffer" to "the booter chose graphics mode", which is a different
  question, and would let spec 3 be silently blocked if it published the mode
  record without also setting `video.v_baseAddr`.

The vestigial `KERNBOOTSTRUCT *kernbootstruct = KERNSTRUCT_ADDR;` therefore
stays declared and unused, and the plan's "it becomes used" (Task 4 Step 2, as
committed up to `3188aa18d`) does not hold.
Keeping it costs nothing measurable: our pre-Task-4 build already reserves the
reference's `0x88` and no more, so gcc drops the unused local entirely.
**Not determinable:** whether 4.2's source carried the same vestigial
declaration - an unused local leaves no trace in the binary.

### The reference's `kminit` calls it too; ours is not changed here

`_kminit` at `0x00197514` is the second and only other caller of
`_FBAllocateVBEConsole` in the reference **[measured]** - the scan decoded
`__text` linearly and collected every `call rel32` whose target is
`0x0019ECB8`; there are exactly two, this one and `_BasicAllocateConsole`'s.
It reads:

```
  00197517  mov      dword ptr [0x1e777c], 1     ; initialized = TRUE
  00197521  call     0x19ecb8                    ; _FBAllocateVBEConsole
  00197526  mov      dword ptr [0x1f7b3c], eax   ; basicConsole = ...
  0019752b  test     eax, eax
  0019752d  jne      0x197539
  0019752f  call     0x197c58                    ; _BasicAllocateConsole
  00197534  mov      dword ptr [0x1f7b3c], eax
  00197539  cmp      dword ptr [0x1114c], 0      ; kernbootstruct->graphicsMode
```

Our `kminit` (`bsd/dev/i386/km.m:494-510`, `_kminit` at `0x001E1A70` in the
Task 3 kernel) is the same function without that first attempt: `initialized =
TRUE`, `basicConsole = BasicAllocateConsole()`, then the identical
`cmp dword ptr [0x1114c], 0` - **the same absolute address as the reference's**,
which independently confirms `kbs+0x14c` is `graphicsMode` on both sides
**[measured]**.

This divergence is **left in place**. Once `BasicAllocateConsole` makes the
call itself, the reference's extra attempt in `kminit` is a redundant duplicate
with no behavioural effect, and `km.m` is not Task 4's file. Recorded for
whoever owns `km.m` parity; it is not a defect in what Task 4 shipped.

### The change, and why it is invisible today

```c
    console = FBAllocateVBEConsole();
    if (console)
	return console;
```

inserted ahead of an untouched `bzero`/640/480/`VGAAllocateConsole` tail, plus
`#import <bsd/dev/i386/FBConsole.h>`. **Correction: not insertions only.** One
pre-existing line was removed - the blank, whitespace-only line that stood
immediately after the `kernbootstruct` declaration - to make room for the new
`IOConsoleInfo *console;` local and the comment block. No other pre-existing
line changed.

`FBAllocateVBEConsole` returns `NIL` on every boot in this tree, because
nothing writes `kbs+0x1854` - spec 3 owns that producer, as recorded under
"`0x12854` has no producer in this tree, and that is the correct state".
**The new arm is unreachable until spec 3 exists**, and the VGA path below is
what runs. No producer was stubbed, no guard weakened and no debug override
added to make the arm reachable.

Compile risk from the new `#import` was checked statically, since the build box
was unavailable (below). `FBConsole.h` pulls `<mach/boolean.h>`,
`<driverkit/displayDefs.h>` and `<bsd/dev/i386/ConsoleSupport.h>`.
`ConsoleSupport.h` has no include guard, but `BasicConsole.c` **already**
includes it twice today under two different spellings - `BasicConsole.h`
imports `"ConsoleSupport.h"` and `VGAConsole.h` imports
`<bsd/dev/i386/ConsoleSupport.h>` - and `displayDefs.h` likewise. FBConsole.h
uses the same angle spelling `VGAConsole.h` does, so the new import adds no
combination the translation unit does not already compile **[inference, from
the existing include graph; not confirmed by a compile]**.

### NOT VERIFIED: the build and the invisibility gate could not be run

**[SUPERSEDED — see "Task 4: resolved" at the end of this section. Later
passes got the build box back, checks 1-3 passed, and check 4 passes under
the same-session A/B control substituted for the "must be identical" gate
this section still assumes below. Task 4 is complete. The account below is
left as written, for the infrastructure history it records.]**

**This section is the honest state of Task 4 and must be read before Task 5
starts.** Acceptance items 1-3 - kernel builds, Task 2's 539-byte extent still
MATCHes, console output identical to the pre-Task-4 kernel - are **not
demonstrated**, for an infrastructure reason:

- The Rhapsody build box named in the gitignored `vm/vm.conf`, the "legacy PPC
  build box" of `vm/SSH CONNECTION.md`, **appears powered off**
  **[inference: only unreachability was measured below, not the power state
  itself]**. `vm/sync-src.ps1 -Path kernel-7` failed with `ssh: connect to
  host 10.10.0.241 port 22: Connection timed out`; twelve pings in three
  batches spread over roughly four minutes all timed out (one very first ping
  replied, then nothing -- stale ARP); the address is absent from the host's
  ARP table. It is a machine on the LAN, not a VM this repo can start - there
  is no launcher for it under `vm/` (`start-vm.cmd` boots `work/test.img`, the
  i386 boot-test image, and nothing else), and no hypervisor process is
  running on the host **[measured]**.
- `rbuild` runs only on that guest, so no kernel could be produced; with no new
  kernel there is nothing to graft into an image and nothing to compare against
  a pre-Task-4 capture. Falling back to `gnumake` was not attempted and would
  not have been evidence anyway.

The retained pre-Task-4 kernel **was** re-verified, since that could be done
locally: 1,490,352 bytes, SHA-256
`1C0F8B804A5ECEF5124B3FCE9C3335356B7692B7C1FD11E2A40CFD6B87F7215D`, and
`_FBAllocateConsole` `0x001E8740`, `_VBEModeInfo2IODisplayInfo` `0x001E87D4`,
`_FBAllocateVBEConsole` `0x001E89F0` - all equal to the values this record
carries **[measured]**. It is sound to compare against when the box
returns.

### What to run when the build box is back

Task 3's two provisioning workarounds still apply verbatim (`--toolchain`, and
`/usr/local/bin` on the profile's `path=`).

```
powershell -NoProfile -File vm/sync-src.ps1 -Path kernel-7
# on the guest:
sed -e 's|^path=.*|path=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin|' \
    /build/src/rbuild-1/toolchains/gcc-darwin.conf > /tmp/task4-gcc-darwin.conf
rbuild kernel --state /build/state --toolchain /tmp/task4-gcc-darwin.conf \
  --arch i386 /build/src /build/repo /tmp/task4-kvbe-dst
```

Then three gates, the third of which this task's measurements make available
and the plan's Task 4 step (as committed up to `3188aa18d`) did not expect to
exist:

1. `compare_kvbe.py <reference i386 slice> <built kernel>` still MATCHes on all
   411 compared bytes. The function moves; a move is expected to re-hash.
2. Boot the **unmodified** image with the new kernel and with
   `task3-mach_kernel-final`, `--at 30,60,95 --keys "mach_kernel -v\n"`, on a
   temporary work image. The two console captures must be **identical**.
   **[SUPERSEDED — impossible as stated; two boots of the same kernel are not
   identical (measured below). Re-specified as a same-session A/B control -
   see "Task 4: resolved" at the end of this section.]**
3. **New parity target.** `_BasicAllocateConsole` in the built kernel should be
   **72 bytes**, and should match the reference's 72 bytes above with only the
   three `e8` displacements differing - those are addresses and cannot agree.
   A different length, or any other differing byte, means the emitted shape is
   not the reference's.

### Reproducing the Task 4 measurements

Same tooling as the rest of this record - `capstone` 5.0.6 in
`.venv-binrecon`, `CS_ARCH_X86` / `CS_MODE_32`, `file offset = va - 0x100000`.
The caller scan disassembles `__text` linearly (restarting one byte past any
undecodable run) and keeps every `call` with a literal target equal to
`0x0019ECB8`; the containing function is the greatest `N_SECT` symbol address
not exceeding the call site. `_BasicAllocateConsole` and `_kminit` were then
listed from their entry to the first `ret`. The same listing was run against
`task3-mach_kernel-final` for our side. The `KERNBOOTSTRUCT`-absence claim
reuses the D2 filter - memory operands with `base == 0 && index == 0` and
displacement in `[0x11000, 0x13000)` - restricted to the 72 bytes.

### Task 4 verification pass, 2026-09-22: the build guest starved mid-build

A second session was given the verification half of Task 4 with the build box
reported reachable. It was — briefly. The source change is unaltered
(`e2d02efe8`); nothing in this pass touched it. The four checks split cleanly:

| Check | Result |
|---|---|
| 1. `_VBEModeInfo2IODisplayInfo` / `_FBAllocateVBEConsole` defined and external in the build | **not run** — no build |
| 2. Task 2's 539-byte extent still MATCHes | **not run** — no build |
| 3. `_BasicAllocateConsole` is 72 bytes and matches bar the three `e8` displacements | **not run** — no build |
| 4. Console output identical to the pre-Task-4 kernel | **half run** — the pre-Task-4 half is captured twice, with a measured noise floor; the post-Task-4 half needs the build |

#### What did run on the guest, and where it stopped

The guest was up. In sequence, all **[measured]**:

- `uname -a` → `Rhapsody rhap2 5.6 ... RELEASE_PPC ... Power Macintosh`;
  `/build/tools/bin/rbuild` present, 115900 bytes, dated Sep 22 08:07.
- `/` (which carries `/build` and `/tmp`) had **993461 KB free of 2023269**,
  48% used, before anything was built.
- `vm/sync-src.ps1 -Path kernel-7` completed. The change is on the guest:
  `/build/src/kernel-7/bsd/dev/i386/BasicConsole.c:32` has the `FBConsole.h`
  import and `:265` has `console = FBAllocateVBEConsole();`.
- Task 3's profile workaround was applied verbatim from the record above, to a
  **differently named** copy so the two tasks cannot collide:

  ```
  sed -e 's|^path=.*|path=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin|' \
      /build/src/rbuild-1/toolchains/gcc-darwin.conf > /tmp/task4b-gcc-darwin.conf
  ```

  `diff` against the repo profile shows exactly one changed line, line 16, the
  `path=`. No repo file was changed.
- The build was started at **09:47 local**, detached, logging to
  `/tmp/task4b-build.log`:

  ```
  rbuild kernel --state /build/state --toolchain /tmp/task4b-gcc-darwin.conf \
    --arch i386 /build/src /build/repo /tmp/task4b-kvbe-dst
  ```

  Five seconds in, the log read `building driverkit-139.1-3-i386 from
  /build/src/driverkit-3:` / `Building build root:`. That is the last thing
  ever read from this build.

From roughly **10:25** onward every new SSH session was refused, and it stayed
refused through **12:53** — two and a half hours — with no successful connection in
between. The failure is specific and is *not* the Task 4 predecessor's
"box is powered off":

- `ping` → 3 of 3 replies, 5 ms. `Test-NetConnection -Port 22` → `True`.
- `ssh -v` gets as far as `Local version string SSH-2.0-...` and then
  **`kex_exchange_identification: Connection closed by remote host`** — the
  server closes *before sending its own version banner*, i.e. before any key
  exchange and long before authentication.

That signature means sshd accepted the TCP connection and then could not get a
child to the point of writing a banner. **[inference, marked as such]** The
most likely cause is resource starvation on the guest — memory, swap or the
process table — under an unsupervised `rbuild kernel`; the root filesystem's
993 MB of free space is also within reach of a full build root plus kernel
objects, and `/tmp/task3-kvbe-dst` from the previous task is still on it. Which
of those it is **cannot be determined from off the box**, and nothing here
should be read as having established it.

Ruled out **[measured]**:

- *Not* the client's legacy crypto options — the identical option set worked
  repeatedly against this host at 09:41–09:47.
- *Not* host-side connection exhaustion alone. Five abandoned `ssh.exe`
  processes were found holding ESTABLISHED sessions (from concurrent polls that
  the harness backgrounded on timeout); all five were killed, `netstat` then
  showed zero connections to `10.10.0.241:22`, and the very next attempt failed
  the same way. Holding several concurrent sessions open against this sshd is
  still a bad idea and probably contributed to the first refusals.
- *Not* another agent's build. The only other session touching this guest in
  this run was checked; the peer sessions were idle.

**Operational lesson for the next attempt, worth more than the diagnosis:**
run `rbuild` **in the foreground of a single held SSH session** and let its
output stream, rather than detaching it with `nohup` and polling over fresh
connections. Task 3 did the former and finished. This pass did the latter, and
when the guest stopped accepting new sessions it lost all contact with a build
that may well have been running fine.

#### Check 4's baseline half, and what "identical" can actually mean

This is new measurement and it survives the outage, so it is recorded in full.
The gate says the two console outputs "must be identical". Taken literally
against the artefacts the harness produces, that is unachievable — so the
noise floor was measured first, by booting the **same** kernel
(`task3-mach_kernel-final`) twice and comparing the two captures. **[measured]**

Method, exactly as run, from `vm/` in the `vbe20-kernel` worktree:

```
MSYS_NO_PATHCONV=1 python graft-kernel.py D:/RhapsodiOS/vm/golden.img \
    <kernel> work/test.img
python qemu-shot.py work/test.img shots-t4v-pre2 --at 30,60,95 \
    --keys $'mach_kernel -v\n' --keys-at 8
```

Two harness notes, both **[measured]**, both of which cost a boot to find:

- `rhap_inject.check_target` permits exactly one destination, `vm/work/test.img`
  **relative to the `vm/` directory of the checkout the script is run from**.
  Any other name, such as a per-session `work/<name>.img`, is refused. Run from a worktree this
  is already isolation: `<worktree>/vm/work/test.img` is a different file from
  the main checkout's, so no other session's image is touched. `golden.img` is
  only read, and was read from the main checkout because a worktree has no copy.
- **`--keys-at` must be raised.** At the default 3.0 s the boot loader received
  only `mach_ke` — the tail of `mach_kernel -v\n`, including the Return, was
  dropped — and the boot sat at `boot:` forever, 720x400, never entering the
  kernel. `--keys-at 8` lands the whole string inside the 10-second countdown
  and boots. The documented invocation in `docs/drivers/drvVGA-boot-gate.md:50`
  omits `--keys-at`; anyone reusing it should not assume the default works.

Results, two runs of the identical kernel (`shots-t4v-pre2`, `shots-t4v-preB`):

- **`serial.log` (COM2, the kernel's own console) — 76 lines in both, and the
  two line multisets are equal**: `diff <(sort a) <(sort b)` is empty. The only
  difference is interleaving: a five-line IDE block (`Registering: hc0`,
  `hd0: QEMU HARDDISK 2.5+`, geometry, multisector, `Registering: hd0`) and the
  line `intr: phantom IRQ 15, EOI to master` swap places. A device-probe race,
  not a content difference. SHA-256 of the two logs therefore differs
  (`BF84F83D…7DB` vs `9263D43D…8FD`) — **hashing serial.log is the wrong
  instrument**; the sorted line multiset is the right one.
- **Screenshots** — at 60 s and 95 s the boot has settled at
  `Continue without network? (y/n)` and the two runs' 640x480 frames differ in
  **48 pixels of 307200**, in exactly two places: character column 14 of the
  `May  8 05:00:2x init:` line and columns 17–18 of the
  `Fri May  8 05:00:3x PDT 1998` line. Those are the seconds digits of the boot
  clock. Every other pixel is identical. The 30 s frame is *not* comparable
  between runs — the screen is still scrolling and 16399 pixels differ —
  exactly as `qemu-shot.py`'s own banner warns.

So the operative form of check 4, for whoever runs it, is **[inference from the
above, marked]**:

> The new kernel's `serial.log` must contain the **same 76 lines** as the
> baseline's (order-insensitive compare), and its settled 60 s/95 s frames must
> differ from the baseline's **only** in the two clock-second fields. Anything
> else — one extra line, one missing line, a different word, a different pixel
> outside those two fields — is a real difference and the gate fails.

That is a sharper test than a hash comparison and it is not a weakening: the
baseline pair proves the two allowed sources of variation are a probe race and
a wall clock, neither of which `BasicAllocateConsole` can touch.

**[SUPERSEDED — this "operative form" treats the morning `pre2`/`preB`
capture as a fixed baseline good for later runs. Pass 3 measured that same
baseline drifting 2,518 px from a same-day re-boot of the identical,
unchanged kernel (see "Task 4 verification pass 3" below), so a fixed
morning baseline is not trustworthy across sessions regardless of how sharp
the comparison against it is. The gate was re-specified as a same-session A/B
control - see "Task 4: resolved" at the end of this section.]**

Retained, durable, in the worktree (not committed — captures are build output):
**[SUPERSEDED — not durable. These are gitignored worktree files and do not
survive a worktree cleanup; see pass 3's equivalent note below, which is the
correct one.]**

```
vm/shots-t4v-pre2/   serial.log  bf84f83ddcc092c6e078603d17db43ad3e3543e986bad98d9ae571baeca027db
                     shot-60s.png, shot-95s.png  0326ded733cae7b606451b1ee27d432aec34dfc39c79b9c3eb822c6eeb11eb01
vm/shots-t4v-preB/   serial.log  9263d43d08c1c8a30fff4554b4b4baf387b83e7bb43b7c20832432d5206f8fdb
                     shot-60s.png, shot-95s.png  8568f9fb751bf51640c32fc2621a4537bf5be81ca1550c33d6e70600faa28eae
```

#### The two inputs to the un-run checks, re-verified

Both were checked before use, because this spec has already lost one artefact
to a scratchpad. **[measured, 2026-09-22]**

- **The retained pre-Task-4 kernel is intact and is what the record says.**
  The session-scratchpad copy of `task3-mach_kernel-final`, 1490352 bytes, SHA-256
  `1C0F8B804A5ECEF5124B3FCE9C3335356B7692B7C1FD11E2A40CFD6B87F7215D`,
  `_FBAllocateVBEConsole` `0x001E89F0`, `_VBEModeInfo2IODisplayInfo`
  `0x001E87D4`, `_BasicAllocateConsole` `0x001E214C`, all three `n_type 0x0F`.
  It is still in a **session scratchpad**, which is not durable; the fallback
  remains a rebuild from `760961e1d`.
- **The reference's 72 bytes reproduce exactly.** Read straight out of
  `mach_kernel_i386` at `_BasicAllocateConsole` = `0x00197C58`, the 72 bytes
  are byte-for-byte the dump recorded above. Resolving the three `e8`
  displacements against the slice's own symbol table gives
  `fn+10 -> 0x0019ECB8 _FBAllocateVBEConsole`, `fn+31 -> 0x00101600 _bzero`,
  `fn+57 -> 0x0019B760 _VGAAllocateConsole` — the three names check 3 requires
  our build to call. **[These offsets are the `e8` call-opcode bytes. Pass 3
  below reports the same three calls by their rel32 operand, one byte later
  — fn+11/32/58.]**

#### Still owed

Checks 1, 2 and 3, and check 4's second half. Nothing in this pass changes what
Task 4's code should be, and nothing in it is evidence that the code is right.
**Task 5 must still not start until check 4 has actually been run**, against a
built kernel, using the comparison form measured above.

**[SUPERSEDED — check 4 has since been run (pass 3, below) and passes under
the re-specified same-session A/B control. Task 4 is complete; see
"Task 4: resolved" at the end of this section.]**

### Task 4 verification pass 3, 2026-09-22: built; checks 1-3 pass; check 4 as written fails

The source is unaltered (`e2d02efe8`). This pass built it, ran all four checks,
and added one control boot when check 4 failed. **Check 4, in the form the
previous pass wrote down, fails.** The control says why, but it does not change
the verdict. Choosing a different gate is not this record's decision.

| Check | Result |
|---|---|
| 1. both symbols defined and external | **pass** |
| 2. Task 2's 539-byte extent | **pass**, MATCH 411/411 |
| 3. `_BasicAllocateConsole` byte oracle | **pass**: 72 bytes, 60/60 unmasked bytes identical, all three targets correct |
| 4. against `shots-t4v-pre2`/`-preB` | **FAIL**: one serial line differs after sorting, and the settled frames differ outside the clock (see below) |

#### The build, and how the guest was kept alive

All **[measured]**:

- Before the build, the guest had been up 15 minutes. It had 50534 free pages
  and 997020 KB free on `/`, and `ps aux` showed nothing busy. The load
  averages still read 2.2-3.0, so that number means nothing on this box.
- `vm/sync-src.ps1 -Path kernel-7` from this worktree completed. On the guest,
  `BasicConsole.c:32` carries the import and `:265` the call.
- The profile workaround is Task 3's `sed`, verbatim, writing
  `/tmp/task4c-gcc-darwin.conf`. `diff` against the repo profile shows only
  line 16, `path=`.
- The build ran in the foreground of **one** SSH session, `ssh -T ...
  /bin/sh -s`, with the script on stdin. The host ran it as a background job
  and never polled it. rbuild's output went to `/tmp/task4c-build.log` on the
  guest. The same session then printed that log in full, extracted the kernel
  and printed it `uuencode`d, so no second session was needed to get it back.
- The command:

  ```
  rbuild kernel --state /build/state --toolchain /tmp/task4c-gcc-darwin.conf \
    --arch i386 /build/src /build/repo /tmp/task4c-kvbe-dst
  ```

  It ran from 16:24:54 to 16:47:55 guest time and ended with `rbuild: kernel
  complete`, exit 0, producing eight APKs. `BasicConsole.c` compiled with
  **no diagnostic**. The only diagnostic from `FBConsole.c` is Task 2's known
  cast warning at line 1477.
- **The guest stayed healthy.** Every SSH connection in this pass was accepted:
  two pre-checks, the sync's two sessions and the build session. At the end of
  the build the load averages read 3.05/3.25/3.29 and 40407 pages were free.

#### The kernel

`./mach_kernel` from `kernel-154.5.1-7-i386.apk` is 1490352 bytes. On the
guest, `sum` gives `8583 1456` and `cksum` gives `3886786274 1490352`. The
uudecoded local copy reproduces both. Its SHA-256 is
`74B12FCD53E886AAFCBB29AD400C5DEDD10B26F04BBA0FBC6E02DAEFEA25CFF4`. The
embedded banner reads `Tue Sep 22 13:46:24 PDT 2026` **[measured]**. That is
2h38m *before* the 16:24:54 guest-time build start recorded above under "The
build" - the two are only consistent if the guest's shell clock (used for
"guest time" throughout this pass) and the clock the build stamps into
`version[]` differ by an unstated ~3 hours. **Not determined:** which clock is
correct, or why they disagree; both readings are reported as measured from
their respective sources.

It is retained as a gitignored file in the worktree,
`vm/work/task4c-mach_kernel`, with a second copy in the session scratchpad.
The pre-Task-4 kernel was copied beside it as `vm/work/task3-mach_kernel-final`
(SHA-256 `1C0F8B80...215D`, re-checked). **Both copies survive the session but
not a worktree cleanup.** Neither is durable beyond that. If they are lost,
the fallback is to rebuild from `e2d02efe8` - **but that rebuild cannot
reproduce the recorded SHA-256s**: the embedded `version[]` build stamp (serial
line 4, and the clock-offset question noted above) changes on every rebuild,
and the boot captures themselves cannot be regenerated either, because of the
cross-session drift this pass measured (2,518 px between two boots of the
identical pre-Task-4 kernel on the same day). The committed hashes in this
record are the only durable trace of what was actually measured.

#### Checks 1-3

**[measured]** The results, check by check:

- **Check 1.** Guest `nm` and the local Mach-O parse agree:
  `_VBEModeInfo2IODisplayInfo` is at `0x001E87DC`, `_FBAllocateVBEConsole` at
  `0x001E89F8` and `_BasicAllocateConsole` at `0x001E214C`. All three have
  `n_type 0x0F`.
- **Check 2.** `compare_kvbe.py` reports `MATCH: all 411 compared bytes
  identical`, and the dispatch and all 31 table targets agree relative to the
  entry. The extent moved by +8 (`0x001E87D4` to `0x001E87DC`), which is still
  `0 mod 4`. Its SHA-256 is now
  `6CA497348D3D3F7F1A90E8C849A87A576CB37438C84E10AD34DE459CD5599800`. As
  before, the moved hash comes entirely from the masked absolute bytes.
- **Check 3.** Decoding from the symbol to the first `ret` gives **72 bytes**:

  ```
  5589e581ec8800000053e89d68000085c0752b68880000008d9d78ffffff53e8
  d0eaf1ffc78578ffffff80020000c7857cffffffe001000053e8e63a00008b9d
  74ffffff89ec5dc3
  ```

  Masking the rel32s at fn+11, 32 and 58 leaves 60 bytes, all identical to
  the reference. **[These offsets are the rel32 operands, one byte after
  pass 2's `e8` opcode offsets fn+10/31/57 above; both are correct, just
  different conventions.]** The three calls resolve against our own symbol table to
  `_FBAllocateVBEConsole` (`0x001E89F8`), `_bzero` (`0x00100C40`) and
  `_VGAAllocateConsole` (`0x001E5C70`), in that order. The `jne` lands on
  fn+62, as the reference's does. The eight bytes after the `ret`
  (`55 89 e5 83 ec 10 57 56`) also equal the reference's. The stripped kernel
  has no local symbols, so the size comes from the decode. The distance to the
  next symbol is not a size.

#### Check 4 as written: fails, in two ways

The method is the recorded one. `graft-kernel.py` wrote a fresh
`vm/work/test.img`, and `/mach_kernel` read back from it matches the SHA-256
above. Then `qemu-shot.py --at 30,60,95 --keys $'mach_kernel -v\n' --keys-at 8`
captured the boot into `vm/shots-t4c-post/`. Both comparisons are against the
morning baselines. **[measured]**

1. **The sorted serial diff is not empty.** Exactly one line differs, serial
   line 4: `Sun Sep 20 15:00:37 PDT 2026; root(rcbuilder):...` against
   `Tue Sep 22 13:46:24 PDT 2026; ...`. This is the kernel's `version[]`
   banner. It sits at file offset `0x13A102` in both kernels, and this
   build's own log shows the build writing it (`char version[] = "Kernel
   Release 5.3:\nTue Sep 22 13:46:24 PDT 2026; ...`). Every rebuild changes
   this line. The noise floor was measured by booting one kernel twice, so it
   could not show this line moving.
2. **The settled frames differ outside the clock.** The 60 s and 95 s frames
   differ by 2500 pixels from `pre2` and 2502 from `preB`, not 48. The top
   five visible text rows are different text. The eight
   `intr: phantom IRQ 15, EOI to master` lines now come *after*
   `Power management is enabled.`, at serial lines 53-60. In the baselines
   they fell inside the IDE probe: lines 28 and 33-39 in `pre2`, 37-44 in
   `preB`. So they are what fills the top of the screen. The clock lines then
   differ in the seconds field: init at `05:00:13` here against `05:00:28`
   in `pre2`. The boot had also settled by 30 s (all three frames are
   identical), where the morning's 30 s frames were still scrolling.

#### The control that was added once check 4 failed

Two more boots went through the same procedure, on this host, within minutes
of the first. **[measured]**

- `vm/shots-t4c-preC/` is the **pre-Task-4** kernel,
  `task3-mach_kernel-final`, re-booted now. `/mach_kernel` in the image was
  read back and verified.
- `vm/shots-t4c-post2/` is the new kernel booted a second time.

| Pair | serial | 60 s / 95 s frames |
|---|---|---|
| `preC` vs `pre2` | equal as sorted multisets | **2518 px**, the same five rows as above |
| `preC` vs `post` | same 76 lines **in the same order**; only line 4, the banner, differs | 30 px, the clock ones digits only (text row 6 col 14, row 7 col 18) |
| `preC` vs `post2` | same as above | **0 px**: pixel-identical, same PNG SHA-256 |
| `post` vs `post2` | byte-identical | 30 px, the clock ones digits only |

The pre-Task-4 kernel, booted today, shows the same shift from the morning
baselines that the new kernel does. So difference 2 above is not a property
of the Task 4 kernel. Booted side by side under the same conditions, the two
kernels differ by exactly one serial line, the build banner, and by at most
the clock digits on screen.

**Not determined:** why today's boots reach init about 14 guest seconds sooner
than the morning's, and why that moves the phantom-IRQ block. Two things were
ruled out. It is not the image: `golden.img` was last modified 2026-07-24,
before both sets of runs. It is not the kernel: the `preC` control rules that
out. Any statement about host load at 10:02-10:08 would be a guess, and none
is made here.

#### What this does and does not settle

- **As written, check 4 FAILS.** The gate named the `pre2`/`preB` captures as
  its baseline and required an empty sorted diff. Neither condition holds.
  Task 4 stays **BLOCKED** on check 4 until someone decides whether it may be
  read as:
  (i) the sorted serial diff, excluding the build-banner line, **and**
  (ii) a pre-Task-4 control booted in the same session as the kernel under
  test, standing in for a baseline captured at another time.
- Read that way, the recorded captures pass. `post2` is pixel-identical to
  `preC`, and `post`/`post2` differ from `preC` only in line 4 of `serial.log`.
  **[inference: that conclusion depends on accepting (i) and (ii), which this
  pass did not decide]**
- Nothing here needed the new arm to run. No producer was stubbed, no guard
  weakened and no debug override added.

Captures retained in the worktree. They are gitignored and uncommitted, and
all three frames of each run hash the same:

```
vm/shots-t4c-post/   serial.log  9807128aa606ae7d0abcbae617ec2248f782d7b596d00fb51a3e89454a53a262
                     shot-{30,60,95}s.png  ceef59251f9788ea79a5b30342ddce4e9d6fbf86279004344d3a9ed13c70fae5
vm/shots-t4c-post2/  serial.log  9807128aa606ae7d0abcbae617ec2248f782d7b596d00fb51a3e89454a53a262
                     shot-{30,60,95}s.png  125c4133b06bb46e8e3d06262ef225c9f44fb3ecce0bc933cf639ffbc4474f76
vm/shots-t4c-preC/   serial.log  ba96aebab0223c392852ef7fdf031cb1ac5ff1349175c8e410aac9c0a768c51e
                     shot-{30,60,95}s.png  125c4133b06bb46e8e3d06262ef225c9f44fb3ecce0bc933cf639ffbc4474f76
```

### Task 4: resolved — the gate is a same-session A/B control, and check 4 passes

The "someone decides" above has been decided, and on grounds that do not
depend on the result: booting one kernel twice to get a fixed morning
baseline cannot see rebuild artefacts (the `version[]` build stamp) or
cross-session drift (this pass's own 2,518 px shift between two same-day
boots of the unchanged pre-Task-4 kernel), so a gate built on that baseline
was measuring the environment, not the kernel. The correction, and the
reasoning for it, live in the plan, not here - see
`docs/superpowers/plans/2026-09-21-i386-vbe-kernel-support.md`, the section
headed **"The console comparison: a same-session A/B control"**. The gate is
now: boot a pre-Task-4 control and the candidate back to back, in the same
session, on the same unmodified image; the sorted `serial.log` diff excluding
line 4 (the build stamp) must be empty, and frame differences must be
confined to the boot-clock digits.

**Under that gate, check 4 passes.** The measured numbers, controller-verified
(same captures as above - `vm/shots-t4c-preC/`, `vm/shots-t4c-post/`,
`vm/shots-t4c-post2/`):

| Comparison | Serial, excl. line 4 | 60 s / 95 s frames |
| --- | --- | --- |
| old kernel, morning vs later (the control) | 0 lines | 2,518 px, rows 42..121 |
| old vs new, same session, boot 1 | 0 lines, **0 even unsorted** | 30 px, rows 102..121 (clock) |
| old vs new, same session, boot 2 | 0 lines | **0 px — pixel-identical** |

The control row is what condemns the fixed-baseline gate: the pre-Task-4
kernel, which cannot contain Task 4's change, fails the old gate's "identical
to the morning capture" test just as badly as the new kernel did. Measured
against the control instead - the only comparison that isolates Task 4's
change from the environment - the new kernel differs from the pre-Task-4
kernel by nothing but its own build stamp and, on one of two boots, the
clock's seconds digits.

With checks 1-3 already passing (verification pass 3, above) and check 4
passing under this gate, **Task 4 is complete.**

## Task 5: the boot gates

The full gate record is `docs/kernel/i386-vbe-console.md`: procedure, hashes
of every input and capture, and what the gates do and do not establish. This
section keeps the measurements that bear on the kernel functions, and the
corrections to earlier statements in this record and in the plan.

**Result: all three gates pass.** Gate 2 (`sarld` links spec 1's driver
against the new kernel) and Gate 3 (it loads and registers as `VBEDisplay0`)
pass on positive evidence from the kernel's `serial.log`. The default
graphics-mode boot of the new kernel is indistinguishable from the pre-Task-4
kernel's, over five alternating boots in one session.

### Inputs, verified before use

All **[measured]**, 2026-09-22, just before the first boot:

- `git status src/kernel-7` at `f853aae61`: clean. No sync and no build in
  this task. Comment-stripped `BasicConsole.c` is identical at `e2d02efe8` and
  at `HEAD`, and no other kernel source changed between them, so the Task 4
  kernel is the current source.
- New kernel `vm/work/task4c-mach_kernel`, SHA-256 `74B12FCD...25CFF4`.
  Control `vm/work/task3-mach_kernel-final` and its scratchpad twin, both
  `1C0F8B80...215D`.
- Driver `_reloc` `77399531...8A3A36A1`, equal to spec 1's ledger
  `rebuilt_sha256`.
- `golden.img` SHA-256 `E1968E3EF57F3060AA01CEAB8B4D5C49C067E6ACC5F8626EBABEEFE0E663879F`.
  This replaces Task 4's mtime-only statement with a hash, though it cannot
  say retroactively what the image held that morning.
- Each boot image was read back after it was built: `/mach_kernel`, and for
  the with-driver boots every installed bundle file, all hash-equal to their
  sources.

### Gate 2 and Gate 3, in brief

Three verbose boots were run back to back: new kernel without the driver,
with it, then without it again (`A1`, `B`, `A2`). **[measured]**

- `B`'s log carries, after `Registering: EISA0`:
  `VBEDisplay0: VESA video driver initialization.`,
  `VBEDisplay0: Skipping framebuffer initialization (card not in VBE mode).`,
  `VBEDisplay0: Driver loaded to export VBE mode list.`,
  `VBEDisplay0: No VBE modes found.`, `Registering: VBEDisplay0`.
- Every one of the 12 devices `A1` and `A2` register is still registered in
  `B`. That no-cascade check is structurally weak, for two reasons: the driver
  links last in `Boot Drivers`, so a failure of its own link could not have
  removed an earlier driver; and, *[inference]*, an undefined-symbol failure
  like this one does not cascade at any position — `docs/boot/sarld-driver-link-limit.md`'s
  cascade is specific to a malloc fatal (`rld(): virtual memory exhausted`),
  raised through `fatal()`/`cleanup()`, not through the `error()` path an
  undefined symbol takes (`src/cctools-2/ld/symbols.c:3523`, `ld.c:2059`,
  `rld.c:402-405`).
- `B` against `A2`, in order, differs in the five driver lines and in line 9.
  Line 9 reads `vm_page_free_count` `3c8c`, becoming `3c8b` with the driver:
  one page fewer. *[inference]* That page is the booter's allocation for the
  linked driver.
- **Negative control.** The pre-spec-2 kernel
  (the main checkout's gitignored `vm/install/mach_kernel`, `9916E7C0...21CF8D`) has neither
  `_VBEModeInfo2IODisplayInfo` nor `_FBAllocateVBEConsole`. Booted with the
  same bundle, it stops at the booter with
  `rld(): Undefined symbols: _VBEModeInfo2IODisplayInfo`, captured in
  frame. The kernel then logs
  `configureDriver: driver class 'VBE20DisplayDriver' was not loaded`.
  The undefined-symbol part of spec 1's prediction is now measured, not
  argued. Its cascade and panic were not seen, but this run also linked the
  driver last, where neither could show; that they would not occur elsewhere
  rests on the *[inference]* in the no-cascade bullet above.

### What the booter hands the kernel, measured in guest memory

This is the measurement that matters most for Tasks 3 and 4.

A boot script saved guest physical `0x11000..0x131FF` with QMP `pmemsave`
at fixed times. It uses the same QEMU arguments and QMP client as
`qemu-shot.py`, imported from it. Two boots of the new kernel were dumped: the
default graphics-mode boot, at 12, 16, 30 and 60 s, and a verbose boot, at
12, 30 and 60 s. **[measured]**

- **`kbs+0x1854` and `kbs+0x1858` are zero** at every sample on both boots,
  as is the rest of `_reserved` (`0x1138C..0x130D7`). So
  `FBAllocateVBEConsole`'s guard sees zero, as D2 and Task 3 argued. That
  claim now rests on a measurement of the running guest, not only on reading
  the booter's `bzero`.
- **`boot_video` (`0x130D8`, 24 bytes) is zero on both boots**, including
  `v_baseAddr`.
- The graphics-mode and verbose dumps differ in two fields only:
  - `bootString`: empty on the graphics boot, `" -v"` on the verbose one.
  - `graphicsMode` at `0x1114C`: 1 on the graphics boot, 0 on the verbose one.

  The graphics-mode boot hands the kernel no extra video information anywhere
  in that range.
- `magicCookie` at `0x110A4` reads `0xA7A7A7A7` and `numBootDrivers` at
  `0x11154` reads 6. That is consistent with our `KERNBOOTSTRUCT` layout at
  the front of the struct. *[inference]* That the booter's struct matches ours
  as far as `boot_video` follows from that and is not independently checked.
  The "only two fields differ" statement above does not depend on it.

### Corrections

- **The booter these boots run is not `src/boot-2`.** The booter on
  `golden.img` is Apple's `boot` v5.0.41.1: 39,616 bytes, `AA06C3C5...F6B5F2C2`,
  byte-identical to `/usr/standalone/i386/boot` and to both boot-area copies.
  It contains no `Graphics Mode` string. **[measured]**
- **The plan's "graphics mode ... the only path on which the booter writes
  `video.v_baseAddr`" does not hold for that booter.** `v_baseAddr` is zero on
  its graphics-mode boot. **[measured, above]**
- **Task 4's statement about `v_baseAddr` needs one qualification.** Task 4's
  design-question bullet says the booter "already writes it today"
  (`graphics.c:200-208`). That is correct as a reading of `src/boot-2`,
  *conditional* on its `setMode()` taking the VBE branch. That branch needs a
  `Graphics Mode` key (`graphics.c:189-190`), which this image's
  `System.config` does not set. **[read from source and from the table]** So
  on this image the discarded guard would have been dormant under either
  booter. The decision to drop it does not change: it rests on the
  reference's shape, the first three bullets of that section.
- **Typing a kernel name suppresses graphics mode on this booter.** Typing
  `mach_kernel` and Return at 8 s gives a text-mode boot. Only an untouched
  countdown gives the graphics panel. So the plan's "Use `--keys-at 8`" for
  the graphics-mode step is wrong for that step: the graphics-mode boots here
  sent no keys. **[measured]**
- **The phantom-IRQ race is wider than the plan's comparison rule names.**
  All 14 boots of this session log exactly eight
  `intr: phantom IRQ 15, EOI to master` lines. Between boots of the *same*
  kernel, those lines move: before or after `Power management is enabled.`,
  split around it, or partly into the IDE probe block. On the verbose console
  this reaches the settled frame: 490 px in text row 4 between two
  no-driver boots of the same kernel. **[measured]** Outside those eight
  lines, every same-configuration pair matches line for line.
- **No gate rests on this widened rule.** The planned A-B-A (`dC1`/`dN`/`dC2`)
  passes the plan's rule 2 ("The comparison, tightened"), unmodified, with empty raw diffs; only the extra
  pairs `dC2`/`dN2` and `dN2`/`dC3` needed the exclusion.

### The graphics-mode A-B-A

The boots ran control, new, control, new, control (`dC1`, `dN`, `dC2`, `dN2`,
`dC3`), with no keys. **[measured]**

- Serial: identical for every adjacent pair once line 4's date is masked and
  the phantom lines are left out of the order. Line 4's config and version
  text is identical.
- Settled frames at 45, 60, 95 and 120 s: **0 px for every pair**, no mask
  needed. All five hash to `C0F78DDB...7C247ED`.
- Transient frames vary with timing. At 24 s and 30 s `dN` was ahead of
  both `dC1` and `dC2`. The extension was run to test that: `dN2` fell back
  to the controls' timing and `dC3` showed `dN`'s lead. The lead is not a
  property of either kernel.

A graphics-mode boot with the driver (`dB`) prints the same five driver lines,
and its settled frames are pixel-identical to `dN`'s.

### `_VBE20DisplayDriver_instance`

Spec 1 flagged this difference as the one that might matter at load time: the
reference leaves the symbol an unallocated common, while our `kl_ld`
allocates it in `__common`. **It caused no trouble.** The driver linked,
instantiated, initialised and registered. **Not established:** whether
anything read the symbol during these boots.

### Harness notes

- **`vm/install-driver.py` fails on this host.** It runs `cp -c`, a macOS
  clone flag, and GNU cp 8.32 rejects it. This run used a scratch wrapper that
  imports the tool unchanged and replaces only that call with
  `shutil.copyfile`. The harness itself was not modified.
- In the successful verbose boot, the booter screen survives under a second
  after Return, and the last frame before the kernel console ends on
  `Loading binary for VBE20DisplayDriver device driver.`, before the link
  result. A frame capture cannot show that result in the passing case.
  Hence the serial-only gate.

### Still open

- The frame-buffer console. Nothing has run `FBAllocateVBEConsole` past its
  guard, and nothing will until spec 3 writes `kbs+0x1854`/`+0x1858`.
- `VBEModeInfo2IODisplayInfo` at runtime. The driver links against it, but the
  "Skipping" path never calls it.
- These captures cannot be regenerated. See the gate record.
