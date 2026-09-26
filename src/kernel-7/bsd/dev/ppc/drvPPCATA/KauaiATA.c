/*
 * KauaiATA.c - Kauai UltraATA/100 timing tables.
 */

#include "KauaiATA.h"

static const unsigned int kauai_pio[] = {
    0x08000a92,		/* PIO 0 */
    0x0800060f,		/* PIO 1 */
    0x0800038b,		/* PIO 2 */
    0x05000249,		/* PIO 3 */
    0x04000148		/* PIO 4 */
};

static const unsigned int kauai_mwdma[] = {
    0x00618000,		/* multiword DMA 0 */
    0x00209000,		/* multiword DMA 1 */
    0x00148000		/* multiword DMA 2 */
};

static const unsigned int kauai_ultra[] = {
    0x000070c1,		/* Ultra DMA 0 */
    0x00005d81,		/* Ultra DMA 1 */
    0x00004a61,		/* Ultra DMA 2 */
    0x00003a51,		/* Ultra DMA 3 */
    0x00002a31,		/* Ultra DMA 4 */
    0x00002921		/* Ultra DMA 5 */
};

#define KAUAI_COUNT(table)	(sizeof(table) / sizeof((table)[0]))

int
KauaiTimingWords(unsigned int pioMode, KauaiDMAType dmaType,
    unsigned int dmaMode, unsigned int *pioConfig, unsigned int *ultraConfig)
{
    unsigned int first;
    unsigned int second;

    if (pioConfig == 0 || ultraConfig == 0 ||
        pioMode >= KAUAI_COUNT(kauai_pio))
        return 0;
    first = kauai_pio[pioMode];
    second = 0;
    switch (dmaType) {
    case kKauaiDMANone:
        first |= kauai_mwdma[0];
        break;
    case kKauaiDMAMultiword:
        if (dmaMode >= KAUAI_COUNT(kauai_mwdma))
            return 0;
        first |= kauai_mwdma[dmaMode];
        break;
    case kKauaiDMAUltra:
        if (dmaMode >= KAUAI_COUNT(kauai_ultra))
            return 0;
        second = kauai_ultra[dmaMode];
        break;
    default:
        return 0;
    }
    *pioConfig = first;
    *ultraConfig = second;
    return 1;
}

unsigned int
KauaiMaxUltraMode(const char *cableType, unsigned int length)
{
    if (cableType != 0 && length >= 3 && cableType[0] == '8' &&
        cableType[1] == '0' && cableType[2] == '-')
        return KAUAI_MAX_ULTRA_MODE;
    return KAUAI_MAX_ULTRA_40_WIRE;
}
