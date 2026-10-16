/*	NSTypesetter.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSTypesetter.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <math.h>

@interface NSFont (NSTypesetterPrinting)
- (float)_widthOfPackedGlyphs:(const unsigned char *)packedGlyphs count:(unsigned)count;
@end

static void requestConcreteImplementation(id object, SEL selector)
{
    [NSException raise:NSInternalInconsistencyException
                format:@"%@ %@ is a subclass responsibility and has not been overridden.",
                       NSStringFromClass([object class]),
                       NSStringFromSelector(selector)];
}

@implementation NSTypesetter

+ (id)sharedSystemTypesetter
{
    return [NSSimpleHorizontalTypesetter sharedInstance];
}

+ (NSSize)printingAdjustmentInLayoutManager:(NSLayoutManager *)layoutMgr
    forNominallySpacedGlyphRange:(NSRange)nominallySpacedGlyphsRange
                     packedGlyphs:(const unsigned char *)packedGlyphs
                             count:(unsigned)packedGlyphsCount
{
    NSSize adjustment = {0.0f, 0.0f};
    unsigned characterIndex = [layoutMgr characterIndexForGlyphAtIndex:nominallySpacedGlyphsRange.location];
    NSAttributedString *textStorage = [layoutMgr textStorage];
    NSFont *font = [textStorage attribute:NSFontAttributeName
                                  atIndex:characterIndex
                           effectiveRange:NULL];
    NSFont *substitutedFont = [layoutMgr substituteFontForFont:font];

    if (substitutedFont != font && ![font isFixedPitch]) {
        float substitutedWidth = [substitutedFont _widthOfPackedGlyphs:packedGlyphs count:packedGlyphsCount];
        float fontWidth = [font _widthOfPackedGlyphs:packedGlyphs count:packedGlyphsCount];
        float widthDifference = substitutedWidth - fontWidth;
        if (fabs(widthDifference) > fontWidth / 10000.0f)
            adjustment.width = widthDifference / packedGlyphsCount;
    }
    return adjustment;
}

- (void)layoutGlyphsInLayoutManager:(NSLayoutManager *)layoutManager
              startingAtGlyphIndex:(unsigned)startGlyphIndex
       maxNumberOfLineFragments:(unsigned)maxNumLines
                   nextGlyphIndex:(unsigned *)nextGlyph
{
    requestConcreteImplementation(self, _cmd);
}

- (float)baselineOffsetInLayoutManager:(NSLayoutManager *)layoutMgr glyphIndex:(unsigned)glyphIndex
{
    requestConcreteImplementation(self, _cmd);
    return NSBaselineNotSet;
}

@end

