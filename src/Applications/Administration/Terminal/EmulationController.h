#ifndef TERMINAL_EMULATION_CONTROLLER_H
#define TERMINAL_EMULATION_CONTROLLER_H

#import <Foundation/NSObject.h>
#import "Emulation.h"

@interface EmulationController : NSObject
{
    id translateCheck;
    id altMatrix;
    id keypadCheck;
    id strictCheck;
    id altMsg;
    id altBox;
    id checkMatrix;
    int revertMeta;
    unsigned char revertTranslate;
    unsigned char revertKeypad;
    unsigned char revertStrict;
    unsigned char _padding0;
}

- (void)lastVisible:(id)sender;
- (void)firstVisible:(id)sender;
- (void)showDefault:(char)show;
- (id)setDefault;
- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults;
- (void)suggest:(id)sender;
- (void)setMeta:(int)meta opts:(char)translate :(char)keypad :(char)strict lock:(char)lock;
- (void)revert:(id)sender;
- (void)setStruct:(TerminalEmulationDefaults *)defaults;
- (void)displayValues:(int)meta :(char)translate :(char)keypad :(char)strict;

@end


_Static_assert(sizeof(EmulationController) == 40,
    "Terminal EmulationController PPC/i386 instance size");

typedef struct {
    @defs(EmulationController);
} EmulationControllerLayout;

_Static_assert(__builtin_offsetof(EmulationControllerLayout, translateCheck) == 4,
    "Terminal EmulationController first outlet offset");
_Static_assert(__builtin_offsetof(EmulationControllerLayout, revertMeta) == 32,
    "Terminal EmulationController revert meta offset");
_Static_assert(__builtin_offsetof(EmulationControllerLayout, revertTranslate) == 36,
    "Terminal EmulationController revert translate offset");
_Static_assert(__builtin_offsetof(EmulationControllerLayout, revertStrict) == 38,
    "Terminal EmulationController revert strict offset");

#endif
