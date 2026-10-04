#ifndef I596_TEST_NXLOCK_H
#define I596_TEST_NXLOCK_H

#import <objc/Object.h>

@protocol NXLock
- (void)lock;
- (void)unlock;
@end

@interface NXSpinLock : Object <NXLock>
@end

#endif
