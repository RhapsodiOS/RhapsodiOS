#import <driverkit/IODevice.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IODirectDevice.h>
#import <driverkit/IODisplay.h>
#import <driverkit/IOFrameBufferDisplay.h>
#import <driverkit/generalFuncs.h>
#import <mach/i386/vm_param.h>

/* Link-only superclass/runtime substitutes for the isolated DAC fixture. */
IODisplayInfo ATI_mockSuperDisplayInfo;

@implementation IODevice
@end

@implementation IOConfigTable
@end

@implementation IODeviceDescription
@end

@implementation IODirectDevice
@end

@implementation IODisplay
@end

@implementation IOFrameBufferDisplay
- initFromDeviceDescription:(id)description { (void)description; return self; }
- free { return self; }
- (IODisplayInfo *)displayInfo { return &ATI_mockSuperDisplayInfo; }
@end

vm_offset_t page_mask = 0xfff;

const char *IOFindNameForValue(int value, const IONamedValue *namedValueArray)
{
    (void)value;
    (void)namedValueArray;
    return "test";
}
