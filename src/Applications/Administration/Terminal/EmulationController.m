#import "EmulationController.h"
#import <AppKit/NSMatrix.h>
#import <Foundation/NSUserDefaults.h>

extern id _theDefaultsObject;

@interface EmulationController (DisplayValues)
- (void)displayValues:(int)meta :(char)translate :(char)keypad :(char)strict;
@end

@interface EmulationController (ControlState)
- (int)state;
- (void)setState:(int)state;
- (id)selectedCell;
@end

@interface EmulationController (CellTag)
- (int)tag;
@end

@interface EmulationController (DisplayControls)
- (void)deselectAllCells;
- (BOOL)isEnabled;
- (BOOL)abortEditing;
- (BOOL)resignFirstResponder;
- (void)setTitle:(id)title;
- (void)display;
@end

@implementation EmulationController

- (void)lastVisible:(id)sender
{
    (void)sender;
}

- (void)firstVisible:(id)sender
{
    [(NSMatrix *)sender selectCellWithTag:31];
}

- (void)showDefault:(char)show
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    int meta;
    char translate;
    char keypad;
    char strict;

    [defaults synchronize];
    meta = [defaults integerForKey:@"Meta"];
    translate = (char)[defaults boolForKey:@"Translate"];
    keypad = (char)[defaults boolForKey:@"Keypad"];
    strict = (char)[defaults boolForKey:@"StrictEmulation"];
    [self setMeta:meta opts:translate :keypad :strict lock:show];
}

- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults
{
    [self setMeta:defaults->var9
        opts:(char)(unsigned char)defaults->var6
        :(char)(unsigned char)defaults->var2
        :(char)(unsigned char)defaults->var5
        lock:1];
}

- (void)suggest:(id)sender
{
    (void)sender;
    [self setMeta:-1 opts:1 :0 :0 lock:0];
}

- (void)setMeta:(int)meta opts:(char)translate :(char)keypad :(char)strict lock:(char)lock
{
    if (lock) {
        revertMeta = meta;
        revertTranslate = (unsigned char)translate;
        revertKeypad = (unsigned char)keypad;
        revertStrict = (unsigned char)strict;
    }
    [self displayValues:meta :translate :keypad :strict];
}

- (void)revert:(id)sender
{
    (void)sender;
    [self setMeta:revertMeta opts:(char)revertTranslate
        :(char)revertKeypad :(char)revertStrict lock:0];
}

- (void)setStruct:(TerminalEmulationDefaults *)defaults
{
    id selectedCell;

    defaults->var6 = (signed char)[translateCheck state];
    defaults->var2 = (signed char)[keypadCheck state];
    defaults->var5 = (signed char)[strictCheck state];
    if (altMsg != nil) {
        defaults->var9 = (signed char)revertMeta;
    } else {
        selectedCell = [altMatrix selectedCell];
        defaults->var9 = (signed char)[selectedCell tag];
    }
}

- (void)displayValues:(int)meta :(char)translate :(char)keypad :(char)strict
{
    [keypadCheck setState:keypad];
    [strictCheck setState:strict];
    [translateCheck setState:translate];
    [(NSMatrix *)checkMatrix deselectAllCells];

    if (meta >= -1 && (meta <= 0 || meta == 27)) {
        if (altMsg != nil && [altMsg isEnabled]) {
            [altMsg abortEditing];
            [altMsg resignFirstResponder];
        }
        [(NSMatrix *)altMatrix selectCellWithTag:meta];
    } else {
        if (altMsg != nil)
            return;
        [altBox setTitle:altMsg];
    }
    [altBox display];
}

- (id)setDefault
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    id selectedCell;

    [defaults setBool:[translateCheck state] forKey:@"Translate"];
    [defaults setBool:[keypadCheck state] forKey:@"Keypad"];
    [defaults setBool:[strictCheck state] forKey:@"StrictEmulation"];
    if (altMsg != nil) {
        [defaults setInteger:revertMeta forKey:@"Meta"];
    } else {
        selectedCell = [altMatrix selectedCell];
        [defaults setInteger:[selectedCell tag] forKey:@"Meta"];
    }
    return self;
}

@end
