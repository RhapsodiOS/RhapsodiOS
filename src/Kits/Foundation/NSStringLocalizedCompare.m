#import <Foundation/NSString.h>

#include "NSStringLocalizedCompareData.inc"

static const short *NSLocaleWeightsForCharacter(unichar character, int *index) {
    unsigned tableIndex = 0;
    unsigned rangeIndex;

    for (rangeIndex = 0; rangeIndex < NS_LOCALE_KEY_RANGE_COUNT; rangeIndex++) {
        unsigned first = NSLocaleKeyRanges[rangeIndex][0];
        unsigned last = NSLocaleKeyRanges[rangeIndex][1];

        if (character >= first && character <= last) {
            *index = (int)(tableIndex + character - first);
            return NSLocaleWeights + 4 * (*index + 1);
        }
        tableIndex += last - first + 1;
    }

    *index = -1;
    return NSLocaleWeights;
}

static const short *NSLocaleLigatureForIndex(int index) {
    if (index < 0 || index >= NS_LOCALE_LIGATURE_RECORD_COUNT)
        return 0;
    return NSLocaleLigatureData[index];
}

static unsigned NSLocaleLigatureLength(const short *record) {
    return record[0] > 0 ? (unsigned)record[0] : 4;
}

static void NSLocaleExpandLigature(NSMutableString **string,
                                   NSString *original,
                                   unsigned *length,
                                   unsigned index,
                                   int ligatureIndex) {
    const short *record = NSLocaleLigatureForIndex(ligatureIndex);
    unsigned expandedLength;

    if (!record)
        return;
    if (!*string)
        *string = (NSMutableString *)[NSMutableString stringWithString:original];

    expandedLength = NSLocaleLigatureLength(record);
    [*string replaceCharactersInRange:NSMakeRange(index, 1)
                       withCharacters:(const unichar *)(record + 1)
                               length:expandedLength];
    *length += expandedLength - 1;

    while (record[0] < 0) {
        unsigned insertedLength;
        NSString *insertedString;

        record = NSLocaleLigatureForIndex(-record[0]);
        if (!record)
            break;
        insertedLength = NSLocaleLigatureLength(record);
        insertedString = [NSString stringWithCharacters:
            (const unichar *)(record + 1) length:insertedLength];
        [*string insertString:insertedString atIndex:index + expandedLength];
        expandedLength += insertedLength;
        *length += insertedLength;
    }
}

NSComparisonResult NSCompareStringsWithLocale(NSString *first,
                                               NSString *second,
                                               unsigned char options,
                                               unsigned rangeLocation,
                                               unsigned rangeLength) {
    NSMutableString *firstCopy = nil;
    NSMutableString *secondCopy = nil;
    unsigned firstLength = rangeLength;
    unsigned secondLength = [second length];
    unsigned firstIndex = rangeLocation;
    unsigned secondIndex = 0;
    int primaryDifference = 0;
    int secondaryDifference = 0;
    int tertiaryDifference = 0;
    NSComparisonResult result = NSOrderedSame;

    if (rangeLocation >= rangeLocation + rangeLength) {
        if (secondLength == 0)
            goto done;
        result = NSOrderedAscending;
        goto done;
    }

    while (secondIndex < secondLength) {
        const short *firstWeights;
        const short *secondWeights;
        int firstWeightIndex;
        int secondWeightIndex;
        unichar firstCharacter;
        unichar secondCharacter;

        while (1) {
            firstCharacter = [(firstCopy ? (NSString *)firstCopy : first)
                              characterAtIndex:firstIndex];
            firstWeights = NSLocaleWeightsForCharacter(firstCharacter, &firstWeightIndex);
            if (firstWeights[0] <= 1)
                break;
            if (!NSLocaleLigatureForIndex(firstWeights[0] - 2))
                break;
            NSLocaleExpandLigature(&firstCopy, first, &firstLength, firstIndex,
                                   firstWeights[0] - 2);
        }

        while (1) {
            secondCharacter = [(secondCopy ? (NSString *)secondCopy : second)
                               characterAtIndex:secondIndex];
            secondWeights = NSLocaleWeightsForCharacter(secondCharacter, &secondWeightIndex);
            if (secondWeights[0] <= 1)
                break;
            if (!NSLocaleLigatureForIndex(secondWeights[0] - 2))
                break;
            NSLocaleExpandLigature(&secondCopy, second, &secondLength, secondIndex,
                                   secondWeights[0] - 2);
        }

        if (firstWeightIndex < 0 || firstWeights[0] < 0) {
            if (secondWeightIndex >= 0 && secondWeights[0] >= 0) {
                result = NSOrderedDescending;
                goto done;
            }
            if (firstCharacter < secondCharacter) {
                result = NSOrderedAscending;
                goto done;
            }
            if (firstCharacter > secondCharacter) {
                result = NSOrderedDescending;
                goto done;
            }
            ++secondIndex;
            ++firstIndex;
            goto next_character;
        }
        if (secondWeightIndex < 0 || secondWeights[0] < 0) {
            result = NSOrderedAscending;
            goto done;
        }

        if (firstWeights[1] != secondWeights[1]) {
            if (firstWeights[0] == 0 && secondWeights[0] == 0) {
                result = (unsigned short)firstWeights[1] >= (unsigned short)secondWeights[1]
                             ? NSOrderedDescending : NSOrderedAscending;
                goto done;
            }
            if (!primaryDifference)
                primaryDifference = (unsigned short)firstWeights[1] <
                                            (unsigned short)secondWeights[1]
                                        ? -1 : 1;
        }

        if (firstWeights[2] != secondWeights[2]) {
            if (firstWeights[0] != 0 || secondWeights[0] != 0) {
                if (!primaryDifference)
                    primaryDifference = (unsigned short)firstWeights[2] <
                                                (unsigned short)secondWeights[2]
                                            ? -1 : 1;
            } else if (!secondaryDifference) {
                secondaryDifference = (unsigned short)firstWeights[2] <
                                              (unsigned short)secondWeights[2]
                                          ? -1 : 1;
            }
        }

        if (!(options & 1) && firstWeights[3] != secondWeights[3]) {
            if (firstWeights[0] != 0 || secondWeights[0] != 0) {
                if (!primaryDifference)
                    primaryDifference = (unsigned short)firstWeights[3] <
                                                (unsigned short)secondWeights[3]
                                            ? -1 : 1;
            } else if (!tertiaryDifference) {
                tertiaryDifference = (unsigned short)firstWeights[3] <
                                             (unsigned short)secondWeights[3]
                                         ? -1 : 1;
            }
        }

        if (firstWeights[0] != 0) {
            if (secondWeights[0] == 0)
                goto advance_first;
        } else if (secondWeights[0] != 0) {
            goto advance_second;
        }
        ++secondIndex;
advance_first:
        ++firstIndex;
next_character:
        if (firstIndex >= rangeLocation + firstLength)
            break;
        continue;
advance_second:
        ++secondIndex;
        if (firstIndex >= rangeLocation + firstLength)
            break;
    }

    if (firstIndex < rangeLocation + firstLength) {
        result = NSOrderedDescending;
        goto done;
    }
    if (secondIndex < secondLength) {
        result = NSOrderedAscending;
        goto done;
    }
    if (secondaryDifference)
        result = (NSComparisonResult)secondaryDifference;
    else if (tertiaryDifference)
        result = (NSComparisonResult)tertiaryDifference;
    else if (firstLength < secondLength)
        result = NSOrderedAscending;
    else if (firstLength > secondLength)
        result = NSOrderedDescending;
    else
        result = (NSComparisonResult)primaryDifference;

done:
    return result;
}
