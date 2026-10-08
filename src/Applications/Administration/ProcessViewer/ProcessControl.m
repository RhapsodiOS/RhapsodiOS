#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <signal.h>
#include <unistd.h>
#import "ProcessControl.h"
#ifdef PROCESSVIEWER_TEST
#import "tests/test_support.h"
#endif

#define PVLocalized(key) [[NSBundle mainBundle] localizedStringForKey:(key) value:(key) table:nil]

static NSString * const _TypePopUpDefaultKey = @"DefaultTypeTag";
static NSString * const _IntervalDefaultKey = @"RefreshInterval";
static NSString * const _SortIdentifierDefaultKey = @"SortColumn";
static NSString * const _SortAscendingDefaultKey = @"SortAscending";
static NSString * const PVProcessTableConfig = @"ProcessTableConfig";
static NSString * const PVProcessWindow = @"ProcessWindow";
static const double PVProcessViewerVersionNumber = 15.0;
static const double PVMinimumRefreshInterval = 0.0;
static NSString * const _AllowKillDefaultKey = @"DeleteProtectedProcesses";
static NSString * const administratorUserName = @"root";
static NSString * const MachineMightCrashProcesses[] = {
    @"init", @"mach_init", @"kern_loader", @"update", @"nmserver",
    @"portmap", @"nibindd", @"netinfod", @"lookupd", @"ppcd",
    @"loginwindow", @"Workspace", nil
};
static NSString * const LogoutProcesses[] = {
    @"WindowServer", @"Viewer", @"pbs", @"AKServer", nil
};

#ifdef PROCESSVIEWER_TEST
#define PVCurrentUserName() PVTestCurrentUserName()
#define PVRunAlertPanel(title, message, defaultButton, alternateButton, otherButton, argument1, argument2) PVTestRunAlertPanel(title, message, defaultButton, alternateButton, otherButton, argument1, argument2)
#define PVSendSignal(pid, signalNumber) PVTestSendSignal(pid, signalNumber)
#define PVSavePanel() ((NSSavePanel *)PVTestControllerSavePanel())
#define PVBeep() PVTestBeep()
#define PVShowSystemInfoPanel(options, command, sender) PVTestShowSystemInfoPanel(options, command, sender)
#define PVRegisterDefaults(defaults) PVTestRegisterDefaults(defaults)
#else
#define PVCurrentUserName() NSUserName()
#define PVRunAlertPanel(title, message, defaultButton, alternateButton, otherButton, argument1, argument2) NSRunAlertPanel(title, message, defaultButton, alternateButton, otherButton, argument1, argument2)
#define PVSendSignal(pid, signalNumber) kill(pid, signalNumber)
#define PVSavePanel() [NSSavePanel savePanel]
#define PVBeep() NSBeep()
#define PVShowSystemInfoPanel(options, command, sender) NSShowSystemInfoPanel(options, command, sender)
#define PVRegisterDefaults(defaults) [[NSUserDefaults standardUserDefaults] registerDefaults:defaults]
#endif

@implementation ProcessControl

- (id)init
{
    self = [super init];
    if (self != nil) {
        NSDictionary *defaults = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:-1], _TypePopUpDefaultKey,
            @"20.0", _IntervalDefaultKey,
            @"NO", _AllowKillDefaultKey, nil];
        PVRegisterDefaults(defaults);
        fieldNames = [[NSMutableArray alloc] init];
        filteredProcesses = [[NSMutableArray alloc] init];
        allProcesses = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [allColumns release];
    [fieldNames release];
    [filteredProcesses release];
    [allProcesses release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSArray *types;
    NSArray *columns;
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];
    NSWindow *window;
    NSString *savedTag;
    NSString *savedSortColumn;
    unsigned int index;

    savedTag = [userDefaults stringForKey:_TypePopUpDefaultKey];
    [printInfo setOrientation:NSLandscapeOrientation];
    [printInfo setLeftMargin:36.0];

    [typePopup removeAllItems];
    types = [ProcessType allProcessTypes];
    processTypes = types;
    for (index = 0; index < [types count]; ++index) {
        ProcessType *type = [types objectAtIndex:index];
        NSString *name = [type localizedName];
        NSMenuItem *item;

        [typePopup addItemWithTitle:name];
        item = [typePopup itemWithTitle:name];
        [item setRepresentedObject:type];
        if (savedTag != nil && [savedTag isEqualToString:[type name]]) {
            [typePopup selectItemWithTitle:name];
            [typePopup synchronizeTitleAndSelectedItem];
        }
    }

    columns = [processTable tableColumns];
    allColumns = [[NSArray arrayWithArray:columns] retain];
    [[sortOrderButton cell] setBordered:YES];
    [[sortOrderButton cell] setBezeled:NO];
    [[sortOrderButton cell] performSelector:@selector(_setBackgroundColor:)
                                 withObject:[NSColor headerColor]];
    [processTable setCornerView:sortOrderButton];
    [sortOrderButton setState:[userDefaults boolForKey:_SortAscendingDefaultKey] ? 1 : 0];

    window = [processTable window];
    [window setFrameUsingName:PVProcessWindow];
    [window setFrameAutosaveName:PVProcessWindow];
    [processTable setAutosaveName:PVProcessTableConfig];
    [processTable setAutosaveTableColumns:YES];
    [processTable sizeToFit];

    savedSortColumn = [userDefaults stringForKey:_SortIdentifierDefaultKey];
    if (savedSortColumn != nil) {
        int column = [processTable columnWithIdentifier:savedSortColumn];
        [processTable setHighlightedColumn:column];
    }

    [rateField setDoubleValue:[userDefaults floatForKey:_IntervalDefaultKey]];
    [self assignActions];
    [self getProcesses:savedSortColumn];
    [self updateRate];
    if ([inspector isVisible]) {
        [self showMoreInfoAboutSelection:nil];
        [moreInfoSwitch setState:1];
    }
    [window makeKeyAndOrderFront:nil];
}

- (void)assignActions
{
    NSEnumerator *enumerator = [[processTable tableColumns] objectEnumerator];
    NSTableColumn *column;
    [processTable setAutosaveTableColumns:YES];
    while ((column = [enumerator nextObject]) != nil) {
        [[column headerCell] setTarget:self];
        [[column headerCell] setAction:@selector(resort:)];
    }
}

- (BOOL)shouldShowProcess:(Process *)process
{
    id selectedType = [[typePopup selectedItem] representedObject];
    NSString *filter = [filterText stringValue];
    NSString *value;

    if (selectedType != nil && ![selectedType matchesProcess:process])
        return NO;
    value = [process objectForKey:@"NAME"];
    if ([filter length] == 0 || value == nil)
        return YES;
    return [value rangeOfString:filter
                       options:NSCaseInsensitiveSearch].location != NSNotFound;
}

- (void)setShowType:(id)sender
{
    NSMenuItem *item = [typePopup selectedItem];
    [[NSUserDefaults standardUserDefaults] setInteger:[item tag]
                                               forKey:_TypePopUpDefaultKey];
    [self updateForSortChange:NO filterChange:YES];
}

- (void)getProcesses:(id)sender
{
    NSArray *processes = [Process enumerateProcessesAndFetch:YES];
    [allProcesses setArray:(processes != nil ? processes : [NSArray array])];
    [self updateForSortChange:YES filterChange:YES];
    [self updateRate];
}

- (void)updateForSortChange:(BOOL)sortChange filterChange:(BOOL)filterChange
{
    NSMutableArray *selected = [NSMutableArray array];
    NSEnumerator *rows = [processTable selectedRowEnumerator];
    NSNumber *rowNumber;
    unsigned int index;
    id columnIdentifier = [[processTable highlightedColumnIdentifier] retain];
    BOOL ascending = [sortOrderButton state] != 0;
    ProcessSortContext sortContext;

    while ((rowNumber = [rows nextObject]) != nil) {
        int row = [rowNumber intValue];
        if (row >= 0 && row < (int)[filteredProcesses count])
            [selected addObject:[filteredProcesses objectAtIndex:row]];
    }

    if (filterChange) {
        [filteredProcesses removeAllObjects];
        for (index = 0; index < [allProcesses count]; ++index) {
            id process = [allProcesses objectAtIndex:index];
            if ([self shouldShowProcess:process])
                [filteredProcesses addObject:process];
        }
    }

    if (sortChange && columnIdentifier != nil &&
        [Process getSortContext:&sortContext forKey:columnIdentifier ascending:ascending]) {
        NSArray *sorted = [filteredProcesses sortedArrayUsingFunction:sortFunction
                                                               context:&sortContext];
        [filteredProcesses setArray:sorted];
    }

    [processTable reloadData];
    [processTable deselectAll:self];
    for (index = 0; index < [selected count]; ++index) {
        unsigned int row = [filteredProcesses indexOfObjectIdenticalTo:[selected objectAtIndex:index]];
        if (row != NSNotFound)
            [processTable selectRow:row byExtendingSelection:YES];
    }

    if ([filteredProcesses count] == [allProcesses count])
        [countField setStringValue:[NSString stringWithFormat:
            PVLocalized(@"%u processes."), (unsigned int)[allProcesses count]]];
    else if ([filteredProcesses count] == 0)
        [countField setStringValue:[NSString stringWithFormat:
            PVLocalized(@"No matching processes (%u total)."), (unsigned int)[allProcesses count]]];
    else
        [countField setStringValue:[NSString stringWithFormat:
            PVLocalized(@"%u of %u processes displayed."),
            (unsigned int)[filteredProcesses count], (unsigned int)[allProcesses count]]];
    [columnIdentifier release];
}

- (void)resort:(id)sender
{
    int columnIndex = [processTable selectedColumn];
    NSArray *columns = [processTable tableColumns];
    NSTableColumn *column;
    id identifier;
    if (columnIndex >= 0 && columnIndex < (int)[columns count]) {
        column = [columns objectAtIndex:columnIndex];
        identifier = [column identifier];
        [processTable setHighlightedColumn:columnIndex];
    } else {
        identifier = nil;
        [processTable setHighlightedColumn:-1];
    }
    if (identifier != nil)
        [[NSUserDefaults standardUserDefaults] setObject:identifier
                                                 forKey:_SortIdentifierDefaultKey];
    else
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:_SortIdentifierDefaultKey];
    [self updateForSortChange:YES filterChange:NO];
}

- (void)refilter:(id)sender
{
    [self updateForSortChange:NO filterChange:YES];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    [self refilter:self];
}

- (void)changeSortOrder:(id)sender
{
    BOOL ascending = [sender state] != 0;
    [[NSUserDefaults standardUserDefaults] setBool:ascending forKey:_SortAscendingDefaultKey];
    [self updateForSortChange:YES filterChange:NO];
}

- (void)updateRate
{
    double interval = [rateField doubleValue];
    if (timer != nil) {
        [timer invalidate];
        [timer release];
        timer = nil;
    }
    if (interval > PVMinimumRefreshInterval) {
        timer = [[NSTimer scheduledTimerWithTimeInterval:interval
                                                  target:self
                                                selector:@selector(getProcesses:)
                                                userInfo:nil
                                                 repeats:YES] retain];
    }
    [rateField setDoubleValue:interval];
}

- (void)resetRate:(id)sender
{
    float value = [sender floatValue];
    [[NSUserDefaults standardUserDefaults] setFloat:value forKey:_IntervalDefaultKey];
    [rateField setFloatValue:value];
    [self updateRate];
}

- (void)bumpRate:(id)sender
{
    NSNumberFormatter *formatter = (NSNumberFormatter *)[[rateField cell] formatter];
    double proposed = [rateField doubleValue] + [sender intValue];
    double maximum = [[formatter maximum] doubleValue];
    double minimum = [[formatter minimum] doubleValue];
    if (proposed > maximum || proposed < minimum) {
        PVBeep();
        return;
    }
    [[NSUserDefaults standardUserDefaults] setFloat:(float)proposed forKey:_IntervalDefaultKey];
    [rateField setDoubleValue:proposed];
    [self updateRate];
}

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (int)[filteredProcesses count];
}

- (id)tableView:(NSTableView *)tableView
 objectValueForTableColumn:(NSTableColumn *)column
            row:(int)rowIndex
{
    NSParameterAssert(rowIndex >= 0 && rowIndex < [filteredProcesses count]);
    return [[filteredProcesses objectAtIndex:rowIndex] objectForKey:[column identifier]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    int count = (int)[processTable numberOfSelectedRows];
    if (![inspector isVisible])
        return;
    if (count == 0)
        [inspector showInfoForNoSelection];
    else if (count > 1)
        [inspector showInfoForMultipleSelection];
    else {
        int row = [processTable selectedRow];
        [inspector showInfoForProcess:[filteredProcesses objectAtIndex:row]];
    }
}

- (void)showMoreInfoAboutSelection:(id)sender
{
}

- (void)toggleMoreInfo:(id)sender
{
    int state = [sender state];
    if (state == 1) {
        [inspector setVisible:YES];
        [self showMoreInfoAboutSelection:nil];
    } else if (state == 0) {
        [inspector setVisible:NO];
    }
}

- (void)hideColumn:(id)sender
{
    NSEnumerator *selectedColumns = [processTable selectedColumnEnumerator];
    NSArray *columns = [processTable tableColumns];
    NSNumber *columnNumber;
    while ((columnNumber = [selectedColumns nextObject]) != nil) {
        NSTableColumn *column = [columns objectAtIndex:[columnNumber intValue]];
        [processTable removeTableColumn:column];
    }
    [processTable setNeedsDisplay:YES];
}

- (void)showAllColumns:(id)sender
{
    NSEnumerator *enumerator = [[processTable tableColumns] objectEnumerator];
    NSTableColumn *column;
    while ((column = [enumerator nextObject]) != nil)
        [processTable removeTableColumn:column];

    enumerator = [allColumns objectEnumerator];
    while ((column = [enumerator nextObject]) != nil) {
        [processTable addTableColumn:column];
    }
    [processTable setNeedsDisplay:YES];
}

- (void)exportProcessList:(id)sender
{
    NSSavePanel *panel = PVSavePanel();
    NSMutableArray *representations = [NSMutableArray array];
    NSEnumerator *enumerator;
    id process;
    int response;

    enumerator = [filteredProcesses objectEnumerator];
    while ((process = [enumerator nextObject]) != nil)
        [representations addObject:[process dictionaryRepresentation]];
    [panel setRequiredFileType:@"plist"];
    response = [panel runModalForDirectory:NSHomeDirectory()
                                      file:PVLocalized(@"Exported Processes.plist")];
    if (response == NSOKButton) {
        if (![representations writeToFile:[panel filename] atomically:YES])
            PVBeep();
    }
}

- (void)print:(id)sender
{
    NSView *printView = [[processTable superview] superview];
    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:printView];
    [operation runOperation];
}

- (void)killProcesses:(id)sender
{
    NSEnumerator *rows = [processTable selectedRowEnumerator];
    NSNumber *rowNumber;
    while ((rowNumber = [rows nextObject]) != nil) {
        int row = [rowNumber intValue];
        [self killProcessWithConfirmation:[filteredProcesses objectAtIndex:row]];
    }
    [self getProcesses:sender];
}

- (void)killProcessWithConfirmation:(Process *)process
{
    NSString *owner = [process objectForKey:@"USER"];
    NSString *name = [process objectForKey:@"NAME"];
    unsigned int pid = [process processId];
    NSString *user = PVCurrentUserName();
    BOOL deleteProtected = [[NSUserDefaults standardUserDefaults]
        boolForKey:_AllowKillDefaultKey];
    NSString *goAheadButton = deleteProtected ? PVLocalized(@"Go ahead") : nil;
    unsigned int index;
    int response;

    if ([user isEqualToString:administratorUserName]) {
        for (index = 0; index < 12; ++index) {
            if ([name isEqualToString:MachineMightCrashProcesses[index]])
                break;
        }
        if (index < 12) {
            (void)PVRunAlertPanel(PVLocalized(@"WARNING"),
                PVLocalized(@"Quitting '%@' will log you out."),
                PVLocalized(@"Cancel"), goAheadButton, nil, name, nil);
        }
    } else if ([user isEqualToString:owner]) {
        for (index = 0; index < 4; ++index) {
            if ([name isEqualToString:LogoutProcesses[index]])
                break;
        }
        if (index < 4) {
            response = PVRunAlertPanel(PVLocalized(@"WARNING"),
                PVLocalized(@"Quitting '%@' might disrupt your computer."),
                PVLocalized(@"Cancel"), goAheadButton, nil, name, nil);
            if (response != 0)
                return;
        }
    } else {
        (void)PVRunAlertPanel(PVLocalized(@"Quit Process"),
            PVLocalized(@"You cannot quit the process '%@' because it's owned by %@."),
            PVLocalized(@"Cancel"), nil, nil, name, owner);
        return;
    }

    response = PVRunAlertPanel(PVLocalized(@"Quit Process"),
        PVLocalized(deleteProtected
            ? @"Do you really want to quit '%@'? Any unsaved work will be lost."
            : @"Do you really want to quit '%@'?"),
        PVLocalized(@"Quit"), PVLocalized(@"Force Quit"),
        PVLocalized(@"Cancel"), name, nil);
    if (response != -1) {
        int signalNumber = response == 1 ? SIGINT : SIGKILL;
        (void)PVSendSignal((pid_t)pid, signalNumber);
    }
}

- (void)showAboutPanel:(id)sender
{
    if (optionsDictionary == nil)
        optionsDictionary = [[NSDictionary alloc] initWithObjectsAndKeys:
            @"1998", @"CopyrightStartYear",
            [NSString stringWithFormat:@"%3.1f", PVProcessViewerVersionNumber],
            @"Version", nil];
    PVShowSystemInfoPanel(optionsDictionary, _cmd, sender);
}

- (BOOL)validateMenuItem:(id)item
{
    SEL action = [item action];
    if (action == @selector(killProcesses:))
        return [processTable numberOfSelectedRows] > 0;
    if (action == @selector(showMoreInfoAboutSelection:))
        return [processTable selectedRow] >= 0;
    return YES;
}

- (void)windowDidResize:(NSNotification *)notification
{
    [processTable sizeLastColumnToFit];
}

- (BOOL)windowShouldClose:(id)sender
{
    [NSApp terminate:sender];
    return NO;
}

@end

#ifndef PROCESSVIEWER_TEST
int main(int argc, char **argv)
{
    return NSApplicationMain(argc, (const char **)argv);
}
#endif
