#import "StartupController.h"

#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSZone.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSForm.h>
#import <AppKit/NSOpenPanel.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSButtonCell.h>

#include <string.h>
#include <unistd.h>

#import "TerminalApp.h"

extern id _theDefaultsObject;

@interface NSObject (StartupControllerActions)
- (void)setUpButtons:(int)count;
@end

@implementation StartupController

- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults
{
    (void)defaults;
}

- (void)showDefault:(char)show
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    int action;
    NSString *file;

    (void)show;
    [defaults synchronize];
    action = [defaults integerForKey:@"StartupAction"];
    if (action < 0) {
        action = 0;
        [defaults setInteger:action forKey:@"StartupAction"];
    } else if (action > 2) {
        action = 2;
        [defaults setInteger:action forKey:@"StartupAction"];
    }
    file = [defaults stringForKey:@"StartupFile"];
    if (file == nil)
        file = @"";
    [self setAction:action file:[file cString]
        fastLaunch:(char)[defaults boolForKey:@"FastLaunch"] lockRevert:1];
}

- (void)setAction:(int)action file:(const char *)file
    fastLaunch:(char)fastLaunch lockRevert:(char)lockRevert
{
    NSString *path;
    NSZone *zone;
    size_t length;

    (void)[actionMatrix selectCellWithTag:action];
    path = [NSString stringWithCString:file];
    [[pathForm cellAtIndex:0] setStringValue:path];
    [fastAutolaunchCheck setState:fastLaunch];

    if (lockRevert) {
        zone = [self zone];
        if (revertStartupFile != NULL)
            NSZoneFree(zone, revertStartupFile);
        length = strlen(file);
        revertStartupFile = (char *)NSZoneMalloc(zone,
            (unsigned int)(length + 1));
        if (revertStartupFile == NULL) {
            [NSException raise:NSMallocException
                format:@"Couldn't malloc space for file name."];
        }
        strcpy(revertStartupFile, file);
        revertAction = action;
        revertFastLaunch = (unsigned char)fastLaunch;
    }
}

- (void)suggest
{
    [self setAction:1 file:"" fastLaunch:1 lockRevert:0];
    [(id)NSApp updateWindows];
}

- (void)revert
{
    [actionMatrix selectCellWithTag:revertAction];
    [[pathForm cellAtIndex:0] setStringValue:
        [NSString stringWithCString:revertStartupFile]];
    [fastAutolaunchCheck setState:revertFastLaunch];
    [(id)NSApp updateWindows];
}

- (void)setStruct:(TerminalEmulationDefaults *)defaults
{
    (void)defaults;
}

- (char)checkSettings
{
    id selected = [actionMatrix selectedCell];
    const char *path;
    NSString *title;
    NSString *message;
    NSString *useAnyway;
    NSString *cancel;

    if ([selected tag] != 2)
        return 1;
    path = [[[pathForm cellAtIndex:0] stringValue] cString];
    title = NSLocalizedString(@"Save Settings", @"");
    if (path == NULL || strlen(path) == 0) {
        message = NSLocalizedString(@"You've asked that a file be opened when Terminal starts up, but haven't specified which file.  Type the file's path into the Path form, or press the Set button to bring up the Open panel.", @"");
        NSRunAlertPanel(title, message, nil, nil, nil);
        return 0;
    }
    if (access(path, F_OK) != 0) {
        message = NSLocalizedString(
            @"The file you've specified doesn't seem to exist.", @"");
    } else if (access(path, R_OK) != 0) {
        message = NSLocalizedString(
            @"The file you've specified exists, but you can't read it.", @"");
    } else {
        return 1;
    }
    useAnyway = NSLocalizedString(@"Use Anyway", @"");
    cancel = NSLocalizedString(@"Cancel", @"");
    return NSRunAlertPanel(title, message, useAnyway, cancel, nil) == 1;
}

- (void)firstVisible:(id)sender
{
    [sender setUpButtons:24];
    [self showDefault:1];
}

- (void)lastVisible:(id)sender
{
    (void)sender;
}

- (id)startupFilesChanged:(id)sender
{
    id file = [sender selectedCell];

    if (file != nil) {
        id value = [file objectValue];

        if (value != nil && [value cString] != NULL)
            [[pathForm cellAtIndex:0] setStringValue:value];
    }
    return self;
}

- (void)setPathRequest:(id)sender
{
    id panel = [NSOpenPanel openPanel];
    NSString *directory = [[pathForm cellAtIndex:0] stringValue];
    NSString *selected;

    if (directory == nil || access([directory cString], F_OK) != 0)
        directory = @"/";
    [panel setDirectory:directory];
    if ([panel runModalForTypes:nil] != NSOKButton)
        return;
    selected = [panel filename];
    if (selected != nil) {
        [[pathForm cellAtIndex:0] setStringValue:selected];
        [self pathWasSet:self];
    }
    (void)sender;
}

- (void)pathWasSet:(id)sender
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    const char *path = [[[pathForm cellAtIndex:0] stringValue] cString];
    id selected;

    (void)sender;
    [actionMatrix selectCellWithTag:
        path != NULL && strlen(path) != 0 ? 2 : 1];
    if ([self checkSettings]) {
        selected = [actionMatrix selectedCell];
        [defaults setInteger:[selected tag] forKey:@"StartupAction"];
        [defaults setObject:[[pathForm cellAtIndex:0] stringValue]
            forKey:@"StartupFile"];
    }
}

- (void)fastStartupChanged:(id)sender
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;

    (void)sender;
    [defaults setBool:(BOOL)[(NSButtonCell *)fastAutolaunchCheck state]
        forKey:@"FastLaunch"];
}

- (void)startupActionChanged:(id)sender
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    id selected;
    int action;

    (void)sender;
    selected = [actionMatrix selectedCell];
    action = [selected tag];
    [defaults setInteger:action forKey:@"StartupAction"];
    if (action == 2)
        [pathForm selectTextAtIndex:0];
}

- (id)setDefault
{
    return self;
}

- (void)forceSetDefault
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;
    id selected = [actionMatrix selectedCell];

    [defaults setInteger:[selected tag] forKey:@"StartupAction"];
    [defaults setObject:[[pathForm cellAtIndex:0] stringValue]
        forKey:@"StartupFile"];
    [defaults setBool:(BOOL)[(NSButtonCell *)fastAutolaunchCheck state]
        forKey:@"FastLaunch"];
}

- (void)savePanelDidChangeStartupDefaults:(id)sender
{
    (void)sender;
    [self forceSetDefault];
}

@end
