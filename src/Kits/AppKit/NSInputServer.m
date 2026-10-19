/*	NSInputServer.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSInputServer.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSView.h>
#import <Foundation/NSObjCRuntime.h>

@interface NSInputServicePanel : NSPanel
- (void)_setAvoidsActivation:(BOOL)flag;
@end

@interface NSInputClientWrapper : NSObject
+ (id)clientWrapperWithRealClient:(id)client;
@end

static id NSInputServerClient(id client)
{
    if (![client respondsToSelector:@selector(conversationIdentifier)])
        return client;

    return [NSInputClientWrapper clientWrapperWithRealClient:client];
}

@implementation NSInputServer

- initWithDelegate:(id)aDelegate name:(NSString *)name
{
    self = [super init];
    if (self) {
        _name = [name retain];
        _delegate = [aDelegate retain];
    }
    return self;
}

- (void)dealloc
{
    [_name release];
    [_delegate release];
    [super dealloc];
}

- (id)description
{
    return _name;
}

- (BOOL)canBeDisabled
{
    if ([_delegate respondsToSelector:@selector(canBeDisabled)])
        return [_delegate canBeDisabled];
    return YES;
}

- (BOOL)wantsToInterpretAllKeystrokes
{
    if ([_delegate respondsToSelector:@selector(wantsToInterpretAllKeystrokes)])
        return [_delegate wantsToInterpretAllKeystrokes];
    return NO;
}

- (BOOL)wantsToHandleMouseEvents
{
    if ([_delegate respondsToSelector:@selector(wantsToHandleMouseEvents)])
        return [_delegate wantsToHandleMouseEvents];
    return NO;
}

- (BOOL)wantsToDelayTextChangeNotifications
{
    if ([_delegate respondsToSelector:@selector(wantsToDelayTextChangeNotifications)])
        return [_delegate wantsToDelayTextChangeNotifications];
    return NO;
}

- (void)insertText:(id)aString client:(id)sender
{
    if ([_delegate respondsToSelector:@selector(insertText:client:)])
        [_delegate insertText:aString client:NSInputServerClient(sender)];
    else
        NSLog(@"%@ can not respond to insertText:client:", _name);
}

- (void)doCommandBySelector:(SEL)aSelector client:(id)sender
{
    if ([_delegate respondsToSelector:@selector(doCommandBySelector:client:)])
        [_delegate doCommandBySelector:aSelector client:NSInputServerClient(sender)];
    else
        NSLog(@"%@ can not respond to doCommandBySelector:client:", _name);
}

- (void)markedTextAbandoned:(id)sender
{
    if ([_delegate respondsToSelector:@selector(markedTextAbandoned:)])
        [_delegate markedTextAbandoned:NSInputServerClient(sender)];
}

- (void)markedTextSelectionChanged:(NSRange)newSel client:(id)sender
{
    if ([_delegate respondsToSelector:@selector(markedTextSelectionChanged:client:)])
        [_delegate markedTextSelectionChanged:newSel client:NSInputServerClient(sender)];
}

- (void)terminate:(id)sender
{
    if ([_delegate respondsToSelector:@selector(terminate:)])
        [_delegate terminate:NSInputServerClient(sender)];
}

- (void)inputClientBecomeActive:(id)sender
{
    if ([_delegate respondsToSelector:@selector(inputClientBecomeActive:)])
        [_delegate inputClientBecomeActive:NSInputServerClient(sender)];
}

- (void)inputClientResignActive:(id)sender
{
    if ([_delegate respondsToSelector:@selector(inputClientResignActive:)])
        [_delegate inputClientResignActive:NSInputServerClient(sender)];
}

- (void)inputClientEnabled:(id)sender
{
    if ([_delegate respondsToSelector:@selector(inputClientEnabled:)])
        [_delegate inputClientEnabled:NSInputServerClient(sender)];
}

- (void)inputClientDisabled:(id)sender
{
    if ([_delegate respondsToSelector:@selector(inputClientDisabled:)])
        [_delegate inputClientDisabled:NSInputServerClient(sender)];
}

- (void)activeConversationWillChange:(id)sender fromOldConversation:(long)oldConversation
{
    if ([_delegate respondsToSelector:
            @selector(activeConversationWillChange:fromOldConversation:)])
        [_delegate activeConversationWillChange:NSInputServerClient(sender)
                            fromOldConversation:oldConversation];
}

- (void)activeConversationChanged:(id)sender toNewConversation:(long)newConversation
{
    if ([_delegate respondsToSelector:
            @selector(activeConversationChanged:toNewConversation:)])
        [_delegate activeConversationChanged:NSInputServerClient(sender)
                           toNewConversation:newConversation];
}

- (BOOL)mouseDownOnCharacterIndex:(unsigned)theIndex
                    atCoordinate:(NSPoint)thePoint
                    withModifier:(unsigned int)theFlags
                           client:(id)sender
{
    if ([_delegate respondsToSelector:
            @selector(mouseDownOnCharacterIndex:atCoordinate:withModifier:client:)])
        return [_delegate mouseDownOnCharacterIndex:theIndex atCoordinate:thePoint
                                       withModifier:theFlags
                                             client:NSInputServerClient(sender)];
    return NO;
}

- (BOOL)mouseDraggedOnCharacterIndex:(unsigned)theIndex
                       atCoordinate:(NSPoint)thePoint
                       withModifier:(unsigned int)theFlags
                              client:(id)sender
{
    if ([_delegate respondsToSelector:
            @selector(mouseDraggedOnCharacterIndex:atCoordinate:withModifier:client:)])
        return [_delegate mouseDraggedOnCharacterIndex:theIndex atCoordinate:thePoint
                                          withModifier:theFlags
                                                client:NSInputServerClient(sender)];
    return NO;
}

- (void)mouseUpOnCharacterIndex:(unsigned)theIndex
                  atCoordinate:(NSPoint)thePoint
                  withModifier:(unsigned int)theFlags
                         client:(id)sender
{
    if ([_delegate respondsToSelector:
            @selector(mouseUpOnCharacterIndex:atCoordinate:withModifier:client:)])
        [_delegate mouseUpOnCharacterIndex:theIndex atCoordinate:thePoint
                              withModifier:theFlags
                                    client:NSInputServerClient(sender)];
}

+ (id)inputServicePanelWithContentRect:(NSRect)contentRect
                             styleMask:(unsigned)style
                               backing:(NSBackingStoreType)backing
                                 defer:(BOOL)flag
{
    NSInputServicePanel *panel;

    panel = [[NSInputServicePanel allocWithZone:NULL]
        initWithContentRect:contentRect styleMask:style backing:backing defer:flag];
    return [panel autorelease];
}

@end

@implementation NSInputServer (NSInputServerDOOptimization)

- (void)_inputClientChangedStatus:(unsigned)status
                      inputClient:(id)client
                              arg1:(unsigned)arg1
                              arg2:(unsigned)arg2
{
    if (status & 0x10) {
        [self markedTextSelectionChanged:NSMakeRange(arg1, arg2) client:client];
        return;
    }

    if (status & 0x01)
        [self inputClientBecomeActive:client];
    if (status & 0x02)
        [self inputClientEnabled:client];
    if (status & 0x08)
        [self markedTextAbandoned:client];
    if (status & 0x04)
        [self activeConversationChanged:client toNewConversation:arg1];
    if (status & 0x40)
        [self inputClientDisabled:client];
    if (status & 0x20)
        [self inputClientResignActive:client];
}

@end

@implementation NSInputServicePanel

- (BOOL)canBecomeKeyWindow
{
    return NO;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}

- initWithContentRect:(NSRect)contentRect
           styleMask:(unsigned)style
             backing:(NSBackingStoreType)backing
               defer:(BOOL)flag
{
    [super initWithContentRect:contentRect styleMask:style backing:backing defer:flag];
    [self setBecomesKeyOnlyIfNeeded:YES];
    [self setFloatingPanel:YES];
    [self setHidesOnDeactivate:NO];
    [self _setAvoidsActivation:YES];
    return self;
}

- (void)sendEvent:(NSEvent *)event
{
    if ([event type] == NSLeftMouseDown || [event type] == NSLeftMouseUp) {
        NSPoint point = [event locationInWindow];
        NSView *target = [_borderView hitTest:point];
        [target mouseDown:event];
    } else {
        [super sendEvent:event];
    }
}

@end

@implementation NSInputServer (NSInputServerCompatibility)

- (void)cancelInput:(id)sender conversation:(long)conversation
{
    if ([_delegate respondsToSelector:@selector(cancelInput:conversation:)])
        [_delegate cancelInput:sender conversation:conversation];
}

- (void)senderDidBecomeActive:(id)sender
{
    if ([_delegate respondsToSelector:@selector(senderDidBecomeActive:)])
        [_delegate senderDidBecomeActive:sender];
}

- (void)senderDidResignActive:(id)sender
{
    if ([_delegate respondsToSelector:@selector(senderDidResignActive:)])
        [_delegate senderDidResignActive:sender];
}

- (void)setActivated:(BOOL)flag sender:(id)sender
{
    if ([_delegate respondsToSelector:@selector(setActivated:sender:)])
        [_delegate setActivated:flag sender:sender];
    else
        NSLog(@"%@ can not respond to setActivated:sender:", _name);
}

@end
