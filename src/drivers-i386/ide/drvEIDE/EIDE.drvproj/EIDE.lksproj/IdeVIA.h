/*
 * IdeVIA.h - VIA VT82C5xx/686A chipset back-end.
 */
#ifndef _IDE_VIA_H_
#define _IDE_VIA_H_

#import "IdeBMIDE.h"
#import "VIATiming.h"

extern const ideChipsetOps_t ideVIAOps;

@interface IdeController(VIA)
- (BOOL) VIASetTiming:(void *)drives;
- (BOOL) VIAResetTiming;
- (BOOL) VIADetectCable;
@end

#endif /* _IDE_VIA_H_ */
