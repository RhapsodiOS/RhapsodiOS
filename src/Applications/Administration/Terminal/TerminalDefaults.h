#ifndef TERMINAL_DEFAULTS_H
#define TERMINAL_DEFAULTS_H

#include "Emulation.h"
#include "Terminal.h"

#import <Foundation/NSCoder.h>
#import <Foundation/NSZone.h>

TerminalEmulationDefaults *defaultsFromDB(NSZone *zone);
void getDefaultColors(id *colors);
void writeDefaultsToTypedStream(const TerminalEmulationDefaults *defaults,
    const struct TerminalExtraWindowInfo *windowInfo, NSCoder *stream);
TerminalEmulationDefaults *readDefaultsFromTypedStream(NSCoder *stream,
    struct TerminalExtraWindowInfo *windowInfo, NSZone *zone);

#endif
