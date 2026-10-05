#ifndef TERMINAL_FONT_TRAP_H
#define TERMINAL_FONT_TRAP_H

#import <AppKit/NSView.h>

@interface FontTrap : NSView
{
    id fontTarget;
    id targetProxy;
}

- (id)initWithFrame:(NSRect)frame;
- (BOOL)acceptsFirstResponder;
- (void)changeFont:(id)sender;
- (BOOL)resignFirstResponder;

@end

#endif
