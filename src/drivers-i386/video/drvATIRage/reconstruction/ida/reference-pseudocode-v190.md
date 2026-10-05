# Reference IDA pseudocode export

IDA 9.4 Hex-Rays; functions=61


## 0x0 -[ATI initFromDeviceDescription:]

```c
id __cdecl -[ATI initFromDeviceDescription:](ATI *self, SEL a2, id a3)
{
  id v3; // eax
  const char *v5; // eax
  const char *v6; // eax
  ATI_BIOS *v7; // eax
  id v8; // edx
  unsigned int v9; // ecx
  unsigned __int32 v10; // eax
  unsigned int v11; // esi
  unsigned __int32 v12; // eax
  unsigned __int32 v13; // eax
  unsigned __int8 *queryData; // esi
  const char *v15; // eax
  const char *v16; // eax
  const char *v17; // eax
  const char *v18; // edx
  const char *v19; // eax
  const char *v20; // eax
  id v21; // eax
  const char *v22; // eax
  const char *v23; // eax
  _DWORD *v24; // eax
  id v25; // edx
  unsigned int v26; // ecx
  unsigned __int16 v27; // dx
  unsigned __int32 v28; // eax
  unsigned int v29; // ecx
  const char *v30; // [esp-20h] [ebp-64h]
  const char *v31; // [esp-1Ch] [ebp-60h]
  id v32; // [esp-Ch] [ebp-50h]
  id v33; // [esp-Ch] [ebp-50h]
  const char *v34; // [esp-Ch] [ebp-50h]
  id v35; // [esp-Ch] [ebp-50h]
  id v36; // [esp-Ch] [ebp-50h]
  const char *v37; // [esp+10h] [ebp-34h]
  id v38; // [esp+14h] [ebp-30h]
  int v39; // [esp+18h] [ebp-2Ch] BYREF
  objc_super v40; // [esp+1Ch] [ebp-28h] BYREF
  char __dst[32]; // [esp+24h] [ebp-20h] BYREF

  self->engineStarted = 0;
  if ( objc_msgSend(a1: a3, a2: aGetpcideviceFu, 0, 0, 0) != nullptr )
  {
    v3 = -[ATI name](a1: self, a2: aName);
    IOLog(a1: "ATIRage: ATIRage adapter not found\n", v3);
    v40.receiver = self;
    v40.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v40, a2: sel_free);
  }
  if ( +[ATI_BIOS ATIPresent:](a1: aAtiBios, a2: sel_ATIPresent_, &v39) == 0 )
  {
    v5 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: ATI BIOS not found\n", v5);
    v40.receiver = self;
    v40.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v40, a2: sel_free);
  }
  if ( -[ATI fixDeviceDescriptionForPCI:](a1: self, a2: sel_fixDeviceDescriptionForPCI_, a3) == 0 )
  {
    v6 = (const char *)-[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Configuration error. Aborting...\n", v6);
    v40.receiver = self;
    v40.super_class = (Class)stru_8158.super_class;
    return -[ATI free](a1: &v40, a2: sel_free);
  }
  v40.receiver = self;
  v40.super_class = (Class)stru_8158.super_class;
  if ( -[ATI initFromDeviceDescription:](a1: &v40, a2: sel_initFromDeviceDescription_, a3) != nullptr )
  {
    v7 = +[ATI_BIOS alloc](a1: aAtiBios, a2: aAlloc);
    v8 = -[ATI_BIOS initAtSegmentAddress:](a1: v7, a2: sel_initAtSegmentAddress_);
    self->atiBios = v8;
    if ( v8 != nullptr )
    {
      self->queryDataSize = 0;
      objc_msgSend(a1: self->atiBios, a2: sel_getIOBaseAddress_relocatable_, &self->baseAddress, &self->relocatableIO);
      if ( self->relocatableIO != 0 )
        v9 = self->baseAddress + 132;
      else
        v9 = self->baseAddress + 17408;
      v10 = __indword(v9);
      v11 = v10;
      __outdword(v9, 0x55555555u);
      _InterlockedIncrement(&xxx_92);
      v12 = __indword(v9);
      if ( v12 != 1431655765 )
      {
        v33 = -[ATI name](a1: self, a2: aName);
        IOLog(a1: "%s: Rage/Rage II/Rage Pro BIOS not found.\n", v33);
        return -[ATI free](a1: self, a2: sel_free);
      }
      __outdword(v9, 0xAAAAAAAA);
      _InterlockedIncrement(&xxx_92);
      v13 = __indword(v9);
      if ( v13 != -1431655766 )
      {
        v32 = -[ATI name](a1: self, a2: aName);
        IOLog(a1: "%s: Mach64/Rage failed second regsiter test.\n", v32);
        return -[ATI free](a1: self, a2: sel_free);
      }
      __outdword(v9, v11);
      _InterlockedIncrement(&xxx_92);
      if ( -[ATI getQueryData](a1: self, a2: sel_getQueryData) == 0 )
      {
        queryData = (unsigned __int8 *)self->queryData;
        self->supportsGamma = (queryData[20] & 0x40) != 0;
        self->supportsGrey256 = (queryData[20] & 0x20) != 0;
        self->vramBytes = -[ATI displayMemorySize](a1: self, a2: sel_displayMemorySize);
        v15 = (const char *)IOFindNameForValue(a1: queryData[9], a2: &ATI_AsicTypeValues);
        strcpy(__dst, __src: v15);
        if ( queryData[9] == 0xD7 )
        {
          v16 = (const char *)IOFindNameForValue(a1: queryData[8], a2: &ATI_AsicSubTypeValues);
          strcat(__s1: __dst, __s2: v16);
        }
        v17 = (const char *)-[ATI name](a1: self, a2: aName);
        IOLog(a1: "%s: ATI Rage/Rage II/Rage Pro Found!\n", v17);
        v31 = (const char *)IOFindNameForValue(a1: queryData[11], a2: &ATI_memSizeValues);
        v18 = "NO";
        if ( self->supportsGamma != 0 )
          v18 = "YES";
        v30 = v18;
        v19 = (const char *)-[ATI name](a1: self, a2: aName);
        IOLog(a1: "%s: Type %s.  Gamma: %s.  Memory: %s.\n", v19, __dst, v30, v31);
        v38 = objc_msgSend(a1: a3, a2: aConfigtable);
        self->ramdacStyle = 0;
        v37 = (const char *)objc_msgSend(a1: v38, a2: aValueforstring, "RAMDAC Style");
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
            v20 = (const char *)-[ATI name](a1: self, a2: aName);
            IOLog(a1: "%s: ramdacStyle from table = %s\n", v20, v37);
          }
          objc_msgSend(a1: v38, a2: aFreestring, v37);
        }
        v21 = objc_msgSend(a1: v38, a2: aValueforstring, "Display Mode");
        if ( v21 != nullptr )
        {
          if ( -[ATI parseModeString:](a1: self, a2: sel_parseModeString_, v21) == 0 )
          {
            if ( dword_42F4[34 * self->modeNumber] == 4 )
            {
              v34 = (const char *)IOFindNameForValue(a1: self->colorConfig, a2: &colorConfigValues);
              v23 = (const char *)-[ATI name](a1: self, a2: aName);
              IOLog(a1: "%s: 24 Bit Color Configuration = %s\n", v23, v34);
            }
            if ( objc_msgSend(a1: self->atiBios, a2: sel_setApertureEnable_VGAAperture_apertureAdrs_, 1, 0, 0) == nullptr )
            {
              v24 = objc_msgSend(a1: a3, a2: aMemoryrangelis);
              v25 = -[ATI mapFrameBufferAtPhysicalAddress:length:](a1: self, a2: aMapframebuffer, *v24, 0x800000);
              self->vram = v25;
              if ( v25 != nullptr )
              {
                if ( self->relocatableIO != 0 )
                  v26 = self->baseAddress + 160;
                else
                  v26 = self->baseAddress + 24576;
                v27 = v26;
                v28 = __indword(v26);
                v29 = v28;
                LOBYTE(v29) = v28 & 0xEF;
                __outdword(v27, v29);
                _InterlockedIncrement(&xxx_92);
                register_base_address = (int)self->vram + 8387584;
                -[ATI updateModeList](a1: self, a2: sel_updateModeList);
                v40.receiver = self;
                v40.super_class = (Class)stru_8158.super_class;
                qmemcpy(
                  -[ATI displayInfo](a1: &v40, a2: aDisplayinfo),
                  (char *)&AtiModeList + 136 * self->modeNumber,
                  0x88u);
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
                v36 = -[ATI name](a1: self, a2: aName);
                IOLog(a1: "%s: VRAM test failure, aborting\n", v36);
              }
              else
              {
                v35 = -[ATI name](a1: self, a2: aName);
                IOLog(a1: "%s: Unable to map frame buffer\n", v35);
              }
            }
          }
        }
        else
        {
          v22 = (const char *)-[ATI name](a1: self, a2: aName);
          IOLog(a1: "%s: No Display Mode found; aborting\n", v22);
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


## 0x680 -[ATI fixDeviceDescriptionForPCI:]

```c
char __cdecl -[ATI fixDeviceDescriptionForPCI:](ATI *self, SEL a2, id a3)
{
  int i; // edi
  int v4; // esi
  int v5; // ecx
  int v6; // eax
  char v7; // al
  int j; // edi
  int k; // edi
  int v10; // esi
  int m; // edi
  int v12; // esi
  int v13; // esi
  int n; // edi
  int v15; // esi
  int v16; // eax
  int v17; // eax
  int v18; // edx
  int v19; // ecx
  id v20; // eax
  const char *v21; // eax
  unsigned __int32 v22; // eax
  unsigned int v23; // esi
  int v24; // edi
  id v25; // eax
  unsigned int v26; // esi
  id v27; // eax
  id v29; // [esp-14h] [ebp-128h]
  id v30; // [esp-14h] [ebp-128h]
  unsigned int v31; // [esp+Ch] [ebp-108h]
  unsigned int v32; // [esp+Ch] [ebp-108h]
  int v33; // [esp+10h] [ebp-104h]
  int v34; // [esp+10h] [ebp-104h]
  unsigned int v35; // [esp+18h] [ebp-FCh]
  unsigned int v36; // [esp+1Ch] [ebp-F8h]
  id v37; // [esp+30h] [ebp-E4h]
  char v38; // [esp+34h] [ebp-E0h]
  int v39; // [esp+38h] [ebp-DCh]
  int v40; // [esp+38h] [ebp-DCh]
  int v41; // [esp+3Ch] [ebp-D8h]
  int v42; // [esp+3Ch] [ebp-D8h]
  int v43; // [esp+40h] [ebp-D4h] BYREF
  _DWORD v44[18]; // [esp+44h] [ebp-D0h] BYREF
  _DWORD v45[18]; // [esp+8Ch] [ebp-88h] BYREF
  _DWORD v46[16]; // [esp+D4h] [ebp-40h] BYREF

  v39 = 0;
  v38 = 1;
  v37 = -[ATI class](a1: self, a2: aClass);
  v41 = 0;
  for ( i = 16; i <= 39; i += 4 )
  {
    objc_msgSend(a1: v37, a2: aGetpciconfigda, v44, (unsigned __int8)i, a3);
    v4 = -16;
    if ( (v44[0] & 1) != 0 )
      v4 = -4;
    objc_msgSend(a1: v37, a2: aSetpciconfigda, v44[0] | v4, (unsigned __int8)i, a3);
    objc_msgSend(a1: v37, a2: aGetpciconfigda, &v43, (unsigned __int8)i, a3);
    objc_msgSend(a1: v37, a2: aSetpciconfigda, v44[0], (unsigned __int8)i, a3);
    v5 = v43 & v4;
    if ( (v43 & v4) != 0 )
    {
      if ( (v44[0] & 1) != 0 )
      {
        v6 = 2 * v39;
        v45[v6] = v44[0] & v4;
        v45[v6 + 1] = -v5;
        v44[++v39] = i;
      }
      else
      {
        v33 = 2 * v41;
        v46[v33] = v4 & v44[0];
        v46[v33 + 1] = -(v43 & v4);
        v44[v41++ + 10] = i;
      }
    }
  }
  v7 = 1;
  for ( j = 0; v41 > j; ++j )
  {
    if ( v46[2 * j] <= 0x3FFFFFu )
      v7 = 0;
  }
  for ( k = 0; v39 > k; ++k )
  {
    if ( v45[2 * k] <= 0xFFu )
      v7 = 0;
  }
  if ( v7 == 0 )
  {
    v10 = *(_DWORD *)objc_msgSend(a1: a3, a2: aMemoryrangelis);
    for ( m = 0; v41 > m; ++m )
    {
      v12 = (v46[2 * m + 1] + v10 - 1) & -v46[2 * m + 1];
      v46[2 * m] = v12;
      objc_msgSend(a1: v37, a2: aSetpciconfigda, v12, LOBYTE(v44[m + 10]), a3);
      v10 = v46[2 * m + 1] + v12;
    }
    v13 = *(_DWORD *)objc_msgSend(a1: a3, a2: aPortrangelist);
    for ( n = 0; v39 > n; ++n )
    {
      v15 = (v45[2 * n + 1] + v13 - 1) & -v45[2 * n + 1];
      v45[2 * n] = v15;
      objc_msgSend(a1: v37, a2: aSetpciconfigda, v15, LOBYTE(v44[n + 1]), a3);
      v13 = v45[2 * n + 1] + v15;
    }
  }
  v16 = 2 * v41;
  v46[v16] = 655360;
  v46[v16 + 1] = 0x20000;
  v17 = 8 * v41 + 8;
  *(_DWORD *)((char *)v46 + v17) = 786432;
  *(_DWORD *)((char *)&v46[1] + v17) = 0x10000;
  v42 = v41 + 2;
  v34 = 2 * v39;
  v45[v34] = 944;
  v45[v34 + 1] = 48;
  v18 = 8 * v39 + 8;
  *(_DWORD *)((char *)v45 + v18) = 258;
  *(_DWORD *)((char *)&v45[1] + v18) = 1;
  v19 = 8 * v39 + 16;
  *(_DWORD *)((char *)v45 + v19) = 18152;
  *(_DWORD *)((char *)&v45[1] + v19) = 1;
  v40 = v39 + 3;
  objc_msgSend(a1: a3, a2: aSetmemoryrange, 0, 0);
  if ( objc_msgSend(a1: a3, a2: aSetmemoryrange, v46, v42) != nullptr )
  {
    v35 = start_base_address;
    v36 = v42 - 2;
    self->overrideStartBaseAddress = 0;
    v20 = objc_msgSend(a1: a3, a2: aConfigtable);
    if ( v20 != nullptr )
    {
      v21 = (const char *)objc_msgSend(a1: v20, a2: aValueforstring, "FB Address");
      if ( v21 != nullptr && *v21 != 0 )
      {
        v22 = strtol(__str: v21, __endptr: nullptr, __base: 16) & 0x7F000000;
        if ( v22 > 0x3FFFFFF )
        {
          v35 = v22;
          self->overrideStartBaseAddress = 1;
        }
      }
    }
    v23 = 0;
    if ( v42 != 2 )
    {
      do
      {
        v31 = v35;
        if ( v35 <= 0xFEFFFFFF )
        {
          v24 = 2 * v23;
          do
          {
            v46[v24] = v31;
            objc_msgSend(a1: a3, a2: aSetmemoryrange, 0, 0);
            if ( objc_msgSend(a1: a3, a2: aSetmemoryrange, v46, v23) == nullptr )
              break;
            v31 += v46[v24 + 1];
          }
          while ( v31 <= 0xFEFFFFFF );
        }
        ++v23;
      }
      while ( v36 > v23 );
    }
    objc_msgSend(a1: a3, a2: aSetmemoryrange, 0, 0);
    v25 = objc_msgSend(a1: a3, a2: aSetmemoryrange, v46, v42);
    if ( v25 != nullptr )
    {
      -[ATI stringFromReturn:](a1: self, a2: aStringfromretu, v25);
      v29 = -[ATI name](a1: self, a2: aName);
      IOLog(a1: "%s: Error in setMemoryRangeList (%s)\n", v29);
      return 0;
    }
    v26 = 0;
    v32 = 16;
    if ( v42 != 2 )
    {
      do
      {
        if ( v32 > 0x27 )
          break;
        objc_msgSend(a1: v37, a2: aSetpciconfigda, v46[2 * v26++], (unsigned __int8)v32, a3);
        v32 += 4;
      }
      while ( v36 > v26 );
    }
  }
  objc_msgSend(a1: a3, a2: aSetportrangeli, 0, 0);
  v27 = objc_msgSend(a1: a3, a2: aSetportrangeli, v45, v40);
  if ( v27 != nullptr )
  {
    -[ATI stringFromReturn:](a1: self, a2: aStringfromretu, v27);
    v30 = -[ATI name](a1: self, a2: aName);
    IOLog(a1: "%s: Error in setPortRangeList (%s)\n", v30);
    return 0;
  }
  return v38;
}
```


## 0xCE0 -[ATI getQueryData]

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


## 0xE10 -[ATI parseModeString:]

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


## 0xEA0 -[ATI updateModeList]

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


## 0x10BC -[ATI isModeValid:]

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


## 0x1144 -[ATI verifyMemoryMap]

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


## 0x11A8 -[ATI free]

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


## 0x1238 -[ATI enterLinearMode]

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
    v3 = displayInfoToColorDepth(a1: (int)v2);
    displayInfoToColorSpace(a1: (int)v2);
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


## 0x135C -[ATI revertToVGAMode]

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

  qmemcpy(v8, byte_3BC2, 30);
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


## 0x1458 _waitForFIFO

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


## 0x148C _waitForIdle

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


## 0x14D8 _doBlit

```c
int __cdecl doBlit(
        unsigned int a1,
        unsigned int a2,
        unsigned int a3,
        unsigned int a4,
        unsigned int a5,
        unsigned int a6)
{
  unsigned int v6; // ecx
  unsigned int v7; // edx
  unsigned int v8; // edx
  unsigned int v9; // esi
  _DWORD *v10; // edx
  int v11; // eax
  unsigned int v12; // eax
  int result; // eax
  int v14; // [esp+Ch] [ebp-1Ch]
  unsigned int v15; // [esp+10h] [ebp-18h]
  unsigned int v16; // [esp+14h] [ebp-14h]
  unsigned int v17; // [esp+18h] [ebp-10h]
  int v18; // [esp+1Ch] [ebp-Ch]
  int v19; // [esp+20h] [ebp-8h]
  int v20; // [esp+24h] [ebp-4h]

  v6 = a5;
  v7 = a5 - a1;
  if ( (int)(a5 - a1) < 0 )
    v7 = a1 - a5;
  if ( a3 > v7 )
  {
    v8 = a6 - a2;
    if ( (int)(a6 - a2) < 0 )
      v8 = a2 - a6;
    if ( a4 > v8 )
    {
      v14 = 0;
      if ( a1 >= a5 )
      {
        LOBYTE(v14) = 1;
        v17 = a1;
      }
      else
      {
        v17 = a3 + a1 - 1;
        v6 = a3 + a5 - 1;
      }
      v16 = v6;
      if ( a6 <= a2 )
      {
        LOBYTE(v14) = v14 | 2;
        v15 = a2;
LABEL_14:
        v9 = a6;
        goto LABEL_15;
      }
      v15 = a4 + a2 - 1;
      v9 = a4 + a6 - 1;
LABEL_15:
      waitForIdle();
      waitForFIFO(a1: 10);
      v10 = (_DWORD *)register_base_address;
      v20 = *(_DWORD *)(register_base_address + 728);
      v19 = *(_DWORD *)(register_base_address + 436);
      v18 = *(_DWORD *)(register_base_address + 304);
      *(_DWORD *)(register_base_address + 728) = 768;
      v10[109] = 0;
      v11 = v14 | v18 & 0x80;
      LOBYTE(v11) = v11 | 0x18;
      v10[76] = v11;
      v10[99] = v15 | (v17 << 16);
      v12 = a4 | (a3 << 16);
      v10[102] = v12;
      v10[67] = v9 | (v16 << 16);
      v10[70] = v12;
      waitForFIFO(a1: 3);
      result = register_base_address;
      *(_DWORD *)(register_base_address + 728) = v20;
      *(_DWORD *)(result + 436) = v19;
      *(_DWORD *)(result + 304) = v18;
      return result;
    }
  }
  v14 = 3;
  v17 = a1;
  v15 = a2;
  v16 = a5;
  goto LABEL_14;
}
```


## 0x161C -[ATI showCursor:frame:token:]

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


## 0x1660 -[ATI moveCursor:frame:token:]

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


## 0x16A4 -[ATI hideCursor:]

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


## 0x16E0 _doFill

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


## 0x1768 -[ATI initEngine]

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


## 0x19A0 -[ATI resetEngine]

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
  _InterlockedIncrement(&xxx_92);
  v5 = LOWORD(self->baseAddress) + 208;
  v6 = __indword(v5);
  v7 = v6;
  BYTE1(v7) = BYTE1(v6) | 1;
  __outdword(v5, v7);
  _InterlockedIncrement(&xxx_92);
  LOWORD(v7) = LOWORD(self->baseAddress) + 160;
  v8 = __indword(v7);
  __outdword(v7, v8 & 0xFF00FFFF | 0xAE0000);
  _InterlockedIncrement(&xxx_92);
}
```


## 0x1A1C -[ATI displayModeCount]

```c
unsigned int __cdecl -[ATI displayModeCount](ATI *self, SEL a2)
{
  return AtiModeListCount;
}
```


## 0x1A28 -[ATI displayModes]

```c
$514E7C50D28E54AB164B6500F83867A3 *__cdecl -[ATI displayModes](ATI *self, SEL a2)
{
  return ($514E7C50D28E54AB164B6500F83867A3 *)&AtiModeList;
}
```


## 0x1A34 -[ATI displayMemorySize]

```c
unsigned int __cdecl -[ATI displayMemorySize](ATI *self, SEL a2)
{
  return memSizeToBytes(a1: *((_BYTE *)self->queryData + 11));
}
```


## 0x1A50 -[ATI setPendingDisplayMode:]

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


## 0x1AE8 -[ATI setIntValues:forParameter:count:]

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


## 0x1BB8 _isATI68880RevC

```c
_BOOL4 __cdecl isATI68880RevC(__int16 a1)
{
  unsigned __int8 v1; // al

  v1 = __inbyte(a1 + 195);
  return v1 == 0xD0;
}
```


## 0x1BDC _SetGammaValue

```c
unsigned int __cdecl SetGammaValue(__int16 a1, int a2, int a3, int a4, int a5)
{
  unsigned int result; // eax

  __outbyte(a1 + 193, (unsigned int)(a5 * a2) >> 6);
  _InterlockedIncrement(&xxx_8);
  __outbyte(a1 + 193, (unsigned int)(a5 * a3) >> 6);
  _InterlockedIncrement(&xxx_8);
  result = (unsigned int)(a5 * a4) >> 6;
  __outbyte(a1 + 193, result);
  _InterlockedIncrement(&xxx_8);
  return result;
}
```


## 0x1C30 -[ATI setGammaTable]

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


## 0x1DA4 -[ATI setBrightness:token:]

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


## 0x1DE0 -[ATI setTransferTable:count:]

```c
id __cdecl -[ATI setTransferTable:count:](ATI *self, SEL a2, const unsigned int *a3, int a4)
{
  _BYTE *queryData; // eax
  char v5; // bl
  int v6; // edx
  int ramdacStyle; // eax
  char *v8; // eax
  int v9; // eax
  int i; // esi
  char *redTransferTable; // ebx
  int v12; // eax
  int j; // esi
  char *greenTransferTable; // [esp+Ch] [ebp-Ch]
  unsigned __int8 v16; // [esp+10h] [ebp-8h]
  char v17; // [esp+14h] [ebp-4h]

  queryData = self->queryData;
  v16 = queryData[12];
  v5 = 2;
  if ( self->supportsGrey256 != 0 )
    v5 = 0;
  v6 = (unsigned __int8)queryData[9];
  if ( v6 != 67 && v6 != 69 )
  {
    if ( v16 == 5 )
      goto LABEL_11;
    if ( v16 <= 5u )
    {
      if ( v16 != 2 )
        goto LABEL_12;
LABEL_11:
      v5 = 0;
      goto LABEL_12;
    }
    if ( v16 == 21 && isATI68880RevC(a1: self->baseAddress) )
      goto LABEL_11;
  }
LABEL_12:
  v17 = v5;
  ramdacStyle = self->ramdacStyle;
  if ( ramdacStyle == 1 )
  {
    v17 = 0;
  }
  else if ( ramdacStyle == 2 )
  {
    v17 = 2;
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
    for ( i = 0; a4 > i; ++i )
    {
      redTransferTable = self->redTransferTable;
      greenTransferTable = self->greenTransferTable;
      v12 = LOBYTE(a3[i]) >> v17;
      self->blueTransferTable[i] = v12;
      greenTransferTable[i] = v12;
      redTransferTable[i] = v12;
    }
  }
  else if ( v9 == 2 )
  {
    for ( j = 0; a4 > j; ++j )
    {
      self->redTransferTable[j] = HIBYTE(a3[j]) >> v17;
      self->greenTransferTable[j] = BYTE2(a3[j]) >> v17;
      self->blueTransferTable[j] = BYTE1(a3[j]) >> v17;
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


## 0x1FCC _displayInfoToColorSpace

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


## 0x2034 _colorDepthToColorSpace

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


## 0x2084 _displayInfoToColorDepth

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


## 0x20D4 _memSizeToBytes

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


## 0x2154 +[ATIRageDisplayDriverKernelServerInstance kernelServerInstance]

```c
$8EF4127CF77ECA3DDB612FCF233DC3A8 **__cdecl +[ATIRageDisplayDriverKernelServerInstance kernelServerInstance](
        id a1,
        SEL a2)
{
  return ($8EF4127CF77ECA3DDB612FCF233DC3A8 **)&ATIRageDisplayDriver_instance;
}
```


## 0x2160 +[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver]

```c
int __cdecl +[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver](id a1, SEL a2)
{
  return 500;
}
```


## 0x216C +[ATI_BIOS ATIPresent:]

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


## 0x2208 -[ATI_BIOS init]

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


## 0x22AC -[ATI_BIOS initAtSegmentAddress:]

```c
id __cdecl -[ATI_BIOS initAtSegmentAddress:](ATI_BIOS *self, SEL a2, unsigned int a3)
{
  objc_super v4; // [esp+4h] [ebp-8h] BYREF

  self->segmentBase = a3;
  self->_priv = (void *)IOMalloc(a1: 36);
  self->initialized = 1;
  v4.receiver = self;
  v4.super_class = (Class)stru_81A8.ext;
  return -[ATI_BIOS init](a1: &v4, a2: sel_init);
}
```


## 0x22F0 -[ATI_BIOS free]

```c
id __cdecl -[ATI_BIOS free](ATI_BIOS *self, SEL a2)
{
  objc_super v3; // [esp+4h] [ebp-8h] BYREF

  if ( self->initialized != 0 )
    IOFree(a1: self->_priv, a2: 36);
  v3.receiver = self;
  v3.super_class = (Class)stru_81A8.ext;
  return -[ATI_BIOS free](a1: &v3, a2: sel_free);
}
```


## 0x2334 -[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:]

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


## 0x2368 -[ATI_BIOS setVGAMode:gamma:]

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


## 0x2404 -[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:]

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


## 0x2438 -[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]

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


## 0x2508 -[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:]

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


## 0x25D4 -[ATI_BIOS querySize:size:]

```c
int __cdecl -[ATI_BIOS querySize:size:](ATI_BIOS *self, SEL a2, char a3, unsigned int *a4)
{
  *a4 = 4096;
  return 0;
}
```


## 0x25E8 -[ATI_BIOS deviceQuery:bufferSize:buffer:]

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


## 0x26A8 -[ATI_BIOS setDPMSMode:]

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


## 0x2730 -[ATI_BIOS getDPMSMode:]

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


## 0x27A4 -[ATI_BIOS setAPMState:]

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


## 0x282C -[ATI_BIOS getAPMState:]

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


## 0x28A0 -[ATI_BIOS getIOBaseAddress:relocatable:]

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


## 0x291C -[ATI_BIOS getRefreshRate:]

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


## 0x29C0 -[ATI_BIOS changeRefreshRate:]

```c
int __cdecl -[ATI_BIOS changeRefreshRate:](ATI_BIOS *self, SEL a2, char *a3)
{
  return 3;
}
```


## 0x29CC -[ATI_BIOS initBIOSBuf:function:]

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


## 0x2A1C -[ATI_BIOS setupCodeSegments]

```c
void __cdecl -[ATI_BIOS setupCodeSegments](ATI_BIOS *self, SEL a2)
{
  _DWORD *priv; // esi
  int v3; // eax
  _DWORD *v4; // edx
  unsigned int v5; // edx
  int v6; // eax
  int v7; // ebx
  void *v8; // eax
  int v9; // eax
  _DWORD *v10; // [esp+Ch] [ebp-4h]

  priv = self->_priv;
  v3 = gdt + 128;
  v4 = (_DWORD *)(gdt + 144);
  v10 = (_DWORD *)(gdt + 152);
  *priv = *(_DWORD *)(gdt + 128);
  priv[1] = *(_DWORD *)(v3 + 4);
  priv[2] = *v4;
  priv[3] = v4[1];
  priv[6] = *v10;
  priv[7] = v10[1];
  v5 = self->segmentBase - 0x40000000;
  *(_WORD *)(v3 + 2) = self->segmentBase;
  *(_BYTE *)(v3 + 4) = BYTE2(v5);
  *(_BYTE *)(v3 + 7) = HIBYTE(v5);
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
  v6 = gdt + 144;
  *(_WORD *)(gdt + 146) = 11848;
  *(_BYTE *)(v6 + 4) = 0;
  *(_BYTE *)(v6 + 7) = -64;
  *(_BYTE *)(v6 + 5) &= 0xE0u;
  *(_BYTE *)(v6 + 5) |= 0x1Au;
  *(_BYTE *)(v6 + 5) &= 0x9Fu;
  *(_BYTE *)(v6 + 5) = *(_BYTE *)(v6 + 5);
  *(_BYTE *)(v6 + 5) |= 0x80u;
  *(_BYTE *)(v6 + 6) |= 0x40u;
  *(_BYTE *)(v6 + 6) &= ~0x80u;
  *(_WORD *)v6 = -1;
  *(_BYTE *)(v6 + 6) &= 0xF0u;
  *(_BYTE *)(v6 + 6) = *(_BYTE *)(v6 + 6);
  v7 = gdt + 152;
  v8 = (void *)IOMalloc(a1: 2048);
  priv[8] = v8;
  bzero(a1: v8, a2: 0x800u);
  v9 = priv[8] - 0x40000000;
  *(_WORD *)(v7 + 2) = *((_WORD *)priv + 16);
  *(_BYTE *)(v7 + 4) = BYTE2(v9);
  *(_BYTE *)(v7 + 7) = HIBYTE(v9);
  *(_BYTE *)(v7 + 5) &= 0xE0u;
  *(_BYTE *)(v7 + 5) |= 0x12u;
  *(_BYTE *)(v7 + 5) &= 0x9Fu;
  *(_BYTE *)(v7 + 5) = *(_BYTE *)(v7 + 5);
  *(_BYTE *)(v7 + 5) |= 0x80u;
  *(_BYTE *)(v7 + 6) |= 0x40u;
  *(_BYTE *)(v7 + 6) &= ~0x80u;
  *(_WORD *)v7 = 2047;
  *(_BYTE *)(v7 + 6) &= 0xF0u;
  *(_BYTE *)(v7 + 6) = *(_BYTE *)(v7 + 6);
  *(_BYTE *)(v7 + 6) &= ~0x40u;
  ATI_Bios_StackOffset = 2048;
  ATI_Bios_StackSelector = 152;
}
```


## 0x2BA0 -[ATI_BIOS restoreCodeSegments]

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


## 0x2C08 -[ATI_BIOS createDataSegment:size:]

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


## 0x2CDC -[ATI_BIOS restoreDataSegment]

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


## 0x2D00 -[ATI_BIOS doBios:dataSeg:]

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


## 0x2D44 -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]

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
  char v10; // al
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


## 0x2EC0 _ATIbios16

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
