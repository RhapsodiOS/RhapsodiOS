/* Prologue for compiling boot-2 sources (e.g. disk.c) under bootefi-1
 * without editing src/boot-2 itself.  boot-2's disk.c does
 * `static char * const intbuf = (char *)ptov(BIOS_ADDR);` — a compile-time
 * constant initializer.  BIOS_ADDR (0xC00) sits inside physical page 0,
 * which OVMF's null-pointer detection withholds from AllocatePages
 * (confirmed in the Task 3 memory spike).  There is no BIOS on this
 * platform, so the address is otherwise arbitrary; move it to the unused
 * EISA_CONFIG region (0x20000), which the loader zeroes and nothing else
 * claims.  Passed to the compiler via `-include` so BIOS_ADDR is already
 * redefined before any source file's own #include <memory.h>. */
#include <memory.h>

#undef BIOS_ADDR
#define BIOS_ADDR	0x020000
