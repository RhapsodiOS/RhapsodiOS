#import "TitleBarController.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSForm.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSTextField.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSZone.h>

#include <stdlib.h>
#include <string.h>

#import "Shell.h"
#import "TerminalApp.h"
#import "TerminalDefaults.h"
#import "TString.h"
#import "WindowTitle.h"

extern id _theDefaultsObject;

@interface NSObject (TitleBarControllerPreferencesCallbacks)
- (void)setUpButtons:(int)flags;
@end

static const char *titleFormCString(id form)
{
    id value = [[(NSForm *)form cellAtIndex:0] stringValue];

    return [value cString];
}

@implementation TitleBarController

- (id)init
{
    revertCustomTitle = NULL;
    return [super init];
}

- (void)awakeFromNib
{
    maxFakeTitleFrame = [fakeTitle frame];
}

- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults
{
    const char *custom = [[(TString *)defaults->var16 stringValue] cString];

    [self setBits:defaults->var15 custom:custom lock:1];
}

- (void)showDefault:(char)show
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    NSString *custom;
    int bits;

    [defaults synchronize];
    bits = [defaults integerForKey:@"TitleBits"];
    custom = [defaults stringForKey:@"CustomTitle"];
    [self setBits:bits custom:[custom cString] lock:show];
}

- (void)suggest
{
    [self setBits:7 custom:"" lock:0];
}

- (void)setBits:(int)bits custom:(const char *)custom lock:(char)lock
{
    if (lock) {
        size_t length;

        revertBits = bits;
        if (revertCustomTitle != NULL)
            free(revertCustomTitle);
        if (custom != NULL) {
            length = strlen(custom);
            revertCustomTitle = NSZoneMalloc([self zone], length + 1);
            strcpy(revertCustomTitle, custom);
        }
    }
    [self displayBits:bits custom:custom];
    [(NSForm *)titleForm selectTextAtIndex:0];
}

- (void)displayBits:(int)bits custom:(const char *)custom
{
    NSMatrix *matrix = (NSMatrix *)elementMatrix;
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *visibleCustom;
    NSString *fileName;
    char *titleBytes;
    NSString *title;
    NSRect frame;
    NSRect clippedFrame;
    NSFont *font;
    float delta;
    id formCell;
    int index;

    for (index = 0; index <= 4; index++) {
        id cell = [matrix cellWithTag:1 << index];
        [cell setState:(bits >> index) & 1];
    }
    [matrix display];

    if (custom != NULL && custom[0] != '\0')
        visibleCustom = [NSString stringWithCString:custom];
    else
        visibleCustom = [bundle localizedStringForKey:@"Custom Title"
            value:@"Custom Title" table:nil];
    fileName = [bundle localizedStringForKey:@"~/TermSetup.term"
        value:@"Custom Title" table:nil];
    titleBytes = winTitle([(TerminalApp *)NSApp shell], "/dev/ttyp1",
        80, 24, bits, 0, [visibleCustom cString], [fileName cString]);
    title = [NSString stringWithCString:titleBytes];
    frame = [fakeTitle frame];
    font = [fakeTitle font];
    delta = [font widthOfString:title] + 10.0f - frame.size.width;
    frame.origin.x -= delta * 0.5f;
    frame.size.width += delta;
    clippedFrame = NSIntersectionRect(frame, maxFakeTitleFrame);
    [fakeTitle setFrame:clippedFrame];
    [(NSTextField *)fakeTitle setStringValue:title];
    [[fakeTitle superview] setNeedsDisplay:YES];

    formCell = [(NSForm *)titleForm cellAtIndex:0];
    if (custom == NULL)
        [formCell setStringValue:@"Custom Title"];
    else
        [formCell setStringValue:[NSString stringWithCString:custom]];
}

- (void)revert
{
    [self setBits:revertBits custom:revertCustomTitle lock:0];
}

- (id)setDefault
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    const char *custom;
    NSString *customString;

    if ([self checkSettings]) {
        [defaults setInteger:[self titleBits] forKey:@"TitleBits"];
        custom = titleFormCString(titleForm);
        if (custom != NULL && custom[0] != '\0')
            customString = [NSString stringWithCString:custom];
        else
            customString = @"Custom Title";
        [defaults setObject:customString forKey:@"CustomTitle"];
    }
    return self;
}

- (int)titleBits
{
    NSMatrix *matrix = (NSMatrix *)elementMatrix;
    int bits = 0;
    int index;

    for (index = 0; index <= 4; index++) {
        id cell = [matrix cellWithTag:1 << index];
        if ([cell state] != 0)
            bits |= 1 << index;
    }
    return bits;
}

- (char)checkSettings
{
    id customCell = [(NSMatrix *)elementMatrix cellWithTag:8];
    const char *custom;
    NSString *title;
    NSString *message;

    if ([customCell state] == 0)
        return 1;
    custom = titleFormCString(titleForm);
    if (custom != NULL && custom[0] != '\0')
        return 1;

    title = [[NSBundle mainBundle] localizedStringForKey:@"Custom Title"
        value:@"Custom Title" table:nil];
    message = [[NSBundle mainBundle] localizedStringForKey:
        @"You've asked that a custom title be included in the title bar, but you haven't entered a title."
        value:@"You've asked that a custom title be included in the title bar, but you haven't entered a title."
        table:nil];
    NSRunAlertPanel(title, message, nil, nil, nil);
    return 0;
}

- (void)setStruct:(TerminalEmulationDefaults *)defaults
{
    NSString *custom;

    if (![self checkSettings])
        return;
    defaults->var15 = (unsigned char)[self titleBits];
    custom = [NSString stringWithCString:titleFormCString(titleForm)];
    [(TString *)defaults->var16 empty];
    [(TString *)defaults->var16 setStringValue:custom];
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

- (void)titleBitsChanged:(id)sender
{
    NSWindow *window;
    const char *custom;
    int bits;

    (void)sender;
    window = [(NSMatrix *)elementMatrix window];
    [window disableFlushWindow];
    bits = [self titleBits];
    custom = titleFormCString(titleForm);
    [self displayBits:bits custom:custom];
    [window enableFlushWindow];
    [[window contentView] setNeedsDisplay:YES];
}

- (void)textDidEndEditing:(id)sender
{
    const char *custom = titleFormCString(titleForm);
    BOOL hasCustom = custom != NULL && custom[0] != '\0';
    id customCell = [(NSMatrix *)elementMatrix cellWithTag:8];

    (void)sender;
    if ([customCell state] != hasCustom) {
        [customCell setState:hasCustom];
        [(NSMatrix *)elementMatrix selectCell:customCell];
    }
    [self titleBitsChanged:self];
}

@end
