/*	NSNibConnector.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSNibConnector.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSString.h>
#include <string.h>

@interface NSString (NSNibConnectorCompatibility)
- (id)initWithCString:(const char *)bytes length:(unsigned)length encoding:(NSStringEncoding)encoding;
@end

@implementation NSNibConnector

+ (void)initialize
{
    if (self == [NSNibConnector class])
        [self setVersion:17];
}

- (id)init
{
    self = [super init];
    _label = @"";
    return self;
}

- (id)source
{
    return _source;
}

- (void)setSource:(id)source
{
    _source = source;
}

- (id)destination
{
    return _destination;
}

- (void)setDestination:(id)destination
{
    _destination = destination;
}

- (NSString *)label
{
    return _label;
}

- (void)setLabel:(NSString *)label
{
    if (![_label isEqual:label]) {
        [_label release];
        _label = [label copyWithZone:[self zone]];
    }
}

- (id)initWithCoder:(NSCoder *)coder
{
    if ([coder versionForClassName:@"NSNibConnector"] > 16) {
        [coder decodeValuesOfObjCTypes:"@@@", &_source, &_destination, &_label];
    } else {
        const char *label;
        [coder decodeValuesOfObjCTypes:"@@*", &_source, &_destination, &label];
        _label = [[NSString allocWithZone:[self zone]]
            initWithCString:label length:(unsigned)strlen(label) encoding:NSASCIIStringEncoding];
    }

    [_source retain];
    [_destination retain];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeValuesOfObjCTypes:"@@@", &_source, &_destination, &_label];
}

- (void)replaceObject:(id)oldObject withObject:(id)newObject
{
    if ([self source] == oldObject)
        [self setSource:newObject];
    if ([self destination] == oldObject)
        [self setDestination:newObject];
}

- (void)instantiateWithObjectInstantiator:(id)objectInstantiator
{
    [self setSource:[objectInstantiator instantiateObject:[self source]]];
    [self setDestination:[objectInstantiator instantiateObject:[self destination]]];
}

- (void)establishConnection
{
}

- (void)dealloc
{
    [_label release];
    [super dealloc];
}

@end

