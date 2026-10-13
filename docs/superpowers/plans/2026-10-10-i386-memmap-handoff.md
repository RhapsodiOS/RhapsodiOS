# i386 Memory Map Hand-off Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pass the firmware memory map from boot-2 (E820) and bootefi-1
(EFI map) to the i386 kernel in `kernBootStruct`, and have the kernel stop
managing memory above the top of the contiguous usable run from 1 MB.

**Architecture:** Reuse the `worktree-i386-large-memory` branch's
`kernBootStruct` fields (offsets 908/912) and its boot-2 E820 commit. Add
a pure EFI→E820 translator to bootefi-1, called on the final memory map
before `ExitBootServices`. Move the kernel's `memmap_contiguous_top()`
into its own file and use it in `size_memory()`.

**Tech Stack:** C (gnu89, 1999-era NeXT/Darwin code), boot-2 and
kernel-7 built on the i386 Rhapsody guest with rbuild, bootefi-1 and host
unit tests built on Windows with clang (`C:\Program Files\LLVM\bin`) and
scoop `make`.

**Spec:** `docs/superpowers/specs/2026-10-10-i386-memmap-handoff-design.md`

## Global Constraints

- Work in worktree `D:\RhapsodiOS\.claude\worktrees\i386-memmap`, branch
  `i386-memmap`. Never `cd` to `D:\RhapsodiOS`.
- Commit messages: one or two lines, subsystem prefix (`boot: `,
  `bootefi: `, `kernel: `), describe the change, **no metadata or
  trailers** (CLAUDE.md overrides any attribution instruction).
- Match surrounding style (tabs/4-space mix as in the file). Surgical
  changes only.
- Legacy sources may hold Mac-Roman bytes: before editing a file, check
  `grep -c -P '[^\x00-\x7F]' FILE`; if non-zero, edit via a latin-1 Python
  script, not the Edit tool.
- `git archive`/`git show` of these trees: use `git -c core.autocrlf=false`.
- Host tools: prefix commands with
  `PATH="/c/Program Files/LLVM/bin:$PATH"`. Never pass `LINK=` to make.
- `kernBootStruct` fields: `int memMapCount` at offset 908 (0 == no map),
  `boot_mem_range_t memMap[32]` at 912..1296, each `{unsigned base;
  unsigned end /* exclusive, <= 0xFFFFF000 */; unsigned type /* E820 */}`,
  `BOOT_MEMMAP_MAX 32`, `BOOT_MEM_RAM 1`. No other field moves.
- E820 types: 1 usable, 2 reserved, 3 ACPI reclaimable, 4 ACPI NVS.
- Kernel boot line, exact text: `memory map: %d ranges, top 0x%x\n` or
  `no memory map, using extmem\n`.
- Subagents do not touch QEMU guests or disk images. Guest builds and boot
  tests (Task 5) are done by the controller.

## Review Focus

- A map with no usable range adjoining 1 MB (firmware oddity): the kernel
  must fall back to `extmem`, not end memory at 1 MB. Test in Task 3.
- `memMapCount` garbage (negative or > 32) from a buggy booter: clamp to
  0..32, never read past `memMap[32]`. Test in Task 3.
- `maxmem=` larger than the map top: must not raise memory above the map.
  Covered by Task 3's `memmap_end_of_memory` test.
- EFI descriptors with `DescriptorSize` larger than
  `sizeof(EFI_MEMORY_DESCRIPTOR)` (real firmware uses 48): stride by
  `dsize`. Test in Task 4.
- An EFI range at or crossing 4 GB, and one wholly above it: clip / drop,
  `end` never above `0xFFFFF000`. Test in Task 4.

---

### Task 1: kernBootStruct memory map fields

**Files:**
- Modify: `src/boot-2/i386/libsa/kernBootStruct.h`
- Modify: `src/kernel-7/machdep/i386/kernBootStruct.h`
- Test: host syntax check (no new file)

**Interfaces:**
- Produces: `boot_mem_range_t`, `BOOT_MEMMAP_MAX`, `BOOT_MEM_RAM`,
  `KERNBOOTSTRUCT.memMapCount`, `KERNBOOTSTRUCT.memMap[]`, as in Global
  Constraints, in both headers.

- [ ] **Step 1: Bring over the branch commit**

```bash
git cherry-pick a2238f621
```
Resolve conflicts, if any, so both headers carry exactly the fields and
assertions of `git show a2238f621` and keep every field master added
since.

- [ ] **Step 2: Verify both headers compile as i386 with the assertions**

Run, from `src`:
```bash
PATH="/c/Program Files/LLVM/bin:$PATH"
for h in boot-2/i386/libsa/kernBootStruct.h kernel-7/machdep/i386/kernBootStruct.h; do
  clang -m32 -fsyntax-only -I. -x c "$h" && echo "ok $h"
done
```
Expected: `ok` for both. (A failed `__kbs_*` typedef assertion shows as
"array size is negative".)

- [ ] **Step 3: Commit** (only if Step 1 needed a conflict fix; otherwise
the cherry-pick is the commit). Message: `boot: carry a physical memory
map in kernBootStruct`.

---

### Task 2: boot-2 hands the E820 map over

**Files:**
- Modify: `src/boot-2/i386/boot2/sizememory.c`
- Modify: `src/boot-2/i386/libsaio/biosfn.c`
- Modify: `src/boot-2/i386/libsaio/saio_internal.h`

**Interfaces:**
- Consumes: Task 1's `kernBootStruct->memMap`, `memMapCount`,
  `BOOT_MEMMAP_MAX`.
- Produces: `getMemoryMap(boot_mem_range_t *map, int max, int *count)`
  returning the contiguous top (bytes) as on the branch; `extmem` =
  `(top - 1MB) / 1024` when E820 worked.

- [ ] **Step 1: Bring over the branch commit**

```bash
git cherry-pick 93d35f479
```
Resolve against master's versions of the three files. Keep the branch's
logic: E820 fills `kernBootStruct->memMap` directly, ES is set for the
INT 15h call, Left-Shift / E801 / INT 88h fallbacks unchanged and leave
`memMapCount` 0.

- [ ] **Step 2: Verify `sizememory.c` and `biosfn.c` parse**

Run, from `src/boot-2/i386`:
```bash
PATH="/c/Program Files/LLVM/bin:$PATH" clang -m32 -fsyntax-only -w \
  -Ilibsa -Ilibsaio -I../../kernel-7 -I../../kernel-7/bsd boot2/sizememory.c libsaio/biosfn.c
```
Expected: no errors. (Warnings are suppressed; the boot2 sources predate
prototypes. If the host headers cannot satisfy an include, report the
exact error instead of shimming it; the controller builds on the guest.)

- [ ] **Step 3: Commit** (only if a conflict fix was needed). Message:
`boot: report the contiguous memory top instead of the E820 sum`.

---

### Task 3: Kernel sizes memory from the map

**Files:**
- Create: `src/kernel-7/machdep/i386/memmap.c`, `memmap.h`
- Modify: `src/kernel-7/machdep/i386/i386_init.c` (`size_memory()`)
- Modify: `src/kernel-7/conf/files.i386` (add
  `machdep/i386/memmap.c	standard` after the `i386_init.c` line)
- Test: `src/kernel-7/machdep/i386/tests/memmap_test.c`,
  `src/kernel-7/machdep/i386/tests/Makefile`

**Interfaces:**
- Consumes: Task 1's types.
- Produces (in `memmap.h`, which includes only `kernBootStruct.h`):
  - `unsigned int memmap_contiguous_top(const boot_mem_range_t *map, int n);`
    Top of the contiguous run of `BOOT_MEM_RAM` ranges starting at
    `0x100000`; entries unsorted; repeat until stable (the branch's
    algorithm in `33754b94a`). Returns `0x100000` when nothing adjoins it.
  - `int memmap_count(int raw);` clamps to `0..BOOT_MEMMAP_MAX`.
  - `unsigned int memmap_end_of_memory(unsigned int map_top, unsigned int maxmem_bytes, unsigned int extmem_bytes);`
    If `map_top > 0x100000`: `maxmem_bytes` if non-zero and lower, else
    `map_top`. Otherwise: `maxmem_bytes` if non-zero, else `extmem_bytes`
    (today's behavior).

- [ ] **Step 1: Write the failing tests** in `tests/memmap_test.c`
  (plain `assert`, `main` prints `memmap_test: ok`):

```c
/* QEMU 128 MB: low RAM, reserved BIOS, RAM 1MB..0x7fe0000, ACPI above */
boot_mem_range_t q[] = {{0,0x9fc00,1},{0x9fc00,0xa0000,2},{0xf0000,0x100000,2},
                        {0x100000,0x7fe0000,1},{0x7fe0000,0x8000000,2},{0xfffc0000,0xfffff000,2}};
assert(memmap_contiguous_top(q, 6) == 0x7fe0000);
/* unsorted, split RAM that touches exactly */
boot_mem_range_t u[] = {{0x400000,0x800000,1},{0x100000,0x400000,1}};
assert(memmap_contiguous_top(u, 2) == 0x800000);
/* ISA hole at 15 MB stops the run */
boot_mem_range_t h[] = {{0x100000,0xf00000,1},{0xf00000,0x1000000,2},{0x1000000,0x4000000,1}};
assert(memmap_contiguous_top(h, 3) == 0xf00000);
/* nothing adjoins 1 MB */
boot_mem_range_t n[] = {{0x200000,0x800000,1}};
assert(memmap_contiguous_top(n, 1) == 0x100000);
assert(memmap_contiguous_top(q, 0) == 0x100000);
assert(memmap_count(-5) == 0 && memmap_count(7) == 7 && memmap_count(1000) == BOOT_MEMMAP_MAX);
assert(memmap_end_of_memory(0x7fe0000, 0, 0x8000000) == 0x7fe0000);
assert(memmap_end_of_memory(0x7fe0000, 0x10000000, 0) == 0x7fe0000);  /* maxmem cannot raise */
assert(memmap_end_of_memory(0x7fe0000, 0x4000000, 0) == 0x4000000);   /* maxmem can lower */
assert(memmap_end_of_memory(0x100000, 0, 0x7f00000) == 0x7f00000);    /* no usable map: extmem */
assert(memmap_end_of_memory(0x100000, 0x4000000, 0x7f00000) == 0x4000000);
```

`tests/Makefile`: `CC ?= clang`, `-std=gnu89 -Wall -Werror -m32
-I.. -I../../..`, target `check` builds `memmap_test` from
`memmap_test.c ../memmap.c` and runs it.

- [ ] **Step 2: Run to verify it fails**

Run: `cd src/kernel-7/machdep/i386/tests && PATH="/c/Program Files/LLVM/bin:$PATH" make check`
Expected: FAIL (missing `memmap.c`/`memmap.h`).

- [ ] **Step 3: Implement `memmap.c` / `memmap.h`** with the three
functions above (APSL header like neighboring files).

- [ ] **Step 4: Run to verify it passes** — same command; expected output
`memmap_test: ok`. (If `-m32` cannot link on this host, drop it for the
test only and say so in the report.)

- [ ] **Step 5: Wire into `size_memory()`** in `i386_init.c`:
  - `n = memmap_count(kernBootStruct->memMapCount)`;
    `top = n ? memmap_contiguous_top(kernBootStruct->memMap, n) : 0x100000`;
  - `end_of_memory = memmap_end_of_memory(top, maxmem ? KB(maxmem) : 0, KB(extmem))`
    (use the file's existing KB-to-bytes helper/macro);
  - print the exact boot line from Global Constraints with `printf`.
  Keep everything else in `size_memory()` unchanged.

- [ ] **Step 6: Syntax-check the kernel file is not possible on the host;
  confirm by inspection that `i386_init.c` includes `memmap.h` and that
  `conf/files.i386` lists `memmap.c`.** The controller builds the kernel.

- [ ] **Step 7: Commit**

```bash
git add src/kernel-7/machdep/i386/memmap.[ch] src/kernel-7/machdep/i386/tests src/kernel-7/machdep/i386/i386_init.c src/kernel-7/conf/files.i386
git commit -m "kernel: end physical memory at the top of the booter's usable map"
```

---

### Task 4: bootefi-1 hands the EFI map over as E820

**Files:**
- Create: `src/bootefi-1/efi_memmap.c`, `efi_memmap.h`
- Modify: `src/bootefi-1/handoff.c` (after a successful `GetMemoryMap`,
  before `ExitBootServices`)
- Modify: `src/bootefi-1/Makefile` (add `efi_memmap.c` to the loader's
  sources, following how `efi_bootargs.c` is listed)
- Modify: `src/bootefi-1/tests/Makefile` (target `test-memmap`, built like
  `test-bootargs` with `ACPI_TEST_CFLAGS`)
- Test: `src/bootefi-1/tests/efi_memmap_test.c`

**Interfaces:**
- Consumes: Task 1's `boot_mem_range_t`, `BOOT_MEMMAP_MAX`; `efi.h`'s
  `EFI_MEMORY_DESCRIPTOR` and memory type enum.
- Produces: `int efi_to_e820(const void *map, UINTN size, UINTN dsize, boot_mem_range_t *out, int max);`
  - Types: `EfiConventionalMemory`, `EfiBootServicesCode/Data`,
    `EfiLoaderCode/Data` → 1; `EfiACPIReclaimMemory` → 3;
    `EfiACPIMemoryNVS` → 4; all others → 2.
  - Range = `[PhysicalStart, PhysicalStart + NumberOfPages * 4096)`.
    Drop if `PhysicalStart >= 0xFFFFF000`; cap `end` at `0xFFFFF000`.
  - Sort by base, merge ranges where `a.end == b.base && a.type == b.type`.
  - If more than `max` remain: keep all type-1 ranges first, then the rest
    in address order until `max`. If type-1 ranges alone exceed `max`,
    return 0 and write nothing meaningful.
  - Iterate descriptors with stride `dsize`, never
    `sizeof(EFI_MEMORY_DESCRIPTOR)`.
  - No dynamic allocation; a fixed local scratch array of 128 entries
    (ranges beyond 128 before merging: return 0).

- [ ] **Step 1: Write the failing tests** in `tests/efi_memmap_test.c`
  (build descriptors in a byte buffer with a chosen `dsize`; plain
  `assert`; print `efi_memmap_test: ok`):

```c
/* QEMU-like: conv 0..0xa0000, conv 1MB..0x7fe0000 split as
   BootServicesData + Conventional + LoaderData (merge to one),
   ACPIReclaim 0x7fe0000..0x7ff0000, NVS 0x7ff0000..0x8000000,
   MMIO 0xffe00000..0x100000000 (crosses the 0xFFFFF000 cap) */
n = efi_to_e820(buf, size, 48, out, BOOT_MEMMAP_MAX);
assert(n == 5);
assert(out[0].base == 0 && out[0].end == 0xa0000 && out[0].type == 1);
assert(out[1].base == 0x100000 && out[1].end == 0x7fe0000 && out[1].type == 1);
assert(out[2].type == 3 && out[3].type == 4);
assert(out[4].base == 0xffe00000 && out[4].end == 0xfffff000 && out[4].type == 2);
/* wholly above 4 GB dropped */
/* unsorted input comes out sorted */
/* dsize == sizeof(EFI_MEMORY_DESCRIPTOR) also works */
/* 40 alternating usable/reserved ranges, max 32: all 20 usable kept, then
   12 reserved; every out[i].type==1 range present */
/* 40 non-adjacent usable ranges, max 32: returns 0 */
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd src/bootefi-1/tests && PATH="/c/Program Files/LLVM/bin:$PATH" make test-memmap`
Expected: FAIL (missing `efi_memmap.c`).

- [ ] **Step 3: Implement `efi_memmap.c` / `efi_memmap.h`.**

- [ ] **Step 4: Run to verify it passes** — expected `efi_memmap_test: ok`.
Also run the existing `make test-bootargs test-sector test-acpi` to show
nothing else broke.

- [ ] **Step 5: Wire into `handoff.c`**: immediately after the
`GetMemoryMap` that returns success and before `ExitBootServices`:
`KERNSTRUCT_ADDR->memMapCount = efi_to_e820(map, size, dsize, KERNSTRUCT_ADDR->memMap, BOOT_MEMMAP_MAX);`
No allocation, no console output (it would change the map key).

- [ ] **Step 6: Build the loader** following
`memory: bootefi-windows-build-and-boot` (from `src/bootefi-1`):
`PATH="/c/Program Files/LLVM/bin:$PATH" make` with the documented
`-Wno-error=...` CC flags if needed. Expected: the `.efi` links.

- [ ] **Step 7: Commit**

```bash
git add src/bootefi-1/efi_memmap.[ch] src/bootefi-1/handoff.c src/bootefi-1/Makefile src/bootefi-1/tests
git commit -m "bootefi: hand the kernel the EFI memory map as E820 ranges"
```

---

### Task 5: Guest builds and boot tests (controller only)

- [ ] **Step 1: Build boot-2 and kernel-7 on the v2 build guest**
  (`vm/work/ffsbench/private3`, `rhap-i386-bootstrapped-v2.img` with
  `-snapshot`): sync `boot-2` and `kernel-7`, run `vm/build-i386-booter.sh`
  (expect `boot2/Makefile`'s "booter N bytes of 45056" line, N < 45056)
  and the kernel build (`ffs-kernel3.ps1`). For the master+pexpert test
  kernel, cherry-pick Tasks 1 and 3 onto `scratch-master-pexpert`.
- [ ] **Step 2: BIOS boot.** On a private copy of the bench root image
  (never a shared one), install the new boot2 (adapt `vm/install-booter.py`'s
  method; it only writes `vm/work/test.img`, so do not point it at a shared
  file). Boot the pexpert kernel at 128 MB. Expect
  `memory map: N ranges, top 0x7fe0000` and physical memory just under
  128 MB.
- [ ] **Step 3: 8 stall-mode builds** on that image with the pexpert
  kernel. Expect no `pmap_remove_all` panic (baseline 4 of 7, and 4 of 5
  with the vm_policy fix).
- [ ] **Step 4: Old booter.** Same kernel on the stock bench image. Expect
  `no memory map, using extmem` and `physical memory = 128.00 megabytes`.
- [ ] **Step 5: UEFI.** golden.img snapshot + bundled edk2 + the new
  bootefi `.efi` (vvfat ESP recipe). Expect the map line and the same top.
- [ ] **Step 6:** Record results in the spec's status line and commit
  (`docs: record the i386 memory map hand-off test results`).
