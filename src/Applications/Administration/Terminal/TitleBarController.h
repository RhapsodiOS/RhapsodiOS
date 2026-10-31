#ifndef TERMINAL_TITLE_BAR_CONTROLLER_H
#define TERMINAL_TITLE_BAR_CONTROLLER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
#import "Emulation.h"

@interface TitleBarController : NSObject
{
    id elementMatrix;
    id titleForm;
    id fakeTitle;
    NSRect maxFakeTitleFrame;
    int revertBits;
    char *revertCustomTitle;
    id prefObject;
}
- (id)init;
- (void)awakeFromNib;
- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults;
- (void)showDefault:(char)show;
- (void)suggest;
- (void)setBits:(int)bits custom:(const char *)custom lock:(char)lock;
- (void)displayBits:(int)bits custom:(const char *)custom;
- (void)revert;
- (id)setDefault;
- (int)titleBits;
- (char)checkSettings;
- (void)setStruct:(TerminalEmulationDefaults *)defaults;
- (void)firstVisible:(id)sender;
- (void)lastVisible:(id)sender;
- (void)titleBitsChanged:(id)sender;
- (void)textDidEndEditing:(id)sender;
@end

typedef struct {
    id isa;
    id elementMatrix;
    id titleForm;
    id fakeTitle;
    NSRect maxFakeTitleFrame;
    int revertBits;
    char *revertCustomTitle;
    id prefObject;
} TitleBarControllerLayout;

#if defined(__rhapsody__) || defined(TARGET_OS_RHAPSODY)
_Static_assert(sizeof(TitleBarController) == 44,
    "Terminal TitleBarController PPC/i386 instance size");
_Static_assert(__builtin_offsetof(TitleBarControllerLayout, elementMatrix) == 4,
    "Terminal TitleBarController matrix offset");
_Static_assert(__builtin_offsetof(TitleBarControllerLayout, titleForm) == 8,
    "Terminal TitleBarController form offset");
_Static_assert(__builtin_offsetof(TitleBarControllerLayout, fakeTitle) == 12,
    "Terminal TitleBarController preview offset");
_Static_assert(__builtin_offsetof(TitleBarControllerLayout, revertBits) == 32,
    "Terminal TitleBarController revert bits offset");
_Static_assert(__builtin_offsetof(TitleBarControllerLayout, prefObject) == 40,
    "Terminal TitleBarController preference object offset");
#endif

#endif
