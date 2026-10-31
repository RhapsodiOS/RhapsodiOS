#import "TerminalAgent.h"
#import "Terminal.h"
#import "Shell.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSInterfaceStyle.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>

extern NSString *NSInterfaceStyleDefault;


@implementation TerminalAgent

- (void)setTerminal:(Terminal *)value
{
    terminal = value;
}

- (Terminal *)terminal
{
    return terminal;
}

- (id)initDefaults:(const TerminalEmulationDefaults *)defaults
    inFolder:(const char *)folder env:(char **)environment
{
    NSZone *zone;
    NSWindow *window;
    NSView *windowContentView;
    NSScrollView *scrollView;
    NSScroller *scroller;
    NSRect windowRect;
    NSRect scrollRect;
    NSRect terminalRect;
    NSInterfaceStyle interfaceStyle;
    BOOL darkInterface;

    [super init];

    zone = [self zone];
    terminal = nil;
    windowRect.origin.x = 100.0;
    windowRect.origin.y = 100.0;
    windowRect.size.width = 100.0;
    windowRect.size.height = 100.0;
    window = [[NSWindow allocWithZone:zone] initWithContentRect:windowRect
        styleMask:14 backing:NSBackingStoreBuffered defer:NO];
    if (window == nil) {
        [self release];
        return nil;
    }

    [window setReleasedWhenClosed:YES];
    [window setMiniwindowImage:[NSImage imageNamed:@"Terminal"]];
    [window setOneShot:YES];
    windowContentView = [window contentView];
    [windowContentView setAutoresizesSubviews:YES];

    scrollView = [[NSScrollView allocWithZone:NULL] initWithFrame:
        [windowContentView bounds]];
    [scrollView setHasHorizontalScroller:NO];
    [scrollView setHasVerticalScroller:YES];
    scrollRect = [scrollView frame];
    [scrollView setScrollsDynamically:NO];
    [scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    interfaceStyle = NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil);
    darkInterface = (interfaceStyle ^ 1) != 0;
    terminalRect = scrollRect;
    terminalRect.origin = NSZeroPoint;
    if (darkInterface)
        terminalRect.size.width += 1.0;
    terminal = [[Terminal allocWithZone:zone] initWithFrame:terminalRect];
    if (terminal != nil && [terminal setUpWithDefaults:defaults
        inFolder:folder env:environment]) {
        [terminal setDelegate:self];
        [terminal display];
        [window setDelegate:self];
        [window setFrameAutosaveName:@"Terminal"];
        [scrollView setDocumentView:terminal];
        [windowContentView addSubview:scrollView];
        scroller = [scrollView verticalScroller];
        [scroller setTarget:terminal];
        [scroller setAction:@selector(_lscrollup:)];
        [terminal setScroller:scroller];
        [terminal setDrawsLineAtRightEdge:darkInterface];
        return self;
    }

    [window release];
    [self release];
    return nil;
}

@end
