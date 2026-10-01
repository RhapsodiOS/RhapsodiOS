#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "Inspector.h"
#import "InspectorLayout.h"
#import "Process.h"

static NSString * const _InspectorVisibleDefaultKey = @"InspectorVisible";
static NSString * const _SelectedInspectorTabDefaultKey = @"SelectedInspectorTab";
static NSString * const ProcessBecameInvalidNotification =
    @"ProcessBecameInvalidNotification";
static NSString * const _TabTitles[] = {
    @"Process ID", @"Statistics", @"Path & Arguments", nil
};

#define PVInspectorString(key) [[NSBundle mainBundle] localizedStringForKey:(key) value:(key) table:nil]

@implementation Inspector

- (void)awakeFromNib
{
    if ([[NSUserDefaults standardUserDefaults]
            boolForKey:_InspectorVisibleDefaultKey])
        [self setVisible:YES];
}

- (void)setSplitView:(NSSplitView *)view
{
    NSArray *subviews;
    NSRect mainFrame;
    NSRect initialFrame;
    NSRect splitFrame;

    if (splitView == view)
        return;
    [splitView removeFromSuperview];
    splitView = [view retain];
    initialFrame = [splitView frame];
    subviews = [splitView subviews];
    mainFrame = [[subviews objectAtIndex:0] frame];
    splitFrame = [splitView frame];
    _minMainContainerHeight = initialFrame.size.height + mainFrame.size.height -
        splitFrame.size.height;
}

- (void)_loadInspectorNib
{
    NSArray *views;
    NSArray *labels;
    NSArray *identifiers;
    NSRect tabFrame;
    NSRect splitBounds;
    NSRect splitFrame;
    unsigned int index;
    unsigned int selectedIndex;

    if (![NSBundle loadNibNamed:@"inspector" owner:self]) {
        NSRunAlertPanel(PVInspectorString(@"Inspector"),
                        PVInspectorString(@"Unable to load inspector.nib"),
                        PVInspectorString(@"OK"), nil, nil);
        return;
    }
    tabFrame = [tabContainer frame];
    splitBounds = [splitView bounds];
    splitFrame = [splitView frame];
    (void)splitFrame;
    tabFrame = PVInspectorInitialTabContainerFrame(tabFrame, splitBounds);
    [tabContainer setFrame:tabFrame];
    _minTabContainerHeight = tabFrame.size.height;

    [argumentsTable setDataSource:self];
    [argumentsTable setDelegate:self];
    [tabContainer removeFromSuperview];
    [invalidSelectionView removeFromSuperview];
    [pidView removeFromSuperview];
    [statsView removeFromSuperview];
    [argsView removeFromSuperview];

    views = [NSArray arrayWithObjects:pidView, statsView, argsView, nil];
    labels = [NSArray arrayWithObjects:
        PVInspectorString(_TabTitles[0]), PVInspectorString(_TabTitles[1]),
        PVInspectorString(_TabTitles[2]), nil];
    identifiers = [NSArray arrayWithObjects:@"Process ID", @"Statistics",
        @"Path & Arguments", nil];
    for (index = 0; index < [views count]; ++index) {
        NSTabViewItem *item = [[NSTabViewItem alloc]
            initWithIdentifier:[identifiers objectAtIndex:index]];
        [item setLabel:[labels objectAtIndex:index]];
        [item setView:[views objectAtIndex:index]];
        [tabView addTabViewItem:item];
        [item release];
    }
    selectedIndex = [[[NSUserDefaults standardUserDefaults]
        objectForKey:_SelectedInspectorTabDefaultKey] unsignedIntValue];
    if (selectedIndex < [tabView numberOfTabViewItems])
        [tabView selectTabViewItemAtIndex:selectedIndex];
}

- (void)dealloc
{
    [invalidSelectionView release];
    [pidView release];
    [statsView release];
    [argsView release];
    [super dealloc];
}

- (void)_setCurrentView:(BOOL)valid
{
    NSTabViewItem *item;
    NSArray *views;
    int index;
    if (tabView == nil)
        return;
    item = [tabView selectedTabViewItem];
    if (item == nil)
        return;
    if (valid) {
        views = [NSArray arrayWithObjects:pidView, statsView, argsView, nil];
        index = [tabView indexOfTabViewItem:item];
        if (index >= 0 && index < (int)[views count])
            [item setView:[views objectAtIndex:index]];
    } else if (invalidSelectionView != nil) {
        [item setView:invalidSelectionView];
    }
}

- (void)setVisible:(BOOL)visible
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSWindow *window;
    NSScreen *screen;
    NSRect windowFrame;
    NSRect tabFrame;
    NSRect screenFrame;
    NSSize minimumSize;
    float divider;
    float amount;

    visible = visible ? YES : NO;
    if (visible == _isVisible)
        return;
    window = [splitView window];
    windowFrame = [window frame];
    minimumSize = [window minSize];
    if (tabContainer == nil)
        [self _loadInspectorNib];
    if (tabContainer == nil)
        return;

    tabFrame = [tabContainer frame];
    divider = [splitView dividerThickness];
    amount = tabFrame.size.height + divider;

    if (visible) {
        screen = [window screen];
        [splitView addSubview:tabContainer];
        windowFrame.size.height += amount;
        windowFrame.origin.y -= amount;
        minimumSize.height += _minTabContainerHeight + divider;
        if (screen != nil) {
            screenFrame = [screen frame];
            screenFrame.origin.y += 10.0;
            if (!NSPointInRect(windowFrame.origin, screenFrame)) {
                windowFrame.size.height +=
                    windowFrame.origin.y - screenFrame.origin.y;
                windowFrame.origin.y = screenFrame.origin.y;
            }
        }
        _isVisible = YES;
    } else {
        windowFrame.size.height -= amount;
        windowFrame.origin.y += amount;
        minimumSize.height -= _minTabContainerHeight + divider;
        [tabContainer removeFromSuperview];
        _isVisible = NO;
    }
    if (windowFrame.size.height < minimumSize.height)
        windowFrame.size.height = minimumSize.height;
    [window setMinSize:minimumSize];
    [window setFrame:windowFrame display:YES];
    [defaults setBool:_isVisible forKey:_InspectorVisibleDefaultKey];
}

- (BOOL)isVisible
{
    return _isVisible;
}

- (void)showInfoForProcess:(Process *)process
{
    NSArray *arguments = [process arguments];
    if (process == nil || arguments == nil || [arguments count] == 0) {
        [self showInfoForNoSelection];
        return;
    }

    [self _setProcess:process];
    [self _setCurrentView:YES];
    [self setVisible:YES];
    [pathField setStringValue:[arguments objectAtIndex:0]];
    [argumentsTable reloadData];
    [pidField setIntValue:[process processId]];
    [parentField setIntValue:[process parentProcessId]];
    [processGroupField setIntValue:[process processGroupId]];
    [savedUidField setIntValue:[process savedUserId]];
    [terminalField setStringValue:[process tty]];
    [realMemoryField setStringValue:[process objectForKey:@"RSIZE"]];
    [virtualMemoryField setStringValue:[process objectForKey:@"VSIZE"]];
    [timeField setStringValue:[process objectForKey:@"TIME"]];
}

- (void)showInfoForNoSelection
{
    [self _setProcess:nil];
    [self _setCurrentView:NO];
    [invalidSelectionText setStringValue:PVInspectorString(@"No processes selected")];
}

- (void)showInfoForMultipleSelection
{
    [self _setProcess:nil];
    [self _setCurrentView:NO];
    [invalidSelectionText setStringValue:PVInspectorString(@"Multiple processes selected")];
}

- (void)_setProcess:(Process *)process
{
    if (_process == process)
        return;
    if (_process != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
            name:ProcessBecameInvalidNotification object:_process];
        [_process release];
    }
    _process = [process retain];
    if (_process != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(_processTanked:) name:ProcessBecameInvalidNotification
            object:_process];
    }
}

- (void)_processTanked:(NSNotification *)notification
{
    [self setVisible:NO];
}

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
    unsigned int count = [[_process arguments] count];
    return count > 0 ? (int)count - 1 : 0;
}

- (id)tableView:(NSTableView *)tableView
 objectValueForTableColumn:(NSTableColumn *)column
            row:(int)row
{
    NSArray *arguments = [_process arguments];
    return [arguments objectAtIndex:row + 1];
}

- (void)tabView:(NSTabView *)view didSelectTabViewItem:(NSTabViewItem *)item
{
    int index = [view indexOfTabViewItem:item];
    if (index >= 0) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:index]
                                                  forKey:_SelectedInspectorTabDefaultKey];
    }
}

- (void)splitView:(NSSplitView *)sender constrainMinCoordinate:(float *)minimum
         maxCoordinate:(float *)maximum ofSubviewAt:(int)offset
{
    if (offset == 0) {
        NSRect splitFrame = [sender frame];
        *minimum += _minMainContainerHeight;
        *maximum = splitFrame.size.height - _minTabContainerHeight -
            [sender dividerThickness];
    }
}

- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
    NSArray *subviews = [sender subviews];
    NSRect splitFrame;
    float heights[2];
    float minimums[2];
    float y;
    float divider;
    unsigned int index;

    if ([subviews count] != 2) {
        [sender adjustSubviews];
        return;
    }

    splitFrame = [sender frame];
    heights[0] = [[subviews objectAtIndex:0] frame].size.height;
    heights[1] = [[subviews objectAtIndex:1] frame].size.height;
    minimums[0] = [subviews objectAtIndex:0] == tabContainer ?
        _minTabContainerHeight : _minMainContainerHeight;
    minimums[1] = [subviews objectAtIndex:1] == tabContainer ?
        _minTabContainerHeight : _minMainContainerHeight;
    (void)oldSize;
    divider = [sender dividerThickness];
    PVInspectorResizeSubviewHeights(&heights[0], &heights[1],
                                    splitFrame.size.height, divider,
                                    minimums[0], minimums[1]);
    y = 0.0;
    for (index = 0; index < 2; ++index) {
        NSView *subview = [subviews objectAtIndex:index];
        NSRect subviewFrame = NSMakeRect(0.0, y, splitFrame.size.width,
                                         heights[index]);
        [subview setFrame:subviewFrame];
        y += heights[index] + divider;
    }
}

@end
