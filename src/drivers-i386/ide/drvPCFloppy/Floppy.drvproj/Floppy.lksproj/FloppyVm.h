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
#import <driverkit/return.h>

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

/* Aliases for decompiled IOReturn names → stock driverkit/return.h codes */
#ifndef IO_R_IO_ERROR
#define IO_R_IO_ERROR		IO_R_IO
#endif
#ifndef IO_R_NOT_FORMATTED
#define IO_R_NOT_FORMATTED	IO_R_UNSUPPORTED
#endif
#ifndef IO_R_MEDIA_ERROR
#define IO_R_MEDIA_ERROR	IO_R_MEDIA
#endif
#ifndef IO_R_DMA_ERROR
#define IO_R_DMA_ERROR		IO_R_DMA
#endif
#ifndef IO_R_DEVICE_ERROR
#define IO_R_DEVICE_ERROR	IO_R_INTERNAL
#endif
#ifndef IO_R_NO_MEDIA
#define IO_R_NO_MEDIA		IO_R_NO_DEVICE
#endif
#ifndef IO_R_NO_MEMORY
#define IO_R_NO_MEMORY		IO_R_RESOURCE
#endif

#endif /* _FLOPPY_VM_H_ */
