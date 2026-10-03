# drvATIRage i386 reconstruction findings

Reference SHA-256: `6D08A58A44D5797DA0DD626BBEB705E3621910C99120486F69BD623DE9E61D9A`; bytes: 63548; architecture: i386 little-endian.

## Coverage

IDA found 61 function boundaries covering 11862 bytes. Raw symbols, runtime metadata and instruction/xref analysis add the 117-byte `__bios16` at `0x2e48` and the 203-byte `__ATIbios32` at `0x2f20`. The initial gap total is 202 bytes; `__bios16` occupies 117, and the rest is 85 verified alignment bytes. The combined partition covers all 12267 `__TEXT,__text` bytes.

`__bios16` saves the protected-mode stack, loads the BIOS stack selector, writes the runtime BIOS far-jump operand, far-jumps to the selected BIOS entry, restores ESP/SS on return, and executes `retf`. Its code starts after 2 alignment bytes at `0x2e46`; 3 bytes align the following `_ATIbios16` wrapper. The thunk begins at `0x2f20` and ends at `0x2feb`; its far-call operand is patched at `0x2f7a`/`0x2f7e`. IDA did not create a function boundary for `__bios16`; an explicit function-creation request also returned false because the path leaves by a far jump and resumes at an internal label. The database now has comments at the entry and the runtime-patched operand, and was saved as `ATIRageDisplayDriver_reloc.i64` beside the external reference.

Key IDA disassembly for the supplemental transition:

```text
2e48  mov     ds:dword_6B1C, eax
2e57  mov     eax, ds:_ATI_Bios_Offset
2e5c  mov     dword_2EA6, eax
2e61  mov     ax, ds:_ATI_Bios_Selector
2e67  mov     word_2EAA, ax
2e6d  mov     eax, esp
2e7d  mov     ax, ds:_ATI_Bios_StackOffset
2e86  mov     ax, ds:_ATI_Bios_StackSelector
2e92  push    ax
2e99  sub     eax, offset __bios16
2ea5  jmp     far ptr [runtime-patched offset:selector]
2eac  mov     eax, ds:dword_6B20
2eb1  mov     esp, eax
2eb3  mov     ax, ds:word_6B24
2eb9  mov     ss, ax
2ebc  retf
```

## Runtime and static data

Raw Objective-C metadata yields 50 method entries and type encodings, including category ownership. The ATI instance is 624 bytes (552-byte inherited prefix); ATI_BIOS is 16 bytes with a 36-byte private block. The BIOS register block is 48 bytes with register, selector, output segment and entry-offset positions documented in `reference-contract.json`.
The mode array has 72 records of 136 bytes (9792 bytes total); the CRTC array has 18 records of 30 bytes. Raw record contents, relocations, all 1048 Mach-O relocations, section hashes, imported symbols, and 41 packaged resource hashes are in the contract. The contract also records the 16-byte `gamma16` and `gamma8` arrays, both four-value refresh arrays, the 6-entry mode-to-refresh mapping, and both `IONamedValue` lookup tables.

The i386 ATI class layout is 624 bytes: inherited prefix 552 bytes; three `char *` transfer-table pointers; the recovered scalar/pointer fields; five byte flags; three alignment bytes; and the final `unsigned long` plus three integers. `ATI_BIOS` is 16 bytes. The BIOS register argument is a 48-byte anonymous struct whose seven register members are 4-byte unions, followed by three selector words and two `unsigned long` slots; the BIOS thunk writes the selector into the low word of the `output_ds` slot. The declaration preserves the nested anonymous-union type encoding observed in the runtime metadata.

The generated `ATIRageModes.h` is derived from the contract: each mode’s fields are decoded from its 136 raw bytes and its `parameters` pointer is restored by matching the relocation to one of the 18 CRTC records. The table remains writable because initialization mutates framebuffer pointers, color encodings, flags, and availability bits. The 41 packaged resources were copied from the reference bundle and match each manifest size and SHA-256.

## Initial tool result

IDA 9.4 reference-only analysis: complete=true, diagnostic=null, comparison acceptance=false because no rebuilt artifact was supplied. The saved analysis is `C:\Users\raynorpat\.codex\worktrees\drvatirage-reconstruction\RhapsodiOS\tools\binrecon\out\drvATIRage-i386\published\analysis-reference-ida.json`. The source map currently records the original 61-function partition as unmapped because the checked-in driver is still the preexisting placeholder; generated methods and supplemental code are accounted for separately. The parity ledger starts all 63 entries as `unexamined`.

## Routine ledger

| Address | Bytes | Reference routine | Planned owner | Initial state |
| --- | ---: | --- | --- | --- |
| `0x0000` | 1664 | `-[ATI initFromDeviceDescription:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x0680` | 1632 | `-[ATI fixDeviceDescriptionForPCI:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x0ce0` | 304 | `-[ATI getQueryData]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x0e10` | 144 | `-[ATI parseModeString:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x0ea0` | 540 | `-[ATI updateModeList]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x10bc` | 136 | `-[ATI isModeValid:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1144` | 98 | `-[ATI verifyMemoryMap]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x11a8` | 141 | `-[ATI free]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1238` | 292 | `-[ATI enterLinearMode]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x135c` | 252 | `-[ATI revertToVGAMode]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1458` | 52 | `_waitForFIFO` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x148c` | 73 | `_waitForIdle` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x14d8` | 322 | `_doBlit` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x161c` | 67 | `-[ATI showCursor:frame:token:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1660` | 67 | `-[ATI moveCursor:frame:token:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x16a4` | 57 | `-[ATI hideCursor:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x16e0` | 133 | `_doFill` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x1768` | 566 | `-[ATI initEngine]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x19a0` | 122 | `-[ATI resetEngine]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1a1c` | 12 | `-[ATI displayModeCount]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1a28` | 12 | `-[ATI displayModes]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1a34` | 26 | `-[ATI displayMemorySize]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1a50` | 151 | `-[ATI setPendingDisplayMode:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1ae8` | 208 | `-[ATI setIntValues:forParameter:count:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1bb8` | 33 | `_isATI68880RevC` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x1bdc` | 84 | `_SetGammaValue` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x1c30` | 372 | `-[ATI setGammaTable]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1da4` | 60 | `-[ATI setBrightness:token:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1de0` | 489 | `-[ATI setTransferTable:count:]` | `LKS/ATIRageDisplayDriver.m` | objc: unexamined |
| `0x1fcc` | 101 | `_displayInfoToColorSpace` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x2034` | 77 | `_colorDepthToColorSpace` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x2084` | 79 | `_displayInfoToColorDepth` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x20d4` | 125 | `_memSizeToBytes` | `LKS/ATIRageDisplayDriver.m` | c: unexamined |
| `0x2154` | 12 | `+[ATIRageDisplayDriverKernelServerInstance kernelServerInstance]` | `generated: Kernel Server glue` | generated: unexamined |
| `0x2160` | 12 | `+[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver]` | `generated: Kernel Server glue` | generated: unexamined |
| `0x216c` | 154 | `+[ATI_BIOS ATIPresent:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2208` | 162 | `-[ATI_BIOS init]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x22ac` | 65 | `-[ATI_BIOS initAtSegmentAddress:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x22f0` | 65 | `-[ATI_BIOS free]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2334` | 51 | `-[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2368` | 153 | `-[ATI_BIOS setVGAMode:gamma:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2404` | 51 | `-[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2438` | 206 | `-[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2508` | 202 | `-[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x25d4` | 18 | `-[ATI_BIOS querySize:size:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x25e8` | 190 | `-[ATI_BIOS deviceQuery:bufferSize:buffer:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x26a8` | 134 | `-[ATI_BIOS setDPMSMode:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2730` | 114 | `-[ATI_BIOS getDPMSMode:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x27a4` | 134 | `-[ATI_BIOS setAPMState:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x282c` | 114 | `-[ATI_BIOS getAPMState:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x28a0` | 122 | `-[ATI_BIOS getIOBaseAddress:relocatable:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x291c` | 161 | `-[ATI_BIOS getRefreshRate:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x29c0` | 12 | `-[ATI_BIOS changeRefreshRate:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x29cc` | 80 | `-[ATI_BIOS initBIOSBuf:function:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2a1c` | 388 | `-[ATI_BIOS setupCodeSegments]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2ba0` | 102 | `-[ATI_BIOS restoreCodeSegments]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2c08` | 212 | `-[ATI_BIOS createDataSegment:size:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2cdc` | 36 | `-[ATI_BIOS restoreDataSegment]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2d00` | 68 | `-[ATI_BIOS doBios:dataSeg:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2d44` | 258 | `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | `LKS/ATI_BIOS.m` | objc: unexamined |
| `0x2e48` | 117 | `__bios16` | `LKS/ATI_BIOS16.s` | transition: unexamined |
| `0x2ec0` | 95 | `_ATIbios16` | `LKS/ATIbios16.c` | c: unexamined |
| `0x2f20` | 203 | `__ATIbios32` | `LKS/ATIbios.s` | thunk: unexamined |

## Padding ranges

| Address | Bytes | Raw-byte classification |
| --- | ---: | --- |
| `0x11a6` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x1235` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x14d5` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x161a` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x165f` | 1 | IDA alignment; zero/NOP bytes (`9E076CEAF246…`) |
| `0x16a3` | 1 | IDA alignment; zero/NOP bytes (`9E076CEAF246…`) |
| `0x16dd` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x1765` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x199e` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x1a1a` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x1a4e` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x1ae7` | 1 | IDA alignment; zero/NOP bytes (`9E076CEAF246…`) |
| `0x1bd9` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x1fc9` | 3 | IDA alignment; zero/NOP bytes (`709E80C88487…`) |
| `0x2031` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x2081` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x20d3` | 1 | IDA alignment; zero/NOP bytes (`9E076CEAF246…`) |
| `0x2151` | 3 | IDA alignment; zero/NOP bytes (`709E80C88487…`) |
| `0x2206` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x22aa` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x22ed` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x2331` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x2367` | 1 | IDA alignment; zero/NOP bytes (`9E076CEAF246…`) |
| `0x2401` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x2437` | 1 | IDA alignment; zero/NOP bytes (`9E076CEAF246…`) |
| `0x2506` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x25d2` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x25e6` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x26a6` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x272e` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x27a2` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x282a` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x289e` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x291a` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x29bd` | 3 | IDA alignment; zero/NOP bytes (`E65CA7C06AE3…`) |
| `0x2c06` | 2 | IDA alignment; zero/NOP bytes (`182003D5C37D…`) |
| `0x2e46` | 2 | IDA alignment; zero/NOP bytes (`96A296D224F2…`) |
| `0x2ebd` | 3 | IDA alignment; zero/NOP bytes (`709E80C88487…`) |
| `0x2f1f` | 1 | IDA alignment; zero/NOP bytes (`6E340B9CFFB3…`) |

No ATI code has been reconstructed yet. Routine states will advance only when source, ABI and instruction evidence has been reviewed. Hardware and rebuilt-binary results are pending.
