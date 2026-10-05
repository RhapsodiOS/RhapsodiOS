#import "TerminalApp.h"
#import "Terminal.h"
#import "Emulation.h"
#import "TerminalAgent.h"
#import "TerminalDOProtocol.h"
#import "TerminalDO.h"
#import "ServiceProvider.h"
#import "TerminalDefaults.h"
#import "Preferences.h"
#import "TerminalServices.h"
#import "ServiceManager.h"
#import "Shell.h"
#import "CommandPanel.h"
#import "TString.h"
#import "SavePanelMode.h"

#import <Foundation/NSBundle.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSArchiver.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSProcessInfo.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageRep.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSOpenPanel.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSForm.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSStatusBar.h>
#import <AppKit/NSStatusItem.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSAttributedString.h>

#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <termcap.h>
#include <unistd.h>
#import <mach/mach.h>

#import "DirtMonitor.h"
@interface ServiceCache (TerminalServicesImport)
- (char)readService:(TerminalServiceRecord *)service fromFile:(FILE *)file
    zone:(NSZone *)zone;
- (void)disableOfferExamples;
- (int)addNewTermService:(TerminalServiceRecord *)service;
- (void)removeServiceAt:(int)index;
@end

@interface TerminalApp (TerminalLibraryOpen)
- (BOOL)openFile:(id)filename;
- (BOOL)openServicesFile:(id)filename;
@end

@interface TerminalApp (TerminalAppInstantiation)
- (id)_newInstance;
- (id)valueForStreamKey:(id)value;
@end

extern char **environmentFrom(NSData *data, NSZone *zone);

id _theDefaultsObject;
NSDictionary *_theDefaults;
NSString *_theAppName;
NSCursor *_TIBeam;
DPSContext _appDPSContext;
static NSZone *theDefaultsZone;
static NSOpenPanel *openPanel;
static NSSavePanel *savePanel;
extern const char Terminal_VERS_NUM[];
extern unsigned char _preInitedTabs[256];
extern void handleSIGHUP(int signalNumber);
extern int setprivexec(int enabled);
extern id objc_msgSend(id receiver, SEL selector, ...);
extern void NSShowSystemInfoPanel(id options, SEL selector, id sender);

@interface NSApplication (TerminalSignalHandling)
- (void)setEnabled:(BOOL)enabled;
@end

@interface NSApplication (TerminalMainWindowAccess)
- (id)_mainWindow;
@end

void handleSIGHUP(int signalNumber)
{
    (void)signalNumber;
    [NSApp setEnabled:YES];
}

@implementation TerminalApp

+ (void)initialize
{
    char termcapEntry[1024];
    int character;

    if (tgetent(termcapEntry, "vt100") > 0)
        setenv("TERMCAP", termcapEntry, 1);
    setenv("TERM", "vt100", 1);
    setenv("TERM_PROGRAM", "Apple_Terminal", 1);
    setenv("TERM_PROGRAM_VERSION", Terminal_VERS_NUM, 1);

    signal(SIGTSTP, SIG_IGN);
    signal(SIGHUP, (void (*)(int))handleSIGHUP);
    signal(SIGTERM, (void (*)(int))handleSIGHUP);
    signal(SIGINT, (void (*)(int))handleSIGHUP);

    for (character = 0; character < 255; character++)
        _preInitedTabs[character] = (character & 7) == 0;
}

- (id)_newInstance
{
    ((id (*)(id, SEL, id))objc_msgSend)(self,
        @selector(valueForStreamKey:), self);
    _terminalAppPrintFlags.fields.isShellWindow = 0;
    _terminalAppPrintFlags.fields.debugEnabled = 0;
    return self;
}

+ (id)sharedApplication
{
    id application = [super sharedApplication];
    [application _newInstance];
    return application;
}

- (BOOL)prefWindowVisible
{
    return _terminalAppFlags.fields.prefVisible;
}

- (void)setPrefWindowVisible:(char)value
{
    _terminalAppFlags.fields.prefVisible = value;
}

- (id)prefManager
{
    NSZone *zone;
    unsigned pageSize;

    if (prefManager == nil) {
        pageSize = NSPageSize();
        zone = NSCreateZone(pageSize, pageSize, YES);
        if (zone == nil) {
            NSBeep();
            return nil;
        }
        NSSetZoneName(zone, @"Preferences");
        prefManager = [[Preferences allocWithZone:zone] init];
    }
    return prefManager;
}

- (void)preferences:(id)sender
{
    Preferences *preferences;
    NSWindow *mainWindow;
    id firstResponder;
    int pane;

    preferences = (Preferences *)[self prefManager];
    [self setPrefWindowVisible:YES];
    pane = [sender tag];
    if (pane <= 7)
        [preferences reflectChoiceOfPane:pane];

    mainWindow = [NSApp mainWindow];
    firstResponder = [mainWindow firstResponder];
    if (firstResponder != nil &&
        [firstResponder isKindOfClass:[Terminal class]])
        [preferences setCurrentTerminal:firstResponder];
    else
        [preferences showDefault:YES];

    [preferences showPrefWindow:self];
}

- (id)serviceProvider
{
    return serviceProvider;
}

- (id)serviceCache
{
    NSZone *zone;

    if (serviceCache == nil) {
        zone = serviceProvider == nil ? NSDefaultMallocZone() :
            [serviceProvider zone];
        serviceCache = [[ServiceCache allocWithZone:zone] init];
    }
    return serviceCache;
}

- (id)dirtMonitor
{
    NSUserDefaults *defaults;

    if (dirtMonitor == nil) {
        dirtMonitor = [[DirtMonitor allocWithZone:[self zone]] init];
        defaults = [NSUserDefaults standardUserDefaults];
        [dirtMonitor setShellsClean:[defaults boolForKey:@"ShellsClean"]
            runningBackgroundClean:[defaults boolForKey:@"RunningBackgroundClean"]
            fastAudits:[defaults boolForKey:@"FastAudits"]
            cleanCommands:[self cleanCommands]];
    }
    return dirtMonitor;
}


- (const char **)cleanCommands
{
    NSUserDefaults *defaults;
    NSString *commandsString;
    const char *commands;
    char *copy;
    char *command;
    char *separator;
    int commandIndex;
    size_t length;

    for (commandIndex = 0; cleanCommands[commandIndex] != NULL;
        commandIndex++)
        free((void *)cleanCommands[commandIndex]);

    defaults = [NSUserDefaults standardUserDefaults];
    commandsString = [defaults stringForKey:@"CleanCommands"];
    commands = [commandsString cString];
    copy = NULL;
    if (commands != NULL) {
        length = strlen(commands);
        copy = NSZoneMalloc([self zone], length + 1);
        strcpy(copy, commands);
    }

    commandIndex = 0;
    command = copy;
    if (command != NULL) {
        do {
            if (*command == '\0')
                break;
            separator = index(command, ';');
            if (separator != NULL)
                *separator = '\0';
            length = strlen(command);
            cleanCommands[commandIndex] = NSZoneMalloc([self zone], length + 1);
            strcpy((char *)cleanCommands[commandIndex], command);
            if (commandIndex > 17) {
                break;
            }
            command = separator + 1;
            commandIndex++;
        } while (separator != NULL);
    }
    for (; commandIndex <= 19; commandIndex++)
        cleanCommands[commandIndex] = NULL;

    return cleanCommands;
}

- (void)save:(id)sender
{
    [self save:sender mustPrompt:0 howMany:1 inFile:NULL];
}

- (void)saveAs:(id)sender
{
    [self save:sender mustPrompt:1 howMany:0 inFile:NULL];
}

- (char)save:(id)sender mustPrompt:(char)mustPrompt howMany:(int)howMany
    inFile:(const char *)path
{
    NSWindow *window;
    NSSavePanel *panel;
    id cell;
    Terminal *terminal;
    Terminal *newSharedTerminal;
    NSArchiver *archiver;
    NSMutableData *data;
    NSString *filename;
    NSString *title;
    NSString *titleKey;
    NSString *message;
    const char *targetPath;
    const char *currentPath;
    int *windowNumbers;
    int windowCount;
    int savedCount;
    int index;
    int sharesFile;
    TerminalSavePanelTitleMode titleMode;
    TerminalSaveWindowAction windowAction;
    char autoOpen;
    char initializedSavePanel;

    initializedSavePanel = 0;
    /* PPC __sel_backref resolves this entry's mainWindow, delegate, class,
       and isKindOfClass: sends. */
    window = [NSApp mainWindow];
    terminal = (Terminal *)[window delegate];
    if (![terminal isKindOfClass:[Terminal class]]) {
        if (!mustPrompt) {
            NSBeep();
            return 0;
        }
        terminal = nil;
    }

    if (path == NULL && !mustPrompt && [terminal fileName] != NULL)
        path = [terminal fileName];

    if (path == NULL) {
        if (savePanel == nil) {
            savePanel = [NSSavePanel savePanel];
            initializedSavePanel = 1;
        }
        panel = savePanel;
        [panel setRequiredFileType:@"term"];
        [panel setAccessoryView:saveAccessory];
        [autoOpenBox setState:0];
        cell = [saveHowMany itemWithTag:(terminal != nil ? 0 : 2)];
        title = [cell title];
        [panel setTitle:title];
        cell = [saveHowMany itemWithTag:0];
        [cell setEnabled:terminal != nil];
        [saveHowMany display];
        if (initializedSavePanel)
            [self makePanelGoToLibrary:panel];
        sharesFile = (howMany == 1) ? [terminal sharesFile] : 0;
        titleMode = terminalSavePanelTitleMode(
            howMany, mustPrompt, sharesFile);
        switch (titleMode) {
        case TerminalSavePanelSaveSet:
            titleKey = @"Save Set";
            break;
        case TerminalSavePanelSave:
            titleKey = @"Save";
            break;
        case TerminalSavePanelSaveAs:
            titleKey = @"Save As";
            break;
        default:
            titleKey = @"You aren't seeing this";
            break;
        }
        title = [[NSBundle mainBundle] localizedStringForKey:
            titleKey value:@"" table:nil];
        [panel setTitle:title];
        if ([panel runModal] != 1)
            return 0;

        filename = [panel filename];
        path = [filename fileSystemRepresentation];
        title = [saveHowMany title];
        cell = [saveHowMany itemWithTitle:title];
        howMany = [cell tag];
        autoOpen = [autoOpenBox state] != 0;
    } else {
        autoOpen = 0;
    }

    targetPath = path;

    NSCountWindows(&windowCount);
    windowNumbers = (int *)__builtin_alloca(
        sizeof(*windowNumbers) * windowCount);

    data = [[NSMutableData alloc] init];
    archiver = [[NSArchiver alloc] initForWritingWithMutableData:data];
    if (data == nil || archiver == nil) {
        [archiver release];
        [data release];
        title = [[NSBundle mainBundle] localizedStringForKey:
            @"Save" value:@"Save" table:nil];
        message = [[NSBundle mainBundle] localizedStringForKey:
            @"Cannot write %s." value:@"Cannot write %s." table:nil];
        NSRunAlertPanel(title, message, NULL, NULL, NULL, targetPath);
        return 1;
    }

    savedCount = 0;
    newSharedTerminal = nil;
    if (howMany == 0 || (howMany == 1 &&
        (terminal == nil || [terminal fileName] == NULL))) {
        if (terminal != nil) {
            struct TerminalExtraWindowInfo info;
            [terminal getExtraWinInfo:&info];
            writeDefaultsToTypedStream(
                (const TerminalEmulationDefaults *)[terminal defaults],
                &info, archiver);
            [terminal setFileName:targetPath sharesFile:0];
            ++savedCount;
        }
    } else {
        NSWindowList(windowCount, windowNumbers);
        for (index = windowCount - 1; index >= 0; --index) {
            window = [self windowWithWindowNumber:windowNumbers[index]];
            if (![[window delegate] isKindOfClass:[Terminal class]])
                continue;
            terminal = (Terminal *)[window delegate];
            currentPath = [terminal fileName];
            windowAction = terminalSaveWindowAction(howMany,
                currentPath != NULL && strcmp(currentPath, targetPath) == 0);
            if (windowAction == TerminalSaveWindowSkip)
                continue;
            if (windowAction == TerminalSaveWindowAddToSet) {
                [terminal setFileName:targetPath sharesFile:1];
                newSharedTerminal = terminal;
            }

            {
                struct TerminalExtraWindowInfo info;
                [terminal getExtraWinInfo:&info];
                writeDefaultsToTypedStream(
                    (const TerminalEmulationDefaults *)[terminal defaults],
                    &info, archiver);
            }
            ++savedCount;
        }
    }

    if (savedCount == 1 && newSharedTerminal != nil)
        [newSharedTerminal setFileName:targetPath sharesFile:0];
    [archiver release];
    if (![data writeToFile:
        [NSString stringWithCString:targetPath] atomically:YES]) {
        [data release];
        title = [[NSBundle mainBundle] localizedStringForKey:
            @"Save" value:@"Save" table:nil];
        message = [[NSBundle mainBundle] localizedStringForKey:
            @"Cannot write %s." value:@"Cannot write %s." table:nil];
        NSRunAlertPanel(title, message, NULL, NULL, NULL, targetPath);
        return 1;
    }
    [data release];

    if (autoOpen) {
        NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
        [defaults setObject:[NSString stringWithCString:targetPath]
            forKey:@"StartupFile"];
        [defaults setInteger:2 forKey:@"StartupAction"];
        if ([self hasPrefManager])
            [(Preferences *)[self prefManager] notifyController:
                @selector(savePanelDidChangeStartupDefaults:) withArg:sender];
    }
    [self maybeUpdateLibraryMenu];
    return 1;
}

- (char)validateMenuItem:(id)item
{
    NSBundle *bundle;
    NSString *title;
    int tag;

    tag = [item tag];
    switch (tag) {
    case 23:
        return (_terminalAppPrintFlags.raw & 0xffff0000U) != 0;
    case 24:
    case 27:
    case 31:
    case 33:
        return _terminalAppPrintFlags.fields.isShellWindow;
    case 25:
        if (!_terminalAppPrintFlags.fields.isShellWindow ||
            !_terminalAppPrintFlags.fields.debugEnabled)
            return 0;
        bundle = [NSBundle mainBundle];
        title = [bundle localizedStringForKey:@"Yield Keys" value:@""
            table:nil];
        [item setTitle:title];
        [item setTag:26];
        return 1;
    case 26:
        bundle = [NSBundle mainBundle];
        if (!_terminalAppPrintFlags.fields.isShellWindow) {
            title = [bundle localizedStringForKey:@"Steal Keys" value:@""
                table:nil];
            [item setTitle:title];
            [item setTag:25];
            return 0;
        }
        if (!_terminalAppFlags.fields.isPartOfASet)
            return 0;
        title = [bundle localizedStringForKey:@"Yield Keys" value:@""
            table:nil];
        [item setTitle:title];
        [item setTag:26];
        return 1;
    case 28:
        return _terminalAppPrintFlags.fields.isShellWindow &&
            _terminalAppPrintFlags.fields.hasScroller;
    case 29:
    case 32:
        return 1;
    case 30:
        if (_terminalAppPrintFlags.fields.isShellWindow)
            return 1;
        bundle = [NSBundle mainBundle];
        title = [bundle localizedStringForKey:
            (_terminalAppFlags.fields.isPartOfASet ? @"Save Set" : @"Save")
            value:@"" table:nil];
        if ([[item title] isEqualToString:title])
            return 0;
        [item setTitle:title];
        return 1;
    default:
        return 1;
    }
}

- (int)msgPaste:(id)sender
{
    Terminal *terminal;
    TerminalEmulationDefaults *defaults;

    (void)sender;
    terminal = [self newShell:NULL];
    if (terminal == nil)
        return -1;

    defaults = (TerminalEmulationDefaults *)[terminal defaults];
    defaults->var18 = 2;
    [terminal setDefaults:defaults];
    [terminal setServiceOwner:(int)self];
    return 0;
}

- (id)newShell:(const char *)shell
{
    return [self newShell:shell inFolder:NULL env:nil];
}

- (id)newShell:(const char *)shell env:(id)environment
{
    return [self newShell:shell inFolder:NULL env:environment];
}

- (id)newShell:(const char *)shell inFolder:(const char *)folder env:(id)environment
{
    NSZone *zone;
    NSString *zoneName;
    TerminalEmulationDefaults *defaults;
    char **environmentVector;
    TerminalAgent *agent;
    Terminal *terminal;
    NSWindow *window;
    size_t shellLength;

    if (![self setupDefaults])
        return nil;
    [Shell freeAll];
    zone = NSCreateZone(NSPageSize(), NSPageSize(), YES);
    if (zone == NULL) {
        NSBeep();
        return nil;
    }

    ++termCount;
    zoneName = [NSString stringWithCString:"Terminal"];
    NSSetZoneName(zone, zoneName);
    defaults = defaultsFromDB(zone);
    if (defaults == NULL) {
        NSRecycleZone(zone);
        return nil;
    }

    if (shell != NULL && *shell != '\0') {
        free(defaults->var10);
        shellLength = strlen(shell);
        defaults->var10 = NSZoneMalloc(zone, shellLength + 1);
        if (defaults->var10 == NULL) {
            NSRunAlertPanel(@"New Shell",
                @"Couldn't start up the shell you requested.  Check to be sure that it exists and that you can execute it.",
                @"OK", NULL, NULL);
        }
        strcpy(defaults->var10, shell);
        defaults->var18 = TSCloseOnExit;
        defaults->var1 = 0;
    }

    environmentVector = environment != nil
        ? environmentFrom((NSData *)environment, zone) : NULL;
    agent = [[TerminalAgent allocWithZone:zone]
        initDefaults:defaults inFolder:folder env:environmentVector];
    if (agent == nil)
        return nil;
    if (environmentVector != NULL)
        free(environmentVector);

    terminal = [agent terminal];
    window = [terminal window];
    [window setDelegate:terminal];
    [window setTarget:self];
    [agent release];
    return terminal;
}

- (int)runCommand:(const char *)command usingShell:(const char *)shell
    inFolder:(const char *)folder windowTitle:(const char *)windowTitle
    closeOnExit:(char)closeOnExit
{
    Terminal *terminal;
    TerminalEmulationDefaults *defaults;

    terminal = [self newShell:shell inFolder:folder env:nil];
    if (terminal == nil)
        return -1;

    if (windowTitle != NULL && *windowTitle != '\0')
        [terminal setCustomTitle:windowTitle];

    defaults = (TerminalEmulationDefaults *)[terminal defaults];
    defaults->var18 = closeOnExit ? TSCloseOnExit : TSDontCloseOnExit;
    [terminal setDefaults:defaults];
    if (command != NULL && *command != '\0')
        [terminal output:command];
    return 0;
}

- (BOOL)application:(id)application openTempFile:(id)filename
{
    return [self application:application openFile:filename];
}

- (void)displayAppStatus:(id)sender
{
    (void)sender;
    if (drewStatusIcon)
        [statusItem setImage:offStatusIcon];
    else
        [statusItem setImage:onStatusIcon];
    drewStatusIcon = drewStatusIcon == 0;
    needsStatusUpdate = 0;
}

- (void)resetAppStatus
{
    [statusItem setImage:nil];
    drewStatusIcon = 0;
}

- (void)updateAppStatus
{
    NSArray *representations;
    NSString *imagePath;
    NSImage *image;
    NSImageRep *representation;
    NSSize iconSize;
    int index;

    if (needsStatusUpdate)
        return;
    needsStatusUpdate = 1;

    if (onStatusIcon == nil) {
        imagePath = [[NSBundle mainBundle] pathForImageResource:@"icon"];
        image = [[NSImage alloc] initWithContentsOfFile:imagePath];
        representations = [image representations];
        index = (int)[representations count] - 1;
        while (index >= 0) {
            representation = [representations objectAtIndex:index];
            iconSize = [representation size];
            if (NSEqualSizes(NSMakeSize(16.0, 16.0), iconSize))
                break;
            index--;
        }

        if (index >= 0) {
            onStatusIcon = [[NSImage alloc]
                initWithSize:NSMakeSize(16.0, 16.0)];
            [onStatusIcon addRepresentation:representation];
        } else {
            onStatusIcon = [[self applicationIconImage] copyWithZone:NULL];
            [onStatusIcon setScalesWhenResized:YES];
            [onStatusIcon setSize:NSMakeSize(16.0, 16.0)];
        }
        offStatusIcon = [[NSImage alloc]
            initWithSize:NSMakeSize(16.0, 16.0)];
    }

    if (statusItem == nil) {
        statusItem = [[NSStatusBar systemStatusBar]
            statusItemWithLength:16.0];
        [statusItem setHighlightMode:YES];
        [statusItem setTarget:self];
        [statusItem setAction:@selector(displayAppStatus:)];
    }
    [statusItem setImage:onStatusIcon];
    [self performSelector:@selector(displayAppStatus:) withObject:self
        afterDelay:0.5];
}

- (void)info:(id)sender
{
    NSString *creditsPath;
    NSAttributedString *credits;
    NSImage *applicationNameImage;
    NSString *version;

    if (aboutBoxOptions == nil) {
        creditsPath = [[NSBundle mainBundle]
            pathForResource:@"Credits" ofType:@"rtf"];
        credits = [[NSAttributedString alloc]
            initWithPath:creditsPath documentAttributes:NULL];
        applicationNameImage = [NSImage imageNamed:@"TerminalTitle"];
        version = [NSString stringWithFormat:@"%@", Terminal_VERS_NUM];
        aboutBoxOptions = [[NSDictionary alloc] initWithObjectsAndKeys:
            credits, @"Credits",
            applicationNameImage, @"ApplicationNameImage",
            version, @"Version",
            @"1997", @"CopyrightStartYear", nil];
    }
    NSShowSystemInfoPanel(aboutBoxOptions, _cmd, sender);
}

- (void)showServiceManager:(id)sender
{
    NSZone *zone;
    unsigned pageSize;

    (void)sender;
    if (serviceManager == nil) {
        pageSize = NSPageSize();
        zone = NSCreateZone(pageSize, pageSize, YES);
        if (zone == nil) {
            NSBeep();
            return;
        }
        NSSetZoneName(zone, @"SvcManager");
        serviceManager = [[ServiceManager allocWithZone:zone] init];
    }
    [serviceManager go:0];
}

- (void)newCommand:(id)sender
{
    (void)sender;
    if (newCommand == nil)
        newCommand = [[CommandPanel allocWithZone:NULL] init];
    [newCommand showPanel];
}

- (void)new:(id)sender
{
    (void)sender;
    [self newShell:NULL];
}

- (const char *)shell
{
    const char *shellPath;
    struct passwd *user;

    shellPath = [[[NSUserDefaults standardUserDefaults]
        stringForKey:@"Shell"] cString];
    if (shellPath != NULL && strcmp(shellPath, "NO") != 0)
        return shellPath;

    user = getpwuid(getuid());
    return user != NULL ? user->pw_shell : "/bin/csh";
}

- (BOOL)DOServicesOK
{
    char path[1044];
    const char *bundlePath;

    bundlePath = [[[NSBundle mainBundle] bundlePath] cString];
    sprintf(path, "%s/.DisableDOServices", bundlePath);
    return access(path, 0) == -1;
}

- (void)doStartupAction
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    int action = [defaults integerForKey:@"StartupAction"];
    NSString *startupFile;

    if (action == 1) {
        [self new:self];
        return;
    }
    if (action != 2)
        return;

    [defaults synchronize];
    startupFile = [defaults objectForKey:@"StartupFile"];
    if (startupFile == nil || [startupFile length] == 0) {
        [defaults setInteger:1 forKey:@"StartupAction"];
        [self new:self];
        return;
    }

    [self openFile:startupFile];
}

- (BOOL)setupDefaults
{
    struct passwd *user;
    NSAutoreleasePool *pool;
    NSArray *searchList;
    NSDictionary *domain;
    NSMutableDictionary *emptyDomain;
    NSString *bundlePath;
    NSString *username;

    if (_theDefaultsObject != nil)
        return YES;

    pool = [NSAutoreleasePool new];

    if (theDefaultsZone == nil) {
        theDefaultsZone = NSCreateZone(0x6000, NSPageSize(), YES);
        NSSetZoneName(theDefaultsZone, @"UserDefaults");
    }

    user = getpwuid(getuid());
    if (user != NULL) {
        username = [NSString stringWithCString:user->pw_name];
        _theDefaultsObject = [[NSUserDefaults allocWithZone:theDefaultsZone]
            initWithUser:username];
    } else {
        _theDefaultsObject = [[NSUserDefaults allocWithZone:theDefaultsZone]
            init];
    }

    if (_theDefaultsObject == nil) {
        NSBeep();
        [pool release];
        return NO;
    }

    bundlePath = [[NSBundle mainBundle] bundlePath];
    searchList = [[[(NSUserDefaults *)_theDefaultsObject searchList]
        mutableCopyWithZone:theDefaultsZone] autorelease];
    [(NSMutableArray *)searchList addObject:NSArgumentDomain];
    [(NSMutableArray *)searchList addObject:bundlePath];

    domain = [(NSUserDefaults *)_theDefaultsObject
        persistentDomainForName:bundlePath];
    if (domain == nil) {
        emptyDomain = [[[NSMutableDictionary allocWithZone:theDefaultsZone]
            init] autorelease];
        [(NSUserDefaults *)_theDefaultsObject
            setPersistentDomain:emptyDomain forName:bundlePath];
    }

    [(NSMutableArray *)searchList addObject:NSGlobalDomain];
    [(NSMutableArray *)searchList addObject:NSRegistrationDomain];
    [(NSUserDefaults *)_theDefaultsObject setSearchList:searchList];
    [pool release];
    return YES;
}

- (void)applicationWillFinishLaunching:(id)notification
{
    NSUserDefaults *defaults;

    (void)notification;
    setprivexec(1);
    _appDPSContext = DPSGetCurrentContext();

    defaults = [[NSUserDefaults alloc] init];
    _theDefaultsObject = defaults;
    _theDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
        @"NO", @"AutoFocus",
        @"YES", @"Autowrap",
        @"NO", @"Keypad",
        @"YES", @"Scrollback",
        @"YES", @"SourceDotLogin",
        @"NO", @"StrictEmulation",
        @"YES", @"Translate",
        @"YES", @"MonitorProcs",
        @"YES", @"ShellsClean",
        @"NO", @"RunningBackgroundClean",
        @"NO", @"FastAudits",
        @"24", @"Rows",
        @"80", @"Columns",
        @"-1", @"Meta",
        @"", @"Shell",
        @"200", @"WinLocX",
        @"580", @"WinLocY",
        @"rlogin;telnet", @"CleanCommands",
        @"3", @"TitleBits",
        @"Terminal", @"CustomTitle",
        @"-1", @"SaveLines",
        @"0", @"ShellExitAction",
        @"", @"StartupFile",
        @"1", @"StartupAction",
        @"NO", @"DockLaunchHide",
        @"0", @"ServiceSequenceNumber",
        @"0 0 0   1 1 1   0 0 0   0.333 0.333 0.333 1 1 1   0.333 0.333 0.333   0.666 0.666 0.666   0.333 0.333 0.333",
            @"TextColors",
        @"8", @"TextAttributes", nil];
    [defaults registerDefaults:_theDefaults];
    _theAppName = [[[NSProcessInfo processInfo] processName] copy];
    _terminalAppFlags.fields.forceQuit = 0;
    _terminalAppFlags.fields.shellsShouldQuit = 0;
}

- (void)applicationDidFinishLaunching:(id)notification
{
    static NSString *digitTitles[10] = {
        @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9"
    };
    NSUserDefaults *defaults;
    NSArray *sendTypes;
    NSArray *returnTypes;
    NSFontManager *fontManager;
    NSMenu *mainMenu;
    NSMenu *applicationMenu;
    NSMenu *preferencesMenu;
    NSMenuItem *libraryItem;
    NSString *homeDirectory;
    NSString *title;
    NSString *startupHost;
    NSZone *zone;
    NSCursor *cursor;
    int index;

    (void)notification;
    defaults = (NSUserDefaults *)_theDefaultsObject;

    sendTypes = [NSArray arrayWithObjects:NSStringPboardType, nil];
    returnTypes = [NSArray array];
    fontManager = [NSFontManager new];
    [fontManager setDelegate:self];
    [NSApp registerServicesMenuSendTypes:sendTypes returnTypes:returnTypes];

    mainMenu = [NSApp mainMenu];
    applicationMenu = [[mainMenu itemWithTag:15] target];
    if ([defaults boolForKey:@"LibraryMenu"]) {
        homeDirectory = NSHomeDirectory();
        self->libraryDir = [[homeDirectory
            stringByAppendingPathComponent:@"Library/Terminal"] copyWithZone:NULL];
        self->showLibraryMenu = 1;

        zone = [NSMenu menuZone];
        title = [[NSBundle mainBundle] localizedStringForKey:@"Library"
            value:@"" table:nil];
        self->libraryMenu = [[NSMenu allocWithZone:zone] initWithTitle:title];
        title = [[NSBundle mainBundle] localizedStringForKey:@"Library"
            value:@"" table:nil];
        libraryItem = [applicationMenu insertItemWithTitle:title
            action:@selector(submenuAction:) keyEquivalent:@"" atIndex:2];
        [applicationMenu setSubmenu:self->libraryMenu forItem:libraryItem];
        [self updateLibraryMenu];
    }

    preferencesMenu = [[NSMenu alloc] initWithTitle:@""];
    for (index = 1; index <= 8; ++index) {
        id item = [preferencesMenu addItemWithTitle:digitTitles[index]
            action:@selector(preferences:) keyEquivalent:@""];
        [item setTag:index - 1];
    }

    self->serviceProvider = [[ServiceProvider alloc] init];
    [NSApp setServicesProvider:self->serviceProvider];

    self->statusItem = [[[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength] retain];
    [self->statusItem setImage:nil];
    [self->statusItem setTarget:self];
    [self->statusItem setAction:@selector(unhide:)];

    if (![defaults boolForKey:@"DisableDOServices"]) {
        startupHost = [defaults objectForKey:@"NXHost"];
        if ([startupHost cString] == NULL && [self DOServicesOK]) {
            zone = NSCreateZone(vm_page_size, vm_page_size, YES);
            if (zone != nil) {
                TerminalDO *terminalDO = [[TerminalDO allocWithZone:zone] init];
                [terminalDO release];
                NSSetZoneName(zone, @"TerminalDO");
            }
        }
    }

    startupHost = [defaults objectForKey:@"NXOpen"];
    if ([startupHost cString] == NULL) {
        if ([defaults boolForKey:@"DockLaunchHide"] &&
            [defaults boolForKey:@"NSAutoLaunch"]) {
            [self hide:self];
            self->inLaunchHide = 1;
        } else {
            [self doStartupAction];
        }
    }

    cursor = [[NSCursor allocWithZone:[self zone]]
        initWithImage:[NSImage imageNamed:@"TIbeam"]
        hotSpot:NSMakePoint(1.0f, 8.0f)];
    _TIBeam = [cursor retain];
}

- (BOOL)applicationShouldTerminate:(id)sender
{
    NSArray *windows;
    NSMutableArray *terminalWindows;
    NSWindow *window;
    NSWindow *preferencesWindow;
    NSWindow *mainWindow;
    NSRect frame;
    id delegate;
    Terminal *terminal;
    NSBundle *bundle;
    NSString *title;
    NSString *message;
    NSString *defaultButton;
    NSString *alternateButton;
    NSString *otherButton;
    int count;
    int editedCount;
    int index;
    int response;

    (void)sender;
    mainWindow = [NSApp _mainWindow];
    if (mainWindow != nil) {
        frame = [mainWindow frame];
        [_theDefaultsObject setInteger:(int)frame.origin.x forKey:@"WinLocX"];
        [_theDefaultsObject setInteger:(int)(frame.origin.y + frame.size.height)
            forKey:@"WinLocY"];
    }

    windows = [NSApp windows];
    count = (int)[windows count];
    terminalWindows = [NSMutableArray arrayWithCapacity:count];
    editedCount = 0;
    preferencesWindow = nil;
    for (index = 0; index < count; ++index) {
        window = [windows objectAtIndex:index];
        delegate = [window delegate];
        if ([delegate isKindOfClass:[Terminal class]]) {
            terminal = (Terminal *)delegate;
            if (!_terminalAppFlags.fields.forceQuit) {
                if (![_theDefaultsObject boolForKey:@"MonitorProcs"] ||
                    [terminal isDead]) {
                    [window setDocumentEdited:NO];
                } else {
                    [window setDocumentEdited:[[self dirtMonitor]
                        isDeviceDirty:[terminal shellDevice]]];
                }
                if ([window isDocumentEdited])
                    ++editedCount;
            }
            [terminalWindows addObject:window];
        } else if ([delegate isKindOfClass:[Preferences class]]) {
            preferencesWindow = window;
        }
    }

    _terminalAppFlags.fields.shellsShouldQuit = 0;
    if (!_terminalAppFlags.fields.forceQuit) {
        bundle = [NSBundle mainBundle];
        if (![_theDefaultsObject boolForKey:@"MonitorProcs"]) {
            title = [bundle localizedStringForKey:@"Quit" value:@"" table:nil];
            message = [bundle localizedStringForKey:
                @"Do you really want to quit Terminal?" value:@"" table:nil];
            defaultButton = [bundle localizedStringForKey:@"Quit"
                value:@"" table:nil];
            alternateButton = [bundle localizedStringForKey:@"Cancel"
                value:@"" table:nil];
            response = NSRunAlertPanel(title, message, defaultButton,
                alternateButton, nil);
            if (response == NSAlertAlternateReturn)
                return NO;
            _terminalAppFlags.fields.shellsShouldQuit = 1;
        } else if (editedCount != 0) {
            title = [bundle localizedStringForKey:@"Quit" value:@"" table:nil];
            message = [bundle localizedStringForKey:
                @"There are active windows." value:@"" table:nil];
            defaultButton = [bundle localizedStringForKey:@"Quit Anyway"
                value:@"" table:nil];
            alternateButton = [bundle localizedStringForKey:@"Review Windows"
                value:@"" table:nil];
            otherButton = [bundle localizedStringForKey:@"Cancel"
                value:@"" table:nil];
            response = NSRunAlertPanel(title, message, defaultButton,
                alternateButton, otherButton);
            if (response == NSAlertOtherReturn)
                return NO;
            if (response == NSAlertDefaultReturn) {
                _terminalAppFlags.fields.shellsShouldQuit = 1;
            } else if (response != NSAlertAlternateReturn) {
                exit(0);
            } else {
                for (index = 0; index < (int)[terminalWindows count];) {
                    window = [terminalWindows objectAtIndex:index];
                    if (![window isDocumentEdited] ||
                        ![[window delegate] isKindOfClass:[Terminal class]]) {
                        ++index;
                        continue;
                    }
                    [terminalWindows removeObjectAtIndex:index];
                    [window performClose:self];
                    if ([window isVisible])
                        return NO;
                }
            }
        }
    }

    if (preferencesWindow != nil && [preferencesWindow isVisible]) {
        [preferencesWindow performClose:self];
        if ([preferencesWindow isVisible] &&
            !_terminalAppFlags.fields.forceQuit) {
            _terminalAppFlags.fields.shellsShouldQuit = 0;
            return NO;
        }
    }

    for (index = 0; index < (int)[terminalWindows count]; ++index) {
        window = [terminalWindows objectAtIndex:index];
        [window performClose:self];
        if ([window isVisible] && !_terminalAppFlags.fields.forceQuit) {
            _terminalAppFlags.fields.shellsShouldQuit = 0;
            return NO;
        }
    }
    return YES;
}

- (void)applicationDidBecomeActive:(id)notification
{
    id application;

    application = [notification object];
    [application recalculateDirtyWindows];
    [application maybeUpdateLibraryMenu];
}


- (void)applicationDidUnhide:(id)notification
{
    NSArray *windows;
    NSWindow *window;
    Terminal *terminal;
    int index;

    (void)notification;
    if (inLaunchHide) {
        inLaunchHide = 0;
        [self doStartupAction];
    } else {
        windows = [NSApp windows];
        for (index = 0; index < (int)[windows count]; index++) {
            window = [windows objectAtIndex:index];
            terminal = (Terminal *)[window delegate];
            if ([terminal isKindOfClass:[Terminal class]])
                [terminal updateDirtIfNeeded];
        }
    }

    needsStatusUpdate = 0;
    [self resetAppStatus];
}

- (BOOL)fontManager:(id)fontManager willIncludeFont:(NSString *)fontName
{
    NSFont *candidateFont;
    float *fontWidths;

    (void)fontManager;
    candidateFont = [NSFont fontWithName:fontName size:12.0f];
    if (candidateFont == nil)
        return NO;
    fontWidths = [candidateFont widths];
    return fontWidths != NULL && fontWidths['i'] == fontWidths['W'];
}

- (void)maybeUpdateLibraryMenu
{
    NSDictionary *attributes;
    id modifiedDate;
    NSFileManager *fileManager;

    if (showLibraryMenu == 0 || libraryDir == nil)
        return;

    fileManager = [NSFileManager defaultManager];
    attributes = [fileManager fileAttributesAtPath:libraryDir traverseLink:YES];
    if (attributes == nil)
        return;

    modifiedDate = [attributes fileModificationDate];
    if ((int)[libraryMenuTime compare:modifiedDate] == -1)
        [self updateLibraryMenu];
}

- (void)updateLibraryMenu
{
    NSDictionary *attributes;
    NSFileManager *fileManager;
    NSArray *filenames;
    NSMutableArray *terminalNames;
    NSString *filename;
    NSString *name;
    NSMenuItem *item;
    int index;

    fileManager = [NSFileManager defaultManager];
    attributes = [fileManager fileAttributesAtPath:libraryDir traverseLink:YES];
    if (showLibraryMenu != 0) {
        for (index = [libraryMenu numberOfItems] - 1; index >= 0; --index)
            [libraryMenu removeItemAtIndex:index];

        if (attributes == nil)
            return;

        [libraryMenuTime release];
        libraryMenuTime = [[attributes fileModificationDate] retain];

        filenames = [fileManager directoryContentsAtPath:libraryDir];
        terminalNames = [NSMutableArray arrayWithCapacity:[filenames count]];
        for (index = 0; index < (int)[filenames count]; ++index) {
            filename = [filenames objectAtIndex:index];
            if ([[filename pathExtension] isEqualToString:@"term"]) {
                name = [filename stringByDeletingPathExtension];
                [terminalNames addObject:name];
            }
        }

        if ([terminalNames count] == 0)
            return;

        [terminalNames sortUsingSelector:@selector(caseInsensitiveCompare:)];
        for (index = 0; index < (int)[terminalNames count]; ++index) {
            name = [terminalNames objectAtIndex:index];
            item = [libraryMenu addItemWithTitle:name
                action:@selector(openLibraryTerm:) keyEquivalent:@""];
            [item setTarget:self];
        }
    }
}

- (void)makePanelGoToLibrary:(id)sender
{
    NSString *home;
    NSString *directory;
    const char *path;
    struct stat attributes;

    home = NSHomeDirectory();
    if (home == nil || [home isEqualToString:@"/"]) {
        [sender setDirectory:@"/"];
        return;
    }

    directory = [home stringByAppendingPathComponent:@"Library/Terminal"];
    path = [directory fileSystemRepresentation];
    if (stat(path, &attributes) != 0) {
        if (mkdir(path, 0777) != 0) {
            [sender setDirectory:home];
            return;
        }
    } else if ((attributes.st_mode & S_IFMT) != S_IFDIR) {
        return;
    }

    [sender setDirectory:directory];
}

- (void)open:(id)sender
{
    NSArray *fileTypes;
    NSString *filename;

    (void)sender;
    if (openPanel == nil) {
        openPanel = [NSOpenPanel openPanel];
        [self makePanelGoToLibrary:openPanel];
    }

    fileTypes = [NSArray arrayWithObjects:@"svcs", @"term", nil];
    if ([openPanel runModalForTypes:fileTypes] != NSCancelButton) {
        filename = [openPanel filename];
        if (filename != nil) {
            if ([filename hasSuffix:@"svcs"])
                [self openServicesFile:filename];
            else
                [self openFile:filename];
        }
    }
}

- (BOOL)openFile:(NSString *)filename
{
    NSBundle *bundle;
    NSString *title;
    NSString *message;
    const char *path;
    NSData *data;
    NSUnarchiver *unarchiver;
    NSZone *zone;
    NSString *zoneName;
    struct TerminalExtraWindowInfo windowInfo;
    TerminalEmulationDefaults *defaults;
    TerminalAgent *agent;
    Terminal *terminal;
    Terminal *firstTerminal;
    NSWindow *window;
    NSWindow *lastVisibleWindow;
    NSScreen *screen;
    NSRect screenFrame;
    NSPoint topLeft;
    int openedCount;

    path = [filename fileSystemRepresentation];
    if (access(path, 4) != 0) {
        bundle = [NSBundle mainBundle];
        title = [bundle localizedStringForKey:@"Open" value:@"Open"
            table:nil];
        message = [bundle localizedStringForKey:@"Cannot open %s."
            value:@"Cannot open %s." table:nil];
        NSRunAlertPanel(title, message, NULL, NULL, NULL, path);
        return YES;
    }

    data = [NSData dataWithContentsOfMappedFile:filename];
    if (data == nil) {
        bundle = [NSBundle mainBundle];
        title = [bundle localizedStringForKey:@"Open" value:@"Open"
            table:nil];
        message = [bundle localizedStringForKey:@"Cannot open %s."
            value:@"Cannot open %s." table:nil];
        NSRunAlertPanel(title, message, NULL, NULL, NULL, path);
        return NO;
    }

    unarchiver = [[NSUnarchiver alloc] initForReadingWithData:data];
    firstTerminal = nil;
    lastVisibleWindow = nil;
    openedCount = 0;

    NS_DURING
        while (![unarchiver isAtEnd]) {
            zone = NSCreateZone(NSPageSize(), NSPageSize(), YES);
            if (zone == nil)
                [NSException raise:NSMallocException format:nil];

            ++termCount;
            zoneName = [NSString stringWithFormat:@"Term #%d", termCount];
            NSSetZoneName(zone, zoneName);
            defaults = readDefaultsFromTypedStream(unarchiver, &windowInfo,
                zone);

            agent = [[TerminalAgent allocWithZone:zone]
                initDefaults:defaults inFolder:NULL env:NULL];
            if (agent == nil)
                [NSException raise:NSMallocException format:nil];

            terminal = [agent terminal];
            [agent release];
            if (++openedCount == 1)
                firstTerminal = terminal;

            [terminal setFileName:path sharesFile:YES];
            window = [terminal window];
            screen = [window screen];
            screenFrame = [screen frame];
            topLeft = NSMakePoint(windowInfo.x * screenFrame.size.width,
                windowInfo.y * screenFrame.size.height);
            [window setFrameOrigin:topLeft];
            [window setDelegate:terminal];
            [window setTarget:self];
            if (windowInfo.hidden)
                [window orderOut:self];
            else
                lastVisibleWindow = window;
        }
    NS_HANDLER
        bundle = [NSBundle mainBundle];
        title = [bundle localizedStringForKey:@"Open" value:@"Open"
            table:nil];
        message = [bundle localizedStringForKey:
            @"An error occurred while reading from %s."
            value:@"An error occurred while reading from %s." table:nil];
        NSRunAlertPanel(title, message, NULL, NULL, NULL, path);
        [unarchiver release];
        return NO;
    NS_ENDHANDLER

    if (lastVisibleWindow != nil)
        [lastVisibleWindow makeKeyAndOrderFront:self];
    if (openedCount == 1)
        [firstTerminal setFileName:path sharesFile:NO];
    [unarchiver release];
    return YES;
}

- (BOOL)application:(id)application openFile:(NSString *)filename
{
    NSString *suffix;
    const char *path;
    struct stat attributes;
    id terminal;

    (void)application;
    if (filename != nil && ![filename isEqualToString:@""] &&
        [filename isEqualToString:@"/tmp/.reallyignorethis.term"])
        return YES;

    suffix = [@"." stringByAppendingString:@"term"];
    if ([filename hasSuffix:suffix]) {
        [self openFile:filename];
        return YES;
    }

    suffix = [@"." stringByAppendingString:@"svcs"];
    if ([filename hasSuffix:suffix])
        return [self openServicesFile:filename];

    path = [filename fileSystemRepresentation];
    if (stat(path, &attributes) == 0 &&
        (attributes.st_mode & S_IFMT) == S_IFDIR) {
        terminal = [self newShell:NULL inFolder:path env:NULL];
    } else {
        if (access(path, 1) != 0)
            return NO;
        terminal = [self newShell:path];
    }
    return terminal != nil;
}

- (BOOL)openServicesFile:(NSString *)filename
{
    const char *path;
    const char *baseName;
    char *slash;
    char summary[8192];
    FILE *file;
    ServiceCache *cache;
    TerminalServiceRecord service;
    TerminalServiceSet *serviceSet;
    NSBundle *bundle;
    NSString *title;
    NSString *message;
    NSString *button;
    NSString *alternateButton;
    int index;
    int panelResult;
    int importedCount;
    char skipService;

    path = [filename fileSystemRepresentation];
    cache = [self serviceCache];
    if (cache == nil) {
        NSBeep();
        return NO;
    }

    if (access(path, 4) != 0)
        goto open_error;

    slash = rindex((char *)path, '/');
    baseName = slash != NULL ? slash + 1 : path;
    bundle = [NSBundle mainBundle];
    title = [bundle localizedStringForKey:@"Terminal Services"
        value:@"Terminal Services" table:nil];
    message = [bundle localizedStringForKey:
        @"Add services defined in %s to your configuration?"
        value:@"Add services defined in %s to your configuration?"
        table:nil];
    button = [bundle localizedStringForKey:@"Add" value:@"Add" table:nil];
    alternateButton = [bundle localizedStringForKey:@"Don't Load"
        value:@"Don't Load" table:nil];
    if (NSRunAlertPanel(title, message, button, alternateButton, NULL,
            baseName) != 1)
        return NO;

    message = [bundle localizedStringForKey:
        @"The following services were added to your configuration: "
        value:@"The following services were added to your configuration: "
        table:nil];
    strcpy(summary, [message cString]);
    file = fopen(path, "r");
    if (file == NULL)
        goto open_error;

    if ([cache serviceSet] == NULL) {
        [cache disableOfferExamples];
        [cache loadServiceSet];
    }

    importedCount = 0;
    while ([cache readService:&service fromFile:file zone:[self zone]]) {
        serviceSet = [cache serviceSet];
        if (serviceSet == NULL) {
            NSBeep();
            return NO;
        }

        skipService = NO;
        for (index = 0; index < serviceSet->count; ++index) {
            if ([service.name isEqualToString:
                    serviceSet->records[index].name])
                break;
        }

        if (index < serviceSet->count) {
            message = [bundle localizedStringForKey:
                @"A service named '%s' already exists.  Replace it?"
                value:@"A service named '%s' already exists.  Replace it?"
                table:nil];
            button = [bundle localizedStringForKey:@"Replace"
                value:@"Replace" table:nil];
            alternateButton = [bundle localizedStringForKey:@"Skip"
                value:@"Skip" table:nil];
            panelResult = NSRunAlertPanel(title, message, button,
                alternateButton, nil, [service.name cString]);
            if (panelResult == -1)
                break;
            if (panelResult == 0)
                skipService = YES;
            else
                [cache removeServiceAt:index];
        }

        if (!skipService) {
            [cache addNewTermService:&service];
            if (importedCount != 0)
                strcat(summary, ", ");
            strcat(summary, [service.name cString]);
            ++importedCount;
            free((void *)service.name);
            free((void *)service.command);
        }
    }
    fclose(file);

    if (importedCount != 0) {
        if (serviceManager != nil)
            [serviceManager go:1];
        message = [NSString stringWithCString:summary];
    } else {
        message = [bundle localizedStringForKey:@"No services were added."
            value:@"No services were added." table:nil];
    }
    title = [bundle localizedStringForKey:@"Terminal Services"
        value:@"Terminal Services" table:nil];
    NSRunAlertPanel(title, message, NULL, NULL, NULL);
    return YES;

open_error:
    bundle = [NSBundle mainBundle];
    title = [bundle localizedStringForKey:@"Terminal Services"
        value:@"Terminal Services" table:nil];
    message = [bundle localizedStringForKey:@"Cannot open %s."
        value:@"Cannot open %s." table:nil];
    NSRunAlertPanel(title, message, NULL, NULL, NULL, path);
    return YES;
}

- (BOOL)openLibraryTerm:(id)sender
{
    NSString *name;
    NSString *path;

    name = [sender title];
    path = [libraryDir stringByAppendingPathComponent:name];
    path = [path stringByAppendingPathExtension:@"term"];
    return [self openFile:path];
}


- (void)quickTitleOK:(id)sender
{
    [quickTitlePanel orderOut:sender];
    [NSApp stopModalWithCode:0];
}

- (void)quickTitleCancel:(id)sender
{
    [quickTitlePanel orderOut:sender];
    [NSApp stopModalWithCode:1];
}

- (void)quickTitle:(id)sender
{
    Terminal *terminal;
    TerminalEmulationDefaults *defaults;
    id titleCell;
    NSString *formCell;
    NSString *title;
    const char *titleBytes;
    NSWindow *window;
    id currentEvent;

    (void)sender;
    window = [NSApp keyWindow];
    if (window == nil)
        return;
    terminal = (Terminal *)[window delegate];
    if (![terminal isKindOfClass:[Terminal class]]) {
        NSBeep();
        return;
    }
    defaults = (TerminalEmulationDefaults *)[terminal defaults];

    titleCell = [quickTitleForm cellAtIndex:0];
    formCell = [defaults->var16 stringValue];
    [titleCell setStringValue:formCell];
    [quickTitleForm selectTextAtIndex:0];
    [quickTitlePanel center];
    [quickTitlePanel makeKeyAndOrderFront:self];
    if ([NSApp runModalForWindow:quickTitlePanel] != 0)
        return;

    currentEvent = [NSApp currentEvent];
    if (([currentEvent modifierFlags] & NSAlternateKeyMask) != 0)
        defaults->var15 = 8;
    else
        defaults->var15 |= 8;
    title = [titleCell stringValue];
    titleBytes = [title cString];
    [(TString *)defaults->var16 setStringValue:
        [NSString stringWithCString:titleBytes]];
    [terminal setDefaults:defaults];
    if ([(TerminalApp *)NSApp hasPrefManager]) {
        [(Preferences *)[(TerminalApp *)NSApp prefManager]
            notifyController:@selector(terminalDidBecomeMain:) withArg:
                terminal];
    }
}

- (void)recalculateDirtyWindows
{
    NSArray *windows;
    NSWindow *window;
    Terminal *terminal;
    id application;
    int index;

    windows = [NSApp windows];
    for (index = 0; index < (int)[windows count]; index++) {
        window = [windows objectAtIndex:index];
        terminal = (Terminal *)[window delegate];
        if (![terminal isKindOfClass:[Terminal class]])
            continue;

        if (![_theDefaultsObject boolForKey:@"MonitorProcs"] ||
            [terminal isDead]) {
            [window setDocumentEdited:NO];
        } else {
            application = [NSApp delegate];
            [window setDocumentEdited:[[application dirtMonitor]
                isDeviceDirty:[terminal shellDevice]]];
        }
    }
}

- (void)setPerformingPrint:(char)value
{
    _terminalAppPrintFlags.fields.performingPrint = value;
}

- (void)print:(id)sender
{
    NSWindow *window;
    id target;

    window = [NSApp mainWindow];
    target = [window delegate];
    if (target != nil && [target isKindOfClass:[Terminal class]])
        [target print:sender];
    else
        NSBeep();
}

- (void)setWindowStatus:(char)isShellWindow withScroller:(char)hasScroller
    debug:(char)debugEnabled setMember:(char)isPartOfASet
{
    _terminalAppPrintFlags.fields.isShellWindow = isShellWindow;
    _terminalAppPrintFlags.fields.hasScroller = hasScroller;
    _terminalAppPrintFlags.fields.debugEnabled = debugEnabled;
    _terminalAppFlags.fields.isPartOfASet = isPartOfASet;
}

- (void)activateNext:(id)sender forward:(BOOL)forward includeMini:(BOOL)includeMini
{
    NSWindow *window;
    NSWindow *nextWindow;
    id delegate;
    NSArray *windows;
    int direction;
    int index;
    int count;

    window = [sender window];
    windows = [NSApp windows];
    count = (int)[windows count];
    direction = forward ? 1 : -1;
    for (index = 0; index < count; index++) {
        if ([windows objectAtIndex:index] == window)
            break;
    }
    if (index == count)
        return;

    index += direction;
    while (index != (int)[windows indexOfObject:window]) {
        if (index >= count)
            index = 0;
        else if (index < 0)
            index = count - 1;
        nextWindow = [windows objectAtIndex:index];
        delegate = [nextWindow delegate];
        if (delegate != nil && [delegate respondsToSelector:
                @selector(terminalDidBecomeMain:)] &&
            (includeMini || ([nextWindow isVisible] &&
                (((unsigned int)[nextWindow styleMask] & NSResizableWindowMask) != 0)))) {
            [nextWindow makeKeyAndOrderFront:self];
            return;
        }
        index += direction;
    }
}

- (void)killZone:(NSZone *)zone
{
    NSRecycleZone(zone);
}

- (id)lazyDestroyZone:(NSZone *)zone wait:(double)wait
{
    NSMethodSignature *signature;
    NSInvocation *invocation;

    signature = [self methodSignatureForSelector:@selector(killZone:)];
    invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:self];
    [invocation setSelector:@selector(killZone:)];
    [invocation setArgument:&zone atIndex:2];
    return [NSTimer scheduledTimerWithTimeInterval:wait
        invocation:invocation repeats:NO];
}

- (BOOL)hasPrefManager
{
    return prefManager != nil;
}

- (BOOL)doingForcedQuit
{
    return (_terminalAppFlags.raw & 0x00ffff00) != 0;
}

- (void)monStart:(id)sender
{
}

- (void)monStop:(id)sender
{
}

@end
