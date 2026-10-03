# Manager initialization evidence

Reference identity: `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`.

IDA at `0x4938` shows `SccbMgr_my_int` reading one byte at the card I/O base plus 55 and testing bit `0x20`. At `0x51bc`, `SccbMgrTableInitAll` initializes exactly four 20-byte card records, clears the manager-info and I/O-base pointers, sets manager card index to `0xff`, and clears host ID. `SccbMgrTableInitCard` loops over 16 targets, clears target bytes `+2/+3`, initializes each target, then clears the card queue cursor/current SCCB/card flags/command count. The card record uses index `+14`, queue cursor `+15`, flags `+16`, and host ID `+17`. `SccbMgrTableInitTarget` clears target bytes `0..31` and LUN counters `+32..+63`, all 33 disconnected pointers, selection head/tail, eligibility/count and sync byte; its loop returns the last index (32).

At `0x6d94`, `scsiInitSCCB` initializes transfer flags/counts, preserves the binary's SG opcode decisions (2/4), sets the no-data bit, updates tagged-command/target flags, writes identify message `LUN|0x80` or `LUN|0xc0`, clears host/target/tag/manager/SG/ATC/saved-ATC/phase/completion state, emits message byte 8, and returns `5 * cardIndex`. The tag policy reads the 80-byte `BL_CardFlags` table and the target status byte at `+206`.

The production-function tests seed the complete card and target tables with nonzero bytes before initialization, verify the cleared regions and sentinels, exercise SG+zero-data/tagged SCCB setup, and assert the interrupt-pending port offset and mask. The native suite passes; all affected translation units compile for freestanding i386 with warnings as errors.
