#import <AppKit/AppKit.h>
#import "Process.h"
#import "ProcessType.h"
#import "ProcessTableView.h"
#import "Inspector.h"

@interface ProcessControl : NSResponder {
    ProcessTableView *processTable;
    NSButton *sortOrderButton;
    NSTextField *filterText;
    NSPopUpButton *typePopup;
    NSTextField *rateField;
    NSTextField *countField;
    NSTimer *timer;
    NSArray *allColumns;
    NSMutableArray *fieldNames;
    NSMutableArray *filteredProcesses;
    NSMutableArray *allProcesses;
    NSDictionary *optionsDictionary;
    NSButton *moreInfoSwitch;
    Inspector *inspector;
    NSArray *processTypes;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (void)assignActions;
- (void)bumpRate:(id)sender;
- (void)changeSortOrder:(id)sender;
- (void)controlTextDidChange:(NSNotification *)notification;
- (void)dealloc;
- (void)exportProcessList:(id)sender;
- (void)getProcesses:(id)sender;
- (void)hideColumn:(id)sender;
- (id)init;
- (void)killProcessWithConfirmation:(id)sender;
- (void)killProcesses:(id)sender;
- (int)numberOfRowsInTableView:(NSTableView *)tableView;
- (void)print:(id)sender;
- (void)refilter:(id)sender;
- (void)resetRate:(id)sender;
- (void)resort:(id)sender;
- (void)setShowType:(id)sender;
- (BOOL)shouldShowProcess:(Process *)process;
- (void)showAboutPanel:(id)sender;
- (void)showAllColumns:(id)sender;
- (void)showMoreInfoAboutSelection:(id)sender;
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(int)row;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (void)toggleMoreInfo:(id)sender;
- (void)updateForSortChange:(BOOL)sortChange filterChange:(BOOL)filterChange;
- (void)updateRate;
- (void)updateRate;
- (BOOL)validateMenuItem:(id)item;
- (void)windowDidResize:(NSNotification *)notification;
- (BOOL)windowShouldClose:(id)sender;
@end

