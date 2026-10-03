# Evidence for the final recovered function group

The following implementations were written against the IDA 9.4 pseudocode for the supplied `BusLogicFPSCSI_reloc` reference image. Register offsets, structure strides, branch conditions, and side effects were checked against the decompilation; these are not inferred from the Linux BusLogic driver.

| Reference entry | Reconstruction evidence |
|---|---|
| `0x1c94 _autoCmdCmplt` | Completion-status switch, target status/EEPROM updates, sense-request setup, callback completion, and selection-failure path are represented in `FlashPoint.c`. The `busfree_auto_completion_and_msgout` trace case verifies a successful completion and per-LUN state clearing. |
| `0x2a90 _phaseMsgOut` | Message-out states, selection resume, negotiation reset, queue flush, ACK/REQ handling, and completion branches are represented. The trace case verifies its no-current-SCCB message handshake. |
| `0x2f68 _phaseBusFree` | Bus-free status states, reset-command cleanup, target negotiation flags, and target queue state are represented. The trace case verifies a negotiation transition and ACK writes. |
| `0x3160 _ScamInit` | The initialization sequence uses the `BL_Card` base-port field, EEPROM option word, SCAM entry states, legacy scan, arbitration, assignment, persistence, and two-device flag logic shown by IDA. |
| `0x3344 _ScamArbitration` | Both initial arbitration and common bus setup preserve IDA's signal tests, cleanup writes, wait, and return values. |
| `0x3488 _ScamBusFree` | Port 41/116/70/68/71/109/67 cleanup sequence follows the decompiled order; `scam_wire_cycles` asserts the control-register transitions. |
| `0x3530 _ScamAssignID` | ID string collection, isolate retry, match results 20/21, ID assignment encoding, and final transfer cycles follow the decompiled loop. |
| `0x3610 _ScamSelect` | Selection and SCAM signal/data handshakes follow the IDA port sequence. |
| `0x36a4 _ScamXferCycle` | Data-cycle setup, ready wait, sampled low five bits, and three wire transitions follow IDA; the same function is exercised through `ScamIsolate` in the trace harness. |
| `0x376c _ScamSendIsolate` | Per-byte, MSB-first arbitration and its match/termination checks follow the decompiled nested loops. |
| `0x380c _ScamIsolate` | Eight-bit ID byte assembly, malformed-cycle rejection, early terminator rules, and 32-byte limit follow IDA; `scam_wire_cycles` covers the empty-ID terminator. |
| `0x3924 _ScamSelLegacy` | EEPROM, command, interrupt, timeout, and completion register programming preserves the IDA order and both success/failure returns. |
| `0x3b7c _initScamInfo` | Sixteen or eight 32-byte IDs are loaded from EEPROM and classified into free or existing states using the port-41 hardware mode bit. |
| `0x3ca4 _scamMatchId` | Existing-ID match, free-slot allocation, replacement of an existing ID, states 16/17/18, and card dirty-bit updates follow IDA. `scam_id_matching` covers both direct match and free-slot allocation. |
| `0x3f04 _scamSaveDeviceInfo` | Existing EEPROM checksum, SCAM word persistence, new checksum word, and write-enable transitions follow IDA. `utilEEWrite` uses the reference calling convention `(base, data, address)`. |
| `0x46a0 _SccbMgr_start_sccb` | Lock boundaries, SCCB initialization, command-count/interrupt enable, queue decision, immediate selection, and port-41 gate cleanup follow IDA. `manager_entry_abort_and_select` covers the queued-start path. |
| `0x484c _SccbMgr_abort_sccb` | Active-port rejection, queued-command removal/callback, command count cleanup, and disconnected-command search follow IDA. The manager test covers queue removal and callback completion. |
| `0x4960 _SccbMgr_isr` | Interrupt snapshot, error delegation, event priority, phase and DMA dispatch, disconnect/reselection paths, deferred selection, and final interrupt gate cleanup follow IDA. |
| `0x4e88 _SccbMgr_bad_isr` | Adapter error, phase-sequence, selection-timeout, and bus-reset recovery branches follow IDA, including target negotiation-state resets and SCAM reinitialization. |
| `0x53e0 _scsiSelect` | Eligibility checks, reset and negotiation setup, tagged/untagged message setup, CDB FIFO writes, and interrupt start sequence follow IDA. `manager_entry_abort_and_select` checks target eligibility and the first CDB word. |
| `0x585c _scsiReselection` | Reselection target/lun/tag decoding, retry/abort handshakes, disconnected-command restoration, queue count adjustment, and selection reject completion follow IDA. |

The final native checks compile `FlashPoint.c` for `i386-unknown-none-elf` with warnings enabled and run the host register-trace suite. The repository has no configured Rhapsody driver-kit SDK or guest image, so these checks do not claim a kernel driver build or hardware runtime result.
