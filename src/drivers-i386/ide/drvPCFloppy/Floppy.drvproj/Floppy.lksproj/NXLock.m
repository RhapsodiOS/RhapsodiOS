/*
 * Minimal NXLock for i386 PS2Keyboard kernel server builds.
 */
#import "NXLock.h"

@implementation NXLock
- lock { return self; }
- unlock { return self; }
@end

@implementation NXConditionLock
- initWith:(int)condition
{
    [super init];
    _priv = (void *)condition;
    return self;
}
- (int)condition { return (int)_priv; }
- lock { return self; }
- unlock { return self; }
- lockWhen:(int)condition { (void)condition; return self; }
- unlockWith:(int)condition { _priv = (void *)condition; return self; }
@end

@implementation NXSpinLock
- lock { return self; }
- unlock { return self; }
@end

@implementation NXRecursiveLock
- lock { return self; }
- unlock { return self; }
@end
