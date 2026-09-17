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
