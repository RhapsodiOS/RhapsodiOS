/*	NSTextAttachment.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSFileWrapper.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageRep.h>
#import <AppKit/NSWorkspace.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSPathUtilities.h>

@implementation NSTextAttachment

- (id)initWithFileWrapper:(NSFileWrapper *)fileWrapper
{
    self = [super init];
    if (self != nil) {
        _fileWrapper = [fileWrapper retain];
        _cell = nil;
        _flags.cellWasExplicitlySet = NO;
    }
    return self;
}

- (void)dealloc
{
    [_cell release];
    [_fileWrapper release];
    [super dealloc];
}

- (id <NSTextAttachmentCell>)attachmentCell
{
    if (_cell == nil) {
        NSTextAttachmentCell *cell = [[NSTextAttachmentCell alloc] init];
        NSImage *image = nil;
        if ([_fileWrapper isRegularFile]) {
            NSData *data = [_fileWrapper regularFileContents];
            if (data != nil && [NSImageRep imageRepClassForData:data] != Nil) {
                image = [[NSImage alloc] initWithData:data];
            }
        }
        if (image == nil && _fileWrapper != nil) {
            NSString *fileType = [[_fileWrapper preferredFilename] pathExtension];
            if ([fileType length] == 0)
                fileType = [[_fileWrapper filename] pathExtension];
            if ([fileType length] != 0)
                image = [[[NSWorkspace sharedWorkspace] iconForFileType:fileType] retain];
        }
        if (image != nil) {
            [cell setImage:image];
            [image release];
        }
        [cell setAttachment:self];
        _cell = cell;
    }
    return _cell;
}

- (void)setAttachmentCell:(id <NSTextAttachmentCell>)cell
{
    if (cell != _cell) {
        [_cell release];
        _cell = [cell retain];
        _flags.cellWasExplicitlySet = (_cell != nil);
        [_cell setAttachment:self];
    }
}

- (NSFileWrapper *)fileWrapper
{
    return _fileWrapper;
}

- (void)setFileWrapper:(NSFileWrapper *)fileWrapper
{
    if (fileWrapper != _fileWrapper) {
        [_fileWrapper release];
        _fileWrapper = [fileWrapper retain];
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    NSTextAttachment *copy = [[[self class] allocWithZone:zone] initWithFileWrapper:_fileWrapper];
    if (_flags.cellWasExplicitlySet && _cell != nil) {
        id cellCopy = [(id)_cell copyWithZone:zone];
        [copy setAttachmentCell:cellCopy];
        [cellCopy release];
    }
    return copy;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSTextAttachment %p; fileWrapper = %@>", self, _fileWrapper];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    char cellWasExplicitlySet = (_cell != nil && _flags.cellWasExplicitlySet);
    [coder encodeValuesOfObjCTypes:"c@", &cellWasExplicitlySet, &_fileWrapper];
    if (cellWasExplicitlySet)
        [coder encodeObject:_cell];
}

- (id)initWithCoder:(NSCoder *)coder
{
    char cellWasExplicitlySet = NO;
    NSFileWrapper *fileWrapper = nil;
    [coder decodeValuesOfObjCTypes:"c@", &cellWasExplicitlySet, &fileWrapper];

    self = [self initWithFileWrapper:fileWrapper];
    if (self != nil && cellWasExplicitlySet)
        [self setAttachmentCell:[coder decodeObject]];
    [fileWrapper release];
    return self;
}

@end
