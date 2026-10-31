#ifndef TERMINAL_PREFERENCES_H
#define TERMINAL_PREFERENCES_H

#import <Foundation/NSObject.h>
#import <Foundation/NSNotification.h>

@interface Preferences : NSObject
{
    id container;
    id paneSelector;
    id processMonitorCntl;
    id processMonitorPane;
    id titleBarCntl;
    id titleBarPane;
    id shellCntl;
    id shellPane;
    id miscCntl;
    id miscPane;
    id emulationCntl;
    id emulationPane;
    id windowCntl;
    id windowPane;
    id startupCntl;
    id startupPane;
    id revertButton;
    id okButton;
    id setDefaultButton;
    id suggestButton;
    id showDefaultButton;
    id window;
    id buttonMatrix;
    id textAttrCntl;
    id textAttrPane;
    id controllers[8];
    id installedController;
    id subPanes[8];
    id currentTerminal;
    id installedPane;
    char shouldEnableOKIfPossible;
}
- (id)init;
- (void)setUpButtons:(int)flags;
- (void)revert:(id)sender;
- (void)setDefaultX:(id)sender;
- (void)ok:(id)sender;
- (void)suggest:(id)sender;
- (void)showDefault:(BOOL)show;
- (void)setCurrentTerminal:(id)terminal;
- (void)terminalDidBecomeMain:(id)terminal;
- (void)terminalDidResignMain:(id)terminal;
- (id)okButton;
- (id)currentTerminal;
- (void)doFlush;
- (void)handleReturnByProxy:(id)sender;
- (void)showPrefWindow:(id)sender;
- (void)reflectChoiceOfPane:(int)tag;
- (void)windowDidBecomeKey:(id)notification;
- (void)windowWillClose:(id)notification;
- (BOOL)windowShouldClose:(id)sender;
- (void)windowDidResignKey:(id)notification;
- (id)notifyController:(SEL)selector withArg:(id)arg;
@end

#endif
