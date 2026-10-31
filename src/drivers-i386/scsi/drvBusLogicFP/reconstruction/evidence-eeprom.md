# EEPROM serial path evidence

Reference identity: `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`.

IDA ranges `0x7480..0x7780` confirm the EEPROM routines. `utilEESendCmdAddr` reads `B+41 & 0x10`, writes `0x20,0x28`, shifts command bits `4,2,1`, then shifts address bits starting at `0x80` when clear or `0x200` when set until the shifted bit becomes zero. Each bit writes data, clock-high, clock-low to `B+34`. The serial command trace therefore has three command bits and eight or ten address bits.

`utilEEWriteOnOff` preserves `IN B+34 & 0xc0`, sends command 4 with address 960 or 0, then emits `(top|0x20, top)`. `utilEEWrite` sends command 5, shifts 16 data bits from `0x8000` through 1, calls `Wait(B,7)`, and emits the exact final `(top|0x20, top|0x28, top|0x20, top)` sequence. `utilEERead` sends command 6, samples exactly 16 bits from `IN B+34 & 1`, shifts MSB-first, and emits its end/idle pair without a readiness wait.

Production tests exercise `utilEESendCmdAddr` in 10-bit address mode and `utilEERead` with 16 one-bit samples. They assert 42 total events for the former (one read, 41 writes) and 93 events for the latter (18 reads, 75 writes); both pass. Production source and tests compile as freestanding i386 with warnings as errors.
