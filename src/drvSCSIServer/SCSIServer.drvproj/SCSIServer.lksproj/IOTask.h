/*
 * IOTask.h
 * Mach task, memory-wiring, and client-death-notification interface for SCSIServer driver
 *
 * Provides task port allocation, memory wiring, and client task reference/notification
 * management used by IOSCSISession.
 */

#ifndef _IOTASK_H_
#define _IOTASK_H_

#import <objc/Object.h>
#import <mach/mach.h>

/* ========================================================================
 * C Functions for Mach Task Plumbing
 * ======================================================================== */

/* Allocate and assign a name to a Mach port
 * name: Port name to assign
 */
void IOTaskPortAllocateName(mach_port_t name);

/* Allocate a Mach port in the IOTask's IPC space, without renaming it
 * name: Pointer to receive the newly allocated port (output parameter)
 * Returns: port_allocate()'s kern_return_t
 */
int IOTaskPortAllocate(mach_port_t *name);

/* Deallocate a Mach port in the task
 * port: Mach port to deallocate
 */
void IOTaskPortDeallocate(mach_port_t port);

/* Wire memory in task's address space for DMA
 * address: Virtual address to wire
 * length: Length of memory region in bytes
 * Returns: result of vm_map_pageable()
 */
int IOTaskWireMemory(unsigned int address, int length);

/* Unwire previously wired memory
 * address: Virtual address to unwire
 * length: Length of memory region in bytes
 */
void IOTaskUnwireMemory(unsigned int address, int length);

/* Reference a client task and increment its reference count
 * clientReferenceSlot: Pointer to the caller's own storage cell holding a
 *   slot pointer into _clientReferences[0..31]. If the cell doesn't already
 *   point into that range, a free slot is found and written back through
 *   this pointer.
 * Returns: 0 on success, 6 if no slots are available, error code from the
 *   kernel function on failure
 */
int IOReferenceClientTask(int **clientReferenceSlot);

/* Decrement reference count for a client task
 * clientEntry: Pointer to a _clientReferences[0..31] slot (a bare int
 *   refcount; offset +0 is the entire entry, there is no offset +4 field)
 * Returns: 0 on success, result of cleanup function if refcount reaches 0, 4 on error
 */
int IODereferenceClientTask(int *clientEntry);

/* Convert a client task port to its VM map
 * taskPort: Mach task port
 * Returns: the task's VM map on success, 0 on failure
 *
 * Called from the MiG server stubs, which pass the result on as the SCSI
 * request's `client` (vm_task_t).
 */
int IOConvertTaskPortToVMTask(mach_port_t taskPort);

/* Release a VM map obtained from IOConvertTaskPortToVMTask
 * vmTask: VM map to release
 *
 * Returns nothing: the body is a single call to vm_map_deallocate(), which is
 * itself void (src/kernel-7/vm/vm_map.h:401), and every MiG-stub call site
 * discards the result register.
 */
void IODestroyMappedVMTask(int vmTask);

/* Register for client task death notification
 * task: the client's task port, as an ipc_port_t handed to us by the kernel
 * session: the IOSCSISession to notify; also its own Mach port name.  The
 *   reference stores this argument verbatim into the notification entry's
 *   second field (address 8708), which IOReleaseNotifyForFunc matches against
 *   its own `id session` and _io_task_notification uses as a msg_remote_port.
 * deathPort: Pointer to receive the registered death port (output parameter)
 * Returns: 0 on success, IO_R_RESOURCE if all 32 slots are taken,
 *   IO_R_IPC_FAILURE if the notification thread could not be forked, or the
 *   failing call's own error code
 *
 * This function does return.  It is _io_task_notification, the thread it
 * forks, that never returns in the ordinary case - that thread is internal to
 * IOTask.m and is no longer declared here.
 */
extern int IORequestNotifyForClientTask(mach_port_t task, id session, mach_port_t *deathPort);

/* Release notification registration
 * deathPort: Death notification port to release
 * session: IOSCSISession object associated with the notification
 */
void IOReleaseNotifyForFunc(mach_port_t deathPort, id session);

#endif /* _IOTASK_H_ */
