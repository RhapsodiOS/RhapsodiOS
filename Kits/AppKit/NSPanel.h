/*
	NSPanel.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSWindow.h>
#import <AppKit/AppKitDefines.h>

/*
 * In the following two functions, msg may be a printf-like message with
 * the arguments tacked onto the end.  Thus, to get a '%' in your message,
 * you must use '%%'
 */

APPKIT_EXTERN int NSRunAlertPanel(NSString *title, NSString *msg, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...);
APPKIT_EXTERN int NSRunInformationalAlertPanel(NSString *title, NSString *msg, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...);
APPKIT_EXTERN int NSRunCriticalAlertPanel(NSString *title, NSString *msg, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...);

APPKIT_EXTERN id NSGetAlertPanel(NSString *title, NSString *msg, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...);
APPKIT_EXTERN id NSGetInformationalAlertPanel(NSString *title, NSString *msg, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...);
APPKIT_EXTERN id NSGetCriticalAlertPanel(NSString *title, NSString *msg, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...);

APPKIT_EXTERN void NSReleaseAlertPanel(id panel);

/*
 * NSRunAlertPanel() return values (also returned by runModalSession: when
 * the modal session is run with a panel returned by NSGetAlertPanel()).
 */

enum {
    NSAlertDefaultReturn		= 1,
    NSAlertAlternateReturn		= 0,
    NSAlertOtherReturn			= -1,
    NSAlertErrorReturn			= -2
};

enum {
    NSOKButton				= 1,
    NSCancelButton			= 0
};

// Panel specific styleMask
enum {
    NSUtilityWindowMask			= 1 << 4
};

@interface NSPanel : NSWindow
{
/*All instance variables are private*/
}

- (BOOL)isFloatingPanel;
- (void)setFloatingPanel:(BOOL)flag;
- (BOOL)becomesKeyOnlyIfNeeded;
- (void)setBecomesKeyOnlyIfNeeded:(BOOL)flag;
- (BOOL)worksWhenModal;
- (void)setWorksWhenModal:(BOOL)flag;

@end
