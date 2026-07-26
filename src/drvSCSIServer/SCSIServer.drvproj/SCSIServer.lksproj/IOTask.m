/*
 * IOTask.m
 * Mach task, memory-wiring, and client-death-notification plumbing for SCSIServer driver
 */

#import "IOTask.h"
#import <mach/mach.h>

/* Global entry structure pointer
 * The '_entry' global contains pointers to kernel functions and data:
 * offset +0x18: Task port for memory operations
 * offset +0xa4: Mach port management functions
 */
extern struct {
    char pad1[0x18];
    mach_port_t task_port;     /* offset +0x18 */
    char pad2[0x8c];
    void *port_funcs;          /* offset +0xa4 */
} *_entry;

/* Page size global - used for address alignment */
extern unsigned int _page_size;

/* ========================================================================
 * Client Reference Counting (data)
 * ======================================================================== */

/*
 * Client reference tracking structure
 *
 * Located at address 0x4008 in the binary
 * Valid range: 0x4008 - 0x4087 (128 bytes = 32 ints)
 * Boundary at 0x4088 is marked as _notifyThread
 *
 * This is an array of reference counts, where each entry is a single int
 * representing the reference count for that client slot. The IOReferenceClientTask
 * function searches this array for empty slots (value == 0) and allocates them
 * as needed.
 *
 * Structure:
 * - Array of 32 integers (128 bytes total)
 * - Each entry is a reference count (not a struct)
 * - Empty slots have value 0
 * - Allocated slots have reference count >= 1
 */
static int _clientReferences[32] = {0};  /* Client reference array at 0x4008-0x4087 */

/*
 * Notify thread identifier or boundary marker
 *
 * Located at address 0x4088 in the binary, immediately after _clientReferences
 * This serves as a boundary marker for the client references array in
 * IOReferenceClientTask, which searches until it reaches &_notifyThread.
 *
 * Cross-references show this is used by IORequestNotifyForClientTask,
 * suggesting it may be a thread identifier for notification handling.
 */
static int _notifyThread = 0;  /* Notify thread or boundary marker at 0x4088 */

/* ========================================================================
 * Client Task Notification Management (data)
 * ======================================================================== */

/*
 * Global notification client tracking
 * Maximum 32 (0x20) notification clients can be registered
 *
 * Structure:
 * - notifClients[64]: Array of 32 client entries (2 ints each = 8 bytes)
 *   Entry structure:
 *   offset +0: death port (mach_port_t)
 *   offset +4: reference count
 * - DAT_00004098[64]: Parallel array storing session objects (id)
 * - notifClientCnt: Current number of registered clients
 */
static int notifClients[64];      /* 32 entries * 2 ints = 64 ints */
static id notifClientObjects[32]; /* Parallel array for session objects */
static int notifClientCnt = 0;    /* Current client count */

/* ========================================================================
 * Port Management Functions
 * ======================================================================== */

/*
 * IOTaskPortAllocateName - Allocate and assign a name to a Mach port
 * name: Port name to assign
 */
void IOTaskPortAllocateName(mach_port_t name)
{
    int result;
    mach_port_t allocated_port;
    void *port_funcs;

    /* Get port management functions from global entry structure */
    port_funcs = _entry->port_funcs;

    /* TODO: Allocate port
     * result = FUN_000019ac(port_funcs, &allocated_port)
     */
    result = 0;

    if (result == 0) {
        /* TODO: Insert send right with name
         * FUN_0000199c(port_funcs, allocated_port, name)
         */
    }
}

/*
 * IOTaskPortDeallocate - Deallocate a Mach port
 * port: Mach port to deallocate
 */
void IOTaskPortDeallocate(mach_port_t port)
{
    void *port_funcs;

    /* Get port management functions from global entry structure */
    port_funcs = _entry->port_funcs;

    /* TODO: Call mach_port_deallocate()
     * FUN_00001a2c(port_funcs, port)
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
    mach_port_t task_port;

    /* Get task port from global entry structure */
    task_port = _entry->task_port;

    /* Align start address to page boundary (round down) */
    start_addr = address & ~(_page_size - 1);

    /* Calculate end address aligned to page boundary (round up) */
    end_addr = (address + length + (_page_size - 1)) & ~(_page_size - 1);

    /* TODO: Call kernel vm_wire() function
     * FUN_00001a8c(task_port, start_addr, end_addr, 0)
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
    mach_port_t task_port;

    /* Get task port from global entry structure */
    task_port = _entry->task_port;

    /* Align start address to page boundary (round down) */
    start_addr = address & ~(_page_size - 1);

    /* Calculate end address aligned to page boundary (round up) */
    end_addr = (address + length + (_page_size - 1)) & ~(_page_size - 1);

    /* TODO: Call kernel vm_unwire() function
     * FUN_00001aec(task_port, start_addr, end_addr, 1)
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
    if ((current_entry < &_clientReferences[0]) || (current_entry > &_clientReferences[31])) {
        /* Entry not in valid range - need to find or allocate a slot */

        /* Start search at beginning of client references table
         * piVar2 = &_clientReferences
         */
        search_ptr = _clientReferences;

        /* Search for an empty slot (where *slot == 0)
         * Decompiled:
         * do {
         *   if (*piVar2 == 0) break;
         *   piVar2 = piVar2 + 1;
         * } while (piVar2 < &_notifyThread);
         */
        while (search_ptr < &_notifyThread) {
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
        if (search_ptr > &_clientReferences[31]) {
            /* No empty slots available */
            return 6;  /* Error code 6: no slots */
        }

        /* Call kernel function to set up the reference
         * Decompiled: iVar1 = FUN_00001be4(*(undefined4 *)(_entry + 0xa4),*clientReferenceSlot,piVar2)
         *
         * This appears to be a kernel function that:
         * - Takes the port functions pointer from _entry+0xa4
         * - Takes the original *clientReferenceSlot value (client identifier?)
         * - Takes the allocated slot pointer
         * - Returns 0 on success, error code on failure
         */
        result = 0;  /* TODO: Call actual kernel function */
        /* result = FUN_00001be4(_entry->port_funcs, *clientReferenceSlot, search_ptr); */

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
     * Range check: &_clientReferences[0] <= clientEntry <= &_notifyThread,
     * the same bounds IOReferenceClientTask uses for the same table
     * (_clientReferences[i] is a bare int refcount, offset +0 is the
     * entire entry -- there is no offset +4 field here)
     */
    if ((clientEntry < &_clientReferences[0]) ||
        (clientEntry > &_notifyThread)) {
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
        /* Call function from entry table at offset 0xa4
         * This appears to be a Mach port cleanup function
         * FUN_00001c88(*(undefined4 *)(_entry + 0xa4))
         *
         * This likely calls mach_port_deallocate() or similar
         */
        result = 0;  /* Placeholder - actual cleanup would happen here */
    }
    else {
        result = 0;  /* Success, refcount still > 0 */
    }

    return result;
}

/* ========================================================================
 * Client Task Notification Management
 * ======================================================================== */

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
         *   notifClients[i*2+1]: reference count
         */
        client_entry = &notifClients[i * 2];

        /* Check if this entry matches the death port and session */
        if ((client_entry[0] == (int)deathPort) &&
            (notifClientObjects[i] == session)) {

            /* Dereference the client task (decrements reference count) */
            IODereferenceClientTask(&notifClients[i * 2]);

            /* Clear the entry (8 bytes = 2 ints) */
            memset(client_entry, 0, 8);

            /* Decrement global client count */
            notifClientCnt--;
        }
    }
}
