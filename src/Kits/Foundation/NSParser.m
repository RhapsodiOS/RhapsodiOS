/*	NSParser.m
	Grammar-driven tokenization and property-list parsing.
*/

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSSerialization.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSZone.h>

#include <stdarg.h>
#include <ctype.h>
#include <string.h>

extern id _NSMethodExceptionProem(id object, SEL selector);
extern NSStringEncoding _NSDefaultCStringEncoding(void);
extern unsigned NSPushAutoreleasePool(void);
extern void NSPopAutoreleasePool(unsigned token);
extern int NSNextEUCToUnicode(unsigned char **bytes, unsigned remaining,
                              unichar *character);
extern unichar NSNEXTSTEPToPrecompUnicode(unsigned char byte);
extern id _NSNewInlineCString(const void *bytes, unsigned length, NSZone *zone);
extern id _NSNewInlineUnicodeString(const unichar *characters, unsigned length,
                                    NSZone *zone);
extern NSString *__NSEmptyString;

@interface NSString (NSParserEncodingPrivate)
- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)filledLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)lossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange;
@end

typedef struct {
    unsigned startCharacters[8];
    unsigned continuationCharacters[8];
    unsigned separatorCharacters[8];
    unsigned multiSeparatorStarts[8];
    unsigned multiSeparatorCharacters[8];
    char *multipleSeparators;
    unsigned char quoteSingle;
    unsigned char quoteDouble;
    unsigned char integerParsing;
    unsigned char floatParsing;
} NSParserTokenizationParameters;

enum {
    NSParserTokenEnd = 1,
    NSParserTokenQuotedString = 2,
    NSParserTokenUnquotedString = 4,
    NSParserTokenInteger = 8,
    NSParserTokenFloat = 16,
    NSParserTokenSeparator = 32,
    NSParserTokenOther = 128
};

@interface _NSParserSyntaxNode : NSObject <NSCopying> {
@public
    int type;
    unsigned theIndex;
    id arg;
}
- (id)initWithType:(int)aType arg:(id)anArgument;
@end

@interface NSParser : NSObject {
@public
    NSDictionary *_grammar;
    NSParserTokenizationParameters *_tokenizationParameters;
    unichar *_tokenBuffer;
    unsigned _tokenMax;
    unsigned _tokenCount;
    void *_input;
    unsigned _inputLength;
    unsigned char _inputIsASCII;
    unsigned char _tokenBufferReady;
    unsigned char _tokenIsASCII;
    unsigned char _tokenType;
    unsigned _inputPos;
    unsigned _inputLine;
    unsigned _tokenInputPos;
    id *_parseStack;
    unsigned _parseStackMax;
    unsigned _parseStackCount;
    NSHashTable *_allStrings;
    NSZone *_zone;
    void *_reserved2;
}
- (id)initWithGrammar:(NSDictionary *)grammar;
- (void)setString:(NSString *)string;
- (void)nextToken;
- (id)parse:(id)rule;
- (id)parseTokenEqualTo:(NSString *)token mask:(unsigned)mask;
- (id)parseSeparatorEqualTo:(NSString *)separator;
- (id)parseData;
- (id)parseDictionaryOfKey:(id)keyRule value:(id)valueRule;
- (id)parseMetaRuleBody;
- (id)parseMetaSyntaxSequence;
- (id)parseMetaSyntaxLeafResultShouldBeSkipped:(char *)shouldSkip;
- (id)parseSuite:(id)rule separator:(id)separator allowOmitLastSeparator:(char)omit;
- (id)parseSuiteOfPairsKey:(id)keyRule separator:(id)keySeparator
                     value:(id)valueRule separator:(id)valueSeparator
      allowOmitLastSeparator:(char)omit;
- (void)parseError:(NSString *)format, ...;
+ (id)parsedGrammarForString:(NSString *)string;
@end

@interface NSPropertyListParser : NSParser
- (id)initWithString:(NSString *)string;
- (id)parseDictionary;
- (id)parseArray;
@end

@interface _NSPListParserOldStyle : NSPropertyListParser
- (id)parseOldOrNewStringsFile;
- (id)parseDictionary;
- (id)parseDictionaryBracketLess;
@end

static Class NSParserSyntaxNodeClass;
static NSString *NSParserDescribeSubs(NSArray *subs, NSString *separator);

static void NSParserSetBit(unsigned *bits, unsigned char character) {
    bits[character >> 5] |= 1U << (character & 31);
}

static BOOL NSParserHasBit(const unsigned *bits, unsigned character) {
    return character < 256 &&
        (bits[character >> 5] & (1U << (character & 31))) != 0;
}

static void NSParserGrowTokenBuffer(NSParser *parser) {
    unsigned newMaximum = parser->_tokenMax * 2 + 1;
    unsigned elementSize = parser->_tokenIsASCII
        ? sizeof(unsigned char) : sizeof(unichar);

    parser->_tokenBuffer = NSZoneRealloc(parser->_zone,
        parser->_tokenBuffer, newMaximum * elementSize);
    parser->_tokenMax = newMaximum;
}

static void NSParserMakeTokenBufferWide(NSParser *parser) {
    unsigned count = parser->_tokenCount;
    unsigned char *bytes = (unsigned char *)parser->_tokenBuffer;
    unichar *characters;

    if (2 * count > parser->_tokenMax) {
        characters = NSZoneMalloc(parser->_zone,
                                  2 * parser->_tokenMax);
    } else {
        characters = parser->_tokenBuffer;
        parser->_tokenMax >>= 1;
    }
    while (count != 0) {
        --count;
        characters[count] = bytes[count];
    }
    if (characters != parser->_tokenBuffer) {
        NSZoneFree(parser->_zone, parser->_tokenBuffer);
        parser->_tokenBuffer = characters;
    }
    parser->_tokenIsASCII = 0;
}

static void NSParserAppendCharacter(NSParser *parser, unichar character) {
    if (parser->_tokenMax <= parser->_tokenCount + 1)
        NSParserGrowTokenBuffer(parser);
    if (parser->_tokenIsASCII && character > 0x7f)
        NSParserMakeTokenBufferWide(parser);
    if (parser->_tokenIsASCII)
        ((unsigned char *)parser->_tokenBuffer)[parser->_tokenCount++] =
            (unsigned char)character;
    else
        parser->_tokenBuffer[parser->_tokenCount++] = character;
}

static unichar NSParserCharacterAt(NSParser *parser, unsigned position,
                                   unsigned *nextPosition) {
    if (position >= parser->_inputLength) {
        if (nextPosition != NULL)
            *nextPosition = position + 1;
        return 0;
    }
    if (!parser->_inputIsASCII) {
        if (nextPosition != NULL)
            *nextPosition = position + 1;
        return ((unichar *)parser->_input)[position];
    }
    if (nextPosition != NULL)
        *nextPosition = position + 1;
    return ((unsigned char *)parser->_input)[position];
}

static unichar NSParserReadCharacter(NSParser *parser, unsigned *position) {
    unsigned nextPosition;
    unichar character = NSParserCharacterAt(parser, *position, &nextPosition);

    *position = nextPosition;
    return character;
}

static unichar NSParserReadEscapedCharacter(NSParser *parser) {
    unichar character = NSParserReadCharacter(parser, &parser->_inputPos);

    switch (character) {
    case 'a': return '\a';
    case 'b': return '\b';
    case 'f': return '\f';
    case 'n': return '\n';
    case 'r': return '\r';
    case 't': return '\t';
    case 'v': return '\v';
    case '\n':
        parser->_inputLine++;
        return '\n';
    case '0': case '1': case '2': case '3':
    case '4': case '5': case '6': case '7': {
        unsigned value = character - '0';
        unsigned digits = 1;
        unichar digit;

        while (digits < 3 &&
               (digit = NSParserCharacterAt(parser, parser->_inputPos, NULL)) >= '0' &&
               digit <= '7') {
            value = value * 8 + digit - '0';
            NSParserReadCharacter(parser, &parser->_inputPos);
            digits++;
        }
#if defined(__ppc__) || defined(__POWERPC__)
        return NSNEXTSTEPToPrecompUnicode((unsigned char)value);
#else
        return (unichar)value;
#endif
    }
    case 'U': {
        unsigned value = 0;
        unsigned digits;

        for (digits = 0; digits < 4; digits++) {
            unichar digit = NSParserCharacterAt(
                parser, parser->_inputPos, NULL);
            unsigned digitValue;

            if (digit >= '0' && digit <= '9')
                digitValue = digit - '0';
            else if (digit >= 'A' && digit <= 'F')
                digitValue = digit - 'A' + 10;
            else if (digit >= 'a' && digit <= 'f')
                digitValue = digit - 'a' + 10;
            else
                break;
            value = value * 16 + digitValue;
            NSParserReadCharacter(parser, &parser->_inputPos);
        }
        return (unichar)value;
    }
    default:
        return character;
    }
}

static void NSParserAppendQuotedInputCharacter(NSParser *parser,
                                               unsigned char byte) {
    if (_NSDefaultCStringEncoding() == NSJapaneseEUCStringEncoding) {
        unsigned char *bytes = (unsigned char *)parser->_input;
        unsigned char *cursor = bytes + parser->_inputPos - 1;
        unsigned char *start = cursor;
        unichar characters[2];
        int additionalBytes;
        int count = NSNextEUCToUnicode(&cursor,
            parser->_inputLength - parser->_inputPos, characters);

        if (count > 0) {
            int index;
            for (index = 0; index < count && index < 2; index++)
                NSParserAppendCharacter(parser, characters[index]);
            additionalBytes = (int)(cursor - start) - 1;
            if (additionalBytes < 0)
                additionalBytes = 0;
            parser->_inputPos += (unsigned)additionalBytes;
            return;
        }
    }
    NSParserAppendCharacter(parser, NSNEXTSTEPToPrecompUnicode(byte));
}

static unsigned char NSParserFromHexDigit(NSParser *parser,
                                          unsigned char character) {
    if (character >= '0' && character <= '9')
        return character - '0';
    character = (unsigned char)tolower(character);
    if (character < 'a' || character > 'f') {
        [parser parseError:@"Incorrect hex digit: %c", character];
        return 0;
    }
    return character - 'a' + 10;
}

static NSString *NSParserStringFromToken(NSParser *parser) {
    NSString *string;
    id previous;

    if (parser->_tokenInputPos == 0x7fffffffU) {
        if (parser->_tokenIsASCII)
            string = _NSNewInlineCString(parser->_tokenBuffer,
                parser->_tokenCount, parser->_zone);
        else
            string = _NSNewInlineUnicodeString(parser->_tokenBuffer,
                parser->_tokenCount, parser->_zone);
    } else if (parser->_tokenIsASCII && parser->_inputIsASCII) {
        string = _NSNewInlineCString(
            (unsigned char *)parser->_input + parser->_tokenInputPos,
            parser->_tokenCount, parser->_zone);
    } else if (parser->_tokenIsASCII) {
        const unichar *input = (const unichar *)parser->_input
            + parser->_tokenInputPos;

        if (parser->_tokenCount <= 512) {
            char bytes[512];
            unsigned index;

            for (index = 0; index < parser->_tokenCount; index++)
                bytes[index] = (char)input[index];
            string = _NSNewInlineCString(bytes, parser->_tokenCount,
                                         parser->_zone);
        } else {
            char *bytes = NSZoneMalloc(parser->_zone, parser->_tokenCount);
            unsigned index;

            for (index = 0; index < parser->_tokenCount; index++)
                bytes[index] = (char)input[index];
            string = [[NSString allocWithZone:parser->_zone]
                initWithCStringNoCopy:bytes length:parser->_tokenCount
                freeWhenDone:YES];
        }
    } else if (parser->_inputIsASCII) {
        const unsigned char *input = (const unsigned char *)parser->_input
            + parser->_tokenInputPos;

        if (parser->_tokenCount <= 512) {
            unichar characters[512];
            unsigned index;

            for (index = 0; index < parser->_tokenCount; index++)
                characters[index] = input[index];
            string = _NSNewInlineUnicodeString(characters,
                parser->_tokenCount, parser->_zone);
        } else {
            unichar *characters = NSZoneMalloc(parser->_zone,
                parser->_tokenCount * sizeof(unichar));
            unsigned index;

            for (index = 0; index < parser->_tokenCount; index++)
                characters[index] = input[index];
            string = [[NSString allocWithZone:parser->_zone]
                initWithCharactersNoCopy:characters
                length:parser->_tokenCount freeWhenDone:YES];
        }
    } else {
        string = _NSNewInlineUnicodeString(
            (const unichar *)parser->_input + parser->_tokenInputPos,
            parser->_tokenCount, parser->_zone);
    }

    previous = parser->_allStrings != NULL
        ? NSHashGet(parser->_allStrings, string) : nil;

    if (previous != nil) {
        [string release];
        return previous;
    }
    if (parser->_allStrings == NULL)
        parser->_allStrings = NSCreateHashTableWithZone(
            NSNonRetainedObjectHashCallBacks, 0x50, parser->_zone);
    NSHashInsertKnownAbsent(parser->_allStrings, string);
    return string;
}

static void NSParserAutoreleaseAllStrings(NSParser *parser) {
    if (parser->_allStrings != NULL) {
        NSHashEnumerator enumerator = NSEnumerateHashTable(parser->_allStrings);
        id string;

        while ((string = NSNextHashEnumeratorItem(&enumerator)) != nil)
            [string autorelease];
        NSFreeHashTable(parser->_allStrings);
        parser->_allStrings = NULL;
    }
}

@implementation _NSParserSyntaxNode

- (id)initWithType:(int)aType arg:(id)anArgument {
    type = aType;
    arg = [anArgument copyWithZone:NULL];
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [self retain];
}

- (NSString *)description {
    switch (type) {
    case 0:
        return [arg quotedStringRepresentation];
    case 1: {
        NSString *subs = NSParserDescribeSubs(arg, @" ");
        return theIndex != 0x7fffffffU
            ? [NSString stringWithFormat:@"[%d] %@", theIndex, subs]
            : subs;
    }
    case 2:
        return NSParserDescribeSubs(arg, @" | ");
    case 3:
        return NSParserDescribeSubs(arg, @" || ");
    case 4:
        return [NSString stringWithFormat:@"< %@ >", arg];
    default:
        return @"? ? ?";
    }
}

- (void)dealloc {
    [arg release];
    [super dealloc];
}

@end

typedef struct {
    unsigned inputPos;
    unsigned inputLine;
    unsigned tokenCount;
    unsigned tokenInputPos;
    unsigned parseStackCount;
    unsigned char tokenBufferReady;
    unsigned char tokenIsASCII;
    unsigned char tokenType;
    void *tokenBuffer;
} NSParserTokenHead;

static id NSParserParseSyntaxNode(NSParser *parser,
                                  _NSParserSyntaxNode *node);

static void NSParserPushTokenHead(NSParser *parser, NSParserTokenHead *head) {
    head->inputPos = parser->_inputPos;
    head->inputLine = parser->_inputLine;
    head->tokenCount = parser->_tokenCount;
    head->tokenInputPos = parser->_tokenInputPos;
    head->parseStackCount = parser->_parseStackCount;
    head->tokenBufferReady = parser->_tokenBufferReady;
    head->tokenIsASCII = parser->_tokenIsASCII;
    head->tokenType = parser->_tokenType;
    head->tokenBuffer = NULL;
    if (parser->_tokenBufferReady &&
        parser->_tokenInputPos == 0x7fffffffU) {
        unsigned size = parser->_tokenCount *
            (parser->_tokenIsASCII ? sizeof(unsigned char) : sizeof(unichar));
        head->tokenBuffer = NSZoneMalloc(parser->_zone, size);
        memcpy(head->tokenBuffer, parser->_tokenBuffer, size);
    }
}

static void NSParserPopTokenHead(NSParser *parser, NSParserTokenHead *head) {
    parser->_inputPos = head->inputPos;
    parser->_inputLine = head->inputLine;
    parser->_tokenCount = head->tokenCount;
    parser->_tokenInputPos = head->tokenInputPos;
    parser->_tokenBufferReady = head->tokenBufferReady;
    parser->_tokenIsASCII = head->tokenIsASCII;
    parser->_tokenType = head->tokenType;
    while (parser->_parseStackCount > head->parseStackCount)
        [parser->_parseStack[--parser->_parseStackCount] release];
    if (head->tokenBuffer != NULL) {
        unsigned size = head->tokenCount *
            (head->tokenIsASCII ? sizeof(unsigned char) : sizeof(unichar));
        memcpy(parser->_tokenBuffer, head->tokenBuffer,
               size);
    }
}

static id NSParserParseSyntaxValue(NSParser *parser, id value) {
    return *(Class *)(void *)value == NSParserSyntaxNodeClass
        ? NSParserParseSyntaxNode(parser, value) : [parser parse:value];
}

static NSString *NSParserDescribeSubs(NSArray *subs, NSString *separator) {
    NSMutableString *description =
        [[NSMutableString allocWithZone:NULL] init];
    unsigned count = [subs count];
    unsigned index;

    for (index = 0; index < count; index++) {
        [description appendString:[[subs objectAtIndex:index] description]];
        if (index + 1 < count)
            [description appendString:separator];
    }
    return [description autorelease];
}

static id NSParserParseSyntaxNode(NSParser *parser,
                                  _NSParserSyntaxNode *node) {
    NSArray *children = [node->arg isKindOfClass:[NSArray class]]
        ? node->arg : nil;
    unsigned count;
    unsigned index;
    id result;

    switch (node->type) {
    case 0:
        return [parser parseTokenEqualTo:node->arg
                                    mask:NSParserTokenQuotedString
                                        | NSParserTokenUnquotedString
                                        | NSParserTokenInteger
                                        | NSParserTokenFloat
                                        | NSParserTokenSeparator];
    case 1: {
        id selected = nil;
        NSMutableArray *values = nil;

        if (children == nil || [children count] == 0)
            return nil;
        count = [children count];
        result = NSParserParseSyntaxValue(parser,
                                          [children objectAtIndex:0]);
        if (result == nil)
            return nil;
        if (node->theIndex == 0x7fffffffU) {
            values = [NSMutableArray arrayWithCapacity:count];
            [values addObject:result];
        } else if (node->theIndex == 0) {
            selected = result;
        }
        for (index = 1; index < count; index++) {
            id child = [children objectAtIndex:index];
            result = NSParserParseSyntaxValue(parser, child);
            if (result == nil)
                [parser parseError:@"In sequence %@, %@ expected",
                                   node->arg, child];
            if (node->theIndex == 0x7fffffffU)
                [values addObject:result];
            else if (node->theIndex == index)
                selected = result;
        }
        return node->theIndex == 0x7fffffffU ? values : selected;
    }
    case 2:
        if (children == nil)
            return nil;
        for (index = 0; index < [children count]; index++) {
            result = NSParserParseSyntaxValue(
                parser, [children objectAtIndex:index]);
            if (result != nil)
                return result;
        }
        return nil;
    case 3: {
        NSParserTokenHead head;
        id selected = nil;

        if (children == nil)
            return nil;
        NSParserPushTokenHead(parser, &head);
        for (index = 0; index < [children count]; index++) {
            NS_DURING {
                selected = NSParserParseSyntaxValue(
                    parser, [children objectAtIndex:index]);
            } NS_HANDLER {
                selected = nil;
            } NS_ENDHANDLER
            if (selected != nil)
                break;
            NSParserPopTokenHead(parser, &head);
        }
        if (head.tokenBuffer != NULL)
            NSZoneFree(parser->_zone, head.tokenBuffer);
        return selected;
    }
    case 4: {
        NSMutableArray *items;

        result = NSParserParseSyntaxValue(parser, node->arg);
        if (result == nil)
            return nil;
        items = [NSMutableArray arrayWithObject:result];
        while ((result = NSParserParseSyntaxValue(parser, node->arg)) != nil)
            [items addObject:result];
        return items;
    }
    default:
        return nil;
    }
}



@implementation NSParser

- (id)initWithGrammar:(NSDictionary *)grammar {
    _zone = [self zone];
    _grammar = [grammar copyWithZone:_zone];
    _tokenizationParameters = NSZoneMalloc(_zone, 0xa8);
    memset(_tokenizationParameters, 0, 0xa8);

    [self setUnquotedStringStartCharacters:@"_$/:."
                         lowerCaseLetters:1 upperCaseLetters:1 digits:1];
    [self setUnquotedStringCharacters:@"_$/:."
                    lowerCaseLetters:1 upperCaseLetters:1 digits:1];
    [self setMonoCharacterSeparatorCharacters:nil usualPunctuation:1];
    [self setQuotingWithSingleQuote:0 double:1];
    return self;
}

- (void)dealloc {
    NSParserTokenizationParameters *tokenizationParameters =
        _tokenizationParameters;

    if (_input != NULL)
        NSZoneFree(_zone, _input);
    if (_tokenBuffer != NULL)
        NSZoneFree(_zone, _tokenBuffer);
    [_grammar release];
    while (_parseStackCount != 0)
        [_parseStack[--_parseStackCount] release];
    if (_parseStack != NULL)
        NSZoneFree(_zone, _parseStack);
    if (tokenizationParameters != NULL) {
        NSZoneFree(_zone, tokenizationParameters->multipleSeparators);
        NSZoneFree(_zone, tokenizationParameters);
    }
    NSParserAutoreleaseAllStrings(self);
    [super dealloc];
}

- (void)setString:(NSString *)string {
    unsigned filledLength = 0;
    unsigned length;
    NSStringEncoding encoding;

    if (_input != NULL)
        NSZoneFree(_zone, _input);
    if ([string fastestEncoding] == _NSDefaultCStringEncoding()) {
        _inputIsASCII = 1;
        _inputLength = [string cStringLength];
        _input = NSZoneMalloc(_zone, _inputLength + 1);
#if defined(__ppc__) || defined(__POWERPC__)
        encoding = _NSDefaultCStringEncoding();
        length = [string length];
#else
        length = [string length];
        encoding = _NSDefaultCStringEncoding();
#endif
        [string getBytes:(char *)_input maxLength:_inputLength
            filledLength:&filledLength encoding:encoding
            allowLossyConversion:NO range:NSMakeRange(0, length)
            remainingRange:NULL];
        ((unsigned char *)_input)[filledLength] = 0;
    } else {
        _inputIsASCII = 0;
        length = [string length];
        _inputLength = length;
        _input = NSZoneMalloc(_zone, 2 * (_inputLength + 1));
        [string getCharacters:(unichar *)_input range:NSMakeRange(0, length)];
        ((unichar *)_input)[_inputLength] = 0;
    }
    _inputLine = 1;
    _inputPos = 0;
    _tokenBufferReady = 0;
    while (_parseStackCount != 0)
        [_parseStack[--_parseStackCount] autorelease];
    NSParserAutoreleaseAllStrings(self);
}

- (void)setEnableFloatParsing:(char)enabled {
    _tokenizationParameters->floatParsing = enabled;
}

- (void)setEnableIntegerParsing:(char)enabled {
    _tokenizationParameters->integerParsing = enabled;
}

- (void)setQuotingWithSingleQuote:(char)single double:(char)doubleQuote {
    _tokenizationParameters->quoteSingle = single;
    _tokenizationParameters->quoteDouble = doubleQuote;
}

- (void)setMultipleCharacterSeparators:(NSArray *)separators {
    unsigned separatorCount = [separators count];
    unsigned separatorIndex;
    unsigned bufferSize = 1;
    unsigned *separatorLengths;
    char *buffer;
    char *cursor;

    memset(_tokenizationParameters->multiSeparatorStarts, 0,
           sizeof(_tokenizationParameters->multiSeparatorStarts));
    memset(_tokenizationParameters->multiSeparatorCharacters, 0,
           sizeof(_tokenizationParameters->multiSeparatorCharacters));
    NSZoneFree(_zone, _tokenizationParameters->multipleSeparators);
    _tokenizationParameters->multipleSeparators = NULL;
    if (separatorCount == 0)
        return;

    NSArray *sortedSeparators = [separators sortedArrayUsingSelector:@selector(compare:)];
    separatorLengths = NSZoneMalloc(NULL,
                                    separatorCount * sizeof(unsigned));
    for (separatorIndex = separatorCount; separatorIndex > 0; separatorIndex--) {
        NSString *separator = [sortedSeparators objectAtIndex:separatorIndex - 1];
        unsigned length = [separator length];

        separatorLengths[separatorIndex - 1] = length;
        if (length <= 1) {
            [NSException raise:NSInvalidArgumentException format:
                @"%@: Separator strings expected to be at least 2 characters in length: %@",
                _NSMethodExceptionProem(self, _cmd), separator];
        }
        bufferSize += length + 1;
    }

    buffer = NSZoneMalloc(_zone, bufferSize);
    cursor = buffer;
    for (separatorIndex = separatorCount; separatorIndex > 0; separatorIndex--) {
        NSString *separator = [sortedSeparators objectAtIndex:separatorIndex - 1];
        const unsigned char *characters = (const unsigned char *)[separator cString];
        unsigned length = separatorLengths[separatorIndex - 1];

        NSParserSetBit(_tokenizationParameters->multiSeparatorStarts, characters[0]);
        NSParserSetBit(_tokenizationParameters->multiSeparatorCharacters, characters[1]);
        memmove(cursor, characters, length + 1);
        cursor += length + 1;
    }
    *cursor = '\0';
    _tokenizationParameters->multipleSeparators = buffer;
    NSZoneFree(NULL, separatorLengths);
}

- (void)setMonoCharacterSeparatorCharacters:(NSString *)characters
                             usualPunctuation:(char)usualPunctuation {
    unsigned index;
    const unsigned char *bytes =
        (const unsigned char *)[characters cString];

    memset(_tokenizationParameters->separatorCharacters, 0,
           sizeof(_tokenizationParameters->separatorCharacters));
    if (usualPunctuation) {
        for (index = 0; index < 256; index++)
            if (ispunct((unsigned char)index))
                NSParserSetBit(_tokenizationParameters->separatorCharacters,
                               index);
    }
    if (characters != nil) {
        while (*bytes != 0)
            NSParserSetBit(_tokenizationParameters->separatorCharacters,
                           *bytes++);
    }
}

- (void)setUnquotedStringStartCharacters:(NSString *)characters
                       lowerCaseLetters:(char)lower
                       upperCaseLetters:(char)upper
                                  digits:(char)digits {
    unsigned index;
    const unsigned char *bytes =
        (const unsigned char *)[characters cString];

    memset(_tokenizationParameters->startCharacters, 0,
           sizeof(_tokenizationParameters->startCharacters));
    if (lower)
        for (index = 'a'; index <= 'z'; index++)
            NSParserSetBit(_tokenizationParameters->startCharacters, index);
    if (upper)
        for (index = 'A'; index <= 'Z'; index++)
            NSParserSetBit(_tokenizationParameters->startCharacters, index);
    if (digits)
        for (index = '0'; index <= '9'; index++)
            NSParserSetBit(_tokenizationParameters->startCharacters, index);
    if (characters != nil) {
        while (*bytes != 0)
            NSParserSetBit(_tokenizationParameters->startCharacters,
                           *bytes++);
    }
}

- (void)setUnquotedStringCharacters:(NSString *)characters
                  lowerCaseLetters:(char)lower
                  upperCaseLetters:(char)upper
                             digits:(char)digits {
    unsigned index;
    const unsigned char *bytes =
        (const unsigned char *)[characters cString];

    memset(_tokenizationParameters->continuationCharacters, 0,
           sizeof(_tokenizationParameters->continuationCharacters));
    if (lower)
        for (index = 'a'; index <= 'z'; index++)
            NSParserSetBit(_tokenizationParameters->continuationCharacters, index);
    if (upper)
        for (index = 'A'; index <= 'Z'; index++)
            NSParserSetBit(_tokenizationParameters->continuationCharacters, index);
    if (digits)
        for (index = '0'; index <= '9'; index++)
            NSParserSetBit(_tokenizationParameters->continuationCharacters, index);
    if (characters != nil) {
        while (*bytes != 0)
            NSParserSetBit(_tokenizationParameters->continuationCharacters,
                           *bytes++);
    }
}

- (void)nextToken {
    unichar character;
    unsigned start;

    _tokenCount = 0;
    _tokenInputPos = 0x7fffffffU;

    for (;;) {
        start = _inputPos;
        character = NSParserReadCharacter(self, &_inputPos);
        if (character == 0) {
            _tokenType = NSParserTokenEnd;
            _tokenBufferReady = 1;
            return;
        }
        if (character == '\n') {
            _inputLine++;
            continue;
        }
        if (character == ' ' || character == '\t' || character == '\r' ||
            character == '\f' || character == '\v') {
            continue;
        }
        if (character == '/' && NSParserCharacterAt(self, _inputPos, NULL) == '/') {
            NSParserReadCharacter(self, &_inputPos);
            while (_inputPos < _inputLength &&
                   NSParserCharacterAt(self, _inputPos, NULL) != '\n')
                NSParserReadCharacter(self, &_inputPos);
            if (_inputPos < _inputLength &&
                NSParserCharacterAt(self, _inputPos, NULL) == '\n')
                _inputLine++;
            continue;
        }
        if (character == '/' && NSParserCharacterAt(self, _inputPos, NULL) == '*') {
            NSParserReadCharacter(self, &_inputPos);
            for (;;) {
                character = NSParserReadCharacter(self, &_inputPos);
                if (character == 0) {
                    _tokenType = NSParserTokenEnd;
                    _tokenBufferReady = 1;
                    return;
                }
                if (character == '\n')
                    _inputLine++;
                if (character == '*') {
                    unichar following = NSParserCharacterAt(self, _inputPos, NULL);

                    if (_inputPos < _inputLength)
                        NSParserReadCharacter(self, &_inputPos);
                    else
                        _inputPos++;
                    switch (following) {
                        case '\n':
                            _inputLine++;
                            break;
                        case '/':
                            goto blockCommentEnded;
                        case '*':
                            _inputPos--;
                            break;
                    }
                }
            }
blockCommentEnded:
            continue;
        }
        break;
    }

    _tokenBufferReady = 1;
    if (!_tokenIsASCII)
        _tokenMax *= 2;
    _tokenIsASCII = 1;

    if ((character == '\'' && _tokenizationParameters->quoteSingle) ||
        (character == '"' && _tokenizationParameters->quoteDouble)) {
        _tokenType = NSParserTokenQuotedString;
        for (;;) {
            unichar next = NSParserReadCharacter(self, &_inputPos);
            BOOL escaped = NO;

            if (next == 0) {
                [self parseError:@"Unterminated quoted string"];
                return;
            }
            if (next == character) {
                _tokenBufferReady = 1;
                return;
            }
            if (next == '\\') {
                next = NSParserReadEscapedCharacter(self);
                escaped = YES;
            } else if (next == '\n') {
                _inputLine++;
            }
            if (!escaped && _inputIsASCII && next > 0x7f) {
                NSParserAppendQuotedInputCharacter(self, (unsigned char)next);
                continue;
            }
            NSParserAppendCharacter(self, next);
        }
    }

    if ((_tokenizationParameters->integerParsing ||
         _tokenizationParameters->floatParsing) &&
        ((character >= '0' && character <= '9') ||
         (_tokenizationParameters->floatParsing && character == '.'))) {
        unsigned integerEnd = start;
        unsigned tokenEnd = start;
        BOOL hasFloat = !_tokenizationParameters->integerParsing;

        if (character != '.') {
            while (NSParserCharacterAt(self, integerEnd, NULL) >= '0' &&
                   NSParserCharacterAt(self, integerEnd, NULL) <= '9')
                integerEnd++;
            tokenEnd = integerEnd;
        }
        if (_tokenizationParameters->floatParsing) {
            unsigned fractionStart = tokenEnd;
            if (NSParserCharacterAt(self, tokenEnd, NULL) == '.') {
                tokenEnd++;
                while (NSParserCharacterAt(self, tokenEnd, NULL) >= '0' &&
                       NSParserCharacterAt(self, tokenEnd, NULL) <= '9')
                    tokenEnd++;
                hasFloat = character != '.' || tokenEnd > fractionStart + 1;
                if (!hasFloat)
                    tokenEnd = start;
            }
            unichar exponentCharacter =
                NSParserCharacterAt(self, tokenEnd, NULL);
            BOOL isExponent = _inputIsASCII
                ? tolower((unsigned char)exponentCharacter) == 'e'
                : (exponentCharacter == 'e' || exponentCharacter == 'E');

            if (tokenEnd > start && isExponent) {
                unsigned exponent = tokenEnd + 1;
                if (NSParserCharacterAt(self, exponent, NULL) == '+' ||
                    NSParserCharacterAt(self, exponent, NULL) == '-')
                    exponent++;
                if (NSParserCharacterAt(self, exponent, NULL) >= '0' &&
                    NSParserCharacterAt(self, exponent, NULL) <= '9') {
                    tokenEnd = exponent + 1;
                    while (NSParserCharacterAt(self, tokenEnd, NULL) >= '0' &&
                           NSParserCharacterAt(self, tokenEnd, NULL) <= '9')
                        tokenEnd++;
                    hasFloat = YES;
                }
            }
        }
        if (tokenEnd > start) {
            _tokenType = hasFloat
                ? NSParserTokenFloat : NSParserTokenInteger;
            _tokenInputPos = start;
            _tokenCount = tokenEnd - start;
            _inputPos = tokenEnd;
            _tokenBufferReady = 1;
            return;
        }
    }

    if (character <= 0x7f && NSParserHasBit(
            _tokenizationParameters->startCharacters, character)) {
        unsigned tokenEnd = _inputPos;
        BOOL needsBuffer = NO;

        _tokenType = NSParserTokenUnquotedString;
        while (tokenEnd < _inputLength) {
            character = NSParserCharacterAt(self, tokenEnd, NULL);
            if (character >= 256 || !NSParserHasBit(
                    _tokenizationParameters->continuationCharacters, character))
                break;
            if (character > 0x7f)
                needsBuffer = YES;
            tokenEnd++;
        }
        if (needsBuffer) {
            unichar firstCharacter = NSParserCharacterAt(self, start, NULL);

            if (!NSParserHasBit(
                    _tokenizationParameters->continuationCharacters,
                    firstCharacter)) {
                if (firstCharacter < 256 && NSParserHasBit(
                        _tokenizationParameters->multiSeparatorStarts,
                        firstCharacter)) {
                    unichar nextCharacter =
                        NSParserCharacterAt(self, _inputPos, NULL);
                    const char *separator =
                        _tokenizationParameters->multipleSeparators;

                    if (nextCharacter != 0 && nextCharacter < 256 &&
                        NSParserHasBit(
                            _tokenizationParameters->multiSeparatorCharacters,
                            nextCharacter)) {
                        while (separator != NULL && *separator != '\0') {
                            unsigned length = strlen(separator);
                            unsigned offset;

                            if (start + length <= _inputLength) {
                                for (offset = 0; offset < length; offset++) {
                                    if (NSParserCharacterAt(
                                            self, start + offset, NULL) !=
                                        (unsigned char)separator[offset])
                                        break;
                                }
                                if (offset == length) {
                                    for (offset = 0; offset < length; offset++)
                                        NSParserAppendCharacter(
                                            self, (unsigned char)separator[offset]);
                                    _inputPos = start + length;
                                    _tokenType = NSParserTokenSeparator;
                                    _tokenBufferReady = 1;
                                    return;
                                }
                            }
                            separator += length + 1;
                        }
                    }
                }
                NSParserAppendCharacter(self, firstCharacter);
                _tokenType = NSParserHasBit(
                    _tokenizationParameters->separatorCharacters,
                    firstCharacter)
                    ? NSParserTokenSeparator : NSParserTokenOther;
                _tokenBufferReady = 1;
                return;
            }
            _tokenCount = 0;
            NSParserAppendCharacter(self, firstCharacter);
            while (_inputPos < tokenEnd)
                NSParserAppendCharacter(self,
                    NSParserReadCharacter(self, &_inputPos));
        } else {
            _tokenCount = tokenEnd - start;
            _tokenInputPos = start;
            _inputPos = tokenEnd;
        }
        _tokenBufferReady = 1;
        return;
    }

    if (character < 256 && NSParserHasBit(
            _tokenizationParameters->continuationCharacters, character)) {
        unsigned tokenEnd = _inputPos;

        while (tokenEnd < _inputLength) {
            unichar next = NSParserCharacterAt(self, tokenEnd, NULL);
            if (next >= 256 || !NSParserHasBit(
                    _tokenizationParameters->continuationCharacters, next))
                break;
            tokenEnd++;
        }
        _tokenCount = 0;
        NSParserAppendCharacter(self, character);
        while (_inputPos < tokenEnd)
            NSParserAppendCharacter(self,
                NSParserReadCharacter(self, &_inputPos));
        _tokenType = NSParserTokenUnquotedString;
        _tokenBufferReady = 1;
        return;
    }

    if (character < 256 && NSParserHasBit(
            _tokenizationParameters->multiSeparatorStarts, character)) {
        unichar nextCharacter = NSParserCharacterAt(self, _inputPos, NULL);

        if (nextCharacter != 0 && nextCharacter < 256 &&
            NSParserHasBit(_tokenizationParameters->multiSeparatorCharacters,
                           nextCharacter)) {
            const char *separator = _tokenizationParameters->multipleSeparators;
            while (separator != NULL && *separator != '\0') {
                unsigned length = strlen(separator);
                unsigned offset;

                if (start + length <= _inputLength) {
                    for (offset = 0; offset < length; offset++) {
                        if (NSParserCharacterAt(self, start + offset, NULL) !=
                            (unsigned char)separator[offset])
                            break;
                    }
                    if (offset == length) {
                        for (offset = 0; offset < length; offset++)
                            NSParserAppendCharacter(self, (unsigned char)separator[offset]);
                        _inputPos = start + length;
                        _tokenType = NSParserTokenSeparator;
                        _tokenBufferReady = 1;
                        return;
                    }
                }
                separator += length + 1;
            }
        }
    }

    _tokenType = NSParserTokenSeparator;
    if (character < 256 && NSParserHasBit(
            _tokenizationParameters->separatorCharacters, character)) {
        NSParserAppendCharacter(self, character);
    } else {
        _tokenType = NSParserTokenOther;
        NSParserAppendCharacter(self, character);
    }
    _tokenBufferReady = 1;
}

- (unsigned)peekTokenType {
    if (!_tokenBufferReady)
        [self nextToken];
    return _tokenType;
}

- (id)peekTokenWithMask:(unsigned)mask {
    if (![self peekTokenType] || (_tokenType & mask) == 0)
        return nil;
    return NSParserStringFromToken(self);
}

- (id)parseTokenWithMask:(unsigned)mask {
    id token;

    if (!_tokenBufferReady)
        [self nextToken];
    if ((_tokenType & mask) == 0)
        return nil;
    token = NSParserStringFromToken(self);
    _tokenBufferReady = 0;
    return token;
}

- (id)parseString { return [self parseTokenWithMask:6]; }
- (id)parseQuotedString { return [self parseTokenWithMask:NSParserTokenQuotedString]; }
- (id)parseUnquotedString { return [self parseTokenWithMask:NSParserTokenUnquotedString]; }
- (id)parseNumber { return [self parseTokenWithMask:NSParserTokenInteger | NSParserTokenFloat]; }
- (id)parseSeparator { return [self parseTokenWithMask:NSParserTokenSeparator]; }

- (id)parseTokenEqualTo:(NSString *)token mask:(unsigned)mask {
    NSString *parsed;

    if (!_tokenBufferReady)
        [self nextToken];
    if ((_tokenType & (unsigned char)mask) == 0 ||
        (_tokenIsASCII && _tokenCount != [token length]))
        return nil;
    if (_allStrings == NULL)
        _allStrings = NSCreateHashTableWithZone(
            NSNonRetainedObjectHashCallBacks, 6, _zone);
    if (NSHashGet(_allStrings, token) == nil)
        NSHashInsertKnownAbsent(_allStrings, [token copyWithZone:_zone]);
    parsed = NSParserStringFromToken(self);
    if (![parsed isEqualToString:token])
        return nil;
    _tokenBufferReady = 0;
    return token;
}

- (void)expectTokenEqualTo:(NSString *)token mask:(unsigned)mask {
    if ([self parseTokenEqualTo:token mask:mask] == nil)
        [self parseError:@"Token '%@' expected", token];
}

- (id)parseSeparatorEqualTo:(NSString *)separator {
    const unsigned char *bytes;
    unsigned length;
    unsigned index;

    if (!_tokenBufferReady)
        [self nextToken];
    if (_tokenType != NSParserTokenSeparator)
        return nil;
    bytes = (const unsigned char *)[separator cString];
    length = (unsigned)strlen((const char *)bytes);
    if (_tokenCount != length || !_tokenIsASCII)
        return nil;
    if (_tokenInputPos == 0x7fffffffU) {
        for (index = 0; index < length; index++) {
            if (((unsigned char *)_tokenBuffer)[index] != bytes[index])
                return nil;
        }
    } else if (!_inputIsASCII) {
        const unichar *input = (const unichar *)_input;
        for (index = 0; index < length; index++) {
            if (input[_tokenInputPos + index] != bytes[index])
                return nil;
        }
    } else if (memcmp((const unsigned char *)_input + _tokenInputPos,
                      bytes, length) != 0) {
        return nil;
    }
    _tokenBufferReady = 0;
    return separator;
}

- (void)expectSeparatorEqualTo:(NSString *)separator {
    if ([self parseSeparatorEqualTo:separator] == nil)
        [self parseError:@"Separator '%@' expected", separator];
}

- (id)expect:(id)rule {
    id result = [self parse:rule];
    if (result == nil) {
        _parseStack[_parseStackCount++] = [rule copyWithZone:NULL];
        [self parseError:@"%@ expected", rule];
    }
    return result;
}

- (void)expectEndOfInput {
    if ([self peekTokenType] != NSParserTokenEnd)
        [self parseError:@"End of input expected"];
}

- (id)parse:(id)rule {
    id production;
    SEL selector;
    id result;

    if (_parseStackCount >= _parseStackMax) {
        _parseStackMax = _parseStackMax * 2 + 1;
        _parseStack = NSZoneRealloc(_zone, _parseStack,
                                    _parseStackMax * sizeof(id));
    }
    _parseStack[_parseStackCount++] = [rule copyWithZone:NULL];
    production = [_grammar objectForKey:rule];
    if (production != nil &&
        *(Class *)(void *)production == NSParserSyntaxNodeClass) {
        result = NSParserParseSyntaxNode(self, production);
        [_parseStack[--_parseStackCount] release];
        return result;
    }
    if (production != nil) {
        result = [self parse:production];
        [_parseStack[--_parseStackCount] release];
        return result;
    }
    selector = NSSelectorFromString(rule);
    if (selector == NULL) {
        NSLog(@"*** Unimplemented ObjC selector '%@'; Could be a misspelled unit name",
              rule);
        result = nil;
    } else {
        result = [self performSelector:selector];
    }
    [_parseStack[--_parseStackCount] release];
    return result;
}

- (void)parseError:(NSString *)format, ... {
    va_list arguments;
    NSString *reason;
    NSString *nextToken;
    NSArray *units;

    va_start(arguments, format);
    reason = [[NSString allocWithZone:_zone]
        initWithFormat:format arguments:arguments];
    va_end(arguments);
    [reason autorelease];
#if defined(__ppc__) || defined(__POWERPC__)
    units = [NSArray arrayWithObjects:_parseStack count:_parseStackCount];
    nextToken = _tokenBufferReady ? NSParserStringFromToken(self)
                                  : __NSEmptyString;
#else
    nextToken = _tokenBufferReady ? NSParserStringFromToken(self)
                                  : __NSEmptyString;
    units = [NSArray arrayWithObjects:_parseStack count:_parseStackCount];
#endif
    [NSException raise:NSParseErrorException
                format:@"*** %@;\nParse error line %d (position %d) for units: %@;\nNext token is '%@'",
                       reason, (int)_inputLine, (int)_inputPos, units,
                       nextToken];
}

- (id)parseSuite:(id)rule separator:(id)separator
    allowOmitLastSeparator:(char)omit {
    id stackItems[128];
    id *items = stackItems;
    unsigned capacity = 128;
    unsigned count = 0;
    id item;

    while ((item = [self parse:rule]) != nil) {
        if (count + 1 > capacity) {
            if (capacity == 128) {
                capacity = 256;
                items = NSZoneMalloc(_zone, sizeof(id) * capacity);
                memmove(items, stackItems, sizeof(id) * 128);
            } else {
                capacity *= 2;
                items = NSZoneRealloc(_zone, items,
                                      sizeof(id) * capacity);
            }
        }
        items[count++] = item;
        if (separator == nil)
            continue;
        if (omit) {
            if ([self parseSeparatorEqualTo:separator] == nil)
                break;
        } else {
            [self expectSeparatorEqualTo:separator];
        }
    }
    NSArray *result = [[NSArray allocWithZone:_zone]
        initWithObjects:items count:count];
    if (items != stackItems)
        NSZoneFree(_zone, items);
    return [result autorelease];
}

- (id)parseSuiteOfPairsKey:(id)keyRule separator:(id)keySeparator
                     value:(id)valueRule separator:(id)valueSeparator
      allowOmitLastSeparator:(char)omit {
    NSMutableDictionary *items = [[NSMutableDictionary allocWithZone:_zone]
        initWithCapacity:32];
    id key;

#if defined(__ppc__) || defined(__POWERPC__)
    NS_DURING {
#endif
    while ((key = [self parse:keyRule]) != nil) {
        id value;
        if (keySeparator != nil)
            [self expectSeparatorEqualTo:keySeparator];
        value = [self expect:valueRule];
        [items setObject:value forKey:key];
        if (valueSeparator == nil)
            continue;
        if (omit) {
            if ([self parseSeparatorEqualTo:valueSeparator] == nil)
                break;
        } else {
            [self expectSeparatorEqualTo:valueSeparator];
        }
    }
#if defined(__ppc__) || defined(__POWERPC__)
    } NS_HANDLER {
        [items release];
        [localException raise];
    } NS_ENDHANDLER
#endif
    NSDictionary *result = [[NSDictionary allocWithZone:_zone]
        initWithDictionary:items];
    [items release];
    return [result autorelease];
}

- (id)parseDictionaryOfKey:(id)keyRule value:(id)valueRule {
    if ([self parseSeparatorEqualTo:@"{"] == nil)
        return nil;
    if ([self parseSeparatorEqualTo:@"}"] != nil)
        return [NSDictionary dictionary];
    id dictionary = [self parseSuiteOfPairsKey:keyRule separator:@"="
        value:valueRule separator:@";" allowOmitLastSeparator:1];
    [self expectSeparatorEqualTo:@"}"];
    return dictionary;
}

- (id)parseData {
    NSMutableData *data;
    unsigned dataLength = 0;

    if ([self parseSeparatorEqualTo:@"<"] == nil)
        return nil;
    data = [[NSMutableData allocWithZone:_zone] init];
    for (;;) {
        id pair = [self parseTokenWithMask:NSParserTokenUnquotedString];
        const char *characters;
        unsigned index;
        unsigned length;
        if (pair == nil)
            break;
        characters = [pair cString];
        length = strlen(characters);
        if ((length & 1) != 0)
            [self parseError:
                @"Data representation should always contain an even number of hex digits: '%@'",
                pair];
        [data setLength:dataLength + (length >> 1)];
        unsigned char *output = (unsigned char *)[data mutableBytes] + dataLength;
        dataLength += length >> 1;
        for (index = 0; index < length; index += 2) {
            unsigned char high = NSParserFromHexDigit(
                self, (unsigned char)characters[index]);
            unsigned char low = NSParserFromHexDigit(
                self, (unsigned char)characters[index + 1]);
            *output++ = (unsigned char)((high << 4) | low);
        }
    }
    [self expectSeparatorEqualTo:@">"];
    return [data autorelease];
}

+ (id)parsedGrammarForString:(NSString *)string {
    NSMutableDictionary *grammar;
    NSParser *parser;
    id result;

    if (NSParserSyntaxNodeClass == Nil)
        NSParserSyntaxNodeClass = [_NSParserSyntaxNode class];
    grammar = [[NSMutableDictionary allocWithZone:NULL] initWithCapacity:3];
    [grammar setObject:@"parseUnquotedString" forKey:@"Token"];
    [grammar setObject:@"parseMetaSyntaxSequence" forKey:@"MetaSyntaxSequence"];
    [grammar setObject:@"parseMetaRuleBody" forKey:@"MetaRuleBody"];
    parser = [[NSParser allocWithZone:NULL] initWithGrammar:grammar];
    [parser setMultipleCharacterSeparators:[NSArray arrayWithObject:@"||"]];
    [parser setQuotingWithSingleQuote:1 double:1];
    [parser setString:string];
    [grammar release];
    result = [parser parseSuiteOfPairsKey:@"Token" separator:@"="
        value:@"MetaRuleBody" separator:@";" allowOmitLastSeparator:0];
    [parser expectEndOfInput];
    [parser release];
    return result;
}

- (id)parseMetaRuleBody {
    NSMutableArray *choices;
    id sequence = [self expect:@"MetaSyntaxSequence"];
    if ([self parseSeparatorEqualTo:@"|"] != nil) {
        choices = [[NSMutableArray allocWithZone:_zone] initWithCapacity:16];
        [choices addObject:sequence];
        do {
            sequence = [self expect:@"MetaSyntaxSequence"];
            [choices addObject:sequence];
        } while ([self parseSeparatorEqualTo:@"|"] != nil);
        sequence = [[_NSParserSyntaxNode allocWithZone:_zone]
            initWithType:2 arg:choices];
        [choices release];
        return [sequence autorelease];
    }
    if ([self parseSeparatorEqualTo:@"||"] != nil) {
        choices = [[NSMutableArray allocWithZone:_zone] initWithCapacity:16];
        [choices addObject:sequence];
        do {
            sequence = [self expect:@"MetaSyntaxSequence"];
            [choices addObject:sequence];
        } while ([self parseSeparatorEqualTo:@"||"] != nil);
        sequence = [[_NSParserSyntaxNode allocWithZone:_zone]
            initWithType:3 arg:choices];
        [choices release];
        return [sequence autorelease];
    }
    return sequence;
}

- (id)parseMetaSyntaxSequence {
    NSMutableArray *parts;
    unsigned selected = 0x7fffffffU;
    unsigned values = 0;
    id part;
    id nextPart;
    char firstShouldSkip = 0;
    char nextShouldSkip = 0;
    char shouldSkip = 0;

    part = [self parseMetaSyntaxLeafResultShouldBeSkipped:&firstShouldSkip];
    if (part == nil)
        return nil;
    nextPart = [self parseMetaSyntaxLeafResultShouldBeSkipped:&nextShouldSkip];
    if (nextPart == nil)
        return part;

    parts = [[NSMutableArray allocWithZone:_zone] initWithCapacity:16];
    if (!firstShouldSkip) {
        selected = values++;
    }
    [parts addObject:part];
    if (!nextShouldSkip) {
        selected = [parts count];
        values++;
    }
    [parts addObject:nextPart];
    while ((part = [self parseMetaSyntaxLeafResultShouldBeSkipped:&shouldSkip]) != nil) {
        if (!shouldSkip) {
            selected = [parts count];
            values++;
        }
        [parts addObject:part];
    }
    _NSParserSyntaxNode *sequence = [[_NSParserSyntaxNode allocWithZone:_zone]
        initWithType:1 arg:parts];
    if (values == 1)
        sequence->theIndex = selected;
    else
        sequence->theIndex = 0x7fffffffU;
    [parts release];
    return [sequence autorelease];
}

- (id)parseMetaSyntaxLeafResultShouldBeSkipped:(char *)shouldSkip {
    id token = [self parseUnquotedString];

    *shouldSkip = 0;
    if (token != nil)
        return token;
    token = [self parseQuotedString];
    if (token != nil) {
        *shouldSkip = 1;
        return [[[_NSParserSyntaxNode allocWithZone:_zone]
            initWithType:0 arg:token] autorelease];
    }
    if ([self parseSeparatorEqualTo:@"<"] != nil) {
        id body = [self parseMetaRuleBody];
        [self expectSeparatorEqualTo:@">"];
        return [[[_NSParserSyntaxNode allocWithZone:_zone]
            initWithType:4 arg:body] autorelease];
    }
    return nil;
}

@end

static NSDictionary *NSPropertyListGrammar;

id _NSParseObjectFromASCIIPropertyListOrSerialization(NSData *data) {
    const unsigned char *bytes;
    unsigned length;
    unsigned cursor = 0;
    NSStringEncoding encoding;
    NSString *string = nil;
    id result = nil;

    length = [data length];
    bytes = [data bytes];
    if ((length & 3) == 0 && length > 7 && bytes[0] <= 0x1f &&
        bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0)
        return [NSDeserializer deserializePropertyListFromData:data
            atCursor:&cursor mutableContainers:NO];

    if (length > 1 && (length & 1) == 0 &&
        ((bytes[0] == 0xfe && bytes[1] == 0xff) ||
         (bytes[0] == 0xff && bytes[1] == 0xfe)))
        encoding = NSUnicodeStringEncoding;
    else
        encoding = [NSString defaultCStringEncoding];
    string = [[NSString allocWithZone:NULL]
        initWithData:data encoding:encoding];

    if (string != nil) {
        NS_DURING {
            result = [string propertyList];
        } NS_HANDLER {
            NS_DURING {
                result = [string propertyListFromStringsFileFormat];
            } NS_HANDLER {
                result = nil;
            } NS_ENDHANDLER
        } NS_ENDHANDLER
    }
    [string release];
    return result;
}

@implementation NSPropertyListParser

- (id)initWithString:(NSString *)string {
    if (NSPropertyListGrammar == nil)
        NSPropertyListGrammar = [[[self class] parsedGrammarForString:@"String = parseString; Array = parseArray; Dictionary = parseDictionary; Data = parseData; xObject = Dictionary | Array | Data | String;"] copyWithZone:[self zone]];
    [self initWithGrammar:NSPropertyListGrammar];
    [self setString:string];
    return self;
}

- (id)parseDictionary {
    return [self parseDictionaryOfKey:@"String" value:@"xObject"];
}

- (id)parseArray {
    if ([self parseSeparatorEqualTo:@"("] == nil)
        return nil;
    id result = [self parseSuite:@"xObject" separator:@","
        allowOmitLastSeparator:1];
    [self expectSeparatorEqualTo:@")"];
    return result;
}

@end

@implementation _NSPListParserOldStyle

- (id)parseDictionary {
    if ([self parseSeparatorEqualTo:@"{"] == nil)
        return nil;
    if ([self parseSeparatorEqualTo:@"}"] != nil)
        return [NSDictionary dictionary];
    id result = [self parseDictionaryBracketLess];
    [self expectSeparatorEqualTo:@"}"];
    return result;
}

- (id)parseDictionaryBracketLess {
    NSMutableDictionary *dictionary;
    id key;

#if defined(__ppc__) || defined(__POWERPC__)
    dictionary = [NSMutableDictionary dictionaryWithCapacity:40];
#else
    dictionary = [NSMutableDictionary dictionaryWithCapacity:12];
#endif

    while ((key = [self parse:@"String"]) != nil) {
        id value;
        if ([self parseSeparatorEqualTo:@"="] != nil)
            value = [self expect:@"parseString"];
        else
            value = key;
        [dictionary setObject:value forKey:key];
        if ([self parseSeparatorEqualTo:@";"] == nil)
            break;
    }
    return dictionary;
}

- (id)parseOldOrNewStringsFile {
    if ([self parseSeparatorEqualTo:@"{"] == nil)
        return [self parseDictionaryBracketLess];
    if ([self parseSeparatorEqualTo:@"}"] != nil)
        return [NSDictionary dictionary];
    id result = [self parseDictionaryBracketLess];
    [self expectSeparatorEqualTo:@"}"];
    return result;
}

@end

@implementation NSString (NSExtendedStringPropertyListParsing)

- (id)propertyList {
    unsigned pool = NSPushAutoreleasePool();
    NSPropertyListParser *parser = [[NSPropertyListParser allocWithZone:NULL]
        initWithString:self];
    id result = nil;
    NS_DURING {
        result = [parser expect:@"xObject"];
        [parser expectEndOfInput];
        [result retain];
    } NS_HANDLER {
        [parser release];
        [localException retain];
        NSPopAutoreleasePool(pool);
        [localException autorelease];
        [localException raise];
    } NS_ENDHANDLER
    [parser release];
    NSPopAutoreleasePool(pool);
    return [result autorelease];
}

- (NSDictionary *)propertyListFromStringsFileFormat {
    unsigned pool = NSPushAutoreleasePool();
    _NSPListParserOldStyle *parser = [[_NSPListParserOldStyle allocWithZone:NULL]
        initWithString:self];
    id result = nil;
    NS_DURING {
        result = [parser parseOldOrNewStringsFile];
        [parser expectEndOfInput];
        [result retain];
    } NS_HANDLER {
        [parser release];
        [localException retain];
        NSPopAutoreleasePool(pool);
        [localException autorelease];
        [localException raise];
    } NS_ENDHANDLER
    [parser release];
    NSPopAutoreleasePool(pool);
    return [result autorelease];
}

@end
