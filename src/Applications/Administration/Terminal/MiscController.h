#ifndef TERMINAL_MISC_CONTROLLER_H
#define TERMINAL_MISC_CONTROLLER_H

#import <Foundation/NSObject.h>
#import "Emulation.h"

@class NSButtonCell;
@class NSMatrix;
@class NSTextField;

@interface MiscController : NSObject
{
    id autoFocusCheck;
    id wrapCheck;
    id lineLimitField;
    id linesUnlimited;
    id linesLimited;
    id scrollbackEnableCheck;
    id okButton;
    id otherOptionsMatrix;
    unsigned char revertScrollback;
    unsigned char revertAutoFocus;
    unsigned char revertAutowrap;
    unsigned char _padding0;
    int revertSaveLines;
}

- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults;
- (void)showDefault:(char)show;
- (void)suggest;
- (void)setScrollback:(char)scrollback lines:(int)lines wrap:(char)wrap
    autoFocus:(char)autoFocus lock:(char)lock;
- (void)displayScrollback:(char)scrollback lines:(int)lines wrap:(char)wrap
    autoFocus:(char)autoFocus;
- (void)revert;
- (id)setDefault;
- (void)setStruct:(TerminalEmulationDefaults *)defaults;
- (char)checkSettings;
- (void)firstVisible:(id)sender;
- (void)lastVisible:(id)sender;
- (void)handleReturn:(id)sender;
- (void)limitLines:(id)sender;
- (void)unlimitLines:(id)sender;

@end

#endif
