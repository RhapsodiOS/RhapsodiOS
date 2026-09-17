/* Shim for <architecture/byte_order.h>: the real header lives at
 * src/architecture-1/byte_order.h (named "-1" in this repo, not
 * "architecture", so it isn't found by its bracket-include spelling
 * without this redirect).
 *
 * It also picks its ppc/i386 half with `#if defined(__ppc__) /
 * #elif defined(__i386__)`, and this 1999 i386-only code has no case for
 * building natively as x86_64.  The asm it uses (rorw/bswap on
 * register-sized operands) assembles fine under x86_64 too, so force
 * __i386__ just for this include -- but only for this include: the host
 * SDK's <sys/cdefs.h> (already fully processed earlier in every
 * translation unit that gets here, guarded against re-inclusion) uses a
 * *global* __i386__ to pick pre-UNIX03 symbol-versioned libc aliases
 * (open$UNIX2003 and friends) that don't exist in the real 64-bit
 * libSystem we link against.  Leaving __i386__ defined past this header
 * would poison any later, unguarded use of it elsewhere in the file. */
#ifndef __i386__
#define __i386__ 1
#define BOOTEFI_HOST_UNDEF_I386
#endif

/* The real header's NXSwapLong()/NXSwapBigLongToHost() operate on
 * `unsigned long`.  On the original 32-bit host (and the real i386 EFI
 * target) that's 4 bytes, matching the 32-bit on-disk fields
 * (disk_label_t, disktab, ufs dinode) they're used to byte-swap.  On this
 * LP64 host `unsigned long` is 8 bytes, so e.g. `bswap` operates on a
 * 64-bit register and corrupts the value once it's truncated back into a
 * 32-bit field -- this is exactly why golden.img's disk label failed its
 * magic-number check (dlV3) until this was found.  Rename the originals
 * out of the way and replace them with correct fixed-32-bit versions. */
/* NXSwapLongLong has the identical bug one level up: it byte-swaps by
 * splitting the 64-bit value into a `union { unsigned long long;
 * unsigned long ul[2]; }` and swapping the two 4-byte halves -- valid only
 * when `unsigned long` is 4 bytes.  On this LP64 host it's 8, so `ul[2]`
 * is 16 bytes overlaid on an 8-byte value: a stack-buffer-overflow (caught
 * by AddressSanitizer reading di_size in byte_swap_superblock). */
#define NXSwapLong		bootefi_host_orig_NXSwapLong_unused
#define NXSwapLongLong		bootefi_host_orig_NXSwapLongLong_unused
#define NXSwapBigLongToHost	bootefi_host_orig_NXSwapBigLongToHost_unused
#define NXSwapBigLongLongToHost	bootefi_host_orig_NXSwapBigLongLongToHost_unused

#include "architecture-1-real/byte_order.h"

#undef NXSwapLong
#undef NXSwapLongLong
#undef NXSwapBigLongToHost
#undef NXSwapBigLongLongToHost

static __inline__ unsigned int NXSwapLong(unsigned int inv)
{
    return ((inv & 0x000000ffu) << 24) | ((inv & 0x0000ff00u) << 8) |
           ((inv & 0x00ff0000u) >> 8)  | ((inv & 0xff000000u) >> 24);
}

static __inline__ unsigned int NXSwapBigLongToHost(unsigned int x)
{
    return NXSwapLong(x);
}

static __inline__ unsigned long long NXSwapLongLong(unsigned long long inv)
{
    return ((unsigned long long)NXSwapLong((unsigned int)(inv & 0xffffffffu)) << 32) |
           (unsigned long long)NXSwapLong((unsigned int)(inv >> 32));
}

static __inline__ unsigned long long NXSwapBigLongLongToHost(unsigned long long x)
{
    return NXSwapLongLong(x);
}

#ifdef BOOTEFI_HOST_UNDEF_I386
#undef __i386__
#undef BOOTEFI_HOST_UNDEF_I386
#endif
