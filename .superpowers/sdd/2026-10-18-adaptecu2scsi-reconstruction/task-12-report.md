# Task12 hardware-interface reconstruction report

Base: `608e9f524deeaaa79910e484ee9c5008be3f863c`. Work only in `C:/Users/raynorpat/.codex/worktrees/adaptecu2scsi/RhapsodiOS`; unrelated `D:/RhapsodiOS` work untouched. Single implementer; no helper/reviewer agents. Controller independent review follows this report.

All31 `SCSIH*` bodies are implemented in `AdaptecU2CHIMHIM.c`, including interleaved `SCSIHSetupHardware@0x192304`. Current ledger closure is368 control-flow-confirmed/108unexamined. Source map375mapped/85unmapped/16duplicate candidates/0disputes; the7pre-existing mapped transitional drafts are not extra CF bodies. Data30recovered/13switch-owner-CF pending/5controller-data pending. Only31 ledger rows and assigned `switch_230ed4` semantic data row changed.

## Actual producers and scope

Canonical source/runtime freeze: `78b79a22bdbdde4f6b88792bc650035590bb17c3`. All final135 cases were validated individually on reference before this commit; full compiled preflight also passed135+2context pairs+2FreeUnit pairs+8native switch paths before freeze. Final public CLI and supplementary executions ran from that commit with HEAD and all actual runtime inputs held until both completed. No fixture/permission expansion after execution. Later proof/audit/report commits are postprocessing, not relabeled CPU/native producers.

| Evidence | Actual result | Raw SHA-256 |
| --- | --- | --- |
| Public `objects/task12/reference-results.json` |135 cases,6,304,724 instructions |`51862BF8A2413865A9050865197544C185753E4EC4DD4CAA4C0BB5F24172A2AD` |
| Supplementary `objects/task12/native-results.json` |135 mixed compiled cases,6,305,734 instructions;2 real caller context pairs;2 FreeUnit pairs;8native switch paths |`8F55988ECAE4B9270E7257B3956B8D309CE8524D5914F50C4618F716E4A3C39E` |
| Private arena Mach-O |Actual native HIM+accepted Config+accepted Resource; unchanged reference code/sections for remaining callees |`941F3CAF05F505C72329FB7D8633E9266B3BE6016E49CDA30E2B09C0160F464D` |
| Actual arena relocation/definition manifest |Genuine object relocations and exact body/section mappings |`D1CB7DB3FF4DDB7E172D3A793CA0C8F8DC52B47C9E4EE3F0458AF09C61C1CB90` |

The supplementary image is a mixed closure, not a reconstructed full kernel or a full native call chain. All remaining driver callees execute pinned actual reference bodies. The strict public runner, shared contracts and its exact `0x1931e4` machine-input exception are unchanged. No code body replacements, instruction skipping, counter patches or mid-execution register changes occur. Unknown internal transfers, memory bounds, SP, sentinel and all r14..r31 checks remain strict. Hooks capture observations only.

## Native compilation and canonical input reuse

Four source batches add8/8/8/7 bodies. Historical RELEASE_PPC compile batches1..4 each passed with empty `1.log`. Final actual object is batch4, original producer base `608e9f524deeaaa79910e484ee9c5008be3f863c` plus `work_in_progress:true`, not the later source/runtime commit. Original manifests, input/product archives, commands and raw logs remain unchanged under `OUT/task12`. The recorded exact-input reuse ruling allows the batch4 object: all7 actual compiled LF/archive bytes equal canonical Git blobs at78b79a22b. No metadata-only rebuild occurred.

| Compiled LF input | SHA-256 |
| --- | --- |
| `AdaptecU2CHIMHIM.c` |`8D525340984B297A107475149AD714EAD06073A04220E6FC5C1F6B5B3E8E0F5F` |
| `AdaptecU2CHIMTypes.h` |`EBCAF8DC111A1B45A63A17C55B35CD5D22AB35BB3AF46901EF7F16E55549772A` |
| `AdaptecU2CHIM.h` |`B5210607C79287A4071EB3921A885BBF7011F0E61F1AE7D43708A8AEEBF94106` |
| `AdaptecU2CHIMPrivate.h` |`BB3BC6F7DF328DF7772ED2F0E74EFC4CBEED70291DC626490D91F454E19EA4C0` |
| `OSMFunctions.h` |`F7DBE4235865185DE6B2D2F5BC1BCCB77C5E999D5968B002B00D61CE2F5EBFD3` |
| `AdaptecU2SCSI.h` |`3F91074F77D3AD83B41B477859C8B970ADDBBC0CA90145299277EAA8E6F6EE9C` |
| `AdaptecU2SCSIPrivate.h` |`3FC62CD8BAC420FF920A2FAB1F9B50DE464BED138A1E502B108DCBEDAFE9C3CE` |

Actual object SHA-256 `2FCD3D06DC2A5DD6EB584DE744D367779DA5DEE39EEAEFA2B15901DDCAC2EDC9`; source SHA-256 `8D525340984B297A107475149AD714EAD06073A04220E6FC5C1F6B5B3E8E0F5F`. Raw actual manifests and compiler launcher/input copies are recorded in task12.json; the committed `tests/task12-build-provenance/` copies preserve the historical producer identities and canonical hashes. Bulk native archives and SDK/guest evidence stay ignored as required.

The compile used the existing owned snapshot guest `adaptecu2scsi-kbuild`, SSH2293/QMP4693/monitor4793. QMP identity was checked before use; no guest restart/shutdown or name-based process termination occurred. Private staging `/private/tmp/adaptecu2scsi-task12` and intended source `/private/tmp/adaptecu2scsi-task2/src/kernel-7` paths were inspected before copied helpers ran; independent `baseline-sdk/tree` was preserved. Compiler: Apple cc-771.4/gcc2.7.2.1 with `-arch ppc -mcpu=604 -msoft-float`, Samurai1.9.0 prepared RELEASE_PPC environment and accepted Task2 SDK/bootstrap framework links. `guest/environment.txt` contains initial diagnostics, including the initial absentcc1 path; later accepted `baseline-final-proof.log`/handoff document the working staged environment. These are inherited preparation evidence, not fresh Task12 full-kernel builds.

The exact actual compiler command is preserved in `OUT/objects/task12/1.command`:

```text
cd BUILD.ninja/RELEASE_PPC && obj=locc.o && cc -static -nostdinc -nostdlib -traditional-cpp -fno-builtin -c -g -O2 -MD -imacros meta_features.h -I. -I../.. -I../../bsd -I../../bsd/include -I../../machdep -I../../bsd/netat -I../../bsd/netat/h -I../../bsd/netat/at -I/System/Library/Frameworks/System.framework/PrivateHeaders -I/System/Library/Frameworks/System.framework/Headers -I/System/Library/Frameworks/System.framework/Headers/bsd -DNEXT -DTIMEZONE="0" -DPST="0" -DINET -DMACH -DNO_DIRECT_RPC -DNETAT -DDEBUG -DARCH_PRIVATE -D_KERNEL -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DKERNEL_BUILD -D__APPLE__ -DNeXT -D_NEXT_SOURCE -arch ppc -I../../bsd/include -finline -fno-keep-inline-functions -force_cpusubtype_ALL -fwritable-strings -fno-common -msoft-float -mcpu=604 -Dppc -DPPC -Wall -Wno-four-char-constants -fpascal-strings ../../bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2CHIMHIM.c -o /private/tmp/adaptecu2scsi-task12/batch4-native/1-AdaptecU2CHIMHIM.c.o
```

`task12.json/native_artifacts` pins the actual manifest, inputs, object, command, diagnostics, source/header hash lists, complete raw input/product archives and inherited guest/environment evidence. `native_build_provenance_copies` binds committed original launchers/input JSON to original raw identities. `execution_inputs` includes the complete actual launcher/import/JSON/production declaration closure: task12_execute/identity/link/native/inputs, reused task11_native leaf helper, ppc_cases/reference, binrecon readers/source_paths, both case documents, snapshot, seven source/header inputs and frozen inventory function block. No ignored generator, model or common runtime import participates. The public extracted reference.json bulk identity input is separately pinned in execution_artifacts and authenticated by the owner gate.

## 31-body control-flow and actual coverage table

All addresses are reference starts. Reference extents/native bodies and exact Mach-O relocations are independently bound in task12.json. `cases` below means an actually observed entry (or explicit direct native/reference no-op leaf), not merely inclusion in an internal allowed range. Every row reaches intermediate control-flow-confirmed.

| Body / reference start | Reviewed behavior | Actual current case IDs |
| --- | --- | --- |
| `SCSIHGetConfiguration` `0x191f44` | Read8 HCNTRL135; replace flags4000 from bit0; clear bits40/1 when40 set, setup environment, pause iff bit4 clear, prepare config, typed firmware getConfig, hardware config, restore old control iff originally running; sync, return0. | `task12-b1-getconfig-3`; `task12-b1-getconfig-5`; `task12-b5-getconfig-control-0`; `task12-b5-getconfig-control-196`; `task12-b5-getconfig-control-197` |
| `SCSIHGetMemoryTable` `0x192064` | Byte fields and halfword sizes only across descriptor0/1/2/4; qout8*(ucharScbs+1), firmware word04 stride, minimum4*stride; table4.size retained/copied to minimum; table3 untouched. Firmware index uchar. | `task12-b1-memory-0-4`; `task12-b1-memory-0-255`; `task12-b1-memory-3-4`; `task12-b1-memory-3-255`; `task12-b1-memory-4-4`; `task12-b1-memory-4-255`; `task12-b1-memory-5-4`; `task12-b1-memory-5-255` |
| `SCSIHApplyMemoryTable` `0x19213c` | Publish qout C4/activeHiobs538/scbBuffersD0 pointers before failure; quotient table1 ushort size/firmware stride truncated uchar; lower count<=3 returns1 without count publication, lower>=4 publishes byte; otherwise return0. | `task12-b1-apply-0-2`; `task12-b1-apply-0-4`; `task12-b1-apply-0-8`; `task12-b1-apply-0-255`; `task12-b1-apply-3-2`; `task12-b1-apply-3-4`; `task12-b1-apply-3-8`; `task12-b1-apply-3-255`; `task12-b1-apply-4-2`; `task12-b1-apply-4-4`; `task12-b1-apply-4-8`; `task12-b1-apply-4-255`; `task12-b1-apply-5-2`; `task12-b1-apply-5-4`; `task12-b1-apply-5-8`; `task12-b1-apply-5-255` |
| `SCSIHInitialize` `0x1921b8` | WriteHCNTRL4; optional hardware5C seqStretchWorkaround then optional firmware80 configureScbRam; firmware54 setupSequencer failure returns-1 immediately. Success hardware reset, firmware58 resetSoftware, HardwareInitialize with unchanged incomingr28, optional flags40000000 ResetScsi+Delay4000, start sequencer, sync return0. Reference/native onlyr31 local. | `task12-b1-initialize-failure`; `task12-b5-initialize-real-success`; `task12-b6-initialize-configure-failure`; `task12-b7-initialize-reset-settle` |
| `SCSIHSetupHardware` `0x192304` | Interleaved192304 owner: select actual SCSIHardware[uchar hardwareMode] and publish pointerHHCB244; no invented validation or allocation. | `task12-b1-setup-0`; `task12-b1-setup-1` |
| `SCSIHSizeSEEPROM` `0x19cb4c` | Read control/pause ifrunning; hardwareMode0 presence write/read30 bit8 failure goes through restore. worddc lowbyte0->64,1->128,other->0; restore and return. | `task12-b4-size-0-0-False`; `task12-b4-size-0-0-True`; `task12-b4-size-0-1-True`; `task12-b4-size-0-2-True`; `task12-b4-size-1-0-True`; `task12-b4-size-1-1-True` |
| `SCSIHReadSEEPROM` `0x19cc94` | Read/pause; hardwareMode0 presence failure returns1 WITHOUT restore. Write30=32/waitbit16; signed wordCount loop actual ReadE2Register(wordOffset+i,handle*,widthbyte); write30=0, conditional restore, return0. | `task12-b4-eeprom-early-True`; `task12-b4-eeprom-True-0-0-2`; `task12-b4-eeprom-True-1-1-1`; `task12-b4-eeprom-True-1-0--1` |
| `SCSIHWriteSEEPROM` `0x19cea4` | Read/pause; mode0 presence failure returns1 WITHOUT restore. widthbyte selects enable192/address&#124;768/10bits or48/address&#124;192/8bits. Real SendE2Address, waitbit16, signed loop, waitbit1, real WriteE2Register with ushort data, disable/send0/write30=0, restore return0. | `task12-b4-eeprom-early-False`; `task12-b4-eeprom-False-0-0-2`; `task12-b4-eeprom-False-1-1-1`; `task12-b4-eeprom-False-1-0--1` |
| `SCSIHSetUnitHandle` `0x19d89c` | Publish HHCB pointer, target/lun byte fields and device pointerHHCB32+10*target into16-byte unit prefix; preserve all other bytes. | `task12-b1-unit-0`; `task12-b1-unit-15`; `task12-b1-unit-7` |
| `SCSIHFreeUnitHandle` `0x19d8d0` | Genuine no-op for unit-or-HHCB void* alias; no reads/writes. Actual direct two native/reference leaves; public alias ABI parser remains explicitly deferred to16. | `task12-native-freeunit-unit`; `task12-native-freeunit-hhcb` |
| `SCSIHDisableIRQ` `0x19d8dc` | Read8 HCNTRL135; clear bit2 by AND253, forward uchar to real SCSIhWriteHCNTRL, sync. Wrapper owns read; hardware callee owns resulting write. | `task12-b2-SCSIHDisableIRQ` |
| `SCSIHEnableIRQ` `0x19d944` | Read8 HCNTRL135; set bit2 by OR2, forward uchar to real SCSIhWriteHCNTRL, sync. Distinct operation-owner attribution retained. | `task12-b2-SCSIHEnableIRQ` |
| `SCSIHPollIRQ` `0x19d9ac` | HardwareFlags100000 selects real SCSIhWWReadINTSTAT(handle-pointer), otherwise direct OSMReadUExact8 aggregate-handle+145; return low four bits as uchar. | `task12-b2-poll-False-False-171`; `task12-b2-poll-True-True-165`; `task12-b2-poll-True-False-162`; `task12-b2-poll-True-False-173` |
| `SCSIHQueueHIOB` `0x19da14` | Follow HIOB->unit->HHCB, publish HIOB into activeHiobs[ucharSCB], then typed firmware.deliverScb(HHCB,HIOB), sync; all four real callback modes execute. | `task12-b2-deliver-Standard64`; `task12-b2-deliver-Swapping32`; `task12-b2-deliver-StandardAdv`; `task12-b2-deliver-SwappingAdv` |
| `SCSIHQueueSpecialHIOB` `0x19da64` | Rawfn-1 normalized8-way table:1AbortTask,2ScsiBusReset(HIOB.context.HHCB,HIOB)+status1+Complete,3typed setupBDR,4/8sync only,6conditional flags100000 publication+status1+Complete,7AbortTaskSet. Raw5/outside default returns without sync. | `task12-b2-b7-queue-special-0`; `task12-b2-b7-queue-special-4`; `task12-b2-b7-queue-special-5`; `task12-b2-b7-queue-special-6`; `task12-b2-b7-queue-special-8`; `task12-b2-b7-queue-special-9`; `task12-b2-b7-queue-special-10`; `task12-b2-b7-queue-special-255`; `task12-b2-b10-full-bus-reset`; `task12-b6-abort-task-hardware-miss`; `task12-b6-abort-set-0`; `task12-b6-setup-bdr-Standard64`; `task12-b6-setup-bdr-Swapping32`; `task12-b6-setup-bdr-StandardAdv`; `task12-b6-setup-bdr-SwappingAdv`; `task12-b6-special6-flags-0x400000`; `task12-b6-special6-flags-0x500000` |
| `SCSIHPowerManagement` `0x19db4c` | Ignore eventWord; actual CheckHostIdle true->1 else2, no invented power transitions or controls. | `task12-b2-SCSIHPowerManagement-zero`; `task12-b2-SCSIHPowerManagement-all-empty`; `task12-b2-SCSIHPowerManagement-active-first`; `task12-b2-SCSIHPowerManagement-active-last`; `task12-b2-SCSIHPowerManagement-foreign` |
| `SCSIHApplyDeviceTable` `0x19db7c` | Genuine input-erased constant-zero stub; unspecified parameter declaration preserved, no extra guessed formal or memory side effect. | `task12-b1-device-stub` |
| `SCSIHCheckHostIdle` `0x19db8c` | Unsigned byte index loop to numberScbs; first activeHiobs entry other than ffffffff returns0; empty/exhausted loop returns1. | `task12-b2-SCSIHCheckHostIdle-zero`; `task12-b2-SCSIHPowerManagement-zero`; `task12-b2-SCSIHCheckHostIdle-all-empty`; `task12-b2-SCSIHPowerManagement-all-empty`; `task12-b2-SCSIHCheckHostIdle-active-first`; `task12-b2-SCSIHPowerManagement-active-first`; `task12-b2-SCSIHCheckHostIdle-active-last`; `task12-b2-SCSIHPowerManagement-active-last`; `task12-b2-SCSIHCheckHostIdle-foreign`; `task12-b2-SCSIHPowerManagement-foreign` |
| `SCSIHCheckDeviceIdle` `0x19dbdc` | Unsigned byte loop skips ffffffff; follows real HIOB.unit.target byte and returns0 only matching target; exhausted/empty returns1. | `task12-b2-SCSIHCheckDeviceIdle-zero`; `task12-b2-SCSIHCheckDeviceIdle-all-empty`; `task12-b2-SCSIHCheckDeviceIdle-active-first`; `task12-b2-SCSIHCheckDeviceIdle-active-last`; `task12-b2-SCSIHCheckDeviceIdle-foreign`; `task12-b3-nego-Force-0-4-143-129-False`; `task12-b3-nego-Force-0-4-142-0-False`; `task12-b3-nego-Force-1-4-143-0-False`; `task12-b3-nego-Force-1-0-143-129-False`; `task12-b3-nego-Force-0-4-143-129-True`; `task12-b3-nego-Suppress-0-4-143-129-False`; `task12-b3-nego-Suppress-0-4-142-0-False`; `task12-b3-nego-Suppress-1-4-143-0-False`; `task12-b3-nego-Suppress-1-0-143-129-False`; `task12-b3-nego-Suppress-0-4-143-129-True` |
| `SCSIHSuppressNegotiation` `0x19deec` | Real device-idle failure returns before MMIO. HardwareMode1 reads135/pauses iff4 clear. getOption ushort==143 triggers xferOptAssign(HHCB,target,ushort0). Mode1 originally-running restores direct8 control. | `task12-b3-nego-Suppress-0-4-143-129-False`; `task12-b3-nego-Suppress-0-4-142-0-False`; `task12-b3-nego-Suppress-1-4-143-0-False`; `task12-b3-nego-Suppress-1-0-143-129-False`; `task12-b3-nego-Suppress-0-4-143-129-True` |
| `SCSIHForceNegotiation` `0x19e01c` | Real device-idle failure returns. Device.rate&129 selects ushort143 else0; mode1 preserves control with conditional pause/restore, typed xferOptAssign HHCB,target,option always on idle. | `task12-b3-nego-Force-0-4-143-129-False`; `task12-b3-nego-Force-0-4-142-0-False`; `task12-b3-nego-Force-1-4-143-0-False`; `task12-b3-nego-Force-1-0-143-129-False`; `task12-b3-nego-Force-0-4-143-129-True` |
| `SCSIHGetHWInformation` `0x19e144` | Read/pause; narrow/wide identity, ADAPTEC AIC11bytes noNUL, IDbyte1 ORhostID, deviceID nibbles&#124;48, bus/device decimal, PCI16&fffffffe hex with historical9->@ threshold<=8. Preserve neutralbits/prefix; mode0/1 thresholds,16 actual option/Fast20 callbacks, typed getProfileParameters(info,HHCB), restore. | `task12-b4-profile-Get-0-False-4`; `task12-b4-profile-Get-1-False-0`; `task12-b4-profile-Get-1-True-4`; `task12-b6-profile-narrow` |
| `SCSIHPutHWInformation` `0x19e55c` | Read/pause; write info.hostID at actual hardware.configurationRegister and HHCB byte; mode0 fifo direct, mode1 flagword and two ordered volatile FIFO byte publications for split/unsplit. Real updateDataFifoThrsh, successive flags word stores, MMIO2 masksC7/flags, typed putProfileParameters(info,HHCB), restore. | `task12-b4-profile-Put-0-False-4`; `task12-b4-profile-Put-1-False-0`; `task12-b4-profile-Put-1-True-4` |
| `SCSIHEnableExpStatus` `0x19e7a8` | Only flags20000 gate: set hardwareFlags20000, real PauseAndWait, firmware.setBreakPoint(HHCB,uchar2), real UnPause; no extra sync. | `task12-b3-exp-True-disabled`; `task12-b3-exp-True-enabled` |
| `SCSIHDisableExpStatus` `0x19e810` | Only flags20000 gate: clear hardwareFlags20000, real PauseAndWait, firmware.clearBreakPoint(HHCB,uchar2), real UnPause. | `task12-b3-exp-False-disabled`; `task12-b3-exp-False-enabled` |
| `SCSIHEnableExtScbRam` `0x19e9bc` | Read control/pause ifrunning; typed getScbRamCtrls and actual hardware masks. Return previous enabled state. Available+disabled clears disablemask; available always publishes low hostAddress.words3 to8-bit MMIO240; restore ifrunning. | `task12-b3-ram-EnableExtScbRam-0-4`; `task12-b3-ram-EnableExtScbRam-4-4`; `task12-b3-ram-EnableExtScbRam-12-0`; `task12-b6-initialize-configure-failure` |
| `SCSIHDisableExtScbRam` `0x19eaf0` | Read control/pause ifrunning; available state determines old enabled return. Only oldenabled writes control&#124;disablemask; unavailable returns0; conditional restore. | `task12-b3-ram-DisableExtScbRam-0-4`; `task12-b3-ram-DisableExtScbRam-4-4`; `task12-b3-ram-DisableExtScbRam-12-0` |
| `SCSIHExtScbRAMAvail` `0x19f494` | Read control/pause ifrunning; return boolean getScbRamCtrls&actual ramAvailableMask, conditional restore; no guessed constants replacing descriptor masks. | `task12-b3-ram-ExtScbRAMAvail-0-4`; `task12-b3-ram-ExtScbRAMAvail-4-4`; `task12-b3-ram-ExtScbRAMAvail-12-0` |
| `SCSIHReadScratchRam` `0x19f554` | Read/pause; signed offset>63 chooses+48 else+32; initial value truncates uchar, subsequent first+i not retruncated. Signed count controls ordered8-bit reads into destination; conditional restore. | `task12-b4-scratch-True-63-2`; `task12-b4-scratch-True-64-2`; `task12-b4-scratch-True-208-2`; `task12-b4-scratch-True--1--1` |
| `SCSIHWriteScratchRam` `0x19f670` | Read/pause; identical signed threshold and initial uchar truncation, signed loop sends each source byte to first+i; conditional restore. | `task12-b4-scratch-False-63-2`; `task12-b4-scratch-False-64-2`; `task12-b4-scratch-False-208-2`; `task12-b4-scratch-False--1--1` |
| `SCSIHReadHADDR` `0x1a0304` | Read control/pause ifrunning; four ordered byte reads136..139 into destination0..3, conditional WriteHCNTRL restore. | `task12-b3-address-0`; `task12-b3-address-4` |

## Typed forwarding and ABI

Production declarations are the accepted Task3/Task11 typed interfaces. Parameters preserve uchar target/lun/count/mode/control/masks, ushort options/EEPROM data, signed int EEPROM/scratch counts/offsets and32-bit event/address/status words. Calls through firmware/hardware descriptors use their actual typed slot signatures and original table targets. `OSMReadUExact8`/`OSMWriteUExact8` receive the accepted by-value I/O-handle aggregate; WW helpers receive the handle pointer. Real primitive instructions execute; no aggregate is flattened into a new fake C convention. Scalar/pointer returns use supported r3; void/input-erased conventions retain exact accepted exceptions.

Initialize checks hardware descriptor0x5c `seqStretchWorkaround` and firmware0x80 `configureScbRam`, then firmware0x54 `setupSequencer`,0x58 `resetSoftware`; configure return is ignored as the reference does. Earlier native batches used incorrect0x84 `setupAssignScbBuffer`; actual reference/native comparison found this and final batch4 corrected it. Original80-vs84 source/native diagnostics and old raw batches are preserved. SetupBDR is firmware0xf8; direct callback arguments are `(HHCB*,HIOB*)`. Status breakpoint callbacks receive `(HHCB*,uchar2)`. Profile callbacks receive `(HWInformation*,HHCB*)`, with const input for put. Option/Fast20/xfer calls retain `(HHCB*,uchar target[,ushort option])`. Actual native relocations, first8 argument registers at real linking calls and exact callee entries are captured in native-results.json/him_calls.

| HIM caller | Actually executed forwarding targets (case bindings in task12.json) |
| --- | --- |
| `SCSIHGetConfiguration` | `OSMReadUExact8`, `SCSIhSetupEnvironment`, `SCSIhPrepareConfig`, `SCSIhNonStandardGetConfig`, `SCSIhGetHardwareConfiguration`, `SCSIhPauseAndWait`, `SCSIhWriteHCNTRL`, `OSMWriteUExact8` |
| `SCSIHGetMemoryTable` | No body call; actual data/stub path |
| `SCSIHApplyMemoryTable` | No body call; actual data/stub path |
| `SCSIHInitialize` | `SCSIhWriteHCNTRL`, `SCSIhSwappingAdvSetupSequencer`, `SCSIhAICBayonetSeqStretchWorkaround`, `SCSIhResetChannelHardware`, `SCSIhSwappingAdvResetSoftware`, `SCSIhInitializeHardware`, `SCSIhStartToRunSequencer`, `SCSIhStandardConfigureScbRam`, `SCSIhStandard64SetupSequencer`, `SCSIhResetScsi`, `SCSIhDelayCount500us` |
| `SCSIHSetupHardware` | No body call; actual data/stub path |
| `SCSIHSizeSEEPROM` | `OSMReadUExact8`, `SCSIhPauseAndWait`, `OSMWriteUExact8`, `SCSIhWriteHCNTRL` |
| `SCSIHReadSEEPROM` | `OSMReadUExact8`, `SCSIhPauseAndWait`, `OSMWriteUExact8`, `SCSIhReadE2Register`, `SCSIhWriteHCNTRL` |
| `SCSIHWriteSEEPROM` | `OSMReadUExact8`, `SCSIhPauseAndWait`, `OSMWriteUExact8`, `SCSIhSendE2Address`, `SCSIhWait2usec`, `SCSIhWriteE2Register`, `SCSIhWriteHCNTRL` |
| `SCSIHSetUnitHandle` | No body call; actual data/stub path |
| `SCSIHFreeUnitHandle` | No body call; actual data/stub path |
| `SCSIHDisableIRQ` | `OSMReadUExact8`, `SCSIhWriteHCNTRL` |
| `SCSIHEnableIRQ` | `OSMReadUExact8`, `SCSIhWriteHCNTRL` |
| `SCSIHPollIRQ` | `OSMReadUExact8`, `SCSIhWWReadINTSTAT` |
| `SCSIHQueueHIOB` | `SCSIhDeliverScb` |
| `SCSIHQueueSpecialHIOB` | `SCSIrCompleteSpecialHIOB`, `SCSIhScsiBusReset`, `SCSIhAbortTask`, `SCSIhAbortTaskSet`, `SCSIhStandard64SetupBDR`, `SCSIhSwapping32SetupBDR`, `SCSIhStandardAdvSetupBDR`, `SCSIhSwappingAdvSetupBDR` |
| `SCSIHPowerManagement` | `SCSIHCheckHostIdle` |
| `SCSIHApplyDeviceTable` | No body call; actual data/stub path |
| `SCSIHCheckHostIdle` | No body call; actual data/stub path |
| `SCSIHCheckDeviceIdle` | No body call; actual data/stub path |
| `SCSIHSuppressNegotiation` | `SCSIHCheckDeviceIdle`, `SCSIhStandardGetOption`, `SCSIhStandardXferOptAssign`, `OSMReadUExact8`, `SCSIhPauseAndWait`, `OSMWriteUExact8` |
| `SCSIHForceNegotiation` | `SCSIHCheckDeviceIdle`, `SCSIhStandardXferOptAssign`, `OSMReadUExact8`, `SCSIhPauseAndWait`, `OSMWriteUExact8` |
| `SCSIHGetHWInformation` | `OSMReadUExact8`, `OSDGetHostAddress`, `OSDReadPciConfiguration`, `SCSIhStandardGetOption`, `SCSIhStandardGetFast20Reg`, `SCSIhAIC78XXGetProfileParameters`, `SCSIhPauseAndWait`, `SCSIhAICBayonetGetProfileParameters`, `SCSIhWriteHCNTRL` |
| `SCSIHPutHWInformation` | `OSMReadUExact8`, `OSMWriteUExact8`, `SCSIhAIC78XXUpdateDataFifoThrsh`, `SCSIhAIC78XXPutProfileParameters`, `SCSIhPauseAndWait`, `SCSIhAICBayonetUpdateDataFifoThrsh`, `SCSIhAICBayonetPutProfileParameters`, `SCSIhWriteHCNTRL` |
| `SCSIHEnableExpStatus` | `SCSIhPauseAndWait`, `SCSIhStandard64SetBreakPoint`, `SCSIhUnPause` |
| `SCSIHDisableExpStatus` | `SCSIhPauseAndWait`, `SCSIhStandard64ClearBreakPoint`, `SCSIhUnPause` |
| `SCSIHEnableExtScbRam` | `OSMReadUExact8`, `SCSIhAICBayonetGetScbRamCtrls`, `OSDGetHostAddress`, `OSMWriteUExact8`, `SCSIhPauseAndWait`, `SCSIhAICBayonetPutScbRamCtrls`, `SCSIhWriteHCNTRL`, `SCSIhAIC78XXGetScbRamCtrls` |
| `SCSIHDisableExtScbRam` | `OSMReadUExact8`, `SCSIhAICBayonetGetScbRamCtrls`, `SCSIhAICBayonetPutScbRamCtrls`, `SCSIhPauseAndWait`, `SCSIhWriteHCNTRL` |
| `SCSIHExtScbRAMAvail` | `OSMReadUExact8`, `SCSIhAICBayonetGetScbRamCtrls`, `SCSIhPauseAndWait`, `SCSIhWriteHCNTRL` |
| `SCSIHReadScratchRam` | `OSMReadUExact8`, `SCSIhPauseAndWait`, `SCSIhWriteHCNTRL` |
| `SCSIHWriteScratchRam` | `OSMReadUExact8`, `OSMWriteUExact8`, `SCSIhPauseAndWait`, `SCSIhWriteHCNTRL` |
| `SCSIHReadHADDR` | `OSMReadUExact8`, `SCSIhPauseAndWait`, `SCSIhWriteHCNTRL` |

HHCB1380, UnitControl16, HardwareInformation428 and TransportSpecific20 are accessed-prefix views, not proof of trailing original sizeof. This source allocates none of them. Enclosing Adapter2600, Target40 and OSMIOB200 allocations/count arithmetic remain exact accepted contracts; no sizeof(prefix_view) substitutes for enclosing allocation. Unit device stride is10 here, distinct from accepted Resource SetUnitHandle queue stride68 and Target allocation40. Neutral fields, union bits and caller-reserved bytes remain preserved. Native publication checks require byte/halfword memory-table fields, pointer/byte unit writes, three published pointers before ApplyMemory failure and optional count byte, and two actual FIFO byte publications in hardwareMode1 plus word-width profile flags. Incomingr28 has no new C formal/default.

## Assigned switch closure

`switch_230ed4`,32bytes, reference owner `SCSIHQueueSpecialHIOB@0x19da64`, has normalized index `raw uchar function-1`, unsigned bound7, signed32-bit table-relative entries. Existing reference table/guard/dispatch bytes,8targets and default address remain exact. Production C switch compiles to a genuine eight-entry relative table. Native graph follows actual branch paths within owner bounds and checks real external-call relocations, indirect callback path, sync and return; no orphan address array was added.

| Raw function / normalized index | Behavior |
| --- | --- |
|1 /0 |AbortTask then sync |
|2 /1 |ScsiBusReset, status1, CompleteSpecialHIOB, sync |
|3 /2 |Actual typed firmware setupBDR, sync; four firmware modes exercised |
|4 /3 and8 /7 |Shared sync-only epilog |
|5 /4 |Aliases default no-sync epilog |
|6 /5 |Conditional flags100000 update, status1, CompleteSpecialHIOB, sync; flag paths0/400000/500000 actual |
|7 /6 |AbortTaskSet then sync |
|0,9,10,255 /outside |Default return without sync |

Actual full bus reset uses authentic Resource caller `task12-b2-b10-full-bus-reset`,2,651,262 reference instructions and all6000 delay iterations, rather than a mocked internal reset. Abort-task/set branches use authentic supported Resource callers with explicit real HIM/hardware entry observations. All switch outcomes have actual fixtures in addition to native graph closure.

## Incoming-r28 caller/native witness

The actual reference `SCSIRInitialize@0x1a2558..0x1a2594` and `SCSIHInitialize@0x1921b8..0x1922a4` forward incomingr28 unchanged; native HIMInitialize allocates onlyr31 apart from ABI-preserving real calls. The authentic publicAPI `SCSIInitialize@0x1a4644..0x1a493c` also has no reference r28 write; its actual nativeAPI call-site proof is a current Task13 obligation, not assumed from generic callee-saved ABI.

The approved narrow supplementary test enters exact real SCSIRInitialize before any instruction and seeds only architectural initialr28 to two frozen uint32 values. It records the value at real Resource/HIM/Hardware entries, byte MMIO255 and preservation through return. All other r14..r31 sentinels and SP are checked. No mid-execution mutation/body hook/skip/counter override occurs. Wrong entry, image identity and unapproved context fail before execution; public1931e4 machine-input guard remains unchanged.

| Case | Seed / resulting MMIO255 | Reference/native instructions |
| --- | --- | --- |
| `task12-r28-0x12345635` |`0x12345635` /`0x35` |141302/141314 |
| `task12-r28-0x89abcda6` |`0x89abcda6` /`0xa6` |141302/141314 |

Native variant executes the actual native Resource/HIM/accepted Config bodies from genuine checked Mach-O relocations in a private arena. Original reference file/database instructions are unchanged; native symbol arenas and all relocated words are authenticated by replaying actual relocation tables without a CPU rerun. Other callees remain pinned real reference bodies. Normal cache/chip override controls continue existing accepted Task8 coverage; public GetConfiguration control0/c4/c5 and full initialization/default/reset branches are exercised here. Final Task15/16 require actual matching context witnesses through the complete native chain in all4 independently mapped exact linked images.

## Exact MMIO ownership and consumed snapshot

Accepted shared contracts and Task11 snapshot are unchanged. `tests/task12-contracts.json` contains exact canonical accepted Task11 baseline (`DEC24F3F4C26F6F6EA5370DF9DAE26DC74BE04B255D773FB3A04F82E7428149A`) plus isolated task12-hardware group. Its146 rows are the exact directional union of frozen cases/context expectations;32 register offsets are new relative to Task11hardware rows. Rows do not expand after execution. Stable offset:size:direction keys resolve through task12.json/mmio_operations to538 actual instruction/callsite/owner/case records. No unused speculative row remains.

The observer verifies actual mapped instruction bytes, genuine linking b/blrl/bctrl, actual target/LR, and owner bounds before attributing a primitive access. A tailcall/veneer/unknown chain is rejected, not guessed from LR-4. It records three identities separately: actual operation owner/referenceaddress (SCSIH only when its own instruction calls the primitive; otherwise actual lower-case SCSIh), HIM caller, and accepted Task5 OSM primitive/access instruction. Every observed MMIO access is accounted for by its frozen trace, and every row resolves exact actual evidence plus accepted owner proof. Owner gate re-authenticates code bytes/native relocations against raw results. Metadata-only mutual consistency is insufficient.

Example: EnableIRQ owns the read at reference0x19d944, while the resulting HCNTRL write is owned by `SCSIhWriteHCNTRL@0x19ff74`; HIMcaller EnableIRQ and Task5 primitive are separate. No repetition of the deferred Task11 generic-owned-body attribution problem. Final Task16 must consolidate validated group deltas and fresh cases, retaining/flattening these authenticated exact references.

## Actual fixture observables

The three named families authenticate fresh actual outputs before reuse: memory54,queue56,profile25. They compare the selected actual IDs and exact frozen observations, including return/memory/pointer/callback/MMIO/barrier data. Meaningful missing, stale, corrupted observation, unknown-call, sentinel and snapshot/owner/callsite negatives guard reuse; named tests do not launch duplicate CPU corpora. The full byte/pointer/trace values remain in committed task12-cases.json and pinned raw results. The following table indexes every actual case and concrete observation shape/instruction count.

| Case ID / actual entry | Return; observed memory targets; trace events | Reference/native instructions |
| --- | --- | --- |
| `task12-b1-memory-0-4` /`SCSIHGetMemoryTable` |void; table+0; 0 |54/51 |
| `task12-b1-memory-0-255` /`SCSIHGetMemoryTable` |void; table+0; 0 |54/51 |
| `task12-b1-memory-3-4` /`SCSIHGetMemoryTable` |void; table+0; 0 |54/51 |
| `task12-b1-memory-3-255` /`SCSIHGetMemoryTable` |void; table+0; 0 |54/51 |
| `task12-b1-memory-4-4` /`SCSIHGetMemoryTable` |void; table+0; 0 |54/51 |
| `task12-b1-memory-4-255` /`SCSIHGetMemoryTable` |void; table+0; 0 |54/51 |
| `task12-b1-memory-5-4` /`SCSIHGetMemoryTable` |void; table+0; 0 |54/51 |
| `task12-b1-memory-5-255` /`SCSIHGetMemoryTable` |void; table+0; 0 |54/51 |
| `task12-b1-unit-0` /`SCSIHSetUnitHandle` |void; unit+0; 0 |13/13 |
| `task12-b1-unit-15` /`SCSIHSetUnitHandle` |void; unit+0; 0 |13/13 |
| `task12-b1-unit-7` /`SCSIHSetUnitHandle` |void; unit+0; 0 |13/13 |
| `task12-b1-setup-0` /`SCSIHSetupHardware` |void; hhcb+244; 0 |9/9 |
| `task12-b1-setup-1` /`SCSIHSetupHardware` |void; hhcb+244; 0 |9/9 |
| `task12-b1-device-stub` /`SCSIHApplyDeviceTable` |0; none; 0 |4/4 |
| `task12-b1-apply-0-2` /`SCSIHApplyMemoryTable` |1; hhcb+0; 0 |29/29 |
| `task12-b1-apply-0-4` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |30/29 |
| `task12-b1-apply-0-8` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |26/26 |
| `task12-b1-apply-0-255` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |26/26 |
| `task12-b1-apply-3-2` /`SCSIHApplyMemoryTable` |1; hhcb+0; 0 |29/29 |
| `task12-b1-apply-3-4` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |30/29 |
| `task12-b1-apply-3-8` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |26/26 |
| `task12-b1-apply-3-255` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |26/26 |
| `task12-b1-apply-4-2` /`SCSIHApplyMemoryTable` |1; hhcb+0; 0 |29/29 |
| `task12-b1-apply-4-4` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |30/29 |
| `task12-b1-apply-4-8` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |26/26 |
| `task12-b1-apply-4-255` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |26/26 |
| `task12-b1-apply-5-2` /`SCSIHApplyMemoryTable` |1; hhcb+0; 0 |29/29 |
| `task12-b1-apply-5-4` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |30/29 |
| `task12-b1-apply-5-8` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |26/26 |
| `task12-b1-apply-5-255` /`SCSIHApplyMemoryTable` |0; hhcb+0; 0 |26/26 |
| `task12-b1-getconfig-3` /`SCSIHGetConfiguration` |0; adapter+24; 20 |1151/1230 |
| `task12-b1-getconfig-5` /`SCSIHGetConfiguration` |0; adapter+24; 20 |1151/1230 |
| `task12-b1-initialize-failure` /`SCSIHInitialize` |4294967295; none; 4530 |68038/68038 |
| `task12-b2-SCSIHCheckHostIdle-zero` /`SCSIHCheckHostIdle` |1; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |8/8 |
| `task12-b2-SCSIHCheckDeviceIdle-zero` /`SCSIHCheckDeviceIdle` |1; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |9/9 |
| `task12-b2-SCSIHPowerManagement-zero` /`SCSIHPowerManagement` |1; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |20/21 |
| `task12-b2-SCSIHCheckHostIdle-all-empty` /`SCSIHCheckHostIdle` |1; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |34/34 |
| `task12-b2-SCSIHCheckDeviceIdle-all-empty` /`SCSIHCheckDeviceIdle` |1; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |35/35 |
| `task12-b2-SCSIHPowerManagement-all-empty` /`SCSIHPowerManagement` |1; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |46/47 |
| `task12-b2-SCSIHCheckHostIdle-active-first` /`SCSIHCheckHostIdle` |0; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |15/15 |
| `task12-b2-SCSIHCheckDeviceIdle-active-first` /`SCSIHCheckDeviceIdle` |0; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |20/20 |
| `task12-b2-SCSIHPowerManagement-active-first` /`SCSIHPowerManagement` |2; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |26/28 |
| `task12-b2-SCSIHCheckHostIdle-active-last` /`SCSIHCheckHostIdle` |0; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |31/31 |
| `task12-b2-SCSIHCheckDeviceIdle-active-last` /`SCSIHCheckDeviceIdle` |0; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |36/36 |
| `task12-b2-SCSIHPowerManagement-active-last` /`SCSIHPowerManagement` |2; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |42/44 |
| `task12-b2-SCSIHCheckHostIdle-foreign` /`SCSIHCheckHostIdle` |0; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |15/15 |
| `task12-b2-SCSIHCheckDeviceIdle-foreign` /`SCSIHCheckDeviceIdle` |1; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |39/39 |
| `task12-b2-SCSIHPowerManagement-foreign` /`SCSIHPowerManagement` |2; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |26/28 |
| `task12-b2-SCSIHDisableIRQ` /`SCSIHDisableIRQ` |void; hhcb+0, hiob+0; 4 |79/83 |
| `task12-b2-SCSIHEnableIRQ` /`SCSIHEnableIRQ` |void; hhcb+0, hiob+0; 4 |79/83 |
| `task12-b2-poll-False-False-171` /`SCSIHPollIRQ` |11; hhcb+0, hiob+0; 1 |36/37 |
| `task12-b2-poll-True-True-165` /`SCSIHPollIRQ` |5; hhcb+0, hiob+0; 2 |82/82 |
| `task12-b2-poll-True-False-162` /`SCSIHPollIRQ` |2; hhcb+0, hiob+0; 7 |164/164 |
| `task12-b2-poll-True-False-173` /`SCSIHPollIRQ` |13; hhcb+0, hiob+0; 7 |165/165 |
| `task12-b2-deliver-Standard64` /`SCSIHQueueHIOB` |void; scb+0, sg+0, reserve+0, adapter+240, active+0; 5 |197/197 |
| `task12-b2-deliver-Swapping32` /`SCSIHQueueHIOB` |void; scb+0, sg+0, reserve+0, adapter+240, active+0; 5 |237/237 |
| `task12-b2-deliver-StandardAdv` /`SCSIHQueueHIOB` |void; scb+0, sg+0, reserve+0, adapter+240, active+0; 5 |213/213 |
| `task12-b2-deliver-SwappingAdv` /`SCSIHQueueHIOB` |void; scb+0, sg+0, reserve+0, adapter+240, active+0; 5 |212/212 |
| `task12-b2-b7-queue-special-0` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 0 |14/14 |
| `task12-b2-b7-queue-special-4` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 1 |24/24 |
| `task12-b2-b7-queue-special-5` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 0 |23/23 |
| `task12-b2-b7-queue-special-6` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 1 |186/190 |
| `task12-b2-b7-queue-special-8` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 1 |24/24 |
| `task12-b2-b7-queue-special-9` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 0 |14/14 |
| `task12-b2-b7-queue-special-10` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 0 |14/14 |
| `task12-b2-b7-queue-special-255` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 0 |14/14 |
| `task12-b2-b10-full-bus-reset` /`SCSIRQueueSpecialHIOB` |void; active+0, scb+0, hiob+0, adapter+0, hostwait+0, devwait+0, hostwaitiob+44, devwaitiob+44, iob+44; 126145 |2651262/2651341 |
| `task12-b3-exp-False-disabled` /`SCSIHDisableExpStatus` |void; hhcb+0, hiob+0; 0 |13/13 |
| `task12-b3-exp-True-disabled` /`SCSIHEnableExpStatus` |void; hhcb+0, hiob+0; 0 |13/13 |
| `task12-b3-exp-False-enabled` /`SCSIHDisableExpStatus` |void; hhcb+0, hiob+0; 9 |255/255 |
| `task12-b3-exp-True-enabled` /`SCSIHEnableExpStatus` |void; hhcb+0, hiob+0; 14 |350/350 |
| `task12-b3-nego-Force-0-4-143-129-False` /`SCSIHForceNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 2 |127/128 |
| `task12-b3-nego-Force-0-4-142-0-False` /`SCSIHForceNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 2 |127/128 |
| `task12-b3-nego-Force-1-4-143-0-False` /`SCSIHForceNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 3 |156/157 |
| `task12-b3-nego-Force-1-0-143-129-False` /`SCSIHForceNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 9 |300/301 |
| `task12-b3-nego-Force-0-4-143-129-True` /`SCSIHForceNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |42/43 |
| `task12-b3-nego-Suppress-0-4-143-129-False` /`SCSIHSuppressNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 3 |165/166 |
| `task12-b3-nego-Suppress-0-4-142-0-False` /`SCSIHSuppressNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 1 |109/110 |
| `task12-b3-nego-Suppress-1-4-143-0-False` /`SCSIHSuppressNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 4 |194/195 |
| `task12-b3-nego-Suppress-1-0-143-129-False` /`SCSIHSuppressNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 10 |338/339 |
| `task12-b3-nego-Suppress-0-4-143-129-True` /`SCSIHSuppressNegotiation` |void; hhcb+0, hiob+0, descriptor+0, active+0, done+0; 0 |40/41 |
| `task12-b3-ram-EnableExtScbRam-0-4` /`SCSIHEnableExtScbRam` |0; adapter+24; 2 |92/92 |
| `task12-b3-ram-EnableExtScbRam-4-4` /`SCSIHEnableExtScbRam` |1; adapter+24; 4 |131/134 |
| `task12-b3-ram-EnableExtScbRam-12-0` /`SCSIHEnableExtScbRam` |0; adapter+24; 13 |368/371 |
| `task12-b3-ram-DisableExtScbRam-0-4` /`SCSIHDisableExtScbRam` |0; adapter+24; 2 |90/90 |
| `task12-b3-ram-DisableExtScbRam-4-4` /`SCSIHDisableExtScbRam` |1; adapter+24; 4 |136/136 |
| `task12-b3-ram-DisableExtScbRam-12-0` /`SCSIHDisableExtScbRam` |0; adapter+24; 9 |291/291 |
| `task12-b3-ram-ExtScbRAMAvail-0-4` /`SCSIHExtScbRAMAvail` |0; adapter+24; 2 |89/94 |
| `task12-b3-ram-ExtScbRAMAvail-4-4` /`SCSIHExtScbRAMAvail` |1; adapter+24; 2 |89/94 |
| `task12-b3-ram-ExtScbRAMAvail-12-0` /`SCSIHExtScbRAMAvail` |1; adapter+24; 9 |285/290 |
| `task12-b3-address-0` /`SCSIHReadHADDR` |void; address+0; 11 |312/312 |
| `task12-b3-address-4` /`SCSIHReadHADDR` |void; address+0; 5 |152/152 |
| `task12-b4-scratch-True-63-2` /`SCSIHReadScratchRam` |void; data+0; 3 |119/119 |
| `task12-b4-scratch-True-64-2` /`SCSIHReadScratchRam` |void; data+0; 9 |278/280 |
| `task12-b4-scratch-True-208-2` /`SCSIHReadScratchRam` |void; data+0; 3 |118/120 |
| `task12-b4-scratch-True--1--1` /`SCSIHReadScratchRam` |void; data+0; 1 |63/63 |
| `task12-b4-scratch-False-63-2` /`SCSIHWriteScratchRam` |void; data+0; 5 |125/125 |
| `task12-b4-scratch-False-64-2` /`SCSIHWriteScratchRam` |void; data+0; 11 |284/286 |
| `task12-b4-scratch-False-208-2` /`SCSIHWriteScratchRam` |void; data+0; 5 |124/126 |
| `task12-b4-scratch-False--1--1` /`SCSIHWriteScratchRam` |void; data+0; 1 |63/63 |
| `task12-b4-size-0-0-False` /`SCSIHSizeSEEPROM` |0; hhcb+0, hiob+0; 10 |266/266 |
| `task12-b4-size-0-0-True` /`SCSIHSizeSEEPROM` |64; hhcb+0, hiob+0; 4 |111/111 |
| `task12-b4-size-0-1-True` /`SCSIHSizeSEEPROM` |128; hhcb+0, hiob+0; 4 |113/113 |
| `task12-b4-size-0-2-True` /`SCSIHSizeSEEPROM` |0; hhcb+0, hiob+0; 4 |112/113 |
| `task12-b4-size-1-0-True` /`SCSIHSizeSEEPROM` |64; hhcb+0, hiob+0; 1 |58/58 |
| `task12-b4-size-1-1-True` /`SCSIHSizeSEEPROM` |128; hhcb+0, hiob+0; 7 |219/220 |
| `task12-b4-eeprom-early-True` /`SCSIHReadSEEPROM` |1; hhcb+0, hiob+0, data+0; 8 |230/230 |
| `task12-b4-eeprom-early-False` /`SCSIHWriteSEEPROM` |1; hhcb+0, hiob+0, data+0; 8 |240/238 |
| `task12-b4-eeprom-True-0-0-2` /`SCSIHReadSEEPROM` |0; hhcb+0, hiob+0, data+0; 1208 |23826/23826 |
| `task12-b4-eeprom-True-1-1-1` /`SCSIHReadSEEPROM` |0; hhcb+0, hiob+0, data+0; 656 |12995/12995 |
| `task12-b4-eeprom-True-1-0--1` /`SCSIHReadSEEPROM` |0; hhcb+0, hiob+0, data+0; 7 |171/171 |
| `task12-b4-eeprom-False-0-0-2` /`SCSIHWriteSEEPROM` |0; hhcb+0, hiob+0, data+0; 2196 |43240/43236 |
| `task12-b4-eeprom-False-1-1-1` /`SCSIHWriteSEEPROM` |0; hhcb+0, hiob+0, data+0; 1502 |29628/29626 |
| `task12-b4-eeprom-False-1-0--1` /`SCSIHWriteSEEPROM` |0; hhcb+0, hiob+0, data+0; 447 |8851/8847 |
| `task12-b4-profile-Get-0-False-4` /`SCSIHGetHWInformation` |void; adapter+24, information+0; 85 |6011/6107 |
| `task12-b4-profile-Get-1-False-0` /`SCSIHGetHWInformation` |void; adapter+24, information+0; 76 |4947/5044 |
| `task12-b4-profile-Get-1-True-4` /`SCSIHGetHWInformation` |void; adapter+24, information+0; 69 |4755/4852 |
| `task12-b4-profile-Put-0-False-4` /`SCSIHPutHWInformation` |void; adapter+24, information+0; 8 |409/436 |
| `task12-b4-profile-Put-1-False-0` /`SCSIHPutHWInformation` |void; adapter+24, information+0; 15 |622/657 |
| `task12-b4-profile-Put-1-True-4` /`SCSIHPutHWInformation` |void; adapter+24, information+0; 8 |426/461 |
| `task12-b5-initialize-real-success` /`SCSIRInitialize` |0; adapter+24, qout+0, active+0, descriptors+0; 6977 |141300/141315 |
| `task12-b5-getconfig-control-0` /`SCSIHGetConfiguration` |0; adapter+24; 28 |1384/1463 |
| `task12-b5-getconfig-control-196` /`SCSIHGetConfiguration` |0; adapter+24; 22 |1178/1258 |
| `task12-b5-getconfig-control-197` /`SCSIHGetConfiguration` |0; adapter+24; 18 |1242/1318 |
| `task12-b6-abort-task-hardware-miss` /`SCSIrAbortTask` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, related+0, iob+44, related-iob+44; 4 |359/356 |
| `task12-b6-abort-set-0` /`SCSIrAbortTaskSet` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44; 4 |445/445 |
| `task12-b6-setup-bdr-Standard64` /`SCSIHQueueSpecialHIOB` |void; hhcb+212, hiob+32, active+28; 107 |1685/1685 |
| `task12-b6-setup-bdr-Swapping32` /`SCSIHQueueSpecialHIOB` |void; hhcb+212, hiob+32, active+28, scb+0; 12 |262/262 |
| `task12-b6-setup-bdr-StandardAdv` /`SCSIHQueueSpecialHIOB` |void; hhcb+212, hiob+32, active+28; 103 |1626/1626 |
| `task12-b6-setup-bdr-SwappingAdv` /`SCSIHQueueSpecialHIOB` |void; hhcb+212, hiob+32, active+28, scb+0; 8 |198/198 |
| `task12-b6-special6-flags-0x400000` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 1 |186/190 |
| `task12-b6-special6-flags-0x500000` /`SCSIHQueueSpecialHIOB` |void; hiob+0, descriptor+0, active+0, done+0, adapter+0, iob+44, controller+1396; 1 |179/180 |
| `task12-b6-initialize-configure-failure` /`SCSIHInitialize` |4294967295; none; 4023 |60520/60520 |
| `task12-b6-profile-narrow` /`SCSIHGetHWInformation` |void; adapter+24, information+0; 85 |6001/6098 |
| `task12-b7-initialize-reset-settle` /`SCSIRInitialize` |0; adapter+24, qout+0, active+0, descriptors+0; 145043 |3220773/3220788 |

Concrete branch checks include table modes0/3/4/5 and scb counts0/255; preserved descriptor4size; ApplyMemory available2/4/8/255 with actual mode5stride64 and byte truncation; pointer publication before failure; unit targets/luns; IRQWW/normal and polling low4bits; active entries/sentinel and target-match/miss; four deliverScb modes; special default/alias/caller branches; suppress idle/busy and option143/non143; force option0/143 and pause/restore; old-state external RAM values using actual descriptor availability4/disable8 masks; address/scratch threshold63/64/208 and negative counts; EEPROM presence failures and finite nonterminal wait transitions, both addressing widths and multiword loops; profile mode0/mode1 split/unsplit and narrow/wide paths, initial identity ORbits and historical PCI9->@; configuration WWrestore/default controls; setup loader failures before reset/start; full success with optional reset+settle.

FreeUnit public alias convention remains unsupported by the existing shared parser. Current supplementary direct HIM no-op pairs for Unit16 and HHCB1380 each execute4 reference/native instructions, preserve bytes/SP/nonvolatiles and perform no writes. Accepted Task11 separately retains two actual native Resource-wrapper+reference-HIM mixed cases; they were not rerun or relabeled. Task16 must add the narrow alias parser mapping and direct pairs in all4 linked images.

## Commands and validation evidence

PowerShell from the isolated worktree, `PYTHONPATH=tools/binrecon`, Python `OUT/venv/Scripts/python.exe`. Full actual CPU commands:

```text
python P/tests/ppc_cases.py reference --reference OUT/reference --cases P/tests/task12-cases.json --contracts P/tests/task12-contracts.json --output OUT/objects/task12/reference-results.json
python P/tests/task12_execute.py --reference OUT/reference --objects OUT/objects/task12 --him OUT/objects/task12/1-AdaptecU2CHIMHIM.c.o --config OUT/objects/task8/1-AdaptecU2CHIMConfig.c.o --resource OUT/objects/task11/1-AdaptecU2CHIMResource.c.o
```

Here P=`src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI`, OUT=`tools/binrecon/out/adaptecu2scsi-ppc`. Actual complete CLI outputs are retained as `OUT/task12/final-public.log` and `final-native.log`; the public output is `reference: 135 frozen cases passed`, supplementary output names every135case and finishes135compiled/2context/2FreeUnit/8switch PASS with held78b79 producer. Individual raw reference freeze artifacts, native preflight and older WIP results are preserved separately, not promoted as final current evidence.

Initial RED: `pytest -p no:faulthandler P/tests/test_reconstruction.py -k him -q` ->3expected missing-HIM-owner failures/424deselected, `initial-red-scoped.log`. Initial unused reference fixture unnecessarily extracted reference; removed that dependency; no earlier accepted CPU corpus/baseline was rerun.

Owner gate: `python P/tests/verify.py group --reference OUT/reference --repo-root . --objects OUT/objects/task12 --group AdaptecU2CHIMHIM.c` ->PASS (actual reference identity/partition/evidence). Nativepublication checks also pass memory-table byte/halfword footprint, unit pointer/bytes, ApplyMemory failure ordering and profile double FIFO writes.

Focused named/negative/layout/inventory/switch/canonical command results are appended below after completion. These are structural/authenticated-evidence checks except the explicit pre-execution context rejection guards. No completed previous corpus/full baseline rerun.

## Preserved failures, corrections and limits

- Early batches incorrectly selected firmware0x84 instead of0x80 configureScbRam; final batch4 corrected source and compiled bytes. Old artifacts remain diagnostics.
- Preliminary direct reset fixture lacked real Resource preconditions and failed strict unknown-call checks; replaced by authentic Resource caller, with actual full delay path.
- Preliminary mode5 table fixture used stride32; actual accepted descriptor gives64. Corrected only those inputs and refroze them before final input commit. Preliminary native92 output also contains obsolete RAM1/3 inputs; it is explicitly WIP and not final evidence.
- Early initialization expectations used the wrong hardware-specific external-termination sequence, PCI callback adapteroffset1664 instead of1672, and expected PCI8 instead of actual masked0. Corrected from real accepted typed table/reference instructions and actual outcomes; no code patch/hook/default was introduced to fit them.
- Private arena prototype rejected unhandled paired/sectdiff/BSS cases before execution; emitter now uses validated real paired relocations, unchanged onebase sectdiffs, correct zero-fill sections and strict unresolved/unknown relocation rejection. Failed loader attempts retained.
- One concurrent exploratory generator overwrote current Task12 fixture edits; repaired from preserved actual inputs/results before freeze. Generators are ignored offline tooling and absent from runtime closure. All final exact new cases were validated before input freeze.
- One focused permission negative initially selected an already-read+write row, so it made no change and correctly failed to raise. Test now selects a single-direction row and verifies a real expansion is rejected.
- Historical Task11 scoped-delta test previously compared Task11base773b to HEAD, so adding Task12 would make a correct later owner fail. Controller approved test-only producer-relative bound608e9f5vs773b, retaining current canonical task11.json equality. New explicit extra/missing owned-row/switch negatives preserve strict historical scope; current Task12 delta separately checks608e9f5->HEAD. No accepted runtime input changed.
- Task11 deferred qualifierwarning, generic16rowattribution and historical-raw-vs-current helper-line-ending issue remain Task16/final triage; Task12 does not silently claim those repaired. Its own runtime identity checks compare current canonical blobs with historical stored producer working hashes, with a focused LF/CRLF helper regression; no general prior-checkout portability claim.
- No new physical validation, hardware support or i386 port. No full linked-kernel/native closure, Task15fourbuilds, Task16freshallcorpora/476bodies/48data final paired acceptance or all4 r28 witnesses is claimed. Those remain mandatory, together with Task13 actual native publicAPI forwarding.

The original reference IDA database was left open/unchanged; the Task12-owned temporary native batch3 database lease was closed. The owned build guest remains active for controller/following tasks. Final self-review covers only Task12 code/evidence and directly affected historical test bounds; parent performs independent review.

## Final scoped audit results

- Owner CLI PASS; layout CLI PASS; inventory CLI PASS. Logs: OUT/task12/layout-gate.log and inventory-gate.log; initial owner CLI output was `group: reference identity, partition and evidence verified`.
- Focused mixed-suite exact command below completed with **42 passed,1 failed,420deselected in341.41s**. All42 intended Task12/affected structural checks passed, including all3 named HIM tests, four explicit historical Task11 extra/missing row/switch negatives, historical Task11 positive bound, snapshot/actual observation/launcher imports/all7 native inputs/callsite/context/publication guards, dispatch header and switch accounting. The one failure was an accidentally selected inherited Task5 OSD parameter because `him` also matches `AdaptecU2CHIMOSD.c`. This is not a clean-suite claim.

```text
OUT/venv/Scripts/python.exe -m pytest -p no:faulthandler src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/test_task12.py src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/test_reconstruction.py -k '(him or task11_canonical_git_closure or firmware_switch_metadata_all_case_values or dispatch_headers_are_not_callbacks or layout_rejects_changed_header) and not him_canonical_git_and_exact_owner_delta' -q
```

Complete output: OUT/task12/focused-gates.log. The inherited failure is `test_task5_required_owners_have_actual_bodies[AdaptecU2CHIMOSD.c-14]`: verify.py190 validates existing stored Task5 results and ppc_cases.py593 rejects `stale result: contracts_sha256` against current shared contracts. It did not reexecute an old CPU corpus. Accepted Task5 source/proof/runtime inputs were not changed. Controller ruling carries this old current-contract provenance issue to mandatory Task16 fresh consolidated all-corpus repair/check and final review; no42-check rerun solely for selector hygiene.

The earlier negative-only attempt was30passed/1negative-fixture mistake/1deselected; the corrected exact permission/publication subset was6passed/26deselected in5.14s. All corrected intended checks subsequently passed in the42-check run. No stale/failed preliminary result is promoted as a clean final pass.

Task12 canonical Git/current31-owner delta check follows the evidence commit; its exact command/output and final commit are recorded in the concluding audit entry. Independent controller review remains required.

## Canonical Git closure and self-review

Evidence/audit commit: `2095ef3bd`. Canonical current-owner test:

```text
$env:PYTHONPATH='tools/binrecon'
tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe -m pytest -p no:faulthandler src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/test_task12.py::test_him_canonical_git_and_exact_owner_delta -q
.                                                                        [100%]
1 passed in 1.73s
```

Complete output: OUT/task12/canonical-git.log. It reads canonical Git blobs, verifies all31 and only31 ledger rows, exact artifact digest,31 source-map additions and unchanged other mappings/duplicates/disputes, and unchanged data outside the one assigned switch. The final report-only commit preserves those exact code/proof/map/ledger/runtime artifacts. No additional CPU execution is needed for a report update.

Self-review: checked all31 reference/native bodies and exact typed forwarding/slot correction; final actual current135-case native/reference observations and genuine relocations;31 actual entry/leaf coverage bindings; normalized switch/default aliases; strict real-callee bounds, MMIO operation-owner bytes/call-sites and every frozen permission; all7 compiled LF inputs/canonical Git equality and true native/source/runtime producer separation; proof-ledger source-map delta; canonical line endings; no accepted consumed contract/header/proof runtime changes; no unrelated source cleanup. `git diff --check` and staged checks are clean. Controller independent review is still the next gate.

Fully expanded actual final CPU launch commands (PowerShell from the isolated worktree):

```text
$env:PYTHONPATH='tools/binrecon'
tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/ppc_cases.py reference --reference tools/binrecon/out/adaptecu2scsi-ppc/reference --cases src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/task12-cases.json --contracts src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/task12-contracts.json --output tools/binrecon/out/adaptecu2scsi-ppc/objects/task12/reference-results.json
tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/tests/task12_execute.py --reference tools/binrecon/out/adaptecu2scsi-ppc/reference --objects tools/binrecon/out/adaptecu2scsi-ppc/objects/task12 --him tools/binrecon/out/adaptecu2scsi-ppc/objects/task12/1-AdaptecU2CHIMHIM.c.o --config tools/binrecon/out/adaptecu2scsi-ppc/objects/task8/1-AdaptecU2CHIMConfig.c.o --resource tools/binrecon/out/adaptecu2scsi-ppc/objects/task11/1-AdaptecU2CHIMResource.c.o
```

Actual outputs: `reference: 135 frozen cases passed`; supplementary lists135 exact case IDs and finishes `PASS135 compiled cases,2 real caller context pairs,2 FreeUnit pairs,8 switch paths; HEAD 78b79a22bdbdde4f6b88792bc650035590bb17c3`. The proof/source commit is separate from original native608e9f5+WIP; raw outputs retain their original identities.
