/*
        NSPICTImageRep.h
        Application Kit
        Copyright (c) 1997, Apple Computer, Inc.
        All rights reserved.
*/

#import <AppKit/NSImageRep.h>

@class NSPICTParser;

@interface NSPICTImageRep : NSImageRep
{
    /*All instance variables are private*/
    NSPoint        _pictOrigin;		/* topLeft of picFrame */
    NSData*        _pictData;
    NSPICTParser*  _pictParser;		/* keep it cached */
    unsigned int   _reserved;
}

+ (id)imageRepWithData:(NSData*)pictData;
- (id)initWithData:(NSData*)pictData;

- (NSData*) PICTRepresentation;
- (NSRect)  boundingBox;

@end
