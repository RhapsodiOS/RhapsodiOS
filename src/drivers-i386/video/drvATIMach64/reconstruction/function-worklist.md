# drvATIMach64 routine worklist

Reference SHA-256: `AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C`  
IDA: IDA 9.4  
Coverage: 54 entries = 52 handwritten + 2 generated methods.

| Address | Size | Kind | Reference name | Review status |
| ---: | ---: | --- | --- | --- |
| `0x0000` | 2719 | handwritten | `-[ATI initFromDeviceDescription:]` | source reconstructed; parity pending |
| `0x0aa0` | 141 | handwritten | `-[ATI free]` | source reconstructed; parity pending |
| `0x0b30` | 277 | handwritten | `-[ATI enterLinearMode]` | source reconstructed; parity pending |
| `0x0c48` | 138 | handwritten | `-[ATI revertToVGAMode]` | source reconstructed; parity pending |
| `0x0cd4` | 12 | handwritten | `-[ATI displayModeCount]` | source reconstructed; parity pending |
| `0x0ce0` | 12 | handwritten | `-[ATI displayModes]` | source reconstructed; parity pending |
| `0x0cec` | 26 | handwritten | `-[ATI displayMemorySize]` | source reconstructed; parity pending |
| `0x0d08` | 123 | handwritten | `-[ATI setPendingDisplayMode:]` | source reconstructed; parity pending |
| `0x0d84` | 304 | handwritten | `-[ATI getQueryData]` | source reconstructed; parity pending |
| `0x0eb4` | 152 | handwritten | `-[ATI parseModeString:]` | source reconstructed; parity pending |
| `0x0f4c` | 412 | handwritten | `-[ATI updateModeList]` | source reconstructed; parity pending |
| `0x10e8` | 136 | handwritten | `-[ATI isModeValid:]` | source reconstructed; parity pending |
| `0x1170` | 98 | handwritten | `-[ATI verifyMemoryMap]` | source reconstructed; parity pending |
| `0x11d4` | 350 | handwritten | `-[ATI changeHardwareMapping:]` | source reconstructed; parity pending |
| `0x1334` | 346 | handwritten | `-[ATI changeTableMapping:]` | source reconstructed; parity pending |
| `0x1490` | 45 | handwritten | `_isATI68880RevC` | source reconstructed; parity pending |
| `0x14c0` | 82 | handwritten | `_SetGammaValue` | source reconstructed; parity pending |
| `0x1514` | 308 | handwritten | `-[ATI setGammaTable]` | source reconstructed; parity pending |
| `0x1648` | 60 | handwritten | `-[ATI setBrightness:token:]` | source reconstructed; parity pending |
| `0x1684` | 489 | handwritten | `-[ATI setTransferTable:count:]` | source reconstructed; parity pending |
| `0x1870` | 101 | handwritten | `_displayInfoToColorSpace` | source reconstructed; parity pending |
| `0x18d8` | 77 | handwritten | `_colorDepthToColorSpace` | source reconstructed; parity pending |
| `0x1928` | 79 | handwritten | `_displayInfoToColorDepth` | source reconstructed; parity pending |
| `0x1978` | 113 | handwritten | `_memSizeToBytes` | source reconstructed; parity pending |
| `0x19ec` | 12 | generated | `+[ATIMach64DisplayDriverKernelServerInstance kernelServerInstance]` | build-generated; parity pending |
| `0x19f8` | 12 | generated | `+[ATIMach64DisplayDriverVersion driverKitVersionForATIMach64DisplayDriver]` | build-generated; parity pending |
| `0x1a04` | 154 | handwritten | `+[ATI_BIOS ATIPresent:]` | source reconstructed; parity pending |
| `0x1aa0` | 162 | handwritten | `-[ATI_BIOS init]` | source reconstructed; parity pending |
| `0x1b44` | 65 | handwritten | `-[ATI_BIOS initAtSegmentAddress:]` | source reconstructed; parity pending |
| `0x1b88` | 65 | handwritten | `-[ATI_BIOS free]` | source reconstructed; parity pending |
| `0x1bcc` | 51 | handwritten | `-[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:]` | source reconstructed; parity pending |
| `0x1c00` | 153 | handwritten | `-[ATI_BIOS setVGAMode:gamma:]` | source reconstructed; parity pending |
| `0x1c9c` | 51 | handwritten | `-[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:]` | source reconstructed; parity pending |
| `0x1cd0` | 206 | handwritten | `-[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]` | source reconstructed; parity pending |
| `0x1da0` | 202 | handwritten | `-[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:]` | source reconstructed; parity pending |
| `0x1e6c` | 18 | handwritten | `-[ATI_BIOS querySize:size:]` | source reconstructed; parity pending |
| `0x1e80` | 190 | handwritten | `-[ATI_BIOS deviceQuery:bufferSize:buffer:]` | source reconstructed; parity pending |
| `0x1f40` | 134 | handwritten | `-[ATI_BIOS setDPMSMode:]` | source reconstructed; parity pending |
| `0x1fc8` | 114 | handwritten | `-[ATI_BIOS getDPMSMode:]` | source reconstructed; parity pending |
| `0x203c` | 134 | handwritten | `-[ATI_BIOS setAPMState:]` | source reconstructed; parity pending |
| `0x20c4` | 114 | handwritten | `-[ATI_BIOS getAPMState:]` | source reconstructed; parity pending |
| `0x2138` | 122 | handwritten | `-[ATI_BIOS getIOBaseAddress:relocatable:]` | source reconstructed; parity pending |
| `0x21b4` | 161 | handwritten | `-[ATI_BIOS getRefreshRate:]` | source reconstructed; parity pending |
| `0x2258` | 12 | handwritten | `-[ATI_BIOS changeRefreshRate:]` | source reconstructed; parity pending |
| `0x2264` | 80 | handwritten | `-[ATI_BIOS initBIOSBuf:function:]` | source reconstructed; parity pending |
| `0x22b4` | 388 | handwritten | `-[ATI_BIOS setupCodeSegments]` | source reconstructed; parity pending |
| `0x2438` | 102 | handwritten | `-[ATI_BIOS restoreCodeSegments]` | source reconstructed; parity pending |
| `0x24a0` | 212 | handwritten | `-[ATI_BIOS createDataSegment:size:]` | source reconstructed; parity pending |
| `0x2574` | 36 | handwritten | `-[ATI_BIOS restoreDataSegment]` | source reconstructed; parity pending |
| `0x2598` | 68 | handwritten | `-[ATI_BIOS doBios:dataSeg:]` | source reconstructed; parity pending |
| `0x25dc` | 258 | handwritten | `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | source reconstructed; parity pending |
| `0x26e0` | 117 | handwritten | `__bios16` | source reconstructed; parity pending |
| `0x2758` | 95 | handwritten | `_ATIbios16` | source reconstructed; parity pending |
| `0x27b8` | 203 | handwritten | `__ATIbios32` | source reconstructed; parity pending |
