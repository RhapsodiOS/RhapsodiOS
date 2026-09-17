/* Shim for <sys/lock.h>: the host SDK's own sys/lock.h doesn't define
 * `struct lock__bsd__`, which ufs/ufs/inode.h needs, so redirect to this
 * repo's src/kernel-7/bsd/sys/lock.h instead.
 *
 * That header pulls in mach/i386/simple_lock.h, which -- like
 * architecture/byte_order.h -- has no branch for building this i386-only
 * code natively as x86_64.  Force __i386__ just around this include: the
 * host SDK's <sys/cdefs.h> is already fully processed earlier in every
 * translation unit that reaches here (guarded against re-inclusion), so
 * this can't retroactively change its decision -- but __i386__ must not be
 * left defined afterwards, or it would poison any *later*, unguarded use
 * of it elsewhere in the file into picking pre-UNIX03 symbol-versioned
 * libc aliases (open$UNIX2003 and friends) that don't exist in the real
 * 64-bit libSystem we link against. */
#ifndef __i386__
#define __i386__ 1
#define BOOTEFI_HOST_UNDEF_I386
#endif

#include "lock_real.h"

#ifdef BOOTEFI_HOST_UNDEF_I386
#undef __i386__
#undef BOOTEFI_HOST_UNDEF_I386
#endif
