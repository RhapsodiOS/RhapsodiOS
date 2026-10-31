#ifndef TERMINAL_TERMINALAGENT_H
#define TERMINAL_TERMINALAGENT_H

#import <Foundation/NSObject.h>

#include "Emulation.h"

@class Terminal;

@interface TerminalAgent : NSObject
{
    Terminal *terminal;
}

- (void)setTerminal:(Terminal *)value;
- (Terminal *)terminal;
- (id)initDefaults:(const TerminalEmulationDefaults *)defaults
    inFolder:(const char *)folder env:(char **)environment;

@end

#endif
