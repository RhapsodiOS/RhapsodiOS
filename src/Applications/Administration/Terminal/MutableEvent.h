#ifndef TERMINAL_MUTABLE_EVENT_H
#define TERMINAL_MUTABLE_EVENT_H

#import <AppKit/NSEvent.h>

@interface MutableEvent : NSEvent
+ (id)mutableEventWithEvent:(NSEvent *)event;
- (char)charValue;
- (void)setChar:(char)character;
- (void)setChars:(NSString *)characters;
- (void)setKeyCode:(unsigned int)keyCode;
- (void)setModifierFlags:(unsigned int)modifierFlags;
@end

#endif
