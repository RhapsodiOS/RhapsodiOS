#import "TextAttributeController.h"

#import <AppKit/NSColor.h>
#import <AppKit/NSColorPanel.h>
#import <AppKit/NSColorWell.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSMatrix.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

#include <stdio.h>

#import "Terminal.h"
#import "TerminalDefaults.h"

@interface NSObject (TextAttributeControllerPreferencesCallbacks)
- (void)setUpButtons:(int)flags;
- (id)currentTerminal;
@end

extern id _theDefaultsObject;
static void textColorWells(TextAttributeController *controller, id *wells)
{
    TextAttributeControllerLayout *layout =
        (TextAttributeControllerLayout *)controller;

    wells[0] = layout->NormalTextWell;
    wells[1] = layout->InverseTextWell;
    wells[2] = layout->BoldTextWell;
    wells[3] = layout->BlinkTextWell;
    wells[4] = layout->NormalBackWell;
    wells[5] = layout->InverseBackWell;
    wells[6] = layout->SelectionWell;
    wells[7] = layout->CursorWell;
}

@implementation TextAttributeController

- (void)revert
{
}

- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults
{
    id wells[8];
    unsigned attributes = (unsigned)defaults->var20;
    unsigned index;

    textColorWells(self, wells);
    for (index = 0; index < 8; index++)
        [(NSColorWell *)wells[index] setColor:defaults->var19[index]];
    [(NSMatrix *)CursorSelector selectCellWithTag:attributes & 3];
    [CursorBlinkButton setState:(attributes >> 2) & 1];
    [DoubleStrikeButton setState:(attributes >> 3) & 1];
}

- (id)setDefault
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    char colorString[160];
    size_t used = 0;
    unsigned index;
    id wells[8];
    NSColorPanel *panel = [NSColorPanel sharedColorPanel];
    float red;
    float green;
    float blue;
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    id selected;
    int attributes;

    textColorWells(self, wells);
    colorString[0] = '\0';
    for (index = 0; index < 8; index++) {
        NSColor *color = [[(NSColorWell *)wells[index] color]
            colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

        [panel setColor:color];
        [[panel color] getRed:&red green:&green blue:&blue alpha:NULL];
        used += (size_t)sprintf(colorString + used, "%s%f %f %f",
            index == 0 ? "" : " ", red, green, blue);
    }
    [defaults setObject:[NSString stringWithCString:colorString]
        forKey:@"TextColors"];

    selected = [CursorSelector selectedCell];
    attributes = ([selected tag] & 3) |
        ([(NSButtonCell *)CursorBlinkButton state] << 2) |
        ([(NSButtonCell *)DoubleStrikeButton state] << 3);
    [defaults setInteger:attributes forKey:@"TextAttributes"];
    [pool release];
    return self;
}

- (void)showDefault:(char)show
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    id colors[8] = { nil, nil, nil, nil, nil, nil, nil, nil };
    id wells[8];
    unsigned attributes;
    unsigned index;

    (void)show;
    textColorWells(self, wells);
    [defaults synchronize];
    getDefaultColors(colors);
    for (index = 0; index < 8; index++)
        [(NSColorWell *)wells[index] setColor:colors[index]];

    attributes = (unsigned)[defaults integerForKey:@"TextAttributes"];
    [(NSMatrix *)CursorSelector selectCellWithTag:attributes & 3];
    [(NSButtonCell *)CursorBlinkButton setState:(attributes >> 2) & 1];
    [(NSButtonCell *)DoubleStrikeButton setState:(attributes >> 3) & 1];
}

- (void)suggest
{
}

- (void)setStruct:(TerminalEmulationDefaults *)defaults
{
    id wells[8];
    id selected = [CursorSelector selectedCell];
    unsigned index;

    textColorWells(self, wells);
    for (index = 0; index < 8; index++) {
        id oldColor = defaults->var19[index];
        id color = [(NSColorWell *)wells[index] color];

        defaults->var19[index] = [color copy];
        [oldColor release];
    }
    defaults->var20 = ([selected tag] & 3);
    defaults->var20 |= (
        [(NSButtonCell *)CursorBlinkButton state] << 2);
    defaults->var20 |= (
        [(NSButtonCell *)DoubleStrikeButton state] << 3);
}

- (void)firstVisible:(id)sender
{
    [sender setUpButtons:31];
    prefObject = sender;
}

- (void)lastVisible:(id)sender
{
    (void)sender;
}

- (void)windowDidBecomeKey:(id)notification
{
    id terminal;

    (void)notification;
    terminal = [prefObject currentTerminal];
    if (terminal != nil)
        [self setFromStruct:(const TerminalEmulationDefaults *)
            [terminal defaults]];
}

@end
