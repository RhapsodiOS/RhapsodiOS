/* Generated from reference-contract.json; do not hand-edit table records. */
#ifndef __ATIRAGE_MODES_H__
#define __ATIRAGE_MODES_H__

#import "ATI_BIOS.h"
#import <driverkit/driverTypes.h>

static const unsigned char AtiVgaCRTC[30] = {
    0x00, 0x00, 0x80, 0x00, 0x00, 0x08, 0x63, 0x4f, 0x52, 0x2c, 0x0c, 0x02, 0xdf, 0x01, 0xea, 0x01, 0x22, 0xff, 0xd6, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static const unsigned char gamma16[16] = {
    0x00, 0x4a, 0x66, 0x7b, 0x8c, 0x9b, 0xa8, 0xb4, 0xc0, 0xca, 0xd4, 0xdd, 0xe6, 0xef, 0xf7, 0xff
};
static const unsigned char gamma8[256] = {
    0x00, 0x0f, 0x16, 0x1b, 0x1f, 0x23, 0x27, 0x2a, 0x2d, 0x2f, 0x32, 0x34, 0x37, 0x39, 0x3b, 0x3d, 0x3f, 0x41, 0x43, 0x45, 0x47, 0x49, 0x4a, 0x4c, 0x4e, 0x4f, 0x51, 0x52, 0x54, 0x55, 0x57, 0x58, 0x5a, 0x5b, 0x5d, 0x5e, 0x5f, 0x61, 0x62, 0x63, 0x64, 0x66, 0x67, 0x68, 0x69, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa2, 0xa3, 0xa4, 0xa5, 0xa5, 0xa6, 0xa7, 0xa8, 0xa8, 0xa9, 0xaa, 0xab, 0xab, 0xac, 0xad, 0xae, 0xae, 0xaf, 0xb0, 0xb1, 0xb1, 0xb2, 0xb3, 0xb3, 0xb4, 0xb5, 0xb6, 0xb6, 0xb7, 0xb8, 0xb8, 0xb9, 0xba, 0xba, 0xbb, 0xbc, 0xbc, 0xbd, 0xbe, 0xbe, 0xbf, 0xc0, 0xc0, 0xc1, 0xc2, 0xc2, 0xc3, 0xc4, 0xc4, 0xc5, 0xc6, 0xc6, 0xc7, 0xc8, 0xc8, 0xc9, 0xc9, 0xca, 0xcb, 0xcb, 0xcc, 0xcd, 0xcd, 0xce, 0xce, 0xcf, 0xd0, 0xd0, 0xd1, 0xd2, 0xd2, 0xd3, 0xd3, 0xd4, 0xd5, 0xd5, 0xd6, 0xd6, 0xd7, 0xd8, 0xd8, 0xd9, 0xd9, 0xda, 0xda, 0xdb, 0xdc, 0xdc, 0xdd, 0xdd, 0xde, 0xde, 0xdf, 0xe0, 0xe0, 0xe1, 0xe1, 0xe2, 0xe2, 0xe3, 0xe4, 0xe4, 0xe5, 0xe5, 0xe6, 0xe6, 0xe7, 0xe7, 0xe8, 0xe9, 0xe9, 0xea, 0xea, 0xeb, 0xeb, 0xec, 0xec, 0xed, 0xed, 0xee, 0xee, 0xef, 0xf0, 0xf0, 0xf1, 0xf1, 0xf2, 0xf2, 0xf3, 0xf3, 0xf4, 0xf4, 0xf5, 0xf5, 0xf6, 0xf6, 0xf7, 0xf7, 0xf8, 0xf8, 0xf9, 0xf9, 0xfa, 0xfa, 0xfb, 0xfb, 0xfc, 0xfc, 0xfd, 0xfd, 0xfe, 0xff
};

IONamedValue bitsPerPixelValues[6] = {
    { 0, "2 Bits Per Pixel" }, { 1, "8 Bits Per Pixel" }, { 2, "12 Bits Per Pixel" }, { 3, "15 Bits Per Pixel" }, { 4, "24 Bits Per Pixel" }, { 0, 0 }
};
IONamedValue colorConfigValues[7] = {
    { 0, "Default" }, { 1, "RGBx" }, { 2, "BGRx" }, { 3, "xRGB" }, { 4, "xBGR" }, { 5, "None" }, { 0, 0 }
};
static int Refresh_60_72_75[4] = { 60, 72, 75, -1 };
static int Refresh_60_70_75[4] = { 60, 70, 75, -1 };
ATI_ModeRefreshMap ATI_modeToRefreshRatesTable[6] = {
    { 18, Refresh_60_72_75 }, { 106, Refresh_60_72_75 }, { 85, Refresh_60_70_75 }, { 131, Refresh_60_70_75 }, { 132, Refresh_60_72_75 }, { 0, 0 }
};

static ATI_CRTCRecord _AtiCRTCList[18] = {
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0x63, 0x4f, 0x52, 0x2c, 0x020c, 0x01df, 0x01ea, 0x22, 0xff, 0x09d6, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0x67, 0x4f, 0x52, 0x25, 0x0207, 0x01df, 0x01e8, 0x23, 0xff, 0x0c30, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0x68, 0x4f, 0x51, 0x28, 0x01f3, 0x01df, 0x01e0, 0x23, 0xff, 0x0c4e, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0x83, 0x63, 0x68, 0x10, 0x0273, 0x0257, 0x0258, 0x04, 0xff, 0x0fa0, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0x81, 0x63, 0x6a, 0x0f, 0x029b, 0x0257, 0x027c, 0x06, 0xff, 0x1388, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0x83, 0x63, 0x65, 0x0a, 0x0270, 0x0257, 0x0258, 0x03, 0xff, 0x1356, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0xa7, 0x7f, 0x82, 0x31, 0x0325, 0x02ff, 0x0302, 0x26, 0xff, 0x1964, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0xa5, 0x7f, 0x82, 0x11, 0x0325, 0x02ff, 0x0302, 0x06, 0xff, 0x1d4c, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0xa3, 0x7f, 0x81, 0x0c, 0x031f, 0x02ff, 0x0300, 0x03, 0xff, 0x1ec3, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0xb5, 0x8f, 0x97, 0x0e, 0x0393, 0x035f, 0x0365, 0x05, 0xff, 0x1f40, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0xbc, 0x8f, 0x93, 0x13, 0x03b0, 0x035f, 0x036c, 0x0b, 0xff, 0x2710, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0xb6, 0x8f, 0x92, 0x12, 0x03e9, 0x035f, 0x038c, 0x08, 0xff, 0x2af8, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0xd6, 0x9f, 0xa9, 0x2e, 0x042a, 0x03ff, 0x0400, 0x25, 0xff, 0x2af8, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0xd2, 0x9f, 0xa9, 0x0e, 0x0429, 0x03ff, 0x0400, 0x05, 0xff, 0x3138, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x00, 0x0800, 0xd2, 0x9f, 0xa1, 0x12, 0x0429, 0x03ff, 0x0400, 0x03, 0xff, 0x34bc, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x84, 0x0800, 0x0d, 0xc7, 0x18, 0xcf, 0x04e1, 0x04af, 0x04b0, 0x03, 0xff, 0x4f1a, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x84, 0x0000, 0x0d, 0xc7, 0x18, 0xcf, 0x04e1, 0x04af, 0x04b0, 0x03, 0xff, 0x49d4, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
    { 0x00, 0x00, 0x80, 0x84, 0x0000, 0xff, 0xc7, 0xcb, 0x34, 0x04f5, 0x04af, 0x04b9, 0x28, 0xff, 0x3cf0, 0x0000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0000 },
};

IODisplayInfo AtiModeList[72] = {
    { 640, 480, 640, 640, 60, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[0], 307200, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 640, 60, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[0], 307200, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 1280, 60, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[0], 614400, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 2560, 60, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[0], 1228800, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 640, 72, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[1], 307200, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 640, 72, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[1], 307200, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 1280, 72, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[1], 614400, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 2560, 72, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[1], 1228800, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 640, 75, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[2], 307200, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 640, 75, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[2], 307200, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 1280, 75, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[2], 614400, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 640, 480, 640, 2560, 75, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[2], 1228800, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 960, 960, 60, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[3], 576000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 960, 960, 60, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[3], 576000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 800, 1600, 60, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[3], 960000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 800, 3200, 60, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[3], 1920000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 960, 960, 72, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[4], 576000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 960, 960, 72, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[4], 576000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 800, 1600, 72, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[4], 960000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 800, 3200, 72, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[4], 1920000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 960, 960, 75, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[5], 576000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 960, 960, 75, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[5], 576000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 800, 1600, 75, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[5], 960000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 800, 600, 800, 3200, 75, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[5], 1920000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 1024, 60, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[6], 786432, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 1024, 60, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[6], 786432, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 2048, 60, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[6], 1572864, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 4096, 60, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[6], 3145728, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 1024, 70, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[7], 786432, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 1024, 70, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[7], 786432, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 2048, 70, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[7], 1572864, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 4096, 70, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[7], 3145728, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 1024, 75, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[8], 786432, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 1024, 75, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[8], 786432, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 2048, 75, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[8], 1572864, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1024, 768, 1024, 4096, 75, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[8], 3145728, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 1152, 60, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[9], 995328, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 1152, 60, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[9], 995328, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 2304, 60, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[9], 1990656, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 4608, 60, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[9], 3981312, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 1152, 70, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[10], 995328, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 1152, 70, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[10], 995328, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 2304, 70, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[10], 1990656, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 4608, 70, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[10], 3981312, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 1152, 75, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[11], 995328, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 1152, 75, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[11], 995328, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 2304, 75, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[11], 1990656, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1152, 864, 1152, 4608, 75, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[11], 3981312, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 1280, 60, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[12], 1310720, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 1280, 60, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[12], 1310720, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 2560, 60, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[12], 2621440, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 5120, 60, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[12], 5242880, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 1280, 70, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[13], 1310720, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 1280, 70, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[13], 1310720, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 2560, 70, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[13], 2621440, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 5120, 70, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[13], 5242880, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 1280, 75, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[14], 1310720, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 1280, 75, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[14], 1310720, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 2560, 75, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[14], 2621440, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1280, 1024, 1280, 5120, 75, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[14], 5242880, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1600, 1600, 60, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[17], 1920000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1600, 1600, 60, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[17], 1920000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1600, 3200, 60, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[17], 3840000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1632, 6528, 60, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[17], 7833600, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1600, 1600, 70, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[16], 1920000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1600, 1600, 70, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[16], 1920000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1600, 3200, 70, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[16], 3840000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1632, 6528, 70, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[16], 7833600, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1600, 1600, 75, 0, 1, 1, "WWWWWWWW", 120, (void *)&_AtiCRTCList[15], 1920000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1600, 1600, 75, 0, 1, 2, "PPPPPPPP", 120, (void *)&_AtiCRTCList[15], 1920000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1600, 3200, 75, 0, 3, 2, "-RRRRRGGGGGBBBBB", 120, (void *)&_AtiCRTCList[15], 3840000, 0, 0, 175000000, 0, 0, 0, { 0 } },
    { 1600, 1200, 1632, 6528, 75, 0, 4, 2, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 120, (void *)&_AtiCRTCList[15], 7833600, 0, 0, 175000000, 0, 0, 0, { 0 } },
};

static unsigned int AtiModeListCount = 72;
#define ATI_MODE_COUNT 72

#endif /* __ATIRAGE_MODES_H__ */
