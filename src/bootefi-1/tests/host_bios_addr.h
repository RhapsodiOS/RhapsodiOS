/* disk.c pins its sector cache at physical BIOS_ADDR (0xC00), which the host
 * cannot write.  Redirect it at a real buffer.  memory.h defines BIOS_ADDR
 * unconditionally, so undef first. */
#ifndef _HOST_BIOS_ADDR_H_
#define _HOST_BIOS_ADDR_H_

/* boot2's BSD headers (ufs/ufs/inode.h) use LIST_ENTRY() without including
 * sys/queue.h themselves -- on the original NeXT/Rhapsody SDK it arrived
 * transitively; the host SDK's <sys/param.h> does not pull it in, so force
 * it first for every translation unit. */
#include <sys/queue.h>

/* libsa.h pulls in <mach/mach.h>, which on this SDK transitively includes
 * <string.h>, which in turn tail-includes <strings.h> for legacy BSD names
 * -- among them a non-static `int ffs(int);` that collides with sys.c's own
 * `static int ffs(...)`.  On the original NeXT SDK this chain didn't reach
 * strings.h.  Pre-set its include guard so it's skipped everywhere; nothing
 * we build calls the handful of names it would have declared (bcmp, index,
 * rindex, strcasecmp, ffsl/fls) other than ffs itself, which sys.c defines. */
#define _STRINGS_H_

/* libsa.h re-declares bcopy/bzero with old-style signatures, guarded by
 * #ifndef bcopy / #ifndef bzero.  Pre-define the guard macros (without
 * pulling in <strings.h>, whose modern prototypes conflict both with
 * libsa.h's signatures and, via ffs(), with sys.c's own static ffs()) so
 * both calls fall back to plain implicit declarations, already tolerated
 * by -Wno-implicit-function-declaration, and still link against libSystem's
 * real bcopy/bzero. */
#define bcopy bcopy
#define bzero bzero

/* libsa.h also assumes two NeXT Mach type aliases that no longer exist in
 * the host's <mach/mach.h>, and re-declares vm_allocate()/vm_deallocate()
 * with the old 1990s NeXT signature (a `vm_task_t`/`boolean_t anywhere`
 * 4-arg form).  The modern <mach/vm_map.h> declares the same names with a
 * 64-bit-only `vm_map_t`/`int flags` form that conflicts outright, and
 * nothing we build calls either -- they exist in libsa.h only for zalloc.c
 * and mach.c, neither of which is part of this host test.  So pre-set
 * vm_map.h's include guard to skip it entirely rather than try to reconcile
 * the two signatures. */
#define _vm_map_user_
#include <mach/mach.h>
typedef mach_port_t port_t;
typedef mach_port_t vm_task_t;

/* disk.c's intbuf is `static char * const intbuf = (char *)ptov(BIOS_ADDR);`
 * -- a static initializer, which must be a compile-time address constant.
 * The address of a static-storage-duration array qualifies; a pointer
 * *variable*'s value does not.  So ptov must expand to the array itself,
 * not to a pointer that holds its address. */
extern char intbuf_backing[];

#include "memory.h"
#undef  BIOS_ADDR
#undef  ptov
#define BIOS_ADDR   0
#define ptov(p)     (intbuf_backing)

#endif
