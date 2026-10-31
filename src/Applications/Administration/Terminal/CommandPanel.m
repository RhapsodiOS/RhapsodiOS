#import "CommandPanel.h"

#import <AppKit/NSForm.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSNibLoading.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSData.h>
#import <Foundation/NSObjCRuntime.h>

#import "TerminalApp.h"

@implementation CommandPanel

- (void)showPanel
{
    id command;
    id defaults;
    id cell;
    id window;

    if (commandForm == nil) {
        if (![NSBundle loadNibNamed:@"CommandPanel" owner:self]) {
            NSLog(@"%@: Unable to load nib", self);
            return;
        }

        defaults = [NSUserDefaults standardUserDefaults];
        command = [defaults stringForKey:@"LastCommand"];
        if (command != nil) {
            cell = [commandForm cellAtIndex:0];
            [cell setStringValue:command];
            commandHistory[0] = [command copyWithZone:[self zone]];
            currentIndex = 0;
            lastIndex = 0;
        }
    }

    window = [commandForm window];
    [window center];
    [window makeKeyAndOrderFront:nil];
    [window setDelegate:self];
    [commandForm selectTextAtIndex:0];
}

- (void)commandEntered:(id)sender
{
    id cell;
    id command;
    id data;
    id controller;
    id application;
    id terminal;
    id defaults;
    NSStringEncoding encoding;
    unsigned length;
    char *commandBytes;

    (void)sender;
    cell = [commandForm cellAtIndex:0];
    command = [cell stringValue];
    encoding = [NSString defaultCStringEncoding];
    data = [command dataUsingEncoding:encoding allowLossyConversion:1];
    controller = [commandForm window];
    [controller setDelegate:self];

    length = [data length];
    if (command == nil || data == nil || length == 0) {
        NSBeep();
        return;
    }

    commandBytes = alloca(length + 1);
    [data getBytes:commandBytes length:length];
    commandBytes[length] = '\0';

    application = [TerminalApp sharedApplication];
    terminal = [(TerminalApp *)application newShell:commandBytes];
    if (terminal != nil) {
        defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:command forKey:@"LastCommand"];
    }

    if (commandHistory[lastIndex] == nil ||
        ![commandHistory[lastIndex] isEqualToString:command]) {
        lastIndex = (lastIndex + 1) % 10;
        [commandHistory[lastIndex] release];
        commandHistory[lastIndex] = [command copyWithZone:[self zone]];
    }
    currentIndex = lastIndex;
}

- (char)control:(id)control textView:(id)textView
    doCommandBySelector:(SEL)selector
{
    int step;
    int index;
    id field;

    if (selector == @selector(moveUp:))
        step = 9;
    else if (selector == @selector(moveDown:))
        step = 1;
    else {
        if (selector == @selector(complete:)) {
            field = [commandForm currentEditor];
            [field setDelegate:self];
        }
        return 0;
    }

    index = currentIndex;
    do {
        index = (index + step) % 10;
        if (index == currentIndex)
            break;
        if (commandHistory[index] != nil) {
            currentIndex = index;
            field = [commandForm cellAtIndex:0];
            [field setStringValue:commandHistory[currentIndex]];
            [commandForm selectTextAtIndex:0];
            return 1;
        }
    } while (1);

    NSBeep();
    (void)control;
    return 0;
}

@end
