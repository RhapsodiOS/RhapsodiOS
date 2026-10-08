#import "FindPanel.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSForm.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSGraphics.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSString.h>
#import <mach/mach.h>

#import "FieldView.h"
#import "FindCharacters.h"

extern vm_size_t vm_page_size;

@implementation FindPanel

+ (id)alloc
{
    NSZone *zone;

    zone = NSCreateZone(vm_page_size, vm_page_size, YES);
    if (zone == nil) {
        NSBeep();
        return nil;
    }

    NSSetZoneName(zone, @"FindPanel");
    return [super allocWithZone:zone];
}

- (id)findPanel
{
    if (findPanel == nil) {
        NSBundle *bundle;
        NSString *nibPath;
        NSDictionary *externalNameTable;

        bundle = [NSBundle bundleForClass:[self class]];
        nibPath = [bundle pathForResource:@"Find" ofType:@"nib"];
        externalNameTable = [NSDictionary dictionaryWithObjectsAndKeys:
            self, @"NSOwner", nil];
        [NSBundle loadNibFile:nibPath
            externalNameTable:externalNameTable
            withZone:[self zone]];
    }

    return findPanel;
}

- (char)importFindText:(id)findField
{
    NSPasteboard *pasteboard;
    NSArray *types;
    NSEnumerator *enumerator;
    NSString *type;
    NSString *findText;
    id cell;

    if (findField == nil)
        return 0;

    pasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
    if (pasteboard == nil)
        return 0;

    types = [pasteboard types];
    enumerator = [types objectEnumerator];
    while ((type = [enumerator nextObject]) != nil) {
        if ([type isEqualToString:NSStringPboardType]) {
            findText = [pasteboard stringForType:NSStringPboardType];
            if (findText == nil || [findText length] == 0)
                return 0;

            cell = [findField cellAtIndex:0];
            [cell setStringValue:findText];
            return 1;
        }
    }

    return 0;
}

- (char)exportFindText:(id)findField
{
    id cell;
    NSString *findText;
    NSPasteboard *pasteboard;
    NSArray *types;

    if (findField == nil)
        return 0;

    cell = [findField cellAtIndex:0];
    findText = [cell stringValue];
    if (findText == nil || [findText length] == 0)
        return 0;

    pasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
    if (pasteboard == nil)
        return 0;

    types = [NSArray arrayWithObject:NSStringPboardType];
    [pasteboard declareTypes:types owner:nil];
    return [pasteboard setString:findText forType:NSStringPboardType] ? 1 : 0;
}

- (void)findPanel:(id)sender
{
    id panel;
    id contentView;
    id findField;
    id statusField;

    (void)sender;
    panel = [self findPanel];
    contentView = [panel contentView];
    findField = [contentView viewWithTag:100];
    [self importFindText:findField];
    [findField selectTextAtIndex:0];

    contentView = [panel contentView];
    statusField = [contentView viewWithTag:101];
    [statusField setStringValue:@"Not Found"];
    [panel makeKeyAndOrderFront:self];
}

- (void)enterSelection:(id)sender
{
    NSWindow *sourceWindow;
    id firstResponder;
    FieldView *fieldView;
    const char *selection;
    NSWindow *panel;
    id findField;
    id statusField;

    sourceWindow = [NSApp windowWithWindowNumber:(int)sender];
    firstResponder = [sourceWindow firstResponder];
    [self findPanel];

    if (![firstResponder isKindOfClass:[FieldView class]])
        return;

    fieldView = (FieldView *)firstResponder;
    selection = [fieldView selStr];
    if (selection == NULL)
        return;

    panel = [self findPanel];
    findField = [panel viewWithTag:100];
    [[findField cellAtIndex:0] setStringValue:
        [NSString stringWithCString:selection]];
    [findField selectTextAtIndex:0];

    panel = [self findPanel];
    statusField = [panel viewWithTag:101];
    [statusField setStringValue:@"Not Found"];
    [self exportFindText:findField];
}

- (void)doFind:(id)sender findBackwards:(char)backwards
{
    id panel;
    id contentView;
    id findField;
    id findCell;
    id statusField;
    id ignoreCaseButton;
    NSString *query;
    const char *characters;
    NSWindow *mainWindow;
    id firstResponder;
    FieldView *fieldView;
    char found;

    panel = [self findPanel];
    contentView = [panel contentView];
    findField = [contentView viewWithTag:100];
    statusField = [contentView viewWithTag:101];

    if (![panel isVisible])
        [self importFindText:findField];

    ignoreCaseButton = [contentView viewWithTag:102];
    terminalFindIgnoreCase = (unsigned char)[ignoreCaseButton state];
    [statusField setStringValue:@""];

    findCell = [findField cellAtIndex:0];
    query = [findCell stringValue];
    characters = [query cString];
    mainWindow = [NSApp mainWindow];
    firstResponder = [mainWindow firstResponder];
    found = 0;
    if ([firstResponder isKindOfClass:[FieldView class]]) {
        fieldView = (FieldView *)firstResponder;
        found = backwards ? [fieldView bfind:characters]
                          : [fieldView find:characters];
    }

    if (found) {
        if (sender == findField)
            [panel makeKeyAndOrderFront:self];
    } else {
        NSString *message;

        NSBeep();
        message = [[NSBundle mainBundle]
            localizedStringForKey:@"Not Found" value:@"" table:nil];
        [statusField setStringValue:message];
    }

    [self exportFindText:findField];
    [findField selectTextAtIndex:0];
}

- (void)findNext:(id)sender
{
    [self doFind:sender findBackwards:0];
}

- (void)findPrevious:(id)sender
{
    [self doFind:sender findBackwards:1];
}

@end
