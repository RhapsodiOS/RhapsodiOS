/*
 * VBE20DisplayDriver.h - VESA 2.0 display driver.
 */

#import <driverkit/IOFrameBufferDisplay.h>
#import <driverkit/displayDefs.h>

/*
 * One VBE mode as the booter hands it over: a distilled form of the
 * 256-byte VBEModeInfoBlock in boot-2's libsaio/vbe.h.  22 bytes of
 * fields, 24 with the two bytes of alignment padding at 0x12 that the
 * pointer forces.  The types and their order are the reference's type
 * encoding {?=SSSSSCCCCCCCC^v}; the names and the offset each one lands
 * at come from descriptionForVBEMode:'s format string and the order it
 * pushes the fields in.
 */
typedef struct {
    unsigned short	modeNumber;		/* 0x00 */
    unsigned short	modeAttributes;		/* 0x02 */
    unsigned short	xResolution;		/* 0x04 */
    unsigned short	yResolution;		/* 0x06 */
    unsigned short	bytesPerScanline;	/* 0x08 */
    unsigned char	bitsPerPixel;		/* 0x0A */
    unsigned char	memoryModel;		/* 0x0B */
    unsigned char	redMaskSize;		/* 0x0C */
    unsigned char	redFieldPosition;	/* 0x0D */
    unsigned char	greenMaskSize;		/* 0x0E */
    unsigned char	greenFieldPosition;	/* 0x0F */
    unsigned char	blueMaskSize;		/* 0x10 */
    unsigned char	blueFieldPosition;	/* 0x11 */
    void		*frameBuffer;		/* 0x14 */
} VBEModeRec;

@interface VBE20DisplayDriver : IOFrameBufferDisplay
{
    /*
     * No instance variables.  The reference's __OBJC,__instance_vars is
     * zero bytes and its instance_size of 552 is entirely inherited.
     */
}

- (id)initFromDeviceDescription:(IODeviceDescription *)devDesc;
- (void)parseVESAModes:(VBEModeRec *)modes size:(unsigned int)size;
- (void)initDisplayInfo:(IODisplayInfo *)info fromVBEModeInfo:(VBEModeRec *)mode;
- (char *)modeStringForDisplayInfo:(IODisplayInfo *)info;
- (unsigned int)atoi:(const char *)s;
- (char *)descriptionForDisplayInfo:(IODisplayInfo *)info;
- (char *)descriptionForVBEMode:(VBEModeRec *)mode;

@end

@interface IOFrameBufferDisplay (UnnamedInitialization)
- (id)initUnnamedFromDeviceDescription:(IODeviceDescription *)devDesc;
@end
