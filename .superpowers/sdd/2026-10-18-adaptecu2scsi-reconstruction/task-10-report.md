# Task 10 implementer report

Status: DONE. All Task10 scoped gates passed; controller independent review follows this handoff.

Scope is the exact28 Recovery bodies in `[0x193bb8,0x198100)`. New production source is `src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2CHIMRecovery.c`. No switch is assigned. Shared ABI headers, accepted owners, main checkout and build integration are untouched. Work uses the approved isolated checkout at `C:/Users/raynorpat/.codex/worktrees/adaptecu2scsi/RhapsodiOS`.

## Source and native review

Production was written in8/8/8/4-body batches after named/group RED. Native ordinary-memory review exposed real compiler reorderings. Local volatile SCB/HIOB views preserve authenticated byte reads/publications; no shared header was widened. Four later bodies corrected duplicate/eager loads and order. Actual imports are taken from Mach-O relocation records, not misleading unrelocated IDA call labels. Each body in `reconstruction/task10.json` binds source line, actual target bytes/hash/bounds, real import relocations, direct fixture IDs and control-flow review. All28 are proposed control-flow-confirmed, not assembly-matched.

| Body | Reference range (exclusive end) | Source line | Native offset / bytes | Direct cases |
|---|---|---:|---|---:|
| `SCSIhSetStat` | `195e48`â€“`195f20` | 11 | `0` / 324 | 14 |
| `SCSIhTerminateCommand` | `195d28`â€“`195e48` | 44 | `144` / 288 | 14 |
| `SCSIhAbortTarget` | `194bd4`â€“`194d40` | 68 | `264` / 380 | 6 |
| `SCSIhCheckLength` | `194074`â€“`19431c` | 96 | `3e0` / 680 | 15 |
| `SCSIhBreakInterrupt` | `195f20`â€“`1960d0` | 135 | `688` / 432 | 19 |
| `SCSIhSwappingRemoveActiveAbort` | `197150`â€“`1972dc` | 167 | `838` / 396 | 2 |
| `SCSIhStandardRemoveActiveAbort` | `1972dc`â€“`19747c` | 181 | `9c4` / 416 | 2 |
| `SCSIhSwappingRemoveAbortHIOBFromNewQ` | `197ef0`â€“`198100` | 195 | `b64` / 512 | 8 |
| `SCSIhStandard64RequestSense` | `1953d4`â€“`19573c` | 220 | `d64` / 872 | 1 |
| `SCSIhStandardAdvRequestSense` | `195848`â€“`195bf8` | 246 | `10cc` / 944 | 1 |
| `SCSIhSwapping32RequestSense` | `19573c`â€“`195848` | 274 | `147c` / 256 | 1 |
| `SCSIhSwappingAdvRequestSense` | `195bf8`â€“`195d28` | 300 | `157c` / 280 | 1 |
| `SCSIhStandard64ResidueCalc` | `19747c`â€“`197754` | 331 | `1694` / 740 | 5 |
| `SCSIhSwapping32ResidueCalc` | `197754`â€“`1979c0` | 381 | `1978` / 632 | 5 |
| `SCSIhStandardAdvResidueCalc` | `1979c0`â€“`197c58` | 428 | `1bf0` / 664 | 5 |
| `SCSIhSwappingAdvResidueCalc` | `197c58`â€“`197ef0` | 475 | `1e88` / 664 | 5 |
| `SCSIhStandard64ActiveAbort` | `1960d0`â€“`1965a0` | 522 | `2120` / 1224 | 7 |
| `SCSIhStandardAdvActiveAbort` | `1967d8`â€“`196ca4` | 562 | `25e8` / 1220 | 7 |
| `SCSIhSwappingAdvActiveAbort` | `196ca4`â€“`197150` | 602 | `2aac` / 1192 | 8 |
| `SCSIhSwapping32ActiveAbort` | `1965a0`â€“`1967d8` | 651 | `2f54` / 568 | 3 |
| `SCSIhIntSelto` | `194d40`â€“`194eb8` | 678 | `318c` / 376 | 2 |
| `SCSIhIntFree` | `194eb8`â€“`195144` | 699 | `3304` / 652 | 2 |
| `SCSIhParityError` | `195144`â€“`1953d4` | 723 | `3590` / 656 | 6 |
| `SCSIhCheckCondition` | `19462c`â€“`1949d0` | 751 | `3820` / 932 | 9 |
| `SCSIhCdbAbort` | `19431c`â€“`19462c` | 793 | `3bc4` / 776 | 3 |
| `SCSIhBadSeq` | `1949d0`â€“`194bd4` | 827 | `3ecc` / 516 | 2 |
| `SCSIhIntSrst` | `193bb8`â€“`193ea0` | 850 | `40d0` / 740 | 3 |
| `SCSIhIntIOError` | `193ea0`â€“`194074` | 888 | `43b4` / 468 | 2 |

The native object is an intermediate RELEASE_PPC PPC big-endian MH_OBJECT compiled by the real historical compiler. Exact final command, CPU18, source/guest paths and logs are in `OUT/objects/task10/objects.json`; original finalr3 products remain at `OUT/task10/finalr3-native`. Guest QMP `query-name` confirmed `adaptecu2scsi-kbuild`, SSH2293/QMP4693/monitor4793. Distinct staging `/private/tmp/adaptecu2scsi-task10` preserved baseline SDK and prior outputs; guest was not stopped.

Native/source producer: `fa9ab66a29984e668fe392602dfd56b9f47969f1`.
Production canonical/staged SHA256: `8467312ACD5F5802EADEDCC64C6D25B4E3FCF66FBA93545D29C6D1951B7A75F3`.
Object SHA256: `66172D8D81D9B1D7CE85E24D148B2BFCC16967099CEA67190096F65D8A6B24B1`.
Final historical compile `1.log` is empty. Original582 build's predecessor warning is retained;071 restored the actual reference initialization. Later fa9 access correction compiled cleanly.

| Native input | Canonical Git / staged SHA256 | Raw checkout SHA256 |
|---|---|---|
| `AdaptecU2CHIMRecovery.c` | `8467312ACD5F5802EADEDCC64C6D25B4E3FCF66FBA93545D29C6D1951B7A75F3` | `8467312ACD5F5802EADEDCC64C6D25B4E3FCF66FBA93545D29C6D1951B7A75F3` |
| `AdaptecU2CHIMTypes.h` | `EBCAF8DC111A1B45A63A17C55B35CD5D22AB35BB3AF46901EF7F16E55549772A` | `EBCAF8DC111A1B45A63A17C55B35CD5D22AB35BB3AF46901EF7F16E55549772A` |
| `AdaptecU2CHIM.h` | `B5210607C79287A4071EB3921A885BBF7011F0E61F1AE7D43708A8AEEBF94106` | `B5210607C79287A4071EB3921A885BBF7011F0E61F1AE7D43708A8AEEBF94106` |
| `AdaptecU2CHIMPrivate.h` | `BB3BC6F7DF328DF7772ED2F0E74EFC4CBEED70291DC626490D91F454E19EA4C0` | `72F02742B1414FAD4529485B6A9367B4ED29E83F1C6E92442112D2667CF3CAF0` |
| `OSMFunctions.h` | `F7DBE4235865185DE6B2D2F5BC1BCCB77C5E999D5968B002B00D61CE2F5EBFD3` | `F7DBE4235865185DE6B2D2F5BC1BCCB77C5E999D5968B002B00D61CE2F5EBFD3` |
| `AdaptecU2SCSI.h` | `3F91074F77D3AD83B41B477859C8B970ADDBBC0CA90145299277EAA8E6F6EE9C` | `3F91074F77D3AD83B41B477859C8B970ADDBBC0CA90145299277EAA8E6F6EE9C` |
| `AdaptecU2SCSIPrivate.h` | `3FC62CD8BAC420FF920A2FAB1F9B50DE464BED138A1E502B108DCBEDAFE9C3CE` | `3FC62CD8BAC420FF920A2FAB1F9B50DE464BED138A1E502B108DCBEDAFE9C3CE` |

The private header has CRLF raw checkout bytes; native staging uses exact canonical Git LF bytes, as explicitly recorded. No global Git settings changed. Seven source/header inputs are bound separately from13 actual reference executable/JSON/inventory inputs. Accepted eight native dependencies and Task5â€“9 canonical owner proofs are separately authenticated, preserving their original producers.

## Behavioral coverage and bounds

Frozen corpus:158 cases,28direct entries;20interrupt,68completion,70abort. All supported modes0/3/4/5 are included for sense, residue, active abort, termination and serialized ownership. Cases retain A5 neutral neighbors, exact byte/halfword/word accesses, full32-bit little-endian bus addresses including `fffffffc+8->4`, actual SG backedges and real mode callbacks. Reference executes actual accepted Hardware/SCB/Negotiation/OSM bodies and pinned future Resource/HIM helper bodies. No internal CHIM hooks or counter edits are used. Future helper bytes/sizes/contracts are explicitly bound in the owner proof.

Six complete recovery graphs execute all finite4000settle/delay iterations and actual resource/OSM callback chains:

| Case | Actual instructions |
|---|---:|
| full IntSrst | 2,647,862 |
| full IntIOError | 3,530,391 |
| full BadSeq | 2,651,253 |
| IntSrst optional reset + stack | 3,531,392 |
| IntSrst optional stretch | 2,936,488 |
| IntIOError pending interrupt | 3,530,947 |

All remain below ordinary4M. CheckLength counter initialization `80000000`, decrement/comparison/backedge and IntSrst/CheckCondition postdecrement `800000` are retained and reviewed in actual native code. Full CheckLength2^31 and IntSrst8,388,609 initial poll maxima are unexecuted, under controller's targeted-coverage ruling. Actual hardware termination predicates/backedges and complete downstream effects execute. CheckLength status10 before decrement, status28 after decrement and zero all join1942b4 (residual0, register2 restore, host18); no distinct callback/ownership. Nonterminal loop costs31instructions/read (~66.6B total). IntSrst status-clear/exhaustion join193c58; nonterminal55instructions per read/write/eieio (~461.4M total). Costs are calculated, not executed. Defensive malformed SG-list full caps are also CF-only; valid SG termination/backedges execute. No allowance is enlarged; Task9 exact two-entry240M opt-in is unused.

Eight serialized sequences execute both valid completion/abort orders in each mode, each stage an actual PPC call. Pending manager9/breakpoint10000, owned active slot plus sentinel/foreign slots establish valid BreakInterrupt preconditions. Full first-result fixture bytes, explicit pointer bindings and aliasing feed the second input. Actual mutable image writes are monitored and none occur; no stateful external service is invoked (only scripted MMIO/barriers). ABI-clobbered CPU state is reset only at call boundaries. Exact byte and pointer corruption negatives reject changed handoffs. Final active slot is sentinel, done queue owns the HIOB once, done/free counters each1, resource active count0 and pending abort cleared. This models serialized orders, not concurrent timing.

Four critical SCB native/reference footprints check ordinary reads and writes as well as reversed word/halfword stores. A preserved actual pre-correction batch3 object is rejected for store reordering. Fourteen SetStat cases execute both actual native and reference bodies, comparing all56HIOBbytes, exact ordinary memory access traces, sentinel return/SP and r14â€“31 preservation; this is a leaf pairing, not full linked pairing.

## Failures and corrections

Initial named RED:3failed/275deselected0.93s, missing Recovery source. Initial group RED: owner body not implemented. Remaining body RED:25failed/3passed/278deselected2.61s. Early64case named/body GREEN:31passed/275deselected49.68s. Native footprint missing-module RED then1passed0.32s; meaningful preserved-object negative subsequently passed. Expanded native read-order oracle and actual SetStat traces failed against071, then fa9 GREEN3passed311deselected2.05s. Counter/boundary GREEN2passed311deselected1.30s; earlier boundaries/negative GREEN4passed307deselected3.60s. Raw logs remain in `OUT/task10`.

CheckCondition sense fixture initially wrote expectedSCB7 but actual0: assigning HIOB flags1000 zeroed overlaid byte9. Corrected fixture ORs flags preserving byte9; hardware expectation remains7. NewQ SwappingAdv fixture originally guessed Bayonet tail helper; actual descriptor binds AIC78XX tail and bound was corrected. Target-clear register32 guess was corrected from actual firmware descriptor0=223. Copied MMIO labels were replaced with Task10 labels and exact actual register set. Status40 uses actual SCSIHCheckDeviceIdle, not a mock. A copied special fixture lacked its claimed resource region; invalid observation was removed, real callback/owner observations remain. Optional reset+stack+stretch combined fixture had insufficient callback script because actual PauseAndWait/delay also invoke stretch; split into valid reset+stack and stretch cases under4M, preserving raw failure and no skips. Windows authoring-file replace retry handles a bounded file lock only; execution guards are unchanged.

Reference predecessor initialization is actual instruction197f88 `mr r25,r29`, before comparison198014 and predecessor use198060; traversal1980bc updates it after nonmatch. Empty queue returns before use; headmatch follows the head branch; nonhead uses initialized/traversed predecessor. There is no reachable incoming/pre-definition register dependency.071 restores this explicit machine definition rather than inventing a default.

## Commands and evidence

All Python commands use `OUT/venv/Scripts/python.exe`, Python3.13.9/Unicorn2.1.4, `PYTHONPATH=tools/binrecon`; pytest includes `-p no:faulthandler`. Known handled Windows first-chance mem_map diagnostics are not failures; real execution errors remain fatal.

- Initial and bounded authoring: `OUT/task10/fixtures1.py` through `fixtures17.py`, `finalize-cases.py`, separate strict actual logs and per-case raw observations.
- Historical final build: `OUT/task10/native-final-build.ps1 finalr3 fa9ab66a29984e668fe392602dfd56b9f47969f1`; canonical seven-input manifest, archive, exact command, native hashes and empty log retained.
- Authenticated reference IDA path/hash before export: `C:/Users/raynorpat/Downloads/test/MOSXS12v3/mach_kernel`, SHA256 `D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD`,2983828bytes. `OUT/task10/reference-code.json` stores actual all28 disassembly/pseudocode outside Git.
- Fresh unique-path finalr3 native IDA input SHA matched disk SHA before export. `OUT/task10/finalr3-native-code.json` records actual28body disassembly and input SHA. Own native leases closed; no unrelated database lease closed.
- Public reference: `tests/ppc_cases.py reference --reference OUT/reference --cases tests/task10-cases.json --contracts tests/contracts.json --output OUT/objects/task10/reference-results.json`, log `OUT/task10/reference-final.log`.
- Final native/boundary capture: `OUT/task10/final-observations.py`, log `native-boundary-final.log`; actual14native+14referenceSetStat and8sequences/16calls PASS, producer030d8a79fd575a4a26bf292e4404d0c2e09db1e6.
- Freeze: `OUT/task10/freeze-proof.py` consumes actual object/relocations/public/native/boundary results; exact28 ledger entries and source-map only, no assigned switch/data change.

## Limits and self-review

No full kernel integration, four-build acceptance, full linked28body paired execution, all-corpus refresh, physical timing/DMA acceptance or concurrency claim. Those remain Tasks15/16. Accepted Task9 observer caching minor and prior global portability/attribution work remain controller-owned final obligations. No frozen incoming-r28 exception was introduced or used here. Historical IntSelto initial dereference before sentinel guard is preserved rather than repaired.

Self-review verified exact changed file ownership, canonical fresh-Git proof/28ledger digest, actual producer identity, reference/native input closure, native imports, no prior-owner changes, no broad cleanup and all required scoped checks. The only changed ledger entries are the28Recovery addresses; other ledger entries are identical to accepted9beb.

## Fresh final observation identities

Fresh public158 passed at actual producer `030d8a79fd575a4a26bf292e4404d0c2e09db1e6`. Raw `reference-results.json` SHA256 is `D9A26B174E64A3F83943E4AEC2F4EDF7F4CCE79BF8C766D4910F33695D8A60E2`; actual runner is `1/unicorn-2.1.4/bd9d0f0a2a3d881a558fbe9e91d57a9232379ddf71f5f3de0de4ab549475e8a1`. Native14/reference14 raw wrapper SHA256 `D5DDA188F0550EA447F01510BF3E8304D0340DA8B66B20B2A44071B9893F1AE1`; actual16-call boundary wrapper SHA256 `044B02846EB882CE9C20A8E0F12396775BF2FA43BD941ED35F0394FC48A20ED1`. These retain actual030d producer while production/native remainfa9.

Controller's final named-family ruling permits assertions over this complete fresh actual158 artifact after full owner/input authentication; final named checks explicitly do not execute the six graphs a second time. The initial named3 direct run over64 cases remains independent historical GREEN. Final consumers assert exact family IDs and actual expected observations/sentinel/noUnknown/budgets, with missing-result/stale-case/runner/import-closure/changed-observation negatives. Changing the pytest consumer does not change any runtime input consumed by the actual030d public/native/boundary runs.

Self-review semantic comparison against accepted9beb confirms prior contracts are exactly equal after removing only new `task10-hardware` MMIO records. All changed production lines are in the new Recovery owner. No prior source/header/data/switch or shared runner change is present. `git diff --check` passes after removing a trailing test-file blank line.


## Final gates and commit closure

- `pytest -p no:faulthandler tests/test_reconstruction.py -k 'selection_parity_and_bad_sequence or autosense_residual_and_completion or active_abort_vs_completion or (task10 and not proof_digest)' -q`: **51 passed,276deselected in198.83s**. Log `OUT/task10/final-scoped-tests.log`. These comprise named3 authenticated fresh158 families,28body checks, native access/counter/status checks, full boundary checks, preserved native reorder negative and12owner corruptions. Native leaf test coverage remains the same14SetStat cases; repeated assertions do not add case coverage.
- `pytest -p no:faulthandler tests/test_reconstruction.py -k 'target_layout_and_method_contracts or inventory_reference_identity_and_partition' -q`: **2 passed,325deselected in233.63s**. Log `layout-inventory-final.log`. Actual accepted target layout object and freshly authenticated reference inventory are consumed.
- Evidence committed as `f69ca42e43f6bcb40cc96a5753bad3dddfd83d1f` (`scsi: record Ultra2 recovery evidence`). Then `pytest -p no:faulthandler tests/test_reconstruction.py -k task10_proof_digest_matches_canonical_git -q`: **1 passed,326deselected in0.39s**. Log `canonical-git-final.log`. Fresh Git blob bytes materialize the proof, whose digest equals every one of28committed ledger artifacts and canonical working proof. No runtime/native rerun followed this evidence-only commit.
- Public actual158PASS, native14/reference14PAIRPASS and actual8sequences/16callsPASS are separately preserved as described above; final family consumers do not claim a second CPU execution of158.
- Final self-review `git diff --check` passes. Actual source/native/reference/helper producer revisions remain separate and unchanged; no fabricated freshness or static passing execution substitutes. Report-only commit after the canonical check changes no consumed execution or proof input.

Production commits: `580b25c15` first8bodies, `58230d715` remaining recovery graph, `071929fa6` actual predecessor initialization, `fa9ab66a2` exact ordinary byte read/publication order. Fixture/helper closure `030d8a79f`; proof/ledger/map/final consumers `f69ca42e4`. No blocking concern remains within Task10. The disclosed control-flow-only maxima, future helper ownership and Tasks15/16 integration/pairing/freshness obligations remain as bounded scope, not completed work.
