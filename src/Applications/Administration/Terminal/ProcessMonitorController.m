#import "ProcessMonitorController.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

#import <AppKit/NSGraphics.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableView.h>

#import "DirtMonitor.h"
#import "TerminalApp.h"

extern id _theDefaultsObject;

@interface NSObject (ProcessMonitorControllerButtons)
- (void)setUpButtons:(int)count;
@end

@implementation ProcessMonitorController

- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults
{
    (void)defaults;
}

- (void)lastVisible:(id)sender
{
    (void)sender;
}

- (void)revert
{
    [NSException raise:NSInvalidArgumentException
        format:@"*** Method not implemented: %s", sel_getName(_cmd)];
}

- (id)setDefault
{
    [NSException raise:NSInvalidArgumentException
        format:@"*** Method not implemented: %s", sel_getName(_cmd)];
    return self;
}

- (void)suggest
{
    [NSException raise:NSInvalidArgumentException
        format:@"*** Method not implemented: %s", sel_getName(_cmd)];
}

- (void)setStruct:(TerminalEmulationDefaults *)defaults
{
    (void)defaults;
    [NSException raise:NSInvalidArgumentException
        format:@"*** Method not implemented: %s", sel_getName(_cmd)];
}

- (void)writeCommands
{
    NSString *commands = [cleanCommands componentsJoinedByString:@";"];
    [(NSUserDefaults *)_theDefaultsObject setObject:commands
        forKey:@"CleanCommands"];
    [self promulgateSettings];
}

- (void)promulgateSettings
{
    TerminalApp *application = (TerminalApp *)NSApp;
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    DirtMonitor *monitor = (DirtMonitor *)[application dirtMonitor];

    [monitor setShellsClean:[defaults boolForKey:@"ShellsClean"]
        runningBackgroundClean:[defaults boolForKey:@"RunningBackgroundClean"]
        fastAudits:[defaults boolForKey:@"FastAudits"]
        cleanCommands:[application cleanCommands]];
    [defaults synchronize];
}

- (void)enablementChanged:(id)sender
{
    (void)sender;
    [(NSUserDefaults *)_theDefaultsObject setBool:[monitorCheck state]
        forKey:@"MonitorProcs"];
    [self promulgateSettings];
}

- (void)runningBackgroundChanged:(id)sender
{
    (void)sender;
    [(NSUserDefaults *)_theDefaultsObject setBool:[runningCleanCheck state]
        forKey:@"RunningBackgroundClean"];
    [self promulgateSettings];
}

- (void)showDefault:(char)useDefault
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    TerminalApp *application = (TerminalApp *)NSApp;

    (void)useDefault;
    [self displayMonitor:[defaults boolForKey:@"MonitorProcs"]
        shellsClean:[defaults boolForKey:@"ShellsClean"]
        runningBkgndClean:[defaults boolForKey:@"RunningBackgroundClean"]
        fastAudits:[defaults boolForKey:@"FastAudits"]
        cleanCommands:[application cleanCommands]];
}

- (void)displayMonitor:(char)monitor shellsClean:(char)shellsClean
    runningBkgndClean:(char)runningBkgndClean fastAudits:(char)fastAudits
    cleanCommands:(const char **)commands
{
    unsigned int count = 0;
    unsigned int index;

    [runningCleanCheck setState:runningBkgndClean];
    [monitorCheck setState:monitor];
    [checkMatrix selectCellAtRow:fastAudits column:0];

    if (commands != 0) {
        while (commands[count] != 0)
            count++;
        if (cleanCommands == nil)
            cleanCommands = [[NSMutableArray alloc] initWithCapacity:count];
        else
            [cleanCommands removeAllObjects];

        for (index = 0; index < count; index++)
            [cleanCommands addObject:[NSString stringWithCString:commands[index]]];
    }

    [cleanTableView reloadData];
    [cleanTableView noteNumberOfRowsChanged];
    [removeButton setEnabled:NO];
}

- (void)firstVisible:(id)sender
{
    [sender setUpButtons:24];
    [self showDefault:1];
}

- (void)add:(id)sender
{
    NSString *command = [newCleanField stringValue];
    NSCharacterSet *lineBreaks =
        [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
    NSCharacterSet *forbidden =
        [NSCharacterSet characterSetWithCharactersInString:@";"];
    NSRange invalidRange;

    (void)sender;
    if (command == nil ||
        [command rangeOfCharacterFromSet:lineBreaks].location != NSNotFound) {
        NSBeep();
        return;
    }

    invalidRange = [command rangeOfCharacterFromSet:forbidden];
    if (invalidRange.location != NSNotFound) {
        NSRunAlertPanel(NSLocalizedString(@"Strange Command", @""),
            NSLocalizedString(@"Commands may not contain the characters '%s'.", @""),
            nil, nil, nil, ";");
        [newCleanField setDelegate:self];
        return;
    }

    if ([cleanCommands count] > 18) {
        NSRunAlertPanel(NSLocalizedString(@"Too Many Commands", @""),
            NSLocalizedString(
                @"There's only room for %d commands in the clean commands list.", @""),
            nil, nil, nil, 19);
        [newCleanField setDelegate:self];
        return;
    }

    if ([cleanCommands indexOfObject:command] != NSNotFound) {
        NSRunAlertPanel(NSLocalizedString(@"Duplicate Command", @""),
            NSLocalizedString(@"That command is already in the list.", @""),
            nil, nil, nil);
        [newCleanField setDelegate:self];
        return;
    }

    [cleanCommands addObject:command];
    [cleanTableView reloadData];
    [cleanTableView scrollRowToVisible:(int)[cleanCommands count] - 1];
    [cleanScrollView reflectScrolledClipView:[cleanScrollView contentView]];
    [newCleanField setStringValue:@""];
    [newCleanField setDelegate:self];
    [addButton setEnabled:NO];
    [self writeCommands];
}

- (void)remove:(id)sender
{
    unsigned int row;
    BOOL removed = NO;

    (void)sender;
    for (row = [cleanCommands count]; row > 0; row--) {
        unsigned int index = row - 1;
        if ([cleanTableView isRowSelected:(int)index]) {
            [cleanCommands removeObjectAtIndex:index];
            removed = YES;
        }
    }

    if (removed) {
        [cleanTableView reloadData];
        [self promulgateSettings];
    } else {
        NSBeep();
    }
}

- (void)tableViewSelectionDidChange:(id)notification
{
    NSTableView *tableView = (NSTableView *)[notification object];

    if (tableView == cleanTableView)
        [removeButton setEnabled:([tableView numberOfSelectedRows] > 0)];
}

- (void)controlTextDidChange:(id)notification
{
    id field = [[notification userInfo] objectForKey:@"NSFieldEditor"];
    NSString *command = [field string];
    NSCharacterSet *lineBreaks =
        [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
    BOOL enabled = NO;

    if (command != nil && [command length] > 0 &&
        [command rangeOfCharacterFromSet:lineBreaks].location == NSNotFound &&
        [cleanCommands indexOfObject:command] == NSNotFound)
        enabled = YES;

    [addButton setEnabled:enabled];
}

- (int)numberOfRowsInTableView:(id)tableView
{
    if (tableView != cleanTableView)
        return 0;
    return [cleanCommands count];
}

- (id)tableView:(id)tableView objectValueForTableColumn:(id)column row:(int)row
{
    (void)column;
    if (tableView == cleanTableView && row >= 0 &&
        (unsigned int)row < [cleanCommands count])
        return [cleanCommands objectAtIndex:(unsigned int)row];
    return @"";
}

- (void)tableView:(id)tableView setObjectValue:(id)value
    forTableColumn:(id)column row:(int)row
{
    (void)column;
    if (tableView == cleanTableView && row >= 0 &&
        (unsigned int)row < [cleanCommands count])
        [cleanCommands replaceObjectAtIndex:(unsigned int)row withObject:value];
}

@end
