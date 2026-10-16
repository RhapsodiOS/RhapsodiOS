/*	NSControl.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSControl.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSMenu.h>
#import <Foundation/NSDictionary.h>

extern int _NSAppKitGlobalLock;
extern void _NSAppKitLock(int line, const char *file);
extern void _NSAppKitUnlock(int line, const char *file);

static NSMutableDictionary *NSControlCellClasses;

@implementation NSControl

+ (void)initialize
{
    if (self == [NSControl class])
        [self setVersion:41];
}

+ (Class)cellClass
{
    Class controlClass = self;
    Class cellClass = Nil;
    if (_NSAppKitGlobalLock)
        _NSAppKitLock(67, "NSControl.m");
    while (controlClass) {
        cellClass = [NSControlCellClasses objectForKey:controlClass];
        if (cellClass || controlClass == [NSObject class])
            break;
        controlClass = [controlClass superclass];
    }
    if (_NSAppKitGlobalLock)
        _NSAppKitUnlock(69, "NSControl.m");
    return cellClass;
}

+ (void)setCellClass:(Class)cellClass
{
    if (_NSAppKitGlobalLock)
        _NSAppKitLock(49, "NSControl.m");
    if (!NSControlCellClasses)
        NSControlCellClasses = [[NSMutableDictionary alloc] initWithCapacity:3];
    if (cellClass)
        [NSControlCellClasses setObject:cellClass forKey:self];
    else
        [NSControlCellClasses removeObjectForKey:self];
    if (_NSAppKitGlobalLock)
        _NSAppKitUnlock(58, "NSControl.m");
}

- (id)initWithFrame:(NSRect)frameRect
{
    Class cellClass = [[self class] cellClass];
    NSCell *cell = cellClass
        ? [[cellClass allocWithZone:[self zone]] initTextCell:@""]
        : nil;

    self = [super initWithFrame:frameRect];
    [self setCell:cell];
    [cell release];
    _conFlags.enabled = YES;
    _conFlags.calcSize = YES;
    return self;
}

- (void)dealloc
{
    [self abortEditing];
    [_cell release];
    _cell = nil;
    [super dealloc];
}

- (NSCell *)cell
{
    return _cell;
}

- (void)setCell:(NSCell *)cell
{
    if (cell == _cell)
        return;

    [_cell _setControlView:nil];
    [_cell release];
    _cell = [cell retain];
    [_cell _setControlView:self];
}

- (id)target
{
    return [_cell target];
}

- (void)setTarget:(id)target
{
    [_cell setTarget:target];
}

- (SEL)action
{
    return [_cell action];
}

- (void)setAction:(SEL)action
{
    [_cell setAction:action];
}

- (int)tag
{
    return _tag;
}

- (void)setTag:(int)tag
{
    _tag = tag;
}

- (BOOL)isEnabled
{
    return _cell ? [_cell isEnabled] : (_conFlags.enabled != 0);
}

- (void)setEnabled:(BOOL)enabled
{
    if (_cell) {
        if ([_cell isEnabled] == enabled)
            return;
        [_cell setEnabled:enabled];
        if ([_cell controlView] == self)
            return;
    } else {
        if (_conFlags.enabled == enabled)
            return;
        _conFlags.enabled = enabled;
    }

    if (!enabled)
        [self abortEditing];
    [self setNeedsDisplay:YES];
}

- (BOOL)isContinuous
{
    return [_cell isContinuous];
}

- (void)setContinuous:(BOOL)continuous
{
    [_cell setContinuous:continuous];
}

- (NSTextAlignment)alignment
{
    return [_cell alignment];
}

- (void)setAlignment:(NSTextAlignment)alignment
{
    [_cell setAlignment:alignment];
}

- (NSFont *)font
{
    return [_cell font];
}

- (void)setFont:(NSFont *)font
{
    [_cell setFont:font];
}

- (id)objectValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    return [_cell objectValue];
}

- (void)setObjectValue:(id)objectValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    [_cell setObjectValue:objectValue];
}

- (NSString *)stringValue
{
    if (!_cell)
        return @"";
    if ([_cell controlView] != self)
        [self validateEditing];
    return [_cell stringValue];
}

- (void)setStringValue:(NSString *)stringValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    [_cell setStringValue:stringValue];
}

- (int)intValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    return [_cell intValue];
}

- (void)setIntValue:(int)intValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    [_cell setIntValue:intValue];
}

- (float)floatValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    return [_cell floatValue];
}

- (void)setFloatValue:(float)floatValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    [_cell setFloatValue:floatValue];
}

- (double)doubleValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    return [_cell doubleValue];
}

- (void)setDoubleValue:(double)doubleValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    [_cell setDoubleValue:doubleValue];
}

- (NSCell *)selectedCell
{
    return _cell;
}

- (int)selectedTag
{
    return _cell ? [_cell tag] : -1;
}

- (BOOL)ignoresMultiClick
{
    return _conFlags.ignoreMultiClick;
}

- (void)setIgnoresMultiClick:(BOOL)ignoresMultiClick
{
    _conFlags.ignoreMultiClick = ignoresMultiClick;
}

- (BOOL)isOpaque
{
    return [_cell isOpaque];
}

- (BOOL)needsPanelToBecomeKey
{
    return [_cell needsPanelToBecomeKey];
}

- (void)performClick:(id)sender
{
    [_cell performClick:sender];
}

- (void)sizeToFit
{
    if (_cell) {
        NSSize size = [_cell cellSize];
        [self setFrameSize:size];
    }
}

- (void)setFrameSize:(NSSize)newSize
{
    NSSize oldSize = [self frame].size;
    if (oldSize.width != newSize.width || oldSize.height != newSize.height)
        [super setFrameSize:newSize];
}

- (void)calcSize
{
    if (_conFlags.calcSize) {
        [_cell calcDrawInfo:[self bounds]];
        _conFlags.calcSize = NO;
    }
}

- (void)setNeedsDisplay
{
    [super setNeedsDisplay:YES];
    _conFlags.calcSize = YES;
}

- (void)setFloatingPointFormat:(BOOL)autoRange left:(unsigned)leftDigits right:(unsigned)rightDigits
{
    if (_cell) {
        [_cell setFloatingPointFormat:autoRange left:leftDigits right:rightDigits];
        if ([_cell controlView] != self)
            [self updateCell:_cell];
    }
}

- (void)updateCell:(NSCell *)cell
{
    [self setNeedsDisplay:YES];
}

- (void)updateCellInside:(NSCell *)cell
{
    [self setNeedsDisplay:YES];
}

- (void)drawCell:(NSCell *)cell
{
    if (cell && cell == _cell)
        [self display];
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (!_cell)
        return;

    NSWindow *window = [self window];
    BOOL highlight = NO;
    if ([window firstResponder] == self)
        highlight = [window isKeyWindow];

    [_cell highlight:highlight withFrame:[self bounds] inView:self];
    [_cell drawWithFrame:[self bounds] inView:self];
    [_cell highlight:NO withFrame:[self bounds] inView:self];
}

- (int)mouseDownFlags
{
    return [_cell mouseDownFlags];
}

- (void)resetCursorRects
{
    NSRect rect = [self bounds];
    if (!NSIsEmptyRect(rect))
        [_cell resetCursorRect:rect inView:self];
}

- (void)rightMouseDown:(NSEvent *)event
{
    [self mouseDown:event];
}

- (void)selectCell:(NSCell *)cell
{
    if (cell && cell == _cell && ![cell target]) {
        [cell setState:![cell target]];
        [self updateCell:_cell];
    }
}

- (BOOL)becomeFirstResponder
{
    [self setNeedsDisplay:YES];
    if ([_cell respondsToSelector:@selector(setShowsFirstResponder:)])
        [_cell setShowsFirstResponder:YES];
    return YES;
}

- (BOOL)resignFirstResponder
{
    [self setNeedsDisplay:YES];
    if ([_cell respondsToSelector:@selector(setShowsFirstResponder:)])
        [_cell setShowsFirstResponder:NO];
    return YES;
}

- (void)becomeKeyWindow
{
    if ([[self window] firstResponder] == self) {
        [self setNeedsDisplay:YES];
        if ([_cell respondsToSelector:@selector(setShowsFirstResponder:)])
            [_cell setShowsFirstResponder:YES];
    }
}

- (void)resignKeyWindow
{
    if ([[self window] firstResponder] == self) {
        [self setNeedsDisplay:YES];
        if ([_cell respondsToSelector:@selector(setShowsFirstResponder:)])
            [_cell setShowsFirstResponder:NO];
    }
}

- (BOOL)acceptsFirstResponder
{
    return [_cell acceptsFirstResponder];
}

- (BOOL)_hasEditableCell
{
    return _cell && [_cell isEditable] && [_cell isSelectable];
}

- (BOOL)refusesFirstResponder
{
    return [_cell refusesFirstResponder];
}

- (void)setRefusesFirstResponder:(BOOL)refusesFirstResponder
{
    [_cell setRefusesFirstResponder:refusesFirstResponder];
}

- (NSInteger)sendActionOn:(NSInteger)mask
{
    return [_cell sendActionOn:mask];
}

- (BOOL)sendAction:(SEL)action to:(id)target
{
    return [[NSApplication sharedApplication] sendAction:action to:target from:self];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSMenu *menu = [_cell menuForEvent:event inRect:[self bounds] ofView:self];
    return menu ? menu : [super menuForEvent:event];
}

- (void)takeIntValueFrom:(id)sender
{
    [self setIntValue:[sender intValue]];
}

- (void)takeFloatValueFrom:(id)sender
{
    [self setFloatValue:[sender floatValue]];
}

- (void)takeDoubleValueFrom:(id)sender
{
    [self setDoubleValue:[sender doubleValue]];
}

- (void)takeStringValueFrom:(id)sender
{
    [self setStringValue:[sender stringValue]];
}

- (void)takeObjectValueFrom:(id)sender
{
    [self setObjectValue:[sender objectValue]];
}

- (NSText *)currentEditor
{
    NSText *editor = [[self window] fieldEditor:NO forObject:self];
    id delegate = [editor delegate];
    if (delegate != self)
        delegate = [delegate delegate];
    return delegate == self ? editor : nil;
}

- (BOOL)abortEditing
{
    NSText *editor = [self currentEditor];
    if (editor) {
        [editor setDelegate:nil];
        [[self window] endEditingFor:nil];
        NSCell *cell = _cell ? _cell : [self cell];
        [cell endEditing:editor];
    }
    return editor != nil;
}

- (void)validateEditing
{
    NSText *editor = [self currentEditor];
    if (editor)
        [self _validateEditing:editor];
}

- (void)_validateEditing:(NSText *)editor
{
    NSCell *cell = _cell ? _cell : [self cell];
    if ([cell allowsEditingTextAttributes]
        && [editor isKindOfClass:[NSTextView class]]) {
        cell = _cell ? _cell : [self cell];
        [cell setAttributedStringValue:[(NSTextView *)editor textStorage]];
    } else {
        cell = _cell ? _cell : [self cell];
        [cell setStringValue:[editor string]];
    }
}

- (NSAttributedString *)attributedStringValue
{
    if (!_cell)
        return [[[NSAttributedString alloc] initWithString:@""] autorelease];
    if ([_cell controlView] != self)
        [self validateEditing];
    return [_cell attributedStringValue];
}

- (void)setAttributedStringValue:(NSAttributedString *)attributedStringValue
{
    if (_cell && [_cell controlView] != self)
        [self validateEditing];
    [_cell setAttributedStringValue:attributedStringValue];
}

@end

