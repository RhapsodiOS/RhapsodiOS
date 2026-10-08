# drvATIMach64 routine worklist

Reference SHA-256: `AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C`
IDA: IDA 9.4
Coverage: 54 entries = 52 handwritten + 2 generated methods.

Latest inspected rebuild: `tools/binrecon/out/atimach64/fresh-rebuild-v39-gamma-order-2026-10-05/ATIMach64DisplayDriver_reloc` (64,196 bytes; SHA-256 `DAC5542C5DC9880FA11CAA84F334BAA945D74E97EBE794B02DEDD268C175A16C`). The v39 package is 24,128 bytes (SHA-256 `654A18F917869F846D4AFA634D24E239F2D39020D6F06B611D9A0968382DC084`) and embeds the identical relocatable.
Latest corrected comparison: `tools/binrecon/out/atimach64/fresh-reference-aliases-v39-2026-10-05/comparison-v39.json`, against the refreshed actual reference export. IDA pairs all 54 routines: 35 assembly-matched and 19 control-flow-confirmed. `normalized-functions` remains false (code=90, relocation=182, symbol-string-order=0, layout=25, padding=2,227, metadata=2,397). The v39 final evidence verifier passes. The v39 Hex-Rays pair is checked in at `reconstruction/evidence/ida-v39-actual-rebuilt.c`; the ledger is rebound to v39.
The v39 disassembly retains the reviewed `SetGammaValue`, `shortQuery`, and `loadCRTC_comm` behavior fixes. All seven native fixture targets passed against the exact v39 source, and the reconstruction suite passes 67 tests. The BinRecon suite passes 996 tests with 4 skipped. Compatible ATI hardware/ROM validation has not been performed. The complete v39 build log is retained under its fresh rebuild output directory.

| Address | Size | Kind | Reference name | Review status |
| ---: | ---: | --- | --- | --- |
| `0x0000` | 2719 | handwritten | `-[ATI initFromDeviceDescription:]` | IDA/source behavior reviewed; the 15-vs-18 direct `_IOLog` instruction count is explained by three reference error paths tail-jumping to shared call `0x0a7a`; control flow confirmed; BinRecon call-site count differs due to tail merging; cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x0aa0` | 141 | handwritten | `-[ATI free]` | assembly matched |
| `0x0b30` | 277 | handwritten | `-[ATI enterLinearMode]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x0c48` | 138 | handwritten | `-[ATI revertToVGAMode]` | assembly matched |
| `0x0cd4` | 12 | handwritten | `-[ATI displayModeCount]` | assembly matched |
| `0x0ce0` | 12 | handwritten | `-[ATI displayModes]` | assembly matched |
| `0x0cec` | 26 | handwritten | `-[ATI displayMemorySize]` | assembly matched |
| `0x0d08` | 123 | handwritten | `-[ATI setPendingDisplayMode:]` | assembly matched |
| `0x0d84` | 304 | handwritten | `-[ATI getQueryData]` | assembly matched |
| `0x0eb4` | 152 | handwritten | `-[ATI parseModeString:]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x0f4c` | 412 | handwritten | `-[ATI updateModeList]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive |
| `0x10e8` | 136 | handwritten | `-[ATI isModeValid:]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x1170` | 98 | handwritten | `-[ATI verifyMemoryMap]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive |
| `0x11d4` | 350 | handwritten | `-[ATI changeHardwareMapping:]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x1334` | 346 | handwritten | `-[ATI changeTableMapping:]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x1490` | 45 | handwritten | `_isATI68880RevC` | assembly matched |
| `0x14c0` | 82 | handwritten | `_SetGammaValue` | v39 disassembly and Hex-Rays confirm (channel * brightness) >> 6, ordered red/green/blue writes, delay increments and scaled-blue return; red lowering matches but green/blue register allocation and delay-counter relocation differ; control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x1514` | 308 | handwritten | `-[ATI setGammaTable]` | behavior reviewed against v36 IDA and source (DAC setup, default/transfer loops and `outb` delay side effects agree); control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x1648` | 60 | handwritten | `-[ATI setBrightness:token:]` | assembly matched |
| `0x1684` | 489 | handwritten | `-[ATI setTransferTable:count:]` | behavior reviewed against v36 IDA/source and display enum values (shift, allocation, channel extraction, cleanup agree); control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x1870` | 101 | handwritten | `_displayInfoToColorSpace` | assembly matched |
| `0x18d8` | 77 | handwritten | `_colorDepthToColorSpace` | assembly matched |
| `0x1928` | 79 | handwritten | `_displayInfoToColorDepth` | assembly matched |
| `0x1978` | 113 | handwritten | `_memSizeToBytes` | assembly matched |
| `0x19ec` | 12 | generated | `+[ATIMach64DisplayDriverKernelServerInstance kernelServerInstance]` | assembly matched |
| `0x19f8` | 12 | generated | `+[ATIMach64DisplayDriverVersion driverKitVersionForATIMach64DisplayDriver]` | assembly matched |
| `0x1a04` | 154 | handwritten | `+[ATI_BIOS ATIPresent:]` | assembly matched |
| `0x1aa0` | 162 | handwritten | `-[ATI_BIOS init]` | assembly matched |
| `0x1b44` | 65 | handwritten | `-[ATI_BIOS initAtSegmentAddress:]` | assembly matched |
| `0x1b88` | 65 | handwritten | `-[ATI_BIOS free]` | assembly matched |
| `0x1bcc` | 51 | handwritten | `-[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:]` | assembly matched |
| `0x1c00` | 153 | handwritten | `-[ATI_BIOS setVGAMode:gamma:]` | assembly matched |
| `0x1c9c` | 51 | handwritten | `-[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:]` | assembly matched |
| `0x1cd0` | 206 | handwritten | `-[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive; v34 disassembly confirms byte-width AL store |
| `0x1da0` | 202 | handwritten | `-[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:]` | v37 corrected disassembly reads a 16-bit EBX stack temporary and writes its zero-extended value to the 32-bit output; high-bit fixture expects `0x5000` from EBX `0xabcd5000`; control flow confirmed; compiler temp lowering still differs |
| `0x1e6c` | 18 | handwritten | `-[ATI_BIOS querySize:size:]` | assembly matched |
| `0x1e80` | 190 | handwritten | `-[ATI_BIOS deviceQuery:bufferSize:buffer:]` | control flow confirmed; v36 BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive; fresh IDA body matches source/reference field widths and status/log paths |
| `0x1f40` | 134 | handwritten | `-[ATI_BIOS setDPMSMode:]` | assembly matched |
| `0x1fc8` | 114 | handwritten | `-[ATI_BIOS getDPMSMode:]` | assembly matched |
| `0x203c` | 134 | handwritten | `-[ATI_BIOS setAPMState:]` | assembly matched |
| `0x20c4` | 114 | handwritten | `-[ATI_BIOS getAPMState:]` | assembly matched |
| `0x2138` | 122 | handwritten | `-[ATI_BIOS getIOBaseAddress:relocatable:]` | assembly matched |
| `0x21b4` | 161 | handwritten | `-[ATI_BIOS getRefreshRate:]` | assembly matched |
| `0x2258` | 12 | handwritten | `-[ATI_BIOS changeRefreshRate:]` | assembly matched |
| `0x2264` | 80 | handwritten | `-[ATI_BIOS initBIOSBuf:function:]` | behavior reviewed against v36 IDA and source (register-frame fields/return agree); control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x22b4` | 388 | handwritten | `-[ATI_BIOS setupCodeSegments]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x2438` | 102 | handwritten | `-[ATI_BIOS restoreCodeSegments]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x24a0` | 212 | handwritten | `-[ATI_BIOS createDataSegment:size:]` | control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x2574` | 36 | handwritten | `-[ATI_BIOS restoreDataSegment]` | assembly matched |
| `0x2598` | 68 | handwritten | `-[ATI_BIOS doBios:dataSeg:]` | assembly matched |
| `0x25dc` | 258 | handwritten | `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | IDA review found and source corrected ECX mode/resolution byte packing; high-bit fixture added; v36 binary predates fix; control flow confirmed; BinRecon: cfg differs, function range bytes differ, instruction alignment inconclusive, instruction shape differs |
| `0x26e0` | 117 | handwritten | `__bios16` | assembly matched |
| `0x2758` | 95 | handwritten | `_ATIbios16` | assembly matched |
| `0x27b8` | 203 | handwritten | `__ATIbios32` | assembly matched |

The v39 build and corrected IDA export complete with 54 paired routines. Final evidence verification passes, all seven fixture targets pass on the exact v39 source, all 67 reconstruction Python tests pass, and all 996 BinRecon tests pass (4 skipped). Normalized parity remains false (35 assembly matches, 19 control-flow-confirmed). This is the current rebuilt identity used by the ledger; compatibility hardware/ROM validation remains unperformed.
