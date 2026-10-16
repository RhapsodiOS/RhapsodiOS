/*	NSGeometry.m
	Basic definitions for 2-d geometry
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSGeometry.h>
#import <Foundation/NSString.h>
#if defined(__i386__)
#import <Foundation/NSScanner.h>
#endif
#if defined(__ppc__) || defined(__POWERPC__)
#import <Foundation/NSZone.h>
#endif
#import <math.h>

#if defined(__ppc__) || defined(__POWERPC__)
extern double _NSstrtod(const char *string, char **endPointer);
#endif

const NSPoint NSZeroPoint = {0, 0};
const NSSize NSZeroSize = {0, 0};
const NSRect NSZeroRect = {{0, 0}, {0, 0}};

/*	Equality		*/

BOOL
NSEqualPoints(NSPoint aPoint, NSPoint bPoint)
{
    return (aPoint.x == bPoint.x && aPoint.y == bPoint.y);
}

BOOL
NSEqualSizes(NSSize aSize, NSSize bSize)
{
    return (aSize.width == bSize.width && aSize.height == bSize.height);
}

BOOL
NSEqualRects(NSRect aRect, NSRect bRect)
{
    return (aRect.origin.x == bRect.origin.x &&
            aRect.origin.y == bRect.origin.y &&
            aRect.size.width == bRect.size.width &&
            aRect.size.height == bRect.size.height);
}

/*	A rect is empty if it has zero or negative width or height --
	not just the zero rect.  */
BOOL
NSIsEmptyRect(NSRect aRect)
{
    return (aRect.size.width <= 0.0 || aRect.size.height <= 0.0);
}

/*	Simple geometric operations		*/

NSRect
NSInsetRect(NSRect aRect, float dX, float dY)
{
    NSRect result;

    result.origin.x = aRect.origin.x + dX;
    result.origin.y = aRect.origin.y + dY;
    result.size.width = aRect.size.width - dX - dX;
    result.size.height = aRect.size.height - dY - dY;
    return result;
}

NSRect
NSOffsetRect(NSRect aRect, float dX, float dY)
{
    NSRect result;

    result.origin.x = aRect.origin.x + dX;
    result.origin.y = aRect.origin.y + dY;
    result.size.width = aRect.size.width;
    result.size.height = aRect.size.height;
    return result;
}

/*	Rounds the origin down and the opposite corner up to the nearest
	integer, so the result fully covers aRect. An empty rect has no
	corner to round outward from, so it maps to NSZeroRect.  */
NSRect
NSIntegralRect(NSRect aRect)
{
    NSRect result;

    if (!(aRect.size.width > 0.0 && aRect.size.height > 0.0))
        return NSZeroRect;

    result.origin.x = floor(aRect.origin.x);
    result.origin.y = floor(aRect.origin.y);
    result.size.width = ceil(NSMaxX(aRect)) - result.origin.x;
    result.size.height = ceil(NSMaxY(aRect)) - result.origin.y;
    return result;
}

NSRect
NSUnionRect(NSRect aRect, NSRect bRect)
{
    NSRect result;
    float minX, minY, maxX, maxY;

    if (!(aRect.size.width > 0.0 && aRect.size.height > 0.0)) {
        if (bRect.size.width > 0.0 && bRect.size.height > 0.0)
            return bRect;
        return NSZeroRect;
    }
    if (!(bRect.size.width > 0.0 && bRect.size.height > 0.0))
        return aRect;

    minX = (aRect.origin.x < bRect.origin.x) ? aRect.origin.x : bRect.origin.x;
    minY = (aRect.origin.y < bRect.origin.y) ? aRect.origin.y : bRect.origin.y;
    maxX = (NSMaxX(aRect) > NSMaxX(bRect)) ? NSMaxX(aRect) : NSMaxX(bRect);
    maxY = (NSMaxY(aRect) > NSMaxY(bRect)) ? NSMaxY(aRect) : NSMaxY(bRect);

    result.origin.x = minX;
    result.origin.y = minY;
    result.size.width = maxX - minX;
    result.size.height = maxY - minY;
    return result;
}

NSRect
NSIntersectionRect(NSRect aRect, NSRect bRect)
{
    NSRect result;
    float minX, minY, maxX, maxY;

    if (!(aRect.size.width > 0.0 && aRect.size.height > 0.0
          && bRect.size.width > 0.0 && bRect.size.height > 0.0))
        return NSZeroRect;

    minX = (aRect.origin.x > bRect.origin.x) ? aRect.origin.x : bRect.origin.x;
    minY = (aRect.origin.y > bRect.origin.y) ? aRect.origin.y : bRect.origin.y;
    maxX = (NSMaxX(aRect) < NSMaxX(bRect)) ? NSMaxX(aRect) : NSMaxX(bRect);
    maxY = (NSMaxY(aRect) < NSMaxY(bRect)) ? NSMaxY(aRect) : NSMaxY(bRect);

    if (maxX <= minX || maxY <= minY)
        return NSZeroRect;

    result.origin.x = minX;
    result.origin.y = minY;
    result.size.width = maxX - minX;
    result.size.height = maxY - minY;
    return result;
}

BOOL
NSIntersectsRect(NSRect aRect, NSRect bRect)
{
    if (NSIsEmptyRect(aRect) || NSIsEmptyRect(bRect))
        return NO;

    return (NSMinX(aRect) < NSMaxX(bRect) && NSMaxX(aRect) > NSMinX(bRect) &&
            NSMinY(aRect) < NSMaxY(bRect) && NSMaxY(aRect) > NSMinY(bRect));
}

BOOL
NSContainsRect(NSRect aRect, NSRect bRect)
{
    if (NSIsEmptyRect(aRect) || NSIsEmptyRect(bRect))
        return NO;

    return (NSMinX(bRect) >= NSMinX(aRect) && NSMinY(bRect) >= NSMinY(aRect) &&
            NSMaxX(bRect) <= NSMaxX(aRect) && NSMaxY(bRect) <= NSMaxY(aRect));
}

/*	aPoint is inside aRect if it falls on the rect's minimum edges but
	not its maximum ones -- equivalent to NSMouseInRect with flipped
	set to YES, which the reference implements it in terms of.  */
BOOL
NSPointInRect(NSPoint aPoint, NSRect aRect)
{
    return NSMouseInRect(aPoint, aRect, YES);
}

/*	Like NSPointInRect, but "up" depends on flipped: an unflipped rect
	(the usual window/view coordinate system, y increasing upward)
	treats its top and left edges as inclusive and its bottom and
	right edges as exclusive when flipped is NO; a flipped rect (y
	increasing downward) treats top and left as inclusive, bottom and
	right as exclusive -- i.e. the same corner is inclusive either
	way once you account for which edge "top" refers to.  */
BOOL
NSMouseInRect(NSPoint aPoint, NSRect aRect, BOOL flipped)
{
    if (aPoint.x < NSMinX(aRect) || aPoint.x >= NSMaxX(aRect))
        return NO;

    if (flipped) {
        if (aPoint.y < NSMinY(aRect) || aPoint.y >= NSMaxY(aRect))
            return NO;
    } else {
        if (aPoint.y <= NSMinY(aRect) || aPoint.y > NSMaxY(aRect))
            return NO;
    }
    return YES;
}

/*	Splits amount off inRect along edge into *slice, with the rest left
	in *rem. amount is clamped to inRect's extent along that edge, so a
	too-large amount consumes the whole rect and leaves *rem empty.  */
void
NSDivideRect(NSRect inRect, NSRect *slice, NSRect *rem, float amount, NSRectEdge edge)
{
    *slice = inRect;
    *rem = inRect;

    if (edge != NSMinXEdge && edge != NSMaxXEdge) {
        if (amount > inRect.size.height)
            amount = inRect.size.height;
        slice->size.height = amount;
        rem->size.height -= amount;
        if (edge == NSMinYEdge)
            rem->origin.y += slice->size.height;
        else
            slice->origin.y += rem->size.height;
    } else {
        if (amount > inRect.size.width)
            amount = inRect.size.width;
        slice->size.width = amount;
        rem->size.width -= amount;
        if (edge == NSMaxXEdge)
            slice->origin.x += rem->size.width;
        else
            rem->origin.x += slice->size.width;
    }
}

/*	String conversions		*/

NSString *
NSStringFromPoint(NSPoint aPoint)
{
#if defined(__i386__)
    return [NSString stringWithFormat:@"{x = %g; y = %g}",
            aPoint.x, aPoint.y];
#else
    return [NSString stringWithFormat:@"{%g, %g}", aPoint.x, aPoint.y];
#endif
}

NSString *
NSStringFromSize(NSSize aSize)
{
#if defined(__i386__)
    return [NSString stringWithFormat:@"{width = %g; height = %g}",
            aSize.width, aSize.height];
#else
    return [NSString stringWithFormat:@"{%g, %g}", aSize.width, aSize.height];
#endif
}

NSString *
NSStringFromRect(NSRect aRect)
{
#if defined(__i386__)
    return [NSString stringWithFormat:
        @"{x = %g; y = %g; width = %g; height = %g}",
        aRect.origin.x, aRect.origin.y, aRect.size.width, aRect.size.height];
#else
    return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}",
            aRect.origin.x, aRect.origin.y, aRect.size.width, aRect.size.height];
#endif
}

#if defined(__i386__)
static BOOL
NSGeometryScanLabeledFloat(NSScanner *scanner, NSString *label, float *value)
{
    return [scanner scanUpToString:label intoString:NULL] &&
        [scanner scanString:label intoString:NULL] &&
        [scanner scanFloat:value];
}
#elif defined(__ppc__) || defined(__POWERPC__)
static BOOL
NSGeometryIsNumberStart(unsigned char character)
{
    return (character >= '0' && character <= '9') ||
        character == '-' || character == '.' || character == '+';
}

static void
NSGeometryParsePPC(NSString *aString, float *values, unsigned valueCount,
                   BOOL terminateBeforeLastCharacter)
{
    char stackBuffer[1024];
    char *buffer;
    char *endPointer;
    unsigned length, cursor, index;

    length = [aString length];
    buffer = length > 1023 ? NSZoneMalloc(NULL, length + 1) : stackBuffer;
    [aString getCString:buffer];
    if (terminateBeforeLastCharacter) {
        buffer[(int)length - 1] = '\0';
    } else {
        buffer[length] = '\0';
    }

    cursor = 0;
    for (index = 0; index < valueCount; index++) {
        while (cursor < length &&
               !NSGeometryIsNumberStart((unsigned char)buffer[cursor]))
            cursor++;
        values[index] = (float)_NSstrtod(buffer + cursor, &endPointer);
        cursor = (unsigned)(endPointer - buffer);
    }

    if (buffer != stackBuffer)
        NSZoneFree(NULL, buffer);
}
#endif

NSPoint
NSPointFromString(NSString *aString)
{
    NSPoint point;

#if defined(__i386__)
    NSScanner *scanner = [[NSScanner allocWithZone:NULL]
        initWithString:aString];

    [scanner setCharactersToBeSkipped:nil];
    if (!NSGeometryScanLabeledFloat(scanner, @"x = ", &point.x) ||
        !NSGeometryScanLabeledFloat(scanner, @"y = ", &point.y))
        point = NSZeroPoint;
    [scanner release];
#elif defined(__ppc__) || defined(__POWERPC__)
    NSGeometryParsePPC(aString, &point.x, 2, YES);
#else
    point = NSZeroPoint;
#endif
    return point;
}

NSSize
NSSizeFromString(NSString *aString)
{
    NSSize size;

#if defined(__i386__)
    NSScanner *scanner = [[NSScanner allocWithZone:NULL]
        initWithString:aString];

    [scanner setCharactersToBeSkipped:nil];
    if (!NSGeometryScanLabeledFloat(scanner, @"width = ", &size.width) ||
        !NSGeometryScanLabeledFloat(scanner, @"height = ", &size.height))
        size = NSZeroSize;
    [scanner release];
#elif defined(__ppc__) || defined(__POWERPC__)
    NSGeometryParsePPC(aString, &size.width, 2, YES);
#else
    size = NSZeroSize;
#endif
    return size;
}

NSRect
NSRectFromString(NSString *aString)
{
    NSRect rect;

#if defined(__i386__)
    NSScanner *scanner = [[NSScanner allocWithZone:NULL]
        initWithString:aString];

    [scanner setCharactersToBeSkipped:nil];
    if (!NSGeometryScanLabeledFloat(scanner, @"x = ", &rect.origin.x) ||
        !NSGeometryScanLabeledFloat(scanner, @"y = ", &rect.origin.y) ||
        !NSGeometryScanLabeledFloat(scanner, @"width = ", &rect.size.width) ||
        !NSGeometryScanLabeledFloat(scanner, @"height = ", &rect.size.height))
        rect = NSZeroRect;
    [scanner release];
#elif defined(__ppc__) || defined(__POWERPC__)
    NSGeometryParsePPC(aString, &rect.origin.x, 4, NO);
#else
    rect = NSZeroRect;
#endif
    return rect;
}

/*	The reference drives NSCoder's variadic -encodeValuesOfObjCTypes:/
	-decodeValuesOfObjCTypes: primitives here, passing one address per
	float field, rather than -encodeValueOfObjCType:at: on the whole
	struct.  */
@implementation NSCoder (NSGeometryCoding)

- (void)encodePoint:(NSPoint)point
{
    [self encodeValuesOfObjCTypes:"ff", &point.x, &point.y];
}

- (NSPoint)decodePoint
{
    NSPoint point;

    [self decodeValuesOfObjCTypes:"ff", &point.x, &point.y];
    return point;
}

- (void)encodeSize:(NSSize)size
{
    [self encodeValuesOfObjCTypes:"ff", &size.width, &size.height];
}

- (NSSize)decodeSize
{
    NSSize size;

    [self decodeValuesOfObjCTypes:"ff", &size.width, &size.height];
    return size;
}

- (void)encodeRect:(NSRect)rect
{
    [self encodeValuesOfObjCTypes:"ffff", &rect.origin.x, &rect.origin.y,
                                            &rect.size.width, &rect.size.height];
}

- (NSRect)decodeRect
{
    NSRect rect;

    [self decodeValuesOfObjCTypes:"ffff", &rect.origin.x, &rect.origin.y,
                                            &rect.size.width, &rect.size.height];
    return rect;
}

@end
