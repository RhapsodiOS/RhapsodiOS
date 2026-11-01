# Controller direct-method evidence

Reference identity: `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`.

The controller's 18 runtime ivars and total instance size `0x294` come from the IDA Objective-C class metadata at `0xc138/0xcb9c`; the mirrored i386 record is checked in `tests/layout.c`. A freestanding i386 Objective-C syntax/metadata compile against a stub superclass with the verified `0x244` inherited prefix emitted exactly 18 ivars, first offset 580, and instance size 660 (`0x294`). A zero-width alignment field rounds the class size without adding a runtime ivar. This source slice implements the ABI, completion, queue-dispatch, and command-submission methods listed below. Each entry is compared with IDA pseudocode and the corresponding instruction sequence:

| Reference entry | Reconstructed behavior |
|---|---|
| `0x000` `+[BLFPController probe:]` | Checks the config-table instance limit, decodes bus type, obtains PCI resources through `parseConfigSpace` or validates the non-PCI resource lists, probes the board, and initializes the controller. |
| `0x298` `initFromDeviceDescription:` | Initializes three circular queues and the command lock, converts the interrupt port, applies manager flags, resets hardware, validates IRQ sharing, creates SCCBs, reserves host target LUNs 0–7, enables interrupts, sets port backlog, and registers the device. |
| `0xa08` `probeForBoard` | Allocates and page-aligns the 64-byte manager-info block within a 128-byte allocation, fills I/O base/IRQ/owner/bus type, senses the adapter, derives target count from the wide-ID flag, and logs family/model/host ID. |
| `0xd48` `parseConfigSpace` | Reads the 256-byte PCI config space, requires a nonzero first BAR and IRQ, accepts exactly one I/O BAR among six entries, masks its low two bits, and installs the IRQ and port-range lists. |
| `0x554` `maxTransfer` | Returns `16 * page_size`. |
| `0x564` `numberOfTargets` | Returns the `targetsPerBus` byte. |
| `0x578` `free` | If the I/O thread is running, submits a zeroed 48-byte command record with command 2; frees the lock; frees the 128-byte raw manager block; invokes superclass `free`. |
| `0x610/0x620/0x630` queue statistics | Return total sample count, accumulated queue lengths, and maximum queue length respectively. |
| `0x640` `resetStats` | Clears those three counters only. |
| `0x668` `executeRequest:buffer:client:` | Zeroes 48 bytes; writes command 0 and request/buffer/client at offsets 4/8/12; synchronously calls `executeCmdBuf:`; returns offset 16. |
| `0x6b4` `resetSCSIBus` | Zeroes a command record, writes command 1, synchronously calls `executeCmdBuf:`, returns offset 16. |
| `0x6ec` `interruptOccurred` | Calls `SccbMgr_my_int` first and `SccbMgr_isr` only when pending; calls `enableAllInterrupts` afterward only for level IRQ. |
| `0x734/0x760` diagnostics | Log the named interrupt/message value. |
| `0x78c` `receiveMsg` | Logs the event then calls superclass `receiveMsg`. |
| `0x1704` `allocSccb` | Creates an SCCB page when the circular free list is empty, unlinks the first entry through SCCB links `+252/+256`, zeroes exactly 260 bytes, and returns it. |
| `0x1770` `freeSccb:` | Appends the supplied SCCB to the circular free list through links `+252/+256`. |
| `0x17bc` `createSCCBs` | Allocates one `page_size` block, walks in 260-byte strides while the fixed end pointer remains greater than the current address, skips page-crossing entries, zeroes and appends each accepted record. |
| `0x1684` `cmdComplete:` | Samples the completion timestamp when a request is present, stores the 64-bit elapsed value at request offsets 40/44 with low-word borrow, frees and clears the attached SCCB, then signals the command condition lock with value 1. |
| `0x13e8` `sccbComplete:reason:` | Clears and unschedules timeout flag `SCCB+244`; maps reasons 1/2 to request statuses 5/20; for normal completion unlinks the SCCB and decrements outstanding count, copies target status, computes transferred bytes as command-record length minus the updated SCCB residual, maps host/SCSI statuses, stores command result, and calls `cmdComplete:`. |
| `0x1860` `resetHardware` | Calls `SccbMgr_config_adapter`; on `-1` logs and returns 1; otherwise stores the card pointer, logs reset, sleeps 10,000 ms and returns 0. |
| `0x8e8` `commandRequestOccurred` | Holds `commandLock` while removing the first command record, releases it while dispatching reset/execute/exit commands, then reacquires and continues until the circular queue is empty. |
| `0xc18` `executeCmdBuf:` | Allocates a condition lock, appends the 48-byte command record under `commandLock`, sends the exact 24-byte kernel wake message, waits for completion only after successful send, frees the lock, and returns `-703` for send failure. |
| `0xefc` `threadExecuteRequest:` | Allocates and converts an SCCB; conversion failure completes immediately. Success records the kernel port, schedules timeout, appends to `outstandingQ`, updates queue statistics, and starts the SCCB. |
| `0xffc` `threadResetBus:` | Removes outstanding SCCBs from the head in order and completes each with reset reason 2; resets the adapter; signals an optional command with result 0 or 22; reenables interrupts for level IRQ. |
| `0x10c0` `sccbFromCmd:` | Decodes CDB groups 0/1/2/5/6/7, rejects unsupported groups and control-link bits with request status 7, translates the sense buffer, initializes SCCB identity/timing, and selects no-data, direct, or up-to-17-entry page-split SG transfer. Translation failures set request status 14. |
| `0x7d4` `timeoutOccurred` | Samples time once, scans outstanding SCCBs in queue order, unlinks expired requests before completing with reason 1, decrements the outstanding count, and resets the bus after the scan if any request expired. |

These methods were checked against the IDA pseudocode and instruction sequences. SCCB allocation, completion, dispatch, request conversion, timeout, PCI/adapter probe, initialization, submit, and reset code passes freestanding i386 Objective-C syntax compilation using the SDK stubs, with intrusive-list pointers compiled at 32 bits. SCSI message parsing and the manager/interrupt engine remain pending; this evidence does not claim the driver is complete.
