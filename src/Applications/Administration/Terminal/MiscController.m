#import "MiscController.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSTextField.h>
#import <Foundation/NSUserDefaults.h>

extern id _theDefaultsObject;

@interface MiscController (Controls)
- (int)state;
- (int)intValue;
- (void)setState:(int)state;
- (void)setIntValue:(int)value;
- (id)cellAtRow:(int)row column:(int)column;
- (void)setStringValue:(id)value;
- (void)selectText:(id)sender;
- (void)setDelegate:(id)delegate;
- (void)display;
@end

@interface NSObject (PreferencesButtonSetup)
- (void)setUpButtons:(int)count;
@end

@implementation MiscController

- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults
{
    [self setScrollback:(char)defaults->var3 lines:defaults->var17
        wrap:(char)defaults->var1 autoFocus:(char)defaults->var0 lock:1];
}

- (void)showDefault:(char)show
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;

    [defaults synchronize];
    [self setScrollback:(char)[defaults boolForKey:@"Scrollback"]
        lines:[defaults integerForKey:@"SaveLines"]
        wrap:(char)[defaults boolForKey:@"Autowrap"]
        autoFocus:(char)[defaults boolForKey:@"AutoFocus"] lock:1];
}

- (void)suggest
{
    [self setScrollback:1 lines:-1 wrap:1 autoFocus:0 lock:0];
}

- (void)setScrollback:(char)scrollback lines:(int)lines wrap:(char)wrap
    autoFocus:(char)autoFocus lock:(char)lock
{
    if (lock) {
        revertScrollback = (unsigned char)scrollback;
        revertAutoFocus = (unsigned char)autoFocus;
        revertAutowrap = (unsigned char)wrap;
        revertSaveLines = lines;
    }
    [self displayScrollback:scrollback lines:lines wrap:wrap autoFocus:autoFocus];
}

- (void)displayScrollback:(char)scrollback lines:(int)lines wrap:(char)wrap
    autoFocus:(char)autoFocus
{
    [scrollbackEnableCheck setState:scrollback != 0];
    [wrapCheck setState:wrap != 0];
    [autoFocusCheck setState:autoFocus != 0];

    if (lines <= 0) {
        [lineLimitField setStringValue:@"No Wrapper"];
        [[linesLimited cellAtRow:0 column:0] setState:0];
        [[linesUnlimited cellAtRow:0 column:0] setState:1];
    } else {
        [lineLimitField setIntValue:lines];
        [[linesLimited cellAtRow:0 column:0] setState:1];
        [[linesUnlimited cellAtRow:0 column:0] setState:0];
    }
    [linesLimited display];
    [linesUnlimited display];
    [otherOptionsMatrix display];
}

- (void)revert
{
    [self setScrollback:(char)revertScrollback lines:revertSaveLines
        wrap:(char)revertAutowrap autoFocus:(char)revertAutoFocus lock:0];
}

- (id)setDefault
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;

    if ([scrollbackEnableCheck state]) {
        if ([[linesUnlimited cellAtRow:0 column:0] state])
            [defaults setInteger:-1 forKey:@"SaveLines"];
        else
            [defaults setInteger:[lineLimitField intValue] forKey:@"SaveLines"];
        [defaults setBool:[wrapCheck state] forKey:@"Autowrap"];
        [defaults setBool:[autoFocusCheck state] forKey:@"AutoFocus"];
        [defaults setBool:[scrollbackEnableCheck state] forKey:@"Scrollback"];
    }
    return self;
}

- (void)setStruct:(TerminalEmulationDefaults *)defaults
{
    if ([scrollbackEnableCheck state]) {
        if ([[linesUnlimited cellAtRow:0 column:0] state])
            defaults->var17 = -1;
        else
            defaults->var17 = [lineLimitField intValue];
        defaults->var3 = (signed char)[scrollbackEnableCheck state];
        defaults->var1 = (signed char)[wrapCheck state];
        defaults->var0 = (signed char)[autoFocusCheck state];
    }
}

- (char)checkSettings
{
    int lines = [lineLimitField intValue];

    if (![[linesLimited cellAtRow:0 column:0] state])
        return 1;
    if (lines <= 0) {
        NSRunAlertPanel(@"Save Settings",
            @"You must save at least %d lines.", nil, nil, nil);
        return 0;
    }
    if (lines > 499)
        return 1;
    NSRunAlertPanel(@"Save Settings",
        @"That is certainly an odd number of lines to save.",
        nil, nil, nil, 500);
    [lineLimitField setIntValue:500];
    [lineLimitField selectText:self];
    return 0;
}

- (void)firstVisible:(id)sender
{
    [sender setUpButtons:31];
}

- (void)lastVisible:(id)sender
{
    (void)sender;
}

- (void)handleReturn:(id)sender
{
    [scrollbackEnableCheck setState:1];
    [[linesLimited cellAtRow:0 column:0] setState:1];
    [linesLimited display];
    [[linesUnlimited cellAtRow:0 column:0] setState:0];
    [linesUnlimited display];
    [okButton setDelegate:self];
    (void)sender;
}

- (void)limitLines:(id)sender
{
    id unlimitedCell = [linesUnlimited cellAtRow:0 column:0];
    id limitedCell = [linesLimited cellAtRow:0 column:0];

    [unlimitedCell setState:![limitedCell state]];
    [linesUnlimited display];
    (void)sender;
}

- (void)unlimitLines:(id)sender
{
    id limitedCell = [linesLimited cellAtRow:0 column:0];
    id unlimitedCell = [linesUnlimited cellAtRow:0 column:0];

    [limitedCell setState:![unlimitedCell state]];
    [linesLimited display];
    (void)sender;
}

@end
