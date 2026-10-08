#ifndef _INTERCEPTOR_DISPLAY_MODE_H_
#define _INTERCEPTOR_DISPLAY_MODE_H_

enum {
    NSDirectScreenModeTwoBitGrey,
    NSDirectScreenModeEightBitGrey,
    NSDirectScreenModeBlackEightBit,
    NSDirectScreenModeBlackTwelveBit,
    NSDirectScreenModeBlackFifteenBit,
    NSDirectScreenModeBlackTwentyFourBit,
    NSDirectScreenModeWhiteTwelveBit,
    NSDirectScreenModeWhiteFifteenBit,
    NSDirectScreenModeWhiteTwentyFourBit,
    NSDirectScreenModeTwoBitPseudoColor,
    NSDirectScreenModeEightBitPseudoColor,
    NSDirectScreenModeTwelveBitRGB,
    NSDirectScreenModeFifteenBitRGB,
    NSDirectScreenModeThirtyTwoBitRGB
};

typedef struct {
    int depth;
    int bitsPerPixel;
    int bitsPerSample;
    int samplesPerPixel;
    int encoding;
} NSDirectScreenModeFormat;

static const char *NSDirectScreenPixelEncodingForCode(int encoding)
{
    switch (encoding) {
    case NSDirectScreenModeTwoBitGrey:
        return "KK";
    case NSDirectScreenModeEightBitGrey:
        return "WWWWWWWW";
    case NSDirectScreenModeBlackEightBit:
        return "KKKKKKKK";
    case NSDirectScreenModeBlackTwelveBit:
        return "KKKKKKKKKKKK----";
    case NSDirectScreenModeBlackFifteenBit:
        return "-KKKKKKKKKKKKKKK";
    case NSDirectScreenModeBlackTwentyFourBit:
        return "KKKKKKKKKKKKKKKKKKKKKKKK--------";
    case NSDirectScreenModeWhiteTwelveBit:
        return "WWWWWWWWWWWW----";
    case NSDirectScreenModeWhiteFifteenBit:
        return "-WWWWWWWWWWWWWWW";
    case NSDirectScreenModeWhiteTwentyFourBit:
        return "WWWWWWWWWWWWWWWWWWWWWWWW--------";
    case NSDirectScreenModeTwoBitPseudoColor:
        return "PP";
    case NSDirectScreenModeEightBitPseudoColor:
        return "PPPPPPPP";
    case NSDirectScreenModeTwelveBitRGB:
        return "RRRRGGGGBBBB----";
    case NSDirectScreenModeFifteenBitRGB:
        return "-RRRRRGGGGGBBBBB";
    case NSDirectScreenModeThirtyTwoBitRGB:
        return "RRRRRRRRGGGGGGGGBBBBBBBB--------";
    default:
        return 0;
    }
}

/* Color-space and depth codes follow DriverKit's IOColorSpace and
 * IOBitsPerPixel values. */
static int NSDirectScreenModeFormatForCodes(int colorSpace, int depth,
                                            NSDirectScreenModeFormat *format)
{
    static const NSDirectScreenModeFormat formats[3][5] = {
        {
            { 2, 2, 2, 1, NSDirectScreenModeTwoBitGrey },
            { 8, 8, 8, 1, NSDirectScreenModeBlackEightBit },
            { 12, 16, 12, 1, NSDirectScreenModeBlackTwelveBit },
            { 15, 16, 15, 1, NSDirectScreenModeBlackFifteenBit },
            { 24, 32, 24, 1, NSDirectScreenModeBlackTwentyFourBit }
        },
        {
            { 2, 2, 2, 1, NSDirectScreenModeEightBitGrey },
            { 8, 8, 8, 1, NSDirectScreenModeEightBitGrey },
            { 12, 16, 12, 1, NSDirectScreenModeWhiteTwelveBit },
            { 15, 16, 15, 1, NSDirectScreenModeWhiteFifteenBit },
            { 24, 32, 24, 1, NSDirectScreenModeWhiteTwentyFourBit }
        },
        {
            { 2, 2, 1, 3, NSDirectScreenModeTwoBitPseudoColor },
            { 8, 8, 2, 3, NSDirectScreenModeEightBitPseudoColor },
            { 12, 16, 4, 3, NSDirectScreenModeTwelveBitRGB },
            { 15, 16, 5, 3, NSDirectScreenModeFifteenBitRGB },
            { 24, 32, 8, 3, NSDirectScreenModeThirtyTwoBitRGB }
        }
    };

    if (colorSpace < 0 || colorSpace >= 3 || depth < 0 || depth >= 5)
        return 0;
    *format = formats[colorSpace][depth];
    return 1;
}

#endif
