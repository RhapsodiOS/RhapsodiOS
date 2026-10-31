# SCSI request setup and sync-register evidence

Reference identity: `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`.

At `0x691c`, `scsiSenseSetup` saves the original CDB length and first six bytes, writes a six-byte REQUEST SENSE CDB (`03`, preserves `CDB[1]&0xe0`, zeroes bytes 2/3/5, and places sense length in byte 4), sets transfer count from sense length, clears ATC, toggles transfer-state bits `+95`, clears identify bit `0x40`, clears control byte, and keeps only manager-flag bit 0. The production test seeds each changed field and verifies the saved CDB and resulting flags.

At `0x66b0`, `scsiSetSyncValue` maps target IDs to register offsets in order `12,13,14,15,8,9,10,11,4,5,6,7,0,1,2,3`, writes the value to `base+84+offset`, stores that byte at target `+208`, and returns the output helper result. The focused test verifies target 3 maps to `base+99` and stores the value.

At `0x5318`, `scsiFetchMsg` polls `base+68 & 0x20` using the `0x4e1f` loop bound, selects the message register with `OUT base+70,0x80`, reads from `base+116`, and acknowledges with `OUT base+68,0x12`. When both `IN base+66 & 0x20` and `IN base+78 & 1` are set, it clears the pending bit, stores message state 9 at SCCB `+72`, waits for the handshake bit to clear, writes `0x0a` to `base+68`, and returns zero. Tests assert both the ordinary path's register order and the handshake path's state/result.
