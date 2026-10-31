# Phase and transfer evidence

The implementations below were checked against the opened `BusLogicFPSCSI_reloc` database in IDA 9.4. The listed addresses are the function entries in the reference image; the per-routine control flow and immediate values were compared with Hex-Rays pseudocode and instruction disassembly.

| Reference entry | Routine | Evidence and checks |
| --- | --- | --- |
| `0x195c` | `autoLoadDefaultMap` | Preserves the 43 ordered 16-bit microcode words, index-port enable/disable sequence, and consecutive word-port offsets. The `default_map_programming` trace verifies the first and final words and all 47 I/O events. |
| `0x2594` | `hostDataXferRestart` | Preserves direct residual calculation and SG traversal, including exact-boundary and interior-offset branches. `transfer_restart_paths` covers direct, interior, and exact-boundary cases. |
| `0x2810` | `phaseDataOut` | Matches the current SCCB state, direction flag mask, DMA kick sequence, overrun status check, and decode path. `phase_command_and_data_paths` verifies state and register setup. |
| `0x28d0` | `phaseDataIn` | Matches the input direction flags, DMA kick sequence, overrun status check, and decode path. `phase_command_and_data_paths` verifies state and register setup. |
| `0x2994` | `phaseCommand` | Matches reset-command substitution, command FIFO words, optional terminator, SCSI command state, and interrupt-control bit sequence. `phase_command_and_data_paths` verifies the emitted CDB and terminator. |
| `0x2d68` | `phaseIllegal` | Matches interrupt acknowledgement, SCCB error-state updates when a command is active, FIFO wait, and command clear. Compiled for the i386 target. |
| `0x2dd0` | `phaseChkFifo` | Matches inbound FIFO drain, DMA count accounting, parity-status recording, transfer abort/restart, and FIFO cleanup. `phase_fifo_residual_accounting` checks residual-to-ATC accounting and I/O widths. |
| `0x698c` | `scsiXferPad` | Matches DMA completion acknowledgement, phase-preserving padding loop, FIFO handshakes, and status short-circuit. `transfer_pad_status_short_circuit` verifies the acknowledgement and early status branch. |

`FlashPoint.c` and the ABI assertions compile with Clang's `i386-unknown-none-elf` target. The queue and hardware-trace harness also runs on the native host; no physical adapter execution is available in this environment.
