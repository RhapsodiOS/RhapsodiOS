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

## Initial tool result (historical snapshot)

IDA 9.4 reference-only analysis: complete=true, diagnostic=null, comparison acceptance=false because no rebuilt artifact was supplied. The saved analysis is `C:\Users\raynorpat\.codex\worktrees\drvatirage-reconstruction\RhapsodiOS\tools\binrecon\out\drvATIRage-i386\published\analysis-reference-ida.json`. At this initial stage, the driver source was a placeholder and the 61-function partition had not yet been mapped. This is historical state; current source mapping and review status are summarized below.

## Initial routine inventory

The states in this table are the first-pass values and have since been superseded. For current function-level review states, use `reconstruction/ATIRageDisplayDriver_reloc/ledger.json`.

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

## Initial reconstruction checkpoint (historical)

At this checkpoint no ATI code had been reconstructed. Subsequent source, ABI and instruction reviews are reflected in the current status below; rebuilt-binary parity and ATI hardware/runtime validation remain open.


## Current verified reconstruction status (2026-10-05)

The latest accepted native candidate is v235, _reloc size 220,244 bytes, SHA-256 57C016AA253B8DCF069DB4FC0C887B3C1AC601E0475661159FCDEC3FCE1BB4E2. Its Binrecon run at tools/binrecon/out/v235-transfer-gray-load-order/run-summary.json completes but fails normalized-functions; the comparison reports 30 code findings across six functions: initFromDeviceDescription: (1664 reference / 1764 candidate bytes), fixDeviceDescriptionForPCI: (1632/1583), _doBlit (322/328), setTransferTable:count: (489/485), setupCodeSegments (388/390), and loadCRTC_comm (258/254). vm.conf remains at Port 2121.

The current source map associates 59 of the 61 analyzed functions with reconstructed source; the two generated kernel-server/version class methods are separately marked assembly-matched in the ledger. I refreshed all 59 source-line anchors against the current source files (58 changed; `_ATIbios16` remained at line 7). The 63-entry ledger records 58 control-flow-confirmed routines and five assembly-matched routines, based on prior v149 review artifacts. The v235/v236 comparison notes below supplement those reviews for the six currently mismatching methods.

A later v236 artifact is present at `tools/binrecon/out/v236-transfer-gray-blue-preload/ATIRageDisplayDriver_reloc` (220,256 bytes; SHA-256 `29D237CBFE2EF8F4DB0FE87D19EEB4C46DD40F2A91D55A623E24549B8FB860E0`). Its completed Binrecon run still fails `normalized-functions` with the same 30 findings in the same six methods and the same per-method sizes. In `setTransferTable:count:`, v236 has 150 normalized instructions versus 149 in the reference and v235 has 148; an independent LCS gives 124 common instruction/operand pairs for both candidates. v236 preloads the blue destination pointer before the grayscale loop, while the reference loads it inside each iteration before reading the source byte. This does not improve the local LCS, so v236 remains an unaccepted comparison artifact; v235 remains the accepted baseline.

The earlier v237 snapshot (main-source SHA-256 71D9765C1501563E6A5008CA53E75CD11FDE4284D3CD62C48185B713ED590389) reloaded blueTransferTable before reading and shifting the grayscale source value. The current working source includes further unbuilt source-shape trials described below (main SHA-256 9413BF427D6D31F4C7D33EA524A01FE5926A793F73C537122C146006E580EE6F; ATI_BIOS.m SHA-256 0FDEFB23D5A1DADB7A5B08ECF234DE23AE46751F57E2BBF755A2A4E603B2ADD5). Automatic review blocked syncing the trials to the native guest. v235 remains the latest accepted binary; none of the current working source changes has a fresh native build or Binrecon result.

The current source trial combines the initializer's typed structure assignment, a direct `_doBlit` control-register expression, fixed EAX/EDX byte registers in `loadCRTC_comm`, and a compiler memory barrier after reloading the grayscale blue-transfer pointer. Main-source SHA-256 is 9413BF427D6D31F4C7D33EA524A01FE5926A793F73C537122C146006E580EE6F; ATI_BIOS.m SHA-256 is 0FDEFB23D5A1DADB7A5B08ECF234DE23AE46751F57E2BBF755A2A4E603B2ADD5. IDA confirms v235 still calls `_bcopy` in `initFromDeviceDescription:` while the reference uses `cld; rep movsd`. In `_doBlit`, the reference frame reserves 0x1c bytes and combines the control flags in EAX; v235 reserves 0x20 bytes and spills a `blitControl` local. In `loadCRTC_comm`, the reference holds the gamma byte in AL, transfers it to DL, and stores resolution from CL; v235 computes the flag directly in DL and moves resolution through EAX/AL. In the grayscale loop, v235 loads/shifts the table byte before fetching `blueTransferTable`; the reference loads the blue pointer into EDX first. The source trial now puts a memory clobber barrier after the pointer assignment to constrain compiler scheduling. These are unbuilt source trials: no native artifact or Binrecon result exists for them. The prior automatic review blocked native guest synchronization, so the user-approved execution request cannot proceed through that route absent an allowed execution path. v235 remains the latest accepted binary.

Both v235 IDBs are saved and Hex-Rays decompiles all 61 functions on each side without failures. Candidate and reference typed exports are ida/rebuilt-pseudocode-v235-typed.md (SHA-256 C380E19453A7EEB4407BE5A2C21CC07F411D7299EFE93EE6C62C76A7E1236BBD) and ida/reference-pseudocode-v235-typed.md (SHA-256 36DC4C671A6221D963135544F6E8222C6A03F6072BC6F3A44F61118881A68FDA). Recovered annotations include the 624-byte ATI class layout on all 23 candidate ATI methods, the 16-byte ATI_BIOS instance and 36-byte private block, the 48-byte BIOS registers, the 8-byte IORange (`start`, `size`), the 30-byte CRTC record, the 8-byte segment descriptor, and the 72-entry, 136-byte IODisplayInfo table. `initFromDeviceDescription:` and `fixDeviceDescriptionForPCI:` now take `IOPCIDeviceDescription *` in the source header and both saved candidate and reference IDBs; their pseudocode resolves PCI selectors against that class. The initializer's `configTable` local is `IOConfigTable *`; the candidate v235 export retains its built `valueForString:` selector, while the current source now uses the framework-declared `valueForStringKey:` selector. Both exports resolve `freeString:` calls. The PCI fix method also names `barRegisters[18]`, `portRanges[9]`, and `memoryRanges[8]`. `setupCodeSegments` now uses `ATI_SegmentDescriptor *` locals in both databases to expose GDT field accesses. Direct IDA disassembly shows the reference encodes BIOS descriptor base 0xC0002E48, while v235 encodes 0xC0002E7C; the source derives the address from its own `_bios16` symbol, so do not replace it with the reference image's constant. `displayModes` returns IODisplayInfo_Recovered *; cursor overrides use Point *. The generated `kernelServerInstance` class method returns `void **` in both IDBs, matching the two pointer levels in runtime encoding `^^{?}`  while leaving its pointee opaque. BIOS `loadCRTC_comm` locals now distinguish the reference gamma flag in AL from the candidate mode flags in DL; both decompilations type the BIOS result as `int` and name the register block and restore flag.

Reassessment of v150: that structure-assignment build came from the older v149 baseline, where global Binrecon code findings were already 39; v150 increased them to 69 and was reverted. Its IDA disassembly does emit the reference cld; mov ecx, 0x22; rep movsd copy sequence. An independent LCS over normalized mnemonic/operand pairs gives v150 321 common instructions against 504 reference instructions (518 candidate total), versus v235 237 common against the same 504 reference instructions (520 candidate total). Both have initializer call-set, CFG, range, and instruction-shape differences. The older global regression therefore does not settle whether an isolated copy-form trial based on v235 will help. Any such source change still needs a fresh native build and full Binrecon comparison.

The detailed chronological trial log and plan remain in docs/superpowers/plans/2026-10-02-drvatirage-reconstruction.md. Strict Binrecon parity and ATI hardware/runtime validation remain open.

### PCI call-sequence audit (2026-10-05)

For the accepted v235 pair, IDA reports 26 calls in `fixDeviceDescriptionForPCI:` on both sides. Their ordered targets match exactly: 24 `_objc_msgSend` calls, one `_strtol`, and one `_IOLog`; all 24 Objective-C selector loads also match in order (`class`, the BAR config get/set sequence, memory/port range queries and setters, config-table lookup, string conversion, and name lookup). The reference and candidate call-site offsets move as surrounding instructions and control-flow layout differ. Binrecon's `_canonical_calls` includes each call's function-relative source offset, so it reports `calls_equal=false` when those locations shift even though this function's ordered call-target/selector sequence is unchanged. Treat that flag as call-site-layout evidence here, not as a missing or reordered call. The separate instruction-range and CFG mismatches remain real binary differences; this audit does not establish strict parity or prove full semantic equivalence.

The initializer has a related but distinct signal. Reference v235 analysis records nine `_IOLog` call sites and seven `free` selector loads; candidate analysis records eight `_IOLog` sites, eight `free` loads, and one `_bcopy` call. The source factors several diagnostics through a shared `initFailure` label, while v235 retains a `_bcopy` for the final 136-byte display-info copy. The typed pseudocode shows the same failure cases and success-state initialization, but call-site factoring and the copy implementation differ at machine level. The current source now uses structure assignment for that copy; it has not been rebuilt, so it must not be conflated with the v235 binary's `_bcopy` evidence.

### v235 mismatching-function call-target audit (2026-10-05)

Rechecked the six `normalized-functions` failures against the published v235 IDA instruction records (`comparison-ida.json` SHA-256 `114479882064565252C2676E974A801AAFC13881F0112AEE8C88F6F2DD5BF3CE`). Five functions have the same ordered call-target names in reference and candidate, with call-site offsets shifted: `fixDeviceDescriptionForPCI:` (26 calls), `_doBlit` (3), `setTransferTable:count:` (7), `setupCodeSegments` (2), and `loadCRTC_comm` (4). For `setTransferTable:count:` and `loadCRTC_comm`, the Objective-C selector loads also match in order. In those five functions, Binrecon's `calls differ` reason reflects offsets; instruction and CFG mismatches remain.

`initFromDeviceDescription:` has 54 calls in each binary. Comparing target frequencies shows the only target-set difference is one reference `_IOLog` absent from v235 and one candidate-only `_bcopy`; all other target counts match, including 31 `_objc_msgSend` and 8 `_objc_msgSendSuper` calls. The missing reference call logs `No Display Mode found; aborting` (reference function offset `0x475`); the current source contains that log at `ATIRageDisplayDriver.m:179`. The reference copies the 136-byte `IODisplayInfo` record with `rep movsd`, while v235 calls `_bcopy`; the current source uses structure assignment for that copy. Both source changes postdate v235 and remain unbuilt. The next permitted native comparison should check whether those changes restore the missing log and remove `_bcopy`, then continue with the remaining instruction and CFG differences.
### IOConfigTable selector reconciliation (2026-10-05)

The reference `-[ATI fixDeviceDescriptionForPCI:]` decompiles its FB Address lookup as `-[IOConfigTable valueForStringKey:]`. This agrees with `src/driverkit-3/driverkit/IOConfigTable.h`; the current reconstruction had introduced an `ATIRageLegacy` category for `valueForString:` and called that selector at four ATI configuration lookups. That category was unsupported by the framework contract and made the reconstructed driver send a selector the table does not declare. Corrected all four source calls to `valueForStringKey:`, imported `IOConfigTable.h`, and removed the legacy category. The candidate v235 IDB correctly remains an account of the previously built bytes, which still encode `valueForString:`; it must not be relabeled to hide the source/binary mismatch. No native rebuild or Binrecon comparison was run because automatic review had blocked syncing to the native guest. Source SHA-256 is recorded after this edit in the plan; the v235 binary remains the latest accepted artifact.

Both reference and candidate IDBs now persist the `IOConfigTable *` local type in `fixDeviceDescriptionForPCI:`; the reference also has the source-derived `barRegisters[18]`, `IORange portRanges[9]`, and `IORange memoryRanges[8]` local arrays. Hex-Rays exposes `.start` and `.size` field uses. Updated reference export preamble to document these annotations. Current typed export SHA-256 values: reference `36DC4C671A6221D963135544F6E8222C6A03F6072BC6F3A44F61118881A68FDA` and candidate `C380E19453A7EEB4407BE5A2C21CC07F411D7299EFE93EE6C62C76A7E1236BBD`.

After the source edit shifted method lines, regenerated `source-map.json` from the v235 reference analysis and the three source files. It still resolves 59 handwritten entries with no disputed boundaries. `check_reconstruction.py` confirms all 63 code entries and all 12,267 text bytes are accounted for against the reference contract. Source-map SHA-256: `E5E1482B75CEFA081A3C6F7A9AE4607995403CD387FCBAF2D31144CE8EBF1EFC`.

Ran `tools/binrecon/selector_check.py` against the reference binary and reconstructed LKS project. It found 50 reference selectors, 48 source method definitions, and the two expected generated selectors; missing, extra, renamed, and duplicate lists are all empty. This validates method-definition coverage. The four `IOConfigTable` message sends are tracked separately because the checker does not inspect message-send call sites.

### Initializer common cleanup path (2026-10-05)

Adjusted the missing Display Mode branch to log and flow into the same final `[driver free]` return as parse, aperture, and range setup failures. Reference IDA pseudocode places the missing-mode log in an `else` branch and has one shared `-[ATI free]` return after the full mode-selection block; the source previously returned from the missing-mode branch separately. This removes a duplicate source-level cleanup send and follows the recovered control flow. Regenerated the source map after the two-line reduction; 59 source entries remain mapped, and `check_reconstruction.py` still validates all 63 reference code entries and 12,267 text bytes. `selector_check.py` still reports zero missing/extra/renamed/duplicate method definitions. Source SHA-256: `FC4FF461628A08D9ABED488F3E7A192382601F8591A801D88A4F968D35B9A14E`; source-map SHA-256: `05D8A33ED4FA64CFA203080E138F8DFFB2586D053A5B1755B4BA7230302251A9`. This source change is unbuilt; call-site and CFG effects need a fresh Binrecon comparison.

### v235 structural reconstruction gate (2026-10-05)

Ran `check_reconstruction.py` with the reference, the current source map, and the accepted v235 artifact. It exited 0 and reported the reference contract valid: all 63 code entries and 12,267 text bytes accounted for. Since the rebuilt artifact was supplied, this also confirms the checker's ABI, static-data coverage/pointer-target, and transition/thunk gates pass for v235. This does not cover `normalized-functions`; the six function-body mismatches remain. The gate applies to v235 bytes, not the later unbuilt source edits.

### Transfer-table IDA annotations (2026-10-05)

Renamed source-supported locals in `-[ATI setTransferTable:count:]` in both v235 IDBs: `_cmd`, `table`, `count`, `initialShift`, `chipId`, `allocatedTransferTables`, `bitsPerPixel`, `grayValue`, `grayIndex`, `rgbIndex`, `ramdacType`, and `componentShift`. Hex-Rays now makes the grayscale and RGB paths and the shift inputs readable without changing code or inferred data types. Refreshed this method in both typed pseudocode exports and saved the reference and candidate IDBs. New export SHA-256 values: candidate `9FAF2ACBFA7193E62CBABAB2784039516BBBC873F69BEE77CA4A18958B273B61`; reference `4C45A55925F4EFE255286FDA8216C5FD8DF5796A0919EBFA82E66C9C91B8FD4E`. These remain faithful to v235 bytes; they do not apply the newer unbuilt source trial or alter the Binrecon result.

### Blit helper IDA annotations (2026-10-05)

Renamed `_doBlit` locals in both v235 IDBs from register-oriented Hex-Rays names to source-supported names: `destinationXReg`, `overlapXDistance`, `overlapYDistance`, `destinationYStart`, `registers`, `direction`, source/destination start coordinates, and the three saved MMIO registers. The candidate and reference use different temporary layouts, so candidate `blitSize`/`blitControl` and reference `blitControl`/`blitSize` follow their actual roles. Refreshed both export sections and saved the IDBs. Candidate typed-export SHA-256: `4DA45B014DA0AF56DAD8D65299F84B460BAB2B51597E18B99F583F7D616144E4`; reference typed-export SHA-256: `8849BD8519A8CFCD9E24625B5D026E76C94BB02756F6FABC8403872C99A6C5BF`. This documents v235's actual stack/register allocation; no binary bytes or Binrecon input changed.

### Initializer IDA local recovery (2026-10-05)

Expanded the v235 `initFromDeviceDescription:` decompilation in both saved IDBs using the source and DriverKit declarations. Named port probes, saved port state, BIOS base, mode/config strings, ASIC and memory names, range list, framebuffer pointer, and diagnostic arguments; corrected the display-info copy destination name in candidate v235. Typed `memoryRangeList` locals as `IORange *`, mapped framebuffer locals as `void *`, BIOS base as `unsigned int`, config-table locals as `IOConfigTable *`, returned names and config strings as `const char *`, the candidate copy destination as `IODisplayInfo_Recovered *`, and its free selector as `SEL`. This improves analysis readability while keeping v235 pseudocode faithful to the built `valueForString:` selector and `_bcopy` call. Candidate export SHA-256: `C380E19453A7EEB4407BE5A2C21CC07F411D7299EFE93EE6C62C76A7E1236BBD`; reference export SHA-256: `36DC4C671A6221D963135544F6E8222C6A03F6072BC6F3A44F61118881A68FDA`. No binary bytes or comparison inputs changed.
### PCI method local-variable recovery (2026-10-05)

Recovered clean IDA output for `-[ATI fixDeviceDescriptionForPCI:]` in both v235 databases. The candidate and reference had 30 and 31 saved local-variable entries from the failed annotation pass. Clearing those entries alone left the cached Hex-Rays warning; flushing the function cache with `ida_hexrays.mark_cfunc_dirty` removed it. Reapplied only the three source-backed arrays, matched by exact stack offset and width in each IDB: `barRegisters[18]` (`unsigned __int32`, 72 bytes), `portRanges[9]` (`IORange`, 72 bytes), and `memoryRanges[8]` (`IORange`, 64 bytes). Both methods now decompile without the allocation warning. Refreshed the PCI method in the candidate and reference typed exports and saved both IDBs. Full export SHA-256: candidate `F1DB39B840EEA56B20C717FBB79E2DE5476DB8F71F69FC9028475BC9961CFB6C`; reference `F7017F0417BD3A77208A1ECB3D4FC099925ED142AFFBC8CC2AE1C51992288DED`. This updates type/name metadata only; v235 bytes and Binrecon comparison results are unchanged.

### Full v235 pseudocode pass (2026-10-05)

Re-decompiled all 61 functions in the saved candidate and reference IDBs after recovering `fixDeviceDescriptionForPCI:`. Both databases report zero decompilation exceptions and zero local-variable allocation warnings. This verifies that every function represented in the 61-function exports produces current pseudocode; it does not change the six-function `normalized-functions` parity result or claim semantic/runtime validation. Binary bytes are unchanged.

### GDT setup local recovery (2026-10-05)

Renamed the compiler temporaries in `-[ATI_BIOS setupCodeSegments]` in both authoritative v235 IDBs using the values they carry: `code16BaseAdjusted`, `stackAllocation`, and `stackBaseAdjusted`; also named the implicit selector argument `_cmd`. The names distinguish the two address calculations from the allocated stack pointer while preserving the distinct candidate/reference instruction layouts. Refreshed the matching setup-method blocks in both typed pseudocode exports. The candidate still renders its linked `_bios16` immediate as `strcpy("|.")`, and the reference still exposes its image-specific immediate; raw disassembly remains authoritative for those bytes. Type/name metadata only: binary bytes and Binrecon results are unchanged.

### PCI range reconstruction locals (2026-10-05)

Named source-verifiable temporaries in both `fixDeviceDescriptionForPCI:` IDBs and refreshed the corresponding full method blocks in the typed exports. Recovered roles include BAR probe mask/size and register number, memory/port counts and alignment cursors, the low-address override decision, the config-table FB address parse, the candidate memory base search, range-setter results, and error-log names. Candidate and reference local lifetimes/register allocation differ, so names follow each side's actual use rather than forcing matching temporary layouts. Live IDA text matches both exported method blocks exactly (231 candidate lines; 256 reference lines). Both methods still decompile; types and names only changed, leaving v235 binary bytes and Binrecon findings untouched. Updated full export SHA-256 values: candidate `9F5A9134A52B390D5326D648FA1A36F7F3A44B4B89558880BA91C28025294D1F`; reference `B30AD7A8F9243DC656681E16AC451E2E531487D8C3AB3BB30F580600FA352074`.

### GPU fill and engine setup IDA recovery (2026-10-05)

Recovered source-backed local names and types in both authoritative v235 IDBs for `_doFill` and `-[ATI initEngine]`. `_doFill` now identifies the volatile MMIO register pointer and the three saved register values. `initEngine` now types `info` as `IODisplayInfo_Recovered *`, exposing `width` and `bitsPerPixel`, and names pitch, the staged MMIO pointers, selector, and driver name. Candidate and reference method exports match live Hex-Rays output exactly for both methods (25 lines each for `_doFill`; 79 each for `initEngine`). Full typed-export SHA-256: candidate `3FE60D883E8DDB877F35D81DDA43DEB5BBE00DE7E47EA625CE0EED161A50FDEB`; reference `C40979F72A800C93468E343FA7D12BBAC17D21180AE86C1192739E5AB154E4F3`. Saved both IDBs. Metadata only: v235 binary bytes and Binrecon comparison results are unchanged.

### BIOS VGA-mode IDA recovery (2026-10-05)

Recovered the locals in `-[ATI_BIOS setVGAMode:gamma:]` in both v235 IDBs using `ATI_BIOS.m` and the 48-byte `ATI_BIOSRegisters` definition: named `gammaFlag`, `biosResult`, and `registers`; applied `char`, `int`, and `ATI_BIOSRegisters` types; and named the selector `_cmd`. Hex-Rays now identifies the mode/gamma flags in `registers.ecx.bytes.low` and the BIOS status byte in `registers.eax.bytes.high`. Candidate and reference exports match live IDA output exactly (26 lines each). Full typed-export SHA-256: candidate `79367DBEFB779C583AF759062C15B25226C8CE9D8A224E4354CD88C337570E1D`; reference `CFB7C66328771A419527132165A8B6E309260D19547FB76CBC3670C910914DDA`. Both IDBs are saved; v235 bytes and Binrecon inputs are unchanged.

### BIOS aperture setup IDA recovery (2026-10-05)

Annotated both v235 `-[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]` methods from source: named the BIOS return value `biosResult`, the six-word local prefix `registerWords`, the ECX flag byte `apertureFlags`, and the selector `_cmd`. The source-backed names expose the enable/VGA/aperture flag construction, 1 MiB alignment check, address encoding, and BIOS status path. The candidate and reference exports match live IDA output exactly (40 lines each). Full typed-export SHA-256: candidate `5B03AE6BA3041BB7FA6FC669722641D803539225D2CB30D5C49F7CF1E5EDB5FA`; reference `0C304126DDA48046DBA6894484F514A93476A5002836B22681804BFABC4CCDBF`. Saved both databases; binary bytes and Binrecon comparison inputs are unchanged.

### BIOS device-query IDA recovery (2026-10-05)

Recovered the `-[ATI_BIOS deviceQuery:bufferSize:buffer:]` local roles in both v235 IDBs from `ATI_BIOS.m`: `_cmd`, `biosResult` (`int`), the register-word prefix, the query flag byte, and the 16-bit BIOS buffer offset (`136`). The decompilation now exposes the buffer setup, query flag, segmented BIOS call, and return/status paths with source-supported names and widths. Candidate and reference method exports match live IDA output exactly (42 lines each). Full typed-export SHA-256: candidate `C06B63899D625029BCB3859106CD2D29BB25A736B28C9FA2D04ADA2C9EF3E5F2`; reference `3375CFCD4536AD03988AF517C8CC19C9E533C854F115929920BC051C2FD99641`. Both IDBs saved; v235 binary bytes and Binrecon comparison unchanged.

### BIOS DPMS and APM IDA recovery (2026-10-05)

Recovered source-backed names and types in both v235 IDBs for `setDPMSMode:`, `getDPMSMode:`, `setAPMState:`, and `getAPMState:`. Setter methods now expose `ATI_BIOSRegisters`, the integer BIOS result, and `registers.ecx.bytes.low` mode/state writes. Getter methods now distinguish the register prefix, result byte, and BIOS return code. The four candidate and four reference exports match live Hex-Rays output exactly (28 lines per setter; 22 lines per getter). Full typed-export SHA-256: candidate `6052919B17B404EC278A86BAD3CE42A4F37B1933B3D7762E5899A34B67223D13`; reference `BDA585D3AED402916D8D27B28B9A29BC065B9784F0A64147C61CAB50DDC212DD`. Both IDBs saved; v235 binary and Binrecon comparison are unchanged.

### BIOS address and refresh query IDA recovery (2026-10-05)

Recovered source-backed locals and selector names in both v235 IDBs for `getIOBaseAddress:relocatable:`, `getRefreshRate:`, and `shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:`. Address query now identifies the register prefix, relocatable flag, returned base address, and BIOS result; the refresh query identifies the BIOS result, register prefix, EBX input word, and 0x88 query buffer offset. `shortQuery` names its 48-byte `ATI_BIOSRegisters` block and integer BIOS result, and uses the source's signed-byte `ATIByte` output pointers. All three candidate and reference method exports match live IDA output exactly (28, 36, and 41 lines). Full typed-export SHA-256: candidate `FEA43E016AFEE1DD609B1F0A26E7DC8D50C0B168F3941BB836C381D89E323C65`; reference `C05B7A0348F1992BA52EBDAC8B980E478FC22EB349415E8DDA09E48312714498`. Both IDBs saved; binary bytes and Binrecon comparison remain unchanged.

### Query-data acquisition IDA recovery (2026-10-05)

Named and typed the `-[ATI getQueryData]` temporaries in both v235 IDBs from the implementation: query-size and device-query return codes, query size, temporary 16-bit buffer, returned data length, allocated persistent buffer, and driver/error log strings; also named `_cmd`. This exposes the query allocation/copy/free path and both failure logs in the decompilation. Candidate and reference method blocks match live Hex-Rays output exactly (48 lines each). Full typed-export SHA-256: candidate `AC36D8727BD829980111EEF41DD74A935BBD12DB9167405B3458DBACDECEE122`; reference `3420B99751AE08D54826A2D53808546477BFE017FE3249F9D98B48A9CDAFDFCC`. Both IDBs saved; binary bytes and Binrecon result remain unchanged.

### Driver query and mode-parse IDA recovery (2026-10-05)

Recovered the remaining source-backed locals in `-[ATI getQueryData]` and `-[ATI parseModeString:]` in both v235 IDBs. The query routine now exposes its size/device-query result codes, buffer size, temporary/persistent buffer roles, and diagnostic strings. The parser now exposes the selected mode, unsigned validation error, and the distinct log-name temporaries. Both candidate and reference method exports match live Hex-Rays output exactly (48 lines for `getQueryData`; 26 for `parseModeString:`). Full typed-export SHA-256: candidate `E57B2B38697F8F8A21FA7B9F9ED5B3EB49F2880B2CD465099DF96BE2AEDFF69F`; reference `493FAF725801A4E71C026F196EC6992DEDB74167604CD497AED5FDE23024EF56`. Both IDBs saved; v235 bytes and Binrecon comparison unchanged.

### Mode-list update IDA recovery (2026-10-05)

Named and typed the source-backed `-[ATI updateModeList]` locals in both v235 IDBs: device description, config string and its free/log lifetimes, driver name, pixel encoding, mode index and field-index temporary, and `IOConfigTable *configTable`; named the selector `_cmd`. The decompilation now shows RGBx/BGRx/xRGB/xBGR mapping, per-mode framebuffer/gamma/encoding updates, and memory-based unavailability handling. The candidate binary uses `valueForString:` while the reference analysis uses `valueForStringKey:`; retained each IDB's observed selector. Candidate and reference blocks match live Hex-Rays output exactly (85 lines each). Full typed-export SHA-256: candidate `F7999A46DE344DB9B5F58FB9E0FEB42BB4DFCDECFC7577931966BE845CF780D5`; reference `0B469392C5BDFBEAAF848F27073904380077AFDE3FA96928DF5981A91350952D`. Both IDBs saved. Full decompile pass: 61/61 functions, no exceptions per IDB. This is analysis metadata; v235 binary bytes and Binrecon comparison are unchanged.
### Display-mode path IDA recovery (2026-10-05)

Recovered source-backed local names and types in both v235 IDBs for `-[ATI isModeValid:]`, `-[ATI enterLinearMode]`, `-[ATI verifyMemoryMap]`, and `-[ATI revertToVGAMode]`. Mode validation now exposes the mode index, `IODisplayInfo_Recovered *`, bits-per-pixel, and required framebuffer bytes. Linear-mode entry exposes display info, color depth, pitch, BIOS result, CRTC record pointer, and separate driver/error strings. VRAM verification exposes its 16-word saved buffer and separate write/read indices. VGA restore now uses the 32-byte `ATI_CRTCRecord` plus distinct CRTC/VGA results and log temporaries. Each side's four method blocks match live Hex-Rays exactly (27, 49, 19, and 43 lines). Full typed-export SHA-256: candidate `E88846B90C971CC1F96794427EFA8C47E1F33E2FF43D1ECFE3BB22426E55239C`; reference `5425886103CB9C3E0010952A39FD029D4EE65E17D2E37076E30567B09698C264`. Both IDBs saved; full decompile pass remains 61/61 with no exceptions in either database. This pass changes analysis metadata only; binary bytes and Binrecon comparison inputs remain unchanged.
### Gamma programming and idle wait IDA recovery (2026-10-05)

Recovered `-[ATI setGammaTable]` locals in both v235 IDBs: DAC port/value and display depth, preserving the source-backed transfer-table and gamma loop indices; named the selector `_cmd`. Recovered `_waitForIdle`'s assembly-derived loop counter and pre-increment value. Candidate and reference method blocks match live Hex-Rays exactly (61/62 lines for `setGammaTable`, including the reference's existing semantic note; 20 lines for `waitForIdle`). Full typed-export SHA-256: candidate `82571EF806CD26D8262FE152E9CEEF2C1D41ABF7B0055B022E30BD347BA67BEE`; reference `3FF13CB179D5F66C5AFFF450BFC140AC379A43035AA026FCE26BFA59F69B8F79`. Both IDBs saved; each still decompiles all 61 functions without exceptions. Analysis metadata only; binary bytes and Binrecon comparison inputs are unchanged.
### Display-control method IDA recovery (2026-10-05)

Named and typed the arguments and source-backed temporaries in both v235 IDBs for `-[ATI setPendingDisplayMode:]`, `-[ATI setIntValues:forParameter:count:]`, `-[ATI free]`, and `-[ATI setBrightness:token:]`. These now show the mode index, integer-value array/name/count, the super-call records, brightness, and token; selector arguments are `_cmd`. Candidate and reference blocks match live Hex-Rays output exactly (23, 40, 14, and 14 lines per side). Full typed-export SHA-256: candidate `977DD1C77B38BDA9A7682FB8D605E4B4FA4DE350A6C2EF0AF103C032D3707906`; reference `BEFCD221527F184FE3119AD2F3C105D10A270FDDA5D58E1DC350009A4217C4D2`. Saved both IDBs; all 61 functions decompile without exceptions in each. Analysis metadata only; binary bytes and Binrecon inputs are unchanged.
### BIOS segment and lifecycle IDA recovery (2026-10-05)

Recovered source-backed locals in both v235 IDBs for `restoreCodeSegments`, `createDataSegment:size:`, `restoreDataSegment`, `doBios:dataSeg:`, `+[ATI_BIOS ATIPresent:]`, `init`, `initAtSegmentAddress:`, and `free`. The decompilation now labels the 16-bit and stack descriptor pointers, constructed data-segment byte pointer and encoded limit value, BIOS call result, scan base/offset/signature, and super-call records. Updated blocks match live Hex-Rays exactly (14, 45, 4, 14, 19, 17, 11, and 10 lines per side). Full typed-export SHA-256: candidate `9C2C7FEF54962384D30A883D7A395EBDB62A8AA9D21F12A2E6ED6B762C8A357B`; reference `9B544134460D674E966D9F285F7D803731C8BF18577605E47AA3911828FACCA2`. Both IDBs saved; both retain a clean 61-function decompile pass. This is IDA metadata and export work; binary bytes and Binrecon comparison inputs are unchanged.
### Cursor forwarding methods IDA recovery (2026-10-05)

Named the selector and superclass forwarding records in `showCursor:frame:token:`, `moveCursor:frame:token:`, and `hideCursor:` in both v235 IDBs; cursor, frame, and token parameter types/names were already source-typed. All six candidate/reference blocks match live Hex-Rays exactly (9 lines each). Full typed-export SHA-256: candidate `F0A4931C5FB3664B726871057BF3AF8BE9C33909900754AC4104126090DF8DAE`; reference `7DBBF43D354381B0CC9156BDFEF09F094DC34CFFF34EE8629AB9C4C076D1BB23`. Both IDBs saved, with all 61 functions decompiling without exceptions. Binary bytes and Binrecon inputs are unchanged.
### C helper signature and local IDA recovery (2026-10-05)

Recovered source-backed arguments and local roles in both v235 IDBs for `isATI68880RevC`, `SetGammaValue`, `displayInfoToColorSpace`, `colorDepthToColorSpace`, `displayInfoToColorDepth`, and `memSizeToBytes`. Display-info helpers now use the recovered const display-info pointer so Hex-Rays names `bitsPerPixel` and `colorSpace`; gamma helper arguments now identify RGB channels and brightness. Candidate/reference blocks match live Hex-Rays exactly (7, 13, 27, 23, 26, and 30 lines). Full typed-export SHA-256: candidate `575BF6EC3101D2FA9991CD22FD53A67F5BA8D1834E3D813ED3902565E91639E0`; reference `8700EEF2D654A9F9BF5A54C8EC50D8830D015FCE6B99E4BB94D27DDA21164985`. Both IDBs saved; 61/61 functions decompile without exceptions. Binary bytes and Binrecon inputs remain unchanged.
### Objective-C selector argument recovery (2026-10-05)

Renamed the implicit `SEL a2` parameter to `_cmd` in both authoritative v235 IDBs for 13 methods: `verifyMemoryMap`, `enterLinearMode`, `resetEngine`, `displayModeCount`, `displayModes`, `displayMemorySize`, `loadCRTC:gamma:pitchSize:resolution:crtTable:`, `loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:`, `querySize:size:`, `changeRefreshRate:`, `initBIOSBuf:function:`, `loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:`, and `+[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver]`. The candidate and reference typed exports were refreshed from live Hex-Rays output for those sections; all 13 sections per export now match exactly. Both IDBs decompile all 61 functions without exceptions, and the selector-local inventory contains no remaining `SEL a2`. Full export SHA-256: candidate `DDAFEA2DF4135BF33EF4644413703407696ED16436C63948E504A026EA8A0407`; reference `1D06F5F1486ACB5EC88E36BF1F2E04FA2F925A008A77FB936767FCBEFBAE55C7`. Metadata/export updates only; v235 bytes and Binrecon comparison inputs are unchanged.

### Linear-mode and VRAM-check local cleanup (2026-10-05)

Finished the source-backed local names in candidate v235 `-[ATI enterLinearMode]` (`info`, `depth`, `pitch`, `biosResult`, `driverName`, and `errorName`) and `-[ATI verifyMemoryMap]` (`savedVram`). The reference IDB already carried the corresponding names. Refreshed the candidate export sections from Hex-Rays; candidate and reference sections match live IDA exactly. Both databases decompile 61/61 functions without exceptions. Candidate export SHA-256: `96427086F21CC438714CCFDA93A7C6BDAC9778AB1E3FBEF7BF94131AD836B10F`; reference remains `1D06F5F1486ACB5EC88E36BF1F2E04FA2F925A008A77FB936767FCBEFBAE55C7`. These are IDA metadata and export updates only; v235 bytes and Binrecon comparison inputs are unchanged.

### BIOS transition wrapper typing and generated receiver (2026-10-05)

Typed `_ATIbios16`'s argument as `ATI_BIOSRegisters *` and named it `registers` in both v235 IDBs, matching the checked-in wrapper source and exposing field accesses at the established register layout. Named the generated version method's class receiver `self`. Refreshed both export sections from live IDA. Both IDBs still decompile 61/61 functions without exceptions, and the two affected export sections match live pseudocode exactly. Full export SHA-256: candidate `B85FC9CCE7AC0CD8E18B78A481BFB03CD606A5493187AF0FBDDC25442C93F1EE`; reference `C034D026A31D8CCB887C053BF757783A76F66EAD644796E0596E91934210B9D3`. Type/name metadata only; binary bytes and Binrecon results are unchanged.

### Engine-reset temporary recovery (2026-10-05)

Named the seven source/disassembly-backed temporaries in `-[ATI resetEngine]` in both v235 IDBs: the two D0 port values/addresses, their clear/set forms, and the A0 configuration value. Candidate and reference disassembly are instruction-for-instruction identical, including the three locked increments; only the counter symbol differs (`resetEngineWriteCounter` vs. reference `_xxx_92`). Refreshed both export sections; each matches live Hex-Rays, and both IDBs still decompile 61/61 functions without exceptions. Full typed-export SHA-256: candidate `6A63B3A2D612E16B00D915B90792B73F67980EA37EDBB37F7D01174320C1021B`; reference `565A485B03DFA14C89ECEFDFB058795CB7A5FC059CFE8D6AD321A38B24DAAA73`. This is annotation/export work only; binary and Binrecon comparison remain unchanged.

### Initializer failure-site reconstruction (2026-10-05)

IDA's full reference `-[ATI initFromDeviceDescription:]` decompilation has 12 `IOLog` sites; v235 has 8. The current source had combined four reference paths (both reset-port probes, VRAM verification, and framebuffer mapping) through one `initFailure` logger. Replaced that shared block with the four distinct reference messages and `[driver free]` returns, preserving the messages, branch conditions, and cleanup. The initializer source now contains 12 direct `IOLog` sites; the pre-existing missing-display-mode log and structure-assignment copy remain in the unbuilt source trial. Regenerated `source-map.json`: 59 mapped handwritten entries, no disputed boundaries, and two generated methods left unmapped. Main-source SHA-256: `226C3F389877DB38393DC0E879EC8350B10ABC1130CEC5FFC0F910EB08C9C27C`; source-map SHA-256: `BCBA165A99653AD28A119305D1380A4148F0F07C99035745B0CA4285C4E5AF9A`. No tests or native build were run; the last accepted binary remains v235 (`57C016AA253B8DCF069DB4FC0C887B3C1AC601E0475661159FCDEC3FCE1BB4E2`), so the compiler-shape effect and Binrecon parity of this source trial remain unverified. The prior native sync/build remains blocked by the automatic review result.

### PCI range control-flow audit (2026-10-05)

Compared current `fixDeviceDescriptionForPCI:` source with the complete typed candidate and reference pseudocode. The retry bound (`memoryRangeCount - 2`) equals the reference's separately materialized count (`memoryRangeCountTotal - 2`); its loop runs once per probed memory BAR, and each per-BAR scan resets the candidate to the chosen framebuffer base and advances by that BAR's size. The restoration loop similarly writes one memory BAR per probed memory range, with the same `0x10..0x27` register bound as the reference. BAR probing, low-address relocation, alignment arithmetic, VGA ranges, three legacy port ranges, setter reset/call/error paths, and the `FB Address` mask/threshold match. Differences in temporary counts, loop form, and register allocation are compiler/dataflow shape only; no source change is supported by this audit. The saved candidate/reference call sequences have identical ordered targets; Binrecon's call-site-relative mismatch is a layout consequence. Current source remains unbuilt, and v235's strict function-byte findings remain unchanged.

### BIOS CRTC command audit (2026-10-05)

Compared `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` source with the complete reference pseudocode. Initialization and `resolution == 128` guards, BIOS buffer setup, mode/gamma/pitch flag composition in ECX low byte, resolution byte in ECX high byte, resolution-129 CRTC-table data segment setup (30 bytes, offset 136, BX 0), BIOS invocation, AH/error logging, and return values (0/1/2/3 or propagated setup error) match. The source's byte-buffer writes represent the same register fields as the reference's `ATI_BIOSRegisters` member accesses. Strict code parity remains a code-generation/layout finding; this audit found no semantic source correction.

### Transfer-table gray-loop instruction ordering (2026-10-05)

Inspected live IDA disassembly for candidate v235, candidate v236, and the reference `-[ATI setTransferTable:count:]`. The reference loads red and green bases, then reloads the blue base inside each grayscale iteration before reading `table[i]`; v235 loads the blue base after reading and shifting `table[i]`; v236 hoists the blue-base load before the loop. This explains why v236's extra normalized instruction did not improve the 124-instruction LCS against the reference. Current source places a blue-base read inside the loop before a compiler memory barrier and the source-byte read, but no accepted candidate was built from that current source state. Do not infer target parity from the source ordering; a compiler run and regenerated IDA/Binrecon comparison are needed to evaluate it. No source change was made in this audit.

### BIOS thunk entry relocation and blit semantics (2026-10-05)

Live IDA name/xref queries confirm the immediate descriptor targets in `setupCodeSegments` are each binary's own `__bios16` symbol: candidate target `0x2E7C` and reference target `0x2E48`. The current source computes the descriptor base from `_bios16 + 0xC0000000`, so the immediate difference is correct link relocation, not a hard-coded source defect. Also compared candidate/reference `_doBlit` pseudocode and current source: signed-direction absolute overlap distances, strict width/height overlap checks, source/destination reverse starts, direction bits, MMIO save/write/restore order, FIFO waits, and returned register base agree. No behavior change is indicated for either method; their strict findings are instruction/CFG layout differences.

The `_doBlit` comparison did uncover a source type mismatch: IDA gives `sourceYStart`, `destinationXStart`, and `sourceXStart` unsigned 32-bit locals on both binaries, but source had them as signed `int`. Changed those three declarations to `unsigned int` so coordinate packing and the `<< 16` operations use the recovered unsigned arithmetic. This is source-only and unbuilt; the v235 comparison remains unchanged.

Live IDA local-variable queries for `setTransferTable:count:` also show `initialShift` and `componentShift` as `char` in both candidate and reference. Narrowed the source's corresponding `shift` and `selectedShift` locals from `unsigned int` to `char`; all assigned shift values are 0 or 2, so their right-shift behavior is unchanged while the reconstructed types match the recovered byte-sized locals. This remains an unbuilt source edit.

The initializer's `queryData` local is `unsigned __int8 *` in both IDBs, while source declared `unsigned int *` and cast it back for each byte access. Changed the source local to `unsigned char *` and removed those redundant casts. Byte offsets and values are unchanged, and the method's source line count is stable; compilation remains unverified.

Added the IDA-recovered `ATI_SegmentDescriptor` source type (8 bytes, fields at offsets 0/2/4/5/6/7) and changed the four saved-descriptor byte arrays in `ATI_BIOSPrivate` to typed descriptors. The order and sizes remain 8 bytes each, followed by `stack_address` at offset 32; the existing 36-byte private-layout assertion remains, with a new 8-byte descriptor assertion. At the time of this note, setup code had not yet been converted to the recovered descriptor type; the layout assertions were uncompiled.

### CRTC loader register-allocation trial (2026-10-05)

Live IDA disassembly shows v235 initializes the gamma flag directly in `DL` (`xor dl,dl`; conditional `mov dl,10h`), whereas the reference initializes `AL`, copies it into `DL`, then reuses `AL` for the shifted pitch. Current `ATI_BIOS.m` has source-level `EAX`/`EDX` register variables (`gammaFlag`, `modeFlags`) and `ESI`/`EDI`/`EBX` constraints for resolution, receiver, and register buffer, specifically expressing the reference's register roles. This source trial is newer than the v235/v236 binaries and remains uncompiled; the expected instruction order is a hypothesis until a new native artifact can be produced and reanalyzed.


### Typed GDT descriptor reconstruction (2026-10-05)

Converted `-[ATI_BIOS setupCodeSegments]` to use `ATI_BIOSPrivate` and `ATI_SegmentDescriptor` members instead of saved raw descriptor bytes and offsets. The method still saves the original code16, thunk, and stack descriptors; computes the code16 and stack linear bases; derives the thunk base from `_bios16`; allocates and clears the 2048-byte BIOS stack; and writes the same access, limit, granularity, and present bits with volatile self-stores at the existing access/limit barriers. The saved descriptor fields remain in the IDA-confirmed offsets (0, 8, 16, and 24), with `stack_address` at 32 and a 36-byte private record. Source-map entry for `setupCodeSegments` is line 418. The refreshed source map passed Binrecon schema validation with 59 mapped entries, two generated entries unmapped, and no disputed boundaries. `git diff --check` passed. No native compile or Binrecon binary comparison was run; v235 remains the last accepted binary, and native execution remains blocked by the earlier automatic-review rejection.


### PCI BAR local signedness reconstruction (2026-10-05)

Live reference IDA locals for `-[ATI fixDeviceDescriptionForPCI:]` type `reg`, `mask`, `probed`, `memoryCount`, `portCount`, the total range counts, and placement indices as signed `int`; `override` is `char`. The per-BAR retry count (`memoryRangeCount` in the reference) and current PCI register are `unsigned int`. Source now uses those signedness distinctions; the total count stays `int` while `count` and `current` are unsigned. The BAR masks are `-4` and `-16`, as in the reference. BAR counters stay bounded by six probed slots and their fixed legacy ranges; `reg` spans only 16 through 39, and address/size values remain unsigned. The declarations preserve those bounded control-flow domains. This remains uncompiled; the v235 binary, strict findings, and parity status remain unchanged.


The same PCI source block still declared its framebuffer-address config-table local as generic `id`, although reference Hex-Rays types it as `IOConfigTable *`, and the source calls `valueForStringKey:` through it. Changed that local to `IOConfigTable *`, matching the already typed config-table local in the initializer and mode-list updater. This pointer refinement preserves the same Objective-C object representation and selector sends; it is source-only and uncompiled.


### Typed BIOS descriptor save and restore (2026-10-05)

Replaced raw `unsigned int` indexing in the BIOS GDT save/restore paths with the recovered private record and `ATI_SegmentDescriptor` fields. `createDataSegment:size:` now saves the data descriptor as a typed 8-byte record; `restoreDataSegment` restores that record; `restoreCodeSegments` restores code16, thunk, and stack descriptors from their named private fields and frees `stack_address`. This follows reference IDA pseudocode, which expresses the same descriptor assignments and stack pointer. Updated BIOS source-map lines after the method bodies shortened. The two project source paths resolve to the same file and have identical SHA-256. Source-map schema validation passed with 59 mapped entries, two generated entries unmapped, and no disputed boundaries; `git diff --check` passed. No native build or Binrecon binary comparison has run.


### Typed BIOS register-block accesses (2026-10-05)

Replaced raw byte/word indexing in `initBIOSBuf:function:` and `loadCRTC_comm` with the recovered `ATI_BIOSRegisters` union fields. The writes still target EAX low byte, code/data selectors, entry offset, EBP stack offset, ECX mode/resolution bytes, EDX table offset, and EBX zero; the AH check/log now reads EAX high byte by name. The structure remains 48 bytes and the EBX-pinned pointer remains explicit in `loadCRTC_comm`. This follows reference Hex-Rays pseudocode and the recovered register-block layout. Native compilation and Binrecon comparison remain unverified.


### Typed BIOS service register accesses (2026-10-05)

Replaced remaining BIOS service byte/word pointer indexing with `ATI_BIOSRegisters` union members in `setVGAMode:`, `setApertureEnable:`, `shortQuery:`, `deviceQuery:`, DPMS/APM setters and getters, `getIOBaseAddress:`, and `getRefreshRate:`. Register roles now follow the live reference pseudocode: EAX low/high, EBX word/low, ECX low/high, and EDX word/dword. The 48-byte block and call/status flow are unchanged at source level. Refreshed BIOS source-line entries in the map. The remaining BIOS unit has no raw register-byte/word indexing in these service methods. Native compilation and binary parity remain unverified.


### BIOS private-record lifetime size (2026-10-05)

Changed the `ATI_BIOSPrivate` allocation and free sizes from duplicated `36` literals to `sizeof(ATI_BIOSPrivate)`. Reference IDA confirms both calls use 36 bytes, and the recovered private-record declaration has a compile-time 36-byte size assertion, so the emitted allocation extent remains the observed value while following the reconstructed type.


A follow-up comparison of the same method's reference locals showed separate unsigned `memoryRetryIndex`, `candidateRangeIndex`, `memoryBARIndex`, and `currentPCIRegister` roles. Replaced the source's shared `index`/`candidate`/`current` use in those two loops with these explicit counters, retaining signed `index` for the BAR-detection and placement scans. Their loop bounds and list counts remain the IDA-observed values. The source map's later main-file lines were advanced by four to track the added locals and assignment.


### Typed `ATI_BIOS` private-record ivar (2026-10-05)

Changed the `_priv` ivar from `void *` to `ATI_BIOSPrivate *` and removed the redundant casts at allocation and all four descriptor save/restore access sites. Reference IDA already renders `_priv` as `ATI_BIOSPrivate_Layout *`; the source type is now the matching reconstructed record. The ivar's pointer size and object layout stay unchanged on i386; the 36-byte record assertion remains authoritative for allocation extent.

### Static BIOS transition source audit (2026-10-05)

Compared the current `ATIbios16.c`, `ATI_BIOS16.s`, and `ATIbios.s` sources against live reference IDA. The C wrapper at `0x2ec0..0x2f1f` matches the recovered offset bound/check, error log and `-1` return, offset truncation, selector save and replacement with `0x90`, zeroed entry offset, thunk call, and zero return. The `__bios16` transition at `0x2e48..0x2ebc` matches the segment clearing, BIOS entry/stack globals, stack switch, runtime far jump and protected-mode SS/ESP restoration before `retf`. The `__ATIbios32` thunk at `0x2f20..0x2fea` matches the saved-register/segment/flags prologue, register-block offsets and widths, far-call selector/offset slots, CLI placement, output-register stores, and plain `ret` (`retn` in IDA). The C declaration is cdecl, consistent with the thunk's plain return. No source change was justified by this static comparison. This does not establish emitted-object parity: the current source has not been compiled and checked in IDA/Binrecon because the previous automatic review rejected native guest synchronization/build; v235 remains the last accepted candidate.

### Initializer display-info copy reconstruction (2026-10-05)

Reference IDA shows the display-info copy as `cld; mov ecx, 0x22; rep movsd`, copying 136 bytes from `AtiModeList[modeNumber]` to the superclass display-info buffer. The current source's C structure assignment had emitted `_bcopy` in candidate v235, so it did not express the observed copy instructions. Replaced that assignment with i386 inline assembly binding destination/source/count to EDI/ESI/ECX and using `cld; rep movsl`; the fixed count is 34 dwords and the memory clobber preserves the copy's ordering. This is an evidence-backed source correction, but generated instructions and normalized parity are unverified because the current source cannot be compiled through the previously rejected native route. Advanced later main-source source-map anchors by 10 lines; BIOS source anchors are unchanged.

### CRTC loader register-role source audit (2026-10-05)

Compared the live reference sequence at `0x2d9f..0x2db6` with current `loadCRTC_comm` source. Reference initializes the gamma flag in AL, conditionally writes `0x10` to AL, copies it to DL, ORs the mode into DL, reuses AL for the low pitch byte shifted by six, then ORs/stores DL to ECX low. The source's fixed EAX `gammaFlag` and EDX `modeFlags` register locals express that same order; ECX high receives the resolution byte. Candidate v235 still shows its earlier DL-only gamma flag, so it cannot validate the newer source. No further edit was indicated by this comparison; compiler output and Binrecon parity remain unverified.

### Display data and resource coverage recheck (2026-10-05)

Ran `generate_display_data.py --check --resource-root src/drivers-i386/video/drvATIRage/ATIRageDisplayDriver.drvproj`: the generated header matches the evidence contract for all 18 CRTC records and 72 mode records, and all 41 manifest resources match their recorded sizes and SHA-256 values. The reconstruction checker also accepted the reference contract and current source map: 63 code entries and all 12,267 text bytes accounted for. This validates the recovered static data/resources and reference/source ownership gates; it does not validate a newly compiled driver or binary parity.

### Transfer-table grayscale data-flow audit (2026-10-05)

Reference IDA loads red, green, then blue table bases inside each grayscale iteration, fetches `table[i]` and shifts its low byte, then writes the value to blue, green, and red. The current source has the same per-iteration pointer assignments, a compiler memory barrier before the table fetch, and the same write order. Its RGB branch extracts bytes 3, 2 and 1 into red, green and blue, matching reference instructions. No source-level behavioral mismatch was found; current output remains unbuilt and the v235 strict comparison cannot confirm these newer source edits.

### Source-map and parity-ledger anchor reconciliation (2026-10-05)

Synchronized the parity ledger's source path/line anchors with the current source map for all 59 handwritten entries. The consistency pass reports 59 mapped entries and zero ledger/source-map anchor mismatches; the two generated methods remain unmapped as intended. The reconstruction checker still accepts the 63-entry code partition and all 12,267 text bytes. Function review statuses were not advanced by this bookkeeping pass.

### BIOS descriptor and stack cleanup-path audit (2026-10-05)

Compared `createDataSegment:size:`, `setApertureEnable:VGAAperture:apertureAdrs:`, `initBIOSBuf:function:`, and `doBios:dataSeg:` source with reference IDA. The data descriptor math matches: size `> 0x10000` returns 3 before saving or changing the data descriptor; accepted sizes encode `size - 1` directly or a page-rounded limit. Uninitialized service calls return 1 before `initBIOSBuf`, so they do not alter GDT state or allocate the BIOS stack. Aperture misalignment returns 3 after `initBIOSBuf` has run `setupCodeSegments`; this early return leaves the temporary code/stack descriptors installed and the allocated 2048-byte stack unrecovered. Likewise, an oversized data-segment result propagates out of `loadCRTC_comm` before `doBios`, leaving that setup unrecovered while the data descriptor remains untouched. Once `doBios` is entered, it calls `restoreCodeSegments` after `ATIbios16` regardless of its result, then restores the data descriptor only when `dataSeg != 0`; `restoreCodeSegments` restores three descriptors and frees the 2048-byte stack. The invalid BIOS entry-offset `-1` path therefore still restores through `doBios`. The source preserves these observed early-return quirks; no cleanup was added.

### BIOS DPMS/APM and refresh service audit (2026-10-05)

Compared current BIOS service source with live reference IDA pseudocode. DPMS set/get use BIOS functions 12/13; set accepts modes 0..4 and writes `mode & 3`, while get clears ECX low before the call and returns its low two bits. APM set/get use functions 14/15; set accepts 0..3 and masks with 3, while get returns the low two ECX bits. I/O-base query uses function 18, returns ECX bit 0 as the relocatable flag and EDX as the address. Refresh query uses function 21 with a 20-byte data segment, writes offset 136 and BX=0, then returns the BIOS status. `changeRefreshRate:` returns 3. These values, bounds, and packed fields match the current source; no source correction was supported by this pass. Native instruction parity remains unverified.

### Blit overlap and MMIO source recheck (2026-10-05)

Rechecked the current `doBlit` source against the complete reference pseudocode and disassembly. Unsigned coordinate differences followed by signed-negative detection reproduce the reference absolute overlap distances; strict width/height overlap tests, reverse starting coordinates, direction bits, packed XY/size writes, FIFO waits, MMIO save/write/restore order, and return value match. Current source keeps source X in EAX and destination X in ECX, and folds the direction/control bits into the register write without the `blitControl` spill seen in v235. Since v235 predates these current source changes, this is source/IDA agreement only; no compiler parity claim is made and no source correction was justified.

### FIFO and idle polling instruction audit (2026-10-05)

Compared current `waitForFIFO` and `waitForIdle` inline assembly with reference IDA. FIFO wait computes `0x8000 >> count` in EAX, checks the MMIO value at `register_base_address + 784`, and loops while it is above the threshold; the initial `jbe` skips polling when the threshold is already met. Idle wait calls FIFO wait with 16, tests busy bit 0 at offset 824 before delaying, delays one tick, compares the pre-increment counter against 500000 with unsigned `<=`, then either polls again or returns the timeout logger result. Both paths and the returned EAX value match the reference instruction order. No source change was indicated; compiled parity remains unverified.

### Drawing and engine initialization source audit (2026-10-05)

Compared current `doFill`, `initEngine`, and `resetEngine` source with the reference IDA pseudocode/disassembly. `doFill` preserves the reference sequence: idle wait, FIFO(7), save MMIO offsets 728/436/304, set color and fill command, pack `(left << 16) | top` and `(right << 16) | bottom`, FIFO(3), restore those registers in order, and return the register base. `initEngine` writes the recovered engine registers and pitch in the same order, uses width-1 at offset 0x2B0 before width-1 at 0x2A4, applies the depth constants (`0x01020202`/`0x8080`, `0x01030303`/`0x4210`, `0x01060606`/`0x8080`), and finishes with `waitForIdle`; unsupported depths log and fall through to that wait. `resetEngine` matches the reference's two D0 reset-port read/modify/writes, A0 configuration update, and locked counter increments. No semantic source correction was indicated. This is a source-to-reference audit only and does not establish emitted parity for the latest source. `git diff --check` passed.

### Initializer control-flow source audit (2026-10-05)

Compared the current `initFromDeviceDescription:` source with reference IDA pseudocode. The two PCI reset-port probes, their distinct failure messages, and the original-value restoration after successful probes are present in the same sequence. Query-data failure reaches superclass cleanup without another log; the RAMDAC string is freed after parsing; a missing Display Mode logs and frees the driver; parse/aperture failures reach cleanup; framebuffer-map and VRAM-verification failures use their distinct logs; and the success path copies 0x88 bytes with `cld; rep movsl`, initializes the transfer-table state, and returns the driver only after `verifyMemoryMap` succeeds. This matches the reference's branch behavior at source level. Emitted instruction parity remains unverified because the latest source has no accepted native build/Binrecon result.

### Ledger artifact binding audit (2026-10-05)

Current evidence shows `ledger.json` is bound to rebuilt SHA-256 `94E003860FEE0B80A60C3C7062CD1BA4B93C7500392842B7C756629544DAED70`, the v89 candidate. The latest accepted candidate is v235 at SHA-256 `57C016AA253B8DCF069DB4FC0C887B3C1AC601E0475661159FCDEC3FCE1BB4E2`; its run summary explicitly reports `ledger.updated: false`. The current source is newer than both binaries. The ledger therefore cannot certify v235 or the current source, and its binding must not be changed without reviewing against a newly built candidate. The current `drvATIRage-i386` output contains only the reference baseline and a source-map trial file, not a rebuilt image or comparison.

### Placeholder and source-coverage sweep (2026-10-05)

Searched the drvATIRage source tree for TODO/FIXME/stub/unimplemented markers and enumerated the Objective-C/C methods in the main and BIOS implementation files. No live placeholder implementation was found; the only “placeholder” match is a historical note describing the initial state. The source map accounts for 59 handwritten entries and intentionally leaves two generated entries unmapped, covering the reference's 61-function partition. This confirms source coverage, but does not close the pending latest-source compile, parity, or runtime gates.

### Gamma-table programming source audit (2026-10-05)

Compared current `-[ATI setGammaTable]` source with reference IDA pseudocode and disassembly. The DAC mask/index writes occur in the observed order with a locked counter increment after each output. With transfer tables, the method iterates each table entry and repeats its RGB value `256 / transferTableCount` times. Without transfer tables, it reads `bitsPerPixel` from display-info offset 24; depth 1 emits 256 `gamma8` entries, depths 3 and 4 each emit 32 outer iterations by eight inner writes using `gamma16[m >> 1]`, and other depths perform no gamma writes. Source return and branch structure agree with the reference. No semantic correction was indicated; current emitted bytes remain unverified.
