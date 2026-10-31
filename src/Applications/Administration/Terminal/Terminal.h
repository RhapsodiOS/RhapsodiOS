#ifndef TERMINAL_TERMINAL_H
#define TERMINAL_TERMINAL_H

#import <Foundation/NSTimer.h>
#import <AppKit/NSDragging.h>

#include "FieldView.h"
#include "Emulation.h"

@class Shell, NSString;
@class NSWindow;

struct TerminalExtraWindowInfo {
    float x;
    float y;
    char hidden;
};

@interface Terminal : FieldView
{
    Shell *shell;
    char debugging;
    char wasActive;
    char isMiniaturized;
    char needsDirtUpdate;
    char deadMeat;
    char _padding0[3];
    int activeApp;
    int shellDevice;
    NSTimer *dirtUpdateTimer;
    NSTimer *longTermTimer;
    NSTimer *cursorBlinkTimer;
    double lastUpdateTime;
    void *def;
    char needsStatusUpdate;
    char _padding1[3];
    int miniAnimOffset;
    id outputImage;
    int debugTag;
    id emulator;
    unsigned char evflags;
    char _padding2[3];
    char *fileName;
    char sharesSettingsFile;
    char _padding3[3];
    int saveLines;
    int serviceOwner;
    char *springLoadedPaste;
    int DOwinHandle;
    unsigned int defaultCStringEncoding;
    char hackForRightEdge;
}

- (NSWindow *)window;
- (BOOL)setUpWithDefaults:(const TerminalEmulationDefaults *)defaults
    inFolder:(const char *)folder env:(char **)environment;
- (BOOL)isDead;
- (BOOL)acceptsFirstResponder;
- (id)defaults;
- (void)setDefaults:(const TerminalEmulationDefaults *)defaults;
- (void)setTitle:(NSString *)title;
- (void)setCustomTitle:(const char *)title;
- (Shell *)shell;
- (id)emulator;
- (void)setEmulator:(id)value;
- (int)shellDevice;
- (int)serviceOwner;
- (void)setServiceOwner:(int)value;
- (int)DOwinHandle;
- (void)setDOwinHandle:(int)value;
- (char *)fileName;
- (BOOL)sharesFile;
- (void)setFileName:(const char *)name sharesFile:(char)shares;
- (void)setSpringLoadedPaste:(char *)value;
- (void)broadcastSize;
- (void)dealloc;
- (void)cancelDelayedPerforms;
- (void)cursorBlink:(char)shouldBlink;
- (void)handleCursorBlinkTimer:(id)sender;
- (void)redisplayTitle:(id)sender;
- (void)windowDidResignMain:(id)notification;
- (void)windowDidBecomeKey:(id)notification;
- (void)windowDidResignKey:(id)notification;
- (void)windowHook:(unsigned int)columns :(unsigned int)rows;
- (void)output:(const char *)value;
- (void)output:(const char *)bytes len:(unsigned int)length;
- (void)outputChar:(unsigned char)value;
- (void)removeDirtTimers;
- (void)windowWillMiniaturize:(id)notification;
- (void)windowDidDeminiaturize:(id)notification;
- (void)updateDirtIfNeeded;
- (id)outputdata:(const char *)bytes len:(unsigned int)length;
- (id)scheduleUpdate;
- (void)handleDirtTimer:(id)sender;
- (void)pruneNumLinesTo:(unsigned int)lineCount;
- (void)pasteText:(const char *)text;
- (void)paste:(id)sender;
- (void)keyDown:(NSEvent *)event;
- (void)setFrameSize:(NSSize)newSize;
- (void)endOfFileOn:(id)sender;
- (void)childExit:(id)sender status:(id)status;
- (BOOL)windowShouldClose:(id)sender;
- (unsigned int)draggingEntered:(id<NSDraggingInfo>)sender;
- (unsigned int)draggingUpdated:(id<NSDraggingInfo>)sender;
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender;
- (void)_acceptColor:(NSColor *)color atPoint:(NSPoint)point;
- (void)mouseEntered:(id)event;
- (void)mouseExited:(id)event;
- (BOOL)acceptsFirstResponder;
- (void)debugToggle:(id)sender;
- (void)getExtraWinInfo:(struct TerminalExtraWindowInfo *)info;
- (void)updateWindowStatus;
- (void)displayWindowStatus:(id)sender;

@end

#endif
