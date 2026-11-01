# v194 IDA function-size map

IDA 9.4 compared the restored v194 native baseline against the supplied reference. Addresses, sizes, and deltas are hexadecimal.

| Function | Reference start / size | Rebuilt start / size | Size delta |
|---|---:|---:|---:|
| `-[ATI initFromDeviceDescription:]` | `0000 / 680` | `0000 / 6e4` | `+64` |
| `-[ATI fixDeviceDescriptionForPCI:]` | `0680 / 660` | `06e4 / 62f` | `-31` |
| `_doBlit` | `14d8 / 142` | `150c / 14b` | `+9` |
| `-[ATI setGammaTable]` | `1c30 / 174` | `1c6c / 174` | `0` |
| `-[ATI setTransferTable:count:]` | `1de0 / 1e9` | `1e1c / 1d9` | `-10` |
| `-[ATI_BIOS setupCodeSegments]` | `2a1c / 184` | `2a30 / 186` | `+2` |
| `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | `2d44 / 102` | `2d5c / fe` | `-4` |

The map records the seven methods that keep `normalized-functions` from passing. It prioritizes the size deltas only; equal function length does not establish instruction or control-flow parity. The v194 `_reloc` SHA-256 is `6CB08D60398CCD45992A2A0124B23461426CD789C9E73BE34A60C7CC1847C7D9`. The fresh complete rebuilt pseudocode export is `rebuilt-pseudocode-v194.md` (61 functions, zero Hex-Rays failures).
