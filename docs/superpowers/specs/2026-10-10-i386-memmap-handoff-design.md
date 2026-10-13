# i386 memory map hand-off: booters to kernel

Date: 2026-10-10. Status: implemented and verified on QEMU.

Results (master + this branch + the drvPExpert makedepends fix, 128 MB):

- boot2 is 38416 of 45056 bytes (6640 to spare).
- BIOS, new boot2: `memory map: 6 ranges, top 0x7fe0000`, physical
  memory 127.87 MB. 6 of 6 stall-mode builds that booted completed with no
  `pmap_remove_all` panic (2 more never answered on ssh, the image's known
  early-sshd failure); without this change the same kernel panicked in 4
  of 7.
- BIOS, the image's old boot2: `no memory map, using extmem`, 128.00 MB,
  build completed.
- UEFI (golden.img copy, ESP-only disk with the new loader, 256 MB):
  `memory map: 13 ranges, top 0xed0b000`, 237.04 MB; the top is the start
  of the first RuntimeServicesData descriptor and equals the loader's own
  contiguous extmem.

## Problem

The i386 kernel treats firmware-reserved memory as ordinary RAM. On a
128 MB QEMU guest it reports `physical memory = 128.00 megabytes` and
manages the ACPI area at `0x07fe0000`..`0x08000000`, which the firmware's
memory map marks reserved. Master's drvPExpert reads the ACPI tables at
boot through `pexpert_map_physical`, which enters wired, cache-disabled
kernel mappings for those pages (`pmap_enter_cache_spec(kernel_pmap, ...,
wired=1)`). The VM later hands the same physical page to a task and, when
it takes it back, `pmap_remove_all` finds the wired kernel mapping:

    vm_allocate -> vm_map_find -> vm_map_insert -> vm_object_coalesce
      -> vm_object_page_remove -> pmap_remove_all(0x07fe0000)
      -> panic: pmap_remove_all 3

4 of 7 booted stall-mode builds on the master+pexpert kernel panicked this
way. Before pexpert nothing read ACPI, so using that RAM was harmless.

The root cause is that no booter passes the firmware memory map to the
kernel:

- boot-2 reads the BIOS E820 map in `sizememory()`, sums the usable
  entries, and discards the map. Only `convmem`/`extmem` reach the kernel.
  The sum is wrong whenever there is a hole.
- bootefi-1 reads the EFI memory map, reduces it to a contiguous span in
  `efi_sizemem()`, and frees it.
- kernel-7 `size_memory()` manages one range, `[end_of_image,
  KB(extmem))` (or `KB(maxmem)`).

## Goal

When the booter knows the firmware memory map, the kernel never manages
memory the map does not mark usable. Booters that predate this keep
working exactly as today.

Success:

- On a 128 MB QEMU guest booted by the new boot2, the kernel's top of
  physical memory is `0x07fe0000`, the boot line reports the map, and 8
  stall-mode builds on the master+pexpert kernel show no
  `pmap_remove_all` panic (baseline: 4 of 7).
- Booted by bootefi-1 (golden.img snapshot, bundled firmware), the kernel
  reports the map and the same top.
- Booted by an old booter, the kernel's memory size is unchanged and the
  boot line says no map was passed.

## Prior work reused

The unmerged branch `worktree-i386-large-memory` already designed the
interface and the BIOS side (see its
`docs/superpowers/specs/2026-09-25-i386-highmem-design.md`). This work
takes:

- `a2238f621` "boot: carry a physical memory map in kernBootStruct"
- `93d35f479` "boot: report the contiguous memory top instead of the E820
  sum" (also sets ES for the E820 call)
- `memmap_contiguous_top()` from `33754b94a`

and leaves out `2e8daf4d2` (clamping physical memory to the kernel
address space), a separate fix.

## Design

### 1. Interface: kernBootStruct

From `a2238f621`, applied to both copies,
`src/boot-2/i386/libsa/kernBootStruct.h` and
`src/kernel-7/machdep/i386/kernBootStruct.h` (bootefi-1 compiles against
the boot-2 copy):

    #define BOOT_MEMMAP_MAX  32
    #define BOOT_MEM_RAM     1          /* E820 type 1: usable RAM */

    struct boot_mem_range {
        unsigned int base;
        unsigned int end;               /* exclusive, <= 0xFFFFF000 */
        unsigned int type;              /* E820 type */
    };

    int              memMapCount;               /* 908: 0 == no map */
    boot_mem_range_t memMap[BOOT_MEMMAP_MAX];   /* 912 .. 1296 */
    char _reserved[5320 - 4 - BOOT_MEMMAP_MAX * 12];  /* 1296 .. 6228 */

The fields come from the head of `_reserved`. Every existing field,
including the 4.2 VBE offsets that binary drivers use, keeps its offset.
Typedef assertions pin `sizeof (boot_mem_range_t) == 12`, `memMapCount`
at 908 and `memMap` at 912. Ranges lie below 4 GB: a booter drops ranges
wholly above it and clips a range that crosses it. `type` is an E820
type; a UEFI booter translates.

### 2. BIOS booter (boot-2)

From `93d35f479`, rebased onto master's `sizememory.c`:

- E820 writes straight into `kernBootStruct->memMap` and `memMapCount`
  (`getKernBootStruct()` zeroes the struct before sizing, so the map
  survives).
- `extmem` becomes the top of the contiguous usable run from 1 MB, less
  1 MB, instead of the sum of usable entries.
- `getMemoryMap()` sets ES for the INT 15h call.
- The E801 and INT 88h fallbacks, and the Left-Shift override, are
  unchanged and leave `memMapCount` 0.

The branch's code is kept as written, including its 32-bit E820
arithmetic. boot2 is 38432 of 45056 bytes, so the build's size check is
not expected to bite.

The kernel uses `KB(extmem)` as an absolute top, about 1 MB below the
real end, when no map is passed. That pre-existing undercount is left as
is; with a map the kernel no longer reads `extmem`.

### 3. UEFI loader (bootefi-1)

A new pure function, in its own file so the host tests can link it:

    /* Translate an EFI memory map to E820 ranges below 4 GB.
       Returns the count written, or 0 if the usable ranges alone do
       not fit in max. */
    int efi_to_e820(const void *map, UINTN size, UINTN dsize,
                    boot_mem_range_t *out, int max);

- Type mapping: `EfiConventionalMemory`, `EfiBootServicesCode/Data`,
  `EfiLoaderCode/Data` → 1 (same set as `efi_usable()`);
  `EfiACPIReclaimMemory` → 3; `EfiACPIMemoryNVS` → 4; every other type →
  2.
- Ranges are clipped to 4 GB (end capped at `0xFFFFF000`), sorted by
  base, and adjacent ranges of the same type are merged.
- If more than `max` remain, usable ranges are kept first, then the rest
  in address order. If the usable ranges alone exceed `max`, it returns 0
  and the kernel falls back to `extmem`; half a map is never passed.

`handoff.c` calls it on the final map, after the `GetMemoryMap` that
succeeds and before `ExitBootServices`, writing into
`KERNSTRUCT_ADDR->memMap`. The boot struct area (0x11000) is already
reserved by `efi_reserve_ranges()`, so no allocation is needed and the
map key stays valid. `efi_sizemem()` and its `convmem`/`extmem` are
unchanged.

### 4. Kernel (kernel-7)

`memmap_contiguous_top()` moves into its own file,
`machdep/i386/memmap.c` (listed in `conf/files.i386`), so the host tests
can link it:

    /* Top of the contiguous usable run starting at 1 MB.  Entries need
       not be sorted.  Returns 0x100000 when no usable range adjoins
       1 MB. */
    vm_offset_t memmap_contiguous_top(boot_mem_range_t *map, int n);

`size_memory()` in `i386_init.c`:

- reads `memMapCount`, clamped to `0..BOOT_MEMMAP_MAX` (the struct is
  written by code the kernel does not control);
- with a map whose top is above 1 MB, `end_of_memory` = that top;
  otherwise `KB(extmem)` exactly as today;
- `maxmem=` may lower `end_of_memory` but not raise it past the map top;
- prints one line: `memory map: N ranges, top 0x%x` or
  `no memory map, using extmem`.

Everything else is unchanged: one `mem_region`, single-range
`managed_page`. ACPI and reserved pages above the top fall outside the
managed range, so pexpert's wired mappings of them create no pv entries
and never meet the VM. pexpert is not changed.

## Testing

Host unit tests, following the existing `tests/` directories:

- `src/kernel-7/machdep/i386/tests/memmap_test.c`:
  `memmap_contiguous_top()` with unsorted entries, a hole at 15 MB, ACPI
  at the top of RAM, no usable range at 1 MB, adjoining ranges that touch
  exactly, and a count of 0.
- `src/bootefi-1/tests/efi_memmap_test.c`: `efi_to_e820()` with each
  type class, a range crossing 4 GB, a range wholly above 4 GB, merging
  of adjacent same-type ranges, a non-default descriptor size, overflow
  that keeps usable ranges first, and overflow of usable ranges (returns
  0).
- The new offsets are pinned by the `__kbs_` typedef assertions in both kernBootStruct.h copies.

Guest tests (QEMU, never on shared images; see CLAUDE.md):

1. BIOS: install the new boot2 on a throwaway copy of the bench image and
   boot the master+pexpert kernel at 128 MB. Expect `memory map: N
   ranges, top 0x7fe0000` and physical memory just under 128 MB. Run 8
   stall-mode builds; expect no `pmap_remove_all` panic.
2. Old booter: boot the same kernel with the image's own boot2. Expect
   `no memory map, using extmem` and today's memory size.
3. UEFI: boot a golden.img snapshot with the bundled edk2 and bootefi-1.
   Expect the map line and the same top.

## Out of scope

- Multiple memory regions in the i386 pmap (`managed_page`, `pg_desc`,
  `pmap_init`): the later refactor (option 3) that would let memory above
  a hole be used.
- Clamping physical memory to the kernel address space (`2e8daf4d2`).
- pexpert's mapping of managed pages, which this makes unreachable for
  ACPI tables in reserved memory.
- `CONFIG_SIZE` differs between the two `kernBootStruct.h` copies
  (booter `13*4096`, kernel `12*4096`); by hand arithmetic the booter's
  struct would reach past `0x20000` (EISA config). Unverified; noted for a
  separate check.
