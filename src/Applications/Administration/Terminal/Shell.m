#import "Shell.h"

#import <Foundation/NSRunLoop.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSException.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>

#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <ttyent.h>
#include <signal.h>
#include <pwd.h>
#include <grp.h>
#include <utmp.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <util.h>

#include "ShellExec.h"
#include "ProcessIdentity.h"

extern int sigsetmask(int mask);

static NSMutableArray *activeShells;
static int signalPipe[2];
static struct passwd *shellUser;
int defaultModes;
extern char **environ;

static void handleSIGCHLD(int signalNumber)
{
    (void)signalNumber;
    write(signalPipe[1], "X", 1);
}

@implementation Shell

+ (void)initialize
{
    NSFileHandle *signalHandle;
    NSArray *modes;

    activeShells = [[NSMutableArray alloc] init];
    signal(SIGCHLD, handleSIGCHLD);
    shellUser = getpwuid((uid_t)TerminalRealUID());
    pipe(signalPipe);

    signalHandle = [[NSFileHandle alloc]
        initWithFileDescriptor:signalPipe[0]];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(handleFileActivity:)
        name:NSFileHandleDataAvailableNotification object:signalHandle];
    modes = [NSArray arrayWithObject:NSDefaultRunLoopMode];
    [signalHandle readInBackgroundAndNotifyForModes:modes];
}

+ (void)freeAll
{
    [activeShells removeAllObjects];
}

+ (void)handleSignal
{
    int status;
    pid_t child;

    while ((child = wait3(&status, WNOHANG, NULL)) > 0) {
        int index = (int)[activeShells count] - 1;

        for (; index >= 0; --index) {
            Shell *shell = [activeShells objectAtIndex:(unsigned)index];
            if (shell->pid == child) {
                shell->pid = -1;
                [shell->target performSelector:shell->exitAction
                    withObject:shell withObject:(id)&status];
                break;
            }
        }
    }
}

+ (void)handleFileActivity:(NSNotification *)notification
{
    NSFileHandle *handle = [notification object];
    NSArray *modes;

    [Shell handleSignal];
    sigsetmask(0);
    modes = [NSArray arrayWithObject:NSDefaultRunLoopMode];
    [handle readInBackgroundAndNotifyForModes:modes];
}

- (id)init
{
    [super init];
    invalidated = 0;
    pid = -1;
    exitAction = @selector(exitAction);
    pty[0] = 0;
    [activeShells addObject:self];
    command = 0;
    return self;
}

- (void)setExitAction:(SEL)value
{
    exitAction = value;
}

- (SEL)exitAction
{
    return exitAction;
}

- (int)pid
{
    return pid;
}

- (const char *)pty
{
    return pty;
}

- (const char *)command
{
    return command;
}

- (int)slaveMinorDevice
{
    struct stat status;

    if (fstat([self fd], &status) == -1) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd object:self
            file:[NSString stringWithCString:"Shell.m"]
            lineNumber:688
            description:@"Cannot stat master side of pty."];
    }
    return (unsigned char)status.st_rdev;
}

- (int)findslot:(char *)ttyName
{
    size_t nameLength = strlen(ttyName);
    int slot;
    struct ttyent *entry;

    setttyent();
    for (slot = 1; ; ++slot) {
        entry = getttyent();
        if (entry == NULL || strncmp(ttyName, entry->ty_name, nameLength) == 0)
            break;
    }
    endttyent();
    return entry == NULL ? -1 : slot;
}

- (void)login
{
    struct utmp record;
    const char *line = strrchr(pty, '/');
    int fd;

    if (line == NULL)
        return;
    ++line;

    memset(&record, 0, sizeof(record));
    strcpy(record.ut_line, line);
    if (shellUser != NULL)
        strcpy(record.ut_name, shellUser->pw_name);
    memset(record.ut_host, 0, sizeof(record.ut_host));
    time(&record.ut_time);

    become_root();
    fd = open(_PATH_UTMP, O_RDWR);
    if (fd >= 0) {
        slot = [self findslot:(char *)line];
        lseek(fd, (off_t)(36 * slot), SEEK_SET);
        write(fd, &record, 36);
        close(fd);
    }

    fd = open(_PATH_WTMP, O_WRONLY | O_APPEND);
    if (fd >= 0) {
        write(fd, &record, 36);
        close(fd);
    }
    become_user();
}

- (void)logout
{
    struct utmp record;
    const char *line = strrchr(pty, '/');
    struct group *group;
    gid_t gid = 0;
    int fd;

    if (line == NULL)
        return;
    ++line;

    memset(&record, 0, sizeof(record));
    strcpy(record.ut_line, line);
    time(&record.ut_time);

    become_root();
    fd = open(_PATH_WTMP, O_WRONLY | O_APPEND);
    if (fd >= 0) {
        write(fd, &record, 36);
        close(fd);
    }

    fd = open(_PATH_UTMP, O_RDWR);
    if (fd >= 0) {
        if (slot >= 0) {
            lseek(fd, (off_t)(36 * slot), SEEK_SET);
            write(fd, &record, 36);
            close(fd);
        }
    }
    slot = -1;

    group = getgrnam("wheel");
    if (group == NULL)
        group = getgrnam("tty");
    if (group != NULL)
        gid = group->gr_gid;
    chown(pty, 0, gid);
    chmod(pty, 0666);
    become_user();
}

- (char)system:(const char *)commandLine login:(char)login
        folder:(const char *)folder env:(char **)environment
{
    int master;
    int slave;
    int errorPipe[2];
    pid_t child;
    struct winsize windowSize;
    struct termios terminalState;
    pid_t processGroup;
    char errorBuffer[32];
    NSZone *zone;
    size_t commandLength;
    char *commandCopy;

    become_root();
    if (openpty(&master, &slave, pty, NULL, NULL) == -1) {
        become_user();
        return 0;
    }

    fchown(slave, shellUser->pw_uid, (gid_t)-1);
    fchmod(slave, 0620);
    become_user();
    fcntl(master, F_SETFD, FD_CLOEXEC);
    [self setFd:master];
    pipe(errorPipe);
    fcntl(errorPipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(errorPipe[1], F_SETFD, FD_CLOEXEC);

    child = vfork();
    pid = child;
    if (child == 0) {
        setsid();
        ioctl(slave, TIOCSCTTY, 0);
        setuid(shellUser->pw_uid);
        setgid(shellUser->pw_gid);
        if (ioctl(slave, TIOCGWINSZ, &windowSize) < 0)
            memcpy(&windowSize, &defaultModes, sizeof(defaultModes));
        if (tcgetattr(slave, &terminalState) < 0)
            memset(&terminalState, 0, sizeof(terminalState));
        terminalState.c_cflag = (terminalState.c_cflag & 0x00008000) | 0x4B00;
        terminalState.c_iflag = 0x2B02;
        terminalState.c_lflag = (terminalState.c_lflag & 0x80400224) | 0x5CB;
        terminalState.c_oflag = 3;
        ioctl(slave, TIOCSWINSZ, &windowSize);
        tcsetattr(slave, TCSANOW, &terminalState);
        dup2(slave, STDIN_FILENO);
        dup2(slave, STDOUT_FILENO);
        dup2(slave, STDERR_FILENO);
        if (slave > STDERR_FILENO)
            close(slave);
        close(errorPipe[0]);
        processGroup = getpid();
        ioctl(STDIN_FILENO, TIOCSPGRP, &processGroup);
        setpgid(0, processGroup);
        if (getuid() != shellUser->pw_uid ||
            geteuid() != shellUser->pw_uid ||
            getgid() != shellUser->pw_gid ||
            getegid() != shellUser->pw_gid)
            _exit(1);

        [[self target] performSelector:@selector(broadcastSize)];
        if (folder == NULL || *folder == '\0' || chdir(folder) != 0) {
            struct passwd *user = getpwuid(shellUser->pw_uid);
            if (user == NULL || user->pw_dir[0] == '\0' ||
                chdir(user->pw_dir) != 0)
                chdir("/");
        }
        if (environment != NULL)
            environ = environment;
        if (login)
            execs0((char *)commandLine);
        else
            execs((char *)commandLine);
        write(errorPipe[1], "Exec failed", 12);
        _exit(221);
    }

    close(errorPipe[1]);
    close(slave);
    [self login];
    zone = [self zone];
    commandLength = strlen(commandLine);
    commandCopy = (char *)NSZoneRealloc(zone, self->command,
                                         commandLength + 1);
    self->command = commandCopy;
    strcpy(commandCopy, commandLine);
    if (read(errorPipe[0], errorBuffer, sizeof(errorBuffer)) == 0) {
        close(errorPipe[0]);
        return 1;
    }
    close(errorPipe[0]);
    return 0;
}

- (void)kill
{
    if (pid != -1) {
        kill(pid, SIGKILL);
        if (pty[0] == '/') {
            [self logout];
            close([self fd]);
            pty[0] = 0;
        }
    }
}

- (void)invalidate
{
    if (invalidated == 0) {
        invalidated = 1;
        [self kill];
        [activeShells removeObject:self];
        free(command);
    }
}

- (void)dealloc
{
    [self invalidate];
    [super dealloc];
}

@end
