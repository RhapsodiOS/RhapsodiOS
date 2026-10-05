# Rebuilt IDA pseudocode export (v213)

IDA 9.4 Hex-Rays decompilation of the final v213 native reconstruction candidate.

## -[ATI initFromDeviceDescription:] (0x0-0x6e4)

```c
id __cdecl -[ATI initFromDeviceDescription:](ATI *self, SEL a2, id a3)
{
  id v3; // eax
  const char *v5; // eax
  const char *v6; // eax
  ATI_BIOS *v7; // eax
  id v8; // ecx
  unsigned int v9; // ecx
  unsigned __int32 v10; // eax
  unsigned __int32 v11; // eax
  id v12; // ecx
  const char *v13; // edi
  unsigned __int32 v14; // eax
  unsigned __int8 *queryData; // edi
  const char *v16; // eax
  const char *v17; // eax
  int v18; // eax
  const char *v19; // edi
  const char *v20; // eax
  const char *v21; // eax
  const char *v22; // eax
  _DWORD *v23; // eax
  id v24; // ecx
  unsigned int v25; // ecx
  unsigned __int16 v26; // dx
  unsigned __int32 v27; // eax
  unsigned int v28; // ecx
  id v29; // eax
  const char *v30; // [esp-Ch] [ebp-54h]
  const char *v31; // [esp-Ch] [ebp-54h]
  const char *v32; // [esp-8h] [ebp-50h]
  const char *v33; // [esp-4h] [ebp-4Ch]
  id v34; // [esp-4h] [ebp-4Ch]
  unsigned int v35; // [esp+Ch] [ebp-3Ch]
  const char *v36; // [esp+Ch] [ebp-3Ch]
  const char *v37; // [esp+Ch] [ebp-3Ch]
  id v38; // [esp+Ch] [ebp-3Ch]
  id v39; // [esp+18h] [ebp-30h]
  int v40; // [esp+1Ch] [ebp-2Ch] BYREF
  objc_super v41; // [esp+20h] [ebp-28h] BYREF
  char __dst[32]; // [esp+28h] [ebp-20h] BYREF

  self->engineStarted = 0;
  if ( objc_msgSend(a1: a3, a2: aGetpcideviceFu, 0, 0, 0) != nullptr )
  {
    v3 = -[ATI name](a1: self, a2: aName);
    IOLog(a1: "ATIRage: ATIRage adapter not found\n", v3);
    v41.receiver = self;
    v41.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v41, a2: sel_free);
  }
  if ( +[ATI_BIOS ATIPresent:](a1: aAtiBios, a2: sel_ATIPresent_, &v40) == 0 )
  {
    v5 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: ATI BIOS not found\n", v5);
    v41.receiver = self;
    v41.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v41, a2: sel_free);
  }
  if ( -[ATI fixDeviceDescriptionForPCI:](a1: self, a2: sel_fixDeviceDescriptionForPCI_, a3) == 0 )
  {
    v6 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Configuration error. Aborting...\n", v6);
    v41.receiver = self;
    v41.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v41, a2: sel_free);
  }
  v41.receiver = self;
  v41.super_class = (Class)stru_8158.super_class;
  if ( -[ATI initFromDeviceDescription:](a1: &v41, a2: sel_initFromDeviceDescription_, a3) == nullptr )
    goto LABEL_8;
  v7 = +[ATI_BIOS alloc](a1: aAtiBios, a2: aAlloc);
  v8 = -[ATI_BIOS initAtSegmentAddress:](a1: v7, a2: sel_initAtSegmentAddress_);
  self->atiBios = v8;
  if ( v8 == nullptr )
    goto LABEL_8;
  self->queryDataSize = 0;
  objc_msgSend(a1: self->atiBios, a2: sel_getIOBaseAddress_relocatable_, &self->baseAddress, &self->relocatableIO);
  if ( self->relocatableIO != 0 )
    v9 = self->baseAddress + 132;
  else
    v9 = self->baseAddress + 17408;
  v10 = __indword(v9);
  v35 = v10;
  __outdword(v9, 0x55555555u);
  _InterlockedIncrement(&resetEngineWriteCounter);
  v11 = __indword(v9);
  if ( v11 != 1431655765 )
  {
    v12 = -[ATI name](a1: self, a2: aName);
    v13 = "%s: Rage/Rage II/Rage Pro BIOS not found.\n";
LABEL_46:
    v34 = v12;
    v32 = v13;
    goto LABEL_47;
  }
  __outdword(v9, 0xAAAAAAAA);
  _InterlockedIncrement(&resetEngineWriteCounter);
  v14 = __indword(v9);
  if ( v14 != -1431655766 )
  {
    v12 = -[ATI name](a1: self, a2: aName);
    v13 = "%s: Mach64/Rage failed second regsiter test.\n";
    goto LABEL_46;
  }
  __outdword(v9, v35);
  _InterlockedIncrement(&resetEngineWriteCounter);
  if ( -[ATI getQueryData](a1: self, a2: sel_getQueryData) != 0 )
  {
LABEL_8:
    v41.receiver = self;
    v41.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v41, a2: sel_free);
  }
  queryData = (unsigned __int8 *)self->queryData;
  self->supportsGamma = (queryData[20] & 0x40) != 0;
  self->supportsGrey256 = (queryData[20] & 0x20) != 0;
  self->vramBytes = -[ATI displayMemorySize](a1: self, a2: sel_displayMemorySize);
  v16 = (const char *)IOFindNameForValue(a1: queryData[9], a2: &ATI_AsicTypeValues);
  strcpy(__dst, __src: v16);
  if ( queryData[9] == 0xD7 )
  {
    v36 = (const char *)IOFindNameForValue(a1: queryData[8], a2: &ATI_AsicSubTypeValues);
    strcat(__s1: __dst, __s2: v36);
  }
  v17 = (const char *)-[ATI name](a1: self, a2: aName);
  IOLog(a1: "%s: ATI Rage/Rage II/Rage Pro Found!\n", v17);
  v18 = IOFindNameForValue(a1: queryData[11], a2: &ATI_memSizeValues);
  v19 = "NO";
  if ( self->supportsGamma != 0 )
    v19 = "YES";
  v33 = (const char *)v18;
  v20 = (const char *)-[ATI name](a1: self, a2: aName);
  IOLog(a1: "%s: Type %s.  Gamma: %s.  Memory: %s.\n", v20, __dst, v19, v33);
  v39 = objc_msgSend(a1: a3, a2: aConfigtable);
  self->ramdacStyle = 0;
  v37 = (const char *)objc_msgSend(a1: v39, a2: aValueforstring, "RAMDAC Style");
  if ( v37 != nullptr )
  {
    if ( strcmp(v37, "Sparse") == 0 )
    {
      self->ramdacStyle = 1;
    }
    else if ( strcmp(v37, "Dense") == 0 )
    {
      self->ramdacStyle = 2;
    }
    if ( self->ramdacStyle != 0 )
    {
      v21 = (const char *)-[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: ramdacStyle from table = %s\n", v21, v37);
    }
    objc_msgSend(a1: v39, a2: aFreestring, v37);
  }
  v38 = objc_msgSend(a1: v39, a2: aValueforstring, "Display Mode");
  if ( v38 != nullptr )
  {
    if ( -[ATI parseModeString:](a1: self, a2: sel_parseModeString_, v38) != 0 )
      return objc_msgSend(a1: self, a2: v30);
    if ( dword_42F4[34 * self->modeNumber] == 4 )
    {
      v31 = (const char *)IOFindNameForValue(a1: self->colorConfig, a2: &colorConfigValues);
      v22 = (const char *)-[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: 24 Bit Color Configuration = %s\n", v22, v31);
    }
    if ( objc_msgSend(a1: self->atiBios, a2: sel_setApertureEnable_VGAAperture_apertureAdrs_, 1, 0, 0) != nullptr )
      return objc_msgSend(a1: self, a2: v30);
    v23 = objc_msgSend(a1: a3, a2: aMemoryrangelis);
    v24 = -[ATI mapFrameBufferAtPhysicalAddress:length:](a1: self, a2: aMapframebuffer, *v23, 0x800000);
    self->vram = v24;
    if ( v24 != nullptr )
    {
      if ( self->relocatableIO != 0 )
        v25 = self->baseAddress + 160;
      else
        v25 = self->baseAddress + 24576;
      v26 = v25;
      v27 = __indword(v25);
      v28 = v27;
      LOBYTE(v28) = v27 & 0xEF;
      __outdword(v26, v28);
      _InterlockedIncrement(&resetEngineWriteCounter);
      register_base_address = (int)self->vram + 8387584;
      -[ATI updateModeList](a1: self, a2: sel_updateModeList);
      v41.receiver = self;
      v41.super_class = (Class)stru_8158.super_class;
      v29 = -[ATI displayInfo](a1: &v41, a2: aDisplayinfo);
      bcopy(a1: (char *)&AtiModeList + 136 * self->modeNumber, a2: v29, a3: 0x88u);
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
      v12 = -[ATI name](a1: self, a2: aName);
      v13 = "%s: VRAM test failure, aborting\n";
    }
    else
    {
      v12 = -[ATI name](a1: self, a2: aName);
      v13 = "%s: Unable to map frame buffer\n";
    }
    goto LABEL_46;
  }
  -[ATI name](a1: self, a2: aName);
LABEL_47:
  IOLog(a1: v32, v34);
  v30 = sel_free;
  return objc_msgSend(a1: self, a2: v30);
}
```

## -[ATI fixDeviceDescriptionForPCI:] (0x6e4-0xd13)

```c
char __cdecl -[ATI fixDeviceDescriptionForPCI:](ATI *self, SEL a2, id a3)
{
  int v3; // edi
  int v4; // esi
  int v5; // eax
  int v6; // eax
  unsigned int j; // ebx
  unsigned int k; // ebx
  unsigned int m; // ebx
  int v10; // esi
  unsigned int n; // ebx
  int v12; // esi
  int v13; // eax
  int v14; // eax
  int v15; // ecx
  int v16; // edx
  id v17; // eax
  const char *v18; // eax
  __int32 v19; // eax
  unsigned int ii; // ebx
  unsigned int v21; // esi
  int v22; // edi
  id v23; // eax
  unsigned int v24; // esi
  unsigned int v25; // ebx
  id v26; // eax
  id v28; // [esp-14h] [ebp-128h]
  id v29; // [esp-14h] [ebp-128h]
  int v30; // [esp-Ch] [ebp-120h]
  int v31; // [esp+Ch] [ebp-108h]
  int v32; // [esp+Ch] [ebp-108h]
  unsigned int v33; // [esp+24h] [ebp-F0h]
  unsigned int v34; // [esp+28h] [ebp-ECh]
  int v35; // [esp+30h] [ebp-E4h]
  int v36; // [esp+30h] [ebp-E4h]
  int v37; // [esp+30h] [ebp-E4h]
  int v38; // [esp+30h] [ebp-E4h]
  unsigned int v39; // [esp+30h] [ebp-E4h]
  unsigned int i; // [esp+34h] [ebp-E0h]
  id v41; // [esp+38h] [ebp-DCh]
  int v42; // [esp+3Ch] [ebp-D8h] BYREF
  char v43; // [esp+43h] [ebp-D1h]
  _DWORD v44[18]; // [esp+44h] [ebp-D0h] BYREF
  _DWORD v45[18]; // [esp+8Ch] [ebp-88h] BYREF
  _DWORD v46[16]; // [esp+D4h] [ebp-40h] BYREF

  v33 = 0;
  v43 = 1;
  v41 = -[ATI class](a1: self, a2: aClass);
  v34 = 0;
  for ( i = 16; i <= 0x27; i += 4 )
  {
    objc_msgSend(a1: v41, a2: aGetpciconfigda, v44, (unsigned __int8)i, a3);
    v3 = -16;
    if ( (v44[0] & 1) != 0 )
      v3 = -4;
    objc_msgSend(a1: v41, a2: aSetpciconfigda, v44[0] | v3, (unsigned __int8)i, a3);
    objc_msgSend(a1: v41, a2: aGetpciconfigda, &v42, (unsigned __int8)i, a3);
    objc_msgSend(a1: v41, a2: aSetpciconfigda, v44[0], (unsigned __int8)i, a3);
    v4 = v42 & v3;
    if ( (v42 & v3) != 0 )
    {
      if ( (v44[0] & 1) != 0 )
      {
        v5 = 2 * v33;
        v45[v5] = v44[0] & v3;
        v45[v5 + 1] = -v4;
        v44[++v33] = i;
      }
      else
      {
        v31 = 2 * v34;
        v46[v31] = v44[0] & v3;
        v46[v31 + 1] = -v4;
        v44[v34++ + 10] = i;
      }
    }
  }
  v6 = 1;
  for ( j = 0; v34 > j; ++j )
  {
    if ( v46[2 * j] <= 0x3FFFFFu )
      v6 = 0;
  }
  for ( k = 0; v33 > k; ++k )
  {
    if ( v45[2 * k] <= 0xFFu )
      v6 = 0;
  }
  if ( v6 == 0 )
  {
    v35 = *(_DWORD *)objc_msgSend(a1: a3, a2: aMemoryrangelis);
    for ( m = 0; v34 > m; ++m )
    {
      v10 = v46[2 * m + 1];
      v36 = (v35 + v10 - 1) & -v10;
      v46[2 * m] = v36;
      objc_msgSend(a1: v41, a2: aSetpciconfigda, v36, LOBYTE(v44[m + 10]), a3);
      v35 = v10 + v36;
    }
    v37 = *(_DWORD *)objc_msgSend(a1: a3, a2: aPortrangelist);
    for ( n = 0; v33 > n; ++n )
    {
      v12 = v45[2 * n + 1];
      v38 = (v37 + v12 - 1) & -v12;
      v45[2 * n] = v38;
      objc_msgSend(a1: v41, a2: aSetpciconfigda, v38, LOBYTE(v44[n + 1]), a3);
      v37 = v12 + v38;
    }
  }
  v13 = 2 * v34;
  v46[v13] = 655360;
  v46[v13 + 1] = 0x20000;
  v14 = 8 * v34 + 8;
  *(_DWORD *)((char *)v46 + v14) = 786432;
  *(_DWORD *)((char *)&v46[1] + v14) = 0x10000;
  v32 = 2 * v33;
  v45[v32] = 944;
  v45[v32 + 1] = 48;
  v15 = 8 * v33 + 8;
  *(_DWORD *)((char *)v45 + v15) = 258;
  *(_DWORD *)((char *)&v45[1] + v15) = 1;
  v16 = 8 * v33 + 16;
  *(_DWORD *)((char *)v45 + v16) = 18152;
  *(_DWORD *)((char *)&v45[1] + v16) = 1;
  objc_msgSend(a1: a3, a2: aSetmemoryrange, 0, 0);
  if ( objc_msgSend(a1: a3, a2: aSetmemoryrange, v46, v34 + 2) != nullptr )
  {
    v39 = start_base_address;
    self->overrideStartBaseAddress = 0;
    v17 = objc_msgSend(a1: a3, a2: aConfigtable);
    if ( v17 != nullptr )
    {
      v18 = (const char *)objc_msgSend(a1: v17, a2: aValueforstring, "FB Address");
      if ( v18 != nullptr && *v18 != 0 )
      {
        v19 = strtol(__str: v18, __endptr: nullptr, __base: 16);
        if ( (v19 & 0x7F000000u) > 0x3FFFFFF )
        {
          v39 = v19 & 0x7F000000;
          self->overrideStartBaseAddress = 1;
        }
      }
    }
    if ( v34 != 0 )
    {
      for ( ii = 0; ii < v34; ++ii )
      {
        v21 = v39;
        if ( v39 <= 0xFEFFFFFF )
        {
          v22 = 2 * ii;
          do
          {
            v46[v22] = v21;
            objc_msgSend(a1: a3, a2: aSetmemoryrange, 0, 0);
            if ( objc_msgSend(a1: a3, a2: aSetmemoryrange, v46, ii) == nullptr )
              break;
            v21 += v46[v22 + 1];
          }
          while ( v21 <= 0xFEFFFFFF );
        }
      }
    }
    objc_msgSend(a1: a3, a2: aSetmemoryrange, 0, 0);
    v23 = objc_msgSend(a1: a3, a2: aSetmemoryrange, v46, v34 + 2);
    if ( v23 != nullptr )
    {
      -[ATI stringFromReturn:](a1: self, a2: aStringfromretu, v23);
      v28 = -[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: Error in setMemoryRangeList (%s)\n", v28);
      return 0;
    }
    if ( v34 != 0 )
    {
      v24 = 0;
      v25 = 16;
      do
      {
        v30 = v46[2 * v24++];
        objc_msgSend(a1: v41, a2: aSetpciconfigda, v30, (unsigned __int8)v25, a3);
        v25 += 4;
      }
      while ( v34 > v24 && v25 <= 0x27 );
    }
  }
  objc_msgSend(a1: a3, a2: aSetportrangeli, 0, 0);
  v26 = objc_msgSend(a1: a3, a2: aSetportrangeli, v45, v33 + 3);
  if ( v26 == nullptr )
    return v43;
  -[ATI stringFromReturn:](a1: self, a2: aStringfromretu, v26);
  v29 = -[ATI name](a1: self, a2: aName);
  IOLog(a1: "%s: Error in setPortRangeList (%s)\n", v29);
  return 0;
}
```

## -[ATI getQueryData] (0xd14-0xe44)

```c
int __cdecl -[ATI getQueryData](ATI *self, SEL a2)
{
  id v2; // eax
  const char *v3; // eax
  unsigned __int16 *v4; // esi
  id v5; // eax
  unsigned int v6; // eax
  void *v7; // eax
  const char *v9; // eax
  const char *v10; // [esp-Ch] [ebp-18h]
  const char *v11; // [esp-4h] [ebp-10h]
  int v12; // [esp+8h] [ebp-4h] BYREF

  v12 = 0;
  if ( self->queryDataSize != 0 )
  {
    IOFree(a1: self->queryData, a2: self->queryDataSize);
    self->queryDataSize = 0;
  }
  v2 = objc_msgSend(a1: self->atiBios, a2: sel_querySize_size_, 0, &v12);
  if ( v2 != nullptr )
  {
    v11 = (const char *)IOFindNameForValue(a1: v2, a2: &ABReturnValues);
    v3 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: querySize returned %s\n", v3, v11);
  }
  else
  {
    v4 = (unsigned __int16 *)IOMalloc(a1: v12);
    v5 = objc_msgSend(a1: self->atiBios, a2: sel_deviceQuery_bufferSize_buffer_, 0, v12, v4);
    if ( v5 == nullptr )
    {
      v6 = *v4;
      self->queryDataSize = v6;
      v7 = (void *)IOMalloc(a1: v6);
      self->queryData = v7;
      bcopy(a1: v4, a2: v7, a3: self->queryDataSize);
      IOFree(a1: v4, a2: v12);
      return 0;
    }
    v10 = (const char *)IOFindNameForValue(a1: v5, a2: &ABReturnValues);
    v9 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: deviceQuery returned %s\n", v9, v10);
    if ( v12 != 0 )
      IOFree(a1: v4, a2: v12);
  }
  return 1;
}
```

## -[ATI parseModeString:] (0xe44-0xed4)

```c
int __cdecl -[ATI parseModeString:](ATI *self, SEL a2, const char *a3)
{
  id v3; // eax
  const char *v4; // eax
  id v5; // eax
  const char *v7; // eax
  id v8; // [esp-4h] [ebp-8h]

  v3 = -[ATI selectMode:count:](a1: self, a2: aSelectmodeCoun, &AtiModeList, AtiModeListCount);
  self->modeNumber = (int)v3;
  if ( (int)v3 >= 0 )
  {
    v5 = -[ATI isModeValid:](a1: self, a2: sel_isModeValid_, self->modeNumber);
    if ( v5 == nullptr )
      return 0;
    v8 = v5;
    v7 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Requested Mode not supported (0x%x); aborting\n", v7, v8);
  }
  else
  {
    v4 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: selectMode problem; aborting\n", v4);
  }
  return -1;
}
```

## -[ATI updateModeList] (0xed4-0x10f0)

```c
void __cdecl -[ATI updateModeList](ATI *self, SEL a2)
{
  id v2; // eax
  const char *v3; // eax
  const char *v4; // ebx
  const char *v5; // eax
  unsigned int colorConfig; // eax
  const char *v7; // edi
  unsigned int i; // ebx
  int v9; // eax
  const char *v10; // [esp-4h] [ebp-18h]
  id v11; // [esp+10h] [ebp-4h]

  v2 = -[ATI deviceDescription](a1: self, a2: aDevicedescript);
  v11 = objc_msgSend(a1: v2, a2: aConfigtable);
  self->colorConfig = 0;
  v3 = (const char *)objc_msgSend(a1: v11, a2: aValueforstring, "24-bit Configuration");
  v4 = v3;
  if ( v3 != nullptr )
  {
    if ( strcmp(v3, "RGBx") == 0 )
    {
      self->colorConfig = 1;
    }
    else if ( strcmp(v3, "BGRx") == 0 )
    {
      self->colorConfig = 2;
    }
    else if ( strcmp(v3, "xRGB") == 0 )
    {
      self->colorConfig = 3;
    }
    else if ( strcmp(v3, "xBGR") == 0 )
    {
      self->colorConfig = 4;
    }
    if ( self->colorConfig != 0 )
    {
      v10 = v3;
      v5 = (const char *)-[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: colorConfig from table = %s\n", v5, v10);
    }
    objc_msgSend(a1: v11, a2: aFreestring, v4);
  }
  colorConfig = self->colorConfig;
  if ( colorConfig == 2 )
  {
    v7 = "BBBBBBBBGGGGGGGGRRRRRRRR--------";
  }
  else if ( colorConfig > 2 )
  {
    if ( colorConfig != 4 )
    {
LABEL_18:
      v7 = "--------RRRRRRRRGGGGGGGGBBBBBBBB";
      goto LABEL_22;
    }
    v7 = "--------BBBBBBBBGGGGGGGGRRRRRRRR";
  }
  else
  {
    if ( colorConfig != 1 )
      goto LABEL_18;
    v7 = "RRRRRRRRGGGGGGGGBBBBBBBB--------";
  }
LABEL_22:
  for ( i = 0; AtiModeListCount > i; ++i )
  {
    v9 = 136 * i;
    *((_DWORD *)&AtiModeList + 34 * i + 5) = self->vram;
    if ( self->supportsGamma == 0 && *(_DWORD *)((char *)&AtiModeList + v9 + 24) != 1 )
    {
      *(_DWORD *)((char *)&AtiModeList + v9 + 96) &= ~0x10u;
      *((_BYTE *)&AtiModeList + v9 + 96) |= 2u;
    }
    if ( *((_DWORD *)&AtiModeList + 34 * i + 6) == 4 )
      strcpy(__dst: (char *)(136 * i + 17148), __src: v7);
    *((_DWORD *)&AtiModeList + 34 * i + 32) = 0;
    if ( self->vramBytes < *((_DWORD *)&AtiModeList + 34 * i + 26) )
      *((_DWORD *)&AtiModeList + 34 * i + 32) = 2;
  }
}
```

## -[ATI isModeValid:] (0x10f0-0x1178)

```c
unsigned int __cdecl -[ATI isModeValid:](ATI *self, SEL a2, int a3)
{
  _DWORD *v4; // edx
  _BYTE *queryData; // ecx
  int v6; // eax
  unsigned int v7; // ebx

  if ( AtiModeListCount <= a3 )
    return 16;
  v4 = (_DWORD *)((char *)&AtiModeList + 136 * a3);
  queryData = self->queryData;
  v6 = v4[6];
  if ( v6 == 3 )
  {
    if ( (queryData[19] & 2) == 0 )
      return 64;
  }
  else if ( v6 == 4 && self->colorConfig == 5 )
  {
    return 64;
  }
  v7 = v4[1] * v4[3];
  if ( v7 > memSizeToBytes(a1: queryData[11]) )
    return 2;
  else
    return 0;
}
```

## -[ATI verifyMemoryMap] (0x1178-0x11da)

```c
char __cdecl -[ATI verifyMemoryMap](ATI *self, SEL a2)
{
  void *vram; // ebx
  unsigned int i; // eax
  unsigned int j; // eax
  _BYTE v6[64]; // [esp+8h] [ebp-40h] BYREF

  vram = self->vram;
  bcopy(a1: vram, a2: v6, a3: 0x40u);
  for ( i = 0; i <= 0xF; ++i )
    *((_DWORD *)vram + i) = i;
  for ( j = 0; j <= 0xF; ++j )
  {
    if ( *((_DWORD *)vram + j) != j )
      return 0;
  }
  bcopy(a1: v6, a2: self->vram, a3: 0x40u);
  return 1;
}
```

## -[ATI free] (0x11dc-0x1269)

```c
id __cdecl -[ATI free](ATI *self, SEL a2)
{
  objc_super v3; // [esp+4h] [ebp-8h] BYREF

  if ( self->queryDataSize != 0 )
    IOFree(a1: self->queryData, a2: self->queryDataSize);
  if ( self->atiBios != nullptr )
    objc_msgSend(a1: self->atiBios, a2: sel_free);
  if ( self->redTransferTable != nullptr )
    IOFree(a1: self->redTransferTable, a2: 3 * self->transferTableCount);
  v3.receiver = self;
  v3.super_class = (Class)stru_8158.super_class;
  return -[ATI free](a1: &v3, a2: sel_free);
}
```

## -[ATI enterLinearMode] (0x126c-0x1390)

```c
void __cdecl -[ATI enterLinearMode](ATI *self, SEL a2)
{
  _DWORD *v2; // ebx
  int v3; // edi
  char supportsGrey256; // al
  int v5; // edx
  id v6; // eax
  const char *v7; // eax
  const char *v8; // [esp-4h] [ebp-14h]
  int v9; // [esp+Ch] [ebp-4h]

  v2 = -[ATI displayInfo](a1: self, a2: aDisplayinfo);
  v9 = v2[25];
  if ( self->currentState != 1
    && objc_msgSend(a1: self->atiBios, a2: sel_setApertureEnable_VGAAperture_apertureAdrs_, 1, 0, 0) == nullptr )
  {
    v3 = displayInfoToColorDepth(a1: v2);
    displayInfoToColorSpace(a1: v2);
    if ( v3 == 2 )
      supportsGrey256 = self->supportsGrey256;
    else
      supportsGrey256 = self->supportsGamma;
    v5 = 2;
    if ( *v2 == 1024 )
      v5 = 0;
    v6 = objc_msgSend(
           a1: self->atiBios,
           a2: sel_loadCRTCSetMode_gamma_pitchSize_resolution_crtTable_,
           v3,
           supportsGrey256,
           v5,
           129,
           v9);
    if ( v6 != nullptr )
    {
      v8 = (const char *)IOFindNameForValue(a1: v6, a2: &ABReturnValues);
      v7 = (const char *)-[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: Error setting CRTC Paramters (%s)\n", v7, v8);
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

## -[ATI revertToVGAMode] (0x1390-0x148c)

```c
void __cdecl -[ATI revertToVGAMode](ATI *self, SEL a2)
{
  id v2; // eax
  const char *v3; // eax
  id v4; // eax
  const char *v5; // eax
  const char *v6; // [esp-Ch] [ebp-38h]
  const char *v7; // [esp-4h] [ebp-30h]
  _BYTE v8[32]; // [esp+Ch] [ebp-20h] BYREF

  qmemcpy(v8, AtiVgaCRTC, 30);
  v2 = objc_msgSend(a1: self->atiBios, a2: sel_loadCRTCSetMode_gamma_pitchSize_resolution_crtTable_, 1, 0, 2, 129, v8);
  if ( v2 != nullptr )
  {
    v6 = (const char *)IOFindNameForValue(a1: v2, a2: &ABReturnValues);
    v3 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Error setting CRTC (%s)\n", v3, v6);
  }
  v4 = objc_msgSend(a1: self->atiBios, a2: sel_setVGAMode_gamma_, 1, 0);
  if ( v4 != nullptr )
  {
    v7 = (const char *)IOFindNameForValue(a1: v4, a2: &ABReturnValues);
    v5 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Error setting VGA (%s)\n", v5, v7);
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

## _waitForFIFO (0x148c-0x14c0)

```c
unsigned int __cdecl waitForFIFO(char a1)
{
  unsigned int result; // eax

  result = 0x8000u >> a1;
  if ( *(_DWORD *)(register_base_address + 784) > 0x8000u >> a1 )
  {
    result = 0x8000u >> a1;
    while ( *(_DWORD *)(register_base_address + 784) > result )
      ;
  }
  return result;
}
```

## _waitForIdle (0x14c0-0x1509)

```c
int waitForIdle()
{
  unsigned int v0; // ebx
  unsigned int v1; // eax
  int result; // eax

  v0 = 0;
  waitForFIFO(a1: 16);
  while ( 1 )
  {
    result = register_base_address;
    if ( (*(_BYTE *)(register_base_address + 824) & 1) == 0 )
      break;
    IODelay(a1: 1);
    v1 = v0++;
    if ( v1 > 0x7A120 )
      return IOLog(a1: "ATIRage: waitForIdle timeout.\n");
  }
  return result;
}
```

## _doBlit (0x150c-0x1657)

```c
int __cdecl doBlit(
        unsigned int a1,
        unsigned int a2,
        unsigned int a3,
        unsigned int a4,
        unsigned int a5,
        unsigned int a6)
{
  int v6; // ebx
  int v7; // eax
  unsigned int v8; // edx
  unsigned int v9; // edx
  int v10; // esi
  _DWORD *v11; // edx
  int result; // eax
  int v13; // [esp+Ch] [ebp-20h]
  int v14; // [esp+10h] [ebp-1Ch]
  int v15; // [esp+14h] [ebp-18h]
  int v16; // [esp+18h] [ebp-14h]
  int v17; // [esp+1Ch] [ebp-10h]
  int v18; // [esp+20h] [ebp-Ch]
  int v19; // [esp+24h] [ebp-8h]
  int v20; // [esp+28h] [ebp-4h]

  v6 = a1;
  v7 = a5;
  v8 = a5 - a1;
  if ( (int)(a5 - a1) < 0 )
    v8 = a1 - a5;
  if ( a3 > v8 )
  {
    v9 = a6 - a2;
    if ( (int)(a6 - a2) < 0 )
      v9 = a2 - a6;
    if ( a4 > v9 )
    {
      v20 = 0;
      if ( a5 > a1 )
      {
        v6 = a1 + a3 - 1;
        v7 = a5 + a3 - 1;
      }
      else
      {
        LOBYTE(v20) = 1;
      }
      v18 = v7;
      if ( a6 <= a2 )
      {
        LOBYTE(v20) = v20 | 2;
        v14 = a2;
LABEL_14:
        v10 = a6;
        goto LABEL_15;
      }
      v14 = a2 + a4 - 1;
      v10 = a6 + a4 - 1;
LABEL_15:
      waitForIdle();
      waitForFIFO(a1: 10);
      v11 = (_DWORD *)register_base_address;
      v15 = *(_DWORD *)(register_base_address + 728);
      v16 = *(_DWORD *)(register_base_address + 436);
      v17 = *(_DWORD *)(register_base_address + 304);
      *(_DWORD *)(register_base_address + 728) = 768;
      v11[109] = 0;
      v19 = v20 | v17 & 0x80;
      LOBYTE(v19) = v19 | 0x18;
      v11[76] = v19;
      v11[99] = v14 | (v6 << 16);
      v13 = a4 | (a3 << 16);
      v11[102] = v13;
      v11[67] = v10 | (v18 << 16);
      v11[70] = v13;
      waitForFIFO(a1: 3);
      result = register_base_address;
      *(_DWORD *)(register_base_address + 728) = v15;
      *(_DWORD *)(result + 436) = v16;
      *(_DWORD *)(result + 304) = v17;
      return result;
    }
  }
  v20 = 3;
  v14 = a2;
  v18 = a5;
  goto LABEL_14;
}
```

## -[ATI showCursor:frame:token:] (0x1658-0x169b)

```c
id __cdecl -[ATI showCursor:frame:token:](ATI *self, SEL a2, $9B414A52084CF78D000E95AF47DF0AD5 *a3, int a4, int a5)
{
  objc_super v6; // [esp+Ch] [ebp-8h] BYREF

  waitForIdle();
  v6.receiver = self;
  v6.super_class = (Class)stru_8158.super_class;
  return -[ATI showCursor:frame:token:](a1: &v6, a2: sel_showCursor_frame_token_, a3, a4, a5);
}
```

## -[ATI moveCursor:frame:token:] (0x169c-0x16df)

```c
id __cdecl -[ATI moveCursor:frame:token:](ATI *self, SEL a2, $9B414A52084CF78D000E95AF47DF0AD5 *a3, int a4, int a5)
{
  objc_super v6; // [esp+Ch] [ebp-8h] BYREF

  waitForIdle();
  v6.receiver = self;
  v6.super_class = (Class)stru_8158.super_class;
  return -[ATI moveCursor:frame:token:](a1: &v6, a2: sel_moveCursor_frame_token_, a3, a4, a5);
}
```

## -[ATI hideCursor:] (0x16e0-0x1719)

```c
id __cdecl -[ATI hideCursor:](ATI *self, SEL a2, int a3)
{
  objc_super v4; // [esp+8h] [ebp-8h] BYREF

  waitForIdle();
  v4.receiver = self;
  v4.super_class = (Class)stru_8158.super_class;
  return -[ATI hideCursor:](a1: &v4, a2: sel_hideCursor_, a3);
}
```

## _doFill (0x171c-0x17a1)

```c
int __cdecl doFill(int a1, int a2, int a3, int a4, int a5)
{
  _DWORD *v5; // eax
  int v6; // edi
  int v7; // esi
  int v8; // ebx
  int result; // eax

  waitForIdle();
  waitForFIFO(a1: 7);
  v5 = (_DWORD *)register_base_address;
  v6 = *(_DWORD *)(register_base_address + 728);
  v7 = *(_DWORD *)(register_base_address + 436);
  v8 = *(_DWORD *)(register_base_address + 304);
  *(_DWORD *)(register_base_address + 708) = a5;
  v5[182] = 256;
  v5[67] = a2 | (a1 << 16);
  v5[70] = a4 | (a3 << 16);
  waitForFIFO(a1: 3);
  result = register_base_address;
  *(_DWORD *)(register_base_address + 728) = v6;
  *(_DWORD *)(result + 436) = v7;
  *(_DWORD *)(result + 304) = v8;
  return result;
}
```

## -[ATI initEngine] (0x17a4-0x19da)

```c
void __cdecl -[ATI initEngine](ATI *self, SEL a2)
{
  unsigned int *v2; // esi
  unsigned int v3; // ebx
  _DWORD *v4; // eax
  unsigned int v5; // edx
  _DWORD *v6; // eax
  int v7; // eax
  int v8; // eax
  int v9; // eax
  const char *v10; // eax

  v2 = (unsigned int *)-[ATI displayInfo](a1: self, a2: aDisplayinfo);
  -[ATI resetEngine](a1: self, a2: sel_resetEngine);
  v3 = *v2;
  waitForFIFO(a1: 14);
  v4 = (_DWORD *)register_base_address;
  *(_DWORD *)(register_base_address + 800) = -1;
  v5 = v3 >> 3 << 22;
  v4[64] = v5;
  v4[67] = 0;
  v4[69] = 0;
  v4[73] = 0;
  v4[74] = 0;
  v4[75] = 0;
  v4[76] = 35;
  v4[96] = v5;
  v4[99] = 0;
  v4[102] = 0;
  v4[105] = 0;
  v4[108] = 0;
  v4[109] = 16;
  waitForFIFO(a1: 13);
  v6 = (_DWORD *)register_base_address;
  *(_DWORD *)(register_base_address + 576) = 0;
  v6[160] = 0;
  v6[161] = 0;
  v6[162] = 0;
  v6[168] = 0;
  v6[171] = 0;
  v6[172] = *v2 - 1;
  v6[169] = v3 - 1;
  v6[176] = 0;
  v6[177] = -1;
  v6[178] = -1;
  v6[181] = 458755;
  v6[182] = 256;
  waitForFIFO(a1: 3);
  v7 = register_base_address;
  *(_DWORD *)(register_base_address + 768) = 0;
  *(_DWORD *)(v7 + 772) = -1;
  *(_DWORD *)(v7 + 776) = 0;
  switch ( v2[6] )
  {
    case 1u:
      waitForFIFO(a1: 2);
      v8 = register_base_address;
      *(_DWORD *)(register_base_address + 720) = 16908802;
      goto LABEL_5;
    case 3u:
      waitForFIFO(a1: 2);
      v9 = register_base_address;
      *(_DWORD *)(register_base_address + 720) = 16974595;
      *(_DWORD *)(v9 + 716) = 16912;
      break;
    case 4u:
      waitForFIFO(a1: 2);
      v8 = register_base_address;
      *(_DWORD *)(register_base_address + 720) = 17171974;
LABEL_5:
      *(_DWORD *)(v8 + 716) = 32896;
      break;
    default:
      v10 = (const char *)-[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: Pixel depth not supported,\n", v10);
      break;
  }
  waitForIdle();
}
```

## -[ATI resetEngine] (0x19dc-0x1a56)

```c
void __cdecl -[ATI resetEngine](ATI *self, SEL a2)
{
  unsigned __int16 v2; // dx
  unsigned __int32 v3; // eax
  unsigned int v4; // ebx
  unsigned __int16 v5; // dx
  unsigned __int32 v6; // eax
  unsigned __int32 v7; // ebx
  unsigned __int32 v8; // eax

  v2 = LOWORD(self->baseAddress) + 208;
  v3 = __indword(v2);
  v4 = v3;
  BYTE1(v4) = BYTE1(v3) & 0xFE;
  __outdword(v2, v4);
  _InterlockedIncrement(&resetEngineWriteCounter);
  v5 = LOWORD(self->baseAddress) + 208;
  v6 = __indword(v5);
  v7 = v6;
  BYTE1(v7) = BYTE1(v6) | 1;
  __outdword(v5, v7);
  _InterlockedIncrement(&resetEngineWriteCounter);
  LOWORD(v7) = LOWORD(self->baseAddress) + 160;
  v8 = __indword(v7);
  __outdword(v7, v8 & 0xFF00FFFF | 0xAE0000);
  _InterlockedIncrement(&resetEngineWriteCounter);
}
```

## -[ATI displayModeCount] (0x1a58-0x1a64)

```c
unsigned int __cdecl -[ATI displayModeCount](ATI *self, SEL a2)
{
  return AtiModeListCount;
}
```

## -[ATI displayModes] (0x1a64-0x1a70)

```c
$514E7C50D28E54AB164B6500F83867A3 *__cdecl -[ATI displayModes](ATI *self, SEL a2)
{
  return ($514E7C50D28E54AB164B6500F83867A3 *)&AtiModeList;
}
```

## -[ATI displayMemorySize] (0x1a70-0x1a8a)

```c
unsigned int __cdecl -[ATI displayMemorySize](ATI *self, SEL a2)
{
  return memSizeToBytes(a1: *((_BYTE *)self->queryData + 11));
}
```

## -[ATI setPendingDisplayMode:] (0x1a8c-0x1b23)

```c
char __cdecl -[ATI setPendingDisplayMode:](ATI *self, SEL a2, int a3)
{
  const char *v4; // eax
  objc_super v5; // [esp+8h] [ebp-8h] BYREF

  if ( AtiModeListCount <= a3 )
  {
    v4 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: setPendingDisplayMode: bogus displayMode (%d)\n", v4, a3);
  }
  else if ( -[ATI isModeValid:](a1: self, a2: sel_isModeValid_, a3) == 0 )
  {
    dword_42F0[34 * a3] = (int)self->vram;
    v5.receiver = self;
    v5.super_class = (Class)stru_8158.super_class;
    if ( -[ATI setPendingDisplayMode:](a1: &v5, a2: sel_setPendingDisplayMode_, a3) != 0 )
    {
      self->modeNumber = a3;
      return 1;
    }
  }
  return 0;
}
```

## -[ATI setIntValues:forParameter:count:] (0x1b24-0x1bf4)

```c
int __cdecl -[ATI setIntValues:forParameter:count:](ATI *self, SEL a2, unsigned int *a3, char *a4, unsigned int a5)
{
  objc_super v6; // [esp+Ch] [ebp-8h] BYREF

  if ( strcmp(a4, "IODisplayDoBlit") == 0 && a5 == 6 )
  {
    doBlit(a1: *a3, a2: a3[1], a3: a3[2], a4: a3[3], a5: a3[4], a6: a3[5]);
  }
  else if ( strcmp(a4, "IODisplayDoFill") == 0 && a5 == 5 )
  {
    doFill(a1: *a3, a2: a3[1], a3: a3[2], a4: a3[3], a5: a3[4]);
  }
  else
  {
    if ( strcmp(a4, "IOGetDisplaySynced") != 0 || a5 != 1 )
    {
      v6.receiver = self;
      v6.super_class = (Class)stru_8158.super_class;
      return -[ATI setIntValues:forParameter:count:](a1: &v6, a2: sel_setIntValues_forParameter_count_, a3, a4, a5);
    }
    waitForIdle();
  }
  return 0;
}
```

## _isATI68880RevC (0x1bf4-0x1c15)

```c
_BOOL4 __cdecl isATI68880RevC(__int16 a1)
{
  unsigned __int8 v1; // al

  v1 = __inbyte(a1 + 195);
  return v1 == 0xD0;
}
```

## _SetGammaValue (0x1c18-0x1c6c)

```c
unsigned int __cdecl SetGammaValue(__int16 a1, int a2, int a3, int a4, int a5)
{
  unsigned int result; // eax

  __outbyte(a1 + 193, (unsigned int)(a5 * a2) >> 6);
  _InterlockedIncrement(&setGammaValueWriteCounter);
  __outbyte(a1 + 193, (unsigned int)(a5 * a3) >> 6);
  _InterlockedIncrement(&setGammaValueWriteCounter);
  result = (unsigned int)(a5 * a4) >> 6;
  __outbyte(a1 + 193, result);
  _InterlockedIncrement(&setGammaValueWriteCounter);
  return result;
}
```

## -[ATI setGammaTable] (0x1c6c-0x1de0)

```c
id __cdecl -[ATI setGammaTable](ATI *self, SEL a2)
{
  unsigned __int16 v2; // dx
  unsigned __int8 v3; // al
  unsigned int i; // esi
  unsigned int j; // ebx
  unsigned int v6; // edx
  unsigned int k; // ebx
  unsigned int m; // esi
  unsigned int n; // ebx

  v2 = LOWORD(self->baseAddress) + 196;
  v3 = __inbyte(v2);
  __outbyte(v2, v3 & 0xFC | 2);
  _InterlockedIncrement(&setGammaValueWriteCounter);
  __outbyte(LOWORD(self->baseAddress) + 194, 0xFFu);
  _InterlockedIncrement(&setGammaValueWriteCounter);
  __outbyte(LOWORD(self->baseAddress) + 192, 0);
  _InterlockedIncrement(&setGammaValueWriteCounter);
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
    v6 = *((_DWORD *)-[ATI displayInfo](a1: self, a2: aDisplayinfo) + 6);
    if ( v6 == 1 )
    {
      for ( k = 0; k <= 0xFF; ++k )
        SetGammaValue(
          a1: self->baseAddress,
          a2: (unsigned __int8)gamma8[k],
          a3: (unsigned __int8)gamma8[k],
          a4: (unsigned __int8)gamma8[k],
          a5: self->brightnessLevel);
    }
    else if ( v6 != 0 && v6 <= 4 && v6 >= 3 )
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

## -[ATI setBrightness:token:] (0x1de0-0x1e1c)

```c
id __cdecl -[ATI setBrightness:token:](ATI *self, SEL a2, int a3, int a4)
{
  if ( (unsigned int)a3 > 0x40 )
  {
    IOLog(a1: "Display: Invalid arg to setBrightness: %d\n", a3);
    return nullptr;
  }
  else
  {
    self->brightnessLevel = a3;
    -[ATI setGammaTable](a1: self, a2: sel_setGammaTable);
    return self;
  }
}
```

## -[ATI setTransferTable:count:] (0x1e1c-0x2005)

```c
id __cdecl -[ATI setTransferTable:count:](ATI *self, SEL a2, const unsigned int *a3, int a4)
{
  _BYTE *queryData; // eax
  char v5; // bl
  int v6; // edx
  int ramdacStyle; // eax
  char *v8; // eax
  int v9; // eax
  char *blueTransferTable; // edx
  int i; // esi
  char *redTransferTable; // ebx
  int v13; // eax
  int j; // esi
  char *greenTransferTable; // [esp+Ch] [ebp-Ch]
  unsigned __int8 v17; // [esp+10h] [ebp-8h]
  char v18; // [esp+14h] [ebp-4h]

  queryData = self->queryData;
  v17 = queryData[12];
  v5 = 2;
  if ( self->supportsGrey256 != 0 )
    v5 = 0;
  v6 = (unsigned __int8)queryData[9];
  if ( v6 != 67 && v6 != 69 )
  {
    if ( v17 == 5 )
      goto LABEL_11;
    if ( v17 <= 5u )
    {
      if ( v17 != 2 )
        goto LABEL_12;
LABEL_11:
      v5 = 0;
      goto LABEL_12;
    }
    if ( v17 == 21 && isATI68880RevC(a1: self->baseAddress) )
      goto LABEL_11;
  }
LABEL_12:
  v18 = v5;
  ramdacStyle = self->ramdacStyle;
  if ( ramdacStyle > 1 )
  {
    if ( ramdacStyle == 2 )
      v18 = 2;
  }
  else if ( ramdacStyle == 1 )
  {
    v18 = 0;
  }
  if ( self->redTransferTable != nullptr )
    IOFree(a1: self->redTransferTable, a2: 3 * self->transferTableCount);
  self->transferTableCount = a4;
  v8 = (char *)IOMalloc(a1: 3 * a4);
  self->redTransferTable = v8;
  self->greenTransferTable = &v8[a4];
  self->blueTransferTable = &self->greenTransferTable[a4];
  -[ATI displayInfo](a1: self, a2: aDisplayinfo);
  v9 = *((_DWORD *)-[ATI displayInfo](a1: self, a2: aDisplayinfo) + 7);
  if ( v9 == 1 )
  {
    blueTransferTable = self->blueTransferTable;
    for ( i = 0; a4 > i; ++i )
    {
      greenTransferTable = self->greenTransferTable;
      redTransferTable = self->redTransferTable;
      v13 = LOBYTE(a3[i]) >> v18;
      blueTransferTable[i] = v13;
      greenTransferTable[i] = v13;
      redTransferTable[i] = v13;
    }
  }
  else if ( v9 == 2 )
  {
    for ( j = 0; a4 > j; ++j )
    {
      self->redTransferTable[j] = HIBYTE(a3[j]) >> v18;
      self->greenTransferTable[j] = BYTE2(a3[j]) >> v18;
      self->blueTransferTable[j] = BYTE1(a3[j]) >> v18;
    }
  }
  else
  {
    IOFree(a1: self->redTransferTable, a2: 3 * a4);
    self->redTransferTable = nullptr;
  }
  -[ATI setGammaTable](a1: self, a2: sel_setGammaTable);
  return self;
}
```

## _displayInfoToColorSpace (0x2008-0x206d)

```c
int __cdecl displayInfoToColorSpace(int a1)
{
  int v1; // ebx
  unsigned int v2; // eax

  v1 = 0;
  v2 = *(_DWORD *)(a1 + 24);
  if ( v2 == 3 )
    return 2;
  if ( v2 > 3 )
  {
    if ( v2 != 4 )
      goto LABEL_10;
    return 3;
  }
  else
  {
    if ( v2 != 1 )
    {
LABEL_10:
      IOLog(a1: "ATIMach64: displayInfoToColorSpace problem (%d)\n", *(_DWORD *)(a1 + 24));
      IOPanic(a1: "ATIMach64 displayInfoToColorSpace");
      return v1;
    }
    return *(_DWORD *)(a1 + 28) != 1;
  }
}
```

## _colorDepthToColorSpace (0x2070-0x20bd)

```c
int __cdecl colorDepthToColorSpace(int a1)
{
  int result; // eax

  result = 0;
  switch ( a1 )
  {
    case 2:
      result = 1;
      break;
    case 3:
    case 4:
      result = 2;
      break;
    case 5:
    case 6:
      result = 3;
      break;
    default:
      return result;
  }
  return result;
}
```

## _displayInfoToColorDepth (0x20c0-0x210f)

```c
int __cdecl displayInfoToColorDepth(int a1)
{
  int v1; // ebx
  unsigned int v2; // eax

  v1 = 0;
  v2 = *(_DWORD *)(a1 + 24);
  if ( v2 == 3 )
    return 3;
  if ( v2 > 3 )
  {
    if ( v2 != 4 )
      goto LABEL_10;
    return 6;
  }
  else
  {
    if ( v2 != 1 )
    {
LABEL_10:
      IOPanic(a1: "ATIMach64: displayInfoToColorDepth problem");
      return v1;
    }
    return 2;
  }
}
```

## _memSizeToBytes (0x2110-0x218d)

```c
int __cdecl memSizeToBytes(char a1)
{
  int result; // eax

  switch ( a1 )
  {
    case 0:
      result = 0x80000;
      break;
    case 1:
      result = 0x100000;
      break;
    case 2:
      result = 0x200000;
      break;
    case 3:
      result = 0x400000;
      break;
    case 4:
      result = 6291456;
      break;
    case 5:
      result = 8386560;
      break;
    default:
      result = 0x200000;
      break;
  }
  return result;
}
```

## +[ATI_BIOS ATIPresent:] (0x2190-0x222a)

```c
char __cdecl +[ATI_BIOS ATIPresent:](id a1, SEL a2, unsigned int *a3)
{
  unsigned int i; // ebx
  char v5[12]; // [esp+14h] [ebp-Ch] BYREF

  strcpy(v5, "761295520");
  *a3 = 786432;
  do
  {
    for ( i = 0; i < 129 - (strlen(v5) + 1); ++i )
    {
      if ( strncmp(__s1: v5, __s2: (const char *)(*a3 + i), __n: 9u) == 0 )
        return 1;
    }
    *a3 += 4096;
  }
  while ( *a3 <= 0xEFFFF );
  return 0;
}
```

## -[ATI_BIOS init] (0x222c-0x22ce)

```c
ATI_BIOS *__cdecl -[ATI_BIOS init](ATI_BIOS *self, SEL a2)
{
  unsigned int i; // esi
  unsigned int j; // ebx
  char v5[12]; // [esp+14h] [ebp-Ch] BYREF

  strcpy(v5, "761295520");
  for ( i = 786432; i <= 0xEFFFF; i += 4096 )
  {
    for ( j = 0; j < 129 - (strlen(v5) + 1); ++j )
    {
      if ( strncmp(__s1: v5, __s2: (const char *)(j + i), __n: 9u) == 0 )
        return (ATI_BIOS *)-[ATI_BIOS initAtSegmentAddress:](a1: self, a2: sel_initAtSegmentAddress_, i);
    }
  }
  return nullptr;
}
```

## -[ATI_BIOS initAtSegmentAddress:] (0x22d0-0x2311)

```c
id __cdecl -[ATI_BIOS initAtSegmentAddress:](ATI_BIOS *self, SEL a2, unsigned int a3)
{
  objc_super v4; // [esp+4h] [ebp-8h] BYREF

  self->segmentBase = a3;
  self->_priv = (void *)IOMalloc(a1: 36);
  self->initialized = 1;
  v4.receiver = self;
  v4.super_class = (Class)stru_8158.ext;
  return -[ATI_BIOS init](a1: &v4, a2: sel_init);
}
```

## -[ATI_BIOS free] (0x2314-0x2355)

```c
id __cdecl -[ATI_BIOS free](ATI_BIOS *self, SEL a2)
{
  objc_super v3; // [esp+4h] [ebp-8h] BYREF

  if ( self->initialized != 0 )
    IOFree(a1: self->_priv, a2: 36);
  v3.receiver = self;
  v3.super_class = (Class)stru_8158.ext;
  return -[ATI_BIOS free](a1: &v3, a2: sel_free);
}
```

## -[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:] (0x2358-0x238b)

```c
int __cdecl -[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:](
        ATI_BIOS *self,
        SEL a2,
        unsigned int a3,
        char a4,
        unsigned int a5,
        unsigned int a6,
        $D36094C8510EB81E7056FECE159970B1 *a7)
{
  return -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:](
           a1: self,
           a2: sel_loadCRTC_comm_gamma_pitchSize_resolution_crtTable_function_name_,
           a3,
           a4,
           a5,
           a6,
           a7,
           0,
           "loadCRTC");
}
```

## -[ATI_BIOS setVGAMode:gamma:] (0x238c-0x2425)

```c
int __cdecl -[ATI_BIOS setVGAMode:gamma:](ATI_BIOS *self, SEL a2, char a3, char a4)
{
  char v5; // al
  id v6; // eax
  _BYTE v7[48]; // [esp+10h] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v7, 1);
  v5 = 0;
  if ( a4 != 0 )
    v5 = 0x80;
  v7[12] = v5 | (a3 == 0);
  v6 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v7, 0);
  if ( v6 != nullptr )
  {
    IOLog(a1: "ATI_BIOS setDisplayMode: ATIbios32() returned %d\n", v6);
  }
  else
  {
    if ( v7[5] == 0 )
      return 0;
    IOLog(a1: "ATI_BIOS setDisplayMode: ah = 0x%x on return from ATIbios32()\n", v7[5]);
  }
  return 2;
}
```

## -[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:] (0x2428-0x245b)

```c
int __cdecl -[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:](
        ATI_BIOS *self,
        SEL a2,
        unsigned int a3,
        char a4,
        unsigned int a5,
        unsigned int a6,
        $D36094C8510EB81E7056FECE159970B1 *a7)
{
  return -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:](
           a1: self,
           a2: sel_loadCRTC_comm_gamma_pitchSize_resolution_crtTable_function_name_,
           a3,
           a4,
           a5,
           a6,
           a7,
           2,
           "loadCRTCSetMode");
}
```

## -[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:] (0x245c-0x252a)

```c
int __cdecl -[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:](
        ATI_BIOS *self,
        SEL a2,
        char a3,
        char a4,
        unsigned int a5)
{
  id v6; // eax
  _WORD v7[6]; // [esp+14h] [ebp-30h] BYREF
  char v8; // [esp+20h] [ebp-24h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v7, 5);
  v8 = a3 != 0;
  if ( a4 != 0 )
    v8 |= 4u;
  if ( a5 != 0 )
  {
    if ( (a5 & 0xFFFFF) != 0 )
    {
      IOLog(a1: "ATI BIOS setApertureEnable: apertureAdrs misalignment (0x%x)\n", a5);
      return 3;
    }
    v8 |= 0x80u;
    v7[4] = a5 >> 20;
  }
  v6 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v7, 0);
  if ( v6 != nullptr )
  {
    IOLog(a1: "ATI_BIOS setApertureEnable: ATIbios32() returned %d\n", v6);
  }
  else
  {
    if ( HIBYTE(v7[2]) == 0 )
      return 0;
    IOLog(a1: "ATI_BIOS setApertureEnable: ah = 0x%x on return from ATIbios32()\n", HIBYTE(v7[2]));
  }
  return 2;
}
```

## -[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:] (0x252c-0x25f6)

```c
int __cdecl -[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:](
        ATI_BIOS *self,
        SEL a2,
        unsigned int *a3,
        char *a4,
        char *a5,
        unsigned int *a6,
        unsigned int *a7,
        unsigned int *a8,
        char *a9,
        char *a10)
{
  id v11; // eax
  _WORD v12[24]; // [esp+Ch] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v12, 6);
  v11 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v12, 0);
  if ( v11 != nullptr )
  {
    IOLog(a1: "ATI_BIOS shortQuery: ATIbios32() returned %d\n", v11);
  }
  else
  {
    if ( HIBYTE(v12[2]) == 0 )
    {
      *a3 = v12[2] & 0x3F;
      *a4 = (v12[2] & 0x40) != 0;
      *a5 = LOBYTE(v12[2]) >> 7;
      *a6 = v12[4];
      *a7 = HIBYTE(v12[6]);
      *a8 = LOBYTE(v12[6]);
      *a9 = HIBYTE(v12[8]);
      *a10 = v12[8];
      return 0;
    }
    IOLog(a1: "ATI_BIOS shortQuery: ah = 0x%x on return from ATIbios32()\n", HIBYTE(v12[2]));
  }
  return 2;
}
```

## -[ATI_BIOS querySize:size:] (0x25f8-0x260a)

```c
int __cdecl -[ATI_BIOS querySize:size:](ATI_BIOS *self, SEL a2, char a3, unsigned int *a4)
{
  *a4 = 4096;
  return 0;
}
```

## -[ATI_BIOS deviceQuery:bufferSize:buffer:] (0x260c-0x26ca)

```c
int __cdecl -[ATI_BIOS deviceQuery:bufferSize:buffer:](ATI_BIOS *self, SEL a2, char a3, unsigned int a4, void *a5)
{
  int result; // eax
  id v6; // eax
  _WORD v7[6]; // [esp+10h] [ebp-30h] BYREF
  bool v8; // [esp+1Ch] [ebp-24h]
  __int16 v9; // [esp+20h] [ebp-20h]

  if ( self->initialized == 0 )
    return 1;
  bzero(a1: a5, a2: a4);
  -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v7, 9);
  v8 = a3 == 0;
  result = -[ATI_BIOS createDataSegment:size:](a1: self, a2: sel_createDataSegment_size_, a5, a4);
  if ( result == 0 )
  {
    v9 = 136;
    v7[4] = 0;
    v6 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v7, 1);
    if ( v6 != nullptr )
    {
      IOLog(a1: "ATI_BIOS deviceQuery: ATIbios32() returned %d\n", v6);
    }
    else
    {
      if ( HIBYTE(v7[2]) == 0 )
        return 0;
      IOLog(a1: "ATI_BIOS deviceQuery: ah = 0x%x on return from ATIbios32()\n", HIBYTE(v7[2]));
    }
    return 2;
  }
  return result;
}
```

## -[ATI_BIOS setDPMSMode:] (0x26cc-0x2752)

```c
int __cdecl -[ATI_BIOS setDPMSMode:](ATI_BIOS *self, SEL a2, unsigned int a3)
{
  id v4; // eax
  _BYTE v5[48]; // [esp+Ch] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  if ( a3 <= 4 )
  {
    -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v5, 12);
    v5[12] = a3 & 3;
    v4 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v5, 0);
    if ( v4 != nullptr )
    {
      IOLog(a1: "ATI_BIOS Set DPMS Mode: ATIbios32() returned %d\n", v4);
      return 2;
    }
    else
    {
      return 0;
    }
  }
  else
  {
    IOLog(a1: "ATI_BIOS set DPMS mode: %x not valid mode\n", a3);
    return 3;
  }
}
```

## -[ATI_BIOS getDPMSMode:] (0x2754-0x27c6)

```c
int __cdecl -[ATI_BIOS getDPMSMode:](ATI_BIOS *self, SEL a2, unsigned int *a3)
{
  id v4; // eax
  _BYTE v5[12]; // [esp+Ch] [ebp-30h] BYREF
  char v6; // [esp+18h] [ebp-24h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v5, 13);
  v6 = 0;
  v4 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v5, 0);
  if ( v4 != nullptr )
  {
    IOLog(a1: "ATI_BIOS Get DPMS Mode: ATIbios32() returned %d\n", v4);
    return 2;
  }
  else
  {
    *a3 = v6 & 3;
    return 0;
  }
}
```

## -[ATI_BIOS setAPMState:] (0x27c8-0x284e)

```c
int __cdecl -[ATI_BIOS setAPMState:](ATI_BIOS *self, SEL a2, unsigned int a3)
{
  id v4; // eax
  _BYTE v5[48]; // [esp+Ch] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  if ( a3 <= 3 )
  {
    -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v5, 14);
    v5[12] = a3 & 3;
    v4 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v5, 0);
    if ( v4 != nullptr )
    {
      IOLog(a1: "ATI_BIOS Set APM State: ATIbios32() returned %d\n", v4);
      return 2;
    }
    else
    {
      return 0;
    }
  }
  else
  {
    IOLog(a1: "ATI_BIOS set APM state: %x not valid mode\n", a3);
    return 3;
  }
}
```

## -[ATI_BIOS getAPMState:] (0x2850-0x28c2)

```c
int __cdecl -[ATI_BIOS getAPMState:](ATI_BIOS *self, SEL a2, unsigned int *a3)
{
  id v4; // eax
  _BYTE v5[12]; // [esp+Ch] [ebp-30h] BYREF
  char v6; // [esp+18h] [ebp-24h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v5, 15);
  v6 = 0;
  v4 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v5, 0);
  if ( v4 != nullptr )
  {
    IOLog(a1: "ATI_BIOS Get APM State: ATIbios32() returned %d\n", v4);
    return 2;
  }
  else
  {
    *a3 = v6 & 3;
    return 0;
  }
}
```

## -[ATI_BIOS getIOBaseAddress:relocatable:] (0x28c4-0x293e)

```c
int __cdecl -[ATI_BIOS getIOBaseAddress:relocatable:](ATI_BIOS *self, SEL a2, unsigned int *a3, char *a4)
{
  id v5; // eax
  _BYTE v6[12]; // [esp+Ch] [ebp-30h] BYREF
  char v7; // [esp+18h] [ebp-24h]
  unsigned int v8; // [esp+1Ch] [ebp-20h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v6, 18);
  v7 = 0;
  v5 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v6, 0);
  if ( v5 != nullptr )
  {
    IOLog(a1: "ATI_BIOS Short Query 2: ATIbios32() returned %d\n", v5);
    return 2;
  }
  else
  {
    *a4 = v7 & 1;
    *a3 = v8;
    return 0;
  }
}
```

## -[ATI_BIOS getRefreshRate:] (0x2940-0x29e1)

```c
int __cdecl -[ATI_BIOS getRefreshRate:](ATI_BIOS *self, SEL a2, char *a3)
{
  int result; // eax
  id v4; // eax
  _BYTE v5[8]; // [esp+8h] [ebp-30h] BYREF
  __int16 v6; // [esp+10h] [ebp-28h]
  __int16 v7; // [esp+18h] [ebp-20h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v5, 21);
  LOBYTE(v6) = 0;
  result = -[ATI_BIOS createDataSegment:size:](a1: self, a2: sel_createDataSegment_size_, a3, 20);
  if ( result == 0 )
  {
    v7 = 136;
    v6 = 0;
    v4 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v5, 1);
    if ( v4 != nullptr )
    {
      IOLog(a1: "ATI_BIOS getRefreshRate: ATIbios32() returned %d\n", v4);
    }
    else
    {
      if ( v5[5] == 0 )
        return 0;
      IOLog(a1: "ATI_BIOS getRefreshRate: ah = 0x%x on return from ATIbios32()\n", v5[5]);
    }
    return 2;
  }
  return result;
}
```

## -[ATI_BIOS changeRefreshRate:] (0x29e4-0x29f0)

```c
int __cdecl -[ATI_BIOS changeRefreshRate:](ATI_BIOS *self, SEL a2, char *a3)
{
  return 3;
}
```

## -[ATI_BIOS initBIOSBuf:function:] (0x29f0-0x2a40)

```c
int __cdecl -[ATI_BIOS initBIOSBuf:function:](id a1, int a2, void *a3, char a4)
{
  int result; // eax

  objc_msgSend(a1, a2: sel_setupCodeSegments);
  bzero(a1: a3, a2: 0x30u);
  *((_BYTE *)a3 + 4) = a4;
  *((_WORD *)a3 + 16) = 128;
  *((_WORD *)a3 + 17) = 16;
  *((_DWORD *)a3 + 11) = 100;
  result = (unsigned __int16)ATI_Bios_StackOffset >> 1;
  *((_DWORD *)a3 + 7) = result;
  return result;
}
```

## -[ATI_BIOS setupCodeSegments] (0x2a40-0x2bc6)

```c
void __cdecl -[ATI_BIOS setupCodeSegments](ATI_BIOS *self, SEL a2)
{
  _DWORD *priv; // ebx
  int v3; // eax
  int v4; // edx
  _DWORD *v5; // esi
  unsigned int v6; // edi
  void *v7; // eax
  int v8; // edi
  int v9; // esi

  priv = self->_priv;
  v3 = gdt + 128;
  v4 = gdt + 144;
  v5 = (_DWORD *)(gdt + 152);
  *priv = *(_DWORD *)(gdt + 128);
  priv[1] = *(_DWORD *)(v3 + 4);
  priv[2] = *(_DWORD *)v4;
  priv[3] = *(_DWORD *)(v4 + 4);
  priv[6] = *v5;
  priv[7] = v5[1];
  v6 = self->segmentBase - 0x40000000;
  *(_WORD *)(v3 + 2) = self->segmentBase;
  *(_BYTE *)(v3 + 4) = BYTE2(v6);
  *(_BYTE *)(v3 + 7) = HIBYTE(v6);
  *(_BYTE *)(v3 + 5) &= 0xE0u;
  *(_BYTE *)(v3 + 5) |= 0x1Au;
  *(_BYTE *)(v3 + 5) &= 0x9Fu;
  *(_BYTE *)(v3 + 5) = *(_BYTE *)(v3 + 5);
  *(_BYTE *)(v3 + 5) |= 0x80u;
  *(_BYTE *)(v3 + 6) &= ~0x40u;
  *(_BYTE *)(v3 + 6) &= ~0x80u;
  *(_WORD *)v3 = -1;
  *(_BYTE *)(v3 + 6) &= 0xF0u;
  *(_BYTE *)(v3 + 6) = *(_BYTE *)(v3 + 6);
  *(_WORD *)(v4 + 2) = 11908;
  *(_BYTE *)(v4 + 4) = 0;
  *(_BYTE *)(v4 + 7) = -64;
  *(_BYTE *)(v4 + 5) &= 0xE0u;
  *(_BYTE *)(v4 + 5) |= 0x1Au;
  *(_BYTE *)(v4 + 5) &= 0x9Fu;
  *(_BYTE *)(v4 + 5) = *(_BYTE *)(v4 + 5);
  *(_BYTE *)(v4 + 5) |= 0x80u;
  *(_BYTE *)(v4 + 6) |= 0x40u;
  *(_BYTE *)(v4 + 6) &= ~0x80u;
  *(_WORD *)v4 = -1;
  *(_BYTE *)(v4 + 6) &= 0xF0u;
  *(_BYTE *)(v4 + 6) = *(_BYTE *)(v4 + 6);
  v7 = (void *)IOMalloc(a1: 2048);
  priv[8] = v7;
  bzero(a1: v7, a2: 0x800u);
  v8 = priv[8] - 0x40000000;
  v9 = gdt + 152;
  *(_WORD *)(gdt + 154) = *((_WORD *)priv + 16);
  *(_BYTE *)(v9 + 4) = BYTE2(v8);
  *(_BYTE *)(v9 + 7) = HIBYTE(v8);
  *(_BYTE *)(v9 + 5) &= 0xE0u;
  *(_BYTE *)(v9 + 5) |= 0x12u;
  *(_BYTE *)(v9 + 5) &= 0x9Fu;
  *(_BYTE *)(v9 + 5) = *(_BYTE *)(v9 + 5);
  *(_BYTE *)(v9 + 5) |= 0x80u;
  *(_BYTE *)(v9 + 6) |= 0x40u;
  *(_BYTE *)(v9 + 6) &= ~0x80u;
  *(_WORD *)v9 = 2047;
  *(_BYTE *)(v9 + 6) &= 0xF0u;
  *(_BYTE *)(v9 + 6) = *(_BYTE *)(v9 + 6);
  *(_BYTE *)(v9 + 6) &= ~0x40u;
  ATI_Bios_StackOffset = 2048;
  ATI_Bios_StackSelector = 152;
}
```

## -[ATI_BIOS restoreCodeSegments] (0x2bc8-0x2c2e)

```c
void __cdecl -[ATI_BIOS restoreCodeSegments](ATI_BIOS *self, SEL a2)
{
  _DWORD *priv; // eax
  int v3; // edx
  _DWORD *v4; // ecx
  _DWORD *v5; // ebx

  priv = self->_priv;
  v3 = gdt + 128;
  v4 = (_DWORD *)(gdt + 144);
  v5 = (_DWORD *)(gdt + 152);
  *(_DWORD *)(gdt + 128) = *priv;
  *(_DWORD *)(v3 + 4) = priv[1];
  *v4 = priv[2];
  v4[1] = priv[3];
  *v5 = priv[6];
  v5[1] = priv[7];
  IOFree(a1: priv[8], a2: 2048);
}
```

## -[ATI_BIOS createDataSegment:size:] (0x2c30-0x2d04)

```c
int __cdecl -[ATI_BIOS createDataSegment:size:](ATI_BIOS *self, SEL a2, unsigned int a3, unsigned int a4)
{
  _DWORD *v4; // edx
  _DWORD *priv; // eax
  int v7; // ecx
  unsigned int v8; // eax

  v4 = (_DWORD *)(gdt + 136);
  priv = self->_priv;
  if ( a4 <= 0x10000 )
  {
    priv[4] = *v4;
    priv[5] = v4[1];
    v7 = gdt + 136;
    *(_WORD *)(gdt + 138) = a3;
    *(_BYTE *)(v7 + 4) = (a3 - 0x40000000) >> 16;
    *(_BYTE *)(v7 + 7) = (a3 - 0x40000000) >> 24;
    *(_BYTE *)(v7 + 5) &= 0xE0u;
    *(_BYTE *)(v7 + 5) |= 0x12u;
    *(_BYTE *)(v7 + 5) &= 0x9Fu;
    *(_BYTE *)(v7 + 5) = *(_BYTE *)(v7 + 5);
    *(_BYTE *)(v7 + 5) |= 0x80u;
    *(_BYTE *)(v7 + 6) |= 0x40u;
    v8 = a4 - 1;
    if ( a4 - 1 > 0xFFFFF )
    {
      *(_BYTE *)(v7 + 6) |= 0x80u;
      *(_WORD *)v7 = (((a4 + 4095) & 0xFFFFF000) - 4096) >> 12;
      v8 = (((a4 + 4095) & 0xFFFFF000) - 4096) >> 28;
    }
    else
    {
      *(_BYTE *)(v7 + 6) &= ~0x80u;
      *(_WORD *)v7 = v8;
      LOBYTE(v8) = BYTE2(v8) & 0xF;
    }
    *(_BYTE *)(v7 + 6) &= 0xF0u;
    *(_BYTE *)(v7 + 6) |= v8;
    return 0;
  }
  else
  {
    IOLog(a1: "ATI_BIOS: Data Segment size exceeded (0x%x)\n", a4);
    return 3;
  }
}
```

## -[ATI_BIOS restoreDataSegment] (0x2d04-0x2d28)

```c
void __cdecl -[ATI_BIOS restoreDataSegment](ATI_BIOS *self, SEL a2)
{
  int v2; // edx
  _DWORD *priv; // eax

  v2 = gdt + 136;
  priv = self->_priv;
  *(_DWORD *)(gdt + 136) = priv[4];
  *(_DWORD *)(v2 + 4) = priv[5];
}
```

## -[ATI_BIOS doBios:dataSeg:] (0x2d28-0x2d6c)

```c
int __cdecl -[ATI_BIOS doBios:dataSeg:](id a1, int a2, int a3, char a4)
{
  int v4; // esi

  v4 = ATIbios16(a1: a3);
  objc_msgSend(a1, a2: sel_restoreCodeSegments);
  if ( a4 != 0 )
    objc_msgSend(a1, a2: sel_restoreDataSegment);
  return v4;
}
```

## -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:] (0x2d6c-0x2e6a)

```c
int __cdecl -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:](
        ATI_BIOS *self,
        SEL a2,
        unsigned int a3,
        char a4,
        unsigned int a5,
        unsigned int a6,
        $D36094C8510EB81E7056FECE159970B1 *a7,
        unsigned __int8 a8,
        const char *a9)
{
  int result; // eax
  char v10; // dl
  id v11; // eax
  char v12; // [esp+Ch] [ebp-38h]
  _WORD v13[6]; // [esp+14h] [ebp-30h] BYREF
  char v14; // [esp+20h] [ebp-24h]
  char v15; // [esp+21h] [ebp-23h]
  __int16 v16; // [esp+24h] [ebp-20h]

  v12 = 0;
  if ( self->initialized == 0 )
    return 1;
  if ( a6 == 128 )
    return 3;
  -[ATI_BIOS initBIOSBuf:function:](a1: self, a2: sel_initBIOSBuf_function_, v13, a8);
  v10 = 0;
  if ( a4 != 0 )
    v10 = 16;
  v14 = ((_BYTE)a5 << 6) | a3 | v10;
  v15 = a6;
  if ( a6 == 129 )
  {
    result = -[ATI_BIOS createDataSegment:size:](a1: self, a2: sel_createDataSegment_size_, a7, 30);
    if ( result != 0 )
      return result;
    v16 = 136;
    v13[4] = 0;
    v12 = 1;
  }
  v11 = -[ATI_BIOS doBios:dataSeg:](a1: self, a2: sel_doBios_dataSeg_, v13, v12);
  if ( v11 != nullptr )
  {
    IOLog(a1: "ATI_BIOS %s: ATIbios32() returned %d\n", a9, v11);
  }
  else
  {
    if ( HIBYTE(v13[2]) == 0 )
      return 0;
    IOLog(a1: "ATI_BIOS %s: ah = 0x%x on return from ATIbios32()\n", a9, HIBYTE(v13[2]));
  }
  return 2;
}
```

## +[ATIRageDisplayDriverKernelServerInstance kernelServerInstance] (0x2e6c-0x2e78)

```c
$8EF4127CF77ECA3DDB612FCF233DC3A8 **__cdecl +[ATIRageDisplayDriverKernelServerInstance kernelServerInstance](
        id a1,
        SEL a2)
{
  return ($8EF4127CF77ECA3DDB612FCF233DC3A8 **)&ATIRageDisplayDriver_instance;
}
```

## +[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver] (0x2e78-0x2e84)

```c
int __cdecl +[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver](id a1, SEL a2)
{
  return 500;
}
```

## _ATIbios16 (0x2efc-0x2f5b)

```c
int __cdecl ATIbios16(int a1)
{
  kernDataSel = 16;
  if ( *(_DWORD *)(a1 + 44) > 0xFFFFu )
  {
    IOLog(a1: "ATIbios16: invalid offset (0x%x)\n", *(_DWORD *)(a1 + 44));
    return -1;
  }
  else
  {
    ATI_Bios_Offset = *(unsigned __int16 *)(a1 + 44);
    ATI_Bios_Selector = *(_WORD *)(a1 + 32);
    *(_WORD *)(a1 + 32) = 144;
    *(_DWORD *)(a1 + 44) = 0;
    ((void (__stdcall *)(int))_ATIbios32)(a1);
    return 0;
  }
}
```
