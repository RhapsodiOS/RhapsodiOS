/*	NSAffineTransform.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSAffineTransform.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/psops.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#include <math.h>

@interface NSAffineTransform (AppKitPrivate)
- (void)_fillFloatArray:(float *)array;
@end

@implementation NSAffineTransform

+ (void)initialize
{
    if ([NSAffineTransform version] == 0)
        [NSAffineTransform setVersion:1];
}

+ (NSAffineTransform *)transform
{
    return [[[self alloc] init] autorelease];
}

- (id)init
{
    self = [super init];
    if (self != nil) {
        _transformStruct.m11 = 1.0;
        _transformStruct.m12 = 0.0;
        _transformStruct.m21 = 0.0;
        _transformStruct.m22 = 1.0;
        _transformStruct.tX = 0.0;
        _transformStruct.tY = 0.0;
    }
    return self;
}

- (id)initWithTransform:(NSAffineTransform *)transform
{
    self = [self init];
    if (self != nil)
        [self setTransformStruct:[transform transformStruct]];
    return self;
}

- (void)translateXBy:(float)deltaX yBy:(float)deltaY
{
    _transformStruct.tX += _transformStruct.m11 * deltaX + _transformStruct.m21 * deltaY;
    _transformStruct.tY += _transformStruct.m12 * deltaX + _transformStruct.m22 * deltaY;
}

- (void)rotateByDegrees:(float)angle
{
    [self rotateByRadians:angle * 0.017453292519943295f];
}

- (void)rotateByRadians:(float)angle
{
    NSAffineTransformStruct old = _transformStruct;
    float cosine = (float)cos(angle);
    float sine = (float)sin(angle);

    _transformStruct.m11 = cosine * old.m11 + sine * old.m21;
    _transformStruct.m12 = cosine * old.m12 + sine * old.m22;
    _transformStruct.m21 = -sine * old.m11 + cosine * old.m21;
    _transformStruct.m22 = -sine * old.m12 + cosine * old.m22;
}

- (void)scaleBy:(float)scale
{
    [self scaleXBy:scale yBy:scale];
}

- (void)scaleXBy:(float)scaleX yBy:(float)scaleY
{
    _transformStruct.m11 *= scaleX;
    _transformStruct.m12 *= scaleX;
    _transformStruct.m21 *= scaleY;
    _transformStruct.m22 *= scaleY;
}

- (void)invert
{
    NSAffineTransformStruct old = _transformStruct;
    float determinant = old.m11 * old.m22 - old.m12 * old.m21;
    if (determinant == 0.0)
        [NSException raise:NSInvalidArgumentException format:@"Can't invert a singular matrix"];

    _transformStruct.m11 = old.m22 / determinant;
    _transformStruct.m12 = -old.m12 / determinant;
    _transformStruct.m21 = -old.m21 / determinant;
    _transformStruct.m22 = old.m11 / determinant;
    _transformStruct.tX = (old.m21 * old.tY - old.m22 * old.tX) / determinant;
    _transformStruct.tY = (old.m12 * old.tX - old.m11 * old.tY) / determinant;
}

- (void)appendTransform:(NSAffineTransform *)transform
{
    NSAffineTransformStruct other = [transform transformStruct];
    NSAffineTransformStruct old = _transformStruct;
    NSAffineTransformStruct result;

    result.m11 = old.m11 * other.m11 + old.m12 * other.m21;
    result.m12 = old.m11 * other.m12 + old.m12 * other.m22;
    result.m21 = old.m21 * other.m11 + old.m22 * other.m21;
    result.m22 = old.m21 * other.m12 + old.m22 * other.m22;
    result.tX = old.tX * other.m11 + old.tY * other.m21 + other.tX;
    result.tY = old.tX * other.m12 + old.tY * other.m22 + other.tY;
    _transformStruct = result;
}

- (void)prependTransform:(NSAffineTransform *)transform
{
    NSAffineTransformStruct other = [transform transformStruct];
    NSAffineTransformStruct old = _transformStruct;
    NSAffineTransformStruct result;

    result.m11 = other.m11 * old.m11 + other.m12 * old.m21;
    result.m12 = other.m11 * old.m12 + other.m12 * old.m22;
    result.m21 = other.m21 * old.m11 + other.m22 * old.m21;
    result.m22 = other.m21 * old.m12 + other.m22 * old.m22;
    result.tX = other.tX * old.m11 + other.tY * old.m21 + old.tX;
    result.tY = other.tX * old.m12 + other.tY * old.m22 + old.tY;
    _transformStruct = result;
}

- (NSPoint)transformPoint:(NSPoint)aPoint
{
    NSPoint point;
    point.x = _transformStruct.m11 * aPoint.x + _transformStruct.m21 * aPoint.y + _transformStruct.tX;
    point.y = _transformStruct.m12 * aPoint.x + _transformStruct.m22 * aPoint.y + _transformStruct.tY;
    return point;
}

- (NSSize)transformSize:(NSSize)aSize
{
    NSSize size;
    size.width = _transformStruct.m11 * aSize.width + _transformStruct.m21 * aSize.height;
    size.height = _transformStruct.m12 * aSize.width + _transformStruct.m22 * aSize.height;
    return size;
}

- (NSBezierPath *)transformBezierPath:(NSBezierPath *)aPath
{
    NSBezierPath *path = [aPath copy];
    [path transformUsingAffineTransform:self];
    return [path autorelease];
}

- (void)set
{
    float matrix[6];
    [self _fillFloatArray:matrix];
    DPSsendfloatarray(matrix, 6);
    DPSsetmatrix();
}

- (void)concat
{
    float matrix[6];
    [self _fillFloatArray:matrix];
    DPSconcat(matrix);
}

- (void)_fillFloatArray:(float *)array
{
    array[0] = _transformStruct.m11;
    array[1] = _transformStruct.m12;
    array[2] = _transformStruct.m21;
    array[3] = _transformStruct.m22;
    array[4] = _transformStruct.tX;
    array[5] = _transformStruct.tY;
}

- (NSAffineTransformStruct)transformStruct
{
    return _transformStruct;
}

- (void)setTransformStruct:(NSAffineTransformStruct)transformStruct
{
    _transformStruct = transformStruct;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] allocWithZone:zone] initWithTransform:self];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeArrayOfObjCType:@encode(float) count:6 at:&_transformStruct];
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [self init];
    if (self != nil)
        [coder decodeArrayOfObjCType:@encode(float) count:6 at:&_transformStruct];
    return self;
}

@end
