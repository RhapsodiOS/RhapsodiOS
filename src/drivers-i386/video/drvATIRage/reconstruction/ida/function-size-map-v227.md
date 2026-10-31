# Rebuilt drvATIRage i386 function map — v227

| Start | End | Bytes | Function |
|---:|---:|---:|---|
| 0x0 | 0x6e4 | 1764 | -[ATI initFromDeviceDescription:] |
| 0x6e4 | 0xd13 | 1583 | -[ATI fixDeviceDescriptionForPCI:] |
| 0xd14 | 0xe44 | 304 | -[ATI getQueryData] |
| 0xe44 | 0xed4 | 144 | -[ATI parseModeString:] |
| 0xed4 | 0x10f0 | 540 | -[ATI updateModeList] |
| 0x10f0 | 0x1178 | 136 | -[ATI isModeValid:] |
| 0x1178 | 0x11da | 98 | -[ATI verifyMemoryMap] |
| 0x11dc | 0x1269 | 141 | -[ATI free] |
| 0x126c | 0x1390 | 292 | -[ATI enterLinearMode] |
| 0x1390 | 0x148c | 252 | -[ATI revertToVGAMode] |
| 0x148c | 0x14c0 | 52 | _waitForFIFO |
| 0x14c0 | 0x1509 | 73 | _waitForIdle |
| 0x150c | 0x1654 | 328 | _doBlit |
| 0x1654 | 0x1697 | 67 | -[ATI showCursor:frame:token:] |
| 0x1698 | 0x16db | 67 | -[ATI moveCursor:frame:token:] |
| 0x16dc | 0x1715 | 57 | -[ATI hideCursor:] |
| 0x1718 | 0x179d | 133 | _doFill |
| 0x17a0 | 0x19d6 | 566 | -[ATI initEngine] |
| 0x19d8 | 0x1a52 | 122 | -[ATI resetEngine] |
| 0x1a54 | 0x1a60 | 12 | -[ATI displayModeCount] |
| 0x1a60 | 0x1a6c | 12 | -[ATI displayModes] |
| 0x1a6c | 0x1a86 | 26 | -[ATI displayMemorySize] |
| 0x1a88 | 0x1b1f | 151 | -[ATI setPendingDisplayMode:] |
| 0x1b20 | 0x1bf0 | 208 | -[ATI setIntValues:forParameter:count:] |
| 0x1bf0 | 0x1c11 | 33 | _isATI68880RevC |
| 0x1c14 | 0x1c68 | 84 | _SetGammaValue |
| 0x1c68 | 0x1ddc | 372 | -[ATI setGammaTable] |
| 0x1ddc | 0x1e18 | 60 | -[ATI setBrightness:token:] |
| 0x1e18 | 0x2001 | 489 | -[ATI setTransferTable:count:] |
| 0x2004 | 0x2069 | 101 | _displayInfoToColorSpace |
| 0x206c | 0x20b9 | 77 | _colorDepthToColorSpace |
| 0x20bc | 0x210b | 79 | _displayInfoToColorDepth |
| 0x210c | 0x2189 | 125 | _memSizeToBytes |
| 0x218c | 0x2226 | 154 | +[ATI_BIOS ATIPresent:] |
| 0x2228 | 0x22ca | 162 | -[ATI_BIOS init] |
| 0x22cc | 0x230d | 65 | -[ATI_BIOS initAtSegmentAddress:] |
| 0x2310 | 0x2351 | 65 | -[ATI_BIOS free] |
| 0x2354 | 0x2387 | 51 | -[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:] |
| 0x2388 | 0x2421 | 153 | -[ATI_BIOS setVGAMode:gamma:] |
| 0x2424 | 0x2457 | 51 | -[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:] |
| 0x2458 | 0x2526 | 206 | -[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:] |
| 0x2528 | 0x25f2 | 202 | -[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:] |
| 0x25f4 | 0x2606 | 18 | -[ATI_BIOS querySize:size:] |
| 0x2608 | 0x26c6 | 190 | -[ATI_BIOS deviceQuery:bufferSize:buffer:] |
| 0x26c8 | 0x274e | 134 | -[ATI_BIOS setDPMSMode:] |
| 0x2750 | 0x27c2 | 114 | -[ATI_BIOS getDPMSMode:] |
| 0x27c4 | 0x284a | 134 | -[ATI_BIOS setAPMState:] |
| 0x284c | 0x28be | 114 | -[ATI_BIOS getAPMState:] |
| 0x28c0 | 0x293a | 122 | -[ATI_BIOS getIOBaseAddress:relocatable:] |
| 0x293c | 0x29dd | 161 | -[ATI_BIOS getRefreshRate:] |
| 0x29e0 | 0x29ec | 12 | -[ATI_BIOS changeRefreshRate:] |
| 0x29ec | 0x2a3c | 80 | -[ATI_BIOS initBIOSBuf:function:] |
| 0x2a3c | 0x2bc2 | 390 | -[ATI_BIOS setupCodeSegments] |
| 0x2bc4 | 0x2c2a | 102 | -[ATI_BIOS restoreCodeSegments] |
| 0x2c2c | 0x2d00 | 212 | -[ATI_BIOS createDataSegment:size:] |
| 0x2d00 | 0x2d24 | 36 | -[ATI_BIOS restoreDataSegment] |
| 0x2d24 | 0x2d68 | 68 | -[ATI_BIOS doBios:dataSeg:] |
| 0x2d68 | 0x2e66 | 254 | -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:] |
| 0x2e68 | 0x2e74 | 12 | +[ATIRageDisplayDriverKernelServerInstance kernelServerInstance] |
| 0x2e74 | 0x2e80 | 12 | +[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver] |
| 0x2ef8 | 0x2f57 | 95 | _ATIbios16 |
