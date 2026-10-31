#ifndef TERMINAL_WINDOW_CONTROLLER_H
#define TERMINAL_WINDOW_CONTROLLER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

#include "Emulation.h"

@interface WindowController : NSObject
{
    id sizeForm;
    id shellExitMatrix;
    id fontField;
    id fontTrap;
    char *revertFont;
    float revertFontSize;
    int revertShellExit;
    int revertRows;
    int revertColumns;
}

- (id)receiveFontFromTrap:(id)font;
- (void)setFontRequest:(id)sender;
- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults;
- (void)setStruct:(TerminalEmulationDefaults *)defaults;
- (void)showDefault:(char)show;
- (void)suggest;
- (void)setRows:(int)rows cols:(int)columns exitAction:(int)exitAction font:(const char *)fontName size:(float)fontSize lock:(BOOL)lock;
- (void)displayRows:(int)rows cols:(int)columns exitAction:(int)exitAction font:(const char *)fontName size:(float)fontSize;
- (void)revert;
- (id)setDefault;
- (void)firstVisible:(id)sender;
- (void)lastVisible:(id)sender;
- (id)fontTrapDidResignFirstResponder;
- (void)windowDidResignKey:(id)notification;

@end

#endif
