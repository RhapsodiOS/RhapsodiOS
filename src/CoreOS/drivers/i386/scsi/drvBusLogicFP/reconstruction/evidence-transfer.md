# Bus-master transfer evidence

These routines were checked against the corresponding IDA pseudocode and instruction sequences in `BusLogicFPSCSI_reloc`. Clang's i386 freestanding syntax check passes for `FlashPoint.c`.

| Reference entry | Routine | Evidence and checks |
| --- | --- | --- |
| `0x1eec` | `busMstrSGDataXferStart` | Reconstructs the SG table entry stride and port sequence, direction control bits, count register, transfer length, and final channel enable. `bus_master_transfer_registers` checks the emitted address/control words and direction setup. |
| `0x209c` | `busMstrDataXferStart` | Reconstructs sense-buffer versus data-buffer address selection, split address and length writes, and input/output start sequence. `bus_master_transfer_registers` checks the direct data path. |
| `0x217c` | `busMstrTimeOut` | Preserves both bounded status polls, timeout clear commands, interrupt-status read, and final active bit result. The loop bounds and register sequence were compared against IDA. |
| `0x2218` | `hostDataXferAbort` | Reconstructs direct and SG DMA shutdown, sense-buffer handling, bounded FIFO and channel waits, residual SG rewind, host-status updates, and final DMA clear. `host_transfer_abort_completion` covers direct and SG completion branches. |
| `0x25f0` | `XbowInit` | Preserves adapter initialization register sequence and optional X-bus enable based on the port capability bit. Compared with IDA instruction order. |
| `0x26b4` | `BusMasterInit` | Preserves controller reset, timing, interrupt clear, and DMA-channel enable setup. Compared with IDA instruction order. |
