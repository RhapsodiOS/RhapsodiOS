/*	NSCustomImageRep.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSCustomImageRep.h>
#import <Foundation/NSCoder.h>

@interface NSImageRep (NSCustomImageRepCacheMode)
+ (void)setCacheMode:(int)mode;
@end

@implementation NSCustomImageRep

+ (void)initialize
{
	if (self == [NSCustomImageRep class])
		[self setCacheMode:2];
}

- (id)init
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

- (id)initWithDrawSelector:(SEL)method delegate:(id)object
{
	[super init];
	_drawMethod = method;
	_drawObject = object;
	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self == nil)
		return nil;

	_drawObject = [coder decodeObject];
	[coder decodeValueOfObjCType:@encode(SEL) at:&_drawMethod];
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder];
	[coder encodeObject:_drawObject];
	[coder encodeValueOfObjCType:@encode(SEL) at:&_drawMethod];
}

- (id)delegate
{
	return _drawObject;
}

- (SEL)drawSelector
{
	return _drawMethod;
}

- (BOOL)draw
{
	if (_drawObject == nil || ![_drawObject respondsToSelector:_drawMethod])
		return NO;

	[_drawObject performSelector:_drawMethod withObject:self];
	return YES;
}

@end

