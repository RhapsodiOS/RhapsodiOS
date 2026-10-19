/*	NSRange.m
	Range utilities
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSRange.h>
#import <Foundation/NSString.h>
#import <Foundation/NSScanner.h>
#if defined(__ppc__) || defined(__POWERPC__)
#import <Foundation/NSZone.h>
extern unsigned int _NSCStringToUnsignedLong(char *string, char **endPointer);
#endif

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

unsigned
NSSubtractRange(NSRange range, NSRange subrange,
                NSRange *firstRemainder, NSRange *secondRemainder)
{
    unsigned rangeEnd = range.location + range.length;
    unsigned subrangeEnd = subrange.location + subrange.length;

    if (subrangeEnd <= range.location || subrange.location >= rangeEnd) {
        *firstRemainder = NSMakeRange(0, 0);
        *secondRemainder = NSMakeRange(0, 0);
    } else if (subrange.location <= range.location) {
        *firstRemainder = NSMakeRange(
            subrangeEnd,
            rangeEnd > subrangeEnd ? rangeEnd - subrangeEnd : 0);
        *secondRemainder = NSMakeRange(0, 0);
    } else {
        *firstRemainder = NSMakeRange(
            range.location, subrange.location - range.location);
        *secondRemainder = rangeEnd > subrangeEnd
            ? NSMakeRange(subrangeEnd, rangeEnd - subrangeEnd)
            : NSMakeRange(0, 0);
    }
#if defined(__ppc__) || defined(__POWERPC__)
    return range.location;
#else
    return subrangeEnd;
#endif
}

BOOL
NSIntersectsRange(NSRange range1, NSRange range2)
{
    return (range1.location < NSMaxRange(range2) && range2.location < NSMaxRange(range1));
}

NSString *
NSStringFromRange(NSRange range)
{
#if defined(__ppc__) || defined(__POWERPC__)
    return [NSString stringWithFormat:@"{%u, %u}", range.location, range.length];
#else
    return [NSString stringWithFormat:@"{location = %d; length = %d}",
        range.location, range.length];
#endif
}

NSRange
NSRangeFromString(NSString *aString)
{
#if defined(__ppc__) || defined(__POWERPC__)
    {
        unsigned length = [aString length];
        unsigned cursor = 0;
        unsigned char localBuffer[1024];
        unsigned char *buffer = localBuffer;
        char *endPointer;
        NSRange range;

        if (length > 0x3ffU)
            buffer = NSZoneMalloc(NULL, length + 1);
        [aString getCString:(char *)buffer];
        buffer[length] = 0;

        while (cursor < length &&
               !((buffer[cursor] >= '0' && buffer[cursor] <= '9') ||
                 buffer[cursor] == '+'))
            cursor++;
        range.location = _NSCStringToUnsignedLong((char *)buffer + cursor,
                                                   &endPointer);

        cursor = (unsigned)(endPointer - (char *)buffer);
        while (cursor < length &&
               !((buffer[cursor] >= '0' && buffer[cursor] <= '9') ||
                 buffer[cursor] == '+'))
            cursor++;
        range.length = _NSCStringToUnsignedLong((char *)buffer + cursor,
                                                 &endPointer);

        if (buffer != localBuffer)
            NSZoneFree(NULL, buffer);
        return range;
    }
#else
    {
        NSScanner *scanner = [[NSScanner allocWithZone:NULL]
            initWithString:aString];
        NSRange range = NSMakeRange(0, 0);
        int location;
        int length;

        [scanner setCharactersToBeSkipped:nil];
        if ([scanner scanUpToString:@"location = " intoString:NULL] &&
            [scanner scanString:@"location = " intoString:NULL] &&
            [scanner scanInt:&location] &&
            [scanner scanUpToString:@"length = " intoString:NULL] &&
            [scanner scanString:@"length = " intoString:NULL] &&
            [scanner scanInt:&length])
            range = NSMakeRange((unsigned)location, (unsigned)length);

        [scanner release];
        return range;
    }
#endif
}
