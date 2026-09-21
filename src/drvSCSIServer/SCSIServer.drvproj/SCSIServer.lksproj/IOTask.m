/*
 * IOTask.m
 * Mach task, memory-wiring, and client-death-notification plumbing for SCSIServer driver
 */

#import "IOTask.h"
#import <mach/mach.h>
#import <mach/mig_errors.h>
#import <mach/notify.h>
#import <mach/task_special_ports.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/return.h>

/* The DriverKit kernel-internal I/O task.
 *
 * This global used to be called '_entry' here.  It is not: every one of the
 * twenty-three relocations in SCSIServer_reloc that reaches it names the
 * symbol _IOTask_kern (for example addresses 6484/6488 in
 * IOTaskPortAllocateName, 7368/7372 in IOConvertTaskPortToVMTask and
 * 8556/8560 in IORequestNotifyForClientTask), and the DriverKit kernel
 * library declares exactly that global -
 * src/driverkit-3/libDriver/Kernel/generalFuncsPrivate.m:74,
 * "task_t IOTask_kern;  // kernel internal version of IOTask".  It is a
 * task_t, i.e. a struct task * (src/kernel-7/kern/task.h:74).
 *
 * Only two of struct task's fields are ever touched, so they are spelled out
 * here rather than importing <kern/task.h> into a loadable kernel server:
 *
 *   +0x18  vm_map_t map        struct task's "Address space description"
 *                              (kern/task.h:81).  Passed as vm_map_pageable()'s
 *                              map argument at addresses 6760 and 6856.
 *   +0xa4  ipc_space_t itk_space  the task's IPC space.  Passed as the first
 *                              argument of port_allocate, port_rename,
 *                              port_deallocate, ipc_object_copyin_compat and
 *                              ipc_object_copyout_compat - exactly as
 *                              src/kernel-7/driverkit/driverServerXXX.m:343
 *                              writes IOTask_kern->itk_space for the same
 *                              ipc_object_copyin_compat call.
 *
 * The old field names 'task_port' and 'port_funcs' were guesses; neither
 * offset holds a port or a function table.
 */
extern struct {
    char pad1[0x18];
    void *map;                 /* offset +0x18: vm_map_t */
    char pad2[0x8c];
    void *itk_space;           /* offset +0xa4: ipc_space_t */
} *IOTask_kern;

/* The IOTask's own task port name (port_name_t IOTask, the companion of
 * IOTask_kern in generalFuncsPrivate.m:72).  Only _io_task_notification uses
 * it: it accounts for all four of the reference's _IOTask relocations, at
 * 7696/7700 and 8176/8180.  The other twenty-three name _IOTask_kern.
 */
extern port_name_t IOTask;

/* Page size global - used for address alignment
 *
 * Still open (divergences.md's IOTask.m stub-body finding): the reference has
 * no _page_size relocation at all.  IOTaskWireMemory and IOTaskUnwireMemory
 * account for all four of its _page_mask relocations instead, and they use it
 * directly - `not r0, r9` then two `and`s at 6748-6770 - rather than
 * subtracting one from a size.  Left alone here because those two bodies are
 * still stubs and are not this task's to write.
 */
extern unsigned int _page_size;

/* Mach kernel routines this file calls.  Each is one of SCSIServer_reloc's
 * thirty-four imports, resolved through the jump island each bl relocates to;
 * the prototypes are transcribed from this tree's own kernel sources, cited
 * at each call site.
 */
/* port_allocate is the one of these that <mach/mach.h> also declares, as the
 * user-space MIG stub taking a task_t.  The routine reached through the jump
 * island is the kernel's, which takes an ipc_space_t, so the two prototypes
 * cannot both stand.  Call it through a correctly typed pointer instead: the
 * symbol imported is still _port_allocate.
 */
typedef kern_return_t (*kern_port_allocate_fn)(void *space, mach_port_t *name);
#define KERN_PORT_ALLOCATE ((kern_port_allocate_fn)port_allocate)
extern kern_return_t ipc_object_copyin_compat(void *space, mach_port_t name,
                                              int msgt_name, boolean_t dealloc,
                                              void **objectp);
extern kern_return_t ipc_object_copyout_compat(void *space, void *object,
                                               int msgt_name, mach_port_t *namep);
extern void ipc_port_release_send(void *port);
extern int convert_port_to_map(void *port);
extern void vm_map_deallocate(int map);
extern kern_return_t task_set_special_port_EXTERNAL(port_name_t task, int which,
                                                    port_name_t port);
extern void bzero(void *addr, int count);

/* ========================================================================
 * Client Reference Counting (data)
 * ======================================================================== */

/*
 * Client reference tracking array
 *
 * Address and extent confirmed against the reference's own symbol table and
 * section map, not inferred: _clientReferences is at 0x4008 and the next
 * symbol, _notifyThread, is at 0x4088, so the array occupies 0x4008-0x4087,
 * 128 bytes = 32 ints.  __DATA,__data spans 0x4000-0x408b (base 16384,
 * size 140) and holds exactly _protocols.26 (0x4000), _clientReferences and
 * _notifyThread; everything else in this file (_notifClients,
 * _notifClientCnt) is uninitialised and lands in __DATA,__bss.
 *
 * Each entry is a bare int reference count - there is no per-entry struct.
 * IOReferenceClientTask searches for an empty slot (value == 0) and then
 * renames the caller's Mach port *to the address of that slot*, so a slot's
 * address doubles as the client's port name in the IOTask's IPC space (see
 * that function's port_rename call).  That is why IODereferenceClientTask can
 * hand the same pointer straight to port_deallocate as a name.
 */
static int clientReferences[32] = {0};  /* Client reference array at 0x4008-0x4087 */

/*
 * The single client-death notification thread.
 *
 * At 0x4088, immediately after _clientReferences.  This is *not* a boundary
 * marker: it is the IOThread handle of the one _io_task_notification thread,
 * written from IOForkThread's result at address 8748, read at 8720 and 8752 to
 * decide whether a thread is already running, and zeroed at 8224 as that
 * thread exits.
 *
 * The array-bound uses below only coincide with it.  In IOReferenceClientTask
 * and IODereferenceClientTask the upper bound's ha16/lo16 relocation pairs
 * (addresses 6956/6960, 6992/6996, 7008/7012, 7040/7044 and 7196/7200) are
 * *scattered* relocations against __DATA,__data+136, i.e. the assembler's
 * encoding for "_clientReferences + 128", an address outside the symbol it is
 * relative to.  The two genuine _notifyThread references (8712/8716 and
 * 8212/8216) are plain, non-scattered relocations naming the same address.
 * So Apple's source wrote &_clientReferences[32] for the bound and
 * _notifyThread for the thread; the two happen to be the same address.
 */
static IOThread notifyThread = 0;  /* Notification thread handle at 0x4088 */

/* ========================================================================
 * Client Task Notification Management (data)
 * ======================================================================== */

/*
 * Global notification client tracking
 * Maximum 32 (0x20) notification clients can be registered
 *
 * _notifClients is at 0x4094 and the next symbol, _notifClientCnt, is at
 * 0x4194: 256 bytes, i.e. exactly 32 entries of 8 bytes.  There is no second,
 * parallel array - the earlier "DAT_00004098[64] parallel array of session
 * objects" reading mistook entry 0's second word (0x4094 + 4) for the base of
 * one.  Every access in the reference is `slwi rN, i, 3` followed by a load or
 * store at +0 or +4 of _notifClients + rN.
 *
 * Entry structure (2 ints, 8 bytes):
 *   offset +0: the client's death port name, which is also the address of its
 *              _clientReferences slot (see above)
 *   offset +4: the session, stored by IORequestNotifyForClientTask and used by
 *              _io_task_notification as the notification's msg_remote_port
 */
static int notifClients[64];      /* 32 entries * 2 ints = 64 ints */
static int notifClientCnt = 0;    /* Current client count */

/* ========================================================================
 * Port Management Functions
 * ======================================================================== */

/*
 * IOTaskPortAllocateName - Allocate and assign a name to a Mach port
 * name: Port name to assign
 * Returns: port_allocate()'s kern_return_t when it fails, otherwise
 *   port_rename()'s.  The reference leaves port_allocate's r3 alone on the
 *   failure path (the bne at 6508 jumps straight to the epilogue at 6532) and
 *   writes nothing after the bl _port_rename at 6528, so whichever call ran
 *   last supplies the result.
 */
int IOTaskPortAllocateName(mach_port_t name)
{
    int result;
    mach_port_t allocated_port;
    void *space;

    /* Get the IOTask's IPC space from the kernel-internal task */
    space = IOTask_kern->itk_space;

    /* TODO: Allocate port
     * result = port_allocate(space, &allocated_port)
     */
    result = 0;

    if (result == 0) {
        /* TODO: Rename the new port to 'name'
         * result = port_rename(space, allocated_port, name)
         */
    }

    return result;
}

/*
 * IOTaskPortAllocate - Allocate a Mach port in the IOTask's IPC space
 * name: Pointer to receive the newly allocated port (output parameter)
 * Returns: port_allocate()'s kern_return_t
 *
 * Address 6588.  Twelve instructions of body ending in the blr at 6632, plus
 * the single 16-byte jump island at 6636 that makes up the 64-byte
 * next-symbol span:
 *
 *   6588-6596  prologue (mflr / stw lr / stwu -0x40)
 *   6600       mr r4, r3            - the out-parameter moves to argument 2
 *   6604-6612  lis/lwz of _IOTask_kern, then lwz r3, 0xA4(r9)
 *   6616       bl, relocating to _port_allocate
 *   6620-6632  epilogue; nothing writes r3 after the call, so port_allocate's
 *              own return value is this function's
 *
 * How it differs from IOTaskPortAllocateName above (address 6460): that one
 * allocates into a *local* and then makes a second call, port_rename, to give
 * the new port the caller's chosen name; this one allocates straight into the
 * caller's variable and makes no second call.  Neither wraps the other - they
 * are two separate bodies that happen to share their first call.
 */
int IOTaskPortAllocate(mach_port_t *name)
{
    return KERN_PORT_ALLOCATE(IOTask_kern->itk_space, name);
}

/*
 * IOTaskPortDeallocate - Deallocate a Mach port
 * port: Mach port to deallocate
 */
void IOTaskPortDeallocate(mach_port_t port)
{
    void *space;

    /* Get the IOTask's IPC space from the kernel-internal task */
    space = IOTask_kern->itk_space;

    /* TODO: Call port_deallocate()
     * port_deallocate(space, port)
     */
}

/* ========================================================================
 * Memory Wiring Functions
 * ======================================================================== */

/*
 * IOTaskWireMemory - Wire memory in task's address space for DMA
 * address: Virtual address to wire
 * length: Length of memory region in bytes
 *
 * "Wiring" memory locks it into physical RAM and prevents it from being
 * paged out. This is required for DMA operations as the hardware needs
 * stable physical addresses.
 */
int IOTaskWireMemory(unsigned int address, int length)
{
    unsigned int start_addr;
    unsigned int end_addr;
    void *map;

    /* Get the IOTask's address map from the kernel-internal task */
    map = IOTask_kern->map;

    /* Align start address to page boundary (round down) */
    start_addr = address & ~(_page_size - 1);

    /* Calculate end address aligned to page boundary (round up) */
    end_addr = (address + length + (_page_size - 1)) & ~(_page_size - 1);

    /* TODO: Call kernel vm_map_pageable() function
     * vm_map_pageable(map, start_addr, end_addr, 0)
     */
    return 0;
}

/*
 * IOTaskUnwireMemory - Unwire previously wired memory
 * address: Virtual address to unwire
 * length: Length of memory region in bytes
 */
void IOTaskUnwireMemory(unsigned int address, int length)
{
    unsigned int start_addr;
    unsigned int end_addr;
    void *map;

    /* Get the IOTask's address map from the kernel-internal task */
    map = IOTask_kern->map;

    /* Align start address to page boundary (round down) */
    start_addr = address & ~(_page_size - 1);

    /* Calculate end address aligned to page boundary (round up) */
    end_addr = (address + length + (_page_size - 1)) & ~(_page_size - 1);

    /* TODO: Call kernel vm_map_pageable() function
     * vm_map_pageable(map, start_addr, end_addr, 1)
     */
}

/* ========================================================================
 * Client Reference Counting
 * ======================================================================== */

/*
 * IOReferenceClientTask - Reference a client task and increment reference count
 * clientReferenceSlot: Pointer to the caller's own storage cell holding a slot
 *   pointer into _clientReferences[0..31] (input/output parameter)
 * Returns: 0 on success, 6 if no slots available, error code from kernel function on failure
 *
 * This function manages client task references in a more complex way than just
 * incrementing a counter. It:
 * 1. Checks if *clientReferenceSlot already points to a valid entry in the reference table
 * 2. If not, searches for an empty slot in the client reference table
 * 3. Calls a kernel function to set up the reference
 * 4. Updates *clientReferenceSlot to point to the found/allocated entry
 * 5. Increments the reference count in the entry
 *
 * The decompiled code shows this behavior:
 * - If *clientReferenceSlot is already in valid range (0x4008-0x4087), just increment
 * - Otherwise, search _clientReferences array for an empty slot (where *slot == 0)
 * - Call kernel function FUN_00001be4() to set up the reference
 * - Update *clientReferenceSlot to point to the allocated slot
 * - Increment the reference count
 *
 * Client reference table range:
 * - Start: &_clientReferences (0x4008)
 * - End: &_notifyThread (appears to be end of client reference array)
 * - Valid range for existing references: 0x4008-0x4087
 */
int IOReferenceClientTask(int **clientReferenceSlot)
{
    int result;
    int *current_entry;
    int *search_ptr;

    /* Get the entry pointer from clientReferenceSlot
     * piVar2 = *clientReferenceSlot
     */
    current_entry = *clientReferenceSlot;

    /* Check if current_entry is already in valid range
     * Decompiled: if (piVar2 <= &UNK_00004007 || &UNK_00004087 < piVar2)
     * Valid range is &_clientReferences[0] to &_clientReferences[31]
     * (0x4008 - 0x4087)
     */
    if ((current_entry < &clientReferences[0]) || (current_entry > &clientReferences[31])) {
        /* Entry not in valid range - need to find or allocate a slot */

        /* Start search at beginning of client references table
         * piVar2 = &_clientReferences
         */
        search_ptr = clientReferences;

        /* Search for an empty slot (where *slot == 0)
         * Decompiled:
         * do {
         *   if (*piVar2 == 0) break;
         *   piVar2 = piVar2 + 1;
         * } while (piVar2 < &_notifyThread);
         */
        while (search_ptr < (int *)&notifyThread) {
            if (*search_ptr == 0) {
                /* Found empty slot */
                break;
            }
            search_ptr = search_ptr + 1;
        }

        /* Check if we found a valid slot
         * Decompiled: if (&UNK_00004087 < piVar2)
         * This checks if search went past the last valid slot
         */
        if (search_ptr > &clientReferences[31]) {
            /* No empty slots available */
            return 6;  /* Error code 6: no slots */
        }

        /* Rename the client's port to the address of the slot we just found.
         * Address 7076's bl relocates to _port_rename, with
         * r3 = IOTask_kern->itk_space (7056-7064), r4 = *clientReferenceSlot
         * (the client's current port name, 7068) and r5 = the slot address
         * (7072).  From here on the slot's address *is* the port's name in the
         * IOTask's IPC space, which is why IODereferenceClientTask below can
         * pass the same pointer to port_deallocate as a name.
         */
        result = 0;  /* TODO: Call port_rename() */
        /* result = port_rename(IOTask_kern->itk_space, *clientReferenceSlot, (mach_port_t)search_ptr); */

        /* Update *clientReferenceSlot to point to the allocated slot
         * Decompiled: *clientReferenceSlot = piVar2
         */
        *clientReferenceSlot = search_ptr;

        /* Check if kernel function failed
         * Decompiled: if (iVar1 != 0) { return iVar1; }
         */
        if (result != 0) {
            return result;
        }

        /* Update current_entry to point to the new slot */
        current_entry = search_ptr;
    }

    /* Increment reference count in the entry
     * Decompiled: *piVar2 = *piVar2 + 1
     *
     * Note: This increments the value at the entry, which is the reference count.
     * The entry structure appears to be just the reference count itself,
     * not a struct with multiple fields like notifClients.
     */
    *current_entry = *current_entry + 1;

    return 0;  /* Success */
}

/*
 * IODereferenceClientTask - Decrement reference count for a client task
 * clientEntry: Pointer to a _clientReferences[0..31] slot (a bare int
 *   refcount; offset +0 is the entire entry, there is no offset +4 field)
 * Returns: 0 on success, result of cleanup function if refcount reaches 0, 4 on error
 *
 * This function:
 * 1. Validates the client entry pointer is in valid range
 * 2. Decrements the reference count
 * 3. If refcount reaches 0, calls cleanup function
 */
int IODereferenceClientTask(int *clientEntry)
{
    int refcount;
    int result;

    /* Validate pointer is within the _clientReferences table
     * Range check: &_clientReferences[0] <= clientEntry <= &_clientReferences[31],
     * the same bounds IOReferenceClientTask uses for the same table
     * (_clientReferences[i] is a bare int refcount, offset +0 is the
     * entire entry -- there is no offset +4 field here)
     */
    if ((clientEntry < &clientReferences[0]) ||
        (clientEntry > &clientReferences[31])) {
        return 4;  /* Invalid pointer */
    }

    /* Get reference count from offset +0 (the entry itself) */
    refcount = *clientEntry;

    /* Check if reference count is positive */
    if (refcount <= 0) {
        return 4;  /* Invalid refcount */
    }

    /* Decrement reference count */
    *clientEntry = refcount - 1;

    /* If refcount reached 0, call cleanup function */
    if (*clientEntry == 0) {
        /* Address 7276's bl relocates to _port_deallocate, with
         * r3 = IOTask_kern->itk_space (7264-7272) and r4 still holding the
         * incoming pointer from the `mr r4, r3` at 7168 - the entry's own
         * address, which IOReferenceClientTask made the port's name.
         */
        result = 0;  /* TODO: Call port_deallocate() */
        /* result = port_deallocate(IOTask_kern->itk_space, (mach_port_t)clientEntry); */
    }
    else {
        result = 0;  /* Success, refcount still > 0 */
    }

    return result;
}

/* ========================================================================
 * Client Task VM Map Conversion
 * ======================================================================== */

/*
 * IOConvertTaskPortToVMTask - Convert a client task port to its VM map
 * taskPort: Mach task port
 * Returns: the task's VM map on success, 0 on failure
 *
 * Address 7320.  Forty instructions of body ending in the blr at 7476, plus
 * six 16-byte jump islands at 7480-7575 that make up the 256-byte next-symbol
 * span (targets: vm_map_deallocate, IODereferenceClientTask,
 * ipc_port_release_send, convert_port_to_map, ipc_object_copyin_compat,
 * IOReferenceClientTask).
 *
 *   7320-7336  prologue; `stw r3, 0x68(r1)` homes taskPort in the parameter
 *              save area, because its address is about to be taken
 *   7340       li r31, 0                        - vmTask = 0
 *   7344-7348  addi r3, r1, 0x68 / bl -> __TEXT,__text+6908 = IOReferenceClientTask
 *   7352-7364  on non-zero, `li r3, 0` and branch to the epilogue
 *   7368-7396  IOTask_kern->itk_space, the *rewritten* taskPort, MSG_TYPE_PORT,
 *              FALSE and &object -> ipc_object_copyin_compat
 *   7400-7404  on non-zero, jump straight to 7428, leaving r31 at 0
 *   7408-7416  convert_port_to_map(object) -> r31
 *   7420-7424  ipc_port_release_send(object)
 *   7428-7432  the (rewritten) taskPort again -> IODereferenceClientTask
 *   7436-7452  on non-zero, vm_map_deallocate(r31) and r31 = 0
 *   7456-7476  mr r3, r31; epilogue
 *
 * The cell reloaded at 7380 and 7428 is the same one whose address was handed
 * to IOReferenceClientTask, and that function rewrites its pointee (see the
 * port_rename above), so after the call `taskPort` no longer holds the
 * caller's port name - it holds the _clientReferences slot address that is now
 * the port's name.  Reusing the parameter itself, rather than re-reading the
 * caller's value, is what reproduces this.
 *
 * MSG_TYPE_PORT (6) is src/kernel-7/mach/message.h:716; the argument order is
 * ipc_object_copyin_compat(space, name, msgt_name, dealloc, objectp) from
 * src/kernel-7/ipc/ipc_object.c:963, used identically at
 * src/kernel-7/driverkit/driverServerXXX.m:343.
 */
int IOConvertTaskPortToVMTask(mach_port_t taskPort)
{
    int vmTask;
    void *object;

    vmTask = 0;

    if (IOReferenceClientTask((int **)&taskPort) != 0) {
        return 0;
    }

    if (ipc_object_copyin_compat(IOTask_kern->itk_space, taskPort,
                                 MSG_TYPE_PORT, FALSE, &object) == 0) {
        vmTask = convert_port_to_map(object);
        ipc_port_release_send(object);
    }

    /* Dropped unconditionally, on the copyin failure path too */
    if (IODereferenceClientTask((int *)taskPort) != 0) {
        vm_map_deallocate(vmTask);
        vmTask = 0;
    }

    return vmTask;
}

/*
 * IODestroyMappedVMTask - Release a VM map obtained from IOConvertTaskPortToVMTask
 * vmTask: VM map to release
 *
 * Address 7576, the smallest of this file's functions.  Eight instructions of
 * body ending in the blr at 7604, plus one 16-byte jump island at 7608 that
 * makes up the 48-byte next-symbol span:
 *
 *   7576-7584  prologue (mflr / stw lr / stwu -0x40)
 *   7588       bl, relocating to _vm_map_deallocate; r3 is untouched since
 *              entry, so vmTask is passed straight through
 *   7592-7604  epilogue
 *
 * Returns void: vm_map_deallocate() itself is void
 * (src/kernel-7/vm/vm_map.h:401), and each of the six MiG-stub call sites
 * (10792, 11152, 11568, 11988, 12372, 12752) discards r3 - address 10792's
 * call, for instance, is followed at 10796 by `lwz r0, 0x1C(r30)`, reloading
 * the reply's RetCode.  The header's earlier "returns the result of
 * vm_map_deallocate()" was a guess about a function that has no result.
 */
void IODestroyMappedVMTask(int vmTask)
{
    vm_map_deallocate(vmTask);
}

/* ========================================================================
 * Client Task Notification Management
 * ======================================================================== */

/*
 * _io_task_notification - the client-death notification thread body
 *
 * Address 7624, the largest function in this file: 161 instructions of body
 * ending in the (unreachable) blr at 8264, plus nine 16-byte jump islands at
 * 8268-8411 that make up the 788-byte next-symbol span.  It runs as its own
 * thread, forked once by IORequestNotifyForClientTask below, and leaves only
 * through the IOExitThread() at the bottom.
 *
 * There are exactly three phases and every branch of each is accounted for.
 *
 * Setup (7656-7752).  IOTaskPortAllocate(&notifyPort) at 7668; on failure log
 * and jump to the drain phase (7680-7692).  Then
 * task_set_special_port_EXTERNAL(IOTask, 2, notifyPort) at 7712 - slot 2 is
 * TASK_NOTIFY_PORT, src/kernel-7/mach/task_special_ports.h:93 - so the kernel
 * will deliver this task's port-death notifications here; on failure log and
 * jump to the drain phase (7724-7736).  The third IOLog at 7740-7752 is the
 * msg_receive error arm, reached from inside the loop.  All three arms use the
 * one relocation-confirmed _IOLog import and all three branch to 7956.
 *
 * Receive loop (7776-7952).  Each pass rearms the header
 * (msg_local_port = notifyPort, msg_size = 0x20 = sizeof(notification_t)) and
 * calls msg_receive(hdr, RCV_TIMEOUT, 60000) - option 0x100 is RCV_TIMEOUT
 * (message.h:762), the timeout is `li 0` / `ori 0xEA60`, 60000 ms.  Then, in
 * this order:
 *   - 7816-7824: if notifClientCnt is 0 the thread has no work left; jump
 *     *past* the drain phase, straight to the teardown at 8176.
 *   - 7828-7832: -0xCB is RCV_TIMED_OUT (-203, message.h:800); go round again.
 *   - 7836-7840: any other non-zero result is the third IOLog arm above.
 *   - 7844-7952: otherwise scan the 32 slots, stopping early if the count
 *     reaches 0 or the index passes 31 (both tested at the top of each pass,
 *     7848-7864).  A slot whose port matches the notification's notify_port is
 *     retargeted at that client's session (7892-7896), dereferenced, zeroed,
 *     counted down, and the notification is forwarded with
 *     msg_send(hdr, SEND_TIMEOUT, 0).  Non-matching slots just advance.
 *
 * Drain phase (7956-8172).  Reached from all three error arms; its job is to
 * tell every still-registered client that its notification is gone.  If the
 * count is already 0 it is skipped entirely (7956-7968).  Otherwise it builds
 * a synthetic NOTIFY_PORT_DELETED (0x41, notify.h:153) message in place - the
 * bit twiddling at 8024-8044 sets msg_type_number = 1, msg_type_inline = TRUE
 * and clears longform/deallocate on the msg_type_t whose name and size bytes
 * were just stored as MSG_TYPE_PORT_NAME (15, message.h:726) and 32 - and
 * sends one to each occupied slot, again dereferencing, zeroing and counting
 * down.  The index test is at the top (8072-8076) and the count test at the
 * bottom (8164-8172).
 *
 * Teardown (8176-8228).  Clears TASK_NOTIFY_PORT, releases the port unless it
 * is 0, clears _notifyThread so the next IORequestNotifyForClientTask forks a
 * fresh thread, and calls IOExitThread(), which does not return.  The epilogue
 * the assembler emitted after it is dead.
 *
 * Static: nothing outside this file references address 7624; its only caller
 * is IORequestNotifyForClientTask below.
 */
static void _io_task_notification(void)
{
    notification_t notification;
    mach_port_t notifyPort;
    int result;
    int i;

    notifyPort = 0;

    result = IOTaskPortAllocate(&notifyPort);
    if (result != 0) {
        IOLog("_io_task_notification: IOTaskPortAllocate - %d\n", result);
        goto drain;
    }

    result = task_set_special_port_EXTERNAL(IOTask, TASK_NOTIFY_PORT, notifyPort);
    if (result != 0) {
        IOLog("_io_task_notification: task_set_special_port - %d\n", result);
        goto drain;
    }

    for (;;) {
        notification.notify_header.msg_local_port = notifyPort;
        notification.notify_header.msg_size = sizeof(notification_t);

        result = msg_receive(&notification.notify_header, RCV_TIMEOUT, 60000);

        /* Checked before the result is: no clients left means no reason to
         * keep the thread, and nothing to drain either.
         */
        if (notifClientCnt == 0) {
            goto teardown;
        }
        if (result == RCV_TIMED_OUT) {
            continue;
        }
        if (result != 0) {
            IOLog("_io_task_notification: msg_receive - %d\n", result);
            goto drain;
        }

        for (i = 0; (notifClientCnt != 0) && (i <= 0x1f); i++) {
            if (notifClients[i * 2] != (int)notification.notify_port) {
                continue;
            }

            /* Forward the notification to the session that asked for it */
            notification.notify_header.msg_remote_port =
                (port_t)notifClients[i * 2 + 1];

            IODereferenceClientTask((int *)notifClients[i * 2]);
            bzero(&notifClients[i * 2], 8);
            notifClientCnt--;

            (void)msg_send(&notification.notify_header, SEND_TIMEOUT, 0);
        }
    }

drain:
    if (notifClientCnt != 0) {
        /* Synthesize the port-death notification the kernel will no longer be
         * sending, and hand one to every client still registered.
         */
        notification.notify_header.msg_simple = TRUE;
        notification.notify_header.msg_size = sizeof(notification_t);
        notification.notify_header.msg_type = MSG_TYPE_NORMAL;
        notification.notify_header.msg_local_port = PORT_NULL;
        notification.notify_header.msg_id = NOTIFY_PORT_DELETED;
        notification.notify_type.msg_type_name = MSG_TYPE_PORT_NAME;
        notification.notify_type.msg_type_size = 8 * sizeof(port_t);
        notification.notify_type.msg_type_number = 1;
        notification.notify_type.msg_type_inline = TRUE;
        notification.notify_type.msg_type_longform = FALSE;
        notification.notify_type.msg_type_deallocate = FALSE;

        for (i = 0; i <= 0x1f; i++) {
            if (notifClients[i * 2] != 0) {
                notification.notify_header.msg_remote_port =
                    (port_t)notifClients[i * 2 + 1];
                notification.notify_port = (port_t)notifClients[i * 2 + 1];

                IODereferenceClientTask((int *)notifClients[i * 2]);
                bzero(&notifClients[i * 2], 8);
                notifClientCnt--;

                (void)msg_send(&notification.notify_header, SEND_TIMEOUT, 0);
            }
            if (notifClientCnt == 0) {
                break;
            }
        }
    }

teardown:
    (void)task_set_special_port_EXTERNAL(IOTask, TASK_NOTIFY_PORT, PORT_NULL);
    if (notifyPort != 0) {
        IOTaskPortDeallocate(notifyPort);
    }
    notifyThread = 0;
    IOExitThread();
}

/*
 * IORequestNotifyForClientTask - Register for client task death notification
 * task: the client's task port, as an ipc_port_t handed to us by the kernel
 * session: the IOSCSISession to notify; also its own Mach port name
 * deathPort: receives the registered death port (output parameter)
 * Returns: 0 on success, IO_R_RESOURCE if all 32 slots are taken,
 *          IO_R_IPC_FAILURE if the notification thread could not be forked,
 *          or the failing Mach/reference call's own error code
 *
 * Address 8412.  One hundred and twenty instructions of body ending in the blr
 * at 8888, plus six 16-byte jump islands at 8892-8987 that make up the
 * 576-byte next-symbol span before IOReleaseNotifyForFunc at 8988 (targets:
 * bzero, IODereferenceClientTask, IOForkThread, ipc_object_copyin_compat,
 * IOReferenceClientTask, ipc_object_copyout_compat).
 *
 * Three arguments, confirmed at the reference's own call site,
 * -[IOSCSISession(Private) initServerWithTask:sendPort:] addresses 1324-1340:
 * r3 is the method's `task` argument; r4 is `_priv->0xc`, which
 * IOTaskPortAllocateName made equal to self; r5 is `&_priv->0x10`.  The second
 * argument is therefore the session, not a second port argument - the body
 * stores it verbatim into the entry's +4 field at 8708, which is exactly the
 * field IOReleaseNotifyForFunc below compares against its own `id session`
 * parameter, and which _io_task_notification uses as a msg_remote_port.
 *
 *   8448-8464  arguments into r26/r29 and the stack; i = 0
 *   8472-8496  scan _notifClients for the first entry whose port field is 0
 *   8500-8512  none free -> IO_R_RESOURCE (-702, driverkit/return.h:40)
 *   8528-8552  reserve the slot with -1 and bump notifClientCnt
 *   8556-8580  ipc_object_copyout_compat(itk_space, task, 0x11, deathPort);
 *              0x11 is MACH_MSG_TYPE_PORT_SEND (message.h:275/:414)
 *   8584-8604  on failure, un-reserve the slot and return the error
 *   8608-8616  IOReferenceClientTask(deathPort) - renames the copied-out name
 *              to a _clientReferences slot address
 *   8620-8680  on failure, undo the copyout with ipc_object_copyin_compat,
 *              un-reserve the slot and return the error
 *   8684-8708  commit: entry[0] = *deathPort, entry[1] = session
 *   8712-8728  a notification thread already running -> return 0
 *   8732-8760  IOForkThread(_io_task_notification, 0) -> _notifyThread;
 *              non-zero -> return 0
 *   8764-8844  fork failed: undo the copyout, drop the reference, clear
 *              *deathPort, zero the entry, decrement the count, and return
 *              IO_R_IPC_FAILURE (-703, return.h:41)
 *   8848-8888  li r3, 0; epilogue
 *
 * intentional-mismatch, addresses 8592-8604 and 8656-8680: the reference's two
 * early failure paths clear the slot they reserved but do *not* undo the
 * notifClientCnt++ at 8548-8552, even though the third failure path at
 * 8820-8836 does.  Every copyout or reference failure therefore inflates
 * notifClientCnt permanently relative to the number of live entries - a count
 * _io_task_notification trusts both as a loop bound and as its "should I still
 * be running" test, so the leak eventually pins that thread alive with no
 * clients or truncates a drain.  The decrements below are ours; Apple's defect
 * is recorded rather than reproduced, per
 * docs/superpowers/plans/2026-07-25-kernel-pci-pcmcia-reconstruction.md:968.
 */
int IORequestNotifyForClientTask(mach_port_t task, id session,
                                 mach_port_t *deathPort)
{
    int i;
    int result;

    /* Find the first free slot */
    for (i = 0; i < 0x20; i++) {
        if (notifClients[i * 2] == 0) {
            break;
        }
    }
    if (i > 0x1f) {
        return IO_R_RESOURCE;
    }

    /* Reserve it before making any call that can block */
    notifClients[i * 2] = -1;
    notifClientCnt++;

    result = ipc_object_copyout_compat(IOTask_kern->itk_space, (void *)task,
                                       MACH_MSG_TYPE_PORT_SEND, deathPort);
    if (result != 0) {
        notifClients[i * 2] = 0;
        notifClientCnt--;  /* intentional-mismatch: see above */
        return result;
    }

    result = IOReferenceClientTask((int **)deathPort);
    if (result != 0) {
        /* Undo the copyout.  The reference reuses `task`'s own stack home as
         * the throwaway output (addresses 8456 and 8648 name the same slot).
         */
        (void)ipc_object_copyin_compat(IOTask_kern->itk_space, *deathPort,
                                       MSG_TYPE_PORT, FALSE, (void **)&task);
        notifClients[i * 2] = 0;
        notifClientCnt--;  /* intentional-mismatch: see above */
        return result;
    }

    notifClients[i * 2] = (int)*deathPort;
    notifClients[i * 2 + 1] = (int)session;

    if (notifyThread == 0) {
        notifyThread = IOForkThread((IOThreadFunc)_io_task_notification, NULL);

        if (notifyThread == 0) {
            (void)ipc_object_copyin_compat(IOTask_kern->itk_space, *deathPort,
                                           MSG_TYPE_PORT, FALSE, (void **)&task);
            IODereferenceClientTask((int *)*deathPort);
            *deathPort = 0;
            bzero(&notifClients[i * 2], 8);
            notifClientCnt--;
            return IO_R_IPC_FAILURE;
        }
    }

    return 0;
}

/*
 * IOReleaseNotifyForFunc - Release notification registration
 * deathPort: Death notification port to release
 * session: IOSCSISession object associated with the notification
 *
 * This function:
 * 1. Searches the notification client array for matching port/session
 * 2. Dereferences the client task
 * 3. Clears the entry (8 bytes)
 * 4. Decrements the client count
 */
void IOReleaseNotifyForFunc(mach_port_t deathPort, id session)
{
    int i;
    int *client_entry;

    /* Iterate through all possible notification slots (0-31) */
    for (i = 0; i < 0x20; i++) {
        /* Get pointer to client entry (2 ints = 8 bytes per entry)
         * Entry layout:
         *   notifClients[i*2+0]: death port
         *   notifClients[i*2+1]: session
         */
        client_entry = &notifClients[i * 2];

        /* Check if this entry matches the death port and session.  The
         * session comes from the entry's own second word, loaded at address
         * 9080 as `lwz r0, 4(r31)` where r31 = _notifClients + (i << 3); the
         * separate notifClientObjects[] this used to read was a misreading of
         * entry 0's +4 field (0x4098) as the base of a parallel array.
         * _notifClients is 256 bytes (0x4094 up to _notifClientCnt at
         * 0x4194) - exactly the 32 eight-byte entries, with no room for one.
         */
        if ((client_entry[0] == (int)deathPort) &&
            (client_entry[1] == (int)session)) {

            /* Dereference the client task (decrements reference count).
             * The reference passes the value held in the slot (a
             * _clientReferences slot pointer), not the slot's own
             * address: `mr r3, r9` at address 9092, where r9 was loaded
             * from the slot via `lwzx r9, r3, r29`. */
            IODereferenceClientTask((int *)client_entry[0]);

            /* Clear the entry (8 bytes = 2 ints) */
            bzero(client_entry, 8);

            /* Decrement global client count */
            notifClientCnt--;
        }
    }
}
