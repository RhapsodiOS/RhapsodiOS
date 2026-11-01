/*	NSNumberFormatter.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSNumberFormatter.h>
#import <Foundation/NSAttributedString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSDecimalNumber.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSUserDefaults.h>
#import <string.h>

extern NSBundle *_NSFoundationBundle(void);

static id _internalNSNumberFormatterRedColor;

@interface NSString (NSSearchMethods)
- (BOOL)_containsString:(NSString *)string;
- (NSArray *)_componentsSeparatedBySet:(NSCharacterSet *)set;
- (void)_copyToUnicharBuffer:(unichar **)buffer saveLength:(int *)saveLength;
@end

@interface NSMutableString (NSCharacterSetMethods)
- (void)_deleteAllCharactersFromSet:(NSCharacterSet *)set;
@end

static BOOL NSNumberFormatterIsNumberFormatCharacter(unichar character) {
    return character == ',' || character == '.' || character == '_' || character == '#'
            || (character >= '0' && character <= '9');
}

typedef struct {
    unichar *surroundingFormat;
    unsigned surroundingFormatLength;
    unichar *integerFormat;
    unsigned integerFormatLength;
    unichar *fractionFormat;
    unsigned fractionFormatLength;
} NSNumberFormatterFormatBuffer;

@interface NSNumberFormatter (NSNumberFormatterPrivate)
+ (void)_setDefaultRedColor:(id)redColor;
- (void)_commonInit;
- (BOOL)_containsColorForTextAttributesOfNegativeValues;
- (void)_addInternalRedToTextAttributesOfNegativeValues;
- (void)_removeInternalRedFromTextAttributesOfNegativeValues;
- (void)_setDecimalSeparatorNoConsistencyCheck:(NSString *)separator;
- (void)_setThousandSeparatorNoConsistencyCheck:(NSString *)separator;
- (NSString *)_addThousandSeparatorsToFormat:(NSString *)format
        withBuffer:(NSNumberFormatterFormatBuffer *)buffer;
- (void)_addThousandSeparators:(NSString *)format
        withBuffer:(NSNumberFormatterFormatBuffer *)buffer;
- (unsigned short)_decimalPoint;
- (unsigned short)_thousandChar;
- (void)_surroundValueInString:(unichar *)characters withLength:(int *)length
        andBuffer:(NSNumberFormatterFormatBuffer *)buffer;
- (BOOL)_decimalIsNotANumber:(NSDecimalNumber *)number;
- (void)_setFloatingPointFormat:(BOOL)useOptionalDigits left:(unsigned)leftDigits
        right:(unsigned)rightDigits;
- (void)setLocalizationFromDefaults;
- (NSString *)_exchangeDollarInString:(NSString *)string withString:(NSString *)replacement;
- (NSString *)_numberStringForValueObject:(NSDecimalNumber *)number
        withBuffer:(NSNumberFormatterFormatBuffer *)buffer andNegativeFlag:(BOOL)negative;
@end

@interface NSMutableString (NSNumberFormatterPrivate)
- (void)_replaceAllAppearancesOfString:(NSString *)string withString:(NSString *)replacement;
@end

static void NSNumberFormatterSetBufferString(NSString *string, unichar **characters,
        unsigned *length) {
    unsigned stringLength = [string length];
    unichar *copy = stringLength == 0 ? 0 : NSZoneMalloc(0, stringLength * sizeof(unichar));
    if (stringLength != 0)
        [string getCharacters:copy range:NSMakeRange(0, stringLength)];
    if (*characters != 0)
        NSZoneFree(NSZoneFromPointer(*characters), *characters);
    *characters = copy;
    *length = stringLength;
}

static NSString *NSNumberFormatterStringByReplacing(NSString *string,
        NSString *target, NSString *replacement) {
    if (string == nil)
        return nil;
    NSMutableString *copy = [string mutableCopyWithZone:0];
    NSRange match;
    while ((match = [copy rangeOfString:target]).location != NSNotFound)
        [copy replaceCharactersInRange:match withString:replacement];
    NSString *result = [NSString stringWithString:copy];
    [copy release];
    return result;
}

static NSAttributedString *NSNumberFormatterAddWeakAttributes(
        NSAttributedString *string, NSDictionary *attributes) {
    if (string == nil || attributes == nil)
        return string;

    NSMutableAttributedString *result = [string mutableCopyWithZone:0];
    unsigned length = [string length];
    unsigned index = 0;
    while (index < length) {
        NSRange range;
        NSDictionary *existing = [string attributesAtIndex:index effectiveRange:&range];
        NSMutableDictionary *weakAttributes = [attributes mutableCopyWithZone:0];
        NSArray *keys = [existing allKeys];
        unsigned keyIndex;
        for (keyIndex = 0; keyIndex < [keys count]; keyIndex++)
            [weakAttributes removeObjectForKey:[keys objectAtIndex:keyIndex]];
        if ([weakAttributes count] != 0)
            [result addAttributes:weakAttributes range:range];
        [weakAttributes release];
        index = range.location + range.length;
    }
    return [result autorelease];
}

static BOOL NSNumberFormatterSetParseError(NSString **error, NSString *key) {
    if (error == nil)
        return NO;
    *error = [_NSFoundationBundle() localizedStringForKey:key value:@"" table:@"Formatter"];
    return NO;
}

@implementation NSNumberFormatter

+ (void)_setDefaultRedColor:(id)redColor {
    if (_internalNSNumberFormatterRedColor != redColor) {
        [_internalNSNumberFormatterRedColor release];
        _internalNSNumberFormatterRedColor = [redColor copyWithZone:0];
    }
}

- (void)_commonInit {
    [self setTextAttributesForNegativeValues:nil];
    [self setTextAttributesForPositiveValues:nil];
    _attributedStringForZero = [[NSAttributedString allocWithZone:0] initWithString:nil];
    _attributedStringForNil = [[NSAttributedString allocWithZone:0] initWithString:@""];
    _attributedStringForNotANumber = [[NSAttributedString allocWithZone:0] initWithString:@"NaN"];
    [self setMinimum:[NSDecimalNumber notANumber]];
    [self setMaximum:[NSDecimalNumber notANumber]];
    _flags.thousandSeparators = YES;
    _flags.localizesFormat = NO;
    _flags.allowsFloats = YES;
    [self _setDecimalSeparatorNoConsistencyCheck:@"."];
    [self _setThousandSeparatorNoConsistencyCheck:@","];
    _private = NSZoneMalloc(0, 0x30);
    memset(_private, 0, 0x30);
}

- (id)init {
    self = [super init];
    if (self != nil) {
        [self _commonInit];
        [self setFormat:@"#,##0.00;0.00;-#,##0.00"];
    }
    return self;
}

- (void)dealloc {
    void **privateWords = (void **)_private;
    unsigned releaseOrder[6] = { 0, 6, 2, 4, 8, 10 };
    void *pointer;
    unsigned index;

    [_negativeFormat release];
    [_positiveFormat release];
    [_negativeAttributes release];
    [_positiveAttributes release];
    [_attributedStringForZero release];
    [_attributedStringForNil release];
    [_attributedStringForNotANumber release];
    [_minimum release];
    [_maximum release];
    [_roundingBehavior release];

    for (index = 0; index < 6; index++) {
        pointer = privateWords[releaseOrder[index]];
        if (pointer != 0)
            NSZoneFree(NSZoneFromPointer(pointer), pointer);
    }
    NSZoneFree(NSZoneFromPointer(_private), _private);
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone {
    NSNumberFormatter *copy = [[[self class] allocWithZone:zone] init];
    [copy _setDecimalSeparatorNoConsistencyCheck:[self decimalSeparator]];
    [copy _setThousandSeparatorNoConsistencyCheck:[self thousandSeparator]];
    [copy setAttributedStringForZero:[self attributedStringForZero]];
    [copy setAttributedStringForNil:[self attributedStringForNil]];
    [copy setAttributedStringForNotANumber:[self attributedStringForNotANumber]];
    [copy setMinimum:[self minimum]];
    [copy setMaximum:[self maximum]];
    [copy setHasThousandSeparators:[self hasThousandSeparators]];
    [copy setLocalizesFormat:[self localizesFormat]];
    [copy setAllowsFloats:[self allowsFloats]];
    [copy setRoundingBehavior:[self roundingBehavior]];
    [copy setFormat:[self format]];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    BOOL hasThousandSeparators;
    BOOL localizesFormat;
    BOOL allowsFloats;

    [super encodeWithCoder:coder];
    [coder encodeValuesOfObjCTypes:"@@@@@@@", &_positiveFormat, &_negativeFormat,
            &_negativeAttributes, &_positiveAttributes, &_attributedStringForZero,
            &_attributedStringForNil, &_attributedStringForNotANumber];
    hasThousandSeparators = _flags.thousandSeparators;
    localizesFormat = _flags.localizesFormat;
    allowsFloats = _flags.allowsFloats;
    [coder encodeValuesOfObjCTypes:"@@@@@ccc", &_minimum, &_maximum, &_roundingBehavior,
            &_decimalSeparator, &_thousandSeparator, &hasThousandSeparators,
            &localizesFormat, &allowsFloats];
}

- (id)initWithCoder:(NSCoder *)coder {
    unsigned version = [coder versionForClassName:@"NSNumberFormatter"];
    self = [super initWithCoder:coder];
    [self _commonInit];

    if (version > 3) {
        [coder decodeValuesOfObjCTypes:"@@@@@@@", &_positiveFormat, &_negativeFormat,
                &_negativeAttributes, &_positiveAttributes, &_attributedStringForZero,
                &_attributedStringForNil, &_attributedStringForNotANumber];
    } else {
        id ignored[4] = {nil, nil, nil, nil};
        [coder decodeValuesOfObjCTypes:"@@@@@@", &_positiveFormat, &ignored[0],
                &ignored[1], &ignored[2], &_negativeFormat, &ignored[3]];
    }

    if (version != 0) {
        BOOL hasThousandSeparators;
        BOOL localizesFormat;
        BOOL allowsFloats;
        [coder decodeValuesOfObjCTypes:"@@@@@ccc", &_minimum, &_maximum, &_roundingBehavior,
                &_decimalSeparator, &_thousandSeparator, &hasThousandSeparators,
                &localizesFormat, &allowsFloats];
        _flags.thousandSeparators = hasThousandSeparators;
        _flags.localizesFormat = localizesFormat;
        _flags.allowsFloats = allowsFloats;
    } else {
        NSString *legacyPositive = NSNumberFormatterStringByReplacing(
                _positiveFormat, @"9", @"#");
        NSString *legacyNegative = NSNumberFormatterStringByReplacing(
                _negativeFormat, @"9", @"#");
        [_positiveFormat release];
        _positiveFormat = [legacyPositive copyWithZone:[self zone]];
        [_negativeFormat release];
        _negativeFormat = [legacyNegative copyWithZone:[self zone]];
    }

    [self setLocalizationFromDefaults];
    [self format];
    return self;
}

- (NSString *)_exchangeDollarInString:(NSString *)string withString:(NSString *)replacement {
    NSMutableString *replaced = [string mutableCopyWithZone:[self zone]];
    [string release];
    [replaced _replaceAllAppearancesOfString:@"$" withString:replacement];
    return [[NSString stringWithString:replaced] retain];
}

- (void)setLocalizationFromDefaults {
    if (!_flags.localizesFormat) {
        NSString *decimalSeparator = [self decimalSeparator];

        if (![decimalSeparator isEqualToString:@"."]) {
            NSMutableAttributedString *localizedZero =
                [[[self attributedStringForZero] mutableCopyWithZone:0]
                    autorelease];
            NSRange decimalRange =
                [[localizedZero string] rangeOfString:@"."];

            if (decimalRange.length != 0) {
                [localizedZero replaceCharactersInRange:decimalRange
                        withString:decimalSeparator];
                [self setAttributedStringForZero:localizedZero];
            }
        }
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *currencySymbol = [defaults objectForKey:NSCurrencySymbol];
    NSString *decimalSeparator = [defaults objectForKey:NSDecimalSeparator];
    NSString *thousandSeparator = [defaults objectForKey:NSThousandsSeparator];

    if (decimalSeparator != nil) {
        [self setDecimalSeparator:decimalSeparator];
        if (thousandSeparator != nil)
            [self setThousandSeparator:thousandSeparator];

        if (_attributedStringForZero != nil &&
            ![decimalSeparator isEqualToString:@"."]) {
            NSMutableAttributedString *localizedZero =
                [[[self attributedStringForZero] mutableCopyWithZone:0]
                    autorelease];
            NSRange decimalRange =
                [[localizedZero string] rangeOfString:@"."];

            if (decimalRange.length != 0) {
                [localizedZero replaceCharactersInRange:decimalRange
                        withString:decimalSeparator];
                [self setAttributedStringForZero:localizedZero];
            }
        }
    }

    _positiveFormat = [self _exchangeDollarInString:_positiveFormat
            withString:currencySymbol];
    _negativeFormat = [self _exchangeDollarInString:_negativeFormat
            withString:currencySymbol];

    if (currencySymbol != nil && ![currencySymbol isEqualToString:@"$"]) {
        if (_attributedStringForZero != nil) {
            NSMutableAttributedString *localizedZero =
                [[[self attributedStringForZero] mutableCopyWithZone:0]
                    autorelease];
            NSRange currencyRange =
                [[localizedZero string] rangeOfString:@"$"];

            if (currencyRange.length != 0) {
                [localizedZero replaceCharactersInRange:currencyRange
                        withString:currencySymbol];
                [self setAttributedStringForZero:localizedZero];
            }
        }
    }
}

- (NSString *)negativeFormat {
    NSNumberFormatterFormatBuffer *buffer = (NSNumberFormatterFormatBuffer *)_private;
    NSMutableString *format = [_negativeFormat mutableCopyWithZone:[self zone]];
    [_negativeFormat release];
    [format _deleteAllCharactersFromSet:
        [NSCharacterSet characterSetWithCharactersInString:@"[Red]"]];
    NSString *surrounding = [self _addThousandSeparatorsToFormat:format
        withBuffer:buffer];
    [surrounding _copyToUnicharBuffer:&buffer->surroundingFormat
        saveLength:(int *)&buffer->surroundingFormatLength];
    NSString *marker = [self _containsColorForTextAttributesOfNegativeValues]
        ? @"[Red]" : @"";
    _negativeFormat = [[marker stringByAppendingString:format] retain];
    [format release];
    return _negativeFormat;
}

- (void)setNegativeFormat:(NSString *)format {
    if (_negativeFormat != format) {
        [_negativeFormat release];
        if ([format _containsString:@"[Red]"])
            [self _addInternalRedToTextAttributesOfNegativeValues];
        else
            [self _removeInternalRedFromTextAttributesOfNegativeValues];
        _negativeFormat = [format copyWithZone:[self zone]];
        _flags.thousandSeparators = [format _containsString:@","];
        [self negativeFormat];
    }
}

- (NSDictionary *)textAttributesForNegativeValues {
    return _negativeAttributes;
}

- (void)setTextAttributesForNegativeValues:(NSDictionary *)newAttributes {
    [_negativeAttributes autorelease];
    _negativeAttributes = [newAttributes copyWithZone:0];
}

- (BOOL)_containsColorForTextAttributesOfNegativeValues {
    return [[self textAttributesForNegativeValues] objectForKey:@"NSColor"] != nil;
}

- (void)_addInternalRedToTextAttributesOfNegativeValues {
    if (_internalNSNumberFormatterRedColor != nil) {
        NSMutableDictionary *attributes;
        if (_negativeAttributes != nil)
            attributes = [_negativeAttributes mutableCopyWithZone:0];
        else
            attributes = [[NSMutableDictionary allocWithZone:0] init];
        [attributes setObject:_internalNSNumberFormatterRedColor forKey:@"NSColor"];
        [self setTextAttributesForNegativeValues:attributes];
        [attributes release];
    }
}

- (void)_removeInternalRedFromTextAttributesOfNegativeValues {
    if (_negativeAttributes != nil) {
        NSMutableDictionary *attributes = [_negativeAttributes mutableCopyWithZone:0];
        [attributes removeObjectForKey:@"NSColor"];
        [self setTextAttributesForNegativeValues:attributes];
        [attributes release];
    }
}

- (NSString *)positiveFormat {
    NSNumberFormatterFormatBuffer *buffer = (NSNumberFormatterFormatBuffer *)_private + 1;
    NSString *redMarker = [NSString stringWithCString:"[Red]" length:5];
    NSMutableString *format = [_positiveFormat mutableCopyWithZone:[self zone]];
    [_positiveFormat release];
    [format _deleteAllCharactersFromSet:
        [NSCharacterSet characterSetWithCharactersInString:redMarker]];
    NSString *surrounding = [self _addThousandSeparatorsToFormat:format withBuffer:buffer];
    [surrounding _copyToUnicharBuffer:&buffer->surroundingFormat
        saveLength:(int *)&buffer->surroundingFormatLength];
    _positiveFormat = [format copyWithZone:[self zone]];
    [format release];
    return _positiveFormat;
}

- (NSString *)_addThousandSeparatorsToFormat:(NSString *)format
        withBuffer:(NSNumberFormatterFormatBuffer *)buffer {
    unsigned length = [format length];
    unsigned numericStart = length;
    unsigned numericEnd = 0;
    unsigned index;
    for (index = 0; index < length; index++) {
        unichar character = [format characterAtIndex:index];
        if (NSNumberFormatterIsNumberFormatCharacter(character)) {
            if (numericStart == length)
                numericStart = index;
            numericEnd = index + 1;
        }
    }

    NSString *prefix = [format substringToIndex:numericStart];
    NSString *suffix = numericEnd == 0 ? @"" : [format substringFromIndex:numericEnd];
    NSString *numberFormat;
    if (numericStart == length)
        numberFormat = @"#,##0.00";
    else
        numberFormat = [format substringWithRange:NSMakeRange(numericStart,
                numericEnd - numericStart)];
    [self _addThousandSeparators:numberFormat withBuffer:buffer];
    return [[prefix stringByAppendingString:@"@"] stringByAppendingString:suffix];
}

- (void)_addThousandSeparators:(NSString *)format
        withBuffer:(NSNumberFormatterFormatBuffer *)buffer {
    NSMutableString *ungrouped = [format mutableCopyWithZone:0];
    NSRange comma;
    while ((comma = [ungrouped rangeOfString:@","]).location != NSNotFound)
        [ungrouped deleteCharactersInRange:comma];

    NSRange decimal = [ungrouped rangeOfString:@"." options:NSBackwardsSearch];
    NSString *integer = decimal.location == NSNotFound
            ? (NSString *)ungrouped : [ungrouped substringToIndex:decimal.location];
    NSString *fraction = decimal.location == NSNotFound
            ? nil : [ungrouped substringFromIndex:decimal.location];
    NSNumberFormatterSetBufferString(integer, &buffer->integerFormat,
            &buffer->integerFormatLength);
    NSNumberFormatterSetBufferString(fraction, &buffer->fractionFormat,
            &buffer->fractionFormatLength);
    [ungrouped release];
}

- (unsigned short)_decimalPoint {
    if ([_decimalSeparator length] != 0)
        return [_decimalSeparator characterAtIndex:0];
    return '.';
}

- (unsigned short)_thousandChar {
    if ([_thousandSeparator length] != 0)
        return [_thousandSeparator characterAtIndex:0];
    return ',';
}

- (void)_surroundValueInString:(unichar *)characters withLength:(int *)length
        andBuffer:(NSNumberFormatterFormatBuffer *)buffer {
    int valueIndex = *length - 1;
    int formatIndex = (int)buffer->surroundingFormatLength - 1;
    int outputLength = *length + (int)buffer->surroundingFormatLength - 1;
    BOOL insertedValue = NO;
    int index;

    *length = outputLength;
    for (index = 0; index < outputLength; index++) {
        if (formatIndex >= 0 && buffer->surroundingFormat[formatIndex] == '@') {
            insertedValue = YES;
            formatIndex--;
        }
        if (insertedValue && valueIndex >= 0)
            characters[outputLength - index - 1] = characters[valueIndex--];
        else
            characters[outputLength - index - 1] = buffer->surroundingFormat[formatIndex--];
    }
}

- (BOOL)_decimalIsNotANumber:(NSDecimalNumber *)number {
    NSDecimal decimal = [number decimalValue];
    return NSDecimalIsNotANumber(&decimal);
}

- (NSString *)_numberStringForValueObject:(NSDecimalNumber *)number
        withBuffer:(NSNumberFormatterFormatBuffer *)buffer andNegativeFlag:(BOOL)negative {
    NSString *value = [number stringValue];
    unsigned valueLength = [value length];
    int decimalIndex = -1;
    int numberIndex;
    int digitCount = 0;
    unsigned index;
    unichar reversedInteger[200];
    unichar output[200];
    unsigned reversedLength = 0;
    unsigned outputLength = 0;
    unsigned fractionIndex;

    if ([value rangeOfString:@"NaN"].location != NSNotFound) {
        value = @"0";
        valueLength = 1;
    }

    for (index = 0; index < valueLength; index++) {
        if ([value characterAtIndex:index] == '.')
            decimalIndex = (int)index;
    }
    numberIndex = decimalIndex >= 0 ? decimalIndex - 1 : (int)valueLength - 1;

    for (index = buffer->integerFormatLength; index > 0; index--) {
        unichar formatCharacter = buffer->integerFormat[index - 1];
        BOOL hasValue = numberIndex >= 0
                && [value characterAtIndex:(unsigned)numberIndex] != '-';
        if (_flags.thousandSeparators && digitCount != 0 && digitCount % 3 == 0) {
            if (hasValue)
                reversedInteger[reversedLength++] = [self _thousandChar];
            else if (formatCharacter == '0')
                reversedInteger[reversedLength++] = '0';
            else if (formatCharacter == '_')
                reversedInteger[reversedLength++] = ' ';
        }

        if (numberIndex < 0 || [value characterAtIndex:(unsigned)numberIndex] == '-') {
            if (numberIndex >= 0)
                numberIndex--;
            if (formatCharacter == '#')
                continue;
            reversedInteger[reversedLength++] = formatCharacter == '_' ? ' ' : formatCharacter;
            continue;
        }

        if (numberIndex == 0 && [value characterAtIndex:0] == '0'
                && (formatCharacter == '#' || formatCharacter == '_')) {
            numberIndex = -1;
            if (formatCharacter == '_')
                reversedInteger[reversedLength++] = ' ';
            continue;
        }

        reversedInteger[reversedLength++] = [value characterAtIndex:(unsigned)numberIndex--];
        digitCount++;
    }

    while (numberIndex >= 0 && [value characterAtIndex:(unsigned)numberIndex] != '-') {
        if (_flags.thousandSeparators && digitCount != 0 && digitCount % 3 == 0)
            reversedInteger[reversedLength++] = [self _thousandChar];
        reversedInteger[reversedLength++] = [value characterAtIndex:(unsigned)numberIndex--];
        digitCount++;
    }

    while (reversedLength != 0)
        output[outputLength++] = reversedInteger[--reversedLength];

    for (fractionIndex = 0; fractionIndex < buffer->fractionFormatLength; fractionIndex++) {
        unichar formatCharacter = buffer->fractionFormat[fractionIndex];
        unsigned sourceIndex = decimalIndex < 0 ? valueLength
                : (unsigned)decimalIndex + fractionIndex;
        if (sourceIndex < valueLength) {
            unichar valueCharacter = [value characterAtIndex:sourceIndex];
            output[outputLength++] = valueCharacter == '.' ? [self _decimalPoint] : valueCharacter;
        } else if (formatCharacter == '0') {
            output[outputLength++] = '0';
        } else if (formatCharacter == '_') {
            output[outputLength++] = ' ';
        } else if (formatCharacter == '.') {
            output[outputLength++] = [self _decimalPoint];
        }
    }

    if (outputLength != 0 && output[outputLength - 1] == [self _decimalPoint])
        outputLength--;
    int signedLength = (int)outputLength;
    [self _surroundValueInString:output withLength:&signedLength andBuffer:buffer];
    return [NSString stringWithCharacters:output length:(unsigned)signedLength];
}

- (NSString *)stringForObjectValue:(id)object {
    if (![object isKindOfClass:[NSNumber class]])
        return nil;

    NSDecimalNumber *number;
    if ([object isKindOfClass:[NSDecimalNumber class]])
        number = object;
    else
        number = [NSDecimalNumber decimalNumberWithString:[object stringValue]];

    if ([self _decimalIsNotANumber:number])
        return [[self attributedStringForNotANumber] string];

    NSDecimalNumber *zero = [NSDecimalNumber zero];
    BOOL negative = [number compare:zero] == NSOrderedAscending;
    if (!negative && [number compare:zero] == NSOrderedSame
            && [self attributedStringForZero] != nil)
        return [[self attributedStringForZero] string];

    NSNumberFormatterFormatBuffer *buffer = (NSNumberFormatterFormatBuffer *)_private;
    if (!negative)
        buffer++;
    unsigned fractionScale = buffer->fractionFormatLength == 0
            ? 0 : buffer->fractionFormatLength - 1;
    short scale = fractionScale > SHRT_MAX ? SHRT_MAX : (short)fractionScale;
    NSRoundingMode mode = _roundingBehavior == nil
            ? NSRoundPlain : [_roundingBehavior roundingMode];
    NSDecimalNumberHandler *behavior = [[[NSDecimalNumberHandler alloc]
            initWithRoundingMode:mode scale:scale raiseOnExactness:NO
            raiseOnOverflow:YES raiseOnUnderflow:YES raiseOnDivideByZero:YES] autorelease];
    number = [number decimalNumberByRoundingAccordingToBehavior:behavior];
    return [self _numberStringForValueObject:number withBuffer:buffer andNegativeFlag:negative];
}

- (id)defaultObjectValue {
    return [NSDecimalNumber decimalNumberWithString:@"0.0" locale:nil];
}

- (BOOL)getObjectValue:(id *)object forString:(NSString *)string
        errorDescription:(NSString **)error {
    NSString *zeroString = [[self attributedStringForZero] string];
    if ([string isEqualToString:zeroString]) {
        if (object != nil)
            *object = [NSDecimalNumber zero];
        return YES;
    }
    NSString *nilString = [[self attributedStringForNil] string];
    if ([string isEqualToString:nilString]) {
        if (object != nil)
            *object = nil;
        return YES;
    }
    NSString *notANumberString = [[self attributedStringForNotANumber] string];
    if ([string isEqualToString:notANumberString]) {
        if (object != nil)
            *object = [NSDecimalNumber notANumber];
        return YES;
    }

    NSMutableCharacterSet *allowedCharacters = [[[NSMutableCharacterSet allocWithZone:0]
            init] autorelease];
    NSMutableCharacterSet *negativeCharacters = [[[NSMutableCharacterSet allocWithZone:0]
            init] autorelease];
    NSMutableCharacterSet *numericCharacters = [NSMutableCharacterSet
            characterSetWithCharactersInString:@"0123456789"];
    [numericCharacters addCharactersInString:_decimalSeparator];
    [allowedCharacters formUnionWithCharacterSet:numericCharacters];

    NSString *positiveFormat = [self positiveFormat];
    NSString *negativeFormat = [self negativeFormat];
    NSString *zeroFormat = [[self attributedStringForZero] string];
    if ((_positiveFormat != nil && [_positiveFormat rangeOfString:@"_"].location != NSNotFound)
            || (_negativeFormat != nil
                && [_negativeFormat rangeOfString:@"_"].location != NSNotFound))
        [allowedCharacters addCharactersInString:@" "];
    if (positiveFormat != nil)
        [allowedCharacters addCharactersInString:positiveFormat];
    if (negativeFormat != nil)
        [allowedCharacters addCharactersInString:negativeFormat];
    if (zeroFormat != nil)
        [allowedCharacters addCharactersInString:zeroFormat];
    [allowedCharacters addCharactersInString:@";"];

    if (negativeFormat == nil)
        negativeFormat = @"";
    if (positiveFormat == nil)
        positiveFormat = @"";
    if (zeroFormat == nil)
        zeroFormat = @"";
    [negativeCharacters addCharactersInString:negativeFormat];
    [negativeCharacters removeCharactersInString:positiveFormat];
    [negativeCharacters removeCharactersInString:zeroFormat];

    unsigned inputLength = [string length];
    unichar *input = inputLength == 0 ? 0
            : NSZoneMalloc(0, inputLength * sizeof(unichar));
    unichar *numberCharacters = NSZoneMalloc(0, (inputLength + 1) * sizeof(unichar));
    if (inputLength != 0)
        [string getCharacters:input range:NSMakeRange(0, inputLength)];
    unsigned numberLength = 0;
    BOOL isNegative = NO;
    unsigned index;
    for (index = 0; index < inputLength; index++) {
        unichar character = input[index];
        if (![allowedCharacters characterIsMember:character]) {
            if (input != 0)
                NSZoneFree(NSZoneFromPointer(input), input);
            NSZoneFree(NSZoneFromPointer(numberCharacters), numberCharacters);
            return NSNumberFormatterSetParseError(error, @"Invalid number");
        }
        if (character == '-' || [negativeCharacters characterIsMember:character])
            isNegative = YES;
        else if ([numericCharacters characterIsMember:character])
            numberCharacters[numberLength++] = character;
    }
    if (isNegative) {
        memmove(numberCharacters + 1, numberCharacters, numberLength * sizeof(unichar));
        numberCharacters[0] = '-';
        numberLength++;
    }
    if (input != 0)
        NSZoneFree(NSZoneFromPointer(input), input);
    NSString *filteredString = [NSString stringWithCharacters:numberCharacters
            length:numberLength];
    NSZoneFree(NSZoneFromPointer(numberCharacters), numberCharacters);
    if (object == nil)
        return YES;

    NSMutableString *parseString = [filteredString mutableCopyWithZone:0];
    [parseString _replaceAllAppearancesOfString:_decimalSeparator withString:@"."];
    if ([parseString length] == 0) {
        *object = nil;
        [parseString release];
        return YES;
    }

    NSRange decimalRange = [parseString rangeOfString:@"." options:0
            range:NSMakeRange(0, [parseString length])];
    BOOL hasFractionalDigits = decimalRange.location != NSNotFound
            && decimalRange.location < [parseString length] - 1;
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:parseString locale:nil];
    [parseString release];
    *object = number;
    if (number == nil)
        return NSNumberFormatterSetParseError(error, @"Invalid number");

    if (![self _decimalIsNotANumber:_minimum] && [number compare:_minimum] == NSOrderedAscending)
        return NSNumberFormatterSetParseError(error, @"Fell short of minimum");
    if (![self _decimalIsNotANumber:_maximum] && [number compare:_maximum] == NSOrderedDescending)
        return NSNumberFormatterSetParseError(error, @"Maximum exceeded");
    if (_flags.allowsFloats)
        return YES;
    if (!hasFractionalDigits)
        return YES;
    return NSNumberFormatterSetParseError(error, @"Floating Point not allowed");
}

- (NSAttributedString *)attributedStringForObjectValue:(id)object
        withDefaultAttributes:(NSDictionary *)defaultAttributes {
    if (object == nil || ![object isKindOfClass:[NSNumber class]])
        return NSNumberFormatterAddWeakAttributes([self attributedStringForNil],
                defaultAttributes);

    NSMutableDictionary *attributes;
    if (defaultAttributes != nil)
        attributes = [defaultAttributes mutableCopyWithZone:0];
    else
        attributes = [[NSMutableDictionary allocWithZone:0] init];

    NSDecimalNumber *number;
    if ([object isKindOfClass:[NSDecimalNumber class]])
        number = object;
    else
        number = [NSDecimalNumber decimalNumberWithDecimal:[object decimalValue]];
    NSString *formatted = [self stringForObjectValue:number];
    NSComparisonResult comparison = [number compare:[NSDecimalNumber zero]];

    if ([self _decimalIsNotANumber:number]) {
        NSAttributedString *special = NSNumberFormatterAddWeakAttributes(
                [self attributedStringForNotANumber], defaultAttributes);
        [attributes release];
        return special;
    }

    if (comparison == NSOrderedSame && [self attributedStringForZero] != nil) {
        NSAttributedString *special = NSNumberFormatterAddWeakAttributes(
                [self attributedStringForZero], defaultAttributes);
        [attributes release];
        return special;
    }
    if (comparison == NSOrderedAscending
        && [self textAttributesForNegativeValues] != nil)
        [attributes addEntriesFromDictionary:[self textAttributesForNegativeValues]];
    else if (comparison == NSOrderedDescending
             && [self textAttributesForPositiveValues] != nil)
        [attributes addEntriesFromDictionary:[self textAttributesForPositiveValues]];

    NSAttributedString *result = [[[NSAttributedString allocWithZone:0]
            initWithString:formatted attributes:attributes] autorelease];
    [attributes release];
    return result;
}

- (void)_setFloatingPointFormat:(BOOL)useOptionalDigits left:(unsigned)leftDigits
        right:(unsigned)rightDigits {
    unsigned length;
    unichar stackCharacters[512];
    unichar *characters = stackCharacters;
    unsigned index = 0;

    if (useOptionalDigits && leftDigits != 0)
        length = leftDigits + rightDigits + 2;
    else if (leftDigits == 0 || leftDigits == 1)
        length = rightDigits + 2;
    else
        length = leftDigits + rightDigits + 1;

    if (leftDigits + rightDigits + 2 > 512)
        characters = NSZoneMalloc(0, (leftDigits + rightDigits + 2) * sizeof(unichar));

    if (leftDigits == 0 || leftDigits == 1 || useOptionalDigits) {
        characters[index++] = '0';
        characters[index++] = '.';
        if (useOptionalDigits && leftDigits != 0) {
            while (index < length)
                characters[index++] = '#';
        } else {
            while (index < length)
                characters[index++] = '0';
        }
    } else {
        while (index < leftDigits - 1)
            characters[index++] = '_';
        characters[index++] = '0';
        characters[index++] = '.';
        while (index < length)
            characters[index++] = '0';
    }

    [self setHasThousandSeparators:NO];
    [self setFormat:[NSString stringWithCharacters:characters length:length]];
    if (characters != stackCharacters)
        NSZoneFree(0, characters);
}

- (void)setPositiveFormat:(NSString *)format {
    if (_positiveFormat != format) {
        [_positiveFormat release];
        _positiveFormat = [format copyWithZone:[self zone]];
        _flags.thousandSeparators = [format _containsString:@","];
        [self positiveFormat];
    }
}

- (NSDictionary *)textAttributesForPositiveValues {
    return _positiveAttributes;
}

- (void)setTextAttributesForPositiveValues:(NSDictionary *)newAttributes {
    [_positiveAttributes autorelease];
    _positiveAttributes = [newAttributes copyWithZone:0];
}

- (NSAttributedString *)attributedStringForZero {
    return _attributedStringForZero;
}

- (void)setAttributedStringForZero:(NSAttributedString *)newAttributedString {
    [_attributedStringForZero autorelease];
    _attributedStringForZero = [newAttributedString copyWithZone:0];
}

- (NSAttributedString *)attributedStringForNil {
    return _attributedStringForNil;
}

- (void)setAttributedStringForNil:(NSAttributedString *)newAttributedString {
    [_attributedStringForNil autorelease];
    _attributedStringForNil = [newAttributedString copyWithZone:0];
}

- (NSAttributedString *)attributedStringForNotANumber {
    return _attributedStringForNotANumber;
}

- (void)setAttributedStringForNotANumber:(NSAttributedString *)newAttributedString {
    [_attributedStringForNotANumber autorelease];
    _attributedStringForNotANumber = [newAttributedString copyWithZone:0];
}

- (NSString *)format {
    NSString *positive = [self positiveFormat];
    NSAttributedString *zeroString = [self attributedStringForZero];
    NSString *negative = [self negativeFormat];
    NSString *zero = zeroString == nil ? positive : [zeroString string];
    return [NSString stringWithFormat:@"%@;%@;%@", positive, zero, negative];
}

- (void)setFormat:(NSString *)format {
    NSCharacterSet *separator =
        [NSCharacterSet characterSetWithCharactersInString:@";"];
    NSArray *components = [format _componentsSeparatedBySet:separator];

    if ([components count] > 1) {
        if ([components count] == 2) {
            [self setPositiveFormat:[components objectAtIndex:0]];
            [self setAttributedStringForZero:nil];
            [self setNegativeFormat:[components objectAtIndex:1]];
        } else if ([components count] == 3) {
            NSString *zeroFormat;
            NSAttributedString *zeroString;

            [self setPositiveFormat:[components objectAtIndex:0]];
            zeroFormat = [components objectAtIndex:1];
            zeroString = [[NSAttributedString allocWithZone:0]
                initWithString:zeroFormat];
            [self setAttributedStringForZero:[zeroString autorelease]];
            [self setNegativeFormat:[components objectAtIndex:2]];
        } else {
            NSLog(@"Bad formatter string!");
        }
    } else {
        [self setPositiveFormat:format];
        [self setAttributedStringForZero:nil];
        [self setNegativeFormat:[@"-" stringByAppendingString:format]];
    }
    [self format];
}

- (BOOL)hasThousandSeparators {
    return _flags.thousandSeparators;
}

- (void)setHasThousandSeparators:(BOOL)flag {
    _flags.thousandSeparators = flag;
}

- (NSString *)thousandSeparator {
    return _thousandSeparator;
}

- (void)_setThousandSeparatorNoConsistencyCheck:(NSString *)newSeparator {
    if (_thousandSeparator != newSeparator) {
        [_thousandSeparator release];
        _thousandSeparator = [newSeparator copyWithZone:[self zone]];
    }
}

- (void)setThousandSeparator:(NSString *)newSeparator {
    NSString *separator = newSeparator;
    if ([newSeparator isEqualToString:_decimalSeparator]) {
        separator = [[_decimalSeparator copyWithZone:0] autorelease];
        [self _setDecimalSeparatorNoConsistencyCheck:_thousandSeparator];
    }
    [self _setThousandSeparatorNoConsistencyCheck:separator];
}

- (NSString *)decimalSeparator {
    return _decimalSeparator;
}

- (void)_setDecimalSeparatorNoConsistencyCheck:(NSString *)newSeparator {
    if (_decimalSeparator != newSeparator) {
        [_decimalSeparator release];
        _decimalSeparator = [newSeparator copyWithZone:[self zone]];
    }
}

- (void)setDecimalSeparator:(NSString *)newSeparator {
    NSString *separator = newSeparator;
    if ([newSeparator isEqualToString:_thousandSeparator]) {
        separator = [[_thousandSeparator copyWithZone:0] autorelease];
        [self _setThousandSeparatorNoConsistencyCheck:_decimalSeparator];
    }
    [self _setDecimalSeparatorNoConsistencyCheck:separator];
}

- (BOOL)localizesFormat {
    return _flags.localizesFormat;
}

- (void)setLocalizesFormat:(BOOL)flag {
    _flags.localizesFormat = flag;
}

- (BOOL)allowsFloats {
    return _flags.allowsFloats;
}

- (void)setAllowsFloats:(BOOL)flag {
    _flags.allowsFloats = flag;
}

- (NSDecimalNumberHandler *)roundingBehavior {
    return _roundingBehavior;
}

- (void)setRoundingBehavior:(NSDecimalNumberHandler *)newRoundingBehavior {
    [_roundingBehavior autorelease];
    _roundingBehavior = [newRoundingBehavior retain];
}

- (NSDecimalNumber *)minimum {
    return _minimum;
}

- (void)setMinimum:(NSDecimalNumber *)aMinimum {
    if (_minimum != aMinimum) {
        [_minimum release];
        _minimum = [aMinimum copyWithZone:[self zone]];
    }
}

- (NSDecimalNumber *)maximum {
    return _maximum;
}

- (void)setMaximum:(NSDecimalNumber *)aMaximum {
    if (_maximum != aMaximum) {
        [_maximum release];
        _maximum = [aMaximum copyWithZone:[self zone]];
    }
}

@end
