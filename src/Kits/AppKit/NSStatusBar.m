/*	NSStatusBar.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSStatusBar.h>
#import <AppKit/NSStatusItem.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/dpsclient.h>

@interface NSStatusBar (NSStatusBarPrivate)
- (id)_init;
- (id)_name;
- (id)_lockName;
- (id)_statusItemWithLength:(float)length withPriority:(int)priority;
- (void)_insertStatusItemWindow:(NSWindow *)window withPriority:(int)priority;
- (void)_removeStatusItemWindow:(NSWindow *)window;
- (void)_refreshWindows;
- (void)_setLength:(float)length ofStatusItemWindow:(NSWindow *)window;
- (void)_DPSsetupInfo;
- (void)_DPSinsertWindow:(NSWindow *)window withPriority:(int)priority;
- (void)_DPSremoveWindow:(NSWindow *)window;
- (void)_DPSadjustWindows;
- (NSPoint)_cornerLocationForWindowWithSize:(NSSize)size;
- (NSWindow *)_createStatusItemWindow;
- (NSView *)_createStatusItemControlInWindow:(NSWindow *)window;
- (int)_direction;
- (int)_placement;
- (NSPoint)_initialOffset;
- (float)_lengthForSize:(NSSize)size;
@end

@interface NSStatusBarWindow : NSWindow
- (BOOL)_showToolTip;
- (id)initWithContentRect:(NSRect)rect;
@end

@interface NSStatusBarButtonCell : NSButtonCell
{
    NSStatusBar *_fStatusBar;
    NSMenu *_fStatusMenu;
    BOOL _fHighlightMode;
}
- (void)setStatusBar:(NSStatusBar *)statusBar;
- (NSMenu *)statusMenu;
- (void)setStatusMenu:(NSMenu *)menu;
- (BOOL)highlightMode;
- (void)setHighlightMode:(BOOL)highlightMode;
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (void)_fillBackground:(NSRect)rect withAlternateColor:(BOOL)alternate;
- (NSColor *)_textHighlightColor;
- (BOOL)trackMouse:(NSEvent *)event inRect:(NSRect)cellFrame
            ofView:(NSView *)controlView untilMouseUp:(BOOL)untilMouseUp;
@end

@interface NSStatusBarButton : NSButton
- (id)initWithFrame:(NSRect)frame inStatusBar:(NSStatusBar *)statusBar;
- (BOOL)highlightMode;
- (void)setHighlightMode:(BOOL)highlightMode;
- (NSMenu *)statusMenu;
- (void)setStatusMenu:(NSMenu *)menu;
@end

@interface NSStatusItem (NSStatusBarPrivate)
+ (id)_itemInStatusBar:(NSStatusBar *)statusBar withLength:(float)length withPriority:(int)priority;
- (NSWindow *)_window;
@end

extern void SBPSinsertwindow(const char *name, const char *lockName, int windowNumber, int priority);
extern void SBPSremovewindow(const char *name, const char *lockName, int windowNumber);
extern void SBPSadjustwindows(const char *name, const char *lockName);
extern void _NSSetAttachedMenu(id context, NSWindow *window, NSMenu *menu);

static NSStatusBar *systemStatusBar = nil;

@implementation NSStatusBar

+ (NSStatusBar *)systemStatusBar
{
    if (systemStatusBar == nil)
        systemStatusBar = [[[self alloc] _init] retain];
    return systemStatusBar;
}

- (BOOL)isVertical
{
    return [self _direction] == 1;
}

- (NSStatusItem *)statusItemWithLength:(float)length
{
    return [self _statusItemWithLength:length withPriority:1000];
}

- (void)removeStatusItem:(NSStatusItem *)item
{
    [self _removeStatusItemWindow:[item _window]];
}

- (float)thickness
{
    return [NSMenuView menuBarHeight];
}

@end

@implementation NSStatusBar (NSStatusBar_Private)

- (id)_init
{
    self = [super init];
    if (self != nil)
        [self _DPSsetupInfo];
    return self;
}

- (id)_name
{
    return nil;
}

- (id)_lockName
{
    return nil;
}

- (id)_statusItemWithLength:(float)length withPriority:(int)priority
{
    return [NSStatusItem _itemInStatusBar:self withLength:length withPriority:priority];
}

- (void)_insertStatusItemWindow:(NSWindow *)window withPriority:(int)priority
{
    [self _DPSinsertWindow:window withPriority:priority];
}

- (void)_removeStatusItemWindow:(NSWindow *)window
{
    [self _DPSremoveWindow:window];
}

- (void)_refreshWindows
{
    [self _DPSadjustWindows];
}

@end

@implementation NSStatusBar (NSStatusBar_Appearance)

- (float)_lengthForSize:(NSSize)size
{
    return [self isVertical] ? size.height : size.width;
}

- (int)_direction
{
    return 1;
}

- (int)_placement
{
    return 0;
}

- (NSPoint)_initialOffset
{
    return NSMakePoint(-8.0f, 0.0f);
}

@end

@implementation NSStatusBar (NSStatusBarDPS)

- (NSPoint)_cornerLocationForWindowWithSize:(NSSize)size
{
    NSRect screen = [[NSScreen mainScreen] frame];
    NSPoint offset = [self _initialOffset];
    NSPoint point = screen.origin;

    switch ([self _placement]) {
        case 1:
            point.x = NSMinX(screen);
            point.y = NSMaxY(screen) - size.height;
            break;
        case 2:
            point.x = NSMaxX(screen) - size.width;
            point.y = NSMaxY(screen) - size.height;
            break;
        case 3:
            point.x = NSMinX(screen);
            point.y = NSMinY(screen);
            break;
        case 4:
            point.x = NSMaxX(screen) - size.width;
            point.y = NSMinY(screen);
            break;
        default:
            point.y = NSMaxY(screen) - size.height;
            break;
    }
    point.x += offset.x;
    point.y += offset.y;
    return point;
}

@end

@implementation NSStatusBar (NSStatusBar_Appearance)

- (NSWindow *)_createStatusItemWindow
{
    NSSize size = [self isVertical]
        ? NSMakeSize([self thickness], 0.0f)
        : NSMakeSize(0.0f, [self thickness]);
    NSPoint origin = [self _cornerLocationForWindowWithSize:size];
    return [[NSStatusBarWindow alloc] initWithContentRect:NSMakeRect(origin.x, origin.y,
                                                                      size.width, size.height)];
}

- (NSView *)_createStatusItemControlInWindow:(NSWindow *)window
{
    NSRect frame = [window frame];
    NSStatusBarButton *button = [[NSStatusBarButton alloc] initWithFrame:frame inStatusBar:self];
    [window setContentView:button];
    return button;
}

@end

@implementation NSStatusBar (NSStatusBar_Private)

- (void)_setLength:(float)length ofStatusItemWindow:(NSWindow *)window
{
    NSRect frame = [window frame];
    float oldLength = [self isVertical] ? frame.size.height : frame.size.width;
    if (length == oldLength)
        return;

    int placement = [self _placement];
    if ([self isVertical]) {
        if (placement == 1 || placement == 2)
            frame.origin.y -= length - frame.size.height;
        frame.size.width = [self thickness];
        frame.size.height = length;
    } else {
        if (placement == 2 || placement == 4)
            frame.origin.x -= length - frame.size.width;
        frame.size.width = length;
        frame.size.height = [self thickness];
    }
    [window setFrame:frame display:NO];
    [window invalidateCursorRectsForView:[window contentView]];
    [self _refreshWindows];
}

@end

@implementation NSStatusBar (NSStatusBarDPS)

- (void)_DPSsetupInfo
{
    DPSContext context = DPSGetCurrentContext();
    if (context == NULL)
        return;

    NSRect screen = [[NSScreen mainScreen] frame];
    NSSize statusSize = [self isVertical]
        ? NSMakeSize([self thickness], screen.size.height)
        : NSMakeSize(screen.size.width, [self thickness]);
    NSPoint origin = [self _cornerLocationForWindowWithSize:statusSize];
    const char *name = [[self _name] cString];
    const char *lockName = [[self _lockName] cString];
    DPSPrintf(context,
              "nextdict /%s known not {currentshared true setshared "
              "nextdict /%s [[-1 -1 %d %f %f]] put nextdict /%s lock "
              "put setshared} if\n",
              name ? name : "", name ? name : "", [self _direction],
              origin.x, origin.y, lockName ? lockName : "");
}

- (void)_DPSinsertWindow:(NSWindow *)window withPriority:(int)priority
{
    const char *name = [[self _name] cString];
    const char *lockName = [[self _lockName] cString];
    SBPSinsertwindow(name, lockName, (int)[window windowNumber], priority);
    SBPSadjustwindows(name, lockName);
}

- (void)_DPSremoveWindow:(NSWindow *)window
{
    const char *name = [[self _name] cString];
    const char *lockName = [[self _lockName] cString];
    SBPSremovewindow(name, lockName, (int)[window windowNumber]);
    SBPSadjustwindows(name, lockName);
}

- (void)_DPSadjustWindows
{
    SBPSadjustwindows([[self _name] cString], [[self _lockName] cString]);
}

@end

@implementation NSStatusBar (NSStatusBar_Appearance)

- (void)drawBackgroundInRect:(NSRect)rect inView:(NSView *)view highlight:(BOOL)highlight
{
}

@end

@implementation NSStatusBarButton

- (id)initWithFrame:(NSRect)frame inStatusBar:(NSStatusBar *)statusBar
{
    [NSStatusBarButton setCellClass:[NSStatusBarButtonCell class]];
    self = [super initWithFrame:frame];
    if (self != nil) {
        [[self cell] setStatusBar:statusBar];
        [self setBordered:YES];
        [self setTransparent:NO];
        [self setEnabled:YES];
        [self setShowsBorderOnlyWhileMouseInside:NO];
        [self setBezelStyle:NSRegularSquareBezelStyle];
        [self setImagePosition:NSImageOnly];
    }
    return self;
}

- (BOOL)highlightMode
{
    return [(NSStatusBarButtonCell *)[self cell] highlightMode];
}

- (void)setHighlightMode:(BOOL)highlightMode
{
    [(NSStatusBarButtonCell *)[self cell] setHighlightMode:highlightMode];
}

- (NSMenu *)statusMenu
{
    return [(NSStatusBarButtonCell *)[self cell] statusMenu];
}

- (void)setStatusMenu:(NSMenu *)menu
{
    [(NSStatusBarButtonCell *)[self cell] setStatusMenu:menu];
}

@end

@implementation NSStatusBarButtonCell

- (void)setStatusBar:(NSStatusBar *)statusBar
{
    _fStatusBar = statusBar;
}

- (NSMenu *)statusMenu
{
    return _fStatusMenu;
}

- (void)setStatusMenu:(NSMenu *)menu
{
    if (_fStatusMenu == menu)
        return;
    [_fStatusMenu release];
    _fStatusMenu = [menu retain];
}

- (BOOL)highlightMode
{
    return _fHighlightMode;
}

- (void)setHighlightMode:(BOOL)highlightMode
{
    _fHighlightMode = highlightMode;
    [self setHighlightsBy:highlightMode ? 4 : 0];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    BOOL highlight = [self isEnabled] && _fHighlightMode;
    [_fStatusBar drawBackgroundInRect:cellFrame inView:controlView highlight:highlight];
    [super drawWithFrame:cellFrame inView:controlView];
}

- (void)_fillBackground:(NSRect)rect withAlternateColor:(BOOL)alternate
{
}

- (NSColor *)_textHighlightColor
{
    return [NSColor selectedControlColor];
}

- (BOOL)trackMouse:(NSEvent *)event inRect:(NSRect)cellFrame
            ofView:(NSView *)controlView untilMouseUp:(BOOL)untilMouseUp
{
    NSMenu *menu = _fStatusMenu;
    if (menu == nil)
        return [super trackMouse:event inRect:cellFrame ofView:controlView untilMouseUp:untilMouseUp];
    [menu update];
    NSMenu *attachedMenu = [menu attachedMenu];
    NSMenuView *menuView = (NSMenuView *)[attachedMenu menuRepresentation];
    [menuView update];
    _NSSetAttachedMenu(nil, [controlView window], attachedMenu);
    return [menuView trackWithEvent:event];
}

@end

@implementation NSStatusBarWindow

- (BOOL)_showToolTip
{
    return YES;
}

- (id)initWithContentRect:(NSRect)rect
{
    self = [super initWithContentRect:rect styleMask:0 backing:NSBackingStoreBuffered defer:NO];
    if (self != nil) {
        [self setAcceptsMouseMovedEvents:YES];
        [self setLevel:21];
    }
    return self;
}

@end
