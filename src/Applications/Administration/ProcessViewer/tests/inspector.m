#import <AppKit/AppKit.h>
#import "../Inspector.h"
#import "../InspectorLayout.h"
#import "test_support.h"

@protocol PVTestViewParent
- (void)removeSubview:(id)view;
@end

@interface PVTestProcess : NSObject {
    NSArray *_arguments;
    int _pid;
    int _parentPid;
    int _processGroupId;
    int _savedUserId;
}
- (id)initWithArguments:(NSArray *)arguments;
- (id)arguments;
- (int)processId;
- (int)parentProcessId;
- (int)processGroupId;
- (int)savedUserId;
- (id)tty;
- (id)objectForKey:(id)key;
@end

@implementation PVTestProcess
- (id)initWithArguments:(NSArray *)arguments
{
    self = [super init];
    if (self != nil) {
        _arguments = [arguments copy];
        _pid = 321;
        _parentPid = 123;
        _processGroupId = 456;
        _savedUserId = 789;
    }
    return self;
}
- (id)arguments { return _arguments; }
- (int)processId { return _pid; }
- (int)parentProcessId { return _parentPid; }
- (int)processGroupId { return _processGroupId; }
- (int)savedUserId { return _savedUserId; }
- (id)tty { return @"ttys004"; }
- (id)objectForKey:(id)key
{
    if ([key isEqual:@"RSIZE"])
        return @"128K";
    if ([key isEqual:@"VSIZE"])
        return @"1M";
    if ([key isEqual:@"TIME"])
        return @"00:00:02";
    return nil;
}
- (void)dealloc
{
    [_arguments release];
    [super dealloc];
}
@end

@interface PVTestTextField : NSObject {
    NSString *_stringValue;
    int _intValue;
}
- (id)stringValue;
- (int)intValue;
- (void)setStringValue:(NSString *)value;
- (void)setIntValue:(int)value;
@end

@implementation PVTestTextField
- (id)stringValue { return _stringValue; }
- (int)intValue { return _intValue; }
- (void)setStringValue:(NSString *)value
{
    [_stringValue release];
    _stringValue = [value copy];
}
- (void)setIntValue:(int)value { _intValue = value; }
- (void)dealloc
{
    [_stringValue release];
    [super dealloc];
}
@end

@interface PVTestReloadTable : NSObject {
    unsigned int _reloadCount;
}
- (void)reloadData;
- (unsigned int)reloadCount;
@end

@implementation PVTestReloadTable
- (void)reloadData { ++_reloadCount; }
- (unsigned int)reloadCount { return _reloadCount; }
@end

@interface PVTestView : NSObject {
    NSRect _frame;
    id _superview;
}
- (id)initWithFrame:(NSRect)frame;
- (NSRect)frame;
- (void)setFrame:(NSRect)frame;
- (void)setSuperview:(id)view;
- (void)removeFromSuperview;
@end

@implementation PVTestView
- (id)initWithFrame:(NSRect)frame
{
    self = [super init];
    if (self != nil)
        _frame = frame;
    return self;
}
- (NSRect)frame { return _frame; }
- (void)setFrame:(NSRect)frame { _frame = frame; }
- (void)setSuperview:(id)view { _superview = view; }
- (void)removeFromSuperview
{
    if (_superview != nil)
        [(id<PVTestViewParent>)_superview removeSubview:self];
    _superview = nil;
}
@end

@interface PVTestScreen : NSObject {
    NSRect _frame;
}
- (id)initWithFrame:(NSRect)frame;
- (NSRect)frame;
@end

@implementation PVTestScreen
- (id)initWithFrame:(NSRect)frame
{
    self = [super init];
    if (self != nil)
        _frame = frame;
    return self;
}
- (NSRect)frame { return _frame; }
@end

@interface PVTestWindow : NSObject {
    NSRect _frame;
    NSSize _minimumSize;
    id _screen;
    unsigned int _frameSetCount;
    unsigned int _minimumSizeSetCount;
}
- (id)initWithFrame:(NSRect)frame minimumSize:(NSSize)minimumSize screen:(id)screen;
- (NSRect)frame;
- (NSSize)minSize;
- (id)screen;
- (void)setMinSize:(NSSize)size;
- (void)setFrame:(NSRect)frame display:(BOOL)display;
- (unsigned int)frameSetCount;
- (unsigned int)minimumSizeSetCount;
@end

@implementation PVTestWindow
- (id)initWithFrame:(NSRect)frame minimumSize:(NSSize)minimumSize screen:(id)screen
{
    self = [super init];
    if (self != nil) {
        _frame = frame;
        _minimumSize = minimumSize;
        _screen = [screen retain];
    }
    return self;
}
- (NSRect)frame { return _frame; }
- (NSSize)minSize { return _minimumSize; }
- (id)screen { return _screen; }
- (void)setMinSize:(NSSize)size
{
    _minimumSize = size;
    ++_minimumSizeSetCount;
}
- (void)setFrame:(NSRect)frame display:(BOOL)display
{
    _frame = frame;
    ++_frameSetCount;
}
- (unsigned int)frameSetCount { return _frameSetCount; }
- (unsigned int)minimumSizeSetCount { return _minimumSizeSetCount; }
- (void)dealloc
{
    [_screen release];
    [super dealloc];
}
@end

@interface PVTestSplitView : NSObject {
    NSRect _frame;
    NSRect _bounds;
    float _dividerThickness;
    NSMutableArray *_subviews;
    unsigned int _adjustCount;
    id _window;
}
- (id)initWithFrame:(NSRect)frame dividerThickness:(float)thickness;
- (NSRect)frame;
- (NSRect)bounds;
- (float)dividerThickness;
- (NSArray *)subviews;
- (void)addSubview:(id)view;
- (void)removeSubview:(id)view;
- (void)adjustSubviews;
- (unsigned int)adjustCount;
- (id)window;
- (void)setWindow:(id)window;
@end

@implementation PVTestSplitView
- (id)initWithFrame:(NSRect)frame dividerThickness:(float)thickness
{
    self = [super init];
    if (self != nil) {
        _frame = frame;
        _bounds = NSMakeRect(0.0, 0.0, frame.size.width, frame.size.height);
        _dividerThickness = thickness;
        _subviews = [[NSMutableArray alloc] init];
    }
    return self;
}
- (NSRect)frame { return _frame; }
- (NSRect)bounds { return _bounds; }
- (float)dividerThickness { return _dividerThickness; }
- (NSArray *)subviews { return _subviews; }
- (void)addSubview:(id)view
{
    if (![_subviews containsObject:view]) {
        [_subviews addObject:view];
        [(PVTestView *)view setSuperview:self];
    }
}
- (void)removeSubview:(id)view
{
    [_subviews removeObjectIdenticalTo:view];
}
- (void)adjustSubviews { ++_adjustCount; }
- (unsigned int)adjustCount { return _adjustCount; }
- (id)window { return _window; }
- (void)setWindow:(id)window { _window = window; }
- (void)dealloc
{
    [_subviews release];
    [super dealloc];
}
@end

@interface PVTestTabViewItem : NSObject {
    id _view;
}
- (id)initWithView:(id)view;
- (id)view;
- (void)setView:(id)view;
@end

@implementation PVTestTabViewItem
- (id)initWithView:(id)view
{
    self = [super init];
    if (self != nil)
        _view = [view retain];
    return self;
}
- (id)view { return _view; }
- (void)setView:(id)view
{
    [view retain];
    [_view release];
    _view = view;
}
- (void)dealloc
{
    [_view release];
    [super dealloc];
}
@end

@interface PVTestTabView : NSObject {
    id _selectedItem;
    int _selectedIndex;
}
- (id)initWithSelectedItem:(id)item index:(int)index;
- (id)selectedTabViewItem;
- (int)indexOfTabViewItem:(id)item;
- (void)setSelectedItem:(id)item index:(int)index;
@end

@implementation PVTestTabView
- (id)initWithSelectedItem:(id)item index:(int)index
{
    self = [super init];
    if (self != nil) {
        _selectedItem = [item retain];
        _selectedIndex = index;
    }
    return self;
}
- (id)selectedTabViewItem { return _selectedItem; }
- (int)indexOfTabViewItem:(id)item
{
    return item == _selectedItem ? _selectedIndex : -1;
}
- (void)setSelectedItem:(id)item index:(int)index
{
    [item retain];
    [_selectedItem release];
    _selectedItem = item;
    _selectedIndex = index;
}
- (void)dealloc
{
    [_selectedItem release];
    [super dealloc];
}
@end

@interface PVTestableInspector : Inspector
- (void)setProcess:(id)process;
- (float)minimumMainContainerHeight;
- (void)setVisibilityFixtureSplitView:(id)view tabContainer:(id)container
                              window:(id)window
                   minimumMainHeight:(float)mainHeight
                    minimumTabHeight:(float)tabHeight;
- (void)setTabFixture:(id)view pidView:(id)pid statsView:(id)stats
             argsView:(id)args invalidSelectionView:(id)invalid;
- (void)setDetailsFixturePathField:(id)path argumentsTable:(id)table
                           pidField:(id)pid parentField:(id)parent
                   processGroupField:(id)group savedUidField:(id)uid
                        terminalField:(id)terminal realMemoryField:(id)real
                    virtualMemoryField:(id)virtual timeField:(id)time
                invalidSelectionText:(id)invalidText;
@end

@implementation PVTestableInspector
- (float)minimumMainContainerHeight { return _minMainContainerHeight; }
- (void)setProcess:(id)process
{
    [(id)_process release];
    _process = [process retain];
}
- (void)setVisibilityFixtureSplitView:(id)view tabContainer:(id)container
                              window:(id)window
                   minimumMainHeight:(float)mainHeight
                    minimumTabHeight:(float)tabHeight
{
    splitView = (NSSplitView *)view;
    tabContainer = (NSView *)container;
    [(PVTestSplitView *)view setWindow:window];
    _minMainContainerHeight = mainHeight;
    _minTabContainerHeight = tabHeight;
}
- (void)setTabFixture:(id)view pidView:(id)pid statsView:(id)stats
             argsView:(id)args invalidSelectionView:(id)invalid
{
    tabView = (NSTabView *)view;
    pidView = (NSView *)pid;
    statsView = (NSView *)stats;
    argsView = (NSView *)args;
    invalidSelectionView = (NSView *)invalid;
}
- (void)setDetailsFixturePathField:(id)path argumentsTable:(id)table
                           pidField:(id)pid parentField:(id)parent
                   processGroupField:(id)group savedUidField:(id)uid
                        terminalField:(id)terminal realMemoryField:(id)real
                    virtualMemoryField:(id)virtual timeField:(id)time
                invalidSelectionText:(id)invalidText
{
    pathField = (NSTextField *)path;
    argumentsTable = (NSTableView *)table;
    pidField = (NSTextField *)pid;
    parentField = (NSTextField *)parent;
    processGroupField = (NSTextField *)group;
    savedUidField = (NSTextField *)uid;
    terminalField = (NSTextField *)terminal;
    realMemoryField = (NSTextField *)real;
    virtualMemoryField = (NSTextField *)virtual;
    timeField = (NSTextField *)time;
    invalidSelectionText = (NSTextField *)invalidText;
}
- (void)dealloc
{
    [(id)_process release];
    [super dealloc];
}
@end

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSArray *arguments = [NSArray arrayWithObjects:@"/Applications/Worker.app/Worker",
        @"--mode", @"background", nil];
    PVTestProcess *process = [[PVTestProcess alloc] initWithArguments:arguments];
    PVTestProcess *noArguments = [[PVTestProcess alloc] initWithArguments:[NSArray array]];
    PVTestProcess *onlyPath = [[PVTestProcess alloc]
        initWithArguments:[NSArray arrayWithObject:@"/bin/true"]];
    PVTestableInspector *inspector = [PVTestableInspector alloc];

    [inspector setProcess:process];
    PV_CHECK([inspector numberOfRowsInTableView:nil] == 2);
    PV_CHECK_OBJECTS_EQUAL([inspector tableView:nil objectValueForTableColumn:nil row:0],
                           @"--mode");
    PV_CHECK_OBJECTS_EQUAL([inspector tableView:nil objectValueForTableColumn:nil row:1],
                           @"background");
    PV_CHECK_OBJECTS_EQUAL([inspector tableView:nil objectValueForTableColumn:nil row:-1],
                           @"/Applications/Worker.app/Worker");
    {
        BOOL raised = NO;
        NS_DURING
            [inspector tableView:nil objectValueForTableColumn:nil row:2];
        NS_HANDLER
            raised = YES;
        NS_ENDHANDLER
        PV_CHECK(raised);
    }
    [inspector setProcess:noArguments];
    PV_CHECK([inspector numberOfRowsInTableView:nil] == 0);
    {
        BOOL raised = NO;
        NS_DURING
            [inspector tableView:nil objectValueForTableColumn:nil row:0];
        NS_HANDLER
            raised = YES;
        NS_ENDHANDLER
        PV_CHECK(raised);
    }
    [inspector setProcess:onlyPath];
    PV_CHECK([inspector numberOfRowsInTableView:nil] == 0);

    {
        PVTestView *mainView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 170.0)];
        PVTestSplitView *splitView = [[PVTestSplitView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 340.0)
            dividerThickness:2.0];

        [splitView addSubview:mainView];
        [inspector setSplitView:(NSSplitView *)splitView];
        PV_CHECK([inspector minimumMainContainerHeight] == 170.0);
        [splitView release];
        [mainView release];
    }

    {
        PVTestView *oldView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestView *pidView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestView *statsView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestView *argsView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestView *invalidView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestTabViewItem *item = [[PVTestTabViewItem alloc] initWithView:oldView];
        PVTestTabView *tabView = [[PVTestTabView alloc]
            initWithSelectedItem:item index:1];

        [inspector setTabFixture:tabView pidView:pidView statsView:statsView
                        argsView:argsView invalidSelectionView:invalidView];
        [inspector _setCurrentView:YES];
        PV_CHECK([item view] == statsView);
        [tabView setSelectedItem:item index:3];
        [inspector _setCurrentView:YES];
        PV_CHECK([item view] == statsView);
        [inspector _setCurrentView:NO];
        PV_CHECK([item view] == invalidView);
        [tabView setSelectedItem:nil index:0];
        [inspector _setCurrentView:YES];
        PV_CHECK([item view] == invalidView);
        [tabView setSelectedItem:item index:0];
        [inspector setTabFixture:tabView pidView:pidView statsView:statsView
                        argsView:argsView invalidSelectionView:nil];
        [inspector _setCurrentView:NO];
        PV_CHECK([item view] == invalidView);
        [inspector setTabFixture:nil pidView:nil statsView:nil argsView:nil
            invalidSelectionView:nil];
        [inspector _setCurrentView:YES];
        PV_CHECK([item view] == invalidView);

        [tabView release];
        [item release];
        [invalidView release];
        [argsView release];
        [statsView release];
        [pidView release];
        [oldView release];
    }

    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        id previousVisibility = [[defaults objectForKey:@"InspectorVisible"] retain];
        NSRect actualWindowFrame;
        NSSize actualMinimumSize;
        PVTestView *mainView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 250.0)];
        PVTestView *tabContainer = [[PVTestView alloc]
            initWithFrame:NSMakeRect(12.0, 8.0, 300.0, 90.0)];
        PVTestScreen *screen = [[PVTestScreen alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 250.0)];
        PVTestWindow *window = [[PVTestWindow alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 250.0)
            minimumSize:NSMakeSize(320.0, 150.0) screen:screen];
        PVTestSplitView *splitView = [[PVTestSplitView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 250.0)
            dividerThickness:2.0];

        [splitView addSubview:mainView];
        [inspector setVisibilityFixtureSplitView:splitView
                                    tabContainer:tabContainer
                                          window:window
                               minimumMainHeight:150.0
                                minimumTabHeight:80.0];
        [inspector setVisible:YES];
        PV_CHECK([inspector isVisible]);
        PV_CHECK([[splitView subviews] count] == 2);
        PV_CHECK([mainView frame].size.height == 250.0);
        PV_CHECK([tabContainer frame].origin.x == 12.0);
        PV_CHECK([tabContainer frame].origin.y == 8.0);
        PV_CHECK([tabContainer frame].size.width == 300.0);
        PV_CHECK([tabContainer frame].size.height == 90.0);
        actualWindowFrame = [window frame];
        actualMinimumSize = [window minSize];
        PV_CHECK(actualWindowFrame.origin.y == 10.0);
        PV_CHECK(actualWindowFrame.size.height == 240.0);
        PV_CHECK(actualMinimumSize.height == 232.0);
        PV_CHECK([defaults boolForKey:@"InspectorVisible"]);
        PV_CHECK([window frameSetCount] == 1);
        PV_CHECK([window minimumSizeSetCount] == 1);

        [inspector setVisible:YES];
        PV_CHECK([window frameSetCount] == 1);
        [inspector setVisible:NO];
        PV_CHECK(![inspector isVisible]);
        PV_CHECK([[splitView subviews] count] == 1);
        actualWindowFrame = [window frame];
        actualMinimumSize = [window minSize];
        PV_CHECK(actualWindowFrame.origin.y == 102.0);
        PV_CHECK(actualWindowFrame.size.height == 150.0);
        PV_CHECK(actualMinimumSize.height == 150.0);
        PV_CHECK(![defaults boolForKey:@"InspectorVisible"]);
        PV_CHECK([window frameSetCount] == 2);

        [defaults setBool:YES forKey:@"InspectorVisible"];
        [inspector awakeFromNib];
        PV_CHECK([inspector isVisible]);
        PV_CHECK([window frameSetCount] == 3);
        [inspector setVisible:NO];
        PV_CHECK([window frameSetCount] == 4);

        [inspector _setProcess:(Process *)process];
        [inspector setVisible:YES];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"ProcessBecameInvalidNotification"
                          object:noArguments];
        PV_CHECK([inspector isVisible]);
        [inspector _setProcess:(Process *)noArguments];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"ProcessBecameInvalidNotification"
                          object:process];
        PV_CHECK([inspector isVisible]);
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"ProcessBecameInvalidNotification"
                          object:noArguments];
        PV_CHECK(![inspector isVisible]);
        [inspector _setProcess:nil];

        if (previousVisibility != nil)
            [defaults setObject:previousVisibility forKey:@"InspectorVisible"];
        else
            [defaults removeObjectForKey:@"InspectorVisible"];
        [previousVisibility release];
        [splitView release];
        [window release];
        [screen release];
        [tabContainer release];
        [mainView release];
    }

    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        id previousVisibility = [[defaults objectForKey:@"InspectorVisible"] retain];
        PVTestView *mainView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 250.0)];
        PVTestView *container = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 90.0)];
        PVTestScreen *screen = [[PVTestScreen alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 600.0)];
        PVTestWindow *window = [[PVTestWindow alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 250.0)
            minimumSize:NSMakeSize(320.0, 150.0) screen:screen];
        PVTestView *oldView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestView *pidView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestView *statsView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestView *argsView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestView *invalidView = [[PVTestView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
        PVTestTabViewItem *item = [[PVTestTabViewItem alloc] initWithView:oldView];
        PVTestTabView *tabView = [[PVTestTabView alloc]
            initWithSelectedItem:item index:0];
        PVTestSplitView *splitView = [[PVTestSplitView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 250.0)
            dividerThickness:2.0];
        PVTestTextField *pathField = [[PVTestTextField alloc] init];
        PVTestTextField *pidField = [[PVTestTextField alloc] init];
        PVTestTextField *parentField = [[PVTestTextField alloc] init];
        PVTestTextField *groupField = [[PVTestTextField alloc] init];
        PVTestTextField *uidField = [[PVTestTextField alloc] init];
        PVTestTextField *terminalField = [[PVTestTextField alloc] init];
        PVTestTextField *realMemoryField = [[PVTestTextField alloc] init];
        PVTestTextField *virtualMemoryField = [[PVTestTextField alloc] init];
        PVTestTextField *timeField = [[PVTestTextField alloc] init];
        PVTestTextField *invalidText = [[PVTestTextField alloc] init];
        PVTestReloadTable *argumentsTable = [[PVTestReloadTable alloc] init];

        [splitView addSubview:mainView];
        [inspector setVisibilityFixtureSplitView:splitView tabContainer:container
                                          window:window
                               minimumMainHeight:150.0 minimumTabHeight:80.0];
        [inspector setTabFixture:tabView pidView:pidView statsView:statsView
                        argsView:argsView invalidSelectionView:invalidView];
        [inspector setDetailsFixturePathField:pathField argumentsTable:argumentsTable
            pidField:pidField parentField:parentField processGroupField:groupField
            savedUidField:uidField terminalField:terminalField
            realMemoryField:realMemoryField virtualMemoryField:virtualMemoryField
            timeField:timeField invalidSelectionText:invalidText];

        [inspector showInfoForProcess:(Process *)process];
        PV_CHECK([inspector isVisible]);
        PV_CHECK([item view] == pidView);
        PV_CHECK_OBJECTS_EQUAL([pathField stringValue],
            @"/Applications/Worker.app/Worker");
        PV_CHECK([argumentsTable reloadCount] == 1);
        PV_CHECK([inspector numberOfRowsInTableView:nil] == 2);
        PV_CHECK_OBJECTS_EQUAL([inspector tableView:nil
            objectValueForTableColumn:nil row:1], @"background");
        PV_CHECK([pidField intValue] == 321);
        PV_CHECK([parentField intValue] == 123);
        PV_CHECK([groupField intValue] == 456);
        PV_CHECK([uidField intValue] == 789);
        PV_CHECK_OBJECTS_EQUAL([terminalField stringValue], @"ttys004");
        PV_CHECK_OBJECTS_EQUAL([realMemoryField stringValue], @"128K");
        PV_CHECK_OBJECTS_EQUAL([virtualMemoryField stringValue], @"1M");
        PV_CHECK_OBJECTS_EQUAL([timeField stringValue], @"00:00:02");

        [inspector showInfoForProcess:(Process *)noArguments];
        PV_CHECK_OBJECTS_EQUAL([invalidText stringValue], @"No processes selected");
        PV_CHECK([item view] == invalidView);
        PV_CHECK([inspector numberOfRowsInTableView:nil] == 0);
        [inspector showInfoForMultipleSelection];
        PV_CHECK_OBJECTS_EQUAL([invalidText stringValue],
            @"Multiple processes selected");
        PV_CHECK([item view] == invalidView);
        [inspector showInfoForProcess:nil];
        PV_CHECK_OBJECTS_EQUAL([invalidText stringValue], @"No processes selected");
        [inspector setVisible:NO];

        if (previousVisibility != nil)
            [defaults setObject:previousVisibility forKey:@"InspectorVisible"];
        else
            [defaults removeObjectForKey:@"InspectorVisible"];
        [previousVisibility release];
        [inspector setTabFixture:nil pidView:nil statsView:nil argsView:nil
            invalidSelectionView:nil];
        [inspector setDetailsFixturePathField:nil argumentsTable:nil pidField:nil
            parentField:nil processGroupField:nil savedUidField:nil terminalField:nil
            realMemoryField:nil virtualMemoryField:nil timeField:nil
            invalidSelectionText:nil];
        [splitView release];
        [window release];
        [screen release];
        [argumentsTable release];
        [timeField release];
        [virtualMemoryField release];
        [realMemoryField release];
        [terminalField release];
        [uidField release];
        [groupField release];
        [parentField release];
        [pidField release];
        [pathField release];
        [tabView release];
        [item release];
        [invalidView release];
        [argsView release];
        [statsView release];
        [pidView release];
        [oldView release];
        [container release];
        [mainView release];
    }

    {
        NSRect originalTabFrame = NSMakeRect(12.0, 8.0, 300.0, 92.0);
        NSRect splitFrame = NSMakeRect(40.0, 50.0, 480.0, 320.0);
        NSRect splitBounds = NSMakeRect(0.0, 0.0, 460.0, 320.0);
        NSRect preparedFrame = PVInspectorInitialTabContainerFrame(
            originalTabFrame, splitBounds);
        PV_CHECK(splitFrame.size.width == 480.0);
        PV_CHECK(preparedFrame.origin.x == 0.0);
        PV_CHECK(preparedFrame.origin.y == 0.0);
        PV_CHECK(preparedFrame.size.width == 460.0);
        PV_CHECK(preparedFrame.size.height == 92.0);

        {
            float mainHeight = 200.0;
            float tabHeight = 100.0;
            PVInspectorResizeSubviewHeights(&mainHeight, &tabHeight, 330.0,
                                             2.0, 150.0, 80.0);
            PV_CHECK(mainHeight == 228.0);
            PV_CHECK(tabHeight == 100.0);
            mainHeight = 200.0;
            tabHeight = 100.0;
            PVInspectorResizeSubviewHeights(&mainHeight, &tabHeight, 242.0,
                                             2.0, 150.0, 80.0);
            PV_CHECK(mainHeight == 150.0);
            PV_CHECK(tabHeight == 90.0);
            mainHeight = 200.0;
            tabHeight = 100.0;
            PVInspectorResizeSubviewHeights(&mainHeight, &tabHeight, 232.0,
                                             2.0, 150.0, 80.0);
            PV_CHECK(mainHeight == 150.0);
            PV_CHECK(tabHeight == 80.0);
            mainHeight = 200.0;
            tabHeight = 100.0;
            PVInspectorResizeSubviewHeights(&mainHeight, &tabHeight, 220.0,
                                             2.0, 150.0, 80.0);
            PV_CHECK(mainHeight == 150.0);
            PV_CHECK(tabHeight == 80.0);
            mainHeight = 100.0;
            tabHeight = 100.0;
            PVInspectorResizeSubviewHeights(&mainHeight, &tabHeight, 202.0,
                                             2.0, 150.0, 80.0);
            PV_CHECK(mainHeight == 150.0);
            PV_CHECK(tabHeight == 80.0);
        }
    }

    [inspector release];
    [process release];
    [noArguments release];
    [onlyPath release];
    [pool release];
    return PVFinish();
}
