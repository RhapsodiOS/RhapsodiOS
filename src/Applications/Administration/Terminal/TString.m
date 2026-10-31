#import "TString.h"

#include <string.h>

@implementation TString

- (id)_createIfNecessary
{
    if (text == NULL) {
        text = ChunkMalloc(1, 0x20, 0, 0x10, [self zone]);
        text->elements[0] = 0;
        text->count = 1;
    }
    return self;
}

- (id)stringValue
{
    if (text == NULL)
        return nil;
    return [NSString stringWithCString:(const char *)text->elements];
}

- (void)setStringValue:(id)value
{
    const char *valueBytes;
    unsigned int length;

    [self _createIfNecessary];
    if (value == nil)
        value = @"";
    length = [value cStringLength];
    text = ChunkGrow(text, length);
    valueBytes = [value cString];
    strcpy((char *)text->elements, valueBytes);
    text->count = length + 1;
}

- (void)empty
{
    ChunkFree(text);
    text = NULL;
}

- (void)dealloc
{
    [self empty];
    [super dealloc];
}

@end
