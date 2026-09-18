# Finish campaign

Date: 2026-09-17
Branch: `pnpdump-binrecon-finish`

This file tracks instruction-stream work on the **PnPDump** tool. Reloc findings stay in `reconstruction/divergences.md` and are not restated here.

## Rebuilt identities (Task 4)

| Artifact | SHA-256 | Size |
| --- | --- | --- |
| PnPDump (tool) | `04B61B40568C6830F076C83D45FE7511EE2FE04AE68C0043BF4BCF5B3E2EF8B9` | 299684 |
| EISABus_reloc | `4430CA7B3DE0161164445D54DAF584B88CB0D48DFF5E7D55F565670A900E41F8` | 603952 |

Apple references remain `006DC6BB73CEBC6243DA669E5199AEC808F309E72C3EE617A3FD8ED310364772` (PnPDump, 59260) and `8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23` (EISABus_reloc, 100752).

No instruction-shape edits in this pass. `parity_check.py` is missing 0 / 0 on both pairs. Normalized-function acceptance is still FAIL, as expected before the campaign.

### Task 5 baseline identical set (2026-09-17)

IDA `--list` after Task 4: **43** tool rows already `raw_equal` (41 shared nine-class names plus `-[IODeviceMaster free]` and `start`); **0** masked-only. **45** shared reloc rows already `raw_equal` or `masked_equal`. All were advanced to `assembly-matched` in the ledgers (reviewer Pat Raynor). Compiler-shaped differing rows were left unchanged.

### Task 6 omit `return self` on add-to-list (2026-09-17)

Rebuilt tool SHA `0B8B3593E3D22E53D415CA32D3109648A6331CB5064800CF3C58CEF0A34A5920` (299660). Both `-[pnpDMA addDMAToList:]` and `-[pnpIRQ addToIRQList:]` are IDA `raw_equal` / `masked_equal` on the tool. Previously identical Task 5 rows stayed matched. Unpaired count unchanged (10).

```
-[pnpDMA addDMAToList:]
  status=different raw_equal=True masked_equal=True
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  cmp dword ptr [edx+24h], 7              cmp dword ptr [edx+24h], 7
* jg loc_460D                             jg loc_6189
  mov eax, [edx+24h]                      mov eax, [edx+24h]
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov [edx+eax*4+4], ecx                  mov [edx+eax*4+4], ecx
  inc dword ptr [edx+24h]                 inc dword ptr [edx+24h]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

```
-[pnpIRQ addToIRQList:]
  status=different raw_equal=True masked_equal=True
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  cmp dword ptr [edx+44h], 0Fh            cmp dword ptr [edx+44h], 0Fh
* jg loc_42F1                             jg loc_6851
  mov eax, [edx+44h]                      mov eax, [edx+44h]
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov [edx+eax*4+4], ecx                  mov [edx+eax*4+4], ecx
  inc dword ptr [edx+44h]                 inc dword ptr [edx+44h]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `setHigh:Level:` if-shape (2026-09-17)

Inverted the outer test to `if (high)`. Apple `jz` polarity and flag offsets (`4Ah`/`48h`/`4Bh`/`49h`) now match. Leftover is register allocation (`edx`/`al` vs `eax`/`dl`). Accepted as compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `0342C57793A44AAED54A639A34BF13828476773C3E70E6495C0CF403C8440766`.

```
-[pnpIRQ setHigh:Level:]
  status=different raw_equal=False masked_equal=False
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* mov edx, [ebp+self]                     mov eax, [ebp+self]
* mov al, [ebp+arg_C]                     mov dl, [ebp+arg_C]
  cmp [ebp+arg_8], 0                      cmp [ebp+arg_8], 0
* jz loc_431C                             jz loc_6824
* test al, al                             test dl, dl
* jz loc_4314                             jz loc_681C
* mov byte ptr [edx+4Ah], 1               mov byte ptr [eax+4Ah], 1
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
* mov byte ptr [edx+48h], 1               mov byte ptr [eax+48h], 1
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
* test al, al                             test dl, dl
* jz loc_4328                             jz loc_6830
* mov byte ptr [edx+4Bh], 1               mov byte ptr [eax+4Bh], 1
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
* mov byte ptr [edx+49h], 1               mov byte ptr [eax+49h], 1
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `setDeviceName:Length:` min and zero-length test (2026-09-17)

`if (_deviceNameLength == 0)` plus signed `copyLength = 0x4f; if (copyLength > length)`. Reloc IDA `masked_equal` on both methods. Tool leftover is IDA `__src` vs `arg_8` plus jump labels; accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `B8EBBF270EB65058FBCF1DC835D0029440B63E3DE2E63DD271108323529576D0` (299680). Previously identical Task 5 rows stayed matched. Unpaired count unchanged (10).

```
-[PnPLogicalDevice setDeviceName:Length:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  cmp dword ptr [ebx+54h], 0              cmp dword ptr [ebx+54h], 0
* jnz loc_5A54                            jnz loc_4E60
  mov eax, 4Fh                            mov eax, 4Fh
  cmp eax, edx                            cmp eax, edx
* jle loc_5A33                            jle loc_4E3F
  mov eax, edx                            mov eax, edx
  mov [ebx+54h], eax                      mov [ebx+54h], eax
  push eax                                push eax
* mov ecx, [ebp+__src]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
  lea eax, [ebx+4]                        lea eax, [ebx+4]
  push eax                                push eax
  call _strncpy                           call _strncpy
  mov eax, [ebx+54h]                      mov eax, [ebx+54h]
  mov byte ptr [eax+ebx+4], 0             mov byte ptr [eax+ebx+4], 0
  mov eax, 1                              mov eax, 1
* jmp loc_5A56                            jmp loc_4E62
  xor eax, eax                            xor eax, eax
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

```
-[PnPDeviceResources setDeviceName:Length:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  cmp dword ptr [ebx+58h], 0              cmp dword ptr [ebx+58h], 0
* jnz loc_5B58                            jnz loc_40AC
  mov eax, 4Fh                            mov eax, 4Fh
  cmp eax, edx                            cmp eax, edx
* jle loc_5B37                            jle loc_408B
  mov eax, edx                            mov eax, edx
  mov [ebx+58h], eax                      mov [ebx+58h], eax
  push eax                                push eax
* mov ecx, [ebp+__src]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
  lea eax, [ebx+8]                        lea eax, [ebx+8]
  push eax                                push eax
  call _strncpy                           call _strncpy
  mov eax, [ebx+58h]                      mov eax, [ebx+58h]
  mov byte ptr [eax+ebx+8], 0             mov byte ptr [eax+ebx+8], 0
  mov eax, 1                              mov eax, 1
* jmp loc_5B5A                            jmp loc_40AE
  xor eax, eax                            xor eax, eax
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `createMachPort:objectNumber:` return MIG result (2026-09-17)

Return `_IOCreateMachPort(...)` instead of `self`. The printed mnemonic stream now matches; leftover is call-site PIC (`calls differ`). Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `F5EED1197BF4A7E578676F26F0D51C0047886D1B698AB94B1087A17EE7B0752B`. Previously identical rows stayed matched. Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
-[IODeviceMaster createMachPort:objectNumber:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOCreateMachPort                 call __IOCreateMachPort
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 nested `[[list] addObject:]` (2026-09-17)

Dropped the `List *list` temporary on `addIRQ:`/`addDMA:`/`addIOPort:`/`addMemory:`. Reloc IDA `masked_equal` on all four. Tool leftover is PIC selector displacements (`paList_0` vs `paList_1` and immediate offsets). Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `613D8ED01BF4B7A5CAB0C7085A88E61ED7070ED43D102D5B6A1E39D21DD15C3C` (299424). Previously identical rows stayed matched. Unpaired count unchanged (10). `addIOPort:`/`addIRQ:`/`addMemory:` match `addDMA:` aside from the ivar offset.

```
-[PnPResources addDMA:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  call $+5                                call $+5
  pop edx                                 pop edx
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
  mov ecx, edx                            mov ecx, edx
* mov ecx, [ecx+697Ch]                    mov ecx, [ecx+4B0Ch]
  push ecx                                push ecx
* mov edx, ds:(paList_0 - 5724h)[edx]     mov edx, ds:(paList_1 - 5538h)[edx]
  push edx                                push edx
  mov eax, [eax+8]                        mov eax, [eax+8]
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `deviceWithID:` loop polarity (2026-09-17)

`if (device)` plus `if (ID != id) continue; return device`. Apple `jz` on nil now matches. Leftover is the inverted ID-compare jump (`jnz` continue vs `jz` return; equivalent CFG). Accepted compiler-shaped leftover on both (reviewer Pat Raynor). Tool SHA `E93BDF316FA5E6A2ECD4430426E94564D8DEA990BCCADF9D2EC0A9544969CF24` (299424). Previously identical rows stayed matched. Unpaired count unchanged (10).

```
-[PnPDeviceResources deviceWithID:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop edi                                 pop edi
  xor esi, esi                            xor esi, esi
  nop                                     nop
  nop                                     nop
  push esi                                push esi
  mov edx, edi                            mov edx, edi
* mov edx, [edx+5641h]                    mov edx, [edx+600Dh]
  push edx                                push edx
  mov ecx, [ebp+self]                     mov ecx, [ebp+self]
  mov ecx, [ecx+4]                        mov ecx, [ecx+4]
  push ecx                                push ecx
  call _objc_msgSend                      call _objc_msgSend
  mov ebx, eax                            mov ebx, eax
  add esp, 0Ch                            add esp, 0Ch
  test ebx, ebx                           test ebx, ebx
* jz loc_6A40                             jz loc_4064
  mov edx, edi                            mov edx, edi
* mov edx, [edx+56B9h]                    mov edx, [edx+5FFDh]
  push edx                                push edx
  push ebx                                push ebx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  cmp [ebp+arg_8], eax                    cmp [ebp+arg_8], eax
* jnz loc_6A3C                            jz loc_4060
*                                         inc esi
*                                         jmp loc_4024
  mov eax, ebx                            mov eax, ebx
* jmp loc_6A42                            jmp loc_4066
* inc esi
* jmp loc_6A00
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `deviceWithID:` loop polarity (2026-09-17)

`if (device)` plus `if (ID != id) continue; return device`. Apple `jz` on nil now matches. Leftover is the inverted ID-compare jump (`jnz` continue vs `jz` return; equivalent CFG). Accepted compiler-shaped leftover on both (reviewer Pat Raynor). Tool SHA `E93BDF316FA5E6A2ECD4430426E94564D8DEA990BCCADF9D2EC0A9544969CF24` (299424). Previously identical rows stayed matched. Unpaired count unchanged (10).

```
-[PnPDeviceResources deviceWithID:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop edi                                 pop edi
  xor esi, esi                            xor esi, esi
  nop                                     nop
  nop                                     nop
  push esi                                push esi
  mov edx, edi                            mov edx, edi
* mov edx, [edx+5641h]                    mov edx, [edx+600Dh]
  push edx                                push edx
  mov ecx, [ebp+self]                     mov ecx, [ebp+self]
  mov ecx, [ecx+4]                        mov ecx, [ecx+4]
  push ecx                                push ecx
  call _objc_msgSend                      call _objc_msgSend
  mov ebx, eax                            mov ebx, eax
  add esp, 0Ch                            add esp, 0Ch
  test ebx, ebx                           test ebx, ebx
* jz loc_6A40                             jz loc_4064
  mov edx, edi                            mov edx, edi
* mov edx, [edx+56B9h]                    mov edx, [edx+5FFDh]
  push edx                                push edx
  push ebx                                push ebx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  cmp [ebp+arg_8], eax                    cmp [ebp+arg_8], eax
* jnz loc_6A3C                            jz loc_4060
*                                         inc esi
*                                         jmp loc_4024
  mov eax, ebx                            mov eax, ebx
* jmp loc_6A42                            jmp loc_4066
* inc esi
* jmp loc_6A00
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 accept remaining empty-list leftovers (2026-09-17)

Accepted every remaining worklist `none` hand-written row as `intentional-mismatch` (reviewer Pat Raynor). CRT/dyld/libc glue was not added to the PnPDump ledger. Untried source-shaped experiments were not opened. Tool SHA `E93BDF316FA5E6A2ECD4430426E94564D8DEA990BCCADF9D2EC0A9544969CF24`. Dumps are current published IDA `--name`.

#### `-[IODeviceMaster getCharValues:forParameter:objectNumber:count:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[IODeviceMaster getCharValues:forParameter:objectNumber:count:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  mov eax, [ebp+arg_14]                   mov eax, [ebp+arg_14]
  push eax                                push eax
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
  mov eax, [eax]                          mov eax, [eax]
  push eax                                push eax
  mov ecx, [ebp+arg_C]                    mov ecx, [ebp+arg_C]
  push ecx                                push ecx
  mov ecx, [ebp+arg_10]                   mov ecx, [ebp+arg_10]
  push ecx                                push ecx
  mov edx, [edx+4]                        mov edx, [edx+4]
  push edx                                push edx
  call __IOGetCharValues                  call __IOGetCharValues
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[IODeviceMaster getIntValues:forParameter:objectNumber:count:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[IODeviceMaster getIntValues:forParameter:objectNumber:count:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  mov eax, [ebp+arg_14]                   mov eax, [ebp+arg_14]
  push eax                                push eax
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
  mov eax, [eax]                          mov eax, [eax]
  push eax                                push eax
  mov ecx, [ebp+arg_C]                    mov ecx, [ebp+arg_C]
  push ecx                                push ecx
  mov ecx, [ebp+arg_10]                   mov ecx, [ebp+arg_10]
  push ecx                                push ecx
  mov edx, [edx+4]                        mov edx, [edx+4]
  push edx                                push edx
  call __IOGetIntValues                   call __IOGetIntValues
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[IODeviceMaster lookUpByDeviceName:objectNumber:deviceKind:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[IODeviceMaster lookUpByDeviceName:objectNumber:deviceKind:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOLookupByDeviceName             call __IOLookupByDeviceName
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[IODeviceMaster lookUpByObjectNumber:deviceKind:deviceName:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[IODeviceMaster lookUpByObjectNumber:deviceKind:deviceName:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOLookupByObjectNumber           call __IOLookupByObjectNumber
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[IODeviceMaster setCharValues:forParameter:objectNumber:count:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[IODeviceMaster setCharValues:forParameter:objectNumber:count:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_14]                   mov edx, [ebp+arg_14]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOSetCharValues                  call __IOSetCharValues
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[IODeviceMaster setIntValues:forParameter:objectNumber:count:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[IODeviceMaster setIntValues:forParameter:objectNumber:count:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_14]                   mov edx, [ebp+arg_14]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_10]                   mov edx, [ebp+arg_10]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call __IOSetIntValues                   call __IOSetIntValues
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_IOExitThread`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_IOExitThread
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push 0FFFFFFFFh                         push 0FFFFFFFFh
  call _cthread_exit                      call _cthread_exit
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_IOForkThread`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_IOForkThread
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+arg_4]                    mov edx, [ebp+arg_4]
  push edx                                push edx
  mov edx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
  push edx                                push edx
  call _cthread_fork                      call _cthread_fork
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_IOFree`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_IOFree
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+arg_0]                    mov eax, [ebp+arg_0]
  push eax                                push eax
  call _free                              call _free
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_IOMalloc`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_IOMalloc
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+__size]                   mov edx, [ebp+__size]
  push edx                                push edx
  call _malloc                            call _malloc
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_IOResumeThread`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_IOResumeThread
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+arg_0]                    mov eax, [ebp+arg_0]
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call _thread_resume                     call _thread_resume
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_IOSuspendThread`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_IOSuspendThread
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+arg_0]                    mov eax, [ebp+arg_0]
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call _thread_suspend                    call _thread_suspend
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `+[PnPDeviceResources setReadPort:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
+[PnPDeviceResources setReadPort:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  call $+5                                call $+5
  pop eax                                 pop eax
  mov dx, [ebp+arg_8]                     mov dx, [ebp+arg_8]
* mov ds:(_readPort - 5B0Ch)[eax], dx     mov ds:(_readPort - 3C84h)[eax], dx
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPDeviceResources deviceCount]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPDeviceResources deviceCount]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  call $+5                                call $+5
  pop edx                                 pop edx
  mov eax, [ebp+self]                     mov eax, [ebp+self]
* mov edx, ds:(off_C044 - 69D8h)[edx]     mov edx, ds:(paCount_0 - 3FECh)[edx]
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPLogicalDevice addCompatID:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPLogicalDevice addCompatID:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  call $+5                                call $+5
  pop edx                                 pop edx
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
* mov edx, ds:(off_C0A0 - 5A78h)[edx]     mov edx, ds:(paAddobject - 4E94h)[edx]
  push edx                                push edx
  mov eax, [eax+5Ch]                      mov eax, [eax+5Ch]
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_IOLog`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_IOLog
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 12Ch                           sub esp, 12Ch
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  lea eax, [ebp+arg_4]                    lea eax, [ebp+arg_4]
  push eax                                push eax
  mov edx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
  push edx                                push edx
  lea ebx, [ebp+var_12C]                  lea ebx, [ebp+var_12C]
  push ebx                                push ebx
  call _vsprintf                          call _vsprintf
  push ebx                                push ebx
* lea eax, (aS_0 - 7080h)[esi]            lea eax, (aS - 35B4h)[esi]
  push eax                                push eax
  push 3                                  push 3
  call _syslog                            call _syslog
  lea esp, [ebp-134h]                     lea esp, [ebp-134h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `+[PnPDeviceResources setVerbose:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
+[PnPDeviceResources setVerbose:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  call $+5                                call $+5
  pop eax                                 pop eax
*                                         mov eax, ds:(_verbose_ptr - 3C9Ch)[eax]
  mov dl, [ebp+arg_8]                     mov dl, [ebp+arg_8]
* mov ds:(_verbose - 66C8h)[eax], dl      mov byte ptr ds:(loc_3C9C - 3C9Ch)[eax], dl
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[NXLock unlock]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[NXLock unlock]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push esi                                push esi
  push ebx                                push ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov ebx, [esi+4]                        mov ebx, [esi+4]
  push ebx                                push ebx
  call _mutex_try_lock                    call _mutex_try_lock
  add esp, 4                              add esp, 4
  test eax, eax                           test eax, eax
* jnz loc_9025                            jnz loc_355D
  push ebx                                push ebx
  call _mutex_wait_lock                   call _mutex_wait_lock
  add esp, 4                              add esp, 4
  mov byte ptr [ebx+18h], 0               mov byte ptr [ebx+18h], 0
  cmp dword ptr [ebx+0Ch], 0              cmp dword ptr [ebx+0Ch], 0
* jz loc_9038                             jz loc_3570
  lea eax, [ebx+8]                        lea eax, [ebx+8]
  push eax                                push eax
  call _cond_signal                       call _cond_signal
  mov dword ptr [ebx], 0                  mov dword ptr [ebx], 0
  mov eax, esi                            mov eax, esi
  lea esp, [ebp-8]                        lea esp, [ebp-8]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpIOPort initWithBase:Length:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[pnpIOPort initWithBase:Length:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop eax                                 pop eax
  mov edi, [ebp+self]                     mov edi, [ebp+self]
  mov bx, [ebp+arg_8]                     mov bx, [ebp+arg_8]
  mov si, [ebp+arg_C]                     mov si, [ebp+arg_C]
  mov edx, eax                            mov edx, eax
* mov edx, [edx+796Eh]                    mov edx, [edx+3B3Ah]
  push edx                                push edx
  mov [ebp+var_8.receiver], edi           mov [ebp+var_8.receiver], edi
* mov eax, ds:(stru_C20C.super_class - 46EAh)[eax]  mov eax, ds:(stru_A234.super_class - 64CAh)[eax]
  mov [ebp+var_8.super_class], eax        mov [ebp+var_8.super_class], eax
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  mov [edi+6], bx                         mov [edi+6], bx
  mov [edi+4], bx                         mov [edi+4], bx
  mov [edi+0Ah], si                       mov [edi+0Ah], si
  mov eax, edi                            mov eax, edi
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpMemory initWithBase:Length:Bit16:Bit32:HighAddr:Is32:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[pnpMemory initWithBase:Length:Bit16:Bit32:HighAddr:Is32:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 14h                            sub esp, 14h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop eax                                 pop eax
  mov edi, [ebp+self]                     mov edi, [ebp+self]
  mov esi, [ebp+arg_C]                    mov esi, [ebp+arg_C]
  mov bl, [ebp+arg_10]                    mov bl, [ebp+arg_10]
  mov dl, [ebp+arg_14]                    mov dl, [ebp+arg_14]
  mov [ebp+var_C], dl                     mov [ebp+var_C], dl
  mov dl, [ebp+arg_18]                    mov dl, [ebp+arg_18]
  mov [ebp+var_10], dl                    mov [ebp+var_10], dl
  mov dl, [ebp+arg_1C]                    mov dl, [ebp+arg_1C]
  mov [ebp+var_14], dl                    mov [ebp+var_14], dl
  mov edx, eax                            mov edx, eax
* mov edx, [edx+7536h]                    mov edx, [edx+348Ah]
  push edx                                push edx
  mov [ebp+var_8.receiver], edi           mov [ebp+var_8.receiver], edi
* mov eax, ds:(stru_C1BC.ext - 4B22h)[eax]  mov eax, ds:(off_A288 - 6B7Ah)[eax]
  mov [ebp+var_8.super_class], eax        mov [ebp+var_8.super_class], eax
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  mov [edi+8], edx                        mov [edi+8], edx
  mov [edi+4], edx                        mov [edi+4], edx
  mov [edi+10h], esi                      mov [edi+10h], esi
  test bl, bl                             test bl, bl
  setz al                                 setz al
  mov [edi+19h], al                       mov [edi+19h], al
  mov [edi+1Ah], bl                       mov [edi+1Ah], bl
  mov dl, [ebp+var_C]                     mov dl, [ebp+var_C]
  mov [edi+1Bh], dl                       mov [edi+1Bh], dl
  mov dl, [ebp+var_14]                    mov dl, [ebp+var_14]
  mov [edi+1Ch], dl                       mov [edi+1Ch], dl
  mov dl, [ebp+var_10]                    mov dl, [ebp+var_10]
  mov [edi+16h], dl                       mov [edi+16h], dl
  mov eax, edi                            mov eax, edi
  lea esp, [ebp-20h]                      lea esp, [ebp-20h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_IOPanic`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_IOPanic
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
  mov edx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
  push edx                                push edx
  call _IOLog                             call _IOLog
* lea eax, (aWaitingForDebu - 70B9h)[ebx]  lea eax, (aWaitingForDebu - 3961h)[ebx]
  push eax                                push eax
  call _IOLog                             call _IOLog
  nop                                     nop
* jmp loc_70D0                            jmp loc_3978
```

#### `-[NXLock lock]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[NXLock lock]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov edi, [ebp+self]                     mov edi, [ebp+self]
  mov ebx, [edi+4]                        mov ebx, [edi+4]
  push ebx                                push ebx
  call _mutex_try_lock                    call _mutex_try_lock
  add esp, 4                              add esp, 4
  test eax, eax                           test eax, eax
* jnz loc_8FD2                            jnz loc_350A
  push ebx                                push ebx
  call _mutex_wait_lock                   call _mutex_wait_lock
  add esp, 4                              add esp, 4
  cmp byte ptr [ebx+18h], 0               cmp byte ptr [ebx+18h], 0
* jz loc_8FEC                             jz loc_3524
  lea esi, [ebx+8]                        lea esi, [ebx+8]
  nop                                     nop
  push ebx                                push ebx
  push esi                                push esi
  call _condition_wait                    call _condition_wait
  add esp, 8                              add esp, 8
  cmp byte ptr [ebx+18h], 0               cmp byte ptr [ebx+18h], 0
* jnz loc_8FDC                            jnz loc_3514
  mov byte ptr [ebx+18h], 1               mov byte ptr [ebx+18h], 1
  mov dword ptr [ebx], 0                  mov dword ptr [ebx], 0
  mov eax, edi                            mov eax, edi
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_bail`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_bail
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: function range bytes differ
  reason: instruction references differ
  reason: instruction semantics differ

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  call $+5                                call $+5
  pop edx                                 pop edx
  mov ecx, [ebp+arg_4]                    mov ecx, [ebp+arg_4]
  push ecx                                push ecx
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  push ecx                                push ecx
  mov ecx, edx                            mov ecx, edx
* mov ecx, [ecx+6DECh]                    mov ecx, [ecx+5290h]
  push ecx                                push ecx
* lea eax, (aSSD - 3D44h)[edx]            lea eax, (aSSD - 2E94h)[edx]
  push eax                                push eax
  mov eax, edx                            mov eax, edx
* mov eax, [eax+639Ch]                    mov eax, [eax+5224h]
  add eax, 0B0h                           add eax, 0B0h
  push eax                                push eax
  call _fprintf                           call _fprintf
  push 1                                  push 1
  call _exit                              call _exit
```

#### `-[NXLock free]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[NXLock free]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  mov edi, [ebp+self]                     mov edi, [ebp+self]
  mov ebx, [edi+4]                        mov ebx, [edi+4]
  cmp dword ptr [ebx+0Ch], 0              cmp dword ptr [ebx+0Ch], 0
* jz loc_8F73                             jz loc_34AF
  lea eax, [ebx+8]                        lea eax, [ebx+8]
  push eax                                push eax
  call _cond_broadcast                    call _cond_broadcast
  add esp, 4                              add esp, 4
  lea eax, [ebx+8]                        lea eax, [ebx+8]
  push eax                                push eax
  call _spin_lock                         call _spin_lock
* add esp, 4
  push ebx                                push ebx
  call _free                              call _free
  mov edx, esi                            mov edx, esi
* mov edx, [edx+30EEh]                    mov edx, [edx+6B72h]
  push edx                                push edx
  mov [ebp+var_8.receiver], edi           mov [ebp+var_8.receiver], edi
* mov esi, ds:(off_C2B0 - 8F5Ah)[esi]     mov esi, ds:(stru_A0F4.ext - 3496h)[esi]
  mov [ebp+var_8.super_class], esi        mov [ebp+var_8.super_class], esi
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `_IOCopyMemory`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
_IOCopyMemory
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+arg_C]                    mov eax, [ebp+arg_C]
  push eax                                push eax
* mov eax, [ebp+arg_8]                    mov eax, [ebp+__n]
  push eax                                push eax
* mov eax, [ebp+arg_4]                    mov eax, [ebp+__src]
  push eax                                push eax
* mov eax, [ebp+arg_0]                    mov eax, [ebp+__dst]
  push eax                                push eax
* call __IOCopyMemory                     call ___IOCopyMemory
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResources free]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPResources free]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, esi                            mov edx, esi
* mov edx, [edx+6A1Bh]                    mov edx, [edx+4BC7h]
  push edx                                push edx
  mov edx, [ebx+4]                        mov edx, [ebx+4]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov edx, esi                            mov edx, esi
* mov edx, [edx+6A1Bh]                    mov edx, [edx+4BC7h]
  push edx                                push edx
  mov edx, [ebx+8]                        mov edx, [ebx+8]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov edx, esi                            mov edx, esi
* mov edx, [edx+6A1Bh]                    mov edx, [edx+4BC7h]
  push edx                                push edx
  mov edx, [ebx+0Ch]                      mov edx, [ebx+0Ch]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov edx, esi                            mov edx, esi
* mov edx, [edx+6A1Bh]                    mov edx, [edx+4BC7h]
  push edx                                push edx
  mov edx, [ebx+10h]                      mov edx, [ebx+10h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 20h                            add esp, 20h
  mov edx, esi                            mov edx, esi
* mov edx, [edx+6A1Bh]                    mov edx, [edx+4BC7h]
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov esi, ds:(stru_C16C.ext - 562Dh)[esi]  mov esi, ds:(stru_A1E4.super_class - 5441h)[esi]
  mov [ebp+var_8.super_class], esi        mov [ebp+var_8.super_class], esi
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResource free]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPResource free]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, esi                            mov edx, esi
* mov edx, [edx+71A3h]                    mov edx, [edx+4E9Fh]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+71D3h]                    mov edx, [edx+4E9Fh]
*                                         push edx
*                                         mov edx, esi
*                                         mov edx, [edx+4EBBh]
  push edx                                push edx
  mov edx, [ebx+4]                        mov edx, [ebx+4]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8                              add esp, 0Ch
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov edx, esi                            mov edx, esi
* mov edx, [edx+71A3h]                    mov edx, [edx+4E9Fh]
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov esi, ds:(stru_C1BC.super_class - 4EA5h)[esi]  mov esi, ds:(stru_A194.ext - 5169h)[esi]
  mov [ebp+var_8.super_class], esi        mov [ebp+var_8.super_class], esi
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResource init]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPResource init]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+723Fh]                    mov edx, [edx+4F27h]
  push edx                                push edx
  mov [ebp+var_8.receiver], esi           mov [ebp+var_8.receiver], esi
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+73A7h]                    mov edx, [edx+50E3h]
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+723Fh]                    mov edx, [edx+4F27h]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+7217h]                    mov edx, [edx+4F23h]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+72DFh]                    mov edx, [edx+4FF3h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov [esi+4], eax                        mov [esi+4], eax
  mov dword ptr [esi+8], 0                mov dword ptr [esi+8], 0
  add esp, 10h                            add esp, 10h
  cmp dword ptr [esi+4], 0                cmp dword ptr [esi+4], 0
* jz loc_4E80                             jz loc_5144
  mov eax, esi                            mov eax, esi
* jmp loc_4E8D                            jmp loc_5151
* mov ebx, ds:(off_C048 - 4E19h)[ebx]     mov ebx, ds:(paFree_0 - 50DDh)[ebx]
  push ebx                                push ebx
  push esi                                push esi
  call _objc_msgSend                      call _objc_msgSend
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPDeviceResources free]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPDeviceResources free]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  cmp dword ptr [esi+4], 0                cmp dword ptr [esi+4], 0
* jz loc_6996                             jz loc_3F6B
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+56E3h]                    mov edx, [edx+60D7h]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+5713h]                    mov edx, [edx+60D7h]
*                                         push edx
*                                         mov edx, ebx
*                                         mov edx, [edx+60F3h]
  push edx                                push edx
  mov edx, [esi+4]                        mov edx, [esi+4]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8                              add esp, 0Ch
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+56E3h]                    mov edx, [edx+60D7h]
  push edx                                push edx
  mov [ebp+var_8.receiver], esi           mov [ebp+var_8.receiver], esi
* mov ebx, ds:(stru_C11C.super_class - 6965h)[ebx]  mov ebx, ds:(stru_A144.ext - 3F31h)[ebx]
  mov [ebp+var_8.super_class], ebx        mov [ebp+var_8.super_class], ebx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPLogicalDevice free]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPLogicalDevice free]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, esi                            mov edx, esi
* mov edx, [edx+66A3h]                    mov edx, [edx+52C3h]
  push edx                                push edx
  mov edx, [ebx+60h]                      mov edx, [ebx+60h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov edx, esi                            mov edx, esi
* mov edx, [edx+66A3h]                    mov edx, [edx+52C3h]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+66D3h]                    mov edx, [edx+52C3h]
*                                         push edx
*                                         mov edx, esi
*                                         mov edx, [edx+52DFh]
  push edx                                push edx
  mov edx, [ebx+64h]                      mov edx, [ebx+64h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8                              add esp, 0Ch
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov edx, esi                            mov edx, esi
* mov edx, [edx+66A3h]                    mov edx, [edx+52C3h]
  push edx                                push edx
  mov edx, [ebx+5Ch]                      mov edx, [ebx+5Ch]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov edx, esi                            mov edx, esi
* mov edx, [edx+66A3h]                    mov edx, [edx+52C3h]
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov esi, ds:(stru_C11C.ext - 59A5h)[esi]  mov esi, ds:(stru_A194.super_class - 4D45h)[esi]
  mov [ebp+var_8.super_class], esi        mov [ebp+var_8.super_class], esi
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPLogicalDevice init]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPLogicalDevice init]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6773h]                    mov edx, [edx+537Fh]
  push edx                                push edx
  mov [ebp+var_8.receiver], esi           mov [ebp+var_8.receiver], esi
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6863h]                    mov edx, [edx+5513h]
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6773h]                    mov edx, [edx+537Fh]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+674Bh]                    mov edx, [edx+537Bh]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+680Fh]                    mov edx, [edx+5467h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov [esi+60h], eax                      mov [esi+60h], eax
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6773h]                    mov edx, [edx+537Fh]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+674Bh]                    mov edx, [edx+537Bh]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6813h]                    mov edx, [edx+544Bh]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov [esi+64h], eax                      mov [esi+64h], eax
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6773h]                    mov edx, [edx+537Fh]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+674Bh]                    mov edx, [edx+537Bh]
  push edx                                push edx
* mov ebx, ds:(paList - 58E5h)[ebx]       mov ebx, ds:(paList - 4C85h)[ebx]
  push ebx                                push ebx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov [esi+5Ch], eax                      mov [esi+5Ch], eax
  mov eax, esi                            mov eax, esi
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpIOPort print]`

Accepted `intentional-mismatch` (dual-bar forbids swapping: Apple tool uses _printf, reloc both use _IOLog).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[pnpIOPort print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
*                                         push ebx
  call $+5                                call $+5
* pop ecx                                 pop edx
* mov edx, [ebp+self]                     mov ebx, [ebp+self]
* movzx eax, byte ptr [edx+0Ch]           movzx eax, byte ptr [ebx+0Ch]
  push eax                                push eax
* movzx eax, word ptr [edx+0Ah]           movzx eax, word ptr [ebx+0Ah]
  push eax                                push eax
* movzx eax, word ptr [edx+8]             movzx eax, word ptr [ebx+8]
  push eax                                push eax
* movzx eax, word ptr [edx+6]             movzx eax, word ptr [ebx+6]
  push eax                                push eax
* movzx eax, word ptr [edx+4]             movzx eax, word ptr [ebx+4]
  push eax                                push eax
* lea eax, (aIOPort0xX0xXAl - 463Ch)[ecx]  lea eax, (aIOPort0xX0xXAl - 65D9h)[edx]
  push eax                                push eax
* call _printf                            call _IOLog
*                                         mov eax, ebx
*                                         mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPDeviceResources initForBufNoHeader:Length:CSN:]`

Accepted `intentional-mismatch` (dual-bar forbids swapping: Apple tool uses _printf, reloc both use _IOLog).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPDeviceResources initForBufNoHeader:Length:CSN:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  mov edi, [ebp+self]                     mov edi, [ebp+self]
  mov ebx, [ebp+arg_10]                   mov ebx, [ebp+arg_10]
  mov edx, esi                            mov edx, esi
* mov edx, [edx+57B6h]                    mov edx, [edx+6186h]
  push edx                                push edx
  mov [ebp+var_8.receiver], edi           mov [ebp+var_8.receiver], edi
  mov edx, esi                            mov edx, esi
* mov edx, [edx+587Eh]                    mov edx, [edx+62F2h]
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  mov [edi+64h], ebx                      mov [edi+64h], ebx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+57B6h]                    mov edx, [edx+6186h]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+578Eh]                    mov edx, [edx+6182h]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+5856h]                    mov edx, [edx+6252h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov [edi+4], eax                        mov [edi+4], eax
  add esp, 10h                            add esp, 10h
  test eax, eax                           test eax, eax
* jz loc_6924                             jz loc_3F00
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+583Eh]                    mov edx, [edx+61A2h]
  push edx                                push edx
  push edi                                push edi
  call _objc_msgSend                      call _objc_msgSend
  add esp, 10h                            add esp, 10h
* test al, al                             test eax, eax
* jz loc_6930                             jz loc_3F0C
  mov eax, edi                            mov eax, edi
* jmp loc_693D                            jmp loc_3F19
* lea eax, (aPnpdeviceresou_13 - 68A2h)[esi]  lea eax, (aPnpdeviceresou_1 - 3E7Eh)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
* mov esi, ds:(off_C048 - 68A2h)[esi]     mov esi, ds:(paFree_0 - 3E7Eh)[esi]
  push esi                                push esi
  push edi                                push edi
  call _objc_msgSend                      call _objc_msgSend
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResources init]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPResources init]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6FFFh]                    mov edx, [edx+4CDBh]
  push edx                                push edx
  mov [ebp+var_8.receiver], esi           mov [ebp+var_8.receiver], esi
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+713Fh]                    mov edx, [edx+4EBFh]
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6FFFh]                    mov edx, [edx+4CDBh]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6FD7h]                    mov edx, [edx+4CD7h]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+70A3h]                    mov edx, [edx+4DC7h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov [esi+4], eax                        mov [esi+4], eax
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6FFFh]                    mov edx, [edx+4CDBh]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6FD7h]                    mov edx, [edx+4CD7h]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+70A3h]                    mov edx, [edx+4DC7h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov [esi+8], eax                        mov [esi+8], eax
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6FFFh]                    mov edx, [edx+4CDBh]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6FD7h]                    mov edx, [edx+4CD7h]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+70A3h]                    mov edx, [edx+4DC7h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov [esi+0Ch], eax                      mov [esi+0Ch], eax
  add esp, 20h                            add esp, 20h
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6FFFh]                    mov edx, [edx+4CDBh]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+6FD7h]                    mov edx, [edx+4CD7h]
  push edx                                push edx
  mov edx, ebx                            mov edx, ebx
* mov edx, [edx+70A3h]                    mov edx, [edx+4DC7h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  mov [esi+10h], eax                      mov [esi+10h], eax
  add esp, 8                              add esp, 8
  cmp dword ptr [esi+4], 0                cmp dword ptr [esi+4], 0
* jz loc_5149                             jz loc_5419
  cmp dword ptr [esi+8], 0                cmp dword ptr [esi+8], 0
* jz loc_5149                             jz loc_5419
  cmp dword ptr [esi+0Ch], 0              cmp dword ptr [esi+0Ch], 0
* jz loc_5149                             jz loc_5419
  test eax, eax                           test eax, eax
* jnz loc_5158                            jnz loc_5428
* mov ebx, ds:(off_C048 - 5059h)[ebx]     mov ebx, ds:(paFree_0 - 5329h)[ebx]
  push ebx                                push ebx
  push esi                                push esi
  call _objc_msgSend                      call _objc_msgSend
* jmp loc_515A                            jmp loc_542A
  mov eax, esi                            mov eax, esi
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResources print]`

Accepted `intentional-mismatch` (dual-bar forbids swapping: Apple tool uses _printf, reloc both use _IOLog).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[PnPResources print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 24h                            sub esp, 14h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop edi                                 pop edi
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [eax+0Ch]                      mov edx, [eax+0Ch]
* mov [ebp+var_20], edx                   mov [ebp+var_10], edx
  mov edx, [eax+4]                        mov edx, [eax+4]
* mov [ebp+var_1C], edx                   mov [ebp+var_C], edx
  mov edx, [eax+10h]                      mov edx, [eax+10h]
* mov [ebp+var_18], edx                   mov [ebp+var_8], edx
  mov eax, [eax+8]                        mov eax, [eax+8]
* mov [ebp+var_14], eax                   mov [ebp+var_4], eax
* mov edx, [ebp+var_20]
* mov [ebp+var_10], edx
* mov edx, [ebp+var_1C]
* mov [ebp+var_C], edx
* mov edx, [ebp+var_18]
* mov [ebp+var_8], edx
* mov edx, [ebp+var_14]
* mov [ebp+var_4], edx
  xor esi, esi                            xor esi, esi
  mov edx, edi                            mov edx, edi
* mov edx, [edx+70B2h]                    mov edx, [edx+407Eh]
  push edx                                push edx
  mov edx, [ebp+esi*4+var_10]             mov edx, [ebp+esi*4+var_10]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* mov [ebp+var_24], eax                   mov [ebp+var_14], eax
  xor ebx, ebx                            xor ebx, ebx
  add esp, 8                              add esp, 8
* nop
  push ebx                                push ebx
  mov edx, edi                            mov edx, edi
* mov edx, [edx+7082h]                    mov edx, [edx+402Ah]
  push edx                                push edx
* mov edx, [ebp+var_24]                   mov edx, [ebp+var_14]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 0Ch                            add esp, 0Ch
  test eax, eax                           test eax, eax
* jz loc_503C                             jz loc_6068
  mov edx, edi                            mov edx, edi
* mov edx, [edx+70A2h]                    mov edx, [edx+40B2h]
  push edx                                push edx
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8
  inc ebx                                 inc ebx
* jmp loc_500C                            jmp loc_6038
  inc esi                                 inc esi
  cmp esi, 3                              cmp esi, 3
* jle loc_4FF0                            jle loc_6020
* lea esp, [ebp-30h]                      lea esp, [ebp-20h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpIRQ print]`

Accepted `intentional-mismatch` (dual-bar forbids swapping: Apple tool uses _printf, reloc both use _IOLog).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[pnpIRQ print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  mov edi, [ebp+self]                     mov edi, [ebp+self]
  mov [ebp+var_4], 1                      mov [ebp+var_4], 1
* lea eax, (aIrq - 40BEh)[esi]            lea eax, (aIrq - 6866h)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
  xor ebx, ebx                            xor ebx, ebx
  add esp, 4                              add esp, 4
  cmp [edi+44h], ebx                      cmp [edi+44h], ebx
* jle loc_4119                            jle loc_68C2
* lea edx, (aSD_0 - 40BEh)[esi]           lea edx, (aSD_0 - 6866h)[esi]
  mov [ebp+var_8], edx                    mov [ebp+var_8], edx
  nop                                     nop
  nop                                     nop
  nop                                     nop
*                                         cmp [ebp+var_4], 0
*                                         jz loc_68A0
*                                         lea eax, (unk_7103 - 6866h)[esi]
*                                         jmp loc_68A6
*                                         lea eax, (asc_7A10 - 6866h)[esi]
  mov edx, [edi+ebx*4+4]                  mov edx, [edi+ebx*4+4]
  push edx                                push edx
* cmp [ebp+var_4], 0
* jz loc_40FC
* lea eax, (unk_9145 - 40BEh)[esi]
* jmp loc_4102
* lea eax, (asc_94E3 - 40BEh)[esi]
  push eax                                push eax
  mov edx, [ebp+var_8]                    mov edx, [ebp+var_8]
  push edx                                push edx
* call _printf                            call _IOLog
  mov [ebp+var_4], 0                      mov [ebp+var_4], 0
  add esp, 0Ch                            add esp, 0Ch
  inc ebx                                 inc ebx
  cmp [edi+44h], ebx                      cmp [edi+44h], ebx
* jg loc_40E8                             jg loc_6890
  cmp byte ptr [edi+48h], 0               cmp byte ptr [edi+48h], 0
* jz loc_412E                             jz loc_68D7
* lea eax, (aHighEdge - 40BEh)[esi]       lea eax, (aHighEdge - 6866h)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [edi+49h], 0               cmp byte ptr [edi+49h], 0
* jz loc_4143                             jz loc_68EC
* lea eax, (aLowEdge - 40BEh)[esi]        lea eax, (aLowEdge - 6866h)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [edi+4Ah], 0               cmp byte ptr [edi+4Ah], 0
* jz loc_4158                             jz loc_6901
* lea eax, (aHighLevel - 40BEh)[esi]      lea eax, (aHighLevel - 6866h)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [edi+4Bh], 0               cmp byte ptr [edi+4Bh], 0
* jz loc_416D                             jz loc_6916
* lea eax, (aLowLevel - 40BEh)[esi]       lea eax, (aLowLevel - 6866h)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
* lea eax, (asc_93D3 - 40BEh)[esi]        lea eax, (asc_7261 - 6866h)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
*                                         mov eax, edi
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpMemory print]`

Accepted `intentional-mismatch` (dual-bar forbids swapping: Apple tool uses _printf, reloc both use _IOLog).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[pnpMemory print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
*                                         cmp byte ptr [esi+1Ch], 0
*                                         jz loc_6DA0
*                                         lea eax, (a32 - 6D8Eh)[ebx]
*                                         jmp loc_6DA6
*                                         lea eax, (a24 - 6D8Eh)[ebx]
  mov edx, [esi+10h]                      mov edx, [esi+10h]
  push edx                                push edx
  mov edx, [esi+0Ch]                      mov edx, [esi+0Ch]
  push edx                                push edx
  mov edx, [esi+8]                        mov edx, [esi+8]
  push edx                                push edx
  mov edx, [esi+4]                        mov edx, [esi+4]
  push edx                                push edx
* cmp byte ptr [esi+1Ch], 0
* jz loc_48CC
* lea eax, (a32 - 48AAh)[ebx]
* jmp loc_48D2
* lea eax, (a24 - 48AAh)[ebx]
  push eax                                push eax
* lea eax, (aMemS0xLx0xLxAl - 48AAh)[ebx]  lea eax, (aMemS0xLx0xLxAl - 6D8Eh)[ebx]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 18h                            add esp, 18h
  cmp byte ptr [esi+19h], 0               cmp byte ptr [esi+19h], 0
* jz loc_48F7                             jz loc_6DDB
* lea eax, (a8Bit_0 - 48AAh)[ebx]         lea eax, (a8Bit_0 - 6D8Eh)[ebx]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+1Ah], 0               cmp byte ptr [esi+1Ah], 0
* jz loc_490C                             jz loc_6DF0
* lea eax, (a16Bit_0 - 48AAh)[ebx]        lea eax, (a16Bit_0 - 6D8Eh)[ebx]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+1Bh], 0               cmp byte ptr [esi+1Bh], 0
* jz loc_4921                             jz loc_6E05
* lea eax, (a32Bit - 48AAh)[ebx]          lea eax, (a32Bit - 6D8Eh)[ebx]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+14h], 0               cmp byte ptr [esi+14h], 0
* jz loc_4936                             jz loc_6E1A
* lea eax, (aExprom - 48AAh)[ebx]         lea eax, (aExprom - 6D8Eh)[ebx]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+15h], 0               cmp byte ptr [esi+15h], 0
* jz loc_494B                             jz loc_6E2F
* lea eax, (aShadow - 48AAh)[ebx]         lea eax, (aShadow - 6D8Eh)[ebx]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+16h], 0               cmp byte ptr [esi+16h], 0
* jz loc_495C                             jz loc_6E40
* lea eax, (aHiAddr - 48AAh)[ebx]         lea eax, (aHiAddr - 6D8Eh)[ebx]
* jmp loc_4962                            jmp loc_6E46
* lea eax, (aRange - 48AAh)[ebx]          lea eax, (aRange - 6D8Eh)[ebx]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+18h], 0               cmp byte ptr [esi+18h], 0
* jnz loc_4980                            jnz loc_6E64
* lea eax, (aRom - 48AAh)[ebx]            lea eax, (aRom - 6D8Eh)[ebx]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
* lea eax, (asc_93D3 - 48AAh)[ebx]        lea eax, (asc_7261 - 6D8Eh)[ebx]
  push eax                                push eax
* call _printf                            call _IOLog
*                                         mov eax, esi
  lea esp, [ebp-8]                        lea esp, [ebp-8]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpDMA print]`

Accepted `intentional-mismatch` (dual-bar forbids swapping: Apple tool uses _printf, reloc both use _IOLog).

Shared name; reloc dump is in `reconstruction/divergences.md`.

```
-[pnpDMA print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop edi                                 pop edi
  mov [ebp+var_4], 1                      mov [ebp+var_4], 1
* lea eax, (aDmaChannel - 434Eh)[edi]     lea eax, (aDmaChannel - 6226h)[edi]
  push eax                                push eax
* call _printf                            call _IOLog
  xor esi, esi                            xor esi, esi
  add esp, 4                              add esp, 4
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  cmp [edx+24h], esi                      cmp [edx+24h], esi
* jle loc_43B0                            jle loc_6288
* lea ecx, (aSD_0 - 434Eh)[edi]           lea ecx, (aSD_0 - 6226h)[edi]
  mov [ebp+var_8], ecx                    mov [ebp+var_8], ecx
  nop                                     nop
  nop                                     nop
  nop                                     nop
*                                         cmp [ebp+var_4], 0
*                                         jz loc_6260
*                                         lea eax, (unk_7103 - 6226h)[edi]
*                                         jmp loc_6266
*                                         lea eax, (asc_7A10 - 6226h)[edi]
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  mov edx, [edx+esi*4+4]                  mov edx, [edx+esi*4+4]
  push edx                                push edx
* cmp [ebp+var_4], 0
* jz loc_4390
* lea eax, (unk_9145 - 434Eh)[edi]
* jmp loc_4396
* lea eax, (asc_94E3 - 434Eh)[edi]
  push eax                                push eax
  mov ecx, [ebp+var_8]                    mov ecx, [ebp+var_8]
  push ecx                                push ecx
* call _printf                            call _IOLog
  mov [ebp+var_4], 0                      mov [ebp+var_4], 0
  add esp, 0Ch                            add esp, 0Ch
  inc esi                                 inc esi
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  cmp [edx+24h], esi                      cmp [edx+24h], esi
* jg loc_4378                             jg loc_6250
* lea eax, (asc_9551 - 434Eh)[edi]        lea eax, (asc_7A18 - 6226h)[edi]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  mov ecx, [ebp+self]                     mov ecx, [ebp+self]
  cmp byte ptr [ecx+28h], 0               cmp byte ptr [ecx+28h], 0
* jz loc_43D7                             jz loc_62AF
* lea eax, (a8Bit - 434Eh)[edi]           lea eax, (a8Bit - 6226h)[edi]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  cmp byte ptr [edx+29h], 0               cmp byte ptr [edx+29h], 0
* jz loc_43EF                             jz loc_62C7
* lea eax, (a16Bit - 434Eh)[edi]          lea eax, (a16Bit - 6226h)[edi]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
* lea eax, (aBusMaster - 434Eh)[edi]      lea eax, (aBusMaster - 6226h)[edi]
  push eax                                push eax
* call _printf                            call _IOLog
* lea eax, (aByte - 434Eh)[edi]           lea eax, (aByte - 6226h)[edi]
  push eax                                push eax
* call _printf                            call _IOLog
* lea eax, (aWord - 434Eh)[edi]           lea eax, (aWord - 6226h)[edi]
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 0Ch                            add esp, 0Ch
  mov ecx, [ebp+self]                     mov ecx, [ebp+self]
  movzx esi, byte ptr [ecx+2Dh]           movzx esi, byte ptr [ecx+2Dh]
  cmp esi, 3                              cmp esi, 3
* ja def_442B                             ja def_6303
* lea eax, (jpt_442B - 434Eh)[edi]        lea eax, (jpt_6303 - 6226h)[edi]
* add eax, ds:(jpt_442B - 4430h)[eax+esi*4]  add eax, ds:(jpt_6303 - 6308h)[eax+esi*4]
  jmp eax                                 jmp eax
* lea eax, (aCompat - 434Eh)[edi]         lea eax, (aCompat - 6226h)[edi]
* jmp loc_445E                            jmp loc_633A
* lea eax, (aTypeA - 434Eh)[edi]          lea eax, (aTypeA - 6226h)[edi]
* jmp loc_445E                            jmp loc_633A
* lea eax, (aTypeB - 434Eh)[edi]          lea eax, (aTypeB - 6226h)[edi]
* jmp loc_445E                            jmp loc_633A
* lea eax, (aTypeF - 434Eh)[edi]          lea eax, (aTypeF - 6226h)[edi]
*                                         jmp loc_633A
*                                         xor eax, eax
*                                         test eax, eax
*                                         jz loc_6347
  push eax                                push eax
* call _printf                            call _IOLog
  add esp, 4                              add esp, 4
* lea eax, (asc_93D3 - 434Eh)[edi]        lea eax, (asc_7261 - 6226h)[edi]
  push eax                                push eax
* call _printf                            call _IOLog
*                                         mov eax, [ebp+self]
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__PMRestoreDefaults`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__PMRestoreDefaults
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 20h                            mov eax, 0FFFFFFFFh
* push esi
* push ebx
* call $+5
* pop esi
* lea ebx, [ebp+var_20]
* mov [ebp+var_1D], 1
* mov [ebp+var_1C], 18h
* mov [ebp+var_18], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_10], ecx
* call _mig_get_reply_port
* mov [ebp+var_14], eax
* mov [ebp+var_C], 0AB2h
* push 0
* push 0
* push 20h
* push 0
* push ebx
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_8B10
* cmp ebx, 0FFFFFF36h
* jnz loc_8B0C
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_8B4D
* mov edx, [ebp+var_1C]
* movzx eax, [ebp+var_1D]
* cmp [ebp+var_C], 0B16h
* jz loc_8B28
* mov eax, 0FFFFFED3h
* jmp loc_8B4D
* cmp edx, 20h
* jnz loc_8B3D
* cmp eax, 1
* jnz loc_8B3D
* mov eax, ds:(_RetCodeCheck_172 - 8ABDh)[esi]
* cmp [ebp+var_8], eax
* jz loc_8B44
* mov eax, 0FFFFFED4h
* jmp loc_8B4D
* mov eax, [ebp+var_4]
* test eax, eax
* jnz loc_8B4D
* xor eax, eax
* lea esp, [ebp-28h]
* pop ebx
* pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOMapEISADevicePorts`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOMapEISADevicePorts
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 20h                            mov eax, 0FFFFFFFFh
* push esi
* push ebx
* call $+5
* pop esi
* lea ebx, [ebp+var_20]
* mov ecx, esi
* mov ecx, [ecx+1FEBh]
* mov [ebp+var_8], ecx
* mov ecx, [ebp+arg_4]
* mov [ebp+var_4], ecx
* mov [ebp+var_1D], 0
* mov [ebp+var_1C], 20h
* mov [ebp+var_18], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_10], ecx
* call _mig_get_reply_port
* mov [ebp+var_14], eax
* mov [ebp+var_C], 0AA5h
* push 0
* push 0
* push 20h
* push 0
* push ebx
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_7FC8
* cmp ebx, 0FFFFFF36h
* jnz loc_7FC1
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_8005
* mov edx, [ebp+var_1C]
* movzx eax, [ebp+var_1D]
* cmp [ebp+var_C], 0B09h
* jz loc_7FE0
* mov eax, 0FFFFFED3h
* jmp loc_8005
* cmp edx, 20h
* jnz loc_7FF5
* cmp eax, 1
* jnz loc_7FF5
* mov eax, ds:(_RetCodeCheck_120 - 7F61h)[esi]
* cmp [ebp+var_8], eax
* jz loc_7FFC
* mov eax, 0FFFFFED4h
* jmp loc_8005
* mov eax, [ebp+var_4]
* test eax, eax
* jnz loc_8005
* xor eax, eax
* lea esp, [ebp-28h]
* pop ebx
* pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOUnMapEISADevicePorts`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOUnMapEISADevicePorts
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 20h                            mov eax, 0FFFFFFFFh
* push esi
* push ebx
* call $+5
* pop esi
* lea ebx, [ebp+var_20]
* mov ecx, esi
* mov ecx, [ecx+1F37h]
* mov [ebp+var_8], ecx
* mov ecx, [ebp+arg_4]
* mov [ebp+var_4], ecx
* mov [ebp+var_1D], 0
* mov [ebp+var_1C], 20h
* mov [ebp+var_18], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_10], ecx
* call _mig_get_reply_port
* mov [ebp+var_14], eax
* mov [ebp+var_C], 0AA6h
* push 0
* push 0
* push 20h
* push 0
* push ebx
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_8084
* cmp ebx, 0FFFFFF36h
* jnz loc_807D
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_80C1
* mov edx, [ebp+var_1C]
* movzx eax, [ebp+var_1D]
* cmp [ebp+var_C], 0B0Ah
* jz loc_809C
* mov eax, 0FFFFFED3h
* jmp loc_80C1
* cmp edx, 20h
* jnz loc_80B1
* cmp eax, 1
* jnz loc_80B1
* mov eax, ds:(_RetCodeCheck_124 - 801Dh)[esi]
* cmp [ebp+var_8], eax
* jz loc_80B8
* mov eax, 0FFFFFED4h
* jmp loc_80C1
* mov eax, [ebp+var_4]
* test eax, eax
* jnz loc_80C1
* xor eax, eax
* lea esp, [ebp-28h]
* pop ebx
* pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__PMSetPowerManagement`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__PMSetPowerManagement
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 28h                            mov eax, 0FFFFFFFFh
* push esi
* push ebx
* call $+5
* pop esi
* lea ebx, [ebp+var_28]
* mov ecx, esi
* mov ecx, [ecx+15DBh]
* mov [ebp+var_10], ecx
* mov ecx, [ebp+arg_4]
* mov [ebp+var_C], ecx
* mov ecx, esi
* mov ecx, [ecx+15DFh]
* mov [ebp+var_8], ecx
* mov ecx, [ebp+arg_8]
* mov [ebp+var_4], ecx
* mov [ebp+var_25], 1
* mov [ebp+var_24], 28h
* mov [ebp+var_20], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_18], ecx
* call _mig_get_reply_port
* mov [ebp+var_1C], eax
* mov [ebp+var_14], 0AB1h
* push 0
* push 0
* push 20h
* push 0
* push ebx
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_8A68
* cmp ebx, 0FFFFFF36h
* jnz loc_8A62
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_8AA5
* mov edx, [ebp+var_24]
* movzx eax, [ebp+var_25]
* cmp [ebp+var_14], 0B15h
* jz loc_8A80
* mov eax, 0FFFFFED3h
* jmp loc_8AA5
* cmp edx, 20h
* jnz loc_8A95
* cmp eax, 1
* jnz loc_8A95
* mov eax, ds:(_RetCodeCheck_169 - 89F1h)[esi]
* cmp [ebp+var_10], eax
* jz loc_8A9C
* mov eax, 0FFFFFED4h
* jmp loc_8AA5
* mov eax, [ebp+var_C]
* test eax, eax
* jnz loc_8AA5
* xor eax, eax
* lea esp, [ebp-30h]
* pop ebx
* pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__PMSetPowerState`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__PMSetPowerState
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 28h                            mov eax, 0FFFFFFFFh
* push esi
* push ebx
* call $+5
* pop esi
* lea ebx, [ebp+var_28]
* mov ecx, esi
* mov ecx, [ecx+183Fh]
* mov [ebp+var_10], ecx
* mov ecx, [ebp+arg_4]
* mov [ebp+var_C], ecx
* mov ecx, esi
* mov ecx, [ecx+1843h]
* mov [ebp+var_8], ecx
* mov ecx, [ebp+arg_8]
* mov [ebp+var_4], ecx
* mov [ebp+var_25], 1
* mov [ebp+var_24], 28h
* mov [ebp+var_20], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_18], ecx
* call _mig_get_reply_port
* mov [ebp+var_1C], eax
* mov [ebp+var_14], 0AAEh
* push 0
* push 0
* push 20h
* push 0
* push ebx
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_87E8
* cmp ebx, 0FFFFFF36h
* jnz loc_87E2
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_8825
* mov edx, [ebp+var_24]
* movzx eax, [ebp+var_25]
* cmp [ebp+var_14], 0B12h
* jz loc_8800
* mov eax, 0FFFFFED3h
* jmp loc_8825
* cmp edx, 20h
* jnz loc_8815
* cmp eax, 1
* jnz loc_8815
* mov eax, ds:(_RetCodeCheck_156 - 8771h)[esi]
* cmp [ebp+var_10], eax
* jz loc_881C
* mov eax, 0FFFFFED4h
* jmp loc_8825
* mov eax, [ebp+var_C]
* test eax, eax
* jnz loc_8825
* xor eax, eax
* lea esp, [ebp-30h]
* pop ebx
* pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__PMGetPowerEvent`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__PMGetPowerEvent
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 28h                            mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop edi
* lea esi, [ebp+var_28]
* mov [ebp+var_25], 1
* mov [ebp+var_24], 18h
* mov [ebp+var_20], 100h
* mov edx, [ebp+arg_0]
* mov [ebp+var_18], edx
* call _mig_get_reply_port
* mov [ebp+var_1C], eax
* mov [ebp+var_14], 0AAFh
* push 0
* push 0
* push 28h
* push 0
* push esi
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_8894
* cmp ebx, 0FFFFFF36h
* jnz loc_888D
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_88F5
* mov ebx, [ebp+var_24]
* movzx eax, [ebp+var_25]
* cmp [ebp+var_14], 0B13h
* jz loc_88AC
* mov eax, 0FFFFFED3h
* jmp loc_88F5
* cmp ebx, 28h
* jnz loc_88B6
* cmp eax, 1
* jz loc_88C6
* cmp ebx, 20h
* jnz loc_88F0
* cmp eax, 1
* jnz loc_88F0
* cmp [ebp+var_C], 0
* jz loc_88F0
* mov eax, ds:(_RetCodeCheck_159 - 883Eh)[edi]
* cmp [esi+18h], eax
* jnz loc_88F0
* mov eax, [esi+1Ch]
* test eax, eax
* jnz loc_88F5
* mov eax, ds:(_eventCheck_160 - 883Eh)[edi]
* cmp [esi+20h], eax
* jnz loc_88F0
* mov edx, [esi+24h]
* mov ecx, [ebp+arg_4]
* mov [ecx], edx
* mov eax, [esi+1Ch]
* jmp loc_88F5
* mov eax, 0FFFFFED4h
* lea esp, [ebp-34h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOCreateMachPort`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOCreateMachPort
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 28h                            mov eax, [ebp+arg_8]
* push edi
* push esi
* push ebx
* call $+5
* pop edi
* lea esi, [ebp+var_28]
* mov edx, edi
* mov edx, [edx+11DAh]
* mov [ebp+var_10], edx
* mov ecx, [ebp+arg_4]
* mov [ebp+var_C], ecx
* mov [ebp+var_25], 1
* mov [ebp+var_24], 20h
* mov [ebp+var_20], 100h
* mov edx, [ebp+arg_0]
* mov [ebp+var_18], edx
* call _mig_get_reply_port
* mov [ebp+var_1C], eax
* mov [ebp+var_14], 0AB4h
* push 0
* push 0
* push 28h
* push 0
* push esi
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_8E80
* cmp ebx, 0FFFFFF36h
* jnz loc_8E7A
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_8EE1
* mov ebx, [ebp+var_24]
* movzx eax, [ebp+var_25]
* cmp [ebp+var_14], 0B18h
* jz loc_8E98
* mov eax, 0FFFFFED3h
* jmp loc_8EE1
* cmp ebx, 28h
* jnz loc_8EA1
  test eax, eax                           test eax, eax
* jz loc_8EB1                             jz loc_3B24
* cmp ebx, 20h                            mov dword ptr [eax], 0
* jnz loc_8EDC                            mov eax, 0FFFFFFFFh
* cmp eax, 1
* jnz loc_8EDC
* cmp [ebp+var_C], 0
* jz loc_8EDC
* mov eax, ds:(_RetCodeCheck_184 - 8E1Ah)[edi]
* cmp [esi+18h], eax
* jnz loc_8EDC
* mov eax, [esi+1Ch]
* test eax, eax
* jnz loc_8EE1
* mov eax, ds:(_machPortCheck_185 - 8E1Ah)[edi]
* cmp [esi+20h], eax
* jnz loc_8EDC
* mov edx, [esi+24h]
* mov ecx, [ebp+arg_8]
* mov [ecx], edx
* mov eax, [esi+1Ch]
* jmp loc_8EE1
* mov eax, 0FFFFFED4h
* lea esp, [ebp-34h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__PMGetPowerStatus`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__PMGetPowerStatus
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 34h                            mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_34]
* mov edi, [ebp+arg_4]
* lea esi, [ebp+var_30]
* mov [ebp+var_2D], 1
* mov [ebp+var_2C], 18h
* mov [ebp+var_28], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_20], ecx
* call _mig_get_reply_port
* mov [ebp+var_24], eax
* mov [ebp+var_1C], 0AB0h
* push 0
* push 0
* push 30h
* push 0
* push esi
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_8968
* cmp ebx, 0FFFFFF36h
* jnz loc_8962
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_89D9
* mov edx, [ebp+var_2C]
* movzx eax, [ebp+var_2D]
* cmp [ebp+var_1C], 0B14h
* jz loc_8980
* mov eax, 0FFFFFED3h
* jmp loc_89D9
* cmp edx, 30h
* jnz loc_898A
* cmp eax, 1
* jz loc_899A
* cmp edx, 20h
* jnz loc_89D4
* cmp eax, 1
* jnz loc_89D4
* cmp [ebp+var_14], 0
* jz loc_89D4
* mov ecx, [ebp+var_34]
* mov eax, [ecx+16B6h]
* cmp [esi+18h], eax
* jnz loc_89D4
* mov eax, [esi+1Ch]
* test eax, eax
* jnz loc_89D9
* mov ecx, [ebp+var_34]
* mov eax, [ecx+16BAh]
* cmp [esi+20h], eax
* jnz loc_89D4
* mov ecx, [esi+24h]
* mov [edi], ecx
* mov ecx, [esi+28h]
* mov [edi+4], ecx
* mov ecx, [esi+2Ch]
* mov [edi+8], ecx
* mov eax, [esi+1Ch]
* jmp loc_89D9
* mov eax, 0FFFFFED4h
* lea esp, [ebp-40h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOProbeDriver`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOProbeDriver
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 1024h                          mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop esi
* mov ebx, [ebp+arg_8]
* lea edi, [ebp+var_1024]
* mov ecx, esi
* mov ecx, [ecx+1D67h]
* mov [ebp+var_100C], ecx
* mov ecx, esi
* mov ecx, [ecx+1D6Bh]
* mov [ebp+var_1008], ecx
* mov ecx, esi
* mov ecx, [ecx+1D6Fh]
* mov [ebp+var_1004], ecx
* cmp ebx, 1000h
* jbe loc_825C
* mov eax, 0FFFFFECDh
* jmp loc_8324
* push ebx
* lea eax, [ebp+var_1000]
* push eax
* mov ecx, [ebp+arg_4]
* push ecx
* call _bcopy
* mov [ebp+var_1004], ebx
* lea eax, [ebx+3]
* and al, 0FCh
* mov [ebp+var_1021], 1
* add eax, 24h
* mov [ebp+var_1020], eax
* mov [ebp+var_101C], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_1014], ecx
* call _mig_get_reply_port
* mov [ebp+var_1018], eax
* mov [ebp+var_1010], 0AAAh
* push 0
* push 0
* push 20h
* push 0
* push edi
* call _msg_rpc
* mov ebx, eax
* add esp, 20h
* test ebx, ebx
* jz loc_82D8
* cmp ebx, 0FFFFFF36h
* jnz loc_82D4
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_8324
* mov eax, [ebp+var_1020]
* movzx edx, [ebp+var_1021]
* cmp [ebp+var_1010], 0B0Eh
* jz loc_82F8
* mov eax, 0FFFFFED3h
* jmp loc_8324
* cmp eax, 20h
* jnz loc_8310
* cmp edx, 1
* jnz loc_8310
* mov eax, ds:(_RetCodeCheck_138 - 8215h)[esi]
* cmp [ebp+var_100C], eax
* jz loc_8318
* mov eax, 0FFFFFED4h
* jmp loc_8324
* mov eax, [ebp+var_1008]
* test eax, eax
* jnz loc_8324
* xor eax, eax
* lea esp, [ebp-1030h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOUnloadDriver`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOUnloadDriver
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 1024h                          mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop esi
* mov ebx, [ebp+arg_8]
* lea edi, [ebp+var_1024]
* mov ecx, esi
* mov ecx, [ecx+1ACFh]
* mov [ebp+var_100C], ecx
* mov ecx, esi
* mov ecx, [ecx+1AD3h]
* mov [ebp+var_1008], ecx
* mov ecx, esi
* mov ecx, [ecx+1AD7h]
* mov [ebp+var_1004], ecx
* cmp ebx, 1000h
* jbe loc_850C
* mov eax, 0FFFFFECDh
* jmp loc_85D4
* push ebx
* lea eax, [ebp+var_1000]
* push eax
* mov ecx, [ebp+arg_4]
* push ecx
* call _bcopy
* mov [ebp+var_1004], ebx
* lea eax, [ebx+3]
* and al, 0FCh
* mov [ebp+var_1021], 1
* add eax, 24h
* mov [ebp+var_1020], eax
* mov [ebp+var_101C], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_1014], ecx
* call _mig_get_reply_port
* mov [ebp+var_1018], eax
* mov [ebp+var_1010], 0AACh
* push 0
* push 0
* push 20h
* push 0
* push edi
* call _msg_rpc
* mov ebx, eax
* add esp, 20h
* test ebx, ebx
* jz loc_8588
* cmp ebx, 0FFFFFF36h
* jnz loc_8584
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_85D4
* mov eax, [ebp+var_1020]
* movzx edx, [ebp+var_1021]
* cmp [ebp+var_1010], 0B10h
* jz loc_85A8
* mov eax, 0FFFFFED3h
* jmp loc_85D4
* cmp eax, 20h
* jnz loc_85C0
* cmp edx, 1
* jnz loc_85C0
* mov eax, ds:(_RetCodeCheck_146 - 84C5h)[esi]
* cmp [ebp+var_100C], eax
* jz loc_85C8
* mov eax, 0FFFFFED4h
* jmp loc_85D4
* mov eax, [ebp+var_1008]
* test eax, eax
* jnz loc_85D4
* xor eax, eax
* lea esp, [ebp-1030h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOCopyMemory`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOCopyMemory
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* push edi                                mov eax, [ebp+__n]
* push esi                                push eax
* push ebx                                mov eax, [ebp+__src]
* mov ebx, [ebp+arg_C]                    push eax
* cmp [ebp+arg_0], 0                      mov eax, [ebp+__dst]
* jz loc_913B                             push eax
* cmp [ebp+arg_4], 0                      call _memcpy
* jz loc_913B
* mov ecx, [ebp+arg_4]
* cmp [ebp+arg_0], ecx
* jz loc_913B
* cmp [ebp+arg_8], 0
* jz loc_913B
* test ebx, ebx
* jnz loc_9088
* mov ebx, 1
* cmp ebx, 2
* jbe loc_9092
* mov ebx, 4
* cmp ebx, 1
* jnz loc_90A8
* mov ecx, [ebp+arg_8]
* mov edi, [ebp+arg_4]
* mov esi, [ebp+arg_0]
* movsb
* jmp loc_913B
* lea eax, [ebx-1]
* mov edx, [ebp+arg_0]
* and edx, eax
* jz loc_90C9
* mov ecx, ebx
* sub ecx, edx
* mov edx, ecx
* mov edi, [ebp+arg_4]
* mov esi, [ebp+arg_0]
* movsb
* sub [ebp+arg_8], edx
* add [ebp+arg_4], edx
* add [ebp+arg_0], edx
* cmp ebx, 2
* jnz loc_90E0
* mov eax, [ebp+arg_8]
* sar eax, 1
* mov ecx, eax
* mov edi, [ebp+arg_4]
* mov esi, [ebp+arg_0]
* movsw
* jmp loc_90F0
* mov eax, [ebp+arg_8]
* sar eax, 2
* mov ecx, eax
* mov edi, [ebp+arg_4]
* mov esi, [ebp+arg_0]
* movsd
* lea eax, [ebx-1]
* mov edx, [ebp+arg_8]
* and edx, eax
* jz loc_913B
* not eax
* and eax, [ebp+arg_8]
* add [ebp+arg_0], eax
* add [ebp+arg_4], eax
* cmp edx, 2
* jz loc_9125
* jg loc_9114
* cmp edx, 1
* jz loc_9131
* jmp loc_913B
* cmp edx, 3
* jnz loc_913B
* mov ecx, [ebp+arg_0]
* mov cl, [ecx+2]
* mov esi, [ebp+arg_4]
* mov [esi+2], cl
* mov ecx, [ebp+arg_0]
* mov cl, [ecx+1]
* mov esi, [ebp+arg_4]
* mov [esi+1], cl
* mov ecx, [ebp+arg_0]
* mov cl, [ecx]
* mov esi, [ebp+arg_4]
* mov [esi], cl
* lea esp, [ebp-0Ch]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOLookupByObjectNumber`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOLookupByObjectNumber
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 0D0h                           mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_CC]
* lea edx, [ebp+var_C8]
* mov ecx, [ebp+var_CC]
* mov ecx, [ebp+var_CC]
* mov ecx, [ecx+2CEBh]
* mov [ebp+var_B0], ecx
* mov ebx, [ebp+arg_4]
* mov [ebp+var_AC], ebx
* mov [ebp+var_C5], 1
* mov [ebp+var_C4], 20h
* mov [ebp+var_C0], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_B8], ecx
* mov [ebp+var_D0], edx
* call _mig_get_reply_port
* mov [ebp+var_BC], eax
* mov [ebp+var_B4], 0A9Eh
* push 0
* push 0
* push 0C8h
* push 0
* mov edx, [ebp+var_D0]
* push edx
* call _msg_rpc
* mov esi, eax
* add esp, 14h
* mov edx, [ebp+var_D0]
* test esi, esi
* jz loc_72A4
* cmp esi, 0FFFFFF36h
* jnz loc_729C
* call _mig_dealloc_reply_port
* mov eax, esi
* jmp loc_7349
* mov esi, [ebp+var_C4]
* movzx eax, [ebp+var_C5]
* cmp [ebp+var_B4], 0B02h
* jz loc_72C8
* mov eax, 0FFFFFED3h
* jmp loc_7349
* cmp esi, 0C8h
* jnz loc_72D5
* cmp eax, 1
* jz loc_72E8
* cmp esi, 20h
* jnz loc_7344
* cmp eax, 1
* jnz loc_7344
* cmp [ebp+var_AC], 0
* jz loc_7344
* mov ebx, [ebp+var_CC]
* mov eax, [ebx+2CEFh]
* cmp [edx+18h], eax
* jnz loc_7344
* mov eax, [edx+1Ch]
* test eax, eax
* jnz loc_7349
* mov ecx, [ebp+var_CC]
* mov eax, [ecx+2CF3h]
* cmp [edx+20h], eax
* jnz loc_7344
* mov edi, [ebp+arg_8]
* lea esi, [edx+24h]
* cld
* mov ecx, 14h
* movsd
* mov ebx, [ebp+var_CC]
* mov eax, [ebx+2CF7h]
* cmp [edx+74h], eax
* jnz loc_7344
* mov edi, [ebp+arg_C]
* lea esi, [edx+78h]
* cld
* mov ecx, 14h
* movsd
* mov eax, [edx+1Ch]
* jmp loc_7349
* mov eax, 0FFFFFED4h
* lea esp, [ebp-0DCh]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOLookupByDeviceName`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOLookupByDeviceName
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 84h                            mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_80]
* lea edx, [ebp+var_7C]
* mov ecx, [ebp+var_80]
* mov ecx, [ebp+var_80]
* mov ecx, [ecx+2B8Fh]
* mov [ebp+var_64], ecx
* lea edi, [ebp+var_60]
* mov esi, [ebp+arg_4]
* cld
* mov ecx, 14h
* movsd
* mov [ebp+var_79], 1
* mov [ebp+var_78], 6Ch
* mov [ebp+var_74], 100h
* mov ebx, [ebp+arg_0]
* mov [ebp+var_6C], ebx
* mov [ebp+var_84], edx
* call _mig_get_reply_port
* mov [ebp+var_70], eax
* mov [ebp+var_68], 0A9Fh
* push 0
* push 0
* push 7Ch
* push 0
* mov edx, [ebp+var_84]
* push edx
* call _msg_rpc
* mov esi, eax
* add esp, 14h
* mov edx, [ebp+var_84]
* test esi, esi
* jz loc_73F0
* cmp esi, 0FFFFFF36h
* jnz loc_73E9
* call _mig_dealloc_reply_port
* mov eax, esi
* jmp loc_7475
* mov esi, [ebp+var_78]
* movzx eax, [ebp+var_79]
* cmp [ebp+var_68], 0B03h
* jz loc_7408
* mov eax, 0FFFFFED3h
* jmp loc_7475
* cmp esi, 7Ch
* jnz loc_7412
* cmp eax, 1
* jz loc_7422
* cmp esi, 20h
* jnz loc_7470
* cmp eax, 1
* jnz loc_7470
* cmp [ebp+var_60], 0
* jz loc_7470
* mov ecx, [ebp+var_80]
* mov eax, [ecx+2B93h]
* cmp [edx+18h], eax
* jnz loc_7470
* mov eax, [edx+1Ch]
* test eax, eax
* jnz loc_7475
* mov ebx, [ebp+var_80]
* mov eax, [ebx+2B97h]
* cmp [edx+20h], eax
* jnz loc_7470
* mov ebx, [edx+24h]
* mov ecx, [ebp+arg_8]
* mov [ecx], ebx
* mov ecx, [ebp+var_80]
* mov eax, [ecx+2B9Bh]
* cmp [edx+28h], eax
* jnz loc_7470
* mov edi, [ebp+arg_C]
* lea esi, [edx+2Ch]
* cld
* mov ecx, 14h
* movsd
* mov eax, [edx+1Ch]
* jmp loc_7475
* mov eax, 0FFFFFED4h
* lea esp, [ebp-90h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOSetIntValues`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOSetIntValues
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 870h                           mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_86C]
* lea ecx, [ebp+var_868]
* mov [ebp+var_870], ecx
* mov esi, [ebp+var_86C]
* mov esi, [ebp+var_86C]
* mov esi, [esi+264Fh]
* mov [ebp+var_850], esi
* mov ecx, [ebp+arg_4]
* mov [ebp+var_84C], ecx
* mov esi, [ebp+var_86C]
* mov esi, [ebp+var_86C]
* mov esi, [esi+2653h]
* mov [ebp+var_848], esi
* lea edi, [ebp+var_844]
* mov eax, [ebp+arg_8]
* mov esi, eax
* cld
* mov ecx, 10h
* movsd
* mov ecx, [ebp+var_86C]
* mov ecx, [ebp+var_86C]
* mov ecx, [ecx+2657h]
* mov [ebp+var_804], ecx
* cmp [ebp+arg_10], 200h
* jbe loc_7964
* mov eax, 0FFFFFECDh
* jmp loc_7A58
* mov esi, [ebp+arg_10]
* lea ebx, ds:0[esi*4]
* push ebx
* lea eax, [ebp+var_800]
* push eax
* mov ecx, [ebp+arg_C]
* push ecx
* call _bcopy
* mov dx, word ptr [ebp+arg_10]
* and dh, 0Fh
* mov ax, word ptr [ebp+var_804+2]
* and ax, 0F000h
* or ax, dx
* mov word ptr [ebp+var_804+2], ax
* mov [ebp+var_865], 1
* add ebx, 68h
* mov [ebp+var_864], ebx
* mov [ebp+var_860], 100h
* mov esi, [ebp+arg_0]
* mov [ebp+var_858], esi
* call _mig_get_reply_port
* mov [ebp+var_85C], eax
* mov [ebp+var_854], 0AA2h
* push 0
* push 0
* push 20h
* push 0
* mov ecx, [ebp+var_870]
* push ecx
* call _msg_rpc
* mov ebx, eax
* add esp, 20h
* test ebx, ebx
* jz loc_7A04
* cmp ebx, 0FFFFFF36h
* jnz loc_79FD
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_7A58
* mov eax, [ebp+var_864]
* movzx edx, [ebp+var_865]
* cmp [ebp+var_854], 0B06h
* jz loc_7A24
* mov eax, 0FFFFFED3h
* jmp loc_7A58
* cmp eax, 20h
* jnz loc_7A42
* cmp edx, 1
* jnz loc_7A42
* mov esi, [ebp+var_86C]
* mov eax, [esi+265Bh]
* cmp [ebp+var_850], eax
* jz loc_7A4C
* mov eax, 0FFFFFED4h
* jmp loc_7A58
* mov eax, [ebp+var_84C]
* test eax, eax
* jnz loc_7A58
* xor eax, eax
* lea esp, [ebp-87Ch]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOMapEISADeviceMemory`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOMapEISADeviceMemory
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 48h                            mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop esi
* mov al, [ebp+arg_14]
* lea edi, [ebp+var_48]
* mov edx, esi
* mov edx, [edx+1E82h]
* mov [ebp+var_30], edx
* mov ecx, [ebp+arg_4]
* mov [ebp+var_2C], ecx
* mov edx, esi
* mov edx, [edx+1E86h]
* mov [ebp+var_28], edx
* mov ecx, [ebp+arg_8]
* mov [ebp+var_24], ecx
* mov edx, esi
* mov edx, [edx+1E8Ah]
* mov [ebp+var_20], edx
* mov ecx, [ebp+arg_C]
* mov [ebp+var_1C], ecx
* mov edx, esi
* mov edx, [edx+1E8Eh]
* mov [ebp+var_18], edx
* mov ecx, [ebp+arg_10]
* mov ecx, [ecx]
* mov [ebp+var_14], ecx
* mov edx, esi
* mov edx, [edx+1E92h]
* mov [ebp+var_10], edx
* mov [ebp+var_C], al
* mov ecx, esi
* mov ecx, [ecx+1E96h]
* mov [ebp+var_8], ecx
* mov edx, [ebp+arg_18]
* mov [ebp+var_4], edx
* mov [ebp+var_45], 0
* mov [ebp+var_44], 48h
* mov [ebp+var_40], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_38], ecx
* call _mig_get_reply_port
* mov [ebp+var_3C], eax
* mov [ebp+var_34], 0AA7h
* push 0
* push 0
* push 28h
* push 0
* push edi
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_8198
* cmp ebx, 0FFFFFF36h
* jnz loc_8191
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_81F9
* mov ebx, [ebp+var_44]
* movzx eax, [ebp+var_45]
* cmp [ebp+var_34], 0B0Bh
* jz loc_81B0
* mov eax, 0FFFFFED3h
* jmp loc_81F9
* cmp ebx, 28h
* jnz loc_81BA
* cmp eax, 1
* jz loc_81CA
* cmp ebx, 20h
* jnz loc_81F4
* cmp eax, 1
* jnz loc_81F4
* cmp [ebp+var_2C], 0
* jz loc_81F4
* mov eax, ds:(_RetCodeCheck_133 - 80DAh)[esi]
* cmp [edi+18h], eax
* jnz loc_81F4
* mov eax, [edi+1Ch]
* test eax, eax
* jnz loc_81F9
* mov eax, ds:(_addrCheck_134 - 80DAh)[esi]
* cmp [edi+20h], eax
* jnz loc_81F4
* mov ecx, [edi+24h]
* mov edx, [ebp+arg_10]
* mov [edx], ecx
* mov eax, [edi+1Ch]
* jmp loc_81F9
* mov eax, 0FFFFFED4h
* lea esp, [ebp-54h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOSetCharValues`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOSetCharValues
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 270h                           mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_26C]
* mov ebx, [ebp+arg_10]
* lea ecx, [ebp+var_268]
* mov [ebp+var_270], ecx
* mov esi, [ebp+var_26C]
* mov esi, [ebp+var_26C]
* mov esi, [esi+24BFh]
* mov [ebp+var_250], esi
* mov ecx, [ebp+arg_4]
* mov [ebp+var_24C], ecx
* mov esi, [ebp+var_26C]
* mov esi, [ebp+var_26C]
* mov esi, [esi+24C3h]
* mov [ebp+var_248], esi
* lea edi, [ebp+var_244]
* mov eax, [ebp+arg_8]
* mov esi, eax
* cld
* mov ecx, 10h
* movsd
* mov ecx, [ebp+var_26C]
* mov ecx, [ebp+var_26C]
* mov ecx, [ecx+24C7h]
* mov [ebp+var_204], ecx
* cmp ebx, 200h
* jbe loc_7B04
* mov eax, 0FFFFFECDh
* jmp loc_7BF0
* push ebx
* lea eax, [ebp+var_200]
* push eax
* mov esi, [ebp+arg_C]
* push esi
* call _bcopy
* mov edx, ebx
* and dh, 0Fh
* mov ax, word ptr [ebp+var_204+2]
* and ax, 0F000h
* or ax, dx
* mov word ptr [ebp+var_204+2], ax
* lea eax, [ebx+3]
* and al, 0FCh
* mov [ebp+var_265], 1
* add eax, 68h
* mov [ebp+var_264], eax
* mov [ebp+var_260], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_258], ecx
* call _mig_get_reply_port
* mov [ebp+var_25C], eax
* mov [ebp+var_254], 0AA3h
* push 0
* push 0
* push 20h
* push 0
* mov esi, [ebp+var_270]
* push esi
* call _msg_rpc
* mov ebx, eax
* add esp, 20h
* test ebx, ebx
* jz loc_7B9C
* cmp ebx, 0FFFFFF36h
* jnz loc_7B96
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_7BF0
* mov eax, [ebp+var_264]
* movzx edx, [ebp+var_265]
* cmp [ebp+var_254], 0B07h
* jz loc_7BBC
* mov eax, 0FFFFFED3h
* jmp loc_7BF0
* cmp eax, 20h
* jnz loc_7BDA
* cmp edx, 1
* jnz loc_7BDA
* mov ecx, [ebp+var_26C]
* mov eax, [ecx+24CBh]
* cmp [ebp+var_250], eax
* jz loc_7BE4
* mov eax, 0FFFFFED4h
* jmp loc_7BF0
* mov eax, [ebp+var_24C]
* test eax, eax
* jnz loc_7BF0
* xor eax, eax
* lea esp, [ebp-27Ch]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOGetSystemConfig`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOGetSystemConfig
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 1030h                          mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_1030]
* lea esi, [ebp+var_102C]
* mov ecx, [ebp+var_1030]
* mov ecx, [ebp+var_1030]
* mov ecx, [ecx+1C47h]
* mov [ebp+var_1014], ecx
* mov edi, [ebp+arg_4]
* mov [ebp+var_1010], edi
* mov [ebp+var_1029], 1
* mov [ebp+var_1028], 20h
* mov [ebp+var_1024], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_101C], ecx
* call _mig_get_reply_port
* mov [ebp+var_1020], eax
* mov [ebp+var_1018], 0AABh
* push 0
* push 0
* push 102Ch
* push 0
* push esi
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_83DC
* cmp ebx, 0FFFFFF36h
* jnz loc_83D2
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_84A7
* mov ebx, [ebp+var_1028]
* movzx edx, [ebp+var_1029]
* cmp [ebp+var_1018], 0B0Fh
* jz loc_8400
* mov eax, 0FFFFFED3h
* jmp loc_84A7
* lea eax, [ebx-2Ch]
* cmp eax, 1000h
* ja loc_840F
* cmp edx, 1
* jz loc_8422
* cmp ebx, 20h
* jnz loc_845B
* cmp edx, 1
* jnz loc_845B
* cmp [ebp+var_1010], 0
* jz loc_845B
* mov edi, [ebp+var_1030]
* mov eax, [edi+1C4Bh]
* cmp [esi+18h], eax
* jnz loc_845B
* mov eax, [esi+1Ch]
* test eax, eax
* jnz loc_84A7
* mov al, [esi+23h]
* and al, 30h
* cmp al, 30h
* jnz loc_845B
* cmp dword ptr [esi+24h], 80008h
* jnz loc_845B
* mov edx, [esi+28h]
* lea eax, [edx+3]
* and al, 0FCh
* add eax, 2Ch
* cmp ebx, eax
* jz loc_8464
* mov eax, 0FFFFFED4h
* jmp loc_84A7
* mov ecx, [ebp+arg_C]
* mov eax, [ecx]
* cmp edx, eax
* ja loc_848C
* push edx
* mov edi, [ebp+arg_8]
* push edi
* lea eax, [esi+2Ch]
* push eax
* call _bcopy
* mov esi, [esi+28h]
* mov ecx, [ebp+arg_C]
* mov [ecx], esi
* mov eax, [ebp+var_1010]
* jmp loc_84A7
* push eax
* mov edi, [ebp+arg_8]
* push edi
* lea eax, [esi+2Ch]
* push eax
* call _bcopy
* mov esi, [esi+28h]
* mov ecx, [ebp+arg_C]
* mov [ecx], esi
* mov eax, 0FFFFFECDh
* lea esp, [ebp-103Ch]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOGetDriverConfig`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOGetDriverConfig
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 102Ch                          mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop edi
* lea esi, [ebp+var_102C]
* mov ecx, edi
* mov ecx, [ecx+19AFh]
* mov [ebp+var_1014], ecx
* mov ecx, [ebp+arg_4]
* mov [ebp+var_1010], ecx
* mov ecx, edi
* mov ecx, [ecx+19B3h]
* mov [ebp+var_100C], ecx
* mov ecx, [ebp+arg_8]
* mov [ebp+var_1008], ecx
* mov [ebp+var_1029], 1
* mov [ebp+var_1028], 28h
* mov [ebp+var_1024], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_101C], ecx
* call _mig_get_reply_port
* mov [ebp+var_1020], eax
* mov [ebp+var_1018], 0AADh
* push 0
* push 0
* push 102Ch
* push 0
* push esi
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_8694
* cmp ebx, 0FFFFFF36h
* jnz loc_868A
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_8757
* mov ebx, [ebp+var_1028]
* movzx edx, [ebp+var_1029]
* cmp [ebp+var_1018], 0B11h
* jz loc_86B8
* mov eax, 0FFFFFED3h
* jmp loc_8757
* lea eax, [ebx-2Ch]
* cmp eax, 1000h
* ja loc_86C7
* cmp edx, 1
* jz loc_86DA
* cmp ebx, 20h
* jnz loc_870D
* cmp edx, 1
* jnz loc_870D
* cmp [ebp+var_1010], 0
* jz loc_870D
* mov eax, ds:(_RetCodeCheck_151 - 85F5h)[edi]
* cmp [esi+18h], eax
* jnz loc_870D
* mov eax, [esi+1Ch]
* test eax, eax
* jnz loc_8757
* mov al, [esi+23h]
* and al, 30h
* cmp al, 30h
* jnz loc_870D
* cmp dword ptr [esi+24h], 80008h
* jnz loc_870D
* mov edx, [esi+28h]
* lea eax, [edx+3]
* and al, 0FCh
* add eax, 2Ch
* cmp ebx, eax
* jz loc_8714
* mov eax, 0FFFFFED4h
* jmp loc_8757
* mov ecx, [ebp+arg_10]
* mov eax, [ecx]
* cmp edx, eax
* ja loc_873C
* push edx
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, [esi+2Ch]
* push eax
* call _bcopy
* mov esi, [esi+28h]
* mov ecx, [ebp+arg_10]
* mov [ecx], esi
* mov eax, [ebp+var_1010]
* jmp loc_8757
* push eax
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, [esi+2Ch]
* push eax
* call _bcopy
* mov esi, [esi+28h]
* mov ecx, [ebp+arg_10]
* mov [ecx], esi
* mov eax, 0FFFFFECDh
* lea esp, [ebp-1038h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOGetIntValues`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOGetIntValues
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 82Ch                           mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_828]
* lea ecx, [ebp+var_824]
* mov [ebp+var_82C], ecx
* mov esi, [ebp+var_828]
* mov esi, [ebp+var_828]
* mov esi, [esi+2A73h]
* mov [ebp+var_80C], esi
* mov ecx, [ebp+arg_4]
* mov [ebp+var_808], ecx
* mov esi, [ebp+var_828]
* mov esi, [ebp+var_828]
* mov esi, [esi+2A77h]
* mov [ebp+var_804], esi
* lea edi, [ebp+var_800]
* mov eax, [ebp+arg_8]
* mov esi, eax
* cld
* mov ecx, 10h
* movsd
* mov ecx, [ebp+var_828]
* mov ecx, [ebp+var_828]
* mov ecx, [ecx+2A7Bh]
* mov [ebp+var_7C0], ecx
* mov esi, [ebp+arg_C]
* mov [ebp+var_7BC], esi
* mov [ebp+var_821], 1
* mov [ebp+var_820], 6Ch
* mov [ebp+var_81C], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_814], ecx
* call _mig_get_reply_port
* mov [ebp+var_818], eax
* mov [ebp+var_810], 0AA0h
* push 0
* push 0
* push 824h
* push 0
* mov esi, [ebp+var_82C]
* push esi
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_7584
* cmp ebx, 0FFFFFF36h
* jnz loc_757A
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_7699
* mov ebx, [ebp+var_820]
* movzx edx, [ebp+var_821]
* cmp [ebp+var_810], 0B04h
* jz loc_75A8
* mov eax, 0FFFFFED3h
* jmp loc_7699
* lea eax, [ebx-24h]
* cmp eax, 800h
* ja loc_75B7
* cmp edx, 1
* jz loc_75CA
* cmp ebx, 20h
* jnz loc_7625
* cmp edx, 1
* jnz loc_7625
* cmp [ebp+var_808], 0
* jz loc_7625
* mov ecx, [ebp+var_828]
* mov eax, [ecx+2A7Fh]
* mov esi, [ebp+var_82C]
* cmp [esi+18h], eax
* jnz loc_7625
* mov ecx, [ebp+var_82C]
* mov eax, [ecx+1Ch]
* test eax, eax
* jnz loc_7699
* mov esi, [ebp+var_82C]
* mov eax, [esi+20h]
* and eax, 3000FFFFh
* cmp eax, 10002002h
* jnz loc_7625
* mov ecx, [ebp+var_82C]
* mov dx, [ecx+22h]
* and edx, 0FFFh
* lea edi, ds:0[edx*4]
* lea eax, [edi+24h]
* cmp ebx, eax
* jz loc_762C
* mov eax, 0FFFFFED4h
* jmp loc_7699
* mov esi, [ebp+arg_14]
* mov eax, [esi]
* cmp edx, eax
* ja loc_7668
* push edi
* mov ecx, [ebp+arg_10]
* push ecx
* mov eax, [ebp+var_82C]
* add eax, 24h
* push eax
* call _bcopy
* mov esi, [ebp+var_82C]
* mov cx, [esi+22h]
* and ecx, 0FFFh
* mov esi, [ebp+arg_14]
* mov [esi], ecx
* mov eax, [ebp+var_808]
* jmp loc_7699
* shl eax, 2
* push eax
* mov esi, [ebp+arg_10]
* push esi
* mov eax, [ebp+var_82C]
* add eax, 24h
* push eax
* call _bcopy
* mov ecx, [ebp+var_82C]
* mov si, [ecx+22h]
* and esi, 0FFFh
* mov ecx, [ebp+arg_14]
* mov [ecx], esi
* mov eax, 0FFFFFECDh
* lea esp, [ebp-838h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOGetCharValues`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOGetCharValues
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 22Ch                           mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_228]
* lea esi, [ebp+var_224]
* mov [ebp+var_22C], esi
* mov edi, [ebp+var_228]
* mov edi, [ebp+var_228]
* mov edi, [edi+285Fh]
* mov [ebp+var_20C], edi
* mov esi, [ebp+arg_4]
* mov [ebp+var_208], esi
* mov edi, [ebp+var_228]
* mov edi, [ebp+var_228]
* mov edi, [edi+2863h]
* mov [ebp+var_204], edi
* lea edx, [ebp+var_200]
* mov eax, [ebp+arg_8]
* mov edi, edx
* mov esi, eax
* cld
* mov ecx, 10h
* movsd
* mov esi, [ebp+var_228]
* mov esi, [ebp+var_228]
* mov esi, [esi+2867h]
* mov [ebp+var_1C0], esi
* mov edi, [ebp+arg_C]
* mov [ebp+var_1BC], edi
* mov [ebp+var_221], 1
* mov [ebp+var_220], 6Ch
* mov [ebp+var_21C], 100h
* mov esi, [ebp+arg_0]
* mov [ebp+var_214], esi
* call _mig_get_reply_port
* mov [ebp+var_218], eax
* mov [ebp+var_210], 0AA1h
* push 0
* push 0
* push 224h
* push 0
* mov edi, [ebp+var_22C]
* push edi
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_77A8
* cmp ebx, 0FFFFFF36h
* jnz loc_77A0
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_78BA
* mov ecx, [ebp+var_220]
* movzx edx, [ebp+var_221]
* cmp [ebp+var_210], 0B05h
* jz loc_77CC
* mov eax, 0FFFFFED3h
* jmp loc_78BA
* lea eax, [ecx-24h]
* cmp eax, 200h
* ja loc_77DB
* cmp edx, 1
* jz loc_77EE
* cmp ecx, 20h
* jnz loc_7847
* cmp edx, 1
* jnz loc_7847
* cmp [ebp+var_208], 0
* jz loc_7847
* mov esi, [ebp+var_228]
* mov eax, [esi+286Bh]
* mov edi, [ebp+var_22C]
* cmp [edi+18h], eax
* jnz loc_7847
* mov esi, [ebp+var_22C]
* mov eax, [esi+1Ch]
* test eax, eax
* jnz loc_78BA
* mov edi, [ebp+var_22C]
* mov eax, [edi+20h]
* and eax, 3000FFFFh
* cmp eax, 10000808h
* jnz loc_7847
* mov esi, [ebp+var_22C]
* mov dx, [esi+22h]
* and edx, 0FFFh
* lea eax, [edx+3]
* and al, 0FCh
* add eax, 24h
* cmp ecx, eax
* jz loc_7850
* mov eax, 0FFFFFED4h
* jmp loc_78BA
* mov edi, [ebp+arg_14]
* mov eax, [edi]
* cmp edx, eax
* ja loc_788C
* push edx
* mov esi, [ebp+arg_10]
* push esi
* mov eax, [ebp+var_22C]
* add eax, 24h
* push eax
* call _bcopy
* mov edi, [ebp+var_22C]
* mov si, [edi+22h]
* and esi, 0FFFh
* mov edi, [ebp+arg_14]
* mov [edi], esi
* mov eax, [ebp+var_208]
* jmp loc_78BA
* push eax
* mov edi, [ebp+arg_10]
* push edi
* mov eax, [ebp+var_22C]
* add eax, 24h
* push eax
* call _bcopy
* mov esi, [ebp+var_22C]
* mov di, [esi+22h]
* and edi, 0FFFh
* mov esi, [ebp+arg_14]
* mov [esi], edi
* mov eax, 0FFFFFECDh
* lea esp, [ebp-238h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOCallDeviceMethod`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOCallDeviceMethod
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 888h                           mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_884]
* mov ebx, [ebp+arg_10]
* lea esi, [ebp+var_880]
* mov [ebp+var_888], esi
* mov edi, [ebp+var_884]
* mov edi, [ebp+var_884]
* mov edi, [edi+1473h]
* mov [ebp+var_868], edi
* mov esi, [ebp+arg_4]
* mov [ebp+var_864], esi
* mov edi, [ebp+var_884]
* mov edi, [ebp+var_884]
* mov edi, [edi+1477h]
* mov [ebp+var_860], edi
* lea edx, [ebp+var_85C]
* mov eax, [ebp+arg_8]
* mov edi, edx
* mov esi, eax
* cld
* mov ecx, 14h
* movsd
* mov esi, [ebp+var_884]
* mov esi, [ebp+var_884]
* mov esi, [esi+147Bh]
* mov [ebp+var_80C], esi
* cmp ebx, 800h
* ja loc_8DF9
* push ebx
* lea eax, [ebp+var_808]
* push eax
* mov edi, [ebp+arg_C]
* push edi
* call _bcopy
* mov edx, ebx
* and dh, 0Fh
* mov ax, word ptr [ebp+var_80C+2]
* and ax, 0F000h
* or ax, dx
* mov word ptr [ebp+var_80C+2], ax
* lea eax, [ebx+3]
* mov edx, eax
* and dl, 0FCh
* mov eax, [ebp+var_888]
* add eax, edx
* mov esi, [ebp+var_884]
* mov esi, [ebp+var_884]
* mov esi, [esi+147Fh]
* mov [eax+78h], esi
* mov edi, [ebp+arg_14]
* mov edi, [edi]
* mov [eax+7Ch], edi
* mov [ebp+var_87D], 1
* add edx, 80h
* mov [ebp+var_87C], edx
* mov [ebp+var_878], 100h
* mov esi, [ebp+arg_0]
* mov [ebp+var_870], esi
* call _mig_get_reply_port
* mov [ebp+var_874], eax
* mov [ebp+var_86C], 0AB3h
* push 0
* push 0
* push 82Ch
* push 0
* mov edi, [ebp+var_888]
* push edi
* call _msg_rpc
* mov ebx, eax
* add esp, 20h
* test ebx, ebx
* jz loc_8CB8
* cmp ebx, 0FFFFFF36h
* jnz loc_8CB0
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_8DFE
* mov ebx, [ebp+var_87C]
* movzx edx, [ebp+var_87D]
* cmp [ebp+var_86C], 0B17h
* jz loc_8CDC
* mov eax, 0FFFFFED3h
* jmp loc_8DFE
* lea eax, [ebx-2Ch]
* cmp eax, 800h
* ja loc_8CEB
* cmp edx, 1
* jz loc_8D0A
* cmp ebx, 20h
* jnz loc_8D8B
* cmp edx, 1
* jnz loc_8D8B
* cmp [ebp+var_864], 0
* jz loc_8D8B
* mov esi, [ebp+var_884]
* mov eax, [esi+1483h]
* mov edi, [ebp+var_888]
* cmp [edi+18h], eax
* jnz loc_8D8B
* mov esi, [ebp+var_888]
* mov eax, [esi+1Ch]
* test eax, eax
* jnz loc_8DFE
* mov edi, [ebp+var_884]
* mov eax, [edi+1487h]
* mov esi, [ebp+var_888]
* cmp [esi+20h], eax
* jnz loc_8D8B
* mov edi, [ebp+var_888]
* mov esi, [edi+24h]
* mov edi, [ebp+arg_14]
* mov [edi], esi
* mov edi, [ebp+var_888]
* mov eax, [edi+28h]
* and eax, 3000FFFFh
* cmp eax, 10000808h
* jnz loc_8D8B
* mov esi, [ebp+var_888]
* mov cx, [esi+2Ah]
* and ecx, 0FFFh
* lea eax, [ecx+3]
* mov edx, eax
* and dl, 0FCh
* lea eax, [edx+2Ch]
* cmp ebx, eax
* jz loc_8D94
* mov eax, 0FFFFFED4h
* jmp loc_8DFE
* mov edi, [ebp+arg_1C]
* mov eax, [edi]
* cmp ecx, eax
* ja loc_8DD0
* push ecx
* mov esi, [ebp+arg_18]
* push esi
* mov eax, [ebp+var_888]
* add eax, 2Ch
* push eax
* call _bcopy
* mov edi, [ebp+var_888]
* mov si, [edi+2Ah]
* and esi, 0FFFh
* mov edi, [ebp+arg_1C]
* mov [edi], esi
* mov eax, [ebp+var_864]
* jmp loc_8DFE
* push eax
* mov edi, [ebp+arg_18]
* push edi
* mov eax, [ebp+var_888]
* add eax, 2Ch
* push eax
* call _bcopy
* mov esi, [ebp+var_888]
* mov di, [esi+2Ah]
* and edi, 0FFFh
* mov esi, [ebp+arg_1C]
* mov [esi], edi
* mov eax, 0FFFFFECDh
* lea esp, [ebp-894h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `__IOGetEISADeviceConfig`

Accepted `intentional-mismatch` (local stub vs Apple __TEXT body).

```
__IOGetEISADeviceConfig
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 150h                           mov eax, 0FFFFFFFFh
* push edi
* push esi
* push ebx
* call $+5
* pop [ebp+var_148]
* mov esi, [ebp+arg_8]
* lea edi, [ebp+var_144]
* mov [ebp+var_141], 1
* mov [ebp+var_140], 18h
* mov [ebp+var_13C], 100h
* mov ecx, [ebp+arg_0]
* mov [ebp+var_134], ecx
* call _mig_get_reply_port
* mov [ebp+var_138], eax
* mov [ebp+var_130], 0AA4h
* push 0
* push 0
* push 144h
* push 0
* push edi
* call _msg_rpc
* mov ebx, eax
* add esp, 14h
* test ebx, ebx
* jz loc_7C88
* cmp ebx, 0FFFFFF36h
* jnz loc_7C80
* call _mig_dealloc_reply_port
* mov eax, ebx
* jmp loc_7F46
* mov ecx, [ebp+var_140]
* mov [ebp+var_150], ecx
* movzx edx, [ebp+var_141]
* cmp [ebp+var_130], 0B08h
* jz loc_7CB4
* mov eax, 0FFFFFED3h
* jmp loc_7F46
* mov eax, [ebp+var_150]
* add eax, 0FFFFFFD0h
* cmp eax, 114h
* ja loc_7CC9
* cmp edx, 1
* jz loc_7CEC
* cmp [ebp+var_150], 20h
* jnz loc_7EDF
* cmp edx, 1
* jnz loc_7EDF
* cmp [ebp+var_128], 0
* jz loc_7EDF
* mov ecx, [ebp+var_148]
* mov eax, [ecx+2337h]
* cmp [edi+18h], eax
* jnz loc_7EDF
* mov eax, [edi+1Ch]
* test eax, eax
* jnz loc_7F46
* mov eax, [edi+20h]
* and eax, 3000FFFFh
* cmp eax, 10002002h
* jnz loc_7EDF
* mov dx, [edi+22h]
* and edx, 0FFFh
* lea ebx, ds:0[edx*4]
* lea eax, [ebx+30h]
* cmp [ebp+var_150], eax
* jb loc_7EDF
* sub [ebp+var_150], ebx
* mov eax, [esi]
* cmp edx, eax
* jbe loc_7D70
* shl eax, 2
* push eax
* mov ecx, [ebp+arg_4]
* push ecx
* lea eax, [edi+24h]
* push eax
* call _bcopy
* mov di, [edi+22h]
* and edi, 0FFFh
* mov [esi], edi
* jmp loc_7F41
* push ebx
* mov ecx, [ebp+arg_4]
* push ecx
* lea eax, [edi+24h]
* push eax
* call _bcopy
* mov cx, [edi+22h]
* and ecx, 0FFFh
* mov [esi], ecx
* lea esi, [ebx+edi]
* lea edi, [esi-1Ch]
* mov eax, [esi+24h]
* and eax, 3000FFFFh
* add esp, 0Ch
* cmp eax, 10002002h
* jnz loc_7EDF
* mov dx, [esi+26h]
* and edx, 0FFFh
* lea ebx, ds:0[edx*4]
* lea eax, [ebx+30h]
* cmp [ebp+var_150], eax
* jb loc_7EDF
* sub [ebp+var_150], ebx
* mov ecx, [ebp+arg_10]
* mov eax, [ecx]
* cmp edx, eax
* jbe loc_7DFC
* shl eax, 2
* push eax
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, [esi+28h]
* push eax
* call _bcopy
* mov si, [esi+26h]
* and esi, 0FFFh
* mov ecx, [ebp+arg_10]
* mov [ecx], esi
* jmp loc_7F41
* push ebx
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, [esi+28h]
* push eax
* call _bcopy
* mov si, [esi+26h]
* and esi, 0FFFh
* mov ecx, [ebp+arg_10]
* mov [ecx], esi
* lea esi, [ebx+edi]
* lea edi, [esi-10h]
* mov eax, [esi+44h]
* and eax, 3000FFFFh
* add esp, 0Ch
* cmp eax, 10002002h
* jnz loc_7EDF
* mov dx, [esi+46h]
* and edx, 0FFFh
* lea ebx, ds:0[edx*4]
* lea eax, [ebx+30h]
* cmp [ebp+var_150], eax
* jb loc_7EDF
* sub [ebp+var_150], ebx
* mov eax, edx
* shr eax, 1
* mov ecx, [ebp+arg_18]
* mov edx, [ecx]
* cmp eax, edx
* jbe loc_7E90
* lea eax, ds:0[edx*8]
* push eax
* mov ecx, [ebp+arg_14]
* push ecx
* lea eax, [esi+48h]
* push eax
* call _bcopy
* mov ax, [esi+46h]
* and eax, 0FFFh
* shr eax, 1
* mov ecx, [ebp+arg_18]
* jmp loc_7F3F
* push ebx
* mov ecx, [ebp+arg_14]
* push ecx
* lea eax, [esi+48h]
* push eax
* call _bcopy
* mov ax, [esi+46h]
* and eax, 0FFFh
* shr eax, 1
* mov ecx, [ebp+arg_18]
* mov [ecx], eax
* lea esi, [ebx+edi]
* mov eax, [esi+58h]
* and eax, 3000FFFFh
* add esp, 0Ch
* cmp eax, 10002002h
* jnz loc_7EDF
* mov dx, [esi+5Ah]
* and edx, 0FFFh
* lea ebx, ds:0[edx*4]
* lea eax, [ebx+30h]
* cmp [ebp+var_150], eax
* jz loc_7EE8
* mov eax, 0FFFFFED4h
* jmp loc_7F46
* mov eax, edx
* shr eax, 1
* mov ecx, [ebp+arg_20]
* mov edx, [ecx]
* cmp eax, edx
* ja loc_7F1C
* push ebx
* mov ecx, [ebp+arg_1C]
* push ecx
* lea eax, [esi+5Ch]
* push eax
* call _bcopy
* mov ax, [esi+5Ah]
* and eax, 0FFFh
* shr eax, 1
* mov ecx, [ebp+arg_20]
* mov [ecx], eax
* mov eax, [ebp+var_128]
* jmp loc_7F46
* lea eax, ds:0[edx*8]
* push eax
* mov ecx, [ebp+arg_1C]
* push ecx
* lea eax, [esi+5Ch]
* push eax
* call _bcopy
* mov ax, [esi+5Ah]
* and eax, 0FFFh
* shr eax, 1
* mov ecx, [ebp+arg_20]
* mov [ecx], eax
* mov eax, 0FFFFFECDh
* lea esp, [ebp-15Ch]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `_IOSleep` msg_header local (2026-09-17)

Initialize a 24-byte `msg_header` local (`local_port = sleepPort`, `size = sizeof(msg)`) and pass `&msg` to `msg_receive`. `sleepPort` is file-static so gcc emits a direct PIC load. Leftover is PIC displacement of `_sleepPort`. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `CBB7ACF7C34F165F03B0DD5F1AABCF1A8B3DDC2E304F2114BD9EB6C270C868A3` (299556). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
_IOSleep
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 18h                            sub esp, 18h
  call $+5                                call $+5
  pop eax                                 pop eax
* mov eax, ds:(_sleepPort - 6C27h)[eax]   mov eax, ds:(_sleepPort - 3813h)[eax]
  mov [ebp+var_C], eax                    mov [ebp+var_C], eax
  mov [ebp+var_14], 18h                   mov [ebp+var_14], 18h
  mov edx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
  push edx                                push edx
  push 500h                               push 500h
  lea eax, [ebp+var_18]                   lea eax, [ebp+var_18]
  push eax                                push eax
  call _msg_receive                       call _msg_receive
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[NXLock init]` zeroing order (2026-09-17)

Zero mutex/condition/reserved2/waiters/locked in Apple store order and omit unused reserved1/reserved3 stores. Leftover is PIC selector / super_class displacement. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `CEE7E77323946BD2C64A6F1DD296FB41904563274ACCC5479DD6FA9DCE7410AE` (299532). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
-[NXLock init]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push ebx                                push ebx
  call $+5                                call $+5
  pop eax                                 pop eax
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, eax                            mov edx, eax
* mov edx, [edx+3160h]                    mov edx, [edx+6BDCh]
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov eax, ds:(off_C2B0 - 8EF8h)[eax]     mov eax, ds:(stru_A0F4.ext - 3428h)[eax]
  mov [ebp+var_8.super_class], eax        mov [ebp+var_8.super_class], eax
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  push 1Ch                                push 1Ch
  call _malloc                            call _malloc
  mov [ebx+4], eax                        mov [ebx+4], eax
* mov dword ptr ds:(loc_8EF8 - 8EF8h)[eax], 0  mov dword ptr ds:(loc_3428 - 3428h)[eax], 0
  mov dword ptr [eax+8], 0                mov dword ptr [eax+8], 0
  mov dword ptr [eax+10h], 0              mov dword ptr [eax+10h], 0
  mov dword ptr [eax+0Ch], 0              mov dword ptr [eax+0Ch], 0
  mov byte ptr [eax+18h], 0               mov byte ptr [eax+18h], 0
  mov eax, ebx                            mov eax, ebx
  mov ebx, [ebp+var_C]                    mov ebx, [ebp+var_C]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `_IOFindValueForName` for-loop table walk (2026-09-17)

Walk the name/value table with a `for` over dual pointers instead of `if` plus `do-while`. Leftover is instruction scheduling of independent loads/adds. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `F1D978864204107A5B08BC6CBDA5395CAB5A139AC8550CC72303D7079406FDEE` (299452). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
_IOFindValueForName
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
*                                         mov edi, [ebp+arg_8]
  mov esi, [ebp+arg_4]                    mov esi, [ebp+arg_4]
* mov edi, [ebp+arg_8]                    lea ebx, [esi+4]
  cmp dword ptr [esi+4], 0                cmp dword ptr [esi+4], 0
* jz loc_715F                             jz loc_39CF
* lea ebx, [esi+4]
  nop                                     nop
  nop                                     nop
  nop                                     nop
  mov edx, [ebp+__s2]                     mov edx, [ebp+__s2]
  push edx                                push edx
  mov edx, [ebx]                          mov edx, [ebx]
  push edx                                push edx
  call _strcmp                            call _strcmp
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jnz loc_7154                            jnz loc_39C4
  mov esi, [esi]                          mov esi, [esi]
  mov [edi], esi                          mov [edi], esi
  xor eax, eax                            xor eax, eax
* jmp loc_7164                            jmp loc_39D4
*                                         add esi, 8
  add ebx, 8                              add ebx, 8
* add esi, 8
  cmp dword ptr [ebx], 0                  cmp dword ptr [ebx], 0
* jnz loc_7138                            jnz loc_39A8
  mov eax, 0FFFFFD3Eh                     mov eax, 0FFFFFD3Eh
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `_IOFindNameForValue` for-loop table walk (2026-09-17)

Walk the name/value table with a `for` over dual pointers instead of `if` plus `do-while`. Leftover is instruction scheduling of lea/adds plus PIC sprintf displacement. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `FEAC10FEB02CCF2049FD1B5D2916C740BD4C6C45C198FEB5A5A21FC2671E7FB3` (299404). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
_IOFindNameForValue
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  mov edx, [ebp+arg_4]                    mov edx, [ebp+arg_4]
*                                         lea eax, [edx+4]
  cmp dword ptr [edx+4], 0                cmp dword ptr [edx+4], 0
* jz loc_7103                             jz loc_3A0F
* lea eax, [edx+4]
  nop                                     nop
  nop                                     nop
  nop                                     nop
  cmp [edx], ecx                          cmp [edx], ecx
* jnz loc_70F8                            jnz loc_3A04
  mov eax, [eax]                          mov eax, [eax]
* jmp loc_7119                            jmp loc_3A25
*                                         add edx, 8
  add eax, 8                              add eax, 8
* add edx, 8
  cmp dword ptr [eax], 0                  cmp dword ptr [eax], 0
* jnz loc_70F0                            jnz loc_39FC
  push ecx                                push ecx
* lea eax, (aDDUndefined - 70DDh)[ebx]    lea eax, (aDDUndefined - 39E9h)[ebx]
  push eax                                push eax
* add ebx, 3A77h                          add ebx, 4B3Bh
  push ebx                                push ebx
  call _sprintf                           call _sprintf
  mov eax, ebx                            mov eax, ebx
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `+[IODeviceMaster new]` self alloc (2026-09-17)

Allocate the singleton with `[self alloc]` instead of `[super alloc]` so the tool calls `_objc_msgSend` like Apple. Leftover is PIC displacement of `_thisTasksId` and the alloc selector. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `D540CDBB13174DE4F60CBFBDEBB70714F3DEAFCCFFB0E1B15BAD1A017441B7F4` (299372). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
+[IODeviceMaster new]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
* cmp ds:(_thisTasksId - 6A55h)[ebx], 0   cmp ds:(_thisTasksId - 32DDh)[ebx], 0
* jnz loc_6A87                            jnz loc_330F
  mov ecx, ebx                            mov ecx, ebx
* mov ecx, [ecx+55DBh]                    mov ecx, [ecx+6D23h]
  push ecx                                push ecx
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  push ecx                                push ecx
  call _objc_msgSend                      call _objc_msgSend
* mov ds:(_thisTasksId - 6A55h)[ebx], eax  mov ds:(_thisTasksId - 32DDh)[ebx], eax
  call _device_master_self                call _device_master_self
  mov edx, eax                            mov edx, eax
* mov eax, ds:(_thisTasksId - 6A55h)[ebx]  mov eax, ds:(_thisTasksId - 32DDh)[ebx]
  mov [eax+4], edx                        mov [eax+4], edx
* mov eax, ds:(_thisTasksId - 6A55h)[ebx]  mov eax, ds:(_thisTasksId - 32DDh)[ebx]
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpMemory matches:]` alignment local (2026-09-17)

Keep `_alignment` in a local and compute the aligned base only when it is nonzero. Reloc IDA `masked_equal`. Tool leftover is PIC selector displacement (`paMinBase` vs `paMinBase_0`) plus jump labels. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `6CD74564E9E7687387C575FB1483B02E7F7E9CC0C3F8677C8DEECBABA5B2A23D` (299384). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
-[pnpMemory matches:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop eax                                 pop eax
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
* mov eax, ds:(paMinBase - 49A3h)[eax]    mov eax, ds:(paMinBase_0 - 6C8Fh)[eax]
  push eax                                push eax
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov ecx, eax                            mov ecx, eax
  mov edi, [ebx+0Ch]                      mov edi, [ebx+0Ch]
  test edi, edi                           test edi, edi
* jz loc_49CB                             jz loc_6CB7
  lea eax, [edi+ecx-1]                    lea eax, [edi+ecx-1]
  xor edx, edx                            xor edx, edx
  div edi                                 div edi
  imul eax, edi                           imul eax, edi
  cmp ecx, eax                            cmp ecx, eax
* jnz loc_49E0                            jnz loc_6CCC
  cmp [ebx+4], ecx                        cmp [ebx+4], ecx
* ja loc_49E0                             ja loc_6CCC
  cmp [ebx+8], ecx                        cmp [ebx+8], ecx
* jb loc_49E0                             jb loc_6CCC
  mov eax, 1                              mov eax, 1
* jmp loc_49E2                            jmp loc_6CCE
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpMemory setControl:]` omit width zeros (2026-09-17)

Omit reciprocal `_bit16=0`/`_bit8=0` stores and the explicit `return self` so the width cases share Apple's tails. Leftover is char-arg vs Apple pointer reload, PIC jump-table register, and jump labels. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `B07D6F3DA59E6C35CFAA59ECEE240873675F6070219B2A45C248D3E7DE5D1854` (299324). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
-[pnpMemory setControl:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 4                              sub esp, 4
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  mov ecx, [ebp+self]                     mov ecx, [ebp+self]
* mov edi, [ebp+arg_8]                    mov dl, [ebp+arg_8]
* mov al, [edi]                           mov [ebp+var_4], dl
*                                         mov al, dl
  shr al, 3                               shr al, 3
* mov edx, eax                            mov edi, 3
* and edx, 3                              and edi, eax
* mov [ebp+var_4], edx                    cmp edi, 3
* cmp edx, 3                              ja def_6D1A
* ja def_4AAC                             lea eax, (jpt_6D1A - 6CF6h)[esi]
* lea eax, (jpt_4AAC - 4A8Ah)[esi]        add eax, ds:(jpt_6D1A - 6D1Ch)[eax+edi*4]
* add eax, ds:(jpt_4AAC - 4AB0h)[eax+edx*4]
  jmp eax                                 jmp eax
  mov byte ptr [ecx+1Ah], 1               mov byte ptr [ecx+1Ah], 1
* jmp def_4AAC                            jmp def_6D1A
  mov byte ptr [ecx+1Ah], 1               mov byte ptr [ecx+1Ah], 1
  mov byte ptr [ecx+19h], 1               mov byte ptr [ecx+19h], 1
* jmp def_4AAC                            jmp def_6D1A
  mov byte ptr [ecx+1Bh], 1               mov byte ptr [ecx+1Bh], 1
* mov al, [edi]                           mov al, [ebp+var_4]
  shr al, 6                               shr al, 6
  and al, 1                               and al, 1
  mov [ecx+14h], al                       mov [ecx+14h], al
* mov al, [edi]                           mov al, [ebp+var_4]
  shr al, 5                               shr al, 5
  and al, 1                               and al, 1
  mov [ecx+15h], al                       mov [ecx+15h], al
* mov al, [edi]                           mov al, [ebp+var_4]
  shr al, 2                               shr al, 2
  and al, 1                               and al, 1
  mov [ecx+16h], al                       mov [ecx+16h], al
* mov al, [edi]                           mov al, [ebp+var_4]
  shr al, 1                               shr al, 1
  and al, 1                               and al, 1
  mov [ecx+17h], al                       mov [ecx+17h], al
* mov dl, [edi]                           mov dl, [ebp+var_4]
  and dl, 1                               and dl, 1
  mov [ecx+18h], dl                       mov [ecx+18h], dl
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpIRQ initFrom:Length:]` mask/flags expressions (2026-09-17)

Load the IRQ mask and flag byte from the buffer expression instead of locals so the walk reloads like Apple. Leftover is extra buffer-pointer copy / PIC / jump labels. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `0EE81F988F57722E740998F9301339E3749BD35AE61D3945EE4D15CEA0272437` (299252). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

```
-[pnpIRQ initFrom:Length:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 0Ch                            sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop edi
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
* mov edi, [ebp+arg_8]                    mov esi, [ebp+arg_8]
* mov ecx, esi                            mov ecx, edi
* mov ecx, [ecx+7E36h]                    mov ecx, [ecx+392Ah]
  push ecx                                push ecx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov ecx, esi                            mov ecx, edi
* mov ecx, [ecx+803Eh]                    mov ecx, [ecx+3B86h]
  mov [ebp+var_8.super_class], ecx        mov [ebp+var_8.super_class], ecx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
* mov [ebp+var_C], edi
  mov dword ptr [ebx+44h], 0              mov dword ptr [ebx+44h], 0
  xor edx, edx                            xor edx, edx
  add esp, 8                              add esp, 8
* mov ecx, [ebp+var_C]                    nop
* movzx eax, word ptr [ecx]               nop
*                                         nop
*                                         movzx eax, word ptr [esi]
  bt eax, edx                             bt eax, edx
* jnb loc_426D                            jnb loc_6722
  mov eax, [ebx+44h]                      mov eax, [ebx+44h]
  mov [ebx+eax*4+4], edx                  mov [ebx+eax*4+4], edx
  inc dword ptr [ebx+44h]                 inc dword ptr [ebx+44h]
  inc edx                                 inc edx
  cmp edx, 0Fh                            cmp edx, 0Fh
* jle loc_4258                            jle loc_6710
  mov byte ptr [ebx+48h], 1               mov byte ptr [ebx+48h], 1
  cmp [ebp+arg_C], 2                      cmp [ebp+arg_C], 2
* jle loc_42A6                            jle loc_675B
* mov cl, [edi+2]                         mov cl, [esi+2]
  and cl, 1                               and cl, 1
  mov [ebx+48h], cl                       mov [ebx+48h], cl
* mov al, [edi+2]                         mov al, [esi+2]
  shr al, 1                               shr al, 1
  and al, 1                               and al, 1
  mov [ebx+49h], al                       mov [ebx+49h], al
* mov al, [edi+2]                         mov al, [esi+2]
  shr al, 2                               shr al, 2
  and al, 1                               and al, 1
  mov [ebx+4Ah], al                       mov [ebx+4Ah], al
* mov al, [edi+2]                         mov al, [esi+2]
  shr al, 3                               shr al, 3
  and al, 1                               and al, 1
  mov [ebx+4Bh], al                       mov [ebx+4Bh], al
* cmp ds:(_verbose - 4222h)[esi], 0       mov eax, ds:(_verbose_ptr - 66DAh)[edi]
* jz loc_42BC                             cmp byte ptr [eax], 0
* mov esi, ds:(paPrint - 4222h)[esi]      jz loc_6773
* push esi                                mov edi, ds:(paPrint - 66DAh)[edi]
*                                         push edi
  push ebx                                push ebx
  call _objc_msgSend                      call _objc_msgSend
  mov eax, ebx                            mov eax, ebx
* lea esp, [ebp-18h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpIOPort matches:]` alignment local (2026-09-17)

Keep `_alignment` in a 32-bit local, `otherBase` 16-bit, and skip the div when alignment is zero. Leftover is PIC selector plus register vs stack for the divisor. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `A4B5420B1CA4D7E6C320DE35742323181872B8C6E784EA4457CBEF766D2D60A8` (299280). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

```
-[pnpIOPort matches:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 4                              sub esp, 4
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop eax                                 pop ecx
* mov esi, [ebp+self]                     mov ebx, [ebp+self]
* mov eax, ds:(paMinBase - 467Ah)[eax]    mov ecx, ds:(paMinBase_0 - 6596h)[ecx]
*                                         push ecx
*                                         mov eax, [ebp+arg_8]
  push eax                                push eax
* mov edx, [ebp+arg_8]
* push edx
  call _objc_msgSend                      call _objc_msgSend
* mov ebx, eax                            mov ecx, eax
* movzx ecx, bx                           movzx edi, word ptr [ebx+8]
* mov eax, ecx                            movzx esi, cx
* movzx edx, word ptr [esi+8]             test edi, edi
* mov [ebp+var_4], edx                    jz loc_65C6
* test edx, edx                           lea esi, [edi+esi-1]
* jnz loc_46A4                            mov eax, esi
* mov edi, ecx
* jmp loc_46B6
* mov edx, [ebp+var_4]
* lea eax, [edx+eax-1]
  xor edx, edx                            xor edx, edx
* div [ebp+var_4]                         div edi
* mov edi, [ebp+var_4]                    mov esi, eax
* imul edi, eax                           imul esi, edi
* cmp ecx, edi                            movzx eax, cx
* jnz loc_46D0                            cmp eax, esi
* cmp [esi+4], bx                         jnz loc_65E0
* ja loc_46D0                             cmp [ebx+4], cx
* cmp [esi+6], bx                         ja loc_65E0
* jb loc_46D0                             cmp [ebx+6], cx
*                                         jb loc_65E0
  mov eax, 1                              mov eax, 1
* jmp loc_46D2                            jmp loc_65E2
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 -[PnPResource objectAt:Using:] if/else if dispatch (2026-09-17)

Flatten index dispatch to if (index < _depStart) / else if / else so the outer compare is Apple jle. Leftover is the usingList local versus Apple nested [list] plus inner jl/jge polarity and PIC. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA 37C59B6941A1C1EF6DBA48590CB7607337817E9A429BFEE96FC50386E3FC6ADD (299280). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

`
-[PnPResource objectAt:Using:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
*                                         sub esp, 4
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
  mov edi, [ebp+self]                     mov edi, [ebp+self]
  mov esi, [ebp+arg_8]                    mov esi, [ebp+arg_8]
* mov ecx, ebx                            mov edx, ebx
* mov ecx, [ecx+7125h]                    mov edx, [edx+4E66h]
* push ecx                                push edx
* mov ecx, ebx                            mov edx, [ebp+arg_C]
* mov ecx, [ecx+714Dh]                    push edx
* push ecx
* mov ecx, [ebp+arg_C]
* push ecx
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8                              mov [ebp+var_4], eax
* push eax                                mov edx, ebx
*                                         mov edx, [edx+4E0Eh]
*                                         push edx
*                                         mov edx, [ebp+var_4]
*                                         push edx
  call _objc_msgSend                      call _objc_msgSend
* mov edx, eax                            add esp, 10h
* add esp, 8
  cmp [edi+8], esi                        cmp [edi+8], esi
* jle loc_4F58                            jle loc_5260
  push esi                                push esi
* jmp loc_4F90                            mov ebx, ds:(paObjectat - 521Ah)[ebx]
* mov eax, edx                            push ebx
*                                         mov edi, [edi+4]
*                                         push edi
*                                         jmp loc_5289
  add eax, [edi+8]                        add eax, [edi+8]
  cmp esi, eax                            cmp esi, eax
* jge loc_4F88                            jl loc_5278
*                                         add eax, esi
*                                         push eax
*                                         mov ebx, ds:(paObjectat - 521Ah)[ebx]
*                                         push ebx
*                                         mov edi, [edi+4]
*                                         push edi
*                                         jmp loc_5289
  mov eax, esi                            mov eax, esi
  sub eax, [edi+8]                        sub eax, [edi+8]
  push eax                                push eax
* mov ecx, ebx                            mov ebx, ds:(paObjectat - 521Ah)[ebx]
* mov ecx, [ecx+711Dh]
* push ecx
* mov ebx, ds:(paList_0 - 4F1Fh)[ebx]
  push ebx                                push ebx
* mov ecx, [ebp+arg_C]                    mov edx, [ebp+var_4]
* push ecx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8                              lea esp, [ebp-10h]
* push eax
* jmp loc_4F9B
* mov eax, edx
* add eax, [edi+8]
* add eax, esi
* push eax
* mov ebx, ds:(off_C03C - 4F1Fh)[ebx]
* push ebx
* mov edi, [edi+4]
* push edi
* call _objc_msgSend
* lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 `_IOInitGeneralFuncs` statement order (2026-09-17)

Swap of calloutChain head/tail stores missed Apple tail-then-head and was reverted. Leftover is PIC GOT versus lea of `_calloutChain` plus `objc_getClass`/`sel_getUid` versus a class pointer. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `37C59B6941A1C1EF6DBA48590CB7607337817E9A429BFEE96FC50386E3FC6ADD` (299280). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
_IOInitGeneralFuncs
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
*                                         push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop ebx                                 pop ebx
* lea eax, (_calloutChain - 7179h)[ebx]   mov eax, ebx
* mov ds:(dword_AB48 - 7179h)[ebx], eax   mov eax, [eax+494Ah]
* mov ds:(_calloutChain - 7179h)[ebx], eax  add eax, 4
* mov edx, ebx                            mov edx, ds:(off_802C - 36E2h)[ebx]
* mov edx, [edx+4EA7h]                    mov [eax], edx
* push edx                                mov [edx], edx
* mov edx, ebx                            lea eax, (aNxlock - 36E2h)[ebx]
* mov edx, [edx+4F9Fh]                    push eax
* push edx                                call _objc_getClass
*                                         mov esi, eax
*                                         lea eax, (aNew - 36E2h)[ebx]
*                                         push eax
*                                         call _sel_getUid
*                                         push eax
*                                         push esi
  call _objc_msgSend                      call _objc_msgSend
* mov ds:(_calloutLock - 7179h)[ebx], eax  mov edx, eax
* lea eax, (_sleepPort - 7179h)[ebx]      mov eax, ds:(off_8028 - 36E2h)[ebx]
*                                         mov [eax], edx
*                                         lea eax, (_sleepPort - 36E2h)[ebx]
  push eax                                push eax
* mov eax, ds:(_task_self__ptr - 7179h)[ebx]  mov eax, ds:(off_8024 - 36E2h)[ebx]
*                                         mov eax, [eax]
  mov eax, [eax]                          mov eax, [eax]
  push eax                                push eax
  call _port_allocate                     call _port_allocate
* add esp, 10h                            add esp, 18h
  test eax, eax                           test eax, eax
* jz loc_71D4                             jz loc_3750
* lea eax, (aIoinitgeneralf - 7179h)[ebx]  lea eax, (aIoinitgeneralf - 36E2h)[ebx]
  push eax                                push eax
  call _IOLog                             call _IOLog
  add esp, 4                              add esp, 4
  push 0                                  push 0
* lea eax, (_calloutThread - 7179h)[ebx]  mov ebx, ds:(off_8020 - 36E2h)[ebx]
* push eax                                push ebx
  call _IOForkThread                      call _IOForkThread
* mov ebx, [ebp+var_4]                    lea esp, [ebp-8]
*                                         pop ebx
*                                         pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpDMA initFrom:Length:]` do-while mask walk (2026-09-17)

Walk the DMA channel mask with a do-while so the compiler still emits Apple `bt` / `cmp 7` / `jle`. Leftover is explicit `_count = 0` plus `data[1]` versus Apple's post-increment buffer pointer and PIC verbose. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `92B6A5C3723F7882C31C9E060460D36C29FF14CE0F6A915E5215BD25258CE991` (299304). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

```
-[pnpDMA initFrom:Length:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 0Ch                            sub esp, 0Ch
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop edi                                 pop esi
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
* mov esi, [ebp+arg_8]                    mov edi, [ebp+arg_8]
* mov ecx, edi                            mov ecx, esi
* mov ecx, [ecx+7B3Ah]                    mov ecx, [ecx+3F52h]
  push ecx                                push ecx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov ecx, edi                            mov ecx, esi
* mov ecx, [ecx+7D1Ah]                    mov ecx, [ecx+415Eh]
  mov [ebp+var_8.super_class], ecx        mov [ebp+var_8.super_class], ecx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
* mov al, [esi]                           mov dword ptr [ebx+24h], 0
* inc esi
  xor edx, edx                            xor edx, edx
  add esp, 8                              add esp, 8
* and eax, 0FFh                           movzx ecx, byte ptr [edi]
* mov [ebp+var_C], eax                    mov [ebp+var_C], ecx
* nop
* nop
  nop                                     nop
  mov ecx, [ebp+var_C]                    mov ecx, [ebp+var_C]
  bt ecx, edx                             bt ecx, edx
* jnb loc_456A                            jnb loc_60FE
  mov eax, [ebx+24h]                      mov eax, [ebx+24h]
  mov [ebx+eax*4+4], edx                  mov [ebx+eax*4+4], edx
  inc dword ptr [ebx+24h]                 inc dword ptr [ebx+24h]
  inc edx                                 inc edx
  cmp edx, 7                              cmp edx, 7
* jle loc_4558                            jle loc_60EC
* mov edx, esi                            mov dl, [edi+1]
* mov al, [edx]                           mov eax, edx
  and eax, 3                              and eax, 3
  cmp eax, 1                              cmp eax, 1
* jz loc_4598                             jz loc_6130
* jg loc_4584                             jg loc_611C
  test eax, eax                           test eax, eax
* jz loc_458C                             jz loc_6124
* jmp loc_45A8                            jmp loc_6140
  cmp eax, 2                              cmp eax, 2
* jz loc_45A0                             jz loc_6138
* jmp loc_45A8                            jmp loc_6140
  mov byte ptr [ebx+28h], 1               mov byte ptr [ebx+28h], 1
  mov byte ptr [ebx+29h], 0               mov byte ptr [ebx+29h], 0
* jmp loc_45A8                            jmp loc_6140
  mov byte ptr [ebx+28h], 1               mov byte ptr [ebx+28h], 1
* jmp loc_45A4                            jmp loc_613C
  mov byte ptr [ebx+28h], 0               mov byte ptr [ebx+28h], 0
  mov byte ptr [ebx+29h], 1               mov byte ptr [ebx+29h], 1
* mov al, [edx]                           mov al, dl
  shr al, 2                               shr al, 2
  and al, 1                               and al, 1
  mov [ebx+2Ah], al                       mov [ebx+2Ah], al
* mov al, [edx]                           mov al, dl
  shr al, 3                               shr al, 3
  and al, 1                               and al, 1
  mov [ebx+2Bh], al                       mov [ebx+2Bh], al
* mov al, [edx]                           mov al, dl
  shr al, 4                               shr al, 4
  and al, 1                               and al, 1
  mov [ebx+2Ch], al                       mov [ebx+2Ch], al
* mov al, [edx]                           mov al, dl
  shr al, 5                               shr al, 5
  and al, 3                               and al, 3
  mov [ebx+2Dh], al                       mov [ebx+2Dh], al
* cmp ds:(_verbose - 451Eh)[edi], 0       mov eax, ds:(_verbose_ptr - 60B2h)[esi]
* jz loc_45E6                             cmp byte ptr [eax], 0
* mov edi, ds:(paPrint - 451Eh)[edi]      jz loc_6180
* push edi                                mov esi, ds:(paPrint - 60B2h)[esi]
*                                         push esi
  push ebx                                push ebx
  call _objc_msgSend                      call _objc_msgSend
  mov eax, ebx                            mov eax, ebx
  lea esp, [ebp-18h]                      lea esp, [ebp-18h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `_IODelay` in-place timestamp add (2026-09-17)

Add the microsecond delay into the timestamp locals instead of building a 64-bit expression. Leftover is explicit carry versus Apple `adc`, loop buffer reuse, extra `esi`, and `jns` versus `test`/`jge`. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `2EDFF182FD04C99A502E9F65C78C1B2A0017135A2CFE86FF99CCC0DEFEA93088` (299328). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
_IODelay
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 14h                            sub esp, 18h
*                                         push esi
  push ebx                                push ebx
  mov ebx, [ebp+arg_0]                    mov ebx, [ebp+arg_0]
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _IOGetTimestamp                    call _IOGetTimestamp
  mov eax, 3E8h                           mov eax, 3E8h
  mul ebx                                 mul ebx
* mov ecx, eax                            mov ebx, eax
* mov ebx, edx                            mov esi, edx
* add [ebp+var_8], ecx                    mov edx, [ebp+var_8]
* adc [ebp+var_4], ebx                    add [ebp+var_8], ebx
  add esp, 4                              add esp, 4
* lea ebx, [ebp+var_10]                   mov ebx, esi
* nop                                     xor esi, esi
*                                         mov [ebp+var_18], ebx
*                                         mov [ebp+var_14], esi
*                                         mov ecx, [ebp+var_18]
*                                         add ecx, [ebp+var_4]
*                                         cmp [ebp+var_8], edx
*                                         jnb loc_3ABE
*                                         inc ecx
*                                         mov [ebp+var_4], ecx
*                                         mov esi, [ebp+var_8]
*                                         lea ebx, [ebp+var_8]
  nop                                     nop
  push ebx                                push ebx
  call _IOGetTimestamp                    call _IOGetTimestamp
* mov edx, [ebp+var_8]
* sub edx, [ebp+var_10]
  add esp, 4                              add esp, 4
* test edx, edx                           mov edx, esi
* jge loc_6C7C                            sub edx, [ebp+var_8]
* mov ebx, [ebp+var_18]                   jns loc_3AC8
*                                         lea esp, [ebp-20h]
*                                         pop ebx
*                                         pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 -[PnPResource matches:Using:] count==0 else-wrap (2026-09-17)

Wrap the match loop in `else` after `if (count == 0) return YES`. Leftover is Apple's list/count and list/objectAt: stack-trick versus the `configList` local, plus PIC / register scheduling. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA D340AF35027155B5EA5961C2B28AD43903D669BEA1F6D7A43D0745AAD730CB70 (299328). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

`
-[PnPResource matches:Using:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
*                                         sub esp, 4
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop edi
* mov edx, esi                            mov edx, edi
* mov edx, [edx+72E9h]                    mov edx, [edx+4DDAh]
* push edx
* mov edx, esi
* mov edx, [edx+7311h]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8                              mov [ebp+var_4], eax
* push eax                                mov edx, edi
*                                         mov edx, [edx+4D82h]
*                                         push edx
*                                         mov edx, [ebp+var_4]
*                                         push edx
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8                              add esp, 10h
  test eax, eax                           test eax, eax
* jnz loc_4D94                            jnz loc_52E0
  mov eax, 1                              mov eax, 1
* jmp loc_4E02                            jmp loc_533E
  xor eax, eax                            xor eax, eax
* jmp loc_4E02                            jmp loc_533E
  xor ebx, ebx                            xor ebx, ebx
  nop                                     nop
  nop                                     nop
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  push ebx                                push ebx
* mov edx, esi                            mov edx, edi
* mov edx, [edx+7315h]                    mov edx, [edx+4DDEh]
  push edx                                push edx
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* mov edi, eax                            mov esi, eax
  add esp, 10h                            add esp, 10h
* test edi, edi                           test esi, esi
* jz loc_4DF8                             jz loc_5334
  push ebx                                push ebx
* mov edx, esi                            mov edx, edi
* mov edx, [edx+72E1h]                    mov edx, [edx+4D86h]
  push edx                                push edx
* mov edx, esi                            mov edx, [ebp+var_4]
* mov edx, [edx+7311h]
* push edx
* mov edx, [ebp+arg_8]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8
  push eax                                push eax
* call _objc_msgSend                      mov edx, edi
* push eax                                mov edx, [edx+4DE2h]
* mov edx, esi
* mov edx, [edx+7319h]
  push edx                                push edx
* push edi                                push esi
  call _objc_msgSend                      call _objc_msgSend
  add esp, 18h                            add esp, 18h
  test al, al                             test al, al
* jz loc_4D90                             jz loc_52DC
  inc ebx                                 inc ebx
* jmp loc_4D98                            jmp loc_52E4
  test ebx, ebx                           test ebx, ebx
  setnle al                               setnle al
  and eax, 0FFh                           and eax, 0FFh
* lea esp, [ebp-0Ch]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 -[pnpDMA matches:] else-if on otherCount (2026-09-17)

Use `else if (otherCount != 1)` after the zero-count return. Do not swap `_printf`/`_IOLog`. Leftover is Apple's double `[number]` and in-loop `dmaChannels` versus locals, plus tool `_printf` vs `_IOLog` and PIC / register scheduling. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA 76DC2014A1E41A3CE5D22614D2F2CE4570AF5B7284615B7C7E7D3D5894E1DC84 (299328). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

`
-[pnpDMA matches:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop ebx
* mov edi, [ebp+self]                     mov esi, [ebp+self]
* mov edx, esi                            mov edi, [ebp+arg_8]
* mov edx, [edx+7BC5h]                    mov ecx, ebx
* push edx                                mov ecx, [ecx+3EE5h]
* mov edx, [ebp+arg_8]                    push ecx
* push edx                                push edi
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jz loc_4503                             jz loc_6236
* mov edx, esi                            cmp eax, 1
* mov edx, [edx+7BC5h]                    jz loc_6210
* push edx                                lea eax, (aPnpdmaCanOnlyM - 61D7h)[ebx]
* mov edx, [ebp+arg_8]                    push eax
* push edx                                call _IOLog
*                                         jmp loc_6236
*                                         mov eax, 1
*                                         jmp loc_6238
*                                         mov ebx, ds:(paDmachannels_0 - 61D7h)[ebx]
*                                         push ebx
*                                         push edi
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8                              mov ebx, eax
* cmp eax, 1                              xor edx, edx
* jz loc_44D8                             cmp [esi+24h], edx
* lea eax, (aPnpdmaCanOnlyM - 448Bh)[esi]  jle loc_6236
* push eax
* call _printf
* jmp loc_4503
* mov eax, 1
* jmp loc_4505
* xor ebx, ebx
* cmp [edi+24h], ebx
* jle loc_4503
  nop                                     nop
* mov edx, esi                            nop
* mov edx, [edx+7BD5h]                    mov eax, [esi+edx*4+4]
* push edx                                cmp dword ptr ds:(loc_61D7 - 61D7h)[ebx], eax
* mov edx, [ebp+arg_8]                    jz loc_6208
* push edx                                inc edx
* call _objc_msgSend                      cmp [esi+24h], edx
* add esp, 8                              jg loc_6228
* mov eax, [eax]
* cmp [edi+ebx*4+4], eax
* jz loc_44D0
* inc ebx
* cmp [edi+24h], ebx
* jg loc_44E0
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 -[pnpIRQ matches:] else-if on otherCount (2026-09-17)

Use `else if (otherCount != 1)` after the zero-count return. Do not swap `_printf`/`_IOLog`. Leftover is Apple's double `[number]` and in-loop `irqs` versus locals, plus tool `_printf` vs `_IOLog` and PIC / register scheduling. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA 2897B573A7D2D8C2D05A218713E8312674B609C98A09C84010EC76DB708AA61B (299328). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

`
-[pnpIRQ matches:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop ebx
* mov edi, [ebp+self]                     mov esi, [ebp+self]
* mov edx, esi                            mov edi, [ebp+arg_8]
* mov edx, [edx+7EC1h]                    mov ecx, ebx
* push edx                                mov ecx, [ecx+3911h]
* mov edx, [ebp+arg_8]                    push ecx
* push edx                                push edi
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jz loc_4207                             jz loc_680A
* mov edx, esi                            cmp eax, 1
* mov edx, [edx+7EC1h]                    jz loc_67E4
* push edx                                lea eax, (aPnpirqCanOnlyM - 67ABh)[ebx]
* mov edx, [ebp+arg_8]                    push eax
* push edx                                call _IOLog
*                                         jmp loc_680A
*                                         mov eax, 1
*                                         jmp loc_680C
*                                         mov ebx, ds:(paIrqs_0 - 67ABh)[ebx]
*                                         push ebx
*                                         push edi
  call _objc_msgSend                      call _objc_msgSend
* add esp, 8                              mov ebx, eax
* cmp eax, 1                              xor edx, edx
* jz loc_41DC                             cmp [esi+44h], edx
* lea eax, (aPnpirqCanOnlyM - 418Fh)[esi]  jle loc_680A
* push eax
* call _printf
* jmp loc_4207
* mov eax, 1
* jmp loc_4209
* xor ebx, ebx
* cmp [edi+44h], ebx
* jle loc_4207
  nop                                     nop
* mov edx, esi                            nop
* mov edx, [edx+7EC5h]                    mov eax, [esi+edx*4+4]
* push edx                                cmp dword ptr ds:(loc_67AB - 67ABh)[ebx], eax
* mov edx, [ebp+arg_8]                    jz loc_67DC
* push edx                                inc edx
* call _objc_msgSend                      cmp [esi+44h], edx
* add esp, 8                              jg loc_67FC
* mov eax, [eax]
* cmp [edi+ebx*4+4], eax
* jz loc_41D4
* inc ebx
* cmp [edi+44h], ebx
* jg loc_41E4
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 _IOUnscheduleFunc for-loop walk (2026-09-17)

Walk the callout chain with a for-loop. Leave sleepPort file-static. Leftover is PIC GOT versus lea for calloutLock/calloutChain plus the prevLink/nextLink unlink address math. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `8243E1C5CA70ABE3D5109AE5D266381903EE2BC4FF84F5FD39FCE2F849D1B751` (299316). Previously identical rows stayed matched (45). Unpaired count unchanged (10). Tool-only; reloc SHA unchanged.

```
_IOUnscheduleFunc
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop [ebp+var_4]                         pop esi
* mov edx, [ebp+var_4]                    mov ebx, [ebp+arg_4]
* mov edx, [ebp+var_4]                    mov edi, esi
* mov edx, [edx+51BAh]                    mov edi, [edi+687Ah]
* push edx
* mov edi, [ebp+var_4]
* mov edi, [ebp+var_4]
* mov edi, [edi+3C22h]
  push edi                                push edi
*                                         mov eax, ds:(off_8028 - 3792h)[esi]
*                                         mov eax, [eax]
*                                         push eax
  call _objc_msgSend                      call _objc_msgSend
* mov eax, [ebp+var_4]                    mov eax, ds:(off_802C - 3792h)[esi]
* add eax, 3C1Ah                          mov ecx, [eax]
* mov edx, [ebp+var_4]
* mov ebx, [edx+3C1Ah]
  add esp, 8                              add esp, 8
* cmp ebx, eax                            cmp ecx, eax
* jz loc_6FAF                             jz loc_3817
* mov esi, eax                            mov edi, ds:(off_802C - 3792h)[esi]
* nop                                     mov [ebp+var_8], edi
* nop                                     mov edi, ds:(off_802C - 3792h)[esi]
*                                         mov [ebp+var_4], edi
*                                         mov eax, ds:(off_802C - 3792h)[esi]
  mov edi, [ebp+arg_0]                    mov edi, [ebp+arg_0]
* cmp [ebx], edi                          cmp [ecx], edi
* jnz loc_6FA8                            jnz loc_3810
* mov edx, [ebp+arg_4]                    cmp [ecx+4], ebx
* cmp [ebx+4], edx                        jnz loc_3810
* jnz loc_6FA8                            mov edx, [ecx+10h]
* mov ecx, [ebx+10h]                      mov ebx, [ecx+14h]
* mov edi, [ebx+14h]                      mov eax, edx
* mov [ebp+var_8], edi                    cmp [ebp+var_8], edx
* mov eax, ecx                            jz loc_37F0
* cmp ecx, esi                            lea eax, [edx+10h]
* jz loc_6F89                             mov [eax+14h], ebx
* lea eax, [ecx+10h]                      mov eax, ebx
* mov edx, [ebp+var_8]                    cmp [ebp+var_4], eax
* mov [eax+4], edx                        jz loc_37FD
* mov eax, [ebp+var_8]
* cmp eax, esi
* jz loc_6F99
  add eax, 10h                            add eax, 10h
* mov [eax], ecx                          mov [eax+10h], edx
  push 18h                                push 18h
* push ebx                                push ecx
  call _IOFree                            call _IOFree
  add esp, 8                              add esp, 8
* jmp loc_6FAF                            jmp loc_3817
* mov ebx, [ebx+10h]                      mov ecx, [ecx+10h]
* cmp ebx, esi                            cmp ecx, eax
* jnz loc_6F68                            jnz loc_37D4
* mov edi, [ebp+var_4]                    mov edi, esi
* mov edi, [ebp+var_4]                    mov edi, [edi+687Eh]
* mov edi, [edi+51BEh]
  push edi                                push edi
* mov edx, [ebp+var_4]                    mov eax, ds:(off_8028 - 3792h)[esi]
* mov edx, [ebp+var_4]                    mov eax, [eax]
* mov edx, [edx+3C22h]                    push eax
* push edx
  call _objc_msgSend                      call _objc_msgSend
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 -[PnPResources markStartDependentResources] nested walks (2026-09-17)

Collapse each resource walk to `setDepStart:[[list] count]` in irq/dma/port/memory order. Leftover is PIC selector loads, the final setDepStart push register, and explicit `return self`. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA E1BB129535A0C359D6B7EE3F4EF8A791CB309BD3B712B7A7704845CE252B544F (299168). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

`
-[PnPResources markStartDependentResources]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop esi                                 pop ebx
* mov ebx, [ebp+self]                     mov esi, [ebp+self]
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+6876h]                    mov edx, [edx+4A22h]
  push edx                                push edx
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+689Eh]                    mov edx, [edx+4A7Ah]
  push edx                                push edx
* mov edx, [ebx+4]                        mov edx, [esi+4]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  push eax                                push eax
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+68D6h]                    mov edx, [edx+4A86h]
  push edx                                push edx
* mov edx, [ebx+4]                        mov edx, [esi+4]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+6876h]                    mov edx, [edx+4A22h]
  push edx                                push edx
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+689Eh]                    mov edx, [edx+4A7Ah]
  push edx                                push edx
* mov edx, [ebx+8]                        mov edx, [esi+8]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  push eax                                push eax
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+68D6h]                    mov edx, [edx+4A86h]
  push edx                                push edx
* mov edx, [ebx+8]                        mov edx, [esi+8]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 28h                            add esp, 28h
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+6876h]                    mov edx, [edx+4A22h]
  push edx                                push edx
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+689Eh]                    mov edx, [edx+4A7Ah]
  push edx                                push edx
* mov edx, [ebx+0Ch]                      mov edx, [esi+0Ch]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  push eax                                push eax
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+68D6h]                    mov edx, [edx+4A86h]
  push edx                                push edx
* mov edx, [ebx+0Ch]                      mov edx, [esi+0Ch]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+6876h]                    mov edx, [edx+4A22h]
  push edx                                push edx
* mov edx, esi                            mov edx, ebx
* mov edx, [edx+689Eh]                    mov edx, [edx+4A7Ah]
  push edx                                push edx
* mov edx, [ebx+10h]                      mov edx, [esi+10h]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
  push eax                                push eax
* mov esi, ds:(paSetdepstart - 57CEh)[esi]  mov ebx, ds:(paSetdepstart - 5606h)[ebx]
* push esi
* mov ebx, [ebx+10h]
  push ebx                                push ebx
*                                         mov edx, [esi+10h]
*                                         push edx
  call _objc_msgSend                      call _objc_msgSend
*                                         mov eax, esi
  lea esp, [ebp-8]                        lea esp, [ebp-8]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 `-[pnpIOPort initFrom:Length:Type:]` declaration order after header (2026-09-17)

Reorder locals (`base` before `flags`), advance `data` after the flags byte, store `_length` before `_alignment`, and assign `_max_base` before `_min_base` on the fixed path. Leftover is type-8/9 block layout polarity, flags-bit jump polarity, and tool `_printf` / `_verbose` PIC versus reloc `_IOLog`. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `D54019890C601EE74DB643D35EA1E565DFFEDAABA24670B91DDC95F14B0946F2` (299180). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

```
-[pnpIOPort initFrom:Length:Type:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop edi                                 pop edi
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov ebx, [ebp+arg_8]                    mov ebx, [ebp+arg_8]
  mov ecx, edi                            mov ecx, edi
* mov ecx, [ecx+791Eh]                    mov ecx, [ecx+3C2Ah]
  push ecx                                push ecx
  mov [ebp+var_8.receiver], esi           mov [ebp+var_8.receiver], esi
  mov ecx, edi                            mov ecx, edi
* mov ecx, [ecx+7AD6h]                    mov ecx, [ecx+3E5Eh]
  mov [ebp+var_8.super_class], ecx        mov [ebp+var_8.super_class], ecx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  add esp, 8                              add esp, 8
  cmp [ebp+arg_10], 8                     cmp [ebp+arg_10], 8
* jz loc_47C4                             jnz loc_646C
* cmp [ebp+arg_10], 9                     cmp dword ptr [ebp+arg_C], 7
* jnz loc_4842                            jz loc_641C
* cmp [ebp+arg_C], 3                      mov ecx, dword ptr [ebp+arg_C]
* jz loc_4788
* mov ecx, [ebp+arg_C]
  push ecx                                push ecx
* lea eax, (aPnpdeviceresou - 473Ah)[edi]  lea eax, (aPnpdeviceresou_10 - 63DAh)[edi]
* jmp loc_47D4                            jmp loc_6482
* mov ax, [ebx]
* and ah, 3
* mov [esi+6], ax
* mov [esi+4], ax
* movzx ax, byte ptr [ebx+2]
* mov [esi+0Ah], ax
* mov [esi+8], ax
* mov byte ptr [esi+0Ch], 0Ah
* cmp ds:(_verbose - 473Ah)[edi], 0
* jz loc_4842
* lea eax, (aFixed - 473Ah)[edi]
* push eax
* call _printf
* jmp loc_4835
* cmp [ebp+arg_C], 7
* jz loc_47EC
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, (aPnpdeviceresou_0 - 473Ah)[edi]
* push eax
* call _printf
* mov edi, ds:(off_C048 - 473Ah)[edi]
* push edi
* push esi
* call _objc_msgSend
* jmp loc_4844
  mov dl, [ebx]                           mov dl, [ebx]
  inc ebx                                 inc ebx
  mov cx, [ebx]                           mov cx, [ebx]
  mov [esi+4], cx                         mov [esi+4], cx
  mov cx, [ebx+2]                         mov cx, [ebx+2]
  mov [esi+6], cx                         mov [esi+6], cx
  movzx cx, byte ptr [ebx+5]              movzx cx, byte ptr [ebx+5]
  mov [esi+0Ah], cx                       mov [esi+0Ah], cx
  movzx ax, byte ptr [ebx+4]              movzx ax, byte ptr [ebx+4]
  mov [esi+8], ax                         mov [esi+8], ax
  test ax, ax                             test ax, ax
* jnz loc_481D                            jnz loc_644D
  mov cx, [esi+0Ah]                       mov cx, [esi+0Ah]
  mov [esi+8], cx                         mov [esi+8], cx
  test dl, 1                              test dl, 1
* jz loc_4828                             jnz loc_6458
*                                         mov byte ptr [esi+0Ch], 0Ah
*                                         jmp loc_645C
  mov byte ptr [esi+0Ch], 10h             mov byte ptr [esi+0Ch], 10h
* jmp loc_482C                            mov eax, ds:(_verbose_ptr - 63DAh)[edi]
*                                         cmp byte ptr [eax], 0
*                                         jz loc_64DB
*                                         jmp loc_64CE
*                                         cmp [ebp+arg_10], 9
*                                         jnz loc_64DB
*                                         cmp dword ptr [ebp+arg_C], 3
*                                         jz loc_6498
*                                         mov ecx, dword ptr [ebp+arg_C]
*                                         push ecx
*                                         lea eax, (aPnpdeviceresou_11 - 63DAh)[edi]
*                                         push eax
*                                         call _IOLog
*                                         mov edi, ds:(paFree_0 - 63DAh)[edi]
*                                         push edi
*                                         push esi
*                                         call _objc_msgSend
*                                         jmp loc_64DD
*                                         mov ax, [ebx]
*                                         and ah, 3
*                                         mov [esi+6], ax
*                                         mov [esi+4], ax
*                                         movzx ax, byte ptr [ebx+2]
*                                         mov [esi+0Ah], ax
*                                         mov [esi+8], ax
  mov byte ptr [esi+0Ch], 0Ah             mov byte ptr [esi+0Ch], 0Ah
* cmp ds:(_verbose - 473Ah)[edi], 0       mov eax, ds:(_verbose_ptr - 63DAh)[edi]
* jz loc_4842                             cmp byte ptr [eax], 0
* mov edi, ds:(paPrint - 473Ah)[edi]      jz loc_64DB
*                                         lea eax, (aFixed - 63DAh)[edi]
*                                         push eax
*                                         call _IOLog
*                                         mov edi, ds:(paPrint - 63DAh)[edi]
  push edi                                push edi
  push esi                                push esi
  call _objc_msgSend                      call _objc_msgSend
  mov eax, esi                            mov eax, esi
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `_calloutThread` for-loop dispatch (2026-09-17)

Walk due callouts with a for-loop, Unschedule-style unlink, unlock/call/free/relock, then `IOSleep(1000)`. Leave `sleepPort` file-static. Leftover is PIC GOT sentinel versus lea, operand-reversed timestamp compare, and unlink `+14h` versus Apple `+4`. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `0909DDE38D80E6A4189A9832B3A92ED56FD61AAB609F70C3BB883E7EEE7404BA` (299704). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

```
_calloutThread
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 10h                            sub esp, 20h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
* lea edi, (_calloutChain - 6E2Ah)[esi]   mov edx, ds:(off_802C - 39F2h)[esi]
*                                         mov [ebp+var_C], edx
*                                         mov edi, ds:(off_802C - 39F2h)[esi]
*                                         mov [ebp+var_10], edi
*                                         mov edx, ds:(off_802C - 39F2h)[esi]
*                                         mov [ebp+var_14], edx
*                                         mov edi, ds:(off_8028 - 39F2h)[esi]
*                                         mov [ebp+var_18], edi
  nop                                     nop
* nop                                     mov edx, esi
* nop                                     mov edx, [edx+661Ah]
* mov ecx, esi                            push edx
* mov ecx, [ecx+52BAh]                    mov eax, ds:(off_8028 - 39F2h)[esi]
* push ecx                                mov eax, [eax]
* mov ecx, esi                            push eax
* mov ecx, [ecx+3D22h]
* push ecx
  call _objc_msgSend                      call _objc_msgSend
* mov ebx, ds:(_calloutChain - 6E2Ah)[esi]  mov edi, [ebp+var_C]
*                                         mov ebx, [edi]
  add esp, 8                              add esp, 8
  cmp ebx, edi                            cmp ebx, edi
* jz loc_6EF2                             jz loc_3AD5
* mov ecx, [ebx+10h]                      nop
* mov [ebp+var_C], ecx                    mov edx, [ebx+10h]
*                                         mov [ebp+var_1C], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _IOGetTimestamp                    call _IOGetTimestamp
* mov edx, [ebx+0Ch]
* mov eax, [ebp+var_4]
  add esp, 4                              add esp, 4
* cmp edx, eax                            mov eax, [ebx+0Ch]
* ja loc_6EE7                             cmp [ebp+var_4], eax
* jnz loc_6E82                            jb loc_3AC6
* mov eax, [ebp+var_8]                    jnz loc_3A64
* cmp [ebx+8], eax                        mov eax, [ebx+8]
* ja loc_6EE7                             cmp [ebp+var_8], eax
* mov edx, [ebx+10h]                      jb loc_3AC6
* mov ecx, [ebx+14h]                      mov ecx, [ebx+10h]
* mov [ebp+var_10], ecx                   mov edi, [ebx+14h]
* mov eax, edx                            mov [ebp+var_20], edi
* cmp edx, edi                            mov eax, ecx
* jz loc_6E94                             cmp [ebp+var_10], ecx
* lea eax, [edx+10h]                      jz loc_3A77
* mov ecx, [ebp+var_10]                   lea eax, [ecx+10h]
* mov [eax+4], ecx                        mov edx, [ebp+var_20]
* mov eax, [ebp+var_10]                   mov [eax+14h], edx
* cmp eax, edi                            mov eax, [ebp+var_20]
* jz loc_6EA4                             cmp [ebp+var_14], eax
*                                         jz loc_3A88
  add eax, 10h                            add eax, 10h
* mov [eax], edx                          mov [eax+10h], ecx
* mov ecx, esi                            mov edi, esi
* mov ecx, [ecx+52BEh]                    mov edi, [edi+661Eh]
* push ecx                                push edi
* mov ecx, esi                            mov edx, [ebp+var_18]
* mov ecx, [ecx+3D22h]                    mov edx, [edx]
* push ecx                                push edx
  call _objc_msgSend                      call _objc_msgSend
* mov ecx, [ebx+4]                        mov edi, [ebx+4]
* push ecx                                push edi
  mov eax, [ebx]                          mov eax, [ebx]
  call eax                                call eax
  push 18h                                push 18h
  push ebx                                push ebx
  call _IOFree                            call _IOFree
* mov ecx, esi                            mov edx, esi
* mov ecx, [ecx+52BAh]                    mov edx, [edx+661Ah]
* push ecx                                push edx
* mov ecx, esi                            mov edi, [ebp+var_18]
* mov ecx, [ecx+3D22h]                    mov edi, [edi]
* push ecx                                push edi
  call _objc_msgSend                      call _objc_msgSend
  add esp, 1Ch                            add esp, 1Ch
* mov ebx, [ebp+var_C]                    mov ebx, [ebp+var_1C]
* cmp ebx, edi                            cmp ds:(off_802C - 39F2h)[esi], ebx
* jnz loc_6E5C                            jnz loc_3A40
* mov ecx, esi                            mov edx, esi
* mov ecx, [ecx+52BEh]                    mov edx, [edx+661Eh]
* push ecx                                push edx
* mov ecx, esi                            mov eax, ds:(off_8028 - 39F2h)[esi]
* mov ecx, [ecx+3D22h]                    mov eax, [eax]
* push ecx                                push eax
  call _objc_msgSend                      call _objc_msgSend
  push 3E8h                               push 3E8h
  call _IOSleep                           call _IOSleep
  add esp, 0Ch                            add esp, 0Ch
* jmp loc_6E34                            jmp loc_3A18
```

### Task 6 `_IOGetTimestamp` 64-bit store experiment (2026-09-17)

Tried a local `nanos = kern_ts * 1000ULL` then half-word store; rebuilt gained an extra unpaired function and lost an identical row, so the change was reverted. Leftover is the hand-rolled lea/or scale versus Apple's `shld`/`adc` multiply-by-1000. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `0909DDE38D80E6A4189A9832B3A92ED56FD61AAB609F70C3BB883E7EEE7404BA` (299704). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

```
_IOGetTimestamp
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 10h                            sub esp, 10h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
*                                         lea eax, [ebp+var_8]
*                                         push eax
*                                         call _kern_timestamp
*                                         mov esi, [ebp+var_8]
*                                         mov [ebp+var_10], esi
*                                         mov ecx, [ebp+var_4]
*                                         lea eax, ds:0[ecx*4]
*                                         mov edx, esi
*                                         shr edx, 1Eh
*                                         or eax, edx
*                                         lea edx, ds:0[esi*4]
*                                         add eax, ecx
*                                         mov [ebp+var_C], eax
*                                         cmp edx, esi
*                                         jnb loc_353C
*                                         inc [ebp+var_C]
*                                         mov edi, [ebp+var_C]
*                                         lea eax, ds:0[edi*4]
*                                         mov esi, [ebp+var_10]
*                                         lea ecx, [esi+esi*4]
*                                         mov edx, ecx
*                                         shr edx, 1Eh
*                                         or eax, edx
*                                         lea edx, ds:0[ecx*4]
*                                         add edi, eax
*                                         mov [ebp+var_C], edi
*                                         cmp ecx, edx
*                                         jnb loc_3567
*                                         inc edi
*                                         mov [ebp+var_C], edi
*                                         mov edi, [ebp+var_10]
*                                         lea ebx, [edi+edi*4]
*                                         lea ebx, [ebx+ebx*4]
*                                         lea ebx, [ebx+ebx*4]
*                                         lea edi, ds:0[ebx*8]
*                                         mov esi, [ebp+arg_0]
*                                         mov [esi], edi
*                                         mov esi, [ebp+var_C]
*                                         lea eax, ds:0[esi*4]
*                                         mov edi, [ebp+var_10]
*                                         lea ecx, [edi+edi*4]
*                                         lea ecx, [ecx+ecx*4]
*                                         mov edx, ecx
*                                         shr edx, 1Eh
*                                         or edx, eax
*                                         add edx, esi
*                                         lea eax, ds:0[ecx*4]
*                                         shr ebx, 1Dh
*                                         cmp eax, ecx
*                                         jnb loc_35BC
*                                         lea eax, ds:8[edx*8]
*                                         or eax, ebx
*                                         mov esi, [ebp+arg_0]
*                                         mov [esi+4], eax
*                                         jmp loc_35CB
*                                         lea eax, ds:0[edx*8]
*                                         or eax, ebx
  mov edi, [ebp+arg_0]                    mov edi, [ebp+arg_0]
* lea edx, [ebp+var_8]                    mov [edi+4], eax
* push edx
* call _kern_timestamp
* mov edx, 0
* mov ecx, 0
* mov ecx, [ebp+var_4]
* mov eax, [ebp+var_8]
* mov ebx, eax
* xor esi, esi
* mov [ebp+var_10], ebx
* mov [ebp+var_C], esi
* add edx, [ebp+var_10]
* adc ecx, [ebp+var_C]
* mov ebx, edx
* mov esi, ecx
* shld esi, ebx, 2
* shl ebx, 2
* mov [ebp+var_10], ebx
* mov [ebp+var_C], esi
* mov ebx, [ebp+var_10]
* mov esi, [ebp+var_C]
* add ebx, edx
* adc esi, ecx
* mov [ebp+var_10], ebx
* mov [ebp+var_C], esi
* mov edx, ebx
* mov ecx, esi
* shld ecx, edx, 2
* shl edx, 2
* mov ebx, [ebp+var_10]
* mov esi, [ebp+var_C]
* add ebx, edx
* adc esi, ecx
* mov [ebp+var_10], ebx
* mov [ebp+var_C], esi
* mov edx, ebx
* mov ecx, esi
* shld ecx, edx, 2
* shl edx, 2
* add edx, [ebp+var_10]
* adc ecx, [ebp+var_C]
* shld ecx, edx, 3
* shl edx, 3
* mov [edi], edx
* mov [edi+4], ecx
  lea esp, [ebp-1Ch]                      lea esp, [ebp-1Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpMemory initFrom:Length:Type:]` early data32 (2026-09-17)

Declare `data32` before `data` and form the post-control payload pointer immediately after `[super init]`. Leftover is type-switch layout, extra flag zeros, and tool `_printf` / verbose PIC. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `A246805FABE50F87B3C7E73A5D92A9F9F90B6A2D6543D1BE2F438C1C4DE414EB` (299756). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

```
-[pnpMemory initFrom:Length:Type:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 8                              sub esp, 0Ch
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop edi                                 pop edi
* mov esi, [ebp+self]                     mov ebx, [ebp+self]
* mov ebx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
* mov ecx, edi                            mov [ebp+var_C], edx
* mov ecx, [ecx+74B6h]                    mov edx, edi
* push ecx                                mov edx, [edx+364Eh]
* mov [ebp+var_8.receiver], esi           push edx
* mov ecx, edi                            mov [ebp+var_8.receiver], ebx
* mov ecx, [ecx+7646h]                    mov edx, edi
* mov [ebp+var_8.super_class], ecx        mov edx, [edx+38D2h]
*                                         mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
* mov eax, ebx                            mov esi, [ebp+var_C]
* lea ebx, [eax+1]                        inc esi
* mov byte ptr [esi+1Bh], 0               mov byte ptr [ebx+1Bh], 0
* mov byte ptr [esi+1Ah], 0               mov byte ptr [ebx+1Ah], 0
* mov byte ptr [esi+19h], 0               mov byte ptr [ebx+19h], 0
* mov byte ptr [esi+1Ch], 0               mov byte ptr [ebx+1Ch], 0
*                                         mov byte ptr [ebx+14h], 0
*                                         mov byte ptr [ebx+15h], 0
*                                         mov byte ptr [ebx+18h], 0
  add esp, 8                              add esp, 8
  cmp [ebp+arg_10], 5                     cmp [ebp+arg_10], 5
* jz loc_4C78                             jnz loc_6A68
* jg loc_4BF8                             mov byte ptr [ebx+1Ch], 1
*                                         cmp dword ptr [ebp+arg_C], 11h
*                                         jz loc_6A24
*                                         mov edx, dword ptr [ebp+arg_C]
*                                         push edx
*                                         lea eax, (aPnpdeviceresou_12 - 69B6h)[edi]
*                                         jmp loc_6AFA
*                                         mov edx, [ebp+var_C]
*                                         movzx eax, byte ptr [edx]
*                                         push eax
*                                         mov edx, edi
*                                         mov edx, [edx+3716h]
*                                         push edx
*                                         push ebx
*                                         call _objc_msgSend
*                                         mov edx, [esi]
*                                         mov [ebx+4], edx
*                                         mov edx, [esi+4]
*                                         mov [ebx+8], edx
*                                         mov edx, [esi+8]
*                                         mov [ebx+0Ch], edx
*                                         mov esi, [esi+0Ch]
*                                         mov [ebx+10h], esi
*                                         add esp, 0Ch
*                                         cmp dword ptr [ebx+0Ch], 0
*                                         jnz loc_6B5A
*                                         mov [ebx+0Ch], esi
*                                         jmp loc_6B5A
*                                         cmp [ebp+arg_10], 6
*                                         jnz loc_6AE4
*                                         mov byte ptr [ebx+1Ch], 1
*                                         cmp dword ptr [ebp+arg_C], 9
*                                         jz loc_6A84
*                                         mov edx, dword ptr [ebp+arg_C]
*                                         push edx
*                                         lea eax, (aPnpdeviceresou_13 - 69B6h)[edi]
*                                         jmp loc_6AFA
*                                         mov edx, [ebp+var_C]
*                                         movzx eax, byte ptr [edx]
*                                         push eax
*                                         mov edx, edi
*                                         mov edx, [edx+3716h]
*                                         push edx
*                                         push ebx
*                                         call _objc_msgSend
*                                         mov edx, [esi]
*                                         mov [ebx+4], edx
*                                         mov edx, [esi]
*                                         mov [ebx+8], edx
*                                         mov edx, [esi+4]
*                                         mov [ebx+10h], edx
*                                         mov esi, [esi+4]
*                                         mov [ebx+0Ch], esi
*                                         mov eax, ds:(_verbose_ptr - 69B6h)[edi]
*                                         add esp, 0Ch
*                                         cmp byte ptr [eax], 0
*                                         jz loc_6B5A
*                                         lea eax, (aFixed - 69B6h)[edi]
*                                         push eax
*                                         call _IOLog
*                                         mov edx, edi
*                                         mov edx, [edx+36FEh]
*                                         push edx
*                                         push ebx
*                                         call _objc_msgSend
*                                         add esp, 0Ch
*                                         jmp loc_6B5A
  cmp [ebp+arg_10], 1                     cmp [ebp+arg_10], 1
* jz loc_4C08                             jnz loc_6B5A
* jmp loc_4D42                            cmp dword ptr [ebp+arg_C], 9
*                                         jz loc_6B10
*                                         mov edx, dword ptr [ebp+arg_C]
*                                         push edx
*                                         lea eax, (aPnpdeviceresou_14 - 69B6h)[edi]
*                                         push eax
*                                         call _IOLog
*                                         mov edi, ds:(paFree_0 - 69B6h)[edi]
*                                         push edi
*                                         push ebx
*                                         call _objc_msgSend
*                                         jmp loc_6B7A
*                                         mov edx, [ebp+var_C]
*                                         movzx eax, byte ptr [edx]
*                                         push eax
*                                         mov edx, edi
*                                         mov edx, [edx+3716h]
*                                         push edx
*                                         push ebx
*                                         call _objc_msgSend
*                                         movzx eax, word ptr [esi]
*                                         shl eax, 8
*                                         mov [ebx+4], eax
*                                         movzx eax, word ptr [esi+2]
*                                         shl eax, 8
*                                         mov [ebx+8], eax
*                                         movzx edx, word ptr [esi+4]
*                                         mov [ebx+0Ch], edx
*                                         movzx eax, word ptr [esi+6]
*                                         shl eax, 8
*                                         mov [ebx+10h], eax
*                                         add esp, 0Ch
*                                         cmp dword ptr [ebx+0Ch], 0
*                                         jnz loc_6B5A
*                                         mov dword ptr [ebx+0Ch], 10000h
*                                         mov eax, ds:(_verbose_ptr - 69B6h)[edi]
*                                         cmp byte ptr [eax], 0
*                                         jz loc_6B78
  cmp [ebp+arg_10], 6                     cmp [ebp+arg_10], 6
* jz loc_4CD0                             jz loc_6B78
* jmp loc_4D42                            mov edi, ds:(paPrint - 69B6h)[edi]
* cmp [ebp+arg_C], 9                      push edi
* jz loc_4C20                             push ebx
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, (aPnpdeviceresou_1 - 4BA2h)[edi]
* jmp loc_4CE4
* push eax
* mov ecx, edi
* mov ecx, [ecx+74C6h]
* push ecx
* push esi
  call _objc_msgSend                      call _objc_msgSend
* mov edx, ebx                            mov eax, ebx
* movzx eax, word ptr [ebx]               lea esp, [ebp-18h]
* shl eax, 8
* mov [esi+4], eax
* movzx eax, word ptr [ebx+2]
* shl eax, 8
* mov [esi+8], eax
* movzx eax, word ptr [ebx+4]
* mov [esi+0Ch], eax
* add esp, 0Ch
* test eax, eax
* jnz loc_4C5A
* mov dword ptr [esi+0Ch], 10000h
* movzx eax, word ptr [edx+6]
* shl eax, 8
* mov [esi+10h], eax
* cmp ds:(_verbose - 4BA2h)[edi], 0
* jz loc_4D42
* jmp loc_4D35
* mov byte ptr [esi+1Ch], 1
* cmp [ebp+arg_C], 11h
* jz loc_4C90
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, (aPnpdeviceresou_2 - 4BA2h)[edi]
* jmp loc_4CE4
* push eax
* mov ecx, edi
* mov ecx, [ecx+74C6h]
* push ecx
* push esi
* call _objc_msgSend
* mov ecx, [ebx]
* mov [esi+4], ecx
* mov ecx, [ebx+4]
* mov [esi+8], ecx
* mov ecx, [ebx+0Ch]
* mov [esi+10h], ecx
* mov ebx, [ebx+8]
* mov [esi+0Ch], ebx
* add esp, 0Ch
* test ebx, ebx
* jnz loc_4CC4
* mov ecx, [esi+10h]
* mov [esi+0Ch], ecx
* cmp ds:(_verbose - 4BA2h)[edi], 0
* jz loc_4D42
* jmp loc_4D35
* mov byte ptr [esi+1Ch], 1
* cmp [ebp+arg_C], 9
* jz loc_4CFC
* mov ecx, [ebp+arg_C]
* push ecx
* lea eax, (aPnpdeviceresou_3 - 4BA2h)[edi]
* push eax
* call _printf
* mov edi, ds:(off_C048 - 4BA2h)[edi]
* push edi
* push esi
* call _objc_msgSend
* jmp loc_4D44
* push eax
* mov ecx, edi
* mov ecx, [ecx+74C6h]
* push ecx
* push esi
* call _objc_msgSend
* mov eax, [ebx]
* mov [esi+8], eax
* mov [esi+4], eax
* mov ebx, [ebx+4]
* mov [esi+10h], ebx
* mov [esi+0Ch], ebx
* add esp, 0Ch
* cmp ds:(_verbose - 4BA2h)[edi], 0
* jz loc_4D42
* lea eax, (aFixed - 4BA2h)[edi]
* push eax
* call _printf
* mov edi, ds:(paPrint - 4BA2h)[edi]
* push edi
* push esi
* call _objc_msgSend
* mov eax, esi
* lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[PnPDeviceResources initForBuf:Length:CSN:]` header locals (2026-09-17)

Reorder header locals to `serialNum`, `deviceID`, `idValue`, `vendorID`. Leftover is Apple's byte-copy ID construction versus shift-or, plus tool `_printf` / verbose PIC. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `F0D3FA514B5B65D0F1C18F80778A0514A376F8B99D05B273A4047ABD69DEA537` (299756). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

```
-[PnPDeviceResources initForBuf:Length:CSN:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 1Ch                            sub esp, 24h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop ebx                                 pop esi
* mov esi, [ebp+self]                     mov ecx, [ebp+arg_8]
* mov edi, [ebp+arg_8]                    mov [ebp+var_18], ecx
* mov ecx, ebx                            mov ebx, esi
* mov ecx, [ecx+5972h]                    mov ebx, [ebx+6336h]
* push ecx                                push ebx
* mov [ebp+var_14.receiver], esi          mov ecx, [ebp+self]
* mov ecx, ebx                            mov [ebp+var_14.receiver], ecx
* mov ecx, [ecx+5A3Ah]                    mov ebx, esi
* mov [ebp+var_14.super_class], ecx       mov ebx, [ebx+64A2h]
*                                         mov [ebp+var_14.super_class], ebx
  lea eax, [ebp+var_14]                   lea eax, [ebp+var_14]
  push eax                                push eax
  call _objc_msgSendSuper                 call _objc_msgSendSuper
  add esp, 8                              add esp, 8
* cmp [ebp+arg_C], 8                      cmp dword ptr [ebp+arg_C], 8
* ja loc_6730                             jg loc_3D1C
  push 9                                  push 9
* mov ecx, [ebp+arg_C]                    mov ecx, dword ptr [ebp+arg_C]
  push ecx                                push ecx
* lea eax, (aPnpdeviceresou_12 - 66E6h)[ebx]  lea eax, (aPnpdeviceresou_0 - 3CCEh)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
  xor eax, eax                            xor eax, eax
* jmp loc_6889                            jmp loc_3E78
* mov [ebp+var_1C], edi                   mov ebx, [ebp+var_18]
* lea edx, [ebp+var_15]                   mov dl, [ebx+3]
* mov eax, 3                              shl edx, 18h
* nop                                     movzx eax, byte ptr [ebx+2]
* mov ecx, [ebp+var_1C]                   shl eax, 10h
* mov cl, [ecx]                           or edx, eax
* mov [edx], cl                           movzx eax, byte ptr [ebx+1]
* inc [ebp+var_1C]                        shl eax, 8
* dec edx                                 or edx, eax
* dec eax                                 movzx eax, byte ptr [ebx]
* cmp eax, 0FFFFFFFFh                     or edx, eax
* jnz loc_673C                            mov ebx, [ebp+arg_10]
* mov ecx, [ebp+arg_10]                   mov ecx, [ebp+self]
* mov [esi+64h], ecx                      mov [ecx+64h], ebx
* mov ecx, [ebp-18h]                      push edx
*                                         mov ecx, esi
*                                         mov ecx, [ecx+6346h]
  push ecx                                push ecx
* mov ecx, ebx                            mov ebx, [ebp+self]
* mov ecx, [ecx+59C6h]                    push ebx
*                                         call _objc_msgSend
*                                         mov ecx, [ebp+var_18]
*                                         mov ecx, [ecx+4]
*                                         mov [ebp+var_1C], ecx
  push ecx                                push ecx
* push esi                                mov ebx, esi
*                                         mov ebx, [ebx+634Ah]
*                                         push ebx
*                                         mov ecx, [ebp+self]
*                                         push ecx
  call _objc_msgSend                      call _objc_msgSend
* mov ecx, [edi+4]                        mov eax, ds:(_verbose_ptr - 3CCEh)[esi]
*                                         add esp, 18h
*                                         cmp byte ptr [eax], 0
*                                         jz loc_3DFC
*                                         mov ebx, [ebp+var_18]
*                                         mov bl, [ebx+8]
*                                         mov [ebp+var_20], bl
*                                         mov ecx, esi
*                                         mov ecx, [ecx+634Eh]
  push ecx                                push ecx
* mov ecx, ebx                            mov ebx, [ebp+self]
* mov ecx, [ecx+59F2h]                    push ebx
* push ecx
* push esi
  call _objc_msgSend                      call _objc_msgSend
* add esp, 18h                            mov edi, eax
* cmp ds:(_verbose - 66E6h)[ebx], 1
* jnz loc_6818
* movzx eax, byte ptr [edi+8]
* push eax
* mov ecx, ebx
* mov ecx, [ecx+59F6h]
* push ecx
* push esi
* call _objc_msgSend
* add esp, 8
* push eax
* mov ecx, ebx
* mov ecx, [ecx+59CEh]
* push ecx
* push esi
* call _objc_msgSend
* add esp, 8
* push eax
* mov ecx, ebx
* mov ecx, [ecx+59CEh]
* push ecx
* push esi
* call _objc_msgSend
* add esp, 8
* mov edx, eax
  shr eax, 1Ah                            shr eax, 1Ah
  and al, 1Fh                             and al, 1Fh
  add al, 40h                             add al, 40h
  mov [ebp+var_C], al                     mov [ebp+var_C], al
* mov eax, edx                            mov eax, edi
  shr eax, 15h                            shr eax, 15h
  and al, 1Fh                             and al, 1Fh
  add al, 40h                             add al, 40h
  mov [ebp+var_B], al                     mov [ebp+var_B], al
* mov eax, edx                            mov eax, edi
  shr eax, 10h                            shr eax, 10h
  and al, 1Fh                             and al, 1Fh
  add al, 40h                             add al, 40h
  mov [ebp+var_A], al                     mov [ebp+var_A], al
* movzx eax, dx                           movzx eax, di
  push eax                                push eax
* lea eax, (a04x - 66E6h)[ebx]            lea eax, (a04x - 3CCEh)[esi]
  push eax                                push eax
*                                         lea ecx, [ebp+var_C]
*                                         mov dword ptr [ebp+var_24], ecx
  lea eax, [ebp+var_9]                    lea eax, [ebp+var_9]
  push eax                                push eax
  call _sprintf                           call _sprintf
  mov [ebp+var_5], 0                      mov [ebp+var_5], 0
* lea eax, [ebp+var_C]                    movzx eax, [ebp+var_20]
* add esp, 0Ch
  push eax                                push eax
* lea eax, (aVendorIdS0xLxS - 66E6h)[ebx]  mov ebx, [ebp+var_1C]
*                                         push ebx
*                                         push edi
*                                         mov ecx, dword ptr [ebp+var_24]
*                                         push ecx
*                                         lea eax, (aVendorIdS0xLxS - 3CCEh)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
* add esp, 14h                            add esp, 28h
* mov ecx, ebx                            mov ebx, esi
* mov ecx, [ecx+5972h]                    mov ebx, [ebx+6336h]
*                                         push ebx
*                                         mov ecx, esi
*                                         mov ecx, [ecx+6332h]
  push ecx                                push ecx
* mov ecx, ebx                            mov ebx, esi
* mov ecx, [ecx+594Ah]                    mov ebx, [ebx+6402h]
* push ecx                                push ebx
* mov ecx, ebx
* mov ecx, [ecx+5A12h]
* push ecx
  call _objc_msgSend                      call _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call _objc_msgSend                      call _objc_msgSend
* mov [esi+4], eax                        mov ecx, [ebp+self]
*                                         mov [ecx+4], eax
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jz loc_6870                             jz loc_3E5C
* mov ecx, [ebp+arg_C]                    mov ecx, dword ptr [ebp+arg_C]
  push ecx                                push ecx
* lea eax, [edi+9]                        mov eax, [ebp+var_18]
*                                         add eax, 9
  push eax                                push eax
* mov ecx, ebx                            mov ebx, esi
* mov ecx, [ecx+59FAh]                    mov ebx, [ebx+6352h]
*                                         push ebx
*                                         mov ecx, [ebp+self]
  push ecx                                push ecx
* push esi
  call _objc_msgSend                      call _objc_msgSend
  add esp, 10h                            add esp, 10h
* test al, al                             test eax, eax
* jz loc_687C                             jz loc_3E68
* mov eax, esi                            mov eax, [ebp+self]
* jmp loc_6889                            jmp loc_3E78
* lea eax, (aPnpdeviceresou_13 - 66E6h)[ebx]  lea eax, (aPnpdeviceresou_1 - 3CCEh)[esi]
  push eax                                push eax
* call _printf                            call _IOLog
* mov ebx, ds:(off_C048 - 66E6h)[ebx]     mov esi, ds:(paFree_0 - 3CCEh)[esi]
*                                         push esi
*                                         mov ebx, [ebp+self]
  push ebx                                push ebx
* push esi
  call _objc_msgSend                      call _objc_msgSend
* lea esp, [ebp-28h]                      lea esp, [ebp-30h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `_IOScheduleFunc` for-loop tail walk (2026-09-17)

Walk the prev-chain with a for-loop to find the insert tail instead of only using the sentinel+4 tail pointer. Leftover is Apple's direct tail-pointer insert, `shld` multiply by 1e9 versus `mul`, and PIC. Accepted compiler-shaped leftover (reviewer Pat Raynor). Tool SHA `2BF1107328101AC6C3E7826849C64310646201A5D9F9F5AB76D2B1CDFE9810BC` (299832). Previously identical rows stayed matched (45). Unpaired count unchanged (10).

```
_IOScheduleFunc
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 14h                            sub esp, 14h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop [ebp+var_4]                         pop esi
*                                         mov edi, [ebp+arg_4]
  cmp [ebp+arg_8], 0                      cmp [ebp+arg_8], 0
* jnz loc_6CDC                            jnz loc_3770
* mov ebx, [ebp+arg_4]                    push edi
* push ebx                                mov eax, [ebp+arg_0]
* mov esi, [ebp+arg_0]                    call eax
* call esi                                jmp loc_3854
* jmp loc_6E12
* mov ebx, [ebp+var_4]
* mov [ebx+3E9Eh], edi
* mov [ebx+3EA2h], edi
* mov [edi+10h], ecx
* mov [edi+14h], ecx
* jmp loc_6DF3
  push 18h                                push 18h
  call _IOMalloc                          call _IOMalloc
* mov edi, eax                            mov ebx, eax
* mov esi, [ebp+arg_0]                    mov edx, [ebp+arg_0]
* mov [edi], esi                          mov [ebx], edx
* mov ebx, [ebp+arg_4]                    mov [ebx+4], edi
* mov [edi+4], ebx                        lea eax, [ebp+var_8]
* mov esi, [ebp+var_4]                    push eax
* mov esi, [ebp+var_4]                    call _IOGetTimestamp
* mov esi, [esi+543Eh]                    mov eax, 3B9ACA00h
* push esi                                mul [ebp+arg_8]
* mov ebx, [ebp+var_4]                    mov [ebp+var_14], eax
* mov ebx, [ebp+var_4]                    mov [ebp+var_10], edx
* mov ebx, [ebx+3EA6h]                    mov edx, [ebp+var_14]
* push ebx                                mov [ebp+var_C], edx
*                                         mov eax, [ebp+var_14]
*                                         mov edx, [ebp+var_10]
*                                         mov eax, edx
*                                         xor edx, edx
*                                         mov [ebp+var_14], eax
*                                         mov [ebp+var_10], edx
*                                         mov edx, [ebp+var_14]
*                                         mov [ebp+var_14], edx
*                                         mov ecx, [ebp+var_8]
*                                         mov eax, [ebp+var_C]
*                                         add [ebp+var_8], eax
*                                         add esp, 8
*                                         mov edi, [ebp+var_14]
*                                         add edi, [ebp+var_4]
*                                         cmp [ebp+var_8], ecx
*                                         jnb loc_37CC
*                                         inc edi
*                                         mov [ebp+var_4], edi
*                                         mov edx, [ebp+var_8]
*                                         mov [ebx+8], edx
*                                         mov eax, [ebp+var_4]
*                                         mov [ebx+0Ch], eax
*                                         mov edx, esi
*                                         mov edx, [edx+68B2h]
*                                         push edx
*                                         mov eax, ds:(off_8028 - 375Ah)[esi]
*                                         mov eax, [eax]
*                                         push eax
  call _objc_msgSend                      call _objc_msgSend
* lea edx, [edi+8]                        mov ecx, ds:(off_802C - 375Ah)[esi]
*                                         add esp, 8
*                                         cmp [ecx], ecx
*                                         jnz loc_380C
*                                         mov [ecx], ebx
*                                         mov [ecx+4], ebx
*                                         mov [ebx+10h], ecx
*                                         mov [ebx+14h], ecx
*                                         jmp loc_383A
*                                         mov edx, ds:(off_802C - 375Ah)[esi]
*                                         mov ecx, [edx]
*                                         cmp [ecx+10h], edx
*                                         jz loc_3828
*                                         mov edi, ds:(off_802C - 375Ah)[esi]
*                                         nop
*                                         mov ecx, [ecx+10h]
*                                         cmp [ecx+10h], edi
*                                         jnz loc_3820
*                                         mov [ebx+14h], ecx
*                                         mov edx, ds:(off_802C - 375Ah)[esi]
*                                         mov [ebx+10h], edx
*                                         mov [ecx+10h], ebx
*                                         mov [edx+4], ebx
*                                         mov edx, esi
*                                         mov edx, [edx+68B6h]
  push edx                                push edx
* call _IOGetTimestamp                    mov esi, ds:(off_8028 - 375Ah)[esi]
* mov ebx, [ebp+arg_8]                    mov [ebp+var_14], esi
* mov esi, ebx                            mov eax, dword ptr ds:(loc_375A - 375Ah)[esi]
* sar esi, 1Fh                            push eax
* mov [ebp+var_C], ebx
* mov [ebp+var_8], esi
* mov edx, ebx
* mov ecx, esi
* shld ecx, edx, 5
* shl edx, 5
* mov ebx, edx
* mov esi, ecx
* sub ebx, [ebp+var_C]
* sbb esi, [ebp+var_8]
* mov [ebp+var_14], ebx
* mov [ebp+var_10], esi
* mov edx, ebx
* mov ecx, esi
* shld ecx, edx, 6
* shl edx, 6
* sub edx, [ebp+var_14]
* sbb ecx, [ebp+var_10]
* shld ecx, edx, 3
* shl edx, 3
* mov ebx, edx
* mov esi, ecx
* add ebx, [ebp+var_C]
* adc esi, [ebp+var_8]
* mov [ebp+var_14], ebx
* mov [ebp+var_10], esi
* mov edx, ebx
* mov ecx, esi
* shld ecx, edx, 2
* shl edx, 2
* mov ebx, [ebp+var_14]
* mov esi, [ebp+var_10]
* add ebx, edx
* adc esi, ecx
* mov [ebp+var_14], ebx
* mov [ebp+var_10], esi
* mov edx, ebx
* mov ecx, esi
* shld ecx, edx, 2
* shl edx, 2
* mov ebx, [ebp+var_14]
* mov esi, [ebp+var_10]
* add ebx, edx
* adc esi, ecx
* mov [ebp+var_14], ebx
* mov [ebp+var_10], esi
* mov edx, ebx
* mov ecx, esi
* shld ecx, edx, 2
* shl edx, 2
* add edx, [ebp+var_14]
* adc ecx, [ebp+var_10]
* shld ecx, edx, 9
* shl edx, 9
* mov [ebp+var_C], edx
* mov [ebp+var_8], ecx
* add [edi+8], edx
* adc [edi+0Ch], ecx
* add esp, 10h
* mov ecx, [ebp+var_4]
* add ecx, 3E9Eh
* mov esi, [ebp+var_4]
* cmp [esi+3E9Eh], ecx
* jz loc_6CC0
* mov edx, [esi+3EA2h]
* mov [edi+14h], edx
* mov [edi+10h], ecx
* mov [esi+3EA2h], edi
* mov [edx+10h], edi
* mov ebx, [ebp+var_4]
* mov ebx, [ebp+var_4]
* mov ebx, [ebx+5442h]
* push ebx
* mov esi, [ebp+var_4]
* mov esi, [ebp+var_4]
* mov esi, [esi+3EA6h]
* push esi
  call _objc_msgSend                      call _objc_msgSend
  lea esp, [ebp-20h]                      lea esp, [ebp-20h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```
