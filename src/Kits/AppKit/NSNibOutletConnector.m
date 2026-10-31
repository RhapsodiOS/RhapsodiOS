/*	NSNibOutletConnector.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSNibOutletConnector.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <objc/objc-class.h>

static NSString *NSNibOutletConnectorCompatibleName(NSString *name, id destination)
{
    if (name == nil)
        return nil;

    if ([name isEqualToString:@"keyView"] &&
        [destination isEqual:NSClassFromString(@"NSWindowTemplate")])
        return @"initialFirstResponder";
    if ([name isEqualToString:@"textDelegate"])
        return @"delegate";

    return nil;
}

@implementation NSNibOutletConnector

+ (void)initialize
{
    if (self == [NSNibOutletConnector class])
        [self setVersion:207];
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    if ([coder versionForClassName:@"NSNibOutletConnector"] <= 206) {
        NSString *name = NSNibOutletConnectorCompatibleName([self label], [self destination]);
        if (name != nil)
            [self setLabel:name];
    }

    return self;
}

- (void)establishConnection
{
    NSString *label = [self label];
    id destination = [self destination];
    id source = [self source];
    NSString *firstCharacter = [[label substringToIndex:1] capitalizedString];
    NSString *remainder = [label substringFromIndex:1];
    NSString *setterName = [NSString stringWithFormat:@"set%@%@:", firstCharacter, remainder];
    SEL action = NSSelectorFromString(setterName);

    if ([destination respondsToSelector:action])
        [destination performSelector:action withObject:source];
    else
        object_setInstanceVariable(destination, [label UTF8String], source);
}

@end

