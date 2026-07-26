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

/* Allocate a Mach port, without assigning it a name
 * name: Pointer to receive the newly allocated port (output parameter)
 * Returns: 0 on success, error code on failure
 *
 * NOT YET WRITTEN: absent from our source tree; the reference's body is a
 * direct tail call to the imported port_allocate(_IOTask_kern->port_funcs, name).
 * Deferred per the Phase 2 scope decision (needs a PowerPC compiler to verify).
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
 * clientEntry: Pointer to client entry (death port at offset +0, refcount at offset +4)
 * Returns: 0 on success, result of cleanup function if refcount reaches 0, 4 on error
 */
int IODereferenceClientTask(int *clientEntry);

/* Convert a client task port to its VM map
 * taskPort: Mach task port
 * Returns: the task's VM map on success, 0 on failure
 *
 * NOT YET WRITTEN: absent from our source tree. Deferred per the Phase 2
 * scope decision (needs a PowerPC compiler to verify).
 */
int IOConvertTaskPortToVMTask(mach_port_t taskPort);

/* Release a VM map obtained from IOConvertTaskPortToVMTask
 * vmTask: VM map to release
 * Returns: result of vm_map_deallocate()
 *
 * NOT YET WRITTEN: absent from our source tree. Deferred per the Phase 2
 * scope decision (needs a PowerPC compiler to verify).
 */
int IODestroyMappedVMTask(int vmTask);

/* Client task death notification thread body
 * Runs as its own thread, forked by IORequestNotifyForClientTask; never
 * returns in the ordinary case.
 *
 * NOT YET WRITTEN: absent from our source tree. Deferred per the Phase 2
 * scope decision (needs a PowerPC compiler to verify).
 */
void _io_task_notification(void);

/* Register for client task death notification
 * task: Client task port
 * notifyPort: Port to notify when the client task dies
 * deathPort: Pointer to receive the registered death port (output parameter)
 * Returns: 0 on success, error code on failure
 *
 * NOT YET WRITTEN: declared extern only; nothing defines it yet. Deferred
 * per the Phase 2 scope decision (needs a PowerPC compiler to verify).
 */
extern int IORequestNotifyForClientTask(mach_port_t task, mach_port_t notifyPort, mach_port_t *deathPort);

/* Release notification registration
 * deathPort: Death notification port to release
 * session: IOSCSISession object associated with the notification
 */
void IOReleaseNotifyForFunc(mach_port_t deathPort, id session);

#endif /* _IOTASK_H_ */
