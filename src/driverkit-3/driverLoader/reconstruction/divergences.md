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

## Fixed Apple bugs

(none yet)
