/*	NSTextContainer.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSTextContainer.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>

@interface NSTextContainer (NSPrivate)
- (BOOL)_containerObservesTextViewFrameChanges;
- (void)_containerTextViewFrameChanged:(NSNotification *)notification;
- (void)_resizeAccordingToTextView:(NSTextView *)textView;
- (void)_setContainerObservesTextViewFrameChanges:(BOOL)observesChanges;
@end

@implementation NSTextContainer

- (id)initWithContainerSize:(NSSize)size
{
    self = [super init];
    if (self) {
        _layoutManager = nil;
        _textView = nil;
        _size = size;
        _lineFragmentPadding = 5.0f;
        _tcFlags.widthTracksTextView = NO;
        _tcFlags.heightTracksTextView = NO;
        _tcFlags.observingFrameChanges = NO;
    }
    return self;
}

- (NSLayoutManager *)layoutManager
{
    return _layoutManager;
}

- (void)setLayoutManager:(NSLayoutManager *)layoutManager
{
    _layoutManager = layoutManager;
    [_textView setTextContainer:self];
}

- (void)replaceLayoutManager:(NSLayoutManager *)newLayoutManager
{
    if (!newLayoutManager) {
        NSLog(@"NSTextContainer replaceLayoutManager: requires a layout manager");
        return;
    }

    if (!_layoutManager) {
        [newLayoutManager addTextContainer:self];
        return;
    }

    NSLayoutManager *oldLayoutManager = _layoutManager;
    NSTextStorage *textStorage = [oldLayoutManager textStorage];
    if (textStorage) {
        [textStorage removeLayoutManager:oldLayoutManager];
        [textStorage addLayoutManager:newLayoutManager];
    }

    NSArray *containers = [[oldLayoutManager textContainers] copy];
    unsigned int count = [containers count];
    unsigned int index;
    for (index = 0; index < count; index++) {
        NSTextContainer *container = [containers objectAtIndex:index];
        [oldLayoutManager removeTextContainerAtIndex:0];
        [newLayoutManager addTextContainer:container];
    }
    [containers release];
}

- (NSTextView *)textView
{
    return _textView;
}

- (void)setTextView:(NSTextView *)textView
{
    if (_textView == textView)
        return;

    NSTextView *oldTextView = _textView;
    _textView = nil;
    if (oldTextView) {
        if (_tcFlags.observingFrameChanges) {
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:NSViewFrameDidChangeNotification
                                                          object:oldTextView];
        }
        [oldTextView setTextContainer:nil];
        [oldTextView invalidateTextContainerOrigin];
    }

    _textView = textView;
    if (_textView) {
        [_textView setTextContainer:self];
        if (_tcFlags.observingFrameChanges) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(_containerTextViewFrameChanged:)
                                                         name:NSViewFrameDidChangeNotification
                                                       object:_textView];
        }
        [self _resizeAccordingToTextView:_textView];
        [_textView invalidateTextContainerOrigin];
    }

    [_layoutManager textContainerChangedTextView:self];
}

- (void)setWidthTracksTextView:(BOOL)flag
{
    _tcFlags.widthTracksTextView = flag;
    [self _setContainerObservesTextViewFrameChanges:
        (_tcFlags.widthTracksTextView || _tcFlags.heightTracksTextView)];
}

- (BOOL)widthTracksTextView
{
    return _tcFlags.widthTracksTextView;
}

- (void)setHeightTracksTextView:(BOOL)flag
{
    _tcFlags.heightTracksTextView = flag;
    [self _setContainerObservesTextViewFrameChanges:
        (_tcFlags.widthTracksTextView || _tcFlags.heightTracksTextView)];
}

- (BOOL)heightTracksTextView
{
    return _tcFlags.heightTracksTextView;
}

- (void)setContainerSize:(NSSize)size
{
    if (!NSEqualSizes(_size, size)) {
        _size = size;
        [_layoutManager textContainerChangedGeometry:self];
        [_textView invalidateTextContainerOrigin];
        [_textView setNeedsDisplay:YES];
    }
}

- (NSSize)containerSize
{
    return _size;
}

- (void)setLineFragmentPadding:(float)padding
{
    if (_lineFragmentPadding != padding) {
        _lineFragmentPadding = padding;
        [_layoutManager textContainerChangedGeometry:self];
    }
}

- (float)lineFragmentPadding
{
    return _lineFragmentPadding;
}

- (NSRect)lineFragmentRectForProposedRect:(NSRect)proposedRect
                          sweepDirection:(NSLineSweepDirection)sweepDirection
                       movementDirection:(NSLineMovementDirection)movementDirection
                           remainingRect:(NSRectPointer)remainingRect
{
    NSRect candidate = proposedRect;

    switch (movementDirection) {
        case NSLineMovesLeft:
            if (NSMaxX(candidate) > _size.width)
                candidate.origin.x += _size.width - NSMaxX(candidate);
            break;
        case NSLineMovesRight:
            if (candidate.origin.x < 0.0f)
                candidate.origin.x = 0.0f;
            break;
        case NSLineMovesDown:
            if (candidate.origin.y < 0.0f)
                candidate.origin.y = 0.0f;
            break;
        case NSLineMovesUp:
            if (NSMaxY(candidate) > _size.height)
                candidate.origin.y += _size.height - NSMaxY(candidate);
            break;
        default:
            break;
    }

    NSRect bounds = NSMakeRect(0.0f, 0.0f, _size.width, _size.height);
    NSRect fragment = NSIntersectionRect(candidate, bounds);
    if ((sweepDirection <= NSLineSweepRight && fragment.size.height < proposedRect.size.height)
        || (sweepDirection > NSLineSweepRight && fragment.size.width < proposedRect.size.width))
        fragment = NSZeroRect;

    if (remainingRect)
        *remainingRect = NSZeroRect;
    return fragment;
}

- (BOOL)isSimpleRectangularTextContainer
{
    return YES;
}

- (BOOL)containsPoint:(NSPoint)point
{
    NSRect bounds = NSMakeRect(0.0f, 0.0f, _size.width, _size.height);
    return NSPointInRect(point, bounds);
}

- (void)dealloc
{
    NSTextView *textView = _textView;
    _textView = nil;
    if (_tcFlags.observingFrameChanges) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSViewFrameDidChangeNotification
                                                      object:textView];
    }
    [textView setTextContainer:nil];
    [textView invalidateTextContainerOrigin];
    [super dealloc];
}

@end

@implementation NSTextContainer (NSPrivate)

- (BOOL)_containerObservesTextViewFrameChanges
{
    return _tcFlags.observingFrameChanges;
}

- (void)_containerTextViewFrameChanged:(NSNotification *)notification
{
    [self _resizeAccordingToTextView:[notification object]];
}

- (void)_resizeAccordingToTextView:(NSTextView *)textView
{
    if (!_tcFlags.widthTracksTextView && !_tcFlags.heightTracksTextView)
        return;

    NSSize size = _size;
    NSSize frameSize = [textView frame].size;
    NSSize inset = [textView textContainerInset];
    if (_tcFlags.widthTracksTextView)
        size.width = frameSize.width - inset.width - inset.width;
    if (_tcFlags.heightTracksTextView)
        size.height = frameSize.height - inset.height - inset.height;
    [self setContainerSize:size];
}

- (void)_setContainerObservesTextViewFrameChanges:(BOOL)observesChanges
{
    if (_tcFlags.observingFrameChanges == observesChanges)
        return;

    _tcFlags.observingFrameChanges = observesChanges;
    if (!_textView)
        return;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (observesChanges) {
        [center addObserver:self
                  selector:@selector(_containerTextViewFrameChanged:)
                      name:NSViewFrameDidChangeNotification
                    object:_textView];
    } else {
        [center removeObserver:self name:NSViewFrameDidChangeNotification object:_textView];
    }
}

@end
