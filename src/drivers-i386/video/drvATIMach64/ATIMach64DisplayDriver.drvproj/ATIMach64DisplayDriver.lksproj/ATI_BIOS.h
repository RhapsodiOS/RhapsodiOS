#ifndef __ATI_BIOS_H__
#define __ATI_BIOS_H__

#import <objc/Object.h>
#import "ATIBIOSTypes.h"

typedef struct { unsigned char bytes[30]; } ATI_CRTCRecord;

@interface ATI_BIOS : Object
{
@private
    char initialized;
    unsigned int segmentBase;
    void *_priv;
}
+ (char)ATIPresent:(unsigned int *)segmentAddress;
- init;
- initAtSegmentAddress:(unsigned int)segmentAddress;
- free;
- (int)loadCRTC:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitchSize resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)crtTable;
- (int)setVGAMode:(char)mode gamma:(char)gamma;
- (int)loadCRTCSetMode:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitchSize resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)crtTable;
- (int)setApertureEnable:(char)enabled VGAAperture:(char)vgaAperture apertureAdrs:(unsigned int)address;
- (int)shortQuery:(unsigned int *)query hardCoded:(char *)hardCoded smallAperture:(char *)smallAperture address:(unsigned int *)address colorDepth:(unsigned int *)colorDepth memorySize:(unsigned int *)memorySize asicType:(char *)asicType asicRev:(char *)asicRevision;
- (int)querySize:(char)query size:(unsigned int *)size;
- (int)deviceQuery:(char)query bufferSize:(unsigned int)bufferSize buffer:(void *)buffer;
- (int)setDPMSMode:(unsigned int)mode;
- (int)getDPMSMode:(unsigned int *)mode;
- (int)setAPMState:(unsigned int)state;
- (int)getAPMState:(unsigned int *)state;
- (int)getIOBaseAddress:(unsigned int *)address relocatable:(char *)relocatable;
- (int)getRefreshRate:(char *)refreshRate;
- (int)changeRefreshRate:(char *)refreshRate;
- (int)initBIOSBuf:(ATIBIOSRegisters *)registers function:(char)function;
- (void)setupCodeSegments;
- (void)restoreCodeSegments;
- (int)createDataSegment:(unsigned int)address size:(unsigned int)size;
- (void)restoreDataSegment;
- (int)doBios:(void *)registers dataSeg:(char)dataSegment;
- (int)loadCRTC_comm:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitchSize resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)crtTable function:(unsigned char)function name:(const char *)name;
@end

ATI_STATIC_ASSERT(__builtin_offsetof(ATI_BIOS, initialized) == 4, ATI_BIOS_initialized_offset);
ATI_STATIC_ASSERT(__builtin_offsetof(ATI_BIOS, segmentBase) == 8, ATI_BIOS_segmentBase_offset);
ATI_STATIC_ASSERT(__builtin_offsetof(ATI_BIOS, _priv) == 12, ATI_BIOS_private_offset);

#endif
