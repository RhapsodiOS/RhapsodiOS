#ifndef TERMINAL_TEXT_ATTRIBUTE_CONTROLLER_H
#define TERMINAL_TEXT_ATTRIBUTE_CONTROLLER_H

#import <Foundation/NSObject.h>
#import "Emulation.h"

@interface TextAttributeController : NSObject
{
    id prefObject;
    id BlinkTextWell;
    id BoldTextWell;
    id CursorBlinkButton;
    id CursorWell;
    id DoubleStrikeButton;
    id InverseBackWell;
    id InverseTextWell;
    id NormalBackWell;
    id NormalTextWell;
    id SelectionWell;
    id CursorSelector;
}
- (void)revert;
- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults;
- (id)setDefault;
- (void)showDefault:(char)show;
- (void)suggest;
- (void)setStruct:(TerminalEmulationDefaults *)defaults;
- (void)firstVisible:(id)sender;
- (void)lastVisible:(id)sender;
- (void)windowDidBecomeKey:(id)notification;
@end

typedef struct {
    id isa;
    id prefObject;
    id BlinkTextWell;
    id BoldTextWell;
    id CursorBlinkButton;
    id CursorWell;
    id DoubleStrikeButton;
    id InverseBackWell;
    id InverseTextWell;
    id NormalBackWell;
    id NormalTextWell;
    id SelectionWell;
    id CursorSelector;
} TextAttributeControllerLayout;

#if defined(__rhapsody__) || defined(TARGET_OS_RHAPSODY)
_Static_assert(sizeof(TextAttributeController) == 52,
    "Terminal TextAttributeController PPC/i386 instance size");
_Static_assert(__builtin_offsetof(TextAttributeControllerLayout, prefObject) == 4,
    "Terminal TextAttributeController preference object offset");
_Static_assert(__builtin_offsetof(TextAttributeControllerLayout, CursorSelector) == 48,
    "Terminal TextAttributeController cursor selector offset");
#endif

#endif
