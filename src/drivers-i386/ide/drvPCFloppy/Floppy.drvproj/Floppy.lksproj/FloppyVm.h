/*
 * FloppyVm.h - Opaque VM types for i386 Floppy LKS (MACH_USER_API).
 *
 * Do not import <vm/vm_kern.h> here: under MACH_USER_API it conflicts with
 * mach_port_t-based task_t/thread_t from <mach/mach_types.h>.
 */
#ifndef _FLOPPY_VM_H_
#define _FLOPPY_VM_H_

#import <mach/std_types.h>
#import <mach/kern_return.h>

#ifndef _VM_MAP_T
typedef struct vm_map *vm_map_t;
#define _VM_MAP_T
#endif

#ifndef _PMAP_T
typedef struct pmap *pmap_t;
#define _PMAP_T
#endif

#ifndef VM_MAP_NULL
#define VM_MAP_NULL ((vm_map_t)0)
#endif

extern vm_map_t kernel_map;

#endif /* _FLOPPY_VM_H_ */
