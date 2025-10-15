#import "SCSIInspector.h"
#import "configKeys.h"

#define MYNAME		"AMDInspector"
#define NIB_TYPE	"nib"

@implementation AMDInspector

/*
 * Find and load our nib, put a localized title atop the connector 
 * box, and init buttons. 
 */
- init
{
	char 	buffer[MAXPATHLEN];
	NXBundle	*myBundle = [NXBundle bundleForClass:[self class]];
    
	[super init];
	
	if (![myBundle getPath:buffer forResource:MYNAME ofType:NIB_TYPE]) {
		[self free];
		return nil;
	}
	if (![NXApp loadNibFile:buffer owner:self withNames:NO]) {
		[self free];
		return nil;
	}
	return self;
}

/*
 * Get current values of the buttons from the existing 
 * config table. If the current table has no entry for specified
 * key, the associated button will be disabled.
 */    

- (void)_initButton : button   key : (const char *)key
{
	const char *value;
	int ival;

	value = [table valueForStringKey:key];
	if(value == NULL) {
		[button setState:0];
		[button setEnabled:0];
		return;
	}
	else if(strcmp(value, "YES") == 0) {
		ival = 1;
	}
	else {
		ival = 0;
	}
	[button setState:ival];
}

- setTable:(NXStringTable *)instance
{
	
    	[super setTable:instance];
    	[self setAccessoryView:boundingBox];
	[self _initButton:syncButton key:SYNC_ENABLE];
	[self _initButton:fastButton key:FAST_ENABLE];
	[self _initButton:cmdQueueButton key:CMD_QUEUE_ENABLE];
	return self;
}


- sync:sender
{
	int syncEnable;
	char *str;
	
	syncEnable = [sender state];
	if(syncEnable) {
		str = "YES";
	}
	else {
		str = "NO";
	}
    	[table insertKey:SYNC_ENABLE value:str];
	return self;
}

- fast:sender
{
	int fastEnable;
	char *str;
	
	fastEnable = [sender state];
	if(fastEnable) {
		str = "YES";
	}
	else {
		str = "NO";
	}
    	[table insertKey:FAST_ENABLE value:str];
	return self;
}

- cmdQueue:sender
{
	int cmdQueueEnable;
	char *str;
	
	cmdQueueEnable = [sender state];
	if(cmdQueueEnable) {
		str = "YES";
	}
	else {
		str = "NO";
	}
    	[table insertKey:CMD_QUEUE_ENABLE value:str];
	return self;
}

