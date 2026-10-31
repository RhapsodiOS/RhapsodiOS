#import "MutableEvent.h"

@implementation MutableEvent

+ (id)mutableEventWithEvent:(NSEvent *)event
{
    return [self keyEventWithType:[event type]
                         location:[event locationInWindow]
                     modifierFlags:[event modifierFlags]
                         timestamp:[event timestamp]
                      windowNumber:[event windowNumber]
                           context:[event context]
                        characters:[event characters]
       charactersIgnoringModifiers:[event charactersIgnoringModifiers]
                         isARepeat:[event isARepeat]
                            keyCode:[event keyCode]];
}

- (char)charValue
{
    unsigned char *cache = (unsigned char *)&_reservedEvent1;

    if (cache[0] == 0) {
        NSString *keys = _data.key.keys;

        if (keys != nil && [keys length] != 0) {
            NSString *firstCharacter = [keys substringWithRange:NSMakeRange(0, 1)];
            if ([firstCharacter canBeConvertedToEncoding:
                    [NSString defaultCStringEncoding]])
                [firstCharacter getCString:(char *)cache maxLength:1];
        }
    }
    return (char)((signed char)cache[0]);
}

- (void)setChar:(char)character
{
    [_data.key.keys release];
    _data.key.keys = [[NSString allocWithZone:NULL]
        initWithCString:&character length:1];
    ((unsigned char *)&_reservedEvent1)[0] = (unsigned char)character;
}

- (void)setChars:(NSString *)characters
{
    [_data.key.keys release];
    _data.key.keys = [characters retain];
    ((unsigned char *)&_reservedEvent1)[0] = 0;
}

- (void)setKeyCode:(unsigned int)keyCode
{
    _data.key.keyCode = (unsigned short)keyCode;
}

- (void)setModifierFlags:(unsigned int)modifierFlags
{
    _modifierFlags = modifierFlags;
}

@end
