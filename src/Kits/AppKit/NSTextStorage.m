/*	NSTextStorage.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSTextStorage.h>
#import <AppKit/NSLayoutManager.h>
#import <Foundation/NSNotification.h>

NSString *NSTextStorageWillProcessEditingNotification =
    @"NSTextStorageWillProcessEditingNotification";
NSString *NSTextStorageDidProcessEditingNotification =
    @"NSTextStorageDidProcessEditingNotification";

@implementation NSTextStorage

- (id)init
{
    self = [super init];
    if (self) {
        _layoutManagers = [[NSMutableArray allocWithZone:[self zone]] initWithCapacity:1];
        _editedRange.location = NSNotFound;
        _editedRange.length = 0;
        _editedDelta = 0;
        _flags.editedMask = 0;
        _flags.disabled = 0;
    }
    return self;
}

- (void)dealloc
{
    unsigned index = [_layoutManagers count];
    while (index > 0) {
        NSLayoutManager *layoutManager = [_layoutManagers objectAtIndex:--index];
        [layoutManager setTextStorage:nil];
    }
    [_layoutManagers release];
    [super dealloc];
}

- (void)beginEditing
{
    [self _lockForWriting];
    _flags.disabled++;
}

- (void)endEditing
{
    if (_flags.disabled > 1) {
        _flags.disabled--;
    } else {
        if (_editedRange.location != NSNotFound) {
            _flags.disabled = 1;
            [self processEditing];
            _editedRange.location = NSNotFound;
        }
        _flags.disabled = 0;
        _flags.editedMask = 0;
        _editedDelta = 0;
    }
    [self _unlock];
}

- (BOOL)_isEditing
{
    return _flags.disabled != 0;
}

- (void)_lockForReading
{
}

- (void)_lockForWriting
{
}

- (void)_unlock
{
}

- (void)edited:(unsigned)editedMask range:(NSRange)range changeInLength:(int)delta
{
    if (_editedRange.location == NSNotFound) {
        _editedRange = range;
        _editedDelta = delta;
    } else {
        unsigned oldStart = _editedRange.location;
        unsigned oldEnd = oldStart + _editedRange.length;
        unsigned newStart = range.location;
        if (newStart > oldEnd)
            newStart -= _editedDelta;
        unsigned newEnd = newStart + range.length;
        if (newStart < oldStart)
            oldStart = newStart;
        if (newEnd > oldEnd)
            oldEnd = newEnd;
        _editedRange.location = oldStart;
        _editedRange.length = oldEnd - oldStart;
        _editedDelta += delta;
    }
    _flags.editedMask |= editedMask;
    if (_flags.disabled == 0) {
        if (_editedRange.location != NSNotFound) {
            _flags.disabled = 1;
            [self processEditing];
            _editedRange.location = NSNotFound;
            _flags.disabled = 0;
        }
        _flags.editedMask = 0;
        _editedDelta = 0;
    }
}

- (void)processEditing
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSRange range = _editedRange;
    [center postNotificationName:NSTextStorageWillProcessEditingNotification object:self];
    [self fixAttributesInRange:range];
    [center postNotificationName:NSTextStorageDidProcessEditingNotification object:self];
    [self _notifyEdited:_flags.editedMask
                  range:range
         changeInLength:_editedDelta
       invalidatedRange:_editedRange];
}

- (void)_notifyEdited:(unsigned)editedMask
                range:(NSRange)range
       changeInLength:(int)delta
     invalidatedRange:(NSRange)invalidatedRange
{
    unsigned index = [_layoutManagers count];
    while (index > 0) {
        NSLayoutManager *layoutManager = [_layoutManagers objectAtIndex:--index];
        [layoutManager textStorage:self
                            edited:editedMask
                             range:range
                    changeInLength:delta
                  invalidatedRange:invalidatedRange];
    }
}

- (void)addLayoutManager:(NSLayoutManager *)layoutManager
{
    [_layoutManagers addObject:layoutManager];
    [layoutManager setTextStorage:self];
}

- (void)removeLayoutManager:(NSLayoutManager *)layoutManager
{
    [layoutManager setTextStorage:nil];
    unsigned index = [_layoutManagers indexOfObject:layoutManager];
    if (index != NSNotFound)
        [_layoutManagers removeObjectAtIndex:index];
}

- (NSArray *)layoutManagers
{
    return _layoutManagers;
}

- (unsigned)editedMask
{
    return _flags.editedMask;
}

- (NSRange)editedRange
{
    return _editedRange;
}

- (int)changeInLength
{
    return _editedDelta;
}

- (id)delegate
{
    return _delegate;
}

- (void)setDelegate:(id)delegate
{
    if (delegate == _delegate)
        return;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_delegate) {
        [center removeObserver:_delegate
                          name:NSTextStorageWillProcessEditingNotification
                        object:self];
        [center removeObserver:_delegate
                          name:NSTextStorageDidProcessEditingNotification
                        object:self];
    }
    _delegate = delegate;
    if (_delegate) {
        [center addObserver:_delegate
                   selector:@selector(textStorageWillProcessEditing:)
                       name:NSTextStorageWillProcessEditingNotification
                     object:self];
        [center addObserver:_delegate
                   selector:@selector(textStorageDidProcessEditing:)
                       name:NSTextStorageDidProcessEditingNotification
                     object:self];
    }
}

@end
