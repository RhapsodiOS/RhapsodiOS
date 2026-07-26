/*	NSGeometry.m
	Basic definitions for 2-d geometry
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSGeometry.h>
#import <Foundation/NSString.h>
#import <math.h>

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
    result.size.width = aRect.size.width - 2.0 * dX;
    result.size.height = aRect.size.height - 2.0 * dY;
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

    if (NSIsEmptyRect(aRect))
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

    if (NSIsEmptyRect(aRect))
        return bRect;
    if (NSIsEmptyRect(bRect))
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
	treats its bottom and left edges as inclusive and its top and
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

    if (edge == NSMinYEdge || edge == NSMaxYEdge) {
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
    return [NSString stringWithFormat:@"{%g, %g}", aPoint.x, aPoint.y];
}

NSString *
NSStringFromSize(NSSize aSize)
{
    return [NSString stringWithFormat:@"{%g, %g}", aSize.width, aSize.height];
}

NSString *
NSStringFromRect(NSRect aRect)
{
    return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}",
            aRect.origin.x, aRect.origin.y, aRect.size.width, aRect.size.height];
}

/*	Pulls the next number out of a "{x, y}"-style string, starting the
	scan at *cursor and leaving it just past the number found. Skips
	anything that isn't part of a number (braces, commas, whitespace)
	before it. Missing numbers read as 0, matching NSZeroPoint/Size/
	Rect being the fallback for a string that doesn't parse.  */
static float
NSGeometryScanNumber(NSString *aString, unsigned *cursor)
{
    unsigned length, start;
    unichar c;

    length = [aString length];

    while (*cursor < length) {
        c = [aString characterAtIndex:*cursor];
        if ((c >= '0' && c <= '9') || c == '.' || c == '-' || c == '+')
            break;
        (*cursor)++;
    }

    start = *cursor;
    while (*cursor < length) {
        c = [aString characterAtIndex:*cursor];
        if ((c >= '0' && c <= '9') || c == '.' || c == '-' || c == '+' ||
            c == 'e' || c == 'E')
            (*cursor)++;
        else
            break;
    }

    if (*cursor <= start)
        return 0.0;

    return [[aString substringWithRange:NSMakeRange(start, *cursor - start)] floatValue];
}

NSPoint
NSPointFromString(NSString *aString)
{
    NSPoint point;
    unsigned cursor;

    if (aString == nil)
        return NSZeroPoint;

    cursor = 0;
    point.x = NSGeometryScanNumber(aString, &cursor);
    point.y = NSGeometryScanNumber(aString, &cursor);
    return point;
}

NSSize
NSSizeFromString(NSString *aString)
{
    NSSize size;
    unsigned cursor;

    if (aString == nil)
        return NSZeroSize;

    cursor = 0;
    size.width = NSGeometryScanNumber(aString, &cursor);
    size.height = NSGeometryScanNumber(aString, &cursor);
    return size;
}

NSRect
NSRectFromString(NSString *aString)
{
    NSRect rect;
    unsigned cursor;

    if (aString == nil)
        return NSZeroRect;

    cursor = 0;
    rect.origin.x = NSGeometryScanNumber(aString, &cursor);
    rect.origin.y = NSGeometryScanNumber(aString, &cursor);
    rect.size.width = NSGeometryScanNumber(aString, &cursor);
    rect.size.height = NSGeometryScanNumber(aString, &cursor);
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
