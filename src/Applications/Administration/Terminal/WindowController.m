#import "WindowController.h"

#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSFontPanel.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSForm.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/obsoleteNSCStringText.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>

#include <stdio.h>
#include <math.h>
#include <stdlib.h>

#include <string.h>

extern id _theDefaultsObject;

@interface NSObject (WindowControllerPreferencesCallbacks)
- (void)setUpButtons:(int)count;
@end

@interface WindowController (TerminalFontDisplay)
- (void)displayFont:(const char *)name inSize:(float)size;
- (BOOL)checkSettings;
@end

@implementation WindowController

- (id)receiveFontFromTrap:(id)font
{
    NSFont *screenFont;
    NSString *fontName;

    screenFont = [(NSFont *)font screenFont];
    fontName = [screenFont fontName];
    [self displayFont:[fontName cString] inSize:[(NSFont *)font pointSize]];
    return self;
}

- (void)setFontRequest:(id)sender
{
    NSColor *fontFieldColor;
    NSWindow *window;
    NSFontManager *fontManager;
    NSFontPanel *fontPanel;

    (void)sender;
    fontFieldColor = [NSColor colorWithCalibratedWhite:
        (NSLightGray + NSWhite) / 2.0f alpha:1.0f];
    [(NSTextField *)fontField setTextColor:fontFieldColor];
    [(NSTextField *)fontField selectText:nil];

    window = [(NSView *)fontTrap window];
    [window setInitialFirstResponder:fontTrap];
    fontManager = [NSFontManager sharedFontManager];
    fontPanel = [fontManager fontPanel:YES];
    [fontPanel makeKeyAndOrderFront:self];
}

- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults
{
    [self displayRows:defaults->var7 cols:defaults->var8
        exitAction:defaults->var18
        font:[(NSString *)defaults->var11 cString]
        size:defaults->var12];
}

- (void)setStruct:(TerminalEmulationDefaults *)defaults
{
    NSFont *font;
    NSString *fontName;
    NSZone *zone;

    if (![self checkSettings])
        return;

    defaults->var7 = (unsigned short)[[sizeForm cellAtIndex:1] intValue];
    defaults->var8 = (unsigned short)[[sizeForm cellAtIndex:0] intValue];
    defaults->var18 = [(NSMatrix *)shellExitMatrix selectedRow];
    font = [(NSTextField *)fontField font];
    defaults->var12 = [font pointSize];

    [(NSString *)defaults->var11 release];
    zone = NSZoneFromPointer(defaults);
    fontName = [font fontName];
    defaults->var11 = [[NSString allocWithZone:zone] initWithString:fontName];
    if (defaults->var11 == nil)
        NSRunAlertPanel(@"WindowController.m", @"Can't malloc", nil, nil, nil);
}

- (BOOL)checkSettings
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSRect visibleFrame;
    NSFont *font;
    NSString *title;
    NSString *message;
    int rows;
    int columns;
    float cellWidth;
    float ascender;
    float descender;
    float lineHeight;
    int maximum;

    rows = [[sizeForm cellAtIndex:1] intValue];
    columns = [[sizeForm cellAtIndex:0] intValue];
    if (columns <= 4) {
        title = [bundle localizedStringForKey:@"Window Too Small"
            value:@"" table:nil];
        message = [bundle localizedStringForKey:
            @"Windows must have at least %d columns and %d rows."
            value:@"" table:nil];
        NSRunAlertPanel(title, message, nil, nil, nil, 5, 5);
        [[sizeForm cellAtIndex:0] setIntValue:5];
        [sizeForm selectTextAtIndex:0];
        return NO;
    }
    if (rows <= 4) {
        title = [bundle localizedStringForKey:@"Window Too Small"
            value:@"" table:nil];
        message = [bundle localizedStringForKey:
            @"Windows must have at least %d columns and %d rows."
            value:@"" table:nil];
        NSRunAlertPanel(title, message, nil, nil, nil, 5, 5);
        [[sizeForm cellAtIndex:1] setIntValue:5];
        [sizeForm selectTextAtIndex:1];
        return NO;
    }

    visibleFrame = [[NSScreen mainScreen] visibleFrame];
    font = [(NSTextField *)fontField font];
    cellWidth = [font widthOfString:@"X"];
    if (cellWidth * columns > visibleFrame.size.width) {
        title = [bundle localizedStringForKey:@"Window Too Large"
            value:@"" table:nil];
        message = [bundle localizedStringForKey:
            @"The values you have entered would  cause the window not to fit on the screen.  Reduce the font size or dimensions."
            value:@"" table:nil];
        NSRunAlertPanel(title, message, nil, nil, nil);
        maximum = (int)(visibleFrame.size.width / cellWidth);
        [[sizeForm cellAtIndex:0] setIntValue:maximum];
        [sizeForm selectTextAtIndex:0];
        return NO;
    }

    NSTextFontInfo(font, &ascender, &descender, &lineHeight);
    lineHeight = (float)floor(descender / 2.0f - ascender);
    if (lineHeight * rows > visibleFrame.size.height) {
        title = [bundle localizedStringForKey:@"Window Too Large"
            value:@"" table:nil];
        message = [bundle localizedStringForKey:
            @"The values you have entered would  cause the window not to fit on the screen.  Reduce the font size or dimensions."
            value:@"" table:nil];
        NSRunAlertPanel(title, message, nil, nil, nil);
        maximum = (int)(visibleFrame.size.height / lineHeight);
        [[sizeForm cellAtIndex:1] setIntValue:maximum];
        [sizeForm selectTextAtIndex:1];
        return NO;
    }

    if (columns > 255) {
        title = [bundle localizedStringForKey:@"Too Many Columns"
            value:@"" table:nil];
        message = [bundle localizedStringForKey:
            @"There can be at most %d columns."
            value:@"" table:nil];
        NSRunAlertPanel(title, message, nil, nil, nil, 255);
        [[sizeForm cellAtIndex:0] setIntValue:255];
        [sizeForm selectTextAtIndex:0];
        return NO;
    }
    if (rows > 255) {
        title = [bundle localizedStringForKey:@"Too Many Rows"
            value:@"" table:nil];
        message = [bundle localizedStringForKey:
            @"There can be at most %d rows."
            value:@"" table:nil];
        NSRunAlertPanel(title, message, nil, nil, nil, 255);
        [[sizeForm cellAtIndex:1] setIntValue:255];
        [sizeForm selectTextAtIndex:1];
        return NO;
    }
    return YES;
}

- (void)showDefault:(char)show
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    NSString *fontName;
    id fontSize;

    [defaults synchronize];
    fontName = [defaults stringForKey:@"NSFixedPitchFont"];
    fontSize = [defaults objectForKey:@"NSFixedPitchFontSize"];
    [self setRows:[defaults integerForKey:@"Rows"]
        cols:[defaults integerForKey:@"Columns"]
        exitAction:[defaults integerForKey:@"ShellExitAction"]
        font:[fontName cString]
        size:[fontSize floatValue]
        lock:show];
}

- (void)suggest
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    NSDictionary *globalDefaults;
    NSString *fontName;
    id fontSizeObject;
    float fontSize;

    globalDefaults = [defaults persistentDomainForName:NSGlobalDomain];
    fontName = [globalDefaults objectForKey:@"NSFixedPitchFont"];
    fontSizeObject = [globalDefaults objectForKey:@"NSFixedPitchFontSize"];
    fontSize = [fontSizeObject floatValue];

    if (fontName != nil && fontSizeObject != nil && fontSize != 0.0f &&
        [NSFont fontWithName:fontName size:fontSize] != nil) {
        [self setRows:24 cols:80 exitAction:0 font:[fontName cString]
            size:fontSize lock:NO];
    } else {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *fallbackFont = [bundle localizedStringForKey:@"Ohlfs"
            value:@"" table:nil];
        NSString *fallbackSize = [bundle localizedStringForKey:@"10.0"
            value:@"" table:nil];

        [self setRows:24 cols:80 exitAction:0
            font:[fallbackFont cString] size:(float)atof([fallbackSize cString])
            lock:NO];
    }
}


- (id)fontTrapDidResignFirstResponder
{
    NSFont *font;
    NSString *fontName;

    font = [[NSFontManager sharedFontManager] selectedFont];
    fontName = [font fontName];
    [(NSTextField *)fontField setStringValue:fontName];
    [(NSTextField *)fontField selectText:fontName];
    return self;
}

- (void)firstVisible:(id)sender
{
    [sender setUpButtons:31];
    [(NSForm *)sizeForm selectTextAtIndex:0];
}

- (void)lastVisible:(id)sender
{
    [[(NSTextField *)fontField window] makeFirstResponder:nil];
}

- (void)displayRows:(int)rows cols:(int)columns exitAction:(int)exitAction font:(const char *)fontName size:(float)fontSize
{
    int selectedExitAction;

    [[(NSForm *)sizeForm cellAtIndex:1] setIntValue:rows];
    [[(NSForm *)sizeForm cellAtIndex:0] setIntValue:columns];
    [sizeForm display];

    selectedExitAction = exitAction;
    if (selectedExitAction > 2)
        selectedExitAction = 2;
    if (selectedExitAction < 0)
        selectedExitAction = 0;
    [(NSMatrix *)shellExitMatrix selectCellWithTag:selectedExitAction];
    [shellExitMatrix display];
    [self displayFont:fontName inSize:fontSize];
}

- (void)displayFont:(const char *)name inSize:(float)size
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *fontName;
    NSString *sizeString;
    NSString *format;
    NSFont *font;
    char label[256];
    float displaySize;

    fontName = [NSString stringWithCString:name];
    font = [NSFont fontWithName:fontName size:size];
    displaySize = size;
    if (font == nil) {
        fontName = [bundle localizedStringForKey:@"Ohlfs" value:@"" table:nil];
        sizeString = [bundle localizedStringForKey:@"10.0" value:@"" table:nil];
        displaySize = (float)atof([sizeString cString]);
        font = [NSFont fontWithName:fontName size:displaySize];
    }

    [(NSTextField *)fontField setFont:font];
    format = [bundle localizedStringForKey:@"%s %.1f pt."
        value:@"" table:nil];
    sprintf(label, [format cString], [fontName cString], displaySize);
    [(NSTextField *)fontField setStringValue:[NSString stringWithCString:label]];
    [(NSTextField *)fontField selectText:nil];
}

- (void)setRows:(int)rows cols:(int)columns exitAction:(int)exitAction font:(const char *)fontName size:(float)fontSize lock:(BOOL)lock
{
    if (lock) {
        NSZone *zone;
        size_t fontLength;

        if (revertFont != NULL)
            NSZoneFree([self zone], revertFont);
        zone = [self zone];
        fontLength = strlen(fontName);
        revertFont = NSZoneMalloc(zone, fontLength + 1);
        if (revertFont == NULL) {
            NSRunAlertPanel(@"WindowController.m", @"Can't malloc",
                nil, nil, nil);
        }
        strcpy(revertFont, fontName);
        revertFontSize = fontSize;
        revertShellExit = exitAction;
        revertRows = rows;
        revertColumns = columns;
    }
    [self displayRows:rows cols:columns exitAction:exitAction font:fontName size:fontSize];
}

- (void)revert
{
    [self displayRows:revertRows cols:revertColumns exitAction:revertShellExit font:revertFont size:revertFontSize];
}

- (id)setDefault
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    NSFont *font;

    if ([self checkSettings]) {
        [defaults setObject:[[(NSMatrix *)shellExitMatrix selectedCell] stringValue]
            forKey:@"ShellExitAction"];
        [defaults setInteger:[[(NSForm *)sizeForm cellAtIndex:1] intValue]
            forKey:@"Rows"];
        [defaults setInteger:[[(NSForm *)sizeForm cellAtIndex:0] intValue]
            forKey:@"Columns"];
        font = [(NSTextField *)fontField font];
        [defaults setObject:[font fontName] forKey:@"NSFixedPitchFont"];
        [defaults setInteger:(int)[font pointSize]
            forKey:@"NSFixedPitchFontSize"];
    }
    return self;
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    NSWindow *window;

    window = [notification object];
    if ([window firstResponder] == fontTrap)
        [window makeFirstResponder:nil];
}

@end
