# drvATIMach64 routine worklist

Reference SHA-256: `AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C`  
IDA: IDA 9.4  
Coverage: 54 entries = 52 handwritten + 2 generated methods.

| Address | Size | Kind | Reference name | Review status |
| ---: | ---: | --- | --- | --- |
| `0x0000` | 2719 | handwritten | `-[ATI initFromDeviceDescription:]` | unexamined |
| `0x0aa0` | 141 | handwritten | `-[ATI free]` | unexamined |
| `0x0b30` | 277 | handwritten | `-[ATI enterLinearMode]` | unexamined |
| `0x0c48` | 138 | handwritten | `-[ATI revertToVGAMode]` | unexamined |
| `0x0cd4` | 12 | handwritten | `-[ATI displayModeCount]` | unexamined |
| `0x0ce0` | 12 | handwritten | `-[ATI displayModes]` | unexamined |
| `0x0cec` | 26 | handwritten | `-[ATI displayMemorySize]` | unexamined |
| `0x0d08` | 123 | handwritten | `-[ATI setPendingDisplayMode:]` | unexamined |
| `0x0d84` | 304 | handwritten | `-[ATI getQueryData]` | unexamined |
| `0x0eb4` | 152 | handwritten | `-[ATI parseModeString:]` | unexamined |
| `0x0f4c` | 412 | handwritten | `-[ATI updateModeList]` | unexamined |
| `0x10e8` | 136 | handwritten | `-[ATI isModeValid:]` | unexamined |
| `0x1170` | 98 | handwritten | `-[ATI verifyMemoryMap]` | unexamined |
| `0x11d4` | 350 | handwritten | `-[ATI changeHardwareMapping:]` | unexamined |
| `0x1334` | 346 | handwritten | `-[ATI changeTableMapping:]` | unexamined |
| `0x1490` | 45 | handwritten | `_isATI68880RevC` | unexamined |
| `0x14c0` | 82 | handwritten | `_SetGammaValue` | unexamined |
| `0x1514` | 308 | handwritten | `-[ATI setGammaTable]` | unexamined |
| `0x1648` | 60 | handwritten | `-[ATI setBrightness:token:]` | unexamined |
| `0x1684` | 489 | handwritten | `-[ATI setTransferTable:count:]` | unexamined |
| `0x1870` | 101 | handwritten | `_displayInfoToColorSpace` | unexamined |
| `0x18d8` | 77 | handwritten | `_colorDepthToColorSpace` | unexamined |
| `0x1928` | 79 | handwritten | `_displayInfoToColorDepth` | unexamined |
| `0x1978` | 113 | handwritten | `_memSizeToBytes` | unexamined |
| `0x19ec` | 12 | generated | `+[ATIMach64DisplayDriverKernelServerInstance kernelServerInstance]` | unexamined |
| `0x19f8` | 12 | generated | `+[ATIMach64DisplayDriverVersion driverKitVersionForATIMach64DisplayDriver]` | unexamined |
| `0x1a04` | 154 | handwritten | `+[ATI_BIOS ATIPresent:]` | unexamined |
| `0x1aa0` | 162 | handwritten | `-[ATI_BIOS init]` | unexamined |
| `0x1b44` | 65 | handwritten | `-[ATI_BIOS initAtSegmentAddress:]` | unexamined |
| `0x1b88` | 65 | handwritten | `-[ATI_BIOS free]` | unexamined |
| `0x1bcc` | 51 | handwritten | `-[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:]` | unexamined |
| `0x1c00` | 153 | handwritten | `-[ATI_BIOS setVGAMode:gamma:]` | unexamined |
| `0x1c9c` | 51 | handwritten | `-[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:]` | unexamined |
| `0x1cd0` | 206 | handwritten | `-[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]` | unexamined |
| `0x1da0` | 202 | handwritten | `-[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:]` | unexamined |
| `0x1e6c` | 18 | handwritten | `-[ATI_BIOS querySize:size:]` | unexamined |
| `0x1e80` | 190 | handwritten | `-[ATI_BIOS deviceQuery:bufferSize:buffer:]` | unexamined |
| `0x1f40` | 134 | handwritten | `-[ATI_BIOS setDPMSMode:]` | unexamined |
| `0x1fc8` | 114 | handwritten | `-[ATI_BIOS getDPMSMode:]` | unexamined |
| `0x203c` | 134 | handwritten | `-[ATI_BIOS setAPMState:]` | unexamined |
| `0x20c4` | 114 | handwritten | `-[ATI_BIOS getAPMState:]` | unexamined |
| `0x2138` | 122 | handwritten | `-[ATI_BIOS getIOBaseAddress:relocatable:]` | unexamined |
| `0x21b4` | 161 | handwritten | `-[ATI_BIOS getRefreshRate:]` | unexamined |
| `0x2258` | 12 | handwritten | `-[ATI_BIOS changeRefreshRate:]` | unexamined |
| `0x2264` | 80 | handwritten | `-[ATI_BIOS initBIOSBuf:function:]` | unexamined |
| `0x22b4` | 388 | handwritten | `-[ATI_BIOS setupCodeSegments]` | unexamined |
| `0x2438` | 102 | handwritten | `-[ATI_BIOS restoreCodeSegments]` | unexamined |
| `0x24a0` | 212 | handwritten | `-[ATI_BIOS createDataSegment:size:]` | unexamined |
| `0x2574` | 36 | handwritten | `-[ATI_BIOS restoreDataSegment]` | unexamined |
| `0x2598` | 68 | handwritten | `-[ATI_BIOS doBios:dataSeg:]` | unexamined |
| `0x25dc` | 258 | handwritten | `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | unexamined |
| `0x26e0` | 117 | handwritten | `__bios16` | unexamined |
| `0x2758` | 95 | handwritten | `_ATIbios16` | unexamined |
| `0x27b8` | 203 | handwritten | `__ATIbios32` | unexamined |
