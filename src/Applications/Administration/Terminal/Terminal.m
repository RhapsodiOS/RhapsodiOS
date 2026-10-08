#import "Terminal.h"
#import "Shell.h"
#import "TerminalApp.h"
#import "TString.h"
#import "WindowTitle.h"
#import "FilerObjC.h"
#import "MutableEvent.h"
#include "DebugDPS.h"
#include "TerminalScreen.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSFontPanel.h>
#import <AppKit/NSDPSServerContext.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>
#import <objc/objc-runtime.h>
#include <AppKit/dpsOpenStep.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>

extern id _theDefaultsObject;

#import "DirtMonitor.h"

@implementation Terminal

- (BOOL)setUpWithDefaults:(const TerminalEmulationDefaults *)defaults
    inFolder:(const char *)folder env:(char **)environment
{
    Shell *newShell;
    Emulation *newEmulator;
    NSImage *image;
    NSBundle *bundle;
    NSString *title;
    NSString *message;
    int result;
    DirtMonitor *dirtMonitor;

    newShell = [[Shell allocWithZone:[self zone]] init];
    shell = newShell;
    [shell setTarget:self];
    newEmulator = [[(defaults->var5 ? [vt100 class] : [vt52 class])
        allocWithZone:[self zone]] initDefaults:defaults];
    emulator = newEmulator;
    [emulator setTerminal:self];
    [emulator setDefaults:defaults];
    image = [NSImage imageNamed:@"TerminalTitle"];

    evflags &= ~0x20;
    deadMeat = 0;
    enablePSOutput = 0;
    debugging = 0;
    isMiniaturized = 0;
    serviceOwner = -1;
    def = (void *)defaults;
    shellDevice = -1;
    defaultCStringEncoding = (unsigned int)[NSString defaultCStringEncoding];
    [super setUpWithDefaults:defaults];

    result = [shell system:defaults->var10 login:defaults->var4
        folder:folder env:environment];
    if (result) {
        shellDevice = [shell slaveMinorDevice];
        dirtMonitor = [(TerminalApp *)NSApp dirtMonitor];
        [dirtMonitor registerDevice:shellDevice withFD:[shell fd]];
        [shell setExitAction:@selector(childExit:status:)];
        if (![_theDefaultsObject boolForKey:@"SourceDotLogin"]) {
            [dirtMonitor setShellsClean:[_theDefaultsObject
                boolForKey:@"ShellsClean"]
                runningBackgroundClean:[_theDefaultsObject
                    boolForKey:@"RunningBackgroundClean"]
                fastAudits:[_theDefaultsObject boolForKey:@"FastAudits"]
                cleanCommands:[(TerminalApp *)NSApp cleanCommands]];
        }
        if ([_theDefaultsObject boolForKey:@"MonitorProcs"]) {
            dirtUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:0.1
                target:self selector:@selector(updateDirtIfNeeded)
                userInfo:self repeats:YES] retain];
        }
        fileName = NULL;
        return YES;
    }

    deadMeat = 1;
    bundle = [NSBundle mainBundle];
    title = [bundle localizedStringForKey:@"New Shell"
        value:@"New Shell" table:nil];
    message = [bundle localizedStringForKey:
        @"Couldn't start up the shell you requested.  Check to be sure that it exists and that you can execute it."
        value:@"Couldn't start up the shell you requested.  Check to be sure that it exists and that you can execute it."
        table:nil];
    NSRunAlertPanel(title, message, NULL, NULL, NULL);
    return NO;
}

- (void)setDefaults:(const TerminalEmulationDefaults *)defaults
{
    NSWindow *window;
    DirtMonitor *dirtMonitor;
    NSColor *color;
    NSString *colorSpace;
    unsigned int flags;
    unsigned int index;

    if (defaults != def) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd
            object:self
            file:[NSString stringWithCString:"Terminal.m"]
            lineNumber:145
            description:@"Tried to change defaults struct on the fly."];
    }

    evflags = (evflags & 0x7F) | ((defaults->var6 & 1) << 7);
    evflags = (evflags & 0xBF) | ((defaults->var0 & 1) << 6);
    saveLines = defaults->var17;

    window = [self window];
    if (![_theDefaultsObject boolForKey:@"MonitorProcs"] || deadMeat) {
        [window setDocumentEdited:NO];
    } else {
        dirtMonitor = [(TerminalApp *)NSApp dirtMonitor];
        [window setDocumentEdited:[dirtMonitor isDeviceDirty:shellDevice]];
    }

    [emulator setDefaults:defaults];
    for (index = 0; index < 4; ++index) {
        if (textColor[index] != nil)
            [textColor[index] release];
        color = (NSColor *)defaults->var19[index];
        colorSpace = [color colorSpaceName];
        textColor[index] = [[color colorUsingColorSpaceName:colorSpace] copy];
    }
    for (index = 0; index < 3; ++index) {
        if (backColor[index] != nil)
            [backColor[index] release];
        color = (NSColor *)defaults->var19[index + 4];
        colorSpace = [color colorSpaceName];
        backColor[index] = [[color colorUsingColorSpaceName:colorSpace] copy];
    }
    if (cursorColor != nil)
        [cursorColor release];
    color = (NSColor *)defaults->var19[7];
    colorSpace = [color colorSpaceName];
    cursorColor = [[color colorUsingColorSpaceName:colorSpace] copy];

    flags = TERMINAL_FIELD_FLAGS(self);
    flags = (flags & ~0x00080000u) |
        ((defaults->var20 & 8) != 0 ? 0x00080000u : 0);
    flags = (flags & ~0x00040000u) |
        ((defaults->var20 & 4) != 0 ? 0x00040000u : 0);
    TERMINAL_FIELD_SET_FLAGS(self, flags);
    cursorShape = (cursorShape & 0x10) | (defaults->var20 & 3);

    [super setDefaults:defaults];
    [self windowHook:height :cursorx];
}

- (void)invalidate
{
    if (enablePSOutput == 0) {
        [super invalidate];
        [[self window] setDocumentEdited:NO];
        [self cursorBlink:0];
        [self cancelDelayedPerforms];
        [self removeDirtTimers];
        if (shellDevice != -1)
            [[(TerminalApp *)NSApp dirtMonitor] unregisterDevice:shellDevice];
        [shell setTarget:nil];
        [shell close];
        [shell release];
        [emulator release];
        deadMeat = 1;
    }
}

- (void)windowDidBecomeMain:(id)notification
{
    TerminalApp *application;

    application = (TerminalApp *)NSApp;
    if ([application prefWindowVisible]) {
        id preferenceManager = [application prefManager];
        ((void (*)(id, SEL, id))objc_msgSend)(preferenceManager,
            @selector(terminalDidBecomeMain:), self);
    }

    [super windowDidBecomeMain:notification];
}

- (void)windowDidResignMain:(id)notification
{
    TerminalApp *application;

    (void)notification;
    application = (TerminalApp *)NSApp;
    if ([application hasPrefManager]) {
        id preferenceManager = [application prefManager];
        ((void (*)(id, SEL, id))objc_msgSend)(preferenceManager,
            @selector(terminalDidResignMain:), self);
    }
}

- (void)mouseEntered:(id)event
{
    if ([event trackingNumber] == debugTag) {
        wasActive = (unsigned char)[(TerminalApp *)NSApp isActive];
        if (wasActive == 0) {
            getActiveApp(&activeApp);
            [[self window] makeKeyWindow];
            debugActivate();
        }
    }
}

- (void)mouseExited:(id)event
{
    if ([event trackingNumber] == debugTag && wasActive == 0)
        debugDeactivate(activeApp);
}

- (void)debugToggle:(id)sender
{
    NSView *contentView;
    NSRect contentFrame;

    (void)sender;
    if (debugging) {
        debugging = 0;
        [self windowHook:height :cursorx];
        if (!wasActive)
            debugDeactivate(activeApp);
        contentView = [[self window] contentView];
        [contentView removeTrackingRect:debugTag];
    } else {
        debugging = 1;
        [self windowHook:height :cursorx];
        contentView = [[self window] contentView];
        contentFrame = [contentView frame];
        debugTag = [contentView addTrackingRect:contentFrame owner:self
            userData:NULL assumeInside:NO];
        wasActive = (unsigned char)[(TerminalApp *)NSApp isActive];
    }
    [(TerminalApp *)NSApp setWindowStatus:1
        withScroller:(TERMINAL_FIELD_FLAGS(self) & 0x08000000u) != 0
        debug:debugging setMember:sharesSettingsFile];
}

- (void)getExtraWinInfo:(struct TerminalExtraWindowInfo *)info
{
    NSWindow *window = [self window];
    NSRect windowFrame = [window frame];
    NSRect screenFrame = [[window screen] frame];

    info->x = windowFrame.origin.x / screenFrame.size.width;
    info->y = windowFrame.origin.y / screenFrame.size.height;
    info->hidden = ![window isVisible];
}

- (void)windowDidBecomeKey:(id)notification
{
    (void)notification;
    [(TerminalApp *)NSApp setWindowStatus:1
        withScroller:(TERMINAL_FIELD_FLAGS(self) & 0x08000000u) != 0
        debug:debugging setMember:sharesSettingsFile];
    [NSDPSServerContext setDeadKeyProcessingEnabled:
        ([(Emulation *)emulator metaCharacter] & 0x8000) != 0];
    [self cursorBlink:1];

    if ((evflags & 0x20) == 0) {
        if (invalidated) {
            [self lockFocus];
            cursorShape &= ~0x10;
            [self _cursor];
            [self unlockFocus];
            [[self window] flushWindow];
        }
        evflags |= 0x20;
    }
}

- (void)windowDidResignKey:(id)notification
{
    (void)notification;
    [(TerminalApp *)NSApp setWindowStatus:0 withScroller:0 debug:0
        setMember:0];
    [NSDPSServerContext setDeadKeyProcessingEnabled:YES];
    [self cursorBlink:0];

    if ((evflags & 0x20) != 0) {
        if (!isMiniaturized && invalidated) {
            [self lockFocus];
            cursorShape |= 0x10;
            [self _cursor];
            [self unlockFocus];
            [[self window] flushWindow];
        }
        evflags &= ~0x20;
    }
}

- (void)cancelDelayedPerforms
{
    [NSRunLoop cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(_delayedCursor:) object:self];
    [NSRunLoop cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(displayWindowStatus:) object:self];
    [NSRunLoop cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(redisplayTitle:) object:self];
}

- (void)dealloc
{
    [self removeDirtTimers];
    [(TerminalApp *)NSApp lazyDestroyZone:[self zone] wait:NO];
    [super dealloc];
}

- (void)setTitle:(NSString *)title
{
    TerminalEmulationDefaults *defaults = (TerminalEmulationDefaults *)def;

    [(TString *)defaults->var16 empty];
    defaults->var15 = (title != nil &&
        ![title isEqualToString:@"Custom Title"]) ? 8 : 0;
    [self redisplayTitle:self];
}

- (void)setCustomTitle:(const char *)title
{
    TerminalEmulationDefaults *defaults = (TerminalEmulationDefaults *)def;
    NSString *string = [NSString stringWithCString:title];

    [(TString *)defaults->var16 setStringValue:string];
    if (title != NULL && strlen(title) != 0)
        defaults->var15 |= 8;
    else
        defaults->var15 &= 0xF7;
    [self redisplayTitle:self];
}

- (void)redisplayTitle:(id)sender
{
    (void)sender;
    [self windowHook:height :cursorx];
}

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)size
{
    TerminalEmulationDefaults *defaults =
        (TerminalEmulationDefaults *)def;
    unsigned char oldTitleBits = defaults->var15;
    NSSize constrainedSize;

    defaults->var15 = 4;
    constrainedSize = [super windowWillResize:window toSize:size];
    defaults->var15 = oldTitleBits;

    [self displayWindowStatus:self];
    [self performSelector:@selector(windowHook::) withObject:self
        afterDelay:0.5];
    return constrainedSize;
}

- (void)windowHook:(unsigned int)columns :(unsigned int)rows
{
    TerminalEmulationDefaults *defaults;
    NSString *title;
    char *titleBytes;

    defaults = (TerminalEmulationDefaults *)def;
    if (deadMeat) {
        title = [[NSBundle mainBundle] localizedStringForKey:@"Dead Terminal"
            value:@"\n\r[Process exited - exit code %u]" table:nil];
    } else {
        titleBytes = winTitle([shell command], [shell pty], columns, rows,
            defaults->var15, debugging,
            [[(TString *)defaults->var16 stringValue] cString], fileName);
        title = [NSString stringWithCString:titleBytes];
    }
    [[self window] setTitle:title];
}

- (void)updateDirtIfNeeded
{
    NSWindow *window;
    DirtMonitor *dirtMonitor;

    if ([_theDefaultsObject boolForKey:@"MonitorProcs"] && !deadMeat) {
        if (!isMiniaturized && needsDirtUpdate) {
            window = [self window];
            dirtMonitor = [(TerminalApp *)NSApp dirtMonitor];
            [window setDocumentEdited:[dirtMonitor isDeviceDirty:shellDevice]];
            needsDirtUpdate = 0;
        }
    } else {
        [[self window] setDocumentEdited:NO];
    }
}

- (id)scheduleUpdate
{
    NSDate *date;
    double now;

    if (longTermTimer != nil) {
        [longTermTimer invalidate];
        [longTermTimer release];
        longTermTimer = nil;
    }

    if (dirtUpdateTimer != nil) {
        date = [[NSDate allocWithZone:NULL] initWithTimeIntervalSinceNow:0];
        now = [date timeIntervalSinceReferenceDate];
        [date release];
        if (now + 0.4 - lastUpdateTime >= 2.5)
            return self;

        [dirtUpdateTimer invalidate];
        [dirtUpdateTimer release];
        dirtUpdateTimer = nil;
    }

    dirtUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:0.4
        target:self selector:@selector(handleDirtTimer:) userInfo:self
        repeats:YES] retain];
    return self;
}

- (void)handleDirtTimer:(id)sender
{
    DirtMonitor *dirtMonitor;
    NSWindow *window;
    NSDate *date;

    if (isMiniaturized || [NSApp isActive]) {
        needsDirtUpdate = 1;
    } else if ([_theDefaultsObject boolForKey:@"MonitorProcs"] && !deadMeat) {
        window = [self window];
        dirtMonitor = [(TerminalApp *)NSApp dirtMonitor];
        [window setDocumentEdited:[dirtMonitor isDeviceDirty:shellDevice]];
    }

    if (dirtUpdateTimer == sender) {
        [sender invalidate];
        [dirtUpdateTimer release];
        dirtUpdateTimer = nil;
    } else if (longTermTimer == sender) {
        [longTermTimer invalidate];
        [longTermTimer release];
        longTermTimer = nil;
    }

    date = [[NSDate allocWithZone:NULL] initWithTimeIntervalSinceNow:0];
    lastUpdateTime = [date timeIntervalSinceReferenceDate];
    [date release];
}

- (void)cursorBlink:(char)shouldBlink
{
    if (shouldBlink != 0 &&
        (TERMINAL_FIELD_FLAGS(self) & 0x00040000u) != 0 && invalidated != 0) {
        if (cursorBlinkTimer == nil) {
            cursorBlinkTimer = [[NSTimer scheduledTimerWithTimeInterval:0.6
                target:self selector:@selector(handleCursorBlinkTimer:)
                userInfo:self repeats:YES] retain];
        }
    } else if (cursorBlinkTimer != nil) {
        [cursorBlinkTimer invalidate];
        [cursorBlinkTimer release];
        cursorBlinkTimer = nil;
    }
}

- (void)handleCursorBlinkTimer:(id)sender
{
    NS_DURING
        [self lockFocus];
        if (TERMINAL_FIELD_FLAGS(self) & 0x00020000u)
            [self _clearcursor];
        else
            [self _cursor];
        [self unlockFocus];
        [[self window] flushWindow];
    NS_HANDLER
        NSLog(@"Exception %@ occurred while handling timer 0x%lx...invalidating timer",
              localException, (unsigned long)sender);
        [sender invalidate];
        [sender release];
        if (cursorBlinkTimer == sender)
            cursorBlinkTimer = nil;
    NS_ENDHANDLER
}

- (BOOL)isDead { return deadMeat ? YES : NO; }
- (BOOL)acceptsFirstResponder { return YES; }
- (id)defaults { return (id)def; }
- (NSWindow *)window { return [super window]; }
- (Shell *)shell { return shell; }
- (void)broadcastSize
{
    unsigned short windowSize[4];
    NSRect bounds;
    int fileDescriptor;

    bounds = [self bounds];
    windowSize[0] = cursorx;
    windowSize[1] = height;
    windowSize[2] = (unsigned short)bounds.size.width;
    windowSize[3] = (unsigned short)bounds.size.height;

    fileDescriptor = [shell fd];
    if (fileDescriptor > 0)
        ioctl(fileDescriptor, 0x80087467u, windowSize);
}
- (id)emulator { return emulator; }
- (void)setEmulator:(id)value { emulator = value; }
- (int)shellDevice { return shellDevice; }
- (int)serviceOwner { return serviceOwner; }
- (void)setServiceOwner:(int)value { serviceOwner = value; }
- (int)DOwinHandle { return DOwinHandle; }
- (void)setDOwinHandle:(int)value { DOwinHandle = value; }
- (char *)fileName { return fileName; }
- (BOOL)sharesFile { return sharesSettingsFile ? YES : NO; }
- (void)setFileName:(const char *)name sharesFile:(char)shares
{
    sharesSettingsFile = shares;
    if (name != fileName) {
        if (fileName != 0)
            free(fileName);
        if (name != 0 && strlen(name) != 0) {
            fileName = (char *)NSZoneMalloc([self zone], strlen(name) + 1);
            if (fileName == NULL) {
                [[NSAssertionHandler currentHandler]
                    handleFailureInMethod:_cmd
                    object:self
                    file:[NSString stringWithCString:"Terminal.m"]
                    lineNumber:133
                    description:@"Couldn't malloc space for file name."];
            }
            strcpy(fileName, name);
        } else {
            fileName = 0;
        }
        [self windowHook:height :cursorx];
    }
}

- (void)setSpringLoadedPaste:(char *)value
{
    if (springLoadedPaste != 0) {
        springLoadedPaste = (char *)NSZoneRealloc([self zone], springLoadedPaste,
            strlen(value) + strlen(springLoadedPaste) + 1);
        strcat(springLoadedPaste, value);
    } else {
        springLoadedPaste = (char *)NSZoneMalloc([self zone], strlen(value) + 1);
        strcpy(springLoadedPaste, value);
    }
}

- (void)output:(const char *)value
{
    [shell output:value];
}

- (void)output:(const char *)bytes len:(unsigned int)length
{
    [shell output:bytes len:length];
}

- (void)pasteText:(const char *)text
{
    unsigned int length;
    unsigned int index;
    char *mutableText;

    if (text == NULL)
        return;

    length = (unsigned int)strlen(text);
    if (length == 0)
        return;

    if ((evflags & 0x80) != 0) {
        mutableText = (char *)text;
        for (index = 0; index < length; index++) {
            if (mutableText[index] == '\n')
                mutableText[index] = '\r';
        }
    }

    [shell output:text len:length];
}

- (void)paste:(id)sender
{
    NSPasteboard *pasteboard;
    NSArray *pasteboardTypes;
    NSString *text;
    NSData *data;
    NSMutableData *mutableData;
    const unsigned char *bytes;
    unsigned char *mutableBytes;
    unsigned int length;
    unsigned int index;

    pasteboard = [NSPasteboard generalPasteboard];
    pasteboardTypes = [pasteboard types];
    if ([pasteboardTypes indexOfObject:NSStringPboardType] == NSNotFound)
        return;

    text = [pasteboard stringForType:NSStringPboardType];
    if (text == nil || [@"" isEqualToString:text])
        return;

    data = [text dataUsingEncoding:defaultCStringEncoding
        allowLossyConversion:YES];
    length = [data length];
    if ((evflags & 0x80) != 0 && length != 0) {
        bytes = [data bytes];
        mutableData = nil;
        mutableBytes = NULL;
        for (index = 0; index < length && bytes[index] == '\r'; index++) {
            if (mutableData == nil) {
                if ([data isKindOfClass:[NSMutableData class]]) {
                    mutableData = (NSMutableData *)data;
                } else {
                    mutableData = [[data mutableCopyWithZone:[self zone]]
                        autorelease];
                }
                mutableBytes = [mutableData mutableBytes];
            }
            mutableBytes[index] = '\n';
        }
        if (mutableData != nil)
            data = mutableData;
    }

    if ((evflags & 0x40) != 0 && topline < lines->count - cursorx) {
        [self lockFocus];
        [self scrollTo:lines->count - cursorx];
        [self unlockFocus];
    }
    [shell output:(const char *)[data bytes] len:length];
}

- (void)outputChar:(unsigned char)value
{
    [shell outputChar:value];
}

- (void)endOfFileOn:(id)sender
{
    [(Filer *)sender close];
    [(Filer *)sender release];
}

- (void)keyDown:(NSEvent *)event
{
    NSString *characters = [event characters];
    unsigned short key = [characters characterAtIndex:0];
    MutableEvent *mutableEvent =
        [MutableEvent mutableEventWithEvent:event];
    unsigned int modifierFlags = [mutableEvent modifierFlags];

    if ((modifierFlags & NSAlternateKeyMask) != 0 &&
        key >= NSUpArrowFunctionKey && key <= NSRightArrowFunctionKey) {
        BOOL shiftDown =
            ([mutableEvent modifierFlags] & NSShiftKeyMask) != 0;

        if (key == NSUpArrowFunctionKey) {
            if (shiftDown)
                [self pageUp];
            else
                [self lineUp];
        } else if (key == NSDownArrowFunctionKey) {
            if (shiftDown)
                [self pageDown];
            else
                [self lineDown];
        } else if (key == NSLeftArrowFunctionKey) {
            [(TerminalApp *)NSApp activateNext:self forward:YES
                includeMini:shiftDown];
        } else {
            [(TerminalApp *)NSApp activateNext:self forward:NO
                includeMini:shiftDown];
        }
        [[self window] flushWindow];
        PSWait();
        return;
    }

    if (deadMeat) {
        NSBeep();
        return;
    }

    [NSCursor setHiddenUntilMouseMoves:YES];
    TERMINAL_FIELD_SET_FLAGS(self, TERMINAL_FIELD_FLAGS(self) | 0x00010000u);
    if ((TERMINAL_FIELD_FLAGS(self) & 0x06000000u) != 0) {
        [self lockFocus];
        [self _clearSelection];
        [self unlockFocus];
    }
    if (springLoadedPaste != NULL) {
        [self pasteText:springLoadedPaste];
        free(springLoadedPaste);
        springLoadedPaste = NULL;
    }
    if ((evflags & 0x40) != 0 &&
        topline < lines->count - cursorx)
        [self scrollTo:lines->count - cursorx];
    if ([(Emulation *)emulator key:mutableEvent] == 0)
        [shell outputChar:(unsigned char)[mutableEvent charValue]];
}

- (void)setFrameSize:(NSSize)newSize
{
    unsigned int oldHeight;
    unsigned int oldCursorX;
    NSWindow *window;
    NSDate *now;

    oldHeight = height;
    oldCursorX = cursorx;
    [super setFrameSize:newSize];
    if (oldHeight != 0 && (oldHeight != height || oldCursorX != cursorx)) {
        window = [self window];
        now = [NSDate dateWithTimeIntervalSinceNow:0];
        [window nextEventMatchingMask:0 untilDate:now
            inMode:NSEventTrackingRunLoopMode dequeue:NO];
        [self broadcastSize];
    }
    [(Emulation *)emulator termDidResize:self];
}

- (void)childExit:(id)sender status:(id)statusObject
{
    Shell *exitedShell = (Shell *)sender;
    TerminalEmulationDefaults *defaults = (TerminalEmulationDefaults *)def;
    NSBundle *bundle;
    NSString *format;
    const char *coreSuffix;
    char message[260];
    int waitStatus;
    int exitAction;
    BOOL hasMessage;
    DirtMonitor *dirtMonitor;

    if (deadMeat)
        return;

    [exitedShell kill];
    [exitedShell close];

    exitAction = defaults->var18;
    hasMessage = NO;
    waitStatus = *(int *)statusObject;
    if (exitAction != 0) {
        if ((waitStatus & 0x7f) != 0x7f && (waitStatus & 0x7f) != 0) {
            bundle = [NSBundle mainBundle];
            format = [bundle localizedStringForKey:
                @"\n\r[Process was terminated by signal %d%s]"
                value:@"" table:nil];
            coreSuffix = "";
            if (waitStatus & 0x80) {
                coreSuffix = [[bundle localizedStringForKey:
                    @" (core dumped)" value:@"" table:nil] cString];
            }
            sprintf(message, [format cString], waitStatus & 0x7f, coreSuffix);
            hasMessage = YES;
        } else if ((waitStatus & 0x7f) == 0) {
            if ((waitStatus >> 8) != 0) {
                bundle = [NSBundle mainBundle];
                format = [bundle localizedStringForKey:
                    @"\n\r[Process exited - exit code %u]"
                    value:@"" table:nil];
                sprintf(message, [format cString], (unsigned int)(waitStatus >> 8));
                hasMessage = YES;
            } else if (exitAction == 2) {
                bundle = [NSBundle mainBundle];
                format = [bundle localizedStringForKey:
                    @"\n\r[Process completed]" value:@"" table:nil];
                sprintf(message, [format cString]);
                hasMessage = YES;
            }
        }
    }

    if (hasMessage) {
        if (cursory != 0)
            [self outputdata:"\n" len:1];
        [self outputdata:message len:(unsigned int)strlen(message)];
        if ([[self window] isKeyWindow]) {
            [self lockFocus];
            [self _clearcursor];
            [self unlockFocus];
            [[self window] flushWindow];
        }
        [self setDrawCursOK:0];
        [self removeDirtTimers];
        dirtMonitor = [(TerminalApp *)NSApp dirtMonitor];
        [dirtMonitor unregisterDevice:shellDevice];
        shellDevice = -1;
        deadMeat = 1;
        [self windowHook:height :cursorx];
        [[self window] setDocumentEdited:NO];
    } else {
        [self removeDirtTimers];
        deadMeat = 1;
        [[self window] performClose:self];
    }
}

- (BOOL)windowShouldClose:(id)sender
{
    NSWindow *terminalWindow = [self window];
    TerminalApp *app = (TerminalApp *)NSApp;
    DirtMonitor *dirtMonitor = [app dirtMonitor];
    char processNames[10 * 17];
    char processList[1024];
    char format[172];
    int processCount = 0;
    int result;
    int i;
    NSString *title;
    NSString *message;
    NSString *closeButton;
    NSString *cancelButton;
    NSString *baseMessage;

    [self setDrawCursOK:0];
    if ([app doingForcedQuit])
        goto closeWindow;

    if (![_theDefaultsObject boolForKey:@"MonitorProcs"] || deadMeat)
        [terminalWindow setDocumentEdited:NO];
    else
        [terminalWindow setDocumentEdited:
            [dirtMonitor isDeviceDirty:shellDevice]];

    if (![terminalWindow isDocumentEdited])
        goto closeWindow;

    [self setDrawCursOK:0];
    [self removeDirtTimers];
    [dirtMonitor getProcNames:(char (*)[17])processNames
        onDevice:shellDevice
        howMany:&processCount];

    if (processCount == 0) {
        title = [[NSBundle mainBundle] localizedStringForKey:
            @"Close" value:@"" table:nil];
        message = [[NSBundle mainBundle] localizedStringForKey:
            @"Closing this window will terminate the processes inside it."
            value:@"" table:nil];
    } else if (processCount == 1) {
        title = [[NSBundle mainBundle] localizedStringForKey:
            @"Close" value:@"" table:nil];
        baseMessage = [[NSBundle mainBundle] localizedStringForKey:
            @"Closing this window will terminate the %s process(es) inside it."
            value:@"" table:nil];
        sprintf(format, [baseMessage cString], processNames[0]);
        message = [NSString stringWithCString:format];
    } else {
        baseMessage = [[NSBundle mainBundle] localizedStringForKey:
            @"Closing this window will terminate the following processes inside it: "
            value:@"" table:nil];
        strcpy(processList, [baseMessage cString]);
        for (i = 0; i < processCount; ++i) {
            strcat(processList, &processNames[17 * i]);
            if (i < processCount - 1)
                strcat(processList, "\n");
        }
        title = [[NSBundle mainBundle] localizedStringForKey:
            @"Close" value:@"" table:nil];
        message = [NSString stringWithCString:processList];
    }

    closeButton = [[NSBundle mainBundle] localizedStringForKey:
        @"Close Anyway" value:@"" table:nil];
    cancelButton = [[NSBundle mainBundle] localizedStringForKey:
        @"Cancel" value:@"" table:nil];
    result = NSRunAlertPanel(title, message, closeButton, cancelButton,
        nil);
    if (result == 0)
        return NO;

closeWindow:
    if ([terminalWindow isKeyWindow] || [terminalWindow isMainWindow])
        [app activateNext:self forward:NO includeMini:NO];
    [shell kill];
    [app lazyDestroyZone:[self zone] wait:NO];
    return YES;
}

- (unsigned int)draggingEntered:(id<NSDraggingInfo>)sender
{
    return [sender draggingSourceOperationMask] & 4;
}

- (unsigned int)draggingUpdated:(id<NSDraggingInfo>)sender
{
    return [self draggingEntered:sender];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pasteboard;
    NSEnumerator *types;
    NSString *type;
    NSWindow *terminalWindow;
    BOOL acceptsFilenames = NO;

    pasteboard = [sender draggingPasteboard];
    types = [[pasteboard types] objectEnumerator];
    while ((type = [types nextObject]) != nil) {
        if (![type isEqual:NSFilenamesPboardType]) {
            acceptsFilenames = NO;
            break;
        }
        acceptsFilenames = YES;
    }

    if (!acceptsFilenames) {
        [self removeTrackingRect:debugTag];
        [self removeTrackingRect:debugTag + 1];
        terminalWindow = [self window];
        [terminalWindow disableFlushWindow];
        [self scrollTo:lines->count - cursorx];
        [terminalWindow enableFlushWindow];
        [terminalWindow flushWindow];
        [self resetCursorRects];
    }
    return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pasteboard;
    NSEnumerator *typeEnumerator;
    NSString *type;
    id propertyList;
    NSArray *filenames;
    NSString *filename;
    NSWindow *terminalWindow;
    const char *bytes;
    unsigned int length;
    unsigned int i;
    unsigned int j;
    BOOL hasFinalNul;

    pasteboard = [sender draggingPasteboard];
    typeEnumerator = [[pasteboard types] objectEnumerator];
    while ((type = [typeEnumerator nextObject]) != nil) {
        if ([type isEqual:NSFilenamesPboardType] ||
            [type isEqual:NSStringPboardType]) {
            propertyList = [pasteboard propertyListForType:type];
            filenames = (NSArray *)propertyList;
            for (i = 0; i < [filenames count]; ++i) {
                filename = [filenames objectAtIndex:i];
                bytes = [filename cString];
                length = [filename cStringLength];
                hasFinalNul = bytes[length - 1] == '\0';
                if (hasFinalNul)
                    --length;

                for (j = 0; j < length; ++j) {
                    if ((evflags & 0x80) && bytes[j] == '\n')
                        ((char *)bytes)[j] = '\r';
                    else if (bytes[j] == '\t')
                        ((char *)bytes)[j] = ' ';
                }

                terminalWindow = [self window];
                [terminalWindow disableFlushWindow];
                [shell output:bytes len:length];
                [shell output:"\r" len:1];
                terminalWindow = [self window];
                [terminalWindow enableFlushWindow];
            }
            return YES;
        }

        if ([type isEqual:NSColorPboardType]) {
            NSPoint location;
            NSColor *color;

            location = [sender draggingLocation];
            color = [NSColor colorFromPasteboard:pasteboard];
            [self _acceptColor:color atPoint:location];
            return YES;
        }
    }
    return NO;
}

- (void)_acceptColor:(NSColor *)color atPoint:(NSPoint)point
{
    TerminalEmulationDefaults *defaults =
        (TerminalEmulationDefaults *)def;
    TerminalLine *lineNode;
    NSColor *oldColor;
    NSString *colorSpace;
    unsigned int lineIndex;
    unsigned int column;
    unsigned int paletteIndex;
    char character = 0;
    unsigned char attributes = 0;

    point = [self convertPoint:point toView:nil];
    point.x -= (float)(bwidth >> 1);
    [self _point:&point toPosition:&lineIndex :&column];

    lineNode = *(TerminalLine **)(lines->elements +
        (size_t)lineIndex * 8);
    while (lineNode != NULL && lineNode->column <= column) {
        if (column < (unsigned int)lineNode->column + lineNode->length) {
            character = lineNode->text[column - lineNode->column];
            attributes = lineNode->attributes;
            break;
        }
        lineNode = lineNode->next;
    }

    if (lineIndex == (unsigned int)_cursory + lines->count - cursorx &&
        column == cursory) {
        paletteIndex = 7;
    } else if ([self isSelected:column :lineIndex]) {
        paletteIndex = 6;
    } else if (character <= 0 || character == ' ') {
        paletteIndex = (attributes & 1) ? 5 : 4;
    } else if (attributes & 2) {
        paletteIndex = 2;
    } else if (attributes & 8) {
        paletteIndex = 3;
    } else {
        paletteIndex = attributes & 1;
    }

    oldColor = (NSColor *)defaults->var19[paletteIndex];
    if (oldColor != nil)
        [oldColor release];
    colorSpace = [color colorSpaceName];
    defaults->var19[paletteIndex] =
        [[color colorUsingColorSpaceName:colorSpace] copy];
    [self setDefaults:defaults];
}

- (id)outputdata:(const char *)bytes len:(unsigned int)length
{
    unsigned int i;
    unsigned char cursorY;
    unsigned char savedCursorY;

    cursorY = cursory;
    savedCursorY = _cursory;
    if (deadMeat)
        return nil;
    if (length == 0)
        return self;

    if (!isMiniaturized) {
        [self lockFocus];
        [self _clearcursor];
    }
    [emulator output:bytes len:length];

    if (!isMiniaturized) {
        [self _refresh];
        if (TERMINAL_FIELD_FLAGS(self) & 0x00010000u)
            [self _cursor];
        else {
            [NSRunLoop cancelPreviousPerformRequestsWithTarget:self
                selector:@selector(_delayedCursor:) object:self];
            [self performSelector:@selector(_delayedCursor:)
                       withObject:self afterDelay:0.1];
            [self updateWindowStatus];
        }
        TERMINAL_FIELD_SET_FLAGS(self, TERMINAL_FIELD_FLAGS(self) & ~0x00010000u);
    }

    [[self window] flushWindow];
    if (isMiniaturized) {
        [self updateWindowStatus];
    } else {
        if ((TERMINAL_FIELD_FLAGS(self) & 0x08000000u) && saveLines > 0 &&
            topline > lines->count - (unsigned int)saveLines &&
            lines->count > (unsigned int)saveLines + 400u)
            [self pruneNumLinesTo:(unsigned int)saveLines];
        [self unlockFocus];
        if ([NSApp isHidden])
            [NSApp updateAppStatus];
    }

    for (i = 0; i < length; ++i) {
        if (bytes[i] == '\n') {
            [self scheduleUpdate];
            break;
        }
    }
    if (i == length) {
        if (longTermTimer == nil && dirtUpdateTimer == nil)
            longTermTimer = [[NSTimer scheduledTimerWithTimeInterval:0.1
                target:self selector:@selector(handleDirtTimer:)
                userInfo:self repeats:NO] retain];
        if (springLoadedPaste != 0 &&
            (cursory != cursorY || _cursory != savedCursorY)) {
            [self pasteText:springLoadedPaste];
            free(springLoadedPaste);
            springLoadedPaste = 0;
        }
    }
    return self;
}

- (void)pruneNumLinesTo:(unsigned int)lineCount
{
    unsigned int removedCount;
    unsigned int oldCount;
    unsigned int i;
    NSView *contentView;
    NSWindow *terminalWindow;

    oldCount = lines->count;
    removedCount = oldCount - lineCount;
    terminalWindow = [self window];
    [terminalWindow disableFlushWindow];

    for (i = 0; i < lineCount; ++i) {
        if (i < removedCount)
            lineFree(terminalLineAt(lines, i));
        terminalLineSet(lines, i, terminalLineAt(lines, i + removedCount));
        terminalLineSetWrapped(lines, i,
            terminalLineIsWrapped(lines, i + removedCount));
    }
    for (i = lineCount; i < oldCount; ++i) {
        if (i < removedCount)
            lineFree(terminalLineAt(lines, i));
        terminalLineSet(lines, i, NULL);
        terminalLineSetWrapped(lines, i, 0);
    }

    if ((TERMINAL_FIELD_FLAGS(self) & 0x06000000u) != 0) {
        if (selPt0.line >= removedCount && selPt1.line >= removedCount) {
            selPt0.line -= removedCount;
            selPt1.line -= removedCount;
        } else {
            [self _clearSelection];
        }
    }
    lines->count -= removedCount;
    topline -= removedCount;

    contentView = [terminalWindow contentView];
    [contentView setNeedsDisplay:YES];
    [self display];
    [self reflectPosition];
    terminalWindow = [self window];
    [terminalWindow enableFlushWindow];
}

- (void)updateWindowStatus
{
    if (needsStatusUpdate)
        return;

    needsStatusUpdate = 1;
    [NSRunLoop cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(displayWindowStatus:) object:self];
    [self performSelector:@selector(displayWindowStatus:)
        withObject:self afterDelay:0.5];
}

- (void)displayWindowStatus:(id)sender
{
    NSWindow *window = [self window];
    NSView *contentView;
    int offset;
    float y;

    if (window != nil && ([window styleMask] & NSMiniaturizableWindowMask) != 0) {
        offset = miniAnimOffset + 2;
        miniAnimOffset = offset;
        if (offset > 6)
            miniAnimOffset -= 7;
        y = (float)(6 - miniAnimOffset) - 0.5f;
        contentView = [window contentView];
        [contentView lockFocus];
        [outputImage compositeToPoint:NSMakePoint(6.0f, 35.0f - y)
            fromRect:NSMakeRect(0.0f, 0.0f, 24.0f, 24.0f)
            operation:NSCompositeCopy];
        [contentView unlockFocus];
        [window flushWindow];
    }
    needsStatusUpdate = 0;
}

- (void)removeDirtTimers
{
    if (dirtUpdateTimer != nil) {
        [dirtUpdateTimer invalidate];
        [dirtUpdateTimer release];
        dirtUpdateTimer = nil;
    }
    if (longTermTimer != nil) {
        [longTermTimer invalidate];
        [longTermTimer release];
        longTermTimer = nil;
    }
}

- (void)windowWillMiniaturize:(id)notification
{
    isMiniaturized = 1;
    [self setDrawCursOK:0];
    [self removeDirtTimers];
    needsDirtUpdate = 0;
}

- (void)windowDidDeminiaturize:(id)notification
{
    isMiniaturized = 0;
    [self enablePSOutput];
    [self setDrawCursOK:1];
    [self updateDirtIfNeeded];
    [self refreshscreen];
    [[[self window] contentView] setNeedsDisplay:YES];
}

@end
