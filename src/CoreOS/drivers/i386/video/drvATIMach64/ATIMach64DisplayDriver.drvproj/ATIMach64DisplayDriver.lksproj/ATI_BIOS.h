#ifndef __ATI_BIOS_H__
#define __ATI_BIOS_H__

#import <objc/Object.h>
#import "ATIBIOSTypes.h"

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

#endif
