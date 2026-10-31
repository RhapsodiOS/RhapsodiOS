/* IDA 9.4 Hex-Rays pseudocode review export. Not a compilable source unit.
 * Inputs: reference SHA-256 AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C;
 * rebuilt SHA-256 C66D81FC1ACA66935D82069D5F91A61F917C9DF61B68CA835D05B93785222A92.
 * Original function addresses and names are retained below. */



/* _isATI68880RevC at 0x14dc */
_BOOL4 isATI68880RevC()
{
  unsigned __int8 v0; // al
  unsigned __int8 v1; // al

  v0 = __inbyte(0x62ECu);
  __outbyte(0x62ECu, v0 | 3);
  _InterlockedIncrement(&xxx_86);
  v1 = __inbyte(0x5EEFu);
  return v1 == 0xD0;
}


/* _SetGammaValue at 0x1504 */
unsigned int __cdecl SetGammaValue(int a1, int a2, int a3, int a4)
{
  __outbyte(0x5EEDu, (unsigned int)(a1 * a4) >> 6);
  _InterlockedIncrement(&xxx_86);
  __outbyte(0x5EEDu, (unsigned int)(a4 * a2) >> 6);
  _InterlockedIncrement(&xxx_86);
  __outbyte(0x5EEDu, (unsigned int)(a3 * a4) >> 6);
  _InterlockedIncrement(&xxx_86);
  return (unsigned int)(a3 * a4) >> 6;
}


/* -[ATI setGammaTable] at 0x1554 */
id __cdecl -[ATI setGammaTable](ATI *self, SEL a2)
{
  unsigned __int8 v2; // al
  unsigned int i; // ebx
  unsigned int j; // esi
  int v5; // ecx
  unsigned int k; // ebx
  unsigned int m; // ebx
  unsigned int n; // esi

  v2 = __inbyte(0x62ECu);
  __outbyte(0x62ECu, v2 & 0xFC);
  _InterlockedIncrement(&xxx_86);
  __outbyte(0x5EECu, 0);
  _InterlockedIncrement(&xxx_86);
  if ( self->redTransferTable != nullptr )
  {
    for ( i = 0; self->transferTableCount > i; ++i )
    {
      for ( j = 0; j < 256 / self->transferTableCount; ++j )
        SetGammaValue(
          *((unsigned __int8 *)self->redTransferTable + i),
          *((unsigned __int8 *)self->greenTransferTable + i),
          *((unsigned __int8 *)self->blueTransferTable + i),
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
    else if ( (unsigned int)(v5 - 3) <= 1 )
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


/* -[ATI setTransferTable:count:] at 0x16bc */
id __cdecl -[ATI setTransferTable:count:](ATI *self, SEL a2, const unsigned int *a3, int a4)
{
  char *queryData; // eax
  char v5; // dl
  char v6; // al
  char v7; // di
  unsigned int *v8; // eax
  int v9; // ebx
  int v10; // eax
  int i; // ebx
  int v12; // edx
  int j; // ebx
  unsigned __int8 *v15; // [esp+Ch] [ebp-4h]

  queryData = self->queryData;
  v5 = queryData[9];
  v6 = queryData[12];
  v7 = 0;
  if ( self->supportsGrey256 == 0 )
    v7 = 2;
  if ( v5 != 67 && v5 != 69 && (v6 == 5 || v6 == 2 || v6 == 21 && isATI68880RevC()) )
    v7 = 0;
  if ( self->ramdacStyle == 1 )
  {
    v7 = 0;
  }
  else if ( self->ramdacStyle == 2 )
  {
    v7 = 2;
  }
  if ( self->redTransferTable != nullptr )
    IOFree(self->redTransferTable, 3 * self->transferTableCount);
  self->transferTableCount = a4;
  v8 = (unsigned int *)IOMalloc(3 * a4);
  self->redTransferTable = v8;
  self->greenTransferTable = (unsigned int *)((char *)v8 + a4);
  self->blueTransferTable = (unsigned int *)((char *)self->greenTransferTable + a4);
  v9 = *((_DWORD *)-[ATI displayInfo](self, aDisplayinfo) + 6);
  v10 = *((_DWORD *)-[ATI displayInfo](self, aDisplayinfo) + 7);
  if ( v9 == 1 && v10 == 1 )
  {
    for ( i = 0; a4 > i; ++i )
    {
      v12 = (int)LOBYTE(a3[i]) >> v7;
      *((_BYTE *)self->redTransferTable + i) = v12;
      *((_BYTE *)self->greenTransferTable + i) = v12;
      *((_BYTE *)self->blueTransferTable + i) = v12;
    }
  }
  else if ( v10 == 2 && (v9 == 1 || (unsigned int)(v9 - 3) <= 1) )
  {
    for ( j = 0; a4 > j; ++j )
    {
      v15 = (unsigned __int8 *)&a3[j];
      *((_BYTE *)self->redTransferTable + j) = (int)v15[3] >> v7;
      *((_BYTE *)self->greenTransferTable + j) = (int)v15[2] >> v7;
      *((_BYTE *)self->blueTransferTable + j) = (int)v15[1] >> v7;
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


/* _displayInfoToColorSpace at 0x2544 */
int __cdecl displayInfoToColorSpace(int a1)
{
  unsigned int v1; // eax

  v1 = *(_DWORD *)(a1 + 24);
  if ( v1 == 3 )
    return 2;
  if ( v1 > 3 )
  {
    if ( v1 == 4 )
      return 3;
  }
  else if ( v1 == 1 )
  {
    return *(_DWORD *)(a1 + 28) != 1;
  }
  IOLog("ATIMach64: displayInfoToColorSpace problem (%d)\n", *(_DWORD *)(a1 + 24));
  IOPanic("ATIMach64 displayInfoToColorSpace");
  return 0;
}


/* _colorDepthToColorSpace at 0x25ac */
int __cdecl colorDepthToColorSpace(int a1)
{
  int result; // eax

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
      result = 0;
      break;
  }
  return result;
}


/* _displayInfoToColorDepth at 0x2604 */
int __cdecl displayInfoToColorDepth(int a1)
{
  unsigned int v1; // eax

  v1 = *(_DWORD *)(a1 + 24);
  if ( v1 == 3 )
    return 3;
  if ( v1 > 3 )
  {
    if ( v1 == 4 )
      return 6;
  }
  else if ( v1 == 1 )
  {
    return 2;
  }
  IOPanic("ATIMach64: displayInfoToColorDepth problem");
  return 0;
}


/* _memSizeToBytes at 0x2658 */
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


/* -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:] at 0x2438 */
int __cdecl -[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:](
        ATI_BIOS *self,
        SEL a2,
        unsigned int a3,
        char a4,
        unsigned int a5,
        unsigned int a6,
        $A20FE96C2C87A6321064A4A17D01798F *a7,
        unsigned __int8 a8,
        const char *a9)
{
  int result; // eax
  unsigned __int8 v10; // al
  id v11; // eax
  char v12; // [esp+Ch] [ebp-38h]
  _BYTE v13[4]; // [esp+14h] [ebp-30h] BYREF
  int v14; // [esp+18h] [ebp-2Ch]
  int v15; // [esp+1Ch] [ebp-28h]
  __int16 v16; // [esp+34h] [ebp-10h]
  int v17; // [esp+38h] [ebp-Ch]

  v12 = 0;
  if ( self->initialized == 0 )
    return 1;
  if ( a6 == 128 )
    return 3;
  -[ATI_BIOS initBIOSBuf:function:](self, sel_initBIOSBuf_function_, v13, (char)a8);
  v10 = (_BYTE)a5 << 6;
  if ( a4 != 0 )
    v10 |= 0x10u;
  v16 = ((_WORD)a6 << 8) | a3 | v10;
  if ( a6 == 129 )
  {
    result = -[ATI_BIOS createDataSegment:size:](self, sel_createDataSegment_size_, a7, 30);
    if ( result != 0 )
      return result;
    v17 = 136;
    v15 = 0;
    v12 = 1;
  }
  v11 = -[ATI_BIOS doBios:dataSeg:](self, sel_doBios_dataSeg_, v13, v12);
  if ( v11 != nullptr )
  {
    IOLog("ATI_BIOS %s: ATIbios32() returned %d\n", a9, v11);
    return 2;
  }
  if ( BYTE1(v14) != 0 )
  {
    IOLog("ATI_BIOS %s: ah = 0x%x on return from ATIbios32()\n", a9, BYTE1(v14));
    return 2;
  }
  return 0;
}
