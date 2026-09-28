# driverLoader divergences

References: DR2 i386 `e005522ec2e4f107b8071a573ccda9208d49e64e2114d08b8868ee956a0e98b7`
(70132 bytes) and MOSXS 1.2v3 ppc `cd8dd33035aae133ce4ab1d6a203807cbceabc3d5d300326ff105ad33d9d3e14`
(40776 bytes). See nlist.md.

## Accepted

### libDriver is linked dynamically (i386)

DR2's driverLoader carries libDriver's user-mode objects statically
(IOConfigTable, IODevice, IODeviceMaster, driverServerUser,
NXConditionLock, generalFuncs, NXLock). MOSXS 1.2v3 links
`/usr/lib/libDriver.A.dylib` instead, and this build follows 1.2 on both
slices. All 126 i386 reference functions from those objects are
`intentional-mismatch` in `i386/ledger.json`. `parity_check.py`'s i386
`missing_strings` and `missing_symbols` list exactly those objects' items:

missing_strings (57):

- `%d(d) (UNDEFINED)`
- `%s`
- `Bad IPC Message ID`
- `Can't Acquire Desired Lock`
- `Can't Wire Physical Memory`
- `DMA ALignment error`
- `DMA failure`
- `Device Busy`
- `Device Not Open`
- `Device Not Readable`
- `Device Not Writeable`
- `Device Offline`
- `Device Port Already Exists`
- `Device Read Locked`
- `Device Write Locked`
- `Device(s) still open`
- `Device/Channel not attached`
- `Exclusive Access Device`
- `I/O Timeout`
- `I/O error`
- `INVALID STATUS (Internal Error)`
- `IOBlockMajor`
- `IOCharacterMajor`
- `IOClassName`
- `IOConfigTable: _IOGetDriverConfig: %s
`
- `IOConfigTable: _IOGetSystemConfig: %s
`
- `IOConfigTable: readFromStream returned nil
`
- `IODevice`
- `IODeviceKind`
- `IODeviceName`
- `IOInitGeneralFunc: port_allocate error
`
- `IOUnit`
- `Internal Driver error`
- `Invalid Argument`
- `Mach IPC Failure`
- `Media error`
- `Memory Allocation error`
- `No Address Space for Mapping`
- `No DMA Channels Available`
- `No DMA Frames Enqueued`
- `No Interrupt Port Attached`
- `No Such Device`
- `Not Ready`
- `Privilege Violation`
- `Registering: %s
`
- `Registering: %s at %s
`
- `Resource Shortage`
- `Success`
- `Unregistering Device: %s
`
- `Unsupported Function`
- `Version`
- `Virtual Memory error`
- `driverKitVersionFor`
- `installedDrivers: no drivers found
`
- `rld failure`
- `tablesForInstalledDrivers: no system config file found
`
- `waiting for debugger connection...`

missing_symbols (126):

- `+[IOConfigTable newDefaultTableForDriver:]`
- `+[IOConfigTable newForDriver:unit:]`
- `+[IOConfigTable newFromSystemConfig]`
- `+[IOConfigTable tablesForBootDrivers]`
- `+[IOConfigTable tablesForInstalledDrivers]`
- `+[IOConfigTable(Private) openForFile:]`
- `+[IODevice addToBdevswFromDescription:open:close:strategy:ioctl:dump:psize:isTape:]`
- `+[IODevice addToCdevswFromDescription:open:close:read:write:ioctl:stop:reset:select:mmap:getc:putc:]`
- `+[IODevice blockMajor]`
- `+[IODevice characterMajor]`
- `+[IODevice deviceStyle]`
- `+[IODevice driverKitVersionForDriverNamed:]`
- `+[IODevice driverKitVersion]`
- `+[IODevice initialize]`
- `+[IODevice probe:]`
- `+[IODevice registerClass:]`
- `+[IODevice removeFromBdevsw]`
- `+[IODevice removeFromCdevsw]`
- `+[IODevice requiredProtocols]`
- `+[IODevice setBlockMajor:]`
- `+[IODevice setCharacterMajor:]`
- `+[IODevice stringFromReturn:]`
- `+[IODevice unregisterClass:]`
- `+[IODevice(GlobalParameter) callDeviceMethod:inputParams:inputCount:outputParams:outputCount:privileged:objectNumber:]`
- `+[IODevice(GlobalParameter) createMachPort:objectNumber:]`
- `+[IODevice(GlobalParameter) getCharValues:forParameter:objectNumber:count:]`
- `+[IODevice(GlobalParameter) getIntValues:forParameter:objectNumber:count:]`
- `+[IODevice(GlobalParameter) lookupByDeviceName:objectNumber:deviceKind:]`
- `+[IODevice(GlobalParameter) lookupByObjectNumber:deviceKind:deviceName:]`
- `+[IODevice(GlobalParameter) lookupByObjectNumber:instance:]`
- `+[IODevice(GlobalParameter) setCharValues:forParameter:objectNumber:count:]`
- `+[IODevice(GlobalParameter) setIntValues:forParameter:objectNumber:count:]`
- `+[IODeviceMaster new]`
- `-[IOConfigTable driverBundle]`
- `-[IOConfigTable free]`
- `-[IOConfigTable valueForStringKey:]`
- `-[IODevice createMachPort:]`
- `-[IODevice deviceDescription]`
- `-[IODevice deviceKind]`
- `-[IODevice errnoFromReturn:]`
- `-[IODevice free]`
- `-[IODevice getCharValues:forParameter:count:]`
- `-[IODevice getDevicePath:maxLength:]`
- `-[IODevice getIntValues:forParameter:count:]`
- `-[IODevice initFromDeviceDescription:]`
- `-[IODevice init]`
- `-[IODevice location]`
- `-[IODevice matchDevicePath:]`
- `-[IODevice name]`
- `-[IODevice registerDevice]`
- `-[IODevice setCharValues:forParameter:count:]`
- `-[IODevice setDeviceDescription:]`
- `-[IODevice setDeviceKind:]`
- `-[IODevice setIntValues:forParameter:count:]`
- `-[IODevice setLocation:]`
- `-[IODevice setName:]`
- `-[IODevice setUnit:]`
- `-[IODevice stringFromReturn:]`
- `-[IODevice unit]`
- `-[IODevice unregisterDevice]`
- `-[IODeviceMaster createMachPort:objectNumber:]`
- `-[IODeviceMaster free]`
- `-[IODeviceMaster getCharValues:forParameter:objectNumber:count:]`
- `-[IODeviceMaster getIntValues:forParameter:objectNumber:count:]`
- `-[IODeviceMaster lookUpByDeviceName:objectNumber:deviceKind:]`
- `-[IODeviceMaster lookUpByObjectNumber:deviceKind:deviceName:]`
- `-[IODeviceMaster setCharValues:forParameter:objectNumber:count:]`
- `-[IODeviceMaster setIntValues:forParameter:objectNumber:count:]`
- `-[NXConditionLock condition]`
- `-[NXConditionLock free]`
- `-[NXConditionLock initWith:]`
- `-[NXConditionLock init]`
- `-[NXConditionLock lockWhen:]`
- `-[NXConditionLock lock]`
- `-[NXConditionLock unlockWith:]`
- `-[NXConditionLock unlock]`
- `-[NXLock free]`
- `-[NXLock init]`
- `-[NXLock lock]`
- `-[NXLock unlock]`
- `_IOCopyMemory`
- `_IODelay`
- `_IOExitThread`
- `_IOFindNameForValue`
- `_IOFindValueForName`
- `_IOForkThread`
- `_IOFree`
- `_IOGetTimestamp`
- `_IOInitGeneralFuncs`
- `_IOLog`
- `_IOMalloc`
- `_IOPanic`
- `_IOResumeThread`
- `_IOScheduleFunc`
- `_IOSleep`
- `_IOSuspendThread`
- `_IOUnscheduleFunc`
- `__IOCallDeviceMethod`
- `__IOCopyMemory`
- `__IOCreateMachPort`
- `__IOGetCharValues`
- `__IOGetDriverConfig`
- `__IOGetEISADeviceConfig`
- `__IOGetIntValues`
- `__IOGetSystemConfig`
- `__IOLookupByDeviceName`
- `__IOLookupByObjectNumber`
- `__IOMapEISADeviceMemory`
- `__IOMapEISADevicePorts`
- `__IOProbeDriver`
- `__IOSetCharValues`
- `__IOSetIntValues`
- `__IOUnMapEISADevicePorts`
- `__IOUnloadDriver`
- `__PMGetPowerEvent`
- `__PMGetPowerStatus`
- `__PMRestoreDefaults`
- `__PMSetPowerManagement`
- `__PMSetPowerState`
- `_calloutThread`
- `_deviceNameToId`
- `_getClassListEntry`
- `_getClassListEntryForId`
- `_getObjectListEntry`
- `_objectNumToId`
- `_parseDriverList`

### Compiler-shaped leftovers (reviewer Pat Raynor)

Equality below is `raw_equal`, `masked_equal`, or `tools/binrecon/pic_equal.py`
(identical instructions once PIC-base terms and layout-only addresses are
normalized). Every other owned function is `pic_equal` on both slices.

#### `_prePostExec` (i386 and ppc)

Every instruction matches except where the one shared `return 0` block sits:
Apple's compilers keep the first copy (after the Default-table lookup) and
jump the later `return 0`s to it; ours keeps the last copy (after the
Execute question). Tried: a nested nil-table form, an `else` return, `-O2`.

```text
_prePostExec
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 0C68h                          sub esp, 0C68h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop esi                                 pop esi
  mov ebx, [ebp+arg_8]                    mov ebx, [ebp+arg_8]
  mov edx, [ebp+arg_4]                    mov edx, [ebp+arg_4]
  push edx                                push edx
  mov edx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+96B3h]                    mov edx, [edx+497Fh]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+973Bh]                    mov edx, [edx+499Fh]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov [ebp+var_C68], eax                  mov [ebp+var_C68], eax
  add esp, 10h                            add esp, 10h
  test eax, eax                           test eax, eax
* jnz loc_4A8C                            jnz loc_56F7
  cmp [ebp+arg_4], 0                      cmp [ebp+arg_4], 0
* jnz loc_4A83                            jnz loc_5783
  mov edx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+96B7h]                    mov edx, [edx+4983h]
  push edx                                push edx
  mov edx, esi                            mov edx, esi
* mov edx, [edx+973Bh]                    mov edx, [edx+499Fh]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov [ebp+var_C68], eax                  mov [ebp+var_C68], eax
  add esp, 0Ch                            add esp, 0Ch
  test eax, eax                           test eax, eax
* jnz loc_4A8C                            jz loc_5783
* xor eax, eax
* jmp loc_4B8B
  test ebx, ebx                           test ebx, ebx
* jnz loc_4A98                            jnz loc_5704
* lea eax, (aPreLoad - 4A25h)[esi]        lea eax, (aPreLoad - 5691h)[esi]
* jmp loc_4A9E                            jmp loc_570A
* lea eax, (aPostLoad - 4A25h)[esi]       lea eax, (aPostLoad - 5691h)[esi]
  push eax                                push eax
  mov edx, esi                            mov edx, esi
* mov edx, [edx+96A7h]                    mov edx, [edx+4973h]
  push edx                                push edx
  mov edx, [ebp+var_C68]                  mov edx, [ebp+var_C68]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov edi, eax                            mov edi, eax
  add esp, 0Ch                            add esp, 0Ch
  test edi, edi                           test edi, edi
* jz loc_4A83                             jz loc_5783
  cmp byte ptr [edi], 2Fh                 cmp byte ptr [edi], 2Fh
* jz loc_4AD6                             jz loc_5742
* lea eax, (asc_AFC3 - 4A25h)[esi]        lea eax, (asc_778B - 5691h)[esi]
  push eax                                push eax
  push edi                                push edi
  call _strstr                            call _strstr
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jz loc_4AE0                             jz loc_574C
  mov ebx, 3                              mov ebx, 3
* jmp loc_4B76                            jmp loc_57E3
  push edi                                push edi
  test ebx, ebx                           test ebx, ebx
* jnz loc_4AF0                            jnz loc_575C
* lea eax, (aPreLoad - 4A25h)[esi]        lea eax, (aPreLoad - 5691h)[esi]
* jmp loc_4AF6                            jmp loc_5762
* lea eax, (aPostLoad - 4A25h)[esi]       lea eax, (aPostLoad - 5691h)[esi]
  push eax                                push eax
* lea eax, (aExecuteSFileS - 4A25h)[esi]  lea eax, (aExecuteSFileS - 5691h)[esi]
  push eax                                push eax
  lea ebx, [ebp+var_C64]                  lea ebx, [ebp+var_C64]
  push ebx                                push ebx
  call _sprintf                           call _sprintf
  push ebx                                push ebx
  call _inquire                           call _inquire
  add esp, 14h                            add esp, 14h
  test al, al                             test al, al
* jz loc_4A83                             jnz loc_5788
* lea eax, (aConfig - 4A25h)[esi]         xor eax, eax
*                                         jmp loc_57F8
*                                         lea eax, (aConfig - 5691h)[esi]
  push eax                                push eax
  mov edx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
  push edx                                push edx
* lea eax, (aUsrDevices - 4A25h)[esi]     lea eax, (aUsrDevices - 5691h)[esi]
  push eax                                push eax
* lea eax, (aSSS - 4A25h)[esi]            lea eax, (aSSS - 5691h)[esi]
  push eax                                push eax
  lea ebx, [ebp+var_400]                  lea ebx, [ebp+var_400]
  push ebx                                push ebx
  call _sprintf                           call _sprintf
  push ebx                                push ebx
  call _chdir                             call _chdir
  mov edx, [ebp+arg_4]                    mov edx, [ebp+arg_4]
  push edx                                push edx
  push edi                                push edi
  push ebx                                push ebx
* lea eax, (aSSInstanceD - 4A25h)[esi]    lea eax, (aSSInstanceD - 5691h)[esi]
  push eax                                push eax
  lea ebx, [ebp+var_C00]                  lea ebx, [ebp+var_C00]
  push ebx                                push ebx
  call _sprintf                           call _sprintf
  add esp, 2Ch                            add esp, 2Ch
  push ebx                                push ebx
  call _system                            call _system
  add esp, 4                              add esp, 4
  xor ebx, ebx                            xor ebx, ebx
  test eax, eax                           test eax, eax
* jz loc_4B76                             jz loc_57E3
  mov ebx, 2                              mov ebx, 2
* mov esi, ds:(off_E0E0 - 4A25h)[esi]     mov esi, ds:(paFree - 5691h)[esi]
  push esi                                push esi
  mov edx, [ebp+var_C68]                  mov edx, [ebp+var_C68]
  push edx                                push edx
  call _objc_msgSend                      call _objc_msgSend
  mov eax, ebx                            mov eax, ebx
  lea esp, [ebp-0C74h]                    lea esp, [ebp-0C74h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

```text
_prePostExec
  status=different raw_equal=False masked_equal=False
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  mflr r0, lr                             mflr r0, lr
  stmw r26, var_18(r1)                    stmw r26, var_18(r1)
  stw r0, sender_lr(r1)                   stw r0, sender_lr(r1)
  stwu r1, sender_sp(r1)                  stwu r1, sender_sp(r1)
* bcl 20, 4*cr7+so, loc_3E18              bcl 20, 4*cr7+so, loc_3BBC
  mflr r31, lr                            mflr r31, lr
  mr r29, r3                              mr r29, r3
  mr r27, r4                              mr r27, r4
  mr r26, r5                              mr r26, r5
* addis r3, r31, (paIoconfigtable - loc_3E18)@ha  addis r3, r31, (paIoconfigtable - loc_3BBC)@ha
* addis r4, r31, (off_8010 - loc_3E18)@ha  addis r4, r31, (paNewfordriverUn - loc_3BBC)@ha
* lwz r3, (paIoconfigtable - loc_3E18)@l(r3)  lwz r3, (paIoconfigtable - loc_3BBC)@l(r3)
* lwz r4, (off_8010 - loc_3E18)@l(r4)     lwz r4, (paNewfordriverUn - loc_3BBC)@l(r4)
  mr r5, r29                              mr r5, r29
  mr r6, r27                              mr r6, r27
  bl _objc_msgSend                        bl _objc_msgSend
  mr. r28, r3                             mr. r28, r3
* bne cr0, loc_3E7C                       bne cr0, loc_3C18
  cmpwi cr1, r27, 0                       cmpwi cr1, r27, 0
* bne cr1, loc_3E74                       bne cr1, loc_3CC0
* addis r3, r31, (paIoconfigtable - loc_3E18)@ha  addis r3, r31, (paIoconfigtable - loc_3BBC)@ha
* addis r4, r31, (off_8014 - loc_3E18)@ha  addis r4, r31, (paNewdefaulttabl - loc_3BBC)@ha
* lwz r3, (paIoconfigtable - loc_3E18)@l(r3)  lwz r3, (paIoconfigtable - loc_3BBC)@l(r3)
* lwz r4, (off_8014 - loc_3E18)@l(r4)     lwz r4, (paNewdefaulttabl - loc_3BBC)@l(r4)
  mr r5, r29                              mr r5, r29
  bl _objc_msgSend                        bl _objc_msgSend
  mr. r28, r3                             mr. r28, r3
* bne cr0, loc_3E7C                       beq cr0, loc_3CC0
* li r3, 0                                mr r3, r28
* b loc_3F98                              addis r9, r31, (paValueforstring - loc_3BBC)@ha
*                                         addi r4, r9, (paValueforstring - loc_3BBC)@l
  cmpwi cr1, r26, 0                       cmpwi cr1, r26, 0
* bne cr1, loc_3E90                       bne cr1, loc_3C38
* addis r9, r31, (aPreLoad - loc_3E18)@ha  addis r9, r31, (aPreLoad - loc_3BBC)@ha
* addi r5, r9, (aPreLoad - loc_3E18)@l    addi r5, r9, (aPreLoad - loc_3BBC)@l
* b loc_3E98                              b loc_3C40
* addis r9, r31, (aPostLoad - loc_3E18)@ha  addis r9, r31, (aPostLoad - loc_3BBC)@ha
* addi r5, r9, (aPostLoad - loc_3E18)@l   addi r5, r9, (aPostLoad - loc_3BBC)@l
* addis r4, r31, (off_8004 - loc_3E18)@ha  lwz r4, (paValueforstring - 0x8004)(r4)
* mr r3, r28
* lwz r4, (off_8004 - loc_3E18)@l(r4)
  bl _objc_msgSend                        bl _objc_msgSend
  mr. r30, r3                             mr. r30, r3
* beq- cr0, loc_3E74                      beq cr0, loc_3CC0
  lbz r0, 0(r30)                          lbz r0, 0(r30)
  cmpwi cr1, r0, 0x2F                     cmpwi cr1, r0, 0x2F
* beq cr1, loc_3ED4                       beq cr1, loc_3C74
  mr r3, r30                              mr r3, r30
* addis r4, r31, (asc_64B0 - loc_3E18)@ha  addis r4, r31, (asc_64B0 - loc_3BBC)@ha
* addi r4, r4, (asc_64B0 - loc_3E18)@l    addi r4, r4, (asc_64B0 - loc_3BBC)@l
  bl _strstr                              bl _strstr
  cmpwi cr1, r3, 0                        cmpwi cr1, r3, 0
* beq cr1, loc_3EDC                       beq cr1, loc_3C7C
  li r29, 3                               li r29, 3
* b loc_3F84                              b loc_3D2C
  addi r3, r1, 0xCC0+var_88               addi r3, r1, 0xCC0+var_88
  cmpwi cr1, r26, 0                       cmpwi cr1, r26, 0
* bne cr1, loc_3EF4                       bne cr1, loc_3C94
* addis r9, r31, (aPreLoad - loc_3E18)@ha  addis r9, r31, (aPreLoad - loc_3BBC)@ha
* addi r5, r9, (aPreLoad - loc_3E18)@l    addi r5, r9, (aPreLoad - loc_3BBC)@l
* b loc_3EFC                              b loc_3C9C
* addis r9, r31, (aPostLoad - loc_3E18)@ha  addis r9, r31, (aPostLoad - loc_3BBC)@ha
* addi r5, r9, (aPostLoad - loc_3E18)@l   addi r5, r9, (aPostLoad - loc_3BBC)@l
* addis r4, r31, (aExecuteSFileS - loc_3E18)@ha  addis r4, r31, (aExecuteSFileS - loc_3BBC)@ha
* addi r4, r4, (aExecuteSFileS - loc_3E18)@l  addi r4, r4, (aExecuteSFileS - loc_3BBC)@l
  mr r6, r30                              mr r6, r30
  bl _sprintf                             bl _sprintf
  addi r3, r1, 0xCC0+var_88               addi r3, r1, 0xCC0+var_88
  bl _inquire                             bl _inquire
  extsb r3, r3                            extsb r3, r3
  cmpwi cr1, r3, 0                        cmpwi cr1, r3, 0
* beq- cr1, loc_3E74                      bne cr1, loc_3CC8
*                                         li r3, 0
*                                         b loc_3D40
  addi r3, r1, 0xCC0+var_C88              addi r3, r1, 0xCC0+var_C88
* addis r4, r31, (aSSS - loc_3E18)@ha     addis r4, r31, (aSSS - loc_3BBC)@ha
* addi r4, r4, (aSSS - loc_3E18)@l        addi r4, r4, (aSSS - loc_3BBC)@l
* addis r5, r31, (aUsrDevices - loc_3E18)@ha  addis r5, r31, (aUsrDevices - loc_3BBC)@ha
* addi r5, r5, (aUsrDevices - loc_3E18)@l  addi r5, r5, (aUsrDevices - loc_3BBC)@l
  mr r6, r29                              mr r6, r29
* addis r7, r31, (aConfig - loc_3E18)@ha  addis r7, r31, (aConfig - loc_3BBC)@ha
* addi r7, r7, (aConfig - loc_3E18)@l     addi r7, r7, (aConfig - loc_3BBC)@l
  bl _sprintf                             bl _sprintf
  addi r3, r1, 0xCC0+var_C88              addi r3, r1, 0xCC0+var_C88
  bl _chdir                               bl _chdir
  addi r29, r1, 0xCC0+var_888             addi r29, r1, 0xCC0+var_888
  mr r3, r29                              mr r3, r29
* addis r4, r31, (aSSInstanceD - loc_3E18)@ha  addis r4, r31, (aSSInstanceD - loc_3BBC)@ha
* addi r4, r4, (aSSInstanceD - loc_3E18)@l  addi r4, r4, (aSSInstanceD - loc_3BBC)@l
  addi r5, r1, 0xCC0+var_C88              addi r5, r1, 0xCC0+var_C88
  mr r6, r30                              mr r6, r30
  mr r7, r27                              mr r7, r27
  bl _sprintf                             bl _sprintf
  mr r3, r29                              mr r3, r29
  bl _system                              bl _system
  srawi r0, r3, 0x1F                      srawi r0, r3, 0x1F
  xor r3, r0, r3                          xor r3, r0, r3
  subf r3, r3, r0                         subf r3, r3, r0
  rlwinm r29, r3, 2,30,30                 rlwinm r29, r3, 2,30,30
* addis r4, r31, (off_8018 - loc_3E18)@ha  addis r4, r31, (paFree - loc_3BBC)@ha
  mr r3, r28                              mr r3, r28
* lwz r4, (off_8018 - loc_3E18)@l(r4)     lwz r4, (paFree - loc_3BBC)@l(r4)
  bl _objc_msgSend                        bl _objc_msgSend
  mr r3, r29                              mr r3, r29
  addi r1, r1, 0xCC0                      addi r1, r1, 0xCC0
  lwz r0, sender_lr(r1)                   lwz r0, sender_lr(r1)
  mtlr lr, r0                             mtlr lr, r0
  lmw r26, var_18(r1)                     lmw r26, var_18(r1)
  blr lr                                  blr lr
```

#### `_processDriverList` (i386 only; ppc is `pic_equal`)

DR2's compiler loads `list` after the verbose `printf` and emits no
alignment NOPs before the loop; ours loads it first. Scheduling only.

```text
_processDriverList
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 6Ch                            sub esp, 6Ch
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
  pop eax                                 pop eax
*                                         mov ebx, [ebp+arg_0]
  mov cl, [ebp+arg_4]                     mov cl, [ebp+arg_4]
  mov [ebp+var_68], cl                    mov [ebp+var_68], cl
  mov cl, [ebp+arg_8]                     mov cl, [ebp+arg_8]
  mov [ebp+var_6C], cl                    mov [ebp+var_6C], cl
* cmp ds:(_verbose - 3E29h)[eax], 0       cmp ds:(_verbose - 4A7Dh)[eax], 0
* jz loc_3E65                             jz loc_4AB9
  cmp [ebp+var_68], 0                     cmp [ebp+var_68], 0
* jz loc_3E50                             jz loc_4AA4
* lea edx, (aBoot - 3E29h)[eax]           lea edx, (aBoot - 4A7Dh)[eax]
* jmp loc_3E56                            jmp loc_4AAA
* lea edx, (aActive - 3E29h)[eax]         lea edx, (aActive - 4A7Dh)[eax]
  push edx                                push edx
* add eax, 6DDEh                          add eax, 2952h
  push eax                                push eax
  call _printf                            call _printf
  add esp, 8                              add esp, 8
  lea eax, [ebp+var_64]                   lea eax, [ebp+var_64]
  xor dl, dl                              xor dl, dl
* mov ebx, [ebp+arg_0]
  lea esi, [ebp+var_64]                   lea esi, [ebp+var_64]
*                                         nop
*                                         nop
*                                         nop
  cmp byte ptr [ebx], 20h                 cmp byte ptr [ebx], 20h
* jz loc_3E84                             jz loc_4AD8
  cmp byte ptr [ebx], 0                   cmp byte ptr [ebx], 0
* jz loc_3E84                             jz loc_4AD8
  mov dl, 1                               mov dl, 1
  mov cl, [ebx]                           mov cl, [ebx]
* mov byte ptr (loc_3E29 - 3E29h)[eax], cl  mov byte ptr (loc_4A7D - 4A7Dh)[eax], cl
  inc eax                                 inc eax
* jmp loc_3EAA                            jmp loc_4AFE
  test dl, dl                             test dl, dl
* jnz loc_3E90                            jnz loc_4AE4
  cmp byte ptr [ebx], 0                   cmp byte ptr [ebx], 0
* jz loc_3EB4                             jz loc_4B08
* jmp loc_3EAA                            jmp loc_4AFE
* mov byte ptr (loc_3E29 - 3E29h)[eax], 0  mov byte ptr (loc_4A7D - 4A7Dh)[eax], 0
  movsx eax, [ebp+var_6C]                 movsx eax, [ebp+var_6C]
  push eax                                push eax
  movsx eax, [ebp+var_68]                 movsx eax, [ebp+var_68]
  push eax                                push eax
  push esi                                push esi
  call _processDriver                     call _processDriver
  mov eax, esi                            mov eax, esi
  xor dl, dl                              xor dl, dl
  add esp, 0Ch                            add esp, 0Ch
  cmp byte ptr [ebx], 0                   cmp byte ptr [ebx], 0
* jz loc_3EB4                             jz loc_4B08
  inc ebx                                 inc ebx
* jmp loc_3E70                            jmp loc_4AC4
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-74h]                      lea esp, [ebp-74h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Source follows Mac OS X Server 1.2

#### `_processDriver` (i386; ppc is `pic_equal`)

MOSXS 1.2v3 counts the units `configDriver` configured and returns 1 when
there were none. DR2 has no counter and returns 0. This build follows 1.2,
so `driverLoader D=<name>` with nothing configured exits 1 where DR2 exits
0; `vm/driverloader-behaviour.sh` states that as its `expect nodriver 0 1`
case. The i386 dump differs by that counter and the frame slot it needs.

```text
_processDriver
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 4                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  call $+5                                call $+5
* pop edi                                 pop [ebp+var_4]
  mov cl, [ebp+arg_4]                     mov cl, [ebp+arg_4]
* mov [ebp+var_4], cl                     mov [ebp+var_8], cl
*                                         xor edi, edi
  cmp [ebp+arg_8], 0                      cmp [ebp+arg_8], 0
* jnz loc_3EEC                            jnz loc_4B44
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  push ecx                                push ecx
  call _unloadDriver                      call _unloadDriver
* jmp loc_3FA6                            jmp loc_4C0F
  push 0                                  push 0
  push 0                                  push 0
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  push ecx                                push ecx
  call _prePostExec                       call _prePostExec
  add esp, 0Ch                            add esp, 0Ch
  cmp eax, 2                              cmp eax, 2
* jz loc_3F10                             jz loc_4B68
* ja loc_3F90                             ja loc_4C0A
  test eax, eax                           test eax, eax
* jz loc_3F30                             jz loc_4B90
* jmp loc_3F90                            jmp loc_4C0A
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  push ecx                                push ecx
* lea eax, (aDriverloaderDr - 3ECEh)[edi]  mov eax, [ebp+var_4]
*                                         add eax, 28C5h
  push eax                                push eax
* mov eax, edi                            mov ecx, [ebp+var_4]
* mov eax, [eax+83AEh]                    mov eax, [ebp+var_4]
*                                         mov eax, [ecx+35DAh]
  add eax, 0B0h                           add eax, 0B0h
  push eax                                push eax
  call _fprintf                           call _fprintf
* jmp loc_3F90                            jmp loc_4C0A
* cmp [ebp+var_4], 0                      cmp [ebp+var_8], 0
* jnz loc_3F46                            jnz loc_4BA8
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  push ecx                                push ecx
  call _loadDriver                        call _loadDriver
*                                         mov edx, eax
  add esp, 4                              add esp, 4
* test eax, eax                           test edx, edx
* jnz loc_3FA6                            jnz loc_4C0F
  xor esi, esi                            xor esi, esi
*                                         nop
*                                         nop
  test esi, esi                           test esi, esi
  setnle al                               setnle al
  and eax, 0FFh                           and eax, 0FFh
  push eax                                push eax
* cmp [ebp+var_4], 0                      cmp [ebp+var_8], 0
  setz al                                 setz al
  and eax, 0FFh                           and eax, 0FFh
  push eax                                push eax
  push esi                                push esi
  mov ecx, [ebp+arg_0]                    mov ecx, [ebp+arg_0]
  push ecx                                push ecx
  call _configDriver                      call _configDriver
  mov edx, eax                            mov edx, eax
  add esp, 10h                            add esp, 10h
  cmp edx, 3                              cmp edx, 3
* ja def_3F7D                             ja loc_4BF9
* lea eax, (jpt_3F7D - 3ECEh)[edi]        mov eax, [ebp+var_4]
* add eax, (jpt_3F7D - 3F80h)[eax+edx*4]  lea eax, [eax+0C6h]
*                                         add eax, [eax+edx*4]
  jmp eax                                 jmp eax
* mov eax, 1                              inc edi
* jmp loc_3FA6
  inc esi                                 inc esi
  cmp edx, 1                              cmp edx, 1
* jnz loc_3F48                            jnz loc_4BAC
* setnz al                                xor eax, eax
* and eax, 0FFh                           cmp edx, 1
* lea esp, [ebp-10h]                      jnz loc_4C0A
*                                         test edi, edi
*                                         jg loc_4C0F
*                                         mov eax, 1
*                                         lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

## Fixed Apple bugs

(none yet)
