#ifndef _BOOTEFI_MACH_MACH_H_
#define _BOOTEFI_MACH_MACH_H_
/* Shim. src/kernel-7/mach/mach_types.h is xnu kernel-internal source (it
 * itself requires <kern/task.h>, <vm/vm_user.h>, etc.) and this checkout
 * ships no user-space <mach/mach.h> umbrella (that is normally assembled
 * into an installed SDK, which this raw-source checkout does not have).
 * None of the Mach IPC calls libsa.h declares here (vm_allocate, host_info,
 * task_self_, host_self, ...) are used by any source file this loader
 * compiles -- they belong to boot-2's zalloc.c/mach.c, neither of which is
 * part of this build.  Pull in the real, self-contained mach/port.h and
 * mach/machine/kern_return.h for mach_port_t/port_t/kern_return_t (both
 * already used elsewhere in this same translation unit via saio.h's
 * <sys/vnode.h> -> <sys/vm.h> chain, so defining our own conflicting copies
 * here is wrong, not just redundant), and add only the handful of names
 * that are genuinely absent without the full mach_types.h graph. */
#include <mach/port.h>
#include <mach/machine/kern_return.h>
typedef port_t vm_task_t;
typedef port_t host_t;
typedef unsigned int vm_address_t;
typedef int *host_info_t;
#endif /* _BOOTEFI_MACH_MACH_H_ */
