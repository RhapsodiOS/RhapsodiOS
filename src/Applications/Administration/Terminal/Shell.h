#ifndef TERMINAL_SHELL_H
#define TERMINAL_SHELL_H

#import "FilerObjC.h"

@class NSNotification;

@interface Shell : Filer
{
    int pid;
    SEL exitAction;
    char pty[11];
    char _padding0;
    char *command;
    int slot;
    char invalidated;
    char _padding1[3];
}

- (int)pid;
- (id)init;
- (void)kill;
- (void)invalidate;
- (void)dealloc;
- (void)login;
- (void)logout;
- (int)findslot:(char *)ttyName;
- (char)system:(const char *)command login:(char)login folder:(const char *)folder env:(char **)environment;
- (void)setExitAction:(SEL)value;
- (SEL)exitAction;
- (const char *)pty;
- (const char *)command;
- (int)slaveMinorDevice;

+ (void)initialize;
+ (void)freeAll;
+ (void)handleSignal;
+ (void)handleFileActivity:(NSNotification *)notification;

@end

#endif
