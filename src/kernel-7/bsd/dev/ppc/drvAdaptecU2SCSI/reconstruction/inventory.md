# AdaptecU2SCSI reference inventory

Reference: `mach_kernel`, 2,983,828 bytes, SHA-256 `D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD`.
PPC, big-endian, 32-bit Mach-O; `Kernel Release 5.6`, `kernel-190.1.obj~4/RELEASE_PPC`.

IDA 9.4 batch analysis and independent IDA MCP inspection establish 476 contiguous bodies:
84 controller/OSM/helper bodies (16,456 bytes), then 392 CHIM bodies (119,688 bytes).
Both range ends are exclusive: `[0x18770c,0x18b754)` and `[0x18b754,0x1a8adc)`.
Organizational owners below do not claim original Apple translation-unit boundaries.

## Function ownership

<!-- functions:start -->
| Address | Exclusive end | Reference name | Owner |
| --- | --- | --- | --- |
| 0x18770c | 0x18779c | `_AdptMallocContiguous` | `AdaptecU2OSMServices.m` |
| 0x18779c | 0x1877c8 | `_AdptFreeContiguous` | `AdaptecU2OSMServices.m` |
| 0x1877c8 | 0x1877f8 | `+[AdaptecU2SCSI initialize]` | `AdaptecU2SCSI.m` |
| 0x1877f8 | 0x1878a8 | `+[AdaptecU2SCSI probe:]` | `AdaptecU2SCSI.m` |
| 0x1878a8 | 0x1879cc | `-[AdaptecU2SCSI registerHandlerForIRQ:]` | `AdaptecU2SCSI.m` |
| 0x1879cc | 0x187d38 | `-[AdaptecU2SCSI initFromDeviceDescription:]` | `AdaptecU2SCSI.m` |
| 0x187d38 | 0x187d8c | `-[AdaptecU2SCSI getWorkingMemoryForCHIM]` | `AdaptecU2SCSI.m` |
| 0x187d8c | 0x187e54 | `-[AdaptecU2SCSI findAdapter]` | `AdaptecU2SCSI.m` |
| 0x187e54 | 0x188134 | `-[AdaptecU2SCSI initAdapter]` | `AdaptecU2SCSI.m` |
| 0x188134 | 0x188294 | `-[AdaptecU2SCSI allocateAdapterMemory]` | `AdaptecU2SCSI.m` |
| 0x188294 | 0x188344 | `-[AdaptecU2SCSI createOSMIOBPool]` | `AdaptecU2SCSI.m` |
| 0x188344 | 0x188420 | `-[AdaptecU2SCSI scanAdapter]` | `AdaptecU2SCSI.m` |
| 0x188420 | 0x188438 | `-[AdaptecU2SCSI resetStats]` | `AdaptecU2SCSI.m` |
| 0x188438 | 0x188448 | `-[AdaptecU2SCSI sumQueueLengths]` | `AdaptecU2SCSI.m` |
| 0x188448 | 0x188458 | `-[AdaptecU2SCSI maxQueueLength]` | `AdaptecU2SCSI.m` |
| 0x188458 | 0x188468 | `-[AdaptecU2SCSI numQueueSamples]` | `AdaptecU2SCSI.m` |
| 0x188468 | 0x188478 | `-[AdaptecU2SCSI numberOfTargets]` | `AdaptecU2SCSI.m` |
| 0x188478 | 0x188498 | `-[AdaptecU2SCSI maxTransfer]` | `AdaptecU2SCSI.m` |
| 0x188498 | 0x188644 | `-[AdaptecU2SCSI executeRequest:]` | `AdaptecU2SCSI.m` |
| 0x188644 | 0x188804 | `-[AdaptecU2SCSI executeRequest:buffer:client:]` | `AdaptecU2SCSI.m` |
| 0x188804 | 0x188830 | `-[AdaptecU2SCSI executeRequest:ioMemoryDescriptor:]` | `AdaptecU2SCSI.m` |
| 0x188830 | 0x188874 | `-[AdaptecU2SCSI resetSCSIBus]` | `AdaptecU2SCSI.m` |
| 0x188874 | 0x188ab8 | `-[AdaptecU2SCSI free]` | `AdaptecU2SCSI.m` |
| 0x188ab8 | 0x188c38 | `-[AdaptecU2SCSI commandRequestOccurred]` | `AdaptecU2SCSIThread.m` |
| 0x188c38 | 0x1890bc | `-[AdaptecU2SCSI threadExecuteRequest:]` | `AdaptecU2SCSIThread.m` |
| 0x1890bc | 0x1890e0 | `-[AdaptecU2SCSI threadResetSCSIBus:]` | `AdaptecU2SCSIThread.m` |
| 0x1890e0 | 0x189120 | `-[AdaptecU2SCSI timeoutOccurred]` | `AdaptecU2SCSIThread.m` |
| 0x189120 | 0x18914c | `sub_189120` | `AdaptecU2OSMServices.m` |
| 0x18914c | 0x189174 | `sub_18914C` | `AdaptecU2OSMServices.m` |
| 0x189174 | 0x18918c | `sub_189174` | `AdaptecU2OSMServices.m` |
| 0x18918c | 0x1891a0 | `sub_18918C` | `AdaptecU2OSMServices.m` |
| 0x1891a0 | 0x1891b0 | `sub_1891A0` | `AdaptecU2OSMServices.m` |
| 0x1891b0 | 0x1891bc | `sub_1891B0` | `AdaptecU2OSMServices.m` |
| 0x1891bc | 0x189280 | `_OSMReadPCIConfigurationDword` | `AdaptecU2OSMServices.m` |
| 0x189280 | 0x189364 | `_OSMReadPCIConfigurationWord` | `AdaptecU2OSMServices.m` |
| 0x189364 | 0x189448 | `_OSMReadPCIConfigurationByte` | `AdaptecU2OSMServices.m` |
| 0x189448 | 0x18951c | `_OSMWritePCIConfigurationDword` | `AdaptecU2OSMServices.m` |
| 0x18951c | 0x1896bc | `_OSMWritePCIConfigurationWord` | `AdaptecU2OSMServices.m` |
| 0x1896bc | 0x189858 | `_OSMWritePCIConfigurationByte` | `AdaptecU2OSMServices.m` |
| 0x189858 | 0x189aa4 | `_OSMMapIOHandle` | `AdaptecU2OSMServices.m` |
| 0x189aa4 | 0x189b80 | `_OSMReleaseIOHandle` | `AdaptecU2OSMServices.m` |
| 0x189b80 | 0x189d10 | `_OSMEvent` | `OSMFunctions.m` |
| 0x189d10 | 0x189d6c | `_OSMGetBusAddress` | `AdaptecU2OSMServices.m` |
| 0x189d6c | 0x189d84 | `_OSMAdjustBusAddress` | `AdaptecU2OSMServices.m` |
| 0x189d84 | 0x189d94 | `_OSMGetNVSize` | `AdaptecU2OSMServices.m` |
| 0x189d94 | 0x189da4 | `_OSMPutNVData` | `AdaptecU2OSMServices.m` |
| 0x189da4 | 0x189db4 | `_OSMGetNVData` | `AdaptecU2OSMServices.m` |
| 0x189db4 | 0x189de8 | `_OSMReadUExact8` | `AdaptecU2OSMServices.m` |
| 0x189de8 | 0x189e44 | `_OSMReadUExact16` | `AdaptecU2OSMServices.m` |
| 0x189e44 | 0x189ea0 | `_OSMReadUExact32` | `AdaptecU2OSMServices.m` |
| 0x189ea0 | 0x189f0c | `_OSMReadStringUExact8` | `AdaptecU2OSMServices.m` |
| 0x189f0c | 0x18a00c | `_OSMReadStringUExact16` | `AdaptecU2OSMServices.m` |
| 0x18a00c | 0x18a10c | `_OSMReadStringUExact32` | `AdaptecU2OSMServices.m` |
| 0x18a10c | 0x18a148 | `_OSMWriteUExact8` | `AdaptecU2OSMServices.m` |
| 0x18a148 | 0x18a1b4 | `_OSMWriteUExact16` | `AdaptecU2OSMServices.m` |
| 0x18a1b4 | 0x18a20c | `_OSMWriteUExact32` | `AdaptecU2OSMServices.m` |
| 0x18a20c | 0x18a27c | `_OSMWriteStringUExact8` | `AdaptecU2OSMServices.m` |
| 0x18a27c | 0x18a380 | `_OSMWriteStringUExact16` | `AdaptecU2OSMServices.m` |
| 0x18a380 | 0x18a484 | `_OSMWriteStringUExact32` | `AdaptecU2OSMServices.m` |
| 0x18a484 | 0x18a4b0 | `_OSMSynchronizeRange` | `AdaptecU2OSMServices.m` |
| 0x18a4b0 | 0x18a50c | `_OSMWatchdog` | `AdaptecU2OSMServices.m` |
| 0x18a50c | 0x18a51c | `_OSMSaveInterruptState` | `AdaptecU2OSMServices.m` |
| 0x18a51c | 0x18a528 | `_OSMSetInterruptState` | `AdaptecU2OSMServices.m` |
| 0x18a528 | 0x18a66c | `_SendIOBsMaybe` | `OSMFunctions.m` |
| 0x18a66c | 0x18a6bc | `_EnqueueOsmIOB` | `OSMFunctions.m` |
| 0x18a6bc | 0x18a74c | `_HandleHIMFrozen` | `OSMFunctions.m` |
| 0x18a74c | 0x18a7e0 | `_PostUnfreezeHIMQueue` | `OSMFunctions.m` |
| 0x18a7e0 | 0x18a878 | `_ResetSCSIBus` | `OSMFunctions.m` |
| 0x18a878 | 0x18ab0c | `_NormalPostRoutine` | `OSMFunctions.m` |
| 0x18ab0c | 0x18ac08 | `_ProbeTarget` | `OSMFunctions.m` |
| 0x18ac08 | 0x18ad14 | `_PostProtocolAutoConfig` | `OSMFunctions.m` |
| 0x18ad14 | 0x18add4 | `_ValidateTargets` | `OSMFunctions.m` |
| 0x18add4 | 0x18aea0 | `_PostRoutineResetHW` | `OSMFunctions.m` |
| 0x18aea0 | 0x18af70 | `_PostRoutineEventResetHW` | `OSMFunctions.m` |
| 0x18af70 | 0x18afd4 | `_PostRoutineEventPAC` | `OSMFunctions.m` |
| 0x18afd4 | 0x18b1b4 | `_PostProbe` | `OSMFunctions.m` |
| 0x18b1b4 | 0x18b2a8 | `_CleanupWaitingQ` | `OSMFunctions.m` |
| 0x18b2a8 | 0x18b3d0 | `sub_18B2A8` | `OSMFunctions.m` |
| 0x18b3d0 | 0x18b400 | `_AU2Handler` | `OSMFunctions.m` |
| 0x18b400 | 0x18b448 | `_AdaptecU2SCSITimeout` | `OSMFunctions.m` |
| 0x18b448 | 0x18b528 | `__allocOSMIOB` | `OSMFunctions.m` |
| 0x18b528 | 0x18b59c | `__freeOSMIOB` | `OSMFunctions.m` |
| 0x18b59c | 0x18b6a4 | `_AllocOSMIOB` | `OSMFunctions.m` |
| 0x18b6a4 | 0x18b754 | `_FreeOSMIOB` | `OSMFunctions.m` |
| 0x18b754 | 0x18b804 | `_SCSIhDeliverScb` | `AdaptecU2CHIMSCB.c` |
| 0x18b804 | 0x18b85c | `_SCSIhSwapping32PatchXferOpt` | `AdaptecU2CHIMSCB.c` |
| 0x18b85c | 0x18b88c | `_SCSIhStandardAdvPatchXferOpt` | `AdaptecU2CHIMSCB.c` |
| 0x18b88c | 0x18b8bc | `_SCSIhSwappingAdvPatchXferOpt` | `AdaptecU2CHIMSCB.c` |
| 0x18b8bc | 0x18bc6c | `_SCSIhStandard64QHead` | `AdaptecU2CHIMSCB.c` |
| 0x18bc6c | 0x18bf68 | `_SCSIhSwapping32QHead` | `AdaptecU2CHIMSCB.c` |
| 0x18bf68 | 0x18c4ac | `_SCSIhSwappingAdvQHead` | `AdaptecU2CHIMSCB.c` |
| 0x18c4ac | 0x18c85c | `_SCSIhStandardAdvQHead` | `AdaptecU2CHIMSCB.c` |
| 0x18c85c | 0x18c8dc | `_SCSIhStandardRetrieveScb` | `AdaptecU2CHIMSCB.c` |
| 0x18c8dc | 0x18c954 | `_SCSIhStandardQoutcnt` | `AdaptecU2CHIMSCB.c` |
| 0x18c954 | 0x18cae8 | `_SCSIhStandard64QHeadBDR` | `AdaptecU2CHIMSCB.c` |
| 0x18cae8 | 0x18cc70 | `_SCSIhSwapping32QHeadBDR` | `AdaptecU2CHIMSCB.c` |
| 0x18cc70 | 0x18ce04 | `_SCSIhStandardAdvQHeadBDR` | `AdaptecU2CHIMSCB.c` |
| 0x18ce04 | 0x18cf8c | `_SCSIhSwappingAdvQHeadBDR` | `AdaptecU2CHIMSCB.c` |
| 0x18cf8c | 0x18d2ec | `_SCSIhResetChannelHardware` | `AdaptecU2CHIMSCB.c` |
| 0x18d2ec | 0x18d39c | `_SCSIhAbortChannel` | `AdaptecU2CHIMSCB.c` |
| 0x18d39c | 0x18d6f0 | `_SCSIhStandard64ResetSoftware` | `AdaptecU2CHIMSCB.c` |
| 0x18d6f0 | 0x18d938 | `_SCSIhSwappingResetSoftware` | `AdaptecU2CHIMSCB.c` |
| 0x18d938 | 0x18dccc | `_SCSIhStandardAdvResetSoftware` | `AdaptecU2CHIMSCB.c` |
| 0x18dccc | 0x18dfd8 | `_SCSIhSwappingAdvResetSoftware` | `AdaptecU2CHIMSCB.c` |
| 0x18dfd8 | 0x18e05c | `_SCSIhCommonResetSoftware` | `AdaptecU2CHIMSCB.c` |
| 0x18e05c | 0x18e170 | `_SCSIhSetAddressScratchBA32` | `AdaptecU2CHIMSCB.c` |
| 0x18e170 | 0x18e1d0 | `_SCSIhStandardResetBTA` | `AdaptecU2CHIMSCB.c` |
| 0x18e1d0 | 0x18e21c | `_SCSIhSwappingResetBTA` | `AdaptecU2CHIMSCB.c` |
| 0x18e21c | 0x18e324 | `_SCSIhStandardTargetClearBusy` | `AdaptecU2CHIMSCB.c` |
| 0x18e324 | 0x18e34c | `_SCSIhSwappingTargetClearBusy` | `AdaptecU2CHIMSCB.c` |
| 0x18e34c | 0x18e3f0 | `_SCSIhStandardIndexClearBusy` | `AdaptecU2CHIMSCB.c` |
| 0x18e3f0 | 0x18e450 | `_SCSIhSwappingIndexClearBusy` | `AdaptecU2CHIMSCB.c` |
| 0x18e450 | 0x18ea28 | `_SCSIhResetScsi` | `AdaptecU2CHIMSCB.c` |
| 0x18ea28 | 0x18eb98 | `_SCSIhScsiBusReset` | `AdaptecU2CHIMSCB.c` |
| 0x18eb98 | 0x18ec54 | `_SCSIhBusDeviceReset` | `AdaptecU2CHIMSCB.c` |
| 0x18ec54 | 0x18efa8 | `_SCSIhStandard64AbortHIOB` | `AdaptecU2CHIMSCB.c` |
| 0x18efa8 | 0x18f2fc | `_SCSIhStandardAdvAbortHIOB` | `AdaptecU2CHIMSCB.c` |
| 0x18f2fc | 0x18f3e0 | `_SCSIhSwappingAbortHIOB` | `AdaptecU2CHIMSCB.c` |
| 0x18f3e0 | 0x18f730 | `_SCSIhSwappingAdvAbortHIOB` | `AdaptecU2CHIMSCB.c` |
| 0x18f730 | 0x18f984 | `_SCSIhStandardSearchSeqDoneQ` | `AdaptecU2CHIMSCB.c` |
| 0x18f984 | 0x18fbd8 | `_SCSIhStandardAdvSearchSeqDoneQ` | `AdaptecU2CHIMSCB.c` |
| 0x18fbd8 | 0x18fd60 | `_SCSIhStandardSearchDoneQ` | `AdaptecU2CHIMSCB.c` |
| 0x18fd60 | 0x18ffac | `_SCSIhStandard64SearchNewQ` | `AdaptecU2CHIMSCB.c` |
| 0x18ffac | 0x1901f8 | `_SCSIhStandardAdvSearchNewQ` | `AdaptecU2CHIMSCB.c` |
| 0x1901f8 | 0x190408 | `_SCSIhSwappingSearchNewQ` | `AdaptecU2CHIMSCB.c` |
| 0x190408 | 0x190424 | `_SCSIhStandard64ObtainNextScbNum` | `AdaptecU2CHIMSCB.c` |
| 0x190424 | 0x190440 | `_SCSIhSwapping32ObtainNextScbNum` | `AdaptecU2CHIMSCB.c` |
| 0x190440 | 0x19045c | `_SCSIhStandardAdvObtainNextScbNum` | `AdaptecU2CHIMSCB.c` |
| 0x19045c | 0x190478 | `_SCSIhSwappingAdvObtainNextScbNum` | `AdaptecU2CHIMSCB.c` |
| 0x190478 | 0x1904a8 | `_SCSIhStandard64UpdateNextScbNum` | `AdaptecU2CHIMSCB.c` |
| 0x1904a8 | 0x1904d8 | `_SCSIhSwapping32UpdateNextScbNum` | `AdaptecU2CHIMSCB.c` |
| 0x1904d8 | 0x190508 | `_SCSIhStandardAdvUpdateNextScbNum` | `AdaptecU2CHIMSCB.c` |
| 0x190508 | 0x190538 | `_SCSIhSwappingAdvUpdateNextScbNum` | `AdaptecU2CHIMSCB.c` |
| 0x190538 | 0x190564 | `_SCSIhStandard64ObtainNextScbAddress` | `AdaptecU2CHIMSCB.c` |
| 0x190564 | 0x190590 | `_SCSIhStandardAdvObtainNextScbAddress` | `AdaptecU2CHIMSCB.c` |
| 0x190590 | 0x1905cc | `_SCSIhStandard64UpdateNextScbAddress` | `AdaptecU2CHIMSCB.c` |
| 0x1905cc | 0x190608 | `_SCSIhStandardAdvUpdateNextScbAddress` | `AdaptecU2CHIMSCB.c` |
| 0x190608 | 0x1908dc | `_SCSIhStandard64SearchExeQ` | `AdaptecU2CHIMSCB.c` |
| 0x1908dc | 0x1908ec | `_SCSIhSwappingSearchExeQ` | `AdaptecU2CHIMSCB.c` |
| 0x1908ec | 0x190bc0 | `_SCSIhStandardAdvSearchExeQ` | `AdaptecU2CHIMSCB.c` |
| 0x190bc0 | 0x190bfc | `_SCSIhStandard64UpdateAbortBitHostMem` | `AdaptecU2CHIMSCB.c` |
| 0x190bfc | 0x190c38 | `_SCSIhStandardAdvUpdateAbortBitHostMem` | `AdaptecU2CHIMSCB.c` |
| 0x190c38 | 0x190c74 | `_SCSIhSwapping32UpdateAbortBitHostMem` | `AdaptecU2CHIMSCB.c` |
| 0x190c74 | 0x190cb0 | `_SCSIhSwappingAdvUpdateAbortBitHostMem` | `AdaptecU2CHIMSCB.c` |
| 0x190cb0 | 0x190fbc | `_SCSIhStandard64SetupBDR` | `AdaptecU2CHIMSCB.c` |
| 0x190fbc | 0x19111c | `_SCSIhSwapping32SetupBDR` | `AdaptecU2CHIMSCB.c` |
| 0x19111c | 0x19143c | `_SCSIhStandardAdvSetupBDR` | `AdaptecU2CHIMSCB.c` |
| 0x19143c | 0x19159c | `_SCSIhSwappingAdvSetupBDR` | `AdaptecU2CHIMSCB.c` |
| 0x19159c | 0x1917b8 | `_SCSIhStandard64StackBugFix` | `AdaptecU2CHIMSCB.c` |
| 0x1917b8 | 0x191b24 | `_SCSIhSwapping32FreezeHWQueue` | `AdaptecU2CHIMSCB.c` |
| 0x191b24 | 0x191f44 | `_SCSIhSwappingAdvFreezeHWQueue` | `AdaptecU2CHIMSCB.c` |
| 0x191f44 | 0x192064 | `_SCSIHGetConfiguration` | `AdaptecU2CHIMHIM.c` |
| 0x192064 | 0x19213c | `_SCSIHGetMemoryTable` | `AdaptecU2CHIMHIM.c` |
| 0x19213c | 0x1921b8 | `_SCSIHApplyMemoryTable` | `AdaptecU2CHIMHIM.c` |
| 0x1921b8 | 0x1922a8 | `_SCSIHInitialize` | `AdaptecU2CHIMHIM.c` |
| 0x1922a8 | 0x1922c8 | `_SCSIhStandardConfigureScbRam` | `AdaptecU2CHIMConfig.c` |
| 0x1922c8 | 0x192304 | `_SCSIhSetupEnvironment` | `AdaptecU2CHIMConfig.c` |
| 0x192304 | 0x192328 | `_SCSIHSetupHardware` | `AdaptecU2CHIMHIM.c` |
| 0x192328 | 0x1924fc | `_SCSIhPrepareConfig` | `AdaptecU2CHIMConfig.c` |
| 0x1924fc | 0x192708 | `_SCSIhGetCapability` | `AdaptecU2CHIMConfig.c` |
| 0x192708 | 0x19275c | `_SCSIhStandardGetConfig` | `AdaptecU2CHIMConfig.c` |
| 0x19275c | 0x192b6c | `_SCSIhGetMaxHardwareScbs` | `AdaptecU2CHIMConfig.c` |
| 0x192b6c | 0x192b94 | `_SCSIhNonStandardGetConfig` | `AdaptecU2CHIMConfig.c` |
| 0x192b94 | 0x192ba0 | `_SCSIhGetCommonConfig` | `AdaptecU2CHIMConfig.c` |
| 0x192ba0 | 0x192e3c | `_SCSIhGetHardwareConfiguration` | `AdaptecU2CHIMConfig.c` |
| 0x192e3c | 0x193124 | `_SCSIhGetIDBasedConfiguration` | `AdaptecU2CHIMConfig.c` |
| 0x193124 | 0x193154 | `_SCSIhStandard64SetupSequencer` | `AdaptecU2CHIMConfig.c` |
| 0x193154 | 0x193184 | `_SCSIhSwapping32SetupSequencer` | `AdaptecU2CHIMConfig.c` |
| 0x193184 | 0x1931b4 | `_SCSIhStandardAdvSetupSequencer` | `AdaptecU2CHIMConfig.c` |
| 0x1931b4 | 0x1931e4 | `_SCSIhSwappingAdvSetupSequencer` | `AdaptecU2CHIMConfig.c` |
| 0x1931e4 | 0x193554 | `_SCSIhInitializeHardware` | `AdaptecU2CHIMConfig.c` |
| 0x193554 | 0x1936ac | `_SCSIhStartToRunSequencer` | `AdaptecU2CHIMConfig.c` |
| 0x1936ac | 0x193700 | `_SCSIhAIC78XXProcessAutoTerm` | `AdaptecU2CHIMConfig.c` |
| 0x193700 | 0x193794 | `_SCSIhAICBayonetProcessAutoTerm` | `AdaptecU2CHIMConfig.c` |
| 0x193794 | 0x1939dc | `_SCSIhAIC78XXUpdateExtTerm` | `AdaptecU2CHIMConfig.c` |
| 0x1939dc | 0x193bb8 | `_SCSIhAICBayonetUpdateExtTerm` | `AdaptecU2CHIMConfig.c` |
| 0x193bb8 | 0x193ea0 | `_SCSIhIntSrst` | `AdaptecU2CHIMRecovery.c` |
| 0x193ea0 | 0x194074 | `_SCSIhIntIOError` | `AdaptecU2CHIMRecovery.c` |
| 0x194074 | 0x19431c | `_SCSIhCheckLength` | `AdaptecU2CHIMRecovery.c` |
| 0x19431c | 0x19462c | `_SCSIhCdbAbort` | `AdaptecU2CHIMRecovery.c` |
| 0x19462c | 0x1949d0 | `_SCSIhCheckCondition` | `AdaptecU2CHIMRecovery.c` |
| 0x1949d0 | 0x194bd4 | `_SCSIhBadSeq` | `AdaptecU2CHIMRecovery.c` |
| 0x194bd4 | 0x194d40 | `_SCSIhAbortTarget` | `AdaptecU2CHIMRecovery.c` |
| 0x194d40 | 0x194eb8 | `_SCSIhIntSelto` | `AdaptecU2CHIMRecovery.c` |
| 0x194eb8 | 0x195144 | `_SCSIhIntFree` | `AdaptecU2CHIMRecovery.c` |
| 0x195144 | 0x1953d4 | `_SCSIhParityError` | `AdaptecU2CHIMRecovery.c` |
| 0x1953d4 | 0x19573c | `_SCSIhStandard64RequestSense` | `AdaptecU2CHIMRecovery.c` |
| 0x19573c | 0x195848 | `_SCSIhSwapping32RequestSense` | `AdaptecU2CHIMRecovery.c` |
| 0x195848 | 0x195bf8 | `_SCSIhStandardAdvRequestSense` | `AdaptecU2CHIMRecovery.c` |
| 0x195bf8 | 0x195d28 | `_SCSIhSwappingAdvRequestSense` | `AdaptecU2CHIMRecovery.c` |
| 0x195d28 | 0x195e48 | `_SCSIhTerminateCommand` | `AdaptecU2CHIMRecovery.c` |
| 0x195e48 | 0x195f20 | `_SCSIhSetStat` | `AdaptecU2CHIMRecovery.c` |
| 0x195f20 | 0x1960d0 | `_SCSIhBreakInterrupt` | `AdaptecU2CHIMRecovery.c` |
| 0x1960d0 | 0x1965a0 | `_SCSIhStandard64ActiveAbort` | `AdaptecU2CHIMRecovery.c` |
| 0x1965a0 | 0x1967d8 | `_SCSIhSwapping32ActiveAbort` | `AdaptecU2CHIMRecovery.c` |
| 0x1967d8 | 0x196ca4 | `_SCSIhStandardAdvActiveAbort` | `AdaptecU2CHIMRecovery.c` |
| 0x196ca4 | 0x197150 | `_SCSIhSwappingAdvActiveAbort` | `AdaptecU2CHIMRecovery.c` |
| 0x197150 | 0x1972dc | `_SCSIhSwappingRemoveActiveAbort` | `AdaptecU2CHIMRecovery.c` |
| 0x1972dc | 0x19747c | `_SCSIhStandardRemoveActiveAbort` | `AdaptecU2CHIMRecovery.c` |
| 0x19747c | 0x197754 | `_SCSIhStandard64ResidueCalc` | `AdaptecU2CHIMRecovery.c` |
| 0x197754 | 0x1979c0 | `_SCSIhSwapping32ResidueCalc` | `AdaptecU2CHIMRecovery.c` |
| 0x1979c0 | 0x197c58 | `_SCSIhStandardAdvResidueCalc` | `AdaptecU2CHIMRecovery.c` |
| 0x197c58 | 0x197ef0 | `_SCSIhSwappingAdvResidueCalc` | `AdaptecU2CHIMRecovery.c` |
| 0x197ef0 | 0x198100 | `_SCSIhSwappingRemoveAbortHIOBFromNewQ` | `AdaptecU2CHIMRecovery.c` |
| 0x198100 | 0x198464 | `_SCSIhNegotiate` | `AdaptecU2CHIMNegotiation.c` |
| 0x198464 | 0x1985a4 | `_SCSIhExtMsgi` | `AdaptecU2CHIMNegotiation.c` |
| 0x1985a4 | 0x198614 | `_SCSIhInitiateWide` | `AdaptecU2CHIMNegotiation.c` |
| 0x198614 | 0x198884 | `_SCSIhVerifyWideResponse` | `AdaptecU2CHIMNegotiation.c` |
| 0x198884 | 0x198a5c | `_SCSIhInitiateSync` | `AdaptecU2CHIMNegotiation.c` |
| 0x198a5c | 0x198d08 | `_SCSIhVerifySyncResponse` | `AdaptecU2CHIMNegotiation.c` |
| 0x198d08 | 0x198e88 | `_SCSIhRespondToWide` | `AdaptecU2CHIMNegotiation.c` |
| 0x198e88 | 0x1990e4 | `_SCSIhRespondToSync` | `AdaptecU2CHIMNegotiation.c` |
| 0x1990e4 | 0x1993d8 | `_SCSIhSendMessage` | `AdaptecU2CHIMNegotiation.c` |
| 0x1993d8 | 0x199708 | `_SCSIhReceiveMessage` | `AdaptecU2CHIMNegotiation.c` |
| 0x199708 | 0x1999e8 | `_SCSIhHandleMsgOut` | `AdaptecU2CHIMNegotiation.c` |
| 0x1999e8 | 0x199e10 | `_SCSIhHandleMsgIn` | `AdaptecU2CHIMNegotiation.c` |
| 0x199e10 | 0x199eb8 | `_SCSIhAIC78XXCalcScsiRate` | `AdaptecU2CHIMNegotiation.c` |
| 0x199eb8 | 0x199f74 | `_SCSIhAICBayonetCalcScsiRate` | `AdaptecU2CHIMNegotiation.c` |
| 0x199f74 | 0x19a014 | `_SCSIhAIC78XXGetXferPeriod` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a014 | 0x19a15c | `_SCSIhAICBayonetGetXferPeriod` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a15c | 0x19a1f0 | `_SCSIhStandardGetFast20Reg` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a1f0 | 0x19a200 | `_SCSIhStandardAdvGetFast20Reg` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a200 | 0x19a228 | `_SCSIhSwappingGetFast20Reg` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a228 | 0x19a238 | `_SCSIhSwappingAdvGetFast20Reg` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a238 | 0x19a3a0 | `_SCSIhStandardClearFast20Reg` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a3a0 | 0x19a4ec | `_SCSIhSwappingClearFast20Reg` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a4ec | 0x19a6c4 | `_SCSIhStandardLogFast20Map` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a6c4 | 0x19a8e4 | `_SCSIhSwappingLogFast20Map` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a8e4 | 0x19a93c | `_SCSIhSwapping32UpdateFast20HostMem` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a93c | 0x19a9ec | `_SCSIhSwapping32UpdateFast20HW` | `AdaptecU2CHIMNegotiation.c` |
| 0x19a9ec | 0x19aa94 | `_SCSIhCheckSyncNego` | `AdaptecU2CHIMNegotiation.c` |
| 0x19aa94 | 0x19ab58 | `_SCSIhStandardXferOptAssign` | `AdaptecU2CHIMNegotiation.c` |
| 0x19ab58 | 0x19ac30 | `_SCSIhHostXferOptAssign` | `AdaptecU2CHIMNegotiation.c` |
| 0x19ac30 | 0x19ad70 | `_SCSIhChkCondXferAssign` | `AdaptecU2CHIMNegotiation.c` |
| 0x19ad70 | 0x19af7c | `_SCSIhSwapping32CommonXferAssign` | `AdaptecU2CHIMNegotiation.c` |
| 0x19af7c | 0x19b0a8 | `_SCSIhStandardAdvCommonXferAssign` | `AdaptecU2CHIMNegotiation.c` |
| 0x19b0a8 | 0x19b1d4 | `_SCSIhSwappingAdvCommonXferAssign` | `AdaptecU2CHIMNegotiation.c` |
| 0x19b1d4 | 0x19b20c | `_SCSIhSwapping32UpdateXferOptionHostMem` | `AdaptecU2CHIMNegotiation.c` |
| 0x19b20c | 0x19b24c | `_SCSIhStandardAdvUpdateXferOptionHostMem` | `AdaptecU2CHIMNegotiation.c` |
| 0x19b24c | 0x19b28c | `_SCSIhSwappingAdvUpdateXferOptionHostMem` | `AdaptecU2CHIMNegotiation.c` |
| 0x19b28c | 0x19b2e8 | `_SCSIhStandardGetOption` | `AdaptecU2CHIMNegotiation.c` |
| 0x19b2e8 | 0x19b30c | `_SCSIhHostGetOption` | `AdaptecU2CHIMNegotiation.c` |
| 0x19b30c | 0x19b650 | `_SCSIhStandard64ModifyDataPtr` | `AdaptecU2CHIMNegotiation.c` |
| 0x19b650 | 0x19b994 | `_SCSIhSwapping32ModifyDataPtr` | `AdaptecU2CHIMNegotiation.c` |
| 0x19b994 | 0x19bb6c | `_SCSIhStandardAdvModifyDataPtr` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bb6c | 0x19bd44 | `_SCSIhSwappingAdvModifyDataPtr` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bd44 | 0x19bd54 | `_SCSIhAIC78XXGetWideScsiOffset` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bd54 | 0x19bd64 | `_SCSIhAIC78XXGetNarrowScsiOffset` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bd64 | 0x19bd7c | `_SCSIhAICBayonetGetScsiOffset` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bd7c | 0x19bd9c | `_SCSIhAIC78XXClearScsiOffset` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bd9c | 0x19bdc8 | `_SCSIhAICBayonetClearScsiOffset` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bdc8 | 0x19bde0 | `_SCSIhAIC78XXWasSyncXfer` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bde0 | 0x19bdf8 | `_SCSIhAICBayonetWasSyncXfer` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bdf8 | 0x19be08 | `_SCSIhAIC78XXSetDataFifoThrshDefault` | `AdaptecU2CHIMNegotiation.c` |
| 0x19be08 | 0x19be58 | `_SCSIhAIC78XXReadDataFifoThrsh` | `AdaptecU2CHIMNegotiation.c` |
| 0x19be58 | 0x19beb0 | `_SCSIhAIC78XXUpdateDataFifoThrsh` | `AdaptecU2CHIMNegotiation.c` |
| 0x19beb0 | 0x19bec0 | `_SCSIhAICBayonetSetDataFifoThrshDefault` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bec0 | 0x19bf10 | `_SCSIhAICBayonetReadDataFifoThrsh` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bf10 | 0x19bf64 | `_SCSIhAICBayonetUpdateDataFifoThrsh` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bf64 | 0x19bfa0 | `_SCSIhSwappingClearAllFast20Reg` | `AdaptecU2CHIMNegotiation.c` |
| 0x19bfa0 | 0x19c050 | `_SCSIhStandard64ClearAllFast20Reg` | `AdaptecU2CHIMNegotiation.c` |
| 0x19c050 | 0x19c488 | `_SCSIhAIC78XXIgnoreWideResCalc` | `AdaptecU2CHIMNegotiation.c` |
| 0x19c488 | 0x19c7b4 | `_SCSIhAICBayonetIgnoreWideResCalc` | `AdaptecU2CHIMNegotiation.c` |
| 0x19c7b4 | 0x19c87c | `_SCSIhStandardAdvUpdateSGLength` | `AdaptecU2CHIMNegotiation.c` |
| 0x19c87c | 0x19c944 | `_SCSIhSwappingAdvUpdateSGLength` | `AdaptecU2CHIMNegotiation.c` |
| 0x19c944 | 0x19ca40 | `_SCSIhStandardAdvUpdateSGAddress` | `AdaptecU2CHIMNegotiation.c` |
| 0x19ca40 | 0x19cb3c | `_SCSIhSwappingAdvUpdateSGAddress` | `AdaptecU2CHIMNegotiation.c` |
| 0x19cb3c | 0x19cb4c | `_SCSIhScamSupportCheck` | `AdaptecU2CHIMHardware.c` |
| 0x19cb4c | 0x19cc94 | `_SCSIHSizeSEEPROM` | `AdaptecU2CHIMHIM.c` |
| 0x19cc94 | 0x19cea4 | `_SCSIHReadSEEPROM` | `AdaptecU2CHIMHIM.c` |
| 0x19cea4 | 0x19d220 | `_SCSIHWriteSEEPROM` | `AdaptecU2CHIMHIM.c` |
| 0x19d220 | 0x19d390 | `_SCSIhReadE2Register` | `AdaptecU2CHIMHardware.c` |
| 0x19d390 | 0x19d5d0 | `_SCSIhWriteE2Register` | `AdaptecU2CHIMHardware.c` |
| 0x19d5d0 | 0x19d7e8 | `_SCSIhSendE2Address` | `AdaptecU2CHIMHardware.c` |
| 0x19d7e8 | 0x19d89c | `_SCSIhWait2usec` | `AdaptecU2CHIMHardware.c` |
| 0x19d89c | 0x19d8d0 | `_SCSIHSetUnitHandle` | `AdaptecU2CHIMHIM.c` |
| 0x19d8d0 | 0x19d8dc | `_SCSIHFreeUnitHandle` | `AdaptecU2CHIMHIM.c` |
| 0x19d8dc | 0x19d944 | `_SCSIHDisableIRQ` | `AdaptecU2CHIMHIM.c` |
| 0x19d944 | 0x19d9ac | `_SCSIHEnableIRQ` | `AdaptecU2CHIMHIM.c` |
| 0x19d9ac | 0x19da14 | `_SCSIHPollIRQ` | `AdaptecU2CHIMHIM.c` |
| 0x19da14 | 0x19da64 | `_SCSIHQueueHIOB` | `AdaptecU2CHIMHIM.c` |
| 0x19da64 | 0x19db4c | `_SCSIHQueueSpecialHIOB` | `AdaptecU2CHIMHIM.c` |
| 0x19db4c | 0x19db7c | `_SCSIHPowerManagement` | `AdaptecU2CHIMHIM.c` |
| 0x19db7c | 0x19db8c | `_SCSIHApplyDeviceTable` | `AdaptecU2CHIMHIM.c` |
| 0x19db8c | 0x19dbdc | `_SCSIHCheckHostIdle` | `AdaptecU2CHIMHIM.c` |
| 0x19dbdc | 0x19dc40 | `_SCSIHCheckDeviceIdle` | `AdaptecU2CHIMHIM.c` |
| 0x19dc40 | 0x19ddc0 | `_SCSIhAbortTask` | `AdaptecU2CHIMHardware.c` |
| 0x19ddc0 | 0x19deec | `_SCSIhAbortTaskSet` | `AdaptecU2CHIMHardware.c` |
| 0x19deec | 0x19e01c | `_SCSIHSuppressNegotiation` | `AdaptecU2CHIMHIM.c` |
| 0x19e01c | 0x19e144 | `_SCSIHForceNegotiation` | `AdaptecU2CHIMHIM.c` |
| 0x19e144 | 0x19e55c | `_SCSIHGetHWInformation` | `AdaptecU2CHIMHIM.c` |
| 0x19e55c | 0x19e7a8 | `_SCSIHPutHWInformation` | `AdaptecU2CHIMHIM.c` |
| 0x19e7a8 | 0x19e810 | `_SCSIHEnableExpStatus` | `AdaptecU2CHIMHIM.c` |
| 0x19e810 | 0x19e878 | `_SCSIHDisableExpStatus` | `AdaptecU2CHIMHIM.c` |
| 0x19e878 | 0x19e958 | `_SCSIhPauseAndWait` | `AdaptecU2CHIMHardware.c` |
| 0x19e958 | 0x19e9bc | `_SCSIhUnPause` | `AdaptecU2CHIMHardware.c` |
| 0x19e9bc | 0x19eaf0 | `_SCSIHEnableExtScbRam` | `AdaptecU2CHIMHIM.c` |
| 0x19eaf0 | 0x19ebe0 | `_SCSIHDisableExtScbRam` | `AdaptecU2CHIMHIM.c` |
| 0x19ebe0 | 0x19eed0 | `_SCSIhLoadSequencer` | `AdaptecU2CHIMHardware.c` |
| 0x19eed0 | 0x19f0b0 | `_SCSIhWait4Req` | `AdaptecU2CHIMHardware.c` |
| 0x19f0b0 | 0x19f42c | `_SCSIhDelayCount500us` | `AdaptecU2CHIMHardware.c` |
| 0x19f42c | 0x19f494 | `_SCSIhSetupAssignScbBuffer` | `AdaptecU2CHIMHardware.c` |
| 0x19f494 | 0x19f554 | `_SCSIHExtScbRAMAvail` | `AdaptecU2CHIMHIM.c` |
| 0x19f554 | 0x19f670 | `_SCSIHReadScratchRam` | `AdaptecU2CHIMHIM.c` |
| 0x19f670 | 0x19f790 | `_SCSIHWriteScratchRam` | `AdaptecU2CHIMHIM.c` |
| 0x19f790 | 0x19f86c | `_SCSIhAIC78XXAutoTermCable` | `AdaptecU2CHIMHardware.c` |
| 0x19f86c | 0x19ff74 | `_SCSIhCableSense` | `AdaptecU2CHIMHardware.c` |
| 0x19ff74 | 0x19ffe4 | `_SCSIhWriteHCNTRL` | `AdaptecU2CHIMHardware.c` |
| 0x19ffe4 | 0x1a0128 | `_SCSIhWWWriteHCNTRL` | `AdaptecU2CHIMHardware.c` |
| 0x1a0128 | 0x1a0190 | `_SCSIhReadINTSTAT` | `AdaptecU2CHIMHardware.c` |
| 0x1a0190 | 0x1a0304 | `_SCSIhWWReadINTSTAT` | `AdaptecU2CHIMHardware.c` |
| 0x1a0304 | 0x1a0474 | `_SCSIHReadHADDR` | `AdaptecU2CHIMHIM.c` |
| 0x1a0474 | 0x1a0588 | `_SCSIhSetAddressScbBA32` | `AdaptecU2CHIMHardware.c` |
| 0x1a0588 | 0x1a05a8 | `_SCSIhGetAddressScbBA32` | `AdaptecU2CHIMHardware.c` |
| 0x1a05a8 | 0x1a06a4 | `_SCSIhGetEntity32FromScb` | `AdaptecU2CHIMHardware.c` |
| 0x1a06a4 | 0x1a06e4 | `_SCSIhCompareBusAddress` | `AdaptecU2CHIMHardware.c` |
| 0x1a06e4 | 0x1a0734 | `_SCSIhAIC78XXLoadScsiRate` | `AdaptecU2CHIMHardware.c` |
| 0x1a0734 | 0x1a07d4 | `_SCSIhAICBayonetLoadScsiRate` | `AdaptecU2CHIMHardware.c` |
| 0x1a07d4 | 0x1a0828 | `_SCSIhAIC78XXResetDFifo` | `AdaptecU2CHIMHardware.c` |
| 0x1a0828 | 0x1a08bc | `_SCSIhAICBayonetResetDFifo` | `AdaptecU2CHIMHardware.c` |
| 0x1a08bc | 0x1a08c8 | `_SCSIhAIC78XXEnableIOErr` | `AdaptecU2CHIMHardware.c` |
| 0x1a08c8 | 0x1a095c | `_SCSIhAICBayonetEnableIOErr` | `AdaptecU2CHIMHardware.c` |
| 0x1a095c | 0x1a09ac | `_SCSIhAICBayonetGetScbRamCtrls` | `AdaptecU2CHIMHardware.c` |
| 0x1a09ac | 0x1a09d0 | `_SCSIhAIC78XXGetScbRamCtrls` | `AdaptecU2CHIMHardware.c` |
| 0x1a09d0 | 0x1a0a20 | `_SCSIhAICBayonetPutScbRamCtrls` | `AdaptecU2CHIMHardware.c` |
| 0x1a0a20 | 0x1a0a48 | `_SCSIhAIC78XXPutScbRamCtrls` | `AdaptecU2CHIMHardware.c` |
| 0x1a0a48 | 0x1a0a98 | `_SCSIhAIC78XXGetCacheThEn` | `AdaptecU2CHIMHardware.c` |
| 0x1a0a98 | 0x1a0b5c | `_SCSIhAICBayonetGetCacheThEn` | `AdaptecU2CHIMHardware.c` |
| 0x1a0b5c | 0x1a0c50 | `_SCSIhAIC78XXUpdateCacheThEn` | `AdaptecU2CHIMHardware.c` |
| 0x1a0c50 | 0x1a0d8c | `_SCSIhAICBayonetUpdateCacheThEn` | `AdaptecU2CHIMHardware.c` |
| 0x1a0d8c | 0x1a0e28 | `_SCSIhStandardResetCCCtl` | `AdaptecU2CHIMHardware.c` |
| 0x1a0e28 | 0x1a0f24 | `_SCSIhStandardInitCCHHAddr` | `AdaptecU2CHIMHardware.c` |
| 0x1a0f24 | 0x1a0fa4 | `_SCSIhAIC78XXCheckExtArbAckEnBit` | `AdaptecU2CHIMHardware.c` |
| 0x1a0fa4 | 0x1a1024 | `_SCSIhAICBayonetCheckExtArbAckEnBit` | `AdaptecU2CHIMHardware.c` |
| 0x1a1024 | 0x1a1118 | `_SCSIhAIC78XXGetSpeed` | `AdaptecU2CHIMHardware.c` |
| 0x1a1118 | 0x1a11a8 | `_SCSIhAICBayonetGetSpeed` | `AdaptecU2CHIMHardware.c` |
| 0x1a11a8 | 0x1a12a0 | `_SCSIhAIC78XXCalcScsiOption` | `AdaptecU2CHIMHardware.c` |
| 0x1a12a0 | 0x1a139c | `_SCSIhAICBayonetCalcScsiOption` | `AdaptecU2CHIMHardware.c` |
| 0x1a139c | 0x1a1644 | `_SCSIhAIC78XXGetProfileParameters` | `AdaptecU2CHIMHardware.c` |
| 0x1a1644 | 0x1a1880 | `_SCSIhAICBayonetGetProfileParameters` | `AdaptecU2CHIMHardware.c` |
| 0x1a1880 | 0x1a1994 | `_SCSIhAIC78XXPutProfileParameters` | `AdaptecU2CHIMHardware.c` |
| 0x1a1994 | 0x1a1b48 | `_SCSIhAICBayonetPutProfileParameters` | `AdaptecU2CHIMHardware.c` |
| 0x1a1b48 | 0x1a1b9c | `_SCSIhAIC78XXGetQNewTail` | `AdaptecU2CHIMHardware.c` |
| 0x1a1b9c | 0x1a1c44 | `_SCSIhAICBayonetGetQNewTail` | `AdaptecU2CHIMHardware.c` |
| 0x1a1c44 | 0x1a1d50 | `_SCSIhAICBayonetWaitForBusStable` | `AdaptecU2CHIMHardware.c` |
| 0x1a1d50 | 0x1a1eb4 | `_SCSIhSwapping32SetBreakPoint` | `AdaptecU2CHIMHardware.c` |
| 0x1a1eb4 | 0x1a1f88 | `_SCSIhSwappingAdvSetBreakPoint` | `AdaptecU2CHIMHardware.c` |
| 0x1a1f88 | 0x1a20ec | `_SCSIhStandard64SetBreakPoint` | `AdaptecU2CHIMHardware.c` |
| 0x1a20ec | 0x1a21c0 | `_SCSIhStandardAdvSetBreakPoint` | `AdaptecU2CHIMHardware.c` |
| 0x1a21c0 | 0x1a2214 | `_SCSIhSwapping32ClearBreakPoint` | `AdaptecU2CHIMHardware.c` |
| 0x1a2214 | 0x1a22e8 | `_SCSIhSwappingAdvClearBreakPoint` | `AdaptecU2CHIMHardware.c` |
| 0x1a22e8 | 0x1a233c | `_SCSIhStandard64ClearBreakPoint` | `AdaptecU2CHIMHardware.c` |
| 0x1a233c | 0x1a2410 | `_SCSIhStandardAdvClearBreakPoint` | `AdaptecU2CHIMHardware.c` |
| 0x1a2410 | 0x1a245c | `_SCSIhAICBayonetSeqStretchWorkaround` | `AdaptecU2CHIMHardware.c` |
| 0x1a245c | 0x1a24a0 | `_SCSIRGetConfiguration` | `AdaptecU2CHIMResource.c` |
| 0x1a24a0 | 0x1a2528 | `_SCSIRGetMemoryTable` | `AdaptecU2CHIMResource.c` |
| 0x1a2528 | 0x1a2558 | `_SCSIRApplyMemoryTable` | `AdaptecU2CHIMResource.c` |
| 0x1a2558 | 0x1a2598 | `_SCSIRInitialize` | `AdaptecU2CHIMResource.c` |
| 0x1a2598 | 0x1a27c0 | `_SCSIrReset` | `AdaptecU2CHIMResource.c` |
| 0x1a27c0 | 0x1a27e4 | `_SCSIrStandardRemoveScbs` | `AdaptecU2CHIMResource.c` |
| 0x1a27e4 | 0x1a284c | `_SCSIRSetUnitHandle` | `AdaptecU2CHIMResource.c` |
| 0x1a284c | 0x1a286c | `_SCSIRFreeUnitHandle` | `AdaptecU2CHIMResource.c` |
| 0x1a286c | 0x1a2944 | `_SCSIRQueueSpecialHIOB` | `AdaptecU2CHIMResource.c` |
| 0x1a2944 | 0x1a299c | `_SCSIRCheckHostIdle` | `AdaptecU2CHIMResource.c` |
| 0x1a299c | 0x1a2a0c | `_SCSIRCheckDeviceIdle` | `AdaptecU2CHIMResource.c` |
| 0x1a2a0c | 0x1a2acc | `_SCSIrCompleteHIOB` | `AdaptecU2CHIMResource.c` |
| 0x1a2acc | 0x1a2bd0 | `_SCSIrCompleteSpecialHIOB` | `AdaptecU2CHIMResource.c` |
| 0x1a2bd0 | 0x1a2ce4 | `_SCSIrAsyncEvent` | `AdaptecU2CHIMResource.c` |
| 0x1a2ce4 | 0x1a2d48 | `_SCSIrScsiBusReset` | `AdaptecU2CHIMResource.c` |
| 0x1a2d48 | 0x1a2e24 | `_SCSIrBusDeviceReset` | `AdaptecU2CHIMResource.c` |
| 0x1a2e24 | 0x1a2e78 | `_SCSIRPowerManagement` | `AdaptecU2CHIMResource.c` |
| 0x1a2e78 | 0x1a2ef8 | `_SCSIrAbortTask` | `AdaptecU2CHIMResource.c` |
| 0x1a2ef8 | 0x1a2f8c | `_SCSIrAbortTaskSet` | `AdaptecU2CHIMResource.c` |
| 0x1a2f8c | 0x1a2fe8 | `_SCSIRGetHWInformation` | `AdaptecU2CHIMResource.c` |
| 0x1a2fe8 | 0x1a3048 | `_SCSIRPutHWInformation` | `AdaptecU2CHIMResource.c` |
| 0x1a3048 | 0x1a3058 | `_SCSIRGetFreeHead` | `AdaptecU2CHIMResource.c` |
| 0x1a3058 | 0x1a31dc | `_SCSIrAsyncEventCommand` | `AdaptecU2CHIMResource.c` |
| 0x1a31dc | 0x1a324c | `_SCSIrAllocateScb` | `AdaptecU2CHIMResource.c` |
| 0x1a324c | 0x1a3290 | `_SCSIrGetScb` | `AdaptecU2CHIMResource.c` |
| 0x1a3290 | 0x1a32bc | `_SCSIrReturnScb` | `AdaptecU2CHIMResource.c` |
| 0x1a32bc | 0x1a3300 | `_SCSIrDeviceQueueAppend` | `AdaptecU2CHIMResource.c` |
| 0x1a3300 | 0x1a3380 | `_SCSIrDeviceQueueRemove` | `AdaptecU2CHIMResource.c` |
| 0x1a3380 | 0x1a3414 | `_SCSIrAbortHIOBInDevQ` | `AdaptecU2CHIMResource.c` |
| 0x1a3414 | 0x1a34ac | `_SCSIrClearDeviceQueue` | `AdaptecU2CHIMResource.c` |
| 0x1a34ac | 0x1a3508 | `_SCSIrClearAllDeviceQueues` | `AdaptecU2CHIMResource.c` |
| 0x1a3508 | 0x1a3540 | `_SCSIrHostQueueAppend` | `AdaptecU2CHIMResource.c` |
| 0x1a3540 | 0x1a3580 | `_SCSIrHostQueueRemove` | `AdaptecU2CHIMResource.c` |
| 0x1a3580 | 0x1a3614 | `_SCSIrAbortHIOBInHostQ` | `AdaptecU2CHIMResource.c` |
| 0x1a3614 | 0x1a370c | `_SCSIrFindAndAbortHIOB` | `AdaptecU2CHIMResource.c` |
| 0x1a370c | 0x1a37a4 | `_SCSIrClearHostQueue` | `AdaptecU2CHIMResource.c` |
| 0x1a37a4 | 0x1a3888 | `_SCSIrFreeScb` | `AdaptecU2CHIMResource.c` |
| 0x1a3888 | 0x1a3998 | `_SCSIrFreeCriteria` | `AdaptecU2CHIMResource.c` |
| 0x1a3998 | 0x1a39d8 | `_SCSIrPostAbortedHIOB` | `AdaptecU2CHIMResource.c` |
| 0x1a39d8 | 0x1a3a5c | `_SCSIrPostDoneQueue` | `AdaptecU2CHIMResource.c` |
| 0x1a3a5c | 0x1a3abc | `_SCSIrAdjustQueue` | `AdaptecU2CHIMResource.c` |
| 0x1a3abc | 0x1a3b10 | `_SCSIrFinishQueueFull` | `AdaptecU2CHIMResource.c` |
| 0x1a3b10 | 0x1a3b60 | `_SCSIrFreezeAllDeviceQueues` | `AdaptecU2CHIMResource.c` |
| 0x1a3b60 | 0x1a3bc0 | `_SCSIrUnFreezeAllDeviceQueues` | `AdaptecU2CHIMResource.c` |
| 0x1a3bc0 | 0x1a3c0c | `_SCSIrFreezeDeviceQueue` | `AdaptecU2CHIMResource.c` |
| 0x1a3c0c | 0x1a3c50 | `_SCSIrUnFreezeDeviceQueue` | `AdaptecU2CHIMResource.c` |
| 0x1a3c50 | 0x1a3d04 | `_SCSIrDispatchQueuedHIOB` | `AdaptecU2CHIMResource.c` |
| 0x1a3d04 | 0x1a3d38 | `_SCSIGetFunctionPointers` | `AdaptecU2CHIMAPI.c` |
| 0x1a3d38 | 0x1a3d80 | `_SCSIGetNextHostDeviceType` | `AdaptecU2CHIMAPI.c` |
| 0x1a3d80 | 0x1a3e68 | `_SCSICreateInitializationTSCB` | `AdaptecU2CHIMAPI.c` |
| 0x1a3e68 | 0x1a3eb4 | `_SCSIxMaximizeMemory` | `AdaptecU2CHIMTransport.c` |
| 0x1a3eb4 | 0x1a3edc | `_SCSIGetConfiguration` | `AdaptecU2CHIMAPI.c` |
| 0x1a3edc | 0x1a4034 | `_SCSISetConfiguration` | `AdaptecU2CHIMAPI.c` |
| 0x1a4034 | 0x1a4044 | `_SCSISizeAdapterTSCB` | `AdaptecU2CHIMAPI.c` |
| 0x1a4044 | 0x1a4138 | `_SCSICreateAdapterTSCB` | `AdaptecU2CHIMAPI.c` |
| 0x1a4138 | 0x1a4168 | `_SCSISetupAdapterTSCB` | `AdaptecU2CHIMAPI.c` |
| 0x1a4168 | 0x1a433c | `_SCSICheckMemoryNeeded` | `AdaptecU2CHIMAPI.c` |
| 0x1a433c | 0x1a439c | `_SCSISetMemoryPointer` | `AdaptecU2CHIMAPI.c` |
| 0x1a439c | 0x1a4644 | `_SCSIVerifyAdapter` | `AdaptecU2CHIMAPI.c` |
| 0x1a4644 | 0x1a4940 | `_SCSIInitialize` | `AdaptecU2CHIMAPI.c` |
| 0x1a4940 | 0x1a4950 | `_SCSISizeTargetTSCB` | `AdaptecU2CHIMAPI.c` |
| 0x1a4950 | 0x1a4a64 | `_SCSICheckTargetTSCBNeeded` | `AdaptecU2CHIMAPI.c` |
| 0x1a4a64 | 0x1a4c04 | `_SCSICreateTargetTSCB` | `AdaptecU2CHIMAPI.c` |
| 0x1a4c04 | 0x1a4c28 | `_SCSIDisableIRQ` | `AdaptecU2CHIMAPI.c` |
| 0x1a4c28 | 0x1a4c4c | `_SCSIEnableIRQ` | `AdaptecU2CHIMAPI.c` |
| 0x1a4c4c | 0x1a4c78 | `_SCSIPollIRQ` | `AdaptecU2CHIMAPI.c` |
| 0x1a4c78 | 0x1a4c9c | `_SCSIPowerEvent` | `AdaptecU2CHIMAPI.c` |
| 0x1a4c9c | 0x1a4cbc | `_SCSIValidateTargetTSH` | `AdaptecU2CHIMAPI.c` |
| 0x1a4cbc | 0x1a4cfc | `_SCSIxNonScamValidateLun` | `AdaptecU2CHIMTransport.c` |
| 0x1a4cfc | 0x1a4d78 | `_SCSIClearTargetTSH` | `AdaptecU2CHIMAPI.c` |
| 0x1a4d78 | 0x1a4d84 | `_SCSISaveState` | `AdaptecU2CHIMAPI.c` |
| 0x1a4d84 | 0x1a4d90 | `_SCSIRestoreState` | `AdaptecU2CHIMAPI.c` |
| 0x1a4d90 | 0x1a5170 | `_SCSIProfileAdapter` | `AdaptecU2CHIMAPI.c` |
| 0x1a5170 | 0x1a51d0 | `_SCSIReportAdjustableAdapterProfile` | `AdaptecU2CHIMAPI.c` |
| 0x1a51d0 | 0x1a5520 | `_SCSIAdjustAdapterProfile` | `AdaptecU2CHIMAPI.c` |
| 0x1a5520 | 0x1a56c4 | `_SCSIProfileTarget` | `AdaptecU2CHIMAPI.c` |
| 0x1a56c4 | 0x1a56f4 | `_SCSIReportAdjustableTargetProfile` | `AdaptecU2CHIMAPI.c` |
| 0x1a56f4 | 0x1a5a00 | `_SCSIAdjustTargetProfile` | `AdaptecU2CHIMAPI.c` |
| 0x1a5a00 | 0x1a5ad4 | `_SCSIGetNVSize` | `AdaptecU2CHIMAPI.c` |
| 0x1a5ad4 | 0x1a5ce8 | `_SCSIGetNVOSMSegment` | `AdaptecU2CHIMAPI.c` |
| 0x1a5ce8 | 0x1a5d70 | `_SCSIPutNVData` | `AdaptecU2CHIMAPI.c` |
| 0x1a5d70 | 0x1a5e00 | `_SCSIGetNVData` | `AdaptecU2CHIMAPI.c` |
| 0x1a5e00 | 0x1a5e10 | `_SCSIProfileNexus` | `AdaptecU2CHIMAPI.c` |
| 0x1a5e10 | 0x1a5e20 | `_SCSIClearNexusTSH` | `AdaptecU2CHIMAPI.c` |
| 0x1a5e20 | 0x1a5e30 | `_SCSIProfileNode` | `AdaptecU2CHIMAPI.c` |
| 0x1a5e30 | 0x1a5e40 | `_SCSIReportAdjustableNodeProfile` | `AdaptecU2CHIMAPI.c` |
| 0x1a5e40 | 0x1a5e50 | `_SCSIAdjustNodeProfile` | `AdaptecU2CHIMAPI.c` |
| 0x1a5e50 | 0x1a5e60 | `_SCSISetOSMNodeContext` | `AdaptecU2CHIMAPI.c` |
| 0x1a5e60 | 0x1a62cc | `_SCSIQueueIOB` | `AdaptecU2CHIMAPI.c` |
| 0x1a62cc | 0x1a64ec | `_SCSIFrontEndISR` | `AdaptecU2CHIMAPI.c` |
| 0x1a64ec | 0x1a6f64 | `_SCSIBackEndISR` | `AdaptecU2CHIMAPI.c` |
| 0x1a6f64 | 0x1a6f9c | `_OSDBuildSCB` | `AdaptecU2CHIMOSD.c` |
| 0x1a6f9c | 0x1a7194 | `_OSDStandard64BuildSCB` | `AdaptecU2CHIMOSD.c` |
| 0x1a7194 | 0x1a73c8 | `_OSDSwapping32BuildSCB` | `AdaptecU2CHIMOSD.c` |
| 0x1a73c8 | 0x1a75c0 | `_OSDStandardAdvBuildSCB` | `AdaptecU2CHIMOSD.c` |
| 0x1a75c0 | 0x1a77b4 | `_OSDSwappingAdvBuildSCB` | `AdaptecU2CHIMOSD.c` |
| 0x1a77b4 | 0x1a77c8 | `_OSDGetSGList` | `AdaptecU2CHIMOSD.c` |
| 0x1a77c8 | 0x1a7824 | `_OSDCompleteHIOB` | `AdaptecU2CHIMOSD.c` |
| 0x1a7824 | 0x1a7924 | `_OSDCompleteSpecialHIOB` | `AdaptecU2CHIMOSD.c` |
| 0x1a7924 | 0x1a7b04 | `_SCSIxTranslateError` | `AdaptecU2CHIMTransport.c` |
| 0x1a7b04 | 0x1a7b3c | `_OSDGetBusAddress` | `AdaptecU2CHIMOSD.c` |
| 0x1a7b3c | 0x1a7b70 | `_OSDAdjustBusAddress` | `AdaptecU2CHIMOSD.c` |
| 0x1a7b70 | 0x1a7ba8 | `_OSDReadPciConfiguration` | `AdaptecU2CHIMOSD.c` |
| 0x1a7ba8 | 0x1a7bdc | `_OSDWritePciConfiguration` | `AdaptecU2CHIMOSD.c` |
| 0x1a7bdc | 0x1a7ca4 | `_OSDAsyncEvent` | `AdaptecU2CHIMOSD.c` |
| 0x1a7ca4 | 0x1a7cb4 | `_OSDGetHostAddress` | `AdaptecU2CHIMOSD.c` |
| 0x1a7cb4 | 0x1a7cd0 | `_SCSIxApplyNVData` | `AdaptecU2CHIMTransport.c` |
| 0x1a7cd0 | 0x1a7ce0 | `_SCSIxBiosExist` | `AdaptecU2CHIMTransport.c` |
| 0x1a7ce0 | 0x1a7cf0 | `_SCSIxOptimaExist` | `AdaptecU2CHIMTransport.c` |
| 0x1a7cf0 | 0x1a7d18 | `_SCSIxChkLunExist` | `AdaptecU2CHIMTransport.c` |
| 0x1a7d18 | 0x1a7d48 | `_SCSIxSetLunExist` | `AdaptecU2CHIMTransport.c` |
| 0x1a7d48 | 0x1a7d78 | `_SCSIxClearLunExist` | `AdaptecU2CHIMTransport.c` |
| 0x1a7d78 | 0x1a7e38 | `_SCSIxSetupBusScan` | `AdaptecU2CHIMTransport.c` |
| 0x1a7e38 | 0x1a7ee8 | `_SCSIxSetupLunProbe` | `AdaptecU2CHIMTransport.c` |
| 0x1a7ee8 | 0x1a8180 | `_SCSIxQueueBusScan` | `AdaptecU2CHIMTransport.c` |
| 0x1a8180 | 0x1a86fc | `_SCSIxPostBusScan` | `AdaptecU2CHIMTransport.c` |
| 0x1a86fc | 0x1a87cc | `_SCSIxQueueSpecialIOB` | `AdaptecU2CHIMTransport.c` |
| 0x1a87cc | 0x1a87e8 | `_SCSIxPostQueueSpecialIOB` | `AdaptecU2CHIMTransport.c` |
| 0x1a87e8 | 0x1a88dc | `_SCSIxGetSpeed` | `AdaptecU2CHIMTransport.c` |
| 0x1a88dc | 0x1a89bc | `_SCSIxCalcScsiOption` | `AdaptecU2CHIMTransport.c` |
| 0x1a89bc | 0x1a8aa4 | `_SCSIxDetermineFirmwareMode` | `AdaptecU2CHIMTransport.c` |
| 0x1a8aa4 | 0x1a8adc | `_SCSIxGetNextSubSystemSubVendorID` | `AdaptecU2CHIMTransport.c` |
<!-- functions:end -->

## CHIM accounting

| Owner | Bodies |
| --- | ---: |
| `AdaptecU2CHIMSCB.c` | 67 |
| `AdaptecU2CHIMConfig.c` | 20 |
| `AdaptecU2CHIMRecovery.c` | 28 |
| `AdaptecU2CHIMNegotiation.c` | 63 |
| `AdaptecU2CHIMHardware.c` | 61 |
| `AdaptecU2CHIMHIM.c` | 31 |
| `AdaptecU2CHIMResource.c` | 47 |
| `AdaptecU2CHIMTransport.c` | 19 |
| `AdaptecU2CHIMOSD.c` | 14 |
| `AdaptecU2CHIMAPI.c` | 42 |

## Objective-C aliases

The primary class has 21 methods and category `AdaptecU2SCSIThread` has four.
IDA displays the category methods without category qualification; both spellings name the same body.
Targeted extraction reads only `AdaptecU2SCSI.m`, `AdaptecU2SCSIThread.m`, and `OSMFunctions.m`.
It preserves class instance size `0x5d0`, ivars, method encodings, category membership, and implementation addresses.

| Address | Metadata name | Module |
| --- | --- | --- |
| 0x1877c8 | `+[AdaptecU2SCSI initialize]` | `AdaptecU2SCSI.m` |
| 0x1877f8 | `+[AdaptecU2SCSI probe:]` | `AdaptecU2SCSI.m` |
| 0x1878a8 | `-[AdaptecU2SCSI registerHandlerForIRQ:]` | `AdaptecU2SCSI.m` |
| 0x1879cc | `-[AdaptecU2SCSI initFromDeviceDescription:]` | `AdaptecU2SCSI.m` |
| 0x187d38 | `-[AdaptecU2SCSI getWorkingMemoryForCHIM]` | `AdaptecU2SCSI.m` |
| 0x187d8c | `-[AdaptecU2SCSI findAdapter]` | `AdaptecU2SCSI.m` |
| 0x187e54 | `-[AdaptecU2SCSI initAdapter]` | `AdaptecU2SCSI.m` |
| 0x188134 | `-[AdaptecU2SCSI allocateAdapterMemory]` | `AdaptecU2SCSI.m` |
| 0x188294 | `-[AdaptecU2SCSI createOSMIOBPool]` | `AdaptecU2SCSI.m` |
| 0x188344 | `-[AdaptecU2SCSI scanAdapter]` | `AdaptecU2SCSI.m` |
| 0x188420 | `-[AdaptecU2SCSI resetStats]` | `AdaptecU2SCSI.m` |
| 0x188438 | `-[AdaptecU2SCSI sumQueueLengths]` | `AdaptecU2SCSI.m` |
| 0x188448 | `-[AdaptecU2SCSI maxQueueLength]` | `AdaptecU2SCSI.m` |
| 0x188458 | `-[AdaptecU2SCSI numQueueSamples]` | `AdaptecU2SCSI.m` |
| 0x188468 | `-[AdaptecU2SCSI numberOfTargets]` | `AdaptecU2SCSI.m` |
| 0x188478 | `-[AdaptecU2SCSI maxTransfer]` | `AdaptecU2SCSI.m` |
| 0x188498 | `-[AdaptecU2SCSI executeRequest:]` | `AdaptecU2SCSI.m` |
| 0x188644 | `-[AdaptecU2SCSI executeRequest:buffer:client:]` | `AdaptecU2SCSI.m` |
| 0x188804 | `-[AdaptecU2SCSI executeRequest:ioMemoryDescriptor:]` | `AdaptecU2SCSI.m` |
| 0x188830 | `-[AdaptecU2SCSI resetSCSIBus]` | `AdaptecU2SCSI.m` |
| 0x188874 | `-[AdaptecU2SCSI free]` | `AdaptecU2SCSI.m` |
| 0x188ab8 | `-[AdaptecU2SCSI(AdaptecU2SCSIThread) commandRequestOccurred]` | `AdaptecU2SCSIThread.m` |
| 0x188c38 | `-[AdaptecU2SCSI(AdaptecU2SCSIThread) threadExecuteRequest:]` | `AdaptecU2SCSIThread.m` |
| 0x1890bc | `-[AdaptecU2SCSI(AdaptecU2SCSIThread) threadResetSCSIBus:]` | `AdaptecU2SCSIThread.m` |
| 0x1890e0 | `-[AdaptecU2SCSI(AdaptecU2SCSIThread) timeoutOccurred]` | `AdaptecU2SCSIThread.m` |

## Boundary and helper decisions

- No overlapping, missing, or disputed instruction extents exist in either contiguous partition. All 476 bodies remain required.
- `AdptMallocContiguous` at `0x18770c` and `AdptFreeContiguous` at `0x18779c` belong to `AdaptecU2OSMServices.m`. The former bounds requests by `page_size`, allocates `2*size+4`, aligns within a page using `page_shift`/`page_mask`, and saves the base pointer at returned-pointer minus four; the latter releases that base with the matching allocation size.
- `sub_189120` (`0x189120..0x18914c`) uses `lhbrx` and returns a zero-extended swapped halfword; `sub_18914C` (`0x18914c..0x189174`) uses `lwbrx` and returns a swapped word.
- `sub_189174` and `sub_1891A0` zero-extend the low halfword. `sub_18918C` preserves r3 while writing stack locals; `sub_1891B0` preserves r3 with only a stack frame. These six conversion-related bodies belong to `AdaptecU2OSMServices.m`; decompiler void spellings do not establish their final signatures.
- `sub_18B2A8` (`0x18b2a8..0x18b3d0`) belongs to `OSMFunctions.m`. It indexes `adapterQ` using controller offset `0x5a4`, walks the adapter chain three times, and calls HIM slots at controller offsets `0x514`/`0x518`, then `0x508`, then `0x50c`, with adapterTSH at `0x2a8`. Its address is passed to `thread_call_func` by AU2Handler; there is no direct branch caller.
- Unnamed `sub_ADDRESS` names remain stable analysis identities, not invented exported C names. No body is classified as compiler-generated or exempted; final signatures and any generating constructs require later recovery/build evidence.

## Data ownership

The extents below are byte-preservation extraction envelopes. Firmware envelopes include any alignment bytes before the next symbol; descriptor-defined executable lengths are recovered in the firmware task. Diagnostic strings are retained as a single contiguous owned pool.

| Name | Address | Exclusive end | Owner |
| --- | --- | --- | --- |
| `request_message` | 0x27803c | 0x278054 | `AdaptecU2SCSI.m` |
| `OSMRoutines` | 0x278054 | 0x2780d0 | `OSMFunctions.m` |
| `adapterQ` | 0x2780d0 | 0x2782d0 | `AdaptecU2SCSI.m` |
| `diagnostic_strings` | 0x2782d0 | 0x278c7c | `OSMFunctions.m` |
| `SCSIHardwareAIC78XX` | 0x278c7c | 0x278cf4 | `AdaptecU2CHIMTables.c` |
| `SCSIHardwareAICBayonet` | 0x278cf4 | 0x278d6c | `AdaptecU2CHIMTables.c` |
| `SCSIHardware` | 0x278d6c | 0x278d78 | `AdaptecU2CHIMTables.c` |
| `Seq_s64` | 0x278d78 | 0x279548 | `AdaptecU2CHIMFirmware.c` |
| `Seq_w32` | 0x279548 | 0x279c34 | `AdaptecU2CHIMFirmware.c` |
| `Seq_sAdv` | 0x279c34 | 0x27a44c | `AdaptecU2CHIMFirmware.c` |
| `Seq_wAdv` | 0x27a44c | 0x27ad1c | `AdaptecU2CHIMFirmware.c` |
| `SCSIFirmwareStandard64` | 0x27ad1c | 0x27ae44 | `AdaptecU2CHIMTables.c` |
| `SCSIFirmwareSwapping32` | 0x27ae44 | 0x27af6c | `AdaptecU2CHIMTables.c` |
| `SCSIFirmwareStandardAdv` | 0x27af6c | 0x27b094 | `AdaptecU2CHIMTables.c` |
| `SCSIFirmwareSwappingAdv` | 0x27b094 | 0x27b1bc | `AdaptecU2CHIMTables.c` |
| `SCSIFirmware` | 0x27b1bc | 0x27b1d8 | `AdaptecU2CHIMTables.c` |
| `SCSIHostType` | 0x27b1d8 | 0x27b318 | `AdaptecU2CHIMTables.c` |
| `SCSISubSystemSubVendorType` | 0x27b318 | 0x27b398 | `AdaptecU2CHIMTables.c` |
| `SCSIFuncPtrs` | 0x27b398 | 0x27b440 | `AdaptecU2CHIMTables.c` |
| `SCSIConfiguration` | 0x27b440 | 0x27b484 | `AdaptecU2CHIMTables.c` |
| `SCSIDefaultAdapterProfile` | 0x27b484 | 0x27b654 | `AdaptecU2CHIMTables.c` |
| `SCSIAdjustableAdapterProfile` | 0x27b654 | 0x27b824 | `AdaptecU2CHIMTables.c` |
| `SCSIDefaultTargetProfile` | 0x27b824 | 0x27b8a0 | `AdaptecU2CHIMTables.c` |
| `SCSIAdjustableTargetProfile` | 0x27b8a0 | 0x27b91c | `AdaptecU2CHIMTables.c` |
| `SCSIscontrol` | 0x27b91c | 0x27b924 | `AdaptecU2CHIMTables.c` |
| `event_names` | 0x230ca0 | 0x230ce0 | `OSMFunctions.m` |

Switch tables outside the text/data cluster remain owned by their containing routine. Each range was checked with IDA data-item extents and incoming code references. They are retained in raw form; their rebuilt compiler-generated counterpart is established during build verification.

| Name | Address | Size | Referencing function | Owner |
| --- | --- | ---: | --- | --- |
| `jpt_189BE0` | 0x230ce0 | 28 | `_OSMEvent` | `OSMFunctions.m` |
| `jpt_18A934` | 0x230cfc | 320 | `_NormalPostRoutine` | `OSMFunctions.m` |
| `jpt_1925D0` | 0x230e3c | 84 | `_SCSIhGetCapability` | `AdaptecU2CHIMConfig.c` |
| `jpt_192634` | 0x230e90 | 48 | `_SCSIhGetCapability` | `AdaptecU2CHIMConfig.c` |
| `jpt_199FC0` | 0x230ec0 | 20 | `_SCSIhAIC78XXGetXferPeriod` | `AdaptecU2CHIMNegotiation.c` |
| `jpt_19DAA8` | 0x230ed4 | 32 | `_SCSIHQueueSpecialHIOB` | `AdaptecU2CHIMHIM.c` |
| `jpt_1A1150` | 0x230ef4 | 40 | `_SCSIhAICBayonetGetSpeed` | `AdaptecU2CHIMHardware.c` |
| `jpt_1A28C8` | 0x230f1c | 36 | `_SCSIRQueueSpecialHIOB` | `AdaptecU2CHIMResource.c` |
| `jpt_1A2C34` | 0x230f40 | 32 | `_SCSIrAsyncEvent` | `AdaptecU2CHIMResource.c` |
| `jpt_1A4F70` | 0x230f60 | 32 | `_SCSIProfileAdapter` | `AdaptecU2CHIMAPI.c` |
| `jpt_1A5000` | 0x230f80 | 32 | `_SCSIProfileAdapter` | `AdaptecU2CHIMAPI.c` |
| `jpt_1A5BA8` | 0x230fa0 | 48 | `_SCSIGetNVOSMSegment` | `AdaptecU2CHIMAPI.c` |
| `jpt_1A6138` | 0x230fd0 | 76 | `_SCSIQueueIOB` | `AdaptecU2CHIMAPI.c` |
| `jpt_1A6D94` | 0x23101c | 292 | `_SCSIBackEndISR` | `AdaptecU2CHIMAPI.c` |
| `jpt_1A6DE4` | 0x231140 | 164 | `_SCSIBackEndISR` | `AdaptecU2CHIMAPI.c` |
| `jpt_1A6EC0` | 0x2311e4 | 116 | `_SCSIBackEndISR` | `AdaptecU2CHIMAPI.c` |
| `jpt_1A786C` | 0x231258 | 44 | `_OSDCompleteSpecialHIOB` | `AdaptecU2CHIMOSD.c` |
| `jpt_1A7978` | 0x231284 | 292 | `_SCSIxTranslateError` | `AdaptecU2CHIMTransport.c` |
| `jpt_1A79D0` | 0x2313a8 | 164 | `_SCSIxTranslateError` | `AdaptecU2CHIMTransport.c` |
| `jpt_1A7AAC` | 0x23144c | 116 | `_SCSIxTranslateError` | `AdaptecU2CHIMTransport.c` |
| `jpt_1A7C38` | 0x2314c0 | 32 | `_OSDAsyncEvent` | `AdaptecU2CHIMOSD.c` |
| `jpt_1A8214` | 0x2314e0 | 320 | `_SCSIxPostBusScan` | `AdaptecU2CHIMTransport.c` |

## Shared providers

Direct external code references identify the following 29 shared services. Calls through Objective-C dispatch, HIM/OSM tables, and platform function pointers retain their dynamic contracts for later interface recovery; direct-call enumeration does not prove indirect-call closure. No shared service is duplicated in the driver.

| Address | Reference name | Existing provider |
| --- | --- | --- |
| 0x5e08 | `_bzero` | `src/kernel-7/machdep/ppc/bcopy.s` |
| 0x5e58 | `_memset` | `src/kernel-7/machdep/ppc/bcopy.s` |
| 0xdda90 | `_msg_send_from_kernel` | `src/kernel-7/kern/ipc_mig.c` |
| 0xdf4ec | `_task_self` | `src/kernel-7/kern/ipc_tt.c` |
| 0xe07dc | `_kalloc` | `src/kernel-7/kern/kalloc.c` |
| 0xe0930 | `_kfree` | `src/kernel-7/kern/kalloc.c` |
| 0xe72ec | `_ns_timeout` | `src/kernel-7/kern/ns_timer.c` |
| 0xf0998 | `_thread_call_func` | `src/kernel-7/kern/thread_call.c` |
| 0x1439f8 | `_pmap_add_physical_memory` | `src/kernel-7/machdep/ppc/pmap.c` |
| 0x148dd0 | `_fast_bcopy` | `src/kernel-7/machdep/ppc/bcopy.s` |
| 0x148f00 | `_memcpy` | `src/kernel-7/machdep/ppc/bcopy.s` |
| 0x14a4a0 | `_flush_cache` | `src/kernel-7/machdep/ppc/cache.s` |
| 0x1d8804 | `_IOMalloc` | `src/driverkit-3/libDriver/Kernel/generalFuncs.m` |
| 0x1d8838 | `_IOFree` | `src/driverkit-3/libDriver/Kernel/generalFuncs.m` |
| 0x1d8938 | `_IOScheduleFunc` | `src/driverkit-3/libDriver/Kernel/generalFuncs.m` |
| 0x1d89a0 | `_IOUnscheduleFunc` | `src/driverkit-3/libDriver/Kernel/generalFuncs.m` |
| 0x1d89d4 | `_IOGetTimestamp` | `src/driverkit-3/libDriver/Kernel/generalFuncs.m` |
| 0x1d8a5c | `_IOLog` | `src/driverkit-3/libDriver/Kernel/generalFuncs.m` |
| 0x1d8abc | `_IOPanic` | `src/driverkit-3/libDriver/Kernel/generalFuncs.m` |
| 0x1d8af0 | `_IOFindNameForValue` | `src/driverkit-3/libDriver/Kernel/generalFuncs.m` |
| 0x1e01c0 | `_IOExitThread` | `src/driverkit-3/libDriver/Kernel/generalFuncsPrivate.m` |
| 0x1e01fc | `_IOVmTaskSelf` | `src/driverkit-3/libDriver/Kernel/generalFuncsPrivate.m` |
| 0x1e02ec | `_IOConvertPort` | `src/driverkit-3/libDriver/Kernel/generalFuncsPrivate.m` |
| 0x1e0418 | `_IOPhysicalFromVirtual` | `src/driverkit-3/libDriver/Kernel/generalFuncsPrivate.m` |
| 0x1e0478 | `_IOMapPhysicalIntoIOTask` | `src/driverkit-3/libDriver/Kernel/generalFuncsPrivate.m` |
| 0x1e05cc | `_IOUnmapPhysicalFromIOTask` | `src/driverkit-3/libDriver/Kernel/generalFuncsPrivate.m` |
| 0x21e27c | `_objc_msgSend` | `src/objc-1/objc-msg-ppc.s` |
| 0x21e620 | `_objc_msgSendSuper` | `src/objc-1/objc-msg-ppc.s` |
| 0x22adc8 | `_port_set_backlog_EXTERNAL` | `src/kernel-7/ipc/mach_port.c` |

Additional shared data: `_page_size` at `0x2495d0`, `_page_mask` at `0x2a3420`, and `_page_shift` at `0x2a3424` are VM page geometry (`src/kernel-7/vm/vm_resident.c`). `_pmac_int_to_number` at `0x308f98` and `_pmac_register_int` at `0x308f9c` are platform callbacks declared by `src/kernel-7/machdep/ppc/interrupts.h` and supplied by platform initialization.

Objective-C receiver services are supplied by `src/driverkit-3/libDriver/Kernel/IOSCSIController.m`, `src/driverkit-3/libDriver/IODevice.m`, `src/driverkit-3/libDriver/pci/IOPCIDeviceDescription.m`, `src/driverkit-3/libDriver/Kernel/IOMemoryDescriptor.m`, and `src/driverkit-3/libDriver/Kernel/NXLock.m`. Their class, selector and method-name metadata resides in the kernel-wide Objective-C sections. Driver selectors remain attributed to the 25 methods listed above; external selectors and superclass metadata retain their shared runtime provider.

The instruction at `0x1a3f24` reads the configuration word at `0x27b468`; IDA also interprets its value `0x58` as a data address. `0x58` is a scalar, not an additional owned object. The message template at `0x27803c..0x278054` contains the six words `1,24,0,0,0,0x232324`: its last word at `0x278050` is the message ID. IDA also interprets that scalar as a pointer to `0x232324`; there is no additional dependency on data at that address. Neither ordinary scalar is normalized as a pointer.

IDA exposes two sign-extended synthetic stack targets outside the PPC32 address space. The existing exporter excludes those invalid effective addresses; no actual PPC32 branch or data address is excluded.

## Initial reconstruction evidence

Generate the full source map with `binrecon source-map --objc-methods` and **without** `--scope-to-objc`, using the complete published analysis and this driver directory. Seed all entries with `tools/binrecon/seed_ledger.py`. Initial mapped sites are name matches only; duplicate definitions remain `duplicate_candidates`, missing bodies remain `unmapped`, and all 476 ledger entries start `unexamined`. This inventory does not certify draft behavior, target layouts, firmware lengths, or hardware operation.

Reference image, raw analyzer output, helper disassembly/pseudocode, targeted ABI metadata, data bytes, and logs remain under ignored `tools/binrecon/out/adaptecu2scsi-ppc/` or the task scratch workspace. `reference.py` requires an explicit saved IDA analysis; `verify.py inventory` validates its identity and frozen address/name/extent/owner partition against this document, checks metadata/data evidence, and rejects stale or incomplete source maps and ledgers.
