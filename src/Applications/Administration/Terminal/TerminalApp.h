#ifndef TERMINAL_TERMINAL_APP_H
#define TERMINAL_TERMINAL_APP_H

#import <AppKit/NSApplication.h>

@class DirtMonitor;

typedef union {
    unsigned int raw;
    struct {
        char isPartOfASet;
        char forceQuit;
        char shellsShouldQuit;
        char prefVisible;
    } fields;
} TerminalAppFlags;

typedef union {
    unsigned int raw;
    struct {
        char isShellWindow;
        char performingPrint;
        char debugEnabled;
        char hasScroller;
    } fields;
} TerminalAppPrintFlags;

@interface TerminalApp : NSApplication
{
    id quickTitlePanel;
    id quickTitleForm;
    id saveAccessory;
    id autoOpenBox;
    id saveHowMany;
    id newCommand;
    id serviceManager;
    id serviceCache;
    DirtMonitor *dirtMonitor;
    id serviceProvider;
    id prefManager;
    TerminalAppPrintFlags _terminalAppPrintFlags;
    TerminalAppFlags _terminalAppFlags;
    int termCount;
    char inLaunchHide;
    char fontPanelInited;
    char _terminalAppPadding[2];
    const char *cleanCommands[20];
    char needsStatusUpdate;
    char _terminalAppPadding2[3];
    id statusItem;
    char drewStatusIcon;
    char _terminalAppPadding3[3];
    id onStatusIcon;
    id offStatusIcon;
    id aboutBoxOptions;
    id libraryMenu;
    id libraryMenuTime;
    id libraryDir;
    char showLibraryMenu;
}
- (BOOL)prefWindowVisible;
- (void)setPrefWindowVisible:(char)value;
- (id)prefManager;
- (void)preferences:(id)sender;
- (void)applicationWillFinishLaunching:(id)notification;
- (void)applicationDidFinishLaunching:(id)notification;
- (BOOL)applicationShouldTerminate:(id)sender;
- (void)open:(id)sender;
- (void)makePanelGoToLibrary:(id)sender;
- (id)serviceCache;
- (id)serviceProvider;
- (id)dirtMonitor;
- (const char **)cleanCommands;
- (void)save:(id)sender;
- (void)saveAs:(id)sender;
- (char)validateMenuItem:(id)item;
- (int)msgPaste:(id)sender;
- (id)newShell:(const char *)shell;
- (id)newShell:(const char *)shell env:(id)environment;
- (id)newShell:(const char *)shell inFolder:(const char *)folder env:(id)environment;
- (int)runCommand:(const char *)command usingShell:(const char *)shell inFolder:(const char *)folder windowTitle:(const char *)windowTitle closeOnExit:(char)closeOnExit;
- (BOOL)application:(id)application openTempFile:(id)filename;
- (BOOL)application:(id)application openFile:(id)filename;
- (void)displayAppStatus:(id)sender;
- (void)resetAppStatus;
- (void)updateAppStatus;
- (void)showServiceManager:(id)sender;
- (void)newCommand:(id)sender;
- (void)new:(id)sender;
- (const char *)shell;
- (BOOL)DOServicesOK;
- (void)doStartupAction;
- (BOOL)setupDefaults;
- (void)applicationDidBecomeActive:(id)notification;
- (void)applicationDidUnhide:(id)notification;
- (BOOL)fontManager:(id)fontManager willIncludeFont:(NSString *)fontName;
- (void)maybeUpdateLibraryMenu;
- (void)updateLibraryMenu;
- (BOOL)openLibraryTerm:(id)sender;
- (void)quickTitleOK:(id)sender;
- (void)quickTitleCancel:(id)sender;
- (void)quickTitle:(id)sender;
- (void)recalculateDirtyWindows;
- (void)print:(id)sender;
- (char)save:(id)sender mustPrompt:(char)mustPrompt howMany:(int)howMany
    inFile:(const char *)path;
- (void)setPerformingPrint:(char)value;
- (void)setWindowStatus:(char)isShellWindow withScroller:(char)hasScroller
    debug:(char)debugEnabled setMember:(char)isPartOfASet;
- (void)killZone:(NSZone *)zone;
- (BOOL)hasPrefManager;
- (BOOL)doingForcedQuit;
- (void)activateNext:(id)sender forward:(BOOL)forward includeMini:(BOOL)includeMini;
- (id)lazyDestroyZone:(NSZone *)zone wait:(double)wait;
- (void)monStart:(id)sender;
- (void)monStop:(id)sender;
@end

#endif
