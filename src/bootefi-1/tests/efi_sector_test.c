/* Host test for the UEFI loader's 512-byte-sector to media-block
 * arithmetic.  Pure C: no firmware, no boot-2 headers. */
#include <stdio.h>

#include "efi_sector.h"

static int failures;

static void check(const char *name, unsigned long long got,
                  unsigned long long want)
{
    if (got != want) {
        printf("FAIL %s: got %llu want %llu\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

static void span(const char *name, UINT32 block_size, UINT64 secno,
                 UINT32 nsecs, UINT64 want_first, UINT32 want_nblocks,
                 UINT32 want_skip)
{
    UINT64 first = ~0ULL;
    UINT32 nblocks = ~0U, skip = ~0U;
    char buf[128];

    efi_sector_span(block_size, secno, nsecs, &first, &nblocks, &skip);
    sprintf(buf, "%s: first block", name);
    check(buf, first, want_first);
    sprintf(buf, "%s: blocks", name);
    check(buf, nblocks, want_nblocks);
    sprintf(buf, "%s: skip bytes", name);
    check(buf, skip, want_skip);
}

static void test_512_byte_media_unchanged(void)
{
    span("512, sector 0", 512, 0, 1, 0, 1, 0);
    span("512, sector 37 x 18", 512, 37, 18, 37, 18, 0);
}

static void test_aligned_2048(void)
{
    span("2048, sector 8 x 4", 2048, 8, 4, 2, 1, 0);
    span("2048, sector 0 x 16", 2048, 0, 16, 0, 4, 0);
}

static void test_read_spans_blocks_unaligned(void)
{
    span("2048, sector 5 x 3", 2048, 5, 3, 1, 1, 512);
    span("2048, sector 3 x 2", 2048, 3, 2, 0, 2, 1536);
    /* disk.c's largest request: 18 sectors (BIOS_LEN / 512), worst start */
    span("2048, sector 3 x 18", 2048, 3, 18, 0, 6, 1536);
}

static void test_cd_label_sector(void)
{
    check("512: label sector", efi_cd_label_sector(512), 15);
    check("2048: label sector", efi_cd_label_sector(2048), 15);
    span("2048, label", 2048, efi_cd_label_sector(2048), 1, 3, 1, 1536);
}

int main(void)
{
    test_512_byte_media_unchanged();
    test_aligned_2048();
    test_read_spans_blocks_unaligned();
    test_cd_label_sector();
    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
