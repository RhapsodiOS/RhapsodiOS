# Small helper evidence

Reference identity: `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`.

| Entry | IDA-confirmed behavior and check |
|---|---|
| `0x18b4` `blcTimeout` | Sends the 24-byte timeout message only when `SCCB+244` is set, taking its remote port from `SCCB+240`; the Objective-C translation compiles for i386. |
| `0x193c` `BLCCallback` | Reads controller at `SCCB+248` and completes that SCCB with reason 0; the Objective-C translation compiles for i386. |
| `0x1ea0` `dataXferProcessor` | Uses the card's current SCCB; starts SG/direct bus-master transfer once, and on repeated SG restart advances the segment index by 16 and clears SG offset. The host test checks both first and repeated paths with mocked bus-master entry points. |
| `0x2a78` `phaseStatus` | Writes command `0x2a` to `base+100`; host test checks port, width, and value. |
| `0x3880/0x38bc` `ScamWireOrData` / `ScamWireOrSig` | Polls the selected port until 16 consecutive samples lack the requested mask bit; `ScamWireOrData` is host-tested for the 16-sample bound. |
| `0x38f8` `ScamValidQ` | Applies the reference seven-bit loop, adding `0x80` for each absent bit before testing mask `0x18`; host test covers valid and invalid values. |
| `0x3b5c` `ScamWaitSelection` | Polls `base+66` until bit 2 is set; host test checks two reads and the returned final byte. |
| `0x51b4` `SccbMgr_timer_expired` | Empty return in the reference; implemented as an empty function. |

The host executable passed the existing queue, residual, EEPROM, sense/sync, and message cases plus these new helper cases. Production C and Objective-C syntax checks passed with `-Wall -Wextra -Werror` for `i386-unknown-none-elf`. The host executable is not an i386 runtime test.
