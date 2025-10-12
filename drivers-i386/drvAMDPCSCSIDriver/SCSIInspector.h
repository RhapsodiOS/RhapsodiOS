#import <appkit/appkit.h>
#import <driverkit/IODeviceMaster.h>
#import <driverkit/IODeviceInspector.h>

@interface AMDInspector:IODeviceInspector
{
	id	optionsBox;	// the one with the title
	id	boundingBox;	// the one we put in the accessory view
	id	syncButton;
	id	fastButton;
	id	cmdQueueButton;
}

- init;
- (void)_initButton : button   key : (const char *)key;
- setTable:(NXStringTable *)instance;
- sync:sender;
- fast:sender;
- cmdQueue:sender;

@end
