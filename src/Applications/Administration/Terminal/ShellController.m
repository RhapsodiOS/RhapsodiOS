#import "ShellController.h"

#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSZone.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSForm.h>
#import <AppKit/NSPanel.h>

#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#import "TerminalApp.h"

extern id _theDefaultsObject;

@interface NSObject (ShellControllerButtons)
- (void)setUpButtons:(int)count;
@end

@implementation ShellController

- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults
{
    (void)defaults;
}

- (void)showDefault:(char)show
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;

    (void)show;
    [defaults synchronize];
    [self setShell:[(TerminalApp *)NSApp shell]
        source:(char)[defaults boolForKey:@"SourceDotLogin"]];
}

- (void)setShell:(const char *)shell source:(char)source
{
    [[shellForm cellAtIndex:0] setStringValue:
        [NSString stringWithCString:shell]];
    [sourceCheck setState:source];
}

- (void)revert
{
    [NSException raise:NSInvalidArgumentException
        format:@"*** Method not implemented: %s", sel_getName(_cmd)];
}

- (id)setDefault
{
    [NSException raise:NSInvalidArgumentException
        format:@"*** Method not implemented: %s", sel_getName(_cmd)];
    return self;
}

- (void)suggest
{
    [NSException raise:NSInvalidArgumentException
        format:@"*** Method not implemented: %s", sel_getName(_cmd)];
}

- (void)setStruct:(TerminalEmulationDefaults *)defaults
{
    (void)defaults;
    [NSException raise:NSInvalidArgumentException
        format:@"*** Method not implemented: %s", sel_getName(_cmd)];
}

- (char)checkSettings
{
    const char *shell = (const char *)[[shellForm cellAtIndex:0] cString];
    NSZone *zone = [self zone];
    size_t length = strlen(shell);
    char *path = (char *)NSZoneMalloc(zone, (unsigned int)(length + 1));
    char *separator;
    NSString *title;
    NSString *message;
    struct stat status;

    strcpy(path, shell);
    separator = strpbrk(path, " \t\n\r");
    if (separator != NULL && separator >= path)
        *separator = '\0';

    if (access(path, F_OK) == -1) {
        title = NSLocalizedString(@"Nonexistent shell", @"");
        message = NSLocalizedString(@"The file '%s' doesn't exist.", @"");
    } else if (access(path, X_OK) != 0) {
        title = NSLocalizedString(@"Inappropriate shell", @"");
        message = NSLocalizedString(
            @"You don't have permission to execute '%s'.", @"");
    } else if (stat(path, &status) == -1) {
        title = NSLocalizedString(@"Cannot Stat", @"");
        message = NSLocalizedString(@"Could not stat '%s'.", @"");
    } else if ((status.st_mode & S_IFMT) == S_IFREG) {
        free(path);
        return 1;
    } else {
        title = NSLocalizedString(@"Inappropriate shell", @"");
        message = NSLocalizedString(
            @"The file '%s' isn't an executable program.", @"");
    }

    NSRunAlertPanel(title, message, nil, nil, nil, path);
    [shellForm selectTextAtIndex:0];
    free(path);
    return 0;
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

- (void)shellChanged:(id)sender
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;

    (void)sender;
    if ([self checkSettings]) {
        NSString *shell = [[shellForm cellAtIndex:0] stringValue];
        [defaults setObject:shell forKey:@"Shell"];
    }
}

- (void)sourceDotLoginChanged:(id)sender
{
    NSUserDefaults *defaults = (NSUserDefaults *)_theDefaultsObject;

    (void)sender;
    [defaults setBool:[sourceCheck state] forKey:@"SourceDotLogin"];
}

@end
