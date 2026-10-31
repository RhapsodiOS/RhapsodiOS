# v213 IDA function-size map

IDA 9.4 compared the final v213 native candidate against the supplied reference. Addresses, sizes, and deltas are hexadecimal.

| Function | Reference start / size | Rebuilt start / size | Size delta |
|---|---:|---:|---:|
| `-[ATI initFromDeviceDescription:]` | `0000 / 680` | `0000 / 6e4` | `+64` |
| `-[ATI fixDeviceDescriptionForPCI:]` | `0680 / 660` | `06e4 / 62f` | `-31` |
| `_doBlit` | `14d8 / 142` | `150c / 14b` | `+9` |
| `-[ATI setGammaTable]` | `1c30 / 174` | `1c6c / 174` | `+0` |
| `-[ATI setTransferTable:count:]` | `1de0 / 1e9` | `1e1c / 1e9` | `+0` |
| `-[ATI_BIOS setupCodeSegments]` | `2a1c / 184` | `2a40 / 186` | `+2` |
| `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | `2d44 / 102` | `2d6c / fe` | `-4` |

Transfer-table function size is exact at 0x1e9; normalized disassembly LCS is 145/153 lines. Binrecon reports 35 code findings across the same seven methods; strict `normalized-functions` remains false.
