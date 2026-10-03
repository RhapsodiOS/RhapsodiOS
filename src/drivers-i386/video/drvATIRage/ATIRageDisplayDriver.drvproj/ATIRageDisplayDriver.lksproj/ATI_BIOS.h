#ifndef __ATI_BIOS_H__
#define __ATI_BIOS_H__

#import <driverkit/IODevice.h>
#import <driverkit/displayDefs.h>
#import <objc/Object.h>

typedef struct {
    unsigned char byte_00;
    unsigned char byte_01;
    unsigned char byte_02;
    unsigned char byte_03;
    unsigned short word_04;
    unsigned char byte_06;
    unsigned char byte_07;
    unsigned char byte_08;
    unsigned char byte_09;
    unsigned short word_0a;
    unsigned short word_0c;
    unsigned short word_0e;
    unsigned char byte_10;
    unsigned char byte_11;
    unsigned short word_12;
    unsigned short word_14;
    unsigned char byte_16;
    unsigned char byte_17;
    unsigned char byte_18;
    unsigned char byte_19;
    unsigned char byte_1a;
    unsigned char byte_1b;
    unsigned short word_1c;
} ATI_CRTCRecord;

/* The seven register unions intentionally match the reference encoding
 * (IS{?=CC}); the word/byte views share their dword storage. */
#define ATI_BIOS_REGISTER(name) \
    union { \
        unsigned int dword; \
        unsigned short word; \
        struct { unsigned char low, high; } bytes; \
    } name

typedef struct {
    unsigned int reserved_00;
    ATI_BIOS_REGISTER(eax);
    ATI_BIOS_REGISTER(ebx);
    ATI_BIOS_REGISTER(ecx);
    ATI_BIOS_REGISTER(edx);
    ATI_BIOS_REGISTER(edi);
    ATI_BIOS_REGISTER(esi);
    ATI_BIOS_REGISTER(ebp);
    unsigned short code_selector;
    unsigned short data_selector;
    unsigned short output_es;
    unsigned long output_ds;
    unsigned long entry_offset;
} ATI_BIOSRegisters;
#undef ATI_BIOS_REGISTER

typedef struct {
    unsigned char saved_code_descriptor0[8];
    unsigned char saved_code_descriptor1[8];
    unsigned char saved_data_descriptor[8];
    unsigned char saved_stack_descriptor[8];
    unsigned int stack_address;
} ATI_BIOSPrivate;

typedef char _ATI_CRTCRecord_must_be_30_bytes[(sizeof(ATI_CRTCRecord) == 30) ? 1 : -1];
typedef char _ATI_BIOSPrivate_must_be_36_bytes[(sizeof(ATI_BIOSPrivate) == 36) ? 1 : -1];

@interface ATI_BIOS : Object
{
@private
    char initialized;
    unsigned int segmentBase;
    ATI_BIOSPrivate *_priv;
}

+ (char)ATIPresent:(unsigned int *)biosBase;
- init;
- initAtSegmentAddress:(unsigned int)segmentAddress;
- free;
- (int)loadCRTC:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitch
    resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)crtTable;
- (int)setVGAMode:(char)mode gamma:(char)gamma;
- (int)loadCRTCSetMode:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitch
    resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)crtTable;
- (int)setApertureEnable:(char)enable VGAAperture:(char)vgaAperture apertureAdrs:(unsigned int)address;
- (int)shortQuery:(unsigned int *)hardCoded hardCoded:(char *)smallAperture
    smallAperture:(char *)address address:(unsigned int *)colorDepth
    colorDepth:(unsigned int *)memorySize memorySize:(unsigned int *)asicType
    asicType:(char *)asicRev asicRev:(char *)name;
- (int)querySize:(char)query size:(unsigned int *)size;
- (int)deviceQuery:(char)query bufferSize:(unsigned int)size buffer:(void *)buffer;
- (int)setDPMSMode:(unsigned int)mode;
- (int)getDPMSMode:(unsigned int *)mode;
- (int)setAPMState:(unsigned int)state;
- (int)getAPMState:(unsigned int *)state;
- (int)getIOBaseAddress:(unsigned long *)address relocatable:(char *)relocatable;
- (int)getRefreshRate:(char *)refreshRate;
- (int)changeRefreshRate:(char *)refreshRate;
@end

@interface ATI_BIOS (Private)
- (void)initBIOSBuf:(ATI_BIOSRegisters *)registers function:(unsigned int)function;
- (void)setupCodeSegments;
- (void)restoreCodeSegments;
- (int)createDataSegment:(unsigned int)address size:(unsigned int)size;
- (void)restoreDataSegment;
- (int)doBios:(ATI_BIOSRegisters *)registers dataSeg:(char)dataSegment;
- (int)loadCRTC_comm:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitch
    resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)crtTable
    function:(unsigned char)function name:(const char *)name;
@end

#if defined(__i386__) || defined(i386)
typedef char _ATI_BIOSRegisters_must_be_48_bytes[(sizeof(ATI_BIOSRegisters) == 48) ? 1 : -1];
typedef char _ATI_BIOS_instance_must_be_16_bytes[(sizeof(ATI_BIOS) == 16) ? 1 : -1];
#endif

/* Assembly transfer symbols use the 32-bit cdecl ABI in the i386 image. */
extern int ATIbios16(ATI_BIOSRegisters *registers, unsigned int function);
extern void _ATIbios32(void);
extern unsigned int ATI_Bios_Offset;
extern unsigned int ATI_Bios_Selector;
extern unsigned int ATI_Bios_StackOffset;
extern unsigned int ATI_Bios_StackSelector;
extern unsigned int kernDataSel;

#endif
