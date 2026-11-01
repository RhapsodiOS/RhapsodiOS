/*	NSStatusItem.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSStatusItem.h>
#import <AppKit/NSStatusBar.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSException.h>

@interface NSStatusBar (NSStatusItemPrivate)
- (NSWindow *)_createStatusItemWindow;
- (NSView *)_createStatusItemControlInWindow:(NSWindow *)window;
- (void)_insertStatusItemWindow:(NSWindow *)window withPriority:(int)priority;
- (void)_refreshWindows;
- (void)_setLength:(float)length ofStatusItemWindow:(NSWindow *)window;
- (float)_lengthForSize:(NSSize)size;
@end

@interface NSObject (NSStatusItemButton)
- (void)setStatusMenu:(NSMenu *)menu;
- (NSMenu *)statusMenu;
@end

@interface NSStatusItem (NSStatusItem_Private)
- (id)_initInStatusBar:(NSStatusBar *)statusBar withLength:(float)length withPriority:(int)priority;
- (NSButton *)_button;
- (NSWindow *)_window;
- (void)_adjustLength;
@end

@interface NSButton (NSStatusItemPrivateButton)
- (BOOL)highlightMode;
- (void)setHighlightMode:(BOOL)highlightMode;
@end

@implementation NSStatusItem

- (NSStatusBar *)statusBar
{
    return _fStatusBar;
}

@end

@implementation NSStatusItem (NSStatusItemCommon)

- (SEL)action
{
    return [[self _button] action];
}

- (void)setAction:(SEL)action
{
    [[self _button] setAction:action];
}

- (NSString *)title
{
    return [[self _button] title];
}

- (void)setTitle:(NSString *)title
{
    [[self _button] setTitle:title];
    [self _adjustLength];
}

- (NSAttributedString *)attributedTitle
{
    return [[self _button] attributedTitle];
}

- (void)setAttributedTitle:(NSAttributedString *)title
{
    [[self _button] setAttributedTitle:title];
    [self _adjustLength];
}

- (NSImage *)image
{
    return [[self _button] image];
}

- (void)setImage:(NSImage *)image
{
    NSButton *button = [self _button];
    [button setImage:image];
    [button setAlternateImage:image];
    [button setImagePosition:(image != nil) ? NSImageLeft : NSNoImage];
    [self _adjustLength];
}

- (NSMenu *)menu
{
    return [[self _button] statusMenu];
}

- (void)setMenu:(NSMenu *)menu
{
    [[self _button] setStatusMenu:menu];
}

- (BOOL)isEnabled
{
    return [[self _button] isEnabled];
}

- (void)setEnabled:(BOOL)enabled
{
    [[self _button] setEnabled:enabled];
}

- (NSString *)toolTip
{
    return [[self _button] toolTip];
}

- (void)setToolTip:(NSString *)toolTip
{
    [[self _button] setToolTip:toolTip];
}

- (BOOL)highlightMode
{
    return [[self _button] highlightMode];
}

- (void)setHighlightMode:(BOOL)highlightMode
{
    [[self _button] setHighlightMode:highlightMode];
}

- (NSInteger)sendActionOn:(NSInteger)mask
{
    return [[self _button] sendActionOn:mask];
}

@end

@implementation NSStatusItem (NSStatusItemView)

- (NSView *)view
{
    return _fFlags.customView ? _fView : nil;
}

- (void)setView:(NSView *)view
{
    [_fView removeFromSuperview];
    [_fView release];
    _fView = [view retain];
    _fFlags.customView = (view != nil);

    if (view != nil) {
        [_fWindow setContentView:view];
        if (_fLength == NSSquareStatusItemLength) {
            NSRect frame = [view frame];
            if ([_fStatusBar isVertical])
                frame.size.height = [_fStatusBar thickness];
            else
                frame.size.width = [_fStatusBar thickness];
            [view setFrame:frame];
        }
        [self _adjustLength];
        [_fStatusBar _refreshWindows];
    }
}

@end

@implementation NSStatusItem (NSStatusItem_Private)

+ (id)_itemInStatusBar:(NSStatusBar *)statusBar withLength:(float)length withPriority:(int)priority
{
    NSStatusItem *item = [[self alloc] _initInStatusBar:statusBar
                                             withLength:length
                                            withPriority:priority];
    return [item autorelease];
}

- (id)_initInStatusBar:(NSStatusBar *)statusBar withLength:(float)length withPriority:(int)priority
{
    self = [super init];
    if (self == nil)
        return nil;
    if (length > 10000.0f)
        [NSException raise:NSInvalidArgumentException
                    format:@"Status item length %f exceeds the maximum of 10000.", length];

    _fStatusBar = statusBar;
    _fLength = length;
    _fPriority = priority;
    _fFlags.customView = NO;
    _fView = nil;
    _fWindow = [_fStatusBar _createStatusItemWindow];
    [_fStatusBar _insertStatusItemWindow:_fWindow withPriority:_fPriority];
    return self;
}

- (NSWindow *)_window
{
    return _fWindow;
}

- (NSButton *)_button
{
    if (_fFlags.customView)
        return nil;
    if (_fView == nil)
        _fView = [[_fStatusBar _createStatusItemControlInWindow:_fWindow] retain];
    return (NSButton *)_fView;
}

- (void)_adjustLength
{
    float length = _fLength;
    if (length == NSVariableStatusItemLength) {
        NSSize size;
        if (_fFlags.customView) {
            size = [_fView frame].size;
        } else {
            size = [[_fView cell] cellSize];
        }
        length = [_fStatusBar _lengthForSize:size];
    } else if (length == NSSquareStatusItemLength) {
        float thickness = [_fStatusBar thickness];
        length = [_fStatusBar _lengthForSize:NSMakeSize(thickness, thickness)];
    }

    [_fStatusBar _setLength:length ofStatusItemWindow:_fWindow];
    [_fView setNeedsDisplay:YES];
}

@end

