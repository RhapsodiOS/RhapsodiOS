# driverLoader reference nlists

Date: 2026-09-27

## References

| Slice | Path | SHA-256 | Size | `__text` |
|---|---|---|---|---|
| i386 (Rhapsody DR2) | `C:\Users\raynorpat\Downloads\test\DR2\usr\sbin\driverLoader` | `e005522ec2e4f107b8071a573ccda9208d49e64e2114d08b8868ee956a0e98b7` | 70132 | `0x3840`, 28940 |
| ppc (Mac OS X Server 1.2v3) | `C:\Users\raynorpat\Downloads\test\MOSXS12v3\usr\sbin\driverLoader` | `cd8dd33035aae133ce4ab1d6a203807cbceabc3d5d300326ff105ad33d9d3e14` | 40776 | `0x2acc`, 13080 |

Both are unstripped: i386 has 349 symbol table entries, ppc 117.

## Owned code (both slices, same order)

| Symbol | i386 | ppc | Section (i386) |
|---|---|---|---|
| `_main` | `0x39a0` external | `0x2cf0` external | __TEXT,__text |
| `_usage` | `0x3d4c` local | `0x3024` local | __TEXT,__text |
| `_inquire` | `0x3dac` local | `0x3094` local | __TEXT,__text |
| `_processDriverList` | `0x3e1c` local | `0x3130` local | __TEXT,__text |
| `_processDriver` | `0x3ec0` local | `0x3220` local | __TEXT,__text |
| `_loadDriver` | `0x3fb0` local | `0x335c` local | __TEXT,__text |
| `_unloadDriver` | `0x41c4` local | `0x35a4` local | __TEXT,__text |
| `_getInstanceFile` | `0x43d8` local | `0x37e0` local | __TEXT,__text |
| `_configDriver` | `0x44cc` local | `0x3918` local | __TEXT,__text |
| `_securityCheck` | `0x46e8` local | `0x3b40` local | __TEXT,__text |
| `_securityCheckDir` | `0x4730` local | `0x3b9c` local | __TEXT,__text |
| `_prePostExec` | `0x4a14` local | `0x3e04` local | __TEXT,__text |
| `_kl_init` | `0x4b98` local | `0x3fac` local | __TEXT,__text |
| `_kl_com_log` | `0x4d28` local | `0x4164` local | __TEXT,__text |
| `_print_string` | `0x4ea8` local | `0x432c` local | __TEXT,__text |
| `_ping` | `0x4eb4` local | `0x433c` local | __TEXT,__text |
| `_kl_com_add` | `0x4ef8` external | `0x439c` external | __TEXT,__text |
| `_kl_com_delete` | `0x4f78` external | `0x444c` external | __TEXT,__text |
| `_kl_com_load` | `0x4fd0` external | `0x44c8` external | __TEXT,__text |
| `_kl_com_unload` | `0x5030` external | `0x4550` external | __TEXT,__text |
| `_kl_com_get_state` | `0x5088` external | `0x45cc` external | __TEXT,__text |
| `_kl_com_error` | `0x5158` local | `0x46a8` local | __TEXT,__text |
| `_kl_com_wait` | `0x5178` external | `0x46ec` external | __TEXT,__text |
| `_verbose` | `0xc018` external | `0x7018` external | __DATA,__data |
| `_interactive` | `0xc01c` external | `0x701c` external | __DATA,__data |
| `_instruction` | `0xc020` local | `0x7020` local | __DATA,__data |
| `_progName` | `0xc330` external | `0x71b0` external | __DATA,__common |
| `_kl_init_flag` | `0xc028` external | `0x7028` external | __DATA,__data |
| `_kl_port` | `0xc334` external | `0x71b4` external | __DATA,__common |
| `_kernel_task` | `0xc338` external | `0x71b8` external | __DATA,__common |
| `_reply_port` | `0xc33c` external | `0x71bc` external | __DATA,__common |
| `_kern_loader_reply` | `0xc02c` external | `0x702c` external | __DATA,__data |
| `_ping_lock` | `0xc344` local | `0x71c8` local | __DATA,__bss |
| `_strings.N` | `0xc298` local | `0x711c` local | __DATA,__const |

`_strings.N` is the function-local static table of server state names in `kl_com_get_state`; gcc numbered it differently on each slice.

## libkernload code (both slices)

| Symbol | i386 | ppc | Section (i386) |
|---|---|---|---|
| `_kern_loader_abort` | `0x967c` external | `0x4768` external | __TEXT,__text |
| `_kern_loader_load_server` | `0x9750` external | `0x4878` external | __TEXT,__text |
| `_kern_loader_unload_server` | `0x9858` external | `0x49a0` external | __TEXT,__text |
| `_kern_loader_add_server` | `0x9978` external | `0x4ad8` external | __TEXT,__text |
| `_kern_loader_delete_server` | `0x9a98` external | `0x4c10` external | __TEXT,__text |
| `_kern_loader_server_task_port` | `0x9bb8` external | `0x4d48` external | __TEXT,__text |
| `_kern_loader_server_com_port` | `0x9cfc` external | `0x4eb4` external | __TEXT,__text |
| `_kern_loader_status_port` | `0x9e40` external | `0x5020` external | __TEXT,__text |
| `_kern_loader_ping` | `0x9e94` external | `0x5094` external | __TEXT,__text |
| `_kern_loader_log_level` | `0x9ef8` external | `0x5118` external | __TEXT,__text |
| `_kern_loader_get_log` | `0x9fcc` external | `0x5228` external | __TEXT,__text |
| `_kern_loader_server_list` | `0xa0a0` external | `0x5338` external | __TEXT,__text |
| `_kern_loader_server_info_old` | `0xa184` external | `0x5478` external | __TEXT,__text |
| `_kern_loader_server_info` | `0xa448` external | `0x5770` external | __TEXT,__text |
| `_kern_loader_look_up` | `0xa70c` external | `0x5a68` external | __TEXT,__text |
| `_kern_loader_reply_handler` | `0xa888` external | `0x5cdc` external | __TEXT,__text |
| `error_message` | `0xa97a` local | `0x5e18` local | __TEXT,__cstring |

`error_message` is a local label inside libkernload's `__cstring`, not a function. `_kern_loader_reply` (in the owned table) is `kl_com`'s reply-handler table.

## libDriver

### ppc: imported from `/usr/lib/libDriver.A.dylib`

`.objc_class_name_IOConfigTable`, `.objc_class_name_IODevice`, `.objc_class_name_IODeviceMaster`, `.objc_class_name_NXConditionLock`, `_IOLog`, `__IOProbeDriver`, `__IOUnloadDriver`

### i386: carried statically (the accept set in the spec's section 3)

126 functions in `__text` from `0x51d4` up to `_kern_loader_abort` at `0x967c`, in link order `IOConfigTable`, `IODevice`, `IODeviceMaster`, `driverServerUser`, `NXConditionLock`, `generalFuncs`, `NXLock`, then `__IOCopyMemory`:

| Address | Symbol | Binding |
|---|---|---|
| `0x51d4` | `-[IOConfigTable free]` | local |
| `0x525c` | `+[IOConfigTable newFromSystemConfig]` | local |
| `0x53b4` | `+[IOConfigTable newForDriver:unit:]` | local |
| `0x5484` | `+[IOConfigTable newDefaultTableForDriver:]` | local |
| `0x5550` | `+[IOConfigTable tablesForInstalledDrivers]` | local |
| `0x5620` | `+[IOConfigTable tablesForBootDrivers]` | local |
| `0x5828` | `-[IOConfigTable driverBundle]` | local |
| `0x5878` | `-[IOConfigTable valueForStringKey:]` | local |
| `0x58a0` | `+[IOConfigTable(Private) openForFile:]` | local |
| `0x594c` | `_parseDriverList` | local |
| `0x59fc` | `+[IODevice initialize]` | local |
| `0x5abc` | `+[IODevice probe:]` | local |
| `0x5ac8` | `+[IODevice deviceStyle]` | local |
| `0x5ad4` | `+[IODevice requiredProtocols]` | local |
| `0x5ae0` | `+[IODevice registerClass:]` | local |
| `0x5b90` | `+[IODevice unregisterClass:]` | local |
| `0x5c18` | `-[IODevice init]` | local |
| `0x5c4c` | `-[IODevice initFromDeviceDescription:]` | local |
| `0x5cb0` | `-[IODevice deviceDescription]` | local |
| `0x5cf8` | `-[IODevice setDeviceDescription:]` | local |
| `0x5d58` | `-[IODevice getDevicePath:maxLength:]` | local |
| `0x5db4` | `-[IODevice matchDevicePath:]` | local |
| `0x5e0c` | `-[IODevice free]` | local |
| `0x5e54` | `-[IODevice registerDevice]` | local |
| `0x5f40` | `-[IODevice unregisterDevice]` | local |
| `0x5fe0` | `-[IODevice name]` | local |
| `0x5ff0` | `-[IODevice setName:]` | local |
| `0x6034` | `-[IODevice deviceKind]` | local |
| `0x6044` | `-[IODevice setDeviceKind:]` | local |
| `0x6090` | `-[IODevice location]` | local |
| `0x60a0` | `-[IODevice setLocation:]` | local |
| `0x60f0` | `-[IODevice unit]` | local |
| `0x6100` | `-[IODevice setUnit:]` | local |
| `0x6110` | `+[IODevice blockMajor]` | local |
| `0x613c` | `+[IODevice setBlockMajor:]` | local |
| `0x6160` | `+[IODevice characterMajor]` | local |
| `0x618c` | `+[IODevice setCharacterMajor:]` | local |
| `0x61b0` | `+[IODevice addToCdevswFromDescription:open:close:read:write:ioctl:stop:reset:select:mmap:getc:putc:]` | local |
| `0x61bc` | `+[IODevice addToBdevswFromDescription:open:close:strategy:ioctl:dump:psize:isTape:]` | local |
| `0x61c8` | `+[IODevice removeFromCdevsw]` | local |
| `0x61d4` | `+[IODevice removeFromBdevsw]` | local |
| `0x61e0` | `+[IODevice driverKitVersion]` | local |
| `0x61ec` | `+[IODevice driverKitVersionForDriverNamed:]` | local |
| `0x6308` | `-[IODevice getIntValues:forParameter:count:]` | local |
| `0x63f4` | `-[IODevice getCharValues:forParameter:count:]` | local |
| `0x64d4` | `-[IODevice setIntValues:forParameter:count:]` | local |
| `0x64e0` | `-[IODevice setCharValues:forParameter:count:]` | local |
| `0x64ec` | `-[IODevice createMachPort:]` | local |
| `0x6504` | `-[IODevice stringFromReturn:]` | local |
| `0x652c` | `+[IODevice stringFromReturn:]` | local |
| `0x6548` | `-[IODevice errnoFromReturn:]` | local |
| `0x6678` | `+[IODevice(GlobalParameter) lookupByObjectNumber:deviceKind:deviceName:]` | local |
| `0x6718` | `+[IODevice(GlobalParameter) lookupByObjectNumber:instance:]` | local |
| `0x676c` | `+[IODevice(GlobalParameter) lookupByDeviceName:objectNumber:deviceKind:]` | local |
| `0x67f0` | `+[IODevice(GlobalParameter) getIntValues:forParameter:objectNumber:count:]` | local |
| `0x686c` | `+[IODevice(GlobalParameter) getCharValues:forParameter:objectNumber:count:]` | local |
| `0x68e8` | `+[IODevice(GlobalParameter) createMachPort:objectNumber:]` | local |
| `0x695c` | `+[IODevice(GlobalParameter) setIntValues:forParameter:objectNumber:count:]` | local |
| `0x69d8` | `+[IODevice(GlobalParameter) setCharValues:forParameter:objectNumber:count:]` | local |
| `0x6a54` | `+[IODevice(GlobalParameter) callDeviceMethod:inputParams:inputCount:outputParams:outputCount:privileged:objectNumber:]` | local |
| `0x6b50` | `_objectNumToId` | local |
| `0x6ba8` | `_deviceNameToId` | local |
| `0x6c1c` | `_getObjectListEntry` | local |
| `0x6c4c` | `_getClassListEntryForId` | local |
| `0x6cd4` | `_getClassListEntry` | local |
| `0x6d24` | `+[IODeviceMaster new]` | local |
| `0x6d6c` | `-[IODeviceMaster free]` | local |
| `0x6d78` | `-[IODeviceMaster lookUpByObjectNumber:deviceKind:deviceName:]` | local |
| `0x6d98` | `-[IODeviceMaster lookUpByDeviceName:objectNumber:deviceKind:]` | local |
| `0x6db8` | `-[IODeviceMaster getIntValues:forParameter:objectNumber:count:]` | local |
| `0x6de0` | `-[IODeviceMaster getCharValues:forParameter:objectNumber:count:]` | local |
| `0x6e08` | `-[IODeviceMaster setIntValues:forParameter:objectNumber:count:]` | local |
| `0x6e2c` | `-[IODeviceMaster setCharValues:forParameter:objectNumber:count:]` | local |
| `0x6e50` | `-[IODeviceMaster createMachPort:objectNumber:]` | local |
| `0x6e6c` | `__IOLookupByObjectNumber` | external |
| `0x6fd8` | `__IOLookupByDeviceName` | external |
| `0x7104` | `__IOGetIntValues` | external |
| `0x7328` | `__IOGetCharValues` | external |
| `0x7548` | `__IOSetIntValues` | external |
| `0x76e8` | `__IOSetCharValues` | external |
| `0x7880` | `__IOGetEISADeviceConfig` | external |
| `0x7bd4` | `__IOMapEISADevicePorts` | external |
| `0x7c90` | `__IOUnMapEISADevicePorts` | external |
| `0x7d4c` | `__IOMapEISADeviceMemory` | external |
| `0x7e84` | `__IOProbeDriver` | external |
| `0x7fb4` | `__IOGetSystemConfig` | external |
| `0x8134` | `__IOUnloadDriver` | external |
| `0x8264` | `__IOGetDriverConfig` | external |
| `0x83e4` | `__PMSetPowerState` | external |
| `0x84b0` | `__PMGetPowerEvent` | external |
| `0x8580` | `__PMGetPowerStatus` | external |
| `0x8664` | `__PMSetPowerManagement` | external |
| `0x8730` | `__PMRestoreDefaults` | external |
| `0x87d8` | `__IOCallDeviceMethod` | external |
| `0x8a8c` | `__IOCreateMachPort` | external |
| `0x8b6c` | `-[NXConditionLock init]` | local |
| `0x8bd8` | `-[NXConditionLock initWith:]` | local |
| `0x8c08` | `-[NXConditionLock condition]` | local |
| `0x8c18` | `-[NXConditionLock free]` | local |
| `0x8c7c` | `-[NXConditionLock lock]` | local |
| `0x8cd4` | `-[NXConditionLock unlock]` | local |
| `0x8d1c` | `-[NXConditionLock lockWhen:]` | local |
| `0x8d78` | `-[NXConditionLock unlockWith:]` | local |
| `0x8dc8` | `_IOMalloc` | external |
| `0x8dd8` | `_IOFree` | external |
| `0x8de8` | `_IOCopyMemory` | external |
| `0x8e04` | `_IOForkThread` | external |
| `0x8e18` | `_IOSuspendThread` | external |
| `0x8e2c` | `_IOResumeThread` | external |
| `0x8e40` | `_IOExitThread` | external |
| `0x8e50` | `_IOSleep` | external |
| `0x8e84` | `_IODelay` | external |
| `0x8ecc` | `_IOScheduleFunc` | external |
| `0x9050` | `_calloutThread` | local |
| `0x9150` | `_IOUnscheduleFunc` | external |
| `0x920c` | `_IOGetTimestamp` | external |
| `0x92a4` | `_IOLog` | external |
| `0x92e4` | `_IOPanic` | external |
| `0x9308` | `_IOFindNameForValue` | external |
| `0x9354` | `_IOFindValueForName` | external |
| `0x93a4` | `_IOInitGeneralFuncs` | external |
| `0x9420` | `-[NXLock init]` | local |
| `0x9480` | `-[NXLock free]` | local |
| `0x94e4` | `-[NXLock lock]` | local |
| `0x9538` | `-[NXLock unlock]` | local |
| `0x9580` | `__IOCopyMemory` | external |

Data symbols from the same objects (the `__TEXT,__const` entries are `driverServerUser`'s MIG type checks):

`_objectNumberType.80`, `_RetCodeCheck.81`, `_deviceKindCheck.82`, `_deviceNameCheck.83`, `_deviceNameType.86`, `_RetCodeCheck.87`, `_objectNumberCheck.88`, `_deviceKindCheck.89`, `_objectNumberType.92`, `_parameterNameType.93`, `_maxCountType.94`, `_RetCodeCheck.95`, `_objectNumberType.98`, `_parameterNameType.99`, `_maxCountType.100`, `_RetCodeCheck.101`, `_objectNumberType.104`, `_parameterNameType.105`, `_parameterArrayType.106`, `_RetCodeCheck.107`, `_objectNumberType.110`, `_parameterNameType.111`, `_parameterArrayType.112`, `_RetCodeCheck.113`, `_RetCodeCheck.116`, `_threadType.119`, `_RetCodeCheck.120`, `_threadType.123`, `_RetCodeCheck.124`, `_target_taskType.127`, `_physType.128`, `_lengthType.129`, `_addrType.130`, `_anywhereType.131`, `_cacheType.132`, `_RetCodeCheck.133`, `_addrCheck.134`, `_configTableType.137`, `_RetCodeCheck.138`, `_maxDataSizeType.141`, `_RetCodeCheck.142`, `_configTableType.145`, `_RetCodeCheck.146`, `_driverNumType.149`, `_maxDataSizeType.150`, `_RetCodeCheck.151`, `_deviceType.154`, `_stateType.155`, `_RetCodeCheck.156`, `_RetCodeCheck.159`, `_eventCheck.160`, `_RetCodeCheck.163`, `_statusCheck.164`, `_deviceType.167`, `_stateType.168`, `_RetCodeCheck.169`, `_RetCodeCheck.172`, `_objectNumberType.175`, `_parameterNameType.176`, `_inputParamsType.177`, `_maxOutputType.178`, `_RetCodeCheck.179`, `_maxOutputCheck.180`, `_objectNumberType.183`, `_RetCodeCheck.184`, `_machPortCheck.185`, `_IOReturn_values`, `_IODeviceInitFlag`, `_thisTasksId`, `_globalObjectCounter`, `_objectList`, `_objectListLock`, `_classCounter`, `_classList`, `_classListLock`, `_calloutChain`, `_calloutLock`, `_sleepPort`, `_noValue`

## Facts the source must reproduce

- `securityCheck` and `securityCheckDir` have no callers on either slice
  (checked with IDA cross-references). Apple shipped them as dead code.
- `main`'s `D`/`d` case sets `load` by comparing the option letter with
  `'u'`, on both slices, although the switch has no `'u'` case.
- `__cstring` holds `prePostExec: execString %s\n` and `   cwd %s\n`
  between `%s/%s Instance=%d` and `Detached`, but no decompiled code
  references them.
- ppc has a common `_catch_exception_raise`; i386 does not.
- Bindings: `main` and the `kl_com_add`, `kl_com_delete`, `kl_com_load`,
  `kl_com_unload`, `kl_com_get_state` and `kl_com_wait` entry points are
  global; every other owned function is static. `verbose`, `interactive`,
  `kl_init_flag` and `kern_loader_reply` are initialized globals in
  `__data`; `instruction` is an initialized static; `progName`, `kl_port`,
  `kernel_task` and `reply_port` are common (uninitialized) globals;
  `ping_lock` is a static in `__bss`.
