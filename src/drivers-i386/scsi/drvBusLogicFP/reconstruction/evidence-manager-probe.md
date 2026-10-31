# Adapter sensing and phase dispatch evidence

Reference identity: `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`.

`SccbMgr_sense_adapter` at `0x4010` first checks the four-byte `4b 10 30 81` signature and then accepts either status byte `base+51 == 15` or a zero low nibble at `base+6`. A bad first signature byte returns `-1` after one input; `manager_probe_rejects_bad_signature` checks that short-circuit and read width. The remaining EEPROM-derived settings, register masks, family/model fields, and phase table assignments follow the IDA pseudocode and disassembly. The full serial-success trace remains a follow-on manager test.

`phaseDecode` at `0x27c8` writes `2` then `0` to `base+71`, reads `base+68`, masks to the low three phase bits, and dispatches through the table initialized by adapter sensing. `phaseStatus` at `0x2a78` writes `0x2a` to `base+100` and is covered by the host I/O trace test. The production C translation compiles for i386 with warnings as errors.
