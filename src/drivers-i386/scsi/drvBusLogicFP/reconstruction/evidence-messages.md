# SCSI message phase evidence

The SCSI message routines below were checked against IDA pseudocode and instruction flow in the reference image. Clang's i386 freestanding compile and the native register-trace tests cover the reconstructed source.

| Reference entry | Routine | Evidence and checks |
| --- | --- | --- |
| `0x2ce8` | `phaseMsgIn` | Matches FIFO-pending dispatch, bus phase handling, message fetch, and decode dispatch. `message_decode_error_paths` checks the message-phase reject handshake. |
| `0x5b2c` | `scsiDecodeMsg` | Reconstructs command-complete, save/restore pointer, disconnect, reject, extended-message, and invalid-message branches, including target negotiation state and register acknowledgements. `message_decode_error_paths` verifies invalid-message status and handshake output. |
| `0x5e24` | `scsiHandleExtMsg` | Reconstructs the two-byte extended-message read and routes synchronous and wide negotiation replies to their target handlers; unsupported lengths/types set message state and reject. Compared control flow with IDA. |
| `0x5f58` | `scsiInitSyncNego` | Reconstructs synchronous negotiation eligibility, EEPROM period selection, scripted command words, and target state transition. `negotiation_register_programming` checks the accepted-state branch. |
| `0x60c8` | `scsiTargSyncNego` | Reconstructs period/offset reads, configured minimum period, offset clamp, rate encoding, target sync update, and response/reject branches. Compared with IDA. |
| `0x6288` | `scsiInitSyncRespond` | Reconstructs the response microcode words, index-port toggle, transfer setup, and ready-bit poll. `negotiation_register_programming` checks emitted period/offset words and the completion poll. |
| `0x6398` | `scsiInitWideNego` | Reconstructs wide negotiation eligibility, command script, and target state change. `negotiation_register_programming` checks the accepted-state branch. |
| `0x64bc` | `scsiTargWideNego` | Reconstructs target width response, sync-register update, completion acknowledgement, and initiator response branch. Compared with IDA. |
| `0x65bc` | `scsiInitWideRespond` | Reconstructs the response microcode, bus index toggle, transfer start, and ready-bit polling. `negotiation_register_programming` checks the width word and poll. |
| `0x6bac` | `scsiChkDmaDone` | Reconstructs odd-byte correction, residual transfer accounting, bounded DMA/FIFO polling, and phase redispatch. `dma_completion_phase_filter` checks the non-data-phase early return. |
