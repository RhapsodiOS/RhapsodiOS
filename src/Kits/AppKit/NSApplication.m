/*	NSApplication.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSApplication.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSRunLoop.h>
#import <AppKit/NSInputManager.h>
#include <string.h>

APPKIT_EXTERN void _NXOrderKeyAndMain(void);
APPKIT_EXTERN void _NXReorderWindows(void);
APPKIT_EXTERN void _NXPreventWindowOrdering(id application, SEL selector);
APPKIT_EXTERN int _NSAppKitGlobalLock;
APPKIT_EXTERN void _NSAppKitLock(int line, const char *file);
APPKIT_EXTERN void _NSAppKitUnlock(int line, const char *file);

static BOOL _doingOpenFile;
static NSArray *_defaultAndModalPanelModes;

NSArray *_NSDefaultAndModalPanelModes(void)
{
	if (_defaultAndModalPanelModes == nil)
		_defaultAndModalPanelModes = [[NSArray alloc]
			initWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil];
	return _defaultAndModalPanelModes;
}

typedef struct {
	id window;
	int windowNumber;
	unsigned int flags;
} NSApplicationWindowCacheEntry;

@interface NSWindow (NSApplicationUnhidePrivate)
- (BOOL)_canHide;
- (id)_tempHide:(BOOL)hide relWin:(int)relativeWindow;
- (id)_tempUnhideHODWindow;
@end

@interface NSApplication (NSWindowCache)
- (NSApplicationWindowCacheEntry *)_getWindowCache:(id)window add:(BOOL)add;
- (void)_makeHODWindowsPerform:(SEL)selector;
- (id)_findWindowUsingCache:(int)windowNumber;
- (void)_setCacheWindowNum:(int)windowNumber forWindow:(id)window;
- (void)_setHidesOnDeactivateInCache:(BOOL)hidesOnDeactivate forWindow:(id)window;
- (void)_setVisibleInCache:(BOOL)visible forWindow:(id)window;
- (void)_updateWindowsUsingCache;
- (void)_removeWindowFromCache:(id)window;
- (BOOL)_isVisibleUsingCache:(id)window;
- (void)_checkForTerminateAfterLastWindowClosed:(id)window;
@end

@interface NSApplication (NSApplicationContext)
- (int)_mainContextID;
- (NSWindow *)frontWindow;
- (BOOL)_isRunningModal;
- (id)_setKeyWindow:(id)window;
- (id)_setMainWindow:(id)window;
- (BOOL)_mouseActivationInProgress;
- (id)_setMouseActivationInProgress:(BOOL)flag;
- (int)_lastEventTime;
- (void)_setCurrentEvent:(NSEvent *)event;
- (void)setIsActive:(BOOL)flag;
- (int)_currentActivation;
- (int)_pendingActCount;
- (id)_setCurrentActivation:(int)value;
- (NSImage *)applicationIconImage;
- (void)setApplicationIconImage:(NSImage *)image;
- (void)_setEventDelegate:(id)delegate;
- (void)_handleWindowsNeedUpdateNote:(id)notification;
@end

@interface NSInputManager (NSApplicationWindowUpdate)
- (void)_notifyInputServerIfNeeded;
@end

@interface NSObject (NSApplicationEventDelegate)
- (void)application:(NSApplication *)application receivedEvent:(NSEvent *)event dequeued:(BOOL)dequeued;
@end

struct _NSModalSession {
	NSApplication *application;
	NSWindow *window;
	NSModalSession previous;
	int running;
	unsigned char hidesOnDeactivate;
	unsigned char reserved[3];
	int windowNumber;
	int alternateHandler;
	NSDPSContext *context;
};

static NSModalSession _NXLastModalSession;
static int _currentActivation;
static int _deferredCurrentActivation;
static NSImage *_iconImage;

static BOOL _isWindowObjectInCache(id application, NSMutableData *windowCache)
{
	NSApplicationWindowCacheEntry *entries;
	unsigned int index, count;
	BOOL locked = (_NSAppKitGlobalLock != 0);

	if (windowCache == nil)
		return NO;
	if (locked)
		_NSAppKitLock(151, "appCache.m");
	entries = (NSApplicationWindowCacheEntry *)[windowCache mutableBytes];
	count = (unsigned int)[windowCache length] / sizeof(*entries);
	for (index = 0; index < count; index++) {
		if ((entries[index].flags & 0xC0000000U) == 0x40000000U &&
			[entries[index].window isKindOfClass:[NSWindow class]] &&
			entries[index].window != [application _appIcon]) {
			if (locked)
				_NSAppKitUnlock(156, "appCache.m");
			return YES;
		}
	}
	if (locked)
		_NSAppKitUnlock(160, "appCache.m");
	return NO;
}

@implementation NSApplication (NSWindowCache)

- (NSApplicationWindowCacheEntry *)_getWindowCache:(id)window add:(BOOL)add
{
	NSApplicationWindowCacheEntry *entries, *entry = NULL;
	unsigned int index, count, length;
	BOOL locked = (_NSAppKitGlobalLock != 0);

	if (locked)
		_NSAppKitLock(47, "NSApplication.m");
	if (_windowCache == nil)
		_windowCache = [[NSMutableData allocWithZone:[self zone]] initWithCapacity:96];
	entries = (NSApplicationWindowCacheEntry *)[_windowCache mutableBytes];
	count = (unsigned int)[_windowCache length] / sizeof(*entries);
	for (index = 0; index < count; index++) {
		if ((int)entries[index].flags < 0) {
			if (entry == NULL)
				entry = &entries[index];
		} else if (entries[index].window == window) {
			if (locked)
				_NSAppKitUnlock(57, "NSApplication.m");
			return &entries[index];
		}
	}
	if (!add) {
		if (locked)
			_NSAppKitUnlock(62, "NSApplication.m");
		return NULL;
	}
	if (entry != NULL) {
		memset(entry, 0, sizeof(*entry));
		entry->window = window;
		if (locked)
			_NSAppKitUnlock(68, "NSApplication.m");
		return entry;
	}
	length = [_windowCache length];
	[_windowCache setLength:length + sizeof(*entries)];
	entries = (NSApplicationWindowCacheEntry *)[_windowCache mutableBytes];
	entry = &entries[count];
	entry->window = window;
	if (locked)
		_NSAppKitUnlock(75, "NSApplication.m");
	return entry;
}

- (id)_findWindowUsingCache:(int)windowNumber
{
	NSApplicationWindowCacheEntry *entries;
	unsigned int index, count;
	BOOL locked;

	if (_windowCache == nil)
		return nil;
	locked = (_NSAppKitGlobalLock != 0);
	if (locked)
		_NSAppKitLock(85, "NSApplication.m");
	entries = (NSApplicationWindowCacheEntry *)[_windowCache mutableBytes];
	count = (unsigned int)[_windowCache length] / sizeof(*entries);
	for (index = 0; index < count; index++) {
		if ((int)entries[index].flags < 0 ||
			entries[index].windowNumber != windowNumber)
			continue;
		if (locked)
			_NSAppKitUnlock(91, "NSApplication.m");
		return entries[index].window;
	}
	if (locked)
		_NSAppKitUnlock(96, "NSApplication.m");
	return nil;
}

- (void)_makeHODWindowsPerform:(SEL)selector
{
	NSApplicationWindowCacheEntry *entries;
	unsigned int index, count;
	BOOL locked = (_NSAppKitGlobalLock != 0);

	if (_windowCache == nil)
		return;
	if (locked)
		_NSAppKitLock(256, "NSApplication.m");
	entries = (NSApplicationWindowCacheEntry *)[_windowCache mutableBytes];
	count = (unsigned int)[_windowCache length] / sizeof(*entries);
	for (index = 0; index < count; index++) {
		if ((entries[index].flags & 0xA0000000U) == 0x20000000U)
			[entries[index].window performSelector:selector];
	}
	if (locked)
		_NSAppKitUnlock(264, "NSApplication.m");
}

- (void)_updateWindowsUsingCache
{
	NSApplicationWindowCacheEntry *entries;
	unsigned int index, count;
	BOOL locked;

	if (_windowCache == nil)
		return;
	locked = (_NSAppKitGlobalLock != 0);
	if (locked)
		_NSAppKitLock(107, "appCache.m");
	entries = (NSApplicationWindowCacheEntry *)[_windowCache mutableBytes];
	count = (unsigned int)[_windowCache length] / sizeof(*entries);
	for (index = 0; index < count; index++) {
		if ((entries[index].flags & 0xC0000000U) == 0x40000000U)
			[entries[index].window update];
	}
	if (locked)
		_NSAppKitUnlock(115, "appCache.m");
}

- (void)_setCacheWindowNum:(int)windowNumber forWindow:(id)window
{
	NSApplicationWindowCacheEntry *entry;
	BOOL locked = (_NSAppKitGlobalLock != 0);

	if (locked)
		_NSAppKitLock(120, "NSApplication.m");
	entry = [self _getWindowCache:window add:YES];
	entry->windowNumber = windowNumber;
	if (locked)
		_NSAppKitUnlock(123, "NSApplication.m");
}

- (void)_setHidesOnDeactivateInCache:(BOOL)hidesOnDeactivate forWindow:(id)window
{
	NSApplicationWindowCacheEntry *entry;
	BOOL locked = (_NSAppKitGlobalLock != 0);

	if (locked)
		_NSAppKitLock(245, "NSApplication.m");
	entry = [self _getWindowCache:window add:YES];
	entry->flags = ((hidesOnDeactivate << 29) & 0x20000000U) |
		(entry->flags & 0xDFFFFFFFU);
	if (locked)
		_NSAppKitUnlock(248, "NSApplication.m");
}

- (BOOL)_isVisibleUsingCache:(id)window
{
	NSApplicationWindowCacheEntry *entry = [self _getWindowCache:window add:NO];

	return entry != NULL && (entry->flags & 0x40000000U) != 0;
}

- (void)_setVisibleInCache:(BOOL)visible forWindow:(id)window
{
	NSApplicationWindowCacheEntry *entry;
	BOOL locked = (_NSAppKitGlobalLock != 0);

	if (locked)
		_NSAppKitLock(189, "NSApplication.m");
	entry = [self _getWindowCache:window add:YES];
	entry->flags = ((visible << 30) & 0x40000000U) |
		(entry->flags & 0xBFFFFFFFU);
	if (locked)
		_NSAppKitUnlock(192, "NSApplication.m");
	if (!visible && !_appFlags._hidden && [self isActive] &&
		!_isWindowObjectInCache(self, _windowCache)) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		int delay = [[defaults objectForKey:@"NSTerminateAfterLastWindowClosedDelay"] intValue];

		if (delay < 0)
			delay = 0;
		[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(_checkForTerminateAfterLastWindowClosed:) object:self];
		[self performSelector:@selector(_checkForTerminateAfterLastWindowClosed:)
			withObject:self afterDelay:(NSTimeInterval)delay];
	}
}

- (void)_removeWindowFromCache:(id)window
{
	NSApplicationWindowCacheEntry *entry;
	BOOL locked = (_NSAppKitGlobalLock != 0);

	if (locked)
		_NSAppKitLock(215, "NSApplication.m");
	entry = [self _getWindowCache:window add:NO];
	if (entry != NULL)
		entry->flags |= 0x80000000U;
	if (locked)
		_NSAppKitUnlock(218, "NSApplication.m");
	if (!_appFlags._hidden && [self isActive] &&
		!_isWindowObjectInCache(self, _windowCache)) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		int delay = [[defaults objectForKey:@"NSTerminateAfterLastWindowClosedDelay"] intValue];

		if (delay < 0)
			delay = 0;
		[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(_checkForTerminateAfterLastWindowClosed:) object:self];
		[self performSelector:@selector(_checkForTerminateAfterLastWindowClosed:)
			withObject:self afterDelay:(NSTimeInterval)delay];
	}
}

- (void)_checkForTerminateAfterLastWindowClosed:(id)window
{
	id delegate;

	(void)window;
	if (_isWindowObjectInCache(self, _windowCache))
		return;
	delegate = [self delegate];
	if (delegate != nil &&
		[delegate respondsToSelector:@selector(applicationShouldTerminateAfterLastWindowClosed:)] &&
		[delegate applicationShouldTerminateAfterLastWindowClosed:self])
		[self terminate:self];
}

@end

@implementation NSApplication

- (id)_removeHiddenWindow:(int)windowNumber
{
	int index;

	for (index = _hiddenCount - 1; index >= 0; index--) {
		if (_hiddenList[index] == windowNumber)
			break;
	}
	if (index >= 0) {
		memmove(&_hiddenList[index], &_hiddenList[index + 1],
			(_hiddenCount - index - 1) * sizeof(*_hiddenList));
		_hiddenCount--;
	}
	return self;
}

- (void)_windowNumber:(int)oldWindowNumber changedTo:(int)newWindowNumber
{
	NSModalSession session;
	unsigned int index;

	for (session = _NXLastModalSession; session != NULL;
		session = session->previous) {
		if (session->windowNumber == oldWindowNumber)
			session->windowNumber = newWindowNumber;
	}
	if (_hiddenCount <= 0)
		return;
	if (newWindowNumber == -1) {
		[self _removeHiddenWindow:oldWindowNumber];
		return;
	}
	for (index = 0; index < (unsigned int)_hiddenCount; index++) {
		if (_hiddenList[index] == oldWindowNumber)
			_hiddenList[index] = newWindowNumber;
	}
}

- (NSWindow *)windowWithWindowNumber:(int)windowNum
{
	return [self _findWindowUsingCache:windowNum];
}

- (id)_addWindow:(id)window
{
	id windowNumber = [NSNumber numberWithInt:[window windowNumber]];
	BOOL locked = (_NSAppKitGlobalLock != 0);

	if (locked)
		_NSAppKitLock(3144, "NSApplication.m");
	if ([_windowList indexOfObject:windowNumber] == NSNotFound)
		[_windowList addObject:windowNumber];
	if (locked)
		_NSAppKitUnlock(3149, "NSApplication.m");
	return self;
}

- (id)_removeWindow:(id)window
{
	BOOL locked = (_NSAppKitGlobalLock != 0);
	id windowNumber = [NSNumber numberWithInt:[window windowNumber]];

	if (locked)
		_NSAppKitLock(3124, "NSApplication.m");
	[_windowList removeObject:windowNumber];
	if (_keyWindow == window)
		_keyWindow = nil;
	if (_mainWindow == window)
		_mainWindow = nil;
	[self _removeWindowFromCache:window];
	if (locked)
		_NSAppKitUnlock(3131, "NSApplication.m");
	return self;
}

- (NSArray *)windows
{
	BOOL locked = (_NSAppKitGlobalLock != 0);
	unsigned int index, count;
	NSMutableArray *windows;

	if (locked)
		_NSAppKitLock(2755, "NSApplication.m");
	count = [_windowList count];
	windows = [[NSMutableArray allocWithZone:[self zone]] initWithCapacity:count];
	for (index = 0; index < count; index++) {
		NSNumber *windowNumber = [_windowList objectAtIndex:index];
		[windows addObject:[self windowWithWindowNumber:[windowNumber intValue]]];
	}
	if (locked)
		_NSAppKitUnlock(2762, "NSApplication.m");
	return [windows autorelease];
}

- (int)_mainContextID
{
	return *((int *)_threadingSupport);
}

- (NSWindow *)frontWindow
{
	int windowNumber;
	NSWindowListForContext([self _mainContextID], 1, &windowNumber);
	return [self windowWithWindowNumber:windowNumber];
}

- (BOOL)isActive
{
	return _appFlags._active;
}

- (void)setIsActive:(BOOL)flag
{
	unsigned int flags = *((unsigned int *)&_appFlags);
	flags = (flag ? 0x20000000U : 0) | (flags & 0xDFFFFFFFU);
	*((unsigned int *)&_appFlags) = flags;
}

- (BOOL)isHidden
{
	return _appFlags._hidden;
}

- (BOOL)isRunning
{
	return _running > 0;
}

- (int)_currentActivation
{
	return _currentActivation;
}

- (int)_pendingActCount
{
	return _deferredCurrentActivation;
}

- (id)_setCurrentActivation:(int)value
{
	_currentActivation = value;
	return self;
}

- (BOOL)_isRunningModal
{
	if (*((unsigned int *)&_appFlags) & 0x10000000U)
		return _running > 1;
	return _running > 0;
}

- (NSWindow *)modalWindow
{
	if ([self _isRunningModal]) {
		if (_NXLastModalSession != NULL)
			return _NXLastModalSession->window;
	}
	return nil;
}

- (void)updateWindows
{
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NSApplicationWillUpdateNotification object:self];
	[self _updateWindowsUsingCache];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NSApplicationDidUpdateNotification object:self];
}

- (void)setWindowsNeedUpdate:(BOOL)needUpdate
{
	if (!_appFlags._postedWindowsNeedUpdateNote && needUpdate) {
		[[NSRunLoop currentRunLoop]
			performSelector:@selector(_handleWindowsNeedUpdateNote:)
			target:self argument:nil order:NSUpdateWindowsRunLoopOrdering
			modes:_NSDefaultAndModalPanelModes()];
		_appFlags._postedWindowsNeedUpdateNote = YES;
	}
}

- (void)_handleWindowsNeedUpdateNote:(id)notification
{
	_appFlags._postedWindowsNeedUpdateNote = NO;
	[self updateWindows];
	[[NSInputManager currentInputManager] _notifyInputServerIfNeeded];
}

- (id)delayWindowOrdering
{
	return self;
}

- (void)preventWindowOrdering
{
	_NXPreventWindowOrdering(self, _cmd);
}

- (BOOL)_isDoingOpenFile
{
	return _doingOpenFile;
}

- (BOOL)_isDoingHide
{
	return _appFlags._doingHide;
}

- (BOOL)_isDoingUnhide
{
	return _appFlags._doingUnhide;
}

- (BOOL)_isDeactPending
{
	return _appFlags._deactPending;
}

- (NSWindow *)keyWindow
{
	if (_appFlags._active && !_appFlags._invalidState)
		return _keyWindow;
	return nil;
}

- (NSWindow *)mainWindow
{
	if (_appFlags._active && !_appFlags._invalidState)
		return _mainWindow;
	return nil;
}

- (id)_keyWindow
{
	return _keyWindow;
}

- (id)_mainWindow
{
	return _mainWindow;
}

- (id)_setKeyWindow:(id)window
{
	_keyWindow = window;
	return self;
}

- (id)_setMainWindow:(id)window
{
	_mainWindow = window;
	return self;
}

- (BOOL)_mouseActivationInProgress
{
	return (*((unsigned int *)&_appFlags) & 0x01000000U) != 0;
}

- (id)_setMouseActivationInProgress:(BOOL)flag
{
	unsigned int flags = *((unsigned int *)&_appFlags);
	flags = ((flag << 24) & 0x01000000U) | (flags & 0xFEFFFFFFU);
	*((unsigned int *)&_appFlags) = flags;
	return self;
}

- (id)_appIcon
{
	return _appIcon;
}

- (id)_appListener
{
	return _appListener;
}

- (NSDPSContext *)context
{
	return _context;
}

- (NSEvent *)currentEvent
{
	return _currentEvent;
}

- (void)_setCurrentEvent:(NSEvent *)event
{
	if (![event isEqual:_currentEvent]) {
		[_currentEvent release];
		_currentEvent = [event retain];
	}
}

- (int)_lastEventTime
{
	unsigned int flags = *((unsigned int *)&_appFlags);
	if ((flags & 0x10800000U) == 0x10800000U || [_currentEvent type] == 15)
		return 0;
	return (int)[_currentEvent timestamp];
}

- (NSMenu *)mainMenu
{
	return (NSMenu *)_mainMenu;
}

- (id)menu
{
	return [self mainMenu];
}

- (void)setMenu:(id)menu
{
	[self setMainMenu:menu];
}

- (void)_setMainMenu:(id)menu
{
	_mainMenu = menu;
}

- (id)_eventDelegate
{
	return _eventDelegate;
}

- (void)_setEventDelegate:(id)delegate
{
	if (_eventDelegate != delegate) {
		_eventDelegate = delegate;
		_appFlags._hasEventDelegate = delegate != nil &&
			[delegate respondsToSelector:@selector(application:receivedEvent:dequeued:)];
	}
}

- (NSImage *)applicationIconImage
{
	if (!_iconImage)
		[self setApplicationIconImage:[NSImage imageNamed:@"NSApplicationIcon"]];
	return _iconImage;
}

- (void)setApplicationIconImage:(NSImage *)image
{
	NSSize size = [image size];
	if (_iconImage) {
		if (!NSEqualSizes([_iconImage size], size))
			[_iconImage setSize:size];
	} else {
		_iconImage = [[NSImage alloc] initWithSize:size];
		[_iconImage setScalesWhenResized:YES];
	}
	[_iconImage lockFocus];
	[[NSColor clearColor] set];
	NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
	[image compositeToPoint:NSZeroPoint operation:NSCompositeSourceOver];
	[_iconImage unlockFocus];
}

- (void)unhideWithoutActivation
{
	NSNotificationCenter *center;
	NSWindow *window;
	int index, relativeWindow = 0;

	if (_appFlags._doingUnhide)
		return;
	if (!_appFlags._hidden) {
		_NXReorderWindows();
		return;
	}

	_appFlags._doingUnhide = YES;
	center = [NSNotificationCenter defaultCenter];
	[center postNotificationName:NSApplicationWillUnhideNotification object:self];
	NS_DURING
		for (index = 0; index < _hiddenCount; index++) {
			window = [self windowWithWindowNumber:_hiddenList[index]];
			if (window != _appIcon && ([window styleMask] & 0x10000000) == 0 &&
				[window _canHide]) {
				[window _tempHide:NO relWin:relativeWindow];
				relativeWindow = [window windowNumber];
			}
		}
		[self _makeHODWindowsPerform:@selector(_tempUnhideHODWindow)];
	NS_HANDLER
		_appFlags._doingUnhide = NO;
		[localException raise];
	NS_ENDHANDLER

	_appFlags._hidden = NO;
	_appFlags._doingUnhide = NO;
	NSZoneFree([self zone], _hiddenList);
	_hiddenList = NULL;
	_hiddenCount = 0;
	_NXOrderKeyAndMain();
	[center postNotificationName:NSApplicationDidUnhideNotification object:self];
}

@end

