# v205 IDA function-size map

IDA 9.4 compared the native v205 candidate against the supplied reference. Addresses, sizes, and deltas are hexadecimal.

| Function | Reference start / size | Rebuilt start / size | Size delta |
|---|---:|---:|---:|
| `-[ATI initFromDeviceDescription:]` | `0000 / 680` | `0000 / 6e4` | `+64` |
| `-[ATI fixDeviceDescriptionForPCI:]` | `0680 / 660` | `06e4 / 62f` | `-31` |
| `_doBlit` | `14d8 / 142` | `150c / 14b` | `+9` |
| `-[ATI setGammaTable]` | `1c30 / 174` | `1c6c / 174` | `0` |
| `-[ATI setTransferTable:count:]` | `1de0 / 1e9` | `1e1c / 1e5` | `-4` |
| `-[ATI_BIOS setupCodeSegments]` | `2a1c / 184` | `2a3c / 186` | `+2` |
| `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | `2d44 / 102` | `2d68 / fe` | `-4` |

The transfer-table method is now four bytes shorter than the reference (v194 was sixteen bytes shorter). IDA disassembly has 131 normalized instruction lines in common out of 153, versus 127 for v194. Its initial ASIC/DAC loads, stack spill, address load, zero-extension mask, and compare sequence match the reference; remaining differences are later branch layout, color-space dispatch, and loop register allocation. Global Binrecon remains at 35 code findings across the same seven methods, with strict `normalized-functions` still false.

v205 `_reloc` SHA-256: `6F56172DA4301104D2C854FC9F4C9D1805734F5B79DBA11AD1C23FC293D176B2`. Direct Hex-Rays sweep decompiled all 61 functions with zero failures; see `rebuilt-pseudocode-v205.md`.
