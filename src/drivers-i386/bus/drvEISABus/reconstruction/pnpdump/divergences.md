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
