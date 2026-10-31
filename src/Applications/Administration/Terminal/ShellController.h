#ifndef TERMINAL_SHELL_CONTROLLER_H
#define TERMINAL_SHELL_CONTROLLER_H

#import <Foundation/NSObject.h>
#import "Emulation.h"

@interface ShellController : NSObject
{
    id sourceCheck;
    id shellForm;
}
- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults;
- (void)showDefault:(char)show;
- (void)setShell:(const char *)shell source:(char)source;
- (void)revert;
- (id)setDefault;
- (void)suggest;
- (void)setStruct:(TerminalEmulationDefaults *)defaults;
- (char)checkSettings;
- (void)firstVisible:(id)sender;
- (void)lastVisible:(id)sender;
- (void)shellChanged:(id)sender;
- (void)sourceDotLoginChanged:(id)sender;
@end

#endif
