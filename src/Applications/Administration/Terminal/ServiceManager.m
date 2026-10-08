#import "ServiceManager.h"

#import <AppKit/NSMatrix.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSText.h>
#import <AppKit/NSMatrix.h>
#import <Foundation/NSString.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSEnumerator.h>
#import <AppKit/NSText.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSUserDefaults.h>
#import <fcntl.h>
#import <stdio.h>
#import <string.h>

#import "ServiceManagerState.h"
#import "TerminalApp.h"

extern int NXIsPrint(int character);

@interface NSPopUpButton (WhyIsntThisInTheAppKit)
- (id)itemWithTag:(int)tag;
@end

@interface NSMatrix (ServiceManagerSave)
- (BOOL)getRow:(int *)row column:(int *)column ofCell:(id)cell;
@end

@interface ServiceCache (ServiceManagerSave)
- (void)writeService:(TerminalServiceRecord *)service toFile:(void *)file;
- (void)saveService:(TerminalServiceRecord *)service inSlot:(int)slot;
- (void)setOKToSave:(char)allowed;
- (int)addNewTermService:(TerminalServiceRecord *)service;
- (void)removeServiceAt:(int)index;
@end

@implementation NSPopUpButton (WhyIsntThisInTheAppKit)

- (id)itemWithTag:(int)tag
{
    NSMenu *popupMenu = [self menu];
    int itemCount = [popupMenu numberOfItems];
    int index;

    if (popupMenu == nil)
        return nil;
    for (index = 0; index < itemCount; ++index) {
        id item = [popupMenu itemAtIndex:index];

        if ([item tag] == tag)
            return item;
    }
    return nil;
}

@end

@implementation ServiceManager

- (id)init
{
    NSBundle *bundle;
    NSString *nibPath;
    NSDictionary *externalNameTable;
    NSNotificationCenter *notificationCenter;

    [super init];
    bundle = [NSBundle bundleForClass:[self class]];
    nibPath = [bundle pathForResource:@"Services" ofType:@"nib"];
    externalNameTable = [NSDictionary dictionaryWithObjectsAndKeys:
        self, @"NSOwner", nil];
    if (![NSBundle loadNibFile:nibPath externalNameTable:externalNameTable
            withZone:[self zone]])
        return nil;

    [self->svcMatrix setMode:0];
    [self->svcScrollView setHasHorizontalScroller:YES];
    notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
        selector:@selector(windowDidResize:)
        name:NSWindowDidResizeNotification object:self->window];
    self->origFrame = [self->window frame];
    self->dirty = 0;
    self->neverLoaded = 1;
    self->currentExecType = 32;
    return self;
}

- (void)go:(char)forceReload
{
    TerminalApp *application;
    ServiceCache *cache;
    TerminalServiceSet *serviceSet;
    TerminalServiceRecord emptyService = { 0 };
    id selectedCell;
    id cell;
    id previousTitle;
    int previousRow;
    int selectedRow;
    int rowCount;
    int index;
    char hadSelection;

    application = (TerminalApp *)NSApp;
    cache = [application serviceCache];
    if (([cache serviceSetChanged] || forceReload || self->neverLoaded) &&
        ![self isDirty]) {
        self->neverLoaded = 0;
        [self->window disableFlushWindow];

        selectedCell = [self->svcMatrix selectedCell];
        hadSelection = selectedCell != nil;
        previousRow = [self->svcMatrix selectedRow];
        previousTitle = [selectedCell title];

        if (![cache loadServiceSet] ||
            (serviceSet = [cache serviceSet]) == NULL) {
            [self->window setDelegate:self];
            [self->window enableFlushWindow];
            [self->window displayIfNeeded];
            return;
        }

        [self renewForServiceSet:serviceSet];
        if (serviceSet->count != 0) {
            selectedRow = 0;
            if (hadSelection) {
                rowCount = [self cellCountFor:self->svcMatrix];
                for (index = 0; index < rowCount; ++index) {
                    cell = [self->svcMatrix cellAtRow:index column:0];
                    if ([previousTitle isEqualToString:[cell title]]) {
                        selectedRow = index;
                        break;
                    }
                }
                if (selectedRow == 0) {
                    selectedRow = rowCount - 1;
                    if (selectedRow > previousRow)
                        selectedRow = previousRow;
                }
            }

            cell = [self->svcMatrix cellAtRow:selectedRow column:0];
            [cell setState:0];
            [self->svcMatrix selectCellAtRow:selectedRow column:0];
            [self->svcMatrix scrollCellToVisibleAtRow:selectedRow column:0];
            [self serviceSelected:self];
        } else {
            [self setControlsFromService:&emptyService];
            [self->commandForm selectTextAtIndex:0];
            [self setDirty:0];
        }

        [self->svcMatrix display];
        [self->window enableFlushWindow];
        [self->window displayIfNeeded];
    }

    [self updateForCurrentDirtiness];
    [self->window setDelegate:self];
}

- (int)cellCountFor:(id)table
{
    int rows;
    int columns;

    [table getNumberOfRows:&rows columns:&columns];
    return rows * columns;
}

- (void)renewForServiceSet:(TerminalServiceSet *)serviceSet
{
    NSBundle *bundle = [NSBundle mainBundle];
    id cell;
    NSString *title;
    int index;

    if ([self cellCountFor:self->svcMatrix] != serviceSet->count)
        [self->svcMatrix renewRows:serviceSet->count columns:1];

    for (index = 0; index < serviceSet->count; ++index) {
        cell = [self->svcMatrix cellAtRow:index column:0];
        title = [bundle localizedStringForKey:
            serviceSet->records[index].name value:@"" table:@"Services"];
        [cell setTitle:title];
    }
    [self->svcMatrix sizeToCells];
    [self->svcMatrix display];
}

- (char)nameUnique:(id)name
{
    TerminalApp *application = (TerminalApp *)NSApp;
    TerminalServiceSet *serviceSet =
        [[application serviceCache] serviceSet];
    int selectedRow = [self->svcMatrix selectedRow];
    int index;

    for (index = 0; index < [self cellCountFor:self->svcMatrix]; ++index) {
        if (index != selectedRow &&
            [serviceSet->records[index].name isEqualToString:name])
            return 0;
    }
    return 1;
}

- (void)setFlags:(unsigned char *)flags fromControlsIn:(id)controls
{
    NSEnumerator *cells;
    id cell;

    if ([controls isEnabled] == 0) {
        *flags = 0;
        return;
    }

    self->currentFlags = 0;
    cells = [[controls cells] objectEnumerator];
    while ((cell = [cells nextObject]) != nil)
        [self setFlagsFromCell:cell];
    *flags = self->currentFlags;
}

- (char)setFlagsFromCell:(id)cell
{
    if ([cell state] != 0)
        self->currentFlags = TerminalServiceManagerAccumulateCellFlag(
            self->currentFlags, 1, (unsigned char)[cell tag]);
    return 1;
}

- (int)whyAreSettingsNotAcceptable
{
    unsigned char selectionFlags = 0;
    int returnsResult = 0;

    [self setFlags:&selectionFlags fromControlsIn:self->selTypes];
    if (self->currentExecType == 32)
        returnsResult = [[self->polymorphicOpts cellWithTag:4] state] != 0;
    return TerminalServiceManagerSettingsError(selectionFlags,
        self->currentExecType, returnsResult);
}

- (char)checkSettings
{
    int error = [self whyAreSettingsNotAcceptable];

    if (error == 0)
        return 1;
    if (error == 8) {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *title = [bundle localizedStringForKey:@"Terminal Services"
            value:@"Terminal Services" table:nil];
        NSString *message = [bundle localizedStringForKey:
            @"Services must either require a selection or return a result.  Since this service does not accept a selection, it must run in the background and return its output to the service requestor."
            value:@"Services must either require a selection or return a result.  Since this service does not accept a selection, it must run in the background and return its output to the service requestor."
            table:nil];
        NSRunAlertPanel(title, message, nil, nil, nil);
    } else {
        NSBeep();
    }
    return 0;
}

- (void)change:(id)sender
{
    TerminalApp *application = (TerminalApp *)NSApp;
    ServiceCache *cache;
    TerminalServiceRecord service = { 0 };
    id selectedCell;
    int row;

    (void)sender;
    [self->window endEditingFor:nil];
    [self->svcMatrix display];
    if (![self checkSettings])
        return;

    [self fillServiceFromWindow:&service];
    [self warnAboutStrangeness:&service];
    [self->window disableFlushWindow];
    selectedCell = [self->svcMatrix selectedCell];
    service.name = [[NSString allocWithZone:[self zone]]
        initWithString:[selectedCell title]];
    row = [self->svcMatrix selectedRow];
    cache = [application serviceCache];
    [cache saveService:&service inSlot:row];
    [cache setOKToSave:1];
    [self setDirty:0];
    [self renewForServiceSet:[cache serviceSet]];
    [self->svcMatrix display];
    [self->window enableFlushWindow];
    [self->window flushWindow];
    [self freeService:&service];
}

- (void)add:(id)sender
{
    TerminalApp *application = (TerminalApp *)NSApp;
    ServiceCache *cache;
    TerminalServiceSet *serviceSet;
    TerminalServiceRecord service = { 0 };
    NSUserDefaults *defaults;
    NSBundle *bundle;
    NSString *format;
    NSString *serviceName;
    id cell;
    int sequence;
    int index;
    int row;
    char name[520];

    (void)sender;
    [self->window endEditingFor:nil];
    cell = [self->svcMatrix selectedCell];
    [cell setEditable:0];
    [self->svcMatrix display];
    if (![self checkSettings])
        return;

    [self->window disableFlushWindow];
    cache = [application serviceCache];
    serviceSet = [cache serviceSet];
    [cache setOKToSave:1];

    defaults = [NSUserDefaults standardUserDefaults];
    sequence = [defaults integerForKey:@"ServiceSequenceNumber"];
    [defaults setInteger:sequence + 1 forKey:@"ServiceSequenceNumber"];

    [self fillServiceFromWindow:&service];
    service.flags = (unsigned int)sequence;
    [self warnAboutStrangeness:&service];
    bundle = [NSBundle mainBundle];
    format = [bundle localizedStringForKey:@"New Service #%d"
        value:@"" table:nil];

    sequence = 1;
    for (;;) {
        sprintf(name, [format cString], sequence);
        for (index = 0; serviceSet != nil && index < serviceSet->count;
            ++index) {
            if (strcmp(name, [serviceSet->records[index].name cString]) == 0)
                break;
        }
        if (serviceSet == nil || index == serviceSet->count)
            break;
        ++sequence;
    }

    serviceName = [[NSString allocWithZone:[self zone]]
        initWithCString:name];
    service.name = serviceName;
    row = [cache addNewTermService:&service];
    [self freeService:&service];

    [self renewForServiceSet:[cache serviceSet]];
    cell = [self->svcMatrix cellAtRow:row column:0];
    [cell setEditable:1];
    [self->svcMatrix selectCellAtRow:row column:0];
    [self->svcMatrix scrollCellToVisibleAtRow:row column:0];
    [self serviceSelected:self];
    [self->svcMatrix selectTextAtRow:row column:0];
    self->dirty = 0;
    [self updateForCurrentDirtiness];
    [self->window enableFlushWindow];
    [self->window flushWindow];
}

- (char)windowShouldClose:(id)sender
{
    NSBundle *bundle;
    NSString *title;
    NSString *message;
    NSString *defaultButton;
    NSString *alternateButton;
    NSString *otherButton;
    int response;

    if (![self isDirty])
        return 1;

    [self->window makeKeyAndOrderFront:self];
    bundle = [NSBundle mainBundle];
    title = [bundle localizedStringForKey:@"Close" value:@"Close" table:nil];

    if ([self whyAreSettingsNotAcceptable] != 0) {
        message = [bundle localizedStringForKey:
            @"Your changes to this service have not been saved, and can't be used as they are. Would you like to discard the changes?"
            value:@"Your changes to this service have not been saved, and can't be used as they are. Would you like to discard the changes?"
            table:nil];
        defaultButton = [bundle localizedStringForKey:@"Discard Changes"
            value:@"Discard Changes" table:nil];
        alternateButton = [bundle localizedStringForKey:@"Cancel"
            value:@"Cancel" table:nil];
        response = NSRunAlertPanel(title, message, defaultButton,
            alternateButton, nil);
        if (response == 0)
            return 0;
        if (response != 1)
            NSBeep();
        return 1;
    }

    message = [bundle localizedStringForKey:
        @"Your changes to this service have not been saved. Do you want to keep them?"
        value:@"Your changes to this service have not been saved. Do you want to keep them?"
        table:nil];
    defaultButton = [bundle localizedStringForKey:@"Save Changes"
        value:@"Save Changes" table:nil];
    alternateButton = [bundle localizedStringForKey:@"Discard Changes"
        value:@"Discard Changes" table:nil];
    otherButton = [bundle localizedStringForKey:@"Cancel"
        value:@"Cancel" table:nil];
    response = NSRunAlertPanel(title, message, defaultButton,
        alternateButton, otherButton);
    if (response == -1)
        return 0;
    if (response == 1)
        [self change:self];
    else if (response != 0)
        NSBeep();
    return 1;
}

- (void)save:(id)sender
{
    TerminalApp *application = (TerminalApp *)NSApp;
    NSSavePanel *panel;
    NSBundle *bundle;
    NSString *title;
    NSString *message;
    NSString *filename;
    ServiceCache *cache;
    TerminalServiceSet *serviceSet;
    id destinationCell;
    id sourceCell;
    const char *characters;
    int rows;
    int selectedRow;
    int row;
    int descriptor;

    (void)sender;
    [self->window endEditingFor:nil];
    [self->svcMatrix display];
    self->savingCache = [application serviceCache];
    if (self->savingCache == nil) {
        NSBeep();
        return;
    }

    panel = [NSSavePanel savePanel];
    [panel setRequiredFileType:@"svcs"];
    [panel setAccessoryView:self->saveAccessory];
    [self->saveMatrix setAutoscroll:1];
    bundle = [NSBundle mainBundle];
    title = [bundle localizedStringForKey:@"Save Services"
        value:@"" table:nil];
    [panel setTitle:title];

    rows = [self cellCountFor:self->svcMatrix];
    [self->saveMatrix renewRows:rows columns:1];
    for (row = 0; row < rows; ++row) {
        destinationCell = [self->saveMatrix cellAtRow:row column:0];
        sourceCell = [self->svcMatrix cellAtRow:row column:0];
        [destinationCell setTitle:[sourceCell title]];
    }
    [self->saveMatrix sizeToCells];
    selectedRow = [self->svcMatrix selectedRow];
    [self->saveMatrix selectCellAtRow:selectedRow column:0];
    selectedRow = [self->saveMatrix selectedRow];
    [self->saveMatrix scrollCellToVisibleAtRow:selectedRow column:0];
    [self->saveMatrix display];

    if ([panel runModal] != 1)
        return;
    filename = [panel filename];
    if (filename == nil)
        return;
    characters = [filename cString];
    descriptor = open(characters, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (descriptor == -1) {
        title = [bundle localizedStringForKey:@"Save Services"
            value:@"" table:nil];
        message = [bundle localizedStringForKey:@"Cannot write %s."
            value:@"" table:nil];
        NSRunAlertPanel(title, message, nil, nil, nil, characters);
        return;
    }

    self->savingFile = (void *)fdopen(descriptor, "w");
    self->savingSet = [self->savingCache serviceSet];
    serviceSet = (TerminalServiceSet *)self->savingSet;
    if (serviceSet->count != [self cellCountFor:self->svcMatrix]) {
        NSBeep();
        return;
    }

    [self->saveMatrix sendAction:@selector(saveService:) to:self
        forAllCells:0];
    fclose((FILE *)self->savingFile);
}

- (void)warnAboutStrangeness:(TerminalServiceRecord *)service
{
    if (TerminalServiceManagerShouldWarnAboutStrangeness(
            service->options[1], service->options[2])) {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *title = [bundle localizedStringForKey:@"Strange Command"
            value:@"Strange Command" table:nil];
        NSString *message = [bundle localizedStringForKey:
            @"Commands may not contain the characters '%s'."
            value:@"Commands may not contain the characters '%s'." table:nil];
        NSRunAlertPanel(title, message, nil, nil, nil);
    }
}

- (id)setControlsIn:(id)controls fromFlags:(unsigned char)flags
{
    NSArray *cells;
    id cell;
    int row;
    int column;
    int index;
    int cellCount;

    if ([controls isEnabled]) {
        cells = [controls cells];
        cellCount = [self cellCountFor:controls];
        for (index = 0; index < cellCount; ++index) {
            cell = [cells objectAtIndex:(unsigned int)index];
            [controls getRow:&row column:&column ofCell:cell];
            [controls setState:TerminalServiceManagerCellMatchesFlags(
                (unsigned char)[cell tag], flags)
                atRow:row column:column];
        }
    }
    return controls;
}

- (void)fillServiceFromWindow:(TerminalServiceRecord *)service
{
    id cell;
    id value;
    const char *command;
    const char *key;
    size_t commandLength;
    NSZone *zone;
    int index;

    service->flags = self->currentSequenceNumber;
    for (index = 0; index < 9; ++index)
        service->options[index] = 0;

    [self setFlags:&service->options[2] fromControlsIn:self->selOpts];
    [self setFlags:&service->options[5] fromControlsIn:self->shellOpts];
    [self setFlags:&service->options[1] fromControlsIn:self->selTypes];
    if (service->options[1] == 0)
        service->options[1] = 1;

    if (self->currentExecType == 32) {
        service->options[4] = 1;
        [self setFlags:&service->options[6]
            fromControlsIn:self->polymorphicOpts];
    } else {
        [self setFlags:&service->options[4]
            fromControlsIn:self->polymorphicOpts];
    }
    service->options[7] = TerminalServiceManagerRoutingFlags(
        service->options[4], service->options[6]);
    service->options[0] = 1;

    cell = [self->commandForm cellAtIndex:0];
    value = [cell objectValue];
    command = [value cString];
    commandLength = strlen(command);
    zone = [self zone];
    service->command = (char *)NSZoneMalloc(zone, commandLength + 1);
    strcpy((char *)service->command, command);
    service->options[3] = strstr(command, "-f") != 0 ? 2 : 1;

    cell = [self->keyForm cellAtIndex:0];
    key = [[cell objectValue] cString];
    if (key != 0 && strlen(key) != 0)
        service->reserved = *key;
    else
        service->reserved = ' ';
}

- (void)setControlsFromService:(TerminalServiceRecord *)service
{
    id controls;
    id cell;
    id value;
    char keyString[2];

    [self->window disableFlushWindow];
    controls = [self setControlsIn:self->selTypes
        fromFlags:service->options[1]];
    [controls display];
    controls = [self setControlsIn:self->selOpts
        fromFlags:service->options[2]];
    [controls display];
    [self setupExecBoxForWindowType:service->options[4]
        routingFlags:service->options[6] andSetPopUp:1];
    if ([self->shellOpts isEnabled]) {
        controls = [self setControlsIn:self->shellOpts
            fromFlags:service->options[5]];
        [controls display];
    }

    cell = [self->commandForm cellAtIndex:0];
    value = [NSString stringWithCString:service->command];
    [cell setObjectValue:value];

    TerminalServiceManagerFormatKey(service->reserved, keyString);
    value = [NSString stringWithCString:keyString];
    cell = [self->keyForm cellAtIndex:0];
    [cell setObjectValue:value];

    [self->window enableFlushWindow];
    [self->window displayIfNeeded];
}

- (char)control:(id)control textShouldEndEditing:(id)fieldEditor
{
    id selectedCell;
    id currentTitle;
    id editedString;
    const char *characters;
    int length;
    int index;

    if (control != self->svcMatrix)
        return 1;

    selectedCell = [control selectedCell];
    editedString = [fieldEditor string];
    currentTitle = [selectedCell title];
    if ([currentTitle isEqualToString:editedString])
        return 1;

    length = (int)[editedString cStringLength];
    if (length == 0)
        return 0;
    characters = [editedString cString];
    for (index = 0; index < length; ++index) {
        if (NXIsPrint(characters[index]) == 0)
            return 0;
    }
    return [self nameUnique:editedString];
}

- (char)isDirty
{
    return self->dirty;
}

- (void)setDirty:(char)value
{
    int hasSelection = [self->svcMatrix selectedCell] != nil;
    char effectiveValue = (char)TerminalServiceManagerEffectiveDirty(
        value, hasSelection);

    if (self->dirty != effectiveValue) {
        self->dirty = effectiveValue;
        [self updateForCurrentDirtiness];
    }
}

- (void)updateForCurrentDirtiness
{
    id selectedCell;
    TerminalServiceManagerDirtiness state;

    [self->window update];
    selectedCell = [self->svcMatrix selectedCell];
    TerminalServiceManagerGetDirtiness(self->dirty, selectedCell != nil,
        &state);
    [self->changeButton setEnabled:state.changeEnabled];
    [self->removeButton setEnabled:state.removeEnabled];
    [self->saveButton setEnabled:state.saveEnabled];
    [self->window setDocumentEdited:(unsigned char)self->dirty];
    [self->window displayIfNeeded];
}

- (void)editSelectedServiceName:(id)sender
{
    NSMatrix *matrix = self->svcMatrix;
    id cell;
    NSText *editor;
    NSEvent *event;
    NSRect frame;
    int row;
    int column;

    (void)sender;
    cell = [matrix selectedCell];
    row = [matrix selectedRow];
    column = [matrix selectedColumn];
    frame = [matrix cellFrameAtRow:row column:column];
    frame.origin.x += 1.0f;
    frame.origin.y -= 2.0f;

    editor = [self->window fieldEditor:YES forObject:matrix];
    if (editor == nil) {
        NSBeep();
        return;
    }

    [cell setEditable:YES];
    event = [NSApp currentEvent];
    [cell editWithFrame:frame inView:matrix editor:editor delegate:matrix
        event:event];
}

- (void)makeDirty:(id)sender
{
    (void)sender;
    [self setDirty:1];
}

- (void)remove:(id)sender
{
    TerminalApp *application;
    ServiceCache *cache;
    id cell;
    int row;

    (void)sender;
    [self->window setDelegate:nil];
    cell = [self->svcMatrix cellAtRow:self->lastSelected column:0];
    [cell setState:0];
    [self->svcMatrix display];
    [self->window update];
    [self->window disableFlushWindow];

    application = (TerminalApp *)NSApp;
    cache = [application serviceCache];
    [cache setOKToSave:1];
    if ([self isDirty])
        [self setDirty:0];

    cache = [application serviceCache];
    row = [self->svcMatrix selectedRow];
    [cache removeServiceAt:row];
    [self go:1];
    [self->window enableFlushWindow];
    [self->window displayIfNeeded];
}

- (NSSize)windowWillResize:(id)targetWindow toSize:(NSSize)size
{
    (void)targetWindow;
    if (size.width < self->origFrame.size.width)
        size.width = self->origFrame.size.width;
    if (size.height < self->origFrame.size.height)
        size.height = self->origFrame.size.height;
    return size;
}

- (void)controlTextDidChange:(id)sender
{
    (void)sender;
    [self setDirty:1];
}

- (void)windowDidResize:(id)sender
{
    NSSize contentSize;

    (void)sender;
    contentSize = [self->svcScrollView contentSize];
    [self->svcMatrix setCellSize:NSMakeSize(contentSize.width, 16.0f)];
    [self->svcMatrix sizeToCells];
    [self->svcMatrix display];
}

- (void)controlTextDidEndEditing:(id)sender
{
    id editor;
    id field;
    id movement;
    id movementKey;
    id matrix;
    id cell;
    TerminalApp *application;
    ServiceCache *cache;
    TerminalServiceSet *serviceSet;
    TerminalServiceRecord service;
    TerminalServiceRecord *selectedService;
    id editedName;
    unsigned int row;

    editor = [sender object];
    field = [editor delegate];
    movementKey = [NSString stringWithCString:"NSTextMovement"];
    movement = [[sender userInfo] objectForKey:movementKey];
    if (field != self->svcMatrix)
        return;

    matrix = self->svcMatrix;
    cell = [matrix selectedCell];
    application = (TerminalApp *)NSApp;
    cache = [application serviceCache];
    serviceSet = [cache serviceSet];
    row = (unsigned int)[matrix selectedRow];
    selectedService = &serviceSet->records[row];
    service = *selectedService;

    editedName = [editor string];
    if ([[cell title] isEqualToString:editedName]) {
        [matrix abortEditing];
    } else {
        [cell setTitle:editedName];
        [editedName retain];
        service.name = editedName;
        service.command = NSZoneMalloc([self zone],
            strlen(service.command) + 1);
        TerminalServiceManagerCopyCommand((char *)service.command,
            selectedService->command);
        row = (unsigned int)[matrix selectedRow];
        [cache saveService:&service inSlot:(int)row];
    }

    if ([movement intValue] == NSReturnTextMovement) {
        [self->changeButton performClick:self];
        self->ignoreNextMatrixAction = 1;
    }
}

- (void)saveService:(id)sender
{
    int row;
    int column;
    TerminalServiceSet *serviceSet;
    TerminalServiceRecord *service;

    [self->saveMatrix getRow:&row column:&column ofCell:sender];
    (void)column;
    serviceSet = (TerminalServiceSet *)self->savingSet;
    service = &serviceSet->records[row];
    [self->savingCache writeService:service toFile:self->savingFile];
}

- (void)freeService:(TerminalServiceRecord *)service
{
    NSZone *zone;

    [service->name release];
    zone = NSZoneFromPointer((void *)service->command);
    NSZoneFree(zone, (void *)service->command);
}

- (void)execTypeChanged:(id)sender
{
    int executionType;
    unsigned char windowType;
    unsigned char routingFlags;

    executionType = [[sender selectedCell] intValue];
    if (executionType == self->currentExecType)
        return;

    TerminalServiceManagerGetExecutionBoxArguments(executionType,
        &windowType, &routingFlags);
    [self setupExecBoxForWindowType:windowType
        routingFlags:routingFlags andSetPopUp:0];
    [self setDirty:1];
}

- (void)setupExecBoxForWindowType:(unsigned char)windowType
    routingFlags:(unsigned char)routingFlags andSetPopUp:(char)setPopUp
{
    NSBundle *bundle = [NSBundle mainBundle];
    id cell;
    id item;
    NSString *title;
    int index;
    int popupTag;

    if (windowType == 1) {
        cell = [self->polymorphicOpts cellAtRow:0 column:0];
        title = [bundle localizedStringForKey:@"Return Output"
            value:@"Return Output" table:nil];
        [cell setTitle:title];
        cell = [self->polymorphicOpts cellAtRow:1 column:0];
        title = [bundle localizedStringForKey:@"Discard Output"
            value:@"Discard Output" table:nil];
        [cell setTitle:title];
        [self setControlsIn:self->polymorphicOpts fromFlags:routingFlags];
        [self->polymorphicOpts display];
        self->currentExecType = 32;
    } else {
        cell = [self->polymorphicOpts cellAtRow:0 column:0];
        title = [bundle localizedStringForKey:@"New Window"
            value:@"New Window" table:nil];
        [cell setTitle:title];
        cell = [self->polymorphicOpts cellAtRow:1 column:0];
        title = [bundle localizedStringForKey:@"Idle Window"
            value:@"Idle Window" table:nil];
        [cell setTitle:title];
        [self setControlsIn:self->polymorphicOpts fromFlags:windowType];
        [self->polymorphicOpts display];
        self->currentExecType = 64;
    }

    if (TerminalServiceManagerShellOptionsEnabled(routingFlags) == 0) {
        for (index = 0; index < [self cellCountFor:self->shellOpts]; ++index) {
            cell = [self->shellOpts cellAtRow:index column:0];
            [cell setState:0];
        }
        [self->shellOpts setEnabled:0];
        [self->shellOpts display];
    } else {
        [self->shellOpts setEnabled:1];
        cell = [self->shellOpts selectedCell];
        if ([cell tag] == 0) {
            [self->shellOpts selectCellWithTag:4];
            cell = [self->shellOpts cellWithTag:4];
            [cell setState:1];
        }
        [self->shellOpts sizeToCells];
    }

    if (setPopUp != 0) {
        popupTag = TerminalServiceManagerExecutionPopupTagForWindowType(
            windowType, routingFlags);
        item = [self->execTypePopUp itemWithTag:popupTag];
        title = [item title];
        if (title == nil)
            title = @"Oh no!  No title!";
        [self->execTypePopUp setTitle:title];
    }
}

- (void)serviceSelected:(id)sender
{
    TerminalApp *application;
    ServiceCache *cache;
    TerminalServiceSet *serviceSet;
    TerminalServiceRecord *service;
    id selectedCell;
    id previousCell;
    int row;

    if (self->ignoreNextMatrixAction != 0) {
        self->ignoreNextMatrixAction = 0;
        return;
    }

    application = (TerminalApp *)NSApp;
    cache = [application serviceCache];
    serviceSet = [cache serviceSet];
    if (serviceSet == NULL)
        return;
    if (serviceSet->count == 0) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd object:self file:@"ServiceManager.m"
            lineNumber:245 description:@"Selected service with no available svcs?"];
    }

    selectedCell = [self->svcMatrix selectedCell];
    if ([selectedCell isEnabled] == 0) {
        previousCell = [self->svcMatrix cellAtRow:self->lastSelected column:0];
        [previousCell setState:0];
        [selectedCell setState:1];
    }

    row = [self->svcMatrix selectedRow];
    self->lastSelected = row;
    service = &serviceSet->records[row];
    self->currentSequenceNumber = service->flags;
    [self setDirty:0];
    [self setControlsFromService:service];
    [[self->svcMatrix selectedCell] setState:1];
    [self->svcMatrix display];
    (void)sender;
}

- (void)polymorphicOptsChanged:(id)sender
{
    id cell;
    int index;

    if (self->currentExecType == 64) {
        cell = [self->polymorphicOpts selectedCell];
        if ((int)[cell state] == 2) {
            for (index = 0; index < [self cellCountFor:self->shellOpts];
                ++index) {
                cell = [self->shellOpts cellAtRow:index column:0];
                [cell setState:0];
            }
            [self->shellOpts setEnabled:0];
            [self->shellOpts display];
        } else {
            [self->shellOpts setEnabled:1];
            cell = [self->shellOpts selectedCell];
            if ([cell tag] == 0) {
                [self->shellOpts selectCellWithTag:4];
                cell = [self->shellOpts cellWithTag:4];
                [cell setState:1];
            }
            [self->shellOpts sizeToCells];
        }
    }
    [self setDirty:1];
    (void)sender;
}

@end
