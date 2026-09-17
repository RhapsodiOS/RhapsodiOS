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
