/*	NSEnumerator.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSEnumerator.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSObjCRuntime.h>

@implementation NSEnumerator

- (id)nextObject {
    NSRequestConcreteImplementation(self, _cmd, [NSEnumerator class]);
    return nil;
}

- (NSArray *)allObjects {
    NSMutableArray *objects = [NSMutableArray array];
    id object;

    while ((object = [self nextObject]) != nil)
        [objects addObject:object];
    return objects;
}

@end
