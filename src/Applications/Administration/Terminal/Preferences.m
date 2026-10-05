#import "Preferences.h"
#import <AppKit/NSMatrix.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSNibLoading.h>
#import <Foundation/NSBundle.h>
#import <math.h>


@interface Preferences (PreferencesPaneActions)
- (void)reflectChoiceOfPane:(int)tag;
- (void)setUpButtons:(int)count;
@end

@interface Preferences (PreferencesDefaultActions)
- (void)showDefault:(BOOL)show;
@end

@implementation Preferences

- (id)init
{
    id initialized;
    id bundle;
    id nibPath;
    id ownerTable;

    initialized = [super init];
    bundle = [NSBundle bundleForClass:[self class]];
    nibPath = [bundle pathForResource:@"Preferences" ofType:@"nib"];
    ownerTable = [NSDictionary dictionaryWithObjectsAndKeys:self,
        @"NSOwner", nil];
    [NSBundle loadNibFile:nibPath externalNameTable:ownerTable
        withZone:[self zone]];

    controllers[0] = [windowCntl delegate];
    controllers[1] = [titleBarCntl delegate];
    controllers[2] = [emulationCntl delegate];
    controllers[3] = [miscCntl delegate];
    controllers[4] = [processMonitorCntl delegate];
    controllers[5] = [shellCntl delegate];
    controllers[6] = [startupCntl delegate];
    controllers[7] = [textAttrCntl delegate];

    subPanes[0] = [windowPane delegate];
    subPanes[1] = [titleBarPane delegate];
    subPanes[2] = [emulationPane delegate];
    subPanes[3] = [miscPane delegate];
    subPanes[4] = [processMonitorPane delegate];
    subPanes[5] = [shellPane delegate];
    subPanes[6] = [startupPane delegate];
    subPanes[7] = [textAttrPane delegate];

    [self setCurrentTerminal:nil];
    installedPane = nil;
    [self reflectChoiceOfPane:0];
    return initialized;
}

- (void)setUpButtons:(int)flags
{
    BOOL enableOK;
    id contentView;

    shouldEnableOKIfPossible = (char)(flags & 1);
    enableOK = (flags & 1) != 0 && currentTerminal != nil;
    [okButton setEnabled:enableOK];
    [setDefaultButton setEnabled:(flags & 2) != 0];
    [showDefaultButton setEnabled:(flags & 4) != 0];
    [suggestButton setEnabled:(flags & 8) != 0];
    [revertButton setEnabled:(flags & 16) != 0];

    if ((flags & ~0x18) != 0) {
        if ([buttonMatrix superview] == nil) {
            contentView = [window contentView];
            [contentView addSubview:buttonMatrix];
            [buttonMatrix display];
        }
    } else {
        if ([buttonMatrix superview] != nil) {
            [buttonMatrix removeFromSuperview];
            [buttonMatrix display];
        }
        [window display];
    }
}

- (void)revert:(id)sender
{
    if (installedController == nil)
        NSLog(@"No current controller during revert.");

    [window disableFlushWindow];
    [installedController revert:sender];
    [window enableFlushWindow];
    [[window contentView] setNeedsDisplay:YES];
}

- (void)setDefaultX:(id)sender
{
    if (installedController == nil)
        NSLog(@"No current controller during setDefault.");

    [installedController setDefault:sender];
    [NSApp updateWindows];
}

- (void)ok:(id)sender
{
    id defaults;

    if (installedController == nil)
        NSLog(@"No current controller during ok.");
    if (currentTerminal == nil)
        NSLog(@"No current terminal during ok.");

    defaults = [currentTerminal defaults];
    [installedController setStruct:defaults];
    [currentTerminal setDefaults:defaults];
}

- (void)suggest:(id)sender
{
    if (installedController == nil)
        NSLog(@"No current controller during suggest.");

    [window disableFlushWindow];
    [installedController suggest:sender];
    [window enableFlushWindow];
    [[window contentView] setNeedsDisplay:YES];
}

- (void)showDefault:(BOOL)show
{
    if (installedController == nil)
        NSLog(@"No controller during showDefault.");

    [window disableFlushWindow];
    [installedController showDefault:show];
    [window enableFlushWindow];
    [[window contentView] setNeedsDisplay:YES];
}

- (void)setCurrentTerminal:(id)terminal
{
    id notificationCenter;
    id terminalWindow;

    if (currentTerminal != terminal) {
        notificationCenter = [NSNotificationCenter defaultCenter];
        if (currentTerminal != nil) {
            terminalWindow = [currentTerminal window];
            [notificationCenter removeObserver:self
                name:NSWindowWillCloseNotification object:terminalWindow];
        }
        currentTerminal = terminal;
        if (terminal != nil) {
            terminalWindow = [terminal window];
            [notificationCenter addObserver:self
                selector:@selector(windowWillClose:)
                name:NSWindowWillCloseNotification object:terminalWindow];
        }
    }
    [okButton setEnabled:currentTerminal != nil];
}

- (void)terminalDidBecomeMain:(id)terminal
{
    id defaults;

    if (installedController == nil)
        NSLog(@"No controller for activation.");

    defaults = [terminal defaults];
    [installedController setFromStruct:defaults];
    [okButton setEnabled:shouldEnableOKIfPossible];
    [self setCurrentTerminal:terminal];
}

- (void)terminalDidResignMain:(id)terminal
{
    (void)terminal;
    [okButton setEnabled:NO];
    [self setCurrentTerminal:nil];

    if ([(id)NSApp prefWindowVisible]) {
        [window disableFlushWindow];
        if (installedController == nil)
            NSLog(@"No controller for resignation.");
        [self performSelector:@selector(doFlush)
            withObject:nil afterDelay:0.1];
    }
}

- (id)okButton
{
    return okButton;
}

- (id)currentTerminal
{
    return currentTerminal;
}

- (void)doFlush
{
    [window enableFlushWindow];
    [[window contentView] setNeedsDisplay:YES];
}

- (void)handleReturnByProxy:(id)sender
{
    if ([okButton isEnabled])
        [okButton performClick:sender];
}

- (void)showPrefWindow:(id)sender
{
    [window makeKeyAndOrderFront:self];
    if (installedController != nil)
        [installedController firstVisible:self];
}

- (void)changePane:(id)sender
{
    [self reflectChoiceOfPane:[(NSControl *)sender selectedTag]];
}

- (void)reflectChoiceOfPane:(int)tag
{
    id paneItem;
    NSRect containerBounds;
    NSRect paneBounds;
    NSPoint paneOrigin;
    id defaults;

    if (installedPane == subPanes[tag])
        return;

    [window disableFlushWindow];
    paneItem = [paneSelector itemWithTag:tag];
    [paneSelector setTitle:[paneItem title]];

    if (installedPane != nil) {
        if (installedController == nil)
            NSLog(@"Installed pane has no controller.");
        [window endEditingFor:nil];
        [installedController lastVisible:self];
        [installedPane retain];
        [installedPane removeFromSuperview];
    }

    installedPane = subPanes[tag];
    installedController = controllers[tag];
    [container addSubview:installedPane];

    containerBounds = [container bounds];
    paneBounds = [installedPane bounds];
    paneOrigin.x = (float)floor((containerBounds.size.width - paneBounds.size.width) / 2.0);
    paneOrigin.y = (float)floor((containerBounds.size.height - paneBounds.size.height) / 2.0);
    [installedPane setFrameOrigin:paneOrigin];
    [installedController firstVisible:self];

    if (currentTerminal != nil) {
        defaults = [currentTerminal defaults];
        [installedController setFromStruct:defaults];
    } else {
        [installedController showDefault:YES];
        [okButton setEnabled:NO];
    }

    [container display];
    [window enableFlushWindow];
    [[window contentView] setAutoresizesSubviews:YES];
}

- (void)showDefaultX:(id)sender
{
    [self showDefault:NO];
}

- (void)windowDidBecomeKey:(id)notification
{
    if (installedController != nil &&
        [installedController respondsToSelector:@selector(windowDidBecomeKey:)])
        [installedController windowDidBecomeKey:notification];
}

- (void)windowWillClose:(id)notification
{
    [self setCurrentTerminal:nil];
}

- (BOOL)windowShouldClose:(id)sender
{
    [(id)NSApp setPrefWindowVisible:NO];
    if (installedController != nil)
        [installedController lastVisible:self];
    return YES;
}

- (void)windowDidResignKey:(id)notification
{
    if (installedController != nil &&
        [installedController respondsToSelector:@selector(windowDidResignKey:)])
        [installedController windowDidResignKey:notification];
}

- (id)notifyController:(SEL)selector withArg:(id)arg
{
    if (installedController != nil &&
        [installedController respondsToSelector:selector])
        return [installedController performSelector:selector withObject:arg];
    return nil;
}

@end
