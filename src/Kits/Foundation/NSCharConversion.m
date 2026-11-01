/*	NSCharConversion.m
	Byte-to-string conversion helpers
*/

#import <Foundation/NSString.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSException.h>
#import <Foundation/NSZone.h>

#include <string.h>

extern int _NSProprietaryEncodingToUnicode(unsigned char **bytes,
                                           unsigned remaining,
                                           unichar *characters);

static const unichar NSJISX0201ToUnicodeTable[256] = {
    0x005f, 0x0060, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066,
    0x0067, 0x0068, 0x0069, 0x006a, 0x006b, 0x006c, 0x006d, 0x006e,
    0x006f, 0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075, 0x0076,
    0x0077, 0x0078, 0x0079, 0x007a, 0x007b, 0x007c, 0x007d, 0x007e,
    0x007f, 0x0080, 0x0081, 0x0082, 0x0083, 0x0084, 0x0085, 0x0086,
    0x0087, 0x0088, 0x0089, 0x008a, 0x008b, 0x008c, 0x008d, 0x008e,
    0x008f, 0x0090, 0x0091, 0x0092, 0x0093, 0x0094, 0x0095, 0x0096,
    0x0097, 0x0098, 0x0099, 0x009a, 0x009b, 0x009c, 0x009d, 0x009e,
    0x009f, 0x00a0, 0x00a1, 0x00a2, 0x00a3, 0x00a4, 0x00a5, 0x00a6,
    0x00a7, 0x00a8, 0x00a9, 0x00aa, 0x00ab, 0x00ac, 0x00ad, 0x00ae,
    0x00af, 0x00b0, 0x00b1, 0x00b2, 0x00b3, 0x00b4, 0x00b5, 0x00b6,
    0x00b7, 0x00b8, 0x00b9, 0x00ba, 0x00bb, 0x00bc, 0x00bd, 0x00be,
    0x00bf, 0x00e0, 0x00e1, 0x00e2, 0x00e3, 0x00e4, 0x00e5, 0x00e6,
    0x00e7, 0x00e8, 0x00e9, 0x00ea, 0x00eb, 0x00ec, 0x00ed, 0x00ee,
    0x00ef, 0x00f0, 0x00f1, 0x00f2, 0x00f3, 0x00f4, 0x00f5, 0x00f6,
    0x00d7, 0x00f8, 0x00f9, 0x00fa, 0x00fb, 0x00fc, 0x00fd, 0x00fe,
    0x00df, 0x00e0, 0x00e1, 0x00e2, 0x00e3, 0x00e4, 0x00e5, 0x00e6,
    0x00e7, 0x00e8, 0x00e9, 0x00ea, 0x00eb, 0x00ec, 0x00ed, 0x00ee,
    0x00ef, 0x00f0, 0x00f1, 0x00f2, 0x00f3, 0x00f4, 0x00f5, 0x00f6,
    0x00f7, 0x00f8, 0x00f9, 0x00fa, 0x00fb, 0x00fc, 0x00fd, 0x00fe,
    0x00ff, 0xff61, 0xff62, 0xff63, 0xff64, 0xff65, 0xff66, 0xff67,
    0xff68, 0xff69, 0xff6a, 0xff6b, 0xff6c, 0xff6d, 0xff6e, 0xff6f,
    0xff70, 0xff71, 0xff72, 0xff73, 0xff74, 0xff75, 0xff76, 0xff77,
    0xff78, 0xff79, 0xff7a, 0xff7b, 0xff7c, 0xff7d, 0xff7e, 0xff7f,
    0xff80, 0xff81, 0xff82, 0xff83, 0xff84, 0xff85, 0xff86, 0xff87,
    0xff88, 0xff89, 0xff8a, 0xff8b, 0xff8c, 0xff8d, 0xff8e, 0xff8f,
    0xff90, 0xff91, 0xff92, 0xff93, 0xff94, 0xff95, 0xff96, 0xff97,
    0xff98, 0xff99, 0xff9a, 0xff9b, 0xff9c, 0xff9d, 0xff9e, 0xff9f,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd
};

extern char _NSFoundationResourceCPath(char *path);
extern int _NSReadBytesFromFile(char *path, void **bytes, unsigned *length,
#if defined(__ppc__) || defined(__POWERPC__)
                                NSZone *zone, char allocatePages);
#else
                                NSZone *zone);
#endif
extern unsigned _loadConvTable(unsigned short **table, const char *name);
extern unsigned short NS16To16BitEncoding(unsigned short *table,
                                          unsigned count,
                                          unichar character);
extern unichar NSNEXTSTEPToPrecompUnicode(unsigned char byte);

void *NSDecompBuffer;
unsigned NSTotalDecompElements;
id NSDecompSet;
char _decompTableCouldNotBeLoaded;
unsigned _NSNumSlotsInJisUniTable;
unsigned short *JIS0208_To_Uni_Table;
static unsigned char NSFailedToLoadEUCTableWarning;

int
NSNextEUCToUnicode(unsigned char **bytes, unsigned remaining,
                   unichar *character)
{
    unsigned char first = **bytes;
    unsigned short converted;

    if (JIS0208_To_Uni_Table == NULL) {
        _NSNumSlotsInJisUniTable =
            _loadConvTable(&JIS0208_To_Uni_Table, "EUCToUnicode");
        if (_NSNumSlotsInJisUniTable == 0) {
            if (!NSFailedToLoadEUCTableWarning) {
                NSFailedToLoadEUCTableWarning = 1;
                NSLog(@"NSCharConversion: could not load EUCToUnicode conversion table.\n");
            }
            return 0;
        }
    }

    ++*bytes;
    if (first <= 0x7f) {
        *character = first;
        return 1;
    }
    if (first == 0x8e) {
        if (remaining != 1 && **bytes > 0xa0) {
            *character = NSJISX0201ToUnicodeTable[*(*bytes)++];
            return 1;
        }
    } else if (first == 0xa0) {
        if (remaining != 1 && (signed char)**bytes < 0) {
            *character = NSNEXTSTEPToPrecompUnicode(*(*bytes)++);
            return 1;
        }
    } else if (remaining != 1 && first > 0xa0 && **bytes > 0xa0) {
        unsigned short jis = (unsigned short)(first << 8) | **bytes;

        ++*bytes;
        converted = NS16To16BitEncoding(JIS0208_To_Uni_Table,
                                        _NSNumSlotsInJisUniTable, jis);
        *character = converted;
        return 1;
    }
    *character = NSNEXTSTEPToPrecompUnicode(first);
    return 1;
}

int
NSShiftJISToEUC(const unsigned char *shiftJIS, unsigned char *euc,
                unsigned int *consumed)
{
    unsigned char lead = shiftJIS[0];
    unsigned char trail = shiftJIS[1];
    unsigned char jisLead;
    unsigned char jisTrail;

    if (lead < 0x80) {
        euc[0] = lead;
        *consumed = 1;
        return 1;
    }
    if (lead >= 0xa1 && lead <= 0xdf) {
        euc[0] = 0x8e;
        euc[1] = lead;
        *consumed = 1;
        return 2;
    }
    if (lead == 0x87 && trail >= 0x41 && trail <= 0x99) {
        if ((trail & 0x0f) > 9 ||
            (unsigned char)(trail + 0x8a) <= 9)
            return 0;
        switch (trail) {
            case 0x90:
                euc[0] = 0xa2;
                euc[1] = 0xe2;
                break;
            case 0x91:
                euc[0] = 0xa2;
                euc[1] = 0xe1;
                break;
            case 0x92:
                euc[0] = 0xa2;
                euc[1] = 0xe9;
                break;
            case 0x95:
                euc[0] = 0xa2;
                euc[1] = 0xe5;
                break;
            case 0x96:
                euc[0] = 0xa2;
                euc[1] = 0xdd;
                break;
            case 0x97:
                euc[0] = 0xa2;
                euc[1] = 0xdc;
                break;
            default:
                euc[0] = 0xfe;
                euc[1] = (unsigned char)(trail + (trail <= 0x7f ? 0x61 : 0x60));
                break;
        }
        *consumed = 2;
        return 2;
    }
    if (lead >= 0xf0 && lead <= 0xfc &&
        trail >= 0x40 && trail <= 0xfc && trail != 0x7f) {
        euc[0] = '?';
        euc[1] = '?';
        *consumed = 2;
        return 2;
    }
    if (!((lead >= 0x81 && lead <= 0x9f) ||
          (lead >= 0xe0 && lead <= 0xfc)) ||
        trail < 0x40 || trail > 0xfc || trail == 0x7f)
        return 0;

    if (lead <= 0x9f)
        jisLead = (unsigned char)(2 * (lead - 0x71) + 1);
    else
        jisLead = (unsigned char)(2 * (lead + 0x4f) + 1);
    if (trail > 0x7f)
        --trail;
    if (trail <= 0x9d) {
        jisTrail = (unsigned char)(trail - 0x1f);
    } else {
        jisTrail = (unsigned char)(trail - 0x7d);
        ++jisLead;
    }
    euc[0] = jisLead | 0x80;
    euc[1] = jisTrail | 0x80;
    *consumed = 2;
    return 2;
}

int
NSShiftJISToUnicode(unsigned char **bytes, unsigned remaining,
                    unichar *character)
{
    unsigned char euc[2];
    unsigned char *eucBytes = euc;
    unsigned int consumed = 0;

    if (**bytes <= 0x7f) {
        *character = **bytes;
        ++*bytes;
        return 1;
    }
    if ((unsigned char)(**bytes + 0x5f) <= 0x3e) {
        *character = (unichar)(**bytes - 320);
        ++*bytes;
        return 1;
    }
    (void)NSShiftJISToEUC(*bytes, euc, &consumed);
    if (consumed != 0) {
        *bytes += consumed;
        return NSNextEUCToUnicode(&eucBytes, remaining, character);
    }
    ++*bytes;
    return 0;
}

static unsigned short
NSDecompositionWord(const unsigned char *bytes)
{
    return (unsigned short)(bytes[0] | ((unsigned short)bytes[1] << 8));
}

static void
NSReadDecompFile(void)
{
    char path[1028];
    unsigned length;
    void *buffer;

    if (_decompTableCouldNotBeLoaded)
        return;
    _NSFoundationResourceCPath(path);
    strcat(path, "/CharacterSets/NonHangulDecomp.data");
#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSReadBytesFromFile(path, &buffer, &length, NULL, 0)) {
#else
    if (_NSReadBytesFromFile(path, &buffer, &length, NULL)) {
#endif
        NSDecompBuffer = buffer;
        NSTotalDecompElements = NSDecompositionWord(
            (const unsigned char *)buffer + 4);
        NSDecompSet = [[NSCharacterSet decomposableCharacterSet] retain];
    } else {
        _decompTableCouldNotBeLoaded = 1;
        NSLog(@"Warning: unable to load character decomposition table.\n");
    }
}

static int
NSDecompositionOffset(unichar character)
{
    const unsigned char *mappings =
        (const unsigned char *)NSDecompBuffer + 8;
    int first = 0;
    int last = (int)NSTotalDecompElements - 1;

    while (first <= last) {
        int middle = first + (last - first) / 2;
        unsigned short mappedCharacter =
            NSDecompositionWord(mappings + middle * 4);

        if (character < mappedCharacter) {
            last = middle - 1;
        } else if (character > mappedCharacter) {
            first = middle + 1;
        } else {
            return NSDecompositionWord(mappings + middle * 4 + 2);
        }
    }
    return -1;
}

int
NSSimplyDecomposeCharacter(unichar character, unichar *characters)
{
    const unsigned char *sequence;
    int offset;
    int count = 0;

    if (NSDecompBuffer == NULL)
        NSReadDecompFile();
    if (NSDecompBuffer == NULL ||
        ![(NSCharacterSet *)NSDecompSet characterIsMember:character]) {
        characters[0] = character;
        return 1;
    }

    offset = NSDecompositionOffset(character);
    if (offset < 0) {
        [NSException raise:nil
                    format:@"Internal error in NSSimpleDecomposeCharacter()."];
        return 0;
    }
    sequence = (const unsigned char *)NSDecompBuffer + offset * 2;
    while (NSDecompositionWord(sequence + count * 2) != 0) {
        characters[count] = NSDecompositionWord(sequence + count * 2);
        ++count;
    }
    return count;
}

int
NSDecomposeCharacter(unichar character, unichar *characters)
{
    const unsigned char *sequence;
    int offset;
    int count = 0;

    if (NSDecompBuffer == NULL)
        NSReadDecompFile();
    if (NSDecompBuffer == NULL ||
        ![(NSCharacterSet *)NSDecompSet characterIsMember:character]) {
        characters[0] = character;
        return 1;
    }

    offset = NSDecompositionOffset(character);
    if (offset < 0) {
        [NSException raise:nil
                    format:@"Internal error in NSDecomposeCharacter()."];
        return 0;
    }
    sequence = (const unsigned char *)NSDecompBuffer + offset * 2;
    while (NSDecompositionWord(sequence) != 0) {
        count += NSSimplyDecomposeCharacter(
            NSDecompositionWord(sequence), characters + count);
        sequence += 2;
    }
    return count;
}

#define NSConversionInlineBytes 1008

typedef struct {
    unsigned char isCString;
    unsigned char allocated;
    unsigned char reserved[2];
    char *cstring;
    unichar *characters;
    unsigned length;
    unsigned char inlineStorage[NSConversionInlineBytes];
} NSCharConversionBuffer;

extern unichar (*_NSCStringCharToUnichar)(unsigned char byte);

static const unichar NSNEXTSTEPToUnicodeTable[128] = {
    0x00a0, 0x00c0, 0x00c1, 0x00c2, 0x00c3, 0x00c4, 0x00c5, 0x00c7,
    0x00c8, 0x00c9, 0x00ca, 0x00cb, 0x00cc, 0x00cd, 0x00ce, 0x00cf,
    0x00d0, 0x00d1, 0x00d2, 0x00d3, 0x00d4, 0x00d5, 0x00d6, 0x00d9,
    0x00da, 0x00db, 0x00dc, 0x00dd, 0x00de, 0x00b5, 0x00d7, 0x00f7,
    0x00a9, 0x00a1, 0x00a2, 0x00a3, 0x2044, 0x00a5, 0x0192, 0x00a7,
    0x00a4, 0x2019, 0x201c, 0x00ab, 0x2039, 0x203a, 0xfb01, 0xfb02,
    0x00ae, 0x2013, 0x2020, 0x2021, 0x00b7, 0x00a6, 0x00b6, 0x2022,
    0x201a, 0x201e, 0x201d, 0x00bb, 0x2026, 0x2030, 0x00ac, 0x00bf,
    0x00b9, 0x02cb, 0x00b4, 0x02c6, 0x02dc, 0x00af, 0x02d8, 0x02d9,
    0x00a8, 0x00b2, 0x02da, 0x00b8, 0x00b3, 0x02dd, 0x02db, 0x02c7,
    0x2014, 0x00b1, 0x00bc, 0x00bd, 0x00be, 0x00e0, 0x00e1, 0x00e2,
    0x00e3, 0x00e4, 0x00e5, 0x00e7, 0x00e8, 0x00e9, 0x00ea, 0x00eb,
    0x00ec, 0x00c6, 0x00ed, 0x00aa, 0x00ee, 0x00ef, 0x00f0, 0x00f1,
    0x0141, 0x00d8, 0x0152, 0x00ba, 0x00f2, 0x00f3, 0x00f4, 0x00f5,
    0x00f6, 0x00e6, 0x00f9, 0x00fa, 0x00fb, 0x0131, 0x00fc, 0x00fd,
    0x0142, 0x00f8, 0x0153, 0x00df, 0x00fe, 0x00ff, 0xfffd, 0xfffd
};

static const unichar NSSymbolToUnicodeTable[256] = {
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0x0020, 0x0021, 0x2200, 0x0023, 0x2203, 0x0025, 0x0026, 0x220b,
    0x0028, 0x0029, 0x2217, 0x002b, 0x002c, 0x2212, 0x002e, 0x002f,
    0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037,
    0x0038, 0x0039, 0x003a, 0x003b, 0x003c, 0x003d, 0x003e, 0x003f,
    0x2245, 0x0391, 0x0392, 0x03a7, 0x0394, 0x0395, 0x03a6, 0x0393,
    0x0397, 0x0399, 0x03d1, 0x039a, 0x039b, 0x039c, 0x039d, 0x039f,
    0x03a0, 0x0398, 0x03a1, 0x03a3, 0x03a4, 0x03a5, 0x03c2, 0x03a9,
    0x039e, 0x03a8, 0x0396, 0x005b, 0x2234, 0x005d, 0x22a5, 0x005f,
    0x203e, 0x03b1, 0x03b2, 0x03c7, 0x03b4, 0x03b5, 0x03c6, 0x03b3,
    0x03b7, 0x03b9, 0x03d5, 0x03ba, 0x03bb, 0x03bc, 0x03bd, 0x03bf,
    0x03c0, 0x03b8, 0x03c1, 0x03c3, 0x03c4, 0x03c5, 0x03d6, 0x03c9,
    0x03be, 0x03c8, 0x03b6, 0x007b, 0x007c, 0x007d, 0x223c, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0x03d2, 0x2032, 0x2264, 0x2215, 0x221e, 0x0192, 0x2663,
    0x2666, 0x2665, 0x2660, 0x2194, 0x2190, 0x2191, 0x2192, 0x2193,
    0x00b0, 0x00b1, 0x2033, 0x2265, 0x00d7, 0x221d, 0x2202, 0x2022,
    0x00f7, 0x2260, 0x2261, 0x2248, 0x2026, 0xfffd, 0xfffd, 0x21b5,
    0x2135, 0x2111, 0x211c, 0x2118, 0x2297, 0x2295, 0x2205, 0x2229,
    0x222a, 0x2283, 0x2287, 0x2284, 0x2282, 0x2286, 0x2208, 0x2209,
    0x2220, 0x2207, 0x00ae, 0x00a9, 0x2122, 0x220f, 0x221a, 0x22c5,
    0x00ac, 0x2227, 0x2228, 0x21d4, 0x21d0, 0x21d1, 0x21d2, 0x21d3,
    0x25ca, 0x2329, 0x00ae, 0x00a9, 0x2122, 0x2211, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0x232a, 0x222b, 0x2320, 0xfffd, 0x2321, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd
};

static const unichar NSCyrillicToUnicodeTable[128] = {
        0x0402, 0x0403, 0x201a, 0x0453, 0x201e, 0x2026, 0x2020, 0x2021,
#if defined(__ppc__) || defined(__POWERPC__)
        0x20ac,
#else
        0xfffd,
#endif
        0x2030, 0x0409, 0x2039, 0x040a, 0x040c, 0x040b, 0x040f,
        0x0452, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
        0xfffd, 0x2122, 0x0459, 0x203a, 0x045a, 0x045c, 0x045b, 0x045f,
        0x00a0, 0x040e, 0x045e, 0x0408, 0x00a4, 0x0490, 0x00a6, 0x00a7,
        0x0401, 0x00a9, 0x0404, 0x00ab, 0x00ac, 0x00ad, 0x00ae, 0x0407,
        0x00b0, 0x00b1, 0x0406, 0x0456, 0x0491, 0x00b5, 0x00b6, 0x00b7,
        0x0451, 0x2116, 0x0454, 0x00bb, 0x0458, 0x0405, 0x0455, 0x0457,
        0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
        0x0418, 0x0419, 0x041a, 0x041b, 0x041c, 0x041d, 0x041e, 0x041f,
        0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
        0x0428, 0x0429, 0x042a, 0x042b, 0x042c, 0x042d, 0x042e, 0x042f,
        0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
        0x0438, 0x0439, 0x043a, 0x043b, 0x043c, 0x043d, 0x043e, 0x043f,
        0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
        0x0448, 0x0449, 0x044a, 0x044b, 0x044c, 0x044d, 0x044e, 0x044f
};

static const unichar NSCP1250ToUnicodeTable[128] = {
#if defined(__ppc__) || defined(__POWERPC__)
        0x20ac,
#else
        0xfffd,
#endif
        0xfffd, 0x201a, 0xfffd, 0x201e, 0x2026, 0x2020, 0x2021,
        0xfffd, 0x2030, 0x0160, 0x2039, 0x015a, 0x0164, 0x017d, 0x0179,
        0xfffd, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
        0xfffd, 0x2122, 0x0161, 0x203a, 0x015b, 0x0165, 0x017e, 0x017a,
        0x00a0, 0x02c7, 0x02d8, 0x0141, 0x00a4, 0x0104, 0x00a6, 0x00a7,
        0x00a8, 0x00a9, 0x015e, 0x00ab, 0x00ac, 0x00ad, 0x00ae, 0x017b,
        0x00b0, 0x00b1, 0x02db, 0x0142, 0x00b4, 0x00b5, 0x00b6, 0x00b7,
        0x00b8, 0x0105, 0x015f, 0x00bb, 0x013d, 0x02dd, 0x013e, 0x017c,
        0x0154, 0x00c1, 0x00c2, 0x0102, 0x00c4, 0x0139, 0x0106, 0x00c7,
        0x010c, 0x00c9, 0x0118, 0x00cb, 0x011a, 0x00cd, 0x00ce, 0x010e,
        0x0110, 0x0143, 0x0147, 0x00d3, 0x00d4, 0x0150, 0x00d6, 0x00d7,
        0x0158, 0x016e, 0x00da, 0x0170, 0x00dc, 0x00dd, 0x0162, 0x00df,
        0x0155, 0x00e1, 0x00e2, 0x0103, 0x00e4, 0x013a, 0x0107, 0x00e7,
        0x010d, 0x00e9, 0x0119, 0x00eb, 0x011b, 0x00ed, 0x00ee, 0x010f,
        0x0111, 0x0144, 0x0148, 0x00f3, 0x00f4, 0x0151, 0x00f6, 0x00f7,
        0x0159, 0x016f, 0x00fa, 0x0171, 0x00fc, 0x00fd, 0x0163, 0x02d9
};

static const unichar NSCP1253ToUnicodeTable[128] = {
#if defined(__ppc__) || defined(__POWERPC__)
        0x20ac,
#else
        0xfffd,
#endif
        0xfffd, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
        0xfffd, 0x2030, 0xfffd, 0x2039, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
        0xfffd, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
        0xfffd, 0x2122, 0xfffd, 0x203a, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
        0x00a0, 0x0385, 0x0386, 0x00a3, 0x00a4, 0x00a5, 0x00a6, 0x00a7,
        0x00a8, 0x00a9, 0xf8f9, 0x00ab, 0x00ac, 0x00ad, 0x00ae, 0x2015,
        0x00b0, 0x00b1, 0x00b2, 0x00b3, 0x0384, 0x00b5, 0x00b6, 0x00b7,
        0x0388, 0x0389, 0x038a, 0x00bb, 0x038c, 0x00bd, 0x038e, 0x038f,
        0x0390, 0x0391, 0x0392, 0x0393, 0x0394, 0x0395, 0x0396, 0x0397,
        0x0398, 0x0399, 0x039a, 0x039b, 0x039c, 0x039d, 0x039e, 0x039f,
        0x03a0, 0x03a1, 0xf8fa, 0x03a3, 0x03a4, 0x03a5, 0x03a6, 0x03a7,
        0x03a8, 0x03a9, 0x03aa, 0x03ab, 0x03ac, 0x03ad, 0x03ae, 0x03af,
        0x03b0, 0x03b1, 0x03b2, 0x03b3, 0x03b4, 0x03b5, 0x03b6, 0x03b7,
        0x03b8, 0x03b9, 0x03ba, 0x03bb, 0x03bc, 0x03bd, 0x03be, 0x03bf,
        0x03c0, 0x03c1, 0x03c2, 0x03c3, 0x03c4, 0x03c5, 0x03c6, 0x03c7,
        0x03c8, 0x03c9, 0x03ca, 0x03cb, 0x03cc, 0x03cd, 0x03ce, 0xf8fb
};

static const unichar NSCP1254ToUnicodeTable[128] = {
#if defined(__ppc__) || defined(__POWERPC__)
        0x20ac,
#else
        0xfffd,
#endif
        0xfffd, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
        0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0xfffd, 0xfffd, 0xfffd,
        0xfffd, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
        0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0xfffd, 0xfffd, 0x0178,
        0x00a0, 0x00a1, 0x00a2, 0x00a3, 0x00a4, 0x00a5, 0x00a6, 0x00a7,
        0x00a8, 0x00a9, 0x00aa, 0x00ab, 0x00ac, 0x00ad, 0x00ae, 0x00af,
        0x00b0, 0x00b1, 0x00b2, 0x00b3, 0x00b4, 0x00b5, 0x00b6, 0x00b7,
        0x00b8, 0x00b9, 0x00ba, 0x00bb, 0x00bc, 0x00bd, 0x00be, 0x00bf,
        0x00c0, 0x00c1, 0x00c2, 0x00c3, 0x00c4, 0x00c5, 0x00c6, 0x00c7,
        0x00c8, 0x00c9, 0x00ca, 0x00cb, 0x00cc, 0x00cd, 0x00ce, 0x00cf,
        0x011e, 0x00d1, 0x00d2, 0x00d3, 0x00d4, 0x00d5, 0x00d6, 0x00d7,
        0x00d8, 0x00d9, 0x00da, 0x00db, 0x00dc, 0x0130, 0x015e, 0x00df,
        0x00e0, 0x00e1, 0x00e2, 0x00e3, 0x00e4, 0x00e5, 0x00e6, 0x00e7,
        0x00e8, 0x00e9, 0x00ea, 0x00eb, 0x00ec, 0x00ed, 0x00ee, 0x00ef,
        0x011f, 0x00f1, 0x00f2, 0x00f3, 0x00f4, 0x00f5, 0x00f6, 0x00f7,
        0x00f8, 0x00f9, 0x00fa, 0x00fb, 0x00fc, 0x0131, 0x015f, 0x00ff
};

static const unichar NSAdobeStandardToUnicodeTable[96] = {
    0xfffd, 0x00a1, 0x00a2, 0x00a3, 0x2044, 0x00a5, 0x0192, 0x00a7,
    0x00a4, 0x2019, 0x201c, 0x00ab, 0x2039, 0x203a, 0xfb01, 0xfb02,
    0xfffd, 0x2013, 0x2020, 0x2021, 0x00b7, 0xfffd, 0x00b6, 0x2022,
    0x201a, 0x201e, 0x201d, 0x00bb, 0x2026, 0x2030, 0xfffd, 0x00bf,
    0xfffd, 0x02cb, 0x00b4, 0x02c6, 0x02dc, 0x00af, 0x02d8, 0x02d9,
    0x00a8, 0xfffd, 0x02da, 0x00b8, 0xfffd, 0x02dd, 0x02db, 0x02c7,
    0x2014, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0x00c6, 0xfffd, 0x00aa, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0x0141, 0x00d8, 0x0152, 0x00ba, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0x00e6, 0xfffd, 0xfffd, 0xfffd, 0x0131, 0xfffd, 0xfffd,
    0x0142, 0x00f8, 0x0153, 0x00df, 0xfffd, 0xfffd, 0xfffd, 0xfffd
};

static const unichar NSISOLatin2ToUnicodeTable[96] = {
    0x00a0, 0x0104, 0x02d8, 0x0141, 0x00a4, 0x013d, 0x015a, 0x00a7,
    0x00a8, 0x0160, 0x015e, 0x0164, 0x0179, 0x00ad, 0x017d, 0x017b,
    0x00b0, 0x0105, 0x02db, 0x0142, 0x00b4, 0x013e, 0x015b, 0x02c7,
    0x00b8, 0x0161, 0x015f, 0x0165, 0x017a, 0x02dd, 0x017e, 0x017c,
    0x0154, 0x00c1, 0x00c2, 0x0102, 0x00c4, 0x0139, 0x0106, 0x00c7,
    0x010c, 0x00c9, 0x0118, 0x00cb, 0x011a, 0x00cd, 0x00ce, 0x010e,
    0x0110, 0x0143, 0x0147, 0x00d3, 0x00d4, 0x0150, 0x00d6, 0x00d7,
    0x0158, 0x016e, 0x00da, 0x0170, 0x00dc, 0x00dd, 0x0162, 0x00df,
    0x0155, 0x00e1, 0x00e2, 0x0103, 0x00e4, 0x013a, 0x0107, 0x00e7,
    0x010d, 0x00e9, 0x0119, 0x00eb, 0x011b, 0x00ed, 0x00ee, 0x010f,
    0x0111, 0x0144, 0x0148, 0x00f3, 0x00f4, 0x0151, 0x00f6, 0x00f7,
    0x0159, 0x016f, 0x00fa, 0x0171, 0x00fc, 0x00fd, 0x0163, 0x02d9
};

static const unichar NSZapfDingbatToUnicodeTable[256] = {
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0x2701, 0x2702, 0x2703, 0x2704, 0x260e, 0x2706, 0x2707,
    0x2708, 0x2709, 0x261b, 0x261e, 0x270c, 0x270d, 0x270e, 0x270f,
    0x2710, 0x2711, 0x2712, 0x2713, 0x2714, 0x2715, 0x2716, 0x2717,
    0x2718, 0x2719, 0x271a, 0x271b, 0x271c, 0x271d, 0x271e, 0x271f,
    0x2720, 0x2721, 0x2722, 0x2723, 0x2724, 0x2725, 0x2726, 0x2727,
    0x2605, 0x2729, 0x272a, 0x272b, 0x272c, 0x272d, 0x272e, 0x272f,
    0x2730, 0x2731, 0x2732, 0x2733, 0x2734, 0x2735, 0x2736, 0x2737,
    0x2738, 0x2739, 0x273a, 0x273b, 0x273c, 0x273d, 0x273e, 0x273f,
    0x2740, 0x2741, 0x2742, 0x2743, 0x2744, 0x2745, 0x2746, 0x2747,
    0x2748, 0x2749, 0x274a, 0x274b, 0x25cf, 0x274d, 0x25a0, 0x274f,
    0x2750, 0x2751, 0x2752, 0x25b2, 0x25bc, 0x25c6, 0x2756, 0x25d7,
    0x2758, 0x2759, 0x275a, 0x275b, 0x275c, 0x275d, 0x275e, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0xfffd,
    0xfffd, 0x2761, 0x2762, 0x2763, 0x2764, 0x2765, 0x2766, 0x2767,
    0x2663, 0x2666, 0x2665, 0x2660, 0x2460, 0x2461, 0x2462, 0x2463,
    0x2464, 0x2465, 0x2466, 0x2467, 0x2468, 0x2469, 0x2776, 0x2777,
    0x2778, 0x2779, 0x277a, 0x277b, 0x277c, 0x277d, 0x277e, 0x277f,
    0x2780, 0x2781, 0x2782, 0x2783, 0x2784, 0x2785, 0x2786, 0x2787,
    0x2788, 0x2789, 0x278a, 0x278b, 0x278c, 0x278d, 0x278e, 0x278f,
    0x2790, 0x2791, 0x2792, 0x2793, 0x2794, 0x2192, 0x2194, 0x2195,
    0x2798, 0x2799, 0x279a, 0x279b, 0x279c, 0x279d, 0x279e, 0x279f,
    0x27a0, 0x27a1, 0x27a2, 0x27a3, 0x27a4, 0x27a5, 0x27a6, 0x27a7,
    0x27a8, 0x27a9, 0x27aa, 0x27ab, 0x27ac, 0x27ad, 0x27ae, 0x27af,
    0xfffd, 0x27b1, 0x27b2, 0x27b3, 0x27b4, 0x27b5, 0x27b6, 0x27b7,
    0x27b8, 0x27b9, 0x27ba, 0x27bb, 0x27bc, 0x27bd, 0x27be, 0xfffd,
};

static void *
NSCharConversionStorage(NSCharConversionBuffer *result, unsigned bytes,
                        NSZone *zone)
{
    if (bytes > NSConversionInlineBytes) {
        result->allocated = 1;
        return NSZoneMalloc(zone, bytes);
    }
    result->allocated = 0;
    return result->inlineStorage;
}

static unsigned
NSCharConversionHexValue(unsigned char byte)
{
    if (byte >= '0' && byte <= '9')
        return byte - '0';
    if (byte >= 'A' && byte <= 'F')
        return byte - 'A' + 10;
    return byte - '7';
}

int
NSUTF8ToUnicode(unsigned char **cursor, unsigned remaining, unichar *output)
{
    static const unsigned offsetsFromUTF8[6] = {
        0, 0x00003080, 0x000e2080, 0x03c82080, 0xfa082080, 0x82082080
    };
    unsigned char *bytes = *cursor;
    unsigned char first = bytes[0];
    unsigned continuationBytes;
    unsigned index;
    unsigned codePoint;

    if (first < 0xc0)
        continuationBytes = 0;
    else if (first < 0xe0)
        continuationBytes = 1;
    else if (first < 0xf0)
        continuationBytes = 2;
    else if (first < 0xf8)
        continuationBytes = 3;
    else if (first < 0xfc)
        continuationBytes = 4;
    else
        continuationBytes = 5;

    if (remaining <= continuationBytes)
        return 0;
    codePoint = first;
    for (index = 0; index < continuationBytes; ++index)
        codePoint = (codePoint << 6) + bytes[index + 1];
    codePoint -= offsetsFromUTF8[continuationBytes];
    *cursor += continuationBytes + 1;

    if (codePoint <= 0xffff) {
        output[0] = (unichar)codePoint;
        return 1;
    }
    if (codePoint <= 0x10ffff) {
        codePoint -= 0x10000;
        output[0] = (unichar)((codePoint >> 10) + 0xd800);
        output[1] = (unichar)((codePoint & 0x3ff) + 0xdc00);
        return 2;
    }
    output[0] = 0xfffd;
    return 1;
}

static unichar
NSCharConversionDecodeByte(NSStringEncoding encoding, unsigned char byte)
{
    static const unichar CP1252Controls[32] = {
#if defined(__ppc__) || defined(__POWERPC__)
        0x20ac,
#else
        0xfffd,
#endif
        0xfffd, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
        0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0xfffd, 0xfffd, 0xfffd,
        0xfffd, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
        0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0xfffd, 0xfffd, 0x0178
    };

    if ((byte <= 0x7f && encoding != NSSymbolStringEncoding) ||
        encoding == NSASCIIStringEncoding || encoding == NSISOLatin1StringEncoding)
        return byte;
    switch (encoding) {
    case NSNEXTSTEPStringEncoding:
        return NSNEXTSTEPToUnicodeTable[byte - 0x80];
    case NSISOLatin2StringEncoding:
        if (byte <= 0x9f)
            return byte;
        return NSISOLatin2ToUnicodeTable[byte - 0xa0];
    case NSSymbolStringEncoding:
        return NSSymbolToUnicodeTable[byte];
    case NSWindowsCP1251StringEncoding:
        return NSCyrillicToUnicodeTable[byte - 0x80];
    case NSWindowsCP1252StringEncoding:
        return byte < 0xa0 ? CP1252Controls[byte - 0x80] : byte;
    case NSWindowsCP1253StringEncoding:
        return NSCP1253ToUnicodeTable[byte - 0x80];
    case NSWindowsCP1254StringEncoding:
        return NSCP1254ToUnicodeTable[byte - 0x80];
    case NSWindowsCP1250StringEncoding:
        return NSCP1250ToUnicodeTable[byte - 0x80];
    case NSMacOSRomanStringEncoding:
        return _NSCStringCharToUnichar(byte);
    default:
        return byte;
    }
}

unichar NSASCIIToPrecompUnicode(unsigned char byte)
{
    return NSCharConversionDecodeByte(NSASCIIStringEncoding, byte);
}

unichar NSAdobeStandardToPrecompUnicode(unsigned char byte)
{
    if (byte <= 0x9f)
        return byte;
    return NSAdobeStandardToUnicodeTable[byte - 0xa0];
}

unichar NSAdobeStandardCyrillicToUnicode(unsigned char byte)
{
    return NSCharConversionDecodeByte(NSWindowsCP1251StringEncoding, byte);
}

unichar NSISOLatin1ToPrecompUnicode(unsigned char byte)
{
    return NSCharConversionDecodeByte(NSISOLatin1StringEncoding, byte);
}

unichar NSISOLatin2ToPrecompUnicode(unsigned char byte)
{
    if (byte <= 0x9f)
        return byte;
    return NSISOLatin2ToUnicodeTable[byte - 0xa0];
}

typedef struct {
    const char *sequence;
    unsigned length;
    unsigned mode;
} NSISO2022JPSequence;

static const NSISO2022JPSequence NSISO2022JPSequences[8] = {
    {"(B", 2, 0}, {"(H", 2, 0}, {"(I", 2, 1}, {"(J", 2, 0},
    {")I", 2, 1}, {"$@", 2, 2}, {"$B", 2, 2}, {"$D", 2, 2}
};

unichar NSNEXTSTEPToPrecompUnicode(unsigned char byte)
{
    return NSCharConversionDecodeByte(NSNEXTSTEPStringEncoding, byte);
}

unichar NSSymbolToPrecompUnicode(unsigned char byte)
{
    return NSCharConversionDecodeByte(NSSymbolStringEncoding, byte);
}

unichar NSZapfDingbatToPrecompUnicode(unsigned char byte)
{
    return NSZapfDingbatToUnicodeTable[byte];
}

unichar NSWinCodePage1250ToUnicode(unsigned char byte)
{
    return NSCharConversionDecodeByte(NSWindowsCP1250StringEncoding, byte);
}

unichar NSWinCodePage1253ToUnicode(unsigned char byte)
{
    return NSCharConversionDecodeByte(NSWindowsCP1253StringEncoding, byte);
}

unichar NSWinCodePage1254ToUnicode(unsigned char byte)
{
    return NSCharConversionDecodeByte(NSWindowsCP1254StringEncoding, byte);
}

unichar NSWinLatin1ToUnicode(unsigned char byte)
{
    return NSCharConversionDecodeByte(NSWindowsCP1252StringEncoding, byte);
}

int
_NSConvertToASCIIorUnicode2(const void *bytes, unsigned size,
                            NSStringEncoding encoding, BOOL flag,
                            void *buffer, NSZone *zone)
{
    NSCharConversionBuffer *result = (NSCharConversionBuffer *)buffer;
    const unsigned char *source = (const unsigned char *)bytes;
    unsigned index;

    result->isCString = flag == NO;
    result->allocated = 0;
    result->cstring = 0;
    result->characters = 0;
    result->length = 0;
    if (size == 0)
        return 1;

    if (encoding == NSUnicodeStringEncoding || encoding == 0) {
        unsigned characterCount = size >> 1;
        unsigned sourceOffset = 0;
        int littleEndian = 0;
        unichar firstWord;
        unichar *characters;

        firstWord = *(const unichar *)source;
        if (firstWord == 0xfffe || firstWord == 0xfeff) {
#if defined(__ppc__) || defined(__POWERPC__)
            littleEndian = firstWord == 0xfffe;
#else
            littleEndian = firstWord == 0xfeff;
#endif
            sourceOffset = 2;
            --characterCount;
        }
        result->isCString = 0;
        result->length = characterCount;
        characters = (unichar *)NSCharConversionStorage(
            result, characterCount * sizeof(unichar), zone);
        result->characters = characters;
        if (littleEndian) {
#if defined(__ppc__) || defined(__POWERPC__)
            const unsigned char *input = source + sourceOffset;
            for (index = 0; index < characterCount; ++index)
                characters[index] = ((unichar)input[index * 2 + 1] << 8)
                    | input[index * 2];
#else
            memmove(characters, source + sourceOffset,
                    characterCount * sizeof(unichar));
#endif
        } else {
            const unsigned char *input = source + sourceOffset;
            for (index = 0; index < characterCount; ++index)
                characters[index] = ((unichar)input[index * 2] << 8)
                    | input[index * 2 + 1];
        }
        return 1;
    }

    if (encoding == NSNonLossyASCIIStringEncoding) {
        unsigned char *input = (unsigned char *)source;
        unichar *characters;

        result->isCString = 0;
        characters = (unichar *)NSCharConversionStorage(
            result, size * sizeof(unichar), zone);
        result->characters = characters;
        for (index = 0; index < size; ++index) {
            unsigned value = input[index];
            if (input[index] == '\\') {
                unsigned char escaped = input[++index];
                if (escaped == 'U') {
                    value = (NSCharConversionHexValue(input[index + 1]) << 12)
                        | (NSCharConversionHexValue(input[index + 2]) << 8)
                        | (NSCharConversionHexValue(input[index + 3]) << 4)
                        | NSCharConversionHexValue(input[index + 4]);
                    index += 4;
                } else if (escaped != '\\') {
                    value = ((escaped - '0') << 6)
                        | ((input[index + 1] - '0') << 3)
                        | (input[index + 2] - '0');
                    index += 2;
                } else {
                    value = escaped;
                }
            }
            characters[result->length++] = (unichar)value;
        }
        return 1;
    }

    if (encoding == NSASCIIStringEncoding ||
        encoding == NSNEXTSTEPStringEncoding ||
        encoding == NSISOLatin1StringEncoding ||
        encoding == NSISOLatin2StringEncoding ||
        encoding == NSWindowsCP1251StringEncoding ||
        encoding == NSWindowsCP1252StringEncoding ||
        encoding == NSWindowsCP1253StringEncoding ||
        encoding == NSWindowsCP1254StringEncoding ||
        encoding == NSWindowsCP1250StringEncoding ||
        encoding == NSMacOSRomanStringEncoding) {
        int ascii = flag == NO;

        for (index = 0; ascii && index < size; ++index) {
            if (source[index] > 0x7f)
                ascii = 0;
        }
        result->isCString = ascii;
        result->length = size;
        if (ascii) {
            char *cstring = (char *)NSCharConversionStorage(result, size, zone);
            result->cstring = cstring;
            memmove(cstring, source, size);
        } else {
            unichar *characters = (unichar *)NSCharConversionStorage(
                result, size * sizeof(unichar), zone);
            result->characters = characters;
            for (index = 0; index < size; ++index) {
                characters[index] = NSCharConversionDecodeByte(
                    encoding, source[index]);
            }
        }
        return 1;
    }

    if (encoding == NSSymbolStringEncoding) {
        unichar *characters = (unichar *)NSCharConversionStorage(
            result, size * sizeof(unichar), zone);
        result->isCString = 0;
        result->characters = characters;
        result->length = size;
        for (index = 0; index < size; ++index)
            characters[index] = NSCharConversionDecodeByte(
                encoding, source[index]);
        return 1;
    }

    if (encoding == NSISO2022JPStringEncoding) {
        unichar *characters;
        unsigned mode = 0;
        unsigned input = 0;

        result->isCString = 0;
        characters = (unichar *)NSCharConversionStorage(
            result, size * 6 * sizeof(unichar), zone);
        result->characters = characters;
        while (input < size) {
            if (source[input] == 0x1b) {
                unsigned sequence;

                if (size - input <= 2)
                    return 1;
                for (sequence = 0; sequence < 8; ++sequence) {
                    const NSISO2022JPSequence *entry =
                        &NSISO2022JPSequences[sequence];
                    if (memcmp(source + input + 1, entry->sequence,
                               entry->length) == 0) {
                        mode = entry->mode;
                        input += entry->length + 1;
                        break;
                    }
                }
                if (sequence < 8)
                    continue;
            }
            if (mode == 1) {
                unsigned char kana[2] = { 0x8e,
                    (unsigned char)(source[input] | 0x80) };
                unsigned char *cursor = kana;
                result->length += NSNextEUCToUnicode(
                    &cursor, 2, result->characters + result->length);
            } else if (mode == 2) {
                unsigned char jis[2];
                unsigned char *cursor = jis;

                if (size - input <= 1)
                    break;
                jis[0] = (unsigned char)(source[input] | 0x80);
                jis[1] = (unsigned char)(source[input + 1] | 0x80);
                result->length += NSNextEUCToUnicode(
                    &cursor, 2, result->characters + result->length);
                ++input;
            } else {
                result->characters[result->length++] = source[input];
            }
            ++input;
        }
        return 1;
    }

    if (encoding == NSUTF8StringEncoding) {
        unsigned char *cursor = (unsigned char *)source;
        int ascii = flag == NO;
        int (*decoder)(unsigned char **, unsigned, unichar *) = NSUTF8ToUnicode;

        for (index = 0; ascii && index < size; ++index) {
            if (source[index] > 0x7f)
                ascii = 0;
        }
        result->isCString = ascii;
        result->length = size;
        if (ascii) {
            char *cstring = (char *)NSCharConversionStorage(result, size, zone);
            result->cstring = cstring;
            memmove(cstring, source, size);
            return 1;
        }

        result->characters = (unichar *)NSCharConversionStorage(
            result, size * sizeof(unichar), zone);
        result->length = 0;
        while ((unsigned)(cursor - source) < size) {
            int converted = decoder(&cursor,
                size - (unsigned)(cursor - source),
                result->characters + result->length);
            if (converted == 0)
                goto conversionFailed;
            result->length += converted;
        }
        return 1;
    }

    if (encoding == NSJapaneseEUCStringEncoding ||
        encoding == NSShiftJISStringEncoding ||
        encoding == NSProprietaryStringEncoding) {
        unsigned char *cursor = (unsigned char *)source;
        int ascii = flag == NO;
        int (*decoder)(unsigned char **, unsigned, unichar *);

        if (encoding == NSJapaneseEUCStringEncoding)
            decoder = NSNextEUCToUnicode;
        else if (encoding == NSShiftJISStringEncoding)
            decoder = NSShiftJISToUnicode;
        else
            decoder = _NSProprietaryEncodingToUnicode;

        for (index = 0; ascii && index < size; ++index) {
            if (source[index] > 0x7f)
                ascii = 0;
        }
        result->isCString = ascii;
        result->length = size;
        if (ascii) {
            char *cstring = (char *)NSCharConversionStorage(result, size, zone);
            result->cstring = cstring;
            memmove(cstring, source, size);
            return 1;
        }

        result->characters = (unichar *)NSCharConversionStorage(
            result, size * sizeof(unichar), zone);
        result->length = 0;
        while ((unsigned)(cursor - source) < size) {
            int converted = decoder(&cursor,
                size - (unsigned)(cursor - source),
                result->characters + result->length);
            if (converted == 0)
                goto conversionFailed;
            result->length += converted;
        }
        return 1;
    }

conversionFailed:
    if (result->allocated)
        NSZoneFree(zone, result->characters);
    result->isCString = flag == NO;
    result->allocated = 0;
    result->cstring = 0;
    result->characters = 0;
    result->length = 0;
    return 0;
}

int
_NSConvertToASCIIorUnicode(const void *bytes, unsigned size,
                           NSStringEncoding encoding, void **output,
                           unsigned *length, unsigned char *isCString,
                           NSZone *zone)
{
    NSCharConversionBuffer converted;
    void *result;
    unsigned resultSize;

    if (!_NSConvertToASCIIorUnicode2(bytes, size, encoding, NO,
                                     &converted, zone))
        return 0;

    result = converted.isCString ? (void *)converted.cstring
                                 : (void *)converted.characters;
    if (!converted.allocated && result != NULL) {
        resultSize = converted.length;
        if (!converted.isCString)
            resultSize *= sizeof(unichar);
        result = NSZoneMalloc(zone, resultSize);
        memmove(result, converted.isCString ? (void *)converted.cstring
                                            : (void *)converted.characters,
                resultSize);
    }

    *output = result;
    *length = converted.length;
    *isCString = converted.isCString;
    return 1;
}
