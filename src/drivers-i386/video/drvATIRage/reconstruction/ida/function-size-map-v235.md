# v235 IDA function range and size map

Reference and rebuilt function ranges from the v235 Binrecon IDA 9.4 analysis. Status comes from the paired-function comparison; sizes are end minus start.

| Status | Function | Reference range | Bytes | Candidate range | Bytes | Delta |
|---|---|---:|---:|---:|---:|---:|
| different | `-[ATI initFromDeviceDescription:]` | 0x0000–0x0680 | 1664 | 0x0000–0x06E4 | 1764 | 100 |
| different | `-[ATI fixDeviceDescriptionForPCI:]` | 0x0680–0x0CE0 | 1632 | 0x06E4–0x0D13 | 1583 | -49 |
| assembly-matched | `-[ATI getQueryData]` | 0x0CE0–0x0E10 | 304 | 0x0D14–0x0E44 | 304 | 0 |
| assembly-matched | `-[ATI parseModeString:]` | 0x0E10–0x0EA0 | 144 | 0x0E44–0x0ED4 | 144 | 0 |
| assembly-matched | `-[ATI updateModeList]` | 0x0EA0–0x10BC | 540 | 0x0ED4–0x10F0 | 540 | 0 |
| assembly-matched | `-[ATI isModeValid:]` | 0x10BC–0x1144 | 136 | 0x10F0–0x1178 | 136 | 0 |
| assembly-matched | `-[ATI verifyMemoryMap]` | 0x1144–0x11A6 | 98 | 0x1178–0x11DA | 98 | 0 |
| assembly-matched | `-[ATI free]` | 0x11A8–0x1235 | 141 | 0x11DC–0x1269 | 141 | 0 |
| assembly-matched | `-[ATI enterLinearMode]` | 0x1238–0x135C | 292 | 0x126C–0x1390 | 292 | 0 |
| assembly-matched | `-[ATI revertToVGAMode]` | 0x135C–0x1458 | 252 | 0x1390–0x148C | 252 | 0 |
| assembly-matched | `_waitForFIFO` | 0x1458–0x148C | 52 | 0x148C–0x14C0 | 52 | 0 |
| assembly-matched | `_waitForIdle` | 0x148C–0x14D5 | 73 | 0x14C0–0x1509 | 73 | 0 |
| different | `_doBlit` | 0x14D8–0x161A | 322 | 0x150C–0x1654 | 328 | 6 |
| assembly-matched | `-[ATI showCursor:frame:token:]` | 0x161C–0x165F | 67 | 0x1654–0x1697 | 67 | 0 |
| assembly-matched | `-[ATI moveCursor:frame:token:]` | 0x1660–0x16A3 | 67 | 0x1698–0x16DB | 67 | 0 |
| assembly-matched | `-[ATI hideCursor:]` | 0x16A4–0x16DD | 57 | 0x16DC–0x1715 | 57 | 0 |
| assembly-matched | `_doFill` | 0x16E0–0x1765 | 133 | 0x1718–0x179D | 133 | 0 |
| assembly-matched | `-[ATI initEngine]` | 0x1768–0x199E | 566 | 0x17A0–0x19D6 | 566 | 0 |
| assembly-matched | `-[ATI resetEngine]` | 0x19A0–0x1A1A | 122 | 0x19D8–0x1A52 | 122 | 0 |
| assembly-matched | `-[ATI displayModeCount]` | 0x1A1C–0x1A28 | 12 | 0x1A54–0x1A60 | 12 | 0 |
| assembly-matched | `-[ATI displayModes]` | 0x1A28–0x1A34 | 12 | 0x1A60–0x1A6C | 12 | 0 |
| assembly-matched | `-[ATI displayMemorySize]` | 0x1A34–0x1A4E | 26 | 0x1A6C–0x1A86 | 26 | 0 |
| assembly-matched | `-[ATI setPendingDisplayMode:]` | 0x1A50–0x1AE7 | 151 | 0x1A88–0x1B1F | 151 | 0 |
| assembly-matched | `-[ATI setIntValues:forParameter:count:]` | 0x1AE8–0x1BB8 | 208 | 0x1B20–0x1BF0 | 208 | 0 |
| assembly-matched | `_isATI68880RevC` | 0x1BB8–0x1BD9 | 33 | 0x1BF0–0x1C11 | 33 | 0 |
| assembly-matched | `_SetGammaValue` | 0x1BDC–0x1C30 | 84 | 0x1C14–0x1C68 | 84 | 0 |
| assembly-matched | `-[ATI setGammaTable]` | 0x1C30–0x1DA4 | 372 | 0x1C68–0x1DDC | 372 | 0 |
| assembly-matched | `-[ATI setBrightness:token:]` | 0x1DA4–0x1DE0 | 60 | 0x1DDC–0x1E18 | 60 | 0 |
| different | `-[ATI setTransferTable:count:]` | 0x1DE0–0x1FC9 | 489 | 0x1E18–0x1FFD | 485 | -4 |
| assembly-matched | `_displayInfoToColorSpace` | 0x1FCC–0x2031 | 101 | 0x2000–0x2065 | 101 | 0 |
| assembly-matched | `_colorDepthToColorSpace` | 0x2034–0x2081 | 77 | 0x2068–0x20B5 | 77 | 0 |
| assembly-matched | `_displayInfoToColorDepth` | 0x2084–0x20D3 | 79 | 0x20B8–0x2107 | 79 | 0 |
| assembly-matched | `_memSizeToBytes` | 0x20D4–0x2151 | 125 | 0x2108–0x2185 | 125 | 0 |
| assembly-matched | `+[ATIRageDisplayDriverKernelServerInstance kernelServerInstance]` | 0x2154–0x2160 | 12 | 0x2E64–0x2E70 | 12 | 0 |
| assembly-matched | `+[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver]` | 0x2160–0x216C | 12 | 0x2E70–0x2E7C | 12 | 0 |
| assembly-matched | `+[ATI_BIOS ATIPresent:]` | 0x216C–0x2206 | 154 | 0x2188–0x2222 | 154 | 0 |
| assembly-matched | `-[ATI_BIOS init]` | 0x2208–0x22AA | 162 | 0x2224–0x22C6 | 162 | 0 |
| assembly-matched | `-[ATI_BIOS initAtSegmentAddress:]` | 0x22AC–0x22ED | 65 | 0x22C8–0x2309 | 65 | 0 |
| assembly-matched | `-[ATI_BIOS free]` | 0x22F0–0x2331 | 65 | 0x230C–0x234D | 65 | 0 |
| assembly-matched | `-[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:]` | 0x2334–0x2367 | 51 | 0x2350–0x2383 | 51 | 0 |
| assembly-matched | `-[ATI_BIOS setVGAMode:gamma:]` | 0x2368–0x2401 | 153 | 0x2384–0x241D | 153 | 0 |
| assembly-matched | `-[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:]` | 0x2404–0x2437 | 51 | 0x2420–0x2453 | 51 | 0 |
| assembly-matched | `-[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]` | 0x2438–0x2506 | 206 | 0x2454–0x2522 | 206 | 0 |
| assembly-matched | `-[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:]` | 0x2508–0x25D2 | 202 | 0x2524–0x25EE | 202 | 0 |
| assembly-matched | `-[ATI_BIOS querySize:size:]` | 0x25D4–0x25E6 | 18 | 0x25F0–0x2602 | 18 | 0 |
| assembly-matched | `-[ATI_BIOS deviceQuery:bufferSize:buffer:]` | 0x25E8–0x26A6 | 190 | 0x2604–0x26C2 | 190 | 0 |
| assembly-matched | `-[ATI_BIOS setDPMSMode:]` | 0x26A8–0x272E | 134 | 0x26C4–0x274A | 134 | 0 |
| assembly-matched | `-[ATI_BIOS getDPMSMode:]` | 0x2730–0x27A2 | 114 | 0x274C–0x27BE | 114 | 0 |
| assembly-matched | `-[ATI_BIOS setAPMState:]` | 0x27A4–0x282A | 134 | 0x27C0–0x2846 | 134 | 0 |
| assembly-matched | `-[ATI_BIOS getAPMState:]` | 0x282C–0x289E | 114 | 0x2848–0x28BA | 114 | 0 |
| assembly-matched | `-[ATI_BIOS getIOBaseAddress:relocatable:]` | 0x28A0–0x291A | 122 | 0x28BC–0x2936 | 122 | 0 |
| assembly-matched | `-[ATI_BIOS getRefreshRate:]` | 0x291C–0x29BD | 161 | 0x2938–0x29D9 | 161 | 0 |
| assembly-matched | `-[ATI_BIOS changeRefreshRate:]` | 0x29C0–0x29CC | 12 | 0x29DC–0x29E8 | 12 | 0 |
| assembly-matched | `-[ATI_BIOS initBIOSBuf:function:]` | 0x29CC–0x2A1C | 80 | 0x29E8–0x2A38 | 80 | 0 |
| different | `-[ATI_BIOS setupCodeSegments]` | 0x2A1C–0x2BA0 | 388 | 0x2A38–0x2BBE | 390 | 2 |
| assembly-matched | `-[ATI_BIOS restoreCodeSegments]` | 0x2BA0–0x2C06 | 102 | 0x2BC0–0x2C26 | 102 | 0 |
| assembly-matched | `-[ATI_BIOS createDataSegment:size:]` | 0x2C08–0x2CDC | 212 | 0x2C28–0x2CFC | 212 | 0 |
| assembly-matched | `-[ATI_BIOS restoreDataSegment]` | 0x2CDC–0x2D00 | 36 | 0x2CFC–0x2D20 | 36 | 0 |
| assembly-matched | `-[ATI_BIOS doBios:dataSeg:]` | 0x2D00–0x2D44 | 68 | 0x2D20–0x2D64 | 68 | 0 |
| different | `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | 0x2D44–0x2E46 | 258 | 0x2D64–0x2E62 | 254 | -4 |
| assembly-matched | `_ATIbios16` | 0x2EC0–0x2F1F | 95 | 0x2EF4–0x2F53 | 95 | 0 |
