/* Hex-Rays 9.4 pseudocode. Input SHA-256: AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C; IDA database: C:\Users\raynorpat\Downloads\test\Drivers\i386\ATIMach64DisplayDriver.config\ATIMach64DisplayDriver_reloc */

/* -[ATI initFromDeviceDescription:] at 0x0 */
id __cdecl -[ATI initFromDeviceDescription:](ATI *self, SEL a2, id a3)
{
  const char *v4; // eax
  ATI_BIOS *v5; // eax
  ATI_BIOS *v6; // eax
  const char *v7; // eax
  const char *v8; // eax
  const char *v9; // eax
  const char *v10; // ebx
  const char *v11; // eax
  const char *v12; // eax
  const char *v13; // eax
  const char *v14; // ebx
  const char *v15; // eax
  const char *v16; // eax
  const char *v17; // ebx
  const char *v18; // eax
  const char *v19; // eax
  const char *v20; // ebx
  const char *v21; // eax
  const char *v22; // eax
  int v23; // ebx
  id v24; // eax
  const char *v25; // eax
  unsigned int v26; // edi
  unsigned int v27; // ebx
  unsigned int *v28; // eax
  unsigned int v29; // esi
  int fbMapStyle; // eax
  unsigned int v31; // eax
  id v32; // eax
  const char *v33; // eax
  const char *v34; // eax
  const char *v35; // eax
  const char *v36; // eax
  const char *v37; // eax
  const char *v38; // eax
  id v39; // eax
  const char *v40; // eax
  int i; // ebx
  const char *v42; // [esp-10h] [ebp-114h]
  const char *v43; // [esp-10h] [ebp-114h]
  const char *v44; // [esp-Ch] [ebp-110h]
  int v45; // [esp-Ch] [ebp-110h]
  id v46; // [esp-Ch] [ebp-110h]
  const char *v47; // [esp-Ch] [ebp-110h]
  id v48; // [esp-Ch] [ebp-110h]
  id v49; // [esp-Ch] [ebp-110h]
  id v50; // [esp-Ch] [ebp-110h]
  const char *v51; // [esp-4h] [ebp-108h]
  const char *v52; // [esp-4h] [ebp-108h]
  const char *v53; // [esp-4h] [ebp-108h]
  const char *v54; // [esp-4h] [ebp-108h]
  void *vram; // [esp-4h] [ebp-108h]
  char v56; // [esp+10h] [ebp-F4h]
  char v57; // [esp+14h] [ebp-F0h]
  char v58; // [esp+18h] [ebp-ECh]
  id v59; // [esp+1Ch] [ebp-E8h]
  unsigned __int8 *queryData; // [esp+20h] [ebp-E4h]
  int v61; // [esp+24h] [ebp-E0h] BYREF
  objc_super v62; // [esp+28h] [ebp-DCh] BYREF
  char __dst[32]; // [esp+30h] [ebp-D4h] BYREF
  char v64[180]; // [esp+50h] [ebp-B4h] BYREF

  v58 = 0;
  v57 = 0;
  v56 = 0;
  v62.receiver = self;
  v62.super_class = (Class)stru_818C.super_class;
  if ( -[ATI initFromDeviceDescription:](&v62, sel_initFromDeviceDescription_, a3) == nullptr )
  {
    v62.receiver = self;
    v62.super_class = (Class)stru_818C.super_class;
    return -[ATI free](&v62, sel_free);
  }
  if ( +[ATI_BIOS ATIPresent:](aAtiBios, sel_ATIPresent_, &v61) == 0 )
  {
    v4 = (const char *)-[ATI name](self, aName);
    IOLog("%s: ATI BIOS not found\n", v4);
    v62.receiver = self;
    v62.super_class = (Class)stru_818C.super_class;
    return -[ATI free](&v62, sel_free);
  }
  v5 = +[ATI_BIOS alloc](aAtiBios, aAlloc);
  v6 = -[ATI_BIOS init](v5, sel_init);
  self->atiBios = v6;
  if ( v6 == nullptr || (self->queryDataSize = 0, -[ATI getQueryData](self, sel_getQueryData) != 0) )
  {
    v62.receiver = self;
    v62.super_class = (Class)stru_818C.super_class;
    return -[ATI free](&v62, sel_free);
  }
  queryData = (unsigned __int8 *)self->queryData;
  self->supportsGamma = (queryData[20] & 0x40) != 0;
  self->supportsGrey256 = (queryData[20] & 0x20) != 0;
  v7 = (const char *)IOFindNameForValue(queryData[9], &ATI_AsicTypeValues);
  strcpy(__dst, v7);
  if ( queryData[9] == 0xD7 )
  {
    v8 = (const char *)IOFindNameForValue(queryData[8], &ATI_AsicSubTypeValues);
    strcat(__dst, v8);
  }
  v44 = (const char *)IOFindNameForValue(queryData[12], &ATI_dacTypeValues);
  v9 = (const char *)-[ATI name](self, aName);
  sprintf(v64, "%s: ATI Mach64 Found; Type %s; DAC = %s\n", v9, __dst, v44);
  IOLog(v64);
  v10 = "NO";
  if ( self->supportsGamma != 0 )
    v10 = "YES";
  v11 = "NO";
  if ( self->supportsGrey256 != 0 )
    v11 = "YES";
  v51 = v11;
  v45 = v61;
  v42 = (const char *)IOFindNameForValue(queryData[11], &ATI_memSizeValues);
  v12 = (const char *)-[ATI name](self, aName);
  sprintf(v64, "%s: memory=%s; BIOS@%x; Gamma=%s; 256-grey=%s\n", v12, v42, v45, v10, v51);
  IOLog(v64);
  -[ATI updateModeList](self, sel_updateModeList);
  v59 = objc_msgSend(a3, aConfigtable);
  self->colorConfig = 0;
  v13 = (const char *)objc_msgSend(v59, aValueforstring, "24-bit Configuration");
  v14 = v13;
  if ( v13 != nullptr )
  {
    if ( strcmp(v13, "RGBx") == 0 )
    {
      self->colorConfig = 1;
    }
    else if ( strcmp(v13, "BGRx") == 0 )
    {
      self->colorConfig = 2;
    }
    else if ( strcmp(v13, "xRGB") == 0 )
    {
      self->colorConfig = 3;
    }
    else if ( strcmp(v13, "xBGR") == 0 )
    {
      self->colorConfig = 4;
    }
    if ( self->colorConfig != 0 )
    {
      v52 = v13;
      v15 = (const char *)-[ATI name](self, aName);
      IOLog("%s: colorConfig from table = %s\n", v15, v52);
    }
    objc_msgSend(v59, aFreestring, v14);
  }
  self->fbMapStyle = 0;
  v16 = (const char *)objc_msgSend(v59, aValueforstring, "Frame Buffer Mapping");
  v17 = v16;
  if ( v16 != nullptr )
  {
    if ( strcmp(v16, "BIOS") == 0 )
    {
      self->fbMapStyle = 1;
    }
    else if ( strcmp(v16, "Table") == 0 )
    {
      self->fbMapStyle = 2;
    }
    if ( self->fbMapStyle != 0 )
    {
      v53 = v16;
      v18 = (const char *)-[ATI name](self, aName);
      IOLog("%s: fbMapStyle from table = %s\n", v18, v53);
    }
    objc_msgSend(v59, aFreestring, v17);
  }
  self->ramdacStyle = 0;
  v19 = (const char *)objc_msgSend(v59, aValueforstring, "RAMDAC Style");
  v20 = v19;
  if ( v19 != nullptr )
  {
    if ( strcmp(v19, "Sparse") == 0 )
    {
      self->ramdacStyle = 1;
    }
    else if ( strcmp(v19, "Dense") == 0 )
    {
      self->ramdacStyle = 2;
    }
    if ( self->ramdacStyle != 0 )
    {
      v54 = v19;
      v21 = (const char *)-[ATI name](self, aName);
      IOLog("%s: ramdacStyle from table = %s\n", v21, v54);
    }
    objc_msgSend(v59, aFreestring, v20);
  }
  self->isPCI = 0;
  v22 = (const char *)objc_msgSend(v59, aValueforstring, "Bus Type");
  HIWORD(v23) = HIWORD(v22);
  if ( v22 != nullptr )
  {
    if ( strcmp(v22, "PCI") == 0 )
      self->isPCI = 1;
    objc_msgSend(v59, aFreestring, v22);
  }
  v24 = objc_msgSend(v59, aValueforstring, "Display Mode");
  if ( v24 == nullptr )
  {
    v46 = -[ATI name](self, aName);
    IOLog("%s: No Display Mode found; aborting\n", v46);
    return -[ATI free](self, sel_free);
  }
  if ( -[ATI parseModeString:](self, sel_parseModeString_, v24) != 0 )
    return -[ATI free](self, sel_free);
  if ( dword_4294[34 * self->modeNumber] == 4 )
  {
    v47 = (const char *)IOFindNameForValue(self->colorConfig, &colorConfigValues);
    v25 = (const char *)-[ATI name](self, aName);
    IOLog("%s: 24 Bit Color Configuration = %s\n", v25, v47);
  }
  v26 = memSizeToBytes(queryData[11]);
  self->vramBytes = v26;
  LOWORD(v23) = *((_WORD *)queryData + 8);
  v27 = v23 << 20;
  v28 = (unsigned int *)objc_msgSend(a3, aMemoryrangelis);
  if ( v28 == nullptr )
  {
    v48 = -[ATI name](self, aName);
    IOLog("%s: No memory Range specified in config table; aborting\n", v48);
    return -[ATI free](self, sel_free);
  }
  v29 = *v28;
  fbMapStyle = self->fbMapStyle;
  if ( fbMapStyle == 1 )
  {
    v57 = 1;
    v29 = v27;
  }
  else if ( fbMapStyle == 2 )
  {
    v56 = 1;
    v27 = v29;
  }
  if ( (queryData[18] & 0x80u) != 0 && self->fbMapStyle == 0 )
  {
    v31 = 0x8000000 - v26;
    if ( v29 > 0x8000000 - v26 )
    {
      if ( v27 > v31 )
      {
        v56 = 1;
        v57 = 1;
        v29 = 125829120;
        v27 = 125829120;
      }
      else
      {
        v57 = 1;
      }
    }
    else if ( v27 > v31 )
    {
      v56 = 1;
      v27 = v29;
    }
  }
  while ( 1 )
  {
    if ( v29 == v27 && v57 == 0 )
      goto LABEL_75;
    v32 = -[ATI changeTableMapping:](self, sel_changeTableMapping_, v27);
    if ( v32 == nullptr )
    {
      v35 = (const char *)-[ATI name](self, aName);
      IOLog("%s: Changing Config Table Address to 0x%x\n", v35, v27);
      v29 = v27;
LABEL_75:
      if ( v56 == 0 )
        goto LABEL_82;
      goto LABEL_76;
    }
    if ( v57 != 0 )
    {
      if ( v27 == 125829120 )
      {
        v43 = (const char *)-[ATI stringFromReturn:](self, aStringfromretu, v32);
        v33 = (const char *)-[ATI name](self, aName);
        IOLog("%s: error setting memory map to 0x%x(%s); aborting\n", v33, 125829120, v43);
        return -[ATI free](self, sel_free);
      }
      v34 = (const char *)-[ATI name](self, aName);
      IOLog("%s: memory range @ 0x%x reserved; retrying at 0x%x\n", v34, v27, 125829120);
      v56 = 1;
      goto LABEL_81;
    }
    v56 = 1;
LABEL_76:
    if ( -[ATI changeHardwareMapping:](self, sel_changeHardwareMapping_, v29) == 0 )
      break;
    if ( v29 == 125829120 )
    {
      v37 = (const char *)-[ATI name](self, aName);
      IOLog("%s: Can't set memory aperture to 0x%x; aborting\n", v37, 125829120);
      return -[ATI free](self, sel_free);
    }
    v38 = (const char *)-[ATI name](self, aName);
    IOLog("%s: Can't set memory aperture to 0x%x; retrying at 0x%x\n", v38, v29, 125829120);
    v57 = 1;
LABEL_81:
    v29 = 125829120;
    v27 = 125829120;
  }
  v58 = 1;
  v27 = v29;
  v36 = (const char *)-[ATI name](self, aName);
  IOLog("%s: Changing aperture address to 0x%x\n", v36, v29);
LABEL_82:
  if ( v58 != 0 || objc_msgSend(self->atiBios, sel_setApertureEnable_VGAAperture_apertureAdrs_, 1, 0, 0) == nullptr )
  {
    v39 = -[ATI mapFrameBufferAtPhysicalAddress:length:](
            self,
            aMapframebuffer,
            v27,
            ~page_mask & (page_mask + self->vramBytes));
    self->vram = v39;
    if ( v39 == nullptr )
    {
      v49 = -[ATI name](self, aName);
      IOLog("%s: Unable to map frame buffer\n", v49);
      return -[ATI free](self, sel_free);
    }
    vram = self->vram;
    v40 = (const char *)-[ATI name](self, aName);
    IOLog("%s: frame buffer physical addrs 0x%x; mapped to 0x%x\n", v40, v27, vram);
    for ( i = 0; AtiModeListCount > i; ++i )
      *((_DWORD *)&AtiModeList + 34 * i + 5) = self->vram;
    v62.receiver = self;
    v62.super_class = (Class)stru_818C.super_class;
    qmemcpy(-[ATI displayInfo](&v62, aDisplayinfo), (char *)&AtiModeList + 136 * self->modeNumber, 0x88u);
    if ( -[ATI verifyMemoryMap](self, sel_verifyMemoryMap) != 0 )
    {
      self->currentState = 0;
      self->blueTransferTable = nullptr;
      self->greenTransferTable = nullptr;
      self->redTransferTable = nullptr;
      self->transferTableCount = 0;
      self->brightnessLevel = 64;
      return self;
    }
    v50 = -[ATI name](self, aName);
    IOLog("%s: VRAM test failure, aborting\n", v50);
  }
  return -[ATI free](self, sel_free);
}


/* -[ATI free] at 0xaa0 */
id __cdecl -[ATI free](ATI *self, SEL a2)
{
  objc_super v3; // [esp+4h] [ebp-8h] BYREF

  if ( self->queryDataSize != 0 )
    IOFree(self->queryData, self->queryDataSize);
  if ( self->atiBios != nullptr )
    objc_msgSend(self->atiBios, sel_free);
  if ( self->redTransferTable != nullptr )
    IOFree(self->redTransferTable, 3 * self->transferTableCount);
  v3.receiver = self;
  v3.super_class = (Class)stru_818C.super_class;
  return -[ATI free](&v3, sel_free);
}


/* -[ATI enterLinearMode] at 0xb30 */
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

  v2 = -[ATI displayInfo](self, aDisplayinfo);
  v9 = v2[25];
  if ( self->currentState != 1
    && objc_msgSend(self->atiBios, sel_setApertureEnable_VGAAperture_apertureAdrs_, 1, 0, 0) == nullptr )
  {
    v3 = displayInfoToColorDepth(v2);
    displayInfoToColorSpace(v2);
    if ( v3 == 2 )
      supportsGrey256 = self->supportsGrey256;
    else
      supportsGrey256 = self->supportsGamma;
    v5 = 2;
    if ( *v2 == 1024 )
      v5 = 0;
    v6 = objc_msgSend(
           self->atiBios,
           sel_loadCRTCSetMode_gamma_pitchSize_resolution_crtTable_,
           v3,
           supportsGrey256,
           v5,
           129,
           v9);
    if ( v6 != nullptr )
    {
      v8 = (const char *)IOFindNameForValue(v6, &ABReturnValues);
      v7 = (const char *)-[ATI name](self, aName);
      IOLog("%s: Error setting CRTC Paramters (%s)\n", v7, v8);
    }
    else
    {
      memset(self->vram, 0, self->vramBytes);
      self->currentState = 1;
      -[ATI setGammaTable](self, sel_setGammaTable);
    }
  }
}


/* -[ATI revertToVGAMode] at 0xc48 */
void __cdecl -[ATI revertToVGAMode](ATI *self, SEL a2)
{
  id v2; // eax
  const char *v3; // eax
  const char *v4; // [esp-4h] [ebp-8h]

  v2 = objc_msgSend(self->atiBios, sel_setVGAMode_gamma_, 1, 0);
  if ( v2 != nullptr )
  {
    v4 = (const char *)IOFindNameForValue(v2, &ABReturnValues);
    v3 = (const char *)-[ATI name](self, aName);
    IOLog("%s: Error setting VGA (%s)\n", v3, v4);
  }
  else
  {
    if ( self->redTransferTable != nullptr )
    {
      IOFree(self->redTransferTable, 3 * self->transferTableCount);
      self->redTransferTable = nullptr;
    }
    self->currentState = 2;
  }
}


/* -[ATI displayModeCount] at 0xcd4 */
unsigned int __cdecl -[ATI displayModeCount](ATI *self, SEL a2)
{
  return AtiModeListCount;
}


/* -[ATI displayModes] at 0xce0 */
$514E7C50D28E54AB164B6500F83867A3 *__cdecl -[ATI displayModes](ATI *self, SEL a2)
{
  return ($514E7C50D28E54AB164B6500F83867A3 *)&AtiModeList;
}


/* -[ATI displayMemorySize] at 0xcec */
unsigned int __cdecl -[ATI displayMemorySize](ATI *self, SEL a2)
{
  return memSizeToBytes(*((_BYTE *)self->queryData + 11));
}


/* -[ATI setPendingDisplayMode:] at 0xd08 */
char __cdecl -[ATI setPendingDisplayMode:](ATI *self, SEL a2, int a3)
{
  const char *v4; // eax
  objc_super v5; // [esp+8h] [ebp-8h] BYREF

  if ( AtiModeListCount <= a3 )
  {
    v4 = (const char *)-[ATI name](self, aName);
    IOLog("%s: setPendingDisplayMode: bogus displayMode (%d)\n", v4, a3);
  }
  else if ( -[ATI isModeValid:](self, sel_isModeValid_, a3) == 0 )
  {
    self->modeNumber = a3;
    v5.receiver = self;
    v5.super_class = (Class)stru_818C.super_class;
    return -[ATI setPendingDisplayMode:](&v5, sel_setPendingDisplayMode_, a3);
  }
  return 0;
}


/* -[ATI getQueryData] at 0xd84 */
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
    IOFree(self->queryData, self->queryDataSize);
    self->queryDataSize = 0;
  }
  v2 = objc_msgSend(self->atiBios, sel_querySize_size_, 0, &v12);
  if ( v2 != nullptr )
  {
    v11 = (const char *)IOFindNameForValue(v2, &ABReturnValues);
    v3 = (const char *)-[ATI name](self, aName);
    IOLog("%s: querySize returned %s\n", v3, v11);
  }
  else
  {
    v4 = (unsigned __int16 *)IOMalloc(v12);
    v5 = objc_msgSend(self->atiBios, sel_deviceQuery_bufferSize_buffer_, 0, v12, v4);
    if ( v5 == nullptr )
    {
      v6 = *v4;
      self->queryDataSize = v6;
      v7 = (void *)IOMalloc(v6);
      self->queryData = v7;
      bcopy(v4, v7, self->queryDataSize);
      IOFree(v4, v12);
      return 0;
    }
    v10 = (const char *)IOFindNameForValue(v5, &ABReturnValues);
    v9 = (const char *)-[ATI name](self, aName);
    IOLog("%s: deviceQuery returned %s\n", v9, v10);
    if ( v12 != 0 )
      IOFree(v4, v12);
  }
  return 1;
}


/* -[ATI parseModeString:] at 0xeb4 */
int __cdecl -[ATI parseModeString:](ATI *self, SEL a2, const char *a3)
{
  id v3; // eax
  const char *v4; // eax
  id v5; // eax
  const char *v7; // eax
  id v8; // [esp-4h] [ebp-8h]

  v3 = -[ATI selectMode:count:valid:](self, aSelectmodeCoun, &AtiModeList, AtiModeListCount, modeValidArray);
  self->modeNumber = (int)v3;
  if ( (int)v3 >= 0 )
  {
    v5 = -[ATI isModeValid:](self, sel_isModeValid_, self->modeNumber);
    if ( v5 == nullptr )
      return 0;
    v8 = v5;
    v7 = (const char *)-[ATI name](self, aName);
    IOLog("%s: Requested Mode not supported (0x%x); aborting\n", v7, v8);
  }
  else
  {
    v4 = (const char *)-[ATI name](self, aName);
    IOLog("%s: selectMode problem; aborting\n", v4);
  }
  return -1;
}


/* -[ATI updateModeList] at 0xf4c */
void __cdecl -[ATI updateModeList](ATI *self, SEL a2)
{
  _BYTE *queryData; // eax
  unsigned int colorConfig; // eax
  char *v4; // ebx
  int i; // esi
  char *__src; // [esp+Ch] [ebp-4h]

  queryData = self->queryData;
  modeValidArray = 0;
  if ( self->colorConfig == 0 )
  {
    if ( (queryData[19] & 0x20) != 0 )
    {
      self->colorConfig = 1;
    }
    else if ( (char)queryData[19] >= 0 )
    {
      if ( (queryData[19] & 0x40) != 0 )
      {
        self->colorConfig = 2;
      }
      else if ( (queryData[19] & 0x10) != 0 )
      {
        self->colorConfig = 4;
      }
      else
      {
        self->colorConfig = 5;
      }
    }
    else
    {
      self->colorConfig = 3;
    }
  }
  colorConfig = self->colorConfig;
  if ( colorConfig == 2 )
  {
    __src = "BBBBBBBBGGGGGGGGRRRRRRRR--------";
  }
  else
  {
    if ( colorConfig <= 2 )
    {
LABEL_15:
      __src = "RRRRRRRRGGGGGGGGBBBBBBBB--------";
      goto LABEL_19;
    }
    if ( colorConfig == 3 )
    {
      __src = "--------RRRRRRRRGGGGGGGGBBBBBBBB";
    }
    else
    {
      if ( colorConfig != 4 )
        goto LABEL_15;
      __src = "--------BBBBBBBBGGGGGGGGRRRRRRRR";
    }
  }
LABEL_19:
  v4 = (char *)&AtiModeList;
  for ( i = 0; AtiModeListCount > i; v4 += 136 )
  {
    if ( *((_DWORD *)v4 + 6) == 4 )
      strcpy(v4 + 32, __src);
    *((_DWORD *)v4 + 2) = *(_DWORD *)v4;
    *((_DWORD *)v4 + 3) = *((_DWORD *)v4 + 2) * (strlen(v4 + 32) >> 3);
    *((_DWORD *)v4 + 5) = self->vram;
    if ( displayInfoToColorSpace(v4) > 1u && self->supportsGamma != 0 || *((_DWORD *)v4 + 6) == 1 )
      *((_DWORD *)v4 + 24) = 16;
    else
      *((_DWORD *)v4 + 24) = 2;
    *((_DWORD *)v4 + 32) = -[ATI isModeValid:](self, sel_isModeValid_, i);
    *((_DWORD *)v4 + 26) = *((_DWORD *)v4 + 1) * *((_DWORD *)v4 + 3);
    ++i;
  }
}


/* -[ATI isModeValid:] at 0x10e8 */
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
  if ( v7 > memSizeToBytes(queryData[11]) )
    return 2;
  else
    return 0;
}


/* -[ATI verifyMemoryMap] at 0x1170 */
char __cdecl -[ATI verifyMemoryMap](ATI *self, SEL a2)
{
  void *vram; // ebx
  unsigned int i; // eax
  unsigned int j; // eax
  _BYTE v6[64]; // [esp+8h] [ebp-40h] BYREF

  vram = self->vram;
  bcopy(vram, v6, 0x40u);
  for ( i = 0; i <= 0xF; ++i )
    *((_DWORD *)vram + i) = i;
  for ( j = 0; j <= 0xF; ++j )
  {
    if ( *((_DWORD *)vram + j) != j )
      return 0;
  }
  bcopy(v6, self->vram, 0x40u);
  return 1;
}


/* -[ATI changeHardwareMapping:] at 0x11d4 */
int __cdecl -[ATI changeHardwareMapping:](ATI *self, SEL a2, unsigned int a3)
{
  id v3; // eax
  const char *v4; // eax
  id v5; // eax
  const char *v6; // eax
  void *queryData; // eax
  const char *v9; // [esp-10h] [ebp-1Ch]
  const char *v10; // [esp-10h] [ebp-1Ch]
  id v11; // [esp-Ch] [ebp-18h]
  id v12; // [esp-Ch] [ebp-18h]
  unsigned int v13; // [esp+8h] [ebp-4h] BYREF

  v13 = 0;
  if ( objc_msgSend(self->atiBios, sel_setApertureEnable_VGAAperture_apertureAdrs_, 1, 0, a3) != nullptr )
    return 1;
  if ( self->isPCI != 0 )
  {
    v13 = a3;
    v3 = -[ATI setPCIConfigData:atRegister:](self, aSetpciconfigda, a3, 16);
    if ( v3 != nullptr )
    {
      v9 = (const char *)-[ATI stringFromReturn:](self, aStringfromretu, v3);
      v4 = (const char *)-[ATI name](self, aName);
      IOLog("%s: error setting PCI config data (%s)\n", v4, v9);
      return 1;
    }
    v13 = 0;
    v5 = -[ATI getPCIConfigData:atRegister:](self, aGetpciconfigda, &v13, 16);
    if ( v5 != nullptr )
    {
      v10 = (const char *)-[ATI stringFromReturn:](self, aStringfromretu, v5);
      v6 = (const char *)-[ATI name](self, aName);
      IOLog("%s: error getting PCI config data (%s)\n", v6, v10);
      return 1;
    }
    if ( v13 != a3 )
    {
      v11 = -[ATI name](self, aName);
      IOLog("%s: Set Aperture Addrs to 0x%x;  PCI Config Register reported 0x%x\n", v11);
      return 1;
    }
  }
  if ( -[ATI getQueryData](self, sel_getQueryData) == 0 )
  {
    queryData = self->queryData;
    LOWORD(queryData) = *((_WORD *)queryData + 8);
    v13 = (_DWORD)queryData << 20;
    if ( (_DWORD)queryData << 20 == a3 )
      return 0;
    v12 = -[ATI name](self, aName);
    IOLog("%s: Set Aperture Addrs to 0x%x;  BIOS reported 0x%x\n", v12);
  }
  return 1;
}


/* -[ATI changeTableMapping:] at 0x1334 */
int __cdecl -[ATI changeTableMapping:](ATI *self, SEL a2, unsigned int a3)
{
  id v3; // edi
  int *v4; // esi
  const char *v5; // eax
  id v7; // eax
  const char *v8; // eax
  unsigned int i; // eax
  int v10; // ecx
  id v11; // eax
  const char *v12; // eax
  const char *v13; // [esp-8h] [ebp-34h]
  id v14; // [esp-4h] [ebp-30h]
  int v15; // [esp+Ch] [ebp-20h]
  id v16; // [esp+10h] [ebp-1Ch]
  _DWORD v17[6]; // [esp+14h] [ebp-18h] BYREF

  v3 = -[ATI deviceDescription](self, aDevicedescript);
  v4 = (int *)objc_msgSend(v3, aMemoryrangelis);
  if ( v4 != nullptr )
  {
    v7 = objc_msgSend(v3, aNummemoryrange);
    if ( v7 == &loc_3 )
    {
      v15 = *v4;
      for ( i = 0; i < 3; ++i )
      {
        v10 = v4[2 * i + 1];
        v17[2 * i] = v4[2 * i];
        v17[2 * i + 1] = v10;
      }
      v17[0] = a3;
      objc_msgSend(v3, aSetmemoryrange, v17, 0);
      v16 = objc_msgSend(v3, aSetmemoryrange, v17, 3);
      if ( v16 != nullptr )
      {
        v17[0] = v15;
        objc_msgSend(v3, aSetmemoryrange, v17, 0);
        v11 = objc_msgSend(v3, aSetmemoryrange, v17, 3);
        if ( v11 != nullptr )
        {
          v13 = (const char *)-[ATI stringFromReturn:](self, aStringfromretu, v11);
          v12 = (const char *)-[ATI name](self, aName);
          IOLog("%s: WARNING: Error (%s) restoringMemory Range to 0x%x\n", v12, v13, v15);
        }
      }
      return (int)v16;
    }
    else
    {
      v14 = v7;
      v8 = (const char *)-[ATI name](self, aName);
      IOLog("%s: Incorrect number of Memory Ranges (%d, should be 3)\n", v8, v14);
      return -701;
    }
  }
  else
  {
    v5 = (const char *)-[ATI name](self, aName);
    IOLog("%s: No memory Range specified in config table\n", v5);
    return -701;
  }
}


/* _isATI68880RevC at 0x1490 */
_BOOL4 isATI68880RevC()
{
  unsigned __int8 v0; // al
  unsigned __int8 v1; // al

  v0 = __inbyte(0x62ECu);
  __outbyte(0x62ECu, v0 | 3);
  _InterlockedIncrement(&xxx_8);
  v1 = __inbyte(0x5EEFu);
  return v1 == 0xD0;
}


/* _SetGammaValue at 0x14c0 */
unsigned int __cdecl SetGammaValue(int a1, int a2, int a3, int a4)
{
  unsigned int result; // eax

  __outbyte(0x5EEDu, (unsigned int)(a4 * a1) >> 6);
  _InterlockedIncrement(&xxx_8);
  __outbyte(0x5EEDu, (unsigned int)(a4 * a2) >> 6);
  _InterlockedIncrement(&xxx_8);
  result = (unsigned int)(a4 * a3) >> 6;
  __outbyte(0x5EEDu, result);
  _InterlockedIncrement(&xxx_8);
  return result;
}


/* -[ATI setGammaTable] at 0x1514 */
id __cdecl -[ATI setGammaTable](ATI *self, SEL a2)
{
  unsigned __int8 v2; // al
  unsigned int i; // esi
  unsigned int j; // ebx
  unsigned int v5; // ecx
  unsigned int k; // ebx
  unsigned int m; // esi
  unsigned int n; // ebx

  v2 = __inbyte(0x62ECu);
  __outbyte(0x62ECu, v2 & 0xFC);
  _InterlockedIncrement(&xxx_8);
  __outbyte(0x5EECu, 0);
  _InterlockedIncrement(&xxx_8);
  if ( self->redTransferTable != nullptr )
  {
    for ( i = 0; self->transferTableCount > i; ++i )
    {
      for ( j = 0; j < 256 / self->transferTableCount; ++j )
        SetGammaValue(
          (unsigned __int8)self->redTransferTable[i],
          (unsigned __int8)self->greenTransferTable[i],
          (unsigned __int8)self->blueTransferTable[i],
          self->brightnessLevel);
    }
  }
  else
  {
    v5 = *((_DWORD *)-[ATI displayInfo](self, aDisplayinfo) + 6);
    if ( v5 == 1 )
    {
      for ( k = 0; k <= 0xFF; ++k )
        SetGammaValue(
          (unsigned __int8)gamma8[k],
          (unsigned __int8)gamma8[k],
          (unsigned __int8)gamma8[k],
          self->brightnessLevel);
    }
    else if ( v5 != 0 && v5 <= 4 && v5 >= 3 )
    {
      for ( m = 0; m <= 0x1F; ++m )
      {
        for ( n = 0; n <= 7; ++n )
          SetGammaValue(
            (unsigned __int8)gamma16[m >> 1],
            (unsigned __int8)gamma16[m >> 1],
            (unsigned __int8)gamma16[m >> 1],
            self->brightnessLevel);
      }
    }
  }
  return self;
}


/* -[ATI setBrightness:token:] at 0x1648 */
id __cdecl -[ATI setBrightness:token:](ATI *self, SEL a2, int a3, int a4)
{
  if ( (unsigned int)a3 > 0x40 )
  {
    IOLog("Display: Invalid arg to setBrightness: %d\n", a3);
    return nullptr;
  }
  else
  {
    self->brightnessLevel = a3;
    -[ATI setGammaTable](self, sel_setGammaTable);
    return self;
  }
}


/* -[ATI setTransferTable:count:] at 0x1684 */
id __cdecl -[ATI setTransferTable:count:](ATI *self, SEL a2, const unsigned int *a3, int a4)
{
  _BYTE *queryData; // eax
  char v5; // dl
  char v6; // bl
  int ramdacStyle; // eax
  char *v8; // eax
  int v9; // ebx
  int v10; // eax
  int i; // esi
  char *redTransferTable; // ebx
  int v13; // eax
  int j; // esi
  char *greenTransferTable; // [esp+Ch] [ebp-Ch]
  unsigned __int8 v17; // [esp+10h] [ebp-8h]
  char v18; // [esp+14h] [ebp-4h]

  queryData = self->queryData;
  v5 = queryData[9];
  v17 = queryData[12];
  v6 = 2;
  if ( self->supportsGrey256 != 0 )
    v6 = 0;
  if ( v5 != 67 && v5 != 69 )
  {
    if ( v17 == 5 )
      goto LABEL_11;
    if ( v17 <= 5u )
    {
      if ( v17 != 2 )
        goto LABEL_12;
LABEL_11:
      v6 = 0;
      goto LABEL_12;
    }
    if ( v17 == 21 && isATI68880RevC() )
      goto LABEL_11;
  }
LABEL_12:
  v18 = v6;
  ramdacStyle = self->ramdacStyle;
  if ( ramdacStyle == 1 )
  {
    v18 = 0;
  }
  else if ( ramdacStyle == 2 )
  {
    v18 = 2;
  }
  if ( self->redTransferTable != nullptr )
    IOFree(self->redTransferTable, 3 * self->transferTableCount);
  self->transferTableCount = a4;
  v8 = (char *)IOMalloc(3 * a4);
  self->redTransferTable = v8;
  self->greenTransferTable = &v8[a4];
  self->blueTransferTable = &self->greenTransferTable[a4];
  v9 = *((_DWORD *)-[ATI displayInfo](self, aDisplayinfo) + 6);
  v10 = *((_DWORD *)-[ATI displayInfo](self, aDisplayinfo) + 7);
  if ( v9 == 1 && v10 == 1 )
  {
    for ( i = 0; a4 > i; ++i )
    {
      redTransferTable = self->redTransferTable;
      greenTransferTable = self->greenTransferTable;
      v13 = LOBYTE(a3[i]) >> v18;
      self->blueTransferTable[i] = v13;
      greenTransferTable[i] = v13;
      redTransferTable[i] = v13;
    }
  }
  else if ( v10 == 2 && (v9 == 1 || (unsigned int)(v9 - 3) <= 1) )
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
    IOFree(self->redTransferTable, 3 * a4);
    self->redTransferTable = nullptr;
  }
  -[ATI setGammaTable](self, sel_setGammaTable);
  return self;
}


/* _displayInfoToColorSpace at 0x1870 */
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
      IOLog("ATIMach64: displayInfoToColorSpace problem (%d)\n", *(_DWORD *)(a1 + 24));
      IOPanic("ATIMach64 displayInfoToColorSpace");
      return v1;
    }
    return *(_DWORD *)(a1 + 28) != 1;
  }
}


/* _colorDepthToColorSpace at 0x18d8 */
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


/* _displayInfoToColorDepth at 0x1928 */
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
      IOPanic("ATIMach64: displayInfoToColorDepth problem");
      return v1;
    }
    return 2;
  }
}


/* _memSizeToBytes at 0x1978 */
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
    default:
      result = 0x200000;
      break;
  }
  return result;
}


/* +[ATIMach64DisplayDriverKernelServerInstance kernelServerInstance] at 0x19ec */
$8EF4127CF77ECA3DDB612FCF233DC3A8 **__cdecl +[ATIMach64DisplayDriverKernelServerInstance kernelServerInstance](
        id a1,
        SEL a2)
{
  return ($8EF4127CF77ECA3DDB612FCF233DC3A8 **)&ATIMach64DisplayDriver_instance;
}


/* +[ATIMach64DisplayDriverVersion driverKitVersionForATIMach64DisplayDriver] at 0x19f8 */
int __cdecl +[ATIMach64DisplayDriverVersion driverKitVersionForATIMach64DisplayDriver](id a1, SEL a2)
{
  return 500;
}


/* +[ATI_BIOS ATIPresent:] at 0x1a04 */
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
      if ( strncmp(v5, (const char *)(*a3 + i), 9u) == 0 )
        return 1;
    }
    *a3 += 4096;
  }
  while ( *a3 <= 0xEFFFF );
  return 0;
}


/* -[ATI_BIOS init] at 0x1aa0 */
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
      if ( strncmp(v5, (const char *)(j + i), 9u) == 0 )
        return (ATI_BIOS *)-[ATI_BIOS initAtSegmentAddress:](self, sel_initAtSegmentAddress_, i);
    }
  }
  return nullptr;
}


/* -[ATI_BIOS initAtSegmentAddress:] at 0x1b44 */
id __cdecl -[ATI_BIOS initAtSegmentAddress:](ATI_BIOS *self, SEL a2, unsigned int a3)
{
  objc_super v4; // [esp+4h] [ebp-8h] BYREF

  self->segmentBase = a3;
  self->_priv = (void *)IOMalloc(36);
  self->initialized = 1;
  v4.receiver = self;
  v4.super_class = (Class)stru_81DC.ext;
  return -[ATI_BIOS init](&v4, sel_init);
}


/* -[ATI_BIOS free] at 0x1b88 */
id __cdecl -[ATI_BIOS free](ATI_BIOS *self, SEL a2)
{
  objc_super v3; // [esp+4h] [ebp-8h] BYREF

  if ( self->initialized != 0 )
    IOFree(self->_priv, 36);
  v3.receiver = self;
  v3.super_class = (Class)stru_81DC.ext;
  return -[ATI_BIOS free](&v3, sel_free);
}


/* -[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:] at 0x1bcc */
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
           self,
           sel_loadCRTC_comm_gamma_pitchSize_resolution_crtTable_function_name_,
           a3,
           a4,
           a5,
           a6,
           a7,
           0,
           "loadCRTC");
}


/* -[ATI_BIOS setVGAMode:gamma:] at 0x1c00 */
int __cdecl -[ATI_BIOS setVGAMode:gamma:](ATI_BIOS *self, SEL a2, char a3, char a4)
{
  char v5; // al
  id v6; // eax
  _BYTE v7[48]; // [esp+10h] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v7, 1);
  v5 = 0;
  if ( a4 != 0 )
    v5 = 0x80;
  v7[12] = v5 | (a3 == 0);
  v6 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v7, 0);
  if ( v6 != nullptr )
  {
    IOLog("ATI_BIOS setDisplayMode: ATIbios32() returned %d\n", v6);
  }
  else
  {
    if ( v7[5] == 0 )
      return 0;
    IOLog("ATI_BIOS setDisplayMode: ah = 0x%x on return from ATIbios32()\n", v7[5]);
  }
  return 2;
}


/* -[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:] at 0x1c9c */
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
           self,
           sel_loadCRTC_comm_gamma_pitchSize_resolution_crtTable_function_name_,
           a3,
           a4,
           a5,
           a6,
           a7,
           2,
           "loadCRTCSetMode");
}


/* -[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:] at 0x1cd0 */
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
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v7, 5);
  v8 = a3 != 0;
  if ( a4 != 0 )
    v8 |= 4u;
  if ( a5 != 0 )
  {
    if ( (a5 & 0xFFFFF) != 0 )
    {
      IOLog("ATI BIOS setApertureEnable: apertureAdrs misalignment (0x%x)\n", a5);
      return 3;
    }
    v8 |= 0x80u;
    v7[4] = a5 >> 20;
  }
  v6 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v7, 0);
  if ( v6 != nullptr )
  {
    IOLog("ATI_BIOS setApertureEnable: ATIbios32() returned %d\n", v6);
  }
  else
  {
    if ( HIBYTE(v7[2]) == 0 )
      return 0;
    IOLog("ATI_BIOS setApertureEnable: ah = 0x%x on return from ATIbios32()\n", HIBYTE(v7[2]));
  }
  return 2;
}


/* -[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:] at 0x1da0 */
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
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v12, 6);
  v11 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v12, 0);
  if ( v11 != nullptr )
  {
    IOLog("ATI_BIOS shortQuery: ATIbios32() returned %d\n", v11);
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
    IOLog("ATI_BIOS shortQuery: ah = 0x%x on return from ATIbios32()\n", HIBYTE(v12[2]));
  }
  return 2;
}


/* -[ATI_BIOS querySize:size:] at 0x1e6c */
int __cdecl -[ATI_BIOS querySize:size:](ATI_BIOS *self, SEL a2, char a3, unsigned int *a4)
{
  *a4 = 4096;
  return 0;
}


/* -[ATI_BIOS deviceQuery:bufferSize:buffer:] at 0x1e80 */
int __cdecl -[ATI_BIOS deviceQuery:bufferSize:buffer:](ATI_BIOS *self, SEL a2, char a3, unsigned int a4, void *a5)
{
  int result; // eax
  id v6; // eax
  _WORD v7[6]; // [esp+10h] [ebp-30h] BYREF
  bool v8; // [esp+1Ch] [ebp-24h]
  __int16 v9; // [esp+20h] [ebp-20h]

  if ( self->initialized == 0 )
    return 1;
  bzero(a5, a4);
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v7, 9);
  v8 = a3 == 0;
  result = -[ATI_BIOS createDataSegment:size:](self, sel_createDataSegment_size_, a5, a4);
  if ( result == 0 )
  {
    v9 = 136;
    v7[4] = 0;
    v6 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v7, 1);
    if ( v6 != nullptr )
    {
      IOLog("ATI_BIOS deviceQuery: ATIbios32() returned %d\n", v6);
    }
    else
    {
      if ( HIBYTE(v7[2]) == 0 )
        return 0;
      IOLog("ATI_BIOS deviceQuery: ah = 0x%x on return from ATIbios32()\n", HIBYTE(v7[2]));
    }
    return 2;
  }
  return result;
}


/* -[ATI_BIOS setDPMSMode:] at 0x1f40 */
int __cdecl -[ATI_BIOS setDPMSMode:](ATI_BIOS *self, SEL a2, unsigned int a3)
{
  id v4; // eax
  _BYTE v5[48]; // [esp+Ch] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  if ( a3 <= 4 )
  {
    -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v5, 12);
    v5[12] = a3 & 3;
    v4 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v5, 0);
    if ( v4 != nullptr )
    {
      IOLog("ATI_BIOS Set DPMS Mode: ATIbios32() returned %d\n", v4);
      return 2;
    }
    else
    {
      return 0;
    }
  }
  else
  {
    IOLog("ATI_BIOS set DPMS mode: %x not valid mode\n", a3);
    return 3;
  }
}


/* -[ATI_BIOS getDPMSMode:] at 0x1fc8 */
int __cdecl -[ATI_BIOS getDPMSMode:](ATI_BIOS *self, SEL a2, unsigned int *a3)
{
  id v4; // eax
  _BYTE v5[12]; // [esp+Ch] [ebp-30h] BYREF
  char v6; // [esp+18h] [ebp-24h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v5, 13);
  v6 = 0;
  v4 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v5, 0);
  if ( v4 != nullptr )
  {
    IOLog("ATI_BIOS Get DPMS Mode: ATIbios32() returned %d\n", v4);
    return 2;
  }
  else
  {
    *a3 = v6 & 3;
    return 0;
  }
}


/* -[ATI_BIOS setAPMState:] at 0x203c */
int __cdecl -[ATI_BIOS setAPMState:](ATI_BIOS *self, SEL a2, unsigned int a3)
{
  id v4; // eax
  _BYTE v5[48]; // [esp+Ch] [ebp-30h] BYREF

  if ( self->initialized == 0 )
    return 1;
  if ( a3 <= 3 )
  {
    -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v5, 14);
    v5[12] = a3 & 3;
    v4 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v5, 0);
    if ( v4 != nullptr )
    {
      IOLog("ATI_BIOS Set APM State: ATIbios32() returned %d\n", v4);
      return 2;
    }
    else
    {
      return 0;
    }
  }
  else
  {
    IOLog("ATI_BIOS set APM state: %x not valid mode\n", a3);
    return 3;
  }
}


/* -[ATI_BIOS getAPMState:] at 0x20c4 */
int __cdecl -[ATI_BIOS getAPMState:](ATI_BIOS *self, SEL a2, unsigned int *a3)
{
  id v4; // eax
  _BYTE v5[12]; // [esp+Ch] [ebp-30h] BYREF
  char v6; // [esp+18h] [ebp-24h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v5, 15);
  v6 = 0;
  v4 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v5, 0);
  if ( v4 != nullptr )
  {
    IOLog("ATI_BIOS Get APM State: ATIbios32() returned %d\n", v4);
    return 2;
  }
  else
  {
    *a3 = v6 & 3;
    return 0;
  }
}


/* -[ATI_BIOS getIOBaseAddress:relocatable:] at 0x2138 */
int __cdecl -[ATI_BIOS getIOBaseAddress:relocatable:](ATI_BIOS *self, SEL a2, unsigned int *a3, char *a4)
{
  id v5; // eax
  _BYTE v6[12]; // [esp+Ch] [ebp-30h] BYREF
  char v7; // [esp+18h] [ebp-24h]
  unsigned int v8; // [esp+1Ch] [ebp-20h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v6, 18);
  v7 = 0;
  v5 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v6, 0);
  if ( v5 != nullptr )
  {
    IOLog("ATI_BIOS Short Query 2: ATIbios32() returned %d\n", v5);
    return 2;
  }
  else
  {
    *a4 = v7 & 1;
    *a3 = v8;
    return 0;
  }
}


/* -[ATI_BIOS getRefreshRate:] at 0x21b4 */
int __cdecl -[ATI_BIOS getRefreshRate:](ATI_BIOS *self, SEL a2, char *a3)
{
  int result; // eax
  id v4; // eax
  _BYTE v5[8]; // [esp+8h] [ebp-30h] BYREF
  __int16 v6; // [esp+10h] [ebp-28h]
  __int16 v7; // [esp+18h] [ebp-20h]

  if ( self->initialized == 0 )
    return 1;
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v5, 21);
  LOBYTE(v6) = 0;
  result = -[ATI_BIOS createDataSegment:size:](self, sel_createDataSegment_size_, a3, 20);
  if ( result == 0 )
  {
    v7 = 136;
    v6 = 0;
    v4 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v5, 1);
    if ( v4 != nullptr )
    {
      IOLog("ATI_BIOS getRefreshRate: ATIbios32() returned %d\n", v4);
    }
    else
    {
      if ( v5[5] == 0 )
        return 0;
      IOLog("ATI_BIOS getRefreshRate: ah = 0x%x on return from ATIbios32()\n", v5[5]);
    }
    return 2;
  }
  return result;
}


/* -[ATI_BIOS changeRefreshRate:] at 0x2258 */
int __cdecl -[ATI_BIOS changeRefreshRate:](ATI_BIOS *self, SEL a2, char *a3)
{
  return 3;
}


/* -[ATI_BIOS initBIOSBuf:function:] at 0x2264 */
int __cdecl -[ATI_BIOS initBIOSBuf:function:](id a1, int a2, void *a3, char a4)
{
  int result; // eax

  objc_msgSend(a1, sel_setupCodeSegments);
  bzero(a3, 0x30u);
  *((_BYTE *)a3 + 4) = a4;
  *((_WORD *)a3 + 16) = 128;
  *((_WORD *)a3 + 17) = 16;
  *((_DWORD *)a3 + 11) = 100;
  result = (unsigned __int16)ATI_Bios_StackOffset >> 1;
  *((_DWORD *)a3 + 7) = result;
  return result;
}


/* -[ATI_BIOS setupCodeSegments] at 0x22b4 */
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
  *(_WORD *)(gdt + 146) = 9952;
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
  v8 = (void *)IOMalloc(2048);
  priv[8] = v8;
  bzero(v8, 0x800u);
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


/* -[ATI_BIOS restoreCodeSegments] at 0x2438 */
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
  IOFree(priv[8], 2048);
}


/* -[ATI_BIOS createDataSegment:size:] at 0x24a0 */
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
    IOLog("ATI_BIOS: Data Segment size exceeded (0x%x)\n", a4);
    return 3;
  }
}


/* -[ATI_BIOS restoreDataSegment] at 0x2574 */
void __cdecl -[ATI_BIOS restoreDataSegment](ATI_BIOS *self, SEL a2)
{
  int v2; // edx
  _DWORD *priv; // eax

  v2 = gdt + 136;
  priv = self->_priv;
  *(_DWORD *)(gdt + 136) = priv[4];
  *(_DWORD *)(v2 + 4) = priv[5];
}


/* -[ATI_BIOS doBios:dataSeg:] at 0x2598 */
int __cdecl -[ATI_BIOS doBios:dataSeg:](id a1, int a2, int a3, char a4)
{
  int v4; // esi

  v4 = ATIbios16(a3);
  objc_msgSend(a1, sel_restoreCodeSegments);
  if ( a4 != 0 )
    objc_msgSend(a1, sel_restoreDataSegment);
  return v4;
}


/* -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:] at 0x25dc */
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
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v13, a8);
  v10 = 0;
  if ( a4 != 0 )
    v10 = 16;
  v14 = ((_BYTE)a5 << 6) | a3 | v10;
  v15 = a6;
  if ( a6 == 129 )
  {
    result = -[ATI_BIOS createDataSegment:size:](self, sel_createDataSegment_size_, a7, 30);
    if ( result != 0 )
      return result;
    v16 = 136;
    v13[4] = 0;
    v12 = 1;
  }
  v11 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v13, v12);
  if ( v11 != nullptr )
  {
    IOLog("ATI_BIOS %s: ATIbios32() returned %d\n", a9, v11);
  }
  else
  {
    if ( HIBYTE(v13[2]) == 0 )
      return 0;
    IOLog("ATI_BIOS %s: ah = 0x%x on return from ATIbios32()\n", a9, HIBYTE(v13[2]));
  }
  return 2;
}


/* __bios16 at 0x26e0 */
// write access to const memory has been detected, the output may be wrong!
// positive sp value has been detected, the output may be wrong!
id __usercall _bios16@<eax>(int a1@<eax>, ATI *a2, const char *a3, void *a4)
{
  int v5; // [esp-4h] [ebp-4h] BYREF

  bios16_saved_eax = a1;
  *(_DWORD *)((char *)&loc_273D + 1) = ATI_Bios_Offset;
  *(_WORD *)((char *)&loc_273D + 5) = ATI_Bios_Selector;
  bios16_saved_esp = (int)&v5;
  bios16_saved_ss = __SS__;
  return -[ATI initFromDeviceDescription:](a2, a3, a4);
}


/* _ATIbios16 at 0x2758 */
int __cdecl ATIbios16(int a1)
{
  kernDataSel = 16;
  if ( *(_DWORD *)(a1 + 44) > 0xFFFFu )
  {
    IOLog("ATIbios16: invalid offset (0x%x)\n", *(_DWORD *)(a1 + 44));
    return -1;
  }
  else
  {
    ATI_Bios_Offset = *(unsigned __int16 *)(a1 + 44);
    ATI_Bios_Selector = *(_WORD *)(a1 + 32);
    *(_WORD *)(a1 + 32) = 144;
    *(_DWORD *)(a1 + 44) = 0;
    _ATIbios32(a1);
    return 0;
  }
}


/* __ATIbios32 at 0x27b8 */
// write access to const memory has been detected, the output may be wrong!
void __usercall __spoils<ecx> _ATIbios32(int a1@<ebp>)
{
  ATI *v1; // kr00_4
  int v2; // edx
  int v3; // ebx
  int v4; // edi
  int v5; // esi
  int v6; // ebp
  id v7; // eax
  __int16 v8; // kr04_2
  int v9; // edx
  int v10; // edx
  int v11; // ecx
  unsigned int v12; // [esp-30h] [ebp-30h]

  v1 = (ATI *)__readeflags();
  v2 = *(_DWORD *)(a1 + 8);
  *(_WORD *)((char *)&loc_2811 + 5) = *(_WORD *)(v2 + 32);
  *(_DWORD *)((char *)&loc_2811 + 1) = *(_DWORD *)(v2 + 44);
  v3 = *(_DWORD *)(v2 + 8);
  v4 = *(_DWORD *)(v2 + 20);
  v5 = *(_DWORD *)(v2 + 24);
  v6 = *(_DWORD *)(v2 + 28);
  bios32_saved_buffer = v2;
  bios32_saved_eax = *(_DWORD *)(v2 + 4);
  bios32_saved_edx = *(_DWORD *)(v2 + 16);
  _disable();
  v7 = -[ATI initFromDeviceDescription:](v1, (SEL)(unsigned __int16)__GS__, (id)(unsigned __int16)__FS__);
  v8 = __readeflags();
  __DS__ = kernDataSel;
  bios32_result_eax = (int)v7;
  bios32_result_flags = v8;
  bios32_result_es = __ES__;
  bios32_saved_edx = v9;
  v10 = bios32_saved_buffer;
  *MK_FP(kernDataSel, bios32_saved_buffer + 16) = bios32_saved_edx;
  *(_DWORD *)(v10 + 4) = bios32_result_eax;
  *(_WORD *)(v10 + 36) = bios32_result_es;
  *(_WORD *)(v10 + 40) = bios32_result_flags;
  *(_DWORD *)(v10 + 8) = v3;
  *(_DWORD *)(v10 + 12) = v11;
  *(_DWORD *)(v10 + 20) = v4;
  *(_DWORD *)(v10 + 24) = v5;
  *(_DWORD *)(v10 + 28) = v6;
  __writeeflags(v12);
}
