#import <AppKit/AppKit.h>
#include <signal.h>
#include <unistd.h>
#import "../ProcessControl.h"
#import "test_support.h"

@interface PVTestType : NSObject {
    BOOL _matches;
}
- (id)initWithMatch:(BOOL)matches;
- (BOOL)matchesProcess:(id)process;
@end

@implementation PVTestType
- (id)initWithMatch:(BOOL)matches
{
    self = [super init];
    if (self != nil)
        _matches = matches;
    return self;
}
- (BOOL)matchesProcess:(id)process
{
    return _matches;
}
@end

@interface PVTestMenuItem : NSObject {
    id _representedObject;
    SEL _action;
    int _tag;
}
- (id)initWithRepresentedObject:(id)object;
- (id)representedObject;
- (void)setAction:(SEL)action;
- (SEL)action;
- (void)setTag:(int)tag;
- (int)tag;
@end

@implementation PVTestMenuItem
- (id)initWithRepresentedObject:(id)object
{
    self = [super init];
    if (self != nil)
        _representedObject = [object retain];
    return self;
}
- (id)representedObject { return _representedObject; }
- (void)setAction:(SEL)action { _action = action; }
- (SEL)action { return _action; }
- (void)setTag:(int)tag { _tag = tag; }
- (int)tag { return _tag; }
- (void)dealloc
{
    [_representedObject release];
    [super dealloc];
}
@end

@interface PVTestButton : NSObject {
    int _state;
}
- (id)initWithState:(int)state;
- (int)state;
- (void)setState:(int)state;
@end

@implementation PVTestButton
- (id)initWithState:(int)state
{
    self = [super init];
    if (self != nil)
        _state = state;
    return self;
}
- (int)state { return _state; }
- (void)setState:(int)state { _state = state; }
@end

@interface PVTestInspector : NSObject {
    int _visibility;
    unsigned int _visibilityChangeCount;
    int _infoKind;
    id _process;
}
- (void)setVisible:(BOOL)visible;
- (BOOL)isVisible;
- (int)visibility;
- (unsigned int)visibilityChangeCount;
- (void)showInfoForNoSelection;
- (void)showInfoForMultipleSelection;
- (void)showInfoForProcess:(id)process;
- (int)infoKind;
- (id)process;
@end

@implementation PVTestInspector
- (void)setVisible:(BOOL)visible
{
    _visibility = visible;
    ++_visibilityChangeCount;
}
- (int)visibility { return _visibility; }
- (BOOL)isVisible { return _visibility != 0; }
- (unsigned int)visibilityChangeCount { return _visibilityChangeCount; }
- (void)showInfoForNoSelection
{
    _infoKind = 1;
    _process = nil;
}
- (void)showInfoForMultipleSelection
{
    _infoKind = 3;
    _process = nil;
}
- (void)showInfoForProcess:(id)process
{
    _infoKind = 2;
    _process = process;
}
- (int)infoKind { return _infoKind; }
- (id)process { return _process; }
@end

@interface PVTestPopup : NSObject {
    id _selectedItem;
}
- (id)initWithType:(id)type;
- (id)selectedItem;
@end

@implementation PVTestPopup
- (id)initWithType:(id)type
{
    self = [super init];
    if (self != nil && type != nil)
        _selectedItem = [[PVTestMenuItem alloc] initWithRepresentedObject:type];
    return self;
}
- (id)selectedItem { return _selectedItem; }
- (void)dealloc
{
    [_selectedItem release];
    [super dealloc];
}
@end

@interface PVTestTextField : NSObject {
    NSString *_value;
}
- (id)initWithValue:(NSString *)value;
- (id)stringValue;
- (void)setStringValue:(NSString *)value;
- (double)doubleValue;
- (float)floatValue;
- (void)setDoubleValue:(double)value;
- (void)setFloatValue:(float)value;
@end

@implementation PVTestTextField
- (id)initWithValue:(NSString *)value
{
    self = [super init];
    if (self != nil)
        _value = [value copy];
    return self;
}
- (id)stringValue { return _value; }
- (double)doubleValue { return [_value doubleValue]; }
- (float)floatValue { return (float)[_value doubleValue]; }
- (void)setDoubleValue:(double)value
{
    [self setStringValue:[NSString stringWithFormat:@"%g", value]];
}
- (void)setFloatValue:(float)value
{
    [self setStringValue:[NSString stringWithFormat:@"%g", value]];
}
- (void)setStringValue:(NSString *)value
{
    [_value release];
    _value = [value copy];
}
- (void)dealloc
{
    [_value release];
    [super dealloc];
}
@end

@interface PVTestRateFormatter : NSObject
- (id)minimum;
- (id)maximum;
@end

@implementation PVTestRateFormatter
- (id)minimum { return [NSNumber numberWithInt:1]; }
- (id)maximum { return [NSNumber numberWithInt:10]; }
@end

@interface PVTestRateCell : NSObject {
    PVTestRateFormatter *_formatter;
}
- (id)formatter;
@end

@implementation PVTestRateCell
- (id)init
{
    self = [super init];
    if (self != nil)
        _formatter = [[PVTestRateFormatter alloc] init];
    return self;
}
- (id)formatter { return _formatter; }
- (void)dealloc
{
    [_formatter release];
    [super dealloc];
}
@end

@interface PVTestRateField : PVTestTextField {
    PVTestRateCell *_cell;
}
- (id)initWithValue:(NSString *)value;
- (id)cell;
@end

@implementation PVTestRateField
- (id)initWithValue:(NSString *)value
{
    self = [super initWithValue:value];
    if (self != nil)
        _cell = [[PVTestRateCell alloc] init];
    return self;
}
- (id)cell { return _cell; }
- (void)dealloc
{
    [_cell release];
    [super dealloc];
}
@end

@interface PVTestStep : NSObject {
    int _value;
}
- (id)initWithStep:(int)value;
- (int)intValue;
- (float)floatValue;
@end

@implementation PVTestStep
- (id)initWithStep:(int)value
{
    self = [super init];
    if (self != nil)
        _value = value;
    return self;
}
- (int)intValue { return _value; }
- (float)floatValue { return (float)_value; }
@end

@interface PVTestTimer : NSObject {
    BOOL _invalidated;
}
- (void)invalidate;
- (BOOL)isInvalidated;
@end

@implementation PVTestTimer
- (void)invalidate { _invalidated = YES; }
- (BOOL)isInvalidated { return _invalidated; }
@end

@interface PVTestTable : NSObject {
    NSMutableArray *_selectedRows;
    NSMutableArray *_selectedColumns;
    NSMutableArray *_columns;
    id _highlightedColumnIdentifier;
    id _superview;
    int _selectedColumn;
    int _clickedColumn;
    BOOL _autosavesTableColumns;
}
- (id)init;
- (void)setColumns:(NSArray *)columns;
- (NSArray *)columns;
- (NSArray *)tableColumns;
- (id)superview;
- (void)setSuperview:(id)view;
- (id)tableColumnWithIdentifier:(id)identifier;
- (int)columnWithIdentifier:(id)identifier;
- (id)selectedColumnEnumerator;
- (void)setSelectedColumnIndexes:(NSArray *)indexes;
- (int)selectedColumn;
- (int)clickedColumn;
- (void)setSelectedColumnIndex:(int)index;
- (void)setClickedColumnIndex:(int)index;
- (void)setHighlightedColumn:(int)index;
- (void)removeTableColumn:(id)column;
- (void)addTableColumn:(id)column;
- (void)setNeedsDisplay:(BOOL)flag;
- (void)setAutosaveTableColumns:(BOOL)flag;
- (BOOL)autosavesTableColumns;
- (id)selectedRowEnumerator;
- (id)highlightedColumnIdentifier;
- (int)numberOfSelectedRows;
- (int)selectedRow;
- (void)setSelectedRows:(int)count;
- (void)setSelectedRowIndex:(int)row;
- (void)reloadData;
- (void)deselectAll:(id)sender;
- (void)selectRow:(int)row byExtendingSelection:(BOOL)extend;
@end

@implementation PVTestTable
- (id)init
{
    self = [super init];
    if (self != nil) {
        _selectedRows = [[NSMutableArray alloc] init];
        _selectedColumns = [[NSMutableArray alloc] init];
        _columns = [[NSMutableArray alloc] init];
        _selectedColumn = -1;
        _clickedColumn = -1;
    }
    return self;
}
- (void)setColumns:(NSArray *)columns { [_columns setArray:columns]; }
- (NSArray *)columns { return _columns; }
- (NSArray *)tableColumns { return [NSArray arrayWithArray:_columns]; }
- (id)superview { return _superview; }
- (void)setSuperview:(id)view
{
    if (_superview != view) {
        [_superview release];
        _superview = [view retain];
    }
}
- (id)tableColumnWithIdentifier:(id)identifier
{
    int index = [self columnWithIdentifier:identifier];
    return index >= 0 && index < (int)[_columns count]
        ? [_columns objectAtIndex:index] : nil;
}
- (int)columnWithIdentifier:(id)identifier
{
    unsigned int index;
    for (index = 0; index < [_columns count]; ++index) {
        id column = [_columns objectAtIndex:index];
        if ([[column identifier] isEqual:identifier])
            return (int)index;
    }
    return -1;
}
- (id)selectedColumnEnumerator { return [_selectedColumns objectEnumerator]; }
- (int)selectedColumn { return _selectedColumn; }
- (int)clickedColumn { return _clickedColumn; }
- (void)setSelectedColumnIndex:(int)index { _selectedColumn = index; }
- (void)setClickedColumnIndex:(int)index { _clickedColumn = index; }
- (void)setHighlightedColumn:(int)index
{
    [_highlightedColumnIdentifier release];
    _highlightedColumnIdentifier = nil;
    if (index >= 0 && index < (int)[_columns count])
        _highlightedColumnIdentifier = [[[_columns objectAtIndex:index] identifier] retain];
}
- (void)setSelectedColumnIndexes:(NSArray *)indexes
{
    [_selectedColumns setArray:indexes];
}
- (void)removeTableColumn:(id)column { [_columns removeObjectIdenticalTo:column]; }
- (void)addTableColumn:(id)column
{
    if (![_columns containsObject:column])
        [_columns addObject:column];
}
- (void)setNeedsDisplay:(BOOL)flag {}
- (void)setAutosaveTableColumns:(BOOL)flag { _autosavesTableColumns = flag; }
- (BOOL)autosavesTableColumns { return _autosavesTableColumns; }
- (id)selectedRowEnumerator { return [_selectedRows objectEnumerator]; }
- (id)highlightedColumnIdentifier { return _highlightedColumnIdentifier; }
- (int)numberOfSelectedRows { return (int)[_selectedRows count]; }
- (int)selectedRow
{
    return [_selectedRows count] == 1
        ? [[_selectedRows objectAtIndex:0] intValue] : -1;
}
- (void)setSelectedRows:(int)count
{
    int row;
    [_selectedRows removeAllObjects];
    for (row = 0; row < count; ++row)
        [_selectedRows addObject:[NSNumber numberWithInt:row]];
}
- (void)setSelectedRowIndex:(int)row
{
    [_selectedRows removeAllObjects];
    if (row >= 0)
        [_selectedRows addObject:[NSNumber numberWithInt:row]];
}
- (void)reloadData {}
- (void)deselectAll:(id)sender { [_selectedRows removeAllObjects]; }
- (void)selectRow:(int)row byExtendingSelection:(BOOL)extend
{
    if (!extend)
        [_selectedRows removeAllObjects];
    [_selectedRows addObject:[NSNumber numberWithInt:row]];
}
- (void)dealloc
{
    [_selectedRows release];
    [_selectedColumns release];
    [_columns release];
    [_highlightedColumnIdentifier release];
    [_superview release];
    [super dealloc];
}
@end

@interface PVTestColumn : NSObject {
    NSString *_identifier;
}
- (id)initWithIdentifier:(NSString *)identifier;
- (id)identifier;
@end

@implementation PVTestColumn
- (id)initWithIdentifier:(NSString *)identifier
{
    self = [super init];
    if (self != nil)
        _identifier = [identifier copy];
    return self;
}
- (id)init { return [self initWithIdentifier:@"NAME"]; }
- (id)identifier { return _identifier; }
- (void)dealloc
{
    [_identifier release];
    [super dealloc];
}
@end

@interface PVTestProcess : NSObject {
    NSMutableDictionary *_values;
    int _pid;
}
- (id)initWithValue:(id)value;
- (id)initWithUser:(NSString *)user name:(NSString *)name pid:(int)pid;
- (id)objectForKey:(id)key;
- (int)compare:(id)other context:(ProcessSortContext *)context;
- (int)processId;
- (NSDictionary *)dictionaryRepresentation;
@end

static unsigned int processRepresentationCount = 0;

@implementation PVTestProcess
- (id)initWithValue:(id)value
{
    self = [super init];
    if (self != nil) {
        _values = [[NSMutableDictionary alloc] init];
        if (value != nil)
            [_values setObject:value forKey:@"NAME"];
        _pid = 4242;
    }
    return self;
}
- (id)initWithUser:(NSString *)user name:(NSString *)name pid:(int)pid
{
    self = [self initWithValue:name];
    if (self != nil) {
        if (user != nil)
            [_values setObject:user forKey:@"USER"];
        _pid = pid;
    }
    return self;
}
- (id)objectForKey:(id)key
{
    return [_values objectForKey:key];
}
- (int)compare:(id)other context:(ProcessSortContext *)context
{
    NSString *left = [_values objectForKey:context->key];
    NSString *right = [other objectForKey:context->key];
    NSComparisonResult result = [left caseInsensitiveCompare:right];
    return context->ascending ? (int)result : -(int)result;
}
- (int)processId { return _pid; }
- (NSDictionary *)dictionaryRepresentation
{
    ++processRepresentationCount;
    return [NSDictionary dictionaryWithObjectsAndKeys:
        ([_values objectForKey:@"NAME"] != nil ? [_values objectForKey:@"NAME"] : @""),
            @"NAME",
        [NSNumber numberWithInt:_pid], @"PID", nil];
}
- (void)dealloc
{
    [_values release];
    [super dealloc];
}
@end

@interface PVTestSavePanel : NSObject {
    int _response;
    NSString *_path;
    NSString *_requiredFileType;
    NSString *_directory;
    NSString *_suggestedFile;
    unsigned int _representationCountAtPresentation;
}
- (id)initWithResponse:(int)response path:(NSString *)path;
- (void)setResponse:(int)response;
- (void)setPath:(NSString *)path;
- (void)setRequiredFileType:(NSString *)fileType;
- (int)runModalForDirectory:(NSString *)directory file:(NSString *)file;
- (NSString *)filename;
- (NSString *)requiredFileType;
- (NSString *)directory;
- (NSString *)suggestedFile;
- (unsigned int)representationCountAtPresentation;
@end

@implementation PVTestSavePanel
- (id)initWithResponse:(int)response path:(NSString *)path
{
    self = [super init];
    if (self != nil) {
        _response = response;
        _path = [path copy];
    }
    return self;
}
- (void)setResponse:(int)response { _response = response; }
- (void)setPath:(NSString *)path
{
    [_path release];
    _path = [path copy];
}
- (void)setRequiredFileType:(NSString *)fileType
{
    [_requiredFileType release];
    _requiredFileType = [fileType copy];
}
- (int)runModalForDirectory:(NSString *)directory file:(NSString *)file
{
    [_directory release];
    _directory = [directory copy];
    [_suggestedFile release];
    _suggestedFile = [file copy];
    _representationCountAtPresentation = processRepresentationCount;
    return _response;
}
- (NSString *)filename { return _path; }
- (NSString *)requiredFileType { return _requiredFileType; }
- (NSString *)directory { return _directory; }
- (NSString *)suggestedFile { return _suggestedFile; }
- (unsigned int)representationCountAtPresentation
{
    return _representationCountAtPresentation;
}
- (void)dealloc
{
    [_path release];
    [_requiredFileType release];
    [_directory release];
    [_suggestedFile release];
    [super dealloc];
}
@end

static PVTestSavePanel *controllerTestSavePanel = nil;

void PVTestControllerSetSavePanel(id panel)
{
    [controllerTestSavePanel release];
    controllerTestSavePanel = [panel retain];
}

id PVTestControllerSavePanel(void)
{
    return controllerTestSavePanel;
}

int table(int request, int pid, void *buffer, int copyout, unsigned int size)
{
    return 0;
}

@interface PVTestableProcessControl : ProcessControl
- (void)setType:(id)type filter:(NSString *)filter;
- (void)setColumnState:(NSArray *)all visible:(NSArray *)visible;
- (void)setSelectedColumnIndexes:(NSArray *)indexes;
- (void)setSelectedColumnIndex:(int)index clickedIndex:(int)clicked;
- (int)sortButtonState;
- (void)setInspectorForTest:(id)value;
- (unsigned int)showMoreInfoCallCount;
- (NSArray *)visibleColumns;
- (id)highlightedColumnIdentifier;
- (void)setSelectedTypeTag:(int)tag;
- (id)setSortButtonState:(int)state;
- (void)setProcesses:(NSArray *)processes;
- (NSString *)summaryText;
- (void)setRefreshInterval:(double)value timer:(id)newTimer;
- (void)setRateFieldValue:(double)value;
- (id)activeTimer;
- (double)refreshInterval;
- (void)setFilteredProcesses:(NSArray *)processes;
- (void)setSelectedRows:(int)count;
- (void)setSelectedRowIndex:(int)row;
- (void)setHighlightedColumnIndex:(int)index;
- (int)selectedRowIndex;
- (BOOL)autosavesTableColumns;
- (void)setProcessTableSuperview:(id)view;
- (void)setFilterText:(NSString *)text;
@end

@implementation PVTestableProcessControl
static unsigned int controllerShowMoreInfoCallCount = 0;
- (void)showMoreInfoAboutSelection:(id)sender
{
    ++controllerShowMoreInfoCallCount;
}
- (void)setInspectorForTest:(id)value { inspector = value; }
- (unsigned int)showMoreInfoCallCount
{
    return controllerShowMoreInfoCallCount;
}
- (void)setType:(id)type filter:(NSString *)filter
{
    typePopup = [[PVTestPopup alloc] initWithType:type];
    filterText = [[PVTestTextField alloc] initWithValue:filter];
    processTable = [[PVTestTable alloc] init];
    countField = [[PVTestTextField alloc] initWithValue:@""];
    allProcesses = [[NSMutableArray alloc] init];
    filteredProcesses = [[NSMutableArray alloc] init];
}
- (void)setColumnState:(NSArray *)all visible:(NSArray *)visible
{
    [(PVTestTable *)processTable setColumns:visible];
    [allColumns release];
    allColumns = [all copy];
}
- (void)setSelectedColumnIndexes:(NSArray *)indexes
{
    [(PVTestTable *)processTable setSelectedColumnIndexes:indexes];
}
- (void)setSelectedColumnIndex:(int)index clickedIndex:(int)clicked
{
    [(PVTestTable *)processTable setSelectedColumnIndex:index];
    [(PVTestTable *)processTable setClickedColumnIndex:clicked];
}
- (int)sortButtonState { return [(id)sortOrderButton state]; }
- (NSArray *)visibleColumns { return [(PVTestTable *)processTable columns]; }
- (id)highlightedColumnIdentifier
{
    return [(PVTestTable *)processTable highlightedColumnIdentifier];
}
- (void)setSelectedTypeTag:(int)tag
{
    [(PVTestMenuItem *)[(PVTestPopup *)typePopup selectedItem] setTag:tag];
}
- (id)setSortButtonState:(int)state
{
    [sortOrderButton release];
    sortOrderButton = (NSButton *)[[PVTestButton alloc] initWithState:state];
    return sortOrderButton;
}
- (void)setProcesses:(NSArray *)processes
{
    [allProcesses setArray:processes];
    [filteredProcesses setArray:processes];
}
- (void)setFilteredProcesses:(NSArray *)processes
{
    [filteredProcesses setArray:processes];
}
- (NSString *)summaryText { return [countField stringValue]; }
- (void)setRefreshInterval:(double)value timer:(id)newTimer
{
    [rateField release];
    rateField = [[PVTestTextField alloc] initWithValue:[NSString stringWithFormat:@"%g", value]];
    [timer release];
    timer = [newTimer retain];
}
- (void)setRateFieldValue:(double)value
{
    [rateField release];
    rateField = [[PVTestRateField alloc]
        initWithValue:[NSString stringWithFormat:@"%g", value]];
}
- (id)activeTimer { return timer; }
- (double)refreshInterval { return [rateField doubleValue]; }
- (void)setSelectedRows:(int)count { [(id)processTable setSelectedRows:count]; }
- (void)setSelectedRowIndex:(int)row { [(id)processTable setSelectedRowIndex:row]; }
- (void)setHighlightedColumnIndex:(int)index
{
    [(PVTestTable *)processTable setHighlightedColumn:index];
}
- (int)selectedRowIndex
{
    NSEnumerator *rows = [(id)processTable selectedRowEnumerator];
    NSNumber *row = [rows nextObject];
    return row != nil ? [row intValue] : -1;
}
- (BOOL)autosavesTableColumns
{
    return [(PVTestTable *)processTable autosavesTableColumns];
}
- (void)setProcessTableSuperview:(id)view
{
    [(PVTestTable *)processTable setSuperview:view];
}
- (void)setFilterText:(NSString *)text { [(id)filterText setStringValue:text]; }
- (void)dealloc
{
    [typePopup release];
    [sortOrderButton release];
    [filterText release];
    [processTable release];
    [countField release];
    [rateField release];
    [super dealloc];
}
@end

static void testShouldShowProcess(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control;
    PVTestType *includeType;
    PVTestType *excludeType;
    PVTestProcess *process;
    PVTestProcess *processWithoutName;
    PVTestProcess *finder;
    PVTestMenuItem *menuItem;
    PVTestColumn *column;

    includeType = [[PVTestType alloc] initWithMatch:YES];
    excludeType = [[PVTestType alloc] initWithMatch:NO];
    process = [[PVTestProcess alloc] initWithValue:@"System Preferences"];
    processWithoutName = [[PVTestProcess alloc] initWithValue:nil];

    control = [PVTestableProcessControl alloc];
    [control setType:nil filter:@""];
    PV_CHECK([control shouldShowProcess:(Process *)process]);
    [control release];

    control = [PVTestableProcessControl alloc];
    [control setType:includeType filter:@"missing value is not a rejection"];
    PV_CHECK([control shouldShowProcess:(Process *)processWithoutName]);
    [control release];

    control = [PVTestableProcessControl alloc];
    [control setType:excludeType filter:@""];
    PV_CHECK(![control shouldShowProcess:(Process *)process]);
    [control release];

    control = [PVTestableProcessControl alloc];
    [control setType:includeType filter:@"preference"];
    PV_CHECK([control shouldShowProcess:(Process *)process]);
    [control release];

    control = [PVTestableProcessControl alloc];
    [control setType:includeType filter:@"unrelated"];
    PV_CHECK(![control shouldShowProcess:(Process *)process]);
    [control release];

    [process release];
    [processWithoutName release];
    [excludeType release];
    [includeType release];

    includeType = [[PVTestType alloc] initWithMatch:YES];
    process = [[PVTestProcess alloc] initWithValue:@"System Preferences"];
    processWithoutName = [[PVTestProcess alloc] initWithValue:nil];
    finder = [[PVTestProcess alloc] initWithValue:@"Finder"];
    control = [PVTestableProcessControl alloc];
    [control setType:includeType filter:@"preference"];
    [control setProcesses:[NSArray arrayWithObjects:process, processWithoutName, finder, nil]];
    [control updateForSortChange:NO filterChange:YES];
    PV_CHECK([control numberOfRowsInTableView:nil] == 2);
    PV_CHECK_OBJECTS_EQUAL([control summaryText], @"2 of 3 processes displayed.");
    column = [[PVTestColumn alloc] init];
    PV_CHECK_OBJECTS_EQUAL([control tableView:nil objectValueForTableColumn:(NSTableColumn *)column row:0],
                           @"System Preferences");
    {
        BOOL raised = NO;
        NS_DURING
            (void)[control tableView:nil objectValueForTableColumn:(NSTableColumn *)column row:-1];
        NS_HANDLER
            raised = YES;
        NS_ENDHANDLER
        PV_CHECK(raised);
    }
    {
        BOOL raised = NO;
        NS_DURING
            (void)[control tableView:nil objectValueForTableColumn:(NSTableColumn *)column row:2];
        NS_HANDLER
            raised = YES;
        NS_ENDHANDLER
        PV_CHECK(raised);
    }
    menuItem = [[PVTestMenuItem alloc] initWithRepresentedObject:nil];
    [menuItem setAction:@selector(killProcesses:)];
    PV_CHECK(![control validateMenuItem:(NSMenuItem *)menuItem]);
    [control setSelectedRows:1];
    PV_CHECK([control validateMenuItem:(NSMenuItem *)menuItem]);
    [control setSelectedRows:2];
    PV_CHECK([control validateMenuItem:(NSMenuItem *)menuItem]);
    [menuItem setAction:@selector(showMoreInfoAboutSelection:)];
    PV_CHECK(![control validateMenuItem:(NSMenuItem *)menuItem]);
    [control setSelectedRowIndex:0];
    PV_CHECK([control validateMenuItem:(NSMenuItem *)menuItem]);
    [control setSelectedRowIndex:0];
    [control updateForSortChange:NO filterChange:YES];
    PV_CHECK([control selectedRowIndex] == 0);
    [control setFilterText:@""];
    [control updateForSortChange:NO filterChange:YES];
    PV_CHECK([control numberOfRowsInTableView:nil] == 3);
    [control setSelectedRowIndex:2];
    [control setFilterText:@"preference"];
    [control updateForSortChange:NO filterChange:YES];
    PV_CHECK([control selectedRowIndex] == -1);
    [control release];
    [menuItem release];
    [column release];
    [process release];
    [processWithoutName release];
    [finder release];
    [includeType release];
    [pool release];
}

static void testInitRegistersPPCDefaults(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control;

    PVTestControllerReset(@"raynorpat");
    control = [[PVTestableProcessControl alloc] init];
    PV_CHECK([[PVTestRegisteredDefaults() objectForKey:@"DefaultTypeTag"] intValue] == -1);
    PV_CHECK_OBJECTS_EQUAL([PVTestRegisteredDefaults() objectForKey:@"RefreshInterval"], @"20.0");
    PV_CHECK_OBJECTS_EQUAL([PVTestRegisteredDefaults() objectForKey:@"DeleteProtectedProcesses"], @"NO");

    [control release];
    [pool release];
}

static void testSetShowTypePersistsTagAndRefiltersProcesses(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id previousValue = [[defaults objectForKey:@"DefaultTypeTag"] retain];
    PVTestType *excludeType = [[PVTestType alloc] initWithMatch:NO];
    PVTestProcess *process = [[PVTestProcess alloc] initWithValue:@"Editor"];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];

    [control setType:excludeType filter:@""];
    [control setSelectedTypeTag:3];
    [control setProcesses:[NSArray arrayWithObject:process]];
    [control setShowType:nil];
    PV_CHECK([defaults integerForKey:@"DefaultTypeTag"] == 3);
    PV_CHECK([control numberOfRowsInTableView:nil] == 0);

    if (previousValue != nil)
        [defaults setObject:previousValue forKey:@"DefaultTypeTag"];
    else
        [defaults removeObjectForKey:@"DefaultTypeTag"];
    [previousValue release];
    [control release];
    [process release];
    [excludeType release];
    [pool release];
}

static void testAssignActionsEnablesTableColumnAutosaving(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [[PVTestableProcessControl alloc] init];

    [control setType:nil filter:@""];
    [control assignActions];
    PV_CHECK([control autosavesTableColumns]);

    [control release];
    [pool release];
}

static void testSortPreservesSelectedProcessIdentity(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestProcess *beta = [[PVTestProcess alloc] initWithValue:@"Beta"];
    PVTestProcess *alpha = [[PVTestProcess alloc] initWithValue:@"Alpha"];
    PVTestProcess *gamma = [[PVTestProcess alloc] initWithValue:@"Gamma"];
    PVTestColumn *nameColumn = [[PVTestColumn alloc] initWithIdentifier:@"NAME"];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    NSArray *columns = [NSArray arrayWithObject:nameColumn];

    [control setType:nil filter:@""];
    [control setProcesses:[NSArray arrayWithObjects:beta, alpha, gamma, nil]];
    [control setColumnState:columns visible:columns];
    [control setSortButtonState:1];
    [control setHighlightedColumnIndex:0];
    [control setSelectedRowIndex:0];
    [control updateForSortChange:YES filterChange:NO];

    PV_CHECK_OBJECTS_EQUAL([control tableView:nil
        objectValueForTableColumn:(NSTableColumn *)nameColumn row:0], @"Alpha");
    PV_CHECK_OBJECTS_EQUAL([control tableView:nil
        objectValueForTableColumn:(NSTableColumn *)nameColumn row:1], @"Beta");
    PV_CHECK([control selectedRowIndex] == 1);

    [control release];
    [nameColumn release];
    [gamma release];
    [alpha release];
    [beta release];
    [pool release];
}

static void testGetProcessesReplacesRowsAndStartsRefreshTimer(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestProcess *stale = [[PVTestProcess alloc] initWithValue:@"Stale process"];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    NSString *expectedSummary;
    int rows;

    [control setType:nil filter:@""];
    [control setProcesses:[NSArray arrayWithObject:stale]];
    [control setRateFieldValue:1.0];
    [control getProcesses:nil];

    rows = [control numberOfRowsInTableView:nil];
    expectedSummary = [NSString stringWithFormat:@"%d processes.", rows];
    PV_CHECK(rows > 0);
    PV_CHECK_OBJECTS_EQUAL([control summaryText], expectedSummary);
    PV_CHECK([control activeTimer] != nil);

    [control setRateFieldValue:0.0];
    [control updateRate];
    [control release];
    [stale release];
    [pool release];
}

static void testChangeSortOrderPersistsButtonState(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id previousValue = [[defaults objectForKey:@"SortAscending"] retain];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];

    [control setType:nil filter:@""];
    [control changeSortOrder:[control setSortButtonState:1]];
    PV_CHECK([defaults boolForKey:@"SortAscending"] == YES);
    [control changeSortOrder:[control setSortButtonState:0]];
    PV_CHECK([defaults boolForKey:@"SortAscending"] == NO);

    if (previousValue != nil)
        [defaults setObject:previousValue forKey:@"SortAscending"];
    else
        [defaults removeObjectForKey:@"SortAscending"];
    [previousValue release];
    [control release];
    [pool release];
}

static void testShowAllColumnsRestoresSavedColumnOrder(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestColumn *name = [[PVTestColumn alloc] initWithIdentifier:@"NAME"];
    PVTestColumn *pid = [[PVTestColumn alloc] initWithIdentifier:@"PID"];
    PVTestColumn *user = [[PVTestColumn alloc] initWithIdentifier:@"USER"];
    NSArray *all = [NSArray arrayWithObjects:name, pid, user, nil];

    [control setType:nil filter:@""];
    [control setColumnState:all visible:[NSArray arrayWithObjects:pid, name, nil]];
    [control showAllColumns:nil];
    PV_CHECK([[control visibleColumns] count] == 3);
    if ([[control visibleColumns] count] == 3) {
        PV_CHECK([[control visibleColumns] objectAtIndex:0] == name);
        PV_CHECK([[control visibleColumns] objectAtIndex:1] == pid);
        PV_CHECK([[control visibleColumns] objectAtIndex:2] == user);
    }

    [control release];
    [name release];
    [pid release];
    [user release];
    [pool release];
}

static void testHideColumnRemovesEverySelectedColumn(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestColumn *name = [[PVTestColumn alloc] initWithIdentifier:@"NAME"];
    PVTestColumn *pid = [[PVTestColumn alloc] initWithIdentifier:@"PID"];
    PVTestColumn *user = [[PVTestColumn alloc] initWithIdentifier:@"USER"];
    NSArray *all = [NSArray arrayWithObjects:name, pid, user, nil];
    NSArray *selected = [NSArray arrayWithObjects:
        [NSNumber numberWithInt:0], [NSNumber numberWithInt:2], nil];

    [control setType:nil filter:@""];
    [control setColumnState:all visible:all];
    [control setSelectedColumnIndexes:selected];
    [control hideColumn:nil];
    PV_CHECK([[control visibleColumns] count] == 1);
    if ([[control visibleColumns] count] == 1)
        PV_CHECK([[control visibleColumns] objectAtIndex:0] == pid);

    [control release];
    [name release];
    [pid release];
    [user release];
    [pool release];
}

static void testResortUsesSelectedColumnAndPreservesSortDirection(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id previousColumn = [[defaults objectForKey:@"SortColumn"] retain];
    id previousAscending = [[defaults objectForKey:@"SortAscending"] retain];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestColumn *name = [[PVTestColumn alloc] initWithIdentifier:@"NAME"];
    PVTestColumn *pid = [[PVTestColumn alloc] initWithIdentifier:@"PID"];
    NSArray *columns = [NSArray arrayWithObjects:name, pid, nil];

    [control setType:nil filter:@""];
    [control setColumnState:columns visible:columns];
    [defaults setBool:YES forKey:@"SortAscending"];
    [control setSortButtonState:1];
    [control setSelectedColumnIndex:1 clickedIndex:-1];
    [control resort:nil];
    PV_CHECK_OBJECTS_EQUAL([defaults objectForKey:@"SortColumn"], @"PID");
    PV_CHECK_OBJECTS_EQUAL([control highlightedColumnIdentifier], @"PID");
    PV_CHECK([control sortButtonState] == 1);
    PV_CHECK([defaults boolForKey:@"SortAscending"] == YES);

    [control setSelectedColumnIndex:1 clickedIndex:1];
    [control resort:nil];
    PV_CHECK([control sortButtonState] == 1);
    PV_CHECK([defaults boolForKey:@"SortAscending"] == YES);

    [control setSelectedColumnIndex:-1 clickedIndex:-1];
    [control resort:nil];
    PV_CHECK([defaults objectForKey:@"SortColumn"] == nil);

    if (previousColumn != nil)
        [defaults setObject:previousColumn forKey:@"SortColumn"];
    else
        [defaults removeObjectForKey:@"SortColumn"];
    if (previousAscending != nil)
        [defaults setObject:previousAscending forKey:@"SortAscending"];
    else
        [defaults removeObjectForKey:@"SortAscending"];
    [previousColumn release];
    [previousAscending release];
    [control release];
    [name release];
    [pid release];
    [pool release];
}

static void testToggleMoreInfoHandlesOnOffAndMixedStates(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestInspector *inspector = [[PVTestInspector alloc] init];
    PVTestButton *sender = [[PVTestButton alloc] initWithState:1];
    unsigned int priorCallCount;

    [control setType:nil filter:@""];
    [control setInspectorForTest:inspector];
    priorCallCount = [control showMoreInfoCallCount];

    [control toggleMoreInfo:sender];
    PV_CHECK([inspector visibility] == YES);
    PV_CHECK([inspector visibilityChangeCount] == 1);
    PV_CHECK([control showMoreInfoCallCount] == priorCallCount + 1);

    [sender setState:0];
    [control toggleMoreInfo:sender];
    PV_CHECK([inspector visibility] == NO);
    PV_CHECK([inspector visibilityChangeCount] == 2);
    PV_CHECK([control showMoreInfoCallCount] == priorCallCount + 1);

    [sender setState:-1];
    [control toggleMoreInfo:sender];
    PV_CHECK([inspector visibility] == NO);
    PV_CHECK([inspector visibilityChangeCount] == 2);
    PV_CHECK([control showMoreInfoCallCount] == priorCallCount + 1);

    [control release];
    [sender release];
    [inspector release];
    [pool release];
}

static void testSelectionChangesUpdateVisibleInspector(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestInspector *inspector = [[PVTestInspector alloc] init];
    PVTestProcess *first = [[PVTestProcess alloc] initWithValue:@"Editor"];
    PVTestProcess *second = [[PVTestProcess alloc] initWithValue:@"Terminal"];

    [control setType:nil filter:@""];
    [control setInspectorForTest:inspector];
    [control setFilteredProcesses:[NSArray arrayWithObjects:first, second, nil]];
    [control setSelectedRows:1];
    [control setSelectedRowIndex:0];
    [control tableViewSelectionDidChange:nil];
    PV_CHECK([inspector infoKind] == 0);

    [inspector setVisible:YES];
    [control setSelectedRows:0];
    [control tableViewSelectionDidChange:nil];
    PV_CHECK([inspector infoKind] == 1);

    [control setSelectedRows:1];
    [control setSelectedRowIndex:0];
    [control tableViewSelectionDidChange:nil];
    PV_CHECK([inspector infoKind] == 2);
    PV_CHECK([inspector process] == first);

    [control setSelectedRows:2];
    [control tableViewSelectionDidChange:nil];
    PV_CHECK([inspector infoKind] == 3);
    PV_CHECK([inspector process] == nil);

    [control release];
    [inspector release];
    [first release];
    [second release];
    [pool release];
}

static void testRateBelowMinimumInvalidatesTimer(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestTimer *oldTimer = [[PVTestTimer alloc] init];

    [control setType:nil filter:@""];
    [control setRefreshInterval:0.0 timer:oldTimer];
    [control updateRate];
    PV_CHECK([oldTimer isInvalidated]);
    PV_CHECK([control activeTimer] == nil);
    PV_CHECK([control refreshInterval] == 0.0);

    [control setRefreshInterval:1.0 timer:nil];
    [control updateRate];
    PV_CHECK([control activeTimer] != nil);

    [control release];
    [oldTimer release];
    [pool release];
}

static void testBumpRatePersistsOnlyValuesWithinFormatterBounds(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id previousValue = [[defaults objectForKey:@"RefreshInterval"] retain];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestStep *increase = [[PVTestStep alloc] initWithStep:1];
    PVTestStep *decrease = [[PVTestStep alloc] initWithStep:-1];
    id timer;
    unsigned int beeps = PVTestBeepCount();

    [control setType:nil filter:@""];
    [control setRateFieldValue:9.0];
    [control bumpRate:increase];
    PV_CHECK([control refreshInterval] == 10.0);
    PV_CHECK([defaults floatForKey:@"RefreshInterval"] == 10.0f);
    timer = [control activeTimer];
    PV_CHECK(timer != nil);

    beeps = PVTestBeepCount();
    [control bumpRate:increase];
    PV_CHECK([control refreshInterval] == 10.0);
    PV_CHECK([defaults floatForKey:@"RefreshInterval"] == 10.0f);
    PV_CHECK([control activeTimer] == timer);
    PV_CHECK(PVTestBeepCount() == beeps + 1);

    [(NSTimer *)timer invalidate];
    [control setRateFieldValue:1.0];
    [control bumpRate:decrease];
    PV_CHECK([control refreshInterval] == 1.0);
    PV_CHECK([defaults floatForKey:@"RefreshInterval"] == 10.0f);
    PV_CHECK(PVTestBeepCount() == beeps + 2);

    if (previousValue != nil)
        [defaults setObject:previousValue forKey:@"RefreshInterval"];
    else
        [defaults removeObjectForKey:@"RefreshInterval"];
    [previousValue release];
    [decrease release];
    [increase release];
    [control release];
    [pool release];
}

static void testResetRatePersistsValueAndReplacesTimer(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id previousValue = [[defaults objectForKey:@"RefreshInterval"] retain];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestTimer *oldTimer = [[PVTestTimer alloc] init];
    PVTestStep *sender = [[PVTestStep alloc] initWithStep:3];

    [control setType:nil filter:@""];
    [control setRefreshInterval:2.0 timer:oldTimer];
    [control resetRate:sender];
    PV_CHECK([oldTimer isInvalidated]);
    PV_CHECK([control refreshInterval] == 3.0);
    PV_CHECK([defaults floatForKey:@"RefreshInterval"] == 3.0f);
    PV_CHECK([control activeTimer] != nil);

    if (previousValue != nil)
        [defaults setObject:previousValue forKey:@"RefreshInterval"];
    else
        [defaults removeObjectForKey:@"RefreshInterval"];
    [previousValue release];
    [sender release];
    [oldTimer release];
    [control release];
    [pool release];
}

static void setProtectedProcessPreference(BOOL enabled)
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                           forKey:@"DeleteProtectedProcesses"];
}

static void testKillOwnedProcessWithBothSignals(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestProcess *process = [[PVTestProcess alloc]
        initWithUser:@"raynorpat" name:@"Editor" pid:31001];
    id alert;

    setProtectedProcessPreference(NO);
    PVTestControllerReset(@"raynorpat");
    PVTestControllerQueueAlertResponse(1);
    [control killProcessWithConfirmation:(Process *)process];
    PV_CHECK(PVTestControllerAlertCount() == 1);
    alert = PVTestControllerAlertAtIndex(0);
    PV_CHECK_OBJECTS_EQUAL([alert objectForKey:@"title"], @"Quit Process");
    PV_CHECK_OBJECTS_EQUAL([alert objectForKey:@"message"],
                           @"Do you really want to quit '%@'?");
    PV_CHECK_OBJECTS_EQUAL([alert objectForKey:@"default"], @"Quit");
    PV_CHECK_OBJECTS_EQUAL([alert objectForKey:@"alternate"], @"Force Quit");
    PV_CHECK_OBJECTS_EQUAL([alert objectForKey:@"other"], @"Cancel");
    PV_CHECK(PVTestControllerSignalCount() == 1);
    if (PVTestControllerSignalCount() != 0) {
        PV_CHECK(PVTestControllerSignalPidAtIndex(0) == 31001);
        PV_CHECK(PVTestControllerSignalAtIndex(0) == SIGINT);
    }

    PVTestControllerReset(@"raynorpat");
    PVTestControllerQueueAlertResponse(0);
    [control killProcessWithConfirmation:(Process *)process];
    PV_CHECK(PVTestControllerAlertCount() == 1);
    PV_CHECK(PVTestControllerSignalCount() == 1);
    if (PVTestControllerSignalCount() != 0)
        PV_CHECK(PVTestControllerSignalAtIndex(0) == SIGKILL);

    [process release];
    [control release];
    [pool release];
}

static void testKillRejectsAnotherUsersProcess(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestProcess *process = [[PVTestProcess alloc]
        initWithUser:@"other-user" name:@"Editor" pid:31002];
    id alert;

    PVTestControllerReset(@"raynorpat");
    [control killProcessWithConfirmation:(Process *)process];
    PV_CHECK(PVTestControllerAlertCount() == 1);
    PV_CHECK(PVTestControllerSignalCount() == 0);
    alert = PVTestControllerAlertAtIndex(0);
    PV_CHECK_OBJECTS_EQUAL([alert objectForKey:@"message"],
        @"You cannot quit the process '%@' because it's owned by %@.");
    PV_CHECK_OBJECTS_EQUAL([alert objectForKey:@"argument1"], @"Editor");
    PV_CHECK_OBJECTS_EQUAL([alert objectForKey:@"argument2"], @"other-user");

    [process release];
    [control release];
    [pool release];
}

static void testRootWarningPrecedesFinalConfirmation(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestProcess *process = [[PVTestProcess alloc]
        initWithUser:@"daemon" name:@"Workspace" pid:31003];
    id warning;
    id confirmation;

    setProtectedProcessPreference(YES);
    PVTestControllerReset(@"root");
    PVTestControllerQueueAlertResponse(1);
    PVTestControllerQueueAlertResponse(1);
    [control killProcessWithConfirmation:(Process *)process];
    PV_CHECK(PVTestControllerAlertCount() == 2);
    warning = PVTestControllerAlertAtIndex(0);
    PV_CHECK_OBJECTS_EQUAL([warning objectForKey:@"title"], @"WARNING");
    PV_CHECK_OBJECTS_EQUAL([warning objectForKey:@"message"],
                           @"Quitting '%@' will log you out.");
    PV_CHECK_OBJECTS_EQUAL([warning objectForKey:@"default"], @"Cancel");
    PV_CHECK_OBJECTS_EQUAL([warning objectForKey:@"alternate"], @"Go ahead");
    if (PVTestControllerAlertCount() > 1) {
        confirmation = PVTestControllerAlertAtIndex(1);
        PV_CHECK_OBJECTS_EQUAL([confirmation objectForKey:@"message"],
            @"Do you really want to quit '%@'? Any unsaved work will be lost.");
    }
    PV_CHECK(PVTestControllerSignalCount() == 1);
    if (PVTestControllerSignalCount() != 0)
        PV_CHECK(PVTestControllerSignalAtIndex(0) == SIGINT);

    [process release];
    [control release];
    [pool release];
}

static void testOwnerWarningCanCancelProtectedProcesses(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestProcess *process = [[PVTestProcess alloc]
        initWithUser:@"raynorpat" name:@"pbs" pid:31004];
    id warning;

    setProtectedProcessPreference(YES);
    PVTestControllerReset(@"raynorpat");
    PVTestControllerQueueAlertResponse(1);
    [control killProcessWithConfirmation:(Process *)process];
    PV_CHECK(PVTestControllerAlertCount() == 1);
    warning = PVTestControllerAlertAtIndex(0);
    PV_CHECK_OBJECTS_EQUAL([warning objectForKey:@"title"], @"WARNING");
    PV_CHECK_OBJECTS_EQUAL([warning objectForKey:@"message"],
                           @"Quitting '%@' might disrupt your computer.");
    PV_CHECK(PVTestControllerSignalCount() == 0);

    [process release];
    [control release];
    [pool release];
}

static void testAboutPanelUsesReferenceOptionsAndMethodArguments(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [[PVTestableProcessControl alloc] init];
    NSObject *sender = [[NSObject alloc] init];
    NSDictionary *options;

    PVTestControllerReset(@"raynorpat");
    [control showAboutPanel:sender];
    options = PVTestSystemInfoPanelOptions();
    PV_CHECK_OBJECTS_EQUAL([options objectForKey:@"CopyrightStartYear"], @"1998");
    PV_CHECK_OBJECTS_EQUAL([options objectForKey:@"Version"], @"15.0");
    PV_CHECK([options objectForKey:@"ApplicationName"] == nil);
    PV_CHECK(PVTestSystemInfoPanelCommand() == @selector(showAboutPanel:));
    PV_CHECK(PVTestSystemInfoPanelSender() == sender);

    [control showAboutPanel:sender];
    PV_CHECK(PVTestSystemInfoPanelOptions() == options);

    [sender release];
    [control release];
    [pool release];
}

static void testPrintUsesTheTableSuperviewAsItsView(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [[PVTestableProcessControl alloc] init];
    PVTestTable *scrollView = [[PVTestTable alloc] init];
    PVTestTable *containerView = [[PVTestTable alloc] init];

    [control setType:nil filter:@""];
    [control setProcessTableSuperview:scrollView];
    [scrollView setSuperview:containerView];
    PVTestControllerReset(@"raynorpat");
    [control print:nil];

    PV_CHECK(PVTestPrintOperationView() == containerView);

    [control release];
    [scrollView release];
    [containerView release];
    [pool release];
}

static void testExportBuildsFilteredRepresentationsBeforePanelAndWritesPlist(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PVTestableProcessControl *control = [PVTestableProcessControl alloc];
    PVTestProcess *process = [[PVTestProcess alloc]
        initWithUser:@"raynorpat" name:@"Worker" pid:31005];
    PVTestProcess *filteredOut = [[PVTestProcess alloc]
        initWithUser:@"raynorpat" name:@"Hidden Worker" pid:31006];
    PVTestSavePanel *panel;
    NSString *path = [NSString stringWithFormat:@"%@/ProcessViewer-export-%d.plist",
        NSTemporaryDirectory(), (int)getpid()];
    NSArray *exported;
    NSDictionary *record;
    unsigned int beeps;
    NSString *invalidPath;

    [control setType:nil filter:@""];
    [control setProcesses:[NSArray arrayWithObjects:process, filteredOut, nil]];
    [control setFilteredProcesses:[NSArray arrayWithObject:process]];
    processRepresentationCount = 0;

    panel = [[PVTestSavePanel alloc] initWithResponse:0 path:path];
    PVTestControllerSetSavePanel(panel);
    [control exportProcessList:nil];
    PV_CHECK(processRepresentationCount == 1);
    PV_CHECK([panel representationCountAtPresentation] == 1);
    PV_CHECK_OBJECTS_EQUAL([panel requiredFileType], @"plist");
    PV_CHECK_OBJECTS_EQUAL([panel directory], NSHomeDirectory());
    PV_CHECK_OBJECTS_EQUAL([panel suggestedFile], @"Exported Processes.plist");
    PV_CHECK([[NSFileManager defaultManager] fileExistsAtPath:path] == NO);
    [panel setResponse:NSOKButton];
    [control exportProcessList:nil];
    PV_CHECK(processRepresentationCount == 2);
    PV_CHECK([panel representationCountAtPresentation] == 2);
    exported = [NSArray arrayWithContentsOfFile:path];
    PV_CHECK([exported count] == 1);
    record = [exported count] != 0 ? [exported objectAtIndex:0] : nil;
    PV_CHECK_OBJECTS_EQUAL([record objectForKey:@"NAME"], @"Worker");
    PV_CHECK([[record objectForKey:@"PID"] intValue] == 31005);

    unlink([path cString]);
    invalidPath = [NSString stringWithFormat:
        @"/no-such-processviewer-directory-%d/export.plist", (int)getpid()];
    [panel setResponse:NSOKButton];
    [panel setPath:invalidPath];
    beeps = PVTestBeepCount();
    [control exportProcessList:nil];
    PV_CHECK(PVTestBeepCount() == beeps + 1);

    PVTestControllerSetSavePanel(nil);
    [panel release];
    [filteredOut release];
    [process release];
    [control release];
    [pool release];
}

int main(void)
{
    testInitRegistersPPCDefaults();
    testShouldShowProcess();
    testSetShowTypePersistsTagAndRefiltersProcesses();
    testAssignActionsEnablesTableColumnAutosaving();
    testSortPreservesSelectedProcessIdentity();
    testGetProcessesReplacesRowsAndStartsRefreshTimer();
    testChangeSortOrderPersistsButtonState();
    testShowAllColumnsRestoresSavedColumnOrder();
    testHideColumnRemovesEverySelectedColumn();
    testResortUsesSelectedColumnAndPreservesSortDirection();
    testToggleMoreInfoHandlesOnOffAndMixedStates();
    testSelectionChangesUpdateVisibleInspector();
    testRateBelowMinimumInvalidatesTimer();
    testBumpRatePersistsOnlyValuesWithinFormatterBounds();
    testResetRatePersistsValueAndReplacesTimer();
    testKillOwnedProcessWithBothSignals();
    testKillRejectsAnotherUsersProcess();
    testRootWarningPrecedesFinalConfirmation();
    testOwnerWarningCanCancelProtectedProcesses();
    testAboutPanelUsesReferenceOptionsAndMethodArguments();
    testPrintUsesTheTableSuperviewAsItsView();
    testExportBuildsFilteredRepresentationsBeforePanelAndWritesPlist();
    return PVFinish();
}
