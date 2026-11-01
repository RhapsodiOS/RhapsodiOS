/* IDA 9.4 Hex-Rays pseudocode review export. Not a compilable source unit.
 * Inputs: reference SHA-256 AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C;
 * rebuilt SHA-256 C66D81FC1ACA66935D82069D5F91A61F917C9DF61B68CA835D05B93785222A92.
 * Original function addresses and names are retained below. */



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
