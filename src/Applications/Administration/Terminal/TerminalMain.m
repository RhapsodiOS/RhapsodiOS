#import "TerminalApp.h"

#import <AppKit/NSPanel.h>
#import <AppKit/NSNibLoading.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSPathUtilities.h>

#include <stdlib.h>
#include <unistd.h>

#include "ProcessIdentity.h"
#include "TerminalLaunch.h"

static const char *terminalProcessNamePath(void)
{
    return [[[NSProcessInfo processInfo] processName] cString];
}

int main(int argc, char **argv, char **environment)
{
    NSAutoreleasePool *pool;
    NSApplication *application;
    NSString *bundlePath;
    NSString *nibPath;
    NSDictionary *ownerTable;
    NSString *argumentPath;

    (void)argc;
    (void)argv;
    (void)environment;

    TerminalSaveProcessIdentity((unsigned int)getuid(),
        (unsigned int)geteuid(), (unsigned int)getgid());
    become_user();

    pool = [[NSAutoreleasePool alloc] init];
    bundlePath = [[NSBundle mainBundle] bundlePath];
    if (access([bundlePath cString], 4) == -1) {
        argumentPath = [[[[NSProcessInfo processInfo] arguments]
            objectAtIndex:0] stringByDeletingLastPathComponent];
        if (!TerminalCheckWrapperLaunch([argumentPath cString], chdir,
                terminalProcessNamePath, access)) {
            NSRunAlertPanel(@"No Wrapper",
                @"Terminal must be run from the Workspace Manager.",
                @"", nil, nil);
            exit(0);
        }
    }

    application = [TerminalApp sharedApplication];
    nibPath = [[NSBundle mainBundle] pathForResource:@"WindowTop"
        ofType:@"tiff"];
    if (nibPath != nil) {
        ownerTable = [NSDictionary dictionaryWithObjectsAndKeys:application,
            @"NSOwner", nil];
        [NSBundle loadNibFile:nibPath externalNameTable:ownerTable
            withZone:[application zone]];
    }
    [application run];
    [pool release];
    exit(0);
    return 0;
}
