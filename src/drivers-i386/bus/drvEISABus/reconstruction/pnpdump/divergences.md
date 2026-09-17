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
