/*
	NSWindow.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSResponder.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSColor.h>
#import <AppKit/AppKitDefines.h>
#import <Foundation/NSHashTable.h>
@class NSText;
@class NSCursor;
@class NSView;
@class NSButtonCell;
@class NSUndoManager;

enum {
    NSBorderlessWindowMask		= 0,
    NSTitledWindowMask			= 1 << 0,
    NSClosableWindowMask		= 1 << 1,
    NSMiniaturizableWindowMask		= 1 << 2,
    NSResizableWindowMask		= 1 << 3
};

/* used with NSRunLoop's performSelector:target:argument:order:modes: */
enum {
    NSDisplayWindowRunLoopOrdering	= 600000,
    NSResetCursorRectsRunLoopOrdering	= 700000
};

APPKIT_EXTERN NSSize NSIconSize;
APPKIT_EXTERN NSSize NSTokenSize;

enum {
    NSNormalWindowLevel			= 0,
    NSFloatingWindowLevel		= 3,
    NSSubmenuWindowLevel		= 3,   // Actually this is more accurately described as the torn off menu level as below.
    NSTornOffMenuWindowLevel		= 3,
    NSMainMenuWindowLevel		= 20,
    NSStatusWindowLevel			= 21,
    NSDockWindowLevel			= 21,	// deprecated. do not use
    NSModalPanelWindowLevel             = 100,
    NSPopUpMenuWindowLevel              = 101,
    NSScreenSaverWindowLevel            = 1000
};

typedef enum _NSSelectionDirection {
    NSDirectSelection = 0,
    NSSelectingNext,
    NSSelectingPrevious
} NSSelectionDirection;

typedef struct NSWindowAuxiliary NSWindowAuxiliaryOpaque;

@class NSEvent;
@class NSWindowController;

@interface NSWindow : NSResponder
{
    /*All instance variables are private*/
    NSRect              _frame;
    id                  _contentView;
    id                  _delegate;
    NSResponder		*_firstResponder;
    NSView		*_lastLeftHit;
    NSView		*_lastRightHit;
    id                  _counterpart;
    id                  _fieldEditor;
    int                 _winEventMask;
    int                 _windowNum;
    int			_level;
    NSColor		*_backgroundColor;
    id                  _borderView;
    unsigned char	_postingDisabled;
    unsigned char	_styleMask;
    unsigned char	_flushDisabled;
    unsigned char	_reservedWindow1;
    void		*_cursorRects;
    NSHashTable		*_trectTable;
    NSImage		*_miniIcon;
    int			_lastResizeTime;
    NSMutableSet	*_dragTypes;
    NSString		*_representedFilename;
    NSSize		*_sizeLimits;
    NSString		*_frameSaveName;
    NSSet		*_regDragTypes;
    struct __wFlags {
        unsigned int        backing:2;
        unsigned int        visible:1;
        unsigned int        isMainWindow:1;
        unsigned int        isKeyWindow:1;
        unsigned int        hidesOnDeactivate:1;
        unsigned int        dontFreeWhenClosed:1;
        unsigned int        oneShot:1;
        unsigned int        deferred:1;
        unsigned int        cursorRectsDisabled:1;
        unsigned int        haveFreeCursorRects:1;
        unsigned int        validCursorRects:1;
        unsigned int        docEdited:1;
        unsigned int        dynamicDepthLimit:1;
        unsigned int        worksWhenModal:1;
        unsigned int        limitedBecomeKey:1;
        unsigned int        needsFlush:1;
        unsigned int        viewsNeedDisplay:1;
        unsigned int        ignoredFirstMouse:1;
        unsigned int        repostedFirstMouse:1;
        unsigned int        windowDying:1;
        unsigned int        tempHidden:1;
        unsigned int        floatingPanel:1;
        unsigned int        wantsToBeOnMainScreen:1;
        unsigned int        optimizedDrawingOk:1;
        unsigned int        optimizeDrawing:1;
        unsigned int        titleIsRepresentedFilename:1;
        unsigned int        excludedFromWindowsMenu:1;
        unsigned int        depthLimit:4;
        unsigned int        delegateReturnsValidRequestor:1;
        unsigned int        lmouseupPending:1;
        unsigned int        rmouseupPending:1;
        unsigned int        wantsToDestroyRealWindow:1;
        unsigned int        wantsToRegDragTypes:1;
        unsigned int        sentInvalidateCursorRectsMsg:1;
        unsigned int        avoidsActivation:1;
        unsigned int        frameSavedUsingTitle:1;
        unsigned int        didRegDragTypes:1;
        unsigned int        delayedOneShot:1;
        unsigned int	    postedNeedsDisplayNote:1;
        unsigned int	    postedInvalidCursorRectsNote:1;
        unsigned int        initialFirstResponderTempSet:1;
        unsigned int        autodisplay:1;
        unsigned int        tossedFirstEvent:1;
        unsigned int        isImageCache:1;
        unsigned int        interfaceStyle:3;
        unsigned int        keyViewSelectionDirection:2;
        unsigned int        defaultButtonCellKETemporarilyDisabled:1;
        unsigned int        defaultButtonCellKEDisabled:1;
        unsigned int        menuHasBeenSet:1;
        unsigned int        wantsToBeModal:1;
        unsigned int        showingModalFrame:1;
        unsigned int        isTerminating:1;
        unsigned int        win32MouseActivationInProgress:1;
        unsigned int        makingFirstResponderForMouseDown:1;
        unsigned int        needsZoom:1;
        unsigned int 	    sentWindowNeedsDisplayMsg:1;
        unsigned int        needsDealloc:1;
    }                   _wFlags;
    id			_defaultButtonCell;
    NSView 		*_initialFirstResponder;
    NSWindowAuxiliaryOpaque 	*_auxiliaryStorage;
}

+ (NSRect)frameRectForContentRect:(NSRect)cRect styleMask:(unsigned int)aStyle;
+ (NSRect)contentRectForFrameRect:(NSRect)fRect styleMask:(unsigned int)aStyle;
+ (float)minFrameWidthWithTitle:(NSString *)aTitle styleMask:(unsigned int)aStyle;
+ (NSWindowDepth)defaultDepthLimit;


- (id)initWithContentRect:(NSRect)contentRect styleMask:(unsigned int)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag;
- (id)initWithContentRect:(NSRect)contentRect styleMask:(unsigned int)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag screen:(NSScreen *)screen;

- (NSString *)title;
- (void)setTitle:(NSString *)aString;
- (NSString *)representedFilename;
- (void)setRepresentedFilename:(NSString *)aString;
- (void)setTitleWithRepresentedFilename:(NSString *)filename;
- (void)setExcludedFromWindowsMenu:(BOOL)flag;
- (BOOL)isExcludedFromWindowsMenu;
- (void)setContentView:(NSView *)aView;
- (id)contentView;
- (void)setDelegate:(id)anObject;
- (id)delegate;
- (int)windowNumber;
- (unsigned int)styleMask;
- (NSText *)fieldEditor:(BOOL)createFlag forObject:(id)anObject;
- (void)endEditingFor:(id)anObject;

- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen;
- (void)setFrame:(NSRect)frameRect display:(BOOL)flag;
- (void)setContentSize:(NSSize)aSize;
- (void)setFrameOrigin:(NSPoint)aPoint;
- (void)setFrameTopLeftPoint:(NSPoint)aPoint;
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)topLeftPoint;
- (NSRect)frame;

- (void)setResizeIncrements:(NSSize)increments;
- (NSSize)resizeIncrements;
- (void)setAspectRatio:(NSSize)ratio;
- (NSSize)aspectRatio;

- (void)useOptimizedDrawing:(BOOL)flag;
- (void)disableFlushWindow;
- (void)enableFlushWindow;
- (BOOL)isFlushWindowDisabled;
- (void)flushWindow;
- (void)flushWindowIfNeeded;
- (void)setViewsNeedDisplay:(BOOL)flag;
- (BOOL)viewsNeedDisplay;
- (void)displayIfNeeded;
- (void)display;
- (void)setAutodisplay:(BOOL)flag;
- (BOOL)isAutodisplay;

- (void)update;
- (BOOL)makeFirstResponder:(NSResponder *)aResponder;
- (NSResponder *)firstResponder;
- (int)resizeFlags;
- (void)keyDown:(NSEvent *)theEvent;
- (void)close;
- (void)setReleasedWhenClosed:(BOOL)flag;
- (BOOL)isReleasedWhenClosed;
- (void)miniaturize:(id)sender;
- (void)deminiaturize:(id)sender;
- (BOOL)isZoomed;
- (void)zoom:(id)sender;
- (BOOL)isMiniaturized;
- (BOOL)tryToPerform:(SEL)anAction with:(id)anObject;
- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType;
- (void)setBackgroundColor:(NSColor *)color;
- (NSColor *)backgroundColor;

- (void)setHidesOnDeactivate:(BOOL)flag;
- (BOOL)hidesOnDeactivate;
- (void)center;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)orderFront:(id)sender;
- (void)orderBack:(id)sender;
- (void)orderOut:(id)sender;
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(int)otherWin;
- (void)orderFrontRegardless;

- (void)setMiniwindowImage:(NSImage *)image;
- (void)setMiniwindowTitle:(NSString *)title;
- (NSImage *)miniwindowImage;
- (NSString *)miniwindowTitle;

- (void)setDocumentEdited:(BOOL)flag;
- (BOOL)isDocumentEdited;
- (BOOL)isVisible;
- (BOOL)isKeyWindow;
- (BOOL)isMainWindow;
- (BOOL)canBecomeKeyWindow;
- (BOOL)canBecomeMainWindow;
- (void)makeKeyWindow;
- (void)makeMainWindow;
- (void)becomeKeyWindow;
- (void)resignKeyWindow;
- (void)becomeMainWindow;
- (void)resignMainWindow;

- (BOOL)worksWhenModal;
- (NSPoint)convertBaseToScreen:(NSPoint)aPoint;
- (NSPoint)convertScreenToBase:(NSPoint)aPoint;
- (void)performClose:(id)sender;
- (void)performMiniaturize:(id)sender;
- (void)performZoom:(id)sender;
- (int)gState;
- (void)setOneShot:(BOOL)flag;
- (BOOL)isOneShot;
- (NSData *)dataWithEPSInsideRect:(NSRect)rect;
- (void)print:(id)sender;

#ifndef WIN32
- (void)fax:(id)sender;
#endif /* WIN32 */

- (void)disableCursorRects;
- (void)enableCursorRects;
- (void)discardCursorRects;
- (BOOL)areCursorRectsEnabled;
- (void)invalidateCursorRectsForView:(NSView *)aView;
- (void)resetCursorRects;

- (void)setBackingType:(NSBackingStoreType)bufferingType;
- (NSBackingStoreType)backingType;
- (void)setLevel:(int)newLevel;
- (int)level;
- (void)setDepthLimit:(NSWindowDepth)limit;
- (NSWindowDepth)depthLimit;
- (void)setDynamicDepthLimit:(BOOL)flag;
- (BOOL)hasDynamicDepthLimit;
- (NSScreen *)screen;
- (NSScreen *)deepestScreen;
- (BOOL)canStoreColor;

- (NSString *)stringWithSavedFrame;
- (void)setFrameFromString:(NSString *)string;
- (void)saveFrameUsingName:(NSString *)name;
- (BOOL)setFrameUsingName:(NSString *)name;
- (BOOL)setFrameAutosaveName:(NSString *)name;
- (NSString *)frameAutosaveName;
+ (void)removeFrameUsingName:(NSString *)name;

- (void)cacheImageInRect:(NSRect)aRect;
- (void)restoreCachedImage;
- (void)discardCachedImage;

- (NSSize)minSize;
- (NSSize)maxSize;
- (void)setMinSize:(NSSize)size;
- (void)setMaxSize:(NSSize)size;
- (NSEvent *)nextEventMatchingMask:(unsigned int)mask;
- (NSEvent *)nextEventMatchingMask:(unsigned int)mask untilDate:(NSDate *)expiration inMode:(NSString *)mode dequeue:(BOOL)deqFlag;
- (void)discardEventsMatchingMask:(unsigned int)mask beforeEvent:(NSEvent *)lastEvent;
- (void)postEvent:(NSEvent *)event atStart:(BOOL)flag;
- (NSEvent *)currentEvent;
- (void)setAcceptsMouseMovedEvents:(BOOL)flag;
- (BOOL)acceptsMouseMovedEvents;
- (NSDictionary *)deviceDescription;
- (void)sendEvent:(NSEvent *)theEvent;
- (NSPoint)mouseLocationOutsideOfEventStream;
+ (void)menuChanged:(NSMenu *)menu;

- (id)windowController;
- (void)setWindowController:(NSWindowController *)windowController;
@end

@interface NSWindow(NSKeyboardUI)
- (void)setInitialFirstResponder:(NSView *)view;
- (NSView *)initialFirstResponder;
- (void)selectNextKeyView:(id)sender;
- (void)selectPreviousKeyView:(id)sender;
- (void)selectKeyViewFollowingView:(NSView *)aView;
- (void)selectKeyViewPrecedingView:(NSView *)aView;
- (NSSelectionDirection)keyViewSelectionDirection;
- (void)setDefaultButtonCell:(NSButtonCell *)defButt;
- (NSButtonCell *)defaultButtonCell;
- (void)disableKeyEquivalentForDefaultButtonCell;
- (void)enableKeyEquivalentForDefaultButtonCell;
@end

@interface NSWindow(NSDrag)
- (void)dragImage:(NSImage *)anImage at:(NSPoint)baseLocation offset:(NSSize)initialOffset event:(NSEvent *)event pasteboard:(NSPasteboard *)pboard source:(id)sourceObj slideBack:(BOOL)slideFlag;

- (void)registerForDraggedTypes:(NSArray *)newTypes;
- (void)unregisterDraggedTypes;
@end

#ifdef WIN32
@interface NSWindow (NSWindowsExtensions)
- (void * /*HWND*/)windowHandle;
@end
#endif

@interface NSObject(NSWindowNotifications)
- (void)windowDidResize:(NSNotification *)notification;
- (void)windowDidExpose:(NSNotification *)notification;
- (void)windowWillMove:(NSNotification *)notification;
- (void)windowDidMove:(NSNotification *)notification;
- (void)windowDidBecomeKey:(NSNotification *)notification;
- (void)windowDidResignKey:(NSNotification *)notification;
- (void)windowDidBecomeMain:(NSNotification *)notification;
- (void)windowDidResignMain:(NSNotification *)notification;
- (void)windowWillClose:(NSNotification *)notification;
- (void)windowWillMiniaturize:(NSNotification *)notification;
- (void)windowDidMiniaturize:(NSNotification *)notification;
- (void)windowDidDeminiaturize:(NSNotification *)notification;
- (void)windowDidUpdate:(NSNotification *)notification;
- (void)windowDidChangeScreen:(NSNotification *)notification;
@end

@interface NSObject(NSWindowDelegate)
- (BOOL)windowShouldClose:(id)sender;
- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client;
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize;
- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)newFrame;
- (BOOL)windowShouldZoom:(NSWindow *)window toFrame:(NSRect)newFrame;
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window;
@end


/* Notifications */
APPKIT_EXTERN NSString *NSWindowDidBecomeKeyNotification;
APPKIT_EXTERN NSString *NSWindowDidBecomeMainNotification;
APPKIT_EXTERN NSString *NSWindowDidChangeScreenNotification;
APPKIT_EXTERN NSString *NSWindowDidDeminiaturizeNotification;
APPKIT_EXTERN NSString *NSWindowDidExposeNotification;			// userInfo key:  @"NSExposedRect"
APPKIT_EXTERN NSString *NSWindowDidMiniaturizeNotification;
APPKIT_EXTERN NSString *NSWindowDidMoveNotification;
APPKIT_EXTERN NSString *NSWindowDidResignKeyNotification;
APPKIT_EXTERN NSString *NSWindowDidResignMainNotification;
APPKIT_EXTERN NSString *NSWindowDidResizeNotification;
APPKIT_EXTERN NSString *NSWindowDidUpdateNotification;
APPKIT_EXTERN NSString *NSWindowWillCloseNotification;
APPKIT_EXTERN NSString *NSWindowWillMiniaturizeNotification;
APPKIT_EXTERN NSString *NSWindowWillMoveNotification;
