/*	NSWindow.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSInterfaceStyle.h>
#import <AppKit/psopsNeXT.h>

APPKIT_EXTERN int _NSAppKitGlobalLock;
APPKIT_EXTERN void _NSAppKitLock(int line, const char *file);
APPKIT_EXTERN void _NSAppKitUnlock(int line, const char *file);
APPKIT_EXTERN BOOL NSGetBooleanDefault(const char *key);
APPKIT_EXTERN void _NSSetHidesOnDeactivate(NSDPSContext *context,
	BOOL hidesOnDeactivate, BOOL visible);
APPKIT_EXTERN void _NSEnableMouseMovedEventsForWindow(NSDPSContext *context);
APPKIT_EXTERN void _NSDisableMouseMovedEventsForWindow(NSDPSContext *context);
APPKIT_EXTERN NSWindowDepth _NXDefaultWindowDepthLimit(void);

static signed char NSWindowHidesOnDeactivateEnabled = -2;

@interface NSWindow (NSWindowDeactivationPrivate)
- (NSDPSContext *)context;
@end

@interface NSApplication (NSWindowDeactivationPrivate)
- (void)_setHidesOnDeactivateInCache:(BOOL)hidesOnDeactivate forWindow:(id)window;
@end

@implementation NSWindow

+ (NSWindowDepth)defaultDepthLimit
{
	return _NXDefaultWindowDepthLimit();
}

- (NSWindowAuxiliaryOpaque *)_auxStorage
{
	return _auxiliaryStorage;
}

- (BOOL)_isImageCache
{
	return _wFlags.isImageCache;
}

- (NSResponder *)firstResponder
{
	return _firstResponder;
}

- (id)contentView
{
	return _contentView;
}

- (NSString *)representedFilename
{
	return _representedFilename;
}

- (id)delegate
{
	return _delegate;
}

- (NSColor *)backgroundColor
{
	return _backgroundColor;
}

- (NSView *)initialFirstResponder
{
	return _initialFirstResponder;
}

- (NSString *)frameAutosaveName
{
	return _frameSaveName;
}

- (NSImage *)miniwindowImage
{
	return _miniIcon;
}

- (BOOL)acceptsMouseMovedEvents
{
	return (_winEventMask & 0x20) != 0;
}

- (void)setAcceptsMouseMovedEvents:(BOOL)flag
{
	if (_windowNum > 0) {
		if (flag) {
			_NSEnableMouseMovedEventsForWindow([self context]);
			_winEventMask |= 0x20;
		} else {
			_NSDisableMouseMovedEventsForWindow([self context]);
			_winEventMask = 0;
		}
	}
}

- (BOOL)areCursorRectsEnabled
{
	return !_wFlags.cursorRectsDisabled;
}

- (NSSelectionDirection)keyViewSelectionDirection
{
	return _wFlags.keyViewSelectionDirection;
}

- (void)useOptimizedDrawing:(BOOL)flag
{
	_wFlags.optimizeDrawing = flag;
}

- (void)setInitialFirstResponder:(NSView *)view
{
	_initialFirstResponder = view;
}

- (id)_setCounterpart:(id)counterpart
{
	_counterpart = counterpart;
	return self;
}

- (BOOL)_postingEnabled
{
	return _postingDisabled == 0;
}

- (void)_disablePosting
{
	++_postingDisabled;
}

- (void)_setWantsToBeOnMainScreen:(BOOL)flag
{
	_wFlags.wantsToBeOnMainScreen = flag;
}

- (BOOL)_wantsToDestroyRealWindow
{
	return _wFlags.wantsToDestroyRealWindow;
}

- (BOOL)hasDynamicDepthLimit
{
	return _wFlags.dynamicDepthLimit;
}

- (id)_counterpart
{
	return _counterpart;
}

- (id)_getCounterpart
{
	return _counterpart;
}

- (id)_borderView
{
	return _borderView;
}

- (id)_lastLeftHit
{
	return _lastLeftHit;
}

- (id)_lastRightHit
{
	return _lastRightHit;
}

- (BOOL)_avoidsActivation
{
	return _wFlags.avoidsActivation;
}

- (BOOL)_isTerminating
{
	return _wFlags.isTerminating;
}

- (BOOL)_makingFirstResponderForMouseDown
{
	return _wFlags.makingFirstResponderForMouseDown;
}

- (BOOL)_titleIsRepresentedFilename
{
	return _wFlags.titleIsRepresentedFilename;
}

- (BOOL)_wantToBeModal
{
	return _wFlags.wantsToBeModal;
}

- (BOOL)_windowDying
{
	return _wFlags.windowDying;
}

- (BOOL)becomesKeyOnlyIfNeeded
{
	return NO;
}

- (id)_resetDisableCounts
{
	_flushDisabled = 0;
	return nil;
}

- (id)_setNeedsZoom:(id)flag
{
	_wFlags.needsZoom = YES;
	return self;
}

- (void)_setShowingModalFrame:(BOOL)flag
{
	_wFlags.showingModalFrame = flag;
}

- (void)_setWin32MouseActivationInProgress:(BOOL)flag
{
	_wFlags.win32MouseActivationInProgress = flag;
}

- (id)_setOneShotIsDelayed:(BOOL)flag
{
	_wFlags.delayedOneShot = flag;
	return self;
}

- (NSSize)aspectRatio
{
	return [_borderView aspectRatio];
}

- (void)setAspectRatio:(NSSize)ratio
{
	[_borderView setAspectRatio:ratio];
}

- (NSSize)resizeIncrements
{
	return [_borderView resizeIncrements];
}

- (void)setResizeIncrements:(NSSize)increments
{
	[_borderView setResizeIncrements:increments];
}

- (int)resizeFlags
{
	return [_borderView resizeFlags];
}

- (NSPoint)convertBaseToScreen:(NSPoint)point
{
	return NSMakePoint(_frame.origin.x + point.x,
		_frame.origin.y + point.y);
}

- (NSPoint)convertScreenToBase:(NSPoint)point
{
	return NSMakePoint(point.x - _frame.origin.x,
		point.y - _frame.origin.y);
}

- (NSString *)miniwindowTitle
{
	return [_counterpart miniwindowTitle];
}

- (void)setMiniwindowTitle:(NSString *)title
{
	if (NSInterfaceStyleForKey(@"NSWindowInterfaceStyle", self) != 3)
		[_counterpart setMiniwindowTitle:title];
}

- (NSRect)frame
{
	return _frame;
}

- (NSEvent *)currentEvent
{
	return [NSApp currentEvent];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
	return [_contentView performKeyEquivalent:event];
}

- (void)postEvent:(NSEvent *)event atStart:(BOOL)flag
{
	[NSApp postEvent:event atStart:flag];
}

- (void)_setDocumentEdited:(BOOL)flag
{
	flag = (flag != NO);
	if (_wFlags.docEdited == flag)
		return;
	_wFlags.docEdited = flag;
	[_borderView setDocumentEdited:flag];
	if (!_wFlags.excludedFromWindowsMenu)
		[NSApp updateWindowsItem:self];
}

- (void)setDocumentEdited:(BOOL)flag
{
	[self _setDocumentEdited:flag];
	if (NSInterfaceStyleForKey(@"NSWindowInterfaceStyle", self) == 3 &&
		_counterpart != nil)
		[_counterpart _setDocumentEdited:flag];
}

- (int)windowNumber
{
	return _windowNum;
}

- (BOOL)isVisible
{
	return _wFlags.visible;
}

- (unsigned int)styleMask
{
	if (_borderView != nil)
		return [_borderView styleMask];
	return _styleMask;
}

- (BOOL)isKeyWindow
{
	if (_wFlags.isKeyWindow)
		return [NSApp isActive];
	return NO;
}

- (BOOL)isMainWindow
{
	if (_wFlags.isMainWindow)
		return [NSApp isActive];
	return NO;
}

- (BOOL)canBecomeKeyWindow
{
	return [self styleMask] & (NSTitledWindowMask | NSResizableWindowMask);
}

- (BOOL)hidesOnDeactivate
{
	return _wFlags.hidesOnDeactivate;
}

- (void)setHidesOnDeactivate:(BOOL)flag
{
	BOOL locked = (_NSAppKitGlobalLock != 0);

	if (locked)
		_NSAppKitLock(3394, "NSWindow.m");
	if (NSWindowHidesOnDeactivateEnabled == -2)
		NSWindowHidesOnDeactivateEnabled =
			NSGetBooleanDefault("NSHideOnDeactivateEnabled");
	if (flag == NO || NSWindowHidesOnDeactivateEnabled != 0) {
		_wFlags.hidesOnDeactivate = flag;
		if (flag == NO)
			_wFlags.haveFreeCursorRects = NO;
		[NSApp _setHidesOnDeactivateInCache:flag forWindow:self];
		if (_windowNum > 0)
			_NSSetHidesOnDeactivate([self context], flag, _wFlags.visible);
	}
	if (locked)
		_NSAppKitUnlock(3408, "NSWindow.m");
}

- (BOOL)isOneShot
{
	return _wFlags.oneShot;
}

- (BOOL)isReleasedWhenClosed
{
	return !_wFlags.dontFreeWhenClosed;
}

- (void)setOneShot:(BOOL)flag
{
	_wFlags.oneShot = flag;
}

- (void)setReleasedWhenClosed:(BOOL)flag
{
	_wFlags.dontFreeWhenClosed = !flag;
}

- (BOOL)isFlushWindowDisabled
{
	return _flushDisabled != 0;
}

- (void)disableFlushWindow
{
	++_flushDisabled;
}

- (void)enableFlushWindow
{
	if (_flushDisabled != 0)
		--_flushDisabled;
	else
		NSLog(@"[NSWindow enableFlushWindow] was called without disableFlushWindow. Currently this is an NSLog(); in 2W this will be changed to an assertion failure");
}

- (BOOL)viewsNeedDisplay
{
	return _wFlags.viewsNeedDisplay;
}

- (void)setViewsNeedDisplay:(BOOL)flag
{
	_wFlags.viewsNeedDisplay = flag;
	if (flag && _wFlags.autodisplay && [self isVisible])
		[self displayIfNeeded];
}

- (BOOL)isAutodisplay
{
	return _wFlags.autodisplay;
}

- (void)setAutodisplay:(BOOL)flag
{
	_wFlags.autodisplay = flag;
}

- (BOOL)isDocumentEdited
{
	return _wFlags.docEdited;
}

- (BOOL)isExcludedFromWindowsMenu
{
	return _wFlags.excludedFromWindowsMenu;
}

- (void)setExcludedFromWindowsMenu:(BOOL)flag
{
	_wFlags.excludedFromWindowsMenu = flag;
}

- (BOOL)worksWhenModal
{
	return NO;
}

- (NSBackingStoreType)backingType
{
	return (NSBackingStoreType)_wFlags.backing;
}

- (int)level
{
	return _level;
}

- (NSSize)minSize
{
	if (_sizeLimits != 0)
		return _sizeLimits[0];
	return NSZeroSize;
}

- (NSWindowDepth)depthLimit
{
	if (_wFlags.depthLimit != 0)
		return NSAvailableWindowDepths()[_wFlags.depthLimit - 1];
	return 0;
}

- (void)setLevel:(int)newLevel
{
	_level = newLevel;
	if (_windowNum > 0)
		PSsetwindowlevel(newLevel, _windowNum);
}

- (void)setBackingType:(NSBackingStoreType)bufferingType
{
	_wFlags.backing = bufferingType;
	if (_windowNum > 0)
		PSsetwindowtype(bufferingType, _windowNum);
}

- (BOOL)_canHide
{
	return YES;
}

- (id)_tempHideHODWindow
{
	_wFlags.tempHidden = YES;
	return nil;
}

- (id)_tempUnhideHODWindow
{
	_wFlags.tempHidden = NO;
	return nil;
}

- (id)_tempHide:(BOOL)hide relWin:(int)relativeWindow
{
	if (hide) {
		if (_wFlags.visible) {
			[self orderOut:nil];
			_wFlags.tempHidden = YES;
		}
	} else if (_wFlags.tempHidden) {
		if (relativeWindow != 0)
			[self orderWindow:NSWindowBelow relativeTo:relativeWindow];
		else
			[self orderWindow:NSWindowAbove relativeTo:0];
		_wFlags.tempHidden = NO;
	}
	return self;
}

@end

