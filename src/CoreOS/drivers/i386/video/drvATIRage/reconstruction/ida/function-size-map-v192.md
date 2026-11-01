# v192 IDA function-size map

IDA 9.4 compared the reference driver and the native v192 artifact (restored v190 source). Addresses and sizes are hexadecimal; size deltas are rebuilt minus reference.

| Function | Reference start / size | Rebuilt start / size | Size delta |
|---|---:|---:|---:|
| `-[ATI initFromDeviceDescription:]` | `0000 / 680` | `0000 / 6e4` | `+64` |
| `-[ATI fixDeviceDescriptionForPCI:]` | `0680 / 660` | `06e4 / 62f` | `-31` |
| `_doBlit` | `14d8 / 142` | `150c / 14b` | `+9` |
| `-[ATI setGammaTable]` | `1c30 / 174` | `1c6c / 174` | `0` |
| `-[ATI setTransferTable:count:]` | `1de0 / 1e9` | `1e1c / 1d9` | `-10` |
| `-[ATI_BIOS setupCodeSegments]` | `2a1c / 184` | `2a30 / 186` | `+2` |
| `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | `2d44 / 102` | `2d5c / fe` | `-4` |

The `__bios16` entry is at `0x2e48` in the reference and `0x2e74` in v192; `_ATIbios16` is at `0x2ec0` and `0x2eec`, respectively. These addresses are symbol-derived. The map is for locating compiler-shape differences; it does not imply that matching only byte lengths would make the functions equivalent.

v192 is 224,532 bytes, SHA-256 `E65EDD26B3E07E0672E4CC4C1944429CDAAB5169927EDCED5D1A5921751C322D`. Binrecon reports 35 code findings across the same seven methods; strict `normalized-functions` remains false.