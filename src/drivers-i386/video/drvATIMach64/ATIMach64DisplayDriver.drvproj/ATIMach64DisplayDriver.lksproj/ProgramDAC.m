#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#import "ATIPrivate.h"
#import "ATIData.h"
#import <driverkit/i386/ioPorts.h>
#import <driverkit/generalFuncs.h>

#if defined(ATI_DAC_TEST)
extern unsigned char ATI_mockInb(unsigned short port);
extern void ATI_mockOutb(unsigned short port, unsigned char value);
#define ATI_INB(port) ATI_mockInb(port)
#define ATI_OUTB(port, value) ATI_mockOutb((port), (value))
#else
#define ATI_INB(port) inb(port)
#define ATI_OUTB(port, value) outb((port), (value))
#endif

int isATI68880RevC(void)
{
    unsigned char control = ATI_INB(0x62ec);
    ATI_OUTB(0x62ec, control | 3);
    return ATI_INB(0x5eef) == 0xd0;
}

unsigned int SetGammaValue(int red, int green, int blue, int brightness)
{
    unsigned int result;

    ATI_OUTB(0x5eed, (unsigned char)((unsigned int)(brightness * red) >> 6));
    ATI_OUTB(0x5eed, (unsigned char)((unsigned int)(brightness * green) >> 6));
    result = (unsigned int)(brightness * blue) >> 6;
    ATI_OUTB(0x5eed, (unsigned char)result);
    return result;
}

@implementation ATI (ProgramDAC)

- (id)setGammaTable
{
    unsigned int index;
    unsigned int repeat;
    unsigned int bitsPerPixel;
    unsigned char control;

    control = ATI_INB(0x62ec);
    ATI_OUTB(0x62ec, control & 0xfc);
    ATI_OUTB(0x5eec, 0);
    if (redTransferTable != nil) {
        for (index = 0; index < (unsigned int)transferTableCount; ++index) {
            for (repeat = 0; repeat < 256 / transferTableCount; ++repeat) {
                SetGammaValue(((unsigned char *)redTransferTable)[index],
                              ((unsigned char *)greenTransferTable)[index],
                              ((unsigned char *)blueTransferTable)[index],
                              brightnessLevel);
            }
        }
    } else {
        bitsPerPixel = [self displayInfo]->bitsPerPixel;
        if (bitsPerPixel == IO_8BitsPerPixel) {
            for (index = 0; index <= 0xff; ++index)
                SetGammaValue(gamma8[index], gamma8[index], gamma8[index],
                              brightnessLevel);
        } else if (bitsPerPixel >= IO_15BitsPerPixel &&
                   bitsPerPixel <= IO_24BitsPerPixel) {
            for (index = 0; index <= 0x1f; ++index) {
                for (repeat = 0; repeat <= 7; ++repeat) {
                    unsigned char value = gamma16[index >> 1];
                    SetGammaValue(value, value, value, brightnessLevel);
                }
            }
        }
    }
    return self;
}

- (id)setBrightness:(int)level token:(int)token
{
    if ((unsigned int)level > 0x40) {
        IOLog("Display: Invalid arg to setBrightness: %d\n", level);
        return nil;
    }
    brightnessLevel = level;
    [self setGammaTable];
    return self;
}

- (id)setTransferTable:(const unsigned int *)table count:(int)count
{
    unsigned char asicType = ((unsigned char *)queryData)[9];
    unsigned char dacType = ((unsigned char *)queryData)[12];
    unsigned int shift = supportsGrey256 != 0 ? 0 : 2;
    int index;
    unsigned int pixelType;
    unsigned int colorSpace;

    if (asicType != 67 && asicType != 69 &&
        (dacType == 5 || dacType == 2 ||
         (dacType == 21 && isATI68880RevC())))
        shift = 0;
    if (ramdacStyle == 1)
        shift = 0;
    else if (ramdacStyle == 2)
        shift = 2;

    if (redTransferTable != nil)
        IOFree(redTransferTable, 3 * transferTableCount);
    transferTableCount = count;
    redTransferTable = IOMalloc(3 * count);
    greenTransferTable = (unsigned int *)((char *)redTransferTable + count);
    blueTransferTable = (unsigned int *)((char *)greenTransferTable + count);

    pixelType = [self displayInfo]->bitsPerPixel;
    colorSpace = [self displayInfo]->colorSpace;
    if (pixelType == IO_8BitsPerPixel && colorSpace == IO_OneIsWhiteColorSpace) {
        for (index = 0; count > index; ++index) {
            unsigned int component = ((const unsigned char *)table)[index * 4] >> shift;
            ((unsigned char *)redTransferTable)[index] = component;
            ((unsigned char *)greenTransferTable)[index] = component;
            ((unsigned char *)blueTransferTable)[index] = component;
        }
    } else if (colorSpace == IO_RGBColorSpace &&
               (pixelType == IO_8BitsPerPixel ||
                (pixelType >= IO_15BitsPerPixel &&
                 pixelType <= IO_24BitsPerPixel))) {
        for (index = 0; count > index; ++index) {
            const unsigned char *components = (const unsigned char *)&table[index];
            ((unsigned char *)redTransferTable)[index] = components[3] >> shift;
            ((unsigned char *)greenTransferTable)[index] = components[2] >> shift;
            ((unsigned char *)blueTransferTable)[index] = components[1] >> shift;
        }
    } else {
        IOFree(redTransferTable, 3 * count);
        redTransferTable = nil;
    }
    [self setGammaTable];
    return self;
}

@end
