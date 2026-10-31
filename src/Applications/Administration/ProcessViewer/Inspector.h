#import <AppKit/AppKit.h>

@class Process;

@interface Inspector : NSObject {
    Process *_process;
    NSSplitView *splitView;
    NSView *tabContainer;
    NSView *invalidSelectionView;
    NSTabView *tabView;
    NSView *pidView;
    NSView *statsView;
    NSView *argsView;
    NSTextField *invalidSelectionText;
    NSTextField *pathField;
    NSTableView *argumentsTable;
    NSTextField *pidField;
    NSTextField *parentField;
    NSTextField *processGroupField;
    NSTextField *savedUidField;
    NSTextField *terminalField;
    NSTextField *realMemoryField;
    NSTextField *virtualMemoryField;
    NSTextField *timeField;
    BOOL _isVisible;
    float _minTabContainerHeight;
    float _minMainContainerHeight;
}
- (void)_loadInspectorNib;
- (void)_processTanked:(NSNotification *)notification;
- (void)_setCurrentView:(BOOL)valid;
- (void)_setProcess:(Process *)process;
- (void)awakeFromNib;
- (void)dealloc;
- (BOOL)isVisible;
- (int)numberOfRowsInTableView:(NSTableView *)tableView;
- (void)setSplitView:(NSSplitView *)view;
- (void)setVisible:(BOOL)visible;
- (void)showInfoForMultipleSelection;
- (void)showInfoForNoSelection;
- (void)showInfoForProcess:(Process *)process;
- (void)splitView:(NSSplitView *)splitView constrainMinCoordinate:(float *)min maxCoordinate:(float *)max ofSubviewAt:(int)offset;
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize;
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item;
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(int)row;
@end
