#ifndef TERMINAL_SERVICE_PROVIDER_H
#define TERMINAL_SERVICE_PROVIDER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

#include "TerminalDOProtocol.h"

@class NSData, NSText, Terminal;

@interface ServiceProvider : NSObject
{
    id addArgsWindow;
    id addArgsField;
    id addArgsServiceTitle;
    id addInputWindow;
    id addInputText;
    id addInputCommandTitle;
    id addInputServiceTitle;
    id bothWindow;
    id bothArgsField;
    id bothInputText;
    id bothServiceTitle;
    char nibLoaded;
    char _padding[3];
    NSSize addArgsSize;
    NSSize addInputSize;
    NSSize bothSize;
    NSText *convertText;
}

- (id)newCommand:(const char *)command shell:(TSShellType)shellType
    env:(NSData *)environment;
- (id)newCommand:(const char *)command shell:(TSShellType)shellType
    path:(const char *)path env:(NSData *)environment;
- (id)ok:(id)sender;
- (id)cancel:(id)sender;
- (NSSize)windowWillResize:(id)window toSize:(NSSize)size;
- (char)pasteboard:(id)pasteboard containsType:(id)type;
- (char *)copyString:(const char *)string;
- (char *)replace:(const char *)search with:(const char *)replacement
    in:(char *)string;
- (void)ensureNibLoaded;
- (void)provideService:(id)pasteboard userData:(id)userData
    error:(const void **)error;

@end

#endif
