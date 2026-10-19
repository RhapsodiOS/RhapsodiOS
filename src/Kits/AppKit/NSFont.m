/*	NSFont.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSFont.h>

@implementation NSFont

- (NSString *)fontName
{
    return _name ? _name : @"Helvetica";
}

- (float)pointSize
{
    return _size;
}

- (id)copy
{
    return [self copyWithZone:[self zone]];
}

- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    return [self retain];
}

- (unsigned)retainCount
{
    return -1;
}

@end

