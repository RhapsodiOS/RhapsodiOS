/*
 * RivaFBUtility.m -- Utility methods
 * NOTE: This is a stub implementation
 */

#import "RivaFB.h"
#include <stdio.h>

@implementation RivaFB (Utility)

- (void) logInfo
{
    RivaLog("RivaFB: Chip Type: %d\n", rivaHW.chipType);
    RivaLog("RivaFB: FB Size: %d MB\n", rivaHW.fbSize / (1024 * 1024));
}

- (BOOL) setPixelEncoding: (IOPixelEncoding) pixelEncoding
             bitsPerPixel: (int) bitsPerPixel
                  redMask: (int) redMask
                greenMask: (int) greenMask
                 blueMask: (int) blueMask
{
    int i;
    int mask;
    char *encoding = (char *)pixelEncoding;

    /* Clear encoding string */
    for (i = 0; i < IO_MaxPixelBits; i++) {
        encoding[i] = '-';
    }
    encoding[IO_MaxPixelBits] = '\0';

    /* Set red bits */
    mask = redMask;
    for (i = 0; i < 32 && mask; i++) {
        if (mask & (1 << i)) {
            encoding[31 - i] = 'R';
        }
    }

    /* Set green bits */
    mask = greenMask;
    for (i = 0; i < 32 && mask; i++) {
        if (mask & (1 << i)) {
            encoding[31 - i] = 'G';
        }
    }

    /* Set blue bits */
    mask = blueMask;
    for (i = 0; i < 32 && mask; i++) {
        if (mask & (1 << i)) {
            encoding[31 - i] = 'B';
        }
    }

    return YES;
}

@end
