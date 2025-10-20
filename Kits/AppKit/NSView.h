/*
	NSView.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <Foundation/Foundation.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <AppKit/AppKitDefines.h>

@class NSCursor;
@class NSScrollView;
@class NSEvent;

enum {
    NSViewNotSizable			=  0,
    NSViewMinXMargin			=  1,
    NSViewWidthSizable			=  2,
    NSViewMaxXMargin			=  4,
    NSViewMinYMargin			=  8,
    NSViewHeightSizable			= 16,
    NSViewMaxYMargin			= 32
};

typedef enum _NSBorderType {
    NSNoBorder				= 0,
    NSLineBorder			= 1,
    NSBezelBorder			= 2,
    NSGrooveBorder			= 3
} NSBorderType;

typedef struct __VFlags {
#ifdef __BIG_ENDIAN__
	unsigned int        rotatedFromBase:1;
	unsigned int        rotatedOrScaledFromBase:1;
	unsigned int        autosizing:6;
	unsigned int        autoresizeSubviews:1;
	unsigned int        wantsGState:1;
	unsigned int        needsDisplay:1;
	unsigned int        validGState:1;
	unsigned int        newGState:1;
	unsigned int        noVerticalAutosizing:1;
	unsigned int        frameChangeNotesSuspended:1;
	unsigned int        needsFrameChangeNote:1;
	unsigned int        focusChangeNotesSuspended:1;
	unsigned int        boundsChangeNotesSuspended:1;
	unsigned int        needsBoundsChangeNote:1;
	unsigned int        removingWithoutInvalidation:1;
        unsigned int        interfaceStyle0:1;
	unsigned int        needsDisplayForBounds:1;
	unsigned int        specialArchiving:1;
	unsigned int        interfaceStyle1:1;
	unsigned int        retainCount:6;
	unsigned int        retainCountOverMax:1;
	unsigned int        aboutToResize:1;
#else
	unsigned int        aboutToResize:1;
	unsigned int        retainCountOverMax:1;
	unsigned int        retainCount:6;
	unsigned int        interfaceStyle1:1;
	unsigned int        specialArchiving:1;
	unsigned int        needsDisplayForBounds:1;
	unsigned int        interfaceStyle0:1;
        unsigned int        removingWithoutInvalidation:1;
	unsigned int        needsBoundsChangeNote:1;
	unsigned int        boundsChangeNotesSuspended:1;
	unsigned int        focusChangeNotesSuspended:1;
	unsigned int        needsFrameChangeNote:1;
	unsigned int        frameChangeNotesSuspended:1;
	unsigned int        noVerticalAutosizing:1;
	unsigned int        newGState:1;
	unsigned int        validGState:1;
	unsigned int        needsDisplay:1;
	unsigned int        wantsGState:1;
	unsigned int        autoresizeSubviews:1;
	unsigned int        autosizing:6;
	unsigned int        rotatedOrScaledFromBase:1;
	unsigned int        rotatedFromBase:1;
#endif
} _VFlags;

typedef int NSTrackingRectTag;

struct __NSViewAuxiliary;
typedef struct __NSViewAuxiliary _NSViewAuxiliary;

@interface NSView : NSResponder
{
    /*All instance variables are private*/
    NSRect              _frame;
    NSRect              _bounds;
    id                  _superview;
    NSMutableArray      *_subviews;
    NSWindow            *_window;
    int                 _gState;
    id                  _frameMatrix;
    id			_drawMatrix;
    NSMutableSet	*_dragTypes;
    _NSViewAuxiliary	*_viewAuxiliary;
    _VFlags		_vFlags;
    struct __VFlags2 {
	unsigned int	nextKeyViewRefCount:14;
	unsigned int	previousKeyViewRefCount:14;
	unsigned int	clippedFocus:1;
	unsigned int	hasToolTip:1;
	unsigned int	needsRealLockFocus:1;
	unsigned int	menuWasSet:1;
    } _vFlags2;
}


- (id)initWithFrame:(NSRect)frameRect;

- (NSWindow *)window;
- (NSView *)superview;
- (NSArray *)subviews;
- (BOOL)isDescendantOf:(NSView *)aView;
- (NSView *)ancestorSharedWithView:(NSView *)aView;
- (NSView *)opaqueAncestor;
- (void)addSubview:(NSView *)aView;
- (void)addSubview:(NSView *)aView positioned:(NSWindowOrderingMode)place relativeTo:(NSView *)otherView;
- (void)sortSubviewsUsingFunction:(int (*)(id, id, void *))compare context:(void *)context;
- (void)viewWillMoveToWindow:(NSWindow *)newWindow;
- (void)viewWillMoveToSuperview:(NSView *)newSuperview;
- (void)didAddSubview:(NSView *)subview;
- (void)willRemoveSubview:(NSView *)subview;
- (void)removeFromSuperview;
- (void)replaceSubview:(NSView *)oldView with:(NSView *)newView;
- (void)removeFromSuperviewWithoutNeedingDisplay;

- (void)setPostsFrameChangedNotifications:(BOOL)flag;
- (BOOL)postsFrameChangedNotifications;
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize;
- (void)resizeWithOldSuperviewSize:(NSSize)oldSize;
- (void)setAutoresizesSubviews:(BOOL)flag;
- (BOOL)autoresizesSubviews;
- (void)setAutoresizingMask:(unsigned int)mask;
- (unsigned int)autoresizingMask;

- (void)setFrameOrigin:(NSPoint)newOrigin;
- (void)setFrameSize:(NSSize)newSize;
- (void)setFrame:(NSRect)frameRect;
- (NSRect)frame;
- (void)setFrameRotation:(float)angle;
- (float)frameRotation;

- (void)setBoundsOrigin:(NSPoint)newOrigin;
- (void)setBoundsSize:(NSSize)newSize;
- (void)setBoundsRotation:(float)angle;
- (float)boundsRotation;
- (void)translateOriginToPoint:(NSPoint)translation;
- (void)scaleUnitSquareToSize:(NSSize)newUnitSize;
- (void)rotateByAngle:(float)angle;
- (void)setBounds:(NSRect)aRect;
- (NSRect)bounds;

- (BOOL)isFlipped;
- (BOOL)isRotatedFromBase;
- (BOOL)isRotatedOrScaledFromBase;
- (BOOL)isOpaque;

- (NSPoint)convertPoint:(NSPoint)aPoint fromView:(NSView *)aView;
- (NSPoint)convertPoint:(NSPoint)aPoint toView:(NSView *)aView;
- (NSSize)convertSize:(NSSize)aSize fromView:(NSView *)aView;
- (NSSize)convertSize:(NSSize)aSize toView:(NSView *)aView;
- (NSRect)convertRect:(NSRect)aRect fromView:(NSView *)aView;
- (NSRect)convertRect:(NSRect)aRect toView:(NSView *)aView;
- (NSRect)centerScanRect:(NSRect)aRect;

- (BOOL)canDraw;
- (void)setNeedsDisplay:(BOOL)flag;
- (void)setNeedsDisplayInRect:(NSRect)invalidRect;
- (BOOL)needsDisplay;
- (void)lockFocus;
- (void)unlockFocus;
- (BOOL)lockFocusIfCanDraw;
+ (NSView *)focusView;
- (NSRect)visibleRect;

- (void)display;
- (void)displayIfNeeded;
- (void)displayIfNeededIgnoringOpacity;
- (void)displayRect:(NSRect)rect;
- (void)displayIfNeededInRect:(NSRect)rect;
- (void)displayRectIgnoringOpacity:(NSRect)rect;
- (void)displayIfNeededInRectIgnoringOpacity:(NSRect)rect;
- (void)drawRect:(NSRect)rect;

- (int)gState;
- (void)allocateGState;
- (void)releaseGState;
- (void)setUpGState;
- (void)renewGState;

- (void)scrollPoint:(NSPoint)aPoint;
- (BOOL)scrollRectToVisible:(NSRect)aRect;
- (BOOL)autoscroll:(NSEvent *)theEvent;
- (NSRect)adjustScroll:(NSRect)newVisible;
- (void)scrollRect:(NSRect)aRect by:(NSSize)delta;

- (NSView *)hitTest:(NSPoint)aPoint;
- (BOOL)mouse:(NSPoint)aPoint inRect:(NSRect)aRect;
- (id)viewWithTag:(int)aTag;
- (int)tag;
- (BOOL)performKeyEquivalent:(NSEvent *)theEvent;
- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)theEvent;
- (BOOL)needsPanelToBecomeKey;

- (void)addCursorRect:(NSRect)aRect cursor:(NSCursor *)anObj;
- (void)removeCursorRect:(NSRect)aRect cursor:(NSCursor *)anObj;
- (void)discardCursorRects;
- (void)resetCursorRects;

- (NSTrackingRectTag)addTrackingRect:(NSRect)aRect owner:(id)anObject userData:(void *)data assumeInside:(BOOL)flag;
- (void)removeTrackingRect:(NSTrackingRectTag)tag;

- (BOOL)shouldDrawColor;

- (void)setPostsBoundsChangedNotifications:(BOOL)flag;
- (BOOL)postsBoundsChangedNotifications;

- (NSScrollView *)enclosingScrollView;

- (NSMenu *)menuForEvent:(NSEvent *)event;
+ (NSMenu *)defaultMenu;

- (void)setToolTip:(NSString *)string;
- (NSString *)toolTip;

@end

@interface NSView(NSKeyboardUI)
- (BOOL)performMnemonic:(NSString *)theString;
- (void)setNextKeyView:(NSView *)next;
- (NSView *)nextKeyView;
- (NSView *)previousKeyView;
- (NSView *)nextValidKeyView;
- (NSView *)previousValidKeyView;
@end

@interface NSView(NSPrinting)

- (void)writeEPSInsideRect:(NSRect)rect toPasteboard:(NSPasteboard *)pasteboard;
- (NSData *)dataWithEPSInsideRect:(NSRect)rect;
- (void)print:(id)sender;
- (BOOL)knowsPageRange:(NSRangePointer)range;
- (void)beginPrologueBBox:(NSRect)boundingBox creationDate:(NSString *)dateCreated createdBy:(NSString *)anApplication fonts:(NSString *)fontNames forWhom:(NSString *)user pages:(int)numPages title:(NSString *)aTitle;
- (void)endHeaderComments;
- (void)endPrologue;
- (void)beginSetup;
- (void)endSetup;
- (void)beginPage:(int)ordinalNum label:(NSString *)aString bBox:(NSRect)pageRect fonts:(NSString *)fontNames;
- (void)beginPageSetupRect:(NSRect)aRect placement:(NSPoint)location;
- (void)addToPageSetup;
- (void)endPageSetup;
- (void)endPage;
- (void)beginTrailer;
- (void)endTrailer;
- (float)heightAdjustLimit;
- (float)widthAdjustLimit;
- (void)adjustPageWidthNew:(float *)newRight left:(float)oldLeft right:(float)oldRight limit:(float)rightLimit;
- (void)adjustPageHeightNew:(float *)newBottom top:(float)oldTop bottom:(float)oldBottom limit:(float)bottomLimit;
- (NSRect)rectForPage:(int)page;
- (NSPoint)locationOfPrintRect:(NSRect)aRect;
- (void)drawSheetBorderWithSize:(NSSize)borderSize;
- (void)drawPageBorderWithSize:(NSSize)borderSize;

#ifndef WIN32
// Mach-only non-openstep API.
- (void)fax:(id)sender;
#endif

@end


@interface NSView(NSDrag)
- (void)dragImage:(NSImage *)anImage at:(NSPoint)viewLocation offset:(NSSize)initialOffset event:(NSEvent *)event pasteboard:(NSPasteboard *)pboard source:(id)sourceObj slideBack:(BOOL)slideFlag;

- (void)registerForDraggedTypes:(NSArray *)newTypes;
- (void)unregisterDraggedTypes;

- (BOOL)dragFile:(NSString *)filename fromRect:(NSRect)rect slideBack:(BOOL)aFlag event:(NSEvent *)event;

@end

/* Notifications */

APPKIT_EXTERN NSString *NSViewFrameDidChangeNotification;
APPKIT_EXTERN NSString *NSViewFocusDidChangeNotification;
APPKIT_EXTERN NSString *NSViewBoundsDidChangeNotification;
    // This notification is sent whenever the views bounds change and the frame does not.  That is, it is sent whenever the view's bounds are translated, scaled or rotated, but NOT when the bounds change as a result of, for example, setFrameSize:.

