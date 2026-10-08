#ifndef TERMINAL_PROCESS_MONITOR_CONTROLLER_H
#define TERMINAL_PROCESS_MONITOR_CONTROLLER_H

#import <Foundation/NSObject.h>
#import "Emulation.h"

@class NSMutableArray;
@class NSScrollView;
@class NSButtonCell;
@class NSMatrix;
@class NSTableView;
@class NSTextField;

@interface ProcessMonitorController : NSObject
{
    NSTableView *cleanTableView;
    NSButtonCell *runningCleanCheck;
    NSButtonCell *addButton;
    NSButtonCell *removeButton;
    NSTextField *newCleanField;
    NSButtonCell *monitorCheck;
    NSMatrix *checkMatrix;
    NSScrollView *cleanScrollView;
    NSMutableArray *cleanCommands;
}
- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults;
- (void)lastVisible:(id)sender;
- (void)revert;
- (id)setDefault;
- (void)suggest;
- (void)setStruct:(TerminalEmulationDefaults *)defaults;
- (void)writeCommands;
- (void)promulgateSettings;
- (void)enablementChanged:(id)sender;
- (void)runningBackgroundChanged:(id)sender;
- (void)showDefault:(char)useDefault;
- (void)displayMonitor:(char)monitor shellsClean:(char)shellsClean
    runningBkgndClean:(char)runningBkgndClean fastAudits:(char)fastAudits
    cleanCommands:(const char **)commands;
- (void)firstVisible:(id)sender;
- (void)add:(id)sender;
- (void)remove:(id)sender;
- (void)tableViewSelectionDidChange:(id)notification;
- (void)controlTextDidChange:(id)notification;
- (int)numberOfRowsInTableView:(id)tableView;
- (id)tableView:(id)tableView objectValueForTableColumn:(id)column row:(int)row;
- (void)tableView:(id)tableView setObjectValue:(id)value
    forTableColumn:(id)column row:(int)row;
@end

#endif
