#ifndef TERMINAL_STARTUP_CONTROLLER_H
#define TERMINAL_STARTUP_CONTROLLER_H

#import <Foundation/NSObject.h>
#import "Emulation.h"

@interface StartupController : NSObject
{
    id actionMatrix;
    id fastAutolaunchCheck;
    id pathForm;
    int revertAction;
    char *revertStartupFile;
    unsigned char revertFastLaunch;
    unsigned char _padding0[3];
}
- (void)setFromStruct:(const TerminalEmulationDefaults *)defaults;
- (void)showDefault:(char)show;
- (void)setAction:(int)action file:(const char *)file
    fastLaunch:(char)fastLaunch lockRevert:(char)lockRevert;
- (void)suggest;
- (void)revert;
- (void)setStruct:(TerminalEmulationDefaults *)defaults;
- (char)checkSettings;
- (void)firstVisible:(id)sender;
- (void)lastVisible:(id)sender;
- (id)startupFilesChanged:(id)sender;
- (void)setPathRequest:(id)sender;
- (void)pathWasSet:(id)sender;
- (void)fastStartupChanged:(id)sender;
- (void)startupActionChanged:(id)sender;
- (id)setDefault;
- (void)forceSetDefault;
- (void)savePanelDidChangeStartupDefaults:(id)sender;
@end

#if defined(__rhapsody__) || defined(TARGET_OS_RHAPSODY)
_Static_assert(sizeof(StartupController) == 32,
    "Terminal StartupController PPC/i386 instance size");

typedef struct {
    @defs(StartupController);
} StartupControllerLayout;

_Static_assert(__builtin_offsetof(StartupControllerLayout, revertAction) == 16,
    "Terminal StartupController revert action offset");
_Static_assert(__builtin_offsetof(StartupControllerLayout, revertStartupFile) == 20,
    "Terminal StartupController revert file offset");
_Static_assert(__builtin_offsetof(StartupControllerLayout, revertFastLaunch) == 24,
    "Terminal StartupController revert fast-launch offset");
#endif

#endif
