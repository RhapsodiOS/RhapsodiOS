#ifndef _IDE_AMD_H_
#define _IDE_AMD_H_

#import "IdeBMIDE.h"
#import "AMDTiming.h"

extern const ideChipsetOps_t ideAMDOperations;

@interface IdeController(AMD)
- (BOOL) AMDSetTiming:(void *)drives;
- (BOOL) AMDResetTiming;
- (BOOL) AMDDetectCable;
@end

#endif /* _IDE_AMD_H_ */
