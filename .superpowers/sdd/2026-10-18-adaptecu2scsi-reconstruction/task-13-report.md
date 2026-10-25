# Task13 implementation report

Status: DONE_WITH_CONCERNS, ready for controller independent review. All Task13 source, frozen public behavior, genuine native roots, both architectural context pairs, exact switch envelopes and scoped accounting are delivered. The concerns are concrete inherited current-runtime audit failures and the explicitly pending four full native builds/paired consolidation in Tasks15/16; they are not silently waived.

Worktree: `C:/Users/raynorpat/.codex/worktrees/adaptecu2scsi/RhapsodiOS`. Base: `92691668a38e846d1ba853f7b969eff25bb28dde`. Single implementer; no helper/reviewer agents. Read AGENTS.md, task13 brief/extracted/global-context and applied executing-plans, using-git-worktrees, test-driven-development, systematic-debugging and verification-before-completion. Reused the explicitly assigned existing worktree. Parent ledger and briefs were not edited.

## Delivered behavior and accounting

Created Transport19 and API42, all61 authentic symbols/bodies. `reconstruction/task13.json` binds the exact source sites, pinned reference body bytes/basic blocks/calls, actual native bytes/relocations, decoded byte/halfword/word accesses, per-body control-flow review and literal frozen cases. All61 roots have genuine native execution. The public API keeps historical typed PPC widths, callback arguments/order, scan/LUN bitmaps, mode predicates, memory partial-failure publications, configuration/profile masks, target validation, NV semantics, queue ownership, special requests, IRQ/front/back ISR and genuine state/nexus/node stubs. The eight old unspecified-argument declarations remain unspecified; varied eight-register fixtures do not invent lost formals.

Final ledger: **429 control-flow-confirmed /47 unexamined, exact476 unique addresses**; all392 CHIM bodies accounted. Map436 mapped/24 unmapped/16 duplicate candidates. Data41 recovered/2 switch-owner pending/5 controller-body pending. Only Task13's61 ledger rows and11 assigned switch records changed; prior owner proofs/data/source remain unchanged. Seven pre-existing mapped transitional controller drafts still add no CF bodies. Task14 owns the47 remaining OSM/controller/helper bodies. All16 subsystem ID/mask pairs remain stored, with reference scan bound13 accepting only14; null firmware/hardware slots and actual mode predicates remain unchanged.

## RED, bounded native batches and preserved failures

The three required named tests existed before production implementations. Initial `initial-red.log`:3 failures/143.99s; `initial-red-2.log`:3 failures/145.60s, exact error `group: owner body recovery is not implemented: AdaptecU2CHIMTransport.c`. Separate `api-initial-red.log` proves API owner failure. Authentic public prototype discovery first rejected; the approved minimal header addition made success and strict forged/missing/arity/type/return negatives pass. Authentic PCI aggregate first rejected before the approved exact mapping. No parser fallback or shared sentinel/ABI/machine-input relaxation was introduced.

Each initial source/native batch added at most8 bodies. b10 corrected one already recovered body's native storage only:

| Batch | New bodies | Names |
|---|---:|---|
| b1 | 8 | SCSIxApplyNVData, SCSIxBiosExist, SCSIxChkLunExist, SCSIxClearLunExist, SCSIxMaximizeMemory, SCSIxNonScamValidateLun, SCSIxOptimaExist, SCSIxSetLunExist |
| b2 | 8 | SCSIxCalcScsiOption, SCSIxDetermineFirmwareMode, SCSIxGetNextSubSystemSubVendorID, SCSIxGetSpeed, SCSIxPostQueueSpecialIOB, SCSIxSetupBusScan, SCSIxSetupLunProbe, SCSIxTranslateError |
| b3 | 3 | SCSIxPostBusScan, SCSIxQueueBusScan, SCSIxQueueSpecialIOB |
| b4 | 8 | SCSICreateAdapterTSCB, SCSICreateInitializationTSCB, SCSIGetConfiguration, SCSIGetFunctionPointers, SCSIGetNextHostDeviceType, SCSISetConfiguration, SCSISetupAdapterTSCB, SCSISizeAdapterTSCB |
| b5 | 8 | SCSIAdjustNodeProfile, SCSIClearNexusTSH, SCSIProfileNexus, SCSIProfileNode, SCSIReportAdjustableNodeProfile, SCSIRestoreState, SCSISaveState, SCSISetOSMNodeContext |
| b6 | 8 | SCSIClearTargetTSH, SCSIDisableIRQ, SCSIEnableIRQ, SCSIPollIRQ, SCSIPowerEvent, SCSIReportAdjustableTargetProfile, SCSISizeTargetTSCB, SCSIValidateTargetTSH |
| b7 | 8 | SCSICheckMemoryNeeded, SCSICheckTargetTSCBNeeded, SCSICreateTargetTSCB, SCSIGetNVOSMSegment, SCSIGetNVSize, SCSIInitialize, SCSISetMemoryPointer, SCSIVerifyAdapter |
| b8 | 8 | SCSIAdjustAdapterProfile, SCSIAdjustTargetProfile, SCSIGetNVData, SCSIProfileAdapter, SCSIProfileTarget, SCSIPutNVData, SCSIQueueIOB, SCSIReportAdjustableAdapterProfile |
| b9 | 2 | SCSIBackEndISR, SCSIFrontEndISR |
| b10 | 0 | Transport qualifier storage correction only |

Native15+153 Transport pairs, initial52 public cases,70 target/NV/profile cases,219 scan/ISR/verify/adjust cases and135 queue/PostBusScan selector cases were exercised during bounded fixture development; their true WIP preflight records remain separate from the final committed run. Actual observation failures were corrected in the fixtures only when justified: Bayonet's declared hardware-table pointer at adapter+268 required a symbolic pointer observation; ISR reached real OSMWriteUExact8 whose exact60-byte bounds were absent and were added. First getter fixtures lacked scripted memset/copy outcomes, a final-core freeze invocation omitted its required tag, and a Windows write EINVAL interrupted b2 freezing. Those failed logs remain, with corrected pending subsets subsequently executed. No failed attempt is relabeled as a pass.

Earlier shorthand saying b9 compiled clean was wrong and is superseded: b3..b9 Transport was the identical rejecting object with an actual224-byte uninitialized-qualifier warning. The concrete allocation mismatch, its counterexample and corrected b10 product are described below. The full warning is preserved verbatim in the original product/log/archive, not treated as harmless noise.

## Actual native producers, inputs and guest

Native compilation used the owned snapshot guest `adaptecu2scsi-kbuild`, SSH2293/QMP4693/monitor4793, private Task13 staging `/private/tmp/adaptecu2scsi-task13`, private kernel tree `/private/tmp/adaptecu2scsi-task2/src/kernel-7`. Accepted Task2 SDK/baseline was consumed unchanged. Historical environment is Apple cc-771.4/gcc2.7.2.1, GNU Make3.74, staged Samurai1.9.0, SDK `/build/bootstrap-root`, installed fat DriverKit/Objective-C/libcc/MIG inputs. `OUT/guest/environment.txt`, `handoff.md` and `baseline-final-proof.log` bind those identities; the guest stays active for the controller. No baseline source/output or another guest was overwritten/stopped.

All build producer manifests truthfully retain base926+work-in-progress. Canonical input revision is separately **5d3b106789f600dc0897003efd0d9bf8d197c020**. b9 API and b10 Transport each compile its own source plus the same6 actual project headers, all7 LF inputs exactly matching canonical Git blobs. b9's staged archive additionally contains old Transport because that original build compiled both TUs; it is preserved but is not claimed as the current Transport input. No metadata-only rebuild or producer relabel occurred.

| Actual selected TU | Batch | Object SHA256 | Canonical source SHA256 |
|---|---|---|---|
| AdaptecU2CHIMTransport.c | b10, true926+WIP | 9A8468E8A0615DC6945FB4527C1031EFAEBC41C0633352E8BB0978EB5F5CAD44 | EB34A4134420AF11FF6B05C0AB85F403C05E3F7E3D816E304B863E2E85287FCB |
| AdaptecU2CHIMAPI.c | b9, true926+WIP | 8AA19996242F653B18BD32400ECDDB5A8D16EF0F53FF5945B99A15C04104A85D | 1753029F1316526DEBD7F0069C5D17EC8AA366BC97EEC557CA5ADC3116050A04 |

The selected current `OUT/objects/task13/{objects.json,native-inputs.json,source-inputs.sha256,selection.json}` are explicitly offline indices of the original two TUs, with producer manifest/input references. Original b9/b10 manifests, commands, archives and raw input manifests remain immutable; previous top-level b9 indices are archived as `historical-b9-*`. The owner gate checks exact selected entries against each original producer and actual binary/command/log, not a synthetic new compile. b10 Transport and b9 API selected logs are empty; the original b9 Transport warning remains224 bytes. Eight committed provenance copies under `tests/task13-provenance/` bind actual launchers/scripts/input manifests to raw originals. Proof pins185 preserved native artifacts, including rejected products and exact original archive members.

Canonical LF project input closure:

| Input | SHA256 |
|---|---|
| AdaptecU2CHIMTransport.c | EB34A4134420AF11FF6B05C0AB85F403C05E3F7E3D816E304B863E2E85287FCB |
| AdaptecU2CHIMAPI.c | 1753029F1316526DEBD7F0069C5D17EC8AA366BC97EEC557CA5ADC3116050A04 |
| AdaptecU2CHIMTypes.h | EBCAF8DC111A1B45A63A17C55B35CD5D22AB35BB3AF46901EF7F16E55549772A |
| AdaptecU2CHIM.h | B5210607C79287A4071EB3921A885BBF7011F0E61F1AE7D43708A8AEEBF94106 |
| AdaptecU2CHIMPrivate.h | BB3BC6F7DF328DF7772ED2F0E74EFC4CBEED70291DC626490D91F454E19EA4C0 |
| OSMFunctions.h | F7DBE4235865185DE6B2D2F5BC1BCCB77C5E999D5968B002B00D61CE2F5EBFD3 |
| AdaptecU2SCSI.h | 3F91074F77D3AD83B41B477859C8B970ADDBBC0CA90145299277EAA8E6F6EE9C |
| AdaptecU2SCSIPrivate.h | 3FC62CD8BAC420FF920A2FAB1F9B50DE464BED138A1E502B108DCBEDAFE9C3CE |

Build launch commands used from the assigned worktree (one sequential invocation per batch, after the bounded source additions):

```powershell
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build.ps1 b1
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build.ps1 b2
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build.ps1 b3
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build.ps1 b4
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build.ps1 b5
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build.ps1 b6
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build.ps1 b7
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build.ps1 b8
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build.ps1 b9
& tools/binrecon/out/adaptecu2scsi-ppc/task13/build-transport.ps1 b10
```

Each helper stages normalized LF bytes in a uniquely named input tar, records raw/normalized/staged hashes and actual HEAD+WIP, uploads through the existing guest remote helper, executes its corresponding `build-bN.sh`, then fetches its distinct product archive. Hardcoded Task13 input/output/private staging paths were inspected before use. Compiler commands are preserved in every original `N.command` and objects.json. Exact corrected Transport compiler invocation:

```sh
cd BUILD.ninja/RELEASE_PPC && obj=locc.o && cc -static -nostdinc -nostdlib -traditional-cpp -fno-builtin -c -g -O2 -MD -imacros meta_features.h -I. -I../.. -I../../bsd -I../../bsd/include -I../../machdep -I../../bsd/netat -I../../bsd/netat/h -I../../bsd/netat/at -I/System/Library/Frameworks/System.framework/PrivateHeaders -I/System/Library/Frameworks/System.framework/Headers -I/System/Library/Frameworks/System.framework/Headers/bsd -DNEXT -DTIMEZONE="0" -DPST="0" -DINET -DMACH -DNO_DIRECT_RPC -DNETAT -DDEBUG -DARCH_PRIVATE -D_KERNEL -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DKERNEL_BUILD -D__APPLE__ -DNeXT -D_NEXT_SOURCE -arch ppc -I../../bsd/include -finline -fno-keep-inline-functions -force_cpusubtype_ALL -fwritable-strings -fno-common -msoft-float -mcpu=604 -Dppc -DPPC -Wall -Wno-four-char-constants -fpascal-strings ../../bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2CHIMTransport.c -o /private/tmp/adaptecu2scsi-task13/b10-native/1-AdaptecU2CHIMTransport.c.o
```

## Final committed runtime and actual execution

Commit **5d3b106789f600dc0897003efd0d9bf8d197c020**, `scsi: recover transport and public CHIM API`, committed27 explicit paths before either final run. All32 consumed source/Python/import/JSON/inventory-function-section/binrecon inputs were held through complete execution. The executor records both actual raw working hashes and canonical Git hashes; CRLF JSON/raw files are not relabeled as canonical LF compiled inputs. No ignored generator/model imported into the execution closure. Later audit/graph/test/proof/report edits are outside the consumed runtime closure. The inventory function-marker section stayed exact; only descriptive completion prose changed afterward.

Pinned reference:2983828 bytes, SHA `D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD`, real `C:/Users/raynorpat/Downloads/test/MOSXS12v3/mach_kernel`. Existing OUT/venv Python3.13.9/Unicorn2.1.4 was used. Known handled first-chance Windows mem_map diagnostics are already resolved in the brief/upstream FAQ/Task2; targeted pytest uses `-p no:faulthandler`. Real hook/engine/unknown-call failures remain fatal. Original noisy PASS+exit logs remain, with no environment reinstall/cross-Python reprobe.

Final commands (actual executed, stdout/stderr retained):

```powershell
$env:PYTHONPATH='tools/binrecon'
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -u src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/ppc_cases.py reference --reference tools/binrecon/out/adaptecu2scsi-ppc/reference --cases src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/task13-cases.json --contracts src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/task13-contracts.json --output tools/binrecon/out/adaptecu2scsi-ppc/objects/task13/reference-results.json > tools/binrecon/out/adaptecu2scsi-ppc/task13/final-public.log 2>&1
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -u src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/task13_execute.py --reference tools/binrecon/out/adaptecu2scsi-ppc/reference --objects tools/binrecon/out/adaptecu2scsi-ppc/objects/task13 --native C:/Users/raynorpat/.codex/worktrees/adaptecu2scsi/RhapsodiOS/tools/binrecon/out/adaptecu2scsi-ppc/objects/task13/1-AdaptecU2CHIMTransport.c.o --native C:/Users/raynorpat/.codex/worktrees/adaptecu2scsi/RhapsodiOS/tools/binrecon/out/adaptecu2scsi-ppc/objects/task13/2-AdaptecU2CHIMAPI.c.o --native C:/Users/raynorpat/.codex/worktrees/adaptecu2scsi/RhapsodiOS/tools/binrecon/out/adaptecu2scsi-ppc/objects/firmware/2-AdaptecU2CHIMTables.c.o --native C:/Users/raynorpat/.codex/worktrees/adaptecu2scsi/RhapsodiOS/tools/binrecon/out/adaptecu2scsi-ppc/objects/task12/1-AdaptecU2CHIMHIM.c.o --native C:/Users/raynorpat/.codex/worktrees/adaptecu2scsi/RhapsodiOS/tools/binrecon/out/adaptecu2scsi-ppc/objects/task11/1-AdaptecU2CHIMResource.c.o --native C:/Users/raynorpat/.codex/worktrees/adaptecu2scsi/RhapsodiOS/tools/binrecon/out/adaptecu2scsi-ppc/objects/task8/1-AdaptecU2CHIMConfig.c.o > tools/binrecon/out/adaptecu2scsi-ppc/task13/final-native.log 2>&1
```

Actual results: public787 PASS/exit0 (311470 instructions); native787 PASS/exit0 (313996 instructions), plus2 full API caller context pairs and2 exact private-byte pairs. Families: memory90, scan301, queue396. Every root entry is genuine native. Unknown calls, out-of-bounds transfers/memory, sentinel failure, SP/nonvolatile violations, unsupported instructions and budget exhaustion remain failures. Ordinary per-case limits stay <=4M; no new generic budget extension. Final runs were not repeated for metadata.

| Final artifact | Raw SHA256 |
|---|---|
| OUT/objects/task13/reference-results.json | 8682A7165634C97B0FE6459984937A1BA25B42660F76C4B3F274C73942727672 |
| OUT/objects/task13/native-results.json | E022F0C4B2B670AFA9E982670D9B6A70D326C07B8A342002F5345C5C259EF816 |
| OUT/objects/task13/native-arena.macho | 086BABB343B04F36889D56FF799DEBF65F372A357D5636B7E1C320AFA064DFAE |
| OUT/objects/task13/arena.json | 90847A7D7F4658D8C1A64C2625AEDF222F60287B9E9A030E0A77E41DBD8A689D |

Six genuine original native objects form the private supplementary arena: corrected Transport, API, accepted Tables, HIM, Resource and Config (Config owns SCSIhInitializeHardware). All remaining callees execute unchanged authenticated reference bodies. Actual reference SCSIxTranslateError code is reached as a callee at22 owned instruction addresses; proof records that limitation explicitly. All61 owned roots still execute native. This mixed closure is not any of the four full Make/Samurai RELEASE/DEBUG kernels required later.

## Architecture-context witnesses and allocation correction

The load-bearing public caller is SCSIInitialize reference1a4644..1a493c. Actual API object body0xae8..0xdc8 contains no r28 instruction; saved IDA disassembly is pinned. Genuine native callsite and original `_SCSIRInitialize` BR24 relocation are authenticated, rather than relying on generic callee-saved ABI. Final real API->Resource->HIM->Hardware entries all capture the exact incoming r28, with final SP/all nonvolatile registers preserved, actual low-byte register255 write, real full reset/4000-settle execution and strict calls/bounds. Shared public machine_inputs remains exact Hardware1931e4 only; Task13's narrow API context is separate, exact entry/seeds/authenticated image and genuine arena scoped. No new formal/default, mid-run GPR mutation or internal replacement.

| Final API context | Reference instructions | Genuine native-chain instructions | Captured r28 at all4 entries |
|---|---:|---:|---|
| task13-r28-0x12345635 | 3221241 | 3221263 | 0x12345635 |
| task13-r28-0x89abcda6 | 3221241 | 3221263 | 0x89abcda6 |

The original source private qualifier is intentionally indeterminate on status48. Reference SCSIxPostBusScan1a8180..1a86fc allocates frame0x60, stores BYTE at SP+0x38 on normal paths1a8254/1a839c, and status48 invokes real QueueSpecialIOB at1a8480. Callback changes status48->1; late1a8680 `88010038` loads that private BYTE and1a8684 `2c80007f` compares127. Original b9 frame0x50 instead compared incoming r27 at0xe68 `2c9b007f`; its uninitialized register was not the original private storage. Ordinary zero-stack/a500001b happened to choose32 in both, hiding the mismatch.

Initial narrow two-state RED seeded only the authentic reference private byte before its first instruction, leaving b9 native unchanged (it had no corresponding byte). 127 produced reference origin37 versus rejecting native32;53 produced32 both. Old b9 object `D67A5739000B7378D6B90D8976007A481587381064DB734510DFE2BF456216DA`, source `46FE6E82B2BD8551DFB5BD006F28897247B74650987651F0144B4893781B9BC2`,224-byte warning `47BF1154A983D6EE8A0A0E1F19B0AF75048FFEBFD243853874C5A2155DE80372` and raw rejecting arena remain distinct immutable evidence.

Controller ruling approved only minimal `volatile unsigned char qualifier;` (Transport.c286), separate capabilities, no initializer/default/formal. Current assignments292/296 and use351 preserve reference paths. Compiled Transport alone as b10. Independently mapped genuine b10 body0xab4..0xfec, frame0x60/private slot0x38, normal BYTE stores0xb54/0xb94, late load0xe70 `88010038`, use0xe78 `6800007f`, with no initialization or store on48. Exact committed mapping/body/object/image hashes guard each counterpart; no fixed-frame assumption for later builds.

Final frozen pre-entry contexts127/53 each seed ONLY the independently authenticated private byte before the first PPC instruction, then observe only. Both reference and corrected genuine native produce origin37/32 respectively, real callback count1, IOB status1, one exact late byte load/use, zero after-entry private stores, strict full SP/nonvolatile/bounds/unknown-call/sentinel guards. Original indeterminate machine state remains; there is no stable language-portability/default-value claim. `postscan-private-red.*`, `postscan-private-green.*`, original disassemblies, raw b9 archives/warning and final actual pairs are preserved. Tasks15/16 must independently map both patterns in EACH of all4 full native builds, alongside both API r28 contexts; current mixed proof does not satisfy that later requirement.

## Getter, aggregate and MMIO rulings

Only approved shared changes are direct strict CHIM.h prototype discovery and exact AdaptecU2PciLocation16 mapping alongside existing exact IOHandle/Profile cases. Accepted Types.h153..157/interfaces.md43 and real caller187f64/callee1a4044 authenticate r6..r9 four distinct words and productr10. Actual reference/native forwarding preserves `01020304/11223344/55667788/89abcdef` plus each full product `78959004/007f9005/12345678`; wrong width/arity/unknown alias and forged/missing public declarations remain rejected. No generic typedef or return/sentinel/machine-input guard weakening.

Getter frozen raw reference cases forward and copy0/4/168/172 bytes unchanged. There is no size clamp or size-bound branch: the172-byte case copies the168-byte table plus the following4 bytes, the actual SCSIConfiguration version word00000004, leaving only destination bytes172..175 as A5 canaries. The prior report sentence claiming a clamp was incorrect; production source, frozen cases, adapter and raw results have always preserved172. Actual `_fast_bcopy`148dd0..148df8 tailcalls memcpy148f00..149048 with mfmsr/mtmsr/dcbz and indirect alignment paths, unsupported privileged instructions in this strict runner. No real-body execution or privileged-instruction skip is claimed. Approved exact Task13-only external copy adapter obtains raw output ONLY from authenticated genuine relocated native SCSIFuncPtrs bytes. It verifies all41 exact symbolic relocation identities/version4, genuine source bytes/object hash, actual source/destination/count and176-byte A5 destination extent/canaries. Declared41 pointer fields compare symbolically; ordinary version and canary bytes compare exactly. No address-looking-value normalization or reference-address payload is substituted in native evidence. Canonical/adapted case hashes and raw outcomes stay separate; wrong table/relocation/source/count/extent/case identity negatives pass. Each later full native build must use its own genuine mapped table.

Isolated task13-api register snapshot is exactly accepted Task12 baseline canonicalSHA `4A5113A88B7D24AF5093A8E6FAC794717B936F154A4C38C864AC5F4E03B3E0C0` plus86 rows/107 directional permissions. Zero new offset-size-direction permissions relative to Task12; no duplicate offset-size row. Accepted baseline/shared contracts remain unchanged. Exact frozen union only; baseline/delta/duplicate/attribution negatives pass. Every stable combination key binds actual source owner, particular accepted callee proof, authentic linking callsite/argument and actual Task5 primitive instruction/access/count. Index covers all86 keys, with trace counts equal actual MMIO operation counts. Static authenticators check exact callback/dispatch headers, target tables/null slots, register width and actual primitive bytes. Ordinary publication gate authenticates each captured store against actual owner bounds/native-or-reference bytes, memory width and region extent; extra concrete guards retain adapter bytes31/42/43, location/product words and memory size1492 halfword/pointer1496 word. Damage negatives cover forged width/instruction/extent/owner.

## Eleven switches and41 dispatch identities

Native graph review authenticates source/owner body, actual const extent/401 relocation slots, table base HA/LO relocations, unsigned upper guard and condition/default, direct/local/tail/indirect calls and every reachable path bounded to the owner. Every native table target has actual execution coverage. NV reference12-slot switch compiles as an authenticated conditional graph; all12 normalized selectors2..13 execute with actual SEEPROM offsets32 for2/8,64 for3/12,0 otherwise and count32. Queue covers all19 slots plus unsigned default; PostBusScan all80 slots plus lower/upper defaults and real48 callback chain. Translate/BackISR cover full73/41/29 selector ranges/defaults and residual/sense effects. Exact frozen raw reference guards/default/entry envelopes remain in data.json; only recovery status/owner evidence changed.

| Reference switch | Actual owner | Native entries |
|---|---|---:|
| switch_23144c | SCSIxTranslateError | 29 |
| switch_231284 | SCSIxTranslateError | 73 |
| switch_2313a8 | SCSIxTranslateError | 41 |
| switch_2314e0 | SCSIxPostBusScan | 80 |
| switch_230f60 | SCSIProfileAdapter | 8 |
| switch_230f80 | SCSIProfileAdapter | 8 |
| switch_230fd0 | SCSIQueueIOB | 19 |
| switch_2311e4 | SCSIBackEndISR | 29 |
| switch_23101c | SCSIBackEndISR | 73 |
| switch_231140 | SCSIBackEndISR | 41 |
| switch_230fa0 | SCSIGetNVOSMSegment | 12 selectors, conditional chain |

Public table is version4,168 bytes (version word +41 32-bit pointers), pinned rawSHA `F25312DCF9A19067A8EB960AB508E83552BCC706259409C95374B12330AF2E08`. Getter itself is the42nd public body outside that41-slot table. Exact declared offsets/identities:

| Byte offset | Function |
|---:|---|
| 4 | SCSIGetNextHostDeviceType |
| 8 | SCSICreateInitializationTSCB |
| 12 | SCSIGetConfiguration |
| 16 | SCSISetConfiguration |
| 20 | SCSISizeAdapterTSCB |
| 24 | SCSICreateAdapterTSCB |
| 28 | SCSISetupAdapterTSCB |
| 32 | SCSICheckMemoryNeeded |
| 36 | SCSISetMemoryPointer |
| 40 | SCSIVerifyAdapter |
| 44 | SCSIInitialize |
| 48 | SCSISizeTargetTSCB |
| 52 | SCSICheckTargetTSCBNeeded |
| 56 | SCSICreateTargetTSCB |
| 60 | SCSIDisableIRQ |
| 64 | SCSIEnableIRQ |
| 68 | SCSIPollIRQ |
| 72 | SCSIFrontEndISR |
| 76 | SCSIBackEndISR |
| 80 | SCSIQueueIOB |
| 84 | SCSIPowerEvent |
| 88 | SCSIValidateTargetTSH |
| 92 | SCSIClearTargetTSH |
| 96 | SCSISaveState |
| 100 | SCSIRestoreState |
| 104 | SCSIProfileAdapter |
| 108 | SCSIReportAdjustableAdapterProfile |
| 112 | SCSIAdjustAdapterProfile |
| 116 | SCSIProfileTarget |
| 120 | SCSIReportAdjustableTargetProfile |
| 124 | SCSIAdjustTargetProfile |
| 128 | SCSIGetNVSize |
| 132 | SCSIGetNVOSMSegment |
| 136 | SCSIPutNVData |
| 140 | SCSIGetNVData |
| 144 | SCSIProfileNexus |
| 148 | SCSIClearNexusTSH |
| 152 | SCSIProfileNode |
| 156 | SCSIReportAdjustableNodeProfile |
| 160 | SCSIAdjustNodeProfile |
| 164 | SCSISetOSMNodeContext |

## Static gates, exact commands and inherited failures

Executed after final actual runs, without CPU corpus reruns:

```powershell
$env:PYTHONPATH='tools/binrecon'
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe tools/binrecon/out/adaptecu2scsi-ppc/task13/select-products.py
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe tools/binrecon/out/adaptecu2scsi-ppc/task13/assemble-proof.py
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -u src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/verify.py group --reference tools/binrecon/out/adaptecu2scsi-ppc/reference --repo-root . --objects tools/binrecon/out/adaptecu2scsi-ppc/objects/task13 --group AdaptecU2CHIMTransport.c
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -m pytest -p no:faulthandler -q src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/test_task13.py
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -m pytest -p no:faulthandler -q src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/test_task13.py::test_publication_rejects_damage
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -u src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/verify.py inventory --reference tools/binrecon/out/adaptecu2scsi-ppc/reference --repo-root .
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -u src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/verify.py layouts --reference tools/binrecon/out/adaptecu2scsi-ppc/reference --repo-root . --objects tools/binrecon/out/adaptecu2scsi-ppc/objects/layouts-task4
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -u src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/verify.py firmware --reference tools/binrecon/out/adaptecu2scsi-ppc/reference --repo-root . --objects tools/binrecon/out/adaptecu2scsi-ppc/objects/firmware
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -u tools/binrecon/out/adaptecu2scsi-ppc/task13/prior-static-audits.py
git diff --check
```

Results: offline assembly61 bodies/11 graphs PASS; joint owner gate PASS; final named+strict46 PASS/132.63s, including both complete owner audits and all3 required families; additional4 publication negatives PASS/2.69s; inventory PASS; layouts PASS; firmware PASS; diff check clean. An initial layout command used nonexistent OUT/objects/layouts and failed path lookup; retained `final-layouts-audit.log`, corrected to original existing layouts-task4 product and passed (`final-layouts-corrected-path-audit.log`). That path typo is not a new target-layout failure.

Prior static owner audit driver authenticates the pinned unchanged reference once, then calls original gate functions directly (no audit rule altered, no CPU execution):

```python
e = verify.authenticate_reference(out/'reference', root)
verify.audit_service_group(e, root, out/'objects/task5', 'AdaptecU2OSMServices.m')
verify.audit_service_group(e, root, out/'objects/task5', 'AdaptecU2CHIMOSD.c')
verify.audit_hardware_group(e, root, out/'objects/task6')
verify.audit_scb_group(e, root, out/'objects/task7')
verify.audit_config_group(e, root, out/'objects/task8')
verify.audit_negotiation_group(e, root, out/'objects/task9')
verify.audit_recovery_group(e, root, out/'objects/task10')
task11_audit.audit(e, root, out/'objects/task11')
task12_audit.audit(e, root, out/'objects/task12')
```

Each failure was caught only to record all independent outcomes, never converted to a pass. Actual gate results (70.50s combined):

| Gate | Current failure |
|---|---|
| Task5 OSMServices | ValueError: stale result: contracts_sha256 |
| Task5 OSD | ValueError: stale result: contracts_sha256 |
| Task6 | ValueError: stale Task6 reference result |
| Task7 | ValueError: stale Task7 reference result |
| Task8 | ValueError: stale Task8 reference result |
| Task9 | ValueError: stale Task9 reference result |
| Task10 | ValueError: stale Task10 executed input: src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/ppc_cases.py |
| Task11 | ValueError: resource executed input changed: src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/ppc_cases.py |
| Task12 | ValueError: uncommitted HIM execution input: src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/ppc_cases.py |

Task5 contracts identity predates this task and remains a concrete inherited failure. Approved minimal public header discovery/exact aggregate changes necessarily alter shared runner identity; Tasks6..12 retain their historical executed inputs/raw results and fail current freshness checks as shown. None of these current failures means a new CPU execution was attempted/passed. No accepted prior corpus was rerun solely for hashes; no old raw producer/result/proof/contracts were relabeled. Mandatory Task16 fresh consolidated runtime/all corpora/all4 pairs resolves freshness after the planned final consolidation.

Task12's historical delta test now compares its accepted after926 against before608 rather than today's later-owner ledger/data/map. It still compares current Task12 proof to canonical Git HEAD. Controller approved test-only historical pin; explicit extra/missing nonowner/own-switch mutations reject. First damage test exposed missing-own-switch assertion, now exact old-record+recovered+Task12owner_evidence is required. Historical guard focused run5 PASS/3.00s,4 damage cases included again in final46. This does not repair the inherited zip/ledger-cardinality minor; Task13 uses address-keyed exact476/61 cardinality and append/delete/duplicate/wrong-tail negatives.

Pending inherited obligations remain explicit for Task16: Task12 M1 exact16 ledger/cardinality guard; M2 Task5 stale contracts identity and fresh consolidation; M3 two historical EOF notices; Task11 M1 compiler warning/M2 attribution/M3 historical LF/CRLF; Task9 observer-cache and UnitHandle alias; earlier accepted Task5/6 header/raw source and copied Task7/8 attribution/portability issues. Physical hardware timing/validation is separate. No generic runtime, type, copy, stack or allocation waiver was introduced.

## All61 source/native control-flow reviews

Each row points into the exact authenticated body review in task13.json. Complete actual reference/native SHA, basic blocks, calls, relocations, instruction widths and fixture IDs live there; status is control-flow-confirmed, not an assertion that every defensive input was exhaustively executed.

| Function | Reference address | Source line | Native body start/size | Root cases | Review |
|---|---|---:|---|---:|---|
| _SCSIxMaximizeMemory | 0x1a3e68 | 6 | 0x0/76 | 1 | Six descriptors only; independently maximize ushort size and byte alignmentMask, preserving all other descriptor bytes. |
| _SCSIxNonScamValidateLun | 0x1a4cbc | 18 | 0x4c/64 | 2 | Test current bitmap at target index and LUN0, ignoring stored target LUN; return0 for present or2 for absent. |
| _SCSIxTranslateError | 0x1a7924 | 158 | 0x570/464 | 192 | Retain status2 host4..32, status3 host0..72 and nested target0..40 tables/default aliases; autosense/residual width and255 correction; unsupported statuses leave IOB unchanged. |
| _SCSIxApplyNVData | 0x1a7cb4 | 24 | 0x8c/28 | 1 | Publish word nvTargetMask=ffff then return1, retaining the intentionally minimal NV implementation. |
| _SCSIxBiosExist | 0x1a7cd0 | 30 | 0xa8/16 | 1 | Intentional input-erased constant return0; no BIOS discovery side effects are invented. |
| _SCSIxOptimaExist | 0x1a7ce0 | 35 | 0xb8/16 | 1 | Intentional input-erased constant return0; no Optima discovery side effects are invented. |
| _SCSIxChkLunExist | 0x1a7cf0 | 40 | 0xc8/40 | 3 | Compute unsigned bit=(target<<6)+lun, load one bitmap byte, return selected bit as0/1. |
| _SCSIxSetLunExist | 0x1a7d18 | 47 | 0xf0/48 | 3 | Compute unsigned bit=(target<<6)+lun, perform byte read/or/write only at bit>>3; preserve adjacent bytes. |
| _SCSIxClearLunExist | 0x1a7d48 | 54 | 0x120/48 | 3 | Compute unsigned bit=(target<<6)+lun, perform byte read/and/write only at bit>>3; preserve adjacent bytes. |
| _SCSIxSetupBusScan | 0x1a7d78 | 123 | 0x3f4/180 | 2 | Zero128 current bitmap and40 target bytes; type2/adapter pointer; skip hostID; clear tagged/retry words; optional16 ushort flag clears and EnableExpStatus. |
| _SCSIxSetupLunProbe | 0x1a7e38 | 141 | 0x4a8/200 | 4 | Clear current/previous one LUN each; zero40-byte target, publish byte arguments as target/lun words andtype2/adapter; preserve reference uchar truncation of tagged-target mask. |
| _SCSIxQueueBusScan | 0x1a7ee8 | 212 | 0x740/672 | 1 | Zero108-byte IOB and88-byte reserve; real three bus-address callbacks, little-endian8-byte SG, flush64; unit setup/negotiation and real QueueIOB, retaining exact publication order. |
| _SCSIxPostBusScan | 0x1a8180 | 280 | 0xab4/1336 | 115 | Unsigned status-1 guard79/table80; success qualifier/capabilities/bitmap paths,32 advances LUN,48 real special11 chain,66/67/75/80 early posts, one retry and probe/scan completion. Original uninitialized private qualifier BYTE is materialized volatile, no default; exact two-state architectural witness binds actual storage/load/use. |
| _SCSIxQueueSpecialIOB | 0x1a86fc | 263 | 0x9e0/212 | 1 | Zero108-byte IOB, reserve size88 but clear only72 bytes, bus-address callback and real unit setup; publish function/post and call real QueueIOB. |
| _SCSIxPostQueueSpecialIOB | 0x1a87cc | 61 | 0x150/28 | 4 | Return unsigned boolean IOB.status!=1 with no callback or memory mutation. |
| _SCSIxGetSpeed | 0x1a87e8 | 66 | 0x16c/192 | 16 | Mask ushort rate70; fast mappings200/160/133 and legacy100/80/67/57/50/44/40, fallback36; uchar fastMode boundary retained. |
| _SCSIxCalcScsiOption | 0x1a88dc | 85 | 0x22c/232 | 50 | Unsigned range subtraction for rate thresholds and special200; merge offset low4; width16 adds80 with original uchar cast only on wide result. |
| _SCSIxDetermineFirmwareMode | 0x1a89bc | 103 | 0x314/168 | 5 | Call genuine SetupHardware first; Bayonet maskff80ffff==9005 selects4/5 by external RAM, legacyfff0ffff==78909004 selects0/3, generic3. |
| _SCSIxGetNextSubSystemSubVendorID | 0x1a8aa4 | 113 | 0x3bc/56 | 5 | Unsigned index<=13 returns pair and writes mask;14/15 physical tail pairs intentionally remain outside public bound; higher indices return0 without write. |
| _SCSIGetFunctionPointers | 0x1a3d04 | 6 | 0x0/52 | 4 | Forward actual SCSIFuncPtrs source,destination,size unchanged to real external fast_bcopy boundary; no invented bound. Version4/all41 genuine native relocations and0/4/168/172 copy extents authenticated separately. |
| _SCSIGetNextHostDeviceType | 0x1a3d38 | 12 | 0x34/76 | 5 | Unsigned index<=39 plus nonzero type gates two output writes; null slot39 and all higher indices leave output canaries untouched and return0. |
| _SCSICreateInitializationTSCB | 0x1a3d80 | 24 | 0x80/240 | 1 | Publish type0; copy68-byte configuration; get mode3/mode0 tables, maximize, zero72-byte third table, maximize; get mode4/mode5 tables and maximize; return original storage. |
| _SCSIGetConfiguration | 0x1a3eb4 | 40 | 0x170/40 | 3 | Copy exactly68 bytes from initialization+364 into configuration; productID is intentionally unused. |
| _SCSISetConfiguration | 0x1a3edc | 47 | 0x198/340 | 6 | Unsigned count4..255,reserve88,mapped<=2 validation; regenerate mode3/0 tables, zero72-byte third and maximize; repeated lowest-set-bit reduction mutates requested count before mode4/5; final exact68-byte copy. |
| _SCSISizeAdapterTSCB | 0x1a4034 | 83 | 0x2ec/16 | 3 | Return historical enclosing allocation2600, independently of initialization/product arguments and prefix-view sizeof. |
| _SCSICreateAdapterTSCB | 0x1a4044 | 89 | 0x2fc/244 | 3 | Type1/count byte/context/mapped publications; product masks select modes0/4/3 and72-byte memory table; exact16-byte PCI aggregate r6..r9 plus full productr10 preserved and observed. |
| _SCSISetupAdapterTSCB | 0x1a4138 | 117 | 0x3f0/48 | 3 | Copy caller-specified byte extent into adapter OSM table+1560 via external boundary, then return0; no speculative clamp. |
| _SCSICheckMemoryNeeded | 0x1a4168 | 217 | 0x61c/452 | 25 | Adapter index0 clears/regenerates six descriptors by firmware mode; initialization path selects product table; indices0..5 expose byte/ushort fields and zero-size fallback4;6=160/7=114 special buffers; higher0. |
| _SCSISetMemoryPointer | 0x1a433c | 260 | 0x7e0/88 | 6 | Indices0..5 publish address word and truncate size ushort, category ignored;6/7 publish scan pointers; other indices return1 without mutation. |
| _SCSIVerifyAdapter | 0x1a439c | 273 | 0x838/688 | 3 | Read PCI command, require selected IO/memory enable; enable busmaster if needed; real map failure5; publish callback pointers; subsystem filter and product equality; select firmware/buildSCB/stride,16 LUN counts, real configuration capped to prior count. |
| _SCSIInitialize | 0x1a4644 | 334 | 0xae8/736 | 2 | Real Resource/HIM apply-memory partial failure before NV/flags; original BIOS/Optima stubs choose reset path; preserve byte/ushort device fields and PCI64 adjustment; real Resource->HIM->Hardware initialization keeps incomingr28 through authentic API callsite. |
| _SCSISizeTargetTSCB | 0x1a4940 | 169 | 0x498/16 | 1 | Return historical enclosing target allocation40; no trailing-prefix sizeof assumption. |
| _SCSICheckTargetTSCBNeeded | 0x1a4950 | 387 | 0xdc8/264 | 4 | ffff queries last target/LUN current-vs-previous; ordinary path scans16 targets and configured LUN counts for first difference; return boolean without mutation. |
| _SCSICreateTargetTSCB | 0x1a4a64 | 403 | 0xed0/412 | 4 | ffff uses last tuple, ordinary scans first changed bitmap; absent returnsnull; previous bit is set even for disappearance; type2/adapter/target/LUN and tagged highflag published, real UnitHandle then storage returned. |
| _SCSIDisableIRQ | 0x1a4c04 | 174 | 0x4a8/36 | 1 | Forward exact adapter+24 HHCB to genuine HIM disable; retain void result and actual byte MMIO operations. |
| _SCSIEnableIRQ | 0x1a4c28 | 179 | 0x4cc/36 | 1 | Forward exact adapter+24 HHCB to genuine HIM enable; retain void result and actual byte MMIO operations. |
| _SCSIPollIRQ | 0x1a4c4c | 184 | 0x4f0/48 | 4 | Forward exact adapter+24 HHCB to HIM poll and convert result to unsigned boolean. |
| _SCSIPowerEvent | 0x1a4c78 | 189 | 0x520/36 | 6 | Forward exact HHCB and full unmodified opaque event word to ResourcePowerManagement; preserve arbitrary values and busy result. |
| _SCSIValidateTargetTSH | 0x1a4c9c | 194 | 0x544/32 | 2 | Forward genuine target to NonScamValidateLun, retaining its LUN0 validation and0/2 return. |
| _SCSIClearTargetTSH | 0x1a4cfc | 199 | 0x564/136 | 2 | Busy ResourceCheckDeviceIdle returns6; idle clears current/previous exact bitmap bits, frees real unit and returns0. |
| _SCSISaveState | 0x1a4d78 | 125 | 0x420/12 | 3 | Accepted legacy machine-only unspecified-argument exception: preserve incoming machine r3 unchanged with explicit target register output, no invented C formal. |
| _SCSIRestoreState | 0x1a4d84 | 132 | 0x42c/12 | 3 | Accepted legacy machine-only unspecified-argument exception: preserve incoming machine r3 unchanged with explicit target register output, no invented C formal. |
| _SCSIProfileAdapter | 0x1a4d90 | 496 | 0x1414/992 | 20 | Copy464-byte default after real HW profile; ID/BIOS/targets/threshold8+8 tables, fixed width words/16LUNs, actual cache callback and byte hardware revision atword46 retained. |
| _SCSIReportAdjustableAdapterProfile | 0x1a5170 | 568 | 0x17f4/104 | 2 | Copy464 adjustable bytes; legacy hardware explicitly clears three separate-RW threshold words, Bayonet retains template. |
| _SCSIAdjustAdapterProfile | 0x1a51d0 | 580 | 0x185c/856 | 3 | Initialized/busy returns2; changed hostID or incompatible separate threshold returns7;16 uchar LUN truncations, exact legacy/Bayonet threshold bands and flag masks; real ResourcePutHWInformation. |
| _SCSIProfileTarget | 0x1a5520 | 619 | 0x1bb4/408 | 6 | Get real HW info,copy124-byte default; BIOS drive scan, target/LUN/tag/depth/speed/offset/width fields; option143 special sentinel values and disconnect bit retained. |
| _SCSIReportAdjustableTargetProfile | 0x1a56c4 | 210 | 0x5ec/48 | 2 | Copy exactly124 adjustable target bytes; unused leading word is not interpreted as target; return0. |
| _SCSIAdjustTargetProfile | 0x1a56f4 | 655 | 0x1d4c/784 | 4 | Busy6; retain width/sync capability gates and requested/current offset distinction; tagged/disconnect masks; optional signed selector-32/-31 scratch byte RMW; queue depth uchar truncation and real hardware put. |
| _SCSIGetNVSize | 0x1a5a00 | 434 | 0x106c/160 | 10 | OSM nonzero size wins; otherwise genuine SEEPROM size partitioned by two-bit idConfiguration mode as2x,x,2x/3,x/2. |
| _SCSIGetNVOSMSegment | 0x1a5ad4 | 448 | 0x110c/496 | 21 | OSM nonzero size returns2; mode/location switch12 selects wordoffset0/32/64, mode3 unsigned location-4, mode1 channel/slot test; genuine read failure2; exact partitioned offset/size publications. |
| _SCSIPutNVData | 0x1a5ce8 | 476 | 0x12fc/132 | 2 | Forward full byte offset/count/data to real OSM; only status3 falls back to genuine word-addressed SEEPROM write, boolean return. |
| _SCSIGetNVData | 0x1a5d70 | 488 | 0x1380/148 | 2 | OSM success returns0 without SEEPROM; any nonzero OSM result falls back to genuine read with byteOffset/count shifted right1; boolean result. |
| _SCSIProfileNexus | 0x1a5e00 | 139 | 0x438/16 | 3 | Accepted legacy unspecified-argument machine-only constant r3=1 stub, varied incoming argument registers retained in fixtures. |
| _SCSIClearNexusTSH | 0x1a5e10 | 144 | 0x448/16 | 3 | Accepted legacy unspecified-argument machine-only constant r3=1 stub, no invented nexus lifecycle behavior. |
| _SCSIProfileNode | 0x1a5e20 | 149 | 0x458/16 | 3 | Accepted legacy unspecified-argument machine-only constant r3=1 stub, no invented node profile side effects. |
| _SCSIReportAdjustableNodeProfile | 0x1a5e30 | 154 | 0x468/16 | 3 | Accepted legacy unspecified-argument machine-only constant r3=1 stub, no invented node profile copy. |
| _SCSIAdjustNodeProfile | 0x1a5e40 | 159 | 0x478/16 | 3 | Accepted legacy unspecified-argument machine-only constant r3=1 stub, no invented node mutation. |
| _SCSISetOSMNodeContext | 0x1a5e50 | 164 | 0x488/16 | 3 | Accepted legacy unspecified-argument machine-only constant r3=1 stub, no invented context publication. |
| _SCSIQueueIOB | 0x1a5e60 | 717 | 0x205c/1220 | 20 | Normal path constructs genuine reserve+32 HIOB, exact control-bit widths/order and byte sense truncation, resource/device/host/SCB dispatch; special unsigned function-1 table19 plus defaults, real related/unit/HHCB and callback paths, LUN-probe19 logic. |
| _SCSIFrontEndISR | 0x1a62cc | 810 | 0x2520/548 | 6 | Count qout8-byte entries/pass with uchar wrapping; cached count/interrupt flags byte stores; retry-at-most-once INTSTAT and pause/control paths; sync and boolean return. |
| _SCSIBackEndISR | 0x1a64ec | 862 | 0x2744/2708 | 166 | Real qout completion/SCB/resource queues, manager5 bypass and special completions; interrupt dispatch/clear/restore loop; sync then done-ring drain; inlined host73/target41/host29 error tables preserve all aliases/widths and sense/residual publication before real post callback. |

## Self-review and handoff

Reviewed all61 source bodies against pinned IDA pseudocode/instructions and saved body/call/width records, all11 actual native graphs and their reference envelopes, exact public dispatch table/version/copy bounds, partial failures/callback effects, and typed PPC interfaces. Direct r28 caller evidence and the original private-byte state-source mismatch were treated separately; the latter required rejecting old native evidence and recompiling only Transport. Selected original producers and canonical LF inputs remain distinct. Reviewed strict negative scopes and final import closure. No source cleanup, new adapter policy, fake table pointer output, internal call replacement, widened shared machine context or changed prior source/proof is included.

Final canonical Git delta regression/commit details are appended after the metadata commit. The final consumed runtime remains5d; metadata commits must not be described as new CPU producers. Parent performs the independent review. Owned snapshot guest/private outputs/IDA evidence and ignored archives remain available; no shutdown/cleanup was requested. Complete four-build Make/Samurai compile/link/native pairing is still Tasks15/16.


Final metadata commit: **efe47711ee1893352a63648a20323c4de4660bf1**, `scsi: bind transport API recovery evidence`. Actual consumed source/runtime remains5d; no final CPU run was repeated. After that commit, exact command:

```powershell
$env:PYTHONPATH='tools/binrecon'
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -m pytest -p no:faulthandler -q src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/test_task13.py::test_task13_canonical_git_and_exact_owner_delta > tools/binrecon/out/adaptecu2scsi-ppc/task13/final-canonical-git.log 2>&1
```

Result: **1 PASS/0.65s/exit0**. It checks current proof against canonical Git blob; exact476 unique ledger addresses/429CF;61 owned body artifact bindings and unchanged nonowner rows; exact11-only switch delta; source-map436/24/16 and original nonowner mappings. Separate precommit scope check and final32input canonical closure PASS. Targeted verification totals51 checks across46 named/strict +4 publication negatives +1 canonical delta, all passed; no broad old CPU rerun. Canonical Task13 proof SHA **AC0332414CB305C3BA675D7194936BE44D062A10C2EC6BDA164AB30522DD6629**. Final genuine API->Resource callsite0x1100da0 has bytes483002a9 targeting0x1401048, HHCB argument0x70000018; both frozen r28 seeds remain at each real chain entry. Raw final results remain exactly the hashes above. Final handoff status stays DONE_WITH_CONCERNS for the concrete inherited freshness failures/four-build obligations, ready for independent controller review.


## Pre-review getter clarification

Controller caught a report-only contradiction in the getter chapter. The former sentence �actual branch clamps to168� is corrected above. Neither the52-byte pinned reference getter nor the delivered native/source getter has such a comparison/branch. Existing proof body review already states `source,destination,size unchanged` and `no invented bound`; proof and all61 ledger artifact hashes remain unchanged.

Pinned reference SCSIGetFunctionPointers1a3d04..1a3d38, bodySHA6DEA591A4B25724E34954CEC5592C260D5D0CBB9115CBE0FAA23A10474CEB993, actual IDA instructions:

```text
1a3d04 7c0802a6  mflr r0
1a3d08 90010008  stw r0,8(r1)
1a3d0c 9421ffc0  stwu r1,-64(r1)
1a3d10 7c601b78  mr r0,r3       ; save incoming destination
1a3d14 7c852378  mr r5,r4       ; forward incoming size unchanged
1a3d18 3c600028  lis r3,0x28
1a3d1c 3863b398  addi r3,r3,-19560 ; source=0x27b398
1a3d20 7c040378  mr r4,r0       ; copy destination
1a3d24 4bfa50ad  bl 0x148dd0    ; _fast_bcopy(source,destination,size)
1a3d28 38210040  addi r1,r1,64
1a3d2c 80010008  lwz r0,8(r1)
1a3d30 7c0803a6  mtlr r0
1a3d34 4e800020  blr
```

For final case `task13-SCSIGetFunctionPointers-172`, both held5d raw results contain actual external-boundary trace `_fast_bcopy(SCSIFuncPtrs,table+0,172)` (r5=172),14 runner-counted instructions. Frozen reference external outcome writes172 bytes, with00000004 at destination168..171 and A5 only at172..175. Native adapted outcome also writes172, after validating the immutable original Table object/41 exact relocations/genuine relocated pointer bytes. `getter_copy` authenticates a mapped source section through source+172, reads `raw[offset:offset+172]`, checks both initial and adjacent version words00000004, then supplies `source[:count]`; there is no min(count,168) or synthetic source tail.

Exact source adjacency: reference `_SCSIFuncPtrs`0x27b398..0x27b440, then `_SCSIConfiguration` at0x27b440 whose first4 bytes are00000004. Genuine accepted Tables object has table source0x778..0x820, then Configuration source0x820 (68-byte extent). Final relocated table0x1200778..0x1200820 and Configuration0x1200820..0x1200864; native172-byte source range0x1200778..0x1200824 therefore includes that genuine adjacent word. It lies inside authenticated __AU22,__data section0x1200000..0x1200d04. The external copy boundary remains modeled under the approved exact getter ruling; privileged fast_bcopy/memcpy execution is not claimed.

Clarification used only saved raw-result reads, authenticated Mach-O byte/symbol inspection, existing Python adapter validation without PPC execution, and actual pinned IDA read-only disassembly. `OUT/task13/getter-clarification.log` and `getter-forwarding-disasm.json` retain the concrete evidence. All32 canonical execution inputs, raw public/native/arena hashes and canonical proof AC0332414CB305C3BA675D7194936BE44D062A10C2EC6BDA164AB30522DD6629 were rechecked unchanged; no CPU case was rerun or relabeled. The original held5d producer remains authoritative.
