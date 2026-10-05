# Rebuilt drvATIRage i386 function map — v228

| Start | End | Bytes | Function |
|---:|---:|---:|---|
| 0x0 | 0x6E4 | 1764 | -[ATI initFromDeviceDescription:] |
| 0x6E4 | 0xD13 | 1583 | -[ATI fixDeviceDescriptionForPCI:] |
| 0xD14 | 0xE44 | 304 | -[ATI getQueryData] |
| 0xE44 | 0xED4 | 144 | -[ATI parseModeString:] |
| 0xED4 | 0x10F0 | 540 | -[ATI updateModeList] |
| 0x10F0 | 0x1178 | 136 | -[ATI isModeValid:] |
| 0x1178 | 0x11DA | 98 | -[ATI verifyMemoryMap] |
| 0x11DC | 0x1269 | 141 | -[ATI free] |
| 0x126C | 0x1390 | 292 | -[ATI enterLinearMode] |
| 0x1390 | 0x148C | 252 | -[ATI revertToVGAMode] |
| 0x148C | 0x14C0 | 52 | _waitForFIFO |
| 0x14C0 | 0x1509 | 73 | _waitForIdle |
| 0x150C | 0x1654 | 328 | _doBlit |
| 0x1654 | 0x1697 | 67 | -[ATI showCursor:frame:token:] |
| 0x1698 | 0x16DB | 67 | -[ATI moveCursor:frame:token:] |
| 0x16DC | 0x1715 | 57 | -[ATI hideCursor:] |
| 0x1718 | 0x179D | 133 | _doFill |
| 0x17A0 | 0x19D6 | 566 | -[ATI initEngine] |
| 0x19D8 | 0x1A52 | 122 | -[ATI resetEngine] |
| 0x1A54 | 0x1A60 | 12 | -[ATI displayModeCount] |
| 0x1A60 | 0x1A6C | 12 | -[ATI displayModes] |
| 0x1A6C | 0x1A86 | 26 | -[ATI displayMemorySize] |
| 0x1A88 | 0x1B1F | 151 | -[ATI setPendingDisplayMode:] |
| 0x1B20 | 0x1BF0 | 208 | -[ATI setIntValues:forParameter:count:] |
| 0x1BF0 | 0x1C11 | 33 | _isATI68880RevC |
| 0x1C14 | 0x1C68 | 84 | _SetGammaValue |
| 0x1C68 | 0x1DDC | 372 | -[ATI setGammaTable] |
| 0x1DDC | 0x1E18 | 60 | -[ATI setBrightness:token:] |
| 0x1E18 | 0x1FFD | 485 | -[ATI setTransferTable:count:] |
| 0x2000 | 0x2065 | 101 | _displayInfoToColorSpace |
| 0x2068 | 0x20B5 | 77 | _colorDepthToColorSpace |
| 0x20B8 | 0x2107 | 79 | _displayInfoToColorDepth |
| 0x2108 | 0x2185 | 125 | _memSizeToBytes |
| 0x2188 | 0x2222 | 154 | +[ATI_BIOS ATIPresent:] |
| 0x2224 | 0x22C6 | 162 | -[ATI_BIOS init] |
| 0x22C8 | 0x2309 | 65 | -[ATI_BIOS initAtSegmentAddress:] |
| 0x230C | 0x234D | 65 | -[ATI_BIOS free] |
| 0x2350 | 0x2383 | 51 | -[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:] |
| 0x2384 | 0x241D | 153 | -[ATI_BIOS setVGAMode:gamma:] |
| 0x2420 | 0x2453 | 51 | -[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:] |
| 0x2454 | 0x2522 | 206 | -[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:] |
| 0x2524 | 0x25EE | 202 | -[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:] |
| 0x25F0 | 0x2602 | 18 | -[ATI_BIOS querySize:size:] |
| 0x2604 | 0x26C2 | 190 | -[ATI_BIOS deviceQuery:bufferSize:buffer:] |
| 0x26C4 | 0x274A | 134 | -[ATI_BIOS setDPMSMode:] |
| 0x274C | 0x27BE | 114 | -[ATI_BIOS getDPMSMode:] |
| 0x27C0 | 0x2846 | 134 | -[ATI_BIOS setAPMState:] |
| 0x2848 | 0x28BA | 114 | -[ATI_BIOS getAPMState:] |
| 0x28BC | 0x2936 | 122 | -[ATI_BIOS getIOBaseAddress:relocatable:] |
| 0x2938 | 0x29D9 | 161 | -[ATI_BIOS getRefreshRate:] |
| 0x29DC | 0x29E8 | 12 | -[ATI_BIOS changeRefreshRate:] |
| 0x29E8 | 0x2A38 | 80 | -[ATI_BIOS initBIOSBuf:function:] |
| 0x2A38 | 0x2BBE | 390 | -[ATI_BIOS setupCodeSegments] |
| 0x2BC0 | 0x2C26 | 102 | -[ATI_BIOS restoreCodeSegments] |
| 0x2C28 | 0x2CFC | 212 | -[ATI_BIOS createDataSegment:size:] |
| 0x2CFC | 0x2D20 | 36 | -[ATI_BIOS restoreDataSegment] |
| 0x2D20 | 0x2D64 | 68 | -[ATI_BIOS doBios:dataSeg:] |
| 0x2D64 | 0x2E62 | 254 | -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:] |
| 0x2E64 | 0x2E70 | 12 | +[ATIRageDisplayDriverKernelServerInstance kernelServerInstance] |
| 0x2E70 | 0x2E7C | 12 | +[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver] |
| 0x2EF4 | 0x2F53 | 95 | _ATIbios16 |
