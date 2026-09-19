/* Prologue for compiling boot-2 sources (e.g. disk.c) under bootefi-1
 * without editing src/boot-2 itself.  boot-2's disk.c does
 * `static char * const intbuf = (char *)ptov(BIOS_ADDR);` — a compile-time
 * constant initializer.  BIOS_ADDR (0xC00) sits inside physical page 0,
 * which OVMF's null-pointer detection withholds from AllocatePages
 * (confirmed in the Task 3 memory spike).  There is no BIOS on this
 * platform, so the address is otherwise arbitrary; move it to the
 * EISA_CONFIG region (0x20000).  That address is only safe because this
 * build excludes boot-2's boot.c — the sole consumer of EISA_CONFIG_ADDR
 * (src/boot-2/i386/libsa/memory.h) — and because the loader zeroes
 * eisaConfigFunctions in KERNBOOTSTRUCT, so nothing downstream reads an
 * EISA config area either.  WARNING: if boot.c is ever added to this
 * build, this address must move — intbuf and boot.c's EISA config buffer
 * would then alias the same physical bytes, causing silent data
 * corruption.  Passed to the compiler via `-include` so BIOS_ADDR is
 * already redefined before any source file's own #include <memory.h>. */
#include <memory.h>

#undef BIOS_ADDR
#define BIOS_ADDR	0x020000
