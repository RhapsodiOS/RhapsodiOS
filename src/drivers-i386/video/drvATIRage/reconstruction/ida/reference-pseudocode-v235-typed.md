# drvATIRage v235 typed reference pseudocode

Exported from IDA after applying the recovered ATI_BIOS (16-byte), ATI_BIOSPrivate (36-byte), ATI_BIOSRegisters (48-byte), and ATI_CRTCRecord (30-byte), ATI_SegmentDescriptor (8-byte), and ATI_BIOSPrivate_Layout (36-byte) layouts. The 72-entry IODisplayInfo table is also typed in the database; BIOS stack blocks in `shortQuery` and `loadCRTC_comm` use `ATI_BIOSRegisters`; `initFromDeviceDescription:` and `fixDeviceDescriptionForPCI:` use `IOPCIDeviceDescription *`; the PCI method's config-table local uses `IOConfigTable *` and its `barRegisters[18]`, `portRanges[9]`, and `memoryRanges[8]` locals use recovered layouts. The generated accessor return is `void **`, preserving the pointer depth of the Objective-C runtime encoding `^^{?}` for the opaque kernel-server reference. Helper prototypes for FIFO/idle waits and blit/fill operations use the source parameter widths and names. Type metadata only; reference binary unchanged.

## -[ATI initFromDeviceDescription:]

```c
// Control-flow review: PCI/BIOS/config failures log and call super free; init/query failures call super free without extra log; missing Display Mode logs then frees self; parse/aperture failures free self; successful mode setup updates display info and returns self only when verifyMemoryMap succeeds. The reference copies IODisplayInfo with rep movsd.
id __cdecl -[ATI initFromDeviceDescription:](ATI *self, SEL _cmd, struct IOPCIDeviceDescription *deviceDescription)
{
  const char *adapterLogName; // eax
  const char *biosLogName; // eax
  const char *configErrorLogName; // eax
  ATI_BIOS *biosClass; // eax
  ATI_BIOS *biosInstance; // edx
  unsigned int resetPort; // ecx
  unsigned __int32 initialPortRead; // eax
  unsigned int originalPortValue; // esi
  unsigned __int32 firstPortProbe; // eax
  unsigned __int32 secondPortProbe; // eax
  unsigned __int8 *queryData; // esi
  const char *asicName; // eax
  const char *asicSubtypeName; // eax
  const char *foundLogName; // eax
  const char *gammaName; // edx
  const char *capabilityLogName; // eax
  const char *ramdacLogName; // eax
  const char *displayModeText; // eax
  const char *missingModeLogName; // eax
  const char *colorConfigLogName; // eax
  IORange *memoryRanges; // eax
  void *framebuffer; // edx
  unsigned int registerPort; // ecx
  unsigned __int16 registerPortWord; // dx
  unsigned __int32 registerValue; // eax
  unsigned int maskedRegisterValue; // ecx
  const char *gammaNameArgument; // [esp-20h] [ebp-64h]
  const char *memoryName; // [esp-1Ch] [ebp-60h]
  const char *secondProbeErrorName; // [esp-Ch] [ebp-50h]
  const char *firstProbeErrorName; // [esp-Ch] [ebp-50h]
  const char *colorConfigName; // [esp-Ch] [ebp-50h]
  const char *framebufferMapErrorName; // [esp-Ch] [ebp-50h]
  const char *vramTestErrorName; // [esp-Ch] [ebp-50h]
  const char *ramdacStyleText; // [esp+10h] [ebp-34h]
  IOConfigTable *configTable; // [esp+14h] [ebp-30h]
  unsigned int biosBase; // [esp+18h] [ebp-2Ch] BYREF
  objc_super v40; // [esp+1Ch] [ebp-28h] BYREF
  char asicDescription[32]; // [esp+24h] [ebp-20h] BYREF

  self->engineStarted = 0;
  if ( -[IOPCIDeviceDescription getPCIdevice:function:bus:](a1: deviceDescription, a2: aGetpcideviceFu, 0, 0, 0) != nullptr )
  {
    adapterLogName = -[ATI name](a1: self, a2: aName);
    IOLog(a1: "ATIRage: ATIRage adapter not found\n", adapterLogName);
    v40.receiver = self;
    v40.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v40, a2: sel_free);
  }
  if ( +[ATI_BIOS ATIPresent:](a1: aAtiBios, a2: sel_ATIPresent_, &biosBase) == 0 )
  {
    biosLogName = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: ATI BIOS not found\n", biosLogName);
    v40.receiver = self;
    v40.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v40, a2: sel_free);
  }
  if ( -[ATI fixDeviceDescriptionForPCI:](a1: self, a2: sel_fixDeviceDescriptionForPCI_, deviceDescription) == 0 )
  {
    configErrorLogName = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Configuration error. Aborting...\n", configErrorLogName);
    v40.receiver = self;
    v40.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v40, a2: sel_free);
  }
  v40.receiver = self;
  v40.super_class = (Class)stru_8158.super_class;
  if ( -[ATI initFromDeviceDescription:](a1: &v40, a2: sel_initFromDeviceDescription_, deviceDescription) != nullptr )
  {
    biosClass = +[ATI_BIOS alloc](a1: aAtiBios, a2: aAlloc);
    biosInstance = -[ATI_BIOS initAtSegmentAddress:](a1: biosClass, a2: sel_initAtSegmentAddress_);
    self->atiBios = biosInstance;
    if ( biosInstance != nullptr )
    {
      self->queryDataSize = 0;
      objc_msgSend(a1: self->atiBios, a2: sel_getIOBaseAddress_relocatable_, &self->baseAddress, &self->relocatableIO);
      if ( self->relocatableIO != 0 )
        resetPort = self->baseAddress + 132;
      else
        resetPort = self->baseAddress + 17408;
      initialPortRead = __indword(resetPort);
      originalPortValue = initialPortRead;
      __outdword(resetPort, 0x55555555u);
      _InterlockedIncrement(&xxx_92);
      firstPortProbe = __indword(resetPort);
      if ( firstPortProbe != 1431655765 )
      {
        firstProbeErrorName = -[ATI name](a1: self, a2: aName);
        IOLog(a1: "%s: Rage/Rage II/Rage Pro BIOS not found.\n", firstProbeErrorName);
        return -[ATI free](a1: self, a2: sel_free);
      }
      __outdword(resetPort, 0xAAAAAAAA);
      _InterlockedIncrement(&xxx_92);
      secondPortProbe = __indword(resetPort);
      if ( secondPortProbe != -1431655766 )
      {
        secondProbeErrorName = -[ATI name](a1: self, a2: aName);
        IOLog(a1: "%s: Mach64/Rage failed second regsiter test.\n", secondProbeErrorName);
        return -[ATI free](a1: self, a2: sel_free);
      }
      __outdword(resetPort, originalPortValue);
      _InterlockedIncrement(&xxx_92);
      if ( -[ATI getQueryData](a1: self, a2: sel_getQueryData) == 0 )
      {
        queryData = (unsigned __int8 *)self->queryData;
        self->supportsGamma = (queryData[20] & 0x40) != 0;
        self->supportsGrey256 = (queryData[20] & 0x20) != 0;
        self->vramBytes = -[ATI displayMemorySize](a1: self, a2: sel_displayMemorySize);
        asicName = (const char *)IOFindNameForValue(a1: queryData[9], a2: &ATI_AsicTypeValues);
        strcpy(asicDescription, __src: asicName);
        if ( queryData[9] == 0xD7 )
        {
          asicSubtypeName = (const char *)IOFindNameForValue(a1: queryData[8], a2: &ATI_AsicSubTypeValues);
          strcat(__s1: asicDescription, __s2: asicSubtypeName);
        }
        foundLogName = (const char *)-[ATI name](a1: self, a2: aName);
        IOLog(a1: "%s: ATI Rage/Rage II/Rage Pro Found!\n", foundLogName);
        memoryName = (const char *)IOFindNameForValue(a1: queryData[11], a2: &ATI_memSizeValues);
        gammaName = "NO";
        if ( self->supportsGamma != 0 )
          gammaName = "YES";
        gammaNameArgument = gammaName;
        capabilityLogName = (const char *)-[ATI name](a1: self, a2: aName);
        IOLog(a1: "%s: Type %s.  Gamma: %s.  Memory: %s.\n", capabilityLogName, asicDescription, gammaNameArgument, memoryName);
        configTable = -[IOPCIDeviceDescription configTable](a1: deviceDescription, a2: aConfigtable);
        self->ramdacStyle = 0;
        ramdacStyleText = (const char *)objc_msgSend(a1: configTable, a2: aValueforstring, "RAMDAC Style");
        if ( ramdacStyleText != nullptr )
        {
          if ( strcmp(ramdacStyleText, "Sparse") == 0 )
          {
            self->ramdacStyle = 1;
          }
          else if ( strcmp(ramdacStyleText, "Dense") == 0 )
          {
            self->ramdacStyle = 2;
          }
          if ( self->ramdacStyle != 0 )
          {
            ramdacLogName = (const char *)-[ATI name](a1: self, a2: aName);
            IOLog(a1: "%s: ramdacStyle from table = %s\n", ramdacLogName, ramdacStyleText);
          }
          objc_msgSend(a1: configTable, a2: aFreestring, ramdacStyleText);
        }
        displayModeText = objc_msgSend(a1: configTable, a2: aValueforstring, "Display Mode");
        if ( displayModeText != nullptr )
        {
          if ( -[ATI parseModeString:](a1: self, a2: sel_parseModeString_, displayModeText) == 0 )
          {
            if ( AtiModeList[self->modeNumber].bitsPerPixel == 4 )
            {
              colorConfigName = (const char *)IOFindNameForValue(a1: self->colorConfig, a2: &colorConfigValues);
              colorConfigLogName = (const char *)-[ATI name](a1: self, a2: aName);
              IOLog(a1: "%s: 24 Bit Color Configuration = %s\n", colorConfigLogName, colorConfigName);
            }
            if ( objc_msgSend(a1: self->atiBios, a2: sel_setApertureEnable_VGAAperture_apertureAdrs_, 1, 0, 0) == nullptr )
            {
              memoryRanges = -[IOPCIDeviceDescription memoryRangeList](a1: deviceDescription, a2: aMemoryrangelis);
              framebuffer = -[ATI mapFrameBufferAtPhysicalAddress:length:](a1: self, a2: aMapframebuffer, *memoryRanges, 0x800000);
              self->vram = framebuffer;
              if ( framebuffer != nullptr )
              {
                if ( self->relocatableIO != 0 )
                  registerPort = self->baseAddress + 160;
                else
                  registerPort = self->baseAddress + 24576;
                registerPortWord = registerPort;
                registerValue = __indword(registerPort);
                maskedRegisterValue = registerValue;
                LOBYTE(maskedRegisterValue) = registerValue & 0xEF;
                __outdword(registerPortWord, maskedRegisterValue);
                _InterlockedIncrement(&xxx_92);
                register_base_address = (int)self->vram + 8387584;
                -[ATI updateModeList](a1: self, a2: sel_updateModeList);
                v40.receiver = self;
                v40.super_class = (Class)stru_8158.super_class;
                qmemcpy(-[ATI displayInfo](a1: &v40, a2: aDisplayinfo), &AtiModeList[self->modeNumber], 0x88u);
                if ( -[ATI verifyMemoryMap](a1: self, a2: sel_verifyMemoryMap) != 0 )
                {
                  self->currentState = 0;
                  self->blueTransferTable = nullptr;
                  self->greenTransferTable = nullptr;
                  self->redTransferTable = nullptr;
                  self->transferTableCount = 0;
                  self->brightnessLevel = 64;
                  return self;
                }
                vramTestErrorName = -[ATI name](a1: self, a2: aName);
                IOLog(a1: "%s: VRAM test failure, aborting\n", vramTestErrorName);
              }
              else
              {
                framebufferMapErrorName = -[ATI name](a1: self, a2: aName);
                IOLog(a1: "%s: Unable to map frame buffer\n", framebufferMapErrorName);
              }
            }
          }
        }
        else
        {
          missingModeLogName = (const char *)-[ATI name](a1: self, a2: aName);
          IOLog(a1: "%s: No Display Mode found; aborting\n", missingModeLogName);
        }
        return -[ATI free](a1: self, a2: sel_free);
      }
    }
  }
  v40.receiver = self;
  v40.super_class = (Class)stru_8158.super_class;
  return -[ATI free](a1: &v40, a2: sel_free);
}
```

## -[ATI fixDeviceDescriptionForPCI:]

```c
// Semantic review: BAR probing/restoration, range sizing/allocation, FB-address override, memory-range iteration, PCI BAR programming and error returns correspond to the rebuilt implementation. Differences are compiler temporary/register/control-flow layout; no behavior change identified.
char __cdecl -[ATI fixDeviceDescriptionForPCI:](ATI *self, SEL _cmd, struct IOPCIDeviceDescription *deviceDescription)
{
  int reg; // edi
  int mask; // esi
  int probedSize; // ecx
  int portRangeIndex; // eax
  char override; // al
  int memoryCheckIndex; // edi
  int portCheckIndex; // edi
  unsigned int currentMemoryBase; // esi
  int memoryPlacementIndex; // edi
  unsigned int alignedMemoryBase; // esi
  unsigned int currentPortBase; // esi
  int portPlacementIndex; // edi
  unsigned int alignedPortBase; // esi
  int memoryRangeCountIndex; // eax
  int secondMemoryRangeOffset; // eax
  int secondPortRangeOffset; // edx
  int thirdPortRangeOffset; // ecx
  IOConfigTable *configTable; // eax
  const char *text; // eax
  unsigned __int32 parsedFBAddress; // eax
  unsigned int memoryRetryIndex; // esi
  unsigned int candidateRangeIndex; // edi
  int memoryRangeResult; // eax
  unsigned int memoryBARIndex; // esi
  int portRangeResult; // eax
  const char *memoryRangeErrorName; // [esp-14h] [ebp-128h]
  const char *portRangeErrorName; // [esp-14h] [ebp-128h]
  unsigned int candidate; // [esp+Ch] [ebp-108h]
  unsigned int currentPCIRegister; // [esp+Ch] [ebp-108h]
  int memoryCountIndex; // [esp+10h] [ebp-104h]
  int portRangeCountIndex; // [esp+10h] [ebp-104h]
  unsigned int framebufferBase; // [esp+18h] [ebp-FCh]
  unsigned int memoryRangeCount; // [esp+1Ch] [ebp-F8h]
  Class directDeviceClass; // [esp+30h] [ebp-E4h]
  char success; // [esp+34h] [ebp-E0h]
  int portCount; // [esp+38h] [ebp-DCh]
  int portRangeCount; // [esp+38h] [ebp-DCh]
  int memoryCount; // [esp+3Ch] [ebp-D8h]
  int memoryRangeCountTotal; // [esp+3Ch] [ebp-D8h]
  int probed; // [esp+40h] [ebp-D4h] BYREF
  unsigned __int32 barRegisters[18]; // [esp+44h] [ebp-D0h] BYREF
  IORange portRanges[9]; // [esp+8Ch] [ebp-88h] BYREF
  IORange memoryRanges[8]; // [esp+D4h] [ebp-40h] BYREF

  portCount = 0;
  success = 1;
  directDeviceClass = (Class)-[ATI class](a1: self, a2: aClass);
  memoryCount = 0;
  for ( reg = 16; reg <= 39; reg += 4 )
  {
    -[objc_class getPCIConfigData:atRegister:withDeviceDescription:](
      a1: directDeviceClass,
      a2: aGetpciconfigda,
      barRegisters,
      (unsigned __int8)reg,
      deviceDescription);
    mask = -16;
    if ( (barRegisters[0] & 1) != 0 )
      mask = -4;
    -[objc_class setPCIConfigData:atRegister:withDeviceDescription:](
      a1: directDeviceClass,
      a2: aSetpciconfigda,
      barRegisters[0] | mask,
      (unsigned __int8)reg,
      deviceDescription);
    -[objc_class getPCIConfigData:atRegister:withDeviceDescription:](
      a1: directDeviceClass,
      a2: aGetpciconfigda,
      &probed,
      (unsigned __int8)reg,
      deviceDescription);
    -[objc_class setPCIConfigData:atRegister:withDeviceDescription:](
      a1: directDeviceClass,
      a2: aSetpciconfigda,
      barRegisters[0],
      (unsigned __int8)reg,
      deviceDescription);
    probedSize = probed & mask;
    if ( (probed & mask) != 0 )
    {
      if ( (barRegisters[0] & 1) != 0 )
      {
        portRangeIndex = portCount;
        portRanges[portRangeIndex].start = barRegisters[0] & mask;
        portRanges[portRangeIndex].size = -probedSize;
        barRegisters[++portCount] = reg;
      }
      else
      {
        memoryCountIndex = memoryCount;
        memoryRanges[memoryCountIndex].start = mask & barRegisters[0];
        memoryRanges[memoryCountIndex].size = -(probed & mask);
        barRegisters[memoryCount++ + 10] = reg;
      }
    }
  }
  override = 1;
  for ( memoryCheckIndex = 0; memoryCount > memoryCheckIndex; ++memoryCheckIndex )
  {
    if ( memoryRanges[memoryCheckIndex].start <= 0x3FFFFF )
      override = 0;
  }
  for ( portCheckIndex = 0; portCount > portCheckIndex; ++portCheckIndex )
  {
    if ( portRanges[portCheckIndex].start <= 0xFF )
      override = 0;
  }
  if ( override == 0 )
  {
    currentMemoryBase = *(_DWORD *)-[IOPCIDeviceDescription memoryRangeList](a1: deviceDescription, a2: aMemoryrangelis);
    for ( memoryPlacementIndex = 0; memoryCount > memoryPlacementIndex; ++memoryPlacementIndex )
    {
      alignedMemoryBase = (memoryRanges[memoryPlacementIndex].size + currentMemoryBase - 1)
                        & -memoryRanges[memoryPlacementIndex].size;
      memoryRanges[memoryPlacementIndex].start = alignedMemoryBase;
      -[objc_class setPCIConfigData:atRegister:withDeviceDescription:](
        a1: directDeviceClass,
        a2: aSetpciconfigda,
        alignedMemoryBase,
        LOBYTE(barRegisters[memoryPlacementIndex + 10]),
        deviceDescription);
      currentMemoryBase = memoryRanges[memoryPlacementIndex].size + alignedMemoryBase;
    }
    currentPortBase = *(_DWORD *)-[IOPCIDeviceDescription portRangeList](a1: deviceDescription, a2: aPortrangelist);
    for ( portPlacementIndex = 0; portCount > portPlacementIndex; ++portPlacementIndex )
    {
      alignedPortBase = (portRanges[portPlacementIndex].size + currentPortBase - 1)
                      & -portRanges[portPlacementIndex].size;
      portRanges[portPlacementIndex].start = alignedPortBase;
      -[objc_class setPCIConfigData:atRegister:withDeviceDescription:](
        a1: directDeviceClass,
        a2: aSetpciconfigda,
        alignedPortBase,
        LOBYTE(barRegisters[portPlacementIndex + 1]),
        deviceDescription);
      currentPortBase = portRanges[portPlacementIndex].size + alignedPortBase;
    }
  }
  memoryRangeCountIndex = memoryCount;
  memoryRanges[memoryRangeCountIndex].start = 655360;
  memoryRanges[memoryRangeCountIndex].size = 0x20000;
  secondMemoryRangeOffset = 8 * memoryCount + 8;
  *(unsigned int *)((char *)&memoryRanges[0].start + secondMemoryRangeOffset) = 786432;
  *(unsigned int *)((char *)&memoryRanges[0].size + secondMemoryRangeOffset) = 0x10000;
  memoryRangeCountTotal = memoryCount + 2;
  portRangeCountIndex = portCount;
  portRanges[portRangeCountIndex].start = 944;
  portRanges[portRangeCountIndex].size = 48;
  secondPortRangeOffset = 8 * portCount + 8;
  *(unsigned int *)((char *)&portRanges[0].start + secondPortRangeOffset) = 258;
  *(unsigned int *)((char *)&portRanges[0].size + secondPortRangeOffset) = 1;
  thirdPortRangeOffset = 8 * portCount + 16;
  *(unsigned int *)((char *)&portRanges[0].start + thirdPortRangeOffset) = 18152;
  *(unsigned int *)((char *)&portRanges[0].size + thirdPortRangeOffset) = 1;
  portRangeCount = portCount + 3;
  -[IOPCIDeviceDescription setMemoryRangeList:num:](a1: deviceDescription, a2: aSetmemoryrange, 0, 0);
  if ( -[IOPCIDeviceDescription setMemoryRangeList:num:](
         a1: deviceDescription,
         a2: aSetmemoryrange,
         memoryRanges,
         memoryRangeCountTotal) != nullptr )
  {
    framebufferBase = start_base_address;
    memoryRangeCount = memoryRangeCountTotal - 2;
    self->overrideStartBaseAddress = 0;
    configTable = (IOConfigTable *)-[IOPCIDeviceDescription configTable](a1: deviceDescription, a2: aConfigtable);
    if ( configTable != nullptr )
    {
      text = (const char *)-[IOConfigTable valueForStringKey:](a1: configTable, a2: aValueforstring, "FB Address");
      if ( text != nullptr && *text != 0 )
      {
        parsedFBAddress = strtol(__str: text, __endptr: nullptr, __base: 16) & 0x7F000000;
        if ( parsedFBAddress > 0x3FFFFFF )
        {
          framebufferBase = parsedFBAddress;
          self->overrideStartBaseAddress = 1;
        }
      }
    }
    memoryRetryIndex = 0;
    if ( memoryRangeCountTotal != 2 )
    {
      do
      {
        candidate = framebufferBase;
        if ( framebufferBase <= 0xFEFFFFFF )
        {
          candidateRangeIndex = memoryRetryIndex;
          do
          {
            memoryRanges[candidateRangeIndex].start = candidate;
            -[IOPCIDeviceDescription setMemoryRangeList:num:](a1: deviceDescription, a2: aSetmemoryrange, 0, 0);
            if ( -[IOPCIDeviceDescription setMemoryRangeList:num:](
                   a1: deviceDescription,
                   a2: aSetmemoryrange,
                   memoryRanges,
                   memoryRetryIndex) == nullptr )
              break;
            candidate += memoryRanges[candidateRangeIndex].size;
          }
          while ( candidate <= 0xFEFFFFFF );
        }
        ++memoryRetryIndex;
      }
      while ( memoryRangeCount > memoryRetryIndex );
    }
    -[IOPCIDeviceDescription setMemoryRangeList:num:](a1: deviceDescription, a2: aSetmemoryrange, 0, 0);
    memoryRangeResult = (int)-[IOPCIDeviceDescription setMemoryRangeList:num:](
                               a1: deviceDescription,
                               a2: aSetmemoryrange,
                               memoryRanges,
                               memoryRangeCountTotal);
    if ( memoryRangeResult != 0 )
    {
      -[ATI stringFromReturn:](a1: self, a2: aStringfromretu, memoryRangeResult);
      memoryRangeErrorName = (const char *)-[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: Error in setMemoryRangeList (%s)\n", memoryRangeErrorName);
      return 0;
    }
    memoryBARIndex = 0;
    currentPCIRegister = 16;
    if ( memoryRangeCountTotal != 2 )
    {
      do
      {
        if ( currentPCIRegister > 0x27 )
          break;
        -[objc_class setPCIConfigData:atRegister:withDeviceDescription:](
          a1: directDeviceClass,
          a2: aSetpciconfigda,
          memoryRanges[memoryBARIndex++].start,
          (unsigned __int8)currentPCIRegister,
          deviceDescription);
        currentPCIRegister += 4;
      }
      while ( memoryRangeCount > memoryBARIndex );
    }
  }
  -[IOPCIDeviceDescription setPortRangeList:num:](a1: deviceDescription, a2: aSetportrangeli, 0, 0);
  portRangeResult = (int)-[IOPCIDeviceDescription setPortRangeList:num:](
                           a1: deviceDescription,
                           a2: aSetportrangeli,
                           portRanges,
                           portRangeCount);
  if ( portRangeResult != 0 )
  {
    -[ATI stringFromReturn:](a1: self, a2: aStringfromretu, portRangeResult);
    portRangeErrorName = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Error in setPortRangeList (%s)\n", portRangeErrorName);
    return 0;
  }
  return success;
}
```

## -[ATI getQueryData]

```c
int __cdecl -[ATI getQueryData](ATI *self, SEL _cmd)
{
  int querySizeResult; // eax
  const char *querySizeLogName; // eax
  unsigned __int16 *temporary; // esi
  int deviceQueryResult; // eax
  unsigned int queryDataLength; // eax
  void *allocatedQueryData; // eax
  const char *deviceQueryLogName; // eax
  const char *deviceQueryErrorName; // [esp-Ch] [ebp-18h]
  const char *querySizeErrorName; // [esp-4h] [ebp-10h]
  unsigned int size; // [esp+8h] [ebp-4h] BYREF

  size = 0;
  if ( self->queryDataSize != 0 )
  {
    IOFree(a1: self->queryData, a2: self->queryDataSize);
    self->queryDataSize = 0;
  }
  querySizeResult = (int)objc_msgSend(a1: self->atiBios, a2: sel_querySize_size_, 0, &size);
  if ( querySizeResult != 0 )
  {
    querySizeErrorName = (const char *)IOFindNameForValue(a1: querySizeResult, a2: &ABReturnValues);
    querySizeLogName = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: querySize returned %s\n", querySizeLogName, querySizeErrorName);
  }
  else
  {
    temporary = (unsigned __int16 *)IOMalloc(a1: size);
    deviceQueryResult = (int)objc_msgSend(a1: self->atiBios, a2: sel_deviceQuery_bufferSize_buffer_, 0, size, temporary);
    if ( deviceQueryResult == 0 )
    {
      queryDataLength = *temporary;
      self->queryDataSize = queryDataLength;
      allocatedQueryData = (void *)IOMalloc(a1: queryDataLength);
      self->queryData = allocatedQueryData;
      bcopy(a1: temporary, a2: allocatedQueryData, a3: self->queryDataSize);
      IOFree(a1: temporary, a2: size);
      return 0;
    }
    deviceQueryErrorName = (const char *)IOFindNameForValue(a1: deviceQueryResult, a2: &ABReturnValues);
    deviceQueryLogName = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: deviceQuery returned %s\n", deviceQueryLogName, deviceQueryErrorName);
    if ( size != 0 )
      IOFree(a1: temporary, a2: size);
  }
  return 1;
}
```

## -[ATI parseModeString:]

```c
int __cdecl -[ATI parseModeString:](ATI *self, SEL _cmd, const char *modeString)
{
  int selectedMode; // eax
  const char *selectModeLogName; // eax
  unsigned int modeValidationResult; // eax
  const char *invalidModeLogName; // eax
  unsigned int modeErrorForLog; // [esp-4h] [ebp-8h]

  selectedMode = (int)-[ATI selectMode:count:](a1: self, a2: aSelectmodeCoun, AtiModeList, AtiModeListCount);
  self->modeNumber = selectedMode;
  if ( selectedMode >= 0 )
  {
    modeValidationResult = -[ATI isModeValid:](a1: self, a2: sel_isModeValid_, self->modeNumber);
    if ( modeValidationResult == 0 )
      return 0;
    modeErrorForLog = modeValidationResult;
    invalidModeLogName = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Requested Mode not supported (0x%x); aborting\n", invalidModeLogName, modeErrorForLog);
  }
  else
  {
    selectModeLogName = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: selectMode problem; aborting\n", selectModeLogName);
  }
  return -1;
}
```

## -[ATI updateModeList]

```c
void __cdecl -[ATI updateModeList](ATI *self, SEL _cmd)
{
  id deviceDescription; // eax
  const char *configString; // eax
  const char *configStringToFree; // ebx
  const char *driverName; // eax
  unsigned int colorConfig; // eax
  const char *pixelEncoding; // edi
  unsigned int modeIndex; // ebx
  unsigned int modeIndexForFields; // eax
  const char *configStringForLog; // [esp-4h] [ebp-18h]
  IOConfigTable *configTable; // [esp+10h] [ebp-4h]

  deviceDescription = -[ATI deviceDescription](a1: self, a2: aDevicedescript);
  configTable = (IOConfigTable *)objc_msgSend(a1: deviceDescription, a2: aConfigtable);
  self->colorConfig = 0;
  configString = (const char *)-[IOConfigTable valueForStringKey:](
                                 a1: configTable,
                                 a2: aValueforstring,
                                 "24-bit Configuration");
  configStringToFree = configString;
  if ( configString != nullptr )
  {
    if ( strcmp(configString, "RGBx") == 0 )
    {
      self->colorConfig = 1;
    }
    else if ( strcmp(configString, "BGRx") == 0 )
    {
      self->colorConfig = 2;
    }
    else if ( strcmp(configString, "xRGB") == 0 )
    {
      self->colorConfig = 3;
    }
    else if ( strcmp(configString, "xBGR") == 0 )
    {
      self->colorConfig = 4;
    }
    if ( self->colorConfig != 0 )
    {
      configStringForLog = configString;
      driverName = (const char *)-[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: colorConfig from table = %s\n", driverName, configStringForLog);
    }
    -[IOConfigTable freeString:](a1: configTable, a2: aFreestring, configStringToFree);
  }
  colorConfig = self->colorConfig;
  if ( colorConfig == 2 )
  {
    pixelEncoding = "BBBBBBBBGGGGGGGGRRRRRRRR--------";
  }
  else if ( colorConfig > 2 )
  {
    if ( colorConfig != 4 )
    {
LABEL_18:
      pixelEncoding = "--------RRRRRRRRGGGGGGGGBBBBBBBB";
      goto LABEL_22;
    }
    pixelEncoding = "--------BBBBBBBBGGGGGGGGRRRRRRRR";
  }
  else
  {
    if ( colorConfig != 1 )
      goto LABEL_18;
    pixelEncoding = "RRRRRRRRGGGGGGGGBBBBBBBB--------";
  }
LABEL_22:
  for ( modeIndex = 0; AtiModeListCount > modeIndex; ++modeIndex )
  {
    modeIndexForFields = modeIndex;
    AtiModeList[modeIndex].frameBuffer = self->vram;
    if ( self->supportsGamma == 0 && AtiModeList[modeIndexForFields].bitsPerPixel != 1 )
    {
      AtiModeList[modeIndexForFields].flags &= ~0x10u;
      LOBYTE(AtiModeList[modeIndexForFields].flags) |= 2u;
    }
    if ( AtiModeList[modeIndex].bitsPerPixel == 4 )
      strcpy(__dst: (char *)(136 * modeIndex + 17148), __src: pixelEncoding);
    AtiModeList[modeIndex].modeUnavailableFlag = 0;
    if ( self->vramBytes < AtiModeList[modeIndex].memorySize )
      AtiModeList[modeIndex].modeUnavailableFlag = 2;
  }
}
```

## -[ATI isModeValid:]

```c
unsigned int __cdecl -[ATI isModeValid:](ATI *self, SEL _cmd, int mode)
{
  IODisplayInfo_Recovered *modeInfo; // edx
  _BYTE *queryData; // ecx
  unsigned int bitsPerPixel; // eax
  unsigned int requiredBytes; // ebx

  if ( (int)AtiModeListCount <= mode )
    return 16;
  modeInfo = &AtiModeList[mode];
  queryData = self->queryData;
  bitsPerPixel = modeInfo->bitsPerPixel;
  if ( bitsPerPixel == 3 )
  {
    if ( (queryData[19] & 2) == 0 )
      return 64;
  }
  else if ( bitsPerPixel == 4 && self->colorConfig == 5 )
  {
    return 64;
  }
  requiredBytes = modeInfo->height * modeInfo->rowBytes;
  if ( requiredBytes > memSizeToBytes(a1: queryData[11]) )
    return 2;
  else
    return 0;
}
```

## -[ATI verifyMemoryMap]

```c
char __cdecl -[ATI verifyMemoryMap](ATI *self, SEL _cmd)
{
  unsigned int *vram; // ebx
  unsigned int writeIndex; // eax
  unsigned int verifyIndex; // eax
  unsigned int savedVram[16]; // [esp+8h] [ebp-40h] BYREF

  vram = (unsigned int *)self->vram;
  bcopy(a1: vram, a2: savedVram, a3: 0x40u);
  for ( writeIndex = 0; writeIndex <= 0xF; ++writeIndex )
    vram[writeIndex] = writeIndex;
  for ( verifyIndex = 0; verifyIndex <= 0xF; ++verifyIndex )
  {
    if ( vram[verifyIndex] != verifyIndex )
      return 0;
  }
  bcopy(a1: savedVram, a2: self->vram, a3: 0x40u);
  return 1;
}
```

## -[ATI free]

```c
id __cdecl -[ATI free](ATI *self, SEL _cmd)
{
  objc_super superCall; // [esp+4h] [ebp-8h] BYREF

  if ( self->queryDataSize != 0 )
    IOFree(a1: self->queryData, a2: self->queryDataSize);
  if ( self->atiBios != nullptr )
    objc_msgSend(a1: self->atiBios, a2: sel_free);
  if ( self->redTransferTable != nullptr )
    IOFree(a1: self->redTransferTable, a2: 3 * self->transferTableCount);
  superCall.receiver = self;
  superCall.super_class = (Class)stru_8158.super_class;
  return -[ATI free](a1: &superCall, a2: sel_free);
}
```

## -[ATI enterLinearMode]

```c
void __cdecl -[ATI enterLinearMode](ATI *self, SEL _cmd)
{
  IODisplayInfo_Recovered *info; // ebx
  unsigned int depth; // edi
  char supportsGrey256; // al
  unsigned int pitch; // edx
  unsigned int biosResult; // eax
  const char *driverName; // eax
  const char *errorName; // [esp-4h] [ebp-14h]
  void *crtcRecord; // [esp+Ch] [ebp-4h]

  info = (IODisplayInfo_Recovered *)-[ATI displayInfo](a1: self, a2: aDisplayinfo);
  crtcRecord = info->parameters;
  if ( self->currentState != 1
    && objc_msgSend(a1: self->atiBios, a2: sel_setApertureEnable_VGAAperture_apertureAdrs_, 1, 0, 0) == nullptr )
  {
    depth = displayInfoToColorDepth(a1: (int)info);
    displayInfoToColorSpace(a1: (int)info);
    if ( depth == 2 )
      supportsGrey256 = self->supportsGrey256;
    else
      supportsGrey256 = self->supportsGamma;
    pitch = 2;
    if ( info->width == 1024 )
      pitch = 0;
    biosResult = (unsigned int)objc_msgSend(
                                 a1: self->atiBios,
                                 a2: sel_loadCRTCSetMode_gamma_pitchSize_resolution_crtTable_,
                                 depth,
                                 supportsGrey256,
                                 pitch,
                                 129,
                                 crtcRecord);
    if ( biosResult != 0 )
    {
      errorName = (const char *)IOFindNameForValue(a1: biosResult, a2: &ABReturnValues);
      driverName = (const char *)-[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: Error setting CRTC Paramters (%s)\n", driverName, errorName);
    }
    else
    {
      -[ATI initEngine](a1: self, a2: sel_initEngine);
      self->engineStarted = 1;
      bzero(a1: self->vram, a2: self->vramBytes);
      self->currentState = 1;
      -[ATI setGammaTable](a1: self, a2: sel_setGammaTable);
    }
  }
}
```

## -[ATI revertToVGAMode]

```c
void __cdecl -[ATI revertToVGAMode](ATI *self, SEL _cmd)
{
  unsigned int crtcResult; // eax
  const char *driverName; // eax
  unsigned int vgaResult; // eax
  const char *driverNameForVGA; // eax
  const char *crtcErrorName; // [esp-Ch] [ebp-38h]
  const char *vgaErrorName; // [esp-4h] [ebp-30h]
  ATI_CRTCRecord crtc; // [esp+Ch] [ebp-20h] BYREF

  crtc = *(ATI_CRTCRecord *)byte_3BC2;
  crtcResult = (unsigned int)objc_msgSend(
                               a1: self->atiBios,
                               a2: sel_loadCRTCSetMode_gamma_pitchSize_resolution_crtTable_,
                               1,
                               0,
                               2,
                               129,
                               &crtc);
  if ( crtcResult != 0 )
  {
    crtcErrorName = (const char *)IOFindNameForValue(a1: crtcResult, a2: &ABReturnValues);
    driverName = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Error setting CRTC (%s)\n", driverName, crtcErrorName);
  }
  vgaResult = (unsigned int)objc_msgSend(a1: self->atiBios, a2: sel_setVGAMode_gamma_, 1, 0);
  if ( vgaResult != 0 )
  {
    vgaErrorName = (const char *)IOFindNameForValue(a1: vgaResult, a2: &ABReturnValues);
    driverNameForVGA = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Error setting VGA (%s)\n", driverNameForVGA, vgaErrorName);
  }
  else
  {
    if ( self->redTransferTable != nullptr )
    {
      IOFree(a1: self->redTransferTable, a2: 3 * self->transferTableCount);
      self->redTransferTable = nullptr;
    }
    self->currentState = 2;
    self->engineStarted = 0;
  }
}
```

## _waitForFIFO

```c
unsigned int __cdecl waitForFIFO(unsigned int count)
{
  unsigned int result; // eax

  result = 0x8000u >> count;
  if ( *(_DWORD *)(register_base_address + 784) > 0x8000u >> count )
  {
    result = 0x8000u >> count;
    while ( *(_DWORD *)(register_base_address + 784) > result )
      ;
  }
  return result;
}
```

## _waitForIdle

```c
int __cdecl waitForIdle()
{
  unsigned int pollCount; // ebx
  unsigned int pollCountBeforeIncrement; // eax
  int result; // eax

  pollCount = 0;
  waitForFIFO(count: 0x10u);
  while ( 1 )
  {
    result = register_base_address;
    if ( (*(_BYTE *)(register_base_address + 824) & 1) == 0 )
      break;
    IODelay(a1: 1);
    pollCountBeforeIncrement = pollCount++;
    if ( pollCountBeforeIncrement > 0x7A120 )
      return IOLog(a1: "ATIRage: waitForIdle timeout.\n");
  }
  return result;
}
```

## _doBlit

```c
// Semantic review: absolute overlap distances, overlap branch conditions, forward/reverse source/destination coordinates, direction bits, FIFO waits, saved MMIO registers, register write order and return value match rebuilt source. Remaining differences are register selection/CFG layout and the unsigned negation lowering.
int __cdecl doBlit(
        unsigned int sourceX,
        unsigned int sourceY,
        unsigned int width,
        unsigned int height,
        unsigned int destinationX,
        unsigned int destinationY)
{
  unsigned int destinationXReg; // ecx
  unsigned int overlapXDistance; // edx
  unsigned int overlapYDistance; // edx
  unsigned int destinationYStart; // esi
  _DWORD *registers; // edx
  int blitControl; // eax
  unsigned int blitSize; // eax
  int result; // eax
  int direction; // [esp+Ch] [ebp-1Ch]
  unsigned int sourceYStart; // [esp+10h] [ebp-18h]
  unsigned int destinationXStart; // [esp+14h] [ebp-14h]
  unsigned int sourceXStart; // [esp+18h] [ebp-10h]
  int savedRegister304; // [esp+1Ch] [ebp-Ch]
  int savedRegister436; // [esp+20h] [ebp-8h]
  int savedRegister728; // [esp+24h] [ebp-4h]

  destinationXReg = destinationX;
  overlapXDistance = destinationX - sourceX;
  if ( (int)(destinationX - sourceX) < 0 )
    overlapXDistance = sourceX - destinationX;
  if ( width > overlapXDistance )
  {
    overlapYDistance = destinationY - sourceY;
    if ( (int)(destinationY - sourceY) < 0 )
      overlapYDistance = sourceY - destinationY;
    if ( height > overlapYDistance )
    {
      direction = 0;
      if ( sourceX >= destinationX )
      {
        LOBYTE(direction) = 1;
        sourceXStart = sourceX;
      }
      else
      {
        sourceXStart = width + sourceX - 1;
        destinationXReg = width + destinationX - 1;
      }
      destinationXStart = destinationXReg;
      if ( destinationY <= sourceY )
      {
        LOBYTE(direction) = direction | 2;
        sourceYStart = sourceY;
LABEL_14:
        destinationYStart = destinationY;
        goto LABEL_15;
      }
      sourceYStart = height + sourceY - 1;
      destinationYStart = height + destinationY - 1;
LABEL_15:
      waitForIdle();
      waitForFIFO(count: 0xAu);
      registers = (_DWORD *)register_base_address;
      savedRegister728 = *(_DWORD *)(register_base_address + 728);
      savedRegister436 = *(_DWORD *)(register_base_address + 436);
      savedRegister304 = *(_DWORD *)(register_base_address + 304);
      *(_DWORD *)(register_base_address + 728) = 768;
      registers[109] = 0;
      blitControl = direction | savedRegister304 & 0x80;
      LOBYTE(blitControl) = blitControl | 0x18;
      registers[76] = blitControl;
      registers[99] = sourceYStart | (sourceXStart << 16);
      blitSize = height | (width << 16);
      registers[102] = blitSize;
      registers[67] = destinationYStart | (destinationXStart << 16);
      registers[70] = blitSize;
      waitForFIFO(count: 3u);
      result = register_base_address;
      *(_DWORD *)(register_base_address + 728) = savedRegister728;
      *(_DWORD *)(result + 436) = savedRegister436;
      *(_DWORD *)(result + 304) = savedRegister304;
      return result;
    }
  }
  direction = 3;
  sourceXStart = sourceX;
  sourceYStart = sourceY;
  destinationXStart = destinationX;
  goto LABEL_14;
}
```

## -[ATI showCursor:frame:token:]

```c
id __cdecl -[ATI showCursor:frame:token:](ATI *self, SEL _cmd, Point *cursorLoc, int frame, int token)
{
  objc_super superCall; // [esp+Ch] [ebp-8h] BYREF

  waitForIdle();
  superCall.receiver = self;
  superCall.super_class = (Class)stru_8158.super_class;
  return -[ATI showCursor:frame:token:](a1: &superCall, a2: sel_showCursor_frame_token_, cursorLoc, frame, token);
}
```

## -[ATI moveCursor:frame:token:]

```c
id __cdecl -[ATI moveCursor:frame:token:](ATI *self, SEL _cmd, Point *cursorLoc, int frame, int token)
{
  objc_super superCall; // [esp+Ch] [ebp-8h] BYREF

  waitForIdle();
  superCall.receiver = self;
  superCall.super_class = (Class)stru_8158.super_class;
  return -[ATI moveCursor:frame:token:](a1: &superCall, a2: sel_moveCursor_frame_token_, cursorLoc, frame, token);
}
```

## -[ATI hideCursor:]

```c
id __cdecl -[ATI hideCursor:](ATI *self, SEL _cmd, int token)
{
  objc_super superCall; // [esp+8h] [ebp-8h] BYREF

  waitForIdle();
  superCall.receiver = self;
  superCall.super_class = (Class)stru_8158.super_class;
  return -[ATI hideCursor:](a1: &superCall, a2: sel_hideCursor_, token);
}
```

## _doFill

```c
int __cdecl doFill(unsigned int left, unsigned int top, unsigned int right, unsigned int bottom, unsigned int color)
{
  volatile unsigned int *registers; // eax
  unsigned int saved728; // edi
  unsigned int saved436; // esi
  unsigned int saved304; // ebx
  int result; // eax

  waitForIdle();
  waitForFIFO(count: 7u);
  registers = (volatile unsigned int *)register_base_address;
  saved728 = *(_DWORD *)(register_base_address + 728);
  saved436 = *(_DWORD *)(register_base_address + 436);
  saved304 = *(_DWORD *)(register_base_address + 304);
  *(_DWORD *)(register_base_address + 708) = color;
  *((_DWORD *)registers + 182) = 256;
  *((_DWORD *)registers + 67) = top | (left << 16);
  *((_DWORD *)registers + 70) = bottom | (right << 16);
  waitForFIFO(count: 3u);
  result = register_base_address;
  *(_DWORD *)(register_base_address + 728) = saved728;
  *(_DWORD *)(result + 436) = saved436;
  *(_DWORD *)(result + 304) = saved304;
  return result;
}
```

## -[ATI initEngine]

```c
void __cdecl -[ATI initEngine](ATI *self, SEL _cmd)
{
  IODisplayInfo_Recovered *info; // esi
  unsigned int width; // ebx
  volatile unsigned int *initialRegisters; // eax
  unsigned int pitch; // edx
  volatile unsigned int *timingRegisters; // eax
  volatile unsigned int *formatRegisters; // eax
  volatile unsigned int *format1Or4Registers; // eax
  volatile unsigned int *format3Registers; // eax
  const char *driverName; // eax

  info = (IODisplayInfo_Recovered *)-[ATI displayInfo](a1: self, a2: aDisplayinfo);
  -[ATI resetEngine](a1: self, a2: sel_resetEngine);
  width = info->width;
  waitForFIFO(count: 0xEu);
  initialRegisters = (volatile unsigned int *)register_base_address;
  *(_DWORD *)(register_base_address + 800) = -1;
  pitch = width >> 3 << 22;
  *((_DWORD *)initialRegisters + 64) = pitch;
  *((_DWORD *)initialRegisters + 67) = 0;
  *((_DWORD *)initialRegisters + 69) = 0;
  *((_DWORD *)initialRegisters + 73) = 0;
  *((_DWORD *)initialRegisters + 74) = 0;
  *((_DWORD *)initialRegisters + 75) = 0;
  *((_DWORD *)initialRegisters + 76) = 35;
  *((_DWORD *)initialRegisters + 96) = pitch;
  *((_DWORD *)initialRegisters + 99) = 0;
  *((_DWORD *)initialRegisters + 102) = 0;
  *((_DWORD *)initialRegisters + 105) = 0;
  *((_DWORD *)initialRegisters + 108) = 0;
  *((_DWORD *)initialRegisters + 109) = 16;
  waitForFIFO(count: 0xDu);
  timingRegisters = (volatile unsigned int *)register_base_address;
  *(_DWORD *)(register_base_address + 576) = 0;
  *((_DWORD *)timingRegisters + 160) = 0;
  *((_DWORD *)timingRegisters + 161) = 0;
  *((_DWORD *)timingRegisters + 162) = 0;
  *((_DWORD *)timingRegisters + 168) = 0;
  *((_DWORD *)timingRegisters + 171) = 0;
  *((_DWORD *)timingRegisters + 172) = info->width - 1;
  *((_DWORD *)timingRegisters + 169) = width - 1;
  *((_DWORD *)timingRegisters + 176) = 0;
  *((_DWORD *)timingRegisters + 177) = -1;
  *((_DWORD *)timingRegisters + 178) = -1;
  *((_DWORD *)timingRegisters + 181) = 458755;
  *((_DWORD *)timingRegisters + 182) = 256;
  waitForFIFO(count: 3u);
  formatRegisters = (volatile unsigned int *)register_base_address;
  *(_DWORD *)(register_base_address + 768) = 0;
  *((_DWORD *)formatRegisters + 193) = -1;
  *((_DWORD *)formatRegisters + 194) = 0;
  switch ( info->bitsPerPixel )
  {
    case 1u:
      waitForFIFO(count: 2u);
      format1Or4Registers = (volatile unsigned int *)register_base_address;
      *(_DWORD *)(register_base_address + 720) = 16908802;
      goto LABEL_5;
    case 3u:
      waitForFIFO(count: 2u);
      format3Registers = (volatile unsigned int *)register_base_address;
      *(_DWORD *)(register_base_address + 720) = 16974595;
      *((_DWORD *)format3Registers + 179) = 16912;
      break;
    case 4u:
      waitForFIFO(count: 2u);
      format1Or4Registers = (volatile unsigned int *)register_base_address;
      *(_DWORD *)(register_base_address + 720) = 17171974;
LABEL_5:
      *((_DWORD *)format1Or4Registers + 179) = 32896;
      break;
    default:
      driverName = (const char *)-[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: Pixel depth not supported,\n", driverName);
      break;
  }
  waitForIdle();
}
```

## -[ATI resetEngine]

```c
void __cdecl -[ATI resetEngine](ATI *self, SEL _cmd)
{
  unsigned __int16 engineResetPort; // dx
  unsigned __int32 engineResetValue; // eax
  unsigned int engineResetValueCleared; // ebx
  unsigned __int16 engineResetPortAgain; // dx
  unsigned __int32 engineResetValueAgain; // eax
  unsigned __int32 engineResetValueSet; // ebx
  unsigned __int32 engineConfigurationValue; // eax

  engineResetPort = LOWORD(self->baseAddress) + 208;
  engineResetValue = __indword(engineResetPort);
  engineResetValueCleared = engineResetValue;
  BYTE1(engineResetValueCleared) = BYTE1(engineResetValue) & 0xFE;
  __outdword(engineResetPort, engineResetValueCleared);
  _InterlockedIncrement(&xxx_92);
  engineResetPortAgain = LOWORD(self->baseAddress) + 208;
  engineResetValueAgain = __indword(engineResetPortAgain);
  engineResetValueSet = engineResetValueAgain;
  BYTE1(engineResetValueSet) = BYTE1(engineResetValueAgain) | 1;
  __outdword(engineResetPortAgain, engineResetValueSet);
  _InterlockedIncrement(&xxx_92);
  LOWORD(engineResetValueSet) = LOWORD(self->baseAddress) + 160;
  engineConfigurationValue = __indword(engineResetValueSet);
  __outdword(engineResetValueSet, engineConfigurationValue & 0xFF00FFFF | 0xAE0000);
  _InterlockedIncrement(&xxx_92);
}
```

## -[ATI displayModeCount]

```c
unsigned int __cdecl -[ATI displayModeCount](ATI *self, SEL _cmd)
{
  return AtiModeListCount;
}
```

## -[ATI displayModes]

```c
IODisplayInfo_Recovered *__cdecl -[ATI displayModes](ATI *self, SEL _cmd)
{
  return AtiModeList;
}
```

## -[ATI displayMemorySize]

```c
unsigned int __cdecl -[ATI displayMemorySize](ATI *self, SEL _cmd)
{
  return memSizeToBytes(memorySize: *((_BYTE *)self->queryData + 11));
}
```

## -[ATI setPendingDisplayMode:]

```c
char __cdecl -[ATI setPendingDisplayMode:](ATI *self, SEL _cmd, int mode)
{
  const char *driverName; // eax
  objc_super superCall; // [esp+8h] [ebp-8h] BYREF

  if ( (int)AtiModeListCount <= mode )
  {
    driverName = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: setPendingDisplayMode: bogus displayMode (%d)\n", driverName, mode);
  }
  else if ( -[ATI isModeValid:](a1: self, a2: sel_isModeValid_, mode) == 0 )
  {
    AtiModeList[mode].frameBuffer = self->vram;
    superCall.receiver = self;
    superCall.super_class = (Class)stru_8158.super_class;
    if ( -[ATI setPendingDisplayMode:](a1: &superCall, a2: sel_setPendingDisplayMode_, mode) != 0 )
    {
      self->modeNumber = mode;
      return 1;
    }
  }
  return 0;
}
```

## -[ATI setIntValues:forParameter:count:]

```c
int __cdecl -[ATI setIntValues:forParameter:count:](
        ATI *self,
        SEL _cmd,
        unsigned int *values,
        const char *parameterName,
        unsigned int count)
{
  objc_super superCall; // [esp+Ch] [ebp-8h] BYREF

  if ( strcmp(parameterName, "IODisplayDoBlit") == 0 && count == 6 )
  {
    doBlit(
      sourceX: *values,
      sourceY: values[1],
      width: values[2],
      height: values[3],
      destinationX: values[4],
      destinationY: values[5]);
  }
  else if ( strcmp(parameterName, "IODisplayDoFill") == 0 && count == 5 )
  {
    doFill(left: *values, top: values[1], right: values[2], bottom: values[3], color: values[4]);
  }
  else
  {
    if ( strcmp(parameterName, "IOGetDisplaySynced") != 0 || count != 1 )
    {
      superCall.receiver = self;
      superCall.super_class = (Class)stru_8158.super_class;
      return -[ATI setIntValues:forParameter:count:](
               a1: &superCall,
               a2: sel_setIntValues_forParameter_count_,
               values,
               parameterName,
               count);
    }
    waitForIdle();
  }
  return 0;
}
```

## _isATI68880RevC

```c
_BOOL4 __cdecl isATI68880RevC(unsigned __int16 base)
{
  unsigned __int8 portValue; // al

  portValue = __inbyte(base + 195);
  return portValue == 0xD0;
}
```

## _SetGammaValue

```c
unsigned int __cdecl SetGammaValue(unsigned __int16 base, int red, int green, int blue, int brightness)
{
  unsigned int blueScaledValue; // eax

  __outbyte(base + 193, (unsigned int)(brightness * red) >> 6);
  _InterlockedIncrement(&xxx_8);
  __outbyte(base + 193, (unsigned int)(brightness * green) >> 6);
  _InterlockedIncrement(&xxx_8);
  blueScaledValue = (unsigned int)(brightness * blue) >> 6;
  __outbyte(base + 193, blueScaledValue);
  _InterlockedIncrement(&xxx_8);
  return blueScaledValue;
}
```

## -[ATI setGammaTable]

```c
// Semantic review: transfer-table and default gamma paths, write order, loop counts and return match the rebuilt source. The three delay increments share the reference counter with _SetGammaValue. Remaining body difference is the placement of add esp, 8 relative to loading displayInfo.bitsPerPixel; it is independent stack cleanup and does not change the loaded value.
id __cdecl -[ATI setGammaTable](ATI *self, SEL _cmd)
{
  unsigned __int16 port; // dx
  unsigned __int8 value; // al
  unsigned int i; // esi
  unsigned int j; // ebx
  unsigned int depth; // edx
  unsigned int k; // ebx
  unsigned int m; // esi
  unsigned int n; // ebx

  port = LOWORD(self->baseAddress) + 196;
  value = __inbyte(port);
  __outbyte(port, value & 0xFC | 2);
  _InterlockedIncrement(&xxx_8);
  __outbyte(LOWORD(self->baseAddress) + 194, 0xFFu);
  _InterlockedIncrement(&xxx_8);
  __outbyte(LOWORD(self->baseAddress) + 192, 0);
  _InterlockedIncrement(&xxx_8);
  if ( self->redTransferTable != nullptr )
  {
    for ( i = 0; self->transferTableCount > i; ++i )
    {
      for ( j = 0; j < 256 / self->transferTableCount; ++j )
        SetGammaValue(
          a1: self->baseAddress,
          a2: (unsigned __int8)self->redTransferTable[i],
          a3: (unsigned __int8)self->greenTransferTable[i],
          a4: (unsigned __int8)self->blueTransferTable[i],
          a5: self->brightnessLevel);
    }
  }
  else
  {
    depth = *((_DWORD *)-[ATI displayInfo](a1: self, a2: aDisplayinfo) + 6);
    if ( depth == 1 )
    {
      for ( k = 0; k <= 0xFF; ++k )
        SetGammaValue(
          a1: self->baseAddress,
          a2: (unsigned __int8)gamma8[k],
          a3: (unsigned __int8)gamma8[k],
          a4: (unsigned __int8)gamma8[k],
          a5: self->brightnessLevel);
    }
    else if ( depth != 0 && depth <= 4 && depth >= 3 )
    {
      for ( m = 0; m <= 0x1F; ++m )
      {
        for ( n = 0; n <= 7; ++n )
          SetGammaValue(
            a1: self->baseAddress,
            a2: (unsigned __int8)gamma16[m >> 1],
            a3: (unsigned __int8)gamma16[m >> 1],
            a4: (unsigned __int8)gamma16[m >> 1],
            a5: self->brightnessLevel);
      }
    }
  }
  return self;
}
```

## -[ATI setBrightness:token:]

```c
id __cdecl -[ATI setBrightness:token:](ATI *self, SEL _cmd, int brightness, int token)
{
  if ( (unsigned int)brightness > 0x40 )
  {
    IOLog(a1: "Display: Invalid arg to setBrightness: %d\n", brightness);
    return nullptr;
  }
  else
  {
    self->brightnessLevel = brightness;
    -[ATI setGammaTable](a1: self, a2: sel_setGammaTable);
    return self;
  }
}
```

## -[ATI setTransferTable:count:]

```c
id __cdecl -[ATI setTransferTable:count:](ATI *self, SEL _cmd, const unsigned int *table, int count)
{
  _BYTE *queryData; // eax
  char initialShift; // bl
  int chipId; // edx
  int ramdacStyle; // eax
  char *allocatedTransferTables; // eax
  int bitsPerPixel; // eax
  int grayIndex; // esi
  char *redTransferTable; // ebx
  int grayValue; // eax
  int rgbIndex; // esi
  char *greenTransferTable; // [esp+Ch] [ebp-Ch]
  unsigned __int8 ramdacType; // [esp+10h] [ebp-8h]
  char componentShift; // [esp+14h] [ebp-4h]

  queryData = self->queryData;
  ramdacType = queryData[12];
  initialShift = 2;
  if ( self->supportsGrey256 != 0 )
    initialShift = 0;
  chipId = (unsigned __int8)queryData[9];
  if ( chipId != 67 && chipId != 69 )
  {
    if ( ramdacType == 5 )
      goto LABEL_11;
    if ( ramdacType <= 5u )
    {
      if ( ramdacType != 2 )
        goto LABEL_12;
LABEL_11:
      initialShift = 0;
      goto LABEL_12;
    }
    if ( ramdacType == 21 && isATI68880RevC(a1: self->baseAddress) )
      goto LABEL_11;
  }
LABEL_12:
  componentShift = initialShift;
  ramdacStyle = self->ramdacStyle;
  if ( ramdacStyle == 1 )
  {
    componentShift = 0;
  }
  else if ( ramdacStyle == 2 )
  {
    componentShift = 2;
  }
  if ( self->redTransferTable != nullptr )
    IOFree(a1: self->redTransferTable, a2: 3 * self->transferTableCount);
  self->transferTableCount = count;
  allocatedTransferTables = (char *)IOMalloc(a1: 3 * count);
  self->redTransferTable = allocatedTransferTables;
  self->greenTransferTable = &allocatedTransferTables[count];
  self->blueTransferTable = &self->greenTransferTable[count];
  -[ATI displayInfo](a1: self, a2: aDisplayinfo);
  bitsPerPixel = *((_DWORD *)-[ATI displayInfo](a1: self, a2: aDisplayinfo) + 7);
  if ( bitsPerPixel == 1 )
  {
    for ( grayIndex = 0; count > grayIndex; ++grayIndex )
    {
      redTransferTable = self->redTransferTable;
      greenTransferTable = self->greenTransferTable;
      grayValue = LOBYTE(table[grayIndex]) >> componentShift;
      self->blueTransferTable[grayIndex] = grayValue;
      greenTransferTable[grayIndex] = grayValue;
      redTransferTable[grayIndex] = grayValue;
    }
  }
  else if ( bitsPerPixel == 2 )
  {
    for ( rgbIndex = 0; count > rgbIndex; ++rgbIndex )
    {
      self->redTransferTable[rgbIndex] = HIBYTE(table[rgbIndex]) >> componentShift;
      self->greenTransferTable[rgbIndex] = BYTE2(table[rgbIndex]) >> componentShift;
      self->blueTransferTable[rgbIndex] = BYTE1(table[rgbIndex]) >> componentShift;
    }
  }
  else
  {
    IOFree(a1: self->redTransferTable, a2: 3 * count);
    self->redTransferTable = nullptr;
  }
  -[ATI setGammaTable](a1: self, a2: sel_setGammaTable);
  return self;
}
```

## _displayInfoToColorSpace

```c
int __cdecl displayInfoToColorSpace(const IODisplayInfo_Recovered *info)
{
  int colorSpace; // ebx
  unsigned int bitsPerPixel; // eax

  colorSpace = 0;
  bitsPerPixel = info->bitsPerPixel;
  if ( bitsPerPixel == 3 )
    return 2;
  if ( bitsPerPixel > 3 )
  {
    if ( bitsPerPixel != 4 )
      goto LABEL_10;
    return 3;
  }
  else
  {
    if ( bitsPerPixel != 1 )
    {
LABEL_10:
      IOLog(a1: "ATIMach64: displayInfoToColorSpace problem (%d)\n", info->bitsPerPixel);
      IOPanic(a1: "ATIMach64 displayInfoToColorSpace");
      return colorSpace;
    }
    return info->colorSpace != 1;
  }
}
```

## _colorDepthToColorSpace

```c
int __cdecl colorDepthToColorSpace(int depth)
{
  int colorSpace; // eax

  colorSpace = 0;
  switch ( depth )
  {
    case 2:
      colorSpace = 1;
      break;
    case 3:
    case 4:
      colorSpace = 2;
      break;
    case 5:
    case 6:
      colorSpace = 3;
      break;
    default:
      return colorSpace;
  }
  return colorSpace;
}
```

## _displayInfoToColorDepth

```c
int __cdecl displayInfoToColorDepth(const IODisplayInfo_Recovered *info)
{
  int colorDepth; // ebx
  unsigned int bitsPerPixel; // eax

  colorDepth = 0;
  bitsPerPixel = info->bitsPerPixel;
  if ( bitsPerPixel == 3 )
    return 3;
  if ( bitsPerPixel > 3 )
  {
    if ( bitsPerPixel != 4 )
      goto LABEL_10;
    return 6;
  }
  else
  {
    if ( bitsPerPixel != 1 )
    {
LABEL_10:
      IOPanic(a1: "ATIMach64: displayInfoToColorDepth problem");
      return colorDepth;
    }
    return 2;
  }
}
```

## _memSizeToBytes

```c
int __cdecl memSizeToBytes(unsigned __int8 memorySize)
{
  int result; // eax

  switch ( memorySize )
  {
    case 0u:
      result = 0x80000;
      break;
    case 1u:
      result = 0x100000;
      break;
    case 2u:
      result = 0x200000;
      break;
    case 3u:
      result = 0x400000;
      break;
    case 4u:
      result = 6291456;
      break;
    case 5u:
      result = 8386560;
      break;
    default:
      result = 0x200000;
      break;
  }
  return result;
}
```

## +[ATIRageDisplayDriverKernelServerInstance kernelServerInstance]

```c
void **__cdecl +[ATIRageDisplayDriverKernelServerInstance kernelServerInstance](Class self, SEL cmd)
{
  return (void **)&ATIRageDisplayDriver_instance;
}
```

## +[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver]

```c
int __cdecl +[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver](id self, SEL _cmd)
{
  return 500;
}
```

## +[ATI_BIOS ATIPresent:]

```c
char __cdecl +[ATI_BIOS ATIPresent:](Class self, SEL _cmd, unsigned int *biosBase)
{
  unsigned int offset; // ebx
  char signature[12]; // [esp+14h] [ebp-Ch] BYREF

  strcpy(signature, "761295520");
  *biosBase = 786432;
  do
  {
    for ( offset = 0; offset < 129 - (strlen(signature) + 1); ++offset )
    {
      if ( strncmp(__s1: signature, __s2: (const char *)(*biosBase + offset), __n: 9u) == 0 )
        return 1;
    }
    *biosBase += 4096;
  }
  while ( *biosBase <= 0xEFFFF );
  return 0;
}
```

## -[ATI_BIOS init]

```c
id __cdecl -[ATI_BIOS init](ATI_BIOS_Instance_Layout *self, SEL _cmd)
{
  unsigned int biosBase; // esi
  unsigned int offset; // ebx
  char signature[12]; // [esp+14h] [ebp-Ch] BYREF

  strcpy(signature, "761295520");
  for ( biosBase = 786432; biosBase <= 0xEFFFF; biosBase += 4096 )
  {
    for ( offset = 0; offset < 129 - (strlen(signature) + 1); ++offset )
    {
      if ( strncmp(__s1: signature, __s2: (const char *)(offset + biosBase), __n: 9u) == 0 )
        return -[ATI_BIOS_Instance_Layout initAtSegmentAddress:](a1: self, a2: sel_initAtSegmentAddress_, biosBase);
    }
  }
  return nullptr;
}
```

## -[ATI_BIOS initAtSegmentAddress:]

```c
id __cdecl -[ATI_BIOS initAtSegmentAddress:](ATI_BIOS_Instance_Layout *self, SEL _cmd, unsigned int segmentAddress)
{
  objc_super superCall; // [esp+4h] [ebp-8h] BYREF

  self->segmentBase = segmentAddress;
  self->_priv = (ATI_BIOSPrivate *)IOMalloc(a1: 36);
  self->initialized = 1;
  superCall.receiver = self;
  superCall.super_class = (Class)stru_81A8.ext;
  return -[ATI_BIOS_Instance_Layout init](a1: &superCall, a2: sel_init);
}
```

## -[ATI_BIOS free]

```c
id __cdecl -[ATI_BIOS free](ATI_BIOS_Instance_Layout *self, SEL _cmd)
{
  objc_super superCall; // [esp+4h] [ebp-8h] BYREF

  if ( self->initialized != 0 )
    IOFree(a1: self->_priv, a2: 36);
  superCall.receiver = self;
  superCall.super_class = (Class)stru_81A8.ext;
  return -[ATI_BIOS_Instance_Layout free](a1: &superCall, a2: sel_free);
}
```

## -[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:]

```c
int __cdecl -[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        unsigned int mode,
        char gamma,
        unsigned int pitch,
        unsigned int resolution,
        ATI_CRTCRecord *crtTable)
{
  return (int)-[ATI_BIOS_Instance_Layout loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:](
                a1: self,
                a2: sel_loadCRTC_comm_gamma_pitchSize_resolution_crtTable_function_name_,
                mode,
                gamma,
                pitch,
                resolution,
                crtTable,
                0,
                "loadCRTC");
}
```

## -[ATI_BIOS setVGAMode:gamma:]

```c
int __cdecl -[ATI_BIOS setVGAMode:gamma:](ATI_BIOS_Instance_Layout *self, SEL _cmd, char mode, char gamma)
{
  char gammaFlag; // al
  int biosResult; // eax
  ATI_BIOSRegisters registers; // [esp+10h] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, &registers, 1);
  gammaFlag = 0;
  if ( gamma != 0 )
    gammaFlag = 0x80;
  registers.ecx.bytes.low = gammaFlag | (mode == 0);
  biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, &registers, 0);
  if ( biosResult != 0 )
  {
    IOLog(a1: "ATI_BIOS setDisplayMode: ATIbios32() returned %d\n", biosResult);
  }
  else
  {
    if ( registers.eax.bytes.high == 0 )
      return 0;
    IOLog(a1: "ATI_BIOS setDisplayMode: ah = 0x%x on return from ATIbios32()\n", registers.eax.bytes.high);
  }
  return 2;
}
```

## -[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:]

```c
int __cdecl -[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        unsigned int mode,
        char gamma,
        unsigned int pitch,
        unsigned int resolution,
        ATI_CRTCRecord *crtTable)
{
  return (int)-[ATI_BIOS_Instance_Layout loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:](
                a1: self,
                a2: sel_loadCRTC_comm_gamma_pitchSize_resolution_crtTable_function_name_,
                mode,
                gamma,
                pitch,
                resolution,
                crtTable,
                2,
                "loadCRTCSetMode");
}
```

## -[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]

```c
int __cdecl -[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        char enable,
        char vgaAperture,
        unsigned int apertureAddress)
{
  int biosResult; // eax
  unsigned __int16 registerWords[6]; // [esp+14h] [ebp-30h] BYREF
  char apertureFlags; // [esp+20h] [ebp-24h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, registerWords, 5);
  apertureFlags = enable != 0;
  if ( vgaAperture != 0 )
    apertureFlags |= 4u;
  if ( apertureAddress != 0 )
  {
    if ( (apertureAddress & 0xFFFFF) != 0 )
    {
      IOLog(a1: "ATI BIOS setApertureEnable: apertureAdrs misalignment (0x%x)\n", apertureAddress);
      return 3;
    }
    apertureFlags |= 0x80u;
    registerWords[4] = apertureAddress >> 20;
  }
  biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, registerWords, 0);
  if ( biosResult != 0 )
  {
    IOLog(a1: "ATI_BIOS setApertureEnable: ATIbios32() returned %d\n", biosResult);
  }
  else
  {
    if ( HIBYTE(registerWords[2]) == 0 )
      return 0;
    IOLog(a1: "ATI_BIOS setApertureEnable: ah = 0x%x on return from ATIbios32()\n", HIBYTE(registerWords[2]));
  }
  return 2;
}
```

## -[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:]

```c
int __cdecl -[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        unsigned int *hardCoded,
        signed __int8 *smallAperture,
        signed __int8 *address,
        unsigned int *colorDepth,
        unsigned int *memorySize,
        unsigned int *asicType,
        char *asicRev,
        char *name)
{
  int biosResult; // eax
  ATI_BIOSRegisters registerStorage; // [esp+Ch] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, &registerStorage, 6);
  biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, &registerStorage, 0);
  if ( biosResult != 0 )
  {
    IOLog(a1: "ATI_BIOS shortQuery: ATIbios32() returned %d\n", biosResult);
  }
  else
  {
    if ( registerStorage.eax.bytes.high == 0 )
    {
      *hardCoded = registerStorage.eax.bytes.low & 0x3F;
      *smallAperture = (registerStorage.eax.bytes.low & 0x40) != 0;
      *address = registerStorage.eax.bytes.low >> 7;
      *colorDepth = registerStorage.ebx.word;
      *memorySize = registerStorage.ecx.bytes.high;
      *asicType = registerStorage.ecx.bytes.low;
      *asicRev = registerStorage.edx.bytes.high;
      *name = registerStorage.edx.bytes.low;
      return 0;
    }
    IOLog(a1: "ATI_BIOS shortQuery: ah = 0x%x on return from ATIbios32()\n", registerStorage.eax.bytes.high);
  }
  return 2;
}
```

## -[ATI_BIOS querySize:size:]

```c
int __cdecl -[ATI_BIOS querySize:size:](ATI_BIOS_Instance_Layout *self, SEL _cmd, char query, unsigned int *size)
{
  *size = 4096;
  return 0;
}
```

## -[ATI_BIOS deviceQuery:bufferSize:buffer:]

```c
int __cdecl -[ATI_BIOS deviceQuery:bufferSize:buffer:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        char query,
        unsigned int bufferSize,
        void *buffer)
{
  int result; // eax
  int biosResult; // eax
  unsigned __int16 registerWords[6]; // [esp+10h] [ebp-30h] BYREF
  char queryFlag; // [esp+1Ch] [ebp-24h]
  unsigned __int16 queryBufferOffset; // [esp+20h] [ebp-20h]

  if ( self->initialized == 0 )
    return 1;
  bzero(a1: buffer, a2: bufferSize);
  -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, registerWords, 9);
  queryFlag = query == 0;
  result = (int)-[ATI_BIOS_Instance_Layout createDataSegment:size:](
                  a1: self,
                  a2: sel_createDataSegment_size_,
                  buffer,
                  bufferSize);
  if ( result == 0 )
  {
    queryBufferOffset = 136;
    registerWords[4] = 0;
    biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, registerWords, 1);
    if ( biosResult != 0 )
    {
      IOLog(a1: "ATI_BIOS deviceQuery: ATIbios32() returned %d\n", biosResult);
    }
    else
    {
      if ( HIBYTE(registerWords[2]) == 0 )
        return 0;
      IOLog(a1: "ATI_BIOS deviceQuery: ah = 0x%x on return from ATIbios32()\n", HIBYTE(registerWords[2]));
    }
    return 2;
  }
  return result;
}
```

## -[ATI_BIOS setDPMSMode:]

```c
int __cdecl -[ATI_BIOS setDPMSMode:](ATI_BIOS_Instance_Layout *self, SEL _cmd, unsigned int mode)
{
  int biosResult; // eax
  ATI_BIOSRegisters registers; // [esp+Ch] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  if ( mode <= 4 )
  {
    -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, &registers, 12);
    registers.ecx.bytes.low = mode & 3;
    biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, &registers, 0);
    if ( biosResult != 0 )
    {
      IOLog(a1: "ATI_BIOS Set DPMS Mode: ATIbios32() returned %d\n", biosResult);
      return 2;
    }
    else
    {
      return 0;
    }
  }
  else
  {
    IOLog(a1: "ATI_BIOS set DPMS mode: %x not valid mode\n", mode);
    return 3;
  }
}
```

## -[ATI_BIOS getDPMSMode:]

```c
int __cdecl -[ATI_BIOS getDPMSMode:](ATI_BIOS_Instance_Layout *self, SEL _cmd, unsigned int *mode)
{
  int biosResult; // eax
  unsigned __int8 registerPrefix[12]; // [esp+Ch] [ebp-30h] BYREF
  unsigned __int8 dpmsModeByte; // [esp+18h] [ebp-24h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, registerPrefix, 13);
  dpmsModeByte = 0;
  biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, registerPrefix, 0);
  if ( biosResult != 0 )
  {
    IOLog(a1: "ATI_BIOS Get DPMS Mode: ATIbios32() returned %d\n", biosResult);
    return 2;
  }
  else
  {
    *mode = dpmsModeByte & 3;
    return 0;
  }
}
```

## -[ATI_BIOS setAPMState:]

```c
int __cdecl -[ATI_BIOS setAPMState:](ATI_BIOS_Instance_Layout *self, SEL _cmd, unsigned int state)
{
  int biosResult; // eax
  ATI_BIOSRegisters registers; // [esp+Ch] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  if ( state <= 3 )
  {
    -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, &registers, 14);
    registers.ecx.bytes.low = state & 3;
    biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, &registers, 0);
    if ( biosResult != 0 )
    {
      IOLog(a1: "ATI_BIOS Set APM State: ATIbios32() returned %d\n", biosResult);
      return 2;
    }
    else
    {
      return 0;
    }
  }
  else
  {
    IOLog(a1: "ATI_BIOS set APM state: %x not valid mode\n", state);
    return 3;
  }
}
```

## -[ATI_BIOS getAPMState:]

```c
int __cdecl -[ATI_BIOS getAPMState:](ATI_BIOS_Instance_Layout *self, SEL _cmd, unsigned int *state)
{
  int biosResult; // eax
  unsigned __int8 registerPrefix[12]; // [esp+Ch] [ebp-30h] BYREF
  unsigned __int8 apmStateByte; // [esp+18h] [ebp-24h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, registerPrefix, 15);
  apmStateByte = 0;
  biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, registerPrefix, 0);
  if ( biosResult != 0 )
  {
    IOLog(a1: "ATI_BIOS Get APM State: ATIbios32() returned %d\n", biosResult);
    return 2;
  }
  else
  {
    *state = apmStateByte & 3;
    return 0;
  }
}
```

## -[ATI_BIOS getIOBaseAddress:relocatable:]

```c
int __cdecl -[ATI_BIOS getIOBaseAddress:relocatable:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        unsigned int *address,
        signed __int8 *relocatable)
{
  int biosResult; // eax
  unsigned __int8 registerPrefix[12]; // [esp+Ch] [ebp-30h] BYREF
  unsigned __int8 relocatableFlag; // [esp+18h] [ebp-24h]
  unsigned int ioBaseAddress; // [esp+1Ch] [ebp-20h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, registerPrefix, 18);
  relocatableFlag = 0;
  biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, registerPrefix, 0);
  if ( biosResult != 0 )
  {
    IOLog(a1: "ATI_BIOS Short Query 2: ATIbios32() returned %d\n", biosResult);
    return 2;
  }
  else
  {
    *relocatable = relocatableFlag & 1;
    *address = ioBaseAddress;
    return 0;
  }
}
```

## -[ATI_BIOS getRefreshRate:]

```c
int __cdecl -[ATI_BIOS getRefreshRate:](ATI_BIOS_Instance_Layout *self, SEL _cmd, char *refreshRate)
{
  int result; // eax
  int biosResult; // eax
  unsigned __int8 registerPrefix[8]; // [esp+8h] [ebp-30h] BYREF
  unsigned __int16 ebxInput; // [esp+10h] [ebp-28h]
  unsigned __int16 queryBufferOffset; // [esp+18h] [ebp-20h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, registerPrefix, 21);
  LOBYTE(ebxInput) = 0;
  result = (int)-[ATI_BIOS_Instance_Layout createDataSegment:size:](
                  a1: self,
                  a2: sel_createDataSegment_size_,
                  refreshRate,
                  20);
  if ( result == 0 )
  {
    queryBufferOffset = 136;
    ebxInput = 0;
    biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, registerPrefix, 1);
    if ( biosResult != 0 )
    {
      IOLog(a1: "ATI_BIOS getRefreshRate: ATIbios32() returned %d\n", biosResult);
    }
    else
    {
      if ( registerPrefix[5] == 0 )
        return 0;
      IOLog(a1: "ATI_BIOS getRefreshRate: ah = 0x%x on return from ATIbios32()\n", registerPrefix[5]);
    }
    return 2;
  }
  return result;
}
```

## -[ATI_BIOS changeRefreshRate:]

```c
int __cdecl -[ATI_BIOS changeRefreshRate:](ATI_BIOS_Instance_Layout *self, SEL _cmd, char *refreshRate)
{
  return 3;
}
```

## -[ATI_BIOS initBIOSBuf:function:]

```c
void __cdecl -[ATI_BIOS initBIOSBuf:function:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        ATI_BIOSRegisters *registers,
        unsigned int function)
{
  -[ATI_BIOS_Instance_Layout setupCodeSegments](a1: self, a2: sel_setupCodeSegments);
  bzero(a1: registers, a2: 0x30u);
  registers->eax.bytes.low = function;
  registers->code_selector = 128;
  registers->data_selector = 16;
  registers->entry_offset = 100;
  registers->ebp.dword = (unsigned __int16)ATI_Bios_StackOffset >> 1;
}
```

## -[ATI_BIOS setupCodeSegments]

The raw reference disassembly encodes the code32 descriptor base as 0xC0002E48; the v235 candidate encodes 0xC0002E7C. These are image-specific linked `_bios16` addresses. The candidate Hex-Rays pseudocode renders its immediate bytes as `strcpy("|.")`; use raw disassembly for the exact base value and keep the source symbol-relative.

```c
// Equivalent descriptor save/setup flow. The reference's immediate BIOS entry address and this build's strcpy bytes reflect different linked __bios16 locations; keep symbolic address resolution rather than forcing the reference constant.
void __cdecl -[ATI_BIOS setupCodeSegments](ATI_BIOS_Instance_Layout *self, SEL _cmd)
{
  ATI_BIOSPrivate_Layout *priv; // esi
  ATI_SegmentDescriptor *code16Descriptor; // eax
  ATI_SegmentDescriptor *code32Descriptor; // edx
  unsigned __int32 code16BaseAdjusted; // edx
  ATI_SegmentDescriptor *biosCodeDescriptor; // eax
  ATI_SegmentDescriptor *stackDescriptor; // ebx
  void *stackAllocation; // eax
  unsigned __int32 stackBaseAdjusted; // eax
  ATI_SegmentDescriptor *savedStackDescriptor; // [esp+Ch] [ebp-4h]

  priv = (ATI_BIOSPrivate_Layout *)self->_priv;
  code16Descriptor = (ATI_SegmentDescriptor *)(gdt + 128);
  code32Descriptor = (ATI_SegmentDescriptor *)(gdt + 144);
  savedStackDescriptor = (ATI_SegmentDescriptor *)(gdt + 152);
  priv->saved_code_descriptor0 = *(ATI_SegmentDescriptor *)(gdt + 128);
  priv->saved_code_descriptor1 = *code32Descriptor;
  priv->saved_stack_descriptor = *savedStackDescriptor;
  code16BaseAdjusted = self->segmentBase - 0x40000000;
  code16Descriptor->base_low = self->segmentBase;
  code16Descriptor->base_mid = BYTE2(code16BaseAdjusted);
  code16Descriptor->base_high = HIBYTE(code16BaseAdjusted);
  code16Descriptor->access &= 0xE0u;
  code16Descriptor->access |= 0x1Au;
  code16Descriptor->access &= 0x9Fu;
  code16Descriptor->access = code16Descriptor->access;
  code16Descriptor->access |= 0x80u;
  code16Descriptor->limit_flags &= ~0x40u;
  code16Descriptor->limit_flags &= ~0x80u;
  code16Descriptor->limit_low = -1;
  code16Descriptor->limit_flags &= 0xF0u;
  code16Descriptor->limit_flags = code16Descriptor->limit_flags;
  biosCodeDescriptor = (ATI_SegmentDescriptor *)(gdt + 144);
  *(_WORD *)(gdt + 146) = 11848;
  biosCodeDescriptor->base_mid = 0;
  biosCodeDescriptor->base_high = -64;
  biosCodeDescriptor->access &= 0xE0u;
  biosCodeDescriptor->access |= 0x1Au;
  biosCodeDescriptor->access &= 0x9Fu;
  biosCodeDescriptor->access = biosCodeDescriptor->access;
  biosCodeDescriptor->access |= 0x80u;
  biosCodeDescriptor->limit_flags |= 0x40u;
  biosCodeDescriptor->limit_flags &= ~0x80u;
  biosCodeDescriptor->limit_low = -1;
  biosCodeDescriptor->limit_flags &= 0xF0u;
  biosCodeDescriptor->limit_flags = biosCodeDescriptor->limit_flags;
  stackDescriptor = (ATI_SegmentDescriptor *)(gdt + 152);
  stackAllocation = (void *)IOMalloc(a1: 2048);
  priv->stack_address = (unsigned __int32)stackAllocation;
  bzero(a1: stackAllocation, a2: 0x800u);
  stackBaseAdjusted = priv->stack_address - 0x40000000;
  stackDescriptor->base_low = priv->stack_address;
  stackDescriptor->base_mid = BYTE2(stackBaseAdjusted);
  stackDescriptor->base_high = HIBYTE(stackBaseAdjusted);
  stackDescriptor->access &= 0xE0u;
  stackDescriptor->access |= 0x12u;
  stackDescriptor->access &= 0x9Fu;
  stackDescriptor->access = stackDescriptor->access;
  stackDescriptor->access |= 0x80u;
  stackDescriptor->limit_flags |= 0x40u;
  stackDescriptor->limit_flags &= ~0x80u;
  stackDescriptor->limit_low = 2047;
  stackDescriptor->limit_flags &= 0xF0u;
  stackDescriptor->limit_flags = stackDescriptor->limit_flags;
  stackDescriptor->limit_flags &= ~0x40u;
  ATI_Bios_StackOffset = 2048;
  ATI_Bios_StackSelector = 152;
}
```
## -[ATI_BIOS restoreCodeSegments]

```c
void __cdecl -[ATI_BIOS restoreCodeSegments](ATI_BIOS_Instance_Layout *self, SEL _cmd)
{
  ATI_BIOSPrivate_Layout *priv; // eax
  ATI_SegmentDescriptor *code16Descriptor; // ecx
  ATI_SegmentDescriptor *stack16Descriptor; // ebx

  priv = (ATI_BIOSPrivate_Layout *)self->_priv;
  code16Descriptor = (ATI_SegmentDescriptor *)(gdt + 144);
  stack16Descriptor = (ATI_SegmentDescriptor *)(gdt + 152);
  *(ATI_SegmentDescriptor *)(gdt + 128) = priv->saved_code_descriptor0;
  *code16Descriptor = priv->saved_code_descriptor1;
  *stack16Descriptor = priv->saved_stack_descriptor;
  IOFree(a1: priv->stack_address, a2: 2048);
}
```

## -[ATI_BIOS createDataSegment:size:]

```c
int __cdecl -[ATI_BIOS createDataSegment:size:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        unsigned int address,
        unsigned int size)
{
  unsigned __int8 *data16; // ecx
  unsigned int limitValue; // eax

  if ( size <= 0x10000 )
  {
    *(ATI_SegmentDescriptor *)self->_priv->saved_data_descriptor = *(ATI_SegmentDescriptor *)(gdt + 136);
    data16 = (unsigned __int8 *)(gdt + 136);
    *(_WORD *)(gdt + 138) = address;
    data16[4] = (address - 0x40000000) >> 16;
    data16[7] = (address - 0x40000000) >> 24;
    data16[5] &= 0xE0u;
    data16[5] |= 0x12u;
    data16[5] &= 0x9Fu;
    data16[5] = data16[5];
    data16[5] |= 0x80u;
    data16[6] |= 0x40u;
    limitValue = size - 1;
    if ( size - 1 > 0xFFFFF )
    {
      data16[6] |= 0x80u;
      *(_WORD *)data16 = (((size + 4095) & 0xFFFFF000) - 4096) >> 12;
      limitValue = (((size + 4095) & 0xFFFFF000) - 4096) >> 28;
    }
    else
    {
      data16[6] &= ~0x80u;
      *(_WORD *)data16 = limitValue;
      LOBYTE(limitValue) = BYTE2(limitValue) & 0xF;
    }
    data16[6] &= 0xF0u;
    data16[6] |= limitValue;
    return 0;
  }
  else
  {
    IOLog(a1: "ATI_BIOS: Data Segment size exceeded (0x%x)\n", size);
    return 3;
  }
}
```

## -[ATI_BIOS restoreDataSegment]

```c
void __cdecl -[ATI_BIOS restoreDataSegment](ATI_BIOS_Instance_Layout *self, SEL _cmd)
{
  *(_QWORD *)(gdt + 136) = *(_QWORD *)self->_priv->saved_data_descriptor;
}
```

## -[ATI_BIOS doBios:dataSeg:]

```c
int __cdecl -[ATI_BIOS doBios:dataSeg:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        ATI_BIOSRegisters *registers,
        char dataSegment)
{
  int biosCallResult; // esi

  biosCallResult = ATIbios16(a1: (int)registers);
  -[ATI_BIOS_Instance_Layout restoreCodeSegments](a1: self, a2: sel_restoreCodeSegments);
  if ( dataSegment != 0 )
    -[ATI_BIOS_Instance_Layout restoreDataSegment](a1: self, a2: sel_restoreDataSegment);
  return biosCallResult;
}
```

## -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]

```c
// Equivalent BIOS command flow and return codes: initialized/mode guards, command block setup, optional resolution-129 data segment setup, BIOS call, and status logging. Remaining diff is register choice/layout.
int __cdecl -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:](
        ATI_BIOS_Instance_Layout *self,
        SEL _cmd,
        unsigned int mode,
        char gamma,
        unsigned int pitch,
        unsigned int resolution,
        ATI_CRTCRecord *crtTable,
        unsigned __int8 function,
        const char *name)
{
  int result; // eax
  char gammaFlag; // al
  int biosResult; // eax
  char restoreData; // [esp+Ch] [ebp-38h]
  ATI_BIOSRegisters registers; // [esp+14h] [ebp-30h] BYREF

  restoreData = 0;
  if ( self->initialized == 0 )
    return 1;
  if ( resolution == 128 )
    return 3;
  -[ATI_BIOS_Instance_Layout initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, &registers, function);
  gammaFlag = 0;
  if ( gamma != 0 )
    gammaFlag = 16;
  registers.ecx.bytes.low = ((_BYTE)pitch << 6) | mode | gammaFlag;
  registers.ecx.bytes.high = resolution;
  if ( resolution == 129 )
  {
    result = (int)-[ATI_BIOS_Instance_Layout createDataSegment:size:](
                    a1: self,
                    a2: sel_createDataSegment_size_,
                    crtTable,
                    30);
    if ( result != 0 )
      return result;
    registers.edx.word = 136;
    registers.ebx.word = 0;
    restoreData = 1;
  }
  biosResult = (int)-[ATI_BIOS_Instance_Layout doBios:dataSeg:](
                      a1: self,
                      a2: sel_doBios_dataSeg_,
                      &registers,
                      restoreData);
  if ( biosResult != 0 )
  {
    IOLog(a1: "ATI_BIOS %s: ATIbios32() returned %d\n", name, biosResult);
  }
  else
  {
    if ( registers.eax.bytes.high == 0 )
      return 0;
    IOLog(a1: "ATI_BIOS %s: ah = 0x%x on return from ATIbios32()\n", name, registers.eax.bytes.high);
  }
  return 2;
}
```

## _ATIbios16

```c
int __cdecl ATIbios16(ATI_BIOSRegisters *registers)
{
  kernDataSel = 16;
  if ( registers->entry_offset > 0xFFFF )
  {
    IOLog(a1: "ATIbios16: invalid offset (0x%x)\n", registers->entry_offset);
    return -1;
  }
  else
  {
    ATI_Bios_Offset = LOWORD(registers->entry_offset);
    ATI_Bios_Selector = registers->code_selector;
    registers->code_selector = 144;
    registers->entry_offset = 0;
    ((void (__stdcall *)(ATI_BIOSRegisters *))_ATIbios32)(a1: registers);
    return 0;
  }
}
```
