/*	NSRange.m
	Range utilities
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSRange.h>
#import <Foundation/NSString.h>

/*	Exported by the reference but declared in no public header; see
	reconstruction/divergences.md.  */
FOUNDATION_EXPORT BOOL NSIntersectsRange(NSRange range1, NSRange range2);

NSRange
NSUnionRange(NSRange range1, NSRange range2)
{
    NSRange result;
    unsigned int max1, max2, maxCombined;

    max1 = NSMaxRange(range1);
    max2 = NSMaxRange(range2);
    maxCombined = (max1 > max2) ? max1 : max2;

    result.location = (range1.location <= range2.location) ? range1.location : range2.location;
    result.length = maxCombined - result.location;
    return result;
}

/*	The intersection starts wherever the later-starting range begins,
	provided that location still falls short of the other range's end;
	otherwise the ranges don't overlap -- including merely touching --
	and the result is the zero range.  */
NSRange
NSIntersectionRange(NSRange range1, NSRange range2)
{
    NSRange result;
    unsigned int max1, max2, maxCombined;

    max1 = NSMaxRange(range1);
    max2 = NSMaxRange(range2);
    maxCombined = (max1 < max2) ? max1 : max2;

    if (range1.location >= range2.location && range1.location < max2) {
        result.location = range1.location;
        result.length = maxCombined - range1.location;
    } else if (range1.location <= range2.location && max1 > range2.location) {
        result.location = range2.location;
        result.length = maxCombined - range2.location;
    } else {
        result.location = 0;
        result.length = 0;
    }
    return result;
}

BOOL
NSIntersectsRange(NSRange range1, NSRange range2)
{
    return (range1.location < NSMaxRange(range2) && range2.location < NSMaxRange(range1));
}

NSString *
NSStringFromRange(NSRange range)
{
    return [NSString stringWithFormat:@"{%u, %u}", range.location, range.length];
}

/*	Pulls the next unsigned number out of a "{loc, len}"-style string,
	starting the scan at *cursor and leaving it just past the number
	found. Skips anything that isn't a digit (braces, commas, whitespace)
	before it, the same approach NSGeometryScanNumber in NSGeometry.m
	takes for its floating-point fields. A missing number reads as 0.  */
static unsigned int
NSRangeScanNumber(NSString *aString, unsigned *cursor)
{
    unsigned length, start;
    unichar c;

    length = [aString length];

    while (*cursor < length) {
        c = [aString characterAtIndex:*cursor];
        if (c >= '0' && c <= '9')
            break;
        (*cursor)++;
    }

    start = *cursor;
    while (*cursor < length) {
        c = [aString characterAtIndex:*cursor];
        if (c < '0' || c > '9')
            break;
        (*cursor)++;
    }

    if (*cursor <= start)
        return 0;

    return (unsigned int)[[aString substringWithRange:NSMakeRange(start, *cursor - start)] intValue];
}

NSRange
NSRangeFromString(NSString *aString)
{
    NSRange range;
    unsigned cursor;

    if (aString == nil)
        return NSMakeRange(0, 0);

    cursor = 0;
    range.location = NSRangeScanNumber(aString, &cursor);
    range.length = NSRangeScanNumber(aString, &cursor);
    return range;
}
