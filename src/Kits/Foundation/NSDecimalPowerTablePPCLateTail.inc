/* IDA- and image-derived _pow10 rows for PPC reduced indices 26364-26768. */
static const unsigned char NSDecimalPPCLateZeroCounts[51] = {
    0x11, 0x11, 0x01, 0x00, 0x11, 0x11, 0x11, 0x11, 0x00, 0x11,
    0x11, 0x11, 0x11, 0x01, 0xf1, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0x1f
};

static const NSDecimalOutOfTableDivisorRecord NSDecimalPPCLateDivisors[] = {
    {26366, 1, 0}, {26370, 1, 1}, {26374, 1, 2}, {26378, 1, 3},
    {26382, 1, 4}, {26384, 1, 5}, {26386, 2, 6}, {26388, 1, 8},
    {26390, 2, 9}, {26392, 1, 11}, {26394, 1, 12}, {26398, 2, 13},
    {26402, 2, 15}, {26406, 1, 17}, {26410, 1, 18}, {26414, 1, 19},
    {26418, 1, 20}, {26422, 1, 21}, {26426, 1, 22}, {26428, 1, 23},
    {26430, 2, 24}, {26432, 1, 26}, {26434, 1, 27}, {26438, 2, 28},
    {26442, 1, 30}, {26446, 1, 31}, {26450, 1, 32}, {26454, 1, 33},
    {26458, 1, 34}, {26462, 1, 35}, {26466, 1, 36}, {26470, 1, 37},
    {26472, 1, 38}, {26474, 2, 39}, {26478, 1, 41}
};

static const unsigned NSDecimalPPCLateDivisorsCount =
    sizeof(NSDecimalPPCLateDivisors) / sizeof(NSDecimalPPCLateDivisors[0]);

/*  Mapped length words whose divisor payloads extend beyond the image.  */
static const NSDecimalOutOfTableDivisorRecord
NSDecimalPPCLateCountOnlyDivisors[] = {
    {26441, 56252, 0}, {26443, 46452, 0}, {26445, 24424, 0},
    {26447, 10252, 0}, {26449, 21284, 0}, {26451, 35180, 0},
    {26453, 52376, 0}, {26455, 56284, 0}, {26457, 1604, 0},
    {26459, 39016, 0}, {26461, 22336, 0}, {26463, 56012, 0},
    {26465, 10436, 0}, {26467, 4696, 0}, {26469, 49272, 0},
    {26471, 32048, 0}, {26473, 11288, 0}, {26475, 33768, 0},
    {26477, 41968, 0}, {26479, 33768, 0}
};

static const unsigned NSDecimalPPCLateCountOnlyDivisorsCount =
    sizeof(NSDecimalPPCLateCountOnlyDivisors) /
    sizeof(NSDecimalPPCLateCountOnlyDivisors[0]);

static const unsigned short NSDecimalPPCLateDivisorWords[42] = {
    52116, 45740, 56672, 42556, 61564, 1900, 2104, 0,
    304, 7448, 1, 11888, 42700, 9612, 0, 7352,
    0, 49536, 37588, 50304, 55528, 36888, 58392, 12168,
    8724, 1, 14500, 63920, 4264, 0,
    46452, 49328, 30928, 47680, 39016, 41364, 56012, 32072,
    8744, 2304, 0, 33768
};
